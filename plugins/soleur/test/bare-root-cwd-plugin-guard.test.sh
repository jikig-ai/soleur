#!/usr/bin/env bash
# Tests for plugins/soleur/hooks/bare-root-cwd-guard.sh — the plugin-level
# SessionStart arm for the ADR-099 row-3 bare-repo-root misanchor (#10392).
#
# Synthesized fixtures only. No `set -e`: accumulate-then-exit; every deliberately
# non-zero call is captured with `RC=0; x=$(...) || RC=$?`.
#
# The hook reads the SessionStart envelope on stdin (`{"cwd": "<dir>"}`), so the
# runner pipes a jq-built envelope rather than passing an argv operand. When the
# envelope omits .cwd the hook falls back DEVIN_PROJECT_DIR -> CLAUDE_PROJECT_DIR
# -> $PWD — each leg is exercised.

set -uo pipefail

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HOOK="$SCRIPT_DIR/../hooks/bare-root-cwd-guard.sh"
PLUGIN_ROOT="$(cd -P "$SCRIPT_DIR/.." && pwd -P)"
MARKER="SOLEUR_BARE_ROOT_CWD source=plugin-session-start"

# shellcheck source=lib/git-fixture-env.sh
source "$SCRIPT_DIR/lib/git-fixture-env.sh"
git_fixture_env "$SANDBOX" || { printf '[FATAL] git_fixture_env refused %s\n' "$SANDBOX" >&2; exit 2; }

# Canonical copy of test-helpers.sh's assert_fixture_dir — required for every
# mktemp-bound dir used outside the function that bound it (#7652). Byte-equal
# to the canonical definition; do not reword it here only.
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

command -v git >/dev/null 2>&1 || { echo "UNRESOLVED: git missing — this suite asserted nothing; install git"; exit 3; }
command -v jq >/dev/null 2>&1 || { echo "UNRESOLVED: jq missing — this suite asserted nothing; install jq"; exit 3; }
[[ -f "$HOOK" ]] || { echo "FAIL: $HOOK missing — GREEN required"; exit 1; }

PASS=0; FAIL=0; FAILURES=(); CUR=""; CASE_N=0
begin() { CUR="$1"; CASE_N=0; }
ok() { PASS=$((PASS + 1)); CASE_N=$((CASE_N + 1)); printf '  ok   %s: %s\n' "$CUR" "$1"; }
bad() { FAIL=$((FAIL + 1)); CASE_N=$((CASE_N + 1)); FAILURES+=("$CUR: $1"); printf '  FAIL %s: %s\n' "$CUR" "$1"; }
eq() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (expected [$2], got [$3])"; fi; }

# --- fixture builders (mirrored from git-repo-readiness-diag.test.sh — the same
# eight shapes, deliberately copied not shared so the two suites' fixtures stay
# independent populations) --------------------------------------------------
seed_main() {
  local d="$1" t c
  assert_fixture_dir "$d"
  t=$(git -C "$d" hash-object -t tree -w /dev/null) || return 1
  c=$(git -C "$d" commit-tree "$t" -m seed) || return 1
  git -C "$d" update-ref refs/heads/main "$c" || return 1
}
mk_bare_root() {
  local d="$1"; assert_fixture_dir "$d"
  mkdir -p "$d"; git -C "$d" init -q || return 1
  seed_main "$d" || return 1
  git -C "$d" symbolic-ref HEAD refs/heads/main || return 1
  git -C "$d" config core.bare true || return 1
}
mk_plain() {
  local d="$1"; assert_fixture_dir "$d"
  mkdir -p "$d"; git -C "$d" init -q || return 1
  seed_main "$d" || return 1
  git -C "$d" symbolic-ref HEAD refs/heads/main || return 1
}
mk_true_bare() {
  local d="$1"; assert_fixture_dir "$d"
  git init -q --bare "$d" || return 1
  seed_main "$d" || return 1
  git -C "$d" symbolic-ref HEAD refs/heads/main || return 1
}
mk_wtmask() {
  local d="$1"; assert_fixture_dir "$d"
  mk_plain "$d" || return 1
  git -C "$d" config extensions.worktreeConfig true || return 1
  git -C "$d" config --worktree core.bare true || return 1
}
mk_imposter() {
  local d="$1"; assert_fixture_dir "$d"
  mkdir -p "$d/sub/.git"; git -C "$d" init -q || return 1
  seed_main "$d" || return 1
  git -C "$d" symbolic-ref HEAD refs/heads/main || return 1
  printf '[core]\n\tbare = true\n' > "$d/sub/.git/config"
}

# run_hook <dir> — pipe a {"cwd":dir} envelope through the hook; sets OUT, RC.
# The plugin/project env vars are scrubbed inside the subshell so the ambient
# environment can never leak a CLAUDE_PLUGIN_ROOT/DEVIN_PROJECT_DIR resolution
# into a case that asserts on .cwd. Per-case env (GIT_DIR, DEVIN_PROJECT_DIR, …)
# is passed via the `VAR=x run_hook d` prefix form, which survives into the
# subshell.
run_hook() {
  RC=0
  OUT=$(
    unset DEVIN_PROJECT_DIR CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_ROOT
    jq -nc --arg cwd "$1" '{cwd:$cwd}' | bash "$HOOK" 2>/dev/null
  ) || RC=$?
}

# ctx: extract .hookSpecificOutput.additionalContext (empty when OUT is not an
# envelope — the silent contract).
ctx_of() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null; }

echo "bare-root-cwd-plugin-guard.test.sh"

begin P1
d="$SANDBOX/p1"; mk_bare_root "$d" || bad "fixture"
run_hook "$d"
eq "row-3 bare root: exit status is 0" "0" "$RC"
eq "emits hookEventName SessionStart" "SessionStart" \
  "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.hookEventName // ""' 2>/dev/null)"
ctx=$(ctx_of "$OUT")
eq "marker is the first context line" "$MARKER" "$(sed -n 1p <<<"$ctx")"
case "$ctx" in
  *"git worktree add "*) ok "redirect uses generic git worktree add" ;;
  *) bad "context lacks generic git worktree add ($ctx)" ;;
esac
case "$ctx" in
  *"plugins/soleur/"*) bad "context leaks a soleur-specific path on a generic fixture" ;;
  *worktree-manager*) bad "context names worktree-manager without the plugin script gate" ;;
  *) ok "no soleur-specific path without CLAUDE_PLUGIN_ROOT" ;;
esac
unprefixed=$(sed -n '2,$p' <<<"$ctx" | grep -cv '^\[bare-root-cwd\] ' || true)
eq "every line after the marker carries the [bare-root-cwd] prefix" "0" "$unprefixed"
lines=$(wc -l <<<"$ctx" | tr -d ' ')
if (( lines <= 12 )); then ok "context block is bounded (${lines} lines)"; else bad "context block unbounded (${lines} lines)"; fi

begin P2
d="$SANDBOX/p2"; mk_plain "$d" || bad "fixture"
run_hook "$d"
eq "plain clone: silent" "" "$OUT"
eq "plain clone: exit 0" "0" "$RC"

begin P3
d="$SANDBOX/p3"; mk_plain "$d" || bad "fixture"
printf 'not a git config\n' > "$d/.git/config"
run_hook "$d"
eq "masked/corrupt config: silent" "" "$OUT"
eq "masked config: exit 0" "0" "$RC"

begin P4
d="$SANDBOX/p4"; mk_wtmask "$d" || bad "fixture"
run_hook "$d"
eq "worktreeConfig-masked bare: silent (predicate reads the config FILE)" "" "$OUT"
eq "worktreeConfig: exit 0" "0" "$RC"

begin P5
r="$SANDBOX/p5-real"; mk_bare_root "$r" || bad "fixture"
sdir="$SANDBOX/p5-sym"; mkdir -p "$sdir"
ln -s "$r/.git" "$sdir/.git"
run_hook "$sdir"
eq ".git SYMLINK to another root's .git: silent" "" "$OUT"
eq "symlinked .git: exit 0" "0" "$RC"
run_hook "$r"
eq "control: the real bare root still fires" "SessionStart" \
  "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.hookEventName // ""' 2>/dev/null)"

begin P6
d="$SANDBOX/p6"; mk_true_bare "$d" || bad "fixture"
run_hook "$d"
eq "true bare (git init --bare; mirror/server repo): silent" "" "$OUT"
eq "true bare: exit 0" "0" "$RC"

begin P7
d="$SANDBOX/p7"; mk_imposter "$d" || bad "fixture"
run_hook "$d/sub"
eq "imposter .git inside a worktree: silent (gitdir identity)" "" "$OUT"
eq "imposter: exit 0" "0" "$RC"
run_hook "$d"
eq "control: the host plain clone is also silent" "" "$OUT"

begin P8
d="$SANDBOX/p8-notrepo"; mkdir -p "$d"
run_hook "$d"
eq "not a repo: silent" "" "$OUT"
eq "not a repo: exit 0" "0" "$RC"
run_hook "$SANDBOX/p8-does-not-exist"
eq "nonexistent cwd: silent" "" "$OUT"
eq "nonexistent cwd: exit 0" "0" "$RC"

begin P9
# Dedup: target repo carries its own arm — marker file under .claude/hooks/ AND
# a settings/devin registration referencing session-rules-loader.sh. The plugin
# arm must emit nothing (the repo arm reports the session).
d="$SANDBOX/p9"; mk_bare_root "$d" || bad "fixture"
mkdir -p "$d/.claude/hooks"
printf '#!/usr/bin/env bash\n# emits SOLEUR_BARE_ROOT_CWD source=session-start\n' \
  > "$d/.claude/hooks/bare-root-cwd-guard.sh"
# The literal $CLAUDE_PROJECT_DIR inside the fixture registry is intentional —
# the dedup greps for the session-rules-loader.sh path, not for expansion.
# shellcheck disable=SC2016
printf '{"hooks":{"SessionStart":[{"matcher":"startup|resume|clear|compact","hooks":[{"type":"command","command":"\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/session-rules-loader.sh"}]}]}}' \
  > "$d/.claude/settings.json"
run_hook "$d"
eq "armed repo (marker + settings registration): plugin arm silent" "" "$OUT"
eq "dedup arm: exit 0" "0" "$RC"
mkdir -p "$d/.devin"
printf '{"hooks":{"SessionStart":[{"matcher":"","hooks":[{"type":"command","command":"bash .claude/hooks/session-rules-loader.sh"}]}]}}' \
  > "$d/.devin/config.json"
rm -f "$d/.claude/settings.json"
run_hook "$d"
eq "armed repo via .devin/config.json registration: plugin arm silent" "" "$OUT"

begin P10
# Dedup term 1 only: a vendored-but-unwired tree (marker file, NO registration)
# must still fire — over-suppression is the worse failure direction.
d="$SANDBOX/p10"; mk_bare_root "$d" || bad "fixture"
mkdir -p "$d/.claude/hooks"
printf '# SOLEUR_BARE_ROOT_CWD vendored but unwired\n' > "$d/.claude/hooks/bare-root-cwd-guard.sh"
run_hook "$d"
eq "marker file without a registration: still fires" "$MARKER" \
  "$(ctx_of "$OUT" | sed -n 1p)"

begin P11
# Dedup term 2 only: a registration without a marker-bearing hook must still fire.
d="$SANDBOX/p11"; mk_bare_root "$d" || bad "fixture"
mkdir -p "$d/.claude"
printf '{"hooks":{"SessionStart":[{"matcher":"","hooks":[{"type":"command","command":"bash .claude/hooks/session-rules-loader.sh"}]}]}}' \
  > "$d/.claude/settings.json"
run_hook "$d"
eq "registration without a marker file: still fires" "$MARKER" \
  "$(ctx_of "$OUT" | sed -n 1p)"

begin P12
# No jq on PATH: the hook must exit 0 silently (a SessionStart hook that cannot
# emit valid JSON emits nothing). Shim bin carries bash only — the jq gate is
# first, and every downstream failure path is also silent.
nj="$SANDBOX/p12-bin"; assert_fixture_dir "$nj"; mkdir -p "$nj"
ln -s "$(command -v bash)" "$nj/bash"
d="$SANDBOX/p12"; mk_bare_root "$d" || bad "fixture"
env_json=$(jq -nc --arg cwd "$d" '{cwd:$cwd}')
RC=0
OUT=$(PATH="$nj" bash "$HOOK" <<<"$env_json" 2>/dev/null) || RC=$?
eq "no jq: silent" "" "$OUT"
eq "no jq: exit 0" "0" "$RC"

begin P13
# GIT_DIR env-injection: an inherited GIT_DIR must not redirect the probe. Both
# arms mirror the repo guard's G8.
a="$SANDBOX/p13a"; mk_bare_root "$a" || bad "fixture"
p="$SANDBOX/p13b"; mk_plain "$p" || bad "fixture"
GIT_DIR="$p/.git" run_hook "$a"
eq "injected GIT_DIR (plain clone): bare root still fires" "$MARKER" \
  "$(ctx_of "$OUT" | sed -n 1p)"
GIT_DIR="$a/.git" run_hook "$p"
eq "injected GIT_DIR (bare root): plain clone not retroactively marked" "" "$OUT"

begin P14
# Envelope without .cwd: DEVIN_PROJECT_DIR is the first fallback leg.
d="$SANDBOX/p14"; mk_bare_root "$d" || bad "fixture"
RC=0
OUT=$(printf '{}' | DEVIN_PROJECT_DIR="$d" env -u CLAUDE_PROJECT_DIR -u CLAUDE_PLUGIN_ROOT bash "$HOOK" 2>/dev/null) || RC=$?
eq "no .cwd + DEVIN_PROJECT_DIR: fires" "$MARKER" "$(ctx_of "$OUT" | sed -n 1p)"

begin P15
# Second fallback leg: CLAUDE_PROJECT_DIR when DEVIN_PROJECT_DIR is empty.
d="$SANDBOX/p15"; mk_bare_root "$d" || bad "fixture"
RC=0
OUT=$(printf '{}' | CLAUDE_PROJECT_DIR="$d" env -u DEVIN_PROJECT_DIR -u CLAUDE_PLUGIN_ROOT bash "$HOOK" 2>/dev/null) || RC=$?
eq "no .cwd + CLAUDE_PROJECT_DIR: fires" "$MARKER" "$(ctx_of "$OUT" | sed -n 1p)"
# DEVIN_PROJECT_DIR outranks CLAUDE_PROJECT_DIR.
pl="$SANDBOX/p15-plain"; mk_plain "$pl" || bad "fixture"
RC=0
OUT=$(printf '{}' | DEVIN_PROJECT_DIR="$d" CLAUDE_PROJECT_DIR="$pl" env -u CLAUDE_PLUGIN_ROOT bash "$HOOK" 2>/dev/null) || RC=$?
eq "DEVIN_PROJECT_DIR beats CLAUDE_PROJECT_DIR" "$MARKER" "$(ctx_of "$OUT" | sed -n 1p)"

begin P16
# Third fallback leg: $PWD of the hook process.
d="$SANDBOX/p16"; mk_bare_root "$d" || bad "fixture"
RC=0
OUT=$(cd "$d" && printf '{}' | env -u DEVIN_PROJECT_DIR -u CLAUDE_PROJECT_DIR -u CLAUDE_PLUGIN_ROOT bash "$HOOK" 2>/dev/null) || RC=$?
eq "no .cwd + no env + PWD at the bare root: fires" "$MARKER" "$(ctx_of "$OUT" | sed -n 1p)"

begin P17
# Soleur-hint gate: the worktree-manager line appears only when
# ${CLAUDE_PLUGIN_ROOT}/skills/git-worktree/scripts/worktree-manager.sh exists.
d="$SANDBOX/p17"; mk_bare_root "$d" || bad "fixture"
wm="$PLUGIN_ROOT/skills/git-worktree/scripts/worktree-manager.sh"
[[ -f "$wm" ]] || bad "fixture: plugin worktree-manager.sh missing at $wm"
RC=0
OUT=$(jq -nc --arg cwd "$d" '{cwd:$cwd}' | CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" env -u DEVIN_PROJECT_DIR -u CLAUDE_PROJECT_DIR bash "$HOOK" 2>/dev/null) || RC=$?
ctx=$(ctx_of "$OUT")
case "$ctx" in
  *worktree-manager.sh*) ok "soleur-hint line appears when the plugin script exists" ;;
  *) bad "soleur-hint line missing with CLAUDE_PLUGIN_ROOT set ($ctx)" ;;
esac
RC=0
OUT=$(jq -nc --arg cwd "$d" '{cwd:$cwd}' | CLAUDE_PLUGIN_ROOT="$SANDBOX/no-such-plugin" env -u DEVIN_PROJECT_DIR -u CLAUDE_PROJECT_DIR bash "$HOOK" 2>/dev/null) || RC=$?
ctx=$(ctx_of "$OUT")
case "$ctx" in
  *worktree-manager*) bad "soleur-hint emitted for a CLAUDE_PLUGIN_ROOT without the script" ;;
  *) ok "soleur-hint suppressed when the plugin script is absent" ;;
esac
eq "control: marker still fires in the suppressed-hint arm" "$MARKER" "$(sed -n 1p <<<"$ctx")"

begin P18
# Separator-laden cwd: DEL + U+2028 + U+2029 in the path must not inject lines
# into the emitted block (#10395 — the hook's emit runs through the shared
# sanitizer or its built-in fallback).
d="$SANDBOX/p18"$'\x7f\xe2\x80\xa8\xe2\x80\xa9'; mk_bare_root "$d" || bad "fixture"
run_hook "$d"
ctx=$(ctx_of "$OUT")
eq "separator-laden path still detects" "$MARKER" "$(sed -n 1p <<<"$ctx")"
injected=$(sed -n '2,$p' <<<"$ctx" | grep -cv '^\[bare-root-cwd\] ' || true)
eq "injected separators cannot forge an unprefixed line" "0" "$injected"
case "$ctx" in
  *$'\x7f'*|*$'\xe2\x80\xa8'*|*$'\xe2\x80\xa9'*) bad "context carries a separator byte from the path" ;;
  *) ok "DEL/LS/PS stripped from the emitted path" ;;
esac

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
if (( FAIL > 0 )); then printf 'failures:\n' >&2; printf '  %s\n' "${FAILURES[@]}" >&2; exit 1; fi
exit 0
