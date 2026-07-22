#!/usr/bin/env bash
# =============================================================================
# preapply-entrypoint-gate.sh — fail-closed PRE-APPLY GATE + retrospective AUDIT
# for whole-list Cloudflare ruleset phase entrypoints. Closes #6767.
#
# THE HAZARD (#6746). A `kind = "zone"` (or `kind = "root"`) cloudflare_ruleset
# OWNS its phase entrypoint as a WHOLE-LIST replacement. `terraform plan` reports
# "1 to add" for such a resource purely because it is absent from *state* — and
# that line is correct — but `plan` never calls the Cloudflare API, so it cannot
# see that the LIVE entrypoint is already populated with dashboard-created rules.
# A clean plan is therefore fully compatible with a DESTRUCTIVE first apply: the
# create whole-list-PUTs the config's rules over the live list, silently deleting
# rules a human made in the CF dashboard (the "Flexible SSL for web platform"
# outage on app.soleur.ai).
#
# WHY THE DESTROY-GUARD CANNOT BE THIS GATE. destroy-guard-filter-web-platform.jq
# computes before.rules − after.rules; on a create, `before` is null → 0 − N = −N
# → filtered out by `select(. > 0)`, and resource_deletes is 0 too, so no
# [ack-destroy] fires. A plan-derived guard INHERITS plan's blind spot. This gate
# asserts on plan SHAPE (a whole-list resource planned as a pure create from
# absent state) and then QUERIES THE LIVE CLOUDFLARE API to decide. See ADR-133.
#
# INCLUSION PRINCIPLE (what the gate guards — ADR-133 class table). The hazard is
# precisely "a create silently ADOPTS and WHOLE-REPLACES a server-side singleton
# addressed by a natural/composite key that can pre-exist outside Terraform".
# Adjudicated over every cloudflare_* class in this root, exactly ONE lands IN:
# cloudflare_ruleset (zone + account phase entrypoints). Every other class is a
# TF-generated-ID object where a same-named dashboard object is a *different*
# object (OUT). The parity test (test-preapply-entrypoint-gate.sh) makes this a
# TESTED coupling, cross-referenced to the destroy-guard class table.
#
# DEFAULT-DENY. The gate PASSES only on a proven-empty entrypoint (a 200 with an
# empty rule list, or a 404 = phase-exists-no-ruleset). EVERY other outcome —
# non-200 control probe, empty token, unparseable plan JSON, unclassified kind,
# a null URL-building field, and every non-200/404 HTTP code (000/400/401/403/
# 429/5xx/non-numeric) — routes to ONE fail-closed catch-all. Fail-open is the
# cardinal risk; every ambiguity exits non-zero.
#
# MODES:
#   --gate <plan.json>   Runs in the apply job. Reads a `terraform show -json`
#                        plan document; fail-closes an apply that would clobber.
#   --audit [--live]     Retrospective drift audit. Static (default) enumerates
#                        declared rulesets from *.tf and prints a parity table;
#                        --live (CI, needs token) additionally GETs each live
#                        entrypoint and diffs against state.
#
# TESTABILITY SEAM. The HTTP fetch is injected via ONE indirection,
# PREAPPLY_ENTRYPOINT_FETCH (a command or function name). The default is the
# real curl (_default_curl). The test overrides it with a stub so control flow
# is asserted with NO live API in the assertion path. The fetch contract is:
#   called with a Cloudflare API path relative to /client/v4/ ; prints the HTTP
#   status code on line 1 and the response body on lines 2+.
#
# CAP-COUPLING CONVENTION (mirrors the destroy-guard trio): dedicated script +
# dedicated test-preapply-entrypoint-gate.sh + CODEOWNERS rows + a parity test.
# =============================================================================
set -euo pipefail

# --- Constants ---------------------------------------------------------------
# The Cloudflare rulesets API base. The fetch seam is handed a path relative to
# this so the stub and the real curl agree on one contract.
readonly CF_API_BASE="https://api.cloudflare.com/client/v4"
# Known-populated phase used for the control probe (ADR-130 control-probe
# pattern applied to the gate itself): the seo_page_redirects entrypoint. A 200
# here proves token scope + URL scheme + network BEFORE a target 404 is trusted
# to mean "empty phase" rather than "mis-constructed URL / bad token".
readonly CONTROL_PHASE="http_request_dynamic_redirect"
# curl bound (seconds). A Cloudflare hang converts to fail-closed rather than
# holding the SOLE apply concurrency serializer for the whole job budget.
readonly CF_MAX_TIME="${PREAPPLY_CF_MAX_TIME:-20}"

# --- Fetch seam --------------------------------------------------------------
# Default implementation: real curl. Prints HTTP code on line 1, body on 2+.
# ALWAYS exits 0 (a curl transport failure becomes code 000, handled by the
# default-deny catch-all) so the gate — not curl's exit status — owns the
# decision.
_default_curl() {
  local path="$1" resp code body
  # `-w '\n%{http_code}'` appends the code on its own trailing line; `-s`
  # silences the progress meter; `-S` still surfaces hard errors to stderr.
  if ! resp=$(curl -sS --max-time "$CF_MAX_TIME" \
        -H "Authorization: Bearer ${PREAPPLY_CF_TOKEN}" \
        -w $'\n%{http_code}' \
        "${CF_API_BASE}/${path}" 2>/dev/null); then
    printf '000\n'
    return 0
  fi
  code="${resp##*$'\n'}"
  body="${resp%$'\n'*}"
  printf '%s\n%s\n' "$code" "$body"
  return 0
}

# --- Small helpers -----------------------------------------------------------
# A value is "present" iff non-empty AND not the literal jq null string.
_present() { [[ -n "${1:-}" && "$1" != "null" ]]; }

# Emit a fail-closed ::error:: line. Callers set the `fail` sentinel themselves.
_err() { echo "::error::preapply-entrypoint-gate: $*" >&2; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
INFRA_GLOB="${PREAPPLY_INFRA_DIR:-$REPO_ROOT/apps/web-platform/infra}"

# =============================================================================
# --gate <plan.json>
# =============================================================================
run_gate() {
  local plan="${1:-}"
  if [[ -z "$plan" ]]; then
    _err "usage: --gate <plan.json>"
    return 1
  fi

  # 1. TOKEN GUARD (distinct message; NOT a target finding). Before any read.
  if [[ -z "${PREAPPLY_CF_TOKEN:-}" ]]; then
    _err "gate environment: CF token empty/unreadable from Doppler (PREAPPLY_CF_TOKEN) — refusing to probe. This is a gate-environment failure, not a target finding."
    return 1
  fi

  # 2. INPUT VALIDATION. A parse error / non-array / empty file must NEVER read
  #    as "zero matched rows → PASS".
  if [[ ! -f "$plan" ]]; then
    _err "plan file not found: '$plan' — refusing to read a missing plan as 'no matches'."
    return 1
  fi
  if ! jq -e '.resource_changes | type == "array"' "$plan" >/dev/null 2>&1; then
    _err "plan JSON unparseable or .resource_changes is not an array ('$plan') — refusing to read as 'no matches'."
    return 1
  fi

  # 3. PLAN-SHAPE PRE-FILTER. Iterate the FULL resource_changes[] array (never
  #    the -target list — a transitively pulled-in create must still be caught).
  #    EXACT `["create"]` (NOT index("create"), which also matches -replace
  #    ["delete","create"] and CBD ["create","delete"]). before==null AND
  #    importing==null (an imported/adopted resource is exempt in both phases).
  local matched
  matched=$(jq -c '
    .resource_changes[]
    | select(.type == "cloudflare_ruleset")
    | select(.change.actions == ["create"])
    | select(.change.before == null)
    | select(.change.importing == null)
    | {addr: .address,
       kind: .change.after.kind,
       phase: .change.after.phase,
       zone_id: .change.after.zone_id,
       account_id: .change.after.account_id}
  ' "$plan")

  local matched_count=0
  if [[ -n "$matched" ]]; then
    matched_count=$(grep -c '' <<<"$matched")
  fi

  if [[ "$matched_count" -eq 0 ]]; then
    echo "::notice::preapply-entrypoint-gate: 0 create-from-absent cloudflare_ruleset row(s); 0 live probe(s). No clobber surface."
    return 0
  fi

  echo "::notice::preapply-entrypoint-gate: ${matched_count} create-from-absent cloudflare_ruleset row(s) matched; enumerating live entrypoints (1 control probe + ${matched_count} target probe(s))."

  local fetch="${PREAPPLY_ENTRYPOINT_FETCH:-_default_curl}"

  # 4. CONTROL PROBE (once, only because ≥1 matched row). A non-200 here means
  #    the gate environment is invalid (token scope / URL scheme / network) —
  #    fail-closed with a DISTINCT message so a subsequent target 404 provably
  #    means "empty phase", not "mis-constructed URL / bad token".
  local control_zone control_out control_code
  control_zone="${PREAPPLY_CF_ZONE_ID:-}"
  if ! _present "$control_zone"; then
    _err "gate environment invalid: PREAPPLY_CF_ZONE_ID is empty — cannot run the control probe. NOT a target finding."
    return 1
  fi
  if ! control_out=$("$fetch" "zones/${control_zone}/rulesets/phases/${CONTROL_PHASE}/entrypoint" 2>/dev/null); then
    _err "gate environment invalid: control probe fetch failed to execute. NOT a target finding."
    return 1
  fi
  control_code=$(head -n1 <<<"$control_out")
  if [[ "$control_code" != "200" ]]; then
    _err "gate environment invalid: control probe on known-populated phase '${CONTROL_PHASE}' returned HTTP '${control_code}' (expected 200) — token scope / URL scheme / network problem, NOT a target finding. Refusing to trust any target 404 as 'empty'."
    return 1
  fi

  # 5-6. Per matched row: build the endpoint URL (kind allowlist), probe it,
  #      apply DEFAULT-DENY HTTP handling. Aggregate a `fail` sentinel across
  #      ALL rows (never early-exit on the first clobber — a later row could
  #      also clobber and its remedy must be printed too).
  local fail=0 processed=0
  local row addr kind phase zone_id account_id url out code body
  while IFS= read -r row; do
    [[ -z "$row" ]] && continue
    processed=$((processed + 1))
    addr=$(jq -r '.addr'       <<<"$row")
    kind=$(jq -r '.kind'       <<<"$row")
    phase=$(jq -r '.phase'     <<<"$row")
    zone_id=$(jq -r '.zone_id' <<<"$row")
    account_id=$(jq -r '.account_id' <<<"$row")

    if ! _present "$phase"; then
      fail=1
      _err "row '${addr}': phase is null/empty/unknown-after-apply — cannot enumerate the entrypoint. Fail-closed."
      continue
    fi

    # kind allowlist: zone → zones/…, root → accounts/…, anything else → deny.
    case "$kind" in
      zone)
        if ! _present "$zone_id"; then
          fail=1
          _err "row '${addr}': kind=zone but zone_id is null/empty/unknown-after-apply — cannot build the entrypoint URL. Fail-closed."
          continue
        fi
        url="zones/${zone_id}/rulesets/phases/${phase}/entrypoint"
        ;;
      root)
        if ! _present "$account_id"; then
          fail=1
          _err "row '${addr}': kind=root but account_id is null/empty/unknown-after-apply — cannot build the entrypoint URL. Fail-closed."
          continue
        fi
        url="accounts/${account_id}/rulesets/phases/${phase}/entrypoint"
        ;;
      *)
        fail=1
        _err "row '${addr}': unclassified ruleset kind '${kind}' — not in the {zone,root} allowlist. Enumerate this entrypoint by hand and adjudicate the class in ADR-133 before applying. Fail-closed."
        continue
        ;;
    esac

    if ! out=$("$fetch" "$url" 2>/dev/null); then
      fail=1
      _err "row '${addr}': entrypoint fetch failed to execute (${url}). Fail-closed."
      continue
    fi
    code=$(head -n1 <<<"$out")
    body=$(tail -n +2 <<<"$out")

    # DEFAULT-DENY HTTP handling. PASS only on proven-empty; else fail-closed.
    if [[ "$code" == "200" ]]; then
      local rulecount live_id live_rules import_id
      if ! rulecount=$(jq -e '.result.rules | length' <<<"$body" 2>/dev/null); then
        fail=1
        _err "row '${addr}': entrypoint returned 200 but .result.rules is unparseable — refusing to read as 'empty'. Fail-closed."
        continue
      fi
      if [[ "$rulecount" -gt 0 ]]; then
        fail=1
        live_id=$(jq -r '.result.id // "<unknown-ruleset-id>"' <<<"$body")
        live_rules=$(jq -c '.result.rules' <<<"$body")
        if [[ "$kind" == "zone" ]]; then
          import_id="zone/${zone_id}/${live_id}"
        else
          import_id="${account_id}/${live_id}"
        fi
        _err "CLOBBER RISK — '${addr}' is planned as a create-from-absent into phase '${phase}', but its LIVE entrypoint already holds ${rulecount} rule(s). Applying would whole-list-replace them (the #6746 outage class)."
        _err "REMEDY (adopt before applying) — add this SINGULAR-form v4 import block; the plural 'zones/…' form fails as Authentication error (10000):"
        _err "  import { to = ${addr}; id = \"${import_id}\" }"
        _err "and reproduce these live rules verbatim in the resource (including each 'ref', which preserves rule IDs across a whole-list PUT):"
        _err "  ${live_rules}"
        continue
      fi
      # 200 with 0 rules → proven-empty → PASS this row.
      echo "::notice::preapply-entrypoint-gate: '${addr}' → phase '${phase}' entrypoint is 200/empty — safe to create."
      continue
    elif [[ "$code" == "404" ]]; then
      # 404 → phase exists, no ruleset yet → proven-empty → PASS this row.
      echo "::notice::preapply-entrypoint-gate: '${addr}' → phase '${phase}' entrypoint is 404 (empty phase) — safe to create."
      continue
    else
      # Everything else (000/400/401/403/429/5xx/non-numeric) → fail-closed.
      fail=1
      _err "row '${addr}': entrypoint probe returned HTTP '${code}' (not 200-empty and not 404). Default-deny: refusing to apply on an ambiguous entrypoint read. Fail-closed."
      continue
    fi
  done <<<"$matched"

  # Minimum-cardinality guard: every matched row MUST have been processed. An
  # early loop-exit that skipped a row could mask a clobber — treat any shortfall
  # as fail-closed.
  if [[ "$processed" -ne "$matched_count" ]]; then
    _err "internal: processed ${processed} of ${matched_count} matched row(s) — loop did not visit every row. Fail-closed."
    return 1
  fi

  if [[ "$fail" -ne 0 ]]; then
    return 1
  fi
  echo "::notice::preapply-entrypoint-gate: all ${matched_count} create-from-absent row(s) target proven-empty entrypoints — no clobber. PASS."
  return 0
}

# =============================================================================
# --audit [--live]
# =============================================================================
# Static: enumerate declared cloudflare_ruleset resources from *.tf, classify
# zone vs account, note -target coverage. Runnable at /work (no creds).
# Live (--live): control-probe, GET each entrypoint, diff live rules against
# `terraform show -json` state. CI-only (needs PREAPPLY_CF_TOKEN + zone/acct).
run_audit() {
  local live=0
  [[ "${1:-}" == "--live" ]] && live=1

  # Parse each `resource "cloudflare_ruleset" "<name>" { … kind = "<k>" …
  # phase = "<p>" … }` into name<TAB>kind<TAB>phase. Portable awk (no gawk
  # 3-arg match): track the enclosing ruleset and capture the first kind/phase
  # inside the block, flushing at the next resource start or EOF.
  local tf pairs=""
  for tf in "$INFRA_GLOB"/*.tf; do
    [[ -f "$tf" ]] || continue
    pairs+=$(awk '
      function flush() { if (name != "") print name "\t" kind "\t" phase }
      /resource[[:space:]]+"cloudflare_ruleset"[[:space:]]+"/ {
        flush()
        line=$0; sub(/.*"cloudflare_ruleset"[[:space:]]+"/, "", line); sub(/".*/, "", line)
        name=line; kind=""; phase=""; next
      }
      name != "" && kind == ""  && /kind[[:space:]]*=/  { k=$0; sub(/.*kind[[:space:]]*=[[:space:]]*"/,  "", k); sub(/".*/, "", k); kind=k }
      name != "" && phase == "" && /phase[[:space:]]*=/ { p=$0; sub(/.*phase[[:space:]]*=[[:space:]]*"/, "", p); sub(/".*/, "", p); phase=p }
      END { flush() }
    ' "$tf")
    pairs+=$'\n'
  done

  echo "PREAPPLY-AUDIT-STATIC"
  echo "# Whole-list entrypoint audit — declared cloudflare_ruleset resources"
  echo ""
  echo "| Ruleset (name) | kind | phase | entrypoint class | gate-covered |"
  echo "|---|---|---|---|---|"

  local name kind phase cls rows=0
  while IFS=$'\t' read -r name kind phase; do
    [[ -z "$name" ]] && continue
    rows=$((rows + 1))
    case "$kind" in
      zone) cls="zones/<zone>/rulesets/phases/${phase}/entrypoint" ;;
      root) cls="accounts/<acct>/rulesets/phases/${phase}/entrypoint" ;;
      *)    cls="(non-entrypoint kind: ${kind})" ;;
    esac
    echo "| ${name} | ${kind} | ${phase:-—} | ${cls} | yes (cloudflare_ruleset) |"
  done <<<"$pairs"

  echo ""
  echo "Declared cloudflare_ruleset resources: ${rows}"

  if [[ "$live" -eq 0 ]]; then
    echo ""
    echo "Static audit only. Live entrypoint enumeration requires CI creds; run with --live under the guarded entrypoint-audit dispatch (see runbook cloudflare-whole-list-entrypoint-audit.md)."
    return 0
  fi

  # --- Live audit (CI, read-only) ---------------------------------------------
  # Control-probe first, then GET each declared zone/root ruleset's LIVE
  # entrypoint (phase from *.tf, zone/account id from env) and report the live
  # rule count. Read-only: NO import, NO apply. Findings post to #6767.
  echo "PREAPPLY-AUDIT-LIVE"
  if [[ -z "${PREAPPLY_CF_TOKEN:-}" ]]; then
    _err "audit --live: CF token empty/unreadable (PREAPPLY_CF_TOKEN). Fail-closed."
    return 1
  fi
  local zone acct fetch
  zone="${PREAPPLY_CF_ZONE_ID:-}"
  acct="${PREAPPLY_CF_ACCOUNT_ID:-}"
  fetch="${PREAPPLY_ENTRYPOINT_FETCH:-_default_curl}"
  if ! _present "$zone"; then
    _err "audit --live: PREAPPLY_CF_ZONE_ID empty. Fail-closed."
    return 1
  fi
  local cout ccode
  cout=$("$fetch" "zones/${zone}/rulesets/phases/${CONTROL_PHASE}/entrypoint" 2>/dev/null) || {
    _err "audit --live: control probe failed to execute. Fail-closed."; return 1; }
  ccode=$(head -n1 <<<"$cout")
  if [[ "$ccode" != "200" ]]; then
    _err "audit --live: control probe returned HTTP '${ccode}' (expected 200). Fail-closed."
    return 1
  fi
  echo "control probe (${CONTROL_PHASE}) → 200 OK"
  echo ""
  echo "| Ruleset | kind | phase | live HTTP | live rule count |"
  echo "|---|---|---|---|---|"
  local url out code body cnt
  while IFS=$'\t' read -r name kind phase; do
    [[ -z "$name" ]] && continue
    case "$kind" in
      zone) _present "$zone" && url="zones/${zone}/rulesets/phases/${phase}/entrypoint" || url="" ;;
      root) _present "$acct" && url="accounts/${acct}/rulesets/phases/${phase}/entrypoint" || url="" ;;
      *)    url="" ;;
    esac
    if [[ -z "$url" || -z "$phase" ]]; then
      echo "| ${name} | ${kind} | ${phase:-—} | (not enumerable — no id/phase) | — |"
      continue
    fi
    out=$("$fetch" "$url" 2>/dev/null) || { echo "| ${name} | ${kind} | ${phase} | fetch-failed | — |"; continue; }
    code=$(head -n1 <<<"$out"); body=$(tail -n +2 <<<"$out")
    if [[ "$code" == "200" ]]; then
      cnt=$(jq -r '.result.rules | length' <<<"$body" 2>/dev/null || echo "unparseable")
    elif [[ "$code" == "404" ]]; then
      cnt="0 (404 empty phase)"
    else
      cnt="unknown (HTTP ${code})"
    fi
    echo "| ${name} | ${kind} | ${phase} | ${code} | ${cnt} |"
  done <<<"$pairs"
  return 0
}

# =============================================================================
# Dispatch
# =============================================================================
main() {
  local mode="${1:-}"
  case "$mode" in
    --gate)
      shift
      run_gate "${1:-}"
      ;;
    --audit)
      shift
      run_audit "${1:-}"
      ;;
    *)
      _err "usage: $(basename "$0") --gate <plan.json> | --audit [--live]"
      return 2
      ;;
  esac
}

main "$@"
