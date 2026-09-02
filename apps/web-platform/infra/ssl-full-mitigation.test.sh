#!/usr/bin/env bash
# ssl-full-mitigation.test.sh — guards the config rule that is currently holding
# soleur.ai and www.soleur.ai up (#7749, ADR-194).
#
# WHAT IS ACTUALLY LOAD-BEARING HERE
#
# The GitHub Pages origin certificate for soleur.ai EXPIRED at 2026-08-16 13:53:34Z
# and is intentionally never renewed — it cannot be renewed while the records are
# proxied, and ADR-194 abandons it at the Cloudflare Pages cutover rather than
# renewing it. Measured 2026-09-02, from outside the proxy (identical on .109/.110/.111):
#
#   $ echo | openssl s_client -servername soleur.ai -connect 185.199.108.153:443 \
#       | openssl x509 -noout -dates
#   notAfter=Aug 16 13:53:34 2026 GMT
#
# The site nevertheless serves 200/301 today. What holds it up is ONE rule: the
# `set_config` block in `cloudflare_ruleset.seo_config_settings` setting
# `ssl = "full"` for the apex and www. `full` (non-strict) encrypts the CF→origin
# leg but does not validate the certificate; the zone default validates it and
# therefore refuses the expired one, which is what produced the 8h15m HTTP 526
# outage on 2026-08-16.
#
# CAVEAT, stated because this guard cannot check it: the zone-level SSL mode is
# NOT pinned in Terraform. `cloudflare_zone_settings_override.soleur_ai` manages
# `security_header` and `always_use_https` only, so the default this rule overrides
# is dashboard-managed and unverifiable from the repo. It is inferred from the 526
# actually having happened. That is a real gap one level up from this guard: if the
# zone default were flipped to `flexible`, apex would serve cleartext to origin and
# every assertion here would still pass.
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
#   PRE-CUTOVER  (apex still on GitHub Pages IPs, OR www still CNAME'd there)
#                                                          → the rule is MANDATORY.
#   POST-CUTOVER (neither record points at GitHub Pages)   → the rule may be removed.
#
# The disjunction is deliberate and fails safe: either record still pointing at Pages
# keeps the expired origin in the serving path for that host.
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
# Three independent signals, ORed. Any one of them means the expired GitHub Pages
# origin is still in the serving path for at least one host, so the rule stays
# mandatory. Scanning every .tf in this directory rather than dns.tf alone is what
# makes a `git mv` of the record blocks non-fatal.
#
# Signal 3 (the resource block) is the one the sibling www-apex-canonicalizer.test.sh
# uses. It survives parameterization and record-type changes that defeat the literals,
# and aligning on it removes a divergence where two guards in this directory resolved
# the same stage from different predicates and disagreed under ordinary refactors.
TF_STRIPPED="$WORK/all-tf.stripped"
: > "$TF_STRIPPED"
tf_count=0
for f in "$SCRIPT_DIR"/*.tf; do
  [[ -e "$f" ]] || continue
  sed 's/#.*$//' "$f" >> "$TF_STRIPPED"
  tf_count=$((tf_count + 1))
done
if [[ "$tf_count" -lt 1 ]]; then
  printf '[FATAL] no .tf files found in %s — stage resolution would be meaningless\n' "$SCRIPT_DIR" >&2
  exit 1
fi

PAGES_IPS=0
for ip in 185.199.108.153 185.199.109.153 185.199.110.153 185.199.111.153; do
  grep -qF "\"$ip\"" "$TF_STRIPPED" && PAGES_IPS=$((PAGES_IPS + 1))
done
WWW_PAGES=0
grep -qF 'jikig-ai.github.io' "$TF_STRIPPED" && WWW_PAGES=1
# Scoped to the GitHub-Pages-specific record only. A `www` record SURVIVES the
# cutover (re-pointed at the Pages project), so matching it would keep the guard
# armed forever and defeat the self-retirement the removal condition depends on.
GH_BLOCK=0
grep -qE '^resource "cloudflare_record" "github_pages"' "$TF_STRIPPED" && GH_BLOCK=1

if [[ "$PAGES_IPS" -gt 0 || "$WWW_PAGES" -eq 1 || "$GH_BLOCK" -eq 1 ]]; then
  STAGE="pre-cutover"
else
  STAGE="post-cutover"
fi
printf 'stage: %s (across %d .tf file(s) — pages IPs: %d, github.io target: %s, record block: %s)\n\n' \
  "$STAGE" "$tf_count" "$PAGES_IPS" \
  "$([[ "$WWW_PAGES" -eq 1 ]] && echo yes || echo no)" \
  "$([[ "$GH_BLOCK" -eq 1 ]] && echo yes || echo no)"

# ---------------------------------------------------------------------------------------
# EXTRACT the seo_config_settings ruleset's `rules {}` blocks, IN DECLARATION ORDER
# ---------------------------------------------------------------------------------------
# Declaration order is load-bearing. `set_config` is NON-TERMINATING, and Cloudflare
# documents that for those the LAST matching rule in a phase wins — so a second `ssl`
# rule for these hosts declared BELOW the mitigation overwrites it. (The redirect
# ruleset in seo-bulk-redirects.tf is the opposite: redirects terminate, so first match
# wins there. The two files reason in opposite directions and both are correct.)
# The assertion below is position-agnostic — exactly one such rule — which catches a
# second rule on either side without depending on getting the direction right.
# awk tracks brace depth so a nested `action_parameters {}` cannot end a rules block.
RULES="$WORK/rules.txt"
RESMETA="$WORK/resource-meta.txt"
awk '
  function rhs(line,   i) { i = index(line, "="); return substr(line, i + 1) }
  /^resource "cloudflare_ruleset" "seo_config_settings"/ { inres = 1; depth = 0 }
  inres {
    n = gsub(/\{/, "{"); depth += n
    m = gsub(/\}/, "}"); depth -= m
    if (!inrule) {
      if ($0 ~ /^[[:space:]]*phase[[:space:]]*=/)     { print "phase=" rhs($0) > META }
      if ($0 ~ /^[[:space:]]*kind[[:space:]]*=/)      { print "kind=" rhs($0)  > META }
      if ($0 ~ /^[[:space:]]*count[[:space:]]*=/)     { print "count=present"  > META }
      if ($0 ~ /^[[:space:]]*for_each[[:space:]]*=/)  { print "for_each=present" > META }
      if ($0 ~ /^[[:space:]]*lifecycle[[:space:]]*\{/) { print "lifecycle=present" > META }
    }
    if (inrule) {
      if ($0 ~ /^[[:space:]]*action[[:space:]]*=/)         { act = rhs($0) }
      if ($0 ~ /^[[:space:]]*enabled[[:space:]]*=/)        { en  = rhs($0) }
      if ($0 ~ /^[[:space:]]*expression[[:space:]]*=/)     { ex  = rhs($0) }
      if ($0 ~ /^[[:space:]]*ssl[[:space:]]*=/)            { ssl = rhs($0) }
      if (depth <= ruledepth) {
        idx++
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", act); gsub(/^[[:space:]]+|[[:space:]]+$/, "", en)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", ex);  gsub(/^[[:space:]]+|[[:space:]]+$/, "", ssl)
        printf "%d\taction=%s\tenabled=%s\tssl=%s\texpr=%s\n", idx, act, en, (ssl==""?"-":ssl), ex
        inrule = 0; act=""; en=""; ex=""; ssl=""
      }
      next
    }
    if ($0 ~ /^[[:space:]]*rules[[:space:]]*\{/) { inrule = 1; ruledepth = depth - 1; next }
  }
' META="$RESMETA" "$STRIPPED" > "$RULES"
touch "$RESMETA"

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
# Anchored on the ssl key ONLY. Selecting on the hosts too would make the two host
# assertions below unfalsifiable — they could not run unless the hosts were already
# present. The app.soleur.ai rule also sets ssl, so prefer a rule naming the apex when
# one exists and fall back to the first ssl rule, which is what makes a mis-scoped
# mitigation visible rather than silently unselected.
MITIGATION=$(awk -F'\t' '$4 != "ssl=-" && $5 ~ /\\"soleur\.ai\\"/ { print; exit }' "$RULES")
[[ -n "$MITIGATION" ]] || MITIGATION=$(awk -F'\t' '
  $4 != "ssl=-" && $5 != "expr=\"(http.host eq \\\"app.soleur.ai\\\")\"" { print; exit }
' "$RULES")

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

    # --- 5. EXACTLY ONE ssl rule targets these hosts ---------------------------------
    # `set_config` is non-terminating, so the LAST matching rule in the phase wins: a
    # second `ssl` rule for apex/www declared below this one silently overwrites it.
    # Asserting cardinality rather than position catches it from either side, and does
    # not depend on the reader remembering which direction applies to which rule type.
    # Today the only other ssl rule is scoped to app.soleur.ai, which cannot match —
    # the host anchors below are quote-delimited so that subdomain is not miscounted.
    # Counts by the PRESENCE of an ssl key, not by what the expression spells. An
    # expression need not name a host to match it — `(http.host ne "app.soleur.ai")`
    # and `(true)` both match the apex — so any host-literal predicate is bypassable
    # by a rule that is still perfectly able to overwrite this one.
    ssl_rules=$(awk -F'\t' '
      $4 != "ssl=-" && $5 != "expr=\"(http.host eq \\\"app.soleur.ai\\\")\"" { n++ } END { print n + 0 }
    ' "$RULES")
    rc=1; [[ "$ssl_rules" == "1" ]] && rc=0
    verdict "$rc" "exactly one rule in this ruleset sets ssl outside the app.soleur.ai scope (a second one overwrites this via last-match-wins, whatever its expression spells; found: ${ssl_rules})"
    # --- 6. the RESOURCE cannot be conditionally destroyed --------------------------
    # `count = 0` or a `for_each` over an empty set removes the whole ruleset — all
    # three rules, including this mitigation — while every assertion above still reads
    # a perfectly correct rule block in the file.
    rc=0
    grep -qE '^(count|for_each)=present' "$RESMETA" && rc=1
    verdict "$rc" "the ruleset resource carries no count/for_each (either can destroy every rule in it while the block still reads correctly)"

    # --- 7. Terraform still reconciles the rules -------------------------------------
    # `lifecycle { ignore_changes = [rules] }` means a dashboard deletion is never
    # corrected, so the file and production diverge silently and permanently.
    rc=0
    grep -qE '^lifecycle=present' "$RESMETA" && rc=1
    verdict "$rc" "the ruleset resource declares no lifecycle block (ignore_changes would stop Terraform reconciling an out-of-band deletion)"

    # --- 8/9. the ruleset governs these requests at all -----------------------------
    m_phase=$(grep -m1 '^phase=' "$RESMETA" | sed 's/^phase=//' | tr -d '\" ' | tr -d '\t')
    rc=1; [[ "$m_phase" == "http_config_settings" ]] && rc=0
    verdict "$rc" "the ruleset phase is http_config_settings (found: ${m_phase:-<absent>})"
    m_kind=$(grep -m1 '^kind=' "$RESMETA" | sed 's/^kind=//' | tr -d '\" ' | tr -d '\t')
    rc=1; [[ "$m_kind" == "zone" ]] && rc=0
    verdict "$rc" "the ruleset kind is zone (found: ${m_kind:-<absent>})"
  else
    # Keep the case count stage-stable so the floor below stays an exact cardinality.
    for missing in \
      'the mitigation rule is enabled = true' \
      'the mitigation sets ssl = full, not strict or flexible' \
      'the mitigation expression covers the apex soleur.ai' \
      'the mitigation expression covers www.soleur.ai' \
      'exactly one rule in this ruleset sets ssl' \
      'the ruleset resource carries no count/for_each' \
      'the ruleset resource declares no lifecycle block' \
      'the ruleset phase is http_config_settings' \
      'the ruleset kind is zone'; do
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
    'shadowing unconstrained post-cutover' \
    'count/for_each unconstrained post-cutover' \
    'lifecycle unconstrained post-cutover' \
    'phase unconstrained post-cutover' \
    'kind unconstrained post-cutover'; do
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
# Two comparisons rather than one `-ne`, and the threshold assignment sits IMMEDIATELY
# above the `if` with nothing between them. Both are load-bearing for
# `scripts/guard-vacuity-floor.test.sh`, which promotes this file:
#
#   - it recognises a floor by the `-lt`/`-le`/`-ge` shape, so an `-ne` or `-eq` bound is
#     invisible to it — it can neither mutation-test such a floor nor count it as firing;
#   - it builds its mutant by walking BACKWARDS from the floor line collecting simple
#     assignments to bind the threshold, and stops at the first line that is not one. A
#     comment between `EXPECTED_CASES=` and the `if` leaves the mutant unbound, which that
#     guard reports as a construction failure for an otherwise compliant floor.
#
# Keeping both halves preserves exact cardinality: `-lt` catches a deleted or skipped case,
# `-gt` catches one added without review.
EXPECTED_CASES=10
if [[ "$CASES" -lt "$EXPECTED_CASES" ]]; then
  printf '[FATAL] vacuity floor: only %d assertion cases executed, expected %d — a case was deleted or skipped\n' \
    "$CASES" "$EXPECTED_CASES" >&2
  exit 1
fi
if [[ "$CASES" -gt "$EXPECTED_CASES" ]]; then
  printf '[FATAL] vacuity floor: %d assertion cases executed, expected %d — a case was added without updating EXPECTED_CASES\n' \
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
