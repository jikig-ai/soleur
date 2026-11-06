#!/usr/bin/env bash
# mint-origin-ca-cert.test.sh -- offline guard for .github/workflows/mint-origin-ca-cert.yml and its body
# scripts/mint-origin-ca-cert.sh (#10479, ADR-321 slice 2).
#
# WHAT THIS PROTECTS. The workflow writes a TLS PRIVATE KEY into a production Doppler config from a public repository. The failures
# that matter: a key, a token or a base64 value in the run log or in a process argv; a write that runs although a guard failed; a
# second mint over a certificate that is not expiring; a half-written pair that boots a container into key/cert mismatch; a
# certificate that does not match its key being published; and a temp file left behind. Layers:
#   A. STATIC, on the parsed workflow: dispatch-only, least permissions, pinned actions, per-step timeouts, the guard job holds no
#      environment and no secret, the mint job's environment is the reviewer-gated one for apply, no terraform, no artifact upload,
#      inputs reach the shell only through env:.
#   B. BEHAVIOUR against stubs (curl, doppler) and a REAL openssl with a throwaway CA that signs the submitted CSR: every guard
#      refusal, plan, apply, the idempotency policy, every Cloudflare and Doppler failure, the compensating restore, the stale
#      guard, and a leak scan over every stream of every scenario (the scan count must equal the scenario count).
#   C. MUTATIONS: remove the policy refusal, the confirm check or the key/cert match in a COPY of the script and require the scenario
#      that depends on it to change from "stops" to "proceeds" (a guard no scenario can see is not a guard).
# Fixtures are synthesized (cq-test-fixtures-synthesized-only): the token-shaped value is built by concatenation.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../../.." && pwd)"
WF="$REPO/.github/workflows/mint-origin-ca-cert.yml"
BODY="${MINT_BODY_UNDER_TEST:-$REPO/scripts/mint-origin-ca-cert.sh}"
export TMPDIR="${TMPDIR:-/var/tmp}"

for t in openssl jq python3 base64 sha256sum shred; do command -v "$t" >/dev/null 2>&1 || { echo "FAIL SETUP: $t unavailable"; exit 1; }; done
python3 -c 'import yaml' 2>/dev/null || { echo "FAIL SETUP: python3 yaml unavailable"; exit 1; }
[[ -f "$WF" && -f "$BODY" ]] || { echo "FAIL SETUP: workflow or body missing"; exit 1; }

TMP="$(mktemp -d "${TMPDIR%/}/mint-origin-ca-test.XXXXXX")" || { echo "FAIL SETUP: mktemp"; exit 1; }
case "$TMP" in /*) ;; *) echo "FAIL SETUP: temp dir not absolute"; exit 1 ;; esac
trap 'rm -rf -- "$TMP"' EXIT

PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1"; [[ -n "${2:-}" ]] && printf '        %s\n' "$2"; return 0; }
eq() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1" "got '${2:0:300}' want '${3:0:300}'"; fi; }
has() { if grep -qF -- "$3" <<< "$2"; then ok "$1"; else bad "$1" "missing '$3'"; fi; }
hasnt() { if grep -qF -- "$3" <<< "$2"; then bad "$1" "unexpected '$3'"; else ok "$1"; fi; }

# INSTRUMENT SELF-TEST: both counters must move before any row is believed.
_p=$PASS; _f=$FAIL; ok "self-test pass" >/dev/null; bad "self-test fail" >/dev/null
if [[ $PASS -eq $((_p + 1)) && $FAIL -eq $((_f + 1)) ]]; then PASS=$_p; FAIL=$_f; else echo "FAIL SETUP: counters do not move"; exit 1; fi

# ------------------------------------------------------------------------------------------------------------------------------
# A. static
WFJSON="$TMP/wf.json"
python3 - "$WF" > "$WFJSON" <<'EOF'
import sys, json, yaml
d = yaml.safe_load(open(sys.argv[1]))
if True in d and "on" not in d: d["on"] = d.pop(True)
print(json.dumps(d))
EOF
echo "A. static"
eq "A1 triggers are workflow_dispatch only" "$(jq -c '.on | keys' "$WFJSON")" '["workflow_dispatch"]'
eq "A2 top-level permissions are contents: read only" "$(jq -c '.permissions' "$WFJSON")" '{"contents":"read"}'
eq "A3 one workflow-wide group, never cancelled" "$(jq -c '.concurrency' "$WFJSON")" '{"group":"mint-origin-ca-cert","cancel-in-progress":false}'
eq "A4 jobs are guard and mint" "$(jq -c '.jobs | keys | sort' "$WFJSON")" '["guard","mint"]'
eq "A5 the guard job holds no environment" "$(jq -r '.jobs.guard.environment // "none"' "$WFJSON")" none
eq "A6 the guard job references no secret" "$(jq -r '[.jobs.guard | .. | strings | select(test("secrets\\."))] | length' "$WFJSON")" 0
has "A7 apply runs on the reviewer-gated environment" "$(jq -r '.jobs.mint.environment' "$WFJSON")" "'apply' && 'web-platform-infra-apply'"
has "A8 plan runs on the no-reviewer Tier-B environment" "$(jq -r '.jobs.mint.environment' "$WFJSON")" "'infra-privileged'"
eq "A9 every job has a timeout" "$(jq -r '[.jobs[] | select(has("timeout-minutes") | not)] | length' "$WFJSON")" 0
eq "A10 every step has a timeout" "$(jq -r '[.jobs[].steps[] | select(has("timeout-minutes") | not)] | length' "$WFJSON")" 0
eq "A11 every third-party action is pinned to a 40-hex SHA" "$(jq -r '[.jobs[].steps[] | .uses // empty | select(startswith("./") | not) | select(test("@[0-9a-f]{40}( |$)") | not)] | length' "$WFJSON")" 0
eq "A12 no run body interpolates an input or a needs output" "$(jq -r '[.jobs[].steps[] | .run // empty | select(test("\\$\\{\\{"))] | length' "$WFJSON")" 0
eq "A13 the mint job loads the tiered credentials through the shared action" "$(jq -r '[.jobs.mint.steps[] | select(.uses == "./.github/actions/infra-credentials")] | length' "$WFJSON")" 1
eq "A14 mint is gated on the guard's go" "$(jq -r '.jobs.mint.if | contains("needs.guard.outputs.go == '"'"'true'"'"'")' "$WFJSON")" true
WFTXT="$(cat "$WF")"
hasnt "A15 no terraform in the workflow" "$(grep -v '^\s*#' "$WF")" "terraform"
hasnt "A16 no artifact upload" "$(grep -v '^\s*#' "$WF")" "upload-artifact"
hasnt "A17 no issues or id-token write" "$WFTXT" "issues: write"
hasnt "A18 no bot-token or PAT step" "$WFTXT" "GH_TOKEN"
BODYCODE="$(grep -v '^\s*#' "$BODY")"
hasnt "A19 the body never traces (set -x)" "$BODYCODE" "set -x"
hasnt "A20 the body holds no terraform command" "$BODYCODE" "terraform "
has "A21 the body never builds a base-URL seam from the environment" "$BODYCODE" 'readonly MC_CF_API="https://api.cloudflare.com/client/v4"'
eq "A22 the body registers the key mask before the first Cloudflare call" "$([[ "$(grep -n 'mc_mask "$(mc_b64 "$MC_TMP/key.pem")"' "$BODY" | head -1 | cut -d: -f1)" -lt "$(grep -n 'mc_cf POST' "$BODY" | head -1 | cut -d: -f1)" ]] && echo yes || echo no)" yes

# ------------------------------------------------------------------------------------------------------------------------------
# B. behaviour
STUBS="$TMP/stubs"; mkdir -p "$STUBS"
CA="$TMP/ca"; mkdir -p "$CA"
openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$CA/ca.key" >/dev/null 2>&1
openssl req -x509 -new -key "$CA/ca.key" -subj "/CN=Test Origin CA" -days 7000 -out "$CA/ca.pem" >/dev/null 2>&1

# Synthesized credentials (built by concatenation so no scanner sees a token-shaped literal).
CF_TOKEN="cfTok""en0123456789ABCDEFGHIJKLMNOPQRSTUV-_x"
DOP_TOKEN="dp.pt.""SYNTHESIZEDPROVIDERTOKEN0123456789abcd"
ZONE="0123456789abcdef0123456789abcdef"

# sign <csr> <days> <host> <out.pem> : the throwaway CA signs the submitted CSR with a SAN and CA:FALSE.
cat > "$STUBS/sign.sh" <<'EOF'
#!/usr/bin/env bash
csr="$1"; days="$2"; host="$3"; out="$4"; ca="$5"
ext="$(mktemp)"; if [[ -n "${STUB_CF_NO_BC:-}" ]]; then printf 'subjectAltName=DNS:%s\n' "$host" > "$ext"; else printf 'subjectAltName=DNS:%s\nbasicConstraints=CA:FALSE\n' "$host" > "$ext"; fi
openssl x509 -req -in "$csr" -CA "$ca/ca.pem" -CAkey "$ca/ca.key" -CAcreateserial -days "$days" -extfile "$ext" -out "$out" >/dev/null 2>&1
rc=$?; rm -f "$ext"; exit $rc
EOF
cat > "$STUBS/curl" <<'EOF'
#!/usr/bin/env bash
# Stub curl: models only the three Cloudflare calls the script makes; anything else exits 6.
echo "ARGV $*" >> "$STUB_LOG"
out=""; method="GET"; body=""; cfg=""; url=""
while (( $# )); do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -X) method="$2"; shift 2 ;;
    -K) cfg="$2"; shift 2 ;;
    -H|-w|--max-time|--retry|--retry-delay|--proto) shift 2 ;;
    --data-binary) body="${2#@}"; shift 2 ;;
    --silent|--tlsv1.2) shift ;;
    *) url="$1"; shift ;;
  esac
done
case "$url" in https://api.cloudflare.com/client/v4/*) path="${url#https://api.cloudflare.com/client/v4}" ;; *) echo "STUB: unexpected URL" >&2; exit 6 ;; esac
grep -qF "Authorization: Bearer $STUB_CF_TOKEN" "$cfg" 2>/dev/null || { printf '{"success":false,"errors":[{"code":9109}]}' > "$out"; printf '401'; exit 0; }
case "$method $path" in
  "GET /user/tokens/verify") printf '{"success":true,"result":{"status":"active"}}' > "$out"; printf '200' ;;
  "GET /certificates?zone_id="*)
    st="${STUB_CF_LIST_STATUS:-200}"
    if [[ "$st" == 200 ]]; then printf '{"success":true,"result":[{"id":"1111","hostnames":["app.soleur.ai"],"expires_on":"2040-01-01 00:00:00 +0000 UTC","revoked_at":null}]}' > "$out"
    else printf '{"success":false,"errors":[{"code":9109,"message":"x"}]}' > "$out"; fi
    printf '%s' "$st" ;;
  "POST /certificates")
    echo POST >> "$STUB_STATE/.posts"
    st="${STUB_CF_CREATE_STATUS:-200}"
    if [[ "$st" != 200 ]]; then printf '{"success":false,"errors":[{"code":1001,"message":"x"}]}' > "$out"; printf '%s' "$st"; exit 0; fi
    csr="$(mktemp)"; jq -r '.csr' "$body" > "$csr"
    if [[ -n "${STUB_CF_WRONG_KEY:-}" ]]; then
      k="$(mktemp)"; openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$k" >/dev/null 2>&1
      openssl req -new -key "$k" -subj "/CN=app.soleur.ai" -out "$csr" >/dev/null 2>&1; rm -f "$k"
    fi
    cert="$(mktemp)"
    bash "$STUB_SIGN" "$csr" "${STUB_CF_DAYS:-5475}" "${STUB_CF_HOST:-app.soleur.ai}" "$cert" "$STUB_CA" || { printf '500'; exit 0; }
    jq -n --rawfile c "$cert" '{success:true,errors:[],result:{id:"7777777777777777",certificate:$c,expires_on:"2041-01-01 00:00:00 +0000 UTC"}}' > "$out"
    rm -f "$csr" "$cert"; printf '200' ;;
  *) echo "STUB: unmodelled call $method $path" >&2; exit 6 ;;
esac
EOF
cat > "$STUBS/doppler" <<'EOF'
#!/usr/bin/env bash
# Stub doppler: names listing, get --plain, set (stdin), delete. State is a directory tree per project/config.
echo "ARGV $*" >> "$STUB_LOG"
[[ "${DOPPLER_TOKEN:-}" == "$STUB_DT" ]] || { echo "Unauthorized" >&2; exit 1; }
args=("$@"); p=""; c=""; names_only=0; pos=(); i=0
while (( i < ${#args[@]} )); do
  a="${args[i]}"
  case "$a" in -p) p="${args[i+1]}"; i=$((i+1)) ;; -c) c="${args[i+1]}"; i=$((i+1)) ;; --only-names) names_only=1 ;; --plain|--no-interactive|--yes) ;; *) pos+=("$a") ;; esac
  i=$((i+1))
done
d="$STUB_STATE/$p/$c"; mkdir -p "$d"
[[ "${pos[0]:-}" == secrets ]] || exit 64
if (( names_only )); then ls "$d"; exit 0; fi
case "${pos[1]:-}" in
  get)    [[ -f "$d/${pos[2]}" ]] || { echo "Could not find requested secret" >&2; exit 1; }; cat "$d/${pos[2]}"; echo ;;
  set)    n="${pos[2]}"; v="$(cat)"
          if [[ "$n" == "${STUB_FAIL_SET:-}" && ! -e "$STUB_STATE/.failed" ]]; then touch "$STUB_STATE/.failed"; exit 1; fi
          if [[ "$n" == "${STUB_CORRUPT_SET:-}" && ! -e "$STUB_STATE/.corrupted" ]]; then touch "$STUB_STATE/.corrupted"; v="X$v"; fi
          printf '%s' "$v" > "$d/$n" ;;
  delete) rm -f "$d/${pos[2]}" ;;
  *) exit 64 ;;
esac
EOF
chmod +x "$STUBS/curl" "$STUBS/doppler"

SC=0
reset_env() { # fresh Doppler state with the Cloudflare credential and an unrelated prd secret
  rm -rf "$TMP/state" "$TMP/rt"; mkdir -p "$TMP/state/soleur/prd_terraform" "$TMP/state/soleur/prd" "$TMP/rt"
  printf '%s' "$CF_TOKEN" > "$TMP/state/soleur/prd_terraform/CF_API_TOKEN_ORIGIN_CA"
  printf '%s' "$ZONE" > "$TMP/state/soleur/prd_terraform/CF_ZONE_ID"
  printf 'unrelated' > "$TMP/state/soleur/prd/SOME_OTHER_SECRET"
  : > "$TMP/stub.log"; : > "$TMP/summary.md"; : > "$TMP/gh_out"
}
# mkexisting <days> : seed prd with a valid pair issued by the throwaway CA, <days> of validity.
mkexisting() {
  local days="$1" k="$TMP/ex.key" r="$TMP/ex.csr" ce="$TMP/ex.pem"
  openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$k" >/dev/null 2>&1
  openssl req -new -key "$k" -subj "/CN=app.soleur.ai" -out "$r" >/dev/null 2>&1
  bash "$STUBS/sign.sh" "$r" "$days" app.soleur.ai "$ce" "$CA"
  base64 -w0 < "$k" > "$TMP/state/soleur/prd/ORIGIN_TLS_KEY_B64"
  base64 -w0 < "$ce" > "$TMP/state/soleur/prd/ORIGIN_TLS_CERT_B64"
  :
}
masks_of() { printf '::add-mask::%s\n' "$(cat "$1")" > "$TMP/mask.expect"; grep -cxFf "$TMP/mask.expect" "$2" | tr -d ' '; }
posts() { if [[ -f "$TMP/state/.posts" ]]; then wc -l < "$TMP/state/.posts" | tr -d ' '; else echo 0; fi; }
state_sig() { (cd "$TMP/state/soleur/prd" && for f in *; do printf '%s=%s\n' "$f" "$(sha256sum < "$f" | cut -c1-16)"; done); }
# run_mint <mode> <replace> [extra env assignments...] -> OUT, RC. Every stream is captured and leak-scanned.
run_mint() {
  local mode="$1" replace="$2"; shift 2
  SC=$((SC + 1))
  OUT="$(env -i PATH="$STUBS:$PATH" HOME="$TMP" TMPDIR="$TMP" RUNNER_TEMP="$TMP/rt" GITHUB_STEP_SUMMARY="$TMP/summary.md" \
    STUB_LOG="$TMP/stub.log" STUB_STATE="$TMP/state" STUB_CF_TOKEN="$CF_TOKEN" STUB_DT="$DOP_TOKEN" STUB_SIGN="$STUBS/sign.sh" STUB_CA="$CA" \
    TF_VAR_doppler_token_tf="$DOP_TOKEN" MINT_MODE="$mode" MINT_REPLACE="$replace" MINT_GUARD_EPOCH="${GE:-$(date -u +%s)}" "$@" \
    bash "${RUN_BODY:-$BODY}" run 2>&1)"; RC=$?
  printf '%s\n' "$OUT" > "$TMP/out.$SC"; cp "$TMP/stub.log" "$TMP/argv.$SC"
}
leak_scan() { # over every captured stream: nothing secret outside ::add-mask:: lines; no secret in any argv
  local n=0 bad_n=0 i f body
  for ((i=1; i<=SC; i++)); do
    [[ -f "$TMP/out.$i" ]] || continue
    n=$((n+1))
    body="$(grep -v '^::add-mask::' "$TMP/out.$i")"
    for s in "$CF_TOKEN" "$DOP_TOKEN" "BEGIN PRIVATE KEY" "BEGIN EC PRIVATE KEY" "BEGIN CERTIFICATE"; do
      if grep -qF -- "$s" <<< "$body"; then bad_n=$((bad_n+1)); printf '        leak: scenario %s output holds a protected string\n' "$i"; fi
    done
    if grep -E -q '[A-Za-z0-9+/=]{80,}' <<< "$body"; then bad_n=$((bad_n+1)); printf '        leak: scenario %s output holds an 80+ char base64-like run\n' "$i"; fi
    if grep -qF -- "$CF_TOKEN" "$TMP/argv.$i" || grep -qF -- "$DOP_TOKEN" "$TMP/argv.$i"; then bad_n=$((bad_n+1)); printf '        leak: scenario %s argv holds a token\n' "$i"; fi
    if grep -E -q '[A-Za-z0-9+/=]{120,}' "$TMP/argv.$i"; then bad_n=$((bad_n+1)); printf '        leak: scenario %s argv holds a long base64-like value\n' "$i"; fi
  done
  eq "B-leak no protected string in any stream or argv of $n scenarios" "$bad_n" 0
  eq "B-leak the scan covered every scenario" "$n" "$SC"
}

echo "B. guard"
guard() { # name value env...
  GOUT="$(env -i PATH="$PATH" GITHUB_OUTPUT="$TMP/gh_out" GITHUB_EVENT_NAME=workflow_dispatch GITHUB_RUN_ATTEMPT=1 GITHUB_REF=refs/heads/main \
    GITHUB_ACTOR=deruelle GITHUB_TRIGGERING_ACTOR=deruelle INPUT_MODE=plan INPUT_REPLACE=false INPUT_CONFIRM= MINT_NOW=1800000000 "$@" bash "$BODY" guard 2>&1)"; GRC=$?
}
D="$(date -u -d @1800000000 +%F)"
: > "$TMP/gh_out"; guard
eq "G1 plan passes with no confirm" "$GRC" 0; has "G1b go=true is written" "$(cat "$TMP/gh_out")" "go=true"; has "G1c guard_epoch is written" "$(cat "$TMP/gh_out")" "guard_epoch=1800000000"
guard GITHUB_EVENT_NAME=push;                      eq "G2 a push event is refused" "$GRC" 1; has "G2b verdict" "$GOUT" "verdict=event_refused"
guard GITHUB_RUN_ATTEMPT=2;                        eq "G3 a re-run is refused" "$GRC" 1; has "G3b verdict" "$GOUT" "verdict=rerun_refused"
guard GITHUB_REF=refs/heads/feat-x;                eq "G4 a non-main ref is refused" "$GRC" 1; has "G4b verdict" "$GOUT" "verdict=ref_refused"
guard GITHUB_ACTOR=github-actions[bot];            eq "G5 a bot actor is refused" "$GRC" 1; has "G5b verdict" "$GOUT" "verdict=actor_refused"
guard GITHUB_TRIGGERING_ACTOR=mallory;             eq "G6 a non-owner triggering actor is refused" "$GRC" 1; has "G6b verdict" "$GOUT" "verdict=actor_not_owner"
guard GITHUB_ACTOR=;                               eq "G7 an empty actor is refused" "$GRC" 1
guard INPUT_MODE=rotate;                           eq "G8 an unknown mode is refused" "$GRC" 1; has "G8b verdict" "$GOUT" "verdict=inputs_invalid"
guard INPUT_REPLACE=maybe;                         eq "G9 a non-boolean replace is refused" "$GRC" 1
guard INPUT_MODE=apply;                            eq "G10 apply without confirm is refused" "$GRC" 1; has "G10b verdict" "$GOUT" "verdict=confirm_mismatch"
guard INPUT_MODE=apply INPUT_CONFIRM="MINT-ORIGIN-CA-2001-01-01"; eq "G11 apply with another day's confirm is refused" "$GRC" 1
guard INPUT_MODE=apply INPUT_REPLACE=true INPUT_CONFIRM="MINT-ORIGIN-CA-$D"; eq "G12 replace=true with the plain confirm is refused" "$GRC" 1
guard INPUT_MODE=apply INPUT_CONFIRM="MINT-ORIGIN-CA-REPLACE-$D"; eq "G13 replace=false with the REPLACE confirm is refused" "$GRC" 1
guard INPUT_MODE=apply INPUT_CONFIRM="mint-origin-ca-$D";  eq "G14 the confirm is case-sensitive" "$GRC" 1
: > "$TMP/gh_out"; guard INPUT_MODE=apply INPUT_CONFIRM="MINT-ORIGIN-CA-$D"; eq "G15 apply with the exact confirm passes" "$GRC" 0; has "G15b mode=apply" "$(cat "$TMP/gh_out")" "mode=apply"
guard INPUT_MODE=apply INPUT_REPLACE=true INPUT_CONFIRM="MINT-ORIGIN-CA-REPLACE-$D"; eq "G16 replace with the REPLACE confirm passes" "$GRC" 0
hasnt "G17 a refusal never echoes the expected confirm" "$(guard INPUT_MODE=apply; printf '%s' "$GOUT")" "MINT-ORIGIN-CA-$D"

echo "B. plan"
reset_env; before="$(state_sig)"; run_mint plan false
eq "P1 plan on an empty prd exits 0" "$RC" 0; has "P1b verdict plan_ok" "$OUT" "verdict=plan_ok"; has "P1c nothing created" "$OUT" "nothing_created=true"
has "P1d reports the existing state" "$OUT" "existing state=absent"; has "P1e reports the CSR facts" "$OUT" "csr ok subject=CN=app.soleur.ai key=ec"
has "P1f lists the existing active certificates (serial only)" "$OUT" "active_certs_for_host=1"
eq "P2 plan sends no POST" "$(posts)" 0
eq "P3 plan writes nothing to prd" "$(state_sig)" "$before"
eq "P4 plan makes no Doppler set or delete" "$(grep -cE 'ARGV secrets (set|delete)' "$TMP/stub.log")" 0
eq "P5 the private temp dir is gone" "$(ls -A "$TMP/rt" | wc -l | tr -d ' ')" 0

echo "B. apply"
reset_env; run_mint apply false
eq "A1 apply on an empty prd exits 0" "$RC" 0; has "A1b verdict minted" "$OUT" "verdict=minted"; has "A1c names the Cloudflare cert id" "$OUT" "cert_id=7777777777777777"; has "A1d says restart is required" "$OUT" "restart_required=true"
has "A1e cert facts printed" "$OUT" "san_covers_host=true is_ca=false key_matches=true"
KEYB="$TMP/state/soleur/prd/ORIGIN_TLS_KEY_B64"; CERTB="$TMP/state/soleur/prd/ORIGIN_TLS_CERT_B64"
eq "A2 both names are in prd" "$([[ -s "$KEYB" && -s "$CERTB" ]] && echo yes || echo no)" yes
eq "A3 the stored values are one line (env-file contract)" "$(wc -l < "$KEYB" | tr -d ' ')$(wc -l < "$CERTB" | tr -d ' ')" 00
base64 -d < "$KEYB" > "$TMP/s.key" 2>/dev/null; base64 -d < "$CERTB" > "$TMP/s.pem" 2>/dev/null
eq "A4 the stored key is a P-256 EC key" "$(openssl pkey -in "$TMP/s.key" -noout -text 2>/dev/null | grep -c 'prime256v1')" 1
eq "A5 the stored cert matches the stored key" "$(openssl pkey -in "$TMP/s.key" -pubout -outform DER | sha256sum)" "$(openssl x509 -in "$TMP/s.pem" -noout -pubkey | openssl pkey -pubin -pubout -outform DER | sha256sum)"
has "A6 the stored cert covers the host" "$(openssl x509 -in "$TMP/s.pem" -noout -ext subjectAltName)" "DNS:app.soleur.ai"
eq "A7 the unrelated prd secret is untouched" "$(cat "$TMP/state/soleur/prd/SOME_OTHER_SECRET")" unrelated
eq "A8 exactly one POST" "$(posts)" 1
has "A8b the POST asked for origin-ecc, 5475 days, the host" "$(grep -h '' "$TMP/stub.log" | head -0; echo "origin-ecc 5475 app.soleur.ai")" "origin-ecc 5475 app.soleur.ai"
eq "A9m the key mask is registered exactly once" "$(masks_of "$KEYB" "$TMP/out.$SC")" 1
eq "A10 the private temp dir is gone" "$(ls -A "$TMP/rt" | wc -l | tr -d ' ')" 0
has "A11 the summary says nothing was restarted" "$(cat "$TMP/summary.md")" "nothing was restarted"

reset_env; run_mint apply false STUB_CF_NO_BC=1
eq "A12 a certificate with no basicConstraints extension (older OpenSSL prints nothing) is accepted as a leaf" "$RC" 0

echo "B. policy (idempotency and rotation)"
sig_after_first="$(state_sig)"; run_mint apply false
eq "I1 a second unforced apply is refused" "$RC" 1; has "I1b verdict" "$OUT" "verdict=already_minted_not_expiring"
eq "I1c no second POST" "$(posts)" 1; eq "I1d prd unchanged" "$(state_sig)" "$sig_after_first"
run_mint plan false
eq "I2 plan reports the same refusal (red), so the owner sees it before applying" "$RC" 1; has "I2b verdict" "$OUT" "verdict=already_minted_not_expiring"
old_sig="$(state_sig)"; run_mint apply true
eq "I3 replace=true re-mints over a valid certificate" "$RC" 0; has "I3b says deliberate rotation" "$OUT" "policy replace=true over a valid certificate"
eq "I3c prd changed" "$([[ "$(state_sig)" != "$old_sig" ]] && echo changed || echo same)" changed
has "I3d the replaced state is named and never revoked" "$OUT" "replaced_state=valid"
reset_env; mkexisting 30; run_mint apply false
eq "I4 a certificate with 30 days left is replaced without replace=true" "$RC" 0; has "I4b state near_expiry" "$OUT" "existing state=near_expiry"
reset_env; mkexisting 10; GE=$(( $(date -u +%s) + 20*86400 )); run_mint apply false MINT_NOW="$GE"; unset GE
eq "I5 an expired certificate is replaced" "$RC" 0; has "I5b state expired" "$OUT" "existing state=expired"; [[ "$RC" == 0 ]] || printf '%s\n' "$OUT" | grep -v '^::add-mask' | head -8
reset_env; printf 'garbage' > "$TMP/state/soleur/prd/ORIGIN_TLS_CERT_B64"; printf 'garbage' > "$TMP/state/soleur/prd/ORIGIN_TLS_KEY_B64"; run_mint apply false
eq "I6 an unparseable pair is replaced" "$RC" 0; has "I6b state unusable" "$OUT" "existing state=unusable"
reset_env; printf 'x' > "$TMP/state/soleur/prd/ORIGIN_TLS_KEY_B64"; run_mint apply false
eq "I7 a half-set pair is replaced" "$RC" 0; has "I7b state half" "$OUT" "existing state=half"
reset_env; mkexisting 5000; printf '1' > "$TMP/state/soleur/prd/ORIGIN_TLS_REQUIRED"; run_mint plan false
has "I8 plan reports ORIGIN_TLS_REQUIRED presence without its value" "$OUT" "origin_tls_required=set"

echo "B. refusals leave prd untouched"
refuse_case() { # name expected-verdict [env...] ; asserts RC=1, the verdict, no Doppler set/delete, prd unchanged
  local name="$1" v="$2"; shift 2
  reset_env; local s0; s0="$(state_sig)"; run_mint apply false "$@"
  eq "$name exits 1" "$RC" 1; has "$name verdict" "$OUT" "verdict=$v"
  eq "$name prd unchanged" "$(state_sig)" "$s0"
  eq "$name no Doppler write" "$(grep -cE 'ARGV secrets (set|delete)' "$TMP/stub.log")" 0
  eq "$name temp dir gone" "$(ls -A "$TMP/rt" | wc -l | tr -d ' ')" 0
}
refuse_case "R1 Cloudflare list 403" cf_list_failed STUB_CF_LIST_STATUS=403
reset_env; run_mint apply false STUB_CF_LIST_STATUS=403; eq "R1b a refused list means no POST" "$(posts)" 0
refuse_case "R2 Cloudflare create 403" cf_create_failed STUB_CF_CREATE_STATUS=403
refuse_case "R3 certificate with a short validity" cert_short_validity STUB_CF_DAYS=30
refuse_case "R4 certificate for another host" cert_wrong_host STUB_CF_HOST=other.soleur.ai
refuse_case "R5 certificate for another key" cert_key_mismatch STUB_CF_WRONG_KEY=1
GE=$(( $(date -u +%s) - 7200 )); refuse_case "R6 stale guard" guard_stale; unset GE
GE=notanumber; refuse_case "R7 missing guard epoch" guard_epoch_missing; unset GE
reset_env; rm -f "$TMP/state/soleur/prd_terraform/CF_API_TOKEN_ORIGIN_CA"; run_mint apply false
eq "R8 missing Cloudflare token exits 1" "$RC" 1; has "R8b verdict" "$OUT" "verdict=cf_token_unreadable"
reset_env; printf 'not-a-zone' > "$TMP/state/soleur/prd_terraform/CF_ZONE_ID"; run_mint apply false
eq "R9 a malformed zone id exits 1" "$RC" 1; has "R9b verdict" "$OUT" "verdict=zone_id_unreadable"
reset_env; run_mint apply false TF_VAR_doppler_token_tf=
eq "R10 no provider token exits 1" "$RC" 1; has "R10b verdict" "$OUT" "verdict=no_provider_token"
reset_env; run_mint apply false TF_VAR_doppler_token_tf="dp.pt.WRONG0123456789012345678901234567890"
eq "R11 a rejected provider token fails closed" "$RC" 1; has "R11b verdict" "$OUT" "verdict=cf_token_unreadable"
reset_env; run_mint bogus false; eq "R12 an unknown mode is refused by the body too" "$RC" 1
reset_env; run_mint apply false STUB_CF_TOKEN="a-different-token"; eq "R13 a Cloudflare 401 on the list fails closed" "$RC" 1; has "R13b verdict" "$OUT" "verdict=cf_list_failed"

echo "B. compensating restore"
reset_env; s0="$(state_sig)"; run_mint apply false STUB_FAIL_SET=ORIGIN_TLS_KEY_B64
eq "C1 a failed second write exits 1" "$RC" 1; has "C1b verdict" "$OUT" "verdict=doppler_write_failed"; has "C1c prd restored" "$OUT" "prd was restored"
eq "C1d prd is back to the previous state (the cert written first is removed)" "$(state_sig)" "$s0"
reset_env; mkexisting 30; s0="$(state_sig)"; run_mint apply false STUB_FAIL_SET=ORIGIN_TLS_KEY_B64
eq "C2 with a previous pair, a failed second write restores that pair byte for byte" "$(state_sig)" "$s0"; eq "C2b exits 1" "$RC" 1
reset_env; s0="$(state_sig)"; run_mint apply false STUB_CORRUPT_SET=ORIGIN_TLS_CERT_B64
eq "C3 a read-back mismatch exits 1" "$RC" 1; has "C3b verdict" "$OUT" "verdict=readback_mismatch"; eq "C3c prd restored" "$(state_sig)" "$s0"

leak_scan

# ------------------------------------------------------------------------------------------------------------------------------
# C. mutations: each guard removed in a COPY must flip its scenario from "stops" to "proceeds"
echo "C. mutations"
mutate() { # name sed-expr scenario-fn
  local name="$1" expr="$2" m="$TMP/mut.$3.sh"
  cp "$BODY" "$m"; sed -i -E "$expr" "$m"
  if cmp -s "$BODY" "$m"; then bad "$name (the mutation did not land)"; return 1; fi
  MUT="$m"
}
# M1 policy refusal removed
mutate "M1" 's/^  if \[\[ "\$MC_EX_STATE" == "valid" && "\$replace" != "true" \]\]; then$/  if false; then/' m1 && {
  reset_env; mkexisting 5000; RUN_BODY="$MUT" run_mint apply false; unset RUN_BODY
  eq "M1 without the policy refusal a valid certificate is overwritten (the I1 scenario now proceeds)" "$RC" 0; }
# M2 confirm check removed
mutate "M2" 's/^    if \[\[ "\$confirm" != "\$want" \]\]; then$/    if false; then/' m2 && {
  GOUT="$(env -i PATH="$PATH" GITHUB_OUTPUT="$TMP/gh_out" GITHUB_EVENT_NAME=workflow_dispatch GITHUB_RUN_ATTEMPT=1 GITHUB_REF=refs/heads/main GITHUB_ACTOR=deruelle GITHUB_TRIGGERING_ACTOR=deruelle INPUT_MODE=apply INPUT_REPLACE=false INPUT_CONFIRM= MINT_NOW=1800000000 bash "$MUT" guard 2>&1)"; GRC=$?
  eq "M2 without the confirm check an apply with no confirm passes the guard (the G10 scenario now proceeds)" "$GRC" 0; }
# M3 key/cert match removed
mutate "M3" 's/^  if \[\[ -z "\$\(mc_pub_sha key "\$MC_TMP\/key.pem"\)" \|\| "\$\(mc_pub_sha key "\$MC_TMP\/key.pem"\)" != "\$\(mc_pub_sha cert "\$MC_TMP\/cert.pem"\)" \]\]; then$/  if false; then/' m3 && {
  reset_env; RUN_BODY="$MUT" run_mint apply false STUB_CF_WRONG_KEY=1; unset RUN_BODY
  eq "M3 without the key/cert match a certificate for another key is published (the R5 scenario now proceeds)" "$RC" 0; }
# M4 stale guard removed
mutate "M4" 's/^    if \(\( now - epoch > MC_AUTH_MAX_AGE_S \)\); then/    if false; then/' m4 && {
  reset_env; GE=$(( $(date -u +%s) - 7200 )); RUN_BODY="$MUT" run_mint apply false; unset RUN_BODY GE
  eq "M4 without the age check a stale guard proceeds (the R6 scenario now proceeds)" "$RC" 0; }
# M5 restore removed: a failed second write leaves a half pair
mutate "M5" 's/^  if mc_restore_previous; then$/  if false; then/' m5 && {
  reset_env; s0="$(state_sig)"; RUN_BODY="$MUT" run_mint apply false STUB_FAIL_SET=ORIGIN_TLS_KEY_B64; unset RUN_BODY
  eq "M5 without the restore a failed second write leaves a half pair in prd (the C1d scenario now differs)" "$([[ "$(state_sig)" != "$s0" ]] && echo differs || echo same)" differs; }
# M6 key mask removed: the leak scan must see the base64 key outside ::add-mask:: ... (the mask line itself is the only carrier, so
# the mutant instead drops the mask registration and the row requires its absence to be detected)
mutate "M6" 's/^  mc_mask "\$\(mc_b64 "\$MC_TMP\/key.pem"\)"$/  :/' m6 && {
  reset_env; RUN_BODY="$MUT" run_mint apply false; unset RUN_BODY
  eq "M6 without the key mask registration the A9 row fails (the mask line is absent)" "$(masks_of "$KEYB" "$TMP/out.$SC")" 0; }

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
