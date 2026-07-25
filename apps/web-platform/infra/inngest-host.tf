# #6178 (ADR-100) — the dedicated single-host Inngest singleton control plane.
#
# One dedicated Hetzner host running the self-hosted OSS Inngest server
# (`inngest start`, pinned v1.19.4) as a systemd unit with host-local Redis (AOF
# on a block volume) + a distinct non-prod Postgres backend, on the existing
# private network (network.tf) at 10.0.1.40. EXTRACTED from the co-located web
# host so exactly-one-instance is enforced by TOPOLOGY, not a runtime role-guard:
# OSS Inngest v1.x is single-writer and two servers on the same prod Postgres
# double-fire every cron (ADR-100 Context). This host is the prerequisite that
# unblocks active-active web (HA deferred to active-active-N, #6459; web-2 was retired
# 2026-07-17, #6538 — do NOT re-add a web-2 key).
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
  # Fresh private IP in 10.0.1.0/24 — web = .10 (.11 retired 2026-07-17, #6538), git-data = .20, registry = .30.
  inngest_private_ip = "10.0.1.40"

  # nftables allowlist for the inngest control API (:8288/:8289): ONLY the web-host
  # private interfaces. git-data (.20) + registry (.30) are DROPPED (AC-NFT) — a
  # peer-host compromise must not pivot into the (unauthenticated in `start` mode)
  # :8288/v0/gql trigger control plane without the signing key (SEC-H2). Comma-joined
  # for the nft `ip saddr { ... }` set rendered into inngest-nftables.sh.
  #
  # SINGLE-HOST (#6608): web-2 (the retired .11 host) was destroyed 2026-07-17 (#6538), so the
  # roster is web-1 only. This literal is DRIFT-GUARDED against var.web_hosts by
  # inngest-host.test.sh §6b (the allowlist IP set must byte-equal the var.web_hosts
  # private_ip set) — that guard is the edge to var.web_hosts the roster previously lacked,
  # so a stale .11 (or a future roster change) red-lines CI instead of silently re-granting.
  web_host_private_ips = "10.0.1.10"

  # Arch DERIVED from var.inngest_server_type (mirrors zot-registry.tf local.registry_arch):
  # `cax*` (Ampere) → arm64, anything else (`cpx*`/`cx*`) → amd64. Lets the dedicated Inngest
  # host provision on whichever of cax11 (arm64, €5.99) / cpx22 (amd64, €19.49) has Hetzner
  # stock — cax* arm64 was EU-wide out of stock at Phase-2 provision time (#6178). Every
  # arch-coupled download below (inngest CLI, Vector, Doppler CLI) is selected off this local.
  inngest_arch = startswith(var.inngest_server_type, "cax") ? "arm64" : "amd64"

  # Doppler CLI (v3.75.3, pinned in cloud-init-inngest.yml) per-arch download checksum — mirrors
  # zot-registry.tf local.doppler_sha256 (same version, same values).
  inngest_doppler_sha256 = local.inngest_arch == "arm64" ? "f1954f3717fe4c5b65e906a3c6dfe0d20e97b032af35e43db41250931302e143" : "9c840cdd32cffff06d048329549ba2fa908146b385f21cd1d54bf34a0082d0db"
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
  name = "soleur-inngest"
  # Doppler caps description at 255 chars — keep concise; full rationale is in the comments above.
  description = "Isolated boot-credential project for the dedicated Inngest singleton (#6178, ADR-100). Its prd root config holds ONLY the inngest secret set (signing/event keys, Redis password, out-of-band Postgres URI); cross-project isolation from soleur/prd."
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
# absent → the dark host must not push, which is what preserves the no-false-green invariant.
#
# #6536 — CORRECTION. This comment used to claim the absent URL made "the dark host's
# heartbeat curl no-op". That was FALSE, and the false claim is what authorized the bug:
# `curl -fsS --max-time 10 ""` exits 2 ("option : blank argument where content is expected"
# — measured; unset behaves identically), so the dark host's oneshot did not no-op, it FAILED
# every 60s for 3 days (3,724 fires) while this prose asserted the design was already safe.
# The monitor stayed green throughout only because the co-located host is the sole pusher —
# monitor greenness is NOT evidence about the dark host's unit. Same class as #4116: wrapping
# the ping in `doppler run` fixed WHERE the URL comes from, never made its ABSENCE safe.
#
# The skip is now implemented EXPLICITLY, not assumed from curl's behaviour: the ping script
# in inngest-bootstrap.sh carries an @@DARK_ARM@@ sentinel rendered ONLY on this host
# (DOPPLER_PROJECT=soleur-inngest), which logs `url_present=no` and exits 0. The co-located
# web host renders it EMPTY, so an absent URL there still reaches curl and exits 2 — loud, as
# it must be on the live pusher. Accepted minor gap: the dark host has no liveness push
# during dark (a dark, inert host bricking is surfaced at the Phase-2 pre-flight
# registry-empty check, not by continuous monitoring). The dark-arm row is BEST-EFFORT
# evidence, NOT a liveness guarantee: the ping script exits 0 whether or not `logger`
# succeeds, so journald being down / its volume full produces silence + exit 0 —
# byte-identical to a healthy dark host (#4792 makes that a known surface here). Absence of
# the row therefore proves nothing; presence proves the script ran. Stated precisely because
# an over-claimed comment is exactly what #6536 was. Same out-of-band doctrine as
# INNGEST_POSTGRES_URI below.
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

# Service token scoped to the isolated `soleur-inngest` project's `prd` ROOT config. Handed
# to the inngest host cloud-init in place of the full-prd var.doppler_token.
# `.key` is Computed/write-once (same handling as doppler_service_token.registry); rotate
# via `terraform apply -replace=doppler_service_token.inngest`.
#
# access = "read/write" (was "read" — #6178). The cutover flip FSM
# (inngest-cutover-flip.sh:flag_set) advances INNGEST_CUTOVER_FLIP on soleur-inngest/prd
# (armed→flipping→flushed→done, or →aborted/→rolled-back) via `doppler secrets set` under
# THIS token; the flip script comment (:78) already documented that the boot token
# "authorizes the write". Minting it read-only was the mismatch — the flip failed loud at its
# FIRST transition (flag_set flipping, before any Redis/systemctl action), so the dedicated
# scheduler could never complete the flip. Blast radius is UNCHANGED at the cross-project
# level: this token still resolves ONLY the isolated `soleur-inngest/prd` set — there is no
# path to `soleur/prd` or any other project, so a host compromise still cannot read/write
# foreign secrets. The residual (an inngest-server RCE could now WRITE this host's OWN
# isolated secrets, not just read them) is tracked in #6890 for a tighter split — a separate
# root-only write token used only by the root-run flip oneshot (via a cloud-init systemd
# drop-in whose EnvironmentFile wins), keeping inngest-server's deploy-readable token
# read-only. No OCI image change needed; deferred out of the live cutover as hardening.
#
# APPLY BEHAVIOR — this is NOT an in-place widen. Doppler service tokens are immutable, so
# `access` is ForceNew: changing it destroys+recreates the token → new `.key`. That `.key`
# feeds user_data (below), and hcloud_server.inngest carries NO ignore_changes=[user_data],
# so `terraform apply` REPLACES the live dedicated host (destroy+recreate, re-run cloud-init,
# re-bake the new read/write token). The Redis AOF volume survives (separate resource);
# the flip's /var/lock state slot does not (re-derived from the Doppler flag — DBSIZE==0
# still guards a spurious re-flush). Delivered via the #6178 apply_target=inngest-host-replace
# dispatch; confirm `terraform plan` shows `-/+ doppler_service_token.inngest` cascading to
# the host replacement before applying.
resource "doppler_service_token" "inngest" {
  project = doppler_project.inngest.name
  config  = doppler_environment.inngest_prd.slug
  name    = "inngest-boot"
  access  = "read/write"
}

# ---------------- The dedicated Inngest host ----------------
resource "hcloud_server" "inngest" {
  name        = "soleur-inngest"
  server_type = var.inngest_server_type # arch derived in locals (cax*→arm64 / cpx*→amd64); a singleton scheduler, not throughput-bound
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
    # Scoped Doppler token → 0600 root env file. read/write on the ISOLATED `soleur-inngest`
    # project's `prd` root config (the flip FSM writes INNGEST_CUTOVER_FLIP under it — see the
    # doppler_service_token.inngest note above, #6178). It is a SEPARATE project — NO
    # inheritance path to soleur/prd — so a host compromise still reaches ONLY this host's own
    # isolated secret set, never a foreign project. NEVER baked into user_data directly beyond
    # this scoped token (which is itself minimal-blast-radius by construction).
    doppler_token = doppler_service_token.inngest.key
    # Single stable --sdk-url to the ACTIVE web backend's private interface (10.0.1.10).
    # The degenerate no-flap case of the route-once mechanism (ADR-100 Decision 1); migrate
    # to a private VIP when active-active-N web lands (#6459; web-2 retired #6538). Consumed by inngest-bootstrap.sh.
    sdk_url = "http://10.0.1.10:3000/api/inngest"
    # Arch DERIVED from the server type (local.inngest_arch): cax* → arm64, else amd64. The
    # bootstrap consumes INNGEST_CLI_ARCH (inngest-bootstrap.sh:37/54) and verifies the download
    # against the matching checksum — the wrong-arch SHA fails verify. The cloud-init passes this
    # as INNGEST_CLI_SHA256, OVERRIDING the image-env value (which is only correct for amd64).
    inngest_cli_arch   = local.inngest_arch
    inngest_cli_sha256 = local.inngest_arch == "arm64" ? local.inngest_cli_sha256_arm64 : local.inngest_cli_sha256
    # #6197: Vector (journald→Better Stack) SHA, arch-matched — arm64 downloads the aarch64
    # tarball, amd64 the x86_64 tarball; the wrong-arch SHA fails verify. Consumed as VECTOR_CLI_SHA256.
    vector_sha256 = local.inngest_arch == "arm64" ? local.vector_sha256_arm64 : local.vector_sha256
    # Doppler CLI download arch + checksum, both derived from local.inngest_arch.
    doppler_arch   = local.inngest_arch
    doppler_sha256 = local.inngest_doppler_sha256
    # Bake the scoped GHCR read-creds (#6179/#6161) so the cold-boot soleur-inngest-bootstrap
    # OCI pull + cosign-verify authenticates even when Doppler answers empty at the boot
    # instant (else 401 → 226/NAMESPACE abort).
    ghcr_read_user  = var.ghcr_read_user
    ghcr_read_token = var.ghcr_read_token
    # nftables allowlist for the :8288/:8289 control API — web hosts only (SEC-H2).
    web_host_private_ips = local.web_host_private_ips
    # #6178 boot observability: bake the write-only Better Stack Logs ingest token so the
    # earliest runcmd can emit a phone-home marker BEFORE Doppler/OCI/bootstrap — otherwise a
    # failure in those early stages (or a Doppler-CLI-install failure) is a total blind spot on
    # this deny-all-public host. Same low-sensitivity append-only token vector.service already
    # uses; steady-state the marker token is re-fetched from Doppler (this baked copy is the
    # pre-Doppler fallback). Retrievable via the host metadata API — acceptable for an ingest-only
    # logs token on a deny-all host given the diagnosability it buys (weigh before widening use).
    betterstack_logs_token = var.betterstack_logs_token
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

# server_ids is update-in-place (NOT ForceNew), so the scoped `inngest-host-replace` dispatch
# (#6197) does NOT -target this attachment — after that replace it transiently points at the
# destroyed server id and the new host boots with NO hcloud firewall attached until the next
# full/drift apply reconciles server_ids (verify re-attach on replace, as with the Redis volume).
# Low blast radius: this firewall is a zero-rule deny-all; the real :8288/:8289 ingress control is
# host-local nftables (cloud-init, independent of the hcloud firewall) and /api/inngest is HMAC
# fail-closed. Do NOT add it to the replace allow-set — an in-place update is not a replace.
resource "hcloud_firewall_attachment" "inngest" {
  firewall_id = hcloud_firewall.inngest.id
  server_ids  = [hcloud_server.inngest.id]
}

# ---------------- Liveness (PUSH heartbeat) ----------------
# NO new betteruptime_heartbeat here: the plan REUSES the existing
# `betteruptime_heartbeat.inngest_prd` (inngest.tf) — the heartbeat PUSHER (inngest-heartbeat.
# timer, delivered by inngest-bootstrap.sh) simply MOVES from the co-located web host to this
# dedicated host. INNGEST_HEARTBEAT_URL is already published to Doppler by inngest.tf.
