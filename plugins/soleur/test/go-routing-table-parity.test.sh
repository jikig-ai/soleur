#!/usr/bin/env bash
# /soleur:go routing-table parity.
#
# WHY THIS EXISTS. The `go-routing` block in plugins/soleur/commands/go.md is the table a human
# reads; `GO_SKILL_ROUTES` in plugins/soleur/lib/workflow-fidelity.ts is what actually dispatches a
# skill row; and plugins/soleur/skills/eval-harness/enums/go-routes.json is the closed vocabulary the
# eval gate scores against. Three artifacts, one fact, and until this suite existed nothing compared
# them.
#
# Measured, on the PR that added this file (#8289): two routing rows were added to the table and to
# neither other artifact. `resolveGoSkillRoute` is `GO_SKILL_ROUTES[label] ?? GO_SKILL_ROUTES.default`,
# so both new labels resolved silently to `brainstorm` — no throw, no warning — and the generated
# skill-arm prompt presented the two rows and then forbade emitting them, because its closing token
# list is rendered from the enum. A third row, `drain-prs`, had been adrift since #8287 cut the census
# guard specified to catch exactly this (that plan is archived at
# knowledge-base/project/plans/archive/20260918-181155-*-plan.md); that pre-existing drift is what let
# two more rows drift in behind it.
#
# THE DIRECTION IS DELIBERATE: table rows are the POPULATION. Every parity test in this repo iterates
# the dispatch map and asks whether each entry works, which is the opposite direction from the one
# that breaks — a row added to go.md alone is invisible to it.
#
# EACH ROW DECLARES ITS OWN TARGET, so this suite asserts the target rather than mere membership. The
# `Routes To` cell's first backticked token is either `soleur:<skill>` (a skill row, which must be the
# value `GO_SKILL_ROUTES` dispatches for that label) or `soleur:<domain>:<agent>` (an agent row via
# Task spawn — `clo-attestation` and `legal-threshold` are both this shape, which is why they have no
# skill-map entry and must not be required to have one; their target is asserted as a real agent file
# instead). Reading the kind off the row is what lets one suite cover both without a second map, and
# without an exported map that nothing consumes.
#
# Anti-vacuity: the population is derived from the block, never hand-listed, and floors require each
# derivation to have found members — a parity assertion over the empty set reports clean while
# checking nothing, which is this repo's most-documented failure shape.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
GO_MD="$ROOT/plugins/soleur/commands/go.md"
FIDELITY="$ROOT/plugins/soleur/lib/workflow-fidelity.ts"
ENUM="$ROOT/plugins/soleur/skills/eval-harness/enums/go-routes.json"

for f in "$GO_MD" "$FIDELITY" "$ENUM"; do
  [[ -r "$f" ]] || { printf 'FATAL: cannot read %s\n' "$f" >&2; exit 2; }
done

passes=0; fails=0; asserted=0
VERDICT_LOG="$(mktemp -t go-parity.XXXXXXXX.log)" || { printf 'FATAL: no scratch\n' >&2; exit 2; }
trap 'rm -f "$VERDICT_LOG"' EXIT
ok()  { printf '  PASS: %s\n' "$1"; printf 'PASS\n' >> "$VERDICT_LOG"; passes=$((passes + 1)); }
bad() { printf '  FAIL: %s\n' "$1" >&2; printf 'FAIL\n' >> "$VERDICT_LOG"; fails=$((fails + 1)); }
ck()  { asserted=$((asserted + 1)); }

# --- derive the sets -----------------------------------------------------------------------------
# Rows are scoped to the eval-gated block, so a prose table elsewhere in go.md cannot contribute one.
# Each row is emitted as `<intent>\t<first backticked token of the Routes To cell>`.
mapfile -t ROWS < <(
  awk -F'|' '
    /<!-- eval-gate:block:go-routing:start -->/{f=1; next}
    /<!-- eval-gate:block:go-routing:end -->/{f=0}
    f && $2 ~ /^ [a-z][a-z-]* $/ {
      intent=$2; gsub(/ /, "", intent)
      target=""
      if (match($4, /`[^`]+`/)) { target=substr($4, RSTART+1, RLENGTH-2) }
      print intent "\t" target
    }' "$GO_MD" | grep -v '^$' || true
)
# `| grep -v` prunes the phantom empty element that `"\n".join([])` yields for an empty array — a
# blank line becomes a one-element array holding "", so a degenerate enum would otherwise be
# reported as ONE token and a "" would be asserted against the rows.
mapfile -t ENUM_TOKENS < <(python3 -c '
import json,sys
for t in json.load(open(sys.argv[1])):
    print(t)' "$ENUM" | grep -v '^$' || true)
# GO_SKILL_ROUTES only — GO_AGENT_ROUTES does not exist, and inventing one that nothing dispatches
# through would be a dead export. Agent rows are checked against the agent tree instead.
mapfile -t SKILL_MAP < <(
  awk '/^export const GO_SKILL_ROUTES/{f=1; next}
       f && /^};/{f=0}
       f && match($0, /^[[:space:]]*"?[A-Za-z][A-Za-z0-9-]*"?[[:space:]]*:[[:space:]]*"[^"]+"/) {
         line=$0
         sub(/^[[:space:]]*/, "", line); sub(/,?[[:space:]]*$/, "", line)
         split(line, kv, ":")
         k=kv[1]; gsub(/"/, "", k)
         v=kv[2]; gsub(/^[[:space:]]*"|"[[:space:]]*$/, "", v)
         print k "\t" v
       }' "$FIDELITY" | grep -v '^$' || true
)

# --- ANTI-VACUITY FLOORS -------------------------------------------------------------------------
# Derived, not hand-summed. Recipes:
#   awk -F'|' between the two eval-gate markers in go.md, counting cells matching / [a-z-]+ /
#   python3 -c 'import json;print(len(json.load(open(ENUM))))'
#   the literal entry count of GO_SKILL_ROUTES
# Each reports directly with printf + exit 1, never through ok()/bad() (ADR-193).
MIN_ROWS=9
if [[ "${#ROWS[@]}" -lt "$MIN_ROWS" ]]; then
  printf '\nFATAL: the go-routing block yielded %s row(s), floor is %s — the extraction matched (almost) nothing, which is not a parity result.\n' \
    "${#ROWS[@]}" "$MIN_ROWS" >&2
  exit 1
fi
MIN_ENUM=9
if [[ "${#ENUM_TOKENS[@]}" -lt "$MIN_ENUM" ]]; then
  printf '\nFATAL: go-routes.json yielded %s token(s), floor is %s.\n' "${#ENUM_TOKENS[@]}" "$MIN_ENUM" >&2
  exit 1
fi
MIN_SKILL_MAP=7
if [[ "${#SKILL_MAP[@]}" -lt "$MIN_SKILL_MAP" ]]; then
  printf '\nFATAL: GO_SKILL_ROUTES yielded %s entr(y|ies), floor is %s — the key/value extraction broke, so every skill-row target below would pass vacuously.\n' \
    "${#SKILL_MAP[@]}" "$MIN_SKILL_MAP" >&2
  exit 1
fi
# A row with an empty target means the Routes To cell carried no backticked skill/agent — the
# extraction is then reporting on a table shape it does not understand.
_untargeted=0
for r in "${ROWS[@]}"; do [[ -n "${r#*$'\t'}" ]] || _untargeted=$((_untargeted + 1)); done
if [[ "$_untargeted" -gt 0 ]]; then
  printf '\nFATAL: %s row(s) yielded no `Routes To` target — the table shape changed and this suite no longer reads it.\n' \
    "$_untargeted" >&2
  exit 1
fi

in_list() { local needle="$1"; shift; local x; for x in "$@"; do [[ "$x" == "$needle" ]] && return 0; done; return 1; }
map_get() { local k="$1" e; for e in "${SKILL_MAP[@]}"; do [[ "${e%%$'\t'*}" == "$k" ]] && { printf '%s' "${e#*$'\t'}"; return 0; }; done; return 1; }

# --- the parity assertions ------------------------------------------------------------------------
for r in "${ROWS[@]}"; do
  intent="${r%%$'\t'*}"
  target="${r#*$'\t'}"

  ck
  if in_list "$intent" "${ENUM_TOKENS[@]}"; then
    ok "row '$intent' is a member of enums/go-routes.json"
  else
    bad "row '$intent' is NOT in enums/go-routes.json — the eval gate scores it as an out-of-enum label and the generated prompt's closing token list forbids emitting it"
  fi

  # Kind is read off the row: three colon-separated parts is an agent (soleur:<domain>:<agent>),
  # two is a skill (soleur:<skill>).
  case "$target" in
    soleur:*:*)
      agent_leaf="${target##*:}"
      ck
      if [[ -n "$(find "$ROOT/plugins/soleur/agents" -type f -name "${agent_leaf}.md" -print -quit 2>/dev/null)" ]]; then
        ok "agent row '$intent' targets agent '$target', which exists in the agent tree"
      else
        bad "agent row '$intent' targets '$target' but no ${agent_leaf}.md exists under plugins/soleur/agents — the Task spawn names an agent that is not there"
      fi
      ;;
    soleur:*)
      want="${target#soleur:}"
      ck
      if got="$(map_get "$intent")"; then
        if [[ "$got" == "$want" ]]; then
          ok "skill row '$intent' dispatches to '$got', matching its Routes To cell"
        else
          bad "skill row '$intent' says it routes to '$want' but GO_SKILL_ROUTES dispatches '$got' — the table and the dispatcher disagree about the destination"
        fi
      else
        bad "skill row '$intent' has NO GO_SKILL_ROUTES entry — resolveGoSkillRoute falls through '?? default' and silently runs ${target#soleur:}'s place-holder, brainstorm"
      fi
      ;;
    *)
      ck
      bad "row '$intent' has an unrecognised Routes To target '$target' (expected soleur:<skill> or soleur:<domain>:<agent>)"
      ;;
  esac
done

# The converse directions, each cheap and each catching a retired row left behind in one artifact.
for tok in "${ENUM_TOKENS[@]}"; do
  ck
  if in_list "$tok" "${ROWS[@]%%$'\t'*}"; then :; fi
  _hit=0; for r in "${ROWS[@]}"; do [[ "${r%%$'\t'*}" == "$tok" ]] && _hit=1; done
  if [[ "$_hit" -eq 1 ]]; then
    ok "enum token '$tok' has a table row"
  else
    bad "enum token '$tok' has no row in the go-routing block — the scored vocabulary and the table disagree"
  fi
done
for e in "${SKILL_MAP[@]}"; do
  k="${e%%$'\t'*}"
  ck
  _hit=0; for r in "${ROWS[@]}"; do [[ "${r%%$'\t'*}" == "$k" ]] && _hit=1; done
  if [[ "$_hit" -eq 1 ]]; then
    ok "GO_SKILL_ROUTES key '$k' has a table row"
  else
    bad "GO_SKILL_ROUTES dispatches '$k' but no row documents it — a label the router honours and the table never mentions"
  fi
done

# --- ANTI-VACUITY: THE ASSERTION FLOOR ------------------------------------------------------------
# The three floors above bound the DERIVATIONS; this one bounds the EXECUTION. Without it the suite
# sits outside `scripts/guard-vacuity-floor.test.sh`'s population entirely: its `floor_lines_of`
# recognises a floor only when the `if … -lt` condition names a counter (`passes`/`fails`/`asserted`
# or a variable derived from one), and a cardinality bound over `${#ROWS[@]}` names none — so a
# suite with three healthy floors and no assertion floor is invisible to the repo's own meta-ratchet,
# which is exactly the "guard outside the guard's population" shape ADR-193 exists to close.
#
# DERIVED, never hand-summed. Every row executes exactly two assertions (enum membership, plus its
# target — dispatch value for a skill row, agent existence for an agent row), and each converse
# direction executes one per member. So the expected count is a function of the three populations and
# needs no literal that could rot as the table grows.
EXPECTED_ASSERTIONS=$(( 2 * ${#ROWS[@]} + ${#ENUM_TOKENS[@]} + ${#SKILL_MAP[@]} ))
EXPECTED_BREAKDOWN="2x${#ROWS[@]} rows + ${#ENUM_TOKENS[@]} enum + ${#SKILL_MAP[@]} map"
# The `:-1` is not a second threshold. `scripts/guard-vacuity-floor.test.sh` mutation-tests this floor
# by slicing the block below into a standalone script, widened backward only over contiguous simple
# assignments — so the array lengths above are NOT carried, and a bare `$EXPECTED_ASSERTIONS` there is
# unbound, aborts under `set -u`, and the guard scores the floor CONSTRUCTION (status unknown) instead
# of FIRES. The fallbacks bind threshold and message inside that mutant and nowhere else: in a real
# run both EXPECTED_* are always set. `1` is used for the threshold precisely so it cannot rot as the
# table grows, and any positive value discriminates because the mutant zeroes `asserted` to 0. The
# BREAKDOWN needs the same treatment for a less obvious reason — interpolating `${#ROWS[@]}` directly
# into the diagnostic left the floor unconstructible even after the threshold was fixed, because an
# unbound array in the message aborts before the message is printed. A floor whose own diagnostic
# cannot run is indistinguishable from a floor that does not fire.
MIN_ASSERTIONS=${EXPECTED_ASSERTIONS:-1}
ASSERTION_BREAKDOWN=${EXPECTED_BREAKDOWN:-breakdown unavailable under mutation}
if [[ "$asserted" -lt "$MIN_ASSERTIONS" ]]; then
  printf '\nFATAL: anti-vacuity: %d assertion(s) executed, floor is %d (%s). The battery ran but did not assert.\n' \
    "$asserted" "$MIN_ASSERTIONS" "$ASSERTION_BREAKDOWN" >&2
  exit 1
fi

# --- accounting conservation ----------------------------------------------------------------------
# The ledger is append-only and is the authority; the counters are mutable.
_lp="$(grep -c '^PASS$' "$VERDICT_LOG" || true)"
_lf="$(grep -c '^FAIL$' "$VERDICT_LOG" || true)"
if [[ "${_lp:-0}" -ne "$passes" || "${_lf:-0}" -ne "$fails" ]]; then
  printf '\nFATAL: accounting: ledger (%s pass / %s fail) disagrees with the counters (%d / %d).\n' \
    "${_lp:-0}" "${_lf:-0}" "$passes" "$fails" >&2
  exit 1
fi
if [[ $((passes + fails)) -ne "$asserted" ]]; then
  printf '\nFATAL: accounting: passes+fails (%d) != asserted (%d) — a verdict was counted but not recorded.\n' \
    "$((passes + fails))" "$asserted" >&2
  exit 1
fi

printf '\ngo-routing-table-parity.test.sh: %d passed, %d failed, %d assertion(s) executed; %s table rows, %s enum tokens, %s skill-map entries (floors %s/%s/%s, assertion floor %s)\n' \
  "$passes" "$fails" "$asserted" "${#ROWS[@]}" "${#ENUM_TOKENS[@]}" "${#SKILL_MAP[@]}" \
  "$MIN_ROWS" "$MIN_ENUM" "$MIN_SKILL_MAP" "$MIN_ASSERTIONS"

_lf_final="$(grep -c '^FAIL$' "$VERDICT_LOG" || true)"
[[ "${_lf_final:-0}" -eq 0 && "$fails" -eq 0 && "$passes" -gt 0 ]] || exit 1
exit 0
