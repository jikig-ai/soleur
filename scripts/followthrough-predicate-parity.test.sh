#!/usr/bin/env bash
# followthrough-predicate-parity.test.sh -- ONE differential oracle over every executable
# reader of the `soleur:followthrough` directive (#7490).
#
# WHY THIS EXISTS, AND WHY IT IS NOT A SHARED LIBRARY.
# Four places decide whether a tracker is enrolled, and they CANNOT share code: two are prose
# blocks an agent pastes out of a SKILL.md, one is a hook whose own header records that it is
# inlined deliberately ("no source dependency on a repo file that may move" -- the ADR-178
# failure class), and one is the sweeper. So the copies are held in agreement by a comment
# saying "mirror BOTH places".
#
# That comment does not work, and #7490 is the proof. Its author widened the sweeper's fence
# predicate, mirrored it into two of the three producers, and left the third on the old
# spelling -- shipping, inside the PR titled "make every producer agree with its consumer",
# a create-time gate that ALLOWED four body shapes the sweeper refuses to honour. A fifth copy
# (plugins/soleur/test/ship-followthrough-directive.test.sh) was diff-checking a stale mirror
# against a fixture containing no fence at all, so it passed on every fence property.
#
# The remedy is not deduplication, it is a WALKER: derive the verdict from each reader for a
# table of body shapes and assert they agree with the AUTHORITY. A new copy that drifts reds
# here, whichever copy it is.
#
# THE AUTHORITY IS THE SWEEPER. `scripts/sweep-followthroughs.sh` is what actually runs the
# probe, so it defines "enrolled". A producer that is LOOSER green-lights a tracker that will
# never be honoured (the #7490 defect). A producer that is STRICTER is a false denial on a
# merge gate. Both are findings; the table below asserts EQUALITY, not a direction.
#
# Exit: 0 = every reader agrees with the authority on every shape; 1 = at least one divergence.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWEEPER="$REPO_ROOT/scripts/sweep-followthroughs.sh"
SOAK_HOOK="$REPO_ROOT/.claude/hooks/ship-soak-followthrough-gate.sh"
SHIP_SKILL="$REPO_ROOT/plugins/soleur/skills/ship/SKILL.md"

# --- the AUTHORITY, sourced from the shipped file (never re-implemented here) --------------
# shellcheck disable=SC1090
source "$SWEEPER" >/dev/null 2>&1 || true
if ! declare -F parse_directive >/dev/null; then
  printf '[FATAL] parse_directive did not load from %s -- the oracle has no authority\n' "$SWEEPER" >&2
  exit 1
fi

# VERDICT HELPERS ARE DEFINED **AFTER** THE SOURCE, AND THAT ORDER IS LOAD-BEARING.
# `scripts/sweep-followthroughs.sh` defines its own `fail()`, so sourcing it clobbers any
# same-named helper declared above — the suite then reports through the SUT's logger, its
# counters never move, and the accounting check fires on a suite whose assertions all ran
# fine. Caught here by the instrument self-test below, not by reading; it is the
# "a helper that owns its own verdict" class arriving through a namespace collision.
PASS=0; FAIL=0; ASSERTED=0
FAILURES=()   # append-only; the verdict reads THIS, not a counter a silenced helper can fake
pass() { PASS=$((PASS + 1)); printf '  [ok] %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); FAILURES+=("$1"); printf '  [FAIL] %s\n' "$1" >&2; }
check() { ASSERTED=$((ASSERTED + 1)); if [[ "$1" == "0" ]]; then pass "$2"; else fail "$3"; fi; }

authority_enrolled() {  # 1 = the sweeper would honour this body
  local n; n=$(printf '%s' "$1" | parse_directive | grep -c '^script ' || true)
  [[ "${n:-0}" -ge 1 ]] && echo 1 || echo 0
}

# --- READER: the soak gate's fence-strip + enrolment grep, EXTRACTED from the shipped file --
# Extracted rather than restated: a restatement is a sixth copy and would drift the same way.
soak_strip_awk() {
  # Slice between the CONTENT markers the hook carries, then drop the shell wrapper lines.
  # A shape-anchored slice (on the closing `')`) silently stopped matching the moment the awk
  # gained a `|| printf` fallback — the oracle then compared a truncated program and reported a
  # divergence that did not exist. Content anchors survive edits to the program itself.
  awk '/# parity-extract:begin/{f=1;next} /# parity-extract:end/{f=0} f' "$SOAK_HOOK" \
    | sed -n "/unfenced_body=/,/# fence-strip/p" \
    | sed '1s/.*awk .//; $d'
}
soak_enrol_re() {  # the grep -E pattern the gate uses for the directive anchor
  grep -oE "grep -qE '\^<!--[^']*'" "$SOAK_HOOK" | head -1 | sed "s/^grep -qE '//; s/'\$//"
}
soak_enrolled() {  # 1 = the soak gate would call this body enrolled
  local prog re stripped
  prog="$(soak_strip_awk)"; re="$(soak_enrol_re)"
  # A truncated program is worse than an absent one: it PARSES and answers, so the oracle would
  # report a divergence in the SUT when the fault is in the instrument. Require the program to
  # carry the two constructs that define it before trusting anything it says.
  if [[ -z "$prog" || -z "$re" ]] \
     || ! grep -q 'fence_len' <<<"$prog" || ! grep -q 'print' <<<"$prog"; then
    echo "EXTRACT_FAILED"; return
  fi
  stripped="$(printf '%s' "$1" | awk "$prog")"
  grep -qE "$re" <<<"$stripped" && echo 1 || echo 0
}

# --- READER: the create-time PreToolUse gate, driven END TO END -----------------------------
# It carries its own inlined copy of the fence + column-0 predicate, previously held in
# agreement with the authority only by four hand-written rows. Its verdict maps cleanly onto
# enrolment: the gate ALLOWS (silent, rc 0, no stdout) exactly when it parsed a usable
# directive, and DENIES otherwise -- so `allow == 1` is the same bit `authority_enrolled`
# returns. The sandbox provides the executable `p.sh` every shape's `script=` names, so the
# only thing that can differ between the two readers is the PREDICATE, which is the point.
_CG_HOOK="$REPO_ROOT/.claude/hooks/follow-through-directive-gate.sh"
_CG_TMP="$(mktemp -d)"
trap 'rm -rf "$_CG_TMP"' EXIT
mkdir -p "$_CG_TMP/scripts/followthroughs"
printf '#!/usr/bin/env bash\nexit 0\n' > "$_CG_TMP/scripts/followthroughs/p.sh"
chmod +x "$_CG_TMP/scripts/followthroughs/p.sh"
creategate_enrolled() {
  local bf="$_CG_TMP/body.md"
  printf '%s' "$1" > "$bf"
  local out
  out=$(jq -n --arg cmd "gh issue create --title t --label follow-through --body-file $bf" \
               --arg cwd "$_CG_TMP" \
               '{tool_name:"Bash", tool_input:{command:$cmd}, cwd:$cwd}' \
        | bash "$_CG_HOOK" 2>&1)
  [[ -z "$out" ]] && echo 1 || echo 0
}

# --- READER: the ship SKILL.md §5.5 enrolment bash (prose an agent pastes) -----------------
ship_enrol_re() {
  grep -oE "grep -qE '\^<!--[^']*'" "$SHIP_SKILL" | head -1 | sed "s/^grep -qE '//; s/'\$//"
}

# --- the SHAPE TABLE. Derived by shape, not enumerated by name, so a new spelling is one row.
# Each row: <label>|<printf format>. The expected verdict is never written down -- it is
# whatever the AUTHORITY says, which is the whole point of a differential oracle.
D='<!-- soleur:followthrough script=scripts/followthroughs/p.sh earliest=2020-01-01T00:00:00Z -->'
shapes=(
  "column-0 unfenced|## V\n\n$D\n"
  "no directive at all|## V\n\nnothing here\n"
  "3-backtick fence|## V\n\n\`\`\`html\n$D\n\`\`\`\n"
  "tilde fence|## V\n\n~~~html\n$D\n~~~\n"
  "1-space-indented fence|## V\n\n \`\`\`html\n$D\n \`\`\`\n"
  "3-space-indented fence|## V\n\n   \`\`\`html\n$D\n   \`\`\`\n"
  "4-space indent (NOT a fence)|## V\n\n    \`\`\`html\n$D\n    \`\`\`\n"
  "4-backtick wrapping a 3-backtick example|## V\n\n\`\`\`\`md\n\`\`\`\nex\n\`\`\`\n\`\`\`\`\n\n$D\n"
  "fenced example BESIDE a real directive|## V\n\n\`\`\`html\n$D\n\`\`\`\n\n$D\n"
  "unbalanced fence before the directive|## V\n\n\`\`\`html\n$D\n"
  "directive indented 1 space|## V\n\n $D\n"
  "directive indented 2 spaces|## V\n\n  $D\n"
  "zero spaces after <!--|## V\n\n<!--soleur:followthrough script=scripts/followthroughs/p.sh earliest=2020-01-01T00:00:00Z -->\n"
  "three spaces after <!--|## V\n\n<!--   soleur:followthrough script=scripts/followthroughs/p.sh earliest=2020-01-01T00:00:00Z -->\n"
  "CRLF unfenced|## V\r\n\r\n$D\r\n"
  "CRLF fenced|## V\r\n\r\n\`\`\`html\r\n$D\r\n\`\`\`\r\n"
  # The CANONICAL emitted shape. `plugins/soleur/skills/ship/SKILL.md` and the golden fixture
  # `plugins/soleur/test/fixtures/followthrough-directive/expected-issue-body.md` both emit the
  # directive over FOUR lines; every row above this one is single-line, so the shape this repo
  # actually produces was unrepresented in its own oracle.
  "canonical MULTI-LINE directive|## V\n\n<!-- soleur:followthrough\n  script=scripts/followthroughs/p.sh\n  earliest=2020-01-01T00:00:00Z\n-->\n"
  # ... and the same body with a stray fence delimiter INSIDE it. See the absolute assertions
  # below: parity alone is not enough here, because all three readers regressing together
  # would keep this row green.
  "MULTI-LINE directive interrupted by a stray fence|## V\n\n<!-- soleur:followthrough\n  script=scripts/followthroughs/p.sh\n\`\`\`\n  earliest=2020-01-01T00:00:00Z\n-->\n"
)

# --- ABSOLUTE expectations, for the rows where parity alone is not a property --------------
# A differential oracle is satisfied when every reader is wrong in the same way, and the hooks
# carry copies whose own comments instruct the next author to "mirror BOTH places" -- i.e. the
# mirrored change is the LIKELY change. Measured 2026-09-18: widening all three predicates to
# `/^[ ]*(```|~~~)/` (the mirrored widening) left all four suites green, while the 4-space row
# is exactly the far side of CommonMark`s 0-3-space bound that G4-9 pins only the near side of.
# So these rows assert what the AUTHORITY must say, not merely that the readers echo it.
declare -A absolute=(
  ["column-0 unfenced"]=1
  ["no directive at all"]=0
  ["3-backtick fence"]=0
  ["4-space indent (NOT a fence)"]=1
  ["fenced example BESIDE a real directive"]=1
  ["canonical MULTI-LINE directive"]=1
  ["MULTI-LINE directive interrupted by a stray fence"]=1
)

printf 'followthrough-predicate-parity: %d shapes x 3 readers, authority = parse_directive\n\n' "${#shapes[@]}"

ship_re="$(ship_enrol_re)"
check "$([[ -n "$ship_re" ]] && echo 0 || echo 1)" \
  "instrument: the ship SKILL.md enrolment regex extracted ('$ship_re')" \
  "instrument: could NOT extract the ship SKILL.md enrolment regex -- every ship row below would be vacuous"

for row in "${shapes[@]}"; do
  label="${row%%|*}"; fmt="${row#*|}"
  # shellcheck disable=SC2059
  body="$(printf "$fmt")"
  a="$(authority_enrolled "$body")"
  if [[ -n "${absolute[$label]:-}" ]]; then
    exp="${absolute[$label]}"
    check "$([[ "$a" == "$exp" ]] && echo 0 || echo 1)" \
      "authority is ABSOLUTELY correct on: $label (enrolled=$exp)" \
      "authority is WRONG on: $label -- expected enrolled=$exp, got $a (a mirrored widening would keep every parity row green)"
  fi
  s="$(soak_enrolled "$body")"
  check "$([[ "$s" == "$a" ]] && echo 0 || echo 1)" \
    "soak gate agrees with the authority on: $label (both $a)" \
    "soak gate DIVERGES on: $label -- authority=$a soak=$s"
  g="$(creategate_enrolled "$body")"
  check "$([[ "$g" == "$a" ]] && echo 0 || echo 1)" \
    "create-time gate agrees with the authority on: $label (both $a)" \
    "create-time gate DIVERGES on: $label -- authority=$a gate=$g"
  if [[ -n "$ship_re" ]]; then
    prog="$(soak_strip_awk)"
    st="$(printf '%s' "$body" | awk "$prog")"
    sh=$(grep -qE "$ship_re" <<<"$st" && echo 1 || echo 0)
    check "$([[ "$sh" == "$a" ]] && echo 0 || echo 1)" \
      "ship SKILL.md §5.5 agrees with the authority on: $label (both $a)" \
      "ship SKILL.md §5.5 DIVERGES on: $label -- authority=$a ship=$sh"
  fi
done

# --- FIELD-LEVEL assertions: enrolment is not the property that broke ----------------------
# `authority_enrolled` answers "is there a directive", which is a bit the defect below does NOT
# flip. A stray fence between `script=` and `earliest=` in the canonical MULTI-LINE body leaves
# `script=` intact -- it is above the fence -- so the body stays "enrolled" while `earliest=` is
# swallowed. `run_one` then renders it through `${earliest:-now}`, `iso_to_epoch ""` returns 0,
# the soak gate is skipped ENTIRELY, and the tracker closes PASS on day 0. Measured 2026-09-18
# against the shipped sweeper with a matched control: the identical body minus the stray fence
# line correctly reported `earliest=2099-01-01T00:00:00Z not yet reached -- skipping`.
# So assert the FIELD. Every row above would stay green through that whole failure.
_ml_clean="$(printf '## V\n\n<!-- soleur:followthrough\n  script=scripts/followthroughs/p.sh\n  earliest=2020-01-01T00:00:00Z\n-->\n')"
_ml_fenced="$(printf '## V\n\n<!-- soleur:followthrough\n  script=scripts/followthroughs/p.sh\n```\n  earliest=2020-01-01T00:00:00Z\n-->\n')"
for _row in "canonical MULTI-LINE:$_ml_clean" "MULTI-LINE interrupted by a stray fence:$_ml_fenced"; do
  _lbl="${_row%%:*}"; _bdy="${_row#*:}"
  _e="$(printf '%s' "$_bdy" | parse_directive | sed -n 's/^earliest //p' | head -1)"
  check "$([[ "$_e" == "2020-01-01T00:00:00Z" ]] && echo 0 || echo 1)" \
    "authority extracts earliest= from the $_lbl body ('$_e')" \
    "authority LOST earliest= from the $_lbl body (got '$_e') -- run_one would render \${earliest:-now}, skip the soak gate and close the tracker on day 0"
  _s="$(printf '%s' "$_bdy" | parse_directive | sed -n 's/^script //p' | head -1)"
  check "$([[ "$_s" == "scripts/followthroughs/p.sh" ]] && echo 0 || echo 1)" \
    "authority extracts script= from the $_lbl body ('$_s')" \
    "authority LOST script= from the $_lbl body (got '$_s')"
done

# --- the two prose copies must remain BYTE-IDENTICAL to the hook's regex -------------------
soak_re="$(soak_enrol_re)"
check "$([[ -n "$soak_re" && "$soak_re" == "$ship_re" ]] && echo 0 || echo 1)" \
  "the hook and the ship SKILL.md carry the SAME enrolment regex ('$soak_re')" \
  "the hook ('$soak_re') and the ship SKILL.md ('$ship_re') carry DIFFERENT enrolment regexes"

# --- the create-time hook is driven end to end by its own suite; assert it is REGISTERED ----
# The create-time gate's suite is auto-globbed by the hook-suite runner rather than named in
# test-all.sh, so assert the FILE exists and is executable — a suite that is neither is a suite
# whose rows never run, whichever runner claims it.
_dg="$REPO_ROOT/.claude/hooks/follow-through-directive-gate.test.sh"
check "$([[ -x "$_dg" ]] && echo 0 || echo 1)" \
  "the create-time gate's suite exists and is executable" \
  "the create-time gate's suite is missing or non-executable at $_dg"

# --- instrument self-test: both verdict helpers must still be able to move their counters ---
# INSTRUMENT SELF-TEST. Drives BOTH verdict helpers once and requires all three of their
# observables to move — the counters AND the append-only ledger the verdict reads. A floor that
# counts assertions cannot see a `fail()` rewritten to increment `passes`; this can.
_p=$PASS _f=$FAIL _a=$ASSERTED _n=${#FAILURES[@]}
if (( _n > 0 )); then _saved=("${FAILURES[@]}"); else _saved=(); fi
pass "self-test probe"; fail "self-test probe (expected; unwound below)"
if (( PASS != _p + 1 || FAIL != _f + 1 || ${#FAILURES[@]} != _n + 1 )); then
  printf '[FATAL] instrument self-test: a verdict helper did not move all of its observables\n' >&2
  exit 1
fi
PASS=$_p; FAIL=$_f; ASSERTED=$_a
if (( _n > 0 )); then FAILURES=("${_saved[@]}"); else FAILURES=(); fi

# --- accounting + floor, emitted DIRECTLY (never through the helpers they police) ----------
if (( PASS + FAIL != ASSERTED )); then
  printf '[FATAL] accounting: PASS+FAIL (%d) != ASSERTED (%d)\n' "$((PASS + FAIL))" "$ASSERTED" >&2
  exit 1
fi
MIN_ASSERTIONS=68
if (( ASSERTED < MIN_ASSERTIONS )); then
  printf '[FATAL] only %d assertions ran; floor is %d -- the shape table was gutted\n' "$ASSERTED" "$MIN_ASSERTIONS" >&2
  exit 1
fi

printf '\n=== followthrough-predicate-parity: %d passed, %d failed (%d asserted, floor %d) ===\n' \
  "$PASS" "$FAIL" "$ASSERTED" "$MIN_ASSERTIONS"
# The verdict reads the append-only ledger, not a counter: silencing fail() by redirecting its
# increment leaves FAILURES populated and the run still reds.
(( ${#FAILURES[@]} == 0 )) || { printf 'FAILED: %d divergence(s)\n' "${#FAILURES[@]}" >&2; exit 1; }
exit 0
