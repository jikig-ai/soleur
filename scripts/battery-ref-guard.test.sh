#!/usr/bin/env bash
# Guard for the ref-store STATE PREDICATE (#7917, AP-025).
#
# `scripts/hooks/battery-ref-guard/reference-transaction` refuses a refs/tags/* CREATE in the live
# repository for the duration of a gate run. This suite DRIVES it: a presence grep pins spelling,
# and the property here is behaviour.
#
# WHY MOST ARMS FEED THE HOOK ON STDIN. The hook's contract IS its stdin format
# (`<old> <new> <ref>` per line, phase in $1), so the predicate can be tested without git at all.
# That is not merely cheaper — every real `git tag` in this file is a tag-authoring SOURCE SITE
# that `scripts/battery-tag-authorship.test.sh` must then see declared in its ledger, against a
# ceiling ADR-207 §5 governs. Driving the predicate directly keeps that cost at the two arms that
# genuinely need it: the ones proving GIT invokes the hook at all. Holding the verb in a variable
# to duck the census would be under-approximation #7 in that guard's header — invisible by
# construction — so the two wiring sites are declared, not hidden.
#
# THE MUTATION ARM IS THE POINT. Every assertion below is also satisfied by a hook that refuses
# NOTHING, because the tree is clean. So the suite removes the hook and asserts the refusal STOPS.
set -uo pipefail

REPO_ROOT="${BATTERY_REF_REPO_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
case "$REPO_ROOT" in
  /*) : ;;
  *) printf 'ERROR: REPO_ROOT is not absolute (%s)\n' "$REPO_ROOT" >&2; exit 2 ;;
esac
HOOK="$REPO_ROOT/scripts/hooks/battery-ref-guard/reference-transaction"
HOOK_DIR="$REPO_ROOT/scripts/hooks/battery-ref-guard"
RUNNER="$REPO_ROOT/scripts/test-all.sh"
Z=0000000000000000000000000000000000000000
S=1111111111111111111111111111111111111111

passes=0
fails=0
asserted=0
ck() { asserted=$((asserted + 1)); }
pass() { passes=$((passes + 1)); printf '  [ok] %s\n' "$1"; }
fail() { fails=$((fails + 1)); printf '  [FAIL] %s\n' "$1" >&2; }

_p=$passes; _f=$fails; _a=$asserted
{ pass st; fail st; ck; } >/dev/null 2>&1
if (( passes != _p + 1 || fails != _f + 1 || asserted != _a + 1 )); then
  printf '\n[FATAL] helper self-test: pass()/fail()/ck() did not each move their OWN counter\n' >&2
  exit 1
fi
passes=$_p; fails=$_f; asserted=$_a

WORK="$(mktemp -d -t battrefguard.XXXXXXXX)" || { printf 'FATAL: cannot create scratch root\n' >&2; exit 2; }
[[ "$WORK" == /* && -d "$WORK" ]] || { printf 'FATAL: scratch root is not absolute\n' >&2; exit 2; }
trap 'rm -rf "$WORK"' EXIT INT TERM

# drive <cwd> <live-common-or-empty> <old> <new> <ref> -> rc
drive() {
  local rc=0
  # `env -u` FIRST, always. Under a real gate run this suite INHERITS the arming test-all.sh
  # exported, so an arm passing "" for $2 would still see the ambient value and the "unarmed ⇒
  # inert" row would test the armed path instead. Measured: this suite went rc=0 -> rc=1 the
  # moment it was run under the arming it exists to describe.
  ( cd "$1" && printf '%s %s %s\n' "$3" "$4" "$5" \
      | env -u BATTERY_TAG_LIVE_COMMON_DIR ${2:+BATTERY_TAG_LIVE_COMMON_DIR="$2"} \
        bash "$HOOK" prepared >/dev/null 2>&1 ) || rc=$?
  printf '%s' "$rc"
}

printf '=== battery-ref-guard: the ref-store state predicate ===\n'

ck; if [[ -x "$HOOK" ]]; then pass "hook exists and is executable"
else fail "hook missing or not executable at $HOOK"; fi

# The runner must ARM it. Anchored on the export WITH its value, on comment-stripped source, so
# the prose above the arming block (which names the same variable) cannot satisfy this.
ck; _armed="$({ sed 's/[[:space:]]*#.*$//' "$RUNNER" || true; } | grep -cE '^[[:space:]]*export GIT_CONFIG_VALUE_0="\$_bt_hookdir"')"
if [[ "$_armed" == "1" ]]; then pass "scripts/test-all.sh arms the predicate exactly once"
else fail "scripts/test-all.sh arms the predicate $_armed time(s), expected exactly 1"; fi

# THE ARMING MUST NOT NAME A TRACKED PATH. lefthook auto-installs into whatever core.hooksPath
# names; an earlier revision pointed it at scripts/hooks/battery-ref-guard, so a full gate run
# ended with an untracked pre-commit in the repository and the write-boundary sentinel firing
# "[FATAL] A SUITE WROTE TO THE LIVE REPOSITORY". Nothing installs hooks during a single suite,
# so only a full gate run surfaced it — which is exactly why it is pinned here now.
ck; _hookval="$({ sed 's/[[:space:]]*#.*$//' "$RUNNER" || true; } | grep -oE '^[[:space:]]*export GIT_CONFIG_VALUE_0=.*' | head -1)"
if [[ -n "$_hookval" && "$_hookval" != *scripts/hooks* && "$_hookval" != *'$PWD'* ]]; then
  pass "the arming points at a run-scoped dir, not a tracked path (lefthook cannot install into the repo)"
else
  fail "the arming names a tracked path ($_hookval) — lefthook will install into the repository and trip the write boundary"
fi

# --- predicate arms, no git required ---------------------------------------------------------
LIVE_COMMON="$(cd "$(git -C "$REPO_ROOT" rev-parse --git-common-dir)" && pwd -P)"

ck; if [[ "$(drive "$REPO_ROOT" "$LIVE_COMMON" "$Z" "$S" refs/tags/x)" != "0" ]]; then
  pass "armed: a refs/tags CREATE in the live store is REFUSED"
else fail "armed: a refs/tags CREATE in the live store was allowed — the predicate is inert"; fi

# BOTH operands are load-bearing. Measured on git 2.53.0 a DELETE arrives zero->ZERO (not
# sha->zero), so a one-operand `old == zero` test refuses deletes; an earlier revision of this
# hook did exactly that while its comment claimed deletes were out of scope.
ck; if [[ "$(drive "$REPO_ROOT" "$LIVE_COMMON" "$Z" "$Z" refs/tags/x)" == "0" ]]; then
  pass "armed: a refs/tags DELETE (zero->zero) is allowed — a different ADR-207 cell"
else fail "armed: a DELETE was refused — the CREATE discriminator is reading one operand"; fi

ck; if [[ "$(drive "$REPO_ROOT" "$LIVE_COMMON" "$S" "$S" refs/tags/x)" == "0" ]]; then
  pass "armed: a refs/tags MOVE (sha->sha) is allowed — a different ADR-207 cell"
else fail "armed: a MOVE was refused — over-broad"; fi

ck; if [[ "$(drive "$REPO_ROOT" "$LIVE_COMMON" "$Z" "$S" refs/heads/x)" == "0" ]]; then
  pass "armed: a refs/heads CREATE is allowed — this hook owns tags only"
else fail "armed: a branch create was refused — the ref namespace filter is wrong"; fi

ck; if [[ "$(drive "$REPO_ROOT" "" "$Z" "$S" refs/tags/x)" == "0" ]]; then
  pass "unarmed: with BATTERY_TAG_LIVE_COMMON_DIR unset the hook is inert"
else fail "unarmed: the hook refused outside a gate run"; fi

# Fixture discrimination, still without authoring a tag: a repo whose common dir differs.
git init -q "$WORK/fixture" && git -C "$WORK/fixture" config user.email t@t && git -C "$WORK/fixture" config user.name t
ck; if [[ "$(drive "$WORK/fixture" "$LIVE_COMMON" "$Z" "$S" refs/tags/x)" == "0" ]]; then
  pass "armed: a refs/tags CREATE in a DIFFERENT ref store is allowed (sandboxes unaffected)"
else fail "armed: a CREATE in a different ref store was refused — this breaks fixture suites"; fi

# --- wiring arms: does GIT actually invoke it? ------------------------------------------------
# The two declared tag-authoring sites in this file. ONE source line each, called under different
# hook directories so the mutation arm reuses the same site rather than adding a third.
echo x > "$WORK/fixture/f"; git -C "$WORK/fixture" add -A; git -C "$WORK/fixture" commit -qm one >/dev/null 2>&1

try_tag() {
  local rc=0
  local -a e=(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath "GIT_CONFIG_VALUE_0=$2" "BATTERY_TAG_LIVE_COMMON_DIR=$3")
  # repo-boundary-tag-exempt: the wiring proof — it MUST run through real git, since the claim is
  # that git invokes the hook, and it targets a mktemp fixture with that fixture's OWN common dir.
  env "${e[@]}" git -C "$WORK/fixture" tag -a -m m "$1" >/dev/null 2>&1 || rc=$?
  printf '%s' "$rc"
}

FIX_COMMON="$(cd "$WORK/fixture/.git" && pwd -P)"

ck; if [[ "$(try_tag wired "$HOOK_DIR" "$FIX_COMMON")" != "0" ]] && ! git -C "$WORK/fixture" tag -l | grep -qx wired; then
  pass "WIRING: real git invokes the hook — a tag CREATE is refused and no tag appears"
else fail "WIRING: git did not invoke the hook — core.hooksPath arming does not reach real git"; fi

cp -r "$HOOK_DIR" "$WORK/nohook" && rm -f "$WORK/nohook/reference-transaction"
ck; if [[ "$(try_tag unwired "$WORK/nohook" "$FIX_COMMON")" == "0" ]] && git -C "$WORK/fixture" tag -l | grep -qx unwired; then
  pass "MUTATION: with the hook removed the same CREATE succeeds — the refusal is its doing"
else fail "MUTATION: the CREATE still failed with the hook removed — refusals are NOT attributable"; fi

# --- the fixture-builder overwrite this design depends on ------------------------------------
# Fixture cleanliness under arming rests entirely on plugins/soleur/test/lib/git-fixture-env.sh
# unconditionally re-exporting GIT_CONFIG_COUNT/KEY_0/VALUE_0 with its own hermetic config, which
# clobbers the arming for every fixture built through that chokepoint. That is load-bearing and was
# nowhere asserted: if someone makes it conditional, the hook silently follows git into every
# fixture repo and the failure shows up as unrelated suites reddening. Assert it here so the guard
# names the cause instead.
_FIXLIB="$REPO_ROOT/plugins/soleur/test/lib/git-fixture-env.sh"
ck; if [[ -f "$_FIXLIB" ]]; then
  _seen="$(BATTERY_TAG_LIVE_COMMON_DIR="$LIVE_COMMON" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath \
    GIT_CONFIG_VALUE_0="$HOOK_DIR" bash -c 'source "$1"; git_fixture_env "$2" >/dev/null 2>&1; printf "%s" "${GIT_CONFIG_KEY_0:-<unset>}"' _ "$_FIXLIB" "$WORK/fixture" 2>/dev/null)"
  if [[ "$_seen" == "commit.gpgsign" ]]; then
    pass "the #7849 fixture builder overwrites the arming (fixtures see commit.gpgsign, not core.hooksPath)"
  else
    fail "the #7849 fixture builder no longer overwrites GIT_CONFIG_KEY_0 (fixtures see '$_seen') — the hook now follows git into every fixture"
  fi
else
  fail "plugins/soleur/test/lib/git-fixture-env.sh is missing — the overwrite this design depends on cannot be asserted"
fi

# --- Stage D: floors and conservation --------------------------------------------------------
printf '\nbattery-ref-guard: %d passed, %d failed, %d assertion(s) executed\n' "$passes" "$fails" "$asserted"

# Reported DIRECTLY, never through fail() (ADR-193). THE BINDING SITS FLUSH AGAINST THE `if`.
BATTERY_REF_MIN_ASSERTIONS=12
if (( asserted < BATTERY_REF_MIN_ASSERTIONS )); then
  printf '[FATAL] assertion floor: executed %d < BATTERY_REF_MIN_ASSERTIONS=%d\n' "$asserted" "$BATTERY_REF_MIN_ASSERTIONS" >&2
  exit 1
fi
if (( passes + fails != asserted )); then
  printf '[FATAL] accounting conservation: passes(%d) + fails(%d) != asserted(%d)\n' "$passes" "$fails" "$asserted" >&2
  exit 1
fi

(( fails == 0 )) || exit 1
exit 0
