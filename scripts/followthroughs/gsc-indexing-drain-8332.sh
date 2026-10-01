#!/usr/bin/env bash
# Follow-through verification for #8332 — re-verify the #3328 blog-redirect
# edge migration after the GSC index-state lag.
#
# What this proves: every redirect DECLARED in
# apps/web-platform/infra/seo-bulk-redirects.tf is LIVE at the edge (301 to
# the declared target), and the five "Crawled - currently not indexed" pages
# the migration remediated still serve 200 with a self-canonical and no
# meta-refresh. The expectations are PARSED from the tf at sweep time, so the
# probe cannot drift from the source of truth it verifies — a pair added to
# the map is checked on the next sweep; an item removed is no longer checked.
#
# What this deliberately does NOT prove: the GSC "Why pages aren't indexed"
# bucket state itself. Coverage-report state has no API — it is readable only
# through an operator-authenticated dashboard session (same reasoning as
# gsc-404-cdn-cgi-census-6746.sh: the mechanical gate is the edge behaviour,
# the dashboard drains downstream of it on Google's crawl schedule). The
# bucket-level Validate Fix request was submitted 2026-09-20; GSC applies it
# on its own timeline regardless of when this issue closes.
#
# CREDENTIAL POSTURE: none. The probe declares no secrets= and performs only
# anonymous `curl` reads of public soleur.ai URLs plus local reads of the
# checked-out tf file. No git, no gh, no network writes.
#
# Exit semantics (scripts/sweep-followthroughs.sh):
#   0 = PASS       every declared redirect 301s to its target; all five
#                  remediated pages serve 200 + self-canonical + no refresh
#   1 = FAIL       a declared redirect is missing/wrong, a remediated page
#                  regressed, or the tf source of truth is unparseable —
#                  the close criteria are not met
#   2 = TRANSIENT  a fetch failed; retry next sweep
#
# RETIREMENT: when #8332 closes, delete this file and the
# `<!-- soleur:followthrough ... script=scripts/followthroughs/gsc-indexing-drain-8332.sh ... -->`
# directive reference is the issue body itself (dies with the issue). No
# test-all.sh run_suite line, baseline row, or back-pointer exists for it.

set -uo pipefail

UA="Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"
TF="apps/web-platform/infra/seo-bulk-redirects.tf"

# The five "Crawled - currently not indexed" pages whose remediation (edge
# 301s on the date-slug shapes + internal-link equity) this tracker verifies.
LIVE_PAGES=(
  "/blog/soleur-vs-polsia/"
  "/blog/why-most-agentic-tools-plateau/"
  "/blog/ai-agents-for-solo-founders/"
  "/legal/gdpr-policy/"
  "/legal/data-protection-disclosure/"
)

transient=0
failures=0
checks=0

# HEAD one URL; expect 301 with Location == want. Sources in the tf are
# scheme-less apex URLs; checking the https shape exercises the single-hop
# path (http -> https -> redirect is the documented two-hop plain-HTTP path).
check_redirect() {
  local want="$2" url="https://$1"
  local hdrs status loc
  hdrs=$(curl -sSI -A "$UA" --max-time 20 --max-redirs 0 "$url" 2>/dev/null)
  if [ -z "$hdrs" ]; then
    echo "TRANSIENT: fetch failed for $url" >&2
    transient=1
    return
  fi
  checks=$((checks + 1))
  status=$(printf '%s' "$hdrs" | head -1 | tr -d '\r' | grep -oE '[0-9]{3}' | head -1)
  loc=$(printf '%s' "$hdrs" | grep -i '^location:' | head -1 | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r')
  if [ "$status" != "301" ] || [ "$loc" != "$want" ]; then
    echo "FAIL: $url -> status=${status:-none} location=${loc:-none} (want 301 -> $want)" >&2
    failures=$((failures + 1))
  fi
}

# GET one page; expect 200 + self-canonical + no meta-refresh.
check_live_page() {
  local path="$1" url="https://soleur.ai$1"
  local out code body
  out=$(curl -sS -A "$UA" --max-time 20 -w '\n%{http_code}' "$url" 2>/dev/null)
  if [ -z "$out" ]; then
    echo "TRANSIENT: fetch failed for $url" >&2
    transient=1
    return
  fi
  code=$(printf '%s' "$out" | tail -1)
  body=$(printf '%s' "$out" | sed '$d')
  checks=$((checks + 1))
  if [ "$code" != "200" ]; then
    echo "FAIL: $url -> status=$code (want 200)" >&2
    failures=$((failures + 1))
    return
  fi
  # Substring checks via [[ == *...* ]] — NOT `printf | grep -q`: under
  # pipefail, grep -q's early exit SIGPIPEs printf on large bodies and the
  # pipeline reports 141, reading a present canonical as missing.
  if [[ "$body" != *"rel=\"canonical\" href=\"$url\""* ]]; then
    echo "FAIL: $url -> missing self-canonical $url" >&2
    failures=$((failures + 1))
  fi
  if [[ "${body,,}" == *'http-equiv="refresh"'* ]]; then
    echo "FAIL: $url -> emits meta-refresh (stub machinery regression)" >&2
    failures=$((failures + 1))
  fi
}

if [ ! -f "$TF" ]; then
  echo "FAIL: $TF missing — the declared redirect source of truth is gone; cannot verify." >&2
  exit 1
fi

# Explicit items: every quoted `source_url = "..."`/`target_url = "..."` pair,
# zipped in document order. The dynamic block's unquoted `item.value.source`
# never matches the quoted-literal pattern.
mapfile -t sources < <(grep -oE 'source_url[[:space:]]*=[[:space:]]*"[^"]+"' "$TF" | sed 's/.*"\(.*\)"/\1/')
mapfile -t targets < <(grep -oE 'target_url[[:space:]]*=[[:space:]]*"[^"]+"' "$TF" | sed 's/.*"\(.*\)"/\1/')

# Generated blog date-slug pairs: `"<date-slug>" = "<canonical>"` lines inside
# the blog_redirect_pairs map.
mapfile -t pairs < <(awk '/blog_redirect_pairs = \{/,/^  \}/' "$TF" | grep -oE '"[^"]+"[[:space:]]*=[[:space:]]*"[^"]+"')

if [ "${#sources[@]}" -eq 0 ] || [ "${#sources[@]}" -ne "${#targets[@]}" ] || [ "${#pairs[@]}" -eq 0 ]; then
  echo "FAIL: could not parse $TF (sources=${#sources[@]} targets=${#targets[@]} pairs=${#pairs[@]}) — declared list empty or shape changed; cannot verify." >&2
  exit 1
fi

for i in "${!sources[@]}"; do
  check_redirect "${sources[$i]}" "${targets[$i]}"
done

for p in "${pairs[@]}"; do
  date_slug=$(printf '%s' "$p" | sed 's/^"\(.*\)"[[:space:]]*=.*/\1/')
  canonical=$(printf '%s' "$p" | sed 's/.*=[[:space:]]*"\(.*\)"/\1/')
  for suffix in "/" "/index.html" ""; do
    check_redirect "soleur.ai/blog/${date_slug}${suffix}" "https://soleur.ai/blog/${canonical}/"
  done
done

for path in "${LIVE_PAGES[@]}"; do
  check_live_page "$path"
done

echo "checks run: $checks  failures: $failures  (explicit items: ${#sources[@]}, blog pairs: ${#pairs[@]})"

if [ "$transient" -eq 1 ]; then
  echo "TRANSIENT: at least one fetch failed; no verdict asserted" >&2
  exit 2
fi
if [ "$failures" -gt 0 ]; then
  echo "FAIL: $failures check(s) failed — close criteria not met." >&2
  exit 1
fi
echo "PASS: all declared redirects live at the edge and all remediated pages serve 200 + self-canonical."
exit 0
