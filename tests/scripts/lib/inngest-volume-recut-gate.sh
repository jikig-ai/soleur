# shellcheck shell=bash
# Sourced destroy-guard gate for the inngest-volume-recut scoped VOLUME REPLACE
# (apply_target=inngest-volume-recut in .github/workflows/apply-web-platform-infra.yml, #7695).
#
# EXTRACTED + SOURCED (mirrors workspaces-luks-recut-gate.sh / inngest-host-replace-gate.sh):
# both the workflow's inngest_volume_recut plan step AND
# tests/scripts/test-inngest-volume-recut-gate.sh source this file and call
# inngest_volume_recut_gate directly, so the CI decision logic is the SAME bytes the test
# exercises (no re-derived inline copy to drift).
#
# WHAT THIS IS — a scoped `-replace` of the inngest Redis AOF volume, cutting it from plaintext
# ext4 to LUKS. hcloud_volume.inngest_redis (Hetzner id 106261946, created 2026-07-07) is today a
# plaintext ext4 volume holding the Redis append-only file. The recut DESTROYS it and CREATES a
# raw replacement with the same name, which cloud-init-inngest.yml's five-arm discriminator then
# luksFormats. The store must be MEASURED EMPTY first — that is Guard 2
# (tests/scripts/lib/inngest-host-dark-gate.sh), a separate layer. THIS gate answers only the
# plan-shape question: does the apply destroy anything other than the volume the operator named?
#
# ⚠️ INVERSION vs workspaces-luks-recut-gate.sh, and it is the opposite direction. THERE the
# passphrase already existed and the recut REUSED the header key, so ANY action on the passphrase
# (create included) was the header-loss catastrophe. HERE the volume is going from ext4 to LUKS
# for the FIRST time: random_password.inngest_redis_luks / doppler_secret.inngest_redis_luks_key
# are minted at MERGE time via the per-merge `-target=` allowlist, so by dispatch they normally
# show no action at all — but a FIRST create is legal (the recovery shape where the merge-time
# mint did not land). An update/delete/forget is NOT: it rotates the header key against a volume
# whose header was cut from the old one, stranding the store. That is mutation row 4.
#
# ALLOW-SET — exactly two addresses:
#   - hcloud_volume.inngest_redis             REPLACE (actions include BOTH "delete" AND "create")
#                                             or the RECOVERY bare create (["create"], before null)
#   - hcloud_volume_attachment.inngest_redis  CREATE  (re-attach the new volume; a replace also
#                                                      deletes the old attachment — legal)
# Everything else is either NAMED-LIVE (its own loud counter) or trips out_of_scope. The guard's
# closure property is that an address nobody enumerated still ABORTS: out_of_scope quantifies over
# EVERY element of .resource_changes[] rather than over a list of addresses known today.
#
# ⚠️ hcloud_server.inngest IS NAMED-LIVE WITH ZERO ACTIONS — this is the row that pins the
# three-dispatch split. Replacing the host is `inngest-host-replace`'s job, under its own gate
# (inngest-host-replace-gate.sh), which PRESERVES this volume. If the recut were allowed to also
# replace the host, the two dispatches would collapse into one un-reviewed destructive apply and
# the AOF-preserving property of the replace path would be silently unavailable.
#
# ⚠️ ID-PIN on `.change.before.id` — the address-based counters authorize destruction by terraform
# ADDRESS alone. If state ever mapped hcloud_volume.inngest_redis to a DIFFERENT physical volume
# (state corruption, a bad `state mv`, an import error), a `-replace` of the correct ADDRESS would
# destroy the wrong physical volume with every address counter reading 0. The caller supplies $2
# (expected_inngest_volume_id, a required workflow_dispatch input) and the gate asserts the
# REPLACED volume's `.change.before.id` equals it.
#
# ⚠️ id_pin_absent — AND THE PIN IS REQUIRED WHENEVER `before != null`. `expected_id="${2:-}"`
# means an omitted pin is the empty string, and the ID-PIN counter is written to skip on empty
# (that is correct for the recovery bare create, which has no before.id to destroy). Without a
# SEPARATE counter, an omitted pin on a GENUINE destroy silently disables the ID-PIN — the guard
# would authorize destroying whatever physical volume the address happens to resolve to. That is
# mutation row 10, and it is why the two counters are distinct: luks_id_mismatch answers "is the
# pin wrong", id_pin_absent answers "was there a pin at all".
#
# NO [ack-destroy] BYPASS: destroying a volume that holds production scheduler state is authorized
# by the environment reviewer gate (hr-menu-option-ack-not-prod-write-auth) — the job declares
# `environment: inngest-cutover` (non-empty reviewer set — DP-11 F8), never a commit trailer.
#
# The counters use the 4-verb POSITIVE-ACTION filter (create/update/delete/forget) — it excludes
# BOTH `no-op` AND `read`, so a live plan listing untargeted resources as no-op/read does NOT
# false-abort. A `removed{}`/`state rm` manifests as `forget`, not `delete`.
#
# Usage:  source tests/scripts/lib/inngest-volume-recut-gate.sh
#         inngest_volume_recut_gate <plan-json-file> [expected_inngest_volume_id]  # 0=PASS, 1=ABORT
#
# The ABORT line carries `reason=<token>` naming the FIRST failing counter in a fixed order, so
# the mechanically-runnable mutation harness (AC B10) can assert a REASON rather than merely a
# non-zero rc — a battery that asserts only rc cannot tell a guard that caught the right thing
# from one that aborted for an unrelated reason.

# THE FAIL-CLOSED PREAMBLE (#6997). A gate that authorises destructive production
# infrastructure must never let "I could not check" read as "it is fine". These assertions
# refuse a plan document the gate cannot READ, cannot CLASSIFY, or whose counters did not
# evaluate — the shapes that otherwise score zero-of-everything and PASS.
#
# The `declare -F` guard makes the source idempotent: the workflow step may have sourced
# the preamble already, in either order.
# shellcheck source=tests/scripts/lib/plan-gate-preamble.sh
if ! declare -F plan_gate_assert_readable >/dev/null 2>&1; then
  _IVRG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=/dev/null
  source "${_IVRG_DIR}/plan-gate-preamble.sh"
fi

inngest_volume_recut_gate() {
  local plan_json="$1"
  local expected_id="${2:-}"
  local counts vp ac nvf idmm ipa ipu ist ovt oat wst lpt rd oos reason

  # THE ASSERTS LIVE INSIDE THE FUNCTION, AS ITS FIRST STATEMENTS, because they consume
  # $plan_json — a FUNCTION PARAMETER that does not exist at file scope.
  #
  # `|| return 1` also catches a 127 undefined-function status, so a preamble that failed
  # to source aborts the gate rather than silently skipping the check.
  plan_gate_assert_readable     "inngest_volume_recut_gate" "$plan_json" || return 1
  plan_gate_assert_classifiable "inngest_volume_recut_gate" "$plan_json" || return 1

  # Read from the STRUCTURED plan JSON (terraform show -json), never stderr.
  # EXACT-EQUALITY membership via IN(.address; allow[]) — NOT `inside`/`contains`
  # (substring matching would false-match similar addresses). Verified on jq 1.8.x.
  if ! counts=$(jq -n --slurpfile p "$plan_json" --arg expected "$expected_id" '
      def allow: [
        "hcloud_volume.inngest_redis",
        "hcloud_volume_attachment.inngest_redis"
      ];
      # NAMED-LIVE: every address below also has its OWN counter, and this list is what keeps
      # out_of_scope from ALSO firing on it — so `reason=` names the specific property that
      # caught the plan instead of the generic catch-all. An address in NEITHER list still aborts
      # via out_of_scope / resource_deletes: that is the closure property, and it is what makes
      # the gate safe against a resource nobody enumerated.
      #
      # SAID PRECISELY, because an earlier revision of this comment claimed each membership was
      # "independently load-bearing" and it is not: dropping any of the four server/volume
      # addresses from this list changes no verdict and no reason, since their own counters are
      # checked FIRST in the reason order below. Membership is defence in depth and a
      # diagnostic-quality choice, not a second gate. The two that ARE load-bearing here are
      # random_password.inngest_redis_luks and doppler_secret.inngest_redis_luks_key, whose own
      # counter deliberately omits `create` — without this list a first create of the passphrase
      # would abort as out_of_scope, which is the legal shape on the first cut to LUKS.
      def named_live: [
        "hcloud_server.inngest",
        "hcloud_volume.workspaces[\"web-1\"]",
        "hcloud_volume_attachment.workspaces[\"web-1\"]",
        "hcloud_server.web[\"web-1\"]",
        "random_password.inngest_redis_luks",
        "doppler_secret.inngest_redis_luks_key"
      ];
      def positive: (.change.actions? | any(. == "create" or . == "update" or . == "delete" or . == "forget"));
      $p[0] as $plan
      | {
          redis_volume_provisioned: (
            # A GENUINE replace (delete AND create, order-independent — create_before_destroy
            # emits ["create","delete"]) OR the RECOVERY bare create (["create"] with
            # before == null: a stranded destroy-before-create re-dispatch, since inngest-host.tf
            # carries no create_before_destroy on this volume). A bare create with a NON-null
            # before, or a delete/forget/update without a create, is neither and ABORTS.
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_volume.inngest_redis")
              | select(
                  ((.change.actions? | index("delete")) and (.change.actions? | index("create")))
                  or ((.change.actions? == ["create"]) and (.change.before == null))
                ) ]
            | length
          ),
          redis_attachment_created: (
            # The new volume must be re-attached to the inngest host, or Redis comes up with
            # /mnt/data on the ephemeral root disk. A replace also shows a delete of the old
            # attachment (legal — excluded from resource_deletes below); the CREATE is required.
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_volume_attachment.inngest_redis")
              | select(.change.actions? | index("create")) ]
            | length
          ),
          luks_id_mismatch: (
            # ID-PIN: the REPLACED volume (the one carrying a non-null before.id — i.e. the volume
            # being destroyed) must be the exact physical id the dispatch named. Skipped when
            # $expected is empty; that case is covered by id_pin_absent below, NOT waved through.
            if $expected == "" then 0
            else
              [ $plan.resource_changes[]?
                | select(.address == "hcloud_volume.inngest_redis")
                | select((.change.before.id != null) and ((.change.before.id | tostring) != $expected)) ]
              | length
            end
          ),
          id_pin_absent: (
            # THE PIN IS MANDATORY ON A GENUINE DESTROY. An empty $expected makes luks_id_mismatch
            # a no-op by construction, so without this counter an omitted pin silently disables the
            # ID-PIN on exactly the shape it exists to guard. A no-op for the recovery bare create
            # (before == null → there is no physical volume being destroyed to pin).
            if $expected != "" then 0
            else
              [ $plan.resource_changes[]?
                | select(.address == "hcloud_volume.inngest_redis")
                | select(.change.before != null) ]
              | length
            end
          ),
          new_volume_formatted: (
            # THE REPLACEMENT VOLUME MUST BE BORN RAW. This is the counter that grades the PLAN
            # rather than trusting the config, and it exists because the config was wrong and
            # argued for at length: `format = "ext4"` sat on this resource under a
            # `lifecycle { ignore_changes = [format] }` that was believed to neutralise it.
            # `ignore_changes` suppresses DIFFS, never CREATES. Measured 2026-09-03 on the real
            # recut plan (`-replace=hcloud_volume.inngest_redis`):
            #
            #     with    format = "ext4":  after.format=ext4
            #     without format = "ext4":  after.format=null
            #
            # An ext4 replacement is mounted plaintext by cloud-init ARM 1 and spends the one-shot
            # empty-store window producing an UNENCRYPTED volume, while the workflow prints "The
            # new volume is RAW" twice. Counted on the CREATE side only: `before.format` is ext4
            # today and that is the volume being destroyed.
            #
            # REFUSE ANYTHING THAT IS NOT A POSITIVELY-OBSERVED NULL. `after.format != null` alone
            # read three other shapes as "born RAW" and PASSED: `after` absent entirely, `after`
            # explicitly null, and — the reachable one — a format UNKNOWN at plan time, which
            # terraform serialises as null in `after` with `true` in `after_unknown`. The sibling
            # counter in destroy-guard-filter-web-platform.jq (`reboot_updates`) already documents
            # that exact serialisation and was deliberately written to err SAFE on it; this one
            # erred unsafe. A provider bump making `format` Optional+Computed, or any
            # `format = <expression>`, flips the same null from "declared absent" to "unknown" and
            # the born-RAW enforcement evaporates while the gate prints PASS.
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_volume.inngest_redis")
              | select(.change.actions? | index("create"))
              | select(
                  (.change | has("after") | not)
                  or (.change.after == null)
                  or (.change.after.format != null)
                  or ((.change.after_unknown.format // false) == true)
                ) ]
            | length
          ),
          id_pin_unverifiable: (
            # THE THIRD PIN, and the one that closes the gap between the other two. A plan whose
            # `before` is non-null but whose `before.id` is NULL passes both: luks_id_mismatch
            # selects on `before.id != null`, and id_pin_absent only fires when $expected is
            # empty. So a genuine destroy of a volume the plan cannot name sailed through the
            # ID-PIN entirely: the one shape where the operator pin cannot be checked was the one
            # shape where nothing checked it. No fixture covered it either, because the fixture
            # builder always emitted an id.
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_volume.inngest_redis")
              | select(.change.actions? | any(. == "delete" or . == "forget"))
              # `(.change.before.id // null) == null`, NOT `before != null and before.id == null`.
              # The narrower form closed only the shape I happened to fixture — a `before` OBJECT
              # carrying a null id — and left the wider one open: a destroy with NO `before` key at
              # all, where `.change.before` is null, so the `!= null` guard was false and this
              # counter scored 0 alongside the other two. MEASURED on a `["delete","create"]` at
              # this address with `before` omitted: every pin read 0 and the gate printed
              # `PASS — … replaced-volume id is readable and matches the operator-supplied pin`,
              # which was false in both halves. Absent, null, and null-id are one case: the volume
              # is being destroyed and the plan cannot name which volume.
              #
              # Scoped to delete/forget, so the RECOVERY bare create (`before: null`, actions
              # `["create"]`) is untouched — there is nothing to pin when nothing is destroyed.
              | select((.change.before.id // null) == null) ]
            | length
          ),
          inngest_server_touched: (
            # THE THREE-DISPATCH SPLIT, pinned. The recut must not replace the host — that is
            # inngest-host-replace`s job, under a gate that PRESERVES this volume. Zero actions.
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_server.inngest")
              | select(positive) ]
            | length
          ),
          old_volume_touched: (
            # hcloud_volume.workspaces["web-1"] is the LIVE sole-copy /workspaces volume holding
            # every user repository tree. #6593 shipped NO prevent_destroy; this counter is its
            # sole protection from a mis-scoped apply reachable from this menu option.
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_volume.workspaces[\"web-1\"]")
              | select(positive) ]
            | length
          ),
          old_attachment_touched: (
            # Detaching the live /workspaces volume strands sole-copy data just as surely as
            # deleting it.
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_volume_attachment.workspaces[\"web-1\"]")
              | select(positive) ]
            | length
          ),
          web1_server_touched: (
            # cx33 is unrebuildable in all three EU datacentres, so a destroyed/replaced web-1 is
            # "the product is gone" rather than "a slow recovery".
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_server.web[\"web-1\"]")
              | select(positive) ]
            | length
          ),
          luks_passphrase_touched: (
            # THREE verbs, NOT four — create is DELIBERATELY absent. See the inversion note in the
            # header: this volume is being cut to LUKS for the first time, so a first create of the
            # passphrase is legal; an update/delete/forget rotates the header key and strands a
            # store whose header was cut from the previous value.
            [ $plan.resource_changes[]?
              | select(.address == "random_password.inngest_redis_luks" or .address == "doppler_secret.inngest_redis_luks_key")
              | select(.change.actions? | any(. == "update" or . == "delete" or . == "forget")) ]
            | length
          ),
          resource_deletes: (
            # A delete/forget of ANY address EXCEPT the volume + its attachment (both legitimately
            # deleted as part of the replace, and each owned by its own named clause above).
            [ $plan.resource_changes[]?
              | select(.address != "hcloud_volume.inngest_redis" and .address != "hcloud_volume_attachment.inngest_redis")
              | select(.change.actions? | any(. == "delete" or . == "forget")) ]
            | length
          ),
          out_of_scope: (
            # Positive action on an address that is NEITHER in the allow-set NOR named-live. This
            # is the closure clause: a resource nobody enumerated still aborts, and it reaches
            # EVERY member rather than stopping at the first (mutation row 7).
            [ $plan.resource_changes[]?
              | select(positive)
              | select((IN(.address; allow[]) | not) and (IN(.address; named_live[]) | not)) ]
            | length
          )
        }
    ' 2>/dev/null); then
    echo "inngest_volume_recut_gate: ABORT reason=jq_failed — jq evaluation failed on ${plan_json}"
    return 1
  fi
  vp=$(echo "$counts"   | jq -r '.redis_volume_provisioned')
  ac=$(echo "$counts"   | jq -r '.redis_attachment_created')
  idmm=$(echo "$counts" | jq -r '.luks_id_mismatch')
  ipa=$(echo "$counts"  | jq -r '.id_pin_absent')
  ipu=$(echo "$counts"  | jq -r '.id_pin_unverifiable')
  nvf=$(echo "$counts"  | jq -r '.new_volume_formatted')
  ist=$(echo "$counts"  | jq -r '.inngest_server_touched')
  ovt=$(echo "$counts"  | jq -r '.old_volume_touched')
  oat=$(echo "$counts"  | jq -r '.old_attachment_touched')
  wst=$(echo "$counts"  | jq -r '.web1_server_touched')
  lpt=$(echo "$counts"  | jq -r '.luks_passphrase_touched')
  rd=$(echo "$counts"   | jq -r '.resource_deletes')
  oos=$(echo "$counts"  | jq -r '.out_of_scope')

  # Every counter is a non-negative integer BEFORE any arithmetic compares one. A counter that
  # did not evaluate is the empty string, and [[ "" -gt 0 ]] is FALSE under bash coercion — so an
  # uncomputed counter silently satisfies every threshold. This is mutation row 9.
  plan_gate_assert_numeric "inngest_volume_recut_gate" \
    "redis_volume_provisioned=${vp}" "redis_attachment_created=${ac}" "luks_id_mismatch=${idmm}" \
    "id_pin_absent=${ipa}" "id_pin_unverifiable=${ipu}" "new_volume_formatted=${nvf}" "inngest_server_touched=${ist}" "old_volume_touched=${ovt}" \
    "old_attachment_touched=${oat}" "web1_server_touched=${wst}" "luks_passphrase_touched=${lpt}" \
    "resource_deletes=${rd}" "out_of_scope=${oos}" || return 1

  echo "redis_volume_provisioned=${vp} redis_attachment_created=${ac} new_volume_formatted=${nvf} luks_id_mismatch=${idmm} id_pin_absent=${ipa} id_pin_unverifiable=${ipu} inngest_server_touched=${ist} old_volume_touched=${ovt} old_attachment_touched=${oat} web1_server_touched=${wst} luks_passphrase_touched=${lpt} resource_deletes=${rd} out_of_scope=${oos}"

  if [[ "$vp" -ge 1 && "$ac" -ge 1 && "$nvf" -eq 0 && "$idmm" -eq 0 && "$ipa" -eq 0 && "$ipu" -eq 0 && "$ist" -eq 0 && "$ovt" -eq 0 && "$oat" -eq 0 && "$wst" -eq 0 && "$lpt" -eq 0 && "$rd" -eq 0 && "$oos" -eq 0 ]]; then
    echo "inngest_volume_recut_gate: PASS — scoped inngest-redis volume recut permitted (volume REPLACED [or recovery-created] and born RAW + attachment re-created; replaced-volume id is readable and matches the operator-supplied pin; hcloud_server.inngest, the live /workspaces volume/attachment and the web-1 server all untouched; passphrase not rotated; no out-of-scope delete or action)"
    return 0
  fi

  # reason=<token> names the FIRST failing counter in a FIXED order, so the mutation harness can
  # assert WHICH property caught the plan. The order runs most-specific-first: a mutation that
  # touches a named-live address should report that address's counter, not the generic
  # out_of_scope/resource_deletes catch-alls it also trips.
  reason=unknown
  if   [[ "$ovt"  -ne 0 ]]; then reason=old_volume_touched
  elif [[ "$oat"  -ne 0 ]]; then reason=old_attachment_touched
  elif [[ "$wst"  -ne 0 ]]; then reason=web1_server_touched
  elif [[ "$ist"  -ne 0 ]]; then reason=inngest_server_touched
  elif [[ "$lpt"  -ne 0 ]]; then reason=luks_passphrase_touched
  elif [[ "$idmm" -ne 0 ]]; then reason=luks_id_mismatch
  elif [[ "$ipa"  -ne 0 ]]; then reason=id_pin_absent
  elif [[ "$ipu"  -ne 0 ]]; then reason=id_pin_unverifiable
  elif [[ "$nvf"  -ne 0 ]]; then reason=new_volume_formatted
  elif [[ "$rd"   -ne 0 ]]; then reason=resource_deletes
  elif [[ "$oos"  -ne 0 ]]; then reason=out_of_scope
  elif [[ "$vp"   -lt 1 ]]; then reason=volume_not_provisioned
  elif [[ "$ac"   -lt 1 ]]; then reason=attachment_not_created
  fi
  echo "inngest_volume_recut_gate: ABORT reason=${reason} — plan is NOT the exact scoped inngest-redis volume recut (the volume must show a genuine replace [delete AND create] or a recovery bare create [before null] + the attachment a create; the replacement volume must carry NO format [an ext4 create spends the one-shot empty window on an unencrypted store]; a physical-id pin is REQUIRED whenever a volume is actually being destroyed, must be readable in the plan, and must match; a touch on hcloud_server.inngest, the live /workspaces volume/attachment or the web-1 server, a passphrase rotation, an out-of-scope delete, or an out-of-scope positive action all ABORT)"
  return 1
}
