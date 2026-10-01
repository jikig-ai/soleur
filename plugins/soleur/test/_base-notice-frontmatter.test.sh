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

REPO_ROOT="$SCRIPT_DIR/../../.."
PARSER="$REPO_ROOT/plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh"
LIVE_NOTICE="$REPO_ROOT/plugins/soleur/skills/gdpr-gate/NOTICE"
FIXTURES_DIR="$SCRIPT_DIR/fixtures/vendor-drift"

# ONE owning trap for every tempfile and tempdir this suite allocates (ADR-129,
# enforced by `scripts/lint-trap-tempfile-ownership.py`). This suite allocates
# eleven and registered none: if it died between an allocation and its cleanup —
# which `set -euo pipefail` makes routine on any failing assertion — the leak
# survived the run.
#
# Registered at each CALL SITE, in the parent shell, and NOT through a helper.
# A first version wrapped the allocations in `_own() { _TMP_OWNED+=("$1"); ... }`
# invoked as `$(_own "$(mktemp)")` — command substitution runs the helper in a
# SUBSHELL, so every append mutated a copy and the parent array stayed empty
# while the trap read as correct. That linter caught it; the note is kept so the
# next reader does not reintroduce the tidier form.
_TMP_OWNED=()
trap 'rm -rf "${_TMP_OWNED[@]:-}"' EXIT INT TERM

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
# The field is advanced by the weekly vendor-drift cron's attestation PRs, so
# pinning a literal here red-lights every attestation it exists to verify —
# the first attestation PR ever opened (#8166, advancing to 2026-09-14) failed
# CI on exactly this line while carrying no defect of its own. Assert the
# invariants the field is contracted to hold instead: ISO calendar-date shape,
# never below the first recorded verification epoch (the field only advances),
# and never future-dated (a future value asserts a comparison no artifact ran).
#
# Second site of the same pin: #8251 converted the sibling
# `notice-frontmatter.test.sh` to this contract form; this base suite was
# missed (same miss class as the TS4 hardcoded row count documented below),
# and #8166 red-lit on `test-scripts (3/3)` a second time because of it.
echo "TS3: field last-verified returns ISO date"
OUT=$(bash "$PARSER" field last-verified)
if [[ "$OUT" =~ ^20[0-9]{2}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$ ]]; then
  echo "  PASS: field last-verified is ISO-dated ($OUT)"
  PASS=$((PASS + 1))
else
  echo "  FAIL: field last-verified is not an ISO calendar date (got: '$OUT')"
  FAIL=$((FAIL + 1))
fi
TODAY="$(date +%F)"
if [[ ! "$OUT" < "2026-05-10" && ! "$TODAY" < "$OUT" ]]; then
  echo "  PASS: field last-verified is within [2026-05-10, $TODAY]"
  PASS=$((PASS + 1))
else
  echo "  FAIL: field last-verified out of range [2026-05-10, $TODAY] (got: '$OUT')"
  FAIL=$((FAIL + 1))
fi
echo ""

# --- TS4: the emitted registry agrees with the NOTICE body table ---
# lifted-files emits LOCAL blob SHAs (consumed by lefthook integrity gate);
# upstream-files emits UPSTREAM blob SHAs (consumed by drift workflow).
#
# DERIVED FROM THE TABLE, never hardcoded. A literal `5` sat here while the
# NOTICE body table listed EIGHT, and nothing compared the two for 117 days:
# the three unlisted files were rejected by the integrity gate as "silent
# local additions", and the drift cron compared five of eight while reporting
# a clean corpus. The hardcoded number was green throughout — and it went red
# only when #7710 corrected the registry, i.e. it fired on the FIX rather than
# on the defect. The sibling `notice-frontmatter.test.sh` was converted to the
# table-derived form; this base suite was missed, which is the whole reason to
# make the oracle the content rather than a number.
TABLE_COUNT=$(awk '
  /^## gosprinto\/compliance-skills \(MIT\)/ { in_tbl=1; next }
  /^## / { in_tbl=0 }
  in_tbl && /^\| `references\// { n++ }
  END { print n+0 }
' "$LIVE_NOTICE")

# Own-dispatch floor: an awk range that stops matching yields 0, and `0 == 0`
# against an empty registry would read as agreement.
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
assert_eq "$TABLE_COUNT" "$LINE_COUNT" "upstream-files frontmatter entries == NOTICE table rows"
assert_contains "$OUT" "pii-detector/patterns/fields.md:c1bb748fe00a53b283efe66ec937fa39437d2efc" "fields.md upstream line present"
assert_contains "$OUT" "pii-detector/rules/leakage-vectors.md:15a46e529e789930149f4b9bce875bfe5c53e478" "leakage-vectors.md upstream line present"
assert_contains "$OUT" "pii-detector/layers/api-layer.md:9d3202175c1d0225f60a912c489dbdacf4df491c" "api-layer.md upstream line present"
assert_contains "$OUT" "pii-detector/layers/data-in-transit.md:6c9eeabf17d1f0ed5660f5eb54d91587c81214ef" "data-in-transit.md upstream line present"
assert_contains "$OUT" "pii-detector/layers/data-lifecycle.md:a073ef24a0527c2c3a6d738b65ea3ef9d6194abe" "data-lifecycle.md upstream line present"
echo ""

# --- TS4c: legal-generate bundle gets the same frontmatter↔table parity ---
# The second vendored bundle (#8122) must not be a parity orphan: the #7710
# defect class (table/frontmatter divergence undetected for 117 days) is
# exactly what a second NOTICE reintroduces if only gdpr-gate is covered.
LEGAL_NOTICE="$REPO_ROOT/plugins/soleur/skills/legal-generate/NOTICE"
if [[ -f "$LEGAL_NOTICE" ]]; then
  LG_TABLE_COUNT=$(awk '
    /^## General-Legal\/legal-templates \(CC0-1\.0\)/ { in_tbl=1; next }
    /^## / { in_tbl=0 }
    in_tbl && /^\| `references\// { n++ }
    END { print n+0 }
  ' "$LEGAL_NOTICE")
  if (( LG_TABLE_COUNT < 12 )); then
    echo "  FAIL: legal-generate NOTICE body table yielded $LG_TABLE_COUNT lifted rows (expected >= 12) — table scrape is broken, not a clean registry"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: legal-generate NOTICE body table yielded $LG_TABLE_COUNT lifted rows"
    PASS=$((PASS + 1))
  fi
  echo "TS4c: legal-generate lifted-files/upstream-files counts equal the NOTICE table's row count"
  LG_OUT=$(NOTICE_FILE="$LEGAL_NOTICE" bash "$PARSER" lifted-files)
  LG_LINE_COUNT=$(printf '%s\n' "$LG_OUT" | wc -l | tr -d ' ')
  assert_eq "$LG_TABLE_COUNT" "$LG_LINE_COUNT" "legal-generate lifted-files entries == NOTICE table rows"
  LG_OUT=$(NOTICE_FILE="$LEGAL_NOTICE" bash "$PARSER" upstream-files)
  LG_LINE_COUNT=$(printf '%s\n' "$LG_OUT" | wc -l | tr -d ' ')
  assert_eq "$LG_TABLE_COUNT" "$LG_LINE_COUNT" "legal-generate upstream-files entries == NOTICE table rows"
else
  echo "  FAIL: legal-generate NOTICE missing — the vendored bundle's parity guard cannot run"
  FAIL=$((FAIL + 1))
fi
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
TMP_MISSING="$(mktemp)"; _TMP_OWNED+=("$TMP_MISSING")
rm -f "$TMP_MISSING"  # ensure absent
OUT=$(NOTICE_FILE="$TMP_MISSING" bash "$PARSER" days-stale)
assert_eq "999" "$OUT" "days-stale=999 when NOTICE is missing"
echo ""

# --- TS7: malformed-YAML NOTICE → 999 ---
echo "TS7: malformed-YAML NOTICE returns 999 from days-stale"
TMP_MALFORMED="$(mktemp)"; _TMP_OWNED+=("$TMP_MALFORMED")
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
TMP_NOFM="$(mktemp)"; _TMP_OWNED+=("$TMP_NOFM")
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
TMP_GONE="$(mktemp)"; _TMP_OWNED+=("$TMP_GONE")
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
  TIMINGS_FILE="$(mktemp)"; _TMP_OWNED+=("$TIMINGS_FILE")
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
STUB_DIR_2="$(mktemp -d)"; _TMP_OWNED+=("$STUB_DIR_2")
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
STUB_DIR_3="$(mktemp -d)"; _TMP_OWNED+=("$STUB_DIR_3")
make_gh_stub "$STUB_DIR_3" "null"
OUT=$(GH_TOKEN="stub-token" PATH="$STUB_DIR_3:$PATH" bash "$PARSER" cron-run-stale)
assert_eq "999" "$OUT" "cron-run-stale=999 when stub gh emits 'null'"
rm -rf "$STUB_DIR_3"
echo ""

# --- TS-cron-4: cron-run-stale with stub gh emitting non-RFC3339 string → 999 ---
echo "TS-cron-4: cron-run-stale with non-RFC3339 stub output returns 999"
STUB_DIR_4="$(mktemp -d)"; _TMP_OWNED+=("$STUB_DIR_4")
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
STUB_DIR_EMPTY="$(mktemp -d)"; _TMP_OWNED+=("$STUB_DIR_EMPTY")
make_gh_stub "$STUB_DIR_EMPTY" ""
OUT=$(GH_TOKEN="stub-token" PATH="$STUB_DIR_EMPTY:$PATH" bash "$PARSER" cron-run-stale)
assert_eq "999" "$OUT" "cron-run-stale=999 when stub gh emits empty stdout (workflow renamed/deleted case)"
rm -rf "$STUB_DIR_EMPTY"
echo ""

# --- Wall-clock helpers for TS-cron-5 (#8250) ---
# TS-cron-5 used GNU time by its absolute path (the `time -f "%e"` form), absent on
# macOS and on minimal Linux hosts, where the call exited 127 and `set -e`
# aborted the whole suite mid-run. Two $EPOCHREALTIME reads (bash 5+, no
# coreutils) replace it, split into integer microseconds with ${t%.*}/${t#*.}
# — the scripts/test-all.sh idiom — so no float parsing is involved.
#
# A read that is not `digits.digits` makes the CASE FAIL, never pass: under a
# comma-radix locale or an old bash (unset EPOCHREALTIME) a lenient parse would
# compute a zero or garbage elapsed time and `< 6 s` would pass vacuously.
# Wall-clock parser + its own contract rows, shared with the sibling suite.
# Both files carried a byte-identical ~45-line copy; they have a documented
# two-PR drift history, so there is now one copy.
# shellcheck source=lib/wall-clock.sh
source "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/wall-clock.sh"
_wall_clock_self_test


# --- TS-cron-5: cron-run-stale with slow stub gh → 999, bounded by timeout ---
# Asserts the `timeout 5s` wrapper fires. Wall-clock < 6s (5s + grace).
echo "TS-cron-5: cron-run-stale with slow stub gh returns 999 within 6s"
STUB_DIR_5="$(mktemp -d)"; _TMP_OWNED+=("$STUB_DIR_5")
make_gh_stub_sleep "$STUB_DIR_5" 10
T_START="${EPOCHREALTIME:-}"
GH_TOKEN=stub-token PATH="$STUB_DIR_5:$PATH" bash "$PARSER" cron-run-stale >/tmp/cron-stale-out.$$
T_END="${EPOCHREALTIME:-}"
OUT=$(cat /tmp/cron-stale-out.$$ 2>/dev/null)
rm -f /tmp/cron-stale-out.$$
assert_eq "999" "$OUT" "cron-run-stale=999 when gh times out"
WALL_OK=$(_wall_verdict "$T_START" "$T_END" 6000000)
assert_eq "PASS" "$WALL_OK" "cron-run-stale wall-clock <6s (start=${T_START:-<unset>} end=${T_END:-<unset>})"
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
  TIMINGS_FILE_2="$(mktemp)"; _TMP_OWNED+=("$TIMINGS_FILE_2")
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

print_results
