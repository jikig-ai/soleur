# shellcheck shell=bash
# Sourced destroy-guard gate for the registry-REGION-MIGRATE apply path
# (apply_target=registry-region-migrate in .github/workflows/apply-web-platform-infra.yml).
#
# EXTRACTED + SOURCED (mirrors registry-host-replace-gate.sh): both the workflow's
# registry_region_migrate plan step AND tests/scripts/test-registry-region-migrate-gate.sh source
# this file and call registry_region_migrate_gate directly, so the CI decision logic is the SAME
# bytes the test exercises (no re-derived inline copy to drift).
#
# WHY A SEPARATE GATE (vs registry-host-replace-gate.sh): a REGION migration (a var.registry_location
# change — #6288 nbg1->hel1, because the real 8 GB OOM-remediation type cx33 is offered in hel1 but
# NOT nbg1, and the phantom cx32 the plan targeted does not exist) is ForceNew on
# hcloud_volume.registry: the zot store volume is DESTROYED in the old region and RECREATED in the
# new one. registry-host-replace-gate FORBIDS that (store_destroyed==0); this gate PERMITS it,
# because the 35 GB zot store is a DISPOSABLE GHCR MIRROR that re-fills from GHCR on the next CI
# dual-push (pulls fall through to GHCR meanwhile, non-release-blocking, ADR-096).
#
# The load-bearing SAFETY invariant is UNCHANGED: out_of_scope==0 — NO resource outside the
# registry's own 6-member allow-set may be created/updated/destroyed, so this path can NEVER
# collaterally touch the web / git-data / inngest hosts or any other volume/secret. The isolated
# Better Stack logs-token secret MUST still be preserved (secret_destroyed==0) or the fresh host
# bricks (the amended 3-secret boot guard FATALs without BETTERSTACK_LOGS_TOKEN).
#
# POSITIVE creates (vs host-replace's server_replaced + store-preserved): the migration recovery
# state has the old host already destroyed (the failed cx32 -replace tore it down) and the volume
# moving region, so BOTH are pure CREATES in the new region. We assert the positive creates
# (server, fresh store volume, NIC, volume-attachment) so a plan that stripped any of them — a host
# with no store, no NIC, or naked on its public IP — is REJECTED. firewall_ok accepts create OR
# update (a fresh attachment to the new server, or an in-place server_ids update).
#
# Deliberately location-AGNOSTIC: the gate ensures the migration is SAFE + COMPLETE (registry's own
# resources only, all created, secret preserved); var.registry_location is the source of truth for
# WHERE. This keeps the gate reusable for any future registry region move.
#
# NO [ack-destroy] BYPASS: a destructive prod region migration is authorized by the menu-ack
# workflow_dispatch (hr-menu-option-ack-not-prod-write-auth), never a commit trailer.
#
# PASS (rc=0) iff:
#   out_of_scope==0 && secret_destroyed==0 &&
#   server_created>=1 && volume_created>=1 && nic_created>=1 && attachment_created>=1 && firewall_ok>=1
#
# Usage:  source tests/scripts/lib/registry-region-migrate-gate.sh
#         registry_region_migrate_gate <plan-json-file>   # 0=PASS, 1=ABORT

registry_region_migrate_gate() {
  local plan_json="$1"
  local counts oos secdel screate vcreate nic att fw v

  if [[ ! -f "$plan_json" ]]; then
    echo "registry_region_migrate_gate: plan JSON not found: ${plan_json}"
    return 1
  fi
  # Read from the STRUCTURED plan JSON (terraform show -json), never stderr.
  # EXACT-EQUALITY membership via IN(.address; allow[]) — NOT `inside`/`contains`.
  # out_of_scope uses the POSITIVE-ACTION filter (create/update/delete/forget) — excludes BOTH
  # `no-op` AND `read`, so a `data.*` source read (or any no-op dependency the -target set pulls
  # in) does NOT false-abort.
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
          secret_destroyed: (
            # The logs-token secret is in the allow-set (so a delete is NOT out_of_scope), but
            # DELETING/forgetting it would pass the allow-set filter then BRICK the fresh host —
            # the amended 3-secret boot guard FATALs without BETTERSTACK_LOGS_TOKEN, so zot never
            # launches. A named, positive "must be preserved" assert.
            [ $plan.resource_changes[]?
              | select(.address == "doppler_secret.registry_betterstack_logs_token")
              | select(.change.actions? | any(. == "delete" or . == "forget")) ]
            | length
          ),
          server_created: (
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_server.registry")
              | select(.change.actions? | index("create")) ]
            | length
          ),
          volume_created: (
            # The fresh store volume in the NEW region MUST be created — else the new host boots
            # with no /var/lib/zot backing (a volume delete with no matching create = data gone
            # AND no store). Covers both a pure create (old vol already gone) and a replace
            # (delete old-region + create new-region).
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_volume.registry")
              | select(.change.actions? | index("create")) ]
            | length
          ),
          nic_created: (
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_server_network.registry")
              | select(.change.actions? | index("create")) ]
            | length
          ),
          attachment_created: (
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
    echo "registry_region_migrate_gate: jq evaluation failed on ${plan_json}"
    return 1
  fi
  oos=$(echo "$counts" | jq -r '.out_of_scope')
  secdel=$(echo "$counts" | jq -r '.secret_destroyed')
  screate=$(echo "$counts" | jq -r '.server_created')
  vcreate=$(echo "$counts" | jq -r '.volume_created')
  nic=$(echo "$counts" | jq -r '.nic_created')
  att=$(echo "$counts" | jq -r '.attachment_created')
  fw=$(echo "$counts" | jq -r '.firewall_ok')

  # Parse-validate every counter. A jq null/empty would evaluate false in the
  # arithmetic below and could silently mis-decide; fail LOUD instead.
  for v in "$oos" "$secdel" "$screate" "$vcreate" "$nic" "$att" "$fw"; do
    if [[ ! "$v" =~ ^[0-9]+$ ]]; then
      echo "registry_region_migrate_gate: counter parse failed (out_of_scope='${oos}' secret_destroyed='${secdel}' server_created='${screate}' volume_created='${vcreate}' nic_created='${nic}' attachment_created='${att}' firewall_ok='${fw}')"
      return 1
    fi
  done

  echo "out_of_scope=${oos} secret_destroyed=${secdel} server_created=${screate} volume_created=${vcreate} nic_created=${nic} attachment_created=${att} firewall_ok=${fw}"
  if [[ "$oos" -eq 0 && "$secdel" -eq 0 && "$screate" -ge 1 && "$vcreate" -ge 1 && "$nic" -ge 1 && "$att" -ge 1 && "$fw" -ge 1 ]]; then
    echo "registry_region_migrate_gate: PASS — scoped registry region migration permitted (registry server + fresh store volume + NIC + volume-attachment created in the new region; logs-token secret preserved; no out-of-scope resource touched)"
    return 0
  fi
  echo "registry_region_migrate_gate: ABORT — plan is NOT the exact scoped registry region migration (out-of-scope resource create/update/destroy, logs-token secret destroy/forget, or a missing server/volume/NIC/attachment create — the fresh host would boot storeless / NIC-less / firewall-naked)"
  return 1
}
