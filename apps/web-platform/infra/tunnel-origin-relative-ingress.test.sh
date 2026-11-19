#!/usr/bin/env bash
# Drift guard: NO tunnel ingress rule may carry a connector-relative service.
#
# ADR-114 I2 / #6425 / #6483 / #6594. This is ONE tunnel with MULTIPLE connector
# replicas and CF load-balances across them, so a `localhost:` service resolves on
# WHICHEVER replica answers. #6594: the infra-config POST was a coin-flipped WRITE
# self-verified against a separately coin-flipped READ, and the verify gate's retry
# loop laundered it into a green while #6577's ci-deploy.sh never reached web-1.
#
# UNIVERSAL, not per-hostname (review: architecture-strategist P2). I2 governs "any
# route whose correctness depends on which host answers" — so this asserts the
# invariant over EVERY ingress_rule and keeps an explicit (currently empty) allowlist
# for genuinely host-agnostic routes. An enumerated `deploy.`/`ssh.` guard passes
# while a NEW rule ships `localhost:`.
#
# It also closes the shadow-rule defeat (review: test-design-reviewer P1): CF ingress
# is first-match on hostname AND path, so
#     ingress_rule { hostname = "deploy.<base>", path = "/healthz", service = <pinned> }
#     ingress_rule { hostname = "deploy.<base>",                    service = "http://localhost:9000" }
# would satisfy a first-match-wins extractor while the real POST (path /hooks/...)
# falls through to the coin flip. Asserting over ALL rules makes rule ORDER and PATH
# irrelevant — the property is "no rule can serve this route from the wrong host".
#
# COMMENTS ARE STRIPPED BEFORE PARSING (review: test-design-reviewer P1). tunnel.tf's
# prose quotes `ssh://localhost:22` verbatim while explaining why it is wrong, so a
# naive parse can be defeated in BOTH directions: a `#` comment can satisfy the
# invariant, and a `/* */`-commented-out pinned service can shadow a live localhost
# line (awk has no block-comment awareness and last-assignment-wins). Stripping first
# makes the guard comment-blind rather than comment-anchored.
#
# `[[:space:]]*` around `=` rather than a literal space: `terraform fmt` re-aligns the
# equals column when a block gains an attribute (#5132).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF="$SCRIPT_DIR/tunnel.tf"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
INFRA_VALIDATION="$REPO_ROOT/.github/workflows/infra-validation.yml"

# Routes that may legitimately be connector-relative (host-agnostic). EMPTY by design:
# every route on this tunnel today is host-specific. Adding an entry is a deliberate
# I2 exemption and must carry a rationale.
ALLOW_CONNECTOR_RELATIVE=()

# Routes that MUST resolve to web-1 via var.web_hosts (never a hardcoded IP).
REQUIRE_WEB1_ORIGIN=(deploy ssh)

fails=0
pass() { echo "  PASS: $1"; }
fail() {
  echo "  FAIL: $1" >&2
  fails=$((fails + 1))
}

echo "tunnel-origin-relative-ingress.test.sh"

# `-r` not `-f`: an unreadable file must fail with THIS message, not raw awk noise.
if [[ ! -r "$TF" ]]; then
  echo "FATAL: $TF not found or not readable" >&2
  exit 1
fi

# --- Emit "hostname|service" for EVERY ingress_rule, comments stripped ------------
# Two passes: (1) blank /* */ spans and drop whole-line # and // comments, so no
# prose can satisfy or defeat any assertion; (2) walk ingress_rule blocks by brace
# depth (depth-aware, so a nested origin_request {} cannot close the block early)
# and emit one record per rule.
rules_by_res="$(
  awk '
    # --- pass 1: strip comments, STRING-AWARE ---
    # The string tracking is load-bearing, not defensive polish: without it the `//`
    # in `http://localhost:9000` reads as a line comment and the value is truncated to
    # `http:` — which SILENTLY DEFEATS the universal localhost assertion (AC1 can then
    # never fire). Caught by the sandbox baseline, not by reasoning.
    {
      line = $0
      out = ""
      i = 1
      instr = 0
      while (i <= length(line)) {
        ch = substr(line, i, 1)
        c2 = substr(line, i, 2)
        if (inblockcomment) {
          if (c2 == "*/") { inblockcomment = 0; i += 2; continue }
          i++; continue
        }
        if (instr) {
          # A backslash escape inside a string consumes the next char verbatim, so an
          # escaped quote cannot end the string.
          if (ch == "\\") { out = out substr(line, i, 2); i += 2; continue }
          if (ch == "\"") { instr = 0 }
          out = out ch
          i++
          continue
        }
        if (ch == "\"") { instr = 1; out = out ch; i++; continue }
        if (c2 == "/*") { inblockcomment = 1; i += 2; continue }
        if (c2 == "//") { break }
        if (ch == "#") { break }
        out = out ch
        i++
      }
      print out
    }
  ' "$TF" | awk '
    # --- pass 2: extract ingress_rule records ---
    /^resource "cloudflare_zero_trust_tunnel_cloudflared_config"/ { inres = 1; split($0, q, "\""); res = q[4] }
    inres && /ingress_rule[[:space:]]*\{/ {
      inrule = 1; depth = 0; host = ""; svc = ""
    }
    inrule {
      n = gsub(/\{/, "{"); depth += n
      n = gsub(/\}/, "}"); depth -= n
      if ($0 ~ /^[[:space:]]*hostname[[:space:]]*=/) {
        host = $0
        sub(/^[[:space:]]*hostname[[:space:]]*=[[:space:]]*/, "", host)
        sub(/^"/, "", host); sub(/"[[:space:]]*$/, "", host)
      }
      if ($0 ~ /^[[:space:]]*service[[:space:]]*=/) {
        svc = $0
        sub(/^[[:space:]]*service[[:space:]]*=[[:space:]]*/, "", svc)
        # Strip ONLY the surrounding quote pair — a gsub of every quote also eats the
        # inner quotes of var.web_hosts["web-1"], silently defeating the var assert.
        sub(/^"/, "", svc); sub(/"[[:space:]]*$/, "", svc)
      }
      if (depth <= 0) {
        if (svc != "") { print res "\t" host "|" svc }
        inrule = 0
      }
    }
  '
)"

# Each record is "<config resource name>\t<hostname>|<service>"; every assertion below reads the
# rule half, and AC4 (#12937) compares the two config resources' rule sets.
rules="$(cut -f2- <<<"$rules_by_res")"

rule_count=0
[[ -n "$rules" ]] && rule_count=$(printf '%s\n' "$rules" | grep -c '|') || true

# --- AC0: the extractor actually saw the file --------------------------------------
# A REAL cardinality assert: it counts rules EXTRACTED, not turns of a literal list.
# The previous `for host in deploy ssh; do n_checked++` incremented unconditionally
# over a two-element literal, so it was always 2 and could never fire — it asserted
# that bash can iterate (review: test-design-reviewer P2 + pattern-recognition P2).
# tunnel.tf ships deploy./ssh./registry. + a catch-all; require >= 3 service-bearing
# rules so a blinded extractor fails LOUD instead of vacuously passing AC1.
MIN_RULES=3
if [[ "$rule_count" -lt "$MIN_RULES" ]]; then
  fail "extracted only $rule_count ingress_rule(s) with a service; expected >= $MIN_RULES — the parse broke and every assertion below is vacuous"
else
  pass "extracted $rule_count service-bearing ingress_rule(s)"
fi

# --- AC1 (universal): no rule may be connector-relative -----------------------------
connector_relative=0
while IFS='|' read -r host svc; do
  [[ -z "$svc" ]] && continue
  allowed=0
  for a in ${ALLOW_CONNECTOR_RELATIVE[@]+"${ALLOW_CONNECTOR_RELATIVE[@]}"}; do
    [[ "$host" == "$a" ]] && allowed=1
  done
  if [[ "$svc" == *localhost* || "$svc" == *127.0.0.1* ]]; then
    if [[ "$allowed" -eq 1 ]]; then
      pass "${host:-<no-hostname>}: connector-relative but explicitly allowlisted"
    else
      fail "${host:-<no-hostname>}: service is connector-relative ($svc) — ADR-114 I2. CF load-balances across connector replicas, so this resolves on whichever host answers (#6425/#6594). Pin the origin, or add the hostname to ALLOW_CONNECTOR_RELATIVE with a rationale."
      connector_relative=$((connector_relative + 1))
    fi
  fi
done <<< "$rules"
[[ "$connector_relative" -eq 0 ]] && pass "no ingress_rule is connector-relative (checked $rule_count)"

# --- AC2: deploy./ssh. resolve to web-1 via var.web_hosts (never a hardcoded IP) ----
for want in "${REQUIRE_WEB1_ORIGIN[@]}"; do
  matched=0
  bad=0
  while IFS='|' read -r host svc; do
    [[ "$host" == "$want."* ]] || continue
    matched=$((matched + 1))
    # #9421 Part 2a: ssh. targets the keyed jump host (exactly one, variables.tf), still derived from var.web_hosts.
    if [[ "$svc" != *'var.web_hosts["web-1"].private_ip'* && ! ( "$want" == ssh && "$svc" == *'one([for h in values(var.web_hosts) : h.private_ip if h.jump])'* ) ]]; then
      fail "$want.: service ($svc) does not derive its origin from var.web_hosts (the keyed jump host for ssh.) — never hardcode a web address"
      bad=$((bad + 1))
    fi
  done <<< "$rules"

  if [[ "$matched" -eq 0 ]]; then
    fail "$want.: no ingress_rule found — extraction broke, or the route was removed (guard would be blind)"
  elif [[ "$bad" -eq 0 ]]; then
    # Gated on bad==0: an unconditional pass here prints "all origin-pinned" in the
    # same breath as a FAIL naming one that isn't — a PASS line that reports coverage
    # it did not measure is the exact false-reassurance this suite exists to reject.
    pass "$want.: $matched rule(s) found, all origin-pinned via var.web_hosts"
  fi
done

# --- AC4 (#12937): the Soleur-account tunnel config carries the SAME rules as the old one ---------
# The zone move re-homed the tunnel as `_config.web_soleur` beside the untouched `_config.web`. Its
# rules must be derived from the same expressions (ADR-114 I2 holds for both) — compared as the
# exact sorted record set, so a drifted, missing or extra rule on either side reds.
rules_of() { awk -F'\t' -v r="$2" '$1 == r { print $2 }' <<<"$1" | LC_ALL=C sort; }
same_rules() { # <records> -> 0 when web and web_soleur hold identical, 4-rule sets
  local a b; a="$(rules_of "$1" web)"; b="$(rules_of "$1" web_soleur)"
  [[ -n "$b" && "$(grep -c . <<<"$b")" -eq 4 && "$a" == "$b" ]]
}
if same_rules "$rules_by_res"; then
  pass "_config.web_soleur carries exactly _config.web's 4 rules (same expressions)"
else
  fail "_config.web_soleur's ingress rules differ from _config.web's (or it is missing / not 4 rules) — re-derive them from the same expressions"
fi
mut_rules="$(sed -E 's#^(web_soleur\tregistry\.[^|]*\|)tcp://#\1http://#' <<<"$rules_by_res")"
if [[ "$mut_rules" != "$rules_by_res" ]] && ! same_rules "$mut_rules"; then
  pass "AC4 mutation: a web_soleur registry rule rewritten to http:// is caught"
else
  fail "AC4 mutation did not land or was not caught — the comparison is vacuous"
fi

# --- AC5 (#12937): the connector census reads the tunnel in the account tunnel.tf creates it in ----------
# The id literal lives ONCE, in scripts/tunnel-connector-census.sh; the scheduled census step reads it after
# sourcing that file, never Doppler CF_ACCOUNT_ID (the pre-zone-move account).
P_TMP="$(mktemp -d)"
trap 'rm -rf "$P_TMP"' EXIT
acct_of() { grep -E '^[[:space:]]*cf_soleur_account_id[[:space:]]*=' "$1" | sed -E 's/.*"([0-9a-f]{32})".*/\1/'; }
TF_ACCT="$(acct_of "$TF")"
CENSUS_ACCT="$(bash -c 'source "$1" >/dev/null 2>&1; printf "%s" "${CF_TUNNEL_ACCOUNT_ID:-}"' _ "$REPO_ROOT/scripts/tunnel-connector-census.sh")"
if [[ -n "$TF_ACCT" && "$CENSUS_ACCT" == "$TF_ACCT" ]]; then
  pass "census CF_TUNNEL_ACCOUNT_ID equals tunnel.tf local.cf_soleur_account_id"
else
  fail "census CF_TUNNEL_ACCOUNT_ID ('$CENSUS_ACCT') differs from tunnel.tf local.cf_soleur_account_id ('$TF_ACCT')"
fi
sed -E 's/^([[:space:]]*cf_soleur_account_id[[:space:]]*=[[:space:]]*")[0-9a-f]{32}"/\1ffffffffffffffffffffffffffffffff"/' "$TF" >"$P_TMP/tunnel-mut.tf"
MUT_ACCT="$(acct_of "$P_TMP/tunnel-mut.tf")"
if [[ "$MUT_ACCT" == "ffffffffffffffffffffffffffffffff" && "$CENSUS_ACCT" != "$MUT_ACCT" ]]; then
  pass "AC5 mutation: a tunnel.tf account that differs from the census literal is caught"
else
  fail "AC5 mutation did not land or was not caught"
fi
CENSUS_WF="$REPO_ROOT/.github/workflows/scheduled-inngest-health.yml"
census_step() { awk '/- name: Census tunnel connectors \(ADR-114 I1\)/{f=1} f&&/^      - name: /&&!/Census tunnel connectors/{exit} f' "$1" | grep -vE '^[[:space:]]*#'; }
reads_tunnel_acct() { local cs; cs="$(census_step "$1")"; grep -qF 'CF_ACCOUNT_ID="${CF_TUNNEL_ACCOUNT_ID:-}"' <<<"$cs" && ! grep -qF 'secrets get CF_ACCOUNT_ID' <<<"$cs"; }
if reads_tunnel_acct "$CENSUS_WF"; then
  pass "the census step takes its account from CF_TUNNEL_ACCOUNT_ID, not Doppler CF_ACCOUNT_ID"
else
  fail "the census step does not read CF_TUNNEL_ACCOUNT_ID (or still reads Doppler CF_ACCOUNT_ID)"
fi
sed 's/CF_ACCOUNT_ID="${CF_TUNNEL_ACCOUNT_ID:-}"/CF_ACCOUNT_ID="${CF_ACCOUNT_ID_FROM_DOPPLER:-}"/' "$CENSUS_WF" >"$P_TMP/census-mut.yml"
if ! cmp -s "$CENSUS_WF" "$P_TMP/census-mut.yml" && ! reads_tunnel_acct "$P_TMP/census-mut.yml"; then
  pass "AC5 mutation: a census step that no longer reads CF_TUNNEL_ACCOUNT_ID is caught"
else
  fail "AC5 census mutation did not land or was not caught"
fi

# --- AC3: this guard is actually wired into CI --------------------------------------
# Since #8736 presence under apps/web-platform/infra/ IS registration — the
# deploy-script-tests matrix legs glob-derive and run it — so an unregistered
# suite can no longer ship as zero coverage, and what remains to pin is the
# CONNECTION: the legs' run-registered-suites.sh invocation.
if [[ ! -r "$INFRA_VALIDATION" ]]; then
  fail "infra-validation.yml not readable at $INFRA_VALIDATION — cannot verify this guard is wired into CI"
elif grep -qE 'run: bash apps/web-platform/infra/run-registered-suites\.sh' "$INFRA_VALIDATION"; then
  pass "the suite runner is invoked in infra-validation.yml (glob registration since #8736)"
else
  fail "the suite runner is NOT invoked in infra-validation.yml — no infra suite would run in CI (silent zero coverage)"
fi

if [[ "$fails" -gt 0 ]]; then
  echo "FAILED ($fails)" >&2
  exit 1
fi
echo "OK"
