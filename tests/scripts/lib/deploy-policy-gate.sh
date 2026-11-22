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
# `[ack-destroy]` is deliberately NOT consulted. Prints ::error:: lines to STDERR (the id reader and
# deploy_policy_counts run inside `$(...)` captures, which swallow stdout); returns 1 to refuse, 0 to pass.
#
# #12937 (Ruled by CTO agent, 2026-11-23): the same counters cover the whole Access family on its one set of
# addresses (apps .deploy/.ssh/.registry, policies .deploy_service_token/.ci_ssh_service_token/
# .registry_push_service_token), each policy judged against its OWN committed token reference. On this ROUTINE path
# only a no-op or an acknowledged in-place update in the committed shape passes. A create, delete, forget or replace
# of a gated address, a second include block, a wrong id, an app off its pinned zone-scoped shape, and any Access
# app/policy change outside the filter's access_family_table are unsafe: the first create belongs to the `tunnel`
# phase of cf-account-migrate (ADR-329), which runs under its own gate and never calls this function. The deploy
# policy needs the id list committed in tunnel.tf, which plan JSON does not carry, so the workflow feeds this gate
# from deploy_policy_counts (below), never from the destroy guard's own id-less `counts`.
UUID_ERE='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
NIL_UUID='00000000-0000-0000-0000-000000000000'

# deploy_policy_committed_ids <tunnel.tf> -> the committed `deploy_service_token_ids = [...]` list as
# compact JSON on stdout. Exactly ONE non-comment line may declare it (the same line the policy's UUID
# precondition reads); a trailing `# ...` comment is allowed. Anything else (absent, twice, empty, a
# non-UUID entry, the nil placeholder, not a literal list) returns 1 with an ::error::, so a broken read
# never becomes a pass.
deploy_policy_committed_ids() { # <tunnel.tf>
  local tf="$1" lines n list
  lines="$(grep -E '^[[:space:]]*deploy_service_token_ids[[:space:]]*=' "$tf" 2>/dev/null || true)"
  n=0; [[ -n "$lines" ]] && n="$(grep -c . <<<"$lines")"
  if [[ "$n" != "1" ]]; then
    echo "::error::deploy policy guard: ${tf} declares deploy_service_token_ids on ${n} line(s), expected exactly 1. Refusing to apply." >&2
    return 1
  fi
  list="$(sed -nE 's/^[[:space:]]*deploy_service_token_ids[[:space:]]*=[[:space:]]*(\[[^]#]*\])[[:space:]]*(#.*)?$/\1/p' <<<"$lines")"
  if ! jq -ce --arg re "$UUID_ERE" 'if type == "array" and length > 0 and all(.[]; type == "string" and test($re)) then . else error("bad") end' <<<"${list:-null}" >/dev/null 2>&1; then
    echo "::error::deploy policy guard: deploy_service_token_ids in ${tf} is not a non-empty literal list of UUIDs (got '${list}'). Refusing to apply." >&2
    return 1
  fi
  if jq -e --arg nil "$NIL_UUID" 'any(.[]; . == $nil)' <<<"$list" >/dev/null 2>&1; then
    echo "::error::deploy policy guard: placeholder deploy token id still committed (FILL-AT-PHASE-3.1) in ${tf}. Refusing to apply." >&2
    return 1
  fi
  jq -c . <<<"$list"
}

# deploy_policy_counts <tfplan.json> <tunnel.tf> <filter.jq> -> the destroy-guard counters with the committed
# deploy id list bound as $ids. Returns 1 (with an ::error::) when either read fails.
deploy_policy_counts() { # <tfplan.json> <tunnel.tf> <filter.jq>
  local plan="$1" tf="$2" filter="$3" ids out
  ids="$(deploy_policy_committed_ids "$tf")" || return 1
  if ! out="$(jq --argjson ids "$ids" -f "$filter" < "$plan" 2>/dev/null)" || [[ -z "$out" ]]; then
    echo "::error::deploy policy guard: the destroy-guard filter could not read ${plan} with the committed ids. Refusing to apply." >&2
    return 1
  fi
  printf '%s\n' "$out"
}

DEPLOY_POLICY_UNWEDGE="UNWEDGE: fix local.deploy_service_token_ids in tunnel.tf (it must hold the LIVE token id); if the plan creates or replaces a gated Access address, run the cf-account-migrate tunnel phase (ADR-329) instead of this apply; or add a line containing exactly '[skip-web-platform-apply]' to the merge commit message."
deploy_policy_gate() { # <counts-json> <combined tip+push-commit messages>
  local counts="$1" msg="${2-}" k v
  local -A n=()
  for k in deploy_policy_changes deploy_policy_unsafe access_token_stray_forgets; do
    v="$(jq -r --arg k "$k" '.[$k] // "missing"' <<<"$counts" 2>/dev/null)" || v="unparsed"
    [[ "$v" =~ ^[0-9]+$ ]] || {
      echo "::error::deploy policy guard: counter ${k} did not parse as a non-negative integer (got '${v}'). Refusing to apply." >&2
      return 1
    }
    n[$k]="$v"
  done
  if [[ "${n[deploy_policy_unsafe]}" -gt 0 || "${n[access_token_stray_forgets]}" -gt 0 ]]; then
    echo "::error::deploy policy guard: the plan would create, delete, forget or replace a gated Access policy or app (deploy, ssh/ci_ssh or registry/registry_push; their first create belongs to the cf-account-migrate tunnel phase), leave an include other than ONE service_token-only block bound to its own committed token (the deploy one: exactly local.deploy_service_token_ids) with decision non_identity, change a gated app's zone_id/domain/type/policies/options_preflight_bypass/self_hosted_domains/destinations/cors_headers, change any Access app or policy whose address is not in the filter's access_family_table, or forget an Access token other than the deploy token (unsafe=${n[deploy_policy_unsafe]}, stray_forgets=${n[access_token_stray_forgets]}). That locks the deploy webhook, CI SSH or registry push out. No ack reaches this HALT." >&2
    echo "::error::${DEPLOY_POLICY_UNWEDGE}" >&2
    return 1
  fi
  if [[ "${n[deploy_policy_changes]}" -gt 0 ]] && ! [[ "$msg" =~ (^|$'\n')\[ack-deploy-policy\]($|$'\n') ]]; then
    echo "::error::deploy policy guard: the plan changes a gated Access policy or app in place, or does not plan the deploy policy at all (changes=${n[deploy_policy_changes]}). The PR that forgets the deploy token must show it UNCHANGED; a PR that updates a gated policy or app on purpose (an id rotation) adds a line containing exactly '[ack-deploy-policy]' to the merge commit message ([ack-destroy] does not count)." >&2
    echo "::error::${DEPLOY_POLICY_UNWEDGE}" >&2
    return 1
  fi
  return 0
}
