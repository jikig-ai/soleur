#!/usr/bin/env bash
# ssl-full-mitigation.test.sh — guards the config rule that is currently holding
# soleur.ai and www.soleur.ai up (#7749, ADR-194).
#
# WHAT IS ACTUALLY LOAD-BEARING HERE
#
# The GitHub Pages origin certificate for soleur.ai EXPIRED at 2026-08-16 13:53:34Z
# and is intentionally never renewed — it cannot be renewed while the records are
# proxied, and ADR-194 abandons it at the Cloudflare Pages cutover rather than
# renewing it. Measured, from outside the proxy:
#
#   $ echo | openssl s_client -servername soleur.ai -connect 185.199.108.153:443 \
#       | openssl x509 -noout -dates
#   notAfter=Aug 16 13:53:34 2026 GMT
#
# The site nevertheless serves 200/301 today. What holds it up is ONE rule: the
# `set_config` block in `cloudflare_ruleset.seo_config_settings` setting
# `ssl = "full"` for the apex and www. The zone default is Full (STRICT), which
# VALIDATES the origin certificate and therefore refuses the expired one — that is
# what produced the 8h15m HTTP 526 outage on 2026-08-16. `full` (non-strict) still
# encrypts the CF→origin leg but does not validate the certificate.
#
# So this is not a stopgap that buys time against an approaching expiry. The expiry
# already happened. This rule retired the failure class for the whole pre-cutover
# interval, and removing it re-arms a 526 on an HSTS-preloaded apex IMMEDIATELY —
# with no cert-expiry warning available anywhere, because there is no longer an
# expiry to warn about.
#
# WHY A GUARD AND NOT A COMMENT
#
# Before this file, nothing in CI protected that rule, and the rule's own removal
# condition instructed deletion once `gh api repos/jikig-ai/soleur/pages` reported
# a valid `https_certificate`. Under ADR-194 that condition can NEVER be satisfied,
# because the cutover abandons the Pages cert rather than renewing it. A reader
# following that instruction had no exit, and a reader who deleted the block anyway
# took the apex to 526. The condition is replaced below by two MEASURABLE exits, and
# this guard is what enforces them.
#
# STAGE-AWARE BY CONSTRUCTION, NOT BY SKIPPING
#
# The requirement is conditional on the substrate, so the guard resolves the stage
# from `dns.tf` rather than being deleted at cutover:
#
#   PRE-CUTOVER  (apex still on GitHub Pages IPs, proxied) → the rule is MANDATORY.
#   POST-CUTOVER (apex no longer on GitHub Pages)          → the rule may be removed.
#
# That is the first removal exit, and it is checked rather than remembered. The
# second exit — the Pages certificate becomes valid again, i.e. an ADR-194 rollback
# — is not statically observable from the repo, so it is deliberately NOT encoded
# here; taking it means reverting ADR-194, which changes `dns.tf` and therefore this
# guard's stage anyway.
#
# COMMENTS ARE STRIPPED BEFORE ANY ASSERTION RUNS. This file's subject is a rule
# whose surrounding prose necessarily quotes `ssl = "full"`, `soleur.ai` and
# `enabled` many times over. A body-grep that saw those comments would be satisfied
# by the rationale written to explain the rule, and would stay green with the rule
# deleted. Every predicate below reads `$STRIPPED`, never the raw file.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_TF="$SCRIPT_DIR/seo-config-rules.tf"
DNS_TF="$SCRIPT_DIR/dns.tf"

PASS=0
FAIL=0
CASES=0

pass() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1"; }
verdict() { CASES=$((CASES + 1)); if [[ "$1" == "0" ]]; then pass "$2"; else fail "$2"; fi; }

for f in "$CONFIG_TF" "$DNS_TF"; do
  if [[ ! -f "$f" ]]; then
    printf '[FATAL] required file missing: %s\n' "$f" >&2
    exit 1
  fi
done

WORK="$(mktemp -d -t sslfull-guard-XXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 1; }
trap 'rm -rf "$WORK"' EXIT

# Strip whole-line and trailing `#` comments. Terraform has no `#` inside the string
# literals this guard reads (hosts and the ssl value), so a naive strip is exact here.
STRIPPED="$WORK/config.stripped.tf"
sed 's/#.*$//' "$CONFIG_TF" > "$STRIPPED" || { printf '[FATAL] strip failed\n' >&2; exit 1; }
DNS_STRIPPED="$WORK/dns.stripped.tf"
sed 's/#.*$//' "$DNS_TF" > "$DNS_STRIPPED" || { printf '[FATAL] strip failed\n' >&2; exit 1; }

printf '=== ssl=full mitigation guard (#7749) ===\n\n'

# POSITIVE CONTROL FOR THE VERDICT HELPERS (AP-023).
# An assertion-count floor cannot see a neutered `fail()`: with every case passing,
# PASS+FAIL still equals CASES and the suite exits 0 having lost the ability to fail.
# So drive both helpers once and require each counter to move. Counters are restored
# afterwards so this does not perturb the floor.
_p0=$PASS; _f0=$FAIL
pass 'self-check: pass() increments (this PASS line is expected)'
fail 'self-check: fail() increments (this FAIL line is EXPECTED, not a defect)'
if [[ $((PASS - _p0)) -ne 1 || $((FAIL - _f0)) -ne 1 ]]; then
  printf '[FATAL] verdict helpers are not counting (pass delta=%d, fail delta=%d) — every assertion below would be unable to report\n' \
    "$((PASS - _p0))" "$((FAIL - _f0))" >&2
  exit 1
fi
PASS=$_p0; FAIL=$_f0
printf '  (verdict helpers verified: both counters move)\n\n'

# ---------------------------------------------------------------------------------------
# STAGE RESOLUTION — read from dns.tf, comment-stripped
# ---------------------------------------------------------------------------------------
# Pre-cutover iff the apex still carries GitHub Pages anycast A-records. Those four
# IPs are GitHub's published Pages range; their presence is the substrate that makes
# the expired origin cert reachable at all.
PAGES_IPS=0
for ip in 185.199.108.153 185.199.109.153 185.199.110.153 185.199.111.153; do
  grep -qF "\"$ip\"" "$DNS_STRIPPED" && PAGES_IPS=$((PAGES_IPS + 1))
done
WWW_PAGES=1
grep -qE '"jikig-ai\.github\.io"' "$DNS_STRIPPED" || WWW_PAGES=0

if [[ "$PAGES_IPS" -gt 0 || "$WWW_PAGES" -eq 1 ]]; then
  STAGE="pre-cutover"
else
  STAGE="post-cutover"
fi
printf 'stage: %s (github-pages apex IPs found: %d, www→jikig-ai.github.io: %s)\n\n' \
  "$STAGE" "$PAGES_IPS" "$([[ "$WWW_PAGES" -eq 1 ]] && echo yes || echo no)"

# ---------------------------------------------------------------------------------------
# EXTRACT the seo_config_settings ruleset's `rules {}` blocks, IN DECLARATION ORDER
# ---------------------------------------------------------------------------------------
# Declaration order is load-bearing: config rules evaluate in order, so a rule setting
# `ssl` for the same hosts ABOVE the mitigation would decide the value instead of it.
# awk tracks brace depth so a nested `action_parameters {}` cannot end a rules block.
RULES="$WORK/rules.txt"
awk '
  /^resource "cloudflare_ruleset" "seo_config_settings"/ { inres = 1; depth = 0 }
  inres {
    n = gsub(/\{/, "{"); depth += n
    m = gsub(/\}/, "}"); depth -= m
    if (inrule) {
      if ($0 ~ /action[[:space:]]*=/)          { a = $0; sub(/.*=[[:space:]]*/, "", a); act = a }
      if ($0 ~ /enabled[[:space:]]*=/)         { a = $0; sub(/.*=[[:space:]]*/, "", a); en = a }
      if ($0 ~ /expression[[:space:]]*=/)      { a = $0; sub(/.*=[[:space:]]*/, "", a); ex = a }
      if ($0 ~ /[[:space:]]ssl[[:space:]]*=/)  { a = $0; sub(/.*=[[:space:]]*/, "", a); ssl = a }
      if (depth <= ruledepth) {
        idx++
        printf "%d\taction=%s\tenabled=%s\tssl=%s\texpr=%s\n", idx, act, en, (ssl==""?"-":ssl), ex
        inrule = 0; act=""; en=""; ex=""; ssl=""
      }
      next
    }
    if ($0 ~ /^[[:space:]]*rules[[:space:]]*\{/) { inrule = 1; ruledepth = depth - 1; next }
    if (depth == 0 && NR > 1 && inres) { inres = 0 }
  }
' "$STRIPPED" > "$RULES"

RULE_COUNT=$(wc -l < "$RULES" | tr -d ' ')

# Non-vacuity control: if the extractor returns nothing, every assertion below would
# be trivially satisfiable or trivially failing for the wrong reason.
if [[ "$RULE_COUNT" -lt 1 ]]; then
  printf '[FATAL] extracted 0 rules blocks from cloudflare_ruleset.seo_config_settings — the\n' >&2
  printf '        parser did not match the file. Every assertion below would be meaningless.\n' >&2
  exit 1
fi
printf 'extracted %d rules block(s) from cloudflare_ruleset.seo_config_settings\n\n' "$RULE_COUNT"

# The mitigation rule: the one whose action_parameters set ssl, scoped to apex+www.
MITIGATION=$(awk -F'\t' '$4 != "ssl=-" && $5 ~ /\\"soleur\.ai\\"/ && $5 ~ /\\"www\.soleur\.ai\\"/ { print; exit }' "$RULES")

if [[ "$STAGE" == "pre-cutover" ]]; then
  # --- 1. the rule exists at all -------------------------------------------------------
  rc=1; [[ -n "$MITIGATION" ]] && rc=0
  verdict "$rc" 'the ssl set_config rule scoped to soleur.ai + www.soleur.ai is present (removing it re-arms HTTP 526 on the HSTS-preloaded apex)'

  if [[ -n "$MITIGATION" ]]; then
    m_enabled=$(printf '%s' "$MITIGATION" | awk -F'\t' '{print $3}' | sed 's/^enabled=//')
    m_ssl=$(printf '%s' "$MITIGATION"     | awk -F'\t' '{print $4}' | sed 's/^ssl=//' | tr -d '"')
    m_expr=$(printf '%s' "$MITIGATION"    | awk -F'\t' '{print $5}' | sed 's/^expr=//')

    # --- 2. enabled ------------------------------------------------------------------
    rc=1; [[ "$m_enabled" == "true" ]] && rc=0
    verdict "$rc" "the mitigation rule is enabled = true (found: ${m_enabled:-<absent>})"

    # --- 3. the VALUE is full, not strict and not flexible ---------------------------
    # `strict` re-validates the expired cert (the 526). `flexible` would serve the
    # origin leg in cleartext, which is a different and worse failure.
    rc=1; [[ "$m_ssl" == "full" ]] && rc=0
    verdict "$rc" "the mitigation sets ssl = full, not strict or flexible (found: ${m_ssl:-<absent>})"

    # --- 4. BOTH hosts are in scope --------------------------------------------------
    # www alone leaves the apex on the zone default; apex alone leaves www there.
    rc=1; printf '%s' "$m_expr" | grep -qF 'soleur.ai' && rc=0
    verdict "$rc" "the mitigation expression covers the apex soleur.ai"
    rc=1; printf '%s' "$m_expr" | grep -qF 'www.soleur.ai' && rc=0
    verdict "$rc" "the mitigation expression covers www.soleur.ai"

    # --- 5. NOT SHADOWED by an earlier ssl rule on the same hosts --------------------
    # First-match-wins on the `ssl` key: an ssl rule declared above this one whose
    # expression also matches apex/www decides the value instead. Today the only other
    # ssl rule is scoped to app.soleur.ai, which cannot match.
    ssl_rules=$(awk -F'\t' '
      $4 != "ssl=-" && ($5 ~ /\\"soleur\.ai\\"/ || $5 ~ /\\"www\.soleur\.ai\\"/) { n++ } END { print n + 0 }
    ' "$RULES")
    rc=1; [[ "$ssl_rules" == "1" ]] && rc=0
    verdict "$rc" "exactly one rule in this ruleset sets ssl for the apex or www (more than one means declaration order decides the effective value, silently; found: ${ssl_rules})"
  else
    # Keep the case count stage-stable so the floor below stays an exact cardinality.
    for missing in \
      'the mitigation rule is enabled = true' \
      'the mitigation sets ssl = full, not strict or flexible' \
      'the mitigation expression covers the apex soleur.ai' \
      'the mitigation expression covers www.soleur.ai' \
      'no earlier rule in this ruleset sets ssl for the apex or www'; do
      verdict 1 "$missing (unreachable: the mitigation rule itself is absent)"
    done
  fi
else
  # --- POST-CUTOVER: the first removal exit is satisfied ------------------------------
  # The apex no longer resolves to GitHub Pages, so the expired origin cert is out of
  # the serving path and the mitigation may be retired. Assert the stage positively so
  # this branch cannot be reached by a dns.tf the parser simply failed to read.
  rc=1; [[ "$PAGES_IPS" -eq 0 && "$WWW_PAGES" -eq 0 ]] && rc=0
  verdict "$rc" 'post-cutover: dns.tf carries no GitHub Pages apex IPs and no www→jikig-ai.github.io'
  for retired in \
    'the ssl mitigation is no longer mandatory (removal exit 1 satisfied: the cutover landed)' \
    'ssl value unconstrained post-cutover' \
    'apex host scope unconstrained post-cutover' \
    'www host scope unconstrained post-cutover' \
    'shadowing unconstrained post-cutover'; do
    verdict 0 "$retired"
  done
fi

# ---------------------------------------------------------------------------------------
# ANTI-VACUITY FLOOR AND ACCOUNTING (AP-023 / ADR-193)
# ---------------------------------------------------------------------------------------
# Both report with `printf >&2` + `exit 1`, NEVER through this suite's own `fail`. A floor
# routed through `fail` is disarmed by the same one-line edit that disarms every assertion
# it exists to witness.
#
# EXACT cardinality, not a lower bound, and identical in both stages by construction (the
# stage branches are padded to the same count). Bump deliberately when adding a case; do
# not derive it from anything this file computes, which would make it a tautology.
printf '\n'
EXPECTED_CASES=6
if [[ "$CASES" -ne "$EXPECTED_CASES" ]]; then
  printf '[FATAL] vacuity floor: %d assertion cases executed, expected exactly %d — a case was deleted, skipped, or added without updating EXPECTED_CASES\n' \
    "$CASES" "$EXPECTED_CASES" >&2
  exit 1
fi
if [[ $((PASS + FAIL)) -ne "$CASES" ]]; then
  printf '[FATAL] accounting: %d verdicts recorded across %d cases — a verdict helper was neutered or a case produced no verdict\n' \
    "$((PASS + FAIL))" "$CASES" >&2
  exit 1
fi
if [[ "$FAIL" -ne 0 ]]; then
  printf 'FAILED: %d/%d\n' "$FAIL" "$CASES"
  exit 1
fi
printf 'OK: %d/%d\n' "$PASS" "$CASES"
