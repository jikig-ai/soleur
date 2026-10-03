# apps/web-platform/infra/workspaces-luks-fresh-boot.tf
#
# #6931 (ADR-143 R3 / ADR-263) — the credentials of the guest-side fresh-boot LUKS path for web hosts:
# the fresh-host read token delivered in user_data, and the soak-marker config + its write token +
# the GitHub secret carrying that token to the daily verify workflow. #9377 moves the fresh-host read
# token onto its OWN web-class config (prd_workspaces_luks_web, below) so a fresh host's token no longer
# resolves web-1's escrow credential pair.
#
# SEPARATE FILE by design, the workspaces-luks-header.tf precedent: workspaces-luks.test.sh A11 asserts
# FILE-SCOPED exact cardinality over workspaces-luks.tf (one doppler_secret / one doppler_service_token /
# one random_password / one hcloud_volume, and `config = "prd"` nowhere), so a second
# doppler_service_token declared there turns A11 RED. This file carries its own pins in
# workspaces-luks-fresh-boot.test.sh.
#
# NO new TF_VAR_* and no operator-minted default (hr-tf-variable-no-operator-mint-default): every value
# below is an in-graph resource attribute.
#
# autonomy-considered: provider-mint-applied (Doppler config + service tokens + GitHub repo secret via
# the TF App), the doppler_token_web_arm / doppler_token_inngest_arm shape.

# --- The web-class config (#9377) ---------------------------------------------------------------
# A web host born through the fresh-boot path reads its passphrase and its own header-escrow pair from
# THIS config, not from prd_workspaces_luks (web-1's config, which also holds web-1's R2 pair). The
# contents are Terraform-managed in workspaces-luks-header-web.tf (key, bucket name, endpoint); the bucket-scoped
# R2 access pair is the deferred mint and is written into this config separately.
#
# A branch config of `prd` like every other in this repo, so it inherits the same ~116 `prd` secrets
# (ADR-164 census, measured): the split narrows WHICH R2 credential a holder of the web-class token
# reaches, it does not isolate the token from the inherited root. The contract check
# (scripts/check-web-host-escrow-config.sh --live) asserts web-1's R2 pair names are absent from the `prd`
# root, so this branch cannot inherit them.
#
# Deliberately NOT in doppler-config-inventory.txt, for the reason the marker config below is not: that file
# is the token-drift scan's reach and floor (ADR-164/168), adding a name mints a read token for it and forces
# floor edits. Whoever adds it owns the floor edits listed there.
resource "doppler_config" "workspaces_luks_web" {
  project     = "soleur"
  environment = "prd"
  name        = "prd_workspaces_luks_web"
}

# --- The fresh-host read token (D4, #9377) --------------------------------------------------------
# A web host born through the fresh-boot path (hcloud_server.web[*], user_data) reads the LUKS
# passphrase at first boot with `doppler secrets get WORKSPACES_LUKS_KEY --plain --config
# prd_workspaces_luks_web`, using THIS token. It is written to /etc/default/luks-monitor (DOPPLER_TOKEN=,
# 0600 root) by the runcmd that already writes that file's DSN line; it is a templatefile() variable
# of server.tf's user_data map.
#
# WHY NOT THE EXISTING doppler_service_token.workspaces_luks (workspaces-luks.tf). That token is
# published as WORKSPACES_LUKS_BOOT_TOKEN and ROTATED by a create_before_destroy procedure whose
# installer (terraform_data.luks_monitor_token_install) reaches web-1 ONLY. Sharing it would put web-2's
# credential on a rotation that never visits web-2: the old token is destroyed under it, web-2's next
# reboot fails luksOpen, `RequiresMountsFor` holds docker, and the host goes dark with no console and
# no SSH route. This token is therefore NEVER co-rotated, and its rotation IS a host replacement
# (a runbook line plus a test that pins the ABSENCE of create_before_destroy below).
#
# NO create_before_destroy, and the absence is load-bearing, not an omission: with it, a rename-driven
# replace would mint the successor first and delete the predecessor in the SAME apply, i.e. exactly the
# silent co-rotation this token exists to avoid. Without it, a replace is destroy-then-create, which is
# visible to the destroy guard (`[ack-destroy]`) and cannot happen inside an apply that leaves a host
# holding a dead token without a human having acknowledged it.
#
# SCOPE, stated once and truthfully (the workspaces-luks.tf paragraph, repeated rather than
# paraphrased): like every prd_* branch-config token in this repo, this one resolves ~116 `prd` secrets
# (ADR-164 census, measured). "Dedicated config" isolates the passphrase from the CONTAINER env file, NOT
# from a holder of this token. The full-prd `doppler_token` is already in the same user_data map, so the
# marginal exposure is the LUKS passphrase and the web-class escrow credentials. Because the SAME
# WORKSPACES_LUKS_KEY unlocks web-2 and web-1's sole-copy volume, a leak from web-2 is a leak of web-1's
# passphrase (ADR-263 records the shared-passphrase residual; it also constrains any future
# luksChangeKey on web-1). What the split removes is web-1's R2 escrow pair from this token's reach.
#
# The ONLY permitted read is `doppler secrets get WORKSPACES_LUKS_KEY --plain --config
# prd_workspaces_luks_web`. Never `doppler run` or `secrets download` on that config (CWE-522: inheritance
# drags the whole root in). Nothing in this file can see host-side code, so nothing here pins it.
resource "doppler_service_token" "workspaces_luks_fresh_boot_web" {
  project = "soleur"
  config  = doppler_config.workspaces_luks_web.name
  name    = "workspaces-luks-fresh-boot-web-2026-10-02"
  access  = "read"
}

# --- The PRE-SPLIT fresh-host token: LEFT IN PLACE, unused (#9377) ---------------------------------
# Until #9377 this was the token user_data carried, scoped to prd_workspaces_luks (web-1's config).
# server.tf now points at doppler_service_token.workspaces_luks_fresh_boot_web, and this resource is
# NOT edited: every user-set attribute of a doppler_service_token is ForceNew in the pinned provider, so
# re-pointing its `config` is a destroy-and-create, which the push-apply destroy guard (destroy_count over
# every resource) halts without [ack-destroy]. A NEW resource keeps the merge apply purely additive.
#
# Inferred at the time of the split (from birth dates and ignore_changes=[user_data]; no command reads a host): no live
# host holds this token (hcloud_server.web ignores user_data, so web-1 and the existing web-2 never received it) but it still exists in Doppler and still reads
# web-1's pair, so the P4 residual is "narrowed on merge for every NEW birth, closed when this token is
# retired". Retiring it is a LATER, acknowledged destroy ([ack-destroy]) once nothing references it; that
# is listed in the #9377 follow-up comment (confirm it is DESTROYED, not merely unreferenced) and recorded in the ADR-263 amendment. Do not add create_before_destroy here
# either (workspaces-luks-fresh-boot.test.sh F2 pins both tokens).
resource "doppler_service_token" "workspaces_luks_fresh_boot" {
  project = "soleur"
  config  = "prd_workspaces_luks"
  name    = "workspaces-luks-fresh-boot-2026-10-01"
  access  = "read"
}

# --- The soak marker's dedicated config (D5, DC-5) ---------------------------------------------
# WORKSPACES_LUKS_CUTOVER_AT is written by the daily workspaces-luks-verify.yml web-2 leg and read by
# the (future) flip orchestrator through lb-weight-gate.sh. It lives in its OWN branch config rather
# than shared `prd` because Doppler tokens are scoped per CONFIG: a write token on `prd` could overwrite
# any prd secret, and the git-data stamp precedent (GIT_DATA_LUKS_CUTOVER_AT in `prd`) is only
# tolerable because its caller is an environment-gated dispatch, while this writer is a daily cron with
# no human gate. The provider has no `doppler_branch_config`; in DopplerHQ/doppler a branch config is a
# `doppler_config` whose name carries the environment prefix (the doppler_config.git_data_prd shape,
# git-data-luks.tf).
#
# The config is created EMPTY and stays empty until the first green verify run: absent key == "not
# soaked" == the gate fails closed, so creating it grants nothing.
#
# It is deliberately NOT in doppler-config-inventory.txt: that file is the token-drift scan's reach and
# floor (ADR-164/168), adding a name mints a read token for it, and prd_git_data (also TF-declared and
# also absent from the inventory) is the precedent. Whoever adds it owns the floor edits listed there.
resource "doppler_config" "workspaces_luks_marker" {
  project     = "soleur"
  environment = "prd"
  name        = "prd_workspaces_luks_marker"
}

# --- The marker's write token (D5) ---------------------------------------------------------------
# `read/write` on the ONE marker config. A write to a branch config sets that branch's own value, so
# this token cannot modify any `prd` root secret; the verify leg is the only writer (a census in
# workspaces-luks-verify-workflow.test.sh fails on a second workflow or script that writes or deletes
# the key). It also reads the config, which inherits `prd` like every branch config above: the same
# scope statement applies, and it is not described as least privilege on the read side.
#
# Rotation: a change to `name` replaces it (every user-set attribute is ForceNew in the pinned
# provider); the replace propagates the new key into the GitHub secret below in the same apply.
resource "doppler_service_token" "workspaces_luks_marker_write" {
  project = doppler_config.workspaces_luks_marker.project
  config  = doppler_config.workspaces_luks_marker.name
  name    = "workspaces-luks-marker-write"
  access  = "read/write"
}

# The write token as a REPO-level github_actions_secret (the TF GitHub App cannot write ENVIRONMENT
# secrets; see github_actions_secret.doppler_token_inngest_arm for the 403 precedent). Readable by
# every workflow on main, like DOPPLER_TOKEN_WRITE: the writer's custody is "this repo's main branch".
# The marker VALUE is advisory/shape-only (lb-weight-gate checks its shape; sourcing it from evidence is
# #9358): a present marker is kept while the daily probe is GREEN and removed on a non-GREEN run, so it is
# NOT re-validated each run. NO lifecycle.ignore_changes: a -replace of the token propagates here in the
# same apply.
#
# CONSUMERS (keep current): .github/workflows/workspaces-luks-verify.yml (the web-2 leg, writer) and
# .github/workflows/scheduled-followthrough-sweeper.yml (READ only, for scripts/followthroughs/
# web2-luks-live-6931.sh, which reads the marker's age through the Doppler API).
resource "github_actions_secret" "doppler_token_workspaces_luks_marker" {
  repository      = "soleur"
  secret_name     = "DOPPLER_TOKEN_WORKSPACES_LUKS_MARKER"
  plaintext_value = doppler_service_token.workspaces_luks_marker_write.key
}
