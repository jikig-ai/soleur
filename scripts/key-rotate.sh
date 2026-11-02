#!/usr/bin/env bash
# key-rotate.sh - the orchestration body of .github/workflows/key-rotate.yml (#11294, ADR-314; runbook key-rotation.md).
#
# Rotates ONE non-tunnel secret per dispatch (the seven keys of the table below) by a targeted Terraform -replace, then redeploys
# the web fleet canary-then-prod. It SOURCES scripts/inngest-key-rotate.sh (ADR-307, untouched) and overrides what differs
# (CTO F1): the gate table, the in-flight list, the verdict tokens and the same-name redefinitions further down. Bash binds late,
# so only a redefinition BY THE SAME NAME intercepts the sourced callers (kr_post_write_failure calls kr_refuse and kr_post_write_stop).
#
#   key-rotate.sh precondition        credential-free sanity step: the ref rung, then the redaction suite on the dispatched ref
#   key-rotate.sh guard               refusal ladder; outputs go/mode/key/run_apply/run_redeploy/guard_epoch (writes nothing)
#   key-rotate.sh apply               re-checks, value-silent pre-state, plan, five-field projection, gate, apply, post-state
#                                     (EFF_MODE=plan: everything up to and including the gate, writes nothing)
#   key-rotate.sh redeploy recheck|track|verdict   the three steps of the redeploy job
#   key-rotate.sh notify              the ONLY issue filer: after a write, a job that was cancelled or never reported leaves no stop
#                                     sentence of its own, so this files the one action-required issue
#   key-rotate.sh --print-contract    offline and credential-free: the fixed verdict-token list
#
# THE REPOSITORY IS PUBLIC. random_id's `id` IS the key in base64url, so a Terraform stream never reaches a log: every Terraform
# call goes through the sourced kr_tf chokepoint (both streams to files under a 0700 temp dir). The full `terraform show -json`
# holds every root variable and the prior state, so it is projected to five fields at once and deleted. A copy of a key is read
# only through a pipe into sha256sum; only booleans and states leave the function.
#
# No `set -e` (the sourced bodies end in `[[ ]] &&` statements) and no `trap` (the sourced kr_init owns the EXIT trap that removes
# the key-bearing temp files; a second EXIT trap would silently replace it).
# shellcheck disable=SC2034,SC2016  # the sourced route reads KR_* by name; the jq programs are single-quoted on purpose

set -uo pipefail

case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles live credentials and -x would print them (see #7797)\n' >&2; exit 78 ;;
esac

# (0) BEFORE the first source: the Tier-B loader exports a whole Doppler project and the sourced file assigns KR_*, so a stray KR_* or
# KK_* name in the environment must not steer a command. Only the first name is reported (never a value).
if [[ "${GITHUB_ACTIONS:-}" == true ]]; then
  while IFS= read -r _kk_v; do
    printf '[FAIL SETUP] variable %s is set under GITHUB_ACTIONS=true before the sourced route was loaded; refusing (verdict=internal_error)\n' "$_kk_v" >&2
    exit 78
  done < <(compgen -v | grep -E '^K[RK]_')
fi

KK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# (1) the source, AT TOP LEVEL (inside a function the sourced `declare -A` globals would be local).
# shellcheck source=/dev/null
source "$KK_ROOT/scripts/inngest-key-rotate.sh" || { printf '[FAIL SETUP] scripts/inngest-key-rotate.sh could not be sourced (verdict=internal_error)\n' >&2; exit 78; }

# (2) fail-closed type check of every sourced symbol this script depends on, before any Terraform call.
KK_SYMBOL_FUNCS=(kr_tf kr_init kr_tf_prepare kr_scrub kr_gate_rows kr_gate_targets kr_gate_replaces kr_gate_want kr_refuse kr_ok
  kr_inflight_check kr_chk_attempt kr_chk_quiet kr_summary kr_out kr_token_known kr_now kr_iso kr_sleep kr_post_write_failure)
KK_SYMBOL_ARRAYS=(KR_GATE_TABLE KR_INFLIGHT_WORKFLOWS KR_VERDICT_TOKENS)
KK_SYMBOL_SCALARS=(KR_GATE_JQ KR_CHANGED)
for _kk_s in "${KK_SYMBOL_FUNCS[@]}"; do
  declare -F "$_kk_s" >/dev/null 2>&1 || { printf '[FAIL SETUP] sourced function %s is missing (verdict=internal_error)\n' "$_kk_s" >&2; exit 78; }
done
for _kk_s in "${KK_SYMBOL_ARRAYS[@]}"; do
  [[ "$(declare -p "$_kk_s" 2>/dev/null)" == "declare -a "* ]] || { printf '[FAIL SETUP] sourced %s is not a writable array (verdict=internal_error)\n' "$_kk_s" >&2; exit 78; }
done
for _kk_s in "${KK_SYMBOL_SCALARS[@]}"; do
  [[ "$(declare -p "$_kk_s" 2>/dev/null)" == "declare -- "* ]] || { printf '[FAIL SETUP] sourced %s is not a scalar (verdict=internal_error)\n' "$_kk_s" >&2; exit 78; }
done

# (3) wholesale assignment of the three override points. The sourced token list carries tokens this route never emits, so appending
# would make "the list equals the emitted literals" unsatisfiable.
KR_VERDICT_TOKENS=(
  guard_ok ref_refused inputs_invalid actor_refused actor_not_owner rerun_refused confirm_mismatch quiet_window_missing
  egress_rotate_unsupported_no_vector_restart_lever approval_environment_missing webhook_patch_not_ready owner_step_open
  kb_drift_cron_window kb_drift_walker_in_flight run_in_flight run_list_unreadable redaction_coverage_unconfirmed credential_absent
  authorization_stale copy_unreadable partial_absent_state plan_ok plan_gate_refused replace_not_requested terraform_failed
  apply_failed post_hash_unreadable value_unchanged copies_differ rotated_redeploy_failed owner_step_pending issue_unfiled
  rotate_ok job_cancelled internal_error
)
KR_INFLIGHT_WORKFLOWS=(apply-web-platform-infra.yml apply-deploy-pipeline-fix.yml web-platform-release.yml inngest-key-rotate.yml inngest-link-flip.yml cutover-inngest.yml deploy-inngest-image.yml)

# THE GATE TABLE (Guard 1). One table feeds the -target list, the -replace list and the jq allowlist. Fields:
# phase|key|address|flag|actions. flag=replace: targeted AND replaced. flag=target: targeted only; the address changes in place
# because the replaced random_id feeds it. The four inngest_* secrets carry lifecycle.ignore_changes=[value], so they are replaced
# with their random_id (replace-both); the other three have no ignore_changes, so a replaced random_id updates them in place and
# there is no absent-secret window (CTO ruling 2026-11-02; terraform-target-parity.test.ts derives the flag from the HCL).
KR_GATE_TABLE=(
  'A|inngest_manual_trigger_secret_dev|random_id.inngest_manual_trigger_secret_dev|replace|delete,create'
  'B|inngest_manual_trigger_secret_dev|doppler_secret.inngest_manual_trigger_secret_dev|replace|delete,create'
  'A|inngest_manual_trigger_secret_prd|random_id.inngest_manual_trigger_secret_prd|replace|delete,create'
  'B|inngest_manual_trigger_secret_prd|doppler_secret.inngest_manual_trigger_secret_prd|replace|delete,create'
  'A|inngest_signing_key_dev|random_id.inngest_signing_key_dev|replace|delete,create'
  'B|inngest_signing_key_dev|doppler_secret.inngest_signing_key_dev|replace|delete,create'
  'A|inngest_event_key_dev|random_id.inngest_event_key_dev|replace|delete,create'
  'B|inngest_event_key_dev|doppler_secret.inngest_event_key_dev|replace|delete,create'
  'A|kb_drift_ingest_signing_key|random_id.kb_drift_ingest_signing_key|replace|delete,create'
  'B|kb_drift_ingest_signing_key|doppler_secret.kb_drift_ingest_signing_key|target|update'
  'B|kb_drift_ingest_signing_key|doppler_secret.kb_drift_ingest_signing_key_app_runtime|target|update'
  'A|egress_audit_ingest_token|random_id.egress_audit_ingest_token|replace|delete,create'
  'B|egress_audit_ingest_token|doppler_secret.egress_audit_ingest_token|target|update'
  'A|github_webhook_secret|random_id.github_webhook_secret|replace|delete,create'
  'B|github_webhook_secret|doppler_secret.github_app_webhook_secret|target|update'
)

# The copies each key's value lives in: key|project|config|name|address (value-silent reads and the gate's per-copy recovery flag).
KK_COPIES=(
  'inngest_manual_trigger_secret_dev|soleur|dev|INNGEST_MANUAL_TRIGGER_SECRET|doppler_secret.inngest_manual_trigger_secret_dev'
  'inngest_manual_trigger_secret_prd|soleur|prd|INNGEST_MANUAL_TRIGGER_SECRET|doppler_secret.inngest_manual_trigger_secret_prd'
  'inngest_signing_key_dev|soleur|dev|INNGEST_SIGNING_KEY|doppler_secret.inngest_signing_key_dev'
  'inngest_event_key_dev|soleur|dev|INNGEST_EVENT_KEY|doppler_secret.inngest_event_key_dev'
  'kb_drift_ingest_signing_key|soleur|prd_kb_drift_walker|KB_DRIFT_INGEST_SIGNING_KEY|doppler_secret.kb_drift_ingest_signing_key'
  'kb_drift_ingest_signing_key|soleur|prd|KB_DRIFT_INGEST_SIGNING_KEY|doppler_secret.kb_drift_ingest_signing_key_app_runtime'
  'egress_audit_ingest_token|soleur|prd|EGRESS_AUDIT_INGEST_TOKEN|doppler_secret.egress_audit_ingest_token'
  'github_webhook_secret|soleur|prd|GITHUB_APP_WEBHOOK_SECRET|doppler_secret.github_app_webhook_secret'
)
KK_KEYS=(inngest_manual_trigger_secret_dev inngest_manual_trigger_secret_prd inngest_signing_key_dev inngest_event_key_dev
  kb_drift_ingest_signing_key egress_audit_ingest_token github_webhook_secret)

# Authorization posture (CTO H2). The environment infra-privileged has ZERO required reviewers (#11923), so the typed confirm is derivable
# from public inputs: a fat-finger guard, not an authorization. Both actors must be in this committed, exact-match allowlist (the
# CODEOWNERS owner); an owner PAT still passes (residual). Until the reviewer-gated environment exists, a rotate of the keys listed
# in kk_chk_approval refuses approval_environment_missing; the PR that binds the apply job to that environment flips the one line.
KK_OWNER_LOGINS=(deruelle)
KK_APPROVAL_ENV_BOUND=false
KK_AUTH_MAX_AGE_S=3600
KK_RETRIES=3
KK_RETRY_SLEEP_S=20
KK_MAIN_REF="refs/heads/main"
KK_WALKER_WORKFLOW="kb-drift-walker.yml"
KK_OWN_WORKFLOW="key-rotate.yml"
KK_ISSUE_LIMIT=1000

# BUDGET TABLE (seconds): only the values that differ from the sourced route. The suite pins the workflow's timeout-minutes to it as
# plain literals (guard 15/25, apply 40/50, redeploy 85/95, notify 5/15). The G3 window constants derive from these.
KK_APPLY_STEP_S=$((KR_TF_INIT_S + KR_TF_PLAN_S + KR_TF_APPLY_S + KR_STEP_SLACK_S))
KK_APPLY_JOB_S=$((KK_APPLY_STEP_S + KR_JOB_SLACK_S))
# kb_drift window (CTO G3): refuse when [now, now + the remaining budget] intersects [03:00, 03:30] UTC.
KK_KB_WIN_START_S=10800
KK_KB_WIN_LEN_S=1800
KK_KB_BUDGET_GUARD_S=$((KK_APPLY_STEP_S + KR_REDEPLOY_STEP_S))
KK_KB_BUDGET_APPLY_S=$((KK_APPLY_STEP_S + KR_REDEPLOY_STEP_S))
KK_KB_BUDGET_PREAPPLY_S=$((KR_TF_APPLY_S + KR_STEP_SLACK_S + KR_REDEPLOY_STEP_S))
KK_KB_BUDGET_REDEPLOY_S=$KR_REDEPLOY_STEP_S

# The plan projection (CTO H1): ONLY these five fields survive the full `terraform show -json`.
KK_PROJECT_JQ='[.resource_changes[]? | select((.change.actions == ["no-op"] or .change.actions == ["read"]) | not)
  | {address: .address, actions: .change.actions, action_reason: (.action_reason // null), before_null: (.change.before == null), after_unknown_value: (((.change.after_unknown // {}) | if type == "object" then .value else null end) == true)}]'
# The gate over the projection. $want rows: {address, actions, recovery (phase B), replace, recover}.
KK_GATE_JQ='length as $n | ($want | length) as $w
  | $w > 0 and $n == $w
  and ((map(.address) | unique) == ($want | map(.address) | unique))
  and all(.[]; . as $x | any($want[]; . as $r | $r.address == $x.address
      and (($x.actions == $r.actions
            and (if $r.replace then $x.action_reason == "replace_by_request" else true end)
            and (if $r.recovery then $x.after_unknown_value == true else true end))
        or ($r.recover and $x.actions == ["create"] and $x.before_null == true
            and (if $r.recovery then $x.after_unknown_value == true else true end)))))'

KK_GUARD_MODE=""
declare -A KK_BOOL=()
KK_BOOL_ORDER=()
KK_CP=()
KK_PRE_ST=()
KK_PRE_H=()
KK_POST_ST=()
KK_POST_H=()
KK_ABSENT_ALL=false

# (4) THE SAME-NAME REDEFINITIONS. Each carries Inngest-route or `converge` text in the sourced file and is reached by a sourced caller
# or by this script; the suite deletes each one in turn and requires the output to turn. Defined here, after the source.
kk_say() { printf '%s' "$*" | kr_scrub >&2; }

# kr_out: an allowlist of output names and values, so a hash or copy state can never cross a step or job boundary.
kr_out() {
  case "$1" in go|mode|key|run_apply|run_redeploy|guard_epoch|redaction_ok|write_started|verdict) ;; *) return 0 ;; esac
  [[ "$2" =~ ^[A-Za-z0-9_:.-]{0,64}$ ]] || return 0
  [[ -n "${GITHUB_OUTPUT:-}" ]] && printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT" 2>/dev/null
  return 0
}

kr_refuse() {
  local t="$1" d
  kr_token_known "$t" || t="internal_error"
  d="$(printf '%s' "${2:-}" | kr_scrub)"
  KR_VERDICT="$t"
  printf '::error::key-rotate verdict=%s %s\n' "$t" "$d" >&2
  kr_summary "- key-rotate verdict=${t}: ${d}"
  kr_out verdict "$t"
  return 0
}

kr_ok() {
  local t="$1" d
  kr_token_known "$t" || t="internal_error"
  d="$(printf '%s' "${2:-}" | kr_scrub)"
  KR_VERDICT="$t"
  printf 'key-rotate verdict=%s %s\n' "$t" "$d" >&2
  kr_summary "- key-rotate verdict=${t}: ${d}"
  kr_out verdict "$t"
  return 0
}

kr_print_contract() {
  printf 'key-rotate verdict-tokens\n'
  printf '%s\n' "${KR_VERDICT_TOKENS[@]}"
}

# kr_chk_confirm: ROTATE-<KEY upper-cased>-<UTC date from the single clock kr_now>. Exact, case-sensitive; never echoes the expected string.
kr_chk_confirm() {
  local want
  want="ROTATE-$(printf '%s' "${INPUT_KEY:-}" | tr '[:lower:]' '[:upper:]')-$(kk_date "$(kr_now)")"
  [[ "${INPUT_CONFIRM:-}" == "$want" ]] && return 0
  KR_CHECK_TOKEN=confirm_mismatch
  KR_CHECK_DETAIL="confirm must be exactly ROTATE-<KEY>-<YYYY-MM-DD> with the key name upper-cased and the UTC date of this run (a fat-finger guard, not the authorization)"
  return 1
}

kr_verdict_recipe() {
  printf "gh run view %s --log | grep 'key-rotate verdict='" "${GITHUB_RUN_ID:-<run id>}"
}

# kr_converge_cmd: the exact re-dispatch command the stop sentence and the issue carry (the owner types a fresh confirm; no agent runs it).
kr_converge_cmd() {
  local k="${EFF_KEY:-${INPUT_KEY:-<key>}}" extra=""
  [[ "$k" == github_webhook_secret ]] && extra=" -f webhook_patch_ready=true"
  printf 'gh workflow run %s -f mode=rotate -f key=%s -f confirm=ROTATE-%s-YYYY-MM-DD -f quiet_window=true%s' \
    "$KK_OWN_WORKFLOW" "$k" "$(printf '%s' "$k" | tr '[:lower:]' '[:upper:]')" "$extra"
}

# kk_state_row <token>: the three facts every stop sentence states (Doppler, Terraform state, running containers) and the next safe action.
kk_state_row() {
  case "$1" in
    apply_failed) printf 'Doppler: per-copy classification printed in the run log. Terraform state: possibly partial (a replace may have destroyed and not created). Running containers: old. Next safe action: a fresh rotate; if any copy is absent it is urgent, because a container restart now starts without the secret.' ;;
    post_hash_unreadable) printf 'Doppler: unknown. Terraform state: new. Running containers: old. Next safe action: a fresh rotate; the value is unknown, not unchanged.' ;;
    value_unchanged) printf 'Doppler: OLD value. Terraform state: new random_id. Running containers: old. Next safe action: stop and read the ADR item on the ignore_changes premise before re-dispatching; a repeat means the premise is false.' ;;
    copies_differ) printf 'Doppler: both copies present but unequal. Terraform state: new. Running containers: old. Next safe action: a fresh rotate outside the cron window.' ;;
    partial_absent_state) printf 'Doppler: some copies present, some absent. Terraform state: partial. Running containers: old. URGENT, not auto-repaired: do not restart anything; run the recovery rotate now.' ;;
    rotated_redeploy_failed) printf 'Doppler: new. Terraform state: new. Running containers: old, or a MIXED fleet if the canary swapped and prod did not. Next safe action: a fresh rotate.' ;;
    owner_step_pending) printf 'Doppler: new. Terraform state: new. Running containers: new. Next safe action: the single owner action below.' ;;
    *) printf 'Doppler, Terraform state and running containers: unknown. Next safe action: check the run and read the verdict before doing anything else.' ;;
  esac
}

# kk_degrade <token>: the per-key consequence (neutral about the gap window: this text is public).
kk_degrade() {
  local k="${EFF_KEY:-${INPUT_KEY:-}}"
  case "$1:$k" in
    owner_step_pending:github_webhook_secret) printf 'Owner step: update the GitHub App webhook secret with the new value of GITHUB_APP_WEBHOOK_SECRET (runbook key-rotation.md, then github-app-provisioning.md Step 4), redeliver failed deliveries from the App advanced settings, then close this issue.' ;;
    rotated_redeploy_failed:github_webhook_secret) printf 'Do NOT update the GitHub App webhook secret yet; re-dispatch the rotate first.' ;;
    job_cancelled:*|*:github_webhook_secret) printf 'Check the run; do not update the GitHub App webhook secret until you have read the verdict.' ;;
    rotated_redeploy_failed:kb_drift_ingest_signing_key) printf 'Until a redeploy lands, the next 03:00 UTC kb-drift walker run is rejected.' ;;
    rotated_redeploy_failed:inngest_manual_trigger_secret_prd) printf 'Until a redeploy lands, soleur:trigger-cron and the internal routes answer 401 on hosts still on the old value.' ;;
    *) printf 'No production consumer is affected beyond the stated state.' ;;
  esac
}

# kr_stop_sentence <what happened, fixed words>: the token is the verdict kr_refuse just set.
kr_stop_sentence() {
  printf 'STOP: do not re-run the failed jobs. %s %s %s Re-dispatching is the owner'"'"'s own decision under a fresh typed confirm (no agent dispatches a rotate): %s Read the verdict: %s' \
    "$1" "$(kk_state_row "${KR_VERDICT:-internal_error}")" "$(kk_degrade "${KR_VERDICT:-internal_error}")" "$(kr_converge_cmd)" "$(kr_verdict_recipe)"
}

# kr_post_write_stop <token> <what-happened> [kind]: the stop sentence and the step summary. Issues are filed ONLY by the notify job.
kr_post_write_stop() {
  local s
  s="$(kr_stop_sentence "$2")"
  s="$(printf '%s' "$s" | KR_SCRUB_CAP=1400 kr_scrub)"
  printf '::error::key-rotate %s\n' "$s" >&2
  kr_summary "STOP SENTENCE: ${s}"
  return 1
}

# kr_file_issue <token> <sentence>: the ONLY issue filer. De-duplicated on (key, token, run); re-lists after the create call and fails
# loudly when the issue is not there (a swallowed `gh` error would leave a written rotation with no owner).
kr_file_issue() {
  local repo="${GITHUB_REPOSITORY:-}" key="${EFF_KEY:-}" run="${GITHUB_RUN_ID:-0}" title body list n num
  local -a labels=(--label action-required)
  kr_token_known "$1" || { kr_refuse issue_unfiled "the verdict token is unknown"; return 1; }
  if [[ -z "${GH_TOKEN:-}" || -z "$repo" ]]; then kr_refuse issue_unfiled "no GH_TOKEN or repository; the action-required issue was not filed"; return 1; fi
  title="key-rotate ${key} ${1} (run ${run})"
  [[ "$1" == owner_step_pending ]] && labels+=(--label owner_step_pending)
  list="$(gh issue list --repo "$repo" --label action-required --state open --limit "$KK_ISSUE_LIMIT" --json number,title 2>/dev/null)" \
    || { kr_refuse issue_unfiled "the open-issue listing failed"; return 1; }
  n="$(jq 'length' <<<"$list" 2>/dev/null)" || n=""
  if [[ ! "$n" =~ ^[0-9]+$ || "$n" -ge "$KK_ISSUE_LIMIT" ]]; then kr_refuse issue_unfiled "the open-issue listing is unreadable or truncated"; return 1; fi
  body="${GITHUB_SERVER_URL:-https://github.com}/${repo}/actions/runs/${run}"$'\n\n'"verdict=${1}"$'\n\n'"${2}"$'\n'
  printf '%s' "$body" > "$KR_TMP/issue.md"
  num="$(jq -r --arg t "$title" --arg re "^key-rotate ${key} ${1} \\(run [0-9]+\\)\$" '[.[] | select(.title == $t and (.title | test($re)))] | .[0].number // empty' <<<"$list" 2>/dev/null)" || num=""
  if [[ "$num" =~ ^[0-9]+$ ]]; then
    gh issue comment "$num" --repo "$repo" --body-file "$KR_TMP/issue.md" >/dev/null 2>&1 || { kr_refuse issue_unfiled "the follow-up comment could not be posted"; return 1; }
    return 0
  fi
  gh issue create --repo "$repo" --title "$title" "${labels[@]}" --body-file "$KR_TMP/issue.md" >/dev/null 2>&1 || true
  list="$(gh issue list --repo "$repo" --label action-required --state open --limit "$KK_ISSUE_LIMIT" --json number,title 2>/dev/null)" || list="[]"
  if ! jq -e --arg t "$title" 'any(.[]; .title == $t)' <<<"$list" >/dev/null 2>&1; then
    kr_refuse issue_unfiled "the action-required issue was not created (or is missing its label); the red run is the only record"
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------------------------------------------------------
# helpers
kk_date() { date -u -d "@$1" +%F; }

kk_valid_inputs() { # mode key
  case "${1:-}" in plan|rotate) ;; *) kr_refuse inputs_invalid "mode must be plan or rotate"; return 1 ;; esac
  local k
  for k in "${KK_KEYS[@]}"; do [[ "${2:-}" == "$k" ]] && return 0; done
  kr_refuse inputs_invalid "key is not one of the seven rotatable keys"
  return 1
}

kk_chk_ref() {
  [[ "${GITHUB_REF:-}" == "$KK_MAIN_REF" ]] && return 0
  kr_refuse ref_refused "a dispatch from any ref other than main is refused; nothing was written"
  return 1
}

kk_chk_actors() {
  local a o ok
  for a in "${GITHUB_ACTOR:-}" "${GITHUB_TRIGGERING_ACTOR:-}"; do
    if [[ -z "$a" || "$a" == *"[bot]" ]]; then kr_refuse actor_refused "the dispatching actor is empty or a bot; nothing was written"; return 1; fi
  done
  for a in "${GITHUB_ACTOR:-}" "${GITHUB_TRIGGERING_ACTOR:-}"; do
    ok=1
    for o in "${KK_OWNER_LOGINS[@]}"; do [[ "$a" == "$o" ]] && ok=0; done
    if [[ "$ok" != 0 ]]; then kr_refuse actor_not_owner "the dispatching actor is not in the committed owner allowlist; nothing was written"; return 1; fi
  done
  kr_summary "actors: github.actor=$(printf '%s' "${GITHUB_ACTOR:-}" | kr_scrub) github.triggering_actor=$(printf '%s' "${GITHUB_TRIGGERING_ACTOR:-}" | kr_scrub)"
}

kk_chk_egress() {
  [[ "${1:-${INPUT_KEY:-}}" != egress_audit_ingest_token ]] && return 0
  KR_CHECK_TOKEN=egress_rotate_unsupported_no_vector_restart_lever
  KR_CHECK_DETAIL="egress_audit_ingest_token is plan-only: Vector reads the token at start and no restart lever exists without SSH (#11920)"
  return 1
}

kk_chk_approval() {
  case "${INPUT_KEY:-}" in inngest_manual_trigger_secret_prd|kb_drift_ingest_signing_key|github_webhook_secret) ;; *) return 0 ;; esac
  [[ "$KK_APPROVAL_ENV_BOUND" == true ]] && return 0
  KR_CHECK_TOKEN=approval_environment_missing
  KR_CHECK_DETAIL="this key needs the reviewer-gated approval environment (#11923), which does not exist yet; the dev keys are not subject to this"
  return 1
}

kk_chk_webhook_ready() {
  [[ "${INPUT_KEY:-}" != github_webhook_secret ]] && return 0
  [[ "${INPUT_WEBHOOK_PATCH_READY:-}" == true ]] && return 0
  KR_CHECK_TOKEN=webhook_patch_not_ready
  KR_CHECK_DETAIL="webhook_patch_ready must be true: the owner confirms the GitHub App private key and the update step are at hand (readiness, not the authorization)"
  return 1
}

kk_chk_gh() {
  [[ -n "${GH_TOKEN:-}" && -n "${GITHUB_REPOSITORY:-}" ]] && return 0
  KR_CHECK_TOKEN=credential_absent; KR_CHECK_DETAIL="GH_TOKEN or GITHUB_REPOSITORY is not set"; return 1
}

kk_chk_owner_step() { # key github only: the label exists and no open owner_step_pending issue is titled for this key
  local labels issues n
  labels="$(gh label list --repo "${GITHUB_REPOSITORY:-}" --limit "$KK_ISSUE_LIMIT" --json name 2>/dev/null)" \
    || { KR_CHECK_TOKEN=owner_step_open; KR_CHECK_DETAIL="the label listing failed (fail closed)"; return 1; }
  if ! jq -e 'any(.[]; .name == "owner_step_pending")' <<<"$labels" >/dev/null 2>&1; then
    KR_CHECK_TOKEN=owner_step_open; KR_CHECK_DETAIL="the owner_step_pending label does not exist (fail closed)"; return 1
  fi
  issues="$(gh issue list --repo "${GITHUB_REPOSITORY:-}" --label owner_step_pending --state open --limit "$KK_ISSUE_LIMIT" --json title 2>/dev/null)" \
    || { KR_CHECK_TOKEN=owner_step_open; KR_CHECK_DETAIL="the owner_step_pending listing failed (fail closed)"; return 1; }
  n="$(jq 'length' <<<"$issues" 2>/dev/null)" || n=""
  if [[ ! "$n" =~ ^[0-9]+$ || "$n" -ge "$KK_ISSUE_LIMIT" ]]; then KR_CHECK_TOKEN=owner_step_open; KR_CHECK_DETAIL="the owner_step_pending listing is unreadable or truncated (fail closed)"; return 1; fi
  n="$(jq '[.[] | select(.title | test("^key-rotate github_webhook_secret owner_step_pending \\(run [0-9]+\\)$"))] | length' <<<"$issues" 2>/dev/null)" || n=1
  [[ "$n" == 0 ]] && return 0
  KR_CHECK_TOKEN=owner_step_open; KR_CHECK_DETAIL="an owner_step_pending issue for the webhook secret is still open: finish that owner step first"; return 1
}

# kk_runs_count <workflow> <status> [lower-than-run-id]: prints the count of runs, or returns 1 when unreadable.
kk_runs_count() {
  local out n
  out="$(gh run list --repo "${GITHUB_REPOSITORY:-}" --workflow "$1" --status "$2" --limit 50 --json databaseId 2>/dev/null)" || return 1
  n="$(jq --argjson me "${GITHUB_RUN_ID:-0}" --argjson low "${3:-0}" \
    '[.[] | select(.databaseId != $me) | select($low == 0 or .databaseId < $low)] | length' <<<"$out" 2>/dev/null)" || return 1
  [[ "$n" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$n"
}

kk_chk_inflight() { # the sourced three statuses, then the two the sourced helper does not poll
  local wf st n
  kr_inflight_check || return 1
  for wf in "${KR_INFLIGHT_WORKFLOWS[@]}"; do
    for st in pending requested; do
      n="$(kk_runs_count "$wf" "$st")" || { KR_CHECK_TOKEN=run_list_unreadable; KR_CHECK_DETAIL="cannot list ${wf} runs"; return 1; }
      [[ "$n" == 0 ]] || { KR_CHECK_TOKEN=run_in_flight; KR_CHECK_DETAIL="${wf} has ${n} ${st} run(s)"; return 1; }
    done
  done
}

kk_chk_lower_run() { # refuse-only: an earlier key-rotate.yml run still queued or running (key-rotate.yml is not in the sourced list: that would count later runs too)
  local st n
  for st in queued waiting pending requested in_progress; do
    n="$(kk_runs_count "$KK_OWN_WORKFLOW" "$st" "${GITHUB_RUN_ID:-0}")" || { KR_CHECK_TOKEN=run_list_unreadable; KR_CHECK_DETAIL="cannot list ${KK_OWN_WORKFLOW} runs"; return 1; }
    [[ "$n" == 0 ]] || { KR_CHECK_TOKEN=run_in_flight; KR_CHECK_DETAIL="an earlier ${KK_OWN_WORKFLOW} run is still ${st}"; return 1; }
  done
}

# kk_chk_kb_window <budget-seconds>: [now, now + budget] against today's and tomorrow's [03:00, 03:30] UTC (inclusive both ends).
kk_chk_kb_window() {
  local b="${1:-$KK_KB_BUDGET_GUARD_S}" now day d ws we
  now="$(kr_now)"
  day=$((now / 86400 * 86400))
  for d in 0 1; do
    ws=$((day + d * 86400 + KK_KB_WIN_START_S)); we=$((ws + KK_KB_WIN_LEN_S))
    if (( now <= we && now + b >= ws )); then
      KR_CHECK_TOKEN=kb_drift_cron_window
      KR_CHECK_DETAIL="the remaining apply and redeploy budget would overlap the 03:00-03:30 UTC kb-drift walker window"
      return 1
    fi
  done
}

kk_chk_walker() {
  local st n
  for st in queued in_progress waiting pending requested; do
    n="$(kk_runs_count "$KK_WALKER_WORKFLOW" "$st")" || { KR_CHECK_TOKEN=run_list_unreadable; KR_CHECK_DETAIL="cannot list ${KK_WALKER_WORKFLOW} runs (fail closed)"; return 1; }
    [[ "$n" == 0 ]] || { KR_CHECK_TOKEN=kb_drift_walker_in_flight; KR_CHECK_DETAIL="a ${KK_WALKER_WORKFLOW} run is ${st}"; return 1; }
  done
}

# kk_recheck <key> <kb-budget-seconds>: the facts that age (in-flight runs, an earlier run of this workflow, the kb_drift windows).
kk_recheck() {
  KR_CHECK_TOKEN=internal_error; KR_CHECK_DETAIL=""
  kk_chk_inflight || return 1
  kk_chk_lower_run || return 1
  if [[ "$1" == kb_drift_ingest_signing_key ]]; then
    kk_chk_kb_window "$2" || return 1
    kk_chk_walker || return 1
  fi
  return 0
}

# kk_check <name> <function>: records a boolean. plan reports and never refuses; rotate refuses on the first false.
kk_check() {
  local name="$1" fn="$2"
  KR_CHECK_TOKEN=internal_error; KR_CHECK_DETAIL=""
  KK_BOOL_ORDER+=("$name")
  if "$fn"; then KK_BOOL[$name]=true; return 0; fi
  KK_BOOL[$name]=false
  [[ "$KK_GUARD_MODE" == plan ]] && return 0
  kr_refuse "$KR_CHECK_TOKEN" "${KR_CHECK_DETAIL}; nothing was written"
  return 1
}

kk_guard_report() {
  local n
  kr_summary "### key-rotate guard (${KK_GUARD_MODE} ${INPUT_KEY:-})"
  kr_summary "| check | value |"
  kr_summary "|---|---|"
  for n in "${KK_BOOL_ORDER[@]}"; do
    kr_summary "| ${n} | ${KK_BOOL[$n]} |"
    printf 'key-rotate check %s=%s\n' "$n" "${KK_BOOL[$n]}" >&2
  done
}

# ---------------------------------------------------------------------------------------------------------------------------
# PRECONDITION: the credential-free redaction sanity step (CTO H3). An ordering and sanity step: the safety weight is the no-stream design.
KK_REDACTION_LABELS=(tainted-must-be-replaced deposed-will-be-destroyed drift-has-changed)
kk_cmd_precondition() {
  local f rc=0 l miss=""
  kr_out redaction_ok false
  kk_chk_ref || return 1
  kr_init || return 1
  f="$KR_TMP/redaction.out"
  env -i PATH="$PATH" HOME="${HOME:-/}" LC_ALL=C bash "$KK_ROOT/tests/scripts/test-tf-redact-random-ids.sh" > "$f" 2>&1 || rc=$?
  for l in "${KK_REDACTION_LABELS[@]}"; do
    grep -Eq "^\[ok\] .*${l}" "$f" 2>/dev/null || miss="${miss:+$miss }${l}"
  done
  if [[ "$rc" != 0 || -n "$miss" ]]; then
    kr_refuse redaction_coverage_unconfirmed "the redaction suite exited ${rc}; missing row labels: ${miss:-none}; nothing was written"
    return 1
  fi
  kr_out redaction_ok true
  kk_say "key-rotate check redaction_coverage=true (suite exit 0; labels: ${KK_REDACTION_LABELS[*]})"
}

# ---------------------------------------------------------------------------------------------------------------------------
# GUARD
kk_cmd_guard() {
  local mode="${INPUT_MODE:-}" key="${INPUT_KEY:-}"
  kr_out go false
  kk_chk_ref || return 1
  kk_valid_inputs "$mode" "$key" || return 1
  kk_chk_actors || return 1
  KK_GUARD_MODE="$mode"
  kr_init || return 1
  kr_out mode "$mode"; kr_out key "$key"
  if [[ "$mode" == rotate ]]; then
    kk_check run_attempt_is_1 kr_chk_attempt || return 1
    kk_check confirm_ok kr_chk_confirm || return 1
    kk_check quiet_window_attested kr_chk_quiet || return 1
    kk_check key_rotatable kk_chk_egress || return 1
    kk_check approval_environment_bound kk_chk_approval || return 1
    kk_check webhook_patch_ready kk_chk_webhook_ready || return 1
  fi
  kk_check credentials_present kk_chk_gh || { kk_guard_report; return 1; }
  [[ "$key" == github_webhook_secret ]] && { kk_check owner_step_clear kk_chk_owner_step || { kk_guard_report; return 1; }; }
  if [[ "$key" == kb_drift_ingest_signing_key ]]; then
    kk_check kb_drift_window_clear kk_chk_kb_window || { kk_guard_report; return 1; }
    kk_check kb_drift_walker_clear kk_chk_walker || { kk_guard_report; return 1; }
  fi
  kk_check no_run_in_flight kk_chk_inflight || { kk_guard_report; return 1; }
  kk_check no_earlier_run kk_chk_lower_run || { kk_guard_report; return 1; }
  kk_guard_report
  kr_out guard_epoch "$(kr_now)"
  kr_out run_apply true
  if [[ "$mode" == rotate ]]; then kr_out run_redeploy true; else kr_out run_redeploy false; fi
  kr_out go true
  kr_ok guard_ok "mode=${mode} key=${key} (the guard wrote nothing)"
}

# ---------------------------------------------------------------------------------------------------------------------------
# APPLY
# kk_copy_state <project> <config> <name>: prints `present <sha256>`, `absent` or `unknown`. Value-silent: the key exists only on the
# pipe into sha256sum. `absent` ONLY when the name listing succeeded, was non-empty and lacks the name (anchored on whole names, so a
# superset name such as KB_DRIFT_INGEST_SIGNING_KEY_PREVIOUS reads as absent). An empty or failed listing, a failed read and the empty
# string's hash are all `unknown`. Mirrors the sourced kr_name_state, which is Inngest-specific and is not called.
kk_copy_state() {
  local names h
  names="$(DOPPLER_TOKEN="${DOPPLER_TOKEN_TF:-}" doppler secrets --only-names -p "$1" -c "$2" 2>/dev/null)" || { printf 'unknown'; return 0; }
  [[ -n "$names" ]] || { printf 'unknown'; return 0; }
  if ! grep -Eq "(^|[^A-Za-z0-9_])${3}([^A-Za-z0-9_]|\$)" <<<"$names"; then printf 'absent'; return 0; fi
  h="$(DOPPLER_TOKEN="${DOPPLER_TOKEN_TF:-}" doppler secrets get "$3" --plain -p "$1" -c "$2" 2>/dev/null | sha256sum | cut -c1-64)" || { printf 'unknown'; return 0; }
  [[ "$h" =~ ^[0-9a-f]{64}$ && "$h" != "$KR_EMPTY_SHA" ]] || { printf 'unknown'; return 0; }
  printf 'present %s' "$h"
}

kk_load_copies() { # key -> KK_CP (the copy rows of this key)
  local row
  KK_CP=()
  for row in "${KK_COPIES[@]}"; do [[ "${row%%|*}" == "$1" ]] && KK_CP+=("$row"); done
}

kk_pre_state() {
  local i s np=0 na=0 nu=0 p c nm
  KK_PRE_ST=(); KK_PRE_H=()
  for i in "${!KK_CP[@]}"; do
    IFS='|' read -r _ p c nm _ <<<"${KK_CP[i]}"
    s="$(kk_copy_state "$p" "$c" "$nm")"
    case "$s" in
      absent) KK_PRE_ST[i]=absent; KK_PRE_H[i]=""; na=$((na + 1)) ;;
      "present "*) KK_PRE_ST[i]=present; KK_PRE_H[i]="${s#present }"; np=$((np + 1)) ;;
      *) KK_PRE_ST[i]=unknown; KK_PRE_H[i]=""; nu=$((nu + 1)) ;;
    esac
    kk_say "pre-state copy ${c}: ${KK_PRE_ST[i]}"
  done
  if [[ "$nu" != 0 ]]; then kr_refuse copy_unreadable "a copy of the key could not be read value-silently (empty or failed listing, failed read or an empty value); nothing was written"; return 1; fi
  if [[ "$np" != 0 && "$na" != 0 ]]; then
    kr_refuse partial_absent_state "some copies of the key are present and some absent (an interrupted earlier apply). URGENT, not auto-repaired: do not restart anything; run the recovery rotate under a fresh confirm"
    return 1
  fi
  KK_ABSENT_ALL=false
  [[ "$np" == 0 ]] && KK_ABSENT_ALL=true
  return 0
}

# kk_want <key>: the unioned want (phases A and B) with the per-row flags the gate needs.
kk_want() {
  local base absent="{}" repl i p c nm addr
  base="$(jq -cs 'add' <(kr_gate_want A "$1") <(kr_gate_want B "$1"))" || return 1
  repl="$( { kr_gate_replaces A "$1"; kr_gate_replaces B "$1"; } | sed -e 's/^-replace=//' | jq -R -cs 'split("\n") | map(select(length > 0))')"
  for i in "${!KK_CP[@]}"; do
    IFS='|' read -r _ p c nm addr <<<"${KK_CP[i]}"
    absent="$(jq -c --arg a "$addr" --argjson v "$([[ "${KK_PRE_ST[i]}" == absent ]] && echo true || echo false)" '. + {($a): $v}' <<<"$absent")"
  done
  jq -c --argjson absent "$absent" --argjson repl "$repl" --argjson all "$KK_ABSENT_ALL" \
    'map(. + {replace: (.address as $a | $repl | index($a) != null), recover: (if .recovery then ($absent[.address] // false) else $all end)})' <<<"$base"
}

# kk_gate <key> <projection-file> <want>
kk_gate() {
  local key="$1" proj="$2" want="$3" n w why lines
  if jq -e --argjson want "$want" "$KK_GATE_JQ" "$proj" >/dev/null 2>&1; then return 0; fi
  if jq -e '[.[] | select(.actions == ["delete","create"] and .action_reason != "replace_by_request")] | length > 0' "$proj" >/dev/null 2>&1; then
    kr_refuse replace_not_requested "a replace was planned for a reason other than the requested -replace (for example a tainted resource); nothing was applied"
    return 1
  fi
  n="$(jq 'length' "$proj" 2>/dev/null)" || n="?"
  w="$(jq 'length' <<<"$want" 2>/dev/null)" || w="?"
  if [[ ! "$n" =~ ^[0-9]+$ ]]; then why="plan_unparseable"; elif [[ "$n" != "$w" ]]; then why="change_count_${n}_want_${w}"; else why="address_or_action_outside_the_table"; fi
  lines="$(jq -r --argjson want "$want" '
      . as $c | ([$c[] | . as $x | select(any($want[]; .address == $x.address and ($x.actions == .actions or (.recover and $x.actions == ["create"] and $x.before_null))) | not)
          | "\(.address) \(.actions | join(","))"] | .[:5] | join("; ")) as $off
      | ([$want[] | .address as $a | select(any($c[]; .address == $a) | not) | .address] | .[:3] | join("; ")) as $miss
      | "offending: \($off) | missing: \($miss)"' "$proj" 2>/dev/null | tr -cd 'A-Za-z0-9_.,;:|[] -' | cut -c1-380)" || lines=""
  KR_SCRUB_CAP=420 kr_refuse plan_gate_refused "gate refused (${why}); ${lines:-no detail}; nothing was applied (${key} wants $(jq 'length' <<<"$want" 2>/dev/null) rows)"
  return 1
}

# kk_gate_plan <key> <name>: plan, show, PROJECT, delete the full JSON, gate. On success $KR_TMP/tfplan-<name> is the saved plan.
kk_gate_plan() {
  local key="$1" name="$2" rc=0 want proj
  local -a targets repls
  mapfile -t targets < <(kr_gate_targets A "$key"; kr_gate_targets B "$key")
  mapfile -t repls < <(kr_gate_replaces A "$key"; kr_gate_replaces B "$key")
  kr_tf "plan-${name}" plan -no-color -input=false -out="$KR_TMP/tfplan-${name}" -var="ssh_key_path=${KR_TMP}/ci_ssh_key.pub" \
    "${targets[@]}" "${repls[@]}" || rc=$?
  if [[ "$rc" != 0 ]]; then kr_refuse terraform_failed "the plan step exited ${rc}; its output stays on the runner (it carries key bytes)"; return 1; fi
  rc=0
  kr_tf "show-${name}" show -json "$KR_TMP/tfplan-${name}" || rc=$?
  if [[ "$rc" != 0 ]]; then kr_refuse terraform_failed "the plan-to-JSON step exited ${rc}; its output stays on the runner (it carries key bytes)"; return 1; fi
  proj="$KR_TMP/proj-${name}.json"
  ( umask 077; jq -c "$KK_PROJECT_JQ" "$KR_TMP/tf-show-${name}.out" > "$proj" 2>/dev/null ) || rc=$?
  rm -f -- "$KR_TMP/tf-show-${name}.out" "$KR_TMP/tf-show-${name}.err" "$KR_TMP/tf-plan-${name}.out" "$KR_TMP/tf-plan-${name}.err"
  if [[ "$rc" != 0 || ! -s "$proj" ]] || ! jq -e 'type == "array"' "$proj" >/dev/null 2>&1; then
    kr_refuse terraform_failed "the plan projection failed or was empty; the full plan JSON was deleted"
    return 1
  fi
  want="$(kk_want "$key")" || { kr_refuse internal_error "the gate table could not be built for this key"; return 1; }
  kk_gate "$key" "$proj" "$want"
}

kk_chk_stale() { # authorization_stale: the confirm date still today, and the guard-to-apply gap bounded
  local ge="${EFF_GUARD_EPOCH:-}" now
  now="$(kr_now)"
  if [[ ! "$ge" =~ ^[0-9]+$ ]] || (( now - ge > KK_AUTH_MAX_AGE_S )) || [[ "$(kk_date "$now")" != "$(kk_date "$ge")" ]]; then
    kr_refuse authorization_stale "the guard's go is older than $((KK_AUTH_MAX_AGE_S / 60)) minutes or the UTC date rolled; re-dispatch under a fresh confirm; nothing was written"
    return 1
  fi
}

kk_require_attempt() { # <pre|post>
  kr_chk_attempt && return 0
  kr_refuse "$KR_CHECK_TOKEN" "$KR_CHECK_DETAIL; nothing was written"
  return 1
}

kk_settled() {
  local s
  for s in "${KK_POST_ST[@]}"; do [[ "$s" == present-changed ]] || return 1; done
  return 0
}

# kk_post_state: classify EVERY copy (present-unchanged, present-changed, absent, unknown). Retries up to KK_RETRIES times
# KK_RETRY_SLEEP_S apart: Doppler reads can lag the write.
kk_post_state() {
  local try i s h p c nm
  for ((try = 1; try <= KK_RETRIES; try++)); do
    KK_POST_ST=(); KK_POST_H=()
    for i in "${!KK_CP[@]}"; do
      IFS='|' read -r _ p c nm _ <<<"${KK_CP[i]}"
      s="$(kk_copy_state "$p" "$c" "$nm")"
      case "$s" in
        absent) KK_POST_ST[i]=absent; KK_POST_H[i]="" ;;
        "present "*)
          h="${s#present }"; KK_POST_H[i]="$h"
          if [[ "${KK_PRE_ST[i]}" == present && "$h" == "${KK_PRE_H[i]}" ]]; then KK_POST_ST[i]=present-unchanged; else KK_POST_ST[i]=present-changed; fi ;;
        *) KK_POST_ST[i]=unknown; KK_POST_H[i]="" ;;
      esac
    done
    kk_settled && return 0
    (( try < KK_RETRIES )) && kr_sleep "$KK_RETRY_SLEEP_S"
  done
  return 0
}

kk_print_post() {
  local i c
  for i in "${!KK_CP[@]}"; do
    IFS='|' read -r _ _ c _ _ <<<"${KK_CP[i]}"
    kk_say "post-state copy ${c}: ${KK_POST_ST[i]}"
  done
}

kk_has_post() { local s; for s in "${KK_POST_ST[@]}"; do [[ "$s" == "$1" ]] && return 0; done; return 1; }

kk_cmd_apply() {
  local mode="${EFF_MODE:-}" key="${EFF_KEY:-}" rc=0
  kk_valid_inputs "$mode" "$key" || return 1
  kr_init || return 1
  if [[ "$mode" == rotate ]]; then
    kk_require_attempt || return 1
    kk_chk_egress "$key" || { kr_refuse "$KR_CHECK_TOKEN" "${KR_CHECK_DETAIL}; nothing was written"; return 1; }
    kk_chk_stale || return 1
    kk_recheck "$key" "$KK_KB_BUDGET_APPLY_S" || { kr_refuse "$KR_CHECK_TOKEN" "${KR_CHECK_DETAIL}; nothing was written"; return 1; }
  fi
  kr_tf_prepare || return 1
  kk_load_copies "$key"
  kk_pre_state || return 1
  kk_gate_plan "$key" p || return 1
  if [[ "$mode" == plan ]]; then
    kr_summary "gate rows: $(kr_gate_rows A "$key" | cut -d'|' -f3,5 | tr '\n' ' ')$(kr_gate_rows B "$key" | cut -d'|' -f3,5 | tr '\n' ' ')"
    kr_ok plan_ok "the plan gate passed for key=${key} (${#KK_CP[@]} copies readable, absent_all=${KK_ABSENT_ALL}); nothing was applied"
    return 0
  fi
  # the last read before the write: the facts above have aged by up to the init and plan time
  kk_chk_stale || return 1
  kk_recheck "$key" "$KK_KB_BUDGET_PREAPPLY_S" || { kr_refuse "$KR_CHECK_TOKEN" "${KR_CHECK_DETAIL}; nothing was written"; return 1; }
  kr_out write_started true
  KR_TF_T="$KR_TF_APPLY_S" kr_tf apply apply -no-color -input=false "$KR_TMP/tfplan-p" || rc=$?
  kk_post_state
  kk_print_post
  if [[ "$rc" != 0 ]]; then
    kr_post_write_failure apply_failed "the apply exited ${rc}; see the per-copy states above; its output stays on the runner" "The apply failed part-way."
    return 1
  fi
  if kk_has_post unknown; then kr_post_write_failure post_hash_unreadable "a copy could not be read back after the apply" "The apply finished but a copy cannot be read."; return 1; fi
  if kk_has_post absent; then kr_post_write_failure partial_absent_state "a copy is absent after the apply" "A copy of the key is absent after the apply."; return 1; fi
  if kk_has_post present-unchanged; then kr_post_write_failure value_unchanged "a copy did not change (new_differs_from_prior=false)" "The apply reported success but a copy did not change."; return 1; fi
  if [[ "${#KK_POST_H[@]}" -gt 1 && "$(printf '%s\n' "${KK_POST_H[@]}" | sort -u | wc -l | tr -d ' ')" != 1 ]]; then
    kr_post_write_failure copies_differ "copies_equal=false after the apply" "The apply finished but the copies of the key are not equal."; return 1
  fi
  kk_say "key-rotate: apply done for key=${key}; every copy changed and the copies are equal; the redeploy leg is next"
  [[ "$KK_ABSENT_ALL" == true ]] && { kk_say "key-rotate: recovery path - the old value survives only in running containers; the redeploy is mandatory and urgent"; }
  return 0
}

# ---------------------------------------------------------------------------------------------------------------------------
# REDEPLOY (three steps of the redeploy job)
kk_redeploy_refuse() { # <reason-token> <detail>
  kr_post_write_failure rotated_redeploy_failed "reason=${1}: ${2}; the redeploy was not dispatched" "The redeploy leg did not run: the apply landed the new value."
}

kk_redeploy_recheck() {
  [[ "${EFF_MODE:-}" == rotate ]] || { kr_refuse internal_error "redeploy runs for rotate only"; return 1; }
  kk_valid_inputs rotate "${EFF_KEY:-}" || return 1
  kr_init || return 1
  if ! kr_chk_attempt; then kk_redeploy_refuse "$KR_CHECK_TOKEN" "$KR_CHECK_DETAIL"; return 1; fi
  if ! kk_recheck "$EFF_KEY" "$KK_KB_BUDGET_REDEPLOY_S"; then kk_redeploy_refuse "$KR_CHECK_TOKEN" "$KR_CHECK_DETAIL"; return 1; fi
  kk_say "key-rotate: redeploy re-checks passed"
}

kk_redeploy_track() {
  [[ "${WEB_HOST_PRIVATE_IPS:-}" =~ ^[0-9.]+(,[0-9.]+)*$ ]] \
    || { kk_say "WEB_HOST_PRIVATE_IPS is unset or malformed; a single-host redeploy would leave the fleet mixed. Nothing was dispatched."; return 1; }
  if ! WEB_HOST_PRIVATE_IPS="$WEB_HOST_PRIVATE_IPS" REDEPLOY_TIMEOUT_S="$KR_REDEPLOY_S" bash "$KR_TRACK"; then
    kk_say "the fleet redeploy (track.sh) did not confirm a clean swap on every host; its verdict is in the output above"
    return 1
  fi
}

kk_redeploy_verdict() { # the last step: exports a verdict on EVERY path
  local key="${EFF_KEY:-}"
  kk_valid_inputs rotate "$key" || return 1
  kr_init || return 1
  if [[ "${EFF_RECHECK_OUTCOME:-}" != success ]]; then
    kr_post_write_failure rotated_redeploy_failed "the redeploy re-checks did not pass (outcome ${EFF_RECHECK_OUTCOME:-unknown})" "The redeploy leg did not run."; return 1
  fi
  if [[ "${EFF_TRACK_OUTCOME:-}" != success ]]; then
    kr_post_write_failure rotated_redeploy_failed "the fleet redeploy did not confirm (outcome ${EFF_TRACK_OUTCOME:-unknown})" "The redeploy did not confirm: the old containers keep the old value."; return 1
  fi
  if [[ "$key" == github_webhook_secret ]]; then
    kr_post_write_failure owner_step_pending "the redeploy was confirmed by track.sh; the owner step is the only thing left" "The rotation landed and the fleet redeploy was confirmed."; return 1
  fi
  kr_ok rotate_ok "key=${key}; the fleet redeploy was confirmed by track.sh (this does not prove each consumer picked up the value)"
}

kk_cmd_redeploy() {
  case "${1:-}" in
    recheck) kk_redeploy_recheck ;;
    track) kk_redeploy_track ;;
    verdict) kk_redeploy_verdict ;;
    *) printf 'usage: %s redeploy recheck|track|verdict\n' "${0##*/}" >&2; return 64 ;;
  esac
}

# ---------------------------------------------------------------------------------------------------------------------------
# NOTIFY: the ONLY job with issues:write. Files the one action-required issue after a write that did not end green, and closes a key's
# earlier open key-rotate issues on rotate_ok (never the owner_step_pending ones, which the owner closes after the update).
kk_norm_result() { case "${1:-}" in success|failure|cancelled|skipped) printf '%s' "$1" ;; *) printf 'unknown' ;; esac; }

kk_prewrite_token() { # tokens an apply can end with BEFORE the write: a refusal files nothing
  case "$1" in
    rerun_refused|authorization_stale|credential_absent|copy_unreadable|plan_gate_refused|replace_not_requested|terraform_failed|run_in_flight|run_list_unreadable|kb_drift_cron_window|kb_drift_walker_in_flight|inputs_invalid) return 0 ;;
  esac
  return 1
}

kk_close_earlier() { # <key>
  local repo="${GITHUB_REPOSITORY:-}" list num
  list="$(gh issue list --repo "$repo" --label action-required --state open --limit "$KK_ISSUE_LIMIT" --json number,title 2>/dev/null)" \
    || { kk_say "could not list earlier key-rotate issues; none closed"; return 0; }
  while IFS= read -r num; do
    [[ "$num" =~ ^[0-9]+$ ]] || continue
    gh issue close "$num" --repo "$repo" --comment "Superseded by a confirmed rotation of ${1} (run ${GITHUB_RUN_ID:-unknown})." >/dev/null 2>&1 || true
  done < <(jq -r --arg k "$1" '.[] | select((.title | test("^key-rotate " + $k + " [a-z_]+ \\(run [0-9]+\\)$")) and ((.title | startswith("key-rotate " + $k + " owner_step_pending ")) | not)) | .number' <<<"$list" 2>/dev/null)
  return 0
}

kr_cmd_notify() {
  local mode="${EFF_MODE:-}" key="${EFF_KEY:-}" ra rr av rv ws wrote=0 tok what
  [[ "$mode" == rotate ]] || { kk_say "key-rotate: notify has nothing to report for mode '${mode:-}'"; return 0; }
  kk_valid_inputs rotate "$key" || return 1
  ra="$(kk_norm_result "${EFF_RESULT_APPLY:-}")"; rr="$(kk_norm_result "${EFF_RESULT_REDEPLOY:-}")"
  av="${EFF_APPLY_VERDICT:-}"; rv="${EFF_REDEPLOY_VERDICT:-}"; ws="${EFF_WRITE_STARTED:-}"
  kr_init || return 1
  if [[ "$rr" == success && "$rv" == rotate_ok ]]; then kk_close_earlier "$key"; return 0; fi
  [[ "$ra" == skipped ]] && { kk_say "key-rotate: the apply job was skipped; nothing was written"; return 0; }
  case "$ra" in success|cancelled|unknown) wrote=1 ;; esac
  [[ "$ws" == true ]] && wrote=1
  if [[ "$ra" == failure && "$wrote" == 0 ]]; then
    if [[ "$av" == partial_absent_state ]]; then wrote=1
    elif [[ -z "$av" ]] || ! kk_prewrite_token "$av"; then wrote=1; fi
  fi
  if [[ "$wrote" == 0 ]]; then kk_say "key-rotate: no write happened (apply=${ra}); nothing to report"; return 0; fi
  if [[ "$rr" == failure || "$rr" == cancelled ]] && kr_token_known "$rv" && [[ "$rv" != rotate_ok ]]; then tok="$rv"
  elif [[ "$ra" == failure ]] && kr_token_known "$av"; then tok="$av"
  else tok=job_cancelled; fi
  what="A job after the first write ended without a stop sentence of its own (apply=${ra} redeploy=${rr})."
  [[ "$tok" == owner_step_pending ]] && what="The rotation landed and the fleet redeploy was confirmed."
  KR_VERDICT="$tok"
  kr_file_issue "$tok" "$(kr_stop_sentence "$what" | KR_SCRUB_CAP=1400 kr_scrub)"
}

main() {
  case "${1:-}" in
    --print-contract) kr_print_contract ;;
    precondition) kk_cmd_precondition ;;
    guard) kk_cmd_guard ;;
    apply) kk_cmd_apply ;;
    redeploy) kk_cmd_redeploy "${2:-}" ;;
    notify) kr_cmd_notify ;;
    *) printf 'usage: %s --print-contract|precondition|guard|apply|redeploy recheck|track|verdict|notify\n' "${0##*/}" >&2; return 64 ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; exit $?; fi
