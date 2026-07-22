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
# doppler_service_token.registry). Rotate via `terraform apply -replace=doppler_service_token
# .web_probes` — NO lifecycle.ignore_changes, so a rotation propagates the new key into each
# /etc/default/web-<probe> file in the same apply (the installers hash .key into triggers_replace).
#
# autonomy-considered: provider-mint-applied (Doppler service token via the TF Doppler provider; no
# operator mint, no operator-set var — hr-tf-variable-no-operator-mint-default).
resource "doppler_service_token" "web_probes" {
  project = "soleur"
  config  = "prd"
  name    = "web-probes-read" # read-only; the web-1 private-net probe units' doppler-run auth
  access  = "read"
}
