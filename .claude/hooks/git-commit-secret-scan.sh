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
# Hook exit code: 0 always (JSON output controls the gate).
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
# The unrunnable case is split out because it is PERMANENT and machine-wide
# (#8266): folded into the "transient" branch it silently bypassed every
# commit on such a host under a reason that said otherwise.
#
# A `bypass` row is not proof the commit landed: where lefthook runs, its own
# `gitleaks-staged` step can still block the same commit (and, with an
# unrunnable gitleaks, fail it — see #8271).
#
# THE WOULD-BE INDEX (#10696). This hook runs BEFORE the Bash command it guards, so for a command that stages
# AND commits (`git add -A && git commit`, `git commit -a`, `git commit -am`, `git commit -- <path>`) the index
# on disk does not yet hold what the commit will record. When the command's own staging is visible to the
# walker (lib/commit-target-roots.sh sets CTR_COMMIT_STAGES), lib/commit-index-sim.sh copies the real index to
# a temp file inside a 0700 directory this hook allocates, replays the staging onto the COPY (exact replay of
# the literal `git add` words when the directory is proven, else the superset `git add -A`), exports the copy
# plus a quarantined object directory, and scan_root runs unchanged inside that window. Nothing in the real
# index, real object store, real git directory or working tree is touched. A plain `git commit -m x` reaches
# none of this (no simulation, no new git call). gitleaks resolves to a generated wrapper first on PATH in sim
# mode: it applies the time left of ONE 30 s deadline and, on expiry, the hook DENIES (expiry never bypasses).
#
#   Situation                                                          Result
#   benign missing pathspec (trusted git error), no earlier producer   superset scanned; bypass row
#                                                                      git-commit-secret-scan-sim-failed
#                                                                      (cause pathspec-missing); allow if clean
#   missing pathspec and the same command may create it                DENY (the `create` repair)
#   any other replay failure                                           rebuild with the superset
#   failed superset / non-literal force-add / temp dir, index copy or
#   ':' in the objects path / deadline or gitleaks timeout / no bound
#   tool / batched check-attr failure / config-transforming staging
#   argument (-c core.*, filter.*, --namespace, GIT_* prefix ...)      DENY (rule id
#                                                                      git-commit-secret-scan-sim-deny, row text
#                                                                      mode=... cause=...); repair: run git add as
#                                                                      its own call, then commit
#   sim library missing or unreadable                                  DENY every strict commit (lib repair)
#
# NAMED RESIDUALS (covered by one follow-up issue; the sim scans the working tree as it is NOW):
#   - a script or wrapper that runs `git add` inside (the walker sees only the command's own argv);
#   - content created or changed EARLIER in the same command is denied only when a producer is detected;
#     `sed -i` / `prettier --write` before `commit -a` or `add -u` is invisible (pre-execution state);
#   - a positional pathspec AFTER a `-m "..."` (`git commit -m x tracked.json`) never reaches the walker;
#   - the sim scans RAW bytes (clean filters are pinned off): a clean filter / Git LFS may record other bytes;
#   - content a verb brings from OUTSIDE the working tree (`apply --index`, `cherry-pick -n`, `stash pop`,
#     `merge`, `checkout <ref> --`) is not covered: those verbs force the superset, which scans the working tree;
#   - other tools that stage (an IDE, a git alias), and a configured core.fsmonitor daemon (not started by the sim).

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

if [ -f "$PROJECT_DIR/.claude/hooks/lib/incidents.sh" ]; then
  # shellcheck disable=SC1091
  . "$PROJECT_DIR/.claude/hooks/lib/incidents.sh" || true
fi
emit() { command -v emit_incident >/dev/null 2>&1 && emit_incident "$@" || true; }

allow() {
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
  exit 0
}

# sim_recovery — the recovery text for a finding in a WOULD-BE index (#10696). The file is not staged yet, so
# the separate-call advice ('git restore --staged <path>') would loop; the advice that works differs for a
# file the command would ADD and for a tracked file it would take through -a or a pathspec.
sim_recovery() {
  local why=""
  if [ "${CIS_MODE:-}" = superset ] && [ -n "${CIS_WHY:-}" ]; then
    why=" The simulation used a full 'git add -A' (${CIS_WHY}), so unrelated untracked files are scanned too."
  fi
  if [ "${CTR_COMMIT_ALL:-0}" -eq 1 ] || [ "${#CTR_COMMIT_PATHS[@]}" -gt 0 ]; then
    if [ "${#CTR_ADD_META[@]}" -eq 0 ] && [ "${CIS_MODE:-}" = exact ]; then
      printf '%s' "The finding is in a TRACKED file that this commit's own -a / pathspec would record; nothing is staged yet. Recovery: scrub the secret bytes in place (never commit-then-rotate); a .gitignore entry does not help for a tracked file. Then retry.${why}"
      return 0
    fi
  fi
  printf '%s' "Nothing is staged yet: this same command's own git add / commit flags would stage the file. Recovery: scrub the secret bytes (never commit-then-rotate), or delete the file, or add it to .gitignore; or stage only the intended paths in a separate call (git add <path>) and run the commit in the next call.${why}"
}

# deny <reason> [rule id] [ledger row text]. Under a would-be index (CIS_ACTIVE=1) a finding is a SIM deny: the
# reason is cut at the stable anchor that opens the staged-index recovery advice and the sim advice replaces it,
# and the ledger row is a distinct rule id carrying only enumerated words (mode and cause), never git's text.
deny() {
  local reason="$1" rule="${2:-git-commit-secret-scan}" row="${3-}" anchor='The default action is to scrub'
  if [ "${CIS_ACTIVE:-0}" -eq 1 ]; then
    rule=git-commit-secret-scan-sim-deny
    case "$reason" in
      *"$anchor"*) reason="${reason%%"$anchor"*}$(sim_recovery)" ;;
    esac
    : "${row:=mode=${CIS_MODE:-unknown} cause=finding}"
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
if [ "$strict_match" -eq 0 ] && { [[ "$command" != *git* ]] || [[ "$command" != *commit* ]]; }; then
  allow
fi

# Sourced fail-soft ON PURPOSE and checked explicitly: a missing or broken library must
# DENY a commit (it is the safety core), never skip the scan. See deny_undeterminable.
# Sourced only past the cheap test above, so the common non-git Bash call never pays for it.
ctr_ok=0
case "${BASH_SOURCE[0]}" in */*) ctr_dir="${BASH_SOURCE[0]%/*}" ;; *) ctr_dir=. ;; esac
ctr_lib="$ctr_dir/lib/commit-target-roots.sh"
cis_lib="$ctr_dir/lib/commit-index-sim.sh"
# The sim library is sourced in the SAME checked `if` (CTO row 13): a lazy source that fails open would let a
# broken library silently skip the would-be-index scan, so a missing or broken one denies every strict commit.
# shellcheck source=lib/commit-target-roots.sh
# shellcheck source=lib/commit-index-sim.sh
if [ -r "$ctr_lib" ] && . "$ctr_lib" 2>/dev/null && declare -f ctr_collect >/dev/null 2>&1 \
   && [ -r "$cis_lib" ] && . "$cis_lib" 2>/dev/null && declare -f cis_build >/dev/null 2>&1; then
  ctr_ok=1
fi

# Which commands go to the lexer: every loose-only match (always), and a strict match only
# when it carries a directory-affecting token or a same-command staging form (#10696), so a plain
# `git commit -m x` never spawns perl.
need_lex=0
if [ "$ctr_ok" -eq 1 ]; then
  if [ "$strict_match" -eq 0 ] || ctr_wants_lex "$command"; then need_lex=1; fi
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
deny_undeterminable() {
  local kind="$1" cause="$2" repair
  case "$kind" in
    lib) repair="No rewrite of the command can help: the scanner's helper library is damaged. From the repository root restore it with: git checkout -- .claude/hooks/lib  and retry." ;;
    tooling) repair="Fix the tooling: check that perl is on PATH and that plugins/soleur/hooks/lib/shell-argv.pl is intact, then retry. Until then a plain 'git commit' with no cd, -C, env or same-command staging still works; anything that names a directory, or stages and commits in one command, needs the command lexer: run git add in one call, the commit in the next." ;;
    create) repair="Run the command that creates the path as its own call first, then run the commit as a second call (a path that does not exist yet cannot be scanned in the same command)." ;;
    parse) repair="Rewrite the command so the shell can parse it (balanced quotes, terminated substitutions and heredocs; a stray quote or backtick inside an unquoted message is the usual cause), or run 'git -C /abs/path commit ...' as its own call, or run git add in one call and the commit in the next." ;;
    bound) repair="Split the command: run the long or deeply nested parts as separate calls, then 'git -C /abs/path commit ...' on its own (git add in one call, the commit in the next)." ;;
    *) repair="Repair: name the repository as a literal absolute path in the same command — 'git -C /abs/path commit ...' or 'cd /abs/path && git commit ...' (list the paths with 'git worktree list'). Or, where the harness reports the shell's cwd to hooks (not Devin), run 'cd <absolute worktree path>' as its own command first and then 'git commit' with no cd or -C in it. Forms that cannot be resolved and are denied: a variable (\$VAR), \$(...), backticks, ~, a glob, 'cd -', GIT_DIR= / GIT_WORK_TREE= / GIT_INDEX_FILE= (inline, after env, or via export), --git-dir / --work-tree, a path that does not exist yet in a command that creates it, and a string held in a variable that is run by bash -c or by eval. Do not route around this hook with a script or an alias: that skips the scan too." ;;
  esac
  deny "BLOCKED: cannot determine which repository this git commit may target (${cause}), so the staged content was NOT scanned and the commit is blocked. ${repair}" git-commit-secret-scan-undeterminable
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
for _r in ${CTR_ROOTS[@]+"${CTR_ROOTS[@]}"}; do add_root "$_r"; done
add_root "$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
if [ -n "${HOOK_CWD-}" ] && [ -d "$HOOK_CWD" ]; then
  add_root "$(git -C "$HOOK_CWD" rev-parse --show-toplevel 2>/dev/null || echo "")"
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
# TRAPS. EXIT cleans up; INT and TERM must END the hook: bash runs a signal handler and then CONTINUES the script
# (measured), so a handler that only cleans up would delete the sim directory mid-run and let the hook finish in
# `allow`. The handlers therefore `exit` (130 / 143), and the exit runs the EXIT trap. The sim directory holds
# blobs of working-tree files (possibly secrets): it is removed only when it is non-empty, a real directory (not
# a symlink), named commit-sim-*, and owned by the caller.
report_file=""; nodiff_dir=""; nodiff_report=""; sim_dir=""
# The canonical fixture-dir guard (byte-identical to plugins/soleur/test/test-helpers.sh; asserted by
# plugins/soleur/test/fixture-dir-operand-assert.test.sh). It runs only on a temp path this hook just allocated
# (always absolute), before a recursive remove or a write, so a path that came back empty or relative cannot
# retarget the remove at the caller's directory. #7652
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}
cleanup() {
  if [ -n "$report_file" ]; then rm -f "$report_file" 2>/dev/null || true; fi
  if [ -n "$nodiff_report" ]; then rm -f "$nodiff_report" 2>/dev/null || true; fi
  if [ -n "$nodiff_dir" ]; then
    assert_fixture_dir "$nodiff_dir"
    rm -rf "$nodiff_dir" 2>/dev/null || true
  fi
  if [ -n "$sim_dir" ] && [ -d "$sim_dir" ] && [ ! -L "$sim_dir" ] && [ -O "$sim_dir" ]; then
    case "$sim_dir" in
      */commit-sim-*)
        assert_fixture_dir "$sim_dir"
        rm -rf "$sim_dir" 2>/dev/null || true ;;
    esac
  fi
  return 0
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
report_file="$(mktemp -t gitleaks-staged-XXXXXX.json)"
nodiff_dir="$(mktemp -d -t gitleaks-nodiff-XXXXXX)"
nodiff_report="$(mktemp -t gitleaks-nodiff-XXXXXX.json)"

# sim_deny <cause> <reason> — a deny that is about the SIMULATION (it could not be built or bounded, or the
# staging was refused), not about a finding. One distinct rule id; the row carries only enumerated words.
sim_deny() {
  cis_unexport 2>/dev/null || true
  CIS_ACTIVE=0
  deny "$2" git-commit-secret-scan-sim-deny "mode=${CIS_MODE:-unknown} cause=$1"
}

# scan_root <root> — scan ONE repository's staged index. It returns 0 when the root is
# clean or its scan failed transiently (a bypass row is emitted and the loop moves on) and
# NEVER allows or exits the hook: only a finding denies. All state is per call, so a root
# that errors cannot leak into, or end the scan of, the next.
scan_root() {
  local repo_root="$1" _p _a _v ca_rc gl_nodiff=() gl_cfg_n scan_rc=0 nodiff_rc nd_count nd_files
  local findings_count=0 findings_summary="" reason
  : > "$report_file"; : > "$nodiff_report"
  rm -rf "$nodiff_dir"; mkdir -p "$nodiff_dir"

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
  # reports the same value). A batch failure falls back to the old per-path loop on the plain path; in a
  # would-be-index scan it DENIES (a guard that could not run is not a guard).
  ca_rc=0
  git -C "$repo_root" diff --cached --name-only -z --diff-filter=ACMR 2>/dev/null \
    | git -C "$repo_root" check-attr -z --stdin diff > "$report_file" 2>/dev/null || ca_rc=$?
  if [ "$ca_rc" -eq 0 ]; then
    while IFS= read -r -d '' _p && IFS= read -r -d '' _a && IFS= read -r -d '' _v; do
      [ -n "$_p" ] || continue
      if [ "$_v" = "unset" ]; then gl_nodiff+=("$_p"); fi
    done < "$report_file"
  elif [ "${CIS_ACTIVE:-0}" -eq 1 ]; then
    sim_deny check-attr-failed "BLOCKED: the \`-diff\` attribute guard could not run on the simulated index of ${repo_root}, so the content the commit would record was NOT verified and the commit is blocked. Repair: run git add as its own call, then run the commit in the next call."
  else
    while IFS= read -r -d '' _p; do
      [ -n "$_p" ] || continue
      if [ "$(git -C "$repo_root" check-attr diff -- "$_p" 2>/dev/null | sed 's/.*: //')" = "unset" ]; then
        gl_nodiff+=("$_p")
      fi
    done < <(git -C "$repo_root" diff --cached --name-only -z --diff-filter=ACMR 2>/dev/null)
  fi
  : > "$report_file"

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
  gl_cfg_n="${GIT_CONFIG_COUNT:-0}"
  case "$gl_cfg_n" in ''|*[!0-9]*) gl_cfg_n=0 ;; esac
  (
    cd "$repo_root" || exit 1
    env "GIT_CONFIG_COUNT=$((gl_cfg_n + 2))" \
      "GIT_CONFIG_KEY_${gl_cfg_n}=color.ui" "GIT_CONFIG_VALUE_${gl_cfg_n}=never" \
      "GIT_CONFIG_KEY_$((gl_cfg_n + 1))=color.diff" "GIT_CONFIG_VALUE_$((gl_cfg_n + 1))=never" \
      "GIT_CONFIG_PARAMETERS=${GIT_CONFIG_PARAMETERS:+${GIT_CONFIG_PARAMETERS} }'color.ui'='never' 'color.diff'='never'" \
      gitleaks git --pre-commit --staged --redact --no-banner --exit-code 1 \
        --report-format json --report-path "$report_file" >/dev/null 2>&1
  ) || scan_rc=$?

  # Re-scan any `-diff` path from its STAGED blob before trusting a clean verdict.
  # `gitleaks git` structurally could not see these (no `+` lines), so "clean" above
  # is not a statement about them. `detect --no-git` reads file CONTENT and never
  # consults git's diff machinery, so no gitattribute can reach it.
  if (( ${#gl_nodiff[@]} > 0 )); then
    nodiff_rc=0
    for _p in "${gl_nodiff[@]}"; do
      mkdir -p "$nodiff_dir/$(dirname "$_p")" 2>/dev/null || true
      git -C "$repo_root" show ":$_p" > "$nodiff_dir/$_p" 2>/dev/null || true
    done
    gitleaks detect --no-git --source "$nodiff_dir" --config "$repo_root/.gitleaks.toml" --redact --no-banner --exit-code 1 \
      --report-format json --report-path "$nodiff_report" >/dev/null 2>&1 || nodiff_rc=$?
    if [ "$nodiff_rc" -eq 1 ] && [ -s "$nodiff_report" ] && grep -q '"RuleID"' "$nodiff_report" 2>/dev/null; then
      nd_count="$(jq -r 'length' "$nodiff_report" 2>/dev/null || echo 0)"
      nd_files="$(printf '%s, ' "${gl_nodiff[@]}")"
      deny "BLOCKED: gitleaks found ${nd_count} secret-shaped string(s) in staged file(s) of ${repo_root} carrying a \`-diff\` gitattribute: ${nd_files%, }. A \`-diff\` attribute makes git emit \"Binary files … differ\" with no added lines, so the normal staged scan sees NOTHING in these files — they were re-scanned from their staged blobs. Recovery: (1) scrub the secret bytes (never commit-then-rotate); (2) if the \`-diff\` attribute is not deliberate, remove it from .gitattributes / .git/info/attributes."
    fi
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
      [.[] | "\(.File):\(.StartLine) (\(.RuleID))"] | .[0:5] | join("; ")
    ' "$report_file" 2>/dev/null || echo "")"
  fi

  if [ "$findings_count" = "0" ] || [ -z "$findings_summary" ]; then
    # gitleaks exited non-zero but the report file is empty/missing — likely
    # a transient gitleaks error rather than a real finding. Fail-open with
    # a warn so a broken binary doesn't block every commit.
    echo "[git-commit-secret-scan] WARN: gitleaks exited $scan_rc but produced no findings report for $repo_root; continuing with the remaining roots. Run 'gitleaks git --pre-commit --staged' there to diagnose." >&2
    emit git-commit-secret-scan bypass "gitleaks exit=$scan_rc, empty report"
    return 0
  fi

  reason="BLOCKED: gitleaks found ${findings_count} secret-shaped string(s) in the staged index of ${repo_root}. Locations: ${findings_summary}. The default action is to scrub the secrets — never commit-then-rotate. Recovery: (1) unstage the offending file(s) in ${repo_root} with 'git restore --staged <path>'; (2) redact the secret bytes in place; (3) re-stage and retry. If the staged content is a captured-real fixture from 'terraform show -json' or similar, strip the '.variables' block — terraform-show-json embeds sensitive HCL variables verbatim regardless of sensitive=true. See knowledge-base/project/learnings/security-issues/2026-05-25-terraform-show-json-leaks-sensitive-variables-into-fixtures.md."
  deny "$reason"
}

# ---- the would-be index (#10696) -------------------------------------------------------------------
# A command that stages AND commits (`git add -A && git commit`, `commit -a`, `commit -- <path>`) is scanned
# against the index the commit WILL record, built by commit-index-sim.sh on a temp copy: nothing in the real
# index, object store, git directory or working tree is touched. A plain `git commit -m x` reaches none of this.
sim_on=0
if [ "$lex_state" = ok ] && [ "$CTR_COMMIT_SEEN" -eq 1 ] && [ "${CTR_COMMIT_STAGES:-0}" -eq 1 ]; then sim_on=1; fi

if [ "$sim_on" -ne 1 ]; then
  for _r in "${toml_roots[@]}"; do
    scan_root "$_r"
  done
  allow
fi

# From here the policy: refuse, allocate, build per root, scan inside the export window, unexport, clean.
if [ "${CTR_STAGE_REFUSE:-0}" -eq 1 ]; then
  sim_deny config-refused "BLOCKED: the commit's own staging cannot be simulated safely (${CTR_STAGE_REFUSE_WHY}), so the content it would record was NOT scanned and the commit is blocked. Repair: stage in its own call: run 'git add <paths>' as its own command first (the scan then reads the real index), then run the commit as a second call."
fi

# Stale commit-sim-* directories (a SIGKILL cannot run the EXIT trap) older than 60 minutes, owned by the caller,
# real directories only (find -type d never follows a symlink), are swept before a new one is allocated.
sim_tmp="${TMPDIR:-/tmp}"
if [ -d "$sim_tmp" ]; then
  while IFS= read -r _d; do
    if [ -d "$_d" ] && [ ! -L "$_d" ]; then
      assert_fixture_dir "$_d"
      rm -rf "$_d" 2>/dev/null || true
    fi
  done < <(find "$sim_tmp" -maxdepth 1 -type d -name 'commit-sim-*' -user "$(id -u)" -mmin +60 2>/dev/null || true)
fi
if ! sim_dir="$(mktemp -d -t commit-sim-XXXXXX)"; then
  sim_dir=""
  sim_deny temp-dir "BLOCKED: the commit's own staging could not be simulated (a temporary directory could not be created), so the content it would record was NOT scanned and the commit is blocked. Repair: run git add as its own call, then run the commit in the next call."
fi

cis_clock_start
cis_bound_init
if [ "$CIS_BOUND_KIND" = none ]; then
  sim_deny no-bound "BLOCKED: the commit's own staging could not be simulated and bounded (none of timeout, gtimeout or perl is on PATH), so the content it would record was NOT scanned and the commit is blocked. Repair: run git add as its own call, then run the commit in the next call."
fi

# gitleaks resolves to a generated wrapper FIRST on PATH: scan_root calls `env ... gitleaks`, which bypasses a
# shell function, so the bound has to be a program. It applies the time left of the ONE total deadline and, on
# expiry, touches sim_dir/gl-timeout; an expired scan always DENIES (below), it never bypasses.
sim_real_gl="$(command -v gitleaks)"
mkdir -m 700 "$sim_dir/bin" 2>/dev/null || sim_deny temp-dir "BLOCKED: the commit's own staging could not be simulated (a temporary directory could not be created), so the content it would record was NOT scanned and the commit is blocked. Repair: run git add as its own call, then run the commit in the next call."
assert_fixture_dir "$sim_dir"
cat > "$sim_dir/bin/gitleaks" <<'WRAP'
#!/bin/sh
now=$(date +%s 2>/dev/null) || now=""
rem=0
if [ -n "$now" ] && [ -n "$CIS_WRAP_DEADLINE" ]; then rem=$((CIS_WRAP_DEADLINE - now)); fi
if [ "$rem" -le 0 ]; then : > "$CIS_WRAP_MARK"; exit 124; fi
rc=0
case "$CIS_WRAP_KIND" in
  timeout) timeout -k 2 "$rem" "$CIS_WRAP_REAL" "$@" || rc=$? ;;
  gtimeout) gtimeout -k 2 "$rem" "$CIS_WRAP_REAL" "$@" || rc=$? ;;
  perl) perl -e 'alarm shift; exec @ARGV' "$rem" "$CIS_WRAP_REAL" "$@" || rc=$? ;;
  *) : > "$CIS_WRAP_MARK"; exit 124 ;;
esac
case "$rc" in 124|137|142) : > "$CIS_WRAP_MARK" ;; esac
exit "$rc"
WRAP
chmod 700 "$sim_dir/bin/gitleaks"
export CIS_WRAP_REAL="$sim_real_gl" CIS_WRAP_KIND="$CIS_BOUND_KIND" CIS_WRAP_DEADLINE="$CIS_DEADLINE_EPOCH" CIS_WRAP_MARK="$sim_dir/gl-timeout"
export PATH="$sim_dir/bin:$PATH"

# The payload's own .cwd (not HOOK_CWD, which falls back to CLAUDE_PROJECT_DIR / PWD and is never empty): the
# exact replay trusts only a directory the payload itself names.
payload_cwd=""
payload_cwd="$(printf '%s' "$__HI_RAW" | jq -r 'if (.cwd | type) == "string" then .cwd else "" end' 2>/dev/null)" || payload_cwd=""
# shellcheck disable=SC2034  # read by cis_plan in lib/commit-index-sim.sh
CIS_ROOT_COUNT="${#scan_roots[@]}"

sim_i=0
for _r in "${toml_roots[@]}"; do
  sim_i=$((sim_i + 1))
  sim_work="$sim_dir/r$sim_i"
  mkdir -m 700 "$sim_work" 2>/dev/null || sim_deny temp-dir "BLOCKED: the commit's own staging could not be simulated (a temporary directory could not be created), so the content it would record was NOT scanned and the commit is blocked. Repair: run git add as its own call, then run the commit in the next call."
  sim_brc=0
  cis_build "$_r" "$payload_cwd" "$sim_work" || sim_brc=$?
  case "$sim_brc" in
    0) : ;;
    10)
      # The exact replay named a path that does not exist yet (trusted git error, in a proven directory).
      if [ "${CTR_STAGE_PRODUCER:-0}" -eq 1 ]; then
        # An earlier part of the same command may create it: that is a bypass vector, not a typo.
        cis_unexport
        deny_undeterminable create "a path the command stages does not exist yet, and the same command may create it"
      fi
      echo "[git-commit-secret-scan] WARN: a path named by the command's own 'git add' does not exist yet; the whole working tree of $_r was scanned instead." >&2
      emit git-commit-secret-scan-sim-failed bypass "mode=${CIS_MODE:-superset} cause=pathspec-missing"
      ;;
    *)
      case "$CIS_WHY" in
        force-nonliteral)
          sim_deny "$CIS_WHY" "BLOCKED: this command force-adds (git add -f) a path the hook cannot read literally, so the ignored content it would record was NOT scanned and the commit is blocked. Repair: run the force-add as its own call, then run the commit in the next call." ;;
        sim-timeout)
          sim_deny "$CIS_WHY" "BLOCKED: the commit's own staging could not be simulated within its time limit${CIS_ERR:+ ($CIS_ERR)}, so the content it would record was NOT scanned and the commit is blocked. This is a load condition: re-run when the machine is quieter, or run git add as its own call, then run the commit in the next call." ;;
        *)
          sim_deny "${CIS_WHY:-superset-failed}" "BLOCKED: the commit's own staging could not be simulated (${CIS_WHY:-failure}${CIS_ERR:+: $CIS_ERR}), so the content it would record was NOT scanned and the commit is blocked. Repair: run git add as its own call, then run the commit in the next call (the scan then reads the real index)." ;;
      esac ;;
  esac
  scan_root "$_r"
  cis_unexport
  assert_fixture_dir "$sim_work"; rm -rf "$sim_work" 2>/dev/null || true
  if [ -e "$sim_dir/gl-timeout" ]; then
    sim_deny sim-timeout "BLOCKED: the gitleaks scan of the simulated index of $_r did not finish within the simulation's time limit, so the content the commit would record was NOT scanned and the commit is blocked. This is a load condition: re-run when the machine is quieter, or run git add as its own call, then run the commit in the next call."
  fi
done
allow
