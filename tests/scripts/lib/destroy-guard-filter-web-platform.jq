# Destroy-guard counter for apply-web-platform-infra.yml. Path-specific
# per #4420; NO recursive walk(). Five resource types have array-of-blocks
# or single-block surfaces in the current apply allow-list (verified
# 2026-05-25 via apps/web-platform/infra/*.tf inspection — closes #4419);
# a sixth surface (#5911) counts reboot-forcing in-place updates on
# hcloud_server.*; a seventh (#6416) counts host/volume CREATES:
#
#   1. cloudflare_ruleset.*                              .rules
#   2. cloudflare_zero_trust_tunnel_cloudflared_config.* .config[0].ingress_rule
#   3. cloudflare_zone_settings_override.*               .settings[0].security_header
#   4. cloudflare_notification_policy.*                  .email_integration
#   5. cloudflare_zero_trust_access_policy.*             .include
#   6. hcloud_server.* reboot-forcing in-place update    placement_group_id /
#                                                        server_type (#5911)
#   7. hcloud_server.* / hcloud_volume.* host BIRTH  actions incl. "create"
#                                                        (create OR replace; #6416)
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
#          host_creates: int}.
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
  # 7th surface (#6416): a pure `+ create` of a host/volume on the per-PR apply
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
  # TYPE-scoped (not address) for the same defense-in-depth reason
  # reboot_updates is: it covers hcloud_server.git_data / .inngest / .registry
  # and every hcloud_volume, not just hcloud_server.web.
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
  # key). web-1 itself still has NO automated birth path — every route that could
  # reach hcloud_server.web HALTs here; building one is tracked by #6730.
  host_creates: (
    [ .resource_changes[]?
      | select(.type == "hcloud_server" or .type == "hcloud_volume")
      | select(.change.actions? | index("create")) ]
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
