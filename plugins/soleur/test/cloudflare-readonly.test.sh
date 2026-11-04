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
BASE_ENV=(
  "DOPPLER_PROJECT=soleur" "DOPPLER_CONFIG=prd_terraform"
  "CF_ZONE_ID=$ZONE" "CF_ACCOUNT_ID=$ACCT"
  "CF_API_TOKEN_ZONE_SETTINGS=$TOK_Z" "CF_API_TOKEN_RULESETS=$TOK_R" "CF_API_TOKEN_AUDIT=$TOK_A"
)
LEAK_NEEDLES=("$TOK_Z" "$TOK_R" "$TOK_A" "$TOK_BARE" "$CANARY_BODY" "$CANARY_ERR"
  "EXPR_CANARY" "DESC_CANARY" "ACTOR_CANARY" "203.0.113.77" "PATTERN_CANARY" "Bearer")
SUBS=(ssl-mode config-entrypoint pagerules-ssl change-history)

# --- the stub curl (path rewritten into the sandbox copy of the wrapper) ---
cat > "$STUB/curl" <<'STUB_EOF'
#!/bin/bash
D="${0%/*}"
printf "called\n" >> "$D/calls.log"
ARGLOG="$D/argv.bin"
for a in "$@"; do printf "%s\0" "$a" >> "$ARGLOG"; done
while IFS= read -r l || [[ -n "$l" ]]; do printf "%s\n" "$l" >> "$D/stdin.log"; done
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
  rm -f "${STUB:?}/calls.log" "${STUB:?}/argv.bin" "${STUB:?}/stdin.log" "${STUB:?}/env.log"
}
RUNFLAGS=()
OUT="" ERR="" RC=0 L1=""
run() { # run [NAME=value ...] -- args...
  assert_fixture_dir "$WORK"
  local -a ev=()
  while [[ $# -gt 0 && "$1" != "--" ]]; do ev+=("$1"); shift; done
  shift
  OUT=$(/usr/bin/env -i PATH=/usr/bin:/bin ${ev[@]+"${ev[@]}"} "$BASH" ${RUNFLAGS[@]+"${RUNFLAGS[@]}"} "$SUTC" "$@" 2>"$WORK/err.txt" </dev/null)
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
case_labels() {
  awk '/^case "\$SUB" in/{f=1;next} /^esac/{f=0} f' "$1" | grep -Eo '^  [a-z][a-z-]*\)' | tr -d ' )'
}
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
}

# =============================================================================================
# Group: wire (what actually reaches curl)
# =============================================================================================
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
}

# =============================================================================================
# Group: proj (projections: shape, order, enum/regex checks, no vendor text)
# =============================================================================================
json2() { printf '%s' "${OUT#*$'\n'}"; }
jqe() { # jqe <jq filter> : exit status of jq -e on the projection
  json2 | jq -e "$1" > /dev/null
}
grp_proj() {
  # ssl-mode
  fixture 200 "$SSL_OK"
  run "${BASE_ENV[@]}" -- ssl-mode
  t "proj[ssl-mode]: id/value/modified_on projected" jqe '.subcommand=="ssl-mode" and .id=="ssl" and .value=="strict" and .modified_on=="2026-10-01T12:00:00.000000Z"'
  fixture 200 '{"success":true,"result":{"id":"ssl","value":"weird","modified_on":"2026-10-01T12:00:00Z"}}'
  run "${BASE_ENV[@]}" -- ssl-mode
  t "proj[ssl-mode]: an unknown value prints as other" jqe '.value=="other"'
  fixture 200 "$(jq -nc '{success:true,result:{id:"ssl",value:"strict\nevil",modified_on:"2026-10-01T12:00:00Z"}}')"
  run "${BASE_ENV[@]}" -- ssl-mode
  t "proj[ssl-mode]: a value with an embedded newline prints as other (anchored regex)" jqe '.value=="other"'
  fixture 200 '{"success":true,"result":{"value":"full"}}'
  run "${BASE_ENV[@]}" -- ssl-mode
  t "proj[ssl-mode]: a missing result.id prints as invalid" jqe '.value=="full" and .id=="invalid"'
  fixture 200 '{"success":true,"errors":[]}'
  run "${BASE_ENV[@]}" -- ssl-mode
  t "proj[ssl-mode]: a body without result is bad-response" eq "$L1" "cloudflare-readonly: ssl-mode unverified - bad-response (jq exit 1)"

  # config-entrypoint
  fixture 200 "$ENTRY_OK"
  run "${BASE_ENV[@]}" -- config-entrypoint
  t "proj[config-entrypoint]: ok" eq "$L1" "cloudflare-readonly: config-entrypoint ok"
  t "proj[config-entrypoint]: header fields and rule_count 3" jqe '.id=="entryid123" and .version=="7" and .last_updated=="2026-10-01T12:00:00.000000Z" and .rule_count==3'
  t "proj[config-entrypoint]: rules in entrypoint order" jqe '[.rules[].ref]==["aaa111","dcb85b75bc3c4f4aa2a8c13a080bf854","ccc333"]'
  t "proj[config-entrypoint]: adopted rule enabled, ssl flexible, both hosts true" jqe '.rules[1].enabled==true and .rules[1].ssl=="flexible" and .rules[1].mentions_app_host==true and .rules[1].mentions_lb_staging_host==true'
  t "proj[config-entrypoint]: app.soleur.ai.evil does not set mentions_app_host" jqe '.rules[2].mentions_app_host==false and .rules[2].mentions_lb_staging_host==false'
  t "proj[config-entrypoint]: disabled rule keeps enabled false" jqe '.rules[0].enabled==false and .rules[0].ssl=="strict"'
  t "proj[config-entrypoint]: only the allowed keys per rule" jqe 'all(.rules[]; (keys|sort)==["enabled","mentions_app_host","mentions_lb_staging_host","ref","ssl"])'
  t "proj[config-entrypoint]: no expression or description text in any output" leak_scan "$WORK/comb.txt"
  fixture 200 '{"success":true,"result":{"id":"e1","rules":[]}}'
  run "${BASE_ENV[@]}" -- config-entrypoint
  t "proj[config-entrypoint]: version absent prints null, empty rules count 0" jqe '.version==null and .rule_count==0 and .rules==[]'
  fixture 200 '{"success":true,"result":{"id":"e1","last_updated":"2026-10-01T12:00:00Z"}}'
  run "${BASE_ENV[@]}" -- config-entrypoint
  t "proj[config-entrypoint]: rules omitted -> rule_count 0 and ok" jqe '.rule_count==0'
  fixture 200 '{"success":true,"result":{"id":"e1","rules":[{"ref":"$(touch pwn);x","enabled":true,"action_parameters":{"ssl":"evil\u001b[31m"},"expression":"x"}]}}'
  run "${BASE_ENV[@]}" -- config-entrypoint
  t "proj[config-entrypoint]: a ref with shell metacharacters prints as invalid" jqe '.rules[0].ref=="invalid"'
  t "proj[config-entrypoint]: an unknown ssl value prints as other" jqe '.rules[0].ssl=="other"'
  fixture 200 '{"success":true,"result":{"id":"e1","rules":"nope"}}'
  run "${BASE_ENV[@]}" -- config-entrypoint
  t "proj[config-entrypoint]: rules of the wrong type is bad-response" contains "$L1" "unverified - bad-response"

  # pagerules-ssl
  fixture 200 "$PAGE_OK"
  run "${BASE_ENV[@]}" -- pagerules-ssl
  t "proj[pagerules-ssl]: counts" jqe '.active_rule_count==2 and .ssl_rule_count==1 and (.ssl_rules|length)==1'
  t "proj[pagerules-ssl]: ssl rule projected, matches_app_host true" jqe '.ssl_rules[0]=={id:"pr1",status:"active",target_count:1,ssl:"flexible",matches_app_host:true}'
  t "proj[pagerules-ssl]: URL patterns never printed" leak_scan "$WORK/comb.txt"
  fixture 200 '{"success":true,"result":[]}'
  run "${BASE_ENV[@]}" -- pagerules-ssl
  t "proj[pagerules-ssl]: an empty list is ok with zero counts" jqe '.active_rule_count==0 and .ssl_rule_count==0 and .ssl_rules==[]'

  # change-history
  fixture 200 "$(audit_body 3)"
  run "${BASE_ENV[@]}" -- change-history
  t "proj[change-history]: counts by action and resource type" jqe '.rows==3 and .by_action_type=={"token_create":2,"zone.ruleset_update":1} and .by_resource_type=={"token":3}'
  t "proj[change-history]: oldest/newest from action.time, not truncated" jqe '.oldest_time=="2026-11-01T10:00:00Z" and .newest_time=="2026-11-03T10:00:00Z" and .truncated==false'
  t "proj[change-history]: no actor, IP or raw row" leak_scan "$WORK/comb.txt"
  fixture 200 "$(audit_body 50)"
  run "${BASE_ENV[@]}" -- change-history
  t "proj[change-history]: 50 rows -> truncated true" jqe '.rows==50 and .truncated==true'
  fixture 200 "$(jq -nc '{success:true,result:[{action:{type:"Bad Type!",time:"yesterday"},resource:{type:"x y"}}]}')"
  run "${BASE_ENV[@]}" -- change-history
  t "proj[change-history]: group keys and times are checked (invalid)" jqe '.by_action_type=={"invalid":1} and .by_resource_type=={"invalid":1} and .oldest_time==null'
  fixture 200 '{"success":true,"result":[]}'
  run "${BASE_ENV[@]}" -- change-history
  t "proj[change-history]: no rows is ok with rows 0" jqe '.rows==0 and .truncated==false'
}

# =============================================================================================
# Run the groups
# =============================================================================================
if [[ "$SANDBOX_OK" != 1 ]]; then
  vno "sandbox: the CURL=/usr/bin/curl rewrite did not match exactly once - nothing can be exercised"
fi
for g in source wire refuse token env status xtrace proj; do
  if want "$g"; then
    if [[ "$SANDBOX_OK" != 1 && "$g" != source ]]; then continue; fi
    "grp_$g"
  fi
done

# =============================================================================================
# Group: wirefloor harness row + mutation battery (never in the inner child)
# =============================================================================================
mut_n=0
MUT_CAUGHT=0
MUT_TOTAL=0
PEND_KIND=() PEND_LABEL=() PEND_EXPECT=() PEND_DIR=()
MAXJOBS=8
# launch <kind> <label> <expect> <dir> <groups> [NAME=value...]: start the child suite in the background.
launch() {
  local kind="$1" label="$2" expect="$3" d="$4" groups="$5"
  shift 5
  assert_fixture_dir "$d"
  while [[ "$(jobs -rp | wc -l)" -ge "$MAXJOBS" ]]; do wait -n; done
  ( /usr/bin/env CF_RO_TEST_INNER=1 "CF_RO_SUT=$d/cf.sh" "CF_RO_GROUPS=$groups" "$@" bash "$SELF" > "$d/out" 2>&1; printf '%s' "$?" > "$d/rc" ) &
  PEND_KIND+=("$kind")
  PEND_LABEL+=("$label")
  PEND_EXPECT+=("$expect")
  PEND_DIR+=("$d")
}
mutate() { # mutate <label> <expected-failing-row-substring> <groups> <from> <to>
  local label="$1" expect="$2" groups="$3" from="$4" to="$5"
  local d src new tmp cnt
  mut_n=$((mut_n + 1))
  MUT_TOTAL=$((MUT_TOTAL + 1))
  d="$WORK/mut.$mut_n"
  assert_fixture_dir "$d"
  mkdir -p "$d"
  cp "$PROD" "$d/cf.sh"
  src=$(<"$PROD")
  tmp="${src//"$from"/}"
  cnt=$(((${#src} - ${#tmp}) / ${#from}))
  if [[ "$cnt" != 1 ]]; then
    vno "mutate[$label]: anchor matched $cnt times, need exactly 1 - the row measured nothing"
    return
  fi
  new="${src/"$from"/"$to"}"
  assert_fixture_dir "$d"
  printf '%s\n' "$new" > "$d/cf.sh"
  if cmp -s "$PROD" "$d/cf.sh"; then vno "mutate[$label]: the edit did not change the file"; return; fi
  if ! bash -n "$d/cf.sh"; then vno "mutate[$label]: the mutant does not parse - the edit is broken, not caught"; return; fi
  launch mut "$label" "$expect" "$d" "$groups"
}
# collect: wait for every child, then judge each in launch order.
collect() {
  local i kind label expect d irc
  wait
  for ((i = 0; i < ${#PEND_DIR[@]}; i++)); do
    kind="${PEND_KIND[$i]}" label="${PEND_LABEL[$i]}" expect="${PEND_EXPECT[$i]}" d="${PEND_DIR[$i]}"
    assert_fixture_dir "$d"
    irc=$(<"$d/rc")
    grep -F 'FAIL - ' "$d/out" > "$d/failed" || true
    case "$kind" in
      pass) t "$label" eq "$irc" 0 ;;
      blind) t "$label" bash -c '[[ "$1" != 0 ]] && grep -qF "$3" "$2"' _ "$irc" "$d/failed" "$expect" ;;
      mut)
        if [[ "$irc" == 0 ]]; then
          vno "mutate[$label]: the mutant passed the suite (NOT caught)"
        elif grep -qF -- "$expect" "$d/failed"; then
          MUT_CAUGHT=$((MUT_CAUGHT + 1))
          vok "mutate[$label]: caught by row containing '$expect'"
        else
          vno "mutate[$label]: reddened, but not by the named row '$expect'"
        fi
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

  collect
  t "mutation floor: every mutation row ran and was caught ($MUT_CAUGHT of $MUT_TOTAL)" eq "$MUT_CAUGHT" "$MUT_TOTAL"
  t "mutation floor: at least 28 mutation rows ran" test "$MUT_TOTAL" -ge 28
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
