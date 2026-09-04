#!/usr/bin/env bash

# Tests for plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh.
# Run: bash plugins/soleur/test/notice-frontmatter.test.sh
#
# Subcommands under test:
#   field <name>      — print frontmatter scalar value (upstream, pinned-commit,
#                       last-verified, registry).
#   days-stale        — integer days since last-verified. Future date / parse
#                       fail / missing frontmatter all return 999 (treat as
#                       stale immediately). Always exits 0.
#   lifted-files      — one `<path>:<blob-sha>` per line.
#
# NOTICE_FILE env var overrides the default NOTICE path so tests can swap in
# fixtures without touching the live skill NOTICE.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

# --- Instrument self-test -----------------------------------------------
# Drive BOTH assertion helpers and refuse to continue unless both counters
# moved. An assertion-COUNT floor cannot do this job: a stub of the form
# `assert_eq() { PASS=$((PASS+1)); }` still increments, so the floor is
# satisfied by construction. Measured during #7710 review: neutering the
# helpers in THIS suite printed "Passed: 8 / ALL TESTS PASSED", exit 0, with
# every banner, staleness and scan-line assertion silently dropped — and this
# is the suite `gdpr-gate-self-test.yml` runs as a blocking gate.
#
# Reported via printf + exit 1, never through the helper it backstops (ADR-193).
_selftest() {
  local p0="$PASS" f0="$FAIL"
  assert_eq       "x" "x"   "instrument self-test — assert_eq records a pass"
  assert_eq       "x" "y"   "instrument self-test — assert_eq records a failure (EXPECTED FAIL above)"
  assert_contains "xy" "x"  "instrument self-test — assert_contains records a pass"
  assert_contains "xy" "zz" "instrument self-test — assert_contains records a failure (EXPECTED FAIL above)"
  if (( PASS != p0 + 2 )); then
    printf "INSTRUMENT SELF-TEST FAILED: helpers recorded %s passes, expected 2.\\n" "$((PASS - p0))" >&2
    exit 1
  fi
  if (( FAIL != f0 + 2 )); then
    printf "INSTRUMENT SELF-TEST FAILED: helpers recorded %s failures, expected 2.\\n" "$((FAIL - f0))" >&2
    printf "A helper that cannot fail certifies nothing.\\n" >&2
    exit 1
  fi
  PASS="$p0"; FAIL="$f0"
  printf "  (instrument self-test OK)\\n"
}
_selftest
echo ""


REPO_ROOT="$SCRIPT_DIR/../../.."
PARSER="$REPO_ROOT/plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh"
LIVE_NOTICE="$REPO_ROOT/plugins/soleur/skills/gdpr-gate/NOTICE"
FIXTURES_DIR="$SCRIPT_DIR/fixtures/vendor-drift"

echo "=== notice-frontmatter tests ==="
echo ""

assert_file_exists "$PARSER" "notice-frontmatter.sh exists"
assert_file_exists "$LIVE_NOTICE" "live NOTICE exists (frontmatter source of truth)"

# --- TS1: field upstream against live NOTICE ---
echo "TS1: field upstream returns the canonical upstream"
OUT=$(bash "$PARSER" field upstream)
assert_eq "github.com/goSprinto/compliance-skills" "$OUT" "field upstream is correct"
echo ""

# --- TS2: field pinned-commit ---
echo "TS2: field pinned-commit returns the 40-char SHA"
OUT=$(bash "$PARSER" field pinned-commit)
assert_eq "7b58d68461cb1fc033a063e34cc9de63d0b4144b" "$OUT" "field pinned-commit is correct"
echo ""

# --- TS3: field last-verified ---
echo "TS3: field last-verified returns ISO date"
OUT=$(bash "$PARSER" field last-verified)
assert_eq "2026-05-10" "$OUT" "field last-verified is correct"
echo ""

# --- TS4: lifted-files entry count matches the NOTICE body table ---
# lifted-files emits LOCAL blob SHAs (consumed by lefthook integrity gate);
# upstream-files emits UPSTREAM blob SHAs (consumed by drift workflow).
#
# The expected count is DERIVED from the NOTICE's own human-readable table,
# not written as a literal. NOTICE's preamble says "The frontmatter above is
# the canonical machine-readable form; the table below is the human-readable
# form. Drift between them is a bug." — so this assertion IS that bug's
# guard, and a literal here would have to be edited in lockstep with the very
# drift it is meant to catch.
#
# This is not hypothetical: #7710. The table listed EIGHT lifted files while
# the frontmatter carried FIVE, for 117 days. Three reference files were
# consequently rejected by the integrity gate as "silent local additions",
# and the drift cron compared five of eight files while reporting a clean
# corpus. A hardcoded `5` here was green throughout.
TABLE_COUNT=$(awk '
  /^## gosprinto\/compliance-skills \(MIT\)/ { in_tbl=1; next }
  /^## / { in_tbl=0 }
  in_tbl && /^\| `references\// { n++ }
  END { print n+0 }
' "$LIVE_NOTICE")

# Own-dispatch floor: an awk range that stops matching yields 0, and `0 == 0`
# against an empty registry would read as agreement. A zero table count is a
# harness defect, never a clean result.
if (( TABLE_COUNT < 8 )); then
  echo "  FAIL: NOTICE body table yielded $TABLE_COUNT lifted rows (expected >= 8) — table scrape is broken, not a clean registry"
  FAIL=$((FAIL + 1))
else
  echo "  PASS: NOTICE body table yielded $TABLE_COUNT lifted rows"
  PASS=$((PASS + 1))
fi

echo "TS4a: lifted-files entry count equals the NOTICE table's row count"
OUT=$(bash "$PARSER" lifted-files)
LINE_COUNT=$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')
assert_eq "$TABLE_COUNT" "$LINE_COUNT" "lifted-files frontmatter entries == NOTICE table rows"
assert_contains "$OUT" "references/fields.md:68675dd747fcbc74bb84c99eaa14983c9c5a6b24" "fields.md local-sha line present"
assert_contains "$OUT" "references/leakage-vectors.md:8d1d7fc44183e866e128707c3e91e7b63ce835fd" "leakage-vectors.md local-sha line present"
assert_contains "$OUT" "references/layers/api-layer.md:802fc866e320bebeecae2f8e53658253853ab5f9" "api-layer.md local-sha line present"
assert_contains "$OUT" "references/layers/data-in-transit.md:2ce203e9c041c1b1992ff9f7f636fdd63a667a44" "data-in-transit.md local-sha line present"
assert_contains "$OUT" "references/layers/data-lifecycle.md:29357a020bfa0e61f91dd529070fe3eb7cd251da" "data-lifecycle.md local-sha line present"
echo ""

echo "TS4b: upstream-files entry count equals the NOTICE table's row count"
OUT=$(bash "$PARSER" upstream-files)
LINE_COUNT=$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')
# Same derived count, second key. lifted-files and upstream-files walk the
# SAME block with different keys, so a divergence between these two means an
# entry is missing `upstream-path` or `upstream-blob-sha` — an entry the
# drift cron would silently skip while the integrity gate still pinned it.
assert_eq "$TABLE_COUNT" "$LINE_COUNT" "upstream-files frontmatter entries == NOTICE table rows"
assert_contains "$OUT" "pii-detector/patterns/fields.md:c1bb748fe00a53b283efe66ec937fa39437d2efc" "fields.md upstream line present"
assert_contains "$OUT" "pii-detector/rules/leakage-vectors.md:15a46e529e789930149f4b9bce875bfe5c53e478" "leakage-vectors.md upstream line present"
assert_contains "$OUT" "pii-detector/layers/api-layer.md:9d3202175c1d0225f60a912c489dbdacf4df491c" "api-layer.md upstream line present"
assert_contains "$OUT" "pii-detector/layers/data-in-transit.md:6c9eeabf17d1f0ed5660f5eb54d91587c81214ef" "data-in-transit.md upstream line present"
assert_contains "$OUT" "pii-detector/layers/data-lifecycle.md:a073ef24a0527c2c3a6d738b65ea3ef9d6194abe" "data-lifecycle.md upstream line present"
echo ""

# --- TS5: days-stale against live NOTICE prints non-negative integer ---
echo "TS5: days-stale prints a non-negative integer for the live NOTICE"
OUT=$(bash "$PARSER" days-stale)
if [[ "$OUT" =~ ^[0-9]+$ ]]; then
  echo "  PASS: days-stale prints integer ($OUT)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: days-stale did not print integer (got: '$OUT')"
  FAIL=$((FAIL + 1))
fi
echo ""

# --- TS6: missing NOTICE → 999 (stale-immediately fallback) ---
echo "TS6: missing NOTICE returns 999 from days-stale"
TMP_MISSING="$(mktemp)"
rm -f "$TMP_MISSING"  # ensure absent
OUT=$(NOTICE_FILE="$TMP_MISSING" bash "$PARSER" days-stale)
assert_eq "999" "$OUT" "days-stale=999 when NOTICE is missing"
echo ""

# --- TS7: malformed-YAML NOTICE → 999 ---
echo "TS7: malformed-YAML NOTICE returns 999 from days-stale"
TMP_MALFORMED="$(mktemp)"
cat > "$TMP_MALFORMED" <<'EOF'
---
upstream: github.com/goSprinto/compliance-skills
pinned-commit
last-verified 2026-05-10
EOF
OUT=$(NOTICE_FILE="$TMP_MALFORMED" bash "$PARSER" days-stale)
assert_eq "999" "$OUT" "days-stale=999 on malformed frontmatter (no closing ---, missing colons)"
rm -f "$TMP_MALFORMED"
echo ""

# --- TS8: future-dated NOTICE → 999 (per SpecFlow P1.5) ---
echo "TS8: future-dated NOTICE returns 999 from days-stale"
FUTURE_FIXTURE="$FIXTURES_DIR/notice-future-dated.frontmatter"
assert_file_exists "$FUTURE_FIXTURE" "notice-future-dated.frontmatter fixture exists"
OUT=$(NOTICE_FILE="$FUTURE_FIXTURE" bash "$PARSER" days-stale)
assert_eq "999" "$OUT" "days-stale=999 when last-verified is in the future"
echo ""

# --- TS9: missing frontmatter (no opening ---) → 999 ---
echo "TS9: NOTICE without frontmatter returns 999 from days-stale"
TMP_NOFM="$(mktemp)"
cat > "$TMP_NOFM" <<'EOF'
# NOTICE

This file has no frontmatter, only markdown body.
EOF
OUT=$(NOTICE_FILE="$TMP_NOFM" bash "$PARSER" days-stale)
assert_eq "999" "$OUT" "days-stale=999 when frontmatter is absent"
rm -f "$TMP_NOFM"
echo ""

# --- TS10: parser exit code is 0 even on failure paths (advisory contract) ---
echo "TS10: parser exits 0 on missing/malformed input (advisory contract preserved)"
TMP_GONE="$(mktemp)"
rm -f "$TMP_GONE"
set +e
NOTICE_FILE="$TMP_GONE" bash "$PARSER" days-stale >/dev/null 2>&1
RC=$?
set -e
assert_eq "0" "$RC" "exit 0 when NOTICE missing (so subshell-exec from gdpr-gate.sh stays advisory)"
echo ""

# --- TS11: timing — p95 < 100ms across 100 invocations of days-stale ---
# Budget widened from 50ms to 100ms after the parser added strict-ISO
# validation + UTC anchoring on last-verified (review #3521). The original
# 50ms threshold was within process-spawn jitter of the date(1) call;
# 100ms gives 2× headroom while still bounding the runtime overhead the
# banner adds to every gate invocation.
#
# CI-only gate (#4096): measured p95 includes scheduler latency outside the
# parser's control. Under local concurrent load (IDE indexers, parallel test
# suites) the budget fires on noise, not on a parser regression. CI runners
# have predictable load; enforce strictly there, skip locally.
if [[ "${CI:-}" == "true" ]]; then
  echo "TS11: p95 < 100ms over 100 invocations of days-stale"
  TIMINGS_FILE="$(mktemp)"
  for _ in $(seq 1 100); do
    # Capture wall-clock ms via /usr/bin/time -f "%e" (seconds with 2 decimal
    # places). Multiply by 1000, round to integer.
    SECS=$( { /usr/bin/time -f "%e" bash "$PARSER" days-stale >/dev/null ; } 2>&1 )
    printf '%s\n' "$SECS"
  done > "$TIMINGS_FILE"
  # Convert to integer milliseconds, sort, pick p95 (95th percentile = 95th of
  # 100 sorted ascending).
  P95_MS=$(awk '{printf "%d\n", $1*1000}' "$TIMINGS_FILE" | sort -n | awk 'NR==95')
  echo "  p95: ${P95_MS}ms (over 100 runs)"
  if (( P95_MS < 100 )); then
    echo "  PASS: p95 < 100ms"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: p95 >= 100ms (TR2 budget breached)"
    FAIL=$((FAIL + 1))
  fi
  rm -f "$TIMINGS_FILE"
else
  echo "TS11: SKIP (timing test, CI-only — set CI=true to run locally)"
  SKIPPED=$((SKIPPED + 1))
fi
echo ""

# --- TS-cron-1: cron-run-stale with no token → 999 (no-network path) ---
echo "TS-cron-1: cron-run-stale with GH_TOKEN='' and GITHUB_TOKEN='' returns 999"
OUT=$(GH_TOKEN="" GITHUB_TOKEN="" bash "$PARSER" cron-run-stale)
assert_eq "999" "$OUT" "cron-run-stale=999 when no token is available"
echo ""

# --- TS-cron-2: cron-run-stale with stub gh emitting a fixture timestamp ---
# Use a relative date (99 days ago, computed at test time) so the assertion
# is exact and the test is not a calendar landmine. An earlier form pinned
# 2026-02-01 + asserted a 20-day window; the window expired ~10 days after
# merge. Relative date + exact equality eliminates clock drift entirely
# (the test fixture moves with today's date).
echo "TS-cron-2: cron-run-stale with stubbed gh returns 99 (relative date)"
STUB_DIR_2="$(mktemp -d)"
STUB_TS=$(date -u -d '99 days ago' +%Y-%m-%dT00:00:00Z)
make_gh_stub "$STUB_DIR_2" "$STUB_TS"
OUT=$(GH_TOKEN="stub-token" PATH="$STUB_DIR_2:$PATH" bash "$PARSER" cron-run-stale)
assert_eq "99" "$OUT" "cron-run-stale prints exact days (99) for fixture timestamp"
rm -rf "$STUB_DIR_2"
echo ""

# --- TS-cron-3: cron-run-stale with stub gh emitting literal 'null' → 999 ---
# Matches `gh run list ... --jq '.[0].updatedAt'` on an empty result array.
# The parser's `// empty` jq filter + strict-ISO regex must both guard this.
echo "TS-cron-3: cron-run-stale with stub gh emitting 'null' returns 999"
STUB_DIR_3="$(mktemp -d)"
make_gh_stub "$STUB_DIR_3" "null"
OUT=$(GH_TOKEN="stub-token" PATH="$STUB_DIR_3:$PATH" bash "$PARSER" cron-run-stale)
assert_eq "999" "$OUT" "cron-run-stale=999 when stub gh emits 'null'"
rm -rf "$STUB_DIR_3"
echo ""

# --- TS-cron-4: cron-run-stale with stub gh emitting non-RFC3339 string → 999 ---
echo "TS-cron-4: cron-run-stale with non-RFC3339 stub output returns 999"
STUB_DIR_4="$(mktemp -d)"
make_gh_stub "$STUB_DIR_4" "2026-02-01"  # date-only, missing T...Z
OUT=$(GH_TOKEN="stub-token" PATH="$STUB_DIR_4:$PATH" bash "$PARSER" cron-run-stale)
assert_eq "999" "$OUT" "cron-run-stale=999 when stub gh emits a date-only string"
rm -rf "$STUB_DIR_4"
echo ""

# --- TS-cron-empty: cron-run-stale with stub gh emitting empty stdout → 999 ---
# Models the workflow-renamed / workflow-deleted case where
# `gh run list --workflow=<missing>` exits 0 with an empty array, which
# `jq '.[0].updatedAt // empty'` collapses to empty string. The strict-ISO
# regex must reject empty input (architecture-strategist finding on #3541).
echo "TS-cron-empty: cron-run-stale with stub gh emitting empty stdout returns 999"
STUB_DIR_EMPTY="$(mktemp -d)"
make_gh_stub "$STUB_DIR_EMPTY" ""
OUT=$(GH_TOKEN="stub-token" PATH="$STUB_DIR_EMPTY:$PATH" bash "$PARSER" cron-run-stale)
assert_eq "999" "$OUT" "cron-run-stale=999 when stub gh emits empty stdout (workflow renamed/deleted case)"
rm -rf "$STUB_DIR_EMPTY"
echo ""

# --- TS-cron-5: cron-run-stale with slow stub gh → 999, bounded by timeout ---
# Asserts the `timeout 5s` wrapper fires. Wall-clock < 6s (5s + grace).
echo "TS-cron-5: cron-run-stale with slow stub gh returns 999 within 6s"
STUB_DIR_5="$(mktemp -d)"
make_gh_stub_sleep "$STUB_DIR_5" 10
SECS=$( { /usr/bin/time -f "%e" \
  bash -c "GH_TOKEN=stub-token PATH=\"$STUB_DIR_5:\$PATH\" bash \"$PARSER\" cron-run-stale" \
  >/tmp/cron-stale-out.$$ ; } 2>&1 )
OUT=$(cat /tmp/cron-stale-out.$$ 2>/dev/null)
rm -f /tmp/cron-stale-out.$$
assert_eq "999" "$OUT" "cron-run-stale=999 when gh times out"
# Compare floats via awk; emit "PASS"/"FAIL" string and assert it.
WALL_OK=$(awk -v t="$SECS" 'BEGIN { print (t < 6 ? "PASS" : "FAIL") }')
assert_eq "PASS" "$WALL_OK" "cron-run-stale wall-clock <6s (got: ${SECS}s)"
rm -rf "$STUB_DIR_5"
echo ""

# --- TS12: timing — p95 < 100ms across 100 invocations of cron-run-stale ---
# Budget mirrors TS11. Measure the no-token (no-network) path; the
# token-present path inherits the GitHub API latency and is not budgeted.
#
# CI-only gate (#4096): same rationale as TS11 — scheduler latency under
# local load is outside the parser's control.
if [[ "${CI:-}" == "true" ]]; then
  echo "TS12: p95 < 100ms over 100 invocations of cron-run-stale (no-token path)"
  TIMINGS_FILE_2="$(mktemp)"
  for _ in $(seq 1 100); do
    SECS=$( { /usr/bin/time -f "%e" \
      bash -c "GH_TOKEN='' GITHUB_TOKEN='' bash \"$PARSER\" cron-run-stale" \
      >/dev/null ; } 2>&1 )
    printf '%s\n' "$SECS"
  done > "$TIMINGS_FILE_2"
  P95_MS_2=$(awk '{printf "%d\n", $1*1000}' "$TIMINGS_FILE_2" | sort -n | awk 'NR==95')
  echo "  p95: ${P95_MS_2}ms (over 100 runs)"
  if (( P95_MS_2 < 100 )); then
    echo "  PASS: p95 < 100ms"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: p95 >= 100ms (TS12 budget breached)"
    FAIL=$((FAIL + 1))
  fi
  rm -f "$TIMINGS_FILE_2"
else
  echo "TS12: SKIP (timing test, CI-only — set CI=true to run locally)"
  SKIPPED=$((SKIPPED + 1))
fi
echo ""

# --- record-count / key-count: the completeness denominator ---------------
#
# These subcommands carry the `filesExamined === registryCount` conjunct in
# cron-content-vendor-drift, and until #7710 review NOTHING EXECUTED THEM —
# only a source-grep asserted the call site. Measured: replacing the
# `record-count` case body with `echo 0` (which disables the writer forever)
# and with `cmd_upstream_files | wc -l` (which REINSTATES the exact tautology
# the conjunct exists to close) both survived all four bash suites.
echo "TS-RC: record-count and key-count over a registry with a dropped record"

RC_DIR="$(mktemp -d -t notice-rc.XXXXXXXX)"
assert_fixture_dir "$RC_DIR"
trap 'rm -rf "$RC_DIR"' EXIT

# 3 declared records. Record b is missing `upstream-blob-sha`, so the FILTERED
# views drop it; record c is intact.
cat > "$RC_DIR/NOTICE" <<'RC_EOF'
---
upstream: github.com/goSprinto/compliance-skills
pinned-commit: 7b58d68461cb1fc033a063e34cc9de63d0b4144b
last-verified: 2026-05-10
registry: knowledge-base/engineering/policies/content-vendoring.md
lifted-files:
  - path: references/a.md
    upstream-path: pii/a.md
    upstream-blob-sha: aaa1111111111111111111111111111111111111
    local-blob-sha: bbb1111111111111111111111111111111111111
    status: active
  - path: references/b.md
    upstream-path: pii/b.md
    local-blob-sha: bbb2222222222222222222222222222222222222
    status: active
  - path: references/c.md
    upstream-path: pii/c.md
    upstream-blob-sha: aaa3333333333333333333333333333333333333
    local-blob-sha: bbb3333333333333333333333333333333333333
    status: active
---
RC_EOF

RC_DECLARED=$(NOTICE_FILE="$RC_DIR/NOTICE" bash "$PARSER" record-count lifted-files)
RC_STATUS=$(NOTICE_FILE="$RC_DIR/NOTICE" bash "$PARSER" key-count lifted-files status)
RC_EMITTED=$(NOTICE_FILE="$RC_DIR/NOTICE" bash "$PARSER" upstream-files | wc -l | tr -d ' ')

assert_eq "3" "$RC_DECLARED" "record-count counts DECLARED records, including the incomplete one"
assert_eq "3" "$RC_STATUS" "key-count counts a key the record-opener predicate does not consume"
assert_eq "2" "$RC_EMITTED" "the filtered upstream view silently DROPS the incomplete record"

# The whole point: the denominator must NOT equal the filtered view, or the
# completeness conjunct can never fail.
if [[ "$RC_DECLARED" != "$RC_EMITTED" ]]; then
  echo "  PASS: declared ($RC_DECLARED) != emitted ($RC_EMITTED) — a partial comparison is detectable"
  PASS=$((PASS + 1))
else
  echo "  FAIL: declared == emitted on a registry with a dropped record — the completeness conjunct is a tautology"
  FAIL=$((FAIL + 1))
fi

# Opener deletion: the record's keys are absorbed by its predecessor, so the
# opener count AND the filtered view both shrink together. Only a key the
# opener predicate does not consume still sees three.
sed '/^  - path: references\/c.md$/d' "$RC_DIR/NOTICE" > "$RC_DIR/NOTICE-noopener"
RC_D2=$(NOTICE_FILE="$RC_DIR/NOTICE-noopener" bash "$PARSER" record-count lifted-files)
RC_S2=$(NOTICE_FILE="$RC_DIR/NOTICE-noopener" bash "$PARSER" key-count lifted-files status)
assert_eq "2" "$RC_D2" "opener deletion shrinks the record count"
assert_eq "3" "$RC_S2" "key-count still sees three records — it does not share the opener predicate"
if [[ "$RC_S2" != "$RC_D2" ]]; then
  echo "  PASS: the two declared views DISAGREE on opener loss, so it cannot pass silently"
  PASS=$((PASS + 1))
else
  echo "  FAIL: both declared views moved together — opener loss is undetectable"
  FAIL=$((FAIL + 1))
fi

# Empty registry must be 0, not an error that reads as a count.
assert_eq "0" "$(NOTICE_FILE=/nonexistent/NOTICE bash "$PARSER" record-count lifted-files)" \
  "record-count returns 0 when the NOTICE cannot be read (fail-closed)"
echo ""

print_results 41
