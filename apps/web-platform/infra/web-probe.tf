# --- #6438 / #6548: web-host private-net CONSUMER-perspective probe heartbeats -----------------
# The "#5274 PR C" vehicle. Three tracked gaps share one delivery substrate (an SSH terraform_data
# provisioner in server.tf, the sole path that reaches the cx33-unrebuildable web-1):
#   §1 (#6438) — a zot CONSUMER probe: web-1 verifies it can actually SERVE an image from the zot
#                registry over the private NIC, then pings web_zot_consumer; absence alarms.
#   §3 (#6438) — a private-NIC self-report (web_nic_guard) that emits SOLEUR_PRIVATE_NIC and pings
#                a dedicated liveness beat every healthy run (detect + emit + alarm, NO reboot).
#   #6548     — git-data reachability arms the EXISTING git_data_prd (git-data.tf).
#
# for_each = var.web_hosts: PER-HOST anti-masking preserved BY CONSTRUCTION for active-active-N
# (#6459) — each host gets its OWN heartbeat, so a healthy host can never mask a broken sibling.
#
# TWO HOSTS TODAY, BOTH PROBING (corrected 2026-08-04). This block used to read "single live beat
# today (web-1)" and "No hardcoded web-2 resource (it retired 2026-07-17, #6538)". Both clauses are
# stale, and stale in the direction that matters: variables.tf:112 records a DIFFERENT web-2
# RE-ADDED 2026-07-24 as a fresh cattle standby (#6459, ADR-143) — not the fsn1/10.0.1.11 warm
# standby #6538 retired — and it sits in var.web_hosts' default map (hel1, 10.0.1.11, cpx22). So
# `for_each` already materialises web-2 instances of both heartbeats and both doppler_secrets; the
# comment claimed an absence the code does not have.
#
# AND WEB-2 IS GENUINELY FED — do not infer otherwise from server.tf. An intermediate revision of
# this comment reasoned that because terraform_data.zot_consumer_probe_install and
# .private_nic_guard_install are hardcoded to web-1, web-2 had no feeder and its beats rested
# paused. That inference is WRONG and Better Stack refutes it: `web-zot-consumer-probe.service`
# emits from `soleur-web-2` as well as `soleur-web-platform`. The install path for a FRESH host is
# cloud-init.yml, whose runcmd carries `systemctl enable --now web-zot-consumer-probe.timer` (grep
# that literal rather than a line number — this file has churned); the web-1-only SSH
# provisioners are web-1-scoped NOT because ignore_changes=[user_data] is web-1-specific — it is
# not. hcloud_server.web is a for_each resource with ONE lifecycle block (ignore_changes =
# [user_data, ssh_keys, image, placement_group_id], server.tf), so it covers web-2 too, and a
# draft of this very correction implied web-2 self-heals, which is the opposite of the truth. The
# real reason is that web-2's public :22 is firewalled — web-host-provisioner-parity.test.sh spells
# it out: a fan-out would hang every merge on an SSH timeout. So they are web-1's RE-provisioning
# path, not the only install path. Read the telemetry before
# asserting which hosts run a unit — the resource that installs it on the pet is not the resource
# that installs it on the cattle.
#
# The surviving half of the retired clause is the load-bearing one, and it was never a claim about
# web-2's existence: a HARDCODED second heartbeat resource would need its own manifest entry in
# heartbeat-reprovision-parity.test.ts, and one shipped without a feeder is exactly the #6238
# false-absence class. for_each avoids that by construction — one block, one manifest entry, N
# instances — which is a reason to keep for_each, not evidence that web-2 is gone.
#
# free-tier heartbeats are unconditionally creatable (only betteruptime_policy/_monitor are
# count-gated); email-only escalation (betterstack_paid_tier stays false; paid-tier escalation is
# #6549 item 1).

locals {
  # The zot repository path the consumer probe HEADs (tag-INDEPENDENT `/v2/<repo>/tags/list`, so it
  # never goes stale across deploys). Derived from var.image_name: strip the ghcr.io host, then keep
  # the path before any `:tag` or `@sha256:` — e.g. ghcr.io/jikig-ai/soleur-web-platform:latest →
  # jikig-ai/soleur-web-platform. zot mirrors GHCR under the identical repository path.
  zot_probe_repo_web = regex("^[^:@]+", replace(var.image_name, "ghcr.io/", ""))

  # (#7144 task 5a) The probe covers BOTH platform repos, comma-joined. Until now it derived solely
  # from var.image_name, so it proved serviceability of soleur-web-platform ONLY — and nothing in the
  # stack verified that the HOST can pull soleur-inngest-bootstrap over the private NIC with the
  # ZOT_PULL_* credential. That gap matters because a green mirror_only run proves only that zot
  # serves the digest to the PUSH credential over the tunnel from a GitHub runner; zot accessControl
  # can grant push-read without pull-read, and since the GHCR read PAT was revoked 2026-07-30 zot is
  # the SOLE pull path. cloud-init.yml's web arm runs under `set -e` and traps to
  # `soleur-boot-emit inngest_bootstrap failed`, so a digest zot cannot serve the host is a FATAL
  # fresh boot on the only live web origin — not a graceful inngest_ghcr_fallback.
  #
  # Comma (not space) because it cannot appear in an OCI repository name, so the value needs no
  # quoting in the systemd EnvironmentFile that carries it. The probe splits on it and applies
  # ALL-MUST-SERVE aggregation; see web-zot-consumer-probe.sh.
  #
  # WHY ONE BEAT AND NOT TWO — settled 2026-08-04; the review reading is recorded because it is
  # the reading the next editor will also have. architecture-strategist flagged this fold as
  # contradicting the anti-masking rule stated at §3 below ("folding would re-introduce OR-masking
  # across two distinct failure domains"). It does not, and the distinction is the whole point of
  # the aggregation choice:
  #
  #   * OR-masking is A-healthy-hides-B-broken. It needs a beat that fires when EITHER repo
  #     serves. That is the direction that loses alarms, and it is the direction §3 names.
  #   * This fold is AND (web-zot-consumer-probe.sh suppresses the ping unless EVERY listed repo
  #     returns 200, and 401 exits 3 loudly). A broken bootstrap repo therefore SUPPRESSES the
  #     beat and absence alarms. AND can only over-suppress, never under-suppress — it strictly
  #     ADDS detection here, since before #7144 nothing verified the bootstrap repo at all.
  #
  # So the fold sits inside the anti-masking rule, not against it. What it genuinely costs is
  # DISCRIMINABILITY, and that is paid for elsewhere rather than with a second heartbeat: the
  # suppress branch names the offending repos in its journald line (Layer 3, Vector-shipped), which
  # is the same "a verdict must name its own subject" discipline #7144's probe-target-source fix
  # applied to inngest-inventory. A second beat would buy a marginally faster read of WHICH repo
  # failed, at the cost of a second betteruptime_heartbeat + doppler_secret per host and a second
  # URL in the probe's EnvironmentFile — which feeds terraform_data.zot_consumer_probe_install's
  # triggers_replace (grep that resource name in server.tf), i.e. it re-provisions web-1. Adding a second never-observed
  # gate to a host whose FIRST gate has not yet met its promotion criterion is the wrong trade.
  #
  # KNOWN RESIDUAL 1 — TEMPORAL. This fold CHANGED THE SUBJECT of an existing beat.
  # `soleur-web-zot-consumer-web-1` used to attest "the web platform image is servable"; it now
  # attests "web platform AND inngest-bootstrap are servable". A historical absence read across
  # 2026-08-04 is ambiguous between the two, and no aggregation rigour fixes that — only the
  # journald line does.
  #
  # KNOWN RESIDUAL 2 — PER-HOST, and the sharper of the two (found at review). This local reaches
  # web-1 through terraform_data.zot_consumer_probe_install's triggers_replace and its remote-exec
  # env write; it reaches web-2 through NOTHING until web-2 is rebuilt. So after this merges,
  # web-1's beat attests both repos and web-2's attests soleur-web-platform ONLY — indefinitely,
  # under a resource declaration and a monitor name that say otherwise.
  #
  # That is the same hazard §3 uses to justify keeping the NIC beat separate, pointed at §1: a
  # SILENTLY-ABSENT CONJUNCT DEGRADES AND INTO OR. web-zot-consumer-probe.sh splits on the comma
  # and has NO count assertion, so a dropped conjunct is indistinguishable from one that passed.
  # The durable fix is a repo-count floor in the probe, fed by the same envwriter that supplies
  # ZOT_PROBE_REPO — deliberately NOT taken here, because it would add a second unproven change to
  # a probe whose first one has never been observed passing (#7267 has zot dark from both hosts).
  # Do it when the promotion criterion can actually be observed.
  zot_probe_repo = join(",", [local.zot_probe_repo_web, var.inngest_bootstrap_repo])
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
# pings this every healthy run to be observable-when-healthy. NOT subsumed by the zot beat.
#
# The rule, stated precisely enough to apply (sharpened 2026-08-04 — it previously read "folding
# would re-introduce OR-masking across two distinct failure domains", which reads as a ban on ALL
# folding and was cited that way in review against §1's ALL-MUST-SERVE repo list):
#
#   Never fold two failure domains into one beat under OR — a beat that fires when EITHER domain
#   is healthy lets a healthy domain hide a broken one, which is the alarm-losing direction.
#   Folding under AND does not lose alarms (it can only over-suppress), so §1's multi-repo
#   ALL-MUST-SERVE list is within this rule, not an exception to it.
#
# What keeps THIS beat separate is therefore not the masking rule but a different property: the
# guard must be observable WHEN HEALTHY. AND-folding it into the zot beat would make a NIC-healthy
# run indistinguishable from a run where the guard never executed, because both look like "no
# suppression from the NIC side" — and the whole reason this heartbeat exists is that a
# never-firing emit and a dead guard are the same signal. Independence here buys liveness
# evidence; the §1 fold costs only discriminability, which its journald line repays.
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
