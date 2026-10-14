#!/usr/bin/env bash
# Guard suite for plugins/soleur/hooks/version-banner.sh (plugin version visibility, D4).
#
# WHAT IS PINNED. The hook is a SessionStart banner that must (1) cost no network by
# default, (2) never block on the network when opted in, (3) never warn about a version that
# is not actually older, (4) never leak the session's environment to its background child,
# and (5) fail open. Each property has rows in BOTH directions: every "prints the warning"
# row is paired with a row that differs in one field and must NOT.
#
# THE REAL RESOLVER RUNS. Only `git` and `curl` are stubbed. The hook is copied into a
# fixture tree next to a thin recording wrapper around the real plugin-version.sh, so the
# suite sees every resolver call (mode, argv), the environment and the file descriptors of
# the detached refresh child, and when that child finishes.
#
# HOW NETWORK IS WITNESSED.
#  - The `git`/`curl` stubs append their argv to a calls file and exit 64 on any argv they
#    were not written to expect (the exact isolated git argv and the exact compare-API curl
#    argv), so a drifted call is recorded AND loud.
#  - The default-off arm runs with a PATH restricted to a fail-loud stub dir plus a coreutils
#    allowlist: git, curl, wget, nc, ncat, python3, perl, ssh and openssl all record the call
#    and exit 64, and anything else is "command not found". A static row additionally refuses
#    absolute-path network binaries and /dev/tcp in the hook source.
#  - A detached child is asynchronous: rows that expect one wait on the resolver wrapper's END
#    marker (never a fixed sleep) and then assert. Rows that expect NONE wait a fixed bounded
#    window and then assert nothing started. `sleep` is used by the TEST only, never the SUT.
#
# THE LOCK. The lock directory is the synchronous evidence of a spawn decision (the hook
# creates it BEFORE spawning), so "no refresh" rows can also assert it is absent.
#
# DELETED WITH THE BEHAVIOUR (cache is now one file per install, latest-release.<id>):
#   - "cache computed for another install prints no warning" (2.g): a cache keyed to a
#     different install is no longer read at all; it is replaced by the per-install rows
#     (12.x), which assert the opposite consequence: cache=missing, so a refresh IS spawned.
#   - the single-slot `latest-release` fixture writer.

# The conditions handed to assert() are eval strings by design: single quotes are intended (SC2016)
# and the helpers/variables they name are invoked only from inside those strings (SC2034, SC2329).
# shellcheck disable=SC2016,SC2034,SC2329
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -P "$DIR/../../.." && pwd -P)"
SUT="$REPO_ROOT/plugins/soleur/hooks/version-banner.sh"
REAL_RESOLVER="$REPO_ROOT/plugins/soleur/scripts/plugin-version.sh"

# test-helpers.sh owns assert_fixture_dir. It sets -euo pipefail; restore this suite's
# accumulate-then-exit contract.
# shellcheck source=plugins/soleur/test/test-helpers.sh
source "$DIR/test-helpers.sh" || { echo "FATAL: could not source test-helpers.sh" >&2; exit 2; }
set +e -uo pipefail

command -v jq >/dev/null 2>&1 || { echo "FATAL: jq is required by this suite" >&2; exit 2; }
[[ -f "$SUT" ]] || { echo "FATAL: subject not found: $SUT" >&2; exit 2; }
[[ -f "$REAL_RESOLVER" ]] || { echo "FATAL: resolver not found: $REAL_RESOLVER" >&2; exit 2; }

SANDBOX="$(mktemp -d -t verbanner.XXXXXXXX)" || { echo "FATAL: mktemp failed" >&2; exit 2; }
assert_fixture_dir "$SANDBOX"
# Compose with test-helpers.sh's own cleanup (it owns a soleur-inc-* dir): a bare `trap ... EXIT`
# would replace it and leak that dir. A read-only fixture dir cannot be removed by rm -rf until it
# is writable again.
_suite_cleanup() {
  chmod -R u+w "$SANDBOX" 2>/dev/null
  rm -rf "$SANDBOX"
  if declare -F _soleur_sb_cleanup >/dev/null; then _soleur_sb_cleanup; fi
  return 0
}
trap _suite_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

# An ambient value from the operator's shell must not rewrite the suite's meaning.
unset SOLEUR_UPDATE_CHECK SOLEUR_DISABLE_VERSION_BANNER CODEX_THREAD_ID PLUGIN_ROOT \
      CLAUDE_PLUGIN_ROOT SOLEUR_FETCH_TIMEOUT

passes=0
fails=0
SKIPS=0
SKIP_RUN_DEFICIT=0   # subject invocations a skipped row would have made (run and banner floors)
CASES=0
FAILURES=()   # append-only: the verdict reads THIS, so a redirected counter cannot hide a failure.

pass() { passes=$((passes + 1)); printf '  ok   %s\n' "$1"; }
fail() {
  fails=$((fails + 1))
  FAILURES+=("$1")
  printf '  FAIL %s\n' "$1"
  [[ -n "${2:-}" ]] && printf '       %s\n' "$2"
  return 0
}

# --- INSTRUMENT SELF-TEST -----------------------------------------------
# Drives both arms once and refuses to continue unless both counters AND the failure ledger
# moved. Reported with printf + exit, never through the helpers it backstops (ADR-193).
_p0=$passes; _f0=$fails; _l0=${#FAILURES[@]}
pass "instrument self-test (pass arm)" >/dev/null
fail "instrument self-test (fail arm)" >/dev/null
if (( passes != _p0 + 1 )) || (( fails != _f0 + 1 )) || (( ${#FAILURES[@]} != _l0 + 1 )); then
  printf 'FATAL: instrument self-test did not move all three (pass %d->%d, fail %d->%d, ledger %d->%d)\n' \
    "$_p0" "$passes" "$_f0" "$fails" "$_l0" "${#FAILURES[@]}" >&2
  exit 2
fi
passes=$_p0; fails=$_f0; CASES=0; FAILURES=()

# CASES is incremented in the dispatcher, never inside pass()/fail() (guard-vacuity-floor).
assert() { # <name> <condition> [detail]
  CASES=$((CASES + 1))
  if eval "$2"; then pass "$1"; else fail "$1" "${3:-$2}"; fi
}
# A row that cannot run in this environment still counts as a case, so the floors stay exact
# on every machine; it is reported as skipped, never as passed.
skip() { # <name> <reason>
  CASES=$((CASES + 1)); SKIPS=$((SKIPS + 1))
  printf '  skip %s (%s)\n' "$1" "$2"
}

_p1=$passes; _f1=$fails; _c1=$CASES; _s1=$SKIPS
assert "instrument self-test (assert TRUE arm)"  'true'  >/dev/null
assert "instrument self-test (assert FALSE arm)" 'false' >/dev/null 2>&1
skip "instrument self-test (skip arm)" "self-test" >/dev/null
if (( passes != _p1 + 1 )) || (( fails != _f1 + 1 )) || (( CASES != _c1 + 3 )) || (( SKIPS != _s1 + 1 )); then
  printf 'FATAL: assert()/skip() do not gate on their condition (pass %d->%d, fail %d->%d, cases %d->%d, skips %d->%d)\n' \
    "$_p1" "$passes" "$_f1" "$fails" "$_c1" "$CASES" "$_s1" "$SKIPS" >&2
  exit 2
fi
passes=$_p1; fails=$_f1; CASES=$_c1; SKIPS=$_s1; FAILURES=()

# --- recording files ----------------------------------------------------
CALLS="$SANDBOX/calls"            # stubbed network binaries: one line per call (argv)
RCALLS="$SANDBOX/resolver-calls"  # one line per resolver invocation (its argv)
RENV="$SANDBOX/resolver-env"      # sorted env of every `--refresh` resolver invocation
RFDS="$SANDBOX/resolver-fds"      # where fd 0/1/2 point in every `--refresh` invocation
REND="$SANDBOX/resolver-end"      # one `END` line per finished `--refresh` invocation
SENT_GIT="$SANDBOX/sentinel.git"        # written when git is called with the exact argv
SENT_GIT_DONE="$SANDBOX/sentinel.git.done"
SENT_CURL="$SANDBOX/sentinel.curl"      # written when curl is called with the exact argv
MODEFILE="$SANDBOX/compare.mode"
BODYTMPL="$SANDBOX/compare.body.tmpl"
STUB_SHA="0123456789abcdef0123456789abcdef01234567"
: > "$CALLS"; : > "$RCALLS"; : > "$RENV"; : > "$RFDS"; : > "$REND"

# The exact isolated git argv (plugin-version.sh fetch_latest) and the exact compare curl argv.
GIT_ARGV='-c protocol.allow=never -c protocol.https.allow=always -c http.lowSpeedLimit=1 -c http.lowSpeedTime=8 ls-remote --tags https://github.com/jikig-ai/soleur.git refs/tags/v[0-9]*'

# A REAL-SHAPED compare body: pretty-printed, `"status": "ahead"` with a space after the colon,
# multi-line, with a per-file `"status"` AFTER the top-level one (the parser must take the first).
cat > "$BODYTMPL" <<'BODY'
{
  "url": "https://api.github.com/repos/jikig-ai/soleur/compare/abcdef012345...v9.9.9",
  "html_url": "https://github.com/jikig-ai/soleur/compare/abcdef012345...v9.9.9",
  "permalink_url": "https://github.com/jikig-ai/soleur/compare/jikig-ai:abcdef0...jikig-ai:0123456",
  "base_commit": {
    "sha": "abcdef0123456789abcdef0123456789abcdef01",
    "commit": {
      "message": "fix(plugin): a commit message that mentions status without quoting it",
      "verification": { "verified": false, "reason": "unsigned", "signature": null }
    }
  },
  "merge_base_commit": { "sha": "abcdef0123456789abcdef0123456789abcdef01" },
  "status": "@MODE@",
  "ahead_by": 3,
  "behind_by": 0,
  "total_commits": 3,
  "commits": [],
  "files": [
    {
      "sha": "1111111111111111111111111111111111111111",
      "filename": "plugins/soleur/hooks/version-banner.sh",
      "status": "modified",
      "additions": 4,
      "deletions": 1,
      "changes": 5
    }
  ]
}
BODY

# --- stubs --------------------------------------------------------------
# write_stub_git <dir> <sleep-seconds>   write_stub_curl <dir>
# %q-quoted constants are prepended to a quoted heredoc body, so no escaping lives in the stubs.
write_stub_git() {
  {
    printf '#!/usr/bin/env bash\n'
    printf 'CALLS=%q\nSENT=%q\nDONE=%q\nSLEEP=%q\nSHA=%q\n' "$CALLS" "$SENT_GIT" "$SENT_GIT_DONE" "$2" "$STUB_SHA"
    cat <<'STUB'
printf 'git %s\n' "$*" >> "$CALLS"
t="${SOLEUR_FETCH_TIMEOUT:-8}"
exp="-c protocol.allow=never -c protocol.https.allow=always -c http.lowSpeedLimit=1 -c http.lowSpeedTime=$t ls-remote --tags https://github.com/jikig-ai/soleur.git refs/tags/v[0-9]*"
if [[ "$*" == "$exp" ]]; then
  : > "$SENT"
  if [[ "$SLEEP" != 0 ]]; then sleep "$SLEEP"; fi
  printf '%s\trefs/tags/v9.9.9\n' "$SHA"
  printf '%s\trefs/tags/v10.0.0-rc1\n' "$SHA"
  : > "$DONE"
  exit 0
fi
exit 64
STUB
  } > "$1/git"
  chmod +x "$1/git"
}
write_stub_curl() {
  {
    printf '#!/usr/bin/env bash\n'
    printf 'CALLS=%q\nSENT=%q\nMODEFILE=%q\nTMPL=%q\n' "$CALLS" "$SENT_CURL" "$MODEFILE" "$BODYTMPL"
    cat <<'STUB'
printf 'curl %s\n' "$*" >> "$CALLS"
t="${SOLEUR_FETCH_TIMEOUT:-8}"
pre="-q -fsS --proto =https --compressed -m $t -H Accept: application/vnd.github+json https://api.github.com/repos/jikig-ai/soleur/compare/"
if [[ "$*" == "$pre"????????????"...v9.9.9?per_page=1&page=2000" && "$*" =~ compare/[0-9a-f]{12}\.\.\.v9\.9\.9 ]]; then
  : > "$SENT"
  mode="$(cat "$MODEFILE" 2>/dev/null)"; mode="${mode:-ahead}"
  sed "s/@MODE@/$mode/" "$TMPL"
  exit 0
fi
exit 64
STUB
  } > "$1/curl"
  chmod +x "$1/curl"
}

STUBBIN="$SANDBOX/stubs"; assert_fixture_dir "$STUBBIN"; mkdir -p "$STUBBIN"
SLOWBIN="$SANDBOX/slow-stubs"; assert_fixture_dir "$SLOWBIN"; mkdir -p "$SLOWBIN"
write_stub_git "$STUBBIN" 0;  write_stub_curl "$STUBBIN"
write_stub_git "$SLOWBIN" 3;  write_stub_curl "$SLOWBIN"
echo ahead > "$MODEFILE"

# Fail-loud stubs: any network-capable binary that is not git/curl-with-the-exact-argv.
FAILBIN="$SANDBOX/failbin"; assert_fixture_dir "$FAILBIN"; mkdir -p "$FAILBIN"
FAIL_NAMES="git curl wget nc ncat python3 perl ssh openssl"
for n in $FAIL_NAMES; do
  {
    printf '#!/bin/sh\nprintf '"'"'%s %%s\\n'"'"' "$*" >> %q\nexit 64\n' "$n" "$CALLS"
  } > "$FAILBIN/$n"
  chmod +x "$FAILBIN/$n"
done
# The coreutils allowlist: symlinks only to what the hook + resolver --installed path need.
COREBIN="$SANDBOX/corebin"; assert_fixture_dir "$COREBIN"; mkdir -p "$COREBIN"
for t in bash sh env dirname basename cat date stat mkdir rmdir rm mv chmod mktemp sed grep awk head tail tr sort cut jq; do
  p="$(command -v "$t" 2>/dev/null)" && [[ -x "$p" ]] && ln -sf "$p" "$COREBIN/$t"
done
RPATH="$FAILBIN:$COREBIN"

# The stubs are part of the instrument: prove they record AND discriminate argv.
git_stub_unexpected_rc=0; "$STUBBIN/git" status >/dev/null 2>&1 || git_stub_unexpected_rc=$?
curl_stub_unexpected_rc=0; "$STUBBIN/curl" https://example.invalid >/dev/null 2>&1 || curl_stub_unexpected_rc=$?
assert "stub self-test: git exits 64 on unexpected argv" '(( git_stub_unexpected_rc == 64 ))' "rc=$git_stub_unexpected_rc"
assert "stub self-test: curl exits 64 on unexpected argv" '(( curl_stub_unexpected_rc == 64 ))' "rc=$curl_stub_unexpected_rc"
assert "stub self-test: unexpected argv was recorded" 'grep -q "^git status$" "$CALLS" && grep -q "^curl https://example.invalid$" "$CALLS"'
: > "$CALLS"
git_old_rc=0; "$STUBBIN/git" ls-remote --tags https://github.com/jikig-ai/soleur.git 'refs/tags/v*' >/dev/null 2>&1 || git_old_rc=$?
assert "stub self-test: git rejects the pre-isolation argv (no -c protocol pins)" '(( git_old_rc == 64 )) && [[ ! -e "$SENT_GIT" ]]' "rc=$git_old_rc"
git_ok_rc=0; # shellcheck disable=SC2086
"$STUBBIN/git" $GIT_ARGV >/dev/null 2>&1 || git_ok_rc=$?
assert "stub self-test: git accepts exactly the isolated argv and writes its sentinel" '(( git_ok_rc == 0 )) && [[ -e "$SENT_GIT" ]]' "rc=$git_ok_rc"
curl_ok_rc=0
"$STUBBIN/curl" -q -fsS --proto =https --compressed -m 8 -H 'Accept: application/vnd.github+json' \
  'https://api.github.com/repos/jikig-ai/soleur/compare/abcdef012345...v9.9.9?per_page=1&page=2000' >/dev/null 2>&1 || curl_ok_rc=$?
assert "stub self-test: curl accepts exactly the compare argv and writes its sentinel" '(( curl_ok_rc == 0 )) && [[ -e "$SENT_CURL" ]]' "rc=$curl_ok_rc"
curl_old_rc=0
"$STUBBIN/curl" -fsS -H 'Accept: application/vnd.github+json' \
  'https://api.github.com/repos/jikig-ai/soleur/compare/abcdef012345...v9.9.9?per_page=1' >/dev/null 2>&1 || curl_old_rc=$?
assert "stub self-test: curl rejects the pre-hardening argv (no -q/--proto/--compressed/-m/page)" '(( curl_old_rc == 64 ))' "rc=$curl_old_rc"
assert "stub self-test: the compare body is real-shaped (pretty-printed, spaced status, per-file status after)" \
  '[[ "$(grep -c "\"status\": " "$BODYTMPL")" == 2 && "$(sed -n "/\"status\"/{=;q;}" "$BODYTMPL")" -lt "$(grep -n "\"files\"" "$BODYTMPL" | cut -d: -f1)" ]]'
: > "$CALLS"; rm -f "$SENT_GIT" "$SENT_GIT_DONE" "$SENT_CURL"
fail_loud_bad=""
for n in $FAIL_NAMES; do
  rc=0; "$FAILBIN/$n" probe-arg >/dev/null 2>&1 || rc=$?
  (( rc == 64 )) && grep -qx "$n probe-arg" "$CALLS" || fail_loud_bad="$fail_loud_bad $n"
done
assert "stub self-test: every fail-loud stub (git curl wget nc ncat python3 perl ssh openssl) records and exits 64" '[[ -z "$fail_loud_bad" ]]' "bad:$fail_loud_bad"
assert "stub self-test: the restricted PATH resolves curl/wget to the fail-loud stubs and nothing else" \
  '[[ "$(PATH=$RPATH command -v curl)" == "$FAILBIN/curl" && "$(PATH=$RPATH command -v wget)" == "$FAILBIN/wget" && -z "$(PATH=$RPATH command -v ls)" && -z "$(PATH=$RPATH command -v sleep)" ]]'
: > "$CALLS"

# --- fixture trees: the hook copy + a recording wrapper around the real resolver --------------
TREES="$SANDBOX/trees"; assert_fixture_dir "$TREES"; mkdir -p "$TREES"
mkresolver_wrapper() { # <tree>
  mkdir -p "$1/scripts"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'RCALLS=%q\nRENV=%q\nRFDS=%q\nREND=%q\nREAL=%q\n' "$RCALLS" "$RENV" "$RFDS" "$REND" "$REAL_RESOLVER"
    cat <<'WRAP'
printf '%s\n' "$*" >> "$RCALLS"
refresh=0; case " $* " in *" --refresh "*) refresh=1 ;; esac
if (( refresh )); then
  f0=other; [ /dev/fd/0 -ef /dev/null ] && f0=null
  f1=other; [ /dev/fd/1 -ef /dev/null ] && f1=null
  f2=other; [ /dev/fd/2 -ef /dev/null ] && f2=null
  printf 'fds: 0=%s 1=%s 2=%s\n' "$f0" "$f1" "$f2" >> "$RFDS"
  { printf '== %s\n' "$*"; env | sort; } >> "$RENV"
fi
bash "$REAL" "$@"
rc=$?
if (( refresh )); then printf 'END\n' >> "$REND"; fi
exit "$rc"
WRAP
  } > "$1/scripts/plugin-version.sh"
}
mktree() { # <name> [resolver-body]  -> sets TREE_HOOK; wrapper around the real resolver unless a body is given
  local t="$TREES/$1"
  assert_fixture_dir "$t"
  mkdir -p "$t/hooks" "$t/scripts"
  cp "$SUT" "$t/hooks/version-banner.sh"
  if [[ -n "${2:-}" ]]; then printf '#!/usr/bin/env bash\n%s\n' "$2" > "$t/scripts/plugin-version.sh"; else mkresolver_wrapper "$t"; fi
  TREE_HOOK="$t/hooks/version-banner.sh"
}
mktree real; HOOK_REAL="$TREE_HOOK"

# --- fixture plugin roots ----------------------------------------------
mkroot() { # <dir> [version]   (plugin.json keyless unless a version is given)
  local d="$1" v="${2:-}"
  assert_fixture_dir "$d"
  mkdir -p "$d/.claude-plugin" || { echo "FATAL: mkdir $d" >&2; exit 2; }
  if [[ -n "$v" ]]; then
    printf '{"name":"soleur","version":"%s"}\n' "$v" > "$d/.claude-plugin/plugin.json"
  else
    printf '{"name":"soleur"}\n' > "$d/.claude-plugin/plugin.json"
  fi
}
ROOTS="$SANDBOX/roots"; assert_fixture_dir "$ROOTS"
COMMIT12="abcdef012345"
R_MANIFEST="$ROOTS/manifest-1.2.0";  mkroot "$R_MANIFEST" "1.2.0"
R_NEWER="$ROOTS/manifest-2.0.0";     mkroot "$R_NEWER" "2.0.0"
R_EQUAL="$ROOTS/manifest-9.9.9";     mkroot "$R_EQUAL" "9.9.9"
R_NINE="$ROOTS/manifest-1.9.0";      mkroot "$R_NINE" "1.9.0"
R_ZERO="$ROOTS/manifest-03.10.0";    mkroot "$R_ZERO" "03.10.0"   # leading zero: numeric compare, not octal/string
R_THREE9="$ROOTS/manifest-3.9.0";    mkroot "$R_THREE9" "3.9.0"
R_COMMIT="$ROOTS/$COMMIT12";         mkroot "$R_COMMIT"
R_UNKNOWN="$ROOTS/not-a-hash-dir";   mkroot "$R_UNKNOWN"
R_PREC="$ROOTS/prec/$COMMIT12";      mkroot "$R_PREC" "4.4.4"      # hex dir name AND a semver manifest
R_MISSING="$ROOTS/does-not-exist"
ID_M="1.2.0"; ID_C="$COMMIT12"

NOW="$(date +%s)"
DAY=86400
M120="Soleur v1.2.0"
M120_W="Soleur v1.2.0 — newer release v9.9.9 available"
MC="Soleur commit $COMMIT12"
MC_W="$MC — newer release v9.9.9 available"

XDG_N=0
XDG=""
new_xdg() { # fresh cache home per row; sets XDG
  XDG_N=$((XDG_N + 1))
  XDG="$SANDBOX/xdg.$XDG_N"
  assert_fixture_dir "$XDG"
  mkdir -p "$XDG/soleur" || { echo "FATAL: mkdir $XDG" >&2; exit 2; }
}
HOME_N=0
H=""
new_home() { # fresh empty HOME per row; sets H
  HOME_N=$((HOME_N + 1)); H="$SANDBOX/home.$HOME_N"
  assert_fixture_dir "$H"; mkdir -p "$H" || { echo "FATAL: mkdir $H" >&2; exit 2; }
}
CWD_N=0
RUN_CWD="$SANDBOX/cwd.default"; assert_fixture_dir "$RUN_CWD"; mkdir -p "$RUN_CWD"
new_cwd() { # fresh EMPTY working directory per row; sets RUN_CWD (hooks are global: they run in the user's project)
  CWD_N=$((CWD_N + 1)); RUN_CWD="$SANDBOX/cwd.$CWD_N"
  assert_fixture_dir "$RUN_CWD"; mkdir -p "$RUN_CWD" || { echo "FATAL: mkdir $RUN_CWD" >&2; exit 2; }
}
default_cwd() { RUN_CWD="$SANDBOX/cwd.default"; }
HOME_RW="$SANDBOX/home"; assert_fixture_dir "$HOME_RW"; mkdir -p "$HOME_RW"
STDIN_FILE="$SANDBOX/hook-stdin.json"; printf '{"hook_event_name":"SessionStart","source":"startup"}\n' > "$STDIN_FILE"

CACHE() { printf '%s' "$XDG/soleur/latest-release.$1"; }   # <install id>
LOCK() { printf '%s' "$XDG/soleur/refresh.lock"; }

put_cache() { # <id> <tag> <fetched-epoch> <relation> [relation_for (default: id)] [complete (default 1)]
  local id="$1" rf="${5-$1}" comp="${6-1}"
  assert_fixture_dir "$XDG"
  printf 'tag=%s\nsha=%s\nfetched=%s\nrelation=%s\nrelation_for=%s\nreason=\n' \
    "$2" "$STUB_SHA" "$3" "$4" "$rf" > "$(CACHE "$id")"
  if [[ "$comp" == 1 ]]; then printf 'complete=1\n' >> "$(CACHE "$id")"; fi
}
cache_fetched() { sed -n 's/^fetched=//p' "$(CACHE "$1")" 2>/dev/null | head -1; }   # <id>
cache_field() { sed -n "s/^$2=//p" "$(CACHE "$1")" 2>/dev/null | head -1; }          # <id> <key>

mtime_of() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }
age_path() { # <path> <seconds-ago>   (negative = future-dated)
  local p="$1" t
  t=$(( $(date +%s) - $2 ))
  touch -d "@$t" "$p" 2>/dev/null || touch -t "$(date -r "$t" +%Y%m%d%H%M.%S 2>/dev/null)" "$p" 2>/dev/null
  local got; got="$(mtime_of "$p")"
  if [[ ! "$got" =~ ^[0-9]+$ ]] || (( got - t > 2 || t - got > 2 )); then
    echo "FATAL: could not set the mtime of $p to now-$2 (got $got)" >&2; exit 2
  fi
}

# --- harness ------------------------------------------------------------
OUT=""; RC=0; RUNS=0; BANNERS=0; T_MS=0
HOOK="$HOOK_REAL"; MINIMAL=0; MERGE_ERR=0
if [[ -n "${EPOCHREALTIME:-}" ]]; then
  now_ms() { local t="${EPOCHREALTIME/[.,]/}"; printf '%s' $(( 10#$t / 1000 )); }
  LIM_MS=1000
else
  now_ms() { printf '%s' $(( $(date +%s) * 1000 )); }
  LIM_MS=2000   # whole-second clock: allow one tick; the regressions this guards stall >= 3 s
fi
reset_calls() {
  : > "$CALLS"; : > "$RCALLS"; : > "$RENV"; : > "$RFDS"; : > "$REND"
  rm -f "$SENT_GIT" "$SENT_GIT_DONE" "$SENT_CURL"
}
run_hook() { # [VAR=value ...] [-u VAR ...]   (defaults: stub PATH, HOME_RW, XDG; cwd RUN_CWD; stdin = a file)
  RUNS=$((RUNS + 1))
  local -a ov=() drops=() final=() unsets=(-u CODEX_THREAD_ID -u PLUGIN_ROOT -u SOLEUR_UPDATE_CHECK -u SOLEUR_DISABLE_VERSION_BANNER)
  local d n x skipit t0
  while (( $# )); do
    if [[ "$1" == "-u" ]]; then drops+=("$2"); unsets+=(-u "$2"); shift 2; else ov+=("$1"); shift; fi
  done
  local -a defaults=("PATH=$STUBBIN:$PATH")
  (( MINIMAL )) || defaults+=("HOME=$HOME_RW" "XDG_CACHE_HOME=$XDG")
  for d in "${defaults[@]}"; do
    n="${d%%=*}"; skipit=0
    for x in ${drops[@]+"${drops[@]}"}; do [[ "$x" == "$n" ]] && skipit=1; done
    for x in ${ov[@]+"${ov[@]}"}; do [[ "${x%%=*}" == "$n" ]] && skipit=1; done
    (( skipit )) || final+=("$d")
  done
  local -a envcmd=(env)
  (( MINIMAL )) && envcmd=(env -i)
  t0="$(now_ms)"
  if (( MERGE_ERR )); then
    OUT="$(cd "$RUN_CWD" && "${envcmd[@]}" "${unsets[@]}" "${final[@]}" ${ov[@]+"${ov[@]}"} bash "$HOOK" 2>&1 <"$STDIN_FILE")"
  else
    OUT="$(cd "$RUN_CWD" && "${envcmd[@]}" "${unsets[@]}" "${final[@]}" ${ov[@]+"${ov[@]}"} bash "$HOOK" 2>/dev/null <"$STDIN_FILE")"
  fi
  RC=$?
  T_MS=$(( $(now_ms) - t0 ))
  [[ -n "$OUT" ]] && BANNERS=$((BANNERS + 1))
  return 0
}
n_git()  { local n; n="$(grep -c '^git ' "$CALLS" 2>/dev/null || true)";  printf '%s' "${n:-0}"; }
n_curl() { local n; n="$(grep -c '^curl ' "$CALLS" 2>/dev/null || true)"; printf '%s' "${n:-0}"; }
n_refresh() { local n; n="$(grep -c -- '--refresh' "$RCALLS" 2>/dev/null || true)"; printf '%s' "${n:-0}"; }
n_modecalls() { local n; n="$(grep -cE '^--(installed|cached-latest)$' "$RCALLS" 2>/dev/null || true)"; printf '%s' "${n:-0}"; }
n_rcalls() { local n; n="$(grep -c '' "$RCALLS" 2>/dev/null || true)"; printf '%s' "${n:-0}"; }
msg() { printf '%s' "$OUT" | jq -r '.systemMessage // ""' 2>/dev/null; }
one_json() { [[ "$(printf '%s' "$OUT" | jq -s length 2>/dev/null)" == 1 ]]; }
cwd_empty() { [[ -z "$(ls -A "$RUN_CWD" 2>/dev/null)" ]]; }

# Bounded polls with `sleep` (the TEST may sleep; the SUT may not). Portable to bash 3.2.
wait_file() { # <path> [tries of 0.2 s]
  local i
  for ((i = 0; i < ${2:-50}; i++)); do
    [[ -e "$1" ]] && return 0
    sleep 0.2
  done
  [[ -e "$1" ]]
}
settle() { local i; for ((i = 0; i < ${1:-5}; i++)); do sleep 0.2; done; }   # fixed window for NEGATIVE rows
wait_children() { # <expected finished refresh children> [tries]
  local i n
  for ((i = 0; i < ${2:-60}; i++)); do
    n="$(grep -c '^END$' "$REND" 2>/dev/null || true)"
    (( ${n:-0} >= $1 )) && return 0
    # The wrapper logs the call before it does anything else: no call after 2 s means no child.
    if (( i >= 10 )) && (( $(n_refresh) == 0 )); then return 1; fi
    sleep 0.2
  done
  return 1
}

# A probe that proves msg() extracts the field the hook writes, not a decoy.
OUT='{"systemMessage":"MARK","decoy":"DECOY"}'
if [[ "$(msg)" != "MARK" ]]; then printf 'FATAL: msg() does not extract systemMessage\n' >&2; exit 2; fi
OUT=""
# A probe that proves the recording wrapper and the restricted PATH really drive the hook.
new_xdg; reset_calls; run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST"
if [[ ! -s "$RCALLS" || "$(msg)" != "$M120" ]]; then
  printf 'FATAL: the recording wrapper did not see the resolver call (calls: %s, out: %s)\n' "$(cat "$RCALLS")" "$OUT" >&2; exit 2
fi
RUNS=0; BANNERS=0; reset_calls
NONEX_BEFORE=0; [[ -e /nonexistent ]] && NONEX_BEFORE=1

echo "== 1: default off makes zero network calls (restricted PATH) and prints the plain banner =="
for v in UNSET 0 EMPTY yes true 2; do
  new_xdg; put_cache "$ID_M" v9.9.9 "$((NOW - 3 * DAY))" older   # stale AND would warn if on
  reset_calls
  case "$v" in
    UNSET) run_hook "PATH=$RPATH" "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" ;;
    EMPTY) run_hook "PATH=$RPATH" "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=" ;;
    *)     run_hook "PATH=$RPATH" "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=$v" ;;
  esac
  assert "1.$v rc is 0" '(( RC == 0 ))'
  assert "1.$v prints the installed version only" '[[ "$(msg)" == "$M120" ]]' "got: $(msg)"
  assert "1.$v zero calls to ANY network-capable binary" '[[ ! -s "$CALLS" ]]' "calls: $(cat "$CALLS")"
  assert "1.$v exactly one resolver call, --installed" '[[ "$(cat "$RCALLS")" == "--installed" ]]' "calls: $(cat "$RCALLS")"
  assert "1.$v no refresh lock taken (no spawn decision)" '[[ ! -e "$(LOCK)" ]]'
done
# Same for a commit-hash install, where a network-on hook would also call curl.
new_xdg; reset_calls
run_hook "PATH=$RPATH" "CLAUDE_PLUGIN_ROOT=$R_COMMIT"
assert "1.commit default off prints commit identity" '[[ "$(msg)" == "$MC" ]]' "got: $(msg)"
assert "1.commit default off: zero network-binary calls, one --installed resolver call" '[[ ! -s "$CALLS" && "$(cat "$RCALLS")" == "--installed" ]]'
assert "1.static the hook source names no absolute-path network binary and no /dev/tcp" \
  '! grep -nE "/dev/(tcp|udp)|/(usr/)?(local/)?s?bin/(curl|wget|nc|ncat|python3?|perl|ssh|openssl)" "$SUT"'

echo "== 2: opt-in + fresh cache warns without calling git; ONE resolver call per start =="
new_xdg; put_cache "$ID_M" v9.9.9 "$((NOW - 60))" older; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"
assert "2.a manifest: warning names the newer tag" '[[ "$(msg)" == "$M120_W" ]]' "got: $(msg)"
assert "2.b manifest: zero git calls on a fresh cache" '(( $(n_git) == 0 ))'
assert "2.c manifest: no refresh lock" '[[ ! -e "$(LOCK)" ]]'
assert "2.mode manifest: one --cached-latest call, then the downgrade check --cmp, nothing else" \
  '[[ "$(sed -n 1p "$RCALLS")" == "--cached-latest" && "$(sed -n 2p "$RCALLS")" == "--cmp 1.2.0 9.9.9" && "$(n_rcalls)" == 2 && "$(n_modecalls)" == 1 ]]' "calls: $(cat "$RCALLS")"
new_xdg; put_cache "$ID_C" v9.9.9 "$((NOW - 60))" older; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_COMMIT" "SOLEUR_UPDATE_CHECK=1"
assert "2.d commit install: warning printed" '[[ "$(msg)" == "$MC_W" ]]' "got: $(msg)"
assert "2.e commit install: zero git and curl calls" '(( $(n_git) + $(n_curl) == 0 ))'
assert "2.mode commit: exactly ONE resolver call, --cached-latest (no --cmp, no second call)" '[[ "$(cat "$RCALLS")" == "--cached-latest" ]]' "calls: $(cat "$RCALLS")"
# Paired negatives: relation current / unknown, for both install kinds.
for rel in current unknown; do
  new_xdg; put_cache "$ID_M" v9.9.9 "$((NOW - 60))" "$rel"; reset_calls
  run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"
  assert "2.f manifest relation=$rel prints no warning" '[[ "$(msg)" == "$M120" ]]' "got: $(msg)"
  new_xdg; put_cache "$ID_C" v9.9.9 "$((NOW - 60))" "$rel"; reset_calls
  run_hook "CLAUDE_PLUGIN_ROOT=$R_COMMIT" "SOLEUR_UPDATE_CHECK=1"
  assert "2.f commit relation=$rel prints no warning, no spawn" '[[ "$(msg)" == "$MC" && ! -e "$(LOCK)" ]]' "got: $(msg)"
done

echo "== 3: opt-in + stale cache prints the stale answer and spawns exactly one refresh =="
new_xdg; old=$((NOW - 3 * DAY)); put_cache "$ID_M" v9.9.9 "$old" older; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"
wait_children 1
assert "3.a stale value used now (warning present)" '[[ "$(msg)" == "$M120_W" ]]' "got: $(msg)"
assert "3.b hook returned with rc 0" '(( RC == 0 ))'
assert "3.c lock taken synchronously" '[[ -d "$(LOCK)" ]]'
assert "3.d background refresh reached git with the exact argv (sentinel)" '[[ -e "$SENT_GIT" ]]'
assert "3.e background refresh rewrote the cache" '[[ "$(cache_fetched "$ID_M")" != "$old" && -n "$(cache_fetched "$ID_M")" ]]'
assert "3.f exactly one git ls-remote, with the exact isolated argv" \
  '(( $(n_git) == 1 )) && grep -qxF "git $GIT_ARGV" "$CALLS"' "calls: $(cat "$CALLS")"
assert "3.g manifest install needs no compare call" '(( $(n_curl) == 0 ))'
assert "3.mode one --cached-latest, one --cmp, exactly one detached --latest --refresh" \
  '[[ "$(n_modecalls)" == 1 && "$(n_refresh)" == 1 && "$(grep -cx -- "--latest --refresh" "$RCALLS")" == 1 ]]' "calls: $(cat "$RCALLS")"
assert "3.json stdout is exactly ONE JSON value (the child leaked nothing into the pipe)" 'one_json' "out: $OUT"
assert "3.fds the detached child has stdin, stdout and stderr all on /dev/null" '[[ "$(cat "$RFDS")" == "fds: 0=null 1=null 2=null" ]]' "fds: $(cat "$RFDS")"
assert "3.h the refreshed cache is now fresh: next start spawns nothing and warns" \
  'rm -rf "$(LOCK)"; reset_calls; run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"; [[ "$(msg)" == "$M120_W" && ! -e "$(LOCK)" && "$(n_git)" == 0 && "$(n_refresh)" == 0 ]]'

# Commit install, END TO END against the real-shaped compare body: refresh, then the next start warns.
new_xdg; old=$((NOW - 3 * DAY)); put_cache "$ID_C" v9.9.9 "$old" current; reset_calls; echo ahead > "$MODEFILE"
run_hook "CLAUDE_PLUGIN_ROOT=$R_COMMIT" "SOLEUR_UPDATE_CHECK=1"
wait_children 1
assert "3.i commit install: stale relation=current prints plain banner" '[[ "$(msg)" == "$MC" ]]' "got: $(msg)"
assert "3.i2 commit install: one JSON value on the spawning start" 'one_json' "out: $OUT"
assert "3.j commit install: refresh reached curl with the exact compare argv" '[[ -e "$SENT_CURL" ]]' "calls: $(cat "$CALLS")"
assert "3.k commit install: one git, one curl" '(( $(n_git) == 1 && $(n_curl) == 1 ))' "git=$(n_git) curl=$(n_curl)"
assert "3.l the real-shaped pretty-printed body (\"status\": \"ahead\") parses to relation=older in the cache" \
  '[[ "$(cache_field "$ID_C" relation)" == older && "$(cache_field "$ID_C" relation_for)" == "$ID_C" && "$(cache_field "$ID_C" complete)" == 1 ]]' "cache: $(cat "$(CACHE "$ID_C")" 2>&1)"
assert "3.m END TO END: the next start warns about the newer release, spawns nothing" \
  'rm -rf "$(LOCK)"; reset_calls; run_hook "CLAUDE_PLUGIN_ROOT=$R_COMMIT" "SOLEUR_UPDATE_CHECK=1"; [[ "$(msg)" == "$MC_W" && ! -e "$(LOCK)" && "$(n_git)" == 0 && "$(n_curl)" == 0 ]]' "got: $(msg)"
# The opposite bodies: identical and diverged must NOT warn on the next start.
for st in identical diverged; do
  new_xdg; old=$((NOW - 3 * DAY)); put_cache "$ID_C" v9.9.9 "$old" current; reset_calls; echo "$st" > "$MODEFILE"
  run_hook "CLAUDE_PLUGIN_ROOT=$R_COMMIT" "SOLEUR_UPDATE_CHECK=1"
  wait_children 1
  assert "3.n compare status=$st: refresh ran and the next start prints no warning" \
    '[[ -e "$SENT_CURL" ]] && { rm -rf "$(LOCK)"; reset_calls; run_hook "CLAUDE_PLUGIN_ROOT=$R_COMMIT" "SOLEUR_UPDATE_CHECK=1"; [[ "$(msg)" == "$MC" ]]; }' "got: $(msg)"
done
echo ahead > "$MODEFILE"

# STALE cache with relation=older still warns (releases only move forward) AND spawns a refresh;
# STALE with relation=current is turned into unknown by the resolver and prints plain.
new_xdg; old=$((NOW - 3 * DAY)); put_cache "$ID_C" v9.9.9 "$old" older; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_COMMIT" "SOLEUR_UPDATE_CHECK=1"
wait_children 1
assert "3.o commit install: stale relation=older still warns" '[[ "$(msg)" == "$MC_W" ]]' "got: $(msg)"
assert "3.p commit install: stale relation=older also spawned the refresh (lock, git, curl)" '[[ -d "$(LOCK)" && "$(n_git)" == 1 && "$(n_curl)" == 1 ]]'
new_xdg; old=$((NOW - 3 * DAY)); put_cache "$ID_C" v9.9.9 "$old" unknown; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_COMMIT" "SOLEUR_UPDATE_CHECK=1"
wait_children 1
assert "3.q commit install: stale relation=unknown prints plain and still refreshes" '[[ "$(msg)" == "$MC" && -d "$(LOCK)" ]]' "got: $(msg)"

new_xdg; reset_calls    # missing cache
run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"
wait_children 1
assert "3.r missing cache: plain banner, no warning" '[[ "$(msg)" == "$M120" ]]' "got: $(msg)"
assert "3.s missing cache: one refresh spawned and completed, cache written" '[[ -e "$SENT_GIT" && -e "$(CACHE "$ID_M")" && "$(n_git)" == 1 ]]'
assert "3.s2 missing cache: one JSON value" 'one_json' "out: $OUT"

new_xdg; printf 'garbage\n' > "$(CACHE "$ID_M")"; reset_calls    # corrupt cache
run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"
wait_children 1
assert "3.t corrupt cache: plain banner, refresh lock taken" '[[ "$(msg)" == "$M120" && -d "$(LOCK)" ]]' "got: $(msg)"
assert "3.u corrupt cache: refresh repairs it" '[[ -e "$SENT_GIT" && "$(cache_field "$ID_M" complete)" == 1 ]]'
assert "3.u2 corrupt cache: one JSON value" 'one_json' "out: $OUT"

echo "== 4: future-dated cache is stale =="
new_xdg; old=$((NOW - 100)); put_cache "$ID_M" v9.9.9 "$old" older
age_path "$(CACHE "$ID_M")" -$((3 * DAY))
reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"
wait_children 1
assert "4.a future mtime: refresh decision taken (lock present)" '[[ -d "$(LOCK)" ]]'
assert "4.b future mtime: stale value still shown, one JSON value" '[[ "$(msg)" == "$M120_W" ]] && one_json' "got: $(msg)"
assert "4.c future mtime: refresh ran" '[[ -e "$SENT_GIT" && "$(cache_fetched "$ID_M")" != "$old" ]]'
new_xdg; put_cache "$ID_M" v9.9.9 "$((NOW + 3 * DAY))" older; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"
wait_children 1
assert "4.d future fetched epoch: refresh decision taken, one JSON value" '[[ -d "$(LOCK)" ]] && one_json'
assert "4.e future fetched epoch: refresh ran" '[[ -e "$SENT_GIT" && "$(cache_fetched "$ID_M")" != "$((NOW + 3 * DAY))" ]]'

echo "== 5: downgrade and equal versions never warn =="
new_xdg; put_cache 2.0.0 v1.0.0 "$((NOW - 60))" current; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_NEWER" "SOLEUR_UPDATE_CHECK=1"
assert "5.a installed newer than cached latest: no warning" '[[ "$(msg)" == "Soleur v2.0.0" ]]' "got: $(msg)"
# A cache that LIES (relation=older although installed is newer) must still not warn.
new_xdg; put_cache 2.0.0 v1.0.0 "$((NOW - 60))" older; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_NEWER" "SOLEUR_UPDATE_CHECK=1"
assert "5.b a lying relation=older cache still prints no warning" '[[ "$(msg)" == "Soleur v2.0.0" ]]' "got: $(msg)"
assert "5.b2 the hook asked the resolver for the order (--cmp 2.0.0 1.0.0) instead of trusting the cache" 'grep -qx -- "--cmp 2.0.0 1.0.0" "$RCALLS"' "calls: $(cat "$RCALLS")"
new_xdg; put_cache 9.9.9 v9.9.9 "$((NOW - 60))" older; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_EQUAL" "SOLEUR_UPDATE_CHECK=1"
assert "5.c equal versions: no warning even if relation=older is cached" '[[ "$(msg)" == "Soleur v9.9.9" ]]' "got: $(msg)"
new_xdg; put_cache 1.9.0 v1.10.0 "$((NOW - 60))" older; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_NINE" "SOLEUR_UPDATE_CHECK=1"
assert "5.d semver order is numeric (1.9.0 < 1.10.0 warns)" '[[ "$(msg)" == "Soleur v1.9.0 — newer release v1.10.0 available" ]]' "got: $(msg)"
# Leading zeros: 03.10.0 is NEWER than 3.9.0 numerically (a string compare says older and would warn).
new_xdg; put_cache 03.10.0 v3.9.0 "$((NOW - 60))" older; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_ZERO" "SOLEUR_UPDATE_CHECK=1"
assert "5.e leading-zero install 03.10.0 vs cached v3.9.0 (lying older): numeric compare, no warning" '[[ "$(msg)" == "Soleur v03.10.0" ]]' "got: $(msg)"
new_xdg; put_cache 3.9.0 v3.010.0 "$((NOW - 60))" older; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_THREE9" "SOLEUR_UPDATE_CHECK=1"
assert "5.f installed 3.9.0 vs latest v3.010.0: numeric order says older, warns (a string compare would not)" \
  '[[ "$(msg)" == "Soleur v3.9.0 — newer release v3.010.0 available" ]]' "got: $(msg)"

echo "== 6: kill switch and skip conditions print nothing =="
new_xdg; put_cache "$ID_M" v9.9.9 "$((NOW - 3 * DAY))" older; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1" "SOLEUR_DISABLE_VERSION_BANNER=1"
assert "6.a kill switch: no output" '[[ -z "$OUT" ]]' "got: $OUT"
assert "6.b kill switch: rc 0" '(( RC == 0 ))'
assert "6.c kill switch: no lock, no network, no resolver call" '[[ ! -e "$(LOCK)" ]] && (( $(n_git) + $(n_curl) + $(n_rcalls) == 0 ))'
run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_DISABLE_VERSION_BANNER=0"
assert "6.d kill switch is exactly 1 (0 leaves the banner on)" '[[ "$(msg)" == "$M120" ]]' "got: $(msg)"
run_hook -u CLAUDE_PLUGIN_ROOT "SOLEUR_UPDATE_CHECK=1"
assert "6.e no plugin root: no output, rc 0" '[[ -z "$OUT" ]] && (( RC == 0 ))' "got: $OUT rc=$RC"
run_hook "CLAUDE_PLUGIN_ROOT="
assert "6.f empty plugin root: no output" '[[ -z "$OUT" ]]'
run_hook "CLAUDE_PLUGIN_ROOT=$R_MISSING"
assert "6.g plugin root dir missing: no output" '[[ -z "$OUT" ]] && (( RC == 0 ))'
run_hook "CLAUDE_PLUGIN_ROOT=$R_UNKNOWN" "SOLEUR_UPDATE_CHECK=1"
assert "6.h unknown installed source: no output" '[[ -z "$OUT" ]] && (( RC == 0 ))' "got: $OUT"
reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "CODEX_THREAD_ID=thread-1" "SOLEUR_UPDATE_CHECK=1"
assert "6.i Codex marker: no output" '[[ -z "$OUT" ]] && (( RC == 0 ))' "got: $OUT"
run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "PLUGIN_ROOT=/somewhere" "SOLEUR_UPDATE_CHECK=1"
assert "6.j PLUGIN_ROOT marker: no output" '[[ -z "$OUT" ]] && (( RC == 0 ))' "got: $OUT"
assert "6.k other-harness rows made no network call, took no lock, called no resolver" '(( $(n_git) + $(n_curl) + $(n_rcalls) == 0 )) && [[ ! -e "$(LOCK)" ]]'
# Installed identity precedence: the manifest version outranks a hex-looking directory name.
new_xdg; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_PREC"
assert "6.l a semver manifest wins over a commit-hash directory name" '[[ "$(msg)" == "Soleur v4.4.4" ]]' "got: $(msg)"
run_hook "CLAUDE_PLUGIN_ROOT=$R_COMMIT"
assert "6.m the same hash directory with a keyless manifest is a commit install" '[[ "$(msg)" == "$MC" ]]' "got: $(msg)"

echo "== 7: output is one valid JSON object =="
SHAPES=0
for root in "$R_MANIFEST" "$R_COMMIT" "$R_NEWER"; do
  for opt in "" 1; do
    new_xdg; put_cache "$(basename "$root" | sed 's/^manifest-//')" v9.9.9 "$((NOW - 60))" older
    run_hook "CLAUDE_PLUGIN_ROOT=$root" "SOLEUR_UPDATE_CHECK=$opt"
    SHAPES=$((SHAPES + 1))
    assert "7.$SHAPES ($(basename "$root"), opt=${opt:-off}) jq -e parses it" 'printf "%s" "$OUT" | jq -e . >/dev/null'
    assert "7.$SHAPES exactly one JSON value on one line" '[[ "$(printf "%s" "$OUT" | jq -s length)" == 1 && "$(printf "%s\n" "$OUT" | wc -l | tr -d " ")" == 1 ]]'
    assert "7.$SHAPES only key is systemMessage (no additionalContext)" '[[ "$(printf "%s" "$OUT" | jq -c "keys")" == "[\"systemMessage\"]" ]]'
    assert "7.$SHAPES systemMessage shape" '[[ "$(msg)" =~ ^Soleur\ (v[0-9]+\.[0-9]+\.[0-9]+|commit\ [0-9a-f]{12}) ]]' "got: $(msg)"
  done
done

echo "== 8: fail open under an unwritable HOME =="
RO_HOME="$SANDBOX/ro-home"; assert_fixture_dir "$RO_HOME"; mkdir -p "$RO_HOME"; chmod 555 "$RO_HOME"
BLOCKED_HOME="$SANDBOX/blocked-home-file"; assert_fixture_dir "$BLOCKED_HOME"; : > "$BLOCKED_HOME"
for h in "$RO_HOME" "$BLOCKED_HOME/sub"; do
  tag="$(basename "$h")"
  if [[ "$h" == "$RO_HOME" && "${EUID:-$(id -u)}" == 0 ]]; then
    echo "  note: running as root; a chmod 555 HOME is writable to root, so the read-only-HOME rows are skipped"
    SKIP_RUN_DEFICIT=$((SKIP_RUN_DEFICIT + 2))
    for n in "rc is 0" "still prints the banner as valid JSON" "spawns nothing it cannot cache" "default-off also rc 0"; do
      skip "8.$tag $n" "root can write a chmod 555 directory"
    done
    continue
  fi
  reset_calls
  run_hook -u XDG_CACHE_HOME "HOME=$h" "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"
  settle 3
  assert "8.$tag rc is 0" '(( RC == 0 ))'
  assert "8.$tag still prints the banner as valid JSON" '[[ "$(msg)" == "$M120" ]]' "got: $OUT"
  assert "8.$tag spawns nothing it cannot cache" '(( $(n_git) + $(n_curl) + $(n_refresh) == 0 ))'
  run_hook -u XDG_CACHE_HOME "HOME=$h" "CLAUDE_PLUGIN_ROOT=$R_MANIFEST"
  assert "8.$tag default-off also rc 0" '(( RC == 0 )) && [[ "$(msg)" == "$M120" ]]'
done
chmod 755 "$RO_HOME"

echo "== 9: no jq on PATH =="
NOJQ="$SANDBOX/nojq-bin"; assert_fixture_dir "$NOJQ"; mkdir -p "$NOJQ"
for t in bash sed head tail basename dirname date stat mkdir chmod mktemp mv rm rmdir awk grep sort tr cat \
         setsid nohup timeout cut env wc uniq touch ls; do
  p="$(command -v "$t" 2>/dev/null)" && [[ -x "$p" ]] && ln -sf "$p" "$NOJQ/$t"
done
NOJQ_PATH="$STUBBIN:$NOJQ"
control_has_jq="$(PATH="$NOJQ_PATH" command -v jq 2>/dev/null || true)"
assert "9.a control: the restricted PATH really has no jq" '[[ -z "$control_has_jq" ]]' "found: $control_has_jq"
new_xdg; put_cache "$ID_M" v9.9.9 "$((NOW - 60))" older; reset_calls
run_hook "PATH=$NOJQ_PATH" "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"
assert "9.b no jq: manifest version still resolved and warning printed" '[[ "$(msg)" == "$M120_W" ]]' "got: $OUT"
assert "9.c no jq: output still valid JSON" 'printf "%s" "$OUT" | jq -e . >/dev/null'
assert "9.d no jq: rc 0" '(( RC == 0 ))'

echo "== 10: refresh deduplication and lock aging =="
for i in 1 2 3; do
  new_xdg; old=$((NOW - 3 * DAY)); put_cache "$ID_M" v9.9.9 "$old" older; reset_calls
  o1="$SANDBOX/conc.$i.1"; o2="$SANDBOX/conc.$i.2"
  RUNS=$((RUNS + 2))
  env "PATH=$STUBBIN:$PATH" "HOME=$HOME_RW" "XDG_CACHE_HOME=$XDG" "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" SOLEUR_UPDATE_CHECK=1 bash "$HOOK" > "$o1" 2>/dev/null < "$STDIN_FILE" &
  p1=$!
  env "PATH=$STUBBIN:$PATH" "HOME=$HOME_RW" "XDG_CACHE_HOME=$XDG" "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" SOLEUR_UPDATE_CHECK=1 bash "$HOOK" > "$o2" 2>/dev/null < "$STDIN_FILE" &
  p2=$!
  wait "$p1" "$p2"
  [[ -s "$o1" ]] && BANNERS=$((BANNERS + 1)); [[ -s "$o2" ]] && BANNERS=$((BANNERS + 1))
  wait_children 1; settle 3
  assert "10.$i two concurrent starts both print the banner" '[[ -s "$o1" && -s "$o2" ]]'
  assert "10.$i two concurrent starts fetch once" '(( $(n_git) == 1 && $(n_refresh) == 1 ))' "git calls: $(n_git), refresh: $(n_refresh)"
done
# The lock ages out by its mtime. A stale cache is the setting; the lock decides whether to spawn.
lock_row() { # <name> <seconds-ago> <expect: suppress|takeover>
  new_xdg; old=$((NOW - 3 * DAY)); put_cache "$ID_M" v9.9.9 "$old" older
  mkdir "$(LOCK)"; age_path "$(LOCK)" "$2"; reset_calls
  run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"
  if [[ "$3" == takeover ]]; then
    wait_children 1
    assert "$1: banner still printed, one JSON value" '[[ "$(msg)" == "$M120_W" ]] && one_json' "got: $OUT"
    assert "$1: taken over, exactly one refresh runs and rewrites the cache" \
      '[[ -e "$SENT_GIT" && "$(n_git)" == 1 && "$(n_refresh)" == 1 && "$(cache_fetched "$ID_M")" != "$old" ]]' "git=$(n_git) refresh=$(n_refresh)"
  else
    settle 5
    assert "$1: banner still printed" '[[ "$(msg)" == "$M120_W" ]]' "got: $OUT"
    assert "$1: suppressed, no refresh reaches git or the resolver within the window" \
      '[[ ! -e "$SENT_GIT" ]] && (( $(n_git) == 0 && $(n_refresh) == 0 ))' "git=$(n_git) refresh=$(n_refresh)"
  fi
}
new_xdg; put_cache "$ID_M" v9.9.9 "$((NOW - 3 * DAY))" older; mkdir "$(LOCK)"; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"
settle 5
assert "10.d young lock: banner still printed" '[[ "$(msg)" == "$M120_W" ]]'
# One-sided by nature (a negative cannot be awaited): the positive rows above prove the child
# reaches the stub well within this window when it IS spawned.
assert "10.e young lock: no refresh reaches git within the window" '[[ ! -e "$SENT_GIT" ]] && (( $(n_git) == 0 && $(n_refresh) == 0 ))'
lock_row "10.f lock aged 5 minutes SUPPRESSES a spawn" 300 suppress
lock_row "10.g lock aged 590 s (just under the 600 s TTL) suppresses" 590 suppress
lock_row "10.h lock aged 30 s in the future (clock skew within tolerance) suppresses" -30 suppress
lock_row "10.i lock aged 610 s (just over the TTL) is taken over" 610 takeover
lock_row "10.j lock aged 11 minutes is taken over" 660 takeover
lock_row "10.k lock dated +3 days (clock change) is taken over" -$((3 * DAY)) takeover

echo "== 11: spawn hygiene: allowlisted environment, closed fds, never blocks =="
new_xdg; old=$((NOW - 3 * DAY)); put_cache "$ID_M" v9.9.9 "$old" older; reset_calls
mkdir -p "$SANDBOX/tmpdir"
run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1" "MY_API_SECRET=hunter2" "GITHUB_TOKEN=ghp_testtoken" \
  "ANTHROPIC_API_KEY=sk-test" "SOLEUR_FETCH_TIMEOUT=3" "TMPDIR=$SANDBOX/tmpdir" "https_proxy=http://127.0.0.1:9" \
  "NO_PROXY=localhost" "ALL_PROXY=" "SSL_CERT_FILE=/etc/ssl/test-ca.pem" "CURL_CA_BUNDLE=/etc/ssl/test-bundle.pem"
wait_children 1
assert "11.a the refresh ran (so the env witness below is not vacuous)" '[[ -e "$SENT_GIT" && "$(n_refresh)" == 1 ]]' "git=$(n_git) refresh=$(n_refresh)"
assert "11.b MY_API_SECRET and its value are NOT visible to the refresh child" '! grep -q "hunter2" "$RENV" && ! grep -q "^MY_API_SECRET=" "$RENV"'
assert "11.c GITHUB_TOKEN / ANTHROPIC_API_KEY are NOT visible to the refresh child" '! grep -qE "^(GITHUB_TOKEN|ANTHROPIC_API_KEY)=" "$RENV"'
assert "11.d the allowlisted vars ARE visible with their values" \
  'grep -q "^PATH=" "$RENV" && grep -qx "HOME=$HOME_RW" "$RENV" && grep -qx "XDG_CACHE_HOME=$XDG" "$RENV" && grep -qx "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "$RENV" && grep -qx "TMPDIR=$SANDBOX/tmpdir" "$RENV" && grep -qx "SOLEUR_FETCH_TIMEOUT=3" "$RENV" && grep -qx "https_proxy=http://127.0.0.1:9" "$RENV" && grep -qx "NO_PROXY=localhost" "$RENV"' "env: $(tr '\n' ' ' < "$RENV")"
assert "11.e an EMPTY allowlisted var (ALL_PROXY=) is not forwarded" '! grep -q "^ALL_PROXY=" "$RENV"'
assert "11.f the child sees nothing outside the allowlist (SOLEUR_UPDATE_CHECK included)" \
  'NAMES="$(sed -n "s/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p" "$RENV")"; ! grep -qvxE "PATH|HOME|XDG_CACHE_HOME|CLAUDE_PLUGIN_ROOT|TMPDIR|SOLEUR_FETCH_TIMEOUT|SSL_CERT_FILE|SSL_CERT_DIR|CURL_CA_BUNDLE|GIT_SSL_CAINFO|http_proxy|https_proxy|all_proxy|no_proxy|HTTP_PROXY|HTTPS_PROXY|ALL_PROXY|NO_PROXY|_|PWD|SHLVL|OLDPWD" <<<"$NAMES"' "env: $(tr '\n' ' ' < "$RENV")"
assert "11.g SOLEUR_FETCH_TIMEOUT reaches the fetch: the git argv carries lowSpeedTime=3 (exact argv, else the stub exits 64)" \
  '[[ -e "$SENT_GIT" ]] && grep -q "http.lowSpeedTime=3 ls-remote" "$CALLS"' "calls: $(cat "$CALLS")"
assert "11.h stdin, stdout and stderr of the detached child are all /dev/null" '[[ "$(cat "$RFDS")" == "fds: 0=null 1=null 2=null" ]]' "fds: $(cat "$RFDS")"
assert "11.i one JSON value on stdout" 'one_json' "out: $OUT"
assert "11.j the CA trust variables are forwarded to the child (a TLS-intercepting proxy must not silently break the daily refresh)" \
  'grep -qx "SSL_CERT_FILE=/etc/ssl/test-ca.pem" "$RENV" && grep -qx "CURL_CA_BUNDLE=/etc/ssl/test-bundle.pem" "$RENV"' "env: $(tr '\n' ' ' < "$RENV")"
# A symlinked cache dir is refused: the lock must not be created through it.
new_xdg; rm -rf "$XDG/soleur"; SYMT="$XDG/real-target"; mkdir -p "$SYMT"; ln -s "$SYMT" "$XDG/soleur"; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"
settle 3
assert "11.k symlinked cache dir: still a plain banner (fail open)" '[[ "$(msg)" == "$M120" ]] && (( RC == 0 ))' "out=$OUT rc=$RC"
assert "11.l symlinked cache dir: no lock created through the link and no refresh spawned" '[[ ! -e "$SYMT/refresh.lock" ]] && (( $(n_refresh) == 0 ))' "refresh=$(n_refresh)"

# A refresh child that SLEEPS must not delay the hook, hold its pipes, or die with it.
new_xdg; old=$((NOW - 3 * DAY)); put_cache "$ID_M" v9.9.9 "$old" older; reset_calls
run_hook "PATH=$SLOWBIN:$PATH" "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"
t_slow=$T_MS; done_at_return=0; [[ -e "$SENT_GIT_DONE" ]] && done_at_return=1
assert "11.j the hook returns in under ${LIM_MS} ms while the refresh child sleeps 3 s (never blocks)" '(( t_slow < LIM_MS ))' "took ${t_slow} ms"
assert "11.k the child had NOT finished when the hook returned (it is detached, not awaited)" '(( done_at_return == 0 ))'
assert "11.l the banner is printed, rc 0, exactly one JSON value, while the child is still running" '[[ "$(msg)" == "$M120_W" ]] && (( RC == 0 )) && one_json' "out: $OUT"
assert "11.m the child really started (so the timing above is not vacuous) and outlives the hook, then completes the refresh" \
  'wait_file "$SENT_GIT" && wait_file "$SENT_GIT_DONE" 100 && wait_children 1 && [[ "$(cache_fetched "$ID_M")" != "$old" ]]'
# Same with stderr merged into the captured pipe: a child holding stderr (or stdout) open would keep
# the command substitution waiting for EOF and print its output into it.
new_xdg; old=$((NOW - 3 * DAY)); put_cache "$ID_M" v9.9.9 "$old" older; reset_calls
MERGE_ERR=1
run_hook "PATH=$SLOWBIN:$PATH" "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"
MERGE_ERR=0
t_slow=$T_MS
assert "11.n stdout+stderr both captured: the hook still returns in under ${LIM_MS} ms (the child holds neither pipe)" '(( t_slow < LIM_MS ))' "took ${t_slow} ms"
assert "11.o stdout+stderr both captured: exactly one JSON value and nothing else leaked" 'one_json && [[ "$(msg)" == "$M120_W" ]]' "out: $OUT"
wait_children 1 100

echo "== 12: the cache is one file per install =="
# A cache for ANOTHER install id is simply not read: cache=missing, so a refresh IS spawned,
# and the other install's file is left alone.
new_xdg; put_cache "9.9.8" v9.9.9 "$((NOW - 60))" older; other_before="$(cat "$(CACHE 9.9.8)")"; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"
wait_children 1
assert "12.a a fresh cache keyed to ANOTHER install is not read: plain banner" '[[ "$(msg)" == "$M120" ]]' "got: $(msg)"
assert "12.b ... and the missing cache spawns a refresh that writes THIS install's own file" '[[ -d "$(LOCK)" && -e "$SENT_GIT" && "$(cache_field "$ID_M" relation_for)" == "$ID_M" ]]'
assert "12.c ... while the other install's file is untouched" '[[ "$(cat "$(CACHE 9.9.8)")" == "$other_before" ]]'
# The right file name but relation_for naming someone else: corrupt, never trusted.
new_xdg; put_cache "$ID_M" v9.9.9 "$((NOW - 60))" older "9.9.8"; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"
wait_children 1
assert "12.d relation_for for another install: not trusted (plain banner) and repaired by a refresh" '[[ "$(msg)" == "$M120" && -d "$(LOCK)" && "$(cache_field "$ID_M" relation_for)" == "$ID_M" ]]' "got: $(msg)"
# A truncated write loses the trailing complete=1: corrupt, not a fresh answer.
new_xdg; put_cache "$ID_M" v9.9.9 "$((NOW - 60))" older "$ID_M" 0; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"
wait_children 1
assert "12.e a cache without complete=1 is corrupt: no warning, refresh spawned and repaired" '[[ "$(msg)" == "$M120" && -d "$(LOCK)" && "$(cache_field "$ID_M" complete)" == 1 ]]' "got: $(msg)"
# fetched with a leading zero / zero must not wedge the cache (octal) or read as fresh.
for bad in 0 0123456789; do
  new_xdg; put_cache "$ID_M" v9.9.9 "$bad" older; reset_calls
  run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"
  wait_children 1
  assert "12.f fetched=$bad is corrupt: plain banner, refresh spawned, repaired" '[[ "$(msg)" == "$M120" && -d "$(LOCK)" && "$(cache_fetched "$ID_M")" != "$bad" ]]' "got: $(msg)"
done

echo "== 13: nothing is created outside an absolute cache dir =="
# HOME unset and no XDG: the resolver reports no cache dir. Run as the CURRENT user (no sudo) from an
# empty working directory: no `nonexistent`/`.cache` dir anywhere, nothing in the project cwd, no child.
new_cwd; reset_calls
run_hook -u HOME -u XDG_CACHE_HOME "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"
settle 3
assert "13.a HOME unset, no XDG: plain banner, rc 0" '[[ "$(msg)" == "$M120" ]] && (( RC == 0 ))' "got: $OUT rc=$RC"
assert "13.b nothing is created in the working directory" 'cwd_empty' "cwd: $(ls -A "$RUN_CWD")"
assert "13.c no /nonexistent directory appears (the old HOME fallback)" '[[ "$NONEX_BEFORE" == 1 ]] || [[ ! -e /nonexistent ]]'
assert "13.d no child spawned, no git, no lock decision" '(( $(n_refresh) + $(n_git) + $(n_curl) == 0 ))'
# A RELATIVE XDG_CACHE_HOME is ignored (XDG spec), never created under the user's project.
new_cwd; reset_calls
run_hook -u HOME "XDG_CACHE_HOME=relcache" "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"
settle 3
assert "13.e relative XDG and no HOME: plain banner, nothing created in cwd" '[[ "$(msg)" == "$M120" ]] && cwd_empty' "cwd: $(ls -A "$RUN_CWD")"
assert "13.f ... and no child spawned" '(( $(n_refresh) + $(n_git) == 0 ))'
new_cwd; new_home; reset_calls
run_hook "XDG_CACHE_HOME=relcache" "HOME=$H" "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"
wait_children 1
assert "13.g relative XDG with a valid HOME: nothing created in cwd; the cache lives under HOME/.cache instead" \
  'cwd_empty && [[ -d "$H/.cache/soleur/refresh.lock" && -e "$H/.cache/soleur/latest-release.$ID_M" ]]' "cwd: $(ls -A "$RUN_CWD")"
new_cwd; reset_calls
run_hook -u XDG_CACHE_HOME "HOME=relhome" "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"
settle 3
assert "13.h a relative HOME is ignored too: nothing created in cwd, no child" 'cwd_empty && (( $(n_refresh) == 0 ))' "cwd: $(ls -A "$RUN_CWD")"
default_cwd
# Defence in depth: even if a resolver ever reported a relative cache dir, the hook must not mkdir it.
mktree reldir 'printf "source=manifest\nversion=1.2.0\ncache=missing\ncache_dir=relcache/soleur\n"'
HOOK="$TREE_HOOK"; new_cwd; new_xdg; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"
settle 3
HOOK="$HOOK_REAL"
assert "13.i a RELATIVE cache_dir from the resolver: banner printed, nothing created in cwd" '[[ "$(msg)" == "$M120" ]] && cwd_empty' "cwd: $(ls -A "$RUN_CWD")"
default_cwd

echo "== 14: the hook fails open =="
fo_tree() { # <name> <resolver body>  -> runs the hook of that tree once (opt-in, valid manifest root)
  mktree "$1" "$2"; HOOK="$TREE_HOOK"; new_xdg; reset_calls
  run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"
  HOOK="$HOOK_REAL"
}
fo_tree exit3 'exit 3'
assert "14.a resolver exits 3 with no output: no banner, rc 0" '[[ -z "$OUT" ]] && (( RC == 0 ))' "out=$OUT rc=$RC"
fo_tree garbage1 'printf "source=manifest\nversion=banana\n"'
assert "14.b resolver prints a non-semver version: no banner, rc 0" '[[ -z "$OUT" ]] && (( RC == 0 ))' "out=$OUT rc=$RC"
fo_tree garbage2 'printf "source=commit\ncommit=ZZZ\n"; printf "\001\002 \377 noise\n"'
assert "14.c resolver prints a bad commit and binary noise: no banner, rc 0" '[[ -z "$OUT" ]] && (( RC == 0 ))' "out=$OUT rc=$RC"
fo_tree validfail 'printf "source=manifest\nversion=1.2.0\n"; exit 3'
assert "14.d resolver prints a valid source then exits 3: the plain banner, rc 0" '[[ "$(msg)" == "$M120" ]] && (( RC == 0 ))' "out=$OUT rc=$RC"
fo_tree inject 'printf "source=manifest\nversion=1.2.0\ncache=fresh\ncache_dir=/x\nlatest=v9\"9.9.9\nrelation=older\n"'
assert "14.e resolver prints a latest that is not a strict tag: plain banner (no JSON injection)" '[[ "$(msg)" == "$M120" ]] && one_json' "out=$OUT"
fo_tree wrongrel 'printf "source=manifest\nversion=1.2.0\ncache=fresh\ncache_dir=/x\nlatest=v9.9.9\nrelation=older \"}\n"'
assert "14.f relation must be exactly older to warn: plain banner" '[[ "$(msg)" == "$M120" ]]' "out=$OUT"
mktree gone 'exit 0'; rm -f "$TREES/gone/scripts/plugin-version.sh"; HOOK="$TREE_HOOK"; new_xdg; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"; HOOK="$HOOK_REAL"
assert "14.g resolver script missing: no banner, rc 0" '[[ -z "$OUT" ]] && (( RC == 0 ))' "out=$OUT rc=$RC"
mktree unreadable 'printf "source=manifest\nversion=1.2.0\n"'; chmod 000 "$TREES/unreadable/scripts/plugin-version.sh"
HOOK="$TREE_HOOK"; new_xdg; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"; HOOK="$HOOK_REAL"
if [[ "${EUID:-$(id -u)}" == 0 ]]; then
  skip "14.h resolver script unreadable: no banner, rc 0" "root reads a chmod 000 file"
else
  assert "14.h resolver script unreadable: no banner, rc 0" '[[ -z "$OUT" ]] && (( RC == 0 ))' "out=$OUT rc=$RC"
fi
chmod 644 "$TREES/unreadable/scripts/plugin-version.sh"
# `set -u` aborts with status 1 and no ERR trap; the EXIT trap must turn that into exit 0.
mktree unbound; awk '{ print } /^main\(\) \{$/ { print "  : \"$__soleur_unbound_probe\"" }' "$SUT" > "$TREES/unbound/hooks/version-banner.sh"
mktree unbound-notrap; awk '/^trap .exit 0. EXIT$/ { next } { print } /^main\(\) \{$/ { print "  : \"$__soleur_unbound_probe\"" }' "$SUT" > "$TREES/unbound-notrap/hooks/version-banner.sh"
HOOK="$TREES/unbound-notrap/hooks/version-banner.sh"; new_xdg; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST"
assert "14.i control: with the EXIT trap removed the injected unbound variable DOES abort non-zero" '(( RC != 0 ))' "rc=$RC"
HOOK="$TREES/unbound/hooks/version-banner.sh"; new_xdg; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST"
assert "14.j an unbound-variable abort inside the hook still exits 0 (EXIT trap), printing nothing" '[[ -z "$OUT" ]] && (( RC == 0 ))' "out=$OUT rc=$RC"
assert "14.k the injected copy still carries the probe (the row is not vacuous)" 'grep -q __soleur_unbound_probe "$TREES/unbound/hooks/version-banner.sh"'
HOOK="$HOOK_REAL"
# env -i with only PATH and the plugin root: no HOME, no XDG, no TMPDIR.
MINIMAL=1; new_cwd; new_xdg; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST"
assert "14.l env -i with only PATH+CLAUDE_PLUGIN_ROOT (default): banner printed, rc 0" '[[ "$(msg)" == "$M120" ]] && (( RC == 0 ))' "out=$OUT rc=$RC"
reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"
settle 3
MINIMAL=0
assert "14.m env -i, opt-in, no HOME: plain banner, rc 0, nothing created in cwd, no child" '[[ "$(msg)" == "$M120" ]] && (( RC == 0 )) && cwd_empty && (( $(n_refresh) == 0 ))' "out=$OUT rc=$RC"
default_cwd

echo "== 15: an in-place install (source=checkout) shows the checkout's HEAD commit =="
# A local-Folder marketplace loads the plugin from <top>/plugins/soleur, which has no manifest
# version and no commit-hash directory name; the resolver then reads <top>/.git by plain file
# reads. The hook shows it as `commit <sha12> (local checkout)`. Same rows in both directions:
# every shape that resolves prints, every malformed one stays silent, and none runs git.
# Not the stubbed release tag commit (STUB_SHA): that would answer `current` with no compare call.
CO_SHA=a1b2c3d4e5f60718293a4b5c6d7e8f9012345678; CO12="${CO_SHA:0:12}"
MCO="Soleur commit $CO12 (local checkout)"
MCO_W="$MCO — newer release v9.9.9 available"
mkco() { # <name> [sha] -> prints the top dir; the plugin root is <top>/plugins/soleur
  local top="$ROOTS/co/$1"
  assert_fixture_dir "$top"; rm -rf "$top"
  mkroot "$top/plugins/soleur"
  mkdir -p "$top/.git/refs/heads"
  printf 'ref: refs/heads/main\n' > "$top/.git/HEAD"
  printf '%s\n' "${2:-$CO_SHA}" > "$top/.git/refs/heads/main"
  printf '%s' "$top"
}
CO_CLONE="$(mkco clone)"
new_xdg; reset_calls
run_hook "PATH=$RPATH" "CLAUDE_PLUGIN_ROOT=$CO_CLONE/plugins/soleur"
assert "15.a default off: the banner names the checkout commit" '[[ "$(msg)" == "$MCO" ]]' "got: $(msg)"
assert "15.a2 default off: one JSON value, rc 0, zero network-binary calls" 'one_json && (( RC == 0 )) && [[ ! -s "$CALLS" ]]' "calls: $(cat "$CALLS")"
assert "15.a3 default off: one --installed resolver call, no lock" '[[ "$(cat "$RCALLS")" == "--installed" && ! -e "$(LOCK)" ]]' "calls: $(cat "$RCALLS")"
# the layouts the resolver understands all reach the banner
CO_BARE="$(mkco bare)"; printf '[core]\n\tbare = true\n' > "$CO_BARE/.git/config"
CO_DET="$(mkco det)"; printf '%s\n' "$CO_SHA" > "$CO_DET/.git/HEAD"
CO_PACK="$(mkco packed)"; rm -f "$CO_PACK/.git/refs/heads/main"; printf '%s refs/heads/main\n' "$CO_SHA" > "$CO_PACK/.git/packed-refs"
CO_WT="$(mkco wt)"; CO_WTC="$ROOTS/co/wt-common"; assert_fixture_dir "$CO_WTC"; rm -rf "$CO_WTC"
mkdir -p "$CO_WTC/worktrees/w" "$CO_WTC/refs/heads"; printf 'ref: refs/heads/main\n' > "$CO_WTC/worktrees/w/HEAD"
printf '../..\n' > "$CO_WTC/worktrees/w/commondir"; printf '%s\n' "$CO_SHA" > "$CO_WTC/refs/heads/main"
rm -rf "$CO_WT/.git"; printf 'gitdir: %s/worktrees/w\n' "$CO_WTC" > "$CO_WT/.git"
for lay in bare det pack wt; do
  case "$lay" in bare) t="$CO_BARE" ;; det) t="$CO_DET" ;; pack) t="$CO_PACK" ;; wt) t="$CO_WT" ;; esac
  new_xdg; reset_calls; run_hook "PATH=$RPATH" "CLAUDE_PLUGIN_ROOT=$t/plugins/soleur"
  assert "15.b layout $lay: prints the checkout banner" '[[ "$(msg)" == "$MCO" ]]' "got: $(msg)"
done
# silent: nothing readable, nothing printed, rc 0
CO_BAD="$(mkco bad)"; printf 'garbage\n' > "$CO_BAD/.git/HEAD"
CO_NOGIT="$(mkco nogit)"; rm -rf "$CO_NOGIT/.git"
CO_EMPTY="$(mkco emptyhead)"; : > "$CO_EMPTY/.git/HEAD"
for lay in bad nogit emptyhead; do
  case "$lay" in bad) t="$CO_BAD" ;; nogit) t="$CO_NOGIT" ;; emptyhead) t="$CO_EMPTY" ;; esac
  new_xdg; reset_calls; run_hook "CLAUDE_PLUGIN_ROOT=$t/plugins/soleur" "SOLEUR_UPDATE_CHECK=1"
  assert "15.c unreadable checkout ($lay): no output, rc 0, no git/curl, no lock" '[[ -z "$OUT" ]] && (( RC == 0 )) && (( $(n_git) + $(n_curl) == 0 )) && [[ ! -e "$(LOCK)" ]]' "got: $OUT"
done
# (the hostile .git/config proof lives in plugin-version.test.sh, against a repository real git can arm)
# opt-in: the cache is the one stable latest-release.checkout; a warning needs relation=older for THIS commit
new_xdg; put_cache checkout v9.9.9 "$((NOW - 60))" older "$CO12"; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$CO_CLONE/plugins/soleur" "SOLEUR_UPDATE_CHECK=1"
assert "15.e opt-in, fresh cache older: the warning is appended" '[[ "$(msg)" == "$MCO_W" ]]' "got: $(msg)"
assert "15.e2 opt-in, fresh cache: zero git/curl, no lock, one --cached-latest call" '(( $(n_git) + $(n_curl) == 0 )) && [[ ! -e "$(LOCK)" && "$(cat "$RCALLS")" == "--cached-latest" ]]' "calls: $(cat "$RCALLS")"
for rel in current unknown; do
  new_xdg; put_cache checkout v9.9.9 "$((NOW - 60))" "$rel" "$CO12"; reset_calls
  run_hook "CLAUDE_PLUGIN_ROOT=$CO_CLONE/plugins/soleur" "SOLEUR_UPDATE_CHECK=1"
  assert "15.f opt-in, relation=$rel: no warning" '[[ "$(msg)" == "$MCO" ]]' "got: $(msg)"
done
# an entry written for ANOTHER commit is not this checkout's answer: no warning, and a refresh is spawned
new_xdg; put_cache checkout v9.9.9 "$((NOW - 60))" older "fedcba987654"; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$CO_CLONE/plugins/soleur" "SOLEUR_UPDATE_CHECK=1"
wait_children 1
assert "15.g another commit's cache entry: plain banner (never someone else's warning)" '[[ "$(msg)" == "$MCO" ]]' "got: $(msg)"
assert "15.g2 ...and the refresh was spawned (cache=missing, not a corrupt-cache claim)" '[[ -d "$(LOCK)" ]] && (( $(n_refresh) == 1 ))' "calls: $(cat "$RCALLS")"
# END TO END against the real-shaped compare body: refresh, then the next start warns
new_xdg; reset_calls; echo ahead > "$MODEFILE"
run_hook "CLAUDE_PLUGIN_ROOT=$CO_CLONE/plugins/soleur" "SOLEUR_UPDATE_CHECK=1"
wait_children 1
assert "15.h no cache yet: plain banner, refresh spawned, one git and one compare curl" '[[ "$(msg)" == "$MCO" && -d "$(LOCK)" ]] && (( $(n_git) == 1 && $(n_curl) == 1 ))' "got: $(msg) git=$(n_git) curl=$(n_curl)"
assert "15.h2 the refresh wrote latest-release.checkout for this commit, relation older" \
  '[[ "$(cache_field checkout relation)" == older && "$(cache_field checkout relation_for)" == "$CO12" && ! -e "$(CACHE "$CO12")" ]]' "cache: $(cat "$(CACHE checkout)" 2>&1)"
assert "15.h3 END TO END: the next start warns, spawns nothing" \
  'rm -rf "$(LOCK)"; reset_calls; run_hook "CLAUDE_PLUGIN_ROOT=$CO_CLONE/plugins/soleur" "SOLEUR_UPDATE_CHECK=1"; [[ "$(msg)" == "$MCO_W" && ! -e "$(LOCK)" && "$(n_git)" == 0 && "$(n_curl)" == 0 ]]' "got: $(msg)"
# the label whitelist: a resolver answer outside it is silent, whatever the source says
mktree co-badhex 'printf "source=checkout\ncommit=NOTHEX123456\n"'; HOOK="$TREE_HOOK"
new_xdg; reset_calls; run_hook "CLAUDE_PLUGIN_ROOT=$CO_CLONE/plugins/soleur"
assert "15.i source=checkout with a non-hex commit: silent" '[[ -z "$OUT" ]] && (( RC == 0 ))' "got: $OUT"
mktree co-longhex 'printf "source=checkout\ncommit=0123456789abc\n"'; HOOK="$TREE_HOOK"
run_hook "CLAUDE_PLUGIN_ROOT=$CO_CLONE/plugins/soleur"
assert "15.j source=checkout with a 13-hex commit: silent" '[[ -z "$OUT" ]] && (( RC == 0 ))' "got: $OUT"
mktree co-injected 'printf "source=checkout\ncommit=0123456789ab\" injected\n"'; HOOK="$TREE_HOOK"
run_hook "CLAUDE_PLUGIN_ROOT=$CO_CLONE/plugins/soleur"
assert "15.k a commit value carrying a quote is silent (no JSON injection)" '[[ -z "$OUT" ]] && (( RC == 0 ))' "got: $OUT"
mktree co-label "printf 'source=checkout\\ncommit=$CO12\\n'"; HOOK="$TREE_HOOK"
run_hook "CLAUDE_PLUGIN_ROOT=$CO_CLONE/plugins/soleur"
assert "15.l control: a valid source=checkout answer prints the label (the silent rows are not vacuous)" '[[ "$(msg)" == "$MCO" ]]' "got: $(msg)"
mktree co-other 'printf "source=checkouts\ncommit=0123456789ab\n"'; HOOK="$TREE_HOOK"
run_hook "CLAUDE_PLUGIN_ROOT=$CO_CLONE/plugins/soleur"
assert "15.m an unknown source value stays silent" '[[ -z "$OUT" ]] && (( RC == 0 ))' "got: $OUT"
HOOK="$HOOK_REAL"

# --- verdict ------------------------------------------------------------
# Floors are the EXACT counts of a full run (no slack: a vanished section must turn the suite red).
# The root-only skips never run the subject, so they lower the run/banner floors by what they skipped.
MIN_CASES=234
if (( CASES < MIN_CASES )); then
  printf 'FATAL: assertion floor breached -- ran %d cases, floor is %d. Cases were deleted, or the suite aborted early.\n' \
    "$CASES" "$MIN_CASES" >&2
  exit 1
fi
if (( passes + fails + SKIPS != CASES )); then
  printf 'FATAL: verdict accounting broken -- passes(%d) + fails(%d) + skips(%d) != CASES(%d)\n' "$passes" "$fails" "$SKIPS" "$CASES" >&2
  exit 1
fi
# The subject must actually have run and printed: a harness that asserts on empty output
# for every row would still satisfy the "prints nothing" rows.
MIN_RUNS=112; MIN_BANNERS=91
# A root-only skip never runs the subject, so the observed side is credited with what it skipped.
if (( RUNS + SKIP_RUN_DEFICIT < MIN_RUNS || BANNERS + SKIP_RUN_DEFICIT < MIN_BANNERS )); then
  printf 'FATAL: subject ran %d times (floor %d) and printed %d banners (floor %d). The harness asserted without driving the hook.\n' \
    "$RUNS" "$MIN_RUNS" "$BANNERS" "$MIN_BANNERS" >&2
  exit 1
fi

printf '\n%d passed, %d failed, %d skipped (%d cases, %d subject invocations, %d banners)\n' \
  "$passes" "$fails" "$SKIPS" "$CASES" "$RUNS" "$BANNERS"
if (( ${#FAILURES[@]} > 0 )); then
  printf 'FAILURES:\n'
  for f in "${FAILURES[@]}"; do printf '  - %s\n' "$f"; done
  exit 1
fi
printf 'ALL TESTS PASSED\n'
exit 0
