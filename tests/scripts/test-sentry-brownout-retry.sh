#!/usr/bin/env bash
# The brownout retry in apply-sentry-infra.yml must arm on exactly one condition.
#
# A retry is the easiest place in a pipeline to launder a real failure into a slow
# green, and this workflow gates production Sentry paging including GDPR Art.33
# rules. So the assertions that matter most here are the NEGATIVE ones, and the
# thing under test is the shipped code, not a restatement of it.
#
# HISTORY, because it is the reason this file is shaped the way it is. Two earlier
# versions were vacuous in ways that read as thorough:
#
#   v1 restated the loop inline. Deleting the load-bearing condition from the YAML
#      (verified 2 occurrences -> 0) left it green at 6/6.
#   v2 extracted the loop, but `str.index` took only the FIRST match, so every
#      behavioural assertion drove the plan_pr job and the apply job — the one that
#      touches live infrastructure — was covered by nothing executable. It also
#      supplied plan_attempts itself, making `attempts=3` a tautology, and stopped
#      the slice at `done`, leaving the `exit $rc` handler (the actual laundering
#      surface) untested. Five mutations survived, including exit $rc -> exit 0.
#
# So: BOTH sites are enumerated and driven, the slice runs through the exit
# handler, and every constant comes from the workflow rather than from here.
#
# Fixtures carry terraform's `Refreshing state...` preamble because that is what
# made the original two-grep conjunct a tautology: the banner names every
# sentry_issue_alert in state on EVERY plan, so a document-level "mentions
# sentry_issue_alert" test is true on a clean run. A fixture without the preamble
# cannot catch that, and did not.
#
# Refs #7650.
set -uo pipefail

WF=".github/workflows/apply-sentry-infra.yml"
PASS=0; FAIL=0
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

[[ -f "$WF" ]] || { echo "FATAL: $WF not found (run from the repo root)" >&2; exit 2; }
TMP=$(mktemp -d) || { echo "FATAL: mktemp -d failed" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# Extract each retry site VERBATIM, from the backoff schedule through the exit
# handler. Structural anchors only: keying the integrity check on content that is
# itself under test (e.g. grepping for `status 410`) conflates "extraction worked"
# with "the condition is present", and a comment satisfies it either way.
# ---------------------------------------------------------------------------
python3 - "$WF" "$TMP" <<'PY'
import io, sys
src = io.open(sys.argv[1], encoding="utf-8").read()
tmp = sys.argv[2]
START, END = "          plan_backoff=(", "          set -e\n"
starts = []
i = 0
while True:
    i = src.find(START, i)
    if i == -1: break
    starts.append(i); i += 1
if len(starts) != 2:
    sys.stderr.write("FATAL: expected exactly 2 retry sites, found %d — extraction anchor drifted\n" % len(starts))
    sys.exit(2)
for n, st in enumerate(starts, 1):
    en = src.find(END, st)
    if en == -1:
        sys.stderr.write("FATAL: site %d has no `set -e` terminator\n" % n); sys.exit(2)
    block = src[st:en]
    if block.count("while : ; do") != 1 or "exit $rc" not in block:
        sys.stderr.write("FATAL: site %d slice is not a whole retry block\n" % n); sys.exit(2)
    if len(block.splitlines()) > 90:
        sys.stderr.write("FATAL: site %d slice is %d lines — anchors likely spanned two blocks\n"
                         % (n, len(block.splitlines()))); sys.exit(2)
    body = "\n".join(l[10:] if l.startswith(" " * 10) else l for l in block.split("\n"))
    body = body.replace("/tmp/sentry-plan.out", "$OUT")
    # Only `sleep` and `terraform` are stubbed. Every constant — the backoff
    # schedule, the derived attempt budget — executes as shipped.
    io.open("%s/site%d.sh" % (tmp, n), "w", encoding="utf-8").write(
        "set -uo pipefail\n"
        'sleep() { echo "SLEPT $1" >&2; }\n'
        'terraform() {\n'
        '  _n=$(cat "$OUT.attempt" 2>/dev/null || echo 0); _n=$((_n+1)); echo "$_n" > "$OUT.attempt"\n'
        '  _f=$(printf %s "$FIXTURE" | cut -d, -f${_n}); [ -n "$_f" ] || _f=${FIXTURE##*,}\n'
        '  _r=$(printf %s "$FIXRC"   | cut -d, -f${_n}); [ -n "$_r" ] || _r=${FIXRC##*,}\n'
        '  cat "$_f"; return "$_r"\n'
        '}\n'
        + body)
PY
[[ $? -eq 0 ]] || exit 2

for n in 1 2; do
  [[ -s "$TMP/site$n.sh" ]] || { echo "FATAL: site $n extracted empty" >&2; exit 2; }
  # If the workflow renames its temp file, the substitution silently no-ops and the
  # harness would read and write the REAL /tmp. Refuse rather than escape the sandbox.
  grep -q '/tmp/' "$TMP/site$n.sh" && { echo "FATAL: site $n still references /tmp after substitution — rename the fixture path in the test" >&2; exit 2; }
done

# ---------------------------------------------------------------------------
# Fixtures. Shaped like real terraform output, refresh preamble included.
# ---------------------------------------------------------------------------
preamble() {
  printf 'sentry_issue_alert.byok_art_33_breach: Refreshing state... [id=637555]\n'
  printf 'sentry_issue_alert.zot_mirror_fallback_rate: Refreshing state... [id=724212]\n'
  printf 'sentry_cron_monitor.nightly: Refreshing state... [id=1509581]\n'
}
stanza() { # $1=resource  $2=tail line
  printf 'Error: Client error\n\n  with %s,\n  on issue-alerts.tf line 45, in resource:\n\n%s\n' "$1" "$2"
}
S410='Unable to read, got status 410: {"message":"This API no longer exists."}'

{ preamble; stanza 'sentry_issue_alert.byok_art_33_breach' "$S410"; } > "$TMP/brownout"
{ preamble; printf 'No changes. Your infrastructure matches the configuration.\n'; } > "$TMP/clean"
{ preamble; stanza 'sentry_issue_alert.byok_cap_exceeded' 'frequency must be one of [5 10 30].'; } > "$TMP/real_on_family"
{ preamble; stanza 'sentry_cron_monitor.nightly' "$S410"; } > "$TMP/other410"
# The case the tautology made unreachable: a brownout 410 co-occurring with a
# genuine unrelated failure. Retrying this would retry the real error away under
# the brownout's authorisation, and blame the wrong cause if it persisted.
{ preamble; stanza 'sentry_issue_alert.byok_art_33_breach' "$S410"
            stanza 'sentry_uptime_monitor.www' 'Unable to read, got status 500: upstream error'; } > "$TMP/mixed"

# ---------------------------------------------------------------------------
# Drive. Assert the process EXIT STATUS (the block ends in `exit $rc`, which is
# the laundering surface) and count retry markers rather than parsing a summary
# line — a fixture without a trailing newline would corrupt positional parsing.
# `timeout` converts an unbounded-retry mutation into a red test instead of a
# six-hour CI hang.
# ---------------------------------------------------------------------------
drive() { # $1=fixture $2=terraform-rc $3=site -> "exit=<n> attempts=<n> slept=<csv>"
  local out st
  rm -f "$TMP/out.$3.attempt"
  out=$(FIXTURE="$1" FIXRC="$2" OUT="$TMP/out.$3" timeout 20 bash "$TMP/site$3.sh" 2>&1)
  st=$?
  local retries slept cleared
  retries=$(grep -c 'SOLEUR_SENTRY_BROWNOUT outcome=retry' <<<"$out")
  slept=$(grep -o 'SLEPT [0-9]*' <<<"$out" | awk '{printf "%s%s", (NR>1?",":""), $2}')
  cleared=$(grep -c 'SOLEUR_SENTRY_BROWNOUT outcome=cleared' <<<"$out")
  printf %s "$out" > "$TMP/last_out"
  echo "exit=$st attempts=$((retries+1)) slept=${slept:-none} cleared=$cleared"
}

expect() { # $1=label $2=want $3=fixture $4=rc $5=site
  local got; got=$(drive "$3" "$4" "$5")
  if [[ "$got" == "$2" ]]; then pass "site $5: $1 ($got)"
  else fail "site $5: $1 — want [$2] got [$got]"; tail -4 "$TMP/last_out" 2>/dev/null | sed 's/^/        | /'; fi
}

for site in 1 2; do
  # Retries to the budget, honours the SHIPPED backoff schedule, exits non-zero.
  expect "brownout retries to budget with shipped backoff" \
         "exit=1 attempts=3 slept=60,150 cleared=0" "$TMP/brownout" 1 "$site"
  # THE LOAD-BEARING NEGATIVES.
  expect "a genuine error on the deprecated family does not retry" \
         "exit=1 attempts=1 slept=none cleared=0" "$TMP/real_on_family" 1 "$site"
  expect "a 410 on a non-family resource does not retry" \
         "exit=1 attempts=1 slept=none cleared=0" "$TMP/other410" 1 "$site"
  expect "a brownout mixed with a real failure does not retry" \
         "exit=1 attempts=1 slept=none cleared=0" "$TMP/mixed" 1 "$site"
  expect "a clean plan does not loop and exits 0" \
         "exit=0 attempts=1 slept=none cleared=0" "$TMP/clean" 0 "$site"
  # The countable event: a brownout that CLEARS on retry. Without this marker the log
  # shows "we retried" and never "it worked", so the frequency probe cannot separate a
  # resolved brownout from one still in progress. cleared=0 on every scenario above
  # also pins that it is NOT emitted on a first-attempt pass.
  expect "a brownout that clears on retry reports outcome=cleared" \
         "exit=0 attempts=2 slept=60 cleared=1" "$TMP/brownout,$TMP/clean" "1,0" "$site"
done

echo
echo "=== Results ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"
# 12 dispatches (6 scenarios x 2 sites). Sized to the measured count with no slack:
# deleting one assertion must red the suite, not merely lower the number.
if [[ $(( PASS + FAIL )) -lt 12 ]]; then
  echo "FAIL: only $(( PASS + FAIL )) assertions ran, expected >= 12 — the suite did not execute what it claims to cover."
  exit 1
fi
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
