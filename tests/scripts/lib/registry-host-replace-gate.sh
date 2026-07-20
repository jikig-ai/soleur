# shellcheck shell=bash
# Sourced destroy-guard gate for the registry-host-replace scoped -replace
# (apply_target=registry-host-replace in .github/workflows/apply-web-platform-infra.yml).
#
# EXTRACTED + SOURCED (mirrors inngest-host-replace-gate.sh): both
# the workflow's registry_host_replace plan step AND
# tests/scripts/test-registry-host-replace-gate.sh source this file and call
# registry_host_replace_gate directly, so the CI decision logic is the SAME bytes the test
# exercises (no re-derived inline copy to drift).
#
# SELF-CONTAINED jq: the registry replace has a small, fixed 6-member allow-set, so the
# counter logic lives inline here (same posture as inngest-host-replace-gate.sh).
#
# It reads a `terraform show -json <plan>` document and PERMITS EXACTLY the scoped
# registry-host recreate: a -replace of hcloud_server.registry + its 3 id-referencing
# dependents, PLUS the storage volume in-scope (so the pending 30->60 GB resize can ride
# in as a size update — WITHOUT it the guard would abort the very fix the incident needs):
#   - hcloud_server_network.registry     (network.tf; server_id is ForceNew -> replace)
#   - hcloud_volume_attachment.registry  (zot-registry.tf; server_id is ForceNew -> replace)
#   - hcloud_firewall_attachment.registry (zot-registry.tf; server_ids update-in-place —
#       INTENTIONAL deviation from inngest, which omits its firewall attachment. The registry
#       has a real deny-all-public firewall to preserve; a -targeted dependent that is not
#       re-planned would boot the new host WITHOUT the firewall on its public IP.)
#   - hcloud_volume.registry             (the zot OCI store — MUST be preserved; permits ONLY
#       an in-place size ["update"] or ["no-op"], NEVER delete/forget/replace)
#   - doppler_secret.registry_betterstack_logs_token (#6244 — the isolated Better Stack Logs
#       token that the amended 3-secret boot guard requires; MUST ride the SAME dispatch or the
#       guard FATALs and zot never launches. A pure-create on first apply, no-op thereafter. No
#       special assertion beyond allow-set membership — it just must not count as out_of_scope.)
#
# DELIBERATELY ABSENT (#6497) — doppler_secret.zot_pull_token_registry / zot_push_token_registry.
# hcloud_server.registry gained an explicit `depends_on` on both (zot-registry.tf), so `-target`
# pulls them into this plan's dependency closure. They are NOT allow-set members, and that is the
# point: they are already applied and stable, so they plan as `no-op` and the positive-action
# filter below skips them (verified against live prod state — out_of_scope=0, gate PASS). If one
# ever shows a create/update/delete, the credential the host bakes its htpasswd from has DRIFTED
# from Terraform — and a scoped host-replace is exactly the wrong thing to do while that is true.
# The abort is the correct outcome, not a false positive. Do NOT "fix" it by widening the
# allow-set: #6244 is not the precedent (its secret was a genuine pending CREATE against an
# already-existing host; these have no pending create and cannot acquire one on this path).
# Note a from-empty stand-up does NOT reach this branch — with no host in state the plan is a
# bare `create`, so `server_replaced=0` aborts first (and apply-web-platform-infra.yml:453 says
# no dispatch creates this host at all; that is the operator-local full apply's job).
#
# LARGER + STRICTER than the inngest gate (6-member allow-set, positive NIC/firewall
# assertions, size-update-only volume preserve). Do NOT "simplify" it back to the inngest
# shape — the volume + firewall + NIC assertions are load-bearing (a "server replaced but
# NIC/firewall stripped" plan must NOT pass, or the new host boots invisible to the
# egress heartbeat / naked on its public IP).
#
# NO [ack-destroy] BYPASS: a destructive prod host recreate is authorized by the menu-ack
# workflow_dispatch (hr-menu-option-ack-not-prod-write-auth), never a commit trailer.
#
# out_of_scope uses the POSITIVE-ACTION filter (create/update/delete/forget) copied verbatim
# from inngest-host-replace-gate.sh — it excludes BOTH `no-op` AND `read`, so a `data.*`
# source read (or any no-op dependency the -target set pulls in) does NOT false-abort.
#
# PASS (rc=0) iff:
#   out_of_scope==0 && store_destroyed==0 && secret_destroyed==0 && volume_bad_update==0 &&
#   server_replaced==1 && nic_recreated>=1 && attachment_recreated>=1 && firewall_ok>=1
# attachment_recreated (symmetric to nic_recreated): the hcloud_volume_attachment.registry
# must show a `create` — if a future mis-edit dropped -target=hcloud_volume_attachment.registry
# the new host would boot with /var/lib/zot UNMOUNTED (a broken store), yet server/nic/firewall
# could all still pass. A no-store host is as broken as a no-NIC one, so assert it positively.
# store_destroyed / secret_destroyed / volume_bad_update are INTENTIONALLY REDUNDANT named
# backstops for allow-set members whose DELETE would otherwise be silently permitted (the volume
# AND the logs-token secret are both in the allow-set, so out_of_scope does NOT catch their
# destroy — these named counters do). secret_destroyed (symmetric to store_destroyed): dropping
# doppler_secret.registry_betterstack_logs_token would pass the allow-set filter yet BRICK the new
# host — the amended 3-secret boot guard FATALs without BETTERSTACK_LOGS_TOKEN, so zot never
# launches. An operator sees "the zot OCI store / the logs-token secret would be destroyed"
# specifically.
#
# Usage:  source tests/scripts/lib/registry-host-replace-gate.sh
#         registry_host_replace_gate <plan-json-file>   # 0=PASS, 1=ABORT

registry_host_replace_gate() {
  local plan_json="$1"
  local counts oos sdel secdel vbad replaced nic att fw v

  if [[ ! -f "$plan_json" ]]; then
    echo "registry_host_replace_gate: plan JSON not found: ${plan_json}"
    return 1
  fi
  # Read from the STRUCTURED plan JSON (terraform show -json), never stderr.
  # EXACT-EQUALITY membership via IN(.address; allow[]) — NOT `inside`/`contains`
  # (substring matching would false-match similar addresses). Verified on jq 1.8.x.
  if ! counts=$(jq -n --slurpfile p "$plan_json" '
      def allow: [
        "hcloud_server.registry",
        "hcloud_server_network.registry",
        "hcloud_volume_attachment.registry",
        "hcloud_firewall_attachment.registry",
        "hcloud_volume.registry",
        "doppler_secret.registry_betterstack_logs_token"
      ];
      $p[0] as $plan
      | {
          out_of_scope: (
            [ $plan.resource_changes[]?
              | select(.change.actions? | any(. == "create" or . == "update" or . == "delete" or . == "forget"))
              | select(IN(.address; allow[]) | not) ]
            | length
          ),
          store_destroyed: (
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_volume.registry")
              | select(.change.actions? | any(. == "delete" or . == "forget")) ]
            | length
          ),
          secret_destroyed: (
            # #6244 backstop: the logs-token secret is in the allow-set (so a delete is NOT
            # out_of_scope), but DELETING/forgetting it would pass the gate then BRICK the host —
            # the amended 3-secret boot guard FATALs without BETTERSTACK_LOGS_TOKEN, so zot never
            # launches. Symmetric to store_destroyed: a named, positive "must be preserved" assert.
            [ $plan.resource_changes[]?
              | select(.address == "doppler_secret.registry_betterstack_logs_token")
              | select(.change.actions? | any(. == "delete" or . == "forget")) ]
            | length
          ),
          volume_bad_update: (
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_volume.registry")
              | select((.change.actions? == ["update"]) or (.change.actions? == ["no-op"]) | not) ]
            | length
          ),
          server_replaced: (
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_server.registry")
              | select((.change.actions? | index("delete")) and (.change.actions? | index("create"))) ]
            | length
          ),
          nic_recreated: (
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_server_network.registry")
              | select(.change.actions? | index("create")) ]
            | length
          ),
          attachment_recreated: (
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_volume_attachment.registry")
              | select(.change.actions? | index("create")) ]
            | length
          ),
          firewall_ok: (
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_firewall_attachment.registry")
              | select((.change.actions? == ["update"]) or (.change.actions? == ["create"])) ]
            | length
          )
        }
    ' 2>/dev/null); then
    echo "registry_host_replace_gate: jq evaluation failed on ${plan_json}"
    return 1
  fi
  oos=$(echo "$counts" | jq -r '.out_of_scope')
  sdel=$(echo "$counts" | jq -r '.store_destroyed')
  secdel=$(echo "$counts" | jq -r '.secret_destroyed')
  vbad=$(echo "$counts" | jq -r '.volume_bad_update')
  replaced=$(echo "$counts" | jq -r '.server_replaced')
  nic=$(echo "$counts" | jq -r '.nic_recreated')
  att=$(echo "$counts" | jq -r '.attachment_recreated')
  fw=$(echo "$counts" | jq -r '.firewall_ok')

  # Parse-validate every counter. A jq null/empty would evaluate false in the
  # arithmetic below and could silently mis-decide; fail LOUD instead.
  for v in "$oos" "$sdel" "$secdel" "$vbad" "$replaced" "$nic" "$att" "$fw"; do
    if [[ ! "$v" =~ ^[0-9]+$ ]]; then
      echo "registry_host_replace_gate: counter parse failed (out_of_scope='${oos}' store_destroyed='${sdel}' secret_destroyed='${secdel}' volume_bad_update='${vbad}' server_replaced='${replaced}' nic_recreated='${nic}' attachment_recreated='${att}' firewall_ok='${fw}')"
      return 1
    fi
  done

  echo "out_of_scope=${oos} store_destroyed=${sdel} secret_destroyed=${secdel} volume_bad_update=${vbad} server_replaced=${replaced} nic_recreated=${nic} attachment_recreated=${att} firewall_ok=${fw}"
  if [[ "$oos" -eq 0 && "$sdel" -eq 0 && "$secdel" -eq 0 && "$vbad" -eq 0 && "$replaced" -eq 1 && "$nic" -ge 1 && "$att" -ge 1 && "$fw" -ge 1 ]]; then
    echo "registry_host_replace_gate: PASS — scoped registry-host recreate permitted (server + 3 dependents; zot store volume + logs-token secret preserved; NIC + volume-attachment + deny-all firewall re-attached)"
    return 0
  fi
  echo "registry_host_replace_gate: ABORT — plan is NOT the exact scoped registry-host recreate (out-of-scope change, zot-store destroy/replace, logs-token secret destroy/forget, non-size volume update, no server replace, stripped private NIC, unmounted store [volume-attachment not re-created], or stripped firewall)"
  return 1
}
