# shellcheck shell=bash
# Sourced destroy-guard gate for the inngest-host-replace scoped -replace
# (apply_target=inngest-host-replace in .github/workflows/apply-web-platform-infra.yml).
#
# EXTRACTED + SOURCED (mirrors registry-host-replace-gate.sh): both the workflow's
# inngest_host_replace plan step AND tests/scripts/test-inngest-host-replace-gate.sh
# source this file and call inngest_host_replace_gate directly, so the CI decision
# logic is the SAME bytes the test exercises (no re-derived inline copy to drift).
#
# SELF-CONTAINED jq (unlike web2's shared destroy-guard-filter-web-platform.jq): the
# inngest replace has a small, fixed allow-set, so the counter logic lives inline here.
#
# It reads a `terraform show -json <plan>` document and PERMITS EXACTLY the scoped
# inngest-host recreate: a -replace of hcloud_server.inngest + its two id-referencing
# dependents that terraform replaces because they interpolate the NEW server id:
#   - hcloud_server_network.inngest        (network.tf; server_id is ForceNew -> replace)
#   - hcloud_volume_attachment.inngest_redis (inngest-host.tf; server_id is ForceNew -> replace)
# This allow-set was DERIVED (2026-06, #6178) from the then-current web-2-recreate golden
# fixture, which showed that a scoped `-replace` of an hcloud server touches EXACTLY
# server + server_network + volume_attachment — hcloud_firewall_attachment.* (server_ids,
# non-ForceNew) does NOT change, so it is DELIBERATELY absent from the allow-set.
# That fixture was removed with the web-2 dispatch sweep (#6575, 2026-07-20); the derivation
# it justified is unchanged and is now pinned by this gate's OWN tests, which are the live
# guarantee. Do not re-add a pointer to a deleted fixture.
#
# hcloud_volume.inngest_redis (the durable Redis AOF store) is DELIBERATELY ABSENT — the
# volume MUST be preserved across the replace (exactly how web2-retire-gate.sh preserves
# hcloud_volume.workspaces), so ANY change to it trips inngest_out_of_scope_changes AND the
# explicit redis_volume_destroyed backstop below.
#
# NO [ack-destroy] BYPASS: a destructive prod host recreate is authorized by the menu-ack
# workflow_dispatch (hr-menu-option-ack-not-prod-write-auth), never a commit trailer.
#
# PASS (rc=0) iff:
#   inngest_out_of_scope_changes==0 && redis_volume_destroyed==0 && inngest_server_replaced==1
# redis_volume_destroyed==0 is INTENTIONALLY REDUNDANT with the out-of-scope counter
# (a Redis-volume delete is also an out-of-allow-set change) — kept as a named, loud
# backstop so an operator sees "Redis AOF volume would be destroyed" specifically.
#
# Usage:  source tests/scripts/lib/inngest-host-replace-gate.sh
#         inngest_host_replace_gate <plan-json-file>   # 0=PASS, 1=ABORT

inngest_host_replace_gate() {
  local plan_json="$1"
  local counts oos rdel replaced v

  if [[ ! -f "$plan_json" ]]; then
    echo "inngest_host_replace_gate: plan JSON not found: ${plan_json}"
    return 1
  fi
  # Read from the STRUCTURED plan JSON (terraform show -json), never stderr.
  # EXACT-EQUALITY membership via IN(.address; $allow[]) — NOT `inside`/`contains`
  # (substring matching would false-match similar addresses). Verified on jq 1.8.x.
  if ! counts=$(jq -n --slurpfile p "$plan_json" '
      def allow: [
        "hcloud_server.inngest",
        "hcloud_server_network.inngest",
        "hcloud_volume_attachment.inngest_redis"
      ];
      $p[0] as $plan
      | {
          inngest_out_of_scope_changes: (
            [ $plan.resource_changes[]?
              | select(.change.actions? | any(. == "create" or . == "update" or . == "delete" or . == "forget"))
              | select(IN(.address; allow[]) | not) ]
            | length
          ),
          redis_volume_destroyed: (
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_volume.inngest_redis")
              | select(.change.actions? | any(. == "delete" or . == "forget")) ]
            | length
          ),
          inngest_server_replaced: (
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_server.inngest")
              | select((.change.actions? | index("delete")) and (.change.actions? | index("create"))) ]
            | length
          )
        }
    ' 2>/dev/null); then
    echo "inngest_host_replace_gate: jq evaluation failed on ${plan_json}"
    return 1
  fi
  oos=$(echo "$counts" | jq -r '.inngest_out_of_scope_changes')
  rdel=$(echo "$counts" | jq -r '.redis_volume_destroyed')
  replaced=$(echo "$counts" | jq -r '.inngest_server_replaced')

  # Parse-validate every counter. A jq null/empty would evaluate false in the
  # arithmetic below and could silently mis-decide; fail LOUD instead.
  for v in "$oos" "$rdel" "$replaced"; do
    if [[ ! "$v" =~ ^[0-9]+$ ]]; then
      echo "inngest_host_replace_gate: counter parse failed (inngest_out_of_scope_changes='${oos}' redis_volume_destroyed='${rdel}' inngest_server_replaced='${replaced}')"
      return 1
    fi
  done

  echo "inngest_out_of_scope_changes=${oos} redis_volume_destroyed=${rdel} inngest_server_replaced=${replaced}"
  if [[ "$oos" -eq 0 && "$rdel" -eq 0 && "$replaced" -eq 1 ]]; then
    echo "inngest_host_replace_gate: PASS — scoped inngest-host recreate permitted (server + 2 dependents replace; Redis AOF volume preserved)"
    return 0
  fi
  echo "inngest_host_replace_gate: ABORT — plan is NOT the exact scoped inngest-host recreate (out-of-scope change, Redis-volume destroy, or no-op)"
  return 1
}
