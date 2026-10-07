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

for dep in jq openssl; do
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

echo
echo "community-argv.test.sh: $PASS passed, $FAIL failed"
# Exact count, in the pre-existing guard-invisible form: a lower-case `-lt` floor would make this
# `plugins/soleur/skills/*/test/` suite floor-bearing, which grows the DEFERRED ledger in
# scripts/guard-vacuity-floor.test.sh (47 -> 48) until the file is promoted there.
if [[ "$((PASS + FAIL))" -ne 411 ]]; then
  printf 'ANTI-VACUITY FLOOR: ran %s assertions, expected exactly 411\n' "$((PASS + FAIL))" >&2
  exit 1
fi
[[ "$FAIL" -eq 0 ]]
