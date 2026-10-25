#!/usr/bin/env bash
# PreToolUse hook on Bash matching `git commit`. Scans the staged index for
# secret-shaped strings (PEM bodies, vendor tokens, AWS keys) via gitleaks
# and denies the commit if any are found.
#
# Why this hook exists alongside lefthook: lefthook's pre-commit hook is
# only triggered when a `.git/hooks/pre-commit` symlink is installed in
# the working repo (lefthook install). In Soleur's bare-repo + worktree
# topology, fresh worktrees do NOT inherit the hook from the bare repo
# unless `lefthook install` is re-run per worktree. The "Secret-scanning
# floor (#3121)" gate defined in lefthook.yml therefore never fires for
# many local commits — CI catches the leak only at push time. This
# PreToolUse hook closes the gap at the Bash-tool boundary, runs
# regardless of .git/hooks/ state, and cannot be bypassed by
# `git commit --no-verify`.
#
# Source rule: terraform-show-json leak incident (2026-05-25 learning).
# Routing: relies on the same `.gitleaks.toml` and gitleaks binary that
# lefthook would have used — no rule duplication.
#
# Hook stdin: JSON payload from Claude Code with tool_name + tool_input.
# Hook stdout: JSON {hookSpecificOutput: {hookEventName, permissionDecision, permissionDecisionReason}}.
# Hook exit code: 0 (JSON output controls the gate). An internal error is a DENY with exit 0 (the exit latch, below), for a
# plain commit as for a simulated one; only a failure before the traps are installed (hook-input parsing, the cheap gate)
# still exits 1. The simulation library's canonical fixture-dir guard exits 2, so a simulated commit with a TMPDIR it would
# refuse (/dev, /proc, /sys, a `..`) is denied up front (cause temp-dir); a plain commit never looks at that shape.
#
# Fail-open conditions (the hook allows the commit + emits a warn):
#   - gitleaks binary not installed on PATH          (bypass "gitleaks not installed")
#   - gitleaks on PATH but cannot run, e.g. an unpinned version-manager shim
#                                                    (bypass "gitleaks unrunnable (rc=N)")
#   - a RUNNABLE gitleaks exits non-zero with no report — plausibly transient
#                                                    (bypass "gitleaks exit=N, empty report")
#   - No repository to scan: not inside a git work tree, or no .gitleaks.toml at
#     a resolved root (per root; a command naming a root without one still scans the rest)
# These are operator-environment issues, not secret-leak signals — the
# user should fix their tooling but a missing binary should not block
# every commit. CI re-scans on every push as the load-bearing gate.
# NOT among them, in either mode: a gitleaks run that scanned NOTHING. git writing to stderr while gitleaks reads the diff
# (a bad diff.* or core.abbrev value) makes it log "stderr is not empty" and exit 0 (or 1) with an empty report; that log
# line, or any ERR line, DENIES (scan-error), core.bigFileThreshold is pinned to its default, and a repository git cannot
# read at all (every git call dies on a bad config value) DENIES instead of reading as "not a repository" (CTO row 48).
# The unrunnable case is split out because it is PERMANENT and machine-wide
# (#8266): folded into the "transient" branch it silently bypassed every
# commit on such a host under a reason that said otherwise.
#
# A `bypass` row is not proof the commit landed: where lefthook runs, its own
# `gitleaks-staged` step can still block the same commit (and, with an
# unrunnable gitleaks, fail it — see #8271).
#
# THE WOULD-BE INDEX (#10696, ADR-296). This hook runs BEFORE the Bash command it guards, so for a command that stages
# AND commits (`git add -A && git commit`, `git commit -a`, `git commit -am`, `git commit -- <path>`) the index
# on disk does not yet hold what the commit will record. When the command's own staging is visible to the
# walker (lib/commit-target-roots.sh sets CTR_COMMIT_STAGES), lib/commit-index-sim.sh copies the real index to
# a temp file inside a 0700 directory this hook allocates, replays the staging onto the COPY (exact replay of
# the literal `git add` words when the directory is proven, else the superset `git add -A`), exports the copy
# plus a quarantined object directory, and scan_root runs inside that window. ONE 30 s deadline covers the whole
# simulation and the scan; the replay adds, the scan's diff / check-attr / cat-file calls and both gitleaks calls run
# under it (expiry DENIES; it never bypasses). With a proven directory only the root that directory belongs to is
# simulated; every other root is scanned against its real index. Nothing in the real index content, listing or git
# directory and nothing in the working tree is written (the mtime of an existing object may be refreshed). A plain
# `git commit -m x` is lexed where perl exists but needs no simulation: no new git call.
#
#   Situation                                                           Result
#   a finding in the would-be index                                     DENY, rule id git-commit-secret-scan, row
#                                                                       text mode=<exact|superset> cause=finding
#   a staged path that does not exist (git's own trusted error)         DENY cause=pathspec-missing
#   any other replay failure                                            rebuild from a fresh copy with the superset
#   failed superset, force-add with no literal path or in a directory
#   the command does not prove, temp dir / index copy / ':' in the
#   objects path, deadline or gitleaks timeout (sim-timeout), gitleaks
#   error, check-attr failure, an unexpected error or an exit without a
#   decision (internal-error), config-transforming staging or an
#   environment outside the allowlist (config-refused), content from
#   outside the working tree (stage-unsimulable)                        DENY, rule id
#                                                                       git-commit-secret-scan-sim-deny, row text
#                                                                       mode=<plan, or none> cause=...; the repair
#                                                                       is chosen from the command's staging style
#   sim library or walker missing, unreadable, mismatched or truncated DENY every strict commit (lib repair; rule id
#                                                                       git-commit-secret-scan-undeterminable)
#   an inline git alias definition (-c alias.*, --config-env=alias.*,  DENY (undeterminable target, with or without staging)
#   GIT_CONFIG_KEY_n / GIT_CONFIG_PARAMETERS, an earlier git config
#   alias write in the same call)
#   perl absent and the command is more than one simple commit, or     DENY (tooling)
#   perl absent and more than 500 staged -diff files
#
# The unexpected-error denies (the ERR trap and the exit latch) hold from the line where the traps are installed (right
# after the cheap non-commit gate), for a plain commit too (CTO row 55); a failure before it still exits 1 (non-blocking).
# The read-only prepare calls and sim_recovery's git calls are not under the deadline.
#
# NAMED RESIDUALS (the sim scans the working tree as it is NOW; the contract, the cause table and every residual
# are indexed once, with their reasons, in knowledge-base/engineering/architecture/decisions/ADR-296-*.md):
#   - what an EARLIER command in the same call changes is not seen: a producer, `sed -i`, `prettier --write`, an edit
#     of .gitignore, config or attributes, a `git mv` out of a path-keyed allowlist, a `git stash pop`;
#   - a script or wrapper that runs `git add` inside, and user-config aliases (an INLINE alias is a deny);
#   - the sim scans RAW bytes (clean filters are pinned off): a clean filter / Git LFS may record other bytes;
#   - checkout, stash, read-tree, cherry-pick, merge, revert, am, restore, mv and rm take the superset, which scans
#     the working tree as it is now;
#   - a concealed commit word (`git com""mit`, `c=commit; git $c`) passes the outer gate after a staging command;
#   - other tools that stage (an IDE), a configured core.fsmonitor daemon (not started by the sim), a SIGKILL that
#     leaves a 0700 temp directory (the next simulation sweeps marker-bearing ones older than 60 minutes), and a
#     harness that sends no payload cwd (Devin): a bare `git add a && git commit` takes the superset there, while
#     `cd /abs && ...` and a shared absolute `-C` still prove the directory.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

if [ -f "$PROJECT_DIR/.claude/hooks/lib/incidents.sh" ]; then
  # shellcheck disable=SC1091
  . "$PROJECT_DIR/.claude/hooks/lib/incidents.sh" || true
fi
emit() { command -v emit_incident >/dev/null 2>&1 && emit_incident "$@" || true; }

# State the exit latch and the ledger rows read. hook_done is set by allow / deny / the signal handlers; latch_on says
# the hook must not end without a decision (it is on from the first gate on, and follows sim_on once that is known);
# plan_mode is the plan's mode for the ledger (none until cis_plan has run).
hook_done=0; latch_on=0; sim_on=0; plan_mode=none
report_file=""; nodiff_dir=""; nodiff_report=""; sim_dir=""

allow() {
  hook_done=1
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
  exit 0
}

# sim_split_advice — the retry that works for THIS command's own staging style (CTO row 34). "Run git add as its own
# call" has no `git add` to run for `commit -a` or a pathspec commit, and the translation changes meaning for a
# pathspec (a plain commit after `git add x` records everything already staged, not only x).
sim_split_advice() {
  if [ "${CTR_COMMIT_ALL:-0}" -eq 1 ]; then
    printf '%s' "run 'git add -u' (or 'git add <paths>') as its own call, then run the commit again WITHOUT -a (-a / -p / --all stage by themselves)"
  elif [ "${_CTR_PATHSMODE:-0}" -eq 1 ] || [ -n "${CTR_COMMIT_PATHS[*]-}" ]; then
    printf '%s' "run 'git add <paths>' as its own call, check that 'git diff --cached --name-only' lists exactly those files, then run the commit WITHOUT the paths (a plain commit records what is staged)"
  else
    printf '%s' "run 'git add <paths>' as its own call, then run the commit as a second call"
  fi
}

# _san <text> [cap] — a file or directory name, a config key or any other command-sourced text as it may appear in a
# deny reason: every control (Cc: C0, DEL, C1), format (Cf: bidi overrides and isolates, LRM/RLM, ALM, zero-width
# characters, the soft hyphen, the BOM, the Unicode tag block an LLM reads as hidden text), line and paragraph separator
# (Zl, Zp), private-use (Co) and unassigned (Cn) character becomes '?', and so do the invisible code points outside those
# categories (the combining grapheme joiner U+034F, the Hangul fillers U+115F U+1160 U+3164 U+FFA0, the variation selectors
# U+FE00-FE0F and U+E0100-E01EF); the text is capped (default 160 characters).
_SAN_JQ='gsub("[\\p{Cc}\\p{Cf}\\p{Zl}\\p{Zp}\\p{Co}\\p{Cn}\\x{034F}\\x{115F}-\\x{1160}\\x{3164}\\x{FFA0}\\x{FE00}-\\x{FE0F}\\x{E0100}-\\x{E01EF}]"; "?")'
_san() {
  printf '%s' "$1" | jq -Rrs --argjson cap "${2:-160}" "$_SAN_JQ | .[0:\$cap]" 2>/dev/null || printf '%s' '(unprintable text)'
}

# sim_recovery <root> <first finding file> — the recovery text for a finding in a WOULD-BE index (#10696), chosen from
# facts, not from the shape of the command: does the command act in this root (else the hook cannot tell which repository
# the add and commit are meant for), is the file already staged in the REAL index, is it tracked, and why the superset
# was used. The real repository is read with the sim variables unset.
sim_recovery() {
  local root="$1" f="$2" state=untracked named=0 r tgt="" cause="" root_s tgt_s lead
  local g=(env -u GIT_INDEX_FILE -u GIT_OBJECT_DIRECTORY -u GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_LITERAL_PATHSPECS=1 GIT_OPTIONAL_LOCKS=0 git -c core.fsmonitor=false -C "$root")
  if [ -n "$f" ]; then
    if [ -n "$("${g[@]}" diff --cached --name-only -- "$f" 2>/dev/null)" ]; then state=staged
    elif "${g[@]}" cat-file -e "HEAD:$f" 2>/dev/null; then state=tracked
    fi
  fi
  # CTR_ROOTS holds every repository a -C or cd in the command names, including one named by a NON-commit segment
  # (`git -C W log -1 && git add -A && git commit` acts in the shell's directory, not in W). A root is "named" only when
  # nothing else is named or it is one of those; the first named root is offered as the target, never as a bare `cd`.
  if [ "${#CTR_ROOTS[@]}" -eq 0 ]; then named=1; fi
  for r in ${CTR_ROOTS[@]+"${CTR_ROOTS[@]}"}; do if [ "$r" = "$root" ]; then named=1; fi; done
  tgt="${CTR_ROOTS[0]-}"
  root_s=$(_san "$root"); tgt_s=$(_san "$tgt")
  if [ "${CIS_MODE:-}" = superset ]; then
    case "${CIS_WHY:-}" in
      inexact-word) cause=" The simulation used a full 'git add -A' because a word of the staging command cannot be replayed literally (for example a glob, a variable, an option or a launcher): write literal paths (git add clean.txt) and the scan covers only those." ;;
      unproven-dir|dir-not-root) cause=" The simulation used a full 'git add -A' because the hook could not prove which directory the command stages in (for example a relative cd or -C, an unquoted ';' or '|' or an expansion (\$x, \$(...)) in the command text, a second directory, or no payload cwd): start the command with 'cd /abs/path &&' or put the same '-C /abs/path' on every git add and on the commit, or run the git add as its own call." ;;
      opaque|loop) cause=" The simulation used a full 'git add -A' because the command stages in a way the hook cannot replay (a loop or function, or a verb such as stash, merge, checkout or cherry-pick): run that loop or verb ITSELF as its own call first, then 'git add <paths>' as its own call, then the commit." ;;
      replay-failed) cause=" The simulation used a full 'git add -A' because replaying the command's own git add failed${CIS_ERR:+ (git said: $CIS_ERR)}: fix that add (a path that is ignored needs -f, a missing path needs creating), or run it as its own call first." ;;
    esac
  fi
  lead="The default action is to scrub the secrets — never commit-then-rotate."
  if [ "$named" -eq 0 ]; then
    printf '%s' "$lead This command also names ${tgt_s}, and ${root_s} is scanned because the shell sits there; the hook cannot tell which repository the git add and the git commit act in. If they are meant for ${tgt_s}: put '-C ${tgt_s}' on BOTH the git add and the git commit (a separate 'cd' call is safe only when no bare git call in the command is meant for ${root_s}). If they are meant for ${root_s}: scrub the file there.${cause}"
    return 0
  fi
  case "$state" in
    staged)
      printf '%s' "$lead The file is already staged in ${root_s}. Recovery: (1) run 'git restore --staged <path>' as its OWN call (chained with the commit it is not simulated and the commit is denied again); (2) scrub the secret bytes in place; (3) re-stage the scrubbed file and retry.${cause}" ;;
    tracked)
      printf '%s' "$lead The file is TRACKED and changed, and this command's own staging would record it. Recovery: scrub the secret bytes in place (do not delete a tracked file; a .gitignore entry does not help for a tracked file), then run the same command again.${cause}" ;;
    *)
      printf '%s' "$lead The file is untracked and this command's own staging would add it. Recovery: scrub the secret bytes, or delete the file, or add it to .gitignore; or stage only the intended files in a separate call: $(sim_split_advice).${cause}" ;;
  esac
}

# deny <reason> [rule id] [ledger row text]. A finding keeps the rule id git-commit-secret-scan; under a would-be index
# (CIS_ACTIVE=1) its row carries the plan mode and cause=finding. Only a simulation FAILURE is the sim-deny rule id
# (sim_deny), so a counter keyed on the base id still counts every leak denial.
deny() {
  local reason="$1" rule="${2:-git-commit-secret-scan}" row="${3-}"
  hook_done=1
  if [ "${CIS_ACTIVE:-0}" -eq 1 ]; then
    : "${row:=mode=${plan_mode} cause=finding}"
  fi
  emit "$rule" deny "${row:-git-commit-secret-scan: $reason}"
  jq -nc --arg r "$reason" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

# shellcheck source=lib/hook-input.sh
# FAIL-HARD (no `|| true`): a fail-soft source leaves hook_parse_input undefined
# and the hook dies at the call, letting the tool proceed (#7164 defect 2).
source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-input.sh"

# The source above is fail-hard, but 12 of the 20 hooks run `set -uo pipefail`
# WITHOUT -e. There a missing helper makes hook_parse_input return 127, `!`
# inverts that to true, the response functions are 127 too, and the hook reaches
# `exit 0` — a clean pass-through with no row and no prompt, which is defect 2
# reintroduced by a broken deploy. Assert it explicitly instead of relying on -e.
if ! declare -f hook_parse_input >/dev/null 2>&1; then
  echo "[git-commit-secret-scan] hook-input helper missing — guards did NOT run for this call" >&2
  exit 0
fi

payload="$(cat)"
__HI_RAW="$payload"
# ADR-156: hook stdin is model-controlled. A non-string field is surfaced,
# never coerced — this hook never ran eval, but `jq -r` renders an array
# across lines, which matches none of its guards, so the payload would have
# slipped every gate below (#7164). ADR-157: it asks instead.
if ! hook_parse_input "$__HI_RAW"; then
  hook_input_report "git-commit-secret-scan"
  hook_input_should_ask && { hook_input_emit_ask "git-commit-secret-scan"; exit 0; }
  exit 0
fi

tool_kind="$HOOK_TOOL_KIND"

# Only fire on Bash (or its Devin kind twin, exec — #8205).
[ "$tool_kind" = "Bash" ] || allow

command="$HOOK_CMD"; strict_match=1  # the strict test below lowers it to 0
[ -n "$command" ] || allow

# Match `git commit` as a command-leading verb. Tolerates:
#   - bare `git commit ...`
#   - chained: `... && git commit ...`, `... ; git commit ...`, `... | git commit ...`
#   - leading whitespace
# Rejects:
#   - substring matches inside other args (e.g. `echo "git commit example"`)
#   - other git subcommands (git-commit-tree, git commit-graph)
#
# The regex anchors `git commit` after one of: start-of-string, whitespace
# after a chain operator (`&&`, `||`, `;`, `|`), or `$(`. Then requires a
# trailing space-or-end so `commit-tree` / `commit-graph` are not matched.
if ! grep -qE '(^|[[:space:]]|&&|\|\||;|\$\()[[:space:]]*git[[:space:]]+commit([[:space:]]|$)' <<<"$command"; then
  strict_match=0
fi

# STRICT detection above only sees `git commit` with nothing between the two words, so
# `git -C <dir> commit`, a launcher (`timeout 5 git -C <dir> commit`), quoting (`git "-C" ...`)
# and `git -c k=v commit` were allowed before anything was scanned (#10609). A command that
# lacks either word cannot be a commit; every other one goes to the command lexer, which
# CONFIRMS a commit record (a quoted mention of the words is not a commit).
# An inline alias definition (`-c alias.ci=commit ci`, `--config-env=alias.ci=V`, GIT_CONFIG_KEY_0=alias.ci) can hide a
# commit behind a word that is not `commit` (CTO row 49), so a command carrying alias / GIT_CONFIG_ / --config-env text
# goes to the lexer even without the word `commit`; the lexer decides on argv, so a message that says `alias.` is not refused.
if [ "$strict_match" -eq 0 ]; then
  if [[ "$command" != *git* ]]; then
    allow
  elif [[ "$command" != *commit* ]]; then
    # (Without perl there is no lexer to ask: such a call is allowed rather than denied as "tooling", so that
    # `git config alias.st status` is not blocked on a minimal container; the alias-hidden commit is a perl-less residual.)
    case "$command" in
      *[Aa][Ll][Ii][Aa][Ss].*|*GIT_CONFIG_*|*--config-env*) command -v perl >/dev/null 2>&1 || allow ;;
      *) allow ;;
    esac
  fi
fi

# From here the hook may not end without a decision. TRAPS: EXIT cleans up and turns a hook that ended without calling
# allow or deny (a `set -u` abort, an unguarded failure) into a DENY, for a plain commit too (CTO row
# 55: an exit 1 is NON-blocking, i.e. an unscanned commit); INT and TERM must END the hook - bash runs a signal handler
# and then CONTINUES the script (measured), so the handlers `exit` (130 / 143, marked done: a killed hook prints nothing)
# and the exit runs the EXIT trap; ERR (with `set -E`, so it also fires in functions) denies instead of letting errexit
# exit 1. NOT covered: an arithmetic-expansion error (`$((08))`), which bash does not treat as fatal - it abandons the
# enclosing command and carries on, with no ERR and no non-zero exit - so no arithmetic in this hook may take command-sourced
# text unchecked (the GIT_CONFIG_COUNT clamp reads decimal and caps its length). A failure BEFORE this line (hook-input parsing, the cheap gate) still exits 1; a SIGKILL can still leave a 0700
# temp directory behind (the next simulation sweeps marker-bearing ones older than 60 minutes).
latch_on=1

# _rm_owned_dir <dir> <basename prefix> — remove a temp directory THIS hook made, after a cheap local guard (CTO row 53):
# absolute, not a symlink, owned by us, carrying the prefix mktemp gave it. The shape of TMPDIR itself never blocks a plain
# commit (the canonical assert_fixture_dir exits 2 for /dev/shm/x or a `..`), so this does not call it.
_rm_owned_dir() {
  local d="${1-}" pre="${2-}"
  case "$d" in /|//|/.|'') return 0 ;; /*) : ;; *) return 0 ;; esac
  case "${d##*/}" in "$pre"*) : ;; *) return 0 ;; esac
  if [ -L "$d" ] || [ ! -d "$d" ] || [ ! -O "$d" ]; then return 0; fi
  rm -rf "$d" 2>/dev/null || true
  return 0
}

cleanup() {
  if [ -n "$report_file" ]; then rm -f "$report_file" 2>/dev/null || true; fi
  if [ -n "$nodiff_report" ]; then rm -f "$nodiff_report" 2>/dev/null || true; fi
  _rm_owned_dir "$nodiff_dir" gitleaks-nodiff-
  _rm_owned_dir "$sim_dir" commit-sim-
  return 0
}

# hook_error_repair — the repair for a deny that comes from the hook's OWN error (an unexpected failure, an exit without a
# decision): the split-the-staging text only helps a simulated commit (CTO row 55).
hook_error_repair() {
  if [ "$sim_on" -eq 1 ]; then
    sim_split_advice
  else
    printf '%s' "run the same commit again; if it fails again, report this hook error (the exit status and line above) instead of working around it"
  fi
}

# sim_deny <cause> <reason> — a deny that is about the SIMULATION (it could not be built or bounded, the staging was
# refused, a scan could not complete), not about a finding. One distinct rule id; the row carries only enumerated words:
# mode is the PLAN's mode (none until cis_plan has run, as for config-refused and stage-unsimulable), not the attempt's.
sim_deny() {
  cis_unexport 2>/dev/null || true
  deny "$2" git-commit-secret-scan-sim-deny "mode=${plan_mode} cause=$1"
}

sim_timeout_deny() {  # <root>
  sim_deny sim-timeout "BLOCKED: the gitleaks scan of the simulated index of $(_san "$1") did not finish within the simulation's time limit (30 s for the whole simulation and the scan together; a very large working tree can overrun it every time, a busy machine can too), so the content the commit would record was NOT scanned and the commit is blocked. Repair: $(sim_split_advice) (the scan then reads the real index)."
}
sim_scan_error() {  # <root> <what>
  sim_deny scan-error "BLOCKED: the scan of the simulated index of $(_san "$1") did not complete ($2), so the content the commit would record was NOT scanned and the commit is blocked. gitleaks failing to finish is a tooling fault: run 'gitleaks version' and 'gitleaks git --pre-commit --staged' in the repository to see why, fix it, then run the same command again (splitting the staging from the commit does not repair a gitleaks that cannot finish)."
}

# ERRORS. An unguarded failing command under `set -e` exits 1, which the harness treats as NON-blocking: the commit
# would land unscanned. In a subshell or `$( )` the trap only fails that substitution (exit with its status): the
# parent's own ERR then denies.
set -E
sim_err_trap() {
  local rc=$? line="${1-?}"
  [ "${BASH_SUBSHELL:-0}" -eq 0 ] || exit "$rc"
  trap - ERR
  if [ "$latch_on" -eq 1 ]; then
    sim_deny internal-error "BLOCKED: the scan of the commit hit an unexpected error (exit $rc near line $line of the hook), so the content it would record was NOT scanned and the commit is blocked. Repair: $(hook_error_repair)."
  fi
}

# The exit latch (see TRAPS above).
hook_exit() {
  local rc=$?
  trap - EXIT ERR INT TERM
  if [ "$hook_done" -eq 0 ] && [ "$latch_on" -eq 1 ]; then
    hook_done=1
    emit git-commit-secret-scan-sim-deny deny "mode=${plan_mode} cause=internal-error"
    jq -nc --arg r "BLOCKED: the hook ended without reaching a decision (exit $rc), so the content the commit would record was NOT scanned and the commit is blocked. Repair: $(hook_error_repair)." \
      '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}' || true
    cleanup
    exit 0
  fi
  cleanup
  return 0
}

# tmp_fail — a report temp file could not be created: a deny in either mode (the staged content cannot be scanned).
tmp_fail() {
  if [ "$sim_on" -eq 1 ]; then
    sim_deny temp-dir "BLOCKED: the commit's own staging could not be scanned (a temporary file could not be created), so the content it would record was NOT scanned and the commit is blocked. Repair: free space in TMPDIR (or fix a TMPDIR that names a missing directory), then run the same command again; if it keeps failing, $(sim_split_advice)."
  fi
  deny "BLOCKED: the staged index could not be scanned (a temporary file for the scan could not be created), so the commit is blocked. Repair: free space in TMPDIR (or fix a TMPDIR that names a missing directory), then run the same command again."
}
trap hook_exit EXIT
trap 'hook_done=1; exit 130' INT
trap 'hook_done=1; exit 143' TERM
trap 'sim_err_trap $LINENO' ERR

# Sourced fail-soft ON PURPOSE and checked explicitly: a missing or broken library must
# DENY a commit (it is the safety core), never skip the scan. See deny_undeterminable.
# Sourced only past the cheap test above, so the common non-git Bash call never pays for it.
ctr_ok=0
case "${BASH_SOURCE[0]}" in */*) ctr_dir="${BASH_SOURCE[0]%/*}" ;; *) ctr_dir=. ;; esac
ctr_lib="$ctr_dir/lib/commit-target-roots.sh"
cis_lib="$ctr_dir/lib/commit-index-sim.sh"
# The sim library is sourced in the SAME checked `if` (CTO row 13), and both libraries must announce the API they
# were written against (CTO row 32): a lazy source, or an older walker beside a newer hook, would silently skip
# the would-be-index scan, so a missing, broken or mismatched one denies every strict commit.
# shellcheck source=lib/commit-target-roots.sh
# shellcheck source=lib/commit-index-sim.sh
if [ -r "$ctr_lib" ] && . "$ctr_lib" 2>/dev/null && declare -f ctr_collect >/dev/null 2>&1 \
   && declare -f ctr_resolve_roots >/dev/null 2>&1 \
   && [ "${CTR_STAGE_API:-0}" = 1 ] \
   && [ -r "$cis_lib" ] && . "$cis_lib" 2>/dev/null && declare -f cis_build >/dev/null 2>&1 \
   && [ "${CIS_API:-0}" = 1 ]; then
  ctr_ok=1
fi

# Which commands go to the lexer: every loose-only match, and every strict match where perl exists (CTO row 22: a
# pre-filter is an open-world list of the forms that matter, and one ~13 ms lex per commit closes it). Without perl
# the lexer cannot run and a commit that needs it is denied, so only a strict match that carries a directory-affecting
# token or a same-command staging form (ctr_wants_lex) goes there and a plain `git commit -m x` still works.
need_lex=0
if [ "$ctr_ok" -eq 1 ]; then
  if [ "$strict_match" -eq 0 ] || command -v perl >/dev/null 2>&1 || ctr_wants_lex "$command"; then need_lex=1; fi
elif [ "$strict_match" -eq 0 ]; then
  # Library unavailable: this is a broken install, so lean toward the deny. A loose-only match
  # is kept when it carries an option-bearing `git -...` form or any quoting / expansion
  # character a launcher or a quoted global option could hide behind; a plain
  # `git log --grep=commit` is left alone.
  loose_re='git[[:space:]]+-'
  case "$command" in
    *'"'*|*"'"*|*'\'*|*'('*|*'`'*|*'$'*) : ;;
    *) [[ "$command" =~ $loose_re ]] || allow ;;
  esac
fi

# Ambient git env must not redirect any probe or scan below: an inherited GIT_DIR outranks
# `git -C` and would point every one of them at the wrong repository.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
      GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE

lex_state=skipped
if [ "$need_lex" -eq 1 ]; then
  ctr_collect "$command"
  lex_state="$CTR_LEX_STATE"
  if [ "$lex_state" = ok ]; then
    # A loose-only match that the lexer shows is not a commit is not a commit.
    if [ "$CTR_COMMIT_SEEN" -eq 0 ]; then
      # No commit record: a loose-only match is not a commit. A STRICT textual match with no
      # record is quoted prose (or something the walker cannot see): keep the cwd roots,
      # drop the target refusals, which belong to a command that commits.
      if [ "$strict_match" -eq 0 ]; then allow; fi
      CTR_BAD=()
    fi
    # Before the undeterminable check below: a missing target in a command that creates
    # paths is itself a refusal that ctr_resolve_roots records.
    ctr_resolve_roots
  fi
fi

# At this point: the tool call is a `git commit` (or a chain containing one).
# Run gitleaks against the staged index of every repository it targets. Fail-open if
# gitleaks is missing.

GL_REMEDIATION="CI pins gitleaks 8.24.2 — install that version or pin it in your version manager (e.g. 'mise use gitleaks@8.24.2')."

if ! command -v gitleaks >/dev/null 2>&1; then
  echo "[git-commit-secret-scan] WARN: gitleaks not installed — skipping scan. $GL_REMEDIATION" >&2
  emit git-commit-secret-scan bypass "gitleaks not installed"
  allow
fi

# Placed AFTER the cheap repo/config guards on purpose: the probe spawns
# timeout+gitleaks and costs ~400 ms (measured). Above them it paid that on
# EVERY `git commit`, including ones outside a repo or in a repo with no
# .gitleaks.toml — calls that exit without ever scanning. It is memoized and runs
# at most once per hook call, in the main shell (a $(...) would lose the memo flag
# and could not allow/exit the hook).
#
# RESOLVABLE IS NOT RUNNABLE (#8266). `command -v` only proves the name resolves;
# an unpinned mise shim resolves and exits non-zero on every call. Probe by
# running the tool. Bound it with timeout when one exists — stock macOS has
# neither `timeout` nor `gtimeout`, and a missing bound must never be misread as
# a broken gitleaks, or every macOS commit would skip the scan.
gl_probed=0
gitleaks_runnable() {
  [ "$gl_probed" -eq 0 ] || return 0
  gl_probed=1
  local gl_to=() gl_retry_to=() gl_probe_rc=0 gl_probe_err
  if command -v timeout >/dev/null 2>&1; then gl_to=(timeout 10)
  elif command -v gtimeout >/dev/null 2>&1; then gl_to=(gtimeout 10); fi
  # `${a[@]+"${a[@]}"}`, not `"${a[@]}"`: bash 3.2 (stock macOS /bin/bash) treats an
  # EMPTY array as unbound under `set -u`, which is exactly the no-timeout host.
  gl_probe_err="$( { ${gl_to[@]+"${gl_to[@]}"} gitleaks version >/dev/null; } 2>&1 )" || gl_probe_rc=$?
  # A BOUND EXPIRY IS NOT AN UNRUNNABLE BINARY. `timeout` reports 124 when the bound
  # expires (137 when it escalates to SIGKILL) — that is a statement about host LOAD,
  # not about gitleaks. Treating it as "unrunnable" bypasses the scan on a host whose
  # only problem is that it is busy, and prints a remediation (install/pin 8.24.2)
  # that cannot fix it. This matters here specifically: #8231 exists to run these
  # suites in PARALLEL, and concurrency is what expires a 10 s bound. Retry once at a
  # wider bound before concluding anything.
  case "$gl_probe_rc" in
    124|137)
      if command -v timeout >/dev/null 2>&1; then gl_retry_to=(timeout 60)
      elif command -v gtimeout >/dev/null 2>&1; then gl_retry_to=(gtimeout 60); fi
      gl_probe_rc=0
      gl_probe_err="$( { ${gl_retry_to[@]+"${gl_retry_to[@]}"} gitleaks version >/dev/null; } 2>&1 )" || gl_probe_rc=$?
      case "$gl_probe_rc" in
        124|137)
          printf '[git-commit-secret-scan] WARN: the gitleaks probe timed out twice (rc=%s) — this host is too loaded to verify the scanner, so the staged content was NOT scanned. This is a load condition, not a broken install; re-run the commit when the machine is quieter.\n' \
            "$gl_probe_rc" >&2
          emit git-commit-secret-scan-probe-timeout bypass "gitleaks probe timed out (rc=$gl_probe_rc)"
          allow
          ;;
      esac
      ;;
  esac
  if [ "$gl_probe_rc" -ne 0 ]; then
    printf '[git-commit-secret-scan] WARN: gitleaks is on PATH but cannot run (rc=%s, %q) — skipping scan. %s\n' \
      "$gl_probe_rc" "${gl_probe_err%%$'\n'*}" "$GL_REMEDIATION" >&2
    emit git-commit-secret-scan bypass "gitleaks unrunnable (rc=$gl_probe_rc)"
    allow
  fi
}

# A target the scan cannot determine is a DENY, never a skip (#10609): an unscanned
# commit is the failure this hook exists to prevent, the repair is one extra tool call,
# and an `ask` has no answerer in a headless pipeline (ADR-165), so it would degenerate
# into the same skip. There is deliberately NO override variable: an override is the skip.
# text_advice — the same retry as sim_split_advice, for the denies where the lexer never produced facts (it is missing or
# failed): the command TEXT decides (`-a` / `--all`, a `--` pathspec) because no walker fact exists.
text_advice() {
  local re_a='commit[^;&|]*[[:space:]]-[A-Za-z]*a' re_all='commit[^;&|]*[[:space:]]--all([[:space:]]|$)' re_dd='commit.*[[:space:]]--([[:space:]]|$)'
  if [[ "$command" =~ $re_a || "$command" =~ $re_all ]]; then
    printf '%s' "run 'git add -u' (or 'git add <paths>') in one call, then run the commit again WITHOUT -a in the next"
  elif [[ "$command" =~ $re_dd ]]; then
    printf '%s' "run 'git add <paths>' in one call, check that 'git diff --cached --name-only' lists exactly those files, then run the commit WITHOUT the paths in the next"
  else
    printf '%s' "run git add in one call, the commit in the next"
  fi
}

deny_undeterminable() {
  local kind="$1" cause="$2" repair
  case "$kind" in
    lib) repair="No rewrite of the command can help: the scanner's helper library is damaged. Check 'git diff -- .claude/hooks/lib' for uncommitted edits first (restoring discards them), then restore it from the repository root with: git checkout -- .claude/hooks/lib  and retry." ;;
    tooling) repair="Fix the tooling: check that perl is on PATH and that plugins/soleur/hooks/lib/shell-argv.pl is intact, then retry. Without perl only one simple line is read: git commit with -m '<one line, no \$, backtick or backslash>', a bare -m word, -F <file>, --amend, --no-edit, -v, -s, --signoff, --no-verify, -n or -q. These are NOT read without perl: --allow-empty, -S, --author=, -nm, 2>&1, | tail, && push, a comment, a heredoc or \$(...) message. For a long message write it to a file in its own call, then run 'git commit -F <file>'; a command that names a directory, or stages and commits in one command, needs the lexer: $(text_advice)." ;;
    alias) repair="Define no git alias in the command that commits: an inline alias (-c alias.*, --config-env=alias.*, a GIT_CONFIG_* variable) or a 'git config alias.*' written earlier in the same call can run a commit or any staging under a name the hook does not read. Run the commit as a plain 'git commit ...' with no alias in the call; if you need an alias, configure it in its own earlier call and spell out the real verb here." ;;
    launcher) repair="Run the git commit (and the git add) as separate plain calls, outside the launcher or command string: not inside unshare, chroot, nsenter, env -S, su -c, sg -c, ssh, flock -c, watch, script or a similar wrapper. For example 'git add <paths>' in one call, then 'git commit -m ...' in the next." ;;
    create) repair="Run the command that creates the path as its own call first, then run the commit as a second call (a path that does not exist yet cannot be scanned in the same command)." ;;
    parse) repair="Rewrite the command so the shell can parse it (balanced quotes, terminated substitutions and heredocs; a stray quote or backtick inside an unquoted message is the usual cause), or run 'git -C /abs/path commit ...' as its own call, or $(text_advice)." ;;
    bound) repair="Split the command: run the long or deeply nested parts as separate calls, then 'git -C /abs/path commit ...' on its own ($(text_advice))." ;;
    *) repair="Repair: name the repository as a literal absolute path in the same command — 'git -C /abs/path commit ...' or 'cd /abs/path && git commit ...' (list the paths with 'git worktree list'). Or, where the harness reports the shell's cwd to hooks (not Devin), run 'cd <absolute worktree path>' as its own command first and then 'git commit' with no cd or -C in it. Forms that cannot be resolved and are denied: a variable (\$VAR), \$(...), backticks, ~, a glob, 'cd -', GIT_DIR= / GIT_WORK_TREE= / GIT_INDEX_FILE= (inline, after env, or via export), --git-dir / --work-tree, a path that does not exist yet in a command that creates it, and a string held in a variable that is run by bash -c or by eval. Do not route around this hook with a script or an alias: that skips the scan too." ;;
  esac
  deny "BLOCKED: cannot determine which repository this git commit may target ($(_san "$cause" 600)), so the staged content was NOT scanned and the commit is blocked. ${repair}" git-commit-secret-scan-undeterminable
}

undeterminable=""; undet_kind=target
if [ "$ctr_ok" -ne 1 ]; then
  undet_kind=lib
  undeterminable="a helper library (.claude/hooks/lib/commit-target-roots.sh or commit-index-sim.sh) is missing or unreadable"
elif [ "$lex_state" = unavailable ]; then
  undet_kind="$CTR_LEX_KIND"
  undeterminable="$CTR_LEX_WHY"
elif [ "$lex_state" = ok ] && [ "${#CTR_BAD[@]}" -gt 0 ]; then
  # List up to three causes: one repair round-trip is cheaper than three.
  undeterminable="${CTR_BAD[0]}"
  case "${CTR_BAD[0]}" in *"does not exist yet"*) undet_kind=create ;; esac
  [ "${#CTR_BAD[@]}" -gt 1 ] && undeterminable="$undeterminable; ${CTR_BAD[1]}"
  [ "${#CTR_BAD[@]}" -gt 2 ] && undeterminable="$undeterminable; ${CTR_BAD[2]}"
  [ "${#CTR_BAD[@]}" -gt 3 ] && undeterminable="$undeterminable; and $(( ${#CTR_BAD[@]} - 3 )) more"
  if [ "$undet_kind" = target ]; then
    case "$undeterminable" in
      *"defines a git alias"*) undet_kind="alias" ;;
      *"changes the root or namespace"*|*"env -S runs"*|*"runs a command string"*) undet_kind="launcher" ;;
    esac
  fi
fi
if [ -n "$undeterminable" ]; then
  # Honour an unrunnable or timed-out gitleaks first: that is an environment fault and
  # keeps its existing allow + bypass row, exactly as a plain commit would.
  gitleaks_runnable
  deny_undeterminable "$undet_kind" "$undeterminable"
fi

# The repositories to scan: every literal target named in the command, UNIONED with the
# cwd-derived root and the payload-cwd root. The fallback roots are always included: a -C
# can belong to a non-commit segment (`git -C A status; git commit`), and the separate-cd
# repair relies on the payload cwd following the shell. Trade-off accepted: an unrelated
# staged secret in the cwd repo can deny a commit aimed elsewhere; the deny reason names the
# root that held the finding.
scan_roots=()
add_root() {
  local r="$1" x
  [ -n "$r" ] || return 0
  for x in ${scan_roots[@]+"${scan_roots[@]}"}; do if [ "$x" = "$r" ]; then return 0; fi; done
  scan_roots+=("$r")
}
# add_root_of <dir | empty for the hook's own cwd> — add the toplevel of a directory. A rev-parse that fails for any reason but
# "not a git repository" / "a bare root has no work tree" is a repository git cannot read (a bad diff.*, core.abbrev or other
# config value makes every git call die): it is recorded in repo_err and DENIED below, never read as "not a repository"
# (that is an allow, i.e. an unscanned commit).
repo_err="${CTR_ROOT_ERR-}"
add_root_of() {
  local out rc=0
  if [ -n "${1-}" ]; then out="$(git -C "$1" rev-parse --show-toplevel 2>&1)" || rc=$?
  else out="$(git rev-parse --show-toplevel 2>&1)" || rc=$?; fi
  if [ "$rc" -eq 0 ]; then
    add_root "${out##*$'\n'}"
  else
    case "$out" in
      *"not a git repository"*|*"must be run in a work tree"*) : ;;
      *) if [ -z "$repo_err" ]; then repo_err="${out%%$'\n'*}"; fi ;;
    esac
  fi
  return 0
}
for _r in ${CTR_ROOTS[@]+"${CTR_ROOTS[@]}"}; do add_root "$_r"; done
add_root_of ""
if [ -n "${HOOK_CWD-}" ] && [ -d "$HOOK_CWD" ]; then add_root_of "$HOOK_CWD"; fi
if [ -n "$repo_err" ]; then
  sim_deny scan-error "BLOCKED: git cannot read the repository this commit may target (git said: $(_san "$repo_err" 200)), so nothing was scanned and the commit is blocked. Repair: find the setting git complains about with 'git config --show-origin --list' (a bad diff.*, core.abbrev or similar value, local or global), fix it, then run the same command again."
fi

if [ "${#scan_roots[@]}" -eq 0 ]; then
  # No repository to scan: the legacy reasons, in the legacy order. (`git rev-parse
  # --is-inside-work-tree` exits 0 and prints "false" at a core.bare=true root, so this
  # is the .gitleaks.toml row there — a `git commit` in a bare root cannot stage anything.)
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    emit git-commit-secret-scan bypass "not inside git work tree"
    allow
  fi
  echo "[git-commit-secret-scan] WARN: .gitleaks.toml not found at repo root — skipping scan." >&2
  emit git-commit-secret-scan bypass ".gitleaks.toml absent"
  allow
fi

toml_roots=()
for _r in "${scan_roots[@]}"; do
  if [ -f "$_r/.gitleaks.toml" ]; then
    toml_roots+=("$_r")
  else
    echo "[git-commit-secret-scan] WARN: .gitleaks.toml not found at repo root $_r — skipping scan of it." >&2
    emit git-commit-secret-scan bypass ".gitleaks.toml absent"
  fi
done
if [ "${#toml_roots[@]}" -eq 0 ]; then
  allow
fi

gitleaks_runnable

# Run the same scan lefthook.yml configures, against the staged index only.
# `--exit-code 1` makes gitleaks return non-zero on findings.
# `--redact` ensures the matched secret bytes do not appear in stderr.
# `--no-banner` reduces output noise.
# `--report-format json` + `--report-path` capture findings for the deny
# reason without printing the raw secrets to the hook's stdout/stderr.
#
# sim_on: this command stages AND commits, so it is scanned through the would-be index (the exit latch has been on since
# the traps were installed and covers both kinds of commit).
sim_on=0
if [ "$lex_state" = ok ] && [ "$CTR_COMMIT_SEEN" -eq 1 ] && [ "${CTR_COMMIT_STAGES:-0}" -eq 1 ]; then sim_on=1; fi

# The report temp files are allocated under the same rule as everything else: a failed mktemp must DENY (it used to
# slide out as exit 1, which is non-blocking). A relative TMPDIR is made absolute ONCE, here, for every mktemp below
# (the gitleaks call cd's into the repository, so a relative report path would resolve somewhere else). Everything the
# hook writes is private (umask 077). The SHAPE of TMPDIR blocks nothing for a plain commit (CTO row 53: main's behaviour
# on `git commit --allow-empty` with TMPDIR=/dev/shm/x); a simulated one denies, because the simulation library's
# canonical directory guard exits 2 on a synthetic-fs path or a `..` component.
case "${TMPDIR:-}" in ''|/*) : ;; *) TMPDIR="$PWD/$TMPDIR"; export TMPDIR ;; esac
umask 077
if [ "$sim_on" -eq 1 ]; then
  case "${TMPDIR:-/tmp}" in
    */../*|*/..|/proc/*|/sys/*|/dev/*|/|//|/.)
      sim_deny temp-dir "BLOCKED: the commit's own staging could not be simulated (TMPDIR is $(_san "${TMPDIR:-/tmp}" 200), which the simulation refuses: it is in /dev, /proc or /sys, or has a '..' component), so the content it would record was NOT scanned and the commit is blocked. Repair: point TMPDIR at an ordinary directory (for example 'export TMPDIR=/tmp'), then run the same command again; or $(sim_split_advice)." ;;
  esac
fi
report_file="$(mktemp -t gitleaks-staged-XXXXXX.json)" || tmp_fail
nodiff_report="$(mktemp -t gitleaks-nodiff-XXXXXX.json)" || tmp_fail

# scan_root <root> — scan ONE repository's staged index. It returns 0 when the root is
# clean or its scan failed transiently (a bypass row is emitted and the loop moves on) and
# NEVER allows or exits the hook: only a finding denies. All state is per call, so a root
# that errors cannot leak into, or end the scan of, the next.
# sim_bound — gl_bound for the NEXT call: in a would-be-index scan the perl bound with the time left (a deny when none is
# left), else none. Reads scan_root's repo_root and sets its gl_bound (bash dynamic scope).
sim_bound() {
  gl_bound=()
  if [ "${CIS_ACTIVE:-0}" -eq 1 ]; then
    if ! cis_bound_argv; then sim_timeout_deny "$repo_root"; fi
    gl_bound=("${CIS_BOUND_ARGV[@]}")
  fi
}

# gl_output_check <root> <gitleaks output> — gitleaks logs an ERR line when it could not do its job, and when git wrote to
# stderr while gitleaks read the diff it logs "stderr is not empty", scans nothing and exits 0 or 1 with an empty report.
# That is a scan that did not happen: a DENY in BOTH modes (CTO row 48), never a bypass.
gl_output_check() {
  local out="$2" line
  case "$out" in
    *"stderr is not empty"*|*" ERR "*)
      line="${out#*ERR }"; line="${line%%$'\n'*}"
      sim_deny scan-error "BLOCKED: gitleaks could not read the staged changes of $(_san "$1") (it reported: $(_san "$line" 200)), so nothing was scanned and the commit is blocked. Repair: find the setting git complains about with 'git config --show-origin --list' (a bad diff.*, core.abbrev or similar value, local or global), fix it, then run the same command again." ;;
  esac
  return 0
}

# NODIFF_PL — writes the blobs `git cat-file --batch` prints to files named by the paths in a NUL-separated list (argv 1),
# under a destination directory (argv 2). Raw bytes: no work-tree conversion (checkout-index applies working-tree-encoding,
# eol and ident, which hid a UTF-16LE secret). Exit 3 for a blob git could not give, 4 for a short stream, 5 for a name it
# refuses (absolute or with a .. component), 6 when a file could not be written, 7 when the name is already there (two staged
# paths that collide on a case-insensitive file system, or a path equal to the directory's own marker file).
read -r -d '' NODIFF_PL <<'PL' || true
use File::Path qw(make_path); use File::Basename qw(dirname); my %mk;
my ($nf, $dest) = @ARGV; open(my $fh, '<:raw', $nf) or exit 2; my @names; { local $/ = "\0"; @names = <$fh>; chomp(@names); } close $fh;
binmode STDIN;
for my $n (@names) {
  my $h = <STDIN>; defined $h or exit 4; chomp $h; my ($oid, $type, $size) = split / /, $h;
  ($type // '') eq 'blob' or exit 3;
  my $buf = ''; while (length($buf) < $size) { my $r = read(STDIN, $buf, $size - length($buf), length($buf)); $r or exit 4 }
  my $nl = <STDIN>;
  ($n =~ m{^/} or $n =~ m{(^|/)\.\.(/|$)} or $n =~ m{\0}) and exit 5;
  my $path = "$dest/$n"; my $d = dirname($path); make_path($d) unless $mk{$d}++; -e $path and exit 7; open(my $o, '>:raw', $path) or exit 6; print $o $buf; close($o) or exit 6;
}
PL

scan_root() {
  local repo_root="$1" _p _a _v _m _sm _dm _so _do _st ca_rc co_rc gl_nodiff=() gl_nd_oids=() nd_ps=() nd_dirs=() raw_paths=() raw_oids=() raw_i gl_bound=() gl_cfg_n scan_rc=0 nodiff_rc nd_count nd_files nd_i repo_s first_file
  local findings_count=0 findings_summary="" reason gl_out="" gl_drv="" gl_drv_n=0 _nd_fix
  : > "$report_file"; : > "$nodiff_report"

  # GITATTRIBUTE BYPASS GUARD. `gitleaks git` reads a PATCH, so a path marked
  # `-diff` renders as `Binary files a/x and b/x differ` with no `+` lines and
  # scans clean — measured: `.git/info/attributes` containing `creds.txt -diff`
  # took a staged AWS key from rc=1/1 finding to rc=0/0 findings. No colour pin
  # closes it, and neither does `core.attributesFile=/dev/null` nor
  # `GIT_ATTR_NOSYSTEM=1` (both measured): those govern the GLOBAL and SYSTEM
  # attributes files, while `.git/info/attributes` is per-repo and always read.
  # This is the same class the colour pin above exists for — ambient local git
  # config silently disarming the scanner — so it is closed here, not documented.
  #
  # `check-attr` discriminates precisely: an explicit `-diff` reports `unset`,
  # while an auto-detected binary (a PNG) reports `unspecified` (measured), so a
  # legitimately-binary staged file is never caught by this.
  # Affected paths are re-scanned from their STAGED blobs with `detect --no-git`,
  # which never consults git's diff machinery at all — the same mechanism
  # code-to-prd.sh's Layer 3 already relies on.
  # ONE batched pass (a per-path `git check-attr` + `sed` cost 83 s at 5,000 paths; the batch costs 43 ms and
  # reports the same value). A failed batch DENIES in a would-be-index scan (a guard that could not run is not a
  # guard) and, on the plain path, leaves no path to re-scan, which is what the old per-path loop also did when
  # its `check-attr` failed (an empty answer is not `unset`).
  ca_rc=0
  # the staged paths and their RAW blob ids (the new side of the index), then one check-attr over them. Both run under the
  # bound in a would-be-index scan; a `diff` attribute other than unspecified or set (that is: -diff, or a driver name,
  # which may be configured binary or textconv) can blind `gitleaks git`, so those paths are re-scanned from raw blobs.
  sim_bound
  ${gl_bound[@]+"${gl_bound[@]}"} git -c core.fsmonitor=false -C "$repo_root" diff --cached --raw -z --no-abbrev --no-renames --diff-filter=ACMRT > "$nodiff_report" 2>/dev/null || ca_rc=$?
  if [ "$ca_rc" -eq 124 ]; then sim_timeout_deny "$repo_root"; fi
  if [ "$ca_rc" -eq 0 ]; then
    set -f
    while IFS= read -r -d '' _m && IFS= read -r -d '' _p; do
      # shellcheck disable=SC2086  # word splitting of the raw record is the point (noglob is on)
      set -- $_m
      case "${2-}" in 160000) continue ;; esac
      raw_paths+=("$_p"); raw_oids+=("${4-}")
    done < "$nodiff_report"
    set +f
    : > "$nodiff_report"
    if (( ${#raw_paths[@]} > 0 )); then
      sim_bound
      printf '%s\0' "${raw_paths[@]}" \
        | ${gl_bound[@]+"${gl_bound[@]}"} git -c core.fsmonitor=false -C "$repo_root" check-attr -z --stdin diff > "$nodiff_report" 2>/dev/null || ca_rc=$?
      if [ "$ca_rc" -eq 124 ]; then sim_timeout_deny "$repo_root"; fi
    fi
  fi
  if [ "$ca_rc" -eq 0 ]; then
    raw_i=0
    # A path is re-scanned when its `diff` attribute is UNSET (-diff), or names a driver that the repository's git config
    # defines as binary, textconv or command (CTO row 51: ONE `git config --get-regexp`, read the first time a named driver
    # appears). A driver defined outside git config behaves as text (a named residual, ADR-296).
    while IFS= read -r -d '' _p && IFS= read -r -d '' _a && IFS= read -r -d '' _v; do
      case "$_v" in
        unspecified|set) : ;;
        unset) gl_nodiff+=("$_p"); gl_nd_oids+=("${raw_oids[$raw_i]-}") ;;
        *)
          if [ "$gl_drv_n" -eq 0 ]; then
            gl_drv_n=1
            gl_drv="$(git -c core.fsmonitor=false -C "$repo_root" config --get-regexp '^diff\..*\.(binary|textconv|command)$' 2>/dev/null)" || gl_drv=""
            gl_drv=$'\n'"$gl_drv"
          fi
          case "$gl_drv" in
            *$'\n'"diff.$_v.binary "*|*$'\n'"diff.$_v.textconv "*|*$'\n'"diff.$_v.command "*|*$'\n'"diff.$_v.binary"|*$'\n'"diff.$_v.textconv"|*$'\n'"diff.$_v.command")
              gl_nodiff+=("$_p"); gl_nd_oids+=("${raw_oids[$raw_i]-}") ;;
          esac ;;
      esac
      raw_i=$((raw_i + 1))
    done < "$nodiff_report"
    # a short or long answer is a guard that did not run
    if [ "$raw_i" -ne "${#raw_paths[@]}" ]; then ca_rc=1; gl_nodiff=(); gl_nd_oids=(); fi
  fi
  if [ "$ca_rc" -ne 0 ]; then
    if [ "${CIS_ACTIVE:-0}" -eq 1 ]; then
      sim_deny check-attr-failed "BLOCKED: the \`-diff\` attribute guard could not run on the simulated index of $(_san "$repo_root"), so the content the commit would record was NOT verified and the commit is blocked. Repair: $(sim_split_advice)."
    fi
    echo "[git-commit-secret-scan] WARN: the \`-diff\` attribute check failed in $repo_root; files carrying a \`-diff\` attribute were NOT re-scanned." >&2
  fi
  : > "$nodiff_report"

  # `gitleaks git --pre-commit --staged` scans only files added to the index
  # (matches the lefthook-staged invocation byte-for-byte). The hook's CWD
  # may not be the repo root, so cd into it first.
  #
  # COLOUR IS PINNED OFF for this invocation. `gitleaks git` runs git itself and
  # inherits the user's config; under color.ui=always or color.diff=always it
  # parses ANSI-wrapped patch lines and reports ZERO findings on a staged key
  # (measured). lefthook.yml's gitleaks-staged step carries the same two pins.
  #
  # BOTH config surfaces must be pinned, not just GIT_CONFIG_COUNT.
  # GIT_CONFIG_PARAMETERS is a SEPARATE source that git reads AFTER the
  # GIT_CONFIG_COUNT list, so it beats the count-list pin outright — and `git -c
  # <anything>` EXPORTS it into every hook git spawns. Measured: with only the
  # count-list pin, `git -c color.diff=always commit` on a staged AWS key scanned
  # rc=0 / 0 findings and the key landed in history; appending the pin to
  # GIT_CONFIG_PARAMETERS restores rc=1 / 1 finding. We APPEND rather than replace
  # so a caller's own `-c` settings survive.
  #
  # Within GIT_CONFIG_COUNT later entries win, so appending is the correct
  # direction there too. But the append is only safe when the caller's count is a
  # shape git AND this clamp agree on: git tolerates a leading space (" 2"), which
  # the clamp below rewrites to 0, so the pin would then OVERWRITE the caller's
  # first two entries rather than follow them. That is safe for the colour pin
  # itself (it still lands, and still wins) and is why the clamp stays.
  #
  # A `-diff` gitattribute defeats colour pinning entirely (it removes the `+`
  # lines rather than decorating them); that is closed separately by the
  # check-attr guard above, not by these two pins.
  #
  # core.fsmonitor is pinned off the same way (CTO row 29): `git config core.fsmonitor <script>` is an ordinary Bash
  # call, and a program that answers with a malformed token made `gitleaks git --staged` return rc 0 on a staged
  # key (measured). In a would-be-index scan gitleaks runs under the bound program: the time left of the ONE total
  # deadline, a TERM-then-KILL of its whole process group, rc 124.
  #
  # core.bigFileThreshold is pinned to git's default for the same reason (CTO row 48): a tiny value makes every staged file
  # "Binary" and gitleaks reports no leaks at exit 0 (measured on 8.24.2 and 8.30.1). And git writing ANYTHING to stderr
  # while gitleaks reads the diff (a bad diff.* / core.abbrev value) makes gitleaks log "stderr is not empty", scan nothing
  # and exit 0 or 1 with an empty report (measured): its output is captured and that signature, or an ERR line, is a scan
  # failure (gl_output_check).
  gl_cfg_n="${GIT_CONFIG_COUNT:-0}"
  case "$gl_cfg_n" in ''|*[!0-9]*) gl_cfg_n=0 ;; esac
  # a count git reads in decimal ("08" is 8): normalised so the arithmetic below cannot abort and the pin lands at the index git reads
  if [ "${#gl_cfg_n}" -gt 6 ]; then gl_cfg_n=0; else gl_cfg_n=$((10#$gl_cfg_n)); fi
  sim_bound
  gl_out="$(
    cd "$repo_root" || exit 1
    env "GIT_CONFIG_COUNT=$((gl_cfg_n + 4))" \
      "GIT_CONFIG_KEY_${gl_cfg_n}=color.ui" "GIT_CONFIG_VALUE_${gl_cfg_n}=never" \
      "GIT_CONFIG_KEY_$((gl_cfg_n + 1))=color.diff" "GIT_CONFIG_VALUE_$((gl_cfg_n + 1))=never" \
      "GIT_CONFIG_KEY_$((gl_cfg_n + 2))=core.fsmonitor" "GIT_CONFIG_VALUE_$((gl_cfg_n + 2))=false" \
      "GIT_CONFIG_KEY_$((gl_cfg_n + 3))=core.bigFileThreshold" "GIT_CONFIG_VALUE_$((gl_cfg_n + 3))=512m" \
      "GIT_CONFIG_PARAMETERS=${GIT_CONFIG_PARAMETERS:+${GIT_CONFIG_PARAMETERS} }'color.ui'='never' 'color.diff'='never' 'core.fsmonitor'='false' 'core.bigFileThreshold'='512m'" \
      ${gl_bound[@]+"${gl_bound[@]}"} \
      gitleaks git --pre-commit --staged --redact --no-banner --no-color --log-level error --exit-code 1 \
        --report-format json --report-path "$report_file" 2>&1
  )" || scan_rc=$?
  # In a would-be-index scan nothing about the content was ever scanned if gitleaks did not finish its job: an exit
  # other than 0 / 1 is an error (124: the bound), and so is a non-zero exit with no report (CTO row 31).
  if [ "${CIS_ACTIVE:-0}" -eq 1 ]; then
    case "$scan_rc" in
      0|1) : ;;
      124) sim_timeout_deny "$repo_root" ;;
      *) sim_scan_error "$repo_root" "gitleaks exited $scan_rc" ;;
    esac
  fi
  gl_output_check "$repo_root" "$gl_out"

  # Re-scan any `-diff` path from its STAGED blob before trusting a clean verdict.
  # `gitleaks git` structurally could not see these (no `+` lines), so "clean" above
  # is not a statement about them. `detect --no-git` reads file CONTENT and never
  # consults git's diff machinery, so no gitattribute can reach it.
  if (( ${#gl_nodiff[@]} > 0 )); then
    nodiff_rc=0; co_rc=0
    # RAW staged blobs, never a checkout: checkout-index converts through working-tree-encoding, eol and ident, which hid
    # a UTF-16LE secret behind `-diff working-tree-encoding=UTF-16LE`. With perl: ONE `cat-file --batch` split into files
    # named by their paths (a per-path fork cost 42 s at 4,000 paths); without perl one `cat-file blob` per path, capped at
    # 500 paths (CTO row 52: above it the per-path forks run for minutes; install perl or split the commit). A blob that
    # could not be read is NOT a clean file. The directory is private (0700, files 0600 under the umask above), made here
    # and marked so a SIGKILLed hook's leftover is swept like a simulation directory.
    if ! command -v perl >/dev/null 2>&1 && [ "${#gl_nodiff[@]}" -gt 500 ]; then
      sim_deny tooling "BLOCKED: ${#gl_nodiff[@]} staged files of $(_san "$repo_root") carry a \`-diff\` attribute or a binary / textconv diff driver, and without perl each one is read back with its own git call (the cap is 500), so those files were NOT scanned and the commit is blocked. Repair: install perl (the scan then reads them in one pass), or split the commit so fewer than 500 such files are staged at once."
    fi
    _rm_owned_dir "$nodiff_dir" gitleaks-nodiff-; nodiff_dir=""
    nodiff_dir="$(mktemp -d -t gitleaks-nodiff-XXXXXX)" || { nodiff_dir=""; tmp_fail; }
    : > "$nodiff_dir/.soleur-sim-marker" || tmp_fail
    printf '%s\0' "${gl_nodiff[@]}" > "$nodiff_report"
    sim_bound
    if command -v perl >/dev/null 2>&1; then
      nd_ps=(0)
      printf '%s\n' "${gl_nd_oids[@]}" \
        | ${gl_bound[@]+"${gl_bound[@]}"} git -c core.fsmonitor=false -C "$repo_root" cat-file --batch 2>/dev/null \
        | perl -e "$NODIFF_PL" "$nodiff_report" "$nodiff_dir" >/dev/null 2>&1 || nd_ps=("${PIPESTATUS[@]}")
      # the bound's expiry (124) wins over the splitter's own short-stream status
      for nd_i in "${nd_ps[@]}"; do
        if [ "$nd_i" -ne 0 ] && [ "$co_rc" -ne 124 ]; then co_rc=$nd_i; fi
      done
    else
      # one mkdir for every directory the paths need (a per-path fork otherwise)
      for _p in "${gl_nodiff[@]}"; do
        case "$_p" in */*) nd_dirs+=("$nodiff_dir/${_p%/*}") ;; esac
      done
      if [ "${#nd_dirs[@]}" -gt 0 ]; then mkdir -p "${nd_dirs[@]}" 2>/dev/null || co_rc=6; fi
      nd_i=0
      if [ "$co_rc" -eq 0 ]; then
        for _p in "${gl_nodiff[@]}"; do
          if [ -e "$nodiff_dir/$_p" ]; then co_rc=7; break; fi
          ${gl_bound[@]+"${gl_bound[@]}"} git -c core.fsmonitor=false -C "$repo_root" cat-file blob "${gl_nd_oids[$nd_i]}" > "$nodiff_dir/$_p" 2>/dev/null || { co_rc=$?; break; }
          nd_i=$((nd_i + 1))
        done
      fi
    fi
    : > "$nodiff_report"
    if [ "$co_rc" -eq 124 ] && [ "${CIS_ACTIVE:-0}" -eq 1 ]; then sim_timeout_deny "$repo_root"; fi
    if [ "$co_rc" -ne 0 ]; then
      if [ "$co_rc" -eq 7 ]; then
        _nd_fix="two staged paths of the re-scan land on one file name here (names that differ only by case on a case-insensitive file system, or a file called .soleur-sim-marker): rename one of them, then run the same command again"
      else
        _nd_fix="check that the repository's objects are readable ('git fsck') and that TMPDIR has free space, then run the same command again"
      fi
      sim_deny scan-error "BLOCKED: the staged blobs of the \`-diff\` files of $(_san "$repo_root") could not all be read back for the re-scan (exit $co_rc), so those files were NOT scanned and the commit is blocked. Repair: ${_nd_fix}."
    fi
    sim_bound
    gl_out="$(${gl_bound[@]+"${gl_bound[@]}"} gitleaks detect --no-git --source "$nodiff_dir" --config "$repo_root/.gitleaks.toml" --redact --no-banner --no-color --log-level error --exit-code 1 \
      --report-format json --report-path "$nodiff_report" 2>&1)" || nodiff_rc=$?
    if [ "${CIS_ACTIVE:-0}" -eq 1 ]; then
      case "$nodiff_rc" in
        0|1) : ;;
        124) sim_timeout_deny "$repo_root" ;;
        *) sim_scan_error "$repo_root" "the \`-diff\` re-scan exited $nodiff_rc" ;;
      esac
    fi
    gl_output_check "$repo_root" "$gl_out"
    if [ "$nodiff_rc" -eq 1 ] && [ -s "$nodiff_report" ] && grep -q '"RuleID"' "$nodiff_report" 2>/dev/null; then
      nd_count="$(jq -r 'length' "$nodiff_report" 2>/dev/null || echo 0)"
      nd_files=""; nd_i=0
      for _p in "${gl_nodiff[@]}"; do
        nd_i=$((nd_i + 1))
        if [ "$nd_i" -le 5 ]; then nd_files="${nd_files}$(_san "$_p"), "; fi
      done
      if [ "$nd_i" -gt 5 ]; then nd_files="${nd_files}and $((nd_i - 5)) more, "; fi
      deny "BLOCKED: gitleaks found ${nd_count} secret-shaped string(s) in staged file(s) of $(_san "$repo_root") carrying a \`-diff\` gitattribute or a diff driver: ${nd_files%, }. A \`-diff\` attribute (or a driver configured binary or textconv) makes git emit \"Binary files … differ\" with no added lines, so the normal staged scan sees NOTHING in these files — they were re-scanned from their raw staged blobs. Recovery: (1) scrub the secret bytes (never commit-then-rotate); (2) if the \`diff\` attribute is not deliberate, remove it from .gitattributes / .git/info/attributes."
    fi
    if [ "$nodiff_rc" -eq 1 ] && [ "${CIS_ACTIVE:-0}" -eq 1 ]; then sim_scan_error "$repo_root" "the \`-diff\` re-scan reported a failure and no findings"; fi
    if [ "$nodiff_rc" -ne 0 ] && [ "$nodiff_rc" -ne 1 ]; then
      echo "[git-commit-secret-scan] WARN: the \`-diff\` re-scan exited $nodiff_rc without a findings report; those paths were NOT verified." >&2
      emit git-commit-secret-scan-nodiff-rescan-failed bypass "-diff re-scan exit=$nodiff_rc, empty report"
    fi
  fi

  if [ "$scan_rc" -eq 0 ]; then
    return 0
  fi

  # scan_rc != 0 → findings present (or gitleaks crashed). Build a redacted
  # deny reason that names the files + rule IDs but never the secret body.
  if [ -s "$report_file" ]; then
    findings_count="$(jq -r 'length' "$report_file" 2>/dev/null || echo 0)"
    # Each finding: {RuleID, File, StartLine}. Cap at 5 to keep the deny
    # reason terse; the operator can re-run gitleaks locally to see the rest.
    findings_summary="$(jq -r '
      [.[] | "\(.File | '"$_SAN_JQ"' | .[0:120]):\(.StartLine) (\(.RuleID | '"$_SAN_JQ"' | .[0:60]))"] | .[0:5] | join("; ")
    ' "$report_file" 2>/dev/null || echo "")"
  fi

  if [ "$findings_count" = "0" ] || [ -z "$findings_summary" ]; then
    # gitleaks exited non-zero but the report file is empty/missing — likely
    # a transient gitleaks error rather than a real finding. Fail-open with
    # a warn so a broken binary doesn't block every commit. (Not in a would-be-index scan: there the
    # content was never scanned, and the environment is ours, not the operator's.)
    if [ "${CIS_ACTIVE:-0}" -eq 1 ]; then sim_scan_error "$repo_root" "gitleaks exited $scan_rc with no findings report"; fi
    echo "[git-commit-secret-scan] WARN: gitleaks exited $scan_rc but produced no findings report for $repo_root; continuing with the remaining roots. Run 'gitleaks git --pre-commit --staged' there to diagnose." >&2
    emit git-commit-secret-scan bypass "gitleaks exit=$scan_rc, empty report"
    return 0
  fi

  repo_s=$(_san "$repo_root")
  if [ "${CIS_ACTIVE:-0}" -eq 1 ]; then
    # the recovery is built from facts about THIS finding and THIS command (sim_recovery), not cut from a fixed text
    first_file=""
    first_file=$(jq -r '.[0].File // ""' "$report_file" 2>/dev/null | head -n 1) || first_file=""
    reason="BLOCKED: gitleaks found ${findings_count} secret-shaped string(s) in the staged index of ${repo_s} (the index this command would record). Locations: ${findings_summary}. $(sim_recovery "$repo_root" "$first_file")"
  else
    reason="BLOCKED: gitleaks found ${findings_count} secret-shaped string(s) in the staged index of ${repo_s}. Locations: ${findings_summary}. The default action is to scrub the secrets — never commit-then-rotate. Recovery: (1) unstage the offending file(s) in ${repo_s} with 'git restore --staged <path>'; (2) redact the secret bytes in place; (3) re-stage and retry. If the staged content is a captured-real fixture from 'terraform show -json' or similar, strip the '.variables' block — terraform-show-json embeds sensitive HCL variables verbatim regardless of sensitive=true. See knowledge-base/project/learnings/security-issues/2026-05-25-terraform-show-json-leaks-sensitive-variables-into-fixtures.md."
  fi
  deny "$reason"
}

# ---- the would-be index (#10696) -------------------------------------------------------------------
# A command that stages AND commits (`git add -A && git commit`, `commit -a`, `commit -- <path>`) is scanned
# against the index the commit WILL record, built by commit-index-sim.sh on a temp copy: nothing in the real
# index, object store, git directory or working tree is touched. A plain `git commit -m x` reaches none of this.
if [ "$sim_on" -ne 1 ]; then
  for _r in "${toml_roots[@]}"; do
    scan_root "$_r"
  done
  allow
fi

# From here the policy: refuse, allocate, build per root, scan inside the export window, unexport, clean.
if [ "${CTR_STAGE_UNSIMULABLE:-0}" -eq 1 ]; then
  sim_deny stage-unsimulable "BLOCKED: this command puts content in the index that comes from outside the working tree (git update-index --add / --cacheinfo / --index-info, or git apply --index / --cached / --3way), so what the commit would record cannot be scanned and the commit is blocked. Repair: run that staging command as its own call, then run the commit as a second call (the scan then reads the real index)."
fi
if [ "${CTR_STAGE_REFUSE:-0}" -eq 1 ]; then
  sim_deny config-refused "BLOCKED: the commit's own staging cannot be simulated safely ($(_san "${CTR_STAGE_REFUSE_WHY}" 400)), so the content it would record was NOT scanned and the commit is blocked. Repair: $(sim_split_advice) (the scan then reads the real index)."
fi

# Best effort, never a verdict: a SIGKILLed hook leaves its 0700 directory (RAM on a tmpfs TMPDIR). Remove only
# directories that are ours by prefix (commit-sim-* and the -diff re-scan's gitleaks-nodiff-*), owner, MARKER and age
# (older than 60 minutes: a simulation is time-bounded), never following a symlink (CTO row 45).
sim_sweep() {
  local d
  command -v find >/dev/null 2>&1 || return 0
  while IFS= read -r -d '' d; do
    case "$d" in /*) : ;; *) continue ;; esac
    if [ -L "$d" ] || [ ! -f "$d/.soleur-sim-marker" ] || [ -L "$d/.soleur-sim-marker" ]; then continue; fi
    assert_fixture_dir "$d"
    rm -rf "$d" 2>/dev/null || true
  done < <(find "${TMPDIR:-/tmp}" -mindepth 1 -maxdepth 1 -type d \( -name 'commit-sim-*' -o -name 'gitleaks-nodiff-*' \) -user "$(id -u)" -mmin +60 -print0 2>/dev/null || true)
  return 0
}
sim_sweep

if ! sim_dir="$(mktemp -d -t commit-sim-XXXXXX)"; then
  sim_dir=""
  sim_deny temp-dir "BLOCKED: the commit's own staging could not be simulated (a temporary directory could not be created), so the content it would record was NOT scanned and the commit is blocked. Repair: $(sim_split_advice)."
fi
assert_fixture_dir "$sim_dir"
: > "$sim_dir/.soleur-sim-marker" 2>/dev/null || true

cis_clock_start

# The payload's own .cwd (not HOOK_CWD, which falls back to CLAUDE_PROJECT_DIR / PWD and is never empty): the
# exact replay trusts only a directory the payload itself names.
payload_cwd=""
payload_cwd="$(printf '%s' "$__HI_RAW" | jq -r 'if (.cwd | type) == "string" then .cwd else "" end' 2>/dev/null)" || payload_cwd=""
# ONE plan for the whole command (CTO row 33). Proof of the command's directory (exact) means the staging lands in ONE
# repository, the toplevel of CIS_DIR: that root is simulated, and every other root is a fallback root (the hook's cwd,
# the payload cwd) the command cannot stage into, so it is scanned against its real index. Without proof every root is
# simulated with the superset, which is what keeps `git -C A status; git add -A && git commit` closed.
cis_plan "$payload_cwd"
# The plan is read ONCE: cis_build overwrites CIS_MODE when a replay falls back to the superset, and that must not turn
# a fallback-only root into a simulated one.
plan_mode="$CIS_MODE"; plan_top="$CIS_TOP"

sim_i=0
for _r in "${toml_roots[@]}"; do
  if [ "$plan_mode" = exact ] && [ "$_r" != "$plan_top" ]; then
    scan_root "$_r"
    continue
  fi
  sim_i=$((sim_i + 1))
  sim_work="$sim_dir/r$sim_i"
  mkdir -m 700 "$sim_work" 2>/dev/null || sim_deny temp-dir "BLOCKED: the commit's own staging could not be simulated (a temporary directory could not be created), so the content it would record was NOT scanned and the commit is blocked. Repair: $(sim_split_advice)."
  sim_brc=0
  cis_build "$_r" "$payload_cwd" "$sim_work" || sim_brc=$?
  case "$sim_brc" in
    0) : ;;
    *)
      case "$CIS_WHY" in
        pathspec-missing)
          sim_deny "$CIS_WHY" "BLOCKED: this command stages a path that does not exist${CIS_ERR:+ (git said: $CIS_ERR)}, so what it would record cannot be scanned and the commit is blocked. Repair: create the file in an earlier call or fix the spelling, then run the same command." ;;
        force-nonliteral)
          sim_deny "$CIS_WHY" "BLOCKED: this command force-adds (git add -f) a path the hook cannot read literally (a variable, a glob, paths from stdin or --pathspec-from-file), so the ignored content it would record was NOT scanned and the commit is blocked. Repair: run the force-add as its own call, then run the commit in the next call." ;;
        force-unproven-dir)
          sim_deny "$CIS_WHY" "BLOCKED: this command force-adds (git add -f), but the directory the add runs in cannot be proven (for example a relative cd or -C, an unquoted ';' or '|' or an expansion (\$x, \$(...)) in the command text such as a heredoc commit message, or a second directory), so the ignored content it would record was NOT scanned and the commit is blocked. Repair: put 'cd /abs/path &&' or '-C /abs/path' on the add and keep expansions out of the command, or run the force-add as its own call, then run the commit in the next call." ;;
        colon-path)
          sim_deny "$CIS_WHY" "BLOCKED: this repository's object directory path contains a ':' (git cannot name it in GIT_ALTERNATE_OBJECT_DIRECTORIES), so the commit's own staging cannot be simulated in this checkout and the commit is blocked. Repair: stage in its own call ($(sim_split_advice)) so the scan reads the real index, or move the checkout to a path without ':'." ;;
        sim-timeout)
          sim_deny "$CIS_WHY" "BLOCKED: the commit's own staging could not be simulated within its time limit${CIS_ERR:+ ($CIS_ERR)}, so the content it would record was NOT scanned and the commit is blocked. The limit is 30 s for the whole simulation and the scan together: a very large working tree can overrun it every time, and a busy machine can too. Repair: $(sim_split_advice) (the scan then reads the real index)." ;;
        *)
          sim_deny "${CIS_WHY:-superset-failed}" "BLOCKED: the commit's own staging could not be simulated (${CIS_WHY:-failure}${CIS_ERR:+: $CIS_ERR}), so the content it would record was NOT scanned and the commit is blocked. Repair: $(sim_split_advice) (the scan then reads the real index)." ;;
      esac ;;
  esac
  scan_root "$_r"
  cis_unexport
  assert_fixture_dir "$sim_work"; rm -rf "$sim_work" 2>/dev/null || true
done
allow
