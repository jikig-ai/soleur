#!/usr/bin/env bash
# cf-access-deploy-token-mint.test.sh: battery for scripts/cf-access-deploy-token-mint.sh (#12931,
# runbook Phase 3 step 1).
#
# HARNESS. curl, doppler and gh are PATH stubs over a per-case store. Each refuses any argv it does not
# model (exit 64, refused.log), so an unexpected read (CF_API_TOKEN, say) or write fails the row. Every
# credential is synthesized, including an RSA key generated here. The no-secret assertion reads the
# script's output and every recorded argv of every run.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
SUT="$HERE/scripts/cf-access-deploy-token-mint.sh"
[[ -f "$SUT" ]] || { printf '[FATAL] script under test missing: %s\n' "$SUT" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { printf '[FATAL] jq is required\n' >&2; exit 2; }
command -v openssl >/dev/null 2>&1 || { printf '[FATAL] openssl is required\n' >&2; exit 2; }

SBX="$(mktemp -d -t cf-mint.XXXXXXXX)" || { printf '[FATAL] mktemp failed\n' >&2; exit 2; }
trap 'rm -rf -- "$SBX"' EXIT INT TERM HUP
TREE="$SBX/tree"
mkdir -p "$SBX/bin" "$SBX/runs" "$TREE/apps/web-platform/infra/scripts" "$TREE/scripts/lib" || exit 2
ln -s "$REPO/scripts/lib/bearer-curl.sh" "$TREE/scripts/lib/bearer-curl.sh" || exit 2
cp "$SUT" "$TREE/apps/web-platform/infra/scripts/mint.sh" || exit 2
MINT="$TREE/apps/web-platform/infra/scripts/mint.sh"
printf '# synthesized inventory\ndev\nprd\nprd_terraform\nprd_scheduled\n' >"$TREE/apps/web-platform/infra/doppler-config-inventory.txt"

NA=66d4f93f7397f196544e9fe84c3557c2
UUID=11111111-2222-4333-8444-555555555555
export S_MINT="synthetic-mint-token-value" S_ID="synthclientid0123456789.access" S_SECRET="synthclientsecret0123456789abcdef" S_INST="ghs_synthetic_installation_token"
openssl genrsa -out "$SBX/app.pem" 2048 2>/dev/null || { printf '[FATAL] cannot generate the synthetic key\n' >&2; exit 2; }
PEM_MARK="$(sed -n 2p "$SBX/app.pem")"

PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
no() { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; if [[ -n "${D:-}" && -f "$D/out" ]]; then sed 's/^/    /' "$D/out" | tail -n 10; fi; }
check() { if [[ "$1" -eq 0 ]]; then ok "$2"; else no "$2"; fi; }
_p=$PASS; _f=$FAIL; ok "instrument probe" >/dev/null; no "instrument probe" >/dev/null
if [[ "$PASS" -ne $((_p + 1)) || "$FAIL" -ne $((_f + 1)) ]]; then printf '[FATAL] instrument\n' >&2; exit 2; fi
PASS=$_p; FAIL=$_f

cat >"$SBX/bin/doppler" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
D="${STUB_DIR:?}"
no() { printf 'doppler %s\n' "$*" >>"$D/refused.log"; exit 64; }
printf 'doppler %s\n' "$*" >>"$D/argv.log"
key() { printf '%s/store/%s__%s__%s' "$D" "$1" "$2" "$3"; }
if [[ $# -eq 7 && "$1 $2 $3 $4 $6" == "secrets --only-names --json -p -c" ]]; then
  [[ ! -f "$D/nolist.$5.$7" ]] || exit 1
  ( shopt -s nullglob; for f in "$D/store/${5}__${7}__"*; do printf '%s\n' "${f##*__}"; done ) | jq -Rn '[inputs | {(.): {}}] | add // {}'
  exit 0
fi
if [[ $# -eq 8 && "$1 $2 $4 $6 $8" == "secrets get -p -c --plain" ]]; then
  case "$5/$7/$3" in
    soleur/prd_terraform/CF_API_TOKEN_ACCESS_MINT|soleur/prd_terraform/CF_API_TOKEN_ACCESS_MINT_NEXT) ;;
    soleur-infra-app/prd/GITHUB_INFRA_APP_ID|soleur-infra-app/prd/GITHUB_INFRA_APP_PRIVATE_KEY) ;;
    */CF_ACCESS_CLIENT_ID|*/CF_ACCESS_CLIENT_SECRET) ;;
    *) no "$@" ;;
  esac
  f="$(key "$5" "$7" "$3")"
  [[ -f "$f" ]] || exit 1
  cat "$f"; printf '\n'; exit 0
fi
if [[ $# -eq 9 && "$1 $2 $4 $5 $6 $8" == "secrets set --silent --no-interactive -p -c" ]]; then
  case "$3" in CF_ACCESS_CLIENT_ID|CF_ACCESS_CLIENT_SECRET) ;; *) no "$@" ;; esac
  v="$(cat)"
  [[ ! -f "$D/setfail.$7.$9.$3" ]] || exit 1
  if [[ -f "$D/corrupt.$7.$9.$3" ]]; then v="corrupted-value"; fi
  printf '%s' "$v" >"$(key "$7" "$9" "$3")"
  printf '%s %s %s\n' "$7" "$9" "$3" >>"$D/writes.log"
  exit 0
fi
no "$@"
STUB
cat >"$SBX/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
D="${STUB_DIR:?}"
no() { printf 'gh %s\n' "$*" >>"$D/refused.log"; exit 64; }
printf 'gh %s\n' "$*" >>"$D/argv.log"
[[ "${GH_TOKEN:-}" == "$S_INST" ]] || no "(not the installation token)" "$@"
R=jikig-ai/soleur
if [[ $# -eq 8 && "$1 $2 $3 $4 $5 $6 $7 $8" == "secret list --repo $R --app actions --json name,updatedAt" ]]; then
  [[ ! -f "$D/ghlistfail" ]] || exit 1
  ( shopt -s nullglob; for f in "$D"/ghsec/*; do jq -nc --arg n "${f##*/}" --arg u "$(cat "$f")" '{name:$n,updatedAt:$u}'; done ) | jq -s .
  exit 0
fi
if [[ $# -eq 7 && "$1 $2 $4 $5 $6 $7" == "secret set --repo $R --app actions" ]]; then
  case "$3" in CF_ACCESS_CLIENT_ID|CF_ACCESS_CLIENT_SECRET) ;; *) no "$@" ;; esac
  v="$(cat)"
  [[ ! -f "$D/ghsetfail.$3" ]] || exit 1
  printf '%s' "$v" >"$D/ghval.$3"
  [[ -f "$D/ghstale.$3" ]] || printf '2026-11-23T12:00:00Z' >"$D/ghsec/$3"
  printf 'github %s\n' "$3" >>"$D/writes.log"
  exit 0
fi
no "$@"
STUB
cat >"$SBX/bin/curl" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail
D="${STUB_DIR:?}"
no() { printf 'curl %s\n' "$*" >>"$D/refused.log"; exit 64; }
method=GET; url=""; cfg=0; data=""; prev=""
for a in "$@"; do
  case "$prev" in -X) method="$a" ;; -d) data="$a" ;; --config) [[ "$a" == - ]] && cfg=1 ;; esac
  [[ "$a" == https://* ]] && url="$a"
  prev="$a"
done
printf 'curl %s\n' "$*" >>"$D/argv.log"
[[ "$cfg" -eq 1 ]] || no "$@"
hdr="$(cat)"
printf '%s %s\n' "$method" "$url" >>"$D/calls.log"
reply() { if [[ -f "$D/reply.$1" ]]; then cat "$D/reply.$1"; else printf '%s\n%s' "$2" "$3"; fi; exit 0; }
CF=https://api.cloudflare.com/client/v4/accounts/66d4f93f7397f196544e9fe84c3557c2/access/service_tokens
GH=https://api.github.com
case "$method $url" in
  "GET $CF?per_page=100")
    [[ "$hdr" == "header = \"Authorization: Bearer $S_MINT\"" ]] || no "(not the mint token)"
    reply cflist '{"success":true,"result":[{"id":"99999999-2222-4333-8444-555555555555","name":"unrelated"}],"result_info":{"total_count":1}}' 200 ;;
  "POST $CF")
    [[ "$hdr" == "header = \"Authorization: Bearer $S_MINT\"" ]] || no "(not the mint token)"
    jq -e '. == {name:"github-actions-deploy",duration:"8760h"}' <<<"$data" >/dev/null || no "(bad mint body)"
    reply cfmint "$(jq -nc --arg i "$S_ID" --arg s "$S_SECRET" '{success:true,result:{id:"11111111-2222-4333-8444-555555555555",name:"github-actions-deploy",client_id:$i,client_secret:$s}}')" 200 ;;
  "GET $GH/app/installations/166065653")
    [[ "$hdr" == 'header = "Authorization: Bearer '*.*.*'"' ]] || no "(no JWT)"
    reply ghinst '{"id":166065653,"permissions":{"secrets":"write","metadata":"read"}}' 200 ;;
  "POST $GH/app/installations/166065653/access_tokens")
    [[ "$hdr" == 'header = "Authorization: Bearer '*.*.*'"' ]] || no "(no JWT)"
    jq -e '. == {repositories:["soleur"],permissions:{secrets:"write"}}' <<<"$data" >/dev/null || no "(bad scope body)"
    reply ghtoken "$(jq -nc --arg t "$S_INST" '{token:$t,permissions:{secrets:"write",metadata:"read"},repository_selection:"selected",repositories:[{name:"soleur"}]}')" 201 ;;
  "DELETE $GH/installation/token")
    [[ "$hdr" == "header = \"Authorization: Bearer $S_INST\"" ]] || no "(revoke without the installation token)"
    printf 'revoked\n' >>"$D/revoked.log"; printf '\n204'; exit 0 ;;
  *) no "$@" ;;
esac
STUB
chmod +x "$SBX/bin/"*

CASE_N=0
new_case() {
  CASE_N=$((CASE_N + 1))
  D="$SBX/runs/$CASE_N-${1//[^A-Za-z0-9_-]/_}"
  mkdir -p "$D/store" "$D/ghsec" || exit 2
  : >"$D/argv.log"; : >"$D/calls.log"; : >"$D/writes.log"
  put soleur prd_terraform CF_API_TOKEN_ACCESS_MINT "$S_MINT"
  put soleur prd_terraform CF_ACCESS_CLIENT_ID old-id
  put soleur prd_terraform CF_ACCESS_CLIENT_SECRET old-secret
  put soleur-infra-privileged prd CF_ACCESS_CLIENT_ID old-id
  put soleur-infra-privileged prd CF_ACCESS_CLIENT_SECRET old-secret
  put soleur prd SOME_OTHER_KEY x
  put soleur dev SOME_OTHER_KEY x
  put soleur-infra-app prd GITHUB_INFRA_APP_ID 12345
  cp "$SBX/app.pem" "$D/store/soleur-infra-app__prd__GITHUB_INFRA_APP_PRIVATE_KEY"
  printf '2025-01-01T00:00:00Z' >"$D/ghsec/CF_ACCESS_CLIENT_ID"
  printf '2025-01-01T00:00:00Z' >"$D/ghsec/CF_ACCESS_CLIENT_SECRET"
}
put() { printf '%s' "$4" >"$D/store/${1}__${2}__${3}"; } # defined after new_case binds D
run() { env -u GH_TOKEN -u GITHUB_TOKEN PATH="$SBX/bin:$PATH" STUB_DIR="$D" bash "$MINT" "$@" >"$D/out" 2>&1; RC=$?; }
has() { grep -qF -- "$1" "$D/out"; }
n_writes() { grep -c . "$D/writes.log"; }
minted() { grep -c "^POST https://api.cloudflare.com" "$D/calls.log"; }
val() { cat "$D/store/${1}__${2}__${3}" 2>/dev/null; }

printf '\n[dry run]\n'
new_case dry; run
r=1; [[ "$RC" -eq 0 ]] && has 'verdict=dry-run' && [[ "$(minted)" -eq 0 && "$(n_writes)" -eq 0 ]] && r=0
check "$r" "the default is a dry run: no mint and no write"
r=1; has 'holder=soleur-infra-privileged/prd' && has 'holder=soleur/prd_terraform' && has 'holder=github:jikig-ai/soleur' && r=0
check "$r" "the dry run names every holder it would write"
r=1; ! grep -q '^POST .*access_tokens' "$D/calls.log" && r=0
check "$r" "the dry run mints no GitHub installation token"

printf '\n[apply]\n'
new_case apply; run --apply
r=1; [[ "$RC" -eq 0 ]] && has "verdict=ok token_id=$UUID" && r=0
check "$r" "--apply mints and prints the token UUID"
r=1
for h in "soleur-infra-privileged prd" "soleur prd_terraform"; do
  # shellcheck disable=SC2086 # two words: project and config
  [[ "$(val $h CF_ACCESS_CLIENT_ID)" == "$S_ID" && "$(val $h CF_ACCESS_CLIENT_SECRET)" == "$S_SECRET" ]] || r=2
done
[[ "$r" -eq 1 ]] && r=0
check "$r" "both required Doppler holders hold the new pair, byte-exact"
r=1; [[ "$(cat "$D/ghval.CF_ACCESS_CLIENT_ID")" == "$S_ID" && "$(cat "$D/ghval.CF_ACCESS_CLIENT_SECRET")" == "$S_SECRET" ]] && r=0
check "$r" "the GitHub repository secrets hold the new pair"
r=1; [[ "$(n_writes)" -eq 6 ]] && r=0
check "$r" "exactly six writes (two Doppler holders and GitHub, two names each)"
r=1; [[ ! -e "$D/store/soleur__prd__CF_ACCESS_CLIENT_ID" && ! -e "$D/store/soleur__dev__CF_ACCESS_CLIENT_ID" ]] && r=0
check "$r" "a config holding neither name is not written"
r=1; [[ "$(grep -c 'verify=digest' "$D/out")" -eq 4 && "$(grep -c 'verify=updated_at' "$D/out")" -eq 2 ]] && r=0
check "$r" "each Doppler write is verified by digest and each GitHub write by its updated_at"
r=1; [[ -s "$D/revoked.log" ]] && r=0
check "$r" "the installation token is revoked on exit"
r=1; ! grep -q 'secret set .*--body' "$D/argv.log" && ! grep -q 'secrets set .*--value' "$D/argv.log" && r=0
check "$r" "no value is passed by flag to gh or doppler"

new_case extra; put soleur prd CF_ACCESS_CLIENT_ID old-id; put soleur prd CF_ACCESS_CLIENT_SECRET old-secret; run --apply
r=1; [[ "$RC" -eq 0 && "$(val soleur prd CF_ACCESS_CLIENT_SECRET)" == "$S_SECRET" && "$(n_writes)" -eq 8 ]] && r=0
check "$r" "an extra inventory holder of the pair is written too"
new_case next; rm "$D/store/soleur__prd_terraform__CF_API_TOKEN_ACCESS_MINT"; put soleur prd_terraform CF_API_TOKEN_ACCESS_MINT_NEXT "$S_MINT"; run --apply
r=1; [[ "$RC" -eq 0 ]] && has "verdict=ok token_id=$UUID" && r=0
check "$r" "the mint token staged as _NEXT (the Phase 0 hand-off) is used"

printf '\n[refused before the mint]\n'
refused_clean() { [[ "$RC" -eq 1 && "$(minted)" -eq 0 && "$(n_writes)" -eq 0 ]] && has "verdict=refuse reason=$1"; }
new_case no-mint; rm "$D/store/soleur__prd_terraform__CF_API_TOKEN_ACCESS_MINT"; run --apply
refused_clean mint-token-missing; check "$?" "no mint token -> refused"
new_case both-mint; put soleur prd_terraform CF_API_TOKEN_ACCESS_MINT_NEXT other; run --apply
refused_clean mint-token-ambiguous; check "$?" "both the key and its _NEXT -> refused"
new_case half; put soleur prd CF_ACCESS_CLIENT_ID old-id; run --apply
refused_clean holder-half-pair; check "$?" "an inventory config holding half the pair -> refused"
new_case nolist; : >"$D/nolist.soleur.dev"; run --apply
refused_clean holders-unreadable; check "$?" "an unreadable inventory config -> refused (never read as absent)"
new_case nolist-req; : >"$D/nolist.soleur-infra-privileged.prd"; run --apply
refused_clean holders-unreadable; check "$?" "an unreadable required holder -> refused"
new_case exists; printf '%s\n200' '{"success":true,"result":[{"id":"aaaaaaaa-2222-4333-8444-555555555555","name":"github-actions-deploy"}],"result_info":{"total_count":1}}' >"$D/reply.cflist"; run --apply
refused_clean token-exists; check "$?" "a token of that name already exists -> refused"
r=1; has 'id=aaaaaaaa-2222-4333-8444-555555555555' && r=0; check "$r" "the refusal names the existing token's UUID"
new_case trunc; printf '%s\n200' '{"success":true,"result":[],"result_info":{"total_count":101}}' >"$D/reply.cflist"; run --apply
refused_clean token-list-truncated; check "$?" "a truncated token list -> refused (absence not proven)"
new_case cflist403; printf '%s\n403' '{"success":false}' >"$D/reply.cflist"; run --apply
refused_clean token-list-unreadable; check "$?" "the mint token cannot list service tokens -> refused"
new_case noapp; rm "$D/store/soleur-infra-app__prd__GITHUB_INFRA_APP_ID"; run --apply
refused_clean github-app-unreadable; check "$?" "the infra GitHub App id is unreadable -> refused"
new_case badpem; printf 'not-a-key' >"$D/store/soleur-infra-app__prd__GITHUB_INFRA_APP_PRIVATE_KEY"; run --apply
refused_clean github-app-unreadable; check "$?" "a malformed App key -> refused"
new_case grant; printf '%s\n201' "$(jq -nc --arg t "$S_INST" '{token:$t,permissions:{secrets:"write",administration:"write",metadata:"read"},repository_selection:"selected",repositories:[{name:"soleur"}]}')" >"$D/reply.ghtoken"; run --apply
refused_clean github-token-scope; check "$?" "an installation token wider than secrets:write -> refused"
r=1; [[ -s "$D/revoked.log" ]] && r=0; check "$r" "the over-wide installation token is revoked"
new_case grant-repo; printf '%s\n201' "$(jq -nc --arg t "$S_INST" '{token:$t,permissions:{secrets:"write",metadata:"read"},repository_selection:"all",repositories:[]}')" >"$D/reply.ghtoken"; run --apply
refused_clean github-token-scope; check "$?" "an installation token over all repositories -> refused"
new_case ghlist; : >"$D/ghlistfail"; run --apply
refused_clean github-secrets-unreadable; check "$?" "the GitHub secret list is unreadable -> refused before the mint"

printf '\n[the mint itself]\n'
new_case post500; printf '%s\n500' '{"success":false}' >"$D/reply.cfmint"; run --apply
r=1; [[ "$RC" -eq 1 && "$(n_writes)" -eq 0 ]] && has 'verdict=refuse reason=mint-failed' && r=0
check "$r" "the mint POST fails -> refused, nothing written"
new_case post-noid; printf '%s\n200' "$(jq -nc --arg i "$S_ID" --arg s "$S_SECRET" '{success:true,result:{name:"github-actions-deploy",client_id:$i,client_secret:$s}}')" >"$D/reply.cfmint"; run --apply
r=1; [[ "$RC" -eq 1 && "$(n_writes)" -eq 0 ]] && has 'reason=mint-response-invalid' && ! grep -qF -- "$S_SECRET" "$D/out" && r=0
check "$r" "a mint response with no UUID -> refused, nothing written, no value printed"
new_case post-nosecret; printf '%s\n200' "$(jq -nc --arg i "$S_ID" '{success:true,result:{id:"11111111-2222-4333-8444-555555555555",name:"github-actions-deploy",client_id:$i}}')" >"$D/reply.cfmint"; run --apply
r=1; [[ "$RC" -eq 1 && "$(n_writes)" -eq 0 ]] && has 'reason=mint-response-invalid' && has "token_id=$UUID" && r=0
check "$r" "a mint response with no secret -> refused, and the orphan token's UUID is named"

printf '\n[partial failure] names exactly what was written\n'
W1='soleur-infra-privileged/prd:CF_ACCESS_CLIENT_ID'; W2='soleur-infra-privileged/prd:CF_ACCESS_CLIENT_SECRET'
W3='soleur/prd_terraform:CF_ACCESS_CLIENT_ID'; W4='soleur/prd_terraform:CF_ACCESS_CLIENT_SECRET'
W5='github:jikig-ai/soleur:CF_ACCESS_CLIENT_ID'; W6='github:jikig-ai/soleur:CF_ACCESS_CLIENT_SECRET'
new_case part-set; : >"$D/setfail.soleur.prd_terraform.CF_ACCESS_CLIENT_ID"; run --apply
r=1; [[ "$RC" -eq 1 ]] && has "verdict=partial token_id=$UUID written=$W1,$W2 failed=$W3 not_attempted=$W4,$W5,$W6" && r=0
check "$r" "a refused Doppler write: the written, failed and not-attempted holders are exact"
new_case part-digest; : >"$D/corrupt.soleur-infra-privileged.prd.CF_ACCESS_CLIENT_SECRET"; run --apply
r=1; [[ "$RC" -eq 1 ]] && has "written=$W1 failed=$W2 not_attempted=$W3,$W4,$W5,$W6" && has 'cause=digest-mismatch' && r=0
check "$r" "a Doppler read-back whose digest differs stops the run at that holder"
new_case part-gh; : >"$D/ghsetfail.CF_ACCESS_CLIENT_SECRET"; run --apply
r=1; [[ "$RC" -eq 1 ]] && has "written=$W1,$W2,$W3,$W4,$W5 failed=$W6 not_attempted= " && r=0
check "$r" "a refused GitHub write names the five written holders"
new_case part-ghstale; : >"$D/ghstale.CF_ACCESS_CLIENT_ID"; run --apply
r=1; [[ "$RC" -eq 1 ]] && has "written=$W1,$W2,$W3,$W4 failed=$W5 not_attempted=$W6" && has 'cause=updated-at-unchanged' && r=0
check "$r" "a GitHub secret whose updated_at did not move counts as not written"
r=1; has 'delete token' && has "$UUID" && r=0
check "$r" "the partial failure says how to recover (delete the token, re-run)"

printf '\n[inputs]\n'
new_case badarg; run --force
r=1; [[ "$RC" -eq 2 && ! -s "$D/calls.log" && "$(n_writes)" -eq 0 ]] && r=0
check "$r" "an unknown argument exits 2 and touches nothing"
new_case xtrace
env PATH="$SBX/bin:$PATH" STUB_DIR="$D" bash -x "$MINT" --apply >"$D/out" 2>&1; RC=$?
r=1; [[ "$RC" -eq 78 && ! -s "$D/argv.log" ]] && r=0
check "$r" "xtrace refuses (78) before any call"

printf '\n[readers] the deploy pair in GitHub workflows\n'
WF="$REPO/.github/workflows"
ids="$(grep -lF 'secrets.CF_ACCESS_CLIENT_ID' "$WF"/*.yml | sort)"
secs="$(grep -lF 'secrets.CF_ACCESS_CLIENT_SECRET' "$WF"/*.yml | sort)"
r=1; [[ -n "$ids" && "$ids" == "$secs" && "$(grep -c . <<<"$ids")" -ge 10 ]] && r=0
check "$r" "every workflow reading the id also reads the secret, at least 10 of them (one repository secret pair serves all)"

printf '\n[no secret anywhere]\n'
leaks=""
for d in "$SBX"/runs/*/; do
  for v in "$S_MINT" "$S_ID" "$S_SECRET" "$S_INST" "$PEM_MARK"; do
    if grep -qF -- "$v" "$d/out" "$d/argv.log" 2>/dev/null; then leaks+=" ${d%/}"; break; fi
  done
done
r=1; [[ -z "$leaks" ]] && r=0
check "$r" "no credential value in the output or any recorded argv of any run${leaks:+ (leaked in:${leaks##*/})}"
bad=""
for d in "$SBX"/runs/*/; do if [[ -s "$d/refused.log" ]]; then bad+=" ${d%/}"; fi; done
r=1; [[ -z "$bad" ]] && r=0
check "$r" "no stub refused an unmodeled call in any run${bad:+ (in:${bad##*/})}"

printf '\ncf-access-deploy-token-mint: %d passed, %d failed\n' "$PASS" "$FAIL"
MIN_CASES=41
if [[ "$((PASS + FAIL))" -lt "$MIN_CASES" ]]; then printf '[VACUITY] only %d cases ran, floor %d\n' "$((PASS + FAIL))" "$MIN_CASES" >&2; exit 1; fi
[[ "$FAIL" -eq 0 ]] || exit 1
