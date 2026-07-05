# shellcheck shell=bash
# Sourced destroy-guard gate for the web-2-recreate scoped -replace
# (apply_target=web-2-recreate in .github/workflows/apply-web-platform-infra.yml).
#
# EXTRACTED + SOURCED (spec-flow P1-1 / AC5): both the workflow's web_2_recreate
# plan step AND tests/scripts/test-destroy-guard-counter-web-platform.sh source
# this file and call web2_recreate_gate directly, so the CI decision logic is the
# SAME bytes the test exercises (no re-derived inline copy to drift).
#
# It reads a `terraform show -json <plan>` document and PERMITS EXACTLY the scoped
# web-2 recreate: a -replace of hcloud_server.web["web-2"] + its two id-referencing
# dependents (hcloud_server_network.web["web-2"],
# hcloud_volume_attachment.workspaces["web-2"]). It ABORTS on anything else —
# ANY change to hcloud_server.web["web-1"] (the sole live origin), ANY destroy of
# hcloud_volume.workspaces["web-2"] (the data volume must be preserved), a web-2
# in-place reboot, a no-op plan, or any stray out-of-scope resource change.
#
# NO [ack-destroy] BYPASS (AC5): a destructive prod host recreate is authorized by
# the menu-ack workflow_dispatch (hr-menu-option-ack-not-prod-write-auth), never a
# commit trailer. An ack could also permit a web-1 delete, so the precision guard
# (permit ONLY the 3 web-2 replaces) is strictly safer and carries no override.
#
# PASS (rc=0) iff:
#   web2_out_of_scope_changes==0 && nested_deletes==0 && reboot_updates==0
#   && web2_server_replaced==1
# web2_out_of_scope_changes SUBSUMES a delete-only check (spec-flow P0-2);
# reboot_updates==0 + nested_deletes==0 are kept belt-and-braces.
#
# Source of truth for the counters:
#   tests/scripts/lib/destroy-guard-filter-web-platform.jq
# Override the filter path with WEB2_GATE_FILTER (defaults to the sibling .jq).
#
# Usage:  source tests/scripts/lib/web2-recreate-gate.sh
#         web2_recreate_gate <plan-json-file>   # 0=PASS, 1=ABORT

web2_recreate_gate() {
  local plan_json="$1"
  local filter="${WEB2_GATE_FILTER:-$(dirname "${BASH_SOURCE[0]}")/destroy-guard-filter-web-platform.jq}"
  local counts oos ndel rupd replaced v

  if [[ ! -f "$plan_json" ]]; then
    echo "web2_recreate_gate: plan JSON not found: ${plan_json}"
    return 1
  fi
  # Read from the STRUCTURED plan JSON (terraform show -json), never stderr (AC5).
  if ! counts=$(jq -f "$filter" < "$plan_json" 2>/dev/null); then
    echo "web2_recreate_gate: jq filter failed on ${plan_json}"
    return 1
  fi
  oos=$(echo "$counts" | jq -r '.web2_out_of_scope_changes')
  ndel=$(echo "$counts" | jq -r '.nested_deletes')
  rupd=$(echo "$counts" | jq -r '.reboot_updates')
  replaced=$(echo "$counts" | jq -r '.web2_server_replaced')

  # Parse-validate every counter. A jq null/empty would evaluate false in the
  # arithmetic below and could silently mis-decide; fail LOUD instead.
  for v in "$oos" "$ndel" "$rupd" "$replaced"; do
    if [[ ! "$v" =~ ^[0-9]+$ ]]; then
      echo "web2_recreate_gate: counter parse failed (web2_out_of_scope_changes='${oos}' nested_deletes='${ndel}' reboot_updates='${rupd}' web2_server_replaced='${replaced}')"
      return 1
    fi
  done

  echo "web2_out_of_scope_changes=${oos} nested_deletes=${ndel} reboot_updates=${rupd} web2_server_replaced=${replaced}"
  if [[ "$oos" -eq 0 && "$ndel" -eq 0 && "$rupd" -eq 0 && "$replaced" -eq 1 ]]; then
    echo "web2_recreate_gate: PASS — scoped web-2 recreate permitted (server + 2 dependents replace; volume preserved)"
    return 0
  fi
  echo "web2_recreate_gate: ABORT — plan is NOT the exact scoped web-2 recreate (out-of-scope change, web-2 volume destroy, web-1 touch, reboot, or no-op)"
  return 1
}
