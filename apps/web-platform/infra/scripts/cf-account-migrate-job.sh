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
#   GH_TOKEN, GH_REPO   read of in-flight runs; DOPPLER_TOKEN   prd_terraform read for `doppler run`
#   DOPPLER_TOKEN_WRITE  tunnel apply only: prd_terraform write for the CI-SSH pair. Moved to a shell
#                   variable and unset first thing in main, so terraform and curl never inherit it.
#   CFAM_VERIFY_TRIES, CFAM_VERIFY_SLEEP, CFAM_VERIFY_DEADLINE   optional post-apply probe budget:
#                   at most TRIES passes (default 12) with a SLEEP pause between them (default 10 s).
#                   Integers: tries 1-60, pause 0-60, deadline 0-1200; anything else refuses.
#   CFAM_EXPECTED_IN_STATE_UPDATES   apply only: the Terraform addresses (space- or comma-separated;
#                   empty = none) the gate may admit as in-state updates. The apply refuses
#                   in-state-updates-unexpected before `applying=true` when the admitted set differs.
#                   A rehearsal prints the admitted set (`in-state-updates admitted=`) to copy from.
#
# VERIFY BOUND (contract). The verify's deadline `end` is the EARLIER of DEADLINE seconds after the
# verify starts (default 600) and VERIFY_CAP - SLEEP - VERIFY_PASS_MAX seconds after this script
# started (bash's SECONDS; VERIFY_CAP = 1500; VERIFY_PASS_MAX is derived: one probe per
# VERIFY_PAIRS entry plus gptbot, app-noindex and app-health, each of at most VERIFY_PROBE_S = 15 s,
# so 7 x 15 = 105 s today). After each failing pass the loop stops when SECONDS >= end; otherwise it
# pauses and starts the next pass, so a pass can START up to one pause after the deadline, never
# later. Hence the verdict line prints by 1500 s (25 min) after the script started, inside the job's
# 30-min timeout-minutes while the steps before this one take under 5 min. Exception: a verify that
# itself starts after 1500 - SLEEP - VERIFY_PASS_MAX s still runs its one pass, and prints at most
# VERIFY_PASS_MAX s after it started. A pass whose app-health reads 525 or 526 ends the loop at once
# (that rule has landed and will not heal while the loop waits); every other failure is retried.
# The apply-failed probe (probe_partial_apply) is the same loop polled on a 60 s deadline. Both
# phases are probed (verify_live): gptbot, app-noindex and app-health always, the redirect pairs on
# redirects-dns only; a zone-rest failure refuses verify-failed applied=true failing=<list> too.
# A failed apply's probe starts only while SECONDS <= VERIFY_CAP - VERIFY_PASS_MAX (1395 s); later it
# is skipped and the refusal carries verify=skipped, so an overrun costs the probe, never the refusal.
# RESIDUALS: bash imports SECONDS from the environment, so a SECONDS set in the step env shifts the
# clock (the workflow sets none; the suite uses it to place the clock near the cap). The pass
# figure assumes curl honours --max-time; process start-up time is not counted.
#
# REFUSAL FIELDS (contract). On a redirects-dns apply (rehearsal=false) every refusal after the
# state forget carries forget=committed (entrypoint-gate-refused, gate-refused,
# in-state-updates-unexpected, apply-budget-exhausted, setup when the apply's workflow-command token
# cannot be created, apply-failed, import-normalize-reread-failed, verify-failed).
# state-migrate-failed carries forget=committed when the forget's output holds its `backup=uploaded`
# marker (the write may have started) or cannot be read, else forget=unknown. apply-failed and
# import-normalize-reread-failed also carry the result of the best-effort public probe (polled on a
# 60 s deadline) as their probe field: verify=ok, verify=skipped or failing=<list>. failing= is always
# the last field and runs to the end of the line, because its list holds spaces.
# `applying=true` is printed just before terraform apply. RESIDUAL: a cancel or a timeout-minutes
# kill prints no refuse line at all; the log markers backup=uploaded, applying=true and applied=true
# are then the test (runbook Halt).
# The message follows the evidence. apply-failed prints its fix-forward sentence only with no reread=
# field or with reread=ok. gate-refused and rehearsal-refused name the runbook's wrong-value bullet when
# the gate output holds a `differs from the live record` line, say `Edit no DNS record and re-rehearse once`
# when every REFUSE line is `live record unreadable`, and keep their usual text for any other refusal.
#
# IMPORT-NORMALIZE (contract, ADR-329). Every redirects-dns and tunnel plan reads all pinned DNS records
# (the tunnel phase pins cloudflare_record.app alone) after the
# plan and before the phase gate, in a rehearsal and an apply, so the gate can admit the one provider
# update (allow_overwrite and content) only against live values. An apply whose phase has no replace
# member (empty REPLACE_ARGS, so redirects-dns even with no admitted record) gets one INT
# `APPLY_DEADLINE - SECONDS` seconds after `doppler run` hands off, so 1100 s of script time plus the
# Doppler fetch (about 80 s worst case per request at CLI defaults). Fewer than APPLY_MIN_START
# (300 s) left refuses apply-budget-exhausted applied=false before applying=true. When the gate
# admitted at least one record, all records are read again after the apply, on success and on
# failure. A difference or an unreadable record refuses import-normalize-reread-failed applied=true
# forget=committed reread=<r> <probe>; an apply-failed refusal carries forget=committed reread=<r>
# <probe> in that order, where <probe> is the probe field above. <r> is ok,
# differs=<addr:field+field,...> (a 404 is <addr>:notfound), unreadable=<addr,...>, or for a mixed
# result differs=<addr:field+field,...>;unreadable=<addr,...>. Any value containing differs= routes to
# runbook Halt, A DNS record may hold a wrong value; an unreadable= value alone routes to No completed
# re-read (halt_pointer). A re-read detects a bad write and does not undo it. The gate's and the
# re-read's own lines print field names, never a record value; terraform's plan and apply output can
# print values (see the last paragraph). zone-rest has no pins, makes no read, and its apply has no
# bound: an INT between the delete and create of its replace would leave the prd secret deleted.
#
# Test seams of the sourced libraries (CFAM_IMPORTS_FILE) are unset before sourcing: the gate
# compares imports against the COMMITTED file only.
#
# TUNNEL PHASE (contract). No state forget. The plan alone sets cf_migration_import_app=true, and on
# a gate PASS the job reads the deploy policy's service token live (deploy_token_check; a refusal is
# deploy-token-refused; plan_and_gate rc 5). The rehearsal grades the pre-delete's pin list with no request and refuses
# predelete-refused while it is not six ids. The apply leg runs cf-tunnel-host-predelete.sh --apply
# BEFORE the plan (plan ruling F5), so a later gate refusal leaves those six records deleted; they
# serve only Error 1000. After the apply it writes the CI-SSH pair to prd_terraform and verifies it
# by digest; a failed write refuses ci-ssh-sync-failed applied=true after the live probes have run.
# A re-dispatch is safe: the pre-delete counts 404 as gone, every created address plans no-op, the
# tunnel ignores its secret, and -replace rolls only random_id.tunnel_secret.
#
# Order: inputs -> no run in flight on any gated workflow -> the id preflight (CTO D8: Doppler
# resolves the NEW zone/account ids and the legacy R2 account, and every phase token answers 200
# on the new zone/account) -> init. Rehearsal: a scratch copy of the root on a local backend runs
# the real state-forget (--rehearsal) and the plan and both gates, never applies, then asserts the
# remote state serial and the web-platform/backups/ listing are unchanged. Apply: state-forget
# (redirects-dns only), plan with the gate's -target/-replace lists, phase gate, then the
# whole-list entrypoint gate (ADR-136, CTO D2: a ruleset create is a whole-list PUT over the live
# phase entrypoint), apply the graded tfplan only when both PASS, verify the live probes (both phases).
#
# The job's own lines are verdicts and addresses. Terraform's plan and apply output can carry live
# values, so it passes through tf_redact_random_ids and tf_line (every line starts `tf| `, a CR
# becomes a space) inside a per-window ::stop-commands:: token: a live value cannot open a workflow
# command. entrypoint_gate is outside any window because it emits its own ::notice and ::error.
# Exit: 0 ok, 1 refused or failed, 2 setup error.
set -uo pipefail
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac
umask 077

readonly P="cf-account-migrate"
# The OLD ids, the state bucket and the backup prefix (CFAM_*), the R2 call (cfam_r2_aws) and
# cfam_serial_of come from the phase-gate library (load_libs), shared with the state forget.
readonly PREDICATE_REL="apps/web-platform/infra/scripts/cf-account-migration-complete.sh"
readonly PREDELETE_REL="apps/web-platform/infra/scripts/cf-tunnel-host-predelete.sh"
readonly LIVE_STATUSES=(queued in_progress waiting pending requested)

DOPPLER_WRITE_VALUE=""   # main: moved out of the environment before anything else runs
W=""
ROOT=""
VERIFY_FAILING=""
EXPECTED_ISU=""   # sorted, one address per line (validate_inputs)
ADMITTED_ISU=""   # sorted, one address per line (plan_and_gate, on a gate PASS)
NORM_COUNT=0      # records the gate admitted as import-normalize (plan_and_gate, on a gate PASS)
REREAD=""         # the last re-read's result: ok, differs=... or unreadable=... (reread_records)
TARGET_ARGS=()
REPLACE_ARGS=()
GATED=()

refuse() { # <reason-code> <message> [<extra summary fields>]
  # GitHub decodes %25, %0D and %0A in a workflow command's message, so a probed value carrying
  # "%0A::warning::" would render as extra annotation lines: encode them first (every caller).
  local m="${2//%/%25}"
  m="${m//$'\r'/%0D}"; m="${m//$'\n'/%0A}"
  printf '%s phase=%s verdict=refuse reason=%s%s\n' "$P" "${MIGRATE_PHASE:-?}" "$1" "${3:+ $3}"
  printf '::error title=%s::%s\n' "$P" "$m"
  summary "verdict=refuse reason=$1${3:+ $3}"
  exit 1
}

summary() {
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    printf -- '- %s phase=%s rehearsal=%s %s\n' "$P" "${MIGRATE_PHASE:-?}" "${REHEARSAL:-?}" "$1" >>"$GITHUB_STEP_SUMMARY"
  fi
}

# one_line (stdin -> stdout): text as ONE printable line. Becomes a space: C0 controls and DEL; the
# line and paragraph separators, NEL and NBSP (U+2028/9, U+0085, U+00A0); the bidi controls and
# invisible format characters (U+200B-U+200F, U+202A-U+202E, U+2060-U+2064, U+2066-U+206F, U+FEFF,
# U+061C, U+00AD and the U+E0000-U+E007F tag block); markdown-active characters. "::" (a
# workflow-command opener) becomes ":" AFTER the strip, so a format character between two colons
# cannot hide one. Runs of spaces become one.
# RESIDUAL: a deny list. Other invisible code points (variation selectors, U+034F, U+180E, U+3164)
# pass through; they open no workflow command and reorder no text. obs_line adds a closed set.
one_line() {
  LC_ALL=C tr '\000-\037\177' '  ' \
    | LC_ALL=C sed -e 's/\xe2\x80[\x8b-\x8f\xa8-\xae]/ /g' -e 's/\xe2\x81[\xa0-\xa4\xa6-\xaf]/ /g' -e 's/\xef\xbb\xbf/ /g' \
    | LC_ALL=C sed -e 's/\xd8\x9c/ /g' -e 's/\xc2[\x85\xa0\xad]/ /g' -e 's/\xf3\xa0[\x80\x81][\x80-\xbf]/ /g' \
    | LC_ALL=C sed -e 's/::*/:/g' -e 's/[][`<>|*_#]/ /g' \
    | LC_ALL=C tr -s ' '
}

# reason_line: the operator's reason through one_line, for the audit trail; at most 200 bytes.
reason_line() {
  local r
  r="$(printf '%s' "${REASON:-}" | one_line)"
  r="${r# }"
  LC_ALL=C printf '%.200s' "$r"
}

# obs_line <text>: an observed probe result (a status code and a Location or header from the
# network) as one printable token for the failing= list, which reaches the log line, the
# ::error annotation and the step summary. one_line, then a CLOSED set: every byte outside
# printable ASCII becomes a space (a status code, a URL and a header value need nothing else),
# then spaces become "+"; at most 120 bytes.
obs_line() {
  local r
  r="$(printf '%s' "$1" | one_line | LC_ALL=C tr -c '\040-\176' ' ' | LC_ALL=C tr -s ' ')"
  r="${r# }"; r="${r% }"
  LC_ALL=C printf '%.120s' "${r// /+}"
}

# shellcheck disable=SC2329 # invoked by the EXIT trap
cleanup() { if [[ -n "$W" && -d "$W" ]]; then rm -rf "$W"; fi; }

# tf_env <cmd...>: run with the prd_terraform TF_VARs; values the loader exported win (--preserve-env).
# TF_LOG* are stripped INSIDE doppler run, so neither the loader's $GITHUB_ENV export nor a Doppler
# key can turn on provider/state logging (it would print secrets). check_ids runs the same array
# under `timeout` for its short read.
readonly TF_ENV=(doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var --
  env -u TF_LOG -u TF_LOG_PATH -u TF_LOG_CORE -u TF_LOG_PROVIDER)
tf_env() { "${TF_ENV[@]}" "$@"; }

# cmd_token: a fresh 32-hex ::stop-commands:: token; non-zero when one cannot be read.
cmd_token() { local t; t="$(LC_ALL=C od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"; [[ "$t" =~ ^[0-9a-f]{32}$ ]] && printf '%s' "$t"; }
# tf_line (stdin -> stdout): the runner's reader also splits on CR, and a stopped command still prints.
tf_line() { LC_ALL=C sed -e 's/\r/ /g' -e 's/^/tf| /'; }

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
  # Integers only (no leading zero, which bash reads as octal): the budget feeds bash arithmetic,
  # where an array subscript would run a command.
  [[ "${CFAM_VERIFY_TRIES:-12}" =~ ^([1-9]|[1-5][0-9]|60)$ && "${CFAM_VERIFY_SLEEP:-10}" =~ ^([0-9]|[1-5][0-9]|60)$ \
     && "${CFAM_VERIFY_DEADLINE:-600}" =~ ^(0|[1-9][0-9]{0,2}|1[01][0-9][0-9]|1200)$ ]] \
    || refuse bad-verify-budget "CFAM_VERIFY_TRIES must be 1-60, CFAM_VERIFY_SLEEP 0-60 and CFAM_VERIFY_DEADLINE 0-1200 (integers)"
  # Checked here, before anything is written, so a typo cannot surface only after the forget.
  local a raw="${CFAM_EXPECTED_IN_STATE_UPDATES:-}"; local -a isu=()
  read -r -d '' -a isu <<<"${raw//,/ }"
  for a in ${isu[@]+"${isu[@]}"}; do
    [[ "$a" =~ ^[a-z][a-z0-9_]*\.[A-Za-z_][A-Za-z0-9_-]*$ ]] \
      || refuse bad-expected-in-state-updates "expected_in_state_updates must be Terraform addresses (type.name), space- or comma-separated, or empty for none; one entry is not of that shape"
  done
  if [[ "${#isu[@]}" -gt 0 ]]; then EXPECTED_ISU="$(printf '%s\n' "${isu[@]}" | LC_ALL=C sort -u)"; fi
  summary "reason=$(reason_line)"
}

# isu_csv <one address per line>: the set as one comma-separated token, the form the input takes.
isu_csv() { paste -sd, - <<<"$1"; }

# check_expected_isu: the in-state updates the gate admitted on THIS plan must be exactly the set
# the operator passed (copied from the rehearsal's `in-state-updates admitted=` line). An update
# nobody expected would overwrite a rule (a dashboard edit, say) the rehearsal did not show.
check_expected_isu() { # <extra refusal prose> <extra refusal fields>
  [[ "$ADMITTED_ISU" == "$EXPECTED_ISU" ]] && return 0
  printf '%s in-state-updates admitted=%s expected=%s\n' "$P" "$(isu_csv "$ADMITTED_ISU")" "$(isu_csv "$EXPECTED_ISU")"
  refuse in-state-updates-unexpected "the gate admitted in-state updates [$(isu_csv "$ADMITTED_ISU")] but expected_in_state_updates is [$(isu_csv "$EXPECTED_ISU")]; nothing was applied. Each admitted update overwrites a rule already on the NEW zone: re-run the rehearsal, read its in-state-updates admitted= line (runbook Halt, verify-failed step 4), and re-dispatch with exactly that set.$1" "$2"
}

# gated_workflows: every workflow that reaches ./.github/actions/infra-credentials and is NOT in the
# predicate's CFAM_EXEMPT_WORKFLOWS (CTO D1). It reaches the loader by a step line of its own (bare
# or quoted), or through a job-level `uses: ./.github/workflows/<callee>` of a workflow that reaches
# it, followed to a fixed point: a run is listed under the CALLER's name, so the caller is the file
# `gh run list --workflow` must read. The exempt list is read from the predicate itself, in a child
# shell (both scripts declare a readonly P), so there is no second copy to drift.
readonly LOADER_RE="^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*[\"']?\\./\\.github/actions/infra-credentials/?[\"']?[[:space:]]*(#.*)?\$"
readonly CALLEE_RE="^[[:space:]]*uses:[[:space:]]*[\"']?\\./\\.github/workflows/([A-Za-z0-9._-]+\\.ya?ml)[\"']?[[:space:]]*(#.*)?\$"
gated_workflows() {
  local exempt f base c rc reach="" grew=1
  local -a files=()
  # shellcheck disable=SC2016 # expanded by the child bash
  exempt="$(bash -c 'source "$1" && printf "%s\n" "${CFAM_EXEMPT_WORKFLOWS[@]}"' _ "$GITHUB_WORKSPACE/$PREDICATE_REL" 2>/dev/null)" \
    || refuse runs-unreadable "cannot read CFAM_EXEMPT_WORKFLOWS from $PREDICATE_REL"
  [[ -n "${exempt//[[:space:]]/}" ]] || refuse runs-unreadable "the predicate's exempt workflow list is empty"
  for f in "$GITHUB_WORKSPACE"/.github/workflows/*.yml "$GITHUB_WORKSPACE"/.github/workflows/*.yaml; do
    [[ -f "$f" ]] || continue
    files+=("$f")
    rc=0; grep -qE -- "$LOADER_RE" "$f" || rc=$?
    [[ "$rc" -le 1 ]] || refuse runs-unreadable "cannot read ${f##*/} to derive the gated workflows"
    [[ "$rc" -ne 0 ]] || reach+="${f##*/}"$'\n'
  done
  while [[ "$grew" -eq 1 ]]; do
    grew=0
    for f in ${files[@]+"${files[@]}"}; do
      base="${f##*/}"
      grep -qxF -- "$base" <<<"$reach" && continue
      while IFS= read -r c; do
        if [[ -n "$c" ]] && grep -qxF -- "$c" <<<"$reach"; then reach+="$base"$'\n'; grew=1; break; fi
      done < <(sed -nE "s|${CALLEE_RE}|\\1|p" "$f")
    done
  done
  for f in ${files[@]+"${files[@]}"}; do
    base="${f##*/}"
    grep -qxF -- "$base" <<<"$reach" || continue
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
readonly CF_API="https://api.cloudflare.com/client/v4"
# The read probe per token, inside that token's own grant (the read half of what it edits).
token_probe_path() {
  case "$1" in
    cf_api_token) printf 'zones/%s/dns_records?per_page=1' "$CFAM_NEW_ZONE_ID" ;;
    cf_api_token_rulesets) printf 'zones/%s/rulesets' "$CFAM_NEW_ZONE_ID" ;;
    cf_api_token_pages) printf 'accounts/%s/pages/projects' "$CFAM_NEW_ACCOUNT_ID" ;;
    cf_api_token_zone_settings) printf 'zones/%s/settings' "$CFAM_NEW_ZONE_ID" ;;
    cf_api_token_bot_management) printf 'zones/%s/bot_management' "$CFAM_NEW_ZONE_ID" ;;
    # The tunnel phase's scopes on the same token (CF_API_TOKEN_SCOPE_PROBES), read-only.
    cf_api_token@tunnel) printf 'accounts/%s/cfd_tunnel?per_page=1' "$CFAM_NEW_ACCOUNT_ID" ;;
    cf_api_token@access-apps) printf 'zones/%s/access/apps?per_page=1' "$CFAM_NEW_ZONE_ID" ;;
    cf_api_token@service-tokens) printf 'accounts/%s/access/service_tokens?per_page=1' "$CFAM_NEW_ACCOUNT_ID" ;;
    cf_api_token@notifications) printf 'accounts/%s/alerting/v3/policies' "$CFAM_NEW_ACCOUNT_ID" ;;
    *) return 1 ;;
  esac
}
# Probed for every phase that uses cf_api_token, so redirects-dns refuses a token too narrow for the
# tunnel phase BEFORE its state forget. Each reads CF_API_TOKEN_NEXT when one is staged, else the
# live token (the line says source=staged or source=live).
readonly CF_API_TOKEN_SCOPE_PROBES=(cf_api_token@tunnel cf_api_token@access-apps cf_api_token@service-tokens cf_api_token@notifications)
# Runs INSIDE doppler run: prints zone, account, r2 account, then "tok <name> <http-code> <curl-rc>
# <source>" per <name> <url> pair. A token of an unusable shape (a quote or newline would inject a
# curl config directive) is never sent and reads "bad". curl-rc non-zero is a transport failure (a
# timeout, 28; a DNS or connect failure, 6/7): the API was not reached, which says nothing about the token.
# shellcheck disable=SC2016 # expanded by the inner bash
PREFLIGHT_SH="$(cat <<'PREFLIGHT'
printf "%s\n%s\n%s\n" "${TF_VAR_cf_zone_id:-}" "${TF_VAR_cf_account_id:-}" "${TF_VAR_cf_r2_account_id:-}"
while [ "$#" -ge 2 ]; do
  n="$1"; u="$2"; shift 2
  b="$n"; s=live
  case "$n" in *@*)
    b="${n%%@*}"; x="TF_VAR_${b}_next"
    if [ -n "${!x:-}" ]; then b="${b}_next"; s=staged; fi ;;
  esac
  v="TF_VAR_$b"; t="${!v:-}"
  case "$t" in ""|*[!A-Za-z0-9._~+/=-]*) printf "tok %s bad 0 %s\n" "$n" "$s"; continue ;; esac
  c="$(curl --disable --noproxy '*' -sS -o /dev/null --max-time 10 -w "%{http_code}" --config - "$u" 2>/dev/null \
       < <(printf "header = \"Authorization: Bearer %s\"\n" "$t"))"; e=$?
  printf "tok %s %s %s %s\n" "$n" "${c:-000}" "$e" "$s"
done
PREFLIGHT
)"
readonly PREFLIGHT_SH
# Runs INSIDE doppler run: the one read of the deploy token (url in $1), the bearer on curl's stdin
# config. Prints body, newline, http code; the caller prints neither the body nor any field of it.
# shellcheck disable=SC2016 # expanded by the inner bash
DEPLOY_TOKEN_SH="$(cat <<'DEPLOYTOKEN'
t="${TF_VAR_cf_api_token:-}"
case "$t" in ""|*[!A-Za-z0-9._~+/=-]*) exit 65 ;; esac
curl --disable --noproxy '*' -sS --max-time 15 -w '\n%{http_code}' --config - "$1" 2>/dev/null \
  < <(printf "header = \"Authorization: Bearer %s\"\n" "$t")
DEPLOYTOKEN
)"
readonly DEPLOY_TOKEN_SH
# Where a refused value comes from: doppler run --preserve-env keeps what the credential loader
# already exported, so a TF_VAR_* the soleur-infra-privileged project carries wins over prd_terraform.
readonly DOPPLER_SRC=" The value checked is the effective one: soleur/prd_terraform, unless the soleur-infra-privileged project (exported by the credential loader) carries the same name, whose value wins under doppler run --preserve-env. Check both before re-flipping."
check_ids() {
  local out zone acct r2 rc=0 tokens labels n path line code e src note bad=0 unreach=0 scope=0
  local -a pairs=()
  tokens="$(cf_account_migrate_phase_tokens "$MIGRATE_PHASE")" || refuse no-tokens "the gate has no token list for $MIGRATE_PHASE"
  [[ -n "$tokens" ]] || refuse no-tokens "the gate's token list for $MIGRATE_PHASE is empty"
  labels="$tokens"
  if grep -qxF cf_api_token <<<"$tokens"; then labels+=$'\n'"$(printf '%s\n' "${CF_API_TOKEN_SCOPE_PROBES[@]}")"; fi
  while IFS= read -r n; do
    path="$(token_probe_path "$n")" || refuse no-tokens "no read probe is defined for token $n"
    pairs+=("$n" "$CF_API/$path")
  done <<<"$labels"
  # 90 s: up to seven probes of at most 10 s each, plus Doppler's own resolve.
  out="$(timeout 90 "${TF_ENV[@]}" bash -c "$PREFLIGHT_SH" _ "${pairs[@]}" 2>/dev/null)" || rc=$?
  [[ "$rc" -ne 124 ]] || refuse ids-timeout "doppler run did not resolve the ids and token probes within 90 s"
  [[ "$rc" -eq 0 ]] || refuse ids-unreadable "doppler run could not resolve cf_zone_id / cf_account_id"
  # Compared exactly as Terraform sees them: variables.tf's shape check is lowercase-only, so an
  # upper-case spelling is refused here, before the forget, not by the plan after it.
  zone="$(sed -n 1p <<<"$out")"
  acct="$(sed -n 2p <<<"$out")"
  r2="$(sed -n 3p <<<"$out")"
  [[ "$zone" == "$CFAM_NEW_ZONE_ID" ]] \
    || refuse zone-id-not-new "cf_zone_id does not resolve to the Soleur-account zone (Doppler still holds the OLD id, or none). Do the runbook Phase 2 flip first.${DOPPLER_SRC} Nothing was written."
  [[ "$acct" == "$CFAM_NEW_ACCOUNT_ID" ]] \
    || refuse account-id-not-new "cf_account_id does not resolve to the Soleur account (Doppler still holds the OLD id, or none). Do the runbook Phase 2 flip first.${DOPPLER_SRC} Nothing was written."
  [[ "$r2" == "$CFAM_OLD_ACCOUNT_ID" ]] \
    || refuse r2-account-not-old "cf_r2_account_id does not resolve to the legacy account that holds R2 (ADR-329: R2 never moves).${DOPPLER_SRC} Nothing was written."
  while IFS= read -r n; do
    line="$(awk -v n="$n" '$1 == "tok" && $2 == n {print $3, $4, $5; exit}' <<<"$out")"
    code=""; e=""; src=""
    read -r code e src <<<"$line"
    code="${code:-missing}"
    [[ "$e" =~ ^[0-9]{1,3}$ ]] || e=0
    note=""
    if [[ "$n" == *@* ]]; then
      case "$src" in staged|live) note=" source=$src" ;; *) note=" source=unknown" ;; esac
    fi
    if [[ "$e" == 0 ]]; then printf '%s preflight=token name=%s http=%s%s\n' "$P" "$n" "$code" "$note"
    else printf '%s preflight=token name=%s http=%s e=%s%s\n' "$P" "$n" "$code" "$e" "$note"; fi
    # Only a DENIAL (400/401/403/404) or an unusable token shape (bad) is a token verdict. A transport
    # failure, a 429 or a 5xx is no verdict: retry, do not re-mint.
    if [[ "$e" != 0 ]]; then unreach=1
    else
      case "$code" in
        200) ;;
        400|401|403|404|bad|missing) if [[ "$n" == *@* ]]; then scope=1; else bad=1; fi ;;
        *) unreach=1 ;;
      esac
    fi
  done <<<"$labels"
  [[ "$bad" -eq 0 ]] || refuse token-not-new-zone "a provider token for $MIGRATE_PHASE did not answer 200 on the NEW zone/account (see the preflight=token lines): swap or re-mint it (runbook Phase 0/2).${DOPPLER_SRC} Nothing was written."
  [[ "$scope" -eq 0 ]] || refuse token-scope-missing "cf_api_token (the staged CF_API_TOKEN_NEXT when one exists, see source= on the preflight=token lines) was denied a Tunnel, Access, service-token or notification read on the NEW account. Widen the token, or enable Zero Trust on the account if it is off (runbook Phase 0).${DOPPLER_SRC} Nothing was written."
  [[ "$unreach" -eq 0 ]] || refuse token-unreachable "the Cloudflare API gave no verdict on a token probe for $MIGRATE_PHASE (curl failed, or a 429 / 5xx answer: see the e= and http= on the preflight=token lines): not a token verdict. Re-dispatch; do not re-mint. Nothing was written."
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

# One GET per pinned record inside doppler run, so the bearer stays out of argv. Each `doppler run`
# fetches the token again, so its shape is checked again: a quote or newline would add a curl config
# directive. Exit 3 is that refusal, which no retry can fix. A 200 or 404 lands in its own file via a
# rename; any other answer leaves no file, which reads as unreadable and is retried.
# shellcheck disable=SC2016 # expanded by the inner bash
LIVE_READ_SH="$(cat <<'LIVEREAD'
t="${TF_VAR_cf_api_token:-}"
case "$t" in ""|*[!A-Za-z0-9._~+/=-]*) exit 3 ;; esac
b="$1"; d="$2"; z="$3"; shift 3
for id in "$@"; do
  [ -e "$d/$id" ] && continue
  r="$(curl --disable --noproxy '*' -sS --max-time 5 -w '\n%{http_code}' --config - \
       "$b/zones/$z/dns_records/$id" 2>/dev/null \
       < <(printf 'header = "Authorization: Bearer %s"\n' "$t"))" || continue
  code="${r##*$'\n'}"
  if [[ "$code" == 200 || "$code" == 404 ]]; then
    printf '%s\n' "$r" >"$d/$id.tmp" && mv "$d/$id.tmp" "$d/$id"
  fi
done
LIVEREAD
)"
readonly LIVE_READ_SH
readonly LIVE_READ_DEADLINE=90 LIVE_READ_PASSES=5 APPLY_DEADLINE=1100 APPLY_MIN_START=300

# read_live_records <out>: live.json for every pinned record, from a directory no earlier read wrote.
# One deadline spans all passes and is enforced outside doppler run, because a Doppler stall happens
# before any inner timer starts. The pause between passes starts at 5 s and doubles, cut short so the
# next pass still fits the deadline. A record with no response by then is `unreadable` in <out>.
# Non-zero means no usable <out>.
read_live_records() {
  local out="$1" dir pins rc left id pending pass read_end pause=5
  local -a ids=()
  rm -f "$out" "$out.tmp" || return 1
  dir="$(mktemp -d "$W/live.XXXXXX")" || return 1
  pins="$(cf_account_migrate_record_pins "$MIGRATE_PHASE")" || return 1
  mapfile -t ids < <(cut -f2 <<<"$pins")
  if ((${CFAM_VERIFY_SLEEP:-10} < pause)); then pause="${CFAM_VERIFY_SLEEP:-10}"; fi
  read_end=$((SECONDS + LIVE_READ_DEADLINE))
  for ((pass = 1; pass <= LIVE_READ_PASSES; pass++)); do
    left=$((read_end - SECONDS)); ((left > 5)) || break
    rc=0
    timeout -k 5 "$((left - 5))" "${TF_ENV[@]}" bash -c "$LIVE_READ_SH" _ "$CF_API" "$dir" "$CFAM_NEW_ZONE_ID" "${ids[@]}" >/dev/null 2>&1 || rc=$?
    [[ "$rc" -ne 3 ]] || break
    pending=0
    for id in "${ids[@]}"; do [[ -e "$dir/$id" ]] || pending=1; done
    [[ "$pending" -eq 1 ]] || break
    if ((pass < LIVE_READ_PASSES)); then
      # The loop's next pass needs left > 5, so a pause may use all but 6 s of what remains.
      left=$((read_end - SECONDS - 6)); ((left > 0)) || break
      sleep "$((pause < left ? pause : left))"
      pause=$((pause * 2))
    fi
  done
  cf_account_migrate_live_collect "$MIGRATE_PHASE" "$dir" >"$out.tmp" && mv "$out.tmp" "$out"
}

# reread_records: all pinned records again, into their own file, against the graded plan's `after`.
# Sets REREAD; returns 0 only when every record matches.
reread_records() {
  local live="$W/live-reread.json" d a t unread="" differ="" pins all
  # No pin list means no address to name, so the value is a fixed token in the unreadable= form.
  pins="$(cf_account_migrate_record_pins "$MIGRATE_PHASE")" && [[ -n "$pins" ]] \
    || { REREAD="unreadable=all-pinned-records"; return 1; }
  all="$(cut -f1 <<<"$pins" | paste -sd, -)"
  read_live_records "$live" || { REREAD="unreadable=$all"; return 1; }
  d="$(cf_account_migrate_live_diff "$MIGRATE_PHASE" "$W/tfplan.json" "$live")" || { REREAD="unreadable=$all"; return 1; }
  while IFS=$'\t' read -r a t; do
    [[ -n "$a" ]] || continue
    if [[ "$t" == unreadable ]]; then unread+=",$a"; else differ+=",$a:${t//,/+}"; fi
  done <<<"$d" # every differing record
  if [[ -n "$differ" ]]; then
    REREAD="differs=${differ#,}${unread:+;unreadable=${unread#,}}"; return 1
  fi
  if [[ -n "$unread" ]]; then REREAD="unreadable=${unread#,}"; return 1; fi
  REREAD="ok"
  printf '%s import-normalize reread=ok records=%s\n' "$P" "$(grep -c . <<<"$pins")"
}

# halt_pointer <reread value, or empty> <probe field>: the runbook Halt sentences for a post-apply
# refusal. Any value containing differs= is the wrong-value bullet, an unreadable= value alone is No
# completed re-read, and failing=<list> adds the verify-failed steps.
halt_pointer() {
  case "$1" in
    *differs=*) printf ' Runbook Halt: A DNS record may hold a wrong value.' ;;
    *unreadable=*) printf ' Runbook Halt: No completed re-read.' ;;
  esac
  [[ "$2" != failing=* ]] || printf ' The runbook Halt verify-failed steps apply to those failing items (app-health first).'
}

# join_fields <field>...: the non-empty fields, space-separated, in order.
join_fields() {
  local out="" f
  for f in "$@"; do [[ -z "$f" ]] || out+="${out:+ }$f"; done
  printf '%s' "$out"
}

# pull_remote <out-file>: the remote state, read through the real root's backend.
pull_remote() { (cd "$ROOT" && terraform state pull) >"$1" 2>/dev/null && [[ -s "$1" ]]; }

# list_backups: the sorted key list under the backup prefix. rc 124 = the listing timed out.
list_backups() {
  local rc=0
  cfam_r2_aws s3api list-objects-v2 --bucket "$CFAM_STATE_BUCKET" --prefix "$CFAM_BACKUP_PREFIX" \
    --output json >"$W/backups.json" 2>/dev/null || rc=$?
  [[ "$rc" -eq 0 ]] || return "$rc"
  jq -sc '[.[0].Contents[]?.Key] | sort' "$W/backups.json" 2>/dev/null
}

# backups_or_refuse <when>: list_backups into BK, refusing with a named reason on a timeout or a
# failure (in THIS shell, so the verdict line reaches the log).
BK=""
backups_or_refuse() {
  local rc=0
  BK="$(list_backups)" || rc=$?
  [[ "$rc" -ne 124 ]] || refuse backups-timeout "listing s3://$CFAM_STATE_BUCKET/$CFAM_BACKUP_PREFIX ($1) did not finish within 60 s"
  [[ "$rc" -eq 0 ]] || refuse backups-unreadable "cannot list s3://$CFAM_STATE_BUCKET/$CFAM_BACKUP_PREFIX ($1); the no-write assertion needs it"
}

state_migrate() { # [--rehearsal --backup-dir <dir>]; runs in the current directory
  bash "$GITHUB_WORKSPACE/apps/web-platform/infra/scripts/cf-account-state-migrate.sh" \
    --new-zone "$CFAM_NEW_ZONE_ID" --new-account "$CFAM_NEW_ACCOUNT_ID" "$@"
}

# deploy_token_check: the live half of DEPLOY POLICY (gate header). Reads the one service token the
# graded plan admits. Prints the token's UUID and a reason word, never the body or a field of it.
deploy_token_check() {
  local id out rc=0 code body v
  id="$(cf_account_migrate_deploy_token_id "$W/tfplan.json")" || {
    printf '%s deploy-token verdict=refuse detail=no-token-id\n' "$P"; return 1; }
  out="$(timeout 40 "${TF_ENV[@]}" bash -c "$DEPLOY_TOKEN_SH" _ "$CF_API/accounts/$CFAM_NEW_ACCOUNT_ID/access/service_tokens/$id" 2>/dev/null)" || rc=$?
  code="${out##*$'\n'}"; body="${out%$'\n'*}"
  if [[ "$rc" -ne 0 || "$code" != 200 ]]; then
    printf '%s deploy-token id=%s verdict=refuse detail=http-%s e=%s\n' "$P" "$id" "$(obs_line "${code:0:3}")" "$rc"
    return 1
  fi
  v="$(cf_account_migrate_deploy_token_verdict "$id" "$(date +%s)" <<<"$body")" || {
    printf '%s deploy-token id=%s verdict=refuse detail=%s\n' "$P" "$id" "$(obs_line "$v")"; return 1; }
  printf '%s deploy-token id=%s verdict=ok\n' "$P" "$id"
}

# tunnel_predelete: the pinned six-record delete (TUNNEL PHASE in the header).
tunnel_predelete() {
  local rc=0
  # shellcheck disable=SC2016 # expanded by the inner bash, inside doppler run
  tf_env bash -c 'CF_API_TOKEN="${TF_VAR_cf_api_token:-}" exec bash "$1" --apply' _ "$GITHUB_WORKSPACE/$PREDELETE_REL" 2>&1 || rc=$?
  [[ "$rc" -eq 0 ]] || refuse predelete-refused "the pinned six-record pre-delete did not finish (see its verdict line above, which names any record it deleted); no plan ran and nothing was applied. A re-dispatch counts a record already gone as done."
}

# sync_ci_ssh: publish the new CI-SSH pair to prd_terraform on stdin and verify each by digest.
# Returns 1 on any failure, with the one key it stopped at; prints no value.
sync_ci_ssh() {
  local k o v want got
  for k in CI_SSH_ACCESS_TOKEN_ID CI_SSH_ACCESS_TOKEN_SECRET; do
    case "$k" in *_ID) o=ci_ssh_access_service_token_client_id ;; *) o=ci_ssh_access_service_token_client_secret ;; esac
    v="$(terraform output -raw "$o" 2>/dev/null)" || v=""
    if [[ -z "$v" ]]; then printf '%s ci-ssh-sync key=%s verdict=fail cause=output-empty\n' "$P" "$k"; return 1; fi
    # 2>&1 too: Doppler prints the config table (#7133).
    if ! printf '%s' "$v" | DOPPLER_TOKEN="$DOPPLER_WRITE_VALUE" doppler secrets set "$k" --silent --no-interactive -p soleur -c prd_terraform >/dev/null 2>&1; then
      printf '%s ci-ssh-sync key=%s verdict=fail cause=write-refused\n' "$P" "$k"; return 1
    fi
    want="$(printf '%s' "$v" | sha256sum | cut -d' ' -f1)"
    got="$(DOPPLER_TOKEN="$DOPPLER_WRITE_VALUE" doppler secrets get "$k" -p soleur -c prd_terraform --plain 2>/dev/null \
      | LC_ALL=C awk 'NR>1{printf "\n"} {printf "%s",$0}' | sha256sum | cut -d' ' -f1)" || got=""
    v=""
    if [[ "$got" != "$want" ]]; then printf '%s ci-ssh-sync key=%s verdict=fail cause=digest-mismatch\n' "$P" "$k"; return 1; fi
    printf '%s ci-ssh-sync key=%s verdict=ok\n' "$P" "$k"
  done
}

# gate_refusal_rc <gate output>: plan_and_gate's code for a refused plan. 3 when a REFUSE line says a
# record differs from its live read, 4 when every REFUSE line is `live record unreadable`, else 1.
gate_refusal_rc() {
  local l n=0 u=0 d=0
  while IFS= read -r l; do
    [[ "$l" == "REFUSE "* ]] || continue
    n=$((n + 1))
    if [[ "$l" == *" differs from the live record"* ]]; then d=1
    elif [[ "$l" == *" live record unreadable" ]]; then u=$((u + 1)); fi
  done <<<"$1"
  ((d == 0)) || return 3
  ((n == 0 || u != n)) || return 4
  return 1
}

# gate_next <plan_and_gate rc> <text for any other refusal> <lead-in for rc 3 or 4>: how a gate
# refusal's message ends. Neither 3 nor 4 carries a fix-forward or re-dispatch sentence.
gate_next() {
  case "$1" in
    3) printf '%s Runbook Halt: A DNS record may hold a wrong value.' "$3" ;;
    4) printf '%s Edit no DNS record and re-rehearse once; a second consecutive refusal stops for an owner decision.' "$3" ;;
    *) printf '%s' "$2" ;;
  esac
}

# plan_and_gate: in the current directory. Writes $W/tfplan; returns 0 only on phase-gate
# verdict=PASS AND an entrypoint-gate PASS AND (tunnel) a live deploy-token PASS; 2 when the
# entrypoint gate refused; 1, 3 or 4 when the phase gate refused (gate_refusal_rc) or a step before
# it failed (1); 5 when the deploy token was refused.
plan_and_gate() {
  local rc out live="" n=0 tok gc=0
  local -a phase_vars=()
  # The app-record import block is reachable only from this plan (variables.tf defaults it off).
  [[ "$MIGRATE_PHASE" != tunnel ]] || phase_vars=(-var=cf_migration_import_app=true)
  terraform show -json >"$W/pre-plan-state.json" 2>/dev/null || { printf '::error::terraform show -json (pre-plan state) failed\n'; return 1; }
  tok="$(cmd_token)" || { printf '::error title=%s::cannot create the workflow-command token\n' "$P"; return 1; }
  printf '::stop-commands::%s\n' "$tok"
  tf_env terraform plan -no-color -input=false -out="$W/tfplan" \
    -var="ssh_key_path=$W/ci_ssh_key.pub" ${phase_vars[@]+"${phase_vars[@]}"} \
    "${TARGET_ARGS[@]}" ${REPLACE_ARGS[@]+"${REPLACE_ARGS[@]}"} 2>&1 | tf_redact_random_ids | tf_line
  rc=${PIPESTATUS[0]}
  printf '\n::%s::\n' "$tok"
  if [[ "$rc" -ne 0 ]]; then
    printf '::error title=%s::terraform plan failed (exit %s). If the output names cf_zone_id or cf_account_id, Doppler still holds an OLD id (Guard 4).\n' "$P" "$rc"
    return 1
  fi
  terraform show -json "$W/tfplan" >"$W/tfplan.json" 2>/dev/null || { printf '::error::terraform show -json tfplan failed\n'; return 1; }
  if [[ "$MIGRATE_PHASE" == redirects-dns || "$MIGRATE_PHASE" == tunnel ]]; then # read every pinned record
    live="$W/live-records.json"
    read_live_records "$live" || live=""
    [[ -z "$live" ]] || n="$(jq '[.[] | select(.status == "ok")] | length' "$live" 2>/dev/null)" || n=0
    printf '%s live-read records=%s\n' "$P" "${n:-0}"
    out="$(cf_account_migrate_gate "$MIGRATE_PHASE" "$W/tfplan.json" "$W/pre-plan-state.json" "$live")"; rc=$?
  else
    out="$(cf_account_migrate_gate "$MIGRATE_PHASE" "$W/tfplan.json" "$W/pre-plan-state.json")"; rc=$?
  fi
  printf '%s\n' "$out"
  summary "$(grep -E '^cf_account_migrate_gate: phase=' <<<"$out" | tail -n1)"
  if [[ "$rc" -ne 0 ]] || ! grep -qE "^cf_account_migrate_gate: phase=${MIGRATE_PHASE} verdict=PASS " <<<"$out"; then
    gate_refusal_rc "$out"; return
  fi
  # The set the apply compares with expected_in_state_updates; a rehearsal prints it to copy from.
  ADMITTED_ISU="$(sed -n 's/^cf_account_migrate_gate: in-state-update //p' <<<"$out" | LC_ALL=C sort -u)"
  printf '%s in-state-updates count=%s admitted=%s\n' "$P" "$(grep -c . <<<"$ADMITTED_ISU")" "$(isu_csv "$ADMITTED_ISU")"
  summary "in-state-updates admitted=$(isu_csv "$ADMITTED_ISU")"
  # grep -c exits 1 on zero matches (a real 0). Anything else leaves no count, and an empty one would
  # silently skip the post-apply re-read, so it refuses.
  NORM_COUNT="$(grep -c '^cf_account_migrate_gate: import-normalize ' <<<"$out")" || gc=$?
  if ((gc > 1)) || [[ ! "$NORM_COUNT" =~ ^[0-9]+$ ]]; then
    printf '::error title=%s::cannot count the import-normalize records (grep exit %s)\n' "$P" "$gc"
    return 1
  fi
  printf '%s import-normalize count=%s\n' "$P" "$NORM_COUNT"
  summary "import-normalize count=$NORM_COUNT"
  if [[ "$MIGRATE_PHASE" == tunnel ]]; then
    deploy_token_check || return 5
  fi
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
  before="$(cfam_serial_of "$W/pull.tfstate")" || refuse state-pull-failed "pulled state has no numeric serial"
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
  after="$(cfam_serial_of "$W/after.tfstate")" || refuse state-pull-failed "post-rehearsal state has no numeric serial"
  rm -f "$W/after.tfstate"
  [[ "$after" == "$before" ]] || refuse remote-serial-changed "the remote state serial went $before -> $after during a rehearsal"
  backups_or_refuse after; b_after="$BK"
  [[ "$b_after" == "$b_before" ]] || refuse backup-written "a new object appeared under $CFAM_BACKUP_PREFIX during a rehearsal"
  printf '%s rehearsal remote_serial=%s serial_unchanged=true backups_unchanged=true\n' "$P" "$before"
  [[ "$rc" -ne 2 ]] || refuse entrypoint-gate-refused "the whole-list entrypoint gate refused (a live phase entrypoint is populated, or its emptiness could not be proven); see the ::error lines above. Nothing was written."
  [[ "$rc" -ne 5 ]] || refuse deploy-token-refused "the deploy policy's service token did not pass its live read (see the deploy-token line: 200, name github-actions-deploy, about 8760h to expiry). Nothing was written."
  [[ "$rc" -eq 0 ]] || refuse rehearsal-refused "the rehearsal did not reach gate verdict=PASS (see above); nothing was written$(gate_next "$rc" "" ".")"
  if [[ "$MIGRATE_PHASE" == tunnel ]]; then
    # No token and no request: the apply leg must not be the first to learn the list is unusable.
    bash "$GITHUB_WORKSPACE/$PREDELETE_REL" --check-pins \
      || refuse predelete-refused "the gate passed, but the pre-delete's pin list is not six record ids, so the apply leg would refuse. Commit the six ids in a reviewed PR. Nothing was written."
  fi
  printf '%s phase=%s mode=rehearsal verdict=PASS applied=false\n' "$P" "$MIGRATE_PHASE"
  summary "verdict=PASS applied=false"
}

# probe <url> [<user-agent>]: prints "<code> <redirect_url>", then " e=<rc>" when curl itself exited
# non-zero (a timeout, 28, or a refused connection, 7, both read 000 otherwise). A probe carrying
# e= fails whatever its code: served() and the exact 301 match both reject it.
probe() {
  local -a ua=()
  local out rc=0
  [[ -n "${2:-}" ]] && ua=(-A "$2")
  out="$(curl -sS -o /dev/null --max-time "$VERIFY_PROBE_S" -w '%{http_code} %{redirect_url}' ${ua[@]+"${ua[@]}"} "$1" 2>/dev/null)" || rc=$?
  printf '%s' "$out"
  [[ "$rc" -eq 0 ]] || printf ' e=%s' "$rc"
}
served() { [[ "$1" == "$2 "* && "$1" != *" e="* ]]; } # <probe output> <code>: that code, curl exit 0

# noindex_obs <raw header dump>: "<status> hdr=<x-robots-tag value>" of the last response, with
# 000 for no status line (a timeout or refused connection) and hdr=absent for no header.
noindex_obs() {
  awk '{ sub(/\r$/, "") }
    /^HTTP\// { c = $2; v = "" }
    tolower($0) ~ /^x-robots-tag:/ { v = $0; sub(/^[^:]*:[ \t]*/, "", v) }
    END { printf "%s hdr=%s", (c == "" ? "000" : c), (v == "" ? "absent" : v) }' <<<"$1"
}

# Each legacy path must 301 to its exact target (seo-rulesets.tf / seo-bulk-redirects.tf):
# a 301 to the wrong page is as broken for a visitor as a 404.
readonly VERIFY_PAIRS=(
  "https://soleur.ai/pages/agents.html|https://soleur.ai/agents/"
  "https://soleur.ai/pages/legal/privacy-policy.html|https://soleur.ai/legal/privacy-policy/"
  "https://soleur.ai/blog/2026-03-16-soleur-vs-anthropic-cowork/|https://soleur.ai/blog/soleur-vs-anthropic-cowork/"
  "https://www.soleur.ai/|https://soleur.ai/"
)
# One pass: a probe per pair, then gptbot, app-noindex and app-health, each of at most VERIFY_PROBE_S.
readonly VERIFY_CAP=1500 VERIFY_PROBE_S=15
readonly VERIFY_PASS_MAX=$(((${#VERIFY_PAIRS[@]} + 3) * VERIFY_PROBE_S))
# verify_live [<deadline ceiling, s>]: the live probes of the phase just applied, with the loop and
# bound in the header (VERIFY BOUND). Every phase: gptbot (bot_management, the crawler allowlist),
# app-noindex and app-health (an ssl rule or the zone SSL settings can 525/526 the app). The
# redirect pairs: redirects-dns only. VERIFY_PASS_MAX counts the pairs, so it bounds both phases.
verify_live() {
  local tries="${CFAM_VERIFY_TRIES:-12}" pause="${CFAM_VERIFY_SLEEP:-10}" dl="${CFAM_VERIFY_DEADLINE:-600}"
  local i bad u want pair hdrs got end cap nrc stuck ph="${MIGRATE_PHASE:-?}"
  local -a pairs=()
  [[ "$ph" != redirects-dns ]] || pairs=("${VERIFY_PAIRS[@]}")
  if [[ -n "${1:-}" && "$1" -lt "$dl" ]]; then dl="$1"; fi
  end=$((SECONDS + dl))
  cap=$((VERIFY_CAP - pause - VERIFY_PASS_MAX))
  if ((cap < end)); then end=$cap; fi
  # Each failing item carries what came back (<item>=><code>+<location>), so the annotation alone
  # tells a wrong destination from a 404, a timeout (000) or a 526 from the ssl=strict rule.
  for ((i = 1; i <= tries; i++)); do
    bad=""; stuck=""
    for pair in ${pairs[@]+"${pairs[@]}"}; do
      u="${pair%%|*}"; want="${pair#*|}"
      got="$(probe "$u")"
      [[ "$got" == "301 $want" ]] || bad+=" $u=>$(obs_line "$got")"
    done
    got="$(probe https://soleur.ai/ 'Mozilla/5.0 (compatible; GPTBot/1.2)')"
    served "$got" 200 || bad+=" gptbot=>$(obs_line "$got")"
    nrc=0
    hdrs="$(curl -sS -o /dev/null -D - --max-time "$VERIFY_PROBE_S" https://app.soleur.ai/ 2>/dev/null)" || nrc=$?
    if [[ "$nrc" -ne 0 ]] || ! grep -qiE '^x-robots-tag:.*noindex' <<<"$hdrs"; then
      got="$(noindex_obs "$hdrs")"
      [[ "$nrc" -eq 0 ]] || got+=" e=$nrc"
      bad+=" app-noindex=>$(obs_line "$got")"
    fi
    # redirects-dns creates the app's ssl=strict config rule and zone-rest the zone SSL settings:
    # prove the product still serves.
    got="$(probe https://app.soleur.ai/health)"
    served "$got" 200 || bad+=" app-health=>$(obs_line "$got")"
    # A 525/526 is a landed SSL setting: it will not heal while the loop waits, and the refusal is
    # what sends the ops email. Every other failure (a redirect still propagating) retries.
    [[ "$got" =~ ^52[56]\  && "$got" != *" e="* ]] && stuck="${got%% *}"
    if [[ -z "$bad" ]]; then printf '%s verify=%s verdict=ok\n' "$P" "$ph"; return 0; fi
    if [[ -n "$stuck" ]]; then
      printf '%s verify=%s pass=%s app-health=%s retry=stopped\n' "$P" "$ph" "$i" "$stuck"
      break
    fi
    # The deadline (VERIFY BOUND in the header) is checked after each failing pass, so the
    # verdict=fail line below prints before the job's timeout-minutes can cancel the run.
    if [[ "$i" -ge "$tries" ]] || ((SECONDS >= end)); then break; fi
    sleep "$pause"
  done
  VERIFY_FAILING="${bad# }"
  printf '%s verify=%s verdict=fail failing=%s\n' "$P" "$ph" "$VERIFY_FAILING"
  return 1
}

# probe_partial_apply: the best-effort probe after a failed apply, polled on a 60 s deadline (up to
# TRIES passes). A partial apply may already serve rules to every visitor.
probe_partial_apply() { verify_live 60; }

# partial_apply_verdict: sets the caller's `vf`. The probe starts only while it can still end by the
# verdict cap; a later refusal says verify=skipped instead of risking the refusal line.
readonly PROBE_LAST_START=$((VERIFY_CAP - VERIFY_PASS_MAX))
partial_apply_verdict() {
  if ((SECONDS > PROBE_LAST_START)); then vf="verify=skipped"; return 0; fi
  if probe_partial_apply; then vf="verify=ok"; else vf="failing=${VERIFY_FAILING}"; fi
}

run_apply() {
  local rc g fg="" fk="" fx="" vf="" rr="" sx="" msg remaining tok
  local -a bound=()
  cd "$ROOT" || refuse setup "cannot cd to the root"
  if [[ "$MIGRATE_PHASE" == tunnel ]]; then
    # Checked before the delete: an apply that cannot publish the CI-SSH pair must not start.
    [[ -n "$DOPPLER_WRITE_VALUE" ]] || refuse doppler-write-token-missing "DOPPLER_TOKEN_WRITE is not set, so the post-apply CI-SSH sync could not run. Nothing was deleted or applied."
    tunnel_predelete
  fi
  if [[ "$MIGRATE_PHASE" == redirects-dns ]]; then
    # The forget's stdout is kept: its backup=uploaded marker is printed after the backup reached R2
    # and before the one state rm, so without it this run forgot nothing; with it the write may have
    # started (REFUSAL FIELDS in the header).
    state_migrate | tee "$W/state-migrate.out"; rc=${PIPESTATUS[0]}
    if [[ "$rc" -ne 0 ]]; then
      # grep rc 2 (the kept output cannot be read) is not "no marker": take the safe branch.
      g=0; grep -q '^cf-state-migrate backup=uploaded ' "$W/state-migrate.out" 2>/dev/null || g=$?
      if [[ "$g" -ne 1 ]]; then
        refuse state-migrate-failed "the state forget did not finish with verdict=ok (see above) after its backup was uploaded, or its kept output could not be read: entries may already be forgotten. Runbook Halt: fix forward; the _PREV id restore no longer applies." "forget=committed"
      fi
      refuse state-migrate-failed "the state forget did not finish with verdict=ok (see above) and printed no backup=uploaded marker: read its verdict=abort line before re-dispatching." "forget=unknown"
    fi
    # From here on a refusal leaves the forget committed: the old-zone entries stay forgotten (backup
    # uri above) and a re-dispatch resumes with removed=0 (ADR-329 D10, CTO ruling 2026-11-20). The
    # _PREV id restore no longer applies. forget=committed is the field a reader of the verdict line
    # or the summary branches on; the prose says what to do.
    fg=" The state forget is committed (backup uri above); runbook Halt: fix forward and re-dispatch (the forget then removes 0); the _PREV id restore no longer applies."
    fk=" The state forget is committed (backup uri above); the _PREV id restore no longer applies."
    fx="forget=committed"
  fi
  plan_and_gate; rc=$?
  [[ "$rc" -ne 2 ]] || refuse entrypoint-gate-refused "the whole-list entrypoint gate refused (a live phase entrypoint is populated, or its emptiness could not be proven); adopt it with the printed import block first. Nothing was applied.${fg}" "$fx"
  [[ "$rc" -ne 5 ]] || refuse deploy-token-refused "the deploy policy's service token did not pass its live read (see the deploy-token line: 200, name github-actions-deploy, about 8760h to expiry). Nothing was applied; the pre-delete has already run."
  [[ "$rc" -eq 0 ]] || refuse gate-refused "the plan did not reach gate verdict=PASS; nothing was applied.$(gate_next "$rc" "$fg" "$fk")" "$fx"
  check_expected_isu "$fg" "$fx"
  # One INT, never a KILL, and --foreground so it reaches terraform once: a second INT makes it exit
  # at once and can lose in-flight creates from state. Keyed on an empty replace list, not the phase
  # name: with no replace the gate admits no delete, so an INT has no delete-then-create to split
  # (zone-rest's token replace would leave the prd secret deleted). A write started just before its
  # INT guarantees a partial apply, so too little budget refuses; a refusal writes nothing.
  if ((${#REPLACE_ARGS[@]} == 0)); then
    remaining=$((APPLY_DEADLINE - SECONDS))
    ((remaining >= APPLY_MIN_START)) || refuse apply-budget-exhausted "fewer than ${APPLY_MIN_START} s of the ${APPLY_DEADLINE} s apply budget remain; nothing was applied. Re-rehearse and re-dispatch once; on a second refusal stop for an owner decision.${fg}" "applied=false${fx:+ $fx}"
    bound=(timeout --foreground -s INT "$remaining")
  fi
  tok="$(cmd_token)" || refuse setup "cannot create the workflow-command token; nothing was applied.${fg}" "applied=false${fx:+ $fx}"
  printf '%s phase=%s mode=apply applying=true\n' "$P" "$MIGRATE_PHASE"
  printf '::stop-commands::%s\n' "$tok"
  tf_env ${bound[@]+"${bound[@]}"} terraform apply -no-color -input=false -auto-approve "$W/tfplan" 2>&1 | tf_redact_random_ids | tf_line
  rc=${PIPESTATUS[0]}
  printf '\n::%s::\n' "$tok"
  if [[ "$rc" -ne 0 ]]; then
    # apply-failed stays the reason; the result of the best-effort probe is a field.
    msg="terraform apply of the graded plan failed (exit $rc); state may hold a partial apply."
    if ((rc == 124 && ${#bound[@]} > 0)); then msg+=" exit 124 is the apply's one INT at APPLY_DEADLINE firing."; fi
    [[ "$NORM_COUNT" -eq 0 ]] || { reread_records; rr="reread=$REREAD"; }
    partial_apply_verdict
    [[ -z "$rr" ]] || msg+=" Re-read of the DNS records: ${REREAD}."
    msg+=" Probe of the partial apply (polled on a 60 s deadline): ${vf}.$(halt_pointer "$rr" "$vf")"
    # A re-read that did not come back clean routes to its own Halt bullet, not to a re-dispatch.
    if [[ -n "$rr" && "$rr" != reread=ok ]]; then
      refuse apply-failed "$msg" "$(join_fields "$fx" "$rr" "$vf")"
    fi
    msg+=" Fix forward (a reviewed PR if the cause is in code), then re-dispatch the same phase:"
    [[ "$MIGRATE_PHASE" != redirects-dns ]] || msg+=" the forget then removes 0 (cf-state-migrate verdict=ok removed=0), a record whose PATCH failed plans a no-op if live still matches, a record the apply never reached still plans the admitted import-normalize update, and"
    refuse apply-failed "$msg only the remainder is planned and gated." "$(join_fields "$fx" "$rr" "$vf")"
  fi
  printf '%s phase=%s mode=apply applied=true\n' "$P" "$MIGRATE_PHASE"
  if [[ "$NORM_COUNT" -gt 0 ]]; then
    reread_records || {
      partial_apply_verdict
      refuse import-normalize-reread-failed "the apply finished, but the re-read of the DNS records did not match the graded plan: ${REREAD}. Public probes: ${vf}.$(halt_pointer "$REREAD" "$vf")" "$(join_fields "applied=true" "$fx" "reread=$REREAD" "$vf")"
    }
  fi
  local what="noindex/crawler/app-health" halt
  # One Halt for both phases: the runbook's CTO ruling acts on each failing item by its code, after either
  # phase (the app's ssl configuration rule pins Strict whatever the zone-wide setting zone-rest writes).
  halt="act on each failing item by its code. app-health=>525/526: the owner may make one dashboard edit on the NEW zone only (the ssl rule, Strict to Full), then redeliver the window's failed GitHub webhook deliveries (Halt step 2). app-health 3xx whose Location equals a Terraform redirect target: the owner removes that one rule or list item on the NEW zone or account. app-health 000, any other app-health code, or a 3xx no Terraform target matches: no edit, stop for an owner decision. gptbot=>403 after redirects-dns with fight_mode recorded true: the runbook's one allowed next-phase start (run zone-rest). Any other gptbot, app-noindex or redirect-pair failure: no dashboard edit, fix forward. Then a fix-forward PR, a rehearsal, and a re-dispatch of this phase with expected_in_state_updates set to the rehearsal's admitted set (the dashboard-edited rule must plan as a no-op; only a rule nobody edited plans as an in-state update)."
  [[ "$MIGRATE_PHASE" != redirects-dns ]] || what="redirect/$what"
  # A failed sync does not skip the probes: the operator needs both results from this one run.
  if [[ "$MIGRATE_PHASE" == tunnel ]]; then sync_ci_ssh || sx="ci_ssh_sync=failed"; fi
  verify_live || refuse verify-failed "applied, but the ${what} probes did not all pass: ${VERIFY_FAILING}. Runbook Halt, verify-failed: ${halt}" "applied=true${fx:+ $fx}${sx:+ $sx} failing=${VERIFY_FAILING}"
  [[ -z "$sx" ]] || refuse ci-ssh-sync-failed "applied and the live probes passed, but CI_SSH_ACCESS_TOKEN_ID/_SECRET did not reach prd_terraform (see the ci-ssh-sync line), so the CI SSH bridge still holds the old pair. Re-dispatch this phase: every created address plans no-op and the sync runs again." "applied=true"
  printf '%s phase=%s mode=apply verdict=PASS applied=true\n' "$P" "$MIGRATE_PHASE"
  summary "verdict=PASS applied=true"
}

main() {
  # Provider / state debug logging prints secrets; nothing this job runs may inherit it.
  unset TF_LOG TF_LOG_PATH TF_LOG_CORE TF_LOG_PROVIDER
  # A plain shell variable from here on: only sync_ci_ssh hands it to one doppler call.
  DOPPLER_WRITE_VALUE="${DOPPLER_TOKEN_WRITE:-}"
  unset DOPPLER_TOKEN_WRITE
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
