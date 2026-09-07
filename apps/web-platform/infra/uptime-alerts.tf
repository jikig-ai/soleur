# BetterStack uptime + Cloudflare origin-5xx notification — alerting half of
# the 2026-05-18 cert outage post-mortem (PR-β). The fix half landed in PR
# #3974 (initial codification of the ACME-aware HTTPS upgrade) and PR #3986
# (inline of the carve-out into the seo_page_redirects ruleset). Issue #3976
# was the operator runbook for cert recovery. The Sentry half of the alerting
# stack lives at apps/web-platform/infra/sentry/uptime-monitors.tf — these two
# resources are the second-source (BetterStack — independent vendor for
# vendor-isolation) and the page-level error-rate alert (Cloudflare native).
#
# Plan: knowledge-base/project/plans/2026-05-18-feat-soleur-ai-uptime-alerting-plan.md
#
# Why this lives in the main web-platform root (not the sentry root): the
# betterstackhq and cloudflare providers are declared here (main.tf:35-49,
# 21-24). Sentry's own resources live in the sentry/ subroot because that's
# where the jianyuan/sentry provider is declared (sentry/versions.tf:8-11).
# Reuses two existing roots — does NOT create a new one, per
# hr-every-new-terraform-root-must-include-an.

# ── BetterStack: multi-region apex uptime monitor ───────────────────────────
#
# Second-source apex check — independent vendor from Sentry. If Sentry itself
# is degraded (status.sentry.io or our specific org subdomain), this monitor
# still pages. Same logic as the inngest heartbeat (inngest.tf:108-138) and
# the inngest policy (inngest.tf:140-156) — paid-tier features gated on
# var.betterstack_paid_tier (defaults false → email-only on free tier).
#
# Why apex only (not www / not the deep path / not the ACME probe):
#   - The 4 Sentry monitors give us per-URL coverage already. BetterStack is
#     here for VENDOR ISOLATION, not URL coverage. One probe is enough to
#     prove "soleur.ai is reachable" when Sentry is the one that's broken.
#   - Free-tier BetterStack caps the workplace at 10 monitors. Headroom matters.
#
# AMENDED at #7798 (ADR-204), narrowly and deliberately. "Vendor isolation, not
# URL coverage" still governs everything above; it no longer governs a property
# SENTRY CANNOT EXPRESS AT ALL. Sentry's uptime checker always follows 3xx and
# evaluates every assertion against the FINAL response, so "www must 301 to the
# apex" is not a weaker assertion there — it is an unwritable one. Better Stack's
# `follow_redirects = false` is the only knob in the stack that can express it.
# So betteruptime_monitor.soleur_www_redirect below is here on capability
# grounds, not coverage grounds, and the amendment extends no further than that.
#
# Consequence a future reader must not get wrong: redirect-health is now a
# SINGLE-VENDOR property. Apex reachability is watched by Sentry AND Better
# Stack, so a Sentry outage is survivable; the www 301 is watched only here. That
# is a gain (the property went from zero working alarms to one, not from two to
# one), but do not infer second-sourcing from the apex pattern. ADR-204 says so
# explicitly. Runbook: knowledge-base/engineering/operations/runbooks/www-redirect-alarm.md
#
# Live quota measured 2026-09-07 (not counted from .tf blocks, which misses the
# unmanaged app.soleur.ai/health monitor): 3 monitors + 9 heartbeats. Heartbeats
# are NOT pooled against the 10-monitor cap — 12 resources already coexist. This
# monitor is the 4th of 10. Two tracked follow-ups, both also linked from ADR-204:
#   #7883 — no runtime assertion of the redirect's TARGET (only its status code);
#           re-evaluate if a Cloudflare-side change ever reaches prod un-applied.
#   #7884 — betteruptime monitor id 4226366 (app.soleur.ai/health) is LIVE but
#           declared in no root, so nothing converges it and it is invisible to
#           the #5566 coverage guard. It is why the count above is measured.
#
# Why check_frequency = 180 (3 min) vs Sentry's 300s (5 min): denser probe
# trades a tiny BetterStack-bill bump (free-tier sub-minute checks are paid;
# 3-minute is free-tier-allowed per BetterStack pricing snapshot 2026-05) for
# faster mean-time-to-detect during a real outage. Sentry stays at 5min
# because four probes at 5min == one probe at 75s mean across the four; the
# combined cadence is already dense.
#
# follow_redirects = true. NOTE the direction, which this comment had backwards
# until #7749: the APEX is canonical and serves 200; WWW 301s to the apex. Measured
# 2026-09-02 — `curl -o /dev/null -w '%{http_code} %{redirect_url}'` gives
# `200` for https://soleur.ai/ and `301 https://soleur.ai/` for www. The
# www→apex direction is the one seo-bulk-redirects.tf implements and the one
# sentry/uptime-monitors.tf asserts. (It has been inverted here since #4577.)
#
# follow_redirects still earns its keep: it means this monitor succeeds only on a
# terminal 200, so it cannot be satisfied by a redirect into a broken target.
#
# verify_ssl = true: this probe terminates TLS at the CLOUDFLARE EDGE, because
# `url` is https://soleur.ai/ and the apex is proxied. So it validates
# Cloudflare's certificate, which Cloudflare auto-renews.
#
# ssl_expiration IS DELIBERATELY OMITTED, and the reason changed at #7749 — the
# justification that used to sit here is stale and was corrected there.
#
# It read: origin-cert expiry would be caught by "Sentry + this monitor's
# regular failure" anyway. That leaned on the daily `cron-gh-pages-cert-state`
# poll, which ADR-194 has since disarmed. But the conclusion still holds, for a
# stronger reason: THERE IS NO LONGER AN EXPIRY TO WARN ABOUT.
#
# The GitHub Pages origin certificate expired 2026-08-16 13:53:34Z and is
# intentionally never renewed (ADR-194 abandons it at the cutover; it cannot
# renew while proxied). The site serves 200 regardless, because the `ssl =
# "full"` rule in seo-config-rules.tf tells Cloudflare not to validate it.
#
# So setting ssl_expiration here would watch the edge certificate — a cert that
# is never at risk — and stay green forever. It would look like coverage of the
# origin cert and provide none, which is worse than omitting it. If you want to
# observe the origin cert, probe a Pages anycast IP with SNI directly:
#
#   echo | openssl s_client -servername soleur.ai -connect 185.199.108.153:443
#
# What these monitors DO detect is the HTTP 526 that appears within one check
# interval if the `ssl = "full"` rule is removed while the origin cert is
# expired. That rule is guarded by infra/ssl-full-mitigation.test.sh.
resource "betteruptime_monitor" "soleur_apex" {
  monitor_type       = "status"
  url                = "https://soleur.ai/"
  pronounceable_name = "soleur dot ai apex"

  check_frequency     = 180
  request_timeout     = 10
  confirmation_period = 60
  recovery_period     = 60
  follow_redirects    = true

  email = true
  call  = false
  sms   = false
  push  = false

  # Literal name of the only team in the workplace — see inngest.tf:120-129
  # for the case-sensitivity quirk and the rationale for hardcoding vs
  # promoting to a variable.
  team_name = "Your team"
  policy_id = var.betterstack_paid_tier ? betteruptime_policy.uptime[0].id : null

  verify_ssl = true
  paused     = false
}

# App dashboard uptime monitor (app.soleur.ai) — the LB-fronted surface users actually hit.
# REPLACES the #5933 per-host absence detector (betteruptime_monitor.web_host): with the
# multi-host cluster fronted by Cloudflare, an external per-host HTTP probe requires each
# host's origin to serve its own web-<n>.soleur.ai Host/SNI — it does not (the probe returned
# CF 521 because the origin only answers the app.soleur.ai Host, both records sharing one
# origin IP). Per-host "is this specific host dead" is better covered by Cloudflare LB origin
# health checks + the per-host resource-monitor.sh/container-restart-monitor.sh emails to
# ops@ — not an external HTTP monitor that would need per-host origin vhosts/certs. So we
# monitor app.soleur.ai directly; a dead host is drained by the LB and the remaining pool
# keeps this green, which is the correct user-facing signal.
#
# follow_redirects = true: app.soleur.ai/ 307s to /login for an unauthenticated probe, so
# the monitor succeeds only if the full chain / -> 307 -> /login -> 200 returns 200 (proves
# the app is actually serving, not just that the CF edge answered).
resource "betteruptime_monitor" "app" {
  monitor_type       = "status"
  url                = "https://app.soleur.ai/"
  pronounceable_name = "soleur app dashboard"

  check_frequency     = 180
  request_timeout     = 10
  confirmation_period = 60
  recovery_period     = 60
  follow_redirects    = true

  email = true
  call  = false
  sms   = false
  push  = false

  team_name = "Your team"
  policy_id = var.betterstack_paid_tier ? betteruptime_policy.uptime[0].id : null

  verify_ssl = true
  paused     = false
}

# ── The www→apex 301 redirect alarm (#7798, ADR-204) ───────────────────────
#
# This monitor exists because the one that was supposed to hold this role never
# worked. sentry_uptime_monitor.soleur_www asserted `equals 301` on this exact
# URL and failed EVERY check it ever ran: Sentry's uptime checker always follows
# 3xx and evaluates assertions against the final response, so it compared
# `equals 301` against the apex's 200. Measured 2026-09-07 — 10/10 checks
# failing, every row httpStatusCode 301, assertionFailureData naming that
# assertion. That monitor is now retargeted to 2xx REACHABILITY and renamed
# sentry_uptime_monitor.soleur_www_reachability; the redirect-health half lives
# here, on the only vendor that can express it.
#
# Two alarms now watch www and they mean different things. In an inbox:
#   "soleur dot ai www redirect 301"  → www stopped 301-ing to the apex
#   "soleur-ai-www-reachability"      → www is unreachable / 5xx
#
# Runbook: knowledge-base/engineering/operations/runbooks/www-redirect-alarm.md
# The redirect itself is declared in seo-bulk-redirects.tf
# (cloudflare_list.www_canonical); PR-time config drift is guarded by
# infra/www-apex-canonicalizer.test.sh, which also pins the four load-bearing
# attributes below.
resource "betteruptime_monitor" "soleur_www_redirect" {
  # `status` means "2xx-only" and cannot express a 301. This type is what makes
  # the status-code list below meaningful. Free-tier acceptance of the type was
  # MEASURED at #7798 Phase 0 (HTTP 201), because the only in-repo precedent for
  # it is paid-tier-count-gated and has therefore never actually run.
  monitor_type       = "expected_status_code"
  url                = "https://www.soleur.ai/"
  pronounceable_name = "soleur dot ai www redirect 301"

  # THE SINGLE TOKEN THAT SEPARATES THIS MONITOR FROM THE BROKEN ONE. With
  # follow_redirects = true the probe resolves to the apex 200 and [301] can
  # never match — precisely the #7798 defect. Better Stack also refuses the
  # combination outright (measured: HTTP 422 "Cannot follow redirects when
  # expecting a 3xx status code"), so this fails at PR time via the guard and
  # again at apply time via the vendor.
  follow_redirects = false

  # Exact list, not a 3xx class: a 302/307/308 is a different canonicalization
  # contract to search engines, and admitting a 2xx would admit the exact state
  # this monitor exists to catch (www serving the site instead of redirecting).
  expected_status_codes = [301]

  # NOT optional, despite looking like a default. The attribute is `computed` in
  # the pinned provider, so omitting it sends nothing and the API default (true)
  # applies — and Better Stack then REFUSES the create: HTTP 422 "Cannot keep
  # cookies when redirecting when expecting a 3xx status code". Measured against
  # the live API at #7798 Phase 0; without this line the resource never applies.
  remember_cookies = false

  check_frequency = 180 # free-tier-allowed 3 min, matching both siblings
  request_timeout = 10

  # 1200, deliberately NOT 900. During a Pages rebuild www transiently serves its
  # own 200, observed at ~15 min — and 900 is exactly that, i.e. zero margin, so a
  # rebuild running slightly long would open a false incident on the very class
  # this setting exists to absorb. 1200 buys ~5 min of margin. The cost is
  # symmetric and is stated rather than buried: the same timer bounds real
  # regression detection. Worst case ADDS the cadence: up to 180 s to observe the
  # first failure, then the 1200 s window = 1380 s, ~23 min. That replaces a bound
  # dns.tf's Camp B ruling assumed was "one monitor interval" and which was in
  # fact never delivering anything, the assertion behind it having never passed.
  confirmation_period = 1200
  recovery_period     = 60

  email = true
  call  = false
  sms   = false
  push  = false

  team_name = "Your team"

  # Follows the file convention rather than omitting it. Under the free tier the
  # ternary is null and this changes nothing; omitting the attribute instead
  # would silently exclude this monitor from escalation on a future
  # betterstack_paid_tier flip, unlike every sibling.
  policy_id = var.betterstack_paid_tier ? betteruptime_policy.uptime[0].id : null

  verify_ssl = true
  paused     = false
}

# Conditional escalation policy — mirrors betteruptime_policy.inngest
# (inngest.tf:140-156). count-gated on the same paid-tier flag so a free-tier
# operator does not see an apply-time error attempting to create a paid feature.
resource "betteruptime_policy" "uptime" {
  count = var.betterstack_paid_tier ? 1 : 0

  name           = "soleur-uptime-policy"
  incident_token = null
  repeat_count   = 3
  repeat_delay   = 60

  steps {
    type        = "escalation"
    wait_before = 0
    urgency_id  = null
    step_members {
      type = "current_on_call"
    }
  }
}

# ── Better Stack managed alert recipient: ops@jikigai.com ──────────────────
#
# ops@jikigai.com as a managed Better Stack team member so free-tier heartbeat/
# monitor email alerts reach ops@ (not just the account owner, jean.deruelle@).
# Root cause of the unacknowledged soleur-registry-disk-prd incident: recipients
# were not managed in Terraform at all, so only the account owner was emailed.
#
# No new no-default var — the betteruptime provider authenticates via the existing
# var.betterstack_api_token (main.tf:66-68). ops@ is the operator's own contact
# address, not a secret. role = "responder" is the provider default and free-tier
# valid (Phase 0.1: schema — email required, role optional, team_name optional).
# team_name = "Your team" mirrors every other team-scoped betteruptime resource in
# this root (the global token routes to the named team — see soleur_apex above,
# inngest.tf:120-129 for the case-sensitivity rationale).
#
# INERT until ops@ accepts the one-time invite (ops@'s own inbox — analogous to
# OAuth consent). A pending (un-accepted) member receives no alerts; free-tier
# non-owner routing is best-effort. Documented fallback if it proves owner-only:
# betteruptime_outgoing_webhook forward or a Responder-tier upgrade (expense-gated).
# #6604 — the DAILY /workspaces LUKS at-rest probe heartbeat (DP-10: the steady-state dead-probe
# switch, distinct from the soak's log-line query). luks-monitor.sh pushes it once a day on a
# fully-green escrow+header re-test, so a MISSED push (period 86400 + 1h grace) pages — a dead probe
# fails the heartbeat (P1-4). paused until the operator unpauses at cutover; policy-gated on the
# paid tier like every sibling heartbeat. Mirrors betteruptime_heartbeat.git_data_prd.
resource "betteruptime_heartbeat" "workspaces_luks" {
  name      = "soleur-workspaces-luks-prd"
  period    = 86400
  grace     = 3600
  call      = false
  sms       = false
  email     = true
  push      = false
  team_wait = 0
  team_name = "Your team"
  policy_id = var.betterstack_paid_tier ? betteruptime_policy.uptime[0].id : null
  paused    = true

  lifecycle {
    # Operator unpause via UI MUST NOT be reverted by subsequent applies (mirrors git_data_prd).
    ignore_changes = [paused]
  }
}

# #6604 — luks-monitor.sh reads this URL with the SAME pinned `doppler secrets get … --config
# prd_workspaces_luks` form as the passphrase (so the probe never widens to `doppler run`). Kept
# HERE (beside the heartbeat), NOT in workspaces-luks.tf, whose anti-laundering guard
# (workspaces-luks.test.sh A9/A11) forbids any extra resource / ignore_changes in that pristine
# five-resource security surface. Mirrors doppler_secret.git_data_heartbeat_url_prd; it +
# betteruptime_heartbeat.workspaces_luks are BOTH OPERATOR_APPLIED_EXCLUSIONS, applied together by
# the operator apply. NOT one of the five cutover-gate resources; never rides the gated cutover set.
resource "doppler_secret" "workspaces_luks_heartbeat_url" {
  project    = "soleur"
  config     = "prd_workspaces_luks"
  name       = "WORKSPACES_LUKS_HEARTBEAT_URL"
  value      = betteruptime_heartbeat.workspaces_luks.url
  visibility = "masked"

  lifecycle {
    ignore_changes = [value] # URL is stable per heartbeat resource lifetime.
  }
}

resource "betteruptime_team_member" "ops" {
  email     = "ops@jikigai.com"
  role      = "responder"
  team_name = "Your team"
}

# ── Cloudflare zone-level origin-5xx notification policy: NOT shipped ──────
#
# PR #4003 originally declared a `cloudflare_notification_policy` with
# alert_type = "http_alert_origin_error" to catch CF-526-class origin cert
# outages at the edge. Three apply attempts produced three different errors:
#   1. PR #4003 — no filters block → API error 17103 (filters required).
#   2. PR #4015 — filters.zones only → 17103 again (zones alone insufficient).
#   3. PR #4018 — filters.zones + filters.slo → API error 17200: "account is
#      not entitled to create policies for the alert type".
#
# Resolution: none of the http_alert_* types
# (http_alert_origin_error / http_alert_edge_error / advanced_http_alert_error)
# are in the account's available_alerts list. They are Enterprise-tier
# features and the soleur account does not have them. Confirmed via:
#   GET /accounts/{cf_account_id}/alerting/v3/available_alerts
#
# The post-mortem scenario this policy was meant to alert on — 526 origin
# cert validation failures — is already covered by:
#   - `sentry_uptime_monitor.soleur_apex` (5-min interval, 3-fail trip)
#   - `sentry_uptime_monitor.soleur_www_reachability` (renamed at #7798; it was
#     `soleur_www` and asserted `equals 301`, which it could never satisfy -- so
#     read this row as covering 526 only since the 2xx retarget)
#   - `sentry_uptime_monitor.soleur_acme_probe` (ACME-carve-out regression alarm)
#   - `betteruptime_monitor.soleur_apex` (3-min multi-region, vendor-isolated)
# A 526 either fails the TLS handshake or returns a 5xx — both fire the
# uptime monitors. The CF-native policy was belt-and-suspenders, not load-bearing.
#
# Operator follow-up: if/when the CF plan is upgraded to a tier that includes
# http_alert_origin_error, re-introduce this resource with the v4 syntax
#   filters { zones = [var.cf_zone_id]; slo = ["99.9"] }
# documented in PR #4018 before deletion.
