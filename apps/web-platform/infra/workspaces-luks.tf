# =============================================================================
# LUKS-at-rest for the LIVE /workspaces volume (#6588, ADR-118)
# =============================================================================
#
# WHAT THIS CLOSES
# ----------------
# `hcloud_volume.workspaces` (server.tf) holds every user's checked-out source code
# as plaintext ext4, while docs/legal/{privacy-policy,gdpr-policy,data-protection-
# disclosure}.md tell data subjects it is LUKS-encrypted. The operator's decision is
# to make the claim true rather than retract it. This file declares the ADDITIVE
# encrypted volume that ADR-118 cuts over to.
#
# SHARP EDGE — encryption-at-rest is GUEST-SIDE LUKS, NOT an hcloud_volume attribute.
# There is no hcloud `encrypted` flag. `cryptsetup` runs on the host, unlocked by the
# Doppler-injected WORKSPACES_LUKS_KEY — never an argv positional, never baked into
# user_data. Mirrors git-data-luks.tf, with three DELIBERATE divergences called out
# below (no `format`, dedicated-config rationale, web-1 singleton).
#
# THE ISSUE'S PREMISE WAS WRONG, AND THE CORRECTION IS LOAD-BEARING
# -----------------------------------------------------------------
# #6588 asserts `hcloud_volume.format` is ForceNew, so a naive apply destroys the
# volume. That is a RED HERRING: LUKS is guest-side, so `format` never changes on the
# live volume. The REAL data-destroyer is the idempotence guard inverting:
# `if ! cryptsetup isLuks "$DEV"; then luksFormat` (cloud-init-git-data.yml) is false
# on a POPULATED PLAINTEXT device ⇒ luksFormat ⇒ live user code wiped. The precedent
# is safe only because git-data's volume is born fresh. Never point that guard at the
# live volume. This file's guard therefore never runs against `hcloud_volume.workspaces`.
#
# WHY ADDITIVE AND NOT BLUE-GREEN (the issue's preferred approach)
# ---------------------------------------------------------------
# Blue-green needs a new host. `cx33` is `available = false` in ALL THREE EU
# datacentres (live Hetzner API 2026-07-16; corroborated at
# tests/scripts/test-stock-preflight-gate.sh). A `-replace` of hcloud_server.web
# ["web-1"] would DESTROY the sole prod host and then fail to recreate it, leaving the
# platform unrebuildable. See ADR-118 §Alternatives Considered.

# --- Passphrase ---------------------------------------------------------------
# Minted by terraform, never operator-supplied (hr-tf-variable-no-operator-mint-default).
# `special = false` keeps it shell/stdin-safe for the `printf %s | cryptsetup
# --key-file -` pipe; 40 alphanumeric chars is ~238 bits.
#
# NO ignore_changes — rotation is operator-explicit via `-replace`, matching
# git-data-luks.tf:26-30 and live-verify.tf:30-31.
#
# ROTATION IS NOT A RE-KEY, AND THAT IS A TERMINAL HAZARD (C19).
# `terraform apply -replace=random_password.workspaces_luks` mints a new passphrase
# and updates Doppler, but DOES NOT re-key the existing LUKS header. Post-wipe of the
# plaintext backstop, that permanently strands every workspace. The cutover gate MUST
# assert `luks_passphrase_touched == 0` (precedent: git-data-host-replace-gate.sh).
# If rotation must ever be supported, it is `cryptsetup luksChangeKey`, NOT -replace.
resource "random_password" "workspaces_luks" {
  length  = 40
  special = false
}

# --- Key escrow ---------------------------------------------------------------
# DIVERGENCE FROM git-data, AND THE RATIONALE IS NOT git-data's.
#
# git-data isolates its key in a dedicated config for HOST blast-radius reduction.
# That argument does NOT port: web-1 already carries a full-prd DOPPLER_TOKEN, so
# there is no host blast radius left to buy. An attacker on web-1 reads the full-prd
# token and gets the key regardless.
#
# The real reason is a DIFFERENT boundary — host-vs-CONTAINER, not host-vs-host:
# cloud-init.yml runs `doppler secrets download --config prd > "$TMPENV"` and then
# `docker run --env-file "$TMPENV"`, so EVERY secret in the shared `prd` config is
# injected into the agent container's environment. A WORKSPACES_LUKS_KEY in `prd`
# would be readable via /proc/self/environ BY THE VERY AGENT CODE WHOSE DATA IT
# ENCRYPTS (CWE-522) — reducing the at-rest guarantee to zero against in-container
# compromise or prompt-injection exfiltration.
#
# The dedicated config is what keeps the key out of `--env-file`. Asserted by
# workspaces-luks.test.sh A7 (mutation: config == "prd" ⇒ RED).
#
# OPERATOR PRECONDITION: the `prd_workspaces_luks` config must exist in Doppler
# BEFORE `terraform apply` — the provider manages environments and configs as a unit
# and will not create a bare config. Same precondition as git-data-luks.tf:44-50.
resource "doppler_secret" "workspaces_luks_key" {
  project    = "soleur"
  config     = "prd_workspaces_luks"
  name       = "WORKSPACES_LUKS_KEY"
  value      = random_password.workspaces_luks.result
  visibility = "masked"
}

# Read-only boot token: the host resolves the passphrase at unlock time via this
# token, NOT via the full-prd token that feeds the container's --env-file.
resource "doppler_service_token" "workspaces_luks" {
  project = "soleur"
  config  = "prd_workspaces_luks"
  name    = "workspaces-luks-boot"
  access  = "read"
}

# --- The encrypted volume -----------------------------------------------------
# DELIBERATELY NO `format` ATTRIBUTE. This is the single most important line in the
# file — and it is a line that is NOT here.
#
# git-data-luks.tf sets `format = "ext4"` and its own comment admits the format is
# pointless (the guest's luksFormat overwrites the header region anyway). Copying it
# here would be actively harmful: `format = "ext4"` makes the fresh volume carry
# TYPE=ext4, BYTE-INDISTINGUISHABLE from the live plaintext volume. That destroys the
# only sound luksFormat guard — "format only a device with NO filesystem signature".
#
# With no `format`, the device is raw and the discriminator exists:
#
#   sig=$(blkid -o value -s TYPE "$DEV" 2>/dev/null || true)
#   case "$sig" in
#     "")          luksFormat ;;   # raw — the ONLY formattable state
#     crypto_LUKS) : ;;            # idempotent no-op
#     *) echo "FATAL: $DEV carries TYPE=$sig — refusing to format a populated device"; exit 1 ;;
#   esac
#
# "Safe by construction" is asserted; this is safe by ENGINEERING. The cutover script
# selects the device by volume ID from terraform output — NEVER by glob scan. The
# precedent scans for the device that IS LUKS; the inverse predicate matches the LIVE
# PLAINTEXT VOLUME. Asserted by workspaces-luks.test.sh A4 (mutation: appending a
# `format` line ⇒ RED — this is the issue's "a plaintext volume must go RED").
#
# SINGLETON, not `for_each = var.web_hosts` (C18). Three reasons:
#   1. A for_each'd attachment lands outside `web2_allow` in
#      destroy-guard-filter-web-platform.jq:96-100 and would PERMANENTLY BRICK the
#      web-2-recreate path.
#   2. `moved` wants a singleton source.
#   3. web-2 is slated for destruction (#6538), has never served user traffic
#      (app.soleur.ai is a hard-pinned singleton A record to web-1) and its volume is
#      empty. Encrypting a volume scheduled for deletion is waste.
#
# web-2's volume is therefore KNOWINGLY left plaintext — a recorded deviation from
# #6588's "every var.web_hosts member" AC, tracked by #6538. See ADR-118.
#
# Size and location track web-1's live volume exactly: `var.volume_size` is the same
# input `hcloud_volume.workspaces` uses, so the target can never be born smaller than
# the source, and the location must match the server for attachment to be legal.
resource "hcloud_volume" "workspaces_luks" {
  name     = "soleur-web-platform-data-luks"
  size     = var.volume_size
  location = var.web_hosts["web-1"].location

  labels = {
    app = "soleur-web-platform"
  }
}

# Attached ALONGSIDE the live plaintext volume — the additive design's two-copy state.
# The old volume keeps serving /mnt/data throughout Phases 3-4; this one receives the
# rsync. That two-copy state IS the verified-restorable backup (CPO C3), and it beats
# a Hetzner snapshot: it is a live, mountable device the cutover rehearses, not a blob
# nobody has ever restored — and it manufactures no indefinitely-retained plaintext
# copy, which is what made the snapshot wrong (CTO/COO).
#
# NOTE: with a second volume attached, the `scsi-0HC_Volume_*` glob in
# cloud-init.yml becomes AMBIGUOUS. Pinning the mount by volume ID is a hard
# prerequisite of the cutover — see ADR-118 §Sequencing.
resource "hcloud_volume_attachment" "workspaces_luks" {
  volume_id = hcloud_volume.workspaces_luks.id
  server_id = hcloud_server.web["web-1"].id
}
