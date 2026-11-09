#!/usr/bin/env bash
# key-rotate.sh - the orchestration body of .github/workflows/key-rotate.yml (#11294, ADR-317; runbook key-rotation.md).
#
# Rotates ONE non-tunnel secret per dispatch (all seven keys of the table below; egress_audit_ingest_token became fully
# rotatable when the no-SSH vector restart lever and the Terraform PREVIOUS secret landed, #11920) by a targeted
# Terraform -replace, then redeploys the web fleet canary-then-prod. It SOURCES scripts/inngest-key-rotate.sh
# (ADR-307, untouched) and overrides what differs
# (CTO F1): the gate table, the in-flight list, the verdict tokens and the same-name redefinitions further down. Bash binds late,
# so only a redefinition BY THE SAME NAME intercepts the sourced callers (kr_post_write_failure calls kr_refuse and kr_post_write_stop).
#
#   key-rotate.sh precondition        credential-free sanity step: the ref rung, then the redaction suite on the dispatched ref
#   key-rotate.sh guard               refusal ladder; outputs go/mode/key/run_apply/run_redeploy/guard_epoch (writes nothing);
#                                     kk_chk_approval is a LIVE verify of the key-rotate-approval environment's protection_rules
#   key-rotate.sh apply               re-checks, value-silent pre-state, plan, five-field projection, gate, apply, post-state
#                                     (EFF_MODE=plan: everything up to and including the gate, writes nothing). Egress apply-A
#                                     also feeds the old CURRENT into TF_VAR_egress_audit_ingest_token_previous (env only).
#   key-rotate.sh redeploy recheck|track|vector|verdict   the steps of the redeploy job; `vector` runs for egress only and,
#                                     after a settle gate confirms every roster host's deploy slot is terminal,
#                                     dispatches `restart vector _ _` over the deploy webhook, then polls the merged
#                                     deploy-status until EVERY host reports a fresh component=vector success frame
#   key-rotate.sh clear               egress only: plan+apply -replace of doppler_secret.egress_audit_ingest_token_previous
#                                     with the var default "" (PREVIOUS cleared) once the vector leg is green
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
  kr_inflight_check kr_chk_attempt kr_chk_quiet kr_summary kr_out kr_token_known kr_now kr_sleep kr_post_write_failure)
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
  approval_environment_unprotected webhook_patch_not_ready owner_step_open
  kb_drift_cron_window kb_drift_walker_in_flight run_in_flight run_list_unreadable redaction_coverage_unconfirmed credential_absent
  authorization_stale copy_unreadable partial_absent_state plan_ok plan_gate_refused replace_not_requested terraform_failed
  apply_failed post_hash_unreadable value_unchanged copies_differ rotated_redeploy_failed vector_restarted previous_not_cleared
  previous_not_staged owner_step_pending issue_unfiled
  rotate_ok job_cancelled internal_error
)
KR_INFLIGHT_WORKFLOWS=(apply-web-platform-infra.yml apply-deploy-pipeline-fix.yml web-platform-release.yml inngest-key-rotate.yml inngest-link-flip.yml cutover-inngest.yml deploy-inngest-image.yml)

# THE GATE TABLE (Guard 1). One table feeds the -target list, the -replace list and the jq allowlist. Fields:
# phase|key|address|flag|actions. flag=replace: targeted AND replaced. flag=target: targeted only; the address changes in place
# because the replaced random_id feeds it. The four inngest_* secrets and egress_audit_ingest_token_previous carry
# lifecycle.ignore_changes=[value], so they are replaced
# with their random_id (replace-both) or written by -replace with the TF_VAR feed (PREVIOUS); the other three have no ignore_changes,
# so a replaced random_id updates them in place and
# there is no absent-secret window (CTO ruling 2026-11-02; terraform-target-parity.test.ts derives the flag from the HCL).
# The egress PREVIOUS row (#11920) sits in the same apply-A: -replace writes the old CURRENT (staged via the
# PREVIOUS TF variable, env only) so the route accepts CURRENT+PREVIOUS during the vector-restart window.
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
  'B|egress_audit_ingest_token|doppler_secret.egress_audit_ingest_token_previous|replace|delete,create'
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

# Authorization posture (CTO H2). The environment infra-privileged has ZERO required reviewers by design (the unattended
# apply-on-merge needs it), so the typed confirm is derivable from public inputs: a fat-finger guard, not an authorization.
# The authorization is now TWO mechanisms: both actors must be in this committed, exact-match allowlist (the CODEOWNERS
# owner), AND every rotate dispatch waits at the reviewer-gated `key-rotate-approval` environment in front of the first
# production-mutating job (#11923). kk_chk_approval below is the LIVE verify of that environment's protection (a
# referenced-but-absent environment auto-creates UNPROTECTED, the #6780 class): an unreadable read, a missing
# required_reviewers/branch_policy type, an EMPTY reviewer list or a branch policy admitting anything but
# refs/heads/main refuses approval_environment_unprotected. An owner PAT can still dispatch, but the
# reviewer's approval remains a distinct human act (residual, bounded by the gate).
KK_OWNER_LOGINS=(deruelle)
KK_APPROVAL_ENV_BOUND=true
KK_AUTH_MAX_AGE_S=3600
KK_RETRIES=3
KK_RETRY_SLEEP_S=20
KK_MAIN_REF="refs/heads/main"
KK_WALKER_WORKFLOW="kb-drift-walker.yml"
KK_OWN_WORKFLOW="key-rotate.yml"
KK_ISSUE_LIMIT=1000

# BUDGET TABLE (seconds): only the values that differ from the sourced route. The suite pins the workflow's timeout-minutes to it as
# plain literals (guard 15/25, approve 1/11, apply 40/50, redeploy 85/120, clear 40/50, notify 5/15). The G3 window constants derive from these.
KK_APPLY_STEP_S=$((KR_TF_INIT_S + KR_TF_PLAN_S + KR_TF_APPLY_S + KR_STEP_SLACK_S))
KK_APPLY_JOB_S=$((KK_APPLY_STEP_S + KR_JOB_SLACK_S))
KK_RECHECK_STEP_S=600
# The approve job stamps approval_epoch after the reviewer click (the environment wait does not count against the job bound).
KK_APPROVE_STEP_S=60
KK_APPROVE_JOB_S=$((KK_APPROVE_STEP_S + KR_JOB_SLACK_S))
# The vector leg (egress only): dispatch `restart vector _ _` over the deploy webhook, then poll the merged deploy-status
# until every host reports a fresh component=vector success frame. A vector restart is seconds; the bound covers frame
# propagation across the fan-out (the per-peer read itself is bounded at 3 s by cat-deploy-state.sh).
KK_VECTOR_S=600
KK_VECTOR_POLL_S=15
# The pre-dispatch settle gate (#12299): the merged status can still show a peer's slot running (its own deploy holds
# /var/lock/ci-deploy.lock) or a transient lock_contention when track declares green; a restart dispatched into that
# window is silently lost (see kk_redeploy_vector). The 90 s gate plus the 600 s green poll stays under the 15-minute
# vector step bound.
KK_SETTLE_S=90
KK_SETTLE_POLL_S=10
KK_VECTOR_STEP_S=$((KK_VECTOR_S + KR_STEP_SLACK_S))
# The redeploy JOB holds five steps (checkout 2 + Re-checks 10 + track 85 + vector 15 + Verdict 5 = 117 min), so its bound
# is the track step plus the sourced slack plus the Re-checks step plus the vector step: 120 min.
KK_REDEPLOY_JOB_S=$((KR_REDEPLOY_STEP_S + KR_JOB_SLACK_S + KK_RECHECK_STEP_S + KK_VECTOR_STEP_S))
# The clear job (egress only): init + one plan + one apply for the single PREVIOUS row, same shape as the apply job.
KK_CLEAR_STEP_S=$((KR_TF_INIT_S + KR_TF_PLAN_S + KR_TF_APPLY_S + KR_STEP_SLACK_S))
KK_CLEAR_JOB_S=$((KK_CLEAR_STEP_S + KR_JOB_SLACK_S))
# kb_drift window (CTO G3): refuse when [now, now + the remaining budget] intersects [03:00, 03:30] UTC.
KK_KB_WIN_START_S=10800
KK_KB_WIN_LEN_S=1800
# The Re-checks step (up to 10 minutes, 480 s of it the R1 wait) sits between the apply and the track step, so it is part of the
# budget: 40 min apply + 10 min re-checks + 85 min track = 8100 s, and the first unsafe start is about 00:45 UTC.
KK_KB_BUDGET_APPLY_S=$((KK_APPLY_STEP_S + KK_RECHECK_STEP_S + KR_REDEPLOY_STEP_S))
KK_KB_BUDGET_PREAPPLY_S=$((KR_TF_APPLY_S + KR_STEP_SLACK_S + KK_RECHECK_STEP_S + KR_REDEPLOY_STEP_S))
# R3: `terraform show` is capped (the sourced kr_tf default is the plan bound); the write is refused when the time left in the apply
# step is below the apply bound plus this margin. Doppler reads are capped too.
KK_TF_SHOW_S=120
KK_DOPPLER_READ_S=60
# The margin is a literal: the apply kill-after (30 s) plus one post-state round. It does NOT cover the full post-state worst case
# (KK_RETRIES x copies x 2 x KK_DOPPLER_READ_S + (KK_RETRIES - 1) x KK_RETRY_SLEEP_S = 400 s for one copy, 760 s for the two
# kb_drift copies), because the apply step has only KR_STEP_SLACK_S of slack in total. A step kill after the write lands as the notify
# job_cancelled with write_started=true (safe, but the per-copy states are lost). The suite pins the derivation and the literal.
KK_APPLY_MARGIN_S=240
# R1: after a landed write the redeploy leg never refuses on staleness, the kb window or quiet_window; it waits read-only for a
# transient rung (in-flight run, earlier run, walker) to clear, inside the Re-checks step's 10-minute timeout.
KK_REDEPLOY_WAIT_S=480
KK_REDEPLOY_POLL_S=30
# N6: every `gh run list` of the poll is capped; a rung re-poll is at most five statuses, so one poll iteration is bounded by
# KK_REDEPLOY_ITER_S and WAIT + ITER fits the 10-minute Re-checks step (the suite pins it).
KK_GH_POLL_S=20
KK_REDEPLOY_ITER_S=$((5 * KK_GH_POLL_S))
# N3: workflows whose deploy job is a member of the `web-1-swap` concurrency group (web-1-swap-concurrency-parity.test.sh). While the
# redeploy job holds the group their deploy jobs are queued behind OUR hold and cannot finish, so in redeploy mode their runs are not
# blockers (the group serializes the swap anyway). apply-web-platform-infra.yml is NOT listed: its routine apply job is not a member.
KK_SWAP_MEMBER_WORKFLOWS=(web-platform-release.yml apply-deploy-pipeline-fix.yml)

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
KK_LAST_DETAIL=""
KK_GH_BIN=gh
KK_RECHECK_RUNG=""
KK_STEP_START=0
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

# kr_out: an allowlist of output names AND of the value each name may carry (a 64-hex hash, a 43-char key id or a copy state never
# matches any of these shapes), so nothing but a fixed vocabulary can cross a step or job boundary.
kr_out() {
  local k ok=1
  case "$1" in
    verdict) kr_token_known "$2" || return 0 ;;
    go|run_apply|run_redeploy|redaction_ok) [[ "$2" == true || "$2" == false ]] || return 0 ;;
    mode) [[ "$2" == plan || "$2" == rotate ]] || return 0 ;;
    key) for k in "${KK_KEYS[@]}"; do [[ "$2" == "$k" ]] && ok=0; done; [[ "$ok" == 0 ]] || return 0 ;;
    guard_epoch) [[ "$2" =~ ^[0-9]{10}$ ]] || return 0 ;;
    write_started) [[ "$2" == true || -z "$2" ]] || return 0 ;;
    *) return 0 ;;
  esac
  [[ -n "${GITHUB_OUTPUT:-}" ]] && printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT" 2>/dev/null
  return 0
}

kr_refuse() {
  local t="$1" d
  kr_token_known "$t" || t="internal_error"
  d="$(printf '%s' "${2:-}" | kr_scrub)"
  KR_VERDICT="$t"
  KK_LAST_DETAIL="$d"
  printf '::error::key-rotate verdict=%s %s\n' "$t" "$d" >&2
  kr_summary "- key-rotate verdict=${t}: ${d}"
  kr_out verdict "$t"
  return 0
}

# kr_ok <token> <detail> [<name>=<fixed-word>]: the optional third argument is a fixed-vocabulary field appended AFTER the scrub (a
# 49-character verdict token would otherwise be redacted as a token-shaped run).
kr_ok() {
  local t="$1" d
  kr_token_known "$t" || t="internal_error"
  d="$(printf '%s' "${2:-}" | kr_scrub)"
  [[ "${3:-}" =~ ^[a-z_]+=[a-z_]+$ ]] && d="${d} ${3}"
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

# kr_converge_cmd: the exact re-dispatch command the stop sentence and the issue carry (it runs under a fresh, per-command, in-session owner go naming the exact command - an agent may dispatch it under that go; the key-rotate-approval reviewer click is never delegated).
kr_converge_cmd() {
  local k="${EFF_KEY:-}" v ok=1 extra=""
  for v in "${KK_KEYS[@]}"; do [[ "$k" == "$v" ]] && ok=0; done
  [[ "$ok" == 0 ]] || k="<key>"
  [[ "$k" == github_webhook_secret ]] && extra=" -f webhook_patch_ready=true"
  printf 'gh workflow run %s -f mode=rotate -f key=%s -f confirm=ROTATE-%s-YYYY-MM-DD -f quiet_window=true%s' \
    "$KK_OWN_WORKFLOW" "$k" "$(printf '%s' "$k" | tr '[:lower:]' '[:upper:]')" "$extra"
}

# kk_state_row <token>: the three facts every stop sentence states (Doppler, Terraform state, running containers) and the next safe action.
kk_state_row() {
  case "$1:${EFF_KEY:-${INPUT_KEY:-}}" in
    partial_absent_state:kb_drift_ingest_signing_key) printf 'Doppler: some copies present, some absent (or all absent). Terraform state: partial. Running containers: old. URGENT, not auto-repaired: do not restart anything. If one copy is still present, recreate the missing copy in Doppler (or accept the mixed state) and then rotate; a rotate refuses identically until then. If every copy is absent, a recovery rotate is the way out.'; return 0 ;;
    partial_absent_state:*) printf 'Doppler: the copy is absent. Terraform state: partial. Running containers: old. URGENT, not auto-repaired: do not restart anything; run the recovery rotate now (every copy absent is the shape a rotate recovers).'; return 0 ;;
    apply_failed:egress_audit_ingest_token) printf 'Doppler: per-copy classification printed in the run log; the ingest route still accepts the old token through PREVIOUS until the clear runs. Terraform state: possibly partial (a replace may have destroyed and not created). Running containers: old. Next safe action: a fresh rotate; if the CURRENT copy is absent it is urgent.'; return 0 ;;
  esac
  case "$1" in
    apply_failed) printf 'Doppler: per-copy classification printed in the run log. Terraform state: possibly partial (a replace may have destroyed and not created). Running containers: old. Next safe action: a fresh rotate; if any copy is absent it is urgent, because a container restart now starts without the secret.' ;;
    previous_not_cleared) printf 'Doppler: CURRENT is new; EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS is still set (the old token stays accepted - the lossless direction). Terraform state: PREVIOUS populated. Running containers: new. Next safe action: re-dispatch the rotate (the clear leg re-runs); if it refuses again, clear EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS by hand in Doppler soleur/prd.' ;;
    previous_not_staged) printf 'Doppler: CURRENT is new; EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS is absent or empty (the old token is accepted NOWHERE - the LOSSY direction: every host still on the old env is rejected). Terraform state: PREVIOUS empty. Running containers: old. Next safe action: redeploy the web fleet NOW so hosts pick up the new CURRENT; if old-env hosts must be served first, set EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS in Doppler soleur/prd to the prior token value (recoverable from a running host env or the Doppler audit log - drift-free under ignore_changes), then re-dispatch the rotate to land the clear.' ;;
    post_hash_unreadable) printf 'Doppler: unknown. Terraform state: new. Running containers: old. Next safe action: a fresh rotate; the value is unknown, not unchanged.' ;;
    value_unchanged) printf 'Doppler: OLD value. Terraform state: new random_id. Running containers: old. Next safe action: stop and read the ADR item on the ignore_changes premise before re-dispatching; a repeat means the premise is false.' ;;
    copies_differ) printf 'Doppler: both copies present but unequal. Terraform state: new. Running containers: old. Next safe action: a fresh rotate outside the cron window.' ;;
    rotated_redeploy_failed) printf 'Doppler: new. Terraform state: new. Running containers: old, or a MIXED fleet if the canary swapped and prod did not. Next safe action: a fresh rotate.' ;;
    owner_step_pending) printf 'Doppler: new. Terraform state: new. Running containers: new. Next safe action: the single owner action below.' ;;
    *) printf 'Doppler, Terraform state and running containers: unknown. Next safe action: check the run and read the verdict before doing anything else.' ;;
  esac
}

# kk_consequence <key>: what the key's consumers see after a write that did not end green (old containers on the old value, a
# container started while a copy is absent). Neutral about timing: this text is public.
kk_consequence() {
  case "$1" in
    inngest_manual_trigger_secret_prd) printf 'Consequence: old containers answer 401 on /api/internal/* (soleur:trigger-cron) until a redeploy lands; a container started while the copy is absent answers 503 on /api/internal/*.' ;;
    inngest_manual_trigger_secret_dev) printf 'Consequence: no production container reads soleur/dev; a dev shell or server started while the copy is absent has no manual-trigger secret (503 on /api/internal/*).' ;;
    inngest_signing_key_dev|inngest_event_key_dev) printf 'Consequence: no production container reads soleur/dev; a dev server started while the copy is absent boots without the key.' ;;
    kb_drift_ingest_signing_key) printf 'Consequence: the 03:00 UTC kb-drift walker run is rejected with 401 until the copies agree and a redeploy lands; a container started while the prd copy is absent answers 500 on ingest.' ;;
    github_webhook_secret) printf 'Consequence: GitHub webhook deliveries are rejected with 401 (GitHub does not retry them) while the secrets disagree; a container started while the copy is absent answers 500 on every delivery. Do not update the GitHub App webhook secret until you have read the verdict.' ;;
    *) printf 'Consequence: depends on the key; read the verdict before restarting anything.' ;;
  esac
}

# kk_degrade <token>: the per-key consequence (neutral about the gap window: this text is public).
kk_degrade() {
  local k="${EFF_KEY:-${INPUT_KEY:-}}"
  case "$1:$k" in
    owner_step_pending:github_webhook_secret) printf 'Owner step: update the GitHub App webhook secret with the new value of GITHUB_APP_WEBHOOK_SECRET (runbook key-rotation.md, then github-app-provisioning.md Step 4), redeliver failed deliveries from the App advanced settings, then close this issue.' ;;
    rotated_redeploy_failed:github_webhook_secret) printf 'Do NOT update the GitHub App webhook secret yet; re-dispatch the rotate first.' ;;
    job_cancelled:github_webhook_secret) printf 'Check the run; do not update the GitHub App webhook secret until you have read the verdict.' ;;
    rotated_redeploy_failed:kb_drift_ingest_signing_key) printf 'Until a redeploy lands, the next 03:00 UTC kb-drift walker run is rejected.' ;;
    rotated_redeploy_failed:inngest_manual_trigger_secret_prd) printf 'Until a redeploy lands, soleur:trigger-cron and the internal routes answer 401 on hosts still on the old value.' ;;
    rotated_redeploy_failed:inngest_*_dev) printf 'No production container reads the soleur/dev keys; the production redeploy was a rehearsal of the route'"'"'s last leg.' ;;
    previous_not_staged:*) printf 'Consequence: every egress send from a host still on the old env is rejected (the old token is accepted nowhere) until the fleet redeploys onto the new CURRENT or PREVIOUS is set by hand.' ;;
    apply_failed:*|post_hash_unreadable:*|value_unchanged:*|copies_differ:*|partial_absent_state:*|job_cancelled:*) kk_consequence "$k" ;;
    *) printf 'Consequence: depends on the verdict; read it before restarting anything.' ;;
  esac
}

# kr_stop_sentence <what happened, fixed words>: the token is the verdict kr_refuse just set. This is the part that passes through
# kr_scrub; the tail (the re-dispatch command and the verdict recipe) is appended AFTER the scrub by kk_stop_tail, because the confirm
# in the command (ROTATE-<KEY>-YYYY-MM-DD) is 41 or more characters of the token class for four of the six keys and would be redacted.
kr_stop_sentence() {
  printf 'STOP: do not re-run the failed jobs. %s %s %s' \
    "$1" "$(kk_state_row "${KR_VERDICT:-internal_error}")" "$(kk_degrade "${KR_VERDICT:-internal_error}")"
}

# kk_stop_tail: fixed words, the validated key and the numeric run id only. owner_step_pending carries no re-dispatch command (the
# single owner action is above); a kb_drift partial_absent_state gets it only after the missing copy is recreated.
kk_stop_tail() {
  local k="${EFF_KEY:-}"
  case "${KR_VERDICT:-}:$k" in
    owner_step_pending:*) printf ' Read the verdict: %s' "$(kr_verdict_recipe)" ;;
    partial_absent_state:kb_drift_ingest_signing_key) printf ' Only after the missing copy is recreated, re-dispatch under a fresh, per-command, in-session owner go (an agent may dispatch it under that go; the key-rotate-approval reviewer click is never delegated): %s Read the verdict: %s' "$(kr_converge_cmd)" "$(kr_verdict_recipe)" ;;
    *) printf ' Re-dispatching is the owner'"'"'s own decision under a fresh, per-command, in-session go (an agent may dispatch it under that go; the key-rotate-approval reviewer click is never delegated): %s Read the verdict: %s' "$(kr_converge_cmd)" "$(kr_verdict_recipe)" ;;
  esac
}

# kr_post_write_stop <token> <what-happened> [kind]: the stop sentence and the step summary. Issues are filed ONLY by the notify job.
kr_post_write_stop() {
  local s
  s="$(kr_stop_sentence "$2" | KR_SCRUB_CAP=1400 kr_scrub)$(kk_stop_tail)"
  printf '::error::key-rotate %s\n' "$s" >&2
  kr_summary "STOP SENTENCE: ${s}"
  return 1
}

# kr_file_issue <token> <sentence>: the ONLY issue filer. De-duplicated on (key, token, run). The create call's own URL is
# the filing proof (GitHub's issue index lags a fresh create — the immediate re-list reported issue_unfiled while the
# issue existed, #12299); a create that returns no URL is verified by a bounded re-list on the retry cadence, and fails
# loudly when the issue is still not there (a swallowed `gh` error would leave a written rotation with no owner).
kr_file_issue() {
  local repo="${GITHUB_REPOSITORY:-}" key="${EFF_KEY:-}" run="${GITHUB_RUN_ID:-0}" title body list n num att="${GITHUB_RUN_ATTEMPT:-1}" url try
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
  num="$(jq -r --arg t "$title" '[.[] | select(.title == $t)] | .[0].number // empty' <<<"$list" 2>/dev/null)" || num=""
  if [[ "$num" =~ ^[0-9]+$ ]]; then
    # a re-run of the notify job (attempt > 1) must not add a duplicate comment to the issue the first attempt filed (R4)
    if [[ "$att" =~ ^[0-9]+$ && "$att" -gt 1 ]]; then return 0; fi
    gh issue comment "$num" --repo "$repo" --body-file "$KR_TMP/issue.md" >/dev/null 2>&1 || { kr_refuse issue_unfiled "the follow-up comment could not be posted"; return 1; }
    return 0
  fi
  url="$(gh issue create --repo "$repo" --title "$title" "${labels[@]}" --body-file "$KR_TMP/issue.md" 2>/dev/null)" || url=""
  if [[ "$url" == */issues/[0-9]* ]]; then
    kk_say "key-rotate: the action-required issue was filed (${url})"
    return 0
  fi
  # no URL: the create call failed, or its response was lost after the issue landed — a bounded re-list on the retry
  # cadence covers both without racing the index (the old single immediate re-list is what produced the false
  # issue_unfiled verdicts of #12299)
  for ((try = 1; try <= KK_RETRIES; try++)); do
    list="$(gh issue list --repo "$repo" --label action-required --state open --limit "$KK_ISSUE_LIMIT" --json number,title 2>/dev/null)" || list="[]"
    if jq -e --arg t "$title" 'any(.[]; .title == $t)' <<<"$list" >/dev/null 2>&1; then return 0; fi
    (( try < KK_RETRIES )) && kr_sleep "$KK_RETRY_SLEEP_S"
  done
  kr_refuse issue_unfiled "the action-required issue was not created (or is missing its label); the red run is the only record"
  return 1
}

# ---------------------------------------------------------------------------------------------------------------------------
# helpers
kk_date() { date -u -d "@$1" +%F; }

kk_valid_inputs() { # mode key
  case "${1:-}" in plan|rotate) ;; *) kr_refuse inputs_invalid "mode must be plan or rotate"; return 1 ;; esac
  local k
  for k in "${KK_KEYS[@]}"; do [[ "${2:-}" == "$k" ]] && return 0; done
  kr_refuse inputs_invalid "key is not one of the seven selectable keys"
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

# kk_chk_approval (CTO H2/G6, #11923): the LIVE verify of the reviewer-gated environment the rotate waits at. A
# referenced-but-absent or drifted key-rotate-approval environment auto-creates UNPROTECTED (the #6780 vacuous-gate
# class), so the workflow binding alone is not proof — every rotate reads protection_rules once, for every key (the
# approve job gates mode=rotate for all keys). Fail closed at every rung: an unreadable API read refuses, an
# environment whose protection_rules lack EITHER required_reviewers OR a branch policy refuses, a required_reviewers
# rule whose reviewer list is EMPTY refuses (type-presence alone is not protection), and a deployment branch policy
# that admits anything other than refs/heads/main refuses approval_environment_unprotected.
kk_chk_approval() {
  local out pol
  if [[ "$KK_APPROVAL_ENV_BOUND" != true ]]; then
    KR_CHECK_TOKEN=approval_environment_unprotected
    KR_CHECK_DETAIL="KK_APPROVAL_ENV_BOUND is not true: the workflow's approve job is not bound to the reviewer-gated environment"
    return 1
  fi
  out="$(gh api "repos/${GITHUB_REPOSITORY:-}/environments/key-rotate-approval" 2>/dev/null)" \
    || { KR_CHECK_TOKEN=approval_environment_unprotected; KR_CHECK_DETAIL="the key-rotate-approval environment could not be read (an unreadable read is an unprotected environment, fail closed)"; return 1; }
  if ! jq -e '[.protection_rules[]? | .type] | index("required_reviewers") and index("branch_policy")' <<<"$out" >/dev/null 2>&1; then
    KR_CHECK_TOKEN=approval_environment_unprotected
    KR_CHECK_DETAIL="the key-rotate-approval environment's protection_rules lack required_reviewers or a branch policy"
    return 1
  fi
  # content level (a type that names no reviewer protects nobody)
  if ! jq -e '[.protection_rules[]? | select(.type == "required_reviewers") | .reviewers[]?] | length > 0' <<<"$out" >/dev/null 2>&1; then
    KR_CHECK_TOKEN=approval_environment_unprotected
    KR_CHECK_DETAIL="the key-rotate-approval environment's required_reviewers rule lists no reviewer (a review nobody can give is no gate)"
    return 1
  fi
  pol="$(gh api --paginate "repos/${GITHUB_REPOSITORY:-}/environments/key-rotate-approval/deployment-branch-policies" 2>/dev/null)" \
    || { KR_CHECK_TOKEN=approval_environment_unprotected; KR_CHECK_DETAIL="the key-rotate-approval deployment-branch-policies read failed (an unreadable read is an unprotected environment, fail closed)"; return 1; }
  if ! jq -e '.branch_policies as $p | ($p | length) > 0 and all($p[]; .type == "branch" and .name == "main")' <<<"$pol" >/dev/null 2>&1; then
    KR_CHECK_TOKEN=approval_environment_unprotected
    KR_CHECK_DETAIL="the key-rotate-approval deployment branch policy does not restrict deployments to refs/heads/main alone"
    return 1
  fi
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

kk_swap_member() { local m; for m in "${KK_SWAP_MEMBER_WORKFLOWS[@]}"; do [[ "$1" == "$m" ]] && return 0; done; return 1; }

kk_chk_inflight() { # [redeploy]: the sourced three statuses, then the two the sourced helper does not poll
  local wf st n
  local -a wfs=()
  for wf in "${KR_INFLIGHT_WORKFLOWS[@]}"; do
    # N3: in redeploy mode a web-1-swap member's run is not a blocker (its deploy job is queued behind this job's own hold)
    if [[ "${1:-}" == redeploy ]] && kk_swap_member "$wf"; then continue; fi
    wfs+=("$wf")
  done
  local -a KR_INFLIGHT_WORKFLOWS=("${wfs[@]}")
  kr_inflight_check || return 1
  for wf in "${wfs[@]}"; do
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
    [[ "$n" == 0 ]] || { KR_CHECK_TOKEN=run_in_flight; KR_CHECK_DETAIL="an earlier ${KK_OWN_WORKFLOW} run (a plan or a rotate dispatch) is still ${st}"; return 1; }
  done
}

# kk_chk_kb_window <budget-seconds>: [now, now + budget] against today's and tomorrow's [03:00, 03:30] UTC (inclusive both ends).
kk_chk_kb_window() {
  local b="${1:-$KK_KB_BUDGET_APPLY_S}" now day d ws we
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

# kk_recheck <key> <kb-budget-seconds> [redeploy]: the facts that age (in-flight runs, an earlier run of this workflow, the kb_drift
# windows). The "redeploy" mode (R1) skips the kb window: after a landed write the leg must finish, so only the transient rungs
# (in-flight, earlier run, walker) are read, and the caller polls them.
kk_recheck() {
  KR_CHECK_TOKEN=internal_error; KR_CHECK_DETAIL=""; KK_RECHECK_RUNG=""
  KK_RECHECK_RUNG=inflight; kk_chk_inflight "${3:-}" || return 1
  KK_RECHECK_RUNG=lower; kk_chk_lower_run || return 1
  if [[ "$1" == kb_drift_ingest_signing_key ]]; then
    [[ "${3:-}" == redeploy ]] || { KK_RECHECK_RUNG=kb; kk_chk_kb_window "$2" || return 1; }
    KK_RECHECK_RUNG=walker; kk_chk_walker || return 1
  fi
  KK_RECHECK_RUNG=""
  return 0
}

# kk_recheck_rung <rung>: re-read ONE rung of the redeploy poll (N6: after the first blocked pass only the rung that blocked).
kk_recheck_rung() {
  KR_CHECK_TOKEN=internal_error; KR_CHECK_DETAIL=""
  case "$1" in
    inflight) kk_chk_inflight redeploy ;;
    lower) kk_chk_lower_run ;;
    walker) kk_chk_walker ;;
    *) return 1 ;;
  esac
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
# The unknown result carries a fixed-vocabulary cause class (listing_/read_ + timeout|failed|empty), derived from the exit code and
# the emptiness of the read only; no byte of a Doppler stream or value leaves the function. Each Doppler call is capped.
kk_copy_state() {
  local names h rc=0
  names="$(DOPPLER_TOKEN="${DOPPLER_TOKEN_TF:-}" timeout "$KK_DOPPLER_READ_S" doppler secrets --only-names -p "$1" -c "$2" 2>/dev/null)" || rc=$?
  if [[ "$rc" != 0 ]]; then if [[ "$rc" == 124 || "$rc" == 137 ]]; then printf 'unknown:listing_timeout'; else printf 'unknown:listing_failed'; fi; return 0; fi
  [[ -n "$names" ]] || { printf 'unknown:listing_empty'; return 0; }
  if ! grep -Eq "(^|[^A-Za-z0-9_])${3}([^A-Za-z0-9_]|\$)" <<<"$names"; then printf 'absent'; return 0; fi
  h="$(DOPPLER_TOKEN="${DOPPLER_TOKEN_TF:-}" timeout "$KK_DOPPLER_READ_S" doppler secrets get "$3" --plain -p "$1" -c "$2" 2>/dev/null | sha256sum | cut -c1-64)" || rc=$?
  if [[ "$rc" != 0 ]]; then if [[ "$rc" == 124 || "$rc" == 137 ]]; then printf 'unknown:read_timeout'; else printf 'unknown:read_failed'; fi; return 0; fi
  [[ "$h" =~ ^[0-9a-f]{64}$ && "$h" != "$KR_EMPTY_SHA" ]] || { printf 'unknown:read_empty'; return 0; }
  printf 'present %s' "$h"
}

kk_load_copies() { # key -> KK_CP (the copy rows of this key)
  local row
  KK_CP=()
  for row in "${KK_COPIES[@]}"; do [[ "${row%%|*}" == "$1" ]] && KK_CP+=("$row"); done
}

kk_pre_state() {
  local i s np=0 na=0 nu=0 p c nm cls="" cl
  KK_PRE_ST=(); KK_PRE_H=()
  for i in "${!KK_CP[@]}"; do
    IFS='|' read -r _ p c nm _ <<<"${KK_CP[i]}"
    s="$(kk_copy_state "$p" "$c" "$nm")"
    cl=""
    case "$s" in
      absent) KK_PRE_ST[i]=absent; KK_PRE_H[i]=""; na=$((na + 1)) ;;
      "present "*) KK_PRE_ST[i]=present; KK_PRE_H[i]="${s#present }"; np=$((np + 1)) ;;
      *) KK_PRE_ST[i]=unknown; KK_PRE_H[i]=""; nu=$((nu + 1)); cl="${s#unknown}"; cl="${cl#:}"; cls="${cls:+$cls }${cl:-unclassified}" ;;
    esac
    kk_say "pre-state copy ${c}: ${KK_PRE_ST[i]}${cl:+ (cause class ${cl})}"
  done
  if [[ "$nu" != 0 ]]; then kr_refuse copy_unreadable "a copy of the key could not be read value-silently (cause class: ${cls}); nothing was written"; return 1; fi
  if [[ "$np" != 0 && "$na" != 0 ]]; then
    KR_SCRUB_CAP=420 kr_refuse partial_absent_state "some copies of the key are present and some absent (an external deletion or an interrupted earlier apply). URGENT, not auto-repaired: do not restart anything. A rotate refuses identically while the copies are mixed: recreate the missing copy in Doppler (or accept the mixed state), then rotate; nothing was written"
    return 1
  fi
  KK_ABSENT_ALL=false
  [[ "$np" == 0 ]] && KK_ABSENT_ALL=true
  return 0
}

# kk_want <key>: the unioned want (phases A and B) with the per-row flags the gate needs.
kk_want() {
  local base absent="{}" repl i p c nm addr tgt=false
  # a key whose phase-B rows are flag `target` updates its copies in place, so a bare create of its random_id (a lost state entry)
  # is recoverable although the copies are present
  grep -qx target <<<"$(kr_gate_rows B "$1" | cut -d'|' -f4)" && tgt=true
  base="$(jq -cs 'add' <(kr_gate_want A "$1") <(kr_gate_want B "$1"))" || return 1
  # A phase-B row whose address ends _previous is the egress PREVIOUS satellite (#11920): its value is VAR-FED, so a
  # real plan always knows it and the gate's recovery -> after_unknown_value clause can never hold for it (the clear
  # leg spells the same row recovery:false in its one-row want). Demote it out of the recovery class: recover falls to
  # the same ($all or $tgt) class the random_id row sits in, and previous_not_staged still verifies the staged value
  # landed. The address comes out of the gate table (B19), never a literal.
  local sat
  sat="$(kr_gate_rows B "$1" | cut -d'|' -f3 | grep '_previous$' | head -1 || true)"
  if [[ -n "$sat" ]]; then
    base="$(jq -c --arg sat "$sat" 'map(if .address == $sat then .recovery = false else . end)' <<<"$base")" || return 1
  fi
  repl="$( { kr_gate_replaces A "$1"; kr_gate_replaces B "$1"; } | sed -e 's/^-replace=//' | jq -R -cs 'split("\n") | map(select(length > 0))')"
  for i in "${!KK_CP[@]}"; do
    IFS='|' read -r _ p c nm addr <<<"${KK_CP[i]}"
    absent="$(jq -c --arg a "$addr" --argjson v "$([[ "${KK_PRE_ST[i]}" == absent ]] && echo true || echo false)" '. + {($a): $v}' <<<"$absent")"
  done
  jq -c --argjson absent "$absent" --argjson repl "$repl" --argjson all "$KK_ABSENT_ALL" --argjson tgt "$tgt" \
    'map(. + {replace: (.address as $a | $repl | index($a) != null), recover: (if .recovery then ($absent[.address] // false) else ($all or $tgt) end)})' <<<"$base"
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

# kk_tf_class <name> <rc>: a fixed-vocabulary cause class for a failed Terraform step. Only the class word leaves this function: it
# is a count of fixed-pattern matches in the private .err file (backend_auth, provider_auth, state_lock, init, config, timeout, other).
kk_tf_class() {
  local f="$KR_TMP/tf-${1}.err"
  if [[ "${2:-}" == 124 || "${2:-}" == 137 ]]; then printf 'timeout'; return 0; fi
  if [[ -f "$f" ]]; then
    if [[ "$(grep -Eic 'Error acquiring the state lock|state lock' "$f")" -gt 0 ]]; then printf 'state_lock'; return 0; fi
    if [[ "$(grep -Eic 'InvalidAccessKeyId|SignatureDoesNotMatch|No valid credential sources|failed to load backend|error loading state|NoCredentialProviders|AccessDenied|status code: 403' "$f")" -gt 0 ]]; then printf 'backend_auth'; return 0; fi
    if [[ "$(grep -Eic 'Doppler Error|Invalid Auth token|Unauthorized|authentication failed|status code: 401|invalid token' "$f")" -gt 0 ]]; then printf 'provider_auth'; return 0; fi
    if [[ "$(grep -Eic 'Failed to install provider|Failed to query available provider|Backend initialization required|Inconsistent dependency lock file' "$f")" -gt 0 ]]; then printf 'init'; return 0; fi
    if [[ "$(grep -Eic 'Missing required argument|Unsupported argument|Invalid value for variable|No value for required variable|Reference to undeclared|Invalid target|Invalid replace' "$f")" -gt 0 ]]; then printf 'config'; return 0; fi
  fi
  printf 'other'
}

# kk_tf_clean [keep-plan]: delete every Terraform stream file (and the saved plan unless told to keep it) the moment its exit code is
# read. A stream carries key bytes and nothing may linger on the runner until the EXIT trap. The only code that names a `tf-` stream
# file outside the sourced kr_tf is kk_tf_class (reads a count), kk_gate_plan (the projection) and this function (the suite pins it).
kk_tf_clean() {
  rm -f -- "$KR_TMP"/tf-*
  [[ "${1:-}" == keep-plan ]] || rm -f -- "$KR_TMP"/tfplan-*
  return 0
}

# kk_gate_plan <key> <name>: plan, show, PROJECT, delete the full JSON, gate. On success $KR_TMP/tfplan-<name> is the saved plan.
kk_gate_plan() {
  local key="$1" name="$2" rc=0 want proj cls
  local -a targets repls
  mapfile -t targets < <(kr_gate_targets A "$key"; kr_gate_targets B "$key")
  mapfile -t repls < <(kr_gate_replaces A "$key"; kr_gate_replaces B "$key")
  kr_tf "plan-${name}" plan -no-color -input=false -out="$KR_TMP/tfplan-${name}" -var="ssh_key_path=${KR_TMP}/ci_ssh_key.pub" \
    "${targets[@]}" "${repls[@]}" || rc=$?
  if [[ "$rc" != 0 ]]; then
    cls="$(kk_tf_class "plan-${name}" "$rc")"; kk_tf_clean
    kr_refuse terraform_failed "the plan step exited ${rc} (cause class: ${cls}); its output was deleted from the runner (it carried key bytes)"; return 1
  fi
  rc=0
  KR_TF_T="$KK_TF_SHOW_S" kr_tf "show-${name}" show -json "$KR_TMP/tfplan-${name}" || rc=$?
  if [[ "$rc" != 0 ]]; then
    cls="$(kk_tf_class "show-${name}" "$rc")"; kk_tf_clean
    kr_refuse terraform_failed "the plan-to-JSON step exited ${rc} (cause class: ${cls}); its output was deleted from the runner (it carried key bytes)"; return 1
  fi
  proj="$KR_TMP/proj-${name}.json"
  ( umask 077; jq -c "$KK_PROJECT_JQ" "$KR_TMP/tf-show-${name}.out" > "$proj" 2>/dev/null ) || rc=$?
  kk_tf_clean keep-plan
  if [[ "$rc" != 0 || ! -s "$proj" ]] || ! jq -e 'type == "array"' "$proj" >/dev/null 2>&1; then
    kk_tf_clean
    kr_refuse terraform_failed "the plan projection failed or was empty; the full plan JSON was deleted"
    return 1
  fi
  want="$(kk_want "$key")" || { kk_tf_clean; kr_refuse internal_error "the gate table could not be built for this key"; return 1; }
  kk_gate "$key" "$proj" "$want" || { kk_tf_clean; return 1; }
}

kk_stale_test() { # authorization_stale as a report-only test (sets KR_CHECK_*, prints nothing): the confirm date still today, the gap bounded
  local ge="${EFF_GUARD_EPOCH:-}" now
  now="$(kr_now)"
  if [[ ! "$ge" =~ ^[0-9]+$ ]] || (( now - ge > KK_AUTH_MAX_AGE_S )) || [[ "$(kk_date "$now")" != "$(kk_date "$ge")" ]]; then
    KR_CHECK_TOKEN=authorization_stale
    KR_CHECK_DETAIL="the guard's go is older than $((KK_AUTH_MAX_AGE_S / 60)) minutes or the UTC date rolled; re-dispatch under a fresh confirm"
    return 1
  fi
}

kk_chk_stale() { # authorization_stale: refuses
  kk_stale_test && return 0
  kr_refuse "$KR_CHECK_TOKEN" "${KR_CHECK_DETAIL}; nothing was written"
  return 1
}

# kk_chk_apply_budget (R3): immediately before the write, the time left in this step must cover the apply bound plus a margin; a
# step timeout would otherwise kill a half-finished apply.
kk_chk_apply_budget() {
  if (( $(kr_now) - KK_STEP_START + KR_TF_APPLY_S + KK_APPLY_MARGIN_S > KK_APPLY_STEP_S )); then
    kr_refuse authorization_stale "pre-write time left is below the apply budget; nothing was written"
    return 1
  fi
}

kk_require_attempt() {
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

# kk_egress_previous_feed (egress only, #11920): apply-A reads the OLD current value once, value-silently, into the
# PREVIOUS TF variable — env only: the value never reaches argv, a file, a summary or a log (the
# -replace of the PREVIOUS row in the same plan writes it, so the route accepts
# CURRENT+PREVIOUS during the redeploy + vector-restart window). An absent CURRENT (the recovery rotate, KK_ABSENT_ALL)
# feeds "": there is no old token left to preserve.
kk_egress_previous_feed() {
  local v rc=0
  v="$(DOPPLER_TOKEN="${DOPPLER_TOKEN_TF:-}" timeout "$KK_DOPPLER_READ_S" doppler secrets get EGRESS_AUDIT_INGEST_TOKEN --plain -p soleur -c prd 2>/dev/null)" || rc=$?
  if [[ "$rc" != 0 ]]; then
    if [[ "$KK_ABSENT_ALL" == true ]]; then export TF_VAR_egress_audit_ingest_token_previous=""; return 0; fi
    kr_refuse copy_unreadable "the old EGRESS_AUDIT_INGEST_TOKEN could not be read for the PREVIOUS feed; nothing was written"
    return 1
  fi
  export TF_VAR_egress_audit_ingest_token_previous="$v"
  kk_say "key-rotate: the old EGRESS_AUDIT_INGEST_TOKEN was staged for the PREVIOUS row (env only, never argv)"
}

# kk_rotate_would_refuse <key>: report-only (plan mode): the first rotate-only rung this key would meet, as a token already in the
# fixed set, or none. Not evaluated here: the guard-time rungs that need dispatch inputs or the issues API (confirm, quiet_window,
# attempt, webhook_patch_ready, owner_step_open) and authorization_stale (in plan mode it would measure the plan run's own guard age,
# not the age a later rotate dispatch would have).
kk_rotate_would_refuse() {
  local tok=none
  if ! kk_chk_approval "$1"; then tok="$KR_CHECK_TOKEN"
  elif ! kk_recheck "$1" "$KK_KB_BUDGET_APPLY_S"; then tok="$KR_CHECK_TOKEN"
  fi
  [[ "$tok" == none ]] || kr_token_known "$tok" || tok=internal_error
  printf '%s' "$tok"
}

kk_cmd_apply() {
  local mode="${EFF_MODE:-}" key="${EFF_KEY:-}" rc=0 would irc
  KK_STEP_START="$(kr_now)"
  kk_valid_inputs "$mode" "$key" || return 1
  kr_init || return 1
  if [[ "$mode" == rotate ]]; then
    kk_require_attempt || return 1
    kk_chk_approval "$key" || { kr_refuse "$KR_CHECK_TOKEN" "${KR_CHECK_DETAIL}; nothing was written"; return 1; }
    kk_chk_stale || return 1
    kk_recheck "$key" "$KK_KB_BUDGET_APPLY_S" || { kr_refuse "$KR_CHECK_TOKEN" "${KR_CHECK_DETAIL}; nothing was written"; return 1; }
  fi
  if ! kr_tf_prepare; then
    if [[ "${KR_VERDICT:-}" == terraform_failed ]]; then
      # kr_tf_prepare hides the init exit code; the refusal detail it just wrote carries "exited <rc>" (kr_refuse keeps it)
      irc="${KK_LAST_DETAIL#*exited }"; irc="${irc%%[!0-9]*}"; [[ "$irc" =~ ^[0-9]+$ ]] || irc=1
      kk_say "key-rotate: terraform_failed cause class: $(kk_tf_class init "$irc")"
    fi
    kk_tf_clean
    return 1
  fi
  kk_tf_clean
  kk_load_copies "$key"
  kk_pre_state || return 1
  [[ "$key" == egress_audit_ingest_token ]] && { kk_egress_previous_feed || return 1; }
  kk_gate_plan "$key" p || return 1
  if [[ "$mode" == plan ]]; then
    kr_summary "gate rows: $(kr_gate_rows A "$key" | cut -d'|' -f3,5 | tr '\n' ' ')$(kr_gate_rows B "$key" | cut -d'|' -f3,5 | tr '\n' ' ')"
    kk_tf_clean
    would="$(kk_rotate_would_refuse "$key")"
    kr_ok plan_ok "the plan gate passed for key=${key} (${#KK_CP[@]} copies readable, absent_all=${KK_ABSENT_ALL}); nothing was applied" "rotate_would_refuse=${would}"
    return 0
  fi
  # the last read before the write: the facts above have aged by up to the init and plan time
  kk_chk_stale || { kk_tf_clean; return 1; }
  kk_recheck "$key" "$KK_KB_BUDGET_PREAPPLY_S" || { kk_tf_clean; kr_refuse "$KR_CHECK_TOKEN" "${KR_CHECK_DETAIL}; nothing was written"; return 1; }
  kk_chk_apply_budget || { kk_tf_clean; return 1; }
  kr_out write_started true
  KR_TF_T="$KR_TF_APPLY_S" kr_tf apply apply -no-color -input=false "$KR_TMP/tfplan-p" || rc=$?
  kk_tf_clean
  kk_post_state
  kk_print_post
  if [[ "$rc" != 0 ]]; then
    kr_post_write_failure apply_failed "the apply exited ${rc}; see the per-copy states above; its output was deleted from the runner" "The apply failed part-way."
    return 1
  fi
  if kk_has_post unknown; then kr_post_write_failure post_hash_unreadable "a copy could not be read back after the apply" "The apply finished but a copy cannot be read."; return 1; fi
  if kk_has_post absent; then kr_post_write_failure partial_absent_state "a copy is absent after the apply" "A copy of the key is absent after the apply."; return 1; fi
  if kk_has_post present-unchanged; then kr_post_write_failure value_unchanged "a copy did not change (new_differs_from_prior=false)" "The apply reported success but a copy did not change."; return 1; fi
  if [[ "${#KK_POST_H[@]}" -gt 1 && "$(printf '%s\n' "${KK_POST_H[@]}" | sort -u | wc -l | tr -d ' ')" != 1 ]]; then
    kr_post_write_failure copies_differ "copies_equal=false after the apply" "The apply finished but the copies of the key are not equal."; return 1
  fi
  # post-apply PREVIOUS verify (egress only, #11920): the grace window exists only when PREVIOUS reads back the value the
  # feed staged - the old CURRENT (absent or empty reads as the LOSSY direction: hosts still on the old env are rejected
  # until the redeploy). The recovery rotate (KK_ABSENT_ALL, nothing old left to preserve) legitimately reads absent or
  # empty. Value-silent through kk_copy_state; the same retry shape as the post-state read covers Doppler lag. A read that
  # cannot prove the staged value is previous_not_staged; a read that fails outright is post_hash_unreadable.
  if [[ "$key" == egress_audit_ingest_token ]]; then
    local pvs pvc=unread try
    for ((try = 1; try <= KK_RETRIES; try++)); do
      pvs="$(kk_copy_state soleur prd EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS)"
      case "$pvs" in
        "present "*) [[ "$KK_ABSENT_ALL" != true && "$pvs" == "present ${KK_PRE_H[0]:-none}" ]] && pvc=ok || pvc=fail ;;
        absent|unknown:read_empty|unknown:listing_empty) [[ "$KK_ABSENT_ALL" == true ]] && pvc=ok || pvc=fail ;;
        *) pvc=unread ;;
      esac
      [[ "$pvc" == ok ]] && break
      (( try < KK_RETRIES )) && kr_sleep "$KK_RETRY_SLEEP_S"
    done
    case "$pvc" in
      unread) kr_post_write_failure post_hash_unreadable "EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS could not be read back after the apply" "The apply landed but the PREVIOUS read-back failed."; return 1 ;;
      fail) kr_post_write_failure previous_not_staged "after the apply, EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS reads ${pvs:-unknown} - the old token is accepted nowhere (hosts on the old env are rejected until the redeploy)" "The apply landed but the PREVIOUS staging did not take."; return 1 ;;
    esac
    kk_say "key-rotate: post-apply verify - EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS reads the staged old value"
  fi
  kk_say "key-rotate: apply done for key=${key}; every copy changed and the copies are equal; the redeploy leg is next"
  [[ "$KK_ABSENT_ALL" == true ]] && { kk_say "key-rotate: recovery path - the old value survives only in running containers; the redeploy is mandatory and urgent"; }
  return 0
}

# ---------------------------------------------------------------------------------------------------------------------------
# REDEPLOY (three steps of the redeploy job)
kk_redeploy_refuse() { # <reason-token> <detail>
  kr_post_write_failure rotated_redeploy_failed "reason=${1}: ${2}; the new value is landed and the old containers are running; the redeploy was not dispatched" "The redeploy leg did not run: the apply landed the new value."
}

# kk_redeploy_wait <key> (R1): the read-only poll of the transient rungs only. After a landed write this leg never refuses on
# staleness, the kb window or quiet_window; it re-reads every KK_REDEPLOY_POLL_S seconds for at most KK_REDEPLOY_WAIT_S seconds and
# leaves the last blocking rung in KR_CHECK_TOKEN / KR_CHECK_DETAIL when the wait is spent.
kk_redeploy_wait() {
  local start now rung=""
  # N6: every gh call of the poll (the sourced kr_inflight_check included) is capped; the shadow is removed on return
  KK_GH_BIN="$(type -P gh)" || KK_GH_BIN=gh
  gh() { timeout "$KK_GH_POLL_S" "$KK_GH_BIN" "$@"; }
  start="$(kr_now)"
  while :; do
    # after the first blocked pass only the rung that blocked is re-read; once it clears, the full ladder runs once more
    if [[ -z "$rung" ]] || kk_recheck_rung "$rung"; then
      rung=""
      if kk_recheck "$1" 0 redeploy; then unset -f gh; return 0; fi
      rung="$KK_RECHECK_RUNG"
    fi
    now="$(kr_now)"
    if (( now - start + KK_REDEPLOY_POLL_S > KK_REDEPLOY_WAIT_S )); then unset -f gh; return 1; fi
    kr_sleep "$KK_REDEPLOY_POLL_S"
  done
}

kk_redeploy_recheck() {
  [[ "${EFF_MODE:-}" == rotate ]] || { kr_refuse internal_error "redeploy runs for rotate only"; return 1; }
  kk_valid_inputs rotate "${EFF_KEY:-}" || return 1
  kr_init || return 1
  if ! kr_chk_attempt; then kk_redeploy_refuse "$KR_CHECK_TOKEN" "$KR_CHECK_DETAIL"; return 1; fi
  if ! kk_redeploy_wait "$EFF_KEY"; then kk_redeploy_refuse "$KR_CHECK_TOKEN" "$KR_CHECK_DETAIL"; return 1; fi
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
  if [[ "$key" == egress_audit_ingest_token ]]; then
    if [[ "${EFF_VECTOR_OUTCOME:-}" != success ]]; then
      kr_post_write_failure rotated_redeploy_failed "the vector restart leg did not confirm every host (outcome ${EFF_VECTOR_OUTCOME:-unknown}); PREVIOUS stays set and the old token remains accepted" "The fleet redeploy was confirmed but the vector restart did not confirm on every host."
      return 1
    fi
    kr_ok vector_restarted "key=${key}; the fleet redeploy and the per-host vector restart were confirmed; the PREVIOUS clear leg is next"
    return 0
  fi
  kr_ok rotate_ok "key=${key}; the fleet redeploy was confirmed by track.sh (this does not prove each consumer picked up the value)"
}

# ---------------------------------------------------------------------------------------------------------------------------
# REDEPLOY vector (egress only, #11920): dispatch `restart vector _ _` with the peer roster over the existing deploy
# webhook channel (adnanh/webhook, the same HMAC + CF-Access path track.sh uses), then poll the MERGED deploy-status
# until every host reports a fresh component=vector success frame (start_ts above that host's own baseline frame). A
# host that does not report makes the leg non-green: the clear job never runs and PREVIOUS stays set (FR9 - the old
# token remains accepted, the lossless direction). The per-peer slots of the merged read are the peers' whole status
# JSON (cat-deploy-state.sh), so a peer error slot is a failure, never a pass.
#
# #12299: the dispatch additionally runs AFTER a settle gate. track green does not mean a peer's deploy has released
# /var/lock/ci-deploy.lock — a `restart vector` fanned out while a peer is mid-deploy loses that host's flock -n; the
# loser's transient vector/lock_contention frame is then OVERWRITTEN by the still-running deploy's terminal frame, so
# kk_vector_green can never see a fresh vector/success for it and the leg times out into rotated_redeploy_failed with
# nothing actually wrong. The gate polls the merged status until EVERY roster slot is terminal (a numeric exit_code
# >= 0 whose reason is neither running nor lock_contention — a lock_contention frame is terminal for the loser but
# proves the lock is still held by another invocation), then the settled read doubles as the per-host baseline and the
# restart is dispatched. One mid-window re-dispatch is kept as a residual: a peer that still lost the first fan-out is
# caught by the second (the peer arm is an idempotent try-restart).
KK_DEPLOY_BASE="deploy.soleur.ai"
declare -A KK_VBASE_PEERS=()
KK_VBASE_SELF=0
KK_VBASE_EPOCH=0

kk_vector_status() { # <outfile> -> the http code on stdout; the body lands in $1
  # shellcheck source=/dev/null
  source "$KK_ROOT/scripts/lib/bearer-curl.sh" || return 1
  bc_curl key-rotate 'X-Signature-256:sha256=:KK_GET_SIG' 'CF-Access-Client-Id::CF_ACCESS_CLIENT_ID' \
    'CF-Access-Client-Secret::CF_ACCESS_CLIENT_SECRET' -- \
    -s --max-time 15 -o "$1" -w '%{http_code}' -X GET "https://${KK_DEPLOY_BASE}/hooks/deploy-status" || echo 000
}

# kk_vector_green <status-file>: the responder's base frame is a fresh component=vector success AND every roster ip
# either reports one in its peers slot or is the responder itself (absent from .peers = self, covered by the base frame).
kk_vector_green() {
  local f="$1" ip st base
  st="$(jq -r 'select(.component == "vector" and .reason == "success") | .start_ts // 0' "$f" 2>/dev/null)"
  [[ "$st" =~ ^[0-9]+$ && "$st" -gt "$KK_VBASE_SELF" ]] || return 1
  for ip in ${WEB_HOST_PRIVATE_IPS//,/ }; do
    st="$(jq -r --arg ip "$ip" '.peers[$ip] // empty | select(type == "object") | select(.component == "vector" and .reason == "success") | .start_ts // 0' "$f" 2>/dev/null)"
    if [[ -z "$st" ]]; then
      jq -e --arg ip "$ip" '.peers | has($ip)' "$f" >/dev/null 2>&1 && return 1   # a slot exists but holds no fresh success
      continue   # absent slot: the responder's own ip, already confirmed by the base frame
    fi
    [[ "$st" =~ ^[0-9]+$ ]] || return 1
    base="${KK_VBASE_PEERS[$ip]:-$KK_VBASE_EPOCH}"
    (( st > base )) || return 1
  done
  return 0
}

# kk_vector_slot_rows <status-file>: one "ip component/reason/start_ts/exit_code" line per roster host — the .peers[ip]
# slot when present, the base frame for an absent slot (the responder itself, the kk_vector_green convention). A peer
# error object prints its error word in place of the reason.
kk_vector_slot_rows() {
  local f="$1" ip
  for ip in ${WEB_HOST_PRIVATE_IPS//,/ }; do
    jq -r --arg ip "$ip" '
      (if (.peers // {} | has($ip)) then .peers[$ip] else . end) as $s
      | "\($ip) \($s.component // "-")/\($s.reason // ($s.error // "-"))/\($s.start_ts // "-")/\($s.exit_code // "-")"' \
      "$f" 2>/dev/null
  done
}

# kk_vector_settled <status-file>: every roster ip's slot is terminal — a numeric exit_code >= 0 with a reason that is
# neither running nor lock_contention. A peer error slot ({"error":...}) has no exit_code and is not settled.
kk_vector_settled() {
  local f="$1" ip
  for ip in ${WEB_HOST_PRIVATE_IPS//,/ }; do
    jq -e --arg ip "$ip" '
      (if (.peers // {} | has($ip)) then .peers[$ip] else . end) as $s
      | (($s.exit_code | type) == "number" and $s.exit_code >= 0)
        and (($s.reason // "") != "running" and ($s.reason // "") != "lock_contention")' \
      "$f" >/dev/null 2>&1 || return 1
  done
  return 0
}

# kk_vector_dispatch: POST the restart-vector command over the deploy webhook; prints the http code. Idempotent by
# contract (the peer arm is systemctl try-restart), which is what licenses the mid-window re-dispatch.
kk_vector_dispatch() {
  local payload post_sig
  payload="$(jq -cn --arg cmd "restart vector _ _" --arg peers "$WEB_HOST_PRIVATE_IPS" '{command:$cmd, peers:$peers}')"
  post_sig="$(printf '%s' "$payload" | bc_hmac_sha256_hex WEBHOOK_DEPLOY_SECRET)" || post_sig=""
  if [[ -z "$post_sig" ]]; then kk_say "key-rotate: the dispatch signature could not be computed; nothing was sent"; printf '000'; return; fi
  KK_POST_SIG="$post_sig"
  bc_curl key-rotate 'X-Signature-256:sha256=:KK_POST_SIG' 'CF-Access-Client-Id::CF_ACCESS_CLIENT_ID' \
    'CF-Access-Client-Secret::CF_ACCESS_CLIENT_SECRET' -- \
    -s -o /dev/null -w '%{http_code}' --max-time 30 -X POST -H "Content-Type: application/json" \
    -d "$payload" "https://${KK_DEPLOY_BASE}/hooks/deploy" || echo 000
}

kk_redeploy_vector() {
  [[ "${EFF_MODE:-}" == rotate && "${EFF_KEY:-}" == egress_audit_ingest_token ]] || { kr_refuse internal_error "the vector leg runs for egress rotate only"; return 1; }
  kr_init || return 1
  if [[ -z "${WEBHOOK_DEPLOY_SECRET:-}" || -z "${CF_ACCESS_CLIENT_ID:-}" || -z "${CF_ACCESS_CLIENT_SECRET:-}" ]]; then
    kk_say "key-rotate: the deploy webhook trio is not set; the vector restart was not dispatched"; return 1
  fi
  [[ "${WEB_HOST_PRIVATE_IPS:-}" =~ ^[0-9.]+(,[0-9.]+)*$ ]] \
    || { kk_say "WEB_HOST_PRIVATE_IPS is unset or malformed; a partial vector restart would leave the fleet mixed. Nothing was dispatched."; return 1; }
  # shellcheck source=/dev/null
  source "$KK_ROOT/scripts/lib/bearer-curl.sh" || { kk_say "key-rotate: bearer-curl.sh could not be loaded; the vector restart was not dispatched"; return 1; }
  local ip b post_code http start now retried="" row
  KK_GET_SIG="$(bc_hmac_sha256_hex WEBHOOK_DEPLOY_SECRET < /dev/null)" || KK_GET_SIG=""
  if [[ -z "$KK_GET_SIG" ]]; then kk_say "key-rotate: the status-read signature could not be computed; the vector restart was not dispatched"; return 1; fi
  # the settle gate (#12299): poll the merged status until every roster slot is terminal (per-poll slot rows in the
  # log, the full table on timeout), bounded by KK_SETTLE_S; the settled read doubles as the per-host baseline
  start="$(kr_now)"
  while :; do
    http="$(kk_vector_status "$KR_TMP/vbase.json")"
    if [[ "$http" == 200 ]] && kk_vector_settled "$KR_TMP/vbase.json"; then
      kk_say "key-rotate: settle gate - every host slot is terminal; taking the read as the per-host baseline"
      break
    fi
    now="$(kr_now)"
    if (( now - start + KK_SETTLE_POLL_S > KK_SETTLE_S )); then
      kk_say "key-rotate: settle gate - not every host reported a terminal frame within ${KK_SETTLE_S}s (last read HTTP ${http}); the vector restart was not dispatched. Per-host table:"
      while IFS= read -r row; do kk_say "  ${row}"; done < <(kk_vector_slot_rows "$KR_TMP/vbase.json")
      return 1
    fi
    if [[ "$http" == 200 ]]; then
      while IFS= read -r row; do kk_say "  ${row}"; done < <(kk_vector_slot_rows "$KR_TMP/vbase.json")
    else
      kk_say "key-rotate: settle gate - /hooks/deploy-status unreadable (HTTP ${http}); retrying"
    fi
    kr_sleep "$KK_SETTLE_POLL_S"
  done
  # the per-host baseline (fail closed, like track.sh): a frame is fresh only when start_ts exceeds it
  KK_VBASE_SELF="$(jq -r '.start_ts // 0' "$KR_TMP/vbase.json" 2>/dev/null)"
  KK_VBASE_EPOCH="$(kr_now)"
  if [[ ! "$KK_VBASE_SELF" =~ ^[0-9]+$ || "$KK_VBASE_SELF" == 0 ]]; then kk_say "key-rotate: /hooks/deploy-status returned no numeric start_ts baseline; refusing to assert a vector restart blind"; return 1; fi
  KK_VBASE_PEERS=()
  for ip in ${WEB_HOST_PRIVATE_IPS//,/ }; do
    b="$(jq -r --arg ip "$ip" '.peers[$ip].start_ts // empty' "$KR_TMP/vbase.json" 2>/dev/null)"
    [[ "$b" =~ ^[0-9]+$ ]] || b="$KK_VBASE_EPOCH"
    KK_VBASE_PEERS[$ip]="$b"
  done
  post_code="$(kk_vector_dispatch)"
  if [[ "$post_code" != 202 ]]; then kk_say "key-rotate: POST /hooks/deploy rejected (HTTP ${post_code}); the vector restart was not dispatched"; return 1; fi
  kk_say "key-rotate: restart vector dispatched (HTTP 202, peers=${WEB_HOST_PRIVATE_IPS}); polling for a fresh component=vector success frame on every host"
  start="$(kr_now)"
  while :; do
    http="$(kk_vector_status "$KR_TMP/vpoll.json")"
    if [[ "$http" == 200 ]] && kk_vector_green "$KR_TMP/vpoll.json"; then
      kk_say "key-rotate: every host reports a fresh component=vector success frame"
      return 0
    fi
    now="$(kr_now)"
    if [[ -z "$retried" ]] && (( now - start >= KK_VECTOR_S / 2 )); then
      retried=1
      post_code="$(kk_vector_dispatch)"
      if [[ "$post_code" == 202 ]]; then
        kk_say "key-rotate: mid-window re-dispatch of restart vector accepted (HTTP 202; idempotent try-restart - covers a peer that lost the first fan-out to its own deploy lock)"
      else
        kk_say "key-rotate: mid-window re-dispatch rejected (HTTP ${post_code}); the first dispatch's frames still govern"
      fi
    fi
    if (( now - start + KK_VECTOR_POLL_S > KK_VECTOR_S )); then
      kk_say "key-rotate: not every host reported a fresh component=vector success frame within ${KK_VECTOR_S}s; PREVIOUS stays set"
      return 1
    fi
    kr_sleep "$KK_VECTOR_POLL_S"
  done
}

kk_cmd_redeploy() {
  case "${1:-}" in
    recheck) kk_redeploy_recheck ;;
    track) kk_redeploy_track ;;
    vector) kk_redeploy_vector ;;
    verdict) kk_redeploy_verdict ;;
    *) printf 'usage: %s redeploy recheck|track|vector|verdict\n' "${0##*/}" >&2; return 64 ;;
  esac
}

# ---------------------------------------------------------------------------------------------------------------------------
# CLEAR (egress only, #11920): once the vector leg has confirmed every host on the fresh frame, plan+apply the -replace
# of doppler_secret.egress_audit_ingest_token_previous with the var default "" — the honest cleared sentinel (the ingest
# route skips empty values). The plan is gated on exactly that one row; the write goes through the same kr_tf
# chokepoint. Post-verify reads PREVIOUS value-silently: it must be absent or empty, else the old token would stay
# accepted silently — a non-success (previous_not_cleared) retains PREVIOUS only as a diagnosis, never as an outcome.
kk_cmd_clear() {
  local key="${EFF_KEY:-}" rc=0 want cls s try
  [[ "${EFF_MODE:-}" == rotate && "$key" == egress_audit_ingest_token ]] || { kr_refuse internal_error "clear runs for egress rotate only"; return 1; }
  kk_valid_inputs rotate "$key" || return 1
  kr_init || return 1
  if ! kk_require_attempt; then
    kr_post_write_failure previous_not_cleared "the clear leg re-run was refused (${KR_CHECK_TOKEN}); PREVIOUS stays set and the old token remains accepted" "The PREVIOUS clear did not run."
    return 1
  fi
  if ! kk_recheck "$key" 0 redeploy; then
    kr_post_write_failure previous_not_cleared "the clear leg could not start (${KR_CHECK_TOKEN}: ${KR_CHECK_DETAIL}); PREVIOUS stays set and the old token remains accepted" "The PREVIOUS clear did not run."
    return 1
  fi
  if ! kr_tf_prepare; then
    kk_tf_clean
    kr_post_write_failure previous_not_cleared "the init could not start the clear (verdict ${KR_VERDICT:-terraform_failed}); PREVIOUS stays set" "The PREVIOUS clear did not run."
    return 1
  fi
  # one-row want: the PREVIOUS row delete,create by the requested replace, nothing else. The address comes out of the
  # gate table (B19: no resource literal outside it) and the flags through the one -target/-replace construction site.
  local prow pa targets=() repls=()
  prow="$(kr_gate_rows B "$key" | grep 'previous' || true)"
  [[ -n "$prow" ]] || { kr_refuse internal_error "the gate table carries no PREVIOUS row for $key"; return 1; }
  IFS='|' read -r _ _ pa _ _ <<<"$prow"
  mapfile -t targets < <(kr_gate_targets B "$key" | grep "=$pa\$")
  mapfile -t repls < <(kr_gate_replaces B "$key" | grep "=$pa\$")
  want="$(jq -cn --arg a "$pa" '[{address:$a,actions:["delete","create"],recovery:false,replace:true,recover:false}]')"
  # the TF_VAR shadow (the kk_egress_previous_feed precedent, env only, never argv): kr_tf wraps every call in
  # `doppler run --name-transformer tf-var`, which injects EVERY name of soleur/prd_terraform as TF_VAR_*; a stale
  # EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS copy there would feed the OLD token to the PREVIOUS variable and the replace
  # create would rewrite it (#12299). Under --preserve-env an exported name wins even when empty, so the clear
  # exports the cleared sentinel itself.
  export TF_VAR_egress_audit_ingest_token_previous=""
  rc=0
  kr_tf "plan-clear" plan -no-color -input=false -out="$KR_TMP/tfplan-clear" -var="ssh_key_path=${KR_TMP}/ci_ssh_key.pub" \
    "${targets[@]}" "${repls[@]}" || rc=$?
  if [[ "$rc" != 0 ]]; then
    cls="$(kk_tf_class "plan-clear" "$rc")"; kk_tf_clean
    kr_post_write_failure terraform_failed "the clear plan step exited ${rc} (cause class: ${cls}); its output was deleted from the runner; PREVIOUS stays set" "The PREVIOUS clear could not be planned."
    return 1
  fi
  rc=0
  KR_TF_T="$KK_TF_SHOW_S" kr_tf "show-clear" show -json "$KR_TMP/tfplan-clear" || rc=$?
  if [[ "$rc" != 0 ]]; then
    cls="$(kk_tf_class "show-clear" "$rc")"; kk_tf_clean
    kr_post_write_failure terraform_failed "the clear plan-to-JSON step exited ${rc} (cause class: ${cls}); its output was deleted from the runner; PREVIOUS stays set" "The PREVIOUS clear could not be gated."
    return 1
  fi
  local proj="$KR_TMP/proj-clear.json"
  ( umask 077; jq -c "$KK_PROJECT_JQ" "$KR_TMP/tf-show-clear.out" > "$proj" 2>/dev/null ) || rc=$?
  kk_tf_clean keep-plan
  if [[ "$rc" != 0 || ! -s "$proj" ]] || ! jq -e 'type == "array"' "$proj" >/dev/null 2>&1; then
    kk_tf_clean
    kr_post_write_failure terraform_failed "the clear plan projection failed or was empty; the full plan JSON was deleted; PREVIOUS stays set" "The PREVIOUS clear could not be gated."
    return 1
  fi
  if ! kk_gate "$key" "$proj" "$want"; then kk_tf_clean; return 1; fi
  rc=0
  KR_TF_T="$KR_TF_APPLY_S" kr_tf apply apply -no-color -input=false "$KR_TMP/tfplan-clear" || rc=$?
  kk_tf_clean
  if [[ "$rc" != 0 ]]; then
    kr_post_write_failure apply_failed "the clear apply exited ${rc}; its output was deleted from the runner; PREVIOUS may be absent, populated or unchanged" "The PREVIOUS clear failed part-way."
    return 1
  fi
  # post-verify (the value is read through a pipe into sha256sum only): PREVIOUS must be absent or empty. Doppler reads
  # can lag the write, so the same retry shape as the post-state read applies.
  for ((try = 1; try <= KK_RETRIES; try++)); do
    s="$(kk_copy_state soleur prd EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS)"
    case "$s" in
      absent|unknown:read_empty|unknown:listing_empty)
        kr_ok rotate_ok "key=${key}; the PREVIOUS clear applied and EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS reads empty or absent"
        return 0 ;;
    esac
    (( try < KK_RETRIES )) && kr_sleep "$KK_RETRY_SLEEP_S"
  done
  kr_post_write_failure previous_not_cleared "after the clear apply, EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS still reads ${s:-unknown}; the old token stays accepted" "The PREVIOUS clear applied but the token did not empty."
  return 1
}

# ---------------------------------------------------------------------------------------------------------------------------
# NOTIFY: the ONLY job with issues:write. Files the one action-required issue after a write that did not end green, and closes a key's
# earlier open key-rotate issues on rotate_ok (never the owner_step_pending ones, which the owner closes after the update).
kk_norm_result() { case "${1:-}" in success|failure|cancelled|skipped) printf '%s' "$1" ;; *) printf 'unknown' ;; esac; }

# tokens an apply can end with BEFORE the write: a refusal files nothing. internal_error is one of them only here, where notify has
# already established that the apply exported no write_started=true.
kk_prewrite_token() {
  case "$1" in
    rerun_refused|authorization_stale|credential_absent|copy_unreadable|plan_gate_refused|replace_not_requested|terraform_failed|run_in_flight|run_list_unreadable|kb_drift_cron_window|kb_drift_walker_in_flight|inputs_invalid|internal_error|approval_environment_unprotected) return 0 ;;
  esac
  return 1
}

kk_close_earlier() { # <key>: closes only issues whose title run number is LESS than this run's (never a later run's issue)
  local repo="${GITHUB_REPOSITORY:-}" list num me="${GITHUB_RUN_ID:-}"
  [[ "$me" =~ ^[0-9]+$ ]] || { printf '::warning::key-rotate: the run id is unknown; no earlier issue closed\n' >&2; return 0; }
  list="$(gh issue list --repo "$repo" --label action-required --state open --limit "$KK_ISSUE_LIMIT" --json number,title 2>/dev/null)" \
    || { printf '::warning::key-rotate: could not list earlier key-rotate issues; none closed\n' >&2; return 0; }
  while IFS= read -r num; do
    [[ "$num" =~ ^[0-9]+$ ]] || continue
    gh issue close "$num" --repo "$repo" --comment "Superseded by a confirmed rotation of ${1} (run ${me})." >/dev/null 2>&1 \
      || printf '::warning::key-rotate: could not close earlier issue #%s; close it by hand\n' "$num" >&2
  done < <(jq -r --arg k "$1" --argjson me "$me" '.[] | select((.title | test("^key-rotate " + $k + " [a-z_]+ \\(run [0-9]+\\)$")) and ((.title | startswith("key-rotate " + $k + " owner_step_pending ")) | not)
      and ((.title | capture("\\(run (?<n>[0-9]+)\\)$").n | tonumber) < $me)) | .number' <<<"$list" 2>/dev/null)
  return 0
}

kr_cmd_notify() {
  local mode="${EFF_MODE:-}" key="${EFF_KEY:-}" ra rr rcr av rv cv ws wrote=0 tok what
  [[ "$mode" == rotate ]] || { kk_say "key-rotate: notify has nothing to report for mode '${mode:-}'"; return 0; }
  kk_valid_inputs rotate "$key" || return 1
  ra="$(kk_norm_result "${EFF_RESULT_APPLY:-}")"; rr="$(kk_norm_result "${EFF_RESULT_REDEPLOY:-}")"; rcr="$(kk_norm_result "${EFF_RESULT_CLEAR:-}")"
  av="${EFF_APPLY_VERDICT:-}"; rv="${EFF_REDEPLOY_VERDICT:-}"; cv="${EFF_CLEAR_VERDICT:-}"; ws="${EFF_WRITE_STARTED:-}"
  kr_init || return 1
  if [[ "$rr" == success && "$rv" == rotate_ok ]]; then kk_close_earlier "$key"; return 0; fi
  # egress only: the terminal green is the CLEAR leg's rotate_ok (vector_restarted is the interim marker)
  if [[ "$key" == egress_audit_ingest_token && "$rr" == success && "$rv" == vector_restarted && "$rcr" == success && "$cv" == rotate_ok ]]; then kk_close_earlier "$key"; return 0; fi
  [[ "$ra" == skipped ]] && { kk_say "key-rotate: the apply job was skipped; nothing was written"; return 0; }
  case "$ra" in success|cancelled|unknown) wrote=1 ;; esac
  [[ "$ws" == true ]] && wrote=1
  if [[ "$ra" == failure && "$wrote" == 0 ]]; then
    if [[ "$av" == partial_absent_state ]]; then wrote=1
    elif [[ -z "$av" ]] || ! kk_prewrite_token "$av"; then wrote=1; fi
  fi
  if [[ "$wrote" == 0 ]]; then kk_say "key-rotate: no write happened (apply=${ra}); nothing to report"; return 0; fi
  if [[ "$rcr" == failure || "$rcr" == cancelled ]] && kr_token_known "$cv"; then tok="$cv"
  elif [[ "$rr" == failure || "$rr" == cancelled ]] && kr_token_known "$rv" && [[ "$rv" != rotate_ok ]]; then tok="$rv"
  elif [[ "$ra" == failure ]] && kr_token_known "$av"; then tok="$av"
  else tok=job_cancelled; fi
  what="A job after the first write ended without a stop sentence of its own (apply=${ra} redeploy=${rr} clear=${rcr})."
  [[ -z "$ws" ]] && what="${what} (no write_started marker seen from the apply job: a write may or may not have happened)"
  [[ "$tok" == owner_step_pending ]] && what="The rotation landed and the fleet redeploy was confirmed."
  KR_VERDICT="$tok"
  kr_file_issue "$tok" "$(kr_stop_sentence "$what" | KR_SCRUB_CAP=1400 kr_scrub)$(kk_stop_tail)" || return 1
  [[ "$tok" == owner_step_pending ]] && kk_close_earlier "$key"
  return 0
}

main() {
  case "${1:-}" in
    --print-contract) kr_print_contract ;;
    precondition) kk_cmd_precondition ;;
    guard) kk_cmd_guard ;;
    apply) kk_cmd_apply ;;
    redeploy) kk_cmd_redeploy "${2:-}" ;;
    clear) kk_cmd_clear ;;
    notify) kr_cmd_notify ;;
    *) printf 'usage: %s --print-contract|precondition|guard|apply|redeploy recheck|track|vector|verdict|clear|notify\n' "${0##*/}" >&2; return 64 ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; exit $?; fi
