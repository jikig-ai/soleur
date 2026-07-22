#!/usr/bin/env bash
# =============================================================================
# Tests for tests/scripts/lib/preapply-entrypoint-gate.sh (#6767) — the
# fail-closed PRE-APPLY GATE that stops a `terraform apply` from silently
# clobbering a dashboard-created Cloudflare ruleset phase entrypoint, plus its
# retrospective --audit mode.
#
# Three test families, all deterministic and network-free:
#   1. GATE control flow      — synthesized fixtures + a STUBBED fetch seam
#                               (PREAPPLY_ENTRYPOINT_FETCH), so every branch of
#                               the decision table is asserted with NO live API.
#   2. WIRING                  — the gate is invoked from the apply workflow as a
#                               separate step AFTER "Terraform plan" and BEFORE
#                               the MAIN "Terraform apply", with no [ack-destroy]
#                               bypass (grep over the YAML, comments stripped,
#                               tokens asserted independently / whitespace-norm).
#   3. PARITY                  — the forcing function: FAIL if a dispatch -target
#                               set gains a cloudflare_ruleset without a gate, or
#                               if a new cloudflare_* type appears un-adjudicated
#                               vs the ADR-133 / destroy-guard class table.
#
# AUTHORING FOOT-GUNS (per AGENTS + the plan): never `grep -q` on a pipe under
# pipefail (SIGPIPE 141 false-negative) — here-strings / file-arg greps only;
# every negative assertion is mutation-proven capable of failing (the fixtures
# for the opposite verdict exist); minimum-cardinality guards on data-derived
# loops; body-grep wiring assertions anchor on syntactic constructs, not bare
# tokens that also appear in comments.
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$REPO_ROOT/tests/scripts/lib/preapply-entrypoint-gate.sh"
FIXTURES="$REPO_ROOT/tests/scripts/fixtures"
WORKFLOW="$REPO_ROOT/.github/workflows/apply-web-platform-infra.yml"
ADR133="$REPO_ROOT/knowledge-base/engineering/architecture/decisions/ADR-133-preapply-entrypoint-enumeration-gate.md"

pass=0; fail=0
_report() {
  local label="$1" status="$2" detail="${3:-}"
  if [[ "$status" == "ok" ]]; then
    pass=$((pass + 1)); echo "[ok] $label"
  else
    fail=$((fail + 1)); echo "[FAIL] $label $detail" >&2
  fi
}

if [[ ! -f "$GATE" ]]; then
  echo "ERROR: $GATE does not exist — RED phase expected this." >&2
  exit 1
fi

# --- Fetch stub --------------------------------------------------------------
# A process-safe stub (external command, so it crosses the `bash "$GATE"`
# boundary the injection seam names). Logs every call to $STUB_CALLLOG and
# branches on the phase segment of the URL. The control phase is answered from
# STUB_CONTROL_CODE; targets from a per-phase file under STUB_RESPONSE_DIR if
# present, else the global STUB_TARGET_CODE/STUB_TARGET_BODY.
STUB="$(mktemp)"
cat > "$STUB" <<'STUB_EOF'
#!/usr/bin/env bash
set -euo pipefail
path="$1"
[[ -n "${STUB_CALLLOG:-}" ]] && printf '%s\n' "$path" >> "$STUB_CALLLOG"
phase="${path##*phases/}"; phase="${phase%%/entrypoint}"
if [[ "$phase" == "http_request_dynamic_redirect" ]]; then
  printf '%s\n%s\n' "${STUB_CONTROL_CODE:-200}" '{"result":{"id":"ctrlid","rules":[{"ref":"c"}]}}'
  exit 0
fi
if [[ -n "${STUB_RESPONSE_DIR:-}" && -f "$STUB_RESPONSE_DIR/$phase" ]]; then
  cat "$STUB_RESPONSE_DIR/$phase"
  exit 0
fi
printf '%s\n%s\n' "${STUB_TARGET_CODE:-404}" "${STUB_TARGET_BODY:-}"
STUB_EOF
chmod +x "$STUB"

CALLLOG="$(mktemp)"
trap 'rm -f "$STUB" "$CALLLOG"; rm -rf "${SCRATCH:-}"' EXIT

POPULATED_BODY='{"result":{"id":"liverulesetid1234567890abcdef","rules":[{"ref":"dcb85bexisting","action":"set_config"}]}}'
EMPTY_200_BODY='{"result":{"id":"emptyrulesetid","rules":[]}}'

# Run the gate against a fixture with stub-controlled responses. Sets OUT, RC.
_gate() {
  # NOTE: token uses ${5-...} (no colon) so an explicitly-empty 5th arg stays
  # empty (the empty-token test), while an OMITTED arg gets the dummy default.
  local fixture="$1" ctrl="${2:-200}" tcode="${3:-404}" tbody="${4:-}" token="${5-dummy-token}"
  : > "$CALLLOG"
  OUT="$(
    PREAPPLY_CF_TOKEN="$token" \
    PREAPPLY_CF_ZONE_ID="test-zone" \
    PREAPPLY_ENTRYPOINT_FETCH="$STUB" \
    STUB_CALLLOG="$CALLLOG" \
    STUB_CONTROL_CODE="$ctrl" \
    STUB_TARGET_CODE="$tcode" \
    STUB_TARGET_BODY="$tbody" \
    bash "$GATE" --gate "$fixture" 2>&1
  )" && RC=0 || RC=$?
}
_calls() { local n=0; [[ -s "$CALLLOG" ]] && n=$(grep -c '' <"$CALLLOG"); echo "$n"; }

# --- 1. GATE control flow ----------------------------------------------------

# G1: create (zone) + control 200 + target 200/2-rules → BLOCK, singular import.
t_clobber_blocks() {
  _gate "$FIXTURES/tfplan-ruleset-create.json" 200 200 "$POPULATED_BODY"
  if [[ "$RC" -ne 0 ]] \
     && grep -Eq 'CLOBBER RISK' <<<"$OUT" \
     && grep -Eq 'import \{ to = cloudflare_ruleset\.seo_config_settings; id = "zone/zone000000000000000000000000000f/liverulesetid' <<<"$OUT"; then
    _report "G1 create-over-nonempty BLOCKS + carries singular zone/<id> import remedy" ok
  else
    _report "G1 create-over-nonempty BLOCKS" fail "RC=$RC OUT=$(tr '\n' '|' <<<"$OUT")"
  fi
}

# G2: create (zone) + target 404 (empty phase) → PASS.
t_empty_404_passes() {
  _gate "$FIXTURES/tfplan-ruleset-create.json" 200 404 ""
  if [[ "$RC" -eq 0 ]]; then
    _report "G2 create-into-404-empty-phase PASSES (rc=0)" ok
  else
    _report "G2 create-into-404-empty-phase PASSES" fail "RC=$RC OUT=$(tr '\n' '|' <<<"$OUT")"
  fi
}

# G3: create (zone) + target 200 with 0 rules → PASS.
t_empty_200_passes() {
  _gate "$FIXTURES/tfplan-ruleset-create.json" 200 200 "$EMPTY_200_BODY"
  if [[ "$RC" -eq 0 ]]; then
    _report "G3 create-into-200-empty PASSES (rc=0)" ok
  else
    _report "G3 create-into-200-empty PASSES" fail "RC=$RC OUT=$(tr '\n' '|' <<<"$OUT")"
  fi
}

# G4: control probe non-200 → fail-closed (gate-environment-invalid, DISTINCT).
t_control_non200_fails_closed() {
  _gate "$FIXTURES/tfplan-ruleset-create.json" 500 404 ""
  if [[ "$RC" -ne 0 ]] && grep -Eq 'gate environment invalid: control probe' <<<"$OUT"; then
    _report "G4 control-probe non-200 fails closed (gate-environment-invalid)" ok
  else
    _report "G4 control-probe non-200 fails closed" fail "RC=$RC OUT=$(tr '\n' '|' <<<"$OUT")"
  fi
}

# G5-G8: default-deny — one HTTP-code family per case, all → fail-closed.
t_default_deny_families() {
  local code
  for code in 403 000 429 503 abc; do
    _gate "$FIXTURES/tfplan-ruleset-create.json" 200 "$code" ""
    if [[ "$RC" -ne 0 ]] && grep -Eq "returned HTTP '${code}'" <<<"$OUT"; then
      _report "G5.${code} target HTTP ${code} fails closed (default-deny)" ok
    else
      _report "G5.${code} target HTTP ${code} fails closed" fail "RC=$RC OUT=$(tr '\n' '|' <<<"$OUT")"
    fi
  done
}

# G9: empty token → fail-closed BEFORE any curl (zero calls logged).
t_empty_token_fails_before_curl() {
  _gate "$FIXTURES/tfplan-ruleset-create.json" 200 404 "" ""
  local calls; calls=$(_calls)
  if [[ "$RC" -ne 0 ]] && grep -Eq 'CF token empty' <<<"$OUT" && [[ "$calls" -eq 0 ]]; then
    _report "G9 empty token fails closed before any curl (0 calls)" ok
  else
    _report "G9 empty token fails closed before any curl" fail "RC=$RC calls=$calls OUT=$(tr '\n' '|' <<<"$OUT")"
  fi
}

# G10: malformed / non-array / empty plan JSON → fail-closed (never PASS).
t_malformed_json_fails_closed() {
  SCRATCH="$(mktemp -d)"
  printf 'not json at all' > "$SCRATCH/malformed.json"
  printf '{"resource_changes":{}}' > "$SCRATCH/nonarray.json"
  : > "$SCRATCH/empty.json"
  local f allok=1
  for f in malformed nonarray empty; do
    _gate "$SCRATCH/$f.json" 200 404 ""
    if [[ "$RC" -ne 0 ]] && grep -Eq 'unparseable|not found|no matches' <<<"$OUT"; then
      : # ok
    else
      allok=0
      _report "G10.$f malformed plan fails closed" fail "RC=$RC OUT=$(tr '\n' '|' <<<"$OUT")"
    fi
  done
  [[ "$allok" -eq 1 ]] && _report "G10 malformed/non-array/empty plan JSON all fail closed (never 'no matches → PASS')" ok
}

# G11: account-level (kind=root) create over non-empty → BLOCK via accounts/ URL.
t_account_clobber_blocks() {
  _gate "$FIXTURES/tfplan-ruleset-create-account.json" 200 200 "$POPULATED_BODY"
  if [[ "$RC" -ne 0 ]] && grep -Eq 'accounts/acct000000000000000000000000000a/rulesets/phases' <"$CALLLOG"; then
    _report "G11 account-level (kind=root) clobber BLOCKS via accounts/ endpoint" ok
  else
    _report "G11 account-level clobber BLOCKS via accounts/ endpoint" fail "RC=$RC calllog=$(tr '\n' '|' <"$CALLLOG")"
  fi
}

# G12: account-level create into 404 → PASS.
t_account_empty_passes() {
  _gate "$FIXTURES/tfplan-ruleset-create-account.json" 200 404 ""
  if [[ "$RC" -eq 0 ]]; then
    _report "G12 account-level create into 404 PASSES" ok
  else
    _report "G12 account-level create into 404 PASSES" fail "RC=$RC OUT=$(tr '\n' '|' <<<"$OUT")"
  fi
}

# G13: unclassified kind on a create → fail-closed (no target probe for it).
t_unclassified_kind_fails_closed() {
  _gate "$FIXTURES/tfplan-ruleset-create-unclassified.json" 200 404 ""
  if [[ "$RC" -ne 0 ]] && grep -Eq "unclassified ruleset kind 'custom'" <<<"$OUT"; then
    _report "G13 unclassified ruleset kind fails closed" ok
  else
    _report "G13 unclassified ruleset kind fails closed" fail "RC=$RC OUT=$(tr '\n' '|' <<<"$OUT")"
  fi
}

# G14: replace (["delete","create"], before != null) → PASS, does NOT fire,
#      ZERO API calls (no match → no control probe). Locks spec-flow D1.
t_replace_does_not_fire() {
  _gate "$FIXTURES/tfplan-ruleset-replace.json" 200 200 "$POPULATED_BODY"
  local calls; calls=$(_calls)
  if [[ "$RC" -eq 0 ]] && [[ "$calls" -eq 0 ]]; then
    _report "G14 replace (delete,create) does NOT fire — 0 API calls (exact ==[\"create\"])" ok
  else
    _report "G14 replace does NOT fire" fail "RC=$RC calls=$calls OUT=$(tr '\n' '|' <<<"$OUT")"
  fi
}

# G15: import (importing present) → PASS, ZERO API calls (exempt).
t_import_exempt() {
  _gate "$FIXTURES/tfplan-ruleset-import.json" 200 200 "$POPULATED_BODY"
  local calls; calls=$(_calls)
  if [[ "$RC" -eq 0 ]] && [[ "$calls" -eq 0 ]]; then
    _report "G15 import shape exempt — 0 API calls" ok
  else
    _report "G15 import shape exempt" fail "RC=$RC calls=$calls OUT=$(tr '\n' '|' <<<"$OUT")"
  fi
}

# G16: steady-state (no-op) → PASS, ZERO API calls (exempt).
t_steady_state_exempt() {
  _gate "$FIXTURES/tfplan-ruleset-steady-state.json" 200 200 "$POPULATED_BODY"
  local calls; calls=$(_calls)
  if [[ "$RC" -eq 0 ]] && [[ "$calls" -eq 0 ]]; then
    _report "G16 steady-state (no-op) exempt — 0 API calls" ok
  else
    _report "G16 steady-state exempt" fail "RC=$RC calls=$calls OUT=$(tr '\n' '|' <<<"$OUT")"
  fi
}

# G17: untargeted create (a ruleset create present in resource_changes alongside
#      an unrelated row) → BLOCK. Proves iterate-all-resource_changes (arch C).
t_untargeted_create_fires() {
  _gate "$FIXTURES/tfplan-ruleset-create-untargeted.json" 200 200 "$POPULATED_BODY"
  if [[ "$RC" -ne 0 ]] && grep -Eq 'transitively_pulled_in' <<<"$OUT"; then
    _report "G17 untargeted create in resource_changes[] still fires (iterate-all invariant)" ok
  else
    _report "G17 untargeted create still fires" fail "RC=$RC OUT=$(tr '\n' '|' <<<"$OUT")"
  fi
}

# G18: multi-row (one PASS + one FAIL) → BLOCK (loop aggregation). BOTH rows
#      probed (control + 2 targets = 3 calls) — proves no early-exit on row 1.
t_multirow_aggregates() {
  SCRATCH="$(mktemp -d)"
  printf '404\n' > "$SCRATCH/http_ratelimit"
  printf '200\n%s\n' "$POPULATED_BODY" > "$SCRATCH/http_config_settings"
  : > "$CALLLOG"
  OUT="$(
    PREAPPLY_CF_TOKEN="dummy" PREAPPLY_CF_ZONE_ID="test-zone" \
    PREAPPLY_ENTRYPOINT_FETCH="$STUB" STUB_CALLLOG="$CALLLOG" \
    STUB_RESPONSE_DIR="$SCRATCH" \
    bash "$GATE" --gate "$FIXTURES/tfplan-ruleset-multirow.json" 2>&1
  )" && RC=0 || RC=$?
  local calls; calls=$(_calls)
  if [[ "$RC" -ne 0 ]] && [[ "$calls" -eq 3 ]] && grep -Eq 'row_populated_phase' <<<"$OUT"; then
    _report "G18 multi-row PASS+FAIL aggregates to BLOCK; all rows probed (3 calls)" ok
  else
    _report "G18 multi-row aggregation" fail "RC=$RC calls=$calls OUT=$(tr '\n' '|' <<<"$OUT")"
  fi
}

# G19: zero create-from-absent rows → PASS with an explicit 0-probe notice
#      (a normal merge makes NO live API calls). Uses the steady-state fixture.
t_zero_match_zero_calls() {
  _gate "$FIXTURES/tfplan-ruleset-steady-state.json" 200 404 ""
  local calls; calls=$(_calls)
  if [[ "$RC" -eq 0 ]] && [[ "$calls" -eq 0 ]] && grep -Eq '0 create-from-absent' <<<"$OUT"; then
    _report "G19 zero-match plan: 0 API calls + explicit notice (normal-merge no-op)" ok
  else
    _report "G19 zero-match plan makes 0 API calls" fail "RC=$RC calls=$calls OUT=$(tr '\n' '|' <<<"$OUT")"
  fi
}

# --- 2. AUDIT static ---------------------------------------------------------

# A1: --audit static emits the parity table + the declared rulesets, rc=0.
t_audit_static_table() {
  local out rc=0
  out="$(bash "$GATE" --audit 2>&1)" || rc=$?
  if [[ "$rc" -eq 0 ]] \
     && grep -Eq 'PREAPPLY-AUDIT-STATIC' <<<"$out" \
     && grep -Eq 'seo_config_settings' <<<"$out" \
     && grep -Eq 'bulk_redirects' <<<"$out"; then
    _report "A1 --audit static emits parity table incl. seo_config_settings + bulk_redirects" ok
  else
    _report "A1 --audit static emits parity table" fail "rc=$rc out=$(tr '\n' '|' <<<"$out")"
  fi
}

# --- 3. WIRING (grep over the apply workflow) --------------------------------
# Comments are stripped first: every token below also appears in prose, so an
# unstripped body would false-PASS on its own documentation.

_workflow_code() { grep -vE '^[[:space:]]*#' "$WORKFLOW"; }

# Extract the "Pre-apply entrypoint gate" step body (from its name line to the
# next `- name:` at the same indent), comments stripped.
_gate_step_body() {
  awk '
    /^      - name: Pre-apply entrypoint gate/ { inb=1; print; next }
    inb && /^      - name: / { inb=0 }
    inb { print }
  ' "$WORKFLOW" | grep -vE '^[[:space:]]*#'
}

# W1: the plan step captures `terraform show -json tfplan > tfplan.json` once,
#     and the destroy-guard jq reads that file (not a second `terraform show`).
t_plan_step_captures_json_once() {
  local code; code="$(_workflow_code)"
  if grep -Eq 'terraform show -json tfplan > tfplan\.json' <<<"$code" \
     && grep -Eq 'jq -f "\$\{GITHUB_WORKSPACE\}/tests/scripts/lib/destroy-guard-filter-web-platform\.jq" < tfplan\.json' <<<"$code"; then
    _report "W1 plan step captures tfplan.json once; destroy-guard jq reads that file" ok
  else
    _report "W1 plan step captures tfplan.json once" fail "code=$(grep -nE 'terraform show -json|destroy-guard-filter' "$WORKFLOW" | tr '\n' '|')"
  fi
}

# W2: the gate is invoked with the script path AND `--gate tfplan.json`. The
#     tokens are asserted INDEPENDENTLY (the call spans a backslash line
#     continuation, so a single-line grep -F would miss it).
t_gate_invocation_present() {
  local code; code="$(_workflow_code)"
  if grep -Eq 'tests/scripts/lib/preapply-entrypoint-gate\.sh' <<<"$code" \
     && grep -Eq -- '--gate tfplan\.json' <<<"$code"; then
    _report "W2 apply workflow invokes preapply-entrypoint-gate.sh --gate tfplan.json" ok
  else
    _report "W2 gate invocation present" fail "code=$(grep -nE 'preapply-entrypoint-gate|--gate' "$WORKFLOW" | tr '\n' '|' || true)"
  fi
}

# W3: the gate STEP (its OWN body) exports PREAPPLY_CF_TOKEN from
#     CF_API_TOKEN_RULESETS + PREAPPLY_CF_ZONE_ID from CF_ZONE_ID, carries
#     working-directory INFRA_DIR + DOPPLER_TOKEN env + set -euo pipefail.
t_gate_step_env() {
  local body; body="$(_gate_step_body)"
  if [[ -z "$body" ]]; then
    _report "W3 gate step env wiring" fail "gate step body empty — step missing"
    return
  fi
  local ok=1 why=""
  grep -Eq 'PREAPPLY_CF_TOKEN=' <<<"$body"     || { ok=0; why+="[no PREAPPLY_CF_TOKEN export] "; }
  grep -Eq 'CF_API_TOKEN_RULESETS' <<<"$body"  || { ok=0; why+="[no CF_API_TOKEN_RULESETS] "; }
  grep -Eq 'PREAPPLY_CF_ZONE_ID=' <<<"$body"   || { ok=0; why+="[no PREAPPLY_CF_ZONE_ID export] "; }
  grep -Eq 'working-directory:.*INFRA_DIR' <<<"$body" || { ok=0; why+="[no working-directory INFRA_DIR] "; }
  grep -Eq 'DOPPLER_TOKEN:' <<<"$body"         || { ok=0; why+="[no DOPPLER_TOKEN env] "; }
  grep -Eq 'set -euo pipefail' <<<"$body"      || { ok=0; why+="[no set -euo pipefail] "; }
  if [[ "$ok" -eq 1 ]]; then
    _report "W3 gate step: PREAPPLY_CF_TOKEN←CF_API_TOKEN_RULESETS + zone + working-directory INFRA_DIR + DOPPLER_TOKEN + set -euo pipefail" ok
  else
    _report "W3 gate step env wiring" fail "$why"
  fi
}

# W4: the gate step sits AFTER "Terraform plan" and BEFORE the MAIN "Terraform
#     apply" (pinned by name; the SSH apply is "Terraform apply (SSH-...)").
t_gate_step_position() {
  local plan_ln gate_ln apply_ln
  # Patterns start with '-', so pass them via -e (a bare leading-dash arg is
  # read as an option by GNU grep / ugrep).
  plan_ln=$(grep -nF -e '- name: Terraform plan (allow-list' "$WORKFLOW" | head -1 | cut -d: -f1 || true)
  gate_ln=$(grep -nF -e '- name: Pre-apply entrypoint gate' "$WORKFLOW" | head -1 | cut -d: -f1 || true)
  # The MAIN apply step is exactly "Terraform apply" (no trailing " (").
  apply_ln=$(grep -nE '^      - name: Terraform apply$' "$WORKFLOW" | head -1 | cut -d: -f1 || true)
  if [[ -n "$plan_ln" && -n "$gate_ln" && -n "$apply_ln" ]] \
     && [[ "$gate_ln" -gt "$plan_ln" ]] && [[ "$gate_ln" -lt "$apply_ln" ]]; then
    _report "W4 gate step is AFTER Terraform plan and BEFORE the MAIN Terraform apply (plan=$plan_ln gate=$gate_ln apply=$apply_ln)" ok
  else
    _report "W4 gate step position" fail "plan=$plan_ln gate=$gate_ln apply=$apply_ln"
  fi
}

# W5: the gate step carries NO [ack-destroy] bypass. Extract the step body (from
#     its name to the next `- name:`) and assert ack-destroy is absent from it.
t_gate_step_no_ack_bypass() {
  local body; body="$(_gate_step_body)"
  if [[ -z "$body" ]]; then
    _report "W5 gate step body extracts non-empty" fail "empty body — extractor broken or step missing"
    return
  fi
  if grep -Eq 'ack-destroy' <<<"$body"; then
    _report "W5 gate step has no [ack-destroy] bypass" fail "ack-destroy token present in the gate step body"
  else
    _report "W5 gate step carries NO [ack-destroy] bypass (a clobber is never something to type past)" ok
  fi
}

# --- 3b. PARITY --------------------------------------------------------------
# The forcing function. Two invariants keep the class registry from silently
# going stale.

# The gate's covered set and ADR-133's adjudicated-OUT set. Every cloudflare_*
# type in the infra MUST be in exactly one of these two — a new un-adjudicated
# type FAILs, forcing conscious classification (cross-ref the destroy-guard
# class table in destroy-guard-filter-web-platform.jq).
GATE_COVERED=("cloudflare_ruleset")
ADJUDICATED_OUT=(
  "cloudflare_bot_management"
  "cloudflare_list"
  "cloudflare_notification_policy"
  "cloudflare_record"
  "cloudflare_zero_trust_access_application"
  "cloudflare_zero_trust_access_policy"
  "cloudflare_zero_trust_access_service_token"
  "cloudflare_zero_trust_tunnel_cloudflared"
  "cloudflare_zero_trust_tunnel_cloudflared_config"
  "cloudflare_zone_dnssec"
  "cloudflare_zone_settings_override"
)

_in_list() { local needle="$1"; shift; local x; for x in "$@"; do [[ "$x" == "$needle" ]] && return 0; done; return 1; }

# P1: every cloudflare_* TYPE declared in the infra is adjudicated (covered OR
#     out). A new type appearing un-adjudicated FAILs.
t_parity_all_types_adjudicated() {
  local types t missing=() n=0
  types=$(grep -rhoE 'resource "cloudflare_[a-z_]+"' "$REPO_ROOT"/apps/web-platform/infra/*.tf \
          | sed -E 's/resource "([a-z_]+)"/\1/' | sort -u)
  # Minimum-cardinality guard: the infra is known to declare ≥10 cloudflare types.
  n=$(grep -c '' <<<"$types")
  if [[ "$n" -lt 10 ]]; then
    _report "P1 all cloudflare_* types adjudicated" fail "only $n types enumerated — grep/glob likely broke (expected ≥10)"
    return
  fi
  while IFS= read -r t; do
    [[ -z "$t" ]] && continue
    if ! _in_list "$t" "${GATE_COVERED[@]}" && ! _in_list "$t" "${ADJUDICATED_OUT[@]}"; then
      missing+=("$t")
    fi
  done <<<"$types"
  if [[ "${#missing[@]}" -eq 0 ]]; then
    _report "P1 every cloudflare_* type in infra is adjudicated (IN gate-covered or OUT in ADR-133) [$n types]" ok
  else
    _report "P1 un-adjudicated cloudflare_* type(s)" fail "ADJUDICATE in ADR-133 + this test + the destroy-guard class table: ${missing[*]}"
  fi
}

# P2: ADR-133 names every adjudicated-OUT type — so the ADR and this test cannot
#     drift (the coupling the plan requires).
t_parity_adr_lists_out_set() {
  if [[ ! -f "$ADR133" ]]; then
    _report "P2 ADR-133 lists the adjudicated-OUT set" fail "missing $ADR133"
    return
  fi
  local t missing=()
  for t in "${ADJUDICATED_OUT[@]}"; do
    grep -Fq "$t" "$ADR133" || missing+=("$t")
  done
  if [[ "${#missing[@]}" -eq 0 ]]; then
    _report "P2 ADR-133 names every adjudicated-OUT type (ADR↔test coupling)" ok
  else
    _report "P2 ADR-133 lists the adjudicated-OUT set" fail "absent from ADR-133: ${missing[*]}"
  fi
}

# P3: every apply-*.yml job whose -target set includes a cloudflare_ruleset MUST
#     also invoke the gate. Today exactly one job (apply-web-platform-infra.yml's
#     `apply`) targets rulesets; if a NEW job/root gains a ruleset -target
#     without the gate, this FAILs.
t_parity_ruleset_targets_are_gated() {
  local wf files=() ungated=()
  for wf in "$REPO_ROOT"/.github/workflows/apply-*.yml; do
    [[ -f "$wf" ]] || continue
    if grep -qE '\-target=cloudflare_ruleset\.' "$wf"; then
      files+=("$wf")
      grep -q 'preapply-entrypoint-gate\.sh' "$wf" || ungated+=("$(basename "$wf")")
    fi
  done
  # Minimum-cardinality guard: at least the known workflow must match, else the
  # glob/grep silently found nothing and the test is vacuous.
  if [[ "${#files[@]}" -lt 1 ]]; then
    _report "P3 ruleset -target sets are gated" fail "0 apply-*.yml matched -target=cloudflare_ruleset — grep/glob broke (expected ≥1)"
    return
  fi
  if [[ "${#ungated[@]}" -eq 0 ]]; then
    _report "P3 every apply-*.yml with a cloudflare_ruleset -target invokes the gate [${#files[@]} file(s)]" ok
  else
    _report "P3 ruleset -target sets are gated" fail "these target a ruleset WITHOUT the gate: ${ungated[*]}"
  fi
}

# --- 3c. AUDIT JOB (guarded read-only dispatch) ------------------------------

# The entrypoint_audit dispatch value + job. Uses the awk job-block extractor
# (2-space job indent).
_job_block() {
  local job="$1"
  awk -v job="$job" '
    $0 ~ "^  " job ":([[:space:]]|$)" { inb=1; print; next }
    inb && /^  [A-Za-z_]/ { inb=0 }
    inb && /^[A-Za-z]/    { inb=0 }
    inb { print }
  ' "$WORKFLOW"
}

# D1: the entrypoint-audit dispatch value is in the apply_target choice options.
t_audit_dispatch_value_present() {
  local code; code="$(_workflow_code)"
  if grep -Eq '^[[:space:]]*- entrypoint-audit$' <<<"$code"; then
    _report "D1 apply_target choice includes 'entrypoint-audit'" ok
  else
    _report "D1 entrypoint-audit dispatch value present" fail "not in choice options"
  fi
}

# D2: the entrypoint_audit job has a mutually-exclusive if guard, its OWN
#     concurrency group (NOT the apply serializer), issues: write perms, and
#     NO `terraform apply` anywhere in its body.
t_audit_job_shape() {
  local block
  block="$(_job_block "entrypoint_audit")"
  if [[ -z "$block" ]]; then
    _report "D2 entrypoint_audit job shape" fail "job block empty — job missing or extractor broken"
    return
  fi
  local code; code="$(grep -vE '^[[:space:]]*#' <<<"$block")"
  local ok=1 why=""
  grep -Eq "inputs\.apply_target == 'entrypoint-audit'" <<<"$code" || { ok=0; why+="[no mutually-exclusive if] "; }
  grep -Eq 'issues: write' <<<"$code" || { ok=0; why+="[no issues:write] "; }
  # Own concurrency group: a `group:` line that is NOT the apply serializer.
  if grep -Eq 'group:' <<<"$code"; then
    grep -Eq 'group:[[:space:]]*terraform-apply-web-platform-host' <<<"$code" && { ok=0; why+="[reuses apply serializer group] "; }
  else
    ok=0; why+="[no concurrency group] "
  fi
  # NO terraform apply in the audit body (asserted — CTO F5).
  grep -Eq 'terraform apply' <<<"$code" && { ok=0; why+="[contains terraform apply] "; }
  if [[ "$ok" -eq 1 ]]; then
    _report "D2 entrypoint_audit: mutually-exclusive if + own concurrency + issues:write + NO terraform apply" ok
  else
    _report "D2 entrypoint_audit job shape" fail "$why"
  fi
}

# --- Run all -----------------------------------------------------------------
t_clobber_blocks
t_empty_404_passes
t_empty_200_passes
t_control_non200_fails_closed
t_default_deny_families
t_empty_token_fails_before_curl
t_malformed_json_fails_closed
t_account_clobber_blocks
t_account_empty_passes
t_unclassified_kind_fails_closed
t_replace_does_not_fire
t_import_exempt
t_steady_state_exempt
t_untargeted_create_fires
t_multirow_aggregates
t_zero_match_zero_calls
t_audit_static_table
t_plan_step_captures_json_once
t_gate_invocation_present
t_gate_step_env
t_gate_step_position
t_gate_step_no_ack_bypass
t_parity_all_types_adjudicated
t_parity_adr_lists_out_set
t_parity_ruleset_targets_are_gated
t_audit_dispatch_value_present
t_audit_job_shape

echo "=== $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
