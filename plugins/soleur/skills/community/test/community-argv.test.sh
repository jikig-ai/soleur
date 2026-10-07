#!/usr/bin/env bash
# Hermetic argv-hygiene test for the community scripts' credential-bearing curl calls
# (#9597): linkedin-setup.sh (client secret + introspected token, both as form fields),
# the OAuth 1.0a Authorization header in x-community.sh and x-setup.sh, the Discord Bot
# token in discord-community.sh and discord-setup.sh, and the Bluesky createSession body
# (handle + app password) in bsky-community.sh and bsky-setup.sh.
#
# A PATH-shim `curl` records its argv NUL-delimited and, when asked for `--config -`,
# its stdin, and, for `--data-binary @file`, the body file's content and `stat` mode AT
# CURL TIME (the file is gone by the time the script exits). A PATH-shim `jq` records its
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
  # `--data-binary @file` keeps CR/LF (real curl); the body file's content and mode are read NOW.
  if [[ "$prev" == "--data-binary" && "$a" == @* && "${SHIM_MUTATE:-}" != nobody ]]; then
    f="${a#@}"
    cp -- "$f" "$d/body.$n" 2>/dev/null
    { stat -c %a -- "$f" 2>/dev/null || stat -f %Lp -- "$f" 2>/dev/null; } > "$d/bodymode.$n"
    printf '%s\n' "$f" > "$d/bodypath.$n"
  fi
  prev="$a"
  [[ "$a" == http*://* ]] && url="$a"
done
[[ "${SHIM_MODE:-}" == fail7 ]] && exit 7
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
  rm -f "$MOCK"/count "$MOCK"/argv.* "$MOCK"/stdin.* "$MOCK"/env.* "$MOCK"/body.* "$MOCK"/bodymode.* \
    "$MOCK"/bodypath.* "$MOCK"/jqcount "$MOCK"/jqargv.* "$MOCK"/jqenv.*
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

# ===================================================================================
echo "== linkedin-setup.sh validate-credentials =="
LI_SECRET="fixturefixturefixture01"
LI_TOKEN="synthetic-fixture-token-0001"
LI_ENV=(LINKEDIN_CLIENT_ID=synthetic-fixture-client-0001
        "LINKEDIN_CLIENT_SECRET=$LI_SECRET" "LINKEDIN_ACCESS_TOKEN=$LI_TOKEN")

run_sut - "" "${LI_ENV[@]}" -- bash "$LINKEDIN_SETUP" validate-credentials
check "valid: exits 0" test "$RC" -eq 0
check "valid: exactly one curl call" test "$(curl_calls)" -eq 1
check "valid: client secret absent from argv" not argv_has "$LI_SECRET"
check "valid: introspected token absent from argv" not argv_has "$LI_TOKEN"
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
check "generate-token: client secret absent from argv (both calls)" not argv_has "$LI_SECRET"
check "generate-token: access token from the reply absent from argv" not argv_has "synthetic-fixture-token-0002"
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
  check "$label: signed header absent from argv" not argv_has "oauth_signature" "$n"
  check "$label: Authorization header text absent from argv" not argv_has "Authorization: OAuth" "$n"
  check "$label: consumer key absent from argv" not argv_has "$X_KEY" "$n"
  check "$label: access token absent from argv" not argv_has "$X_TOK" "$n"
  check "$label: consumer secret absent from argv" not argv_has "$X_SECRET" "$n"
  check "$label: token secret absent from argv" not argv_has "$X_TOKSECRET" "$n"
  check "$label: consumer + token secrets never reach curl at all (argv and stdin)" \
    bash -c '! grep -aqF -e "$1" -e "$2" -- "$3" "$4"' _ "$X_SECRET" "$X_TOKSECRET" "$MOCK/argv.$n" "$MOCK/stdin.$n"
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
mkdir -p "$SANDBOX/tmp"

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
chk_bot_stdin() { test "$(stdin_text "$1")" = "header = \"Authorization: Bot $2\""; }

# bot_call_checks <label> <n> <token>: the argv/stdin contract of one Discord call.
bot_call_checks() {
  local label="$1" n="$2" tok="$3"
  check "$label: bot token absent from argv" not argv_has "$tok" "$n"
  check "$label: Authorization header text absent from argv" not argv_has "Authorization" "$n"
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
  check "discord-community token ($cls): exit 1 and the exact value-free refusal line on stderr" \
    bash -c '[[ "$1" -eq 1 ]]' _ "$RC"
  check "discord-community token ($cls): refusal marker line is exact" refusal_line discord-community.sh
  check "discord-community token ($cls): curl never invoked" test "$(curl_calls)" -eq 0
  check "discord-community token ($cls): no leak of the value" no_leak
  check "discord-community token ($cls): not the transport diagnostic" no_diag
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
  check "discord-setup token ($cls): exit 1" bash -c '[[ "$1" -eq 1 ]]' _ "$RC"
  check "discord-setup token ($cls): refusal marker line is exact" refusal_line discord-setup.sh
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
RUN_CWD="$GITWORK" run_sut - "" "${DS_ENV[@]}" SHIM_MODE=fail7 -- bash "$DISCORD_SETUP" validate-token
check "discord-setup connect failure without a proxy: exit 1, no proxy claim" \
  bash -c '[[ "$1" -eq 1 ]] && ! grep -qF "bypasses your proxy" <<<"$2"' _ "$RC" "$ERR"

# --- harness rows: a shim that stops recording stdin turns the Discord stdin row RED -------
run_sut - "" "${DC_ENV[@]}" SHIM_MUTATE=nostdin -- bash "$DISCORD_COMMUNITY" guild-info
check "harness: a shim that stops recording stdin makes the Discord stdin row RED" not chk_bot_stdin 1 "$DISC_TOK"

# ===================================================================================
echo "== bsky-community.sh createSession =="
BC_ENV=("BSKY_HANDLE=$BSKY_HANDLE_FIX" "BSKY_APP_PASSWORD=$BSKY_PW_FIX" "TMPDIR=$SANDBOX/tmp")

# body_arg <n>: the operand after --data-binary on call n.
body_arg() {
  local -a a=(); local i
  mapfile -d '' -t a < "$MOCK/argv.$1"
  for (( i = 0; i < ${#a[@]} - 1; i++ )); do
    [[ "${a[i]}" == "--data-binary" ]] && { printf '%s' "${a[i+1]}"; return 0; }
  done
  return 1
}
chk_body_ok() { # <n> <handle> <password>
  [[ -s "$MOCK/body.$1" ]] && jq -e --arg h "$2" --arg p "$3" '.identifier == $h and .password == $p' "$MOCK/body.$1" >/dev/null 2>&1
}
jq_argv_has() { local f; for f in "$MOCK"/jqargv.*; do [[ -e "$f" ]] && grep -aqF -e "$1" -- "$f" && return 0; done; return 1; }
jq_calls() { cat "$MOCK/jqcount" 2>/dev/null || echo 0; }
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
tmp_empty() { [[ -z "$(ls -A "$SANDBOX/tmp")" ]]; }

# bsky_body_checks <label> <n> <handle> <password>
bsky_body_checks() {
  local label="$1" n="$2" h="$3" pw="$4" bp
  bp="$(body_arg "$n" || true)"
  check "$label: password absent from argv" not argv_has "$pw" "$n"
  check "$label: handle absent from argv" not argv_has "$h" "$n"
  check "$label: --disable --noproxy '*' lead argv" test "$(argv_first3 "$n")" = "--disable --noproxy *"
  check "$label: body sent as --data-binary @<file> under TMPDIR" \
    bash -c '[[ "$1" == "@$2/bsky-body."* ]]' _ "$bp" "$SANDBOX/tmp"
  check "$label: body file mode is 0600 AT CURL TIME" test "$(cat "$MOCK/bodymode.$n" 2>/dev/null)" = "600"
  check "$label: body file held exactly the handle and password at curl time" chk_body_ok "$n" "$h" "$pw"
  check "$label: explicit JSON Content-Type" argv_has "Content-Type: application/json" "$n"
}

run_sut - "" "${BC_ENV[@]}" -- bash "$BSKY_COMMUNITY" create-session
check "bsky-community create-session: exit 0" test "$RC" -eq 0
check "bsky-community create-session: exactly one curl call" test "$(curl_calls)" -eq 1
check "bsky-community create-session: the session DID still reaches stdout" grep -qF "did:plc:synth0001" <<<"$OUT"
bsky_body_checks "bsky-community create-session" 1 "$BSKY_HANDLE_FIX" "$BSKY_PW_FIX"
check "bsky-community create-session: body file removed on exit" bash -c '[[ ! -e "${1#@}" ]]' _ "$(body_arg 1 || echo @/nonexistent-sentinel-x)"
check "bsky-community create-session: no body file left under TMPDIR" tmp_empty
check "bsky-community create-session: password absent from every jq argv (jq shim)" not jq_argv_has "$BSKY_PW_FIX"
check "bsky-community create-session: handle absent from every jq argv (jq shim)" not jq_argv_has "$BSKY_HANDLE_FIX"
check "bsky-community create-session: jq shim recorded calls and the writer reads \$ENV.BSKY_PW (recording works)" \
  bash -c '[[ "$1" -ge 2 ]]' _ "$(jq_calls)"
check "bsky-community create-session: the writer jq inherits both variable names" jq_writer_env_ok
check "bsky-community create-session: no other jq child inherits them" jq_others_env_clean
check "bsky-community create-session: the curl child does not inherit them" curl_env_clean

# handle with a double quote: escaped by jq, never injectable
run_sut - "" "BSKY_HANDLE=syn\"thetic.bsky.social" "BSKY_APP_PASSWORD=$BSKY_PW_FIX" "TMPDIR=$SANDBOX/tmp" -- bash "$BSKY_COMMUNITY" create-session
# (The script's own session-echo line is not escaped, so its exit status is not asserted: that
# line is unreachable with a real session, since Bluesky would never mint one for this handle.)
check "bsky-community handle with a double quote: createSession is still sent exactly once" test "$(curl_calls)" -eq 1
check "bsky-community handle with a double quote: body decodes to exactly that handle (escaped, not injected)" \
  chk_body_ok 1 'syn"thetic.bsky.social' "$BSKY_PW_FIX"
# a handle or password with a control character is refused BEFORE curl; non-zero, never 0 or 3; marker on stderr
bsky_refused() { # <label> <handle> <password>
  run_sut - "" "BSKY_HANDLE=$2" "BSKY_APP_PASSWORD=$3" "TMPDIR=$SANDBOX/tmp" -- bash "$BSKY_COMMUNITY" create-session
  check "$1: exit 1 (non-zero, never 0 or 3)" test "$RC" -eq 1
  check "$1: curl never invoked" test "$(curl_calls)" -eq 0
  check "$1: exact value-free refusal marker on stderr" refusal_line bsky-community.sh
  check "$1: value never echoed" no_leak
  check "$1: no body file left behind" tmp_empty
}
bsky_refused "bsky-community handle with a newline" $'syn\nthetic'"$MARK" "$BSKY_PW_FIX"
bsky_refused "bsky-community password with a control character" "$BSKY_HANDLE_FIX" "$MARK"$'\x01'"x"
run_sut - "" "${BC_ENV[@]/TMPDIR=*/TMPDIR=$SANDBOX/no-such-dir}" -- bash "$BSKY_COMMUNITY" create-session
check "bsky-community body file cannot be created: exit 1, curl never invoked" \
  bash -c '[[ "$1" -eq 1 && "$2" -eq 0 ]]' _ "$RC" "$(curl_calls)"
check "bsky-community body file cannot be created: exact refusal marker on stderr" refusal_line bsky-community.sh body_write_failed

echo "== bsky-community.sh get-metrics and post =="
run_sut - "" "${BC_ENV[@]}" -- bash "$BSKY_COMMUNITY" get-metrics
check "bsky-community get-metrics: exit 0, two calls (createSession, getProfile)" bash -c '[[ "$1" -eq 0 && "$2" -eq 2 ]]' _ "$RC" "$(curl_calls)"
bsky_body_checks "bsky-community get-metrics createSession" 1 "$BSKY_HANDLE_FIX" "$BSKY_PW_FIX"
check "bsky-community get-metrics: the session bearer is the stdin header on the profile call (unchanged)" \
  test "$(stdin_text 2)" = "header = \"Authorization: Bearer $BSKY_JWT_FIX\""
check "bsky-community get-metrics: no body file left under TMPDIR" tmp_empty
run_sut - "" "${BC_ENV[@]}" BSKY_ALLOW_POST=true -- bash "$BSKY_COMMUNITY" post "synthetic post text"
check "bsky-community post (the hosted path): exit 0, two calls (createSession, createRecord)" bash -c '[[ "$1" -eq 0 && "$2" -eq 2 ]]' _ "$RC" "$(curl_calls)"
bsky_body_checks "bsky-community post createSession" 1 "$BSKY_HANDLE_FIX" "$BSKY_PW_FIX"
check "bsky-community post: the password never reaches the createRecord call either" not argv_has "$BSKY_PW_FIX" 2
run_sut - "" "BSKY_HANDLE=$BSKY_HANDLE_FIX" "BSKY_APP_PASSWORD=$MARK"$'\x01'"x" BSKY_ALLOW_POST=true "TMPDIR=$SANDBOX/tmp" -- bash "$BSKY_COMMUNITY" post "synthetic post text"
check "bsky-community post (hosted): a refused credential exits 1, never 0 or 3, curl never invoked" \
  bash -c '[[ "$1" -eq 1 && "$2" -eq 0 ]]' _ "$RC" "$(curl_calls)"
check "bsky-community post (hosted): the refusal marker reaches stderr, where content-publisher captures it" refusal_line bsky-community.sh

# --- harness row: a shim that stops reading the --data-binary body turns the body rows RED -----
run_sut - "" "${BC_ENV[@]}" SHIM_MUTATE=nobody -- bash "$BSKY_COMMUNITY" create-session
check "harness: a shim that stops reading the --data-binary body makes the body-content row RED" not chk_body_ok 1 "$BSKY_HANDLE_FIX" "$BSKY_PW_FIX"

echo "== bsky-setup.sh verify =="
# verify sources $GIT_ROOT/.env; the file is synthesized here and lives in the scratch checkout.
printf 'BSKY_HANDLE=%s\nBSKY_APP_PASSWORD=%s\n' "$BSKY_HANDLE_FIX" "$BSKY_PW_FIX" > "$GITWORK/.env"
RUN_CWD="$GITWORK" run_sut - "" "TMPDIR=$SANDBOX/tmp" -- bash "$BSKY_SETUP" verify
check "bsky-setup verify: exit 0, two calls (createSession, getProfile)" bash -c '[[ "$1" -eq 0 && "$2" -eq 2 ]]' _ "$RC" "$(curl_calls)"
bsky_body_checks "bsky-setup verify createSession" 1 "$BSKY_HANDLE_FIX" "$BSKY_PW_FIX"
check "bsky-setup verify: body file removed and nothing left under TMPDIR" tmp_empty
check "bsky-setup verify: password absent from every jq argv (jq shim)" not jq_argv_has "$BSKY_PW_FIX"
check "bsky-setup verify: handle absent from every jq argv (jq shim)" not jq_argv_has "$BSKY_HANDLE_FIX"
check "bsky-setup verify: the writer jq inherits the variable names" jq_writer_env_ok
check "bsky-setup verify: no other jq child inherits them" jq_others_env_clean
check "bsky-setup verify: the curl children do not inherit them" curl_env_clean
check "bsky-setup verify: the session bearer is the stdin header on the profile call (unchanged)" \
  test "$(stdin_text 2)" = "header = \"Authorization: Bearer $BSKY_JWT_FIX\""
printf 'BSKY_HANDLE=$%s\nBSKY_APP_PASSWORD=%s\n' "'syn\\001thetic${MARK}'" "$BSKY_PW_FIX" > "$GITWORK/.env"
RUN_CWD="$GITWORK" run_sut - "" "TMPDIR=$SANDBOX/tmp" -- bash "$BSKY_SETUP" verify
check "bsky-setup verify with a control character in the handle: exit 1, curl never invoked" \
  bash -c '[[ "$1" -eq 1 && "$2" -eq 0 ]]' _ "$RC" "$(curl_calls)"
check "bsky-setup verify with a control character in the handle: exact refusal marker on stderr" refusal_line bsky-setup.sh
check "bsky-setup verify with a control character in the handle: value not echoed" no_leak
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

# 4. The bsky password handed to curl as `-d "$body"`, to jq as `--arg`, or exported.
M="$(mut_make bsky-community.sh '--data-binary @"$BSKY_BODY_FILE" \' '-d "{\"identifier\": \"${BSKY_HANDLE}\", \"password\": \"${BSKY_APP_PASSWORD}\"}" \')"
run_sut - "" "${BC_ENV[@]}" -- bash "$M" create-session
check "mutant: bsky-community handing the password to curl as -d is RED (password in argv)" argv_has "$BSKY_PW_FIX" 1
check "mutant: bsky-community handing the password to curl as -d is RED (no --data-binary body file)" not chk_body_ok 1 "$BSKY_HANDLE_FIX" "$BSKY_PW_FIX"
M="$(mut_make bsky-community.sh \
  $'BSKY_ID="$BSKY_HANDLE" BSKY_PW="$BSKY_APP_PASSWORD" \\\n    jq -n \'{identifier: $ENV.BSKY_ID, password: $ENV.BSKY_PW}\'' \
  $'jq -n --arg id "$BSKY_HANDLE" --arg pw "$BSKY_APP_PASSWORD" \'{identifier: $id, password: $pw}\'')"
run_sut - "" "${BC_ENV[@]}" -- bash "$M" create-session
check "mutant: bsky-community passing the password to jq as --arg is RED (password on jq argv, jq shim)" jq_argv_has "$BSKY_PW_FIX"
check "mutant: bsky-community passing the password to jq as --arg is RED (the environment row loses its writer)" not jq_writer_env_ok
check "mutant: bsky-community passing the password to jq as --arg: the curl shim alone stays blind to it" not argv_has "$BSKY_PW_FIX" 1
M="$(mut_make bsky-community.sh $'  BSKY_ID="$BSKY_HANDLE" BSKY_PW="$BSKY_APP_PASSWORD" \\\n' $'  export BSKY_ID="$BSKY_HANDLE" BSKY_PW="$BSKY_APP_PASSWORD"; \\\n')"
run_sut - "" "${BC_ENV[@]}" -- bash "$M" create-session
check "mutant: bsky-community exporting the password is RED (the curl child inherits it)" not curl_env_clean
check "mutant: bsky-community exporting the password is RED (a later jq child inherits it)" not jq_others_env_clean
M="$(mut_make bsky-setup.sh '--data-binary @"$BSKY_BODY_FILE" \' '-d "{\"identifier\": \"${BSKY_HANDLE}\", \"password\": \"${BSKY_APP_PASSWORD}\"}" \')"
printf 'BSKY_HANDLE=%s\nBSKY_APP_PASSWORD=%s\n' "$BSKY_HANDLE_FIX" "$BSKY_PW_FIX" > "$GITWORK/.env"
RUN_CWD="$GITWORK" run_sut - "" "TMPDIR=$SANDBOX/tmp" -- bash "$M" verify
check "mutant: bsky-setup handing the password to curl as -d is RED (password in argv)" argv_has "$BSKY_PW_FIX" 1
rm -f "$GITWORK/.env"

echo
echo "community-argv.test.sh: $PASS passed, $FAIL failed"
# Exact count, in the pre-existing guard-invisible form: a lower-case `-lt` floor would make this
# `plugins/soleur/skills/*/test/` suite floor-bearing, which grows the DEFERRED ledger in
# scripts/guard-vacuity-floor.test.sh (47 -> 48) until the file is promoted there.
if [[ "$((PASS + FAIL))" -ne 303 ]]; then
  printf 'ANTI-VACUITY FLOOR: ran %s assertions, expected exactly 303\n' "$((PASS + FAIL))" >&2
  exit 1
fi
[[ "$FAIL" -eq 0 ]]
