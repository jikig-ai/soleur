#!/usr/bin/env bash
# www-apex-canonicalizer.test.sh — config-drift guard for the www→apex 301.
#
# Context (#4584, spun out of #4577): the live `www.soleur.ai → 301 → soleur.ai`
# canonicalizer is NOT a Cloudflare Redirect Rule / Page Rule. It is served by
# GitHub Pages (Fastly origin), enforced by the repo-tracked custom-domain file
# `plugins/soleur/docs/CNAME = "soleur.ai"`. GitHub Pages auto-301s every
# non-primary alias (here `www`) to the configured primary custom domain,
# host- and path-preserving — exactly the observed behavior.
#
# Terraform already manages and drift-detects the DNS *substrate* that routes
# www traffic to GitHub Pages (the `www` CNAME + the apex A-record set). What
# pure TF resource-drift CANNOT see is (a) the `CNAME` file (not a TF resource),
# or (b) the *semantic* canonical-host contract that ties these facts together.
# This static test closes that gap: it fails the build if any of the three
# managed facts whose combination produces the redirect is changed.
#
# Runtime drift of the 301 itself is guarded separately by
# `sentry_uptime_monitor.soleur_www` (equals 301). This test is the config-drift
# complement — it blocks the regressing PR before merge.
#
# NOTE: A2/A3 grep the `cloudflare_record` resource name. A future
# cloudflare/cloudflare v4→v5 bump renames `cloudflare_record` →
# `cloudflare_dns_record`; update the resource-name anchors here when that lands.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)" # apps/web-platform/infra → repo root
DNS_TF="$SCRIPT_DIR/dns.tf"
CNAME_FILE="$REPO_ROOT/plugins/soleur/docs/CNAME"

PASS=0
FAIL=0
TOTAL=0

pass() {
  PASS=$((PASS + 1))
  TOTAL=$((TOTAL + 1))
  echo "  PASS: $1"
}

fail() {
  FAIL=$((FAIL + 1))
  TOTAL=$((TOTAL + 1))
  echo "  FAIL: $1"
}

# Extract a single `resource "cloudflare_record" "<name>" { ... }` block.
# Blocks in dns.tf are flat (no nested braces), so range-to-first-`^}` is safe.
record_block() {
  awk -v r="$1" '
    $0 ~ "resource \"cloudflare_record\" \"" r "\"" { f = 1 }
    f { print }
    f && /^}/ { exit }
  ' "$DNS_TF"
}

echo "www-apex-canonicalizer drift-guard"

# A1: docs/CNAME is the apex (catches canonical-direction inversion).
# If this flips to www.soleur.ai, GitHub Pages would 301 apex→www and invert
# the canonical direction with zero TF drift — this is the load-bearing check.
if [[ ! -f "$CNAME_FILE" ]]; then
  # A missing CNAME file is itself a canonical-direction regression: without it
  # GitHub Pages serves no custom domain and the www→apex 301 stops. Emit a
  # clean FAIL rather than letting `set -e` abort on the redirection below.
  fail "docs/CNAME exists at plugins/soleur/docs/CNAME"
else
  cname="$(tr -d '[:space:]' <"$CNAME_FILE")"
  if [[ "$cname" == "soleur.ai" ]]; then
    pass "docs/CNAME is soleur.ai (apex, not www)"
  else
    fail "docs/CNAME is soleur.ai (apex, not www) — got '$cname'"
  fi
fi

# A2: www CNAME → jikig-ai.github.io, proxied (so www traffic reaches GH Pages).
www_block="$(record_block www)"
if grep -qE 'content[[:space:]]*=[[:space:]]*"jikig-ai\.github\.io"' <<<"$www_block"; then
  pass "dns.tf www record targets jikig-ai.github.io"
else
  fail "dns.tf www record targets jikig-ai.github.io"
fi
if grep -qE 'type[[:space:]]*=[[:space:]]*"CNAME"' <<<"$www_block" &&
  grep -qE 'proxied[[:space:]]*=[[:space:]]*true' <<<"$www_block"; then
  pass "dns.tf www record is a proxied CNAME"
else
  fail "dns.tf www record is a proxied CNAME"
fi

# A3: apex github_pages A-record set is proxied and points at soleur.ai
# (catches apex being repointed off GitHub Pages).
apex_block="$(record_block github_pages)"
if grep -qE 'name[[:space:]]*=[[:space:]]*"soleur\.ai"' <<<"$apex_block" &&
  grep -qE 'type[[:space:]]*=[[:space:]]*"A"' <<<"$apex_block" &&
  grep -qE 'proxied[[:space:]]*=[[:space:]]*true' <<<"$apex_block"; then
  pass "dns.tf apex github_pages record is type A, name soleur.ai, proxied"
else
  fail "dns.tf apex github_pages record is type A, name soleur.ai, proxied"
fi

# A4: the GitHub-Pages-owned contract comment exists in dns.tf, so the doc
# cannot silently rot away from this test.
if grep -q "GitHub-Pages-owned" "$DNS_TF"; then
  pass "dns.tf carries the GitHub-Pages-owned contract comment"
else
  fail "dns.tf carries the GitHub-Pages-owned contract comment"
fi

echo
if [[ "$FAIL" -ne 0 ]]; then
  echo "FAILED: $FAIL/$TOTAL"
  exit 1
fi
echo "OK: $PASS/$TOTAL"
