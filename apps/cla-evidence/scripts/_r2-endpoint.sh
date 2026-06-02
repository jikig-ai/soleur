# shellcheck shell=bash
# _r2-endpoint.sh — canonical R2 endpoint hostname pin (issue #3950 item 1).
# Sourced (NEVER executed) by every script that consumes R2_CLA_EVIDENCE_ENDPOINT:
#   - apps/cla-evidence/scripts/gdpr-override.sh
#   - apps/cla-evidence/scripts/inspect-evidence.sh
#   - apps/cla-evidence/scripts/r2-conditional-put.sh  (covers upload-{evidence,bypass})
#   - apps/cla-evidence/infra/bootstrap.sh
#
# Why: R2_CLA_EVIDENCE_ENDPOINT is operator/Doppler-supplied. Without a shape
# check, a compromised shell or mis-sourced `.envrc` could redirect the DELETE /
# tombstone-PUT / probe-PUT to an attacker-owned sink — the GDPR override path
# would silently no-op (object stays live under WORM, fake-success tombstone),
# and the bearer/HMAC creds would be sent to that sink. Pinning the host to the
# canonical `https://<32-lowercase-hex-account>.r2.cloudflarestorage.com` shape
# fails closed (exit 64) before any network call.

# assert_r2_endpoint <url>
#   Exits 64 with a GitHub-Actions ::error:: annotation if <url> is not a
#   canonical R2 S3 endpoint. No-op (returns 0) on a match. A trailing slash is
#   tolerated (some callers store the endpoint with one).
assert_r2_endpoint() {
  [[ "$1" =~ ^https://[a-f0-9]{32}\.r2\.cloudflarestorage\.com/?$ ]] || {
    echo "::error::R2_CLA_EVIDENCE_ENDPOINT does not match canonical R2 hostname (https://<32-hex>.r2.cloudflarestorage.com)" >&2
    exit 64
  }
}
