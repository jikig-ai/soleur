#!/usr/bin/env bash
#
# Tests for fix-round-seats.sh — the single path→seat map consumed by both the
# `none`-tier panel gating and the post-panel fix-commit targeted round (ADR-267).
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
# the workflow's DIMENSIONS registry; the deterministic/non-agent seats the
# workflow carries (shellcheck, anti-slop, gdpr) plus the SKILL-only
# structural-enumeration seat are appended explicitly.
registry() {
  grep -oE "agentType: 'soleur:[a-z:-]+'" "$WORKFLOW" | tr -d "'" | awk -F: '{print $NF}'
  printf '%s\n' shellcheck anti-slop gdpr-gate structural-enumeration code-simplicity-reviewer
}

run() { # $1=label; rest=args — captures stdout, stderr, rc without a subshell race
  local label; label="$1"; : "$label"; shift
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
# Golden output pins membership AND order AND suppression: nothing else may be
# emitted for a lone unmatched source path.
assert "unmatched source emits EXACTLY code-quality + semgrep, in order" \
  '[[ "$OUT" == $'"'"'code-quality-analyst\nsemgrep-sast'"'"' ]]' "out=$OUT"
assert "unmatched source names the path on stderr (unmapped-paths)" \
  'grep -q "unmapped-paths: scripts/lib/foo.ts" <<<"$ERR"' "err=$ERR"

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

# NB: sensitive-path fixtures name a NONEXISTENT path on purpose — the
# battery-tag-authorship closure walks filesystem-real path mentions, and a
# fixture naming a file that runs `git fetch`/`pull` would drag it into the
# battery's offender census (measured live: session-sync.ts, 3 offenders).
# ── ARM 8: sensitive path → security-sentinel ─────────────────────────────────
run sens --files 'apps/web-platform/lib/stripe/__fixture__.ts'
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

# ── ARM 11: every map arm has a presence pin ─────────────────────────────────
# PERSIST isolated (a lib/ path that hits no other arm), PERF, GDPR, and
# ANTISLOP/AGENT_SURFACE each get a fixture — deleting any single arm must red.
run persist --files 'apps/web-platform/lib/util.ts'
assert "persistence lib/ arm emits data-integrity-guardian" \
  'grep -qx "data-integrity-guardian" <<<"$OUT"' "out=$OUT"
run perf --files 'packages/inngest/foo.ts'
assert "perf-arm path emits performance-oracle" \
  'grep -qx "performance-oracle" <<<"$OUT"' "out=$OUT"
run gdprarm --files 'apps/web-platform/lib/auth/x.ts'
assert "gdpr-arm path emits gdpr-gate" \
  'grep -qx "gdpr-gate" <<<"$OUT"' "out=$OUT"
run sloparm --files 'apps/web-platform/components/ui/foo.tsx'
assert "anti-slop+agent-surface arms both fire on a UI path" \
  'grep -qx "anti-slop" <<<"$OUT" && grep -qx "agent-native-reviewer" <<<"$OUT"' "out=$OUT"

# ── ARM 12: comma-separated --files must actually SPLIT ───────────────────────
# SENSITIVE_PATH_RE is ^-anchored, so only the SPLIT second entry can emit
# security-sentinel — the joined line never matches.
run comma --files 'docs/a.md,apps/web-platform/lib/stripe/__fixture__.ts'
assert "comma split is observable (anchored arm on the second entry)" \
  'grep -qx "security-sentinel" <<<"$OUT"' "out=$OUT"

# ── ARM 13: --finding-seats vocabulary normalization ─────────────────────────
# Canonical ids and workflow dimension keys both reduce to leaf names; a forged
# glob token is never pathname-expanded.
run vocab --files 'docs/guide.md' --finding-seats 'soleur:engineering:review:security-sentinel,git-history,code-quality'
assert "canonical id normalizes to leaf" \
  'grep -qx "security-sentinel" <<<"$OUT"' "out=$OUT"
assert "dimension keys normalize to leaves" \
  'grep -qx "git-history-analyzer" <<<"$OUT" && grep -qx "code-quality-analyst" <<<"$OUT"' "out=$OUT"
run dupfs --files 'docs/guide.md' --finding-seats 'security-sentinel,security-sentinel'
assert "duplicate finding-seat dedupes to one line" \
  '[[ "$(grep -c "^security-sentinel$" <<<"$OUT")" -eq 1 ]]' "out=$OUT"
run glob --files '' --finding-seats '*'
assert "a forged glob token cannot expand or reach stdout" \
  '[[ "$RC" -eq 0 && -z "$OUT" ]]' "rc=$RC out=$OUT err=$ERR"
# Discriminating: with `set -f` removed, '*' pathname-expands and stderr shows
# the expanded filenames instead of the literal token.
assert "forged glob is reported literally (set -f holds)" \
  'grep -q "unknown-seat: \*" <<<"$ERR"' "err=$ERR"

# ── ARM 14: whitespace-only and CRLF file entries are normalized ──────────────
run blank --files $'  \n\t\n'
assert "whitespace-only --files behaves like empty (no floor, no seats)" \
  '[[ "$RC" -eq 0 && -z "$OUT" ]]' "rc=$RC out=$OUT err=$ERR"
# Discriminating: a leading-whitespace path only matches the ^-anchored
# sensitive arm after the leading-trim — removing the trim reds this arm.
run wsanchored --files ' apps/web-platform/lib/stripe/__fixture__.ts'
assert "leading-whitespace path still matches the anchored sensitive arm" \
  'grep -qx "security-sentinel" <<<"$OUT"' "out=$OUT"
# Discriminating: git quote-paths a filename containing spaces; the wrapping
# quote would defeat the ^-anchored sensitive arm without the strip.
run quoted --files '"apps/web-platform/lib/stripe/__fixture__.ts"'
assert "quote-pathed entry still matches the anchored sensitive arm" \
  'grep -qx "security-sentinel" <<<"$OUT"' "out=$OUT"
run crlf --files $'scripts/lib/foo.ts\r'
assert "CR-trailing path still matches the source arm" \
  'grep -qx "code-quality-analyst" <<<"$OUT"' "out=$OUT"

# ── Accounting conservation (ADR-193 #3) — reported directly, never via verdict helpers ──
if [[ $((passes + fails)) -ne "$CASES" ]]; then
  printf '\n[FATAL] accounting: passes+fails (%d) != CASES (%d).\n' \
    "$((passes + fails))" "$CASES" >&2
  printf '\n=== fix-round-seats: %d passed, %d failed (%d assertions) ===\n\n' \
    "$passes" "$fails" "$CASES" >&2
  exit 1
fi

# ── Anti-vacuity floor (ADR-193 #1) — reads the INDEPENDENT counter ───────────
FIXSEATS_MIN_ASSERTIONS=36
if (( CASES < FIXSEATS_MIN_ASSERTIONS )); then
  printf '\n[FATAL] anti-vacuity floor: only %d assertion(s) ran, expected >= %d.\n' \
    "$CASES" "$FIXSEATS_MIN_ASSERTIONS" >&2
  printf '\n=== fix-round-seats: %d passed, %d failed (%d assertions) ===\n\n' \
    "$passes" "$fails" "$CASES" >&2
  exit 1
fi

printf '\n=== fix-round-seats: %d passed, %d failed (%d assertions) ===\n\n' \
  "$passes" "$fails" "$CASES"
[[ "$fails" -eq 0 ]]
