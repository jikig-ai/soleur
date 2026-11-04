#!/usr/bin/env bash
# Hermetic suite for plugins/soleur/scripts/cloudflare-readonly.sh (#10479, Class R wrapper).
#
# NO network, NO Doppler, NO real credential. The wrapper calls /usr/bin/curl by absolute path,
# so the suite runs a COPY of it in which exactly one line (`CURL=/usr/bin/curl`) is rewritten
# to a stub, with an exactly-one-match assertion. The curl child gets an EMPTY environment
# (`env -i`), so the stub reads its scenario (status, body, exit, stderr canary) from fixture
# files next to itself and logs argv (NUL-separated), stdin and its own exported environment to
# files next to itself. Real jq. Fake distinctive tokens.
#
# MUTATION HARNESS. `mutate` copies the wrapper, applies ONE literal edit (exactly-one-match,
# `bash -n` clean, differs from the original), re-runs THIS suite in a child (recursion guard:
# CF_RO_TEST_INNER) restricted to the relevant row groups, and counts the row as caught only
# when the child fails WITH THE NAMED ROW. Controls: the pristine copy and a benign comment edit
# both pass, so the suite does not red on every edit; a stub whose log is blind reds the wire
# floor, so a vacuous recorder cannot pass.
#
# Scratch lives under the worktree (Class R item 6: no write outside the worktree) and is removed
# on exit. Tokens reach the wrapper through `env -i NAME=value ...` argument lists, never through
# a helper function's prefix assignment.
set -uo pipefail

TESTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# A suite-mutation child runs a COPY of this file from scratch; it names the real test dir here (inner children only).
if [[ -n "${CF_RO_TEST_INNER:-}" && -n "${CF_RO_TESTDIR:-}" ]]; then TESTDIR="$CF_RO_TESTDIR"; fi
REPO_ROOT="$(cd "$TESTDIR/../../.." && pwd)"
SELF="$TESTDIR/$(basename "${BASH_SOURCE[0]}")"
PROD="$TESTDIR/../scripts/cloudflare-readonly.sh"

# Owning trap BEFORE the helper is sourced (test-helpers.sh composes its incident-sandbox cleanup over an
# existing EXIT trap; one installed afterwards would replace it and leak the sandbox).
WORK=""
cleanup() {
  if [[ -n "${WORK:-}" ]]; then rm -rf -- "${WORK:?}"; fi
}
trap cleanup EXIT
# shellcheck source=plugins/soleur/test/test-helpers.sh
source "$TESTDIR/test-helpers.sh" || { echo "FATAL: could not source test-helpers.sh" >&2; exit 2; }
# test-helpers.sh runs `set -euo pipefail`; this suite accumulates failures instead.
set +e -uo pipefail
assert_fixture_dir "$REPO_ROOT"

INNER="${CF_RO_TEST_INNER:-}"
SELECT="${CF_RO_GROUPS:-all}"
SUT_SRC="$PROD"
if [[ -n "$INNER" && -n "${CF_RO_SUT:-}" ]]; then SUT_SRC="$CF_RO_SUT"; fi

pass=0
fail=0
asserted=0
ok() { pass=$((pass + 1)); printf 'ok   - %s\n' "$1"; }
no() { fail=$((fail + 1)); printf 'FAIL - %s\n' "$1"; }
# t <label> <command...>: passes when the command returns 0. `asserted` moves at the call site.
t() {
  local label="$1"
  shift
  asserted=$((asserted + 1))
  if "$@"; then ok "$label"; else no "$label"; fi
}
# tn <label> <command...>: passes when the command returns NON-zero.
tn() {
  local label="$1"
  shift
  asserted=$((asserted + 1))
  if "$@"; then no "$label"; else ok "$label"; fi
}
vok() { asserted=$((asserted + 1)); ok "$1"; }
vno() { asserted=$((asserted + 1)); no "$1"; }
want() { [[ "$SELECT" == all || ",$SELECT," == *",$1,"* ]]; }

# --- RED: the wrapper must exist. A missing file is a clean failure, not an error. ---
if [[ ! -f "$SUT_SRC" ]]; then
  vno "wrapper present: $SUT_SRC does not exist (RED until the wrapper is written)"
  printf '\n%s passed, %s failed\n' "$pass" "$fail"
  exit 1
fi

# --- scratch (in-worktree), owned trap ---
WORK="$(mktemp -d "$REPO_ROOT/.cf-readonly-test.XXXXXXXX")" || { echo "FATAL: mktemp failed" >&2; exit 2; }
assert_fixture_dir "$WORK"
case "$WORK" in "$REPO_ROOT"/.cf-readonly-test.?*) : ;; *) echo "FATAL: unexpected scratch path" >&2; exit 2 ;; esac
export TMPDIR="$WORK"
trap 'cleanup; trap - INT; kill -INT $$' INT
trap 'cleanup; trap - TERM; kill -TERM $$' TERM
trap 'cleanup; trap - HUP; kill -HUP $$' HUP

STUB="$WORK/stub"
assert_fixture_dir "$STUB"
mkdir -p "$STUB" || { echo "FATAL: mkdir failed" >&2; exit 2; }

# --- fake credentials (synthesized; punctuation-complete so the stdin channel is proven intact) ---
TOK_Z="zfake""ZONESET.Ab~1+2/3=x-9"
TOK_R="rfake""RULESET.Cd~4+5/6=y-8"
TOK_A="afake""AUDITTK.Ef~7+8/9=z-7"
TOK_BARE="bfake""BARE.Gh~0+1/2=w-6"
CANARY_BODY="CANARYBODY_7f3a91"
CANARY_ERR="CANARYERR_91bcd2"
ZONE="0123456789abcdef0123456789abcdef"
ACCT="fedcba9876543210fedcba9876543210"
ZONE_ALT="aaaaaaaabbbbbbbbccccccccdddddddd"
BASE_URL="https://api.cloudflare.com/client/v4"
HOMEDIR="$WORK/home"
assert_fixture_dir "$HOMEDIR"
mkdir -p "$HOMEDIR" || { echo "FATAL: mkdir failed" >&2; exit 2; }
BASE_ENV=(
  "HOME=$HOMEDIR" "DOPPLER_PROJECT=soleur" "DOPPLER_CONFIG=prd_terraform"
  "CF_ZONE_ID=$ZONE" "CF_ACCOUNT_ID=$ACCT"
  "CF_API_TOKEN_ZONE_SETTINGS=$TOK_Z" "CF_API_TOKEN_RULESETS=$TOK_R" "CF_API_TOKEN_AUDIT=$TOK_A"
)
LEAK_NEEDLES=("$TOK_Z" "$TOK_R" "$TOK_A" "$TOK_BARE" "$CANARY_BODY" "$CANARY_ERR"
  "EXPR_CANARY" "DESC_CANARY" "ACTOR_CANARY" "203.0.113.77" "PATTERN_CANARY" "Bearer")
SUBS=(ssl-mode config-entrypoint pagerules-ssl change-history)

# --- the stub curl (path rewritten into the sandbox copy of the wrapper) ---
cat > "$STUB/curl" <<'STUB_EOF'
#!/bin/bash
# Records argv FIRST (NUL-separated), then validates it against the CLOSED set of flags the wrapper is modeled to
# send. Anything else is logged to refusal.log and refused with exit 64. stdin is read and logged ONLY when the
# argv carries `--config -`.
D="${0%/*}"
printf "called\n" >> "$D/calls.log"
ARGLOG="$D/argv.bin"
for a in "$@"; do printf "%s\0" "$a" >> "$ARGLOG"; done
refuse() { printf "%s\n" "$1" >> "$D/refusal.log"; exit 64; }
args=("$@"); n=$#; i=0; cfg=0
while ((i < n)); do
  a="${args[$i]}"
  case "$a" in
    --disable | -sS) : ;;
    --noproxy) i=$((i + 1)); [[ "${args[$i]-}" == '*' ]] || refuse "noproxy-arg" ;;
    -X) i=$((i + 1)); [[ "${args[$i]-}" == GET ]] || refuse "-X-arg" ;;
    --max-time) i=$((i + 1)); [[ "${args[$i]-}" =~ ^[0-9]+$ ]] || refuse "max-time-arg" ;;
    --max-redirs) i=$((i + 1)); [[ "${args[$i]-}" == 0 ]] || refuse "max-redirs-arg" ;;
    -w) i=$((i + 1)); [[ "${args[$i]-}" == $'\n%{http_code}' ]] || refuse "-w-arg" ;;
    --config) i=$((i + 1)); [[ "${args[$i]-}" == '-' ]] || refuse "config-arg"; cfg=1 ;;
    https://*) ((i == n - 1)) || refuse "url-not-last" ;;
    *) refuse "flag:$a" ;;
  esac
  i=$((i + 1))
done
if ((cfg == 1)); then
  while IFS= read -r l || [[ -n "$l" ]]; do printf "%s\n" "$l" >> "$D/stdin.log"; done
fi
export -p > "$D/env.log"
status=$(<"$D/status"); body=$(<"$D/body"); ce=$(<"$D/curl_exit")
if [[ -s "$D/stderr" ]]; then printf "%s\n" "$(<"$D/stderr")" >&2; fi
if [[ "$ce" != 0 ]]; then exit "$ce"; fi
if [[ "$status" == NONE ]]; then exit 0; fi
printf "%s\n%s" "$body" "$status"
STUB_EOF
if [[ -n "$INNER" && -n "${CF_RO_STUB_BLIND:-}" ]]; then
  sed -i 's|^ARGLOG=.*|ARGLOG=/dev/null|' "$STUB/curl"
fi
chmod +x "$STUB/curl"

SUTC="$WORK/cf.sh"
# Sandbox copy: exactly one line is rewritten. Returns non-zero (and says why) otherwise.
make_sandbox() { # $1 source, $2 destination
  local src="$1" dst="$2" n
  assert_fixture_dir "$dst"
  n=$(grep -c '^CURL=/usr/bin/curl$' "$src")
  if [[ "$n" != 1 ]]; then return 1; fi
  sed "s|^CURL=/usr/bin/curl\$|CURL=$STUB/curl|" "$src" > "$dst"
  chmod +x "$dst"
  grep -qF "CURL=$STUB/curl" "$dst"
}
SANDBOX_OK=1
if ! make_sandbox "$SUT_SRC" "$SUTC"; then SANDBOX_OK=0; fi

# --- scenario plumbing ---
fixture() { # status body [curl_exit] [stderr-text]
  assert_fixture_dir "$STUB"
  printf '%s' "$1" > "$STUB/status"
  printf '%s' "$2" > "$STUB/body"
  printf '%s' "${3:-0}" > "$STUB/curl_exit"
  printf '%s' "${4:-}" > "$STUB/stderr"
  rm -f "${STUB:?}/calls.log" "${STUB:?}/argv.bin" "${STUB:?}/stdin.log" "${STUB:?}/env.log" "${STUB:?}/refusal.log"
}
RUNFLAGS=()
OUT="" ERR="" RC=0 L1=""
run() { # run [NAME=value ...] -- args...
  assert_fixture_dir "$WORK"
  local -a ev=()
  while [[ $# -gt 0 && "$1" != "--" ]]; do ev+=("$1"); shift; done
  shift
  OUT=$(/usr/bin/env -i PATH=/usr/bin:/bin ${ev[@]+"${ev[@]}"} "$BASH" ${RUNFLAGS[@]+"${RUNFLAGS[@]}"} "${SUTX:-$SUTC}" "$@" 2>"$WORK/err.txt" </dev/null)
  RC=$?
  ERR=$(<"$WORK/err.txt")
  { printf '%s\n' "$OUT"; printf '%s\n' "$ERR"; } > "$WORK/comb.txt"
  L1="${OUT%%$'\n'*}"
}
ENVX=()
mkenv() { # mkenv NAME... : BASE_ENV without the named variables
  ENVX=()
  local e n skip
  for e in "${BASE_ENV[@]}"; do
    skip=0
    for n in "$@"; do [[ "${e%%=*}" == "$n" ]] && skip=1; done
    if [[ "$skip" == 0 ]]; then ENVX+=("$e"); fi
  done
}
ncalls() {
  local -a l=()
  if [[ -f "$STUB/calls.log" ]]; then mapfile -t l < "$STUB/calls.log"; fi
  printf '%s' "${#l[@]}"
}
ARGV=()
last_arg() {
  local n=${#ARGV[@]}
  if ((n > 0)); then printf '%s' "${ARGV[$((n - 1))]}"; fi
}
load_argv() {
  ARGV=()
  if [[ -f "$STUB/argv.bin" ]]; then mapfile -d '' -t ARGV < "$STUB/argv.bin"; fi
}
tok_of() { # bound token value per subcommand
  case "$1" in
    ssl-mode) printf '%s' "$TOK_Z" ;;
    config-entrypoint | pagerules-ssl) printf '%s' "$TOK_R" ;;
    change-history) printf '%s' "$TOK_A" ;;
  esac
}
tokvar_of() {
  case "$1" in
    ssl-mode) printf '%s' CF_API_TOKEN_ZONE_SETTINGS ;;
    config-entrypoint | pagerules-ssl) printf '%s' CF_API_TOKEN_RULESETS ;;
    change-history) printf '%s' CF_API_TOKEN_AUDIT ;;
  esac
}
url_of() {
  case "$1" in
    ssl-mode) printf '%s' "$BASE_URL/zones/$ZONE/settings/ssl" ;;
    config-entrypoint) printf '%s' "$BASE_URL/zones/$ZONE/rulesets/phases/http_config_settings/entrypoint" ;;
    pagerules-ssl) printf '%s' "$BASE_URL/zones/$ZONE/pagerules?status=active" ;;
  esac
}

# leak scan: 0 when the file is CLEAN, 1 when any needle is found (grep -F, never a regex)
leak_scan() {
  local f="$1" n
  for n in "${LEAK_NEEDLES[@]}"; do
    [[ -n "$n" ]] || return 2
    if grep -qF -- "$n" "$f"; then return 1; fi
  done
  return 0
}
has_file() { grep -qF -- "$2" "$1"; }
eq() { [[ "$1" == "$2" ]]; }
contains() { [[ "$1" == *"$2"* ]]; }

# --- bodies ---
SSL_OK='{"result":{"id":"ssl","value":"strict","editable":true,"modified_on":"2026-10-01T12:00:00.000000Z"},"success":true,"errors":[],"messages":[]}'
ENTRY_OK='{"success":true,"errors":[],"messages":[],"result":{"zz_extra":{"a":1},"rules":[{"id":"r1id","ref":"aaa111","version":"2","enabled":false,"action":"set_config","action_parameters":{"ssl":"strict"},"expression":"(http.host eq \"other.example\") EXPR_CANARY_1","description":"DESC_CANARY_1","last_updated":"2026-10-01T12:00:00Z"},{"ref":"dcb85b75bc3c4f4aa2a8c13a080bf854","enabled":true,"action":"set_config","action_parameters":{"ssl":"flexible"},"expression":"(http.host in {\"app.soleur.ai\" \"lb-staging.soleur.ai\"}) EXPR_CANARY_2","description":"DESC_CANARY_2","unknown_field":[1,2]},{"ref":"ccc333","enabled":true,"action":"set_config","action_parameters":{"ssl":"full"},"expression":"(http.host eq \"app.soleur.ai.evil\")"}],"description":"DESC_CANARY_TOP","name":"default","kind":"zone","phase":"http_config_settings","last_updated":"2026-10-01T12:00:00.000000Z","id":"entryid123","version":"7"}}'
PAGE_OK='{"success":true,"errors":[],"messages":[],"result":[{"id":"pr1","status":"active","priority":1,"targets":[{"target":"url","constraint":{"operator":"matches","value":"*app.soleur.ai/*PATTERN_CANARY"}}],"actions":[{"id":"always_use_https"},{"id":"ssl","value":"flexible"}]},{"id":"pr2","status":"active","priority":2,"targets":[{"target":"url","constraint":{"operator":"matches","value":"*other.example/*"}}],"actions":[{"id":"forwarding_url","value":{"url":"https://x.example","status_code":301}}]}]}'
audit_body() { # $1 = number of rows
  jq -nc --argjson n "$1" '{success:true,errors:[],messages:[],result:[range($n)|{id:("row"+tostring),action:{type:(if .%2==0 then "token_create" else "zone.ruleset_update" end),time:("2026-11-0"+((.%9+1)|tostring)+"T10:00:00Z"),result:true},actor:{email:"ACTOR_CANARY@example.com",ip:"203.0.113.77",type:"user"},resource:{type:"token",id:"x"}}],result_info:{count:($n|tostring),cursor:"c"}}'
}
ok_body() {
  case "$1" in
    ssl-mode) printf '%s' "$SSL_OK" ;;
    config-entrypoint) printf '%s' "$ENTRY_OK" ;;
    pagerules-ssl) printf '%s' "$PAGE_OK" ;;
    change-history) audit_body 3 ;;
  esac
}
ERR_BODY="{\"success\":false,\"errors\":[{\"code\":10000,\"message\":\"Authentication error $CANARY_BODY\"}],\"result\":null}"

EXERCISED=0
WIRE_ROWS=0
REFUSE_ROWS=0

# =============================================================================================
# Group: source (static guards on the wrapper file, each lacks-anchor paired with a has-anchor)
# =============================================================================================
STRIPPED="$WORK/stripped.sh"
assert_fixture_dir "$STRIPPED"
sed -E '/^[[:space:]]*#/d' "$SUT_SRC" > "$STRIPPED"
src_has() { grep -Eq -- "$1" "$STRIPPED"; }
count_sites() { grep -cF -- '"$CURL"' "$1"; }

# Subcommand set extraction (comments already stripped).
array_names() {
  local line
  line=$(grep -E '^SUBCOMMANDS=\(' "$1" | head -n 1)
  line="${line#SUBCOMMANDS=(}"
  line="${line%)}"
  printf '%s\n' $line
}
# Tolerant: any leading whitespace, optional single/double quotes, `a|b)` alternations; the default arm `*` is dropped.
LABEL_RE="^[[:space:]]*[\"']?[^[:space:]|)(;\"']+[\"']?([|][\"']?[^[:space:]|)(;\"']+[\"']?)*\\)"
dispatcher_block() {
  awk '/^[[:space:]]*case "\$SUB" in/{f=1;next} /^[[:space:]]*esac/{f=0} f' "$1"
}
case_labels() {
  dispatcher_block "$1" | grep -Eo "$LABEL_RE" | tr -d " \t)\"'" | tr '|' '\n' | grep -vx '\*'
}
case_arm_count() { # number of `;;` arm terminators inside the dispatcher block
  dispatcher_block "$1" | grep -o ';;' | wc -l
}
cf_get_sites() { grep -cE '(^|[^[:alnum:]_])cf_get[[:space:]]+[^[:space:]()]' "$1"; }
cf_get_args() { grep -oE '(^|[^[:alnum:]_])cf_get[[:space:]]+"[^"]+"' "$1" | sed -E 's/^[^c]*cf_get[[:space:]]+//' | sort; }
curl_assigns() { grep -cE '(^|[^[:alnum:]_])CURL[[:space:]]*\+?=' "$1"; }
# jq / date census: every invocation line (outside the -x preflight tests) must run behind an empty environment.
tool_lines() { grep -E '/usr/bin/(jq|date)' "$1" | grep -vE '\[ -x '; }
tool_unwrapped() { tool_lines "$1" | grep -vE '/usr/bin/env -i /usr/bin/(jq|date)'; }
xtrace_names() { grep -oE '\$\{[A-Z_]+:\+x\}' "$1" | sed -E 's/^\$\{([A-Z_]+):\+x\}$/\1/' | sort -u; }
tokvar_names() { grep -oE 'TOKVAR=CF_[A-Z_]+' "$1" | sed 's/^TOKVAR=//' | sort -u; }
sorted_join() { printf '%s\n' "$@" | sort | tr '\n' ' '; }

grp_source() {
  t "source: wrapper file is non-empty after comment stripping (anchor for every lacks-row)" test -s "$STRIPPED"
  t "source: sandbox rewrite of CURL= matches exactly once" test "$SANDBOX_OK" = 1
  t "source: literal CURL=/usr/bin/curl is present" grep -qx 'CURL=/usr/bin/curl' "$STRIPPED"
  t "source: no environment override of the curl path (no CURL=\${...})" bash -c '! grep -Eq "^CURL=.*[$]" "$1"' _ "$STRIPPED"
  t "source: anchor - set -uo pipefail is present" src_has '^set -uo pipefail'
  tn "source: no set -x / xtrace enabling" src_has '(^|[;[:space:]])set[[:space:]]+-[A-Za-z]*x|xtrace'
  t "source: anchor - xtrace refusal case present" src_has 'case "\$-" in'
  tn "source: no 2>/dev/null" src_has '2>[[:space:]]*/dev/null'
  tn "source: no mktemp" src_has 'mktemp'
  tn "source: no eval" src_has '(^|[^[:alnum:]_])eval([^[:alnum:]_]|$)'
  tn "source: no here-string or heredoc (<<)" src_has '<<'
  t "source: exactly one curl call site" eq "$(count_sites "$STRIPPED")" 1
  tn "source: no bare curl command (curl by name)" src_has '^[[:space:]]*(/usr/bin/env -i )?curl[[:space:]]'
  assert_fixture_dir "$WORK"
  grep -F -- '"$CURL"' "$STRIPPED" > "$WORK/curl_lines.txt" || true
  t "source: anchor - the curl invocation line was extracted" test -s "$WORK/curl_lines.txt"
  tn "source: no -L / --location / -d / --data / --json / -T / -F flag on the curl line" grep -Eq '(^|[[:space:]])(-L|--location|-d|--data[a-z-]*|--json|-T|-F)([[:space:]]|$)' "$WORK/curl_lines.txt"
  t "source: anchor - -X GET present" src_has '-X GET'
  t "source: anchor - --disable present" src_has -- '--disable'
  t "source: anchor - env -i curl invocation" src_has '/usr/bin/env -i "\$CURL" --disable'
  t "source: shebang is #!/usr/bin/env bash" eq "$(head -n 1 "$SUT_SRC")" '#!/usr/bin/env bash'
  if [[ "$SUT_SRC" == "$PROD" ]]; then
    t "source: production file is executable (test -x)" test -x "$PROD"
  fi
  t "source: header documents direct-exec invocation" has_file "$SUT_SRC" 'doppler run -p soleur -c prd_terraform -- plugins/soleur/scripts/cloudflare-readonly.sh'
  tn "source: header never shows doppler run ... -- bash" grep -Eq -- '--[[:space:]]+bash' "$SUT_SRC"
  # census controls: the scan is live
  assert_fixture_dir "$WORK"
  printf '%s\n' 'x=$("$CURL" a)' 'y=$("$CURL" b)' > "$WORK/c2.txt"
  printf '%s\n' 'command -v curl >/dev/null' 'echo "curl exit"' > "$WORK/c0.txt"
  printf '%s\n' 'x=$(/usr/bin/env -i "$CURL" a)' > "$WORK/c1.txt"
  t "source control: a 2-site fixture counts 2" eq "$(count_sites "$WORK/c2.txt")" 2
  t "source control: a command -v fixture counts 0" eq "$(count_sites "$WORK/c0.txt")" 0
  t "source control: a 1-site fixture counts 1" eq "$(count_sites "$WORK/c1.txt")" 1
  # parity: array == case labels == --list output; non-empty and length 4
  local -a arr=() lab=() lst=()
  mapfile -t arr < <(array_names "$STRIPPED")
  mapfile -t lab < <(case_labels "$STRIPPED")
  run -- --list
  mapfile -t lst <<<"$OUT"
  t "parity: SUBCOMMANDS array is non-empty with length 4" eq "${#arr[@]}" 4
  t "parity: dispatcher case labels are non-empty with length 4" eq "${#lab[@]}" 4
  t "parity: --list output has length 4" eq "${#lst[@]}" 4
  t "parity: array == case labels == --list (set equality)" eq "$(sorted_join "${arr[@]}")|$(sorted_join "${lab[@]}")" "$(sorted_join "${lst[@]}")|$(sorted_join "${arr[@]}")"
  t "parity: array equals the four expected names" eq "$(sorted_join "${arr[@]}")" "$(sorted_join "${SUBS[@]}")"
  t "list: --list exits 0" eq "$RC" 0
  t "list: --list names no Doppler project/config and calls no curl" bash -c '! grep -Eqi "doppler|prd" "$1"' _ "$WORK/comb.txt"
  t "list: --list never invoked curl" eq "$(ncalls)" 0

  # --- censuses: the request set, the curl binding, the child environments (each paired with a control fixture) ---
  assert_fixture_dir "$WORK"
  t "census: dispatcher arm terminators == 5 (four arms plus the refusing default)" eq "$(case_arm_count "$STRIPPED")" 5
  printf '%s\n' 'case "$SUB" in' "   \"raw\"|'purge') x ;;" $'\tzap) y ;;' '  *) z ;;' 'esac' > "$WORK/cl.txt"
  t "census control: the tolerant label extractor sees tab, 3-space, quoted and alternation arms" eq "$(case_labels "$WORK/cl.txt" | sort | tr '\n' ' ')" "purge raw zap "
  t "census control: the arm counter sees every terminator" eq "$(case_arm_count "$WORK/cl.txt")" 3
  t "census: exactly four cf_get call sites outside the function" eq "$(cf_get_sites "$STRIPPED")" 4
  local want_tpl
  want_tpl=$(printf '%s\n' \
    '"$BASE/accounts/$CF_ACCOUNT_ID/logs/audit?since=$since&before=$now&limit=$LIMIT&direction=desc"' \
    '"$BASE/zones/$CF_ZONE_ID/pagerules?status=active"' \
    '"$BASE/zones/$CF_ZONE_ID/rulesets/phases/http_config_settings/entrypoint"' \
    '"$BASE/zones/$CF_ZONE_ID/settings/ssl"' | sort | tr '\n' ' ')
  t "census: the four cf_get URL templates are exactly the fixed four" eq "$(cf_get_args "$STRIPPED" | tr '\n' ' ')" "$want_tpl"
  printf '%s\n' 'cf_get() { x; }' '  cf_get "a"' 'y; cf_get "b"' > "$WORK/g2.txt"
  t "census control: the function definition is not a call site; two calls count 2" eq "$(cf_get_sites "$WORK/g2.txt")" 2
  t "census: CURL is assigned exactly once" eq "$(curl_assigns "$STRIPPED")" 1
  t "census: that one assignment is the column-0 literal" eq "$(grep -cx 'CURL=/usr/bin/curl' "$STRIPPED")" 1
  tn "census: CURL is never exported, declared, read into or printf -v'd" src_has '(export|declare|typeset|readonly|local)[[:space:]]+(-[A-Za-z]+[[:space:]]+)?CURL|printf[[:space:]]+-v[[:space:]]+CURL|read[^;]*[[:space:]]CURL'
  printf '%s\n' '  [ -n "${X:-}" ] && CURL=$X' > "$WORK/cu1.txt"
  printf '%s\n' 'export CURL=/x' > "$WORK/cu2.txt"
  t "census control: an indented conditional override counts 1" eq "$(curl_assigns "$WORK/cu1.txt")" 1
  t "census control: an exported form counts 1" eq "$(curl_assigns "$WORK/cu2.txt")" 1
  t "census: anchor - jq runs in exactly 2 places and date in exactly 2, each behind env -i" bash -c '[[ "$(grep -c "/usr/bin/env -i /usr/bin/jq " "$1")" == 2 && "$(grep -c "/usr/bin/env -i /usr/bin/date " "$1")" == 2 ]]' _ "$STRIPPED"
  t "census: every /usr/bin/jq or /usr/bin/date invocation runs behind env -i (empty HOME, empty \$ENV)" eq "$(tool_unwrapped "$STRIPPED" | wc -l)" 0
  tn "census: no bare jq or date command" src_has '(^|[^[:alnum:]_/.-])(jq|date)[[:space:]]+-'
  printf '%s\n' 'x=$(/usr/bin/jq -c a)' > "$WORK/tw1.txt"
  printf '%s\n' 'x=$(/usr/bin/env -i /usr/bin/jq -c a)' '[ -x /usr/bin/jq ] || exit 1' > "$WORK/tw0.txt"
  t "census control: an unwrapped jq line is counted" eq "$(tool_unwrapped "$WORK/tw1.txt" | wc -l)" 1
  t "census control: a wrapped jq line and the -x preflight are not counted" eq "$(tool_unwrapped "$WORK/tw0.txt" | wc -l)" 0
  tn "census: no token, zone or account variable on any jq/date line" bash -c 'grep -E "/usr/bin/(jq|date)" "$1" | grep -Eq "TOK|CF_API|CF_ZONE|CF_ACCOUNT|[$][{]?[!]"' _ "$STRIPPED"
  printf '%s\n' 'x=$(/usr/bin/env -i /usr/bin/jq -c --arg t "$TOK" a)' > "$WORK/tk1.txt"
  tn "census control: a token variable on a jq line is detected" bash -c '! { grep -E "/usr/bin/(jq|date)" "$1" | grep -Eq "TOK|CF_API|CF_ZONE|CF_ACCOUNT|[$][{]?[!]"; }' _ "$WORK/tk1.txt"
  tn "source: no export of the token" src_has '(^|[;[:space:]])(export|declare[[:space:]]+-[A-Za-z]*x)[[:space:]]+(-[A-Za-z]+[[:space:]]+)?TOK'
  tn "source: no /dev/shm" src_has '/dev/shm'
  tn "source: no tee" src_has '(^|[^[:alnum:]_-])tee([^[:alnum:]_-]|$)'
  tn "source: no exec file-descriptor redirection" src_has '(^|[;[:space:]])exec[[:space:]]+[0-9]*[<>]'
  tn "source: no jq --arg / --args / --rawfile / --slurpfile / --jsonargs" src_has '[[:space:]]--(arg|args|rawfile|slurpfile|jsonargs)([[:space:]]|$)'
  tn "source: no NAME=value prefix on an env child" src_has '/usr/bin/env[[:space:]]+([A-Z_]+=|-[A-Za-z]*[[:space:]]+[A-Z_]+=)'
  t "source: the xtrace refusal list names exactly the dispatcher TOKVAR names plus CF_API_TOKEN" eq "$(xtrace_names "$STRIPPED" | tr '\n' ' ')" "$({ tokvar_names "$STRIPPED"; echo CF_API_TOKEN; } | sort -u | tr '\n' ' ')"
  t "source: anchor - the dispatcher binds exactly three token variables" eq "$(tokvar_names "$STRIPPED" | wc -l)" 3
  t "source: LIMIT is assigned once as 50" eq "$(grep -cE '^LIMIT=50$' "$STRIPPED")" 1
  t "source: the literal 50 appears exactly once (the LIMIT assignment)" eq "$(grep -cw '50' "$STRIPPED")" 1
  t "source: the truncated test reads the same LIMIT via --argjson" src_has 'argjson limit "\$LIMIT"'
  t "source: the audit URL template uses \$LIMIT" src_has 'limit=\$LIMIT&direction=desc'
}

# =============================================================================================
# Group: wire (what actually reaches curl)
# =============================================================================================
# The wrapper's curl argv is a CLOSED vector: these ten tokens in this order, then the URL. A deny-list of known-bad
# flags cannot see a duplicated -X, a glued -XPOST, --connect-to, -k or --config /dev/null; full equality does.
EXP=(--disable --noproxy '*' -X GET -sS --max-time 20 --max-redirs 0 -w $'\n%{http_code}' --config -)
argv_equal() { # ARGV == EXP + one trailing URL element
  local n=${#ARGV[@]} m=${#EXP[@]} i
  [[ "$n" == "$((m + 1))" ]] || return 1
  for ((i = 0; i < m; i++)); do [[ "${ARGV[$i]}" == "${EXP[$i]}" ]] || return 1; done
}
check_wire() { # $1 = subcommand
  local sub="$1" tok url a i got_x=0 got_redir=0 bad=0 tokleak=0 n
  tok=$(tok_of "$sub")
  fixture 200 "$(ok_body "$sub")"
  run "${BASE_ENV[@]}" "CF_API_BASE=https://evil.example" "CF_API_TOKEN=$TOK_BARE" -- "$sub"
  load_argv
  t "wire[$sub]: run is ok" eq "$L1" "cloudflare-readonly: $sub ok"
  t "wire[$sub]: curl called exactly once" eq "$(ncalls)" 1
  WIRE_ROWS=$((WIRE_ROWS + 1))
  t "wire[$sub]: recorded argv is non-empty (anti-vacuity floor)" test "${#ARGV[@]}" -gt 0
  t "wire[$sub]: argv[1] is --disable" eq "${ARGV[0]:-}" "--disable"
  t "wire[$sub]: recorded argv equals the closed vector (full equality, URL last)" argv_equal
  t "wire[$sub]: the stub refused no flag (refusal log absent or empty)" test ! -s "$STUB/refusal.log"
  for ((i = 0; i < ${#ARGV[@]}; i++)); do
    a="${ARGV[$i]}"
    if [[ "$a" == "-X" && "${ARGV[$((i + 1))]:-}" == "GET" ]]; then got_x=1; fi
    if [[ "$a" == "--max-redirs" && "${ARGV[$((i + 1))]:-}" == "0" ]]; then got_redir=1; fi
    case "$a" in
      -d | --data* | --json | -T | --upload-file | -F | --form | -L | --location | --url | -u | --user | -H | --header | --request | -K) bad=1 ;;
    esac
    for n in "$TOK_Z" "$TOK_R" "$TOK_A" "$TOK_BARE"; do
      if [[ "$a" == *"$n"* ]]; then tokleak=1; fi
    done
    if [[ "$a" == *Authorization* || "$a" == *Bearer* ]]; then tokleak=1; fi
  done
  t "wire[$sub]: argv has -X GET" eq "$got_x" 1
  t "wire[$sub]: argv has --max-redirs 0" eq "$got_redir" 1
  t "wire[$sub]: argv has none of -d --data* --json -T -F -L -H --url -u" eq "$bad" 0
  t "wire[$sub]: argv carries no token, Authorization or Bearer" eq "$tokleak" 0
  if [[ "$sub" == change-history ]]; then
    url="$(last_arg)"
    local re="^https://api\.cloudflare\.com/client/v4/accounts/$ACCT/logs/audit\?since=([0-9T:Z-]+)&before=([0-9T:Z-]+)&limit=50&direction=desc\$"
    t "wire[$sub]: URL matches the fixed audit template with both since and before" bash -c '[[ "$1" =~ $2 ]]' _ "$url" "$re"
    if [[ "$url" =~ $re ]]; then
      local now s b
      now=$(date -u +%s)
      s=$(date -u -d "${BASH_REMATCH[1]}" +%s 2>/dev/null || echo 0)
      b=$(date -u -d "${BASH_REMATCH[2]}" +%s 2>/dev/null || echo 0)
      t "wire[$sub]: before is now within 2 minutes" test "$((b - now))" -ge -120 -a "$((b - now))" -le 120
      t "wire[$sub]: since is now-7d within 2 minutes" test "$((s - (now - 604800)))" -ge -120 -a "$((s - (now - 604800)))" -le 120
    else
      t "wire[$sub]: since/before parse (template did not match)" false
    fi
  else
    t "wire[$sub]: last argv is the exact fixed URL" eq "$(last_arg)" "$(url_of "$sub")"
  fi
  t "wire[$sub]: URL host is api.cloudflare.com despite a planted CF_API_BASE" bash -c '[[ "$1" == https://api.cloudflare.com/client/v4/* ]]' _ "$(last_arg)"
  t "wire[$sub]: stdin carries the bound token exactly once on one config line" eq "$(grep -cF -- "header = \"Authorization: Bearer $tok\"" "$STUB/stdin.log" 2>/dev/null || true)" 1
  t "wire[$sub]: stdin is exactly one line" eq "$(wc -l < "$STUB/stdin.log" 2>/dev/null || echo 0)" 1
  for n in "$TOK_Z" "$TOK_R" "$TOK_A" "$TOK_BARE"; do
    if [[ "$n" != "$tok" ]]; then
      tn "wire[$sub]: stdin carries no other token ($n)" has_file "$STUB/stdin.log" "$n"
    fi
  done
}
grp_wire() {
  local s
  # closed-vector controls: the equality check itself is live
  local -a keep=("${ARGV[@]}")
  ARGV=("${EXP[@]}" "https://x")
  t "wire control: the exact vector plus a URL is accepted" argv_equal
  ARGV=(--disable --noproxy '*' -X GET -X GET -sS --max-time 20 --max-redirs 0 -w $'\n%{http_code}' --config - "https://x")
  tn "wire control: a duplicated -X is rejected" argv_equal
  ARGV=(--disable --noproxy '*' -XPOST -sS --max-time 20 --max-redirs 0 -w $'\n%{http_code}' --config - "https://x")
  tn "wire control: a glued -XPOST is rejected" argv_equal
  ARGV=("${EXP[@]}")
  tn "wire control: a vector with no URL is rejected" argv_equal
  ARGV=("${keep[@]}")
  for s in "${SUBS[@]}"; do check_wire "$s"; done
  # must-pass non-canonical: a different zone id is substituted into the URL
  fixture 200 "$SSL_OK"
  run "DOPPLER_PROJECT=soleur" "DOPPLER_CONFIG=prd_terraform" "CF_ZONE_ID=$ZONE_ALT" "CF_API_TOKEN_ZONE_SETTINGS=$TOK_Z" -- ssl-mode
  load_argv
  t "wire: a different zone id lands in the URL" eq "$(last_arg)" "$BASE_URL/zones/$ZONE_ALT/settings/ssl"
  t "wire: a different zone id still runs ok" eq "$L1" "cloudflare-readonly: ssl-mode ok"
}

# =============================================================================================
# Group: refuse (nothing is sent)
# =============================================================================================
refused() { # refused <label> <args...> : rc 64, curl never called
  local label="$1"
  shift
  fixture 200 "$SSL_OK"
  run "${BASE_ENV[@]}" -- "$@"
  REFUSE_ROWS=$((REFUSE_ROWS + 1))
  t "refuse: $label -> exit 64" eq "$RC" 64
  t "refuse: $label -> curl never called" eq "$(ncalls)" 0
  tn "refuse: $label -> no ok verdict" contains "$OUT" " ok"
}
grp_refuse() {
  refused "unknown subcommand raw" raw
  refused "ssl-mode/extra" ssl-mode/extra
  refused "path traversal ../x" ../x
  refused "url https://evil.example" https://evil.example
  refused "empty subcommand" ""
  refused "flag -X alone" -X
  refused "no arguments"
  refused "uppercase SSL-MODE" SSL-MODE
  refused "trailing space" "ssl-mode "
  refused "extra positional" ssl-mode extra
  refused "-X POST" -X POST
  refused "ssl-mode -X DELETE" ssl-mode -X DELETE
  refused "--method DELETE" --method DELETE
  refused "--data x" --data x
  refused "ssl-mode --data x" ssl-mode --data x
  refused "--url https://evil.example" --url https://evil.example
  refused "--since-days 3" --since-days 3
  refused "change-history --since-days 3" change-history --since-days 3
  refused "--path /zones" --path /zones
  refused "--token-var CF_API_TOKEN" --token-var CF_API_TOKEN
  refused "--list plus extra" --list extra
  # source pins
  fixture 200 "$SSL_OK"
  run "DOPPLER_PROJECT=soleur" "DOPPLER_CONFIG=dev" "CF_ZONE_ID=$ZONE" "CF_API_TOKEN_ZONE_SETTINGS=$TOK_Z" -- ssl-mode
  t "refuse: DOPPLER_CONFIG=dev -> exit 64" eq "$RC" 64
  t "refuse: DOPPLER_CONFIG=dev -> curl never called" eq "$(ncalls)" 0
  run "DOPPLER_PROJECT=soleur" "CF_ZONE_ID=$ZONE" "CF_API_TOKEN_ZONE_SETTINGS=$TOK_Z" -- ssl-mode
  t "refuse: DOPPLER_CONFIG unset -> exit 64" eq "$RC" 64
  t "refuse: DOPPLER_CONFIG unset -> curl never called" eq "$(ncalls)" 0
  run "DOPPLER_PROJECT=other" "DOPPLER_CONFIG=prd_terraform" "CF_ZONE_ID=$ZONE" "CF_API_TOKEN_ZONE_SETTINGS=$TOK_Z" -- ssl-mode
  t "refuse: DOPPLER_PROJECT=other -> exit 64" eq "$RC" 64
  t "refuse: DOPPLER_PROJECT=other -> curl never called" eq "$(ncalls)" 0
  run "CF_ZONE_ID=$ZONE" "CF_API_TOKEN_ZONE_SETTINGS=$TOK_Z" -- ssl-mode
  t "refuse: both DOPPLER_* unset -> exit 64" eq "$RC" 64
  mkenv CF_ZONE_ID
  run "${ENVX[@]}" "CF_ZONE_ID=not-hex-zone" -- ssl-mode
  t "refuse: non-hex CF_ZONE_ID -> exit 64" eq "$RC" 64
  t "refuse: non-hex CF_ZONE_ID -> curl never called" eq "$(ncalls)" 0
  t "refuse: non-hex CF_ZONE_ID names the variable, not the value" bash -c '[[ "$1" == *CF_ZONE_ID* && "$1" != *not-hex-zone* ]]' _ "$(<"$WORK/comb.txt")"
  mkenv CF_ACCOUNT_ID
  run "${ENVX[@]}" "CF_ACCOUNT_ID=XYZ" -- change-history
  t "refuse: non-hex CF_ACCOUNT_ID -> exit 64" eq "$RC" 64
  t "refuse: non-hex CF_ACCOUNT_ID -> curl never called" eq "$(ncalls)" 0
  # --- the Doppler hint: an UNSET source names the one way to run it; a wrong value does not echo anything back ---
  run "CF_ZONE_ID=$ZONE" "CF_API_TOKEN_ZONE_SETTINGS=$TOK_Z" -- ssl-mode
  t "refuse: unset DOPPLER_* -> the message carries the fixed run-under hint" contains "$ERR" "run under: doppler run -p soleur -c prd_terraform --"
  run "DOPPLER_PROJECT=soleur" "DOPPLER_CONFIG=dev" "CF_ZONE_ID=$ZONE" "CF_API_TOKEN_ZONE_SETTINGS=$TOK_Z" -- ssl-mode
  tn "refuse: a wrong DOPPLER_CONFIG value is not echoed back" contains "$ERR" "dev"

  # --- id shapes: the value is spliced into a URL path, so every near-miss is refused before any request ---
  local idv idlabel idvar idcmd
  for idvar in CF_ZONE_ID CF_ACCOUNT_ID; do
    if [[ "$idvar" == CF_ZONE_ID ]]; then idcmd=ssl-mode; else idcmd=change-history; fi
    for idlabel in "path-dot-dot:${ZONE}/.." "query:${ZONE}?q" "fragment:${ZONE}#" "hex31:${ZONE:0:31}" "hex33:${ZONE}0" "uppercase:${ZONE^^}" "trailing-newline:${ZONE}"$'\n' "slash:${ZONE}/x"; do
      idv="${idlabel#*:}"
      fixture 200 "$(ok_body "$idcmd")"
      mkenv "$idvar"
      run "${ENVX[@]}" "$idvar=$idv" -- "$idcmd"
      REFUSE_ROWS=$((REFUSE_ROWS + 1))
      t "refuse: $idvar ${idlabel%%:*} -> exit 64" eq "$RC" 64
      t "refuse: $idvar ${idlabel%%:*} -> curl never called" eq "$(ncalls)" 0
      tn "refuse: $idvar ${idlabel%%:*} -> no ok verdict" contains "$OUT" " ok"
    done
  done

  # --- unknown-subcommand fuzz: whatever the name, exit 64 and curl is never invoked ---
  local fz
  for fz in api.cloudflare.com evil.example purge delete raw Ssl-Mode SSL-MODE '"ssl-mode"' "'ssl-mode'" 'ssl-mode;id' '$(id)' 'ssl-mode|raw' '*' 'ssl-*' '[s]sl-mode' '?sl-mode' 'ssl-mode ' ' ssl-mode' $'ssl-mode\n' 'ssl_mode' 'zones' '--' '-' '-h' 'help' 'status'; do
    fixture 200 "$SSL_OK"
    run "${BASE_ENV[@]}" -- "$fz"
    REFUSE_ROWS=$((REFUSE_ROWS + 1))
    t "refuse fuzz: name $(printf '%q' "$fz") -> exit 64 and curl never called" bash -c '[[ "$1" == 64 && "$2" == 0 ]]' _ "$RC" "$(ncalls)"
  done
  t "refuse floor: at least 60 refusal rows were exercised (zero checked is RED)" test "$((REFUSE_ROWS * 3))" -ge 60
}

# =============================================================================================
# Group: token (binding, shape, trim, fallback)
# =============================================================================================
grp_token() {
  local s v
  # shape refusals
  for s in 'ab cd' 'ab"cd' $'abc\nurl = "https://evil.example"' 'ab\cd' $'ab\tcd' ''; do
    fixture 200 "$SSL_OK"
    mkenv CF_API_TOKEN_ZONE_SETTINGS
    run "${ENVX[@]}" "CF_API_TOKEN_ZONE_SETTINGS=$s" -- ssl-mode
    if [[ -z "$s" ]]; then
      t "token: empty bound token -> exit 10 no-credential" eq "$RC" 10
    else
      t "token: refused shape ($(printf '%q' "$s")) -> exit 64" eq "$RC" 64
    fi
    t "token: refused/empty shape ($(printf '%q' "$s")) -> curl never called" eq "$(ncalls)" 0
  done
  # a trailing newline / spaces is trimmed and sent trimmed
  fixture 200 "$SSL_OK"
  mkenv CF_API_TOKEN_ZONE_SETTINGS
  run "${ENVX[@]}" "CF_API_TOKEN_ZONE_SETTINGS=$TOK_Z"$'\n' -- ssl-mode
  t "token: trailing newline is accepted (trimmed)" eq "$L1" "cloudflare-readonly: ssl-mode ok"
  t "token: trailing newline is sent trimmed (closing quote follows the token)" eq "$(grep -cF -- "header = \"Authorization: Bearer $TOK_Z\"" "$STUB/stdin.log" 2>/dev/null || true)" 1
  run "${ENVX[@]}" "CF_API_TOKEN_ZONE_SETTINGS=$TOK_Z   " -- ssl-mode
  t "token: trailing spaces are accepted (trimmed)" eq "$L1" "cloudflare-readonly: ssl-mode ok"
  # missing bound variable per subcommand
  for s in "${SUBS[@]}"; do
    v=$(tokvar_of "$s")
    fixture 200 "$(ok_body "$s")"
    mkenv "$v"
    run "${ENVX[@]}" -- "$s"
    t "token[$s]: missing $v -> exit 10" eq "$RC" 10
    t "token[$s]: missing $v -> unverified - no-credential naming the variable" eq "$L1" "cloudflare-readonly: $s unverified - no-credential ($v)"
    t "token[$s]: missing $v -> curl never called" eq "$(ncalls)" 0
    # only CF_API_TOKEN is present: no fallback
    mkenv "$v"
    run "${ENVX[@]}" "CF_API_TOKEN=$TOK_BARE" -- "$s"
    t "token[$s]: only CF_API_TOKEN present -> exit 10 (no fallback)" eq "$RC" 10
    t "token[$s]: only CF_API_TOKEN present -> curl never called" eq "$(ncalls)" 0
    # bound + CF_API_TOKEN present: the bound one only
    fixture 200 "$(ok_body "$s")"
    run "${BASE_ENV[@]}" "CF_API_TOKEN=$TOK_BARE" -- "$s"
    tn "token[$s]: CF_API_TOKEN value never reaches stdin" has_file "$STUB/stdin.log" "$TOK_BARE"
    t "token[$s]: bound token reaches stdin" has_file "$STUB/stdin.log" "$(tok_of "$s")"
  done
  mkenv CF_ACCOUNT_ID
  run "${ENVX[@]}" -- change-history
  t "token: change-history without CF_ACCOUNT_ID -> exit 10 naming CF_ACCOUNT_ID" eq "$L1" "cloudflare-readonly: change-history unverified - no-credential (CF_ACCOUNT_ID)"
  mkenv CF_ZONE_ID
  run "${ENVX[@]}" -- ssl-mode
  t "token: ssl-mode without CF_ZONE_ID -> exit 10" eq "$RC" 10
  # binding is distinct per subcommand: ssl-mode must not use the rulesets/audit token
  mkenv CF_API_TOKEN_ZONE_SETTINGS
  fixture 200 "$SSL_OK"
  run "${ENVX[@]}" -- ssl-mode
  t "token: ssl-mode with only the RULESETS and AUDIT tokens set -> exit 10" eq "$RC" 10
}

# =============================================================================================
# Group: env (the curl child environment is empty)
# =============================================================================================
grp_env() {
  local s
  for s in "${SUBS[@]}"; do
    fixture 200 "$(ok_body "$s")"
    run "${BASE_ENV[@]}" "CF_API_TOKEN=$TOK_BARE" "PLANTED_CANARY=plantedvalue_5521" "HTTPS_PROXY=http://127.0.0.1:9" "CF_API_BASE=https://evil.example" -- "$s"
    t "env[$s]: anchor - the stub dumped its environment (non-empty log)" test -s "$STUB/env.log"
    tn "env[$s]: curl child sees no token (any of four)" bash -c 'grep -qF -e "$2" -e "$3" -e "$4" -e "$5" "$1"' _ "$STUB/env.log" "$TOK_Z" "$TOK_R" "$TOK_A" "$TOK_BARE"
    tn "env[$s]: curl child sees no CF_* variable" grep -q 'CF_' "$STUB/env.log"
    tn "env[$s]: curl child sees no planted non-TLS canary" grep -q 'PLANTED_CANARY' "$STUB/env.log"
    tn "env[$s]: curl child sees no DOPPLER_* variable" grep -q 'DOPPLER_' "$STUB/env.log"
  done
  # jq and date are children too. A planted $HOME/.jq that redefines a builtin runs inside jq with whatever environment
  # jq was given; with the token in it, the canary below prints the token. The wrapper runs jq under `env -i`.
  assert_fixture_dir "$HOMEDIR"
  printf 'def test(re): ($ENV.%s | debug | true);\n' CF_API_TOKEN_ZONE_SETTINGS > "$HOMEDIR/.jq"
  /usr/bin/env HOME="$HOMEDIR" "CF_API_TOKEN_ZONE_SETTINGS=$TOK_Z" /usr/bin/jq -nc '"a" | test("a")' > "$WORK/jqctl.txt" 2>&1
  t "env[jq] control: the planted .jq canary DOES print the token when jq inherits the environment (the probe is live)" has_file "$WORK/jqctl.txt" "$TOK_Z"
  /usr/bin/env -i HOME="$HOMEDIR" /usr/bin/jq -nc '"a" | test("a")' > "$WORK/jqctl2.txt" 2>&1
  tn "env[jq] control: the same canary prints nothing under env -i" has_file "$WORK/jqctl2.txt" "$TOK_Z"
  for s in "${SUBS[@]}"; do
    printf 'def test(re): ($ENV.%s | debug | true);\n' "$(tokvar_of "$s")" > "$HOMEDIR/.jq"
    fixture 200 "$(ok_body "$s")"
    run "${BASE_ENV[@]}" -- "$s"
    t "env[jq/$s]: with a planted \$HOME/.jq the run is still ok" eq "$L1" "cloudflare-readonly: $s ok"
    t "env[jq/$s]: a planted \$HOME/.jq redefining test leaks no token to stdout or stderr" leak_scan "$WORK/comb.txt"
    t "env[jq/$s]: the output is exactly the two-line ok contract" eq "$(printf '%s\n' "$OUT" | wc -l)" 2
  done
  rm -f "$HOMEDIR/.jq"
}

# =============================================================================================
# Group: status (status map x every subcommand) with the leak scan on every cell
# =============================================================================================
# scen <label> <status> <body> <curl_exit> <stderr> <want_rc> <want_line_suffix|"">
status_cells() { # $1 = subcommand
  local s="$1" okb cell
  okb=$(ok_body "$s")
  local -a cells=(
    "200-ok|200|OK|0||0|ok"
    "401|401|ERR|0||11|unverified - token-invalid"
    "403|403|ERR|0||11|unverified - token-lacks-scope"
    "404|404|ERR|0||14|unverified - not-found"
    "429|429|ERR|0||14|unverified - upstream-error"
    "500|500|ERR|0||14|unverified - upstream-error"
    "400|400|ERR|0||14|unverified - upstream-error"
    "302|302|ERR|0||14|unverified - upstream-error"
    "curl-fail|200|OK|7|$CANARY_ERR|14|unverified - upstream-error (curl exit 7)"
    "malformed|200|<html>$CANARY_BODY|0||14|unverified - bad-response"
    "wrongtype|200|\"$CANARY_BODY\"|0||14|unverified - bad-response"
    "null-result|200|{\"success\":true,\"result\":null}|0||14|unverified - bad-response"
    "nonnumeric|abc|OK|0||14|unverified - bad-response"
    "success-false|200|{\"success\":false,\"errors\":[{\"code\":1,\"message\":\"$CANARY_BODY\"}],\"result\":[]}|0||14|unverified - api-error"
    "empty-output|NONE|OK|0||14|unverified - bad-response"
  )
  local name st body ce se wrc wl
  for cell in "${cells[@]}"; do
    IFS='|' read -r name st body ce se wrc wl <<<"$cell"
    # the body field may itself hold '|' only in none of the fixtures above; OK/ERR are placeholders
    case "$body" in
      OK) body="$okb" ;;
      ERR) body="$ERR_BODY" ;;
    esac
    fixture "$st" "$body" "$ce" "$se"
    run "${BASE_ENV[@]}" -- "$s"
    t "status[$s/$name]: exit $wrc" eq "$RC" "$wrc"
    if [[ "$wl" == ok ]]; then
      t "status[$s/$name]: first line is ok" eq "$L1" "cloudflare-readonly: $s ok"
    else
      t "status[$s/$name]: first line is '$wl'" bash -c '[[ "$1" == "$2"* ]]' _ "$L1" "cloudflare-readonly: $s $wl"
    fi
    if [[ "$L1" == "cloudflare-readonly: $s "* ]]; then EXERCISED=$((EXERCISED + 1)); fi
    t "status[$s/$name]: curl called exactly once (no retry, no second token)" eq "$(ncalls)" 1
    t "status[$s/$name]: the stub refused no flag" test ! -s "$STUB/refusal.log"
    t "leak[$s/$name]: stdout+stderr carry no token, canary, actor, IP or Bearer" leak_scan "$WORK/comb.txt"
    t "leak[$s/$name]: argv log carries no token or Authorization" bash -c '! grep -qaF -e "$2" -e "$3" -e "$4" -e Authorization "$1"' _ "$STUB/argv.bin" "$TOK_Z" "$TOK_R" "$TOK_A"
    if [[ "$name" == 403 || "$name" == 401 ]]; then
      t "status[$s/$name]: only the bound token was presented" eq "$(grep -cF -- "Bearer $(tok_of "$s")\"" "$STUB/stdin.log" 2>/dev/null || true)" 1
    fi
  done
}
grp_status() {
  local s
  # detector controls first: the scan itself is live
  assert_fixture_dir "$WORK"
  printf '%s\n' "clean output with nothing in it" > "$WORK/clean.txt"
  printf '%s\n' "leaky $TOK_R tail" > "$WORK/leaky.txt"
  t "leak control: the scan passes a clean file" leak_scan "$WORK/clean.txt"
  tn "leak control: the scan flags a known-leaky file" leak_scan "$WORK/leaky.txt"
  local n i=0
  for n in "${LEAK_NEEDLES[@]}"; do
    i=$((i + 1))
    assert_fixture_dir "$WORK"
    printf 'x %s y\n' "$n" > "$WORK/inj.txt"
    tn "leak control: needle $i is individually detected when injected" leak_scan "$WORK/inj.txt"
  done
  t "leak control: needle list has at least 12 non-empty members" test "${#LEAK_NEEDLES[@]}" -ge 12
  EXERCISED=0
  for s in "${SUBS[@]}"; do status_cells "$s"; done
  t "status floor: at least 4 subcommands x 3 outcomes exercised ($EXERCISED cells)" test "$EXERCISED" -ge 12
}

# =============================================================================================
# Group: xtrace
# =============================================================================================
grp_xtrace() {
  fixture 200 "$SSL_OK"
  RUNFLAGS=(-x)
  run "${BASE_ENV[@]}" -- ssl-mode
  RUNFLAGS=()
  t "xtrace: under bash -x with a token set the wrapper exits 78" eq "$RC" 78
  t "xtrace: no token in the trace output" leak_scan "$WORK/comb.txt"
  t "xtrace: curl never called" eq "$(ncalls)" 0
  RUNFLAGS=(-x)
  run "DOPPLER_PROJECT=soleur" -- --list
  RUNFLAGS=()
  t "xtrace: anchor - --list under -x with NO token set is not refused" eq "$RC" 0
  # every bound variable ALONE (the case-glob list is a union; a variable missing from it only shows when it is the only one set)
  local xv
  for xv in CF_API_TOKEN_ZONE_SETTINGS CF_API_TOKEN_RULESETS CF_API_TOKEN_AUDIT CF_API_TOKEN; do
    fixture 200 "$SSL_OK"
    RUNFLAGS=(-x)
    run "$xv=$TOK_BARE" -- ssl-mode
    RUNFLAGS=()
    t "xtrace[$xv alone]: exit 78" eq "$RC" 78
    t "xtrace[$xv alone]: no token in the trace output" leak_scan "$WORK/comb.txt"
    t "xtrace[$xv alone]: curl never called" eq "$(ncalls)" 0
  done
}

# =============================================================================================
# Group: proj (projections: shape, order, enum/regex checks, no vendor text)
# =============================================================================================
json2() { printf '%s' "${OUT#*$'\n'}"; }
jqe() { # jqe <jq filter> : exit status of jq -e on the projection
  json2 | jq -e "$1" > /dev/null
}
PROJ_ROWS=0
# pr <subcommand> <body>: one projection run. The proj group floor counts THESE runs (not t/ok, which the floor backstops).
pr() {
  PROJ_ROWS=$((PROJ_ROWS + 1))
  fixture 200 "$2"
  run "${BASE_ENV[@]}" -- "$1"
}
# hostile <subcommand> <field label> <body> <jq assertion>: a canary-bearing value in ONE projected field is sanitized, never echoed.
hostile() {
  pr "$1" "$3"
  t "proj[$1]: hostile $2 is sanitized in the output" jqe "$4"
  t "proj[$1]: hostile $2 leaves no canary, token or vendor text anywhere" leak_scan "$WORK/comb.txt"
}
entry_body() { # id version last_updated ref ssl : each a JSON literal
  jq -nc --argjson id "$1" --argjson ver "$2" --argjson lu "$3" --argjson ref "$4" --argjson ssl "$5" \
    '{success:true,result:{id:$id,version:$ver,last_updated:$lu,rules:[{ref:$ref,enabled:true,action_parameters:{ssl:$ssl},expression:"x"}]}}'
}
ENTRY_VALID_ARGS=('"e1"' '"1"' '"2026-10-01T12:00:00Z"' '"r1"' '"flexible"')
# entry_with <index 0-4> <json literal>: the valid entry body with one field replaced
entry_with() {
  local -a a=("${ENTRY_VALID_ARGS[@]}")
  a[$1]="$2"
  entry_body "${a[@]}"
}
page_body() { # id status ssl pattern : each a JSON literal
  jq -nc --argjson id "$1" --argjson st "$2" --argjson ssl "$3" --argjson pat "$4" \
    '{success:true,result:[{id:$id,status:$st,targets:[{target:"url",constraint:{operator:"matches",value:$pat}}],actions:[{id:"ssl",value:$ssl}]}]}'
}
grp_proj() {
  # ssl-mode
  pr ssl-mode "$SSL_OK"
  t "proj[ssl-mode]: id/value/modified_on projected" jqe '.subcommand=="ssl-mode" and .id=="ssl" and .value=="strict" and .modified_on=="2026-10-01T12:00:00.000000Z"'
  pr ssl-mode '{"success":true,"result":{"id":"ssl","value":"weird","modified_on":"2026-10-01T12:00:00Z"}}'
  t "proj[ssl-mode]: an unknown value prints as other" jqe '.value=="other"'
  pr ssl-mode "$(jq -nc '{success:true,result:{id:"ssl",value:"strict\nevil",modified_on:"2026-10-01T12:00:00Z"}}')"
  t "proj[ssl-mode]: a value with an embedded newline prints as other (anchored regex)" jqe '.value=="other"'
  pr ssl-mode '{"success":true,"result":{"value":"full"}}'
  t "proj[ssl-mode]: a missing result.id prints as invalid" jqe '.value=="full" and .id=="invalid"'
  pr ssl-mode '{"success":true,"errors":[]}'
  t "proj[ssl-mode]: a body without result is bad-response (shape), not a jq failure" eq "$L1" "cloudflare-readonly: ssl-mode unverified - bad-response (shape)"

  # config-entrypoint
  pr config-entrypoint "$ENTRY_OK"
  t "proj[config-entrypoint]: ok" eq "$L1" "cloudflare-readonly: config-entrypoint ok"
  t "proj[config-entrypoint]: header fields, rule_count 3, enabled_ssl_rules 2" jqe '.id=="entryid123" and .version=="7" and .last_updated=="2026-10-01T12:00:00.000000Z" and .rule_count==3 and .enabled_ssl_rules==2'
  t "proj[config-entrypoint]: rules in entrypoint order" jqe '[.rules[].ref]==["aaa111","dcb85b75bc3c4f4aa2a8c13a080bf854","ccc333"]'
  t "proj[config-entrypoint]: adopted rule enabled, ssl flexible, both hosts true" jqe '.rules[1].enabled==true and .rules[1].ssl=="flexible" and .rules[1].mentions_app_host==true and .rules[1].mentions_lb_staging_host==true'
  t "proj[config-entrypoint]: app.soleur.ai.evil does not set mentions_app_host" jqe '.rules[2].mentions_app_host==false and .rules[2].mentions_lb_staging_host==false'
  t "proj[config-entrypoint]: disabled rule keeps enabled false" jqe '.rules[0].enabled==false and .rules[0].ssl=="strict"'
  t "proj[config-entrypoint]: only the allowed keys at the top" jqe '(keys|sort)==["enabled_ssl_rules","id","last_updated","rule_count","rules","subcommand","version"]'
  t "proj[config-entrypoint]: only the allowed keys per rule" jqe 'all(.rules[]; (keys|sort)==["enabled","mentions_app_host","mentions_lb_staging_host","ref","ssl"])'
  t "proj[config-entrypoint]: no expression or description text in any output" leak_scan "$WORK/comb.txt"
  pr config-entrypoint '{"success":true,"result":{"id":"e1","rules":[]}}'
  t "proj[config-entrypoint]: version absent prints null, empty rules count 0, enabled_ssl_rules 0" jqe '.version==null and .rule_count==0 and .enabled_ssl_rules==0 and .rules==[]'
  pr config-entrypoint '{"success":true,"result":{"id":"e1","last_updated":"2026-10-01T12:00:00Z"}}'
  t "proj[config-entrypoint]: rules omitted -> rule_count 0 and ok" jqe '.rule_count==0'
  pr config-entrypoint '{"success":true,"result":{"id":"e1","rules":[{"ref":"$(touch pwn);x","enabled":true,"action_parameters":{"ssl":"evil\u001b[31m"},"expression":"x"}]}}'
  t "proj[config-entrypoint]: a ref with shell metacharacters prints as invalid" jqe '.rules[0].ref=="invalid"'
  t "proj[config-entrypoint]: an unknown ssl value prints as other" jqe '.rules[0].ssl=="other"'
  pr config-entrypoint '{"success":true,"result":{"id":"e1","rules":"nope"}}'
  t "proj[config-entrypoint]: rules of the wrong type is bad-response" contains "$L1" "unverified - bad-response"

  # pagerules-ssl
  pr pagerules-ssl "$PAGE_OK"
  t "proj[pagerules-ssl]: counts" jqe '.active_rule_count==2 and .ssl_rule_count==1 and (.ssl_rules|length)==1'
  t "proj[pagerules-ssl]: ssl rule projected, matches_app_host true" jqe '.ssl_rules[0]=={id:"pr1",status:"active",target_count:1,ssl:"flexible",matches_app_host:true}'
  t "proj[pagerules-ssl]: URL patterns never printed" leak_scan "$WORK/comb.txt"
  pr pagerules-ssl '{"success":true,"result":[]}'
  t "proj[pagerules-ssl]: an empty list is ok with zero counts" jqe '.active_rule_count==0 and .ssl_rule_count==0 and .ssl_rules==[]'

  # change-history
  pr change-history "$(audit_body 3)"
  t "proj[change-history]: counts by action and resource type" jqe '.rows==3 and .by_action_type=={"token_create":2,"zone.ruleset_update":1} and .by_resource_type=={"token":3}'
  t "proj[change-history]: oldest/newest from action.time, not truncated" jqe '.oldest_time=="2026-11-01T10:00:00Z" and .newest_time=="2026-11-03T10:00:00Z" and .truncated==false'
  t "proj[change-history]: no actor, IP or raw row" leak_scan "$WORK/comb.txt"
  pr change-history "$(audit_body 50)"
  t "proj[change-history]: 50 rows -> truncated true" jqe '.rows==50 and .truncated==true'
  pr change-history "$(jq -nc '{success:true,result:[{action:{type:"Bad Type!",time:"yesterday"},resource:{type:"x y"}}]}')"
  t "proj[change-history]: group keys and times are checked (invalid)" jqe '.by_action_type=={"invalid":1} and .by_resource_type=={"invalid":1} and .oldest_time==null'
  pr change-history '{"success":true,"result":[]}'
  t "proj[change-history]: no rows is ok with rows 0" jqe '.rows==0 and .truncated==false'

  # --- Records inputs (W2): the verdict rests on counts, not on the literal-substring host booleans ---
  local ADOPTED='{"ref":"dcb85b75bc3c4f4aa2a8c13a080bf854","enabled":true,"action_parameters":{"ssl":"flexible"},"expression":"(http.host in {\"app.soleur.ai\" \"lb-staging.soleur.ai\"})"}'
  entry_rules() { printf '{"success":true,"result":{"id":"e1","rules":[%s]}}' "$1"; }
  pr config-entrypoint "$(entry_rules "$ADOPTED")"
  t "records[B]: the adopted rule alone -> enabled_ssl_rules 1, rule_count 1" jqe '.enabled_ssl_rules==1 and .rule_count==1'
  pr config-entrypoint "$(entry_rules "$ADOPTED"',{"ref":"wild1","enabled":true,"action_parameters":{"ssl":"off"},"expression":"ends_with(http.host, \".soleur.ai\") EXPR_CANARY_W"}')"
  t "records[B]: a wildcard ends_with SSL override -> enabled_ssl_rules 2 although it names neither host" jqe '.enabled_ssl_rules==2 and .rules[1].ssl=="off" and .rules[1].mentions_app_host==false and .rules[1].mentions_lb_staging_host==false'
  t "records[B]: the wildcard rule's expression text is never printed" leak_scan "$WORK/comb.txt"
  pr config-entrypoint "$(entry_rules "$ADOPTED"',{"ref":"wild2","enabled":true,"action_parameters":{"ssl":"off"},"expression":"true"}')"
  t "records[B]: an expression of literally true with ssl off -> enabled_ssl_rules 2" jqe '.enabled_ssl_rules==2 and .rules[1].mentions_app_host==false'
  pr config-entrypoint "$(entry_rules "$ADOPTED"',{"ref":"noenabled","action_parameters":{"ssl":"full"},"expression":"(http.host eq \"x.example\")"}')"
  t "records[B]: a rule that omits enabled counts as enabled (!= false) -> enabled_ssl_rules 2, enabled true" jqe '.enabled_ssl_rules==2 and .rules[1].enabled==true'
  pr config-entrypoint "$(entry_rules "$ADOPTED"',{"ref":"offrule","enabled":false,"action_parameters":{"ssl":"off"},"expression":"true"}')"
  t "records[B]: a disabled ssl rule is not counted -> enabled_ssl_rules 1, enabled false" jqe '.enabled_ssl_rules==1 and .rules[1].enabled==false'
  pr config-entrypoint "$(entry_rules "$ADOPTED"',{"ref":"nossl","enabled":true,"action_parameters":{"cache":true},"expression":"true"}')"
  t "records[B]: an enabled rule with no ssl is not counted -> enabled_ssl_rules 1" jqe '.enabled_ssl_rules==1 and .rules[1].ssl==null'
  pr config-entrypoint "$(entry_rules "$ADOPTED"',{"ref":"near","enabled":true,"action_parameters":{"ssl":"off"},"expression":"(http.host eq \"lb-staging.soleur.ai.evil\")"}')"
  t "records[B]: a lb-staging.soleur.ai.evil near-miss does not set the host figure but still counts as an ssl rule" jqe '.enabled_ssl_rules==2 and .rules[1].mentions_lb_staging_host==false and .rules[1].mentions_app_host==false'
  pr pagerules-ssl "$(page_body '"w1"' '"active"' '"off"' '"*soleur.ai/*"')"
  t "records[C]: a wildcard *soleur.ai/* SSL page rule -> ssl_rule_count 1 although matches_app_host is false" jqe '.ssl_rule_count==1 and .ssl_rules[0].matches_app_host==false and .ssl_rules[0].ssl=="off"'
  t "records[C]: the wildcard pattern text is never printed" leak_scan "$WORK/comb.txt"
  pr pagerules-ssl '{"success":true,"result":[{"id":"two1","status":"active","targets":[{"target":"url","constraint":{"operator":"matches","value":"*other.example/*"}},{"target":"url","constraint":{"operator":"matches","value":"*app.soleur.ai/*"}}],"actions":[{"id":"ssl","value":"full"}]}]}'
  t "records[C]: a two-target rule where only the SECOND matches -> any(), matches_app_host true, target_count 2" jqe '.ssl_rules[0].matches_app_host==true and .ssl_rules[0].target_count==2'
  pr pagerules-ssl '{"success":true,"result":[{"id":"two2","status":"active","targets":[{"target":"url","constraint":{"operator":"matches","value":"*app.soleur.ai/*"}},{"target":"url","constraint":{"operator":"matches","value":"*other.example/*"}}],"actions":[{"id":"ssl","value":"full"}]}]}'
  t "records[C]: a two-target rule where only the FIRST matches -> any(), matches_app_host true" jqe '.ssl_rules[0].matches_app_host==true and .ssl_rules[0].target_count==2'
  pr pagerules-ssl '{"success":true,"result":[{"id":"two3","status":"active","targets":[{"target":"url","constraint":{"operator":"matches","value":"*lb-staging.soleur.ai.evil/*"}},{"target":"url","constraint":{"operator":"matches","value":"*other.example/*"}}],"actions":[{"id":"ssl","value":"off"}]}]}'
  t "records[C]: a lb-staging.soleur.ai.evil near-miss target is an ssl rule (count 1), host figure false" jqe '.ssl_rule_count==1 and .ssl_rules[0].matches_app_host==false'

  # --- timestamps: Z-suffixed RFC 3339 only, so string min/max ordering is sound ---
  pr change-history '{"success":true,"result":[{"action":{"type":"a","time":"2026-11-01T10:00:00Z"},"resource":{"type":"t"}},{"action":{"type":"a","time":"2026-11-01T10:00:00.5Z"},"resource":{"type":"t"}},{"action":{"type":"a","time":"2026-11-01T09:59:59.999Z"},"resource":{"type":"t"}}]}'
  t "proj[change-history]: newest_time orders a fractional second after the whole second (fraction-aware key)" jqe '.newest_time=="2026-11-01T10:00:00.5Z" and .oldest_time=="2026-11-01T09:59:59.999Z"'
  pr change-history '{"success":true,"result":[{"action":{"type":"a","time":"2026-11-01T10:00:00+01:00"},"resource":{"type":"t"}}]}'
  t "proj[change-history]: an offset-form time is not a Z timestamp and is excluded" jqe '.oldest_time==null and .newest_time==null'
  pr ssl-mode '{"success":true,"result":{"id":"ssl","value":"strict","modified_on":"2026-10-01T12:00:00+01:00"}}'
  t "proj[ssl-mode]: an offset-form modified_on prints invalid" jqe '.modified_on=="invalid"'

  # --- hostile canary-bearing values in EACH projected field ---
  hostile ssl-mode id '{"success":true,"result":{"id":"DESC_CANARY id!","value":"strict","modified_on":"2026-10-01T12:00:00Z"}}' '.id=="invalid" and .value=="strict"'
  hostile ssl-mode value '{"success":true,"result":{"id":"ssl","value":"PATTERN_CANARY","modified_on":"2026-10-01T12:00:00Z"}}' '.value=="other"'
  hostile ssl-mode modified_on '{"success":true,"result":{"id":"ssl","value":"strict","modified_on":"EXPR_CANARY_ts"}}' '.modified_on=="invalid"'
  hostile config-entrypoint entry-id "$(entry_with 0 '"DESC_CANARY id"')" '.id=="invalid" and .version=="1"'
  hostile config-entrypoint version "$(entry_with 1 '"EXPR_CANARY_v"')" '.version=="invalid"'
  hostile config-entrypoint version-too-long "$(entry_with 1 '12345678901')" '.version=="invalid"'
  hostile config-entrypoint last_updated "$(entry_with 2 '"EXPR_CANARY_lu"')" '.last_updated=="invalid"'
  hostile config-entrypoint rule-ref "$(entry_with 3 '"PATTERN_CANARY ref"')" '.rules[0].ref=="invalid"'
  hostile config-entrypoint rule-ssl "$(entry_with 4 '"PATTERN_CANARY"')" '.rules[0].ssl=="other"'
  pr config-entrypoint "$(entry_with 1 '7')"
  t "proj[config-entrypoint]: a numeric version prints as its decimal string" jqe '.version=="7"'
  hostile pagerules-ssl rule-id "$(page_body '"PATTERN_CANARY id"' '"active"' '"flexible"' '"x"')" '.ssl_rules[0].id=="invalid"'
  hostile pagerules-ssl status "$(page_body '"p1"' '"PATTERN_CANARY"' '"flexible"' '"x"')" '.ssl_rules[0].status=="other"'
  hostile pagerules-ssl ssl "$(page_body '"p1"' '"active"' '"PATTERN_CANARY"' '"x"')" '.ssl_rules[0].ssl=="other"'
  hostile change-history action-type '{"success":true,"result":[{"action":{"type":"ACTOR_CANARY","time":"2026-11-01T10:00:00Z"},"resource":{"type":"token"}}]}' '.by_action_type=={"invalid":1} and .by_resource_type=={"token":1}'
  hostile change-history resource-type '{"success":true,"result":[{"action":{"type":"token_create","time":"2026-11-01T10:00:00Z"},"resource":{"type":"EXPR_CANARY_rt"}}]}' '.by_resource_type=={"invalid":1} and .by_action_type=={"token_create":1}'
  hostile change-history action-time '{"success":true,"result":[{"action":{"type":"a","time":"EXPR_CANARY_t"},"resource":{"type":"t"}}]}' '.oldest_time==null and .newest_time==null'
}

# =============================================================================================
# Group: shape (the three bad-response reasons are distinct and value-free)
# =============================================================================================
grp_shape() {
  local s
  for s in "${SUBS[@]}"; do
    fixture 200 '{"success":true,"result":null}'
    run "${BASE_ENV[@]}" -- "$s"
    t "shape[$s]: a well-formed body of the wrong shape -> bad-response (shape), exit 14" eq "$L1|$RC" "cloudflare-readonly: $s unverified - bad-response (shape)|14"
    fixture 200 ''
    run "${BASE_ENV[@]}" -- "$s"
    t "shape[$s]: an empty body -> bad-response (shape), exit 14" eq "$L1|$RC" "cloudflare-readonly: $s unverified - bad-response (shape)|14"
    fixture 200 "<html>$CANARY_BODY"
    run "${BASE_ENV[@]}" -- "$s"
    t "shape[$s]: unparseable JSON -> bad-response (jq exit <n>) for a real non-zero jq exit, exit 14" bash -c '[[ "$1|$2" =~ ^cloudflare-readonly:\ $3\ unverified\ -\ bad-response\ \(jq\ exit\ [1-9][0-9]*\)\|14$ ]]' _ "$L1" "$RC" "$s"
    t "shape[$s]: the unparseable body is not echoed" leak_scan "$WORK/comb.txt"
    fixture 200 "\"$CANARY_BODY\""
    run "${BASE_ENV[@]}" -- "$s"
    t "shape[$s]: a JSON string body -> a real jq failure keeps (jq exit <n>)" bash -c '[[ "$1|$2" =~ ^cloudflare-readonly:\ $3\ unverified\ -\ bad-response\ \(jq\ exit\ [1-9][0-9]*\)\|14$ ]]' _ "$L1" "$RC" "$s"
    fixture abc "$(ok_body "$s")"
    run "${BASE_ENV[@]}" -- "$s"
    t "shape[$s]: a non-numeric status stays plain bad-response" eq "$L1|$RC" "cloudflare-readonly: $s unverified - bad-response|14"
  done
}

# =============================================================================================
# Group: tools (preflight of /usr/bin/jq and /usr/bin/date; the date failure message names only what was measured)
# =============================================================================================
make_variant() { # <name> <sed expression> : sets SUTX to a changed copy of the sandbox wrapper; fails when nothing changed
  local v="$WORK/var.$1.sh"
  assert_fixture_dir "$WORK"
  sed "$2" "$SUTC" > "$v"
  chmod +x "$v"
  if cmp -s "$SUTC" "$v"; then return 1; fi
  SUTX="$v"
}
grp_tools() {
  local s
  assert_fixture_dir "$STUB"
  if make_variant nojq 's|/usr/bin/jq|/nonexistent/jq|g'; then
    for s in "${SUBS[@]}"; do
      fixture 200 "$(ok_body "$s")"
      run "${BASE_ENV[@]}" -- "$s"
      t "tools[$s]: no jq -> unverified - no-tool (jq), exit 14" eq "$L1|$RC" "cloudflare-readonly: $s unverified - no-tool (jq)|14"
      t "tools[$s]: no jq -> curl never called (the preflight runs before any request)" eq "$(ncalls)" 0
    done
  else
    vno "tools: the no-jq variant could not be built (no /usr/bin/jq in the wrapper)"
  fi
  if make_variant nodate 's|/usr/bin/date|/nonexistent/date|g'; then
    fixture 200 "$(ok_body change-history)"
    run "${BASE_ENV[@]}" -- change-history
    t "tools[change-history]: no date -> unverified - no-tool (date), exit 14" eq "$L1|$RC" "cloudflare-readonly: change-history unverified - no-tool (date)|14"
    t "tools[change-history]: no date -> curl never called" eq "$(ncalls)" 0
    fixture 200 "$SSL_OK"
    run "${BASE_ENV[@]}" -- ssl-mode
    t "tools[ssl-mode]: no date is irrelevant to a subcommand that never calls date" eq "$L1" "cloudflare-readonly: ssl-mode ok"
  else
    vno "tools: the no-date variant could not be built (no /usr/bin/date in the wrapper)"
  fi
  printf '#!/bin/bash\necho garbage\n' > "$STUB/fakedate_all"
  printf '#!/bin/bash\nif [[ " $* " == *" -d "* ]]; then echo garbage; else exec /usr/bin/date "$@"; fi\n' > "$STUB/fakedate_rel"
  chmod +x "$STUB/fakedate_all" "$STUB/fakedate_rel"
  local fd
  for fd in fakedate_all fakedate_rel; do
    if make_variant "$fd" "s|/usr/bin/env -i /usr/bin/date|/usr/bin/env -i $STUB/$fd|g"; then
      fixture 200 "$(ok_body change-history)"
      run "${BASE_ENV[@]}" -- change-history
      t "tools[$fd]: a date that yields no valid stamp -> exit 64, curl never called" eq "$RC|$(ncalls)" "64|0"
      t "tools[$fd]: the message names only what was measured" eq "$ERR" "cloudflare-readonly: refused: date produced no valid UTC stamp"
    else
      vno "tools: the $fd variant could not be built"
    fi
  done
  SUTX=""
}


# =============================================================================================
# Run the groups
# =============================================================================================
if [[ "$SANDBOX_OK" != 1 ]]; then
  vno "sandbox: the CURL=/usr/bin/curl rewrite did not match exactly once - nothing can be exercised"
fi
# selftest is the no() negative control's child: it runs ONLY when asked for by name, never under `all`.
grp_selftest() {
  printf 'SCRATCH=%s\n' "$WORK"
  vno "selftest: deliberate failing assertion (this child MUST exit non-zero)"
}
PROJ_FLOOR=46
for g in source wire refuse token env status xtrace proj shape tools selftest; do
  if [[ "$g" == selftest ]]; then
    [[ "$SELECT" == selftest ]] || continue
  fi
  if want "$g"; then
    if [[ "$SANDBOX_OK" != 1 && "$g" != source ]]; then continue; fi
    "grp_$g"
  fi
done
# The proj floor sits OUTSIDE the group loop and reports with printf+exit: a loop that no longer runs proj cannot
# also skip the check that proves it ran, and the counter is bumped by pr(), not by the t/ok path the floor backstops.
if want proj && [[ "$SANDBOX_OK" == 1 ]] && [[ "$PROJ_ROWS" -lt "$PROJ_FLOOR" ]]; then
  printf 'FAIL - proj floor: %s projection runs executed, need at least %s (the proj group did not run)\n' "$PROJ_ROWS" "$PROJ_FLOOR"
  printf '\n%s passed, %s failed (%s asserted)\n' "$pass" "$((fail + 1))" "$asserted"
  exit 1
fi

# =============================================================================================
# Group: wirefloor harness row + mutation battery (never in the inner child)
# =============================================================================================
mut_n=0
MUT_CAUGHT=0
MUT_TOTAL=0
MUT_MAXFAIL=60
CONTROL_BAD=0
LAUNCH_SUITE="$SELF"
PEND_KIND=() PEND_LABEL=() PEND_EXPECT=() PEND_DIR=()
MAXJOBS=8
# launch <kind> <label> <expect> <dir> <groups> [NAME=value...]: start the child suite in the background.
launch() {
  local kind="$1" label="$2" expect="$3" d="$4" groups="$5"
  shift 5
  assert_fixture_dir "$d"
  while [[ "$(jobs -rp | wc -l)" -ge "$MAXJOBS" ]]; do wait -n; done
  ( /usr/bin/env CF_RO_TEST_INNER=1 "CF_RO_TESTDIR=$TESTDIR" "CF_RO_SUT=$d/cf.sh" "CF_RO_GROUPS=$groups" "$@" bash "$LAUNCH_SUITE" > "$d/out" 2>&1; printf '%s' "$?" > "$d/rc" ) &
  PEND_KIND+=("$kind")
  PEND_LABEL+=("$label")
  PEND_EXPECT+=("$expect")
  PEND_DIR+=("$d")
}
# edit_once <file> <from> <to> <label>: apply ONE literal edit to a copy of the file. Returns 1 (after a failing row) unless the
# anchor matched exactly once, the result differs from the original, and `bash -n` accepts it.
edit_once() {
  local file="$1" from="$2" to="$3" label="$4" dst="$5"
  local src new tmp cnt
  src=$(<"$file")
  tmp="${src//"$from"/}"
  cnt=$(((${#src} - ${#tmp}) / ${#from}))
  if [[ "$cnt" != 1 ]]; then
    vno "mutate[$label]: anchor matched $cnt times, need exactly 1 - the row measured nothing"
    return 1
  fi
  new="${src/"$from"/"$to"}"
  printf '%s\n' "$new" > "$dst"
  if cmp -s "$file" "$dst"; then vno "mutate[$label]: the edit did not change the file"; return 1; fi
  if ! bash -n "$dst"; then vno "mutate[$label]: the mutant does not parse - the edit is broken, not caught"; return 1; fi
  return 0
}
mutate() { MUT_KIND=mut mutate_kind "$@"; }
MUT_KIND=mut
mutate_kind() { # mutate_kind <label> <expected-failing-row-substring> <groups> <from> <to> (kind in MUT_KIND)
  local label="$1" expect="$2" groups="$3" from="$4" to="$5"
  local d
  mut_n=$((mut_n + 1))
  MUT_TOTAL=$((MUT_TOTAL + 1))
  d="$WORK/mut.$mut_n"
  assert_fixture_dir "$d"
  mkdir -p "$d"
  cp "$PROD" "$d/cf.sh"
  edit_once "$PROD" "$from" "$to" "$label" "$d/cf.sh" || return
  LAUNCH_SUITE="$SELF"
  launch "$MUT_KIND" "$label" "$expect" "$d" "$groups"
}
# mutate_suite: the same, applied to a copy of THIS file (a guard in the suite itself). The wrapper stays pristine.
mutate_suite() { # mutate_suite <kind> <label> <expect> <groups> <from> <to>
  local kind="$1" label="$2" expect="$3" groups="$4" from="$5" to="$6"
  local d
  mut_n=$((mut_n + 1))
  MUT_TOTAL=$((MUT_TOTAL + 1))
  d="$WORK/mut.$mut_n"
  assert_fixture_dir "$d"
  mkdir -p "$d"
  cp "$PROD" "$d/cf.sh"
  cp "$SELF" "$d/suite.sh"
  edit_once "$SELF" "$from" "$to" "$label" "$d/suite.sh" || return
  LAUNCH_SUITE="$d/suite.sh"
  launch "$kind" "$label" "$expect" "$d" "$groups"
  LAUNCH_SUITE="$SELF"
}
# collect: wait for every child, then judge each in launch order.
collect() {
  local i kind label expect d irc nfail sp
  wait
  for ((i = 0; i < ${#PEND_DIR[@]}; i++)); do
    kind="${PEND_KIND[$i]}" label="${PEND_LABEL[$i]}" expect="${PEND_EXPECT[$i]}" d="${PEND_DIR[$i]}"
    assert_fixture_dir "$d"
    if [[ ! -s "$d/rc" ]]; then
      vno "$label: the child left no exit status (crashed or killed) - no verdict"
      if [[ "$kind" == pass ]]; then CONTROL_BAD=1; fi
      continue
    fi
    irc=$(<"$d/rc")
    grep -F 'FAIL - ' "$d/out" > "$d/failed" || true
    nfail=$(sort -u "$d/failed" | wc -l)
    sp=$(sed -n 's/^SCRATCH=//p' "$d/out" | head -n 1)
    case "$kind" in
      pass)
        t "$label" eq "$irc" 0
        if [[ "$irc" != 0 ]]; then CONTROL_BAD=1; fi
        ;;
      blind) t "$label" bash -c '[[ "$1" != 0 ]] && grep -qF "$3" "$2"' _ "$irc" "$d/failed" "$expect" ;;
      negctl)
        # the no() negative control: a child with a deliberately failing assertion exits non-zero AND its scratch dir is gone
        t "$label: exits non-zero with the FAIL line" bash -c '[[ "$1" != 0 ]] && grep -qF "$3" "$2"' _ "$irc" "$d/failed" "$expect"
        t "$label: its scratch directory was removed by the trap" bash -c '[[ -n "$1" && ! -e "$1" ]]' _ "$sp"
        ;;
      *)
        if [[ "$CONTROL_BAD" == 1 ]]; then
          vno "mutate[$label]: the pristine controls are not green - this verdict is void"
          continue
        fi
        if ! grep -qF ' passed, ' "$d/out"; then
          vno "mutate[$label]: the child never reached its accounting line (a crash, not a catch)"
          continue
        fi
        case "$kind" in
          mut)
            if [[ "$irc" == 0 ]]; then
              vno "mutate[$label]: the mutant passed the suite (NOT caught)"
            elif ! grep -qF -- "$expect" "$d/failed"; then
              vno "mutate[$label]: reddened, but not by the named row '$expect'"
            elif [[ "$nfail" -gt "$MUT_MAXFAIL" ]]; then
              vno "mutate[$label]: $nfail distinct rows failed (bound $MUT_MAXFAIL) - a wholesale break, not a targeted catch"
            else
              MUT_CAUGHT=$((MUT_CAUGHT + 1))
              vok "mutate[$label]: caught by row containing '$expect' ($nfail distinct failing rows)"
            fi
            ;;
          wholesale)
            # the bound is live: a mutant that breaks everything must EXCEED it (so a crash is never scored as a catch)
            if [[ "$irc" != 0 && "$nfail" -gt "$MUT_MAXFAIL" ]]; then
              MUT_CAUGHT=$((MUT_CAUGHT + 1))
              vok "mutate[$label]: a wholesale break failed $nfail distinct rows, over the bound $MUT_MAXFAIL, so it would not be scored as a catch"
            else
              vno "mutate[$label]: a wholesale break failed only $nfail distinct rows (rc $irc); the distinct-failure bound is not live"
            fi
            ;;
          invert)
            # a mutated suite whose negative control would go RED: the child exits 0 although it printed the deliberate FAIL
            if [[ "$irc" == 0 ]] && grep -qF -- "$expect" "$d/failed"; then
              MUT_CAUGHT=$((MUT_CAUGHT + 1))
              vok "mutate[$label]: caught - the failing child exited 0, so the negative control reds"
            else
              vno "mutate[$label]: the mutated suite still exits non-zero on a failing assertion (NOT caught)"
            fi
            ;;
          negscratch)
            if [[ -n "$sp" && -e "$sp" ]]; then
              MUT_CAUGHT=$((MUT_CAUGHT + 1))
              vok "mutate[$label]: caught - the scratch directory survived, so the scratch control reds"
              case "$sp" in "$REPO_ROOT"/.cf-readonly-test.?*) rm -rf -- "${sp:?}" ;; esac
            else
              vno "mutate[$label]: the scratch directory was still removed (NOT caught)"
            fi
            ;;
          suitemut)
            # a mutated suite: judged exactly like a wrapper mutant, but the named row is a row of the suite itself
            if [[ "$irc" != 0 ]] && grep -qF -- "$expect" "$d/failed" && [[ "$nfail" -le "$MUT_MAXFAIL" ]]; then
              MUT_CAUGHT=$((MUT_CAUGHT + 1))
              vok "mutate[$label]: caught by row containing '$expect' ($nfail distinct failing rows)"
            else
              vno "mutate[$label]: the mutated suite was not caught by '$expect' (rc $irc, $nfail failing rows)"
            fi
            ;;
        esac
        ;;
    esac
  done
}

if [[ -z "$INNER" ]] && want all; then
  # --- controls ---
  d="$WORK/mut.pristine"
  assert_fixture_dir "$d"
  mkdir -p "$d"
  cp "$PROD" "$d/cf.sh"
  launch pass "control: the pristine wrapper passes the whole suite" "" "$d" all
  d="$WORK/mut.benign"
  assert_fixture_dir "$d"
  mkdir -p "$d"
  { cat "$PROD"; printf '%s\n' '# benign comment edit'; } > "$d/cf.sh"
  launch pass "control: a benign comment edit also passes (the suite does not red on every edit)" "" "$d" all
  d="$WORK/mut.blind"
  assert_fixture_dir "$d"
  mkdir -p "$d"
  cp "$PROD" "$d/cf.sh"
  launch blind "harness: a stub whose argv log is blind reds the wire floor, not a vacuous pass" "recorded argv is non-empty" "$d" wire CF_RO_STUB_BLIND=1

  # --- Guard 1: request closure ---
  mutate "G1.1 -X POST" "wire[ssl-mode]: argv has -X GET" wire '-X GET -sS' '-X POST -sS'
  mutate "G1.2 fifth dispatcher arm" "parity: array == case labels" "source,refuse" '  *) die 64 "refused: unknown subcommand" ;;' $'  raw) cf_get ssl-mode ;;\n  *) die 64 "refused: unknown subcommand" ;;'
  mutate "G1.2b fifth arm refused by unknown-endpoint row" "refuse: unknown subcommand raw -> exit 64" "source,refuse" '  *) die 64 "refused: unknown subcommand" ;;' $'  raw) cf_get ssl-mode ;;\n  *) die 64 "refused: unknown subcommand" ;;'
  mutate "G1.3 refusing arm calls cf_get" "refuse: unknown subcommand raw -> exit 64" refuse '  *) die 64 "refused: unknown subcommand" ;;' '  *) cf_get ssl-mode ;;'
  mutate "G1.4 second curl site" "source: exactly one curl call site" "source,status" '  403) unverified token-lacks-scope 11 ;;' $'  403) /usr/bin/env -i "$CURL" -X GET "$url" --config - < <(printf \'header = "Authorization: Bearer %s"\\n\' "${CF_API_TOKEN_RULESETS:-x}"); unverified token-lacks-scope 11 ;;'
  mutate "G1.4b second curl site (403 retried)" "curl called exactly once" "source,status" '  403) unverified token-lacks-scope 11 ;;' $'  403) /usr/bin/env -i "$CURL" -X GET "$url" --config - < <(printf \'header = "Authorization: Bearer %s"\\n\' "${CF_API_TOKEN_RULESETS:-x}"); unverified token-lacks-scope 11 ;;'
  mutate "G1.5 host overridable" "URL host is api.cloudflare.com despite a planted CF_API_BASE" wire "BASE='https://api.cloudflare.com/client/v4'" 'BASE="${CF_API_BASE:-https://api.cloudflare.com/client/v4}"'
  mutate "G1.6a add -L" "argv has none of -d" wire '--max-redirs 0' '--max-redirs 0 -L'
  mutate "G1.6b drop --max-redirs 0" "argv has --max-redirs 0" wire '--max-redirs 0' '--max-time 21'
  mutate "G1.6c --disable not first" "argv[1] is --disable" wire '"$CURL" --disable' '"$CURL" --noproxy "*" --disable'
  mutate "G1.7 accept extra argument" "refuse: extra positional -> exit 64" refuse 'if [ "$#" -ne 1 ]; then' 'if [ "$#" -lt 1 ]; then'
  mutate "G1.8a delete token-shape check" "token: refused shape" token 'if [[ ! "$TOK" =~ $TOKEN_RE ]]; then' 'if false; then'
  mutate "G1.8b delete trailing-whitespace trim" "token: trailing newline is accepted" token 'TOK="${TOK%"${TOK##*[![:space:]]}"}"' ':'
  mutate "G1.9a swap token binding" "wire[ssl-mode]: stdin carries the bound token exactly once" wire 'TOKVAR=CF_API_TOKEN_ZONE_SETTINGS' 'TOKVAR=CF_API_TOKEN_RULESETS'
  mutate "G1.9b CF_API_TOKEN fallback" "only CF_API_TOKEN present -> exit 10" token 'TOK="${!TOKVAR:-}"' 'TOK="${!TOKVAR:-${CF_API_TOKEN:-}}"'
  mutate "G1.10 delete DOPPLER pin" "refuse: DOPPLER_CONFIG=dev -> exit 64" refuse 'if [ "${DOPPLER_PROJECT:-}" != soleur ] || [ "${DOPPLER_CONFIG:-}" != prd_terraform ]; then' 'if false; then'
  mutate "G1.11a curl by name" "source: sandbox rewrite of CURL= matches exactly once" source $'\nCURL=/usr/bin/curl\n' $'\nCURL=curl\n'
  mutate "G1.11b env override for curl path" "source: no environment override" source $'\nCURL=/usr/bin/curl\n' $'\nCURL=${CF_CURL:-/usr/bin/curl}\n'
  mutate "G1.12 403 maps to ok" "status[ssl-mode/403]: exit 11" status '  403) unverified token-lacks-scope 11 ;;' '  403) : ;;'

  # --- Guard 2: credential non-disclosure ---
  mutate "G2.1a echo token in the 403 branch" "leak[ssl-mode/403]" status '  403) unverified token-lacks-scope 11 ;;' '  403) echo "$TOK"; unverified token-lacks-scope 11 ;;'
  mutate "G2.1b echo token on the success path" "leak[ssl-mode/200-ok]" status "printf 'cloudflare-readonly: %s ok\\n%s\\n' " "echo \"\$TOK\"; printf 'cloudflare-readonly: %s ok\\n%s\\n' "
  mutate "G2.2 token in argv" "argv carries no token, Authorization or Bearer" wire '--config - "$url"' '-H "Authorization: Bearer $TOK" "$url"'
  mutate "G2.3 drop env -i" "curl child sees no" env '/usr/bin/env -i "$CURL"' '"$CURL"'
  mutate "G2.4 print raw body on bad-response" "leak[ssl-mode/wrongtype]" status 'unverified "bad-response (jq exit $1)" 14' '{ printf "%s\n" "$BODY"; unverified "bad-response (jq exit $1)" 14; }'
  mutate "G2.5a remove the xtrace refusal" "xtrace: under bash -x" xtrace 'exit 78' ':'
  mutate "G2.5b add set -x" "source: no set -x" source 'export LC_ALL=C' $'export LC_ALL=C\nset -x'
  mutate "G2.6a add 2>/dev/null" "source: no 2>/dev/null" source 'unset SSLKEYLOGFILE' $': 2>/dev/null\nunset SSLKEYLOGFILE'
  mutate "G2.6b add mktemp" "source: no mktemp" source 'unset SSLKEYLOGFILE' $': mktemp -u\nunset SSLKEYLOGFILE'
  mutate "G2.6c add a here-string" "source: no here-string or heredoc" source 'unset SSLKEYLOGFILE' $': <<< x\nunset SSLKEYLOGFILE'
  mutate "G2.6d add a heredoc" "source: no here-string or heredoc" source 'unset SSLKEYLOGFILE' $': <<\'EOT\'\nEOT\nunset SSLKEYLOGFILE'
  mutate "G2.7 print curl merged stderr" "leak[ssl-mode/curl-fail]" status 'unverified "upstream-error (curl exit $rc)" 14' '{ printf "%s\n" "$out"; unverified "upstream-error (curl exit $rc)" 14; }'


  # --- review round: children run under env -i (W1) ---
  mutate "W1.1 project jq without env -i" "env[jq/ssl-mode]: a planted \$HOME/.jq redefining test leaks no token" env,source '  res=$(/usr/bin/env -i /usr/bin/jq -c' '  res=$(/usr/bin/jq -c'
  mutate "W1.2 guard jq without env -i" "census: every /usr/bin/jq or /usr/bin/date invocation runs behind env -i" source '  kind=$(/usr/bin/env -i /usr/bin/jq -r' '  kind=$(/usr/bin/jq -r'
  mutate "W1.3 date (now) without env -i" "census: every /usr/bin/jq or /usr/bin/date invocation runs behind env -i" source '  now=$(/usr/bin/env -i /usr/bin/date' '  now=$(/usr/bin/date'
  mutate "W1.4 date (since) without env -i" "census: every /usr/bin/jq or /usr/bin/date invocation runs behind env -i" source '  since=$(/usr/bin/env -i /usr/bin/date' '  since=$(/usr/bin/date'
  mutate "W1.5 a bare jq command" "census: no bare jq or date command" source '  [ -x /usr/bin/jq ] || unverified "no-tool (jq)" 14' $'  [ -x /usr/bin/jq ] || unverified "no-tool (jq)" 14\n  jq -n 1'

  # --- Records inputs (W2) ---
  mutate "W2.1 enabled == true instead of != false" "records[B]: a rule that omits enabled counts as enabled" proj 'enabled: (.enabled != false)' 'enabled: (.enabled == true)'
  mutate "W2.2 count rules with no ssl" "records[B]: an enabled rule with no ssl is not counted" proj 'select(.enabled and .ssl != null)' 'select(.enabled)'
  mutate "W2.3 count disabled rules" "records[B]: a disabled ssl rule is not counted" proj 'select(.enabled and .ssl != null)' 'select(.ssl != null)'
  mutate "W2.4 enabled_ssl_rules is just the rule count" "proj[config-entrypoint]: header fields, rule_count 3, enabled_ssl_rules 2" proj 'enabled_ssl_rules: ([$rr[] | select(.enabled and .ssl != null)] | length)' 'enabled_ssl_rules: ($rules | length)'

  # --- bad-response reasons, preflight, LIMIT, Z-only, hint (W3) ---
  mutate "W3.1 shape reported as a jq failure" "shape[ssl-mode]: a well-formed body of the wrong shape" shape '    *) bad_shape ;;' '    *) bad_jq 1 ;;'
  mutate "W3.2 delete the jq preflight" "tools[ssl-mode]: no jq -> unverified - no-tool (jq)" tools '  [ -x /usr/bin/jq ] || unverified "no-tool (jq)" 14' '  :'
  mutate "W3.3 delete the date preflight" "tools[change-history]: no date -> unverified - no-tool (date)" tools '  [ -x /usr/bin/date ] || unverified "no-tool (date)" 14' '  :'
  mutate "W3.4 date message claims GNU date" "tools[fakedate_rel]: the message names only what was measured" tools '[[ ! "$since" =~ $STAMP_RE ]]; then die 64 "refused: date produced no valid UTC stamp"' '[[ ! "$since" =~ $STAMP_RE ]]; then die 64 "refused: date does not support relative times (GNU date required)"'
  mutate "W3.5 LIMIT drifts from 50" "wire[change-history]: URL matches the fixed audit template" wire,source $'\nLIMIT=50\n' $'\nLIMIT=40\n'
  mutate "W3.6 truncated test hardcodes a different limit" "proj[change-history]: 50 rows -> truncated true" proj '>= $limit' '>= 51'
  mutate "W3.7 newest_time by plain max" "newest_time orders a fractional second after the whole second" proj 'newest_time: ($times | max_by(tkey))' 'newest_time: ($times | max)'
  mutate "W3.8 identity tkey" "newest_time orders a fractional second after the whole second" proj 'def tkey: sub("Z$"; "") | if contains(".") then . else . + ".0" end;' 'def tkey: .;'
  mutate "W3.9 accept offset-form timestamps" "an offset-form modified_on prints invalid" proj '(\\.[0-9]+)?Z\\z' '(\\.[0-9]+)?(Z|[+-][0-9]{2}:[0-9]{2})\\z'
  mutate "W3.10 drop the run-under hint" "refuse: unset DOPPLER_* -> the message carries the fixed run-under hint" refuse 'no Doppler source set (run under: doppler run -p soleur -c prd_terraform --)' 'no Doppler source set'

  # --- every projected sanitizer (W4) ---
  mutate "W4.1 modified_on without tsn" "proj[ssl-mode]: hostile modified_on is sanitized" proj 'modified_on: ($r.modified_on | tsn)' 'modified_on: $r.modified_on'
  mutate "W4.2 ssl-mode id without idv" "proj[ssl-mode]: hostile id is sanitized" proj 'id: ($r.id | idv), value:' 'id: $r.id, value:'
  mutate "W4.3 ssl-mode value without enum" "proj[ssl-mode]: hostile value is sanitized" proj 'value: ($r.value | enum)' 'value: $r.value'
  mutate "W4.4 entrypoint id without idv" "proj[config-entrypoint]: hostile entry-id is sanitized" proj 'id: ($r.id | idv), version:' 'id: $r.id, version:'
  mutate "W4.5 version without verstr" "proj[config-entrypoint]: hostile version is sanitized" proj 'version: ($r.version | verstr)' 'version: $r.version'
  mutate "W4.6 last_updated without tsn" "proj[config-entrypoint]: hostile last_updated is sanitized" proj 'last_updated: ($r.last_updated | tsn)' 'last_updated: $r.last_updated'
  mutate "W4.7 rule ref without idv" "proj[config-entrypoint]: hostile rule-ref is sanitized" proj 'ref: (.ref | idv)' 'ref: .ref'
  mutate "W4.8 rule ssl without sslv" "proj[config-entrypoint]: hostile rule-ssl is sanitized" proj 'then .ssl else null end) | sslv), mentions_app_host' 'then .ssl else null end)), mentions_app_host'
  mutate "W4.9 verstr length unbounded" "proj[config-entrypoint]: hostile version-too-long is sanitized" proj '{1,10}' '+'
  mutate "W4.10 pagerule id without idv" "proj[pagerules-ssl]: hostile rule-id is sanitized" proj 'id: (.id | idv), status:' 'id: .id, status:'
  mutate "W4.11 pagerule status uncoerced" "proj[pagerules-ssl]: hostile status is sanitized" proj 'status: (.status | if . == "active" or . == "disabled" then . else "other" end)' 'status: .status'
  mutate "W4.12 pagerule ssl without sslv" "proj[pagerules-ssl]: hostile ssl is sanitized" proj '.value][0] | sslv)' '.value][0])'
  mutate "W4.13 action type without gk" "proj[change-history]: hostile action-type is sanitized" proj 'by_action_type: ([$r[] | ((.action | if type == "object" then .type else null end) | gk)]' 'by_action_type: ([$r[] | ((.action | if type == "object" then .type else null end))]'
  mutate "W4.14 resource type without gk" "proj[change-history]: hostile resource-type is sanitized" proj 'by_resource_type: ([$r[] | ((.resource | if type == "object" then .type else null end) | gk)]' 'by_resource_type: ([$r[] | ((.resource | if type == "object" then .type else null end))]'
  mutate "W4.15 audit time filter dropped" "proj[change-history]: hostile action-time is sanitized" proj 'select(type == "string" and test(rfc))' 'select(type == "string")'
  mutate_suite suitemut "W4.16 the proj group is dropped from the run loop" "proj floor" proj "for g in source wire refuse token env status xtrace pr""oj shape tools selftest; do" "for g in source wire refuse token env status xtrace shape tools selftest; do"

  # --- closed argv vector (W5) ---
  mutate "W5.1 duplicated -X GET" "wire[ssl-mode]: recorded argv equals the closed vector" wire '-X GET -sS' '-X GET -X GET -sS'
  mutate "W5.2 second -X POST" "wire[ssl-mode]: recorded argv equals the closed vector" wire '-X GET -sS' '-X GET -X POST -sS'
  mutate "W5.3 glued -XPOST" "wire[ssl-mode]: recorded argv equals the closed vector" wire '-X GET -sS' '-XPOST -sS'
  mutate "W5.4 --connect-to" "wire[ssl-mode]: recorded argv equals the closed vector" wire '--max-redirs 0' '--max-redirs 0 --connect-to ::evil.example:'
  mutate "W5.5 -k" "wire[ssl-mode]: recorded argv equals the closed vector" wire '-sS --max-time 20' '-sS -k --max-time 20'
  mutate "W5.6 --config /dev/null" "wire[ssl-mode]: recorded argv equals the closed vector" wire '--config - "$url"' '--config /dev/null "$url"'
  mutate "W5.7 -K - instead of --config -" "wire[ssl-mode]: the stub refused no flag" wire '--config - "$url"' '-K - "$url"'
  mutate "W5.8 --location-trusted" "wire[ssl-mode]: recorded argv equals the closed vector" wire '--max-redirs 0' '--max-redirs 0 --location-trusted'
  mutate "W5.9 --resolve" "wire[ssl-mode]: recorded argv equals the closed vector" wire '--max-redirs 0' '--max-redirs 0 --resolve api.cloudflare.com:443:127.0.0.1'
  mutate "W5.10 --form-string" "wire[ssl-mode]: recorded argv equals the closed vector" wire '--max-redirs 0' '--max-redirs 0 --form-string a=b'

  # --- ids, xtrace per variable, dispatcher, request census, CURL census, source guards (W6) ---
  mutate "W6.1 unanchored id regex" "refuse: CF_ZONE_ID path-dot-dot -> exit 64" refuse "ID_RE='^[0-9a-f]{32}\$'" "ID_RE='[0-9a-f]{32}'"
  mutate "W6.2 id regex accepts uppercase" "refuse: CF_ZONE_ID uppercase -> exit 64" refuse "ID_RE='^[0-9a-f]{32}\$'" "ID_RE='^[0-9a-fA-F]{32}\$'"
  mutate "W6.3 xtrace list drops ZONE_SETTINGS" "xtrace[CF_API_TOKEN_ZONE_SETTINGS alone]: exit 78" xtrace '${CF_API_TOKEN_ZONE_SETTINGS:+x}' ''
  mutate "W6.4 xtrace list drops RULESETS" "xtrace[CF_API_TOKEN_RULESETS alone]: exit 78" xtrace '${CF_API_TOKEN_RULESETS:+x}' ''
  mutate "W6.5 xtrace list drops AUDIT" "xtrace[CF_API_TOKEN_AUDIT alone]: exit 78" xtrace '${CF_API_TOKEN_AUDIT:+x}' ''
  mutate "W6.6 xtrace list drops CF_API_TOKEN" "xtrace[CF_API_TOKEN alone]: exit 78" xtrace '${CF_API_TOKEN:+x}' ''
  mutate "W6.7 3-space quoted fifth arm" "parity: dispatcher case labels" source '  *) die 64 "refused: unknown subcommand" ;;' $'   "raw") sub_ssl_mode ;;\n  *) die 64 "refused: unknown subcommand" ;;'
  mutate "W6.8 behavioural fifth arm (purge)" "refuse fuzz: name purge" source,refuse '  *) die 64 "refused: unknown subcommand" ;;' $'  purge) TOKVAR=CF_API_TOKEN_ZONE_SETTINGS; load_credential zone; sub_ssl_mode ;;\n  *) die 64 "refused: unknown subcommand" ;;'
  mutate "W6.9 arm smuggled on an existing line" "census: dispatcher arm terminators == 5" source 'load_credential zone; sub_ssl_mode ;;' 'load_credential zone; sub_ssl_mode ;; hostnames) sub_ssl_mode ;;'
  mutate "W6.10 body-conditional extra request" "census: exactly four cf_get call sites" source,wire '    ok) : ;;' '    ok) cf_get "$BASE/zones/$CF_ZONE_ID/settings/ssl" ;;'
  mutate "W6.11 a URL template tampered" "census: the four cf_get URL templates" source 'pagerules?status=active"' 'pagerules?status=all"'
  mutate "W6.12 CURL conditional override" "census: CURL is assigned exactly once" source $'\nCURL=/usr/bin/curl\n' $'\nCURL=/usr/bin/curl\n[ -n "${CF_CURL:-}" ] && CURL=$CF_CURL\n'
  mutate "W6.13 CURL exported" "census: that one assignment is the column-0 literal" source $'\nCURL=/usr/bin/curl\n' $'\nexport CURL=/usr/bin/curl\n'
  mutate "W6.14 CURL indented override" "census: CURL is assigned exactly once" source $'\nCURL=/usr/bin/curl\n' $'\nCURL=/usr/bin/curl\n  CURL=${CF_CURL:-/usr/bin/curl}\n'
  mutate "W6.15 export TOK" "source: no export of the token" source $'\nTOK=""\n' $'\nexport TOK=""\n'
  mutate "W6.16 tee" "source: no tee" source 'unset SSLKEYLOGFILE' $': | tee /dev/null\nunset SSLKEYLOGFILE'
  mutate "W6.17 /dev/shm" "source: no /dev/shm" source 'unset SSLKEYLOGFILE' $': > /dev/shm/x\nunset SSLKEYLOGFILE'
  mutate "W6.18 exec fd redirection" "source: no exec file-descriptor redirection" source 'unset SSLKEYLOGFILE' $'exec 3>&2\nunset SSLKEYLOGFILE'
  mutate "W6.19 jq --arg" "source: no jq --arg" source 'jq -c --argjson limit' 'jq -c --arg t x --argjson limit'
  mutate "W6.20 env NAME=value prefix" "source: no NAME=value prefix on an env child" source '/usr/bin/env -i /usr/bin/jq -c' '/usr/bin/env -i X=1 /usr/bin/jq -c'
  mutate "W6.21 token variable on a jq line" "census: no token, zone or account variable on any jq/date line" source '--argjson limit "$LIMIT"' '--argjson limit "$LIMIT$TOK"'
  mutate "W6.22 xtrace list vs dispatcher TOKVAR" "source: the xtrace refusal list names exactly" source 'TOKVAR=CF_API_TOKEN_AUDIT;' 'TOKVAR=CF_API_TOKEN_AUDITX;'

  # --- the harness itself (W6 h, i, j) ---
  MUT_KIND=wholesale mutate_kind "W6.23 harness: a wholesale break exceeds the distinct-failure bound" "" all $'\nset -uo pipefail\n' $'\nexit 3\nset -uo pipefail\n'
  d="$WORK/mut.negctl"
  assert_fixture_dir "$d"
  mkdir -p "$d"
  cp "$PROD" "$d/cf.sh"
  launch negctl "harness: the no() negative control" "deliberate failing assertion" "$d" selftest
  mutate_suite invert "W6.24 harness: the summary no longer exits non-zero on a failure" "deliberate failing assertion" selftest 'if [[ "$fa''il" -gt 0 ]]; then exit 1; fi' 'if [[ "$fa''il" -gt 0 ]]; then :; fi'
  mutate_suite invert "W6.25 harness: no() stops counting a failure" "deliberate failing assertion" selftest 'no() { fa''il=$((fa''il + 1)); printf' 'no() { printf'
  mutate_suite negscratch "W6.26 harness: the cleanup trap no longer removes the scratch directory" "" selftest 'if [[ -n "${WO''RK:-}" ]]; then rm -rf -- "${WO''RK:?}"; fi' ':'

  collect
  t "mutation floor: every mutation row ran and was caught ($MUT_CAUGHT of $MUT_TOTAL)" eq "$MUT_CAUGHT" "$MUT_TOTAL"
  t "mutation floor: at least 100 mutation rows ran" test "$MUT_TOTAL" -ge 100
fi

# --- accounting ---
if [[ "$((pass + fail))" != "$asserted" ]]; then
  no "accounting: passes + fails ($((pass + fail))) != asserted ($asserted) - a verdict was dropped"
fi
if [[ "$SELECT" == all && -z "$INNER" ]]; then
  t "floor: at least 400 assertions ran (a suite that checked nothing is RED)" test "$asserted" -ge 400
fi
printf '\n%s passed, %s failed (%s asserted)\n' "$pass" "$fail" "$asserted"
if [[ "$fail" -gt 0 ]]; then exit 1; fi
exit 0
