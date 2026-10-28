# shellcheck shell=bash
# Sourced destroy-guard gate for the git-data-host-replace scoped -replace
# (apply_target=git-data-host-replace in .github/workflows/apply-web-platform-infra.yml, #6242).
#
# Two functions live here: git_data_host_replace_gate (the PRE-apply destroy-guard, #6242) and
# git_data_host_post_apply_assert (the post-apply backstop over the same saved plan, #10137; see the
# comment block above it near the end of this file).
#
# EXTRACTED + SOURCED (mirrors registry-host-replace-gate.sh / inngest-host-replace-gate.sh):
# both the workflow's git_data_host_replace plan step AND
# tests/scripts/test-git-data-host-replace-gate.sh source this file and call
# git_data_host_replace_gate directly, so the CI decision logic is the SAME bytes the test
# exercises (no re-derived inline copy to drift).
#
# SELF-CONTAINED jq: the git-data replace has a small, fixed allow-set, so the
# counter logic lives inline here (same posture as registry-host-replace-gate.sh).
#
# It reads a `terraform show -json <plan>` document and PERMITS EXACTLY the scoped
# git-data-host recreate: a -replace of hcloud_server.git_data + its id-referencing
# dependents (network + the LUKS volume attachment + firewall attachment):
#   - hcloud_server_network.git_data     (network.tf:48; server_id is ForceNew -> replace;
#       the ONLY private-net transport path 10.0.1.20 for web-host push/pull)
#   - hcloud_volume_attachment.git_data_luks  (git-data-luks.tf, `resource "hcloud_volume_attachment"
#       "git_data_luks"`; server_id ForceNew -> replace;
#       else /mnt/git-data-luks — the LUKS at-rest store — boots UNMOUNTED)
#   - hcloud_firewall_attachment.git_data     (git-data.tf, `resource "hcloud_firewall_attachment"
#       "git_data"`; server_ids update-in-place —
#       registry-style INCLUDE, NOT the inngest omission. A fresh Hetzner host has a public
#       IPv4/IPv6; without re-attaching the deny-all firewall it boots NAKED on its public IP.)
#
# DELIBERATELY DIFFERENT FROM REGISTRY (the data VOLUME is NOT in the allow-set):
#   - hcloud_volume.git_data_luks  (git-data-luks.tf, `resource "hcloud_volume" "git_data_luks"`) — LUKS at-rest store
# is PRESERVED BY OMISSION: an untargeted resource cannot be planned for destroy, so leaving
# it out of the -target set is simpler AND strictly safer than including it. Because it is
# OUTSIDE the allow-set, `out_of_scope` catches any positive action on it directly.
# Registry needed its `store_destroyed` named backstop only because its volume WAS in the
# allow-set (it rode a 10->30 GB resize); git-data has no pending resize, so the volume stays
# out and the named backstops below are INTENTIONALLY REDUNDANT — high-value error text, not
# the primary brake.
#
# RETIRED ADDRESSES (#11194, ADR-239 Amendment 2026-10-28): the plaintext pair
# hcloud_volume.git_data and hcloud_volume_attachment.git_data was destroyed at the provider on
# 2026-10-27 and left the HCL. Neither is in the allow-set, so a create/update/delete/forget on
# either is `out_of_scope` in every mode; there is deliberately NO separate counter for them (the
# single `out_of_scope` filter is the brake, and a second one could only disagree with it). The
# suite's RETIRED_ADDRS rows pin that refusal.
#
# LUKS-passphrase safety (CTO High-if-mis-scoped risk): random_password.git_data_luks and
# doppler_secret.git_data_luks_key are ALSO out of the allow-set. A rotated passphrase would
# luksFormat/luksOpen a NEW header on the fresh boot, STRANDING the existing at-rest data. The
# named `luks_passphrase_touched` backstop asserts ZERO actions on BOTH (redundant with
# out_of_scope, but names the specific catastrophe). The idempotent isLuks skip in
# cloud-init-git-data.yml:152-173 only preserves data when the passphrase is unchanged.
#
# LARGER + STRICTER than the inngest gate (positive NIC / store-attachment / firewall
# assertions, named volume + passphrase preserves). Do NOT "simplify" it to the inngest shape —
# a "server replaced but the store attachment or the NIC or the firewall stripped" plan must NOT
# pass, or the new host boots with the store unmounted / invisible on the private net / naked on
# its public IP.
#
# NO [ack-destroy] BYPASS: a destructive prod host recreate is authorized by the menu-ack
# workflow_dispatch (hr-menu-option-ack-not-prod-write-auth), never a commit trailer.
#
# out_of_scope uses the POSITIVE-ACTION filter (create/update/delete/forget) copied verbatim
# from registry-host-replace-gate.sh — it excludes BOTH `no-op` AND `read`, so a `data.*`
# source read (or any no-op dependency the -target set pulls in) does NOT false-abort.
#
# PASS (rc=0) iff:
#   out_of_scope==0 && luks_volume_destroyed==0 && luks_passphrase_touched==0 &&
#   server_replaced==1 && nic_recreated>=1 && luks_attachment_recreated>=1 && firewall_ok>=1
# luks_attachment_recreated is a counter symmetric to nic_recreated: the store attachment must
# show a `create`. If a future mis-edit dropped its -target the new host would boot with the store
# UNMOUNTED, yet server/nic/firewall could all still pass. An unmounted store is as broken as a
# no-NIC host, so assert it positively. luks_volume_destroyed / luks_passphrase_touched are named
# "must be preserved" backstops (operator-legible + GDPR-relevant: the LUKS volume is the Art.17
# at-rest store + rollback backstop).
#
# ROOT-KEY ARM (#8189, ADR-220, Guard 4). A plan that passes every counter above is still
# refused unless git_data_root_key_arm (git-data-root-key-arm-gate.sh) proves the recreated host
# carries exactly {default key, root key}, the root key resolved in prior_state and hashing
# to the committed anchor named by GIT_DATA_ROOT_KEY_FINGERPRINT_FILE. Unset or empty reads
# as a missing anchor and refuses. The allow-set above is unchanged.
#
# HOST-KEY PIN ARM (#7226, ADR-237, Guard 4). The replace also re-mints the git-data SSH host
# key and re-publishes its pin: the job adds -replace='tls_private_key.git_data_host_ssh' and
# -target='doppler_secret.git_data_ssh_host_key', so both addresses are in the allow-set and
# the plan must show exactly:
#   host_key_rotated == 1  the key is ["delete","create"], or ["create"] on the FIRST rotation
#                          (-replace on an address absent from state plans a plain create)
#   host_key_published == 1  the pin secret is create / update / replace
# Every other action on either address — a no-op key (re-uses a key a rooted host could have
# exfiltrated), a no-op secret (stale pin), a delete-only, a create-before-destroy key — scores
# 0 on its counter and ABORTs. (A separate `host_key_bad` counter existed and never decided:
# `terraform show -json` emits one entry per address, so `== 1` on each counter already
# excludes every other action. #7226 review removed it rather than keep a dead arm.)
#
# OUTPUT DISCIPLINE: this gate prints counters, verdicts and ADDRESSES only — never a
# .change.before / .change.after value. A replace plan's before-values carry the OLD user_data
# (which embeds the old host private key), and this output lands in a public Actions log.
# tests/scripts/test-git-data-host-replace-gate.sh HK12 plants a sentinel to hold that.
#
# Usage:  source tests/scripts/lib/git-data-host-replace-gate.sh
#         GIT_DATA_ROOT_KEY_FINGERPRINT_FILE=<path> git_data_host_replace_gate <plan-json-file> [replace|rotate]   # 0=PASS, 1=ABORT
#         git_data_host_post_apply_assert <plan-json-file> <replace|rotate>   # post-apply backstop (#10137), 0=PASS, 1=ABORT
#
# MODE=rotate (#8211 PR2 / ADR-220 D6 — `apply_target=git-data-host-rotate`): the ONE path
# permitted to touch the LUKS store, because a rotated passphrase can only pair with a FRESH
# volume (a new key against the retained volume can never luksOpen — the birth gate's
# luks_orphan_mint arm documents that failure). Rotate admits three more addresses into the
# allow-set and INVERTS the two preserve backstops into positive requirements:
#   hcloud_volume.git_data_luks        MUST be ["delete","create"]  (fresh LUKS store)
#   random_password.git_data_luks      MUST be ["delete","create"]  (re-minted passphrase)
#   doppler_secret.git_data_luks_key   MUST be create/update/replace (re-published)
# The workflow asserts served_repos=0 on the host (Better Stack readback) BEFORE this plan runs;
# the gate grades only the plan document.

# THE FAIL-CLOSED PREAMBLE (#6997). A gate that authorises destructive production
# infrastructure must never let "I could not check" read as "it is fine". These three
# assertions refuse a plan document the gate cannot READ, cannot CLASSIFY, or whose
# counters did not evaluate — the shapes that otherwise score zero-of-everything and PASS.
#
# The `declare -F` guard makes the source idempotent: the workflow step may have sourced
# the preamble already, in either order.
# shellcheck source=tests/scripts/lib/plan-gate-preamble.sh
if ! declare -F plan_gate_assert_readable >/dev/null 2>&1; then
  _GDHRG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=/dev/null
  source "${_GDHRG_DIR}/plan-gate-preamble.sh"
fi

# Sourced UNCONDITIONALLY (no declare -F guard): the file only defines functions, and a
# guard would let a same-named stub defined earlier in the shell stand in for the arm. A
# failed source leaves the function undefined, and the call below then returns 127 and
# refuses.
# shellcheck source=tests/scripts/lib/git-data-root-key-arm-gate.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/git-data-root-key-arm-gate.sh"

git_data_host_replace_gate() {
  local plan_json="$1" mode="${2:-replace}"
  local counts oos lvd lpt replaced nic latt fw hkr hkp lvr lpr lkp
  case "$mode" in
    replace|rotate) : ;;
    *) echo "git_data_host_replace_gate: unknown mode '${mode}' — wiring fault, refusing"; return 1 ;;
  esac

  # THE ASSERTS LIVE INSIDE THE FUNCTION, AS ITS FIRST STATEMENTS, because they consume
  # $plan_json — a FUNCTION PARAMETER that does not exist at file scope. (Not, as an
  # earlier revision claimed, because a file-scope failure would fail open: `set -e` is
  # armed at every gate source site in apply-web-platform-infra.yml, so a file-scope
  # failure fails CLOSED. Getting the right answer from the wrong mechanism is still a
  # defect when the mechanism ends up in an ADR.)
  #
  # `|| return 1` also catches a 127 undefined-function status, so a preamble that failed
  # to source aborts the gate rather than silently skipping the check.
  plan_gate_assert_readable     "git_data_host_replace_gate" "$plan_json" || return 1
  plan_gate_assert_classifiable "git_data_host_replace_gate" "$plan_json" || return 1

  # Read from the STRUCTURED plan JSON (terraform show -json), never stderr.
  # EXACT-EQUALITY membership via IN(.address; allow[]) — NOT `inside`/`contains`
  # (substring matching would false-match similar addresses). Verified on jq 1.8.x.
  if ! counts=$(jq -n --arg mode "$mode" --slurpfile p "$plan_json" '
      # Rotate adds the three addresses the D6 LUKS rotation legitimately replaces;
      # every other positive action is still out_of_scope in both modes.
      def allow: [
        "hcloud_server.git_data",
        "hcloud_server_network.git_data",
        "hcloud_volume_attachment.git_data_luks",
        "hcloud_firewall_attachment.git_data",
        "tls_private_key.git_data_host_ssh",
        "doppler_secret.git_data_ssh_host_key"
      ] + (if $mode == "rotate" then
        [ "hcloud_volume.git_data_luks",
          "random_password.git_data_luks",
          "doppler_secret.git_data_luks_key" ]
        else [] end);
      def hk_key: "tls_private_key.git_data_host_ssh";
      def hk_pin: "doppler_secret.git_data_ssh_host_key";
      def hk_key_ok: (.change.actions? == ["delete","create"]) or (.change.actions? == ["create"]);
      def hk_pin_ok: .change.actions? as $a | [["create"],["update"],["delete","create"],["create","delete"]] | any(.[]; . == $a);
      $p[0] as $plan
      | {
          out_of_scope: (
            [ $plan.resource_changes[]?
              | select(.change.actions? | any(. == "create" or . == "update" or . == "delete" or . == "forget"))
              | select(IN(.address; allow[]) | not) ]
            | length
          ),
          luks_volume_destroyed: (
            # Named backstop for the LUKS at-rest store
            # (git-data-luks.tf, `resource "hcloud_volume" "git_data_luks"`; Art.17 + rollback).
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
          ),
          host_key_rotated: ([ $plan.resource_changes[]? | select(.address == hk_key) | select(hk_key_ok) ] | length),
          host_key_published: ([ $plan.resource_changes[]? | select(.address == hk_pin) | select(hk_pin_ok) ] | length),
          # ROTATE-ONLY positive requirements (mode=rotate): a plain -replace of the LUKS
          # volume alone (no passphrase re-mint, no re-published key) is REFUSED — a new
          # passphrase against a retained volume cannot luksOpen, and a retained passphrase
          # is not a rotation. In mode=replace these counters stay 0 and are unused.
          luks_volume_rotated: (
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_volume.git_data_luks")
              | select(.change.actions? == ["delete","create"]) ]
            | length
          ),
          luks_passphrase_rotated: (
            [ $plan.resource_changes[]?
              | select(.address == "random_password.git_data_luks")
              | select(.change.actions? == ["delete","create"]) ]
            | length
          ),
          luks_key_published: (
            [ $plan.resource_changes[]?
              | select(.address == "doppler_secret.git_data_luks_key")
              | select(.change.actions? as $a | [["create"],["update"],["delete","create"],["create","delete"]] | any(.[]; . == $a)) ]
            | length
          )
        }
    ' 2>/dev/null); then
    echo "git_data_host_replace_gate: jq evaluation failed on ${plan_json}"
    return 1
  fi
  oos=$(echo "$counts" | jq -r '.out_of_scope')
  lvd=$(echo "$counts" | jq -r '.luks_volume_destroyed')
  lpt=$(echo "$counts" | jq -r '.luks_passphrase_touched')
  replaced=$(echo "$counts" | jq -r '.server_replaced')
  nic=$(echo "$counts" | jq -r '.nic_recreated')
  latt=$(echo "$counts" | jq -r '.luks_attachment_recreated')
  fw=$(echo "$counts" | jq -r '.firewall_ok')
  hkr=$(echo "$counts" | jq -r '.host_key_rotated')
  hkp=$(echo "$counts" | jq -r '.host_key_published')
  lvr=$(echo "$counts" | jq -r '.luks_volume_rotated')
  lpr=$(echo "$counts" | jq -r '.luks_passphrase_rotated')
  lkp=$(echo "$counts" | jq -r '.luks_key_published')

  # Every counter is a non-negative integer BEFORE any arithmetic compares one.
  # A counter that did not evaluate is the empty string, and [[ "" -gt 0 ]] is FALSE
  # under bash coercion — so an uncomputed counter silently satisfies every threshold.
  # The shared helper names WHICH counter failed rather than reporting them all.
  plan_gate_assert_numeric "git_data_host_replace_gate" "out_of_scope=${oos}" "luks_volume_destroyed=${lvd}" "luks_passphrase_touched=${lpt}" "server_replaced=${replaced}" "nic_recreated=${nic}" "luks_attachment_recreated=${latt}" "firewall_ok=${fw}" "host_key_rotated=${hkr}" "host_key_published=${hkp}" "luks_volume_rotated=${lvr}" "luks_passphrase_rotated=${lpr}" "luks_key_published=${lkp}" || return 1

  echo "out_of_scope=${oos} luks_volume_destroyed=${lvd} luks_passphrase_touched=${lpt} server_replaced=${replaced} nic_recreated=${nic} luks_attachment_recreated=${latt} firewall_ok=${fw} host_key_rotated=${hkr} host_key_published=${hkp} mode=${mode} luks_volume_rotated=${lvr} luks_passphrase_rotated=${lpr} luks_key_published=${lkp}"
  local luks_ok
  if [[ "$mode" = rotate ]]; then
    # Rotate: the preserve backstops INVERT into positive requirements. The LUKS volume
    # must be delete+create WITH a re-minted passphrase AND a re-published key — a partial
    # rotation is a stranding, not a rotate.
    luks_ok=$(( lvr == 1 && lpr == 1 && lkp == 1 ))
  else
    luks_ok=$(( lvd == 0 && lpt == 0 ))
  fi
  if [[ "$oos" -eq 0 && "$luks_ok" -eq 1 && "$replaced" -eq 1 && "$nic" -ge 1 && "$latt" -ge 1 && "$fw" -ge 1 && "$hkr" -eq 1 && "$hkp" -eq 1 ]]; then
    git_data_root_key_arm "$plan_json" "${GIT_DATA_ROOT_KEY_FINGERPRINT_FILE:-}" || return 1
    if [[ "$mode" = rotate ]]; then
      echo "git_data_host_replace_gate: PASS — scoped git-data-host ROTATE permitted (server + dependents + LUKS volume/passphrase/key all re-minted together; NIC + LUKS store attachment + deny-all firewall re-attached; SSH host key rotated and its pin re-published)"
    else
      echo "git_data_host_replace_gate: PASS — scoped git-data-host recreate permitted (server + dependents; the LUKS data volume + LUKS passphrase preserved by omission; NIC + LUKS store attachment + deny-all firewall re-attached; SSH host key rotated and its pin re-published)"
    fi
    return 0
  fi
  if [[ "$mode" = rotate ]]; then
    echo "git_data_host_replace_gate: ABORT — plan is NOT the exact scoped git-data-host ROTATE (out-of-scope change, an INCOMPLETE LUKS rotation [volume/passphrase/key must all move together — a new passphrase on the retained volume cannot luksOpen], no server replace, stripped private NIC, an unmounted store, a stripped firewall, or an SSH host key/pin not rotated and re-published)"
  else
    echo "git_data_host_replace_gate: ABORT — plan is NOT the exact scoped git-data-host recreate (out-of-scope change, a LUKS volume destroy/forget, a LUKS passphrase rotation, no server replace, stripped private NIC, an unmounted store [the volume-attachment not re-created], a stripped firewall, or an SSH host key that was not rotated with the host / a pin that was not re-published)"
  fi
  return 1
}

# git_data_host_post_apply_assert <plan-json-file> <replace|rotate>   # 0=PASS, 1=ABORT
#
# THE POST-APPLY BACKSTOP (#10137). The apply step of job git_data_host_replace re-reads the
# SAVED plan it just applied and asserts, belt-and-suspenders to git_data_host_replace_gate:
#   - in replace mode the LUKS data volume shows no delete/forget action,
#   - the private NIC and the LUKS store attachment show a create (re-attached).
# The volume assertion is per mode: replace keeps the LUKS volume, rotate asserts none — rotate
# replaces hcloud_volume.git_data_luks on purpose, and the pre-apply gate already requires
# luks_volume_rotated == 1 on the same plan, so no second positive LUKS assertion is made here. The
# retired plaintext pair is not asserted (it is out of the HCL and state; the pre-apply gate refuses
# any positive action on it). The mode is the one the plan step's gate accepted (the workflow
# publishes it as that step's gate_mode output); an unknown, empty or absent mode is a wiring fault
# and refuses.
#
# FAIL-CLOSED: `{"resource_changes":[]}` passes the readable and classifiable arms, so an empty
# plan is rejected by the positive NIC / attachment creates, never by a count. Every jq result is
# compared `!= "0"` / `== "0"` so an empty string (jq failed) refuses rather than satisfies.
# Callers must use `if ! git_data_host_post_apply_assert ...; then exit 1; fi` — a bare call under
# `set +e` fails open.
# WHAT THIS READS: the SAVED plan, written before `terraform apply` ran. It reads no state and calls
# no API, so it is the pre-apply gate's own bytes graded again after the apply has COMPLETED. A
# refusal is therefore detective: the infrastructure has already changed. Wording below says "saved
# plan shows" for that reason, never "the volume is preserved" as an observed outcome.
# The LUKS VOLUME is matched by the plan's own `.type` + `.name` (which cover root, indexed and
# module-prefixed resources whatever the index key holds), with an address fallback for root and
# indexed addresses, so a later `count`, `for_each` or module move of the data volume cannot make
# the check count zero and pass. This is deliberately BROADER than the sibling gates' exact-address
# match: a zero count here reads as "preserved", so the fail-closed direction is the wider net.
# OUTPUT DISCIPLINE: addresses and counts only, never a .change.before/.change.after value.
git_data_host_post_apply_assert() {
  local plan_json="$1" mode="${2:-}"
  local vol_deletes nic_creates att att_creates safe_mode
  case "$mode" in
    replace|rotate) : ;;
    *)
      safe_mode="${mode//[^A-Za-z_-]/?}"
      echo "git_data_host_post_apply_assert: unknown mode '${safe_mode:0:16}' — wiring fault, refusing"
      return 1 ;;
  esac
  plan_gate_assert_readable     "git_data_host_post_apply_assert" "$plan_json" || return 1
  plan_gate_assert_classifiable "git_data_host_post_apply_assert" "$plan_json" || return 1
  if [[ "$mode" == replace ]]; then
    vol_deletes=$(jq '"hcloud_volume.git_data_luks" as $r | [.resource_changes[]?
      | select((.type == "hcloud_volume" and .name == "git_data_luks")
               or ((.address // "") as $a | $a == $r or ($a | startswith($r + "["))))
      | select(.change.actions? | any(. == "delete" or . == "forget"))] | length' "$plan_json" 2>/dev/null) || vol_deletes=""
    if [[ "$vol_deletes" != "0" ]]; then
      echo "::error::hcloud_volume.git_data_luks shows ${vol_deletes:-<unreadable>} delete/forget action(s) in the saved plan that was applied — the data store must be preserved, and the apply has already completed. This should have been caught by the guard; failing hard."
      return 1
    fi
  fi
  nic_creates=$(jq '[.resource_changes[]?
    | select(.address == "hcloud_server_network.git_data")
    | select(.change.actions? | index("create"))] | length' "$plan_json" 2>/dev/null) || nic_creates=""
  if [[ ! "$nic_creates" =~ ^[1-9][0-9]*$ ]]; then
    echo "::error::hcloud_server_network.git_data shows no create action in the saved plan that was applied — the new host would have no private NIC. This should have been caught by the guard; failing hard."
    return 1
  fi
  for att in hcloud_volume_attachment.git_data_luks; do
    att_creates=$(jq --arg a "$att" '[.resource_changes[]?
      | select(.address == $a)
      | select(.change.actions? | index("create"))] | length' "$plan_json" 2>/dev/null) || att_creates=""
    if [[ ! "$att_creates" =~ ^[1-9][0-9]*$ ]]; then
      echo "::error::${att} shows no create action in the saved plan that was applied — the new host would boot with that store UNMOUNTED. This should have been caught by the guard; failing hard."
      return 1
    fi
  done
  if [[ "$mode" = rotate ]]; then
    echo "LUKS volume replaced as intended by the rotate arm; private NIC + LUKS store attachment re-attached (create present) in the saved plan."
  else
    echo "LUKS data volume preserved (saved plan shows 0 delete/forget), private NIC + LUKS store attachment re-attached (create present) in the saved plan."
  fi
  return 0
}
