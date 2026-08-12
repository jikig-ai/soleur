#!/usr/bin/env bash
# Guard 1 — assert the live marketplace ruleset matches its declaration.
#
# Usage: verify-marketplace-ruleset.sh <ruleset-detail.json> [canonical-bypass-actors.json]
# Exit:  0 = every assertion holds; 1 = at least one mismatch, or the input is unusable.
#
# Input is the body of `GET /repos/{owner}/{repo}/rulesets/{id}` — the DETAIL endpoint.
# The LIST endpoint (`/rulesets`) returns a summary carrying only id/name/target/enforcement,
# with NO `rules`, NO `bypass_actors` and NO `conditions`, so a probe written against the list
# would silently assert nothing on three of the four properties below while looking thorough.
# The caller does the two-hop; this script asserts against the detail body.
#
# WHY THIS IS A SCRIPT AND NOT INLINE YAML. A guard that cannot be driven RED is vacuous, and
# the mutations that matter here are mutations of a LIVE GitHub ruleset — not something CI can
# perform. Extracting the assertions makes them drivable against recorded fixtures, which is the
# only way the mutation matrix in scripts/verify-marketplace-ruleset.test.sh can exist at all.
#
# THE 0-vs-null ASYMMETRY IS THE POINT OF THE NORMALISATION.
# Terraform writes `actor_id = 0` for OrganizationAdmin (the provider's HCL spelling, provider
# issue #2536); the live API reads it back as `null`. Comparing the two shapes directly makes
# this probe report drift on EVERY apply, forever — a guard that cries wolf daily is one the
# operator learns to ignore, which is worse than no guard. The canonical is stored API-shaped
# and both sides are normalised 0 -> null before comparing. The sibling `ruleset-cla-required.tf`
# documents the same asymmetry (SE-1) for the CI ruleset.
set -uo pipefail

RULESET_JSON_FILE="${1-}"
CANONICAL_FILE="${2-}"

if [[ -z "$CANONICAL_FILE" ]]; then
  _here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  CANONICAL_FILE="${_here}/marketplace-ruleset-canonical-bypass-actors.json"
fi

problems=()
checked=0

problem() { problems+=("$1"); }

assert_eq() { # $1=label $2=actual $3=expected
  checked=$((checked + 1))
  [[ "$2" == "$3" ]] || problem "${1}: got '${2}', expected '${3}'"
}

# Fail closed on an unusable input. "The ruleset is gone" and "the ruleset is fine" must never
# produce the same verdict — a probe that reports 0-checked-OK is the vacuity this refuses.
if [[ -z "$RULESET_JSON_FILE" ]]; then
  problem "no_argument: expected a path to the ruleset detail JSON as \$1"
elif [[ ! -s "$RULESET_JSON_FILE" ]]; then
  problem "input_missing: no readable, non-empty file at '${RULESET_JSON_FILE}'"
elif ! jq -e 'type == "object"' >/dev/null 2>&1 < "$RULESET_JSON_FILE"; then
  problem "input_unparseable: '${RULESET_JSON_FILE}' did not parse as a JSON object"
elif [[ ! -s "$CANONICAL_FILE" ]]; then
  problem "canonical_missing: no readable canonical bypass-actors file at '${CANONICAL_FILE}'"
elif ! jq -e 'type == "array"' >/dev/null 2>&1 < "$CANONICAL_FILE"; then
  problem "canonical_unparseable: '${CANONICAL_FILE}' did not parse as a JSON array"
else
  J="$RULESET_JSON_FILE"

  assert_eq "enforcement" "$(jq -r '.enforcement // "<absent>"' < "$J")" "active"

  # Selected by .type, never a positional .rules[0] — adding a sibling rule reorders the array
  # (the #5780 lesson from the CI ruleset's own probe).
  assert_eq "pull_request rule present" \
    "$(jq -r '[.rules[]? | select(.type=="pull_request")] | length' < "$J")" "1"

  # The assertion that would have caught this feature's own first draft. `pull_request` present
  # with the count defaulting to 0 does not close an actor holding `pull_requests: write`, and
  # "a pull_request rule exists" passes in both cases.
  assert_eq "required_approving_review_count" \
    "$(jq -r '[.rules[]? | select(.type=="pull_request") | .parameters.required_approving_review_count] | first // "<absent>"' < "$J")" "1"

  # deletion + non_fast_forward are the only UNCONDITIONAL protections here (no PR flow routes
  # around either), and an omission reads as false with no other symptom: enforcement stays
  # active, the pull_request rule stays present, the ref condition stays correct.
  assert_eq "deletion rule present" \
    "$(jq -r '[.rules[]? | select(.type=="deletion")] | length' < "$J")" "1"
  assert_eq "non_fast_forward rule present" \
    "$(jq -r '[.rules[]? | select(.type=="non_fast_forward")] | length' < "$J")" "1"

  # A ruleset can be `active` and structurally intact while quantifying over NOTHING. Point
  # ref_name at a branch that does not exist and every "is it enabled" check still passes.
  #
  # THE INCLUDE ASSERTION ALONE DOES NOT CLOSE THIS, and the first draft of this script
  # stated the property above and then asserted only `include`. Two ways to empty the
  # quantifier while `include` stays correct, both settable by any actor holding
  # `administration: write` on the marketplace repo, and both scored 7/7 OK before these
  # two lines existed:
  #   - `exclude: ["~DEFAULT_BRANCH"]` — subtracts exactly what include adds.
  #   - `target: "tag"` — the rules now govern tag refs; branches are unprotected.
  # Terraform reverts either on the next apply, but the daily drift check never inspects
  # the ruleset (#7511), so the window is bounded only by the next infra push.
  assert_eq "target" "$(jq -r '.target // "<absent>"' < "$J")" "branch"
  assert_eq "conditions.ref_name.include" \
    "$(jq -c '.conditions.ref_name.include // []' < "$J")" '["~DEFAULT_BRANCH"]'
  assert_eq "conditions.ref_name.exclude" \
    "$(jq -c '.conditions.ref_name.exclude // []' < "$J")" '[]'

  # bypass_actors as a SET, not a count or a membership test. A FOURTH entry is the widening
  # that matters, and it is invisible to "is OrganizationAdmin present" or "is the array
  # non-empty" — only full normalised-set equality catches it.
  NORM='map({actor_type, actor_id: (if .actor_id == 0 then null else .actor_id end), bypass_mode}) | sort_by(.actor_type, (.actor_id // "null" | tostring), .bypass_mode)'
  assert_eq "bypass_actors set" \
    "$(jq -c ".bypass_actors // [] | ${NORM}" < "$J")" \
    "$(jq -c "${NORM}" < "$CANONICAL_FILE")"
fi

# Anti-vacuity. A guard that silently evaluates zero properties and exits 0 is the failure mode
# every assertion above is written to avoid, so the count is asserted rather than assumed.
EXPECTED_CHECKS=9
if [[ "${#problems[@]}" -eq 0 && "$checked" -ne "$EXPECTED_CHECKS" ]]; then
  echo "verify-marketplace-ruleset: ran ${checked} assertions, expected ${EXPECTED_CHECKS} — the probe itself is broken." >&2
  exit 1
fi

if [[ "${#problems[@]}" -eq 0 ]]; then
  echo "verify-marketplace-ruleset: OK — ${checked}/${EXPECTED_CHECKS} assertions hold."
  exit 0
fi

echo "verify-marketplace-ruleset: ${#problems[@]} mismatch(es) against the declared ruleset" >&2
printf 'marketplace-ruleset| %s\n' "${problems[@]}" >&2
exit 1
