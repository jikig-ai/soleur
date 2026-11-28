#!/usr/bin/env bash
# completion-floor.test.sh — basic contract tests
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFIER="${SCRIPT_DIR}/completion-floor.sh"

pass=0; fail=0
run() { "$@"; }
assert_exit() {
  local expected="$1"; shift
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
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/repo"
# A linked worktree's hooks export GIT_DIR/GIT_INDEX_FILE as absolute paths;
# without this scrub the fixture commit would land on the live branch.
nogitenv() { env -u GIT_DIR -u GIT_INDEX_FILE -u GIT_WORK_TREE -u GIT_OBJECT_DIRECTORY -u GIT_COMMON_DIR -u GIT_PREFIX GIT_CEILING_DIRECTORIES="$T" "$@"; }
cat >"$T/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf 'hint: use `gh event listen` instead of polling\n' >&2
case "$1 $2" in
  "pr view") [[ -n "${FLOOR_PR:-}" ]] || exit 1; printf '%s\n' "$FLOOR_PR" ;;
  "issue list")
    [[ -n "${FLOOR_LIST_FAIL:-}" ]] && exit 1
    jq_expr=""; while [[ $# -gt 0 ]]; do [[ "$1" == "--jq" ]] && jq_expr="$2"; shift; done
    # No --jq: one line per issue, as gh's table output prints them.
    printf '%s' "${FLOOR_ISSUES:-[]}" | jq -r "${jq_expr:-.[] | .number}" ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$T/bin/gh"
nogitenv git -C "$T/repo" init -q 2>/dev/null
nogitenv git -C "$T/repo" -c user.name=t -c user.email=t@example.com commit -q --allow-empty -m "x" -m "Reviewed-Coverage: full" 2>/dev/null
floor_review() { PATH="$T/bin:$PATH" nogitenv "$VERIFIER" --phase review --root "$T/repo" 2>/dev/null; }
assert_review() { # <label> <want: pass|missing> ; env carries the case
  local out; out="$(floor_review)"
  local got=pass; [[ "$out" == *"no-open-code-review-issues"* ]] && got=missing
  if [[ "$got" == "$2" ]]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: want $2, got: $out"; fi
}
UNREL='[{"number":1,"body":"Ref #131120"},{"number":2,"body":"PR #999"},{"number":3,"body":null}]'
FLOOR_PR=13112 FLOOR_ISSUES="$UNREL" assert_review "unrelated open code-review issues do not block" pass
FLOOR_PR=13112 FLOOR_ISSUES='[{"number":4,"body":"Ref #13112"}]' assert_review "an issue citing this PR blocks" missing
FLOOR_PR=13112 FLOOR_ISSUES='[{"number":5,"body":"from PR #13112."}]' assert_review "a cite followed by punctuation blocks" missing
FLOOR_PR='' FLOOR_ISSUES='[]' assert_review "an unresolvable PR fails closed" missing
FLOOR_PR=13112 FLOOR_LIST_FAIL=1 assert_review "a failed issue read fails closed" missing
# Anti-vacuity: the seven-assertion floor is reported by printf, not through the
# assertion helpers it backstops.
if [[ $((pass + fail)) -lt 7 ]]; then printf '[FATAL] only %d assertions ran (floor 7)\n' "$((pass + fail))"; exit 1; fi

echo "PASS=$pass FAIL=$fail"
[[ "$fail" -eq 0 ]]
