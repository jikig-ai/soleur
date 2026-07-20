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
# the existing token rather than minting an alias is ADR-128.
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
# account-level rulesets endpoint must all return non-403. See ADR-128 for the
# probe set and issue #6755 for the recorded results.
#
# ── PREREQUISITE 2: entrypoint adoption — SATISFIED via the import block ─────
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
# Verified plan after this change (2026-07-20, run against live state):
#
#   Plan: 1 to import, 0 to add, 1 to change, 0 to destroy.
#
# — NOT the "1 to add" that task 3.1 originally recorded. The single change is
# `+1 rule`; the Flexible SSL rule appears in the diff with every attribute
# unchanged. **A plan that says "1 to add" means the import block was dropped
# and the clobber is back.**
#
# The adopted rule's `id`/`ref` do show as `-> (known after apply)`. That is
# inherent to how the v4 provider writes a ruleset — a whole-list PUT, so
# Cloudflare reassigns rule IDs — and is atomic. The rule's expression, action,
# parameters and enabled state are all preserved; only its opaque ID changes.
#
# Tracked in #6767. The generalisation — every other `kind = "zone"` ruleset in
# this repo has the same exposure and was never enumerated — is open there too.
#
# See:
#   - knowledge-base/project/plans/2026-07-20-fix-gsc-404-cdn-cgi-email-protection-plan.md
#   - knowledge-base/project/learnings/2026-05-05-gsc-indexing-triage-patterns.md
#   - seo-rulesets.tf (sibling rulesets on the same provider alias)
#   - Ref #3379 (the api.soleur.ai dormant-rule tracker — deliberately untouched here)

# ADOPTION, not creation. The http_config_settings entrypoint for this zone
# already exists and is already populated, so this resource must IMPORT it —
# see "PREREQUISITE 2" above. Creating instead would replace the entrypoint's
# whole rule list.
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
#
# `provider` is also required and is NOT inherited from the target resource.
# Without it the import read runs through the DEFAULT `cloudflare` provider,
# whose token holds none of the ruleset permissions.
# Gates the import block below. Production default is `true` — adopt.
#
# This exists solely because `mock_provider` does NOT mock `import` blocks:
# Terraform performs the import read against the REAL provider even under
# `terraform test`, so the credential-free `terraform test` leg in
# infra-validation.yml fails with `Authentication error (10000)` before any of
# its actual assertions run. `tests/web-hosts-eu-pin.tftest.hcl` sets this to
# `false` for that reason and that reason only.
#
# DO NOT flip this default. At `false` the import disappears, Terraform plans a
# create against an entrypoint that already exists, and the whole-list clobber
# (#6767) is silently back with no other visible change to this file.
# test/seo-config-rules.test.ts pins the default at `true`.
variable "adopt_seo_config_entrypoint" {
  type    = bool
  default = true
}

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
  rules {
    action      = "set_config"
    description = "Flexible SSL for web platform"
    enabled     = true
    expression  = "(http.host eq \"app.soleur.ai\")"
    action_parameters {
      ssl = "flexible"
    }
  }

  # Scoped to the two marketing hosts ONLY. app./deploy./api. are deliberately
  # excluded — they serve no marketing copy, and including them would collapse
  # this into the rejected zone-wide option.
  #
  # test/seo-config-rules.test.ts pins this expression by EXACT EQUALITY, and
  # pins the ruleset to exactly one rule. Both are deliberate: a deny-list of
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
