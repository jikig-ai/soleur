# --- #6438 / #6548: web-host private-net CONSUMER-perspective probe heartbeats -----------------
# The "#5274 PR C" vehicle. Three tracked gaps share one delivery substrate (an SSH terraform_data
# provisioner in server.tf, the sole path that reaches the cx33-unrebuildable web-1):
#   §1 (#6438) — a zot CONSUMER probe: web-1 verifies it can actually SERVE an image from the zot
#                registry over the private NIC, then pings web_zot_consumer; absence alarms.
#   §3 (#6438) — a private-NIC self-report (web_nic_guard) that emits SOLEUR_PRIVATE_NIC and pings
#                a dedicated liveness beat every healthy run (detect + emit + alarm, NO reboot).
#   #6548     — git-data reachability arms the EXISTING git_data_prd (git-data.tf).
#
# for_each = var.web_hosts: one beat per host in that map (web-1 and, since 2026-07-24, web-2; see
# variables.tf), anti-masking preserved BY CONSTRUCTION for active-active-N (#6459) — each host gets its
# OWN heartbeat, so a healthy host can never mask a broken sibling. No hardcoded per-host resource (a dead
# feeder would red heartbeat-reprovision-parity.test.ts). free-tier heartbeats are unconditionally
# creatable (only betteruptime_policy/_monitor are count-gated); email-only escalation
# (betterstack_paid_tier stays false; paid-tier escalation is #6549 item 1).

locals {
  # The zot repository paths the consumer probe HEADs (tag-INDEPENDENT `/v2/<repo>/tags/list`, so it
  # never goes stale across deploys). The web repo is derived from var.image_name: strip the ghcr.io
  # host, then keep the path before any `:tag` or `@sha256:` — e.g.
  # ghcr.io/jikig-ai/soleur-web-platform:latest → jikig-ai/soleur-web-platform. zot mirrors GHCR under
  # the identical repository path.
  zot_probe_repo_web = regex("^[^:@]+", replace(var.image_name, "ghcr.io/", ""))

  # The second repository a fresh host pulls at first boot (#7258): the repository path of the ZIREF
  # pins in cloud-init.yml and cloud-init-inngest.yml. A literal here, NOT a root variable:
  # variables.tf is a registry-host-replace trigger path (and server.tf a deploy-pipeline-fix one), so
  # a new variable would wake the registry-replace gate (a no-op unless a render input changes) for a
  # one-line probe change. The suite (web-zot-consumer-probe.test.sh, T7) derives the expected path
  # from those pins and fails if this constant drifts from them.
  zot_probe_repo_inngest_bootstrap = "jikig-ai/soleur-inngest-bootstrap"

  # The comma-separated list the probe takes. The local KEEPS its name and stays BARE, so every consumer
  # (the cloud-init templatefile var, hence the env file a host writes once at birth) is unchanged. The probe
  # pings its heartbeat only when EVERY repository in the list serves.
  zot_probe_repo = join(",", [local.zot_probe_repo_web, local.zot_probe_repo_inngest_bootstrap])

  # The digest a fresh host pulls for the bootstrap image (#10004), READ from the ZIREF line it must equal and
  # never restated here, so every pin bump moves it. The pattern is anchored on `ZIREF="`: a comment in that
  # file mentions the pin and must not match. A regex with one capture group returns a LIST, hence the [0].
  # A pin line that stops matching fails the plan loudly, which is the intended direction.
  zot_probe_digest_inngest_bootstrap = regex("(?m)^\\s*ZIREF=\"[^\"/]*/${local.zot_probe_repo_inngest_bootstrap}:v[0-9]+\\.[0-9]+\\.[0-9]+@(sha256:[0-9a-f]{64})\"", file("${path.module}/cloud-init-inngest.yml"))[0]

  # The list web-1's probe is handed (server.tf: the triggers_replace entry and the env-file printf of
  # terraform_data.zot_consumer_probe_install, the only path that re-delivers web-1's env file). The bootstrap
  # element carries its pin so the probe HEADs the manifest hosts actually pull. The web element stays bare:
  # the web image has no committed digest (#10044). Born hosts keep the BARE local above: a pin baked into an
  # env file at birth could never be updated (their user_data is ignore_changes) and would false-red once
  # five newer v.* tags evicted it. The pin is a registry-wide property, so checking it from web-1 suffices.
  zot_probe_repo_pinned = join(",", [local.zot_probe_repo_web, "${local.zot_probe_repo_inngest_bootstrap}@${local.zot_probe_digest_inngest_bootstrap}"])
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

# §4 — runtime Bash synthetic liveness heartbeat (per host; #10455 b, ADR-079 addendum 2026-10-22). Pinged ONLY on a
# verified pass of one real wrapped Bash call in the RUNNING web container, so a sandbox that breaks between deploys (the
# 2026-10-06..16 outage, #10445) stops the beat and pages. PERMANENT and INDEPENDENT of the nic-guard and zot beats (folding
# would re-introduce OR-masking across distinct failure domains; own URL per unit, never shared).
# period 900 s = the timer cadence; grace 1800 s: a skipped run (deploy lock, restart, memory skip) plus jitter must not page,
# and a verified FAIL already pages immediately through <url>/fail, so this beat only needs to be coarse about a DEAD detector.
# The apply-workflow arm gate (arm-heartbeats.sh) PATCHes paused=false only after a real beat lands.
resource "betteruptime_heartbeat" "web_bash_synthetic" {
  for_each = var.web_hosts

  name      = "soleur-web-bash-synthetic-${each.key}"
  period    = 900
  grace     = 1800
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

# Per-host heartbeat URLs → Doppler soleur/prd. Each probe/guard resolves its host's own URL by
# indirect expansion (${!<KEY>}) over the WEB_*_URL_KEY name baked into its env file: the nic-guard, zot and
# web-bash-synthetic SCRIPTS do it after their xtrace refusal (#9639 F6); the git-data and inngest units still do it in
# their wrapper (recorded not fixed on #9639), so these secrets are GENUINELY consumed (not a reserved-but-inert reservation — the anti-pattern
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

resource "doppler_secret" "web_bash_synthetic_url" {
  for_each = var.web_hosts

  project    = "soleur"
  config     = "prd"
  name       = "WEB_BASH_SYNTHETIC_URL_${upper(replace(each.key, "-", "_"))}"
  value      = betteruptime_heartbeat.web_bash_synthetic[each.key].url
  visibility = "masked"
}
