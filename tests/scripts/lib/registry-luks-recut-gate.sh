# shellcheck shell=bash
# Sourced destroy-guard gate for the registry-LUKS-RECUT apply path
# (apply_target=registry-luks-recut in .github/workflows/apply-web-platform-infra.yml, #6929).
#
# EXTRACTED + SOURCED (mirrors registry-region-migrate-gate.sh / registry-host-replace-gate.sh):
# both the workflow's registry_luks_recut plan step AND
# tests/scripts/test-registry-luks-recut-gate.sh source this file and call
# registry_luks_recut_gate directly, so the CI decision logic is the SAME bytes the test
# exercises (no re-derived inline copy to drift).
#
# ── WHY THIS GATE EXISTS (the footgun it removes) ──────────────────────────────────────────
# The 2026-07-24 guest-side-LUKS change made hcloud_volume.registry a RAW device: cloud-init
# now discriminates on `blkid TYPE` with three arms — "" (fresh) -> luksFormat; crypto_LUKS ->
# reuse; ANY OTHER TYPE -> `refusing-non-luks-device … exit 1`. The live volume is still
# PLAINTEXT ext4, so it sits in that third arm.
#
# The operator must therefore NOT use `registry-host-replace` to perform the recut: that path
# PRESERVES the volume (store_destroyed==0), so the replaced host boots cloud-init against the
# still-plaintext device, FATALs, and DARKS THE REGISTRY. Forgetting the `-replace` on the
# volume has exactly the same effect. This gate is the sanctioned vehicle: it admits ONLY a
# plan that replaces the volume, its attachment and the server TOGETHER, so a fresh raw volume
# meets the `blkid` empty arm and gets luksFormatted.
#
# ── DELTA vs registry-region-migrate-gate.sh (read this before assuming they are redundant) ──
# registry_region_migrate_gate's PASS predicate WOULD PASS the canonical recut plan: it asserts
# positive CREATES (server, volume, NIC, attachment) and a replace's actions include "create".
# So this is NOT a different gate — it is that gate PLUS strictness clauses that the region
# migration has no reason to carry:
#   1. an ARM SELECTOR keyed on the plan's own delete-set (a region migration is always the
#      bare-create shape; a recut is normally the replace shape);
#   2. a per-CHANGE ID-PIN (D9) — the region gate is deliberately location-agnostic and pins
#      nothing, so it cannot tell one physical volume from another;
#   3. a full 4-verb named-live clause on the LUKS key + password (D6), which did not exist
#      when the region gate was written;
#   4. a live-probe precondition on the resume arm (D4).
# The two gates are INVERSE on the one axis that matters (volume preserved vs volume replaced),
# and tests/scripts/test-registry-luks-recut-gate.sh enforces that divergence mechanically:
# harmonising them silently re-arms the footgun this issue exists to remove.
#
# ── DO NOT WIDEN THE ALLOW-SET (#6497) ─────────────────────────────────────────────────────
# out_of_scope==0 over a 6-member allow-set is the ONLY thing standing between this dispatch
# and the other tenants of the shared, LOCK-LESS (`use_lockfile = false`)
# terraform-apply-web-platform-host state: hcloud_server.web["web-1"] (unrebuildable cx33, no
# automated birth path — #6730) and hcloud_volume.workspaces (the sole copy of /mnt/data).
# If a plan aborts on out_of_scope, RECONCILE THE PLAN — never add the offending address here.
#
# The firewall attachment legitimately shows `update` in-place (a server_ids change) OR
# `create` (a fresh attachment to the new server); both are admitted, a `delete` is not — a
# registry with no firewall attachment is naked on its public IP.
#
# NO [ack-destroy] BYPASS: a destructive prod recut is authorized by the menu-ack
# workflow_dispatch + typed confirm (hr-menu-option-ack-not-prod-write-auth), never a commit
# trailer.
#
# SOLEUR-DEBT: 6th near-identical sourced destroy-guard (allow-set + positive-action filter +
# counter parse-loop + verdict scaffold are byte-shared with registry-region-migrate-gate.sh and
# registry-host-replace-gate.sh); extract a shared allow-set + counter-scaffold helper when a
# 7th gate lib lands OR when any registry address must change in >1 gate in the same PR.
#
# ── ARMS ────────────────────────────────────────────────────────────────────────────────────
# The arm is derived from the PLAN, never from an argument (v1 selected it with a shell flag,
# which let a recovery flag passed on a genuine replace of the WRONG volume yield
# volume_id_mismatch=0 — reintroducing one layer up the exact hole the id-pin exists to close).
#
# Selection is THREE-WAY, not two — the third case is the whole point of this gate:
#
#   RECUT arm      — the plan contains a delete/forget on hcloud_volume.registry.
#                    Requires the full replace shape + a strict per-change id-pin.
#   RESUME arm     — the plan contains ZERO deletes/forgets ANYWHERE, so it cannot destroy
#                    anything BY CONSTRUCTION. Covers all three mid-apply failure windows. It
#                    is admitted ONLY when the caller passes probe_result="absent", i.e. a live
#                    Hetzner GET proved the pinned volume is really gone — the one piece of
#                    evidence that is INDEPENDENT of the terraform state the gate is guarding.
#                    Without that probe the arm refuses to run at all.
#   PRESERVE-STORE — the plan destroys SOMETHING but NOT the store volume. This is exactly the
#                    registry-host-replace footgun (server replaced, store preserved) and it is
#                    NEITHER arm. It is scored under the strict RECUT rules so that
#                    volume_provisioned=0 names the real problem in the counter line.
#
#                    Folding this case into the permissive resume arm — the obvious two-way
#                    reading of "no volume delete ⇒ resume" — would let a `no-op` volume satisfy
#                    volume_provisioned and PASS the gate that exists to reject it. The
#                    volume-no-op case in the test suite pins this.
#
# PASS (rc=0) iff:
#   out_of_scope==0 && logs_secret_destroyed==0 && luks_key_touched==0 && volume_id_mismatch==0 &&
#   server_provisioned>=1 && volume_provisioned>=1 && attachment_created>=1 &&
#   nic_created>=1 && firewall_ok>=1
#   ... plus completion_progress>=1 in the RESUME arm.
#
# Usage:  source tests/scripts/lib/registry-luks-recut-gate.sh
#         registry_luks_recut_gate <plan-json> <expected_volume_id> [probe_result]
#         # 0=PASS, 1=ABORT

# THE FAIL-CLOSED PREAMBLE (#6997). A gate that authorises destructive production
# infrastructure must never let "I could not check" read as "it is fine". These three
# assertions refuse a plan document the gate cannot READ, cannot CLASSIFY, or whose
# counters did not evaluate — the shapes that otherwise score zero-of-everything and PASS.
#
# The `declare -F` guard makes the source idempotent: the workflow step may have sourced
# the preamble already, in either order.
# shellcheck source=tests/scripts/lib/plan-gate-preamble.sh
if ! declare -F plan_gate_assert_readable >/dev/null 2>&1; then
  _RLRG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=/dev/null
  source "${_RLRG_DIR}/plan-gate-preamble.sh"
fi

registry_luks_recut_gate() {
  local plan_json="${1-}" expected="${2-}" probe="${3-}"
  local counts arm oos logsdel luks vmis srv vol att nic fw prog

  # THE ASSERTS LIVE INSIDE THE FUNCTION, AS ITS FIRST STATEMENTS, because they consume
  # $plan_json — a FUNCTION PARAMETER that does not exist at file scope. (Not, as an
  # earlier revision claimed, because a file-scope failure would fail open: `set -e` is
  # armed at every gate source site in apply-web-platform-infra.yml, so a file-scope
  # failure fails CLOSED. Getting the right answer from the wrong mechanism is still a
  # defect when the mechanism ends up in an ADR.)
  #
  # `|| return 1` also catches a 127 undefined-function status, so a preamble that failed
  # to source aborts the gate rather than silently skipping the check.
  plan_gate_assert_readable     "registry_luks_recut_gate" "$plan_json" || return 1
  plan_gate_assert_classifiable "registry_luks_recut_gate" "$plan_json" || return 1


  # FAIL-CLOSED ON OUR OWN ARGUMENT. The sibling workspaces-luks-recut gate treats an empty
  # $expected as "skip the id-pin"; inheriting that idiom here would silently disarm the one
  # check that distinguishes the authorized physical volume from any other. An id that is not
  # a bare positive integer is a caller bug, not a permission to proceed.
  if [[ ! "$expected" =~ ^[0-9]+$ ]]; then
    echo "registry_luks_recut_gate: ABORT — expected_registry_store_volume_id must be a numeric Hetzner volume id (got '${expected}'). Read it with: curl -s -H \"Authorization: Bearer \$HCLOUD_TOKEN\" 'https://api.hetzner.cloud/v1/volumes?name=soleur-registry-store' | jq -r '.volumes[0].id'"
    return 1
  fi

  # Read from the STRUCTURED plan JSON (terraform show -json), never stderr.
  # EXACT-EQUALITY membership via IN(.address; allow[]) — NOT `inside`/`contains`.
  # The POSITIVE-ACTION filter (create/update/delete/forget) excludes BOTH `no-op` AND `read`,
  # so a data.* source read (or any no-op dependency the -target set pulls in) cannot
  # false-abort.
  if ! counts=$(jq -n --slurpfile p "$plan_json" --arg expected "$expected" '
      def allow: [
        "hcloud_server.registry",
        "hcloud_server_network.registry",
        "hcloud_volume_attachment.registry",
        "hcloud_firewall_attachment.registry",
        "hcloud_volume.registry",
        "doppler_secret.registry_betterstack_logs_token"
      ];
      # NAMED-LIVE: excluded from out_of_scope so their own clause is the sole, legible catcher.
      def named_live: [
        "doppler_secret.registry_luks_key",
        "random_password.registry_luks"
      ];
      def positive: (.change.actions? | any(. == "create" or . == "update" or . == "delete" or . == "forget"));
      def destroys: (.change.actions? | any(. == "delete" or . == "forget"));
      def acts($a): [ $p[0].resource_changes[]? | select(.address == $a) ];

      $p[0] as $plan
      # ARM SELECTION — derived from the plan itself (see header).
      | ( [ $plan.resource_changes[]?
            | select(.address == "hcloud_volume.registry")
            | select(destroys) ] | length ) as $vol_destroys
      | ( [ $plan.resource_changes[]? | select(destroys) ] | length ) as $any_destroys
      # THREE-WAY, not two. A plan that destroys SOMETHING but NOT the store volume is neither
      # arm — it is precisely the registry-host-replace footgun (server replaced, store
      # preserved), and folding it into the permissive resume arm would let a `no-op` volume
      # satisfy volume_provisioned and PASS the gate that exists to reject it. It is scored
      # under the strict recut rules so volume_provisioned=0 names the real problem.
      | (if $vol_destroys > 0 then "recut"
         elif $any_destroys == 0 then "resume"
         else "preserve-store" end) as $arm
      | (if $arm == "resume" then "resume" else "recut" end) as $rules
      | {
          arm: $arm,

          out_of_scope: (
            [ $plan.resource_changes[]?
              | select(positive)
              | select((IN(.address; allow[]) or IN(.address; named_live[])) | not) ]
            | length
          ),

          logs_secret_destroyed: (
            # An allow-set member, so out_of_scope cannot see it — but deleting it BRICKS the
            # fresh host (the 3-secret boot guard FATALs without BETTERSTACK_LOGS_TOKEN, so zot
            # never launches). A named, positive "must be preserved" assert.
            [ $plan.resource_changes[]?
              | select(.address == "doppler_secret.registry_betterstack_logs_token")
              | select(destroys) ]
            | length
          ),

          luks_key_touched: (
            # D6 — FULL 4-VERB, UNCONDITIONAL. A create/update is as fatal as a delete: the
            # host reads REGISTRY_LUKS_KEY at boot to unlock the store, so a key that MOVES
            # between the plan and the boot leaves an unopenable volume. Covers BOTH addresses.
            [ $plan.resource_changes[]?
              | select(IN(.address; named_live[]))
              | select(positive) ]
            | length
          ),

          server_provisioned: (
            # recut: the server must be REPLACED (delete AND create) — a `no-op` here means the
            # operator reached for a volume-only change and the host would keep its old mount.
            # resume: a bare create, or an already-landed no-op.
            if $rules == "recut" then
              [ acts("hcloud_server.registry")[]
                | select((.change.actions? | index("delete")) and (.change.actions? | index("create"))) ]
              | length
            else
              [ acts("hcloud_server.registry")[]
                | select((.change.actions? | index("create")) or (.change.actions? == ["no-op"])) ]
              | length
            end
          ),

          volume_provisioned: (
            # THE load-bearing counter. recut: delete AND create — a preserved (`no-op`) volume
            # is the exact registry-host-replace footgun #6929 removes.
            if $rules == "recut" then
              [ acts("hcloud_volume.registry")[]
                | select((.change.actions? | index("delete")) and (.change.actions? | index("create"))) ]
              | length
            else
              [ acts("hcloud_volume.registry")[]
                | select((.change.actions? | index("create")) or (.change.actions? == ["no-op"])) ]
              | length
            end
          ),

          completion_progress: (
            # RESUME ARM ONLY. A zero-delete plan cannot destroy anything, so nothing else in
            # this gate would reject a plan that also creates nothing — but such a plan is not
            # a recovery, it is a no-op that would report success over an unfinished recut.
            if $rules == "resume" then
              [ $plan.resource_changes[]?
                | select(IN(.address; [
                    "hcloud_volume.registry",
                    "hcloud_server.registry",
                    "hcloud_server_network.registry",
                    "hcloud_volume_attachment.registry"
                  ][]))
                | select(.change.actions? | index("create")) ]
              | length
            else 0 end
          ),

          volume_id_mismatch: (
            # ID-PIN (D9) — PER CHANGE, NEVER PER INVOCATION.
            # recut arm: the volume being destroyed MUST carry before.id == $expected. An
            # ABSENT before.id is a MISMATCH, not a skip: without it the gate cannot tell WHICH
            # physical volume terraform resolved, which is the whole point of the pin.
            # resume arm: there is no before.id to compare (the volume is gone — that is what
            # the live probe proved), so the PROBE is the evidence and this counter is 0.
            if $rules == "recut" then
              [ acts("hcloud_volume.registry")[]
                | select(destroys)
                | select((.change.before.id == null) or ((.change.before.id | tostring) != $expected)) ]
              | length
            else 0 end
          ),

          attachment_created: (
            if $rules == "recut" then
              [ acts("hcloud_volume_attachment.registry")[]
                | select(.change.actions? | index("create")) ] | length
            else
              [ acts("hcloud_volume_attachment.registry")[]
                | select((.change.actions? | index("create")) or (.change.actions? == ["no-op"])) ] | length
            end
          ),

          nic_created: (
            # The private NIC replaces transitively (server_id is ForceNew). A plan that
            # stripped it would leave the registry unreachable on the private network.
            if $rules == "recut" then
              [ acts("hcloud_server_network.registry")[]
                | select(.change.actions? | index("create")) ] | length
            else
              [ acts("hcloud_server_network.registry")[]
                | select((.change.actions? | index("create")) or (.change.actions? == ["no-op"])) ] | length
            end
          ),

          firewall_ok: (
            # create (fresh attachment to the new server) OR update (in-place server_ids).
            # A delete leaves the host naked on its public IP.
            [ acts("hcloud_firewall_attachment.registry")[]
              | select((.change.actions? == ["update"]) or (.change.actions? == ["create"])) ]
            | length
          )
        }
    ' 2>/dev/null); then
    echo "registry_luks_recut_gate: jq evaluation failed on ${plan_json}"
    return 1
  fi

  arm=$(echo "$counts" | jq -r '.arm')
  oos=$(echo "$counts" | jq -r '.out_of_scope')
  logsdel=$(echo "$counts" | jq -r '.logs_secret_destroyed')
  luks=$(echo "$counts" | jq -r '.luks_key_touched')
  vmis=$(echo "$counts" | jq -r '.volume_id_mismatch')
  srv=$(echo "$counts" | jq -r '.server_provisioned')
  vol=$(echo "$counts" | jq -r '.volume_provisioned')
  att=$(echo "$counts" | jq -r '.attachment_created')
  nic=$(echo "$counts" | jq -r '.nic_created')
  fw=$(echo "$counts" | jq -r '.firewall_ok')
  prog=$(echo "$counts" | jq -r '.completion_progress')

  # Every counter is a non-negative integer BEFORE any arithmetic compares one.
  # A counter that did not evaluate is the empty string, and [[ "" -gt 0 ]] is FALSE
  # under bash coercion — so an uncomputed counter silently satisfies every threshold.
  # The shared helper names WHICH counter failed rather than reporting them all.
  #
  # `arm` is DELIBERATELY ABSENT. It is a STRING discriminant ("recut" / "resume" /
  # "preserve-store"), not a counter — it appears in the abort message for diagnostic
  # context only, and the pre-#6997 hand-rolled loop never validated it either. Asserting
  # it numeric would reject every well-formed plan.
  plan_gate_assert_numeric "registry_luks_recut_gate" "out_of_scope=${oos}" "logs_secret_destroyed=${logsdel}" "luks_key_touched=${luks}" "volume_id_mismatch=${vmis}" "server_provisioned=${srv}" "volume_provisioned=${vol}" "attachment_created=${att}" "nic_created=${nic}" "firewall_ok=${fw}" "completion_progress=${prog}" || return 1

  # Echo every counter BEFORE the verdict — this line is the machine-readable ABORT reason the
  # workflow's ::error:: and the operator runbook both key on.
  echo "arm=${arm} out_of_scope=${oos} logs_secret_destroyed=${logsdel} luks_key_touched=${luks} volume_id_mismatch=${vmis} server_provisioned=${srv} volume_provisioned=${vol} attachment_created=${att} nic_created=${nic} firewall_ok=${fw} completion_progress=${prog}"

  # RESUME-ARM PRECONDITION (D4). The bare-create shape is indistinguishable from a from-empty
  # BIRTH by plan shape alone, so it is admitted ONLY on live evidence that the pinned volume
  # is genuinely gone. A 200 from Hetzner means the volume still exists and the remedy is
  # `terraform import`, never `create`.
  if [[ "$arm" == "resume" && "$probe" != "absent" ]]; then
    echo "registry_luks_recut_gate: ABORT — the plan contains NO deletes (the mid-apply resume shape), but the live Hetzner existence probe did not report the pinned volume absent (probe='${probe:-<none>}'). A bare create against a volume that STILL EXISTS is not a recovery: reconcile with \`terraform import\`, never \`create\`. NO [ack-destroy] bypass on this path."
    return 1
  fi

  if [[ "$oos" -eq 0 && "$logsdel" -eq 0 && "$luks" -eq 0 && "$vmis" -eq 0 \
        && "$srv" -ge 1 && "$vol" -ge 1 && "$att" -ge 1 && "$nic" -ge 1 && "$fw" -ge 1 ]]; then
    if [[ "$arm" == "resume" && "$prog" -lt 1 ]]; then
      echo "registry_luks_recut_gate: ABORT — resume plan creates NOTHING (completion_progress=0). A plan with no deletes and no creates is a no-op, not a recovery; it would report success over an unfinished recut."
      return 1
    fi
    echo "registry_luks_recut_gate: PASS — scoped registry LUKS recut permitted (arm=${arm}: store volume + attachment + server provisioned together so cloud-init meets a FRESH RAW device and luksFormats it; logs-token secret and LUKS key preserved; no out-of-scope resource touched)"
    return 0
  fi

  echo "registry_luks_recut_gate: ABORT — plan is NOT the exact scoped registry LUKS recut (out-of-scope create/update/destroy, logs-token secret destroy/forget, LUKS key/password touched, volume id mismatch, or a missing server/volume/attachment/NIC/firewall provision). A PRESERVED store volume (volume_provisioned=0) is the registry-host-replace footgun this path exists to remove: the host would boot cloud-init against a still-plaintext device and FATAL. NO [ack-destroy] bypass on this path."
  return 1
}
