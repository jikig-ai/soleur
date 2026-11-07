#!/usr/bin/env bash
# mint-origin-ca-cert.sh -- the body of .github/workflows/mint-origin-ca-cert.yml (#10479, epic #10205, ADR-321 slice 2).
#
# WHAT IT DOES. Generates an ECC (P-256) key and a CSR on the runner, asks Cloudflare for an Origin CA certificate for
# app.soleur.ai valid 15 years (requested_validity 5475, request_type origin-ecc), checks the certificate against the key,
# and writes ORIGIN_TLS_KEY_B64 and ORIGIN_TLS_CERT_B64 (base64 -w0 of the PEM, the contract of
# apps/web-platform/server/origin-tls.ts) into Doppler soleur/prd. The key is minted OUTSIDE Terraform (ADR-320: no key in
# Tier-A-readable state), so no tls_private_key and no cloudflare_origin_ca_certificate resource exists anywhere.
#
# SUBCOMMANDS.
#   guard   no secret, no network: the refusal ladder (dispatch event, first attempt, ref main, owner actor, inputs, typed
#           confirm). Writes go/mode/replace/guard_epoch to $GITHUB_OUTPUT. Writes nothing else.
#   run     the Tier-B job: plan (read-only rehearsal) or apply (the mint). The only subcommand that touches Doppler or
#           Cloudflare.
#
# THE REPOSITORY IS PUBLIC and the run log is public. This script therefore (a) never uses `set -x`, (b) keeps every Cloudflare
# and Doppler response in a 0600 file under a private temp dir and prints only fields it parsed (numbers, ids, dates, verdict
# tokens), (c) registers an ::add-mask:: for every secret-bearing string BEFORE it exists anywhere else, (d) hands the
# Cloudflare token to curl through a 0600 config file and every Doppler value through stdin, never through argv, (e) shreds the
# temp dir on every exit path. A certificate serial, a not-after date and a sha256 of PUBLIC material are printed; a key, a
# token, a PEM body and a base64 value are never.
#
# POLICY (idempotency and rotation). The 15-year certificate has no renewal event, so a second mint is a mistake unless it is
# deliberate:
#   - nothing in prd                                   -> mint.
#   - half-set, unparseable, not for the host, expired, or <= 90 days left (the app's own warning threshold) -> mint
#     (the existing material is not usable or is about to stop being).
#   - a valid certificate with more than 90 days left -> REFUSED (already_minted_not_expiring) unless replace=true, which also
#     changes the typed confirm (MINT-ORIGIN-CA-REPLACE-<date>).
# A replace never revokes the old certificate (it may still be loaded by a running container until the next restart); the
# verdict line names its serial so a later, separate revoke is possible. Nothing here restarts a container: the new value is
# read at the next container start (the web-platform release redeploy), which is its own owner step.
#
# Seams for the offline suite (plugins/soleur/test/mint-origin-ca-cert.test.sh): MINT_NOW (epoch, single clock), PATH stubs for
# curl and doppler. There is deliberately NO base-URL seam: an environment variable that redirects the Cloudflare call would
# redirect the bearer token with it.

set -uo pipefail

case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

umask 077

readonly MC_HOST="app.soleur.ai"
readonly MC_DOPPLER_PROJECT="soleur"
readonly MC_PRD_CONFIG="prd"
readonly MC_TF_CONFIG="prd_terraform"   # CF_ZONE_ID (an identifier, not a credential) still lives here
readonly MC_TIERB_PROJECT="soleur-infra-privileged"   # the Cloudflare credential lives in the Tier-B project (ADR-241)
readonly MC_TIERB_CONFIG="prd"
readonly MC_KEY_NAME="ORIGIN_TLS_KEY_B64"
readonly MC_CERT_NAME="ORIGIN_TLS_CERT_B64"
readonly MC_CF_TOKEN_NAME="CF_API_TOKEN_ORIGIN_CA"
readonly MC_ZONE_NAME="CF_ZONE_ID"
readonly MC_CF_API="https://api.cloudflare.com/client/v4"
readonly MC_VALIDITY_DAYS=5475
readonly MC_NEAR_EXPIRY_DAYS=90
readonly MC_MIN_DAYS_ISSUED=5000   # an issued certificate must have at least this many days left, or Cloudflare did not honour 15 years
readonly MC_MAIN_REF="refs/heads/main"
readonly MC_OWNER_LOGINS=(deruelle)  # the CODEOWNERS owner; same posture as key-rotate.yml (a fat-finger/identity guard, not the authorization)
readonly MC_AUTH_MAX_AGE_S=3600      # the apply step refuses if the guard passed longer ago than this (an approval can queue for hours)
readonly MC_CMD_TIMEOUT_S=120

mc_now() { printf '%s' "${MINT_NOW:-$(date -u +%s)}"; }
mc_date() { date -u -d "@$1" +%F; }

# A verdict is the one line a reader greps. Fixed vocabulary; the detail is a fixed sentence or numbers, never a stream.
mc_say() { printf 'mint-origin-ca %s\n' "$*"; }
mc_refuse() { # token, fixed sentence
  printf '::error title=mint-origin-ca::verdict=%s %s\n' "$1" "$2"
  mc_say "verdict=$1"
  return 1
}
mc_summary() { [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && printf '%s\n' "$*" >> "$GITHUB_STEP_SUMMARY"; return 0; }
mc_out() { [[ -n "${GITHUB_OUTPUT:-}" ]] && printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"; return 0; }
mc_mask() { # register the value (and each of its lines) as a masked string; never echo it
  local v="$1" ln
  [[ -n "$v" ]] || return 0
  while IFS= read -r ln; do [[ -n "$ln" ]] && printf '::add-mask::%s\n' "$ln"; done <<< "$v"
  return 0
}

# ---------------------------------------------------------------------------------------------------------------------------
# guard
mc_expected_confirm() { # replace date
  if [[ "$1" == "true" ]]; then printf 'MINT-ORIGIN-CA-REPLACE-%s' "$2"; else printf 'MINT-ORIGIN-CA-%s' "$2"; fi
}

mc_guard() {
  local mode="${INPUT_MODE:-}" replace="${INPUT_REPLACE:-false}" confirm="${INPUT_CONFIRM:-}" a o ok want now
  mc_out go false
  [[ "${GITHUB_EVENT_NAME:-}" == "workflow_dispatch" ]] || { mc_refuse event_refused "only a workflow_dispatch may run this; nothing was written"; return 1; }
  [[ "${GITHUB_RUN_ATTEMPT:-1}" == "1" ]] || { mc_refuse rerun_refused "a re-run reuses the first attempt's guard outputs and would bypass the go; dispatch afresh; nothing was written"; return 1; }
  [[ "${GITHUB_REF:-}" == "$MC_MAIN_REF" ]] || { mc_refuse ref_refused "a dispatch from any ref other than main is refused; nothing was written"; return 1; }
  for a in "${GITHUB_ACTOR:-}" "${GITHUB_TRIGGERING_ACTOR:-}"; do
    if [[ -z "$a" || "$a" == *"[bot]" ]]; then mc_refuse actor_refused "the dispatching actor is empty or a bot; nothing was written"; return 1; fi
    ok=1
    for o in "${MC_OWNER_LOGINS[@]}"; do [[ "$a" == "$o" ]] && ok=0; done
    if [[ "$ok" != 0 ]]; then mc_refuse actor_not_owner "the dispatching actor is not in the committed owner allowlist; nothing was written"; return 1; fi
  done
  case "$mode" in plan|apply) ;; *) mc_refuse inputs_invalid "mode must be plan or apply"; return 1 ;; esac
  case "$replace" in true|false) ;; *) mc_refuse inputs_invalid "replace must be true or false"; return 1 ;; esac
  now="$(mc_now)"
  if [[ "$mode" == "apply" ]]; then
    want="$(mc_expected_confirm "$replace" "$(mc_date "$now")")"
    if [[ "$confirm" != "$want" ]]; then
      mc_refuse confirm_mismatch "apply needs the typed confirm MINT-ORIGIN-CA-<YYYY-MM-DD> (UTC date of this run), or MINT-ORIGIN-CA-REPLACE-<YYYY-MM-DD> when replace=true (a fat-finger guard, not the authorization)"
      return 1
    fi
  fi
  mc_say "guard ok mode=$mode replace=$replace actor=$(printf '%s' "${GITHUB_ACTOR:-}" | tr -cd 'A-Za-z0-9-')"
  mc_out go true
  mc_out mode "$mode"
  mc_out replace "$replace"
  mc_out guard_epoch "$now"
  return 0
}

# ---------------------------------------------------------------------------------------------------------------------------
# run
MC_TMP=""
mc_cleanup() {
  local f
  if [[ -n "$MC_TMP" && -d "$MC_TMP" ]]; then
    while IFS= read -r -d '' f; do shred -u -- "$f" 2>/dev/null || rm -f -- "$f"; done < <(find "$MC_TMP" -type f -print0 2>/dev/null)
    rm -rf -- "$MC_TMP"
  fi
  MC_TMP=""
}

# mc_doppler_cfg <project> <config> <verb...>: every Doppler call carries the provider token as DOPPLER_TOKEN for that one command.
mc_doppler() {
  DOPPLER_TOKEN="$MC_DT" timeout "$MC_CMD_TIMEOUT_S" doppler "$@"
}
# mc_names <project> <config>: whole-name listing (value-free).
mc_names() { mc_doppler secrets --only-names -p "$1" -c "$2" 2>/dev/null; }
mc_has_name() { grep -Eq "(^|[^A-Za-z0-9_])$2([^A-Za-z0-9_]|\$)" <<< "$1"; }
# mc_get <project> <config> <name>: the value on stdout, nothing on stderr. The caller captures it into a variable or a file.
mc_get() { mc_doppler secrets get "$3" --plain -p "$1" -c "$2" 2>/dev/null; }
# mc_set <name> <valuefile>: value through stdin; the CLI prints every other secret otherwise, so stdout/stderr go nowhere.
mc_set() { mc_doppler secrets set "$1" -p "$MC_DOPPLER_PROJECT" -c "$MC_PRD_CONFIG" --no-interactive < "$2" >/dev/null 2>&1; }
mc_del() { mc_doppler secrets delete "$1" -p "$MC_DOPPLER_PROJECT" -c "$MC_PRD_CONFIG" --yes >/dev/null 2>&1; }

# mc_cf <method> <path> <outfile> [bodyfile]: Cloudflare call; prints the HTTP status only. Token via a 0600 curl config file.
mc_cf() {
  local method="$1" path="$2" out="$3" body="${4:-}" code rc=0
  local -a args=(--silent --proto '=https' --tlsv1.2 --max-time 60 -K "$MC_TMP/curl.cfg" -X "$method" -H 'Content-Type: application/json'
    -o "$out" -w '%{http_code}')
  [[ -n "$body" ]] && args+=(--data-binary "@$body")
  # No retry on the create: a retry after a lost response would mint a second certificate. GETs retry.
  [[ "$method" == GET ]] && args+=(--retry 2 --retry-delay 2)
  # --disable FIRST (skip ~/.curlrc) and --noproxy '*' (no CURL_PROXY / *_proxy route): this call carries the Cloudflare bearer token,
  # so neither a config file nor a proxy variable may redirect it (#7797 transport confinement).
  code="$(curl --disable --noproxy '*' "${args[@]}" "${MC_CF_API}${path}" 2>/dev/null)" || rc=$?
  [[ "$rc" == 0 ]] || { printf '000'; return 0; }
  printf '%s' "$code"
}
mc_cf_errors() { jq -r '[.errors[]?.code | tostring] | join(",")' "$1" 2>/dev/null | tr -cd '0-9,' | cut -c1-80; }

# mc_b64 <file>: one line, no wrap.
mc_b64() { base64 -w0 < "$1"; }

# mc_cert_facts <certpem-file> -> sets MC_C_DAYS, MC_C_NOT_AFTER, MC_C_SERIAL, MC_C_SAN_OK, MC_C_IS_CA. Returns 1 if it does not parse.
mc_cert_facts() {
  local f="$1" end now_s end_s txt
  MC_C_DAYS=""; MC_C_NOT_AFTER=""; MC_C_SERIAL=""; MC_C_SAN_OK=0; MC_C_IS_CA=1
  end="$(openssl x509 -in "$f" -noout -enddate 2>/dev/null)" || return 1
  end="${end#notAfter=}"
  end_s="$(date -u -d "$end" +%s 2>/dev/null)" || return 1
  now_s="$(mc_now)"
  MC_C_DAYS=$(( (end_s - now_s) / 86400 ))
  MC_C_NOT_AFTER="$(date -u -d "@$end_s" +%FT%TZ)"
  MC_C_SERIAL="$(openssl x509 -in "$f" -noout -serial 2>/dev/null | sed 's/^serial=//' | tr 'A-F' 'a-f' | tr -cd '0-9a-f')"
  # Two separate reads, status ignored: OpenSSL versions differ on whether a missing extension is an error, and a certificate
  # without basicConstraints is not a CA. The SAN match below is what must hold.
  txt="$(openssl x509 -in "$f" -noout -ext subjectAltName 2>/dev/null || true)"
  grep -Eq "DNS:${MC_HOST//./\\.}(,|\$| )" <<< "$txt" && MC_C_SAN_OK=1
  txt="$(openssl x509 -in "$f" -noout -ext basicConstraints 2>/dev/null || true)"
  grep -Eq 'CA:TRUE' <<< "$txt" || MC_C_IS_CA=0
  return 0
}
mc_pub_sha() { # key|cert <file>: sha256 of the DER public key (public material)
  case "$1" in
    key)  openssl pkey -in "$2" -pubout -outform DER 2>/dev/null | sha256sum | cut -c1-64 ;;
    cert) openssl x509 -in "$2" -noout -pubkey 2>/dev/null | openssl pkey -pubin -pubout -outform DER 2>/dev/null | sha256sum | cut -c1-64 ;;
  esac
}

# Existing-state classification -> MC_EX_STATE (absent|half|unusable|expired|near_expiry|valid), MC_EX_DAYS, MC_EX_SERIAL.
# Value-silent: the base64 values are decoded into private files and only parsed facts leave this function.
mc_existing() {
  local names has_k=0 has_c=0 rc=0
  MC_EX_STATE="" MC_EX_DAYS="" MC_EX_SERIAL="" MC_EX_REQUIRED=""
  names="$(mc_names "$MC_DOPPLER_PROJECT" "$MC_PRD_CONFIG")" || rc=$?
  if [[ "$rc" != 0 || -z "$names" ]]; then MC_EX_STATE="unreadable"; return 1; fi
  mc_has_name "$names" "$MC_KEY_NAME" && has_k=1
  mc_has_name "$names" "$MC_CERT_NAME" && has_c=1
  mc_has_name "$names" "ORIGIN_TLS_REQUIRED" && MC_EX_REQUIRED="set" || MC_EX_REQUIRED="unset"
  if [[ $has_k == 0 && $has_c == 0 ]]; then MC_EX_STATE="absent"; return 0; fi
  if [[ "$has_k" != "$has_c" ]]; then MC_EX_STATE="half"; return 0; fi
  # Both present: keep the previous values (for the compensating restore) in private files.
  mc_get "$MC_DOPPLER_PROJECT" "$MC_PRD_CONFIG" "$MC_KEY_NAME" > "$MC_TMP/prev.key.b64" || { MC_EX_STATE="unreadable"; return 1; }
  mc_get "$MC_DOPPLER_PROJECT" "$MC_PRD_CONFIG" "$MC_CERT_NAME" > "$MC_TMP/prev.cert.b64" || { MC_EX_STATE="unreadable"; return 1; }
  MC_PREV_PRESENT=1
  mc_mask "$(cat "$MC_TMP/prev.key.b64")"
  if ! base64 -d < "$MC_TMP/prev.cert.b64" > "$MC_TMP/prev.cert.pem" 2>/dev/null || ! base64 -d < "$MC_TMP/prev.key.b64" > "$MC_TMP/prev.key.pem" 2>/dev/null; then
    MC_EX_STATE="unusable"; return 0
  fi
  if ! mc_cert_facts "$MC_TMP/prev.cert.pem" || [[ "$MC_C_SAN_OK" != 1 || "$MC_C_IS_CA" != 0 ]]; then MC_EX_STATE="unusable"; return 0; fi
  MC_EX_DAYS="$MC_C_DAYS"; MC_EX_SERIAL="$MC_C_SERIAL"
  if [[ -z "$(mc_pub_sha key "$MC_TMP/prev.key.pem")" || "$(mc_pub_sha key "$MC_TMP/prev.key.pem")" != "$(mc_pub_sha cert "$MC_TMP/prev.cert.pem")" ]]; then MC_EX_STATE="unusable"; return 0; fi
  if (( MC_C_DAYS < 0 )); then MC_EX_STATE="expired"
  elif (( MC_C_DAYS <= MC_NEAR_EXPIRY_DAYS )); then MC_EX_STATE="near_expiry"
  else MC_EX_STATE="valid"; fi
  return 0
}

# Compensating restore after a failed second write: put prd back to what it was. Value-silent.
mc_restore_previous() {
  local ok=1
  if [[ "${MC_PREV_PRESENT:-0}" == 1 ]]; then
    mc_set "$MC_KEY_NAME" "$MC_TMP/prev.key.b64" && mc_set "$MC_CERT_NAME" "$MC_TMP/prev.cert.b64" && ok=0
  else
    mc_del "$MC_KEY_NAME"; mc_del "$MC_CERT_NAME"
    local names; names="$(mc_names "$MC_DOPPLER_PROJECT" "$MC_PRD_CONFIG")" || names=""
    if [[ -n "$names" ]] && ! mc_has_name "$names" "$MC_KEY_NAME" && ! mc_has_name "$names" "$MC_CERT_NAME"; then ok=0; fi
  fi
  return "$ok"
}

# mc_fail_restore <token> <what happened>: put prd back, then refuse. The restore outcome picks the token; never a && || chain,
# because mc_refuse returns 1 and would fall through to the other arm.
mc_fail_restore() {
  if mc_restore_previous; then
    mc_refuse "$1" "$2; prd was restored to its previous state"
  else
    mc_refuse "$1_unrestored" "$2 and prd could NOT be confirmed restored; read ORIGIN_TLS_* in soleur/prd before anything else"
  fi
  return 1
}

mc_run() {
  local mode="${MINT_MODE:-}" replace="${MINT_REPLACE:-false}" epoch="${MINT_GUARD_EPOCH:-}" now rc=0
  local cf_token zone code cnt ids
  MC_PREV_PRESENT=0
  case "$mode" in plan|apply) ;; *) mc_refuse inputs_invalid "mode must be plan or apply"; return 1 ;; esac
  case "$replace" in true|false) ;; *) mc_refuse inputs_invalid "replace must be true or false"; return 1 ;; esac
  for t in openssl jq curl doppler base64 sha256sum shred timeout; do command -v "$t" >/dev/null 2>&1 || { mc_refuse tool_missing "a required tool is missing on the runner; nothing was written"; return 1; }; done
  MC_DT="${DOPPLER_TOKEN_TF:-${TF_VAR_doppler_token_tf:-}}"
  [[ -n "$MC_DT" ]] || { mc_refuse no_provider_token "the Tier-B loader exported no Doppler provider token; nothing was written"; return 1; }
  mc_mask "$MC_DT"
  now="$(mc_now)"
  if [[ "$mode" == "apply" ]]; then
    [[ "$epoch" =~ ^[0-9]{9,12}$ ]] || { mc_refuse guard_epoch_missing "no guard timestamp reached the apply step; nothing was written"; return 1; }
    if (( now - epoch > MC_AUTH_MAX_AGE_S )); then mc_refuse guard_stale "the guard passed more than an hour ago (an approval queue can take that long); dispatch afresh; nothing was written"; return 1; fi
  fi

  MC_TMP="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/mint-origin-ca.XXXXXX")" || { mc_refuse tmp_failed "no private temp dir; nothing was written"; return 1; }
  chmod 700 "$MC_TMP"
  trap mc_cleanup EXIT
  trap 'mc_cleanup; exit 130' INT TERM

  # 1. The Cloudflare credential (Tier-B project soleur-infra-privileged/prd, main-only) and the zone id (soleur/prd_terraform),
  #    read value-silently. The credential is NOT read from prd_terraform: that config is Tier-A readable by any branch workflow.
  cf_token="$(mc_get "$MC_TIERB_PROJECT" "$MC_TIERB_CONFIG" "$MC_CF_TOKEN_NAME")" || cf_token=""
  [[ -n "$cf_token" ]] || { mc_refuse cf_token_unreadable "CF_API_TOKEN_ORIGIN_CA could not be read from soleur-infra-privileged/prd; nothing was written"; return 1; }
  mc_mask "$cf_token"
  if [[ ! "$cf_token" =~ ^[A-Za-z0-9._~+/=-]+$ ]]; then mc_refuse cf_token_shape "CF_API_TOKEN_ORIGIN_CA is not a one-line bearer token; nothing was written"; return 1; fi
  zone="$(mc_get "$MC_DOPPLER_PROJECT" "$MC_TF_CONFIG" "$MC_ZONE_NAME")" || zone=""
  if [[ ! "$zone" =~ ^[0-9a-f]{32}$ ]]; then mc_refuse zone_id_unreadable "CF_ZONE_ID is missing or not a 32-hex zone id; nothing was written"; return 1; fi
  printf 'header = "Authorization: Bearer %s"\n' "$cf_token" > "$MC_TMP/curl.cfg"
  cf_token=""

  # 2. What is in prd now, and the policy decision.
  mc_existing || { mc_refuse prd_unreadable "soleur/prd could not be listed or read; nothing was written"; return 1; }
  mc_say "existing state=$MC_EX_STATE days_left=${MC_EX_DAYS:-na} serial=${MC_EX_SERIAL:-na} origin_tls_required=$MC_EX_REQUIRED"
  if [[ "$MC_EX_STATE" == "valid" && "$replace" != "true" ]]; then
    mc_refuse already_minted_not_expiring "prd already holds a valid certificate with more than $MC_NEAR_EXPIRY_DAYS days left; re-dispatch with replace=true only for a deliberate rotation; nothing was written"
    return 1
  fi
  if [[ "$MC_EX_STATE" == "valid" ]]; then mc_say "policy replace=true over a valid certificate (deliberate rotation)"; fi

  # 3. Key and CSR, locally. P-256 is what Cloudflare issues origin-ecc against.
  openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$MC_TMP/key.pem" >/dev/null 2>&1 || { mc_refuse keygen_failed "openssl could not generate the key; nothing was written"; return 1; }
  mc_mask "$(cat "$MC_TMP/key.pem")"
  mc_mask "$(mc_b64 "$MC_TMP/key.pem")"
  openssl req -new -key "$MC_TMP/key.pem" -subj "/CN=${MC_HOST}" -out "$MC_TMP/csr.pem" >/dev/null 2>&1 || { mc_refuse csr_failed "openssl could not build the CSR; nothing was written"; return 1; }
  openssl req -in "$MC_TMP/csr.pem" -verify -noout >/dev/null 2>&1 || { mc_refuse csr_invalid "the CSR does not verify against its own key; nothing was written"; return 1; }
  local curve
  curve="$(openssl pkey -in "$MC_TMP/key.pem" -noout -text 2>/dev/null | sed -n 's/^ASN1 OID: *//p;s/^NIST CURVE: *//p' | paste -sd/ -)"
  mc_say "csr ok subject=CN=${MC_HOST} key=ec curve=${curve:-unknown} pubkey_sha256=$(mc_pub_sha key "$MC_TMP/key.pem") csr_bytes=$(wc -c < "$MC_TMP/csr.pem" | tr -d ' ')"

  # 4. The Cloudflare credential is valid and can reach the certificates API for this zone (a read; the create permission itself
  #    can only be proven by creating, so the apply fails closed on a 403).
  code="$(mc_cf GET /user/tokens/verify "$MC_TMP/verify.json")"
  if [[ "$code" == 200 && "$(jq -r '.success' "$MC_TMP/verify.json" 2>/dev/null)" == true ]]; then
    mc_say "cf token verify status=$(jq -r '.result.status // "unknown"' "$MC_TMP/verify.json" | tr -cd 'a-z_') expires_on=$(jq -r '.result.expires_on // "never"' "$MC_TMP/verify.json" | tr -cd '0-9A-Za-z:.+-')"
  else
    mc_say "cf token verify unavailable http=$(printf '%s' "$code" | tr -cd '0-9') (an account-owned token has no /user verify; the list below is the real check)"
  fi
  code="$(mc_cf GET "/certificates?zone_id=${zone}" "$MC_TMP/list.json")"
  if [[ "$code" != 200 || "$(jq -r '.success' "$MC_TMP/list.json" 2>/dev/null)" != true ]]; then
    mc_refuse cf_list_failed "the Origin CA list call was refused (http=$(printf '%s' "$code" | tr -cd '0-9') cf_error_codes=$(mc_cf_errors "$MC_TMP/list.json")); the token is invalid, expired or lacks Zone / SSL and Certificates; nothing was written"
    return 1
  fi
  cnt="$(jq -r --arg h "$MC_HOST" '[.result[]? | select((.hostnames // []) | index($h)) | select(.revoked_at == null)] | length' "$MC_TMP/list.json" 2>/dev/null | tr -cd '0-9')"
  ids="$(jq -r --arg h "$MC_HOST" '[.result[]? | select((.hostnames // []) | index($h)) | select(.revoked_at == null) | "\(.id|tostring):\(.expires_on|tostring)"] | .[0:10] | join(" ")' "$MC_TMP/list.json" 2>/dev/null | tr -cd '0-9A-Za-z:. +-')"
  mc_say "cf list ok active_certs_for_host=${cnt:-0} (serial:expires) ${ids:-none}"

  if [[ "$mode" == "plan" ]]; then
    mc_say "verdict=plan_ok nothing_created=true would_mint=true validity_days=$MC_VALIDITY_DAYS"
    mc_summary "### mint-origin-ca plan: ok. Token valid, CSR valid, policy allows a mint (existing state: $MC_EX_STATE). Nothing was created or written."
    return 0
  fi

  # 5. Apply: request the certificate. The CSR is public; the key never leaves the runner.
  jq -n --arg h "$MC_HOST" --rawfile csr "$MC_TMP/csr.pem" --argjson v "$MC_VALIDITY_DAYS" \
    '{hostnames: [$h], requested_validity: $v, request_type: "origin-ecc", csr: $csr}' > "$MC_TMP/req.json" || { mc_refuse request_build_failed "could not build the request; nothing was written"; return 1; }
  code="$(mc_cf POST /certificates "$MC_TMP/resp.json" "$MC_TMP/req.json")"
  if [[ "$code" != 200 || "$(jq -r '.success' "$MC_TMP/resp.json" 2>/dev/null)" != true ]]; then
    mc_refuse cf_create_failed "Cloudflare did not issue the certificate (http=$(printf '%s' "$code" | tr -cd '0-9') cf_error_codes=$(mc_cf_errors "$MC_TMP/resp.json")); nothing was written to Doppler"
    return 1
  fi
  local cf_id
  cf_id="$(jq -r '.result.id // empty' "$MC_TMP/resp.json" | tr -cd '0-9A-Za-z')"
  jq -r '.result.certificate // empty' "$MC_TMP/resp.json" > "$MC_TMP/cert.pem"
  mc_say "cf issued cert_id=${cf_id:-unknown} (created at Cloudflare; not yet in Doppler)"

  # 6. Verify what came back against the key, before anything is written.
  if ! mc_cert_facts "$MC_TMP/cert.pem"; then mc_refuse cert_unparseable "the returned certificate does not parse; cf cert_id=${cf_id:-unknown} exists at Cloudflare and is unused; nothing was written to Doppler"; return 1; fi
  if [[ "$MC_C_SAN_OK" != 1 ]]; then mc_refuse cert_wrong_host "the returned certificate does not cover $MC_HOST; cf cert_id=${cf_id:-unknown} is unused; nothing was written to Doppler"; return 1; fi
  if [[ "$MC_C_IS_CA" != 0 ]]; then mc_refuse cert_is_ca "the returned certificate is a CA; cf cert_id=${cf_id:-unknown} is unused; nothing was written to Doppler"; return 1; fi
  if (( MC_C_DAYS < MC_MIN_DAYS_ISSUED )); then mc_refuse cert_short_validity "the returned certificate has only ${MC_C_DAYS} days left, not 15 years; cf cert_id=${cf_id:-unknown} is unused; nothing was written to Doppler"; return 1; fi
  if [[ -z "$(mc_pub_sha key "$MC_TMP/key.pem")" || "$(mc_pub_sha key "$MC_TMP/key.pem")" != "$(mc_pub_sha cert "$MC_TMP/cert.pem")" ]]; then
    mc_refuse cert_key_mismatch "the returned certificate does not match the generated key; cf cert_id=${cf_id:-unknown} is unused; nothing was written to Doppler"; return 1
  fi
  mc_b64 "$MC_TMP/key.pem" > "$MC_TMP/key.b64"
  mc_b64 "$MC_TMP/cert.pem" > "$MC_TMP/cert.b64"
  mc_mask "$(cat "$MC_TMP/cert.b64")"
  local want_k want_c
  want_k="$(sha256sum < "$MC_TMP/key.b64" | cut -c1-64)"
  want_c="$(sha256sum < "$MC_TMP/cert.b64" | cut -c1-64)"
  mc_say "cert ok serial=$MC_C_SERIAL not_after=$MC_C_NOT_AFTER days_left=$MC_C_DAYS san_covers_host=true is_ca=false key_matches=true"

  # 7. Write to prd (two secrets, values by stdin), read back, and restore the previous state if anything disagrees.
  if ! mc_set "$MC_CERT_NAME" "$MC_TMP/cert.b64"; then mc_fail_restore doppler_write_failed "the certificate write was refused (cf cert_id=${cf_id:-unknown} is unused)"; return 1; fi
  if ! mc_set "$MC_KEY_NAME" "$MC_TMP/key.b64"; then mc_fail_restore doppler_write_failed "the key write was refused (cf cert_id=${cf_id:-unknown} is unused)"; return 1; fi
  local got_k got_c
  # $(...) drops the trailing newline the CLI prints; the written value has none, so the digests are comparable.
  got_k="$(mc_get "$MC_DOPPLER_PROJECT" "$MC_PRD_CONFIG" "$MC_KEY_NAME")"; got_k="$(printf '%s' "$got_k" | sha256sum | cut -c1-64)"
  got_c="$(mc_get "$MC_DOPPLER_PROJECT" "$MC_PRD_CONFIG" "$MC_CERT_NAME")"; got_c="$(printf '%s' "$got_c" | sha256sum | cut -c1-64)"
  if [[ "$got_k" != "$want_k" || "$got_c" != "$want_c" ]]; then
    mc_fail_restore readback_mismatch "the values read back from prd differ from what was written (cf cert_id=${cf_id:-unknown} is unused)"
    return 1
  fi

  mc_say "verdict=minted cert_id=${cf_id:-unknown} serial=$MC_C_SERIAL not_after=$MC_C_NOT_AFTER days_left=$MC_C_DAYS cert_sha256=$(openssl x509 -in "$MC_TMP/cert.pem" -noout -fingerprint -sha256 2>/dev/null | sed 's/.*=//' | tr -d ':' | tr 'A-F' 'a-f') replaced_state=$MC_EX_STATE restart_required=true"
  mc_summary "### mint-origin-ca: minted. Serial \`$MC_C_SERIAL\`, valid until $MC_C_NOT_AFTER ($MC_C_DAYS days). Written to soleur/prd and read back. The containers load it at their next start; nothing was restarted. A replaced certificate ($MC_EX_STATE${MC_EX_SERIAL:+, serial $MC_EX_SERIAL}) was not revoked."
  return 0
}

main() {
  case "${1:-}" in
    guard) mc_guard ;;
    run)   mc_run ;;
    *)     printf 'usage: mint-origin-ca-cert.sh guard|run\n' >&2; return 64 ;;
  esac
}
# Sourceable for the suite's unit rows.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
