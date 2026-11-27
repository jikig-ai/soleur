#!/usr/bin/env bash
# cf-account-migration-complete.sh — the migration-in-progress predicate (#12931, plan Guard 3,
# CTO ruling L79). Answers one question about the web-platform Terraform state: has the
# Cloudflare account migration finished, so a routine plan may run again?
#
# Usage:
#   cf-account-migration-complete.sh [--mode full|web2-replace] <state.json>
#       Evaluate a LOCAL raw tfstate file (the S3 object, not `terraform show -json`).
#   cf-account-migration-complete.sh --from-r2
#       The CI wrapper, run as the LAST step of .github/actions/infra-credentials/action.yml.
#       Decides scope, resolves read credentials, copies the state object, then evaluates it.
#       Reads only env: CFAM_WORKFLOW_REF, CFAM_JOB, CFAM_EVENT_NAME, CFAM_WEB_HOST_KEY,
#       CFAM_DOPPLER_TOKEN_LEGACY, TF_STATE_AWS_ACCESS_KEY_ID, TF_STATE_AWS_SECRET_ACCESS_KEY,
#       RUNNER_TEMP. There is no skip knob, by design.
#
# Exit codes: 0 complete (or out of scope), 1 incomplete, 2 unreadable / usage error.
#
# COMPLETE (mode full) means ALL of:
#   - the state carries at least one managed cloudflare_* resource;
#   - every managed cloudflare_* instance outside cloudflare_r2_* carries the NEW zone id and the NEW
#     account id, or none (null / absent / ""). An allowlist, not an old-id denylist: an instance on
#     the OLD ids reads "old-id", one on any third id "unknown-id" (R2 stays on the legacy account,
#     ADR-329);
#   - cloudflare_zero_trust_tunnel_cloudflared.web is in state and every instance carries the NEW
#     account id;
#   - every address of every phase in tests/scripts/lib/cf-account-migrate-gate.sh is in state.
#     That file is the ONE list (cf_account_migrate_phases / cf_account_migrate_phase_spec); this
#     script sources it and never re-types an address;
#   - every instance of every import-class cloudflare_record of those phases holds a non-empty
#     string `content` ("unnormalized <addr>" otherwise): a stopped apply leaves the imports it did
#     not reach in state with null content, so being in state does not prove normalization (Q6).
# Mode web2-replace needs only the tunnel condition: it is the one exception, for
# `web_host_replace` of web-2 once the tunnel phase has landed (plan Phase 1 item 11).
#
# In PR1 the tunnel phase does not exist yet, so this predicate stays "in progress" until PR2 and
# every gated plan fails closed in between. That is intended (CTO L58).
#
# Prints the verdict and addresses only, never an attribute value or any state content.
set -uo pipefail
case "$-" in
  *x*) printf '[FATAL] refusing to run under xtrace: this script handles a live credential and -x would print it (see #7797)\n' >&2; exit 78 ;;
esac

CFAM_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CFAM_GATE_LIB="${CFAM_SELF_DIR}/../../../../tests/scripts/lib/cf-account-migrate-gate.sh"
readonly CFAM_RUNBOOK="knowledge-base/engineering/operations/runbooks/cloudflare-account-migration.md"
readonly CFAM_TUNNEL_ADDR="cloudflare_zero_trust_tunnel_cloudflared.web"
# The state object, in the gate library's bucket (CFAM_OLD_*, CFAM_STATE_BUCKET and the R2 call
# cfam_r2_aws are the library's: one copy, shared with the migrate job and the state forget).
readonly CFAM_STATE_KEY="web-platform/terraform.tfstate"
readonly P="cf-account-migration-complete"

# SCOPE (CTO D1, 2026-11-19): deny by default. EVERY workflow that calls the infra-credentials
# loader is gated unless it is named below. A new workflow, or a renamed one, is therefore gated
# until a reviewed diff names it here. The exempt names are the plan-only / migrator workflows and
# the loader callers that never plan or apply apps/web-platform/infra (other roots, or no
# Terraform at all). tests/scripts/test-cf-account-migration-scope.sh checks each name is a real
# loader caller and that no exempt workflow outside the plan-only pair (or a repo script it runs
# with `bash <path>`, one level, plus what that script sources) pairs a terraform invocation with
# the bare root path. It does not see Terraform reached any other way. The cf-account-migrate
# job reads this same list for its in-flight check (no second copy).
readonly CFAM_EXEMPT_WORKFLOWS=(
  cf-account-migrate.yml scheduled-terraform-drift.yml
  apply-github-infra.yml apply-sentry-infra.yml apply-git-data-root-key.yml git-data-rung2-rehearsal.yml
  inngest-provision-rehearsal.yml mint-origin-ca-cert.yml cutover-inngest.yml git-data-cutover.yml
  web-host-escrow-diagnose.yml
)
# The plan-only / migrator subset: they plan (and the migrator applies) the root by design.
readonly CFAM_PLAN_ONLY_WORKFLOWS=(cf-account-migrate.yml scheduled-terraform-drift.yml)
# Jobs of apply-web-platform-infra.yml that call the credential loader but run no Terraform.
readonly CFAM_EXEMPT_JOBS=(entrypoint_audit registry_pull_path_gate registry_store_restore)

_cfam_unreadable() { # <reason> <message>
  printf '%s verdict=cf-account-migration-state-unreadable reason=%s\n' "$P" "$1"
  printf '::error title=cf-account-migration::verdict=cf-account-migration-state-unreadable reason=%s — %s. Failing closed: an unreadable state is never "complete". See %s.\n' "$1" "$2" "$CFAM_RUNBOOK"
  _cfam_summary "verdict=cf-account-migration-state-unreadable reason=$1"
  return 2
}

_cfam_summary() {
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    printf -- '- %s: %s\n' "$P" "$1" >> "$GITHUB_STEP_SUMMARY" 2>/dev/null || true
  fi
}

# _cfam_load_gate — source the phase-gate library (the ONE address list, the NEW and OLD ids, the
# state bucket and the R2 call) unless it is loaded, then shape-check the four ids. Called once per
# run, before the state is read: cfam_main for a local file, cfam_from_r2 once the run is gated.
# 0 ok; 2 unusable (verdict printed).
_cfam_load_gate() {
  local v bad=""
  # shellcheck source=/dev/null
  { declare -F cf_account_migrate_phase_spec >/dev/null || source "$CFAM_GATE_LIB"; } || bad="unloadable"
  for v in CFAM_NEW_ZONE_ID CFAM_NEW_ACCOUNT_ID CFAM_OLD_ZONE_ID CFAM_OLD_ACCOUNT_ID; do
    [[ "${!v:-}" =~ ^[0-9a-f]{32}$ ]] || bad+=" $v"
  done
  [[ -z "$bad" ]] || { _cfam_unreadable gate-library-unusable "the phase-gate library at $CFAM_GATE_LIB is unusable (${bad# })"; return 2; }
}

# cfam_required_addresses — JSON array, the union of every phase's allow-set, from the gate.
cfam_required_addresses() {
  local phase spec all="[]"
  while IFS= read -r phase; do
    [[ -n "$phase" ]] || continue
    spec="$(cf_account_migrate_phase_spec "$phase")" || return 1
    all="$(jq -c --argjson s "$spec" '. + ($s | keys_unsorted) | unique' <<<"$all")" || return 1
  done < <(cf_account_migrate_phases)
  printf '%s\n' "$all"
}

# cfam_required_records — JSON array, every import-class cloudflare_record of every phase. From the
# phase spec, not the imports file: the cleanup PR deletes that file.
cfam_required_records() {
  local phase spec all="[]"
  while IFS= read -r phase; do
    [[ -n "$phase" ]] || continue
    spec="$(cf_account_migrate_phase_spec "$phase")" || return 1
    all="$(jq -c --argjson s "$spec" '. + [$s | to_entries[]
      | select(.value == "import" and (.key | startswith("cloudflare_record."))) | .key] | unique' <<<"$all")" || return 1
  done < <(cf_account_migrate_phases)
  printf '%s\n' "$all"
}

# cfam_evaluate <mode> <state.json> — 0 complete, 1 incomplete, 2 unreadable. Needs the gate
# library loaded (_cfam_load_gate).
cfam_evaluate() {
  local mode="$1" state="$2" req n_req reasons recs="[]"
  case "$mode" in full|web2-replace) ;; *) echo "$P: unknown mode '$mode'" >&2; return 2 ;; esac

  [[ -f "$state" && -r "$state" ]] || { _cfam_unreadable state-file-unreadable "the state file is missing or unreadable"; return 2; }
  jq -e 'type == "object"' "$state" >/dev/null 2>&1 \
    || { _cfam_unreadable not-json "the state object is not a JSON object"; return 2; }
  jq -e '.version == 4' "$state" >/dev/null 2>&1 \
    || { _cfam_unreadable state-version "the state is not a version-4 tfstate"; return 2; }
  jq -e '.resources | type == "array"' "$state" >/dev/null 2>&1 \
    || { _cfam_unreadable no-resources-array "the state has no resources array"; return 2; }

  req="$(cfam_required_addresses)" || { _cfam_unreadable required-set-unavailable "the phase allow-set could not be read from $CFAM_GATE_LIB"; return 2; }
  n_req="$(jq -r 'length' <<<"$req" 2>/dev/null)" || n_req=""
  # Anti-vacuity: an empty required set would reduce "every migrated address is in state" to true.
  if [[ ! "$n_req" =~ ^[0-9]+$ ]] || (( n_req < 1 )); then
    _cfam_unreadable required-set-empty "the phase allow-set is empty"
    return 2
  fi
  # Full mode only: the web-2 replace lane needs the tunnel condition and nothing else.
  if [[ "$mode" == full ]]; then
    recs="$(cfam_required_records)" || { _cfam_unreadable required-set-unavailable "the import-record list could not be read from $CFAM_GATE_LIB"; return 2; }
    jq -e 'type == "array" and length > 0' <<<"$recs" >/dev/null 2>&1 \
      || { _cfam_unreadable required-set-empty "the import-record list is empty"; return 2; }
  fi

  # One jq pass. Each line is "<reason> <address>" (or a bare reason). A jq error is unreadable,
  # never an empty reason list (an empty list reads as complete).
  reasons="$(jq -r --arg oz "$CFAM_OLD_ZONE_ID" --arg oa "$CFAM_OLD_ACCOUNT_ID" \
      --arg na "$CFAM_NEW_ACCOUNT_ID" --arg nz "$CFAM_NEW_ZONE_ID" --arg tun "$CFAM_TUNNEL_ADDR" --arg mode "$mode" \
      --argjson req "$req" --argjson recs "$recs" '
    def raddr: (if (.module // "") != "" then .module + "." else "" end) + .type + "." + .name;
    def iaddr($a): $a + (if has("index_key") then "[" + (.index_key | tojson) + "]" else "" end);
    # Unbound = null, absent or "". Any other value must be the NEW id (allowlist).
    def bound($k): (.attributes[$k] // "") as $v | if $v == "" then null else $v end;
    [ .resources[] | select((.mode // "managed") == "managed") ] as $m
    | ($m | map(select(.type | startswith("cloudflare_")))) as $cf
    | ($m | map(select(raddr == $tun)) | map(.instances // []) | add // []) as $tunnel
    | (if ($tunnel | length) == 0 then ["tunnel-absent " + $tun]
       else [ $tunnel[] | select((.attributes | type) != "object" or .attributes.account_id != $na)
              | iaddr($tun) | "tunnel-not-on-new-account " + . ] end) as $tun_reasons
    | if $mode == "web2-replace" then $tun_reasons[]
      else
        ( (if ($cf | length) == 0 then ["no-cloudflare-resources"] else [] end)
        + [ $cf[] | select(.type | startswith("cloudflare_r2_") | not) | raddr as $a | (.instances // [])[]
            | select((.attributes | type) != "object") | "instance-without-attributes " + iaddr($a) ]
        + [ $cf[] | select(.type | startswith("cloudflare_r2_") | not) | raddr as $a | (.instances // [])[]
            | select((.attributes | type) == "object")
            | bound("zone_id") as $z | bound("account_id") as $ac
            | select(($z != null and $z != $nz) or ($ac != null and $ac != $na))
            | (if $z == $oz or $ac == $oa then "old-id " else "unknown-id " end) + iaddr($a) ]
        + $tun_reasons
        + ( [ $m[] | select((.instances // []) | length > 0) | raddr ] as $have
            | [ $req[] | select(. as $r | $have | index($r) | not) | "missing " + . ] )
        + [ $m[] | raddr as $a | select($recs | index($a)) | (.instances // [])[]
            | select((.attributes | type) == "object"
                     and ((.attributes.content | type) != "string" or .attributes.content == ""))
            | "unnormalized " + iaddr($a) ]
        )[]
      end' "$state")" || { _cfam_unreadable eval-error "the state could not be evaluated (jq error)"; return 2; }

  if [[ -n "$reasons" ]]; then
    while IFS= read -r line; do printf '%s %s\n' "$P" "$line"; done <<<"$reasons"
    local n; n="$(grep -c . <<<"$reasons")"
    printf '%s verdict=cf-account-migration-in-progress mode=%s reasons=%s required=%s\n' "$P" "$mode" "$n" "$n_req"
    printf '::error title=cf-account-migration::verdict=cf-account-migration-in-progress mode=%s reasons=%s — the Cloudflare account migration (#12931) is not complete, so this job refuses to plan. Finish the migration with cf-account-migrate.yml; see %s.\n' "$mode" "$n" "$CFAM_RUNBOOK"
    _cfam_summary "verdict=cf-account-migration-in-progress mode=$mode reasons=$n"
    return 1
  fi
  printf '%s verdict=cf-account-migration-complete mode=%s required=%s\n' "$P" "$mode" "$n_req"
  return 0
}

# cfam_scope — prints "exempt-workflow <wf>", "exempt-job <job>", "gated full" or
# "gated web2-replace". Pure: env in, decision out.
cfam_scope() {
  local ref="${CFAM_WORKFLOW_REF:-}" job="${CFAM_JOB:-}" ev="${CFAM_EVENT_NAME:-}" key="${CFAM_WEB_HOST_KEY:-}"
  local wf="" w j
  # owner/repo/.github/workflows/<file>@<ref>. Anything that does not parse is GATED (deny).
  if [[ "$ref" == *"/.github/workflows/"*"@"* ]]; then
    wf="${ref#*/.github/workflows/}"
    wf="${wf%%@*}"
  fi
  if [[ -z "$wf" || "$wf" == */* ]]; then
    printf 'gated full\n'
    return 0
  fi
  for w in "${CFAM_EXEMPT_WORKFLOWS[@]}"; do
    if [[ "$wf" == "$w" ]]; then printf 'exempt-workflow %s\n' "$wf"; return 0; fi
  done
  if [[ "$wf" == "apply-web-platform-infra.yml" ]]; then
    for j in "${CFAM_EXEMPT_JOBS[@]}"; do
      if [[ "$job" == "$j" ]]; then printf 'exempt-job %s\n' "$job"; return 0; fi
    done
    if [[ "$job" == "web_host_replace" && "$ev" == "workflow_dispatch" && "$key" == "web-2" ]]; then
      printf 'gated web2-replace\n'
      return 0
    fi
  fi
  printf 'gated full\n'
}

# cfam_resolve_creds — sets CFAM_KEY_ID / CFAM_KEY_SECRET / CFAM_CRED_SOURCE. 0 ok, 1 none.
# Tier B first (TF_STATE_AWS_*, exported by the loader's load step into $GITHUB_ENV, which THIS
# later step can see); else the read-only AWS_* pair from prd_terraform through the legacy token.
cfam_resolve_creds() {
  CFAM_KEY_ID="" CFAM_KEY_SECRET="" CFAM_CRED_SOURCE=""
  local tid="${TF_STATE_AWS_ACCESS_KEY_ID:-}" tsec="${TF_STATE_AWS_SECRET_ACCESS_KEY:-}"
  if [[ -n "$tid" && -n "$tsec" ]]; then
    CFAM_KEY_ID="$tid" CFAM_KEY_SECRET="$tsec" CFAM_CRED_SOURCE="tier_b"
    return 0
  fi
  if [[ -n "$tid" || -n "$tsec" ]]; then
    CFAM_CRED_SOURCE="tier_b_half_set"
    return 1
  fi
  local tok="${CFAM_DOPPLER_TOKEN_LEGACY:-}" id="" sec="" rc_id=0 rc_sec=0
  [[ -n "$tok" ]] || { CFAM_CRED_SOURCE="none"; return 1; }
  command -v doppler >/dev/null 2>&1 || { CFAM_CRED_SOURCE="doppler-missing"; return 1; }
  # Bounded: a stalled Doppler must fail this step with a named reason, not hold the job to its
  # timeout-minutes (a composite step cannot set its own).
  id="$(DOPPLER_TOKEN="$tok" timeout 30 doppler secrets get AWS_ACCESS_KEY_ID --plain -p soleur -c prd_terraform 2>/dev/null)" || { rc_id=$?; id=""; }
  sec="$(DOPPLER_TOKEN="$tok" timeout 30 doppler secrets get AWS_SECRET_ACCESS_KEY --plain -p soleur -c prd_terraform 2>/dev/null)" || { rc_sec=$?; sec=""; }
  if (( rc_id == 124 || rc_sec == 124 )); then CFAM_CRED_SOURCE="legacy_read_timeout"; return 1; fi
  if [[ -z "$id" || -z "$sec" ]]; then CFAM_CRED_SOURCE="legacy_read_failed"; return 1; fi
  # Doppler-fetched values are not auto-masked by Actions. Mask per line before any further use.
  local ln
  while IFS= read -r ln; do [[ -n "$ln" ]] && printf '::add-mask::%s\n' "$ln"; done <<<"$id"$'\n'"$sec"
  CFAM_KEY_ID="$id" CFAM_KEY_SECRET="$sec" CFAM_CRED_SOURCE="legacy"
  return 0
}

cfam_from_r2() {
  local decision kind mode
  decision="$(cfam_scope)"
  kind="${decision%% *}"
  mode="${decision#* }"
  case "$kind" in
    exempt-workflow|exempt-job)
      printf '%s scope=%s name=%s — out of scope, not evaluated\n' "$P" "$kind" "$mode"
      return 0 ;;
    gated) ;;
    *) _cfam_unreadable scope-undecidable "the scope decision returned nothing usable"; return 2 ;;
  esac
  printf '%s scope=gated mode=%s job=%s\n' "$P" "$mode" "${CFAM_JOB:-<unset>}"

  if ! cfam_resolve_creds; then
    _cfam_unreadable "no-credentials-${CFAM_CRED_SOURCE:-none}" "no read credential for the web-platform state object (Tier-B TF_STATE_AWS_* absent and the legacy prd_terraform read did not yield AWS_*)"
    return 2
  fi
  command -v aws >/dev/null 2>&1 || { _cfam_unreadable aws-cli-missing "the aws CLI is not on PATH"; return 2; }
  _cfam_load_gate || return 2

  umask 077
  local base="${RUNNER_TEMP:-${TMPDIR:-/tmp}}" work rc uri="s3://${CFAM_STATE_BUCKET}/${CFAM_STATE_KEY}"
  work="$(mktemp -d "${base%/}/cfam.XXXXXXXX")" || { _cfam_unreadable workdir "cannot create a private work dir"; return 2; }
  # shellcheck disable=SC2064 # expand $work now: the trap must remove THIS dir
  trap "rm -rf '$work'" EXIT
  rc=0
  # The gate library's R2 call (env prefix, 60 s bound, pinned endpoint). Credentials via the
  # command's environment only, never argv; aws stderr is dropped because it is never needed for
  # the verdict and must not become a place a key fragment can surface.
  AWS_ACCESS_KEY_ID="$CFAM_KEY_ID" AWS_SECRET_ACCESS_KEY="$CFAM_KEY_SECRET" AWS_SESSION_TOKEN="" \
    cfam_r2_aws s3 cp "$uri" "$work/state.json" --only-show-errors \
    >/dev/null 2>&1 || rc=$?
  CFAM_KEY_ID="" CFAM_KEY_SECRET=""
  if (( rc == 124 )); then
    _cfam_unreadable copy-timeout "copying ${uri} did not finish within 60 s (credentials=${CFAM_CRED_SOURCE})"
    return 2
  fi
  if (( rc != 0 )) || [[ ! -s "$work/state.json" ]]; then
    _cfam_unreadable copy-failed "copying ${uri} failed (rc=${rc}, credentials=${CFAM_CRED_SOURCE})"
    return 2
  fi
  cfam_evaluate "$mode" "$work/state.json"
}

cfam_main() {
  local mode="full"
  case "${1-}" in
    --from-r2)
      [[ $# -eq 1 ]] || { echo "usage: $0 --from-r2" >&2; return 2; }
      cfam_from_r2
      return $? ;;
    --mode)
      mode="${2-}"; shift 2 || { echo "usage: $0 [--mode full|web2-replace] <state.json>" >&2; return 2; } ;;
  esac
  if [[ $# -ne 1 ]]; then echo "usage: $0 [--mode full|web2-replace] <state.json>" >&2; return 2; fi
  _cfam_load_gate || return 2
  cfam_evaluate "$mode" "$1"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  cfam_main "$@"
  exit $?
fi
