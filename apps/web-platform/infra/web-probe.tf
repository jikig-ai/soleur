# --- #6438 / #6548: web-host private-net CONSUMER-perspective probe heartbeats -----------------
# The "#5274 PR C" vehicle. Three tracked gaps share one delivery substrate (an SSH terraform_data
# provisioner in server.tf, the sole path that reaches the cx33-unrebuildable web-1):
#   §1 (#6438) — a zot CONSUMER probe: web-1 verifies it can actually SERVE an image from the zot
#                registry over the private NIC, then pings web_zot_consumer; absence alarms.
#   §3 (#6438) — a private-NIC self-report (web_nic_guard) that emits SOLEUR_PRIVATE_NIC and pings
#                a dedicated liveness beat every healthy run (detect + emit + alarm, NO reboot).
#   #6548     — git-data reachability arms the EXISTING git_data_prd (git-data.tf).
#
# for_each = var.web_hosts: single live beat today (web-1), anti-masking preserved BY CONSTRUCTION
# for future active-active-N (#6459) — each host gets its OWN heartbeat, so a healthy host can never
# mask a broken sibling. No hardcoded web-2 resource (it retired 2026-07-17, #6538; a dead feeder
# would red heartbeat-reprovision-parity.test.ts). free-tier heartbeats are unconditionally
# creatable (only betteruptime_policy/_monitor are count-gated); email-only escalation
# (betterstack_paid_tier stays false; paid-tier escalation is #6549 item 1).

locals {
  # The zot repository path the consumer probe HEADs (tag-INDEPENDENT `/v2/<repo>/tags/list`, so it
  # never goes stale across deploys). Derived from var.image_name: strip the ghcr.io host, then keep
  # the path before any `:tag` or `@sha256:` — e.g. ghcr.io/jikig-ai/soleur-web-platform:latest →
  # jikig-ai/soleur-web-platform. zot mirrors GHCR under the identical repository path.
  zot_probe_repo = regex("^[^:@]+", replace(var.image_name, "ghcr.io/", ""))
}

# §1 — zot consumer-perspective serviceability heartbeat (per host).
resource "betteruptime_heartbeat" "web_zot_consumer" {
  for_each = var.web_hosts

  name      = "soleur-web-zot-consumer-${each.key}"
  period    = 180
  grace     = 60
  call      = false
  sms       = false
  email     = true
  push      = false
  team_wait = 0
  team_name = "Your team"
  policy_id = var.betterstack_paid_tier ? betteruptime_policy.uptime[0].id : null
  # paused in source; the apply-workflow arm gate PATCHes paused=false ONLY after a real measured
  # beat lands (ADR-117 automated). ignore_changes=[paused] so that unpause is never reverted.
  paused = true

  lifecycle {
    ignore_changes = [paused]
  }
}

# §3 — private-NIC-guard liveness heartbeat (per host). PERMANENT and INDEPENDENT of the zot beat:
# a SOLEUR_PRIVATE_NIC emit that never fires is indistinguishable from "guard dead", so the guard
# pings this every healthy run to be observable-when-healthy. NOT subsumed by the zot beat (folding
# would re-introduce OR-masking across two distinct failure domains).
resource "betteruptime_heartbeat" "web_nic_guard" {
  for_each = var.web_hosts

  name      = "soleur-web-nic-guard-${each.key}"
  period    = 360
  grace     = 120
  call      = false
  sms       = false
  email     = true
  push      = false
  team_wait = 0
  team_name = "Your team"
  policy_id = var.betterstack_paid_tier ? betteruptime_policy.uptime[0].id : null
  paused    = true

  lifecycle {
    ignore_changes = [paused]
  }
}

# Per-host heartbeat URLs → Doppler soleur/prd. The probe/guard systemd units resolve their host's
# own URL by indirect expansion (${!<KEY>}) over the WEB_*_URL_KEY name baked into their env file,
# so these secrets are GENUINELY consumed (not a reserved-but-inert reservation — the anti-pattern
# doppler_secret.zot_heartbeat_url_prd was deleted for, #6438 B3). Masked, same class as every
# existing heartbeat URL secret.
resource "doppler_secret" "web_zot_consumer_url" {
  for_each = var.web_hosts

  project    = "soleur"
  config     = "prd"
  name       = "WEB_ZOT_CONSUMER_URL_${upper(replace(each.key, "-", "_"))}"
  value      = betteruptime_heartbeat.web_zot_consumer[each.key].url
  visibility = "masked"
}

resource "doppler_secret" "web_nic_guard_url" {
  for_each = var.web_hosts

  project    = "soleur"
  config     = "prd"
  name       = "WEB_NIC_GUARD_URL_${upper(replace(each.key, "-", "_"))}"
  value      = betteruptime_heartbeat.web_nic_guard[each.key].url
  visibility = "masked"
}
