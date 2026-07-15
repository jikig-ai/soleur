# Cloudflare Tunnel for webhook-based deploys + CI-runner SSH ingress.
# Routes the deploy webhook (#749) and the CI-runner SSH path (#4177)
# through the tunnel so runner egress doesn't need IP allowlisting.
# Operator/admin SSH still uses the direct A record + admin_ips firewall.

resource "random_id" "tunnel_secret" {
  byte_length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "web" {
  account_id = var.cf_account_id
  name       = "soleur-web-platform"
  config_src = "cloudflare"
  secret     = random_id.tunnel_secret.b64_std

  # The tunnel was created via API before Terraform state existed.
  # secret: original b64 value is irrecoverable.
  # config_src: forces replacement on import; the live tunnel already
  #   uses remote config, so ignoring is safe (#967).
  # TODO: remove ignore_changes after clean reprovisioning (import artifact)
  lifecycle {
    ignore_changes = [secret, config_src]
  }
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "web" {
  account_id = var.cf_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.web.id

  config {
    ingress_rule {
      hostname = "deploy.${var.app_domain_base}"
      service  = "http://localhost:9000"
    }
    # SSH ingress for CI runner — `terraform_data.*` provisioner resources
    # in server.tf reach the host through this tunnel after the runner
    # establishes a `cloudflared access tcp` localhost forward.
    # CF Tunnel ingress rules are first-match; this MUST stay above the
    # catch-all `http_status:404` rule below.
    ingress_rule {
      hostname = "ssh.${var.app_domain_base}"
      service  = "ssh://localhost:22"
    }
    # #6122 (ADR-096) — registry PUSH ingress. A web-host cloudflared connector proxies to
    # the private-net zot host, so the registry host needs NO cloudflared of its own. CI runs
    # `cloudflared access tcp --hostname registry.<base>` → this rule → tcp://10.0.1.30:5000
    # (zot). First-match; MUST stay above the 404.
    #
    # (#6416) This comment used to read "THE web host's cloudflared (already a 10.0.1.0/24
    # member)" — singular, and false. This is ONE tunnel with MULTIPLE connector replicas
    # (web-1 and web-2 both run cloudflared against it; `cloudflared tunnel info` showed 2
    # connectors / 8 QUIC conns), and Cloudflare load-balances across them. So this rule is
    # correct ONLY while EVERY connector host is a 10.0.1.0/24 member — that is ADR-113's
    # invariant I1 (connector homogeneity). web-2 had NO private-net attachment, so ~50% of
    # registry-bridge attempts landed on a connector with no route to 10.0.1.30 and failed.
    #
    # This rule is nonetheless the RIGHT pattern and the one to generalize: its service is
    # private-net-RELATIVE (10.0.1.30), so whichever replica answers proxies to the correct
    # origin. Contrast `ssh://localhost:22` below, which is connector-relative and therefore
    # host-NONdeterministic (ADR-113 I2).
    #
    # `tcp://`, NOT `http://` (#6122 cutover fix): `cloudflared access tcp` bridges a RAW TCP
    # stream over a WebSocket. With an `http://` service the origin cloudflared HTTP-proxies the
    # WS-upgrade to zot, which doesn't speak it → the client dies "websocket: bad handshake"
    # (the exact symptom the first live push runs hit). The sibling SSH bridge works precisely
    # because it uses a raw-TCP service type (`ssh://localhost:22`); `tcp://` is the generic
    # form for zot's plain-HTTP registry — crane/docker then speak HTTP over the raw forward
    # (127.0.0.1:5000 is auto-insecure to docker). The CF Access app + service-token policy are
    # unchanged (identical shape to the working ssh app); only the ingress transport was wrong.
    #
    # NOT STALE (#6357): this rule is the LIVE registry-push path — do NOT remove or repoint it.
    # #6288 moved the zot registry REGION nbg1→hel1 and recreated its store volume, but the origin
    # private IP `10.0.1.30:5000` is UNCHANGED (the 10.0.1.0/24 net spans hel1; zot-registry.tf
    # `registry_private_ip = "10.0.1.30"`). Removing this rule breaks CI registry push; repointing
    # is a no-op. A `dial tcp 10.0.1.30:5000: operation was canceled` here means the origin is
    # transiently DOWN (registry stability = #6288), NOT that the config is wrong.
    ingress_rule {
      hostname = "registry.${var.app_domain_base}"
      service  = "tcp://${local.registry_endpoint}"
      origin_request {
        # Fail-fast so a DOWN registry origin (#6288) doesn't pile up ~30s-held dials that
        # saturate the shared tunnel daemon's HA-stream budget and degrade the sibling
        # deploy-webhook route (the 2026-07-11 502; #6357). Mitigation, not cure — root cause is
        # registry stability (#6288); full deploy-tunnel decoupling + metrics are #6178.
        connect_timeout   = 5    # INTEGER seconds (NOT "5s") — bounds the TCP dial only
        no_happy_eyeballs = true # origin is a v4 literal → drop the v4/v6 parallel-dial fan-out
      }
    }
    # Catch-all rule (required by Cloudflare)
    ingress_rule {
      service = "http_status:404"
    }
  }
}

# Cloudflare Access: protect the deploy endpoint with a service token.
# GitHub Actions sends CF-Access-Client-Id and CF-Access-Client-Secret
# headers alongside the HMAC signature for defense in depth.

resource "cloudflare_zero_trust_access_application" "deploy" {
  zone_id          = var.cf_zone_id
  name             = "Deploy Webhook - soleur-web-platform"
  domain           = "deploy.${var.app_domain_base}"
  type             = "self_hosted"
  session_duration = "24h"
}

resource "cloudflare_zero_trust_access_service_token" "deploy" {
  account_id = var.cf_account_id
  name       = "github-actions-deploy"
}

resource "cloudflare_zero_trust_access_policy" "deploy_service_token" {
  zone_id        = var.cf_zone_id
  application_id = cloudflare_zero_trust_access_application.deploy.id
  name           = "Allow GitHub Actions deploy"
  decision       = "non_identity"
  precedence     = 1

  include {
    service_token = [cloudflare_zero_trust_access_service_token.deploy.id]
  }
}

# Cloudflare Access: protect the SSH ingress with a service token (#4177).
# GitHub Actions runs `cloudflared access tcp --hostname ssh.${app_domain_base}`
# carrying TUNNEL_SERVICE_TOKEN_ID + TUNNEL_SERVICE_TOKEN_SECRET. CF Access
# validates the headers and bridges the raw TCP forward into the tunnel,
# where the host-side cloudflared daemon delivers to localhost:22 (sshd).

resource "cloudflare_zero_trust_access_application" "ssh" {
  zone_id = var.cf_zone_id
  name    = "SSH (CI runner) - soleur-web-platform"
  domain  = "ssh.${var.app_domain_base}"
  type    = "self_hosted"
  # 15m is CF's documented minimum; tighter than the deploy app's 24h
  # because SSH grants host shell access (higher blast radius). A typical
  # apply-deploy-pipeline-fix run is ~3-5 min, so 15m leaves headroom
  # without prolonged token reuse if the cloudflared sidecar's in-memory
  # session token is exfiltrated mid-run.
  session_duration = "15m"
}

resource "cloudflare_zero_trust_access_service_token" "ci_ssh" {
  account_id = var.cf_account_id
  name       = "github-actions-ci-ssh"
}

resource "cloudflare_zero_trust_access_policy" "ci_ssh_service_token" {
  zone_id        = var.cf_zone_id
  application_id = cloudflare_zero_trust_access_application.ssh.id
  name           = "Allow GitHub Actions CI SSH"
  decision       = "non_identity"
  precedence     = 1

  include {
    service_token = [cloudflare_zero_trust_access_service_token.ci_ssh.id]
  }
}

# #6122 (ADR-096) — CF Access for the registry PUSH ingress (CTO ruling). A NEW dedicated
# service token (NOT reused from ci_ssh/deploy) so registry-write access rotates/revokes
# independently of host-shell + webhook access, with its own session duration. Push-time auth
# is BOTH gates: this CF Access service token (network/edge) + the zot-push htpasswd (registry).
# All operator-applied (rides the registry host's full apply), like the rest of the #6122 stack.
resource "cloudflare_zero_trust_access_application" "registry" {
  zone_id = var.cf_zone_id
  name    = "Registry Push (CI) - soleur-web-platform"
  domain  = "registry.${var.app_domain_base}"
  type    = "self_hosted"
  # 15m — same as the ssh app (registry write is a comparable blast radius: it can
  # overwrite platform image tags). A release build's push is well under 15m.
  session_duration = "15m"
}

resource "cloudflare_zero_trust_access_service_token" "registry_push" {
  account_id = var.cf_account_id
  name       = "github-actions-registry-push"
}

resource "cloudflare_zero_trust_access_policy" "registry_push_service_token" {
  zone_id        = var.cf_zone_id
  application_id = cloudflare_zero_trust_access_application.registry.id
  name           = "Allow GitHub Actions registry push"
  decision       = "non_identity"
  precedence     = 1

  include {
    service_token = [cloudflare_zero_trust_access_service_token.registry_push.id]
  }
}

# Publish the registry-push CF Access token to Doppler `prd` (the ROOT config) so the Phase-2
# push workflow reads it at runtime via `doppler secrets get` — NOT a github_actions_secret
# (CTO load-bearing condition #2; avoids the #5566 class).
#
# CONFIG = `prd` (root), NOT `prd_terraform` (#6122 cutover fix): the reusable-release.yml zot
# bridge (`secrets.DOPPLER_TOKEN`) is scoped to the `prd` ROOT config — the SAME config the
# bridge's docker-login step reads ZOT_PUSH_* from (zot-registry.tf writes those to `prd`). It
# CANNOT read the `prd_terraform` BRANCH config (which holds the R2/AWS/Cloudflare terraform
# creds CI must not see — least privilege). A Doppler service token reads exactly ONE config and
# ignores DOPPLER_CONFIG, and branch-local values do NOT propagate to the root; so a token
# written into the `prd_terraform` branch was invisible to the release token and the bridge
# failed "REGISTRY_PUSH_ACCESS_TOKEN_ID/_SECRET missing or empty". Writing to the `prd` root
# fixes it AND keeps every branch working: branch configs (prd_terraform, prd_ghcr, …) INHERIT
# root values. The earlier `like CI_SSH_ACCESS_TOKEN` analogy was the trap — CI_SSH runs under a
# prd_terraform-capable workflow token; the release workflow does not.
#
# WRITE-ONCE (ignore_changes=[value]): cloudflare_zero_trust_access_service_token.client_secret
# is populated ONLY at create and reads EMPTY on subsequent `terraform refresh` (#4492→#4494
# learning). Because this stack is OPERATOR-applied (no CI post-apply output-sync step like
# ci_ssh has), TF writes Doppler directly on the operator's full apply; ignore_changes prevents
# a later refresh from clobbering the live Doppler value with the empty state read. client_id is
# stable, but ignore_changes on both keeps the write-once semantics symmetric. Rotate via
# `terraform apply -replace=cloudflare_zero_trust_access_service_token.registry_push` (which
# re-creates the token → new client_secret → this re-writes Doppler on that apply).
resource "doppler_secret" "registry_push_access_token_id" {
  project    = "soleur"
  config     = "prd"
  name       = "REGISTRY_PUSH_ACCESS_TOKEN_ID"
  value      = cloudflare_zero_trust_access_service_token.registry_push.client_id
  visibility = "masked"
  lifecycle {
    ignore_changes = [value]
  }
}

resource "doppler_secret" "registry_push_access_token_secret" {
  project    = "soleur"
  config     = "prd"
  name       = "REGISTRY_PUSH_ACCESS_TOKEN_SECRET"
  value      = cloudflare_zero_trust_access_service_token.registry_push.client_secret
  visibility = "masked"
  lifecycle {
    ignore_changes = [value]
  }
}

# Alert one week before any CF Access service token expires.
# Cloudflare sends expiring_service_token_alert 7 days pre-expiry.
# Note: this alert fires for ALL service tokens in the account (no per-token
# filtering). Three tokens exist: `github-actions-deploy` (webhook),
# `github-actions-ci-ssh` (CI runner SSH bridge, #4177), and
# `github-actions-registry-push` (CI registry push, #6122); the alert body
# names the specific token.
resource "cloudflare_notification_policy" "service_token_expiry" {
  account_id  = var.cf_account_id
  name        = "CF Access service token expiring"
  description = "Alert when any CF Access service token (github-actions-deploy, github-actions-ci-ssh, or github-actions-registry-push) approaches expiry"
  alert_type  = "expiring_service_token_alert"
  enabled     = true

  email_integration {
    id = var.cf_notification_email
  }
}

output "tunnel_token" {
  value     = cloudflare_zero_trust_tunnel_cloudflared.web.tunnel_token
  sensitive = true
}

output "access_service_token_client_id" {
  value     = cloudflare_zero_trust_access_service_token.deploy.client_id
  sensitive = true
}

output "access_service_token_client_secret" {
  value     = cloudflare_zero_trust_access_service_token.deploy.client_secret
  sensitive = true
}

output "ci_ssh_access_service_token_client_id" {
  value     = cloudflare_zero_trust_access_service_token.ci_ssh.client_id
  sensitive = true
}

output "ci_ssh_access_service_token_client_secret" {
  value     = cloudflare_zero_trust_access_service_token.ci_ssh.client_secret
  sensitive = true
}
