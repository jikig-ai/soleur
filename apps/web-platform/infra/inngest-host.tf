# #6178 (ADR-100) — the dedicated single-host Inngest singleton control plane.
#
# One dedicated Hetzner host running the self-hosted OSS Inngest server
# (`inngest start`, pinned v1.19.4) as a systemd unit with host-local Redis (AOF
# on a block volume) + a distinct non-prod Postgres backend, on the existing
# private network (network.tf) at 10.0.1.40. EXTRACTED from the co-located web
# host so exactly-one-instance is enforced by TOPOLOGY, not a runtime role-guard:
# OSS Inngest v1.x is single-writer and two servers on the same prod Postgres
# double-fire every cron (ADR-100 Context). This host is the prerequisite that
# unblocks active-active web (web-2 pooled, #6178 / #6185).
#
# STRUCTURAL PRECEDENT: zot-registry.tf (ADR-096) / git-data.tf (ADR-068), NOT the
# co-located inngest.tf. inngest.tf provisions keys/secrets for the ON-web-host
# unit; it has no host resources. This file mirrors zot-registry.tf's host/volume/
# network/firewall/separate-Doppler-project/GHCR-baking/boot-self-check shape 1:1.
#
# APPLY-PATH (registry precedent): every resource here is applied by a dedicated
# `apply_target=inngest-host` dispatch (maintenance-window) + the operator's initial
# full untargeted apply + the drift detector — NONE are in the per-PR CI `-target=`
# list. Net-new `.tf` is INERT on merge (nothing references these resources on the
# per-merge path). Two load-bearing conditions carried from registry: (1) cloud-
# init-only, NO `remote-exec` (the SSH-parity guard has no exclusion path otherwise);
# (2) no inngest cred is a github_actions_secret.
#
# DARK-ON-PROVISION (AC-DARK): the host is born on a DISTINCT NON-PROD Postgres
# backend (INNGEST_POSTGRES_URI, set OUT-OF-BAND into this project's prd config — see
# the doppler_secret block below) with an empty function registry, so it fires ZERO
# prod crons at boot. Dark→live is a Phase-2 operator Postgres flip gated behind a
# Redis FLUSHALL + DBSIZE==0 assertion (ADR-100 Decision 6). No window at provision.

locals {
  # Fresh private IP in 10.0.1.0/24 — web = .10/.11, git-data = .20, registry = .30.
  inngest_private_ip = "10.0.1.40"

  # nftables allowlist for the inngest control API (:8288/:8289): ONLY the web-host
  # private interfaces. git-data (.20) + registry (.30) are DROPPED (AC-NFT) — a
  # peer-host compromise must not pivot into the (unauthenticated in `start` mode)
  # :8288/v0/gql trigger control plane without the signing key (SEC-H2). Comma-joined
  # for the nft `ip saddr { ... }` set rendered into inngest-nftables.sh.
  web_host_private_ips = "10.0.1.10,10.0.1.11"
}

# ---------------- Fresh signing/event/redis keys (AC-KEYROTATE, SEC-H3) ----------------
# The dedicated host is a NEW signature boundary → mint FRESH keys, do NOT reuse the
# co-located `random_id.inngest_signing_key_prd` (inngest.tf). Same shapes as the
# co-located resources (byte_length=32 → 64 hex; the SDK accepts `signkey-prod-<hex>`)
# but distinct resources so the blast radius of the old boundary is not carried over.
resource "random_id" "inngest_signing_key_dedicated" {
  byte_length = 32
}

resource "random_id" "inngest_event_key_dedicated" {
  byte_length = 32
}

# Host-local Redis password (AOF queue/run-state auth). random_password (hashicorp/
# random) NOT an operator-mint var (hr-tf-variable-no-operator-mint-default). special
# = false keeps it URL-safe in the redis://:<pw>@127.0.0.1:6379 URI the inngest units
# build. Mirrors random_password.inngest_redis_password_prd (inngest.tf).
resource "random_password" "inngest_redis_password_dedicated" {
  length  = 48
  special = false
}

# ---------------- The ISOLATED `soleur-inngest` Doppler PROJECT (AC3) ----------------
# TRUE isolation requires a SEPARATE PROJECT, not a `prd` branch config: every config in
# an environment resolves that environment's ROOT config as its base, so a token "scoped"
# to a `prd` branch config reads the FULL soleur/prd secret set (~116 incl.
# SUPABASE_SERVICE_ROLE_KEY). Empirically verified (#6122,
# 2026-07-07-doppler-branch-config-does-not-isolate-secrets.md). So the host boot
# credential lives in a DEDICATED project `soleur-inngest` whose OWN `prd` ROOT config
# holds ONLY the inngest secret set; a read token scoped to it resolves exactly those and
# nothing else. Mirrors doppler_project.registry (zot-registry.tf), NOT the co-located
# inngest.tf secrets (which live in shared soleur/prd).
#
# PROVISIONING: TF-created in the operator's full apply (var.doppler_token_tf is a
# workplace-scope personal token). FALLBACK if project-create is denied at apply: create
# the project once via the dashboard (New PROJECT `soleur-inngest` — NOT a config under
# `prd`), TF then managing only the secrets + token inside it.
resource "doppler_project" "inngest" {
  name        = "soleur-inngest"
  description = "Isolated boot-credential project for the dedicated single-host Inngest singleton (#6178, ADR-100) — its `prd` root config holds ONLY the inngest secret set (signing/event keys, Redis password, and the out-of-band Postgres URI); cross-project isolation from soleur/prd (no shared root-secret resolution path, unlike a `prd` branch config; #6122 precedent)."
}

# A TF-created doppler_project is created BARE — no default dev/stg/prd configs that the
# Doppler CLI/dashboard would auto-add — so without this the secrets below fail at apply with
# "Doppler Error: Could not find requested config 'prd'". Creating the environment also creates
# its same-named ROOT config, which is the isolation boundary the host boot token resolves.
# Mirrors doppler_environment.registry_prd (zot-registry.tf, #6189/f0241a2bc — added AFTER this
# branch's merge-base, so the initial 1:1 mirror dropped it). Basic Project-Structure resource,
# NOT a branch config (needs no paid config-inheritance feature).
resource "doppler_environment" "inngest_prd" {
  project = doppler_project.inngest.name
  slug    = "prd"
  name    = "Production"
}

# TF owns these three values → NO ignore_changes (mirrors zot_*_token_registry, NOT the
# co-located inngest.tf ignore_changes shape). Rotation re-propagates in ONE apply via
# `terraform apply -replace=random_id.inngest_signing_key_dedicated` (etc.).
resource "doppler_secret" "inngest_signing_key_dedicated" {
  project    = doppler_project.inngest.name
  config     = doppler_environment.inngest_prd.slug
  name       = "INNGEST_SIGNING_KEY"
  value      = "signkey-prod-${random_id.inngest_signing_key_dedicated.hex}"
  visibility = "masked"
}

resource "doppler_secret" "inngest_event_key_dedicated" {
  project    = doppler_project.inngest.name
  config     = doppler_environment.inngest_prd.slug
  name       = "INNGEST_EVENT_KEY"
  value      = random_id.inngest_event_key_dedicated.hex
  visibility = "masked"
}

resource "doppler_secret" "inngest_redis_password_dedicated" {
  project    = doppler_project.inngest.name
  config     = doppler_environment.inngest_prd.slug
  name       = "INNGEST_REDIS_PASSWORD"
  value      = random_password.inngest_redis_password_dedicated.result
  visibility = "masked"
}

# INNGEST_HEARTBEAT_URL is provisioned OUT-OF-BAND at CUTOVER, NOT a TF resource — a
# deliberate correctness choice (review #6180, data-integrity + user-impact concurred).
# The plan REUSES betteruptime_heartbeat.inngest_prd (don't mint a new monitor); but TF-
# provisioning its URL into soleur-inngest at DARK provision would make the dedicated host's
# heartbeat timer push the SAME prod monitor the still-serving co-located scheduler pushes
# — so during the (multi-day) provision→cutover window a co-located outage would be MASKED
# GREEN by the dark host's ping. So the operator sets INNGEST_HEARTBEAT_URL (=
# betteruptime_heartbeat.inngest_prd.url) into the soleur-inngest prd config only AT cutover
# (Phase 2.x), when the dedicated host BECOMES the sole scheduler and the co-located pusher
# is quiesced — one unambiguous pusher per monitor at all times. Set via `doppler secrets
# set INNGEST_HEARTBEAT_URL` on the soleur-inngest prd config (stdin). During dark the URL is
# absent → the dark host's heartbeat curl no-ops (no false-green). Accepted minor gap: the
# dark host has no liveness push during dark (a dark, inert host bricking is surfaced at the
# Phase-2 pre-flight registry-empty check, not by continuous monitoring). Same out-of-band
# doctrine as INNGEST_POSTGRES_URI below.
# ---------------------------------------------------------------------------------------
# INNGEST_POSTGRES_URI — provisioned OUT-OF-BAND into THIS project's `prd` config, NOT a
# TF resource (mirrors the co-located inngest.tf:170-194 out-of-band doctrine + the
# BETTERSTACK_LOGS_TOKEN pattern). The URI embeds a project-side DB secret TF NEVER minted;
# a `doppler_secret` here would clobber the real value on first create (ignore_changes only
# engages AFTER the resource is in state). It is the session-pooler (:5432, NEVER :6543 —
# breaks inngest's sqlc prepared statements) connection string.
#
# AC-DARK: at provision this points at a DISTINCT NON-PROD Postgres backend (a fresh empty
# database firing ZERO prod crons). It is flipped to the prod inngest Postgres ONLY at the
# Phase-2 cutover (operator, maintenance window), immediately after a Redis FLUSHALL +
# DBSIZE==0 assertion (ADR-100 Decision 6). Provision it BEFORE the host boots (else
# cold-boot bricks — plan 1.4/M4): set it via `doppler secrets set` on the soleur-inngest
# prd config (stdin, never argv). Rotation: rotate the DB password in the Supabase dashboard
# → re-set INNGEST_POSTGRES_URI in the soleur-inngest prd config.
# ---------------------------------------------------------------------------------------

# Read-only service token scoped to the isolated `soleur-inngest` project's `prd` ROOT
# config. Handed to the inngest host cloud-init in place of the full-prd var.doppler_token.
# `.key` is Computed/write-once (same handling as doppler_service_token.registry); rotate
# via `terraform apply -replace=doppler_service_token.inngest`.
resource "doppler_service_token" "inngest" {
  project = doppler_project.inngest.name
  config  = doppler_environment.inngest_prd.slug
  name    = "inngest-boot"
  access  = "read"
}

# ---------------- The dedicated Inngest host ----------------
resource "hcloud_server" "inngest" {
  name        = "soleur-inngest"
  server_type = var.inngest_server_type # cax11 = ARM64 (Ampere); a singleton scheduler, not throughput-bound
  location    = var.location
  image       = "ubuntu-24.04"
  keep_disk   = true
  ssh_keys    = [hcloud_ssh_key.default.id]

  # Public IPv4/IPv6 for EGRESS only (apt + the inngest CLI + bootstrap image pulls during
  # cloud-init). A no-public-IP host has NO internet (no NAT gateway). INGRESS on the public
  # interface is denied by hcloud_firewall.inngest below; /api/inngest + the control API are
  # private-net only. Same public_net rationale as git-data.tf / zot-registry.tf.
  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  # base64gzip-first (git-data.tf / ADR-080 #5927): wrap the whole render so the shell
  # payload compresses under Hetzner's 32,768-byte user_data cap. Hetzner base64-decodes →
  # gzip magic → cloud-init auto-gunzips → byte-identical #cloud-config (DataSourceHetzner).
  user_data = base64gzip(templatefile("${path.module}/cloud-init-inngest.yml", {
    # Mount the Redis AOF volume by its specific id (by-id pattern). Known at plan time;
    # the attachment is a separate resource.
    inngest_volume_id = hcloud_volume.inngest_redis.id
    # Scoped read-only Doppler token → 0600 root env file. The token is scoped to the
    # ISOLATED `soleur-inngest` project's `prd` root config (a SEPARATE project — NO
    # inheritance path to soleur/prd), so a host compromise reads ONLY the inngest secret
    # set. NEVER baked into user_data directly beyond this scoped token (which is itself
    # minimal-blast-radius by construction).
    doppler_token = doppler_service_token.inngest.key
    # Single stable --sdk-url to the ACTIVE web backend's private interface (10.0.1.10).
    # The degenerate no-flap case of the route-once mechanism (ADR-100 Decision 1); migrate
    # to a private VIP when web-2 is pooled (Phase 4.2). Consumed by inngest-bootstrap.sh.
    sdk_url = "http://10.0.1.10:3000/api/inngest"
    # cax11 is ARM64 → the inngest CLI download must be the arm64 build (bootstrap consumes
    # INNGEST_CLI_ARCH; inngest-bootstrap.sh:37/54) AND verify against the arm64 checksum —
    # the amd64 SHA baked in the OCI image env would fail the download verify. The cloud-init
    # passes this as INNGEST_CLI_SHA256, OVERRIDING the image-env (amd64) value.
    inngest_cli_arch         = "arm64"
    inngest_cli_sha256_arm64 = local.inngest_cli_sha256_arm64
    # #6197: arm64 Vector SHA override (cax11 downloads the aarch64 tarball; the amd64
    # image-env SHA would fail verify). Consumed by cloud-init as VECTOR_CLI_SHA256.
    vector_sha256_arm64 = local.vector_sha256_arm64
    # Bake the scoped GHCR read-creds (#6179/#6161) so the cold-boot soleur-inngest-bootstrap
    # OCI pull + cosign-verify authenticates even when Doppler answers empty at the boot
    # instant (else 401 → 226/NAMESPACE abort).
    ghcr_read_user  = var.ghcr_read_user
    ghcr_read_token = var.ghcr_read_token
    # nftables allowlist for the :8288/:8289 control API — web hosts only (SEC-H2).
    web_host_private_ips = local.web_host_private_ips
  }))

  # Deliberately NO lifecycle.ignore_changes=[user_data]. A FRESH host has no spurious diff,
  # and omitting it preserves a clean replace-to-reprovision path (git-data.tf / zot-registry.tf
  # rationale). CONSEQUENCE (ADR-100): this host is the SOLE scheduler, so every cloud-init edit
  # force-replaces it → a cron-outage window — gate all cloud-init edits to the maintenance-
  # window `apply_target=inngest-host` dispatch. The AOF volume is a SEPARATE resource that
  # survives the replace (verify re-attach on replace — git-data precedent).

  labels = {
    app = "soleur-web-platform"
  }
}

# ---------------- Redis AOF block volume ----------------
# The queue/run-state AOF lives here — never tmpfs (a wiped AOF loses in-flight
# step.sleep/queued jobs across a reboot; the exact data-loss trap the durable backend
# fixes). Mounted at /mnt/data (inngest-redis.conf `dir /mnt/data/redis`). Shape mirrors
# hcloud_volume.registry.
resource "hcloud_volume" "inngest_redis" {
  name     = "soleur-inngest-redis-store"
  size     = var.inngest_redis_volume_size
  location = var.location
  format   = "ext4"

  labels = {
    app = "soleur-web-platform"
  }
}

resource "hcloud_volume_attachment" "inngest_redis" {
  volume_id = hcloud_volume.inngest_redis.id
  server_id = hcloud_server.inngest.id
}

# ---------------- Deny-all PUBLIC ingress firewall ----------------
# ZERO inbound rules = deny-all on the PUBLIC interface. Hetzner firewalls filter ONLY the
# public interface; intra-hcloud_network traffic (web hosts on 10.0.1.0/24) is open by network
# membership and needs NO allow rule — so a cloud-firewall rule to "scope" :8288 to web hosts
# would be a NO-OP (SEC-H1, AC-FW). The sole effective /api/inngest boundary is fail-closed HMAC
# signature-verify; the (unauthenticated in `start` mode) :8288/:8289 control API is scoped by
# HOST-LOCAL nftables (inngest-nftables.sh, cloud-init) allowing only the web-host private IPs
# and dropping .20/.30 (SEC-H2). Egress (apt + image pulls) is unaffected by inbound rules.
# Mirrors hcloud_firewall.registry exactly.
resource "hcloud_firewall" "inngest" {
  name = "soleur-inngest"

  labels = {
    app = "soleur-web-platform"
  }
}

resource "hcloud_firewall_attachment" "inngest" {
  firewall_id = hcloud_firewall.inngest.id
  server_ids  = [hcloud_server.inngest.id]
}

# ---------------- Liveness (PUSH heartbeat) ----------------
# NO new betteruptime_heartbeat here: the plan REUSES the existing
# `betteruptime_heartbeat.inngest_prd` (inngest.tf) — the heartbeat PUSHER (inngest-heartbeat.
# timer, delivered by inngest-bootstrap.sh) simply MOVES from the co-located web host to this
# dedicated host. INNGEST_HEARTBEAT_URL is already published to Doppler by inngest.tf.
