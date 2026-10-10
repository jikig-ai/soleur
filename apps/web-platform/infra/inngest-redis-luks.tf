# ============================================================================
# LUKS apparatus for the dedicated inngest host's Redis AOF volume (#7695).
#
# ONE FILE, DELIBERATELY. `scripts/lint-encryption-posture.py` resolves a ledger
# row's citation STRUCTURALLY, not by name similarity: it requires a co-located
# `random_password` + `doppler_secret` pair alongside the apparatus they key. A
# split across two files fails that resolution even when both halves exist, so
# do not "tidy" these into the sibling files their names suggest.
#
# WHAT THIS FILE DOES NOT DO. It creates a passphrase and escrows it. It does
# NOT recut anything and is inert with respect to the running host until a boot
# reads the key. (The
# reviewer-gated `apply_target=inngest-volume-recut` that this paragraph used to
# name is gone (#8285 PR A converted that job into `inngest-backstop-retire`,
# which retired the plaintext backstop `hcloud_volume.inngest_redis`, id
# 106261946; that volume was destroyed 2026-10-09 and the job deleted by PR B).
# ADR-142's additive byte-copy is how the store moved onto `hcloud_volume.inngest_redis_luks`.)
#
# SOLE COPY (#9879). The plaintext backstop is gone, so the volume below and the
# passphrase pair that opens it are the ONLY copy of the Inngest queue and run
# state. They carry delete protection at Hetzner and `prevent_destroy` in
# Terraform; the attachment deliberately does NOT (it is replaced by the sanctioned
# `inngest-host-replace`). Why, the loss-mode table, the deliberate two-step unprotect
# and the read-back recipe: the runbook section "Sole-copy protection and key loss" in
# knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md and the
# ADR it links. inngest-luks-sole-copy.test.sh pins every line of this.
#
# "MERGE IS INERT" IS THE DEFECT HERE, NOT THE SAFETY PROPERTY. Both resources
# below MUST be in the per-merge `-target=` allowlist in
# .github/workflows/apply-web-platform-infra.yml. The passphrase has to EXIST
# before any host boots that reads it: a host replaced ahead of the secret
# reaches its LUKS stage, finds INNGEST_REDIS_LUKS_KEY empty, and — correctly —
# refuses to mount rather than falling back to plaintext. That is a dark host,
# on a fleet whose only scheduler is elsewhere and whose diagnosis is a Better
# Stack read. Ordering is the safety property; inertness is not.
# ============================================================================

# length 40 / special = false — mirrors random_password.workspaces_luks and
# random_password.git_data_luks. `special = false` is not cosmetic: the value is
# piped to `cryptsetup --key-file -` through a `doppler run` environment, and a
# shell-metacharacter-free alphabet removes a whole class of quoting defect from
# a path where a mistake is unrecoverable (a wrong passphrase on a formatted
# volume is indistinguishable from a lost one).
#
# NO `lifecycle { ignore_changes = ... }`, deliberately. A regenerated passphrase
# must cascade — a drifted key that Terraform declines to notice is a volume
# nobody can open, discovered at the next boot rather than at plan time.
#
# SOLE OPENER (#9879): `prevent_destroy` on this pair makes a destroy or replace plan an
# error. A deliberate key rotation (a header `luksChangeKey`) needs it lifted on the pair
# in the same reviewed change; see the runbook section named in the file header.
resource "random_password" "inngest_redis_luks" {
  length  = 40
  special = false

  lifecycle {
    prevent_destroy = true
  }
}

# --- Key escrow -------------------------------------------------------------
# The isolated `soleur-inngest` project, NOT `soleur`. This is the SAME boundary
# the host's own token already draws (doppler_service_token.inngest, #6178): the
# inngest project has no inheritance path to `soleur/prd`, so a compromise of
# either side does not hand over the other's secret set.
#
# Do NOT "simplify" this to `soleur/prd` to match the web host's pattern. The web
# host runs `doppler secrets download --config prd` and injects the whole config
# into the agent container's environment (the boundary workspaces-luks.tf
# documents at length). This host does not, and the isolation is the reason its
# apparatus can key off the root `prd` config at all.
# ── WHY THIS PAIR IS PER-MERGE `-target`ed, UNLIKE ITS THREE SIBLINGS ────────
# random_password.workspaces_luks, random_password.registry_luks and
# random_password.git_data_luks are all OPERATOR_APPLIED_EXCLUSIONS: each rides
# the gated dispatch that PROVISIONS its volume, so mint-at-dispatch is right for
# them — the key and the volume it opens are created by one apply.
#
# This volume already EXISTS. A recut would be a `-replace` of it (the dispatch
# that did that, `inngest-volume-recut`, was retired by #8285 PR A), and the LUKS cut
# happens on the host's NEXT BOOT via cloud-init's blkid discriminator — a
# different apply from the one that mints the key, and possibly a different day.
# A host replaced before the key is minted reaches the LUKS stage, finds
# INNGEST_REDIS_LUKS_KEY empty, and FATALs. So the pair is in the per-merge
# `-target=` allowlist in .github/workflows/apply-web-platform-infra.yml: "the
# merge is inert" is the defect on this path, not the safety property.
#
# THE ADMISSION MUST LAND IN THE SAME COMMIT. The boot isolation self-check on
# soleur-inngest/prd is EXACT-SET (`n_total -ne n_inngest` → FATAL), so a new name
# in that project boot-bricks the host on its next re-provision unless
# cloud-init-inngest.yml's admitting regex knows it. It does, as of #7695, and
# inngest-host.test.sh replays the predicate behaviourally over a name set
# including INNGEST_REDIS_LUKS_KEY. Ordering within the merge is safe: this apply
# creates the secret, hcloud_server.inngest is NOT per-merge targeted, so the
# running host does not re-provision — the check re-runs only on the next
# dispatched replace, which boots the cloud-init that already admits the name.
resource "doppler_secret" "inngest_redis_luks_key" {
  project    = doppler_project.inngest.name
  config     = doppler_environment.inngest_prd.slug
  name       = "INNGEST_REDIS_LUKS_KEY"
  value      = random_password.inngest_redis_luks.result
  visibility = "masked"

  # Sole opener of the sole copy (#9879); see the note on random_password above.
  lifecycle {
    prevent_destroy = true
  }
}

# ═══════════════════════════════════════════════════════════════════════════════
# THE ADR-142 ADDITIVE TARGET VOLUME (#6894)
# ═══════════════════════════════════════════════════════════════════════════════
#
# WHY A SECOND VOLUME RATHER THAN A RECUT OF THE FIRST. `apply_target=inngest-
# volume-recut` (retired by #8285 PR A) was the CHEAP path, and it was unusable here — not as a
# matter of preference but because two records forbid it in conjunction:
#
#   ADR-199  permits the destroy ONLY on a measured-empty store (G13: redis_keys == 0,
#            "redis_keys > 0 routes to ADR-142, with no override").
#   ADR-142  states this store can never BE empty: "armed future reminders sit in the
#            AOF at arbitrary future fire-times ... Draining to empty would mean
#            waiting until the last armed reminder fires — unbounded."
#
# MEASURED 2026-09-17 under all three pins (host=soleur-inngest, host_role=dedicated,
# probe_schema=8): redis_keys=442, redis_expires=431, of which ?estate?:key:*=431 is
# exactly the armed-reminder set ADR-142 names. So G13 refuses, and it refuses
# permanently rather than transiently. The recut was not a path that was merely
# blocked; it was a path this volume never had.
#
# HISTORY (the design this volume was created under, ADR-142): it was INERT AT MERGE
# — created, attached alongside the then-live plaintext volume, and mounted at a
# STAGING path, never at /mnt/data — and nothing copied data here until the
# reviewer-gated cutover ran. The two-copy state was the verified-restorable backup.
# THAT STATE ENDED 2026-10-09 (#8285): the cutover completed, the plaintext volume
# was destroyed, and this volume is now the SOLE copy of the Inngest store.
#
# NO `format` ATTRIBUTE, AND THAT IS LOAD-BEARING — the same reasoning the retired recut
# apparatus recorded for the plaintext volume. The device must be born RAW so
# `blkid -o value -s TYPE` is a sound discriminator: "" means empty and may be
# luksFormatted, `crypto_LUKS` means already cut, anything else is a signature we
# refuse to destroy. Declaring `format = "ext4"` would make the guard's empty arm
# unreachable and the first boot would mount a plaintext ext4 filesystem at the
# staging path — the precise outcome this volume exists to avoid. The precedents
# omit it for this reason (hcloud_volume.workspaces_luks, and the `ignore_changes` note
# that sat on the plaintext `hcloud_volume.inngest_redis` before #8285 PR A removed its
# declaration).
#
# SIZE TRACKS THE SOURCE EXACTLY. `var.inngest_redis_volume_size` is the same input
# the plaintext volume `hcloud_volume.inngest_redis` used (that declaration was removed
# by #8285 PR A), so the target was never born smaller than the volume whose bytes it
# had to hold. `location` must match the server's for the
# attachment to be legal.
#
# SOLE COPY, PINNED TWICE (#9879). Hetzner refuses a delete while delete protection is on, and
# `prevent_destroy` makes any Terraform plan that would destroy or replace this volume an error. They
# cover different edges (a console or API delete versus a plan), so neither replaces the other.
# Protection defends against mistaken deletes; it does not defend against a holder of the read/write
# Hetzner token, which can lift it.
#
# ORDERING TRAP when lifting deliberately: lift delete protection first, in its own reviewed change,
# let it apply, and only then remove `prevent_destroy`. Removing `prevent_destroy` alone lets a destroy
# apply detach the mounted volume before Hetzner refuses the delete. The runbook section named in the
# file header carries the two-step route; this comment spells neither attribute literally so the
# guard suite can pin each as exactly one code line.
resource "hcloud_volume" "inngest_redis_luks" {
  name              = "soleur-inngest-redis-store-luks"
  size              = var.inngest_redis_volume_size
  location          = var.location
  delete_protection = true

  labels = {
    app = "soleur-web-platform"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# This attachment is the live one: the store is served from this volume, and it is the only copy
# (the plaintext volume it was copied from was destroyed 2026-10-09, #8285). It was created ALONGSIDE
# that volume by the additive cutover design (the byte-copy under a clean-stop freeze, then the swap).
#
# THE `-target=` SETS ARE NOT THE SAME SET. Both this volume and this attachment
# join `inngest-host`. Only the ATTACHMENT joins `inngest-host-replace`, because
# that dispatch preserves the durable AOF by OMISSION — its target set names the
# server, its network attachment and this attachment, and deliberately not any
# VOLUME. Adding a volume there would break the invariant the workflow states in
# those words. The attachment must be there, though: inngest-host-replace-gate.sh
# interpolates the server id, so a replace forces this attachment into the plan and
# the gate aborts `out_of_scope` without it.
#
# NO `prevent_destroy` HERE, DELIBERATELY (#9879). Unlike web-1's attachment, this one is replaced by a
# sanctioned dispatch: `inngest-host-replace` replaces the server and therefore this attachment
# (ForceNew on server_id), and a pin would turn that into a plan error. Its protection is the existing
# gate rows (replace only together with the server, shape gate no-op or create only) and the
# reachability pins in plugins/soleur/test/terraform-target-parity.test.ts. The guard suite pins the
# ABSENCE of a lifecycle block here, so adding one is a red row and not a quiet breakage of host replace.
resource "hcloud_volume_attachment" "inngest_redis_luks" {
  volume_id = hcloud_volume.inngest_redis_luks.id
  server_id = hcloud_server.inngest.id
}
