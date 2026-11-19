#!/usr/bin/env bash
# shellcheck shell=bash
# Deploy-webhook Access policy gate (#9294 G1 PR-2, ADR-241 D10; Ruled by CTO agent, 2026-10-23).
#
# SOURCED by .github/workflows/apply-web-platform-infra.yml's "Terraform plan (allow-list ...)" step, which calls
#   deploy_policy_gate "$counts" "$ALL_MSGS" || exit 1
# where ALL_MSGS is the tip message plus every push commit's message (a merge-queue coalesce can bury the
# ack one squash below the tip; event.commits is capped at 20 entries — an older ack still misses, fail-closed
# for the acks, fail-open for the [skip-web-platform-apply] kill-switch, which recomputes the same combined feed
# at preflight; both ack gates and the skip gate consume it).
# right after the apex_move_orphans HALT and BEFORE the destroy_count sum, so `[ack-destroy]` cannot reach it. It lives
# here, not inline, so a test can EXECUTE it (tests/scripts/test-deploy-access-token-forget.sh) and so the 490,000-byte
# ADR-231 workflow cap is not spent on it.
#
# WHY. The deploy webhook's Access policy admits the ids in local.deploy_service_token_ids (tunnel.tf). A wrong id in
# the single `include` block locks the deploy channel out at Access, during the git-data wipe freeze. Nothing else sees
# it: the include-block counter counts BLOCKS (an id swap inside the one block counts 0) and an in-place update is not a
# delete. The three counters come from tests/scripts/lib/destroy-guard-filter-web-platform.jq; this function only decides.
#
#   deploy_policy_unsafe > 0 or access_token_stray_forgets > 0  -> refuse, no ack (the lockout shape, or a forget of an
#                                                                  Access token other than the deploy token)
#   deploy_policy_changes > 0 and no own-line [ack-deploy-policy] -> refuse (the PR that forgets the deploy token must
#                                                                  show the policy UNCHANGED; a rotation PR changes the
#                                                                  include on purpose and carries the ack)
#   a counter that is not a non-negative integer                -> refuse (a jq failure must not read as 0)
# `[ack-destroy]` is deliberately NOT consulted. Prints ::error:: lines; returns 1 to refuse, 0 to pass.
#
# #12937 (Ruled by CTO agent, 2026-11-19): the same counters also cover the three Soleur-account policies
# (`cloudflare_zero_trust_access_policy.{deploy_service_token,ci_ssh_service_token,registry_push_service_token}_soleur`),
# each judged against its OWN committed token reference. Their single acknowledged create passes; a delete,
# a second include block, a wrong id or a re-include on any of them is unsafe. The deploy one needs the id
# list committed in tunnel.tf, which plan JSON does not carry, so the workflow feeds this gate from
# deploy_policy_counts (below), never from the destroy guard's own id-less `counts`.
UUID_ERE='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'

# deploy_policy_committed_ids <tunnel.tf> -> the committed `deploy_service_token_ids_soleur = [...]` list as
# compact JSON on stdout. Exactly ONE non-comment line may declare it (the same line the policy's UUID
# precondition reads); a trailing `# ...` comment is allowed. Anything else (absent, twice, empty, a
# non-UUID entry, not a literal list) returns 1 with an ::error::, so a broken read never becomes a pass.
deploy_policy_committed_ids() { # <tunnel.tf>
  local tf="$1" lines n list
  lines="$(grep -E '^[[:space:]]*deploy_service_token_ids_soleur[[:space:]]*=' "$tf" 2>/dev/null || true)"
  n=0; [[ -n "$lines" ]] && n="$(grep -c . <<<"$lines")"
  if [[ "$n" != "1" ]]; then
    echo "::error::deploy policy guard: ${tf} declares deploy_service_token_ids_soleur on ${n} line(s), expected exactly 1. Refusing to apply."
    return 1
  fi
  list="$(sed -nE 's/^[[:space:]]*deploy_service_token_ids_soleur[[:space:]]*=[[:space:]]*(\[[^]#]*\])[[:space:]]*(#.*)?$/\1/p' <<<"$lines")"
  if ! jq -ce --arg re "$UUID_ERE" 'if type == "array" and length > 0 and all(.[]; type == "string" and test($re)) then . else error("bad") end' <<<"${list:-null}" 2>/dev/null; then
    echo "::error::deploy policy guard: deploy_service_token_ids_soleur in ${tf} is not a non-empty literal list of UUIDs (got '${list}'). Refusing to apply."
    return 1
  fi
}

# deploy_policy_counts <tfplan.json> <tunnel.tf> <filter.jq> -> the destroy-guard counters with the committed
# deploy id list bound as $ids. Returns 1 (with an ::error::) when either read fails.
deploy_policy_counts() { # <tfplan.json> <tunnel.tf> <filter.jq>
  local plan="$1" tf="$2" filter="$3" ids out
  ids="$(deploy_policy_committed_ids "$tf")" || return 1
  if ! out="$(jq --argjson ids "$ids" -f "$filter" < "$plan" 2>/dev/null)" || [[ -z "$out" ]]; then
    echo "::error::deploy policy guard: the destroy-guard filter could not read ${plan} with the committed ids. Refusing to apply."
    return 1
  fi
  printf '%s\n' "$out"
}

DEPLOY_POLICY_UNWEDGE="UNWEDGE: fix local.deploy_service_token_ids / local.deploy_service_token_ids_soleur in tunnel.tf (each must hold the LIVE token id), or add a line containing exactly '[skip-web-platform-apply]' to the merge commit message."
deploy_policy_gate() { # <counts-json> <combined tip+push-commit messages>
  local counts="$1" msg="${2-}" k v
  local -A n=()
  for k in deploy_policy_changes deploy_policy_unsafe access_token_stray_forgets; do
    v="$(jq -r --arg k "$k" '.[$k] // "missing"' <<<"$counts" 2>/dev/null)" || v="unparsed"
    [[ "$v" =~ ^[0-9]+$ ]] || {
      echo "::error::deploy policy guard: counter ${k} did not parse as a non-negative integer (got '${v}'). Refusing to apply."
      return 1
    }
    n[$k]="$v"
  done
  if [[ "${n[deploy_policy_unsafe]}" -gt 0 || "${n[access_token_stray_forgets]}" -gt 0 ]]; then
    echo "::error::deploy policy guard: the plan would create/delete the old deploy Access policy, delete/replace a _soleur Access policy (deploy, ci_ssh or registry_push), leave an include other than ONE service_token block bound to its own committed token (the deploy one: exactly local.deploy_service_token_ids_soleur), or forget an Access token other than the deploy token (unsafe=${n[deploy_policy_unsafe]}, stray_forgets=${n[access_token_stray_forgets]}). That locks the deploy webhook, CI SSH or registry push out. No ack reaches this HALT."
    echo "::error::${DEPLOY_POLICY_UNWEDGE}"
    return 1
  fi
  if [[ "${n[deploy_policy_changes]}" -gt 0 ]] && ! [[ "$msg" =~ (^|$'\n')\[ack-deploy-policy\]($|$'\n') ]]; then
    echo "::error::deploy policy guard: the plan changes a gated Access policy (changes=${n[deploy_policy_changes]}): the old deploy policy, or a _soleur deploy/ci_ssh/registry_push policy (its first create included). The PR that forgets the deploy token must show it UNCHANGED; a PR that creates or re-includes a gated policy on purpose adds a line containing exactly '[ack-deploy-policy]' to the merge commit message ([ack-destroy] does not count)."
    echo "::error::${DEPLOY_POLICY_UNWEDGE}"
    return 1
  fi
  return 0
}
