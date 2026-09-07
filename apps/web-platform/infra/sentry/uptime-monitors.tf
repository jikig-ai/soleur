# Sentry uptime monitors for soleur.ai — alerting half of the 2026-05-18 cert
# outage post-mortem (PR-β). The fix half landed in PR #3974 (initial codification
# of the ACME-aware HTTPS upgrade) and PR #3986 (inline of the carve-out into the
# seo_page_redirects ruleset). Issue #3976 was the operator runbook for cert
# recovery. The cert is now valid; this file is the "next time the carve-out
# silently regresses, hear about it before the next renewal fails" layer.
#
# Plan: knowledge-base/project/plans/2026-05-18-feat-soleur-ai-uptime-alerting-plan.md
#
# WHY FOUR MONITORS:
#   1. Apex (https://soleur.ai/) — primary canonical; what alpha users land on.
#   2. www (https://www.soleur.ai/) — REACHABILITY only, since #7798. It used to
#      claim redirect-health and never delivered it: `equals 301` is structurally
#      unsatisfiable on this substrate, because Sentry's uptime checker always
#      follows 3xx and evaluates assertions against the FINAL response, so it
#      compared 301 against the apex's 200 and failed every check it ever ran
#      (measured 2026-09-07: 10/10 failing, every row httpStatusCode 301). The
#      redirect-health property moved to Better Stack, the only vendor here that
#      can express it (`follow_redirects = false`):
#      betteruptime_monitor.soleur_www_redirect in ../uptime-alerts.tf,
#      "soleur dot ai www redirect 301". See ADR-204 and
#      knowledge-base/engineering/operations/runbooks/www-redirect-alarm.md.
#   3. Deep path (https://soleur.ai/changelog/) — proves the Eleventy build
#      didn't half-fail. Catches "root 200 but every other page 404s".
#   4. ACME carve-out probe — LOAD-BEARING. Alerts on Rule 10 regression in
#      cloudflare_ruleset.seo_page_redirects (seo-rulesets.tf:240-254). See
#      detailed comment on the soleur_acme_probe resource below.
#
# AUTO-APPLY NOTE: `.github/workflows/apply-sentry-infra.yml` plans and applies
# the FULL ROOT of this directory on push-to-`main` (#6589) — every resource
# here, plus anything left in state with no remaining block. It previously
# applied a hand-maintained per-resource `-target=` allow-list; that list made
# DELETION a silent no-op (a deleted block cannot be named in it), which
# orphaned live monitors twice (#4929, #6074). Uptime monitors joined the
# auto-apply in #4585.
#
# What that means when you edit this file: an added resource applies with no
# further wiring — there is no allow-list to also update. A REMOVED resource is
# now a real destroy, and the PR-time `sentry-destroy-required` gate will refuse
# to go green until a line `[ack-destroy]` is pre-staged in the BODY of a commit
# on the branch (not a commit subject — GitHub prefixes those with "* " when it
# composes the squash body, which breaks the anchor the apply gate matches).
#
# BETA STATUS: `sentry_uptime_monitor` may still be documented as beta in the
# provider (pinned v0.15.4 as of #6636 — see provider docs at
# github.com/jianyuan/terraform-provider-sentry/blob/main/docs/resources/uptime_monitor.md).
# The beta2 → v0.15.4 bump (#6636 Phase 0) planned no-op with no attribute drift
# on the 4 uptime monitors; the provider may still rename attributes when the
# resource graduates further.
# Re-validate the schema on every provider bump (`terraform init -upgrade`).
#
# ASSERTION SEMANTICS: the `assertion_json` argument is the SUCCESS condition.
# Sentry creates an issue (fires the alert) when the assertion evaluates FALSE.
# The 200-class monitors (apex, changelog deep) use a (>199 AND <300) assertion.
# The www monitor USED an `equals 301` assertion on the same reasoning, and that
# is exactly the trap this file now documents twice: every op in the catalog
# reads the TERMINAL response, so `equals 301` on a URL that redirects can never
# be true. It is a 2xx reachability probe since #7798 (ADR-204). The ACME probe uses an
# `equals 404` assertion — the synthetic /probe path has no real challenge
# token, so the only "healthy" response is the 404 that proves Cloudflare did
# NOT redirect (i.e., Rule 10's `and not (...)` ACME carve-out is still firing).

# 200-class success assertion: status in [200, 299].
locals {
  uptime_assertion_2xx = provider::sentry::assertion(
    provider::sentry::op_and(
      provider::sentry::op_status_code_check("greater_than", 199),
      provider::sentry::op_status_code_check("less_than", 300),
    )
  )
}

resource "sentry_uptime_monitor" "soleur_apex" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "soleur-ai-apex"
  environment  = "production"

  url              = "https://soleur.ai/"
  method           = "GET"
  interval_seconds = 300
  timeout_ms       = 10000

  # Three consecutive failed checks before paging (15 min sustained outage).
  # Absorbs single-probe-host hiccups without dampening real-incident signal.
  downtime_threshold = 3
  recovery_threshold = 1

  assertion_json = local.uptime_assertion_2xx
}

# STATE MIGRATION, NOT DECORATION. Renaming a resource's ADDRESS is a DESTROY +
# CREATE: Terraform's plan universe is `state UNION config`, so the old address has
# state and no config (delete) while the new one has config and no state (create).
# That is core Terraform and has nothing to do with the provider's RequiresReplace
# set -- an earlier draft of this change reasoned from `name` being an in-place
# ATTRIBUTE and concluded "update-only, no ack needed", which is a category error.
#
# Measured against destroy-guard-filter-sentry.jq: without this block the plan
# scores resource_deletes=1, resource_creates=1, so `sentry-destroy-required`
# blocks the PR; acked and merged it would delete the live detector and create a
# new one -- discarding its check history and opening a coverage gap between the
# two operations, on the monitor this change exists to repair. With the block:
# 0 to add, 0 to change, 0 to destroy.
moved {
  from = sentry_uptime_monitor.soleur_www
  to   = sentry_uptime_monitor.soleur_www_reachability
}

resource "sentry_uptime_monitor" "soleur_www_reachability" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "soleur-ai-www-reachability"
  environment  = "production"

  # RENAMED at #7798, and the rename is the point. This resource spent from
  # 2026-05-29 to 2026-09-07 named for a property it did not check. #4577 gave
  # it an `equals 301` assertion on the reasoning that www's only healthy
  # response is the 301 to apex — correct about the redirect, wrong about the
  # substrate. Sentry's uptime checker always follows 3xx and evaluates the
  # assertion against the FINAL response, so it compared `equals 301` to the
  # apex's 200 -- which it CANNOT satisfy. That is the structural claim, and it
  # is the load-bearing one. The MEASUREMENT is narrower and is stated as such:
  # on 2026-09-07 the 10 most recent checks were 10/10 failing, every row
  # `httpStatusCode 301`, `assertionFailureData` naming this assertion. Do not
  # round that up to "failed every check for 101 days" -- the checks endpoint
  # returns one page, nobody paged back to the assertion's landing, and the
  # `downtime_threshold`/flap note below records a contemporaneous observation
  # that does not obviously fit a 100% reading.
  #
  # Leaving it named `soleur_www` while retargeting the assertion would
  # reproduce, deliberately, the trap documented further down in this file on
  # soleur_acme_probe: a name that outlives the property it names. Hence the
  # rename, and hence the `description` — which the provider documents as
  # "used in the resulting issue", i.e. it reaches the operator rather than a
  # reader of this file.
  #
  # WHAT THIS GUARDS NOW: www is reachable and terminally healthy — DNS, TLS,
  # 5xx, and a redirect chain that lands somewhere serving 2xx. It follows the
  # 301, so it is green whether www 301s to the apex or serves its own 200.
  # WHAT IT DOES NOT GUARD: that the 301 still happens. That is
  # betteruptime_monitor.soleur_www_redirect ("soleur dot ai www redirect 301")
  # in ../uptime-alerts.tf, and nothing here will tell you if it breaks.
  #
  # The url stays www on purpose — that is the host under guard.
  url              = "https://www.soleur.ai/"
  method           = "GET"
  interval_seconds = 300
  timeout_ms       = 10000

  # 3 for parity with soleur_apex. REASON REWRITTEN at #7798, because the reason
  # this comment used to give was deleted by the same change.
  #
  # It read: the docs-deploy window that false-paged this monitor is "suppressed
  # AT THE SOURCE: deploy-docs.yml pauses this monitor ... then resumes it
  # (if: always())", so 3 costs nothing. That bracket is GONE -- #7798 removed it
  # and www-apex-canonicalizer.test.sh now FAILS THE BUILD if it returns, so a
  # reader following the old rationale would be blocked by CI with no explanation.
  #
  # 3 is still right, for a different reason: under the 2xx assertion above, the
  # transient 200 www serves during a Pages rebuild PASSES. There is no longer a
  # deploy window in this monitor's view to absorb, so the threshold does not
  # need to be widened and no suppression mechanism is required.
  #
  # HISTORICAL, retained because it is the one contemporaneous observation that
  # sits awkwardly with "this assertion never passed": #4595/#4596 record that a
  # 2026-05-29 deploy paged soleur_www at 12:30 for a "self-recovered ~15-min
  # flap" -- 12 minutes AFTER `equals 301` landed at 12:18 CEST. A self-recovery
  # implies a passing check. It is more likely that page belongs to the OLD 2xx
  # assertion (which the block comment above notes was itself mis-firing against
  # the live 301), but it is NOT resolved here, which is exactly why the claim
  # above is scoped to what was measured.
  downtime_threshold = 3
  recovery_threshold = 1

  description = "Guards REACHABILITY of https://www.soleur.ai/ only: DNS, TLS, 5xx, and a redirect chain terminating in a 2xx. It does NOT guard that www still 301s to the apex. Until #7798 it asserted equals 301 and failed every check it ever ran, because Sentry follows 3xx and evaluates assertions against the final response - it was comparing 301 to the apex 200. Redirect-health now lives on Better Stack, which can be told not to follow: betteruptime_monitor.soleur_www_redirect, alert name 'soleur dot ai www redirect 301'. If you are reading this in an incident, www is unreachable or erroring; a broken REDIRECT pages from Better Stack instead. Runbook: knowledge-base/engineering/operations/runbooks/www-redirect-alarm.md. Rationale: ADR-204."

  # Success = any 2xx, via the shared local. Sentry fires when that is FALSE.
  # Deliberately NOT `equals 301`: see the block comment above and ADR-204.
  # Note this assertion is satisfied both by "www 301s to a healthy apex" and by
  # "www serves its own 200" - it cannot distinguish them, which is precisely
  # why the redirect half had to move to a vendor that can.
  assertion_json = local.uptime_assertion_2xx
}

resource "sentry_uptime_monitor" "soleur_changelog_deep" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "soleur-ai-changelog-deep"
  environment  = "production"

  # Deep path — guards against the "root serves 200 but every other page 404s"
  # failure mode (Eleventy build half-broken, GitHub Pages serving stale-only).
  # 10-minute interval (cheaper than 5min, still well under any plausible
  # mean-time-to-fix for a static-site regression).
  url              = "https://soleur.ai/changelog/"
  method           = "GET"
  interval_seconds = 600
  timeout_ms       = 10000

  downtime_threshold = 3
  recovery_threshold = 1

  assertion_json = local.uptime_assertion_2xx
}

# ────────────────────────────────────────────────────────────────────────────
# LOAD-BEARING: ACME carve-out regression detector.
#
# The /.well-known/acme-challenge/probe path has NO real challenge token —
# it deliberately returns 404 (CF passes the request through to GitHub Pages,
# which 404s because the path doesn't exist in the published site). What this
# probe is actually checking is the *ABSENCE* of a 301 redirect.
#
# Rule 10 of cloudflare_ruleset.seo_page_redirects (seo-rulesets.tf:240-254) is
# a zone-wide HTTPS catch-all that redirects (not ssl) traffic to https — with
# a NEGATIVE match clause carving out apex+www requests under
# /.well-known/acme-challenge/* so Let's Encrypt's HTTP-01 challenge can hit
# the GH Pages origin on plain HTTP during cert renewal.
#
# If a future edit to that rule's expression drops the `and not (...)` clause
# (or scopes it wrong, or changes the host list), the carve-out silently
# regresses. The next cert renewal would then fail and the apex would 526 for
# ~24h until someone noticed — exactly the 2026-05-18 outage shape.
#
# This probe runs over plain HTTP intentionally — wait, NO: it runs over HTTPS
# because the probe path returns 404 *post*-redirect in normal operation (the
# carve-out only skips redirect for plain-HTTP requests on the ACME path).
# What the probe ACTUALLY catches is: if Rule 10's expression changes such
# that the HTTPS path /.well-known/acme-challenge/* starts getting redirected
# OR cached weirdly, the assertion fires.
#
# More precisely: under healthy ops, GET https://soleur.ai/.well-known/acme-challenge/probe
# returns 404 (CF passes through; GH Pages 404s). If Rule 10 regresses such
# that the ACME path no longer pass-through, the response shape changes
# (most likely to a 301 to a different host, or a 200 with a stale cache hit,
# or a 5xx if the origin path is unreachable). Any non-404 is a signal.
#
# The probe URL is intentionally synthetic — `/probe` is not a real token, and
# Let's Encrypt would never request it. We do not want to probe a real token
# path because (a) those rotate per cert issuance, and (b) when one is active,
# it returns the token-body 200, which would conflict with the equals-404
# assertion. The /probe synthetic name is stable and always-404 under healthy
# ops. Code-review check: confirm no future CI step or Eleventy build creates
# a real /.well-known/acme-challenge/probe file in _site — if it does, this
# monitor will false-fire.
resource "sentry_uptime_monitor" "soleur_acme_probe" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "soleur-ai-acme-carveout-probe"
  environment  = "production"

  url              = "https://soleur.ai/.well-known/acme-challenge/probe"
  method           = "GET"
  interval_seconds = 300
  timeout_ms       = 10000

  description = "Asserts 404 on the ACME challenge path. PRE-CUTOVER that detects a CF Rule 10 (seo_page_redirects ACME carve-out) regression, since the 404 is a passthrough to the GitHub Pages origin. From the #7640/ADR-194 Cloudflare Pages cutover it goes VACUOUS: Pages serves its own 404.html regardless of Rule 10, so the assertion is a permanent pass with zero coupling to the carve-out it names - while Rule 10 and its carve-out are explicitly RETAINED. Do not read green here as carve-out health post-cutover; the lost property is tracked on the #7640 deferred-cleanup issue. Carve-out under guard: Rule 10 in seo-rulesets.tf. The LOAD-BEARING comment above is scoped to the pre-cutover topology."

  downtime_threshold = 3
  recovery_threshold = 1

  # Success = exactly 404. Sentry fires when this assertion is FALSE — i.e.,
  # any non-404 status (200, 301, 302, 5xx) triggers a paging issue.
  assertion_json = provider::sentry::assertion(
    provider::sentry::op_status_code_check("equals", 404)
  )
}
