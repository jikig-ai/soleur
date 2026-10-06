#!/usr/bin/env bash
# Suite for scripts/watch-registration-narrowing-9564.sh (the weekly watcher that
# posts ONE notice on the deferred registration-only narrowing tracker and never
# closes it). Mock-`gh` + fixture-git-history pattern: a PATH-prepended recording
# `gh` serves per-scenario issue JSON and logs every argv, so the property under
# test is the observed call set, never a list of call sites.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/watch-registration-narrowing-9564.sh"

PASS=0; FAIL=0; TOTAL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); }

# Instrument self-test (ADR-193): drive both branches, require both counters to
# move, report with printf + exit, never through the helpers under test.
pass "self-test" >/dev/null
fail "self-test" >/dev/null
if [[ "$PASS" -ne 1 || "$FAIL" -ne 1 || "$TOTAL" -ne 2 ]]; then
  printf 'FATAL: verdict helpers are not dispatching (PASS=%s FAIL=%s TOTAL=%s)\n' "$PASS" "$FAIL" "$TOTAL" >&2
  exit 2
fi
PASS=0; FAIL=0; TOTAL=0

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
bot_comment()  { printf '[{"author":{"login":"github-actions"},"body":"notice\\n%s"}]' "$SENTINEL"; }
bot_comment2() { printf '[{"author":{"login":"github-actions[bot]"},"body":"notice\\n%s"}]' "$SENTINEL"; }
human_comment() { printf '[{"author":{"login":"someone"},"body":"%s"}]' "$SENTINEL"; }

# Commit helpers. `q` adds one additive commit on a runner file (qualifying);
# `qs` does the same with a chosen subject. SHAS accumulates their short hashes.
SHAS=""
qs() { assert_fixture_dir "$REPO"; echo "line-$RANDOM-$RANDOM" >> "$REPO/$TEST_ALL"; g add -A; g commit -q -m "$1"; SHAS="$SHAS $(g log -1 --format=%h)"; }
q() { qs "add suite $1"; }
other_only() { assert_fixture_dir "$REPO"; echo "o2-$RANDOM" >> "$REPO/other.txt"; g add -A; g commit -q -m "docs only"; }
deleting() { assert_fixture_dir "$REPO"; tail -n +2 "$REPO/$TEST_ALL" > "$REPO/$TEST_ALL.new" && mv "$REPO/$TEST_ALL.new" "$REPO/$TEST_ALL"; g add -A; g commit -q -m "rewrite runner (deletes a line)"; }
merge_commit() {
  g checkout -q -b side && other_only && g checkout -q main && g merge -q --no-ff side -m "merge side" || { echo "FATAL: merge fixture failed" >&2; exit 2; }
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

# ---- S1: two qualifying commits -> silent green ----
mkrepo; q 1; q 2; run
[[ "$RC" -eq 0 && "$(comments_posted)" -eq 0 && "$OUT" == *"count=2"* ]] \
  && pass "S1 two qualifying commits: exit 0, no comment, count=2 reported" || fail "S1 (rc=$RC posted=$(comments_posted) out=$OUT)"

# ---- S2: exactly three -> exactly one comment naming count, SHAs, part (b), stays open ----
mkrepo; SHAS=""; q 1; q 2; q 3; run
body="$(cat "$MOCKD/bodies")"; ok=1
[[ "$RC" -eq 0 && "$(comments_posted)" -eq 1 ]] || ok=0
for s in $SHAS; do [[ "$body" == *"$s"* ]] || ok=0; done
[[ "$body" == *"part (b)"* && "$body" == *"stays open"* && "$body" == *"653 s"* && "$body" == *"54.4 min"* && "$body" == *"$SENTINEL"* ]] || ok=0
[[ "$body" == *"3 registration-shaped"* ]] || ok=0
[[ "$ok" -eq 1 ]] && pass "S2 count 3 posts exactly one notice with count, SHAs, part (b), stays-open, sentinel" || fail "S2 (rc=$RC posted=$(comments_posted))"

# ---- S3: three + bot-authored sentinel (both author spellings) -> no comment ----
mkrepo; q 1; q 2; q 3; issue OPEN "$(bot_comment)"; run
a="$(comments_posted)"
issue OPEN "$(bot_comment2)"; reset_calls; run
[[ "$a" -eq 0 && "$(comments_posted)" -eq 0 && "$RC" -eq 0 ]] && pass "S3 bot sentinel (github-actions and github-actions[bot]) suppresses the comment" || fail "S3 (first=$a second=$(comments_posted) rc=$RC)"

# ---- S3c: the bot sentinel is the SECOND comment (a human spoke first) -> still suppressed ----
mkrepo; q 1; q 2; q 3
issue OPEN '[{"author":{"login":"someone"},"body":"hello"},{"author":{"login":"github-actions"},"body":"notice\n'"$SENTINEL"'"}]'; run
[[ "$RC" -eq 0 && "$(comments_posted)" -eq 0 ]] && pass "S3c sentinel in a non-first bot comment still suppresses (every comment is read)" || fail "S3c (rc=$RC posted=$(comments_posted))"

# ---- S4: three + sentinel from a non-bot author -> forgery does not suppress ----
mkrepo; q 1; q 2; q 3; issue OPEN "$(human_comment)"; run
[[ "$RC" -eq 0 && "$(comments_posted)" -eq 1 ]] && pass "S4 forged sentinel from a non-bot account does not suppress the notice" || fail "S4 (rc=$RC posted=$(comments_posted))"

# ---- S5: five + bot sentinel -> once per threshold, not per increment ----
mkrepo; q 1; q 2; q 3; q 4; q 5; issue OPEN "$(bot_comment)"; run
[[ "$RC" -eq 0 && "$(comments_posted)" -eq 0 ]] && pass "S5 count 5 with the threshold sentinel present stays silent" || fail "S5 (rc=$RC posted=$(comments_posted))"

# ---- S6: CLOSED tracker self-disables, even with an unresolvable base ----
mkrepo; q 1; q 2; q 3; issue CLOSED '[]'; WATCH_BASE_SHA_OVERRIDE=0000000000000000000000000000000000000000; run; WATCH_BASE_SHA_OVERRIDE=""
[[ "$RC" -eq 0 && "$(comments_posted)" -eq 0 && "$ERR" != *"::error::"* ]] && pass "S6 closed tracker: exit 0, no comment, no base-commit error" || fail "S6 (rc=$RC err=$ERR)"

# ---- S7: issue/comments read fails -> exit 3 and nothing posted ----
mkrepo; q 1; q 2; q 3; flag view_fail; run
[[ "$RC" -eq 3 && "$(comments_posted)" -eq 0 ]] && pass "S7 failed read: exit 3, no comment (never risks a duplicate)" || fail "S7 (rc=$RC posted=$(comments_posted))"

# ---- S8: absent base on an OPEN tracker -> exit 3 with ::error::; failed post -> exit 1 ----
mkrepo; q 1; q 2; q 3; WATCH_BASE_SHA_OVERRIDE=0000000000000000000000000000000000000000; run; WATCH_BASE_SHA_OVERRIDE=""
[[ "$RC" -eq 3 && "$(comments_posted)" -eq 0 && "$ERR" == *"::error::"* ]] && pass "S8a absent base on an OPEN tracker: exit 3, ::error::, no comment" || fail "S8a (rc=$RC err=$ERR)"
mkrepo; q 1; q 2; q 3; flag comment_fail; run
[[ "$RC" -eq 1 && "$(comments_posted)" -eq 1 ]] && pass "S8b failed comment post: exit 1 (sentinel only ever lands with the comment)" || fail "S8b (rc=$RC posted=$(comments_posted))"

# ---- S10: other-path, merge and deleting commits are not counted; the exclusion is reported ----
mkrepo; q 1; q 2; other_only; merge_commit; deleting; run
[[ "$RC" -eq 0 && "$OUT" == *"count=2"* && "$OUT" == *"excluded=1"* && "$(comments_posted)" -eq 0 ]] \
  && pass "S10 only additive runner commits count (other-path, merge, deleting excluded; excluded=1)" || fail "S10 (rc=$RC out=$OUT)"

# ---- S11: --print-count works with an unresolvable base and stays read-only ----
mkrepo; q 1; WATCH_BASE_SHA_OVERRIDE=0000000000000000000000000000000000000000; run --print-count; WATCH_BASE_SHA_OVERRIDE=""
[[ "$RC" -eq 0 && "$OUT" == *"threshold=3"* && "$OUT" == *"count=unknown"* && "$(comments_posted)" -eq 0 ]] \
  && pass "S11a --print-count: threshold line printed, count=unknown, exit 0, no write" || fail "S11a (rc=$RC out=$OUT)"
mkrepo; q 1; q 2; q 3; run --print-count
[[ "$RC" -eq 0 && "$OUT" == *"threshold=3"* && "$OUT" == *"count=3"* && "$(comments_posted)" -eq 0 ]] \
  && pass "S11b --print-count at 3 reports count=3 and posts nothing" || fail "S11b (rc=$RC out=$OUT posted=$(comments_posted))"

# ---- H1: the recorder is alive (otherwise 'no write calls' passes vacuously) ----
mkrepo; q 1; run
grep -q '^issue view ' "$MOCKD/calls" && pass "H1 recorder logged the issue view call" || fail "H1 recorder is dead (calls log empty)"

# ---- H2: must-PASS non-canonical input: count 4, no sentinel, '#123' and a 300-char subject ----
mkrepo; long="$(printf 'x%.0s' $(seq 1 300))"; qs "fix #123 $long"; q 2; q 3; q 4; run
body="$(cat "$MOCKD/bodies")"; maxlen="$(printf '%s\n' "$body" | awk '/^- / { if (length($0) > m) m = length($0) } END { print m + 0 }')"
[[ "$RC" -eq 0 && "$(comments_posted)" -eq 1 && "$body" == *"#123"* && "$maxlen" -gt 100 && "$maxlen" -le 135 ]] \
  && pass "H2 count 4: exactly one comment, subjects with #123 and 300 chars are truncated (max line $maxlen)" || fail "H2 (rc=$RC posted=$(comments_posted) maxlen=$maxlen)"

# ---- S9: every call in every scenario was an issue view or issue comment; no write verb in source ----
bad=0
for d in "$ROOT"/mock*; do
  [[ -s "$d/calls" ]] || continue
  while IFS= read -r line; do
    case "$line" in "issue view "*|"issue comment "*) ;; *) bad=$((bad + 1)); echo "unexpected call: $line" ;; esac
  done < "$d/calls"
done
[[ "$bad" -eq 0 ]] && pass "S9a observed gh call set is a subset of {issue view, issue comment}" || fail "S9a ($bad unexpected calls)"
stripped="$(grep -vE '^[[:space:]]*#' "$SUT")"
[[ -s "$SUT" && -n "$stripped" ]] || { echo "FATAL: SUT missing or empty" >&2; exit 2; }
if printf '%s\n' "$stripped" | grep -qE 'gh +(issue +(close|edit|reopen|delete|lock|transfer)|api)'; then
  fail "S9b source carries a forbidden gh verb"
else
  pass "S9b source (comments stripped) carries no close/edit/reopen/delete/lock/transfer/api call"
fi

echo
echo "PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL"
# Anti-vacuity floor (ADR-193). The threshold is declared on the line IMMEDIATELY
# above the `if`, not with the other constants: guard-vacuity-floor builds its mutant
# by slicing the floor block plus the CONTIGUOUS simple assignments above it.
MIN_ASSERTIONS=17
if [[ "$TOTAL" -lt "$MIN_ASSERTIONS" ]]; then
  printf 'FATAL: assertion floor breached (TOTAL=%s < %s)\n' "$TOTAL" "$MIN_ASSERTIONS" >&2
  exit 2
fi
[[ "$FAIL" -eq 0 ]] || exit 1
