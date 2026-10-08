#!/usr/bin/env bash
# Hermetic argv-hygiene test for the community scripts' credential-bearing curl calls
# (#9597): linkedin-setup.sh (client secret + introspected token, both as form fields),
# the OAuth 1.0a Authorization header in x-community.sh and x-setup.sh, the Discord Bot
# token in discord-community.sh and discord-setup.sh, and the Bluesky createSession body
# (handle + app password) in bsky-community.sh and bsky-setup.sh.
#
# A PATH-shim `curl` records its argv NUL-delimited and, when asked for `--config -`,
# its stdin config and, for `--data-binary @-`, its stdin BODY (recorded separately). A PATH-shim `jq` records its
# argv and the NAMES of its exported variables (never values). Nothing touches the
# network. Per path the test proves:
#   1. the credential is absent from curl's argument list (the /proc/<pid>/cmdline surface);
#   2. the exact `data-urlencode = "..."` / `header = "..."` line is on the stdin config,
#      decoded the way curl decodes a config string (`\\` and `\"` un-escaped);
#   3. a malformed value (control character, or a quote / backslash where the field
#      forbids one) is refused BEFORE any curl runs, with the script's existing exit code;
#   4. `--disable --noproxy '*'` are the first curl arguments.
# The scripts are driven end to end (their subcommands are non-interactive once the
# credentials are in the environment; generate-token reads its code from stdin and runs
# from a scratch directory that is not a git checkout, so write-env lands there).
# Run: bash plugins/soleur/skills/community/test/community-argv.test.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"
LINKEDIN_SETUP="$HERE/linkedin-setup.sh"
X_COMMUNITY="$HERE/x-community.sh"
X_SETUP="$HERE/x-setup.sh"
DISCORD_COMMUNITY="$HERE/discord-community.sh"
DISCORD_SETUP="$HERE/discord-setup.sh"
BSKY_COMMUNITY="$HERE/bsky-community.sh"
BSKY_SETUP="$HERE/bsky-setup.sh"
HMAC_LIB="$HERE/lib/hmac-sha1-b64.sh"
PINNED_IMAGE='node:22-slim@sha256:4f77a690f2f8946ab16fe1e791a3ac0667ae1c3575c3e4d0d4589e9ed5bfaf3d'

# ===================================================================================
# HMAC-SHA1 oracle (S2, #9597). The plugin signs OAuth 1.0a in bash because the hosted runner
# image has no python3 (lib/hmac-sha1-b64.sh keeps the key off every exec argument). The
# ORACLE is the other implementation, `openssl dgst -hmac`, run here ONLY with synthetic
# keys; the RFC 2202 vectors are a second, non-openssl anchor. These functions are defined
# before the dependency check so `--oracle-only` can run them alone (the pinned-image run
# has openssl but no jq, and no sandbox).
# ===================================================================================
ORC_RAN=0 ORC_BAD=0 ORC_LEN=0 ORC_SPEC=0 ORC_RFC=0

# oc_rep <n> <pattern>: the pattern cycled to exactly n bytes, no trailing newline.
oc_rep() {
  local n="$1" pat="$2" out=""
  while (( ${#out} < n )); do out+="$pat"; done
  printf '%s' "${out:0:n}"
}
# oc_bytes <hex-byte> <n>: a printf format emitting that byte n times.
oc_bytes() {
  local i out=""
  for (( i = 0; i < $2; i++ )); do out+="\\x$1"; done
  printf '%s' "$out"
}
# orc_cmp <key> <message>: the function under test against `openssl dgst -hmac`.
orc_cmp() {
  local want got OC_KEY="$1"
  ORC_RAN=$((ORC_RAN + 1))
  want="$(printf '%s' "$2" | openssl dgst -sha1 -hmac "$1" -binary | base64)"
  got="$(printf '%s' "$2" | hmac_sha1_b64 OC_KEY 2>/dev/null)"
  if [[ -z "$want" || "$got" != "$want" ]]; then ORC_BAD=$((ORC_BAD + 1)); fi
}
# orc_rfc <key-printf-format> <message-printf-format> <expected-hex>: an RFC 2202 vector.
orc_rfc() {
  local OC_KEY want got i wantfmt=""
  ORC_RAN=$((ORC_RAN + 1)); ORC_RFC=$((ORC_RFC + 1))
  # shellcheck disable=SC2059,SC2034
  printf -v OC_KEY "$1"
  for (( i = 0; i < ${#3}; i += 2 )); do wantfmt+="\\x${3:i:2}"; done
  # shellcheck disable=SC2059
  want="$(printf "$wantfmt" | base64)"
  # shellcheck disable=SC2059
  got="$(printf "$2" | hmac_sha1_b64 OC_KEY 2>/dev/null)"
  if [[ -z "$want" || "$got" != "$want" ]]; then ORC_BAD=$((ORC_BAD + 1)); fi
}
oracle_matrix() {
  local -a msgs=() keys=()
  local n k m i
  ORC_RAN=0 ORC_BAD=0 ORC_LEN=0 ORC_SPEC=0 ORC_RFC=0
  msgs=('' 'x' "$(oc_rep 200 'msg-0123456789&=%')" $'trailing-newline\n')
  # Lengths around the 64-byte block boundary; the cycled pattern carries a backslash, a
  # double quote, a space, '=' and '%' so every length also exercises odd bytes.
  for n in 0 1 20 63 64 65 96 200; do
    k="$(oc_rep "$n" 'Ab1&=%\"k Z+/')"
    for m in "${msgs[@]}"; do orc_cmp "$k" "$m"; ORC_LEN=$((ORC_LEN + 1)); done
  done
  # Special keys: `6`x64 (ipad XOR gives NUL bytes), quoting/spacing hazards, '=' and '%',
  # a base64-shaped key with +/=, and a multi-byte UTF-8 key.
  keys=("$(oc_rep 64 '6')" 'a\b\\c' 'a"b"c' 'a b  c ' 'abc==%41%zz=' 'Zm9v+/YmFy/+8=' $'caf\xc3\xa9\xc3\xa9')
  for k in "${keys[@]}"; do
    for m in "${msgs[@]}"; do orc_cmp "$k" "$m"; ORC_SPEC=$((ORC_SPEC + 1)); done
  done
  # RFC 2202 test cases 1-7 (HMAC-SHA1). Keys/messages are printf formats (byte escapes).
  orc_rfc "$(oc_bytes 0b 20)" 'Hi There' b617318655057264e28bc0b6fb378c8ef146be00
  orc_rfc 'Jefe' 'what do ya want for nothing?' effcdf6ae5eb2fa2d27416d5f184df9c259a7c79
  orc_rfc "$(oc_bytes aa 20)" "$(oc_bytes dd 50)" 125d7342b9ac11cd91a39af48aa17b4f63f175d3
  local k4=""; for (( i = 1; i <= 25; i++ )); do k4+="$(printf '\\x%02x' "$i")"; done
  orc_rfc "$k4" "$(oc_bytes cd 50)" 4c9007f4026250c6bc8414f9bf50c86c2d7235da
  orc_rfc "$(oc_bytes 0c 20)" 'Test With Truncation' 4c1a03424b55e07fe7f27be1d58bb9324a9a5a04
  orc_rfc "$(oc_bytes aa 80)" 'Test Using Larger Than Block-Size Key - Hash Key First' aa4ae5e15272d00e95705637ce8a3b55ed402112
  orc_rfc "$(oc_bytes aa 80)" 'Test Using Larger Than Block-Size Key and Larger Than One Block-Size Data' e8e99d0f45237d786d6bbaa7965c7808bbff1a91
}

if [[ "${1:-}" == "--oracle-only" ]]; then
  command -v openssl >/dev/null 2>&1 || { echo "ORACLE-ONLY: openssl missing" >&2; exit 3; }
  [[ -r "$HMAC_LIB" ]] || { echo "ORACLE-ONLY: $HMAC_LIB missing" >&2; exit 3; }
  # shellcheck disable=SC1090
  source "$HMAC_LIB"
  oracle_matrix
  printf 'ORACLE-ONLY bash=%s cases=%s len=%s spec=%s rfc=%s bad=%s\n' "$BASH_VERSION" "$ORC_RAN" "$ORC_LEN" "$ORC_SPEC" "$ORC_RFC" "$ORC_BAD"
  [[ "$ORC_BAD" -eq 0 && "$ORC_LEN" -eq 32 && "$ORC_SPEC" -eq 28 && "$ORC_RFC" -eq 7 ]]
  exit $?
fi
# shellcheck disable=SC1090
[[ -r "$HMAC_LIB" ]] && source "$HMAC_LIB"

# python3: ONLY the test uses it (the independent RFC 5849 percent-encoder of the OAuth oracle); the
# scripts under test never do, and the hosted runner image has none.
for dep in jq openssl python3; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    if [[ -n "${CI:-}" ]]; then
      echo "FAIL: $dep is required in CI but not found" >&2
      exit 1
    fi
    echo "SKIP: $dep not installed"
    exit 0
  fi
done

SANDBOX="$(mktemp -d -t community-argv.XXXXXXXX)" || { echo "FAIL: mktemp" >&2; exit 1; }
[[ -n "$SANDBOX" && -d "$SANDBOX" ]] || { echo "FAIL: no sandbox" >&2; exit 1; }
trap 'rm -rf -- "$SANDBOX"' EXIT

MOCK="$SANDBOX/mock"
WORK="$SANDBOX/work"
GITWORK="$SANDBOX/gitwork"
mkdir -p "$MOCK" "$WORK" "$GITWORK" "$SANDBOX/home"
# x-setup.sh resolves a git root at startup (it only reads it for validate-credentials),
# so its runs happen in a scratch checkout. env -i keeps an inherited GIT_DIR / GIT_INDEX_FILE
# (a linked worktree exports both) from reaching this `git init`.
env -i PATH="$PATH" HOME="$SANDBOX/home" git init -q -- "$GITWORK" || { echo "FAIL: git init" >&2; exit 1; }
SYS_PATH="$PATH"

# --- shims -------------------------------------------------------------------------
cat > "$MOCK/curl" <<'SHIM'
#!/bin/bash
d="$MOCK_DIR"
n=$(( $(cat "$d/count" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$d/count"
printf '%s\0' "$@" > "$d/argv.$n"
# Names (never values) of the variables this child inherited: the `export` mutant row.
compgen -e > "$d/env.$n"
prev=""
for a in "$@"; do
  if [[ "$prev" == "--config" && "$a" == "-" ]]; then
    if [[ "${SHIM_MUTATE:-}" == nostdin ]]; then cat > /dev/null; else cat > "$d/stdin.$n"; fi
  fi
  # `--data-binary @-` reads the request body from stdin (and keeps CR/LF, like real curl). It is
  # recorded as body.<n>, SEPARATE from a `--config -` stdin config (stdin.<n>).
  if [[ "$prev" == "--data-binary" && "$a" == "@-" ]]; then
    if [[ "${SHIM_MUTATE:-}" == nobody ]]; then cat > /dev/null; else cat > "$d/body.$n"; fi
  fi
  prev="$a"
  [[ "$a" == http*://* ]] && url="$a"
done
[[ "${SHIM_MODE:-}" == fail7 ]] && exit 7
[[ "${SHIM_MODE:-}" == fail60 ]] && exit 60
# SHIM_MODE=badjwt: a hostile/garbled createSession reply whose accessJwt holds a quote, a newline
# and a `url = ...` config directive (the line-injection shape the bearer guard exists to refuse).
if [[ "${SHIM_MODE:-}" == badjwt && "$url" == *createSession ]]; then
  printf '%s\n200\n' '{"accessJwt":"synth\"\nurl = \"https://evil.invalid/x\"","did":"did:plc:synth0001","handle":"synthetic.bsky.social"}'
  exit 0
fi
case "$url" in
  *introspectToken) printf '%s\n200\n' '{"active":true,"expires_at":4102444800,"scope":"openid"}' ;;
  *accessToken)     printf '%s\n200\n' '{"access_token":"synthetic-fixture-token-0002"}' ;;
  *userinfo)        printf '%s\n200\n' '{"sub":"synthetic0001"}' ;;
  *2/tweets)        printf '%s\n201\n' '{"data":{"id":"1","text":"hi"}}' ;;
  *2/users/me*)     printf '%s\n200\n' '{"data":{"id":"123","username":"synthetic","name":"Synthetic","public_metrics":{"followers_count":1,"following_count":1,"tweet_count":1}}}' ;;
  *oauth2/applications/@me) printf '%s\n200\n' '{"id":"123456789012345678","name":"synthbot"}' ;;
  *users/@me/guilds*)       printf '%s\n200\n' '[{"id":"1","name":"G","approximate_member_count":3}]' ;;
  *users/@me)               printf '%s\n200\n' '{"id":"1","username":"synthbot"}' ;;
  */webhooks)               printf '%s\n200\n' '{"id":"77","token":"synthwebhook0001"}' ;;
  *messages*|*/members*)    printf '%s\n200\n' '[]' ;;
  */channels)               printf '%s\n200\n' '[{"id":"5","name":"c","type":0,"position":0}]' ;;
  *with_counts*)            printf '%s\n200\n' '{"id":"1","name":"G","approximate_member_count":3}' ;;
  *createSession)           printf '%s\n200\n' '{"accessJwt":"synthjwt.synthjwt.synthjwt","did":"did:plc:synth0001","handle":"synthetic.bsky.social"}' ;;
  *createRecord)            printf '%s\n200\n' '{"uri":"at://did:plc:synth0001/app.bsky.feed.post/1","cid":"synthcid0001"}' ;;
  *getProfile*)             printf '%s\n200\n' '{"did":"did:plc:synth0001","handle":"synthetic.bsky.social","displayName":"S","followersCount":1,"followsCount":1,"postsCount":1}' ;;
  *)                printf '%s\n500\n' '{}' ;;
esac
SHIM
chmod +x "$MOCK/curl"
# `jq` shim: records argv (a `--arg pw ...` regression is invisible to the curl shim alone) and the
# NAMES of the variables jq inherited, then runs the real jq. Passthrough, so every script is unchanged.
REAL_JQ="$(command -v jq)"
cat > "$MOCK/jq" <<'SHIM'
#!/bin/bash
d="$MOCK_DIR"
n=0
[[ -r "$d/jqcount" ]] && read -r n < "$d/jqcount"
n=$((n + 1))
printf '%s\n' "$n" > "$d/jqcount"
printf '%s\0' "$@" > "$d/jqargv.$n"
compgen -e > "$d/jqenv.$n"
# SHIM_MODE=jqfail: the createSession body build (the program that reads $ENV.BSKY_PW) fails.
[[ "${SHIM_MODE:-}" == jqfail && "$*" == *ENV.BSKY_PW* ]] && exit 5
exec "@REAL_JQ@" "$@"
SHIM
sed -i "s|@REAL_JQ@|$REAL_JQ|" "$MOCK/jq"
chmod +x "$MOCK/jq"
for noop in xdg-open open; do
  printf '#!/bin/sh\nexit 0\n' > "$MOCK/$noop"
  chmod +x "$MOCK/$noop"
done
# `date` that yields a timestamp with an embedded newline: oauth_timestamp is the one
# header field that is NOT url-encoded, so this is the only hermetic way to put a control
# character into a real oauth_sign header.
mkdir -p "$SANDBOX/baddate"
cat > "$SANDBOX/baddate/date" <<'SHIM'
#!/bin/sh
printf '12\n34'
SHIM
chmod +x "$SANDBOX/baddate/date"

# --- harness -----------------------------------------------------------------------
PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ok   - $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL - $1"; }
not() { ! "$@"; }
check() { # check <label> <cmd...>
  local label="$1"; shift
  if "$@"; then ok "$label"; else bad "$label"; fi
}

OUT="" ERR="" RC=0
# run_sut <extra-path-dir|-> <stdin-text> <env...> -- <cmd...>
run_sut() {
  local extra="$1" input="$2"; shift 2
  local -a envs=()
  while [[ "$1" != "--" ]]; do envs+=("$1"); shift; done
  shift
  rm -f "$MOCK"/count "$MOCK"/argv.* "$MOCK"/stdin.* "$MOCK"/env.* "$MOCK"/body.* \
    "$MOCK"/jqcount "$MOCK"/jqargv.* "$MOCK"/jqenv.*
  local p="$MOCK:$SYS_PATH"
  [[ "$extra" != "-" ]] && p="$extra:$p"
  # SUT_PATH replaces the whole PATH (the no-interpreter hosted canary).
  [[ -n "${SUT_PATH:-}" ]] && p="$SUT_PATH"
  local o="$SANDBOX/out" e="$SANDBOX/err"
  ( cd "${RUN_CWD:-$WORK}" && env -i PATH="$p" HOME="$SANDBOX/home" MOCK_DIR="$MOCK" "${envs[@]}" "$@" ) \
    > "$o" 2> "$e" <<<"$input"
  RC=$?
  OUT="$(cat "$o")"
  ERR="$(cat "$e")"
}

curl_calls() { cat "$MOCK/count" 2>/dev/null || echo 0; }

# argv_has <value> [n]: is <value> a substring of any recorded argv file (or file n)?
argv_has() {
  local files=("$MOCK"/argv.*)
  [[ -n "${2:-}" ]] && files=("$MOCK/argv.$2")
  [[ -e "${files[0]}" ]] || return 1
  grep -aqF -e "$1" -- "${files[@]}"
}

# argv_absent <value> [n]: <value> is NOT on the recorded argv (all calls, or call n) AND curl actually ran.
# Unlike `! argv_has`, it is FALSE when the argv file is missing, so a row cannot pass because curl
# never ran (a refused or crashed run records no argv at all).
argv_absent() {
  local files=("$MOCK"/argv.*)
  [[ -n "${2:-}" ]] && files=("$MOCK/argv.$2")
  [[ -e "${files[0]}" ]] || return 1
  ! grep -aqF -e "$1" -- "${files[@]}"
}

# argv_first3 <n>: first three curl arguments, space-joined.
argv_first3() {
  local -a a=()
  mapfile -d '' -t a < "$MOCK/argv.$1"
  printf '%s %s %s' "${a[0]:-}" "${a[1]:-}" "${a[2]:-}"
}

# cfg_decode <config-line-value>: un-escape `\\` and `\"` as curl does for a quoted string.
cfg_decode() {
  local s="$1" out="" i c
  for (( i = 0; i < ${#s}; i++ )); do
    c="${s:i:1}"
    if [[ "$c" == '\' ]]; then
      i=$((i + 1))
      c="${s:i:1}"
    fi
    out+="$c"
  done
  printf '%s' "$out"
}

stdin_text() { cat "$MOCK/stdin.$1" 2>/dev/null; }
stdin_lines() { local n=0 _l; while IFS= read -r _l; do n=$((n + 1)); done < "$MOCK/stdin.$1"; echo "$n"; }

# --- instrument controls --------------------------------------------------------------
# The helpers above are what every row trusts. Before row 1, drive check() with a failing command
# and not() with an always-true one and require the counters / return codes to move. Reported
# straight through printf + exit 1 (never through the helpers under test), then the counters reset
# so the controls are not counted as assertions.
_p0=$PASS; _f0=$FAIL
{ check "control: failing command" false; } >/dev/null
if (( FAIL != _f0 + 1 || PASS != _p0 )); then
  printf 'FAIL: instrument control: check() did not count a failing command (PASS %s->%s, FAIL %s->%s)\n' "$_p0" "$PASS" "$_f0" "$FAIL" >&2
  exit 1
fi
{ check "control: passing command" true; } >/dev/null
if (( PASS != _p0 + 1 || FAIL != _f0 + 1 )); then
  printf 'FAIL: instrument control: check() did not count a passing command (PASS %s->%s, FAIL %s->%s)\n' "$_p0" "$PASS" "$_f0" "$FAIL" >&2
  exit 1
fi
if not true; then
  printf 'FAIL: instrument control: not() returned success for an always-true command\n' >&2
  exit 1
fi
if ! not false; then
  printf 'FAIL: instrument control: not() returned failure for an always-false command\n' >&2
  exit 1
fi
PASS=$_p0; FAIL=$_f0
unset _p0 _f0

# ===================================================================================
echo "== linkedin-setup.sh validate-credentials =="
LI_SECRET="fixturefixturefixture01"
LI_TOKEN="synthetic-fixture-token-0001"
LI_ENV=(LINKEDIN_CLIENT_ID=synthetic-fixture-client-0001
        "LINKEDIN_CLIENT_SECRET=$LI_SECRET" "LINKEDIN_ACCESS_TOKEN=$LI_TOKEN")

run_sut - "" "${LI_ENV[@]}" -- bash "$LINKEDIN_SETUP" validate-credentials
check "valid: exits 0" test "$RC" -eq 0
check "valid: exactly one curl call" test "$(curl_calls)" -eq 1
check "valid: client secret absent from argv" argv_absent "$LI_SECRET"
check "valid: introspected token absent from argv" argv_absent "$LI_TOKEN"
check "valid: non-secret client_id still on argv (recording works)" argv_has "client_id=synthetic-fixture-client-0001"
check "valid: --disable --noproxy '*' lead argv" test "$(argv_first3 1)" = "--disable --noproxy *"
check "valid: stdin carries --config - contract" argv_has "--config"
EXPECT=$'data-urlencode = "client_secret=fixturefixturefixture01"\ndata-urlencode = "token=synthetic-fixture-token-0001"'
check "valid: exact secret + token config lines on stdin" test "$(stdin_text 1)" = "$EXPECT"

# malformed: refused before any curl, exit 1 (the script's existing refusal code).
# The env var is built with $'..' so the control characters are real bytes.
li_refused() { # li_refused <label> <secret> <token>
  run_sut - "" LINKEDIN_CLIENT_ID=synthetic-fixture-client-0001 \
    "LINKEDIN_CLIENT_SECRET=$2" "LINKEDIN_ACCESS_TOKEN=$3" -- bash "$LINKEDIN_SETUP" validate-credentials
  check "$1: exit 1" test "$RC" -eq 1
  check "$1: curl never invoked" test "$(curl_calls)" -eq 0
  check "$1: refusal reported on stderr" grep -qF "refusing to send it" <<<"$ERR"
}
li_refused "secret with newline"   $'synthetic\nurl = "https://evil.invalid"' "$LI_TOKEN"
li_refused "secret with quote"     'syn"thetic' "$LI_TOKEN"
li_refused "secret with backslash" 'syn\thetic' "$LI_TOKEN"
li_refused "secret with CR"        $'synthetic\rx' "$LI_TOKEN"
li_refused "token with newline"    "$LI_SECRET" $'synthetic\nurl = "https://evil.invalid"'
li_refused "token with quote"      "$LI_SECRET" 'syn"thetic'

echo "== linkedin-setup.sh generate-token =="
run_sut - $'synthetic-auth-code-0001\n' "${LI_ENV[@]}" -- bash "$LINKEDIN_SETUP" generate-token
check "generate-token: exits 0" test "$RC" -eq 0
check "generate-token: two curl calls (accessToken, userinfo)" test "$(curl_calls)" -eq 2
check "generate-token: client secret absent from argv (both calls)" argv_absent "$LI_SECRET"
check "generate-token: access token from the reply absent from argv" argv_absent "synthetic-fixture-token-0002"
check "generate-token: non-secret code still on argv (recording works)" argv_has "code=synthetic-auth-code-0001" 1
check "generate-token: --disable --noproxy '*' lead argv" test "$(argv_first3 1)" = "--disable --noproxy *"
check "generate-token: exact client_secret line on stdin" \
  test "$(stdin_text 1)" = 'data-urlencode = "client_secret=fixturefixturefixture01"'
check "generate-token: userinfo bearer is the stdin header (unchanged)" \
  test "$(stdin_text 2)" = 'header = "Authorization: Bearer synthetic-fixture-token-0002"'

for case_ in 'newline:'$'synthetic\nx' 'quote:syn"thetic' 'backslash:syn\thetic'; do
  run_sut - $'synthetic-auth-code-0001\n' LINKEDIN_CLIENT_ID=synthetic-fixture-client-0001 \
    "LINKEDIN_CLIENT_SECRET=${case_#*:}" LINKEDIN_ACCESS_TOKEN="$LI_TOKEN" -- bash "$LINKEDIN_SETUP" generate-token
  check "generate-token secret with ${case_%%:*}: exit 1" test "$RC" -eq 1
  check "generate-token secret with ${case_%%:*}: curl never invoked" test "$(curl_calls)" -eq 0
  check "generate-token secret with ${case_%%:*}: refusal reported" grep -qF "refusing to send it" <<<"$ERR"
done

# ===================================================================================
echo "== OAuth 1.0a Authorization header =="
X_KEY="synthetic-fixture-key-0001"
X_SECRET="fixturefixturefixture02"
X_TOK="synthetic-fixture-access-0001"
X_TOKSECRET="synthetic-fixture-access-secret-0001"
X_ENV=("X_API_KEY=$X_KEY" "X_API_SECRET=$X_SECRET" "X_ACCESS_TOKEN=$X_TOK" "X_ACCESS_TOKEN_SECRET=$X_TOKSECRET" X_ALLOW_POST=true)

# x_header_checks <label> <n>: assertions common to every OAuth1 call.
x_header_checks() {
  local label="$1" n="$2" raw decoded
  raw="$(stdin_text "$n")"
  decoded="${raw#header = \"}"
  decoded="$(cfg_decode "${decoded%\"}")"
  check "$label: signed header absent from argv" argv_absent "oauth_signature" "$n"
  check "$label: Authorization header text absent from argv" argv_absent "Authorization: OAuth" "$n"
  check "$label: consumer key absent from argv" argv_absent "$X_KEY" "$n"
  check "$label: access token absent from argv" argv_absent "$X_TOK" "$n"
  check "$label: consumer secret absent from argv" argv_absent "$X_SECRET" "$n"
  check "$label: token secret absent from argv" argv_absent "$X_TOKSECRET" "$n"
  check "$label: consumer + token secrets never reach curl at all (argv and stdin)" \
    bash -c '[[ -e "$3" && -e "$4" ]] && ! grep -aqF -e "$1" -e "$2" -- "$3" "$4"' _ "$X_SECRET" "$X_TOKSECRET" "$MOCK/argv.$n" "$MOCK/stdin.$n"
  check "$label: --disable --noproxy '*' lead argv" test "$(argv_first3 "$n")" = "--disable --noproxy *"
  check "$label: config is exactly one header line" test "$(stdin_lines "$n")" -eq 1
  check "$label: raw line is an escaped header directive" \
    grep -qF 'header = "Authorization: OAuth oauth_consumer_key=\"synthetic-fixture-key-0001\", ' <<<"$raw"
  check "$label: decoded header starts as the OAuth header" \
    test "${decoded:0:63}" = 'Authorization: OAuth oauth_consumer_key="synthetic-fixture-key-'
  check "$label: decoded header carries the access token and a signature" \
    bash -c '[[ "$1" == *"oauth_token=\"synthetic-fixture-access-0001\""* && "$1" == *"oauth_signature=\""* && "$1" == *"oauth_version=\"1.0\"" ]]' _ "$decoded"
}

run_sut - "" "${X_ENV[@]}" -- bash "$X_COMMUNITY" fetch-metrics
check "x-community fetch-metrics (get_request): exit 0" test "$RC" -eq 0
check "x-community fetch-metrics: one curl call" test "$(curl_calls)" -eq 1
x_header_checks "x-community get_request" 1

run_sut - "" "${X_ENV[@]}" -- bash "$X_COMMUNITY" post-tweet "synthetic post"
check "x-community post-tweet (post_request): exit 0" test "$RC" -eq 0
check "x-community post-tweet: one curl call" test "$(curl_calls)" -eq 1
check "x-community post-tweet: non-secret body still on argv (recording works)" argv_has "synthetic post"
x_header_checks "x-community post_request" 1

RUN_CWD="$GITWORK" run_sut - "" "${X_ENV[@]}" -- bash "$X_SETUP" validate-credentials
check "x-setup validate-credentials: exit 0" test "$RC" -eq 0
check "x-setup validate-credentials: one curl call" test "$(curl_calls)" -eq 1
x_header_checks "x-setup" 1

# Refusal: a control character in the header. The newline-bearing timestamp is the only
# unencoded header field, so the shim `date` is the hermetic way to produce one.
x_refused() { # x_refused <label> <cmd...>
  local label="$1"; shift
  RUN_CWD="$GITWORK" run_sut "$SANDBOX/baddate" "" "${X_ENV[@]}" -- "$@"
  check "$label: exit 1 (same as a failed request)" test "$RC" -eq 1
  check "$label: curl never invoked" test "$(curl_calls)" -eq 0
  check "$label: refusal reported on stderr" grep -qF "refusing to send it" <<<"$ERR"
}
x_refused "x-community get_request with control char in header" bash "$X_COMMUNITY" fetch-metrics
x_refused "x-community post_request with control char in header" bash "$X_COMMUNITY" post-tweet "synthetic post"
x_refused "x-setup with control char in header" bash "$X_SETUP" validate-credentials

# --- x-community.sh under bash -x: the CONDITIONAL xtrace prologue is kept -----------------------
# The prologue promises "a founder tracing with none set keeps full tracing". The HMAC library refuses
# `bash -x` unconditionally at load time, so loading it at the top of the script would turn a
# credential-free `bash -x x-community.sh` into exit 78. It is sourced lazily at the first signature.
echo "== x-community.sh under bash -x =="
run_sut - "" -- bash -x "$X_COMMUNITY"
check "x-community under bash -x with NO credentials and no command: exit 1 (usage), not the exit-78 refusal" test "$RC" -eq 1
check "x-community under bash -x with no credentials: the usage text is printed" grep -qF "Usage: x-community.sh <command>" <<<"$ERR"
check "x-community under bash -x with no credentials: no refusal text on either stream (neither the script's nor the HMAC library's)" \
  not grep -qF "Refusing" <<<"$OUT$ERR"
run_sut - "" -- bash -x "$X_COMMUNITY" fetch-metrics
check "x-community fetch-metrics under bash -x with NO credentials: exit 1 (missing credentials), curl never invoked, no refusal text" \
  bash -c '[[ "$1" -eq 1 && "$2" -eq 0 && "$3" == *"Missing X API credentials"* && "$3" != *Refusing* ]]' _ "$RC" "$(curl_calls)" "$OUT$ERR"
XV_MARK="SYNTHXV""0001"
for xv_ in X_API_KEY X_API_SECRET X_ACCESS_TOKEN X_ACCESS_TOKEN_SECRET; do
  run_sut - "" "$xv_=$XV_MARK" -- bash -x "$X_COMMUNITY" fetch-metrics
  check "x-community under bash -x with only $xv_ set: still refused (exit 78), curl never invoked, the value reaches no output" \
    bash -c '[[ "$1" -eq 78 && "$2" -eq 0 && "$3" == *"Refusing to run under"* && "$3" != *"$4"* ]]' _ "$RC" "$(curl_calls)" "$OUT$ERR" "$XV_MARK"
done
run_sut - "" "${X_ENV[@]}" -- bash -x "$X_COMMUNITY" fetch-metrics
check "x-community under bash -x with all four credentials set: exit 78, curl never invoked, no secret in any output" \
  bash -c '[[ "$1" -eq 78 && "$2" -eq 0 && "$3" != *"$4"* && "$3" != *"$5"* ]]' _ "$RC" "$(curl_calls)" "$OUT$ERR" "$X_SECRET" "$X_TOKSECRET"

# --- config-string escaping, exercised on the real helper --------------------------
echo "== _cfg_q round trip =="
# shellcheck disable=SC1090
CFGQ_SRC="$(sed -n '/^_cfg_q() {/p' "$X_SETUP")"
eval "$CFGQ_SRC"
for v in 'plain' 'a"b' 'a\b' 'a\"b' '\\"' 'k="v", k2="v2"'; do
  line="header = \"X: $(_cfg_q "$v")\""
  inner="${line#header = \"X: }"
  check "round trip of '$v'" test "$(cfg_decode "${inner%\"}")" = "$v"
done


# ===================================================================================
# Discord Bot token (discord-community.sh, discord-setup.sh) and the Bluesky createSession
# body (bsky-community.sh, bsky-setup.sh). All fixture credentials are SYNTHESIZED by
# concatenation, so no contiguous token-shaped literal exists in this file.
# ===================================================================================
_rep() { printf '%*s' "$2" '' | tr ' ' "$1"; }
DISC_TOK="SYNTH$(_rep A 19).$(_rep B 6).SYNTH$(_rep C 22)"
# Non-canonical but legal: dashes and underscores inside every segment.
DISC_TOK_ODD="SYNTH$(_rep A 8)_-$(_rep a 8).$(_rep B 3)-$(_rep b 2)_.SYNTH$(_rep C 10)-_$(_rep c 10)"
MARK="SYNTHMARK""0001"
GUILD=123456789012345678
BSKY_HANDLE_FIX="synthetic.bsky.social"
BSKY_PW_FIX="SYNTH$(_rep a 4)-$(_rep b 4)-$(_rep c 4)-$(_rep d 4)"
BSKY_JWT_FIX="synthjwt.synthjwt.synthjwt"

# disc_bad <class>: a Discord token that must be refused (the real shape is [A-Za-z0-9_-]+ x3, dot-joined).
disc_bad() {
  case "$1" in
    newline)          printf '%s.aaa.bbb\nurl = "https://evil.invalid"' "$MARK" ;;
    trailing-newline) printf '%s.aaa.bbb\n' "$MARK" ;;
    quote)            printf '%s.aaa.b"b' "$MARK" ;;
    space)            printf '%s.aaa.b b' "$MARK" ;;
    backslash)        printf '%s.aaa.b\\b' "$MARK" ;;
    two-segments)     printf '%s.aaa' "$MARK" ;;
    *) echo "FATAL: unknown class $1" >&2; exit 2 ;;
  esac
}
DISC_BAD_CLASSES=(newline trailing-newline quote space backslash two-segments)

no_leak()      { ! grep -qF -- "$MARK" <<<"$OUT$ERR"; }
no_diag()      { ! grep -qF "SOLEUR_TRANSPORT_DIAG" <<<"$OUT$ERR"; }
refusal_line() { grep -qxF "SOLEUR_CREDENTIAL_REFUSED script=$1 reason=${2:-token_shape}" <<<"$ERR"; }
# rc1_refusal <script> [reason]: exit 1 AND the exact value-free marker line on stderr.
rc1_refusal() { [[ "$RC" -eq 1 ]] && refusal_line "$@"; }
# curl_env_lacks <NAME...>: curl ran AND none of these variable NAMES were in its inherited environment.
curl_env_lacks() {
  local f n seen=0
  for f in "$MOCK"/env.*; do
    [[ -e "$f" ]] || continue
    seen=$((seen + 1))
    for n in "$@"; do grep -qxF -- "$n" "$f" && return 1; done
  done
  (( seen >= 1 ))
}
chk_bot_stdin() { test "$(stdin_text "$1")" = "header = \"Authorization: Bot $2\""; }

# bot_call_checks <label> <n> <token>: the argv/stdin contract of one Discord call.
bot_call_checks() {
  local label="$1" n="$2" tok="$3"
  check "$label: bot token absent from argv" argv_absent "$tok" "$n"
  check "$label: Authorization header text absent from argv" argv_absent "Authorization" "$n"
  check "$label: --disable --noproxy '*' lead argv" test "$(argv_first3 "$n")" = "--disable --noproxy *"
  check "$label: exact Bot header line on the stdin config" chk_bot_stdin "$n" "$tok"
  check "$label: config is exactly one header line" test "$(stdin_lines "$n")" -eq 1
  check "$label: stdin config requested (--config on argv)" argv_has "--config" "$n"
}

echo "== discord-community.sh =="
DC_ENV=("DISCORD_BOT_TOKEN=$DISC_TOK" "DISCORD_GUILD_ID=$GUILD")
run_sut - "" "${DC_ENV[@]}" -- bash "$DISCORD_COMMUNITY" guild-info
check "discord-community guild-info: exit 0" test "$RC" -eq 0
check "discord-community guild-info: exactly one curl call" test "$(curl_calls)" -eq 1
bot_call_checks "discord-community guild-info" 1 "$DISC_TOK"
run_sut - "" "${DC_ENV[@]}" -- bash "$DISCORD_COMMUNITY" channels
check "discord-community channels: exit 0, one call, exact Bot header on stdin" \
  bash -c '[[ "$1" -eq 0 && "$2" -eq 1 ]]' _ "$RC" "$(curl_calls)"
check "discord-community channels: bot token absent from argv, exact stdin line" \
  bash -c '! grep -aqF -e "$1" -- "$2" && [[ "$(cat "$3")" == "header = \"Authorization: Bot $1\"" ]]' _ "$DISC_TOK" "$MOCK/argv.1" "$MOCK/stdin.1"
run_sut - "" "${DC_ENV[@]}" -- bash "$DISCORD_COMMUNITY" messages 5 1
check "discord-community messages: exit 0, one call, token absent from argv, exact stdin line" \
  bash -c '[[ "$1" -eq 0 && "$2" -eq 1 ]] && ! grep -aqF -e "$3" -- "$4" && [[ "$(cat "$5")" == "header = \"Authorization: Bot $3\"" ]]' _ "$RC" "$(curl_calls)" "$DISC_TOK" "$MOCK/argv.1" "$MOCK/stdin.1"

# must-PASS: a legal token that is not the canonical letters-only shape reaches the call.
run_sut - "" "DISCORD_BOT_TOKEN=$DISC_TOK_ODD" "DISCORD_GUILD_ID=$GUILD" -- bash "$DISCORD_COMMUNITY" guild-info
check "discord-community must-PASS (dots, dashes, underscores in the token): exit 0, one call" \
  bash -c '[[ "$1" -eq 0 && "$2" -eq 1 ]]' _ "$RC" "$(curl_calls)"
check "discord-community must-PASS token: absent from argv, exact stdin line" \
  bash -c '! grep -aqF -e "$1" -- "$2" && [[ "$(cat "$3")" == "header = \"Authorization: Bot $1\"" ]]' _ "$DISC_TOK_ODD" "$MOCK/argv.1" "$MOCK/stdin.1"

# disc_bad_val <class>: the token VALUE, byte-exact (a `$(...)` would strip a trailing newline).
disc_bad_val() { BAD_VAL="$(disc_bad "$1"; printf x)"; BAD_VAL="${BAD_VAL%x}"; }
for cls in "${DISC_BAD_CLASSES[@]}"; do
  disc_bad_val "$cls"
  run_sut - "" "DISCORD_BOT_TOKEN=$BAD_VAL" "DISCORD_GUILD_ID=$GUILD" -- bash "$DISCORD_COMMUNITY" guild-info
  check "discord-community token ($cls): exit 1 and the exact value-free refusal line on stderr" rc1_refusal discord-community.sh
  check "discord-community token ($cls): curl never invoked" test "$(curl_calls)" -eq 0
  check "discord-community token ($cls): no leak of the value" no_leak
  check "discord-community token ($cls): not the transport diagnostic" no_diag
  check "discord-community token ($cls): one human line names the expected shape" \
    grep -qF "three dot-separated base64url segments" <<<"$ERR"
  check "discord-community token ($cls): the human line says the value is not shown" grep -qF "The value is not shown." <<<"$ERR"
  check "discord-community token ($cls): not the old base64.base64.base64 wording" \
    bash -c '! grep -qF -e "invalid format" -e "base64.base64.base64" <<<"$1"' _ "$ERR"
done

echo "== discord-setup.sh =="
DS_ENV=("DISCORD_BOT_TOKEN_INPUT=$DISC_TOK")
RUN_CWD="$GITWORK" run_sut - "" "${DS_ENV[@]}" -- bash "$DISCORD_SETUP" validate-token
check "discord-setup validate-token: exit 0" test "$RC" -eq 0
check "discord-setup validate-token: two curl calls (users/@me, applications/@me)" test "$(curl_calls)" -eq 2
check "discord-setup validate-token: application id still on stdout" test "$OUT" = "$GUILD"
bot_call_checks "discord-setup validate-token call 1" 1 "$DISC_TOK"
bot_call_checks "discord-setup validate-token call 2" 2 "$DISC_TOK"
RUN_CWD="$GITWORK" run_sut - "" "${DS_ENV[@]}" -- bash "$DISCORD_SETUP" discover-guilds
check "discord-setup discover-guilds: exit 0, one call" bash -c '[[ "$1" -eq 0 && "$2" -eq 1 ]]' _ "$RC" "$(curl_calls)"
bot_call_checks "discord-setup discover-guilds" 1 "$DISC_TOK"
RUN_CWD="$GITWORK" run_sut - "" "${DS_ENV[@]}" -- bash "$DISCORD_SETUP" create-webhook "$GUILD"
check "discord-setup create-webhook: exit 0, one call" bash -c '[[ "$1" -eq 0 && "$2" -eq 1 ]]' _ "$RC" "$(curl_calls)"
check "discord-setup create-webhook: non-secret body still on argv (recording works)" argv_has "soleur-community" 1
check "discord-setup create-webhook: still a POST" argv_has "POST" 1
bot_call_checks "discord-setup create-webhook" 1 "$DISC_TOK"
RUN_CWD="$GITWORK" run_sut - "" "DISCORD_BOT_TOKEN_INPUT=$DISC_TOK_ODD" -- bash "$DISCORD_SETUP" validate-token
check "discord-setup must-PASS (dots, dashes, underscores in the token): exit 0, two calls" \
  bash -c '[[ "$1" -eq 0 && "$2" -eq 2 ]]' _ "$RC" "$(curl_calls)"
check "discord-setup must-PASS token: exact stdin line on both calls, absent from argv" \
  bash -c '[[ "$(cat "$3")" == "header = \"Authorization: Bot $1\"" && "$(cat "$4")" == "header = \"Authorization: Bot $1\"" ]] && ! grep -aqF -e "$1" -- "$5" "$6"' _ "$DISC_TOK_ODD" x "$MOCK/stdin.1" "$MOCK/stdin.2" "$MOCK/argv.1" "$MOCK/argv.2"
for cls in "${DISC_BAD_CLASSES[@]}"; do
  disc_bad_val "$cls"
  RUN_CWD="$GITWORK" run_sut - "" "DISCORD_BOT_TOKEN_INPUT=$BAD_VAL" -- bash "$DISCORD_SETUP" validate-token
  check "discord-setup token ($cls): exit 1 and the exact value-free refusal line on stderr" rc1_refusal discord-setup.sh
  check "discord-setup token ($cls): one human line names the expected shape" \
    grep -qF "three dot-separated base64url segments" <<<"$ERR"
  check "discord-setup token ($cls): the human line says the value is not shown" grep -qF "The value is not shown." <<<"$ERR"
  check "discord-setup token ($cls): curl never invoked" test "$(curl_calls)" -eq 0
  check "discord-setup token ($cls): no leak of the value" no_leak
  check "discord-setup token ($cls): not the connect-failure report" not grep -qF "Failed to connect" <<<"$ERR"
done
# xtrace refusal (the lint's "binds a live credential but carries no xtrace refusal").
RUN_CWD="$GITWORK" run_sut - "" "${DS_ENV[@]}" -- bash -x "$DISCORD_SETUP" validate-token
check "discord-setup under bash -x with the token bound: exit 78" test "$RC" -eq 78
check "discord-setup under bash -x: curl never invoked" test "$(curl_calls)" -eq 0
check "discord-setup under bash -x: the token reaches no output" bash -c '! grep -qF -e "$1" <<<"$2"' _ "$DISC_TOK" "$OUT$ERR"
# transport failure: the proxy case is NAMED (the conversion adds --noproxy '*').
RUN_CWD="$GITWORK" run_sut - "" "${DS_ENV[@]}" HTTPS_PROXY=http://127.0.0.1:1 SHIM_MODE=fail7 -- bash "$DISCORD_SETUP" validate-token
check "discord-setup connect failure with a proxy set: exit 1" test "$RC" -eq 1
check "discord-setup connect failure with a proxy set: names the deliberate proxy bypass" grep -qF "bypasses your proxy" <<<"$ERR"
check "discord-setup connect failure: token not echoed" bash -c '! grep -qF -e "$1" <<<"$2"' _ "$DISC_TOK" "$OUT$ERR"
check "discord-setup connect failure with a proxy set: the structured diagnostic marker is on stdout" \
  grep -qF "SOLEUR_TRANSPORT_DIAG surface=" <<<"$OUT"
RUN_CWD="$GITWORK" run_sut - "" "${DS_ENV[@]}" SHIM_MODE=fail7 -- bash "$DISCORD_SETUP" validate-token
check "discord-setup connect failure without a proxy: exit 1, no proxy claim" \
  bash -c '[[ "$1" -eq 1 ]] && ! grep -qF "bypasses your proxy" <<<"$2"' _ "$RC" "$ERR"
check "discord-setup connect failure with no proxy and no curlrc: the bare network line is the last resort" \
  grep -qF "Check your network connection" <<<"$ERR"
# Transport parity with the sibling scripts (TLS-trust arm, ~/.curlrc arm, the diagnostic marker).
RUN_CWD="$GITWORK" run_sut - "" "${DS_ENV[@]}" SHIM_MODE=fail60 -- bash "$DISCORD_SETUP" validate-token
check "discord-setup curl exit 60: exit 1" test "$RC" -eq 1
check "discord-setup curl exit 60: the message names TLS trust, not the network" \
  bash -c 'grep -qF "TLS trust failure" <<<"$1" && ! grep -qF "Check your network connection" <<<"$1"' _ "$ERR"
check "discord-setup curl exit 60: the diagnostic marker carries curl_exit=60 and the script name" \
  grep -qF "script=discord-setup.sh curl_exit=60" <<<"$OUT"
printf 'proxy = "http://127.0.0.1:1"\n' > "$SANDBOX/home/.curlrc"
RUN_CWD="$GITWORK" run_sut - "" "${DS_ENV[@]}" SHIM_MODE=fail7 -- bash "$DISCORD_SETUP" validate-token
rm -f "$SANDBOX/home/.curlrc"
check "discord-setup connect failure with a ~/.curlrc: the message names the curlrc that --disable dropped" \
  bash -c 'grep -qF "~/.curlrc" <<<"$1" && grep -qF "(--disable)" <<<"$1" && ! grep -qF "Check your network connection" <<<"$1"' _ "$ERR"
# The transport-trust variables are unset in the prologue: an exported CURL_CA_BUNDLE must not reach curl.
TLS_ENV=(CURL_CA_BUNDLE=/nonexistent/ca.pem SSL_CERT_FILE=/nonexistent/c.pem SSL_CERT_DIR=/nonexistent SSLKEYLOGFILE=/nonexistent/k.log CURL_HOME=/nonexistent)
RUN_CWD="$GITWORK" run_sut - "" "${DS_ENV[@]}" "${TLS_ENV[@]}" -- bash "$DISCORD_SETUP" discover-guilds
check "discord-setup with the trust variables exported: exit 0, one call (recording works)" \
  bash -c '[[ "$1" -eq 0 && "$2" -eq 1 ]]' _ "$RC" "$(curl_calls)"
check "discord-setup: CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR SSLKEYLOGFILE CURL_HOME never reach curl's environment" \
  curl_env_lacks CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR SSLKEYLOGFILE CURL_HOME

# --- harness rows: a shim that stops recording stdin turns the Discord stdin row RED -------
run_sut - "" "${DC_ENV[@]}" SHIM_MUTATE=nostdin -- bash "$DISCORD_COMMUNITY" guild-info
check "harness: a shim that stops recording stdin makes the Discord stdin row RED" not chk_bot_stdin 1 "$DISC_TOK"
check "harness: that control is RED because of the shim: curl ran and no stdin file was recorded (not a refused credential)" \
  bash -c '[[ "$1" -ge 1 && ! -e "$2" ]]' _ "$(curl_calls)" "$MOCK/stdin.1"

# ===================================================================================
echo "== bsky-community.sh createSession =="
BC_ENV=("BSKY_HANDLE=$BSKY_HANDLE_FIX" "BSKY_APP_PASSWORD=$BSKY_PW_FIX")
# A handle holding a real control character (newline): refused, never sent.
BAD_HANDLE=$'syn\nthetic'"$MARK"

# body_arg <n>: the operand after --data-binary on call n.
body_arg() {
  local -a a=(); local i
  mapfile -d '' -t a < "$MOCK/argv.$1"
  for (( i = 0; i < ${#a[@]} - 1; i++ )); do
    [[ "${a[i]}" == "--data-binary" ]] && { printf '%s' "${a[i+1]}"; return 0; }
  done
  return 1
}
# The createSession body arrives on curl's STDIN (`--data-binary @-`); the shim records it as body.<n>.
chk_body_ok() { # <n> <handle> <password>
  [[ -s "$MOCK/body.$1" ]] && jq -e --arg h "$2" --arg p "$3" '.identifier == $h and .password == $p' "$MOCK/body.$1" >/dev/null 2>&1
}
jq_argv_has() { local f; for f in "$MOCK"/jqargv.*; do [[ -e "$f" ]] && grep -aqF -e "$1" -- "$f" && return 0; done; return 1; }
# jq_argv_absent <value>: not on any recorded jq argv AND jq actually ran (FALSE when nothing was recorded).
jq_argv_absent() {
  local f seen=0
  for f in "$MOCK"/jqargv.*; do
    [[ -e "$f" ]] || continue
    seen=1
    grep -aqF -e "$1" -- "$f" && return 1
  done
  (( seen ))
}
jq_calls() { cat "$MOCK/jqcount" 2>/dev/null || echo 0; }
# jq_recording_ok: the jq shim recorded >= 2 calls AND one of them is the writer (its program reads $ENV.BSKY_PW).
jq_recording_ok() { [[ "$(jq_calls)" -ge 2 ]] && jq_argv_has 'ENV.BSKY_PW'; }
# The writer is the jq call whose program reads $ENV.BSKY_PW; it must inherit the names, every other jq must not.
jq_writer_env_ok() {
  local f n seen=0
  for f in "$MOCK"/jqargv.*; do
    [[ -e "$f" ]] || continue
    n="${f##*.}"
    if grep -aqF 'ENV.BSKY_PW' "$f"; then
      seen=$((seen + 1))
      grep -qxF BSKY_PW "$MOCK/jqenv.$n" && grep -qxF BSKY_ID "$MOCK/jqenv.$n" || return 1
    fi
  done
  (( seen >= 1 ))
}
jq_others_env_clean() {
  local f n others=0
  for f in "$MOCK"/jqargv.*; do
    [[ -e "$f" ]] || continue
    n="${f##*.}"
    grep -aqF 'ENV.BSKY_PW' "$f" && continue
    others=$((others + 1))
    grep -qxF -e BSKY_PW -e BSKY_ID "$MOCK/jqenv.$n" && return 1
  done
  (( others >= 1 ))
}
curl_env_clean() {
  local f seen=0
  for f in "$MOCK"/env.*; do
    [[ -e "$f" ]] || continue
    seen=$((seen + 1))
    grep -qxF -e BSKY_PW -e BSKY_ID "$f" && return 1
  done
  (( seen >= 1 ))
}

# bsky_body_checks <label> <n> <handle> <password>
bsky_body_checks() {
  local label="$1" n="$2" h="$3" pw="$4"
  check "$label: password absent from argv" argv_absent "$pw" "$n"
  check "$label: handle absent from argv" argv_absent "$h" "$n"
  check "$label: --disable --noproxy '*' lead argv" test "$(argv_first3 "$n")" = "--disable --noproxy *"
  check "$label: body sent as --data-binary @- (curl's stdin, no file)" test "$(body_arg "$n" || true)" = "@-"
  check "$label: stdin body held exactly the handle and password" chk_body_ok "$n" "$h" "$pw"
  check "$label: createSession carries no stdin config (the body owns stdin)" argv_absent "--config" "$n"
  check "$label: explicit JSON Content-Type" argv_has "Content-Type: application/json" "$n"
}

run_sut - "" "${BC_ENV[@]}" -- bash "$BSKY_COMMUNITY" create-session
check "bsky-community create-session: exit 0" test "$RC" -eq 0
check "bsky-community create-session: exactly one curl call" test "$(curl_calls)" -eq 1
check "bsky-community create-session: the session DID still reaches stdout" grep -qF "did:plc:synth0001" <<<"$OUT"
bsky_body_checks "bsky-community create-session" 1 "$BSKY_HANDLE_FIX" "$BSKY_PW_FIX"
check "bsky-community create-session: password absent from every jq argv (jq shim)" jq_argv_absent "$BSKY_PW_FIX"
check "bsky-community create-session: handle absent from every jq argv (jq shim)" jq_argv_absent "$BSKY_HANDLE_FIX"
check "bsky-community create-session: jq shim recorded calls and the writer reads \$ENV.BSKY_PW (recording works)" \
  jq_recording_ok
check "bsky-community create-session: the writer jq inherits both variable names" jq_writer_env_ok
check "bsky-community create-session: no other jq child inherits them" jq_others_env_clean
check "bsky-community create-session: the curl child does not inherit them" curl_env_clean

# handle with a double quote: escaped by jq, never injectable
run_sut - "" "BSKY_HANDLE=syn\"thetic.bsky.social" "BSKY_APP_PASSWORD=$BSKY_PW_FIX" -- bash "$BSKY_COMMUNITY" create-session
# (The script's own session-echo line is not escaped, so its exit status is not asserted: that
# line is unreachable with a real session, since Bluesky would never mint one for this handle.)
check "bsky-community handle with a double quote: createSession is still sent exactly once" test "$(curl_calls)" -eq 1
check "bsky-community handle with a double quote: body decodes to exactly that handle (escaped, not injected)" \
  chk_body_ok 1 'syn"thetic.bsky.social' "$BSKY_PW_FIX"
# a handle or password with a control character is refused BEFORE curl; non-zero, never 0 or 3; marker on stderr
# bsky_field_line <field> <other-field>: the ONE human line names the refused FIELD (label only) and not the other.
bsky_field_line() { grep -qF "Error: $1 is empty or contains a control character" <<<"$ERR" && ! grep -qF "$2" <<<"$ERR"; }
bsky_refused() { # <label> <handle> <password> <refused-field> <other-field>
  run_sut - "" "BSKY_HANDLE=$2" "BSKY_APP_PASSWORD=$3" -- bash "$BSKY_COMMUNITY" create-session
  check "$1: exit 1 (non-zero, never 0 or 3) and the exact value-free marker, reason=control_char" rc1_refusal bsky-community.sh control_char
  check "$1: curl never invoked" test "$(curl_calls)" -eq 0
  check "$1: value never echoed" no_leak
  check "$1: jq never invoked (the refused value reaches no child process)" test "$(jq_calls)" -eq 0
  check "$1: one human line names the refused field only" bsky_field_line "$4" "$5"
  check "$1: not the transport diagnostic" no_diag
}
bsky_refused "bsky-community handle with a newline" "$BAD_HANDLE" "$BSKY_PW_FIX" BSKY_HANDLE BSKY_APP_PASSWORD
bsky_refused "bsky-community password with a control character" "$BSKY_HANDLE_FIX" "$MARK"$'\x01'"x" BSKY_APP_PASSWORD BSKY_HANDLE
# a failed body build is classified as a BODY-BUILD failure (exit 1, curl never run, no transport diagnostic).
bsky_jqfail_rows() { # <label>
  check "$1: jq failure while building the body: exit 1, no session reported" \
    bash -c '[[ "$1" -eq 1 ]] && ! grep -qF "did:plc:synth0001" <<<"$2"' _ "$RC" "$OUT"
  check "$1: jq failure names a body-build failure" grep -qF "could not build the Bluesky createSession request body" <<<"$ERR"
  check "$1: jq failure is NOT reported as a curl transport failure" \
    bash -c '! grep -qF -e "SOLEUR_TRANSPORT_DIAG" -e "curl_exit" -e "Failed to connect" <<<"$1"' _ "$OUT$ERR"
  check "$1: jq failure: curl never invoked (nothing was sent)" test "$(curl_calls)" -eq 0
}
run_sut - "" "${BC_ENV[@]}" SHIM_MODE=jqfail -- bash "$BSKY_COMMUNITY" create-session
bsky_jqfail_rows "bsky-community"
# xtrace refusal with the password bound: exit 78, curl never invoked, the password reaches no output.
run_sut - "" "${BC_ENV[@]}" -- bash -x "$BSKY_COMMUNITY" create-session
check "bsky-community under bash -x with the password bound: exit 78" test "$RC" -eq 78
check "bsky-community under bash -x: curl never invoked" test "$(curl_calls)" -eq 0
check "bsky-community under bash -x: the password reaches no output" bash -c '! grep -qF -e "$1" <<<"$2"' _ "$BSKY_PW_FIX" "$OUT$ERR"

echo "== bsky-community.sh get-metrics and post =="
run_sut - "" "${BC_ENV[@]}" -- bash "$BSKY_COMMUNITY" get-metrics
check "bsky-community get-metrics: exit 0, two calls (createSession, getProfile)" bash -c '[[ "$1" -eq 0 && "$2" -eq 2 ]]' _ "$RC" "$(curl_calls)"
bsky_body_checks "bsky-community get-metrics createSession" 1 "$BSKY_HANDLE_FIX" "$BSKY_PW_FIX"
check "bsky-community get-metrics: the session bearer is the stdin header on the profile call (unchanged)" \
  test "$(stdin_text 2)" = "header = \"Authorization: Bearer $BSKY_JWT_FIX\""
run_sut - "" "${BC_ENV[@]}" BSKY_ALLOW_POST=true -- bash "$BSKY_COMMUNITY" post "synthetic post text"
check "bsky-community post (the hosted path): exit 0, two calls (createSession, createRecord)" bash -c '[[ "$1" -eq 0 && "$2" -eq 2 ]]' _ "$RC" "$(curl_calls)"
bsky_body_checks "bsky-community post createSession" 1 "$BSKY_HANDLE_FIX" "$BSKY_PW_FIX"
check "bsky-community post: the password never reaches the createRecord call either" argv_absent "$BSKY_PW_FIX" 2
run_sut - "" "BSKY_HANDLE=$BSKY_HANDLE_FIX" "BSKY_APP_PASSWORD=$MARK"$'\x01'"x" BSKY_ALLOW_POST=true -- bash "$BSKY_COMMUNITY" post "synthetic post text"
check "bsky-community post (hosted): a refused credential exits 1, never 0 or 3, curl never invoked" \
  bash -c '[[ "$1" -eq 1 && "$2" -eq 0 ]]' _ "$RC" "$(curl_calls)"
check "bsky-community post (hosted): the refusal marker (reason=control_char) reaches stderr, where content-publisher captures it" refusal_line bsky-community.sh control_char

# A SERVER-SUPPLIED session token with a quote + newline + `url = ...` directive must be refused by
# the _bearer_ok guard BEFORE it is formatted into the stdin config: only the createSession call runs.
badjwt_rows() { # <label>
  check "$1: a hostile accessJwt is refused (exit 1)" test "$RC" -eq 1
  check "$1: only createSession ran (zero createRecord / getProfile calls)" test "$(curl_calls)" -eq 1
  check "$1: the refusal names the unexpected shape" grep -qE "accessJwt.*(unexpected shape|missing)" <<<"$ERR"
  check "$1: the injected directive never reaches the output" bash -c '! grep -qF "evil.invalid" <<<"$1"' _ "$OUT$ERR"
}
run_sut - "" "${BC_ENV[@]}" SHIM_MODE=badjwt -- bash "$BSKY_COMMUNITY" get-metrics
badjwt_rows "bsky-community get-metrics"
run_sut - "" "${BC_ENV[@]}" BSKY_ALLOW_POST=true SHIM_MODE=badjwt -- bash "$BSKY_COMMUNITY" post "synthetic post text"
badjwt_rows "bsky-community post"

# --- harness row: a shim that stops reading the stdin body turns the body rows RED -------------
run_sut - "" "${BC_ENV[@]}" SHIM_MUTATE=nobody -- bash "$BSKY_COMMUNITY" create-session
check "harness: a shim that stops recording the stdin body makes the body-content row RED" not chk_body_ok 1 "$BSKY_HANDLE_FIX" "$BSKY_PW_FIX"
check "harness: that control is RED because of the shim: curl ran and no body file was recorded (not a refused credential)" \
  bash -c '[[ "$1" -ge 1 && ! -e "$2" ]]' _ "$(curl_calls)" "$MOCK/body.1"

echo "== bsky-setup.sh verify =="
# verify sources $GIT_ROOT/.env; the file is synthesized here and lives in the scratch checkout.
printf 'BSKY_HANDLE=%s\nBSKY_APP_PASSWORD=%s\n' "$BSKY_HANDLE_FIX" "$BSKY_PW_FIX" > "$GITWORK/.env"
RUN_CWD="$GITWORK" run_sut - "" -- bash "$BSKY_SETUP" verify
check "bsky-setup verify: exit 0, two calls (createSession, getProfile)" bash -c '[[ "$1" -eq 0 && "$2" -eq 2 ]]' _ "$RC" "$(curl_calls)"
bsky_body_checks "bsky-setup verify createSession" 1 "$BSKY_HANDLE_FIX" "$BSKY_PW_FIX"
check "bsky-setup verify: password absent from every jq argv (jq shim)" jq_argv_absent "$BSKY_PW_FIX"
check "bsky-setup verify: handle absent from every jq argv (jq shim)" jq_argv_absent "$BSKY_HANDLE_FIX"
check "bsky-setup verify: the writer jq inherits the variable names" jq_writer_env_ok
check "bsky-setup verify: no other jq child inherits them" jq_others_env_clean
check "bsky-setup verify: the curl children do not inherit them" curl_env_clean
check "bsky-setup verify: the .env credentials are un-exported again (BSKY_HANDLE, BSKY_APP_PASSWORD absent from curl's environment)" \
  curl_env_lacks BSKY_HANDLE BSKY_APP_PASSWORD
check "bsky-setup verify: the session bearer is the stdin header on the profile call (unchanged)" \
  test "$(stdin_text 2)" = "header = \"Authorization: Bearer $BSKY_JWT_FIX\""
RUN_CWD="$GITWORK" run_sut - "" SHIM_MODE=jqfail -- bash "$BSKY_SETUP" verify
bsky_jqfail_rows "bsky-setup verify"
RUN_CWD="$GITWORK" run_sut - "" SHIM_MODE=badjwt -- bash "$BSKY_SETUP" verify
badjwt_rows "bsky-setup verify"
RUN_CWD="$GITWORK" run_sut - "" -- bash -x "$BSKY_SETUP" verify
check "bsky-setup under bash -x: exit 78" test "$RC" -eq 78
check "bsky-setup under bash -x: curl never invoked" test "$(curl_calls)" -eq 0
check "bsky-setup under bash -x: the password reaches no output" bash -c '! grep -qF -e "$1" <<<"$2"' _ "$BSKY_PW_FIX" "$OUT$ERR"
printf 'BSKY_HANDLE=$%s\nBSKY_APP_PASSWORD=%s\n' "'syn\\001thetic${MARK}'" "$BSKY_PW_FIX" > "$GITWORK/.env"
RUN_CWD="$GITWORK" run_sut - "" -- bash "$BSKY_SETUP" verify
check "bsky-setup verify with a control character in the handle: exit 1, curl never invoked" \
  bash -c '[[ "$1" -eq 1 && "$2" -eq 0 ]]' _ "$RC" "$(curl_calls)"
check "bsky-setup verify with a control character in the handle: exact refusal marker (reason=control_char) on stderr" refusal_line bsky-setup.sh control_char
check "bsky-setup verify with a control character in the handle: value not echoed" no_leak
check "bsky-setup verify with a control character in the handle: jq never invoked" test "$(jq_calls)" -eq 0
check "bsky-setup verify with a control character in the handle: one human line names BSKY_HANDLE only" bsky_field_line BSKY_HANDLE BSKY_APP_PASSWORD
printf 'BSKY_HANDLE=%s\nBSKY_APP_PASSWORD=$%s\n' "$BSKY_HANDLE_FIX" "'syn\\001thetic${MARK}'" > "$GITWORK/.env"
RUN_CWD="$GITWORK" run_sut - "" -- bash "$BSKY_SETUP" verify
check "bsky-setup verify with a control character in the password: exit 1, exact marker (reason=control_char), curl and jq never invoked" \
  bash -c '[[ "$1" -eq 1 && "$2" -eq 0 && "$3" -eq 0 ]]' _ "$RC" "$(curl_calls)" "$(jq_calls)"
check "bsky-setup verify with a control character in the password: the marker line is exact" refusal_line bsky-setup.sh control_char
check "bsky-setup verify with a control character in the password: one human line names BSKY_APP_PASSWORD only, value not echoed" \
  bash -c 'grep -qF "Error: BSKY_APP_PASSWORD is empty or contains a control character" <<<"$1" && ! grep -qF "BSKY_HANDLE" <<<"$1" && ! grep -qF "$2" <<<"$1"' _ "$ERR" "$MARK"
rm -f "$GITWORK/.env"


# ===================================================================================
# MUTATION rows: each mutant is the real script with ONE literal changed, and each must be
# caught by the same predicate the rows above use. A mutant whose literal is absent aborts
# the suite (a mutation that does not land reports the baseline, which reads as a pass).
# ===================================================================================
echo "== mutants =="
MUT="$SANDBOX/mut"
mkdir -p "$MUT/skills/community/scripts" "$MUT/scripts"
cp "$HERE/../../../scripts/resolve-git-root.sh" "$MUT/scripts/"
# mut_make <basename> <from1> <to1> [<from2> <to2> ...] -> $MUT/skills/community/scripts/<basename>
mut_make() {
  local name="$1" text out="$MUT/skills/community/scripts/$1"; shift
  text="$(cat "$HERE/$name"; printf x)"; text="${text%x}"
  while (( $# >= 2 )); do
    if [[ "$text" != *"$1"* ]]; then echo "FATAL: mutation did not land in $name: '${1:0:50}...'" >&2; exit 2; fi
    text="${text/"$1"/"$2"}"
    shift 2
  done
  printf '%s' "$text" > "$out"
  printf '%s' "$out"
}

# 1. Restore `-H "Authorization: Bot ${TOKEN}"` at the one call site: RED on token-in-argv and on the stdin line.
M="$(mut_make discord-community.sh \
  '"\n%{http_code}" --config - \' '"\n%{http_code}" -H "Authorization: Bot ${DISCORD_BOT_TOKEN}" \' \
  $'2>/dev/null \\\n    < <(printf \'header = "Authorization: Bot %s"\\n\' "$DISCORD_BOT_TOKEN")) ||' '2>/dev/null) ||')"
run_sut - "" "${DC_ENV[@]}" -- bash "$M" guild-info
check "mutant: discord-community with the argv header restored is RED (token in argv)" argv_has "$DISC_TOK" 1
check "mutant: discord-community with the argv header restored is RED (no stdin config line)" not chk_bot_stdin 1 "$DISC_TOK"
M="$(mut_make discord-setup.sh \
  $'    --config -\n    -X "$method"' $'    -H "Authorization: Bot ${DISCORD_BOT_TOKEN_INPUT}"\n    -X "$method"' \
  $'2>/dev/null \\\n      < <(printf \'header = "Authorization: Bot %s"\\n\' "$DISCORD_BOT_TOKEN_INPUT"))' '2>/dev/null)')"
RUN_CWD="$GITWORK" run_sut - "" "${DS_ENV[@]}" -- bash "$M" discover-guilds
check "mutant: discord-setup with the array-held argv header restored is RED (token in argv)" argv_has "$DISC_TOK" 1
check "mutant: discord-setup with the array-held argv header restored is RED (no stdin config line)" not chk_bot_stdin 1 "$DISC_TOK"

# 2. A guard loosened to "two dots" accepts a newline: the newline rows must catch it.
M="$(mut_make discord-community.sh '[[ "$t" =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]]' '[[ "$t" == *.*.* ]]')"
for cls in newline trailing-newline; do
  disc_bad_val "$cls"
  run_sut - "" "DISCORD_BOT_TOKEN=$BAD_VAL" "DISCORD_GUILD_ID=$GUILD" -- bash "$M" guild-info
  check "mutant: a guard that accepts a $cls lets the token reach curl (the refusal rows catch it)" test "$(curl_calls)" -ge 1
done

# 3. Both guards disabled: a malformed token reaches curl (curl_calls != 0 is what the refusal rows assert against).
M="$(mut_make discord-community.sh \
  '_discord_token_ok "${DISCORD_BOT_TOKEN}" || refuse_token_shape' ':' \
  'if ! _discord_token_ok "${DISCORD_BOT_TOKEN}"; then' 'if false; then')"
disc_bad_val newline
run_sut - "" "DISCORD_BOT_TOKEN=$BAD_VAL" "DISCORD_GUILD_ID=$GUILD" -- bash "$M" guild-info
check "mutant: discord-community with its guards removed invokes curl on a malformed token (RED on the refusal rows)" test "$(curl_calls)" -ge 1
M="$(mut_make discord-setup.sh '_discord_token_ok "${DISCORD_BOT_TOKEN_INPUT}" || refuse_token_shape' ':')"
RUN_CWD="$GITWORK" run_sut - "" "DISCORD_BOT_TOKEN_INPUT=$BAD_VAL" -- bash "$M" validate-token
check "mutant: discord-setup with its guard removed invokes curl on a malformed token (RED on the refusal rows)" test "$(curl_calls)" -ge 1

# 4. The bsky password handed to curl as `-d "$body"`, to jq as `--arg`, or exported; the
# control-character guard removed; the jq body-build failure no longer fatal.
M="$(mut_make bsky-community.sh '--data-binary @- \' '-d "{\"identifier\": \"${BSKY_HANDLE}\", \"password\": \"${BSKY_APP_PASSWORD}\"}" \')"
run_sut - "" "${BC_ENV[@]}" -- bash "$M" create-session
check "mutant: bsky-community handing the password to curl as -d is RED (password in argv)" argv_has "$BSKY_PW_FIX" 1
check "mutant: bsky-community handing the password to curl as -d is RED (no --data-binary @- stdin body)" not chk_body_ok 1 "$BSKY_HANDLE_FIX" "$BSKY_PW_FIX"
M="$(mut_make bsky-community.sh \
  $'BSKY_ID="$BSKY_HANDLE" BSKY_PW="$BSKY_APP_PASSWORD" \\\n    jq -n \'{identifier: $ENV.BSKY_ID, password: $ENV.BSKY_PW}\'' \
  $'jq -n --arg id "$BSKY_HANDLE" --arg pw "$BSKY_APP_PASSWORD" \'{identifier: $id, password: $pw}\'')"
run_sut - "" "${BC_ENV[@]}" -- bash "$M" create-session
check "mutant: bsky-community passing the password to jq as --arg is RED (password on jq argv, jq shim)" jq_argv_has "$BSKY_PW_FIX"
check "mutant: bsky-community passing the password to jq as --arg is RED (the environment row loses its writer)" not jq_writer_env_ok
check "mutant: bsky-community passing the password to jq as --arg: the curl shim alone stays blind to it" argv_absent "$BSKY_PW_FIX" 1
# An export at function scope: the curl child AND every later jq child inherit the names.
M="$(mut_make bsky-community.sh $'  local req_body\n' $'  local req_body\n  export BSKY_ID="$BSKY_HANDLE" BSKY_PW="$BSKY_APP_PASSWORD"\n')"
run_sut - "" "${BC_ENV[@]}" -- bash "$M" create-session
check "mutant: bsky-community exporting the password is RED (the curl child inherits it)" not curl_env_clean
check "mutant: bsky-community exporting the password is RED (a later, non-writer jq child inherits it)" not jq_others_env_clean
M="$(mut_make bsky-community.sh \
  $'  _bsky_cred_ok "${BSKY_HANDLE:-}" || bsky_refuse control_char BSKY_HANDLE\n' ':
' \
  $'  _bsky_cred_ok "${BSKY_APP_PASSWORD:-}" || bsky_refuse control_char BSKY_APP_PASSWORD\n' ':
')"
run_sut - "" "BSKY_HANDLE=$BAD_HANDLE" "BSKY_APP_PASSWORD=$BSKY_PW_FIX" -- bash "$M" create-session
check "mutant: bsky-community with its guard removed invokes curl on a control-character handle (RED on the refusal rows)" test "$(curl_calls)" -ge 1
# The jq body-build failure no longer fatal: the empty body is POSTed and the session reads as good (RED on the jq-failure rows).
M="$(mut_make bsky-community.sh "password: \$ENV.BSKY_PW}') || {" "password: \$ENV.BSKY_PW}') || true; false && {")"
run_sut - "" "${BC_ENV[@]}" SHIM_MODE=jqfail -- bash "$M" create-session
check "mutant: bsky-community ignoring the jq failure reads a failed body build as a good POST (RC 0, no body-build message)" \
  bash -c '[[ "$1" -eq 0 ]] && ! grep -qF "could not build" <<<"$2"' _ "$RC" "$ERR"
# Independence from pipefail: the classification is a command-substitution status, not a pipeline status.
M="$(mut_make bsky-community.sh 'set -euo pipefail' 'set -eu')"
run_sut - "" "${BC_ENV[@]}" SHIM_MODE=jqfail -- bash "$M" create-session
bsky_jqfail_rows "bsky-community WITHOUT pipefail"
# The bearer guards: with BOTH removed a hostile server-supplied accessJwt reaches the stdin config.
M="$(mut_make bsky-community.sh \
  $'  if ! _bearer_ok "$ACCESS_JWT"; then\n        ACCESS_JWT=""' $'  if false; then\n        ACCESS_JWT=""' \
  '  _bearer_ok "$ACCESS_JWT" || return 120' '  :')"
run_sut - "" "${BC_ENV[@]}" SHIM_MODE=badjwt -- bash "$M" get-metrics
check "mutant: bsky-community with the bearer guards removed sends the hostile token (a getProfile call follows; RED on the refusal rows)" test "$(curl_calls)" -ge 2
check "mutant: bsky-community with the bearer guards removed: the stdin config carries an injected extra line" test "$(stdin_lines 2)" -gt 1
M="$(mut_make bsky-setup.sh '--data-binary @- \' '-d "{\"identifier\": \"${BSKY_HANDLE}\", \"password\": \"${BSKY_APP_PASSWORD}\"}" \')"
printf 'BSKY_HANDLE=%s\nBSKY_APP_PASSWORD=%s\n' "$BSKY_HANDLE_FIX" "$BSKY_PW_FIX" > "$GITWORK/.env"
RUN_CWD="$GITWORK" run_sut - "" -- bash "$M" verify
check "mutant: bsky-setup handing the password to curl as -d is RED (password in argv)" argv_has "$BSKY_PW_FIX" 1
check "mutant: bsky-setup handing the password to curl as -d is RED (no --data-binary @- stdin body)" not chk_body_ok 1 "$BSKY_HANDLE_FIX" "$BSKY_PW_FIX"
M="$(mut_make bsky-setup.sh \
  $'  _bsky_cred_ok "${BSKY_HANDLE:-}" || bsky_refuse control_char BSKY_HANDLE\n' ':
' \
  $'  _bsky_cred_ok "${BSKY_APP_PASSWORD:-}" || bsky_refuse control_char BSKY_APP_PASSWORD\n' ':
')"
printf 'BSKY_HANDLE=$%s\nBSKY_APP_PASSWORD=%s\n' "'syn\\001thetic${MARK}'" "$BSKY_PW_FIX" > "$GITWORK/.env"
RUN_CWD="$GITWORK" run_sut - "" -- bash "$M" verify
check "mutant: bsky-setup with its guard removed invokes curl on a control-character handle (RED on the refusal rows)" test "$(curl_calls)" -ge 1
printf 'BSKY_HANDLE=%s\nBSKY_APP_PASSWORD=%s\n' "$BSKY_HANDLE_FIX" "$BSKY_PW_FIX" > "$GITWORK/.env"
M="$(mut_make bsky-setup.sh "password: \$ENV.BSKY_PW}') || {" "password: \$ENV.BSKY_PW}') || true; false && {")"
RUN_CWD="$GITWORK" run_sut - "" SHIM_MODE=jqfail -- bash "$M" verify
check "mutant: bsky-setup ignoring the jq failure reads a failed body build as a good POST (RC 0, no body-build message)" \
  bash -c '[[ "$1" -eq 0 ]] && ! grep -qF "could not build" <<<"$2"' _ "$RC" "$ERR"
M="$(mut_make bsky-setup.sh 'set -euo pipefail' 'set -eu')"
RUN_CWD="$GITWORK" run_sut - "" SHIM_MODE=jqfail -- bash "$M" verify
bsky_jqfail_rows "bsky-setup verify WITHOUT pipefail"
M="$(mut_make bsky-setup.sh '  if ! _bearer_ok "$access_jwt"; then' '  if false; then')"
RUN_CWD="$GITWORK" run_sut - "" SHIM_MODE=badjwt -- bash "$M" verify
check "mutant: bsky-setup with the bearer guard removed sends the hostile token (a getProfile call follows; RED on the refusal rows)" test "$(curl_calls)" -ge 2
check "mutant: bsky-setup with the bearer guard removed: the stdin config carries an injected extra line" test "$(stdin_lines 2)" -gt 1
M="$(mut_make bsky-setup.sh '  export -n BSKY_HANDLE BSKY_APP_PASSWORD' '  :')"
RUN_CWD="$GITWORK" run_sut - "" -- bash "$M" verify
check "mutant: bsky-setup without the un-export hands the .env credentials to curl (RED on the curl-environment row)" not curl_env_lacks BSKY_HANDLE BSKY_APP_PASSWORD
rm -f "$GITWORK/.env"

# 5. discord-setup transport parity: the prologue unset and the TLS-trust arm, each removed in turn.
M="$(mut_make discord-setup.sh $'unset SSLKEYLOGFILE CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR CURL_HOME \\\n      HOSTALIASES LOCALDOMAIN RES_OPTIONS\n' $':\n')"
RUN_CWD="$GITWORK" run_sut - "" "${DS_ENV[@]}" "${TLS_ENV[@]}" -- bash "$M" discover-guilds
check "mutant: discord-setup without the prologue unset lets CURL_CA_BUNDLE etc. reach curl (RED on the curl-environment row)" \
  not curl_env_lacks CURL_CA_BUNDLE SSL_CERT_FILE SSL_CERT_DIR SSLKEYLOGFILE CURL_HOME
M="$(mut_make discord-setup.sh '"$curl_exit" == "60" ||' '"$curl_exit" == "99" ||')"
RUN_CWD="$GITWORK" run_sut - "" "${DS_ENV[@]}" SHIM_MODE=fail60 -- bash "$M" validate-token
check "mutant: discord-setup without the TLS-trust arm reports exit 60 as a bare network failure (RED on the exit-60 row)" \
  bash -c '! grep -qF "TLS trust failure" <<<"$1" && grep -qF "Check your network connection" <<<"$1"' _ "$ERR"

# ===================================================================================
# Negative controls: every helper the rows above trust must be able to say NO. Each control feeds
# a helper an input that makes its condition false (a shim or a one-literal SUT mutant) and
# requires the helper to flip, so a helper that quietly became vacuous turns this section RED.
# ===================================================================================
echo "== helper negative controls =="
# no_leak: a refusal that echoes the value
M="$(mut_make discord-setup.sh 'The value is not shown." >&2' 'The value is ${DISCORD_BOT_TOKEN_INPUT}." >&2')"
disc_bad_val newline
RUN_CWD="$GITWORK" run_sut - "" "DISCORD_BOT_TOKEN_INPUT=$BAD_VAL" -- bash "$M" validate-token
check "negctl: no_leak is false when the refusal echoes the value" not no_leak
# no_diag: a real transport failure prints the diagnostic marker
RUN_CWD="$GITWORK" run_sut - "" "${DS_ENV[@]}" SHIM_MODE=fail7 -- bash "$DISCORD_SETUP" validate-token
check "negctl: no_diag is false when the SOLEUR_TRANSPORT_DIAG line is printed" not no_diag
# refusal_line: a refusal that omits the marker, and a marker with the wrong reason / script
M="$(mut_make discord-setup.sh $'  printf \'SOLEUR_CREDENTIAL_REFUSED script=%s reason=token_shape\\n\' "$SOLEUR_TRANSPORT_SCRIPT" >&2\n' $'  :\n')"
RUN_CWD="$GITWORK" run_sut - "" "DISCORD_BOT_TOKEN_INPUT=$BAD_VAL" -- bash "$M" validate-token
check "negctl: refusal_line is false when the marker line is omitted" not refusal_line discord-setup.sh
RUN_CWD="$GITWORK" run_sut - "" "DISCORD_BOT_TOKEN_INPUT=$BAD_VAL" -- bash "$DISCORD_SETUP" validate-token
check "negctl: refusal_line is false for a different reason" not refusal_line discord-setup.sh control_char
check "negctl: refusal_line is false for a different script name" not refusal_line bsky-setup.sh
check "negctl: refusal_line is true for the real marker (control)" refusal_line discord-setup.sh
# jq_others_env_clean: the function-scope export mutant (above) is the dirty input
M="$(mut_make bsky-community.sh $'  local req_body\n' $'  local req_body\n  export BSKY_ID="$BSKY_HANDLE" BSKY_PW="$BSKY_APP_PASSWORD"\n')"
run_sut - "" "${BC_ENV[@]}" -- bash "$M" create-session
check "negctl: jq_others_env_clean is false when a non-writer jq child inherits the names" not jq_others_env_clean
# stdin_lines: a two-line stdin config
M="$(mut_make discord-community.sh $'printf \'header = "Authorization: Bot %s"\\n\' "$DISCORD_BOT_TOKEN")' $'printf \'header = "Authorization: Bot %s"\\nheader = "X-Extra: 1"\\n\' "$DISCORD_BOT_TOKEN")')"
run_sut - "" "${DC_ENV[@]}" -- bash "$M" guild-info
check "negctl: stdin_lines counts two lines for a two-line config" test "$(stdin_lines 1)" -eq 2
check "negctl: the one-line-config row would be RED for a two-line config" not test "$(stdin_lines 1)" -eq 1
# argv_first3: a call that drops --disable
M="$(mut_make discord-community.sh "curl --disable --noproxy '*' -s -w" "curl --noproxy '*' -s -w")"
run_sut - "" "${DC_ENV[@]}" -- bash "$M" guild-info
check "negctl: argv_first3 no longer reads '--disable --noproxy *' when --disable is dropped" not test "$(argv_first3 1)" = "--disable --noproxy *"
# argv_absent / jq_argv_absent: FALSE when nothing ran (a refused run records no argv)
RUN_CWD="$GITWORK" run_sut - "" "DISCORD_BOT_TOKEN_INPUT=$BAD_VAL" -- bash "$DISCORD_SETUP" validate-token
check "negctl: argv_absent is false when curl never ran (no argv file)" not argv_absent "$DISC_TOK"
check "negctl: jq_argv_absent is false when jq never ran (no jq argv file)" not jq_argv_absent "$BSKY_PW_FIX"
check "negctl: curl_env_lacks is false when curl never ran" not curl_env_lacks CURL_CA_BUNDLE

# rc1_refusal: the marker is on stderr but the exit code is NOT 1 (a refusal that exits 0 or 3 must not read as one)
M="$(mut_make discord-community.sh $'The value is not shown." >&2\n  exit 1' $'The value is not shown." >&2\n  exit 0')"
disc_bad_val newline
run_sut - "" "DISCORD_BOT_TOKEN=$BAD_VAL" "DISCORD_GUILD_ID=$GUILD" -- bash "$M" guild-info
check "negctl: rc1_refusal is false when the marker is present but the refusal exits 0 (discord-community 1->0)" \
  bash -c '[[ "$1" -eq 0 ]] && grep -qxF "SOLEUR_CREDENTIAL_REFUSED script=discord-community.sh reason=token_shape" <<<"$2"' _ "$RC" "$ERR"
check "negctl: rc1_refusal is false for that exit-0 refusal" not rc1_refusal discord-community.sh
M="$(mut_make bsky-community.sh $'The value is not shown." >&2\n  exit 1' $'The value is not shown." >&2\n  exit 3')"
run_sut - "" "BSKY_HANDLE=$BAD_HANDLE" "BSKY_APP_PASSWORD=$BSKY_PW_FIX" -- bash "$M" create-session
check "negctl: the bsky exit-3 refusal mutant keeps the marker and returns 3" \
  bash -c '[[ "$1" -eq 3 ]] && grep -qxF "SOLEUR_CREDENTIAL_REFUSED script=bsky-community.sh reason=control_char" <<<"$2"' _ "$RC" "$ERR"
check "negctl: rc1_refusal is false when the marker is present but the refusal exits 3 (bsky 1->3)" not rc1_refusal bsky-community.sh control_char
run_sut - "" "BSKY_HANDLE=$BAD_HANDLE" "BSKY_APP_PASSWORD=$BSKY_PW_FIX" -- bash "$BSKY_COMMUNITY" create-session
check "negctl: rc1_refusal is true for the real refusal (control)" rc1_refusal bsky-community.sh control_char
# bsky_field_line: the human line names the wrong field, or names the other field too
check "negctl: bsky_field_line is true when the line names the refused field only (control)" bsky_field_line BSKY_HANDLE BSKY_APP_PASSWORD
check "negctl: bsky_field_line is false when the line names a different field than the one expected" not bsky_field_line BSKY_APP_PASSWORD BSKY_HANDLE
check "negctl: bsky_field_line is false when the other field also appears on stderr" not bsky_field_line BSKY_HANDLE BSKY_HANDLE
# jq_recording_ok / jq_argv_has: jq never ran (a refused run), and a run whose jq argv lacks the value
check "negctl: jq_recording_ok is false when jq never ran (refused credential, nothing recorded)" not jq_recording_ok
check "negctl: jq_argv_has is false when jq never ran" not jq_argv_has "$BSKY_HANDLE_FIX"
run_sut - "" "${BC_ENV[@]}" -- bash "$BSKY_COMMUNITY" create-session
check "negctl: jq_recording_ok is true for a real createSession run (control)" jq_recording_ok
check "negctl: jq_argv_has is false for a value that is not on any jq argv (the password, in a real run)" not jq_argv_has "$BSKY_PW_FIX"
M="$(mut_make bsky-community.sh \
  $'BSKY_ID="$BSKY_HANDLE" BSKY_PW="$BSKY_APP_PASSWORD" \\\n    jq -n \'{identifier: $ENV.BSKY_ID, password: $ENV.BSKY_PW}\'' \
  $'jq -n --arg id "$BSKY_HANDLE" --arg pw "$BSKY_APP_PASSWORD" \'{identifier: $id, password: $pw}\'')"
run_sut - "" "${BC_ENV[@]}" -- bash "$M" create-session
check "negctl: jq_recording_ok is false when no jq call reads \$ENV.BSKY_PW (the --arg mutant)" not jq_recording_ok

# --- transport-block drift guard ------------------------------------------------------------
# discord-setup.sh carries a verbatim copy of discord-community.sh's transport block. Extract both
# (from the `unset SSLKEYLOGFILE ...` line through the closing brace of report_transport_failure)
# and require byte equality, normalising ONLY the two per-script assignments.
echo "== transport-block drift =="
transport_block() { # <file>
  awk '/^unset SSLKEYLOGFILE /{p=1} p{print} p && /^report_transport_failure\(\) \{/{r=1} r && /^}$/{exit}' "$1" |
    sed -e 's/^SOLEUR_TRANSPORT_SCRIPT=.*/SOLEUR_TRANSPORT_SCRIPT=<normalised>/' \
        -e 's/^SOLEUR_TRANSPORT_PLATFORM=.*/SOLEUR_TRANSPORT_PLATFORM=<normalised>/'
}
DRIFT="$SANDBOX/drift"
mkdir -p "$DRIFT"
transport_block "$DISCORD_COMMUNITY" > "$DRIFT/community.blk"
transport_block "$DISCORD_SETUP" > "$DRIFT/setup.blk"
blk_sane() { # <block-file>: non-empty, spans the whole block, and is long enough not to be a truncated extraction
  [[ -s "$1" ]] && grep -qxF 'report_transport_failure() {' "$1" && grep -qF 'echo "Check your network connection and try again." >&2' "$1" \
    && [[ "$(wc -l < "$1")" -ge 80 ]]
}
check "drift: the discord-community.sh transport block extracted whole (non-vacuous)" blk_sane "$DRIFT/community.blk"
check "drift: the discord-setup.sh transport block extracted whole (non-vacuous)" blk_sane "$DRIFT/setup.blk"
check "drift: the discord-setup.sh transport block is byte-identical to discord-community.sh's (bar the two per-script literals)" \
  cmp -s "$DRIFT/community.blk" "$DRIFT/setup.blk"
# Mutation: one character changed in discord-setup's copy of the block must turn the comparison RED.
sed 's/eight fields, on the saved stdout/eight fieldz, on the saved stdout/' "$DISCORD_SETUP" > "$DRIFT/setup-mut.sh"
check "drift: the one-character mutation landed in the sandbox copy" not cmp -s "$DISCORD_SETUP" "$DRIFT/setup-mut.sh"
transport_block "$DRIFT/setup-mut.sh" > "$DRIFT/setup-mut.blk"
check "drift: a one-character edit to discord-setup's copy makes the comparison RED" not cmp -s "$DRIFT/community.blk" "$DRIFT/setup-mut.blk"
# Normalisation is limited to the two literals: changing them stays GREEN, changing a third literal does not.
sed -e 's/^SOLEUR_TRANSPORT_SCRIPT=.*/SOLEUR_TRANSPORT_SCRIPT="other.sh"/' -e 's/^SOLEUR_TRANSPORT_PLATFORM=.*/SOLEUR_TRANSPORT_PLATFORM="Other"/' "$DISCORD_SETUP" > "$DRIFT/setup-lit.sh"
transport_block "$DRIFT/setup-lit.sh" > "$DRIFT/setup-lit.blk"
check "drift: the two per-script literals are the only normalised difference" cmp -s "$DRIFT/community.blk" "$DRIFT/setup-lit.blk"

# ===================================================================================
# S2 (#9597): the OAuth 1.0a signing key off every argument (lib/hmac-sha1-b64.sh) and the
# write-env value allow-list. All keys and values below are SYNTHESIZED.
# ===================================================================================
# The mutant tree (the "== mutants ==" section above) needs the library beside the mutated scripts.
mkdir -p "$MUT/skills/community/scripts/lib"
[[ -r "$HMAC_LIB" ]] && cp "$HMAC_LIB" "$MUT/skills/community/scripts/lib/"
echo "== hmac-sha1-b64.sh: static contract =="
LIB_CODE="$SANDBOX/hmac-lib.code"
if [[ -r "$HMAC_LIB" ]]; then sed -e '/^[[:space:]]*#/d' "$HMAC_LIB" > "$LIB_CODE"; else : > "$LIB_CODE"; fi
# The function body alone (code lines only): the load-time prologue legitimately has a fallback exit.
LIB_FN="$SANDBOX/hmac-lib.fn"
awk '/^hmac_sha1_b64\(\) \{/{f=1} f{print} f&&/^}/{exit}' "$LIB_CODE" > "$LIB_FN"
lib_fn_has() { local n; n="$(grep -c -e "$1" "$LIB_FN")"; [[ "$n" =~ ^[0-9]+$ && "$n" -ge 1 ]]; }
lib_fn_zero_exit() { local n rc; n="$(grep -cE '(^|[^A-Za-z_])exit([^A-Za-z_]|$)' "$LIB_FN")"; rc=$?; [[ "$rc" -le 1 && "$n" == 0 ]]; }
# lib_zero <ERE>: the pattern compiles (grep rc <= 1) AND matches no CODE line (comments stripped).
lib_zero() { local n rc; n="$(grep -cE -e "$1" "$LIB_CODE")"; rc=$?; [[ "$rc" -le 1 && "$n" == 0 ]]; }
# lib_ones <ERE>: the pattern compiles AND matches exactly one code line.
lib_ones() { local n rc; n="$(grep -cE -e "$1" "$LIB_CODE")"; rc=$?; [[ "$rc" -le 1 && "$n" == 1 ]]; }
# lib_some <ERE>: the pattern compiles AND matches at least one code line.
lib_some() { local n rc; n="$(grep -cE -e "$1" "$LIB_CODE")"; rc=$?; [[ "$rc" -le 1 && "$n" =~ ^[0-9]+$ && "$n" -ge 1 ]]; }
# file_count <fixed-string> <file>: occurrences (lines) in the whole file, comments included.
file_count() { grep -cF -e "$1" -- "$2"; }

check "lib: lib/hmac-sha1-b64.sh exists and is readable" test -r "$HMAC_LIB"
check "lib: defines exactly one function, hmac_sha1_b64" lib_ones '^hmac_sha1_b64\(\) \{'
check "lib: the file defines no other function (one function only)" test "$(grep -cE '^[A-Za-z_][A-Za-z0-9_]*\(\) *\{' "$LIB_CODE")" -eq 1
check "lib: no here-string or heredoc on any code line (they write key-derived data to a temp file on bash < 5.1)" lib_zero '<<'
lib_fn_ctl() { lib_fn_has "return 1" && lib_fn_has "openssl dgst -sha1 -binary"; }
check "lib: the function body is extracted (control: it holds a return and the openssl pipe)" lib_fn_ctl
check "lib: no exit in the function body (a sourced function returns non-zero, the caller decides)" lib_fn_zero_exit
check "lib: the load-time xtrace refusal is the FIRST code line of the file (the lint's prologue rule)" test "$(awk 'NF{print; exit}' "$LIB_CODE")" = 'case "$-" in'
check "lib: no -hmac or -macopt operand anywhere in the code" lib_zero '(-hmac|-macopt)'
check "lib: LC_ALL=C is set (byte semantics)" lib_some 'LC_ALL=C'
check "lib: carries its own xtrace refusal (it can be sourced without the caller's preamble)" lib_some 'case "\$-" in'
check "lib: never prints the credential-refusal marker (the caller decides the exit code and prints)" \
  test "$(file_count SOLEUR_CREDENTIAL_REFUSED "$HMAC_LIB" 2>/dev/null)" = 0
check "lib: static-check controls: a pattern that must match does match (the extractor is not empty)" lib_some 'hmac_sha1_b64'
check "lib: static-check controls: lib_zero says NO for a present token" not lib_zero 'hmac_sha1_b64'
for f_ in "$X_COMMUNITY" "$X_SETUP"; do
  check "$(basename "$f_"): sources lib/hmac-sha1-b64.sh exactly once" test "$(file_count 'lib/hmac-sha1-b64.sh' "$f_")" -eq 1
  check "$(basename "$f_"): no -hmac operand remains" test "$(file_count '-hmac' "$f_")" = 0
  check "$(basename "$f_"): the signing key is passed to the function by NAME (never an expansion)" \
    test "$(file_count 'hmac_sha1_b64 signing_key' "$f_")" -eq 1
done

echo "== hmac-sha1-b64.sh: oracle against openssl dgst -hmac =="
oracle_matrix
check "oracle: the key-length x message matrix ran exactly 32 cases (inner counter)" test "$ORC_LEN" -eq 32
check "oracle: the special-key matrix ran exactly 28 cases (inner counter)" test "$ORC_SPEC" -eq 28
check "oracle: all 7 RFC 2202 vectors ran (inner counter)" test "$ORC_RFC" -eq 7
check "oracle: 67 comparisons in total (inner counter)" test "$ORC_RAN" -eq 67
check "oracle: every comparison equals the reference (keys 0,1,20,63,64,65,96,200 bytes; 6x64; backslash, quote, space; = and %; RFC 2202)" test "$ORC_BAD" -eq 0
# Comparator negative controls: the comparison can say NO, and can say YES.
CTL_NO="$( hmac_sha1_b64() { cat >/dev/null; printf 'AAAAAAAAAAAAAAAAAAAAAAAAAAA='; }; ORC_BAD=0; orc_cmp "ctl-key" "ctl-msg"; printf '%s' "$ORC_BAD" )"
CTL_YES="$( hmac_sha1_b64() { local k="${!1}"; openssl dgst -sha1 -hmac "$k" -binary | base64; }; ORC_BAD=0; orc_cmp "ctl-key" "ctl-msg"; printf '%s' "$ORC_BAD" )"
check "negctl: the oracle comparison counts a wrong digest as a mismatch" test "$CTL_NO" = 1
check "negctl: the oracle comparison counts the reference digest as a match" test "$CTL_YES" = 0
# Mutants of the library: each must turn the oracle RED.
mut_lib() { # <tag> <from> <to> -> path of the mutant library ('' when the literal is absent)
  local text out="$SANDBOX/mutlib.$1.sh"
  [[ -r "$HMAC_LIB" ]] || return 0
  text="$(cat "$HMAC_LIB"; printf x)"; text="${text%x}"
  if [[ "$text" != *"$2"* ]]; then echo "FATAL: lib mutation did not land: '${2:0:50}'" >&2; return 0; fi
  printf '%s' "${text/"$2"/"$3"}" > "$out"
  printf '%s' "$out"
}
# shellcheck disable=SC1090
orc_bad_of() { ( source "$1" 2>/dev/null && oracle_matrix && printf '%s' "$ORC_BAD" ) || true; }
M_LIB="$(mut_lib noprehash '> 128 ' '> 12800 ')"
check "mutant: a library that never pre-hashes a key longer than 64 bytes is RED on the oracle (65, 96, 200 byte keys and RFC 2202 cases 6-7)" \
  test "$(orc_bad_of "$M_LIB")" -ge 1
M_LIB="$(mut_lib ipad '^ 54' '^ 55')"
check "mutant: a library with a wrong inner pad is RED on the oracle" test "$(orc_bad_of "$M_LIB")" -ge 1
M_LIB="$(mut_lib opad '^ 92' '^ 93')"
check "mutant: a library with a wrong outer pad is RED on the oracle" test "$(orc_bad_of "$M_LIB")" -ge 1

echo "== hmac-sha1-b64.sh: argv and environment hygiene (recording openssl/od/tr/base64 shims) =="
# The shims record argv and the NAMES of the variables the child inherited, then exec the REAL binary
# (a fake that returned a canned digest would agree with the consumer's own reading of the contract).
REC="$SANDBOX/rec"
mkdir -p "$REC"
for t_ in openssl od tr base64; do
  rp_="$(command -v "$t_")" || { echo "FAIL: $t_ not found" >&2; exit 1; }
  cat > "$REC/$t_" <<'SHIM'
#!/bin/bash
d="$MOCK_DIR"; b="${0##*/}"
printf '%s\0' "$@" > "$d/rec.$b.$$"
compgen -e > "$d/recenv.$b.$$"
exec "@REAL@" "$@"
SHIM
  sed -i "s|@REAL@|$rp_|" "$REC/$t_"
  chmod +x "$REC/$t_"
done
rec_clear() { rm -f "$MOCK"/rec.* "$MOCK"/recenv.*; }
rec_count() { local n=0 f; for f in "$MOCK"/rec."$1".*; do [[ -e "$f" ]] && n=$((n + 1)); done; printf '%s' "$n"; }
# rec_argv_absent <needle>: some tool was recorded AND the needle is on no recorded argv.
rec_argv_absent() {
  local f seen=0
  for f in "$MOCK"/rec.*; do
    [[ -e "$f" ]] || continue
    seen=$((seen + 1))
    grep -aqF -e "$1" -- "$f" && return 1
  done
  (( seen >= 1 ))
}
# rec_env_clean <name|prefix*>...: some tool was recorded AND none of these names is in any recorded environment.
rec_env_clean() {
  local f n seen=0
  for f in "$MOCK"/recenv.*; do
    [[ -e "$f" ]] || continue
    seen=$((seen + 1))
    for n in "$@"; do
      if [[ "$n" == *'*' ]]; then
        grep -q -e "^${n%\*}" -- "$f" && return 1
      else
        grep -qxF -e "$n" -- "$f" && return 1
      fi
    done
  done
  (( seen >= 1 ))
}
# rec_env_leaks <name|prefix*>...: at least one of these names IS in some recorded environment (the mutant rows).
rec_env_leaks() {
  local f n
  for f in "$MOCK"/recenv.*; do
    [[ -e "$f" ]] || continue
    for n in "$@"; do
      if [[ "$n" == *'*' ]]; then
        grep -q -e "^${n%\*}" -- "$f" && return 0
      else
        grep -qxF -e "$n" -- "$f" && return 0
      fi
    done
  done
  return 1
}
# rec_argv_has <needle>: the needle IS on some recorded argv (the mutant rows).
rec_argv_has() {
  local f
  for f in "$MOCK"/rec.*; do
    [[ -e "$f" ]] || continue
    grep -aqF -e "$1" -- "$f" && return 0
  done
  return 1
}
# rec_argv_absent_all <needle>...: every needle is absent (and something was recorded).
rec_argv_absent_all() { local n; for n in "$@"; do rec_argv_absent "$n" || return 1; done; }
# rec_dgst_exact <n>: exactly n openssl calls with the argv `dgst -sha1 -binary`; every other openssl call is `rand -hex 16`.
rec_dgst_exact() {
  local f n=0 a
  for f in "$MOCK"/rec.openssl.*; do
    [[ -e "$f" ]] || continue
    a="$(tr '\0' ' ' < "$f")"
    case "$a" in
      'dgst -sha1 -binary ') n=$((n + 1)) ;;
      'rand -hex 16 ') ;;
      *) return 1 ;;
    esac
  done
  [[ "$n" -eq "$1" ]]
}

# --- the function under `set -a`: no key-derived name reaches any child's environment ---------
SETA_KEY="$(oc_rep 20 'k3y&=%')"
SETA_MSG='GET&https%3A%2F%2Fapi.x.com%2F2%2Fusers%2Fme&a%3Db'
SETA_WANT="$(printf '%s' "$SETA_MSG" | openssl dgst -sha1 -hmac "$SETA_KEY" -binary | base64)"
SETA_OUT="" SETA_RC=0
seta_run() { # <lib-file>
  rec_clear
  # shellcheck disable=SC1090
  SETA_OUT="$( set -a; export MOCK_DIR="$MOCK"; PATH="$REC:$PATH"; source "$1"; HM_KEY="$SETA_KEY"; printf '%s' "$SETA_MSG" | hmac_sha1_b64 HM_KEY )"
  SETA_RC=$?
}
seta_run "$HMAC_LIB"
check "set -a: the digest still equals the openssl reference" bash -c '[[ -n "$1" && "$1" == "$2" ]]' _ "$SETA_OUT" "$SETA_WANT"
check "set -a: exit 0" test "$SETA_RC" -eq 0
check "set -a: exactly two openssl calls were recorded (inner and outer digest), both with the argv 'dgst -sha1 -binary'" rec_dgst_exact 2
check "set -a: the od, tr and base64 children were recorded too (the shims are on the path)" \
  bash -c '[[ "$1" -ge 1 && "$2" -ge 1 && "$3" -ge 1 ]]' _ "$(rec_count od)" "$(rec_count tr)" "$(rec_count base64)"
check "set -a: the key bytes are on no recorded argv" rec_argv_absent "$SETA_KEY"
check "set -a: HM_KEY and every _hs_* name are absent from every child's environment" rec_env_clean HM_KEY '_hs_*'
check "set -a: control, allexport does export a plain assignment (the mechanism is real)" \
  bash -c '[[ "$( set -a; HM_KEY=x; compgen -e )" == *HM_KEY* ]]'
# Mutants: dropping the un-export or the allexport-off turns the environment row RED.
M_LIB="$(mut_lib exportn 'export -n -- "$1"' ':')"
seta_run "$M_LIB"
check "mutant: a library that does not un-export the key variable leaks HM_KEY into a child environment (RED on the set -a row)" rec_env_leaks HM_KEY
M_LIB="$(mut_lib allexport 'set +a' ':')"
seta_run "$M_LIB"
check "mutant: a library that leaves allexport on exports its own locals (RED on the set -a row)" rec_env_leaks '_hs_*'

# --- failure semantics ----------------------------------------------------------------------
HF_KEY="SYNTH-hf-key-0001"
HF_OUT="$( HM_KEY="$HF_KEY" bash -c 'source "$1"; set -x; printf m | hmac_sha1_b64 HM_KEY; echo "rc=$?"' _ "$HMAC_LIB" 2>"$SANDBOX/hf.err" )"
HF_ERR="$(cat "$SANDBOX/hf.err")"
check "xtrace: switched on after loading, the function refuses (rc 78) and prints no digest" test "$HF_OUT" = "rc=78"
check "xtrace: the key reaches neither stdout nor the trace on stderr" bash -c '[[ "$3" != *"$1"* && "$4" != *"$1"* ]]' _ "$HF_KEY" x "$HF_OUT" "$HF_ERR"
check "xtrace: the refusal is not the credential-refusal marker" bash -c '[[ "$1" != *SOLEUR_CREDENTIAL_REFUSED* ]]' _ "$HF_ERR"
HF_LOAD="$( HM_KEY="$HF_KEY" bash -xc 'source "$1"; echo "src=$? defined=$(type -t hmac_sha1_b64)"' _ "$HMAC_LIB" 2>"$SANDBOX/hf2.err" )"
HF_ERR2="$(cat "$SANDBOX/hf2.err")"
check "xtrace: sourcing the library under bash -x refuses at load time (return 78) and defines nothing" bash -c '[[ "$1" == *"src=78 defined=" ]]' _ "$HF_LOAD"
check "xtrace: the load-time refusal is on STDOUT (agent runtimes swallow stderr) and names the cause" bash -c '[[ "$1" == *"Refusing to load the HMAC helper"* ]]' _ "$HF_LOAD"
check "xtrace: the key is in neither stream of the load-time refusal" bash -c '[[ "$1" != *"$3"* && "$2" != *"$3"* ]]' _ "$HF_LOAD" "$HF_ERR2" "$HF_KEY"
NOPATH="$SANDBOX/emptypath"; mkdir -p "$NOPATH"
# shellcheck disable=SC2034
HF_OUT="$( PATH="$NOPATH"; HM_KEY="$HF_KEY"; printf m | hmac_sha1_b64 HM_KEY 2>/dev/null )"; HF_RC=$?
check "failure: no openssl on PATH -> non-zero and no digest" bash -c '[[ "$1" -ne 0 && -z "$2" ]]' _ "$HF_RC" "$HF_OUT"
HF_OUT="$( printf m | hmac_sha1_b64 HM_NEVER_SET 2>/dev/null )"; HF_RC=$?
check "failure: an unset key variable -> non-zero and no digest (an unset key is not an empty key)" bash -c '[[ "$1" -ne 0 && -z "$2" ]]' _ "$HF_RC" "$HF_OUT"
HF_OUT="$( printf m | hmac_sha1_b64 '' 2>/dev/null )"; HF_RC=$?
check "failure: an empty variable name -> non-zero and no digest" bash -c '[[ "$1" -ne 0 && -z "$2" ]]' _ "$HF_RC" "$HF_OUT"
rm -f "$SANDBOX/SENT.sub"
HF_OUT="$( printf m | hmac_sha1_b64 "a[\$(touch $SANDBOX/SENT.sub)]" 2>/dev/null )"; HF_RC=$?
check "failure: a variable name with a subscript command substitution is refused, and nothing runs" \
  bash -c '[[ "$1" -ne 0 && -z "$2" && ! -e "$3" ]]' _ "$HF_RC" "$HF_OUT" "$SANDBOX/SENT.sub"
HF_OUT="$( HM_KEY="$HF_KEY" bash -c 'source "$1"; printf m | hmac_sha1_b64 HM_KEY' _ "$HMAC_LIB" 2>/dev/null )"; HF_RC=$?
check "failure: control, the same call without -x succeeds and prints a 28-character digest" bash -c '[[ "$1" -eq 0 && "${#2}" -eq 28 ]]' _ "$HF_RC" "$HF_OUT"

# --- full signed requests through the real scripts -----------------------------------------
echo "== OAuth 1.0a signing through the scripts (recording shims) =="
# The OAuth signing key is urlencode(consumer secret) & urlencode(token secret) (RFC 5849 3.4.2). The
# oracle encodes with its OWN encoder (t_urlenc, below), so a SUT that drops the encoding disagrees
# whenever a secret holds a reserved character. SIGN_S / SIGN_T name the secrets of the run under
# check; the default fixtures are unreserved characters, where the encoding is the identity, so the
# reserved-character run further down is what pins it.
SIGN_S="$X_SECRET" SIGN_T="$X_TOKSECRET"
# The oracle's percent-encoder is NOT a copy of the script's `urlencode` (a line-for-line copy agreed
# with it on a multi-byte character and both disagreed with the RFC): it is Python's, over the UTF-8
# BYTES of the string, leaving exactly the RFC 5849 3.6 unreserved set (ALPHA DIGIT - . _ ~).
t_urlenc() { python3 -c 'import sys, urllib.parse; sys.stdout.write(urllib.parse.quote(sys.argv[1], safe=""))' "$1"; }
check "oracle encoder: the RFC 5849 reserved set and a space encode per the RFC (hard-coded expectation, not the SUT's output)" \
  test "$(t_urlenc 'a b+c/d=e&f~g%h:i')" = 'a%20b%2Bc%2Fd%3De%26f~g%25h%3Ai'
check "oracle encoder: a multi-byte character encodes as its UTF-8 BYTES (%C3%A9%E2%82%AC for e-acute and euro), not as code points" \
  test "$(t_urlenc 'é€')" = '%C3%A9%E2%82%AC'
check "oracle encoder: an empty string encodes to an empty string" test -z "$(t_urlenc '')"
x_signkey() { printf '%s&%s' "$(t_urlenc "$SIGN_S")" "$(t_urlenc "$SIGN_T")"; }
x_keyhex() { printf '%s' "$SIGN_S" | od -An -tx1 | tr -d ' \n'; }
# x_sig_ok <n> <METHOD>: the oauth_signature on call n equals an INDEPENDENT recomputation from the
# recorded header, URL and query (openssl dgst -hmac over the synthetic key).
x_sig_ok() {
  local n="$1" method="$2" raw hdr url w base query="" ck nonce ts tok sig params want base_str
  local -a a=() lines=()
  [[ -s "$MOCK/stdin.$n" && -s "$MOCK/argv.$n" ]] || return 1
  raw="$(stdin_text "$n")"; hdr="${raw#header = \"}"; hdr="$(cfg_decode "${hdr%\"}")"
  mapfile -d '' -t a < "$MOCK/argv.$n"
  url=""; for w in "${a[@]}"; do [[ "$w" == http*://* ]] && url="$w"; done
  [[ -n "$url" ]] || return 1
  base="${url%%\?*}"; [[ "$url" == *\?* ]] && query="${url#*\?}"
  oauth_field() { [[ "$hdr" =~ $1=\"([^\"]*)\" ]] && printf '%s' "${BASH_REMATCH[1]}"; }
  ck="$(oauth_field oauth_consumer_key)"; nonce="$(oauth_field oauth_nonce)"; ts="$(oauth_field oauth_timestamp)"
  tok="$(oauth_field oauth_token)"; sig="$(oauth_field oauth_signature)"
  [[ -n "$ck" && -n "$nonce" && -n "$ts" && -n "$tok" && -n "$sig" ]] || return 1
  lines=("oauth_consumer_key=$ck" "oauth_nonce=$nonce" "oauth_signature_method=HMAC-SHA1" "oauth_timestamp=$ts" "oauth_token=$tok" "oauth_version=1.0")
  if [[ -n "$query" ]]; then
    local pair
    while IFS= read -r pair; do
      [[ -n "$pair" ]] && lines+=("$(t_urlenc "${pair%%=*}")=$(t_urlenc "${pair#*=}")")
    done < <(printf '%s\n' "${query//&/$'\n'}")
  fi
  params="$(printf '%s\n' "${lines[@]}" | LC_ALL=C sort | paste -sd '&' -)"
  base_str="${method}&$(t_urlenc "$base")&$(t_urlenc "$params")"
  want="$(printf '%s' "$base_str" | openssl dgst -sha1 -hmac "$(x_signkey)" -binary | base64)"
  [[ -n "$want" && "$(t_urlenc "$want")" == "$sig" ]]
}
x_hdr_shape() {
  local raw; raw="$(stdin_text "$1")"
  [[ "$raw" == 'header = "Authorization: OAuth oauth_consumer_key=\"'* && "$raw" == *'oauth_signature_method=\"HMAC-SHA1\"'* && "$raw" == *'oauth_version=\"1.0\""' ]]
}
x_rec_rows() { # <label> <n> <method>
  local label="$1" n="$2" method="$3"
  check "$label: header is the same Authorization: OAuth structure on curl's stdin config" x_hdr_shape "$n"
  check "$label: the signature equals an independent recomputation (openssl dgst -hmac over the synthetic key)" x_sig_ok "$n" "$method"
  check "$label: exactly two dgst calls, each with the argv 'dgst -sha1 -binary'" rec_dgst_exact 2
  check "$label: no -hmac operand on any recorded argv (openssl, od, tr, base64)" rec_argv_absent "-hmac"
  check "$label: no -macopt operand on any recorded argv" rec_argv_absent "-macopt"
  check "$label: neither secret, the full signing key nor the key's hex is on any recorded argv" \
    rec_argv_absent_all "$SIGN_S" "$SIGN_T" "$(x_signkey)" "$(x_keyhex)"
  check "$label: signing_key and _hs_* are absent from every recorded child environment" rec_env_clean signing_key '_hs_*'
}
rec_clear
run_sut "$REC" "" "${X_ENV[@]}" -- bash "$X_COMMUNITY" fetch-metrics
check "x-community fetch-metrics with the recording shims: exit 0, one curl call" bash -c '[[ "$1" -eq 0 && "$2" -eq 1 ]]' _ "$RC" "$(curl_calls)"
x_rec_rows "x-community fetch-metrics (GET, query signed)" 1 GET
rec_clear
run_sut "$REC" "" "${X_ENV[@]}" -- bash "$X_COMMUNITY" post-tweet "synthetic post"
check "x-community post-tweet with the recording shims: exit 0, one curl call" bash -c '[[ "$1" -eq 0 && "$2" -eq 1 ]]' _ "$RC" "$(curl_calls)"
x_rec_rows "x-community post-tweet (POST)" 1 POST
rec_clear
RUN_CWD="$GITWORK" run_sut "$REC" "" "${X_ENV[@]}" -- bash "$X_SETUP" validate-credentials
check "x-setup validate-credentials with the recording shims: exit 0, one curl call" bash -c '[[ "$1" -eq 0 && "$2" -eq 1 ]]' _ "$RC" "$(curl_calls)"
x_rec_rows "x-setup validate-credentials (GET)" 1 GET
# Mutant: the old argv spelling comes back in x-community -> the argv rows go RED.
M="$(mut_make x-community.sh 'hmac_sha1_b64 signing_key' 'openssl dgst -sha1 -hmac "$signing_key" -binary | base64')"
rec_clear
run_sut "$REC" "" "${X_ENV[@]}" -- bash "$M" fetch-metrics
check "mutant: x-community with the -hmac spelling restored puts the signing key on openssl's argv (RED on the argv rows)" rec_argv_has "$X_TOKSECRET"
check "mutant: that control is RED because the key is there, not because nothing ran (a curl call and an openssl call were recorded)" \
  bash -c '[[ "$1" -eq 1 && "$2" -ge 2 ]]' _ "$(curl_calls)" "$(rec_count openssl)"

# --- reserved characters in the secrets: the signing key is urlencoded (RFC 5849 3.4.2) ------------
# The fixtures above are unreserved characters, where urlencode is the identity, so a SUT that dropped
# the encoding would still match. These secrets hold + / = & space ~ and a percent escape.
echo "== OAuth 1.0a signing key with reserved characters in the secrets =="
XR_S='Sec+ret/with=eq&amp 02'
XR_T='tok~sec%41:x+y/z='
XR_ENV=("X_API_KEY=$X_KEY" "X_API_SECRET=$XR_S" "X_ACCESS_TOKEN=$X_TOK" "X_ACCESS_TOKEN_SECRET=$XR_T" X_ALLOW_POST=true)
SIGN_S="$XR_S" SIGN_T="$XR_T"
check "reserved fixture: the encoded key differs from the raw one (the encoding is not the identity here)" \
  bash -c '[[ "$1" != "$2&$3" ]]' _ "$(x_signkey)" "$XR_S" "$XR_T"
rec_clear
run_sut "$REC" "" "${XR_ENV[@]}" -- bash "$X_COMMUNITY" fetch-metrics
check "reserved secrets, x-community fetch-metrics: exit 0, one curl call" bash -c '[[ "$1" -eq 0 && "$2" -eq 1 ]]' _ "$RC" "$(curl_calls)"
check "reserved secrets, x-community: the signature equals the oracle over the RFC 5849 encoded key" x_sig_ok 1 GET
check "reserved secrets, x-community: neither raw secret, the encoded key nor its hex is on any recorded argv" \
  rec_argv_absent_all "$XR_S" "$XR_T" "$(x_signkey)" "$(x_keyhex)"
rec_clear
RUN_CWD="$GITWORK" run_sut "$REC" "" "${XR_ENV[@]}" -- bash "$X_SETUP" validate-credentials
check "reserved secrets, x-setup validate-credentials: exit 0, one curl call" bash -c '[[ "$1" -eq 0 && "$2" -eq 1 ]]' _ "$RC" "$(curl_calls)"
check "reserved secrets, x-setup: the signature equals the oracle over the RFC 5849 encoded key" x_sig_ok 1 GET
# Mutants: the encoding dropped from the key in either script is invisible on the unreserved fixtures and RED here.
M="$(mut_make x-community.sh '"$(urlencode "${X_API_SECRET}")&$(urlencode "${X_ACCESS_TOKEN_SECRET}")"' '"${X_API_SECRET}&${X_ACCESS_TOKEN_SECRET}"')"
run_sut "$REC" "" "${XR_ENV[@]}" -- bash "$M" fetch-metrics
check "mutant: x-community with the key left unencoded is RED on the reserved run (a request was signed and the signature disagrees)" \
  bash -c '[[ "$1" -eq 1 ]]' _ "$(curl_calls)"
check "mutant: x-community with the key left unencoded: the oracle rejects its signature" not x_sig_ok 1 GET
SIGN_S="$X_SECRET" SIGN_T="$X_TOKSECRET"
run_sut "$REC" "" "${X_ENV[@]}" -- bash "$M" fetch-metrics
check "mutant control: the same unencoded-key mutant is GREEN on the unreserved fixtures (why the reserved run is needed)" x_sig_ok 1 GET
SIGN_S="$XR_S" SIGN_T="$XR_T"
M="$(mut_make x-setup.sh '"$(urlencode "${X_API_SECRET}")&$(urlencode "${X_ACCESS_TOKEN_SECRET}")"' '"${X_API_SECRET}&${X_ACCESS_TOKEN_SECRET}"')"
RUN_CWD="$GITWORK" run_sut "$REC" "" "${XR_ENV[@]}" -- bash "$M" validate-credentials
check "mutant: x-setup with the key left unencoded is RED on the reserved run (a request was signed and the signature disagrees)" \
  bash -c '[[ "$1" -eq 1 ]]' _ "$(curl_calls)"
check "mutant: x-setup with the key left unencoded: the oracle rejects its signature" not x_sig_ok 1 GET
SIGN_S="$X_SECRET" SIGN_T="$X_TOKSECRET"

# --- multi-byte characters in the secrets: the key is encoded as its UTF-8 BYTES (RFC 5849 3.6) -----
# The script runs here under a UTF-8 locale (env -i would otherwise leave it in the C locale, where a
# character-wise loop is byte-wise by accident). The oracle's encoder is Python's, over the bytes.
echo "== OAuth 1.0a signing key with multi-byte characters in the secrets =="
XU_LOC=C.UTF-8
XU_S='Sécret€one' XU_T='tökén€two'
XU_ENV=("LC_ALL=$XU_LOC" "X_API_KEY=$X_KEY" "X_API_SECRET=$XU_S" "X_ACCESS_TOKEN=$X_TOK" "X_ACCESS_TOKEN_SECRET=$XU_T" X_ALLOW_POST=true)
check "multi-byte canary: the $XU_LOC locale is installed here and counts one character for e-acute (the row is not vacuous)" \
  bash -c '[[ "$(LC_ALL="$1" bash -c "echo \${#1}" _ "é")" == 1 ]]' _ "$XU_LOC"
SIGN_S="$XU_S" SIGN_T="$XU_T"
check "multi-byte fixture: the encoded key holds the UTF-8 byte escapes, not code points (%C3%A9, not %E9)" \
  bash -c '[[ "$1" == *"%C3%A9"* && "$1" != *"%E9"* ]]' _ "$(x_signkey)"
rec_clear
run_sut "$REC" "" "${XU_ENV[@]}" -- bash "$X_COMMUNITY" fetch-metrics
check "multi-byte secrets, x-community fetch-metrics: exit 0, one curl call" bash -c '[[ "$1" -eq 0 && "$2" -eq 1 ]]' _ "$RC" "$(curl_calls)"
check "multi-byte secrets, x-community: the signature equals the oracle over the byte-encoded key" x_sig_ok 1 GET
rec_clear
RUN_CWD="$GITWORK" run_sut "$REC" "" "${XU_ENV[@]}" -- bash "$X_SETUP" validate-credentials
check "multi-byte secrets, x-setup validate-credentials: exit 0, one curl call" bash -c '[[ "$1" -eq 0 && "$2" -eq 1 ]]' _ "$RC" "$(curl_calls)"
check "multi-byte secrets, x-setup: the signature equals the oracle over the byte-encoded key" x_sig_ok 1 GET
# Mutants: the code-point encoding comes back (no LC_ALL=C in urlencode) -> the oracle disagrees.
M="$(mut_make x-community.sh 'urlencode() {
  local LC_ALL=C
' 'urlencode() {
')"
run_sut "$REC" "" "${XU_ENV[@]}" -- bash "$M" fetch-metrics
check "mutant: x-community urlencode without LC_ALL=C still signs and sends one request (exit 0)" bash -c '[[ "$1" -eq 0 && "$2" -eq 1 ]]' _ "$RC" "$(curl_calls)"
check "mutant: x-community urlencode without LC_ALL=C encodes a multi-byte secret by code point: the oracle rejects its signature" not x_sig_ok 1 GET
M="$(mut_make x-setup.sh 'urlencode() {
  local LC_ALL=C
' 'urlencode() {
')"
RUN_CWD="$GITWORK" run_sut "$REC" "" "${XU_ENV[@]}" -- bash "$M" validate-credentials
check "mutant: x-setup urlencode without LC_ALL=C still signs and sends one request (exit 0)" bash -c '[[ "$1" -eq 0 && "$2" -eq 1 ]]' _ "$RC" "$(curl_calls)"
check "mutant: x-setup urlencode without LC_ALL=C encodes a multi-byte secret by code point: the oracle rejects its signature" not x_sig_ok 1 GET
SIGN_S="$X_SECRET" SIGN_T="$X_TOKSECRET"

# --- an inherited exported function named hmac_sha1_b64 must not stand in for the vetted library ------
echo "== x-community.sh: an inherited hmac_sha1_b64 function =="
# The stand-in drains its stdin (builtins only) before answering: a stand-in that exits at once races the
# caller's `printf | hmac_sha1_b64` (SIGPIPE under `pipefail` when the writer is slower than the exit),
# which flakes the "still sends one request" rows on a loaded host.
IMPFN='BASH_FUNC_hmac_sha1_b64%%=() { local l; while IFS= read -r l || [ -n "$l" ]; do :; done; echo IMPORTED; }'
check "inherited-function canary: bash imports that exported function from the environment here (the row is not vacuous)" \
  bash -c '[[ "$(env "$1" bash -c "type -t hmac_sha1_b64")" == function ]]' _ "$IMPFN"
rec_clear
run_sut "$REC" "" "${X_ENV[@]}" "$IMPFN" -- bash "$X_COMMUNITY" fetch-metrics
check "inherited hmac_sha1_b64 function: x-community still exits 0 with one curl call" bash -c '[[ "$1" -eq 0 && "$2" -eq 1 ]]' _ "$RC" "$(curl_calls)"
check "inherited hmac_sha1_b64 function: the signature is the vetted library's (equals the independent recomputation), not the inherited stand-in's" x_sig_ok 1 GET
# Mutant: the pre-fix guard (load the library only when no such function exists) and no unset -> the stand-in runs.
M="$(mut_make x-community.sh 'unset -f hmac_sha1_b64 2>/dev/null || true' ':' 'source "$SCRIPT_DIR/lib/hmac-sha1-b64.sh" >&3 || {' 'declare -F hmac_sha1_b64 >/dev/null || source "$SCRIPT_DIR/lib/hmac-sha1-b64.sh" >&3 || {')"
rec_clear
run_sut "$REC" "" "${X_ENV[@]}" "$IMPFN" -- bash "$M" fetch-metrics
check "mutant: x-community with the declare -F guard and no unset still sends one request (exit 0)" bash -c '[[ "$1" -eq 0 && "$2" -eq 1 ]]' _ "$RC" "$(curl_calls)"
check "mutant: that guard mutant signs with the INHERITED function: the oracle rejects the signature (RED on the row above)" not x_sig_ok 1 GET
# The control for the mutant: the same mutant without an inherited function signs correctly (the guard alone is harmless).
rec_clear
run_sut "$REC" "" "${X_ENV[@]}" -- bash "$M" fetch-metrics
check "mutant control: the same guard mutant with NO inherited function signs correctly (the row is RED because of the import)" x_sig_ok 1 GET

# x-setup.sh loads the library at startup, so the same drop-then-check has to be there. With the library
# intact the source redefines the function whatever was inherited; the path the drop closes is a library
# that loads WITHOUT defining it (truncated, emptied). That is built in a sandbox tree with an empty library.
echo "== x-setup.sh: an inherited hmac_sha1_b64 function =="
XSL="$SANDBOX/xslib"
mkdir -p "$XSL/skills/community/scripts/lib" "$XSL/scripts"
cp "$HERE/../../../scripts/resolve-git-root.sh" "$XSL/scripts/"
printf '# a library that loads and defines nothing\n:\n' > "$XSL/skills/community/scripts/lib/hmac-sha1-b64.sh"
xsl_run() { # <x-setup.sh text file> [inherited-function env]: run validate-credentials against the empty library
  cp "$1" "$XSL/skills/community/scripts/x-setup.sh"
  rec_clear
  RUN_CWD="$GITWORK" run_sut "$REC" "" "${X_ENV[@]}" "${@:2}" -- bash "$XSL/skills/community/scripts/x-setup.sh" validate-credentials
}
rec_clear
RUN_CWD="$GITWORK" run_sut "$REC" "" "${X_ENV[@]}" "$IMPFN" -- bash "$X_SETUP" validate-credentials
check "inherited hmac_sha1_b64 function: x-setup with the real library still exits 0 with one curl call" bash -c '[[ "$1" -eq 0 && "$2" -eq 1 ]]' _ "$RC" "$(curl_calls)"
check "inherited hmac_sha1_b64 function: x-setup's signature is the vetted library's (equals the independent recomputation)" x_sig_ok 1 GET
xsl_run "$X_SETUP"
check "x-setup with a library that defines nothing and NO inherited function: exit 1, curl never invoked (control: the empty library alone refuses)" \
  bash -c '[[ "$1" -eq 1 && "$2" -eq 0 ]]' _ "$RC" "$(curl_calls)"
xsl_run "$X_SETUP" "$IMPFN"
check "x-setup with a library that defines nothing and an inherited function: exit 1 and curl never invoked (the stand-in does not sign)" \
  bash -c '[[ "$1" -eq 1 && "$2" -eq 0 ]]' _ "$RC" "$(curl_calls)"
check "x-setup with a library that defines nothing and an inherited function: the load failure is named on stderr, no credential on either stream" \
  bash -c '[[ "$1" == *"did not define hmac_sha1_b64"* && "$1$2" != *"$3"* && "$1$2" != *"$4"* ]]' _ "$ERR" "$OUT" "$X_SECRET" "$X_TOKSECRET"
# Mutant 1: the unset is gone (the declare -F check alone sees the inherited stand-in and passes it).
M="$(mut_make x-setup.sh 'unset -f hmac_sha1_b64 2>/dev/null || true' ':')"
xsl_run "$M" "$IMPFN"
check "mutant: x-setup without the unset -f signs with the INHERITED function: one request is sent (RED on the refusal row)" test "$(curl_calls)" -eq 1
check "mutant: that mutant's signature is the stand-in's, so the independent recomputation rejects it" not x_sig_ok 1 GET
xsl_run "$M"
check "mutant control: the same mutant with NO inherited function still refuses on the empty library (the row above is RED because of the import)" \
  bash -c '[[ "$1" -eq 1 && "$2" -eq 0 ]]' _ "$RC" "$(curl_calls)"
# Mutant 2: the post-load check is gone (the unset alone still refuses, but the load failure is no longer named).
M="$(mut_make x-setup.sh 'if ! declare -F hmac_sha1_b64 >/dev/null; then' 'if false; then')"
xsl_run "$M" "$IMPFN"
check "mutant: x-setup without the post-load check still sends nothing (the unset leaves no signer; exit 1)" \
  bash -c '[[ "$1" -eq 1 && "$2" -eq 0 ]]' _ "$RC" "$(curl_calls)"
check "mutant: that mutant no longer names the load failure (RED on the named-failure row)" bash -c '[[ "$1" != *"did not define hmac_sha1_b64"* ]]' _ "$ERR"
# The comment claim: an inherited function of the NAME is what is closed, not "every callee".
check "x-community.sh: the signing comment no longer claims that only the vetted library's definition can run with the key in scope" \
  test "$(file_count "only the vetted library's definition can ever run" "$X_COMMUNITY")" -eq 0
check "x-community.sh: the signing comment states the true claim (an inherited function of this name cannot stand in for the library's)" \
  test "$(file_count "stand in for the library's" "$X_COMMUNITY")" -eq 1
check "x-community.sh: the signing comment states the residual (an exported od, tr, openssl, base64 or cat still receives the key on its stdin)" \
  test "$(file_count "one named od, tr, openssl, base64 or cat still receives it on its stdin" "$X_COMMUNITY")" -eq 1
check "the HMAC library header states the same residual and claims no stronger control" \
  test "$(file_count "receives the key on its stdin" "$HMAC_LIB")" -eq 1

# Lazy loading: the library is sourced inside oauth_sign, and the top-level source line is gone.
check "x-community.sh: the only source of lib/hmac-sha1-b64.sh sits inside oauth_sign (lazy, not at load)" \
  awk 'BEGIN{f=0;n=0;ins=0} /^oauth_sign\(\) \{/{f=1} /^}/{f=0} /^[[:space:]]*#/{next} /source .*lib\/hmac-sha1-b64\.sh/{n++; if(f)ins++} END{exit !(n==1 && ins==1)}' "$X_COMMUNITY"
M="$(mut_make x-community.sh 'SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
' 'SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/hmac-sha1-b64.sh"
')"
run_sut - "" -- bash -x "$M"
check "mutant: x-community with the library sourced at load again refuses a credential-free bash -x run (exit 78: RED on the rows above)" \
  bash -c '[[ "$1" -eq 78 && "$2" == *"Refusing to load the HMAC helper"* ]]' _ "$RC" "$OUT"
run_sut - "" -- bash "$M"
check "mutant control: that same load-time-source mutant still prints usage when NOT traced (exit 1): the row above is RED because of -x" test "$RC" -eq 1

# The lazy load can fail (the library is missing or unreadable): that must refuse, never send unsigned.
NOLIB="$SANDBOX/nolib"
mkdir -p "$NOLIB/mut"
cp "$X_COMMUNITY" "$NOLIB/x-community.sh"
run_sut - "" "${X_ENV[@]}" -- bash "$NOLIB/x-community.sh" fetch-metrics
check "x-community with the signing library missing: exit 1, curl never invoked, and the load failure is named (not a generic signature failure)" \
  bash -c '[[ "$1" -eq 1 && "$2" -eq 0 && "$3" == *"could not load the OAuth signing helper"* ]]' _ "$RC" "$(curl_calls)" "$ERR"
check "x-community with the signing library missing: no credential reaches either stream" \
  bash -c '[[ "$1" != *"$2"* && "$1" != *"$3"* ]]' _ "$OUT$ERR" "$X_SECRET" "$X_TOKSECRET"
nolib_one_error() { # the load failure is the ONE error: no second, misleading "unexpected shape" line
  [[ "$ERR" != *"unexpected shape"* && "$OUT$ERR" != *"unexpected shape"* && "$(awk '/^Error:/ {n++} END {print n + 0}' <<<"$ERR")" -eq 1 ]]
}
check "x-community with the signing library missing: exactly one Error line, and no second 'unexpected shape' line" nolib_one_error
# Mutant: the failed signature no longer stops the caller, so the empty header falls through to the shape check.
M="$(mut_make x-community.sh 'auth_header=$(oauth_sign "GET" "$url" "${param_args[@]}") || exit 1' 'auth_header=$(oauth_sign "GET" "$url" "${param_args[@]}")')"
mkdir -p "$NOLIB/mut2"; cp "$M" "$NOLIB/mut2/x-community.sh"
run_sut - "" "${X_ENV[@]}" -- bash "$NOLIB/mut2/x-community.sh" fetch-metrics
check "mutant: x-community without the exit after a failed signature still exits 1 and sends nothing (so only the one-error row can catch it)" \
  bash -c '[[ "$1" -eq 1 && "$2" -eq 0 ]]' _ "$RC" "$(curl_calls)"
check "mutant: that mutant prints the second, misleading 'unexpected shape' line (RED on the one-error row)" not nolib_one_error
M="$(mut_make x-community.sh 'source "$SCRIPT_DIR/lib/hmac-sha1-b64.sh" >&3 || {' 'source "$SCRIPT_DIR/lib/hmac-sha1-b64.sh" >&3 2>/dev/null || true; : || {')"
cp "$M" "$NOLIB/mut/x-community.sh"
run_sut - "" "${X_ENV[@]}" -- bash "$NOLIB/mut/x-community.sh" fetch-metrics
check "mutant: x-community that ignores a failed library load no longer names it (exit 1 still, curl never invoked; RED on the load-failure row)" \
  bash -c '[[ "$1" -eq 1 && "$2" -eq 0 && "$3" != *"could not load the OAuth signing helper"* ]]' _ "$RC" "$(curl_calls)" "$ERR"

echo "== hosted path: x-community.sh under a PATH with no interpreter =="
MINPATH="$SANDBOX/minpath"; mkdir -p "$MINPATH"
for t_ in bash openssl jq date sort sed tail head cat tr od base64 dirname basename paste; do
  rp_="$(command -v "$t_")" && ln -sf "$rp_" "$MINPATH/$t_"
done
cp "$MOCK/curl" "$MINPATH/curl"
min_found() { local n=0 t; for t in "$@"; do PATH="$MINPATH" command -v "$t" >/dev/null 2>&1 && n=$((n + 1)); done; printf '%s' "$n"; }
check "canary: no python3, python, node, perl, ruby or php on the restricted PATH" test "$(min_found python3 python node perl ruby php)" -eq 0
check "canary control: the restricted PATH does resolve bash, openssl, jq and curl (the probe can say yes)" test "$(min_found bash openssl jq curl)" -eq 4
SUT_PATH="$MINPATH" run_sut - "" "${X_ENV[@]}" -- bash "$X_COMMUNITY" fetch-metrics
check "canary: fetch-metrics succeeds with one signed request and no interpreter" bash -c '[[ "$1" -eq 0 && "$2" -eq 1 ]]' _ "$RC" "$(curl_calls)"
check "canary: the request signature is correct (independent recomputation)" x_sig_ok 1 GET
check "canary: the account JSON came back through jq" test "$(jq -r '.username' <<<"$OUT")" = "synthetic"
SUT_PATH="$MINPATH" run_sut - "" "${X_ENV[@]}" -- bash "$X_COMMUNITY" post-tweet "synthetic post"
check "canary: post-tweet succeeds with a correct signature and no interpreter" bash -c '[[ "$1" -eq 0 && "$2" -eq 1 ]]' _ "$RC" "$(curl_calls)"
check "canary: the post-tweet signature is correct (independent recomputation)" x_sig_ok 1 POST

# ===================================================================================
echo "== write-env allow-list: bsky-setup.sh, discord-setup.sh, x-setup.sh =="
# Every value is validated BEFORE the first write; a refused value prints the marker plus one human
# line naming only the VARIABLE, writes nothing, exits 1 and leaves any existing .env untouched. The
# sentinel mechanism: after the run the .env is SOURCED in a clean shell; a value that survived
# validation would run `touch SENT`.
SENT="$SANDBOX/SENTINEL.fired"
WE_VAL="" WE_REASON="" WE_RUNS=0
# The classes the allow-list must refuse. The first seven were the original matrix; the rest close the
# shell metacharacters it omitted (& | < > ' # * ? [ { ! $ and a backslash, alone and glued to a
# command substitution) plus the two control characters other than a newline (tab, CR), and the two
# parentheses (a subshell / array / function-definition opener and closer). Each of the
# single-character classes holds ONLY that one hostile character beside letters, so widening the
# allow-list by exactly that character is what the class's row must catch (a value that also held a
# second hostile character would stay refused for the second one).
WE_CLASSES=(cmdsub backtick nlassign dquote semi space tilde amp pipe lt gt squote hash star qmark lbracket lbrace bang dollar backslash bsglue tab cr lparen rparen)
# The classes that must always be present by NAME (a list cannot shrink to a few, or repeat one, and stay green).
WE_REQUIRED_CLASSES=(cmdsub backtick nlassign dquote semi space tilde lparen rparen backslash tab cr squote dollar)
we_class_val() { # <class> -> WE_VAL, WE_REASON
  WE_REASON=token_shape
  case "$1" in
    cmdsub)   WE_VAL="\$(touch $SENT)" ;;
    backtick) WE_VAL="\`touch $SENT\`" ;;
    nlassign) WE_VAL=$'abc\nEVIL=$(touch '"$SENT"')'; WE_REASON=control_char ;;
    dquote)   WE_VAL='abc"def' ;;
    semi)     WE_VAL="abc;touch $SENT" ;;
    space)    WE_VAL="abc touch $SENT" ;;
    tilde)    WE_VAL=$'~/abc' ;;
    amp)      WE_VAL='abc&def' ;;
    pipe)     WE_VAL='abc|def' ;;
    lt)       WE_VAL='abc<def' ;;
    gt)       WE_VAL='abc>def' ;;
    squote)   WE_VAL="abc'def" ;;
    hash)     WE_VAL='abc#def' ;;
    star)     WE_VAL='abc*' ;;
    qmark)    WE_VAL='abc?' ;;
    lbracket) WE_VAL='abc[def' ;;
    lbrace)   WE_VAL='abc{def' ;;
    bang)     WE_VAL='abc!def' ;;
    dollar)   WE_VAL='a$HOME' ;;
    backslash) WE_VAL='abc\def' ;;
    bsglue)   WE_VAL="abc\\\$(touch $SENT)" ;;
    tab)      WE_VAL=$'abc\tdef'; WE_REASON=control_char ;;
    cr)       WE_VAL=$'abc\rdef'; WE_REASON=control_char ;;
    lparen)   WE_VAL='abc(def' ;;
    rparen)   WE_VAL='abc)def' ;;
    *) echo "FATAL: unknown class $1" >&2; exit 2 ;;
  esac
}
we_fired() {
  rm -f "$SENT"
  ( cd "$GITWORK" && env -i PATH="$SYS_PATH" HOME="$SANDBOX/home" bash -c 'set -a; source ./.env' ) >/dev/null 2>&1 || true
  [[ -e "$SENT" ]]
}
we_untouched() { cmp -s "$SANDBOX/env.before" "$GITWORK/.env" || return 1; not we_fired; }
# we_refusal_ok <script> <var> <reason> <value> <other-var>...
we_refusal_ok() {
  local script="$1" var="$2" reason="$3" val="$4" n o re; shift 4
  [[ "$RC" -eq 1 ]] || return 1
  # The marker: exactly once, value-free, on STDERR, naming the refused variable and the phase.
  n="$(grep -cxF "SOLEUR_CREDENTIAL_REFUSED script=$script reason=$reason var=$var phase=write-env" <<<"$ERR")"
  [[ "$n" == 1 ]] || return 1
  n="$(grep -c 'SOLEUR_CREDENTIAL_REFUSED' <<<"$ERR")"
  [[ "$n" == 1 ]] || return 1
  # The ONE human line is on STDOUT (a signal the caller must act on; write-env has no stdout payload).
  n="$(grep -c '^Error:' <<<"$OUT")"
  [[ "$n" == 1 ]] || return 1
  n="$(grep -c '^Error:' <<<"$ERR")"
  [[ "$n" == 0 ]] || return 1
  re="(^|[^A-Za-z0-9_])${var}([^A-Za-z0-9_]|\$)"
  [[ "$OUT" =~ $re ]] || return 1
  for o in "$@"; do
    re="(^|[^A-Za-z0-9_])${o}([^A-Za-z0-9_]|\$)"
    [[ "$OUT$ERR" =~ $re ]] && return 1
  done
  [[ "$OUT$ERR" != *"$val"* ]] || return 1
  [[ "$OUT$ERR" != *SOLEUR_TRANSPORT_DIAG* ]]
}
WE_BASE=()
# we_run_bad <label> <seed> <script> <bad-var> <class> <args...>: the base environment is WE_BASE.
we_run_bad() {
  local label="$1" seed="$2" script="$3" var="$4" cls="$5" e val reason; shift 5
  local -a envs=() others=()
  we_class_val "$cls"; val="$WE_VAL"; reason="$WE_REASON"
  for e in "${WE_BASE[@]}"; do
    [[ "${e%%=*}" == "$var" ]] && continue
    envs+=("$e"); others+=("${e%%=*}")
  done
  envs+=("$var=$val")
  printf '%s\n' "$seed" > "$GITWORK/.env"; chmod 600 "$GITWORK/.env"
  cp "$GITWORK/.env" "$SANDBOX/env.before"
  RUN_CWD="$GITWORK" run_sut - "" "${envs[@]}" -- bash "$script" "$@"
  WE_RUNS=$((WE_RUNS + 1))
  check "$label write-env $var=<$cls>: refused (exit 1, the stderr marker once with reason=$reason var=$var phase=write-env, one human line on stdout naming only $var, value not echoed)" \
    we_refusal_ok "$(basename "$script")" "$var" "$reason" "$val" "${others[@]}"
  check "$label write-env $var=<$cls>: .env byte-identical and the sentinel never fires on source" we_untouched
}
# we_value_is <NAME> <expected>: the clean-shell value of NAME in .env equals expected, byte for byte.
we_value_is() { [[ "$( cd "$GITWORK" && env -i PATH="$SYS_PATH" HOME="$SANDBOX/home" bash -c 'source ./.env; printf "%s" "${!1}"' _ "$1" )" == "$2" ]]; }
we_mode_600() { [[ -n "$(find "$GITWORK/.env" -type f -perm 600 2>/dev/null)" ]]; }
we_line_count() { [[ "$(grep -c "^$1=" "$GITWORK/.env")" == 1 ]]; }
# we_values_ok <NAME=expected>...: every pair is in .env exactly once with the expected value, KEEP_ME survived.
we_values_ok() {
  local p
  we_value_is KEEP_ME 1 || return 1
  for p in "$@"; do
    we_line_count "${p%%=*}" || return 1
    we_value_is "${p%%=*}" "${p#*=}" || return 1
  done
}

# --- bsky-setup.sh ---------------------------------------------------------------------------
BS_SEED=$'KEEP_ME=1\nBSKY_HANDLE=old.bsky.social\nBSKY_APP_PASSWORD=old-app-pass\nOTHER=2'
WE_BASE=("BSKY_HANDLE=$BSKY_HANDLE_FIX" "BSKY_APP_PASSWORD=$BSKY_PW_FIX")
BS_VARS=(BSKY_HANDLE BSKY_APP_PASSWORD)
for var_ in "${BS_VARS[@]}"; do
  for cls_ in "${WE_CLASSES[@]}"; do we_run_bad "bsky-setup" "$BS_SEED" "$BSKY_SETUP" "$var_" "$cls_" write-env; done
done
LONG_HANDLE="a-long-handle.example-pds.social"
BS_PW2="abcd-efgh_IJKL.mnop+/=:%"
printf '%s\n' "$BS_SEED" > "$GITWORK/.env"; chmod 644 "$GITWORK/.env"
RUN_CWD="$GITWORK" run_sut - "" "BSKY_HANDLE=$LONG_HANDLE" "BSKY_APP_PASSWORD=$BS_PW2" -- bash "$BSKY_SETUP" write-env
check "bsky-setup write-env round trip: exit 0, no marker, mode 600 (an existing mode 644 file is tightened)" \
  bash -c '[[ "$1" -eq 0 && "$2" != *SOLEUR_CREDENTIAL_REFUSED* ]]' _ "$RC" "$ERR"
check "bsky-setup write-env round trip: .env is mode 600" we_mode_600
check "bsky-setup write-env round trip: sourcing .env yields both values byte-for-byte, once each, and the unrelated line survives" \
  we_values_ok "BSKY_HANDLE=$LONG_HANDLE" "BSKY_APP_PASSWORD=$BS_PW2"
# The confirmation is human text of a command with no stdout payload: STDOUT, like the refusal line.
we_wrote_stdout() { # <N>: exactly one "Wrote N variables to <path> (permissions: 600)" line on stdout, nothing on stderr
  [[ "$OUT" == "Wrote $1 variables to "*" (permissions: 600)" && "$(wc -l <<<"$OUT")" -eq 1 && -z "$ERR" ]]
}
check "bsky-setup write-env round trip: the 'Wrote 2 variables' confirmation is the one line on stdout and stderr is empty" we_wrote_stdout 2
# Missing credentials: also stdout (write-env has no stdout payload), exit 1, and NO marker (the marker is the allow-list's alone).
we_missing_stdout() { # <expected-missing-credential-name>
  [[ "$RC" -eq 1 && "$OUT" == *"Error: Missing "*"credentials: "*"$1"* && "$OUT" == *"To configure:"* \
    && -z "$ERR" && "$OUT$ERR" != *SOLEUR_CREDENTIAL_REFUSED* ]]
}
printf '%s\n' "$BS_SEED" > "$GITWORK/.env"; cp "$GITWORK/.env" "$SANDBOX/env.before"
RUN_CWD="$GITWORK" run_sut - "" "BSKY_HANDLE=$BSKY_HANDLE_FIX" -- bash "$BSKY_SETUP" write-env
check "bsky-setup write-env with BSKY_APP_PASSWORD missing: exit 1, the diagnostic names it on STDOUT, stderr empty, no marker" we_missing_stdout BSKY_APP_PASSWORD
check "bsky-setup write-env with a credential missing: the existing .env is left byte-identical" cmp -s "$SANDBOX/env.before" "$GITWORK/.env"

# --- x-setup.sh -------------------------------------------------------------------------------
XS_SEED=$'KEEP_ME=1\nX_API_KEY=old\nX_API_SECRET=old\nX_ACCESS_TOKEN=old\nX_ACCESS_TOKEN_SECRET=old\nOTHER=2'
WE_BASE=("X_API_KEY=$X_KEY" "X_API_SECRET=$X_SECRET" "X_ACCESS_TOKEN=$X_TOK" "X_ACCESS_TOKEN_SECRET=$X_TOKSECRET")
XS_VARS=(X_API_KEY X_API_SECRET X_ACCESS_TOKEN X_ACCESS_TOKEN_SECRET)
for var_ in "${XS_VARS[@]}"; do
  for cls_ in "${WE_CLASSES[@]}"; do we_run_bad "x-setup" "$XS_SEED" "$X_SETUP" "$var_" "$cls_" write-env; done
done
XS_K="Ab12Cd34Ef56Gh78Ij90Kl12M"; XS_S="aB3+/=:%xYz-Q.w_9ZkLmNoPqRsTuVwXyZ0123456789a"; XS_T="1234567890123456789-AbCdEfGhIjKlMnOpQrStUvWxYz"; XS_TS="zZyYxXwWvVuUtTsSrRqQpPoOnNmMlLkKjJiIhH"
printf '%s\n' "$XS_SEED" > "$GITWORK/.env"; chmod 644 "$GITWORK/.env"
RUN_CWD="$GITWORK" run_sut - "" "X_API_KEY=$XS_K" "X_API_SECRET=$XS_S" "X_ACCESS_TOKEN=$XS_T" "X_ACCESS_TOKEN_SECRET=$XS_TS" -- bash "$X_SETUP" write-env
check "x-setup write-env round trip: exit 0, no marker" bash -c '[[ "$1" -eq 0 && "$2" != *SOLEUR_CREDENTIAL_REFUSED* ]]' _ "$RC" "$ERR"
check "x-setup write-env round trip: .env is mode 600" we_mode_600
check "x-setup write-env round trip: sourcing .env yields all four values byte-for-byte (a secret holding + / = : %), once each, and the unrelated line survives" \
  we_values_ok "X_API_KEY=$XS_K" "X_API_SECRET=$XS_S" "X_ACCESS_TOKEN=$XS_T" "X_ACCESS_TOKEN_SECRET=$XS_TS"
check "x-setup write-env round trip: the 'Wrote 4 variables' confirmation is the one line on stdout and stderr is empty" we_wrote_stdout 4
printf '%s\n' "$XS_SEED" > "$GITWORK/.env"; cp "$GITWORK/.env" "$SANDBOX/env.before"
RUN_CWD="$GITWORK" run_sut - "" "X_API_KEY=$XS_K" "X_API_SECRET=$XS_S" "X_ACCESS_TOKEN=$XS_T" -- bash "$X_SETUP" write-env
check "x-setup write-env with X_ACCESS_TOKEN_SECRET missing: exit 1, the diagnostic names it on STDOUT, stderr empty, no marker" we_missing_stdout X_ACCESS_TOKEN_SECRET
check "x-setup write-env with a credential missing: the existing .env is left byte-identical" cmp -s "$SANDBOX/env.before" "$GITWORK/.env"

# --- discord-setup.sh -------------------------------------------------------------------------
DW_URL="https://discord.com/api/webhooks/123456789012345678/SYNTHwebhook-token_0001"
DW_REL="https://discord.com/api/webhooks/223456789012345678/SYNTHreleases-token_0002"
DW_BLOG="https://discord.com/api/webhooks/323456789012345678/SYNTHblog-token_0003"
DS_SEED=$'KEEP_ME=1\nDISCORD_BOT_TOKEN=old\nDISCORD_GUILD_ID=1\nDISCORD_WEBHOOK_URL=old\nDISCORD_RELEASES_WEBHOOK_URL=old\nDISCORD_BLOG_WEBHOOK_URL=old\nOTHER=2'
WE_BASE=("DISCORD_BOT_TOKEN_INPUT=$DISC_TOK" "DISCORD_WEBHOOK_URL_INPUT=$DW_URL" "DISCORD_RELEASES_WEBHOOK_URL_INPUT=$DW_REL" "DISCORD_BLOG_WEBHOOK_URL_INPUT=$DW_BLOG")
DS_VARS=(DISCORD_BOT_TOKEN_INPUT DISCORD_WEBHOOK_URL_INPUT DISCORD_RELEASES_WEBHOOK_URL_INPUT DISCORD_BLOG_WEBHOOK_URL_INPUT)
for var_ in "${DS_VARS[@]}"; do
  for cls_ in "${WE_CLASSES[@]}"; do we_run_bad "discord-setup" "$DS_SEED" "$DISCORD_SETUP" "$var_" "$cls_" write-env "$GUILD"; done
done
# The floor counts DISTINCT classes (sort -u), not array elements or words: eight copies of one class,
# or a list cut to a few, must not satisfy it. The required names are asserted present on top of the count.
we_distinct_classes() { printf '%s\n' "$@" | sort -u | wc -l; }
we_has_all_required() { local want c; for want in "${WE_REQUIRED_CLASSES[@]}"; do for c in "$@"; do [[ "$c" == "$want" ]] && continue 2; done; return 1; done; }
check "write-env hostile rows: the matrix has at least 25 DISTINCT classes (a shrunk or duplicated class list must fail)" test "$(we_distinct_classes "${WE_CLASSES[@]}")" -ge 25
check "write-env hostile rows: every required class (parentheses, backslash, tab, CR, quote, dollar, ...) is present by name" we_has_all_required "${WE_CLASSES[@]}"
we_distinct_is() { [[ "$(we_distinct_classes "${@:2}")" -eq "$1" ]]; }
check "write-env hostile rows: the distinct counter counts three copies of one class as 1" we_distinct_is 1 quote quote quote
check "write-env hostile rows: the distinct counter counts one duplicate among four classes as 3" we_distinct_is 3 quote quote semi pipe
check "write-env hostile rows: the required-name check discriminates (a list missing lparen is refused)" \
  not we_has_all_required cmdsub backtick nlassign dquote semi space tilde rparen backslash tab cr squote dollar
check "write-env hostile rows: the inner counter saw every run (${#BS_VARS[@]} + ${#XS_VARS[@]} + ${#DS_VARS[@]} variables x ${#WE_CLASSES[@]} classes)" \
  test "$WE_RUNS" -eq "$(( (${#BS_VARS[@]} + ${#XS_VARS[@]} + ${#DS_VARS[@]}) * ${#WE_CLASSES[@]} ))"
printf '%s\n' "$DS_SEED" > "$GITWORK/.env"; chmod 644 "$GITWORK/.env"
RUN_CWD="$GITWORK" run_sut - "" "${WE_BASE[@]}" -- bash "$DISCORD_SETUP" write-env "$GUILD"
check "discord-setup write-env round trip (webhook URL from the environment): exit 0, no marker" \
  bash -c '[[ "$1" -eq 0 && "$2" != *SOLEUR_CREDENTIAL_REFUSED* ]]' _ "$RC" "$ERR"
check "discord-setup write-env round trip: the 'Wrote 5 variables' confirmation is the one line on stdout and stderr is empty" we_wrote_stdout 5
check "discord-setup write-env round trip: .env is mode 600" we_mode_600
check "discord-setup write-env round trip: all five values byte-for-byte, once each, and the unrelated line survives" \
  we_values_ok "DISCORD_BOT_TOKEN=$DISC_TOK" "DISCORD_GUILD_ID=$GUILD" "DISCORD_WEBHOOK_URL=$DW_URL" "DISCORD_RELEASES_WEBHOOK_URL=$DW_REL" "DISCORD_BLOG_WEBHOOK_URL=$DW_BLOG"

echo "== discord-setup.sh write-env: the webhook URL moves off the command line =="
dw_untouched_run() { # <env...> -- <cmd...>: seeds a .env, runs, leaves RC/OUT/ERR
  printf "%s\n" "$DS_SEED" > "$GITWORK/.env"; chmod 644 "$GITWORK/.env"
  cp "$GITWORK/.env" "$SANDBOX/env.before"
  RUN_CWD="$GITWORK" run_sut - "" "$@"
}
dw_no_secret() { [[ "$OUT$ERR" != *"$DW_URL"* && "$OUT$ERR" != *SYNTHwebhook-token_0001* ]]; }
dw_no_marker() { [[ "$(grep -c SOLEUR_CREDENTIAL_REFUSED <<<"$ERR")" == 0 ]]; }
dw_names_var() { [[ "$OUT" == *"Error: DISCORD_WEBHOOK_URL_INPUT is not set"* ]]; }
# dw_devnull_run <env...> -- <cmd...>: like dw_untouched_run but with stdin from /dev/null, so it is certainly not a terminal.
dw_devnull_run() {
  local o="$SANDBOX/out2" e="$SANDBOX/err2"
  local -a envs=()
  while [[ "$1" != "--" ]]; do envs+=("$1"); shift; done
  shift
  printf "%s\n" "$DS_SEED" > "$GITWORK/.env"; chmod 644 "$GITWORK/.env"
  cp "$GITWORK/.env" "$SANDBOX/env.before"
  ( cd "$GITWORK" && env -i PATH="$MOCK:$SYS_PATH" HOME="$SANDBOX/home" MOCK_DIR="$MOCK" "${envs[@]}" "$@" ) < /dev/null > "$o" 2> "$e"
  RC=$?
  OUT="$(cat "$o")"
  ERR="$(cat "$e")"
}
# The non-TTY remedy keeps every value out of the COMMAND TEXT (the transcript, the shell history, a
# wrapper's argument list): the values are read from mode-600 files. An inline `VAR=value command`, and
# any `printf '%s' "$URL" |` form (the URL has to come from somewhere typed into a command), is NOT offered.
DW_FILEFORM='read -r DISCORD_WEBHOOK_URL_INPUT < /path/to/webhook-url.txt; read -r DISCORD_BOT_TOKEN_INPUT < /path/to/bot-token.txt; export DISCORD_WEBHOOK_URL_INPUT DISCORD_BOT_TOKEN_INPUT; discord-setup.sh write-env <guild_id>'
DW_INLINE_RE='(^|[[:space:]])DISCORD_[A-Z_]+_INPUT=[^[:space:]]'
# dw_no_inline: no `DISCORD_*_INPUT=<something>` word anywhere in the output, and no printf/$URL pipe form.
dw_no_inline() { [[ ! "$OUT" =~ $DW_INLINE_RE ]] && [[ "$OUT" != *printf* && "$OUT" != *'$URL'* ]]; }
# dw_names_token: the remedy names the bot token too (a missing webhook plus a missing token must not give a second bare exit 64).
dw_names_token() { [[ "$OUT" == *"read -rs DISCORD_BOT_TOKEN_INPUT; export DISCORD_BOT_TOKEN_INPUT"* ]]; }
# The non-TTY remedy, one predicate per conjunct so a mutant can be driven to break exactly one of them
# (dw_failed names the failing ones). The three recipes added for the value-in-command-text and
# lingering-export findings: the mode-first file recipe for BOTH files, the chmod note for an existing
# file, the bot token supplied to create-webhook, and both secrets confined to a subshell.
dw_c_fileform()    { [[ "$OUT" == *"$DW_FILEFORM"* ]]; }
dw_c_nontty()      { [[ "$OUT" == *"stdin is not a terminal"* ]]; }
dw_c_createwh()    { [[ "$OUT" == *"create-webhook <channel_id> > /path/to/webhook-url.txt"* ]]; }
dw_c_umask_hook()  { [[ "$OUT" == *"(umask 077; cat > /path/to/webhook-url.txt)"* ]]; }
dw_c_umask_token() { [[ "$OUT" == *"(umask 077; cat > /path/to/bot-token.txt)"* ]]; }
dw_c_chmod()       { [[ "$OUT" == *"run chmod 600 on it before writing"* ]]; }
dw_c_cw_token()    { [[ "$OUT" == *"read -r DISCORD_BOT_TOKEN_INPUT < /path/to/bot-token.txt; export DISCORD_BOT_TOKEN_INPUT; umask 077; discord-setup.sh create-webhook"* ]]; }
dw_c_wrap_open()   { [[ "$OUT" == *"( read -r DISCORD_WEBHOOK_URL_INPUT < /path/to/webhook-url.txt;"* ]]; }
dw_c_wrap_close()  { [[ "$OUT" == *"discord-setup.sh write-env <guild_id> )"* ]]; }
DW_CONJ=(dw_c_fileform dw_c_nontty dw_c_createwh dw_c_umask_hook dw_c_umask_token dw_c_chmod dw_c_cw_token dw_c_wrap_open dw_c_wrap_close dw_names_token dw_no_inline)
dw_remedy_non_tty() { local c; for c in "${DW_CONJ[@]}"; do "$c" || return 1; done; }
dw_failed() { local c out=""; for c in "${DW_CONJ[@]}"; do "$c" || out+="$c "; done; printf '%s' "${out% }"; }
dw_quiet_clean() { dw_no_secret && dw_untouched && dw_no_marker; }
dw_untouched() { cmp -s "$SANDBOX/env.before" "$GITWORK/.env"; }
dw_quiet_untouched() { dw_no_secret && dw_untouched; }
dw_clean_untouched() { dw_no_marker && dw_untouched; }
# (1) a second positional, environment variable unset
dw_untouched_run "DISCORD_BOT_TOKEN_INPUT=$DISC_TOK" -- bash "$DISCORD_SETUP" write-env "$GUILD" "$DW_URL"
check "discord positional webhook (env unset): refused with exit 64" test "$RC" -eq 64
check "discord positional webhook: the message (on stdout) names DISCORD_WEBHOOK_URL_INPUT and shows the interactive no-history form" \
  bash -c '[[ "$1" == *DISCORD_WEBHOOK_URL_INPUT* && "$1" == *"read -rs DISCORD_WEBHOOK_URL_INPUT"* ]]' _ "$OUT"
check "discord positional webhook: stdin is not a terminal here, so the remedy ALSO gives the read-from-a-mode-600-file form for both inputs and recommends no inline VAR=value form (read -rs needs a TTY)" dw_remedy_non_tty
check "discord positional webhook: the whole usage error is on stdout (nothing on stderr)" test -z "$ERR"
check "discord positional webhook: the argument is never echoed (stdout and stderr)" dw_no_secret
check "discord positional webhook: not the credential-shape marker (this is a usage error)" dw_no_marker
check "discord positional webhook: an existing .env is left byte-identical" dw_untouched
# (1a) the same, with stdin from /dev/null (no terminal, as in an agent runtime)
dw_devnull_run "DISCORD_BOT_TOKEN_INPUT=$DISC_TOK" -- bash "$DISCORD_SETUP" write-env "$GUILD" "$DW_URL"
check "discord positional webhook, stdin </dev/null: exit 64 and the remedy gives the file-read form" \
  bash -c '[[ "$1" -eq 64 ]]' _ "$RC"
check "discord positional webhook, stdin </dev/null: the non-TTY remedy text is on stdout" dw_remedy_non_tty
check "discord positional webhook, stdin </dev/null: the argument is never echoed, .env untouched" dw_quiet_untouched
dw_devnull_run "DISCORD_BOT_TOKEN_INPUT=$DISC_TOK" -- bash "$DISCORD_SETUP" write-env "$GUILD"
check "discord write-env with no webhook, stdin </dev/null: exit 64 and the non-TTY remedy (file-read form) on stdout" \
  bash -c '[[ "$1" -eq 64 ]]' _ "$RC"
check "discord write-env with no webhook, stdin </dev/null: the remedy text gives the file-read form for both inputs" dw_remedy_non_tty
check "discord write-env with no webhook, stdin </dev/null: the remedy recommends no inline VAR=value form and no printf/\$URL pipe form" dw_no_inline
check "discord write-env with no webhook, stdin </dev/null: the remedy also names DISCORD_BOT_TOKEN_INPUT (following it once does not give a second bare exit 64)" dw_names_token
check "discord write-env with no webhook, stdin </dev/null: the remedy states the residual (values stay in the files until deleted; create-webhook output is redirected into the file)" \
  bash -c '[[ "$1" == *"Delete both files afterwards: the values stay in them until you do."* && "$1" == *"without printing the URL"* ]]' _ "$OUT"
check "discord write-env with no webhook, stdin </dev/null: the usage error is on stdout and stderr is empty" test -z "$ERR"
# (1b) the positional AND the variable: still refused (the secret is already on this command line)
dw_untouched_run "DISCORD_BOT_TOKEN_INPUT=$DISC_TOK" "DISCORD_WEBHOOK_URL_INPUT=$DW_URL" -- bash "$DISCORD_SETUP" write-env "$GUILD" "$DW_URL"
check "discord positional webhook (env also set): still refused with exit 64" test "$RC" -eq 64
check "discord positional webhook (env also set): the argument is never echoed and .env is untouched" dw_quiet_untouched
# (3) neither
dw_untouched_run "DISCORD_BOT_TOKEN_INPUT=$DISC_TOK" -- bash "$DISCORD_SETUP" write-env "$GUILD"
check "discord write-env with neither the positional nor the variable: exit 64" test "$RC" -eq 64
check "discord write-env with neither: the usage error names the variable" dw_names_var
check "discord write-env with neither: .env untouched, no marker" dw_clean_untouched
# (4) the variable set but empty
dw_untouched_run "DISCORD_BOT_TOKEN_INPUT=$DISC_TOK" "DISCORD_WEBHOOK_URL_INPUT=" -- bash "$DISCORD_SETUP" write-env "$GUILD"
check "discord write-env with an EMPTY DISCORD_WEBHOOK_URL_INPUT: exit 64" test "$RC" -eq 64
check "discord write-env with an EMPTY DISCORD_WEBHOOK_URL_INPUT: the same usage error naming the variable" dw_names_var
# (5) the bot token missing or empty: the same usage-error class (64) as a missing webhook, remedy on stdout
dw_untouched_run "DISCORD_WEBHOOK_URL_INPUT=$DW_URL" -- bash "$DISCORD_SETUP" write-env "$GUILD"
check "discord write-env with DISCORD_BOT_TOKEN_INPUT unset: exit 64 (the same class as a missing webhook), the usage error on stdout names the variable" \
  bash -c '[[ "$1" -eq 64 && "$2" == *DISCORD_BOT_TOKEN_INPUT* ]]' _ "$RC" "$OUT"
check "discord write-env with DISCORD_BOT_TOKEN_INPUT unset: .env untouched, no marker, the webhook not echoed" dw_quiet_clean
check "discord write-env with DISCORD_BOT_TOKEN_INPUT unset: the remedy is printed too (SKILL.md says both missing inputs print it) and names the token" dw_names_token
dw_devnull_run "DISCORD_WEBHOOK_URL_INPUT=$DW_URL" -- bash "$DISCORD_SETUP" write-env "$GUILD"
check "discord write-env with DISCORD_BOT_TOKEN_INPUT unset, stdin </dev/null: exit 64 and the non-TTY file-read remedy on stdout, no inline form" \
  bash -c '[[ "$1" -eq 64 ]]' _ "$RC"
check "discord write-env with DISCORD_BOT_TOKEN_INPUT unset, stdin </dev/null: the remedy gives the file-read form and recommends no inline VAR=value form" dw_remedy_non_tty
# (5a) no guild_id at all: the same usage-error class (64) with the text on STDOUT, not a stderr-only `${1:?}` exit 1
dw_devnull_run "DISCORD_BOT_TOKEN_INPUT=$DISC_TOK" "DISCORD_WEBHOOK_URL_INPUT=$DW_URL" -- bash "$DISCORD_SETUP" write-env
check "discord write-env with no guild_id: exit 64 (usage class), not the exit 1 of a bash parameter error" \
  bash -c '[[ "$1" -eq 64 ]]' _ "$RC"
check "discord write-env with no guild_id: the usage line and the error are on stdout and stderr is empty" \
  bash -c '[[ "$1" == *"Usage: discord-setup.sh write-env <guild_id>"* && "$1" == *"Error: guild_id is missing"* && -z "$2" ]]' _ "$OUT" "$ERR"
check "discord write-env with no guild_id: .env untouched, no marker, neither secret echoed" bash -c '[[ "$1" != *"$2"* && "$1" != *"$3"* ]]' _ "$OUT$ERR" "$DW_URL" "$DISC_TOK"
check "discord write-env with no guild_id: .env untouched" dw_clean_untouched
dw_untouched_run "DISCORD_BOT_TOKEN_INPUT=" "DISCORD_WEBHOOK_URL_INPUT=$DW_URL" -- bash "$DISCORD_SETUP" write-env "$GUILD"
check "discord write-env with an EMPTY DISCORD_BOT_TOKEN_INPUT: exit 64 and the same usage error" \
  bash -c '[[ "$1" -eq 64 && "$2" == *DISCORD_BOT_TOKEN_INPUT* ]]' _ "$RC" "$OUT"
# (6) the webhook URL in the guild_id slot: refused as non-numeric WITHOUT echoing it
dw_untouched_run "DISCORD_BOT_TOKEN_INPUT=$DISC_TOK" "DISCORD_WEBHOOK_URL_INPUT=$DW_URL" -- bash "$DISCORD_SETUP" write-env "$DW_URL"
check "discord write-env with the webhook URL as the sole positional (the guild_id slot): exit 1, 'must be numeric'" \
  bash -c '[[ "$1" -eq 1 && "$2" == *"guild_id must be numeric"* ]]' _ "$RC" "$ERR"
check "discord write-env with a non-numeric guild_id: the one line is on stderr and stdout is empty (the real stream the header and SKILL.md state)" \
  bash -c '[[ -z "$1" && "$(wc -l <<<"$2")" -eq 1 ]]' _ "$OUT" "$ERR"
check "discord write-env with the webhook URL as the guild_id: the URL is on neither stream, .env untouched" dw_quiet_untouched
dw_untouched_run "DISCORD_BOT_TOKEN_INPUT=$DISC_TOK" -- bash "$DISCORD_SETUP" list-channels "$DW_URL"
check "discord list-channels with the webhook URL as the guild_id: exit 1 and the URL is on neither stream, curl never invoked" \
  bash -c '[[ "$1" -eq 1 && "$2" -eq 0 ]]' _ "$RC" "$(curl_calls)"
check "discord list-channels with the webhook URL as the guild_id: the URL is not echoed" dw_no_secret
# (2) the repair path: the variable, no positional -> written, mode 600 (a hostile value on this path is refused by the hostile rows above)
dw_untouched_run "DISCORD_BOT_TOKEN_INPUT=$DISC_TOK" "DISCORD_WEBHOOK_URL_INPUT=$DW_URL" -- bash "$DISCORD_SETUP" write-env "$GUILD"
check "discord write-env repair path (variable, no positional): exit 0" test "$RC" -eq 0
check "discord write-env repair path: the URL lands in .env byte-for-byte" we_value_is DISCORD_WEBHOOK_URL "$DW_URL"
check "discord write-env repair path: .env is mode 600" we_mode_600
check "discord write-env repair path: the URL is not echoed" dw_no_secret

# --- population manifest: every cmd_write_env writer is classified -------------------------------
echo "== write-env writers: population manifest =="
WRITERS="$(cd "$HERE" && grep -lE '^cmd_write_env\(\)' ./*-setup.sh | sed 's|^\./||' | sort | paste -sd ' ' -)"
check "population: the cmd_write_env writers derived by grep are exactly the four classified ones" \
  test "$WRITERS" = "bsky-setup.sh discord-setup.sh linkedin-setup.sh x-setup.sh"
check "population: the derived writer set is non-empty (anti-vacuity: four writers, no more, no fewer)" test "$(wc -w <<<"$WRITERS")" -eq 4
for w_ in bsky-setup.sh discord-setup.sh x-setup.sh; do
  # validated: the validator is called inside cmd_write_env BEFORE its first mutation of the file
  check "population: $w_ validates every value before the first temp-file, touch or write in cmd_write_env" \
    awk 'BEGIN{v=0;m=0} /^cmd_write_env\(\) \{/{f=1} f&&/_wenv_validate /&&!v{v=NR} f&&/mktemp|touch "\$env_file"|>> "\$env_file"/&&!m{m=NR} f&&/^}/{exit} END{exit !(v&&m&&v<m)}' "$HERE/$w_"
done
check "population: linkedin-setup.sh is the one DEFERRED writer (tracked follow-up) and carries no validator yet; move it to the validated list with its own rows when it gains one" \
  test "$(file_count '_wenv_validate' "$HERE/linkedin-setup.sh")" -eq 0

# --- the three _wenv blocks are one block ---------------------------------------------------------
echo "== write-env allow-list: the three copies are byte-identical =="
wenv_block() { # <file>: from `_wenv_class() {` through the closing brace of `_wenv_validate`
  awk '/^_wenv_class\(\) \{/{f=1} f{print} f&&/^_wenv_validate\(\) \{/{v=1} v&&/^}$/{exit}' "$1"
}
WBLK="$SANDBOX/wenvblk"
mkdir -p "$WBLK"
wenv_sane() { # <block-file>: non-empty, whole, and long enough not to be a truncated extraction
  [[ -s "$1" ]] && [[ "$(wc -l < "$1")" -ge 25 ]] && grep -qxF '_wenv_validate() {' "$1" \
    && grep -qF '*[!A-Za-z0-9._:/@%+=,-]*) return 1 ;;' "$1" && grep -qF 'phase=write-env' "$1"
}
for w_ in bsky-setup.sh discord-setup.sh x-setup.sh; do
  wenv_block "$HERE/$w_" > "$WBLK/$w_.blk"
  check "wenv drift: the $w_ _wenv block extracted whole (non-vacuous)" wenv_sane "$WBLK/$w_.blk"
done
check "wenv drift: discord-setup.sh's _wenv block is byte-identical to bsky-setup.sh's" cmp -s "$WBLK/bsky-setup.sh.blk" "$WBLK/discord-setup.sh.blk"
check "wenv drift: x-setup.sh's _wenv block is byte-identical to bsky-setup.sh's" cmp -s "$WBLK/bsky-setup.sh.blk" "$WBLK/x-setup.sh.blk"
# Mutation: one character widened in ONE copy turns the comparison RED (and the mutation landed).
M="$(mut_make discord-setup.sh '[!A-Za-z0-9._:/@%+=,-]' '[!A-Za-z0-9._:/@%+=,*-]')"
wenv_block "$M" > "$WBLK/discord-mut.blk"
check "wenv drift: the widening mutation landed in the discord-setup.sh sandbox copy" not cmp -s "$HERE/discord-setup.sh" "$M"
check "wenv drift: a copy whose allow-list was widened by one character is RED against the others" not cmp -s "$WBLK/bsky-setup.sh.blk" "$WBLK/discord-mut.blk"
M="$(mut_make x-setup.sh "echo \"Error: \${2} holds" "echo \"Error: \${2} holdz")"
wenv_block "$M" > "$WBLK/x-mut.blk"
check "wenv drift: a one-character edit to the human line of x-setup.sh's copy is RED against the others" not cmp -s "$WBLK/bsky-setup.sh.blk" "$WBLK/x-mut.blk"

# --- mutants: each validator weakening is caught by the rows above ------------------------------
echo "== write-env mutants =="
we_mutant_run() { # <label> <seed> <mutant-script> <bad-var> <class> <args...>
  local label="$1" seed="$2" script="$3" var="$4" cls="$5" e val; shift 5
  local -a envs=()
  we_class_val "$cls"; val="$WE_VAL"
  for e in "${WE_BASE[@]}"; do [[ "${e%%=*}" == "$var" ]] || envs+=("$e"); done
  envs+=("$var=$val")
  printf '%s\n' "$seed" > "$GITWORK/.env"; chmod 600 "$GITWORK/.env"
  cp "$GITWORK/.env" "$SANDBOX/env.before"
  RUN_CWD="$GITWORK" run_sut - "" "${envs[@]}" -- bash "$script" "$@"
}
# we_mut_fired <mutant-script>: the mutant PARSES (a syntax error would leave .env untouched and read as a pass)
# AND its hostile write reached .env or fired the sentinel.
we_mut_fired() { bash -n "$1" 2>/dev/null && not we_untouched; }
WE_BASE=("BSKY_HANDLE=$BSKY_HANDLE_FIX" "BSKY_APP_PASSWORD=$BSKY_PW_FIX")
M="$(mut_make bsky-setup.sh '_wenv_validate BSKY_HANDLE BSKY_APP_PASSWORD' ':')"
we_mutant_run "bsky" "$BS_SEED" "$M" BSKY_HANDLE cmdsub write-env
check "mutant: bsky-setup with the validator call removed writes the hostile value and the sentinel fires on source (RED on the hostile row)" we_mut_fired "$M"
M="$(mut_make bsky-setup.sh '_wenv_validate BSKY_HANDLE BSKY_APP_PASSWORD' '_wenv_validate BSKY_HANDLE')"
we_mutant_run "bsky" "$BS_SEED" "$M" BSKY_APP_PASSWORD cmdsub write-env
check "mutant: bsky-setup validating only the first value lets a hostile SECOND value through (RED on the position-2 row)" we_mut_fired "$M"
M="$(mut_make bsky-setup.sh '[!A-Za-z0-9._:/@%+=,-]' '[!A-Za-z0-9._:/@%+=,\ -]')"
we_mutant_run "bsky" "$BS_SEED" "$M" BSKY_HANDLE space write-env
check "mutant: bsky-setup with the allow-list widened to a space lets 'VAR=x cmd' through and the sentinel fires on source (RED on the hostile row)" we_mut_fired "$M"
# The human line back on stderr: the refusal rows (one Error: line on STDOUT, none on stderr) go RED.
we_mutant_refusal_red() { # <mutant> <seed> <var> <class> <args...>; WE_BASE is set. Refused still (exit 1) but the FORMAT row is RED.
  local m="$1" seed="$2" var="$3" cls="$4" e; shift 4
  local -a others=()
  we_mutant_run x "$seed" "$m" "$var" "$cls" "$@"
  we_class_val "$cls"
  for e in "${WE_BASE[@]}"; do [[ "${e%%=*}" == "$var" ]] || others+=("${e%%=*}"); done
  [[ "$RC" -eq 1 ]] && ! we_refusal_ok "$(basename "$m")" "$var" "$WE_REASON" "$WE_VAL" "${others[@]}"
}
M="$(mut_make bsky-setup.sh $'add it to .env by hand."\n  exit 1' $'add it to .env by hand." >&2\n  exit 1')"
check "mutant: bsky-setup printing the allow-list human line on stderr again is RED on the refusal rows (still exit 1)" \
  we_mutant_refusal_red "$M" "$BS_SEED" BSKY_HANDLE semi write-env
WE_BASE=("X_API_KEY=$X_KEY" "X_API_SECRET=$X_SECRET" "X_ACCESS_TOKEN=$X_TOK" "X_ACCESS_TOKEN_SECRET=$X_TOKSECRET")
M="$(mut_make x-setup.sh '_wenv_validate X_API_KEY X_API_SECRET X_ACCESS_TOKEN X_ACCESS_TOKEN_SECRET' ':')"
we_mutant_run "x" "$XS_SEED" "$M" X_ACCESS_TOKEN_SECRET backtick write-env
check "mutant: x-setup with the validator call removed writes the hostile value and the sentinel fires on source (RED on the hostile row)" we_mut_fired "$M"
# (In a case pattern `|` and `&` must be backslash-quoted: bare, the shell reads a separator or a
# control operator, and the mutant would not even parse; we_mut_fired refuses an unparsable mutant.)
M="$(mut_make x-setup.sh '[!A-Za-z0-9._:/@%+=,-]' '[!A-Za-z0-9._:/@%+=,\|-]')"
we_mutant_run "x" "$XS_SEED" "$M" X_API_KEY pipe write-env
check "mutant: x-setup with the allow-list widened to a pipe lets 'VAR=x|y' through, so the written .env differs from its seed (RED on the pipe row)" we_mut_fired "$M"
M="$(mut_make x-setup.sh $' reason=%s var=%s phase=write-env\\n\' "$SOLEUR_TRANSPORT_SCRIPT" "$1" "$2" >&2' $' reason=%s\\n\' "$SOLEUR_TRANSPORT_SCRIPT" "$1" >&2')"
check "mutant: x-setup whose stderr marker lost var= and phase= is RED on the refusal rows (still exit 1)" \
  we_mutant_refusal_red "$M" "$XS_SEED" X_API_SECRET backtick write-env
WE_BASE=("DISCORD_BOT_TOKEN_INPUT=$DISC_TOK" "DISCORD_WEBHOOK_URL_INPUT=$DW_URL" "DISCORD_RELEASES_WEBHOOK_URL_INPUT=$DW_REL" "DISCORD_BLOG_WEBHOOK_URL_INPUT=$DW_BLOG")
M="$(mut_make discord-setup.sh '_wenv_validate DISCORD_BOT_TOKEN_INPUT DISCORD_WEBHOOK_URL_INPUT DISCORD_RELEASES_WEBHOOK_URL_INPUT DISCORD_BLOG_WEBHOOK_URL_INPUT' ':')"
we_mutant_run "discord" "$DS_SEED" "$M" DISCORD_BLOG_WEBHOOK_URL_INPUT semi write-env "$GUILD"
check "mutant: discord-setup with the validator call removed writes a hostile optional webhook and the sentinel fires on source (RED on the hostile row)" we_mut_fired "$M"
M="$(mut_make discord-setup.sh '[!A-Za-z0-9._:/@%+=,-]' '[!A-Za-z0-9._:/@%+=,\&-]')"
we_mutant_run "discord" "$DS_SEED" "$M" DISCORD_WEBHOOK_URL_INPUT amp write-env "$GUILD"
check "mutant: discord-setup with the allow-list widened to an ampersand lets 'VAR=x&y' through, so the written .env differs from its seed (RED on the amp row)" we_mut_fired "$M"
# The Discord usage-error remedy: stdin not a terminal -> the file-read form; the check is inverted -> it vanishes.
M="$(mut_make discord-setup.sh 'if [ ! -t 0 ]; then' 'if [ -t 0 ]; then')"
dw_devnull_run "DISCORD_BOT_TOKEN_INPUT=$DISC_TOK" -- bash "$M" write-env "$GUILD"
check "mutant: discord-setup with the terminal test inverted drops the non-TTY remedy under stdin </dev/null (exit 64 still; RED on the non-TTY rows)" \
  bash -c '[[ "$1" -eq 64 ]]' _ "$RC"
check "mutant: that inverted-terminal-test mutant no longer gives the file-read form" not dw_remedy_non_tty
# Each conjunct of dw_remedy_non_tty is driven to FAIL ALONE by a mutant that breaks only it.
# (a) an inline `VAR=value command` form comes back: the no-inline conjunct (the rest of the remedy is intact).
M="$(mut_make discord-setup.sh '    echo "Your stdin is not a terminal' '    echo "  DISCORD_WEBHOOK_URL_INPUT=<webhook-url> discord-setup.sh write-env <guild_id>"
    echo "Your stdin is not a terminal')"
dw_devnull_run "DISCORD_BOT_TOKEN_INPUT=$DISC_TOK" -- bash "$M" write-env "$GUILD"
check "mutant: the inline-assignment form restored into the non-TTY remedy: only the no-inline conjunct is RED (the file form and the token are still there)" \
  bash -c '[[ "$1" -eq 64 ]]' _ "$RC"
check "mutant: that inline-form mutant still has the file-read form and names the token (only the no-inline conjunct fails)" \
  bash -c '[[ "$1" == *"$2"* ]]' _ "$OUT" "$DW_FILEFORM"
check "mutant: that inline-form mutant is caught by dw_no_inline alone" not dw_no_inline
check "mutant: that inline-form mutant makes dw_remedy_non_tty RED" not dw_remedy_non_tty
# (b) the printf/$URL pipe form comes back (it does not match the VAR=value regex: the printf conjunct).
M="$(mut_make discord-setup.sh '    echo "Your stdin is not a terminal' '    echo "  printf %s \"\$URL\" | { read -r DISCORD_WEBHOOK_URL_INPUT; export DISCORD_WEBHOOK_URL_INPUT; discord-setup.sh write-env <guild_id>; }"
    echo "Your stdin is not a terminal')"
dw_devnull_run "DISCORD_BOT_TOKEN_INPUT=$DISC_TOK" -- bash "$M" write-env "$GUILD"
check "mutant: the printf-pipe form restored: it carries no VAR=value word, so the printf/\$URL arm alone catches it" \
  bash -c '[[ ! "$1" =~ $2 && "$1" == *printf* ]]' _ "$OUT" "$DW_INLINE_RE"
check "mutant: that printf-pipe mutant is caught by dw_no_inline (through its printf/\$URL arm)" not dw_no_inline
check "mutant: that printf-pipe mutant makes dw_remedy_non_tty RED" not dw_remedy_non_tty
# (c) the bot token dropped from the remedy: the names-the-token conjunct.
M="$(mut_make discord-setup.sh '  echo "  read -rs DISCORD_BOT_TOKEN_INPUT; export DISCORD_BOT_TOKEN_INPUT"
' '')"
dw_devnull_run "DISCORD_BOT_TOKEN_INPUT=$DISC_TOK" -- bash "$M" write-env "$GUILD"
check "mutant: the remedy without the bot-token line: dw_names_token is RED (the rest of the remedy is intact)" not dw_names_token
check "mutant: that token-less remedy still has no inline form (the other conjunct is not the one failing)" dw_no_inline
# (e) every remaining conjunct, one mutant each that breaks ONLY it. The control runs first: the real
# script has every conjunct green. Each from-string starts at the echo (the header comment of the
# script carries near-copies of these texts, so a bare substring would land in the comment).
dw_devnull_run "DISCORD_BOT_TOKEN_INPUT=$DISC_TOK" -- bash "$DISCORD_SETUP" write-env "$GUILD"
check "conjunct control: the real script gives the non-TTY remedy with every conjunct green (the named set below is empty)" test -z "$(dw_failed)"
check "conjunct control: the conjunct list is the eleven predicates (a dropped name cannot hide a mutant)" test "${#DW_CONJ[@]}" -eq 11
dw_alone_mut() { # <label> <the one conjunct expected to fail> <from> <to>
  local M; M="$(mut_make discord-setup.sh "$3" "$4")"
  dw_devnull_run "DISCORD_BOT_TOKEN_INPUT=$DISC_TOK" -- bash "$M" write-env "$GUILD"
  check "mutant: $1: exit 64 still (the usage class), so only the remedy text moved" test "$RC" -eq 64
  check "mutant: $1: exactly $2 fails and no other conjunct" test "$(dw_failed)" = "$2"
  check "mutant: $1: dw_remedy_non_tty is RED" not dw_remedy_non_tty
}
dw_alone_mut "the file-read line no longer exports the bot token" dw_c_fileform \
  'echo "  ( read -r DISCORD_WEBHOOK_URL_INPUT < /path/to/webhook-url.txt; read -r DISCORD_BOT_TOKEN_INPUT < /path/to/bot-token.txt; export DISCORD_WEBHOOK_URL_INPUT DISCORD_BOT_TOKEN_INPUT;' \
  'echo "  ( read -r DISCORD_WEBHOOK_URL_INPUT < /path/to/webhook-url.txt; read -r DISCORD_BOT_TOKEN_INPUT < /path/to/bot-token.txt; export DISCORD_WEBHOOK_URL_INPUT;'
dw_alone_mut "the remedy does not say stdin is not a terminal" dw_c_nontty \
  'echo "Your stdin is not a terminal, so' 'echo "Your stdin is a pipe, so'
dw_alone_mut "create-webhook output is no longer redirected into the file (the URL would print)" dw_c_createwh \
  'discord-setup.sh create-webhook <channel_id> > /path/to/webhook-url.txt )' 'discord-setup.sh create-webhook <channel_id> )'
dw_alone_mut "the webhook-file recipe lost its umask (a 0644 file)" dw_c_umask_hook \
  'echo "  (umask 077; cat > /path/to/webhook-url.txt)"' 'echo "  (cat > /path/to/webhook-url.txt)"'
dw_alone_mut "the bot-token-file recipe lost its umask (a 0644 file)" dw_c_umask_token \
  'echo "  (umask 077; cat > /path/to/bot-token.txt)"' 'echo "  (cat > /path/to/bot-token.txt)"'
dw_alone_mut "the existing-file chmod note is gone (a redirect keeps a wider mode)" dw_c_chmod \
  'run chmod 600 on it before writing' 'write to it'
dw_alone_mut "create-webhook is no longer given the bot token" dw_c_cw_token \
  'export DISCORD_BOT_TOKEN_INPUT; umask 077; discord-setup.sh create-webhook' 'umask 077; discord-setup.sh create-webhook'
dw_alone_mut "the one-command form lost its opening parenthesis (the exports would stay in the invoking shell)" dw_c_wrap_open \
  'echo "  ( read -r DISCORD_WEBHOOK_URL_INPUT <' 'echo "  read -r DISCORD_WEBHOOK_URL_INPUT <'
dw_alone_mut "the one-command form lost its closing parenthesis (the exports would stay in the invoking shell)" dw_c_wrap_close \
  'discord-setup.sh write-env <guild_id> )"' 'discord-setup.sh write-env <guild_id>"'
# (d) no guild_id: the usage branch reverted to a bash parameter error.
M="$(mut_make discord-setup.sh 'if [[ $# -eq 0 ]]; then' 'if false; then')"
dw_devnull_run "DISCORD_BOT_TOKEN_INPUT=$DISC_TOK" "DISCORD_WEBHOOK_URL_INPUT=$DW_URL" -- bash "$M" write-env
check "mutant: discord-setup without the no-guild_id branch exits non-64 (RED on the exit-64 row)" bash -c '[[ "$1" -ne 64 ]]' _ "$RC"
check "mutant: that no-guild_id mutant has no usage text on stdout (RED on the stdout row)" bash -c '[[ "$1" != *"Error: guild_id is missing"* ]]' _ "$OUT"
# The snowflake echo restored: the webhook URL in the guild_id slot is printed.
M="$(mut_make discord-setup.sh 'must be numeric. The value is not shown." >&2' 'must be numeric. Got: ${id}" >&2')"
dw_untouched_run "DISCORD_BOT_TOKEN_INPUT=$DISC_TOK" "DISCORD_WEBHOOK_URL_INPUT=$DW_URL" -- bash "$M" write-env "$DW_URL"
check "mutant: discord-setup echoing 'Got: <value>' again prints the webhook URL (exit 1 still; RED on the redaction rows)" \
  bash -c '[[ "$1" -eq 1 ]]' _ "$RC"
check "mutant: that Got-echo mutant leaks the URL, so the redaction row would be RED" not dw_no_secret
# The bot-token exit class: back to the generic exit 1.
M="$(mut_make discord-setup.sh 'is not set (or is empty). Pass the bot token in that environment variable, not as an argument."
    _print_env_remedy
    exit 64' 'is not set (or is empty). Pass the bot token in that environment variable, not as an argument."
    _print_env_remedy
    exit 1')"
dw_untouched_run "DISCORD_WEBHOOK_URL_INPUT=$DW_URL" -- bash "$M" write-env "$GUILD"
check "mutant: discord-setup with the missing-bot-token exit class back to 1 is RED on the exit-64 row" bash -c '[[ "$1" -eq 1 ]]' _ "$RC"
# The missing-token branch without its remedy (the pre-fix shape: usage + error only, no form to follow).
M="$(mut_make discord-setup.sh 'is not set (or is empty). Pass the bot token in that environment variable, not as an argument."
    _print_env_remedy
    exit 64' 'is not set (or is empty). Pass the bot token in that environment variable, not as an argument."
    exit 64')"
dw_untouched_run "DISCORD_WEBHOOK_URL_INPUT=$DW_URL" -- bash "$M" write-env "$GUILD"
check "mutant: discord-setup whose missing-bot-token branch prints no remedy still exits 64 (so only the remedy rows can catch it)" bash -c '[[ "$1" -eq 64 ]]' _ "$RC"
check "mutant: that remedy-less missing-bot-token mutant is RED on dw_names_token" not dw_names_token
# The human text of write-env on STDOUT (missing credentials, the confirmation): each moved line put back on stderr is RED.
xs_ok_env=("X_API_KEY=$XS_K" "X_API_SECRET=$XS_S" "X_ACCESS_TOKEN=$XS_T" "X_ACCESS_TOKEN_SECRET=$XS_TS")
M="$(mut_make x-setup.sh 'require_credentials 2>&1' 'require_credentials')"
RUN_CWD="$GITWORK" run_sut - "" "X_API_KEY=$XS_K" "X_API_SECRET=$XS_S" "X_ACCESS_TOKEN=$XS_T" -- bash "$M" write-env
check "mutant: x-setup write-env with the missing-credentials text back on stderr is RED on the stdout row (still exit 1)" \
  bash -c '[[ "$1" -eq 1 ]]' _ "$RC"
check "mutant: that stderr-diagnostic x-setup mutant fails we_missing_stdout" not we_missing_stdout X_ACCESS_TOKEN_SECRET
M="$(mut_make x-setup.sh 'echo "Wrote 4 variables to ${env_file} (permissions: 600)"' 'echo "Wrote 4 variables to ${env_file} (permissions: 600)" >&2')"
RUN_CWD="$GITWORK" run_sut - "" "${xs_ok_env[@]}" -- bash "$M" write-env
check "mutant: x-setup write-env with the confirmation back on stderr still exits 0" bash -c '[[ "$1" -eq 0 ]]' _ "$RC"
check "mutant: that stderr-confirmation x-setup mutant fails we_wrote_stdout" not we_wrote_stdout 4
M="$(mut_make bsky-setup.sh 'require_credentials 2>&1' 'require_credentials')"
RUN_CWD="$GITWORK" run_sut - "" "BSKY_HANDLE=$BSKY_HANDLE_FIX" -- bash "$M" write-env
check "mutant: bsky-setup write-env with the missing-credentials text back on stderr is RED on the stdout row (still exit 1)" \
  bash -c '[[ "$1" -eq 1 ]]' _ "$RC"
check "mutant: that stderr-diagnostic bsky-setup mutant fails we_missing_stdout" not we_missing_stdout BSKY_APP_PASSWORD
# The missing-credentials advice (stdout of write-env) points at the no-history form, never an inline assignment.
xs_advice_ok() { [[ "$OUT" == *"read -rs X_API_KEY; export X_API_KEY"* && "$OUT" == *"kept in the transcript and the shell history"* && "$OUT" != *"X_API_KEY="* ]]; }
bs_advice_ok() { [[ "$OUT" == *"read -rs BSKY_APP_PASSWORD; export BSKY_APP_PASSWORD"* && "$OUT" == *"kept in the transcript and the shell history"* && "$OUT" != *"BSKY_APP_PASSWORD="* ]]; }
RUN_CWD="$GITWORK" run_sut - "" "X_API_KEY=$XS_K" "X_API_SECRET=$XS_S" "X_ACCESS_TOKEN=$XS_T" -- bash "$X_SETUP" write-env
check "x-setup write-env with a credential missing: exit 1 and the advice shows the read -rs form and no inline assignment" bash -c '[[ "$1" -eq 1 ]]' _ "$RC"
check "x-setup write-env with a credential missing: the advice text is read -rs, the transcript/history reason, no X_API_KEY=" xs_advice_ok
M="$(mut_make x-setup.sh ', without typing a value into the command (its text is kept in the transcript and the shell history): in a terminal, read -rs X_API_KEY; export X_API_KEY, and the same for each of the other three' '')"
RUN_CWD="$GITWORK" run_sut - "" "X_API_KEY=$XS_K" "X_API_SECRET=$XS_S" "X_ACCESS_TOKEN=$XS_T" -- bash "$M" write-env
check "mutant: x-setup with the bare 'Export them as environment variables' advice back is RED on the advice row (still exit 1)" bash -c '[[ "$1" -eq 1 ]]' _ "$RC"
check "mutant: that bare-advice x-setup mutant fails xs_advice_ok" not xs_advice_ok
RUN_CWD="$GITWORK" run_sut - "" "BSKY_HANDLE=$BSKY_HANDLE_FIX" -- bash "$BSKY_SETUP" write-env
check "bsky-setup write-env with a credential missing: exit 1" bash -c '[[ "$1" -eq 1 ]]' _ "$RC"
check "bsky-setup write-env with a credential missing: the advice text is read -rs, the transcript/history reason, no BSKY_APP_PASSWORD=" bs_advice_ok
M="$(mut_make bsky-setup.sh ', without typing a value into the command (its text is kept in the transcript and the shell history): in a terminal, read -rs BSKY_APP_PASSWORD; export BSKY_APP_PASSWORD' '')"
RUN_CWD="$GITWORK" run_sut - "" "BSKY_HANDLE=$BSKY_HANDLE_FIX" -- bash "$M" write-env
check "mutant: bsky-setup with the bare 'Export ... as environment variables' advice back is RED on the advice row (still exit 1)" bash -c '[[ "$1" -eq 1 ]]' _ "$RC"
check "mutant: that bare-advice bsky-setup mutant fails bs_advice_ok" not bs_advice_ok
# The same advice in the two community scripts (stderr, exit 1).
xs_advice_all_ok() { [[ "$OUT$ERR" == *"read -rs X_API_KEY; export X_API_KEY"* && "$OUT$ERR" == *"kept in the transcript and the shell history"* && "$OUT$ERR" != *"X_API_KEY="* ]]; }
bs_advice_all_ok() { [[ "$OUT$ERR" == *"read -rs BSKY_APP_PASSWORD; export BSKY_APP_PASSWORD"* && "$OUT$ERR" == *"kept in the transcript and the shell history"* && "$OUT$ERR" != *"BSKY_APP_PASSWORD="* ]]; }
run_sut - "" -- bash "$X_COMMUNITY" fetch-metrics
check "x-community with no credentials: exit 1, curl never invoked, and the advice shows the read -rs form and no inline assignment" \
  bash -c '[[ "$1" -eq 1 && "$2" -eq 0 ]]' _ "$RC" "$(curl_calls)"
check "x-community with no credentials: the advice text is read -rs, the transcript/history reason, no X_API_KEY=" xs_advice_all_ok
M="$(mut_make x-community.sh ', without typing a value into the command (its text is kept in the transcript and the shell history): in a terminal, read -rs X_API_KEY; export X_API_KEY, and the same for each of the other three' '')"
run_sut - "" -- bash "$M" fetch-metrics
check "mutant: x-community with the bare advice back is RED on the advice row (still exit 1)" bash -c '[[ "$1" -eq 1 ]]' _ "$RC"
check "mutant: that bare-advice x-community mutant fails xs_advice_all_ok" not xs_advice_all_ok
run_sut - "" -- bash "$BSKY_COMMUNITY" create-session
check "bsky-community with no credentials: exit 1, curl never invoked" bash -c '[[ "$1" -eq 1 && "$2" -eq 0 ]]' _ "$RC" "$(curl_calls)"
check "bsky-community with no credentials: the advice text is read -rs, the transcript/history reason, no BSKY_APP_PASSWORD=" bs_advice_all_ok
M="$(mut_make bsky-community.sh ', without typing a value into the command (its text is kept in the transcript and the shell history): in a terminal, read -rs BSKY_APP_PASSWORD; export BSKY_APP_PASSWORD' '')"
run_sut - "" -- bash "$M" create-session
check "mutant: bsky-community with the bare advice back is RED on the advice row (still exit 1)" bash -c '[[ "$1" -eq 1 ]]' _ "$RC"
check "mutant: that bare-advice bsky-community mutant fails bs_advice_all_ok" not bs_advice_all_ok
M="$(mut_make bsky-setup.sh 'echo "Wrote 2 variables to ${env_file} (permissions: 600)"' 'echo "Wrote 2 variables to ${env_file} (permissions: 600)" >&2')"
RUN_CWD="$GITWORK" run_sut - "" "BSKY_HANDLE=$BSKY_HANDLE_FIX" "BSKY_APP_PASSWORD=$BSKY_PW_FIX" -- bash "$M" write-env
check "mutant: bsky-setup write-env with the confirmation back on stderr still exits 0" bash -c '[[ "$1" -eq 0 ]]' _ "$RC"
check "mutant: that stderr-confirmation bsky-setup mutant fails we_wrote_stdout" not we_wrote_stdout 2
M="$(mut_make discord-setup.sh 'echo "Wrote ${var_count} variables to ${env_file} (permissions: 600)"' 'echo "Wrote ${var_count} variables to ${env_file} (permissions: 600)" >&2')"
RUN_CWD="$GITWORK" run_sut - "" "${WE_BASE[@]}" -- bash "$M" write-env "$GUILD"
check "mutant: discord-setup write-env with the confirmation back on stderr still exits 0" bash -c '[[ "$1" -eq 0 ]]' _ "$RC"
check "mutant: that stderr-confirmation discord-setup mutant fails we_wrote_stdout" not we_wrote_stdout 5
# The usage table: every command row's " - " separator sits in one column (the verify row had lost a space).
RUN_CWD="$GITWORK" run_sut - "" -- bash "$DISCORD_SETUP"
dw_usage_aligned() { # <usage-text>: six command rows, one separator column
  awk '/^  [a-z]/ { c = index($0, " - "); if (c == 0) bad = 1; if (col == 0) col = c; else if (c != col) bad = 1; n++ } END { exit !(n == 6 && !bad) }' <<<"$1"
}
check "discord-setup usage: exit 1 with the table on stderr, nothing on stdout" bash -c '[[ "$1" -eq 1 && -z "$2" ]]' _ "$RC" "$OUT"
check "discord-setup usage: the six command rows share one separator column" dw_usage_aligned "$ERR"
M="$(mut_make discord-setup.sh "echo \"  verify$(printf '%26s' '')- Run" "echo \"  verify$(printf '%25s' '')- Run")"
RUN_CWD="$GITWORK" run_sut - "" -- bash "$M"
check "mutant: discord-setup usage with the verify row one column short is RED on the alignment row" not dw_usage_aligned "$ERR"
# Positive control for the sentinel mechanism itself: a known-bad .env fires it, a clean one does not.
printf 'PC=$(touch %s)\n' "$SENT" > "$GITWORK/.env"
check "sentinel control: sourcing a known-bad .env fires the sentinel (the mechanism is real)" we_fired
printf 'PC=clean\n' > "$GITWORK/.env"
check "sentinel control: sourcing a clean .env does not fire it" not we_fired
rm -f "$GITWORK/.env" "$SENT"

# --- the oracle under other bash builds ---------------------------------------------------------
echo "== hmac-sha1-b64.sh: the oracle under the oldest bash and inside the pinned image =="
bash_num() { "$1" -c 'echo $((BASH_VERSINFO[0] * 100 + BASH_VERSINFO[1]))' 2>/dev/null; }
OLD_BASH="" OLD_NUM=9999
for cand_ in $(type -ap bash) /bin/bash /usr/bin/bash /usr/local/bin/bash /opt/homebrew/bin/bash; do
  [[ -x "$cand_" ]] || continue
  v_="$(bash_num "$cand_")"; [[ "$v_" =~ ^[0-9]+$ ]] || continue
  if (( v_ < OLD_NUM )); then OLD_NUM=$v_; OLD_BASH="$cand_"; fi
done
DEF_NUM=$((BASH_VERSINFO[0] * 100 + BASH_VERSINFO[1]))
if (( OLD_NUM < DEF_NUM )); then
  OLD_OUT="$("$OLD_BASH" "${BASH_SOURCE[0]}" --oracle-only 2>&1)"; OLD_RC=$?
  check "oracle under the oldest bash on this host ($OLD_BASH, ${OLD_NUM}): all 67 comparisons equal the reference" \
    bash -c '[[ "$1" -eq 0 && "$2" == *" cases=67 "* && "$2" == *" bad=0"* ]]' _ "$OLD_RC" "$OLD_OUT"
  echo "  note - oldest bash ${OLD_NUM} is older than the default ${DEF_NUM}: exercised"
else
  # The running bash IS the oldest here, so a child --oracle-only pass would repeat the in-process
  # matrix above byte for byte (a second full pass for nothing): reuse that run's counters instead.
  echo "  note - the oldest bash on this host (${OLD_NUM}) is the running bash: no second pass; an OLDER bash (macOS 3.2) was NOT exercised here"
  check "oracle under the oldest bash on this host (the running bash ${DEF_NUM}; the in-process matrix above is that run): all 67 comparisons equal the reference" \
    bash -c '[[ "$1" -eq 67 && "$2" -eq 0 ]]' _ "$ORC_RAN" "$ORC_BAD"
fi
# The pinned base image has NO openssl of its own (measured); the runner image gets it from the
# `ca-certificates` package its Dockerfile installs, which depends on it. So the run installs that one
# package first. That needs the network and a pull, so it is opt-in: COMMUNITY_ARGV_DOCKER=1. Without
# it (or without docker) the row reports "not exercised" and still counts as one row.
IMG_STATE="not exercised (needs docker and COMMUNITY_ARGV_DOCKER=1: the pinned image has no openssl, so the run installs ca-certificates, as the runner Dockerfile does)"
IMG_OUT="" IMG_RC=0
if [[ -n "${COMMUNITY_ARGV_DOCKER:-}" ]] && command -v docker >/dev/null 2>&1; then
  IMG_OUT="$(docker run --rm -v "$HERE/..:/skill:ro" "$PINNED_IMAGE" bash -c 'apt-get update -qq >/dev/null 2>&1 && apt-get install -y -qq --no-install-recommends ca-certificates >/dev/null 2>&1 && command -v openssl >/dev/null && bash /skill/test/community-argv.test.sh --oracle-only' 2>&1)"; IMG_RC=$?
  IMG_STATE="exercised"
fi
if [[ "$IMG_STATE" == exercised ]]; then
  check "oracle inside the pinned node:22-slim image (the hosted bash 5.2): all 67 comparisons equal the reference" \
    bash -c '[[ "$1" -eq 0 && "$2" == *" cases=67 "* && "$2" == *" bad=0"* ]]' _ "$IMG_RC" "$IMG_OUT"
else
  echo "  note - oracle inside the pinned image: $IMG_STATE"
  check "oracle inside the pinned image: not exercised on this host, and the image reference is still digest-pinned (a floating tag would silently change the bash the oracle runs under)" \
    bash -c '[[ "$1" =~ ^node:22-slim@sha256:[0-9a-f]{64}$ ]]' _ "$PINNED_IMAGE"
fi
# The image this oracle runs in is the image the repo BUILDS: compare PINNED_IMAGE with the FROM line(s)
# of apps/web-platform/Dockerfile (read-only here), so a Dockerfile bump cannot leave the oracle on the
# old image with a green row, and a different 64-hex digest cannot satisfy it.
DOCKERFILE_REL="../../../../../apps/web-platform/Dockerfile"
dockerfile_pins_image() { # <Dockerfile>: every `FROM node:22-slim@sha256:...` line carries exactly PINNED_IMAGE, and there is at least one
  local imgs; imgs="$(awk '/^FROM node:22-slim@sha256:/ { print $2 }' "$1" 2>/dev/null | sort -u)"
  [[ -n "$imgs" && "$imgs" == "$PINNED_IMAGE" ]]
}
check "pinned image: PINNED_IMAGE equals the node:22-slim digest of every FROM line in apps/web-platform/Dockerfile (not a literal that only this file checks)" \
  dockerfile_pins_image "$HERE/$DOCKERFILE_REL"
mkdir -p "$SANDBOX/dockerfile"
# The tamper rewrites the FIRST digest character of every FROM line to a different one, whatever it is
# (a digest bump changes the leading character, and a tamper keyed on one hard-coded character would then
# read RED as an instrument error). 0 becomes 1; any other character becomes 0.
tamper_digest() { # <in> <out>
  sed -E -e 's/^(FROM node:22-slim@sha256:)0/\11/' -e t -e 's/^(FROM node:22-slim@sha256:)[^0]/\10/' "$1" > "$2"
}
tamper_digest "$HERE/$DOCKERFILE_REL" "$SANDBOX/dockerfile/Dockerfile.bumped"
tamper_all_hex() { # every leading hex digit is changed by tamper_digest, on a synthetic one-line Dockerfile
  local c n=0
  for c in 0 1 2 3 4 5 6 7 8 9 a b c d e f; do
    printf 'FROM node:22-slim@sha256:%s%s AS base\n' "$c" "$(printf '%063d' 0)" > "$SANDBOX/dockerfile/lead.in"
    tamper_digest "$SANDBOX/dockerfile/lead.in" "$SANDBOX/dockerfile/lead.out"
    cmp -s "$SANDBOX/dockerfile/lead.in" "$SANDBOX/dockerfile/lead.out" && return 1
    n=$((n + 1))
  done
  [[ "$n" -eq 16 ]]
}
check "pinned image: the tamper changes the leading digest character for each of the sixteen hex digits (it does not depend on the current digest)" tamper_all_hex
check "pinned image: the doctored Dockerfile (one digest character changed on every FROM line) differs from the real one" not cmp -s "$HERE/$DOCKERFILE_REL" "$SANDBOX/dockerfile/Dockerfile.bumped"
check "pinned image: a Dockerfile whose digest moved on is RED (PINNED_IMAGE no longer matches)" not dockerfile_pins_image "$SANDBOX/dockerfile/Dockerfile.bumped"
check "pinned image: a Dockerfile with no node:22-slim FROM line is RED (an empty comparison cannot pass)" not dockerfile_pins_image /dev/null
echo
echo "community-argv.test.sh: $PASS passed, $FAIL failed"
# Exact count, in the pre-existing guard-invisible form: a lower-case `-lt` floor would make this
# `plugins/soleur/skills/*/test/` suite floor-bearing, which grows the DEFERRED ledger in
# scripts/guard-vacuity-floor.test.sh (47 -> 48) until the file is promoted there.
if [[ "$((PASS + FAIL))" -ne 1227 ]]; then
  printf 'ANTI-VACUITY FLOOR: ran %s assertions, expected exactly 1227\n' "$((PASS + FAIL))" >&2
  exit 1
fi
[[ "$FAIL" -eq 0 ]]
