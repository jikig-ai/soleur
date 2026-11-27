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

# REFUSE TO RUN UNDER XTRACE (#7797). This script binds a live Cloudflare API token, a
# webhook HMAC secret and a CF Access client secret; with `-x` the shell prints every
# expansion, so each one lands in the job log in plaintext BEFORE any `::add-mask::`
# below can take effect. Masking cannot retract what xtrace already printed. First
# statement after `set`, because anything above it is already traced.
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

# Credentials ride curl's STDIN config channel (`--config -`), never its argument list, which
# every local user can read via /proc/<pid>/cmdline (#9597). Two guards, because the two value
# classes differ: a bearer TOKEN has a closed charset; a header VALUE (CF Access id/secret, the
# HMAC) only needs to be unable to break out of the config string or start a new directive.
# A value failing its guard means the check could not run: that is a gate failure (exit 1),
# exactly like a missing credential, never a skip.
_bearer_ok() { local LC_ALL=C; case "${1:-}" in ''|*[!A-Za-z0-9._~+/=-]*) return 1 ;; esac; }
_cfg_ok() { local LC_ALL=C; case "${1:-}" in ''|*'"'*|*'\'*|*[[:cntrl:]]*) return 1 ;; esac; }
# Script-owned scratch for the deploy-status body (was the fixed /tmp/deploy-status-verify.json:
# a fixed name is shared by every concurrent run of this script).
DEPLOY_STATUS_TMP="$(mktemp)"
DEPLOY_STATUS_HDR="$(mktemp)"
trap 'rm -f "$DEPLOY_STATUS_TMP" "$DEPLOY_STATUS_HDR"' EXIT

# Resolve the infra dir from THIS script's own location — absolute and
# CWD-independent. Do NOT honor a relative $INFRA_DIR override (#6595): the workflow
# exports INFRA_DIR=apps/web-platform/infra AND runs this step with
# working-directory=$INFRA_DIR, so the CWD is already the infra dir and a
# `cd apps/web-platform/infra` from there dies "No such file or directory" — which
# gates (if: success()) and thus SKIPS the SSH-provisioned apply leg that delivers
# fail2ban's ignoreip grant and every other remote-exec resource.
INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$INFRA_DIR"

DOPPLER_ARGS=(--project soleur --config prd_terraform)

# --- Expected origins: canonical sources, never a hardcoded private IP literal ------
# ONE console session, two expressions, one answer per line: web-1's private IP (deploy./ssh.)
# and the zot endpoint (registry., zot-registry.tf local.registry_endpoint).
CONSOLE_OUT=$(doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform console <<<$'var.web_hosts["web-1"].private_ip\nlocal.registry_endpoint' 2>/dev/null || true)
WEB1_IP=$(sed -n 1p <<<"$CONSOLE_OUT" | tr -d '"' | tr -d '[:space:]')
REGISTRY_ENDPOINT=$(sed -n 2p <<<"$CONSOLE_OUT" | tr -d '"' | tr -d '[:space:]')
if [[ ! "$WEB1_IP" =~ ^10\.0\.1\.[0-9]{1,3}$ ]]; then
  echo "::error::could not resolve var.web_hosts[\"web-1\"].private_ip via terraform console (got '${WEB1_IP}'). Refusing to verify against an unknown origin — a blind check is worse than none."
  exit 1
fi
if [[ ! "$REGISTRY_ENDPOINT" =~ ^10\.0\.1\.[0-9]{1,3}:[0-9]{1,5}$ ]]; then
  echo "::error::could not resolve local.registry_endpoint via terraform console (got '${REGISTRY_ENDPOINT}'). Refusing to verify the registry. route against an unknown origin."
  exit 1
fi

CF_API_TOKEN=$(doppler secrets get CF_API_TOKEN "${DOPPLER_ARGS[@]}" --plain 2>/dev/null || true)
[[ -n "$CF_API_TOKEN" ]] && echo "::add-mask::$CF_API_TOKEN"
if [[ -z "$CF_API_TOKEN" ]]; then
  # Fail CLOSED. A missing credential means the check did not run; treating that as a
  # pass is how a gate certifies silence.
  echo "::error::doppler read failed for CF_API_TOKEN — the ingress verification could NOT run. This is a gate failure, not a skip."
  exit 1
fi

# The tunnel the deploy./ssh./registry. CNAMEs point at, and ITS account (#12937). Both come from the
# TF outputs (tunnel.tf `cf_tunnel_id` / `cf_tunnel_account_id`, read off the `.web` resource dns.tf's
# CNAMEs reference), NOT from Doppler `CF_ACCOUNT_ID`: state says which tunnel the records route to, so
# a Doppler id flipped ahead of ADR-329's tunnel phase cannot point this check at another account.
TUNNEL_ID=$(terraform output -raw cf_tunnel_id 2>/dev/null || true)
TUNNEL_ACCOUNT_ID=$(terraform output -raw cf_tunnel_account_id 2>/dev/null || true)
if [[ ! "$TUNNEL_ID" =~ ^[0-9a-fA-F-]{36}$ ]]; then
  echo "::error::could not resolve the tunnel id from terraform output cf_tunnel_id (got '${TUNNEL_ID}'). This is a gate failure, not a skip."
  exit 1
fi
if [[ ! "$TUNNEL_ACCOUNT_ID" =~ ^[0-9a-f]{32}$ ]]; then
  echo "::error::could not resolve the tunnel account from terraform output cf_tunnel_account_id (got '${TUNNEL_ACCOUNT_ID}'). This is a gate failure, not a skip."
  exit 1
fi

# --- (a) Config plane: authoritative, vantage-free read-back ------------------------
# `--disable` FIRST (position is load-bearing: it aborts ~/.curlrc parsing, and a later
# position is too late), then `--noproxy '*'`. Without them a runner-level ~/.curlrc or an
# ALL_PROXY/HTTPS_PROXY variable redirects this request — bearer token intact — to a host
# of the attacker's choosing, with the destination URL below still reading correctly.
if ! _bearer_ok "$CF_API_TOKEN"; then
  echo "::error::CF_API_TOKEN failed the token-shape check — the ingress verification could NOT run. This is a gate failure, not a skip."
  exit 1
fi
CFG=$(curl --disable --noproxy '*' -sS --max-time 20 --config - \
  "https://api.cloudflare.com/client/v4/accounts/${TUNNEL_ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/configurations" \
  < <(printf 'header = "Authorization: Bearer %s"\n' "$CF_API_TOKEN"))

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

# Every rule whose hostname starts with the route is checked (joined), not the first match: a second
# rule after a compliant first makes `got` differ from `want` and reds.
n_checked=0
for pair in "deploy|http://${WEB1_IP}:9000" "ssh|ssh://${WEB1_IP}:22" "registry|tcp://${REGISTRY_ENDPOINT}"; do
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
[[ "$n_checked" -eq 3 ]] || { echo "::error::internal: checked ${n_checked} routes, expected 3"; rc=1; }
[[ "$rc" -eq 0 ]] || exit 1

# --- (b) Data plane: the pinned origin actually serves -------------------------------
# A clean config read-back does NOT prove the origin answers — this is the check that
# catches a correct-looking pin at a dead address.
APP_DOMAIN_BASE=$(doppler secrets get APP_DOMAIN_BASE "${DOPPLER_ARGS[@]}" --plain 2>/dev/null || echo "soleur.ai")
# The trio comes from the caller's env (the Tier-B loader step, #9294), never from prd_terraform.
WEBHOOK_SECRET="${WEBHOOK_DEPLOY_SECRET?Tier-B loader exported no WEBHOOK_DEPLOY_SECRET - see the Load infra credentials step source= line}"
CF_ACCESS_ID="${CF_ACCESS_CLIENT_ID?Tier-B loader exported no CF_ACCESS_CLIENT_ID - see the Load infra credentials step source= line}"
CF_ACCESS_SECRET="${CF_ACCESS_CLIENT_SECRET?Tier-B loader exported no CF_ACCESS_CLIENT_SECRET - see the Load infra credentials step source= line}"
[[ -n "$WEBHOOK_SECRET" ]] && echo "::add-mask::$WEBHOOK_SECRET"
[[ -n "$CF_ACCESS_SECRET" ]] && echo "::add-mask::$CF_ACCESS_SECRET"

HMAC=$(printf '' | HMAC_KEY="$WEBHOOK_SECRET" python3 -I -c 'import hashlib,hmac,os,sys;k=os.environb.get(b"HMAC_KEY");k or sys.exit(1);sys.stdout.write(hmac.new(k,sys.stdin.buffer.read(),hashlib.sha256).hexdigest())') || HMAC=""
if ! { _cfg_ok "$HMAC" && _cfg_ok "$CF_ACCESS_ID" && _cfg_ok "$CF_ACCESS_SECRET"; }; then
  echo "::error::a deploy-status credential (webhook HMAC, CF Access id or secret) failed the header-value check — the data-plane verification could NOT run. This is a gate failure, not a skip."
  exit 1
fi
HTTP_CODE="000"
for attempt in 1 2 3 4 5; do
  # --disable/--noproxy as above (#7797): this call carries the webhook HMAC and both
  # CF Access client credentials.
  HTTP_CODE=$(curl --disable --noproxy '*' -s -o "$DEPLOY_STATUS_TMP" -D "$DEPLOY_STATUS_HDR" -w '%{http_code}' --max-time 15 --config - \
    "https://deploy.${APP_DOMAIN_BASE}/hooks/deploy-status" 2>/dev/null \
    < <(printf 'header = "X-Signature-256: sha256=%s"\nheader = "CF-Access-Client-Id: %s"\nheader = "CF-Access-Client-Secret: %s"\n' \
          "$HMAC" "$CF_ACCESS_ID" "$CF_ACCESS_SECRET") || echo "000")
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
  # SOLEUR_TUNNEL_VERIFY (Ruled by CTO agent, 2026-11-19): name the MEASURED cause before failing.
  # The data plane cannot tell "no connector" from "dead origin" (both are an edge 5xx), the control plane
  # can: read the tunnel's connector census (the same classifier the scheduled census uses). No pass path
  # is added at zero connectors — a dead connector on a future apply must stay red.
  # shellcheck source=scripts/tunnel-connector-census.sh
  source "${INFRA_DIR}/../../../scripts/tunnel-connector-census.sh"
  CONN_RESP=$(curl --disable --noproxy '*' -sS --max-time 20 -w '\n%{http_code}' --config - \
    "https://api.cloudflare.com/client/v4/accounts/${TUNNEL_ACCOUNT_ID}/cfd_tunnel/${TUNNEL_ID}/connections" \
    < <(printf 'header = "Authorization: Bearer %s"\n' "$CF_API_TOKEN") 2>/dev/null || printf '\n000')
  read -r CENSUS CONNS <<<"$(classify_connector_census "$(tail -1 <<<"$CONN_RESP")" "$(sed '$d' <<<"$CONN_RESP")")"
  case "$CENSUS" in
    zero_connectors) VERIFY_CAUSE="no-connector" ;;
    # A connector is up. Access's own refusal carries its stamp (cf-access-aud/-domain) or redirects to its login: the
    # predicate scripts/check-cloudflare-token-drift.sh uses. An unstamped 403 is web-1's webhook (hooks.json HMAC rule).
    ok|multi_connector)
      if grep -qiE '^cf-access-(aud|domain):' "$DEPLOY_STATUS_HDR" 2>/dev/null \
         || { [[ "$HTTP_CODE" == 30? ]] && grep -qiE '^location:.*(cloudflareaccess\.com|/cdn-cgi/access/)' "$DEPLOY_STATUS_HDR" 2>/dev/null; }; then
        VERIFY_CAUSE="access-refused"
      elif [[ "$HTTP_CODE" == "403" ]]; then VERIFY_CAUSE="origin-refused"
      else VERIFY_CAUSE="origin-not-serving"; fi ;;
    # census_unavailable, or any verdict this script does not know: nothing was measured.
    *) VERIFY_CAUSE="connections-unreadable"; CONNS="unknown" ;;
  esac
  echo "SOLEUR_TUNNEL_VERIFY cause=${VERIFY_CAUSE} tunnel=${TUNNEL_ID} connections=${CONNS}"
  [[ -n "${GITHUB_OUTPUT:-}" ]] && echo "cause=${VERIFY_CAUSE}" >> "$GITHUB_OUTPUT"
  # Each cause gets its own annotation; only origin-not-serving blames the origin and prescribes the pin revert.
  # The annotations do not repeat the SOLEUR_TUNNEL_VERIFY prefix, so the runbook grep finds exactly one line.
  case "$VERIFY_CAUSE" in
    no-connector)
      echo "::error::Tunnel verify (no-connector): tunnel ${TUNNEL_ID} has 0 connections, so nothing serves deploy./ssh./registry. The Terraform apply itself landed. Remedy: re-bake the connector host: gh workflow run apply-web-platform-infra.yml -f apply_target=web-host-replace -f web_host_key=web-2 -f confirm=REPLACE-web-2"
      if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
        cat >> "$GITHUB_STEP_SUMMARY" <<SUMMARY
**Tunnel verify: no connector.** Tunnel \`${TUNNEL_ID}\` has 0 connections, so deploy./ssh./registry. have nothing behind them. This is EXPECTED on the first apply after the tunnel moved account, before the connector host is re-born with its token (\`web-host-replace web-2\`). Any other apply that reports it means the connector is down, which is a real outage.
SUMMARY
      fi
      ;;
    connections-unreadable)
      echo "::error::Tunnel verify (connections-unreadable): deploy.${APP_DOMAIN_BASE}/hooks/deploy-status returned HTTP ${HTTP_CODE} and the tunnel's connection count could not be read, so neither the connector nor the origin was measured. Re-read the census: gh workflow run scheduled-inngest-health.yml"
      ;;
    access-refused)
      echo "::error::Tunnel verify (access-refused): deploy-status answered HTTP ${HTTP_CODE} with Cloudflare Access's stamp (a cf-access-* header or a redirect to its login) and ${CONNS} live connector(s); the origin was not reached. Probe each Access pair: doppler run -p soleur -c prd_terraform -- bash scripts/check-cloudflare-token-drift.sh"
      ;;
    origin-refused)
      echo "::error::Tunnel verify (origin-refused): deploy-status answered HTTP 403 with no Cloudflare Access stamp and ${CONNS} live connector(s), so Access admitted the request and web-1's webhook refused its X-Signature-256 (hooks.json answers 403 on an HMAC mismatch). Check WEBHOOK_DEPLOY_SECRET parity: doppler run -p soleur -c prd_terraform -- bash scripts/check-deploy-script-parity.sh --status-only"
      ;;
    *)
      cat >&2 <<EOF
::error::deploy.${APP_DOMAIN_BASE}/hooks/deploy-status returned HTTP ${HTTP_CODE} after the ingress pin — the pinned origin ${WEB1_IP}:9000 is NOT serving. The management plane is down.
CF's edge-generated 502 does not name the origin it failed to reach, so check, in order:
  1. web-1's private NIC is up and holds ${WEB1_IP} (a fresh boot can serve ingress before the NIC converges — ADR-114:210-213; #6557 documents attaches that land while the guest never configures the address).
  2. webhook.service is running and bound to 0.0.0.0:9000.
Recovery: revert the ingress pin and merge. tunnel.tf applies via the Cloudflare API, NOT through the deploy. tunnel, so the revert lands even with deploy. and ssh. both dead.
EOF
      ;;
  esac
  cat "$DEPLOY_STATUS_TMP" >&2 2>/dev/null || true
  exit 1
fi

echo "ok: deploy.${APP_DOMAIN_BASE} is serving from the pinned origin (host_id=$(jq -r '.host_id // "unknown"' "$DEPLOY_STATUS_TMP" 2>/dev/null || echo unknown))"
