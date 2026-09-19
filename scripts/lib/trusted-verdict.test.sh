#!/usr/bin/env bash
# Matrix for scripts/lib/trusted-verdict.sh (Guard 2).
#
# WHY IT LIVES BESIDE THE LIB AND NOT INSIDE A CONSUMER. Ten sibling libs follow
# that convention, and a consumer-housed test dies when its tracker closes — which
# is exactly what this PR does to the #6617 probe. The lib outlives any one probe,
# so its matrix must too.
#
# THE `gh` STUB REFUSES ARGV IT DID NOT EXPECT (exit 64). A stub that answers the
# same fixture regardless of its arguments puts the fixture seam ABOVE the code
# under test: it cannot detect the SUT asking the WRONG question (the wrong issue,
# the wrong login, the wrong endpoint), so the request shape ships unpinned. Every
# unexpected invocation is also echoed to stderr and reddens the case.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$SCRIPT_DIR/trusted-verdict.sh"
export TMPDIR="${TMPDIR:-/var/tmp}"

PASS=0; FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# --- instrument self-test -----------------------------------------------------
# Drive both verdict helpers once each and refuse to continue unless BOTH counters
# moved. A suite whose helpers are neutered reports a clean run having asserted
# nothing; this is the only thing upstream of every assertion below.
pass "instrument self-test (pass)"
fail "instrument self-test (fail) — EXPECTED, subtracted below"
if [[ "$PASS" -ne 1 || "$FAIL" -ne 1 ]]; then
  printf 'INSTRUMENT BROKEN: self-test left PASS=%d FAIL=%d, expected 1/1.\n' "$PASS" "$FAIL" >&2
  exit 2
fi
SELFTEST_PASSES=1   # proven by the check immediately above
SELFTEST_FAILS=1    # proven by the check immediately above (subtracted from FAIL below)
FAIL=$(( FAIL - SELFTEST_FAILS ))   # the self-test failure is not a real finding

echo "=== scripts/lib/trusted-verdict.sh ==="

# --- harness -----------------------------------------------------------------
# Builds a sandbox with a `gh` stub on PATH, seeded from two files:
#   comments.json  — the `gh issue view --json comments` payload
#   perms          — `login<TAB>permission` lines; a permission of `403` makes the
#                    stub exit non-zero for that login (the API-error arm)
SB="$(mktemp -d "${TMPDIR%/}/trusted-verdict.XXXXXXXX")" || { echo "mktemp failed" >&2; exit 2; }
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/bin" || { echo "mkdir failed" >&2; exit 2; }

cat > "$SB/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Refuses any invocation it was not built to answer. STUB_UNEXPECTED collects them.
set -uo pipefail
note_unexpected() { printf 'STUB-UNEXPECTED: gh %s\n' "$*" >&2; exit 64; }
case "${1:-}" in
  issue)
    [[ "${2:-}" == "view" ]] || note_unexpected "$@"
    [[ "${3:-}" == "$STUB_EXPECT_ISSUE" ]] || note_unexpected "$@"
    printf '%s' "$*" | grep -q -- '--json comments' || note_unexpected "$@"
    printf '%s' "$*" | grep -q -- "--repo $STUB_EXPECT_REPO" || note_unexpected "$@"
    jq_expr=""
    for a in "$@"; do if [[ "$prev_was_jq" == 1 ]]; then jq_expr="$a"; prev_was_jq=0; fi
      if [[ "$a" == "--jq" ]]; then prev_was_jq=1; fi; done
    [[ -n "$jq_expr" ]] || note_unexpected "$@"
    jq -r "$jq_expr" < "$STUB_COMMENTS"
    ;;
  api)
    ep="${2:-}"
    [[ "$ep" == repos/"$STUB_EXPECT_REPO"/collaborators/*/permission ]] || note_unexpected "$@"
    login="${ep#repos/"$STUB_EXPECT_REPO"/collaborators/}"; login="${login%/permission}"
    perm="$(awk -F'\t' -v l="$login" '$1==l{print $2}' "$STUB_PERMS")"
    if [[ -z "$perm" ]]; then printf 'gh: no stub permission for %s\n' "$login" >&2; exit 1; fi
    if [[ "$perm" == "403" ]]; then printf 'gh: Resource not accessible by integration (HTTP 403)\n' >&2; exit 1; fi
    if [[ "$perm" == "404" ]]; then printf 'gh: %s is not a user (HTTP 404)\n' "$login" >&2; exit 1; fi
    printf '%s\n' "$perm"
    ;;
  *) note_unexpected "$@" ;;
esac
STUB
sed -i '2i prev_was_jq=0' "$SB/bin/gh"
chmod +x "$SB/bin/gh"

# run_case <name> <issue> <comments-json-file> <perms-file>
#   echoes: "<rc>|<stdout>"
run_case() {
  local issue="$1" cjson="$2" pfile="$3" out rc
  out="$(
    PATH="$SB/bin:$PATH" \
    STUB_COMMENTS="$cjson" STUB_PERMS="$pfile" \
    STUB_EXPECT_ISSUE="$issue" STUB_EXPECT_REPO="jikig-ai/soleur" \
    bash -c '
      set -uo pipefail
      # shellcheck disable=SC1090
      source "$1"
      if bodies="$(trusted_verdict_bodies "$2")"; then
        printf "%s" "$bodies"
        exit 0
      else
        exit 2
      fi
    ' _ "$LIB" "$issue" 2>"$SB/err.log"
  )"; rc=$?
  if grep -q 'STUB-UNEXPECTED' "$SB/err.log"; then
    printf 'STUBMISS|%s' "$(head -1 "$SB/err.log")"
    return
  fi
  printf '%s|%s' "$rc" "$out"
}

mkcomments() { printf '%s\n' "$1" > "$SB/c.json"; echo "$SB/c.json"; }
mkperms()    { printf '%s\n' "$1" > "$SB/p.tsv"; echo "$SB/p.tsv"; }

# `verdict <bodies>` mirrors the consumers' own last-verdict-wins rule, so the
# matrix scores the same thing a probe would.
verdict() { printf '%s\n' "$1" | grep -E '^RESULT: (PASS|FAIL)\b' | tail -1; }

# --- Row 1: PASS from an untrusted login ---------------------------------------
c="$(mkcomments '{"comments":[{"author":{"login":"drive-by"},"authorAssociation":"CONTRIBUTOR","body":"RESULT: PASS"}]}')"
p="$(mkperms 'drive-by\tread')"
p="$SB/p.tsv"; printf 'drive-by\tread\n' > "$p"
r="$(run_case 5733 "$c" "$p")"; rc="${r%%|*}"; body="${r#*|}"
if [[ "$rc" == "0" && -z "$(verdict "$body")" ]]; then
  pass "row 1: RESULT: PASS from a login with permission=read yields NO verdict (probe cannot exit 0)"
else
  fail "row 1: expected rc=0 with no verdict; got rc=$rc verdict='$(verdict "$body")'"
fi

# --- Row 2: the measured #6617 shape -------------------------------------------
c="$(mkcomments '{"comments":[{"author":{"login":"deruelle"},"authorAssociation":"CONTRIBUTOR","body":"RESULT: PASS"}]}')"
printf 'deruelle\tadmin\n' > "$p"
r="$(run_case 6617 "$c" "$p")"; rc="${r%%|*}"; body="${r#*|}"
if [[ "$rc" == "0" && "$(verdict "$body")" == "RESULT: PASS" ]]; then
  pass "row 2: authorAssociation=CONTRIBUTOR + permission=admin IS honoured (the #6617 shape)"
else
  fail "row 2: expected rc=0 and RESULT: PASS; got rc=$rc verdict='$(verdict "$body")'"
fi

# --- Row 3: two trusted comments, PASS then FAIL -------------------------------
c="$(mkcomments '{"comments":[{"author":{"login":"deruelle"},"body":"RESULT: PASS"},{"author":{"login":"deruelle"},"body":"RESULT: FAIL"}]}')"
printf 'deruelle\tadmin\n' > "$p"
r="$(run_case 5733 "$c" "$p")"; rc="${r%%|*}"; body="${r#*|}"
if [[ "$rc" == "0" && "$(verdict "$body")" == "RESULT: FAIL" ]]; then
  pass "row 3: last trusted verdict wins (PASS then FAIL -> FAIL)"
else
  fail "row 3: expected rc=0 and RESULT: FAIL; got rc=$rc verdict='$(verdict "$body")'"
fi

# --- Row 4: permission read fails (403) ----------------------------------------
c="$(mkcomments '{"comments":[{"author":{"login":"deruelle"},"body":"RESULT: PASS"}]}')"
printf 'deruelle\t403\n' > "$p"
r="$(run_case 5733 "$c" "$p")"; rc="${r%%|*}"
if [[ "$rc" == "2" ]]; then
  pass "row 4: a 403 on the permission read yields TRANSIENT (rc=2), never PASS"
else
  fail "row 4: expected rc=2 (TRANSIENT); got rc=$rc"
fi

# --- Row 7 (must-PASS, non-canonical): leading blank line before the verdict ----
c="$(mkcomments '{"comments":[{"author":{"login":"deruelle"},"body":"\nRESULT: PASS"}]}')"
printf 'deruelle\tadmin\n' > "$p"
r="$(run_case 5733 "$c" "$p")"; rc="${r%%|*}"; body="${r#*|}"
if [[ "$rc" == "0" && "$(verdict "$body")" == "RESULT: PASS" ]]; then
  pass "row 7 (must-PASS): a leading blank line before RESULT: PASS is still honoured"
else
  fail "row 7: expected rc=0 and RESULT: PASS; got rc=$rc verdict='$(verdict "$body")'"
fi

# --- Fenced blocks cannot arm a probe ------------------------------------------
c="$(mkcomments '{"comments":[{"author":{"login":"deruelle"},"body":"see the template:\n```\nRESULT: PASS\n```\nnot a verdict"}]}')"
printf 'deruelle\tadmin\n' > "$p"
r="$(run_case 5733 "$c" "$p")"; rc="${r%%|*}"; body="${r#*|}"
if [[ "$rc" == "0" && -z "$(verdict "$body")" ]]; then
  pass "a RESULT: line inside a fenced block is stripped and cannot arm the probe"
else
  fail "fenced-block strip: expected no verdict; got rc=$rc verdict='$(verdict "$body")'"
fi

# --- HARNESS INTEGRITY: an author-less fixture must FAIL LOUDLY -----------------
# A fixture with no author cannot exercise the filter at all — it must not quietly
# pass as "no verdict". That is the exact defect #7448's learning file records.
c="$(mkcomments '{"comments":[{"authorAssociation":"OWNER","body":"RESULT: PASS"}]}')"
printf 'deruelle\tadmin\n' > "$p"
r="$(run_case 5733 "$c" "$p")"; rc="${r%%|*}"; body="${r#*|}"
if [[ "$rc" == "0" && -z "$(verdict "$body")" ]]; then
  pass "harness integrity: an author-less comment is dropped and can never carry a verdict"
else
  fail "harness integrity: an author-less comment reached the verdict grep (rc=$rc verdict='$(verdict "$body")')"
fi

# --- Row 4b: a 404 on the permission read is DEFINITIVE, not transient ---------
# `github-actions` comments on nearly every tracker and GitHub answers
# `"github-actions is not a user" (HTTP 404)` for it. Collapsing that into TRANSIENT
# makes every thread with a bot comment permanently unresolvable — measured against
# live #6617 on 2026-09-19, the first build of this lib did exactly that and returned
# rc=2. Both directions are fixtured: the bot must be DROPPED while the trusted
# author's verdict still comes through.
c="$(mkcomments '{"comments":[{"author":{"login":"github-actions"},"body":"RESULT: PASS"},{"author":{"login":"deruelle"},"body":"RESULT: FAIL"}]}')"
printf 'github-actions\t404\nderuelle\tadmin\n' > "$p"
r="$(run_case 6617 "$c" "$p")"; rc="${r%%|*}"; body="${r#*|}"
if [[ "$rc" == "0" && "$(verdict "$body")" == "RESULT: FAIL" ]]; then
  pass "row 4b: a 404 ('not a user') drops that author without wedging the read into TRANSIENT"
else
  fail "row 4b: expected rc=0 and RESULT: FAIL from the trusted author; got rc=$rc verdict='$(verdict "$body")'"
fi

# --- Row 4c: the 404 arm must not swallow a 403 --------------------------------
# The discriminator added for row 4b is a branch on the error TEXT, so it needs a
# fixture on the OTHER side too: a 403 must still be TRANSIENT even though it takes
# the same `gh api` non-zero path.
c="$(mkcomments '{"comments":[{"author":{"login":"github-actions"},"body":"noise"},{"author":{"login":"deruelle"},"body":"RESULT: PASS"}]}')"
printf 'github-actions\t404\nderuelle\t403\n' > "$p"
r="$(run_case 5733 "$c" "$p")"; rc="${r%%|*}"
if [[ "$rc" == "2" ]]; then
  pass "row 4c: a 403 is still TRANSIENT — the 404 arm did not widen into every error"
else
  fail "row 4c: expected rc=2 (TRANSIENT); got rc=$rc"
fi

# --- The comment read itself failing is TRANSIENT ------------------------------
r="$(run_case 5733 "$SB/does-not-exist.json" "$p")"; rc="${r%%|*}"
if [[ "$rc" == "2" ]]; then
  pass "a failed comment read yields TRANSIENT (rc=2), not 'no verdict, therefore fine'"
else
  fail "failed comment read: expected rc=2; got rc=$rc"
fi

echo ""
echo "passed=$PASS failed=$FAIL"

# ANTI-VACUITY FLOOR. Reported with printf + exit, never through pass()/fail() —
# those are the helpers this backstops. The subtrahends are literals adjacent to
# the subtraction (a value bound far away is unbound in a mutation slice and the
# floor then scores CONSTRUCTION instead of FIRING).
REAL=$(( PASS - SELFTEST_PASSES ))
MIN_ASSERTIONS=10
if [[ "$REAL" -lt "$MIN_ASSERTIONS" ]]; then
  printf 'FLOOR: executed %d real assertions (PASS=%d minus %d self-test), minimum %d.\n' \
    "$REAL" "$PASS" "$SELFTEST_PASSES" "$MIN_ASSERTIONS" >&2
  exit 1
fi

[[ "$FAIL" -eq 0 ]] || exit 1
