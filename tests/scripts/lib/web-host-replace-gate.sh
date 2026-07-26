# shellcheck shell=bash
# Sourced destroy-guard gate for the web-host REPLACE dispatch
# (apply_target=web-host-replace in .github/workflows/apply-web-platform-infra.yml, #6969).
#
# EXTRACTED + SOURCED (mirrors web-host-birth-gate.sh / git-data-host-replace-gate.sh):
# both the workflow's web_host_replace plan step AND
# tests/scripts/test-web-host-replace-gate.sh source this file and call
# web_host_replace_gate directly, so the CI decision logic is the SAME bytes the test
# exercises (no re-derived inline copy to drift).
#
# ── WHY THIS GATE EXISTS AT ALL ──────────────────────────────────────────────────
#
# `soleur-web-2` went dark and there was NO mechanism to replace it. web-host-create is
# additive-only: its gate demands EXACTLY ONE create and permits NO destroys, so a
# dispatch against a host already in state plans zero creates and the birth gate correctly
# refuses ("the host already exists — a no-op the gate must not rubber-stamp"). That gate's
# own header names this file:
#
#   "Scoped host REPLACEMENT is a different operation with a different gate; it does not
#    borrow this one."
#
# This is that sibling. NOT a widened birth: the birth/replace distinction is precisely
# what makes the birth gate's destroy arm meaningful, and dissolving it would mean a
# `["delete","create"]` — one create to a naive counter, while destroying a live host —
# could ride the additive path.
#
# A NEW DISPATCH JOB INHERITS NOTHING. The per-PR `host_creates` HALT is a separate inline
# copy in the `apply` job, whose `if:` is mutually exclusive with every dispatch job. So
# this gate is not defense-in-depth behind an existing check — for this path it is the ONLY
# check. Treat every branch as load-bearing.
#
# ── WHY WEB-1 IS REFUSED BY NAME ─────────────────────────────────────────────────
#
# Measured against the worktree, not assumed. The plan this was built from asserted that a
# web host owns two symmetric per-host volume families, mirroring git-data. It does not:
#
#   • hcloud_volume.workspaces IS `for_each = var.web_hosts` (server.tf) — per host.
#   • hcloud_volume.workspaces_luks is a SINGLETON (workspaces-luks.tf), and
#     hcloud_volume_attachment.workspaces_luks.server_id is hardcoded to
#     hcloud_server.web["web-1"].id. web-2 has no LUKS volume AT ALL.
#
# So replacing web-1 is not "web-2 with a bigger blast radius" — it entails two members no
# other key has:
#   1. hcloud_volume_attachment.workspaces_luks must be RECREATED (server_id is ForceNew).
#      Omit it and the LUKS at-rest store boots UNATTACHED while the host reports healthy.
#   2. cloudflare_record.app must be RE-POINTED (its content is
#      hcloud_server.web["web-1"].ipv4_address, dns.tf). Omit it and app.soleur.ai resolves
#      to a destroyed host — a total product outage.
#
# And the decisive reason, which is NOT a plan property and therefore not something any
# plan-shaped gate can observe: web-1 currently carries TWO attached volumes mid-ADR-119
# cutover (the live plaintext one plus the LUKS volume receiving the rsync).
# workspaces-luks.tf states the consequence in terms — "with a second volume attached, the
# `scsi-0HC_Volume_*` glob in cloud-init.yml becomes AMBIGUOUS. Pinning the mount by volume
# ID is a hard prerequisite of the cutover." A fresh web-1 would boot, mount whichever
# volume the glob resolved first, serve normally, and strand or overwrite data.
#
# A gate that admitted web-1 would be certifying a safety property it structurally cannot
# check. Refusing is the only honest control until ADR-119 §Sequencing's volume-ID mount pin
# lands; the refusal is keyed on the LUKS-pinned key below so that when that pin ships, the
# reviewer of THAT change is the one who decides to relax this. Tracked as the web-1
# follow-up in ADR-148 §Alternatives.
#
# ── PASS (rc=0) iff ALL of ───────────────────────────────────────────────────────
#
#   replaced       == 1   exactly one hcloud_server is replaced (delete+create)
#   replaced_addr  == the requested   the replaced host is the one authorized
#   workspaces_volume_destroyed == 0  the per-host plaintext store survives
#   luks_volume_destroyed       == 0  the LUKS at-rest store survives
#   luks_passphrase_touched     == 0  no rotation strands data behind a new header
#   reboot_updates == 0   no OTHER live host is power-cycled
#   out_of_scope   == 0   nothing outside the four-member fan-out changes
#   nic  >= 1  |  vatt >= 1  |  fw >= 1        the members the replace ENTAILS
#
# The first seven are PROHIBITIONS; the last three are REQUIREMENTS. A gate built only from
# prohibitions cannot make a replace safe — it constrains what the plan may ALSO do, never
# what it must do — and the birth gate shipped exactly that way until review found it
# accepted a plan whose only entry was the server itself.
#
# WHY THOSE THREE REQUIREMENTS AND NOT THE WHOLE FAN-OUT. Each is entailed by the server's
# own replacement, so the implication holds by construction:
#   • hcloud_server_network.web[k]           — server_id is ForceNew. Absent ⇒ #6416: the
#       host boots with no private IP and, transiently, no firewall, and it looks exactly
#       like a successful apply.
#   • hcloud_volume_attachment.workspaces[k] — server_id is ForceNew. Absent ⇒ cloud-init's
#       /mnt/data mount is fail-open (`|| true` + `nofail`), so the host writes every user
#       worktree to the ROOT DISK, serves happily, and loses all of them the first time the
#       real volume mounts over that path.
#   • hcloud_firewall_attachment.web         — a fleet singleton whose `server_ids` is
#       `[for h in hcloud_server.web : h.id]`, so it UPDATES rather than replaces. Absent ⇒
#       a fresh Hetzner host boots NAKED on its public IPv4/IPv6.
# hcloud_volume.workspaces[k] is deliberately NOT required: it legitimately pre-exists and
# must survive, which is the opposite requirement.
#
# ── PRESERVED BY OMISSION ────────────────────────────────────────────────────────
#
# hcloud_volume.workspaces[k], hcloud_volume.workspaces_luks, random_password.workspaces_luks
# and doppler_secret.workspaces_luks_key are OUTSIDE the allow-set. An untargeted resource
# cannot be planned for destroy, so leaving them out of the -target set is simpler AND
# strictly safer than including them, and `out_of_scope` catches any positive action on them
# directly. The three named backstops below are INTENTIONALLY REDUNDANT — they exist for the
# error text an operator reads mid-abort. "an address you did not authorize changed" is true
# and tells nobody that the workspace store was about to be destroyed.
#
# NOTE the volume still APPEARS in a real plan as a no-op dependency of the targeted
# attachment. The positive-action filter (create/update/delete/forget) excludes both `no-op`
# and `read`, so a data-source read or a no-op dependency does NOT false-abort. A gate that
# refused every correct plan would be an outage dressed as a safety feature.
#
# NO [ack-destroy] BYPASS: a destructive prod host recreate is authorized by the menu-ack
# workflow_dispatch (hr-menu-option-ack-not-prod-write-auth), never a commit trailer.
#
# FAIL-CLOSED. A missing file, unparseable JSON, a null `resource_changes`, an entry with no
# array `.change.actions`, or an empty host key all ABORT. This gate authorizes DESTROYING a
# production host; "I could not check" must never read as "it is fine".
#
# Usage:  source tests/scripts/lib/web-host-replace-gate.sh
#         web_host_replace_gate <plan-json-file> <web-host-key>   # 0=PASS, 1=ABORT

# The var.web_hosts key whose replacement entails the LUKS singleton attachment and the apex
# A record — see the header. Named rather than inlined so the refusal arm reads as a
# topology fact with one place to change when ADR-119's mount pin lands.
_WEB_HOST_REPLACE_LUKS_PINNED_KEY="web-1"

# The replace fan-out, defined ONCE.
#
# The birth gate carried this twice — once in the counting filter, once in the offenders
# extraction — and review mutation-proved the second copy was guarded by nothing: deleting a
# member from it left that suite fully green. One definition, both call sites.
#
# KEEP IN LOCKSTEP WITH the -target list in apply-web-platform-infra.yml's web_host_replace
# job. plugins/soleur/test/terraform-target-parity.test.ts enforces it; this comment tells
# you why it will fail.
_WEB_HOST_REPLACE_ALLOW='def allow($k): [
      "hcloud_server.web[\"\($k)\"]",
      "hcloud_server_network.web[\"\($k)\"]",
      "hcloud_volume_attachment.workspaces[\"\($k)\"]",
      "hcloud_firewall_attachment.web"
];'

web_host_replace_gate() {
  local plan_json="${1:-}" host_key="${2:-}"
  local want_addr counts offenders v
  local oos wvd lvd lpt replaced replaced_addr nic vatt fw reboot

  if [[ -z "$host_key" ]]; then
    echo "web_host_replace_gate: ABORT — no host key supplied. The gate cannot verify WHICH host is being replaced without the request it is grading against, and a replace gate that does not check identity is a count check wearing a costume — one satisfied by destroying web-1."
    return 1
  fi

  # Refused BEFORE the plan is even read: this is a property of the request, not of the
  # plan, and there is no plan shape that would make it safe. See the header for the
  # measured topology (LUKS singleton attachment + apex A record + the ambiguous
  # `scsi-0HC_Volume_*` mount glob while two volumes are attached).
  if [[ "$host_key" == "$_WEB_HOST_REPLACE_LUKS_PINNED_KEY" ]]; then
    echo "web_host_replace_gate: ABORT — '${host_key}' is the LUKS-pinned host and this path REFUSES it by name. Replacing it entails two members no other key has (hcloud_volume_attachment.workspaces_luks, whose server_id is hardcoded to this host and is ForceNew; and cloudflare_record.app, the apex A record pinned to its ipv4_address). Decisively, it currently carries TWO attached volumes mid-ADR-119 cutover, which makes cloud-init's scsi-0HC_Volume_* mount glob AMBIGUOUS — a fresh host would mount whichever volume resolved first, serve normally, and strand or overwrite data. That is a cloud-init property, invisible to any plan-shaped gate, so no arm below could certify it. Land ADR-119 §Sequencing's volume-ID mount pin first."
    return 1
  fi

  if [[ ! -f "$plan_json" ]]; then
    echo "web_host_replace_gate: ABORT — plan JSON not found: ${plan_json}"
    return 1
  fi

  want_addr="hcloud_server.web[\"${host_key}\"]"

  # `resource_changes[]?` tolerates the key being absent, which is why this null-guard is a
  # SEPARATE explicit check: `null | length` is 0 in jq and `-eq 0` would read a degraded
  # document as "no changes" — the same fail-open shape that lets a 200-with-null-body pass
  # a count check. An unreadable plan is an abort, not a zero.
  if ! jq -e 'has("resource_changes") and (.resource_changes | type == "array")' \
       < "$plan_json" >/dev/null 2>&1; then
    echo "web_host_replace_gate: ABORT — the document at ${plan_json} is unparseable or has no resource_changes array. Fail-closed: an unreadable plan is not evidence of a safe one."
    return 1
  fi

  # Every entry MUST carry an ARRAY .change.actions before any counter reads one.
  #
  # jq's `null | index("delete")` returns null rather than erroring, so an entry missing
  # `.change.actions` is silently DROPPED by every select — a resource that vanishes from
  # the work-list instead of failing closed. What that hides is precisely a destroy the gate
  # cannot see. MEASURED, not assumed: the mutation battery proves neutering this arm makes
  # a no-actions plan PASS.
  # POSITIVE assertion, and that shape is the whole point. The earlier form searched for
  # offenders with `.change.actions` (no `?`): when `.change` is a SCALAR, jq raises
  # "Cannot index string with actions" and exits 5 — and `if jq -e ...; then` reads a jq
  # ERROR as "no offenders found". The counting filter below uses `.change.actions?`, which
  # swallows the same error and drops the entry from every select. MEASURED: a plan carrying
  # {"address":"hcloud_volume.workspaces[\"web-2\"]","change":"delete"} returned rc=0 PASS
  # with workspaces_volume_destroyed=0 and out_of_scope=0 — every user worktree on the host
  # destroyed, invisible to all three arms that exist to name it.
  #
  # `all(...)` requires EVERY entry to be well-formed, so any error, any missing key and any
  # wrong type all land on the abort side. The inner `all(.change.actions[]; type=="string")`
  # closes the nested case: `"actions": [["delete"]]` passes a bare `type=="array"` check and
  # then compares an array to a string in every `any(. == "delete")`, which is false forever.
  if ! jq -e 'all(.resource_changes[];
                  (.change | type) == "object"
                  and (.change.actions | type) == "array"
                  and all(.change.actions[]; type == "string"))' \
       < "$plan_json" >/dev/null 2>&1; then
    # `.change.actions?` here, matching the counting filter — without it this extraction
    # errors on the very entry it is trying to name and the operator gets an empty list.
    offenders=$(jq -r '[.resource_changes[] | select(((.change | type) != "object") or ((.change.actions? | type) != "array")) | .address] | .[0:10] | join(", ")' < "$plan_json" 2>/dev/null)
    echo "web_host_replace_gate: ABORT — unclassifiable plan entry: ${offenders} has no object .change carrying an array of string .change.actions, so it cannot be classified as create/replace/destroy/no-op. Fail-closed: an entry the gate cannot read is not evidence of a safe plan — a destroy hiding in an unreadable entry is exactly what this refuses to wave through."
    return 1
  fi

  # Read from the STRUCTURED plan JSON (terraform show -json), never stderr.
  # EXACT-EQUALITY membership via IN(.address; allow($k)[]) — NOT `inside`/`contains`, which
  # substring-match, so the bare for_each map address `hcloud_server.web` would satisfy the
  # keyed member and wave the entire fleet through. Verified on jq 1.8.x.
  if ! counts=$(jq -n --slurpfile p "$plan_json" --arg k "$host_key" "${_WEB_HOST_REPLACE_ALLOW}"'
      $p[0] as $plan
      | {
          out_of_scope: (
            # DENY-LIST of the two known-inert verbs, NOT an allow-list of mutating ones.
            # The allow-list form shipped here first and its comment claimed "an allow-list of
            # verbs stays correct as the action vocabulary grows" — that is backwards, and it
            # is the fail-open direction: anything terraform emits that is not one of the four
            # named verbs was classified INERT. Terraform has already grown the vocabulary once
            # (`forget`, 1.7). MEASURED: {"actions":["destroy"]} on hcloud_volume.workspaces_luks
            # returned PASS. Only a deny-list of `no-op`/`read` stays correct as it grows again.
            [ $plan.resource_changes[]?
              | select([.change.actions[]] - ["no-op", "read"] | length > 0)
              | select(IN(.address; allow($k)[]) | not) ]
            | length
          ),
          workspaces_volume_destroyed: (
            # Named backstop for THIS host'"'"'s plaintext workspace store (server.tf). It is OUT
            # of the allow-set, so out_of_scope already catches any positive action — this is
            # the operator-legible "every workspace on this host would be destroyed" line.
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_volume.workspaces[\"\($k)\"]")
              | select(.change.actions? | any(. == "delete" or . == "forget")) ]
            | length
          ),
          luks_volume_destroyed: (
            # Named backstop for the LUKS at-rest store (workspaces-luks.tf; Art.17 + the
            # rollback backstop). A SINGLETON, not per-host — see the header.
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_volume.workspaces_luks")
              | select(.change.actions? | any(. == "delete" or . == "forget")) ]
            | length
          ),
          luks_passphrase_touched: (
            # A rotated passphrase luksFormat/luksOpens a NEW header on the fresh boot,
            # STRANDING the existing at-rest data while the host boots and reports healthy.
            # BOTH the random_password AND the doppler_secret carrying it must show ZERO
            # positive actions.
            [ $plan.resource_changes[]?
              | select(.address == "random_password.workspaces_luks" or .address == "doppler_secret.workspaces_luks_key")
              | select([.change.actions[]] - ["no-op", "read"] | length > 0) ]
            | length
          ),
          replaced: (
            # TYPE-scoped, not address-scoped, so a replace of the WRONG host is counted and
            # can then be named by the identity arm. An address-scoped count would report 0
            # and abort with "nothing to replace", which reads like a mis-scoped -target
            # rather than "you are about to destroy a different host".
            [ $plan.resource_changes[]?
              | select(.type == "hcloud_server")
              | select((.change.actions? | index("delete")) and (.change.actions? | index("create"))) ]
            | length
          ),
          replaced_addr: (
            [ $plan.resource_changes[]?
              | select(.type == "hcloud_server")
              | select((.change.actions? | index("delete")) and (.change.actions? | index("create")))
              | .address ][0] // ""
          ),
          nic: (
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_server_network.web[\"\($k)\"]")
              | select(.change.actions? | index("create")) ]
            | length
          ),
          vatt: (
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_volume_attachment.workspaces[\"\($k)\"]")
              | select(.change.actions? | index("create")) ]
            | length
          ),
          fw: (
            # server_ids is a plain updatable list, so the fleet singleton UPDATES as the
            # replaced host'"'"'s id changes. `create` is accepted for the first-ever attachment.
            [ $plan.resource_changes[]?
              | select(.address == "hcloud_firewall_attachment.web")
              | select((.change.actions? == ["update"]) or (.change.actions? == ["create"])) ]
            | length
          ),
          reboot_updates: (
            # Reboot-forcing IN-PLACE update on ANY hcloud_server. TYPE-scoped: web-1 is the
            # host this arm is really about, but git_data / inngest / registry hold volumes
            # whose power-cycle is no cheaper. Selecting `actions == ["update"]` exactly never
            # double-counts the replace (which carries a "delete") and never fires on a create.
            # location/datacenter force a full REPLACE, which the cardinality + identity arms
            # already own.
            [ $plan.resource_changes[]?
              | select(.type == "hcloud_server")
              | select(.change.actions? == ["update"])
              | select(.change.before.placement_group_id != .change.after.placement_group_id
                    or .change.before.server_type       != .change.after.server_type) ]
            | length
          )
        }
    ' 2>/dev/null); then
    echo "web_host_replace_gate: ABORT — jq evaluation failed on ${plan_json}. Fail-closed."
    return 1
  fi

  oos=$(echo "$counts" | jq -r '.out_of_scope')
  wvd=$(echo "$counts" | jq -r '.workspaces_volume_destroyed')
  lvd=$(echo "$counts" | jq -r '.luks_volume_destroyed')
  lpt=$(echo "$counts" | jq -r '.luks_passphrase_touched')
  replaced=$(echo "$counts" | jq -r '.replaced')
  replaced_addr=$(echo "$counts" | jq -r '.replaced_addr')
  nic=$(echo "$counts" | jq -r '.nic')
  vatt=$(echo "$counts" | jq -r '.vatt')
  fw=$(echo "$counts" | jq -r '.fw')
  reboot=$(echo "$counts" | jq -r '.reboot_updates')

  # Parse-validate every NUMERIC counter (replaced_addr is a string and is compared, not
  # counted). A jq null/empty would evaluate false in the arithmetic below and could
  # silently mis-decide; fail LOUD instead.
  for v in "$oos" "$wvd" "$lvd" "$lpt" "$replaced" "$nic" "$vatt" "$fw" "$reboot"; do
    if [[ ! "$v" =~ ^[0-9]+$ ]]; then
      echo "web_host_replace_gate: ABORT — counter parse failed (out_of_scope='${oos}' workspaces_volume_destroyed='${wvd}' luks_volume_destroyed='${lvd}' luks_passphrase_touched='${lpt}' replaced='${replaced}' nic='${nic}' vatt='${vatt}' fw='${fw}' reboot_updates='${reboot}'). Fail-closed."
      return 1
    fi
  done

  echo "web_host_replace_gate: requested=${host_key} replaced=${replaced} replaced_addr=${replaced_addr} workspaces_volume_destroyed=${wvd} luks_volume_destroyed=${lvd} luks_passphrase_touched=${lpt} nic_recreated=${nic} volume_attachment_recreated=${vatt} firewall_ok=${fw} reboot_updates=${reboot} out_of_scope=${oos}"

  if [[ "$replaced" -ne 1 ]]; then
    if [[ "$replaced" -eq 0 ]]; then
      echo "web_host_replace_gate: ABORT — no host replace in this plan. \`terraform plan -replace=<addr>\` on an address ABSENT from state exits 0 with no warning and plans a plain CREATE — which is a BIRTH, and a birth must go through apply_target=web-host-create so it is graded against the additive contract. Either '${host_key}' is not in state, or the -target set is mis-scoped."
    else
      echo "web_host_replace_gate: ABORT — ${replaced} hcloud_server replaces; expected exactly 1. The -target set has escaped its scope; one authorization replaces one host."
    fi
    return 1
  fi

  if [[ "$replaced_addr" != "$want_addr" ]]; then
    echo "web_host_replace_gate: ABORT — IDENTITY MISMATCH: the plan replaces ${replaced_addr} but the dispatch authorized ${want_addr} (key '${host_key}'). A count-only check passes this plan. If the replaced host is web-1, applying it would DESTROY the singleton behind the app.soleur.ai A record, which has no failover partner and no load balancer."
    return 1
  fi

  if [[ "$wvd" -ne 0 ]]; then
    echo "web_host_replace_gate: ABORT — ${wvd} destroy/forget action(s) on hcloud_volume.workspaces[\"${host_key}\"], this host's workspaces volume. That volume holds every user worktree on the host and is preserved by OMISSION from the -target set; a plan that destroys it is not a replace, it is data loss. (It also carries prevent_destroy, so this plan could not apply — but a gate that relies on a downstream error to save it is not a gate.)"
    return 1
  fi

  if [[ "$lvd" -ne 0 ]]; then
    echo "web_host_replace_gate: ABORT — ${lvd} destroy/forget action(s) on hcloud_volume.workspaces_luks, the LUKS at-rest volume. It is the Art.17 at-rest store and the rollback backstop, it belongs to no host's replace fan-out, and it is preserved by omission."
    return 1
  fi

  if [[ "$lpt" -ne 0 ]]; then
    echo "web_host_replace_gate: ABORT — ${lpt} action(s) on the LUKS passphrase (random_password.workspaces_luks / doppler_secret.workspaces_luks_key). A rotated passphrase opens a NEW header on the fresh boot and STRANDS the existing at-rest data behind it, while the host boots and reports perfectly healthy."
    return 1
  fi

  if [[ "$reboot" -ne 0 ]]; then
    echo "web_host_replace_gate: ABORT — ${reboot} reboot-forcing in-place update(s) on a LIVE hcloud_server (placement_group_id or server_type). Replacing one host must not power-cycle another. This is reachable because hcloud_firewall_attachment.web is a singleton over the whole for_each map, so targeting it pulls every web host into the plan — web-1 included, the sole live origin behind app.soleur.ai. Apply the reboot as its own maintenance-window operation, not as a side effect of a replace."
    return 1
  fi

  if [[ "$oos" -ne 0 ]]; then
    offenders=$(jq -r --arg k "$host_key" "${_WEB_HOST_REPLACE_ALLOW}"'
      [ .resource_changes[]
        | select(.change.actions | any(. == "create" or . == "update" or . == "delete" or . == "forget"))
        | select(IN(.address; allow($k)[]) | not) | .address ] | .[0:10] | join(", ")' \
      < "$plan_json" 2>/dev/null)
    echo "web_host_replace_gate: ABORT — ${oos} out-of-scope change(s), outside the replace fan-out for '${host_key}': ${offenders}. One authorization replaces one host and touches only that host's four fan-out addresses. A sibling host's NIC, the apex A record, or a Cloudflare ruleset riding along is a different operation that has not been authorized here."
    return 1
  fi

  # ── REQUIREMENT ARMS ─────────────────────────────────────────────────────────────
  #
  # Everything above is a PROHIBITION. Prohibitions alone cannot make a replace safe: they
  # constrain what the plan may ALSO do, never what it must do, and the allow-set says these
  # addresses are PERMITTED to change, not that they must. Kept as three separate arms rather
  # than a loop so each names its OWN consequence — the message is what an operator acts on.
  if [[ "$nic" -lt 1 ]]; then
    echo "web_host_replace_gate: ABORT — the plan replaces ${want_addr} but does NOT create hcloud_server_network.web[\"${host_key}\"] (${nic} creates; expected >= 1). server_id is ForceNew, so a new server entails a new NIC by construction; its absence means the -target set is mis-scoped. A server without its private NIC comes up with no private-net IP and, transiently, no firewall — that is #6416, and it looks exactly like a successful apply."
    return 1
  fi

  if [[ "$vatt" -lt 1 ]]; then
    echo "web_host_replace_gate: ABORT — the plan replaces ${want_addr} but does NOT create hcloud_volume_attachment.workspaces[\"${host_key}\"] (${vatt} creates; expected >= 1). server_id is ForceNew, so the attachment is entailed by the replace. A server without it writes /mnt/data to the ROOT DISK behind a fail-open mount, serves normally, and loses every workspace the first time the real volume mounts over that path."
    return 1
  fi

  if [[ "$fw" -lt 1 ]]; then
    echo "web_host_replace_gate: ABORT — the plan replaces ${want_addr} but hcloud_firewall_attachment.web shows no create/update (${fw}; expected >= 1). Its server_ids is [for h in hcloud_server.web : h.id], so replacing a host changes that list by construction. Without the re-attachment the fresh Hetzner host boots NAKED on its public IPv4/IPv6."
    return 1
  fi

  echo "web_host_replace_gate: PASS — scoped replace of ${want_addr} permitted (exactly 1 host replace + its private NIC + its workspaces volume attachment + the fleet firewall re-attachment; the workspaces volume, the LUKS volume and the LUKS passphrase preserved by omission; 0 reboots of other hosts, 0 out-of-scope changes, identity matches the dispatch request '${host_key}')."
  return 0
}
