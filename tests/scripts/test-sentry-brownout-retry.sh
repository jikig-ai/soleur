#!/usr/bin/env bash
# The brownout retry in apply-sentry-infra.yml must fire on exactly one signature.
#
# Why this exists: a retry is the easiest place in a pipeline to launder a real
# failure into a slow green. The value of this loop is not that it retries — it is
# that it REFUSES to retry anything except Sentry's deprecated alert-rule 410. So
# the assertions that matter most here are the negative ones.
#
# The loop is embedded in YAML, so the shape is extracted from the workflow and
# driven against fixtures. Extracting (rather than restating) is deliberate: a test
# that carries its own copy of the logic passes forever after the workflow drifts.
#
# Refs #7650.
set -uo pipefail

WF=".github/workflows/apply-sentry-infra.yml"
PASS=0; FAIL=0
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

[[ -f "$WF" ]] || { echo "FATAL: $WF not found (run from the repo root)" >&2; exit 2; }

# --- structural: the conjunction must be present at BOTH plan sites -------------
sites=$(grep -c 'SOLEUR_SENTRY_BROWNOUT_RETRY' "$WF")
[[ "$sites" -eq 2 ]] && pass "retry armed at both plan sites (found $sites)" \
  || fail "expected the retry at 2 plan sites, found $sites"

# Both conjuncts must be required. A retry keyed on 'status 410' alone would also
# fire for a 410 from any other Sentry endpoint, which is not what was measured.
conj=$(grep -cF "grep -q 'sentry_issue_alert\." "$WF")
[[ "$conj" -ge 2 ]] && pass "retry requires the deprecated-family resource, not just a 410" \
  || fail "the sentry_issue_alert conjunct is missing (found $conj, expected >= 2)"

# --- behavioural: drive the extracted shape against fixtures --------------------
TMP=$(mktemp -d) || { echo "FATAL: mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

# Extract the retry loop VERBATIM from the workflow instead of restating it. A test
# that carries its own copy of the logic keeps passing after the workflow drifts —
# measured: with a hand-written copy here, deleting the sentry_issue_alert conjunct
# from the YAML left this file fully green. Extraction is what makes the negative
# assertions below bind to the shipped code.
python3 - "$WF" > "$TMP/loop.sh" <<'PY'
import io, sys
src = io.open(sys.argv[1], encoding="utf-8").read()
i = src.index("while : ; do")
j = src.index("          done\n", i) + len("          done\n")
block = "\n".join(l[10:] if l.startswith(" " * 10) else l for l in src[i:j].split("\n"))
sys.stdout.write(
    "set -uo pipefail\n"
    "plan_attempts=3\n"
    "plan_backoff=(0 0)\n"
    "attempt=1\n"
    "sleep() { :; }\n"
    "terraform() { cat \"$FIXTURE\"; return \"$FIXRC\"; }\n"
    + block.replace("/tmp/sentry-plan.out", "$OUT")
    + "\necho \"rc=$rc attempts=$attempt\"\n")
PY
[[ -s "$TMP/loop.sh" ]] || { echo "FATAL: could not extract the retry loop from $WF" >&2; exit 2; }
grep -q 'status 410' "$TMP/loop.sh" || { echo "FATAL: extracted block lacks the retry condition — extraction anchor drifted" >&2; exit 2; }

# The loop tees plan output to stdout (that is what puts it in the CI log), so take
# only the final summary line rather than the whole transcript.
drive() { FIXTURE="$1" FIXRC="$2" OUT="$TMP/out" bash "$TMP/loop.sh" 2>/dev/null | tail -1; }

printf 'Error: Client error\n  with sentry_issue_alert.byok_art_33_breach,\nUnable to read, got status 410: {"message":"This API no longer exists."}\n' > "$TMP/brownout"
printf 'Error: Invalid resource type\n  on issue-alerts.tf line 12\nCould not resolve attribute "frequency".\n' > "$TMP/real"
printf 'Error: Client error\n  with sentry_cron_monitor.nightly,\nUnable to read, got status 410: {"message":"This API no longer exists."}\n' > "$TMP/other410"
printf 'No changes. Your infrastructure matches the configuration.\n' > "$TMP/clean"
# A GENUINE failure on a deprecated-family resource, with no 410. Found by mutation:
# without this fixture, replacing the `status 410` test with `true` left the suite
# green, because no other fixture pairs a real error with a sentry_issue_alert. It is
# the case that pins the 410 conjunct rather than the resource-name conjunct.
printf 'Error: Invalid Attribute Value\n  with sentry_issue_alert.byok_cap_exceeded,\n  on issue-alerts.tf line 40:\nfrequency must be one of [5 10 30].\n' > "$TMP/real_on_family"

r=$(drive "$TMP/brownout" 1)
[[ "$r" == "rc=1 attempts=3" ]] && pass "brownout 410 retries to the attempt budget ($r)" \
  || fail "brownout should retry to 3 attempts, got: $r"

# THE LOAD-BEARING NEGATIVE: a real failure must not be retried into a slow green.
r=$(drive "$TMP/real" 1)
[[ "$r" == "rc=1 attempts=1" ]] && pass "a genuine plan failure exits on the first attempt ($r)" \
  || fail "a genuine failure must NOT retry, got: $r"

# A 410 from a type outside the deprecated family must not arm the retry either.
r=$(drive "$TMP/other410" 1)
[[ "$r" == "rc=1 attempts=1" ]] && pass "a 410 on a non-deprecated type does not retry ($r)" \
  || fail "410 alone must not arm the retry, got: $r"

# Pins the 410 conjunct: same resource family, real error, must not retry.
r=$(drive "$TMP/real_on_family" 1)
[[ "$r" == "rc=1 attempts=1" ]] && pass "a real error ON a sentry_issue_alert does not retry ($r)" \
  || fail "a non-410 failure must NOT retry even on the deprecated family, got: $r"

r=$(drive "$TMP/clean" 0)
[[ "$r" == "rc=0 attempts=1" ]] && pass "a clean plan does not loop ($r)" \
  || fail "a successful plan must not loop, got: $r"

echo
echo "=== Results ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
# Anti-vacuity: 6 assertions are dispatched above; a lower count means the file
# did not run what it claims to cover.
if [[ $(( PASS + FAIL )) -lt 7 ]]; then
  echo "FAIL: only $(( PASS + FAIL )) assertions ran, expected >= 7 — the suite did not execute what it claims to cover."
  exit 1
fi
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
