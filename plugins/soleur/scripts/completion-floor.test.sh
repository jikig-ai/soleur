#!/usr/bin/env bash
# completion-floor.test.sh — basic contract tests
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFIER="${SCRIPT_DIR}/completion-floor.sh"

pass=0; fail=0; total=0
run() { "$@"; }
assert_exit() {
  local expected="$1"; shift
  total=$((total+1))
  "$@" >/dev/null 2>&1
  local rc=$?
  if [[ "$rc" -eq "$expected" ]]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: expected exit $expected got $rc for: $*"; fi
}

# unknown phase -> exit 2
assert_exit 2 "$VERIFIER" --phase bogus

# missing --phase -> exit 2
assert_exit 2 "$VERIFIER"

# --- review: no-open-code-review-issues is scoped to THIS PR ---------------
# A stub gh on PATH: `pr view` prints FLOOR_PR (or fails when unset), with
# gh 2.106's hint on stderr; `issue list` applies the --jq filter to a fixed
# issue set, so the real jq expression the verifier builds is what runs.
# The shared builder (plugins/soleur/AGENTS.md): sourcing arms the git-location
# tripwire, and git_fixture_env sweeps GIT_*, sets a ceiling and pins identity.
# shellcheck source=../test/lib/git-fixture-env.sh
source "${SCRIPT_DIR}/../test/lib/git-fixture-env.sh" || { echo "FATAL: could not source git-fixture-env.sh" >&2; exit 2; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/repo"
cat >"$T/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf 'hint: use `gh event listen` instead of polling\n' >&2
case "$1 $2" in
  "pr view") [[ -n "${FLOOR_PR:-}" ]] || exit 1; printf '%s\n' "$FLOOR_PR" ;;
  "issue list")
    [[ -n "${FLOOR_LIST_FAIL:-}" ]] && exit 1
    # Answer only the call shape the verifier must make: open, code-review,
    # labels read, and a limit of at least 1000 (gh's default 30 truncates).
    a=" $* "; [[ "$a" == *" --label code-review "* && "$a" == *" --state open "* \
      && "$a" =~ \ -L\ ([0-9]+)\  && "${BASH_REMATCH[1]}" -ge 1000 && "$a" == *",labels"* ]] || exit 3
    jq_expr=""; while [[ $# -gt 0 ]]; do [[ "$1" == "--jq" ]] && jq_expr="$2"; shift; done
    # No --jq: one line per issue, as gh's table output prints them.
    printf '%s' "${FLOOR_ISSUES:-[]}" | jq -r "${jq_expr:-.[] | .number}" ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$T/bin/gh"
( git_fixture_env "$T/repo" && git -C "$T/repo" init -q \
  && git -C "$T/repo" commit -q --allow-empty -m "x" -m "Reviewed-Coverage: full" ) >/dev/null 2>&1 \
  || { echo "FATAL: fixture repo setup failed" >&2; exit 2; }
floor_review() { ( git_fixture_env "$T/repo" >/dev/null 2>&1 && PATH="$T/bin:$PATH" "$VERIFIER" --phase review --root "$T/repo" 2>/dev/null ); }
assert_review() { # <label> <want: pass|missing> ; env carries the case
  total=$((total+1))
  local out; out="$(floor_review)"
  local got=pass; [[ "$out" == *"no-open-code-review-issues"* ]] && got=missing
  if [[ "$got" == "$2" ]]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: want $2, got: $out"; fi
}
# Helper self-test: drive each verdict helper once to a known pass and once to
# a known fail (floor_review stubbed, so this does not depend on the SUT), then
# unwind. A helper that can no longer conclude either way is a FATAL by
# printf + exit, never through the helpers under test.
_st_p=$pass; _st_f=$fail; _st_t=$total
assert_exit 0 true >/dev/null; assert_exit 0 false >/dev/null
_st_real="$(declare -f floor_review)"
floor_review() { printf 'SOLEUR_FLOOR_GATE phase=review status=fail missing=no-open-code-review-issues\n'; }
assert_review "self-test hit" missing >/dev/null; assert_review "self-test miss" pass >/dev/null
eval "$_st_real"
if [[ "$pass" -ne $((_st_p + 2)) || "$fail" -ne $((_st_f + 2)) ]]; then
  printf '[FATAL] helper self-test: verdict helpers cannot conclude (pass +%d, fail +%d; want +2/+2)\n' "$((pass - _st_p))" "$((fail - _st_f))" >&2
  exit 1
fi
pass=$_st_p; fail=$_st_f; total=$_st_t
UNREL='[{"number":1,"body":"Ref #131120"},{"number":2,"body":"PR #999"},{"number":3,"body":null}]'
FLOOR_PR=13112 FLOOR_ISSUES="$UNREL" assert_review "unrelated open code-review issues do not block" pass
FLOOR_PR=13112 FLOOR_ISSUES='[{"number":4,"body":"Ref #13112"}]' assert_review "an issue citing this PR blocks" missing
FLOOR_PR=13112 FLOOR_ISSUES='[{"number":5,"body":"from PR #13112."}]' assert_review "a cite followed by punctuation blocks" missing
FLOOR_PR=13112 FLOOR_ISSUES='[{"number":9,"body":"See https://github.com/o/r/pull/13112 review"}]' assert_review "a /pull/N URL cite blocks" missing
FLOOR_PR=13112 FLOOR_ISSUES='[{"number":10,"body":"https://github.com/o/r/pull/131120"}]' assert_review "a longer /pull/ number does not block" pass
FLOOR_PR=13112 FLOOR_ISSUES='[{"number":11,"body":"Ref #113112 and https://github.com/o/r/pull/113112"}]' assert_review "a number ending in the PR number does not block" pass
FLOOR_PR=13112 FLOOR_ISSUES='[{"number":12,"body":"PR #999 bumps build 13112; see https://example.com/v/13112"}]' assert_review "a bare PR number not after # or /pull/ does not block" pass
FLOOR_PR='' FLOOR_ISSUES='[]' assert_review "an unresolvable PR fails closed" missing
FLOOR_PR=13112 FLOOR_LIST_FAIL=1 assert_review "a failed issue read fails closed" missing
FLOOR_PR=13112 FLOOR_ISSUES='[{"number":6,"body":"**Source:** PR #13112 review","labels":[{"name":"code-review"},{"name":"deferred-scope-out"}]},{"number":7,"body":"Ref #13112","labels":[{"name":"synthetic-test"}]}]' \
  assert_review "scope-out and synthetic-test issues citing this PR do not block" pass
FLOOR_PR=13112 FLOOR_ISSUES='[{"number":8,"body":"Ref #13112","labels":[{"name":"code-review"},{"name":"type/security"}]}]' \
  assert_review "a labelled (non-scope-out) issue citing this PR blocks" missing
FLOOR_PR=13112 FLOOR_ISSUES="$(jq -cn '[range(1000) | {number: ., body: "x"}]')" \
  assert_review "a full 1000-issue page fails closed" missing
# Anti-vacuity: the exact measured total, counted on entry to each assertion
# helper (not by pass/fail) and reported by printf, never through the helpers
# it backstops — a dropped row is a FATAL.
MIN_ASSERTIONS=14
if [[ "$total" -lt "$MIN_ASSERTIONS" ]]; then
  printf '[FATAL] vacuity floor: only %d of %d assertions ran — rows were dropped or the suite stopped early\n' "$total" "$MIN_ASSERTIONS" >&2
  exit 1
fi

echo "PASS=$pass FAIL=$fail"
[[ "$fail" -eq 0 ]]
