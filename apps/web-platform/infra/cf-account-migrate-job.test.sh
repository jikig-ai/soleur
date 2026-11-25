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
# there then reds this suite instead of agreeing with it.
OZ="5af02a2f394e9ba6e0ea23c381a26b67"
OA="4d5ba6f096b2686fbdd404167dd4e125"
grep -qx "CFAM_OLD_ZONE_ID=\"$OZ\"" "$REPO/tests/scripts/lib/cf-account-migrate-gate.sh" \
  && grep -qx "CFAM_OLD_ACCOUNT_ID=\"$OA\"" "$REPO/tests/scripts/lib/cf-account-migrate-gate.sh" \
  || { printf '[FATAL] OLD ids in the gate library differ from the legacy account literals\n' >&2; exit 1; }
SENTINEL="SENTINEL-SECRET-VALUE-DO-NOT-PRINT"
# The deploy service token the tunnel fixture's policy admits (not a secret: a token UUID).
DT="11111111-2222-4333-8444-555555555555"

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
# The Doppler WRITE token belongs to the one sync call: terraform must never inherit it.
if [[ -n "${DOPPLER_TOKEN_WRITE:-}" || "${DOPPLER_TOKEN:-}" == stub-write ]]; then
  printf 'WRITE-TOKEN-LEAK in terraform %s\n' "${1:-}" >>"$D/calls.log"
fi
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
    # tfout: what a hostile live value makes terraform print, on the plan and on the apply.
    printf 'Plan: stub\n'; if [[ -f "$D/tfout" ]]; then cat "$D/tfout"; fi; exit "$(mode plan)" ;;
  apply) shift; log "apply $*"; : >"$D/applied"; if [[ -f "$D/tfout" ]]; then cat "$D/tfout"; fi; exit "$(mode apply)" ;;
  output)
    [[ "$#" -eq 3 && "$2" == -raw ]] || { log "UNEXPECTED $*"; exit 64; }
    case "$3" in
      ci_ssh_access_service_token_client_id|ci_ssh_access_service_token_client_secret) ;;
      *) log "UNEXPECTED $*"; exit 64 ;;
    esac
    log "output $3"
    if [[ -f "$D/mode.tfoutput-empty" ]]; then exit 0; fi
    printf 'SENTINEL-SECRET-VALUE-DO-NOT-PRINT-%s' "$3" ;;
  *) log "UNEXPECTED $*"; exit 64 ;;
esac
STUB
# doppler accepts exactly `run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var --`,
# and the CI-SSH sync's stdin write and --plain read of its two keys, on the write token only.
cat >"$SBX/bin/doppler" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
D="${STUB_DIR:?}"
printf 'doppler %s\n' "${1:-}" >>"$D/calls.log"
if [[ "${1:-} ${2:-}" == "secrets set" || "${1:-} ${2:-}" == "secrets get" ]]; then
  no() { printf 'doppler %s\n' "$*" >>"$D/refused.log"; exit 64; }
  case "${3:-}" in CI_SSH_ACCESS_TOKEN_ID|CI_SSH_ACCESS_TOKEN_SECRET) ;; *) no "$@" ;; esac
  [[ "${DOPPLER_TOKEN:-}" == stub-write ]] || no "(not the write token)" "$@"
  if [[ "$2" == set ]]; then
    [[ $# -eq 9 && "$4 $5 $6 $7 $8 $9" == "--silent --no-interactive -p soleur -c prd_terraform" ]] || no "$@"
    v="$(cat)"
    if [[ -f "$D/mode.dopplerset" ]]; then exit 1; fi
    if [[ -f "$D/mode.dopplercorrupt" ]]; then v=corrupted; fi
    printf '%s' "$v" >"$D/dstore.$3"
    printf 'doppler-set %s\n' "$3" >>"$D/calls.log"
  else
    [[ $# -eq 8 && "$4 $5 $6 $7 $8" == "-p soleur -c prd_terraform --plain" ]] || no "$@"
    [[ -f "$D/dstore.$3" ]] || exit 1
    cat "$D/dstore.$3"; printf '\n'
  fi
  exit 0
fi
[[ $# -gt 9 && "$1 $2 $3 $4 $5 $6 $7 $8 $9" == "run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var --" ]] \
  || { printf 'doppler %s\n' "$*" >>"$D/refused.log"; exit 64; }
if [[ -f "$D/mode.doppler" ]]; then exit "$(cat "$D/mode.doppler")"; fi
# mode.doppler_after_apply: Doppler answers until the apply has run, then fails (the re-read's fetch).
if [[ -f "$D/mode.doppler_after_apply" && -f "$D/applied" ]]; then exit 1; fi
# mode.doppler_stall: the record read's `doppler run` hangs before its command starts.
if [[ -f "$D/mode.doppler_stall" && "$*" == *'/dns_records/'* ]]; then printf 'doppler-stall\n' >>"$D/calls.log"; exec sleep 40; fi
[[ "$*" != *'/dns_records/'* ]] || printf 'doppler-live-read\n' >>"$D/calls.log"
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
# mode.badtoken: the value the record read fetches (the preflight fetched a clean one).
if [[ -f "$D/mode.badtoken" && "$*" == *'/dns_records/'* ]]; then TF_VAR_cf_api_token="$(cat "$D/mode.badtoken")"; export TF_VAR_cf_api_token; fi
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
  # A record GET, answered from the planned `after` unless a rec* file overrides it. `when` is pre
  # or post the apply. reconce.<when>.<id>: one 500; reccode.<when>[.<id>]: that code;
  # recfilter.<when>.<id>: a jq filter over the response.
  if [[ "$path" == zones/*/dns_records/* ]]; then
    id="${path##*/}"; when=pre; [[ -f "$D/applied" ]] && when=post
    printf 'cf-record-get %s token=%s when=%s\n' "$id" "$name" "$when" >>"$D/calls.log"
    # Exactly the modeled GET: no proxy, no curlrc, a 5 s bound, the status line, the NEW zone.
    want=(--disable --noproxy '*' -sS --max-time 5 -w '\n%{http_code}' --config - "https://api.cloudflare.com/client/v4/zones/${STUB_NZ:?}/dns_records/$id")
    [[ "$#" -eq "${#want[@]}" && "$*" == "${want[*]}" ]] || { printf 'curl %s\n' "$*" >>"$D/refused.log"; exit 64; }
    if [[ -f "$D/reconce.$when.$id" ]]; then rm -f "$D/reconce.$when.$id"; printf '{"success":false}\n500'; exit 0; fi
    for c in "$D/reccode.$when.$id" "$D/reccode.$when"; do
      if [[ -f "$c" ]]; then printf '{"success":false}\n%s' "$(cat "$c")"; exit 0; fi
    done
    body="$(jq -c --arg id "$id" 'first(.resource_changes[] | select(.change.after.id? == $id) | .change.after)
      | {success: true, result: {id, zone_id, type, name: .hostname, content, ttl, proxied, priority, comment: null, tags, settings: {}}}' "$D/plan.json")"
    if [[ -f "$D/recfilter.$when.$id" ]]; then body="$(jq -c "$(cat "$D/recfilter.$when.$id")" <<<"$body")"; fi
    printf '%s\n200' "$body"
    exit 0
  fi
  if [[ "$nullout" -eq 1 ]]; then
    # D8 token preflight: -o /dev/null -w '%{http_code}'
    printf 'cf-api-probe %s token=%s\n' "$path" "$name" >>"$D/calls.log"
    # cfrc.<name>: curl itself fails (a transport fault) with that exit code; -w still prints 000.
    if [[ -f "$D/cfrc.$name" ]]; then printf '000'; exit "$(cat "$D/cfrc.$name")"; fi
    # cfpath.<path with / -> _>: that one probe answers this code, whichever token asked.
    if [[ -f "$D/cfpath.${path//\//_}" ]]; then cat "$D/cfpath.${path//\//_}"; exit 0; fi
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
# curl.rc: "<url> <exit code>" lines; that URL answers nothing (000, no header dump) and curl exits so.
if [[ -f "$D/curl.rc" ]]; then
  rc="$(awk -v u="$url" '$1 == u {print $2; exit}' "$D/curl.rc")"
  if [[ -n "$rc" ]]; then [[ "$dump" -eq 1 ]] || printf '000 '; exit "$rc"; fi
fi
# mode.flaky: a redirect still propagating: agents.html answers 404 on its first probe only
# (counted in flaky.n). A 526 is not flaky: the verify stops on it (mode.health).
if [[ -f "$D/mode.flaky" && "$url" == https://soleur.ai/pages/agents.html ]]; then
  n="$(cat "$D/flaky.n" 2>/dev/null || printf 0)"; printf '%s' "$((n + 1))" >"$D/flaky.n"
  if [[ "$n" -eq 0 ]]; then printf '404 '; else printf '301 https://soleur.ai/agents/'; fi
  exit 0
fi
if [[ -f "$D/mode.verify" ]]; then
  [[ "$dump" -eq 1 ]] && printf 'HTTP/2 200\r\n\r\n' || printf '500 '
  exit 0
fi
# mode.noindex: the raw header dump app.soleur.ai answers with (empty = a timeout: no status line).
if [[ "$dump" -eq 1 && -f "$D/mode.noindex" ]]; then cat "$D/mode.noindex"; exit 0; fi
if [[ "$dump" -eq 1 ]]; then printf 'HTTP/2 200\r\nx-robots-tag: noindex\r\n\r\n'; exit 0; fi
# mode.wrongdest: an empty file misdirects agents.html; otherwise it names the one URL to misdirect.
# mode.location: the Location the misdirected URL answers with (default https://soleur.ai/elsewhere/).
if [[ -f "$D/mode.wrongdest" ]]; then
  w="$(cat "$D/mode.wrongdest")"; [[ -n "$w" ]] || w=https://soleur.ai/pages/agents.html
  loc=https://soleur.ai/elsewhere/; [[ -f "$D/mode.location" ]] && loc="$(cat "$D/mode.location")"
  [[ "$url" == "$w" ]] && { printf '301 %s' "$loc"; exit 0; }
fi
case "$url" in
  https://app.soleur.ai/health) if [[ -f "$D/mode.health" ]]; then printf '526 '; else printf '200 '; fi ;;
  https://www.soleur.ai/) printf '301 https://soleur.ai/' ;;
  # mode.gptbot: bot_management blocks the allowlisted crawler (403).
  https://soleur.ai/) [[ "$ua" == *GPTBot* && ! -f "$D/mode.gptbot" ]] && printf '200 ' || printf '403 ' ;;
  https://soleur.ai/pages/agents.html) printf '301 https://soleur.ai/agents/' ;;
  https://soleur.ai/pages/legal/privacy-policy.html) printf '301 https://soleur.ai/legal/privacy-policy/' ;;
  https://soleur.ai/blog/2026-03-16-soleur-vs-anthropic-cowork/) printf '301 https://soleur.ai/blog/soleur-vs-anthropic-cowork/' ;;
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
# timeout: logs its argv, then runs the real binary, so the apply's bound is asserted on what ran.
REAL_TIMEOUT="$(command -v timeout)" || { printf '[FATAL] timeout is required\n' >&2; exit 2; }
export REAL_TIMEOUT
cat >"$SBX/bin/timeout" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${STUB_DIR:?}/timeout.log"
exec "${REAL_TIMEOUT:?}" "$@"
STUB
chmod +x "$SBX/bin/"*
# Fakes a case opts into through PATH in env.extra.
# grep: the job's import-normalize count fails with a real error (exit 2).
REAL_GREP="$(command -v grep)" || { printf '[FATAL] grep is required\n' >&2; exit 2; }
# od: the call numbered in <case>/od.fail fails, so the plan's or the apply's token cannot be made.
REAL_OD="$(command -v od)" || { printf '[FATAL] od is required\n' >&2; exit 2; }
export REAL_GREP REAL_OD
mkdir -p "$SBX/bin-grep" "$SBX/bin-od" || exit 2
cat >"$SBX/bin-grep/grep" <<'STUB'
#!/usr/bin/env bash
[[ "$*" != "-c ^cf_account_migrate_gate: import-normalize " ]] || exit 2
exec "${REAL_GREP:?}" "$@"
STUB
cat >"$SBX/bin-od/od" <<'STUB'
#!/usr/bin/env bash
n="$(cat "${STUB_DIR:?}/od.n" 2>/dev/null || printf 0)"; n=$((n + 1)); printf '%s' "$n" >"$STUB_DIR/od.n"
[[ "$n" != "$(cat "$STUB_DIR/od.fail")" ]] || exit 1
exec "${REAL_OD:?}" "$@"
STUB
chmod +x "$SBX/bin-grep/grep" "$SBX/bin-od/od"

# ---------------------------------------------------------------------------
# FIXTURES
# ---------------------------------------------------------------------------
# build_plan <phase> <out>: a plan that satisfies the gate for <phase>, derived from the gate's spec.
build_plan() {
  local spec lit
  spec="$(cf_account_migrate_phase_spec "$1")" || return 1
  lit="$(_cfam_import_literals "$1")" || return 1
  jq -n --argjson spec "$spec" --argjson lit "$lit" --arg s "$SENTINEL" --arg nz "$NZ" --arg na "$NA" --arg dt "$DT" '
    # An import-class member carries the id its committed literal ends in; a planned create has none.
    def ids($a): (if ($lit[$a] | type) == "string" then {id: ($lit[$a] | split("/") | last)} else {} end)
                 + (if ($a | test("^cloudflare_(list|pages_project|pages_domain|zero_trust_tunnel_cloudflared|zero_trust_tunnel_cloudflared_config|zero_trust_access_service_token|notification_policy)[.]")) or $a == "cloudflare_ruleset.bulk_redirects" then {account_id: $na}
                    elif ($a | startswith("cloudflare_")) then {zone_id: $nz} else {} end);
    # The Access content the gate grades in the tunnel phase, in the shape provider 4.52.7 plans it.
    def papp: "cloudflare_zero_trust_access_application";
    def ptok: "cloudflare_zero_trust_access_service_token";
    def ppol: "cloudflare_zero_trust_access_policy";
    def polrefs: {(ppol + ".deploy_service_token"): {app: (papp + ".deploy"), tok: ["local.deploy_service_token_ids"]},
                  (ppol + ".ci_ssh_service_token"): {app: (papp + ".ssh"), tok: [(ptok + ".ci_ssh.id"), (ptok + ".ci_ssh")]},
                  (ppol + ".registry_push_service_token"): {app: (papp + ".registry"), tok: [(ptok + ".registry_push.id"), (ptok + ".registry_push")]}};
    def apppin: {(papp + ".deploy"): {domain: "deploy.soleur.ai", type: "self_hosted", session_duration: "24h"},
                 (papp + ".ssh"): {domain: "ssh.soleur.ai", type: "self_hosted", session_duration: "15m"},
                 (papp + ".registry"): {domain: "registry.soleur.ai", type: "self_hosted", session_duration: "15m"}};
    def pol($a): if $a == (ppol + ".deploy_service_token") then {decision: "non_identity", include: [{service_token: [$dt]}]}
                 elif polrefs[$a] != null then {decision: "non_identity", include: [{}]}
                 elif apppin[$a] != null then apppin[$a]
                 else {} end;
    def unk($a): if $a == (ppol + ".deploy_service_token") then {include: [{service_token: [false]}]}
                 elif polrefs[$a] != null then {include: [{service_token: true}]}
                 elif apppin[$a] != null then {account_id: true}
                 else {} end;
    # Ruleset kind/phase, as the root declares them: the entrypoint gate builds its URLs from these.
    # A record carries the key set measured from a real plan (Terraform 1.10.5, provider 4.52.7),
    # with synthesized values: the job reads every record and compares it with this `after`.
    def rec($a; $l): ($a | split(".")[1]) as $n
      | {id: ($l | split("/")[1]), zone_id: $nz, name: $n, hostname: ($n + ".soleur.ai"), type: "TXT",
         content: ("synthetic-" + $n), value: null, ttl: 1, proxied: false, proxiable: false, priority: null,
         comment: "", tags: [], data: [], metadata: {}, created_on: "2026-11-19T00:00:00Z",
         modified_on: "2026-11-19T00:00:00Z", timeouts: null, allow_overwrite: false};
    def rs($a): {"cloudflare_ruleset.allowlist_ai_crawlers": {kind: "zone", phase: "http_request_firewall_custom"},
                 "cloudflare_ruleset.cache_shared_binaries": {kind: "zone", phase: "http_request_cache_settings"},
                 "cloudflare_ruleset.seo_config_settings": {kind: "zone", phase: "http_config_settings"},
                 "cloudflare_ruleset.seo_page_redirects": {kind: "zone", phase: "http_request_dynamic_redirect"},
                 "cloudflare_ruleset.seo_response_headers": {kind: "zone", phase: "http_response_headers_transform"},
                 "cloudflare_ruleset.bulk_redirects": {kind: "root", phase: "http_request_redirect"}}[$a] // {};
    {format_version: "1.2",
     configuration: {root_module: {resources: [polrefs | to_entries[] | {address: .key, expressions: {
       application_id: {references: [(.value.app + ".id"), .value.app]},
       include: [{service_token: {references: .value.tok}}]}}]}},
     resource_changes: [
      $spec | to_entries[] | .key as $a | .value as $c
      | ({address: $a, mode: "managed", type: ($a | split(".")[0]), change: (
            # The gate fixes the planned value of the runtime zone-id secret and of the Pages
            # account-id secret (its expected-values table): those carry it exactly.
            if $c == "create" then {actions: ["create"], before: null,
                after: ((if $a == "doppler_secret.cf_zone_id_prd" then {project: "soleur", config: "prd", name: "CF_ZONE_ID", value: $nz} else {value: $s} end) + ids($a) + rs($a) + pol($a)),
                after_unknown: unk($a)}
            elif $c == "import" and ($a | startswith("cloudflare_record.")) then
              {actions: ["no-op"], importing: {id: $lit[$a]}, before: rec($a; $lit[$a]), after: rec($a; $lit[$a]), after_unknown: {}}
            elif $c == "import" then {actions: ["no-op"], importing: {id: $lit[$a]}, before: ids($a), after: ids($a)}
            elif $c == "mutable" then {actions: ["update"], before: {},
                after: (if $a == "github_actions_secret.cloudflare_account_id_pages"
                        then {repository: "soleur", secret_name: "CLOUDFLARE_ACCOUNT_ID_PAGES", plaintext_value: $na}
                        elif $a == "doppler_secret.registry_push_access_token_id"
                        then {project: "soleur", config: "prd", name: "REGISTRY_PUSH_ACCESS_TOKEN_ID", visibility: "masked", value: $s}
                        elif $a == "doppler_secret.registry_push_access_token_secret"
                        then {project: "soleur", config: "prd", name: "REGISTRY_PUSH_ACCESS_TOKEN_SECRET", visibility: "masked", value: $s}
                        else {repository: "soleur", secret_name: "CLOUDFLARE_API_TOKEN_PAGES", plaintext_value: $s} end)}
            elif $a == "random_id.tunnel_secret" then {actions: ["delete", "create"], before: {id: "rnd-tunnel-id"}, after: {byte_length: 32}}
            else {actions: ["delete", "create"], before: {id: "tok-id-1"}, after: {project: "soleur", config: "prd", name: "CF_API_TOKEN_DNS_EDIT", visibility: "masked", value: $s}} end)}
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
      r("doppler_secret.cf_api_token_dns_edit"; "doppler_secret"; {id: "tok-id-1", value: $s}),
      r("random_id.tunnel_secret"; "random_id"; {id: "rnd-tunnel-id"})
    ]}}}}' >"$1"
}

# The gated set, derived here independently of the job: every workflow file that uses the
# infra-credentials action (bare or quoted), plus every workflow whose job calls a local reusable
# workflow in the set (to a fixed point: a run is listed under the CALLER's name), minus the
# predicate's CFAM_EXEMPT_WORKFLOWS (CTO D1). A literal sample stops a shrunk derivation from
# shrinking the suite with it.
EXEMPT_TXT="$(bash -c 'source "$1"; printf "%s\n" "${CFAM_EXEMPT_WORKFLOWS[@]}"' _ "$HERE/scripts/cf-account-migration-complete.sh")" \
  || { printf '[FATAL] cannot read the predicate exempt list\n' >&2; exit 2; }
derive_gated() { # <workflows dir> <out file>
  local f reach callees n=-1 q="[\"']?"
  reach="$(awk -v q="$q" 'BEGIN { re = "^[ \t]*(-[ \t]+)?uses:[ \t]*" q "[.]/[.]github/actions/infra-credentials/?" q "[ \t]*(#.*)?$" }
    $0 ~ re { n = FILENAME; sub(/.*\//, "", n); print n }' "$1"/*.yml "$1"/*.yaml 2>/dev/null | sort -u)"
  while [[ "$(grep -c . <<<"$reach")" -ne "$n" ]]; do
    n="$(grep -c . <<<"$reach")"
    for f in "$1"/*.yml "$1"/*.yaml; do
      [[ -f "$f" ]] || continue
      callees="$(grep -oE "^[[:space:]]*uses:[[:space:]]*${q}\./\.github/workflows/[A-Za-z0-9._-]+\.ya?ml" "$f" | sed 's#.*/##')"
      [[ -n "$callees" ]] || continue
      if grep -qxF -f <(printf '%s\n' "$reach") <<<"$callees"; then
        reach="$(printf '%s\n%s\n' "$reach" "${f##*/}" | grep . | sort -u)"
      fi
    done
  done
  grep -vxF -f <(printf '%s\n' "$EXEMPT_TXT") <<<"$reach" >"$2"
}
GATED_FILE="$SBX/gated.txt"
derive_gated "$REPO/.github/workflows" "$GATED_FILE"
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
    PATH="$SBX/bin:$PATH" STUB_DIR="$d" STUB_GATED="$GATED_FILE" STUB_NZ="$NZ" \
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
refused_for() { [[ "$(rc_of "$1")" == 1 ]] && grep -qE "verdict=refuse reason=$2( |\$)" "$1/out.txt"; }

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
  chk_forget_committed "$1" gate-refused
}
chk_forget_committed() { # <dir> <reason>: a redirects-dns apply refusal after the forget names it as a field
  chk_refuse_fields "$1" "$2" forget=committed || { WHY="no-forget-${WHY#no-}"; return 1; }
}
chk_refuse_fields() { # <dir> <reason> <fields>: the redirects-dns apply refusal line and summary carry exactly <fields>
  grep -qxF -- "cf-account-migrate phase=redirects-dns verdict=refuse reason=$2 $3" "$1/out.txt" || { WHY="no-field"; return 1; }
  grep -qxF -- "- cf-account-migrate phase=redirects-dns rehearsal=false verdict=refuse reason=$2 $3" "$1/summary.md" || { WHY="no-summary"; return 1; }
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
chk_dest() { # a legacy path that 301s to the wrong page fails the verify, naming what came back
  chk_dest_for "$1" 'https://soleur.ai/pages/agents.html'
}
chk_dest_for() { # <dir> <url>: that URL alone fails, with its observed result, in the line, the
  # annotation and the summary (which also records that the apply landed)
  local want="$2=>301+https://soleur.ai/elsewhere/"
  refused_for "$1" verify-failed || { WHY="rc:$(rc_of "$1")"; return 1; }
  grep -qxF -- "cf-account-migrate verify=redirects-dns verdict=fail failing=${want}" "$1/out.txt" || { WHY="no-dest:$2"; return 1; }
  grep -qF -- "::error title=cf-account-migrate::applied, but the redirect/noindex/crawler/app-health probes did not all pass: ${want}." "$1/out.txt" || { WHY="no-annotation"; return 1; }
  grep -qxF -- "- cf-account-migrate phase=redirects-dns rehearsal=false verdict=refuse reason=verify-failed applied=true forget=committed failing=${want}" "$1/summary.md" || { WHY="no-applied-summary"; return 1; }
}
chk_hostile_location() { # a network Location carrying %0A and :: stays inside ONE annotation
  refused_for "$1" verify-failed || { WHY="rc:$(rc_of "$1")"; return 1; }
  grep -qF -- '::error title=cf-account-migrate::applied, but the redirect/noindex/crawler/app-health probes did not all pass: https://soleur.ai/pages/agents.html=>301+https://soleur.ai/x%250A:warning:y.' "$1/out.txt" || { WHY="not-encoded"; return 1; }
  if grep -qF -- '::warning' "$1/out.txt" "$1/summary.md"; then WHY="warning-opener"; return 1; fi
}
chk_deadline() { # the deadline ends the verify after ONE pass (of TRIES=3), with its verdict line
  refused_for "$1" verify-failed || { WHY="rc:$(rc_of "$1")"; return 1; }
  grep -q "^cf-account-migrate verify=$(cat "$1/phase") verdict=fail failing=" "$1/out.txt" || { WHY="no-verdict-line"; return 1; }
  [[ "$(grep -c '^curl https://app.soleur.ai/health$' "$1/calls.log")" -eq 1 ]] || { WHY="passes:$(grep -c '^curl https://app.soleur.ai/health$' "$1/calls.log")"; return 1; }
}
chk_retry() { # pass 1 fails, pass 2 passes: verdict ok after exactly two passes, applied, rc 0
  [[ "$(rc_of "$1")" == 0 ]] || { WHY="rc:$(rc_of "$1")"; return 1; }
  grep -qx 'cf-account-migrate verify=redirects-dns verdict=ok' "$1/out.txt" || { WHY="no-ok"; return 1; }
  [[ "$(grep -c '^curl https://app.soleur.ai/health$' "$1/calls.log")" -eq 2 ]] || { WHY="passes:$(grep -c '^curl https://app.soleur.ai/health$' "$1/calls.log")"; return 1; }
}
chk_applyfail_health() { # a failed apply is still probed: the refusal carries forget=committed and the 526
  refused_for "$1" apply-failed || { WHY="rc:$(rc_of "$1")"; return 1; }
  grep -q '^terraform\[remote\] apply' "$1/calls.log" || { WHY="no-apply-call"; return 1; }
  grep -qx 'cf-account-migrate phase=redirects-dns mode=apply applying=true' "$1/out.txt" || { WHY="no-applying-line"; return 1; }
  if grep -q 'mode=apply applied=true' "$1/out.txt"; then WHY="applied-line"; return 1; fi
  chk_refuse_fields "$1" apply-failed 'forget=committed failing=app-health=>526' || return 1
}
chk_curl_rc() { # curl's own exit code reaches the failing item: +e=<rc>
  refused_for "$1" verify-failed || { WHY="rc:$(rc_of "$1")"; return 1; }
  grep -qxF -- 'cf-account-migrate verify=redirects-dns verdict=fail failing=app-noindex=>000+hdr=absent+e=7 app-health=>000+e=28' "$1/out.txt" || { WHY="no-rc-item"; return 1; }
}
chk_reason_bidi() { # bidi/format characters in the reason become spaces in the summary line
  grep -qxF -- '- cf-account-migrate phase=redirects-dns rehearsal=true reason=a b c d e f g h' "$1/summary.md" || { WHY="not-stripped"; return 1; }
}
chk_obs_ascii() { # a Location with a bidi override and a non-ASCII letter reads as printable ASCII only
  refused_for "$1" verify-failed || { WHY="rc:$(rc_of "$1")"; return 1; }
  grep -qxF -- 'cf-account-migrate verify=redirects-dns verdict=fail failing=https://soleur.ai/pages/agents.html=>301+https://soleur.ai/x+y+z' "$1/out.txt" || { WHY="not-ascii"; return 1; }
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
chk_entrypoint_refused_apply() { chk_entrypoint_refused "$1" || return 1; chk_forget_committed "$1" entrypoint-gate-refused; }
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
# shellcheck disable=SC2016 # injected text, expanded only if the job fails to validate it
setup_budget_deadline() { new_case "budgetd-$1" redirects-dns false; printf 'CFAM_VERIFY_DEADLINE=P[$(touch %s/pwned)]\n' "$LAST_D" >"$LAST_D/env.extra"; }
setup_hostile_loc() { new_case "hostloc-$1" redirects-dns false; : >"$LAST_D/mode.wrongdest"; printf 'https://soleur.ai/x%%0A::warning::y' >"$LAST_D/mode.location"; }
# Three failing passes allowed, no pause, deadline 0: the deadline ends the verify after ONE pass.
# The pass count is the observable (passes:1 pristine), so no wall bound is needed.
setup_deadline() {
  new_case "deadline-$1" redirects-dns false; : >"$LAST_D/mode.verify"
  printf 'CFAM_VERIFY_TRIES=3\nCFAM_VERIFY_SLEEP=0\nCFAM_VERIFY_DEADLINE=0\n' >"$LAST_D/env.extra"
}
# The clock placed past the cap (bash imports SECONDS from the environment): with DEADLINE=600 the
# cap alone (1500 - 0 - 105 = 1395 s after the script start) ends the verify after ONE pass. On
# zone-rest, whose apply has no start floor: a redirects-dns apply refuses this late.
setup_cap() {
  new_case "cap-$1" zone-rest false; remote_state "$LAST_D/remote.tfstate" "$NZ" "$NA"; : >"$LAST_D/mode.verify"
  printf 'CFAM_VERIFY_TRIES=3\nCFAM_VERIFY_SLEEP=0\nCFAM_VERIFY_DEADLINE=600\nSECONDS=1400\n' >"$LAST_D/env.extra"
}
setup_retry() {
  new_case "retry-$1" redirects-dns false; : >"$LAST_D/mode.flaky"
  printf 'CFAM_VERIFY_TRIES=3\nCFAM_VERIFY_SLEEP=0\nCFAM_VERIFY_DEADLINE=600\n' >"$LAST_D/env.extra"
}
setup_applyfail_health() { new_case "afh-$1" redirects-dns false; printf '1' >"$LAST_D/mode.apply"; : >"$LAST_D/mode.health"; }
setup_curl_rc() { new_case "curlrc-$1" redirects-dns false; printf 'https://app.soleur.ai/ 7\nhttps://app.soleur.ai/health 28\n' >"$LAST_D/curl.rc"; }
setup_reason_bidi() { new_case "rbidi-$1" redirects-dns true; printf 'a\xe2\x80\xaeb\xe2\x81\xa6c\xef\xbb\xbfd\xe2\x80\x8ee\xe2\x80\x8bf\xc2\xadg\xf3\xa0\x80\x81h' >"$LAST_D/reason"; }
setup_obs_ascii() { new_case "obsascii-$1" redirects-dns false; : >"$LAST_D/mode.wrongdest"; printf 'https://soleur.ai/x\xe2\x80\xaey\xc3\xa9z' >"$LAST_D/mode.location"; }
setup_imports_seam() { new_case "impseam-$1" redirects-dns true; printf 'CFAM_IMPORTS_FILE=%s/no-such-imports.tf\n' "$LAST_D" >"$LAST_D/env.extra"; }
setup_tflog() {
  new_case "tflog-$1" redirects-dns true
  printf 'TF_LOG=DEBUG\nTF_LOG_PATH=%s/tf.log\n' "$LAST_D" >"$LAST_D/env.extra"
  printf 'TF_LOG_PROVIDER=TRACE\n' >"$LAST_D/doppler.inject"
}
setup_tflog_doppler() { new_case "tflogd-$1" redirects-dns true; printf 'TF_LOG_PROVIDER=TRACE\n' >"$LAST_D/doppler.inject"; }
setup_health() { new_case "health-$1" redirects-dns false; : >"$LAST_D/mode.health"; }
setup_wrongdest() { new_case "wrongdest-$1" redirects-dns false; : >"$LAST_D/mode.wrongdest"; }
setup_wrongdest_cowork() { new_case "wrongdestc-$1" redirects-dns false; printf 'https://soleur.ai/blog/2026-03-16-soleur-vs-anthropic-cowork/' >"$LAST_D/mode.wrongdest"; }
setup_reason() { new_case "reason-$1" redirects-dns true; printf 're-run after a 5xx\n::error title=x::pwned\x07 `code`\npwned2' >"$LAST_D/reason"; }
setup_backups_timeout() { new_case "bkto-$1" redirects-dns true; printf '124' >"$LAST_D/mode.aws"; }
setup_ids_timeout() { new_case "idsto-$1" redirects-dns false; printf '124' >"$LAST_D/mode.doppler"; }
setup_runs_timeout() { new_case "runsto-$1" redirects-dns false; printf '124' >"$LAST_D/mode.gh"; }
# D15: curl itself fails on one token probe (28, a timeout): a network fault, not a token verdict.
setup_token_unreach() { new_case "tokunr-$1" redirects-dns false; printf '28' >"$LAST_D/cfrc.cf_api_token_rulesets"; }
chk_token_unreach() { chk_preflight_refused "$1" token-unreachable || return 1
  grep -qx 'cf-account-migrate preflight=token name=cf_api_token_rulesets http=000 e=28' "$1/out.txt" || { WHY="no-e-line"; return 1; }
}
# fr4 F2: the rulesets token probe answers 429: the API gave no verdict.
setup_token_429() { new_case "tok429-$1" redirects-dns false; printf '429' >"$LAST_D/cfcode.cf_api_token_rulesets"; }
chk_token_429() { chk_preflight_refused "$1" token-unreachable; }
# D16: Doppler holds the NEW zone id in upper case; variables.tf's shape check is lowercase-only.
setup_upper_zone() { new_case "upzone-$1" redirects-dns false; printf '%s\n%s\n%s\n' "${NZ^^}" "$NA" "$OA" >"$LAST_D/ids"; }
# D12: app-health 526 on every pass, three passes allowed: the verify stops after the first.
setup_health_stuck() {
  new_case "hstuck-$1" redirects-dns false; : >"$LAST_D/mode.health"
  printf 'CFAM_VERIFY_TRIES=3\nCFAM_VERIFY_SLEEP=0\nCFAM_VERIFY_DEADLINE=600\n' >"$LAST_D/env.extra"
}
chk_health_stuck() {
  chk_health "$1" || return 1
  grep -qx 'cf-account-migrate verify=redirects-dns pass=1 app-health=526 retry=stopped' "$1/out.txt" || { WHY="no-stop-line"; return 1; }
  chk_passes "$1" 1
}
# Every probe 500 (app-health a 500, not a 525/526), three passes allowed: all three run.
setup_health_500() {
  new_case "h500-$1" redirects-dns false; : >"$LAST_D/mode.verify"
  printf 'CFAM_VERIFY_TRIES=3\nCFAM_VERIFY_SLEEP=0\nCFAM_VERIFY_DEADLINE=600\n' >"$LAST_D/env.extra"
}
chk_health_500() { refused_for "$1" verify-failed || { WHY="rc:$(rc_of "$1")"; return 1; }; chk_passes "$1" 3; }
chk_passes() { # <dir> <n>: exactly <n> verify passes (one app-health probe each)
  local n; n="$(grep -c '^curl https://app.soleur.ai/health$' "$1/calls.log")"
  [[ "$n" -eq "$2" ]] || { WHY="passes:$n"; return 1; }
}
# D8: a fix-forward re-dispatch whose plan updates a rule already in state on the NEW zone
# (cloudflare_ruleset.seo_config_settings): the gate admits it as an in-state update.
ISU_ADDR=cloudflare_ruleset.seo_config_settings
isu_case() { # <label> <rehearsal> [<expected_in_state_updates>]
  new_case "isu-$1" redirects-dns "$2"
  remote_state "$LAST_D/remote.tfstate" "$NZ" "$NA"
  jq --arg nz "$NZ" --arg a "$ISU_ADDR" '.show.values.root_module.resources += [{address: $a, mode: "managed", type: "cloudflare_ruleset", name: "n", values: {zone_id: $nz}}]' \
    "$LAST_D/remote.tfstate" >"$LAST_D/s" && mv "$LAST_D/s" "$LAST_D/remote.tfstate"
  jq --arg a "$ISU_ADDR" '(.resource_changes[] | select(.address == $a) | .change) |= (.actions = ["update"] | .before = (.after | del(.value)))' \
    "$LAST_D/plan.json" >"$LAST_D/p" && mv "$LAST_D/p" "$LAST_D/plan.json"
  if [[ -n "${3+set}" ]]; then printf 'CFAM_EXPECTED_IN_STATE_UPDATES=%s\n' "$3" >"$LAST_D/env.extra"; fi
}
setup_isu_unexpected() { isu_case "unexp-$1" false; }
chk_isu_unexpected() { # refused before applying=true, both sets printed, forget=committed
  if grep -q '^terraform\[[a-z]*\] apply' "$1/calls.log"; then WHY="apply-called"; return 1; fi
  if grep -q 'applying=true' "$1/out.txt"; then WHY="applying-line"; return 1; fi
  refused_for "$1" in-state-updates-unexpected || { WHY="not-refused:rc=$(rc_of "$1")"; return 1; }
  grep -qx "cf-account-migrate in-state-updates admitted=$ISU_ADDR expected=" "$1/out.txt" || { WHY="no-sets-line"; return 1; }
  chk_forget_committed "$1" in-state-updates-unexpected
}
setup_isu_bad() { new_case "isubad-$1" redirects-dns false; printf 'CFAM_EXPECTED_IN_STATE_UPDATES=%s;touch\n' "$ISU_ADDR" >"$LAST_D/env.extra"; }
chk_isu_bad() { chk_refused_early "$1" bad-expected-in-state-updates; }
# D19: a workspace whose .github/workflows holds the real files plus a three-deep local reusable
# chain: wf-top calls wf-mid (no loader), which calls wf-callee (a QUOTED loader line).
MIRROR_WF="$SBX/mirror-wf"
mkdir -p "$MIRROR_WF/.github/workflows" || exit 2
ln -s "$REPO/tests" "$MIRROR_WF/tests"; ln -s "$REPO/apps" "$MIRROR_WF/apps"
for f in "$REPO"/.github/workflows/*.yml "$REPO"/.github/workflows/*.yaml; do [[ -f "$f" ]] && ln -s "$f" "$MIRROR_WF/.github/workflows/${f##*/}"; done
printf 'on: workflow_call\njobs:\n  a:\n    runs-on: ubuntu-24.04\n    steps:\n      - uses: "./.github/actions/infra-credentials"\n' >"$MIRROR_WF/.github/workflows/cfam-wf-callee.yml"
printf 'on: workflow_call\njobs:\n  b:\n    uses: ./.github/workflows/cfam-wf-callee.yml\n' >"$MIRROR_WF/.github/workflows/cfam-wf-mid.yml"
printf 'on: workflow_dispatch\njobs:\n  c:\n    uses: '"'"'./.github/workflows/cfam-wf-mid.yml'"'"' # reusable\n' >"$MIRROR_WF/.github/workflows/cfam-wf-top.yml"
GATED_WF="$SBX/gated-wf.txt"
derive_gated "$MIRROR_WF/.github/workflows" "$GATED_WF"
setup_inflight_caller() {
  new_case "inflcaller-$1" redirects-dns true; printf '1\n' >"$LAST_D/gh.cfam-wf-top.yml.in_progress"
  printf 'GITHUB_WORKSPACE=%s\nSTUB_GATED=%s\n' "$MIRROR_WF" "$GATED_WF" >"$LAST_D/env.extra"
}
# D31: the forget fails and its kept output is unreadable (a directory where the file was).
setup_forget_unreadable() {
  new_case "forgetunr-$1" redirects-dns false; printf 'GITHUB_WORKSPACE=%s\n' "$MIRROR" >"$LAST_D/env.extra"
  printf 'cf-state-migrate verdict=abort reason=state-rm-failed\n' >"$LAST_D/mode.forget"; : >"$LAST_D/mode.forget-unreadable"
}
chk_forget_unreadable() {
  refused_for "$1" state-migrate-failed || { WHY="rc:$(rc_of "$1")"; return 1; }
  grep -qx 'state-migrate-stub made-output-unreadable' "$1/calls.log" || { WHY="seam-missed"; return 1; }
  chk_refuse_fields "$1" state-migrate-failed forget=committed
}

printf 'cf-account-migrate-job: battery\n'
cmp -s "$SUT" "$PRISTINE"; verdict "$?" "pristine copy equals the script under test"
for p in redirects-dns zone-rest tunnel; do
  remote_state "$SBX/fx.tfstate" "$NZ" "$NA" && jq .show "$SBX/fx.tfstate" >"$SBX/fx-state.json" \
    && build_plan "$p" "$SBX/fx.json" && cf_account_migrate_gate "$p" "$SBX/fx.json" "$SBX/fx-state.json" >/dev/null
  verdict "$?" "fixture: the derived $p plan passes the real gate (else every PASS row is void)"
done

# --- Input refusals -----------------------------------------------------------
printf '\n[inputs] refused before any infra call\n'
setup_bad_confirm c; run_job "$LAST_D" "$PRISTINE"; WHY=""
chk_bad_confirm "$LAST_D"; verdict "$?" "confirm for another phase -> reason=bad-confirm, no terraform/doppler/aws call ($WHY)"
new_case unknown redirects-dns true
printf 'tunnels' >"$LAST_D/phase"; printf 'MIGRATE-CF-tunnels' >"$LAST_D/confirm"; run_job "$LAST_D" "$PRISTINE"; WHY=""
chk_refused_early "$LAST_D" unknown-phase; verdict "$?" "a phase the gate does not list -> reason=unknown-phase ($WHY)"
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
r=1; [[ "$(grep -c . "$GATED_WF")" -eq $((N_GATED + 3)) ]] && grep -qxF cfam-wf-top.yml "$GATED_WF" \
  && grep -qxF cfam-wf-mid.yml "$GATED_WF" && grep -qxF cfam-wf-callee.yml "$GATED_WF" && r=0
verdict "$r" "suite derivation: a quoted loader line and a two-deep local reusable chain add callee, mid and top"
setup_inflight_caller x; run_job "$LAST_D" "$PRISTINE"; WHY=""
r=1; chk_inflight "$LAST_D" && grep -qx 'cf-account-migrate inflight workflow=cfam-wf-top.yml status=in_progress count=1' "$LAST_D/out.txt" && r=0
verdict "$r" "a run of a workflow that reaches the loader only through job-level uses: of a reusable chain -> reason=run-in-flight ($WHY)"
new_case inflight-caller-all redirects-dns true; printf 'GITHUB_WORKSPACE=%s\nSTUB_GATED=%s\n' "$MIRROR_WF" "$GATED_WF" >"$LAST_D/env.extra"
run_job "$LAST_D" "$PRISTINE"
r=1; [[ ! -s "$LAST_D/refused.log" ]] && grep -qx "cf-account-migrate inflight=none workflows=$((N_GATED + 3))" "$LAST_D/out.txt" && r=0
verdict "$r" "the job's gated set over that workspace equals the suite's derivation (N+3, every gh call modeled)"

# --- Id preflight ---------------------------------------------------------------
printf '\n[ids] Doppler must resolve the NEW ids before anything is written\n'
setup_old_ids x; run_job "$LAST_D" "$PRISTINE"; WHY=""
chk_ids_refused "$LAST_D"; verdict "$?" "old zone id in Doppler -> reason=zone-id-not-new before init/forget ($WHY)"
# D34: the loader's soleur-infra-privileged export wins under --preserve-env, so the refusal names both sources.
DOPPLER_SRC_TXT='The value checked is the effective one: soleur/prd_terraform, unless the soleur-infra-privileged project (exported by the credential loader) carries the same name, whose value wins under doppler run --preserve-env. Check both before re-flipping.'
r=1; grep -qF -- "::error title=cf-account-migrate::cf_zone_id does not resolve to the Soleur-account zone (Doppler still holds the OLD id, or none). Do the runbook Phase 2 flip first. $DOPPLER_SRC_TXT Nothing was written." "$LAST_D/out.txt" && r=0
verdict "$r" "zone-id-not-new names both Doppler sources (prd_terraform, and the loader's infra-privileged export that wins)"
new_case oldacct redirects-dns false; printf '%s\n%s\n' "$NZ" "$OA" >"$LAST_D/ids"; run_job "$LAST_D" "$PRISTINE"
r=1; refused_for "$LAST_D" account-id-not-new && ! grep -q '^terraform' "$LAST_D/calls.log" && r=0
verdict "$r" "old account id in Doppler -> reason=account-id-not-new before any terraform call"
r=1; ! grep -q "$OA" "$LAST_D/out.txt" "$LAST_D/err.txt" && r=0
verdict "$r" "the id preflight does not print the resolved ids"
setup_upper_zone x; run_job "$LAST_D" "$PRISTINE"; WHY=""
chk_ids_refused "$LAST_D"; verdict "$?" "the NEW zone id in upper case -> reason=zone-id-not-new before init/forget (no case fold; variables.tf is lowercase-only) ($WHY)"
new_case upacct redirects-dns false; printf '%s\n%s\n%s\n' "$NZ" "${NA^^}" "$OA" >"$LAST_D/ids"; run_job "$LAST_D" "$PRISTINE"
r=1; refused_for "$LAST_D" account-id-not-new && ! grep -q '^terraform' "$LAST_D/calls.log" && r=0
verdict "$r" "the NEW account id in upper case -> reason=account-id-not-new before any terraform call"

# --- Token / R2 preflight (CTO D8) ------------------------------------------------------
printf '\n[preflight] R2 stays legacy; every phase token reads the NEW zone/account\n'
setup_token_403 x; run_job "$LAST_D" "$PRISTINE"; WHY=""
chk_token_403 "$LAST_D"; verdict "$?" "rulesets token 403 on the new zone -> reason=token-not-new-zone, only the code printed, no terraform call ($WHY)"
r=1; grep -qF -- "swap or re-mint it (runbook Phase 0/2). $DOPPLER_SRC_TXT Nothing was written." "$LAST_D/out.txt" && r=0
verdict "$r" "token-not-new-zone names both Doppler sources before a swap or re-mint"
setup_r2_new x; run_job "$LAST_D" "$PRISTINE"; WHY=""
chk_r2_old "$LAST_D"; verdict "$?" "cf_r2_account_id = the NEW account -> reason=r2-account-not-old, no terraform call ($WHY)"
setup_token_unreach x; run_job "$LAST_D" "$PRISTINE"; WHY=""
chk_token_unreach "$LAST_D"; verdict "$?" "curl times out (28) on the rulesets token probe -> reason=token-unreachable (retry), http=000 e=28 printed, no terraform call ($WHY)"
new_case tok-mixed redirects-dns false; printf '28' >"$LAST_D/cfrc.cf_api_token_rulesets"; printf '403' >"$LAST_D/cfcode.cf_api_token"; run_job "$LAST_D" "$PRISTINE"; WHY=""
chk_preflight_refused "$LAST_D" token-not-new-zone; verdict "$?" "one token 403 and another unreachable -> reason=token-not-new-zone (a definite token verdict wins) ($WHY)"
# fr4 F2: a 429 or a 5xx is the API giving no verdict, not a bad token: retry, never re-mint.
for c in 429 503; do
  new_case "tok-$c" redirects-dns false; printf '%s' "$c" >"$LAST_D/cfcode.cf_api_token_rulesets"; run_job "$LAST_D" "$PRISTINE"; WHY=""
  r=1; chk_preflight_refused "$LAST_D" token-unreachable && grep -qx "cf-account-migrate preflight=token name=cf_api_token_rulesets http=$c" "$LAST_D/out.txt" && r=0
  verdict "$r" "rulesets token probe answers $c -> reason=token-unreachable (no verdict), never token-not-new-zone"
done
new_case tok-paths redirects-dns true; run_job "$LAST_D" "$PRISTINE"
r=1
diff <(sed -n 's/^cf-api-probe \(.*\)$/\1/p' "$LAST_D/calls.log" | sort) <(printf '%s\n' \
  "zones/$NZ/dns_records?per_page=1 token=cf_api_token" "zones/$NZ/rulesets token=cf_api_token_rulesets" \
  "accounts/$NA/pages/projects token=cf_api_token_pages" \
  "accounts/$NA/cfd_tunnel?per_page=1 token=cf_api_token" "zones/$NZ/access/apps?per_page=1 token=cf_api_token" \
  "accounts/$NA/access/service_tokens?per_page=1 token=cf_api_token" "accounts/$NA/alerting/v3/policies token=cf_api_token" | sort) >/dev/null && r=0
verdict "$r" "redirects-dns probes its three tokens and cf_api_token's four tunnel scopes, each on the new zone/account"
r=1; [[ "$(cat "$LAST_D/rc")" == 0 ]] && ! grep -q 'tok-' "$LAST_D/curl-argv.log" && r=0
verdict "$r" "no token value reaches curl's argv (stdin config only)"
new_case tok-zrest zone-rest true; remote_state "$LAST_D/remote.tfstate" "$NZ" "$NA"; run_job "$LAST_D" "$PRISTINE"
r=1
diff <(sed -n 's/^cf-api-probe \(.*\)$/\1/p' "$LAST_D/calls.log" | sort) <(printf '%s\n' \
  "zones/$NZ/settings token=cf_api_token_zone_settings" "zones/$NZ/bot_management token=cf_api_token_bot_management" | sort) >/dev/null && r=0
verdict "$r" "zone-rest probes exactly its two tokens (zone_settings, bot_management)"
r=1; [[ "$(cf_account_migrate_phase_tokens redirects-dns | tr '\n' ' ')" == "cf_api_token cf_api_token_rulesets cf_api_token_pages " \
  && "$(cf_account_migrate_phase_tokens zone-rest | tr '\n' ' ')" == "cf_api_token_zone_settings cf_api_token_bot_management " \
  && "$(cf_account_migrate_phase_tokens tunnel | tr '\n' ' ')" == "cf_api_token " ]] \
  && ! cf_account_migrate_phase_tokens tunnels >/dev/null 2>&1 && r=0
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
r=1; refused_for "$LAST_D" gate-refused && grep -q 'Guard 4' "$LAST_D/out.txt" && ! grep -q '\] apply' "$LAST_D/calls.log" \
  && chk_forget_committed "$LAST_D" gate-refused && r=0
verdict "$r" "plan failure (e.g. Guard 4 validation) surfaces an ::error:: naming Guard 4, no apply, forget=committed"
# D33: zone-rest writes the zone SSL settings and bot_management, so it is probed after apply too
# (app-health, gptbot, app-noindex), never with the redirect pairs.
REDIRECT_PAIR_CURL='^curl https://(soleur[.]ai/(pages|blog)/|www[.]soleur[.]ai/)'
chk_zrest_probed() { # <dir>: the zone-rest live probes ran, the redirect pairs did not
  grep -qx 'curl https://app.soleur.ai/health' "$1/calls.log" && grep -qx 'curl https://soleur.ai/' "$1/calls.log" \
    && grep -qx 'curl https://app.soleur.ai/' "$1/calls.log" || { WHY="not-probed"; return 1; }
  if grep -qE "$REDIRECT_PAIR_CURL" "$1/calls.log"; then WHY="pair-probed"; return 1; fi
}
chk_zrest_apply_ok() {
  [[ "$(rc_of "$1")" == 0 ]] || { WHY="rc:$(rc_of "$1")"; return 1; }
  chk_zone_rest_args "$1" || return 1
  if grep -q 'state rm' "$1/calls.log"; then WHY="forget"; return 1; fi
  grep -qx 'cf-account-migrate verify=zone-rest verdict=ok' "$1/out.txt" || { WHY="no-ok"; return 1; }
  chk_zrest_probed "$1"
}
setup_zone_rest_apply x; run_job "$LAST_D" "$PRISTINE"; WHY=""
chk_zrest_apply_ok "$LAST_D"; verdict "$?" "zone-rest apply: no forget, -target/-replace argv equals the gate's lists, applied, live probes ok without the redirect pairs ($WHY)"
setup_zrest_health() { new_case "zrh-$1" zone-rest false; remote_state "$LAST_D/remote.tfstate" "$NZ" "$NA"; : >"$LAST_D/mode.health"; }
chk_zrest_health() { # app-health 526 after a zone-rest apply: verify-failed applied=true, stopped after one pass
  refused_for "$1" verify-failed || { WHY="rc:$(rc_of "$1")"; return 1; }
  grep -qxF -- 'cf-account-migrate phase=zone-rest verdict=refuse reason=verify-failed applied=true failing=app-health=>526' "$1/out.txt" || { WHY="no-field"; return 1; }
  grep -qxF -- '- cf-account-migrate phase=zone-rest rehearsal=false verdict=refuse reason=verify-failed applied=true failing=app-health=>526' "$1/summary.md" || { WHY="no-summary"; return 1; }
  grep -qx 'cf-account-migrate verify=zone-rest pass=1 app-health=526 retry=stopped' "$1/out.txt" || { WHY="no-stop-line"; return 1; }
  grep -qF 'Runbook Halt, verify-failed: act on each failing item by its code. app-health=>525/526: the owner may make one dashboard edit on the NEW zone only' "$1/out.txt" || { WHY="no-halt-text"; return 1; }
  chk_zrest_probed "$1"
}
setup_zrest_health x; run_job "$LAST_D" "$PRISTINE"; WHY=""
chk_zrest_health "$LAST_D"; verdict "$?" "zone-rest apply, then app-health 526 -> reason=verify-failed applied=true failing=app-health=>526, the shared Halt text ($WHY)"
new_case zrest-gptbot zone-rest false; remote_state "$LAST_D/remote.tfstate" "$NZ" "$NA"; : >"$LAST_D/mode.gptbot"; run_job "$LAST_D" "$PRISTINE"
r=1; grep -qxF -- 'cf-account-migrate phase=zone-rest verdict=refuse reason=verify-failed applied=true failing=gptbot=>403' "$LAST_D/out.txt" && r=0
verdict "$r" "zone-rest apply, then GPTBot 403 (bot_management) -> reason=verify-failed applied=true failing=gptbot=>403"
new_case verify-broken redirects-dns false; : >"$LAST_D/mode.verify"; run_job "$LAST_D" "$PRISTINE"; D_HEALTH_MSG="$LAST_D"
r=1; refused_for "$LAST_D" verify-failed && grep -q '\] apply' "$LAST_D/calls.log" \
  && grep -q '^cf-account-migrate verify=redirects-dns verdict=fail failing=.* app-noindex=>200+hdr=absent ' "$LAST_D/out.txt" && r=0
verdict "$r" "probes failing after apply -> reason=verify-failed (the job goes red); app-noindex names a 200 with no header"
# app-noindex carries what came back: a timeout (no status line) and a 5xx with another value differ.
for nx in "000+hdr=absent|" "503+hdr=all|HTTP/2 503\r\nx-robots-tag: all\r\n\r\n"; do
  new_case noindex-obs redirects-dns false; printf '%b' "${nx#*|}" >"$LAST_D/mode.noindex"; run_job "$LAST_D" "$PRISTINE"
  r=1; refused_for "$LAST_D" verify-failed && grep -qxF -- "cf-account-migrate verify=redirects-dns verdict=fail failing=app-noindex=>${nx%%|*}" "$LAST_D/out.txt" && r=0
  verdict "$r" "app-noindex failing alone reads app-noindex=>${nx%%|*}"
done
new_case applyfail redirects-dns false; printf '1' >"$LAST_D/mode.apply"; run_job "$LAST_D" "$PRISTINE"; WHY=""
r=1; chk_refuse_fields "$LAST_D" apply-failed 'forget=committed verify=ok' \
  && grep -qx 'cf-account-migrate phase=redirects-dns mode=apply applying=true' "$LAST_D/out.txt" && r=0
verdict "$r" "terraform apply failure -> reason=apply-failed forget=committed verify=ok (the partial apply polled on a 60 s deadline), applying=true printed ($WHY)"
r=1; grep -q 'the forget then removes 0' "$LAST_D/out.txt" && ! grep -q 'Halt verify-failed steps apply' "$LAST_D/out.txt" && r=0
verdict "$r" "apply-failed with verify=ok: the forget sentence, and no verify-failed pointer"
setup_applyfail_health x; run_job "$LAST_D" "$PRISTINE"; WHY=""
chk_applyfail_health "$LAST_D"; verdict "$?" "apply fails, then the probe finds app-health 526 -> reason=apply-failed forget=committed failing=app-health=>526 ($WHY)"
r=1; grep -qF 'The runbook Halt verify-failed steps apply to those failing items (app-health first).' "$LAST_D/out.txt" && r=0
verdict "$r" "apply-failed with failing=: points at the runbook Halt verify-failed steps (app-health first)"
chk_zrest_applyfail() {
  refused_for "$1" apply-failed || { WHY="rc:$(rc_of "$1")"; return 1; }
  grep -qx 'cf-account-migrate phase=zone-rest verdict=refuse reason=apply-failed verify=ok' "$1/out.txt" || { WHY="fields"; return 1; }
  if grep -q 'forget' "$1/out.txt"; then WHY="forget-sentence"; return 1; fi
  chk_zrest_probed "$1"
}
setup_zrest_applyfail() { new_case "afz-$1" zone-rest false; remote_state "$LAST_D/remote.tfstate" "$NZ" "$NA"; printf '1' >"$LAST_D/mode.apply"; }
setup_zrest_applyfail x; run_job "$LAST_D" "$PRISTINE"; WHY=""
chk_zrest_applyfail "$LAST_D"; verdict "$?" "zone-rest apply failure -> reason=apply-failed verify=ok (the partial apply probed, no redirect pairs), no forget field or sentence ($WHY)"
new_case afz-health zone-rest false; remote_state "$LAST_D/remote.tfstate" "$NZ" "$NA"; printf '1' >"$LAST_D/mode.apply"; : >"$LAST_D/mode.health"; run_job "$LAST_D" "$PRISTINE"
r=1; grep -qxF -- 'cf-account-migrate phase=zone-rest verdict=refuse reason=apply-failed failing=app-health=>526' "$LAST_D/out.txt" && r=0
verdict "$r" "zone-rest apply failure with app-health 526 -> reason=apply-failed failing=app-health=>526"
r=1; grep -qF 'app-health=>525/526: the owner may make one dashboard edit on the NEW zone only (the ssl rule, Strict to Full), then redeliver' "$D_HEALTH_MSG/out.txt" \
  && grep -qF 'app-health 3xx whose Location equals a Terraform redirect target: the owner removes that one rule or list item' "$D_HEALTH_MSG/out.txt" \
  && grep -qF 'app-health 000, any other app-health code, or a 3xx no Terraform target matches: no edit, stop for an owner decision' "$D_HEALTH_MSG/out.txt" \
  && grep -qF 'gptbot=>403 after redirects-dns with fight_mode recorded true' "$D_HEALTH_MSG/out.txt" \
  && grep -qF 'Any other gptbot, app-noindex or redirect-pair failure: no dashboard edit, fix forward' "$D_HEALTH_MSG/out.txt" && r=0
verdict "$r" "verify-failed names the runbook's edit cases only (525/526, a Terraform-target 3xx; no edit otherwise)"
# --- In-state updates (D8) ---
r=1; grep -qx 'cf-account-migrate in-state-updates count=0 admitted=' "$D_AP/out.txt" && grep -qx 'cf-account-migrate in-state-updates count=0 admitted=' "$D_REH/out.txt" && r=0
verdict "$r" "first apply and rehearsal: the gate admitted no in-state update (count=0), and the empty input matches"
isu_case reh true; run_job "$LAST_D" "$PRISTINE"
r=1; [[ "$(rc_of "$LAST_D")" == 0 ]] && grep -qx "cf-account-migrate in-state-updates count=1 admitted=$ISU_ADDR" "$LAST_D/out.txt" \
  && grep -qxF -- "- cf-account-migrate phase=redirects-dns rehearsal=true in-state-updates admitted=$ISU_ADDR" "$LAST_D/summary.md" && r=0
verdict "$r" "rehearsal of a fix-forward: prints the admitted set to copy (count=1, log and summary)"
setup_isu_unexpected x; run_job "$LAST_D" "$PRISTINE"; WHY=""
chk_isu_unexpected "$LAST_D"; verdict "$?" "apply admits an in-state update the empty input did not expect -> reason=in-state-updates-unexpected forget=committed, before applying=true ($WHY)"
isu_case match false " ,$ISU_ADDR , $ISU_ADDR"; run_job "$LAST_D" "$PRISTINE"
r=1; [[ "$(rc_of "$LAST_D")" == 0 ]] && grep -qx 'cf-account-migrate phase=redirects-dns mode=apply verdict=PASS applied=true' "$LAST_D/out.txt" && r=0
verdict "$r" "apply whose admitted set equals the input (comma/space separated, repeated) -> applied"
new_case isu-extra redirects-dns false; printf 'CFAM_EXPECTED_IN_STATE_UPDATES=%s\n' "$ISU_ADDR" >"$LAST_D/env.extra"; run_job "$LAST_D" "$PRISTINE"
r=1; refused_for "$LAST_D" in-state-updates-unexpected && grep -qx "cf-account-migrate in-state-updates admitted= expected=$ISU_ADDR" "$LAST_D/out.txt" \
  && ! grep -q '\] apply' "$LAST_D/calls.log" && r=0
verdict "$r" "first apply (none admitted) with a non-empty input -> reason=in-state-updates-unexpected, no apply"
setup_isu_bad x; run_job "$LAST_D" "$PRISTINE"; WHY=""
chk_isu_bad "$LAST_D"; verdict "$?" "a malformed expected_in_state_updates entry -> reason=bad-expected-in-state-updates before any infra call ($WHY)"
# --- Verify retry policy (D12) and the apply-failed ceiling (D13) ---
setup_health_stuck x; run_job "$LAST_D" "$PRISTINE"; WHY=""
chk_health_stuck "$LAST_D"; verdict "$?" "app-health 526 stops the verify after one pass of three (it will not heal) ($WHY)"
setup_health_500 x; run_job "$LAST_D" "$PRISTINE"; WHY=""
chk_health_500 "$LAST_D"; verdict "$?" "app-health 500 (not 525/526) is retried: all three passes run ($WHY)"
# fn_passes <script> <fn> [<arg>...]: the verify passes <fn> makes under the production defaults
# (no CFAM_VERIFY_*), a fast-failing curl (every probe 500) and a virtual clock (sleep only advances
# SECONDS), so a 60 s deadline costs no wall time.
fn_passes() {
  local lib cnt
  lib="$(mktemp "$SBX/fnlib.XXXXXX")" && cnt="$(mktemp "$SBX/fncount.XXXXXX")" || return 2
  sed '/^main "\$@"$/d' "$1" >"$lib"
  # shellcheck disable=SC2016 # expanded by the child bash
  env -u CFAM_VERIFY_TRIES -u CFAM_VERIFY_SLEEP -u CFAM_VERIFY_DEADLINE -u SECONDS MIGRATE_PHASE=redirects-dns FN_COUNT="$cnt" bash -c '
    source "$1" || exit 2; shift
    curl() { case "$*" in *app.soleur.ai/health*) printf x >>"$FN_COUNT" ;; esac
             if [[ "$*" == *" -D - "* ]]; then printf "HTTP/2 500\r\n\r\n"; else printf "500 "; fi; }
    sleep() { SECONDS=$((SECONDS + $1)); }
    "$@" >/dev/null' _ "$lib" "${@:2}"
  printf '%s' "$(($(wc -c <"$cnt")))"
}
r=1; fp="$(fn_passes "$PRISTINE" probe_partial_apply)"; fv="$(fn_passes "$PRISTINE" verify_live)"
[[ "$fp" == 7 && "$fv" == 12 ]] && r=0
verdict "$r" "defaults: the apply-failed probe polls 7 passes (60 s deadline, 10 s pause); the post-apply verify 12 (passes $fp / $fv)"
new_case rerun redirects-dns false; remote_state "$LAST_D/remote.tfstate" "$NZ" "$NA"; run_job "$LAST_D" "$PRISTINE"
r=1; [[ "$(rc_of "$LAST_D")" == 0 ]] && grep -q 'cf-state-migrate verdict=ok removed=0' "$LAST_D/out.txt" && ! grep -q 'state rm' "$LAST_D/calls.log" && r=0
verdict "$r" "redirects-dns re-dispatch after migration: forget removes 0, apply proceeds"

# --- Whole-list entrypoint gate (CTO D2) --------------------------------------------
printf '\n[entrypoint] a populated live phase entrypoint blocks the create (ADR-136)\n'
setup_entry_apply x; run_job "$LAST_D" "$PRISTINE"; WHY=""
chk_entrypoint_refused_apply "$LAST_D"; verdict "$?" "apply: populated http_config_settings -> reason=entrypoint-gate-refused forget=committed, import block printed, apply never called ($WHY)"
setup_entry_rehearsal x; run_job "$LAST_D" "$PRISTINE"; WHY=""
r=1; chk_entrypoint_refused "$LAST_D" && grep -q 'serial_unchanged=true backups_unchanged=true' "$LAST_D/out.txt" \
  && ! grep -q 'forget=committed' "$LAST_D/out.txt" "$LAST_D/summary.md" && r=0
verdict "$r" "rehearsal: the same refusal, after the no-write assertions, with no forget=committed field ($WHY)"
setup_entry_seam x; run_job "$LAST_D" "$PRISTINE"; WHY=""
chk_entrypoint_ran "$LAST_D"; verdict "$?" "the gate runs on the NEW zone in zone-list mode with the rulesets token; its fetch seam is ignored ($WHY)"
r=1; p_line="$(line_no "$D_AP" 'show -json tfplan')"; g_line="$(line_no "$D_AP" "cf-api-gate zones/$NZ/rulesets ")"; a_line="$(line_no "$D_AP" 'terraform\[remote\] apply')"
[[ -n "$p_line" && -n "$g_line" && -n "$a_line" ]] && ((p_line < g_line && g_line < a_line)) && r=0
verdict "$r" "apply order: phase gate (show tfplan) < entrypoint gate < apply"

# --- Hardening ----------------------------------------------------------------------
printf '\n[hardening] pinned endpoint, bounded calls, test seams, logging, audit line\n'
for pair in r2_evil:chk_r2_ignored r2_evil_apply:chk_r2_ignored budget:chk_budget budget_deadline:chk_budget imports_seam:chk_rehearsal_clean tflog:chk_rehearsal_clean \
  tflog_doppler:chk_rehearsal_clean health:chk_health reason:chk_reason backups_timeout:chk_backups_timeout \
  ids_timeout:chk_ids_timeout hostile_loc:chk_hostile_location retry:chk_retry cap:chk_deadline curl_rc:chk_curl_rc \
  reason_bidi:chk_reason_bidi obs_ascii:chk_obs_ascii; do
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
# mode.forget: the forget prints that file's lines and fails (a mid-forget abort).
# mode.forget-unreadable: and then the job's kept copy of this output becomes a directory, so its
# marker grep exits 2 (the pause lets tee open the file first).
if [[ -f "$STUB_DIR/mode.forget" ]]; then
  cat "$STUB_DIR/mode.forget"
  if [[ -f "$STUB_DIR/mode.forget-unreadable" ]]; then
    sleep 0.3; o="${RUNNER_TEMP:?}/cf-migrate/state-migrate.out"
    rm -f "$o" && mkdir "$o" && printf 'state-migrate-stub made-output-unreadable\n' >>"$STUB_DIR/calls.log"
  fi
  exit 1
fi
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
r=1; refused_for "$LAST_D" state-migrate-failed && ! grep -q 'terraform\[remote\] plan' "$LAST_D/calls.log" \
  && chk_refuse_fields "$LAST_D" state-migrate-failed forget=unknown && r=0
verdict "$r" "no cloudflare_* at all: the forget aborts with no backup and the job refuses state-migrate-failed forget=unknown before any plan"
setup_forget_after_backup() {
  new_case "forgetbk-$1" redirects-dns false; printf 'GITHUB_WORKSPACE=%s\n' "$MIRROR" >"$LAST_D/env.extra"
  printf 'cf-state-migrate backup=uploaded uri=s3://x/y\ncf-state-migrate verdict=abort reason=state-rm-failed\n' >"$LAST_D/mode.forget"
}
chk_forget_after_backup() {
  refused_for "$1" state-migrate-failed || { WHY="rc:$(rc_of "$1")"; return 1; }
  if grep -q 'terraform\[remote\] plan' "$1/calls.log"; then WHY="planned"; return 1; fi
  chk_refuse_fields "$1" state-migrate-failed forget=committed
}
setup_forget_after_backup x; run_job "$LAST_D" "$PRISTINE"; WHY=""
chk_forget_after_backup "$LAST_D"; verdict "$?" "the forget fails after backup=uploaded -> reason=state-migrate-failed forget=committed, no plan ($WHY)"
setup_forget_unreadable x; run_job "$LAST_D" "$PRISTINE"; WHY=""
chk_forget_unreadable "$LAST_D"; verdict "$?" "the forget fails and its kept output cannot be read (grep rc 2) -> forget=committed, the safe branch ($WHY)"
new_case applyfail-msg redirects-dns false; printf '1' >"$LAST_D/mode.apply"; run_job "$LAST_D" "$PRISTINE"
r=1; grep -q 'Fix forward.*re-dispatch the same phase: the forget then removes 0' "$LAST_D/out.txt" && ! grep -q 'every phase is idempotent' "$LAST_D/out.txt" && r=0
verdict "$r" "apply-failed names the fix-forward / re-dispatch path (removed=0 on the re-run)"

# --- import-normalize (CTO ruling 2026-11-22) ------------------------------------------
printf '\n[import-normalize] the live read, the bounded apply and the post-apply re-read\n'
REC_ADDR=cloudflare_record.dkim_resend; REC2_ADDR=cloudflare_record.spf_send
rec_id_of() { jq -r --arg a "$1" '.[$a]' <<<"$(_cfam_import_literals)" | cut -d/ -f2; }
REC_ID="$(rec_id_of "$REC_ADDR")"; REC2_ID="$(rec_id_of "$REC2_ADDR")"
[[ "$REC_ID" =~ ^[0-9a-f]{32}$ && "$REC2_ID" =~ ^[0-9a-f]{32}$ ]] || { printf '[FATAL] record pins unreadable\n' >&2; exit 2; }
norm_case() { # <label> <rehearsal>: the plan the provider produces for all 26 records
  new_case "norm-$1" redirects-dns "$2"
  jq '(.resource_changes[] | select(.type == "cloudflare_record") | .change) |= (.actions = ["update"]
        | .before = (.after + {allow_overwrite: null, content: null}) | .after_unknown = {})' \
    "$LAST_D/plan.json" >"$LAST_D/p" && mv "$LAST_D/p" "$LAST_D/plan.json"
}
rec_gets() { # <dir> <when> [<record id>]
  local n; n="$(grep -c "^cf-record-get ${3:-[0-9a-f]*} token=cf_api_token when=$2\$" "$1/calls.log")"; printf '%s' "${n:-0}"
}
before() { # <dir> <pattern-a> <pattern-b>: the first a precedes the first b
  local a b; a="$(line_no "$1" "$2")"; b="$(line_no "$1" "$3")"
  [[ -n "$a" && -n "$b" && "$a" -lt "$b" ]]
}
setup_norm_rehearsal() { norm_case "reh-$1" true; }
setup_norm_apply() { norm_case "apply-$1" false; }
setup_norm_preread() { norm_case "preread-$1" false; printf '500' >"$LAST_D/reccode.pre"; }
setup_norm_differs() { norm_case "differs-$1" false; printf '.result.ttl = 300' >"$LAST_D/recfilter.post.$REC_ID"; }
setup_norm_differs2() { setup_norm_differs "two-$1"; printf '.result.ttl = 300' >"$LAST_D/recfilter.post.$REC2_ID"; }
setup_norm_404() { norm_case "nf-$1" false; printf '404' >"$LAST_D/reccode.post.$REC_ID"; }
setup_norm_flaky() { norm_case "flaky-$1" false; : >"$LAST_D/reconce.post.$REC_ID"; }
setup_norm_unread() { norm_case "unread-$1" false; printf '500' >"$LAST_D/reccode.post.$REC_ID"; }
setup_norm_doppler() { norm_case "dopp-$1" false; : >"$LAST_D/mode.doppler_after_apply"; }
setup_norm_badtoken() { norm_case "badtok-$1" false; printf 'bad"SENTINEL-TOK' >"$LAST_D/mode.badtoken"; }
setup_norm_af() { norm_case "af-$1" false; printf '1' >"$LAST_D/mode.apply"; }
setup_norm_af_differs() { setup_norm_af "d-$1"; printf '.result.ttl = 300' >"$LAST_D/recfilter.post.$REC_ID"; }
setup_norm_af_unread() { setup_norm_af "u-$1"; printf '500' >"$LAST_D/reccode.post.$REC_ID"; }
setup_norm_124() { norm_case "t124-$1" false; printf '124' >"$LAST_D/mode.apply"; }
setup_norm_nobudget() { norm_case "nobudget-$1" false; printf 'SECONDS=1200\n' >"$LAST_D/env.extra"; }
# Away from the 800 s boundary, because the clock moves while the job runs.
setup_norm_s900() { norm_case "s900-$1" false; printf 'SECONDS=900\n' >"$LAST_D/env.extra"; }
setup_norm_s700() { norm_case "s700-$1" false; printf 'SECONDS=700\n' >"$LAST_D/env.extra"; }
setup_norm_s1000() { norm_case "s1000-$1" false; printf 'SECONDS=1000\n' >"$LAST_D/env.extra"; }
# A redirects-dns apply cannot start this late (APPLY_MIN_START), so zone-rest reaches the skip.
setup_skip_probe() {
  new_case "skipprobe-$1" zone-rest false; remote_state "$LAST_D/remote.tfstate" "$NZ" "$NA"
  printf '1' >"$LAST_D/mode.apply"; printf 'SECONDS=1396\n' >"$LAST_D/env.extra"
}
setup_zrest_124() { new_case "zr124-$1" zone-rest false; remote_state "$LAST_D/remote.tfstate" "$NZ" "$NA"; printf '124' >"$LAST_D/mode.apply"; }
reread_mixed() { printf '.result.ttl = 300' >"$LAST_D/recfilter.post.$REC_ID"; printf '500' >"$LAST_D/reccode.post.$REC2_ID"; }
setup_norm_mixed() { norm_case "mixed-$1" false; reread_mixed; }
setup_norm_af_mixed() { setup_norm_af "m-$1"; reread_mixed; }
setup_norm_differs_failing() { setup_norm_differs "f-$1"; : >"$LAST_D/mode.health"; }
setup_norm_unread_failing() { setup_norm_unread "f-$1"; : >"$LAST_D/mode.health"; }
setup_norm_af_differs_failing() { setup_norm_af_differs "f-$1"; : >"$LAST_D/mode.health"; }
setup_norm_af_unread_failing() { setup_norm_af_unread "f-$1"; : >"$LAST_D/mode.health"; }
setup_norm_grepfail() { norm_case "grepfail-$1" false; printf 'PATH=%s\n' "$SBX/bin-grep:$SBX/bin:$PATH" >"$LAST_D/env.extra"; }
setup_norm_stall() { norm_case "stall-$1" false; : >"$LAST_D/mode.doppler_stall"; }
setup_tf_hostile() { new_case "tfhost-$1" redirects-dns false; printf 'x\r::add-mask::y\n##[error]forged\n' >"$LAST_D/tfout"; }
setup_tok_plan() { new_case "tokplan-$1" redirects-dns false; printf '1' >"$LAST_D/od.fail"; printf 'PATH=%s\n' "$SBX/bin-od:$SBX/bin:$PATH" >"$LAST_D/env.extra"; }
setup_tok_apply() { new_case "tokapply-$1" redirects-dns false; printf '2' >"$LAST_D/od.fail"; printf 'PATH=%s\n' "$SBX/bin-od:$SBX/bin:$PATH" >"$LAST_D/env.extra"; }
setup_noop_clean() { new_case "noop-$1" redirects-dns false; }
setup_noop_differs() { new_case "noopd-$1" redirects-dns false; printf '.result.content = "SYNTH-DRIFT"' >"$LAST_D/recfilter.pre.$REC_ID"; }
# Near the floor on both sides, still far enough from 800 s for the clock to move during the run.
setup_norm_s760() { norm_case "s760-$1" false; printf 'SECONDS=760\n' >"$LAST_D/env.extra"; }
setup_norm_s840() { norm_case "s840-$1" false; printf 'SECONDS=840\n' >"$LAST_D/env.extra"; }
# Output an INT cut mid-line: no trailing newline.
setup_tf_cut() { new_case "tfcut-$1" redirects-dns false; printf 'Still creating' >"$LAST_D/tfout"; }
setup_af_plain() { new_case "afplain-$1" redirects-dns false; printf '1' >"$LAST_D/mode.apply"; }
# Gate-time reads: one record differs, one is unreadable, both, or unreadable beside another REFUSE.
gr_differs() { printf '.result.ttl = 300' >"$LAST_D/recfilter.pre.$REC_ID"; }
gr_unread() { printf '500' >"$LAST_D/reccode.pre.$REC_ID"; }
gr_mixed() { gr_differs; printf '500' >"$LAST_D/reccode.pre.$REC2_ID"; }
gr_other() {
  gr_unread
  jq --arg a "$REC2_ADDR" '(.resource_changes[] | select(.address == $a) | .change.after.ttl) = 300' \
    "$LAST_D/plan.json" >"$LAST_D/p" && mv "$LAST_D/p" "$LAST_D/plan.json"
}
setup_gr_differs() { norm_case "grd-$1" false; gr_differs; }
setup_gr_unread() { norm_case "gru-$1" false; gr_unread; }
setup_gr_mixed() { norm_case "grm-$1" false; gr_mixed; }
setup_gr_other() { norm_case "gro-$1" false; gr_other; }
setup_rh_differs() { norm_case "rhd-$1" true; gr_differs; }
setup_rh_unread() { norm_case "rhu-$1" true; gr_unread; }
setup_rh_other() { norm_case "rho-$1" true; gr_other; }

chk_norm_rehearsal() {
  [[ "$(rc_of "$1")" == 0 ]] || { WHY="rc:$(rc_of "$1")"; return 1; }
  grep -qx 'cf-account-migrate live-read records=26' "$1/out.txt" || { WHY="no-read-line"; return 1; }
  grep -qx 'cf-account-migrate import-normalize count=26' "$1/out.txt" || { WHY="no-count-line"; return 1; }
  [[ "$(rec_gets "$1" pre)" == 26 ]] || { WHY="gets:$(rec_gets "$1" pre)"; return 1; }
  before "$1" '^terraform\[local\] plan' '^cf-record-get' || { WHY="read-before-plan"; return 1; }
  if grep -q '^terraform\[[a-z]*\] apply' "$1/calls.log"; then WHY="applied"; return 1; fi
  [[ "$(jq -r .serial "$1/remote.tfstate")" == 7 ]] || { WHY="serial"; return 1; }
}
chk_norm_apply() {
  local n
  [[ "$(rc_of "$1")" == 0 ]] || { WHY="rc:$(rc_of "$1")"; return 1; }
  [[ "$(rec_gets "$1" pre)" == 26 ]] || { WHY="pre:$(rec_gets "$1" pre)"; return 1; }
  [[ "$(rec_gets "$1" post)" == 26 ]] || { WHY="post:$(rec_gets "$1" post)"; return 1; }
  before "$1" '^terraform\[remote\] plan' '^cf-record-get' || { WHY="read-before-plan"; return 1; }
  before "$1" '^cf-record-get' "^cf-api-gate zones/$NZ/rulesets" || { WHY="read-after-gate"; return 1; }
  before "$1" '^terraform\[remote\] apply' 'when=post$' || { WHY="reread-before-apply"; return 1; }
  before "$1" 'when=post$' '^curl https://app.soleur.ai/health$' || { WHY="reread-after-verify"; return 1; }
  grep -qx 'cf-account-migrate import-normalize reread=ok records=26' "$1/out.txt" || { WHY="no-reread-line"; return 1; }
  grep -qx 'cf-account-migrate in-state-updates count=0 admitted=' "$1/out.txt" || { WHY="isu"; return 1; }
  n="$(sed -nE 's/^--foreground -s INT ([0-9]+) terraform apply .*/\1/p' "$1/timeout.log" 2>/dev/null)"
  [[ "$n" =~ ^[0-9]+$ && "$n" -gt 0 && "$n" -le 1100 ]] || { WHY="no-bound"; return 1; }
  if grep -qF 'tok-cf_api_token' "$1/curl-argv.log"; then WHY="bearer-in-argv"; return 1; fi
}
chk_gate_refused_noapply() {
  if grep -q '^terraform\[[a-z]*\] apply' "$1/calls.log"; then WHY="applied"; return 1; fi
  refused_for "$1" gate-refused || { WHY="rc:$(rc_of "$1")"; return 1; }
}
chk_norm_preread() {
  chk_gate_refused_noapply "$1" || return 1
  grep -qF "REFUSE $REC_ADDR live record unreadable" "$1/out.txt" || { WHY="no-refuse-line"; return 1; }
}
chk_reread_fields() { # <dir> <reread value>
  refused_for "$1" import-normalize-reread-failed || { WHY="rc:$(rc_of "$1")"; return 1; }
  chk_refuse_fields "$1" import-normalize-reread-failed "applied=true forget=committed reread=$2 verify=ok"
}
chk_norm_differs() { chk_reread_fields "$1" "differs=$REC_ADDR:ttl" || return 1; [[ "$(rec_gets "$1" post "$REC_ID")" == 1 ]] || { WHY="retried"; return 1; }; }
chk_norm_differs2() {
  refused_for "$1" import-normalize-reread-failed || { WHY="rc:$(rc_of "$1")"; return 1; }
  grep -qE "reread=differs=[^ ]*$REC_ADDR:ttl" "$1/out.txt" && grep -qE "reread=differs=[^ ]*$REC2_ADDR:ttl" "$1/out.txt" || { WHY="one-member"; return 1; }
}
chk_norm_404() { chk_reread_fields "$1" "differs=$REC_ADDR:notfound" || return 1; [[ "$(rec_gets "$1" post "$REC_ID")" == 1 ]] || { WHY="retried"; return 1; }; }
chk_norm_flaky() {
  [[ "$(rc_of "$1")" == 0 ]] || { WHY="rc:$(rc_of "$1")"; return 1; }
  grep -qx 'cf-account-migrate import-normalize reread=ok records=26' "$1/out.txt" || { WHY="no-reread-line"; return 1; }
  [[ "$(rec_gets "$1" post)" == 27 ]] || { WHY="post:$(rec_gets "$1" post)"; return 1; }
}
chk_norm_unread() { chk_reread_fields "$1" "unreadable=$REC_ADDR" || return 1; [[ "$(rec_gets "$1" post "$REC_ID")" == 5 ]] || { WHY="passes:$(rec_gets "$1" post "$REC_ID")"; return 1; }; }
chk_norm_doppler() {
  local f
  refused_for "$1" import-normalize-reread-failed || { WHY="rc:$(rc_of "$1")"; return 1; }
  f="$(sed -nE 's/.*reason=import-normalize-reread-failed applied=true forget=committed reread=unreadable=([^ ]+) verify=ok$/\1/p' "$1/out.txt" | head -n1)"
  [[ "$(tr ',' '\n' <<<"$f" | grep -c '^cloudflare_record\.')" == 26 ]] || { WHY="named:$f"; return 1; }
}
chk_norm_badtoken() {
  if grep -q '^cf-record-get' "$1/calls.log"; then WHY="curl-called"; return 1; fi
  chk_gate_refused_noapply "$1" || return 1
  [[ "$(grep -c '^doppler-live-read$' "$1/calls.log")" == 1 ]] || { WHY="attempts:$(grep -c '^doppler-live-read$' "$1/calls.log")"; return 1; }
  if grep -qF 'SENTINEL-TOK' "$1/out.txt" "$1/err.txt" "$1/summary.md"; then WHY="value-printed"; return 1; fi
  grep -qF "REFUSE $REC_ADDR live record unreadable" "$1/out.txt" || { WHY="no-refuse-line"; return 1; }
}
chk_af_fields() { # <dir> <reread value>
  refused_for "$1" apply-failed || { WHY="rc:$(rc_of "$1")"; return 1; }
  chk_refuse_fields "$1" apply-failed "forget=committed reread=$2 verify=ok" || return 1
  before "$1" 'when=post$' '^curl https://app.soleur.ai/health$' || { WHY="probe-before-reread"; return 1; }
}
chk_norm_af() { chk_af_fields "$1" ok; }
chk_norm_af_differs() { chk_af_fields "$1" "differs=$REC_ADDR:ttl"; }
chk_norm_af_unread() { chk_af_fields "$1" "unreadable=$REC_ADDR"; }
# R21: the runbook routes on this exact text.
chk_norm_124() {
  chk_norm_af "$1" || return 1
  grep -qF 'terraform apply of the graded plan failed (exit 124)' "$1/out.txt" || { WHY="no-exit-124"; return 1; }
  grep -qF "exit 124 is the apply's one INT at APPLY_DEADLINE firing." "$1/out.txt" || { WHY="no-int-text"; return 1; }
}
chk_zrest_124() { # no bound on zone-rest, so a 124 from terraform is not the INT
  refused_for "$1" apply-failed || { WHY="rc:$(rc_of "$1")"; return 1; }
  grep -qF 'failed (exit 124)' "$1/out.txt" || { WHY="no-exit-124"; return 1; }
  if grep -qF 'one INT at APPLY_DEADLINE' "$1/out.txt"; then WHY="claims-int"; return 1; fi
}
# apply_bound <dir>: the seconds of the apply's `timeout`, empty when it had none.
apply_bound() { sed -nE 's/^--foreground -s INT ([0-9]+) terraform apply .*/\1/p' "$1/timeout.log" 2>/dev/null; }
chk_norm_s700() { # Q2: inside the floor the apply runs, with what is left of the budget as its bound
  local n
  [[ "$(rc_of "$1")" == 0 ]] || { WHY="rc:$(rc_of "$1")"; return 1; }
  n="$(apply_bound "$1")"
  [[ "$n" =~ ^[0-9]+$ && "$n" -ge 300 && "$n" -le 400 ]] || { WHY="bound:$n"; return 1; }
}
chk_norm_s760() { # P3-3: close above the floor the apply still runs, on what is left of the budget
  local n
  [[ "$(rc_of "$1")" == 0 ]] || { WHY="rc:$(rc_of "$1")"; return 1; }
  n="$(apply_bound "$1")"
  [[ "$n" =~ ^[0-9]+$ && "$n" -ge 300 && "$n" -le 340 ]] || { WHY="bound:$n"; return 1; }
}
# Halt routing (R1, R4, R17). <route> holds W (wrong value), N (no completed re-read), F (verify-failed).
HALT_W='Runbook Halt: A DNS record may hold a wrong value.'
HALT_N='Runbook Halt: No completed re-read.'
HALT_F='The runbook Halt verify-failed steps apply to those failing items (app-health first).'
chk_halt() { # <dir> <reason> <fields> <route>
  local m k s
  refused_for "$1" "$2" || { WHY="rc:$(rc_of "$1")"; return 1; }
  chk_refuse_fields "$1" "$2" "$3" || return 1
  if grep -q 'also-unreadable' "$1/out.txt"; then WHY="also-unreadable-line"; return 1; fi
  m="$(grep '^::error title=cf-account-migrate::' "$1/out.txt")"
  for k in W N F; do
    case "$k" in W) s="$HALT_W" ;; N) s="$HALT_N" ;; F) s="$HALT_F" ;; esac
    if [[ "$4" == *"$k"* ]]; then [[ "$m" == *"$s"* ]] || { WHY="no-$k"; return 1; }
    else [[ "$m" != *"$s"* ]] || { WHY="extra-$k"; return 1; }; fi
  done
}
RR_F="applied=true forget=committed reread"
chk_h_rr_diff() { chk_halt "$1" import-normalize-reread-failed "$RR_F=differs=$REC_ADDR:ttl verify=ok" W; }
chk_h_rr_unread() { chk_halt "$1" import-normalize-reread-failed "$RR_F=unreadable=$REC_ADDR verify=ok" N; }
chk_h_rr_mixed() { chk_halt "$1" import-normalize-reread-failed "$RR_F=differs=$REC_ADDR:ttl;unreadable=$REC2_ADDR verify=ok" W; }
chk_h_rr_diff_f() { chk_halt "$1" import-normalize-reread-failed "$RR_F=differs=$REC_ADDR:ttl failing=app-health=>526" WF; }
chk_h_rr_unread_f() { chk_halt "$1" import-normalize-reread-failed "$RR_F=unreadable=$REC_ADDR failing=app-health=>526" NF; }
chk_h_af_diff() { chk_halt "$1" apply-failed "forget=committed reread=differs=$REC_ADDR:ttl verify=ok" W; }
chk_h_af_unread() { chk_halt "$1" apply-failed "forget=committed reread=unreadable=$REC_ADDR verify=ok" N; }
chk_h_af_mixed() { chk_halt "$1" apply-failed "forget=committed reread=differs=$REC_ADDR:ttl;unreadable=$REC2_ADDR verify=ok" W; }
chk_h_af_diff_f() { chk_halt "$1" apply-failed "forget=committed reread=differs=$REC_ADDR:ttl failing=app-health=>526" WF; }
chk_h_af_unread_f() { chk_halt "$1" apply-failed "forget=committed reread=unreadable=$REC_ADDR failing=app-health=>526" NF; }
chk_h_af_ok() { chk_halt "$1" apply-failed "forget=committed reread=ok verify=ok" ""; }
# Architecture F1: the sentence after the Halt pointer follows the same evidence.
AF_TAIL='Fix forward (a reviewed PR if the cause is in code), then re-dispatch the same phase:'
chk_af_tail() { # <dir> <fields> <route> <yes|no: the fix-forward sentence belongs>
  local m
  chk_halt "$1" apply-failed "$2" "$3" || return 1
  m="$(grep '^::error title=cf-account-migrate::' "$1/out.txt")"
  if [[ "$4" == yes ]]; then [[ "$m" == *"$AF_TAIL"* ]] || { WHY="no-tail"; return 1; }; return 0; fi
  [[ "${m,,}" != *"fix forward"* ]] || { WHY="has-fix-forward"; return 1; }
  [[ "$m" != *re-dispatch* ]] || { WHY="has-re-dispatch"; return 1; }
}
chk_t_none() { chk_af_tail "$1" "forget=committed verify=ok" "" yes; }
chk_t_ok() { chk_af_tail "$1" "forget=committed reread=ok verify=ok" "" yes; }
chk_t_diff() { chk_af_tail "$1" "forget=committed reread=differs=$REC_ADDR:ttl verify=ok" W no; }
chk_t_unread() { chk_af_tail "$1" "forget=committed reread=unreadable=$REC_ADDR verify=ok" N no; }
chk_t_mixed() { chk_af_tail "$1" "forget=committed reread=differs=$REC_ADDR:ttl;unreadable=$REC2_ADDR verify=ok" W no; }
GR_BASE='::error title=cf-account-migrate::the plan did not reach gate verdict=PASS; nothing was applied.'
RH_BASE='::error title=cf-account-migrate::the rehearsal did not reach gate verdict=PASS (see above); nothing was written'
FG_TXT='The state forget is committed (backup uri above); runbook Halt: fix forward and re-dispatch (the forget then removes 0); the _PREV id restore no longer applies.'
FK_TXT='The state forget is committed (backup uri above); the _PREV id restore no longer applies.'
HALT_E='Edit no DNS record and re-rehearse once; a second consecutive refusal stops for an owner decision.'
chk_next() { # <dir> <reason> <exact annotation> <yes|no: a fix-forward or re-dispatch sentence belongs>
  local m
  refused_for "$1" "$2" || { WHY="rc:$(rc_of "$1")"; return 1; }
  m="$(grep '^::error title=cf-account-migrate::' "$1/out.txt")"
  if [[ "$4" == no ]]; then
    [[ "${m,,}" != *"fix forward"* ]] || { WHY="has-fix-forward"; return 1; }
    [[ "$m" != *re-dispatch* ]] || { WHY="has-re-dispatch"; return 1; }
  fi
  [[ "$m" == "$3" ]] || { WHY="msg"; return 1; }
}
chk_gr_differs() { chk_next "$1" gate-refused "$GR_BASE $FK_TXT $HALT_W" no && chk_forget_committed "$1" gate-refused; }
chk_gr_unread() { chk_next "$1" gate-refused "$GR_BASE $FK_TXT $HALT_E" no && chk_forget_committed "$1" gate-refused; }
chk_gr_today() { chk_next "$1" gate-refused "$GR_BASE $FG_TXT" yes && chk_forget_committed "$1" gate-refused; }
chk_rh_differs() { chk_next "$1" rehearsal-refused "$RH_BASE. $HALT_W" no; }
chk_rh_unread() { chk_next "$1" rehearsal-refused "$RH_BASE. $HALT_E" no; }
chk_rh_today() { chk_next "$1" rehearsal-refused "$RH_BASE" yes; }
chk_norm_grepfail() { # R16: a real grep failure on the count refuses instead of disabling the re-read
  chk_gate_refused_noapply "$1" || return 1
  grep -qF 'cannot count the import-normalize records (grep exit 2)' "$1/out.txt" || { WHY="no-count-error"; return 1; }
}
chk_norm_stall() { # F7: the read's `doppler run` starts under the outer timeout, so a stall reads as unreadable
  grep -q '^doppler-stall$' "$1/calls.log" || { WHY="no-stall"; return 1; }
  grep -qE '^-k 5 [0-9]+ doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- env ' "$1/timeout.log" 2>/dev/null \
    || { WHY="no-outer-timeout"; return 1; }
  chk_gate_refused_noapply "$1" || return 1
  grep -qF "REFUSE $REC_ADDR live record unreadable" "$1/out.txt" || { WHY="no-refuse-line"; return 1; }
}
# Q7: both terraform pipelines sit inside a matching token window, with every line prefixed.
chk_tf_windows() {
  local v
  [[ "$(rc_of "$1")" == 0 ]] || { WHY="rc:$(rc_of "$1")"; return 1; }
  if LC_ALL=C grep -q $'\r' "$1/out.txt"; then WHY="cr"; return 1; fi
  v="$(awk '
    /^::stop-commands::/ { if (open) bad = "nested"; tok = substr($0, 18); if (length(tok) != 32) bad = "token"; open = 1; n++; next }
    open && $0 == "::" tok "::" { open = 0; next }
    open && $0 != "" && $0 !~ /^tf\| / { bad = "unprefixed" }
    !open && /^tf\| / { bad = "outside" }
    END { if (open) bad = "unclosed"; print (bad != "" ? bad : "ok:" n) }' "$1/out.txt")"
  [[ "$v" == ok:2 ]] || { WHY="window:$v"; return 1; }
}
chk_tf_cut() { # P3-2: output cut mid-line keeps its text, and the closer still lands on its own line
  chk_tf_windows "$1" || return 1
  [[ "$(grep -cxF 'tf| Still creating' "$1/out.txt")" -eq 2 ]] || { WHY="no-cut-line"; return 1; }
}
chk_tf_window() {
  chk_tf_windows "$1" || return 1
  [[ "$(grep -cxF 'tf| x ::add-mask::y' "$1/out.txt")" -eq 2 ]] || { WHY="no-mask-line"; return 1; }
  [[ "$(grep -cxF 'tf| ##[error]forged' "$1/out.txt")" -eq 2 ]] || { WHY="no-error-line"; return 1; }
  if grep -qE '^(::add-mask::|##\[error\])' "$1/out.txt"; then WHY="command-opener"; return 1; fi
}
chk_tok_plan() {
  if grep -q '^terraform\[[a-z]*\] plan' "$1/calls.log"; then WHY="planned"; return 1; fi
  chk_gate_refused_noapply "$1" || return 1
  grep -qF 'cannot create the workflow-command token' "$1/out.txt" || { WHY="no-token-error"; return 1; }
}
chk_tok_apply() {
  if grep -q '^terraform\[[a-z]*\] apply' "$1/calls.log"; then WHY="applied"; return 1; fi
  if grep -q 'applying=true' "$1/out.txt"; then WHY="applying-line"; return 1; fi
  chk_refuse_fields "$1" setup "applied=false forget=committed"
}
# fn_read <script> <virtual seconds per attempt>: read_live_records under production defaults on a
# virtual clock. Prints "<pauses> attempts=<n> elapsed=<s>".
fn_read() {
  local lib wd
  lib="$(mktemp "$SBX/fnlib.XXXXXX")" && wd="$(mktemp -d "$SBX/fnread.XXXXXX")" || return 2
  sed '/^main "\$@"$/d' "$1" >"$lib"
  # shellcheck disable=SC2016 # expanded by the child bash
  env -u CFAM_VERIFY_SLEEP -u SECONDS MIGRATE_PHASE=redirects-dns FN_STEP="$2" FN_W="$wd" bash -c '
    source "$1" || exit 2
    W="$FN_W"; CFAM_NEW_ZONE_ID=z; pauses=""; n=0
    cf_account_migrate_record_pins() { printf "cloudflare_record.a\tdeadbeef\n"; }
    cf_account_migrate_live_collect() { printf "{}\n"; }
    sleep() { pauses+="$1 "; SECONDS=$((SECONDS + $1)); }
    timeout() { n=$((n + 1)); SECONDS=$((SECONDS + ($3 < FN_STEP ? $3 : FN_STEP))); return 124; }
    read_live_records "$W/out.json" >/dev/null 2>&1
    printf "%sattempts=%s elapsed=%s\n" "$pauses" "$n" "$SECONDS"' _ "$lib"
}
# fn_reread <script>: reread_records with a failing pin lookup. Prints "rc=<n> reread=<value>".
fn_reread() {
  local lib
  lib="$(mktemp "$SBX/fnlib.XXXXXX")" || return 2
  sed '/^main "\$@"$/d' "$1" >"$lib"
  # shellcheck disable=SC2016 # expanded by the child bash
  env MIGRATE_PHASE=redirects-dns bash -c '
    source "$1" || exit 2
    W="$(dirname "$1")"
    cf_account_migrate_record_pins() { return 1; }
    read_live_records() { return 1; }
    reread_records >/dev/null 2>&1; rc=$?
    printf "rc=%s reread=%s\n" "$rc" "$REREAD"' _ "$lib"
}
# gate_call_arity <script>: the argument count of the job's redirects-dns gate call, comments stripped.
gate_call_arity() {
  local call args
  call="$(sed -n '/^plan_and_gate() {$/,/^}$/p' "$1" | sed -E -e '/^[[:space:]]*#/d' -e 's/[[:space:]]+#.*$//' \
    | sed -n '/== redirects-dns || "\$MIGRATE_PHASE" == tunnel \]\]; then$/,/^  else$/p' | grep 'cf_account_migrate_gate ')" || return 1
  [[ "$(grep -c . <<<"$call")" -eq 1 ]] || return 1
  args="${call#*cf_account_migrate_gate }"; args="${args%%)*}"
  grep -oE '"[^"]+"' <<<"$args" | grep -c .
}
chk_norm_nobudget() {
  if grep -q '^terraform\[[a-z]*\] apply' "$1/calls.log"; then WHY="applied"; return 1; fi
  if grep -q 'applying=true' "$1/out.txt"; then WHY="applying-line"; return 1; fi
  refused_for "$1" apply-budget-exhausted || { WHY="not-refused"; return 1; }
  chk_refuse_fields "$1" apply-budget-exhausted "applied=false forget=committed"
}
chk_skip_probe() {
  refused_for "$1" apply-failed || { WHY="rc:$(rc_of "$1")"; return 1; }
  grep -qxF -- 'cf-account-migrate phase=zone-rest verdict=refuse reason=apply-failed verify=skipped' "$1/out.txt" || { WHY="no-field"; return 1; }
  if grep -q '^curl https://app.soleur.ai/health$' "$1/calls.log"; then WHY="probed"; return 1; fi
}
chk_noop_clean() { # Q1: no replace in the phase, so the bound holds with no admitted record
  local n
  [[ "$(rc_of "$1")" == 0 ]] || { WHY="rc:$(rc_of "$1")"; return 1; }
  [[ "$(rec_gets "$1" pre)" == 26 ]] || { WHY="gets:$(rec_gets "$1" pre)"; return 1; }
  [[ "$(rec_gets "$1" post)" == 0 ]] || { WHY="reread"; return 1; }
  grep -qx 'cf-account-migrate import-normalize count=0' "$1/out.txt" || { WHY="no-count-line"; return 1; }
  n="$(apply_bound "$1")"
  [[ "$n" =~ ^[0-9]+$ && "$n" -gt 0 && "$n" -le 1100 ]] || { WHY="unbounded"; return 1; }
}
chk_noop_differs() {
  chk_gate_refused_noapply "$1" || return 1
  grep -qF "REFUSE $REC_ADDR differs from the live record (content)" "$1/out.txt" || { WHY="no-refuse-line"; return 1; }
  if grep -qF 'SYNTH-DRIFT' "$1/out.txt"; then WHY="value-printed"; return 1; fi
}
chk_zrest_noread() {
  [[ "$(rc_of "$1")" == 0 ]] || { WHY="rc:$(rc_of "$1")"; return 1; }
  if grep -qE '^(cf-record-get|doppler-live-read)' "$1/calls.log"; then WHY="record-read"; return 1; fi
  # The log holds the job's other bounded calls, so an empty one would prove nothing.
  [[ -s "$1/timeout.log" ]] || { WHY="no-timeout-log"; return 1; }
  if grep -q 'terraform apply' "$1/timeout.log"; then WHY="bounded"; return 1; fi
  grep -q '^terraform\[remote\] apply' "$1/calls.log" || { WHY="no-apply"; return 1; }
}
norm_row() { # <label> <setup> <check>
  "$2" case; run_job "$LAST_D" "$PRISTINE"; WHY=""
  if "$3" "$LAST_D"; then verdict 0 "$1"; else verdict 1 "$1 (WHY=$WHY)"; fi
}
norm_row "N1 a rehearsal reads all 26 after the plan, admits them and applies nothing" setup_norm_rehearsal chk_norm_rehearsal
norm_row "N2 an apply runs plan, read, gates, a bounded apply, re-read, verify" setup_norm_apply chk_norm_apply
norm_row "N3 a read failure before the apply refuses at the gate" setup_norm_preread chk_norm_preread
norm_row "N4 a post-apply difference halts at once" setup_norm_differs chk_norm_differs
norm_row "N5 every differing record is named" setup_norm_differs2 chk_norm_differs2
norm_row "N6 a post-apply 404 halts without a retry" setup_norm_404 chk_norm_404
norm_row "N7 (H2) one unreadable pass then a clean one passes" setup_norm_flaky chk_norm_flaky
norm_row "N8 unreadable through every pass halts" setup_norm_unread chk_norm_unread
norm_row "N9 (S1) Doppler failing on the re-read names all 26, never the pre-write responses" setup_norm_doppler chk_norm_doppler
norm_row "N10 (S3) a token failing the shape guard makes no curl call and one attempt" setup_norm_badtoken chk_norm_badtoken
norm_row "N11 apply-failed carries reread=ok before verify=" setup_norm_af chk_norm_af
norm_row "N12 apply-failed carries reread=differs" setup_norm_af_differs chk_norm_af_differs
norm_row "N13 apply-failed carries reread=unreadable" setup_norm_af_unread chk_norm_af_unread
norm_row "N14 (R21) the bound's exit 124 reaches apply-failed and the message names the INT" setup_norm_124 chk_norm_124
norm_row "N15 no apply budget refuses before applying=true" setup_norm_nobudget chk_norm_nobudget
norm_row "N16 past 1395 s a failed (zone-rest) apply skips the probe and says so" setup_skip_probe chk_skip_probe
norm_row "N17 (Q1) redirects-dns with NORM_COUNT=0 reads 26, is bounded and makes no re-read" setup_noop_clean chk_noop_clean
norm_row "N18 an all-no-op plan refuses on a live difference, printing no value" setup_noop_differs chk_noop_differs
norm_row "N19 (Q1) zone-rest makes no record read and its apply argv has no timeout" setup_zone_rest_apply chk_zrest_noread
norm_row "N20 (Q2) SECONDS=900 refuses apply-budget-exhausted before applying=true" setup_norm_s900 chk_norm_nobudget
norm_row "N21 (Q2) SECONDS=700 runs with a bound of at most 400" setup_norm_s700 chk_norm_s700
norm_row "N22 (F6) SECONDS=1000 is inside the floor's refusal, so no apply starts with 100 s left" setup_norm_s1000 chk_norm_nobudget
norm_row "N23 (R21) a zone-rest exit 124 is not called the INT: that apply has no bound" setup_zrest_124 chk_zrest_124
norm_row "N24 (P3-3) SECONDS=760 still runs, with a bound of 300 to 340" setup_norm_s760 chk_norm_s760
norm_row "N25 (P3-3) SECONDS=840 refuses apply-budget-exhausted before applying=true" setup_norm_s840 chk_norm_nobudget
norm_row "H1 (R1) reread-failed, differs: the wrong-value bullet only" setup_norm_differs chk_h_rr_diff
norm_row "H2 (R1) reread-failed, unreadable only: No completed re-read only" setup_norm_unread chk_h_rr_unread
norm_row "H3 (R17) reread-failed, mixed: one field, routed as a difference" setup_norm_mixed chk_h_rr_mixed
norm_row "H4 (R4) reread-failed, differs with failing=: both sentences" setup_norm_differs_failing chk_h_rr_diff_f
norm_row "H5 (R4) reread-failed, unreadable with failing=: both sentences" setup_norm_unread_failing chk_h_rr_unread_f
norm_row "H6 (R1) apply-failed, differs: the wrong-value bullet only" setup_norm_af_differs chk_h_af_diff
norm_row "H7 (R1) apply-failed, unreadable only: No completed re-read only" setup_norm_af_unread chk_h_af_unread
norm_row "H8 (R17) apply-failed, mixed: one field, routed as a difference" setup_norm_af_mixed chk_h_af_mixed
norm_row "H9 apply-failed, differs with failing=: both sentences" setup_norm_af_differs_failing chk_h_af_diff_f
norm_row "H10 apply-failed, unreadable with failing=: both sentences" setup_norm_af_unread_failing chk_h_af_unread_f
norm_row "H11 apply-failed, reread=ok verify=ok: no Halt pointer" setup_norm_af chk_h_af_ok
norm_row "T1 (F1) apply-failed with no reread= field keeps the fix-forward sentence" setup_af_plain chk_t_none
norm_row "T2 (F1) apply-failed, reread=ok keeps the fix-forward sentence" setup_norm_af chk_t_ok
norm_row "T3 (F1) apply-failed, differs: no fix-forward or re-dispatch sentence" setup_norm_af_differs chk_t_diff
norm_row "T4 (F1) apply-failed, unreadable: no fix-forward or re-dispatch sentence" setup_norm_af_unread chk_t_unread
norm_row "T5 (F1) apply-failed, mixed: no fix-forward or re-dispatch sentence" setup_norm_af_mixed chk_t_mixed
norm_row "T6 (F1) gate-refused, differs: the wrong-value bullet, no re-dispatch" setup_gr_differs chk_gr_differs
norm_row "T7 (F1) gate-refused, unreadable only: edit nothing and re-rehearse" setup_gr_unread chk_gr_unread
norm_row "T8 (F1) gate-refused, differs and unreadable: the wrong-value bullet" setup_gr_mixed chk_gr_differs
norm_row "T9 (F1) gate-refused, unreadable beside another REFUSE keeps today's text" setup_gr_other chk_gr_today
norm_row "T10 (F1) gate-refused with no live-read line keeps today's text" setup_refuse_apply chk_gr_today
norm_row "T11 (F1) rehearsal-refused, differs: the wrong-value bullet" setup_rh_differs chk_rh_differs
norm_row "T12 (F1) rehearsal-refused, unreadable only: edit nothing and re-rehearse" setup_rh_unread chk_rh_unread
norm_row "T13 (F1) rehearsal-refused, any other refusal keeps today's text" setup_rh_other chk_rh_today
norm_row "R16 a real grep failure on the count refuses, with no apply" setup_norm_grepfail chk_norm_grepfail
norm_row "Q7 both terraform pipelines are windowed and prefixed, with no CR" setup_tf_hostile chk_tf_window
norm_row "Q7 (P3-2) output cut with no trailing newline still closes both windows" setup_tf_cut chk_tf_cut
norm_row "Q7 no plan token: refused before terraform plan" setup_tok_plan chk_tok_plan
norm_row "Q7 no apply token: refused setup applied=false before applying=true" setup_tok_apply chk_tok_apply
r=1; v="$(fn_reread "$PRISTINE")"; [[ "$v" == "rc=1 reread=unreadable=all-pinned-records" ]] && r=0
verdict "$r" "R18 a failed pin lookup in the re-read is unreadable= and returns 1 ($v)"
r=1; v="$(fn_read "$PRISTINE" 0)"; [[ "$v" == "5 10 20 40 attempts=5 elapsed="* ]] && r=0
verdict "$r" "R8 five passes with the pause doubling from 5 s ($v)"
r=1; v="$(fn_read "$PRISTINE" 20)"; e="${v##*elapsed=}"; [[ "$e" =~ ^[0-9]+$ && "$e" -le 90 && "$v" != "5 10 20 40 "* ]] && r=0
verdict "$r" "R8 slow passes cut the pauses and stay inside the 90 s deadline ($v)"
# shellcheck disable=SC2016 # literal script text
r=1; v="$(sed -n '/^LIVE_READ_SH=/,/^LIVEREAD$/p' "$PRISTINE")"; [[ "$v" != *api.cloudflare.com* && "$v" == *'"$b/zones/$z/dns_records/$id"'* ]] && r=0
verdict "$r" "R19 the live-read script takes the API base as an argument and holds no copy of it"

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
# Selector drift the argv-exact fakes now see.
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
H5="$(mk_mutant tflog-doppler 's/^  env -u TF_LOG -u TF_LOG_PATH -u TF_LOG_CORE -u TF_LOG_PROVIDER)$/  )/')"
red "H5 a Doppler-side TF_LOG* reaches terraform plan" "$H5" chk_rehearsal_clean '^tf-log-leak$' setup_tflog_doppler
H6="$(mk_mutant no-health '/bad+=" app-health/d')"
red "H6 post-apply verify drops the app.soleur.ai/health probe" "$H6" chk_health '^rc:0$' setup_health
H6b="$(mk_mutant any-301 's/"301 \$want"/301\\ */')"
red "H6b post-apply verify accepts a legacy 301 to any destination" "$H6b" chk_dest '^rc:0$' setup_wrongdest
# Every pair is checked, not only agents.html: each other target misdirected alone fails the verify.
for wd in https://soleur.ai/pages/legal/privacy-policy.html https://soleur.ai/blog/2026-03-16-soleur-vs-anthropic-cowork/ https://www.soleur.ai/; do
  new_case "wrongdest-each" redirects-dns false; printf '%s' "$wd" >"$LAST_D/mode.wrongdest"; run_job "$LAST_D" "$PRISTINE"; WHY=""
  chk_dest_for "$LAST_D" "$wd"; verdict "$?" "verify: $wd 301ing to the wrong page alone fails, naming what came back ($WHY)"
done
# The verify's exact targets are a hand-kept copy of the Terraform and of the runbook's Verify
# block: tie each pair to both, so a .tf retarget cannot leave a red run after a correct apply.
job_pairs() { sed -n '/^readonly VERIFY_PAIRS=($/,/^)$/p' "$REPO/apps/web-platform/infra/scripts/cf-account-migrate-job.sh" | sed -n 's/^  "\(https:[^|]*\)|\(https:[^"]*\)"$/\1 \2/p'; }
tf_target_of() { # <source-url> -> the Terraform's target for it
  local src="$1" inf="$REPO/apps/web-platform/infra" slug canon
  case "$src" in
    https://soleur.ai/pages/agents.html)
      awk '/http.request.uri.path eq \\"\/pages\/agents.html\\"/{on=1} on && /value *= *"https:/{sub(/.*value *= *"/,""); sub(/".*/,""); print; exit}' "$inf/seo-rulesets.tf" ;;
    https://soleur.ai/pages/legal/*|https://www.soleur.ai/)   # www: the www_canonical list item
      grep -A1 -F -- "source_url            = \"${src#https://}\"" "$inf/seo-bulk-redirects.tf" | sed -n 's/^ *target_url *= *"\(.*\)"$/\1/p' ;;
    https://soleur.ai/blog/*)
      slug="${src#https://soleur.ai/blog/}"; slug="${slug%/}"
      canon="$(sed -n "s/^ *\"${slug}\" *= *\"\([^\"]*\)\"$/\1/p" "$inf/seo-bulk-redirects.tf")"
      [[ -n "$canon" ]] && printf 'https://soleur.ai/blog/%s/\n' "$canon" ;;
  esac
}
r=1; WHY=""; n=0
while read -r src want; do
  n=$((n + 1))
  [[ "$(tf_target_of "$src")" == "$want" ]] || { WHY+=" tf:$src"; continue; }
  rb="$(grep -F -- "curl " "$REPO/knowledge-base/engineering/operations/runbooks/cloudflare-account-migration.md" || true)"
  rb="$(grep -F -- "$src" <<<"$rb" || true)"
  [[ -n "$rb" ]] && grep -qF -- "301" <<<"$rb" && grep -qF -- "$want" <<<"$rb" || WHY+=" runbook:$src"
done < <(job_pairs)
[[ "$n" -eq 4 && -z "$WHY" ]] && r=0
verdict "$r" "the verify's four exact targets equal the Terraform's and the runbook Verify block's (n=$n$WHY)"
chk_dest_cowork() { chk_dest_for "$1" 'https://soleur.ai/blog/2026-03-16-soleur-vs-anthropic-cowork/'; }
H6c="$(mk_mutant drop-pair '/^  "https:\/\/soleur.ai\/blog\/2026-03-16-soleur-vs-anthropic-cowork\/|/d')"
red "H6c post-apply verify drops a legacy redirect pair" "$H6c" chk_dest_cowork '^rc:0$' setup_wrongdest_cowork
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
R1="$(mk_mutant forget-ok-ignored '/^    state_migrate | tee /{n;s/^    if \[\[ "\$rc" -ne 0 \]\]; then$/    if [[ "$rc" -eq 0 ]]; then/;}')"
setup_redispatch() { new_case "redispatch-mut-$1" redirects-dns false; forgotten_state "$LAST_D/remote.tfstate"; printf 'GITHUB_WORKSPACE=%s\n' "$MIRROR" >"$LAST_D/env.extra"; }
chk_redispatch_apply() { chk_redispatch "$1" apply; }
red "R1 a removed=0 forget treated as a failure (re-dispatch deadlock)" "$R1" chk_redispatch_apply '^(rc:1|no-plan)$' setup_redispatch
M8="$(mk_mutant always-apply 's/if \[\[ "$REHEARSAL" == true \]\]; then run_rehearsal; else run_apply; fi/run_apply/')"
red "M8 rehearsal dispatch routed to the apply path" "$M8" chk_rehearsal_clean '^(apply-called|aws-s3-cp|remote-state-rm)$' setup_rehearsal
# shellcheck disable=SC2016 # sed expression matches literal script text
V1="$(mk_mutant annotation-unescaped 's#^  local m="\${2//%/%25}"$#  local m="$2"#')"
red "V1 refuse() prints a network value's %0A undecoded into the annotation" "$V1" chk_hostile_location '^not-encoded$' setup_hostile_loc
# shellcheck disable=SC2016 # sed expression matches literal script text
V2="$(mk_mutant no-deadline 's/ || ((SECONDS >= end))//')"
red "V2 the verify loop without its deadline check runs every pass (TRIES=3, DEADLINE=0)" "$V2" chk_deadline '^passes:3$' setup_deadline
# shellcheck disable=SC2016 # sed expression matches literal script text
V4="$(mk_mutant end-now 's/^  end=\$((SECONDS + dl))$/  end=$SECONDS/')"
red "V4 the deadline set to the verify's start (end=\$SECONDS) gives up after one failing pass" "$V4" chk_retry '^(rc:1|no-ok)$' setup_retry
# shellcheck disable=SC2016 # sed expression matches literal script text
V5="$(mk_mutant no-cap '/^  if ((cap < end)); then end=\$cap; fi$/d')"
red "V5 the verify deadline without the script-start cap runs every pass past 1395 s" "$V5" chk_deadline '^passes:3$' setup_cap
# shellcheck disable=SC2016 # sed expression matches literal script text
V6="$(mk_mutant applyfail-no-probe 's/^  if probe_partial_apply; then vf="verify=ok"; else vf="failing=\${VERIFY_FAILING}"; fi$/  :/')"
red "V6 a failed apply is not probed (the partial apply's 526 is unreported)" "$V6" chk_applyfail_health '^no-field$' setup_applyfail_health
# shellcheck disable=SC2016 # sed expression matches literal script text
V7="$(mk_mutant applyfail-no-forget 's/ "\$(join_fields "\$fx" "\$rr" "\$vf")"$/ "$vf"/')"
red "V7 apply-failed without the forget=committed field" "$V7" chk_applyfail_health '^no-field$' setup_applyfail_health
V8="$(mk_mutant no-applying-line '/mode=apply applying=true/d')"
red "V8 no applying=true marker before terraform apply" "$V8" chk_applyfail_health '^no-applying-line$' setup_applyfail_health
# shellcheck disable=SC2016 # sed expression matches literal script text
V9="$(mk_mutant verify-no-forget 's/"applied=true\${fx:+ \$fx}\${sx:+ \$sx} failing=/"applied=true${sx:+ $sx} failing=/')"
red "V9 verify-failed without the forget=committed field" "$V9" chk_dest '^no-applied-summary$' setup_wrongdest
# shellcheck disable=SC2016 # sed expression matches literal script text
V10="$(mk_mutant forget-marker-ignored 's/^      if \[\[ "\$g" -ne 1 \]\]; then$/      if false; then/')"
red "V10 a forget that failed after backup=uploaded reported as forget=unknown" "$V10" chk_forget_after_backup '^no-field$' setup_forget_after_backup
# shellcheck disable=SC2016 # sed expression matches literal script text
V14="$(mk_mutant forget-grep-rc-folded 's/ 2>\/dev\/null || g=\$?$/ 2>\/dev\/null || g=1/')"
red "V14 (D31) the marker grep's rc 2 (output unreadable) read as no marker -> forget=unknown" "$V14" chk_forget_unreadable '^no-field$' setup_forget_unreadable
# shellcheck disable=SC2016 # sed expression matches literal script text
V15="$(mk_mutant no-isu-check '/^  check_expected_isu "\$fg" "\$fx"$/d')"
red "V15 (D8) the apply never compares the admitted in-state updates with the input" "$V15" chk_isu_unexpected '^(apply-called|applying-line)$' setup_isu_unexpected
V16="$(mk_mutant isu-shape-unchecked 's/|| refuse bad-expected-in-state-updates/|| true/')"
red "V16 (D8) a malformed expected_in_state_updates entry is not refused up front" "$V16" chk_isu_bad '^not-refused' setup_isu_bad
# shellcheck disable=SC2016 # sed expression matches literal script text
V17="$(mk_mutant token-rc-folded 's/^    if \[\[ "\$e" != 0 \]\]; then unreach=1$/    if [[ "$e" != 0 ]]; then bad=1/')"
red "V17 (D15) a curl transport failure read as a token verdict (re-mint, not retry)" "$V17" chk_token_unreach '^not-refused' setup_token_unreach
V27="$(mk_mutant token-429-is-verdict 's/^    else case "\$code" in 200) ;; 400|401|403|404|bad|missing) bad=1 ;; \*) unreach=1 ;; esac; fi$/    else case "$code" in 200) ;; *) bad=1 ;; esac; fi/')"
red "V27 (fr4 F2) a 429 token probe read as a token verdict (re-mint, not retry)" "$V27" chk_token_429 '^not-refused' setup_token_429
# shellcheck disable=SC2016 # sed expression matches literal script text
V18="$(mk_mutant zone-case-fold 's/^  zone="\$(sed -n 1p <<<"\$out")"$/  zone="$(sed -n 1p <<<"$out" | tr A-F a-f)"/')"
red "V18 (D16) the id preflight folds case again: an upper-case NEW zone id passes and the forget runs" "$V18" chk_ids_refused '^remote-state-rm$' setup_upper_zone
# shellcheck disable=SC2016 # sed expression matches literal script text
V19="$(mk_mutant no-callee-closure 's/^  while \[\[ "\$grew" -eq 1 \]\]; do$/  while false; do/')"
red "V19 (D19) gated_workflows ignores job-level uses: of a reusable chain" "$V19" chk_inflight '^not-refused' setup_inflight_caller
V20="$(mk_mutant loader-unquoted '/^readonly LOADER_RE=/s/\[[^]]*\]?//g')"
red "V20 (D19) gated_workflows misses a quoted loader line (the chain's callee)" "$V20" chk_inflight '^not-refused' setup_inflight_caller
# shellcheck disable=SC2016 # sed expression matches literal script text
V21="$(mk_mutant no-stuck-stop '/^    \[\[ "\$got" =~ \^52\[56\]/d')"
red "V21 (D12) the verify keeps retrying a 526 it cannot heal" "$V21" chk_health_stuck '^(no-stop-line|passes:3)$' setup_health_stuck
V22="$(mk_mutant stuck-any-code 's/=~ \^52\[56\]\\ /=~ ^[0-9]/')"
red "V22 (D12) any app-health failure stops the verify (a 500 is no longer retried)" "$V22" chk_health_500 '^passes:1$' setup_health_500
# shellcheck disable=SC2016 # sed expression matches literal script text
V23="$(mk_mutant forget-sentence-always 's/^    \[\[ "\$MIGRATE_PHASE" != redirects-dns \]\] || msg+=" the forget/    msg+=" the forget/')"
red "V23 (D9) zone-rest apply-failed carries the redirects-dns forget sentence" "$V23" chk_zrest_applyfail '^forget-sentence$' setup_zrest_applyfail
# shellcheck disable=SC2016 # sed expression matches literal script text
V24="$(mk_mutant zrest-no-verify 's/^  verify_live || refuse verify-failed/  [[ "$MIGRATE_PHASE" != redirects-dns ]] || verify_live || refuse verify-failed/')"
red "V24 (D33) the post-apply live verify skipped for zone-rest (a 526 after it goes unreported)" "$V24" chk_zrest_health '^rc:0$' setup_zrest_health
# shellcheck disable=SC2016 # sed expression matches literal script text
V25="$(mk_mutant zrest-no-applyfail-probe 's/^  if probe_partial_apply; then vf=/  if [[ "$MIGRATE_PHASE" != redirects-dns ]]; then :; elif probe_partial_apply; then vf=/')"
red "V25 (D33) a failed zone-rest apply is not probed" "$V25" chk_zrest_applyfail '^fields$' setup_zrest_applyfail
# shellcheck disable=SC2016 # sed expression matches literal script text
V26="$(mk_mutant zrest-probes-pairs 's/^  \[\[ "\$ph" != redirects-dns \]\] || pairs=/  pairs=/')"
red "V26 (D33) zone-rest probes the redirect pairs too" "$V26" chk_zrest_apply_ok '^(pair-probed|rc:1)$' setup_zone_rest_apply
# D13: the apply-failed probe's 60 s ceiling, function level (virtual clock, no wall time).
F1="$(mk_mutant applyfail-no-ceiling 's/^probe_partial_apply() { verify_live 60; }$/probe_partial_apply() { verify_live; }/')"
r=1; n="$(fn_passes "$F1" probe_partial_apply)"; [[ "$n" == 12 ]] && r=0
verdict "$r" "F1 (D13) the apply-failed probe without its 60 s ceiling polls the full budget: RED as required (passes $n, pristine 7)"
# shellcheck disable=SC2016 # sed expression matches literal script text
F2="$(mk_mutant ceiling-inverted 's/if \[\[ -n "\${1:-}" && "\$1" -lt "\$dl" \]\]/if [[ -n "${1:-}" \&\& "$1" -gt "$dl" ]]/')"
r=1; n="$(fn_passes "$F2" probe_partial_apply)"; [[ "$n" == 12 ]] && r=0
verdict "$r" "F2 (D13) the ceiling comparison inverted (-gt): RED as required (passes $n, pristine 7)"
# shellcheck disable=SC2016 # sed expression matches literal script text
V11="$(mk_mutant probe-rc-dropped 's/^  \[\[ "\$rc" -eq 0 \]\] || printf . e=%s. "\$rc"$/  :/')"
red "V11 probe() drops curl's exit code (a timeout reads as a bare 000)" "$V11" chk_curl_rc '^(no-rc-item|rc:0)$' setup_curl_rc
V12="$(mk_mutant one-line-no-format '/^    | LC_ALL=C sed -e .s\/\\x/d')"
red "V12 one_line without the bidi/format-character strip" "$V12" chk_reason_bidi '^not-stripped$' setup_reason_bidi
# shellcheck disable=SC2016 # sed expression matches literal script text
V13="$(mk_mutant obs-no-closed-set '/^  r="\$(printf .%s. "\$1" | one_line /s/ | LC_ALL=C tr -c [^|]*|/ |/')"
red "V13 obs_line without the printable-ASCII closed set" "$V13" chk_obs_ascii '^not-ascii$' setup_obs_ascii
# shellcheck disable=SC2016 # sed expression matches literal script text
V3="$(mk_mutant no-forget-field 's/ "\$fx"$//')"
red "V3 a post-forget gate refusal without the forget=committed field" "$V3" chk_gate_blocks_apply '^no-forget-field$' setup_refuse_apply

# Guard 1 (job half) and Guard 2: each mutant of the read, the bound or the re-read reds its case.
# shellcheck disable=SC2016 # sed expressions match literal script text
{
G13="$(mk_mutant read-before-plan 's/^  tf_env terraform plan /  read_live_records "$W\/live-records.json"\n&/' 's/^    read_live_records "\$live" || live=""$/    :/')"
G14="$(mk_mutant skip-read-noop 's/^  if \[\[ "\$MIGRATE_PHASE" == redirects-dns || "\$MIGRATE_PHASE" == tunnel \]\]; then # read every pinned record$/  if [[ "$MIGRATE_PHASE" == redirects-dns || "$MIGRATE_PHASE" == tunnel ]] \&\& jq -e "any(.resource_changes[]; .change.actions == [\\"update\\"])" "$W\/tfplan.json" >\/dev\/null; then/')"
G21="$(mk_mutant gate-three-args 's/ "\$W\/pre-plan-state.json" "\$live")"; rc=\$?$/ "$W\/pre-plan-state.json")"; rc=$?/')"
R1="$(mk_mutant no-reread-ok 's/^    reread_records || {$/    true || {/')"
R2="$(mk_mutant no-reread-af '/^    \[\[ "\$NORM_COUNT" -eq 0 \]\] || { reread_records/d')"
R3="$(mk_mutant reread-unread-ok 's/^    if \[\[ "\$t" == unreadable \]\]; then unread+=",\$a"; else/    if [[ "$t" == unreadable ]]; then :; else/')"
R4="$(mk_mutant reread-first-only 's/^  done <<<"\$d" # every differing record$/  break; done <<<"$d"/')"
R5="$(mk_mutant notfound-retried 's/\[\[ "\$code" == 200 || "\$code" == 404 \]\]/[[ "$code" == 200 ]]/')"
R6="$(mk_mutant reread-before-apply 's/^  printf .%s phase=%s mode=apply applying=true.n. "\$P" "\$MIGRATE_PHASE"$/  read_live_records "$W\/extra.json" || :\n&/')"
R7="$(mk_mutant no-bound 's/^    bound=(timeout --foreground -s INT "\$remaining")$/    bound=()/')"
R8="$(mk_mutant no-foreground 's/^    bound=(timeout --foreground -s INT /    bound=(timeout -s INT /')"
R9="$(mk_mutant probe-before-reread 's/^    \[\[ "\$NORM_COUNT" -eq 0 \]\] || { reread_records/    probe_partial_apply || :\n&/')"
R10="$(mk_mutant no-budget-refuse '/^    ((remaining >= APPLY_MIN_START)) || refuse apply-budget-exhausted/d')"
R11="$(mk_mutant bound-zone-rest 's/^  if ((\${#REPLACE_ARGS\[@\]} == 0)); then$/  if true; then/')"
Q1="$(mk_mutant bound-on-norm-count 's/^  if ((\${#REPLACE_ARGS\[@\]} == 0)); then$/  if [[ "$NORM_COUNT" -gt 0 ]]; then/')"
Q2="$(mk_mutant no-start-floor 's/^    ((remaining >= APPLY_MIN_START)) ||/    ((remaining > 0)) ||/')"
F6="$(mk_mutant bound-full-deadline 's/^    bound=(timeout --foreground -s INT "\$remaining")$/    bound=(timeout --foreground -s INT "$APPLY_DEADLINE")/')"
R21M="$(mk_mutant no-int-text '/^    if ((rc == 124 && \${#bound\[@\]} > 0)); then msg+=/d')"
HW="$(mk_mutant halt-no-wrong-value 's/^    \*differs=\*) printf .*$/    *differs=*) : ;;/')"
HN="$(mk_mutant halt-no-unread 's/^    \*unreadable=\*) printf .*$/    *unreadable=*) : ;;/')"
HF="$(mk_mutant halt-no-failing '/^  \[\[ "\$2" != failing=\* \]\] || printf /d')"
HA="$(mk_mutant halt-af-no-reread 's/\$(halt_pointer "\$rr" "\$vf")/$(halt_pointer "" "$vf")/')"
HR="$(mk_mutant halt-rr-no-reread 's/\$(halt_pointer "\$REREAD" "\$vf")/$(halt_pointer "" "$vf")/')"
R17M="$(mk_mutant mixed-drops-unread 's/REREAD="differs=\${differ#,}\${unread:+;unreadable=\${unread#,}}"/REREAD="differs=${differ#,}"/')"
R16M="$(mk_mutant count-failure-ignored 's/^  if ((gc > 1)) || \[\[ ! "\$NORM_COUNT" =~ \^\[0-9\]+\$ \]\]; then$/  if false; then/')"
R18M="$(mk_mutant reread-pins-unguarded '/^    || { REREAD="unreadable=all-pinned-records"; return 1; }$/d' 's/^  pins="\$(cf_account_migrate_record_pins "\$MIGRATE_PHASE")" && \[\[ -n "\$pins" \]\] \\$/  pins="$(cf_account_migrate_record_pins "$MIGRATE_PHASE")"/')"
R8D="$(mk_mutant pause-not-doubled '/^      pause=\$((pause \* 2))$/d')"
R8C="$(mk_mutant pause-not-cut 's/^      sleep "\$((pause < left ? pause : left))"$/      sleep "$pause"/')"
Q7A="$(mk_mutant plan-no-tf-line 's/"\${REPLACE_ARGS\[@\]}"} 2>&1 | tf_redact_random_ids | tf_line$/"${REPLACE_ARGS[@]}"} 2>\&1 | tf_redact_random_ids/')"
Q7B="$(mk_mutant apply-no-tf-line 's#"\$W/tfplan" 2>&1 | tf_redact_random_ids | tf_line$#"$W/tfplan" 2>\&1 | tf_redact_random_ids#')"
Q7C="$(mk_mutant plan-window-open '0,/^  printf .\\n::%s::\\n. "\$tok"$/{/^  printf .\\n::%s::\\n. "\$tok"$/d}')"
Q7D="$(mk_mutant apply-window-closed-early 's/^  tf_env \${bound\[@\]+"\${bound\[@\]}"} terraform apply /  printf "::%s::\\n" "$tok"\n&/')"
Q7E="$(mk_mutant tf-line-keeps-cr "s/-e 's.\\\\r. .g' //")"
Q7F="$(mk_mutant plan-token-unchecked 's/^  tok="\$(cmd_token)" || { printf .*$/  tok="$(cmd_token)"/')"
Q7G="$(mk_mutant apply-token-unchecked 's/^  tok="\$(cmd_token)" || refuse setup .*$/  tok="$(cmd_token)"/')"
F7A="$(mk_mutant read-no-noproxy "s/^  r=\"\$(curl --disable --noproxy '\*' -sS --max-time 5/  r=\"\$(curl --disable -sS --max-time 5/")"
F7B="$(mk_mutant read-no-disable 's/^  r="\$(curl --disable /  r="$(curl /')"
F7C="$(mk_mutant read-no-max-time 's/ -sS --max-time 5 -w / -sS -w /')"
F7D="$(mk_mutant read-no-status "s/ --max-time 5 -w '.n%{http_code}' --config - / --max-time 5 --config - /")"
F7S="$(mk_mutant read-short-deadline 's/LIVE_READ_DEADLINE=90/LIVE_READ_DEADLINE=8/')"
F7T="$(mk_mutant read-no-outer-timeout 's/LIVE_READ_DEADLINE=90/LIVE_READ_DEADLINE=8/' 's/^    timeout -k 5 "\$((left - 5))" "\${TF_ENV\[@\]}" bash -c /    "${TF_ENV[@]}" bash -c /')"
R12="$(mk_mutant reuse-read-dir 's/^  dir="\$(mktemp -d "\$W\/live\.XXXXXX")" || return 1$/  dir="$W\/live.fixed"; mkdir -p "$dir" || return 1/')"
R13="$(mk_mutant no-token-guard '/^case "\$t" in ""|\*\[!A-Za-z0-9\._~+\/=-\]\*) exit 3 ;; esac$/d')"
R14="$(mk_mutant retry-after-guard '/^    \[\[ "\$rc" -ne 3 \]\] || break$/d')"
Q7H="$(mk_mutant apply-closer-no-newline '/terraform apply -no-color/,/^  printf .\\n::%s::\\n. "\$tok"$/s/^  printf .\\n::%s::\\n. "\$tok"$/  printf "::%s::\\n" "$tok"/')"
Q2H="$(mk_mutant floor-350 's/APPLY_MIN_START=300/APPLY_MIN_START=350/')"
Q2L="$(mk_mutant floor-200 's/APPLY_MIN_START=300/APPLY_MIN_START=200/')"
TA="$(mk_mutant af-tail-always 's/^    if \[\[ -n "\$rr" && "\$rr" != reread=ok \]\]; then$/    if false; then/')"
TB="$(mk_mutant af-tail-lost-on-ok 's/^    if \[\[ -n "\$rr" && "\$rr" != reread=ok \]\]; then$/    if [[ -n "$rr" ]]; then/')"
TC="$(mk_mutant gate-differs-unclassed 's/^  ((d == 0)) || return 3$/  :/')"
TD="$(mk_mutant gate-unread-unclassed 's/^  ((n == 0 || u != n)) || return 4$/  :/')"
TE="$(mk_mutant gate-unread-any-line 's/^  ((n == 0 || u != n)) || return 4$/  ((u == 0)) || return 4/')"
TF="$(mk_mutant gate-unread-first 's/^  ((d == 0)) || return 3$/  ((u == 0)) || return 4\n&/')"
TG="$(mk_mutant gate-text-ignores-class 's/nothing was applied\.\$(gate_next "\$rc" "\$fg" "\$fk")/nothing was applied.${fg}/')"
TH="$(mk_mutant rehearsal-text-ignores-class 's/nothing was written\$(gate_next "\$rc" "" ".")/nothing was written/')"
}
red "G1-13 the read moved before terraform plan" "$G13" chk_norm_rehearsal '^read-before-plan$' setup_norm_rehearsal
red "G1-14 the read skipped on an all-no-op plan" "$G14" chk_noop_clean '^gets:0$' setup_noop_clean
red "G1-21 the gate called with three arguments" "$G21" chk_noop_differs '^applied$' setup_noop_differs
red "G2-1 no re-read after a clean apply" "$R1" chk_norm_differs '^rc:0$' setup_norm_differs
red "G2-2 no re-read on apply-failed" "$R2" chk_norm_af_differs '^no-field$' setup_norm_af_differs
red "G2-3 an unread record reads as clean" "$R3" chk_norm_unread '^rc:0$' setup_norm_unread
red "G2-4 the re-read stops at the first differing record" "$R4" chk_norm_differs2 '^one-member$' setup_norm_differs2
red "G2-5 a 404 treated as retryable" "$R5" chk_norm_404 '^(no-field|retried)$' setup_norm_404
red "G2-6 the re-read run before the apply" "$R6" chk_norm_apply '^pre:52$' setup_norm_apply
red "G2-7 the apply bound removed" "$R7" chk_norm_apply '^no-bound$' setup_norm_apply
red "G2-8 the bound without --foreground" "$R8" chk_norm_apply '^no-bound$' setup_norm_apply
red "G2-9 the partial-apply probe before the re-read" "$R9" chk_norm_af '^probe-before-reread$' setup_norm_af
red "G2-10 the no-budget refusal removed" "$R10" chk_norm_nobudget '^(applied|applying-line|not-refused)$' setup_norm_nobudget
red "G2-11 a zone-rest apply bounded" "$R11" chk_zrest_noread '^bounded$' setup_zone_rest_apply
red "G2-12 the re-read reuses the pre-gate responses" "$R12" chk_norm_doppler '^rc:0$' setup_norm_doppler
red "G2-13 the token-shape guard removed" "$R13" chk_norm_badtoken '^curl-called$' setup_norm_badtoken
red "G2-14 retrying after the guard's exit 3" "$R14" chk_norm_badtoken '^attempts:5$' setup_norm_badtoken
red "Q1m the bound keyed on NORM_COUNT again leaves a no-record apply unbounded" "$Q1" chk_noop_clean '^unbounded$' setup_noop_clean
red "Q2m the 300 s start floor removed" "$Q2" chk_norm_nobudget '^(applied|applying-line|not-refused)$' setup_norm_s900
red "F6m the bound is the full deadline, not what is left of it" "$F6" chk_norm_s700 '^bound:1100$' setup_norm_s700
red "R21m the message no longer names the INT" "$R21M" chk_norm_124 '^no-int-text$' setup_norm_124
red "R1a a difference loses the wrong-value pointer" "$HW" chk_h_rr_diff '^no-W$' setup_norm_differs
red "R1b an unreadable re-read loses the No completed re-read pointer" "$HN" chk_h_rr_unread '^no-N$' setup_norm_unread
red "R4a failing= loses the verify-failed sentence" "$HF" chk_h_rr_diff_f '^no-F$' setup_norm_differs_failing
red "R1c apply-failed does not pass its re-read to the pointer" "$HA" chk_h_af_diff '^no-W$' setup_norm_af_differs
red "R4b reread-failed does not pass its re-read to the pointer" "$HR" chk_h_rr_unread '^no-N$' setup_norm_unread
red "R17m a mixed re-read drops the unreadable record" "$R17M" chk_h_rr_mixed '^no-field$' setup_norm_mixed
red "R16m a failed count is not refused (the re-read is silently off)" "$R16M" chk_norm_grepfail '^(applied|rc:0)$' setup_norm_grepfail
r=1; v="$(fn_reread "$R18M")"; [[ "$v" == "rc=1 reread=unreadable=" ]] && r=0
verdict "$r" "R18m the unguarded pin lookup yields an empty unreadable= list: RED as required ($v)"
r=1; v="$(fn_read "$R8D" 0)"; [[ "$v" == "5 5 5 5 attempts=5 elapsed="* ]] && r=0
verdict "$r" "R8m the pause no longer doubles: RED as required ($v)"
r=1; v="$(fn_read "$R8C" 20)"; e="${v##*elapsed=}"; [[ "$e" =~ ^[0-9]+$ && "$e" -gt 90 ]] && r=0
verdict "$r" "R8n the pause is not cut to the deadline, and the read overruns 90 s: RED as required ($v)"
red "Q7a the plan pipeline loses tf_line" "$Q7A" chk_tf_window '^cr$' setup_tf_hostile
red "Q7b the apply pipeline loses tf_line" "$Q7B" chk_tf_window '^cr$' setup_tf_hostile
red "Q7c the plan's window is never closed" "$Q7C" chk_tf_window '^window:(nested|unclosed)$' setup_tf_hostile
red "Q7d the apply's window closes before terraform apply" "$Q7D" chk_tf_window '^window:outside$' setup_tf_hostile
red "Q7e tf_line keeps the CR" "$Q7E" chk_tf_window '^cr$' setup_tf_hostile
red "Q7f the plan runs with no token" "$Q7F" chk_tok_plan '^planned$' setup_tok_plan
red "Q7g the apply runs with no token" "$Q7G" chk_tok_apply '^(applied|applying-line)$' setup_tok_apply
r=1; [[ "$(gate_call_arity "$PRISTINE")" == 4 && "$(gate_call_arity "$G21")" == 3 ]] && r=0
verdict "$r" "U8 the job's redirects-dns/tunnel gate call passes four arguments (static, comments stripped; the three-argument mutant reads 3)"
red "F7a the record GET loses --noproxy" "$F7A" chk_norm_apply '^rc:1$' setup_norm_apply
red "F7b the record GET loses --disable" "$F7B" chk_norm_apply '^rc:1$' setup_norm_apply
red "F7c the record GET loses --max-time" "$F7C" chk_norm_apply '^rc:1$' setup_norm_apply
red "F7d the record GET loses its status line" "$F7D" chk_norm_apply '^rc:1$' setup_norm_apply
RED_BASE="$F7S" red "F7e the record read's doppler run starts under the outer timeout" "$F7T" chk_norm_stall '^no-outer-timeout$' setup_norm_stall
red "Q7h the apply's closer loses its leading newline, so a cut line swallows it" "$Q7H" chk_tf_cut '^window:unclosed$' setup_tf_cut
red "Q2h a 350 s floor refuses the 760 s row" "$Q2H" chk_norm_s760 '^rc:1$' setup_norm_s760
red "Q2l a 200 s floor lets the 840 s row start" "$Q2L" chk_norm_nobudget '^(applied|applying-line|not-refused)$' setup_norm_s840
red "T-a the fix-forward sentence printed on a differing re-read" "$TA" chk_t_diff '^has-fix-forward$' setup_norm_af_differs
red "T-b the fix-forward sentence lost on reread=ok" "$TB" chk_t_ok '^no-tail$' setup_norm_af
red "T-c a gate difference is not classed" "$TC" chk_gr_differs '^has-fix-forward$' setup_gr_differs
red "T-d an unreadable-only gate refusal is not classed" "$TD" chk_gr_unread '^has-fix-forward$' setup_gr_unread
red "T-e one unreadable line classes a refusal that has another REFUSE" "$TE" chk_gr_today '^msg$' setup_gr_other
red "T-f unreadable outranks a difference" "$TF" chk_gr_differs '^msg$' setup_gr_mixed
red "T-g the gate-refused text ignores the class" "$TG" chk_gr_differs '^has-fix-forward$' setup_gr_differs
red "T-h the rehearsal-refused text ignores the class" "$TH" chk_rh_differs '^msg$' setup_rh_differs

# --- Stub refusals ---------------------------------------------------------------
# --- Tunnel phase (PR2) ---------------------------------------------------------------
# The real gate and job over a mirror whose pre-delete is a contract stub: the real script's behaviour
# is pinned in cf-tunnel-host-predelete.test.sh, and its committed pin list is empty.
printf '\n[tunnel] pre-delete, plan, live deploy token, apply, CI-SSH sync\n'
MT="$SBX/mirror-tunnel"
mkdir -p "$MT/apps/web-platform/infra/scripts" || exit 2
ln -s "$REPO/.github" "$MT/.github"; ln -s "$REPO/tests" "$MT/tests"
ln -s "$HERE/scripts/cf-account-migration-complete.sh" "$MT/apps/web-platform/infra/scripts/cf-account-migration-complete.sh"
ln -s "$HERE/cf-account-migration-imports.tf" "$MT/apps/web-platform/infra/cf-account-migration-imports.tf"
# The gate reads the committed Access include blocks beside the imports file.
ln -s "$HERE/tunnel.tf" "$MT/apps/web-platform/infra/tunnel.tf"
cat >"$MT/apps/web-platform/infra/scripts/cf-tunnel-host-predelete.sh" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
D="${STUB_DIR:?}"
b=none; [[ "${CF_API_TOKEN:-}" != tok-cf_api_token ]] || b=live
printf 'predelete %s bearer=%s\n' "$*" "$b" >>"$D/calls.log"
if [[ -f "$D/mode.predelete" ]]; then printf 'cf-tunnel-host-predelete verdict=refuse reason=record-mismatch\n'; exit 1; fi
exit 0
STUB
chmod +x "$MT/apps/web-platform/infra/scripts/cf-tunnel-host-predelete.sh"
deploy_token_fixture() { # <dir> [<code>] [<name>] [<hours to expiry>]
  local e; e="$(date -u -d "+${4:-8700} hours" +%Y-%m-%dT%H:%M:%SZ)"
  { printf '%s\n' "${2:-200}"
    jq -nc --arg id "$DT" --arg n "${3:-github-actions-deploy}" --arg e "$e" --arg s "$SENTINEL" \
      '{success:true,result:{id:$id,name:$n,expires_at:$e,client_id:$s}}'
  } >"$1/cf.accounts_${NA}_access_service_tokens_${DT}"
}
# tmark <file> [<content>]: write one mode or env file into the current case dir.
tmark() {
  local f="$SBX/runs/${LAST_D##*/}/$1"
  printf '%s' "${2-}" >"$f"
}
tunnel_case() { # <label> <rehearsal>
  new_case "tun-$1" tunnel "$2" || exit 2
  remote_state "$LAST_D/remote.tfstate" "$NZ" "$NA"
  tmark env.extra "GITHUB_WORKSPACE=$MT"$'\n'"DOPPLER_TOKEN_WRITE=stub-write"$'\n'
  deploy_token_fixture "$LAST_D"
  # The app record import plans the provider's import-normalize update, like every record import.
  jq '(.resource_changes[] | select(.address == "cloudflare_record.app") | .change) |= (.actions = ["update"]
        | .before = (.after + {allow_overwrite: null, content: null}) | .after_unknown = {})' \
    "$LAST_D/plan.json" >"$LAST_D/p" && mv "$LAST_D/p" "$LAST_D/plan.json"
}
APP_REC_ID=f21d6911cdacb1e109ae31bcfb440e7d
no_leak() { # <dir>: no fixture secret and no write token reached the job's output or terraform
  ! grep -qF "$SENTINEL" "$1/out.txt" "$1/err.txt" && ! grep -q '^WRITE-TOKEN-LEAK' "$1/calls.log" && ! grep -qF stub-write "$1/out.txt" "$1/err.txt"
}
no_apply() { ! grep -q '^terraform\[[a-z]*\] apply' "$1/calls.log"; }

tunnel_case rehearsal true; run_job "$LAST_D" "$PRISTINE"; D_T="$LAST_D"; WHY=""
chk_rehearsal_clean "$D_T"; verdict "$?" "tunnel rehearsal: PASS, no apply, remote serial 7 ($WHY)"
argv_matches "$D_T" local tunnel; verdict "$?" "tunnel rehearsal: plan -target/-replace argv equals the gate's tunnel lists"
r=1; grep -qx -- '-var=cf_migration_import_app=true' "$D_T/plan_args.local" && r=0
verdict "$r" "tunnel plan alone turns the app-record import on"
r=1; grep -qx 'predelete --check-pins bearer=none' "$D_T/calls.log" && [[ "$(grep -c '^predelete ' "$D_T/calls.log")" -eq 1 ]] && r=0
verdict "$r" "tunnel rehearsal grades the pin list only, with no token, and never runs the delete"
r=1; ! grep -q 'terraform\[[a-z]*\] state rm' "$D_T/calls.log" && r=0
verdict "$r" "tunnel rehearsal forgets nothing"
r=1; grep -qx "cf-account-migrate deploy-token id=$DT verdict=ok" "$D_T/out.txt" && no_leak "$D_T" && r=0
verdict "$r" "tunnel rehearsal reads the deploy token live and prints only its UUID and verdict"
r=1; grep -qx 'cf-account-migrate live-read records=1' "$D_T/out.txt" \
  && grep -qx 'cf-account-migrate import-normalize count=1' "$D_T/out.txt" \
  && [[ "$(rec_gets "$D_T" pre "$APP_REC_ID")" == 1 && "$(rec_gets "$D_T" pre)" == 1 ]] \
  && before "$D_T" '^terraform\[local\] plan' '^cf-record-get' && r=0
verdict "$r" "tunnel rehearsal: the app record is read live after the plan and admitted as its one import-normalize update"
r=1; ! grep -q 'tok-' "$D_T/curl-argv.log" && r=0
verdict "$r" "the deploy-token read carries its bearer on stdin config, never argv"
r=1; ! grep -q -- 'cf_migration_import_app' "$D_REH/plan_args.local" && r=0
verdict "$r" "a redirects-dns plan does not set the app-record import"

new_case tun-real-pins tunnel true; remote_state "$LAST_D/remote.tfstate" "$NZ" "$NA"; deploy_token_fixture "$LAST_D"
run_job "$LAST_D" "$PRISTINE"
r=1; refused_for "$LAST_D" predelete-refused && grep -q 'cf-tunnel-host-predelete verdict=refuse reason=pins-missing' "$LAST_D/out.txt" \
  && grep -q 'phase=tunnel verdict=PASS' "$LAST_D/out.txt" && no_apply "$LAST_D" && r=0
verdict "$r" "the committed empty pin list refuses the rehearsal, after showing the gate's PASS"

tunnel_case apply false; run_job "$LAST_D" "$PRISTINE"; D_TA="$LAST_D"
r=1; [[ "$(rc_of "$D_TA")" == 0 ]] && grep -qx 'cf-account-migrate phase=tunnel mode=apply verdict=PASS applied=true' "$D_TA/out.txt" && r=0
verdict "$r" "tunnel apply: PASS"
r=1; grep -qx 'predelete --apply bearer=live' "$D_TA/calls.log" \
  && [[ "$(line_no "$D_TA" '^predelete --apply')" -lt "$(line_no "$D_TA" 'terraform\[remote\] plan')" ]] \
  && [[ "$(line_no "$D_TA" 'terraform\[remote\] plan')" -lt "$(line_no "$D_TA" 'terraform\[remote\] apply')" ]] && r=0
verdict "$r" "tunnel apply: the pre-delete runs with the provider token, before the plan, and the apply after it"
r=1; ! grep -q 'terraform\[remote\] state rm' "$D_TA/calls.log" && r=0
verdict "$r" "tunnel apply: no state forget"
r=1; [[ "$(rec_gets "$D_TA" pre "$APP_REC_ID")" == 1 && "$(rec_gets "$D_TA" post "$APP_REC_ID")" == 1 ]] \
  && grep -qx 'cf-account-migrate import-normalize reread=ok records=1' "$D_TA/out.txt" \
  && before "$D_TA" '^terraform\[remote\] apply' 'when=post$' && r=0
verdict "$r" "tunnel apply: the app record is re-read after the apply and matches the graded plan"
r=1; [[ "$(cat "$D_TA/dstore.CI_SSH_ACCESS_TOKEN_ID")" == "$SENTINEL-ci_ssh_access_service_token_client_id" \
  && "$(cat "$D_TA/dstore.CI_SSH_ACCESS_TOKEN_SECRET")" == "$SENTINEL-ci_ssh_access_service_token_client_secret" ]] && r=0
verdict "$r" "tunnel apply: both CI-SSH keys hold the new outputs, byte-exact"
r=1; [[ "$(line_no "$D_TA" 'terraform\[remote\] apply')" -lt "$(line_no "$D_TA" '^doppler-set CI_SSH_ACCESS_TOKEN_ID')" ]] \
  && [[ "$(grep -c 'ci-ssh-sync key=.* verdict=ok' "$D_TA/out.txt")" -eq 2 ]] && r=0
verdict "$r" "tunnel apply: the sync runs after the apply and verifies both keys"
no_leak "$D_TA"; verdict "$?" "tunnel apply: no secret value or write token in the output, and terraform never inherits the write token"

tunnel_case app-differs false; tmark "recfilter.post.$APP_REC_ID" '.result.ttl = 300'; run_job "$LAST_D" "$PRISTINE"
r=1; refused_for "$LAST_D" import-normalize-reread-failed \
  && grep -qE "reason=import-normalize-reread-failed .*applied=true.* reread=differs=cloudflare_record\.app:ttl" "$LAST_D/out.txt" && r=0
verdict "$r" "tunnel apply: an app record that differs after the apply -> import-normalize-reread-failed applied=true"
tunnel_case app-pre-differs false; tmark "recfilter.pre.$APP_REC_ID" '.result.ttl = 300'; run_job "$LAST_D" "$PRISTINE"
r=1; refused_for "$LAST_D" gate-refused && grep -q 'REFUSE cloudflare_record.app differs from the live record' "$LAST_D/out.txt" && no_apply "$LAST_D" && r=0
verdict "$r" "tunnel apply: an app record that differs before the apply -> gate-refused, nothing applied"
tunnel_case predelete-refused false; tmark mode.predelete; run_job "$LAST_D" "$PRISTINE"
r=1; refused_for "$LAST_D" predelete-refused && ! grep -q 'terraform\[remote\] plan' "$LAST_D/calls.log" && no_apply "$LAST_D" && r=0
verdict "$r" "a refused pre-delete -> reason=predelete-refused, no plan and no apply"
tunnel_case no-write false; tmark env.extra "GITHUB_WORKSPACE=$MT"$'\n'; run_job "$LAST_D" "$PRISTINE"
r=1; refused_for "$LAST_D" doppler-write-token-missing && ! grep -q '^predelete' "$LAST_D/calls.log" && no_apply "$LAST_D" && r=0
verdict "$r" "no DOPPLER_TOKEN_WRITE -> refused before the delete"

for spec in "404:github-actions-deploy:8700:http-404" "200:github-actions-ci-ssh:8700:name-differs" "200:github-actions-deploy:720:expiry-out-of-window"; do
  IFS=: read -r c nm h why <<<"$spec"
  tunnel_case "dt-reh-$why" true; deploy_token_fixture "$LAST_D" "$c" "$nm" "$h"; run_job "$LAST_D" "$PRISTINE"
  r=1; refused_for "$LAST_D" deploy-token-refused && grep -q "deploy-token id=$DT verdict=refuse detail=$why" "$LAST_D/out.txt" && no_apply "$LAST_D" && no_leak "$LAST_D" && r=0
  verdict "$r" "rehearsal: deploy token $why -> reason=deploy-token-refused, its body not printed"
  tunnel_case "dt-app-$why" false; deploy_token_fixture "$LAST_D" "$c" "$nm" "$h"; run_job "$LAST_D" "$PRISTINE"
  r=1; refused_for "$LAST_D" deploy-token-refused && no_apply "$LAST_D" && r=0
  verdict "$r" "apply: deploy token $why -> reason=deploy-token-refused, nothing applied"
done

for m in tfoutput-empty dopplerset dopplercorrupt; do
  tunnel_case "sync-$m" false; tmark "mode.$m"; run_job "$LAST_D" "$PRISTINE"
  r=1; refused_for "$LAST_D" ci-ssh-sync-failed && grep -q 'reason=ci-ssh-sync-failed applied=true' "$LAST_D/out.txt" \
    && grep -q 'verify=tunnel verdict=ok' "$LAST_D/out.txt" && no_leak "$LAST_D" && r=0
  verdict "$r" "CI-SSH sync failure ($m) -> reason=ci-ssh-sync-failed applied=true, after the live probes ran"
done
tunnel_case sync-and-verify false; tmark mode.dopplerset; tmark mode.health; run_job "$LAST_D" "$PRISTINE"
r=1; refused_for "$LAST_D" verify-failed && grep -q 'ci_ssh_sync=failed' "$LAST_D/out.txt" && r=0
verdict "$r" "a failed sync AND a failed probe -> reason=verify-failed, carrying ci_ssh_sync=failed"

printf '\n[forget] the redirects-dns forget, which is the only forget, removes the tunnel slice\n'
# The tunnel phase runs no forget of its own: the real forget script classifies EVERY old-id
# cloudflare_* entry, so the 15 Cloudflare members of the tunnel spec go with redirects-dns. The
# random_id and the two Doppler secrets are not Cloudflare objects and stay, which is why the tunnel
# phase replaces and updates them.
new_case forget-tunnel-slice redirects-dns true
TUN_CF="$(cf_account_migrate_phase_spec tunnel | jq -c '[keys[] | select(startswith("cloudflare_"))]')"
tmark remote.tfstate "$(jq --argjson cf "$TUN_CF" --arg oz "$OZ" --arg oa "$OA" '.show.values.root_module.resources +=
  ([$cf[] | {address: ., mode: "managed", type: split(".")[0], name: "n",
    values: (if test("tunnel_cloudflared|access_service_token|notification_policy") then {account_id: $oa} else {zone_id: $oz} end)}]
   + [{address: "doppler_secret.registry_push_access_token_id", mode: "managed", type: "doppler_secret", name: "n", values: {id: "d1"}},
      {address: "doppler_secret.registry_push_access_token_secret", mode: "managed", type: "doppler_secret", name: "n", values: {id: "d2"}}])' \
  "$LAST_D/remote.tfstate")"
run_job "$LAST_D" "$PRISTINE"
r=1; [[ "$(jq length <<<"$TUN_CF")" -eq 15 ]] && grep -q 'terraform\[local\] state rm argc=17' "$LAST_D/calls.log" && r=0
for a in $(jq -r '.[]' <<<"$TUN_CF"); do grep -qxF "cf-state-migrate address=$a action=rm" "$LAST_D/out.txt" || r=1; done
verdict "$r" "B3: the redirects-dns forget removes all 15 Cloudflare members of the tunnel spec (2 fixture entries + 15)"
r=1; ! grep -qE 'cf-state-migrate address=(random_id|doppler_secret)' "$LAST_D/out.txt" && r=0
verdict "$r" "B3: the forget leaves random_id.tunnel_secret and the registry Doppler secrets in state"

printf '\n[scope probes] cf_api_token is read for the tunnel scopes before anything is written\n'
SVC="accounts_${NA}_access_service_tokens?per_page=1"
tunnel_case scope-paths true; run_job "$LAST_D" "$PRISTINE"
r=1
diff <(sed -n 's/^cf-api-probe \(.*\)$/\1/p' "$LAST_D/calls.log" | sort) <(printf '%s\n' \
  "zones/$NZ/dns_records?per_page=1 token=cf_api_token" "accounts/$NA/cfd_tunnel?per_page=1 token=cf_api_token" \
  "zones/$NZ/access/apps?per_page=1 token=cf_api_token" "accounts/$NA/access/service_tokens?per_page=1 token=cf_api_token" \
  "accounts/$NA/alerting/v3/policies token=cf_api_token" | sort) >/dev/null \
  && grep -qx 'cf-account-migrate preflight=ids verdict=ok tokens=1' "$LAST_D/out.txt" \
  && grep -qx 'cf-account-migrate preflight=token name=cf_api_token@tunnel http=200 source=live' "$LAST_D/out.txt" && r=0
verdict "$r" "tunnel probes its DNS read and the four scopes on the live token when none is staged"
tunnel_case scope-staged true; tmark doppler.inject $'TF_VAR_cf_api_token_next=tok-cf_api_token_next\n'; run_job "$LAST_D" "$PRISTINE"
r=1; [[ "$(grep -c '^cf-api-probe .* token=cf_api_token_next$' "$LAST_D/calls.log")" -eq 4 ]] \
  && grep -q '^cf-api-probe zones/.*/dns_records?per_page=1 token=cf_api_token$' "$LAST_D/calls.log" \
  && grep -qx 'cf-account-migrate preflight=token name=cf_api_token@service-tokens http=200 source=staged' "$LAST_D/out.txt" && r=0
verdict "$r" "a staged CF_API_TOKEN_NEXT answers the four scope probes; the DNS probe stays on the live token"
tunnel_case scope-403 true; tmark doppler.inject $'TF_VAR_cf_api_token_next=tok-cf_api_token_next\n'; tmark "cfpath.$SVC" 403; run_job "$LAST_D" "$PRISTINE"
r=1; refused_for "$LAST_D" token-scope-missing && ! grep -q '^terraform' "$LAST_D/calls.log" \
  && grep -qx 'cf-account-migrate preflight=token name=cf_api_token@service-tokens http=403 source=staged' "$LAST_D/out.txt" && r=0
verdict "$r" "a staged token denied service tokens -> reason=token-scope-missing in the rehearsal, before any terraform call"
new_case scope-rd-403 redirects-dns false; tmark "cfpath.$SVC" 403; run_job "$LAST_D" "$PRISTINE"
r=1; refused_for "$LAST_D" token-scope-missing && ! grep -q 'terraform\[remote\] state rm' "$LAST_D/calls.log" && ! grep -q '^terraform' "$LAST_D/calls.log" && r=0
verdict "$r" "redirects-dns refuses a token too narrow for the tunnel BEFORE its state forget"
tunnel_case scope-503 true; tmark "cfpath.$SVC" 503; run_job "$LAST_D" "$PRISTINE"
r=1; refused_for "$LAST_D" token-unreachable && r=0
verdict "$r" "a scope probe answering 503 is no verdict -> reason=token-unreachable, never token-scope-missing"
new_case scope-zrest zone-rest true; remote_state "$LAST_D/remote.tfstate" "$NZ" "$NA"; run_job "$LAST_D" "$PRISTINE"
r=1; ! grep -q 'cf_api_token@' "$LAST_D/out.txt" && r=0
verdict "$r" "zone-rest, which does not use cf_api_token, runs no scope probe"

printf '\n[tunnel mutants] each new guard is load-bearing\n'
t_mut() { # <label> <sed-expr> <setup-fn>: the mutant must reach an apply the pristine script refused
  local m="$SBX/mut/tun-$CASES.sh"
  sed -e "$2" "$PRISTINE" >"$m"
  if cmp -s "$m" "$PRISTINE" || ! bash -n "$m"; then verdict 1 "$1: the mutation did not land or does not parse"; return; fi
  "$3"; run_job "$LAST_D" "$m"
  r=1; grep -q '^terraform\[remote\] apply' "$LAST_D/calls.log" && r=0
  verdict "$r" "$1: RED without it (the mutant applied)"
}
set_dt_404() { tunnel_case mut-dt false; deploy_token_fixture "$LAST_D" 404; }
set_pd_refused() { tunnel_case mut-pd false; tmark mode.predelete; }
t_mut "M-deploy-token" 's/^    deploy_token_check || return 5$/    :/' set_dt_404
t_mut "M-predelete" 's/^  \[\[ "\$rc" -eq 0 \]\] || refuse predelete-refused .*$/  :/' set_pd_refused

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
EXPECTED_CASES=327
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
