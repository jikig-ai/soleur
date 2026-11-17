#!/usr/bin/env bash
# bastion-egress.sh — the bastion's egress allowlist (#12866, ADR-327 step 2a; CTO ruling F2).
#
# Resolves the hostnames below and loads, in ONE `nft -f` transaction, the baseline ruleset
# (/etc/nftables.conf: input and output policy drop) plus a set of the resolved IPv4 addresses that
# the output chain may reach on tcp/443. Run by bastion-egress.service at boot and by
# bastion-egress.timer to follow address changes.
#
# TWO RULES TAKEN FROM cron-egress-resolve.sh, NOT ITS 1,024 LINES:
#   1. one atomic swap: the baseline and the set load together, so the host is never between them;
#   2. a failed lookup never empties the set: any lookup failure exits non-zero BEFORE `nft` runs,
#      leaving whatever ruleset is loaded (the baseline at boot, the last good set on a refresh).
# This file is NOT rendered from the web script, so a web egress edit never replaces the bastion.
#
# EVERY HOSTNAME CITES ITS CONSUMER ON THE BASTION (`soleur-egress: <unit or file>`); bastion.test.sh
# rejects an uncited row and a citation the render does not install.
set -euo pipefail

ENV_FILE="${BASTION_EGRESS_ENV:-/etc/soleur/bastion-egress.env}"
BASELINE="${BASTION_EGRESS_BASELINE:-/etc/nftables.conf}"

# <hostname> soleur-egress: <consumer>. @SENTRY_INGEST_HOST@ is read from $ENV_FILE (rendered from
# var.sentry_dsn), so a DSN rotation is a replace input, not a script edit.
ALLOW='
archive.ubuntu.com    soleur-egress: /etc/apt/sources.list.d/ubuntu.sources
security.ubuntu.com   soleur-egress: /etc/apt/sources.list.d/ubuntu.sources
@SENTRY_INGEST_HOST@  soleur-egress: cloud-init
'

log() { printf '[bastion-egress] %s\n' "$*"; }
die() { printf '[bastion-egress] FAIL: %s; the loaded ruleset is unchanged\n' "$*" >&2; exit 1; }

command -v nft >/dev/null || die "nft binary not found"
[[ -s "$BASELINE" ]] || die "baseline $BASELINE is missing"
[[ -r "$ENV_FILE" ]] || die "env file $ENV_FILE is missing"
SENTRY_INGEST_HOST="$(sed -n 's/^SENTRY_INGEST_HOST=//p' "$ENV_FILE" | head -1)"
[[ "$SENTRY_INGEST_HOST" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]] || die "SENTRY_INGEST_HOST='${SENTRY_INGEST_HOST}' is not a hostname"

ips=""
while read -r host cite consumer; do
  [[ -z "${host:-}" ]] && continue
  [[ "$cite" == "soleur-egress:" && -n "${consumer:-}" ]] || die "allowlist row '${host}' carries no soleur-egress citation"
  [[ "$host" == "@SENTRY_INGEST_HOST@" ]] && host="$SENTRY_INGEST_HOST"
  got="$(timeout 10 getent ahostsv4 "$host" 2>/dev/null | awk '{print $1}' | sort -u || true)"
  [[ -n "$got" ]] || die "lookup failed for ${host} (${consumer})"
  while read -r ip; do
    [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || die "lookup for ${host} returned '${ip}', not an IPv4 address"
    ips="${ips:+$ips, }$ip"
  done <<<"$got"
done <<<"$ALLOW"
[[ -n "$ips" ]] || die "the allowlist resolved to nothing"

BATCH="include \"${BASELINE}\"
add set inet soleur_bastion soleur_egress_allow { type ipv4_addr; }
add element inet soleur_bastion soleur_egress_allow { ${ips} }
add rule inet soleur_bastion output ip daddr @soleur_egress_allow tcp dport 443 accept comment \"soleur-egress: bastion-egress.service\"
"
printf '%s' "$BATCH" | nft -c -f - || die "the batch failed nft -c"
printf '%s' "$BATCH" | nft -f - || die "nft -f failed"
log "OK: baseline plus ${ips} on tcp/443"
