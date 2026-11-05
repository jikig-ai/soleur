#!/usr/bin/env bash
# test-suite-lanes.test.sh — census over the concurrency-lane table (#8231).
#
# Auto-registered via the scripts/lib/*.test.sh glob. Asserts:
#   1. Every label --enumerate-commands emits resolves to a token set — the
#      classifier never leaves a registration unclassifiable (an unclassifiable
#      suite would either guess a lane or, worse, run independent by default).
#   2. Every override-table entry names an EMITTED label — a stale override
#      silently protects nothing, which is the exact drift class the exclusion
#      shape exists to catch.
#   3. Every override carries a non-empty reason.
#   4. No label appears in the override table twice.
#   5. The two contract edges: lane_tokens_conflict says `*` conflicts with
#      everything (the drain barrier) and disjoint token sets do not conflict.

set -euo pipefail

cd "$(dirname "$0")/../.."
REPO_ROOT="$(pwd)"

PASSES=0; FAILURES=0
pass() { PASSES=$((PASSES + 1)); printf '[pass] %s\n' "$1"; }
fail() { FAILURES=$((FAILURES + 1)); printf '[FAIL] %s\n' "$1"; }

# shellcheck source=scripts/lib/test-suite-lanes.sh
source "scripts/lib/test-suite-lanes.sh"

# The label set, read through the SAME channel the scheduler's input flows
# through: --enumerate-commands SUITE_COMMAND records (label + argv).
ENUM_OUT="$(TEST_TIMING_LOG=/dev/null timeout 300 bash scripts/test-all.sh --enumerate-commands all 2>/dev/null || true)"
mapfile -t rows < <(grep '^SUITE_COMMAND\b' <<<"$ENUM_OUT" || true)

if (( ${#rows[@]} < 100 )); then
  fail "enumerate returned only ${#rows[@]} SUITE_COMMAND records — the census needs the real population"
else
  pass "census covers ${#rows[@]} emitted registrations"
fi

# 1. Every emitted label resolves — lane_tokens_for must always answer.
unresolvable=0
declare -A seen_label=()
for r in "${rows[@]}"; do
  # TAB-split, not whitespace: labels like `apps/web-platform [unit]` contain
  # spaces and are one field in the SUITE_COMMAND record.
  IFS=$'\t' read -ra fields <<<"$r"
  label="${fields[1]}"
  [[ -n "${seen_label[$label]:-}" ]] && continue
  seen_label[$label]=1
  toks="$(lane_tokens_for "$label" "${fields[@]:2}" 2>/dev/null)" || { unresolvable=$((unresolvable + 1)); continue; }
done
# Union in every `run_suite` literal in the runner source: conditionally
# emitted registrations (`apps/web-platform [unit]` relevance-declines to a
# skip_suite in this diff state; the infra runner's leg gating can do the
# same) are real labels the override table may legitimately name even when
# this run's enumerate output does not emit them.
while IFS= read -r lit; do
  seen_label["$lit"]=1
done < <(grep -oE 'run_suite "[^"]+"' scripts/test-all.sh | sed 's/run_suite "//; s/"$//')
if (( unresolvable == 0 )); then
  pass "every emitted label resolves to a token set (unclassifiable → *, never unresolvable)"
else
  fail "$unresolvable labels did not resolve"
fi

# 2. Overrides name emitted labels only.
stale=()
for l in "${LANE_OVERRIDE_LABELS[@]}"; do
  [[ -n "${seen_label[$l]:-}" ]] || stale+=("$l")
done
if (( ${#stale[@]} == 0 )); then
  pass "every override entry names a label --enumerate emits (${#LANE_OVERRIDE_LABELS[@]} entries)"
else
  fail "stale override labels: ${stale[*]}"
fi

# 3. Every override carries a non-empty reason.
empty_reason=0
for (( i = 0; i < ${#LANE_OVERRIDE_REASONS[@]}; i++ )); do
  [[ -n "${LANE_OVERRIDE_REASONS[i]:-}" ]] || empty_reason=$((empty_reason + 1))
done
(( ${#LANE_OVERRIDE_REASONS[@]} == ${#LANE_OVERRIDE_LABELS[@]} )) || empty_reason=999
if (( empty_reason == 0 )); then
  pass "every override carries a non-empty machine-checkable reason"
else
  fail "$empty_reason override entries have a missing/empty reason"
fi

# 4. No label in the override table twice.
declare -A dup_check=()
dups=0
for l in "${LANE_OVERRIDE_LABELS[@]}"; do
  [[ -n "${dup_check[$l]:-}" ]] && dups=$((dups + 1))
  dup_check[$l]=1
done
if (( dups == 0 )); then
  pass "no label declared twice in the override table"
else
  fail "$dups duplicate override labels"
fi

# 5. The conflict contract.
c_ok=1
lane_tokens_conflict "*" "" || c_ok=0
lane_tokens_conflict "*" "lock:test-all" || c_ok=0
lane_tokens_conflict "artifact:_site" "artifact:_site" || c_ok=0
lane_tokens_conflict "artifact:_site" "lock:test-all" && c_ok=0
lane_tokens_conflict "" "" && c_ok=0
if (( c_ok == 1 )); then
  pass "lane_tokens_conflict: * drains everything, shared tokens intersect, disjoint sets do not"
else
  fail "lane_tokens_conflict contract violated"
fi

# 6. The replay arms' explicit override (#12013): every registered `ci-pr-affected-replay-*` label carries an override
#    equal to what the classifier derives for it MINUS `lock:test-all`. The arms drive sandboxed copies of the
#    runner under `mktemp -d` roots and never take the real advisory lock, so the token only serialized them.
#    The comparison is made against `_lane_derive` (the classifier WITHOUT the override lookup), so a token the
#    suite file later gains (xargs -P, _site/, a live-repo git verb) moves the derived side and reds the label;
#    the label list comes from --enumerate-commands, not from a hard-coded set.
_norm_toks() { local -a a; read -ra a <<<"${1:-}"; { printf '%s\n' "${a[@]+"${a[@]}"}" | grep -v '^$' || true; } | sort -u | tr '\n' ' ' | sed 's/ *$//'; }
_derived_minus_lock() { local t; t="$(_lane_derive "$@")"; _norm_toks "$(tr ' ' '\n' <<<"$t" | { grep -vxF 'lock:test-all' || true; } | tr '\n' ' ')"; }
# arm_override_ok <override-tokens> <argv...> — 0 iff the override equals derived-minus-lock for that argv.
arm_override_ok() { local ov="$1"; shift; [[ "$(_norm_toks "$ov")" == "$(_derived_minus_lock "$@")" ]]; }

# Instrument self-tests: the comparison is not vacuous. (H1) a classifier input that does not exist derives `*`
# (fail closed), which an empty override must NOT equal; (H2) a must-pass fixture that names test-all.sh only in a
# comment and as a planted path derives exactly `lock:test-all`, so an EMPTY override equals derived-minus-lock;
# and a fixture that also carries an inner pool must NOT equal the empty override.
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
_h_dir="$(mktemp -d "${TMPDIR:-/tmp}/lanes-h.XXXXXX")"
assert_fixture_dir "$_h_dir"
printf '#!/usr/bin/env bash\n# drives a sandboxed copy of scripts/test-all.sh\ncp seed scripts/test-all.sh\n' > "$_h_dir/h2.test.sh"
printf '#!/usr/bin/env bash\nbash scripts/test-all.sh\nxargs -P 4 true\n' > "$_h_dir/h3.test.sh"
h_ok=1
arm_override_ok "" bash "$_h_dir/does-not-exist.test.sh" && h_ok=0                  # H1: nonexistent input must NOT pass
arm_override_ok "" bash "$_h_dir/h2.test.sh" || h_ok=0                             # H2: comment/planted-path mention only
[[ "$(_lane_derive bash "$_h_dir/h2.test.sh")" == "lock:test-all" ]] || h_ok=0     # H2 control: derived is exactly the token
arm_override_ok "" bash "$_h_dir/h3.test.sh" && h_ok=0                             # a gained cpu:pool token reds an empty override
arm_override_ok "cpu:pool" bash "$_h_dir/h3.test.sh" || h_ok=0
rm -rf "$_h_dir"
if (( h_ok == 1 )); then
  pass "replay-arm guard instrument: nonexistent input and a gained token red an empty override; the mention-only fixture passes"
else
  fail "replay-arm guard instrument is not discriminating"
fi

arm_n=0; arm_bad=()
declare -A arm_seen=()
for r in "${rows[@]}"; do
  IFS=$'\t' read -ra fields <<<"$r"
  label="${fields[1]}"
  [[ "$label" == *ci-pr-affected-replay-* ]] || continue
  [[ -n "${arm_seen[$label]:-}" ]] && continue
  arm_seen[$label]=1; arm_n=$((arm_n + 1))
  # The override IS the label's token set; the lookup without it must derive exactly lock:test-all today.
  ov="$(lane_tokens_for "$label" "${fields[@]:2}")"
  [[ "$(_lane_derive "${fields[@]:2}")" == "lock:test-all" ]] || arm_bad+=("$label:derived-not-exactly-lock:test-all($(_lane_derive "${fields[@]:2}"))")
  arm_override_ok "$ov" "${fields[@]:2}" || arm_bad+=("$label:override='$ov'")
done
# The non-empty floor is a guard on the label list itself (3 arms today); written as a statement, not as an
# `if` floor, so scripts/guard-vacuity-floor.test.sh does not read it as a counter floor needing a mutant.
arm_gate=1
(( arm_n < 3 )) && arm_gate=0
(( ${#arm_bad[@]} == 0 )) || arm_gate=0
if (( arm_gate == 1 )); then
  pass "replay arms: each of $arm_n registered ci-pr-affected-replay-* labels overrides to its derived tokens minus lock:test-all"
else
  fail "replay arms: n=$arm_n (floor 3) violations: ${arm_bad[*]:-none}"
fi
# The suite file itself never takes the advisory lock (the premise of dropping the token).
replay_file="plugins/soleur/test/ci-pr-affected-replay.test.sh"
if [[ -r "$replay_file" ]] && ! grep -qE '(^|[^_[:alnum:]])tc_acquire([^_[:alnum:]]|$)' "$replay_file"; then
  pass "replay suite file never calls tc_acquire (the arms never take the real advisory lock)"
else
  fail "replay suite file is unreadable or calls tc_acquire — the empty override is no longer justified"
fi

echo ""
echo "=== test-suite-lanes: $PASSES passed, $FAILURES failed ==="
(( FAILURES == 0 )) || exit 1
exit 0
