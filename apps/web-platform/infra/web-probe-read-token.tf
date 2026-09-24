# --- #6438/#6548: dedicated read-scoped Doppler token for the web-1 private-net probe units ---
# The three web-host private-net probe systemd units (web-zot-consumer-probe, web-git-data-probe,
# web-private-nic-guard) run `doppler run --project soleur --config prd -- …` as ROOT to inject
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
# adds no new secret exposure on web-1 — it is the least-privilege source for the probe units
# specifically). NO github_actions_secret publication: the value is consumed only by the in-repo
# *_install SSH provisioners, never by a workflow.
#
# State storage: `.key` is Computed + write-once + Sensitive (same handling as
# doppler_service_token.registry). NO lifecycle.ignore_changes.
#
# ROTATION (#8705) is a change to `name` (ForceNew in DopplerHQ/doppler v1.21.2), merged with
# `[ack-destroy]`; the shared mechanics are workspaces-luks.tf's ROTATION comment. What differs here:
#   - create_before_destroy gives TOKEN-level failure atomicity only. The main apply finishes the
#     replace, delete included, before the SSH stage re-fires the FOUR web-1 installers (server.tf
#     private_nic_guard / zot_consumer_probe / inngest_consumer_probe / git_data_probe _install, each
#     hashing .key in triggers_replace). web-1 holds a dead token for ~35 s, longer if that stage fails.
#   - Fresh hosts keep a dead copy (hcloud_server.web ignore_changes = [user_data]): re-seed each one
#     with the web-host-replace dispatch once the merge apply is green (runbooks/web-host-replace.md).
#   - No same-name replace: without create_before_destroy it deletes first, and with it Doppler must
#     accept two same-named tokens, which nobody has probed.
# Rotated 2026-09-24 from web-probes-read (created 2026-07-18; retained web-1 snapshot 411798619 holds it, #8705).
# Verify: bash apps/web-platform/infra/scripts/web-probes-token-rotation-verify.sh (prints ROTATED).
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
