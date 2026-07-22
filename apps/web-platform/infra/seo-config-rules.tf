# Configuration Rules (http_config_settings phase) on the soleur.ai zone.
#
# ── Why this file exists ─────────────────────────────────────────────────────
#
# Google Search Console's "Not found (404)" report FAILED validation on
# 2026-07-20 for:
#
#   https://soleur.ai/cdn-cgi/l/email-protection      (Failed,  crawled 2026-07-01)
#   https://www.soleur.ai/cdn-cgi/l/email-protection  (Pending, crawled 2026-05-22)
#
# Root cause (verified live, not assumed): Cloudflare's Email Obfuscation
# feature — part of Scrape Shield, on by default — rewrites every `mailto:`
# href AND every plaintext address in the served marketing HTML into a
# `/cdn-cgi/l/email-protection#<xor>` link plus a `data-cfemail` span. That
# path only resolves for the JS-decoded click path; a bare Googlebot crawl of
# the href gets an HTTP 404. Census at implementation time (Googlebot UA,
# `grep -o … | wc -l` — `grep -c` undercounts, the hrefs share a line in
# minified HTML):
#
#   /                            0
#   /getting-started/            2
#   /pricing/                    1
#   /legal/privacy-policy/      20
#   /legal/terms-and-conditions/ 7
#   TOTAL                       30
#
# The rewrite is edge-injected: `git grep cdn-cgi -- plugins/soleur/docs`
# matches nothing, so there is no source-side link to delete. Turning the
# feature off for the marketing hosts removes all 30 hrefs at the origin of the
# problem.
#
# ── Why not robots.txt ───────────────────────────────────────────────────────
#
# `Disallow: /cdn-cgi/` is Cloudflare's generic hygiene advice and it is the
# wrong remedy here, on three independent grounds:
#
#   1. Google explicitly advises against it for this exact case: "Don't create
#      fake content, redirect to your homepage, or use robots.txt to block
#      404s — all of these things make it harder for us to recognize your
#      site's structure."
#      (https://support.google.com/webmasters/answer/2445990)
#   2. robots.txt cannot de-index. Google: "A page that's disallowed in
#      robots.txt can still be indexed if linked to from other sites."
#      (https://developers.google.com/search/docs/crawling-indexing/robots/intro)
#      The 30 internal links above are precisely that precondition — blocking
#      the crawl would remove the 404 signal that retires the URL while leaving
#      the links that keep it discoverable.
#   3. This repo already hit that trap on THIS zone six weeks earlier:
#      knowledge-base/project/learnings/
#        2026-06-14-gsc-indexed-though-blocked-by-robots-is-a-real-misconfig-not-benign.md
#      documents app.soleur.ai/ becoming "Indexed, though blocked by
#      robots.txt" because a Disallow stopped Googlebot from ever reading the
#      noindex. Vendor hygiene advice does not override the more specific
#      vendor guidance for the situation you actually have.
#
# ── Why host-scoped and not zone-wide ────────────────────────────────────────
#
# `cloudflare_zone_settings_override` is per-ZONE, so disabling obfuscation
# there would also disable it on app.soleur.ai, deploy.soleur.ai and
# api.soleur.ai. Those hosts serve no marketing copy, so the change would be
# pure blast radius with no benefit. A Configuration Rule is the narrowest
# instrument that expresses "these two hosts only". That bounded scope is the
# whole difference between this remedy and the rejected one, so
# test/seo-config-rules.test.ts pins it — see the rule block below.
#
# ── What this trades away ────────────────────────────────────────────────────
#
# The marketing pages' contact addresses (ops@jikigai.com, hello@soleur.ai,
# legal@jikigai.com) become plaintext and therefore harvestable. What is lost
# is cheap friction, NOT a security control: `data-cfemail` is a single-byte
# XOR with the key in the first byte, decoded by off-the-shelf scrapers for
# over a decade. Plaintext contact addresses on legal pages are near-universal
# practice, and plaintext is the form that actually satisfies Art. 12's
# "easily accessible" expectation for a contact channel.
#
# The consequence that matters is NOT spam volume. `legal@jikigai.com` is the
# GDPR inquiry channel (cookie-policy.md) and the Art. 22(3) contestation
# channel (terms-and-conditions.md), and the statutory clocks in
# knowledge-base/legal/statutory-response-catalog.md start on AWARENESS — so a
# legitimate DSAR silently auto-filed into junk does not pause its clock, it
# consumes it. The mitigation is therefore a mailbox setting, not a threshold:
# legal@ and ops@ spam filtering MUST quarantine-for-review rather than
# discard, so a misclassified request is recoverable. If volume later warrants
# it, escalate to a contact form or an alias — NOT to re-enabling obfuscation,
# which would reintroduce this bug. (The in-product Art. 22(3) affordance at
# /dashboard/audit is login-gated, so non-users and closed-account data
# subjects have only this channel.)
#
# Side effect (intended): the getting-started hero's graceful-degradation
# fallback `(or email ops@jikigai.com)` currently renders live as the literal
# string `[email protected]` — the one element whose job is to show a copyable
# address. With obfuscation off, it renders correctly with no source edit.
#
# ── PREREQUISITE 1: token scope — SATISFIED 2026-07-20 ───────────────────────
#
# The `cloudflare.rulesets` alias token (var.cf_api_token_rulesets) originally
# did NOT carry the Configuration-Rules permission. Verified by live probe:
#
#   GET /zones/<zone>/rulesets/phases/http_config_settings/entrypoint      → 403
#   GET /zones/<zone>/rulesets/phases/http_request_dynamic_redirect/...    → 200
#
# `Config Rules:Edit` (zone, soleur.ai) was appended to the token on 2026-07-20
# and the same probe now returns 200. Note the UI spells the permission
# `Config Rules`, NOT "Configuration Rules". The decision test behind widening
# the existing token rather than minting an alias is ADR-130.
#
# Per that decision test the EXISTING token is widened rather than a new
# `cf_api_token_config_rules` alias minted. Widening moves no secret material
# (a permission edit does not rotate the value), so it adds no new no-default
# root variable — which matters because Terraform resolves all root vars BEFORE
# `-target` pruning, so an unprovisioned one would fail the entire
# merge-triggered apply for every resource, not just this one.
#
# Because the widen mutates a live credential that four production concerns
# already depend on, a retained-scope probe set is MANDATORY after this widen
# and after any future re-scope of this token: http_config_settings,
# http_request_dynamic_redirect, http_request_cache_settings, and the
# account-level rulesets endpoint must all return non-403. See ADR-130 for the
# probe set and issue #6755 for the recorded results.
#
# ── PREREQUISITE 2: entrypoint adoption — SATISFIED ON APPLY (import block) ──
#
# A `kind = "zone"` ruleset OWNS its phase's entrypoint, which is a whole-list
# replacement. `plan` reports "1 to add" because the resource is absent from
# STATE — it cannot see rules created through the Cloudflare dashboard.
#
# That probe was run on 2026-07-20 and it FAILED CLOSED. The entrypoint already
# exists (a21ac79d368f425a95c895c43a090d57, version 1, last updated
# 2026-03-17) and carried one live dashboard-created rule:
#
#   description: "Flexible SSL for web platform"
#   expression:  (http.host eq "app.soleur.ai")
#   action:      set_config { ssl: "flexible" }
#
# Had this resource been applied as originally written — one rules block, no
# import — it would have deleted that rule and dropped app.soleur.ai to the
# zone-level SSL mode. Outage-class, and completely invisible to `plan`, which
# reported a clean "1 to add, 0 to change, 0 to destroy" throughout.
#
# Both halves of the fix are now in this file:
#   1. the rule is reproduced verbatim as the FIRST rules block below, and
#   2. the `import` block adopts the existing ruleset into state, so Terraform
#      UPDATES the entrypoint rather than creating it.
# Neither half is sufficient alone: (1) without (2) still creates and clobbers;
# (2) without (1) still deletes the rule on the next plan.
#
# Verified plan against live state. Re-run 2026-07-20 against the SHIPPED config
# — with the `for_each` gate and the `ref` pin both present. An earlier capture
# predated the gate and was therefore evidence about a config that no longer
# existed; re-running was cheaper than reasoning about whether it still applied.
#
#   Plan: 1 to import, 0 to add, 1 to change, 0 to destroy.
#
# — NOT the "1 to add" that task 3.1 originally recorded. The single change is
# `+1 rule`. With `ref` pinned, the adopted rule now carries NO `~` markers at
# all in the diff (its `id` and `ref` both stay
# `dcb85b75bc3c4f4aa2a8c13a080bf854` instead of going `(known after apply)`), so
# the plan proves the apply does not touch it. Only the new rule gets a fresh ID.
#
# **A plan that says "1 to add" means the import block was dropped.**
#
# ── ROLL FORWARD, NEVER REVERT ───────────────────────────────────────────────
#
# Once applied, this resource is in state, so `git revert` of the PR removes the
# resource AND the import block and Terraform plans a DESTROY of the entrypoint
# — deleting BOTH rules and dropping app.soleur.ai to the zone SSL mode (live
# zone setting is `strict`). That is strictly worse than the bug this file
# fixes, and the destroy-guard makes it look survivable: a full resource delete
# increments `resource_deletes`, so the gate prints "Add [ack-destroy] to
# acknowledge" — inviting exactly the bypass, under outage pressure, that
# completes the outage. Recovery from a bad apply is ROLL-FORWARD ONLY: fix the
# `rules` blocks and re-apply. If the entrypoint is ever emptied, the adopted
# rule is reproduced verbatim below and can be PUT back through the same
# `zones/$ZONE/rulesets/phases/http_config_settings/entrypoint` endpoint the
# ADR-130 probe set already curls — no dashboard needed.
#
# Tracked in #6767. Scope of that generalisation, corrected: the other four
# `kind = "zone"` rulesets in this repo (seo_page_redirects, seo_response_headers,
# allowlist_ai_crawlers, cache_shared_binaries, bulk_redirects) are ALREADY IN
# STATE — verified via `terraform state list` — so `plan` refreshes their
# entrypoints and would surface a dashboard-added rule as drift. Their exposure
# is RETROSPECTIVE (anything added before their own first apply is already
# gone), not the prospective hazard this file hit. #6767 SHIPPED both halves
# (ADR-133): the prospective PRE-APPLY GATE — tests/scripts/lib/preapply-entrypoint-gate.sh,
# wired as the "Pre-apply entrypoint gate" step in apply-web-platform-infra.yml,
# which fail-closes any FUTURE whole-list ruleset create-from-absent whose live
# entrypoint is non-empty — AND the retrospective drift-audit (the same script's
# --audit mode, run via the guarded entrypoint-audit dispatch).
#
# See:
#   - knowledge-base/project/plans/2026-07-20-fix-gsc-404-cdn-cgi-email-protection-plan.md
#   - knowledge-base/project/learnings/2026-05-05-gsc-indexing-triage-patterns.md
#   - seo-rulesets.tf (sibling rulesets on the same provider alias)
#   - Ref #3379 (the api.soleur.ai dormant-rule tracker — deliberately untouched here)

# ADOPTION, not creation. The http_config_settings entrypoint for this zone
# already exists and is already populated, so this resource IMPORTS it — see
# "PREREQUISITE 2" above.
#
# Import ID format is `zone/<zone_id>/<ruleset_id>` — SINGULAR `zone`, on the
# pinned provider 4.52.7. The published docs on the provider's `main` branch say
# `zones/...` (plural); that is v5 syntax and it FAILS HERE, but not loudly:
# v4 does not reject the unknown prefix, it silently falls through to the
# account-level path and issues
# `GET /accounts/<zone_id>/rulesets/<id>` — a zone ID in an accounts URL — which
# surfaces as `Authentication error (10000)`. The error names authentication, so
# it reads like a token-scope problem and sends you back to re-probe a
# credential that was already correct. Verified empirically against 4.52.7:
# 2-segment `<zone_id>/<ruleset_id>` → "invalid import identifier";
# `zones/...` → wrong-path auth error; `zone/...` → correct
# `GET /zones/<zone_id>/rulesets/<id>`.
# test/seo-config-rules.test.ts pins the singular form.
#
# `provider` here is EXPLICIT, not required: an import block DOES inherit its
# target resource's provider. Measured — with this line deleted and the DEFAULT
# `cloudflare` provider's token replaced by a garbage value, the plan still
# succeeded (`1 to import`), which is only possible via the `rulesets` alias.
# (An earlier revision of this comment claimed the opposite. It was wrong: the
# `zones/`→`zone/` ID fix alone resolved the failure, and adding `provider` had
# changed nothing.) Kept because it makes the credential legible at the call
# site, and pinned by the test so it cannot be dropped silently.
#
# The ruleset ID is hardcoded while the zone is a variable. That coupling is
# deliberate — the ID is valid only for this zone — and it fails CLOSED: a
# repointed `cf_zone_id`, or an entrypoint recreated in the dashboard, makes the
# import read fail rather than clobber. Note the blast radius, though: import
# targets are validated BEFORE `-target` pruning, so that failure aborts the
# whole ~70-target apply, not just this resource.
import {
  for_each = var.adopt_seo_config_entrypoint ? toset(["adopt"]) : toset([])
  provider = cloudflare.rulesets
  to       = cloudflare_ruleset.seo_config_settings
  id       = "zone/${var.cf_zone_id}/a21ac79d368f425a95c895c43a090d57"
}

# `name` and `description` deliberately mirror the live entrypoint EXACTLY
# ("default" / empty) rather than carrying a descriptive label. Cloudflare names
# every phase entrypoint "default", and matching it keeps the adoption plan to a
# single legible change — `+1 rule` — instead of mixing a real rule addition in
# with cosmetic attribute churn. The rationale that would have gone in a
# descriptive name lives in this file's header and in each rule's own
# `description`.
resource "cloudflare_ruleset" "seo_config_settings" {
  provider    = cloudflare.rulesets
  zone_id     = var.cf_zone_id
  name        = "default"
  description = ""
  kind        = "zone"
  phase       = "http_config_settings"

  # ── ADOPTED RULE — pre-existing, NOT part of this change ───────────────────
  #
  # Created in the Cloudflare dashboard on 2026-03-17, never represented in
  # Terraform. It is reproduced here verbatim because a `kind = "zone"` ruleset
  # owns its phase entrypoint as a whole-list replacement: omitting it does not
  # leave it alone, it DELETES it, dropping app.soleur.ai to the zone-level SSL
  # mode. test/seo-config-rules.test.ts pins this block for exactly that reason
  # — the regression it guards is a future edit quietly dropping it.
  #
  # Ordered first to match its live position. Order is not semantically
  # load-bearing here (both rules are set_config over disjoint host sets), but
  # matching live keeps the import diff empty.
  # `ref` is pinned to the live rule's existing ref, not omitted. The v4 provider
  # preserves rule IDs across a whole-list PUT by matching on `ref` — without it
  # the original ref is lost on first apply and BOTH rules re-randomise their IDs
  # on every future rule add/remove. Pinning it is what makes "reproduced
  # verbatim" literally true and removes the `(known after apply)` churn.
  rules {
    action      = "set_config"
    description = "Flexible SSL for web platform"
    enabled     = true
    expression  = "(http.host eq \"app.soleur.ai\")"
    ref         = "dcb85b75bc3c4f4aa2a8c13a080bf854"
    action_parameters {
      ssl = "flexible"
    }
  }

  # Scoped to the two marketing hosts ONLY. app./deploy./api. are deliberately
  # excluded — they serve no marketing copy, and including them would collapse
  # this into the rejected zone-wide option.
  #
  # test/seo-config-rules.test.ts pins this expression by EXACT EQUALITY, and
  # pins the ruleset to exactly two rules. Both are deliberate: a deny-list of
  # forbidden hostnames constrains spelling rather than scope, and review
  # produced several mutants that name no forbidden host yet widen the rule to
  # the whole zone (`or ends_with(http.host, ".soleur.ai")`, a `zone_name`
  # disjunct, a tautology) — plus one that appends a SECOND, wider rule, which
  # Cloudflare evaluates with full effect. Editing the scope therefore requires
  # editing the test's CANONICAL_EXPRESSION too. That is the feature.
  #
  # `in` with a set literal is exact membership — it does NOT expand to
  # subdomains (that would be `wildcard` / `matches` / `contains`).
  rules {
    action      = "set_config"
    description = "Disable Email Obfuscation on soleur.ai + www.soleur.ai (GSC 404 on /cdn-cgi/l/email-protection)"
    enabled     = true
    expression  = "(http.host in {\"soleur.ai\" \"www.soleur.ai\"})"
    action_parameters {
      email_obfuscation = false
    }
  }
}
