#!/usr/bin/env bash
# supabase-advisor-scan.sh — assert that no table in a Supabase project's
# `public` schema is missing row-level security. Scans ONE project ref; the
# caller loops it over every ref and aggregates (so one bad ref cannot retire
# coverage for the others).
#
# CONTRACT
#   In  (env) : REF, PROJECT_NAME, SUPABASE_ACCESS_TOKEN
#   Out (stdout): parseable key=value lines + a non-asserting lint census
#   Exit      : 0 = clean (or benign advisor lag), 1 = failure, with fail_mode=
#
# WHY THIS IS A SCRIPT AND NOT A WORKFLOW `run:` BLOCK
# ====================================================
# It needs a callable seam. The single most important property here is that the
# gate CANNOT SILENTLY PASS, and that property is only worth as much as the test
# that proves it. Nothing can drive a `run:` block with a fixture body, so the
# same logic inline in YAML would be asserted by prose instead of by a test.
# tests/scripts/test-supabase-advisor-scan.sh drives this file through every
# parse case and decision quadrant by stubbing `curl` on PATH.
#
# THE BUG THIS FILE EXISTS NOT TO REPEAT
# ======================================
# The pre-existing idiom (apply-inngest-rls.yml) parses the advisor with
#   [.lints[]? | select(.name=="rls_disabled_in_public")] | length
# The `?` swallows a missing key. Verified live 2026-07-16: an expired PAT
# returns HTTP 401 with {"message":"JWT could not be decoded"}, and that idiom
# scores it **0** — indistinguishable from a clean scan. A `== 0` assertion on
# that parse is permanently green on a dead token.
#
# That `?` is CORRECT where it lives: there it is corroboration that must never
# break an apply. It is fatal here, where it is an assertion that must never
# pass on garbage. Same token, opposite correctness, depending on whether the
# caller ASSERTS. Never copy it mechanically.
#
# Hence the ladder below: every rung must PROVE the next rung's input is real
# before parsing it. A zero is only ever reported after we have established
# there was something to count.
#
# WHY THE API HOST IS PINNED WITH NO ENV OVERRIDE
# ===============================================
# This process holds a Supabase cloud-admin PAT. An overridable host is a
# PAT-exfil-via-redirect seam. Testability comes from stubbing the curl BINARY,
# which costs production nothing.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/lib/strip-log-injection.sh
. "${SCRIPT_DIR}/lib/strip-log-injection.sh"
# shellcheck source=scripts/lib/scrub-supabase-pat.sh
. "${SCRIPT_DIR}/lib/scrub-supabase-pat.sh"

# Both libs are stdin filters. Everything echoed from an API body goes through
# this — a crafted response must not be able to forge a ::error:: runner
# directive or smuggle the PAT into a log.
sanitize() { printf '%s' "${1:-}" | strip_log_injection | scrub_pat; }

API="https://api.supabase.com" # pinned — NO env override (see header)

fail_mode=""
fail_detail=""
# First failure wins: it is the root cause. Later rungs are downstream noise.
record_failure() {
  if [[ -z "$fail_mode" ]]; then
    fail_mode="$1"
    fail_detail="$2"
  fi
}

# A PROVEN VIOLATION OUTRANKS ANY INFRASTRUCTURE FAULT and overrides first-wins.
# The two are not comparable: an infra fault means "the gate could not look", a
# violation means "the gate looked and the data is exposed". If the advisor is
# unreachable AND the catalog proves a public table has no RLS, the operator
# must be paged for the exposure (class A), not handed a p2 "scan failed"
# ticket. The workflow derives the issue class from this fail_mode, so
# first-wins here would silently downgrade a real exposure to a token-renewal
# ticket.
record_violation() {
  fail_mode="$1"
  fail_detail="$2"
}

ok() { [[ -z "$fail_mode" ]]; }

# Rung 1's outcome, tracked separately from `ok`. Identity is a genuine
# precondition for every later rung (without it we do not know WHICH project we
# are asserting against). The ADVISOR's health is NOT such a precondition — see
# the rung 3 header.
identity_ok=0

: "${REF:=}" "${PROJECT_NAME:=}" "${SUPABASE_ACCESS_TOKEN:=}"
[[ -z "$REF" ]] && record_failure "config_error" "REF not set."
[[ -z "$PROJECT_NAME" ]] && record_failure "config_error" "PROJECT_NAME not set."
[[ -z "$SUPABASE_ACCESS_TOKEN" ]] && record_failure "config_error" "SUPABASE_ACCESS_TOKEN not set."

# The PAT is piped to curl on STDIN via `--header @-`, never interpolated into
# an argument. `--header "Authorization: Bearer $TOK"` would look equivalent, but
# the shell expands it BEFORE exec, so the cloud-admin token lands in curl's argv
# and is world-readable at /proc/<pid>/cmdline for the life of the request.
# Mirrors the same idiom (and the same reasoning) in scripts/audit-ruleset-bypass.sh.
#
# The standing repo rebuttal — that `--header @-` "would fork the shared HTTP
# plumbing for no real gain" (apply-inngest-rls-dev.yml) — is scoped to workflow
# `run:` steps that have no shared plumbing to reuse. This is a standalone
# script, the same context as audit-ruleset-bypass.sh, so it does not apply here.
#
# stderr is dropped so a curl diagnostic cannot echo the URL back.
api_get() {
  printf 'Authorization: Bearer %s' "$SUPABASE_ACCESS_TOKEN" |
    curl --silent --show-error --max-time 30 \
      --header @- \
      --write-out $'\n%{http_code}' --url "$1" 2>/dev/null
}

api_query() {
  printf 'Authorization: Bearer %s' "$SUPABASE_ACCESS_TOKEN" |
    curl --silent --show-error --max-time 30 \
      --request POST \
      --header @- \
      --header "Content-Type: application/json" \
      --data "$(jq -nc --arg q "$1" '{query:$q}')" \
      --write-out $'\n%{http_code}' --url "$API/v1/projects/${REF}/database/query" 2>/dev/null
}

http_code() { printf '%s' "$1" | tail -1; }
http_body() { printf '%s' "$1" | sed '$d'; }

# Postgres single-quote escaping for a value interpolated into a SQL literal.
# The advisor's metadata is upstream data; it does not get to write SQL.
sql_lit() { printf "'%s'" "${1//\'/\'\'}"; }

# --- Rung 1: project-identity preflight -------------------------------------
# Binds ref -> project via Supabase's OWN identity record rather than inferring
# identity from schema contents. Asserts HTTP separately from the name so an
# unreachable API is reported as unreachable, not silently as "wrong project".
if ok; then
  resp="$(api_get "$API/v1/projects/${REF}")"
  code="$(http_code "$resp")"
  body="$(http_body "$resp")"
  if [[ "$code" != "200" ]]; then
    record_failure "identity_unreachable" \
      "project-identity preflight HTTP ${code} for ref ${REF}: $(sanitize "$(printf '%s' "$body" | head -c 200)")"
  else
    actual_name="$(printf '%s' "$body" | jq -r '.name // empty' 2>/dev/null)"
    if [[ "$actual_name" != "$PROJECT_NAME" ]]; then
      record_failure "identity_mismatch" \
        "ref ${REF} resolves to project '$(sanitize "$actual_name")', expected '${PROJECT_NAME}'."
    else
      identity_ok=1
      echo "identity_preflight=pass"
    fi
  fi
fi

# --- Rung 2: the advisor (SUBORDINATE — may only ever ADD a failure) --------
advisor_count=""
advisor_body=""
if [[ "$identity_ok" -eq 1 ]]; then
  resp="$(api_get "$API/v1/projects/${REF}/advisors/security")"
  code="$(http_code "$resp")"
  advisor_body="$(http_body "$resp")"

  # 2a. Transport. A non-200 is a FAILURE, never a zero. This is the 401 case.
  if [[ "$code" != "200" ]]; then
    record_failure "advisor_unreachable" \
      "advisor HTTP ${code}: $(sanitize "$(printf '%s' "$advisor_body" | head -c 200)")"
  # 2b. Structure. Proves there is an array to count BEFORE counting it.
  #     Without this rung, {"message":"..."} counts as 0.
  elif ! printf '%s' "$advisor_body" | jq -e 'has("lints") and (.lints|type=="array")' >/dev/null 2>&1; then
    record_failure "advisor_malformed" \
      "advisor body has no .lints array (API contract drift?): $(sanitize "$(printf '%s' "$advisor_body" | head -c 200)")"
  else
    # 2c. ONLY NOW count — and with .lints[] WITHOUT the `?`. The `?` is
    #     unnecessary once (2b) proved the array exists, and it is precisely
    #     what makes the idiom this file replaces fail-open.
    advisor_count="$(printf '%s' "$advisor_body" |
      jq '[.lints[] | select(.name=="rls_disabled_in_public")] | length' 2>/dev/null)"
    if ! [[ "$advisor_count" =~ ^[0-9]+$ ]]; then
      record_failure "advisor_malformed" "advisor count did not parse to an integer."
    else
      echo "advisor_rls_disabled_in_public=${advisor_count}"
    fi
  fi
fi

# --- Rung 3: the catalog (AUTHORITATIVE, UNCONDITIONAL) ---------------------
# Deliberately NOT nested inside an advisor-non-zero conditional. Staleness cuts
# BOTH ways: the advisor can be served stale right after a DDL change, so a
# cached clean advisor over a live violation is a real, reachable false-green. A
# design that consults the catalog only when the advisor fires misses it —
# rebuilding the fail-open one tier up, via staleness instead of parsing.
#
# This is the coverage-bearing tier (ADR-112's two-tier pattern, in the correct
# orientation): the advisor is advisory and may only ADD a failure; it can never
# suppress or weaken this assertion.
#
# UNCONDITIONAL MEANS UNCONDITIONAL — including "the advisor broke".
# This rung is gated on `identity_ok`, NOT on `ok`. Gating on `ok` would skip the
# catalog whenever the ADVISOR failed, which quietly makes the coverage-bearing
# tier depend on the health of the advisory one — ADR-112's "NEVER
# coverage-bearing" violated through the back door. Concretely: if Supabase
# renames `.lints`, rung 2b records advisor_malformed, and the catalog check —
# which needs nothing from the advisor and shares only the PAT — would never run.
# #3366's actual coverage would retire behind a p2 "scan failed" ticket while a
# live RLS violation went unpaged. Identity IS a real precondition (without it we
# do not know which project we are asserting against); the advisor is not.
rls_off=""
rls_off_tables=""
if [[ "$identity_ok" -eq 1 ]]; then
  # Select the offending table IDENTITIES, not a bare count.
  #
  # A count is not actionable. `catalog_rls_off=3` tells the operator a p1
  # data-exposure page is real but not WHICH table to fix, and this is the one
  # tier that can answer: in the exact scenario this rung exists for (a stale
  # advisor over a live violation) the advisor reports zero findings, so there
  # is no lint metadata to name the table either. Emitting only a count would
  # send the operator to the Supabase dashboard to hand-run this same query —
  # the dashboard-eyeball round trip the no-SSH/no-dashboard rule exists to
  # prevent. The count is derived from the row array below.
  resp="$(api_query "select n.nspname||'.'||c.relname as rls_off_table from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind in ('r','p') and c.relrowsecurity=false order by 1")"
  code="$(http_code "$resp")"
  body="$(http_body "$resp")"
  # NOTE: this endpoint answers 201, not 200 — verified live 2026-07-16.
  # Asserting == 200 here (as an earlier draft of the plan specified) would have
  # false-failed the gate on every single run.
  if [[ "$code" != "200" && "$code" != "201" ]]; then
    record_failure "catalog_unreachable" \
      "catalog query HTTP ${code}: $(sanitize "$(printf '%s' "$body" | head -c 200)")"
  # An EMPTY array is the clean case, so this cannot assert length>0. It asserts
  # the response is a row array whose every element carries a string identity —
  # `all` over an empty array is true, which is exactly right: zero offending
  # tables is a proven clean, while {"message":"JWT could not be decoded"} is
  # not an array and fails loud.
  elif ! printf '%s' "$body" |
      jq -e 'type=="array" and all(.[]; has("rls_off_table") and (.rls_off_table|type=="string"))' >/dev/null 2>&1; then
    record_failure "catalog_malformed" \
      "catalog query did not return a row array of table identities: $(sanitize "$(printf '%s' "$body" | head -c 200)")"
  else
    rls_off="$(printf '%s' "$body" | jq 'length' 2>/dev/null)"
    rls_off_tables="$(printf '%s' "$body" | jq -r '[.[].rls_off_table] | join(", ")' 2>/dev/null)"
    echo "catalog_rls_off=${rls_off}"
    [[ -n "$rls_off_tables" ]] && echo "catalog_rls_off_tables=$(sanitize "$rls_off_tables")"
  fi
fi

# --- Rung 4: the decision ---------------------------------------------------
# Also gated on identity_ok, not ok: a proven violation must be reported even if
# the advisor failed. record_violation OVERRIDES the first-wins fail_mode so the
# operator is paged for the exposure (class A) rather than handed the advisor's
# p2 "scan failed" ticket.
if [[ "$identity_ok" -eq 1 ]]; then
  if [[ -n "$rls_off" && "$rls_off" -gt 0 ]]; then
    # The authoritative assertion, independent of what the advisor said — and
    # independent of whether the advisor even worked.
    record_violation "violation_confirmed" \
      "${rls_off} table(s) in the public schema of ${PROJECT_NAME} have RLS disabled: ${rls_off_tables}"
  elif [[ -n "$rls_off" && -n "$advisor_count" && "$advisor_count" -gt 0 ]]; then
    # Advisor fires, catalog clean. The ONLY benign explanation is the advisor's
    # documented lag (<=1h self-heal window). Verify it OBJECT-SCOPED, never
    # count-vs-count: our catalog predicate hardcodes relkind in ('r','p') and
    # nspname='public', so a genuine finding on an object OUTSIDE that predicate
    # would meet a clean-looking rls_off=0 and get downgraded to a WARN-pass.
    # Two numbers agreeing at 0 does not prove they measured the same tables.
    #
    # So: check each advisor-NAMED table directly, WITHOUT the relkind filter.
    # Anything other than "this exact table is now RLS-on" fails. That also
    # stops a PERMANENT disagreement from WARN-passing forever as "lag".
    # Extract the advisor-named tables, ASSERTING THE EXTRACTION ITSELF.
    #
    # This rung is subject to the same rule as every other one above: a zero is
    # only ever reported after we have established there was something to count.
    # An earlier version of this block piped jq straight into `while read` with
    # `2>/dev/null` and a `// "?"` hedge. That reproduced this file's headline
    # bug one tier up: if jq errored mid-stream (e.g. .metadata.name is an
    # object after contract drift), the error was swallowed, the loop body never
    # ran, `indeterminate` stayed empty, and the script reported
    # "every named table is now RLS-enabled" and exited 0 — having checked
    # NOTHING, while the advisor was actively reporting a finding.
    #
    # `strings` drops any metadata value that is not a string, and
    # `select(length == 2)` drops any lint missing either half — so a shape the
    # parse cannot trust produces FEWER rows than the advisor counted, and the
    # cardinality check below turns that into a loud failure instead of a
    # silent clean. The Supabase lint object's shape was pinned live from a
    # SIBLING lint (rls_enabled_no_policy) because no live
    # rls_disabled_in_public sample exists on any of the three projects, so
    # "the field names are what I think they are" is an assumption this rung
    # must verify rather than trust.
    lint_rows="$(printf '%s' "$advisor_body" |
      jq -r '.lints[] | select(.name=="rls_disabled_in_public")
             | [(.metadata.schema | strings), (.metadata.name | strings)]
             | select(length == 2) | @tsv' 2>/dev/null)"
    jq_rc=$?
    row_count=0
    [[ -n "$lint_rows" ]] && row_count="$(printf '%s\n' "$lint_rows" | grep -c . || true)"

    if [[ "$jq_rc" -ne 0 ]]; then
      # NOT class A: this is the gate's own instrument failing, not a proven
      # data exposure. Paging p1/type/security here would cry wolf nightly.
      record_failure "advisor_metadata_malformed" \
        "could not parse table identity out of the advisor lint metadata (jq exit ${jq_rc}) — the API contract may have drifted."
    elif [[ "$row_count" -ne "$advisor_count" ]]; then
      record_failure "advisor_metadata_malformed" \
        "advisor reported ${advisor_count} rls_disabled_in_public finding(s) but only ${row_count} carried a usable schema+table identity — REFUSING to treat the unparseable remainder as benign lag."
    else
    indeterminate=""
    checked=0
    while IFS=$'\t' read -r lschema ltable; do
      [[ -z "$lschema$ltable" ]] && continue
      qresp="$(api_query "select c.relrowsecurity from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname=$(sql_lit "$lschema") and c.relname=$(sql_lit "$ltable")")"
      qcode="$(http_code "$qresp")"
      qbody="$(http_body "$qresp")"
      if [[ "$qcode" != "200" && "$qcode" != "201" ]]; then
        indeterminate="${indeterminate} ${lschema}.${ltable}(lookup-http-${qcode})"
        continue
      fi
      # No row => the advisor named a table the catalog cannot find. That is an
      # unexplained disagreement, which is NOT benign.
      if ! printf '%s' "$qbody" | jq -e 'type=="array" and length>0' >/dev/null 2>&1; then
        indeterminate="${indeterminate} ${lschema}.${ltable}(no-such-relation)"
        continue
      fi
      if [[ "$(printf '%s' "$qbody" | jq -r '.[0].relrowsecurity' 2>/dev/null)" != "true" ]]; then
        indeterminate="${indeterminate} ${lschema}.${ltable}(rls-still-off)"
      fi
      checked=$((checked + 1))
    done <<< "$lint_rows"

    if [[ -n "$indeterminate" ]]; then
      record_violation "confirm_indeterminate" \
        "advisor flagged ${advisor_count} table(s) but the catalog disagrees for:$(sanitize "$indeterminate"). Refusing to treat an unexplained disagreement as advisor lag."
    elif [[ "$checked" -ne "$advisor_count" ]]; then
      # Belt-and-braces: the loop must actually have run once per advisor
      # finding. Without this, any future edit that makes the loop body skip
      # (a `continue`, a read failure) silently restores the fail-open.
      record_failure "advisor_metadata_malformed" \
        "expected to verify ${advisor_count} advisor-named table(s) but only checked ${checked} — refusing to report clean on an unverified finding."
    else
      # Benign: every advisor-named table is demonstrably RLS-on now.
      echo "warn=stale_advisor"
      echo "::warning::Supabase advisor reported ${advisor_count} rls_disabled_in_public finding(s) on ${PROJECT_NAME}, but every named table is now RLS-enabled — treating as advisor lag (<=1h self-heal window)."
    fi
    fi
  fi
fi

# --- Non-asserting lint census ----------------------------------------------
# Observability only. These lints are deliberately NOT asserted: the definer and
# no-policy classes are non-zero by design and are owned by ADR-112's
# authoritative guard, which explicitly forbids citing a cheaper tier to weaken
# it. Reporting them is useful; asserting them here would be a regression.
#
# Gated on advisor_count being set — i.e. the structural rung above already
# PROVED there is a lints array. That is what lets this use the strict `.lints[]`
# with no `?`. Guarding on a merely non-empty body instead would let this parse a
# 401 error body, and reintroducing that `?` anywhere in this file is exactly the
# mechanical copy the header warns against, so the shape guard forbids it
# outright rather than trusting "it's only the census".
if [[ -n "$advisor_count" ]]; then
  census="$(printf '%s' "$advisor_body" |
    jq -r '[.lints[] | .name] | group_by(.) | map("\(.[0])=\(length)") | join(" ")' 2>/dev/null)"
  [[ -n "$census" && "$census" != "null" ]] && echo "census=$(sanitize "$census")"
fi

# --- Emit ------------------------------------------------------------------
# THE VERDICT BRANCHES ON THE RAW fail_mode, NEVER THE SANITIZED COPY.
# Sanitization exists for log safety and must not sit on the control-flow path:
# branching on `fail_mode_safe` means ANY degradation of sanitize() — a lib that
# failed to source, a tr/sed error, an empty return — silently converts EVERY
# failure into `scan_result=clean` exit 0. That is a whole-gate fail-open
# reachable without touching a single assertion, and it is exactly the class
# this file exists to eliminate. The sanitized copies are for OUTPUT only.
fail_mode_safe="$(sanitize "$fail_mode")"
fail_detail_safe="$(sanitize "$fail_detail")"
echo "fail_mode=${fail_mode_safe}"
echo "fail_detail=${fail_detail_safe}"

if [[ -n "$fail_mode" ]]; then
  echo "::error::supabase-advisor-scan FAILED for ${PROJECT_NAME} (${REF}): ${fail_mode_safe} — ${fail_detail_safe}"
  exit 1
fi
echo "scan_result=clean"
exit 0
