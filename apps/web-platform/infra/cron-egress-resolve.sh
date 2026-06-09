#!/usr/bin/env bash
# cron-egress-resolve.sh — maintain the nftables egress allowlist sets
# (#5046 PR-2 / cron-egress-firewall).
#
# Resolves every host in /etc/soleur/cron-egress-allowlist.txt (plus the
# doppler-provided dynamic hosts: SENTRY_INGEST_DOMAIN, the Supabase URL
# hosts) to IPv4 addresses and reconciles the nftables sets
# @soleur_egress_allow / @soleur_egress_dns in table `ip filter`.
#
# Hard conditions (plan §Phase 2.B, arch-confirmed):
#   - ADDITIVE-THEN-PRUNE, ATOMICALLY: adds and deletes are emitted in ONE
#     `nft -f` transaction (no intermediate empty-set window). NEVER
#     `flush set` + repopulate.
#   - FAIL-SAFE ON EMPTY: if resolution yields ZERO addresses (transient DNS
#     outage), abort WITHOUT pruning — a frozen set beats an empty one.
#   - PARTIAL-FAILURE = ADDITIVE-ONLY: if ANY host failed to resolve this
#     tick, skip ALL deletes (its previous IPs must survive until it
#     resolves again).
#   - The timer-unit failure alarms via OnFailure= (cron-egress-alarm.service)
#     AND this script posts a Sentry Crons check-in (slug
#     cron-egress-resolve) so a DEAD timer surfaces as a missed check-in.
#
# Runs doppler-wrapped (prd config) so SENTRY_* / SUPABASE_* / RESEND_API_KEY
# are present; every env read degrades gracefully when absent (dev hosts).
set -euo pipefail

ALLOWLIST_FILE="${ALLOWLIST_FILE:-/etc/soleur/cron-egress-allowlist.txt}"
ALLOW_SET="soleur_egress_allow"
DNS_SET="soleur_egress_dns"
CONTAINER="soleur-web-platform"
SENTRY_SLUG="cron-egress-resolve"
LOG_TAG="cron-egress-resolve"

log() { echo "[$LOG_TAG] $*"; }

# --- Sentry Crons check-in (mirrors postSentryHeartbeat, _cron-shared.ts) ---
sentry_checkin() {
  local status="$1"
  local domain="${SENTRY_INGEST_DOMAIN:-}"
  local project="${SENTRY_PROJECT_ID:-}"
  local key="${SENTRY_PUBLIC_KEY:-}"
  if [[ -z "$domain" || -z "$project" || -z "$key" ]]; then
    log "WARN: Sentry env unset — skipping ${status} check-in"
    return 0
  fi
  curl -s -o /dev/null --max-time 10 -X POST \
    "https://${domain}/api/${project}/cron/${SENTRY_SLUG}/${key}/?status=${status}" \
    || log "WARN: Sentry check-in POST failed (status=${status})"
}

fail() {
  log "ERROR: $*"
  sentry_checkin error
  exit 1
}

command -v nft >/dev/null || fail "nft binary not found"
command -v jq >/dev/null || fail "jq binary not found"

# --- Gather hostnames ---------------------------------------------------------
HOSTS=()
if [[ -f "$ALLOWLIST_FILE" ]]; then
  while IFS= read -r line; do
    line="${line%%#*}"
    line="$(echo "$line" | tr -d '[:space:]')"
    [[ -n "$line" ]] && HOSTS+=("$line")
  done < "$ALLOWLIST_FILE"
else
  fail "allowlist file missing: $ALLOWLIST_FILE"
fi

# Dynamic hosts from the doppler env (operator-configured; not hardcodable).
extract_host() { echo "$1" | sed -E 's|^[a-z+]+://||; s|/.*$||; s|:.*$||'; }
[[ -n "${SENTRY_INGEST_DOMAIN:-}" ]] && HOSTS+=("$SENTRY_INGEST_DOMAIN")
[[ -n "${NEXT_PUBLIC_SUPABASE_URL:-}" ]] && HOSTS+=("$(extract_host "$NEXT_PUBLIC_SUPABASE_URL")")
[[ -n "${SUPABASE_URL:-}" ]] && HOSTS+=("$(extract_host "$SUPABASE_URL")")

[[ ${#HOSTS[@]} -gt 0 ]] || fail "no hosts to resolve (empty allowlist)"

# --- Resolve -------------------------------------------------------------------
DESIRED_ALLOW=""
FAILED_HOSTS=0
for host in $(printf '%s\n' "${HOSTS[@]}" | sort -u); do
  # getent ahostsv4 uses the HOST resolver (the same path the re-resolve
  # cadence argument assumes: cadence ≪ SaaS DNS TTL → fail-loud, not silent).
  ips="$(timeout 10 getent ahostsv4 "$host" 2>/dev/null | awk '{print $1}' | sort -u || true)"
  if [[ -z "$ips" ]]; then
    log "WARN: could not resolve $host (keeping its previous addresses)"
    FAILED_HOSTS=$((FAILED_HOSTS + 1))
    continue
  fi
  DESIRED_ALLOW+="$ips"$'\n'
done
DESIRED_ALLOW="$(echo "$DESIRED_ALLOW" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort -u || true)"

# FAIL-SAFE: never operate against a fully-empty resolution (DNS outage).
[[ -n "$DESIRED_ALLOW" ]] || fail "resolution returned ZERO addresses — refusing to touch the sets (fail-safe)"

# --- DNS resolver pin set ------------------------------------------------------
# The container's own resolvers (Docker default bridge copies the host's
# resolv.conf, substituting 8.8.8.8/8.8.4.4 when the host's are loopback-only).
DNS_IPS=""
if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$CONTAINER"; then
  DNS_IPS="$(docker exec "$CONTAINER" cat /etc/resolv.conf 2>/dev/null | awk '/^nameserver/ {print $2}' || true)"
fi
if [[ -z "$DNS_IPS" && -r /run/systemd/resolve/resolv.conf ]]; then
  DNS_IPS="$(awk '/^nameserver/ {print $2}' /run/systemd/resolve/resolv.conf)"
fi
[[ -z "$DNS_IPS" ]] && DNS_IPS=$'8.8.8.8\n8.8.4.4'
DNS_IPS="$(echo "$DNS_IPS" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort -u || true)"
[[ -n "$DNS_IPS" ]] || fail "no IPv4 resolver to pin"

# --- Reconcile (one atomic nft -f transaction) ---------------------------------
current_set() {
  nft -j list set ip filter "$1" 2>/dev/null \
    | jq -r '.nftables[]?.set?.elem?[]? | if type == "object" then .elem.val else . end' \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort -u || true
}

build_batch() {
  local set_name="$1" desired="$2" prune="$3"
  local current adds dels
  current="$(current_set "$set_name")"
  adds="$(comm -23 <(echo "$desired") <(echo "$current") | paste -sd, -)"
  dels="$(comm -13 <(echo "$desired") <(echo "$current") | paste -sd, -)"
  [[ -n "$adds" ]] && echo "add element ip filter $set_name { $adds }"
  if [[ "$prune" == "prune" && -n "$dels" ]]; then
    echo "delete element ip filter $set_name { $dels }"
  fi
  return 0
}

PRUNE="prune"
if [[ "$FAILED_HOSTS" -gt 0 ]]; then
  log "WARN: $FAILED_HOSTS host(s) failed to resolve — ADDITIVE-ONLY tick (no prune)"
  PRUNE="no-prune"
fi

BATCH="$(
  build_batch "$ALLOW_SET" "$DESIRED_ALLOW" "$PRUNE"
  build_batch "$DNS_SET" "$DNS_IPS" "$PRUNE"
)"

if [[ -n "$BATCH" ]]; then
  echo "$BATCH" | nft -f - || fail "nft batch apply failed"
  log "applied: $(echo "$BATCH" | tr '\n' ' ' | cut -c1-400)"
else
  log "sets already converged (no changes)"
fi

# --- Fail-loud: surface kernel egress-blocked drops to Sentry -------------------
# The nftables default-drop logs to the KERNEL journal (host pipeline → Better
# Stack), which Sentry issue alerting cannot see. Each tick, count fresh drops
# and post ONE Sentry error event tagged feature=cron-egress-firewall /
# op=egress_blocked — the issue-alerts.tf `egress_blocked` alert pages on it
# (AC-P2.10). Sample lines carry only kernel packet metadata (IPs/ports), no
# payload and no secrets.
BLOCK_HITS="$(journalctl -k --since "-5min" --no-pager 2>/dev/null | grep -c 'egress-blocked: ' || true)"
if [[ "${BLOCK_HITS:-0}" -gt 0 ]]; then
  log "WARN: $BLOCK_HITS egress-blocked drop(s) in the last 5m"
  if [[ -n "${SENTRY_INGEST_DOMAIN:-}" && -n "${SENTRY_PROJECT_ID:-}" && -n "${SENTRY_PUBLIC_KEY:-}" ]]; then
    SAMPLE="$(journalctl -k --since "-5min" --no-pager 2>/dev/null | grep 'egress-blocked: ' | tail -3 | tr '"' "'" | tr '\n' ';' | cut -c1-500)"
    PAYLOAD="$(jq -n \
      --arg msg "egress-blocked: container egress denied (${BLOCK_HITS} hits in last 5m)" \
      --arg sample "$SAMPLE" \
      --argjson hits "$BLOCK_HITS" \
      '{message: $msg, level: "error", platform: "other", logger: "cron-egress-resolve",
        tags: {feature: "cron-egress-firewall", op: "egress_blocked"},
        extra: {sample: $sample, hits: $hits}}')"
    curl -s -o /dev/null --max-time 10 -X POST \
      "https://${SENTRY_INGEST_DOMAIN}/api/${SENTRY_PROJECT_ID}/store/" \
      -H "Content-Type: application/json" \
      -H "X-Sentry-Auth: Sentry sentry_version=7, sentry_key=${SENTRY_PUBLIC_KEY}" \
      -d "$PAYLOAD" \
      || log "WARN: egress_blocked Sentry event POST failed"
  else
    log "WARN: Sentry env unset — egress_blocked event not posted"
  fi
fi

sentry_checkin ok
log "OK: allow=$(echo "$DESIRED_ALLOW" | wc -l) addrs, dns=$(echo "$DNS_IPS" | wc -l) resolvers, failed_hosts=$FAILED_HOSTS, blocked_5m=$BLOCK_HITS"
