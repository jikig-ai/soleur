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
# GHCR carve (#9275): GitHub's dedicated Packages frontends (/meta `.packages`,
# which serve ghcr.io and docker.pkg.github.com) sit INSIDE the .git ranges, so
# they are subtracted from the allow list at /32 granularity (bash + jq only; the
# Inngest cron runs this inside the app container, no python). A "hole" is a
# `.packages` IPv4 entry that is not an exact .git/.web/.api member and whose
# prefix is /28 or longer; each hole that overlaps the allow list is "effective"
# and is recorded as one header line in the output file, exactly:
#   # Excluded (GitHub Packages frontends): <cidr>
# Consumers (post-apply assertion, resolver sampler, tests) grep that one pattern;
# the loader ignores comments. /meta is untrusted input: holes shorter than /28
# or with leading-zero octets are skipped with a WARN, more than 64 effective
# holes or more than 2048 output lines die, and a DNS-sanity guard refuses to
# write when github.com / api.github.com currently resolves inside a hole (a die
# freezes the daily refresh; the stale file keeps serving).
#
# Usage:
#   gen-github-egress-cidr.sh            # fetch live /meta, write the file (no-op if unchanged)
#   gen-github-egress-cidr.sh --check    # exit 0 if committed file == fresh gen, 1 on drift
#   META_JSON_FILE=fixture.json gen-...  # read /meta from a file (test/offline)
#   OUT=/path/to/file gen-...            # override the output path (tests)
set -euo pipefail
# sort/comm ordering must not depend on the caller's locale (the cron's minimal
# env differs from a developer shell; a mismatch is a perpetual drift PR).
export LC_ALL=C

MAX_HOLES=64     # effective holes above this: unexpected /meta shape -> die
MAX_OUT=2048     # emitted prefixes above this: unexpected shape -> die
MIN_HOLE_PFX=28  # holes shorter than /28 are skipped (a /8 hole would delete the ranges github.com lives in)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${OUT:-$SCRIPT_DIR/../cron-egress-allowlist-cidr.txt}"
META_URL="https://api.github.com/meta"
META_JSON_FILE="${META_JSON_FILE:-}"
MODE="write"
[[ "${1:-}" == "--check" ]] && MODE="check"

log() { echo "[gen-github-egress-cidr] $*" >&2; }
die() { log "ERROR: $*"; exit 1; }
warn() { log "WARN: $*"; }

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
# .packages drives the carve: absent / not an array of strings -> refuse to write a
# file that silently stops carving. .web is optional ((.web // []) below), so it is
# only shape-checked when present.
echo "$meta_json" | jq -e '(.packages|type)=="array" and all(.packages[]; type=="string")' >/dev/null 2>&1 \
  || die "/meta .packages missing or not an array of strings (schema change; refusing to write a file that silently stops carving)"
echo "$meta_json" | jq -e '((.web // [])|type)=="array"' >/dev/null 2>&1 \
  || die "/meta .web is present but not an array (schema change)"

# 2. EXTRACT — verbatim filter (matches the file header + the runbook recipe;
#    select(test(":")|not) drops the IPv6 entries). AC2 pins this string.
mapfile -t cidrs < <(echo "$meta_json" | jq -r '(.git+.api)[]|select(test(":")|not)' | sort -u)

# 3. GUARD non-empty (a truncated /meta or an IPv6-only response must not blank the file).
[[ "${#cidrs[@]}" -gt 0 ]] || die "empty extraction (truncated /meta or IPv6-only) — refusing to blank the file"
[[ "${#cidrs[@]}" -le "$MAX_OUT" ]] || die "extraction has ${#cidrs[@]} ranges (> $MAX_OUT; unexpected /meta shape)"

# 4. VALIDATE every line + reject over-broad prefixes. Both this validator and
#    the loader's are SHAPE validators that accept a structurally-valid 0.0.0.0/0;
#    the prefix-floor (>= /8) is the breadth defense the one allow-all vector needs.
validate_allow() {
  local cidr prefix
  for cidr in "$@"; do
    is_valid_ipv4_cidr "$cidr" || die "invalid CIDR from /meta: '$cidr' (reject-whole-file; refusing to write a partial)"
    prefix="${cidr##*/}"
    (( prefix >= 8 )) || die "over-broad CIDR from /meta: '$cidr' (prefix < /8 — allow-all egress vector)"
  done
}
validate_allow "${cidrs[@]}"

# 5. CARVE the GitHub Packages frontends (#9275). Integer math only; every octet
#    and prefix goes through 10# so a leading zero can never read as octal.
CP_LO=0; CP_HI=0; CP_PFX=0
cidr_parse() { # $1 validated a.b.c.d/p -> CP_LO/CP_HI (aligned network bounds), CP_PFX
  local ip="${1%/*}" o1 o2 o3 o4 size
  IFS=. read -r o1 o2 o3 o4 <<< "$ip"
  CP_PFX=$(( 10#${1##*/} ))
  size=$(( 1 << (32 - CP_PFX) ))
  CP_LO=$(( ((10#$o1 << 24) | (10#$o2 << 16) | (10#$o3 << 8) | 10#$o4) & ~(size - 1) & 0xFFFFFFFF ))
  CP_HI=$(( CP_LO + size - 1 ))
}
INT_IP=""
int_to_ip() { INT_IP="$(( ($1 >> 24) & 255 )).$(( ($1 >> 16) & 255 )).$(( ($1 >> 8) & 255 )).$(( $1 & 255 ))"; }

# Pure address-exclude of ONE hole from ONE allow prefix; appends the surviving
# prefixes to NEXT. Disjoint -> kept verbatim; hole covers the prefix -> dropped;
# hole strictly inside -> halve the prefix toward the hole, keeping the sibling
# half at each level (the CIDR remainder).
HOLE_LO=(); HOLE_HI=(); HOLE_PFX=(); NEXT=()
carve_one() { # $1 allow cidr, $2 hole index
  local h_lo="${HOLE_LO[$2]}" h_hi="${HOLE_HI[$2]}" h_pfx="${HOLE_PFX[$2]}" a_lo a_hi cur_lo pfx half
  cidr_parse "$1"; a_lo=$CP_LO; a_hi=$CP_HI; pfx=$CP_PFX
  if (( a_hi < h_lo || h_hi < a_lo )); then NEXT+=("$1"); return 0; fi
  if (( h_lo <= a_lo && a_hi <= h_hi )); then return 0; fi
  cur_lo=$a_lo
  while (( pfx < h_pfx )); do
    pfx=$(( pfx + 1 )); half=$(( 1 << (32 - pfx) ))
    if (( h_lo < cur_lo + half )); then
      int_to_ip $(( cur_lo + half )); NEXT+=("$INT_IP/$pfx")
    else
      int_to_ip "$cur_lo"; NEXT+=("$INT_IP/$pfx"); cur_lo=$(( cur_lo + half ))
    fi
  done
}

exclude_holes() { # carves every HOLE_* entry out of the cidrs array
  local i c
  for (( i = 0; i < ${#HOLE_LO[@]}; i++ )); do
    NEXT=()
    for c in "${cidrs[@]}"; do carve_one "$c" "$i"; done
    cidrs=(${NEXT[@]+"${NEXT[@]}"})
    [[ "${#cidrs[@]}" -le "$MAX_OUT" ]] || die "carve produced ${#cidrs[@]} ranges (> $MAX_OUT; unexpected /meta shape)"
  done
}

# holes = .packages IPv4 minus EXACT .git/.web/.api members (an entry /meta lists
# as the same range for git/api, the 20.217.135.1/32 shape, is never carved).
mapfile -t pkg_holes < <(comm -23 \
  <(echo "$meta_json" | jq -r '.packages[]|select(test(":")|not)' | sort -u) \
  <(echo "$meta_json" | jq -r '(.git+(.web // [])+.api)[]|select(test(":")|not)' | sort -u))
pkg_v4_n="$(echo "$meta_json" | jq -r '[.packages[]|select(test(":")|not)]|length')"
[[ "$pkg_v4_n" -gt 0 ]] || die "/meta .packages has no IPv4 entries (schema change; refusing to write a file that silently stops carving)"

A_LO=(); A_HI=()
for cidr in "${cidrs[@]}"; do cidr_parse "$cidr"; A_LO+=("$CP_LO"); A_HI+=("$CP_HI"); done

eff_lines=""   # canonical effective holes, one per line (sorted, unique below)
for hole in ${pkg_holes[@]+"${pkg_holes[@]}"}; do
  # a leading-zero octet/prefix is ambiguous (inet_aton reads octal): never apply it
  if [[ "$hole" =~ (^|[./])0[0-9] ]]; then
    warn "skipping non-canonical Packages entry '$hole' (leading-zero octet or prefix)"; continue
  fi
  is_valid_ipv4_cidr "$hole" || die "invalid CIDR in /meta .packages: '$hole' (reject-whole-file; refusing to write a partial)"
  cidr_parse "$hole"
  if (( CP_PFX < MIN_HOLE_PFX )); then
    warn "skipping Packages entry '$hole' (prefix shorter than /$MIN_HOLE_PFX; would delete allow ranges)"; continue
  fi
  overlaps=0
  for (( i = 0; i < ${#A_LO[@]}; i++ )); do
    if (( ! (A_HI[i] < CP_LO || CP_HI < A_LO[i]) )); then overlaps=1; break; fi
  done
  (( overlaps )) || continue   # outside every allow prefix: nothing to carve
  int_to_ip "$CP_LO"; eff_lines+="$INT_IP/$CP_PFX"$'\n'
done
eff_holes=()
if [[ -n "$eff_lines" ]]; then mapfile -t eff_holes < <(printf '%s' "$eff_lines" | sort -u); fi
[[ "${#eff_holes[@]}" -le "$MAX_HOLES" ]] || die "${#eff_holes[@]} effective Packages holes (> $MAX_HOLES; unexpected /meta shape)"

for hole in ${eff_holes[@]+"${eff_holes[@]}"}; do
  cidr_parse "$hole"; HOLE_LO+=("$CP_LO"); HOLE_HI+=("$CP_HI"); HOLE_PFX+=("$CP_PFX")
done

if [[ "${#eff_holes[@]}" -eq 0 ]]; then
  warn "no effective Packages holes (every .packages entry is outside the allow list, an exact .git/.web/.api member, or skipped): writing the uncarved allow list; the runtime probe is the control"
else
  # DNS sanity: if github.com / api.github.com currently resolves INSIDE a hole the
  # carve would cut GitHub itself. Only a lookup that SUCCEEDS and lands in a hole
  # dies; a failed or absent lookup only warns (guard degrades; the probe covers it).
  if command -v getent >/dev/null; then
    for name in github.com api.github.com; do
      ans=""
      if command -v timeout >/dev/null; then
        ans="$(timeout 10 getent ahostsv4 "$name" 2>/dev/null)" || ans=""
      else
        ans="$(getent ahostsv4 "$name" 2>/dev/null)" || ans=""
      fi
      if [[ -z "$ans" ]]; then
        warn "DNS-sanity lookup of $name failed or returned nothing (guard skipped for this name)"; continue
      fi
      while read -r ip _; do
        is_valid_ipv4_cidr "$ip/32" || continue
        cidr_parse "$ip/32"
        for (( i = 0; i < ${#HOLE_LO[@]}; i++ )); do
          if (( CP_LO >= HOLE_LO[i] && CP_LO <= HOLE_HI[i] )); then
            die "ghcr-carve-would-cut-github: $name resolves to $ip inside an excluded Packages hole (refusing to write; stale file keeps serving)"
          fi
        done
      done <<< "$ans"
    done
  else
    warn "getent not found: DNS-sanity guard skipped (the runtime probe is the control)"
  fi
  exclude_holes
fi

# Re-validate EVERY emitted prefix (loader parity + the >= /8 floor), dedupe, cap.
mapfile -t cidrs < <(printf '%s\n' "${cidrs[@]}" | sort -u)
[[ "${#cidrs[@]}" -gt 0 ]] || die "carve left no ranges — refusing to blank the file"
[[ "${#cidrs[@]}" -le "$MAX_OUT" ]] || die "output has ${#cidrs[@]} ranges (> $MAX_OUT; unexpected /meta shape)"
validate_allow "${cidrs[@]}"

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
# Carve (#9275): the GitHub Packages frontends (/meta \`.packages\`: ghcr.io and
# docker.pkg.github.com) are subtracted from that union at /32 granularity, except
# exact .git/.web/.api members. Each subtracted frontend range is listed below as
# one 'Excluded' header line (no allow range is hand-narrowed; see the generator).
#
# Snapshot: api.github.com/meta \`.git\` + \`.api\` minus the Packages frontends, $count IPv4 ranges.
EOF
  local h
  for h in ${eff_holes[@]+"${eff_holes[@]}"}; do
    printf '# Excluded (GitHub Packages frontends): %s\n' "$h"
  done
  printf '# Generated: %s\n' "$d"
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

# 5. WRITE atomically: mktemp IN THE TARGET DIR (cross-device mv loses atomicity),
#    EXIT trap removes the temp on any failure, mv -f is the atomic swap.
#    Precedent: infra-config-install.sh:118,127.
snapshot="$(date -u +%F)"
tmp="$(mktemp "${OUT}.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
emit_file "$snapshot" > "$tmp"
mv -f "$tmp" "$OUT"
log "wrote $OUT ($count ranges, snapshot $snapshot)"
