# TLS for the web -> Inngest scheduler link (#10136, ADR-292 provisional ordinal).
#
# The dedicated Inngest host (10.0.1.40) serves its control API and the event/registry endpoints on
# :8288 in cleartext. `inngest start` v1.45.1 has no TLS flag (measured, plan Phase 0), so a stunnel4
# terminator on the host listens on 10.0.1.40:8443 and forwards to 127.0.0.1:8288 (cloud-init-inngest.yml).
# This file owns the key material and its three Doppler copies. The listener, the host-side fetch, the
# web-side CA file and the flag resolver are other files; none of them is wired to anything here by a
# Terraform edge.
#
# ONE SELF-SIGNED LEAF, THE WEB CLIENT'S TRUST ANCHOR (precedent: proxy-tls.tf, ADR-068 amendment).
# The web container pins this exact certificate through NODE_EXTRA_CA_CERTS and verifies with
# rejectUnauthorized left at its default (NODE_TLS_REJECT_UNAUTHORIZED stays absent everywhere; the
# docker-run tuple gate pins that). The certificate is therefore deliberately NOT a CA
# (`is_ca_certificate = false`, basicConstraints CA:FALSE): a leaf signed with this key must not
# validate, so a leaked key can impersonate THIS endpoint only, never mint certificates for another.
# The only SAN is the private IP (no DNS name exists for the host). The web-side resolver does NOT
# re-check the SAN or purpose: the host-side `curl --cacert` self-gate and the canary's CA-withheld
# negative control prove the pinned file against the real listener (ADR-292).
#
# FOUR PROPERTIES THAT ARE EASY TO "FIX" AND MUST NOT BE:
#   1. NOT count-gated, unlike proxy-tls.tf. ADR-118 gated that quartet because the proxy SERVER logged
#      a silent fallback on mere presence of the secrets. Nothing reads these until the host is
#      replaced and the flag resolver is armed, so an always-present trio is inert (the plan's
#      inert/active matrix). The FLAG at the bottom IS count-gated: absent means http.
#   2. NO `early_renewal_hours`. Inside that window the provider plans a REPLACE of the certificate,
#      `prevent_destroy` blocks it, and every later per-merge apply then fails. Expiry is watched by the
#      90-day `notafter_days` alert on the host's tls-health series instead (10-year validity, rotation is
#      out of scope and documented in the runbook).
#   3. `prevent_destroy` on key AND cert. Replacing either regenerates the keypair, which changes the
#      CA the web hosts pinned and the cert the host serves at once; that is a coordinated flip, not an
#      apply side effect. (The host replace gate also aborts if either appears in a replace plan:
#      tests/scripts/test-inngest-host-replace-gate.sh rows T1-T5.)
#   4. NOTHING IN inngest-host.tf MAY REFERENCE THESE ADDRESSES. A templatefile variable that read
#      `tls_*` or `doppler_secret.inngest_tls_*` would put the cert in hcloud_server.inngest's user_data,
#      so a cert change would force-replace the sole scheduler and the addresses would join the
#      inngest-host-replace closure. The host fetches the key and cert from Doppler at runtime with its
#      own service token. Pinned by plugins/soleur/test/terraform-target-parity.test.ts.
#
# CREATED BY THE PER-MERGE APPLY. The five addresses below are in the merge `-target` list of
# apply-web-platform-infra.yml (key and cert together, as ADR-118 notes). No `hcloud_server` is in their
# dependency closure (doppler_project.inngest and doppler_environment.inngest_prd only), so the merge
# apply creates names and values without replacing the Inngest host; the closure is asserted statically
# in terraform-target-parity.test.ts.
#
# THE SECRETS ARE MASKED and Terraform owns the value (no `ignore_changes`), the same shape as the
# sibling inngest_*_dedicated secrets. The private key is in terraform.tfstate (R2 state bucket, same
# custody as every other generated key in this root) and in Doppler soleur-inngest/prd; the host process
# that terminates TLS reads it once into a tmpfs RuntimeDirectory (cloud-init-inngest.yml).
#
# INNGEST_TLS_CA IS BASE64. The PEM is multi-line and would otherwise reach the web container through
# the docker env-file format; ci-deploy.sh decodes it and, only when the flag resolves https, validates it
# (size, no PRIVATE KEY block, exactly one CERTIFICATE, parses, not expired, not a CA) and installs it at
# /mnt/data/inngest-link/inngest-ca.pem after the self-gate passes. It lives in `soleur`/`prd` (the web container's config), the key and cert
# in `soleur-inngest`/`prd` (the host's isolated project); literal "soleur"/"prd" as in proxy-tls.tf.

resource "tls_private_key" "inngest_link" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"

  lifecycle {
    prevent_destroy = true
  }
}

resource "tls_self_signed_cert" "inngest_link" {
  private_key_pem = tls_private_key.inngest_link.private_key_pem

  subject {
    common_name  = "soleur-inngest-link"
    organization = "Soleur"
  }

  # The only SAN: the scheduler's private IP, the address the web hosts dial. No DNS names.
  ip_addresses = [local.inngest_private_ip]

  # 10 years: long-lived by design (no rotation cron; the 90-day alert is the warning).
  validity_period_hours = 87600

  # Explicit: the leaf is the trust anchor and must not be able to issue.
  is_ca_certificate = false

  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "server_auth",
  ]

  lifecycle {
    prevent_destroy = true
  }
}

# Private key -> the host's isolated Doppler project (read by soleur-inngest-tls.service's ExecStartPre).
resource "doppler_secret" "inngest_tls_key" {
  project    = doppler_project.inngest.name
  config     = doppler_environment.inngest_prd.slug
  name       = "INNGEST_TLS_KEY"
  value      = tls_private_key.inngest_link.private_key_pem
  visibility = "masked"
}

# Certificate -> the host's isolated Doppler project (served by stunnel; compared with the web CA).
resource "doppler_secret" "inngest_tls_cert" {
  project    = doppler_project.inngest.name
  config     = doppler_environment.inngest_prd.slug
  name       = "INNGEST_TLS_CERT"
  value      = tls_self_signed_cert.inngest_link.cert_pem
  visibility = "masked"
}

# The same certificate, base64, in the web container's config: the pinned CA (see the header).
resource "doppler_secret" "inngest_tls_ca" {
  project    = "soleur"
  config     = "prd"
  name       = "INNGEST_TLS_CA"
  value      = base64encode(tls_self_signed_cert.inngest_link.cert_pem)
  visibility = "masked"
}

# ── The link flag (INNGEST_LINK_TLS) ─────────────────────────────────────────────────────────────────
# An unset flag is a secret that does not exist; ci-deploy.sh reads a missing key as authoritative
# absence and keeps the legacy http URL. Values (allowlist in resolve_inngest_link):
#   (absent)        http://10.0.1.40:8288
#   pending:<epoch> https only while now <= epoch + 30 min (a lease; a lapse resolves to http plus an event)
#   1               https, fail-closed: a failed self-gate, a CA read error or an invalid CA fails the deploy
#
# SOURCE OF TRUTH: the Tier-B `inngest_link_flag` job of apply-web-platform-infra.yml (apply_target=inngest-link-flag,
# environment infra-privileged), driven by .github/workflows/inngest-link-flip.yml, passes the requested value as
# TF_VAR_inngest_link_tls in the environment of its terraform plan (empty for `off`), set AFTER `doppler run` injected
# its own variables, and applies only this resource. It writes and deletes NO Doppler key. That is deliberate:
# prd_terraform is a Doppler BRANCH config that INHERITS prd, and this resource writes the secret into prd, so the value
# a prd_terraform key delete would have "removed" reappears by inheritance and the plan would carry no delete.
# This resource is DELIBERATELY OUT of the per-merge `-target` list (CTO G1): a merge must never flip the production
# URL, and a prd-write credential is not minted for this. It is classified in OPERATOR_APPLIED_EXCLUSIONS and stripped
# from the per-merge view in terraform-target-parity.test.ts, with a row asserting the flip job is its only targeting site.
#
# A full untargeted plan (the drift detector, infra-validation) sees the resource consistently WITHOUT the job's override:
# `doppler run -c prd_terraform --name-transformer tf-var` resolves INNGEST_LINK_TLS through prd_terraform's inheritance of
# prd, which holds exactly the secret this resource manages, so var.inngest_link_tls equals state (both empty while the
# secret does not exist). The one way to break that is a hand-made INNGEST_LINK_TLS override KEY IN prd_terraform: it would
# shadow prd and make every untargeted plan propose a change. None is created by this repo. The variable's validation
# rejects any value outside the resolver's allowlist before a plan can carry it; the resolver re-checks, since the value
# is read from Doppler on the host.
resource "doppler_secret" "inngest_link_tls" {
  count = var.inngest_link_tls == "" ? 0 : 1

  project    = "soleur"
  config     = "prd"
  name       = "INNGEST_LINK_TLS"
  value      = var.inngest_link_tls
  visibility = "unmasked"
}
