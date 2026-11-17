# Sentry uptime monitor for the production app (https://app.soleur.ai).
#
# Decision: ADR-328 (knowledge-base/engineering/architecture/decisions/
# ADR-328-sentry-uptime-holds-one-slot-for-the-production-app.md).
#
# WHY ONE MONITOR:
#   Sentry includes ONE uptime monitor on this plan; every further monitor bills
#   $1.00/mo. That one slot goes to the production app, declared here as a new
#   manual monitor that replaces the one Sentry auto-detected for the web-platform
#   project (detector 1422253, deleted through the API immediately before the
#   merge that creates this one; ADR-328 Sequencing), so
#   the app is second-sourced across two vendors (DC-1, #6606): Better Stack
#   PAGES for this URL (betteruptime_monitor.app, betteruptime_monitor.app_health
#   in ../uptime-alerts.tf); this monitor DETECTS (opens a Sentry issue) without
#   paging.
#
#   Marketing-site uptime (https://soleur.ai/, the www 301, the /changelog/ deep
#   path, the sampled redirect probes) is Better Stack's, not Sentry's (ADR-328).
#   The four Sentry marketing monitors that used to live here (apex, www
#   reachability, changelog deep path, ACME carve-out probe) were removed at
#   ADR-328; the changelog deep path moved to
#   betteruptime_monitor.soleur_changelog_deep. The ACME carve-out probe was
#   removed as VACUOUS: after the Cloudflare Pages cutover (#7640, ADR-194) Pages
#   serves its own 404 regardless of Rule 10, so its `equals 404` assertion could
#   not fail. The lost carve-out property stays open on #7799.
#
#   A second sentry_uptime_monitor anywhere in this directory bills a second slot.
#   The scheduled sentry-alert drift check counts the blocks in every .tf here and
#   reports any live uptime monitor beyond them, and www-apex-canonicalizer.test.sh
#   fails the PR unless the directory declares exactly one, on app.soleur.ai, with
#   no count/for_each, and none probing soleur.ai or www.soleur.ai.
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
# a real destroy, and the PR-time `sentry-destroy-required` gate will refuse
# to go green until a line `[ack-destroy]` is pre-staged in the BODY of a commit
# on the branch (not a commit subject — GitHub prefixes those with "* " when it
# composes the squash body, which breaks the anchor the apply gate matches).
#
# BETA STATUS: `sentry_uptime_monitor` may still be documented as beta in the
# provider (pinned v0.15.7 in versions.tf; first pinned at v0.15.4 in #6636 — see provider docs at
# github.com/jianyuan/terraform-provider-sentry/blob/main/docs/resources/uptime_monitor.md).
# The provider may still rename attributes when the resource graduates further.
# Re-validate the schema on every provider bump (`terraform init -upgrade`).
#
# ASSERTION SEMANTICS: the `assertion_json` argument is the SUCCESS condition.
# Sentry creates an issue (fires the alert) when the assertion evaluates FALSE.
# The app monitor uses a (>199 AND <300) assertion. Every op in the catalog reads
# the TERMINAL response — Sentry's uptime checker always follows 3xx — so an
# `equals 3xx` assertion on a URL that redirects can never be true (ADR-204).

# 200-class success assertion: status in [200, 299].
locals {
  uptime_assertion_2xx = provider::sentry::assertion(
    provider::sentry::op_and(
      provider::sentry::op_status_code_check("greater_than", 199),
      provider::sentry::op_status_code_check("less_than", 300),
    )
  )
}

# CREATED, NOT IMPORTED (ADR-328; decision-challenges D2). Sentry auto-detected
# https://app.soleur.ai and runs it as detector 1422253 in mode 3 (auto-detected).
# This block creates a separate manual monitor for the same URL. 1422253 is
# deleted through the API (GET, DELETE, GET expecting 404; D3a) immediately
# BEFORE the merge that adds this block, not after: the post-apply fidelity probe
# in apply-sentry-infra.yml fails on any live non-manual uptime monitor, so a
# later delete would red the merge's own apply run. Better Stack pages for the
# app in the minutes between the delete and the apply.
# An `import {}` is not usable here: scripts/sentry-adoption-plan-assert.sh
# reads any import or forget row as the #7650 alert adoption and fails the plan.
resource "sentry_uptime_monitor" "app" {
  organization = var.sentry_org
  project      = data.sentry_project.web_platform.slug
  name         = "soleur-app-reachability"
  environment  = "production"

  # The exact live string, no trailing slash: a different url is a different
  # monitor to Sentry, and a drift between this and live re-plans every run.
  url              = "https://app.soleur.ai"
  method           = "GET"
  interval_seconds = 60
  timeout_ms       = 10000

  # Three consecutive failed checks before opening an issue (3 min sustained
  # outage at a 60 s interval). Absorbs single-probe-host hiccups.
  downtime_threshold = 3
  recovery_threshold = 1

  description = "The one included Sentry uptime slot (ADR-328): reachability of the production app https://app.soleur.ai, second-sourced across two vendors (DC-1, #6606). Better Stack PAGES for this URL (betteruptime_monitor.app and betteruptime_monitor.app_health in apps/web-platform/infra/uptime-alerts.tf); this monitor DETECTS - it opens a Sentry issue and does not page. If you are reading this in an incident, check the Better Stack incident for the same window first. Marketing-site uptime (soleur.ai, www) is Better Stack only."

  assertion_json = local.uptime_assertion_2xx

  # PERMANENT - do not drop in a tidy-up. The provider's read never sets
  # `project`, and `project` carries RequiresReplace: if state ever loses it
  # (a re-import, a state rebuild), the next plan would destroy and re-create
  # this monitor.
  lifecycle {
    ignore_changes = [project]
  }
}
