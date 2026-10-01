#!/usr/bin/env bash
#
# Tests for fix-round-seats.sh — the single path→seat map consumed by both the
# `none`-tier panel gating and the post-panel fix-commit targeted round (ADR-265).
#
# The suite needs NO filesystem fixtures — the SUT is a pure argv→stdout
# function, so every arm is an invocation plus a stdout/stderr assertion. That
# also means there is deliberately no mktemp/assert_fixture_dir machinery.
#
# Mutation axes covered (Guard 1 of the 9399 plan): per-arm membership, the
# code-quality floor on unmatched source, multi-area unions, registry
# validation of emitted AND --finding-seats tokens, the forged-token drop, and
# the empty-diff contract.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$(cd "${DIR}/../scripts" && pwd)/fix-round-seats.sh"
WORKFLOW="$(cd "${DIR}/../workflows" && pwd)/review.workflow.js"

passes=0
fails=0
# INDEPENDENT case counter (ADR-193): moves in assert(), never in the verdict
# helpers — a counter owned by pass()/fail() dies with the verdict it counts.
CASES=0

pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() {
  fails=$((fails + 1))
  printf '  FAIL %s\n' "$1"
  [[ -n "${2:-}" ]] && printf '       %s\n' "$2"
  return 0
}

assert() {
  CASES=$((CASES + 1))
  if eval "$2"; then
    pass "$1"
  else
    fail "$1" "${3:-$2}"
  fi
}

printf '\n=== fix-round-seats ===\n\n'

[[ -f "$SUT" ]] || {
  printf '\n[FATAL] SUT missing at %s — nothing to test.\n' "$SUT" >&2
  exit 1
}
[[ -f "$WORKFLOW" ]] || {
  printf '\n[FATAL] workflow missing at %s — registry cannot be derived.\n' "$WORKFLOW" >&2
  exit 1
}

# Canonical seat registry, DERIVED — not restated. Agent-type leaves come from
# the workflow's DIMENSIONS registry; the two deterministic/non-agent seats the
# workflow carries (shellcheck, anti-slop, gdpr) plus the SKILL-only
# structural-enumeration seat are appended explicitly.
registry() {
  grep -oE "agentType: 'soleur:[a-z:-]+'" "$WORKFLOW" | tr -d "'" | awk -F: '{print $NF}'
  printf '%s\n' shellcheck anti-slop gdpr-gate structural-enumeration
}

run() { # $1=label; rest=args — captures stdout, stderr, rc without a subshell race
  local label="$1"; shift
  OUT="$(bash "$SUT" "$@" 2>"$TMPERR")"; RC=$?
  ERR="$(cat "$TMPERR")"
}
TMPERR="$(mktemp -t fixseats-err.XXXXXXXX)"
trap 'rm -f "$TMPERR"' EXIT

# ── ARM 1: migration path → data-integrity + data-migration (+ deploy-verify) ──
run mig --files 'apps/web-platform/supabase/migrations/20990101000000_x.sql'
assert "migration path exits 0" '[[ "$RC" -eq 0 ]]' "rc=$RC err=$ERR"
assert "migration path emits data-integrity-guardian" \
  'grep -qx "data-integrity-guardian" <<<"$OUT"' "out=$OUT"
assert "migration path emits data-migration-expert" \
  'grep -qx "data-migration-expert" <<<"$OUT"' "out=$OUT"
assert "migration path emits deployment-verification-agent" \
  'grep -qx "deployment-verification-agent" <<<"$OUT"' "out=$OUT"

# ── ARM 2: floor — an unmatched source path still emits code-quality-analyst ──
# `scripts/lib/` hits no area arm (not web-platform, not plugins/soleur), so the
# only mapped seat is the deterministic SAST one — the floor must still fire.
run floor --files 'scripts/lib/foo.ts'
assert "unmatched source emits code-quality floor" \
  '[[ "$RC" -eq 0 ]] && grep -qx "code-quality-analyst" <<<"$OUT"' "rc=$RC out=$OUT"
assert "unmatched source also emits semgrep (source extension)" \
  'grep -qx "semgrep-sast" <<<"$OUT"' "out=$OUT"

# ── ARM 3: multi-area union does not stop at the first member ─────────────────
run multi --files $'plugins/soleur/skills/review/test/fix-round-seats.test.sh\napps/web-platform/supabase/migrations/20990101000000_x.sql'
assert "test file + migration yields BOTH test-design and data-integrity" \
  'grep -qx "test-design-reviewer" <<<"$OUT" && grep -qx "data-integrity-guardian" <<<"$OUT"' "out=$OUT"
assert "test file + .sh extension also yields shellcheck" \
  'grep -qx "shellcheck" <<<"$OUT"' "out=$OUT"

# ── ARM 4: every emitted token resolves against the canonical registry ────────
run reg --files $'apps/web-platform/supabase/migrations/20990101000000_x.sql\napps/web-platform/server/auth.ts\nplugins/soleur/skills/review/test/fix-round-seats.test.sh'
_reg="$(registry | sort -u)"
_bad="$(comm -23 <(sort -u <<<"$OUT") <(printf '%s\n' "$_reg"))"
assert "all emitted seats resolve against the derived registry" \
  '[[ -z "$_bad" ]]' "unregistered: $_bad"

# ── ARM 5: --finding-seats unions the reporting seat ──────────────────────────
run find --files 'docs/guide.md' --finding-seats user-impact-reviewer
assert "finding-seat unions into an otherwise path-empty round" \
  '[[ "$RC" -eq 0 ]] && grep -qx "user-impact-reviewer" <<<"$OUT"' "rc=$RC out=$OUT"

# ── ARM 6: forged / unknown --finding-seats tokens never reach stdout ──────────
run forge --files 'docs/guide.md' --finding-seats $'security-sentinel\nBUG-INJECTED'
assert "newline-forged token is dropped, not echoed" \
  '! grep -qx "BUG-INJECTED" <<<"$OUT"' "out=$OUT"
assert "newline-forged token warns on stderr" \
  'grep -q "unknown-seat:" <<<"$ERR"' "err=$ERR"
assert "the real seat in the same arg survives" \
  'grep -qx "security-sentinel" <<<"$OUT"' "out=$OUT"
run unk --files 'docs/guide.md' --finding-seats 'not-a-seat'
assert "unknown seat name dropped with warning" \
  '[[ "$RC" -eq 0 ]] && ! grep -qx "not-a-seat" <<<"$OUT" && grep -q "unknown-seat: not-a-seat" <<<"$ERR"' \
  "rc=$RC out=$OUT err=$ERR"

# ── ARM 7: empty --files is a distinct exit-0 contract ────────────────────────
run empty --files ''
assert "empty file list exits 0 with empty stdout" \
  '[[ "$RC" -eq 0 && -z "$OUT" ]]' "rc=$RC out=$OUT"
assert "empty file list notes it on stderr" \
  'grep -q "note: empty fix diff" <<<"$ERR"' "err=$ERR"

# ── ARM 8: sensitive path → security-sentinel ─────────────────────────────────
run sens --files 'apps/web-platform/server/session-sync.ts'
assert "sensitive path emits security-sentinel" \
  'grep -qx "security-sentinel" <<<"$OUT"' "out=$OUT"

# ── ARM 9: docs-only path emits no seats (floor is source-only) ───────────────
run docs --files 'README.md'
assert "non-source unmatched path emits nothing" \
  '[[ "$RC" -eq 0 && -z "$OUT" ]]' "rc=$RC out=$OUT"

# ── ARM 10: usage error exits 2 ───────────────────────────────────────────────
run badflag --bogus
assert "unknown flag exits 2" '[[ "$RC" -eq 2 ]]' "rc=$RC"
run noargs
assert "no args exits 2" '[[ "$RC" -eq 2 ]]' "rc=$RC"

# ── ARM 11: deterministic dedup — duplicate paths and seat overlap ────────────
run dup --files $'a/x.test.ts\nb/y.test.ts\na/x.test.ts'
_n="$(printf '%s\n' "$OUT" | sort | uniq -d | wc -l | tr -d ' ')"
assert "no seat emitted twice" '[[ "$_n" -eq 0 ]]' "dups in: $OUT"

# ── ARM 12: comma-separated --files also parses ───────────────────────────────
run comma --files 'apps/web-platform/supabase/migrations/20990101000000_x.sql,plugins/soleur/skills/review/test/fix-round-seats.test.sh'
assert "comma-separated files parse identically" \
  'grep -qx "data-integrity-guardian" <<<"$OUT" && grep -qx "test-design-reviewer" <<<"$OUT"' "out=$OUT"

# ── Accounting conservation (ADR-193 #3) — reported directly, never via verdict helpers ──
if [[ $((passes + fails)) -ne "$CASES" ]]; then
  printf '\n[FATAL] accounting: passes+fails (%d) != CASES (%d).\n' \
    "$((passes + fails))" "$CASES" >&2
  printf '\n=== fix-round-seats: %d passed, %d failed (%d assertions) ===\n\n' \
    "$passes" "$fails" "$CASES" >&2
  exit 1
fi

# ── Anti-vacuity floor (ADR-193 #1) — reads the INDEPENDENT counter ───────────
SELFTEST_PASSES=1
FIXSEATS_MIN_ASSERTIONS=20
if (( CASES - SELFTEST_PASSES < FIXSEATS_MIN_ASSERTIONS )); then
  printf '\n[FATAL] anti-vacuity floor: only %d assertion(s) ran, expected >= %d.\n' \
    "$((CASES - SELFTEST_PASSES))" "$FIXSEATS_MIN_ASSERTIONS" >&2
  printf '\n=== fix-round-seats: %d passed, %d failed (%d assertions) ===\n\n' \
    "$passes" "$fails" "$CASES" >&2
  exit 1
fi

printf '\n=== fix-round-seats: %d passed, %d failed (%d assertions) ===\n\n' \
  "$passes" "$fails" "$CASES"
[[ "$fails" -eq 0 ]]
