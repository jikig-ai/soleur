# proxy-hello-hmac.tf — the signing key for the host↔host session-router relay's hello message
# (#12289, epic #8211 / #12167; ADR-118 owns the proxy-TLS count-gate pattern this file copies).
#
# The relay's TLS channel (proxy-tls.tf) authenticates the SERVER and, with the pre-handshake
# allowlist (#12288), the peer's address. It does not authenticate the CALLER: any process on the
# private net that completes the handshake can send a hello naming another user's session. The next
# PR ("A") makes the hello an HMAC-SHA256 over the user id, workspace id, timestamp and nonce, keyed
# with THIS secret, and the receiving host fails closed on a missing or invalid MAC. This file only
# mints the secret, so it exists in Doppler `prd` before any build that reads it deploys (a merge
# touching apps/web-platform/** starts the release; containers read Doppler only at start).
#
# One shared key for both hosts: they are equally trusted, owned nodes (the same proportionality
# bar as the shared TLS cert in proxy-tls.tf). `prd` only: the relay does not run in dev, and the
# next PR's tests use synthesized fixtures (cq-test-fixtures-synthesized-only).
#
# Generator: random_bytes, NOT random_password (CTO ruling 6). random_password has no hex output;
# random_bytes.hex is the 64 lowercase hex characters of 32 CSPRNG bytes, is marked Sensitive by the
# provider (locked at hashicorp/random 3.9.0: `hex` sensitive, and the type has no `id` attribute, so
# the plan log and the `Refreshing state... [id=...]` line print no key material), and flows only into
# the masked doppler_secret below. This file declares no output on purpose.
#
# COUNT-GATED ON var.host_proxy_tls_enabled, exactly like proxy_tls_key, so every reference is [0] and
# both resources ride the per-merge saved plan in apply-web-platform-infra.yml together. The gate also
# couples this key's lifecycle to the TLS flag on purpose: setting host_proxy_tls_enabled false
# destroys this pair, and setting it true again mints a DIFFERENT key, which a fail-closed hello would
# turn into a relay outage. A later count-to-for_each or rename refactor needs a moved {} block: for the
# random_bytes it REPLACES the key, and for the doppler_secret (Doppler keys a secret by NAME) the orphan
# address's destroy deletes PROXY_HELLO_HMAC_KEY from prd while the new address upserts it, in an undefined
# order, so a later full-root plan can leave the secret absent. The -target lists hide the orphan until then.
#
# NO auto-rotation, and no replace or taint of random_bytes.proxy_hello_hmac: each host reads the secret at
# container start, so a one-step change splits web-1 and web-2 across keys for the length of the rolling
# redeploy (CTO ruling 6). The verifier now also accepts a verify-only slot, PROXY_HELLO_HMAC_KEY_ACCEPT_ALSO
# (never signed with, absent by default, NOT minted here), so a routine rotation is three phases, each one
# Doppler change plus one rolling restart (ADR-323 Decision 9). A -replace here is rejected: it writes the new
# key into the same Tier-A-readable state. No phase can run until #12538 moves this key out of Terraform.

resource "random_bytes" "proxy_hello_hmac" {
  count = var.host_proxy_tls_enabled ? 1 : 0

  length = 32
}

resource "doppler_secret" "proxy_hello_hmac_key" {
  count = var.host_proxy_tls_enabled ? 1 : 0

  project    = "soleur"
  config     = "prd"
  name       = "PROXY_HELLO_HMAC_KEY"
  value      = random_bytes.proxy_hello_hmac[0].hex
  visibility = "masked"
}
