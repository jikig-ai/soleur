#!/usr/bin/env bash
#
# Drift guard for the dedicated Inngest singleton host (#6178, ADR-100). Asserts the
# load-bearing security/correctness invariants of inngest-host.tf + cloud-init-inngest.yml:
#   - FRESH signing/event keys (AC-KEYROTATE) — NOT reused from the co-located inngest.tf.
#   - Secrets on a SEPARATE Doppler PROJECT `soleur-inngest` (AC3), not a `prd` branch config.
#   - hcloud_firewall.inngest is deny-all-public (zero inbound); nftables (not the cloud
#     firewall) scopes :8288/:8289 to web-host IPs only, dropping git-data/.20 + registry/.30.
#   - NO lifecycle.ignore_changes=[user_data] (maintenance-window force-replace, ADR-100).
#   - arm64 inngest-CLI SHA override (the amd64 image-env SHA would fail the arm64 verify).
#   - Vector WIRED on this arm64 host (arm64 build + isolated-project token, #6197).
#
# Run: bash apps/web-platform/infra/inngest-host.test.sh
# Registered in .github/workflows/infra-validation.yml.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST_TF="${DIR}/inngest-host.tf"
CLOUD_INIT="${DIR}/cloud-init-inngest.yml"
INNGEST_TF="${DIR}/inngest.tf"
VECTOR_TF="${DIR}/vector.tf"
BOOTSTRAP="${DIR}/inngest-bootstrap.sh"

passes=0
fails=0
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); echo "FAIL: $1" >&2; }

for f in "$HOST_TF" "$CLOUD_INIT" "$INNGEST_TF" "$VECTOR_TF" "$BOOTSTRAP"; do
  [ -f "$f" ] || { echo "FAIL: required file not found: $f" >&2; exit 1; }
done

# 1. FRESH keys (AC-KEYROTATE) — the dedicated resources exist AND are distinct from the
#    co-located inngest.tf keys. A reuse would sign the new boundary with the old key (SEC-H3).
grep -qE 'resource "random_id" "inngest_signing_key_dedicated"' "$HOST_TF" \
  && grep -qE 'resource "random_id" "inngest_event_key_dedicated"' "$HOST_TF" \
  && grep -qE 'resource "random_password" "inngest_redis_password_dedicated"' "$HOST_TF" \
  && pass || fail "fresh dedicated signing/event/redis key resources present"
# The dedicated signing secret must reference the DEDICATED key, never the co-located _prd one.
# Strip COMMENT lines first — the header comments reference the co-located key BY NAME as the
# thing NOT reused (a bare grep would false-match that prose).
if grep -qE 'random_id\.inngest_signing_key_dedicated\.hex' "$HOST_TF" \
   && ! grep -vE '^[[:space:]]*#' "$HOST_TF" | grep -qE 'random_id\.inngest_(signing|event)_key_prd'; then
  pass
else
  fail "dedicated secrets reference the dedicated keys, not the co-located _prd keys"
fi

# 2. Separate Doppler PROJECT (AC3), not a prd branch config.
grep -qE 'resource "doppler_project" "inngest"' "$HOST_TF" \
  && grep -qE 'name[[:space:]]*=[[:space:]]*"soleur-inngest"' "$HOST_TF" \
  && pass || fail "separate soleur-inngest Doppler project declared"
# Every dedicated doppler_secret targets that project (never a `config = "prd_inngest"` branch).
if grep -qE 'config[[:space:]]*=[[:space:]]*"prd_inngest"' "$HOST_TF"; then
  fail "dedicated secrets must NOT use a prd_inngest branch config (non-isolating, #6122)"
else
  pass
fi

# 3. Deny-all-public firewall (zero inbound rules) — intra-subnet is open by membership;
#    signature-verify is the /api/inngest boundary; nftables scopes the control API.
if awk '/resource "hcloud_firewall" "inngest"/{f=1} f&&/^}/{f=0} f' "$HOST_TF" | grep -qE 'rule[[:space:]]*\{|direction[[:space:]]*=[[:space:]]*"in"'; then
  fail "hcloud_firewall.inngest must have ZERO inbound rules (deny-all-public)"
else
  pass
fi

# 4. NO lifecycle.ignore_changes=[user_data]. Strip COMMENT lines first — the block carries a
#    "Deliberately NO ...ignore_changes=[user_data]" prose comment a bare grep would false-match.
if grep -vE '^[[:space:]]*#' "$HOST_TF" | grep -qE 'ignore_changes[[:space:]]*=[[:space:]]*\[[^]]*user_data'; then
  fail "hcloud_server.inngest must NOT set ignore_changes=[user_data] (ADR-100 force-replace)"
else
  pass
fi

# 5. arm64 inngest-CLI SHA: a distinct arm64 checksum local is declared AND the cloud-init
#    OVERRIDES the (amd64) image-env SHA with it before running the bootstrap.
grep -qE 'inngest_cli_sha256_arm64[[:space:]]*=[[:space:]]*"[0-9a-f]{64}"' "$INNGEST_TF" \
  && grep -qF 'INNGEST_CLI_SHA256="${inngest_cli_sha256_arm64}"' "$CLOUD_INIT" \
  && grep -qF 'INNGEST_CLI_ARCH=${inngest_cli_arch}' "$CLOUD_INIT" \
  && pass || fail "arm64 inngest-CLI SHA declared + overrides the image-env amd64 SHA in cloud-init"

# 6. nftables scopes :8288/:8289 to web-host IPs only. The allowlist is the TF constant
#    local.web_host_private_ips (host.tf), rendered into the nft saddr set via ${web_host_private_ips}.
#    git-data(.20)/registry(.30) are absent from that local → dropped by the default policy.
grep -qE 'web_host_private_ips[[:space:]]*=[[:space:]]*"10\.0\.1\.10,10\.0\.1\.11"' "$HOST_TF" \
  && grep -qF 'ip saddr { ${web_host_private_ips} } accept' "$CLOUD_INIT" \
  && pass || fail "nftables saddr set is the web-host allowlist (.10/.11) via local.web_host_private_ips"
# The web-host allowlist local must NOT contain git-data(.20)/registry(.30).
if grep -qE 'web_host_private_ips[[:space:]]*=' "$HOST_TF" && grep -E 'web_host_private_ips[[:space:]]*=' "$HOST_TF" | grep -qE '10\.0\.1\.(20|30)'; then
  fail "web_host_private_ips must NOT include git-data(.20)/registry(.30)"
else
  pass
fi

# 7. Vector WIRED on this arm64 host (#6197): a distinct arm64 SHA local is declared, the
#    cloud-init OVERRIDES VECTOR_CLI_SHA256 with it, passes VECTOR_CLI_ARCH=arm64, and stages
#    /tmp/vector.toml so the bootstrap writes the vector.service unit.
grep -qE 'vector_sha256_arm64[[:space:]]*=[[:space:]]*"[0-9a-f]{64}"' "$VECTOR_TF" \
  && grep -qF 'VECTOR_CLI_SHA256=${vector_sha256_arm64}' "$CLOUD_INIT" \
  && grep -qF 'VECTOR_CLI_ARCH=arm64' "$CLOUD_INIT" \
  && grep -qF ':/vector.toml /tmp/vector.toml' "$CLOUD_INIT" \
  && pass || fail "Vector wired (arm64) — SHA local + cloud-init SHA override + VECTOR_CLI_ARCH=arm64 + /tmp/vector.toml staged"
# The DEFERRED empty VECTOR_CLI_* form must be GONE (would skip the install).
if grep -qE 'VECTOR_CLI_VERSION=""|"VECTOR_CLI_VERSION="' "$CLOUD_INIT"; then
  fail "Vector must no longer be deferred (empty VECTOR_CLI_* form is gone)"
else
  pass
fi
# The templatefile must pass vector_sha256_arm64 into the cloud-init render.
grep -qF 'vector_sha256_arm64 = local.vector_sha256_arm64' "$HOST_TF" \
  && pass || fail "inngest-host.tf templatefile passes vector_sha256_arm64 = local.vector_sha256_arm64"

# 8. inngest-bootstrap.sh arch-parameterizes the Vector install (#6197): VECTOR_CLI_ARCH
#    defaults amd64 (web host preserved) + an arm64->aarch64 triple map applied to BOTH the
#    download URL AND the extract path. No residual UNCONDITIONAL x86_64 literal in either.
grep -qE 'VECTOR_CLI_ARCH="\$\{VECTOR_CLI_ARCH:-amd64\}"' "$BOOTSTRAP" \
  && grep -qF 'aarch64-unknown-linux-musl' "$BOOTSTRAP" \
  && grep -qF '${vec_triple}.tar.gz' "$BOOTSTRAP" \
  && grep -qF 'vector-${vec_triple}/bin/vector' "$BOOTSTRAP" \
  && pass || fail "inngest-bootstrap.sh arch-parameterizes Vector (VECTOR_CLI_ARCH + aarch64 triple for URL + extract)"
# The URL/extract must NOT still hardcode vector-x86_64-unknown-linux-musl.
if grep -qF 'vector-x86_64-unknown-linux-musl' "$BOOTSTRAP"; then
  fail "inngest-bootstrap.sh must not hardcode vector-x86_64-unknown-linux-musl (URL/extract derive from \${vec_triple})"
else
  pass
fi

# 9. Boot isolation self-check admits BETTERSTACK_LOGS_TOKEN as a TOP-LEVEL alternation
#    member (#6197). A NESTED member would match INNGEST_BETTERSTACK_LOGS_TOKEN and fail to
#    match a bare BETTERSTACK_LOGS_TOKEN → boot-brick. The HEARTBEAT_URL)|BETTERSTACK anchor
#    proves the token is a sibling of the INNGEST_ group, not inside it. Floor rose 4->5.
grep -qF 'HEARTBEAT_URL)|BETTERSTACK_LOGS_TOKEN)' "$CLOUD_INIT" \
  && grep -qF '"$n_inngest" -lt 5' "$CLOUD_INIT" \
  && pass || fail "isolation self-check admits BETTERSTACK_LOGS_TOKEN (top-level) and the floor is -lt 5"
# The old floor must be gone.
if grep -qF '"$n_inngest" -lt 4' "$CLOUD_INIT"; then
  fail "isolation floor must be -lt 5, not the old -lt 4"
else
  pass
fi

echo ""
echo "=== inngest-host.test.sh: ${passes} passed, ${fails} failed ==="
[ "$fails" -eq 0 ] || exit 1
