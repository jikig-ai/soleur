#!/usr/bin/env bash
# apex-single-node-replace.test.sh — keeps the apex transition on ONE Terraform
# resource address, so Terraform core supplies the Delete→Create ordering (#7640,
# ADR-194, plan §D5).
#
# THE PROPERTY
#
# Cloudflare rejects an `A` and a `CNAME` coexisting at one name with error 81053.
# The ADR-194 cutover must therefore never have the apex `CNAME` create dispatched
# concurrently with the apex `A` deletes. The plan's original answer was a two-pass
# ordered apply; it was cut, because `git revert` of the cutover PR deletes the
# pre-pass along with the DNS hunk (`on: push` runs the workflow from the merged
# ref), so the rollback would have run UNORDERED against an already-failing apex.
#
# What replaced it needs no machinery at all: collapse the transition onto a single
# resource address and let core's replace semantics serialise it. Measured against
# provider 4.52.7 / Terraform 1.10.5 — `type` is ForceNew, so `A`→`CNAME` at one
# address plans as actions ["delete","create"], one address, inherently ordered.
#
# So there is no sequence left to assert and no plan document to grade. The residual
# risk is that a LATER edit silently removes the property core is providing, and that
# is a static question about `dns.tf` — answerable with no plan, no credentials and no
# fixtures. That is this guard, and it is why it is small.
#
# WHY IT SHIPS IN PR4a, ONE MERGE BEFORE THE THING IT GUARDS
#
# It must be green on `main` in the window BETWEEN the two merges, or it blocks PR4a's
# own CI and every unrelated infra PR until PR4b lands. Hence the stage resolution
# below: both the pre-flip and post-flip shapes are legal inputs, and each stage
# asserts the shape THAT stage requires. Every case executes in every stage — a
# skipped case is a vacuity hole, and the case count is the anti-vacuity floor's only
# input.
#
# THE QUANTIFIER IS STRUCTURAL, NOT A MEMBER LIST
#
# The apex-record cases quantify over EVERY `cloudflare_record` block in `dns.tf`
# whose `name` resolves to the apex and whose `type` is an address type — not over an
# enumerated list of the addresses this cutover happens to touch. A future sibling
# apex record added by anyone is caught by the quantifier rather than by someone
# remembering to extend a list. `name = "soleur.ai"` is also carried by the Protonmail
# MX and four TXT records, which are NOT address records and must not be counted; the
# type filter is what excludes them.
#
# THE TWO-MERGE CONTRACT LITERAL
#
# `SURVIVING_APEX_KEY` is the one `for_each` key PR4a leaves behind and PR4b's `moved`
# block must name byte-identically. It is pinned here because after the flip `dns.tf`
# no longer declares `github_pages` at all, so there is nothing left in the file to
# compare the `moved.from` index against. Both stages assert it against the real file
# — pre-flip against the surviving `for_each` set, post-flip against the `moved.from`
# index — which is what makes the mismatch detectable at all. Terraform does NOT error
# on a `moved` whose source is absent from state: it no-ops, `pages_apex` plans as a
# bare create, the real survivor plans as a separate delete, and the 81053 hazard is
# restored with no signal anywhere. This is the only detection there is.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

DNS_TF="${APEX_GUARD_DNS_TF:-$SCRIPT_DIR/dns.tf}"
APPLY_WF="${APEX_GUARD_APPLY_WF:-$REPO_ROOT/.github/workflows/apply-web-platform-infra.yml}"
VALIDATION_WF="${APEX_GUARD_VALIDATION_WF:-$REPO_ROOT/.github/workflows/infra-validation.yml}"

SURVIVING_APEX_KEY="185.199.108.153"

PASS=0
FAIL=0
CASES=0

pass() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1"; }

# CASES moves in exactly ONE place, and it is a WRAPPER calling the verdict helpers
# rather than touching PASS/FAIL itself (AP-023, ADR-193 Decision #2). That keeps the
# accounting identity at the bottom non-tautological: stub `pass` or `fail` to a no-op
# and CASES keeps climbing while PASS+FAIL does not, so the identity fires. A counter
# incremented INSIDE both verdict helpers moves WITH the verdict, so a deleted row and
# its count vanish together and the identity holds under the exact fault it catches.
verdict() { # <rc> <name>
  CASES=$((CASES + 1))
  if [[ "$1" -eq 0 ]]; then pass "$2"; else fail "$2"; fi
}

for required in "$DNS_TF" "$APPLY_WF" "$VALIDATION_WF"; do
  if [[ ! -r "$required" ]]; then
    printf '[FATAL] required input not readable: %s\n' "$required" >&2
    exit 2
  fi
done

# ---------------------------------------------------------------------------------------
# READERS
# ---------------------------------------------------------------------------------------

# Strip `#` and `//` line comments while tracking string state, so a `#` inside a quoted
# value and a `//` inside a URL both survive. Every assertion runs against the stripped
# view: a body-grep for a bare token otherwise matches the explanatory comment written to
# explain the token, and the assertion passes by reading documentation instead of config.
strip_comments() { # <file>
  awk '
    {
      line = $0; out = ""; q = ""; i = 1; n = length(line)
      while (i <= n) {
        c = substr(line, i, 1)
        if (q != "") {
          if (c == "\\") { out = out c substr(line, i + 1, 1); i += 2; continue }
          if (c == q) { q = "" }
          out = out c; i++; continue
        }
        if (c == "\"" || c == "'"'"'") { q = c; out = out c; i++; continue }
        if (c == "#") { break }
        if (c == "/" && substr(line, i + 1, 1) == "/") { break }
        out = out c; i++
      }
      print out
    }
  ' "$1"
}

DNS_STRIPPED="$(strip_comments "$DNS_TF")"

# Emit `<resource-name>\t<type>\t<has_cbd>` for every `cloudflare_record` block whose
# `name` resolves to the apex AND whose `type` is an ADDRESS type. Brace-depth scoped so a
# nested block cannot truncate the read. `@` is accepted alongside the FQDN because either
# spelling addresses the zone root.
apex_address_records() {
  awk '
    !inb && $0 ~ /^resource[[:space:]]+"cloudflare_record"[[:space:]]+"[^"]+"/ {
      match($0, /"cloudflare_record"[[:space:]]+"[^"]+"/)
      seg = substr($0, RSTART, RLENGTH)
      sub(/^"cloudflare_record"[[:space:]]+"/, "", seg); sub(/"$/, "", seg)
      rname = seg; inb = 1; depth = 0; rec_name = ""; rec_type = ""; cbd = 0
    }
    inb {
      if ($0 ~ /^[[:space:]]*name[[:space:]]*=/ && rec_name == "") {
        v = $0; sub(/^[[:space:]]*name[[:space:]]*=[[:space:]]*/, "", v)
        gsub(/[[:space:]]+$/, "", v); gsub(/^"|"$/, "", v); rec_name = v
      }
      if ($0 ~ /^[[:space:]]*type[[:space:]]*=/ && rec_type == "") {
        v = $0; sub(/^[[:space:]]*type[[:space:]]*=[[:space:]]*/, "", v)
        gsub(/[[:space:]]+$/, "", v); gsub(/^"|"$/, "", v); rec_type = v
      }
      if ($0 ~ /create_before_destroy[[:space:]]*=[[:space:]]*true/) { cbd = 1 }
      d = gsub(/\{/, "{"); depth += d
      d = gsub(/\}/, "}"); depth -= d
      if (depth <= 0) {
        inb = 0
        if ((rec_name == "soleur.ai" || rec_name == "@") &&
            (rec_type == "A" || rec_type == "AAAA" || rec_type == "CNAME")) {
          printf "%s\t%s\t%d\n", rname, rec_type, cbd
        }
      }
    }
  ' <<<"$DNS_STRIPPED"
}

# One `moved { from = … to = … }` block, brace-depth scoped, as `<from>\t<to>`.
moved_pairs() {
  awk '
    !inb && $0 ~ /^moved[[:space:]]*\{/ { inb = 1; depth = 0; f = ""; t = "" }
    inb {
      if ($0 ~ /^[[:space:]]*from[[:space:]]*=/) {
        v = $0; sub(/^[[:space:]]*from[[:space:]]*=[[:space:]]*/, "", v); gsub(/[[:space:]]+$/, "", v); f = v
      }
      if ($0 ~ /^[[:space:]]*to[[:space:]]*=/) {
        v = $0; sub(/^[[:space:]]*to[[:space:]]*=[[:space:]]*/, "", v); gsub(/[[:space:]]+$/, "", v); t = v
      }
      d = gsub(/\{/, "{"); depth += d
      d = gsub(/\}/, "}"); depth -= d
      if (depth <= 0) { inb = 0; printf "%s\t%s\n", f, t }
    }
  ' <<<"$DNS_STRIPPED"
}

# First `key = value` in a block, anchored on ASSIGNMENT SYNTAX. One awk process, never
# `grep … | head -1`: under `set -o pipefail` head exits after the first line, grep dies of
# SIGPIPE (141), pipefail promotes it and the run aborts exactly when it found its match.
attr() { # <key> <blocktext>
  awk -v k="$1" '
    !seen && $0 ~ "^[[:space:]]*" k "[[:space:]]*=" {
      sub("^[[:space:]]*" k "[[:space:]]*=[[:space:]]*", "")
      sub("[[:space:]]+$", "")
      print; seen = 1
    }
  ' <<<"$2"
}

unquote() { local s="$1"; s="${s#\"}"; s="${s%\"}"; printf '%s' "$s"; }

hcl_block() { # <type> <name>
  awk -v t="$1" -v n="$2" '
    !inb && $0 ~ "^resource[[:space:]]+\"" t "\"[[:space:]]+\"" n "\"" { inb = 1; depth = 0 }
    inb {
      print
      d = gsub(/\{/, "{"); depth += d
      d = gsub(/\}/, "}"); depth -= d
      if (depth <= 0) { inb = 0 }
    }
  ' <<<"$DNS_STRIPPED"
}

# ---------------------------------------------------------------------------------------
# STAGE RESOLUTION
# ---------------------------------------------------------------------------------------
# Resolved from whether `pages_apex` is DECLARED — not from the apex record's own type, so
# a mutation that repoints the apex by rewriting its type cannot re-derive the stage to
# match itself.
PAGES_APEX_BLOCK="$(hcl_block cloudflare_record pages_apex)"
if [[ -n "$PAGES_APEX_BLOCK" ]]; then
  STAGE="post-flip"
else
  STAGE="pre-flip"
fi

APEX_RECS="$(apex_address_records)"
APEX_COUNT=0
[[ -n "$APEX_RECS" ]] && APEX_COUNT="$(printf '%s\n' "$APEX_RECS" | wc -l | tr -d ' ')"

printf 'apex-single-node-replace: stage=%s, apex address records=%d\n\n' "$STAGE" "$APEX_COUNT"

# ---------------------------------------------------------------------------------------
# STAGE-INDEPENDENT CASES
# ---------------------------------------------------------------------------------------

# M7 — the second-member row. A guard that stops at the first matching apex block, or that
# checks only the addresses it expects BY NAME, passes a second apex `A` added alongside a
# correct `pages_apex` while the zone again carries A-and-CNAME at one name.
rc=1; [[ "$APEX_COUNT" -eq 1 ]] && rc=0
verdict "$rc" "exactly one apex address record in dns.tf (found ${APEX_COUNT}: $(printf '%s' "${APEX_RECS//$'\n'/, }" | tr '\t' ':'))"

# M1 — the core row. `create_before_destroy` on the apex silently INVERTS the one ordering
# Cloudflare rejects: the CNAME create would be dispatched before the A delete. It reads as
# a safety improvement and nothing else in CI notices. Quantified over every apex address
# record, so it cannot be reintroduced on a sibling.
cbd_offenders=""
while IFS=$'\t' read -r rname rtype rcbd; do
  [[ -z "${rname:-}" ]] && continue
  [[ "$rcbd" == "1" ]] && cbd_offenders="${cbd_offenders}${rname} "
done <<<"$APEX_RECS"
rc=1; [[ -z "$cbd_offenders" ]] && rc=0
verdict "$rc" "no apex address record declares create_before_destroy (offenders: ${cbd_offenders:-none})"

# M4 — Camp B. `type` is ForceNew at 4.52.7 (measured), so an `A` at www becomes a SECOND
# replacement racing the first and moves PR4b's destroy_count to 2.
WWW_BLOCK="$(hcl_block cloudflare_record www)"
WWW_TYPE="$(unquote "$(attr type "$WWW_BLOCK")")"
rc=1; [[ "$WWW_TYPE" == "CNAME" ]] && rc=0
verdict "$rc" "www stays a CNAME so it cannot become a second ForceNew replacement (found: ${WWW_TYPE:-<absent>})"

# M5/M6 — a `moved` block whose endpoints are not BOTH in the apply allow-list does not
# mis-plan, it HARD-ERRORS: `Error: Moved resource instances excluded by targeting`
# (measured). The apply job's plan is `-target`-scoped, so both literals must be present.
#
# Line-anchored, and that anchor is load-bearing: `-target=cloudflare_record.github_pages`
# is a strict PREFIX of `-target=cloudflare_record.github_pages_challenge`, so an unanchored
# grep for the former is satisfied by the latter and M5 passes while the endpoint is gone.
APPLY_STRIPPED="$(sed 's/[[:space:]]*\\$//' "$APPLY_WF")"
for endpoint in cloudflare_record.github_pages cloudflare_record.pages_apex; do
  rc=1
  grep -qE "^[[:space:]]*-target=${endpoint//./\\.}[[:space:]]*$" <<<"$APPLY_STRIPPED" && rc=0
  verdict "$rc" "apply allow-list targets ${endpoint} (line-anchored; prefix-siblings do not satisfy it)"
done

# M9 — the own-dispatch row. A guard nobody runs is a guard that passes by never running.
# This is the www-apex-canonicalizer chokepoint lesson applied to this guard's own
# registration: `infra-validation.yml` runs explicit `run:` steps, never a glob, so an
# unregistered suite silently never gates.
rc=1
grep -qF 'apex-single-node-replace.test.sh' "$VALIDATION_WF" && rc=0
verdict "$rc" "this guard is registered in infra-validation.yml (an unregistered suite never gates)"

# ---------------------------------------------------------------------------------------
# STAGE-DEPENDENT CASES — three in each stage, so the floor stays an EXACT cardinality
# ---------------------------------------------------------------------------------------
if [[ "$STAGE" == "pre-flip" ]]; then
  # PR4a's shape: `github_pages` survives with exactly one `for_each` key, and that key is
  # the literal PR4b's `moved.from` must name. Asserting it HERE is what makes M3
  # detectable one merge later — this is the only place the survivor is still declared.
  GH_BLOCK="$(hcl_block cloudflare_record github_pages)"
  keys="$(grep -oE '"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"' <<<"$GH_BLOCK" | tr -d '"' || true)"
  key_count=0
  [[ -n "$keys" ]] && key_count="$(printf '%s\n' "$keys" | wc -l | tr -d ' ')"
  rc=1; [[ "$key_count" -eq 1 && "$keys" == "$SURVIVING_APEX_KEY" ]] && rc=0
  verdict "$rc" "pre-flip: github_pages carries exactly the one for_each key ${SURVIVING_APEX_KEY} (found ${key_count}: ${keys//$'\n'/, })"

  GH_TYPE="$(unquote "$(attr type "$GH_BLOCK")")"
  rc=1; [[ "$GH_TYPE" == "A" ]] && rc=0
  verdict "$rc" "pre-flip: the apex origin is still the github_pages A record (found: ${GH_TYPE:-<absent>})"

  rc=1; [[ -z "$(moved_pairs)" ]] && rc=0
  verdict "$rc" "pre-flip: no moved block yet (the flip is PR4b's merge, not this one)"
else
  # M2 — deleting the `moved` block leaves the old and new declarations as two unrelated
  # addresses: the exact plan measured as `1 to add … 1 to destroy` across two addresses,
  # dispatched concurrently.
  MOVED="$(moved_pairs)"
  moved_to_apex=""
  while IFS=$'\t' read -r mfrom mto; do
    [[ -z "${mto:-}" ]] && continue
    [[ "$mto" == "cloudflare_record.pages_apex" ]] && moved_to_apex="$mfrom"
  done <<<"$MOVED"
  rc=1; [[ -n "$moved_to_apex" ]] && rc=0
  verdict "$rc" "post-flip: a moved block re-addresses the survivor to cloudflare_record.pages_apex"

  # M3 — THE silent-failure row, and the highest-value case in this file. Terraform does not
  # error on a moved whose source is absent from state; it no-ops.
  want="cloudflare_record.github_pages[\"${SURVIVING_APEX_KEY}\"]"
  rc=1; [[ "$moved_to_apex" == "$want" ]] && rc=0
  verdict "$rc" "post-flip: moved.from is byte-identical to the key PR4a left — want ${want}, got ${moved_to_apex:-<absent>}"

  PAGES_APEX_TYPE="$(unquote "$(attr type "$PAGES_APEX_BLOCK")")"
  rc=1; [[ "$PAGES_APEX_TYPE" == "CNAME" ]] && rc=0
  verdict "$rc" "post-flip: pages_apex is a CNAME (found: ${PAGES_APEX_TYPE:-<absent>})"
fi

# ---------------------------------------------------------------------------------------
# ANTI-VACUITY FLOOR AND ACCOUNTING (AP-023 / ADR-193)
# ---------------------------------------------------------------------------------------
# Both report with `printf >&2` + `exit 1`, NEVER through this suite's own `fail`. A floor
# routed through `fail` is disarmed by the same one-line edit that disarms every assertion
# it exists to witness.
#
# EXACT cardinality, not a lower bound, and identical in both stages by construction (the
# stage branches are padded to the same count). Bump deliberately when adding a case; do not
# derive it from anything this file computes, which would make it a tautology.
printf '\n'
# Two comparisons rather than one `-ne`, and the threshold assignment sits IMMEDIATELY above
# the `if` with nothing between them. Both are load-bearing for
# `scripts/guard-vacuity-floor.test.sh`, which promotes this file: it recognises a floor by
# the `-lt`/`-le`/`-ge` shape, so an `-ne` or `-eq` bound is invisible to it.
EXPECTED_CASES=9
if [[ "$CASES" -lt "$EXPECTED_CASES" ]]; then
  printf '[VACUITY] only %d case(s) ran, expected exactly %d — a case was deleted or skipped\n' "$CASES" "$EXPECTED_CASES" >&2
  exit 1
fi
if [[ "$CASES" -gt "$EXPECTED_CASES" ]]; then
  printf '[VACUITY] %d case(s) ran, expected exactly %d — bump EXPECTED_CASES deliberately\n' "$CASES" "$EXPECTED_CASES" >&2
  exit 1
fi
# The accounting identity: CASES is incremented by the wrapper, PASS/FAIL by the helpers it
# calls. Stub either helper to a no-op and these diverge.
if [[ "$((PASS + FAIL))" -lt "$CASES" ]]; then
  printf '[VACUITY] accounting identity broken: PASS+FAIL=%d < CASES=%d — a verdict helper is not recording\n' "$((PASS + FAIL))" "$CASES" >&2
  exit 1
fi

printf 'apex-single-node-replace: %d passed, %d failed (%d cases, stage=%s)\n' "$PASS" "$FAIL" "$CASES" "$STAGE"
[[ "$FAIL" -eq 0 ]] || exit 1
