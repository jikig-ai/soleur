# shellcheck shell=bash
# Sourced destroy-guard gate for the git-data-host-replace scoped -replace
# (apply_target=git-data-host-replace in .github/workflows/apply-web-platform-infra.yml, #6242).
#
# EXTRACTED + SOURCED (mirrors registry-host-replace-gate.sh / inngest-host-replace-gate.sh):
# both the workflow's git_data_host_replace plan step AND
# tests/scripts/test-git-data-host-replace-gate.sh source this file and call
# git_data_host_replace_gate directly, so the CI decision logic is the SAME bytes the test
# exercises (no re-derived inline copy to drift).
#
# SELF-CONTAINED jq: the git-data replace has a small, fixed 5-member allow-set, so the
# counter logic lives inline here (same posture as registry-host-replace-gate.sh).
#
# It reads a `terraform show -json <plan>` document and PERMITS EXACTLY the scoped
# git-data-host recreate: a -replace of hcloud_server.git_data + its 4 id-referencing
# dependents (network + BOTH volume attachments + firewall attachment):
#   - hcloud_server_network.git_data     (network.tf:48; server_id is ForceNew -> replace;
#       the ONLY private-net transport path 10.0.1.20 for web-host push/pull)
#   - hcloud_volume_attachment.git_data       (git-data.tf:207; server_id ForceNew -> replace;
#       else /mnt/git-data — the plaintext bare-repo store — boots UNMOUNTED)
#   - hcloud_volume_attachment.git_data_luks  (git-data-luks.tf:90; server_id ForceNew -> replace;
#       else /mnt/git-data-luks — the LUKS at-rest store — boots UNMOUNTED)
#   - hcloud_firewall_attachment.git_data     (git-data.tf:228; server_ids update-in-place —
#       registry-style INCLUDE, NOT the inngest omission. A fresh Hetzner host has a public
#       IPv4/IPv6; without re-attaching the deny-all firewall it boots NAKED on its public IP.)
#
# DELIBERATELY DIFFERENT FROM REGISTRY (the two data VOLUMES are NOT in the allow-set):
#   - hcloud_volume.git_data       (git-data.tf:196) — plaintext bare-repo store, and
#   - hcloud_volume.git_data_luks  (git-data-luks.tf:79) — LUKS at-rest store
# are PRESERVED BY OMISSION: an untargeted resource cannot be planned for destroy, so leaving
# them out of the -target set is simpler AND strictly safer than including them. Because they
# are OUTSIDE the allow-set, `out_of_scope` catches any positive action on them directly.
# Registry needed its `store_destroyed` named backstop only because its volume WAS in the
# allow-set (it rode a 10->30 GB resize); git-data has no pending resize, so the volumes stay
# out and the named backstops below are INTENTIONALLY REDUNDANT — high-value error text, not
# the primary brake.
#
# LUKS-passphrase safety (CTO High-if-mis-scoped risk): random_password.git_data_luks and
# doppler_secret.git_data_luks_key are ALSO out of the allow-set. A rotated passphrase would
# luksFormat/luksOpen a NEW header on the fresh boot, STRANDING the existing at-rest data. The
# named `luks_passphrase_touched` backstop asserts ZERO actions on BOTH (redundant with
# out_of_scope, but names the specific catastrophe). The idempotent isLuks skip in
# cloud-init-git-data.yml:142-163 only preserves data when the passphrase is unchanged.
#
# LARGER + STRICTER than the inngest gate (5-member allow-set, positive NIC / BOTH-attachment /
# firewall assertions, named volume + passphrase preserves). Do NOT "simplify" it to the
# inngest or single-attachment shape — a "server replaced but a store attachment or the NIC or
# the firewall stripped" plan must NOT pass, or the new host boots with a store unmounted /
# invisible on the private net / naked on its public IP.
#
# NO [ack-destroy] BYPASS: a destructive prod host recreate is authorized by the menu-ack
# workflow_dispatch (hr-menu-option-ack-not-prod-write-auth), never a commit trailer.
#
# out_of_scope uses the POSITIVE-ACTION filter (create/update/delete/forget) copied verbatim
# from registry-host-replace-gate.sh — it excludes BOTH `no-op` AND `read`, so a `data.*`
# source read (or any no-op dependency the -target set pulls in) does NOT false-abort.
#
# PASS (rc=0) iff:
#   out_of_scope==0 && git_data_volume_destroyed==0 && luks_volume_destroyed==0 &&
#   luks_passphrase_touched==0 && server_replaced==1 && nic_recreated>=1 &&
#   plaintext_attachment_recreated>=1 && luks_attachment_recreated>=1 && firewall_ok>=1
# plaintext_attachment_recreated / luks_attachment_recreated are SEPARATE counters (symmetric to
# nic_recreated): each store attachment must show a `create`. If a future mis-edit dropped one
# -target the new host would boot with that store UNMOUNTED, yet server/nic/firewall/other-store
# could all still pass. An unmounted store is as broken as a no-NIC host, so assert each
# positively. git_data_volume_destroyed / luks_volume_destroyed / luks_passphrase_touched are
# named "must be preserved" backstops (operator-legible + GDPR-relevant: the LUKS volume is the
# Art.17 at-rest store + rollback backstop).
#
# Usage:  source tests/scripts/lib/git-data-host-replace-gate.sh
#         git_data_host_replace_gate <plan-json-file>   # 0=PASS, 1=ABORT

git_data_host_replace_gate() {
  local plan_json="$1"
  local counts oos gvd lvd lpt replaced nic patt latt fw v

  if [[ ! -f "$plan_json" ]]; then
    echo "git_data_host_replace_gate: plan JSON not found: ${plan_json}"
    return 1
  fi
  # Read from the STRUCTURED plan JSON (terraform show -json), never stderr.
  # EXACT-EQUALITY membership via IN(.address; allow[]) — NOT `inside`/`contains`
  # (substring matching would false-match similar addresses). Verified on jq 1.8.x.
  if ! counts=$(jq -n --slurpfile p "$plan_json" '
      def allow: [
        "hcloud_server.git_data",
        "hcloud_server_network.git_data",
        "hcloud_volume_attachment.git_data",
        "hcloud_volume_attachment.git_data_luks",
        "hcloud_firewall_attachment.git_data"
      ];
      $p[0] as $plan
      | {
          out_of_scope: (
            [ $plan.resource_changes[]?
              | select(.change.actions? | any(. == "create" or . == "update" or . == "delete" or . == "forget"))
              | select(IN(.address; allow[]) | not) ]
            | length
          ),
          git_data_volume_destroyed: (
            # Named backstop for the plaintext bare-repo store (git-data.tf:196). It is OUT of
            # the allow-set, so out_of_scope already catches any positive action — this is the
            # operator-legible "your git history would be destroyed" line.
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_volume.git_data")
              | select(.change.actions? | any(. == "delete" or . == "forget")) ]
            | length
          ),
          luks_volume_destroyed: (
            # Named backstop for the LUKS at-rest store (git-data-luks.tf:79; Art.17 + rollback).
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_volume.git_data_luks")
              | select(.change.actions? | any(. == "delete" or . == "forget")) ]
            | length
          ),
          luks_passphrase_touched: (
            # CTO High-if-mis-scoped: a rotated passphrase opens a NEW LUKS header on fresh boot,
            # stranding the old at-rest data. BOTH the random_password AND its doppler_secret must
            # show ZERO positive actions. Redundant with out_of_scope (both are out of the
            # allow-set) but names the specific catastrophe.
            [ $plan.resource_changes[]?
              | select(.address == "random_password.git_data_luks" or .address == "doppler_secret.git_data_luks_key")
              | select(.change.actions? | any(. == "create" or . == "update" or . == "delete" or . == "forget")) ]
            | length
          ),
          server_replaced: (
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_server.git_data")
              | select((.change.actions? | index("delete")) and (.change.actions? | index("create"))) ]
            | length
          ),
          nic_recreated: (
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_server_network.git_data")
              | select(.change.actions? | index("create")) ]
            | length
          ),
          plaintext_attachment_recreated: (
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_volume_attachment.git_data")
              | select(.change.actions? | index("create")) ]
            | length
          ),
          luks_attachment_recreated: (
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_volume_attachment.git_data_luks")
              | select(.change.actions? | index("create")) ]
            | length
          ),
          firewall_ok: (
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_firewall_attachment.git_data")
              | select((.change.actions? == ["update"]) or (.change.actions? == ["create"])) ]
            | length
          )
        }
    ' 2>/dev/null); then
    echo "git_data_host_replace_gate: jq evaluation failed on ${plan_json}"
    return 1
  fi
  oos=$(echo "$counts" | jq -r '.out_of_scope')
  gvd=$(echo "$counts" | jq -r '.git_data_volume_destroyed')
  lvd=$(echo "$counts" | jq -r '.luks_volume_destroyed')
  lpt=$(echo "$counts" | jq -r '.luks_passphrase_touched')
  replaced=$(echo "$counts" | jq -r '.server_replaced')
  nic=$(echo "$counts" | jq -r '.nic_recreated')
  patt=$(echo "$counts" | jq -r '.plaintext_attachment_recreated')
  latt=$(echo "$counts" | jq -r '.luks_attachment_recreated')
  fw=$(echo "$counts" | jq -r '.firewall_ok')

  # Parse-validate every counter. A jq null/empty would evaluate false in the
  # arithmetic below and could silently mis-decide; fail LOUD instead.
  for v in "$oos" "$gvd" "$lvd" "$lpt" "$replaced" "$nic" "$patt" "$latt" "$fw"; do
    if [[ ! "$v" =~ ^[0-9]+$ ]]; then
      echo "git_data_host_replace_gate: counter parse failed (out_of_scope='${oos}' git_data_volume_destroyed='${gvd}' luks_volume_destroyed='${lvd}' luks_passphrase_touched='${lpt}' server_replaced='${replaced}' nic_recreated='${nic}' plaintext_attachment_recreated='${patt}' luks_attachment_recreated='${latt}' firewall_ok='${fw}')"
      return 1
    fi
  done

  echo "out_of_scope=${oos} git_data_volume_destroyed=${gvd} luks_volume_destroyed=${lvd} luks_passphrase_touched=${lpt} server_replaced=${replaced} nic_recreated=${nic} plaintext_attachment_recreated=${patt} luks_attachment_recreated=${latt} firewall_ok=${fw}"
  if [[ "$oos" -eq 0 && "$gvd" -eq 0 && "$lvd" -eq 0 && "$lpt" -eq 0 && "$replaced" -eq 1 && "$nic" -ge 1 && "$patt" -ge 1 && "$latt" -ge 1 && "$fw" -ge 1 ]]; then
    echo "git_data_host_replace_gate: PASS — scoped git-data-host recreate permitted (server + 4 dependents; BOTH data volumes + LUKS passphrase preserved by omission; NIC + both store attachments + deny-all firewall re-attached)"
    return 0
  fi
  echo "git_data_host_replace_gate: ABORT — plan is NOT the exact scoped git-data-host recreate (out-of-scope change, a git-data/LUKS volume destroy/forget, a LUKS passphrase rotation, no server replace, stripped private NIC, an unmounted store [a volume-attachment not re-created], or a stripped firewall)"
  return 1
}
