# shellcheck shell=bash
# Sourced destroy-guard gate for the workspaces-luks-cutover scoped FIRST PROVISION
# (apply_target=workspaces-luks-cutover in .github/workflows/apply-web-platform-infra.yml, #6604).
#
# EXTRACTED + SOURCED (mirrors git-data-host-replace-gate.sh / registry-host-replace-gate.sh):
# both the workflow's workspaces_luks_cutover plan step AND
# tests/scripts/test-workspaces-luks-cutover-gate.sh source this file and call
# workspaces_luks_cutover_gate directly, so the CI decision logic is the SAME bytes the test
# exercises (no re-derived inline copy to drift).
#
# ⚠️ DP-1 (terraform-architect F1, P1) — THIS IS A FIRST PROVISION, NOT A HOST -replace.
# All FIVE workspaces_luks resources are OPERATOR_APPLIED_EXCLUSIONS not yet in state
# (terraform-target-parity.test.ts lists them + the token exclusion, "ride the operator's
# workspaces-luks-cutover dispatch apply"), so the create job's plan is a pure `+create` of
# ALL FIVE. The gate MUST PERMIT those creates. Copying git-data's `luks_passphrase_touched`
# clause verbatim (which counts create — correct for a -replace where the passphrase already
# exists in state) would ABORT the very provision this gate exists to authorize. Here
# `luks_passphrase_touched` counts update/delete/forget ONLY — a FIRST create is legal; a later
# re-mint is the F4 catastrophe.
#
# It reads a `terraform show -json <plan>` document and PERMITS EXACTLY the scoped
# workspaces-luks first provision: a `+create` of the five #6593-authored resources, and
# NOTHING else. The create job `-target`s exactly these five (precedent: warm-standby -targets
# exactly its excluded resources, apply-web-platform-infra.yml — never untargeted, which pulls
# unrelated drift):
#   - random_password.workspaces_luks         (workspaces-luks.tf:51 — the passphrase)
#   - doppler_secret.workspaces_luks_key       (workspaces-luks.tf:98 — REQUIRED: the escrow
#       proof + the host unlock read WORKSPACES_LUKS_KEY via the prd_workspaces_luks config)
#   - doppler_service_token.workspaces_luks     (workspaces-luks.tf:118 — the scoped read token)
#   - hcloud_volume.workspaces_luks             (workspaces-luks.tf:165 — the encrypted volume)
#   - hcloud_volume_attachment.workspaces_luks  (workspaces-luks.tf:185 — attaches it to web-1)
#
# THE SOLE-COPY-DATA BACKSTOPS (each named, operator-legible; several redundant with
# out_of_scope but they name the specific catastrophe):
#   - old_volume_touched     — hcloud_volume.workspaces["web-1"] (server.tf:1241, for_each) is
#       the LIVE plaintext /mnt/data. #6593 deliberately shipped NO `prevent_destroy` (it fails
#       the whole for_each plan). This counter IS AC20's STOP — the old volume's only protection.
#   - old_attachment_touched — hcloud_volume_attachment.workspaces["web-1"] (server.tf:1253):
#       detaching the live /mnt/data mid-cutover strands sole-copy data (terraform-architect F3).
#   - web1_server_touched    — hcloud_server.web["web-1"] (server.tf:99): cx33 is unrebuildable in
#       all 3 EU DCs, so a destroyed/replaced web-1 is "the product is gone", not "a workspace".
#   - luks_volume_destroyed  — a delete OR forget of the encrypted volume this job just created.
#   - luks_passphrase_touched — update/delete/forget (NEVER create) on random_password.workspaces_luks
#       OR doppler_secret.workspaces_luks_key: a re-mint opens a NEW header, stranding at-rest data
#       (the C19/F4 catastrophe). A FIRST create is legal; a later re-mint is not.
#   - resource_deletes       — a delete OR forget of ANYTHING: a pure `+create` provision has no
#       deletes, so any delete/forget is by definition out of shape.
#   - out_of_scope           — any positive (create/update/delete/forget) action on an address
#       NOT in the allow-set. Catches every un-enumerated touch directly.
#
# NO [ack-destroy] BYPASS: the first provision of a sole-copy-data volume is authorized by the
# menu-ack workflow_dispatch (hr-menu-option-ack-not-prod-write-auth), never a commit trailer.
#
# The "touched"/delete/out-of-scope counters use the git-data 4-verb POSITIVE-ACTION filter
# (create/update/delete/forget) — it excludes BOTH `no-op` AND `read`, so a live plan that lists
# the untargeted old volume / a `data.*` source read as a no-op/read does NOT false-abort. A
# `removed{}`/`state rm` manifests as `forget`, not `delete` — both are counted.
#
# Usage:  source tests/scripts/lib/workspaces-luks-cutover-gate.sh
#         workspaces_luks_cutover_gate <plan-json-file>   # 0=PASS, 1=ABORT

workspaces_luks_cutover_gate() {
  local plan_json="$1"
  local counts vc ac sc ovt oat wst lvd lpt rd oos v

  if [[ ! -f "$plan_json" ]]; then
    echo "workspaces_luks_cutover_gate: plan JSON not found: ${plan_json}"
    return 1
  fi
  # Read from the STRUCTURED plan JSON (terraform show -json), never stderr.
  # EXACT-EQUALITY membership via IN(.address; allow[]) — NOT `inside`/`contains`
  # (substring matching would false-match similar addresses). Verified on jq 1.8.x.
  if ! counts=$(jq -n --slurpfile p "$plan_json" '
      def allow: [
        "random_password.workspaces_luks",
        "doppler_secret.workspaces_luks_key",
        "doppler_service_token.workspaces_luks",
        "hcloud_volume.workspaces_luks",
        "hcloud_volume_attachment.workspaces_luks"
      ];
      # The three LIVE addresses each guarded by their OWN named clause (old_volume_touched /
      # old_attachment_touched / web1_server_touched). out_of_scope EXCLUDES them so those named
      # clauses are the SOLE catcher of a touch on them — making each independently load-bearing
      # (a future allow-set widening can no longer silently shift their coverage onto out_of_scope,
      # and the mutation test can isolate each). A touch on any of them still ABORTS (the named clause).
      def named_live: [
        "hcloud_volume.workspaces[\"web-1\"]",
        "hcloud_volume_attachment.workspaces[\"web-1\"]",
        "hcloud_server.web[\"web-1\"]"
      ];
      def positive: (.change.actions? | any(. == "create" or . == "update" or . == "delete" or . == "forget"));
      $p[0] as $plan
      | {
          luks_volume_created: (
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_volume.workspaces_luks")
              | select(.change.actions? | index("create")) ]
            | length
          ),
          luks_attachment_created: (
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_volume_attachment.workspaces_luks")
              | select(.change.actions? | index("create")) ]
            | length
          ),
          luks_secret_created: (
            # REQUIRED: the escrow proof (AC22) can only run AFTER this create — the host reads
            # WORKSPACES_LUKS_KEY via the prd_workspaces_luks doppler_secret. No secret ⇒ no unlock.
            [ $plan.resource_changes[]?
              | select(.address == "doppler_secret.workspaces_luks_key")
              | select(.change.actions? | index("create")) ]
            | length
          ),
          old_volume_touched: (
            # The AC20 STOP — the LIVE plaintext /mnt/data. #6593 shipped NO prevent_destroy; this
            # counter is the sole protection for the old volume. bracketed indexed address, 4-verb.
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_volume.workspaces[\"web-1\"]")
              | select(positive) ]
            | length
          ),
          old_attachment_touched: (
            # Detaching the live /mnt/data mid-cutover strands sole-copy data (F3).
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_volume_attachment.workspaces[\"web-1\"]")
              | select(positive) ]
            | length
          ),
          web1_server_touched: (
            # Highest-value: cx33 unrebuildable ⇒ a replaced/destroyed web-1 is unrecoverable.
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_server.web[\"web-1\"]")
              | select(positive) ]
            | length
          ),
          luks_volume_destroyed: (
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_volume.workspaces_luks")
              | select(.change.actions? | any(. == "delete" or . == "forget")) ]
            | length
          ),
          luks_passphrase_touched: (
            # DP-1: update/delete/forget ONLY, NEVER create. A FIRST create of the passphrase /
            # its doppler_secret is legal (this is a first provision); a later re-mint opens a
            # NEW header and strands the at-rest data (the C19/F4 catastrophe).
            [ $plan.resource_changes[]?
              | select(.address == "random_password.workspaces_luks" or .address == "doppler_secret.workspaces_luks_key")
              | select(.change.actions? | any(. == "update" or . == "delete" or . == "forget")) ]
            | length
          ),
          resource_deletes: (
            # A pure +create provision has NO deletes. Any delete/forget is out of shape — EXCEPT the
            # luks volume itself, which is owned by the named luks_volume_destroyed clause (so that
            # clause is the sole catcher of a luks-volume delete/forget and stays independently
            # load-bearing). A delete/forget of any OTHER resource still fires here.
            [ $plan.resource_changes[]?
              | select(.address != "hcloud_volume.workspaces_luks")
              | select(.change.actions? | any(. == "delete" or . == "forget")) ]
            | length
          ),
          out_of_scope: (
            # Positive action on an address that is NEITHER in the allow-set NOR one of the three
            # named live addresses (each owned by its own clause above). So out_of_scope catches only
            # GENUINELY un-enumerated addresses, and the named clauses solely own their addresses.
            [ $plan.resource_changes[]?
              | select(positive)
              | select((IN(.address; allow[]) | not) and (IN(.address; named_live[]) | not)) ]
            | length
          )
        }
    ' 2>/dev/null); then
    echo "workspaces_luks_cutover_gate: jq evaluation failed on ${plan_json}"
    return 1
  fi
  vc=$(echo "$counts" | jq -r '.luks_volume_created')
  ac=$(echo "$counts" | jq -r '.luks_attachment_created')
  sc=$(echo "$counts" | jq -r '.luks_secret_created')
  ovt=$(echo "$counts" | jq -r '.old_volume_touched')
  oat=$(echo "$counts" | jq -r '.old_attachment_touched')
  wst=$(echo "$counts" | jq -r '.web1_server_touched')
  lvd=$(echo "$counts" | jq -r '.luks_volume_destroyed')
  lpt=$(echo "$counts" | jq -r '.luks_passphrase_touched')
  rd=$(echo "$counts" | jq -r '.resource_deletes')
  oos=$(echo "$counts" | jq -r '.out_of_scope')

  # Parse-validate every counter. A jq null/empty would evaluate false in the
  # arithmetic below and could silently mis-decide; fail LOUD instead.
  for v in "$vc" "$ac" "$sc" "$ovt" "$oat" "$wst" "$lvd" "$lpt" "$rd" "$oos"; do
    if [[ ! "$v" =~ ^[0-9]+$ ]]; then
      echo "workspaces_luks_cutover_gate: counter parse failed (luks_volume_created='${vc}' luks_attachment_created='${ac}' luks_secret_created='${sc}' old_volume_touched='${ovt}' old_attachment_touched='${oat}' web1_server_touched='${wst}' luks_volume_destroyed='${lvd}' luks_passphrase_touched='${lpt}' resource_deletes='${rd}' out_of_scope='${oos}')"
      return 1
    fi
  done

  echo "luks_volume_created=${vc} luks_attachment_created=${ac} luks_secret_created=${sc} old_volume_touched=${ovt} old_attachment_touched=${oat} web1_server_touched=${wst} luks_volume_destroyed=${lvd} luks_passphrase_touched=${lpt} resource_deletes=${rd} out_of_scope=${oos}"
  if [[ "$vc" -ge 1 && "$ac" -ge 1 && "$sc" -ge 1 && "$ovt" -eq 0 && "$oat" -eq 0 && "$wst" -eq 0 && "$lvd" -eq 0 && "$lpt" -eq 0 && "$rd" -eq 0 && "$oos" -eq 0 ]]; then
    echo "workspaces_luks_cutover_gate: PASS — scoped workspaces-luks first provision permitted (volume + attachment + doppler_secret created; old plaintext volume/attachment + web-1 server untouched; no re-mint, no destroy, nothing out of scope)"
    return 0
  fi
  echo "workspaces_luks_cutover_gate: ABORT — plan is NOT the exact scoped workspaces-luks first provision (a touch on the old plaintext volume/attachment or the web-1 server, a luks-volume destroy/forget, a passphrase re-mint, any delete, an out-of-scope positive action, or a missing volume/attachment/secret create)"
  return 1
}
