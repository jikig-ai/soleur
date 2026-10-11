#!/usr/bin/env bash
# Guard suite for plugins/soleur/hooks/version-banner.sh (plugin version visibility, D4).
#
# WHAT IS PINNED. The hook is a SessionStart banner that must (1) cost no network by
# default, (2) never block on the network when opted in, (3) never warn about a version that
# is not actually older, and (4) fail open. Each property has rows in BOTH directions: every
# "prints the warning" row is paired with a row that differs in one field and must NOT.
#
# HOW NETWORK IS WITNESSED. `git` and `curl` are PATH-shimmed stubs. Each appends its argv to
# a calls file and exits 64 on any argv it was not written to expect, so an unexpected
# invocation is both recorded AND loud. The default-off rows assert the calls file holds zero
# lines; a hook that ran `git` even once would show it. The detached background refresh is
# asynchronous, so rows that expect one wait on a sentinel file the stub writes (never a
# fixed sleep) and then on the cache being rewritten.
#
# The lock directory is the synchronous evidence of a spawn decision (the hook creates it
# BEFORE spawning), so the "no refresh" rows assert it is absent rather than racing a child.

# The conditions handed to assert() are eval strings by design; single quotes are intended.
# shellcheck disable=SC2016
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -P "$DIR/../../.." && pwd -P)"
SUT="$REPO_ROOT/plugins/soleur/hooks/version-banner.sh"

# test-helpers.sh owns assert_fixture_dir. It sets -euo pipefail; restore this suite's
# accumulate-then-exit contract.
# shellcheck source=plugins/soleur/test/test-helpers.sh
source "$DIR/test-helpers.sh" || { echo "FATAL: could not source test-helpers.sh" >&2; exit 2; }
set +e -uo pipefail

command -v jq >/dev/null 2>&1 || { echo "FATAL: jq is required by this suite" >&2; exit 2; }
[[ -f "$SUT" ]] || { echo "FATAL: subject not found: $SUT" >&2; exit 2; }

SANDBOX="$(mktemp -d -t verbanner.XXXXXXXX)" || { echo "FATAL: mktemp failed" >&2; exit 2; }
assert_fixture_dir "$SANDBOX"
# A read-only fixture dir cannot be removed by rm -rf until it is writable again.
trap 'chmod -R u+w "$SANDBOX" 2>/dev/null; rm -rf "$SANDBOX"' EXIT INT TERM HUP

# An ambient value from the operator's shell must not rewrite the suite's meaning.
unset SOLEUR_UPDATE_CHECK SOLEUR_DISABLE_VERSION_BANNER CODEX_THREAD_ID PLUGIN_ROOT \
      CLAUDE_PLUGIN_ROOT SOLEUR_FETCH_TIMEOUT

passes=0
fails=0
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

_p1=$passes; _f1=$fails; _c1=$CASES
assert "instrument self-test (assert TRUE arm)"  'true'  >/dev/null
assert "instrument self-test (assert FALSE arm)" 'false' >/dev/null 2>&1
if (( passes != _p1 + 1 )) || (( fails != _f1 + 1 )) || (( CASES != _c1 + 2 )); then
  printf 'FATAL: assert() does not gate on its condition (pass %d->%d, fail %d->%d, cases %d->%d)\n' \
    "$_p1" "$passes" "$_f1" "$fails" "$_c1" "$CASES" >&2
  exit 2
fi
passes=$_p1; fails=$_f1; CASES=$_c1; FAILURES=()

# --- stubs --------------------------------------------------------------
STUBBIN="$SANDBOX/stubs"; assert_fixture_dir "$STUBBIN"; mkdir -p "$STUBBIN"
CALLS="$SANDBOX/calls"; : > "$CALLS"
SENT_GIT="$SANDBOX/sentinel.git"
SENT_CURL="$SANDBOX/sentinel.curl"
STUB_SHA="0123456789abcdef0123456789abcdef01234567"

cat > "$STUBBIN/git" <<STUB
#!/usr/bin/env bash
printf 'git %s\n' "\$*" >> "$CALLS"
if [[ "\$*" == "ls-remote --tags https://github.com/jikig-ai/soleur.git refs/tags/v*" ]]; then
  printf '%s\trefs/tags/v9.9.9\n' "$STUB_SHA"
  : > "$SENT_GIT"
  exit 0
fi
exit 64
STUB
cat > "$STUBBIN/curl" <<STUB
#!/usr/bin/env bash
printf 'curl %s\n' "\$*" >> "$CALLS"
case "\$*" in
  *api.github.com/repos/jikig-ai/soleur/compare/*)
    : > "$SENT_CURL"
    printf '{"status":"ahead","ahead_by":3}'
    exit 0 ;;
esac
exit 64
STUB
chmod +x "$STUBBIN/git" "$STUBBIN/curl"

# The stubs are part of the instrument: prove they record AND discriminate argv.
git_stub_unexpected_rc=0; "$STUBBIN/git" status >/dev/null 2>&1 || git_stub_unexpected_rc=$?
curl_stub_unexpected_rc=0; "$STUBBIN/curl" https://example.invalid >/dev/null 2>&1 || curl_stub_unexpected_rc=$?
assert "stub self-test: git exits 64 on unexpected argv" '(( git_stub_unexpected_rc == 64 ))' "rc=$git_stub_unexpected_rc"
assert "stub self-test: curl exits 64 on unexpected argv" '(( curl_stub_unexpected_rc == 64 ))' "rc=$curl_stub_unexpected_rc"
assert "stub self-test: unexpected argv was recorded" 'grep -q "^git status$" "$CALLS" && grep -q "^curl https://example.invalid$" "$CALLS"'
: > "$CALLS"

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
R_COMMIT="$ROOTS/$COMMIT12";         mkroot "$R_COMMIT"
R_UNKNOWN="$ROOTS/not-a-hash-dir";   mkroot "$R_UNKNOWN"
R_MISSING="$ROOTS/does-not-exist"

HOME_RW="$SANDBOX/home"; assert_fixture_dir "$HOME_RW"; mkdir -p "$HOME_RW"
NOW="$(date +%s)"
DAY=86400

XDG_N=0
XDG=""
new_xdg() { # fresh cache home per row; sets XDG
  XDG_N=$((XDG_N + 1))
  XDG="$SANDBOX/xdg.$XDG_N"
  assert_fixture_dir "$XDG"
  mkdir -p "$XDG/soleur" || { echo "FATAL: mkdir $XDG" >&2; exit 2; }
}
CACHE() { printf '%s' "$XDG/soleur/latest-release"; }
LOCK() { printf '%s' "$XDG/soleur/refresh.lock"; }

put_cache() { # <tag> <fetched-epoch> <relation> <relation_for>
  assert_fixture_dir "$XDG"
  printf 'tag=%s\nsha=%s\nfetched=%s\nrelation=%s\nrelation_for=%s\nreason=\n' \
    "$1" "$STUB_SHA" "$2" "$3" "$4" > "$(CACHE)"
}

cache_fetched() { sed -n 's/^fetched=//p' "$(CACHE)" 2>/dev/null | head -1; }

# --- harness ------------------------------------------------------------
OUT=""; RC=0; RUNS=0; BANNERS=0
reset_calls() { : > "$CALLS"; rm -f "$SENT_GIT" "$SENT_CURL"; }
run_hook() { # [VAR=value ...] [-u VAR ...]
  RUNS=$((RUNS + 1))
  # `env` treats everything after the first operand as the command, so options must come first.
  local -a unsets=(-u CODEX_THREAD_ID -u PLUGIN_ROOT -u SOLEUR_UPDATE_CHECK -u SOLEUR_DISABLE_VERSION_BANNER)
  local -a sets=("PATH=$STUBBIN:$PATH" "HOME=$HOME_RW")
  local drop_xdg=0
  while (( $# )); do
    if [[ "$1" == "-u" ]]; then
      unsets+=(-u "$2"); [[ "$2" == XDG_CACHE_HOME ]] && drop_xdg=1; shift 2
    else
      sets+=("$1"); shift
    fi
  done
  (( drop_xdg )) || sets+=("XDG_CACHE_HOME=$XDG")
  OUT="$(env "${unsets[@]}" "${sets[@]}" bash "$SUT" 2>/dev/null </dev/null)"
  RC=$?
  [[ -n "$OUT" ]] && BANNERS=$((BANNERS + 1))
  return 0
}
n_git()  { local n; n="$(grep -c '^git ' "$CALLS" 2>/dev/null || true)";  printf '%s' "${n:-0}"; }
n_curl() { local n; n="$(grep -c '^curl ' "$CALLS" 2>/dev/null || true)"; printf '%s' "${n:-0}"; }
msg() { printf '%s' "$OUT" | jq -r '.systemMessage // ""' 2>/dev/null; }

# Bounded wait on a file, polling with a builtin timeout read (no fixed sleep, no external sleep).
wait_file() { # <path> [tries]
  local i
  for ((i = 0; i < ${2:-200}; i++)); do
    [[ -e "$1" ]] && return 0
    read -r -t 0.05 <> <(:) 2>/dev/null || true
  done
  [[ -e "$1" ]]
}
# Wait for the background refresh to REWRITE the cache (fetched changed from $1).
wait_refreshed() { # <old-fetched> [tries]
  local i cur
  for ((i = 0; i < ${2:-200}; i++)); do
    cur="$(cache_fetched)"
    [[ -n "$cur" && "$cur" != "$1" ]] && return 0
    read -r -t 0.05 <> <(:) 2>/dev/null || true
  done
  return 1
}

# A probe that proves msg() extracts the field the hook writes, not a decoy.
OUT='{"systemMessage":"MARK","decoy":"DECOY"}'
if [[ "$(msg)" != "MARK" ]]; then printf 'FATAL: msg() does not extract systemMessage\n' >&2; exit 2; fi
OUT=""

echo "== 1: default off makes zero network calls and prints the plain banner =="
for v in UNSET 0 EMPTY yes true 2; do
  new_xdg; put_cache v9.9.9 "$((NOW - 3 * DAY))" older 1.2.0   # stale AND would warn if on
  reset_calls
  case "$v" in
    UNSET) run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" ;;
    EMPTY) run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=" ;;
    *)     run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=$v" ;;
  esac
  assert "1.$v rc is 0" '(( RC == 0 ))'
  assert "1.$v prints the installed version only" '[[ "$(msg)" == "Soleur v1.2.0" ]]' "got: $(msg)"
  assert "1.$v zero git calls" '(( $(n_git) == 0 ))' "git calls: $(n_git)"
  assert "1.$v zero curl calls" '(( $(n_curl) == 0 ))' "curl calls: $(n_curl)"
  assert "1.$v no refresh lock taken (no spawn decision)" '[[ ! -e "$(LOCK)" ]]'
done
# Same for a commit-hash install, where a network-on hook would also call curl.
new_xdg; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_COMMIT"
assert "1.commit default off prints commit identity" '[[ "$(msg)" == "Soleur commit '"$COMMIT12"'" ]]' "got: $(msg)"
assert "1.commit default off zero git and curl calls" '(( $(n_git) + $(n_curl) == 0 ))'

echo "== 2: opt-in + fresh cache warns without calling git =="
new_xdg; put_cache v9.9.9 "$((NOW - 60))" older 1.2.0; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"
assert "2.a manifest: warning names the newer tag" '[[ "$(msg)" == "Soleur v1.2.0 — newer release v9.9.9 available" ]]' "got: $(msg)"
assert "2.b manifest: zero git calls on a fresh cache" '(( $(n_git) == 0 ))'
assert "2.c manifest: no refresh lock" '[[ ! -e "$(LOCK)" ]]'
new_xdg; put_cache v9.9.9 "$((NOW - 60))" older "$COMMIT12"; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_COMMIT" "SOLEUR_UPDATE_CHECK=1"
assert "2.d commit install: warning printed" '[[ "$(msg)" == "Soleur commit '"$COMMIT12"' — newer release v9.9.9 available" ]]' "got: $(msg)"
assert "2.e commit install: zero git and curl calls" '(( $(n_git) + $(n_curl) == 0 ))'
# Paired negatives: relation current, and a cache computed for a DIFFERENT install.
new_xdg; put_cache v9.9.9 "$((NOW - 60))" current 1.2.0; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"
assert "2.f relation=current prints no warning" '[[ "$(msg)" == "Soleur v1.2.0" ]]' "got: $(msg)"
new_xdg; put_cache v9.9.9 "$((NOW - 60))" older 0.0.1; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"
assert "2.g cache computed for another install prints no warning" '[[ "$(msg)" == "Soleur v1.2.0" ]]' "got: $(msg)"

echo "== 3: opt-in + stale cache prints the stale answer and spawns exactly one refresh =="
new_xdg; old=$((NOW - 3 * DAY)); put_cache v9.9.9 "$old" older 1.2.0; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"
assert "3.a stale value used now (warning present)" '[[ "$(msg)" == "Soleur v1.2.0 — newer release v9.9.9 available" ]]' "got: $(msg)"
assert "3.b hook returned with rc 0" '(( RC == 0 ))'
assert "3.c lock taken synchronously" '[[ -d "$(LOCK)" ]]'
assert "3.d background refresh reached git (sentinel)" 'wait_file "$SENT_GIT"'
assert "3.e background refresh rewrote the cache" 'wait_refreshed "$old"'
assert "3.f exactly one git ls-remote, with the fixed argv" \
  '(( $(n_git) == 1 )) && grep -q "^git ls-remote --tags https://github.com/jikig-ai/soleur.git refs/tags/v\*$" "$CALLS"' "calls: $(cat "$CALLS")"
assert "3.g manifest install needs no compare call" '(( $(n_curl) == 0 ))'
assert "3.h the refreshed cache is now fresh: next start spawns nothing and warns" \
  'rm -rf "$(LOCK)"; reset_calls; run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"; [[ "$(msg)" == "Soleur v1.2.0 — newer release v9.9.9 available" && ! -e "$(LOCK)" && "$(n_git)" == 0 ]]'

new_xdg; old=$((NOW - 3 * DAY)); put_cache v9.9.9 "$old" current "$COMMIT12"; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_COMMIT" "SOLEUR_UPDATE_CHECK=1"
assert "3.i commit install: stale relation=current prints plain banner" '[[ "$(msg)" == "Soleur commit '"$COMMIT12"'" ]]' "got: $(msg)"
assert "3.j commit install: refresh reached curl compare" 'wait_file "$SENT_CURL" && wait_refreshed "$old"'
assert "3.k commit install: one git, one curl" '(( $(n_git) == 1 && $(n_curl) == 1 ))' "git=$(n_git) curl=$(n_curl)"

new_xdg; reset_calls    # missing cache
run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"
assert "3.l missing cache: plain banner, no warning" '[[ "$(msg)" == "Soleur v1.2.0" ]]' "got: $(msg)"
assert "3.m missing cache: one refresh spawned and completed" 'wait_file "$SENT_GIT" && wait_file "$(CACHE)" && (( $(n_git) == 1 ))'

new_xdg; printf 'garbage\n' > "$(CACHE)"; reset_calls    # corrupt cache
run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"
assert "3.n corrupt cache: plain banner, refresh lock taken" '[[ "$(msg)" == "Soleur v1.2.0" && -d "$(LOCK)" ]]' "got: $(msg)"
assert "3.o corrupt cache: refresh repairs it" 'wait_file "$SENT_GIT" && wait_refreshed ""'

echo "== 4: future-dated cache is stale =="
new_xdg; old=$((NOW - 100)); put_cache v9.9.9 "$old" older 1.2.0
touch -d '+3 days' "$(CACHE)" 2>/dev/null || touch -t 203512312359 "$(CACHE)"
reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"
assert "4.a future mtime: refresh decision taken (lock present)" '[[ -d "$(LOCK)" ]]'
assert "4.b future mtime: stale value still shown" '[[ "$(msg)" == "Soleur v1.2.0 — newer release v9.9.9 available" ]]' "got: $(msg)"
assert "4.c future mtime: refresh ran" 'wait_file "$SENT_GIT" && wait_refreshed "$old"'
new_xdg; put_cache v9.9.9 "$((NOW + 3 * DAY))" older 1.2.0; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"
assert "4.d future fetched epoch: refresh decision taken" '[[ -d "$(LOCK)" ]]'
assert "4.e future fetched epoch: refresh ran" 'wait_file "$SENT_GIT" && wait_refreshed "$((NOW + 3 * DAY))"'

echo "== 5: downgrade and equal versions never warn =="
new_xdg; put_cache v1.0.0 "$((NOW - 60))" current 2.0.0; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_NEWER" "SOLEUR_UPDATE_CHECK=1"
assert "5.a installed newer than cached latest: no warning" '[[ "$(msg)" == "Soleur v2.0.0" ]]' "got: $(msg)"
# A cache that LIES (relation=older although installed is newer) must still not warn.
new_xdg; put_cache v1.0.0 "$((NOW - 60))" older 2.0.0; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_NEWER" "SOLEUR_UPDATE_CHECK=1"
assert "5.b a lying relation=older cache still prints no warning" '[[ "$(msg)" == "Soleur v2.0.0" ]]' "got: $(msg)"
new_xdg; put_cache v9.9.9 "$((NOW - 60))" older 9.9.9; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_EQUAL" "SOLEUR_UPDATE_CHECK=1"
assert "5.c equal versions: no warning even if relation=older is cached" '[[ "$(msg)" == "Soleur v9.9.9" ]]' "got: $(msg)"
new_xdg; put_cache v1.10.0 "$((NOW - 60))" older 1.9.0; reset_calls
R_NINE="$ROOTS/manifest-1.9.0"; mkroot "$R_NINE" "1.9.0"
run_hook "CLAUDE_PLUGIN_ROOT=$R_NINE" "SOLEUR_UPDATE_CHECK=1"
assert "5.d semver order is numeric (1.9.0 < 1.10.0 warns)" '[[ "$(msg)" == "Soleur v1.9.0 — newer release v1.10.0 available" ]]' "got: $(msg)"

echo "== 6: kill switch and skip conditions print nothing =="
new_xdg; put_cache v9.9.9 "$((NOW - 3 * DAY))" older 1.2.0; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1" "SOLEUR_DISABLE_VERSION_BANNER=1"
assert "6.a kill switch: no output" '[[ -z "$OUT" ]]' "got: $OUT"
assert "6.b kill switch: rc 0" '(( RC == 0 ))'
assert "6.c kill switch: no lock, no network" '[[ ! -e "$(LOCK)" ]] && (( $(n_git) + $(n_curl) == 0 ))'
run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_DISABLE_VERSION_BANNER=0"
assert "6.d kill switch is exactly 1 (0 leaves the banner on)" '[[ "$(msg)" == "Soleur v1.2.0" ]]' "got: $(msg)"
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
assert "6.k other-harness rows made no network call and took no lock" '(( $(n_git) + $(n_curl) == 0 )) && [[ ! -e "$(LOCK)" ]]'

echo "== 7: output is one valid JSON object =="
SHAPES=0
for root in "$R_MANIFEST" "$R_COMMIT" "$R_NEWER"; do
  for opt in "" 1; do
    new_xdg; put_cache v9.9.9 "$((NOW - 60))" older "$(basename "$root" | sed 's/^manifest-//')"
    run_hook "CLAUDE_PLUGIN_ROOT=$root" "SOLEUR_UPDATE_CHECK=$opt"
    SHAPES=$((SHAPES + 1))
    assert "7.$SHAPES ($(basename "$root"), opt=${opt:-off}) jq -e parses it" 'printf "%s" "$OUT" | jq -e . >/dev/null'
    assert "7.$SHAPES exactly one JSON value on one line" '[[ "$(printf "%s" "$OUT" | jq -s length)" == 1 && "$(printf "%s\n" "$OUT" | wc -l)" == 1 ]]'
    assert "7.$SHAPES only key is systemMessage (no additionalContext)" '[[ "$(printf "%s" "$OUT" | jq -c "keys")" == "[\"systemMessage\"]" ]]'
    assert "7.$SHAPES systemMessage shape" '[[ "$(msg)" =~ ^Soleur\ (v[0-9]+\.[0-9]+\.[0-9]+|commit\ [0-9a-f]{12}) ]]' "got: $(msg)"
  done
done

echo "== 8: fail open under an unwritable HOME =="
RO_HOME="$SANDBOX/ro-home"; assert_fixture_dir "$RO_HOME"; mkdir -p "$RO_HOME"; chmod 555 "$RO_HOME"
BLOCKED_HOME="$SANDBOX/blocked-home-file"; assert_fixture_dir "$BLOCKED_HOME"; : > "$BLOCKED_HOME"
for h in "$RO_HOME" "$BLOCKED_HOME/sub"; do
  reset_calls
  run_hook -u XDG_CACHE_HOME "HOME=$h" "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"
  tag="$(basename "$h")"
  assert "8.$tag rc is 0" '(( RC == 0 ))'
  assert "8.$tag still prints the banner as valid JSON" '[[ "$(msg)" == "Soleur v1.2.0" ]]' "got: $OUT"
  assert "8.$tag spawns nothing it cannot cache" '(( $(n_git) + $(n_curl) == 0 ))'
  run_hook -u XDG_CACHE_HOME "HOME=$h" "CLAUDE_PLUGIN_ROOT=$R_MANIFEST"
  assert "8.$tag default-off also rc 0" '(( RC == 0 )) && [[ "$(msg)" == "Soleur v1.2.0" ]]'
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
new_xdg; put_cache v9.9.9 "$((NOW - 60))" older 1.2.0; reset_calls
run_hook "PATH=$NOJQ_PATH" "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"
assert "9.b no jq: manifest version still resolved and warning printed" '[[ "$(msg)" == "Soleur v1.2.0 — newer release v9.9.9 available" ]]' "got: $OUT"
assert "9.c no jq: output still valid JSON" 'printf "%s" "$OUT" | jq -e . >/dev/null'
assert "9.d no jq: rc 0" '(( RC == 0 ))'

echo "== 10: refresh deduplication =="
for i in 1 2 3; do
  new_xdg; old=$((NOW - 3 * DAY)); put_cache v9.9.9 "$old" older 1.2.0; reset_calls
  o1="$SANDBOX/conc.$i.1"; o2="$SANDBOX/conc.$i.2"
  RUNS=$((RUNS + 2))
  env "PATH=$STUBBIN:$PATH" "HOME=$HOME_RW" "XDG_CACHE_HOME=$XDG" "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" SOLEUR_UPDATE_CHECK=1 bash "$SUT" > "$o1" 2>/dev/null </dev/null &
  p1=$!
  env "PATH=$STUBBIN:$PATH" "HOME=$HOME_RW" "XDG_CACHE_HOME=$XDG" "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" SOLEUR_UPDATE_CHECK=1 bash "$SUT" > "$o2" 2>/dev/null </dev/null &
  p2=$!
  wait "$p1" "$p2"
  [[ -s "$o1" ]] && BANNERS=$((BANNERS + 1)); [[ -s "$o2" ]] && BANNERS=$((BANNERS + 1))
  wait_file "$SENT_GIT" >/dev/null; wait_refreshed "$old" >/dev/null
  assert "10.$i two concurrent starts both print the banner" '[[ -s "$o1" && -s "$o2" ]]'
  assert "10.$i two concurrent starts fetch once" '(( $(n_git) == 1 ))' "git calls: $(n_git)"
done
# An unexpired lock suppresses the spawn; an expired one is taken over.
new_xdg; put_cache v9.9.9 "$((NOW - 3 * DAY))" older 1.2.0; mkdir "$(LOCK)"; reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"
assert "10.d young lock: banner still printed" '[[ "$(msg)" == "Soleur v1.2.0 — newer release v9.9.9 available" ]]'
# One-sided by nature (a negative cannot be awaited): the positive rows above prove the
# child reaches the stub within this window when it IS spawned.
assert "10.e young lock: no refresh reaches git within the window" '! wait_file "$SENT_GIT" 20 && (( $(n_git) == 0 ))'
new_xdg; old=$((NOW - 3 * DAY)); put_cache v9.9.9 "$old" older 1.2.0; mkdir "$(LOCK)"
touch -d '-2 hours' "$(LOCK)" 2>/dev/null || touch -t 200001010000 "$(LOCK)"
reset_calls
run_hook "CLAUDE_PLUGIN_ROOT=$R_MANIFEST" "SOLEUR_UPDATE_CHECK=1"
assert "10.f expired lock is taken over and a refresh runs" 'wait_file "$SENT_GIT" && wait_refreshed "$old" && (( $(n_git) == 1 ))'

# --- verdict ------------------------------------------------------------
MIN_CASES=100
if (( CASES < MIN_CASES )); then
  printf 'FATAL: assertion floor breached -- ran %d cases, floor is %d. Cases were deleted, or the suite aborted early.\n' \
    "$CASES" "$MIN_CASES" >&2
  exit 1
fi
if (( passes + fails != CASES )); then
  printf 'FATAL: verdict accounting broken -- passes(%d) + fails(%d) != CASES(%d)\n' "$passes" "$fails" "$CASES" >&2
  exit 1
fi
# The subject must actually have run and printed: a harness that asserts on empty output
# for every row would still satisfy the "prints nothing" rows.
MIN_RUNS=45; MIN_BANNERS=38
if (( RUNS < MIN_RUNS || BANNERS < MIN_BANNERS )); then
  printf 'FATAL: subject ran %d times (floor %d) and printed %d banners (floor %d). The harness asserted without driving the hook.\n' \
    "$RUNS" "$MIN_RUNS" "$BANNERS" "$MIN_BANNERS" >&2
  exit 1
fi

printf '\n%d passed, %d failed (%d cases, %d subject invocations, %d banners)\n' \
  "$passes" "$fails" "$CASES" "$RUNS" "$BANNERS"
if (( ${#FAILURES[@]} > 0 )); then
  printf 'FAILURES:\n'
  for f in "${FAILURES[@]}"; do printf '  - %s\n' "$f"; done
  exit 1
fi
printf 'ALL TESTS PASSED\n'
exit 0
