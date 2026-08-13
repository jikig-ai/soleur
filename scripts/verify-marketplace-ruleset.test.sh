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

# WHY THIS IS NOT `expect "$label" "$(mutate '<filter>')" <rc>`.
# The first draft mutated inside a command substitution. A subshell cannot fail the run:
# a typo'd filter made jq exit non-zero, the substitution yielded an EMPTY path, the
# verifier fail-closed on the missing input, and every RED row PASSED for a reason that
# had nothing to do with the mutation. Measured: with mutate() fully broken, 16 of these
# 18 rows still reported green. So the mutation happens in THIS shell, and both failure
# modes are asserted before the row is allowed to count.
expect_mut() { # $1=label $2=jq-filter $3=want-rc
  if ! jq "$2" "$TMP/baseline.json" > "$TMP/m.json" 2>"$TMP/jqerr.txt"; then
    fail "$1" "mutate: jq filter failed: $2 :: $(tr '\n' ' ' < "$TMP/jqerr.txt" | cut -c1-160)"
    return
  fi
  # A filter that selects nothing (a renamed key, a changed actor_type) silently produces
  # the baseline unchanged. That row then asserts "the DECLARED ruleset is rejected",
  # which is false, and it would fail — but only by accident of direction. For a row
  # expecting rc 0 it passes while proving nothing. Landing is asserted either way.
  if cmp -s "$TMP/baseline.json" "$TMP/m.json"; then
    fail "$1" "mutate: filter produced NO change — the row is vacuous: $2"
    return
  fi
  expect "$1" "$TMP/m.json" "$3"
}

# --- Positive control -------------------------------------------------------------------------
# Without this, every RED below is satisfied by a verifier that rejects everything.
expect "control: the declared ruleset passes" "$TMP/baseline.json" 0

# This is the row that fails on EVERY apply if the normalisation is dropped: Terraform writes 0,
# the API returns null, and the canonical is API-shaped. Assert the 0-shape is accepted too.
expect_mut "control: actor_id 0 (Terraform shape) normalises equal to null (API shape)" \
  '(.bypass_actors[] | select(.actor_type=="OrganizationAdmin") | .actor_id) = 0' 0

# --- G1.1: enforcement / presence (own-dispatch row) -------------------------------------------
expect_mut "G1.1a enforcement disabled is rejected" '.enforcement = "disabled"' 1
expect_mut "G1.1b evaluate-mode enforcement is rejected" '.enforcement = "evaluate"' 1
expect "G1.1c a missing input fails closed" "$TMP/nope.json" 1
printf 'not json\n' > "$TMP/garbage.json"
expect "G1.1d an unparseable body fails closed" "$TMP/garbage.json" 1
printf '[]\n' > "$TMP/array.json"
expect "G1.1e a non-object body fails closed" "$TMP/array.json" 1

# --- G1.2: SECOND-MEMBER ROW -------------------------------------------------------------------
# A FOURTH bypass actor. "OrganizationAdmin is present" and "bypass_actors is non-empty" both
# still pass here; only full set equality catches the widening.
expect_mut "G1.2a a 4th bypass actor is rejected (second-member row)" \
  '.bypass_actors += [{"actor_id": 99, "actor_type": "Integration", "bypass_mode": "always"}]' 1
expect_mut "G1.2b a bypass actor removed is rejected" \
  '.bypass_actors = [.bypass_actors[0]]' 1
# NARROWING, not widening: `always` bypasses in every situation, `pull_request` only inside the
# PR flow. It must still redden — set equality is the property, and drifting the App's mode in
# EITHER direction means the live ruleset stopped matching what infra declares.
expect_mut "G1.2c a bypass_mode narrowed from always to pull_request is rejected" \
  '(.bypass_actors[] | select(.actor_type=="Integration") | .bypass_mode) = "pull_request"' 1
expect_mut "G1.2d a swapped Integration actor_id is rejected" \
  '(.bypass_actors[] | select(.actor_type=="Integration") | .actor_id) = 122213433' 1

# --- G1.3: the approval count — this feature's own shipped defect -------------------------------
expect_mut "G1.3a required_approving_review_count 0 is rejected" \
  '(.rules[] | select(.type=="pull_request") | .parameters.required_approving_review_count) = 0' 1
expect_mut "G1.3b the pull_request rule removed is rejected" \
  '.rules = [.rules[] | select(.type != "pull_request")]' 1

# The five sub-fields the .tf declares and the probe did not read until #7493 review. Each is
# explicit in the declaration because none has a provider default, so a live value diverging
# from it is drift by definition — and the approval-count row above passes through all of them.
expect_mut "G1.3c require_last_push_approval flipped is rejected" \
  '(.rules[] | select(.type=="pull_request") | .parameters.require_last_push_approval) = true' 1
expect_mut "G1.3d dismiss_stale_reviews_on_push flipped is rejected" \
  '(.rules[] | select(.type=="pull_request") | .parameters.dismiss_stale_reviews_on_push) = true' 1
# `false` is the DECLARED value for four of these, and jq's `//` fires on false as well as null.
# A probe reading them with `first // "<absent>"` mismatches on every input, including the
# canonical — invisible to any RED row, since a probe that rejects everything satisfies them all.
# This row is the direction that catches it.
expect_mut "G1.3e a REMOVED sub-field is rejected (not silently read as its false default)" \
  'del(.rules[] | select(.type=="pull_request") | .parameters.require_code_owner_review)' 1
expect_mut "G1.3f a narrowed allowed_merge_methods is rejected" \
  '(.rules[] | select(.type=="pull_request") | .parameters.allowed_merge_methods) = ["squash"]' 1
# Order is not promised by the API; the assertion sorts. This must NOT redden.
expect_mut "G1.3g allowed_merge_methods order is irrelevant" \
  '(.rules[] | select(.type=="pull_request") | .parameters.allowed_merge_methods) = ["rebase","squash","merge"]' 0

# --- G1.4: deletion / non_fast_forward ----------------------------------------------------------
# Declared in the .tf and asserted nowhere before this. Clearing either leaves every other
# assertion passing while the property is false.
expect_mut "G1.4a the deletion rule removed is rejected" \
  '.rules = [.rules[] | select(.type != "deletion")]' 1
expect_mut "G1.4b the non_fast_forward rule removed is rejected" \
  '.rules = [.rules[] | select(.type != "non_fast_forward")]' 1

# --- G1.5: the quantifier (active, structurally intact, governing nothing) ----------------------
# Every row here leaves `enforcement: active`, all three rules present and the bypass set
# correct. They are the ways a ruleset can be perfectly formed and protect no ref at all.
expect_mut "G1.5a a ref_name pointing at a nonexistent branch is rejected" \
  '.conditions.ref_name.include = ["refs/heads/does-not-exist"]' 1
expect_mut "G1.5b an empty ref_name include is rejected" \
  '.conditions.ref_name.include = []' 1
# exclude subtracts exactly what include adds. `include` still reads ["~DEFAULT_BRANCH"], so
# the include assertion alone reports green — this scored 7/7 OK before the exclude assertion.
expect_mut "G1.5c an exclude that cancels the include is rejected" \
  '.conditions.ref_name.exclude = ["~DEFAULT_BRANCH"]' 1
expect_mut "G1.5d any non-empty exclude is rejected" \
  '.conditions.ref_name.exclude = ["refs/heads/main"]' 1
# target: "tag" reparents every rule onto tag refs. Branch pushes become unprotected while
# enforcement, rules and conditions all still read exactly as declared.
expect_mut "G1.5e target retargeted to tag refs is rejected" '.target = "tag"' 1
expect_mut "G1.5f an absent target fails closed" 'del(.target)' 1

# --- Rule order independence --------------------------------------------------------------------
# Adding a sibling rule reorders `rules[]`; a positional `.rules[0]` reader would break here.
expect_mut "rule order is irrelevant (selected by .type, never positionally)" \
  '.rules |= reverse' 0

MIN_ASSERTIONS=27
if [[ "$ASSERTED" -lt "$MIN_ASSERTIONS" ]]; then
  fail "anti-vacuity floor" "only $ASSERTED assertion(s) ran, expected >= $MIN_ASSERTIONS"
fi

echo "=== Results: $PASS passed, $FAIL failed ($ASSERTED assertions) ==="
[[ "$FAIL" -eq 0 ]]
