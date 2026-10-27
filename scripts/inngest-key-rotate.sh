#!/usr/bin/env bash
# inngest-key-rotate.sh - the orchestration body of .github/workflows/inngest-key-rotate.yml (#10540, ADR-304 provisional).
#
# Rotates the two Inngest shared secrets (INNGEST_SIGNING_KEY, INNGEST_EVENT_KEY) on BOTH copies, in two Terraform phases with a
# host reboot and a verification between them, then redeploys the web fleet:
#
#   inngest-key-rotate.sh guard      refusal ladder; outputs the go/no-go and what the later jobs need (no writes)
#   inngest-key-rotate.sh apply1     phase 1: -replace the dedicated random_id(s), update the dedicated Doppler secret(s)
#                                    (mode=plan: plan Gate A and Gate B only, write nothing)
#   inngest-key-rotate.sh reboot     the ONE Hetzner control-plane soft reboot of the host named soleur-inngest (one POST)
#   inngest-key-rotate.sh verify     wait for a NEW boot_id, then SERVING + a tls-health row with listener=1 (Better Stack)
#   inngest-key-rotate.sh apply2     phase 2: -replace the app doppler_secret(s) in soleur/prd (their value derives from the
#                                    already-replaced dedicated random_id); assert both copies are equal (value-silent)
#   inngest-key-rotate.sh redeploy   canary-then-prod fleet redeploy through dispatch-web-redeploy/track.sh
#   inngest-key-rotate.sh --print-contract   offline: the fixed verdict-token list (preflight Check 10 runs it)
#
# THE REPOSITORY IS PUBLIC. random_id's `id` IS the key in base64url and `hex` is not sensitive to Terraform, so a plan,
# an apply, a refresh or `terraform show` prints key bytes. This script therefore NEVER lets a Terraform stream reach a log:
# every Terraform call goes through kr_tf, which sends stdout and stderr to a file under a private temp dir, unsets TF_LOG,
# and prints nothing. The plan, the plan JSON and the temp dir are never printed, never uploaded, and removed on exit. On a
# failure only the exit code and jq-derived ADDRESSES and ACTIONS are printed. A copy of a key is read only through a pipe
# into sha256sum (kr_hash); only booleans leave that function.
#
# FAILURE SEMANTICS (plan table "Failure semantics"). A refusal before any write prints one fixed verdict token and writes
# nothing. A failure after a write prints ONE stop sentence with the exact `converge` command (it needs the owner's own
# per-command go; no agent runs it), files one action-required issue, and exits non-zero. There is no automatic retry, no
# hard reset and no second reboot POST. `converge` never mints a key.
#
# Environment (supplied by the workflow; nothing is echoed):
#   INPUT_MODE INPUT_KEYS INPUT_CONFIRM INPUT_REASON INPUT_ROTATED_AT INPUT_QUIET_WINDOW   the dispatch inputs (guard)
#   EFF_MODE EFF_KEYS EFF_SERVER_ID EFF_BOOT_PRE EFF_ROTATED_AT EFF_REBOOT_POST EFF_POST_EPOCH   the guard's outputs (write jobs)
#   GITHUB_RUN_ID GITHUB_RUN_ATTEMPT GITHUB_REPOSITORY GITHUB_SERVER_URL GITHUB_OUTPUT GITHUB_STEP_SUMMARY RUNNER_TEMP GH_TOKEN
#   DOPPLER_TOKEN                         Tier-A repo secret: doppler run -c prd_terraform, the link flag, HCLOUD_TOKEN_READONLY (guard)
#   DOPPLER_TOKEN_TF AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY HCLOUD_TOKEN   exported by the infra-credentials loader (apply, reboot)
#   BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}   the Better Stack read credentials (guard, verify)
#   WEBHOOK_DEPLOY_SECRET CF_ACCESS_CLIENT_ID CF_ACCESS_CLIENT_SECRET WEB_HOST_PRIVATE_IPS   the fleet redeploy (track.sh)
# Test seams (NEVER set by the workflow; the suite asserts it): KR_SLEEP KR_NOW KR_HZ_BASE KR_TRACK KR_HOST_STATE KR_BS_QUERY
#   KR_INFRA_DIR.

# shellcheck disable=SC2034,SC2016  # budget vars are read by the workflow suite (it sources this file); KR_HZ_TOKEN is read by NAME in bc_curl; the jq programs are single-quoted on purpose
set -uo pipefail

case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles live credentials and -x would print them (see #7797)\n' >&2; exit 78 ;;
esac
export LC_ALL=C

KR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ---------------------------------------------------------------------------------------------------------------------------
# THE VERDICT TOKENS. The one fixed vocabulary of this script: every ::error:: and every summary line carries
# `inngest-key-rotate verdict=<token>` with a token from this list and nothing free-form in its place. `--print-contract`
# prints it; the suite pins that the list and the verdict literals used below are the same set.
KR_VERDICT_TOKENS=(
  guard_ok inputs_invalid rerun_refused confirm_mismatch quiet_window_missing credential_absent
  link_flag_unreadable link_flag_unset link_flag_pending link_flag_invalid soak_unreadable soak_open
  run_list_unreadable run_in_flight hetzner_unreadable host_not_unique host_state_unreadable host_not_serving_pre
  converge_source_missing converge_mismatch
  plan_ok plan_gate_refused terraform_failed apply1_ok apply_failed copy_unreadable value_unchanged copies_differ
  apply2_ok apply2_skipped
  reboot_post_failed reboot_action_failed reboot_refused_second_post reboot_ok host_silent host_not_serving host_read_failed
  redeploy_failed rotate_ok converge_ok internal_error
)

kr_print_contract() {
  printf 'inngest-key-rotate verdict-tokens\n'
  printf '%s\n' "${KR_VERDICT_TOKENS[@]}"
}

# ---------------------------------------------------------------------------------------------------------------------------
# BUDGET TABLE (seconds). The ONE place the route's deadlines are stated; inngest-key-rotate-workflow.test.sh pins the
# workflow's timeout-minutes to it (each step/job minutes = the value rounded up). Every number is the pipeline's own
# invariant or a sum of the others.
#   KR_GUARD_S           guard job: Doppler/GitHub/Hetzner/Better Stack reads and one host-state read
KR_GUARD_S=900
#   Terraform (kr_tf): init, one plan+show (two in mode=plan: Gate A and Gate B), one apply
KR_TF_INIT_S=300
KR_TF_PLAN_S=900
KR_TF_APPLY_S=900
KR_STEP_SLACK_S=300
#   KR_APPLY_STEP_S      the apply step = init + two plans + apply + slack (apply1 in mode=plan runs both plans, no apply)
KR_APPLY_STEP_S=$((KR_TF_INIT_S + 2 * KR_TF_PLAN_S + KR_TF_APPLY_S + KR_STEP_SLACK_S))
#   Reboot: the POST plus the Hetzner action poll, then the verification read. The Hetzner `success` only means the ACPI
#   request reached the guest, so evidence is a new boot_id (KR_BOOT_WAIT_S from the POST) and SERVING + tls-health listener=1
#   (KR_VERIFY_S from the POST, which CONTAINS the boot wait). Never a hard reset.
KR_REBOOT_ACTION_S=300
KR_BOOT_WAIT_S=600
KR_VERIFY_S=900
KR_POLL_S=30
KR_REBOOT_STEP_S=$((KR_REBOOT_ACTION_S + KR_STEP_SLACK_S))
KR_VERIFY_STEP_S=$((KR_VERIFY_S + KR_STEP_SLACK_S))
#   Redeploy: bounded by the pipeline's own ceiling (ci-deploy-wrapper.sh hard-kills ci-deploy.sh at 4800 s)
KR_PIPELINE_CEILING_S=4800
KR_REDEPLOY_S=4800
KR_JOB_SLACK_S=600
KR_GUARD_JOB_S=$((KR_GUARD_S + KR_JOB_SLACK_S))
KR_APPLY_JOB_S=$((KR_APPLY_STEP_S + KR_JOB_SLACK_S))
KR_REBOOT_JOB_S=$((KR_REBOOT_STEP_S + KR_VERIFY_STEP_S + KR_JOB_SLACK_S))
KR_REDEPLOY_JOB_S=$((KR_REDEPLOY_S + KR_JOB_SLACK_S))

KR_SLEEP="${KR_SLEEP:-sleep}"
KR_NOW="${KR_NOW:-date +%s}"
KR_HZ_BASE="${KR_HZ_BASE:-https://api.hetzner.cloud}"
KR_TRACK="${KR_TRACK:-$KR_ROOT/.github/actions/dispatch-web-redeploy/track.sh}"
KR_HOST_STATE="${KR_HOST_STATE:-$KR_ROOT/scripts/inngest-host-state.sh}"
KR_BS_QUERY="${KR_BS_QUERY:-$KR_ROOT/scripts/betterstack-query.sh}"
KR_INFRA_DIR="${KR_INFRA_DIR:-$KR_ROOT/apps/web-platform/infra}"

KR_SERVER_NAME="soleur-inngest"
KR_SERVER_IP="10.0.1.40"
KR_SOAK_ISSUE=11215
KR_WORKFLOW_FILE="inngest-key-rotate.yml"
KR_INFLIGHT_WORKFLOWS=(apply-web-platform-infra.yml inngest-link-flip.yml cutover-inngest.yml deploy-inngest-image.yml web-platform-release.yml inngest-key-rotate.yml)
KR_HOST_PROJECT="soleur-inngest"
KR_APP_PROJECT="soleur"
KR_COPY_CONFIG="prd"
# sha256 of the empty string: a secret that reads back empty hashes to this and is refused (value_unchanged would otherwise
# pass on two empty copies).
KR_EMPTY_SHA="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

# ---------------------------------------------------------------------------------------------------------------------------
# THE GATE TABLE (Guard 1). Gate A (phase 1) and Gate B (phase 2) are built from THIS ONE TABLE: the -target list, the -replace
# flags and the jq allowlist applied to `terraform show -json` all derive from it through kr_gate_rows, so no construction
# site can drift from the others. Fields: phase|key|address|flag|actions. flag=replace means the address is targeted AND
# replaced; flag=target means targeted only (it changes because a replaced address feeds it). Rows of phase B also accept the
# documented recovery shape (a bare ["create"] whose `before` is null: the destroy half of a -replace ran, the create did not).
# No row of phase A accepts a bare create: a new random_id where none was in state would mint a key nobody asked for.
KR_GATE_TABLE=(
  'A|signing|random_id.inngest_signing_key_dedicated|replace|delete,create'
  'A|event|random_id.inngest_event_key_dedicated|replace|delete,create'
  'A|signing|doppler_secret.inngest_signing_key_dedicated|target|update'
  'A|event|doppler_secret.inngest_event_key_dedicated|target|update'
  'B|signing|doppler_secret.inngest_signing_key_prd|replace|delete,create'
  'B|event|doppler_secret.inngest_event_key_prd|replace|delete,create'
)

declare -A KR_BOOL=()
KR_BOOL_ORDER=()
KR_TMP=""
KR_POSTED=0
KR_CHECK_TOKEN="internal_error"
KR_CHECK_DETAIL=""
KR_GUARD_MODE=""
KR_SERVER_ID=""
KR_BOOT_PRE="-"
KR_ROTATED_AT=""
KR_REBOOT_POST="false"
KR_DERIVED_KEYS=""
KR_HZ_TOKEN=""
KR_HS_RC=0
KR_HS_SERVING=""
KR_HS_BOOT=""
KR_HS_OBS=0
KR_BS_RC=0
KR_ACTION_ID=""
KR_VERDICT=""

kr_now() { $KR_NOW; }
kr_sleep() { $KR_SLEEP "$1"; }
kr_log() { printf '%s\n' "$*" >&2; }
kr_iso() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
kr_epoch() { date -u -d "$1" +%s 2>/dev/null || echo 0; }

# kr_scrub: stdin -> one line, at most 200 characters (KR_SCRUB_CAP raises it for the stop sentence), safe for a PUBLIC run log. It covers the SHORT error bodies of Hetzner,
# Better Stack and gh only; Terraform output is never scrubbed because it is never printed. Redacts [id=...] groups, signkey-
# strings, hex runs of 41 or more (a key is 64; a 40-hex git SHA passes), base64url runs of 41 or more (a key id is 43),
# Authorization/Bearer values, and breaks any `::` so no workflow command can be smuggled in.
kr_scrub() {
  tr -d '\r\000' | tr '\n' ' ' | sed -E \
    -e 's/\[id=[^]]*\]/[id=<redacted>]/g' \
    -e 's/(signkey-(prod|test)-)[A-Za-z0-9_-]+/\1<redacted>/g' \
    -e 's/[A-Fa-f0-9]{41,}/<hex-redacted>/g' \
    -e 's/[A-Za-z0-9_-]{41,}/<token-redacted>/g' \
    -e 's/(Bearer|Authorization:?)[[:space:]]+[^[:space:]]+/\1 <redacted>/Ig' \
    -e 's/::/: :/g' | cut -c1-"${KR_SCRUB_CAP:-200}"
}

kr_token_known() {
  local t
  for t in "${KR_VERDICT_TOKENS[@]}"; do [[ "$t" == "$1" ]] && return 0; done
  return 1
}

kr_summary() { [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && printf '%s\n' "$*" >> "$GITHUB_STEP_SUMMARY" 2>/dev/null; return 0; }

kr_out() { # kr_out <name> <value>: a job output; the value is one validated line
  [[ "$2" != *$'\n'* ]] || return 0
  [[ -n "${GITHUB_OUTPUT:-}" ]] && printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT" 2>/dev/null
  return 0
}

# kr_refuse <token> <detail>: a refusal; nothing was written. detail is a fixed sentence of this script, scrubbed anyway.
kr_refuse() {
  local t="$1" d
  kr_token_known "$t" || t="internal_error"
  d="$(printf '%s' "${2:-}" | kr_scrub)"
  KR_VERDICT="$t"
  printf '::error::inngest-key-rotate verdict=%s %s\n' "$t" "$d" >&2
  kr_summary "- inngest-key-rotate verdict=${t}: ${d}"
  kr_out verdict "$t"
  return 0
}

# kr_ok <token> <detail>: a success line, same shape.
kr_ok() {
  local t="$1" d
  kr_token_known "$t" || t="internal_error"
  d="$(printf '%s' "${2:-}" | kr_scrub)"
  KR_VERDICT="$t"
  printf 'inngest-key-rotate verdict=%s %s\n' "$t" "$d" >&2
  kr_summary "- inngest-key-rotate verdict=${t}: ${d}"
  kr_out verdict "$t"
  return 0
}

kr_cleanup() {
  [[ -n "$KR_TMP" && -d "$KR_TMP" ]] && rm -rf -- "$KR_TMP"
  return 0
}

kr_init() {
  local base="${RUNNER_TEMP:-${TMPDIR:-/var/tmp}}"
  [[ -n "$KR_TMP" ]] && return 0
  KR_TMP="$(mktemp -d "${base%/}/inngest-key-rotate.XXXXXX")" || { kr_refuse internal_error "could not create the private temp dir"; return 1; }
  chmod 700 "$KR_TMP"
  trap kr_cleanup EXIT
  # shellcheck source=/dev/null
  source "$KR_ROOT/scripts/lib/bearer-curl.sh" || { kr_refuse internal_error "scripts/lib/bearer-curl.sh could not be loaded"; return 1; }
  for b in jq curl; do
    command -v "$b" >/dev/null 2>&1 || { kr_refuse internal_error "${b} is not on PATH"; return 1; }
  done
  return 0
}

kr_secret_name() { case "$1" in signing) printf 'INNGEST_SIGNING_KEY' ;; event) printf 'INNGEST_EVENT_KEY' ;; *) return 1 ;; esac; }
kr_keys_list() { case "$1" in signing) printf 'signing' ;; event) printf 'event' ;; both) printf 'signing event' ;; *) return 1 ;; esac; }

kr_valid_mode_keys() {
  case "${1:-}" in plan|rotate|converge) ;; *) kr_refuse inputs_invalid "mode must be plan, rotate or converge"; return 1 ;; esac
  case "${2:-}" in signing|event|both) ;; *) kr_refuse inputs_invalid "keys must be signing, event or both"; return 1 ;; esac
}

# ---------------------------------------------------------------------------------------------------------------------------
# Hetzner (control plane). The token reaches curl on its stdin config through bearer-curl.sh (ADR-280), never an argument.
# kr_hz <GET|POST> <path> <out-file>: prints the HTTP code ("000" on a transport failure or a refused credential).
kr_hz() {
  local method="$1" path="$2" out="$3" code
  code="$(bc_curl inngest-key-rotate 'Authorization:Bearer :KR_HZ_TOKEN' -- -sS --connect-timeout 5 --max-time 20 \
    -o "$out" -w '%{http_code}' -X "$method" "${KR_HZ_BASE}${path}")" || code=000
  printf '%s' "$code"
}

# kr_load_ro_token: the guard's Hetzner token is the READ-ONLY one (HCLOUD_TOKEN_READONLY, Tier-A prd_terraform); the write
# token never reaches the guard job.
kr_load_ro_token() {
  local t
  t="$(doppler secrets get HCLOUD_TOKEN_READONLY --plain -p soleur -c prd_terraform 2>/dev/null)" || t=""
  bc_ok "$t" || return 1
  printf '::add-mask::%s\n' "$t"
  KR_HZ_TOKEN="$t"
}

# kr_resolve_server: exactly one server named soleur-inngest AND it carries the private IP 10.0.1.40. Sets KR_SERVER_ID.
kr_resolve_server() {
  local f="$KR_TMP/servers.json" code n
  code="$(kr_hz GET "/v1/servers?name=${KR_SERVER_NAME}" "$f")"
  if [[ "$code" != 200 ]]; then KR_CHECK_TOKEN=hetzner_unreadable; KR_CHECK_DETAIL="the server lookup answered HTTP ${code}"; return 1; fi
  n="$(jq -r --arg n "$KR_SERVER_NAME" --arg ip "$KR_SERVER_IP" \
    '[.servers[]? | select(.name == $n and any(.private_net[]?; .ip == $ip)) | .id] | if length == 1 then .[0] else "none" end' "$f" 2>/dev/null)" || n=none
  if [[ ! "$n" =~ ^[0-9]+$ ]]; then KR_CHECK_TOKEN=host_not_unique; KR_CHECK_DETAIL="not exactly one server named ${KR_SERVER_NAME} with private IP ${KR_SERVER_IP}"; return 1; fi
  KR_SERVER_ID="$n"
}

# kr_reboot_post <server-id>: sets KR_ACTION_ID. THE ONLY CALLER OF THE HETZNER POST IN THIS ROUTE, and a per-process latch
# makes a second call a refusal: the latch is set BEFORE the request, so a failed POST is not retried either. (No command
# substitution at the call site: the latch and the verdict must live in THIS process.)
kr_reboot_post() {
  local code
  KR_ACTION_ID=""
  if [[ "$KR_POSTED" == 1 ]]; then kr_refuse reboot_refused_second_post "a second reboot POST in one run is refused"; return 1; fi
  KR_POSTED=1
  code="$(kr_hz POST "/v1/servers/${1}/actions/reboot" "$KR_TMP/post.json")"
  if [[ ! "$code" =~ ^2[0-9][0-9]$ ]]; then KR_CHECK_DETAIL="the reboot POST answered HTTP ${code}"; return 1; fi
  KR_ACTION_ID="$(jq -r '.action.id // empty' "$KR_TMP/post.json" 2>/dev/null)" || KR_ACTION_ID=""
  [[ "$KR_ACTION_ID" =~ ^[0-9]+$ ]] || { KR_CHECK_DETAIL="the reboot POST returned no action id"; KR_ACTION_ID=""; return 1; }
}

# ---------------------------------------------------------------------------------------------------------------------------
# Better Stack (the only channel that reaches the dedicated host). Host text never leaves the runner: the host-state output
# is parsed with anchored patterns and only fixed tokens are printed.
# kr_read_host <since>: runs scripts/inngest-host-state.sh; sets KR_HS_RC, KR_HS_SERVING (yes|no|""), KR_HS_BOOT (8 hex|""),
# KR_HS_OBS (epoch|0).
kr_read_host() {
  local f="$KR_TMP/hs.out" obs
  KR_HS_RC=0; KR_HS_SERVING=""; KR_HS_BOOT=""; KR_HS_OBS=0
  timeout 240 bash "$KR_HOST_STATE" --since "$1" --no-errors > "$f" 2> "$KR_TMP/hs.err" || KR_HS_RC=$?
  [[ "$KR_HS_RC" == 0 ]] || return 0
  KR_HS_SERVING="$(sed -n -E 's/^  VERDICT        (NOT )?SERVING   SERVING=(yes|no)( .*)?$/\2/p' "$f" | head -1)"
  KR_HS_BOOT="$(sed -n -E 's/^  boot_id        ([0-9a-f]{8,36})$/\1/p' "$f" | head -1)"
  KR_HS_BOOT="${KR_HS_BOOT:0:8}"
  obs="$(sed -n -E 's/^  observed_at    ([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}).*$/\1/p' "$f" | head -1)"
  [[ -n "$obs" ]] && KR_HS_OBS="$(kr_epoch "${obs/ /T}Z")"
  return 0
}

# kr_tls_rows <since-iso>: writes the dedicated host's tls-health series to $KR_TLS (tab-separated, oldest first):
#   epoch<TAB>boot_id(8)<TAB>listener<TAB>host. Isolation mirrors scripts/followthroughs/inngest-tls-soak-10136.sh (marker,
# stage, shipper) and pins host=soleur-inngest. Returns non-zero when the read FAILED (KR_BS_RC; no verdict, never "not serving").
kr_tls_rows() {
  local raw
  KR_BS_RC=0
  : > "$KR_TMP/tls.tsv"
  raw="$(timeout 180 "$KR_BS_QUERY" --since "$1" --grep stage=tls-health --limit 2000 2>"$KR_TMP/bs.err")" || { KR_BS_RC=$?; return 1; }
  printf '%s\n' "$raw" | jq -R -r '
    def kv($d; $k): (first($d | capture("(^|\\s)" + $k + "=(?<v>[^\\s]+)") | .v) // "-");
    fromjson? | objects | . as $o
    | ($o.raw? | strings | fromjson? | objects) as $r
    | select($r.marker == "SOLEUR_INNGEST_BOOT_STAGE")
    | select($r.stage == "tls-health")
    | select($r.shipper == "cloud-init-phone-home")
    | select(($r.host? // "") == "soleur-inngest")
    | (($o.dt // "") | tostring | sub("T"; " ") | sub("Z$"; "") | sub("\\.[0-9]+$"; "")) as $d
    | (try ($d | strptime("%Y-%m-%d %H:%M:%S") | mktime) catch null) as $e
    | ($r.detail // "") as $det
    | select($e != null)
    | [($e | tostring), (kv($det; "boot_id") | .[0:8]), kv($det; "listener"), $r.host] | @tsv' 2>/dev/null | sort -s -n -k1,1 > "$KR_TMP/tls.tsv"
  return 0
}

# kr_bs_classify: the class token of a failed Better Stack read (shared classifier), for the message; never the body.
kr_bs_classify() {
  local lib="$KR_ROOT/scripts/lib/betterstack-read-classify.sh" cls="other"
  # shellcheck source=/dev/null
  if [[ -f "$lib" ]] && source "$lib" 2>/dev/null; then cls="$(bs_read_classify "$KR_BS_RC" "$KR_TMP/bs.err" 2>/dev/null)" || cls=other; fi
  printf '%s' "$cls"
}

# ---------------------------------------------------------------------------------------------------------------------------
# Value-silent compare. The key exists only on the pipe into sha256sum; only a hash (never printed) or a boolean leaves.
# kr_hash <host|app> <signing|event>: prints the sha256 hex or returns 1 (unreadable or empty). Used by the apply jobs, which
# hold the provider token (DOPPLER_TOKEN_TF) that can read both projects.
kr_hash() {
  local proj name h
  case "$1" in host) proj="$KR_HOST_PROJECT" ;; app) proj="$KR_APP_PROJECT" ;; *) return 2 ;; esac
  name="$(kr_secret_name "$2")" || return 2
  h="$(DOPPLER_TOKEN="${DOPPLER_TOKEN_TF:-}" doppler secrets get "$name" --plain -p "$proj" -c "$KR_COPY_CONFIG" 2>/dev/null | sha256sum | cut -c1-64)" || return 1
  [[ "$h" =~ ^[0-9a-f]{64}$ && "$h" != "$KR_EMPTY_SHA" ]] || return 1
  printf '%s' "$h"
}

# kr_copies_equal <key>: 0 equal, 1 differ, 2 unreadable. Prints nothing.
kr_copies_equal() {
  local a b
  a="$(kr_hash host "$1")" || return 2
  b="$(kr_hash app "$1")" || return 2
  [[ "$a" == "$b" ]]
}

# ---------------------------------------------------------------------------------------------------------------------------
# Terraform. kr_tf is THE chokepoint: nothing else in this script runs terraform.
# kr_tf <name> <terraform args...>: stdout -> $KR_TMP/tf-<name>.out, stderr -> $KR_TMP/tf-<name>.err, nothing printed, TF_LOG
# and friends unset. The variables of the plan come from `doppler run --preserve-env ... --name-transformer tf-var` (the loader's
# Tier-B values win under --preserve-env).
kr_tf() {
  local name="$1" rc=0
  shift
  ( cd "$KR_INFRA_DIR" && env -u TF_LOG -u TF_LOG_PATH -u TF_LOG_CORE -u TF_LOG_PROVIDER TF_IN_AUTOMATION=1 \
      timeout --kill-after=30 "${KR_TF_T:-$KR_TF_PLAN_S}" \
      doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- \
      terraform "$@" > "$KR_TMP/tf-${name}.out" 2> "$KR_TMP/tf-${name}.err" ) || rc=$?
  return "$rc"
}

# kr_gate_rows <A|B> <keys-list>: the table rows of a phase for the selected keys (space-separated: "signing event").
kr_gate_rows() {
  local row ph key addr flag acts k
  for row in "${KR_GATE_TABLE[@]}"; do
    IFS='|' read -r ph key addr flag acts <<<"$row"
    [[ "$ph" == "$1" ]] || continue
    for k in $2; do
      [[ "$k" == "$key" ]] && printf '%s|%s|%s|%s|%s\n' "$ph" "$key" "$addr" "$flag" "$acts"
    done
  done
}

# The three construction sites of Guard 1, each derived from kr_gate_rows and from nothing else.
kr_gate_targets() { # one -target= per selected row
  local row ph key addr flag acts
  while IFS='|' read -r ph key addr flag acts; do
    [[ -n "$addr" ]] && printf -- '-target=%s\n' "$addr"
  done < <(kr_gate_rows "$1" "$2")
}
kr_gate_replaces() { # one -replace= per selected row whose flag is replace
  local row ph key addr flag acts
  while IFS='|' read -r ph key addr flag acts; do
    [[ "$flag" == replace ]] && printf -- '-replace=%s\n' "$addr"
  done < <(kr_gate_rows "$1" "$2")
}
kr_gate_want() { # the jq allowlist: [{address, actions, recovery}]
  local row ph key addr flag acts rec
  while IFS='|' read -r ph key addr flag acts; do
    [[ -n "$addr" ]] || continue
    rec=false; [[ "$ph" == B ]] && rec=true
    jq -cn --arg a "$addr" --arg acts "$acts" --argjson r "$rec" '{address: $a, actions: ($acts | split(",")), recovery: $r}'
  done < <(kr_gate_rows "$1" "$2") | jq -cs '.'
}

KR_GATE_JQ='
  [.resource_changes[]? | select((.change.actions == ["no-op"] or .change.actions == ["read"]) | not)] as $c
  | ($c | length) as $n
  | ($want | length) as $w
  | ($c | map(. as $x | select(any($want[]; . as $r
        | $r.address == $x.address and ($x.index? == null) and $x.mode == "managed"
          and ($x.change.actions == $r.actions
               or ($r.recovery and $x.change.actions == ["create"] and $x.change.before == null))))) | length) as $ok
  | (($want | map(.address) | sort) == ($c | map(.address) | sort)) as $same
  | $w > 0 and $n == $w and $ok == $n and $same'

# kr_gate <A|B> <keys-list> <plan-json>: 0 = the plan changes exactly the table's addresses with exactly its action arrays
# (and a change count equal to the table size: `all()` over [] is true, so the count is what makes an empty plan fail). On a
# refusal it prints verdict=plan_gate_refused with the first failing property and sanitized addresses/actions ONLY.
kr_gate() {
  local phase="$1" keys="$2" plan="$3" want n w reason lines
  want="$(kr_gate_want "$phase" "$keys")" || want="[]"
  if jq -e --argjson want "$want" "$KR_GATE_JQ" "$plan" >/dev/null 2>&1; then return 0; fi
  n="$(jq -r '[.resource_changes[]? | select((.change.actions == ["no-op"] or .change.actions == ["read"]) | not)] | length' "$plan" 2>/dev/null)" || n="?"
  w="$(jq -r 'length' <<<"$want" 2>/dev/null)" || w="?"
  if [[ ! "$n" =~ ^[0-9]+$ ]]; then reason="plan_unparseable"
  elif [[ "$n" != "$w" ]]; then reason="change_count_${n}_want_${w}"
  else reason="address_or_action_outside_the_table"; fi
  lines="$(jq -r --argjson want "$want" '
      [.resource_changes[]? | select((.change.actions == ["no-op"] or .change.actions == ["read"]) | not)] as $c
      | ([$c[] | . as $x | select(any($want[]; .address == $x.address and ($x.change.actions == .actions or (.recovery and $x.change.actions == ["create"] and $x.change.before == null))) | not)
          | "\(.address) \(.change.actions | join(","))"] | .[:5] | join("; ")) as $off
      | ([$want[] | .address as $a | select(any($c[]; .address == $a) | not) | .address] | .[:3] | join("; ")) as $miss
      | "offending: \($off) | missing: \($miss)"' "$plan" 2>/dev/null | tr -cd 'A-Za-z0-9_.,;:|[] -' | cut -c1-380)" || lines=""
  KR_SCRUB_CAP=420 kr_refuse plan_gate_refused "gate ${phase} refused (${reason}); ${lines:-no detail}; nothing was applied"
  return 1
}

# kr_gate_plan <A|B> <keys-list> <name>: plan, show, gate. On success $KR_TMP/tfplan-<name> is the saved plan.
kr_gate_plan() {
  local phase="$1" keys="$2" name="$3" rc=0
  local -a targets repls
  mapfile -t targets < <(kr_gate_targets "$phase" "$keys")
  mapfile -t repls < <(kr_gate_replaces "$phase" "$keys")
  kr_tf "plan-${name}" plan -no-color -input=false -out="$KR_TMP/tfplan-${name}" -var="ssh_key_path=${KR_TMP}/ci_ssh_key.pub" \
    "${targets[@]}" "${repls[@]}" || rc=$?
  if [[ "$rc" != 0 ]]; then kr_refuse terraform_failed "the plan step (${name}) exited ${rc}; its output stays on the runner (it carries key bytes)"; return 1; fi
  rc=0
  kr_tf "show-${name}" show -json "$KR_TMP/tfplan-${name}" || rc=$?
  if [[ "$rc" != 0 ]]; then kr_refuse terraform_failed "the plan-to-JSON step (${name}) exited ${rc}; its output stays on the runner (it carries key bytes)"; return 1; fi
  kr_gate "$phase" "$keys" "$KR_TMP/tf-show-${name}.out"
}

kr_tf_prepare() { # init + the throwaway public key var.ssh_key_path must parse
  local rc=0
  [[ -n "${AWS_ACCESS_KEY_ID:-}" && -n "${AWS_SECRET_ACCESS_KEY:-}" && -n "${DOPPLER_TOKEN:-}" && -n "${DOPPLER_TOKEN_TF:-}" ]] \
    || { kr_refuse credential_absent "the Terraform backend pair, DOPPLER_TOKEN or DOPPLER_TOKEN_TF is not set (loader or secret missing)"; return 1; }
  ssh-keygen -t ed25519 -f "$KR_TMP/ci_ssh_key" -N "" -q >/dev/null 2>&1 || { kr_refuse internal_error "ssh-keygen failed"; return 1; }
  KR_TF_T="$KR_TF_INIT_S" kr_tf init init -input=false -lockfile=readonly || rc=$?
  if [[ "$rc" != 0 ]]; then kr_refuse terraform_failed "the init step exited ${rc}; its output stays on the runner"; return 1; fi
}

# ---------------------------------------------------------------------------------------------------------------------------
# Failure reporting. After a WRITE has been attempted the route stops: one stop sentence with the exact converge command, one
# action-required issue, a non-zero exit. No retry, no hard reset.
kr_converge_cmd() {
  local k="${EFF_KEYS:-${INPUT_KEYS:-both}}"
  printf 'gh workflow run %s -f mode=converge -f keys=%s -f confirm=CONVERGE-INNGEST-%s-%s -f quiet_window=true -f reason="converge after inngest-key-rotate run %s"' \
    "$KR_WORKFLOW_FILE" "$k" "$(printf '%s' "$k" | tr '[:lower:]' '[:upper:]')" "$(date -u +%F)" "${GITHUB_RUN_ID:-unknown}"
}

kr_stop_sentence() { # <what happened, fixed words>
  printf 'STOP: do not retry and do not dispatch another rotate (a second rotate is a new rotation). %s The recovery is the converge mode; it needs the owner'"'"'s own per-command go naming this exact command (no agent runs it; the confirm date must be the UTC date of that dispatch): %s' \
    "$1" "$(kr_converge_cmd)"
}

kr_file_issue() { # <token> <sentence>
  local repo="${GITHUB_REPOSITORY:-}" title body n
  if [[ -z "${GH_TOKEN:-}" || -z "$repo" ]]; then printf '::warning::inngest-key-rotate: no GH_TOKEN or repository; the action-required issue was not filed.\n' >&2; return 0; fi
  title="inngest-key-rotate ${1} (run ${GITHUB_RUN_ID:-unknown})"
  n="$(gh issue list --repo "$repo" --label action-required --state open --limit 100 --json title 2>/dev/null | jq -r --arg t "$title" '[.[] | select(.title == $t)] | length')" || n=0
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  [[ "$n" == 0 ]] || return 0
  body="${GITHUB_SERVER_URL:-https://github.com}/${repo}/actions/runs/${GITHUB_RUN_ID:-0}"$'\n\n'"verdict=${1}"$'\n\n'"${2}"$'\n'
  printf '%s' "$body" > "$KR_TMP/issue.md"
  gh issue create --repo "$repo" --title "$title" --label action-required --body-file "$KR_TMP/issue.md" >/dev/null 2>&1 \
    || printf '::warning::inngest-key-rotate: could not file the action-required issue (the red run is the only record).\n' >&2
  return 0
}

# kr_post_write_failure <token> <detail> <what-happened>: the single exit path of a failure after a write was attempted.
kr_post_write_failure() {
  local s
  kr_refuse "$1" "$2"
  s="$(kr_stop_sentence "$3")"
  s="$(printf '%s' "$s" | KR_SCRUB_CAP=700 kr_scrub)"
  printf '::error::inngest-key-rotate %s\n' "$s" >&2
  kr_summary "STOP SENTENCE: ${s}"
  kr_file_issue "$1" "$s"
  return 1
}

# kr_inflight_check: refuse while a related workflow is running. Re-run as the first step of every write job (the groups do
# not serialize web-platform-release against this route).
kr_inflight_check() {
  local wf st n
  for wf in "${KR_INFLIGHT_WORKFLOWS[@]}"; do
    for st in in_progress queued waiting; do
      n="$(gh run list --repo "${GITHUB_REPOSITORY:-}" --workflow "$wf" --status "$st" --limit 50 --json databaseId 2>/dev/null \
        | jq --argjson me "${GITHUB_RUN_ID:-0}" '[.[] | select(.databaseId != $me)] | length')" || n=unreadable
      if [[ ! "$n" =~ ^[0-9]+$ ]]; then KR_CHECK_TOKEN=run_list_unreadable; KR_CHECK_DETAIL="cannot list ${wf} runs"; return 1; fi
      if [[ "$n" != 0 ]]; then KR_CHECK_TOKEN=run_in_flight; KR_CHECK_DETAIL="${wf} has ${n} ${st} run(s)"; return 1; fi
    done
  done
}

kr_require_no_inflight() { # the write jobs' first step
  if ! kr_inflight_check; then kr_refuse "$KR_CHECK_TOKEN" "$KR_CHECK_DETAIL; nothing was written"; return 1; fi
}

# ---------------------------------------------------------------------------------------------------------------------------
# GUARD
kr_chk_attempt() { [[ "${GITHUB_RUN_ATTEMPT:-}" == 1 ]] && return 0; KR_CHECK_TOKEN=rerun_refused; KR_CHECK_DETAIL="a re-run reuses the inputs and would bypass the owner's go; only plan may be re-run"; return 1; }
kr_chk_confirm() {
  local want
  want="$(printf '%s' "${INPUT_MODE:-}" | tr '[:lower:]' '[:upper:]')-INNGEST-$(printf '%s' "${INPUT_KEYS:-}" | tr '[:lower:]' '[:upper:]')-$(date -u +%F)"
  [[ "${INPUT_CONFIRM:-}" == "$want" ]] && return 0
  KR_CHECK_TOKEN=confirm_mismatch; KR_CHECK_DETAIL="confirm must be exactly <MODE>-INNGEST-<KEYS>-<UTC date of this run> (a typo-guard, not the authorization)"; return 1
}
kr_chk_quiet() { [[ "${INPUT_QUIET_WINDOW:-}" == true ]] && return 0; KR_CHECK_TOKEN=quiet_window_missing; KR_CHECK_DETAIL="quiet_window must attest no claude cron, approved Concierge action, pending payment_failed or Art. 15 response is in flight"; return 1; }
kr_chk_creds() {
  [[ -n "${DOPPLER_TOKEN:-}" && -n "${GH_TOKEN:-}" && -n "${BETTERSTACK_QUERY_HOST:-}" && -n "${BETTERSTACK_QUERY_USERNAME:-}" && -n "${BETTERSTACK_QUERY_PASSWORD:-}" ]] && return 0
  KR_CHECK_TOKEN=credential_absent; KR_CHECK_DETAIL="DOPPLER_TOKEN, GH_TOKEN or a BETTERSTACK_QUERY_* credential is not set"; return 1
}
# The link flag: soleur/prd_terraform INNGEST_LINK_TLS (the source key the Tier-B flag job writes; TF_VAR_inngest_link_tls).
# Distinct tokens for unreadable, absent, pending:<epoch>, and anything else; only the value 1 passes.
kr_chk_link() {
  local names v
  names="$(doppler secrets --only-names -p soleur -c prd_terraform 2>/dev/null)" || names=""
  if [[ -z "$names" ]]; then KR_CHECK_TOKEN=link_flag_unreadable; KR_CHECK_DETAIL="cannot list soleur/prd_terraform"; return 1; fi
  if ! grep -Eq '(^|[^A-Za-z0-9_])INNGEST_LINK_TLS([^A-Za-z0-9_]|$)' <<<"$names"; then
    KR_CHECK_TOKEN=link_flag_unset; KR_CHECK_DETAIL="the link flag is absent (the link is plaintext http:8288; rotating would send the new key across it)"; return 1
  fi
  v="$(doppler secrets get INNGEST_LINK_TLS --plain -p soleur -c prd_terraform 2>/dev/null)" || v="__unreadable__"
  case "$v" in
    1) return 0 ;;
    __unreadable__) KR_CHECK_TOKEN=link_flag_unreadable; KR_CHECK_DETAIL="cannot read the link flag"; return 1 ;;
    pending:*) KR_CHECK_TOKEN=link_flag_pending; KR_CHECK_DETAIL="the link flag is a pending lease, not 1"; return 1 ;;
    *) KR_CHECK_TOKEN=link_flag_invalid; KR_CHECK_DETAIL="the link flag is neither 1 nor a pending lease"; return 1 ;;
  esac
}
kr_chk_soak() {
  local r
  r="$(gh issue view "$KR_SOAK_ISSUE" --repo "${GITHUB_REPOSITORY:-}" --json state,stateReason 2>/dev/null | jq -r '"\(.state) \(.stateReason)"')" || r=""
  [[ -n "$r" ]] || { KR_CHECK_TOKEN=soak_unreadable; KR_CHECK_DETAIL="cannot read tracker #${KR_SOAK_ISSUE}"; return 1; }
  [[ "$r" == "CLOSED COMPLETED" ]] && return 0
  KR_CHECK_TOKEN=soak_open; KR_CHECK_DETAIL="tracker #${KR_SOAK_ISSUE} (the 48 h TLS soak) is not closed as completed"; return 1
}
kr_chk_server() {
  kr_load_ro_token || { KR_CHECK_TOKEN=credential_absent; KR_CHECK_DETAIL="HCLOUD_TOKEN_READONLY could not be read"; return 1; }
  kr_resolve_server
}

# kr_chk_serving: the pre-reboot host read. SERVING=yes AND the newest tls-health row (last 30 min) carries listener=1.
# Sets KR_BOOT_PRE. A failed read is host_state_unreadable (no verdict about the host), a read host that is not serving is
# host_not_serving_pre.
kr_chk_serving() {
  local newest ep boot lis now
  now="$(kr_now)"
  kr_read_host 90m
  case "$KR_HS_RC" in
    0) ;;
    4) KR_CHECK_TOKEN=host_not_serving_pre; KR_CHECK_DETAIL="no dedicated-host probe row in 90 minutes (silence is not health)"; return 1 ;;
    *) KR_CHECK_TOKEN=host_state_unreadable; KR_CHECK_DETAIL="the host-state read exited ${KR_HS_RC} (no verdict about the host)"; return 1 ;;
  esac
  if [[ "$KR_HS_SERVING" != yes ]]; then KR_CHECK_TOKEN=host_not_serving_pre; KR_CHECK_DETAIL="the newest probe row reads NOT SERVING"; return 1; fi
  kr_tls_rows "$(kr_iso $((now - 1800)))" || { KR_CHECK_TOKEN=host_state_unreadable; KR_CHECK_DETAIL="the tls-health read failed (class $(kr_bs_classify))"; return 1; }
  newest="$(tail -n 1 "$KR_TMP/tls.tsv")"
  IFS=$'\t' read -r ep boot lis _ <<<"$newest"
  if [[ -z "$ep" || "$lis" != 1 ]]; then KR_CHECK_TOKEN=host_not_serving_pre; KR_CHECK_DETAIL="no tls-health row with listener=1 in the last 30 minutes"; return 1; fi
  KR_BOOT_PRE="${boot:-${KR_HS_BOOT:--}}"
  [[ "$KR_BOOT_PRE" =~ ^[0-9a-f]{8}$ ]] || KR_BOOT_PRE="-"
}

# kr_chk_converge_source: derive keys and rotated_at from the newest non-plan run of this workflow whose apply1 job SUCCEEDED
# (a guard-refused run has no apply1 job and never qualifies). Owner-supplied keys/rotated_at must agree.
kr_chk_converge_source() {
  local list id mode keys jv done_at found="" tries=0 given
  list="$(gh run list --repo "${GITHUB_REPOSITORY:-}" --workflow "$KR_WORKFLOW_FILE" --limit 200 --json databaseId,displayTitle,event 2>/dev/null)" \
    || { KR_CHECK_TOKEN=run_list_unreadable; KR_CHECK_DETAIL="cannot list ${KR_WORKFLOW_FILE} runs"; return 1; }
  while read -r id mode keys; do
    [[ -n "$id" ]] || continue
    tries=$((tries + 1)); [[ "$tries" -le 15 ]] || break
    jv="$(gh run view "$id" --repo "${GITHUB_REPOSITORY:-}" --json jobs 2>/dev/null)" \
      || { KR_CHECK_TOKEN=run_list_unreadable; KR_CHECK_DETAIL="cannot read run ${id}"; return 1; }
    done_at="$(jq -r '[.jobs[]? | select(.name == "apply1" and .conclusion == "success")] | .[0].completedAt // empty' <<<"$jv" 2>/dev/null)" || done_at=""
    if [[ -n "$done_at" ]]; then found="$id"; KR_DERIVED_KEYS="$keys"; KR_ROTATED_AT="$(kr_epoch "$done_at")"; break; fi
  done < <(jq -r --argjson me "${GITHUB_RUN_ID:-0}" '.[] | select(.event == "workflow_dispatch" and .databaseId != $me)
      | select(.displayTitle | test("^inngest-key-rotate (rotate|converge) (signing|event|both)$"))
      | "\(.databaseId) \(.displayTitle)"' <<<"$list" | awk '{print $1, $3, $4}')
  if [[ -z "$found" || ! "$KR_ROTATED_AT" =~ ^[0-9]+$ || "$KR_ROTATED_AT" == 0 ]]; then
    KR_CHECK_TOKEN=converge_source_missing; KR_CHECK_DETAIL="no earlier non-plan run reached a successful apply1 (a guard-refused run does not qualify)"; return 1
  fi
  if [[ "$KR_DERIVED_KEYS" != "${INPUT_KEYS:-}" ]]; then KR_CHECK_TOKEN=converge_mismatch; KR_CHECK_DETAIL="the keys input disagrees with the run being converged"; return 1; fi
  given="${INPUT_ROTATED_AT:-}"
  if [[ -n "$given" ]]; then
    local ge; ge="$(kr_epoch "$given")"
    if [[ ! "$given" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || (( ge < KR_ROTATED_AT - 600 || ge > KR_ROTATED_AT + 600 )); then
      KR_CHECK_TOKEN=converge_mismatch; KR_CHECK_DETAIL="rotated_at disagrees with the run being converged"; return 1
    fi
  fi
}

# kr_chk_converge_host: decide whether this converge issues the (at most one) reboot POST. No POST when the newest boot began
# after rotated_at (every tls-health row of the newest boot_id since rotated_at-10min is later than rotated_at) or when a
# Hetzner reboot action is running or finished after rotated_at. Sets KR_REBOOT_POST and KR_BOOT_PRE.
kr_chk_converge_host() {
  local f="$KR_TMP/actions.json" code newest ep boot lis first running after
  code="$(kr_hz GET "/v1/servers/${KR_SERVER_ID}/actions?sort=id:desc&per_page=25" "$f")"
  if [[ "$code" != 200 ]]; then KR_CHECK_TOKEN=hetzner_unreadable; KR_CHECK_DETAIL="the server action list answered HTTP ${code}"; return 1; fi
  running="$(jq -r '[.actions[]? | select((.command | tostring | test("reboot")) and .status == "running")] | length' "$f" 2>/dev/null)" || running=x
  after="$(jq -r --arg t "$(kr_iso "$KR_ROTATED_AT")" '[.actions[]? | select((.command | tostring | test("reboot")) and .status == "success" and (.finished // "") > $t)] | length' "$f" 2>/dev/null)" || after=x
  if [[ ! "$running" =~ ^[0-9]+$ || ! "$after" =~ ^[0-9]+$ ]]; then KR_CHECK_TOKEN=hetzner_unreadable; KR_CHECK_DETAIL="the server action list did not parse"; return 1; fi
  kr_tls_rows "$(kr_iso $((KR_ROTATED_AT - 600)))" || { KR_CHECK_TOKEN=host_state_unreadable; KR_CHECK_DETAIL="the tls-health read failed (class $(kr_bs_classify))"; return 1; }
  newest="$(tail -n 1 "$KR_TMP/tls.tsv")"
  IFS=$'\t' read -r ep boot lis _ <<<"$newest"
  KR_BOOT_PRE="-"; [[ "$boot" =~ ^[0-9a-f]{8}$ ]] && KR_BOOT_PRE="$boot"
  first=0
  [[ "$KR_BOOT_PRE" != - ]] && first="$(awk -F'\t' -v b="$KR_BOOT_PRE" '$2 == b { print $1; exit }' "$KR_TMP/tls.tsv")"
  KR_REBOOT_POST=true
  if [[ "$running" != 0 || "$after" != 0 ]]; then KR_REBOOT_POST=false
  elif [[ "$first" =~ ^[0-9]+$ && "$first" -gt "$KR_ROTATED_AT" ]]; then KR_REBOOT_POST=false; fi
  # A boot that began after rotated_at needs no boot_id comparison; the verification keys on rows after rotated_at instead.
  [[ "$KR_REBOOT_POST" == false ]] && KR_BOOT_PRE="-"
  return 0
}

kr_run_check() { # <boolean-name> <function>: plan reports and never refuses; rotate/converge refuse on the first failure
  local name="$1" fn="$2"
  KR_CHECK_TOKEN=internal_error; KR_CHECK_DETAIL=""
  KR_BOOL_ORDER+=("$name")
  if "$fn"; then KR_BOOL[$name]=true; return 0; fi
  KR_BOOL[$name]=false
  [[ "$KR_GUARD_MODE" == plan ]] && return 0
  kr_refuse "$KR_CHECK_TOKEN" "${KR_CHECK_DETAIL}; nothing was written"
  return 1
}

kr_guard_report() {
  local n
  kr_summary "### inngest-key-rotate guard (${KR_GUARD_MODE} ${INPUT_KEYS})"
  kr_summary "reason: $(printf '%s' "${INPUT_REASON:-}" | kr_scrub)"
  kr_summary "| check | value |"
  kr_summary "|---|---|"
  for n in "${KR_BOOL_ORDER[@]}"; do
    kr_summary "| ${n} | ${KR_BOOL[$n]} |"
    printf 'inngest-key-rotate check %s=%s\n' "$n" "${KR_BOOL[$n]}" >&2
  done
}

kr_cmd_guard() {
  local mode="${INPUT_MODE:-}" keys="${INPUT_KEYS:-}"
  kr_out go false
  kr_valid_mode_keys "$mode" "$keys" || return 1
  if [[ -z "${INPUT_REASON//[[:space:]]/}" ]]; then kr_refuse inputs_invalid "reason is required"; return 1; fi
  KR_GUARD_MODE="$mode"
  kr_init || return 1
  kr_out mode "$mode"; kr_out keys "$keys"
  if [[ "$mode" != plan ]]; then
    kr_run_check run_attempt_is_1 kr_chk_attempt || return 1
    kr_run_check confirm_ok kr_chk_confirm || return 1
    kr_run_check quiet_window_attested kr_chk_quiet || return 1
  else
    kr_run_check run_attempt_is_1 kr_chk_attempt; kr_run_check confirm_ok kr_chk_confirm; kr_run_check quiet_window_attested kr_chk_quiet
  fi
  kr_run_check credentials_present kr_chk_creds || { kr_guard_report; return 1; }
  kr_run_check link_flag_is_1 kr_chk_link || { kr_guard_report; return 1; }
  kr_run_check soak_closed_completed kr_chk_soak || { kr_guard_report; return 1; }
  kr_run_check no_run_in_flight kr_chk_inflight_wrap || { kr_guard_report; return 1; }
  kr_run_check server_unique kr_chk_server || { kr_guard_report; return 1; }
  case "$mode" in
    rotate) kr_run_check host_serving_pre_reboot kr_chk_serving || { kr_guard_report; return 1; } ;;
    plan) kr_run_check host_serving_pre_reboot kr_chk_serving ;;
    converge)
      kr_run_check converge_source_found kr_chk_converge_source || { kr_guard_report; return 1; }
      kr_run_check converge_host_read kr_chk_converge_host || { kr_guard_report; return 1; } ;;
  esac
  kr_guard_report
  kr_out server_id "${KR_SERVER_ID:-}"
  kr_out boot_pre "$KR_BOOT_PRE"
  kr_out rotated_at "${KR_ROTATED_AT:-}"
  case "$mode" in
    plan) kr_out run_apply1 true; kr_out run_reboot false; kr_out run_apply2 false; kr_out run_redeploy false; kr_out reboot_post false ;;
    rotate) kr_out run_apply1 true; kr_out run_reboot true; kr_out run_apply2 true; kr_out run_redeploy true; kr_out reboot_post true ;;
    converge) kr_out run_apply1 false; kr_out run_reboot true; kr_out run_apply2 true; kr_out run_redeploy true; kr_out reboot_post "$KR_REBOOT_POST" ;;
  esac
  kr_out go true
  kr_ok guard_ok "mode=${mode} keys=${keys} (the guard wrote nothing)"
}
kr_chk_inflight_wrap() { kr_inflight_check; }

# ---------------------------------------------------------------------------------------------------------------------------
# APPLY 1 (phase 1) and PLAN
kr_cmd_apply1() {
  local mode="${EFF_MODE:-}" keys="${EFF_KEYS:-}" k rc klist
  local -A prior=()
  kr_valid_mode_keys "$mode" "$keys" || return 1
  [[ "$mode" == plan || "$mode" == rotate ]] || { kr_refuse internal_error "apply1 runs for plan and rotate only"; return 1; }
  kr_init || return 1
  klist="$(kr_keys_list "$keys")"
  [[ "$mode" == rotate ]] && { kr_require_no_inflight || return 1; }
  kr_tf_prepare || return 1
  if [[ "$mode" == rotate ]]; then
    for k in $klist; do
      prior[$k]="$(kr_hash host "$k")" || { kr_refuse copy_unreadable "cannot read the dedicated ${k} key copy (value-silent hash)"; return 1; }
    done
  fi
  kr_gate_plan A "$klist" a || return 1
  if [[ "$mode" == plan ]]; then
    kr_gate_plan B "$klist" b || return 1
    kr_summary "gate A addresses: $(kr_gate_rows A "$klist" | cut -d'|' -f3,5 | tr '\n' ' ')"
    kr_summary "gate B addresses: $(kr_gate_rows B "$klist" | cut -d'|' -f3,5 | tr '\n' ' ')"
    kr_ok plan_ok "gates A and B passed for keys=${keys}; nothing was applied"
    return 0
  fi
  rc=0
  KR_TF_T="$KR_TF_APPLY_S" kr_tf apply apply -no-color -input=false "$KR_TMP/tfplan-a" || rc=$?
  if [[ "$rc" != 0 ]]; then
    kr_post_write_failure apply_failed "the phase 1 apply exited ${rc}; the dedicated copy may be half-replaced; the app copy is untouched; its output stays on the runner" \
      "Phase 1 failed part-way."
    return 1
  fi
  for k in $klist; do
    local now_h
    now_h="$(kr_hash host "$k")" || { kr_post_write_failure copy_unreadable "cannot read the dedicated ${k} copy after the apply" "Phase 1 applied but could not be verified."; return 1; }
    if [[ "$now_h" == "${prior[$k]}" ]]; then
      kr_post_write_failure value_unchanged "the dedicated ${k} copy did not change (new_differs_from_prior=false)" "Phase 1 reported success but the dedicated ${k} key did not change."
      return 1
    fi
  done
  kr_ok apply1_ok "phase 1 applied for keys=${keys}; new_differs_from_prior=true; the app copy is untouched until the scheduler is verified SERVING"
}

# ---------------------------------------------------------------------------------------------------------------------------
# REBOOT (the POST) and VERIFY (the wait). Two steps so the write token reaches only the POST step.
kr_cmd_reboot() {
  local sid="${EFF_SERVER_ID:-}" aid st i t0 rc=0 f
  [[ "${EFF_MODE:-}" == rotate || "${EFF_MODE:-}" == converge ]] || { kr_refuse internal_error "reboot runs for rotate and converge only"; return 1; }
  if [[ "${EFF_REBOOT_POST:-}" != true ]]; then kr_log "inngest-key-rotate: no reboot POST this run (a reboot is running or finished after rotated_at, or the newest boot began after it)"; return 0; fi
  kr_init || return 1
  [[ "$sid" =~ ^[0-9]+$ ]] || { kr_refuse internal_error "no server id from the guard"; return 1; }
  [[ -n "${HCLOUD_TOKEN:-}" ]] || { kr_refuse credential_absent "HCLOUD_TOKEN is empty: the loader exported no Hetzner token"; return 1; }
  printf '::add-mask::%s\n' "$HCLOUD_TOKEN"
  KR_HZ_TOKEN="$HCLOUD_TOKEN"
  kr_require_no_inflight || return 1
  kr_resolve_server || { kr_refuse "$KR_CHECK_TOKEN" "$KR_CHECK_DETAIL; nothing was written"; return 1; }
  [[ "$KR_SERVER_ID" == "$sid" ]] || { kr_refuse host_not_unique "the server id changed since the guard; nothing was written"; return 1; }
  t0="$(kr_now)"
  kr_reboot_post "$sid" || rc=$?
  aid="$KR_ACTION_ID"
  if [[ "$rc" != 0 ]]; then
    [[ "$KR_VERDICT" == reboot_refused_second_post ]] && return 1
    kr_post_write_failure reboot_post_failed "${KR_CHECK_DETAIL:-the reboot POST failed}" "The reboot POST failed: the dedicated copy is new, the scheduler still runs the old keys, the app copy is old."
    return 1
  fi
  f="$KR_TMP/action.json"
  st=unknown
  for ((i = 0; i < KR_REBOOT_ACTION_S / 10; i++)); do
    if [[ "$(kr_hz GET "/v1/servers/${sid}/actions/${aid}" "$f")" == 200 ]]; then st="$(jq -r '.action.status // "unknown"' "$f" 2>/dev/null)" || st=unknown; fi
    [[ "$st" == success || "$st" == error ]] && break
    kr_sleep 10
  done
  if [[ "$st" != success ]]; then
    kr_post_write_failure reboot_action_failed "the Hetzner reboot action ended '$(printf '%s' "$st" | tr -cd '[:lower:]')' (success only means the request reached the guest)" \
      "The reboot action did not report success: the scheduler may still run the old keys."
    return 1
  fi
  kr_out post_epoch "$t0"
  kr_ok reboot_ok "the soft reboot request was accepted at $(kr_iso "$t0") (evidence of the restart is the next step, never this status)"
}

# kr_poll_host <required-after-epoch> <boot-pre>: one read. Sets KR_NEWBOOT (8 hex|""), KR_SERVE (yes|no|unknown),
# KR_LISTEN (1|0|""), KR_READ_FAULT (1 when a read produced no verdict). A boot counts as NEW only when a row at or after
# <required-after-epoch> carries a boot_id different from <boot-pre> ("-" = unknown: the epoch bound alone decides).
kr_poll_host() {
  local after="$1" pre="$2" ep boot lis
  KR_NEWBOOT=""; KR_SERVE=unknown; KR_LISTEN=""; KR_READ_FAULT=0
  kr_read_host 30m
  case "$KR_HS_RC" in 0|4) ;; *) KR_READ_FAULT=1 ;; esac
  if kr_tls_rows "$(kr_iso $((after - 60)))"; then
    while IFS=$'\t' read -r ep boot lis _; do
      [[ "$ep" =~ ^[0-9]+$ && "$ep" -ge "$after" && "$boot" =~ ^[0-9a-f]{8}$ ]] || continue
      [[ "$pre" == - || "$boot" != "$pre" ]] || continue
      KR_NEWBOOT="$boot"
    done < "$KR_TMP/tls.tsv"
    if [[ -n "$KR_NEWBOOT" ]]; then
      KR_LISTEN=0
      while IFS=$'\t' read -r ep boot lis _; do
        [[ "$ep" =~ ^[0-9]+$ && "$ep" -ge "$after" && "$boot" == "$KR_NEWBOOT" && "$lis" == 1 ]] && KR_LISTEN=1
      done < "$KR_TMP/tls.tsv"
    fi
  else
    KR_READ_FAULT=1
  fi
  if [[ "$KR_HS_RC" == 0 && -n "$KR_HS_BOOT" && ( "$pre" == - || "$KR_HS_BOOT" != "$pre" ) && "$KR_HS_OBS" -ge "$after" ]]; then
    [[ -z "$KR_NEWBOOT" ]] && KR_NEWBOOT="$KR_HS_BOOT"
    [[ "$KR_HS_BOOT" == "$KR_NEWBOOT" ]] && KR_SERVE="${KR_HS_SERVING:-unknown}"
  fi
  return 0
}

# kr_cmd_verify: the evidence. Pass = a boot_id different from the pre-reboot capture (or, with no POST this run, rows later than
# rotated_at), the host-state script's SERVING=yes (it includes registry_fns) and a tls-health row with that boot_id and listener=1.
# No new boot_id within KR_BOOT_WAIT_S of the POST is host_silent; not serving by KR_VERIFY_S is host_not_serving; a read that
# never produced a verdict is host_read_failed (never a claim about the host).
kr_cmd_verify() {
  local pre="${EFF_BOOT_PRE:--}" after t_post boot_deadline verify_deadline now fault_seen=0
  [[ "${EFF_MODE:-}" == rotate || "${EFF_MODE:-}" == converge ]] || { kr_refuse internal_error "verify runs for rotate and converge only"; return 1; }
  kr_init || return 1
  [[ -n "${BETTERSTACK_QUERY_HOST:-}" && -n "${BETTERSTACK_QUERY_USERNAME:-}" && -n "${BETTERSTACK_QUERY_PASSWORD:-}" ]] \
    || { kr_refuse credential_absent "a BETTERSTACK_QUERY_* credential is not set"; return 1; }
  [[ "$pre" =~ ^([0-9a-f]{8}|-)$ ]] || pre="-"
  if [[ "${EFF_POST_EPOCH:-}" =~ ^[0-9]+$ ]]; then
    t_post="$EFF_POST_EPOCH"; after="$t_post"
    # A POST was made: with no boot_id to compare against, rows inside the graceful stop (TimeoutStopSec=180) are still the old boot.
    [[ "$pre" == - ]] && after=$((t_post + 180))
  elif [[ "${EFF_ROTATED_AT:-}" =~ ^[0-9]+$ ]]; then
    t_post="$(kr_now)"; after="$EFF_ROTATED_AT"
  else
    kr_refuse internal_error "neither a POST time nor rotated_at was supplied"; return 1
  fi
  boot_deadline=$((t_post + KR_BOOT_WAIT_S)); verify_deadline=$((t_post + KR_VERIFY_S))
  while :; do
    kr_poll_host "$after" "$pre"
    [[ "$KR_READ_FAULT" == 1 ]] && fault_seen=1
    if [[ -n "$KR_NEWBOOT" && "$KR_SERVE" == yes && "$KR_LISTEN" == 1 ]]; then
      kr_summary "- new_boot_id_seen=true serving=true tls_listener=1"
      kr_ok reboot_ok "new boot_id seen, SERVING=yes, tls-health listener=1 (booleans only; host text stays on the runner)"
      return 0
    fi
    now="$(kr_now)"
    if [[ -z "$KR_NEWBOOT" && "$now" -ge "$boot_deadline" ]]; then
      if [[ "$fault_seen" == 1 && "$KR_HS_RC" != 4 ]]; then
        kr_post_write_failure host_read_failed "no verdict: the Better Stack read failed (class $(kr_bs_classify)); this says nothing about the host" "The host could not be read after the reboot."
      else
        kr_post_write_failure host_silent "no probe or tls-health row with a new boot_id within $((KR_BOOT_WAIT_S / 60)) minutes of the reboot request" \
          "The host did not come back with a new boot_id; the sole scheduler may be down (crons and reminders stop). Web is NOT redeployed and keeps the old app key. No hard reset is issued by this route; recover per the runbook stage table."
      fi
      return 1
    fi
    if [[ "$now" -ge "$verify_deadline" ]]; then
      if [[ "$fault_seen" == 1 && "$KR_SERVE" == unknown ]]; then
        kr_post_write_failure host_read_failed "no verdict: the host-state read did not produce SERVING within the window (class $(kr_bs_classify))" "The host state could not be read."
      else
        kr_post_write_failure host_not_serving "a new boot_id was seen but SERVING=${KR_SERVE} and listener=${KR_LISTEN:-?} at the end of the $((KR_VERIFY_S / 60)) minute window" \
          "The host rebooted but is not serving: the sole scheduler is down (crons and reminders stop). Web is NOT redeployed and keeps the old app key. No hard reset is issued by this route; recover per the runbook stage table."
      fi
      return 1
    fi
    kr_sleep "$KR_POLL_S"
  done
}

# ---------------------------------------------------------------------------------------------------------------------------
# APPLY 2 (phase 2)
kr_cmd_apply2() {
  local mode="${EFF_MODE:-}" keys="${EFF_KEYS:-}" k rc klist bkeys=""
  kr_valid_mode_keys "$mode" "$keys" || return 1
  [[ "$mode" == rotate || "$mode" == converge ]] || { kr_refuse internal_error "apply2 runs for rotate and converge only"; return 1; }
  kr_init || return 1
  klist="$(kr_keys_list "$keys")"
  kr_require_no_inflight || return 1
  for k in $klist; do
    rc=0; kr_copies_equal "$k" || rc=$?
    case "$rc" in
      2) kr_refuse copy_unreadable "cannot compare the ${k} copies (value-silent hash)"; return 1 ;;
      1) bkeys="${bkeys:+$bkeys }$k" ;;
      0)
        # rotate: phase 1 just made the copies differ, so equal here means phase 1 did not land. converge: equal means done.
        if [[ "$mode" == rotate ]]; then kr_refuse value_unchanged "the ${k} copies are already equal before phase 2 (phase 1 did not change the dedicated copy); nothing was written"; return 1; fi ;;
    esac
  done
  if [[ -z "$bkeys" ]]; then kr_ok apply2_skipped "copies_equal=true for keys=${keys}; nothing to apply"; return 0; fi
  kr_tf_prepare || return 1
  kr_gate_plan B "$bkeys" b || return 1
  rc=0
  KR_TF_T="$KR_TF_APPLY_S" kr_tf apply apply -no-color -input=false "$KR_TMP/tfplan-b" || rc=$?
  if [[ "$rc" != 0 ]]; then
    kr_post_write_failure apply_failed "the phase 2 apply exited ${rc}; the copies differ; its output stays on the runner" \
      "Phase 2 failed: the dedicated copy is new and verified, the app copy may be old or missing."
    return 1
  fi
  for k in $klist; do
    rc=0; kr_copies_equal "$k" || rc=$?
    if [[ "$rc" != 0 ]]; then
      kr_post_write_failure copies_differ "copies_equal=false for ${k} after phase 2 (compare rc ${rc})" "Phase 2 applied but the two copies are not equal."
      return 1
    fi
  done
  kr_ok apply2_ok "phase 2 applied for keys=${keys}; copies_equal=true (both copies hold the same value; nothing printed)"
}

# ---------------------------------------------------------------------------------------------------------------------------
# REDEPLOY
kr_cmd_redeploy() {
  local mode="${EFF_MODE:-}" keys="${EFF_KEYS:-}" done_at ts
  kr_valid_mode_keys "$mode" "$keys" || return 1
  [[ "$mode" == rotate || "$mode" == converge ]] || { kr_refuse internal_error "redeploy runs for rotate and converge only"; return 1; }
  kr_init || return 1
  kr_require_no_inflight || return 1
  [[ "${WEB_HOST_PRIVATE_IPS:-}" =~ ^[0-9.]+(,[0-9.]+)*$ ]] \
    || { kr_refuse internal_error "WEB_HOST_PRIVATE_IPS is unset or malformed; a single-host redeploy would leave the fleet mixed. Nothing was dispatched."; return 1; }
  if ! WEB_HOST_PRIVATE_IPS="$WEB_HOST_PRIVATE_IPS" REDEPLOY_TIMEOUT_S="$KR_REDEPLOY_S" bash "$KR_TRACK"; then
    kr_post_write_failure redeploy_failed "the fleet redeploy (track.sh) did not confirm a clean swap on every host; its verdict is in the output above" \
      "The redeploy did not confirm: the old containers keep the old key; the scheduler and Doppler have the new one."
    return 1
  fi
  done_at="$(kr_now)"; ts="$(kr_iso "$done_at")"
  kr_ok "${mode}_ok" "keys=${keys}; the fleet redeploy was confirmed by track.sh (web-1 swapped, web-2 accepted the trigger)"
  kr_evidence "$mode" "$keys" "$ts"
}

# kr_evidence: the value-free record and the ready-to-paste S5-A5-DONE line. PRINTED ONLY: nothing here posts it (the
# follow-through probe reads the owner's own comments; an agent-posted line does not satisfy the owner record).
kr_evidence() {
  local mode="$1" keys="$2" ts="$3" url rot="n/a"
  [[ "${EFF_ROTATED_AT:-}" =~ ^[0-9]+$ ]] && rot="$(kr_iso "$EFF_ROTATED_AT")"
  url="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-0}"
  {
    printf '### Evidence (value-free; paste on #10136 with the line below if you accept it)\n\n'
    printf '```\nmode=%s keys=%s\nredeploy_confirmed_at=%s\nrun=%s\nrotated_at=%s\nbooleans: copies_equal=true new_boot_id_seen=true serving=true tls_listener=1 link_flag_is_1=true redeploy_ok=true\n```\n' \
      "$mode" "$keys" "$ts" "$url" "$rot"
  } | while IFS= read -r l; do kr_summary "$l"; printf '%s\n' "$l" >&2; done
  if [[ "$keys" == signing || "$keys" == both ]]; then
    printf 'S5-A5-DONE: %s\n' "$ts"
    kr_summary "S5-A5-DONE: ${ts}"
    kr_log "inngest-key-rotate: the line above is printed only; the owner posts it on #10136. Nothing in this workflow posts it."
  else
    kr_log "inngest-key-rotate: keys=event rotated the event key only; A5 is the signing-key rotation, so no S5-A5-DONE line is printed."
  fi
}

main() {
  case "${1:-}" in
    --print-contract) kr_print_contract ;;
    guard) kr_cmd_guard ;;
    apply1) kr_cmd_apply1 ;;
    reboot) kr_cmd_reboot ;;
    verify) kr_cmd_verify ;;
    apply2) kr_cmd_apply2 ;;
    redeploy) kr_cmd_redeploy ;;
    *) printf 'usage: %s --print-contract|guard|apply1|reboot|verify|apply2|redeploy\n' "${0##*/}" >&2; return 64 ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; exit $?; fi
