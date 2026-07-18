#!/usr/bin/env bash
# Exit-code harness for ci-deploy-sentry-post-fail-6475.sh (#6475 Item 2 / D-6, AC5).
#
# The follow-through's exit code IS its authorization artifact (sweep-followthroughs.sh
# closes #6475 on 0, comments+leaves-open on 1, retries on anything else). The cardinal
# sin is a vacuous exit 0 that auto-closes #6475 while a Sentry POST failure is live, or
# a spurious exit 1 that pages on a clean codebase. Every case here pins one arm of the
# POST-failure / liveness / fail-safe decision tree.
#
# FIXTURE FIDELITY (load-bearing). Better Stack's `raw` column is the full journald
# JSON, and betterstack-query.sh emits it via `FORMAT JSONEachRow`, so the inner quotes
# arrive backslash-ESCAPED on stdout (`\"SYSLOG_IDENTIFIER\":\"ci-deploy\"`). The
# fixtures below reproduce that exact escaped shape — an earlier bare-syslog fixture
# (`<13>ci-deploy: …`) gave a false green while the SUT false-FAILed against live prod,
# because inngest ships GitHub-webhook logs (SYSLOG_IDENTIFIER=doppler) to the same
# source that embed both "Sentry POST failed" and "ci-deploy" (branch names / issue
# bodies). Case 7 reproduces that contamination and pins the field-isolated fix.
#
# SEAM: the SUT reads its Better Stack rows from the query script named by
# CI_DEPLOY_SENTRY_BQ. The mock below is FAITHFUL to betterstack-query.sh: server-side
# it runs `raw LIKE '%term%'` against the UNescaped column, so the mock matches each
# --grep term against a backslash-STRIPPED copy of the fixture line (approximating the
# column) while emitting the ORIGINAL escaped line — exactly the real pipeline. It also
# supports a per-term fault (3rd make_mock arg) to model one query faulting while the
# other returns rows. No network, no creds.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/ci-deploy-sentry-post-fail-6475.sh"
fails=0
pass() { printf '  PASS: %s\n' "$1"; }
fail() { printf '  FAIL: %s\n' "$1" >&2; fails=$((fails + 1)); }

[[ -f "$SUT" ]] || { echo "FATAL: SUT not found at $SUT" >&2; exit 1; }
[[ -x "$SUT" ]] || { echo "FATAL: SUT not executable at $SUT" >&2; exit 1; }

# Creds present for every normal case (the SUT gates on their presence); the dedicated
# "empty creds" case unsets them explicitly.
export BETTERSTACK_QUERY_HOST=dummy-host
export BETTERSTACK_QUERY_USERNAME=dummy-user
export BETTERSTACK_QUERY_PASSWORD=dummy-pass

WORK="$(mktemp -d)"
trap 'rm -f "$MOCK" 2>/dev/null; rm -rf "$WORK" 2>/dev/null' EXIT
MOCK="$WORK/mock-bq.sh"

# make_mock <fixture-file> <exit-rc> [<fault-term>] — a betterstack-query.sh stand-in.
# If <exit-rc> != 0 it faults for ALL calls (creds/query fault). Otherwise, if any
# --grep term equals <fault-term> it exits 3 (per-term fault); else it emits the
# fixture lines whose backslash-STRIPPED form contains ANY term (OR-combined, faithful
# to `raw LIKE` on the unescaped column), verbatim (escaped).
make_mock() {
  local fixture="$1" rc="$2" fault_term="${3:-}"
  cat > "$MOCK" <<MOCKEOF
#!/usr/bin/env bash
set -uo pipefail
terms=()
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --grep) terms+=("\$2"); shift 2 ;;
    --since|--until|--limit|--table|--table-s3) shift 2 ;;
    *) shift ;;
  esac
done
if [[ $rc -ne 0 ]]; then exit $rc; fi
fault_term='$fault_term'
if [[ -n "\$fault_term" ]]; then
  for t in "\${terms[@]}"; do [[ "\$t" == "\$fault_term" ]] && exit 3; done
fi
if [[ \${#terms[@]} -eq 0 ]]; then cat "$fixture"; exit 0; fi
while IFS= read -r line; do
  probe="\${line//\\\\/}"   # strip backslashes -> approximates the unescaped column
  for t in "\${terms[@]}"; do
    if [[ "\$probe" == *"\$t"* ]]; then printf '%s\n' "\$line"; break; fi
  done
done < "$fixture"
exit 0
MOCKEOF
  chmod 0755 "$MOCK"
}

# run_case <desc> <expected-rc> — assert the SUT exits expected-rc with the current MOCK.
run_case() {
  local desc="$1" expected="$2" rc=0 out
  out="$(CI_DEPLOY_SENTRY_BQ="$MOCK" "$SUT" 2>&1)" || rc=$?
  if [[ "$rc" -eq "$expected" ]]; then
    pass "$desc (exit=$rc)"
  else
    fail "$desc — expected exit=$expected got exit=$rc :: ${out:0:220}"
  fi
}

# Fixtures: synthesized JSONEachRow rows (cq-test-fixtures-synthesized-only) in the REAL
# escaped `raw` shape betterstack-query.sh emits. A real ci-deploy emission carries the
# top-level journald field `\"SYSLOG_IDENTIFIER\":\"ci-deploy\"`; webhook contamination
# carries a different identifier (doppler) with the markers only in its message payload.

# 1. FAIL (load-bearing alarm) — a real ci-deploy row (SYSLOG_IDENTIFIER field) carries
#    "Sentry POST failed".
cat > "$WORK/fx-fail.json" <<'EOF'
{"dt":"2026-07-18T09:00:00Z","raw":"{\"SYSLOG_IDENTIFIER\":\"ci-deploy\",\"MESSAGE\":\"deploy start web-1\",\"host\":\"soleur-web-platform\"}"}
{"dt":"2026-07-18T09:04:12Z","raw":"{\"SYSLOG_IDENTIFIER\":\"ci-deploy\",\"MESSAGE\":\"SANDBOX_CANARY: Sentry POST failed\",\"host\":\"soleur-web-platform\"}"}
EOF
make_mock "$WORK/fx-fail.json" 0
run_case "real ci-deploy 'Sentry POST failed' + liveness -> FAIL (loud alarm)" 1

# 2. PASS — real ci-deploy activity (field present), zero "Sentry POST failed".
cat > "$WORK/fx-pass.json" <<'EOF'
{"dt":"2026-07-18T09:00:00Z","raw":"{\"SYSLOG_IDENTIFIER\":\"ci-deploy\",\"MESSAGE\":\"deploy start web-1\",\"host\":\"soleur-web-platform\"}"}
{"dt":"2026-07-18T09:05:00Z","raw":"{\"SYSLOG_IDENTIFIER\":\"ci-deploy\",\"MESSAGE\":\"deploy complete web-1\",\"host\":\"soleur-web-platform\"}"}
EOF
make_mock "$WORK/fx-pass.json" 0
run_case "clean ci-deploy activity, no POST failure -> PASS" 0

# 3. TRANSIENT — zero ci-deploy (field) rows entirely (source dark / no deploys).
: > "$WORK/fx-zero.json"
make_mock "$WORK/fx-zero.json" 0
run_case "zero ci-deploy liveness (source dark) -> TRANSIENT (not vacuous PASS)" 2

# 4. TRANSIENT — betterstack-query.sh non-zero (creds/query fault). Never PASS/FAIL.
make_mock "$WORK/fx-pass.json" 3
run_case "betterstack-query fault -> TRANSIENT" 2

# 5. TRANSIENT — BETTERSTACK_QUERY_* unset. Must be exit 2, NEVER exit 1 (a `:?` gate
#    would abort with status 1 = FAIL = false alarm on a green codebase).
make_mock "$WORK/fx-pass.json" 0
rc=0
out="$(env -u BETTERSTACK_QUERY_HOST -u BETTERSTACK_QUERY_USERNAME -u BETTERSTACK_QUERY_PASSWORD \
  CI_DEPLOY_SENTRY_BQ="$MOCK" "$SUT" 2>&1)" || rc=$?
if [[ "$rc" -eq 2 ]]; then pass "unset BETTERSTACK_QUERY_* -> TRANSIENT (exit=$rc, never 1)"
else fail "unset creds — expected exit=2 got exit=$rc :: ${out:0:200}"; fi

# 6. TRANSIENT — invalid soak window (guard before any query).
rc=0
out="$(CI_DEPLOY_SENTRY_BQ="$MOCK" CI_DEPLOY_SENTRY_SOAK_WINDOW="bogus" "$SUT" 2>&1)" || rc=$?
if [[ "$rc" -eq 2 ]]; then pass "invalid CI_DEPLOY_SENTRY_SOAK_WINDOW -> TRANSIENT (exit=$rc)"
else fail "invalid window — expected exit=2 got exit=$rc :: ${out:0:200}"; fi

# 7. PASS (contamination discriminator, LOAD-BEARING — reproduces the live false-FAIL).
#    An inngest webhook row (SYSLOG_IDENTIFIER=doppler) embeds BOTH "Sentry POST failed"
#    and "ci-deploy" (branch name + issue-body quote) in its message payload, but is NOT
#    a real ci-deploy emission. The field-isolated post-filter drops it; ci-deploy
#    liveness is otherwise clean -> PASS. Under the OLD bare-`grep ci-deploy` post-filter
#    this arm FAILed (the defect this PR fixes).
cat > "$WORK/fx-contamination.json" <<'EOF'
{"dt":"2026-07-18T09:00:00Z","raw":"{\"SYSLOG_IDENTIFIER\":\"ci-deploy\",\"MESSAGE\":\"deploy complete web-1\",\"host\":\"soleur-web-platform\"}"}
{"dt":"2026-07-18T09:10:00Z","raw":"{\"SYSLOG_IDENTIFIER\":\"doppler\",\"MESSAGE\":\"GitHub webhook push ref refs/heads/feat-one-shot-6475-ci-deploy-sentry-fail-loud quotes: logger -t ci-deploy <TAG>: Sentry POST failed\",\"host\":\"soleur-web-platform\"}"}
EOF
make_mock "$WORK/fx-contamination.json" 0
run_case "webhook contamination (doppler tag embeds both markers) does NOT false-alarm -> PASS" 0

# 8. TRANSIENT — the query script itself missing/non-executable.
rc=0
out="$(CI_DEPLOY_SENTRY_BQ="$WORK/does-not-exist.sh" "$SUT" 2>&1)" || rc=$?
if [[ "$rc" -eq 2 ]]; then pass "missing/non-executable BQ -> TRANSIENT (exit=$rc)"
else fail "missing BQ — expected exit=2 got exit=$rc :: ${out:0:200}"; fi

# 9. FAIL-precedence (load-bearing) — a REAL POST-failure must fire exit 1 even when the
#    (separate) liveness query would fault. The mock faults on the liveness term
#    (SYSLOG_IDENTIFIER":"ci-deploy) but returns the fixture for "Sentry POST failed".
#    Because the SUT evaluates FAIL BEFORE fetching liveness, a real recurrence is never
#    masked into a TRANSIENT retry. A reorder (liveness fetch first) would exit 2 here.
make_mock "$WORK/fx-fail.json" 0 'SYSLOG_IDENTIFIER":"ci-deploy'
run_case "real FAIL not masked by a liveness-query fault -> FAIL (exit 1, not TRANSIENT)" 1

if [[ "$fails" -gt 0 ]]; then
  echo "FAILED: $fails case(s)" >&2
  exit 1
fi
echo "OK: all ci-deploy-sentry-post-fail-6475 arms passed"
