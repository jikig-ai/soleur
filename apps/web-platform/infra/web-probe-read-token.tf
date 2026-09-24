# --- #6438/#6548: dedicated read-scoped Doppler token for the web-host private-net probe units ---
# The four web-host private-net probe systemd units (web-zot-consumer-probe, web-git-data-probe,
# web-private-nic-guard, inngest-consumer-probe) run `doppler run --project soleur --config prd -- …` as ROOT to inject
# their per-host heartbeat URL + credentials. They FAILED TO START on web-1 because their systemd
# env carried no DOPPLER_TOKEN (and web-1 has no /etc/default/inngest-server — web_colocate_inngest
# defaults false — so there was no *suitable* root-doppler token source for the probe units: web-1
# DOES carry a full-prd DOPPLER_TOKEN via the deploy-owned /etc/default/webhook-deploy, but that file
# also imports DOPPLER_CONFIG_DIR=/tmp/.doppler — the #6536 clash surface — so it must not be sourced
# here). This mints a dedicated credential for that auth, delivered into each unit's own
# /etc/default/web-<probe> file (server.tf *_install provisioners).
#
# WHY A DEDICATED READ TOKEN (fleet least-privilege convention; mirrors doppler_service_token
# .registry / .git_data / .inngest, all read-scoped boot tokens): the probes need ONLY to READ
# soleur/prd secrets, so this is `access = "read"` — NOT the full-prd var.doppler_token, and NOT the
# deploy-owned /etc/default/webhook-deploy token (which also imports DOPPLER_CONFIG_DIR=/tmp/.doppler,
# re-opening the #6536 ownership-clash surface). With Environment=HOME=/root on the units and a
# token-only env value (no DOPPLER_CONFIG_DIR), doppler uses /root/.doppler and never touches
# /tmp/.doppler.
#
# BLAST RADIUS: a Doppler service token is CONFIG-scoped, so this reads the whole soleur/prd config
# (the probes' host already carries a full-prd DOPPLER_TOKEN via /etc/default/webhook-deploy, so this
# adds no new exposure to ROOT ON THE LIVE HOST — it is the least-privilege source for the probe
# units specifically). It DOES add a live credential to every copy of the host's disk (a snapshot
# image, a rescue mount): that is why #8705 rotated it. NO github_actions_secret publication: the
# value is consumed only by the four in-repo *_install SSH provisioners (web-1) and by
# hcloud_server.web's user_data templatefile at host creation (fresh hosts), never by a workflow.
#
# State storage: `.key` is Computed + write-once + Sensitive (same handling as
# doppler_service_token.registry). NO lifecycle.ignore_changes.
#
# ROTATION (#8705) is a change to `name` (ForceNew in DopplerHQ/doppler v1.21.2), merged with
# `[ack-destroy]`; the shared mechanics are workspaces-luks.tf's ROTATION comment. What differs here:
#   - create_before_destroy gives TOKEN-level failure atomicity only. The main apply finishes the
#     replace, delete included, before the post-bridge SSH stage re-fires the FOUR web-1 installers
#     (terraform_data.private_nic_guard_install, terraform_data.zot_consumer_probe_install,
#     terraform_data.inngest_consumer_probe_install, terraform_data.git_data_probe_install — each
#     hashes .key in triggers_replace). web-1 holds a dead token until that stage completes (~35 s in
#     run 36005279546, 2026-09-24), and until a green `manual-rerun` dispatch if the main apply or
#     that stage fails.
#   - If the old token's delete fails, it stays in state as a deposed object: the verifier reads
#     STALE, and the next push apply HALTs on the unacked delete until a merge commit carries
#     [ack-destroy] (a dispatch cannot carry it).
#   - apply-deploy-pipeline-fix.yml reaches this token transitively (through hcloud_server.web) and
#     refuses any non-terraform_data delete, so it can never perform the rotation itself.
#   - Fresh hosts keep a dead copy (hcloud_server.web ignore_changes = [user_data]): re-seed each one
#     with the web-host-replace dispatch once the merge apply is green (runbooks/web-host-replace.md).
#   - No same-name replace: without create_before_destroy it deletes first, and with it Doppler must
#     accept two same-named tokens, which nobody has probed.
#   - Reverting a rename is NOT a rollback: it mints a third token (needs [ack-destroy] again, and
#     re-fires the installers). To roll forward, rename again with a new date suffix.
# Rotated 2026-09-24 from web-probes-read (created 2026-07-18; retained web-1 snapshot 411798619 very
# likely holds it, #8705).
# Verify: bash apps/web-platform/infra/scripts/web-probes-token-rotation-verify.sh (prints ROTATED; a
# Doppler-side verdict only — host delivery is the SSH stage's run log and the probe heartbeats).
# Pinned by apps/web-platform/infra/web-probes-token-rotation.test.sh.
#
# autonomy-considered: provider-mint-applied (Doppler service token via the TF Doppler provider; no
# operator mint, no operator-set var — hr-tf-variable-no-operator-mint-default).
resource "doppler_service_token" "web_probes" {
  project = "soleur"
  config  = "prd"
  name    = "web-probes-read-2026-09-24" # read-only; the web-host private-net probe units' doppler-run auth
  access  = "read"

  lifecycle {
    create_before_destroy = true
  }
}
