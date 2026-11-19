#!/usr/bin/env bash
# cf-account-migrate-job.sh — the body of .github/workflows/cf-account-migrate.yml (#12931).
# Runbook: knowledge-base/engineering/operations/runbooks/cloudflare-account-migration.md.
#
# Environment:
#   MIGRATE_PHASE   one of cf_account_migrate_phases (tests/scripts/lib/cf-account-migrate-gate.sh)
#   CONFIRM         exactly MIGRATE-CF-<phase> (typo-guard; the environment approval authorizes)
#   REHEARSAL       true | false
#   REASON          non-blank audit text
#   GITHUB_WORKSPACE, RUNNER_TEMP, INFRA_DIR (absolute, or relative to the workspace)
#   R2_ENDPOINT     optional; when set it must equal the pinned state endpoint (R2_ENDPOINT_PINNED),
#                   which is what every R2 call here and the state-forget use
#   GH_TOKEN, GH_REPO   read of in-flight runs; DOPPLER_TOKEN   prd_terraform read for `doppler run`
#   CFAM_VERIFY_TRIES, CFAM_VERIFY_SLEEP   optional post-apply probe budget (default 12 x 10s;
#                   integers, tries 1-60, pause 0-60 s, anything else refuses)
# Test seams of the sourced libraries (CFAM_IMPORTS_FILE) are unset before sourcing: the gate
# compares imports against the COMMITTED file only.
#
# Order: inputs -> no run in flight on any gated workflow -> Doppler resolves the NEW ids ->
# init. Rehearsal: a scratch copy of the root on a local backend runs the real state-forget
# (--rehearsal) and the plan and both gates, never applies, then asserts the remote state serial
# and the web-platform/backups/ listing are unchanged. Apply: state-forget (redirects-dns only),
# plan with the gate's -target/-replace lists, phase gate, then the whole-list entrypoint gate
# (ADR-136, CTO D2: a ruleset create is a whole-list PUT over the live phase entrypoint), apply
# the graded tfplan only when both PASS, verify.
#
# Prints verdict lines and addresses only; terraform output goes through tf_redact_random_ids.
# Exit: 0 ok, 1 refused or failed, 2 setup error.
set -uo pipefail
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac
umask 077

readonly P="cf-account-migrate"
readonly STATE_BUCKET="soleur-terraform-state"
readonly BACKUP_PREFIX="web-platform/backups/"
# The legacy-account R2 endpoint that holds the state bucket (main.tf backend). A credentialed
# request's destination is pinned, never taken from the environment (#7873).
readonly R2_ENDPOINT_PINNED="https://4d5ba6f096b2686fbdd404167dd4e125.r2.cloudflarestorage.com"
readonly PREDICATE_REL="apps/web-platform/infra/scripts/cf-account-migration-complete.sh"
readonly LIVE_STATUSES=(queued in_progress waiting pending requested)

W=""
ROOT=""
TARGET_ARGS=()
REPLACE_ARGS=()
GATED=()

refuse() { # <reason-code> <message>
  printf '%s phase=%s verdict=refuse reason=%s\n' "$P" "${MIGRATE_PHASE:-?}" "$1"
  printf '::error title=%s::%s\n' "$P" "$2"
  summary "verdict=refuse reason=$1"
  exit 1
}

summary() {
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    printf -- '- %s phase=%s rehearsal=%s %s\n' "$P" "${MIGRATE_PHASE:-?}" "${REHEARSAL:-?}" "$1" >>"$GITHUB_STEP_SUMMARY"
  fi
}

# reason_line: the operator's reason as ONE printable line for the audit trail: C0 controls, DEL,
# U+2028/U+2029, "::" (workflow-command openers) and markdown-active characters become spaces;
# at most 200 bytes.
reason_line() {
  local r
  r="$(printf '%s' "${REASON:-}" | LC_ALL=C tr '\000-\037\177' '  ' \
    | LC_ALL=C sed -e 's/\xe2\x80[\xa8\xa9]/ /g' -e 's/::*/:/g' -e 's/[][`<>|*_#]/ /g' | LC_ALL=C tr -s ' ')"
  r="${r# }"
  LC_ALL=C printf '%.200s' "$r"
}

# shellcheck disable=SC2329 # invoked by the EXIT trap
cleanup() { if [[ -n "$W" && -d "$W" ]]; then rm -rf "$W"; fi; }

# tf_env <cmd...>: run with the prd_terraform TF_VARs; values the loader exported win (--preserve-env).
# TF_LOG* are stripped INSIDE doppler run, so neither the loader's $GITHUB_ENV export nor a Doppler
# key can turn on provider/state logging (it would print secrets).
tf_env() {
  doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- \
    env -u TF_LOG -u TF_LOG_PATH -u TF_LOG_CORE -u TF_LOG_PROVIDER "$@"
}
# tf_env_bounded <seconds> <cmd...>: tf_env for a short read; rc 124 when Doppler stalls.
tf_env_bounded() {
  local t="$1"; shift
  timeout "$t" doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- \
    env -u TF_LOG -u TF_LOG_PATH -u TF_LOG_CORE -u TF_LOG_PROVIDER "$@"
}

# r2_aws <aws args...>: the ONE R2 aws prefix (region, checksum mode, no IMDS) and a 60 s bound.
r2_aws() {
  timeout 60 env AWS_DEFAULT_REGION=auto AWS_REQUEST_CHECKSUM_CALCULATION=when_required \
    AWS_RESPONSE_CHECKSUM_VALIDATION=when_required AWS_EC2_METADATA_DISABLED=true aws "$@"
}

load_libs() {
  [[ -n "${GITHUB_WORKSPACE:-}" ]] || { printf '%s: GITHUB_WORKSPACE is not set\n' "$P" >&2; exit 2; }
  local lib="$GITHUB_WORKSPACE/tests/scripts/lib"
  # The gate's imports-file override is a test seam; production grades against the committed file.
  unset CFAM_IMPORTS_FILE
  # shellcheck source=/dev/null
  source "$lib/cf-account-migrate-gate.sh" || { printf '%s: cannot source the phase gate\n' "$P" >&2; exit 2; }
  # shellcheck source=/dev/null
  source "$lib/tf-redact-random-ids.sh" || { printf '%s: cannot source tf-redact-random-ids\n' "$P" >&2; exit 2; }
}

validate_inputs() {
  local phases
  # Captured, not piped into `grep -q`: under pipefail an early grep exit SIGPIPEs the producer.
  phases="$(cf_account_migrate_phases)" || refuse unknown-phase "cannot read the gate's phase list"
  grep -qxF -- "${MIGRATE_PHASE:-}" <<<"$phases" \
    || refuse unknown-phase "migrate_phase must be one of: $(tr '\n' ' ' <<<"$phases")"
  [[ "${CONFIRM:-}" == "MIGRATE-CF-${MIGRATE_PHASE}" ]] \
    || refuse bad-confirm "confirm must be exactly MIGRATE-CF-${MIGRATE_PHASE}. It is a typo-guard; the environment approval is the authorization."
  [[ "${REHEARSAL:-}" == true || "${REHEARSAL:-}" == false ]] || refuse bad-rehearsal "rehearsal must be true or false"
  [[ -n "${REASON//[[:space:]]/}" ]] || refuse no-reason "reason is required"
  local v
  for v in RUNNER_TEMP INFRA_DIR; do
    [[ -n "${!v:-}" ]] || refuse missing-env "$v is not set"
  done
  if [[ -n "${R2_ENDPOINT:-}" && "$R2_ENDPOINT" != "$R2_ENDPOINT_PINNED" ]]; then
    refuse r2-endpoint-not-pinned "R2_ENDPOINT is set to something other than the pinned state endpoint; refusing to send state or credentials there"
  fi
  # The state-forget reads R2_ENDPOINT from the environment: hand it the pinned value only.
  export R2_ENDPOINT="$R2_ENDPOINT_PINNED"
  # Integers only: the budget feeds bash arithmetic, where an array subscript would run a command.
  [[ "${CFAM_VERIFY_TRIES:-12}" =~ ^([1-9]|[1-5][0-9]|60)$ && "${CFAM_VERIFY_SLEEP:-10}" =~ ^([0-9]|[1-5][0-9]|60)$ ]] \
    || refuse bad-verify-budget "CFAM_VERIFY_TRIES must be 1-60 and CFAM_VERIFY_SLEEP 0-60 (integers)"
  summary "reason=$(reason_line)"
}

# gated_workflows: every workflow that calls ./.github/actions/infra-credentials and is NOT in the
# predicate's CFAM_EXEMPT_WORKFLOWS (CTO D1). The exempt list is read from the predicate itself,
# in a child shell (both scripts declare a readonly P), so there is no second copy to drift.
gated_workflows() {
  local exempt f base
  # shellcheck disable=SC2016 # expanded by the child bash
  exempt="$(bash -c 'source "$1" && printf "%s\n" "${CFAM_EXEMPT_WORKFLOWS[@]}"' _ "$GITHUB_WORKSPACE/$PREDICATE_REL" 2>/dev/null)" \
    || refuse runs-unreadable "cannot read CFAM_EXEMPT_WORKFLOWS from $PREDICATE_REL"
  [[ -n "${exempt//[[:space:]]/}" ]] || refuse runs-unreadable "the predicate's exempt workflow list is empty"
  for f in "$GITHUB_WORKSPACE"/.github/workflows/*.yml "$GITHUB_WORKSPACE"/.github/workflows/*.yaml; do
    [[ -f "$f" ]] || continue
    awk '/^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*\.\/\.github\/actions\/infra-credentials\/?[[:space:]]*(#.*)?$/ {found=1} END {exit !found}' "$f" || continue
    base="${f##*/}"
    grep -qxF -- "$base" <<<"$exempt" && continue
    GATED+=("$base")
  done
  [[ "${#GATED[@]}" -gt 0 ]] || refuse runs-unreadable "no gated workflow found under .github/workflows (the derivation is broken)"
}

# A queued or approval-waiting run still executes later, against state this job is rewriting.
refuse_inflight() {
  local wf st n rc busy=0
  gated_workflows
  for wf in "${GATED[@]}"; do
    for st in "${LIVE_STATUSES[@]}"; do
      rc=0
      n="$(timeout 30 gh run list --workflow "$wf" --status "$st" --limit 50 --json databaseId --jq 'length' 2>/dev/null)" || rc=$?
      [[ "$rc" -ne 124 ]] || refuse runs-timeout "gh run list for $wf (status $st) did not answer within 30 s; cannot prove no run is in flight"
      [[ "$rc" -eq 0 ]] || refuse runs-unreadable "gh run list failed for $wf (status $st); cannot prove no run is in flight"
      [[ "$n" =~ ^[0-9]+$ ]] || refuse runs-unreadable "gh run list for $wf (status $st) returned a non-count"
      if [[ "$n" -gt 0 ]]; then
        printf '%s inflight workflow=%s status=%s count=%s\n' "$P" "$wf" "$st" "$n"
        busy=1
      fi
    done
  done
  [[ "$busy" -eq 0 ]] || refuse run-in-flight "a run of a gated workflow is queued, waiting or running; let it finish or cancel it, then re-dispatch"
  printf '%s inflight=none workflows=%s\n' "$P" "${#GATED[@]}"
}

# Guard 4 fails the plan on an old id, but the redirects-dns forget runs BEFORE the plan, so the
# values Terraform will see are checked first, exactly as `doppler run` resolves them (CTO D8
# keeps this preflight for the migrate job). Checked: the NEW zone and account ids; R2 stays on
# the LEGACY account; and every provider token the phase uses (cf_account_migrate_phase_tokens)
# answers 200 on one GET against the NEW zone or account. No id or token is printed: a token
# reaches curl on its stdin config channel, and only the HTTP code comes back.
readonly R2_ACCOUNT_OLD="4d5ba6f096b2686fbdd404167dd4e125"
readonly CF_API="https://api.cloudflare.com/client/v4"
# The read probe per token, inside that token's own grant (the read half of what it edits).
token_probe_path() {
  case "$1" in
    cf_api_token) printf 'zones/%s/dns_records?per_page=1' "$CFAM_NEW_ZONE_ID" ;;
    cf_api_token_rulesets) printf 'zones/%s/rulesets' "$CFAM_NEW_ZONE_ID" ;;
    cf_api_token_pages) printf 'accounts/%s/pages/projects' "$CFAM_NEW_ACCOUNT_ID" ;;
    cf_api_token_zone_settings) printf 'zones/%s/settings' "$CFAM_NEW_ZONE_ID" ;;
    cf_api_token_bot_management) printf 'zones/%s/bot_management' "$CFAM_NEW_ZONE_ID" ;;
    *) return 1 ;;
  esac
}
# Runs INSIDE doppler run: prints zone, account, r2 account, then "tok <name> <http-code>" per
# <name> <url> pair. A token of an unusable shape (a quote or newline would inject a curl config
# directive) is never sent and reads "bad".
# shellcheck disable=SC2016 # expanded by the inner bash
readonly PREFLIGHT_SH='
printf "%s\n%s\n%s\n" "${TF_VAR_cf_zone_id:-}" "${TF_VAR_cf_account_id:-}" "${TF_VAR_cf_r2_account_id:-}"
while [ "$#" -ge 2 ]; do
  n="$1"; u="$2"; shift 2
  v="TF_VAR_$n"; t="${!v:-}"
  case "$t" in ""|*[!A-Za-z0-9._~+/=-]*) printf "tok %s bad\n" "$n"; continue ;; esac
  c="$(curl --disable --noproxy "*" -sS -o /dev/null --max-time 10 -w "%{http_code}" --config - "$u" 2>/dev/null \
       < <(printf "header = \"Authorization: Bearer %s\"\n" "$t"))" || c="000"
  printf "tok %s %s\n" "$n" "${c:-000}"
done
'
check_ids() {
  local out zone acct r2 rc=0 tokens n path line code bad=0
  local -a pairs=()
  tokens="$(cf_account_migrate_phase_tokens "$MIGRATE_PHASE")" || refuse no-tokens "the gate has no token list for $MIGRATE_PHASE"
  [[ -n "$tokens" ]] || refuse no-tokens "the gate's token list for $MIGRATE_PHASE is empty"
  while IFS= read -r n; do
    path="$(token_probe_path "$n")" || refuse no-tokens "no read probe is defined for token $n"
    pairs+=("$n" "$CF_API/$path")
  done <<<"$tokens"
  out="$(tf_env_bounded 60 bash -c "$PREFLIGHT_SH" _ "${pairs[@]}" 2>/dev/null)" || rc=$?
  [[ "$rc" -ne 124 ]] || refuse ids-timeout "doppler run did not resolve the ids and token probes within 60 s"
  [[ "$rc" -eq 0 ]] || refuse ids-unreadable "doppler run could not resolve cf_zone_id / cf_account_id"
  zone="$(sed -n 1p <<<"$out" | tr 'A-F' 'a-f')"
  acct="$(sed -n 2p <<<"$out" | tr 'A-F' 'a-f')"
  r2="$(sed -n 3p <<<"$out" | tr 'A-F' 'a-f')"
  [[ "$zone" == "$CFAM_NEW_ZONE_ID" ]] \
    || refuse zone-id-not-new "cf_zone_id does not resolve to the Soleur-account zone (Doppler still holds the OLD id, or none). Do the runbook Phase 2 flip first. Nothing was written."
  [[ "$acct" == "$CFAM_NEW_ACCOUNT_ID" ]] \
    || refuse account-id-not-new "cf_account_id does not resolve to the Soleur account (Doppler still holds the OLD id, or none). Do the runbook Phase 2 flip first. Nothing was written."
  [[ "$r2" == "$R2_ACCOUNT_OLD" ]] \
    || refuse r2-account-not-old "cf_r2_account_id does not resolve to the legacy account that holds R2 (ADR-329: R2 never moves). Nothing was written."
  while IFS= read -r n; do
    line="$(awk -v n="$n" '$1 == "tok" && $2 == n {print $3; exit}' <<<"$out")"
    code="${line:-missing}"
    printf '%s preflight=token name=%s http=%s\n' "$P" "$n" "$code"
    [[ "$code" == 200 ]] || bad=1
  done <<<"$tokens"
  [[ "$bad" -eq 0 ]] || refuse token-not-new-zone "a provider token for $MIGRATE_PHASE did not answer 200 on the NEW zone/account (see the preflight=token lines): swap or re-mint it (runbook Phase 0/2). Nothing was written."
  printf '%s preflight=ids verdict=ok tokens=%s\n' "$P" "$(grep -c . <<<"$tokens")"
}

build_args() {
  local t r
  t="$(cf_account_migrate_targets "$MIGRATE_PHASE")" || refuse no-targets "the gate has no target list for $MIGRATE_PHASE"
  [[ -n "$t" ]] || refuse no-targets "the gate's target list for $MIGRATE_PHASE is empty"
  mapfile -t TARGET_ARGS <<<"$t"
  r="$(cf_account_migrate_replaces "$MIGRATE_PHASE")" || refuse no-targets "the gate has no replace list for $MIGRATE_PHASE"
  if [[ -n "$r" ]]; then mapfile -t REPLACE_ARGS <<<"$r"; fi
  printf '%s targets=%d replaces=%d\n' "$P" "${#TARGET_ARGS[@]}" "${#REPLACE_ARGS[@]}"
}

# entrypoint_gate: tests/scripts/lib/preapply-entrypoint-gate.sh --gate on the graded plan, in
# zone-list control mode (the new zone may be empty, so no phase is known-populated), bound to the
# NEW zone constant. The rulesets token reaches the gate through the environment, never argv; the
# gate's own test seams are stripped.
entrypoint_gate() {
  # shellcheck disable=SC2016 # expanded by the inner bash, inside doppler run
  tf_env env -u PREAPPLY_ENTRYPOINT_FETCH -u PREAPPLY_INFRA_DIR -u PREAPPLY_CF_MAX_TIME -u PREAPPLY_CF_ACCOUNT_ID \
    PREAPPLY_CONTROL=zone-list PREAPPLY_CF_ZONE_ID="$CFAM_NEW_ZONE_ID" \
    bash -c 'export PREAPPLY_CF_TOKEN="${TF_VAR_cf_api_token_rulesets:-}"; exec bash "$1" --gate "$2"' \
    _ "$GITHUB_WORKSPACE/tests/scripts/lib/preapply-entrypoint-gate.sh" "$W/tfplan.json" 2>&1
}

serial_of() { jq -er 'if (.serial | type) == "number" then .serial else error("no serial") end' "$1" 2>/dev/null; }

# pull_remote <out-file>: the remote state, read through the real root's backend.
pull_remote() { (cd "$ROOT" && terraform state pull) >"$1" 2>/dev/null && [[ -s "$1" ]]; }

# list_backups: the sorted key list under the backup prefix. rc 124 = the listing timed out.
list_backups() {
  local rc=0
  r2_aws s3api list-objects-v2 --bucket "$STATE_BUCKET" --prefix "$BACKUP_PREFIX" \
    --endpoint-url "$R2_ENDPOINT_PINNED" --output json >"$W/backups.json" 2>/dev/null || rc=$?
  [[ "$rc" -eq 0 ]] || return "$rc"
  jq -sc '[.[0].Contents[]?.Key] | sort' "$W/backups.json" 2>/dev/null
}

# backups_or_refuse <when>: list_backups into BK, refusing with a named reason on a timeout or a
# failure (in THIS shell, so the verdict line reaches the log).
BK=""
backups_or_refuse() {
  local rc=0
  BK="$(list_backups)" || rc=$?
  [[ "$rc" -ne 124 ]] || refuse backups-timeout "listing s3://$STATE_BUCKET/$BACKUP_PREFIX ($1) did not finish within 60 s"
  [[ "$rc" -eq 0 ]] || refuse backups-unreadable "cannot list s3://$STATE_BUCKET/$BACKUP_PREFIX ($1); the no-write assertion needs it"
}

state_migrate() { # [--rehearsal --backup-dir <dir>]; runs in the current directory
  bash "$GITHUB_WORKSPACE/apps/web-platform/infra/scripts/cf-account-state-migrate.sh" \
    --new-zone "$CFAM_NEW_ZONE_ID" --new-account "$CFAM_NEW_ACCOUNT_ID" "$@"
}

# plan_and_gate: in the current directory. Writes $W/tfplan; returns 0 only on phase-gate
# verdict=PASS AND an entrypoint-gate PASS; 2 when the entrypoint gate refused, 1 otherwise.
plan_and_gate() {
  local rc out
  terraform show -json >"$W/pre-plan-state.json" 2>/dev/null || { printf '::error::terraform show -json (pre-plan state) failed\n'; return 1; }
  tf_env terraform plan -no-color -input=false -out="$W/tfplan" \
    -var="ssh_key_path=$W/ci_ssh_key.pub" "${TARGET_ARGS[@]}" ${REPLACE_ARGS[@]+"${REPLACE_ARGS[@]}"} 2>&1 | tf_redact_random_ids
  rc=${PIPESTATUS[0]}
  if [[ "$rc" -ne 0 ]]; then
    printf '::error title=%s::terraform plan failed (exit %s). If the output names cf_zone_id or cf_account_id, Doppler still holds an OLD id (Guard 4).\n' "$P" "$rc"
    return 1
  fi
  terraform show -json "$W/tfplan" >"$W/tfplan.json" 2>/dev/null || { printf '::error::terraform show -json tfplan failed\n'; return 1; }
  out="$(cf_account_migrate_gate "$MIGRATE_PHASE" "$W/tfplan.json" "$W/pre-plan-state.json")"; rc=$?
  printf '%s\n' "$out"
  summary "$(grep -E '^cf_account_migrate_gate: phase=' <<<"$out" | tail -n1)"
  [[ "$rc" -eq 0 ]] && grep -qE "^cf_account_migrate_gate: phase=${MIGRATE_PHASE} verdict=PASS " <<<"$out" || return 1
  if ! entrypoint_gate; then
    printf '%s entrypoint-gate verdict=refuse\n' "$P"
    return 2
  fi
  printf '%s entrypoint-gate verdict=PASS\n' "$P"
  summary "entrypoint-gate verdict=PASS"
}

run_rehearsal() {
  local scratch="$W/scratch" before after b_before b_after rc
  backups_or_refuse before; b_before="$BK"
  mkdir -p "$scratch" "$W/backup" || refuse scratch-failed "cannot create the scratch root"
  pull_remote "$W/pull.tfstate" || refuse state-pull-failed "terraform state pull failed"
  before="$(serial_of "$W/pull.tfstate")" || refuse state-pull-failed "pulled state has no numeric serial"
  tar -C "$ROOT" --exclude=./.terraform -cf - . | tar -C "$scratch" -xf - || refuse scratch-failed "cannot copy the root"
  rm -rf "$scratch/.terraform"
  printf 'terraform {\n  backend "local" {\n    path = "rehearsal.tfstate"\n  }\n}\n' >"$scratch/backend_override.tf"
  mv "$W/pull.tfstate" "$scratch/rehearsal.tfstate" || refuse scratch-failed "cannot seed the local state"
  (
    cd "$scratch" || exit 1
    terraform init -input=false -reconfigure -lockfile=readonly -no-color >/dev/null 2>&1 \
      || { printf '::error::terraform init (scratch root, local backend) failed\n'; exit 1; }
    if [[ "$MIGRATE_PHASE" == redirects-dns ]]; then
      state_migrate --rehearsal --backup-dir "$W/backup" || exit 1
    fi
    plan_and_gate
  )
  rc=$?
  # The no-write assertions run whatever the rehearsal body did.
  # (rc 2: the entrypoint gate refused; any other non-zero: the forget or the phase gate.)
  pull_remote "$W/after.tfstate" || refuse state-pull-failed "terraform state pull (after) failed"
  after="$(serial_of "$W/after.tfstate")" || refuse state-pull-failed "post-rehearsal state has no numeric serial"
  rm -f "$W/after.tfstate"
  [[ "$after" == "$before" ]] || refuse remote-serial-changed "the remote state serial went $before -> $after during a rehearsal"
  backups_or_refuse after; b_after="$BK"
  [[ "$b_after" == "$b_before" ]] || refuse backup-written "a new object appeared under $BACKUP_PREFIX during a rehearsal"
  printf '%s rehearsal remote_serial=%s serial_unchanged=true backups_unchanged=true\n' "$P" "$before"
  [[ "$rc" -ne 2 ]] || refuse entrypoint-gate-refused "the whole-list entrypoint gate refused (a live phase entrypoint is populated, or its emptiness could not be proven); see the ::error lines above. Nothing was written."
  [[ "$rc" -eq 0 ]] || refuse rehearsal-refused "the rehearsal did not reach gate verdict=PASS (see above); nothing was written"
  printf '%s phase=%s mode=rehearsal verdict=PASS applied=false\n' "$P" "$MIGRATE_PHASE"
  summary "verdict=PASS applied=false"
}

probe() { # <url> [<user-agent>]: prints "<code> <redirect_url>"
  local -a ua=()
  [[ -n "${2:-}" ]] && ua=(-A "$2")
  curl -sS -o /dev/null --max-time 15 -w '%{http_code} %{redirect_url}' ${ua[@]+"${ua[@]}"} "$1" 2>/dev/null
}

verify_redirects_dns() {
  local tries="${CFAM_VERIFY_TRIES:-12}" pause="${CFAM_VERIFY_SLEEP:-10}" i bad u hdrs
  for ((i = 1; i <= tries; i++)); do
    bad=""
    for u in https://soleur.ai/pages/agents.html https://soleur.ai/pages/legal/privacy-policy.html \
      https://soleur.ai/blog/2026-03-16-soleur-vs-anthropic-cowork/; do
      [[ "$(probe "$u")" == 301\ * ]] || bad+=" $u"
    done
    [[ "$(probe https://www.soleur.ai/)" == "301 https://soleur.ai/" ]] || bad+=" https://www.soleur.ai/"
    [[ "$(probe https://soleur.ai/ 'Mozilla/5.0 (compatible; GPTBot/1.2)')" == 200\ * ]] || bad+=" gptbot"
    hdrs="$(curl -sS -o /dev/null -D - --max-time 15 https://app.soleur.ai/ 2>/dev/null)"
    grep -qiE '^x-robots-tag:.*noindex' <<<"$hdrs" || bad+=" app-noindex"
    # The same apply creates the app's ssl=strict config rule: prove the product still serves.
    [[ "$(probe https://app.soleur.ai/health)" == 200\ * ]] || bad+=" app-health"
    if [[ -z "$bad" ]]; then printf '%s verify=redirects-dns verdict=ok\n' "$P"; return 0; fi
    [[ "$i" -lt "$tries" ]] && sleep "$pause"
  done
  printf '%s verify=redirects-dns verdict=fail failing=%s\n' "$P" "${bad# }"
  return 1
}

run_apply() {
  local rc
  cd "$ROOT" || refuse setup "cannot cd to the root"
  if [[ "$MIGRATE_PHASE" == redirects-dns ]]; then
    state_migrate || refuse state-migrate-failed "the state forget did not finish with verdict=ok (see above)"
  fi
  plan_and_gate; rc=$?
  [[ "$rc" -ne 2 ]] || refuse entrypoint-gate-refused "the whole-list entrypoint gate refused (a live phase entrypoint is populated, or its emptiness could not be proven); adopt it with the printed import block first. Nothing was applied."
  [[ "$rc" -eq 0 ]] || refuse gate-refused "the plan did not reach gate verdict=PASS; nothing was applied"
  tf_env terraform apply -no-color -input=false -auto-approve "$W/tfplan" 2>&1 | tf_redact_random_ids
  rc=${PIPESTATUS[0]}
  [[ "$rc" -eq 0 ]] || refuse apply-failed "terraform apply of the graded plan failed (exit $rc); fix forward and re-dispatch (every phase is idempotent)"
  printf '%s phase=%s mode=apply applied=true\n' "$P" "$MIGRATE_PHASE"
  if [[ "$MIGRATE_PHASE" == redirects-dns ]]; then
    verify_redirects_dns || refuse verify-failed "applied, but the redirect/noindex/crawler/app-health probes did not all pass"
  fi
  printf '%s phase=%s mode=apply verdict=PASS applied=true\n' "$P" "$MIGRATE_PHASE"
  summary "verdict=PASS applied=true"
}

main() {
  # Provider / state debug logging prints secrets; nothing this job runs may inherit it.
  unset TF_LOG TF_LOG_PATH TF_LOG_CORE TF_LOG_PROVIDER
  load_libs
  validate_inputs
  refuse_inflight
  W="$RUNNER_TEMP/cf-migrate"
  mkdir -p "$W" || refuse setup "cannot create $W"
  trap cleanup EXIT
  if [[ "$INFRA_DIR" == /* ]]; then ROOT="$INFRA_DIR"; else ROOT="$GITHUB_WORKSPACE/$INFRA_DIR"; fi
  [[ -d "$ROOT" ]] || refuse setup "INFRA_DIR is not a directory"
  build_args
  check_ids
  # The root's file(var.ssh_key_path) is evaluated at plan time; nothing here consumes the key.
  ssh-keygen -t ed25519 -f "$W/ci_ssh_key" -N "" -q || refuse setup "ssh-keygen failed"
  (cd "$ROOT" && terraform init -input=false -lockfile=readonly -no-color >/dev/null 2>&1) \
    || refuse init-failed "terraform init (remote backend) failed"
  if [[ "$REHEARSAL" == true ]]; then run_rehearsal; else run_apply; fi
}

main "$@"
