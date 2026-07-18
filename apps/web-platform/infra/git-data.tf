# Epic #5274 Phase 2 PR B / ADR-068 — the git-data host (multi-host /workspaces).
#
# A dedicated Hetzner host that stores the per-workspace BARE git repos (objects +
# refs) and enforces the writer-side CAS fence (ADR-068 §3). The web host keeps
# worktrees on local NVMe and pushes to this host over the private net
# (network.tf). At replicas=1 the fence is live-but-non-rejecting; it becomes
# load-bearing at Phase 3's second writer.
#
# Apply-path note: cloud-init-only (NO remote-exec provisioner). The CI runner
# cannot SSH either host, so any provisioner here would hang the merge-triggered
# auto-apply. `terraform apply` returns green on server CREATE without waiting for
# cloud-init; the post-merge readiness/cutover script (web-host-driven, over the
# private net) verifies git + bare-repo root + hook are live BEFORE cutover
# (hr-fresh-host-provisioning-reachable-from-terraform-apply).
#
# REPROVISION-PATH (ADR-103, #6242): git-data resources are OPERATOR_APPLIED_EXCLUSIONS
# (never touched per-PR), and the per-PR path bridges over SSH to the EXISTING web host so
# it cannot reprovision this host at all. A sanctioned dispatch-only `git-data-host-replace`
# `workflow_dispatch` path now exists (apply-web-platform-infra.yml, mirroring
# registry-host-replace / ADR-100 inngest-host-replace) to re-run this host's cloud-init
# WITHOUT SSH — a scoped, destroy-guarded `terraform apply -replace='hcloud_server.git_data'`
# that PRESERVES BOTH data volumes (hcloud_volume.git_data + hcloud_volume.git_data_luks) and
# the LUKS passphrase by OMISSION. It is a maintenance-window dispatch, not a per-PR apply;
# these resources remain excluded from the per-PR `-target=` list. Before it, git-data had
# ZERO non-SSH reprovision path (hr-prod-host-config-change-immutable-redeploy gap). The
# invariant that a boot-armed heartbeat needs such a path is mechanically enforced by
# plugins/soleur/test/heartbeat-reprovision-parity.test.ts.

# --- In-band transport keypair (ED25519) ------------------------------------
# DEDICATED key — NOT reused from tls_private_key.ci_ssh. Mirrors the ci-ssh-key.tf
# shape (tls_private_key.ci_ssh + the trimspace() local + doppler_secret). The
# public half goes onto the git-data host (cloud-init authorized_keys, git-shell
# forced-command); the private half goes to Doppler for git-auth.ts to consume.
#
# Intentionally a single throwaway shared key (the Phase-2 floor: one web host,
# git-shell-scoped). Phase 3's per-workspace_id mTLS (ADR-068 §6) REPLACES it; it
# is NOT a cluster-wide mount credential, so the Phase-3 swap is additive-then-
# remove (the Phase-3 plan must plan its removal).
resource "tls_private_key" "git_transport" {
  algorithm = "ED25519"
}

# --- In-band PROVISION keypair (ED25519) ------------------------------------
# A SECOND, dedicated key — SEPARATE from tls_private_key.git_transport (ADR-068
# amendment 2026-07-01 "PR B bare-repo provisioning"). Its cloud-init forced
# command is the FIXED `git-data-provision.sh` (idempotent `git init --bare`),
# NEVER git-shell. Provisioning authority and ref-write authority are separate
# credentials with separate blast radii (ADR-068 §6): a leaked transport key
# cannot fabricate repos, and a leaked provision key cannot write refs. Same OS
# `git` user (per-key command= overrides the login shell). Same throwaway-shape as
# git_transport; Phase 3's per-workspace_id mTLS replaces both.
resource "tls_private_key" "git_provision" {
  algorithm = "ED25519"
}

# --- In-band REMOVE keypair (ED25519) ---------------------------------------
# A THIRD, dedicated key — SEPARATE from git_transport AND git_provision (#5274
# Phase 3, ADR-068 GDPR Art. 17 / CLO DL-1). Its cloud-init forced command is the
# FIXED `git-data-remove.sh` (idempotent `rm -rf <id>.git`), NEVER git-shell.
# Provisioning, ref-write, and ERASURE authority are three separate credentials
# with separate blast radii (ADR-068 §6): a leaked transport/provision key cannot
# delete repos, and a leaked remove key cannot write refs. Same OS `git` user
# (per-key command= overrides the login shell). Same throwaway-shape as the
# siblings; Phase 3's per-workspace_id posture replaces all three.
resource "tls_private_key" "git_remove" {
  algorithm = "ED25519"
}

locals {
  # trimspace() strips the trailing newline tls_private_key.public_key_openssh
  # carries — without it the cloud-init authorized_keys line renders with a
  # trailing blank, breaking the forced-command entry. Same rationale as
  # local.ci_ssh_pubkey (ci-ssh-key.tf).
  git_transport_pubkey = trimspace(tls_private_key.git_transport.public_key_openssh)
  git_provision_pubkey = trimspace(tls_private_key.git_provision.public_key_openssh)
  git_remove_pubkey    = trimspace(tls_private_key.git_remove.public_key_openssh)
}

# Private half → Doppler. Consumed at RUNTIME by the web host's git-auth.ts, which
# is configured from Doppler `prd` (prd values are baked into the container env at
# start) — NOT `prd_terraform` (that config feeds the CI/terraform deploy pipeline,
# which is where doppler_secret.deploy_ssh_private_key correctly lives because it is
# a DEPLOY-time key). This is a RUNTIME key, so it belongs in `prd`. The TF doppler
# token demonstrably writes `prd` (see doppler_secret.git_data_heartbeat_url_prd
# below). NOT cloud-init — the web host carries ignore_changes=[user_data], so
# cloud-init can never reach the running container.
resource "doppler_secret" "git_transport_ssh_private_key" {
  project    = "soleur"
  config     = "prd"
  name       = "GIT_TRANSPORT_SSH_PRIVATE_KEY"
  value      = tls_private_key.git_transport.private_key_openssh
  visibility = "masked"
}

# Provision key private half → Doppler `prd` (RUNTIME key; same rationale as
# git_transport above). Consumed by git-data-replication.ts (sshWithPrivateKeyAuth)
# to reach the `git-data-provision.sh` forced command before the first push.
resource "doppler_secret" "git_provision_ssh_private_key" {
  project    = "soleur"
  config     = "prd"
  name       = "GIT_PROVISION_SSH_PRIVATE_KEY"
  value      = tls_private_key.git_provision.private_key_openssh
  visibility = "masked"
}

# Remove key private half → Doppler `prd` (RUNTIME key; same rationale as the
# siblings). Consumed by account-delete.ts / workspace-delete (3.D) to reach the
# `git-data-remove.sh` forced command over the private net for Art. 17 erasure.
resource "doppler_secret" "git_remove_ssh_private_key" {
  project    = "soleur"
  config     = "prd"
  name       = "GIT_REMOVE_SSH_PRIVATE_KEY"
  value      = tls_private_key.git_remove.private_key_openssh
  visibility = "masked"
}

# --- The git-data host -------------------------------------------------------
resource "hcloud_server" "git_data" {
  name        = "soleur-git-data"
  server_type = var.git_data_server_type # cax11 = ARM64 (Ampere); git/sshd are ARM-native
  location    = var.location
  image       = "ubuntu-24.04"
  keep_disk   = true
  ssh_keys    = [hcloud_ssh_key.default.id]

  # P0 — public IPv4/IPv6 for EGRESS only (apt + GitHub during cloud-init). A
  # no-public-IP host has NO internet (no NAT gateway exists in this account), so
  # `apt-get install git` in the bootstrap would fail. INGRESS on the public
  # interface is denied by hcloud_firewall.git_data below; transport is private-
  # net only.
  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  # gzip-first (#5927). Post-#5918 the rendered cloud-config is ~41.7 KB — OVER
  # Hetzner's 32,768-byte user_data cap. git-data runs NO docker and pulls NO image,
  # so #5921's web-host bake-and-extract mechanism (ADR-080) does NOT transfer here.
  # Instead wrap the WHOLE render in base64gzip(): the highly-compressible shell
  # payload gzips to ~16.4 KB, and the base64 of that (~21.9 KB) is what Hetzner
  # stores against the cap — under it with ~10 KB headroom.
  #
  # Decode contract: Hetzner does NOT accept binary user-data, so it base64-decodes
  # the stored string before cloud-init sees it (cloud-init's
  # DataSourceHetzner.maybe_b64decode, added ≥20.3; Ubuntu 24.04 ships far newer) →
  # raw gzip bytes (magic 1f 8b) → cloud-init auto-gunzips → byte-identical
  # #cloud-config. base64 is therefore MANDATORY on Hetzner, which makes base64gzip()
  # the intended path, not a datasource gamble. The template + all 5 injected scripts
  # stay byte-identical; only this expression changed. Byte-exact size is confirmed at
  # #5887's first `terraform plan`; fail-closed at first provisioning if decode fails
  # (web-host readiness check finds no git/bare-repo, blocks cutover). See ADR-080.
  user_data = base64gzip(templatefile("${path.module}/cloud-init-git-data.yml", {
    git_data_bootstrap_b64               = base64encode(file("${path.module}/git-data-bootstrap.sh"))
    git_data_pre_receive_placeholder_b64 = base64encode(file("${path.module}/git-data-pre-receive-placeholder.sh"))
    # The FIXED provision forced-command wrapper (git init --bare), delivered to
    # /usr/local/bin like the bootstrap (ADR provisioning amendment).
    git_data_provision_b64 = base64encode(file("${path.module}/git-data-provision.sh"))
    # The TRANSPORT allowlist forced-command wrapper (Sub-PR 3.D) — replaces the raw
    # git-shell forced command; delivered to /usr/local/bin like the others.
    git_data_transport_wrapper_b64 = base64encode(file("${path.module}/git-data-transport-wrapper.sh"))
    # The FIXED erasure forced-command wrapper (rm -rf <id>.git), Art. 17 (3.A;
    # app-side call lands in 3.D). Delivered to /usr/local/bin like the others.
    git_data_remove_b64 = base64encode(file("${path.module}/git-data-remove.sh"))
    # trimspace()'d — see local.git_transport_pubkey / local.git_provision_pubkey.
    git_transport_pubkey = local.git_transport_pubkey
    git_provision_pubkey = local.git_provision_pubkey
    git_remove_pubkey    = local.git_remove_pubkey
    # Mount the bare-repo volume by its specific id (server.tf/cloud-init.yml
    # by-id pattern). Known at plan time; the attachment is a separate resource.
    git_data_volume_id = hcloud_volume.git_data.id
    # The FRESH LUKS-at-rest cutover volume (Sub-PR 3.D, git-data-luks.tf). Guest-side
    # cryptsetup luksOpens + mounts it at /mnt/git-data-luks. by-id like the plaintext one.
    git_data_luks_volume_id = hcloud_volume.git_data_luks.id
    # Doppler service token → 0600 root env file so the boot-time `doppler run` can
    # read GIT_DATA_LUKS_KEY. SCOPED read-only token for the `prd_git_data` config
    # (only GIT_DATA_LUKS_KEY) — NOT the full-prd var.doppler_token (3.D security review
    # MEDIUM / CTO ruling: a git-data-host compromise must not yield service-role /
    # GIT_REMOVE / PROXY_TLS material). The passphrase itself is NEVER in this user_data.
    doppler_token = doppler_service_token.git_data.key
  }))

  # Deliberately NO lifecycle.ignore_changes=[user_data]. The web host carries it
  # only as an IMPORT ARTIFACT (server.tf:66-72); a FRESH host has no spurious
  # diff, and omitting it preserves a clean replace-to-reprovision path during the
  # fence-iteration window (P1).

  labels = {
    app = "soleur-web-platform"
  }
}

# --- Bare-repo block volume --------------------------------------------------
# The bare repos AND the per-(workspace,worktree) fence sidecar/lock live here —
# never tmpfs (a reboot resetting the fence max to 0 would let a stale writer
# win). Shape mirrors hcloud_volume.workspaces (server.tf:926-940).
resource "hcloud_volume" "git_data" {
  name     = "soleur-git-data-store"
  size     = var.git_data_volume_size
  location = var.location
  format   = "ext4"

  labels = {
    app = "soleur-web-platform"
  }
}

resource "hcloud_volume_attachment" "git_data" {
  volume_id = hcloud_volume.git_data.id
  server_id = hcloud_server.git_data.id
}

# --- Deny-all PUBLIC ingress firewall ----------------------------------------
# ZERO inbound rules = deny-all on the PUBLIC interface (P1). Hetzner firewalls
# filter only the public interface; intra-hcloud_network traffic (the web host's
# git transport + liveness probe on 10.0.1.0/24) is open by network membership
# and needs NO allow rule. NO inbound SSH/git rule on the public interface —
# private-net transport only. Egress (apt/GitHub) is unaffected by inbound rules.
resource "hcloud_firewall" "git_data" {
  name = "soleur-git-data"

  labels = {
    app = "soleur-web-platform"
  }
}

# Separate attachment resource (mirrors hcloud_firewall_attachment.web,
# firewall.tf:91-94) rather than an inline apply_to block.
resource "hcloud_firewall_attachment" "git_data" {
  firewall_id = hcloud_firewall.git_data.id
  server_ids  = [hcloud_server.git_data.id]
}

# --- Liveness (PUSH heartbeat) -----------------------------------------------
# Better Stack cannot PULL a deny-all-public-ingress host, so liveness is a PUSH
# heartbeat: a web-host cron probes git-data over the private net (git ls-remote /
# ssh) and pings this heartbeat URL on success; absence-of-ping alerts. Shape
# mirrors betteruptime_heartbeat.inngest_prd (inngest.tf:268-298).
#
# paused = true initially (same rationale as inngest_prd): until the web-host
# probe cron is wired + deployed, the gap between apply (Better Stack starts
# expecting a ping within `grace`) and the first ping would fire a false alert.
# Unpause via the Better Stack UI (or flip in a follow-up) once the probe ships.
resource "betteruptime_heartbeat" "git_data_prd" {
  name   = "soleur-git-data-prd"
  period = 60
  # grace relaxed 30 → 180 (#6548 / #5274 PR C): git-data is fail-soft ("an OVERLAY, not a hard
  # dependency", ensure-workspace-repo.ts:332), so a single transient reachability blip must NOT
  # page. The web-host probe (web-git-data-probe.sh) pings on every reachable run; 180s of grace
  # means paging fires only on a SUSTAINED (multi-window) break, not a one-off.
  grace     = 180
  call      = false
  sms       = false
  email     = true
  push      = false
  team_wait = 0
  # Literal name of the only team in this Better Stack workplace (case-sensitive
  # provider lookup) — see inngest.tf:277-281.
  team_name  = "Your team"
  policy_id  = var.betterstack_paid_tier ? betteruptime_policy.inngest[0].id : null
  paused     = true
  sort_index = 0

  lifecycle {
    # Operator unpause via UI MUST NOT be reverted by subsequent applies (mirrors
    # betteruptime_heartbeat.inngest_prd).
    ignore_changes = [paused]
  }
}

# Heartbeat URL → Doppler prd, so the (follow-up) web-host probe cron can read it
# via the server's existing `doppler secrets download` flow. Mirrors
# doppler_secret.inngest_heartbeat_url_prd (inngest.tf:323-329).
#
# TODO(#5274 PR C / follow-up): the web-host probe cron itself (git ls-remote over
# the private net to 10.0.1.20, then curl GIT_DATA_HEARTBEAT_URL on success) needs
# ci-deploy wiring (a systemd timer like inngest-heartbeat.timer). This resource +
# the URL secret are the IaC deliverable here; the probe script is the follow-up.
#
# This TODO is honest — unlike its registry counterpart, which claimed the probe had shipped and
# left the monitor inert for 9 days (#6537). It is now ENFORCED rather than merely accurate:
# heartbeat-manifest.ts declares this row `feeder: {kind:"none", url_secret:"GIT_DATA_HEARTBEAT_URL"}`
# and the parity guard asserts that secret still has zero dereferencing consumers — so the day PR C
# ships the probe, CI goes red and forces the row (and the arming decision) to be reconciled.
# See ADR-117. Live-absence of this heartbeat is tracked separately in #6548.
resource "doppler_secret" "git_data_heartbeat_url_prd" {
  project    = "soleur"
  config     = "prd"
  name       = "GIT_DATA_HEARTBEAT_URL"
  value      = betteruptime_heartbeat.git_data_prd.url
  visibility = "masked"
}
