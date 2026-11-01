#!/usr/bin/env bash
# Follow-through soak for epic #6027 — GA LB pool health + serving evidence (AC4/AC11).
#
# After the ga-monitor-fix / ga-pool-update arms apply, asserts over the soak window
# [DEPLOY_TS, DEPLOY_TS+7d]:
#   (a) CF pool-health API reports every origin healthy:true,
#   (b) https://app.soleur.ai/health serves 200,
#   (c) zero new Better Stack incidents in the window.
#
# Exit semantics (sweep-followthroughs.sh contract):
#   0 = PASS       (all origins healthy + edge 200 + zero incidents in-window)
#   1 = FAIL       (any probe red — leave the tracker open, investigate)
#   2 = NOT YET    (deploy anchor absent/unparseable, or the window has not elapsed
#                   — the mirror of post-deploy-incident-soak.sh's anchor arm)
#   3 = TRANSIENT  (API/auth/parse failure — CANNOT ESTABLISH; retry next sweep)
#
# DEPLOY ANCHOR. The sweeper execs probes argv-free under `env -i`; the ONLY
# per-tracker channel is earliest= -> SOLEUR_FT_EARLIEST plus the declared
# secrets= names — DEPLOY_TS_EPOCH has no delivery channel under it. The
# directive's `earliest=<flip+7d>` is the soak window END (the
# post-deploy-incident-soak.sh convention), so deploy_ts = earliest - 7d. A
# manual run may pin DEPLOY_TS_EPOCH directly as an override.
#
# Required env (declare via secrets=): CF_API_TOKEN, CF_ACCOUNT_ID,
#   BETTERSTACK_API_TOKEN — the incident leg is REQUIRED (absent => TRANSIENT,
#   never a silent skip of a finding leg).
#
# RETIREMENT: retires when the #6027 tracker closes — nothing else consumes this
# probe. `gh issue list --label follow-through` first; a closed-within-lookback
# tracker still runs it.
set -uo pipefail

case "$-" in
  *x*)
    if [ -n "${CF_API_TOKEN:+x}${BETTERSTACK_API_TOKEN:+x}" ]; then
      printf '[FATAL] refusing to run under xtrace with a live credential set (see #7797).\n' >&2
      exit 78
    fi ;;
esac

export LC_ALL=C
# Same TLS-subversion prologue as betterstack-query.sh / the sibling probes: under
# the sweeper's env -i these are absent anyway; a local doppler run could set them.
unset SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR CURL_HOME HOSTALIASES LOCALDOMAIN RES_OPTIONS
export TMPDIR="${TMPDIR:-/var/tmp}"

_bearer_ok() { local LC_ALL=C; case "${1:-}" in ''|*[!A-Za-z0-9._~+/=-]*) return 1 ;; esac; }
transient() { printf '[TRANSIENT] %s\n' "$1" >&2; exit 3; }
notyet()    { printf '[NOT YET] %s\n'   "$1" >&2; exit 2; }

# ISO-8601 -> epoch. GNU `date -d` first, BSD/macOS `date -j -f` fallback — the
# sibling probe's conversion, verbatim.
iso_epoch() {
  date -u -d "$1" +%s 2>/dev/null && return 0
  date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null
}
epoch_day() {
  date -u -d "@$1" +%F 2>/dev/null || date -u -r "$1" +%F 2>/dev/null
}
# Canonical ISO-8601 UTC ONLY — earliest= is issue-body data any member can edit,
# and GNU `date -d` accepts natural-language single tokens ("now", "@epoch") that
# would silently move the window (post-deploy-incident-soak.sh precedent).
canonical_iso() { [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; }

command -v jq   >/dev/null 2>&1 || transient "jq not on PATH"
command -v curl >/dev/null 2>&1 || transient "curl not on PATH"

for v in CF_API_TOKEN CF_ACCOUNT_ID; do
  if [ -z "${!v:-}" ]; then transient "$v unset — cannot establish verdict (declare it in the directive's secrets=)"; fi
done
_bearer_ok "${CF_API_TOKEN:-}" || transient "CF_API_TOKEN fails shape guard"
# REQUIRED leg input, never a silent skip — but bound via ${VAR:-} so an absent
# secret exits 3 TRANSIENT instead of unbound-exit-1 under set -u (rc 1 reopens a
# closed tracker on a read fault).
_bearer_ok "${BETTERSTACK_API_TOKEN:-}" || transient "BETTERSTACK_API_TOKEN unset/bad shape — the incident leg cannot be established"

# ── Deploy anchor ─────────────────────────────────────────────────────────────
DEPLOY_TS_EPOCH="${DEPLOY_TS_EPOCH:-}"
if [[ -z "$DEPLOY_TS_EPOCH" ]]; then
  earliest="${SOLEUR_FT_EARLIEST:-}"
  [[ -n "$earliest" ]] || notyet "no deploy anchor — DEPLOY_TS_EPOCH unset and SOLEUR_FT_EARLIEST absent (under the sweeper, earliest=<flip+7d> is the window END)"
  canonical_iso "$earliest" || notyet "SOLEUR_FT_EARLIEST '${earliest}' is not canonical ISO-8601 UTC (YYYY-MM-DDTHH:MM:SSZ) — issue-body data is not trusted at read"
  earliest_epoch="$(iso_epoch "$earliest" || true)"
  [[ -n "${earliest_epoch:-}" ]] || notyet "SOLEUR_FT_EARLIEST '${earliest}' is not a parseable ISO timestamp"
  DEPLOY_TS_EPOCH=$(( earliest_epoch - 604800 ))
fi
case "$DEPLOY_TS_EPOCH" in ''|*[!0-9]*) transient "DEPLOY_TS_EPOCH '${DEPLOY_TS_EPOCH}' not epoch digits" ;; esac
END=$(( DEPLOY_TS_EPOCH + 604800 ))
NOW=$(date -u +%s)
if (( NOW < END )); then
  notyet "soak window [${DEPLOY_TS_EPOCH} .. ${END}] has not fully elapsed — the sweeper's earliest= gate should already have deferred this"
fi

fail=0
CF="https://api.cloudflare.com/client/v4/accounts/${CF_ACCOUNT_ID}"
UPTIME_HOST="uptime.betterstack.com"
WORK="$(mktemp -d -t soak6027.XXXXXXXX)" || transient "mktemp failed"
trap 'rm -rf "$WORK"' EXIT

# The bearer rides curl's stdin --config channel, never argv (#9597 Rule E).
cf_get() { # <url> -> body
  curl --disable --noproxy '*' -sf --max-time 10 --proto '=https' --max-redirs 0 \
    --config - "$1" \
    < <(printf 'header = "Authorization: Bearer %s"\n' "$CF_API_TOKEN")
}

# (a) pool health — every origin across every PoP must read healthy:true, and the
#     read must carry >= 1 origin record (an empty pop_health is an instrument
#     failure, not a vacuous PASS).
POOL_ID=$(cf_get "${CF}/load_balancers/pools" | jq -r '.result[] | select(.name=="web-1") | .id') || POOL_ID=""
[[ "$POOL_ID" =~ ^[0-9a-f]+$ ]] || transient "web-1 pool id unresolvable or off-shape ('${POOL_ID}') — refusing to re-interpolate it"
POOL_HEALTH=$(cf_get "${CF}/load_balancers/pools/${POOL_ID}/health") || transient "pool-health read failed"
ORIGINS=$(printf '%s' "$POOL_HEALTH" | jq -r '[.result.pop_health[].origins[][]] | length' 2>/dev/null || true)
case "$ORIGINS" in ''|*[!0-9]*) transient "pool-health payload unparseable" ;; esac
if [[ "$ORIGINS" -lt 1 ]]; then
  transient "pop_health carried no origin records — an empty set is not a verdict"
fi
UNHEALTHY=$(printf '%s' "$POOL_HEALTH" | jq '[.result.pop_health[].origins[][] | select(.healthy != true)] | length' 2>/dev/null || true)
case "$UNHEALTHY" in ''|*[!0-9]*) transient "pool-health unhealthy count unparseable" ;; esac
if [ "$UNHEALTHY" -gt 0 ]; then
  printf '[FAIL] %s origin(s) unhealthy in pool %s\n' "$UNHEALTHY" "$POOL_ID" >&2; fail=1
fi

# (b) edge serving — a transport failure (curl 000) is CANNOT ESTABLISH, not a red.
CODE=$(curl --disable --noproxy '*' -s -o /dev/null -w '%{http_code}' --max-time 8 \
  --proto '=https' --max-redirs 0 https://app.soleur.ai/health || echo 000)
if [ "$CODE" = "000" ]; then
  transient "edge probe transport failure (curl code 000) — serving evidence cannot be established"
fi
if [ "$CODE" != "200" ]; then
  printf '[FAIL] app.soleur.ai/health -> %s\n' "$CODE" >&2; fail=1
fi

# (c) incident window [DEPLOY_TS_EPOCH, +7d] — /api/v2/incidents takes from/to as
#     YYYY-MM-DD; page with per_page=50 and walk pagination.next (host-pinned), then
#     re-assert the window bounds client-side on attributes.started_at so a stubbed
#     or drifted page cannot smuggle an out-of-window row (post-deploy-incident-soak
#     .sh pattern). An unparseable started_at is a transport fault, never a verdict.
FROM_D=$(epoch_day "$DEPLOY_TS_EPOCH") || transient "could not render window start date"
TO_D=$(epoch_day "$END") || transient "could not render window end date"
[[ -n "$FROM_D" && -n "$TO_D" ]] || transient "could not render window dates"

url="https://${UPTIME_HOST}/api/v2/incidents?per_page=50&from=${FROM_D}&to=${TO_D}"
page=0
: > "$WORK/incidents.ndjson"
while [[ -n "$url" ]]; do
  page=$((page + 1))
  [[ "$page" -le 50 ]] || transient "incidents pagination exceeded 50 pages"
  case "$url" in
    "https://${UPTIME_HOST}/"*) ;;
    *) transient "refusing off-host pagination.next" ;;
  esac
  body=$(curl --disable --noproxy '*' -sS --max-time 10 --proto '=https' --max-redirs 0 \
    -H 'Accept: application/json' --config - "$url" \
    < <(printf 'header = "Authorization: Bearer %s"\n' "$BETTERSTACK_API_TOKEN")) \
    || transient "incidents read did not answer"
  printf '%s' "$body" | jq -e '.data | type == "array"' >/dev/null 2>&1 \
    || transient "incidents payload unparseable"
  printf '%s' "$body" | jq -c '.data[]' >> "$WORK/incidents.ndjson"
  url=$(printf '%s' "$body" | jq -r '.pagination.next // empty')
done
INCIDENTS=$(jq -s --argjson s "$DEPLOY_TS_EPOCH" --argjson e "$END" '
  [.[] | .attributes.started_at // ""]
  | if any(.[]; (. == "") or ((try (sub("\\.[0-9]+";"") | sub("\\+00:00$";"Z") | fromdateiso8601) catch null) == null))
    then error("unparseable started_at")
    else [.[] | (sub("\\.[0-9]+";"") | sub("\\+00:00$";"Z") | fromdateiso8601)
          | select(. >= $s and . <= $e)] | length
    end' "$WORK/incidents.ndjson" 2>/dev/null) || INCIDENTS=""
case "$INCIDENTS" in ''|*[!0-9]*) transient "incident window unparseable" ;; esac
if [ "$INCIDENTS" -gt 0 ]; then
  printf '[FAIL] %s Better Stack incident(s) in soak window\n' "$INCIDENTS" >&2; fail=1
fi

if [ "$fail" -eq 0 ]; then
  printf '[PASS] pool %s all origins healthy; edge 200; %d incidents in window\n' "$POOL_ID" "$INCIDENTS"
fi
exit "$fail"
