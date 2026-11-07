#!/usr/bin/env bash
# shellcheck shell=bash
# Deploy-webhook Access policy gate (#9294 G1 PR-2, ADR-241 D10; Ruled by CTO agent, 2026-10-23).
#
# SOURCED by .github/workflows/apply-web-platform-infra.yml's "Terraform plan (allow-list ...)" step, which calls
#   deploy_policy_gate "$counts" "$HEAD_MSG" || exit 1
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
deploy_policy_gate() { # <counts-json> <head-commit-message>
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
    echo "::error::deploy policy guard: the plan would create/delete the deploy Access policy, leave its include other than ONE non-empty service_token block, or forget an Access token other than the deploy token (unsafe=${n[deploy_policy_unsafe]}, stray_forgets=${n[access_token_stray_forgets]}). That locks the deploy webhook out. No ack reaches this HALT."
    echo "::error::UNWEDGE: fix local.deploy_service_token_ids in tunnel.tf (it must hold the LIVE token id), or add a line containing exactly '[skip-web-platform-apply]' to the merge commit message."
    return 1
  fi
  if [[ "${n[deploy_policy_changes]}" -gt 0 ]] && ! [[ "$msg" =~ (^|$'\n')\[ack-deploy-policy\]($|$'\n') ]]; then
    echo "::error::deploy policy guard: the plan changes the deploy Access policy (changes=${n[deploy_policy_changes]}). The PR that forgets the deploy token must show it UNCHANGED; a rotation PR that changes the include on purpose adds a line containing exactly '[ack-deploy-policy]' to the merge commit message ([ack-destroy] does not count)."
    return 1
  fi
  return 0
}
