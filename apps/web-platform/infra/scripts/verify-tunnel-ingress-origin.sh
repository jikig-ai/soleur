#!/usr/bin/env bash
# Post-apply verification that the CF Tunnel ingress origins are live and
# origin-relative. Invoked by apply-web-platform-infra.yml after `terraform apply`.
#
# See that workflow's step comment for WHY this exists. In short: `terraform apply` of
# a Cloudflare tunnel config always succeeds — CF never checks the origin is
# reachable — so before this script a wrong pin applied GREEN and silently took out
# the management plane (#6594 / ADR-114 I2).
#
# Extracted to a script rather than inline YAML so the adjudication is readable and
# testable, per the same rationale as the infra-config gate extraction.
#
# NO ssh (hr-no-ssh-fallback-in-runbooks): every check is an HTTPS read.

set -euo pipefail

INFRA_DIR="${INFRA_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$INFRA_DIR"

DOPPLER_ARGS=(--project soleur --config prd_terraform)

# --- Expected origin: canonical source, never a hardcoded 10.0.1.10 -----------------
WEB1_IP=$(doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform console <<<'var.web_hosts["web-1"].private_ip' 2>/dev/null \
  | tr -d '"' | tr -d '[:space:]')
if [[ ! "$WEB1_IP" =~ ^10\.0\.1\.[0-9]{1,3}$ ]]; then
  echo "::error::could not resolve var.web_hosts[\"web-1\"].private_ip via terraform console (got '${WEB1_IP}'). Refusing to verify against an unknown origin — a blind check is worse than none."
  exit 1
fi

CF_API_TOKEN=$(doppler secrets get CF_API_TOKEN "${DOPPLER_ARGS[@]}" --plain 2>/dev/null || true)
CF_ACCOUNT_ID=$(doppler secrets get CF_ACCOUNT_ID "${DOPPLER_ARGS[@]}" --plain 2>/dev/null || true)
[[ -n "$CF_API_TOKEN" ]] && echo "::add-mask::$CF_API_TOKEN"
if [[ -z "$CF_API_TOKEN" || -z "$CF_ACCOUNT_ID" ]]; then
  # Fail CLOSED. A missing credential means the check did not run; treating that as a
  # pass is how a gate certifies silence.
  echo "::error::doppler read failed for CF_API_TOKEN/CF_ACCOUNT_ID — the ingress verification could NOT run. This is a gate failure, not a skip."
  exit 1
fi

TUNNEL_ID=$(terraform state show cloudflare_zero_trust_tunnel_cloudflared.web 2>/dev/null \
  | awk '/^[[:space:]]*id[[:space:]]*=/ { gsub(/"/, "", $3); print $3; exit }')
if [[ ! "$TUNNEL_ID" =~ ^[0-9a-fA-F-]{36}$ ]]; then
  echo "::error::could not resolve the tunnel id from terraform state (got '${TUNNEL_ID}')."
  exit 1
fi

# --- (a) Config plane: authoritative, vantage-free read-back ------------------------
CFG=$(curl -sS --max-time 20 \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  "https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/configurations")

if [[ "$(jq -r '.success // false' <<<"$CFG")" != "true" ]]; then
  echo "::error::CF API configurations read failed — cannot verify the live ingress."
  jq -r '.errors // empty' <<<"$CFG" >&2 || true
  exit 1
fi

rc=0

# Universal assert, mirroring tunnel-origin-relative-ingress.test.sh's AC1: NO ingress
# rule may be connector-relative. An enumerated deploy./ssh. check passes while a NEW
# rule ships localhost:.
BAD=$(jq -r '[.result.config.ingress[]?
              | select((.service // "") | test("localhost|127\\.0\\.0\\.1"))
              | "  \(.hostname // "<catch-all>") -> \(.service)"] | .[]?' <<<"$CFG")
if [[ -n "$BAD" ]]; then
  echo "::error::LIVE tunnel config carries connector-relative ingress service(s) — the coin flip is back (ADR-114 I2, #6425/#6594):"
  printf '%s\n' "$BAD" >&2
  rc=1
fi

n_checked=0
for pair in "deploy|http://${WEB1_IP}:9000" "ssh|ssh://${WEB1_IP}:22"; do
  sub="${pair%%|*}"
  want="${pair#*|}"
  got=$(jq -r --arg h "${sub}." '[.result.config.ingress[]?
           | select((.hostname // "") | startswith($h))
           | .service] | join(",")' <<<"$CFG")
  n_checked=$((n_checked + 1))
  if [[ -z "$got" ]]; then
    echo "::error::live tunnel config has NO ingress rule for ${sub}. — the route is missing entirely."
    rc=1
  elif [[ "$got" != "$want" ]]; then
    echo "::error::live ${sub}. ingress service is '${got}', expected '${want}'. The apply reported success but the edge is serving a different origin."
    rc=1
  else
    echo "ok: live ${sub}. ingress service == ${want}"
  fi
done
[[ "$n_checked" -eq 2 ]] || { echo "::error::internal: checked ${n_checked} routes, expected 2"; rc=1; }
[[ "$rc" -eq 0 ]] || exit 1

# --- (b) Data plane: the pinned origin actually serves -------------------------------
# A clean config read-back does NOT prove the origin answers — this is the check that
# catches a correct-looking pin at a dead address.
APP_DOMAIN_BASE=$(doppler secrets get APP_DOMAIN_BASE "${DOPPLER_ARGS[@]}" --plain 2>/dev/null || echo "soleur.ai")
WEBHOOK_SECRET=$(doppler secrets get WEBHOOK_DEPLOY_SECRET "${DOPPLER_ARGS[@]}" --plain)
CF_ACCESS_ID=$(doppler secrets get CF_ACCESS_CLIENT_ID "${DOPPLER_ARGS[@]}" --plain 2>/dev/null \
  || doppler secrets get CI_SSH_ACCESS_TOKEN_ID "${DOPPLER_ARGS[@]}" --plain)
CF_ACCESS_SECRET=$(doppler secrets get CF_ACCESS_CLIENT_SECRET "${DOPPLER_ARGS[@]}" --plain 2>/dev/null \
  || doppler secrets get CI_SSH_ACCESS_TOKEN_SECRET "${DOPPLER_ARGS[@]}" --plain)
[[ -n "$WEBHOOK_SECRET" ]] && echo "::add-mask::$WEBHOOK_SECRET"
[[ -n "$CF_ACCESS_SECRET" ]] && echo "::add-mask::$CF_ACCESS_SECRET"

HMAC=$(printf '' | openssl dgst -sha256 -hmac "$WEBHOOK_SECRET" | sed 's/.*= //')
HTTP_CODE="000"
for attempt in 1 2 3 4 5; do
  HTTP_CODE=$(curl -s -o /tmp/deploy-status-verify.json -w '%{http_code}' --max-time 15 \
    -H "X-Signature-256: sha256=${HMAC}" \
    -H "CF-Access-Client-Id: ${CF_ACCESS_ID}" \
    -H "CF-Access-Client-Secret: ${CF_ACCESS_SECRET}" \
    "https://deploy.${APP_DOMAIN_BASE}/hooks/deploy-status" 2>/dev/null || echo "000")
  [[ "$HTTP_CODE" == "200" ]] && break
  # Retrying a REACHABILITY probe is sound — the CF edge propagates a new config
  # asynchronously. This is NOT the #6594 retry defect: that loop retried a CONTENT
  # assert across independent connector selections, so it passed if ANY host matched
  # (any-of-3). Here every attempt targets the same pinned origin, so retrying can
  # only absorb propagation latency — it cannot launder a wrong origin into a pass.
  echo "attempt ${attempt}: HTTP ${HTTP_CODE} (edge may still be propagating; retrying in 6s)"
  sleep 6
done

if [[ "$HTTP_CODE" != "200" ]]; then
  cat >&2 <<EOF
::error::deploy.${APP_DOMAIN_BASE}/hooks/deploy-status returned HTTP ${HTTP_CODE} after the ingress pin — the pinned origin ${WEB1_IP}:9000 is NOT serving. The management plane is down.
CF's edge-generated 502 does not name the origin it failed to reach, so check, in order:
  1. web-1's private NIC is up and holds ${WEB1_IP} (a fresh boot can serve ingress before the NIC converges — ADR-114:210-213; #6557 documents attaches that land while the guest never configures the address).
  2. webhook.service is running and bound to 0.0.0.0:9000.
Recovery: revert the ingress pin and merge. tunnel.tf applies via the Cloudflare API, NOT through the deploy. tunnel, so the revert lands even with deploy. and ssh. both dead.
EOF
  cat /tmp/deploy-status-verify.json >&2 2>/dev/null || true
  exit 1
fi

echo "ok: deploy.${APP_DOMAIN_BASE} is serving from the pinned origin (host_id=$(jq -r '.host_id // "unknown"' /tmp/deploy-status-verify.json 2>/dev/null || echo unknown))"
