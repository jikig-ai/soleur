# shellcheck shell=bash
# Sourced birth gate for the git-data host CREATE dispatch (#6977).
#
# THE INVERSE OF git-data-host-replace-gate.sh. That gate requires
# `actions ⊇ {delete, create}` and fires on any touch of the LUKS passphrase; this one
# requires exactly one CREATE and permits no destroys at all. They are siblings by shape
# and opposites by contract — never grade one operation's plan against the other's
# allow-set. A first birth planned against the replace gate aborts three separate ways,
# which is why this file exists.
#
# A NEW DISPATCH JOB INHERITS NOTHING (ADR-145). The per-PR `host_creates > 0` HALT is a
# separate inline copy in the `apply` job, whose `if:` is mutually exclusive with every
# dispatch job. So this gate is not defense-in-depth behind an existing check — for this
# job it is the ONLY check. Treat every branch as load-bearing.
#
# WHAT IS BEHIND IT. git-data is the shared bare-repo store: every connected user's
# source code and workspace history. The workflow calls it "the fleet's most
# irreplaceable data store", and ADR-115 excludes it from the reboot primitive, so most
# mistakes here are not repairable in place — the host must be replaced.
#
# PASS (rc=0) iff ALL of:
#   creates                 == 1    exactly one hcloud_server is born
#   created address         == hcloud_server.git_data
#   destroys                == 0    delete AND forget, type-unscoped
#   volume_destroys         == 0    named arm — owns the message, not the refusal
#   firewall_rules          == 0    the deny-all firewall stays deny-all
#   luks_passphrase_touched == 0    no delete/forget/update on the passphrase pair
#   reboot_updates          == 0    no live host power-cycled by the birth
#   out_of_scope            == 0    nothing outside the eighteen-address fan-out
#   the four ENTAILED members each create exactly once
#   the thirteen PRESENCE members each appear with actions ⊆ {create, no-op}
#
# WHY THE REQUIREMENT ARM IS SPLIT BY ENTAILMENT. This is the most important contract in
# the file, and getting it wrong breaks the gate in BOTH directions.
#
#   TOO STRICT — a permanent wedge. `random_password.git_data_luks` is dependency-free
#   and lands in terraform's first wave. On a dispatch whose server create fails after it
#   lands, it is in state, and the re-dispatch re-plans it `no-op`. A gate demanding
#   `creates == 1` on it aborts on EVERY retry, forever. The replace gate cannot rescue
#   the operator either (it needs a delete on a resource that does not exist), so both
#   automated routes refuse and the only remaining path is the untargeted laptop apply
#   this work exists to eliminate.
#
#   TOO LOOSE — it authorizes the ADR-115 catastrophe. Host born, data written, host
#   destroyed outside terraform (a console action, a quota event), volumes retained,
#   passphrase absent from state: a gate that MANDATES a fresh passphrase create hands
#   the host a new key, `isLuks` declines to reformat, `luksOpen` fails silently, and the
#   existing at-rest data is permanently unopenable.
#
# So the rule is not "require the fan-out". It is "require exactly those members whose
# existence the server's own creation ENTAILS, and require the rest merely to be
# PRESENT". The four entailed members each reference `hcloud_server.git_data.id`, so a
# new server implies a new instance by construction — which is what makes demanding
# their create safe. Nothing else has that property. Anything looser breaks a legitimate
# retry; anything tighter is unenforceable.
#
# NOTHING IN THE BOOT PATH FAILS CLOSED, which is why the plan-time arms carry the whole
# weight. The Doppler install runcmd has no `set -e`, and the LUKS block's
# `set -euo pipefail` is line 1 of the heredoc that `doppler run` EXECUTES — so on a
# missing or wrong-arch binary it never runs at all. The boot then "succeeds" with the
# volume unmounted and no off-host signal. Do not credit either with failing closed.
#
# FAIL-CLOSED input handling is delegated to plan-gate-preamble.sh. A missing file,
# unparseable JSON, a null `resource_changes`, or an entry with no array `.change.actions`
# all ABORT. This gate authorizes creating the store that holds user source code; "I could
# not check" must never read as "it is fine".
#
# Usage:  source tests/scripts/lib/plan-gate-preamble.sh
#         source tests/scripts/lib/git-data-host-birth-gate.sh
#         git_data_host_birth_gate <plan-json>          # 0=PASS, 1=ABORT

# shellcheck source=tests/scripts/lib/plan-gate-preamble.sh
if ! declare -F plan_gate_assert_readable >/dev/null 2>&1; then
  _GDHBG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=/dev/null
  source "${_GDHBG_DIR}/plan-gate-preamble.sh"
fi

# The birth fan-out, defined ONCE.
#
# SINGLETON, so `def allow:` takes no key argument — unlike web-host-birth-gate.sh, whose
# `def allow($k):` exists because `hcloud_server.web` is a for_each map. Keep that
# difference: terraform-target-parity.test.ts extracts this literal with the
# unparameterized `/def allow:\s*\[([^\]]+)\]/` and pins it three ways against the
# workflow's -target list and the test's own const.
#
# KEEP IN LOCKSTEP WITH the -target list in apply-web-platform-infra.yml's
# git_data_host_create job. The parity test enforces it; this comment tells you why it
# will fail.
_GIT_DATA_BIRTH_ALLOW='def allow: [
      "hcloud_server.git_data",
      "hcloud_server_network.git_data",
      "hcloud_volume.git_data",
      "hcloud_volume.git_data_luks",
      "hcloud_volume_attachment.git_data",
      "hcloud_volume_attachment.git_data_luks",
      "hcloud_firewall.git_data",
      "hcloud_firewall_attachment.git_data",
      "doppler_config.git_data_prd",
      "doppler_service_token.git_data",
      "tls_private_key.git_transport",
      "tls_private_key.git_provision",
      "tls_private_key.git_remove",
      "doppler_secret.git_transport_ssh_private_key",
      "doppler_secret.git_provision_ssh_private_key",
      "doppler_secret.git_remove_ssh_private_key",
      "random_password.git_data_luks",
      "doppler_secret.git_data_luks_key"
];'

git_data_host_birth_gate() {
  local plan_json="${1:-}"
  local want_addr="hcloud_server.git_data"
  local creates destroys created_addr reboot_updates out_of_scope
  local volume_destroys volume_updates firewall_rules firewall_unreadable luks_passphrase_touched luks_orphan_mint
  local fw_identity_bad server_inline_firewalls
  local fw_attach_ok
  local offenders required_addr required_creates present_addr present

  plan_gate_assert_readable "git_data_host_birth_gate" "$plan_json" || return 1
  plan_gate_assert_classifiable "git_data_host_birth_gate" "$plan_json" || return 1

  creates=$(jq '[.resource_changes[] | select(.type == "hcloud_server") | select(.change.actions | index("create"))] | length' < "$plan_json" 2>/dev/null)

  # Any destroy-shaped action ANYWHERE, not just on hcloud_server. `forget` counts: a
  # `removed{}` state-drop abandons a live billing resource, which is not a destroy but
  # is equally not a birth.
  destroys=$(jq '[.resource_changes[] | select(.change.actions | index("delete") or index("forget"))] | length' < "$plan_json" 2>/dev/null)

  # NAMED volume-destroy arm (issue AC2). Layered behind the generic destroy arm — it
  # owns the MESSAGE, not the refusal. An operator reading "1 destroy/forget action"
  # mid-dispatch does not learn that the thing about to be destroyed is the store holding
  # every user's source code, and that is the sentence that stops a hand from moving.
  volume_destroys=$(jq '[.resource_changes[]
    | select(.address == "hcloud_volume.git_data" or .address == "hcloud_volume.git_data_luks")
    | select(.change.actions | index("delete") or index("forget"))] | length' < "$plan_json" 2>/dev/null)

  # FIREWALL-CONTENT arm. hcloud_firewall.git_data is a ZERO-RULE DENY-ALL firewall and
  # it is IN the allow-set (it is upstream of its own attachment, which references its
  # id), so `update` is a permitted verb on it and no other arm inspects its contents.
  # That combination is exactly the hole an earlier draft of this gate shipped: an
  # `update` adding inbound rules passed every arm while converting a correct-looking
  # birth into a bare-repo store reachable from the open internet.
  #
  # Scoped to every verb except `read`, NOT just create|update. A create-or-update filter
  # skips the `no-op` shape — and `no-op` is exactly what the firewall plans on the
  # PARTIAL-BIRTH RESUME, which is the documented must-pass recovery path. Measured: a
  # resume plan whose firewall was `["no-op"]` with a populated `.after.rule` opening
  # 0.0.0.0/0:22 scored firewall_rules=0 and PASSED, so the headline promise "the deny-all
  # firewall stays deny-all" was unchecked on the one path an operator is told to re-run. Counts rules in `.change.after`,
  # tolerating the key being absent or null (a no-op refresh has no `after.rule`).
  # FAIL CLOSED on a rule set the plan does not disclose.
  #
  # `(.change.after.rule // []) | length` reads 0 in three distinct "I cannot see the
  # rules" cases, all measured PASS before this was hardened:
  #   • `after.rule` is null but `after_unknown.rule` is true — the shape a
  #     `dynamic "rule" { for_each = <computed> }` produces, so the rule set is simply not
  #     known at plan time;
  #   • `after` is null entirely (`after_unknown: true`);
  #   • `after.rule` is present but not an array.
  # Counting those as "zero rules" is the same fail-open as reading a degraded 200 as an
  # empty list. A separate counter keeps the abort message able to say WHICH it was.
  firewall_rules=$(jq '[.resource_changes[]
    | select(.address == "hcloud_firewall.git_data")
    | select(.change.actions | any(. != "read"))
    | if (.change.after.rule // null) == null then 0
      elif (.change.after.rule | type) != "array" then 0
      else (.change.after.rule | length) end] | add // 0' < "$plan_json" 2>/dev/null)

  firewall_unreadable=$(jq '[.resource_changes[]
    | select(.address == "hcloud_firewall.git_data")
    | select(.change.actions | any(. != "read"))
    | select(((.change.after | type) != "object")
          or ((.change.after_unknown.rule // false) != false)
          or (((.change.after.rule // null) != null) and ((.change.after.rule | type) != "array")))] | length' < "$plan_json" 2>/dev/null)

  # F5: the attachment's IDENTITY, not just the firewall's content. Nothing else in this
  # gate reads which firewall the attachment binds, nor whether the server carries inline
  # `firewall_ids`. Both were measured PASS: an attachment created against a permissive
  # `hcloud_firewall.web` (present only as a no-op, so out_of_scope skips it) satisfies
  # every content arm while leaving the store bound to an internet-open firewall.
  #
  # A correct birth either creates the firewall in this same plan (so its id is unknown
  # and `after_unknown.firewall_id` is true) or binds the already-created one. Anything
  # that resolves to a KNOWN id which is not this plan's own firewall is refused.
  fw_identity_bad=$(jq '[.resource_changes[]
    | select(.address == "hcloud_firewall_attachment.git_data")
    | select(((.change.after.firewall_id // null) != null)
          and ((.change.after_unknown.firewall_id // false) == false))] | length' < "$plan_json" 2>/dev/null)

  server_inline_firewalls=$(jq '[.resource_changes[]
    | select(.address == "hcloud_server.git_data")
    | select(((.change.after.firewall_ids // []) | length) > 0)] | length' < "$plan_json" 2>/dev/null)

  # LUKS-PASSPHRASE arm — ADR-115's second normative blocker, and the one mutation with
  # no recovery path at all. A rotated passphrase luksOpens a NEW header; `isLuks` then
  # declines to reformat, so existing at-rest data is permanently unopenable. Both halves
  # of the pair are in the allow-set, so `update` on either is otherwise permitted.
  #
  # The four mutating verbs, NOT "anything that is not create": a `create` on a first
  # birth is correct and a `no-op` on a retry is correct. Mirrors the replace gate's
  # `luks_passphrase_touched` invariant, which an earlier draft of this gate dropped.
  luks_passphrase_touched=$(jq '[.resource_changes[]
    | select(.address == "random_password.git_data_luks" or .address == "doppler_secret.git_data_luks_key")
    | select(.change.actions | any(. == "delete" or . == "forget" or . == "update"))] | length' < "$plan_json" 2>/dev/null)

  # ORPHANED PASSPHRASE MINT — the hole the delete/forget/update arm above does NOT close.
  #
  # Not mandating a create is not the same as REFUSING one, and terraform plans a create
  # for any resource absent from state regardless of what this gate asks for. So consider
  # the exact state this file's own TOO LOOSE paragraph describes — volumes retained, the
  # passphrase pair gone from state (a `state rm`, a partial state restore, a workspace
  # rebuilt against a stale backend):
  #
  #   random_password.git_data_luks     -> create   (absent from state)
  #   doppler_secret.git_data_luks_key  -> create
  #   hcloud_volume.git_data_luks       -> no-op    (the volume still exists, with data)
  #
  # Every arm passed: the verb filter sees no delete/forget/update, presence accepts a
  # create, out_of_scope is 0. MEASURED rc=0 before this arm existed. The apply then mints
  # a NEW passphrase, overwrites GIT_DATA_LUKS_KEY, and the host luksOpens a new header
  # against the old volume — `isLuks` declines to reformat, the old passphrase is gone from
  # both state and Doppler, and the data is permanently unopenable. ADR-115 bars git-data
  # from the reboot primitive, so there is no recovery.
  #
  # THE INVARIANT: a passphrase create is legitimate ONLY when the volume it will encrypt
  # is being created in the same plan. A correct first birth has both as `create`. The
  # catastrophic state is the one where they diverge, and that is exactly what this counts.
  luks_orphan_mint=$(jq '
    ( [.resource_changes[] | select(.address == "random_password.git_data_luks" or .address == "doppler_secret.git_data_luks_key")
       | select(.change.actions | index("create"))] | length ) as $pw_creates
    | ( [.resource_changes[] | select(.address == "hcloud_volume.git_data_luks")
       | select(.change.actions | index("create"))] | length ) as $vol_creates
    | if $pw_creates > 0 and $vol_creates == 0 then $pw_creates else 0 end' < "$plan_json" 2>/dev/null)

  # VOLUME-UPDATE arm. Both volumes are in the allow-set (their ids are baked into
  # user_data), so `update` on either is permitted by every other arm. A resize riding a
  # birth is a mis-scope signal: the birth CREATES these volumes, so an in-place update
  # means the plan is grading against volumes that already exist — a different operation
  # wearing a birth's clothes. Scoped to `update` alone; delete/forget belong to the
  # named volume-destroy arm above.
  volume_updates=$(jq '[.resource_changes[]
    | select(.address == "hcloud_volume.git_data" or .address == "hcloud_volume.git_data_luks")
    | select(.change.actions | index("update"))] | length' < "$plan_json" 2>/dev/null)

  # Reboot-forcing IN-PLACE update on ANY hcloud_server. A BACKSTOP here rather than live
  # coverage, and the difference is worth stating honestly: unlike the web fleet's
  # `hcloud_firewall_attachment.web` (`server_ids = [for h in hcloud_server.web : h.id]`,
  # which drags every web host into the plan), `hcloud_firewall_attachment.git_data` is
  # `server_ids = [hcloud_server.git_data.id]` — a direct singleton. No other
  # hcloud_server can enter this gate's transitive closure today. Kept because that is a
  # property of today's HCL, not a guarantee.
  reboot_updates=$(jq '[.resource_changes[]
    | select(.type == "hcloud_server")
    | select(.change.actions == ["update"])
    | select(.change.before.placement_group_id != .change.after.placement_group_id
          or .change.before.server_type       != .change.after.server_type)] | length' \
    < "$plan_json" 2>/dev/null)

  # Anything CHANGED whose address is not in the birth fan-out. `no-op` is excluded by
  # listing the four mutating actions explicitly rather than negating "no-op" — terraform
  # also emits `read` for data sources, which is not a change either, and a verb
  # allow-list stays correct as the action vocabulary grows.
  #
  # A DENY-list of the known-INERT verbs, not an allow-list of the mutating ones.
  #
  # `any(. == "create" or . == "update" or . == "delete" or . == "forget")` classifies any
  # verb terraform adds NEXT as inert, and terraform has grown this vocabulary once
  # already (`forget`). Measured: a synthesized `["evict"]` on an out-of-scope address
  # scores 0 under the allow-list (gate PASSES) and 1 under this deny-list (gate ABORTS),
  # while every legitimate shape — the 18-address birth, a data-source `read`, a
  # transitive `no-op` — scores identically under both. A novel verb is now refused until
  # someone deliberately classifies it.
  #
  # IN(...) is EXACT-equality membership. `contains`/`inside` substring-match, so a bare
  # `hcloud_volume.git_data` would satisfy the `hcloud_volume.git_data_luks` member —
  # conflating the plaintext store with the encrypted one, which is the single confusion
  # this gate must never make.
  out_of_scope=$(jq -r "${_GIT_DATA_BIRTH_ALLOW}"'
    [ .resource_changes[]
      | select(.change.actions | any(. != "no-op" and . != "read"))
      | select(IN(.address; allow[]) | not) ] | length' \
    < "$plan_json" 2>/dev/null)

  plan_gate_assert_numeric "git_data_host_birth_gate" \
    "creates=${creates}" "destroys=${destroys}" "volume_destroys=${volume_destroys}" \
    "volume_updates=${volume_updates}" "firewall_rules=${firewall_rules}" "firewall_unreadable=${firewall_unreadable}" \
    "fw_identity_bad=${fw_identity_bad}" "server_inline_firewalls=${server_inline_firewalls}" \
    "luks_passphrase_touched=${luks_passphrase_touched}" "luks_orphan_mint=${luks_orphan_mint}" \
    "reboot_updates=${reboot_updates}" "out_of_scope=${out_of_scope}" || return 1

  # Telemetry BEFORE the verdict, so a truncated log still shows the counters that
  # produced the decision.
  echo "git_data_host_birth_gate: host_creates=${creates} destroys=${destroys} volume_destroys=${volume_destroys} volume_updates=${volume_updates} firewall_rules=${firewall_rules} firewall_unreadable=${firewall_unreadable} fw_identity_bad=${fw_identity_bad} luks_passphrase_touched=${luks_passphrase_touched} luks_orphan_mint=${luks_orphan_mint} reboot_updates=${reboot_updates} out_of_scope=${out_of_scope}"

  if [[ "$creates" -ne 1 ]]; then
    if [[ "$creates" -eq 0 ]]; then
      echo "git_data_host_birth_gate: ABORT — no host create in this plan. The dispatch asked to birth ${want_addr} and the plan births nothing: either the host already exists (a no-op this gate must not rubber-stamp) or the -target set is mis-scoped. If a PREVIOUS dispatch partially succeeded, the retry is still expected to show the server as a create — a server that is already in state is not a birth."
    else
      echo "git_data_host_birth_gate: ABORT — ${creates} hcloud_server creates; expected exactly 1. The -target set has escaped its scope; one authorization births one host."
    fi
    return 1
  fi

  if [[ "$volume_destroys" -ne 0 ]]; then
    offenders=$(jq -r '[.resource_changes[]
      | select(.address == "hcloud_volume.git_data" or .address == "hcloud_volume.git_data_luks")
      | select(.change.actions | index("delete") or index("forget")) | .address] | join(", ")' < "$plan_json" 2>/dev/null)
    echo "git_data_host_birth_gate: ABORT — this plan destroys a git-data DATA VOLUME: ${offenders}. That is the shared bare-repo store holding every connected user's source code and workspace history. hcloud_volume.git_data is the plaintext store and hcloud_volume.git_data_luks is the encrypted one; destroying either during a BIRTH is never correct, because a birth is additive by definition and the volumes outlive the host. If you are trying to recover a half-created host, the volumes are exactly what you must keep."
    return 1
  fi

  # THE PASSPHRASE ARM RUNS BEFORE THE GENERIC DESTROY ARM, deliberately.
  #
  # A `delete` on random_password.git_data_luks is caught by both. If the generic arm ran
  # first it would own the message, and the operator would read "1 destroy/forget action"
  # — true, and useless. The consequence that matters is not "something was destroyed",
  # it is "the key to the encrypted store is being rotated and the data behind the old
  # header becomes permanently unopenable". Message ordering IS the safety property here:
  # these aborts are read mid-dispatch by someone deciding whether to re-dispatch.
  if [[ "$luks_passphrase_touched" -ne 0 ]]; then
    offenders=$(jq -r '[.resource_changes[]
      | select(.address == "random_password.git_data_luks" or .address == "doppler_secret.git_data_luks_key")
      | select(.change.actions | any(. == "delete" or . == "forget" or . == "update")) | .address] | join(", ")' < "$plan_json" 2>/dev/null)
    echo "git_data_host_birth_gate: ABORT — the plan mutates the LUKS PASSPHRASE pair: ${offenders}. A rotated passphrase luksOpens a NEW header, and cloud-init's isLuks check then declines to reformat — so any data already at rest on hcloud_volume.git_data_luks becomes permanently unopenable, with no recovery. ADR-115 excludes git-data from the reboot primitive, so this cannot be walked back on the host either. A birth may CREATE the passphrase (first dispatch) or leave it as a no-op (retry); it may never delete, forget or update it."
    return 1
  fi

  if [[ "$luks_orphan_mint" -ne 0 ]]; then
    echo "git_data_host_birth_gate: ABORT — ORPHANED LUKS PASSPHRASE MINT: the plan CREATES the LUKS passphrase pair while hcloud_volume.git_data_luks is NOT being created. That means the encrypted volume already exists — with data on it — and this apply would mint a FRESH passphrase and overwrite GIT_DATA_LUKS_KEY. The host would then luksOpen a new header against the old volume; cloud-init's isLuks check declines to reformat, and the previous passphrase is gone from both terraform state and Doppler, so the existing at-rest data becomes permanently unopenable. ADR-115 bars git-data from the reboot primitive, so there is no on-host recovery. This is the state a \`state rm\`, a partial state restore, or a rebuild against a stale backend produces. If you are deliberately re-keying an EMPTY volume, destroy the volume in its own operation first."
    return 1
  fi

  if [[ "$destroys" -ne 0 ]]; then
    offenders=$(jq -r '[.resource_changes[] | select(.change.actions | index("delete") or index("forget")) | .address] | .[0:10] | join(", ")' < "$plan_json" 2>/dev/null)
    echo "git_data_host_birth_gate: ABORT — ${destroys} destroy/forget action(s): ${offenders}. A birth is purely ADDITIVE. A replace (delete+create) reads as one create to a count check while destroying a live host; scoped host replacement is a different operation with its own gate (git-data-host-replace-gate.sh) and does not borrow this one."
    return 1
  fi

  created_addr=$(jq -r '[.resource_changes[] | select(.type == "hcloud_server") | select(.change.actions | index("create")) | .address][0]' < "$plan_json" 2>/dev/null)

  if [[ "$created_addr" != "$want_addr" ]]; then
    echo "git_data_host_birth_gate: ABORT — IDENTITY MISMATCH: the plan births ${created_addr} but this dispatch authorizes ${want_addr}. A count-only check passes this plan. If the born host is hcloud_server.web[\"web-1\"], applying it would create the singleton behind the app.soleur.ai A record, which has no failover partner."
    return 1
  fi

  if [[ "$firewall_unreadable" -ne 0 ]]; then
    echo "git_data_host_birth_gate: ABORT — FIREWALL CONTENT UNREADABLE: the plan does not disclose hcloud_firewall.git_data's rule set (after is not an object, after_unknown.rule is set, or after.rule is not an array). That is the shape a computed \`dynamic \"rule\"\` block produces. Fail-closed: an undisclosed rule set is not evidence of a deny-all firewall, and this firewall plus its attachment are the entire public-exposure defense for a store holding every user's source code."
    return 1
  fi

  if [[ "$fw_identity_bad" -ne 0 ]]; then
    echo "git_data_host_birth_gate: ABORT — FIREWALL IDENTITY: hcloud_firewall_attachment.git_data binds a firewall whose id is already KNOWN, so it is not the hcloud_firewall.git_data this plan creates. Every rule-content arm in this gate inspects hcloud_firewall.git_data; binding the host to a DIFFERENT firewall satisfies all of them while leaving the store reachable from whatever that firewall permits."
    return 1
  fi

  if [[ "$server_inline_firewalls" -ne 0 ]]; then
    echo "git_data_host_birth_gate: ABORT — the plan sets firewall_ids inline on hcloud_server.git_data. This host's firewall is bound via hcloud_firewall_attachment.git_data, whose content this gate inspects; an inline firewall_ids list bypasses that inspection entirely and can attach any firewall, including a permissive one."
    return 1
  fi

  if [[ "$firewall_rules" -ne 0 ]]; then
    echo "git_data_host_birth_gate: ABORT — FIREWALL CONTENT: the plan gives hcloud_firewall.git_data ${firewall_rules} inbound rule(s); it must remain a ZERO-RULE DENY-ALL firewall. That firewall plus hcloud_firewall_attachment.git_data are the entire public-exposure defense for a store holding every user's source code. Adding a rule during a birth is not a birth — it is a firewall change wearing one, and it would leave the store reachable from the open internet while every other counter in this plan looked correct."
    return 1
  fi

  if [[ "$volume_updates" -ne 0 ]]; then
    offenders=$(jq -r '[.resource_changes[]
      | select(.address == "hcloud_volume.git_data" or .address == "hcloud_volume.git_data_luks")
      | select(.change.actions | index("update")) | .address] | join(", ")' < "$plan_json" 2>/dev/null)
    echo "git_data_host_birth_gate: ABORT — VOLUME UPDATE: the plan updates ${offenders} in place. A birth CREATES these volumes, so an in-place update means the plan is grading against volumes that already exist — a resize or a retype riding a birth is a mis-scope signal, not a birth. Apply a volume change as its own operation, where the abort message can tell you what it will do to the data on it."
    return 1
  fi

  if [[ "$reboot_updates" -ne 0 ]]; then
    echo "git_data_host_birth_gate: ABORT — ${reboot_updates} reboot-forcing in-place update(s) on a LIVE hcloud_server (placement_group_id or server_type). A birth must not power-cycle a running host. This is a backstop: hcloud_firewall_attachment.git_data is a direct singleton (server_ids = [hcloud_server.git_data.id]), so no other host should be able to enter this plan's closure — its presence here means the -target set is wider than the birth. Apply the reboot as its own maintenance-window operation."
    return 1
  fi

  if [[ "$out_of_scope" -ne 0 ]]; then
    offenders=$(jq -r "${_GIT_DATA_BIRTH_ALLOW}"'
      [ .resource_changes[]
        | select(.change.actions | any(. != "no-op" and . != "read"))
        | select(IN(.address; allow[]) | not) | .address ] | .[0:10] | join(", ")' \
      < "$plan_json" 2>/dev/null)
    echo "git_data_host_birth_gate: ABORT — ${out_of_scope} out-of-scope change(s), outside the eighteen-address birth fan-out: ${offenders}. One authorization births one host and touches only that host's fan-out. Two addresses are refused here deliberately: betteruptime_heartbeat.git_data_prd (its feeder already shipped and is web-host-resident — creating a monitor this route cannot arm produces a green dashboard measuring nothing) and terraform_data.git_data_probe_install (it SSH-provisions web-1, the LIVE serving host, and remote-exec runs at APPLY, not at plan)."
    return 1
  fi

  # ── REQUIREMENT ARM — ENTAILED HALF ────────────────────────────────────────────
  #
  # Exactly these four reference hcloud_server.git_data.id, so a new server implies a new
  # instance of each by construction. That implication is what makes `creates == 1` safe
  # to demand here and unsafe to demand anywhere else. Every arm above is a PROHIBITION,
  # and prohibitions cannot catch a MISSING member — the allow-set says these addresses
  # are PERMITTED to change, never that they must.
  # hcloud_firewall_attachment.git_data is DELIBERATELY NOT IN THIS LOOP — see the
  # outcome assertion below it. `.id`-reference is not the property that governs
  # entailment; STATE IDENTITY is, and this is the one member where they diverge.
  for required_addr in \
    "hcloud_server_network.git_data" \
    "hcloud_volume_attachment.git_data" \
    "hcloud_volume_attachment.git_data_luks"; do
    required_creates=$(jq --arg a "$required_addr" \
      '[.resource_changes[] | select(.address == $a) | select(.change.actions | index("create"))] | length' \
      < "$plan_json" 2>/dev/null)
    plan_gate_assert_numeric "git_data_host_birth_gate" "required_creates[${required_addr}]=${required_creates}" || return 1
    if [[ "$required_creates" -ne 1 ]]; then
      echo "git_data_host_birth_gate: ABORT — the plan births ${want_addr} but does NOT create ${required_addr} (${required_creates} creates; expected exactly 1). Each of the four entailed members has a distinct catastrophic absence: hcloud_server_network.git_data missing is #6416 — the host comes up with no private-net IP, and because runcmd is once-per-instance no reboot repairs it (ADR-115 bars git-data from the reboot primitive, so the host must be REPLACED). hcloud_firewall_attachment.git_data missing leaves the host NAKED on its public IPv4/IPv6, because the deny-all firewall is bound to it by nothing else. Either hcloud_volume_attachment missing means the store boots with its volume unmounted — for git_data_luks that means at-rest encryption is absent while every artifact claims it is present. All four are entailed by the server's own creation, so their absence means the -target set is mis-scoped, not that they were deliberately omitted."
      return 1
    fi
  done

  # ── REQUIREMENT ARM — PRESENCE HALF ────────────────────────────────────────────
  #
  # The remaining thirteen must APPEAR in the plan with actions ⊆ {create, no-op}. This
  # catches a typo'd -target (an address absent from the closure fails presence, and
  # nothing else in CI asserts that a -target string names a declared address) while
  # NOT poisoning the retry: on a resumed dispatch these legitimately re-plan as no-ops.
  #
  # `no-op` is accepted here and ONLY here. A destroy on one of these is caught above by
  # the destroy arm; an update on the passphrase pair or the firewall by their own arms.
  for present_addr in \
    "hcloud_volume.git_data" \
    "hcloud_volume.git_data_luks" \
    "hcloud_firewall.git_data" \
    "doppler_config.git_data_prd" \
    "doppler_service_token.git_data" \
    "tls_private_key.git_transport" \
    "tls_private_key.git_provision" \
    "tls_private_key.git_remove" \
    "doppler_secret.git_transport_ssh_private_key" \
    "doppler_secret.git_provision_ssh_private_key" \
    "doppler_secret.git_remove_ssh_private_key" \
    "random_password.git_data_luks" \
    "doppler_secret.git_data_luks_key"; do
    present=$(jq --arg a "$present_addr" \
      '[.resource_changes[] | select(.address == $a) | select((.change.actions | length) > 0 and (.change.actions | all(. == "create" or . == "no-op")))] | length' \
      < "$plan_json" 2>/dev/null)
    plan_gate_assert_numeric "git_data_host_birth_gate" "present[${present_addr}]=${present}" || return 1
    if [[ "$present" -eq 0 ]]; then
      echo "git_data_host_birth_gate: ABORT — ${present_addr} is not present in the plan as a create-or-no-op. Every member of the birth fan-out must appear: an address missing from the plan entirely means the -target set is mis-scoped, and nothing else in CI asserts that a -target= string names a declared address. Three of these are the SSH private-key secrets (doppler_secret.git_{transport,provision,remove}_ssh_private_key) — omit one and the host's authorized_keys holds a public half whose private half exists only in tfstate, so the web container can never use it. doppler_config.git_data_prd is the prd_git_data branch config itself; without it the two Doppler writes fail at apply with 'Could not find requested config'. Unlike the four entailed members this arm accepts a no-op, because on a resumed dispatch these legitimately already exist."
      return 1
    fi
  done

  # ── FIREWALL ATTACHMENT — an OUTCOME assertion, not a verb assertion ────────────
  #
  # This address looks entailed and is not. From the hcloud provider source (v1.63.0,
  # internal/firewall/attachment_resource.go): the resource's terraform ID is the
  # FIREWALL's id, not the server's, and readAttachment calls d.SetId("") only when the
  # FIREWALL is nil. So when the server is destroyed outside terraform — the exact
  # scenario this file's TOO LOOSE paragraph is about — the attachment SURVIVES refresh
  # with `server_ids` emptied, and the re-birth plans an in-place UPDATE, not a create
  # (`server_ids` is plain Optional; only `firewall_id` is ForceNew).
  #
  # Demanding a create here therefore aborts the re-birth with "the -target set is
  # mis-scoped" — a wrong diagnosis — and wedges it permanently, because the replace gate
  # cannot rescue a server that does not exist either. That is the same
  # only-the-laptop-apply-remains outcome the entailment split exists to prevent,
  # arrived at from the opposite direction.
  #
  # web-host-birth-gate.sh states this exact reasoning for its own fleet attachment
  # ("it UPDATES (server_ids grows), it does not create"); the justification transfers in
  # full and an earlier draft of this gate dropped it.
  #
  # Assert the OUTCOME instead: the attachment ends up bound to exactly one server. True
  # on a first birth (create with one id) and on a re-birth (update from [] to one id),
  # and it still catches BOTH failure directions the strict-create arm was protecting —
  # omission (the host boots naked on its public IPs) and a fan-out to several servers.
  fw_attach_ok=$(jq '[.resource_changes[]
    | select(.address == "hcloud_firewall_attachment.git_data")
    | select(.change.actions | all(. == "create" or . == "update" or . == "no-op"))
    | select((.change.after.server_ids // []) | length == 1)] | length' < "$plan_json" 2>/dev/null)
  plan_gate_assert_numeric "git_data_host_birth_gate" "fw_attach_ok=${fw_attach_ok}" || return 1
  if [[ "$fw_attach_ok" -eq 0 ]]; then
    echo "git_data_host_birth_gate: ABORT — hcloud_firewall_attachment.git_data does not end this plan bound to exactly one server. It is the ONLY thing binding the zero-rule deny-all hcloud_firewall.git_data to the host, so without it the store boots NAKED on its public IPv4/IPv6 with every connected user's source code on it. This arm asserts the OUTCOME (server_ids ends at length 1) rather than a verb, because the attachment's terraform ID is the FIREWALL's id: when a host is destroyed outside terraform the attachment survives refresh with server_ids emptied, so a legitimate re-birth plans an UPDATE here, not a create. Both an omitted attachment and a fan-out to multiple servers fail this check."
    return 1
  fi

  echo "git_data_host_birth_gate: PASS — scoped birth of ${want_addr} permitted (exactly 1 host create, its 3 entailed members created + its firewall attachment bound to exactly 1 server, all 13 presence members create-or-no-op, 0 destroys, 0 volume destroys, 0 firewall rules, 0 passphrase mutations, 0 reboots, 0 out-of-scope changes)."
  return 0
}
