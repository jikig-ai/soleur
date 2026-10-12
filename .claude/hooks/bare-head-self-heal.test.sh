#!/usr/bin/env bash
# Tests for .claude/hooks/bare-head-self-heal.sh (helper cases H1-H10) and its wiring in
# .claude/hooks/session-rules-loader.sh (loader cases L1-L3).
#
# Synthesized fixtures only: throwaway repos under one mktemp root, built with git plumbing
# (hash-object / commit-tree / update-ref) so no fixture needs a commit identity of its own.
# No `set -e`: this is an accumulate-then-exit suite, and every deliberately non-zero call is
# captured with `rc=0; x=$(...) || rc=$?` so a failing call cannot abort before it is reported.

set -uo pipefail

SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT

# Redirect incident telemetry into a per-suite sandbox BEFORE any case runs. Sourced after the
# EXIT trap above on purpose: the lib composes with a trap that already exists.
SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
. "$SCRIPT_DIR/lib/test-incident-sandbox.sh"

HELPER="$SCRIPT_DIR/bare-head-self-heal.sh"
LOADER="$SCRIPT_DIR/session-rules-loader.sh"
MARKER_GONE="SOLEUR_BARE_HEAD_HEALED from=refs/heads/gone to=refs/heads/main"

# The shared fixture git environment: sweeps every inherited GIT_* location variable (a hook-
# exported GIT_DIR would otherwise aim these writes at the caller's repo), pins a ceiling,
# config and identity.
# shellcheck source=../../plugins/soleur/test/lib/git-fixture-env.sh
source "$SCRIPT_DIR/../../plugins/soleur/test/lib/git-fixture-env.sh"
git_fixture_env "$SANDBOX" || { printf '[FATAL] git_fixture_env refused %s\n' "$SANDBOX" >&2; exit 2; }

# Refuse before writing, rather than let an empty operand retarget a git write at whatever
# repository the caller happens to be standing in. `git -C ""` does NOT error — it silently
# operates on the current directory, which under TEST_GROUP=scripts is the developer's live
# worktree, whose `.git/config` is the SHARED file every worktree on the machine inherits.
#
# Rejects, beyond empty: bare `/` AND its aliases `//` and `/.` (a `/*` arm accepts all three, and
# `rm -rf "/"/*` is the worst outcome in this corpus — a one-character bypass of a stated
# rejection); any path containing `..`, which can resolve back inside the real repo; and
# /proc, /sys, /dev, because `/proc/self/cwd` is absolute, passes every other arm, and resolves
# to precisely "whatever repository the caller happens to be standing in".
#
# Still no `realpath`: it breaks on a symlinked /tmp, which this corpus uses. So a symlink to
# $HOME is ACCEPTED — stated here rather than left implied, because the arms above make this
# look like a containment check and it is not.
#
# The body below is a COPY. The canonical definition lives in
# plugins/soleur/test/test-helpers.sh; plugins/soleur/test/fixture-dir-operand-assert.test.sh
# asserts this copy is byte-equal to it. Do not reword it in one file only. #7652
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

command -v jq >/dev/null 2>&1 || { echo "UNRESOLVED: jq missing — this suite asserted nothing; install jq"; exit 3; }
command -v git >/dev/null 2>&1 || { echo "UNRESOLVED: git missing — this suite asserted nothing; install git"; exit 3; }
if [[ ! -f "$HELPER" ]]; then
  echo "FAIL: $HELPER missing — GREEN required"
  exit 1
fi
if [[ ! -x "$LOADER" ]]; then
  echo "FAIL: $LOADER not executable or missing"
  exit 1
fi

# --- accounting ---------------------------------------------------------------------------
PASS=0
FAIL=0
FAILURES=()
EXECUTED=()
CUR=""
CASE_N=0
EMPTY_CASES=()

# A case that executed no assertion is an empty case, whatever the totals say.
close_case() {
  if [[ -n "$CUR" ]] && (( CASE_N == 0 )); then EMPTY_CASES+=("$CUR"); fi
}
begin() { close_case; EXECUTED+=("$1"); CUR="$1"; CASE_N=0; }
ok() { PASS=$((PASS + 1)); CASE_N=$((CASE_N + 1)); printf '  ok   %s: %s\n' "$CUR" "$1"; }
bad() { FAIL=$((FAIL + 1)); CASE_N=$((CASE_N + 1)); FAILURES+=("$CUR: $1"); printf '  FAIL %s: %s\n' "$CUR" "$1"; }
eq() {
  if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1 (expected [$2], got [$3])"; fi
}

# Instrument self-test: drive each verdict helper once and require its counter to move. A helper
# that silently stopped counting would otherwise report an empty suite as a clean one.
_p=$PASS
_f=$FAIL
CUR="selftest"
ok "selftest-pass" >/dev/null
bad "selftest-fail" >/dev/null
eq "selftest-eq-pass" "a" "a" >/dev/null
eq "selftest-eq-fail" "a" "b" >/dev/null
if (( PASS != _p + 2 || FAIL != _f + 2 )); then
  printf 'FATAL: instrument self-test: ok/bad/eq did not move their counters\n' >&2
  exit 1
fi
PASS=$_p
FAIL=$_f
FAILURES=()
CUR=""
CASE_N=0

# --- fixture builders -----------------------------------------------------------------------
# seed_main <dir> [extra-branch]: one empty-tree commit on refs/heads/main (and on the extra
# branch), through plumbing only.
seed_main() {
  local d="$1" t c
  assert_fixture_dir "$d"
  t=$(git -C "$d" hash-object -t tree -w /dev/null) || return 1
  c=$(git -C "$d" commit-tree "$t" -m seed) || return 1
  git -C "$d" update-ref refs/heads/main "$c" || return 1
  if [[ -n "${2:-}" ]]; then
    git -C "$d" update-ref "refs/heads/$2" "$c" || return 1
  fi
}

# mk_bare_root: the real layout — a normal repo with a `.git` directory and on-disk files, then
# `core.bare true`.
mk_bare_root() {
  local d="$1"
  assert_fixture_dir "$d"
  mkdir -p "$d"
  git -C "$d" init -q || return 1
  seed_main "$d" "${2:-}" || return 1
  git -C "$d" symbolic-ref HEAD refs/heads/main || return 1
  git -C "$d" config core.bare true || return 1
}

# mk_true_bare: `git init --bare`, gitdir == dir (the second bare shape).
mk_true_bare() {
  local d="$1"
  assert_fixture_dir "$d"
  git init -q --bare "$d" || return 1
  seed_main "$d" || return 1
  git -C "$d" symbolic-ref HEAD refs/heads/main || return 1
}

mk_plain() {
  local d="$1"
  assert_fixture_dir "$d"
  mkdir -p "$d"
  git -C "$d" init -q || return 1
  seed_main "$d" || return 1
  git -C "$d" symbolic-ref HEAD refs/heads/main || return 1
}

dangle() {
  assert_fixture_dir "$1"
  git -C "$1" symbolic-ref HEAD refs/heads/gone
}

head_of() {
  local r
  assert_fixture_dir "$1"
  r=$(git -C "$1" symbolic-ref -q HEAD || printf '<detached>')
  printf '%s' "$r"
}

# run_helper <dir>: sets OUT (stdout) and RC (exit status).
run_helper() {
  RC=0
  OUT=$(bash "$HELPER" "$1" 2>/dev/null) || RC=$?
}

# --- helper cases ---------------------------------------------------------------------------
echo "bare-head-self-heal.test.sh"

begin H1
d="$SANDBOX/h1"; mk_bare_root "$d" || bad "fixture"
dangle "$d"
run_helper "$d"
eq "marker is exactly one line in the documented format" "$MARKER_GONE" "$OUT"
eq "HEAD now names main" "refs/heads/main" "$(head_of "$d")"
eq "exit status is 0" "0" "$RC"

begin H2
d="$SANDBOX/h2"; mk_bare_root "$d" || bad "fixture"
dangle "$d"
run_helper "$d"
eq "first run heals (precondition for idempotency)" "$MARKER_GONE" "$OUT"
run_helper "$d"
eq "second run is silent (idempotent)" "" "$OUT"
eq "HEAD still main" "refs/heads/main" "$(head_of "$d")"
eq "exit status is 0" "0" "$RC"

begin H3
d="$SANDBOX/h3"; mk_bare_root "$d" || bad "fixture"
run_helper "$d"
eq "healthy main: silent" "" "$OUT"
eq "HEAD unchanged" "refs/heads/main" "$(head_of "$d")"

begin H4
d="$SANDBOX/h4"; mk_bare_root "$d" feat || bad "fixture"
git -C "$d" symbolic-ref HEAD refs/heads/feat
run_helper "$d"
eq "healthy non-main: silent" "" "$OUT"
eq "a resolving HEAD is never touched, even when it is not main" "refs/heads/feat" "$(head_of "$d")"

begin H5
d="$SANDBOX/h5"; mk_plain "$d" || bad "fixture"
dangle "$d"
run_helper "$d"
eq "non-bare repo: silent" "" "$OUT"
eq "non-bare HEAD untouched" "refs/heads/gone" "$(head_of "$d")"

begin H6
d="$SANDBOX/h6"; mk_bare_root "$d" other || bad "fixture"
git -C "$d" update-ref -d refs/heads/main
dangle "$d"
run_helper "$d"
eq "main missing: silent" "" "$OUT"
eq "nothing safe to point at: HEAD untouched" "refs/heads/gone" "$(head_of "$d")"

begin H7
root="$SANDBOX/h7"; mk_bare_root "$root" || bad "fixture"
wt="$SANDBOX/h7-wt"
git -C "$root" worktree add -q -b wtbranch "$wt" main || bad "worktree fixture"
git -C "$root" update-ref -d refs/heads/wtbranch
dangle "$root"
run_helper "$wt"
eq "linked worktree: silent" "" "$OUT"
eq "worktree's own dangling HEAD untouched" "refs/heads/wtbranch" "$(head_of "$wt")"
eq "root HEAD untouched" "refs/heads/gone" "$(head_of "$root")"

begin H8
d="$SANDBOX/h8"; mk_bare_root "$d" || bad "fixture"
sha=$(git -C "$d" rev-parse main)
git -C "$d" update-ref --no-deref HEAD "$sha"
run_helper "$d"
eq "detached HEAD: silent" "" "$OUT"
eq "still detached" "<detached>" "$(head_of "$d")"
eq "detached commit unchanged" "$sha" "$(git -C "$d" rev-parse HEAD)"

begin H9
d="$SANDBOX/h9-notrepo"; mkdir -p "$d"
run_helper "$d"
eq "not a repo: silent" "" "$OUT"
eq "not a repo: exit status is 0" "0" "$RC"
d="$SANDBOX/h9-lock"; mk_bare_root "$d" || bad "fixture"
dangle "$d"
: > "$d/.git/HEAD.lock"
run_helper "$d"
eq "lock held: no false marker" "" "$OUT"
eq "lock held: exit status is 0" "0" "$RC"
eq "lock held: HEAD unchanged" "refs/heads/gone" "$(head_of "$d")"

begin H10
d="$SANDBOX/h10"; mk_true_bare "$d" || bad "fixture"
dangle "$d"
run_helper "$d"
eq "true bare (a mirror or server repo, not this layout): silent" "" "$OUT"
eq "true bare HEAD untouched" "refs/heads/gone" "$(head_of "$d")"

begin H11
d="$SANDBOX/h11"; mk_bare_root "$d" feat || bad "fixture"
git -C "$d" symbolic-ref HEAD refs/heads/feat
git -C "$d" pack-refs --all
run_helper "$d"
eq "healthy HEAD naming a PACKED ref: silent" "" "$OUT"
eq "packed healthy HEAD untouched" "refs/heads/feat" "$(head_of "$d")"

begin H12
d="$SANDBOX/h12"; mk_bare_root "$d" || bad "fixture"
git -C "$d" pack-refs --all
dangle "$d"
run_helper "$d"
eq "dangling HEAD with a PACKED main: healed" "$MARKER_GONE" "$OUT"
eq "HEAD names main" "refs/heads/main" "$(head_of "$d")"

begin H13
d="$SANDBOX/h13"; mk_bare_root "$d" broken || bad "fixture"
printf '0000000000000000000000000000000000000001\n' > "$d/.git/refs/heads/broken"
git -C "$d" symbolic-ref HEAD refs/heads/broken
run_helper "$d"
eq "a ref that EXISTS but names a missing object is corruption, not dangling: silent" "" "$OUT"
eq "corrupt-target HEAD untouched" "refs/heads/broken" "$(head_of "$d")"

begin H14
d="$SANDBOX/h14"; mk_bare_root "$d" || bad "fixture"
git -C "$d" symbolic-ref HEAD refs/tags/gone
run_helper "$d"
eq "HEAD naming a tag ref (not a branch): silent" "" "$OUT"
eq "tag-ref HEAD untouched" "refs/tags/gone" "$(head_of "$d")"

begin H15
real="$SANDBOX/h15-real"; mk_true_bare "$real" || bad "fixture"
dangle "$real"
stub="$SANDBOX/h15-stub"; mkdir -p "$stub"
printf 'gitdir: %s\n' "$real" > "$stub/.git"
run_helper "$stub"
eq "a .git FILE redirecting to another repo: silent" "" "$OUT"
eq "the redirect target is untouched" "refs/heads/gone" "$(head_of "$real")"

begin H16
a="$SANDBOX/h16a"; mk_bare_root "$a" || bad "fixture"
dangle "$a"
b="$SANDBOX/h16b"; mk_bare_root "$b" || bad "fixture"
dangle "$b"
RC=0
OUT=$(GIT_DIR="$b/.git" bash "$HELPER" "$a" 2>/dev/null) || RC=$?
eq "inherited GIT_DIR: the NAMED repo is the one healed" "$MARKER_GONE" "$OUT"
eq "named repo HEAD now main" "refs/heads/main" "$(head_of "$a")"
eq "the GIT_DIR repo is untouched" "refs/heads/gone" "$(head_of "$b")"

begin H17
d="$SANDBOX/h17"; mk_bare_root "$d" || bad "fixture"
ran="$SANDBOX/h17-hook-ran"
mkdir -p "$d/.git/hooks"
printf '#!/bin/sh\ntouch "%s"\n' "$ran" > "$d/.git/hooks/reference-transaction"
chmod +x "$d/.git/hooks/reference-transaction"
dangle "$d"
if [[ -e "$ran" ]]; then ok "control: the hook fires on a symbolic-ref HEAD write (the fixture's own dangle)"; else bad "control: the hook did not fire on symbolic-ref, so the assertion below proves nothing"; fi
rm -f "$ran"
run_helper "$d"
eq "heal still happens" "$MARKER_GONE" "$OUT"
if [[ -e "$ran" ]]; then bad "a repository-controlled reference-transaction hook ran"; else ok "no repository hook ran during the repair"; fi
d="$SANDBOX/h17b"; mk_bare_root "$d" || bad "fixture"
ran="$SANDBOX/h17b-hook-ran"
mkdir -p "$d/hp"
printf '#!/bin/sh\ntouch "%s"\n' "$ran" > "$d/hp/reference-transaction"
chmod +x "$d/hp/reference-transaction"
git -C "$d" config core.hooksPath "$d/hp"
dangle "$d"
if [[ -e "$ran" ]]; then ok "control: a repo-config core.hooksPath hook fires on the fixture's own write"; else bad "control: the core.hooksPath hook did not fire, so the assertion below proves nothing"; fi
rm -f "$ran"
run_helper "$d"
eq "heal still happens with a repo-config hooksPath" "$MARKER_GONE" "$OUT"
if [[ -e "$ran" ]]; then bad "a core.hooksPath hook ran during the repair"; else ok "no core.hooksPath hook ran during the repair"; fi

begin H18
d="$SANDBOX/h18"; mk_bare_root "$d" || bad "fixture"
git -C "$d" symbolic-ref HEAD "$(printf 'refs/heads/a\xe2\x80\xa8b')" || bad "fixture: git rejected the Unicode ref name"
run_helper "$d"
eq "a U+2028 in the old ref name is dropped from the marker" "SOLEUR_BARE_HEAD_HEALED from=refs/heads/ab to=refs/heads/main" "$OUT"

begin H19
b="$SANDBOX/h19b"; mk_bare_root "$b" || bad "fixture"
dangle "$b"
RC=0
OUT=$(cd "$b" && bash "$HELPER" "$SANDBOX/h19-does-not-exist" 2>/dev/null) || RC=$?
eq "nonexistent dir: silent (a failed cd must not fall through to the caller's own repo)" "" "$OUT"
eq "nonexistent dir: exit status is 0" "0" "$RC"
eq "the repo the caller stood in is untouched" "refs/heads/gone" "$(head_of "$b")"

begin H20
p="$SANDBOX/h20"; mk_bare_root "$p" || bad "fixture"
dangle "$p"
mkdir -p "$p/sub/.git"
printf '[core]\n\tbare = true\n' > "$p/sub/.git/config"
run_helper "$p/sub"
eq "a skeleton .git (config only) nested under a dangling bare root: silent" "" "$OUT"
eq "the parent root HEAD is untouched" "refs/heads/gone" "$(head_of "$p")"

begin H21
r="$SANDBOX/h21-real"; mk_bare_root "$r" || bad "fixture"
dangle "$r"
sdir="$SANDBOX/h21-sym"; mkdir -p "$sdir"
ln -s "$r/.git" "$sdir/.git"
run_helper "$sdir"
eq "a .git SYMLINK to another root's .git: silent" "" "$OUT"
eq "the symlink target's HEAD is untouched" "refs/heads/gone" "$(head_of "$r")"

begin H22
d="$SANDBOX/h22"; mk_bare_root "$d" || bad "fixture"
git -C "$d" symbolic-ref HEAD "refs/heads/Feat_1.x-y"
run_helper "$d"
eq "every allowlisted character class survives into the marker" "SOLEUR_BARE_HEAD_HEALED from=refs/heads/Feat_1.x-y to=refs/heads/main" "$OUT"
d="$SANDBOX/h22b"; mk_bare_root "$d" || bad "fixture"
long="refs/heads/$(printf 'a%.0s' $(seq 1 100))/$(printf 'b%.0s' $(seq 1 100))/$(printf 'c%.0s' $(seq 1 100))"
git -C "$d" symbolic-ref HEAD "$long"
run_helper "$d"
eq "an over-long old ref name is capped at 80 characters" "SOLEUR_BARE_HEAD_HEALED from=${long:0:80} to=refs/heads/main" "$OUT"

# --- loader cases ---------------------------------------------------------------------------
# Pin the ambient state the loader reads, so the "marker is the trailing line" assertion does not
# depend on whether the host happens to carry a tmpfs-guard alarm: a populated alarm file makes the
# alarm block ALWAYS present, which is the only arrangement under which the ordering is observable.
ALARM_FILE="$SANDBOX/tmpfs-alarms.log"
HEARTBEAT_FILE="$SANDBOX/tmpfs-heartbeat"
printf '2026-01-01T00:00:00Z fixture alarm\n' > "$ALARM_FILE"
: > "$HEARTBEAT_FILE"
export TMPFS_GUARD_ALARM_FILE="$ALARM_FILE" TMPFS_GUARD_HEARTBEAT_FILE="$HEARTBEAT_FILE"

# A rule-corpus fixture committed BEFORE `core.bare true` (git add refuses once it is set), so the
# root carries the on-disk files a synced bare root carries.
mk_loader_root() {
  local d="$1"
  assert_fixture_dir "$d"
  mkdir -p "$d"
  git -C "$d" init -q || return 1
  git -C "$d" symbolic-ref HEAD refs/heads/main || return 1
  cat > "$d/AGENTS.rules.md" <<'RULES'
# AGENTS Rules
## Hard Rules
- Core rule [id: hr-test-core].
RULES
  cat > "$d/AGENTS.md" <<'IDX'
# Index
## Hard Rules
- [id: hr-test-core]
IDX
  git -C "$d" add . || return 1
  git -C "$d" commit -q -m baseline || return 1
  git -C "$d" config core.bare true || return 1
}

# invoke_loader <loader> <cwd>: sets LOUT (raw stdout), LRC and CTX (additionalContext).
invoke_loader() {
  local loader="$1" cwd="$2" payload
  payload=$(jq -nc --arg cwd "$cwd" '{cwd: $cwd, session_id: "heal-test"}')
  LRC=0
  LOUT=$(printf '%s' "$payload" | "$loader" 2>/dev/null) || LRC=$?
  CTX=$(jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$LOUT" 2>/dev/null) || CTX=""
}

# no_fallback <ctx>: line 1 must be the normal stamp, never the ERR-trap FALLBACK envelope.
no_fallback() {
  case "$(sed -n 1p <<<"$1")" in
    *FALLBACK*) bad "the loader degraded to its FALLBACK envelope" ;;
    *) ok "the loader did not degrade to its FALLBACK envelope" ;;
  esac
}

count_marker() {
  awk '/^SOLEUR_BARE_HEAD_HEALED /{n++} END{print n+0}' <<<"$1"
}

begin L1
d="$SANDBOX/l1"; mk_loader_root "$d" || bad "fixture"
dangle "$d"
invoke_loader "$LOADER" "$d"
line3=$(sed -n 3p <<<"$CTX")
case "$line3" in
  "[session-context] branch: main |"*) ok "branch line reads main, not HEAD" ;;
  *) bad "branch line reads [$line3]" ;;
esac
eq "marker present exactly once" "1" "$(count_marker "$CTX")"
last=$(tail -n 1 <<<"$CTX")
eq "marker is the trailing line" "$MARKER_GONE" "$last"
case "$CTX" in
  *"[tmpfs-guard] /tmp alarm, most recent: 2026-01-01T00:00:00Z fixture alarm"*) ok "the alarm block is present, so the marker's position AFTER it is observable" ;;
  *) bad "the alarm block is missing: the ordering assertion above is vacuous" ;;
esac
case "$CTX" in
  *"hr-test-core"*) ok "rule bodies still load" ;;
  *) bad "rule bodies missing from context" ;;
esac
invoke_loader "$LOADER" "$d"
eq "second invocation exits 0" "0" "$LRC"
eq "second invocation emits no marker" "0" "$(count_marker "$CTX")"
case "$(sed -n 3p <<<"$CTX")" in
  "[session-context] branch: main |"*) ok "second invocation still reads branch main" ;;
  *) bad "second invocation branch line is wrong" ;;
esac

begin L2
d="$SANDBOX/l2"; mk_loader_root "$d" || bad "fixture"
invoke_loader "$LOADER" "$d"
eq "healthy bare root: no marker" "0" "$(count_marker "$CTX")"
case "$CTX" in
  *"hr-test-core"*) ok "rule bodies load" ;;
  *) bad "rule bodies missing from context" ;;
esac

begin L3
d="$SANDBOX/l3-repo"; mk_loader_root "$d" || bad "fixture"
dangle "$d"
copy="$SANDBOX/l3-copy/.claude/hooks"
assert_fixture_dir "$copy"
mkdir -p "$copy"
cp "$LOADER" "$copy/session-rules-loader.sh"
printf '#!/usr/bin/env bash\nprintf "junk line\\nINJECTED\\n"\nexit 7\n' > "$copy/bare-head-self-heal.sh"
chmod +x "$copy/session-rules-loader.sh" "$copy/bare-head-self-heal.sh"
invoke_loader "$copy/session-rules-loader.sh" "$d"
eq "stub exits 7: loader exits 0" "0" "$LRC"
case "$(sed -n 1p <<<"$CTX")" in
  *FALLBACK*) bad "a failing helper degraded the loader to its FALLBACK envelope" ;;
  *) ok "a failing helper did not trip the loader's ERR trap" ;;
esac
case "$(sed -n 3p <<<"$CTX")" in
  "[session-context] branch:"*) ok "the session-context line is still on line 3" ;;
  *) bad "line 3 is not the session-context line" ;;
esac
if jq -e '.hookSpecificOutput.additionalContext' <<<"$LOUT" >/dev/null 2>&1; then
  ok "envelope is valid JSON"
else
  bad "envelope is not valid JSON"
fi
case "$CTX" in
  *"hr-test-core"*) ok "rule bodies still load under a failing helper" ;;
  *) bad "rule bodies missing under a failing helper" ;;
esac
case "$CTX" in
  *"junk line"*|*INJECTED*) bad "helper junk reached the context" ;;
  *) ok "helper junk did not reach the context" ;;
esac
eq "no marker from a non-marker helper" "0" "$(count_marker "$CTX")"
printf '#!/usr/bin/env bash\nprintf "SOLEUR_BARE_HEAD_HEALED from=x to=y\\nINJECTED\\n"\nexit 0\n' > "$copy/bare-head-self-heal.sh"
invoke_loader "$copy/session-rules-loader.sh" "$d"
eq "only the first helper line is taken as the marker" "1" "$(count_marker "$CTX")"
eq "the marker taken is exactly the helper's first line" "SOLEUR_BARE_HEAD_HEALED from=x to=y" "$(tail -n 1 <<<"$CTX")"
case "$CTX" in
  *INJECTED*) bad "a second helper line reached the context" ;;
  *) ok "a second helper line did not reach the context" ;;
esac
printf '#!/usr/bin/env bash\nprintf "SOLEUR_BARE_HEAD_HEALEDX from=x to=y\\n"\nexit 0\n' > "$copy/bare-head-self-heal.sh"
invoke_loader "$copy/session-rules-loader.sh" "$d"
case "$CTX" in
  *SOLEUR_BARE_HEAD_HEALEDX*) bad "a near-miss prefix (no space) was accepted as the marker" ;;
  *) ok "a near-miss prefix was rejected" ;;
esac

begin L4
d="$SANDBOX/l4-repo"; mk_loader_root "$d" || bad "fixture"
dangle "$d"
copy="$SANDBOX/l4-copy/.claude/hooks"
assert_fixture_dir "$copy"
mkdir -p "$copy"
cp "$LOADER" "$copy/session-rules-loader.sh"
chmod +x "$copy/session-rules-loader.sh"
invoke_loader "$copy/session-rules-loader.sh" "$d"
eq "no helper beside the loader (a stale bare-root copy): loader exits 0" "0" "$LRC"
no_fallback "$CTX"
case "$CTX" in
  *"hr-test-core"*) ok "rule bodies still load without the helper" ;;
  *) bad "rule bodies missing without the helper" ;;
esac
eq "no marker without the helper" "0" "$(count_marker "$CTX")"

begin L5
if command -v timeout >/dev/null 2>&1; then
  d="$SANDBOX/l5-repo"; mk_loader_root "$d" || bad "fixture"
  copy="$SANDBOX/l5-copy/.claude/hooks"
  assert_fixture_dir "$copy"
  mkdir -p "$copy"
  cp "$LOADER" "$copy/session-rules-loader.sh"
  printf '#!/usr/bin/env bash\nsleep 60\n' > "$copy/bare-head-self-heal.sh"
  chmod +x "$copy/session-rules-loader.sh" "$copy/bare-head-self-heal.sh"
  t0=$SECONDS
  SOLEUR_BARE_HEAL_TIMEOUT_S=2 invoke_loader "$copy/session-rules-loader.sh" "$d"
  elapsed=$((SECONDS - t0))
  eq "a hung helper: loader still exits 0" "0" "$LRC"
  no_fallback "$CTX"
  if (( elapsed < 20 )); then ok "a hung helper is cut off by the timeout (took ${elapsed}s, not 60s)"; else bad "a hung helper stalled the loader for ${elapsed}s"; fi
  case "$CTX" in
    *"hr-test-core"*) ok "rule bodies still load after a hung helper" ;;
    *) bad "rule bodies missing after a hung helper" ;;
  esac
else
  ok "skipped: no timeout binary on this host (the loader then runs the helper untimed)"
fi

# --- completion floors ------------------------------------------------------------------------
close_case
DECLARED=(H1 H2 H3 H4 H5 H6 H7 H8 H9 H10 H11 H12 H13 H14 H15 H16 H17 H18 H19 H20 H21 H22 L1 L2 L3 L4 L5)
if [[ "${EXECUTED[*]}" != "${DECLARED[*]}" ]]; then
  printf 'FATAL: declared cases differ from executed cases\n  declared: %s\n  executed: %s\n' \
    "${DECLARED[*]}" "${EXECUTED[*]}" >&2
  exit 1
fi
if (( ${#EMPTY_CASES[@]} > 0 )); then
  printf 'FATAL: cases that executed no assertion: %s\n' "${EMPTY_CASES[*]}" >&2
  exit 1
fi
if (( PASS + FAIL == 0 )); then
  printf 'FATAL: zero assertions executed — this run asserted nothing\n' >&2
  exit 1
fi

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
if (( FAIL > 0 )); then
  printf 'FAILED:\n'
  printf '  %s\n' "${FAILURES[@]}"
  exit 1
fi
exit 0
