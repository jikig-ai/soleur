#!/usr/bin/env bash
# rundevoo-dns-set-equality.sh — whole-list DNS drift probe for rundevoo.run
# (#12971).
#
# Usage: rundevoo-dns-set-equality.sh <terraform-show-json-file>
#   Env:   CLOUDFLARE_API_TOKEN — the zone-scoped token (CF_API_TOKEN_RUNDEVOO
#          in Doppler prd_terraform). NO fallback to a broader credential: the
#          whole point of the comparison is bounded reach, and a silently
#          wider token would be the defect this probe exists to find.
#   exit 0: the live record set equals the Terraform-managed set exactly
#   exit 1: any unmanaged live record, any managed record missing live,
#           incomplete enumeration, or a failed API call — fail closed
#
# WHY THIS EXISTS. `terraform plan` — even with refresh — can only compare
# state UNION config. A DNS record added out-of-band in the Cloudflare
# dashboard is in NEITHER set, so no plan will ever see it: the parked zone
# could acquire an A record serving arbitrary content under a company-owned
# name while every drift leg stays green. Only a REST enumeration of the
# complete live record set covers that direction. `dig` is not a substitute —
# it cannot enumerate records.
#
# MANAGED SET is read from `terraform show -json` of the RECORDED state (the
# drift leg passes the state capture, not a plan file): resources of
# type `cloudflare_record` that Terraform is managing. A record declared in
# config but never applied is not "managed" — the plan leg already covers the
# config-vs-live direction.
#
# KNOWN LIVE-ONLY MEMBERS. Cloudflare auto-manages the apex NS records
# (the zone's authoritative nameservers): they exist in the live record list
# and are NEVER Terraform resources. Enabling DNSSEC also causes Cloudflare
# to auto-publish apex CDS and CDNSKEY records (RFC 8078 — Registrar zones
# rely on them for automatic DS propagation), which likewise never appear in
# terraform state. All three are excluded on the live side at the apex only —
# a future delegated NS record for a subdomain is NOT excluded and would
# correctly trip the probe. Anything else that appears live-only is unmanaged
# drift and fails the probe.
#
# DNSSEC POSTURE is probed directly too: cloudflare_zone_dnssec.status is a
# computed-only attribute (provider v4), so an out-of-band DNSSEC disable
# produces NO config-vs-state diff — plan stays green — and the record
# enumeration below cannot see it (apex CDS/CDNSKEY are deliberately
# excluded). GET /zones/{id}/dnssec is the only watcher. Acceptable statuses
# are "active" and "pending" (post-enable propagation window); "disabled",
# "pending-disabled", or anything else fails closed.
#
# The zone id is the committed import-block literal in
# infra/rundevoo-run/zone.tf — deterministic, reviewed, and the same id the
# apply targets.
#
# Lives in a script (not inline in scheduled-terraform-drift.yml) so its
# branches are unit-tested by tests/scripts/test-rundevoo-dns-set-equality.sh
# with a PATH-stubbed curl — no network in tests.

set -euo pipefail

# Refuse to run under xtrace: -x prints a variable's value the moment it is
# bound (see #7797), and this script handles a live Cloudflare zone token.
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

GREEN='\033[32m'; RED='\033[31m'; NC='\033[0m'
red()    { printf '%b%s%b\n' "$RED"    "$*" "$NC" >&2; }
green()  { printf '%b%s%b\n' "$GREEN"  "$*" "$NC"; }

# Confined bearer curl — same helper bootstrap.sh uses (cross-app coupling,
# recorded in infra/rundevoo-run/README.md). The token rides curl's stdin
# config channel, never argv.
# shellcheck source=../apps/cla-evidence/scripts/_cf-admin-token.sh disable=SC1091
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/../apps/cla-evidence/scripts" && pwd)/_cf-admin-token.sh"

CF_API_BASE="https://api.cloudflare.com/client/v4"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZONE_TF="$REPO_ROOT/infra/rundevoo-run/zone.tf"

state_json="${1:?usage: rundevoo-dns-set-equality.sh <terraform-show-json-file>}"
[[ -f "$state_json" ]] || { red "no such file: $state_json"; exit 1; }

if [[ -z "${CLOUDFLARE_API_TOKEN:-}" ]]; then
  red "CLOUDFLARE_API_TOKEN is required (the zone-scoped rundevoo token). No fallback: a broader credential would defeat the scope boundary this probe certifies."
  exit 1
fi

# Zone id from the committed import block — the same literal the apply uses.
# `id = ` is anchored at line start: `account_id = ` also ends in `id = ` and
# would false-match otherwise; the hex is then extracted cleanly (a bare
# tr/strip would keep the 'd' in 'id' — it is itself a hex character).
# The `|| true` inside the substitution is load-bearing: without it a no-match
# pipeline fails under pipefail+errexit at the assignment and the named
# diagnostic below is never reached.
ZONE_ID=$(grep -oE -m1 '[0-9a-f]{32}' < <(grep -oE '^[[:space:]]*id = "[0-9a-f]{32}"' "$ZONE_TF") || true)
[[ ${#ZONE_ID} -eq 32 ]] || { red "could not read the zone id from $ZONE_TF import block"; exit 1; }

# ── managed set: type<TAB>name<TAB>content per cloudflare_record in state ──
managed=$(mktemp); live=$(mktemp)
trap 'rm -f "$managed" "$live"' EXIT
jq -r '
  [.values.root_module.resources[]? | select(.type == "cloudflare_record")
    | .values | [.type, .name, .content] | @tsv][] ' "$state_json" \
  | sort -u > "$managed"

# ── live set: paginated enumeration (bounded) ──────────────────────────────
# Incomplete enumeration must fail closed — a truncated list would let
# unmanaged records hide past the page boundary.
page=1
while :; do
  resp=$(_cf_admin_curl "$CLOUDFLARE_API_TOKEN" \
    "$CF_API_BASE/zones/$ZONE_ID/dns_records?per_page=500&page=$page" \
    --max-time 30 -fsS) \
    || { red "GET /zones/{id}/dns_records page $page failed"; exit 1; }
  success=$(printf '%s' "$resp" | jq -r '.success // false')
  [[ "$success" == "true" ]] \
    || { red "dns_records page $page returned success=$success"; exit 1; }
  printf '%s' "$resp" | jq -r '
    [.result[]? | select((.name == "rundevoo.run" and (.type == "NS" or .type == "CDS" or .type == "CDNSKEY")) | not)
      | [.type, .name, .content] | @tsv][] ' >> "$live"
  # `// empty`, never a default page count: a missing/non-numeric total_pages
  # must fail closed, not silently assume one page and skip the rest.
  total_pages=$(printf '%s' "$resp" | jq -r '.result_info.total_pages // empty')
  if [[ ! "$total_pages" =~ ^[0-9]+$ ]]; then
    red "dns_records page $page returned a missing/non-numeric result_info.total_pages ('$total_pages') — refusing to trust a partial enumeration"
    exit 1
  fi
  [[ "$page" -ge "$total_pages" ]] && break
  page=$((page + 1))
  if [[ "$page" -gt 10 ]]; then
    red "dns_records enumeration exceeded 10 pages (500/page) — refusing to assert equality over a possibly truncated list"
    exit 1
  fi
done
sort -u -o "$live" "$live"

# ── DNSSEC posture (see header: invisible to both plan and record sets) ────
rc=0
resp=$(_cf_admin_curl "$CLOUDFLARE_API_TOKEN" \
  "$CF_API_BASE/zones/$ZONE_ID/dnssec" --max-time 30 -fsS) \
  || { red "GET /zones/{id}/dnssec failed"; exit 1; }
dnssec_status=$(printf '%s' "$resp" | jq -r '.result.status // ""')
if [[ "$dnssec_status" != "active" && "$dnssec_status" != "pending" ]]; then
  red "DNSSEC status is '$dnssec_status' (expected active or pending) — an out-of-band disable is invisible to terraform plan; investigate the zone."
  rc=1
fi

# ── set difference ─────────────────────────────────────────────────────────
unmanaged=$(comm -13 "$managed" "$live")        # live, not managed
missing=$(comm -23 "$managed" "$live")          # managed, not live

if [[ -n "$unmanaged" ]]; then
  red "UNMANAGED live DNS record(s) — present in the rundevoo.run zone but managed by NO terraform state:"
  printf '%s\n' "$unmanaged" | sed 's/^/  /' >&2
  red "An out-of-band record can serve arbitrary content under a company-owned domain. Remove it in the dashboard or adopt it in infra/rundevoo-run/dns.tf."
  rc=1
fi
if [[ -n "$missing" ]]; then
  red "MISSING live DNS record(s) — managed by terraform state but absent from the live zone:"
  printf '%s\n' "$missing" | sed 's/^/  /' >&2
  rc=1
fi
if [[ "$rc" -eq 0 ]]; then
  green "dns set equality: live == managed ($(wc -l < "$live" | tr -d ' ') record(s), apex NS/CDS/CDNSKEY excluded), dnssec=$dnssec_status"
fi
exit "$rc"
