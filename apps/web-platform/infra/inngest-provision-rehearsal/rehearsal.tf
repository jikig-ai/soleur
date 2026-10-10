# (#9175) The throwaway Inngest host and everything the forced-race rehearsal needs.
#
# EVERY ADDRESS IN THIS FILE CARRIES `.rehearsal` IN ITS NAME, and that is a mechanical
# contract rather than a naming convention: inngest-provision-rehearsal.test.sh asserts
# that every hcloud_*/doppler_* address in this root matches `\.rehearsal\b`. An address
# without it is either a typo or a prod resource that wandered in, and the two are
# indistinguishable at review speed.
#
# THE REHEARSAL IS THE PROVISION PATH, NOT THE HOST. What is under test is
# cloud-init-inngest.yml's provision unit end-to-end: NIC-absent birth -> private_nic_timeout
# -> bounded retries -> (Phase B attaches the NIC) -> zot pull -> isolation check ->
# bootstrap -> latch -> REBOOT -> latch prevents re-run. The host exists only to run those
# bytes; it is destroyed when the run ends.
#
# ONLY THE IDENTITY IS THROWAWAY, NOT THE MECHANISM. The template is the PRODUCTION
# cloud-init-inngest.yml rendered through terraform's own templatefile, the volumes are real
# Hetzner volumes, and the Doppler reads/writes are real — a stub anywhere in that chain
# would rehearse a boot that does not exist and report it as the real one.

locals {
  # The trailing hyphen before the run id is LOAD-BEARING everywhere this prefix is matched:
  # `soleur-inngest` is a PREFIX of `soleur-inngest-rehearsal-…`, so an unanchored glob
  # written the other way round matches the PRODUCTION host. The orphan sweep in
  # scheduled-terraform-drift.yml pins the same literal for the same reason.
  rehearsal_host_name = "soleur-inngest-rehearsal-${var.rehearsal_run_id}"
  # The scratch Doppler config name. `rehearsal_<runid>` is a ROOT config of a NON-INHERITING
  # environment — deliberately NOT a branch under prd (branch configs resolve the
  # environment's root as their base, which would hand the throwaway host every prod
  # soleur-inngest secret). The workflow passes it to the template as inngest_doppler_config.
  rehearsal_doppler_config = "rehearsal_${var.rehearsal_run_id}"
  # The private IP the Phase-B NIC attach assigns. Distinct from prod's .40 (the live
  # scheduler keeps it), in the same 10.0.1.0/24 subnet the template's NIC wait expects.
  rehearsal_private_ip = "10.0.1.60"

  # Arch derivation mirrors inngest-host.tf's local.inngest_arch exactly (cax* -> arm64).
  rehearsal_arch = startswith(var.server_type, "cax") ? "arm64" : "amd64"

  # THE PINNED CHECKSUMS ARE COPIES OF THE PARENT ROOT'S — inngest.tf's
  # inngest_cli_sha256(+_arm64) and inngest_doppler_sha256, vector.tf's vector_sha256(+_arm64).
  # A literal copy is the divergence class #6570 burned on (a pin bump applied to the parent
  # alone leaves this root verifying a different binary while every suite stays green), so
  # inngest-provision-rehearsal.test.sh pins all four pairs EQUAL to the parent literals.
  inngest_cli_sha256       = "52c07d837088a6712acd15b8edd4191f961b69884541f468a3c1b9bb4348a4e5"
  inngest_cli_sha256_arm64 = "58db59dbe39afd7472c7c59bd7cc9f82f5da5810dabdac40b2bde3a8338aa7b5"
  vector_sha256            = "8a3cc62d18ec88bb8433159d1d3455d3c77fefff73ce46d4f8cc464e100f65f1"
  vector_sha256_arm64      = "365bab73244780083eb95b3e42161a9179f23a0811ffa6180f613c3af06ed8e6"
  doppler_sha256           = local.rehearsal_arch == "arm64" ? "f1954f3717fe4c5b65e906a3c6dfe0d20e97b032af35e43db41250931302e143" : "9c840cdd32cffff06d048329549ba2fa908146b385f21cd1d54bf34a0082d0db"

  # The registry's stable private IP — the REAL zot endpoint, because the forced race exists
  # to exercise the REAL pull. In Phase A the host has no private NIC so this is unreachable
  # (that IS the injected failure); in Phase B the attach makes it routable.
  zot_registry_endpoint = "10.0.1.30:5000"
  zot_pull_user         = "zot-pull"

  # The whole-comment-line strip, byte-identical to inngest-host.tf's local
  # .inngest_rationale_strip — the render must be post-processed the same way production's
  # is, or the bytes that boot here differ from the bytes a prod birth would run.
  inngest_rationale_strip = "/(?m)^[ \t]*#([ \t][^\n]*)?\n/"

  rehearsal_user_data_plain = replace(templatefile("${path.module}/../cloud-init-inngest.yml", {
    # --- identity/scratch args (the ONLY deliberate divergences from prod's map) ---
    inngest_volume_id      = hcloud_volume.rehearsal_inngest.id
    inngest_luks_volume_id = hcloud_volume.rehearsal_inngest_luks.id
    doppler_token          = doppler_service_token.rehearsal.key
    inngest_doppler_config = local.rehearsal_doppler_config
    # SDK URL at loopback — no web backend exists for this host to register with, and a
    # closed loopback port is what INNGEST_DIAGNOSTIC_BOOT expects anyway.
    sdk_url = "http://127.0.0.1:3000/api/inngest"
    # The nftables allowlist renders these as the only permitted :8288 peers — loopback, so
    # even a reachable private net cannot route prod traffic to the throwaway host.
    web_host_private_ips = "127.0.0.1"
    inngest_private_ip   = local.rehearsal_private_ip
    # --- MUST MATCH PROD (the checksums above are drift-pinned by the sentinel suite) ---
    inngest_expect_luks    = "false"
    inngest_cli_arch       = local.rehearsal_arch
    inngest_cli_sha256     = local.rehearsal_arch == "arm64" ? local.inngest_cli_sha256_arm64 : local.inngest_cli_sha256
    vector_sha256          = local.rehearsal_arch == "arm64" ? local.vector_sha256_arm64 : local.vector_sha256
    doppler_arch           = local.rehearsal_arch
    doppler_sha256         = local.doppler_sha256
    zot_registry_endpoint  = local.zot_registry_endpoint
    zot_pull_user          = local.zot_pull_user
    zot_pull_token         = var.zot_pull_token
    betterstack_logs_token = var.betterstack_logs_token
    sentry_dsn             = ""
  }), local.inngest_rationale_strip, "")
  rehearsal_user_data_b64gz = base64gzip(local.rehearsal_user_data_plain)
}

# --- The private network (read-only; owned by the parent root) ----------------
# DATA, not resource — this root must never create or modify the shared network. Phase B
# attaches to it so the rehearsal exercises the real NIC-attached code path against the
# real subnet (zot reachability included).
data "hcloud_network" "private" {
  name = "soleur-private"
}

# --- Throwaway SSH key -------------------------------------------------------
# NOT an access path — nothing in this route SSHes to the rehearsal host (the reboot is the
# Hetzner API, the evidence is Better Stack). It exists because a Hetzner server created
# with no `ssh_keys` gets a ROOT PASSWORD MAILED to the account owner — a credential
# delivered over email, outliving the host. A throwaway key destroyed with the root is
# strictly less material at rest.
resource "tls_private_key" "rehearsal" {
  algorithm = "ED25519"
}

resource "hcloud_ssh_key" "rehearsal" {
  name       = local.rehearsal_host_name
  public_key = tls_private_key.rehearsal.public_key_openssh

  labels = {
    app = "soleur-inngest-provision-rehearsal"
  }
}

# --- The scratch Doppler environment (a NON-INHERITING root config) -----------
# `doppler_environment` (not `doppler_config`): an environment's root config inherits
# NOTHING, which is the whole isolation argument. The rung2 rehearsal used a branch config
# under `prd`; every branch under an environment resolves that environment's ROOT as its
# base, so that host could read every prod soleur secret. A token scoped to
# `rehearsal_<runid>` reads exactly the five secrets below — nothing else exists in it.
resource "doppler_environment" "rehearsal" {
  project = "soleur-inngest"
  slug    = local.rehearsal_doppler_config
  name    = "Rehearsal ${var.rehearsal_run_id}"
}

resource "random_id" "rehearsal_signing_key" {
  byte_length = 32
}

resource "random_id" "rehearsal_event_key" {
  byte_length = 32
}

resource "random_password" "rehearsal_redis_password" {
  length  = 48
  special = false
}

# The five secrets the scratch config holds, and NOTHING else — keep the set exact: the
# boot-time isolation self-check counts config members and FATALs on any unexpected name.
resource "doppler_secret" "rehearsal_signing_key" {
  project = doppler_environment.rehearsal.project
  config  = doppler_environment.rehearsal.slug
  name    = "INNGEST_SIGNING_KEY"
  # The signkey-prod- prefix is load-bearing: inngest-server's ExecStart strips exactly that
  # prefix (`${INNGEST_SIGNING_KEY#signkey-prod-}`) — a rehearsal key without it would boot
  # with the prefix still attached, which is a different value than prod computes.
  value      = "signkey-prod-${random_id.rehearsal_signing_key.hex}"
  visibility = "masked"
}

resource "doppler_secret" "rehearsal_event_key" {
  project    = doppler_environment.rehearsal.project
  config     = doppler_environment.rehearsal.slug
  name       = "INNGEST_EVENT_KEY"
  value      = random_id.rehearsal_event_key.hex
  visibility = "masked"
}

resource "doppler_secret" "rehearsal_redis_password" {
  project    = doppler_environment.rehearsal.project
  config     = doppler_environment.rehearsal.slug
  name       = "INNGEST_REDIS_PASSWORD"
  value      = random_password.rehearsal_redis_password.result
  visibility = "masked"
}

resource "doppler_secret" "rehearsal_diagnostic_boot" {
  project = doppler_environment.rehearsal.project
  config  = doppler_environment.rehearsal.slug
  name    = "INNGEST_DIAGNOSTIC_BOOT"
  # THE SAFETY VALUE. Diagnostic boot makes the bootstrap render the SQLite-only ExecStart
  # with --sdk-url pointed at a closed loopback port — the throwaway host adopts NO registry
  # and cannot double-fire prod crons even if every other guard failed. This is the arm the
  # rehearsal exists to make reproducible (#7228 shipped it; #9175 proves it survives a
  # forced provisioning race).
  value      = "true"
  visibility = "masked"
}

resource "doppler_secret" "rehearsal_betterstack_logs_token" {
  project    = doppler_environment.rehearsal.project
  config     = doppler_environment.rehearsal.slug
  name       = "BETTERSTACK_LOGS_TOKEN"
  value      = var.betterstack_logs_token
  visibility = "masked"
}

resource "doppler_service_token" "rehearsal" {
  project = doppler_environment.rehearsal.project
  config  = doppler_environment.rehearsal.slug
  name    = "inngest-provision-rehearsal-${var.rehearsal_run_id}"
  # READ, not read/write: the rehearsal exercises the provision+bootstrap path, which only
  # READS the config. The cutover FSMs are inert under diagnostic boot, so no write
  # authority is needed — and a leaked throwaway token then cannot MUTATE anything.
  access = "read"
}

# --- The two volumes ---------------------------------------------------------
# Mirrors prod's pair: a plaintext AOF volume and the LUKS target volume, both RAW (no
# `format` — the blkid signature IS the LUKS discriminator; declaring ext4 would make the
# resolver's empty arm unreachable, see inngest-redis-luks.tf's header note). Size matches
# prod's inngest_redis_volume_size default so the rehearsal exercises the same geometry.
resource "hcloud_volume" "rehearsal_inngest" {
  name     = "${local.rehearsal_host_name}-store"
  size     = 10
  location = var.location

  labels = {
    app = "soleur-inngest-provision-rehearsal"
  }
}

resource "hcloud_volume" "rehearsal_inngest_luks" {
  name     = "${local.rehearsal_host_name}-luks"
  size     = 10
  location = var.location

  labels = {
    app = "soleur-inngest-provision-rehearsal"
  }
}

# --- Deny-all PUBLIC ingress firewall -----------------------------------------
# Zero rules, same shape as hcloud_firewall.inngest. The host needs public EGRESS (apt,
# the CLI/binary downloads, Doppler, Sentry, Better Stack) and zero public ingress.
resource "hcloud_firewall" "rehearsal" {
  name = local.rehearsal_host_name

  labels = {
    app = "soleur-inngest-provision-rehearsal"
  }
}

# --- The host ------------------------------------------------------------------
# CLOUD-INIT ONLY — no remote-exec, no in-place patch path, matching inngest-host.tf's own
# posture. The host is created fresh, booted, measured off-box, REBOOTED (Hetzner API, for
# the latch-idempotence leg), and destroyed. No `keep_disk`: the root disk dies with it.
resource "hcloud_server" "rehearsal" {
  name        = local.rehearsal_host_name
  server_type = var.server_type
  location    = var.location
  image       = "ubuntu-24.04"
  ssh_keys    = [hcloud_ssh_key.rehearsal.id]

  # Public IPv4/IPv6 for EGRESS only — same rationale as the prod host (no NAT gateway
  # exists, so a no-public-IP host has no internet at all). Ingress is denied by the
  # deny-all firewall bound at ServerCreate below.
  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  # The deny-all firewall binds HERE, inside ServerCreate, so the host never boots
  # unfirewalled — mirrors hcloud_server.inngest's own comment (#8754 taught why the
  # attachment resource is wrong for this).
  firewall_ids = [hcloud_firewall.rehearsal.id]

  user_data = local.rehearsal_user_data_b64gz

  # Order the secret writes BEFORE the host boots — same edge git-data/inngest carry: the
  # service token is upstream via user_data, but a token is only AUTHORIZATION to read the
  # config; it says nothing about the config CONTAINING the names. Without this, terraform
  # could create the host first and the boot's isolation check would see an empty config.
  depends_on = [
    doppler_secret.rehearsal_signing_key,
    doppler_secret.rehearsal_event_key,
    doppler_secret.rehearsal_redis_password,
    doppler_secret.rehearsal_diagnostic_boot,
    doppler_secret.rehearsal_betterstack_logs_token,
  ]

  lifecycle {
    # The 32,768 B user_data cap, enforced at PLAN — a -replace/apply that produced an
    # over-cap render would otherwise destroy a live evidence mid-run. Mirrors prod's
    # precondition (inngest-host.tf) verbatim in spirit, with this root's locals.
    precondition {
      condition     = length(local.rehearsal_user_data_b64gz) <= 32768 && startswith(local.rehearsal_user_data_plain, "#cloud-config\n")
      error_message = "rehearsal user_data is ${length(local.rehearsal_user_data_b64gz)} B base64gzip'd against Hetzner's 32,768 B cap, or has lost its #cloud-config header. Refusing to plan."
    }
  }

  # NO `lifecycle.ignore_changes` anywhere in this root — the host is cattle by
  # construction (one boot, then teardown), so there is no drift to suppress, and
  # suppressing user_data drift would let a rehearsal re-report a stale boot as a fresh one.

  labels = {
    app = "soleur-inngest-provision-rehearsal"
  }
}

resource "hcloud_volume_attachment" "rehearsal_inngest" {
  volume_id = hcloud_volume.rehearsal_inngest.id
  server_id = hcloud_server.rehearsal.id
  automount = false
}

resource "hcloud_volume_attachment" "rehearsal_inngest_luks" {
  volume_id = hcloud_volume.rehearsal_inngest_luks.id
  server_id = hcloud_server.rehearsal.id
  automount = false
}

# THE PHASE TOGGLE. This is the ONLY resource whose existence differs between the two
# applies: Phase A (nic_attached=false) is born WITHOUT the private NIC so the provision
# unit's NIC wait exhausts and retries; Phase B (nic_attached=true) adds exactly this
# resource — `terraform plan -out` in the workflow asserts that additive delta is exactly
# this address and nothing else (scripts/inngest-provision-plan-shape.sh).
resource "hcloud_server_network" "rehearsal" {
  count      = var.nic_attached ? 1 : 0
  server_id  = hcloud_server.rehearsal.id
  network_id = data.hcloud_network.private.id
  ip         = local.rehearsal_private_ip
}
