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

# TEST SEAM, FAIL-CLOSED IN CI. The mutation battery drives this guard against
# fixture trees. A seam that a CI environment could set would silently redirect
# the guard at a fixture and report green about a file nobody shipped, so the
# overrides are refused whenever CI is set.
APEX_GUARD_TF_DIR="${APEX_GUARD_TF_DIR:-$SCRIPT_DIR}"
APPLY_WF="${APEX_GUARD_APPLY_WF:-$REPO_ROOT/.github/workflows/apply-web-platform-infra.yml}"
VALIDATION_WF="${APEX_GUARD_VALIDATION_WF:-$REPO_ROOT/.github/workflows/infra-validation.yml}"
if [[ -n "${CI:-}" ]]; then
  for seam in APEX_GUARD_TF_DIR APEX_GUARD_APPLY_WF APEX_GUARD_VALIDATION_WF; do
    if [[ -n "${!seam:-}" && "${!seam}" != "${seam_default:-}" ]]; then
      case "$seam" in
        APEX_GUARD_TF_DIR)        [[ "$APEX_GUARD_TF_DIR" == "$SCRIPT_DIR" ]] || { printf '[FATAL] %s is set under CI — refusing to run against a fixture\n' "$seam" >&2; exit 2; } ;;
        APEX_GUARD_APPLY_WF)      [[ "$APPLY_WF" == "$REPO_ROOT/.github/workflows/apply-web-platform-infra.yml" ]] || { printf '[FATAL] %s is set under CI\n' "$seam" >&2; exit 2; } ;;
        APEX_GUARD_VALIDATION_WF) [[ "$VALIDATION_WF" == "$REPO_ROOT/.github/workflows/infra-validation.yml" ]] || { printf '[FATAL] %s is set under CI\n' "$seam" >&2; exit 2; } ;;
      esac
    fi
  done
fi

# WHAT THIS GUARD CANNOT SEE, STATED SO NOBODY READS IT AS COVERED.
#
# The contract's real counterparty is Terraform STATE, and this guard is static
# by construction. A CONSISTENT repo-side rename of the survivor — this pin and
# the dns.tf key changed together — satisfies every case here while the state
# still holds the OLD key, so PR4b's `moved.from` would name a key absent from
# state and Terraform would no-op the move with no error. Measured: that
# co-mutation passes 11/11.
#
# The same blindness covers a PR4a that merges but does not CONVERGE
# ([skip-web-platform-apply], or a failed apply): the repo says one key while
# state holds four. `[ack-destroy]` cannot discriminate either, because
# destroy_count is 1 in both the correct and the broken PR4b plan.
#
# The mechanism that DOES cover it is PF9b, asserted against plan JSON rather
# than against text: the `pages_apex` resource_change must carry
# `previous_address == cloudflare_record.github_pages["<survivor>"]`. That is a
# PR4b deliverable (tasks.md 2.9); do not read this guard as a substitute.
#
# The one key PR4a leaves behind and PR4b's `moved` block must name
# byte-identically. Pinned here because after the flip no .tf declares
# `github_pages` at all, so nothing is left in the tree to compare against.
SURVIVING_APEX_KEY="185.199.108.153"

# The apex zone name, normalised. `@` and a trailing-dot FQDN address the same
# zone root, and DNS names are case-insensitive — all three spellings are
# folded before comparison so none of them escapes the quantifier.
APEX_ZONE="soleur.ai"

PASS=0
FAIL=0
CASES=0

pass() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1"; }

# CASES moves in exactly ONE place, and it is a WRAPPER calling the verdict
# helpers rather than touching PASS/FAIL itself (AP-023, ADR-193 Decision #2).
#
# `==` rather than `-eq`: `[[ "" -eq 0 ]]` is TRUE in bash (arithmetic context
# coerces an empty string to 0), so an `-eq` comparison records a PASS for an
# unset rc. `==` is a string comparison and records a FAIL, which is the arm
# that should win when the operand is degenerate.
verdict() { # <rc> <name>
  CASES=$((CASES + 1))
  if [[ "$1" == "0" ]]; then pass "$2"; else fail "$2"; fi
}

# POSITIVE CONTROL (ADR-193). The accounting identity below can only see a
# verdict that goes NOWHERE — it cannot see one that goes to the WRONG arm.
# Measured: rewriting the wrapper to `CASES=$((CASES+1)); pass "$2"` left all
# assertions reporting PASS with `create_before_destroy` planted on the live
# apex, CASES still climbing to its exact floor and PASS+FAIL still equal to it.
# Driving both helpers once each, before any case runs, is what closes that:
# a mis-routing wrapper cannot move both counters.
# It drives `verdict` — the WRAPPER — not `pass`/`fail` directly. Driving the
# helpers proves only that they record; the mutation that matters rewrites the
# wrapper to send every verdict to the PASS arm, and a control that bypasses the
# wrapper cannot see it. Measured: with the control on the helpers, the routing
# mutation left the guard fully green with a real defect planted.
_p0=$PASS; _f0=$FAIL; _c0=$CASES
verdict 0 "instrument self-test: the PASS arm records"
verdict 1 "instrument self-test: the FAIL arm records (EXPECTED — subtracted below)"
if [[ "$PASS" -ne $((_p0 + 1)) || "$FAIL" -ne $((_f0 + 1)) || "$CASES" -ne $((_c0 + 2)) ]]; then
  printf '[FATAL] instrument self-test: verdict did not route both arms (PASS %d->%d, FAIL %d->%d, CASES %d->%d)\n' \
    "$_p0" "$PASS" "$_f0" "$FAIL" "$_c0" "$CASES" >&2
  exit 2
fi
PASS=$((PASS - 1)); FAIL=$((FAIL - 1)); CASES=$((CASES - 2))

mapfile -t TF_FILES < <(find "$APEX_GUARD_TF_DIR" -maxdepth 1 -name '*.tf' -type f | sort)
if [[ "${#TF_FILES[@]}" -eq 0 ]]; then
  printf '[FATAL] no .tf files under %s — every assertion below would be vacuous\n' "$APEX_GUARD_TF_DIR" >&2
  exit 2
fi
for required in "$APPLY_WF" "$VALIDATION_WF"; do
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

# THE WHOLE ROOT, NOT ONE FILE. Terraform evaluates every .tf in the directory,
# so a guard that reads only dns.tf answers a question about a file rather than
# about the configuration. Measured: relocating `pages_apex` into cf-pages.tf
# left all cases green while the root carried an apex A AND an apex CNAME.
# The sibling `ssl-full-mitigation.test.sh` scans `*.tf` for exactly this reason.
TF_STRIPPED="$(for f in "${TF_FILES[@]}"; do strip_comments "$f"; done)"

# Emit one row per `cloudflare_record` block: <label>\t<name>\t<type>\t<cbd>\t<literal>
# `literal` is 0 when `name` or `type` is a non-literal expression (a var, a
# local, an interpolation). Those rows are NOT silently dropped — a record whose
# addressing this guard cannot READ is a record it cannot VOUCH for, and a
# quantifier that skips what it cannot measure fails open exactly where a future
# DRY refactor would put it.
cloudflare_records() {
  awk '
    !inb && $0 ~ /^[[:space:]]*resource[[:space:]]+"cloudflare_record"[[:space:]]+"[^"]+"/ {
      match($0, /"cloudflare_record"[[:space:]]+"[^"]+"/)
      seg = substr($0, RSTART, RLENGTH)
      sub(/^"cloudflare_record"[[:space:]]+"/, "", seg); sub(/"$/, "", seg)
      rname = seg; inb = 1; depth = 0
      rec_name = ""; rec_type = ""; cbd = 0; lit = 1; meta = 0
    }
    inb {
      if ($0 ~ /^[[:space:]]*name[[:space:]]*=/ && rec_name == "") {
        v = $0; sub(/^[[:space:]]*name[[:space:]]*=[[:space:]]*/, "", v); gsub(/[[:space:]]+$/, "", v)
        if (v ~ /^".*"$/) { gsub(/^"|"$/, "", v); rec_name = tolower(v); sub(/\.$/, "", rec_name) }
        else { rec_name = "<expr>"; lit = 0 }
      }
      if ($0 ~ /^[[:space:]]*type[[:space:]]*=/ && rec_type == "") {
        v = $0; sub(/^[[:space:]]*type[[:space:]]*=[[:space:]]*/, "", v); gsub(/[[:space:]]+$/, "", v)
        if (v ~ /^".*"$/) { gsub(/^"|"$/, "", v); rec_type = toupper(v) }
        else { rec_type = "<expr>"; lit = 0 }
      }
      if ($0 ~ /create_before_destroy[[:space:]]*=/) {
        v = $0; sub(/^.*create_before_destroy[[:space:]]*=[[:space:]]*/, "", v); gsub(/[[:space:]]+$/, "", v)
        if (v == "true") { cbd = 1 } else if (v != "false") { cbd = 1; lit = 0 }
      }
      if ($0 ~ /^[[:space:]]*(count|for_each)[[:space:]]*=/) { meta = 1 }
      d = gsub(/\{/, "{"); depth += d
      d = gsub(/\}/, "}"); depth -= d
      if (depth <= 0) {
        inb = 0
        printf "%s\t%s\t%s\t%d\t%d\t%d\n", rname, rec_name, rec_type, cbd, lit, meta
      }
    }
  ' <<<"$TF_STRIPPED"
}

ALL_RECORDS="$(cloudflare_records)"

# Rows whose name resolves to the apex AND whose type is an address type.
# `soleur.ai`, `soleur.ai.` and `@` are all folded to the zone root upstream.
apex_address_rows() {
  while IFS=$'\t' read -r rname rec_name rec_type cbd lit meta; do
    [[ -z "${rname:-}" ]] && continue
    [[ "$rec_name" == "$APEX_ZONE" || "$rec_name" == "@" ]] || continue
    [[ "$rec_type" == "A" || "$rec_type" == "AAAA" || "$rec_type" == "CNAME" ]] || continue
    printf '%s\t%s\t%s\t%s\t%s\n' "$rname" "$rec_type" "$cbd" "$lit" "$meta"
  done <<<"$ALL_RECORDS"
}

# Rows addressing the www host, under ANY resource label. M4 previously read
# only the block LABELLED `www`, so a second www record under a different label
# was outside both it and the apex quantifier.
www_rows() {
  while IFS=$'\t' read -r rname rec_name rec_type cbd lit meta; do
    [[ -z "${rname:-}" ]] && continue
    [[ "$rec_name" == "www" || "$rec_name" == "www.$APEX_ZONE" ]] || continue
    printf '%s\t%s\n' "$rname" "$rec_type"
  done <<<"$ALL_RECORDS"
}

# One `moved { from = … to = … }` block, brace-depth scoped, as <from>\t<to>.
moved_pairs() {
  awk '
    !inb && $0 ~ /^[[:space:]]*moved[[:space:]]*\{/ { inb = 1; depth = 0; f = ""; t = "" }
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
  ' <<<"$TF_STRIPPED"
}

# First `key = value` in a block, anchored on ASSIGNMENT SYNTAX. One awk process,
# never `grep … | head -1`: head exits after the first line and grep dies of
# SIGPIPE, which `pipefail` then promotes into the pipeline's status. This file
# runs without `set -e`, so that would not abort the run — it would make the
# assignment's status non-zero at the exact moment the read SUCCEEDED, which is
# worse than an abort because it is silent.
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
    !inb && $0 ~ "^[[:space:]]*resource[[:space:]]+\"" t "\"[[:space:]]+\"" n "\"" { inb = 1; depth = 0 }
    inb {
      print
      d = gsub(/\{/, "{"); depth += d
      d = gsub(/\}/, "}"); depth -= d
      if (depth <= 0) { inb = 0 }
    }
  ' <<<"$TF_STRIPPED"
}

# The merge-apply job's plan step, extracted by its own `- name:` heading and
# bounded by the next step at the same indent. The `-target=` assertions run
# against THIS, not against the whole workflow: the file carries ~15 other jobs
# with their own target lists, so a file-global grep is satisfied by a
# `workflow_dispatch`-only job, by an `if: false` decoy, and by runbook prose
# inside a block scalar — all three measured GREEN before this was scoped.
apply_plan_step() {
  awk '
    /^      - name: Terraform plan \(allow-list, non-SSH resources only\)/ { inb = 1; print; next }
    inb && /^      - name: / { inb = 0 }
    inb { print }
  ' "$APPLY_WF" | sed 's/[[:space:]]*\\$//'
}

APPLY_PLAN_STEP="$(apply_plan_step)"

# ---------------------------------------------------------------------------------------
# STAGE RESOLUTION
# ---------------------------------------------------------------------------------------
# Resolved from whether `pages_apex` is DECLARED anywhere in the root — not from
# the apex record's own type, so a mutation that repoints the apex by rewriting
# its type cannot re-derive the stage to match itself.
PAGES_APEX_BLOCK="$(hcl_block cloudflare_record pages_apex)"
if [[ -n "$PAGES_APEX_BLOCK" ]]; then
  STAGE="post-flip"
else
  STAGE="pre-flip"
fi

APEX_ROWS="$(apex_address_rows)"
APEX_COUNT=0
[[ -n "$APEX_ROWS" ]] && APEX_COUNT="$(printf '%s\n' "$APEX_ROWS" | grep -c . || true)"

WWW_ROWS="$(www_rows)"
WWW_COUNT=0
[[ -n "$WWW_ROWS" ]] && WWW_COUNT="$(printf '%s\n' "$WWW_ROWS" | grep -c . || true)"

printf 'apex-single-node-replace: stage=%s, %d .tf file(s), apex address records=%d, www records=%d\n\n' \
  "$STAGE" "${#TF_FILES[@]}" "$APEX_COUNT" "$WWW_COUNT"

# ---------------------------------------------------------------------------------------
# STAGE-INDEPENDENT CASES
# ---------------------------------------------------------------------------------------

# The second-member row. A guard that stops at the first matching apex block, or
# that checks only the addresses it expects BY NAME, passes a second apex record
# added alongside a correct one while the zone again carries A-and-CNAME at one
# name. Quantified across every .tf in the root.
rc=1; [[ "$APEX_COUNT" -eq 1 ]] && rc=0
verdict "$rc" "exactly one apex address record across the root (found ${APEX_COUNT}: $(printf '%s' "${APEX_ROWS//$'\n'/, }" | tr '\t' ':'))"

# The core row. `create_before_destroy` on the apex silently INVERTS the one
# ordering Cloudflare rejects: the CNAME create would be dispatched before the A
# delete. It reads as a safety improvement and nothing else in CI notices.
cbd_offenders=""
while IFS=$'\t' read -r rname rtype rcbd _ _; do
  [[ -z "${rname:-}" ]] && continue
  [[ "$rcbd" == "1" ]] && cbd_offenders="${cbd_offenders}${rname}(${rtype}) "
done <<<"$APEX_ROWS"
rc=1; [[ -z "$cbd_offenders" ]] && rc=0
verdict "$rc" "no apex address record declares create_before_destroy (offenders: ${cbd_offenders:-none})"

# FAIL CLOSED ON WHAT CANNOT BE MEASURED. A record whose `name` or `type` is a
# variable, local or interpolation drops out of every filter above — so the two
# quantifiers would report a clean count while an apex record sat outside them.
# "Could not measure" must not read as "not an apex record"; this is the arm
# that makes the structural claim in the header true rather than aspirational.
nonliteral=""
while IFS=$'\t' read -r rname rec_name rec_type cbd lit meta; do
  [[ -z "${rname:-}" ]] && continue
  [[ "$lit" == "0" ]] && nonliteral="${nonliteral}${rname} "
done <<<"$ALL_RECORDS"
rc=1; [[ -z "$nonliteral" ]] && rc=0
verdict "$rc" "every cloudflare_record addresses itself with literal name/type (unreadable: ${nonliteral:-none})"

# Camp B, quantified. `type` is ForceNew at provider 4.52.7 (measured), so an
# `A` at www becomes a SECOND replacement racing the first and moves PR4b's
# destroy_count to 2. Reading only the block LABELLED `www` left a second www
# record under a different label outside both this and the apex quantifier.
rc=1; [[ "$WWW_COUNT" -eq 1 ]] && rc=0
verdict "$rc" "exactly one www record across the root (found ${WWW_COUNT}: $(printf '%s' "${WWW_ROWS//$'\n'/, }" | tr '\t' ':'))"

www_bad=""
while IFS=$'\t' read -r rname rtype; do
  [[ -z "${rname:-}" ]] && continue
  [[ "$rtype" == "CNAME" ]] || www_bad="${www_bad}${rname}(${rtype}) "
done <<<"$WWW_ROWS"
rc=1; [[ -z "$www_bad" && "$WWW_COUNT" -ge 1 ]] && rc=0
verdict "$rc" "every www record is a CNAME so none can become a second ForceNew replacement (offenders: ${www_bad:-none})"

# A `moved` block whose endpoints are not BOTH in the apply allow-list does not
# mis-plan, it HARD-ERRORS: `Error: Moved resource instances excluded by
# targeting` (measured). Scoped to the merge-apply plan STEP, because the file
# carries ~15 other jobs with their own `-target=` lists.
#
# The line anchor is load-bearing independently:
# `-target=cloudflare_record.github_pages` is a strict PREFIX of
# `-target=cloudflare_record.github_pages_challenge`, so an unanchored grep for
# the former is satisfied by the latter while the endpoint is gone.
for endpoint in cloudflare_record.github_pages cloudflare_record.pages_apex; do
  rc=1
  grep -qE "^[[:space:]]*-target=${endpoint//./\\.}[[:space:]]*$" <<<"$APPLY_PLAN_STEP" && rc=0
  verdict "$rc" "the merge-apply plan step targets ${endpoint} (step-scoped; a dispatch-only job does not satisfy it)"
done

# The own-dispatch row. A guard nobody runs is a guard that passes by never
# running. Anchored on the `run:` INVOCATION over a comment-stripped view — a
# bare substring search is satisfied by a comment naming the file, which is
# precisely the failure this file's own strip_comments header describes, and it
# was the one input never being stripped. AC65 asked for the invocation anchor.
rc=1
grep -qE '^[[:space:]]*run:.*apex-single-node-replace\.test\.sh([[:space:]]|$)' \
  <(strip_comments "$VALIDATION_WF") && rc=0
verdict "$rc" "this guard is dispatched by a run: step in infra-validation.yml (a comment naming it does not satisfy this)"

# ---------------------------------------------------------------------------------------
# STAGE-DEPENDENT CASES — three in each stage, so the floor stays an EXACT cardinality
# ---------------------------------------------------------------------------------------
if [[ "$STAGE" == "pre-flip" ]]; then
  # PR4a's shape: `github_pages` survives with exactly one `for_each` key, and
  # that key is the literal PR4b's `moved.from` must name. Asserting it HERE is
  # what makes the post-flip mismatch detectable one merge later — this is the
  # only place the survivor is still declared.
  GH_BLOCK="$(hcl_block cloudflare_record github_pages)"
  keys="$(grep -oE '"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"' <<<"$GH_BLOCK" | tr -d '"' || true)"
  key_count=0
  [[ -n "$keys" ]] && key_count="$(printf '%s\n' "$keys" | grep -c . || true)"
  rc=1; [[ "$key_count" -eq 1 && "$keys" == "$SURVIVING_APEX_KEY" ]] && rc=0
  verdict "$rc" "pre-flip: github_pages carries exactly the one for_each key ${SURVIVING_APEX_KEY} (found ${key_count}: ${keys//$'\n'/, })"

  GH_TYPE="$(unquote "$(attr type "$GH_BLOCK")")"
  rc=1; [[ "$GH_TYPE" == "A" ]] && rc=0
  verdict "$rc" "pre-flip: the apex origin is still the github_pages A record (found: ${GH_TYPE:-<absent>})"

  # Scoped to moves TARGETING the apex, not to `moved` blocks in general:
  # placement-group.tf legitimately carries four of them for the hcloud fleet,
  # and reading the whole root (which is correct) makes an unscoped emptiness
  # check false by construction.
  premature=""
  while IFS=$'\t' read -r mfrom mto; do
    [[ -z "${mto:-}" ]] && continue
    [[ "$mto" == "cloudflare_record.pages_apex" ]] && premature="${premature}${mfrom} "
  done <<<"$(moved_pairs)"
  rc=1; [[ -z "$premature" ]] && rc=0
  verdict "$rc" "pre-flip: no moved block targets the apex yet (the flip is PR4b's merge, not this one; found: ${premature:-none})"
else
  # Deleting the `moved` block leaves the old and new declarations as two
  # unrelated addresses: the exact plan measured as `1 to add … 1 to destroy`
  # across two addresses, dispatched concurrently.
  MOVED="$(moved_pairs)"
  moved_to_apex=""
  while IFS=$'\t' read -r mfrom mto; do
    [[ -z "${mto:-}" ]] && continue
    [[ "$mto" == "cloudflare_record.pages_apex" ]] && moved_to_apex="$mfrom"
  done <<<"$MOVED"
  rc=1; [[ -n "$moved_to_apex" ]] && rc=0
  verdict "$rc" "post-flip: a moved block re-addresses the survivor to cloudflare_record.pages_apex"

  # THE silent-failure row, and the highest-value case in this file. Terraform
  # does not error on a moved whose source is absent from state; it no-ops, so
  # pages_apex plans as a bare create while the real survivor plans as a
  # separate delete — two addresses, concurrent, with no signal anywhere.
  want="cloudflare_record.github_pages[\"${SURVIVING_APEX_KEY}\"]"
  rc=1; [[ "$moved_to_apex" == "$want" ]] && rc=0
  verdict "$rc" "post-flip: moved.from is byte-identical to the key PR4a left — want ${want}, got ${moved_to_apex:-<absent>}"

  # A `count`/`for_each` on pages_apex makes it many instances at one address,
  # which is not the single-node replace core serialises. The apex quantifier
  # counts BLOCKS, so this is the instance-cardinality arm it cannot see.
  pa_meta=""
  while IFS=$'\t' read -r rname _ _ _ rmeta; do
    [[ "$rname" == "pages_apex" && "$rmeta" == "1" ]] && pa_meta="yes"
  done <<<"$APEX_ROWS"
  PAGES_APEX_TYPE="$(unquote "$(attr type "$PAGES_APEX_BLOCK")")"
  rc=1; [[ "$PAGES_APEX_TYPE" == "CNAME" && -z "$pa_meta" ]] && rc=0
  verdict "$rc" "post-flip: pages_apex is a single-instance CNAME (type=${PAGES_APEX_TYPE:-<absent>}, count/for_each=${pa_meta:-no})"
fi

# ---------------------------------------------------------------------------------------
# ANTI-VACUITY FLOOR AND ACCOUNTING (AP-023 / ADR-193)
# ---------------------------------------------------------------------------------------
# Both report with `printf >&2` + `exit 1`, NEVER through this suite's own `fail`.
# A floor routed through `fail` is disarmed by the same one-line edit that
# disarms every assertion it exists to witness.
printf '\n'
EXPECTED_CASES=11
if [[ "$CASES" -lt "$EXPECTED_CASES" ]]; then
  printf '[VACUITY] only %d case(s) ran, expected exactly %d — a case was deleted or skipped\n' "$CASES" "$EXPECTED_CASES" >&2
  exit 1
fi
if [[ "$CASES" -gt "$EXPECTED_CASES" ]]; then
  printf '[VACUITY] %d case(s) ran, expected exactly %d — bump EXPECTED_CASES deliberately\n' "$CASES" "$EXPECTED_CASES" >&2
  exit 1
fi
# `-ne`, not `-lt`. The one-sided form misses the OVER-count direction, which is
# the shape of "fixing" a red row by adding a stray `pass` outside the wrapper.
# The sibling ssl-full-mitigation.test.sh uses `-ne` for the same reason.
if [[ "$((PASS + FAIL))" -ne "$CASES" ]]; then
  printf '[VACUITY] accounting identity broken: PASS+FAIL=%d != CASES=%d\n' "$((PASS + FAIL))" "$CASES" >&2
  exit 1
fi

printf 'apex-single-node-replace: %d passed, %d failed (%d cases, stage=%s)\n' "$PASS" "$FAIL" "$CASES" "$STAGE"
[[ "$FAIL" -eq 0 ]] || exit 1
