# Destroy-guard counter for apply-web-platform-infra.yml. Path-specific
# per #4420; NO recursive walk(). Five resource types have array-of-blocks
# or single-block surfaces in the current apply allow-list (verified
# 2026-05-25 via apps/web-platform/infra/*.tf inspection — closes #4419);
# a sixth surface (#5911) counts reboot-forcing in-place updates on
# hcloud_server.*; a seventh (#6416) counts hcloud_server CREATES:
#
#   1. cloudflare_ruleset.*                              .rules
#   2. cloudflare_zero_trust_tunnel_cloudflared_config.* .config[0].ingress_rule
#   3. cloudflare_zone_settings_override.*               .settings[0].security_header
#   4. cloudflare_notification_policy.*                  .email_integration
#   5. cloudflare_zero_trust_access_policy.*             .include
#   6. hcloud_server.* reboot-forcing in-place update    placement_group_id /
#                                                        server_type (#5911)
#   7. hcloud_server.* host BIRTH                       actions incl. "create"
#                                                        (create OR replace; #6416.
#                                                        hcloud_volume dropped #6919/T55)
#
# The HIGHEST-impact case is (1) — removing the ACME carve-out
# (cloudflare_ruleset.seo_page_redirects.rules[10] at seo-rulesets.tf)
# would silently re-fire the 2026-05-18 cert-renewal outage on the next
# ~60-day Let's Encrypt renewal cycle.
#
# SCHEMA STABILITY: `terraform show -json change.before` / `change.after`
# are documented contracts
# (https://developer.hashicorp.com/terraform/internals/json-format#change-representation).
# When a single-block (MaxItems: 1) surface is omitted, Terraform encodes
# it as an empty array in the JSON plan — that's why .config[0],
# .settings[0], .email_integration, and .include all index identically
# via `[.<path>[]?] | length`.
#
# SHARP EDGE: `["forget"]` actions (Terraform 1.7+ `removed { lifecycle {
# destroy = false } }` blocks) will trip nested_deletes against this filter
# because `change.actions = ["forget"]` is excluded only from resource_deletes
# (the `index("delete")` check) but `before.rules` is populated while `after`
# is null → positive count. Currently no `removed` blocks in
# apps/web-platform/infra/; if you add one, the remedy DEPENDS ON THE CONSUMER:
#   - `apply` job only — acknowledge with `[ack-destroy]` (operator intent matches).
#   - apply-deploy-pipeline-fix — `[ack-destroy]` is UNAVAILABLE there (a push
#     path with no ack token to type past), so the
#     only remedy is widening the nested-clause guard to
#     `index("delete") + index("forget")`.
# Prefer the widening: it is the one fix that works for every consumer. Note also
# that `["forget"]` is counted by NO host_creates arm on any path — a state-drop
# of hcloud_server/hcloud_volume passes every gate and silently strands the
# volume (the hazard T49 guards on the retire path). Pre-existing, no `removed`
# blocks exist today; recorded here so the next author does not rediscover it.
#
# PROVIDER PIN: cloudflare/cloudflare ~> 4.0 (currently 4.52.7). Two of
# the five clauses are at risk on a v5 upgrade
# (`ingress_rule` → `ingress` rename; `cloudflare_zone_settings_override`
# removed in v5). See learning
# `2026-03-20-cloudflare-terraform-v4-v5-resource-names.md`. When
# bumping to v5, extend the clauses in lockstep and re-capture
# tests/scripts/fixtures/tfplan-web-platform-real-baseline.json.
#
# CAP-COUPLING CONVENTION: this is the third path-specific destroy-guard
# filter (alongside destroy-guard-filter.jq and destroy-guard-filter-sentry.jq).
# A future apply-* workflow MUST follow the same pattern: dedicated
# `destroy-guard-filter-<workflow>.jq`, dedicated
# `test-destroy-guard-counter-<workflow>.sh`, CODEOWNERS rows.
#
# Input: `terraform show -json <plan>` document.
# Output: {resource_deletes: int, nested_deletes: int, reboot_updates: int,
#          host_creates: int, luks_passphrase_rotations: int}.
# Every key past the first three is ADDITIVE; the first three are byte-unchanged
# so the manual-rerun consumer that reads only them keeps working. host_creates
# has TWO workflow readers: the `apply` job (#6416) and apply-deploy-pipeline-fix.yml
# (#6718) — plus tests/scripts/lib/web2-retire-gate.sh, which is test-only
# (sourced by the counter suite, never by a workflow). Both workflow readers
# evaluate it OUTSIDE any destroy_count sum, so `[ack-destroy]` cannot bypass
# either; deploy-pipeline-fix has no ack path at all.
#
# The web2_out_of_scope_changes / web2_server_replaced keys were removed with the
# web-2 dispatch sweep (#6575, 2026-07-20) along with their sole reader, the
# web_2_recreate job's sourced gate. The retire keys below are unaffected.
#
# Each `_count($side)` helper uses `$side` value-binding (jq 1.7+; safe on
# jq 1.8.x). NOT the call-by-name filter-arg shape that crashed v1 of
# #4420 on string-key descent. The `($side // {})` null-coalesce keeps
# the count valid for resources whose `before` or `after` is null
# (resource-create / resource-delete edges that the outer
# `select(.change.actions? | index("delete") | not)` guard already
# excludes from this branch).

def cf_ruleset_rules_count($side):
  ($side // {}) | [.rules[]?] | length;

def cf_tunnel_ingress_count($side):
  ($side // {}) | [.config[]?.ingress_rule[]?] | length;

def cf_zone_security_header_count($side):
  ($side // {}) | [.settings[]?.security_header[]?] | length;

def cf_notif_email_integration_count($side):
  ($side // {}) | [.email_integration[]?] | length;

def cf_access_policy_include_count($side):
  ($side // {}) | [.include[]?] | length;

# --- web-2 retire scoped guard (#6538) -------------------------------------
# web-2 RETIRE allow-set (#6538). FIVE addresses.
#
# hcloud_volume.workspaces["web-2"] is REQUIRED here — destroying the data volume
# IS the retirement. Leaving it behind is the stranding hazard (20 GB billing,
# nothing attached). This is the OPPOSITE of the contract a scoped host -replace
# needs, where the data volume must SURVIVE and any change to it must abort. The
# sibling recreate allow-set that encoded that opposite contract was removed with
# the web-2 dispatch sweep (#6575, 2026-07-20). The warning it carried still binds
# any future host gate: an allow-set is specific to ONE operation's contract, and
# copy-pasting one into another operation's gate silently grades a plan against the
# wrong contract. Derive a new set from the operation's own semantics; never reuse
# this one for a replace.
# hcloud_firewall_attachment.web is the measured "1 to change": the attachment
# UPDATES to drop web-2 from server_ids. It must never DELETE (that strips web-1's
# firewall) — see retire_firewall_attachment_deletes.
#
# proxy-TLS is DELIBERATELY ABSENT (ADR-118 premise falsified, measured 2026-07-17).
# tls_private_key.proxy_server / tls_self_signed_cert.proxy_server /
# doppler_secret.proxy_tls_{cert,key} are absent from BOTH state and Doppler prd —
# `proxy-tls.tf` is "contract before consumer" config that was never applied — so
# they plan as CREATE, not the replace/update ADR-118 assumed. Excluding them means
# any attempt to birth them inside a host retirement trips
# web2_retire_out_of_scope_changes and ABORTS. Do NOT add them here or to B6.2's
# -target list: targeting doppler_secret.proxy_tls_cert without
# doppler_secret.proxy_tls_key writes a cert to prd with NO matching key.
def web2_retire_allow: [
  "hcloud_server.web[\"web-2\"]",
  "hcloud_server_network.web[\"web-2\"]",
  "hcloud_volume_attachment.workspaces[\"web-2\"]",
  "hcloud_volume.workspaces[\"web-2\"]",
  "hcloud_firewall_attachment.web"
];

# Count DESTROY actions at one exact address. Address-pinned by design: a bare
# `hcloud_volume.*` count would let WEB-1's volume satisfy the web-2 volume
# counter (T45). "forget" is deliberately NOT counted — a Terraform 1.7+
# `removed{}` state-drop leaves the real volume alive and billing while dropping
# it from state, which is the stranding hazard wearing a different hat (T49).
def destroyed_at($addr):
  [ .resource_changes[]?
    | select(.address == $addr)
    | select(.change.actions? | index("delete")) ]
  | length;

{
  # IS THIS PLAN GRADEABLE AT ALL? Every clause below reads `.resource_changes[]?`,
  # whose `?` swallows a missing or non-array value — so a structurally empty plan
  # ({}, a null, an error document) yields 0 for EVERY counter, and the consumer's
  # `^[0-9]+$` validation accepts all of them. A plan nobody could grade would pass
  # every gate in the step and the apply would proceed against the saved binary
  # tfplan. This flag is the difference between "no destructive changes" and
  # "nothing was read".
  plan_ok: (.resource_changes | type == "array"),
  resource_deletes: ([.resource_changes[]? | select(.change.actions? | index("delete"))] | length),
  nested_deletes: (
    [
      # 1. cloudflare_ruleset.rules
      (.resource_changes[]?
       | select(.type == "cloudflare_ruleset")
       | select(.change.actions? | index("delete") | not)
       | (cf_ruleset_rules_count(.change.before) - cf_ruleset_rules_count(.change.after))
       | select(. > 0)),
      # 2. cloudflare_zero_trust_tunnel_cloudflared_config.config[0].ingress_rule
      (.resource_changes[]?
       | select(.type == "cloudflare_zero_trust_tunnel_cloudflared_config")
       | select(.change.actions? | index("delete") | not)
       | (cf_tunnel_ingress_count(.change.before) - cf_tunnel_ingress_count(.change.after))
       | select(. > 0)),
      # 3. cloudflare_zone_settings_override.settings[0].security_header
      (.resource_changes[]?
       | select(.type == "cloudflare_zone_settings_override")
       | select(.change.actions? | index("delete") | not)
       | (cf_zone_security_header_count(.change.before) - cf_zone_security_header_count(.change.after))
       | select(. > 0)),
      # 4. cloudflare_notification_policy.email_integration
      (.resource_changes[]?
       | select(.type == "cloudflare_notification_policy")
       | select(.change.actions? | index("delete") | not)
       | (cf_notif_email_integration_count(.change.before) - cf_notif_email_integration_count(.change.after))
       | select(. > 0)),
      # 5. cloudflare_zero_trust_access_policy.include
      (.resource_changes[]?
       | select(.type == "cloudflare_zero_trust_access_policy")
       | select(.change.actions? | index("delete") | not)
       | (cf_access_policy_include_count(.change.before) - cf_access_policy_include_count(.change.after))
       | select(. > 0))
    ] | add // 0
  ),
  # 6th surface (#5911): hcloud_server.* reboot-forcing IN-PLACE update.
  # A placement_group_id / server_type change → power-off reboot of the
  # RUNNING host with ZERO destroys → invisible to resource_deletes + the 5
  # Cloudflare nested clauses above. TYPE-scoped select (not address)
  # INTENTIONALLY covers BOTH hcloud_server.web AND hcloud_server.git_data
  # (git-data.tf) — git_data is not target-reachable today but a git_data
  # reboot (holds the LUKS git volume) is MORE disruptive, so
  # defense-in-depth. `location`/`datacenter` force a full REPLACE (actions
  # include "delete") → already caught by resource_deletes and NOT compared
  # here (a REPLACE never matches actions==["update"], so comparing them
  # would be dead code). Selecting ONLY actions==["update"] never
  # double-counts a REPLACE, never false-fires on a CREATE (web-2 add), and
  # never false-fires on a `moved` re-address (serializes as no-op). An
  # `after` value UNKNOWN at plan time (placement_group_id is a resource
  # reference → serialized into change.after_unknown, change.after.<attr>
  # absent → jq yields null) still trips (before != null) — errs SAFE
  # (availability friction, never a missed reboot). KNOWN-UNCOVERED: a future
  # reboot/power-cycle attr (rescue, iso) or a provider upgrade flipping a
  # ForceNew attr to in-place silently returns rupd=0; any new hcloud_server
  # argument must be consciously classified reboot/non-reboot (CODEOWNERS
  # coupling on server.tf + this filter).
  reboot_updates: (
    [ .resource_changes[]?
      | select(.type == "hcloud_server")
      | select(.change.actions == ["update"])
      | select(.change.before.placement_group_id != .change.after.placement_group_id
            or .change.before.server_type       != .change.after.server_type) ]
    | length
  ),
  # 7th surface (#6416): a pure `+ create` of an hcloud_server on the per-PR apply
  # path. INVISIBLE to every counter above — no delete (resource_deletes=0), no
  # nested-block shrinkage (nested_deletes=0), and not an ["update"]
  # (reboot_updates=0). Measured against tfplan-hcloud-server-create.json.
  #
  # HOW THE DRIFT HAPPENS: `-target` is transitive at the RESOURCE level
  # (verified, TF 1.10.5), so EVERY allow-listed resource referencing ANY
  # hcloud_server.web instance pulls the whole for_each map — web-2 included.
  # There are TWO such pullers, not one: cloudflare_record.app (dns.tf:16) AND
  # hcloud_firewall_attachment.web (firewall.tf:93). cloudflare_record.app is
  # UNREMOVABLE (it is the apex A record for app.soleur.ai), so the pull cannot
  # be broken by trimming the allow-list — it must be GUARDED here instead.
  # That transitive pull-in is `-target` SEMANTICS, not a resource bug.
  #
  # WHY IT MATTERS (#6416): the per-PR apply created soleur-web-2 but NOT its
  # hcloud_server_network attachment (not target-reachable), so the host booted
  # public-IP-only and could never reach zot. A `+ create` also boots WITHOUT a
  # firewall: hcloud provider 1.63.0 documents that hcloud_firewall_attachment
  # (unlike hcloud_server.firewall_ids) does NOT attach before first boot. Tunnel
  # topology + measured failure rates: ADR-114 (do not restate them here).
  #
  # TYPE-scoped to hcloud_server (not address) for the same defense-in-depth
  # reason reboot_updates is: it covers hcloud_server.git_data / .inngest /
  # .registry, not just hcloud_server.web. hcloud_volume was DROPPED from this
  # arm 2026-07-24 (#6919, T55): once var.web_hosts holds >1 key, a job's OWN
  # legitimate `hcloud_volume.workspaces[<newhost>]` create is a routine
  # for_each fan-out, not a host birth — counting it tripped a HALT whose
  # remediation text ("no -var image_name", ":latest", cloud-init stage=verify)
  # is written for hcloud_server ONLY. The #6416 failure mode is a HOST born
  # unattached; a volume-only create never births a serving host, so dropping it
  # loses no #6416 coverage. The retire path keeps its own ADDRESS-pinned volume
  # counters (web2_volume_destroyed etc.) below — unaffected by this narrowing.
  #
  # `index("create")`, NOT `== ["create"]`. This counts EVERY action shape that
  # BIRTHS a host: ["create"], ["delete","create"] (a -replace), and
  # ["create","delete"] (create_before_destroy). An earlier draft used the exact
  # form, reasoning "a -replace is already counted by resource_deletes → no
  # double-count". That reasoning is FALSE here, and dangerously so:
  # host_creates is NOT a term in the workflow's destroy_count sum, so there is
  # nothing to double-count against — the exactness bought nothing and cost the
  # guarantee. Worse, a -replace trips resource_deletes, and the destroy gate
  # then PRINTS "Add [ack-destroy] to acknowledge". An author acking a legitimate
  # sibling change (say a ruleset-rule removal in the same merge) would ack the
  # host rebirth through with it — and a reborn host has no
  # hcloud_server_network attach, which is #6416 reproducing THROUGH the guard
  # built to prevent it. The reboot_updates surface already learned this lesson
  # (#5911's steer says "do NOT add [ack-destroy]"); host REBIRTH must get the
  # same treatment. Caught at review by security-sentinel.
  #
  # Not double-counted in practice either: a -replace increments BOTH
  # resource_deletes (via index("delete")) and host_creates, but they are
  # evaluated by two INDEPENDENT gates — the HALT fires first and unconditionally,
  # so the destroy gate's count is never reached. MEASURED against
  # tfplan-hcloud-server-location-replace.json: resource_deletes=1,
  # host_creates=1 (T30).
  #
  # KNOWN-UNCOVERED (declared, not accidental): a create/delete of
  # hcloud_server_network against an EXISTING host is invisible to all 7
  # surfaces. The server create catches the born-unattached case that caused
  # #6416, but detaching a live host's private NIC would pass. That is the I1
  # runtime-precondition gap tracked in #6441, not a counter this filter can add.
  #
  # BACKWARD-COMPAT: additive key. The manual-rerun consumer that reads only
  # resource_deletes/nested_deletes/reboot_updates stays byte-unchanged.
  # host_creates is read by BOTH the `apply` job (#6416) and
  # apply-deploy-pipeline-fix.yml (#6718), and each evaluates its HALT OUTSIDE
  # the destroy_count sum — there is deliberately NO [ack-destroy] bypass on
  # either (a host create is never the right thing to type past on an unattended
  # per-PR apply, nor on a push path that passes no -var image_name; the dispatch
  # jobs that legitimately create/replace are separate jobs and do not read this
  # key). As of #6730 (ADR-145) web hosts DO have an automated birth path — the
  # `web-host-create` dispatch — but it is a separate job that does not read this
  # key at all: it sources its own INVERTED gate
  # (tests/scripts/lib/web-host-birth-gate.sh), which demands exactly one create OF
  # THE REQUESTED HOST plus zero destroys/reboots/out-of-scope changes. This HALT is
  # unchanged and still correct for every route that reaches it.
  host_creates: (
    [ .resource_changes[]?
      | select(.type == "hcloud_server")
      | select(.change.actions? | index("create")) ]
    | length
  ),

  # 8th surface (#7640 PR4b, plan AC72): the apex transition must never plan TWO
  # addresses at once.
  #
  # THE ONLY CLAUSE HERE THAT IS ABOUT STATE RATHER THAN TEXT. Cloudflare rejects
  # an A and a CNAME coexisting at one name (81053), so the cutover collapses the
  # transition onto ONE Terraform address and lets core serialise Delete->Create.
  # That holds only while the plan really is one address.
  #
  # THE PROPERTY IS "NOT TWO ADDRESSES", NOT "THE MOVE RESOLVED". An earlier
  # revision counted a `pages_apex` create whose `previous_address` was absent or
  # wrong. That is a PROXY for the hazard, and it is wrong in both directions:
  #
  #   - It MISSED a PR4a that merged without converging. State then holds four
  #     `github_pages` instances; the `moved` resolves the pinned one correctly
  #     (so `previous_address` is right and the proxy is satisfied) while the
  #     other three plan as separate deletes — four apex addresses in flight.
  #
  #   - It FIRED on the mid-replace recovery, which is the one moment the apex is
  #     already dark. A replace that dies between Delete and Create leaves state
  #     holding NEITHER address, so the re-run's `moved` no-ops and `pages_apex`
  #     plans as a bare create with no `previous_address`. There is no surviving
  #     A record to collide with — it is the correct, safe recovery — and the
  #     HALT blocked it with no `[ack-destroy]` bypass, while its own remediation
  #     text told the operator not to delete the `moved` block. Measured by the
  #     review panel against this filter: the recovery plan scored 1.
  #
  # Counting the CO-OCCURRENCE instead is both stricter and correct: it catches
  # the unconverged case the proxy missed, and admits the recovery the proxy
  # blocked. `[ack-destroy]` still cannot discriminate any of this — `destroy_count`
  # is 1 in the healthy plan and 1 in the orphaned one — which is why the consumer
  # HALTs on this counter ABOVE the ack rather than behind it.
  #
  # Permanently 0 once converged: a plan that does not birth `pages_apex` scores 0
  # whatever else it contains, so a one-time transition cannot block later applies.
  apex_move_orphans: (
    ([ .resource_changes[]?
       | select(.type == "cloudflare_record")
       | select(.name == "pages_apex")
       | select(.change.actions? | index("create")) ] | length) as $apex_create
    | ([ .resource_changes[]?
         | select(.type == "cloudflare_record")
         | select(.name == "github_pages")
         | select(.change.actions? | index("delete")) ] | length) as $sibling_delete
    | if $apex_create > 0 and $sibling_delete > 0 then $sibling_delete else 0 end
  ),

  # 9th surface (#7695): a LUKS PASSPHRASE ROTATION on the per-PR apply path.
  #
  # `random_password.inngest_redis_luks` and `doppler_secret.inngest_redis_luks_key` are BOTH in
  # the per-merge `-target=` allow-list, so a routine merge apply reaches them. A delete/replace
  # there mints a new passphrase while the LUKS header on the live volume is still cut from the
  # OLD one — the store is then unopenable, on a host with no SSH and no console, and the AOF it
  # holds is user prompts and agent output. There is no recovery: the header key is the only copy.
  #
  # WHY IT NEEDS ITS OWN COUNTER RATHER THAN resource_deletes. A replace trips resource_deletes,
  # and the destroy gate then prints "Add [ack-destroy] to acknowledge" — so an author acking a
  # legitimate sibling change in the same merge acks the passphrase rotation through with it. That
  # is exactly the reasoning host_creates records for host REBIRTH, and it applies here with a
  # worse outcome: a reborn host is recoverable, a rotated header is not. Read OUTSIDE the
  # destroy_count sum, so `[ack-destroy]` cannot reach it.
  #
  # `update` OR `delete` OR `forget`, and NOT `create`.
  #
  # `update` WAS MISSING, and the comment below already claimed it was here. A Doppler-side
  # value change plans as a bare `["update"]` on the secret — no delete, no forget — so it scored
  # ZERO on every counter in this file, `destroy_count` stayed 0, and the apply never even reached
  # the ackable destroy gate, let alone this HALT. Measured on this repo's own rotation fixture
  # with the sibling random_password row removed:
  #     {"resource_deletes":0,"luks_passphrase_rotations":0}
  # That address is in the per-merge `-target=` list, so an unattended merge apply reaches it. The
  # result is a Doppler passphrase the live LUKS header was never cut from: the store is
  # unopenable on the next boot, on a host with no SSH and no console, and the header key is the
  # only copy. The parity claim below is now true rather than aspirational. A first CREATE is legal and expected
  # — this volume is being cut to LUKS for the first time, and inngest_volume_recut_gate makes the
  # same three-verb exclusion for the same reason. `forget` IS counted: a Terraform 1.7+ state-drop
  # of the passphrase leaves the header cut from a value nothing records any more, which is the
  # stranding hazard wearing a different hat (the same note the retire counters carry at T49).
  # 10th surface (#7695 review F1): AN ENTRY WHOSE VERB SET CANNOT BE READ, AT ANY ADDRESS.
  #
  # I closed this shape at the two LUKS addresses and left the CLASS open everywhere else — the
  # instance fixed, the defect kept. `[] | any(...)` is `false` and `[] | index("delete")` is null,
  # so an entry with `"actions": []`, `before` populated and `after` null — the shape of a destroy —
  # is invisible to resource_deletes, host_creates, reboot_updates, apex_move_orphans, destroyed_at()
  # and every web2 retire counter. MEASURED on this filter before this counter existed, with three
  # such entries at hcloud_volume.inngest_redis, hcloud_server.web["web-1"] and
  # hcloud_volume.workspaces["web-2"]:
  #     {"plan_ok":true,"resource_deletes":0,"host_creates":0,"nested_deletes":0,
  #      "reboot_updates":0,"luks_passphrase_rotations":0}
  # Three destroys of sole-copy volumes — the Inngest AOF and every user's repository tree — read as
  # a clean plan. `destroy_count` is then 0, so `[ack-destroy]` is never even demanded and the apply
  # proceeds against the saved binary tfplan.
  #
  # This is NOT hypothetical and it is not new: gate-suite-harness.sh's own `rc_empty_actions`
  # docstring records a real 18-address birth plan that also carried hcloud_server.web["web-1"] with
  # `"actions": []` and `"after": null` — a destroy of the singleton behind app.soleur.ai — scoring
  # destroys=0, out_of_scope=0, and PASSING. The shape was measured in this repo and the general
  # remedy was never applied to this filter.
  #
  # `plan_gate_preamble.sh` closes exactly this for the GATE scripts via plan_gate_assert_classifiable;
  # it does not run on the workflow path, which is why the check has to exist here too.
  #
  # `[]` is the ONLY silent shape. `"actions": null`, a missing `.change`, and a scalar `.change` all
  # make jq exit non-zero, which `set -e` on the `counts=$(jq …)` assignment surfaces. This counter
  # covers the one that returns rc 0 with a well-formed all-zeros document.
  undecidable_entries: (
    [ .resource_changes[]?
      | select(((.change.actions | type) != "array") or ((.change.actions | length) == 0)) ]
    | length
  ),

  luks_passphrase_rotations: (
    [ .resource_changes[]?
      | select(.address == "random_password.inngest_redis_luks"
            or .address == "doppler_secret.inngest_redis_luks_key")
      | select(
          # DECIDABILITY FIRST, then the verb set. `any(...)` over an empty array is `false`, so an
          # entry present at one of these two addresses with `"actions": []` — `before` populated,
          # `after` null, i.e. the shape of a destroy — scored ZERO here AND zero on
          # resource_deletes, and the apply never reached either gate. Measured on this filter
          # before the fix: {"luks_passphrase_rotations":0,"resource_deletes":0}. It is the only
          # degraded shape that stays silent; `"actions": null` and a missing `.change` both make
          # jq exit non-zero, which the apply surfaces. This is the same class #6997 closed for the
          # gate scripts via plan-gate-preamble.sh, which does not run on this workflow path.
          #
          # An entry AT THESE ADDRESSES whose verb set cannot be read is not evidence of safety, so
          # it counts. `["no-op"]` and `["create"]` are decidable and legitimately score 0 — no-op
          # is the routine merge reading, and a first create is this volume being cut to LUKS for
          # the first time.
          ((.change.actions | type) != "array")
          or ((.change.actions | length) == 0)
          or (.change.actions | any(. == "update" or . == "delete" or . == "forget"))
        ) ]
    | length
  ),

  # --- web-2 RETIRE counters (#6538) -------------------------------------
  # Read ONLY by web2_retire_gate (tests/scripts/lib/web2-retire-gate.sh) against
  # the B6.2 operator-local 5-target plan. BACKWARD-COMPAT: additive keys; the
  # apply / manual-rerun consumers are unchanged.
  #
  # EXACT-EQUALITY membership via IN(...) — NOT
  # `inside`/array-`contains`, which do SUBSTRING matching and would false-match
  # a bare `hcloud_server.web`. "forget" IS counted here: a `removed{}` state-drop
  # on any out-of-set address is an out-of-scope change.
  web2_retire_out_of_scope_changes: (
    [ .resource_changes[]?
      | select(.change.actions? | any(. == "create" or . == "update" or . == "delete" or . == "forget"))
      | select(IN(.address; web2_retire_allow[]) | not) ]
    | length
  ),
  # Four NAMED per-address destroy counters, not a bare `length == 4` — the gate
  # must know WHICH resources are going, not how many (T42/T45).
  web2_server_destroyed:             destroyed_at("hcloud_server.web[\"web-2\"]"),
  web2_server_network_destroyed:     destroyed_at("hcloud_server_network.web[\"web-2\"]"),
  web2_volume_attachment_destroyed:  destroyed_at("hcloud_volume_attachment.workspaces[\"web-2\"]"),
  web2_volume_destroyed:             destroyed_at("hcloud_volume.workspaces[\"web-2\"]"),
  # The firewall attachment must UPDATE (drop web-2 from server_ids), never DELETE
  # (that strips web-1's firewall). Split into two counters rather than one
  # `_ok` boolean so the gate can require deletes==0 STRICTLY while keeping
  # updates retry-tolerant (<=1): on a retry the attachment may already be
  # updated, yielding 0 — which must not fail closed.
  retire_firewall_attachment_updates: (
    [ .resource_changes[]?
      | select(.address == "hcloud_firewall_attachment.web")
      | select(.change.actions == ["update"]) ]
    | length
  ),
  retire_firewall_attachment_deletes: (
    [ .resource_changes[]?
      | select(.address == "hcloud_firewall_attachment.web")
      | select(.change.actions? | index("delete")) ]
    | length
  )
}
