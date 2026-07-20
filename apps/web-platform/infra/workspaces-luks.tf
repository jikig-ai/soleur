# =============================================================================
# LUKS-at-rest for the LIVE /workspaces volume (#6588, ADR-119)
# =============================================================================
#
# WHAT THIS CLOSES
# ----------------
# `hcloud_volume.workspaces` (server.tf) holds every user's checked-out source code
# as plaintext ext4, while docs/legal/{privacy-policy,gdpr-policy,data-protection-
# disclosure}.md tell data subjects it is LUKS-encrypted. The operator's decision is
# to make the claim true rather than retract it. This file declares the ADDITIVE
# encrypted volume that ADR-119 cuts over to.
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
# platform unrebuildable. See ADR-119 §Alternatives Considered.

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
# THE MECHANISM IS INHERITANCE DIRECTIONALITY, AND IT IS THE ONLY THING LOAD-BEARING.
# Doppler resolves root → branch: a secret written to the `prd_workspaces_luks` BRANCH
# does not appear in a `--config prd` download. That asymmetry — and nothing else — is
# what keeps the key out of `--env-file`.
#
# ⚠️ THIS IS NOT LEAST PRIVILEGE, AND SAYING SO WOULD BE FALSE.
# The inverse does NOT hold: a branch config INHERITS the full root secret set, so
# `doppler_service_token.workspaces_luks` below resolves ~116 `prd` secrets including
# SUPABASE_SERVICE_ROLE_KEY. It is materially a full-prd token. The repo established
# this empirically and is tracking it:
#   knowledge-base/project/learnings/security-issues/
#     2026-07-07-doppler-branch-config-does-not-isolate-secrets.md  (severity: high)
#   #6122 fixed zot by moving to a SEPARATE PROJECT; #6167 audits the rest — including
#   `prd_git_data`, the precedent this file mirrors.
# It costs nothing on web-1 (which already carries a full-prd DOPPLER_TOKEN at
# cloud-init.yml:409, so there is no host blast radius left to buy), which is why the
# CWE-522 container boundary still genuinely holds. True isolation would be a separate
# Doppler project — that is #6167's scope, not this PR's.
#
# Asserted by workspaces-luks.test.sh A7 (relocation ⇒ RED) AND A11 (ADDITION of any
# resource writing to `config = "prd"` ⇒ RED). A7 alone was addition-blind: a SECOND
# doppler_secret writing this key to shared `prd`, unmasked, passed 20/20 green.
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

# The host resolves the passphrase at unlock time via this token. `access = "read"`
# is real (it cannot WRITE secrets) — but it is NOT a narrower READ scope than the
# host's existing full-prd token: branch configs inherit the root, so this token reads
# all ~116 prd secrets too (see the escrow comment above, #6167). Do not describe it
# as least-privilege.
#
# ⚠️ #6604 (the cutover) MUST read it with `doppler secrets get WORKSPACES_LUKS_KEY
# --plain --config prd_workspaces_luks`. The natural-looking alternatives are exactly
# the CWE-522 hole this file exists to close, because inheritance drags the root in:
#   `doppler run --config prd_workspaces_luks -- …`      → injects all ~116 + the key
#   `doppler secrets download --config prd_workspaces_luks` → same, into a file
# Neither this .tf nor its guard can see host-side code, so nothing here pins it.
resource "doppler_service_token" "workspaces_luks" {
  project = "soleur"
  config  = "prd_workspaces_luks"
  name    = "workspaces-luks-boot"
  access  = "read"
}

# #6649 — publish the boot token to a repo-level GitHub Actions secret so the cutover/verify
# workflows can deliver it host-side (the ONLY credential that reads prd_workspaces_luks; web-1's
# baked DOPPLER_TOKEN is prd-root-scoped and cannot). Mirrors github_actions_secret.doppler_token_inngest_arm
# (inngest-arm-write-token.tf) exactly: a repo secret, no lifecycle.ignore_changes — a `-replace`
# rotation of the token propagates the new key here in the same apply.
#
# This reclassifies the token from operator-applied-host-token to CI-PUBLISHED token, so
# apply-web-platform-infra.yml's DEFAULT allow-list explicitly targets BOTH this resource AND
# doppler_service_token.workspaces_luks, and terraform-target-parity.test.ts REMOVES the token from
# OPERATOR_APPLIED_TOKEN_EXCLUSIONS (the #5566 "a token feeding a github_actions_secret MUST be
# targeted, never excluded" rule). It rides the DEFAULT apply, NOT the scoped
# apply_target=workspaces-luks-cutover job (whose gate asserts EXACTLY the five volume/attachment/
# passphrase/secret/token creates and would abort on a sixth resource).
resource "github_actions_secret" "workspaces_luks_boot_token" {
  repository      = "soleur"
  secret_name     = "WORKSPACES_LUKS_BOOT_TOKEN"
  plaintext_value = doppler_service_token.workspaces_luks.key
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
# #6588's "every var.web_hosts member" AC, tracked by #6538. See ADR-119.
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
# prerequisite of the cutover — see ADR-119 §Sequencing.
resource "hcloud_volume_attachment" "workspaces_luks" {
  volume_id = hcloud_volume.workspaces_luks.id
  server_id = hcloud_server.web["web-1"].id
}

# GitHub Environment with a required-reviewer protection rule — the SOLE human
# authorization on the irreversible /workspaces LUKS freeze (C19 / AC20b; DP-11 F8).
# The cutover job in .github/workflows/workspaces-luks-cutover.yml declares
# `environment: ${{ !inputs.dry_run && 'workspaces-luks-cutover' || '' }}` (#6649), so the
# REAL freeze arm (`dry_run=false`) is held in "Waiting" for reviewer approval BEFORE any
# step executes — that approval IS the human ack — while a reversible `dry_run=true` rehearsal
# resolves to an empty (ungated) environment and runs unattended (autonomy). The expression is
# fail-closed: the same `!inputs.dry_run` operand gates the freeze, so any freeze-reachable run
# is gated. A zero-reviewer environment auto-approves, so reviewers.users MUST stay non-empty for
# the freeze arm. reviewers.users takes numeric GitHub user IDs — 54279 = @deruelle (the
# operator/founder). Mirrors github_repository_environment.inngest_cutover (inngest-arm-write-token.tf).
#
# Provisioned by the DEFAULT allow-list apply (apply-web-platform-infra.yml push /
# apply_target=manual-rerun), NOT the scoped apply_target=workspaces-luks-cutover job:
# that job's sourced workspaces_luks_cutover_gate asserts the plan is EXACTLY the five
# volume/attachment/passphrase/secret/token creates, so a sixth create there aborts it.
resource "github_repository_environment" "workspaces_luks_cutover" {
  repository  = "soleur"
  environment = "workspaces-luks-cutover"

  reviewers {
    users = [54279]
  }
}
