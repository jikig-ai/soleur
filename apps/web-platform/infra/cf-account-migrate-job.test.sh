#!/usr/bin/env bash
# cf-account-migrate-job.test.sh — battery for scripts/cf-account-migrate-job.sh, the body of
# .github/workflows/cf-account-migrate.yml (#12931, CTO L24/L43/L79).
#
# HARNESS
# - terraform, doppler, gh, aws, curl and ssh-keygen are PATH stubs; every call is appended to one
#   calls.log, so call ORDER is observable. The REAL phase gate and the REAL state-forget script run.
# - The terraform stub keeps two state stores: "remote" (the case dir) and "local" (rehearsal.tfstate
#   in a cwd whose backend_override.tf declares backend "local"). Log lines carry the store label,
#   so a rehearsal that wrote the remote store is visible, not inferred.
# - Plans served by the stub are built from the gate's own phase spec and the committed imports
#   file, so a PASS fixture tracks the one list; the -target/-replace checks compare argv with the
#   gate functions' output.
# - Refusals are proven load-bearing with sed mutants of a PRISTINE COPY: each mutant must differ
#   (cmp), parse (bash -n), and turn a check that is GREEN on pristine RED for the named reason.
# - Fixtures are synthesized; the OLD ids are literals, checked against the gate library.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
SUT="$HERE/scripts/cf-account-migrate-job.sh"
MIGRATE="$HERE/scripts/cf-account-state-migrate.sh"
[[ -f "$SUT" && -x "$MIGRATE" ]] || { printf '[FATAL] script under test missing\n' >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { printf '[FATAL] jq is required\n' >&2; exit 2; }

# The legacy ids are literals here, never read out of the gate library the scripts source: a typo
# there then reds this suite instead of agreeing with it (#12931 review, SM1).
OZ="5af02a2f394e9ba6e0ea23c381a26b67"
OA="4d5ba6f096b2686fbdd404167dd4e125"
grep -qx "CFAM_OLD_ZONE_ID=\"$OZ\"" "$REPO/tests/scripts/lib/cf-account-migrate-gate.sh" \
  && grep -qx "CFAM_OLD_ACCOUNT_ID=\"$OA\"" "$REPO/tests/scripts/lib/cf-account-migrate-gate.sh" \
  || { printf '[FATAL] OLD ids in the gate library differ from the legacy account literals\n' >&2; exit 1; }
SENTINEL="SENTINEL-SECRET-VALUE-DO-NOT-PRINT"

# shellcheck source=/dev/null
source "$REPO/tests/scripts/lib/cf-account-migrate-gate.sh" || { printf '[FATAL] cannot source the gate\n' >&2; exit 2; }
NZ="$CFAM_NEW_ZONE_ID"; NA="$CFAM_NEW_ACCOUNT_ID"

SBX="$(mktemp -d -t cf-migrate-job.XXXXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 2; }
trap 'rm -rf "$SBX"' EXIT INT TERM HUP
mkdir -p "$SBX/bin" "$SBX/runs" "$SBX/mut" || exit 2
PRISTINE="$SBX/pristine.sh"
cp "$SUT" "$PRISTINE" || exit 2

PASS=0; FAIL=0; CASES=0
pass() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
fail() {
  FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1"
  if [[ -n "${LAST_D:-}" && -f "$LAST_D/out.txt" ]]; then
    printf '    rc=%s; last output of %s:\n' "$(cat "$LAST_D/rc" 2>/dev/null)" "${LAST_D##*/}"
    tail -n 12 "$LAST_D/out.txt" "$LAST_D/err.txt" | sed 's/^/      /'
  fi
}
verdict() { CASES=$((CASES + 1)); if [[ "$1" == "0" ]]; then pass "$2"; else fail "$2"; fi; }

# INSTRUMENT SELF-TEST: both arms must move their counters, or every verdict below is decorative.
_p0=$PASS; _f0=$FAIL; _c0=$CASES
verdict 0 "instrument self-test: the PASS arm records"
verdict 1 "instrument self-test: the FAIL arm records (EXPECTED, subtracted below)"
if [[ "$PASS" -ne $((_p0 + 1)) || "$FAIL" -ne $((_f0 + 1)) || "$CASES" -ne $((_c0 + 2)) ]]; then
  printf '[FATAL] instrument self-test: verdict did not route both arms\n' >&2; exit 2
fi
PASS=$((PASS - 1)); FAIL=$((FAIL - 1)); CASES=$((CASES - 2))

# ---------------------------------------------------------------------------
# STUBS
# ---------------------------------------------------------------------------
cat >"$SBX/bin/terraform" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
D="${STUB_DIR:?}"
if [[ -f backend_override.tf ]] && grep -q 'backend "local"' backend_override.tf; then L=local; S="$PWD/rehearsal.tfstate"
else L=remote; S="$D/remote.tfstate"; fi
log() { printf 'terraform[%s] %s\n' "$L" "$*" >>"$D/calls.log"; }
# Any TF_LOG* reaching terraform is recorded: provider/state debug logs print secrets.
for v in TF_LOG TF_LOG_PATH TF_LOG_CORE TF_LOG_PROVIDER; do
  [[ -n "${!v:-}" ]] && printf 'TFLOG-LEAK %s in terraform %s\n' "$v" "${1:-}" >>"$D/calls.log"
done
mode() { if [[ -f "$D/mode.$1" ]]; then cat "$D/mode.$1"; else printf '0'; fi; }
case "${1:-}" in
  init)
    log "init dotterraform=$([[ -e .terraform ]] && echo yes || echo no)"; exit 0 ;;
  state)
    case "${2:-}" in
      pull) log "state pull"; cat "$S" ;;
      rm)
        shift 2; log "state rm argc=$#"
        jq --args '.serial += 1 | .show.values.root_module.resources |= map(select(.address as $x | any($ARGS.positional[]; . == $x) | not))' "$@" <"$S" >"$S.new" || exit 70
        mv "$S.new" "$S"
        for a in "$@"; do printf 'Removed %s\n' "$a"; done
        printf 'Successfully removed %d resource instance(s).\n' "$#" ;;
      *) log "UNEXPECTED $*"; exit 64 ;;
    esac ;;
  show)
    if [[ "$#" -eq 2 && "$2" == -json ]]; then log "show -json state"; jq '.show' "$S"
    elif [[ "$#" -eq 3 && "$2" == -json ]]; then log "show -json tfplan"; cat "$D/plan.json"
    else log "UNEXPECTED $*"; exit 64; fi ;;
  plan)
    shift; log "plan"; : >"$D/plan_args.$L"
    for a in "$@"; do
      printf '%s\n' "$a" >>"$D/plan_args.$L"
      [[ "$a" == -out=* ]] && : >"${a#-out=}"
    done
    printf 'Plan: stub\n'; exit "$(mode plan)" ;;
  apply) shift; log "apply $*"; exit "$(mode apply)" ;;
  *) log "UNEXPECTED $*"; exit 64 ;;
esac
STUB
# doppler accepts exactly `run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var --`.
cat >"$SBX/bin/doppler" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
D="${STUB_DIR:?}"
printf 'doppler %s\n' "${1:-}" >>"$D/calls.log"
[[ $# -gt 9 && "$1 $2 $3 $4 $5 $6 $7 $8 $9" == "run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var --" ]] \
  || { printf 'doppler %s\n' "$*" >>"$D/refused.log"; exit 64; }
if [[ -f "$D/mode.doppler" ]]; then exit "$(cat "$D/mode.doppler")"; fi
shift 9
# A Doppler-side TF_LOG* (the stub injects what doppler.inject names) must still be stripped.
if [[ -f "$D/doppler.inject" ]]; then while IFS= read -r kv; do export "${kv?}"; done <"$D/doppler.inject"; fi
export TF_VAR_cf_zone_id="${TF_VAR_cf_zone_id:-$(sed -n 1p "$D/ids")}"
export TF_VAR_cf_account_id="${TF_VAR_cf_account_id:-$(sed -n 2p "$D/ids")}"
export TF_VAR_cf_r2_account_id="${TF_VAR_cf_r2_account_id:-$(sed -n 3p "$D/ids")}"
# Synthesized provider tokens: tok-<variable name>. The curl fake maps a bearer back to its name.
for t in cf_api_token cf_api_token_rulesets cf_api_token_pages cf_api_token_zone_settings cf_api_token_bot_management; do
  export "TF_VAR_$t=tok-$t"
done
exec "$@"
STUB
# gh accepts exactly the modeled argv: `run list --workflow <gated wf> --status <one of the five
# live statuses> --limit 50 --json databaseId --jq length`. Anything else exits 64 and lands in
# refused.log, which the suite asserts empty for every pristine run.
cat >"$SBX/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
D="${STUB_DIR:?}"
no() { printf 'gh %s\n' "$*" >>"$D/refused.log"; exit 64; }
[[ $# -eq 12 && "$1 $2 $3 $5" == "run list --workflow --status" && "$7 $8 $9 ${10} ${11} ${12}" == "--limit 50 --json databaseId --jq length" ]] || no "$@"
case "$6" in queued|in_progress|waiting|pending|requested) ;; *) no "$@" ;; esac
grep -qxF -- "$4" "${STUB_GATED:?}" || no "$@"
printf 'gh run list workflow=%s status=%s\n' "$4" "$6" >>"$D/calls.log"
if [[ -f "$D/mode.gh" ]]; then rc="$(cat "$D/mode.gh")"; exit "${rc:-1}"; fi
if [[ -f "$D/gh.$4.$6" ]]; then cat "$D/gh.$4.$6"; else printf '0\n'; fi
STUB
# aws accepts exactly the job's listing (bucket, prefix, pinned endpoint, R2 env prefix) and the
# state-forget's backup upload to the pinned endpoint under the same prefix.
cat >"$SBX/bin/aws" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
D="${STUB_DIR:?}"
EP="https://4d5ba6f096b2686fbdd404167dd4e125.r2.cloudflarestorage.com"
no() { printf 'aws %s\n' "$*" >>"$D/refused.log"; exit 64; }
printf 'aws %s %s\n' "${1:-}" "${2:-}" >>"$D/calls.log"
case "${1:-} ${2:-}" in
  "s3api list-objects-v2")
    [[ $# -eq 10 && "$3 $4 $5 $6 $7 $8 $9 ${10}" == "--bucket soleur-terraform-state --prefix web-platform/backups/ --output json --endpoint-url $EP" ]] || no "$@"
    [[ "${AWS_DEFAULT_REGION:-}" == auto && "${AWS_REQUEST_CHECKSUM_CALCULATION:-}" == when_required \
      && "${AWS_RESPONSE_CHECKSUM_VALIDATION:-}" == when_required && "${AWS_EC2_METADATA_DISABLED:-}" == true ]] || no "(R2 env prefix missing)" "$@"
    if [[ -f "$D/mode.aws" ]]; then exit "$(cat "$D/mode.aws")"; fi
    if [[ -s "$D/backups.keys" ]]; then jq -Rn '{Contents: [inputs | {Key: .}]}' <"$D/backups.keys"; fi ;;
  "s3 cp")
    [[ $# -eq 7 && "$4" == s3://soleur-terraform-state/web-platform/backups/pre-cf-account-migration-*.tfstate \
      && "$5 $6 $7" == "--only-show-errors --endpoint-url $EP" ]] || no "$@"
    # The upload and the listing both go through the gate library's cfam_r2_aws: one R2 env prefix.
    [[ "${AWS_DEFAULT_REGION:-}" == auto && "${AWS_REQUEST_CHECKSUM_CALCULATION:-}" == when_required \
      && "${AWS_RESPONSE_CHECKSUM_VALIDATION:-}" == when_required && "${AWS_EC2_METADATA_DISABLED:-}" == true ]] || no "(R2 env prefix missing)" "$@"
    k="${4#s3://}"; printf '%s\n' "${k#*/}" >>"$D/backups.keys" ;;
  *) no "$@" ;;
esac
STUB
cat >"$SBX/bin/curl" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
D="${STUB_DIR:?}"
url=""; ua=""; dump=0; prev=""; cfg=0; nullout=0
for a in "$@"; do
  [[ "$prev" == -A ]] && ua="$a"
  [[ "$prev" == -D ]] && dump=1
  [[ "$prev" == --config && "$a" == - ]] && cfg=1
  [[ "$prev" == -o && "$a" == /dev/null ]] && nullout=1
  [[ "$a" == https://* ]] && url="$a"
  prev="$a"
done
printf 'curl %s\n' "$url" >>"$D/calls.log"
printf '%s\n' "$*" >>"$D/curl-argv.log"
if [[ "$url" == https://api.cloudflare.com/client/v4/* ]]; then
  # A Cloudflare API call carries its bearer on stdin (--config -), never in argv.
  [[ "$cfg" -eq 1 ]] || { printf 'curl %s\n' "$*" >>"$D/refused.log"; exit 64; }
  tok="$(sed -n 's/^header = "Authorization: Bearer \(.*\)"$/\1/p')"
  name="${tok#tok-}"
  path="${url#https://api.cloudflare.com/client/v4/}"
  if [[ "$nullout" -eq 1 ]]; then
    # D8 token preflight: -o /dev/null -w '%{http_code}'
    printf 'cf-api-probe %s token=%s\n' "$path" "$name" >>"$D/calls.log"
    if [[ -f "$D/cfcode.$name" ]]; then cat "$D/cfcode.$name"; else printf '200'; fi
    exit 0
  fi
  # The entrypoint gate (-w '\n%{http_code}'): body, newline, code. cf.<path with / -> _> overrides.
  printf 'cf-api-gate %s token=%s\n' "$path" "$name" >>"$D/calls.log"
  f="$D/cf.${path//\//_}"
  if [[ -f "$f" ]]; then code="$(sed -n 1p "$f")"; body="$(sed -n '2,$p' "$f")"
  else
    case "$path" in
      */rulesets) code=200; body='{"result":[]}' ;;
      *) code=404; body='{"success":false}' ;;
    esac
  fi
  printf '%s\n%s' "$body" "$code"
  exit 0
fi
if [[ -f "$D/mode.verify" ]]; then
  [[ "$dump" -eq 1 ]] && printf 'HTTP/2 200\r\n\r\n' || printf '500 '
  exit 0
fi
if [[ "$dump" -eq 1 ]]; then printf 'HTTP/2 200\r\nx-robots-tag: noindex\r\n\r\n'; exit 0; fi
case "$url" in
  https://app.soleur.ai/health) if [[ -f "$D/mode.health" ]]; then printf '526 '; else printf '200 '; fi ;;
  https://www.soleur.ai/) printf '301 https://soleur.ai/' ;;
  https://soleur.ai/) [[ "$ua" == *GPTBot* ]] && printf '200 ' || printf '403 ' ;;
  https://soleur.ai/*) printf '301 https://soleur.ai/elsewhere/' ;;
  *) printf '404 ' ;;
esac
STUB
cat >"$SBX/bin/ssh-keygen" <<'STUB'
#!/usr/bin/env bash
f=""; prev=""
for a in "$@"; do [[ "$prev" == -f ]] && f="$a"; prev="$a"; done
[[ -n "$f" ]] || exit 64
: >"$f"; printf 'ssh-ed25519 AAAAstub test\n' >"$f.pub"
STUB
chmod +x "$SBX/bin/"*

# ---------------------------------------------------------------------------
# FIXTURES
# ---------------------------------------------------------------------------
# build_plan <phase> <out>: a plan that satisfies the gate for <phase>, derived from the gate's spec.
build_plan() {
  local spec lit
  spec="$(cf_account_migrate_phase_spec "$1")" || return 1
  lit="$(_cfam_import_literals)" || return 1
  jq -n --argjson spec "$spec" --argjson lit "$lit" --arg s "$SENTINEL" --arg nz "$NZ" --arg na "$NA" '
    def ids($a): if ($a | test("^cloudflare_(list|pages_project|pages_domain)[.]")) or $a == "cloudflare_ruleset.bulk_redirects" then {account_id: $na}
                 elif ($a | startswith("cloudflare_")) then {zone_id: $nz} else {} end;
    # Ruleset kind/phase, as the root declares them: the entrypoint gate builds its URLs from these.
    def rs($a): {"cloudflare_ruleset.allowlist_ai_crawlers": {kind: "zone", phase: "http_request_firewall_custom"},
                 "cloudflare_ruleset.cache_shared_binaries": {kind: "zone", phase: "http_request_cache_settings"},
                 "cloudflare_ruleset.seo_config_settings": {kind: "zone", phase: "http_config_settings"},
                 "cloudflare_ruleset.seo_page_redirects": {kind: "zone", phase: "http_request_dynamic_redirect"},
                 "cloudflare_ruleset.seo_response_headers": {kind: "zone", phase: "http_response_headers_transform"},
                 "cloudflare_ruleset.bulk_redirects": {kind: "root", phase: "http_request_redirect"}}[$a] // {};
    {format_version: "1.2", resource_changes: [
      $spec | to_entries[] | .key as $a | .value as $c
      | ({address: $a, mode: "managed", type: ($a | split(".")[0]), change: (
            if $c == "create" then {actions: ["create"], before: null, after: ({value: $s} + ids($a) + rs($a))}
            elif $c == "import" then {actions: ["no-op"], importing: {id: $lit[$a]}, before: ids($a), after: ids($a)}
            elif $c == "mutable" then {actions: ["update"], before: {}, after: {plaintext_value: $s}}
            else {actions: ["delete", "create"], before: {id: "tok-id-1"}, after: {value: $s}} end)}
         + (if $c == "replace" then {action_reason: "replace_by_request"} else {} end))
    ]}' >"$2"
}

# remote_state <file> <zone-for-record>: serial 7, two old-id candidates (unless migrated), an R2
# bucket and the replace target.
remote_state() {
  jq -n --arg z "$2" --arg a "$3" --arg oa "$OA" --arg s "$SENTINEL" '
    def r($addr; $t; $v): {address: $addr, mode: "managed", type: $t, name: "n", values: $v};
    {version: 4, serial: 7, lineage: "lin-1", show: {format_version: "1.0", values: {root_module: {resources: [
      r("cloudflare_record.dmarc"; "cloudflare_record"; {zone_id: $z, content: $s}),
      r("cloudflare_list.www_canonical"; "cloudflare_list"; {account_id: $a}),
      r("cloudflare_r2_bucket.luks"; "cloudflare_r2_bucket"; {account_id: $oa}),
      r("doppler_secret.cf_api_token_dns_edit"; "doppler_secret"; {id: "tok-id-1", value: $s})
    ]}}}}' >"$1"
}

# The gated set, derived here independently of the job: every workflow file that uses the
# infra-credentials action, minus the predicate's CFAM_EXEMPT_WORKFLOWS (CTO D1). A literal sample
# stops a shrunk derivation from shrinking the suite with it.
GATED_FILE="$SBX/gated.txt"
EXEMPT_TXT="$(bash -c 'source "$1"; printf "%s\n" "${CFAM_EXEMPT_WORKFLOWS[@]}"' _ "$HERE/scripts/cf-account-migration-complete.sh")" \
  || { printf '[FATAL] cannot read the predicate exempt list\n' >&2; exit 2; }
: >"$GATED_FILE"
for f in "$REPO"/.github/workflows/*.yml "$REPO"/.github/workflows/*.yaml; do
  [[ -f "$f" ]] || continue
  awk '/^[[:space:]]*(-[[:space:]]+)?uses:[[:space:]]*\.\/\.github\/actions\/infra-credentials\/?[[:space:]]*(#.*)?$/ {x=1} END {exit !x}' "$f" || continue
  grep -qxF -- "${f##*/}" <<<"$EXEMPT_TXT" || printf '%s\n' "${f##*/}" >>"$GATED_FILE"
done
N_GATED="$(grep -c . "$GATED_FILE")"
LIVE="queued in_progress waiting pending requested"

LAST_D=""
# new_case <label> <phase> <rehearsal> -> sets LAST_D; a valid, converging case by default.
new_case() {
  local d
  d="$(mktemp -d "$SBX/runs/${1//[^A-Za-z0-9._-]/_}.XXXXXX")" || return 1
  mkdir -p "$d/root/.terraform" "$d/runner" || return 1
  printf 'terraform {}\n' >"$d/root/main.tf"; : >"$d/root/.terraform/marker"
  : >"$d/calls.log"; : >"$d/backups.keys"
  printf '%s\n%s\n%s\n' "$NZ" "$NA" "$OA" >"$d/ids"
  remote_state "$d/remote.tfstate" "$OZ" "$OA"
  build_plan "$2" "$d/plan.json" || return 1
  printf '%s' "$2" >"$d/phase"; printf '%s' "$3" >"$d/rehearsal"; printf 'MIGRATE-CF-%s' "$2" >"$d/confirm"
  printf 'test %s' "$1" >"$d/reason"
  LAST_D="$d"
}

run_job() { # <dir> <script>; <dir>/env.extra holds extra KEY=VALUE lines (later wins)
  local d="$1" extra=()
  if [[ -f "$d/env.extra" ]]; then mapfile -t extra <"$d/env.extra"; fi
  env -u TF_VAR_cf_zone_id -u TF_VAR_cf_account_id -u TF_LOG -u TF_LOG_PATH -u TF_LOG_CORE -u TF_LOG_PROVIDER \
    PATH="$SBX/bin:$PATH" STUB_DIR="$d" STUB_GATED="$GATED_FILE" \
    MIGRATE_PHASE="$(cat "$d/phase")" CONFIRM="$(cat "$d/confirm")" REHEARSAL="$(cat "$d/rehearsal")" \
    REASON="$(cat "$d/reason")" GITHUB_WORKSPACE="$REPO" RUNNER_TEMP="$d/runner" INFRA_DIR="$d/root" \
    GH_TOKEN=stub GH_REPO=o/r DOPPLER_TOKEN=stub \
    GITHUB_STEP_SUMMARY="$d/summary.md" CFAM_VERIFY_TRIES=2 CFAM_VERIFY_SLEEP=0 \
    ${extra[@]+"${extra[@]}"} bash "$2" >"$d/out.txt" 2>"$d/err.txt"
  printf '%s' "$?" >"$d/rc"
  printf '%s' "$2" >"$d/script"
}

rc_of() { cat "$1/rc"; }
calls() { grep -c -- "$2" "$1/calls.log"; }
line_no() { grep -n -m1 -- "$2" "$1/calls.log" | cut -d: -f1; }
refused_for() { [[ "$(rc_of "$1")" == 1 ]] && grep -q "verdict=refuse reason=$2\$" "$1/out.txt"; }

# argv_matches <dir> <label> <phase>: the plan's -target/-replace argv equals the gate's lists.
argv_matches() {
  local f="$1/plan_args.$2"
  [[ -s "$f" ]] || return 1
  diff <(grep '^-target=' "$f" | sort) <(cf_account_migrate_targets "$3" | sort) >/dev/null \
    && diff <(grep '^-replace=' "$f" | sort) <(cf_account_migrate_replaces "$3" | sort) >/dev/null
}

# ---------------------------------------------------------------------------
# CHECKS: each sets WHY on RED.
# ---------------------------------------------------------------------------
WHY=""
chk_refused_early() { # <dir> <reason>: refused before any terraform/doppler/aws call
  if ! refused_for "$1" "$2"; then WHY="not-refused:rc=$(rc_of "$1")"; return 1; fi
  if grep -qE '^(terraform|doppler|aws)' "$1/calls.log"; then WHY="touched-infra"; return 1; fi
}
chk_bad_confirm() { chk_refused_early "$1" bad-confirm; }
chk_inflight() { chk_refused_early "$1" run-in-flight; }
chk_ids_refused() { # refused before init, any state write or plan
  if grep -q 'terraform\[remote\] state rm' "$1/calls.log"; then WHY="remote-state-rm"; return 1; fi
  if ! refused_for "$1" zone-id-not-new; then WHY="not-refused:rc=$(rc_of "$1")"; return 1; fi
  if grep -q '^terraform' "$1/calls.log"; then WHY="terraform-called"; return 1; fi
}
chk_rehearsal_clean() { # PASS, no aws s3 cp, no apply, remote untouched, forget ran on the local copy
  if [[ -s "$1/refused.log" ]]; then WHY="stub-refused"; return 1; fi
  if grep -q '^TFLOG-LEAK' "$1/calls.log"; then WHY="tf-log-leak"; return 1; fi
  if grep -q '^aws s3 cp' "$1/calls.log"; then WHY="aws-s3-cp"; return 1; fi
  if grep -q '^terraform\[[a-z]*\] apply' "$1/calls.log"; then WHY="apply-called"; return 1; fi
  if [[ "$(jq -r .serial "$1/remote.tfstate")" != 7 ]]; then WHY="remote-serial"; return 1; fi
  if grep -q 'terraform\[remote\] state rm' "$1/calls.log"; then WHY="remote-state-rm"; return 1; fi
  if [[ "$(rc_of "$1")" != 0 ]]; then WHY="rc:$(rc_of "$1")"; return 1; fi
  grep -qx 'cf-account-migrate phase=[a-z-]* mode=rehearsal verdict=PASS applied=false' "$1/out.txt" || { WHY="no-pass-line"; return 1; }
}
chk_refuses_backup_write() {
  refused_for "$1" backup-written || { WHY="rc:$(rc_of "$1")"; return 1; }
}
chk_refuses_serial() {
  refused_for "$1" remote-serial-changed || { WHY="rc:$(rc_of "$1")"; return 1; }
}
chk_gate_blocks_apply() {
  if grep -q '^terraform\[remote\] apply' "$1/calls.log"; then WHY="apply-called"; return 1; fi
  refused_for "$1" gate-refused || { WHY="rc:$(rc_of "$1")"; return 1; }
  grep -q 'cf_account_migrate_gate: phase=redirects-dns verdict=REFUSE' "$1/out.txt" || { WHY="no-refuse-line"; return 1; }
}
chk_r2_ignored() { # a hostile R2_ENDPOINT changes nothing: PASS, and every aws call met the pinned-endpoint fake
  if [[ -s "$1/refused.log" ]]; then WHY="stub-refused"; return 1; fi
  [[ "$(rc_of "$1")" == 0 ]] || { WHY="rc:$(rc_of "$1")"; return 1; }
  grep -q '^aws s3' "$1/calls.log" || { WHY="no-aws-call"; return 1; }
}
chk_budget() { # refused before any infra call, and the injected subscript never ran
  if [[ -e "$1/pwned" ]]; then WHY="injected"; return 1; fi
  chk_refused_early "$1" bad-verify-budget || { WHY+=":$(tail -n1 "$1/out.txt"):$(tail -n1 "$1/err.txt")"; return 1; }
}
chk_health() {
  refused_for "$1" verify-failed || { WHY="rc:$(rc_of "$1")"; return 1; }
  grep -q 'verdict=fail failing=.*app-health' "$1/out.txt" || { WHY="no-app-health"; return 1; }
}
chk_reason() { # one sanitized reason line in the step summary, no workflow-command opener
  grep -q '^- cf-account-migrate phase=redirects-dns rehearsal=true reason=re-run after a 5xx :error title=x:pwned' "$1/summary.md" || { WHY="no-reason-line"; return 1; }
  if grep -qF '::' "$1/summary.md"; then WHY="double-colon"; return 1; fi
  if grep -q '^pwned2' "$1/summary.md"; then WHY="newline-injected"; return 1; fi
}
chk_preflight_refused() { # <dir> <reason>: refused before init, the state forget, or any plan
  if ! refused_for "$1" "$2"; then WHY="not-refused:rc=$(rc_of "$1")"; return 1; fi
  if grep -q '^terraform' "$1/calls.log"; then WHY="terraform-called"; return 1; fi
}
chk_token_403() { chk_preflight_refused "$1" token-not-new-zone || return 1
  grep -qx 'cf-account-migrate preflight=token name=cf_api_token_rulesets http=403' "$1/out.txt" || { WHY="no-code-line"; return 1; }
}
chk_r2_old() { chk_preflight_refused "$1" r2-account-not-old; }
chk_entrypoint_refused() { # <dir>: refused by the entrypoint gate, nothing applied or written
  if grep -q '^terraform\[[a-z]*\] apply' "$1/calls.log"; then WHY="apply-called"; return 1; fi
  if ! refused_for "$1" entrypoint-gate-refused; then WHY="not-refused:rc=$(rc_of "$1")"; return 1; fi
  grep -q 'CLOBBER RISK' "$1/out.txt" || { WHY="no-clobber-line"; return 1; }
  grep -q 'import { to = cloudflare_ruleset.seo_config_settings; id = "zone/'"$NZ"'/live-cfg-1" }' "$1/out.txt" || { WHY="no-import-block"; return 1; }
}
chk_entrypoint_ran() { # PASS, and the gate probed the NEW zone's list with the rulesets token, no seam
  [[ "$(rc_of "$1")" == 0 ]] || { WHY="rc:$(rc_of "$1")"; return 1; }
  grep -qx "cf-api-gate zones/$NZ/rulesets token=cf_api_token_rulesets" "$1/calls.log" || { WHY="no-zone-list"; return 1; }
  grep -qx 'cf-account-migrate entrypoint-gate verdict=PASS' "$1/out.txt" || { WHY="no-pass"; return 1; }
}
chk_backups_timeout() { chk_refused_late "$1" backups-timeout; }
chk_ids_timeout() { chk_refused_late "$1" ids-timeout; }
chk_runs_timeout() { chk_refused_early "$1" runs-timeout; }
chk_refused_late() { # refused for <reason>, nothing applied, no remote state write
  if ! refused_for "$1" "$2"; then WHY="not-refused:rc=$(rc_of "$1")"; return 1; fi
  if grep -qE 'terraform\[remote\] (apply|state rm)' "$1/calls.log"; then WHY="wrote"; return 1; fi
}
chk_zone_rest_args() {
  argv_matches "$1" remote zone-rest || { WHY="argv-mismatch"; return 1; }
  grep -qx -- '-replace=doppler_secret.cf_api_token_dns_edit' "$1/plan_args.remote" || { WHY="no-replace"; return 1; }
}

# ---------------------------------------------------------------------------
# MUTANTS
# ---------------------------------------------------------------------------
mk_mutant() { # <name> <sed-expr>... -> prints the mutant path; aborts the suite on a vacuous mutant
  local name="$1" out="$SBX/mut/$1.sh" e; shift
  cp "$PRISTINE" "$out" || exit 2
  for e in "$@"; do sed -i -e "$e" "$out" || exit 2; done
  if cmp -s "$PRISTINE" "$out"; then printf '[FATAL] mutant %s is identical to pristine\n' "$name" >&2; exit 2; fi
  bash -n "$out" || { printf '[FATAL] mutant %s does not parse\n' "$name" >&2; exit 2; }
  printf '%s' "$out"
}
# red <label> <mutant> <check> <why-regex> <setup-fn>: GREEN on the base (pristine unless RED_BASE
# names an earlier mutant), RED on the mutant for <why>.
red() {
  local label="$1" mut="$2" chk="$3" why="$4" setup="$5" base="${RED_BASE:-$PRISTINE}"
  "$setup" base; run_job "$LAST_D" "$base"; WHY=""
  if ! "$chk" "$LAST_D"; then verdict 1 "$label: check is RED on the base (WHY=$WHY)"; return; fi
  "$setup" mutant; run_job "$LAST_D" "$mut"; WHY=""
  if "$chk" "$LAST_D"; then verdict 1 "$label: mutant survived ($chk stayed GREEN)"; return; fi
  if [[ "$WHY" =~ $why ]]; then verdict 0 "$label: RED as required (WHY=$WHY)"
  else verdict 1 "$label: RED for the wrong reason (WHY=$WHY, wanted /$why/)"; fi
}
green_mut() { # <label> <mutant> <check> <setup-fn>: another guard must still catch this mutant
  "$4" mutant; run_job "$LAST_D" "$2"; WHY=""
  if "$3" "$LAST_D"; then verdict 0 "$1"; else verdict 1 "$1 (WHY=$WHY)"; fi
}

setup_bad_confirm() { new_case "confirm-$1" redirects-dns true; printf 'MIGRATE-CF-zone-rest' >"$LAST_D/confirm"; }
setup_inflight() { new_case "inflight-$1" redirects-dns true; printf '1\n' >"$LAST_D/gh.apply-web-platform-infra.yml.waiting"; }
setup_old_ids() { new_case "oldids-$1" redirects-dns false; printf '%s\n%s\n' "$OZ" "$NA" >"$LAST_D/ids"; }
setup_rehearsal() { new_case "rehearsal-$1" redirects-dns true; }
setup_refuse_apply() {
  new_case "refuse-$1" redirects-dns false
  jq '.resource_changes += [{address: "cloudflare_record.app", mode: "managed", type: "cloudflare_record", change: {actions: ["delete"], before: {}, after: null}}]' \
    "$LAST_D/plan.json" >"$LAST_D/p" && mv "$LAST_D/p" "$LAST_D/plan.json"
}
setup_zone_rest_apply() { new_case "zrest-$1" zone-rest false; remote_state "$LAST_D/remote.tfstate" "$NZ" "$NA"; }
populate_cfg() { printf '200\n{"result":{"id":"live-cfg-1","rules":[{"ref":"r1","action":"set_config"}]}}\n' >"$LAST_D/cf.zones_${NZ}_rulesets_phases_http_config_settings_entrypoint"; }
setup_entry_apply() { new_case "entry-$1" redirects-dns false; populate_cfg; }
setup_entry_rehearsal() { new_case "entryr-$1" redirects-dns true; populate_cfg; }
setup_entry_seam() { new_case "entryseam-$1" redirects-dns true; printf 'PREAPPLY_ENTRYPOINT_FETCH=/bin/false\n' >"$LAST_D/env.extra"; }
setup_token_403() { new_case "tok403-$1" redirects-dns false; printf '403' >"$LAST_D/cfcode.cf_api_token_rulesets"; }
setup_r2_new() { new_case "r2new-$1" redirects-dns false; printf '%s\n%s\n%s\n' "$NZ" "$NA" "$NA" >"$LAST_D/ids"; }
# Nothing reads R2_ENDPOINT: the listing (rehearsal) and the forget's upload (apply) stay on the pinned endpoint.
setup_r2_evil() { new_case "r2evil-$1" redirects-dns true; printf 'R2_ENDPOINT=https://r2.example.invalid\n' >"$LAST_D/env.extra"; }
setup_r2_evil_apply() { new_case "r2evila-$1" redirects-dns false; printf 'R2_ENDPOINT=https://r2.example.invalid\n' >"$LAST_D/env.extra"; }
setup_budget() { new_case "budget-$1" redirects-dns false; printf 'CFAM_VERIFY_TRIES=P[$(touch %s/pwned)]\n' "$LAST_D" >"$LAST_D/env.extra"; }
setup_imports_seam() { new_case "impseam-$1" redirects-dns true; printf 'CFAM_IMPORTS_FILE=%s/no-such-imports.tf\n' "$LAST_D" >"$LAST_D/env.extra"; }
setup_tflog() {
  new_case "tflog-$1" redirects-dns true
  printf 'TF_LOG=DEBUG\nTF_LOG_PATH=%s/tf.log\n' "$LAST_D" >"$LAST_D/env.extra"
  printf 'TF_LOG_PROVIDER=TRACE\n' >"$LAST_D/doppler.inject"
}
setup_tflog_doppler() { new_case "tflogd-$1" redirects-dns true; printf 'TF_LOG_PROVIDER=TRACE\n' >"$LAST_D/doppler.inject"; }
setup_health() { new_case "health-$1" redirects-dns false; : >"$LAST_D/mode.health"; }
setup_reason() { new_case "reason-$1" redirects-dns true; printf 're-run after a 5xx\n::error title=x::pwned\x07 `code`\npwned2' >"$LAST_D/reason"; }
setup_backups_timeout() { new_case "bkto-$1" redirects-dns true; printf '124' >"$LAST_D/mode.aws"; }
setup_ids_timeout() { new_case "idsto-$1" redirects-dns false; printf '124' >"$LAST_D/mode.doppler"; }
setup_runs_timeout() { new_case "runsto-$1" redirects-dns false; printf '124' >"$LAST_D/mode.gh"; }

printf 'cf-account-migrate-job: battery\n'
cmp -s "$SUT" "$PRISTINE"; verdict "$?" "pristine copy equals the script under test"
for p in redirects-dns zone-rest; do
  remote_state "$SBX/fx.tfstate" "$NZ" "$NA" && jq .show "$SBX/fx.tfstate" >"$SBX/fx-state.json" \
    && build_plan "$p" "$SBX/fx.json" && cf_account_migrate_gate "$p" "$SBX/fx.json" "$SBX/fx-state.json" >/dev/null
  verdict "$?" "fixture: the derived $p plan passes the real gate (else every PASS row is void)"
done

# --- Input refusals -----------------------------------------------------------
printf '\n[inputs] refused before any infra call\n'
setup_bad_confirm c; run_job "$LAST_D" "$PRISTINE"; WHY=""
chk_bad_confirm "$LAST_D"; verdict "$?" "confirm for another phase -> reason=bad-confirm, no terraform/doppler/aws call ($WHY)"
new_case unknown redirects-dns true
printf 'tunnel' >"$LAST_D/phase"; printf 'MIGRATE-CF-tunnel' >"$LAST_D/confirm"; run_job "$LAST_D" "$PRISTINE"; WHY=""
chk_refused_early "$LAST_D" unknown-phase; verdict "$?" "phase=tunnel (PR2) -> reason=unknown-phase ($WHY)"
new_case blank-reason redirects-dns true; printf '  ' >"$LAST_D/reason"; run_job "$LAST_D" "$PRISTINE"; WHY=""
chk_refused_early "$LAST_D" no-reason; verdict "$?" "blank reason -> reason=no-reason ($WHY)"
new_case bad-rehearsal redirects-dns yes; run_job "$LAST_D" "$PRISTINE"; WHY=""
chk_refused_early "$LAST_D" bad-rehearsal; verdict "$?" "rehearsal=yes -> reason=bad-rehearsal ($WHY)"

# --- In-flight runs -------------------------------------------------------------
printf '\n[inflight] a queued/waiting/running run on any gated workflow refuses\n'
r=1
for w in apply-web-platform-infra.yml apply-deploy-pipeline-fix.yml cf-lb-overlay.yml key-rotate.yml inngest-key-rotate.yml; do
  grep -qxF "$w" "$GATED_FILE" || r=0
done
grep -qxF cf-account-migrate.yml "$GATED_FILE" && r=0
grep -qxF scheduled-terraform-drift.yml "$GATED_FILE" && r=0
[[ "$r" -eq 1 && "$N_GATED" -ge 5 ]]; verdict "$?" "derived gated set (${N_GATED}) holds the five root planners and neither plan-only exempt workflow"
for spec in apply-web-platform-infra.yml:waiting apply-deploy-pipeline-fix.yml:queued cf-lb-overlay.yml:in_progress key-rotate.yml:pending inngest-key-rotate.yml:requested; do
  new_case "inflight-${spec%%:*}" redirects-dns true; printf '1\n' >"$LAST_D/gh.${spec%%:*}.${spec#*:}"
  run_job "$LAST_D" "$PRISTINE"; WHY=""
  chk_inflight "$LAST_D"; verdict "$?" "${spec#*:} run of ${spec%%:*} -> reason=run-in-flight ($WHY)"
done
new_case inflight-ghfail redirects-dns false; : >"$LAST_D/mode.gh"; run_job "$LAST_D" "$PRISTINE"; WHY=""
chk_refused_early "$LAST_D" runs-unreadable; verdict "$?" "gh run list failure -> reason=runs-unreadable, fail closed ($WHY)"
new_case inflight-timeout redirects-dns false; printf '124' >"$LAST_D/mode.gh"; run_job "$LAST_D" "$PRISTINE"; WHY=""
chk_refused_early "$LAST_D" runs-timeout; verdict "$?" "gh run list timing out (rc 124) -> reason=runs-timeout, fail closed ($WHY)"
new_case inflight-all redirects-dns true; run_job "$LAST_D" "$PRISTINE"
r=1
diff <(sed -n 's/^gh run list workflow=\([^ ]*\) status=\(.*\)$/\1 \2/p' "$LAST_D/calls.log" | sort) \
  <(while IFS= read -r w; do for st in $LIVE; do printf '%s %s\n' "$w" "$st"; done; done <"$GATED_FILE" | sort) >/dev/null && r=0
verdict "$r" "the in-flight check reads every gated workflow (${N_GATED}) x the 5 live statuses, each pair exactly once"
r=1; grep -qx "cf-account-migrate inflight=none workflows=${N_GATED}" "$LAST_D/out.txt" && r=0
verdict "$r" "the in-flight line reports the derived gated count"

# --- Id preflight ---------------------------------------------------------------
printf '\n[ids] Doppler must resolve the NEW ids before anything is written\n'
setup_old_ids x; run_job "$LAST_D" "$PRISTINE"; WHY=""
chk_ids_refused "$LAST_D"; verdict "$?" "old zone id in Doppler -> reason=zone-id-not-new before init/forget ($WHY)"
new_case oldacct redirects-dns false; printf '%s\n%s\n' "$NZ" "$OA" >"$LAST_D/ids"; run_job "$LAST_D" "$PRISTINE"
r=1; refused_for "$LAST_D" account-id-not-new && ! grep -q '^terraform' "$LAST_D/calls.log" && r=0
verdict "$r" "old account id in Doppler -> reason=account-id-not-new before any terraform call"
r=1; ! grep -q "$OA" "$LAST_D/out.txt" "$LAST_D/err.txt" && r=0
verdict "$r" "the id preflight does not print the resolved ids"

# --- Token / R2 preflight (CTO D8) ------------------------------------------------------
printf '\n[preflight] R2 stays legacy; every phase token reads the NEW zone/account\n'
setup_token_403 x; run_job "$LAST_D" "$PRISTINE"; WHY=""
chk_token_403 "$LAST_D"; verdict "$?" "rulesets token 403 on the new zone -> reason=token-not-new-zone, only the code printed, no terraform call ($WHY)"
setup_r2_new x; run_job "$LAST_D" "$PRISTINE"; WHY=""
chk_r2_old "$LAST_D"; verdict "$?" "cf_r2_account_id = the NEW account -> reason=r2-account-not-old, no terraform call ($WHY)"
new_case tok-paths redirects-dns true; run_job "$LAST_D" "$PRISTINE"
r=1
diff <(sed -n 's/^cf-api-probe \(.*\)$/\1/p' "$LAST_D/calls.log" | sort) <(printf '%s\n' \
  "zones/$NZ/dns_records?per_page=1 token=cf_api_token" "zones/$NZ/rulesets token=cf_api_token_rulesets" \
  "accounts/$NA/pages/projects token=cf_api_token_pages" | sort) >/dev/null && r=0
verdict "$r" "redirects-dns probes exactly its three tokens, each on the new zone/account"
r=1; [[ "$(cat "$LAST_D/rc")" == 0 ]] && ! grep -q 'tok-' "$LAST_D/curl-argv.log" && r=0
verdict "$r" "no token value reaches curl's argv (stdin config only)"
new_case tok-zrest zone-rest true; remote_state "$LAST_D/remote.tfstate" "$NZ" "$NA"; run_job "$LAST_D" "$PRISTINE"
r=1
diff <(sed -n 's/^cf-api-probe \(.*\)$/\1/p' "$LAST_D/calls.log" | sort) <(printf '%s\n' \
  "zones/$NZ/settings token=cf_api_token_zone_settings" "zones/$NZ/bot_management token=cf_api_token_bot_management" | sort) >/dev/null && r=0
verdict "$r" "zone-rest probes exactly its two tokens (zone_settings, bot_management)"
r=1; [[ "$(cf_account_migrate_phase_tokens redirects-dns | tr '\n' ' ')" == "cf_api_token cf_api_token_rulesets cf_api_token_pages " \
  && "$(cf_account_migrate_phase_tokens zone-rest | tr '\n' ' ')" == "cf_api_token_zone_settings cf_api_token_bot_management " ]] \
  && ! cf_account_migrate_phase_tokens tunnel >/dev/null 2>&1 && r=0
verdict "$r" "cf_account_migrate_phase_tokens: the ruled token lists per phase, unknown phase fails"

# --- Rehearsal --------------------------------------------------------------------
printf '\n[rehearsal] local-backend scratch copy, nothing written\n'
setup_rehearsal x; run_job "$LAST_D" "$PRISTINE"; D_REH="$LAST_D"; WHY=""
chk_rehearsal_clean "$D_REH"; verdict "$?" "redirects-dns rehearsal: PASS, no aws s3 cp, no apply, remote serial 7 ($WHY)"
r=1; grep -q 'terraform\[local\] state rm argc=2' "$D_REH/calls.log" && r=0
verdict "$r" "rehearsal: the real state forget removed the 2 old-id entries from the LOCAL copy"
r=1; grep -qx 'cf-account-migrate rehearsal remote_serial=7 serial_unchanged=true backups_unchanged=true' "$D_REH/out.txt" && r=0
verdict "$r" "rehearsal: prints the serial/backups no-write assertion"
r=1; grep -q 'terraform\[local\] init dotterraform=no' "$D_REH/calls.log" && r=0
verdict "$r" "rehearsal: the scratch root is initialised without the copied .terraform"
argv_matches "$D_REH" local redirects-dns; verdict "$?" "rehearsal: plan -target/-replace argv equals the gate's redirects-dns lists"
r=1; [[ ! -e "$D_REH/plan_args.remote" ]] && r=0
verdict "$r" "rehearsal: no plan ran against the remote backend"
r=1; grep -q 'cf_account_migrate_gate: phase=redirects-dns verdict=PASS ' "$D_REH/out.txt" && r=0
verdict "$r" "rehearsal: prints the gate verdict line"
r=1; [[ ! -e "$D_REH/runner/cf-migrate" ]] && r=0
verdict "$r" "rehearsal: \$RUNNER_TEMP/cf-migrate removed on exit"
new_case reh-refuse redirects-dns true
jq '.resource_changes[0].change.actions = ["update"]' "$LAST_D/plan.json" >"$LAST_D/p" && mv "$LAST_D/p" "$LAST_D/plan.json"
run_job "$LAST_D" "$PRISTINE"
r=1; refused_for "$LAST_D" rehearsal-refused && grep -q 'serial_unchanged=true' "$LAST_D/out.txt" \
  && ! grep -q '\] apply' "$LAST_D/calls.log" && r=0
verdict "$r" "rehearsal + gate REFUSE: reason=rehearsal-refused, no-write assertion still ran, no apply"
new_case reh-zrest zone-rest true; remote_state "$LAST_D/remote.tfstate" "$NZ" "$NA"; run_job "$LAST_D" "$PRISTINE"; WHY=""
r=1; chk_rehearsal_clean "$LAST_D" && ! grep -q 'state rm' "$LAST_D/calls.log" && argv_matches "$LAST_D" local zone-rest && r=0
verdict "$r" "zone-rest rehearsal: PASS, no state forget, -replace argv equals the gate's list ($WHY)"

# --- Apply --------------------------------------------------------------------------
printf '\n[apply] forget -> plan -> gate -> apply, only on PASS\n'
new_case apply redirects-dns false; run_job "$LAST_D" "$PRISTINE"; D_AP="$LAST_D"
r=1; [[ "$(rc_of "$D_AP")" == 0 ]] && grep -qx 'cf-account-migrate phase=redirects-dns mode=apply verdict=PASS applied=true' "$D_AP/out.txt" && r=0
verdict "$r" "redirects-dns apply: rc 0, verdict=PASS applied=true"
b="$(line_no "$D_AP" '^aws s3 cp')"; s="$(line_no "$D_AP" 'terraform\[remote\] state rm')"
p="$(line_no "$D_AP" 'terraform\[remote\] plan')"; g="$(line_no "$D_AP" 'show -json tfplan')"; a="$(line_no "$D_AP" 'terraform\[remote\] apply')"
r=1; [[ -n "$b" && -n "$s" && -n "$p" && -n "$g" && -n "$a" ]] && ((b < s && s < p && p < g && g < a)) && r=0
verdict "$r" "apply order: backup upload < state rm < plan < show tfplan < apply"
r=1; [[ "$(calls "$D_AP" 'terraform\[remote\] apply')" -eq 1 ]] && grep -q 'apply .*cf-migrate/tfplan$' "$D_AP/calls.log" && r=0
verdict "$r" "apply runs exactly once, on the graded tfplan"
argv_matches "$D_AP" remote redirects-dns; verdict "$?" "apply: plan -target/-replace argv equals the gate's redirects-dns lists"
r=1; grep -qx 'cf-account-migrate verify=redirects-dns verdict=ok' "$D_AP/out.txt" && r=0
verdict "$r" "apply: post-apply redirect/noindex/crawler probes pass"
r=1; ! grep -q "$SENTINEL" "$D_AP/out.txt" "$D_AP/err.txt" "$D_REH/out.txt" "$D_REH/err.txt" && r=0
verdict "$r" "no state or plan value reaches stdout/stderr (sentinel absent)"
setup_refuse_apply x; run_job "$LAST_D" "$PRISTINE"; WHY=""
chk_gate_blocks_apply "$LAST_D"; verdict "$?" "gate REFUSE blocks apply: reason=gate-refused, no apply call ($WHY)"
new_case planfail redirects-dns false; printf '1' >"$LAST_D/mode.plan"; run_job "$LAST_D" "$PRISTINE"
r=1; refused_for "$LAST_D" gate-refused && grep -q 'Guard 4' "$LAST_D/out.txt" && ! grep -q '\] apply' "$LAST_D/calls.log" && r=0
verdict "$r" "plan failure (e.g. Guard 4 validation) surfaces an ::error:: naming Guard 4, no apply"
setup_zone_rest_apply x; run_job "$LAST_D" "$PRISTINE"; WHY=""
r=1; [[ "$(rc_of "$LAST_D")" == 0 ]] && chk_zone_rest_args "$LAST_D" && ! grep -qE 'state rm|^curl https://[a-z.]*soleur[.]ai' "$LAST_D/calls.log" && r=0
verdict "$r" "zone-rest apply: no forget, no probes, -target/-replace argv equals the gate's lists, applied ($WHY)"
new_case verify-broken redirects-dns false; : >"$LAST_D/mode.verify"; run_job "$LAST_D" "$PRISTINE"
r=1; refused_for "$LAST_D" verify-failed && grep -q '\] apply' "$LAST_D/calls.log" && r=0
verdict "$r" "probes failing after apply -> reason=verify-failed (the job goes red)"
new_case applyfail redirects-dns false; printf '1' >"$LAST_D/mode.apply"; run_job "$LAST_D" "$PRISTINE"
r=1; refused_for "$LAST_D" apply-failed && ! grep -q '^curl https://[a-z.]*soleur[.]ai' "$LAST_D/calls.log" && r=0
verdict "$r" "terraform apply failure -> reason=apply-failed, no probes"
new_case rerun redirects-dns false; remote_state "$LAST_D/remote.tfstate" "$NZ" "$NA"; run_job "$LAST_D" "$PRISTINE"
r=1; [[ "$(rc_of "$LAST_D")" == 0 ]] && grep -q 'cf-state-migrate verdict=ok removed=0' "$LAST_D/out.txt" && ! grep -q 'state rm' "$LAST_D/calls.log" && r=0
verdict "$r" "redirects-dns re-dispatch after migration: forget removes 0, apply proceeds"

# --- Whole-list entrypoint gate (CTO D2) --------------------------------------------
printf '\n[entrypoint] a populated live phase entrypoint blocks the create (ADR-136)\n'
setup_entry_apply x; run_job "$LAST_D" "$PRISTINE"; WHY=""
chk_entrypoint_refused "$LAST_D"; verdict "$?" "apply: populated http_config_settings -> reason=entrypoint-gate-refused, import block printed, apply never called ($WHY)"
setup_entry_rehearsal x; run_job "$LAST_D" "$PRISTINE"; WHY=""
r=1; chk_entrypoint_refused "$LAST_D" && grep -q 'serial_unchanged=true backups_unchanged=true' "$LAST_D/out.txt" && r=0
verdict "$r" "rehearsal: the same refusal, after the no-write assertions ($WHY)"
setup_entry_seam x; run_job "$LAST_D" "$PRISTINE"; WHY=""
chk_entrypoint_ran "$LAST_D"; verdict "$?" "the gate runs on the NEW zone in zone-list mode with the rulesets token; its fetch seam is ignored ($WHY)"
r=1; p_line="$(line_no "$D_AP" 'show -json tfplan')"; g_line="$(line_no "$D_AP" "cf-api-gate zones/$NZ/rulesets ")"; a_line="$(line_no "$D_AP" 'terraform\[remote\] apply')"
[[ -n "$p_line" && -n "$g_line" && -n "$a_line" ]] && ((p_line < g_line && g_line < a_line)) && r=0
verdict "$r" "apply order: phase gate (show tfplan) < entrypoint gate < apply"

# --- Hardening ----------------------------------------------------------------------
printf '\n[hardening] pinned endpoint, bounded calls, test seams, logging, audit line\n'
for pair in r2_evil:chk_r2_ignored r2_evil_apply:chk_r2_ignored budget:chk_budget imports_seam:chk_rehearsal_clean tflog:chk_rehearsal_clean \
  tflog_doppler:chk_rehearsal_clean health:chk_health reason:chk_reason backups_timeout:chk_backups_timeout \
  ids_timeout:chk_ids_timeout; do
  "setup_${pair%%:*}" x; run_job "$LAST_D" "$PRISTINE"; WHY=""
  "${pair#*:}" "$LAST_D"; verdict "$?" "${pair%%:*}: ${pair#*:} green on the pristine script ($WHY)"
done

# --- Re-dispatch after a committed forget (CTO D10) ------------------------------------
# The first redirects-dns apply forgot every non-R2 cloudflare_* entry and then failed before
# writing any. Remote state now holds the R2 bucket plus non-Cloudflare entries only. Ruled
# contract of cf-account-state-migrate.sh: such a state gives `verdict=ok removed=0` (no backup,
# no state rm), and the job must then reach the plan. The forget is modelled by a contract stub in
# a mirror workspace (the real script's side is pinned in cf-account-state-migrate.test.sh, owned
# with the D10 change); everything else here is the real job, gate and libraries.
printf '\n[re-dispatch] after a committed forget, the job reaches the plan\n'
MIRROR="$SBX/mirror"
mkdir -p "$MIRROR/apps/web-platform/infra/scripts" || exit 2
ln -s "$REPO/.github" "$MIRROR/.github"; ln -s "$REPO/tests" "$MIRROR/tests"
ln -s "$HERE/scripts/cf-account-migration-complete.sh" "$MIRROR/apps/web-platform/infra/scripts/cf-account-migration-complete.sh"
# The gate resolves the committed imports file relative to itself, so the mirror carries it too.
ln -s "$HERE/cf-account-migration-imports.tf" "$MIRROR/apps/web-platform/infra/cf-account-migration-imports.tf"
cat >"$MIRROR/apps/web-platform/infra/scripts/cf-account-state-migrate.sh" <<'STUB'
#!/usr/bin/env bash
# Contract stub (CTO D10): zero non-R2 cloudflare_* candidates AND >=1 managed cloudflare_r2_bucket
# -> verdict=ok removed=0; zero cloudflare_* at all -> abort zero-candidates.
set -uo pipefail
printf 'state-migrate-stub %s\n' "$*" >>"${STUB_DIR:?}/calls.log"
j="$(terraform show -json)" || { echo "cf-state-migrate verdict=abort reason=show-failed"; exit 1; }
r2="$(jq '[.values.root_module.resources[]? | select(.mode == "managed" and .type == "cloudflare_r2_bucket")] | length' <<<"$j")"
cf="$(jq '[.values.root_module.resources[]? | select(.mode == "managed" and (.type | startswith("cloudflare_")) and .type != "cloudflare_r2_bucket")] | length' <<<"$j")"
if [[ "$cf" -eq 0 && "$r2" -ge 1 ]]; then echo "cf-state-migrate verdict=ok removed=0 skipped=0"; exit 0; fi
echo "cf-state-migrate verdict=abort reason=zero-candidates"; exit 1
STUB
chmod +x "$MIRROR/apps/web-platform/infra/scripts/cf-account-state-migrate.sh"
forgotten_state() { # <file>: serial 8, the R2 bucket and a non-Cloudflare secret only
  jq -n --arg oa "$OA" --arg s "$SENTINEL" '
    def r($addr; $t; $v): {address: $addr, mode: "managed", type: $t, name: "n", values: $v};
    {version: 4, serial: 8, lineage: "lin-1", show: {format_version: "1.0", values: {root_module: {resources: [
      r("cloudflare_r2_bucket.luks"; "cloudflare_r2_bucket"; {account_id: $oa}),
      r("doppler_secret.cf_api_token_dns_edit"; "doppler_secret"; {id: "tok-id-1", value: $s})
    ]}}}}' >"$1"
}
chk_redispatch() { # <dir> <mode>: forget ok removed=0, no state rm, reached the plan and PASS
  if ! grep -q '^state-migrate-stub ' "$1/calls.log"; then WHY="no-forget-call"; return 1; fi
  if ! grep -q 'cf-state-migrate verdict=ok removed=0' "$1/out.txt"; then WHY="forget-not-ok"; return 1; fi
  if grep -q 'state rm' "$1/calls.log"; then WHY="state-rm"; return 1; fi
  if ! grep -q 'terraform\[[a-z]*\] plan' "$1/calls.log"; then WHY="no-plan"; return 1; fi
  [[ "$(rc_of "$1")" == 0 ]] || { WHY="rc:$(rc_of "$1")"; return 1; }
  grep -qx "cf-account-migrate phase=redirects-dns mode=$2 verdict=PASS applied=$([[ $2 == apply ]] && echo true || echo false)" "$1/out.txt" || { WHY="no-pass-line"; return 1; }
}
for mode in apply rehearsal; do
  new_case "redispatch-$mode" redirects-dns "$([[ $mode == rehearsal ]] && echo true || echo false)"
  forgotten_state "$LAST_D/remote.tfstate"
  printf 'GITHUB_WORKSPACE=%s\n' "$MIRROR" >"$LAST_D/env.extra"
  run_job "$LAST_D" "$PRISTINE"; WHY=""
  chk_redispatch "$LAST_D" "$mode"; verdict "$?" "$mode re-dispatch on a forgotten state (R2 + non-Cloudflare only): forget ok removed=0, plan reached, PASS ($WHY)"
done
new_case redispatch-nocf redirects-dns false
jq '.show.values.root_module.resources |= map(select(.type | startswith("cloudflare_") | not))' "$LAST_D/remote.tfstate" >"$LAST_D/s" && mv "$LAST_D/s" "$LAST_D/remote.tfstate"
printf 'GITHUB_WORKSPACE=%s\n' "$MIRROR" >"$LAST_D/env.extra"
run_job "$LAST_D" "$PRISTINE"
r=1; refused_for "$LAST_D" state-migrate-failed && ! grep -q 'terraform\[remote\] plan' "$LAST_D/calls.log" && r=0
verdict "$r" "no cloudflare_* at all: the forget aborts and the job refuses state-migrate-failed before any plan"
new_case applyfail-msg redirects-dns false; printf '1' >"$LAST_D/mode.apply"; run_job "$LAST_D" "$PRISTINE"
r=1; grep -q 'Fix forward.*re-dispatch the same phase: the forget then removes 0' "$LAST_D/out.txt" && ! grep -q 'every phase is idempotent' "$LAST_D/out.txt" && r=0
verdict "$r" "apply-failed names the fix-forward / re-dispatch path (removed=0 on the re-run)"

# --- Mutations ------------------------------------------------------------------------
printf '\n[mutations] each refusal is load-bearing\n'
M1="$(mk_mutant confirm 's/|| refuse bad-confirm/|| true/')"
red "M1 confirm check removed" "$M1" chk_bad_confirm '^not-refused' setup_bad_confirm
M2="$(mk_mutant inflight 's/|| refuse run-in-flight/|| true/')"
red "M2 in-flight refusal removed" "$M2" chk_inflight '^not-refused' setup_inflight
M3="$(mk_mutant ids 's/^  check_ids$/  :/')"
red "M3 id preflight removed (forget would run on old ids)" "$M3" chk_ids_refused '^remote-state-rm$' setup_old_ids
# shellcheck disable=SC2016 # sed expressions match literal script text
M4="$(mk_mutant rehearsal-flag 's/state_migrate --rehearsal --backup-dir "$W\/backup"/state_migrate/')"
red "M4 rehearsal forget without --rehearsal" "$M4" chk_rehearsal_clean '^aws-s3-cp$' setup_rehearsal
green_mut "M4: the job's own no-new-backup assertion refuses it (reason=backup-written)" "$M4" chk_refuses_backup_write setup_rehearsal
# shellcheck disable=SC2016
M4B="$(mk_mutant rehearsal-flag-noassert 's/state_migrate --rehearsal --backup-dir "$W\/backup"/state_migrate/' 's/|| refuse backup-written/|| true/')"
RED_BASE="$M4" red "M4b: M4 plus the backups assertion removed" "$M4B" chk_refuses_backup_write '^rc:0$' setup_rehearsal
M5="$(mk_mutant no-override '/backend_override\.tf"$/d')"
red "M5 scratch root without the local-backend override" "$M5" chk_rehearsal_clean '^remote-serial$' setup_rehearsal
green_mut "M5: the job's own remote-serial assertion refuses it" "$M5" chk_refuses_serial setup_rehearsal
M5B="$(mk_mutant no-override-noassert '/backend_override\.tf"$/d' 's/|| refuse remote-serial-changed/|| true/')"
RED_BASE="$M5" red "M5b: M5 plus the serial assertion removed" "$M5B" chk_refuses_serial '^rc:0$' setup_rehearsal
M6="$(mk_mutant no-gate 's/|| refuse gate-refused "the plan did not reach/|| true "the plan did not reach/')"
red "M6 apply not conditioned on the gate" "$M6" chk_gate_blocks_apply '^apply-called$' setup_refuse_apply
# shellcheck disable=SC2016
M7="$(mk_mutant no-replace 's/ \${REPLACE_ARGS\[@\]+"\${REPLACE_ARGS\[@\]}"}//')"
red "M7 -replace args dropped" "$M7" chk_zone_rest_args '^argv-mismatch$' setup_zone_rest_apply
# shellcheck disable=SC2016
# shellcheck disable=SC2016
M9="$(mk_mutant inflight-exempt-drift 's/grep -qxF -- "$base" <<<"$exempt" && continue/[[ "$base" == apply-web-platform-infra.yml ]] \&\& continue/')"
red "M9 the in-flight check skips a gated workflow (exempt list not the predicate's)" "$M9" chk_inflight '^not-refused' setup_inflight
# Selector drift the argv-exact fakes now see (review J1, J2, J4).
# shellcheck disable=SC2016 # sed expression matches literal script text
J1="$(mk_mutant backup-prefix 's#--prefix "$CFAM_BACKUP_PREFIX"#--prefix "web-platform/nonexistent/"#')"
red "J1 the backup listing's prefix drifts from the state-forget's (the library's CFAM_BACKUP_PREFIX)" "$J1" chk_rehearsal_clean '^stub-refused$' setup_rehearsal
J2="$(mk_mutant doppler-config 's/-c prd_terraform --name-transformer/-c prd --name-transformer/g')"
red "J2 doppler run reads -c prd instead of prd_terraform" "$J2" chk_rehearsal_clean '^stub-refused$' setup_rehearsal
J4="$(mk_mutant live-statuses 's/pending requested)$/completed success)/')"
red "J4 the live-status list loses pending/requested" "$J4" chk_rehearsal_clean '^stub-refused$' setup_rehearsal
# shellcheck disable=SC2016 # sed expression matches literal script text
H1="$(mk_mutant r2-unpinned 's/^  cfam_r2_aws s3api list-objects-v2 /  aws --endpoint-url "$R2_ENDPOINT" s3api list-objects-v2 /')"
red "H1 the backup listing bypasses the shared R2 call and takes R2_ENDPOINT" "$H1" chk_r2_ignored '^stub-refused$' setup_r2_evil
H2="$(mk_mutant budget-unchecked 's/|| refuse bad-verify-budget/|| true/')"
red "H2 verify budget not validated (arithmetic injection runs)" "$H2" chk_budget '^(injected|not-refused)' setup_budget
H3="$(mk_mutant imports-seam 's/^  unset CFAM_IMPORTS_FILE$/  :/')"
# LAYERED since the gate library ignores a non-committed CFAM_IMPORTS_FILE itself (#12931 review):
# neutering the job's unset must leave the run clean, with the gate naming the override it dropped.
chk_imports_ignored() { chk_rehearsal_clean "$1" || return 1; grep -q 'ignoring CFAM_IMPORTS_FILE=' "$1/err.txt" || { WHY="no-gate-ignore-line"; return 1; }; }
green_mut "H3 CFAM_IMPORTS_FILE: the gate still ignores the override with the job's unset neutered" "$H3" chk_imports_ignored setup_imports_seam
H4="$(mk_mutant tflog-global 's/^  unset TF_LOG TF_LOG_PATH TF_LOG_CORE TF_LOG_PROVIDER$/  :/')"
red "H4 TF_LOG from the environment reaches terraform" "$H4" chk_rehearsal_clean '^tf-log-leak$' setup_tflog
H5="$(mk_mutant tflog-doppler 's/env -u TF_LOG -u TF_LOG_PATH -u TF_LOG_CORE -u TF_LOG_PROVIDER "\$@"/"$@"/g')"
red "H5 a Doppler-side TF_LOG* reaches terraform plan" "$H5" chk_rehearsal_clean '^tf-log-leak$' setup_tflog_doppler
H6="$(mk_mutant no-health '/bad+=" app-health"/d')"
red "H6 post-apply verify drops the app.soleur.ai/health probe" "$H6" chk_health '^rc:0$' setup_health
H7="$(mk_mutant raw-reason 's/summary "reason=$(reason_line)"/summary "reason=$REASON"/')"
red "H7 reason written to the summary unsanitized" "$H7" chk_reason '^(double-colon|newline-injected|no-reason-line)$' setup_reason
H8="$(mk_mutant backups-timeout 's/|| refuse backups-timeout/|| true/')"
red "H8 a listing timeout is not named" "$H8" chk_backups_timeout '^not-refused' setup_backups_timeout
H9="$(mk_mutant ids-timeout 's/|| refuse ids-timeout/|| true/')"
red "H9 a Doppler timeout is not named" "$H9" chk_ids_timeout '^not-refused' setup_ids_timeout
H10="$(mk_mutant runs-timeout 's/|| refuse runs-timeout/|| true/')"
red "H10 a gh timeout is not named" "$H10" chk_runs_timeout '^not-refused' setup_runs_timeout
D8A="$(mk_mutant r2-unchecked 's/|| refuse r2-account-not-old/|| true/')"
red "D8a R2 account check removed" "$D8A" chk_r2_old '^not-refused' setup_r2_new
D8B="$(mk_mutant token-unchecked 's/|| refuse token-not-new-zone/|| true/')"
red "D8b token preflight verdict ignored" "$D8B" chk_token_403 '^not-refused' setup_token_403
E1="$(mk_mutant no-entrypoint-gate 's/^  if ! entrypoint_gate; then$/  if false; then/')"
red "E1 entrypoint gate call deleted" "$E1" chk_entrypoint_refused '^(apply-called|not-refused)' setup_entry_apply
E2="$(mk_mutant entrypoint-seam 's/ -u PREAPPLY_ENTRYPOINT_FETCH//')"
red "E2 the gate's fetch seam reaches production" "$E2" chk_entrypoint_ran '^rc:1$' setup_entry_seam
# shellcheck disable=SC2016
R1="$(mk_mutant forget-ok-ignored 's/state_migrate || refuse state-migrate-failed/state_migrate \&\& refuse state-migrate-failed/')"
setup_redispatch() { new_case "redispatch-mut-$1" redirects-dns false; forgotten_state "$LAST_D/remote.tfstate"; printf 'GITHUB_WORKSPACE=%s\n' "$MIRROR" >"$LAST_D/env.extra"; }
chk_redispatch_apply() { chk_redispatch "$1" apply; }
red "R1 a removed=0 forget treated as a failure (re-dispatch deadlock)" "$R1" chk_redispatch_apply '^(rc:1|no-plan)$' setup_redispatch
M8="$(mk_mutant always-apply 's/if \[\[ "$REHEARSAL" == true \]\]; then run_rehearsal; else run_apply; fi/run_apply/')"
red "M8 rehearsal dispatch routed to the apply path" "$M8" chk_rehearsal_clean '^(apply-called|aws-s3-cp|remote-state-rm)$' setup_rehearsal

# --- Stub refusals ---------------------------------------------------------------
# Every PATH fake refuses an unmodeled argv into refused.log. A pristine run must never trip one:
# a drifted selector (bucket/prefix, Doppler config, status literal) shows up here, not as a pass.
r=0; bad=""
for d in "$SBX"/runs/*/; do
  [[ "$(cat "$d/script" 2>/dev/null)" == "$PRISTINE" ]] || continue
  if [[ -s "$d/refused.log" ]]; then r=1; bad+=" ${d%/}"; fi
done
verdict "$r" "no PATH fake refused an unmodeled call in any pristine run${bad:+ (refused in:${bad##*/})}"

# ---------------------------------------------------------------------------
# ANTI-VACUITY FLOOR: printf + exit 1, never this suite's own fail.
# ---------------------------------------------------------------------------
printf '\n'
EXPECTED_CASES=98
if [[ "$CASES" -ne "$EXPECTED_CASES" ]]; then
  printf '[VACUITY] %d case(s) ran, expected exactly %d (a case was skipped, deleted or added without bumping the floor)\n' "$CASES" "$EXPECTED_CASES" >&2
  exit 1
fi
if [[ "$((PASS + FAIL))" -ne "$CASES" ]]; then
  printf '[VACUITY] accounting identity broken: PASS+FAIL=%d != CASES=%d\n' "$((PASS + FAIL))" "$CASES" >&2
  exit 1
fi
printf 'cf-account-migrate-job: %d passed, %d failed (%d cases)\n' "$PASS" "$FAIL" "$CASES"
[[ "$FAIL" -eq 0 ]] || exit 1
