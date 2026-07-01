# proxy-tls.tf — one-way TLS material for the host↔host session-router proxy
# (epic #5274 Phase 3, ADR-068 amendment 2026-07-01 "TLS + credential + D2").
#
# Under user-sticky routing (ADR-068 amendment), a session that lands on a
# non-owning web host is proxied to the owning host over the private net. That
# channel carries user content (assistant output / tool results / file content), so
# it needs encryption-in-transit (NFR-026 / CLO NFR-026). The plan chose ONE-WAY
# TLS — a server cert each host presents, the proxying client pins our self-signed
# cert as its trust anchor (rejectUnauthorized:true, NEVER false — MITM). Mutual /
# client certs are dropped as over-built for 2 hosts we own (DHH/simplicity).
#
# Design: a SINGLE long-lived self-signed server cert whose SANs cover every web
# host's private IP, shared by all hosts as their TLS server identity + pinned by
# the proxying client as its CA. A shared key is acceptable — the hosts are equally
# trusted, owned nodes (the same proportionality bar that downgraded mTLS), and a
# shared cert avoids per-host Doppler selection that web-1's frozen cloud-init
# (ignore_changes=[user_data]) cannot deliver anyway (the cert reaches the running
# container via Doppler `prd`, like the git-data keys). Long-lived (10y) ⇒ NO
# rotation cron; the consumer logs notAfter at startup + a single Better Stack
# cert-expiry monitor covers it (see Observability). "Contract before consumer":
# this material ships in 3.A so the proxy server/client in 3.B can load it.

resource "tls_private_key" "proxy_server" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P256"
}

resource "tls_self_signed_cert" "proxy_server" {
  private_key_pem = tls_private_key.proxy_server.private_key_pem

  subject {
    common_name  = "soleur-web-proxy"
    organization = "Soleur"
  }

  # SANs: every web host's private IP (the proxy dials the owner by private IP) +
  # the for_each keys as DNS names + localhost (same-host loopback serve path).
  ip_addresses = [for h in values(var.web_hosts) : h.private_ip]
  dns_names    = concat(keys(var.web_hosts), ["localhost"])

  # 10 years — long-lived by design (no rotation cron; ADR-068 amendment).
  validity_period_hours = 87600
  early_renewal_hours   = 720

  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "server_auth",
  ]
}

# Private key → Doppler `prd` (RUNTIME secret; same rationale + config as the
# git-data keys in git-data.tf — baked into the container env at start, NOT
# cloud-init, since the web host carries ignore_changes=[user_data]). Consumed by
# the 3.B session-router's TLS server (https.createServer / WebSocketServer
# noServer).
resource "doppler_secret" "proxy_tls_key" {
  project    = "soleur"
  config     = "prd"
  name       = "PROXY_TLS_KEY"
  value      = tls_private_key.proxy_server.private_key_pem
  visibility = "masked"
}

# Cert (public material, but Doppler-delivered for parity so the app loads both
# from one source). Serves double duty: the TLS server's cert AND the proxying
# client's pinned trust anchor (`ca: [PROXY_TLS_CERT]`, rejectUnauthorized:true).
resource "doppler_secret" "proxy_tls_cert" {
  project    = "soleur"
  config     = "prd"
  name       = "PROXY_TLS_CERT"
  value      = tls_self_signed_cert.proxy_server.cert_pem
  visibility = "masked"
}
