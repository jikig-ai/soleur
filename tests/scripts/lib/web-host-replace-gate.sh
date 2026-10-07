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
#   • hcloud_volume.workspaces IS per host (server.tf) — since #6604 step 7 its for_each is
#     local.plaintext_workspaces_hosts, i.e. web-2 only: web-1's plaintext volume is retired.
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
#   3. every terraform_data.* SSH provisioner pinned to web-1 hardcodes
#      connection.host = hcloud_server.web["web-1"].ipv4_address. `-target` is
#      upstream-only, so NONE of them is pulled into the plan — including the seccomp and
#      AppArmor sandbox controls. A replaced web-1 leaves every one un-run against a dead IP,
#      and no plan-shaped arm can see them. COUNT (measured 2026-10-02 with
#      `grep -c 'host *= *hcloud_server.web\["web-1"\]'` per file of the infra root): 22 —
#      18 in server.tf, 3 in workspaces-luks.tf, 1 in ci-ssh-key.tf. The earlier text of this
#      header said 17 and the refusal message said 15; neither was a measurement, and both
#      counted server.tf alone. The count drifts, so this comment is dated and re-derived
#      rather than trusted.
#
# And the decisive reason, which is NOT a plan property and therefore not something any
# plan-shaped gate can observe:
#
#   HISTORICAL (MEASURED 2026-07-27, true until #6604 step 7): /mnt/data on a fresh host pins
#   BY-ID to hcloud_volume.workspaces[key] (cloud-init.yml,
#   `/dev/disk/by-id/scsi-0HC_Volume_${workspaces_volume_id}`), which on web-1 was the
#   PLAINTEXT volume the 2026-07-23 cutover SUPERSEDED, then retained as the rollback
#   backstop. A rebuilt web-1 would have mounted that backstop and served every user
#   worktree rolled back to 2026-07-23.
#
#   SINCE #6604 step 7 that volume is wiped, deleted and forgotten from state, and web-1's
#   workspaces_volume_id renders the literal "retired-6604" (server.tf). Live data is solely
#   on hcloud_volume.workspaces_luks. Nothing on a fresh boot opens the mapper — crypttab is
#   written with keyfile `none` + nofail (soleur-host-bootstrap.sh) and the guest-side unlock
#   path for the TEMPLATE web-1 was built from has no opener (the fresh-boot path #6931 delivered, ADR-263, serves fresh hosts and does not change web-1). So a rebuilt web-1 now boots onto an EMPTY /mnt/data (cloud-init
#   emits `workspaces_mount fatal`) while every user worktree sits on the attached, unopened
#   LUKS volume. Different symptom, same refusal: still not a plan property.
#
# CORRECTION, recorded because the earlier wording was load-bearing and false: this header
# used to name an "AMBIGUOUS `scsi-0HC_Volume_*` glob" as the decisive reason, quoting a
# workspaces-luks.tf comment that went stale when #6604 pinned the mount by-id. There is no
# glob; the repo carries a live assertion that it stays gone. Worse, that wording named
# "ADR-119 §Sequencing's volume-ID mount pin" as the unblock condition — a section that does
# not exist, for a pin that ALREADY SHIPPED — so the refusal read as relaxable today. A
# reviewer who relaxed it on that basis would inherit reasons 1-3 with NO gate arms at all.
#
# A gate that admitted web-1 would be certifying a safety property it structurally cannot
# check. #6931 (the fresh-boot guest-side LUKS path, ADR-263) is DONE and is no longer the
# blocker. THE REMAINING UNBLOCK CONDITIONS ARE key-conditional requirement arms for
# hcloud_volume_attachment.workspaces_luks and cloudflare_record.app, plus a rehearsal on a
# non-production host (no web-1 replace has ever been performed), plus #6964.
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
#   key == _WEB_HOST_REPLACE_LUKS_ARMS_KEY only (reachable only with the refusal cleared):
#   luks_att >= 1 | apex >= 1                    the two members web-1 alone entails
#
# The first seven are PROHIBITIONS; the rest are REQUIREMENTS: three for every key (nic, vatt, fw) plus
# the two keyed arms (luks_att, apex), i.e. FIVE requirements for web-1 and three for any other key. A gate built only from
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
# and doppler_secret.workspaces_luks_key are OUTSIDE the allow-set. NOT because "an untargeted
# resource cannot be planned for destroy" — that is false, `-target` prunes DEPENDENTS, not
# DEPENDENCIES. hcloud_volume.workspaces[k] IS in the graph (the targeted attachment
# references it) and shows as a no-op; it is held by prevent_destroy (a PLAN-time error) plus
# out_of_scope + workspaces_volume_destroyed. The LUKS volume and passphrase are genuinely
# outside the graph because nothing targeted references them. Since #6604 step 7 (PR #9348)
# Terraform declares prevent_destroy + delete_protection on the LUKS volume (the sole copy) and
# prevent_destroy on its attachment, so out_of_scope + luks_volume_destroyed now back a plan-time
# error, and a Hetzner-side refusal once the post-merge SSH-stage apply has delivered
# delete_protection (until then they were its ONLY guards). A web-1 replace also forces a new
# hcloud_volume_attachment.workspaces_luks, so its plan fails closed even without the name refusal. The three named backstops below are INTENTIONALLY REDUNDANT — they exist for the
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

# The key the KEYED ARMS below apply to (#9356). A separate constant from the refusal on
# purpose: terraform-target-parity.test.ts binds the refusal literal to the workflow's
# fail-fast copy, and the arms must be able to exist while the refusal is active. The arms
# are dead code while the refusal holds; they are the evidence a later relaxing change is
# graded against. T2 (#9357) dissolves the workspaces_luks address and this arm becomes
# obsolete with it.
_WEB_HOST_REPLACE_LUKS_ARMS_KEY="web-1"

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

# The KEYED extension of the allow-set (#9356): two addresses, applicable to
# _WEB_HOST_REPLACE_LUKS_ARMS_KEY ONLY. Kept as its own definition so the base `allow($k)`
# above stays the single literal terraform-target-parity.test.ts compares to the workflow's
# -target list, and so the extension is pinned separately as exactly these two addresses.
# hcloud_volume.workspaces_luks and the passphrase resources are deliberately NOT here: they
# remain prohibitions.
#
# `$akey` is supplied to every jq program that includes this text (--arg akey). The
# comparison `$k == $akey` is what keeps web-2 (and any other key) on the base allow-set.
_WEB_HOST_REPLACE_ARMS_ALLOW='def allow_arms: [
      "hcloud_volume_attachment.workspaces_luks",
      "cloudflare_record.app"
];
def effective_allow($k): allow($k) + (if $k == $akey then allow_arms else [] end);'

web_host_replace_gate() {
  local plan_json="${1:-}" host_key="${2:-}"
  local want_addr counts offenders v
  local oos wvd lvd lpt replaced replaced_addr nic vatt fw reboot arms latt apex

  if [[ -z "$host_key" ]]; then
    echo "web_host_replace_gate: ABORT — no host key supplied. The gate cannot verify WHICH host is being replaced without the request it is grading against, and a replace gate that does not check identity is a count check wearing a costume — one satisfied by destroying web-1. NOTHING HAS BEEN DESTROYED — this gate runs before the apply. Do not re-dispatch; hand this line to an engineer."
    return 1
  fi

  # Refused BEFORE the plan is even read: this is a property of the request, not of the
  # plan, and there is no plan shape that would make it safe. See the header for the
  # measured topology (LUKS singleton attachment + apex A record + 22 web-1-pinned SSH
  # provisioners + the unopened-mapper boot, which is the decisive one).
  if [[ "$host_key" == "$_WEB_HOST_REPLACE_LUKS_PINNED_KEY" ]]; then
    echo "web_host_replace_gate: ABORT — '${host_key}' is the LUKS-pinned host and this path REFUSES it by name. Replacing it entails two members no other key has (hcloud_volume_attachment.workspaces_luks, whose server_id is hardcoded to this host and is ForceNew; and cloudflare_record.app, the apex A record pinned to its ipv4_address). It also leaves every web-1-pinned terraform_data SSH provisioner un-run against a dead IP (-target is upstream-only). DECISIVELY: nothing on a fresh boot opens the LUKS mapper (crypttab keyfile is 'none' on the template path web-1 was built from; the fresh-boot guest-side LUKS path that #6931 delivered, ADR-263, serves fresh hosts and does not change web-1), and this host no longer owns a plaintext workspaces volume (the one superseded by the 2026-07-23 LUKS cutover was wiped and deleted in #6604 step 7; cloud-init renders the 'retired-6604' sentinel). A rebuilt host would boot onto an EMPTY /mnt/data while every user worktree sat on the attached, unopened LUKS volume. That is a cloud-init property, invisible to any plan-shaped gate, so no arm below could certify it. NOTHING HAS BEEN DESTROYED. Do not re-dispatch — the key-conditional gate arms now exist but are arms-only and cannot observe any of the blockers above, so this still needs a rehearsal on a non-production host and #6964 first."
    return 1
  fi

  if [[ ! -f "$plan_json" ]]; then
    echo "web_host_replace_gate: ABORT — plan JSON not found: ${plan_json} NOTHING HAS BEEN DESTROYED — this gate runs before the apply. Do not re-dispatch; hand this line to an engineer."
    return 1
  fi

  want_addr="hcloud_server.web[\"${host_key}\"]"

  # `resource_changes[]?` tolerates the key being absent, which is why this null-guard is a
  # SEPARATE explicit check: `null | length` is 0 in jq and `-eq 0` would read a degraded
  # document as "no changes" — the same fail-open shape that lets a 200-with-null-body pass
  # a count check. An unreadable plan is an abort, not a zero.
  if ! jq -e 'has("resource_changes") and (.resource_changes | type == "array")' \
       < "$plan_json" >/dev/null 2>&1; then
    echo "web_host_replace_gate: ABORT — the document at ${plan_json} is unparseable or has no resource_changes array. Fail-closed: an unreadable plan is not evidence of a safe one. NOTHING HAS BEEN DESTROYED — this gate runs before the apply. Do not re-dispatch; hand this line to an engineer."
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
                  and (.change.actions | length) > 0
                  and all(.change.actions[]; type == "string"))' \
       < "$plan_json" >/dev/null 2>&1; then
    # `.change.actions?` here, matching the counting filter — without it this extraction
    # errors on the very entry it is trying to name and the operator gets an empty list.
    offenders=$(jq -r '[.resource_changes[] | select(((.change | type) != "object") or ((.change.actions? | type) != "array") or ((.change.actions? | length) == 0)) | .address] | .[0:10] | join(", ")' < "$plan_json" 2>/dev/null)
    echo "web_host_replace_gate: ABORT — unclassifiable plan entry: ${offenders} has no object .change carrying a NON-EMPTY array of string .change.actions, so it cannot be classified as create/replace/destroy/no-op. Fail-closed: an entry the gate cannot read is not evidence of a safe plan — a destroy hiding in an unreadable entry is exactly what this refuses to wave through. NOTHING HAS BEEN DESTROYED — this gate runs before the apply. Do not re-dispatch; hand this line to an engineer."
    return 1
  fi

  # Read from the STRUCTURED plan JSON (terraform show -json), never stderr.
  # EXACT-EQUALITY membership via IN(.address; allow($k)[]) — NOT `inside`/`contains`, which
  # substring-match, so the bare for_each map address `hcloud_server.web` would satisfy the
  # keyed member and wave the entire fleet through. Verified on jq 1.8.x.
  if ! counts=$(jq -n --slurpfile p "$plan_json" --arg k "$host_key" --arg akey "$_WEB_HOST_REPLACE_LUKS_ARMS_KEY" "${_WEB_HOST_REPLACE_ALLOW}${_WEB_HOST_REPLACE_ARMS_ALLOW}"'
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
              | select(IN(.address; effective_allow($k)[]) | not) ]
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
            # The web-1 random_password and its doppler_secret key copy, AND the web host class own
            # generator random_password.workspaces_luks_web with its doppler_secret key copy (#9377: the
            # web class holds a DISTINCT passphrase, not a copy of the web-1 one), must show ZERO positive actions.
            [ $plan.resource_changes[]?
              | select(.address == "random_password.workspaces_luks" or .address == "doppler_secret.workspaces_luks_key" or .address == "doppler_secret.workspaces_luks_web_key" or .address == "random_password.workspaces_luks_web")
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
    echo "web_host_replace_gate: ABORT — jq evaluation failed on ${plan_json}. Fail-closed. NOTHING HAS BEEN DESTROYED — this gate runs before the apply. Do not re-dispatch; hand this line to an engineer."
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
      echo "web_host_replace_gate: ABORT — counter parse failed (out_of_scope='${oos}' workspaces_volume_destroyed='${wvd}' luks_volume_destroyed='${lvd}' luks_passphrase_touched='${lpt}' replaced='${replaced}' nic='${nic}' vatt='${vatt}' fw='${fw}' reboot_updates='${reboot}'). Fail-closed. NOTHING HAS BEEN DESTROYED — this gate runs before the apply. Do not re-dispatch; hand this line to an engineer."
      return 1
    fi
  done

  echo "web_host_replace_gate: requested=${host_key} replaced=${replaced} replaced_addr=${replaced_addr} workspaces_volume_destroyed=${wvd} luks_volume_destroyed=${lvd} luks_passphrase_touched=${lpt} nic_recreated=${nic} volume_attachment_recreated=${vatt} firewall_ok=${fw} reboot_updates=${reboot} out_of_scope=${oos}"

  if [[ "$replaced" -ne 1 ]]; then
    if [[ "$replaced" -eq 0 ]]; then
      echo "web_host_replace_gate: ABORT — no host replace in this plan. \`terraform plan -replace=<addr>\` on an address ABSENT from state exits 0 with no warning and plans a plain CREATE — which is a BIRTH, and a birth must go through apply_target=web-host-create so it is graded against the additive contract. Either '${host_key}' is not in state, or the -target set is mis-scoped. NOTHING HAS BEEN DESTROYED — this gate runs before the apply. Do not re-dispatch; hand this line to an engineer."
    else
      echo "web_host_replace_gate: ABORT — ${replaced} hcloud_server replaces; expected exactly 1. The -target set has escaped its scope; one authorization replaces one host. NOTHING HAS BEEN DESTROYED — this gate runs before the apply. Do not re-dispatch; hand this line to an engineer."
    fi
    return 1
  fi

  if [[ "$replaced_addr" != "$want_addr" ]]; then
    echo "web_host_replace_gate: ABORT — IDENTITY MISMATCH: the plan replaces ${replaced_addr} but the dispatch authorized ${want_addr} (key '${host_key}'). A count-only check passes this plan. If the replaced host is web-1, applying it would DESTROY the singleton behind the app.soleur.ai A record, which has no failover partner and no load balancer. NOTHING HAS BEEN DESTROYED — this gate runs before the apply. Do not re-dispatch; hand this line to an engineer."
    return 1
  fi

  if [[ "$wvd" -ne 0 ]]; then
    echo "web_host_replace_gate: ABORT — ${wvd} destroy/forget action(s) on hcloud_volume.workspaces[\"${host_key}\"], this host's workspaces volume. That volume holds every user worktree on the host and is preserved by OMISSION from the -target set; a plan that destroys it is not a replace, it is data loss. (It also carries prevent_destroy, so this plan could not apply — but a gate that relies on a downstream error to save it is not a gate.) NOTHING HAS BEEN DESTROYED — this gate runs before the apply. Do not re-dispatch; hand this line to an engineer."
    return 1
  fi

  if [[ "$lvd" -ne 0 ]]; then
    echo "web_host_replace_gate: ABORT — ${lvd} destroy/forget action(s) on hcloud_volume.workspaces_luks, the LUKS at-rest volume. It is the Art.17 at-rest store and the rollback backstop, it belongs to no host's replace fan-out, and it is preserved by omission. NOTHING HAS BEEN DESTROYED — this gate runs before the apply. Do not re-dispatch; hand this line to an engineer."
    return 1
  fi

  if [[ "$lpt" -ne 0 ]]; then
    echo "web_host_replace_gate: ABORT — ${lpt} action(s) on the LUKS passphrase (random_password.workspaces_luks / doppler_secret.workspaces_luks_key / doppler_secret.workspaces_luks_web_key / random_password.workspaces_luks_web). A rotated passphrase opens a NEW header on the fresh boot and STRANDS the existing at-rest data behind it, while the host boots and reports perfectly healthy. NOTHING HAS BEEN DESTROYED — this gate runs before the apply. Do not re-dispatch; hand this line to an engineer."
    return 1
  fi

  if [[ "$reboot" -ne 0 ]]; then
    echo "web_host_replace_gate: ABORT — ${reboot} reboot-forcing in-place update(s) on a LIVE hcloud_server (placement_group_id or server_type). Replacing one host must not power-cycle another. This is reachable because hcloud_firewall_attachment.web is a singleton over the whole for_each map, so targeting it pulls every web host into the plan — web-1 included, the sole live origin behind app.soleur.ai. Apply the reboot as its own maintenance-window operation, not as a side effect of a replace. NOTHING HAS BEEN DESTROYED — this gate runs before the apply. Do not re-dispatch; hand this line to an engineer."
    return 1
  fi

  if [[ "$oos" -ne 0 ]]; then
    offenders=$(jq -r --arg k "$host_key" --arg akey "$_WEB_HOST_REPLACE_LUKS_ARMS_KEY" "${_WEB_HOST_REPLACE_ALLOW}${_WEB_HOST_REPLACE_ARMS_ALLOW}"'
      [ .resource_changes[]
        | select(.change.actions | any(. == "create" or . == "update" or . == "delete" or . == "forget"))
        | select(IN(.address; effective_allow($k)[]) | not) | .address ] | .[0:10] | join(", ")' \
      < "$plan_json" 2>/dev/null)
    echo "web_host_replace_gate: ABORT — ${oos} out-of-scope change(s), outside the replace fan-out for '${host_key}': ${offenders}. One authorization replaces one host and touches only that host's four fan-out addresses (plus the two keyed web-1 arms addresses for that key alone). A sibling host's NIC, the apex A record, or a Cloudflare ruleset riding along is a different operation that has not been authorized here. NOTHING HAS BEEN DESTROYED — this gate runs before the apply. Do not re-dispatch; hand this line to an engineer."
    return 1
  fi

  # ── REQUIREMENT ARMS ─────────────────────────────────────────────────────────────
  #
  # Everything above is a PROHIBITION. Prohibitions alone cannot make a replace safe: they
  # constrain what the plan may ALSO do, never what it must do, and the allow-set says these
  # addresses are PERMITTED to change, not that they must. Kept as three separate arms rather
  # than a loop so each names its OWN consequence — the message is what an operator acts on.
  if [[ "$nic" -lt 1 ]]; then
    echo "web_host_replace_gate: ABORT — the plan replaces ${want_addr} but does NOT create hcloud_server_network.web[\"${host_key}\"] (${nic} creates; expected >= 1). server_id is ForceNew, so a new server entails a new NIC by construction; its absence means the -target set is mis-scoped. A server without its private NIC comes up with no private-net IP and, transiently, no firewall — that is #6416, and it looks exactly like a successful apply. NOTHING HAS BEEN DESTROYED — this gate runs before the apply. Do not re-dispatch; hand this line to an engineer."
    return 1
  fi

  if [[ "$vatt" -lt 1 ]]; then
    echo "web_host_replace_gate: ABORT — the plan replaces ${want_addr} but does NOT create hcloud_volume_attachment.workspaces[\"${host_key}\"] (${vatt} creates; expected >= 1). server_id is ForceNew, so the attachment is entailed by the replace. A server without it writes /mnt/data to the ROOT DISK behind a fail-open mount, serves normally, and loses every workspace the first time the real volume mounts over that path. NOTHING HAS BEEN DESTROYED — this gate runs before the apply. Do not re-dispatch; hand this line to an engineer."
    return 1
  fi

  if [[ "$fw" -lt 1 ]]; then
    echo "web_host_replace_gate: ABORT — the plan replaces ${want_addr} but hcloud_firewall_attachment.web shows no create/update (${fw}; expected >= 1). Its server_ids is [for h in hcloud_server.web : h.id], so replacing a host changes that list by construction. Without the re-attachment the fresh Hetzner host boots NAKED on its public IPv4/IPv6. NOTHING HAS BEEN DESTROYED — this gate runs before the apply. Do not re-dispatch; hand this line to an engineer."
    return 1
  fi

  # ── KEY-CONDITIONAL ARMS (#9356) ─────────────────────────────────────────────────
  #
  # Reachable ONLY for _WEB_HOST_REPLACE_LUKS_ARMS_KEY and, today, only with the refusal at the
  # top of this function cleared (it is the first statement, so a complete web-1 plan still
  # aborts while it is active — CPO condition 1). They run AFTER every prohibition above and
  # after the three generic requirement arms, so no arm here can mask a prohibition.
  #
  # ARMS ONLY — "arms complete" is NOT "web-1 safe". Three blockers are invisible to any
  # plan-shaped gate: (1) /mnt/data pins by-id to the superseded PLAINTEXT volume, (2) the
  # web-1-pinned terraform_data SSH provisioners are not in a -target plan (count them with
  # grep -c at work time; see the header), (3) -target is upstream-only. A fixture that
  # satisfies these arms is an ARMS-ONLY fixture and certifies nothing about those.
  #
  #   luks_att  hcloud_volume_attachment.workspaces_luks shows a CREATE (server_id is ForceNew,
  #             so replacing web-1 recreates it) AND its after.volume_id equals the LUKS volume
  #             id in the PRIOR STATE. `index("create")` alone also passes a delete+create onto
  #             a DIFFERENT volume — the exact shape that boots the host with the wrong disk.
  #   apex      cloudflare_record.app is updated IN PLACE (exactly ["update"]: a delete+create
  #             of the apex record is an outage window), its content CHANGES, every other
  #             attribute is unchanged, and the content is sourced from the replaced server
  #             (after_unknown.content is true for ANY replace, so the plan JSON configuration
  #             references are what prove the source).
  if [[ "$host_key" == "$_WEB_HOST_REPLACE_LUKS_ARMS_KEY" ]]; then
    if ! arms=$(jq -n --slurpfile p "$plan_json" --arg k "$host_key" '
        # Every attribute except content is unchanged. The five named attributes must be PRESENT on
        # both sides and equal; any other attribute present on both sides must be equal too. An
        # attribute the plan marks unknown is absent from `after` (a provider-computed field such as
        # a modified-on stamp) and is tolerated ONLY if it is not one of the five; an attribute that
        # appears only in `after` is a change and is refused.
        def apex_attrs_equal:
          .change as $c | ($c.before // {}) as $b | ($c.after // {}) as $a
          | all(["name", "type", "proxied", "ttl", "zone_id"][]; . as $n | ($b | has($n)) and ($a | has($n)) and ($b[$n] == $a[$n]))
            and all(($b | keys_unsorted)[]; . as $n | $n == "content" or (($a | has($n)) | not) or $b[$n] == $a[$n])
            and all(($a | keys_unsorted)[]; . as $n | $n == "content" or ($b | has($n)));
        # The record content must be sourced from THIS replaced server: a configuration reference to
        # hcloud_server.web["<key>"]. after_unknown.content is true for ANY replace, so it proves nothing.
        def apex_sourced($plan; $key):
          any(($plan.configuration.root_module.resources[]? | select(.address == "cloudflare_record.app") | .expressions.content.references[]?);
              type == "string" and startswith("hcloud_server.web[\"" + $key + "\"]"));
        $p[0] as $plan
        | ( [ $plan.prior_state.values.root_module.resources[]?
              | select(.address == "hcloud_volume.workspaces_luks")
              | .values.id | select(. != null) | tostring | select(length > 0) ][0] // "" ) as $luksid
        | {
            luks_att: (
              [ $plan.resource_changes[]?
                | select(.address == "hcloud_volume_attachment.workspaces_luks")
                | select(.change.actions? | index("create"))
                | select($luksid != "" and (.change.after.volume_id != null) and ((.change.after.volume_id | tostring) == $luksid)) # arm:luks-volume-id
              ] | length
            ),
            apex: (
              [ $plan.resource_changes[]?
                | select(.address == "cloudflare_record.app")
                | select(.change.actions == ["update"]) # arm:apex-actions
                | select((.change.after.content != null and .change.after.content != .change.before.content) or .change.after_unknown.content == true) # arm:apex-content
                | select(apex_attrs_equal) # arm:apex-attrs
                | select(apex_sourced($plan; $k)) # arm:apex-source
              ] | length
            )
          }' 2>/dev/null); then
      echo "web_host_replace_gate: ABORT — jq evaluation failed on the keyed arms for ${plan_json}. Fail-closed. NOTHING HAS BEEN DESTROYED — this gate runs before the apply. Do not re-dispatch; hand this line to an engineer."
      return 1
    fi
    latt=$(echo "$arms" | jq -r '.luks_att')
    apex=$(echo "$arms" | jq -r '.apex')
    for v in "$latt" "$apex"; do
      if [[ ! "$v" =~ ^[0-9]+$ ]]; then
        echo "web_host_replace_gate: ABORT — keyed-arm counter parse failed (luks_att='${latt}' apex='${apex}'). Fail-closed. NOTHING HAS BEEN DESTROYED — this gate runs before the apply. Do not re-dispatch; hand this line to an engineer."
        return 1
      fi
    done
    echo "web_host_replace_gate: keyed arms for ${host_key}: luks_attachment_recreated_onto_prior_volume=${latt} apex_record_repointed_in_place=${apex}"

    if [[ "$latt" -lt 1 ]]; then
      echo "web_host_replace_gate: ABORT — the plan replaces ${want_addr} but does NOT create hcloud_volume_attachment.workspaces_luks onto the LUKS volume recorded in the prior state (${latt} matching creates; expected >= 1). Its server_id is ForceNew and hardcoded to this host, so the attachment is entailed by the replace; absent it the LUKS at-rest store boots UNATTACHED while the host reports healthy, and a create onto a DIFFERENT volume id boots it with the wrong disk. NOTHING HAS BEEN DESTROYED — this gate runs before the apply. Do not re-dispatch; hand this line to an engineer."
      return 1
    fi

    if [[ "$apex" -lt 1 ]]; then
      echo "web_host_replace_gate: ABORT — the plan replaces ${want_addr} but cloudflare_record.app is not updated in place to the replaced server (${apex} qualifying entries; expected 1: exactly [\"update\"], content changing, name/type/proxied/ttl/zone_id unchanged, content sourced from hcloud_server.web[\"${host_key}\"]). The apex A record is pinned to this host's ipv4_address: left stale it resolves app.soleur.ai to a destroyed host, and a delete+create of it is an outage window. NOTHING HAS BEEN DESTROYED — this gate runs before the apply. Do not re-dispatch; hand this line to an engineer."
      return 1
    fi
  fi

  echo "web_host_replace_gate: PASS — scoped replace of ${want_addr} permitted (exactly 1 host replace + its private NIC + its workspaces volume attachment + the fleet firewall re-attachment; the workspaces volume, the LUKS volume and the LUKS passphrase preserved by omission; 0 reboots of other hosts, 0 out-of-scope changes, identity matches the dispatch request '${host_key}')."
  return 0
}
