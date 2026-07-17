# shellcheck shell=bash
# Sourced destroy-guard gate for the web-2 RETIREMENT (#6538) — the operator-local
# 5-target plan of B6.2, NOT any CI path.
#
# EXTRACTED + SOURCED (mirrors web2-recreate-gate.sh): the B6.3 gate invocation AND
# tests/scripts/test-destroy-guard-counter-web-platform.sh both source this file and
# call web2_retire_gate directly, so the bytes the operator runs are the bytes under
# test (no re-derived inline copy to drift).
#
# It reads a `terraform show -json <plan>` document and PERMITS EXACTLY the scoped
# web-2 retirement: destroy hcloud_server.web["web-2"], hcloud_server_network.web
# ["web-2"], hcloud_volume_attachment.workspaces["web-2"] and
# hcloud_volume.workspaces["web-2"], plus an in-place UPDATE of
# hcloud_firewall_attachment.web (dropping web-2 from server_ids).
#
# NOT web2-recreate with an extra address. The two gates are OPPOSITES on the data
# volume: recreate REQUIRES it to survive, retire REQUIRES it to go. Grading a
# retire plan against web2_allow aborts on the volume destroy that IS the
# retirement; grading a recreate plan against web2_retire_allow permits destroying
# the data the recreate exists to preserve.
#
# NO [ack-destroy] BYPASS (mirrors web2-recreate-gate.sh): a destructive prod host
# retirement is authorized by an explicit per-command operator go-ahead
# (hr-menu-option-ack-not-prod-write-auth), never a commit trailer. An ack could
# also permit a web-1 delete, so the precision guard carries no override.
#
# PASS (rc=0) iff ALL of:
#   web2_retire_out_of_scope_changes == 0   (subsumes web-1 touch, proxy-TLS birth,
#                                            stray creates, `removed{}` state-drops)
#   nested_deletes == 0 && reboot_updates == 0        (defense-in-depth backstop)
#   each of the 4 named destroy counters <= 1         (subset, NOT strict equality)
#   (server + network + volume_attachment + volume) >= 1   (not a no-op plan)
#   retire_firewall_attachment_deletes == 0           (never strip web-1's firewall)
#   retire_firewall_attachment_updates <= 1
#   NO-STRAND: web2_server_destroyed <= web2_volume_destroyed
#
# WHY SUBSET AND NOT EQUALITY. Terraform applies sequentially and can die mid-way.
# Strict equality (all four destroys required) fails closed on the retry and strands
# a half-retired host — the v1 P0. So any retry SUBSET must pass.
#
# WHY THE NO-STRAND IMPLICATION. A bare subset rule would also accept the measured
# push-apply shape (2026-07-17: `0 to add, 1 to change, 1 to destroy` — the server
# destroyed, the volume NOT in that scope). Applying that kills the host and leaves
# a 20 GB volume billing forever with nothing attached. A plan is computed from
# CURRENT state, so `server_destroyed == 1 => volume_destroyed == 1` separates the
# two exactly:
#   fresh retire  : both in state, both destroyed       -> 1 => 1  PASS
#   retry (server already destroyed): server=0          -> vacuous PASS
#   push-apply shape: server destroyed, volume unscoped -> 1 => 0  ABORT
# Expressed as `server -le volume` since both are 0/1.
#
# Source of truth for the counters:
#   tests/scripts/lib/destroy-guard-filter-web-platform.jq
# Override the filter path with WEB2_GATE_FILTER (defaults to the sibling .jq).
#
# Usage:  source tests/scripts/lib/web2-retire-gate.sh
#         web2_retire_gate <plan-json-file>   # 0=PASS, 1=ABORT

web2_retire_gate() {
  local plan_json="$1"
  local filter="${WEB2_GATE_FILTER:-$(dirname "${BASH_SOURCE[0]}")/destroy-guard-filter-web-platform.jq}"
  local counts oos ndel rupd srv net vat vol fwu fwd members v

  if [[ ! -f "$plan_json" ]]; then
    echo "web2_retire_gate: plan JSON not found: ${plan_json}"
    return 1
  fi
  # Read from the STRUCTURED plan JSON (terraform show -json), never stderr.
  if ! counts=$(jq -f "$filter" < "$plan_json" 2>/dev/null); then
    echo "web2_retire_gate: jq filter failed on ${plan_json}"
    return 1
  fi
  oos=$(echo "$counts" | jq -r '.web2_retire_out_of_scope_changes')
  ndel=$(echo "$counts" | jq -r '.nested_deletes')
  rupd=$(echo "$counts" | jq -r '.reboot_updates')
  srv=$(echo "$counts" | jq -r '.web2_server_destroyed')
  net=$(echo "$counts" | jq -r '.web2_server_network_destroyed')
  vat=$(echo "$counts" | jq -r '.web2_volume_attachment_destroyed')
  vol=$(echo "$counts" | jq -r '.web2_volume_destroyed')
  fwu=$(echo "$counts" | jq -r '.retire_firewall_attachment_updates')
  fwd=$(echo "$counts" | jq -r '.retire_firewall_attachment_deletes')

  # Parse-validate every counter. A jq null/empty would evaluate false in the
  # arithmetic below and could silently mis-decide; fail LOUD instead.
  for v in "$oos" "$ndel" "$rupd" "$srv" "$net" "$vat" "$vol" "$fwu" "$fwd"; do
    if [[ ! "$v" =~ ^[0-9]+$ ]]; then
      echo "web2_retire_gate: counter parse failed (oos='${oos}' nested_deletes='${ndel}' reboot_updates='${rupd}' server='${srv}' network='${net}' volume_attachment='${vat}' volume='${vol}' fw_updates='${fwu}' fw_deletes='${fwd}')"
      return 1
    fi
  done

  members=$((srv + net + vat + vol))
  echo "web2_retire_out_of_scope_changes=${oos} nested_deletes=${ndel} reboot_updates=${rupd} server=${srv} network=${net} volume_attachment=${vat} volume=${vol} fw_updates=${fwu} fw_deletes=${fwd} members=${members}"

  if [[ "$oos" -ne 0 ]]; then
    echo "web2_retire_gate: ABORT — ${oos} out-of-scope change(s): something outside the 5 web-2 retire addresses is being created/updated/deleted/forgotten (web-1 touch, proxy-TLS birth, or a stray resource)."
    return 1
  fi
  if [[ "$ndel" -ne 0 || "$rupd" -ne 0 ]]; then
    echo "web2_retire_gate: ABORT — nested_deletes=${ndel} reboot_updates=${rupd} (expected 0/0)."
    return 1
  fi
  if [[ "$srv" -gt 1 || "$net" -gt 1 || "$vat" -gt 1 || "$vol" -gt 1 ]]; then
    echo "web2_retire_gate: ABORT — a per-address destroy counter exceeds 1; the plan is not a scoped retirement."
    return 1
  fi
  if [[ "$members" -lt 1 ]]; then
    echo "web2_retire_gate: ABORT — no-op plan (0 of the 4 web-2 resources are being destroyed). The apply must be a real, scoped retirement."
    return 1
  fi
  if [[ "$fwd" -ne 0 ]]; then
    echo "web2_retire_gate: ABORT — hcloud_firewall_attachment.web is being DELETED (${fwd}); it must UPDATE in place. A delete strips web-1's firewall."
    return 1
  fi
  if [[ "$fwu" -gt 1 ]]; then
    echo "web2_retire_gate: ABORT — hcloud_firewall_attachment.web shows ${fwu} updates (expected <=1)."
    return 1
  fi
  # NO-STRAND. Both operands are 0/1, so -le encodes `server => volume`.
  if [[ "$srv" -gt "$vol" ]]; then
    echo "web2_retire_gate: ABORT — STRANDING HAZARD: hcloud_server.web[\"web-2\"] is being destroyed but hcloud_volume.workspaces[\"web-2\"] is NOT. Applying this kills the host and leaves a 20 GB volume billing with nothing attached. This is the push-apply shape (0 add / 1 change / 1 destroy) — re-run the plan with the full 5-target scope."
    return 1
  fi

  echo "web2_retire_gate: PASS — scoped web-2 retirement permitted (${members} of 4 web-2 resources destroyed; firewall attachment updates in place; volume not stranded)"
  return 0
}
