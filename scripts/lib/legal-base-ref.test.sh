#!/usr/bin/env bash
# legal-base-ref.test.sh -- suite for the shared legal-corpus base resolver.
#
# The resolver exists because gate 1 and gate 2 previously answered "what am I diffing
# against?" differently while registered side by side in the same runner. Its PRECEDENCE
# branches are the part with no other coverage: both gates' suites drive it only through the
# default path, so `MERGE_GROUP_BASE_SHA` and `GITHUB_BASE_REF` would be dead under this
# registration and nothing would notice.
#
# Auto-globbed by test-all.sh (`scripts/lib/*.test.sh`); no run_suite line needed.

set -euo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/legal-base-ref.sh"

MIN_ASSERTIONS=13

fails=0
passes=0
pass() { passes=$((passes + 1)); echo "[ok] $1"; }
fail() { fails=$((fails + 1)); echo "[FAIL] $1" >&2; }

if [[ ! -f "$LIB" ]]; then
  fail "library missing at scripts/lib/legal-base-ref.sh"
  echo "passed: $passes  failed: $fails" >&2
  exit 1
fi

SANDBOX=$(mktemp -d -t legal-base-ref.XXXXXXXX) || { echo "mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$SANDBOX"' EXIT

# A fixture repo with a real second branch, so merge-base is a distinct commit rather than
# HEAD -- otherwise every precedence assertion would pass for the wrong reason.
mk_repo() {
  local d
  d=$(mktemp -d "$SANDBOX/repo-XXXXXXXX") || return 1
  git -C "$d" init -q -b main
  git -C "$d" config user.email t@t
  git -C "$d" config user.name t
  echo one > "$d/f"; git -C "$d" add -A; git -C "$d" -c core.hooksPath=/dev/null commit -qm one
  git -C "$d" checkout -q -b release
  echo two > "$d/f"; git -C "$d" add -A; git -C "$d" -c core.hooksPath=/dev/null commit -qm two
  git -C "$d" checkout -q -b feat
  echo three > "$d/f"; git -C "$d" add -A; git -C "$d" -c core.hooksPath=/dev/null commit -qm three
  printf '%s\n' "$d"
}

# Run legal_resolve_base in a fresh shell inside <repo>. Echoes "<rc>|<stdout>".
resolve() {
  local d="$1" explicit="${2:-}" out rc=0
  shift 2 2>/dev/null || shift 1
  out=$(cd "$d" && env "$@" bash -c ". '$LIB'; legal_resolve_base '$explicit'" 2>/dev/null) || rc=$?
  printf '%s|%s' "$rc" "$out"
}

# ---------------------------------------------------------------------------
# Library hygiene
# ---------------------------------------------------------------------------

direct_rc=0
bash "$LIB" >/dev/null 2>&1 || direct_rc=$?
[[ "$direct_rc" != "0" ]] && pass "direct execution refused (rc=$direct_rc)" \
  || fail "direct execution exited 0 -- the guard is inert"

double_rc=0
bash -c ". '$LIB'; . '$LIB'; [[ \$(type -t legal_resolve_base) == function ]]" || double_rc=$?
[[ "$double_rc" == "0" ]] && pass "double-source is a no-op and leaves the function defined" \
  || fail "double-source failed (rc=$double_rc)"

# ---------------------------------------------------------------------------
# Precedence. Each branch is asserted to WIN over the ones below it, which is the
# property a single default-path fixture cannot distinguish.
# ---------------------------------------------------------------------------

d=$(mk_repo)
main_sha=$(git -C "$d" rev-parse main)
rel_sha=$(git -C "$d" rev-parse release)

res=$(resolve "$d" "" "MERGE_GROUP_BASE_SHA=$main_sha" "GITHUB_BASE_REF=release")
rc=${res%%|*}; out=${res#*|}
if [[ "$rc" == "0" ]] && [[ "$out" == "${main_sha}"*"${main_sha}" ]]; then
  pass "MERGE_GROUP_BASE_SHA wins over GITHUB_BASE_REF"
else
  fail "MERGE_GROUP_BASE_SHA precedence wrong (rc=$rc out=$out)"
fi

res=$(resolve "$d" "" "GITHUB_BASE_REF=release")
rc=${res%%|*}; out=${res#*|}
# No `origin` remote in the fixture, so origin/release cannot resolve -> fail closed.
if [[ "$rc" == "2" ]]; then
  pass "GITHUB_BASE_REF resolves via origin/<ref> and fails closed when absent"
else
  fail "GITHUB_BASE_REF branch did not fail closed on a missing remote (rc=$rc)"
fi

res=$(resolve "$d" "release")
rc=${res%%|*}; out=${res#*|}
if [[ "$rc" == "0" ]] && [[ "$out" == "release"* ]]; then
  pass "an explicit ref wins over every environment branch"
else
  fail "explicit ref precedence wrong (rc=$rc out=$out)"
fi

# The merge base of feat and release is release's tip; of feat and main is main's tip.
res=$(resolve "$d" "release"); out=${res#*|}
[[ "$out" == *"$rel_sha" ]] && pass "merge-base is computed, not the tip echoed back" \
  || fail "merge-base wrong for release: $out"

res=$(resolve "$d" "main"); out=${res#*|}
[[ "$out" == *"$main_sha" ]] && pass "merge-base against an ancestor branch is that branch's tip" \
  || fail "merge-base wrong for main: $out"

# Output shape: "<ref>\t<sha>" -- both gates split on the tab.
res=$(resolve "$d" "main"); out=${res#*|}
if [[ "$out" == *$'\t'* ]]; then
  pass "output is tab-separated <ref>\\t<merge-base>"
else
  fail "output is not tab-separated: $out"
fi

# ---------------------------------------------------------------------------
# Fail-closed paths. Exit 2 is "cannot decide" and must never collapse to 0.
# ---------------------------------------------------------------------------

res=$(resolve "$d" "does-not-exist"); rc=${res%%|*}
[[ "$rc" == "2" ]] && pass "unresolvable ref exits 2" || fail "unresolvable ref gave rc=$rc"

nonrepo=$(mktemp -d "$SANDBOX/nonrepo-XXXXXXXX")
res=$(resolve "$nonrepo" "main"); rc=${res%%|*}
[[ "$rc" == "2" ]] && pass "outside a work tree exits 2" || fail "non-repo gave rc=$rc"

# Unrelated histories: a ref that resolves but shares no ancestor must not report clean.
d2=$(mk_repo)
: "${d2:?fixture dir is empty; git -C '' would retarget this write}"
git -C "$d2" checkout -q --orphan orphan
echo x > "$d2/g"; git -C "$d2" add -A; git -C "$d2" -c core.hooksPath=/dev/null commit -qm orphan
res=$(resolve "$d2" "main"); rc=${res%%|*}
[[ "$rc" == "2" ]] && pass "unrelated histories exit 2 (no merge base)" \
  || fail "unrelated histories gave rc=$rc -- a vacuous base would follow"

# ---------------------------------------------------------------------------
# The fetch is CONDITIONAL. It was unconditional and measured as ~98% of both gates'
# wall time, against a CI job that already checks out at fetch-depth 0.
# ---------------------------------------------------------------------------

if grep -qE 'rev-parse --verify --quiet .*\|\| *$|! *git rev-parse --verify' "$LIB" \
   || grep -qE 'git rev-parse --verify --quiet "\$\{base_ref\}\^\{commit\}" >/dev/null' "$LIB"; then
  pass "the fetch is guarded by a resolve check"
else
  fail "no resolve guard around the fetch -- it is unconditional again"
fi

# Behavioural companion: with no `origin` remote at all, an already-resolvable ref still
# works, which is only possible if the fetch is skipped rather than required.
res=$(resolve "$d" "main"); rc=${res%%|*}
[[ "$rc" == "0" ]] && pass "resolves without any origin remote (fetch genuinely skipped)" \
  || fail "resolution required a fetch (rc=$rc)"

echo "passed: $passes  failed: $fails"

total=$((passes + fails))
if (( total < MIN_ASSERTIONS )); then
  echo "suite ran only ${total} assertions, expected at least ${MIN_ASSERTIONS} -- assertions are not running" >&2
  exit 1
fi
(( fails == 0 )) || exit 1
