#!/usr/bin/env bash
# verification-scaffold — deterministic generator for the generic guardrail set
# (#10404). Iterates references/guards.tsv (tier=v1) and emits the selected
# guards into a user repo: PreToolUse hooks + a .claude/settings.json merge +
# scripts/verification/ helpers + a repo-root .github/workflows/verification-
# gates.yml, advisory-first by default. A TMPDIR-detached-worktree bite-proof
# proves each installed guard pass -> fail -> pass before the doc block is
# written.
#
# Usage:
#   verification-scaffold.sh [--target PATH] [--guards a,b | --all]
#                            [--mode advisory|enforce] [--dry-run] [--list]
#                            [--uninstall GUARD] [--headless]
#
# Defaults: --target $PWD, --guards = all v1 rows, --mode advisory, interactive
# is a no-op (--headless only declares the intent — the script never prompts).
#
# Exit matrix (every non-zero is a hard, fail-closed stop; every message prints
# on STDOUT first — agent runtimes surface stdout and swallow stderr):
#   0   success (incl. --uninstall of a never-installed guard: prints, exits 0)
#   64  usage error (unknown flag, unknown/v2 guard, --mode bogus)
#   65  precondition: --target is not inside a git work tree
#   66  refuse-if-exists (an emitted artifact already present; NO --force)
#   69  TMPDIR resolves inside the target, neither node nor jq resolves, the
#       existing .claude/settings.json is malformed, a git error, or the run
#       lock is held (<git-common-dir>/verification-scaffold.lock, pid inside)
#   71  bite-proof: an installed guard did not pass on the clean staged tree
#   72  bite-proof: an installed guard did NOT decide on the injected probe
#   73  bite-proof: an installed guard did not return to green after the probe
#
# Self-cleanup: armed BEFORE the first write, disarmed after the bite passes —
# every failure in between removes exactly the artifacts THIS run emitted
# (tracked in $WORK/emitted + the settings.json backup), so a failed install is
# re-runnable and never leaves a half-installed guard set. The doc block is
# written last; a doc failure warns only.
#
# Portable: POSIX tools only (no realpath, no `sed -i`, timeout->gtimeout->bare
# fallback); runs on founder hosts including stock macOS.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REF_DIR="$SKILL_DIR/references"
GUARDS_TSV="$REF_DIR/guards.tsv"

TAG="verification-scaffold"
log()  { printf '%s: %s\n' "$TAG" "$*" >&2; }
say()  { printf '%s: %s\n' "$TAG" "$*"; }
warn() { printf '%s: WARNING: %s\n' "$TAG" "$*"; }
die()  { say "FAILED (${2:-1}): $1"; log "$1"; exit "${2:-1}"; }

# physdir <dir>: physical path of an EXISTING directory (pwd -P — no realpath on
# stock macOS). Prints nothing when the dir is missing.
physdir() { ( cd -- "$1" 2>/dev/null && pwd -P ); }

# --- guards.tsv ---------------------------------------------------------------
# Row: name \t verdict \t surfaces \t templates \t default_mode \t deps \t
# source_files \t emits \t tier. Read once into parallel scalars via per-row
# helpers (small fixed set — a line-scan per lookup is fine and keeps bash 3.2
# compatibility: no associative arrays).
_guard_field() { # _guard_field <name> <col> -> field value (empty when absent)
  awk -F'\t' -v n="$1" -v c="$2" '$1 == n { print $c; exit }' "$GUARDS_TSV"
}
v1_guards() { awk -F'\t' '$1 !~ /^#/ && $1 != "name" && $9 == "v1" { print $1 }' "$GUARDS_TSV"; }

# --- args ---------------------------------------------------------------------
TARGET="$PWD"
GUARDS_ARG=""
MODE="advisory"
DRY_RUN=0
DO_LIST=0
UNINSTALL=""
HEADLESS=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)    TARGET="${2:-}"; shift 2 ;;
    --guards)    GUARDS_ARG="${2:-}"; shift 2 ;;
    --all)       GUARDS_ARG=""; shift ;;
    --mode)      MODE="${2:-}"; shift 2 ;;
    --dry-run)   DRY_RUN=1; shift ;;
    --list)      DO_LIST=1; shift ;;
    --uninstall) UNINSTALL="${2:-}"; shift 2 ;;
    --headless)  HEADLESS=1; shift ;;
    -h|--help)   sed -n '2,20p' "$0"; exit 0 ;;
    *)           die "unknown argument: $1" 64 ;;
  esac
done
case "$MODE" in advisory|enforce) ;; *) die "--mode must be advisory|enforce, got: $MODE" 64 ;; esac

# Resolve the guard set.
if [[ -n "$GUARDS_ARG" ]]; then
  GUARDS="$(printf '%s' "$GUARDS_ARG" | tr ',' ' ')"
else
  GUARDS="$(v1_guards | tr '\n' ' ')"
fi
GUARDS="${GUARDS% }"

for g in $GUARDS; do
  tier="$(_guard_field "$g" 9)"
  [[ -n "$tier" ]] || die "unknown guard: $g (run --list)" 64
  [[ "$tier" == "v1" ]] || die "guard $g is a v2 candidate only — not emittable" 64
done
[[ -n "$UNINSTALL" ]] && { tier="$(_guard_field "$UNINSTALL" 9)"; [[ -n "$tier" ]] || die "unknown guard: $UNINSTALL" 64; }

# Target must resolve to a git work tree BEFORE anything else (SpecFlow #2).
TARGET="$(physdir "$TARGET")" || TARGET=""
[[ -n "$TARGET" ]] || die "--target does not resolve to a directory" 65
if [[ "$DO_LIST" -eq 0 ]]; then
  git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || die "target $TARGET is not inside a git work tree" 65
  TARGET="$(physdir "$(git -C "$TARGET" rev-parse --show-toplevel)")"
fi

# --- --list ---------------------------------------------------------------------
if [[ "$DO_LIST" -eq 1 ]]; then
  awk -F'\t' '$1 !~ /^#/ && $1 != "name" { printf "%-14s %-4s %-7s emits: %s\n", $1, $9, $3, $8 }' "$GUARDS_TSV"
  if [[ -n "$TARGET" && -d "$TARGET/.git" || -f "$TARGET/.git" ]]; then
    for g in $GUARDS; do
      inst=""
      IFS=';' read -ra ep <<<"$(_guard_field "$g" 8)"
      for p in "${ep[@]}"; do [[ -e "$TARGET/$p" ]] && { inst="$inst $p"; }; done
      [[ -n "$inst" ]] && say "installed:$g →${inst}"
    done
  fi
  exit 0
fi

# --- run lock (mkdir in the git common dir) -------------------------------------
RUN_LOCK=""
take_run_lock() {
  local common
  common="$(git -C "$TARGET" rev-parse --git-common-dir 2>/dev/null)" || common=".git"
  [[ "$common" == /* ]] || common="$TARGET/$common"
  RUN_LOCK="$common/verification-scaffold.lock"
  if ! mkdir "$RUN_LOCK" 2>/dev/null; then
    local owner
    owner="$(cat "$RUN_LOCK/pid" 2>/dev/null || true)"
    if [[ -n "$owner" ]] && kill -0 "$owner" 2>/dev/null; then
      RUN_LOCK=""
      die "another verification-scaffold run (pid $owner) is in progress in this repository; wait for it" 69
    fi
    rm -rf -- "$RUN_LOCK"
    mkdir "$RUN_LOCK" 2>/dev/null || { RUN_LOCK=""; die "cannot take the run lock at $RUN_LOCK" 69; }
  fi
  printf '%s\n' "$$" > "$RUN_LOCK/pid"
}
release_run_lock() {
  [[ -n "${RUN_LOCK:-}" && -d "$RUN_LOCK" ]] && rm -rf -- "$RUN_LOCK"
  RUN_LOCK=""
  return 0
}

# TMPDIR containment — a mktemp inside the repo would land the bite worktree and
# its logs in the user's tree as untracked files (constraint-scaffold exit-69
# precedent).
check_tmpdir_outside_repo() {
  local t
  t="$(physdir "${TMPDIR:-/tmp}")" || t=""
  [[ -n "$t" ]] || return 0
  case "$t" in
    "$TARGET"|"$TARGET"/*)
      die "TMPDIR ($t) resolves inside the target repository; refusing" 69 ;;
  esac
}

# --- emitted-file bookkeeping + self-cleanup -------------------------------------
WORK="$(mktemp -d -t verification-scaffold-XXXXXX)"
EMITTED_LOG="$WORK/emitted"     # one target-absolute path per line, as written
DIRS_LOG="$WORK/dirs-created"   # dirs mkdir -p created THIS run (deepest first)
: > "$EMITTED_LOG"; : > "$DIRS_LOG"

record_emit()   { printf '%s\n' "$1" >> "$EMITTED_LOG"; }
record_dir()    { grep -qxF "$1" "$DIRS_LOG" 2>/dev/null || printf '%s\n' "$1" >> "$DIRS_LOG"; }

ensure_dir() { # ensure_dir <abs dir> — mkdir -p, recording only NEW dirs (leaf-up)
  local d="$1" missing=""
  while [[ ! -d "$d" ]]; do missing="$d $missing"; d="$(dirname "$d")"; done
  for d in $missing; do mkdir "$d" && record_dir "$d"; done
}

SETTINGS="$TARGET/.claude/settings.json"
SETTINGS_BACKED_UP=0
backup_settings() {
  [[ "$SETTINGS_BACKED_UP" -eq 1 ]] && return 0
  if [[ -f "$SETTINGS" ]]; then cp "$SETTINGS" "$WORK/settings.json.bak"; else : > "$WORK/settings.json.absent"; fi
  SETTINGS_BACKED_UP=1
}

CLEANUP_ARMED=0
_vs_cleanup() {
  local why="${1:-run aborted}"
  release_run_lock
  if [[ "$CLEANUP_ARMED" -eq 1 ]]; then
    local removed="" f d
    while IFS= read -r f; do
      [[ -e "$f" ]] && { rm -f -- "$f"; removed="$removed ${f#"$TARGET"/}"; }
    done < "$EMITTED_LOG"
    if [[ "$SETTINGS_BACKED_UP" -eq 1 ]]; then
      if [[ -f "$WORK/settings.json.bak" ]]; then cp "$WORK/settings.json.bak" "$SETTINGS" && removed="$removed .claude/settings.json(restored)"
      else rm -f -- "$SETTINGS" && removed="$removed .claude/settings.json"; fi
    fi
    # DIRS_LOG is recorded shallowest-first; remove deepest-first via a portable
    # reverse (neither tac nor tail -r exists on both GNU and BSD).
    while IFS= read -r d; do rmdir "$d" >/dev/null 2>&1 || true; done \
      < <(awk '{a[NR]=$0} END{for(i=NR;i>0;i--)print a[i]}' "$DIRS_LOG")
    [[ -n "$removed" ]] && say "$why; removed:${removed}"
  fi
  # The bite worktree is removed on the same path — a mid-bite failure must not
  # leave a registered worktree behind.
  if [[ -n "${WT:-}" && -d "$WT" ]]; then
    git -C "$TARGET" worktree remove --force "$WT" >/dev/null 2>&1 || true
    rm -rf -- "$WT"
  fi
  [[ -n "${BITE_DIR:-}" && -d "$BITE_DIR" ]] && rm -rf -- "$BITE_DIR"
  return 0
}

# --- template emission -----------------------------------------------------------
# emit_tpl <template-rel> <target-rel> <mode>: render @MODE@/@DEFAULT_BRANCHES@/
# @CI_CONTINUE_ON_ERROR@ substitutions, write, record.
emit_tpl() {
  local tpl="$REF_DIR/$1" out="$TARGET/$2" mode="${3:-0644}"
  ensure_dir "$(dirname "$out")"
  sed -e "s~@MODE@~$MODE~g" \
      -e "s~@DEFAULT_BRANCHES@~$DEFAULT_BRANCHES~g" \
      -e "s~@CI_CONTINUE_ON_ERROR@~$CI_CONTINUE_ON_ERROR~g" \
      "$tpl" > "$out"
  chmod "$mode" "$out"
  record_emit "$out"
}

HOOK_COMMANDS=()   # settings.json command strings, one per emitted hook
emit_guard() {
  local g="$1"
  case "$g" in
    secret-scan)
      emit_tpl "guards/secret-scan-hook.sh.template" ".claude/hooks/secret-scan.sh" 0755
      HOOK_COMMANDS+=("bash \"\$CLAUDE_PROJECT_DIR/.claude/hooks/secret-scan.sh\"")
      emit_tpl "gitleaks.toml.template" ".gitleaks.toml" 0644
      ;;
    commit-on-main)
      emit_tpl "guards/commit-on-main-hook.sh.template" ".claude/hooks/commit-on-main.sh" 0755
      HOOK_COMMANDS+=("bash \"\$CLAUDE_PROJECT_DIR/.claude/hooks/commit-on-main.sh\"")
      emit_tpl "guards/precommit-guard.sh.template" "scripts/verification/precommit-guard.sh" 0755
      emit_tpl "guards/wrapper-boundary.sh.template" "scripts/verification/lib/wrapper-boundary.sh" 0644
      ;;
    block-stash)
      emit_tpl "guards/block-stash-hook.sh.template" ".claude/hooks/block-stash.sh" 0755
      HOOK_COMMANDS+=("bash \"\$CLAUDE_PROJECT_DIR/.claude/hooks/block-stash.sh\"")
      ;;
    orphan-test)
      emit_tpl "guards/orphan-test-check.sh.template" "scripts/verification/orphan-test-check.sh" 0755
      emit_known_orphans
      ;;
    *) die "no emitter for guard: $g" 64 ;;
  esac
}

# Seed .github/verification-known-orphans.txt: header + one grandfathered row per
# currently-unregistered tracked *.test.sh (the baseline precedent — pre-existing
# orphans are recorded, never silently absorbed).
RUNNER_GLOBS_SEED="scripts/test-all.sh scripts/run-tests* Makefile makefile package.json"
emit_known_orphans() {
  local out="$TARGET/.github/verification-known-orphans.txt"
  {
    printf '# verification-known-orphans.txt — seeded by soleur:verification-scaffold.\n'
    printf '# Format: <repo-relative path>.test.sh # <reason>. A suite listed here is\n'
    printf '# excluded from the orphan-test check; a line without a reason fails it.\n'
  } > "$out"
  # Registration surfaces, same rule the emitted check applies: any workflow
  # file plus any file matching a runner glob.
  local surfaces="" f pat
  for f in "$TARGET"/.github/workflows/*.yml "$TARGET"/.github/workflows/*.yaml; do
    [[ -f "$f" ]] && surfaces="$surfaces $f"
  done
  local rf
  while IFS= read -r rf; do surfaces="$surfaces $TARGET/$rf"; done < <(
    cd "$TARGET" && for pat in $RUNNER_GLOBS_SEED; do for f in $pat; do [[ -f "$f" ]] && printf '%s\n' "$f"; done; done
  )
  local suite base seeded=0
  while IFS= read -r suite; do
    [[ -n "$suite" ]] || continue
    base="$(basename "$suite")"
    # shellcheck disable=SC2086
    if [[ -n "${surfaces# }" ]] && grep -lFq -- "$base" $surfaces 2>/dev/null | grep -q .; then continue; fi
    printf '%s # pre-existing at verification-scaffold install (grandfathered — register or remove)\n' "$suite" >> "$out"
    seeded=$((seeded + 1))
  done < <(git -C "$TARGET" ls-files '*.test.sh' 2>/dev/null)
  [[ "$seeded" -gt 0 ]] && log "seeded $seeded grandfathered orphan row(s) in ${out#"$TARGET"/}"
  record_emit "$out"
}

# --- settings.json merge (node-first, jq fallback, else refuse) -------------------
merge_settings() {
  backup_settings
  ensure_dir "$(dirname "$SETTINGS")"
  local cmds=() h
  for h in "${HOOK_COMMANDS[@]+"${HOOK_COMMANDS[@]}"}"; do [[ -n "$h" ]] && cmds+=("$h"); done
  if command -v node >/dev/null 2>&1; then
    node - "$SETTINGS" ${cmds[@]+"${cmds[@]}"} <<'NODE'
const fs = require('fs');
const [,, file, ...cmds] = process.argv;
let d = {};
if (fs.existsSync(file) && fs.statSync(file).size > 0) d = JSON.parse(fs.readFileSync(file, 'utf8'));
d.hooks = d.hooks || {};
d.hooks.PreToolUse = d.hooks.PreToolUse || [];
for (const c of cmds) {
  const seen = d.hooks.PreToolUse.some(m => (m.hooks || []).some(h => h.command === c));
  if (!seen) d.hooks.PreToolUse.push({ matcher: 'Bash', hooks: [{ type: 'command', command: c }] });
}
fs.writeFileSync(file, JSON.stringify(d, null, 2) + '\n');
NODE
  elif command -v jq >/dev/null 2>&1; then
    [[ -f "$SETTINGS" ]] || printf '{}\n' > "$SETTINGS"
    local c
    for c in ${cmds[@]+"${cmds[@]}"}; do
      local tmp="$WORK/settings.jq"
      jq --arg c "$c" '
        .hooks //= {} | .hooks.PreToolUse //= [] |
        if ([.hooks.PreToolUse[].hooks[]? | .command] | index($c)) then .
        else .hooks.PreToolUse += [{matcher:"Bash",hooks:[{type:"command",command:$c}]}] end
      ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
    done
  else
    die "neither node nor jq resolves — cannot merge .claude/settings.json safely (install one, or register the hooks by hand)" 69
  fi
  # NOT recorded in EMITTED_LOG: the backup governs the restore path, and the
  # file itself may be user-owned and pre-existing — never rm'd.
}

unmerge_settings() { # remove the given guards' hook command entries
  local names="$1" c
  [[ -f "$SETTINGS" ]] || return 0
  if command -v node >/dev/null 2>&1; then
    node - "$SETTINGS" $names <<'NODE'
const fs = require('fs');
const [,, file, ...names] = process.argv;
if (!fs.existsSync(file)) process.exit(0);
const d = JSON.parse(fs.readFileSync(file, 'utf8'));
if (!d.hooks || !d.hooks.PreToolUse) process.exit(0);
const drop = new Set(names.map(n => `bash "$CLAUDE_PROJECT_DIR/.claude/hooks/${n}.sh"`));
d.hooks.PreToolUse = d.hooks.PreToolUse
  .map(m => ({ ...m, hooks: (m.hooks || []).filter(h => !drop.has(h.command)) }))
  .filter(m => (m.hooks || []).length > 0);
fs.writeFileSync(file, JSON.stringify(d, null, 2) + '\n');
NODE
  elif command -v jq >/dev/null 2>&1; then
    local tmp="$WORK/settings.jq" expr="."
    for c in $names; do
      expr="$expr | .hooks.PreToolUse = ([.hooks.PreToolUse[]? | .hooks = ([.hooks[]? | select(.command != \"bash \\\"\$CLAUDE_PROJECT_DIR/.claude/hooks/$c.sh\\\"\")])] | map(select((.hooks|length) > 0)))"
    done
    jq "$expr" "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  fi
}

# --- workflow render -----------------------------------------------------------
# Keep the marker block only for selected ci guards; stamp continue-on-error.
render_workflow() {
  local tpl="$REF_DIR/guards/verification-gates.yml.template" out="$1"
  local keep_secret=0 keep_orphan=0 g
  for g in $GUARDS; do
    case "$g" in secret-scan) keep_secret=1 ;; orphan-test) keep_orphan=1 ;; esac
  done
  awk -v ks="$keep_secret" -v ko="$keep_orphan" '
    /^  # verification-scaffold:begin:secret-scan$/ { skip = (ks ? 0 : 1); if (skip) next }
    /^  # verification-scaffold:end:secret-scan$/   { if (skip) { skip=0; next } }
    /^  # verification-scaffold:begin:orphan-test$/ { skip = (ko ? 0 : 1); if (skip) next }
    /^  # verification-scaffold:end:orphan-test$/   { if (skip) { skip=0; next } }
    !skip { print }
  ' "$tpl" | sed -e "s|@CI_CONTINUE_ON_ERROR@|$CI_CONTINUE_ON_ERROR|g" > "$out"
  record_emit "$out"
}

# --- default-branch detection (SpecFlow #1) --------------------------------------
resolve_default_branches() {
  local ref
  ref="$(git -C "$TARGET" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [[ -n "$ref" ]]; then
    DEFAULT_BRANCHES="${ref#origin/}"
  else
    DEFAULT_BRANCHES="main|master"
  fi
  # Regex-escape: a default named release/1.0 must not let . match a literal.
  DEFAULT_BRANCHES="$(printf '%s' "$DEFAULT_BRANCHES" | sed 's/[][\.*^$/]/\\&/g')"
}

# --- bite-proof ------------------------------------------------------------------
WT=""
BITE_DIR=""
prove_bite() {
  BITE_DIR="$(mktemp -d -t verification-bite-XXXXXX)"
  WT="$BITE_DIR/wt"
  local git_err
  git_err="$(git -C "$TARGET" worktree add --detach "$WT" HEAD 2>&1 >/dev/null)" \
    || die "git worktree add failed: $(printf '%s' "$git_err" | tail -n 3 | tr '\n' ' ')" 69
  # Mirror the emitted files into the worktree (untracked emits are not in HEAD).
  local f
  while IFS= read -r f; do
    local rel="${f#"$TARGET"/}"
    mkdir -p "$WT/$(dirname "$rel")"
    [[ -f "$f" ]] && cp "$f" "$WT/$rel" && [[ "$f" == *.sh ]] && chmod +x "$WT/$rel"
  done < "$EMITTED_LOG"

  for g in $GUARDS; do
    case "$g" in
      secret-scan)    bite_secret_scan ;;
      commit-on-main) bite_commit_on_main ;;
      block-stash)    bite_block_stash ;;
      orphan-test)    bite_orphan_test ;;
    esac
  done
  git -C "$TARGET" worktree remove --force "$WT" >/dev/null 2>&1 || true
  rm -rf -- "$BITE_DIR"
  WT=""; BITE_DIR=""
}

bite_fail() { # bite_fail <code> <guard> <msg>
  say "bite-proof FAILED ($1): $2 — $3"
  exit "$1"
}

# Run an emitted hook: stdin payload, cwd = $WT. Captures stdout JSON + stderr.
run_hook() { # run_hook <hook-path> <command> <cwd-override?>
  local hook="$1" cmd="$2" cwd="${3:-$WT}"
  ( cd "$cwd" && printf '%s' "$(payload_json "$cmd" "$cwd")" | bash "$hook" ) 2>"$BITE_DIR/hook-err.log"
}
payload_json() { # payload_json <command> <cwd>
  if command -v jq >/dev/null 2>&1; then
    jq -nc --arg c "$1" --arg w "$2" '{tool_name:"Bash",tool_input:{command:$c},cwd:$w}'
  elif command -v node >/dev/null 2>&1; then
    node -e 'console.log(JSON.stringify({tool_name:"Bash",tool_input:{command:process.argv[1]},cwd:process.argv[2]}))' "$1" "$2"
  else
    printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' "$1" "$2"
  fi
}
decision_of() { sed -n 's/.*"permissionDecision": *"\([a-z]*\)".*/\1/p' "$1" | head -n 1; }
expect_decision() { # expect_decision <guard> <stage> <got-file> <want...>
  local g="$1" stage="$2" f="$3"; shift 3
  local got; got="$(decision_of "$f")"
  local w
  for w in "$@"; do [[ "$got" == "$w" ]] && return 0; done
  return 1
}

bite_secret_scan() {
  if ! command -v gitleaks >/dev/null 2>&1; then
    say "bite-proof secret-scan: SKIP — gitleaks is not on PATH (the hook will warn+allow per commit; the CI job still scans). Install gitleaks 8.24.x to prove this arm."
    return 0
  fi
  local hook="$WT/.claude/hooks/secret-scan.sh" out
  # pass: clean staged file
  printf 'hello\n' > "$WT/bite-clean.txt"
  git -C "$WT" add bite-clean.txt
  out="$(run_hook "$hook" "git commit -m x")" || true
  expect_decision secret-scan pass <(printf '%s' "$out") allow \
    || bite_fail 71 secret-scan "clean staged tree did not allow (got: $out; stderr: $(cat "$BITE_DIR/hook-err.log"))"
  # fail: staged secret-shaped string
  # Synthetic-but-shaped secret (the AWS docs example key is allowlisted in
  # gitleaks's default ruleset — this variant keeps the 40-char shape only).
  printf 'AWS_SECRET_ACCESS_KEY = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYSYNTHETIC0"\n' > "$WT/bite-secret.txt"
  git -C "$WT" add bite-secret.txt
  out="$(run_hook "$hook" "git commit -m x")" || true
  if [[ "$MODE" == "enforce" ]]; then want=deny; else want=ask; fi
  expect_decision secret-scan fail <(printf '%s' "$out") "$want" \
    || bite_fail 72 secret-scan "staged secret did not produce $want (got: $out; stderr: $(cat "$BITE_DIR/hook-err.log"))"
  # pass again: revert
  git -C "$WT" rm -q --cached bite-secret.txt && rm -f "$WT/bite-secret.txt"
  out="$(run_hook "$hook" "git commit -m x")" || true
  expect_decision secret-scan pass2 <(printf '%s' "$out") allow \
    || bite_fail 73 secret-scan "did not return to green after the probe was reverted (got: $out)"
  say "bite-proof secret-scan: pass -> fail($want) -> pass"
}

bite_commit_on_main() {
  local hook="$WT/.claude/hooks/commit-on-main.sh" out
  local fx="$BITE_DIR/fx-commit" first="${DEFAULT_BRANCHES%%|*}"
  first="${first//\\/}"  # un-escape for git branch creation
  mkdir -p "$fx"
  # symbolic-ref points the unborn HEAD at the resolved default BEFORE the first
  # commit — `git init -b` would fail on old gits and `checkout -b` collides when
  # the init default already IS the resolved name.
  git -C "$fx" init -q
  git -C "$fx" symbolic-ref HEAD "refs/heads/$first"
  git -C "$fx" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$fx" checkout -qb feat-bite
  local want; [[ "$MODE" == "enforce" ]] && want=deny || want=allow
  # The hook resolves its guard via the cwd's toplevel — run it from the
  # worktree; the PAYLOAD's -C targets the fixture repo the guard branches on.
  # pass: feature branch
  out="$(run_hook "$hook" "git -C $fx commit -m x" "$WT")" || true
  expect_decision commit-on-main pass <(printf '%s' "$out") allow \
    || bite_fail 71 commit-on-main "feature-branch payload was not allowed (got: $out; stderr: $(cat "$BITE_DIR/hook-err.log"))"
  # fail: default branch
  git -C "$fx" checkout -q "$first"
  out="$(run_hook "$hook" "git -C $fx commit -m x" "$WT")" || true
  expect_decision commit-on-main fail <(printf '%s' "$out") "$want" \
    || bite_fail 72 commit-on-main "default-branch ($first) payload did not produce $want (got: $out; stderr: $(cat "$BITE_DIR/hook-err.log"))"
  # Advisory must warn a REFUSAL on stderr — an allow with no signal is a silent
  # guard, and a tool-error warn must not satisfy the arm either.
  if [[ "$MODE" == "advisory" ]] && ! grep -qE 'not allowed|refused' "$BITE_DIR/hook-err.log"; then
    bite_fail 72 commit-on-main "advisory refusal carried no refusal WARN on stderr (got: $out; stderr: $(cat "$BITE_DIR/hook-err.log"))"
  fi
  # pass again
  git -C "$fx" checkout -q feat-bite
  out="$(run_hook "$hook" "git -C $fx commit -m x" "$WT")" || true
  expect_decision commit-on-main pass2 <(printf '%s' "$out") allow \
    || bite_fail 73 commit-on-main "did not return to allow on a feature branch (got: $out)"
  say "bite-proof commit-on-main: pass -> fail($want) -> pass"
}

bite_block_stash() {
  local hook="$WT/.claude/hooks/block-stash.sh" out want
  [[ "$MODE" == "enforce" ]] && want=deny || want=allow
  out="$(run_hook "$hook" "git status")" || true
  expect_decision block-stash pass <(printf '%s' "$out") allow \
    || bite_fail 71 block-stash "git status was not allowed (got: $out)"
  out="$(run_hook "$hook" "git add x && git stash pop")" || true
  expect_decision block-stash fail <(printf '%s' "$out") "$want" \
    || bite_fail 72 block-stash "chained 'git stash pop' did not produce $want (got: $out)"
  if [[ "$MODE" == "advisory" ]] && ! grep -qE 'not allowed' "$BITE_DIR/hook-err.log"; then
    bite_fail 72 block-stash "advisory refusal carried no refusal WARN on stderr (got: $out)"
  fi
  out="$(run_hook "$hook" "git stash list")" || true
  expect_decision block-stash pass2 <(printf '%s' "$out") allow \
    || bite_fail 73 block-stash "documented read-only 'git stash list' was not allowed (got: $out)"
  say "bite-proof block-stash: pass -> fail($want) -> pass"
}

bite_orphan_test() {
  local check="$WT/scripts/verification/orphan-test-check.sh" out rc
  # pass: current tree (grandfather rows already cover pre-existing orphans)
  out="$(cd "$WT" && bash "$check" 2>&1)" || bite_fail 71 orphan-test "clean tree did not pass: $out"
  # fail: an unregistered suite
  printf '#!/usr/bin/env bash\nexit 0\n' > "$WT/scratch-bite.test.sh"
  git -C "$WT" add scratch-bite.test.sh
  rc=0; out="$(cd "$WT" && bash "$check" 2>&1)" || rc=$?
  if [[ "$rc" -eq 0 ]] || ! grep -q 'scratch-bite.test.sh' <<<"$out"; then
    git -C "$WT" rm -q --cached scratch-bite.test.sh; rm -f "$WT/scratch-bite.test.sh"
    bite_fail 72 orphan-test "injected unregistered suite was not named (rc=$rc): $out"
  fi
  # pass again
  git -C "$WT" rm -q --cached scratch-bite.test.sh; rm -f "$WT/scratch-bite.test.sh"
  out="$(cd "$WT" && bash "$check" 2>&1)" \
    || bite_fail 73 orphan-test "did not return to green after the probe was reverted: $out"
  say "bite-proof orphan-test: pass -> fail(named scratch-bite.test.sh) -> pass"
}

# --- doc block (append-once, written LAST) -----------------------------------------
emit_doc() {
  local guard_list="${GUARDS// /, }" guard_rows="" g surfaces artifacts decides
  for g in $GUARDS; do
    surfaces="$(_guard_field "$g" 3)"
    artifacts="$(printf '%s' "$(_guard_field "$g" 8)" | tr ';' ' ')"
    case "$g" in
      secret-scan)    decides="secret-shaped strings staged for commit" ;;
      commit-on-main) decides="commits on the default branch(es): $DEFAULT_BRANCHES" ;;
      block-stash)    decides="every git stash except list/show" ;;
      orphan-test)    decides="tracked *.test.sh named by no runner surface" ;;
    esac
    guard_rows="$guard_rows| \`$g\` ($surfaces) | \`$artifacts\` | $decides |"$'\n'
  done
  printf '%s' "$guard_rows" > "$WORK/doc-rows"
  local content
  content="$(sed -e "s|@MODE@|$MODE|g" -e "s|@GUARD_LIST@|$guard_list|g" \
      -e "s|@DATE@|$(date -u +%Y-%m-%d)|g" \
      -e "/@GUARD_TABLE@/r $WORK/doc-rows" -e "/@GUARD_TABLE@/d" \
      "$REF_DIR/verification-readme.template")"
  local doc="$TARGET/VERIFICATION.md"
  [[ -e "$doc" || -L "$doc" ]] && doc="$TARGET/README.md"
  [[ -L "$doc" ]] && { warn "refusing to append through a symlink: ${doc#"$TARGET"/}"; return 0; }
  if grep -qF 'verification-scaffold:readme:start' "$doc" 2>/dev/null; then
    log "doc block already present in ${doc#"$TARGET"/}"
    return 0
  fi
  [[ -s "$doc" && -n "$(tail -c 1 "$doc")" ]] && printf '\n' >> "$doc"
  printf '%s\n' "$content" >> "$doc" \
    || warn "could not append the doc block to ${doc#"$TARGET"/} — the guards are installed and proven; add references/verification-readme.template by hand"
}

# --- --uninstall -------------------------------------------------------------------
if [[ -n "$UNINSTALL" ]]; then
  g="$UNINSTALL"
  emits="$(_guard_field "$g" 8)"
  removed=""
  IFS=';' read -ra paths <<<"$emits"
  for p in "${paths[@]}"; do
    f="$TARGET/$p"
    case "$p" in
      .github/workflows/verification-gates.yml)
        # Shared artifact: strip only this guard's job block; delete only when no
        # other selected-capable ci guard remains installed.
        other_ci=0
        for og in $(v1_guards); do
          [[ "$og" == "$g" ]] && continue
          case "$(_guard_field "$og" 3)" in *ci*)
            IFS=';' read -ra op <<<"$(_guard_field "$og" 8)"
            for q in "${op[@]}"; do [[ "$q" == "scripts/verification/orphan-test-check.sh" || "$q" == ".claude/hooks/secret-scan.sh" ]] && [[ -e "$TARGET/$q" ]] && other_ci=1; done
          esac
        done
        if [[ -f "$f" ]]; then
          if [[ "$other_ci" -eq 1 ]]; then
            sed "/# verification-scaffold:begin:$g/,/# verification-scaffold:end:$g/d" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
            removed="$removed $p($g-job-stripped)"
          else
            rm -f -- "$f"; removed="$removed $p"
          fi
        fi ;;
      .gitleaks.toml)
        if [[ -f "$f" ]]; then
          if cmp -s "$f" "$REF_DIR/gitleaks.toml.template"; then rm -f -- "$f"; removed="$removed $p"
          else warn "leaving modified $p (no longer the emitted bytes — remove by hand if unwanted)"; fi
        fi ;;
      .claude/hooks/*.sh|scripts/verification/*)
        [[ -e "$f" ]] && { rm -f -- "$f"; removed="$removed $p"; } ;;
      *) [[ -e "$f" ]] && { rm -f -- "$f"; removed="$removed $p"; } ;;
    esac
  done
  # settings.json hook entries for this guard's hooks
  hook_names=""
  for p in "${paths[@]}"; do case "$p" in .claude/hooks/*.sh) hook_names="$hook_names $(basename "$p" .sh)" ;; esac; done
  [[ -n "$hook_names" ]] && unmerge_settings "$hook_names"
  # Empty dirs — only those THIS scaffold created (the persisted ledger), only
  # when empty (rmdir enforces that).
  if [[ -f "$TARGET/.claude/.verification-scaffold-dirs" ]]; then
    while IFS= read -r d; do [[ -d "$d" ]] && rmdir "$d" 2>/dev/null || true; done \
      < <(awk '{a[NR]=$0} END{for(i=NR;i>0;i--)print a[i]}' "$TARGET/.claude/.verification-scaffold-dirs")
  fi
  # Drop the ledger itself when no v1 guard has a single artifact left.
  left=""
  for og in $(v1_guards); do
    IFS=';' read -ra ep <<<"$(_guard_field "$og" 8)"
    for p in "${ep[@]}"; do [[ -e "$TARGET/$p" ]] && left=1; done
  done
  [[ -z "$left" ]] && rm -f -- "$TARGET/.claude/.verification-scaffold-dirs" \
    && rmdir "$TARGET/.claude" 2>/dev/null || true
  if [[ -z "$removed" ]]; then
    say "$g: not installed — nothing removed."
    for og in $(v1_guards); do
      inst=""
      IFS=';' read -ra ep <<<"$(_guard_field "$og" 8)"
      for p in "${ep[@]}"; do [[ -e "$TARGET/$p" ]] && inst="$inst $p"; done
      [[ -n "$inst" ]] && say "installed:$og →${inst}"
    done
    exit 0
  fi
  say "uninstalled $g — removed:${removed}"
  exit 0
fi

# --- default mode ------------------------------------------------------------------
check_tmpdir_outside_repo
resolve_default_branches
[[ "$MODE" == "enforce" ]] && CI_CONTINUE_ON_ERROR="false" || CI_CONTINUE_ON_ERROR="true"

# Merge tool precheck BEFORE the lock/write window (69 with named remediation).
need_merge=0
for g in $GUARDS; do case "$(_guard_field "$g" 3)" in *hook*) need_merge=1 ;; esac; done
if [[ "$need_merge" -eq 1 ]] && ! command -v node >/dev/null 2>&1 && ! command -v jq >/dev/null 2>&1; then
  die "no node and no jq on PATH — cannot merge .claude/settings.json; install either or deselect the hook guards" 69
fi
# Malformed existing settings.json refused pre-write (AC7).
if [[ -f "$SETTINGS" ]]; then
  if command -v node >/dev/null 2>&1; then
    node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$SETTINGS" 2>/dev/null \
      || die ".claude/settings.json is not valid JSON — refusing before any write" 69
  elif command -v jq >/dev/null 2>&1; then
    jq -e . "$SETTINGS" >/dev/null 2>&1 || die ".claude/settings.json is not valid JSON — refusing before any write" 69
  fi
fi

# Refuse-if-exists over every emit path (deduped), BEFORE anything is written.
# .claude/settings.json is merged, never refused. Doc files are append-once.
collide="" seen=""
for g in $GUARDS; do
  IFS=';' read -ra ep <<<"$(_guard_field "$g" 8)"
  for p in "${ep[@]}"; do
    [[ "$p" == ".claude/settings.json" ]] && continue
    case " $seen " in *" $p "*) continue ;; esac
    seen="$seen $p"
    [[ -e "$TARGET/$p" ]] && collide="$collide $p"
  done
done
[[ -n "$collide" ]] && die "refuse-if-exists:${collide} already present (no --force). Remove or --uninstall the owning guard first." 66

if [[ "$DRY_RUN" -eq 1 ]]; then
  say "dry-run — would emit into $TARGET (mode=$MODE, default-branches=$DEFAULT_BRANCHES):"
  for g in $GUARDS; do
    say "  [$g]"
    IFS=';' read -ra ep <<<"$(_guard_field "$g" 8)"
    for p in "${ep[@]}"; do say "    $p"; done
  done
  if [[ "$need_merge" -eq 1 ]]; then
    say "  merge .claude/settings.json (PreToolUse Bash):"
    for g in $GUARDS; do
      IFS=';' read -ra ep <<<"$(_guard_field "$g" 8)"
      for p in "${ep[@]}"; do case "$p" in .claude/hooks/*.sh) say "    hook: $p" ;; esac; done
    done
  fi
  say "  doc block → VERIFICATION.md (else README.md marker block), written last"
  say "  then a TMPDIR detached-worktree bite-proof per guard (pass -> fail -> pass)"
  exit 0
fi

# Arm self-cleanup before the FIRST write.
CLEANUP_ARMED=1
trap '_vs_cleanup' EXIT
trap '_vs_cleanup interrupted; trap - EXIT; exit 143' INT TERM
take_run_lock

# Emission order (Guard 5): hooks+scripts+aux → settings merge → workflow → bite → doc.
ensure_dir "$TARGET/.claude/hooks"
ensure_dir "$TARGET/scripts/verification"
ensure_dir "$TARGET/.github/workflows"
for g in $GUARDS; do
  emit_guard "$g"
  log "emitted guard: $g"
done
[[ "${#HOOK_COMMANDS[@]}" -gt 0 ]] && merge_settings
need_workflow=0
for g in $GUARDS; do case "$(_guard_field "$g" 3)" in *ci*) need_workflow=1 ;; esac; done
if [[ "$need_workflow" -eq 1 ]]; then
  render_workflow "$TARGET/.github/workflows/verification-gates.yml"
  log "emitted: .github/workflows/verification-gates.yml"
fi

# Persist the created-dir ledger so --uninstall can honor "removed only if the
# run created them AND they're empty" (SpecFlow #3).
if [[ -s "$DIRS_LOG" ]]; then
  ensure_dir "$TARGET/.claude"
  cp "$DIRS_LOG" "$TARGET/.claude/.verification-scaffold-dirs"
  record_emit "$TARGET/.claude/.verification-scaffold-dirs"
fi

# Bite-proof, then prose. A repo with no commits cannot host a detached worktree
# — skip loudly rather than pretend (the emitted artifacts still refuse-if-exists).
if git -C "$TARGET" rev-parse --verify HEAD >/dev/null 2>&1; then
  prove_bite
else
  say "bite-proof: SKIP — HEAD does not resolve (no commits yet); the installed guards are unproven until the first commit, then re-run with --guards none semantics: verify by hand"
fi

release_run_lock
CLEANUP_ARMED=0
trap - EXIT INT TERM

emit_doc
say "done (mode=$MODE). Guards: ${GUARDS}. Promote per VERIFICATION.md after >=1 clean run."
exit 0
