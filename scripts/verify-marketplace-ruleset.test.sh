#!/usr/bin/env bash
# Guard 1 mutation matrix — drives scripts/verify-marketplace-ruleset.sh against recorded
# ruleset-detail fixtures.
#
# WHY FIXTURES. Guard 1's property is about a LIVE GitHub ruleset, and its mutations (flip
# enforcement, add a fourth bypass actor, clear non_fast_forward) cannot be performed in CI —
# they would mean mutating production branch protection on the plugin's distribution channel.
# Recording the API's response shape and mutating THAT is the only honest way to prove the probe
# reddens. Claiming the live rows are "tested" without this would be the ceremony the Guard
# Contract format exists to prevent.
#
# The baseline fixture mirrors what `GET /repos/{owner}/{repo}/rulesets/{id}` returns for the
# ruleset declared in infra/github/ruleset-marketplace-pr-required.tf — including `actor_id:
# null` for OrganizationAdmin, which is what the API actually emits where Terraform writes 0.
set -euo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERIFIER="${MARKETPLACE_RULESET_VERIFIER:-$REPO_ROOT/scripts/verify-marketplace-ruleset.sh}"
CANONICAL="$REPO_ROOT/scripts/marketplace-ruleset-canonical-bypass-actors.json"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
ASSERTED=0
pass() { PASS=$((PASS + 1)); ASSERTED=$((ASSERTED + 1)); echo "  PASS: $1"; }
fail() {
  FAIL=$((FAIL + 1)); ASSERTED=$((ASSERTED + 1))
  echo "  FAIL: $1"; [[ $# -lt 2 ]] || echo "        $2"
}

echo "=== verify-marketplace-ruleset ==="

[[ -x "$VERIFIER" ]] || { fail "verifier is executable at $VERIFIER"; echo "=== Results: $PASS passed, $FAIL failed ==="; exit 1; }
[[ -f "$CANONICAL" ]] || { fail "canonical bypass-actors file exists at $CANONICAL"; echo "=== Results: $PASS passed, $FAIL failed ==="; exit 1; }

# API-shaped baseline: OrganizationAdmin carries `actor_id: null` here, where the .tf writes 0.
cat > "$TMP/baseline.json" <<'EOF'
{
  "id": 20765621,
  "name": "Marketplace PR Required",
  "target": "branch",
  "source_type": "Repository",
  "source": "jikig-ai/soleur-marketplace",
  "enforcement": "active",
  "bypass_actors": [
    { "actor_id": null, "actor_type": "OrganizationAdmin", "bypass_mode": "always" },
    { "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always" },
    { "actor_id": 3261325, "actor_type": "Integration", "bypass_mode": "always" }
  ],
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 1,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false,
        "allowed_merge_methods": ["squash", "merge", "rebase"]
      }
    }
  ]
}
EOF

run_rc() { local rc=0; "$VERIFIER" "$1" "$CANONICAL" > "$TMP/out.txt" 2>&1 || rc=$?; echo "$rc"; }

expect() { # $1=label $2=file $3=want-rc
  local got; got="$(run_rc "$2")"
  if [[ "$got" == "$3" ]]; then pass "$1 (exit $got)"
  else fail "$1" "expected exit $3, got $got; output: $(tr '\n' ' ' < "$TMP/out.txt" | cut -c1-240)"; fi
}

mutate() { jq "$1" "$TMP/baseline.json" > "$TMP/m.json"; echo "$TMP/m.json"; }

# --- Positive control -------------------------------------------------------------------------
# Without this, every RED below is satisfied by a verifier that rejects everything.
expect "control: the declared ruleset passes" "$TMP/baseline.json" 0

# This is the row that fails on EVERY apply if the normalisation is dropped: Terraform writes 0,
# the API returns null, and the canonical is API-shaped. Assert the 0-shape is accepted too.
expect "control: actor_id 0 (Terraform shape) normalises equal to null (API shape)" \
  "$(mutate '(.bypass_actors[] | select(.actor_type=="OrganizationAdmin") | .actor_id) = 0')" 0

# --- G1.1: enforcement / presence (own-dispatch row) -------------------------------------------
expect "G1.1a enforcement disabled is rejected" "$(mutate '.enforcement = "disabled"')" 1
expect "G1.1b evaluate-mode enforcement is rejected" "$(mutate '.enforcement = "evaluate"')" 1
expect "G1.1c a missing input fails closed" "$TMP/nope.json" 1
printf 'not json\n' > "$TMP/garbage.json"
expect "G1.1d an unparseable body fails closed" "$TMP/garbage.json" 1
printf '[]\n' > "$TMP/array.json"
expect "G1.1e a non-object body fails closed" "$TMP/array.json" 1

# --- G1.2: SECOND-MEMBER ROW -------------------------------------------------------------------
# A FOURTH bypass actor. "OrganizationAdmin is present" and "bypass_actors is non-empty" both
# still pass here; only full set equality catches the widening.
expect "G1.2a a 4th bypass actor is rejected (second-member row)" \
  "$(mutate '.bypass_actors += [{"actor_id": 99, "actor_type": "Integration", "bypass_mode": "always"}]')" 1
expect "G1.2b a bypass actor removed is rejected" \
  "$(mutate '.bypass_actors = [.bypass_actors[0]]')" 1
expect "G1.2c a bypass_mode widened to always->pull_request is rejected" \
  "$(mutate '(.bypass_actors[] | select(.actor_type=="Integration") | .bypass_mode) = "pull_request"')" 1
expect "G1.2d a swapped Integration actor_id is rejected" \
  "$(mutate '(.bypass_actors[] | select(.actor_type=="Integration") | .actor_id) = 122213433')" 1

# --- G1.3: the approval count — this feature's own shipped defect -------------------------------
expect "G1.3a required_approving_review_count 0 is rejected" \
  "$(mutate '(.rules[] | select(.type=="pull_request") | .parameters.required_approving_review_count) = 0')" 1
expect "G1.3b the pull_request rule removed is rejected" \
  "$(mutate '.rules = [.rules[] | select(.type != "pull_request")]')" 1

# --- G1.4: deletion / non_fast_forward ----------------------------------------------------------
# Declared in the .tf and asserted nowhere before this. Clearing either leaves every other
# assertion passing while the property is false.
expect "G1.4a the deletion rule removed is rejected" \
  "$(mutate '.rules = [.rules[] | select(.type != "deletion")]')" 1
expect "G1.4b the non_fast_forward rule removed is rejected" \
  "$(mutate '.rules = [.rules[] | select(.type != "non_fast_forward")]')" 1

# --- G1.5: the ref condition (active but quantifying over nothing) ------------------------------
expect "G1.5a a ref_name pointing at a nonexistent branch is rejected" \
  "$(mutate '.conditions.ref_name.include = ["refs/heads/does-not-exist"]')" 1
expect "G1.5b an empty ref_name include is rejected" \
  "$(mutate '.conditions.ref_name.include = []')" 1

# --- Rule order independence --------------------------------------------------------------------
# Adding a sibling rule reorders `rules[]`; a positional `.rules[0]` reader would break here.
expect "rule order is irrelevant (selected by .type, never positionally)" \
  "$(mutate '.rules |= reverse')" 0

MIN_ASSERTIONS=18
if [[ "$ASSERTED" -lt "$MIN_ASSERTIONS" ]]; then
  fail "anti-vacuity floor" "only $ASSERTED assertion(s) ran, expected >= $MIN_ASSERTIONS"
fi

echo "=== Results: $PASS passed, $FAIL failed ($ASSERTED assertions) ==="
[[ "$FAIL" -eq 0 ]]
