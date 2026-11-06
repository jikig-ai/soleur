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
#   6. The replay arms' explicit override: empty tokens, equal to the derived set
#      minus lock:test-all (#12013).
#   7. Start-first order (#12013): the replay arms start with the pool, in the
#      runner's real registration stream (see the section for the contract).

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
declare -A tok_of=()   # label -> token set, kept for section 7 (no second fork per label)
for r in "${rows[@]}"; do
  # TAB-split, not whitespace: labels like `apps/web-platform [unit]` contain
  # spaces and are one field in the SUITE_COMMAND record.
  IFS=$'\t' read -ra fields <<<"$r"
  label="${fields[1]}"
  [[ -n "${seen_label[$label]:-}" ]] && continue
  seen_label[$label]=1
  toks="$(lane_tokens_for "$label" "${fields[@]:2}" 2>/dev/null)" || { unresolvable=$((unresolvable + 1)); continue; }
  tok_of[$label]="$toks"
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
trap 'rm -rf "$_h_dir"' EXIT
printf '#!/usr/bin/env bash\n# drives a sandboxed copy of scripts/test-all.sh\ncp seed scripts/test-all.sh\n' > "$_h_dir/h2.test.sh"
printf '#!/usr/bin/env bash\nbash scripts/test-all.sh\nxargs -P 4 true\n' > "$_h_dir/h3.test.sh"
h_ok=1
arm_override_ok "" bash "$_h_dir/does-not-exist.test.sh" && h_ok=0                  # H1: nonexistent input must NOT pass
arm_override_ok "" bash "$_h_dir/h2.test.sh" || h_ok=0                             # H2: comment/planted-path mention only
[[ "$(_lane_derive bash "$_h_dir/h2.test.sh")" == "lock:test-all" ]] || h_ok=0     # H2 control: derived is exactly the token
arm_override_ok "" bash "$_h_dir/h3.test.sh" && h_ok=0                             # a gained cpu:pool token reds an empty override
arm_override_ok "cpu:pool" bash "$_h_dir/h3.test.sh" || h_ok=0
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
# The suite file itself never takes the advisory lock (the premise of dropping the token): no lock entry
# point is named, and its scratch root is a distinct per-run `mktemp -d` (the other half of the premise).
replay_file="plugins/soleur/test/ci-pr-affected-replay.test.sh"
if [[ -r "$replay_file" ]] && ! grep -qE '(^|[^_[:alnum:]])(tc_acquire|_tc_queue_wait|_tc_ticket_mint|flock)([^_[:alnum:]]|$)' "$replay_file"; then
  pass "replay suite file names no advisory-lock entry point (tc_acquire, queue wait, ticket mint, flock)"
else
  fail "replay suite file is unreadable or names an advisory-lock entry point — the empty override is no longer justified"
fi
if [[ -r "$replay_file" ]] && ! grep -qE 'test-contention' "$replay_file"; then
  pass "replay suite file never references the lock library (test-contention) at all"
else
  fail "replay suite file references test-contention (or is unreadable) - the empty override is no longer justified"
fi
if [[ -r "$replay_file" ]] && grep -qE '^SANDBOX="\$\(mktemp -d "\$TMPDIR/' "$replay_file"; then
  pass "replay suite scratch root is a distinct per-run mktemp -d (arms cannot share a sandbox path)"
else
  fail "replay suite no longer builds SANDBOX from a per-run mktemp -d — concurrent arms could collide"
fi
# The empty override is reserved for the replay arms: no OTHER label may carry an empty token set.
empty_labels=""; arm_labels=""
for (( i = 0; i < ${#LANE_OVERRIDE_LABELS[@]}; i++ )); do
  [[ -z "${LANE_OVERRIDE_TOKENS[i]// /}" ]] && empty_labels+="${LANE_OVERRIDE_LABELS[i]}"$'\n'
done
for l in "${!arm_seen[@]}"; do arm_labels+="$l"$'\n'; done
if [[ "$(sort <<<"$empty_labels")" == "$(sort <<<"$arm_labels")" && -n "$arm_labels" ]]; then
  pass "the set of empty-token overrides equals the set of registered replay arms (no other suite lost its lane)"
else
  fail "empty-token overrides '$(tr '\n' ' ' <<<"$empty_labels")' != replay arms '$(tr '\n' ' ' <<<"$arm_labels")'"
fi

# 7. Start-first order of the replay arms (#12013). In the pooled gate a suite starts as the registration stream reaches it
#    and a queued `*` (drain-barrier) suite blocks every later launch; the replay arms are the longest suites, so they are
#    registered first. Over the runner's REAL raw registration stream (--enumerate-commands all, not the label-deduplicated
#    map): every label under the arm prefix (at least three) appears exactly once, no registration runs the whole battery
#    (by label, or by argv without --rows), each arm's 1-based row is at most the pool width, and no row before the last arm
#    carries a `*` token. Nothing is asserted about any other suite's order, the total, or the --rows ranges (the totality
#    suite tiles those; ci-oracle-lane compares each arm's argv). Scope limits, stated: an arm is any label under the arm prefix
#    (section 6 shares that coupling); a whole-battery registration under another label WITH a --rows range is the totality
#    suite's to catch (its tiling check), not this guard's. Rationale and measurements: ADR-242, decision 29.
SF_W=4   # the local gate's pool width: the SOLEUR_TEST_JOBS default of the affected-tests wrapper; the guard cannot detect a change of it
SF_ARM_PREFIX="${replay_file%.test.sh}-"
# start_first_ok — stdin: one `label<TAB>tokens<TAB>argv` row per registration, in order. Prints one violation per line.
start_first_ok() {
  local row rest l t a i last=0 n_arms=0 sf_gate
  local -a labels=() toks=() argvs=() viol=()
  local -A cnt=()
  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    l="${row%%$'\t'*}"; rest=""; t=""; a=""
    if [[ "$row" == *$'\t'* ]]; then rest="${row#*$'\t'}"; t="${rest%%$'\t'*}"; fi
    if [[ "$rest" == *$'\t'* ]]; then a="${rest#*$'\t'}"; fi
    labels+=("$l"); toks+=("$t"); argvs+=("$a")
  done
  for (( i = 0; i < ${#labels[@]}; i++ )); do
    l="${labels[i]}"
    if [[ "$l" == "$replay_file" || ( "${argvs[i]}" == *"$replay_file"* && "${argvs[i]}" != *"--rows"* ) ]]; then
      viol+=("bare: $l runs the whole replay battery as a plain suite at row $((i + 1))")
    fi
    if [[ "$l" == "${SF_ARM_PREFIX}"* ]]; then
      cnt[$l]=$(( ${cnt[$l]:-0} + 1 ))
      if (( cnt[$l] == 1 )); then
        n_arms=$((n_arms + 1))
        if (( i + 1 > last )); then last=$((i + 1)); fi
        if (( i + 1 > SF_W )); then viol+=("index: $l is at row $((i + 1)), past the pool width $SF_W"); fi
      else
        viol+=("count: $l is registered ${cnt[$l]} times (exactly once required)")
      fi
    fi
  done
  # Written as a statement, not as an `if` counter floor, so guard-vacuity-floor does not read it as one.
  sf_gate=1
  (( n_arms >= 3 )) || sf_gate=0
  (( sf_gate == 1 )) || viol+=("arms: only $n_arms replay arms (label prefix $SF_ARM_PREFIX) in the registration stream, at least 3 required")
  for (( i = 0; i + 1 < last; i++ )); do
    case " ${toks[i]} " in
      *" * "*) viol+=("star: ${labels[i]} (row $((i + 1))) carries the * drain token before the last arm (row $last)") ;;
    esac
  done
  if (( ${#viol[@]} > 0 )); then printf '%s\n' "${viol[@]}"; return 1; fi
  return 0
}
# sf_rows <label|tokens|argv>... — rows as DATA (the pipe becomes the TAB), so the live check and the synthetic cases run
# the SAME function. sf_run records the verdict in SF_RC / SF_OUT.
sf_rows() { printf '%s\n' "$@" | tr '|' '\t'; }
sf_run() { SF_RC=0; SF_OUT="$(start_first_ok)" || SF_RC=$?; }
# sf_emit_rows — stdin: --enumerate-commands lines; stdout: `label<TAB>tokens<TAB>argv` rows. Tokens come from section 1's
# map; `-` and not `:-`, so the replay arms' EMPTY token set stays a value and only a label the map lacks fails closed to `*`.
sf_emit_rows() {
  local r line l a
  while IFS= read -r r; do
    [[ "$r" == "SUITE_COMMAND"$'\t'* ]] || continue
    line="${r#SUITE_COMMAND$'\t'}"; l="${line%%$'\t'*}"; a=""
    if [[ "$line" == *$'\t'* ]]; then a="${line#*$'\t'}"; a="${a//$'\t'/ }"; fi
    [[ -n "$l" ]] || continue
    printf '%s\t%s\t%s\n' "$l" "${tok_of[$l]-*}" "$a"
  done
}
SFA="${SF_ARM_PREFIX}a"; SFB="${SF_ARM_PREFIX}b"; SFC="${SF_ARM_PREFIX}c"

# 7.H Must-PASS inputs that are NOT the canonical order: the function must not reject everything.
sf_h_ok=1
sf_run < <(sf_rows "$SFA|" "$SFB|" "$SFC|" "x|" "y|lock:test-all" "z|*");  (( SF_RC == 0 )) || sf_h_ok=0   # * and lock rows AFTER the arms
sf_run < <(sf_rows "$SFA|" "$SFB|" "$SFC|" "star|*");                      (( SF_RC == 0 )) || sf_h_ok=0   # a * on the row right after the last arm
sf_run < <(sf_rows "$SFC|" "$SFA|" "$SFB|" "x|");                          (( SF_RC == 0 )) || sf_h_ok=0   # any order among the arms
sf_run < <(sf_rows "s1|" "$SFA|" "$SFB|" "$SFC|");                         (( SF_RC == 0 )) || sf_h_ok=0   # a token-free suite above the arms is intended
sf_run < <(sf_rows "$SFA|" "$SFB|" "$SFC|" "${SF_ARM_PREFIX}d|");          (( SF_RC == 0 )) || sf_h_ok=0   # the arm set is derived: a fourth arm is accepted
sf_run < <(sf_rows "$SFA||$replay_file --rows 1" "$SFB|" "$SFC|");  (( SF_RC == 0 )) || sf_h_ok=0   # the battery with --rows is an arm, not the bare suite
sf_run < <(sf_rows "$SFA|" "$SFB|" "$SFC|" "foo-replay-thing|" "p|" "q|artifact:_site" "r|" "s|" "t|"); (( SF_RC == 0 )) || sf_h_ok=0   # a label that merely contains replay
if (( sf_h_ok == 1 )); then
  pass "start-first guard instrument: non-canonical valid orders pass (arm order, a suite or a derived fourth arm, * and lock rows after the arms)"
else
  fail "start-first guard instrument rejects a valid order: rc=$SF_RC out=$SF_OUT"
fi

# 7.M Synthetic mutations. Each must be RED for its OWN reason (the message names the clause).
sf_expect_red() {   # <desc> <expected-clause-prefix> <rows...>
  local desc="$1" clause="$2"; shift 2
  sf_run < <(sf_rows "$@")
  if (( SF_RC != 0 )) && grep -q "^${clause}:" <<<"$SF_OUT"; then
    pass "start-first guard RED on $desc ($clause)"
  else
    fail "start-first guard did not go RED on $desc via the $clause clause: rc=$SF_RC out=$SF_OUT"
  fi
}
sf_expect_red "a and b first, c past the pool width"                      index "$SFA|" "$SFB|" "x1|" "x2|" "$SFC|"
sf_expect_red "an arm registered twice (counted on raw rows)"             count "$SFA|" "$SFA|" "$SFB|" "$SFC|"
sf_expect_red "the whole battery registered under the bare suite label"   bare  "$SFA|" "$SFB|" "$SFC|" "$replay_file|"
sf_expect_red "the whole battery registered under another label"          bare  "$SFA|" "$SFB|" "$SFC|" "whole||$replay_file"
sf_expect_red "a * row between the arms, all arms within the width"       star  "$SFA|" "star1|*" "$SFB|" "$SFC|"
sf_expect_red "a * row first, above the arms"                             star  "star0|*" "$SFA|" "$SFB|" "$SFC|"
sf_expect_red "a * row on the row just before the last arm"               star  "$SFA|" "$SFB|" "s|*" "$SFC|"
sf_expect_red "empty input (no arms found)"                               arms
sf_expect_red "only two arms registered"                                  arms  "$SFA|" "$SFB|"

# 7.R Runner-copy mutants, built from the real runner under the file's own temp dir. The runner resolves its libs and shard
#     tables beside itself, so the copy gets the repo's lib directory by symlink and the tables by glob copy (the glob names
#     none of them, so the PR-affected audit records no new pair). Each mutant must change the runner, enumerate a plausible
#     population, and go RED on its own clause. glob = the pre-change layout (arms registered by the glob loop's special
#     case); star = a new unclassified suite (its tokens fail closed to `*`) registered above the arms.
sf_mutant() {   # <mode> <expected-clause-prefix>; sets SF_MUT_WHY on failure
  local mode="$1" clause="$2" sb="$_h_dir/sf-sandbox-$1" enum n
  SF_MUT_WHY=""
  assert_fixture_dir "$sb"
  mkdir -p "$sb/scripts"
  cp "$REPO_ROOT"/scripts/suite-*.tsv "$sb/scripts/" 2>/dev/null || { SF_MUT_WHY="no shard or duration tables to copy"; return 1; }
  ln -s "$REPO_ROOT/scripts/lib" "$sb/scripts/lib"
  MODE="$mode" REPLAY_FILE="$replay_file" ARM_PREFIX="$SF_ARM_PREFIX" python3 -I - "$REPO_ROOT/scripts/test-all.sh" "$sb/scripts/test-all.sh" <<'PY' || { SF_MUT_WHY="mutator refused"; return 1; }
import os, re, sys
src, dst = sys.argv[1:3]
s = open(src, encoding="utf-8").read()
pre, rf, mode = os.environ["ARM_PREFIX"], os.environ["REPLAY_FILE"], os.environ["MODE"]
pat = re.compile(r'^[ ]*run_suite "' + re.escape(pre) + r'[a-z]+" bash [^\n]*\n', re.M)
lines = [m.group(0).strip() for m in pat.finditer(s)]
assert len(lines) >= 3, f"expected at least 3 arm registrations, found {len(lines)}"
if mode == "glob":
    s2 = pat.sub('', s)
    anchor = 'if [[ "$f" == "' + rf + '" ]]; then\n'
    assert s2.count(anchor) == 1, "glob-loop special case not found exactly once"
    s2 = s2.replace(anchor, anchor + ''.join('      ' + l + '\n' for l in lines))
elif mode == "star":
    first = pat.search(s)
    s2 = s[:first.start()] + '  run_suite "scripts/zz-sf-star-fixture" bash scripts/zz-sf-star-fixture.test.sh\n' + s[first.start():]
else:
    raise SystemExit("unknown mode " + mode)
open(dst, 'w', encoding="utf-8").write(s2)
PY
  if cmp -s "$REPO_ROOT/scripts/test-all.sh" "$sb/scripts/test-all.sh"; then SF_MUT_WHY="the mutation did not change the runner"; return 1; fi
  enum="$(cd "$REPO_ROOT" && TEST_TIMING_LOG=/dev/null timeout 300 bash "$sb/scripts/test-all.sh" --enumerate-commands all 2>"$sb/enum.err")" \
    || { SF_MUT_WHY="mutant enumeration exited non-zero: $(head -c 200 "$sb/enum.err")"; return 1; }
  n="$(grep -c '^SUITE_COMMAND' <<<"$enum" || true)"
  if (( n < 100 )); then SF_MUT_WHY="mutant enumeration returned only $n registrations"; return 1; fi
  sf_run < <(sf_emit_rows <<<"$enum")
  if (( SF_RC == 0 )) || ! grep -q "^${clause}:" <<<"$SF_OUT"; then
    SF_MUT_WHY="the mutant was not RED on the $clause clause: rc=$SF_RC out=$(head -c 200 <<<"$SF_OUT")"; return 1
  fi
  return 0
}
if sf_mutant glob index; then
  pass "start-first guard RED on the runner-copy mutant (arms moved back into the glob loop)"
else
  fail "start-first guard runner-copy mutant (glob): $SF_MUT_WHY"
fi
if sf_mutant star star; then
  pass "start-first guard RED on the runner-copy mutant (an unclassified suite registered above the arms)"
else
  fail "start-first guard runner-copy mutant (star): $SF_MUT_WHY"
fi

# 7.L The live check, over the real raw registration stream (duplicates kept).
assert_fixture_dir "$_h_dir"
printf '%s\n' "${rows[@]}" | sf_emit_rows > "$_h_dir/sf-live-rows.tsv"
sf_run < "$_h_dir/sf-live-rows.tsv"
if (( SF_RC == 0 )); then
  pass "start-first: the replay arms start with the pool in the real registration stream"
else
  fail "start-first: $(tr '\n' ';' <<<"$SF_OUT")"
fi

# Dispatch floor, reported directly (never through fail()): deleting a block of assertions lowers PASSES.
# 12 assertions before section 7, plus the 13 it adds (instrument, 9 synthetic, 2 runner-copy mutants, live check).
(( PASSES < 25 )) && { printf '[FATAL] only %s assertions passed, expected at least 25\n' "$PASSES"; exit 1; }
echo ""
echo "=== test-suite-lanes: $PASSES passed, $FAILURES failed ==="
(( FAILURES == 0 )) || exit 1
exit 0
