#!/usr/bin/env bash
# Hermetic argv-hygiene test for the community scripts' credential-bearing curl calls
# (#9597): linkedin-setup.sh (client secret + introspected token, both as form fields)
# and the OAuth 1.0a Authorization header in x-community.sh and x-setup.sh.
#
# A PATH-shim `curl` records its argv NUL-delimited and, when asked for `--config -`,
# its stdin. Nothing touches the network. Per path the test proves:
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
prev=""
for a in "$@"; do
  if [[ "$prev" == "--config" && "$a" == "-" ]]; then
    cat > "$d/stdin.$n"
  fi
  prev="$a"
  url="$a"
done
case "$url" in
  *introspectToken) printf '%s\n200\n' '{"active":true,"expires_at":4102444800,"scope":"openid"}' ;;
  *accessToken)     printf '%s\n200\n' '{"access_token":"synthetic-fixture-token-0002"}' ;;
  *userinfo)        printf '%s\n200\n' '{"sub":"synthetic0001"}' ;;
  *2/tweets)        printf '%s\n201\n' '{"data":{"id":"1","text":"hi"}}' ;;
  *2/users/me*)     printf '%s\n200\n' '{"data":{"id":"123","username":"synthetic","name":"Synthetic","public_metrics":{"followers_count":1,"following_count":1,"tweet_count":1}}}' ;;
  *)                printf '%s\n500\n' '{}' ;;
esac
SHIM
chmod +x "$MOCK/curl"
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
  rm -f "$MOCK"/count "$MOCK"/argv.* "$MOCK"/stdin.*
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

echo
echo "community-argv.test.sh: $PASS passed, $FAIL failed"
if [[ "$((PASS + FAIL))" -ne 101 ]]; then
  printf 'ANTI-VACUITY FLOOR: ran %s assertions, expected exactly 101\n' "$((PASS + FAIL))" >&2
  exit 1
fi
[[ "$FAIL" -eq 0 ]]
