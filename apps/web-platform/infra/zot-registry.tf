# #6122 (ADR-096) — the self-hosted zot container-registry host.
#
# A dedicated Hetzner host running a single zot OCI registry as a docker container
# (digest-pinned upstream image), volume-backed at /var/lib/zot, on the existing
# private network (network.tf). Hetzner web hosts + CI `docker pull` our two private
# platform images from it with a Terraform-generated read-only htpasswd credential
# (zero human mint). Supersedes GHCR for our own images (ADR-096; a GitHub App
# installation token cannot pull private GHCR packages — community #171423).
#
# STRUCTURAL PRECEDENT: git-data.tf (ADR-068), NOT inngest.tf. inngest.tf has no host
# resources — Inngest runs as a unit ON the web host. git-data is the only brand-new
# dedicated-host precedent, so this file mirrors its host/volume/network/firewall/
# heartbeat/scoped-secret shape 1:1.
#
# APPLY-PATH (CTO ruling 2026-07-06, apply-path-cto-ruling.md): every resource here is
# an OPERATOR_APPLIED_EXCLUSION (parity test), applied by the operator's initial full
# (untargeted) `terraform apply` + the 12h drift detector — NONE are in the per-PR CI
# `-target=` list. The per-PR path bridges over SSH to the EXISTING web host; it cannot
# provision a brand-new host. Two load-bearing conditions: (1) cloud-init-only, NO
# `remote-exec` terraform_data (else the SSH-parity guard has no exclusion path); (2) no
# zot cred is a github_actions_secret — Phase-2 CI push reads ZOT_PUSH_* via `doppler run`.
#
# REPROVISION-PATH (ADR-096 amendment 2026-07-08): the per-PR exclusion above is UNCHANGED,
# but a sanctioned dispatch-only `registry-host-replace` `workflow_dispatch` path now exists
# (apply-web-platform-infra.yml, mirroring ADR-100's inngest-host-replace) to re-run this
# host's cloud-init + apply any pending volume resize WITHOUT SSH — a scoped, destroy-guarded
# `terraform apply -replace='hcloud_server.registry'` that PRESERVES hcloud_volume.registry.
# It is a maintenance-window dispatch, not a per-PR apply; these resources remain excluded
# from the per-PR `-target=` list.
#
# TRANSPORT: HTTP on the private net (deny-all-public firewall below). cosign digest-
# pinning + offline verify is the integrity guarantee (registry-agnostic — Phase-0 spike);
# the private network is the trust boundary (plan's accepted risk: a leaked read-only
# cred is pull-only, in-datacenter, private-network-scoped). Web hosts add the registry to
# docker `insecure-registries` in Phase 3. TLS on the private net is a documented hardening
# follow-up (not in this plan's scope; would add tls_* cert resources + CA distribution).

locals {
  # Fresh private IP in 10.0.1.0/24 — web = .10/.11, git-data = .20, registry = .30.
  registry_private_ip = "10.0.1.30"

  # The registry ref prefix web hosts + CI pull/push against (docker refs carry no
  # scheme). Published as ZOT_REGISTRY_URL.
  registry_endpoint = "${local.registry_private_ip}:5000"

  # zot's OWN image is third-party (upstream project-zot), DIGEST-PINNED, v2.1.2. Pulled from
  # the PUBLIC upstream registry at boot — NEVER from our own zot (bootstrap paradox, Sharp Edges).
  # Arch is DERIVED from var.registry_server_type so a single var switches the whole host: `cax*`
  # (Ampere) → arm64, anything else (`cx*`/`cpx*`) → amd64. This lets provisioning take whichever of
  # cax11 (ARM, €5.99) / cx23 (x86, €5.49) has Hetzner stock — both are functionally identical for a
  # store-and-serve registry (it never RUNS the amd64 platform images it holds). Re-verify BOTH
  # digests on a version bump: `crane digest ghcr.io/project-zot/zot-linux-{arm64,amd64}:vX.Y.Z`.
  registry_arch   = startswith(var.registry_server_type, "cax") ? "arm64" : "amd64"
  zot_image_arm64 = "ghcr.io/project-zot/zot-linux-arm64@sha256:c3fc47782d98b731d5928a24182b495e28cc92f9dcf1d5317f7dbd632e10bf30"
  zot_image_amd64 = "ghcr.io/project-zot/zot-linux-amd64@sha256:073f30d99fbdbcd8869334231c9ca45c75e535e4bdc6e28cc8a1541abe7a3f71"

  # zot's container memory cap, DERIVED from the host it will actually run on (ADR-062:
  # cap = host RAM − ~1024m for cron+doppler+sshd+OS). It was previously a hardcoded
  # `7168m` literal in cloud-init-registry.yml, with NOTHING tying it to
  # var.registry_server_type — the same missing-data-edge shape as the htpasswd staleness this
  # host's replace_triggered_by exists to prevent, and just as silent. (This said "the htpasswd
  # bug ... exists to fix (#6497)". Deleted: that causation was falsified by the 2026-07-16
  # 08:15Z re-bake — htpasswd converged on both users and `login_failed` continued. The
  # missing-data-edge ANALOGY is what this comment needs and it survives intact; naming a
  # still-open defect as the thing a line "fixes" is precisely what made #6497 undiagnosable for
  # a week.) Switching the
  # var to a 4 GB type would have left a 7168m cap on a 4096m host: the cgroup limit can
  # never bind, so zot is free to take the host down instead of being contained — which is
  # precisely the uncapped-on-4GB condition of the #6288 restart-loop. Deriving it means
  # the cap cannot disagree with the host, whatever the var says.
  #
  # `memory` is GB from the live catalog, so the value tracks Hetzner rather than a map
  # that rots. It is also a phantom-type tripwire: #6288 set this var to `cx32`, a type
  # that does not exist, and the apply DESTROYED the registry host before failing
  # `server type cx32 not found` on the create. This data source resolves at PLAN time, so
  # a nonexistent type now fails before anything is destroyed.
  registry_host_reserve_mb = 1024
  registry_memory_cap_mb   = data.hcloud_server_type.registry.memory * 1024 - local.registry_host_reserve_mb
  zot_image                = local.registry_arch == "arm64" ? local.zot_image_arm64 : local.zot_image_amd64
  # Doppler CLI (v3.75.3) per-arch SHA256 for the cloud-init download (arm64 / amd64).
  doppler_sha256 = local.registry_arch == "arm64" ? "f1954f3717fe4c5b65e906a3c6dfe0d20e97b032af35e43db41250931302e143" : "9c840cdd32cffff06d048329549ba2fa908146b385f21cd1d54bf34a0082d0db"

  # Non-secret, stable htpasswd usernames (constants — only the TOKENS are secret).
  zot_pull_user = "zot-pull"
  zot_push_user = "zot-push"

  # Better Stack Logs ingest endpoint for the registry host's SOLEUR_ZOT_DISK self-report
  # (#6244). Region/cluster-bound (learning 2026-05-22): source 2457081 authenticates on the
  # EU Falkenstein cluster `eu-fsn-3` — the EXACT endpoint vector.toml ships to (verified
  # 2026-05-22 via authenticated POST probe: eu-fsn-3 → 202, eu-nbg-2 → 401). The registry
  # reuses this SAME source + token (SOLEUR_ZOT_DISK is the discriminating grep marker), so no
  # new source is provisioned. NON-secret host routing (like disk_heartbeat_url) → baked into
  # user_data via templatefile; the token is the only secret and stays in the isolated Doppler
  # config. (#6895) The boot isolation self-check cardinality is now 4 — 2 ZOT tokens + this logs
  # token + REGISTRY_LUKS_KEY (the guest-LUKS passphrase) — see the self-check at :741-746.
  # keep in sync with vector.toml [sinks.betterstack].uri (same source 2457081 / eu-fsn-3 endpoint).
  betterstack_logs_ingest_url = "https://s2457081.eu-fsn-3.betterstackdata.com/"
}

# --- Read-only pull + read/write push credentials (TF-generated, zero human mint) ----
# random_password (NOT random_id) → printable, htpasswd/URL-safe. special=false keeps the
# token free of chars that break `docker login -p` / htpasswd. NO ignore_changes anywhere
# downstream (TF owns the values), so `terraform apply -replace=random_password.zot_pull`
# updates BOTH Doppler copies (soleur/prd + soleur-registry/prd) in one apply.
#
# The host's /etc/zot/htpasswd is a SEPARATE plane and does NOT follow from that. It is
# baked exactly once — at boot, by cloud-init-registry.yml's runcmd — from these values,
# read via the Doppler CLI. The token values are deliberately kept out of user_data
# (see :263-265), so Terraform has NO data edge from random_password to
# hcloud_server.registry and cannot know a rotation staled the bake.
# hcloud_server.registry's lifecycle.replace_triggered_by is what supplies that edge: it
# replaces the host so the htpasswd is re-baked from the new value in the SAME apply.
# Without it a rotation silently diverges the host from Doppler and every pull login is
# rejected forever, with no signal saying why. Mirrors random_password.git_data_luks.
#
# This comment used to end "— which is exactly what #6497 / Sentry WEB-PLATFORM-5B was."
# That causation is FALSIFIED and the claim is deleted rather than softened: the 2026-07-16
# 08:15Z re-bake was the experiment the hypothesis implied, and after it the host's htpasswd
# MATCHES Doppler on both users while `login_failed` continues. A stale htpasswd is a real
# hazard and this edge is the right fix for it — it was simply not the cause of #6497, whose
# actual cause is still unknown (see the plan; #6497 buys the datum before attempting a
# repair). Naming a still-open defect as "solved by this line" is what made the gate
# undiagnosable for a week in the first place.
# The registry host's server type, read from the live Hetzner catalog so local.registry_
# memory_cap_mb tracks the real host instead of a hand-maintained type→RAM map. Read-only;
# creates nothing. Resolves at PLAN time, which is what makes it a phantom-type tripwire
# (see the local's comment: #6288's `cx32` destroyed a host before failing on the create).
data "hcloud_server_type" "registry" {
  name = var.registry_server_type
}

# #6497 / #6565 — BOTH attributes below are load-bearing for a SECURITY property in another file.
# `ci-deploy.sh` › `_login_hatch()` emits TWO length fields off-box to Better Stack + Sentry:
# `stderr_chars` (the length of `docker login`'s whole stderr) and `errno_chars` (#6565 — the
# length of its FINAL ": "-delimited segment). Both are safe ONLY because this token is
# (a) fixed-length, so a registry echoing it moves the length by the same amount for every
# possible value (zero bits about content), and (b) drawn from `[A-Za-z0-9]` (`special = false`),
# so no character expands under a registry's JSON/URL escaping into a CONTENT-DEPENDENT length.
# Changing `length` to a variable-length credential (a JWT / OIDC-minted session token) OR
# setting `special = true` turns BOTH fields into a length oracle on a live credential, and
# **BOTH MUST be bucketed first — bucketing only `stderr_chars` leaves `errno_chars` carrying the
# same oracle through a narrower window.** Read `_login_hatch()`'s field table before touching either.
# The reverse-citation exists because the trigger was written in the CONSUMER and this is the
# PRODUCER — and `specs/feat-registry-oidc-migration/spec.md` FR2/FR3 already schedule exactly
# that change.
resource "random_password" "zot_pull" {
  length  = 40
  special = false
}

resource "random_password" "zot_push" {
  length  = 40
  special = false
}

# --- #6895 (ADR-096 amendment / ADR-140) — guest-side LUKS-at-rest passphrase --------
# The zot storage volume (hcloud_volume.registry) is a RAW block device (no `format`
# below); cryptsetup luksFormat/luksOpen runs IN THE GUEST at cloud-init
# (cloud-init-registry.yml), unlocked by THIS passphrase delivered ONLY as the
# Doppler-injected env REGISTRY_LUKS_KEY — never an argv positional, never baked into
# user_data. There is NO hcloud `encrypted` volume attribute (ADR-140). Mirrors
# random_password.git_data_luks (git-data-luks.tf): length 40 alphanumeric (~238 bits),
# special=false keeps it shell/stdin-safe for the `printf %s | cryptsetup --key-file -`
# pipe. NO keepers / NO ignore_changes — rotation is operator-explicit via `-replace`
# (SE1: a rotation is a volume RECUT, not a bare host replace — see the depends_on note
# and cloud-init-registry.yml's LUKS block).
resource "random_password" "registry_luks" {
  length  = 40
  special = false
}

# --- Host-scoped boot credential: the ISOLATED `soleur-registry` project ---------------
# The registry host builds its htpasswd from BOTH tokens at boot, reading them via a
# read-only service token. TRUE isolation requires a boundary that does NOT share the `prd`
# root: a Doppler *branch config* under `prd` (as the original design used) does NOT isolate —
# every config in an environment resolves that environment's ROOT config as its base, so a
# token "scoped" to a `prd` branch config reads the FULL prd secret set (SUPABASE_SERVICE_ROLE_KEY,
# GIT_* keys, PROXY_TLS_* — all 116). Empirically verified (#6122). So the host credential
# lives in a DEDICATED project `soleur-registry` whose own `prd` ROOT config holds ONLY these
# two ZOT tokens; a read token scoped to it resolves exactly two secrets and nothing else.
# This DEPARTS FROM — does not mirror — the `prd_git_data` / `prd_kb_drift_walker` branch-config
# pattern, which has the identical non-isolation bug (audit + remediation tracked in #6167).
# (A standalone *environment* in `soleur` was rejected: the project is at the 4-environment
# tier cap — dev/prd/ci/cli — so a 5th env is impossible without a Doppler Team-plan upgrade.)
#
# PROVISIONING (fully automated — ZERO operator CLI actions, per
# hr-fresh-host-provisioning-reachable-from-terraform-apply): the agent's `terraform apply` stands
# the whole isolation boundary up from empty state. Terraform creates the isolated project
# (`doppler_project.registry`) AND its `prd` environment + root config (`doppler_environment.registry_prd`),
# then writes the two host secrets + the boot token into that config. var.doppler_token_tf is a
# workplace-scope personal token (create-project + create-environment scope). Rotate via
# `terraform apply -replace=random_password.zot_pull`.
resource "doppler_project" "registry" {
  name        = "soleur-registry"
  description = "Isolated boot-credential project for the zot registry host (#6122, ADR-096) — its `prd` root config holds ONLY the two ZOT htpasswd tokens; cross-project isolation from soleur/prd (no shared root-secret resolution path)."
}

# The `prd` environment + its root config inside the isolated project. REQUIRED for zero-operator
# provisioning: a TF-created `doppler_project` is created BARE (no default dev/stg/prd configs that
# the Doppler CLI/dashboard would auto-add), so without this the host secrets below fail at apply
# with "Doppler Error: Could not find requested config 'prd'" (#6122 provisioning). Creating the
# environment also creates its same-named root config, which is the isolation boundary the host
# boot token resolves. Does NOT need the paid config-inheritance feature (#6067) — it is a basic
# Project-Structure resource, not a branch config.
resource "doppler_environment" "registry_prd" {
  project = doppler_project.registry.name
  slug    = "prd"
  name    = "Production"
}

resource "doppler_secret" "zot_pull_token_registry" {
  project    = doppler_project.registry.name
  config     = doppler_environment.registry_prd.slug
  name       = "ZOT_PULL_TOKEN"
  value      = random_password.zot_pull.result
  visibility = "masked"
}

resource "doppler_secret" "zot_push_token_registry" {
  project    = doppler_project.registry.name
  config     = doppler_environment.registry_prd.slug
  name       = "ZOT_PUSH_TOKEN"
  value      = random_password.zot_push.result
  visibility = "masked"
}

# #6895 — the guest-side LUKS passphrase, published to the SAME isolated soleur-registry/prd
# root config the host already reads at boot (doppler_service_token.registry). Mirrors
# doppler_secret.git_data_luks_key — no NEW service token is provisioned; the existing scoped
# read token resolves it alongside the two ZOT tokens + the logs token. This is the FOURTH
# secret in the isolated config, so the boot isolation self-check cardinality moves 3->4
# (cloud-init-registry.yml :741-746, P1-A) and REGISTRY_LUKS_KEY is admitted BY NAME. It is a
# registry-scoped secret, so the #6122 isolation property is preserved (no soleur/prd path).
resource "doppler_secret" "registry_luks_key" {
  project    = doppler_project.registry.name
  config     = doppler_environment.registry_prd.slug
  name       = "REGISTRY_LUKS_KEY"
  value      = random_password.registry_luks.result
  visibility = "masked"
}

# Write-only Better Stack Logs ingest token in the ISOLATED soleur-registry/prd config, so the
# registry host's zot-disk-heartbeat.sh reporter (cloud-init-registry.yml) can ship its
# SOLEUR_ZOT_DISK disk-state event to Better Stack Logs under `doppler run --project
# soleur-registry --config prd` — the in-surface probe for the deny-all, no-SSH host (#6244).
# EXACT MIRROR of inngest-betterstack-token.tf (#6197, ADR-100): value from the sensitive,
# no-default var.betterstack_logs_token (sourced from Doppler prd_terraform —
# hr-tf-variable-no-operator-mint-default; already provisioned for #6197, only the one 24-char
# token enters terraform.tfstate). ignore_changes=[value]: rotation is managed at the source of
# truth, and the boot isolation self-check keys on the NAME so a rotate is safe. Reference the
# TF-managed project + env (NOT literals) so Terraform builds the dependency edge and a `-target`
# of this secret pulls the project/config in. Its presence is REQUIRED by the amended boot guard
# (cardinality 3) — deleting it FATALs the bootstrap (loud fail > silent observability blind spot).
resource "doppler_secret" "registry_betterstack_logs_token" {
  project    = doppler_project.registry.name
  config     = doppler_environment.registry_prd.slug
  name       = "BETTERSTACK_LOGS_TOKEN"
  value      = var.betterstack_logs_token
  visibility = "masked"

  lifecycle {
    ignore_changes = [value]
  }
}

# Read-only service token scoped to the isolated `soleur-registry` project's `prd` ROOT config
# (only the two ZOT tokens). Handed to the registry host cloud-init in place of the full-prd
# var.doppler_token. `.key` is Computed/write-once (same handling as doppler_service_token.git_data);
# rotate via `terraform apply -replace=doppler_service_token.registry`.
resource "doppler_service_token" "registry" {
  project = doppler_project.registry.name
  config  = doppler_environment.registry_prd.slug
  name    = "zot-registry-boot"
  access  = "read"
}

# --- Client/CI-facing secrets: the shared `prd` config ---------------------------------
# Web hosts (pull) + CI (push) read these from `prd`, their existing runtime/deploy config.
# TF owns the values → NO ignore_changes (mirrors the ghcr-minter-doppler-token.tf shape, NOT
# ghcr-read-credential.tf's operator-minted ignore_changes shape).
resource "doppler_secret" "zot_registry_url" {
  project    = "soleur"
  config     = "prd"
  name       = "ZOT_REGISTRY_URL"
  value      = local.registry_endpoint
  visibility = "masked"
}

resource "doppler_secret" "zot_pull_user" {
  project    = "soleur"
  config     = "prd"
  name       = "ZOT_PULL_USER"
  value      = local.zot_pull_user
  visibility = "masked"
}

resource "doppler_secret" "zot_pull_token" {
  project    = "soleur"
  config     = "prd"
  name       = "ZOT_PULL_TOKEN"
  value      = random_password.zot_pull.result
  visibility = "masked"
}

resource "doppler_secret" "zot_push_user" {
  project    = "soleur"
  config     = "prd"
  name       = "ZOT_PUSH_USER"
  value      = local.zot_push_user
  visibility = "masked"
}

resource "doppler_secret" "zot_push_token" {
  project    = "soleur"
  config     = "prd"
  name       = "ZOT_PUSH_TOKEN"
  value      = random_password.zot_push.result
  visibility = "masked"
}

# --- The registry host -----------------------------------------------------------------
resource "hcloud_server" "registry" {
  name        = "soleur-registry"
  server_type = var.registry_server_type # cax11 (arm64) / cx23 (amd64) — arch derived in locals
  location    = var.registry_location    # independent of var.location (#6122: registry is nbg1)
  image       = "ubuntu-24.04"
  keep_disk   = true
  ssh_keys    = [hcloud_ssh_key.default.id]

  # Public IPv4/IPv6 for EGRESS only (apt + the upstream zot image pull during cloud-init).
  # A no-public-IP host has NO internet (no NAT gateway). INGRESS on the public interface is
  # denied by hcloud_firewall.registry below; pull transport is private-net only. Mirrors
  # git-data.tf's public_net rationale.
  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  # base64gzip-first (git-data.tf / ADR-080 #5927): wrap the whole render so the shell
  # payload compresses under Hetzner's 32,768-byte user_data cap. zot's cloud-init is small
  # (docker + one container + htpasswd gen; no bake-and-extract), but budget for it anyway
  # and verify the byte-exact size at the first `terraform plan`. Hetzner base64-decodes →
  # gzip magic → cloud-init auto-gunzips → byte-identical #cloud-config (DataSourceHetzner).
  user_data = base64gzip(templatefile("${path.module}/cloud-init-registry.yml", {
    # Mount the zot storage volume by its specific id (server.tf/cloud-init.yml by-id
    # pattern). Known at plan time; the attachment is a separate resource.
    registry_volume_id = hcloud_volume.registry.id
    # Scoped read-only Doppler token → 0600 root env file so the boot-time `doppler run`
    # can read ZOT_PULL_TOKEN/ZOT_PUSH_TOKEN and build htpasswd. The tokens themselves are
    # NEVER in this user_data (retrievable via the hcloud metadata API).
    doppler_token = doppler_service_token.registry.key
    # zot's digest-pinned upstream image + the fixed htpasswd usernames (non-secret).
    zot_image     = local.zot_image
    zot_pull_user = local.zot_pull_user
    zot_push_user = local.zot_push_user
    # Host arch (arm64/amd64) → the matching Doppler CLI release build + its checksum.
    doppler_arch   = local.registry_arch
    doppler_sha256 = local.doppler_sha256
    # zot's cgroup memory cap, derived from THIS host's real RAM (see local.registry_
    # memory_cap_mb). Baked into user_data on purpose: that gives Terraform the data edge
    # the hardcoded literal never had, so a server_type change re-renders user_data and
    # re-bakes a matching cap on the replaced host, in the same apply. Non-secret (a
    # number), same class as zot_image.
    zot_memory_cap_mb = local.registry_memory_cap_mb
    # Disk-health heartbeat: the host pings this ONLY while /var/lib/zot is under 85% used, so
    # a filling store (or a down host / broken cron) alerts via Better Stack absence — no SSH,
    # no dashboard-eyeballing (hr-no-dashboard-eyeball-pull-data-yourself). Not a secret (a bare
    # ping URL); baked into user_data like zot_image, retrievable via the hcloud metadata API.
    disk_heartbeat_url = betteruptime_heartbeat.registry_disk_prd.url
    # #6537 — zot LIVENESS heartbeat: the host pings this ONLY while zot answers on its own
    # private IP, so a dead zot process on a live host alerts via Better Stack absence. This is
    # the feeder that arms betteruptime_heartbeat.registry_prd; until it shipped, that monitor
    # had ZERO consumers and stayed paused. Same class as disk_heartbeat_url: a bare ping URL,
    # not a secret, baked into user_data and retrievable via the hcloud metadata API.
    liveness_heartbeat_url = betteruptime_heartbeat.registry_prd.url
    # Better Stack Logs ingest URL for the SOLEUR_ZOT_DISK self-report (#6244). NON-secret host
    # routing (like disk_heartbeat_url) — baked into user_data; the ONLY secret is
    # BETTERSTACK_LOGS_TOKEN, injected at cron time via `doppler run` from the isolated config.
    betterstack_ingest_url = local.betterstack_logs_ingest_url
    # #6415 — the host's OWN expected private IP, baked at template time so the private-NIC
    # guard's trigger predicate is a pure LOCAL read with zero runtime dependencies (IMDS is
    # telemetry, never the trigger). Non-secret host routing, same class as zot_image: this
    # RFC1918 address is already in user_data and retrievable from the hcloud metadata API.
    # Single-sourced with hcloud_server_network.registry.ip (network.tf) — see the drift
    # rationale there; a drifted copy would reboot a healthy host.
    private_ip = local.registry_private_ip
  }))

  # Deliberately NO lifecycle.ignore_changes=[user_data]. A FRESH host has no spurious diff,
  # and omitting it preserves a clean replace-to-reprovision path (git-data.tf rationale) —
  # so a zot config change re-applies via cloud-init re-provision (cloud-init is idempotent).

  # #6497: the ONLY edge from the pull/push credentials to this host. The tokens are read at
  # boot via the Doppler CLI and baked into /etc/zot/htpasswd once; they are deliberately
  # absent from user_data (:263-265), so Terraform sees no data dependency and a rotation
  # would leave the host serving the OLD htpasswd forever while both Doppler copies show the
  # new value. Naming the resources here forces the bake to follow the value: a rotation
  # replaces the host in the same apply.
  # This edge is sound on its own terms, but it is NOT the fix for #6497 — that claim was
  # falsified by the 2026-07-16 08:15Z re-bake (htpasswd now matches Doppler on both users;
  # `login_failed` continues). See the falsification note on `random_password.zot_pull`.
  # SAFE on a routine apply: random_password has no `keepers`, so these are stable and fire
  # only under an explicit `-replace` (verify with `grep -nE '^\s*keepers' zot-registry.tf` →
  # no hits; a bare `grep -n keepers` also matches this very comment).
  # The edge fires ONLY on the operator's untargeted full apply — the registry-host-replace
  # dispatch hardcodes `-replace='hcloud_server.registry'` and does not target these, so a
  # rotation is not plannable there. See the ADR-115 amendment (#6497).
  lifecycle {
    replace_triggered_by = [
      random_password.zot_pull,
      random_password.zot_push,
    ]
  }

  # #6244: the host does NOT reference doppler_secret.registry_betterstack_logs_token directly
  # (the cron reads it at run time via `doppler run`), so there is no IMPLICIT dependency edge.
  # The amended 3-secret boot guard FATALs (zot never launches) if that secret is not already in
  # the isolated config when this host boots — make the ordering DETERMINISTIC (not latency-lucky
  # on the registry-host-replace apply) by declaring it explicitly.
  # #6497: the two ZOT token secrets are read at boot through the same Doppler CLI path and
  # GATE the htpasswd bake, so they need the identical treatment — the #6244 fix was made for
  # one secret and never generalized. Without them a fresh stand-up (or this host's own
  # replace) may boot before the secret writes land and bake an htpasswd from a stale read.
  # #6895: REGISTRY_LUKS_KEY is read at boot through the SAME scoped Doppler CLI path and GATES
  # the guest luksFormat/luksOpen of the store volume — the identical boot-ordering hazard the
  # three secrets above already guard. Without this edge a fresh stand-up (or this host's own
  # replace) may boot before the secret write lands and FATAL on an empty key (fail-loud). Do NOT
  # add random_password.registry_luks to lifecycle.replace_triggered_by above: rotating the
  # passphrase and merely replacing the HOST would luksOpen the OLD-key volume with the NEW key
  # and FATAL — a rotation is a volume RECUT (SE1), not a bare host replace.
  depends_on = [
    doppler_secret.registry_betterstack_logs_token,
    doppler_secret.zot_pull_token_registry,
    doppler_secret.zot_push_token_registry,
    doppler_secret.registry_luks_key,
  ]

  labels = {
    app = "soleur-web-platform"
  }
}

# --- zot storage block volume ----------------------------------------------------------
# The OCI blobs (both platform images + backfilled release tags + cosign .sig referrers)
# live here — never tmpfs (a wiped registry breaks cold-boot pulls). dedupe is on, so a
# small volume is ample. Shape mirrors hcloud_volume.git_data.
resource "hcloud_volume" "registry" {
  name     = "soleur-registry-store"
  size     = var.registry_volume_size
  location = var.registry_location # MUST match hcloud_server.registry (#6122: nbg1)
  # SHARP EDGE (#6895 / D1 Option B): NO `format` — this is a RAW block device. Guest-side
  # cryptsetup luksFormats it luks2 at cloud-init and mkfs.ext4's the real FS INSIDE the
  # /dev/mapper/registry mapper (cloud-init-registry.yml). There is no hcloud `encrypted`
  # attribute (ADR-140); at-rest encryption is guest-side only. A raw device lets the guest's
  # `blkid TYPE` discriminator distinguish fresh ("") -> luksFormat, crypto_LUKS -> reuse, and
  # any OTHER TYPE (e.g. a populated plaintext ext4 the registry-host-replace preserve-path
  # kept) -> FATAL refuse instead of a silent wipe. This DEPARTS from git_data_luks (which keeps
  # format=ext4 + an isLuks guard, Option A) precisely because the registry has a volume-preserving
  # host-replace dispatch git-data lacks (ADR-096 footgun).

  labels = {
    app = "soleur-web-platform"
  }
}

resource "hcloud_volume_attachment" "registry" {
  volume_id = hcloud_volume.registry.id
  server_id = hcloud_server.registry.id
}

# --- Deny-all PUBLIC ingress firewall --------------------------------------------------
# ZERO inbound rules = deny-all on the PUBLIC interface. Hetzner firewalls filter only the
# public interface; intra-hcloud_network traffic (web hosts pulling on 10.0.1.0/24) is open
# by network membership and needs NO allow rule. NO public ingress for the registry — pull
# transport is private-net only. Egress (apt + upstream zot image pull) is unaffected by
# inbound rules. Mirrors hcloud_firewall.git_data exactly.
resource "hcloud_firewall" "registry" {
  name = "soleur-registry"

  labels = {
    app = "soleur-web-platform"
  }
}

resource "hcloud_firewall_attachment" "registry" {
  firewall_id = hcloud_firewall.registry.id
  server_ids  = [hcloud_server.registry.id]
}

# --- Liveness (PUSH heartbeat) ---------------------------------------------------------
# Better Stack cannot PULL a deny-all-public-ingress host, so liveness is a PUSH heartbeat.
#
# WHAT FEEDS THIS (#6537): the registry's OWN cloud-init ships `zot-liveness-heartbeat.timer`
# (cloud-init-registry.yml), which pings this URL every 60s ONLY while zot answers on the host's
# private IP. The probe targets the private IP, never loopback: zot binds 0.0.0.0, so a loopback
# probe answers even on a host holding no private NIC (#6400's exact blindness).
#
# Enforced, not asserted: `heartbeat-manifest.ts` declares this row's feeder as the arming
# construct, and TWO suites gate it — `zot-liveness-heartbeat.test.sh` (delete the unit or the
# runcmd enable => RED, and it pins the private-IP + no-`-f` + AccuracySec properties behaviorally)
# and `heartbeat-reprovision-parity.test.ts` (the manifest row must name a real arming construct).
#
# The earlier version of THIS comment described a web-host probe cron and told the reader to
# "unpause via the Better Stack UI once the probe ships". The probe was never written, so the
# monitor sat paused and inert for 9 days while this comment asserted otherwise. That dangling
# instruction — no owner, no forcing function, unverified by anything — WAS the bug (#6537), and it
# is deliberately not replaced with another one.
#
# `paused = true` here is correct and permanent: `ignore_changes = [paused]` below decouples source
# from live state, and this resource is an OPERATOR_APPLIED_EXCLUSION (untargeted), so a source
# unpause is a no-op either way. LIVE state is armed (paused=false, up) as of 2026-07-16 — this
# source value is not the live one, which is the whole point of ADR-117.
#
# Arming was a one-time API PATCH under a bounded arm-and-watch: the beat CANNOT be measured before
# unpausing (Better Stack exposes no last_heartbeat_at and no /events; a paused monitor reads
# status="paused" forever), so the rollback is held in-process and re-pauses inside period+grace if
# no beat lands. It fired for real on the first attempt — the host booted NIC-less (#6400), the
# feeder correctly withheld its ping, and the rollback re-paused at 86s with no alert. See ADR-117
# §Ordering. Do NOT "simplify" this to a bare unpause: an unfed monitor left armed pages forever
# (#6210).
#
# The consumer-perspective probe (can a CLIENT reach zot over the private net?) is a DIFFERENT
# layer and remains open as #6438 §1; this on-host beat does not close it.
resource "betteruptime_heartbeat" "registry_prd" {
  name      = "soleur-registry-prd"
  period    = 60
  grace     = 30
  call      = false
  sms       = false
  email     = true
  push      = false
  team_wait = 0
  # Literal case-sensitive team name (see inngest.tf / git-data.tf).
  team_name = "Your team"
  # Reuse the existing inngest escalation policy (git-data.tf does the same) — no new policy.
  policy_id  = var.betterstack_paid_tier ? betteruptime_policy.inngest[0].id : null
  paused     = true
  sort_index = 0

  lifecycle {
    # Operator unpause via UI MUST NOT be reverted by subsequent applies (git-data.tf rationale).
    ignore_changes = [paused]
  }
}

# NOTE (#6438 B3): doppler_secret.zot_heartbeat_url_prd (ZOT_HEARTBEAT_URL) was DELETED here. It was
# a reservation for the OFF-HOST consumer-perspective probe (#6438 §1) that never existed, and its
# own comment prescribed deleting it once #6438 resolved. #6438 is now resolved by the WEB-HOST
# consumer probe, which mints its OWN per-host heartbeat + URL secret (betteruptime_heartbeat.
# web_zot_consumer / doppler_secret.web_zot_consumer_url in web-probe.tf) — the registry's own
# registry_prd beat is the registry's self-view, not the consumer's. Removing the reserved secret is
# the single expected `-target`ed destroy on this apply (AC5).

# --- Disk-capacity guard (#6122 follow-up) --------------------------------------------------
# A SECOND heartbeat, distinct from the liveness beat above: the registry host's cron pings it
# only while /var/lib/zot is < 85% used (cloud-init-registry.yml). A store that grows toward full
# — the failure that #6122 hit (100% → all pushes 500 'no space left on device') — silently stops
# the ping, and Better Stack alerts BEFORE the disk is full, without any SSH/df or dashboard poll
# (hr-no-dashboard-eyeball-pull-data-yourself). Pairs with storage.retention (growth cap) + the
# 60 GB volume (headroom, grown 30→60 in #6247): retention bounds growth, this catches it if bounding ever regresses.
# period 900s / grace 600s: disk fills slowly, and 600s of grace covers the redeploy boot gap so
# paused=false is safe (no operator UI unpause needed — the cron pings within cloud-init).
resource "betteruptime_heartbeat" "registry_disk_prd" {
  name       = "soleur-registry-disk-prd"
  period     = 900
  grace      = 600
  call       = false
  sms        = false
  email      = true
  push       = false
  team_wait  = 0
  team_name  = "Your team"
  policy_id  = var.betterstack_paid_tier ? betteruptime_policy.inngest[0].id : null
  paused     = false
  sort_index = 0

  lifecycle {
    # Operator UI pause (e.g. during a planned volume resize) must survive subsequent applies.
    ignore_changes = [paused]
  }
}
