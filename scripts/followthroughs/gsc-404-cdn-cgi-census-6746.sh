#!/usr/bin/env bash
# Follow-through verification for PR #6746 — GSC "Not found (404)" on
# /cdn-cgi/l/email-protection.
#
# What this proves: that Cloudflare actually honoured the Configuration Rule.
# Source assertions cannot establish it — the rewrite is edge-injected, so the
# ONLY proof is fetching the live marketing HTML as Googlebot and counting the
# emitted hrefs. That is AC9, and it is fully automatable, which is why this is
# a scripted probe rather than an operator eyeball
# (hr-no-dashboard-eyeball-pull-data-yourself).
#
# The GSC coverage-report re-validation itself is genuinely human-only (no API
# exposes coverage-validation state), but it is DOWNSTREAM of this: if the
# census is 0, the hrefs are gone and the GSC rows clear on Google's next crawl.
# So the mechanical gate is the census, not the dashboard.
#
# Exit semantics (enforced by scripts/sweep-followthroughs.sh):
#   0 = PASS       census is 0 across all five paths — rule is live
#   1 = FAIL       hrefs still present — the rule did not take effect
#   2 = TRANSIENT  a fetch failed; retry next sweep rather than assert a verdict
#
# Convention: knowledge-base/engineering/operations/runbooks/followthrough-convention.md

set -uo pipefail

UA="Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"
PATHS=("" "getting-started/" "pricing/" "legal/privacy-policy/" "legal/terms-and-conditions/")
# Baseline at implementation time (seo-config-rules.tf header): 0/2/1/20/7 = 30.
BASELINE_TOTAL=30

total=0
transient=0
for p in "${PATHS[@]}"; do
  body=$(curl -sS --max-time 20 -A "$UA" "https://soleur.ai/${p}" 2>/dev/null)
  rc=$?
  if [ "$rc" -ne 0 ] || [ -z "$body" ]; then
    echo "TRANSIENT: fetch failed for /${p} (curl rc=${rc})" >&2
    transient=1
    continue
  fi
  # `grep -o | wc -l`, never `grep -c`: the hrefs share a line in minified HTML,
  # so grep -c undercounts (documented in seo-config-rules.tf).
  n=$(printf '%s' "$body" | grep -o 'cdn-cgi/l/email-protection' | wc -l | tr -d ' ')
  echo "  /${p} -> ${n}"
  total=$((total + n))
done

if [ "$transient" -eq 1 ]; then
  echo "TRANSIENT: at least one path could not be fetched; no verdict asserted" >&2
  exit 2
fi

echo "census total: ${total} (baseline was ${BASELINE_TOTAL})"

if [ "$total" -eq 0 ]; then
  echo "PASS: zero /cdn-cgi/l/email-protection hrefs emitted — Cloudflare honoured the rule."
  exit 0
fi

echo "FAIL: ${total} href(s) still emitted. The Configuration Rule is not in effect." >&2
echo "  Check: the apply may not have run, the rule may be mis-scoped, or Email" >&2
echo "  Obfuscation may have been re-enabled. Probe the entrypoint:" >&2
echo "  GET /zones/\$ZONE/rulesets/phases/http_config_settings/entrypoint" >&2
exit 1
