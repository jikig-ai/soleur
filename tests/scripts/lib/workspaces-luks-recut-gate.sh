# shellcheck shell=bash
# Sourced destroy-guard gate for the workspaces-luks-recut scoped VOLUME REPLACE
# (apply_target=workspaces-luks-recut in .github/workflows/apply-web-platform-infra.yml, #6855 / #6812).
#
# EXTRACTED + SOURCED (mirrors workspaces-luks-cutover-gate.sh / git-data-host-replace-gate.sh):
# both the workflow's workspaces_luks_recut plan step AND
# tests/scripts/test-workspaces-luks-recut-gate.sh source this file and call
# workspaces_luks_recut_gate directly, so the CI decision logic is the SAME bytes the test
# exercises (no re-derived inline copy to drift).
#
# ⚠️ WHAT THIS IS — a scoped `-replace` of the ORPHANED LUKS volume, NOT a first provision.
# After the 2026-07-20 dead-man revert, hcloud_volume.workspaces_luks (Hetzner id 106406962) is
# still in state and already crypto_LUKS, holding the operator-ACCEPTED-discarded 27-min window
# (#6812 comment, 2026-07-21). A plain re-cut against it hits workspaces-cutover.sh's
# crypto_LUKS→idempotent-no-op arm and never luksFormats. This gate authorizes making it FRESH:
# a scoped `terraform -replace=hcloud_volume.workspaces_luks` (+ its attachment) that DESTROYS the
# orphaned volume and CREATES a raw one with the SAME name — so the existing cutover then resolves
# the new device by name, hits the raw→luksFormat arm, and copies from live plaintext.
#
# INVERSION vs the cutover gate: there the LUKS volume is a pure `+create` (first provision) and the
# passphrase's FIRST create is legal. HERE the volume is a REPLACE (delete AND create) and the
# passphrase MUST be PRESERVED — the recut REUSES the existing header key, so ANY action on the
# passphrase / its doppler_secret (create included) is the F4 header-loss catastrophe and ABORTS.
#
# It reads a `terraform show -json <plan>` document and PERMITS EXACTLY the scoped recut:
#   - hcloud_volume.workspaces_luks             REPLACE  (actions include BOTH "delete" AND "create")
#   - hcloud_volume_attachment.workspaces_luks  CREATE   (re-attach the new volume; a replace also
#                                                          deletes the old attachment — legal)
# and NOTHING else. The recut job `-replace`s the volume and `-target`s exactly these two.
#
# ⚠️ RECOVERY ARM (architecture-strategist P2, #6855 review) — a `-replace` on hcloud_volume.workspaces_luks
# is destroy-BEFORE-create (no create_before_destroy in workspaces-luks.tf), so an apply that fails
# BETWEEN the delete and the create strands the resource OUT of state. A re-dispatch then plans a
# BARE create (`-replace` on an absent address plans a plain create), and the volume shows
# ["create"] with `before == null`. The gate ACCEPTS that recovery shape — a bare create of a FRESH
# empty volume touches no live data (every data-safety counter below is unchanged), and auto-recovery
# via re-dispatch honors hr-exhaust-all-automated-options rather than stranding a non-technical
# operator on a manual `terraform apply`. `luks_volume_provisioned` therefore accepts EITHER a genuine
# replace OR a bare create when `before == null`; a bare create with a NON-null before, or a
# delete/forget/update without a create, still ABORTS.
#
# ⚠️ ID-PIN (user-impact-reviewer P2 FINDING 1, #6855 review) — the address-based counters authorize
# destruction by terraform ADDRESS alone. If state ever mapped hcloud_volume.workspaces_luks to the
# LIVE volume's physical id (state corruption / a bad `state mv` / import error), a `-replace` of the
# correct ADDRESS would destroy the WRONG physical volume with every counter reading 0. When the caller
# supplies `$2` (the operator-confirmed physical volume id of the orphaned volume — required by the
# workflow), the gate asserts the REPLACED volume's `.change.before.id` equals it; a mismatch ABORTS,
# binding destruction to the physical volume the operator named. The recovery arm's bare create has
# `before == null` (no id to destroy), so the id-pin is correctly a no-op there.
#
# THE SOLE-COPY-DATA BACKSTOPS (each named, operator-legible):
#   - old_volume_touched     — hcloud_volume.workspaces["web-1"] (server.tf, for_each) is the LIVE
#       plaintext /mnt/data. #6593 shipped NO prevent_destroy. This counter is its sole protection.
#   - old_attachment_touched — hcloud_volume_attachment.workspaces["web-1"]: detaching the live
#       /mnt/data strands sole-copy data.
#   - web1_server_touched    — hcloud_server.web["web-1"]: cx33 is unrebuildable in all 3 EU DCs, so
#       a destroyed/replaced web-1 is "the product is gone".
#   - luks_passphrase_touched — create/update/delete/forget (the FULL 4-verb — UNLIKE the cutover
#       gate) on random_password.workspaces_luks OR doppler_secret.workspaces_luks_key. The recut
#       reuses the existing key; any touch strands the at-rest data (C19/F4).
#   - luks_id_mismatch       — when the operator supplies the expected volume id, the replaced
#       volume's before.id must equal it (the ID-PIN above).
#   - resource_deletes       — a delete OR forget of ANYTHING EXCEPT the volume + its attachment
#       (both legitimately deleted as part of the replace). Any other delete/forget is out of shape.
#   - out_of_scope           — any positive (create/update/delete/forget) action on an address that
#       is NEITHER in the allow-set NOR one of the three named-live addresses. This is the sole
#       catcher of a touch on doppler_service_token.workspaces_luks (deliberately NOT named-live —
#       it must be untouched) and any other un-enumerated resource.
#
# NAMED-LIVE ⇄ web_hosts COUPLING (security-sentinel P3-3): the three live addresses below enumerate
# `hcloud_volume.workspaces` / `..._attachment.workspaces` / `hcloud_server.web` for the SINGLE key
# in `var.web_hosts` today (web-1; web-2 retired #6538, variables.tf). If web_hosts ever regains a
# key, add that host's three addresses here — a NEW host's live volume/attachment/server would still
# ABORT via the out_of_scope / resource_deletes catch-alls (data-safe), but the friendly per-address
# diagnostic would degrade to the generic out-of-scope message until enumerated here.
#
# NO [ack-destroy] BYPASS: the recut of a sole-copy-data volume is authorized by the environment
# reviewer gate (hr-menu-option-ack-not-prod-write-auth) — the job declares
# `environment: workspaces-luks-cutover` (non-empty reviewer set — DP-11 F8), never a commit trailer.
#
# The counters use the 4-verb POSITIVE-ACTION filter (create/update/delete/forget) — it excludes
# BOTH `no-op` AND `read`, so a live plan that lists the untargeted web-1 server / a `data.*` read
# as a no-op/read does NOT false-abort. A `removed{}`/`state rm` manifests as `forget`, not `delete`.
#
# Usage:  source tests/scripts/lib/workspaces-luks-recut-gate.sh
#         workspaces_luks_recut_gate <plan-json-file> [expected_luks_volume_id]   # 0=PASS, 1=ABORT

workspaces_luks_recut_gate() {
  local plan_json="$1"
  local expected_id="${2:-}"
  local counts vp ac ovt oat wst lpt idmm rd oos v

  if [[ ! -f "$plan_json" ]]; then
    echo "workspaces_luks_recut_gate: plan JSON not found: ${plan_json}"
    return 1
  fi
  # Read from the STRUCTURED plan JSON (terraform show -json), never stderr.
  # EXACT-EQUALITY membership via IN(.address; allow[]). Verified on jq 1.8.x.
  if ! counts=$(jq -n --slurpfile p "$plan_json" --arg expected "$expected_id" '
      def allow: [
        "hcloud_volume.workspaces_luks",
        "hcloud_volume_attachment.workspaces_luks"
      ];
      # The three LIVE addresses + the passphrase/secret are each guarded by their OWN named clause.
      # out_of_scope EXCLUDES them so those named clauses are the SOLE catcher of a touch on them —
      # making each independently load-bearing. doppler_service_token.workspaces_luks is INTENTIONALLY
      # absent here → a touch on it fires out_of_scope (it must stay untouched during a recut).
      def named_live: [
        "hcloud_volume.workspaces[\"web-1\"]",
        "hcloud_volume_attachment.workspaces[\"web-1\"]",
        "hcloud_server.web[\"web-1\"]",
        "random_password.workspaces_luks",
        "doppler_secret.workspaces_luks_key"
      ];
      def positive: (.change.actions? | any(. == "create" or . == "update" or . == "delete" or . == "forget"));
      $p[0] as $plan
      | {
          luks_volume_provisioned: (
            # A GENUINE replace (delete AND create, order-independent) OR the RECOVERY bare create
            # (["create"] with before == null — a stranded destroy-before-create re-dispatch). A bare
            # create with a NON-null before, or a delete/forget/update without a create, is neither
            # and ABORTS.
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_volume.workspaces_luks")
              | select(
                  ((.change.actions? | index("delete")) and (.change.actions? | index("create")))
                  or ((.change.actions? == ["create"]) and (.change.before == null))
                ) ]
            | length
          ),
          luks_attachment_created: (
            # The new volume must be re-attached to web-1. A replace also shows a delete of the old
            # attachment (legal — excluded from resource_deletes below); the create is required.
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_volume_attachment.workspaces_luks")
              | select(.change.actions? | index("create")) ]
            | length
          ),
          luks_id_mismatch: (
            # ID-PIN: when the operator supplies the expected physical volume id, the REPLACED volume
            # (the one carrying a non-null before.id — i.e. the volume being destroyed) must be that
            # exact id. A mismatch means the address resolves to a DIFFERENT physical volume than the
            # operator authorized (state corruption) — ABORT. Skipped when $expected is empty, and a
            # no-op for the recovery bare create (before == null → no before.id to destroy).
            if $expected == "" then 0
            else
              [ $plan.resource_changes[]?
                | select(.address == "hcloud_volume.workspaces_luks")
                | select((.change.before.id != null) and ((.change.before.id | tostring) != $expected)) ]
              | length
            end
          ),
          old_volume_touched: (
            # The LIVE plaintext /mnt/data. Its sole protection (#6593 shipped NO prevent_destroy).
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_volume.workspaces[\"web-1\"]")
              | select(positive) ]
            | length
          ),
          old_attachment_touched: (
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_volume_attachment.workspaces[\"web-1\"]")
              | select(positive) ]
            | length
          ),
          web1_server_touched: (
            # cx33 unrebuildable ⇒ a replaced/destroyed web-1 is unrecoverable.
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_server.web[\"web-1\"]")
              | select(positive) ]
            | length
          ),
          luks_passphrase_touched: (
            # FULL 4-verb (create INCLUDED — unlike the cutover gate). The recut REUSES the existing
            # header key; a create/update/delete/forget here opens a NEW header and strands the
            # at-rest data (the C19/F4 catastrophe).
            [ $plan.resource_changes[]?
              | select(.address == "random_password.workspaces_luks" or .address == "doppler_secret.workspaces_luks_key")
              | select(positive) ]
            | length
          ),
          resource_deletes: (
            # A delete/forget of ANY address EXCEPT the volume + its attachment (both legitimately
            # deleted as part of the replace, and each owned by its own named clause above). Any
            # OTHER delete/forget is out of shape.
            [ $plan.resource_changes[]?
              | select(.address != "hcloud_volume.workspaces_luks" and .address != "hcloud_volume_attachment.workspaces_luks")
              | select(.change.actions? | any(. == "delete" or . == "forget")) ]
            | length
          ),
          out_of_scope: (
            # Positive action on an address that is NEITHER in the allow-set NOR named-live.
            [ $plan.resource_changes[]?
              | select(positive)
              | select((IN(.address; allow[]) | not) and (IN(.address; named_live[]) | not)) ]
            | length
          )
        }
    ' 2>/dev/null); then
    echo "workspaces_luks_recut_gate: jq evaluation failed on ${plan_json}"
    return 1
  fi
  vp=$(echo "$counts" | jq -r '.luks_volume_provisioned')
  ac=$(echo "$counts" | jq -r '.luks_attachment_created')
  idmm=$(echo "$counts" | jq -r '.luks_id_mismatch')
  ovt=$(echo "$counts" | jq -r '.old_volume_touched')
  oat=$(echo "$counts" | jq -r '.old_attachment_touched')
  wst=$(echo "$counts" | jq -r '.web1_server_touched')
  lpt=$(echo "$counts" | jq -r '.luks_passphrase_touched')
  rd=$(echo "$counts" | jq -r '.resource_deletes')
  oos=$(echo "$counts" | jq -r '.out_of_scope')

  # Parse-validate every counter. A jq null/empty would evaluate false in the arithmetic below and
  # could silently mis-decide; fail LOUD instead.
  for v in "$vp" "$ac" "$idmm" "$ovt" "$oat" "$wst" "$lpt" "$rd" "$oos"; do
    if [[ ! "$v" =~ ^[0-9]+$ ]]; then
      echo "workspaces_luks_recut_gate: counter parse failed (luks_volume_provisioned='${vp}' luks_attachment_created='${ac}' luks_id_mismatch='${idmm}' old_volume_touched='${ovt}' old_attachment_touched='${oat}' web1_server_touched='${wst}' luks_passphrase_touched='${lpt}' resource_deletes='${rd}' out_of_scope='${oos}')"
      return 1
    fi
  done

  echo "luks_volume_provisioned=${vp} luks_attachment_created=${ac} luks_id_mismatch=${idmm} old_volume_touched=${ovt} old_attachment_touched=${oat} web1_server_touched=${wst} luks_passphrase_touched=${lpt} resource_deletes=${rd} out_of_scope=${oos}"
  if [[ "$vp" -ge 1 && "$ac" -ge 1 && "$idmm" -eq 0 && "$ovt" -eq 0 && "$oat" -eq 0 && "$wst" -eq 0 && "$lpt" -eq 0 && "$rd" -eq 0 && "$oos" -eq 0 ]]; then
    echo "workspaces_luks_recut_gate: PASS — scoped workspaces-luks recut permitted (volume REPLACED [or recovery-created] + attachment re-created; replaced-volume id matches the operator-supplied id; live plaintext volume/attachment + web-1 server untouched; passphrase reused, no re-mint; no out-of-scope delete or action)"
    return 0
  fi
  echo "workspaces_luks_recut_gate: ABORT — plan is NOT the exact scoped workspaces-luks recut (the LUKS volume must show a genuine replace [delete AND create] or a recovery bare create [before null] + the attachment a create; the replaced-volume id must match the operator-supplied expected id; a touch on the live plaintext volume/attachment or the web-1 server, a passphrase re-mint/touch, an out-of-scope delete, or an out-of-scope positive action all ABORT)"
  return 1
}
