#!/usr/bin/env bash
# Tests for sentry-monitors-audit.sh — Sentry Monitors/Alerts migration audit.
#
# Run via:  bash apps/web-platform/scripts/sentry-monitors-audit.test.sh
#
# Test environment isolation: each test runs the script in a tmpdir with
# SENTRY_FIXTURE_* env vars overriding the live API. Live API is NEVER called
# from this test.

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/sentry-monitors-audit.sh"

# Inherited by every `bash "$SCRIPT"` invocation below. The script's
# residency mismatch detector (added in #3863, refs #3861) compares the
# DSN cluster substring against the probed API host region; tests use
# SENTRY_API_HOST=de.sentry.io so the DSN must match that cluster or the
# detector trips exit 2 before any fixture is read. T1's env -i strips
# this (correctly — that test exercises the missing-token branch).
export NEXT_PUBLIC_SENTRY_DSN='https://test@o123.ingest.de.sentry.io/456'

if [[ ! -x "$SCRIPT" ]]; then
  echo "ERROR: $SCRIPT not found or not executable" >&2
  exit 1
fi

PASS=0
FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }

# ------------------------------------------------------------------------
# T1 — missing SENTRY_AUTH_TOKEN exits non-zero with clear message.
# ------------------------------------------------------------------------
echo "T1: missing SENTRY_AUTH_TOKEN"
set +e
out=$(env -i PATH="$PATH" HOME="$HOME" bash "$SCRIPT" 2>&1)
rc=$?
set -e
if [[ "$rc" != "0" ]] && printf '%s' "$out" | grep -qi 'SENTRY_AUTH_TOKEN'; then
  pass "non-zero exit with token-name in stderr"
else
  fail "rc=$rc out=$out"
fi

# ------------------------------------------------------------------------
# T2 — region probe override: SENTRY_API_HOST short-circuits the probe.
# When SENTRY_API_HOST=de.sentry.io and fixtures are supplied, the script
# completes without any live network call and emits a report mentioning
# the EU host.
# ------------------------------------------------------------------------
echo "T2: region probe override (EU)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
printf '[]' > "$TMP/monitors.json"
printf '[]' > "$TMP/rules.json"
set +e
out=$(SENTRY_AUTH_TOKEN=fake \
      SENTRY_ORG=jikigai \
      SENTRY_PROJECT=web-platform \
      SENTRY_API_HOST=de.sentry.io \
      SENTRY_FIXTURE_MONITORS="$TMP/monitors.json" \
      SENTRY_FIXTURE_RULES="$TMP/rules.json" \
      AUDIT_OUT_DIR="$TMP" \
      bash "$SCRIPT" 2>&1)
rc=$?
set -e
report=$(ls "$TMP"/sentry-migration-audit-*.md 2>/dev/null | head -1)
if [[ "$rc" == "0" ]] && [[ -f "$report" ]] && grep -q 'de.sentry.io' "$report"; then
  pass "EU host respected, report written"
else
  fail "rc=$rc report=$report"
fi

# ------------------------------------------------------------------------
# T3 — Class A: cron detector with no routing workflow. REFIXTURED in #7590
# onto the binding that actually exists (monitor <- name - detector
# -workflowIds-> workflow). The old fixture bound `monitor.slug` inside rule
# filters, a shape that matches 0 rows in the live org and always did.
#
# Class A is reported as a COUNT, not a per-slug list, so identity is pinned
# by the count being 1-of-2 rather than by grepping a slug: a predicate that
# ignored `workflowIds` would report 2, and one that inverted it would also
# report 1 — which is why T15 fixtures the OTHER direction (both routed -> 0).
# ------------------------------------------------------------------------
echo "T3: Class A — cron detector with no routing workflow"
TMP3=$(mktemp -d)
cat > "$TMP3/monitors.json" <<'EOF'
[
  {"slug": "monitor-a", "name": "Monitor A", "type": "cron_job", "config": {"schedule": "0 * * * *"}},
  {"slug": "monitor-b", "name": "Monitor B", "type": "cron_job", "config": {"schedule": "0 0 * * *"}}
]
EOF
printf '[]' > "$TMP3/workflows.json"
cat > "$TMP3/detectors.json" <<'EOF'
[
  {"id": "3001", "name": "monitor-a", "type": "monitor_check_in_failure", "workflowIds": ["9001"]},
  {"id": "3002", "name": "monitor-b", "type": "monitor_check_in_failure", "workflowIds": []}
]
EOF
set +e
SENTRY_AUTH_TOKEN=fake \
  SENTRY_ORG=jikigai \
  SENTRY_PROJECT=web-platform \
  SENTRY_API_HOST=de.sentry.io \
  SENTRY_FIXTURE_MONITORS="$TMP3/monitors.json" \
  SENTRY_FIXTURE_RULES="$TMP3/workflows.json" \
  SENTRY_FIXTURE_DETECTORS="$TMP3/detectors.json" \
  AUDIT_OUT_DIR="$TMP3" \
  bash "$SCRIPT" >/dev/null 2>&1
rc=$?
set -e
report=$(ls "$TMP3"/sentry-migration-audit-*.md 2>/dev/null | head -1)
if [[ "$rc" == "0" ]] && [[ -f "$report" ]] \
   && grep -qE '\*\*1\*\* of \*\*2\*\* cron detectors' "$report" \
   && ! grep -qE 'Invariant .* HOLDS' "$report"; then
  pass "Class A counted 1 of 2 (routed detector excluded); invariant correctly does not hold"
else
  fail "rc=$rc"
  sed -n '/^## Orphans/,$p' "$report" 2>/dev/null | head -20 >&2 || true
fi
rm -rf "$TMP3"

# ------------------------------------------------------------------------
# T4 — idempotency: same-day re-run overwrites prior report at the same
# path without corrupting it (no append, no double-render).
# ------------------------------------------------------------------------
echo "T4: same-day re-run overwrites cleanly"
TMP4=$(mktemp -d)
printf '[]' > "$TMP4/monitors.json"
printf '[]' > "$TMP4/rules.json"
# Pin AUDIT_DATE_OVERRIDE so the three invocations cannot straddle midnight
# UTC and produce two dated reports under heavy CI scheduling.
for i in 1 2 3; do
  SENTRY_AUTH_TOKEN=fake \
    SENTRY_ORG=jikigai \
    SENTRY_PROJECT=web-platform \
    SENTRY_API_HOST=de.sentry.io \
    SENTRY_FIXTURE_MONITORS="$TMP4/monitors.json" \
    SENTRY_FIXTURE_RULES="$TMP4/rules.json" \
    AUDIT_OUT_DIR="$TMP4" \
    AUDIT_DATE_OVERRIDE="2026-05-15" \
    bash "$SCRIPT" >/dev/null 2>&1
done
n_reports=$(ls "$TMP4"/sentry-migration-audit-*.md 2>/dev/null | wc -l)
report=$(ls "$TMP4"/sentry-migration-audit-*.md 2>/dev/null | head -1)
n_headers=$(grep -c '^# Sentry Monitors/Alerts Migration Audit' "$report" 2>/dev/null || echo 99)
if [[ "$n_reports" == "1" ]] && [[ "$n_headers" == "1" ]]; then
  pass "exactly one report, exactly one header (no double-render)"
else
  fail "n_reports=$n_reports n_headers=$n_headers"
fi
rm -rf "$TMP4"

# ------------------------------------------------------------------------
# T5 — match-by-id: two monitors with the same name resolve as distinct
# entries (id is the discriminator, not name).
# ------------------------------------------------------------------------
echo "T5: duplicate-name monitors resolve by id"
TMP5=$(mktemp -d)
cat > "$TMP5/monitors.json" <<'EOF'
[
  {"slug": "dup-1", "name": "Same Name", "type": "cron_job", "config": {"schedule": "0 * * * *"}},
  {"slug": "dup-2", "name": "Same Name", "type": "cron_job", "config": {"schedule": "0 0 * * *"}}
]
EOF
printf '[]' > "$TMP5/rules.json"
SENTRY_AUTH_TOKEN=fake \
  SENTRY_ORG=jikigai \
  SENTRY_PROJECT=web-platform \
  SENTRY_API_HOST=de.sentry.io \
  SENTRY_FIXTURE_MONITORS="$TMP5/monitors.json" \
  SENTRY_FIXTURE_RULES="$TMP5/rules.json" \
  AUDIT_OUT_DIR="$TMP5" \
  bash "$SCRIPT" >/dev/null 2>&1
report=$(ls "$TMP5"/sentry-migration-audit-*.md 2>/dev/null | head -1)
n_dup1=$(grep -cE '^\| dup-1 ' "$report" 2>/dev/null || echo 0)
n_dup2=$(grep -cE '^\| dup-2 ' "$report" 2>/dev/null || echo 0)
if [[ "$n_dup1" == "1" ]] && [[ "$n_dup2" == "1" ]]; then
  pass "both slugs present as distinct rows"
else
  fail "n_dup1=$n_dup1 n_dup2=$n_dup2"
fi
rm -rf "$TMP5"

# ------------------------------------------------------------------------
# T6 / T7 (id manifest + README extraction handshake) were DELETED in #7590.
# The `<!-- ids: ... -->` manifest fed a first-time `terraform import` that is
# complete; the marker has no live consumer. Repointing it at workflows/ would
# have silently changed its identifier space while keeping its name, so it was
# retired rather than migrated. See Decision 4 in the plan.
# ------------------------------------------------------------------------

# ------------------------------------------------------------------------
# T8 — Class B: a cron detector naming a monitor that does not exist live.
# REFIXTURED in #7590: the binding is the detector's `.name` (detectors carry
# no `slug` field), not a `monitor.slug` filter key on a rule.
# ------------------------------------------------------------------------
echo "T8: Class B — cron detector names a missing monitor"
TMP8=$(mktemp -d)
cat > "$TMP8/monitors.json" <<'EOF'
[
  {"slug": "live-monitor", "name": "Live", "type": "cron_job", "config": {"schedule": "0 * * * *"}}
]
EOF
printf '[]' > "$TMP8/workflows.json"
cat > "$TMP8/detectors.json" <<'EOF'
[
  {"id": "8100", "name": "live-monitor",  "type": "monitor_check_in_failure", "workflowIds": ["1"]},
  {"id": "8101", "name": "ghost-monitor", "type": "monitor_check_in_failure", "workflowIds": ["1"]}
]
EOF
SENTRY_AUTH_TOKEN=fake \
  SENTRY_ORG=jikigai \
  SENTRY_PROJECT=web-platform \
  SENTRY_API_HOST=de.sentry.io \
  SENTRY_FIXTURE_MONITORS="$TMP8/monitors.json" \
  SENTRY_FIXTURE_RULES="$TMP8/workflows.json" \
  SENTRY_FIXTURE_DETECTORS="$TMP8/detectors.json" \
  AUDIT_OUT_DIR="$TMP8" \
  bash "$SCRIPT" >/dev/null 2>&1
report=$(ls "$TMP8"/sentry-migration-audit-*.md 2>/dev/null | head -1)
if grep -qE 'Class B' "$report" && grep -qE '`ghost-monitor`' "$report" \
   && ! grep -qE '^- `live-monitor` — a cron detector' "$report"; then
  pass "Class B orphan 'ghost-monitor' detected; 'live-monitor' not flagged"
else
  fail "Class B section missing or ghost-monitor not flagged"
  sed -n '/^## Orphans/,$p' "$report" 2>/dev/null | head -20 >&2 || true
fi
rm -rf "$TMP8"

# ------------------------------------------------------------------------
# T9 — Class C: a workflow with no actions anywhere. REFIXTURED in #7590 onto
# the workflows shape, where `.triggers` is an OBJECT (verified live) and
# routing may ALSO live under `.actionFilters[].actions[]`.
# ------------------------------------------------------------------------
echo "T9: Class C — workflow with no actions"
TMP9=$(mktemp -d)
printf '[]' > "$TMP9/monitors.json"
cat > "$TMP9/workflows.json" <<'EOF'
[
  {"id": "7777", "name": "auth-exchange-code-burst", "triggers": {"actions": []}, "actionFilters": []},
  {"id": "7778", "name": "auth-signout-burst",       "triggers": {"actions": [{"id":"NotifyEmailAction"}]}, "actionFilters": []}
]
EOF
SENTRY_AUTH_TOKEN=fake \
  SENTRY_ORG=jikigai \
  SENTRY_PROJECT=web-platform \
  SENTRY_API_HOST=de.sentry.io \
  SENTRY_FIXTURE_MONITORS="$TMP9/monitors.json" \
  SENTRY_FIXTURE_RULES="$TMP9/workflows.json" \
  AUDIT_OUT_DIR="$TMP9" \
  bash "$SCRIPT" >/dev/null 2>&1
report=$(ls "$TMP9"/sentry-migration-audit-*.md 2>/dev/null | head -1)
if grep -qE 'Class C' "$report" && grep -qE 'workflow id `7777`' "$report" && ! grep -qE 'workflow id `7778`' "$report"; then
  pass "Class C flagged 7777 (no actions), not 7778 (has action)"
else
  fail "Class C detection mis-fired"
  sed -n '/^## Orphans/,$p' "$report" 2>/dev/null | head -20 >&2 || true
fi
rm -rf "$TMP9"

# ------------------------------------------------------------------------
# T10 (non-numeric id filtering) was DELETED in #7590 with the manifest it
# guarded. The defense it provided — never word-splitting a vendor-supplied id
# into a shell consumer — is preserved by there being no such consumer at all.
# ------------------------------------------------------------------------

# ------------------------------------------------------------------------
# T11 — Class B narrow extraction: only `monitor_check_in_failure` detectors
# bind a monitor slug. The live org also carries `error`, `issue_stream` and
# `uptime_domain_failure` detectors whose names are ordinary prose; treating
# those as monitor bindings would flood the report with false orphans — the
# same false-positive class the pre-#7590 narrow extraction existed to stop,
# rebased onto the new schema.
# ------------------------------------------------------------------------
echo "T11: Class B narrow extraction — non-cron detectors do not false-flag"
TMP11=$(mktemp -d)
cat > "$TMP11/monitors.json" <<'EOF'
[
  {"slug": "scheduled-daily-triage", "name": "Daily triage", "type": "cron_job", "config": {"schedule": "0 4 * * *"}}
]
EOF
printf '[]' > "$TMP11/workflows.json"
cat > "$TMP11/detectors.json" <<'EOF'
[
  {"id": "9200", "name": "scheduled-daily-triage", "type": "monitor_check_in_failure", "workflowIds": ["1"]},
  {"id": "9201", "name": "auth", "type": "error", "workflowIds": []},
  {"id": "9202", "name": "soleur-ai", "type": "uptime_domain_failure", "workflowIds": []}
]
EOF
SENTRY_AUTH_TOKEN=fake \
  SENTRY_ORG=jikigai \
  SENTRY_PROJECT=web-platform \
  SENTRY_API_HOST=de.sentry.io \
  SENTRY_FIXTURE_MONITORS="$TMP11/monitors.json" \
  SENTRY_FIXTURE_RULES="$TMP11/workflows.json" \
  SENTRY_FIXTURE_DETECTORS="$TMP11/detectors.json" \
  AUDIT_OUT_DIR="$TMP11" \
  bash "$SCRIPT" >/dev/null 2>&1
report=$(ls "$TMP11"/sentry-migration-audit-*.md 2>/dev/null | head -1)
# `auth` and `soleur-ai` are non-cron detector names, NOT monitor bindings.
if [[ -f "$report" ]] \
   && ! grep -qE 'Class B' "$report" \
   && ! grep -qE '`auth`' "$report" \
   && ! grep -qE '`soleur-ai`' "$report" \
   && grep -qE '\*\*0\*\* of \*\*1\*\* cron detectors' "$report"; then
  pass "non-cron detector names did not flag as Class B; cron count scoped to 1"
else
  fail "non-cron detector name false-flagged as Class B"
  sed -n '/^## Orphans/,$p' "$report" 2>/dev/null | head -20 >&2 || true
fi
rm -rf "$TMP11"

# ------------------------------------------------------------------------
# T12 — Class C disjunction: a workflow routes if it has actions under
# `.triggers.actions[]` OR `.actionFilters[].actions[]`. Each arm is fixtured
# ALONE, because a fixture satisfying both proves only that the set is
# non-empty: dropping either arm would stay green, and the arm that reads
# `actionFilters` is exactly the one a triggers-only check would false-flag.
# ------------------------------------------------------------------------
echo "T12: Class C disjunction — each routing arm fixtured alone"
TMP12=$(mktemp -d)
printf '[]' > "$TMP12/monitors.json"
cat > "$TMP12/workflows.json" <<'EOF'
[
  {
    "id": "8001",
    "name": "routes-via-triggers-only",
    "triggers": {"actions": [{"id":"sentry.integrations.slack","targetIdentifier":"#alerts"}]},
    "actionFilters": []
  },
  {
    "id": "8002",
    "name": "routes-nowhere",
    "triggers": {"actions": []},
    "actionFilters": []
  },
  {
    "id": "8003",
    "name": "routes-via-actionfilters-only",
    "triggers": {"actions": []},
    "actionFilters": [{"actions": [{"id":"NotifyEmailAction"}]}]
  }
]
EOF
SENTRY_AUTH_TOKEN=fake \
  SENTRY_ORG=jikigai \
  SENTRY_PROJECT=web-platform \
  SENTRY_API_HOST=de.sentry.io \
  SENTRY_FIXTURE_MONITORS="$TMP12/monitors.json" \
  SENTRY_FIXTURE_RULES="$TMP12/workflows.json" \
  AUDIT_OUT_DIR="$TMP12" \
  bash "$SCRIPT" >/dev/null 2>&1
report=$(ls "$TMP12"/sentry-migration-audit-*.md 2>/dev/null | head -1)
if grep -qE 'workflow id `8002`' "$report" \
   && ! grep -qE 'workflow id `8001`' "$report" \
   && ! grep -qE 'workflow id `8003`' "$report"; then
  pass "8002 (no routing) flagged; 8001 (triggers arm) and 8003 (actionFilters arm) not"
else
  fail "Class C disjunction mis-fired"
  sed -n '/^## Orphans/,$p' "$report" 2>/dev/null | head -20 >&2 || true
fi
rm -rf "$TMP12"

# ------------------------------------------------------------------------
# T13 — Residency mismatch detector (refs #3861): when the probed API host
# region disagrees with the DSN cluster substring, the script MUST refuse
# to emit an audit artifact (exit 2, stderr error). Guards the §5(2)
# accountability surface against the A1↔A2 half-state hole.
# ------------------------------------------------------------------------
echo "T13: residency mismatch detector — DE DSN + US host refuses to emit"
TMP13=$(mktemp -d)
printf '[]' > "$TMP13/monitors.json"
printf '[]' > "$TMP13/rules.json"
set +e
out=$(SENTRY_AUTH_TOKEN=fake \
      SENTRY_ORG=jikigai \
      SENTRY_API_HOST=sentry.io \
      NEXT_PUBLIC_SENTRY_DSN='https://abc@o123.ingest.de.sentry.io/456' \
      SENTRY_FIXTURE_MONITORS="$TMP13/monitors.json" \
      SENTRY_FIXTURE_RULES="$TMP13/rules.json" \
      AUDIT_OUT_DIR="$TMP13" \
      bash "$SCRIPT" 2>&1)
rc=$?
set -e
n_reports=$(ls "$TMP13"/sentry-migration-audit-*.md 2>/dev/null | wc -l)
if [[ "$rc" == "2" ]] \
   && printf '%s' "$out" | grep -qE 'residency mismatch — probed=sentry\.io DSN cluster=de' \
   && [[ "$n_reports" == "0" ]]; then
  pass "exit 2, stderr names both sides, no artifact written"
else
  fail "rc=$rc n_reports=$n_reports out=$out"
fi
rm -rf "$TMP13"

# ------------------------------------------------------------------------
# T14 — Frontmatter emits both residency signals: the renamed
# `**Probed host:**` (the actual API call destination) and the new
# `**DSN cluster:**` (the authoritative ingest cluster substring). Two
# signals are load-bearing: if one is bypassed (operator override, env
# misconfig), the other gives an auditor a second read.
# ------------------------------------------------------------------------
echo "T14: frontmatter emits Probed host + DSN cluster"
TMP14=$(mktemp -d)
printf '[]' > "$TMP14/monitors.json"
printf '[]' > "$TMP14/rules.json"
SENTRY_AUTH_TOKEN=fake \
  SENTRY_ORG=jikigai \
  SENTRY_API_HOST=de.sentry.io \
  SENTRY_FIXTURE_MONITORS="$TMP14/monitors.json" \
  SENTRY_FIXTURE_RULES="$TMP14/rules.json" \
  AUDIT_OUT_DIR="$TMP14" \
  bash "$SCRIPT" >/dev/null 2>&1
report=$(ls "$TMP14"/sentry-migration-audit-*.md 2>/dev/null | head -1)
if [[ -f "$report" ]] \
   && grep -qE '^- \*\*Probed host:\*\* de\.sentry\.io$' "$report" \
   && grep -qE '^- \*\*DSN cluster:\*\* de$' "$report" \
   && ! grep -qE '^- \*\*API host:\*\*' "$report"; then
  pass "Probed host + DSN cluster present; legacy API host line removed"
else
  fail "frontmatter shape regression"
  head -8 "$report" >&2 2>/dev/null || true
fi
rm -rf "$TMP14"

# ========================================================================
# Transport-seam tests (#7590).
#
# The SENTRY_FIXTURE_* seams `cat` a file and return BEFORE curl runs, so they
# cannot express an HTTP status, a response header or a retry sequence — the
# three things every defect in #7590 lives in. These tests stub `curl` on PATH
# instead, matching the established repo dialect
# (apps/cla-evidence/scripts/upload-evidence.test.sh).
#
# The stub emulates the two call-site shapes the SUT actually uses:
#   * body-returning  — Gate 1 and every fetch read stdout as the BODY
#   * status-returning — Gates 2/3 pass `-o /dev/null -w '%{http_code}'` and
#                        read stdout as the STATUS
# A wrapper that injected its own `-w` would corrupt the first shape; one that
# injected `-o` would blank it. That is the P0 this seam exists to catch.
# ========================================================================

# Writes $1/curl. Each test supplies $1/respond.sh, which receives URL, METHOD
# and N (1-based invocation count) in the environment and prints one line:
#   <status><TAB><extra-headers-file|-><TAB><body-file|->
mk_curl_stub() {
  local dir="$1"
  mkdir -p "$dir"
  : > "$dir/requests.txt"
  printf '0' > "$dir/count"
  cat > "$dir/curl" <<STUB
#!/usr/bin/env bash
STUB_DIR="$dir"
STUB
  cat >> "$dir/curl" <<'STUB'
hdr=""; url=""; out=""; prev=""; method="GET"; wants_w=0
for a in "$@"; do
  [[ "$prev" == "-D" ]] && hdr="$a"
  [[ "$prev" == "-X" ]] && method="$a"
  [[ "$prev" == "-o" ]] && out="$a"
  [[ "$a" == "-w" ]] && wants_w=1
  case "$a" in http://*|https://*) url="$a" ;; esac
  prev="$a"
done
n=$(cat "$STUB_DIR/count" 2>/dev/null || echo 0); n=$((n+1)); printf '%s' "$n" > "$STUB_DIR/count"
printf '%s %s\n' "$method" "$url" >> "$STUB_DIR/requests.txt"
spec=$(URL="$url" METHOD="$method" N="$n" bash "$STUB_DIR/respond.sh")
status=$(printf '%s' "$spec" | cut -f1)
hfile=$(printf '%s' "$spec" | cut -f2)
bfile=$(printf '%s' "$spec" | cut -f3)
if [[ -n "$hdr" ]]; then
  printf 'HTTP/2 %s\r\n' "$status" > "$hdr"
  [[ "$hfile" != "-" && -f "$hfile" ]] && cat "$hfile" >> "$hdr"
  printf '\r\n' >> "$hdr"
fi
body=""
[[ "$bfile" != "-" && -f "$bfile" ]] && body=$(cat "$bfile")
[[ -n "$out" ]] && printf '%s' "$body" > "$out"
if (( wants_w == 1 )); then
  printf '%s' "$status"
elif [[ -z "$out" ]]; then
  printf '%s' "$body"
fi
exit 0
STUB
  chmod +x "$dir/curl"
}

# Happy-path responder: gates pass, all collections empty. Tests override the
# single URL they care about.
mk_default_respond() {
  local dir="$1"
  printf '{"id":"123"}' > "$dir/org.json"
  printf '[]' > "$dir/empty.json"
  cat > "$dir/respond.sh" <<STUB
#!/usr/bin/env bash
d="$dir"
STUB
  cat >> "$dir/respond.sh" <<'STUB'
case "$URL" in
  */monitors/*|*/monitors/)   printf '200\t-\t%s\n' "$d/empty.json" ;;
  */workflows/*|*/workflows/) printf '200\t-\t%s\n' "$d/empty.json" ;;
  */detectors/*|*/detectors/) printf '200\t-\t%s\n' "$d/empty.json" ;;
  */releases/*|*/releases/)   printf '201\t-\t-\n' ;;
  */projects/*/)              printf '200\t-\t-\n' ;;
  */organizations/*/)         printf '200\t-\t%s\n' "$d/org.json" ;;
  *)                          printf '200\t-\t%s\n' "$d/empty.json" ;;
esac
STUB
  chmod +x "$dir/respond.sh"
}

run_sut_stubbed() {  # $1 = stub dir; remaining args = extra env assignments
  local dir="$1"; shift
  env PATH="$dir:$PATH" \
    SENTRY_AUTH_TOKEN=fake \
    SENTRY_ORG=jikigai \
    SENTRY_PROJECT=web-platform \
    SENTRY_API_HOST=de.sentry.io \
    NEXT_PUBLIC_SENTRY_DSN='https://test@o123.ingest.de.sentry.io/456' \
    SENTRY_TF_DIR="$dir/tf" \
    AUDIT_OUT_DIR="$dir" \
    "$@" \
    bash "$SCRIPT" 2>&1
}

# ------------------------------------------------------------------------
# T15 — Class A, FAR direction. T3 fixtures one-of-two unrouted; this
# fixtures the direction where a too-aggressive predicate gives a false
# positive. A check that ignored `workflowIds` entirely would report 2 here
# and 2 in T3, passing neither — but a check inverted to "has workflowIds"
# would report 1 in T3 and pass it. Both directions are required.
# ------------------------------------------------------------------------
echo "T15: Class A far direction — all detectors routed yields zero"
TMP15=$(mktemp -d)
cat > "$TMP15/monitors.json" <<'EOF'
[
  {"slug": "monitor-a", "name": "A", "type": "cron_job", "config": {"schedule": "0 * * * *"}},
  {"slug": "monitor-b", "name": "B", "type": "cron_job", "config": {"schedule": "0 0 * * *"}}
]
EOF
printf '[]' > "$TMP15/workflows.json"
cat > "$TMP15/detectors.json" <<'EOF'
[
  {"id": "1", "name": "monitor-a", "type": "monitor_check_in_failure", "workflowIds": ["w1"]},
  {"id": "2", "name": "monitor-b", "type": "monitor_check_in_failure", "workflowIds": ["w2"]}
]
EOF
SENTRY_AUTH_TOKEN=fake SENTRY_ORG=jikigai SENTRY_PROJECT=web-platform \
  SENTRY_API_HOST=de.sentry.io \
  SENTRY_FIXTURE_MONITORS="$TMP15/monitors.json" \
  SENTRY_FIXTURE_RULES="$TMP15/workflows.json" \
  SENTRY_FIXTURE_DETECTORS="$TMP15/detectors.json" \
  AUDIT_OUT_DIR="$TMP15" bash "$SCRIPT" >/dev/null 2>&1
report=$(ls "$TMP15"/sentry-migration-audit-*.md 2>/dev/null | head -1)
if grep -qE '\*\*0\*\* of \*\*2\*\* cron detectors' "$report"; then
  pass "all-routed fixture yields Class A count 0 of 2"
else
  fail "Class A far direction"
  sed -n '/^## Orphans/,$p' "$report" 2>/dev/null | head -12 >&2 || true
fi
rm -rf "$TMP15"

# ------------------------------------------------------------------------
# T16 — a 410 with deprecation headers must NAME ITS OWN CAUSE. The
# assertion anchors on the replacement-endpoint substring, a content anchor:
# a bare `grep -q ERROR` would also be satisfied by the pre-#7590 message and
# would discriminate nothing.
# ------------------------------------------------------------------------
echo "T16: 410 + deprecation headers self-names"
TMP16=$(mktemp -d); mk_curl_stub "$TMP16"; mk_default_respond "$TMP16"
mkdir -p "$TMP16/tf"; printf 'resource "sentry_cron_monitor" "x" {\n  name = "none"\n}\n' > "$TMP16/tf/m.tf"
printf 'x-sentry-deprecation-date: 2026-05-14T00:00:00+00:00\r\nx-sentry-replacement-endpoint: /api/0/organizations/jikigai/workflows/\r\n' > "$TMP16/dep.hdr"
printf '{"message":"This API no longer exists."}' > "$TMP16/gone.json"
cat > "$TMP16/respond.sh" <<STUB
#!/usr/bin/env bash
d="$TMP16"
STUB
cat >> "$TMP16/respond.sh" <<'STUB'
case "$URL" in
  */workflows/*|*/workflows/) printf '410\t%s\t%s\n' "$d/dep.hdr" "$d/gone.json" ;;
  */monitors/*|*/monitors/)   printf '200\t-\t%s\n' "$d/empty.json" ;;
  */detectors/*|*/detectors/) printf '200\t-\t%s\n' "$d/empty.json" ;;
  */releases/*|*/releases/)   printf '201\t-\t-\n' ;;
  */projects/*/)              printf '200\t-\t-\n' ;;
  */organizations/*/)         printf '200\t-\t%s\n' "$d/org.json" ;;
  *)                          printf '200\t-\t%s\n' "$d/empty.json" ;;
esac
STUB
chmod +x "$TMP16/respond.sh"
set +e
out=$(run_sut_stubbed "$TMP16"); rc=$?
set -e
# The replacement-endpoint assertion is anchored on its LABEL, not on the bare
# path: the same path also appears on the `url:` line, so `grep -q
# '/organizations/jikigai/workflows/'` was satisfied whether or not the
# replacement header was ever emitted. Deleting the replacement line from the
# diagnostic left this test GREEN until the mutation battery caught it
# (cq-assert-anchor-not-bare-token).
if [[ "$rc" != "0" ]] \
   && grep -q 'http_status:  410' <<<"$out" \
   && grep -q 'api_host:     de.sentry.io' <<<"$out" \
   && grep -q 'url:          https://de.sentry.io/api/0/organizations/jikigai/workflows/' <<<"$out" \
   && grep -q 'x-sentry-replacement-endpoint: /api/0/organizations/jikigai/workflows/' <<<"$out" \
   && grep -q 'x-sentry-deprecation-date:    2026-05-14' <<<"$out" \
   && grep -qi 'MIGRATE' <<<"$out"; then
  pass "410 diagnostic carries status, host, URL, deprecation date, replacement and a verdict"
else
  fail "410 diagnostic incomplete (rc=$rc)"
  printf '%s\n' "$out" | tail -20 >&2
fi
rm -rf "$TMP16"

# ------------------------------------------------------------------------
# T17 — deprecation headers on a 200. The non-canonical input the contract
# explicitly permits: this is the state the deprecated endpoints were in for
# three months while nothing read the header. Must warn and still exit 0.
# ------------------------------------------------------------------------
echo "T17: deprecation headers on a 200 warn without failing"
TMP17=$(mktemp -d); mk_curl_stub "$TMP17"; mk_default_respond "$TMP17"
mkdir -p "$TMP17/tf"; printf 'resource "sentry_cron_monitor" "x" {\n  name = "none"\n}\n' > "$TMP17/tf/m.tf"
# Date far in the future: warn only, no escalation.
printf 'X-Sentry-Deprecation-Date: 2099-01-01T00:00:00+00:00\r\nX-Sentry-Replacement-Endpoint: /api/0/organizations/jikigai/successor/\r\n' > "$TMP17/dep.hdr"
cat > "$TMP17/respond.sh" <<STUB
#!/usr/bin/env bash
d="$TMP17"
STUB
cat >> "$TMP17/respond.sh" <<'STUB'
case "$URL" in
  */workflows/*|*/workflows/) printf '200\t%s\t%s\n' "$d/dep.hdr" "$d/empty.json" ;;
  */monitors/*|*/monitors/)   printf '200\t-\t%s\n' "$d/empty.json" ;;
  */detectors/*|*/detectors/) printf '200\t-\t%s\n' "$d/empty.json" ;;
  */releases/*|*/releases/)   printf '201\t-\t-\n' ;;
  */projects/*/)              printf '200\t-\t-\n' ;;
  */organizations/*/)         printf '200\t-\t%s\n' "$d/org.json" ;;
  *)                          printf '200\t-\t%s\n' "$d/empty.json" ;;
esac
STUB
chmod +x "$TMP17/respond.sh"
set +e
out=$(run_sut_stubbed "$TMP17"); rc=$?
set -e
# Mixed-case header names are deliberate: `-D` preserves wire casing, so a
# case-SENSITIVE match would silently never fire.
if [[ "$rc" == "0" ]] \
   && grep -q 'DEPRECATED' <<<"$out" \
   && grep -q 'workflows/' <<<"$out" \
   && grep -q '2099-01-01' <<<"$out"; then
  pass "200 + deprecation headers warns (case-insensitively) and exits 0"
else
  fail "tripwire did not warn on a 200 (rc=$rc)"
  printf '%s\n' "$out" | tail -15 >&2
fi
rm -rf "$TMP17"

# ------------------------------------------------------------------------
# T17b — escalation. The SAME input inside the window must exit non-zero.
# A perpetual warning is what failed in 2026-07: versions.tf records this very
# family answering 410 and being written off as transient.
# ------------------------------------------------------------------------
echo "T17b: deprecation inside the escalation window fails"
TMP17B=$(mktemp -d); mk_curl_stub "$TMP17B"; mk_default_respond "$TMP17B"
mkdir -p "$TMP17B/tf"; printf 'resource "sentry_cron_monitor" "x" {\n  name = "none"\n}\n' > "$TMP17B/tf/m.tf"
printf 'x-sentry-deprecation-date: 2026-05-14T00:00:00+00:00\r\n' > "$TMP17B/dep.hdr"
cat > "$TMP17B/respond.sh" <<STUB
#!/usr/bin/env bash
d="$TMP17B"
STUB
cat >> "$TMP17B/respond.sh" <<'STUB'
case "$URL" in
  */workflows/*|*/workflows/) printf '200\t%s\t%s\n' "$d/dep.hdr" "$d/empty.json" ;;
  */monitors/*|*/monitors/)   printf '200\t-\t%s\n' "$d/empty.json" ;;
  */detectors/*|*/detectors/) printf '200\t-\t%s\n' "$d/empty.json" ;;
  */releases/*|*/releases/)   printf '201\t-\t-\n' ;;
  */projects/*/)              printf '200\t-\t-\n' ;;
  */organizations/*/)         printf '200\t-\t%s\n' "$d/org.json" ;;
  *)                          printf '200\t-\t%s\n' "$d/empty.json" ;;
esac
STUB
chmod +x "$TMP17B/respond.sh"
set +e
out=$(run_sut_stubbed "$TMP17B"); rc=$?
set -e
if [[ "$rc" != "0" ]] && grep -qi 'deprecated and its date is within' <<<"$out"; then
  pass "past-dated deprecation escalates to a non-zero exit"
else
  fail "escalation did not fire (rc=$rc)"
  printf '%s\n' "$out" | tail -10 >&2
fi
rm -rf "$TMP17B"

# ------------------------------------------------------------------------
# T18 — retry classification AND stdout neutrality.
#
# Neutrality is asserted DIRECTLY, by extracting curl_retry and diffing its
# stdout against bare `curl "$@"` for both call-site shapes. This is the
# assertion that would have caught the `-w` P0: a wrapper `-w` after "$@" wins
# (duplicate -w is last-wins) and turns a healthy body into `[...]200`.
# ------------------------------------------------------------------------
echo "T18: retry classification + stdout byte-neutrality"
TMP18=$(mktemp -d); mk_curl_stub "$TMP18"
awk '/^CURL_BIN=/{on=1} on{print} on && /^curl_retry\(\)/{inr=1} inr && /^}/{exit}' "$SCRIPT" > "$TMP18/lib.sh"
printf '[{"id":"1"}]' > "$TMP18/body.json"

t18_fail=0
# --- (a) 500 then 200 on a safe GET: retried, final body returned ---------
cat > "$TMP18/respond.sh" <<STUB
#!/usr/bin/env bash
d="$TMP18"
STUB
cat >> "$TMP18/respond.sh" <<'STUB'
if [[ "$N" -eq 1 ]]; then printf '500\t-\t-\n'; else printf '200\t-\t%s\n' "$d/body.json"; fi
STUB
chmod +x "$TMP18/respond.sh"
printf '0' > "$TMP18/count"
got=$(cd "$TMP18" && CURL_BIN="$TMP18/curl" bash -c 'set -euo pipefail; source ./lib.sh; curl_retry -s "https://de.sentry.io/api/0/x/"' 2>/dev/null)
n_calls=$(wc -l < "$TMP18/requests.txt")
if [[ "$got" == '[{"id":"1"}]' ]] && [[ "$n_calls" == "2" ]]; then
  pass "T18a: 5xx on a safe GET is retried and the final body is returned"
else
  fail "T18a: got='$got' calls=$n_calls"; t18_fail=1
fi

# --- (b) 410 is NEVER retried --------------------------------------------
cat > "$TMP18/respond.sh" <<'STUB'
#!/usr/bin/env bash
printf '410\t-\t-\n'
STUB
chmod +x "$TMP18/respond.sh"
printf '0' > "$TMP18/count"; : > "$TMP18/requests.txt"
(cd "$TMP18" && CURL_BIN="$TMP18/curl" bash -c 'set -euo pipefail; source ./lib.sh; curl_retry -s "https://de.sentry.io/api/0/x/"' >/dev/null 2>&1)
n_calls=$(wc -l < "$TMP18/requests.txt")
if [[ "$n_calls" == "1" ]]; then
  pass "T18b: 410 is not retried (retrying would mask a sunset as a flake)"
else
  fail "T18b: 410 retried $n_calls times"; t18_fail=1
fi

# --- (c) a 5xx on a non-idempotent POST is NOT status-retried -------------
# A retried write whose first attempt landed server-side returns 208, and
# Gate 3's `!= 201` check would then report a false scope failure.
cat > "$TMP18/respond.sh" <<'STUB'
#!/usr/bin/env bash
if [[ "$N" -eq 1 ]]; then printf '500\t-\t-\n'; else printf '208\t-\t-\n'; fi
STUB
chmod +x "$TMP18/respond.sh"
printf '0' > "$TMP18/count"; : > "$TMP18/requests.txt"
(cd "$TMP18" && CURL_BIN="$TMP18/curl" bash -c 'set -euo pipefail; source ./lib.sh; curl_retry -s -X POST "https://de.sentry.io/api/0/x/releases/"' >/dev/null 2>&1)
n_calls=$(wc -l < "$TMP18/requests.txt")
if [[ "$n_calls" == "1" ]]; then
  pass "T18c: a write probe is not status-retried (208-after-retry cannot arise)"
else
  fail "T18c: POST status-retried $n_calls times"; t18_fail=1
fi

# --- (d) stdout byte-identity, BOTH call-site shapes ----------------------
cat > "$TMP18/respond.sh" <<STUB
#!/usr/bin/env bash
d="$TMP18"
STUB
cat >> "$TMP18/respond.sh" <<'STUB'
printf '200\t-\t%s\n' "$d/body.json"
STUB
chmod +x "$TMP18/respond.sh"
printf '0' > "$TMP18/count"
body_wrapped=$(cd "$TMP18" && CURL_BIN="$TMP18/curl" bash -c 'set -euo pipefail; source ./lib.sh; curl_retry -s "https://de.sentry.io/api/0/x/"' 2>/dev/null)
body_bare=$("$TMP18/curl" -s "https://de.sentry.io/api/0/x/" 2>/dev/null)
status_wrapped=$(cd "$TMP18" && CURL_BIN="$TMP18/curl" bash -c 'set -euo pipefail; source ./lib.sh; curl_retry -s -o /dev/null -w "%{http_code}" "https://de.sentry.io/api/0/x/"' 2>/dev/null)
status_bare=$("$TMP18/curl" -s -o /dev/null -w '%{http_code}' "https://de.sentry.io/api/0/x/" 2>/dev/null)
if [[ "$body_wrapped" == "$body_bare" ]] && [[ "$body_wrapped" == '[{"id":"1"}]' ]] \
   && [[ "$status_wrapped" == "$status_bare" ]] && [[ "$status_wrapped" == "200" ]]; then
  pass "T18d: curl_retry stdout is byte-identical to bare curl in BOTH shapes"
else
  fail "T18d: body '$body_wrapped' vs '$body_bare'; status '$status_wrapped' vs '$status_bare'"; t18_fail=1
fi
rm -rf "$TMP18"

# ------------------------------------------------------------------------
# T19 — the Class A invariant, asserted where something reads it.
# `class_a_count == cron_detector_count` distinguishes ordinary growth from a
# real routing attachment from an extraction failure; a literal baseline of 55
# would go stale the moment monitor 56 lands and can distinguish none of them.
# ------------------------------------------------------------------------
echo "T19: Class A invariant is machine-checked"
TMP19=$(mktemp -d)
cat > "$TMP19/monitors.json" <<'EOF'
[{"slug": "m1", "name": "M1", "type": "cron_job", "config": {"schedule": "0 * * * *"}}]
EOF
printf '[]' > "$TMP19/workflows.json"
cat > "$TMP19/detectors.json" <<'EOF'
[{"id": "1", "name": "m1", "type": "monitor_check_in_failure", "workflowIds": []}]
EOF
SENTRY_AUTH_TOKEN=fake SENTRY_ORG=jikigai SENTRY_PROJECT=web-platform \
  SENTRY_API_HOST=de.sentry.io \
  SENTRY_FIXTURE_MONITORS="$TMP19/monitors.json" \
  SENTRY_FIXTURE_RULES="$TMP19/workflows.json" \
  SENTRY_FIXTURE_DETECTORS="$TMP19/detectors.json" \
  AUDIT_OUT_DIR="$TMP19" bash "$SCRIPT" >/dev/null 2>&1
report=$(ls "$TMP19"/sentry-migration-audit-*.md 2>/dev/null | head -1)
if grep -qE '\*\*1\*\* of \*\*1\*\* cron detectors' "$report" \
   && grep -qE 'Invariant `class_a_count == cron_detector_count` HOLDS' "$report" \
   && ! grep -qE '^- `m1` — ' "$report"; then
  pass "invariant reported when it holds; no per-slug list emitted"
else
  fail "invariant not machine-checked"
  sed -n '/^## Orphans/,$p' "$report" 2>/dev/null | head -12 >&2 || true
fi
rm -rf "$TMP19"

# ------------------------------------------------------------------------
# T21 — extraction-failure guard. Zero cron detectors against a non-empty
# live monitor list is a BROKEN EXTRACTION, not a clean org. Under the old
# predicate this state produced a loud artifact (all monitors flagged); under
# the new one it would produce a clean report and exit 0 — quiet, green and
# wrong. That inversion is why this guard is load-bearing.
# ------------------------------------------------------------------------
echo "T21: zero cron detectors against live monitors is an extraction failure"
TMP21=$(mktemp -d)
cat > "$TMP21/monitors.json" <<'EOF'
[{"slug": "m1", "name": "M1", "type": "cron_job", "config": {"schedule": "0 * * * *"}}]
EOF
printf '[]' > "$TMP21/workflows.json"
printf '[]' > "$TMP21/detectors.json"
set +e
out=$(SENTRY_AUTH_TOKEN=fake SENTRY_ORG=jikigai SENTRY_PROJECT=web-platform \
  SENTRY_API_HOST=de.sentry.io \
  SENTRY_FIXTURE_MONITORS="$TMP21/monitors.json" \
  SENTRY_FIXTURE_RULES="$TMP21/workflows.json" \
  SENTRY_FIXTURE_DETECTORS="$TMP21/detectors.json" \
  AUDIT_OUT_DIR="$TMP21" bash "$SCRIPT" 2>&1)
rc=$?
set -e
report=$(ls "$TMP21"/sentry-migration-audit-*.md 2>/dev/null | head -1)
if [[ "$rc" != "0" ]] && grep -qi 'orphan extraction is broken' <<<"$out" \
   && { [[ ! -f "$report" ]] || ! grep -q 'No orphans detected' "$report"; }; then
  pass "extraction failure named; clean-state string never emitted"
else
  fail "extraction guard did not fire (rc=$rc)"
  printf '%s\n' "$out" | tail -8 >&2
fi
rm -rf "$TMP21"

# ------------------------------------------------------------------------
# T20 — pagination is FOLLOWED, not truncated.
#
# Cursor-following is mandatory rather than loud-fail because `detectors/`
# grows 1:1 with cron monitors: a truncation failure would, by ordinary
# growth, red this audit before the terraform plan step that deploys the fix.
# ------------------------------------------------------------------------
echo "T20: detectors pagination is followed"
TMP20=$(mktemp -d); mk_curl_stub "$TMP20"; mk_default_respond "$TMP20"
mkdir -p "$TMP20/tf"
printf 'resource "sentry_cron_monitor" "a" {\n  name = "m1"\n}\nresource "sentry_cron_monitor" "b" {\n  name = "m2"\n}\n' > "$TMP20/tf/m.tf"
cat > "$TMP20/monitors.json" <<'EOF'
[{"slug":"m1","name":"M1","type":"cron_job","config":{"schedule":"0 * * * *"}},
 {"slug":"m2","name":"M2","type":"cron_job","config":{"schedule":"0 0 * * *"}}]
EOF
printf '[{"id":"1","name":"m1","type":"monitor_check_in_failure","workflowIds":["w"]}]' > "$TMP20/det_p1.json"
printf '[{"id":"2","name":"m2","type":"monitor_check_in_failure","workflowIds":["w"]}]' > "$TMP20/det_p2.json"
# Absolute Link pointing at a DIFFERENT host than $api_host — which is what
# Sentry actually returns (verified live: targets are sentry.io even when the
# request went to <org>.sentry.io). A host-equality check would refuse every
# real pagination; only cursor-extract-and-rebuild is both safe and correct.
printf 'link: <https://sentry.io/api/0/organizations/jikigai/detectors/?&cursor=100:1:0>; rel="next"; results="true"; cursor="100:1:0"\r\n' > "$TMP20/next.hdr"
cat > "$TMP20/respond.sh" <<STUB
#!/usr/bin/env bash
d="$TMP20"
STUB
cat >> "$TMP20/respond.sh" <<'STUB'
case "$URL" in
  *detectors/?cursor=*) printf '200\t-\t%s\n' "$d/det_p2.json" ;;
  */detectors/)         printf '200\t%s\t%s\n' "$d/next.hdr" "$d/det_p1.json" ;;
  */monitors/*|*/monitors/) printf '200\t-\t%s\n' "$d/monitors.json" ;;
  */workflows/*|*/workflows/) printf '200\t-\t%s\n' "$d/empty.json" ;;
  */releases/*|*/releases/)   printf '201\t-\t-\n' ;;
  */projects/*/)              printf '200\t-\t-\n' ;;
  */organizations/*/)         printf '200\t-\t%s\n' "$d/org.json" ;;
  *)                          printf '200\t-\t%s\n' "$d/empty.json" ;;
esac
STUB
chmod +x "$TMP20/respond.sh"
set +e
out=$(run_sut_stubbed "$TMP20"); rc=$?
set -e
report=$(ls "$TMP20"/sentry-migration-audit-*.md 2>/dev/null | head -1)
# The cursor must be rebuilt onto $api_host, never onto the header's host.
off_host=$(grep -c 'https://sentry.io' "$TMP20/requests.txt" || true)
if [[ "$rc" == "0" ]] \
   && grep -qE '\*\*0\*\* of \*\*2\*\* cron detectors' "$report" \
   && grep -q 'cursor=100:1:0' "$TMP20/requests.txt" \
   && [[ "$off_host" == "0" ]] \
   && grep -q 'Enumeration complete:\*\* yes' "$report"; then
  pass "both detector pages audited; cursor rebuilt onto \$api_host, never the header's host"
else
  fail "pagination not followed (rc=$rc off_host=$off_host)"
  cat "$TMP20/requests.txt" >&2
  grep -E 'cron detectors|Enumeration' "$report" >&2 2>/dev/null || true
fi
rm -rf "$TMP20"

# ------------------------------------------------------------------------
# T20b — a hostile Link target is REFUSED and the refusal poisons the clean
# verdict. curl parses everything before an `@` as userinfo, so following
# `<@attacker.tld/…>` would issue a real off-box request carrying
# SENTRY_AUTH_TOKEN. Asserting on the stub's recorded hosts — not on the
# absence of an error, which a silently-followed redirect also satisfies.
# ------------------------------------------------------------------------
echo "T20b: hostile Link target refused and clean verdict suppressed"
TMP20B=$(mktemp -d); mk_curl_stub "$TMP20B"; mk_default_respond "$TMP20B"
mkdir -p "$TMP20B/tf"; printf 'resource "sentry_cron_monitor" "x" {\n  name = "none"\n}\n' > "$TMP20B/tf/m.tf"
printf 'link: <@attacker.tld/api/0/organizations/jikigai/detectors/>; rel="next"; results="true"; cursor="100:1:0"\r\n' > "$TMP20B/evil.hdr"
cat > "$TMP20B/respond.sh" <<STUB
#!/usr/bin/env bash
d="$TMP20B"
STUB
cat >> "$TMP20B/respond.sh" <<'STUB'
case "$URL" in
  */detectors/*|*/detectors/) printf '200\t%s\t%s\n' "$d/evil.hdr" "$d/empty.json" ;;
  */monitors/*|*/monitors/)   printf '200\t-\t%s\n' "$d/empty.json" ;;
  */workflows/*|*/workflows/) printf '200\t-\t%s\n' "$d/empty.json" ;;
  */releases/*|*/releases/)   printf '201\t-\t-\n' ;;
  */projects/*/)              printf '200\t-\t-\n' ;;
  */organizations/*/)         printf '200\t-\t%s\n' "$d/org.json" ;;
  *)                          printf '200\t-\t%s\n' "$d/empty.json" ;;
esac
STUB
chmod +x "$TMP20B/respond.sh"
set +e
out=$(run_sut_stubbed "$TMP20B"); rc=$?
set -e
report=$(ls "$TMP20B"/sentry-migration-audit-*.md 2>/dev/null | head -1)
bad_hosts=$(grep -cE 'attacker\.tld' "$TMP20B/requests.txt" || true)
if [[ "$bad_hosts" == "0" ]] \
   && grep -qi 'userinfo-injection' <<<"$out" \
   && grep -q 'Enumeration complete:\*\* NO' "$report" \
   && ! grep -q 'No orphans detected' "$report"; then
  pass "no request to attacker.tld; refusal counted; clean-state string suppressed"
else
  fail "hostile Link handling wrong (bad_hosts=$bad_hosts rc=$rc)"
  grep -E 'attacker|Enumeration|No orphans' "$TMP20B/requests.txt" "$report" >&2 2>/dev/null || true
fi
rm -rf "$TMP20B"

# ------------------------------------------------------------------------
# T20c — MAX_PAGES ceiling bounds an endpoint that always returns a cursor,
# and hitting it counts as truncation rather than completing quietly.
# ------------------------------------------------------------------------
echo "T20c: MAX_PAGES ceiling bounds the cursor loop"
TMP20C=$(mktemp -d); mk_curl_stub "$TMP20C"; mk_default_respond "$TMP20C"
mkdir -p "$TMP20C/tf"; printf 'resource "sentry_cron_monitor" "x" {\n  name = "none"\n}\n' > "$TMP20C/tf/m.tf"
printf 'link: <https://de.sentry.io/api/0/organizations/jikigai/detectors/?&cursor=9:9:9>; rel="next"; results="true"; cursor="9:9:9"\r\n' > "$TMP20C/loop.hdr"
cat > "$TMP20C/respond.sh" <<STUB
#!/usr/bin/env bash
d="$TMP20C"
STUB
cat >> "$TMP20C/respond.sh" <<'STUB'
case "$URL" in
  */detectors/*|*/detectors/) printf '200\t%s\t%s\n' "$d/loop.hdr" "$d/empty.json" ;;
  */monitors/*|*/monitors/)   printf '200\t-\t%s\n' "$d/empty.json" ;;
  */workflows/*|*/workflows/) printf '200\t-\t%s\n' "$d/empty.json" ;;
  */releases/*|*/releases/)   printf '201\t-\t-\n' ;;
  */projects/*/)              printf '200\t-\t-\n' ;;
  */organizations/*/)         printf '200\t-\t%s\n' "$d/org.json" ;;
  *)                          printf '200\t-\t%s\n' "$d/empty.json" ;;
esac
STUB
chmod +x "$TMP20C/respond.sh"
set +e
out=$(run_sut_stubbed "$TMP20C" SENTRY_AUDIT_MAX_PAGES=3); rc=$?
set -e
report=$(ls "$TMP20C"/sentry-migration-audit-*.md 2>/dev/null | head -1)
n_det=$(grep -c 'detectors/' "$TMP20C/requests.txt" || true)
if [[ "$n_det" == "3" ]] \
   && grep -q 'MAX_PAGES ceiling' <<<"$out" \
   && grep -q 'Enumeration complete:\*\* NO' "$report" \
   && ! grep -q 'No orphans detected' "$report"; then
  pass "loop stopped at the ceiling (3 requests); truncation counted; no clean verdict"
else
  fail "MAX_PAGES ceiling not enforced (n_det=$n_det rc=$rc)"
  printf '%s\n' "$out" | tail -8 >&2
fi
rm -rf "$TMP20C"

# ------------------------------------------------------------------------
# T22 — ASSEMBLY: no Sentry call bypasses the curl_retry chokepoint.
#
# Guard 1's property is "every response carrying a deprecation header produces
# a warning". The tripwire attaches to curl_retry, so a new call site written
# as bare `curl` is silently unmonitored — no fixture can catch that, because
# the defect is the ABSENCE of a call. This asserts the ENUMERATION, not a
# snapshot of today's list: the two known bypasses are exempted BY REASON, and
# any third one fails until someone states why it is allowed.
#
# Comment lines are stripped first: this file discusses `curl` in prose in
# several places, and a body-grep sees comments too.
# ------------------------------------------------------------------------
echo "T22: assembly — every Sentry call goes through curl_retry"
sut_code=$(grep -vE '^[[:space:]]*#' "$SCRIPT")
# A bare `curl` invocation is one not preceded by `_` (curl_retry) and not the
# seam variable. `-w` here is the word-boundary class, not curl's flag.
bare_lines=$(grep -nE '(^|[^_[:alnum:]$"])curl[[:space:]]' <<<"$sut_code" \
  | grep -vE 'curl_retry|CURL_BIN' || true)
n_bare=$(printf '%s' "$bare_lines" | grep -c . || true)
# The invocation and its URL are on different physical lines (backslash
# continuations), so identifying WHICH bypass each site is needs the following
# lines too — a line-local grep for `users/me/` finds nothing and the check
# would fail against a perfectly correct file.
bare_sites=$(grep -E -A3 '(^|[^_[:alnum:]$"])curl[[:space:]]' <<<"$sut_code" \
  | grep -vE 'curl_retry|CURL_BIN' || true)
# Exempt, with reasons:
#   1. the region-probe loop — runs BEFORE api_host is resolved, so there is
#      no validated host to attach a tripwire to, and it probes /users/me/
#      rather than a deprecated collection endpoint.
#   2. Gate 3's cleanup DELETE — best-effort teardown of the write probe; its
#      response is discarded by design (`|| true`), so it has no verdict to
#      carry and must not be able to fail the audit.
n_exempt=2
if [[ "$n_bare" == "$n_exempt" ]] \
   && grep -q 'users/me/' <<<"$bare_sites" \
   && grep -q 'X DELETE' <<<"$bare_sites"; then
  pass "exactly the 2 enumerated bypasses use bare curl; every other Sentry call is chokepointed"
else
  fail "bare-curl call sites changed: found $n_bare, expected $n_exempt"
  printf '%s\n' "$bare_lines" >&2
  echo "    If you added a Sentry call, route it through curl_retry (so the" >&2
  echo "    deprecation tripwire sees it) or add it here WITH a reason." >&2
fi

# ------------------------------------------------------------------------
# Anti-vacuity floor. A suite whose assertions all silently stopped running
# would otherwise report "0 passed, 0 failed" and exit 0. The floor is a
# COUNT of executed assertions, so it catches a harness that dies early — it
# cannot catch an assertion that runs but checks nothing, which is what the
# mutation battery in the PR body is for.
# ------------------------------------------------------------------------
MIN_ASSERTIONS=25
if (( PASS + FAIL < MIN_ASSERTIONS )); then
  echo "  FAIL: anti-vacuity floor — only $((PASS + FAIL)) assertions ran, expected >= $MIN_ASSERTIONS"
  FAIL=$((FAIL+1))
fi

# ------------------------------------------------------------------------
echo
echo "Results: $PASS passed, $FAIL failed"
exit $((FAIL > 0 ? 1 : 0))
