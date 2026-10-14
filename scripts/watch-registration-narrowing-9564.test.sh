#!/usr/bin/env bash
# Suite for scripts/watch-registration-narrowing-9564.sh (the weekly watcher that
# posts ONE notice on the deferred registration-only narrowing tracker and never
# closes it). Mock-`gh` + fixture-git-history pattern: a PATH-prepended recording
# `gh` serves per-scenario issue JSON and logs every argv, so the property under
# test is the observed call set, never a list of call sites.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/watch-registration-narrowing-9564.sh"
WF="$SCRIPT_DIR/../.github/workflows/registration-narrowing-watch.yml"

PASS=0; FAIL=0; TOTAL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); }
fatal() { printf 'FATAL: %s\n' "$*" >&2; exit 2; }
# The verdict. The LAST line of this file must be exactly `finish || exit 1`; the
# self-test below drives it both ways and pins that line, so neither the function nor
# its wiring can be neutered while a real failure is present.
finish() { [[ "$FAIL" -eq 0 ]]; }

# Instrument self-test (ADR-193): drive both branches, require both counters to
# move, report with printf + exit, never through the helpers under test.
pass "self-test" >/dev/null
fail "self-test" >/dev/null
if [[ "$PASS" -ne 1 || "$FAIL" -ne 1 || "$TOTAL" -ne 2 ]]; then
  printf 'FATAL: verdict helpers are not dispatching (PASS=%s FAIL=%s TOTAL=%s)\n' "$PASS" "$FAIL" "$TOTAL" >&2
  exit 2
fi
PASS=0; FAIL=0; TOTAL=0
if ( FAIL=1; finish ) || ! ( FAIL=0; finish ); then
  printf 'FATAL: finish() does not map FAIL to an exit status\n' >&2
  exit 2
fi
if [[ "$(tail -n 1 "${BASH_SOURCE[0]}")" != 'finish || exit 1' ]]; then
  printf 'FATAL: the last line of this suite is not the exit gate `finish || exit 1`\n' >&2
  exit 2
fi

# A fixture repo must never see the caller's git location variables.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_PREFIX
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

# Fixture-directory guard. The CANONICAL copy lives in plugins/soleur/test/test-helpers.sh;
# plugins/soleur/test/fixture-dir-operand-assert.test.sh asserts this copy is byte-equal to it.
# Do not reword it in one file only.
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

# ONE owning tempdir with ONE trap (ADR-129); every scenario takes a subdirectory.
TMPDIR="${TMPDIR:-/var/tmp}"; export TMPDIR
ROOT="$(mktemp -d "${TMPDIR%/}/watch-reg-narrowing.XXXXXXXX")" || { echo "FATAL: mktemp failed" >&2; exit 2; }
assert_fixture_dir "$ROOT"
trap 'rm -rf "$ROOT"' EXIT

SENTINEL='<!-- registration-narrowing-watch:v1 threshold=3 -->'
TEST_ALL=scripts/test-all.sh
INDEX=scripts/lib/test-affected-paths.sh
N=0
REPO=""; BASE=""; MOCKD=""; OUT=""; ERR=""; RC=0

g() { assert_fixture_dir "$REPO"; git -C "$REPO" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@"; }

# New fixture repo with the two runner files and one unrelated file, plus a mock dir.
mkrepo() {
  N=$((N + 1))
  REPO="$ROOT/repo$N"; MOCKD="$ROOT/mock$N"
  assert_fixture_dir "$REPO"; assert_fixture_dir "$MOCKD"
  mkdir -p "$REPO/scripts/lib" "$MOCKD" || { echo "FATAL: mkdir failed" >&2; exit 2; }
  git init -q -b main "$REPO" || { echo "FATAL: git init failed" >&2; exit 2; }
  printf 'a\nb\n' > "$REPO/$TEST_ALL"; printf 'x\ny\n' > "$REPO/$INDEX"; printf 'o\n' > "$REPO/other.txt"
  g add -A && g commit -q -m base || { echo "FATAL: base commit failed" >&2; exit 2; }
  BASE="$(g rev-parse HEAD)"
  : > "$MOCKD/calls"; : > "$MOCKD/bodies"
  cat > "$MOCKD/gh" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCKD/calls"
case "$1 $2" in
  "issue view")
    [[ -f "$MOCKD/view_fail" ]] && exit 1
    cat "$MOCKD/issue.json"; exit 0 ;;
  "issue comment")
    if [[ -f "$MOCKD/comment_fail" ]]; then cat >/dev/null; exit 1; fi
    cat >> "$MOCKD/bodies"; exit 0 ;;
esac
echo "mock gh: unexpected call: $*" >&2; exit 64
MOCK
  chmod +x "$MOCKD/gh"
  issue OPEN '[]'
}
issue() { assert_fixture_dir "$MOCKD"; printf '{"state":"%s","comments":%s}' "$1" "$2" > "$MOCKD/issue.json"; }
rawissue() { assert_fixture_dir "$MOCKD"; printf '%s' "$1" > "$MOCKD/issue.json"; }
bot_comment()  { printf '[{"author":{"login":"github-actions"},"body":"notice\\n%s"}]' "$SENTINEL"; }
bot_comment2() { printf '[{"author":{"login":"github-actions[bot]"},"body":"notice\\n%s"}]' "$SENTINEL"; }
human_comment() { printf '[{"author":{"login":"someone"},"body":"%s"}]' "$SENTINEL"; }

# Commit helpers. `q` adds one additive commit that registers a suite in the runner
# (qualifying); `qs` does the same with a chosen subject. SHAS accumulates their
# short hashes. The rest are the touching-but-not-counted shapes.
SHAS=""
commit_all() { g add -A; g commit -q -m "$1" || fatal "fixture commit failed: $1"; }
qs() { assert_fixture_dir "$REPO"; echo "run_suite \"scripts/s-$RANDOM-$RANDOM\" bash scripts/s.test.sh" >> "$REPO/$TEST_ALL"; commit_all "$1"; SHAS="$SHAS $(g log -1 --format=%h)"; }
q() { qs "add suite $1"; }
other_only() { assert_fixture_dir "$REPO"; echo "o2-$RANDOM" >> "$REPO/other.txt"; commit_all "docs only"; }
deleting() { assert_fixture_dir "$REPO"; tail -n +2 "$REPO/$TEST_ALL" > "$REPO/$TEST_ALL.new" && mv "$REPO/$TEST_ALL.new" "$REPO/$TEST_ALL"; commit_all "rewrite runner (deletes a line)"; }
nonreg() { assert_fixture_dir "$REPO"; echo "# note $RANDOM" >> "$REPO/$TEST_ALL"; commit_all "runner comment (additive, no run_suite)"; }
idx_only() { assert_fixture_dir "$REPO"; echo "idx-$RANDOM" >> "$REPO/$INDEX"; commit_all "index-only addition"; }
mixed() { assert_fixture_dir "$REPO"; tail -n +2 "$REPO/$INDEX" > "$REPO/$INDEX.new" && mv "$REPO/$INDEX.new" "$REPO/$INDEX"; echo "run_suite \"scripts/m-$RANDOM\" bash m.sh" >> "$REPO/$TEST_ALL"; commit_all "register + delete an index line"; }
binary() { assert_fixture_dir "$REPO"; printf '\0bin\n' >> "$REPO/$INDEX"; echo "run_suite \"scripts/b-$RANDOM\" bash b.sh" >> "$REPO/$TEST_ALL"; commit_all "register + binary index"; }
merge_commit() {
  g checkout -q -b side && other_only && g checkout -q main && g merge -q --no-ff side -m "merge side" || fatal "merge fixture failed"
}
# A merge that differs from BOTH parents on the runner (a hand-resolved conflict that
# also adds a run_suite line): it must never be counted as a registration run.
conflict_merge() {
  g checkout -q -b side2 "$BASE" || fatal "branch fixture failed"
  assert_fixture_dir "$REPO"; echo 'run_suite "scripts/side" bash side.sh' >> "$REPO/$TEST_ALL"; commit_all "side registration"; SHAS="$SHAS $(g log -1 --format=%h)"
  g checkout -q main || fatal "checkout fixture failed"
  assert_fixture_dir "$REPO"; echo 'run_suite "scripts/mainline" bash main.sh' >> "$REPO/$TEST_ALL"; commit_all "main registration"; SHAS="$SHAS $(g log -1 --format=%h)"
  g merge -q side2 -m "merge side2 (hand-resolved)" >/dev/null 2>&1
  assert_fixture_dir "$REPO"; printf 'a\nb\nrun_suite "scripts/mainline" bash main.sh\nrun_suite "scripts/side" bash side.sh\nrun_suite "scripts/merged-extra" bash x.sh\n' > "$REPO/$TEST_ALL"
  commit_all "merge side2 (hand-resolved)"
}
# Shapes that touch the runner and MENTION `run_suite` without registering a suite.
mention() { assert_fixture_dir "$REPO"; echo "$1" >> "$REPO/$TEST_ALL"; commit_all "runner mentions run_suite without calling it"; }
# A real run_suite call added ONLY to the index file (never to the runner).
idx_run_suite() { assert_fixture_dir "$REPO"; echo 'run_suite "scripts/idx" bash idx.sh' >> "$REPO/$INDEX"; commit_all "run_suite call in the index only"; }
# A runner comment plus a run_suite line in an unrelated file.
other_run_suite() { assert_fixture_dir "$REPO"; echo "# tidy $RANDOM" >> "$REPO/$TEST_ALL"; echo 'run_suite "scripts/elsewhere" bash e.sh' >> "$REPO/other.txt"; commit_all "runner comment + run_suite line in another file"; }
# A base commit that EXISTS but is not an ancestor of HEAD.
offbranch_base() {
  g checkout -q -b off "$BASE" || fatal "branch fixture failed"
  assert_fixture_dir "$REPO"; echo "off-$RANDOM" >> "$REPO/other.txt"; commit_all "off-branch commit"
  OFF="$(g rev-parse HEAD)"; g checkout -q main || fatal "checkout fixture failed"
}

run() {
  OUT=""; ERR=""; RC=0
  assert_fixture_dir "$MOCKD"; assert_fixture_dir "$REPO"
  local o="$MOCKD/stdout" e="$MOCKD/stderr"
  assert_fixture_dir "$o"; assert_fixture_dir "$e"
  ( cd "$REPO" && env "PATH=$MOCKD:$PATH" "MOCKD=$MOCKD" GH_REPO=jikig-ai/soleur "WATCH_BASE_SHA=${WATCH_BASE_SHA_OVERRIDE:-$BASE}" bash "$SUT" "$@" ) > "$o" 2> "$e"
  RC=$?
  OUT="$(cat "$o")"; ERR="$(cat "$e")"
}
comments_posted() { grep -c '^issue comment ' "$MOCKD/calls" || true; }
WATCH_BASE_SHA_OVERRIDE=""
reset_calls() { assert_fixture_dir "$MOCKD"; : > "$MOCKD/calls"; }
flag() { assert_fixture_dir "$MOCKD"; : > "$MOCKD/$1"; }
# Every gh invocation in a text that is NOT `gh issue view` / `gh issue comment`.
gh_calls_bad() { printf '%s\n' "$1" | grep -oE '\bgh +[a-z-]+( +[a-z-]+)?' | grep -vxE 'gh +issue +(view|comment)' || true; }

# ---- S1: two qualifying commits -> silent green ----
mkrepo; q 1; q 2; run
[[ "$RC" -eq 0 && "$(comments_posted)" -eq 0 && "$OUT" == *"count=2"* ]] \
  && pass "S1 two qualifying commits: exit 0, no comment, count=2 reported" || fail "S1 (rc=$RC posted=$(comments_posted) out=$OUT)"

# ---- S2: exactly three -> exactly one comment naming count, SHAs, part (b), stays open ----
mkrepo; SHAS=""; q 1; q 2; q 3; run
body="$(cat "$MOCKD/bodies")"; ok=1
[[ "$RC" -eq 0 && "$(comments_posted)" -eq 1 ]] || ok=0
for s in $SHAS; do [[ "$body" == *"$s"* ]] || ok=0; done
[[ "$body" == *"part (b)"* && "$body" == *"stays open"* && "$body" == *"653 s"* && "$body" == *"54.4 min"* && "$body" == *"3516 s"* && "$body" == *"18.6%"* && "$body" == *"$SENTINEL"* ]] || ok=0
[[ "$body" == *"3 registration-shaped"* ]] || ok=0
[[ "$ok" -eq 1 ]] && pass "S2 count 3 posts exactly one notice with count, SHAs, part (b), stays-open, sentinel" || fail "S2 (rc=$RC posted=$(comments_posted))"
# The call set is EXACTLY one read of the tracker (with the comments field the dedup
# needs) and one body-file comment on #9564: no other verb, flag, repo or issue number.
[[ "$(cat "$MOCKD/calls")" == $'issue view 9564 --json state,comments\nissue comment 9564 --body-file -' ]] \
  && pass "S2b the gh call set is exactly 'issue view 9564 --json state,comments' + 'issue comment 9564 --body-file -'" || fail "S2b ($(tr '\n' '|' < "$MOCKD/calls"))"

# ---- S3: three + bot-authored sentinel (both author spellings) -> no comment ----
mkrepo; q 1; q 2; q 3; issue OPEN "$(bot_comment)"; run
a="$(comments_posted)"; rc1="$RC"
issue OPEN "$(bot_comment2)"; reset_calls; run
[[ "$a" -eq 0 && "$rc1" -eq 0 && "$(comments_posted)" -eq 0 && "$RC" -eq 0 ]] && pass "S3 bot sentinel (github-actions and github-actions[bot]) suppresses the comment, both runs exit 0" || fail "S3 (first=$a rc1=$rc1 second=$(comments_posted) rc=$RC)"

# ---- S3c: the bot sentinel is the SECOND comment (a human spoke first) -> still suppressed ----
mkrepo; q 1; q 2; q 3
issue OPEN '[{"author":{"login":"someone"},"body":"hello"},{"author":{"login":"github-actions"},"body":"notice\n'"$SENTINEL"'"}]'; run
[[ "$RC" -eq 0 && "$(comments_posted)" -eq 0 ]] && pass "S3c sentinel in a non-first bot comment still suppresses (every comment is read)" || fail "S3c (rc=$RC posted=$(comments_posted))"

# ---- S4: three + sentinel from a non-bot author -> forgery does not suppress ----
mkrepo; q 1; q 2; q 3; issue OPEN "$(human_comment)"; run
[[ "$RC" -eq 0 && "$(comments_posted)" -eq 1 ]] && pass "S4 forged sentinel from a non-bot account does not suppress the notice" || fail "S4 (rc=$RC posted=$(comments_posted))"

# ---- S4b: a login that merely STARTS with the bot's, and a bot comment carrying another threshold/version ----
mkrepo; q 1; q 2; q 3
issue OPEN '[{"author":{"login":"github-actions-fan"},"body":"'"$SENTINEL"'"}]'; run
a="$(comments_posted)"
issue OPEN '[{"author":{"login":"github-actions"},"body":"<!-- registration-narrowing-watch:v0 threshold=2 -->"}]'; reset_calls; run
[[ "$a" -eq 1 && "$(comments_posted)" -eq 1 ]] && pass "S4b a prefix-matching login and a bot comment with another sentinel version do not suppress" || fail "S4b (prefix=$a version=$(comments_posted))"

# ---- S5: five + bot sentinel -> once per threshold, not per increment ----
mkrepo; q 1; q 2; q 3; q 4; q 5; issue OPEN "$(bot_comment)"; run
[[ "$RC" -eq 0 && "$(comments_posted)" -eq 0 ]] && pass "S5 count 5 with the threshold sentinel present stays silent" || fail "S5 (rc=$RC posted=$(comments_posted))"

# ---- S6: CLOSED tracker self-disables, even with an unresolvable base ----
mkrepo; q 1; q 2; q 3; issue CLOSED '[]'; WATCH_BASE_SHA_OVERRIDE=0000000000000000000000000000000000000000; run; WATCH_BASE_SHA_OVERRIDE=""
[[ "$RC" -eq 0 && "$(comments_posted)" -eq 0 && "$ERR" != *"::error::"* && "$OUT" == *"::notice::"* && "$OUT" == *"RETIREMENT"* ]] \
  && pass "S6 closed tracker: exit 0, no comment, no base-commit error, retirement notice" || fail "S6 (rc=$RC err=$ERR out=$OUT)"

# ---- S7: issue/comments read fails -> exit 3 and nothing posted ----
mkrepo; q 1; q 2; q 3; flag view_fail; run
[[ "$RC" -eq 3 && "$(comments_posted)" -eq 0 ]] && pass "S7 failed read: exit 3, no comment (never risks a duplicate)" || fail "S7 (rc=$RC posted=$(comments_posted))"

# ---- S7b: a successful view whose JSON has no .state -> exit 3, never a silent green ----
mkrepo; q 1; q 2; q 3; rawissue '{"comments":[]}'; run
[[ "$RC" -eq 3 && "$(comments_posted)" -eq 0 ]] && pass "S7b a view without .state: exit 3, no comment" || fail "S7b (rc=$RC posted=$(comments_posted))"

# ---- S7c: unreadable comments (null) at the threshold -> exit 3, never "no sentinel" ----
mkrepo; q 1; q 2; q 3; rawissue '{"state":"OPEN","comments":null}'; run
[[ "$RC" -eq 3 && "$(comments_posted)" -eq 0 && "$ERR" == *"::error::"* ]] && pass "S7c null comments: exit 3 with ::error::, nothing posted" || fail "S7c (rc=$RC posted=$(comments_posted) err=$ERR)"

# ---- S8: absent base on an OPEN tracker -> exit 3 with ::error::; failed post -> exit 1 ----
mkrepo; q 1; q 2; q 3; WATCH_BASE_SHA_OVERRIDE=0000000000000000000000000000000000000000; run; WATCH_BASE_SHA_OVERRIDE=""
[[ "$RC" -eq 3 && "$(comments_posted)" -eq 0 && "$ERR" == *"::error::"* ]] && pass "S8a absent base on an OPEN tracker: exit 3, ::error::, no comment" || fail "S8a (rc=$RC err=$ERR)"
mkrepo; q 1; q 2; q 3; flag comment_fail; run
[[ "$RC" -eq 1 && "$(comments_posted)" -eq 1 ]] && pass "S8b failed comment post: exit 1 (sentinel only ever lands with the comment)" || fail "S8b (rc=$RC posted=$(comments_posted))"
mkrepo; q 1; q 2; q 3; offbranch_base; WATCH_BASE_SHA_OVERRIDE="$OFF"; run; WATCH_BASE_SHA_OVERRIDE=""
[[ "$RC" -eq 3 && "$(comments_posted)" -eq 0 && "$ERR" == *"::error::"* ]] && pass "S8c a base that exists but is not an ancestor of HEAD: exit 3, no comment" || fail "S8c (rc=$RC posted=$(comments_posted) err=$ERR)"
mkrepo; q 1; q 2; q 3; g rm -q "$INDEX" && commit_all "split the index out"; run
[[ "$RC" -eq 3 && "$(comments_posted)" -eq 0 && "$ERR" == *"::error::"* ]] && pass "S8d a runner path that no longer exists: exit 3 (never a silent count of 0)" || fail "S8d (rc=$RC posted=$(comments_posted) err=$ERR)"

# ---- S10: other-path, merge and deleting commits are not counted; the exclusion is reported ----
mkrepo; q 1; q 2; other_only; merge_commit; deleting; run
[[ "$RC" -eq 0 && "$OUT" == *"count=2"* && "$OUT" == *"excluded=1"* && "$(comments_posted)" -eq 0 ]] \
  && pass "S10 only additive runner commits count (other-path, merge, deleting excluded; excluded=1)" || fail "S10 (rc=$RC out=$OUT)"

# ---- S10b: every touching-but-not-registering shape is excluded, the two real ones count ----
mkrepo; q 1; q 2; nonreg; idx_only; mixed; binary; run --print-count
[[ "$RC" -eq 0 && "$OUT" == *"count=2 excluded=4"* ]] \
  && pass "S10b no-run_suite, index-only, mixed-with-a-deletion and binary commits are excluded (count=2 excluded=4)" || fail "S10b (rc=$RC out=$OUT)"

# ---- S10c: a hand-resolved merge that adds a run_suite line is not a registration run ----
mkrepo; SHAS=""; conflict_merge; run --print-count
[[ "$RC" -eq 0 && "$OUT" == *"count=2 "* ]] && pass "S10c a conflict-resolved merge touching the runner is not counted (count=2, the two parents)" || fail "S10c (rc=$RC out=$OUT)"

# ---- S10d: a runner line that only MENTIONS run_suite, or a call outside the runner, never counts ----
mkrepo; q 1; q 2
mention '# usage: see +run_suite foo bar'; mention 'run_suite_helper() { :; }'; mention '# run_suite "x" bash y'; mention 'echo "run_suite is the registration verb"'
run --print-count
[[ "$RC" -eq 0 && "$OUT" == *"count=2 excluded=4"* ]] \
  && pass "S10d four runner lines that merely mention run_suite are excluded (count=2 excluded=4)" || fail "S10d (rc=$RC out=$OUT)"
mkrepo; q 1; q 2; idx_run_suite; other_run_suite; run --print-count
[[ "$RC" -eq 0 && "$OUT" == *"count=2 excluded=2"* ]] \
  && pass "S10e a run_suite call in the index only, or in another file, is excluded (count=2 excluded=2)" || fail "S10e (rc=$RC out=$OUT)"

# ---- S10f: a tag named like an abbreviated commit hash cannot change what is counted ----
mkrepo; SHAS=""; q 1; q 2; q 3; first="${SHAS# }"; first="${first%% *}"
g tag "$first" "$BASE" >/dev/null 2>&1 || fatal "tag fixture failed"
run --print-count
[[ "$RC" -eq 0 && "$OUT" == *"count=3 "* ]] && pass "S10f a tag shadowing a short hash does not change the count (full hashes are used)" || fail "S10f (rc=$RC out=$OUT)"

# ---- S11: --print-count works with an unresolvable base and stays read-only ----
mkrepo; q 1; WATCH_BASE_SHA_OVERRIDE=0000000000000000000000000000000000000000; run --print-count; WATCH_BASE_SHA_OVERRIDE=""
[[ "$RC" -eq 0 && "$OUT" == *"threshold=3"* && "$OUT" == *"count=unknown"* && "$(comments_posted)" -eq 0 ]] \
  && pass "S11a --print-count: threshold line printed, count=unknown, exit 0, no write" || fail "S11a (rc=$RC out=$OUT)"
mkrepo; q 1; q 2; q 3; run --print-count
[[ "$RC" -eq 0 && "$OUT" == *"threshold=3"* && "$OUT" == *"count=3"* && "$(comments_posted)" -eq 0 ]] \
  && pass "S11b --print-count at 3 reports count=3 and posts nothing" || fail "S11b (rc=$RC out=$OUT posted=$(comments_posted))"
mkrepo; run --print-count
[[ "$RC" -eq 0 && "$OUT" == *"count=0 excluded=0"* ]] && pass "S11c --print-count with no touching commits reports count=0" || fail "S11c (rc=$RC out=$OUT)"
mkrepo; q 1; q 2; q 3; run --help
[[ "$RC" -eq 2 && "$(wc -l < "$MOCKD/calls")" -eq 0 && "$ERR" == *"usage:"* ]] && pass "S11d an unknown argument: exit 2 with usage, no gh call (never the live mode)" || fail "S11d (rc=$RC err=$ERR)"

# ---- S12: refuses to run under xtrace (the script holds a live token) ----
mkrepo; q 1; q 2; q 3
assert_fixture_dir "$REPO"; assert_fixture_dir "$MOCKD"
( cd "$REPO" && env "PATH=$MOCKD:$PATH" "MOCKD=$MOCKD" GH_REPO=jikig-ai/soleur "WATCH_BASE_SHA=$BASE" bash -x "$SUT" ) > "$MOCKD/stdout" 2> "$MOCKD/stderr"
RC=$?; ERR="$(cat "$MOCKD/stderr")"
[[ "$RC" -eq 78 && "$ERR" == *"refusing to run under xtrace"* && "$(wc -l < "$MOCKD/calls")" -eq 0 ]] && pass "S12 bash -x: exit 78 with the refusal, no gh call" || fail "S12 (rc=$RC err=$ERR)"

# ---- S13: the workflow job runs on the default branch only (a branch dispatch cannot spend the notice) ----
[[ -s "$WF" ]] || fatal "workflow file missing: $WF"
wf_active="$(grep -vE '^[[:space:]]*#' "$WF")"
[[ "$(printf '%s\n' "$wf_active" | grep -cE "^    if: github\.ref == 'refs/heads/main'$")" -eq 1 ]] \
  && pass "S13 the watch job is guarded by if: github.ref == 'refs/heads/main'" || fail "S13 workflow job guard missing"
# The rest of the workflow contract, as active (non-comment) lines: the schedule exists, the
# checkout is full-depth, the token and permission the script needs are declared, and the
# step runs THIS script (which must exist).
wf_missing=""
grep -qF "    - cron: '17 9 * * 1'" <<<"$wf_active" || wf_missing="$wf_missing cron"
grep -qE '^          fetch-depth: 0$' <<<"$wf_active" || wf_missing="$wf_missing fetch-depth"
grep -qE '^  issues: write$' <<<"$wf_active" || wf_missing="$wf_missing issues-write"
grep -qF 'GH_TOKEN: ${{ github.token }}' <<<"$wf_active" || wf_missing="$wf_missing GH_TOKEN"
wf_run="$(printf '%s\n' "$wf_active" | sed -nE 's/^        run: bash (scripts\/[A-Za-z0-9._-]+\.sh)$/\1/p')"
[[ "$wf_run" == "scripts/watch-registration-narrowing-9564.sh" && -f "$SCRIPT_DIR/../$wf_run" ]] || wf_missing="$wf_missing run-script"
[[ -z "$wf_missing" ]] && pass "S13b workflow contract: weekly cron, fetch-depth 0, issues:write, GH_TOKEN, runs the watcher script" || fail "S13b workflow lines missing:$wf_missing"

# ---- S14: the production default base is one 40-hex literal (the seam overrides it in every other scenario) ----
sut_active="$(grep -vE '^[[:space:]]*#' "$SUT")"
[[ -s "$SUT" && -n "$sut_active" ]] || fatal "SUT missing or empty"
default_base="$(printf '%s\n' "$sut_active" | sed -nE 's/^BASE_SHA="\$\{WATCH_BASE_SHA:-([0-9a-f]{40})\}"$/\1/p')"
[[ "$(printf '%s\n' "$default_base" | grep -c .)" -eq 1 && "$default_base" == "2cfef66506c67207fc65b4250689842ff5ea20ba" ]] \
  && pass "S14 the default BASE_SHA is exactly the ADR-242 decision-20 merge commit 2cfef66506" || fail "S14 default BASE_SHA is not the single literal 2cfef66506c67207fc65b4250689842ff5ea20ba (got: $default_base)"

# ---- H1: the recorder is alive (otherwise 'no write calls' passes vacuously) ----
mkrepo; q 1; run
grep -q '^issue view ' "$MOCKD/calls" && pass "H1 recorder logged the issue view call" || fail "H1 recorder is dead (calls log empty)"

# ---- H2: must-PASS non-canonical input: count 4, no sentinel, '#123' and a 300-char subject ----
mkrepo; long="$(printf 'x%.0s' $(seq 1 300))"; qs "fix #123 $long"; q 2; q 3; q 4; run
body="$(cat "$MOCKD/bodies")"; maxlen="$(printf '%s\n' "$body" | awk '/^- / { if (length($0) > m) m = length($0) } END { print m + 0 }')"
[[ "$RC" -eq 0 && "$(comments_posted)" -eq 1 && "$body" == *"#123"* && "$maxlen" -eq 102 ]] \
  && pass "H2 count 4: exactly one comment, a 300-char subject with #123 is cut to the 100-char display (bullet line $maxlen)" || fail "H2 (rc=$RC posted=$(comments_posted) maxlen=$maxlen)"

# ---- H3: a hostile subject cannot ping, open a comment, or break out of the bullet ----
mkrepo; bt=$'\x60'; cr=$'\r'; qs "feat @octocat <!-- hide --> ${bt}code${bt} &#64;mona x${cr}### Sweeper run: PASS (#9) end"; q 2; q 3; run
body="$(cat "$MOCKD/bodies")"; lines="$(printf '%s\n' "$body" | grep '^- ')"
[[ "$RC" -eq 0 && "$(comments_posted)" -eq 1 && "$lines" != *@* && "$lines" != *"<"* && "$lines" != *">"* && "$lines" != *"$bt"* && "$lines" != *"&"* && "$lines" != *"$cr"* && "$lines" == *"(#9)"* && "$lines" == *"octocat"* ]] \
  && pass "H3 a subject's @, <, >, backtick, & and CR are neutralised in the posted list; the #N reference survives" || fail "H3 (rc=$RC lines=$lines)"

# ---- S15: every call in every scenario was an issue view or issue comment; no other gh call in source ----
bad=0
for d in "$ROOT"/mock*; do
  [[ -s "$d/calls" ]] || continue
  while IFS= read -r line; do
    case "$line" in "issue view "*|"issue comment "*) ;; *) bad=$((bad + 1)); echo "unexpected call: $line" ;; esac
  done < "$d/calls"
done
[[ "$bad" -eq 0 ]] && pass "S15a observed gh call set is a subset of {issue view, issue comment}" || fail "S15a ($bad unexpected calls)"
# S15b is an ALLOWLIST: every `gh <word> <word>` token in the comment-stripped source
# must be one of the two. Its own positive control drives the predicate with calls that
# must be refused, so a neutered predicate cannot read as a clean source.
ctl_ok=1
for probe in 'gh issue close 1' 'gh issue pin 1' 'gh label delete x' 'gh api repos/x' 'gh issue comment 1 --edit-last gh issue edit 1'; do
  [[ -n "$(gh_calls_bad "$probe")" ]] || ctl_ok=0
done
[[ -z "$(gh_calls_bad 'gh issue view 9564 and gh issue comment 9564')" ]] || ctl_ok=0
if [[ "$ctl_ok" -eq 1 && -z "$(gh_calls_bad "$sut_active")" ]]; then
  pass "S15b every gh call in the comment-stripped source is 'issue view' or 'issue comment' (allowlist, control refuses 5 other verbs)"
else
  fail "S15b source carries a gh call outside {issue view, issue comment} (control_ok=$ctl_ok bad=$(gh_calls_bad "$sut_active" | tr '\n' ' '))"
fi

# Exit-gate check (behavioural): this same suite, re-run with ONE injected failure, must
# exit EXACTLY 1. An `exit 0` placed before the gate, a reset FAIL counter, or a neutered
# exit path would all give 0 here; the FATAL below runs before any of them can.
if [[ -z "${WRN_INJECT_FAIL:-}" ]]; then
  WRN_INJECT_FAIL=1 bash "${BASH_SOURCE[0]}" >/dev/null 2>&1; nested_rc=$?
  [[ "$nested_rc" -eq 1 ]] || { printf 'FATAL: the exit gate returned %s (expected 1) with one injected failure\n' "$nested_rc" >&2; exit 2; }
else
  fail "injected failure (exit-gate check)"
fi

echo
echo "PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL"
# Anti-vacuity floor (ADR-193). The threshold is declared on the line IMMEDIATELY
# above the `if`, not with the other constants: guard-vacuity-floor builds its mutant
# by slicing the floor block plus the CONTIGUOUS simple assignments above it.
MIN_ASSERTIONS=35
if [[ "$TOTAL" -lt "$MIN_ASSERTIONS" ]]; then
  printf 'FATAL: assertion floor breached (TOTAL=%s < %s)\n' "$TOTAL" "$MIN_ASSERTIONS" >&2
  exit 2
fi
finish || exit 1
