#!/usr/bin/env bash
# gen-github-egress-cidr.sh — regenerate cron-egress-allowlist-cidr.txt from
# GitHub /meta (#5284). Idempotent + fail-loud. DO NOT hand-edit the output file.
#
# Replaces the hand-snapshotted CIDR list so the container egress firewall
# self-heals when GitHub rotates its api.github.com Azure 20.x/4.x /32 LB pool
# (the failure mode behind Sentry incident 5516336). The committed file stays the
# source of truth; the Inngest cron `cron-github-cidr-refresh` runs this script on
# a schedule and opens a direct-merge PR on drift, after which the existing
# terraform_data.cron_egress_firewall apply path re-provisions the firewall.
#
# Usage:
#   gen-github-egress-cidr.sh            # fetch live /meta, write the file (no-op if unchanged)
#   gen-github-egress-cidr.sh --check    # exit 0 if committed file == fresh gen, 1 on drift
#   META_JSON_FILE=fixture.json gen-...  # read /meta from a file (test/offline)
#   OUT=/path/to/file gen-...            # override the output path (tests)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${OUT:-$SCRIPT_DIR/../cron-egress-allowlist-cidr.txt}"
META_URL="https://api.github.com/meta"
META_JSON_FILE="${META_JSON_FILE:-}"
MODE="write"
[[ "${1:-}" == "--check" ]] && MODE="check"

log() { echo "[gen-github-egress-cidr] $*" >&2; }
die() { log "ERROR: $*"; exit 1; }

# Strict IPv4-CIDR validator — byte-identical to the loader's is_valid_ipv4_cidr
# (cron-egress-nftables.sh:70-80, #5268/#5242). Reused verbatim so a line this
# generator emits can never be one the loader later die()s on (or vice-versa).
is_valid_ipv4_cidr() {
  local cidr="$1" prefix o1 o2 o3 o4
  [[ "$cidr" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})/([0-9]{1,2})$ ]] || return 1
  o1=${BASH_REMATCH[1]}; o2=${BASH_REMATCH[2]}; o3=${BASH_REMATCH[3]}
  o4=${BASH_REMATCH[4]}; prefix=${BASH_REMATCH[5]}
  (( o1 <= 255 && o2 <= 255 && o3 <= 255 && o4 <= 255 && prefix <= 32 )) || return 1
  return 0
}

command -v jq >/dev/null || die "jq not found (apt-get install jq)"

# 1. FETCH (fail-loud). -f → non-2xx is a hard error (no partial body);
#    --max-time bounds the hang (2026-04-28 network-timeout learning).
if [[ -n "$META_JSON_FILE" ]]; then
  [[ -f "$META_JSON_FILE" ]] || die "META_JSON_FILE not found: $META_JSON_FILE"
  meta_json="$(cat "$META_JSON_FILE")"
else
  command -v curl >/dev/null || die "curl not found"
  meta_json="$(curl -fsS --max-time 30 "$META_URL")" || die "fetch $META_URL failed"
fi

# Shape guard: a truncated or schema-changed /meta that lacks .git/.api must fail
# loud rather than silently produce an empty extraction.
echo "$meta_json" | jq -e 'has("git") and has("api")' >/dev/null 2>&1 \
  || die "/meta missing .git/.api keys (truncated body or schema change)"

# 2. EXTRACT — verbatim filter (matches the file header + the runbook recipe;
#    select(test(":")|not) drops the IPv6 entries). AC2 pins this string.
mapfile -t cidrs < <(echo "$meta_json" | jq -r '(.git+.api)[]|select(test(":")|not)' | sort -u)

# 4. GUARD non-empty (a truncated /meta or an IPv6-only response must not blank the file).
[[ "${#cidrs[@]}" -gt 0 ]] || die "empty extraction (truncated /meta or IPv6-only) — refusing to blank the file"

# 3. VALIDATE every line + reject over-broad prefixes. Both this validator and
#    the loader's are SHAPE validators that accept a structurally-valid 0.0.0.0/0;
#    the prefix-floor (>= /8) is the breadth defense the one allow-all vector needs.
for cidr in "${cidrs[@]}"; do
  is_valid_ipv4_cidr "$cidr" || die "invalid CIDR from /meta: '$cidr' (reject-whole-file; refusing to write a partial)"
  prefix="${cidr##*/}"
  (( prefix >= 8 )) || die "over-broad CIDR from /meta: '$cidr' (prefix < /8 — allow-all egress vector)"
done

count="${#cidrs[@]}"

# Emit the full file content for a given Generated: date. The header is static
# (only the count tracks the body, and the Generated: date is normalized away for
# the no-op comparison below) so a no-op refresh produces a byte-identical file.
emit_file() {
  local d="$1"
  cat <<EOF
# Container egress CIDR allowlist (cron-egress-firewall; GitHub LB-range fix).
# DO NOT EDIT — regenerate via apps/web-platform/infra/scripts/gen-github-egress-cidr.sh
# (auto-refreshed on GitHub /meta rotation by the cron-github-cidr-refresh Inngest cron, #5284).
#
# One IPv4 CIDR per line; '#' comments and blank lines ignored. These are loaded
# by cron-egress-nftables.sh into the 'soleur_egress_allow_cidr' interval set and
# accepted by a dedicated SOLEUR-EGRESS rule. The crons dial BOTH github.com (git
# clone) AND api.github.com (App-token mint + REST audit). api.github.com
# round-robins DNS across the big git/pages blocks AND a rotating pool of Azure
# 20.x/4.x /32 hosts; an uncovered rotated IP is default-dropped -> no GitHub call
# -> no Sentry heartbeat -> missed cron check-in (incident 5516336,
# scheduled-ruleset-bypass-audit, 2026-06-14).
#
# Source: https://api.github.com/meta  (.git + .api IPv4 union; IPv6 dropped)
#   curl -fsS --max-time 30 https://api.github.com/meta \\
#     | jq -r '(.git+.api)[]|select(test(":")|not)' | sort -u
#
# Snapshot: api.github.com/meta \`.git\` + \`.api\`, $count IPv4 ranges.
# Generated: $d
EOF
  printf '%s\n' "${cidrs[@]}"
}

# The Generated: date is the only volatile header field; normalize it away so the
# no-op / drift decision is made on the BODY + static header only. Without this a
# no-op refresh would restamp the date daily -> a daily spurious PR + config_hash
# churn (deepen-pass correction; AC7b).
normalize_date() { sed -E 's/^# Generated: [0-9]{4}-[0-9]{2}-[0-9]{2}$/# Generated: <DATE>/'; }

fresh_canonical="$(emit_file '<DATE>')"

if [[ "$MODE" == "check" ]]; then
  [[ -f "$OUT" ]] || { log "drift: $OUT does not exist"; exit 1; }
  if [[ "$fresh_canonical" == "$(normalize_date < "$OUT")" ]]; then
    exit 0
  fi
  log "drift: committed file != fresh /meta generation"
  exit 1
fi

# Write mode: no-op when nothing but the date would change.
if [[ -f "$OUT" && "$fresh_canonical" == "$(normalize_date < "$OUT")" ]]; then
  log "no-op: $OUT already current ($count ranges; date not advanced)"
  exit 0
fi

# 6. WRITE atomically: mktemp IN THE TARGET DIR (cross-device mv loses atomicity),
#    EXIT trap removes the temp on any failure, mv -f is the atomic swap.
#    Precedent: infra-config-install.sh:118,127.
snapshot="$(date -u +%F)"
tmp="$(mktemp "${OUT}.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
emit_file "$snapshot" > "$tmp"
mv -f "$tmp" "$OUT"
log "wrote $OUT ($count ranges, snapshot $snapshot)"
