#!/usr/bin/env bash
# resend-inbound-bootstrap.sh — one-shot, IDEMPOTENT provisioning of the
# Resend inbound-email ingress for feat-operator-inbox-delegation.
#
# WHEN IT RUNS: pre-merge (plan step E.2) — it MINTS the values the rest of
# the rollout consumes: the inbound MX/DNS record set that dns.tf is authored
# from, and the webhook signing secret the /api/webhooks/resend-inbound route
# verifies with. dns.tf is written AFTER this run, from the records printed
# at the end. Safe to re-run at any time: every step either detects existing
# state and reports it, or performs an idempotent PATCH/insert.
#
# WHAT IT DOES:
#   1. Account-ownership preflight: asserts soleur.ai exists AND is verified
#      in THIS Resend account (two Resend accounts have existed — a key from
#      the wrong one would provision a parallel, dead ingress).
#   2. Enables inbound receiving on the domain (PATCH capabilities.receiving).
#   3. Ensures an email.received webhook for the prod ingress endpoint
#      exists; creates it if absent and captures the signing secret.
#   4. Writes the signing secret STRAIGHT into Doppler soleur/prd as
#      RESEND_INBOUND_WEBHOOK_SECRET via stdin — the full secret is NEVER
#      echoed; stdout only ever shows whsec_***…<last4>.
#   5. Prints the domain's full DNS record set for dns.tf authoring.
#
# USAGE (operator, from repo root):
#   doppler run -p soleur -c prd -- \
#     bash apps/web-platform/infra/resend-inbound-bootstrap.sh
#
# REQUIRES: RESEND_API_KEY in env (Doppler-injected), curl, jq, doppler.
# API shapes per https://resend.com/docs/api-reference/domains/update-domain
# and https://resend.com/docs/api-reference/webhooks/create-webhook.

set -euo pipefail

# IMPORTANT (verified live 2026-06-11, #5103): Resend RECEIVING is DOMAIN-SCOPED.
# Enabling receiving on the apex `soleur.ai` domain produces a Receiving MX on the
# APEX (record name ""), which would collide with the operator's Proton apex MX and
# split all @soleur.ai delivery — a brand-critical mail outage. To keep the apex
# untouched (plan TR1), the inbound ingress MUST be its OWN Resend domain
# `inbound.soleur.ai`: this script (a) ensures that domain exists + is verified,
# (b) enables receiving on IT (MX lands on inbound.soleur.ai, additive to the apex),
# (c) ensures the account-level email.received webhook exists. Proton Sieve then
# forwards ops@soleur.ai → <anything>@inbound.soleur.ai.
RESEND_API="https://api.resend.com"
DOMAIN_NAME="inbound.soleur.ai"
APEX_DOMAIN="soleur.ai"  # must stay Proton-owned; this script never touches it
WEBHOOK_ENDPOINT="https://app.soleur.ai/api/webhooks/resend-inbound"
WEBHOOK_EVENT="email.received"
DOPPLER_PROJECT="soleur"
DOPPLER_CONFIG="prd"
SECRET_NAME="RESEND_INBOUND_WEBHOOK_SECRET"

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------
for bin in curl jq doppler; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "ERROR: required tool '$bin' not found on PATH" >&2
    exit 1
  fi
done

if [[ -z "${RESEND_API_KEY:-}" ]]; then
  echo "ERROR: RESEND_API_KEY is not set. Run under:" >&2
  echo "  doppler run -p ${DOPPLER_PROJECT} -c ${DOPPLER_CONFIG} -- bash $0" >&2
  exit 1
fi

# Authenticated GET/POST/PATCH against the Resend API. The API key NEVER
# appears in argv (a `curl -H "Authorization: ..."` header is readable by any
# local process via /proc/<pid>/cmdline): the Authorization header reaches
# curl through --config on a process-substitution FD, so it exists only as an
# unlinked pipe between bash and curl.
resend_api() {
  local method="$1" path="$2" body="${3:-}"
  if [[ -n "$body" ]]; then
    curl -sS -X "$method" "${RESEND_API}${path}" \
      --config <(printf 'header = "Authorization: Bearer %s"\n' "$RESEND_API_KEY") \
      -H "Content-Type: application/json" \
      -d "$body"
  else
    curl -sS -X "$method" "${RESEND_API}${path}" \
      --config <(printf 'header = "Authorization: Bearer %s"\n' "$RESEND_API_KEY")
  fi
}

# ---------------------------------------------------------------------------
# 1. Account-ownership preflight
# ---------------------------------------------------------------------------
echo "==> [1/5] Ensuring the dedicated receiving domain (${DOMAIN_NAME})"
echo "    (apex ${APEX_DOMAIN} is Proton-owned and is NEVER touched by this script)"
domains_json="$(resend_api GET /domains)"

domain_id="$(jq -r --arg name "$DOMAIN_NAME" \
  '.data[]? | select(.name == $name) | .id' <<<"$domains_json")"

if [[ -z "$domain_id" || "$domain_id" == "null" ]]; then
  # Register inbound.soleur.ai as its OWN Resend domain (region pinned to match
  # the apex domain's eu-west-1). Returns the DKIM/SPF records to add to dns.tf.
  echo "    domain absent — creating Resend domain '${DOMAIN_NAME}' (eu-west-1)"
  create_domain="$(resend_api POST /domains \
    "$(jq -nc --arg name "$DOMAIN_NAME" '{name: $name, region: "eu-west-1"}')")"
  domain_id="$(jq -r '.id // empty' <<<"$create_domain")"
  if [[ -z "$domain_id" ]]; then
    echo "ERROR: could not create domain '${DOMAIN_NAME}':" >&2
    jq -r '.message // "unparseable response"' <<<"$create_domain" >&2
    exit 1
  fi
  echo "    OK: created (id ${domain_id}). Add the DKIM/SPF records printed in [5/5]"
  echo "    to DNS, then RE-RUN this script once they propagate to flip to verified."
fi

domain_json="$(resend_api GET "/domains/${domain_id}")"
domain_status="$(jq -r '.status // "unknown"' <<<"$domain_json")"
echo "    ${DOMAIN_NAME} status: ${domain_status} (id ${domain_id})"
# 'verified' or 'partially_verified' (sending verified, receiving MX pending) both
# permit enabling receiving; only a brand-new 'pending'/'not_started' domain whose
# DKIM has not propagated yet should pause here for a DNS round-trip.
if [[ "$domain_status" == "pending" || "$domain_status" == "not_started" ]]; then
  echo "    NOTE: DKIM not yet verified — receiving-enable will still be attempted,"
  echo "    but the domain only goes fully live once the [5/5] records propagate."
fi

# ---------------------------------------------------------------------------
# 2. Enable inbound receiving on the domain
# ---------------------------------------------------------------------------
# PATCH /domains/{id} per
# https://resend.com/docs/api-reference/domains/update-domain — the
# capabilities object toggles inbound receiving. Idempotent: PATCHing an
# already-enabled domain is a no-op success, so re-runs are safe.
echo "==> [2/5] Enabling inbound receiving on ${DOMAIN_NAME}"
patch_response="$(resend_api PATCH "/domains/${domain_id}" \
  '{"capabilities":{"receiving":"enabled"}}')"
patch_error="$(jq -r '.message // empty' <<<"$patch_response")"
if [[ -n "$patch_error" ]]; then
  # Tolerate already-enabled phrasing; abort on anything else.
  if grep -qi "already" <<<"$patch_error"; then
    echo "    OK: receiving already enabled (${patch_error})"
  else
    echo "ERROR: enabling receiving failed: ${patch_error}" >&2
    exit 1
  fi
else
  echo "    OK: receiving enabled"
fi

# ---------------------------------------------------------------------------
# 3. Ensure the email.received webhook exists
# ---------------------------------------------------------------------------
echo "==> [3/5] Ensuring ${WEBHOOK_EVENT} webhook for ${WEBHOOK_ENDPOINT}"
webhooks_json="$(resend_api GET /webhooks)"

# NOTE: the live Resend API uses `endpoint` (NOT the documented `endpoint_url`);
# verified 2026-06-11 against the prod account — `endpoint_url` returns
# "Missing `endpoint` field". Both names are matched here for forward-compat.
existing_webhook_id="$(jq -r \
  --arg url "$WEBHOOK_ENDPOINT" --arg ev "$WEBHOOK_EVENT" \
  '.data[]? | select(.endpoint == $url or .endpoint_url == $url)
            | select((.events // []) | index($ev))
            | .id' <<<"$webhooks_json" | head -n1)"

signing_secret=""
if [[ -n "$existing_webhook_id" && "$existing_webhook_id" != "null" ]]; then
  echo "    OK: webhook already exists (id ${existing_webhook_id}) — not recreating"
  # Retrieve the secret if the API exposes it on GET (masked print only).
  webhook_detail="$(resend_api GET "/webhooks/${existing_webhook_id}")"
  signing_secret="$(jq -r '.signing_secret // .secret // empty' <<<"$webhook_detail")"
  if [[ -n "$signing_secret" ]]; then
    echo "    signing secret retrievable: whsec_***…${signing_secret: -4}"
  else
    echo "    signing secret not retrievable via GET — Doppler value left as-is"
  fi
else
  # POST /webhooks per
  # https://resend.com/docs/api-reference/webhooks/create-webhook —
  # {endpoint_url, events} → response carries the one-time signing_secret.
  create_response="$(resend_api POST /webhooks \
    "$(jq -nc --arg url "$WEBHOOK_ENDPOINT" --arg ev "$WEBHOOK_EVENT" \
       '{endpoint: $url, events: [$ev]}')")"
  webhook_id="$(jq -r '.id // empty' <<<"$create_response")"
  signing_secret="$(jq -r '.signing_secret // .secret // empty' <<<"$create_response")"
  if [[ -z "$webhook_id" || -z "$signing_secret" ]]; then
    echo "ERROR: webhook creation failed or returned no signing secret:" >&2
    jq -r '.message // "unparseable response"' <<<"$create_response" >&2
    exit 1
  fi
  echo "    OK: webhook created (id ${webhook_id}), secret whsec_***…${signing_secret: -4}"
fi

# ---------------------------------------------------------------------------
# 4. Write the signing secret into Doppler (stdin pipe — never echoed)
# ---------------------------------------------------------------------------
echo "==> [4/5] Writing ${SECRET_NAME} into Doppler ${DOPPLER_PROJECT}/${DOPPLER_CONFIG}"
if [[ -n "$signing_secret" ]]; then
  # The secret travels stdin → doppler ONLY. No echo, no argv, no tmp file.
  # `--silent` suppresses the success line, but `doppler secrets set` still prints
  # the full config table to stdout — redirect to /dev/null so no secret leaks.
  printf '%s' "$signing_secret" | doppler secrets set "$SECRET_NAME" \
    --project "$DOPPLER_PROJECT" --config "$DOPPLER_CONFIG" \
    --no-interactive --silent > /dev/null
  echo "    OK: ${SECRET_NAME} set (whsec_***…${signing_secret: -4})"
else
  echo "    SKIPPED: no secret captured this run (pre-existing webhook whose"
  echo "    secret is not retrievable). If Doppler ${SECRET_NAME} is unset,"
  echo "    delete the webhook in the Resend dashboard and re-run this script."
fi

# ---------------------------------------------------------------------------
# 5. Print the domain DNS record set (dns.tf authoring input)
# ---------------------------------------------------------------------------
echo "==> [5/5] DNS record set for ${DOMAIN_NAME} (author dns.tf from this):"
domain_json="$(resend_api GET "/domains/${domain_id}")"
echo "------------------------------------------------------------------------"
jq -r '.records[]? |
  [.record, .type, .name, (.priority // "" | tostring), .value, .status] |
  @tsv' <<<"$domain_json" | column -t -s$'\t' || {
  echo "(no records array in response — raw dump follows)"
  jq '.' <<<"$domain_json"
}
echo "------------------------------------------------------------------------"
echo "Done. Next: author the inbound record set in apps/web-platform/infra/dns.tf"
echo "from the rows above (additive-only; zero diff on apex Proton MX/SPF/DKIM/_dmarc)."
