#!/usr/bin/env bash
# Guard suite for plugins/soleur/scripts/plugin-version.sh.
#
# The resolver feeds the SessionStart banner, /soleur:version and /soleur:help, so the
# properties pinned here are the ones a user would be misled by if they broke:
#   * it never reports a version it did not read (nested JSON keys, prerelease tags, other
#     tag families, a cache written for another install);
#   * "cannot tell" (offline, timeout, diverged, parse failure, stale cache) is never
#     rendered as "current";
#   * the lookups cannot be redirected or authenticated by the caller's environment: a
#     neutral cwd, no user/project git config, https only, bounded by a timeout;
#   * the cache is per install, absolute-path only, private (0600/0700), validated on read,
#     and a failed compare is retried within the hour rather than silenced for a day;
#   * it always exits 0 and works without jq, git, curl or timeout and with an unwritable cache.
#
# HOW THE NETWORK IS WITNESSED. PATH carries a fake `git` and `curl`. Each appends its argv
# to a calls file, records its cwd and the environment keys that could redirect it, and exits
# 64 on any shape the resolver is not supposed to send. No row reaches the network.
#
# Every behaviour row has a must-NOT sibling that differs in one field (see the section
# banners). The verdict is read from the append-only FAILURES ledger, not from a counter.

# Conditions are passed as plain strings in a few places; single quotes are intended.
# shellcheck disable=SC2016
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

# An ambient value from the operator's shell must not rewrite the suite's meaning.
unset SOLEUR_FETCH_TIMEOUT CODEX_THREAD_ID XDG_CACHE_HOME CLAUDE_PLUGIN_ROOT PLUGIN_ROOT \
      SOLEUR_UPDATE_CHECK SOLEUR_DISABLE_VERSION_BANNER

DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -P "$DIR/../../.." && pwd -P)"
SUT="$REPO_ROOT/plugins/soleur/scripts/plugin-version.sh"

# shellcheck source=plugins/soleur/test/test-helpers.sh
source "$DIR/test-helpers.sh" || { echo "FATAL: could not source test-helpers.sh" >&2; exit 2; }
set +e -uo pipefail
[[ -f "$SUT" ]] || { echo "FATAL: subject not found: $SUT" >&2; exit 2; }

SANDBOX="$(mktemp -d -t plugver.XXXXXXXX)" || { echo "FATAL: mktemp failed" >&2; exit 2; }
assert_fixture_dir "$SANDBOX"
# Composed with test-helpers.sh's own cleanup: a bare `trap ... EXIT` here would replace it
# and leak the soleur-inc-* incident-telemetry sandbox. chmod first: a fixture may be read-only.
trap 'chmod -R u+w "$SANDBOX" 2>/dev/null; rm -rf "$SANDBOX"; declare -F _soleur_sb_cleanup >/dev/null && _soleur_sb_cleanup' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

REAL_BASH="$(command -v bash)"

mkd() { # name -> a fresh fixture directory under the sandbox (printed)
  local d="$SANDBOX/$1"
  assert_fixture_dir "$d"
  rm -rf "$d"; mkdir -p "$d"
  printf '%s' "$d"
}

STUBS="$(mkd stubs)"
ROOTS="$(mkd roots)"
CALLS="$SANDBOX/calls"; : > "$CALLS"
GITLOG="$SANDBOX/gitlog"; : > "$GITLOG"
CURLARGS="$SANDBOX/curlargs"; : > "$CURLARGS"
mkdir -p "$SANDBOX/home" "$SANDBOX/cwd"
assert_fixture_dir "$SANDBOX/home"; assert_fixture_dir "$SANDBOX/cwd"

assert_fixture_dir "$STUBS"
cat > "$STUBS/git" <<'STUB'
#!/usr/bin/env bash
echo "git $*" >> "${STUB_CALLS:-/dev/null}"
{
  echo "argv=$*"
  echo "cwd=$PWD"
  for k in GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_NOSYSTEM GIT_CONFIG_COUNT \
           GIT_CONFIG_PARAMETERS GIT_SSH GIT_SSH_COMMAND GIT_PROXY_COMMAND GIT_ASKPASS \
           GIT_EXEC_PATH GIT_TERMINAL_PROMPT GIT_DIR HOME XDG_CONFIG_HOME; do
    echo "$k=${!k-<unset>}"
  done
  echo "--"
} >> "${STUB_GITLOG:-/dev/null}"
if [[ " $* " == *" ls-remote "* && "$*" == *"refs/tags/v[0-9]*"* && "$*" == *"https://github.com/jikig-ai/soleur.git"* ]]; then
  [[ -n "${STUB_GIT_SLEEP:-}" ]] && exec sleep "$STUB_GIT_SLEEP"
  [[ "${STUB_GIT_RC:-0}" != 0 ]] && exit "$STUB_GIT_RC"
  cat "$STUB_LSREMOTE"; exit 0
fi
exit 64
STUB
assert_fixture_dir "$STUBS"
cat > "$STUBS/curl" <<'STUB'
#!/usr/bin/env bash
echo "curl $*" >> "${STUB_CALLS:-/dev/null}"
if [[ -n "${STUB_CURLARGS:-}" ]]; then
  printf '%s\n' "$@" > "$STUB_CURLARGS"
  echo "$PWD" > "$STUB_CURLARGS.cwd"
fi
[[ "$*" == *"/compare/"* ]] || exit 64
[[ "${STUB_CURL_RC:-0}" != 0 ]] && exit "$STUB_CURL_RC"
cat "$STUB_COMPARE_BODY"; exit 0
STUB
chmod +x "$STUBS/git" "$STUBS/curl"

# Restricted PATH directories: the tools the resolver needs, and only the named extras.
# "stub:git" links the recording stub; a bare name links the system tool.
BASE_TOOLS="bash sh sed grep awk sort date stat mktemp mv rm chmod mkdir basename tail head tr cat dirname cut sleep touch ln env pkill kill"
mkbin() { # name tool... -> printed directory
  local d="$SANDBOX/bin.$1" t p; shift
  assert_fixture_dir "$d"
  rm -rf "$d"; mkdir -p "$d"
  for t in $BASE_TOOLS "$@"; do
    case "$t" in
      stub:*) ln -s "$STUBS/${t#stub:}" "$d/${t#stub:}" ;;
      *) p="$(command -v "$t" 2>/dev/null)" && [[ "$p" == /* ]] && ln -sf "$p" "$d/$t" ;;
    esac
  done
  printf '%s' "$d"
}
P_NOJQ="$(mkbin nojq timeout stub:git stub:curl)"
P_JQ="$(mkbin jq timeout jq stub:git stub:curl)"
P_NOGIT="$(mkbin nogit timeout stub:curl)"
P_NOCURL="$(mkbin nocurl timeout stub:git)"
P_NOTIMEOUT="$(mkbin notimeout stub:git stub:curl)"
HAVE_JQ=0; command -v jq >/dev/null 2>&1 && HAVE_JQ=1
HAVE_TIMEOUT=0; { command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; } && HAVE_TIMEOUT=1
TIMEOUT_BIN=""; command -v timeout >/dev/null 2>&1 && TIMEOUT_BIN=timeout
[[ -n "$TIMEOUT_BIN" ]] || { command -v gtimeout >/dev/null 2>&1 && TIMEOUT_BIN=gtimeout; }

# ---- verdict helpers -----------------------------------------------------------
passes=0; fails=0; CASES=0; RUNS=0; SKIPS=0; QUIET=0; SKIP_RUN_DEFICIT=0
FAILURES=()   # append-only: the verdict reads THIS, so a redirected counter cannot hide a failure.
pass() { passes=$((passes + 1)); }
fail() {
  fails=$((fails + 1)); FAILURES+=("$1")
  (( QUIET )) || printf '  FAIL %s\n' "$1"
  return 0
}
check() { # name expected actual
  CASES=$((CASES + 1))
  if [[ "$2" == "$3" ]]; then pass; else fail "$1: expected [$2] got [$3]"; fi
}
check_has() { # name needle haystack
  CASES=$((CASES + 1))
  if [[ "$3" == *"$2"* ]]; then pass; else fail "$1: missing [$2] in [$3]"; fi
}
check_lacks() { # name needle haystack
  CASES=$((CASES + 1))
  if [[ "$3" != *"$2"* ]]; then pass; else fail "$1: unexpected [$2] in [$3]"; fi
}
skip_case() { # name reason: counted (the case count stays deterministic) and announced
  CASES=$((CASES + 1)); SKIPS=$((SKIPS + 1)); pass
  printf '  SKIP %s (%s)\n' "$1" "$2"
}

# Instrument self-test: drive BOTH verdict arms of ALL THREE helpers once and require every
# observable to move, and the right rows to be the ones that failed, before any assertion is
# trusted. Then unwind so the floor below stays exact.
_p0=$passes; _f0=$fails; _c0=$CASES; _n0=${#FAILURES[@]}; QUIET=1
check st-eq a a; check st-ne a b
check_has st-has-yes b abc; check_has st-has-no x abc
check_lacks st-lacks-yes x abc; check_lacks st-lacks-no b abc
QUIET=0
if (( passes != _p0 + 3 || fails != _f0 + 3 || CASES != _c0 + 6 || ${#FAILURES[@]} != _n0 + 3 )) \
   || [[ "${FAILURES[$_n0]:-}" != st-ne:* || "${FAILURES[$((_n0 + 1))]:-}" != st-has-no:* \
         || "${FAILURES[$((_n0 + 2))]:-}" != st-lacks-no:* ]]; then
  echo "FATAL: instrument self-test failed -- a verdict helper does not take both arms or does not move its counters" >&2
  exit 1
fi
passes=$_p0; fails=$_f0; CASES=$_c0; FAILURES=()

# ---- harness -------------------------------------------------------------------
mkroot() { # relpath manifest-json -> prints root path
  local r="$ROOTS/$1"
  assert_fixture_dir "$r"
  mkdir -p "$r/.claude-plugin"
  printf '%s\n' "$2" > "$r/.claude-plugin/plugin.json"
  printf '%s' "$r"
}

reset_logs() { : > "$CALLS"; : > "$GITLOG"; : > "$CURLARGS"; rm -f "$CURLARGS.cwd"; }
new_env() { # fresh cache dir + logs per scenario
  XDG="$(mkd "xdg.$1")"; reset_logs
}

LSR="$SANDBOX/lsremote"; CMP="$SANDBOX/compare.json"; EMPTYF="$SANDBOX/empty"; : > "$EMPTYF"
ENVS=()   # extra NAME=value pairs for the NEXT run only

# run <root|-> <cache-dir|-> args... ; sets OUT and RC.
#   `-` as root leaves CLAUDE_PLUGIN_ROOT unset; `-` as cache-dir leaves XDG_CACHE_HOME unset.
#   Per-call knobs (set as prefix assignments): X_CWD X_PATH X_SUT X_HOME X_TIMEOUT LSR STUB_*.
#   ENVS=(A=b ...) is consumed by the next run.
run() {
  local root="$1" xdg="$2"; shift 2
  local -a ex=() tm=() e=(env -u CLAUDE_PLUGIN_ROOT -u XDG_CACHE_HOME)
  # X_TIMEOUT=<s> bounds ONE run so a regression that blocks (a read on a FIFO, a scan of a
  # multi-GiB file) turns that row red instead of hanging the whole suite.
  if [[ -n "${X_TIMEOUT:-}" && -n "$TIMEOUT_BIN" ]]; then tm=("$TIMEOUT_BIN" "$X_TIMEOUT"); fi
  if (( ${#ENVS[@]} )); then ex=("${ENVS[@]}"); fi
  ENVS=()
  [[ "$root" != - ]] && e+=("CLAUDE_PLUGIN_ROOT=$root")
  [[ "$xdg" != - ]] && e+=("XDG_CACHE_HOME=$xdg")
  RUNS=$((RUNS + 1))
  OUT="$(cd "${X_CWD:-$SANDBOX/cwd}" && "${e[@]}" PATH="${X_PATH:-$STUBS:$PATH}" HOME="${X_HOME-$SANDBOX/home}" \
    STUB_CALLS="$CALLS" STUB_GITLOG="$GITLOG" STUB_CURLARGS="$CURLARGS" \
    STUB_LSREMOTE="$LSR" STUB_COMPARE_BODY="$CMP" \
    STUB_GIT_RC="${STUB_GIT_RC:-0}" STUB_CURL_RC="${STUB_CURL_RC:-0}" STUB_GIT_SLEEP="${STUB_GIT_SLEEP:-}" \
    ${ex[@]+"${ex[@]}"} ${tm[@]+"${tm[@]}"} "$REAL_BASH" "${X_SUT:-$SUT}" "$@" 2>&1)"
  RC=$?
}
val() { printf '%s\n' "$OUT" | sed -n "s/^$1=//p" | head -1; }
nval() { printf '%s\n' "$OUT" | grep -c "^$1=" || true; }   # how many lines carry this key
ncalls() { grep -c "^$1 " "$CALLS" 2>/dev/null || true; }
glog() { sed -n "s/^$1=//p" "$GITLOG" | head -1; }          # first git call's recorded value
cargs() { tr '\n' ' ' < "$CURLARGS"; }
cafter() { awk -v k="$1" 'f{print; exit} $0==k{f=1}' "$CURLARGS"; }  # the argument after flag $1
dirlist() { # names inside a directory (dotfiles included), space-terminated, glob-sorted
  local f
  for f in "$1"/* "$1"/.[!.]*; do [[ -e "$f" || -L "$f" ]] && printf '%s ' "${f##*/}"; done
  return 0
}
near() { # got want tolerance -> 1|0
  [[ "$1" =~ ^[0-9]+$ ]] || { echo 0; return 0; }
  local d=$(( $1 - $2 )); (( d < 0 )) && d=$(( -d ))
  (( d <= $3 )) && echo 1 || echo 0
}
settime() { # file epoch
  local ts; ts="$(date -d "@$2" +%Y%m%d%H%M.%S 2>/dev/null || date -r "$2" +%Y%m%d%H%M.%S)"
  touch -t "$ts" "$1"
}
modeof() { stat -c %a "$1" 2>/dev/null || stat -f %Lp "$1"; }

cfile() { printf '%s/soleur/latest-release.%s' "$XDG" "$1"; }
cval() { sed -n "s/^$2=//p" "$(cfile "$1")" | head -1; }
put_cache() { # id tag sha fetched relation reason [complete(1|0)] [relation_for]
  local f; f="$(cfile "$1")"; assert_fixture_dir "$XDG"; assert_fixture_dir "$f"; mkdir -p "$XDG/soleur"
  { printf 'tag=%s\nsha=%s\nfetched=%s\nrelation=%s\nrelation_for=%s\nreason=%s\n' \
      "$2" "$3" "$4" "$5" "${8:-$1}" "$6"
    [[ "${7:-1}" == 1 ]] && printf 'complete=1\n'; } > "$f"
}

SHA1=1111111111111111111111111111111111111111
SHA2=2222222222222222222222222222222222222222
SHA3=3333333333333333333333333333333333333333
# Real `git ls-remote --tags` shape: tab-separated, annotated tags carry a peeled ^{} line.
# The tags ABOVE the true max (v3.335.10) are the ones a loosened filter would wrongly pick:
# prereleases with a short suffix (so awk's numeric prefix parse reads them as X.Y.Z), the
# other tag families, and components wider than four digits. The max sits in the middle.
printf '%s\t%s\n' \
  "$SHA1" "refs/tags/vinngest-v9.9.9" "$SHA1" "refs/tags/web-v9.9.9" \
  "$SHA1" "refs/tags/telegram-v9.9.9" "$SHA1" "refs/tags/zot-image-v9.9.9" \
  "$SHA1" "refs/tags/v99.0.0-x" "$SHA1" "refs/tags/v99.0.0-rc1" \
  "$SHA1" "refs/tags/v3.335.11-a" "$SHA1" "refs/tags/v3.335.11-rc1" \
  "$SHA1" "refs/tags/v12345.0.0" "$SHA1" "refs/tags/v1.12345.0" "$SHA1" "refs/tags/v1.0.12345" \
  "$SHA1" "refs/tags/v3.335.8" "$SHA1" "refs/tags/v3.9.0" "$SHA1" "refs/tags/v3.335.9" \
  "$SHA2" "refs/tags/v3.335.10" "$SHA3" "refs/tags/v3.335.10^{}" \
  "$SHA1" "refs/tags/v2.99.99" > "$LSR"

# Compare-API bodies. The real response is PRETTY-PRINTED, multi-line, with a space after the
# colon, and the top-level "status" comes BEFORE a files[] whose entries carry their own
# "status". A parser written against compact JSON passes the compact rows and silently never
# warns on a real install.
body_pretty() { # top-level-status file-entry-status
  cat <<EOF
{
  "url": "https://api.github.com/repos/jikig-ai/soleur/compare/b78d30e919ff...v3.335.10",
  "html_url": "https://github.com/jikig-ai/soleur/compare/b78d30e919ff...v3.335.10",
  "base_commit": {
    "sha": "b78d30e919ff0000000000000000000000000000",
    "commit": { "message": "base" }
  },
  "status": "$1",
  "ahead_by": 3,
  "behind_by": 0,
  "total_commits": 3,
  "commits": [],
  "files": [
    {
      "sha": "abc123",
      "filename": "README.md",
      "status": "$2",
      "additions": 1
    }
  ]
}
EOF
}
printf '{"status":"ahead","ahead_by":3,"files":[{"status":"modified"}]}\n' > "$CMP"

# ---- stubs witness what they claim to ------------------------------------------
STUB_CALLS=/dev/null STUB_GITLOG=/dev/null "$STUBS/git" status >/dev/null 2>&1; _rc=$?
check stub-git-rejects-unexpected-argv 64 "$_rc"
STUB_CALLS=/dev/null "$STUBS/curl" -q https://example.test/x >/dev/null 2>&1; _rc=$?
check stub-curl-rejects-non-compare-url 64 "$_rc"
: > "$GITLOG"
GIT_SSH_COMMAND=probe STUB_CALLS=/dev/null STUB_GITLOG="$GITLOG" STUB_LSREMOTE="$EMPTYF" \
  "$STUBS/git" ls-remote --tags https://github.com/jikig-ai/soleur.git 'refs/tags/v[0-9]*' >/dev/null 2>&1
check_has stub-git-records-set-env "GIT_SSH_COMMAND=probe" "$(cat "$GITLOG")"
check_has stub-git-records-unset-env "GIT_DIR=<unset>" "$(cat "$GITLOG")"

# ---- installed: identity precedence -----------------------------------------------
R_STAMPED="$(mkroot 3.335.8 '{"name":"soleur","version":"3.335.8"}')"
R_KEYLESS="$(mkroot b78d30e919ff '{"name":"soleur"}')"
R_SUFFIX="$(mkroot b78d30e919ff-1a2b3c4d '{"name":"soleur"}')"
R_NEITHER="$(mkroot plain-dir '{"name":"soleur"}')"
R_GARBAGE="$(mkroot abcdef012345 '{"name":"soleur","version":"latest"}')"
R_HEXSEM="$(mkroot c0ffee123456 '{"name":"soleur","version":"2.0.0"}')"
R_PLAINSEM="$(mkroot plain-with-version '{"name":"soleur","version":"2.1.0"}')"
R_UPPER="$(mkroot B78D30E919FF '{"name":"soleur"}')"
R_HEX11="$(mkroot b78d30e919f '{"name":"soleur"}')"
R_HEX13="$(mkroot b78d30e919ff1 '{"name":"soleur"}')"

new_env inst
run "$R_STAMPED" "$XDG" --installed
check inst-stamped-source manifest "$(val source)"; check inst-stamped-version 3.335.8 "$(val version)"
run "$R_KEYLESS" "$XDG" --installed
check inst-keyless-source commit "$(val source)"; check inst-keyless-commit b78d30e919ff "$(val commit)"
check inst-keyless-no-version "" "$(val version)"
run "$R_SUFFIX" "$XDG" --installed
check inst-suffix-commit b78d30e919ff "$(val commit)"
run "$R_NEITHER" "$XDG" --installed
check inst-neither-source unknown "$(val source)"
run "$R_GARBAGE" "$XDG" --installed
check inst-garbage-ignored commit "$(val source)"; check inst-garbage-no-version "" "$(val version)"
run "$R_STAMPED" "$XDG" --bogus-flag
check bogus-flag-rc 0 "$RC"
run "$R_STAMPED" "$XDG"
check_has no-mode-prints-usage "usage:" "$OUT"; check no-mode-rc 0 "$RC"
# precedence: a semver manifest outranks a commit-shaped directory name, in both directions
run "$R_HEXSEM" "$XDG" --installed
check prec-hexdir-with-semver-manifest-source manifest "$(val source)"
check prec-hexdir-with-semver-manifest-version 2.0.0 "$(val version)"
check prec-hexdir-with-semver-manifest-no-commit "" "$(val commit)"
run "$R_PLAINSEM" "$XDG" --installed
check prec-plain-dir-with-semver-manifest manifest/2.1.0 "$(val source)/$(val version)"
run "$R_UPPER" "$XDG" --installed;  check prec-uppercase-hex-dir-is-not-a-commit unknown "$(val source)"
run "$R_HEX11" "$XDG" --installed;  check prec-11-hex-dir-is-not-a-commit unknown "$(val source)"
run "$R_HEX13" "$XDG" --installed;  check prec-13-hex-dir-is-not-a-commit unknown "$(val source)"

# ---- installed: root fallback (CLAUDE_PLUGIN_ROOT unset or empty) -------------------
# The Bash tool does not always export CLAUDE_PLUGIN_ROOT, so the resolver derives the root
# from its own location (one level above scripts/).
mkcopy() { # relpath -> prints the copied script path; the root is $ROOTS/<relpath>
  local d="$ROOTS/$1/scripts"
  assert_fixture_dir "$d"
  mkdir -p "$d"; cp "$SUT" "$d/plugin-version.sh"
  printf '%s' "$d/plugin-version.sh"
}
new_env fb
S_HEX="$(mkcopy fb/b78d30e919ff)"
X_SUT="$S_HEX" run - "$XDG" --installed
check fb-unset-hexdir-source commit "$(val source)"; check fb-unset-hexdir-commit b78d30e919ff "$(val commit)"
X_SUT="$S_HEX" run "" "$XDG" --installed
check fb-empty-env-is-unset commit "$(val source)"
S_PLAIN="$(mkcopy fb/plain)"
X_SUT="$S_PLAIN" run - "$XDG" --installed
check fb-unset-plain-dir-source unknown "$(val source)"
assert_fixture_dir "$ROOTS"
S_HEXSEM="$(mkcopy fb/c0ffee123456)"; mkdir -p "$ROOTS/fb/c0ffee123456/.claude-plugin"
printf '{"name":"soleur","version":"2.0.0"}\n' > "$ROOTS/fb/c0ffee123456/.claude-plugin/plugin.json"
X_SUT="$S_HEXSEM" run - "$XDG" --installed
check fb-manifest-beats-hexdir manifest/2.0.0 "$(val source)/$(val version)"
# env wins over location, and a relative invocation still resolves absolutely
X_SUT="$S_HEX" run "$R_STAMPED" "$XDG" --installed
check fb-env-beats-script-location manifest/3.335.8 "$(val source)/$(val version)"
X_CWD="$ROOTS/fb/b78d30e919ff/scripts" X_SUT=./plugin-version.sh run - "$XDG" --installed
check fb-relative-invocation commit/b78d30e919ff "$(val source)/$(val commit)"
# running the script from a keyless plugins/soleur that is not a commit dir and has no .git
# above it. This was the REAL repo until source=checkout existed: a checkout of this repository
# (a worktree, CI's detached clone) now resolves as a checkout, so the row runs a sandbox copy.
S_REPOCOPY="$(mkcopy fb/repocopy/plugins/soleur)"
mkdir -p "$ROOTS/fb/repocopy/plugins/soleur/.claude-plugin"
printf '{"name":"soleur"}\n' > "$ROOTS/fb/repocopy/plugins/soleur/.claude-plugin/plugin.json"
X_SUT="$S_REPOCOPY" run - "$XDG" --installed
check fb-repo-run-source unknown "$(val source)"; check fb-repo-run-rc 0 "$RC"
# none: only when the (derived or given) root is not a directory
run "$SANDBOX/does-not-exist" "$XDG" --installed
check none-missing-root-source none "$(val source)"; check none-missing-root-rc 0 "$RC"
: > "$SANDBOX/a-file"
run "$SANDBOX/a-file" "$XDG" --installed
check none-file-root-source none "$(val source)"
run "$SANDBOX/does-not-exist" "$XDG" --compare --refresh
check none-compare-relation unknown/installed-unknown "$(val relation)/$(val reason)"

# ---- installed: marketplace= ----------------------------------------------------------
mp_run() { # relpath -> runs --installed against $ROOTS/<relpath>
  run "$ROOTS/$1" "$XDG" --installed
}
mkroot "mp1/plugins/cache/soleur-marketplace/soleur/b78d30e919ff" '{"name":"soleur"}' >/dev/null
mp_run "mp1/plugins/cache/soleur-marketplace/soleur/b78d30e919ff"
check mp-derived soleur-marketplace "$(val marketplace)"; check mp-derived-source commit "$(val source)"
mkroot "mp2/plugins/cache/soleur/soleur/b78d30e919ff" '{"name":"soleur"}' >/dev/null
mp_run "mp2/plugins/cache/soleur/soleur/b78d30e919ff"
check mp-legacy-soleur-at-soleur soleur "$(val marketplace)"
run "$ROOTS/mp1/plugins/cache/soleur-marketplace/soleur/b78d30e919ff/" "$XDG" --installed
check mp-trailing-slash soleur-marketplace "$(val marketplace)"
run "$R_KEYLESS" "$XDG" --installed
check mp-absent-outside-cache 0 "$(nval marketplace)"
mkroot "mp3/plugins/cache/mk/other/b78d30e919ff" '{"name":"soleur"}' >/dev/null
mp_run "mp3/plugins/cache/mk/other/b78d30e919ff"
check mp-absent-when-parent-not-soleur 0 "$(nval marketplace)"
mkroot "mp4/plugins/notcache/mk/soleur/b78d30e919ff" '{"name":"soleur"}' >/dev/null
mp_run "mp4/plugins/notcache/mk/soleur/b78d30e919ff"
check mp-absent-when-grandparent-not-cache 0 "$(nval marketplace)"
for bad in 'a b' 'a;b' 'a$b' 'a`b' "a'b" 'a|b' $'a\nmarketplace=evil'; do
  rel="mph/plugins/cache/$bad/soleur/b78d30e919ff"
  mkroot "$rel" '{"name":"soleur"}' >/dev/null
  mp_run "$rel"
  check "mp-hostile-rejected [${bad//$'\n'/\\n}]" 0 "$(nval marketplace)"
done
mp_run "mp1/plugins/cache/soleur-marketplace/soleur/b78d30e919ff"
run "$ROOTS/mp1/plugins/cache/soleur-marketplace/soleur/b78d30e919ff" "$XDG" --compare --refresh
check mp-also-in-compare soleur-marketplace "$(val marketplace)"

# ---- latest: tag filter and ordering ------------------------------------------------
new_env tags
run "$R_KEYLESS" "$XDG" --latest --refresh
check tags-latest v3.335.10 "$(val latest)"
check tags-latest-commit-peeled "$SHA3" "$(val latest_commit)"
check tags-status ok "$(val latest_status)"
check_lacks tags-no-web-tag web-v "$OUT"; check_lacks tags-no-other-families-above-max v9.9.9 "$OUT"
check_lacks tags-no-prerelease -rc1 "$OUT"; check_lacks tags-no-short-prerelease v99.0.0 "$OUT"
check tags-ls-remote-called 1 "$(ncalls git)"
check tags-fixed-url 1 "$(grep -c 'https://github.com/jikig-ai/soleur.git' "$CALLS")"
check_has tags-glob-is-v-digit "refs/tags/v[0-9]*" "$(glog argv)"
# numeric, not lexical or length-based
printf '%s\t%s\n' "$SHA1" refs/tags/v9.9.9 "$SHA2" refs/tags/v10.0.0 "$SHA1" refs/tags/v2.20.0 "$SHA1" refs/tags/v2.3.0 > "$SANDBOX/ls.numeric"
new_env tags-num; LSR="$SANDBOX/ls.numeric" run "$R_KEYLESS" "$XDG" --latest --refresh
check tags-numeric-v10-beats-v9 v10.0.0 "$(val latest)"
printf '%s\t%s\n' "$SHA1" refs/tags/v1.0.10000 "$SHA2" refs/tags/v1.0.9999 > "$SANDBOX/ls.width"
new_env tags-width; LSR="$SANDBOX/ls.width" run "$R_KEYLESS" "$XDG" --latest --refresh
check tags-four-digit-component-kept v1.0.9999 "$(val latest)"
# a lightweight max tag has no ^{} line: latest_commit is the tag's own sha
printf '%s\t%s\n' "$SHA1" refs/tags/v3.335.9 "$SHA2" refs/tags/v3.335.10 > "$SANDBOX/ls.light"
new_env tags-light; LSR="$SANDBOX/ls.light" run "$R_KEYLESS" "$XDG" --latest --refresh
check tags-lightweight-latest v3.335.10 "$(val latest)"
check tags-lightweight-commit-is-own-sha "$SHA2" "$(val latest_commit)"
# the peeled line may come first
printf '%s\t%s\n' "$SHA3" 'refs/tags/v3.335.10^{}' "$SHA2" refs/tags/v3.335.10 > "$SANDBOX/ls.peeledfirst"
new_env tags-peel1; LSR="$SANDBOX/ls.peeledfirst" run "$R_KEYLESS" "$XDG" --latest --refresh
check tags-peeled-line-first "$SHA3" "$(val latest_commit)"
# nothing usable -> no-tags and no latest
printf 'this is not a ref line\n\n\tgarbage\n' > "$SANDBOX/ls.garbage"
printf '%s\t%s\n' "$SHA1" refs/tags/web-v1.0.0 "$SHA1" refs/tags/v1.0.0-rc1 "$SHA1" refs/tags/v12345.0.0 > "$SANDBOX/ls.nonematch"
for nm in empty garbage nonematch; do
  case "$nm" in empty) f="$EMPTYF" ;; *) f="$SANDBOX/ls.$nm" ;; esac
  new_env "notags-$nm"; LSR="$f" run "$R_KEYLESS" "$XDG" --latest --refresh
  check "notags-$nm-status" no-tags "$(val latest_status)"; check "notags-$nm-no-latest" 0 "$(nval latest)"
  check "notags-$nm-rc" 0 "$RC"
done
# latest does not depend on the installed manifest key
new_env same-a; run "$R_STAMPED" "$XDG" --latest --refresh; A="$(printf '%s\n' "$OUT" | grep -E '^(latest|latest_commit|latest_status)=')"
new_env same-b; run "$R_KEYLESS" "$XDG" --latest --refresh; B="$(printf '%s\n' "$OUT" | grep -E '^(latest|latest_commit|latest_status)=')"
check latest-independent-of-manifest-key "$A" "$B"

# ---- relation: manifest installs (semver) -------------------------------------------
new_env rel-a; run "$R_STAMPED" "$XDG" --compare --refresh
check rel-manifest-older older "$(val relation)"
check rel-manifest-no-compare-call 0 "$(ncalls curl)"
R_NEW="$(mkroot 3.335.10 '{"name":"soleur","version":"3.335.10"}')"
new_env rel-b; run "$R_NEW" "$XDG" --compare --refresh
check rel-manifest-current current "$(val relation)"
R_AHEAD="$(mkroot 4.0.0 '{"name":"soleur","version":"4.0.0"}')"
new_env rel-c; run "$R_AHEAD" "$XDG" --compare --refresh
check rel-manifest-downgrade-is-current current "$(val relation)"
# a manifest install needs no curl, so a missing curl must not degrade it
new_env rel-d; X_PATH="$P_NOCURL" run "$R_STAMPED" "$XDG" --compare --refresh
check rel-manifest-without-curl older "$(val relation)"

# ---- relation: commit installs (compare API) ----------------------------------------
cmp_case() { # name body curl-rc want-relation want-reason
  new_env "cmp-$1"
  printf '%s' "$2" > "$CMP"
  STUB_CURL_RC="$3" run "$R_KEYLESS" "$XDG" --compare --refresh
  check "cmp-$1-relation" "$4" "$(val relation)"
  check "cmp-$1-reason" "$5" "$(val reason)"
  check "cmp-$1-one-call" 1 "$(ncalls curl)"
  if [[ "$4" == unknown ]]; then check_lacks "cmp-$1-never-current" "relation=current" "$OUT"; fi
}
cmp_case compact-ahead '{"status":"ahead","ahead_by":3,"files":[{"status":"modified"}]}' 0 older ""
cmp_case ahead      "$(body_pretty ahead modified)"      0 older ""
cmp_case behind     "$(body_pretty behind added)"        0 current ""
cmp_case identical  "$(body_pretty identical modified)"  0 current ""
cmp_case diverged   "$(body_pretty diverged removed)"    0 unknown diverged
cmp_case failed     '{}'                                 22 unknown compare-failed
cmp_case garbage    'not json at all'                    0 unknown compare-unparseable
cmp_case nostatus   $'{\n  "url": "x",\n  "ahead_by": 3,\n  "files": [ { "filename": "a" } ]\n}' 0 unknown compare-unparseable
cmp_case oddstatus  "$(body_pretty weird modified)"      0 unknown compare-unparseable
cmp_case htmlbody   '<html><body>Rate limited</body></html>' 0 unknown compare-unparseable
# the request shape (the last compare case above leaves the logs; re-run one for them)
new_env cmp-shape; printf '%s' "$(body_pretty ahead modified)" > "$CMP"
run "$R_KEYLESS" "$XDG" --compare --refresh
check cmp-url-has-sha-and-tag 1 "$(grep -c 'compare/b78d30e919ff\.\.\.v3.335.10?per_page=1&page=2000' "$CALLS")"
check curl-first-arg-is-q -q "$(head -1 "$CURLARGS")"
check_has curl-https-only "--proto =https" "$(cargs)"
check_has curl-compressed "--compressed" "$(cargs)"
check curl-default-timeout 8 "$(cafter -m)"
check_has curl-url-tail "?per_page=1&page=2000" "$(tail -1 "$CURLARGS")"
check curl-url-ends-with-page "?per_page=1&page=2000" "$(tail -1 "$CURLARGS" | sed 's/.*\(?per_page=1&page=2000\)$/\1/')"
check curl-runs-from-root-cwd / "$(cat "$CURLARGS.cwd")"
# the installed commit is the tag commit: nothing to compare, and no curl call at all
R_ATTAG="$(mkroot 333333333333 '{"name":"soleur"}')"
new_env attag; run "$R_ATTAG" "$XDG" --compare --refresh
check attag-relation current "$(val relation)"; check attag-no-curl 0 "$(ncalls curl)"
check attag-latest-commit "$SHA3" "$(val latest_commit)"
# the annotated tag OBJECT sha is not the commit: no shortcut, the compare runs
R_ATOBJ="$(mkroot 222222222222 '{"name":"soleur"}')"
new_env atobj; run "$R_ATOBJ" "$XDG" --compare --refresh
check atobj-compares 1 "$(ncalls curl)"
# a lightweight max tag's own sha is the commit
R_ATLIGHT="$(mkroot 222222222222-1a2b3c4d '{"name":"soleur"}')"
new_env atlight; LSR="$SANDBOX/ls.light" run "$R_ATLIGHT" "$XDG" --compare --refresh
check atlight-relation current "$(val relation)"; check atlight-no-curl 0 "$(ncalls curl)"
# an unrecognised install has nothing to compare and nothing to cache
new_env unk; run "$R_NEITHER" "$XDG" --compare --refresh
check unk-relation unknown/installed-unknown "$(val relation)/$(val reason)"
check unk-no-curl 0 "$(ncalls curl)"; check unk-latest v3.335.10 "$(val latest)"
check unk-nothing-persisted "" "$(dirlist "$XDG")"
new_env unk2; run "$R_NEITHER" "$XDG" --cached-latest
check unk-cached-latest-missing missing "$(val cache)"
# no git / no curl: said so, never "current"
new_env nogit; X_PATH="$P_NOGIT" run "$R_KEYLESS" "$XDG" --compare --refresh
check nogit-status no-git "$(val latest_status)"; check_lacks nogit-never-current "relation=current" "$OUT"
check nogit-no-curl-call 0 "$(ncalls curl)"; check nogit-rc 0 "$RC"
new_env nocurl; X_PATH="$P_NOCURL" run "$R_KEYLESS" "$XDG" --compare --refresh
check nocurl-relation unknown/no-curl "$(val relation)/$(val reason)"
check nocurl-latest v3.335.10 "$(val latest)"; check_lacks nocurl-never-current "relation=current" "$OUT"

# ---- a failed compare is retried within the hour, not silenced for a day -----------------
# The cache stamp is backdated by TTL - FAIL_FRESH so the entry is fresh for ~1 h only.
chk_stamp() { # name id want-offset-from-now
  local now; now="$(date +%s)"
  check "$1" 1 "$(near "$(cval "$2" fetched)" "$(( now + $3 ))" 15)"
}
new_env ff-failed; STUB_CURL_RC=22 run "$R_KEYLESS" "$XDG" --compare --refresh
chk_stamp ff-compare-failed-backdated b78d30e919ff -82800
new_env ff-garbage; printf 'nope' > "$CMP"; run "$R_KEYLESS" "$XDG" --compare --refresh
chk_stamp ff-compare-unparseable-backdated b78d30e919ff -82800
new_env ff-nocurl; X_PATH="$P_NOCURL" run "$R_KEYLESS" "$XDG" --compare --refresh
chk_stamp ff-no-curl-backdated b78d30e919ff -82800
new_env ff-diverged; printf '%s' "$(body_pretty diverged modified)" > "$CMP"; run "$R_KEYLESS" "$XDG" --compare --refresh
chk_stamp ff-diverged-keeps-full-ttl b78d30e919ff 0
new_env ff-ok; printf '%s' "$(body_pretty ahead modified)" > "$CMP"; run "$R_KEYLESS" "$XDG" --compare --refresh
chk_stamp ff-success-keeps-full-ttl b78d30e919ff 0
new_env ff-manifest; run "$R_STAMPED" "$XDG" --compare --refresh
chk_stamp ff-manifest-keeps-full-ttl 3.335.8 0
# 59 minutes after a failed compare the entry is still fresh; 61 minutes after, stale
NOW="$(date +%s)"
new_env ff-59; put_cache b78d30e919ff v3.335.10 "$SHA3" "$(( NOW - 3540 - 82800 ))" unknown compare-failed
run "$R_KEYLESS" "$XDG" --cached-latest; check ff-59min-still-fresh fresh "$(val cache)"
new_env ff-61; put_cache b78d30e919ff v3.335.10 "$SHA3" "$(( NOW - 3660 - 82800 ))" unknown compare-failed
run "$R_KEYLESS" "$XDG" --cached-latest; check ff-61min-is-stale stale "$(val cache)"
# the recorded failure reason is what a reader sees from a fresh cache
new_env ff-reason; STUB_CURL_RC=22 run "$R_KEYLESS" "$XDG" --compare --refresh
check ff-cached-reason compare-failed "$(cval b78d30e919ff reason)"
run "$R_KEYLESS" "$XDG" --cached-latest
check ff-cached-readback unknown/compare-failed "$(val relation)/$(val reason)"

# ---- a cached relation is only as good as the cache -----------------------------------
NOW="$(date +%s)"
for rel in current older; do
  new_env "age-$rel"
  put_cache b78d30e919ff v3.0.0 "$SHA1" "$NOW" "$rel" ""
  run "$R_KEYLESS" "$XDG" --cached-latest
  check "age-fresh-$rel-kept" "$rel" "$(val relation)"; check "age-fresh-$rel-state" fresh "$(val cache)"
  new_env "age-stale-$rel"
  put_cache b78d30e919ff v3.0.0 "$SHA1" "$(( NOW - 200000 ))" "$rel" ""
  run "$R_KEYLESS" "$XDG" --cached-latest
  check "age-stale-$rel-state" stale "$(val cache)"
  if [[ "$rel" == current ]]; then
    check age-stale-current-becomes-unknown unknown/stale-cache "$(val relation)/$(val reason)"
  else
    check age-stale-older-stays-older older/ "$(val relation)/$(val reason)"
  fi
done
# a failed fetch degrades a cached `current` and keeps a cached `older`
P_NONE="$SANDBOX/ls.none"; : > "$P_NONE"
for cls in offline timeout no-git no-tags; do
  for rel in current older; do
    new_env "fail-$cls-$rel"
    put_cache b78d30e919ff v3.0.0 "$SHA1" "$(date +%s)" "$rel" ""
    case "$cls" in
      offline) STUB_GIT_RC=128 run "$R_KEYLESS" "$XDG" --compare --refresh ;;
      timeout) STUB_GIT_RC=124 run "$R_KEYLESS" "$XDG" --compare --refresh ;;
      no-git)  X_PATH="$P_NOGIT" run "$R_KEYLESS" "$XDG" --compare --refresh ;;
      no-tags) LSR="$EMPTYF" run "$R_KEYLESS" "$XDG" --compare --refresh ;;
    esac
    check "fail-$cls-$rel-status" "$cls" "$(val latest_status)"
    if [[ "$rel" == current ]]; then
      check "fail-$cls-current-degrades" unknown/stale-cache "$(val relation)/$(val reason)"
    else
      check "fail-$cls-older-kept" older/ "$(val relation)/$(val reason)"
    fi
    check "fail-$cls-$rel-no-compare" 0 "$(ncalls curl)"
  done
done
# a failed fetch does not rewrite the cache
new_env fail-keeps-file; put_cache b78d30e919ff v3.0.0 "$SHA1" "$(( NOW - 200000 ))" older ""
_before="$(cat "$(cfile b78d30e919ff)")"
STUB_GIT_RC=128 run "$R_KEYLESS" "$XDG" --latest
check fail-leaves-cache-untouched "$_before" "$(cat "$(cfile b78d30e919ff)")"
# a stale cache is refetched and replaced
new_env stale-refetch; put_cache 3.335.8 v3.0.0 "$SHA1" "$(( NOW - 200000 ))" older ""
run "$R_STAMPED" "$XDG" --latest
check stale-refetches 1 "$(ncalls git)"; check stale-new-tag v3.335.10 "$(val latest)"
check stale-cache-replaced v3.335.10 "$(cval 3.335.8 tag)"

# ---- cache: per install, private, validated -----------------------------------------
new_env c1; run "$R_STAMPED" "$XDG" --latest --refresh
check cache-file-is-per-install "latest-release.3.335.8 " "$(dirlist "$XDG/soleur")"
check cache-dir-printed "$XDG/soleur" "$(val cache_dir)"
check cache-written-0600 600 "$(modeof "$(cfile 3.335.8)")"
check cache-dir-0700 700 "$(modeof "$XDG/soleur")"
check cache-file-ends-with-complete-marker complete=1 "$(tail -1 "$(cfile 3.335.8)")"
check cache-file-records-install 3.335.8 "$(cval 3.335.8 relation_for)"
reset_logs; run "$R_STAMPED" "$XDG" --latest
check cache-fresh-no-network 0 "$(ncalls git)"; check cache-fresh-state fresh "$(val cache)"
run "$R_STAMPED" "$XDG" --cached-latest
check cached-latest-no-network 0 "$(ncalls git)"; check cached-latest-value v3.335.10 "$(val latest)"
check cached-latest-cache-dir "$XDG/soleur" "$(val cache_dir)"
run "$R_STAMPED" "$XDG" --latest --refresh
check cache-refresh-forces-call 1 "$(ncalls git)"
# a second install gets its own file: neither clobbers the other, and neither reads the other
run "$R_KEYLESS" "$XDG" --cached-latest
check cache-other-install-sees-nothing missing "$(val cache)"; check cache-other-install-no-latest 0 "$(nval latest)"
_stamped_before="$(cat "$(cfile 3.335.8)")"
run "$R_KEYLESS" "$XDG" --latest --refresh
check cache-two-installs-two-files "latest-release.3.335.8 latest-release.b78d30e919ff " "$(dirlist "$XDG/soleur" | tr ' ' '\n' | sort | tr '\n' ' ')"
check cache-other-install-untouched "$_stamped_before" "$(cat "$(cfile 3.335.8)")"
# a file under this install's name that was written for another install is not trusted
new_env c-foreign; put_cache b78d30e919ff v3.335.10 "$SHA3" "$(date +%s)" current "" 1 3.335.8
run "$R_KEYLESS" "$XDG" --cached-latest
check cache-relation-for-other-install corrupt "$(val cache)"; check cache-foreign-no-latest 0 "$(nval latest)"
# an unrecognised install neither reads, writes nor clobbers anything
new_env c-unk; put_cache b78d30e919ff v3.0.0 "$SHA1" "$(( NOW - 200000 ))" older ""
_keep="$(cat "$(cfile b78d30e919ff)")"
run "$R_NEITHER" "$XDG" --latest --refresh
check cache-unknown-install-answers ok "$(val latest_status)"
check cache-unknown-install-leaves-other-file "$_keep" "$(cat "$(cfile b78d30e919ff)")"
check cache-unknown-install-adds-no-file "latest-release.b78d30e919ff " "$(dirlist "$XDG/soleur")"
new_env c-none; run "$SANDBOX/does-not-exist" "$XDG" --latest --refresh
check cache-none-install-persists-nothing "" "$(dirlist "$XDG")"
check cache-none-install-answers ok "$(val latest_status)"
# a cache dir that already exists with loose permissions is tightened to 0700
new_env c-dirmode; mkdir -p "$XDG/soleur"; chmod 755 "$XDG/soleur"
run "$R_STAMPED" "$XDG" --latest --refresh
check cache-dir-preexisting-tightened 700 "$(modeof "$XDG/soleur")"

# ---- cache location: absolute only --------------------------------------------------
PROJ="$(mkd proj.rel)"; H="$(mkd home.rel)"
X_CWD="$PROJ" X_HOME="$H" run "$R_STAMPED" relcache --latest --refresh
check relxdg-nothing-in-cwd "" "$(dirlist "$PROJ")"
check relxdg-falls-back-to-home-cache "$H/.cache/soleur" "$(val cache_dir)"
check relxdg-written-under-home "latest-release.3.335.8 " "$(dirlist "$H/.cache/soleur")"
H2="$(mkd home.rel2)"
X_CWD="$PROJ" X_HOME=relhome run "$R_STAMPED" relcache --latest --refresh
check relxdg-relhome-nothing-in-cwd "" "$(dirlist "$PROJ")"
check relxdg-relhome-no-cache-dir 0 "$(nval cache_dir)"; check relxdg-relhome-still-answers ok "$(val latest_status)"
X_CWD="$PROJ" X_HOME="" run "$R_STAMPED" - --latest --refresh
check emptyhome-nothing-in-cwd "" "$(dirlist "$PROJ")"
check emptyhome-no-cache-dir 0 "$(nval cache_dir)"; check emptyhome-rc 0 "$RC"
X_CWD="$PROJ" X_HOME="$H2" run "$R_STAMPED" - --latest --refresh
check unset-xdg-uses-home-cache "$H2/.cache/soleur" "$(val cache_dir)"
X_CWD="$PROJ" X_HOME="$H2" run "$R_STAMPED" ./relative/path --installed
check relxdg-installed-nothing-in-cwd "" "$(dirlist "$PROJ")"
# unwritable cache dir: still answers from the fetch, still exits 0
new_env ro; : > "$SANDBOX/blocker"
run "$R_STAMPED" "$SANDBOX/blocker" --latest --refresh
check unwritable-rc 0 "$RC"; check unwritable-status ok "$(val latest_status)"
# a symlinked cache dir is refused (shared XDG dirs): nothing is written through it
new_env symdir; SYMT="$(mkd symtarget)"; ln -s "$SYMT" "$XDG/soleur"
run "$R_STAMPED" "$XDG" --latest --refresh
check symdir-target-untouched "" "$(dirlist "$SYMT")"
check symdir-still-answers ok "$(val latest_status)"; check symdir-rc 0 "$RC"
# a symlink planted at the cache file is replaced, never written through
new_env symfile; mkdir -p "$XDG/soleur"; SYMF="$SANDBOX/symfile.target"; printf 'SENTINEL\n' > "$SYMF"
ln -s "$SYMF" "$(cfile 3.335.8)"
run "$R_STAMPED" "$XDG" --latest --refresh
check symfile-target-untouched SENTINEL "$(cat "$SYMF")"
check symfile-replaced-by-regular-file 1 "$([[ -f "$(cfile 3.335.8)" && ! -L "$(cfile 3.335.8)" ]] && echo 1 || echo 0)"

# ---- cache integrity -----------------------------------------------------------------
NOW="$(date +%s)"
rawc() { # name id "printf-format body"
  new_env "$1"; mkdir -p "$XDG/soleur"; printf '%b' "$3" > "$(cfile "$2")"
}
VALID="tag=v3.0.0\nsha=$SHA1\nfetched=$NOW\nrelation=older\nrelation_for=b78d30e919ff\nreason=\ncomplete=1\n"
rawc integ-valid b78d30e919ff "$VALID"
run "$R_KEYLESS" "$XDG" --cached-latest
check integ-valid-state fresh "$(val cache)"; check integ-valid-latest v3.0.0 "$(val latest)"
check integ-valid-commit "$SHA1" "$(val latest_commit)"; check integ-valid-relation older "$(val relation)"
# a truncated write loses the trailing complete=1 and must not read as a fresh "unknown"
rawc integ-trunc b78d30e919ff "tag=v3.0.0\nsha=$SHA1\nfetched=$NOW\nrelation=older\nrelation_for=b78d30e919ff\nreason=\n"
run "$R_KEYLESS" "$XDG" --cached-latest
check integ-truncated-is-corrupt corrupt "$(val cache)"; check integ-truncated-no-latest 0 "$(nval latest)"
rawc integ-complete0 b78d30e919ff "tag=v3.0.0\nsha=$SHA1\nfetched=$NOW\nrelation=older\nrelation_for=b78d30e919ff\nreason=\ncomplete=0\n"
run "$R_KEYLESS" "$XDG" --cached-latest
check integ-complete-not-1-is-corrupt corrupt "$(val cache)"
rawc integ-garbage b78d30e919ff 'garbage\n'
run "$R_KEYLESS" "$XDG" --cached-latest
check integ-garbage-state corrupt "$(val cache)"; check integ-garbage-rc 0 "$RC"
# fetched must be a plain decimal: a leading zero is octal in bash arithmetic and aborts
for badf in 08 09 0 -5 12abc "" 1234567890123 ' 5'; do
  rawc "integ-fetched" b78d30e919ff "tag=v3.0.0\nsha=$SHA1\nfetched=$badf\nrelation=older\nrelation_for=b78d30e919ff\nreason=\ncomplete=1\n"
  run "$R_KEYLESS" "$XDG" --cached-latest
  check "integ-fetched-[$badf]-corrupt" corrupt "$(val cache)"
  check "integ-fetched-[$badf]-still-prints" commit "$(val source)"
done
# ...and a wedged cache heals on the next refresh instead of aborting every run
rawc integ-wedge b78d30e919ff "tag=v3.0.0\nsha=$SHA1\nfetched=08\nrelation=older\nrelation_for=b78d30e919ff\nreason=\ncomplete=1\n"
run "$R_KEYLESS" "$XDG" --compare
check integ-wedge-refetches 1 "$(ncalls git)"; check integ-wedge-rc 0 "$RC"
check integ-wedge-healed 1 "$(near "$(cval b78d30e919ff fetched)" "$(date +%s)" 15)"
# individual fields are validated, not trusted
for badsha in ZZZZ "${SHA1:0:39}" "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" "${SHA1}0" "not-a-sha"; do
  rawc integ-sha b78d30e919ff "tag=v3.0.0\nsha=$badsha\nfetched=$NOW\nrelation=older\nrelation_for=b78d30e919ff\nreason=\ncomplete=1\n"
  run "$R_KEYLESS" "$XDG" --cached-latest
  check "integ-sha-[$badsha]-dropped" 0 "$(nval latest_commit)"; check "integ-sha-[$badsha]-tag-kept" v3.0.0 "$(val latest)"
done
rawc integ-rel-bogus b78d30e919ff "tag=v3.0.0\nsha=$SHA1\nfetched=$NOW\nrelation=bogus\nrelation_for=b78d30e919ff\nreason=\ncomplete=1\n"
run "$R_KEYLESS" "$XDG" --cached-latest
check integ-relation-outside-enum-is-unknown unknown "$(val relation)"; check_lacks integ-relation-bogus-not-echoed "relation=bogus" "$OUT"
for badr in 'Bad Reason!' '$(id)' 'x;y' "$(printf 'a%.0s' $(seq 1 41))" 'UPPER'; do
  rawc integ-reason b78d30e919ff "tag=v3.0.0\nsha=$SHA1\nfetched=$NOW\nrelation=older\nrelation_for=b78d30e919ff\nreason=$badr\ncomplete=1\n"
  run "$R_KEYLESS" "$XDG" --cached-latest
  check "integ-reason-[${badr:0:12}]-dropped" 0 "$(nval reason)"; check "integ-reason-[${badr:0:12}]-relation-kept" older "$(val relation)"
done
rawc integ-reason-ok b78d30e919ff "tag=v3.0.0\nsha=$SHA1\nfetched=$NOW\nrelation=unknown\nrelation_for=b78d30e919ff\nreason=diverged\ncomplete=1\n"
run "$R_KEYLESS" "$XDG" --cached-latest
check integ-valid-reason-kept unknown/diverged "$(val relation)/$(val reason)"
for badt in web-v1.0.0 v3.0 v3.0.0-rc1 v1.2.3.4 latest ""; do
  rawc integ-tag b78d30e919ff "tag=$badt\nsha=$SHA1\nfetched=$NOW\nrelation=older\nrelation_for=b78d30e919ff\nreason=\ncomplete=1\n"
  run "$R_KEYLESS" "$XDG" --cached-latest
  check "integ-tag-[$badt]-corrupt" corrupt "$(val cache)"
done
# time: future-dated stamp and future-dated mtime count as stale, not fresh forever
rawc integ-future b78d30e919ff "tag=v3.0.0\nsha=$SHA1\nfetched=$(( NOW + 99999 ))\nrelation=older\nrelation_for=b78d30e919ff\nreason=\ncomplete=1\n"
run "$R_KEYLESS" "$XDG" --cached-latest; check integ-future-fetched-is-stale stale "$(val cache)"
rawc integ-mtime b78d30e919ff "$VALID"; settime "$(cfile b78d30e919ff)" "$(( NOW + 259200 ))"
run "$R_KEYLESS" "$XDG" --cached-latest; check integ-future-mtime-is-stale stale "$(val cache)"
rawc integ-mtime-near b78d30e919ff "$VALID"; settime "$(cfile b78d30e919ff)" "$(( NOW + 30 ))"
run "$R_KEYLESS" "$XDG" --cached-latest; check integ-mtime-within-slack-is-fresh fresh "$(val cache)"
rawc integ-age-ok b78d30e919ff "tag=v3.0.0\nsha=$SHA1\nfetched=$(( NOW - 80000 ))\nrelation=older\nrelation_for=b78d30e919ff\nreason=\ncomplete=1\n"
run "$R_KEYLESS" "$XDG" --cached-latest; check integ-age-80000s-is-fresh fresh "$(val cache)"
rawc integ-age-old b78d30e919ff "tag=v3.0.0\nsha=$SHA1\nfetched=$(( NOW - 86500 ))\nrelation=older\nrelation_for=b78d30e919ff\nreason=\ncomplete=1\n"
run "$R_KEYLESS" "$XDG" --cached-latest; check integ-age-86500s-is-stale stale "$(val cache)"
new_env corrupt-missing
run "$R_STAMPED" "$XDG" --cached-latest; check missing-state missing "$(val cache)"; check missing-no-latest 0 "$(nval latest)"

# ---- network isolation ---------------------------------------------------------------
# The lookups run from a neutral directory with the user's and the project's git
# configuration disabled and https as the only allowed protocol.
HOSTILE="$(mkd proj.hostile)"; assert_fixture_dir "$HOSTILE"; mkdir -p "$HOSTILE/.git"
printf 'ref: refs/heads/main\n' > "$HOSTILE/.git/HEAD"
printf '[url "http://127.0.0.1:1/"]\n\tinsteadOf = https://github.com/\n[core]\n\tsshCommand = evil\n[http]\n\textraHeader = Authorization: evil\n' > "$HOSTILE/.git/config"
new_env iso
ENVS=(GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=url.http://127.0.0.1:1/.insteadOf GIT_CONFIG_VALUE_0=https://github.com/
      GIT_CONFIG_PARAMETERS="'url.http://127.0.0.1:1/.insteadof=https://github.com/'"
      GIT_SSH_COMMAND=evil GIT_SSH=evil GIT_PROXY_COMMAND=evil GIT_ASKPASS=/evil GIT_EXEC_PATH=/evil GIT_DIR=/x)
X_CWD="$HOSTILE" run "$R_KEYLESS" "$XDG" --compare --refresh
check iso-still-answers ok "$(val latest_status)"
check iso-git-cwd-is-root / "$(glog cwd)"
check iso-git-config-global /dev/null "$(glog GIT_CONFIG_GLOBAL)"
check iso-git-config-system /dev/null "$(glog GIT_CONFIG_SYSTEM)"
check iso-git-config-nosystem 1 "$(glog GIT_CONFIG_NOSYSTEM)"
check iso-git-terminal-prompt 0 "$(glog GIT_TERMINAL_PROMPT)"
check iso-git-home-neutral /nonexistent "$(glog HOME)"
check iso-git-xdg-config-neutral /nonexistent "$(glog XDG_CONFIG_HOME)"
for k in GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS GIT_SSH_COMMAND GIT_SSH GIT_PROXY_COMMAND GIT_ASKPASS GIT_EXEC_PATH GIT_DIR; do
  check "iso-hostile-$k-not-visible" "<unset>" "$(glog "$k")"
done
_argv="$(glog argv)"
check_has iso-argv-protocol-allow-never "-c protocol.allow=never" "$_argv"
check_has iso-argv-https-allowed "-c protocol.https.allow=always" "$_argv"
check_has iso-argv-lowspeed-limit "-c http.lowSpeedLimit=1" "$_argv"
check_has iso-argv-lowspeed-time "-c http.lowSpeedTime=8" "$_argv"
check_has iso-argv-ls-remote-tags "ls-remote --tags https://github.com/jikig-ai/soleur.git refs/tags/v[0-9]*" "$_argv"
check iso-hostile-project-untouched ".git " "$(dirlist "$HOSTILE")"
check iso-curl-first-arg -q "$(head -1 "$CURLARGS")"
# the same call from an ordinary cwd with a clean env
new_env iso2; run "$R_KEYLESS" "$XDG" --latest --refresh
check iso-clean-env-cwd-is-root / "$(glog cwd)"
check iso-clean-env-no-ssh-command "<unset>" "$(glog GIT_SSH_COMMAND)"

# ---- fetch bound ---------------------------------------------------------------------
# A hung git is cut off at SOLEUR_FETCH_TIMEOUT; without timeout/gtimeout (stock macOS) the
# git call still bounds itself through http.lowSpeed*.
new_env tmo-real
if (( HAVE_TIMEOUT )); then
  ENVS=(SOLEUR_FETCH_TIMEOUT=1); SECONDS=0
  STUB_GIT_SLEEP=30 run "$R_KEYLESS" "$XDG" --latest --refresh; _el=$SECONDS
  check tmo-hung-git-status timeout "$(val latest_status)"
  check tmo-hung-git-returns-fast 1 "$(( _el < 5 ? 1 : 0 ))"
  check tmo-hung-git-was-called 1 "$(ncalls git)"
  check_has tmo-lowspeed-time-follows-env "http.lowSpeedTime=1" "$(glog argv)"
  check tmo-hung-git-rc 0 "$RC"
  # a hung git must not read as "current" from a fresh cache either
  new_env tmo-cache; put_cache b78d30e919ff v3.0.0 "$SHA1" "$(date +%s)" current ""
  ENVS=(SOLEUR_FETCH_TIMEOUT=1); STUB_GIT_SLEEP=30 run "$R_KEYLESS" "$XDG" --compare --refresh
  check tmo-hung-git-cached-current-degrades unknown/stale-cache "$(val relation)/$(val reason)"
else
  for n in status returns-fast was-called lowspeed-time-follows-env rc cached-current-degrades; do
    skip_case "tmo-hung-git-$n" "no timeout/gtimeout on PATH"
  done
  SKIP_RUN_DEFICIT=$((SKIP_RUN_DEFICIT + 2))
fi
# invalid values fall back to 8 (0 would disable every bound); a valid one is honoured
for bad in 0 abc "" -1 1.5 ' '; do
  new_env "tmo-bad"; ENVS=("SOLEUR_FETCH_TIMEOUT=$bad")
  run "$R_KEYLESS" "$XDG" --compare --refresh
  check "tmo-invalid-[$bad]-curl-m" 8 "$(cafter -m)"
  check_has "tmo-invalid-[$bad]-git-lowspeed" "http.lowSpeedTime=8" "$(glog argv)"
done
for good in 5:5 010:10 08:8 1:1; do
  new_env "tmo-good"; ENVS=("SOLEUR_FETCH_TIMEOUT=${good%%:*}")
  run "$R_KEYLESS" "$XDG" --compare --refresh
  check "tmo-valid-[${good%%:*}]-curl-m" "${good##*:}" "$(cafter -m)"
  check_has "tmo-valid-[${good%%:*}]-git-lowspeed" "http.lowSpeedTime=${good##*:}" "$(glog argv)"
done
# without timeout/gtimeout the low-speed bound still travels with the git call
new_env tmo-none; X_PATH="$P_NOTIMEOUT" run "$R_KEYLESS" "$XDG" --compare --refresh
check tmo-none-latest-ok v3.335.10 "$(val latest)"
check_has tmo-none-lowspeed-limit "-c http.lowSpeedLimit=1" "$(glog argv)"
check_has tmo-none-lowspeed-time "-c http.lowSpeedTime=8" "$(glog argv)"
check_has tmo-none-https-only "-c protocol.https.allow=always" "$(glog argv)"
check tmo-none-curl-keeps-m 8 "$(cafter -m)"

# ---- --cmp ---------------------------------------------------------------------------
cmp_row() { # a b want
  run - "$XDG" --cmp "$1" "$2"
  check "cmp-semver-[$1][$2]" "$3" "$OUT"
}
new_env cmpmode
cmp_row 1.2.3 1.2.4 older;      cmp_row 1.2.3 1.2.3 same;       cmp_row 1.2.4 1.2.3 newer
cmp_row 1.2.3 1.3.0 older;      cmp_row 2.0.0 1.99.99 newer;    cmp_row 3.335.10 3.335.9 newer
cmp_row 3.9.0 03.10.0 older;    cmp_row 1.02.3 1.2.3 same;      cmp_row 08.0.0 8.0.0 same
cmp_row 09.0.0 10.0.0 older;    cmp_row 0.0.0 0.0.0 same;       cmp_row 10.0.0 9.9.9 newer
cmp_row 1.2 1.2.3 unknown;      cmp_row v1.2.3 1.2.3 unknown;   cmp_row abc def unknown
cmp_row 1.2.3 1.2.3.4 unknown;  cmp_row 1.2.3 1.2.3-rc1 unknown; cmp_row "" "" unknown
cmp_row 1.2.3 "" unknown;       cmp_row ' 1.2.3' 1.2.3 unknown; cmp_row $'1.2.3\n' 1.2.3 unknown
run - "$XDG" --cmp 1.2.3
check cmp-missing-operand unknown "$OUT"; check cmp-missing-operand-rc 0 "$RC"
run - "$XDG" --cmp
check cmp-no-operands unknown "$OUT"
run - "$XDG" --cmp 1.2.3 1.2.4
check cmp-single-line 1 "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"; check cmp-rc 0 "$RC"
check cmp-no-git-call 0 "$(ncalls git)"; check cmp-no-curl-call 0 "$(ncalls curl)"

# ---- no jq: the top-level version only ------------------------------------------------
# The same fixtures run with jq and without; both arms must agree. A nested "version" (an MCP
# server's, say) must never be returned as the plugin's.
NJ=0
nj() { # name manifest want(source/version)
  NJ=$((NJ + 1)); local r; r="$(mkroot "$(printf 'nj/a%011x' "$NJ")" "$2")"
  X_PATH="$P_NOJQ" run "$r" "$XDG" --installed
  check "nojq-$1" "$3" "$(val source)/$(val version)"
  if (( HAVE_JQ )); then
    X_PATH="$P_JQ" run "$r" "$XDG" --installed
    check "jq-$1" "$3" "$(val source)/$(val version)"
  else
    skip_case "jq-$1" "jq not installed"; SKIP_RUN_DEFICIT=$((SKIP_RUN_DEFICIT + 1))
  fi
}
new_env nj
check nojq-path-has-no-jq 0 "$([[ -e "$P_NOJQ/jq" ]] && echo 1 || echo 0)"
nj single-line '{"name":"soleur","version":"1.2.3"}' manifest/1.2.3
nj pretty $'{\n  "name": "soleur",\n  "version": "1.2.3"\n}' manifest/1.2.3
nj spaced-colon '{"version" : "1.2.3"}' manifest/1.2.3
nj nested-only '{"mcpServers":{"x":{"version":"6.6.6"}}}' commit/
nj nested-only-pretty $'{\n  "mcpServers": {\n    "x": {\n      "version": "6.6.6"\n    }\n  }\n}' commit/
nj nested-before-top '{"nested":{"version":"6.6.6"},"version":"1.2.3"}' manifest/1.2.3
nj nested-before-top-pretty $'{\n  "nested": {\n    "version": "6.6.6"\n  },\n  "version": "1.2.3"\n}' manifest/1.2.3
nj top-before-nested '{"version":"1.2.3","nested":{"version":"6.6.6"}}' manifest/1.2.3
nj array-nested '{"list":[{"version":"6.6.6"}],"version":"1.2.3"}' manifest/1.2.3
nj top-nonsemver-nested-semver '{"version":"latest","n":{"version":"6.6.6"}}' commit/
nj braces-in-strings '{"a":"}}}","b":"{{{","version":"1.2.3"}' manifest/1.2.3
nj escaped-quotes-in-string '{"description":"has } and { and \" version\": \"9.9.9\" inside","x":{"y":"}"},"version":"1.2.3"}' manifest/1.2.3
nj version-as-value '{"name":"version","other":"1.2.3"}' commit/
nj number-version '{"version":123}' commit/

# ---- watchdog fallback, hostile cache base, symlinked read, command flag --------------------
# Without timeout/gtimeout a stalled git is killed by the bash watchdog (lowSpeed alone does not
# bound a stalled connect/TLS handshake).
new_env wd; ENVS=(SOLEUR_FETCH_TIMEOUT=1); _t0=$SECONDS
STUB_GIT_SLEEP=30 X_PATH="$P_NOTIMEOUT" run "$R_KEYLESS" "$XDG" --latest --refresh; _el=$((SECONDS - _t0))
check wd-no-timeout-binary-times-out timeout "$(val latest_status)"
check wd-no-timeout-binary-bounded-under-6s 1 "$(( _el < 6 ? 1 : 0 ))"
# A control character in XDG_CACHE_HOME must not inject key=value lines into the output.
new_env ctl; ENVS=("XDG_CACHE_HOME=/abs/x"$'\n'"relation=older"$'\n'"latest=v9.9.9"); run "$R_KEYLESS" "$XDG" --cached-latest
check ctl-xdg-no-injected-latest "" "$(printf '%s\n' "$OUT" | sed -n '/^latest=v9.9.9$/p')"
check ctl-xdg-falls-back-to-home-cache 1 "$(printf '%s\n' "$OUT" | grep -c '^cache_dir=.*/home/.cache/soleur$')"
# A symlinked cache dir is not READ either (a planted cache in a shared XDG dir).
new_env symread; put_cache b78d30e919ff v3.335.10 "$SHA3" "$(date +%s)" older ""
SYMR="$(mkd symread.target)"; assert_fixture_dir "$SYMR"; assert_fixture_dir "$XDG"; rmdir "$SYMR"; mv "$XDG/soleur" "$SYMR"; ln -s "$SYMR" "$XDG/soleur"
run "$R_KEYLESS" "$XDG" --cached-latest
check symread-refused missing "$(val cache)"
# The command is user-started: the legal text says so, so the flag must stay in the frontmatter.
check version-md-disable-model-invocation 1 "$(head -8 "$REPO_ROOT/plugins/soleur/commands/version.md" | grep -c '^disable-model-invocation: true$')"

# ---- installed: local checkout identity (source=checkout) --------------------------------
# An in-place install (a local-Folder marketplace, or --plugin-dir) loads the plugin from
# <top>/plugins/soleur, which has no manifest `version` and no 12-hex directory name. The
# identity is then the checkout's HEAD, read by PLAIN FILE READS ONLY: the repository's own
# config, hooks and attributes are untrusted project input and git is never run against it.
# Every fixture is hand-written bytes (no git exposure); the git stub records any call, so
# `ncalls git == 0` is the "never ran git" witness, and a real-git row proves the hostile
# config below is ARMED (a witness against an unarmed fixture would be vacuous).
SHA_M=0123456789abcdef0123456789abcdef01234567
SHA_X=fedcba9876543210fedcba9876543210fedcba98
SHA_Y=a1b2c3d4e5f60718293a4b5c6d7e8f9012345678
SHA_Z=00112233445566778899aabbccddeeff00112233
CO="$ROOTS/co"
REAL_GIT="$(command -v git 2>/dev/null || true)"

co_top() { # name -> fresh top dir whose plugins/soleur has a keyless manifest (printed)
  local top="$CO/$1"
  assert_fixture_dir "$top"; rm -rf "$top"
  mkdir -p "$top/plugins/soleur/.claude-plugin"
  printf '{"name":"soleur"}\n' > "$top/plugins/soleur/.claude-plugin/plugin.json"
  printf '%s' "$top"
}
co_clone() { # name sha [branch=main] -> top with a .git DIRECTORY, HEAD -> branch, one loose ref
  local top b="${3:-main}"; top="$(co_top "$1")"
  assert_fixture_dir "$top/.git"
  mkdir -p "$(dirname "$top/.git/refs/heads/$b")"
  printf 'ref: refs/heads/%s\n' "$b" > "$top/.git/HEAD"
  printf '%s\n' "$2" > "$top/.git/refs/heads/$b"
  printf '%s' "$top"
}
co_run() { run "$1/plugins/soleur" "$XDG" --installed; }
co_expect() { # name top sha40|unknown -> source/commit, no extra keys, rc 0, git never called
  co_run "$2"
  if [[ "$3" == unknown ]]; then
    check "$1" "source=unknown" "$OUT"
  else
    check "$1" "checkout/${3:0:12}/0/0" "$(val source)/$(val commit)/$(nval version)/$(nval marketplace)"
    check "$1-exact-output" "source=checkout"$'\n'"commit=${3:0:12}" "$OUT"
  fi
  check "$1-rc-and-no-git" "0/0" "$RC/$(ncalls git)"
}

new_env co
# --- positive shapes: a clone, a bare layout whose files are mirrored, a worktree, packed refs, detached
T="$(co_clone clone "$SHA_M")";                      co_expect co-clone "$T" "$SHA_M"
T="$(co_clone slash-branch "$SHA_X" feat/issue-#12)"; co_expect co-branch-with-slash-and-hash "$T" "$SHA_X"
T="$(co_clone bare "$SHA_Y")"                         # the maintainer's layout: core.bare=true, files mirrored on disk
printf '[core]\n\tbare = true\n\trepositoryformatversion = 0\n' > "$T/.git/config"; co_expect co-bare-mirrored "$T" "$SHA_Y"
T="$(co_top detached)"; mkdir -p "$T/.git"; printf '%s\n' "$SHA_Z" > "$T/.git/HEAD"; co_expect co-detached-head "$T" "$SHA_Z"
T="$(co_top detached-nonl)"; mkdir -p "$T/.git"; printf '%s' "$SHA_Z" > "$T/.git/HEAD"; co_expect co-detached-head-no-newline "$T" "$SHA_Z"
T="$(co_top packed)"; mkdir -p "$T/.git"; printf 'ref: refs/heads/main\n' > "$T/.git/HEAD"
printf '# pack-refs with: peeled fully-peeled sorted \n%s refs/heads/main-decoy\n%s refs/heads/main\n%s refs/tags/v1.0.0\n^%s\n' \
  "$SHA_X" "$SHA_M" "$SHA_Y" "$SHA_Z" > "$T/.git/packed-refs"
co_expect co-packed-refs-only "$T" "$SHA_M"
# a packed entry loses to nothing: with BOTH, the loose ref wins (git's own order)
T="$(co_top packed-and-loose)"; mkdir -p "$T/.git/refs/heads"; printf 'ref: refs/heads/main\n' > "$T/.git/HEAD"
printf '%s refs/heads/main\n' "$SHA_X" > "$T/.git/packed-refs"; printf '%s\n' "$SHA_Y" > "$T/.git/refs/heads/main"
co_expect co-loose-beats-packed "$T" "$SHA_Y"
# a linked worktree: .git is a FILE with `gitdir:`; per-worktree HEAD, refs from commondir
T="$(co_top worktree)"; COMMON="$CO/worktree-common.git"; assert_fixture_dir "$COMMON"; rm -rf "$COMMON"
mkdir -p "$COMMON/worktrees/wt" "$COMMON/refs/heads/feat"
printf 'ref: refs/heads/main\n' > "$COMMON/HEAD"
printf 'ref: refs/heads/feat/x\n' > "$COMMON/worktrees/wt/HEAD"
printf '../..\n' > "$COMMON/worktrees/wt/commondir"
printf '%s\n' "$SHA_M" > "$COMMON/refs/heads/feat/x"
printf 'gitdir: %s/worktrees/wt\n' "$COMMON" > "$T/.git"
co_expect co-worktree-absolute-gitdir "$T" "$SHA_M"
T="$(co_top worktree-rel)"; WRC="$CO/worktree-rel-common"; assert_fixture_dir "$WRC"; rm -rf "$WRC"
mkdir -p "$WRC/worktrees/wt" "$WRC/refs/heads"
printf 'ref: refs/heads/topic\n' > "$WRC/worktrees/wt/HEAD"; printf '../..\n' > "$WRC/worktrees/wt/commondir"
printf '%s\n' "$SHA_X" > "$WRC/refs/heads/topic"
printf 'gitdir: ../worktree-rel-common/worktrees/wt\n' > "$T/.git"
co_expect co-worktree-relative-gitdir "$T" "$SHA_X"
T="$(co_top worktree-detached)"; WDC="$CO/worktree-detached-common"; assert_fixture_dir "$WDC"; rm -rf "$WDC"
mkdir -p "$WDC/worktrees/wt"; printf '%s\n' "$SHA_Z" > "$WDC/worktrees/wt/HEAD"
printf 'gitdir: %s/worktrees/wt\n' "$WDC" > "$T/.git"
co_expect co-worktree-detached-head "$T" "$SHA_Z"
# a trailing slash on the root is the same root
T="$(co_clone slash "$SHA_M")"; run "$T/plugins/soleur/" "$XDG" --installed
check co-trailing-slash-root "checkout/${SHA_M:0:12}" "$(val source)/$(val commit)"
# a symlinked HEAD / loose ref still resolves (git itself follows them)
T="$(co_clone symlink "$SHA_Y")"; printf 'ref: refs/heads/main\n' > "$T/.git/real-head"; rm -f "$T/.git/HEAD"; ln -s real-head "$T/.git/HEAD"
co_expect co-symlinked-head "$T" "$SHA_Y"
# a directory name that ends in a newline: the decoy sibling must not be read in its place
# (command substitution strips trailing newlines, so a dirname/basename implementation reads
# the OTHER repository). The root below is the one with the newline.
NLP="$CO/decoy"; assert_fixture_dir "$NLP"; rm -rf "$NLP"
mkdir -p "$NLP/foo/.git/refs/heads" "$NLP/foo/plugins/soleur/.claude-plugin"
printf 'ref: refs/heads/main\n' > "$NLP/foo/.git/HEAD"; printf '%s\n' "$SHA_X" > "$NLP/foo/.git/refs/heads/main"
printf '{"name":"soleur"}\n' > "$NLP/foo/plugins/soleur/.claude-plugin/plugin.json"
NLD="$NLP/foo"$'\n'; mkdir -p "$NLD/.git/refs/heads" "$NLD/plugins/soleur/.claude-plugin"
printf 'ref: refs/heads/main\n' > "$NLD/.git/HEAD"; printf '%s\n' "$SHA_Y" > "$NLD/.git/refs/heads/main"
printf '{"name":"soleur"}\n' > "$NLD/plugins/soleur/.claude-plugin/plugin.json"
run "$NLD/plugins/soleur" "$XDG" --installed
check co-newline-dir-reads-its-own-repo "checkout/${SHA_Y:0:12}" "$(val source)/$(val commit)"
check co-newline-dir-two-lines 2 "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"

# --- precedence: a manifest version beats a checkout; a checkout never invents a version or marketplace
T="$(co_clone prec "$SHA_M")"; printf '{"name":"soleur","version":"2.1.0"}\n' > "$T/plugins/soleur/.claude-plugin/plugin.json"
co_run "$T"; check co-manifest-version-beats-checkout "manifest/2.1.0" "$(val source)/$(val version)"
check co-manifest-version-no-commit-key 0 "$(nval commit)"

# --- the anchor: only <top>/plugins/soleur with <top>/.git and a plugin.json is a checkout
T="$(co_clone anchor-other "$SHA_M")"; mkdir -p "$T/plugins/other/.claude-plugin"; printf '{"name":"soleur"}\n' > "$T/plugins/other/.claude-plugin/plugin.json"
run "$T/plugins/other" "$XDG" --installed; check co-anchor-wrong-basename "source=unknown" "$OUT"
T="$(co_top anchor-nogit)"; co_expect co-anchor-no-dot-git "$T" unknown
T="$(co_clone anchor-nomanifest "$SHA_M")"; rm -f "$T/plugins/soleur/.claude-plugin/plugin.json"
co_expect co-anchor-no-plugin-json "$T" unknown
# a dotfiles-style repository ABOVE the project must not be adopted: the walk is not free
DOT="$CO/dot"; assert_fixture_dir "$DOT"; rm -rf "$DOT"
mkdir -p "$DOT/home/.git/refs/heads" "$DOT/home/work/proj/plugins/soleur/.claude-plugin"
printf 'ref: refs/heads/main\n' > "$DOT/home/.git/HEAD"; printf '%s\n' "$SHA_X" > "$DOT/home/.git/refs/heads/main"
printf '{"name":"soleur"}\n' > "$DOT/home/work/proj/plugins/soleur/.claude-plugin/plugin.json"
run "$DOT/home/work/proj/plugins/soleur" "$XDG" --installed; check co-anchor-ancestor-repo-not-adopted "source=unknown" "$OUT"
# a directory that is NOT <top>/plugins/soleur but holds its own .git and plugin.json (any other
# plugin checkout passed to --plugin-dir) is not Soleur's identity: the suffix is the anchor
T="$(co_clone anchor-foreign "$SHA_M")"; mkdir -p "$T/.claude-plugin"; printf '{"name":"soleur"}\n' > "$T/.claude-plugin/plugin.json"
run "$T" "$XDG" --installed; check co-anchor-foreign-root-with-own-git "source=unknown" "$OUT"
# a relative root is never anchored (the cwd decides what it means)
# (./plugins/soleur ends in /plugins/soleur, so only the absolute-path check can refuse it)
T="$(co_clone anchor-rel "$SHA_M")"; X_CWD="$T" run "./plugins/soleur" "$XDG" --installed
check co-anchor-relative-root "source=unknown" "$OUT"
# a symlinked root is resolved physically: it names the repository it REALLY lives in
T="$(co_clone anchor-link "$SHA_M")"; ln -sfn "$T/plugins/soleur" "$CO/linkroot"
run "$CO/linkroot" "$XDG" --installed
check co-symlinked-root-reads-its-real-repo "checkout/${SHA_M:0:12}" "$(val source)/$(val commit)"
# ...and never the repository that merely holds the link (an unrelated project with a symlink in it)
H="$(co_clone symlink-host "$SHA_X")"; rm -rf "$H/plugins/soleur"; ln -s "$T/plugins/soleur" "$H/plugins/soleur"
run "$H/plugins/soleur" "$XDG" --installed
check co-symlink-inside-another-repo-reads-the-target-not-the-host "checkout/${SHA_M:0:12}" "$(val source)/$(val commit)"
# accepted residual, recorded as a row: a project that vendors plugins/soleur beside its own .git
# AND a plugin.json is indistinguishable from an in-place checkout (CTO ruling 2026-10-13: only 12
# hex of a validated line are ever shown, and only under the opt-in sent).
T="$(co_clone anchor-vendored "$SHA_Y")"; co_expect co-anchor-vendored-project-accepted "$T" "$SHA_Y"

# --- never reports what it did not read: every malformed HEAD / ref shape is `unknown`, silently
silent_head() { # name kind -> a clone whose HEAD file holds the bytes for <kind>
  local t f; t="$(co_clone "silent-$1" "$SHA_M")"; f="$t/.git/HEAD"
  case "$2" in
    empty)        : > "$f" ;;
    ref-only)     printf 'ref:\n' > "$f" ;;
    ref-no-name)  printf 'ref: refs/heads/\n' > "$f" ;;
    tag-ref)      printf 'ref: refs/tags/main\n' > "$f"; mkdir -p "$t/.git/refs/tags"; printf '%s\n' "$SHA_M" > "$t/.git/refs/tags/main" ;;
    dotdot)       printf 'ref: refs/heads/../x\n' > "$f" ;;
    space)        printf 'ref: refs/heads/a b\n' > "$f"; printf '%s\n' "$SHA_M" > "$t/.git/refs/heads/a b" ;;
    crlf-ref)     printf 'ref: refs/heads/main\r\n' > "$f" ;;
    crlf-sha)     printf '%s\r\n' "$SHA_M" > "$f" ;;
    sha39)        printf '%s\n' "${SHA_M:0:39}" > "$f" ;;
    sha41)        printf '%s\n' "${SHA_M}0" > "$f" ;;
    upper)        printf '%s\n' "$(printf '%s' "$SHA_M" | tr a-f A-F)" > "$f" ;;
    non-hex)      printf '%s\n' "${SHA_M:0:39}g" > "$f" ;;
    gitdir-line)  printf 'gitdir: /somewhere\n' > "$f" ;;
    unborn)       printf 'ref: refs/heads/nothing-here\n' > "$f" ;;
    two-lines)    printf '%s\n%s\n' "$SHA_M" "$SHA_X" > "$f" ;;
    nul-spliced)  printf 'ref: refs/heads/ma\0in\n' > "$f" ;;
    loose-ref-garbage) printf 'not a sha\n' > "$t/.git/refs/heads/main" ;;
    loose-ref-upper)   printf '%s\n' "$(printf '%s' "$SHA_M" | tr a-f A-F)" > "$t/.git/refs/heads/main" ;;
    loose-ref-dir)     rm -f "$t/.git/refs/heads/main"; mkdir -p "$t/.git/refs/heads/main" ;;
    loose-invalid-no-fallthrough) printf 'not a sha\n' > "$t/.git/refs/heads/main"; printf '%s refs/heads/main\n' "$SHA_X" > "$t/.git/packed-refs" ;;
    reftable)     printf 'ref: refs/heads/.invalid\n' > "$f"; mkdir -p "$t/.git/reftable" ;;
    packed-bad-sha) rm -f "$t/.git/refs/heads/main"; printf 'zzzz refs/heads/main\n' > "$t/.git/packed-refs" ;;
    packed-other-only) rm -f "$t/.git/refs/heads/main"; printf '%s refs/heads/mainx\n%s refs/heads/xmain\n' "$SHA_X" "$SHA_Y" > "$t/.git/packed-refs" ;;
    gitfile-garbage) rm -rf "$t/.git"; printf 'gitdir:\n' > "$t/.git" ;;
    gitfile-missing-target) rm -rf "$t/.git"; printf 'gitdir: %s/nowhere\n' "$CO" > "$t/.git" ;;
  esac
  printf '%s' "$t"
}
for kind in empty ref-only ref-no-name tag-ref dotdot space crlf-ref crlf-sha sha39 sha41 \
            upper non-hex gitdir-line unborn two-lines nul-spliced loose-ref-garbage \
            loose-ref-upper loose-ref-dir loose-invalid-no-fallthrough \
            reftable packed-bad-sha packed-other-only gitfile-garbage \
            gitfile-missing-target; do
  T="$(silent_head "$kind" "$kind")"; co_expect "co-silent-$kind" "$T" unknown
done
# valid_ref_name deny arms: every row names a ref whose loose file EXISTS and holds a valid sha, so
# without its arm the resolver would print a commit (a missing target would be refused anyway)
deny_ref() { # label ref-as-written [file-path-under-refs/heads, default = the ref]
  local t f; t="$(co_clone "deny-$1" "$SHA_M")"; f="${3:-$2}"
  mkdir -p "$(dirname "$t/.git/refs/heads/$f")"; printf '%s\n' "$SHA_M" > "$t/.git/refs/heads/$f"
  printf 'ref: refs/heads/%s\n' "$2" > "$t/.git/HEAD"
  co_expect "co-deny-ref-$1" "$t" unknown
}
deny_ref tilde 'a~b'; deny_ref caret 'a^b'; deny_ref colon 'a:b'; deny_ref qmark 'a?b'; deny_ref star 'a*b'
deny_ref bracket 'a[b'; deny_ref backslash 'a\b'; deny_ref at-brace 'a@{b'; deny_ref tab $'a\tb'
deny_ref lock-suffix 'x.lock'; deny_ref trailing-dot 'x.'; deny_ref dot-component 'a/.b'; deny_ref at-alone '@'
deny_ref double-slash 'a//b' 'a/b'
# `..` climbing out of refs/heads to a file that exists and holds a valid sha
T="$(co_clone deny-dotdot-climb "$SHA_M")"; mkdir -p "$T/.git/refs/heads/a"; printf '%s\n' "$SHA_M" > "$T/.git/refs/secretfile"
printf 'ref: refs/heads/a/../../secretfile\n' > "$T/.git/HEAD"; co_expect co-deny-ref-dotdot-climb "$T" unknown
# the same ref name accepted when it is NOT hostile (control: the rows above are not just a broken fixture)
T="$(co_clone deny-control "$SHA_M" 'a-b_c.d/e')"; co_expect co-deny-ref-control-accepts-a-plain-name "$T" "$SHA_M"
# pointer edge rows: an empty commondir is not a pointer; an absolute one is followed (ruled, bounded to 12 hex)
T="$(co_top commondir-empty)"; CDE="$CO/commondir-empty-common"; assert_fixture_dir "$CDE"; rm -rf "$CDE"
mkdir -p "$CDE/worktrees/wt" "$CDE/refs/heads"; printf 'ref: refs/heads/main\n' > "$CDE/worktrees/wt/HEAD"; : > "$CDE/worktrees/wt/commondir"
printf '%s\n' "$SHA_M" > "$CDE/refs/heads/main"; printf 'gitdir: %s/worktrees/wt\n' "$CDE" > "$T/.git"
# the fallback directory (the worktree's own gitdir) holds a valid ref too, so ONLY the empty-pointer guard refuses it
mkdir -p "$CDE/worktrees/wt/refs/heads"; printf '%s\n' "$SHA_X" > "$CDE/worktrees/wt/refs/heads/main"
co_expect co-commondir-empty-is-unknown "$T" unknown
T="$(co_top commondir-abs)"; CDA="$CO/commondir-abs-common"; assert_fixture_dir "$CDA"; rm -rf "$CDA"
mkdir -p "$CDA/worktrees/wt" "$CDA/refs/heads"; printf 'ref: refs/heads/main\n' > "$CDA/worktrees/wt/HEAD"; printf '%s\n' "$CDA" > "$CDA/worktrees/wt/commondir"
printf '%s\n' "$SHA_X" > "$CDA/refs/heads/main"; printf 'gitdir: %s/worktrees/wt\n' "$CDA" > "$T/.git"
co_expect co-commondir-absolute-is-followed "$T" "$SHA_X"
# a loose ref that is a DANGLING symlink exists as a path: it must not fall through to a packed entry
T="$(co_clone dangling "$SHA_M")"; rm -f "$T/.git/refs/heads/main"; ln -s /nonexistent-soleur-ref "$T/.git/refs/heads/main"
printf '%s refs/heads/main\n' "$SHA_X" > "$T/.git/packed-refs"; co_expect co-loose-dangling-symlink-no-fallthrough "$T" unknown
# a non-ASCII branch AND directory name resolve the same in every locale (bytes, not characters)
T="$(co_clone "café" "$SHA_M" 'feat/café')"
ENVS=(LC_ALL=C); co_expect co-nonascii-names-under-C-locale "$T" "$SHA_M"
co_expect co-nonascii-names-under-ambient-locale "$T" "$SHA_M"
UTF8LOC="$(locale -a 2>/dev/null | grep -i -m1 -E '^(en_US|C)\.utf-?8$' || true)"
if [[ -n "$UTF8LOC" ]]; then ENVS=("LC_ALL=$UTF8LOC"); co_expect co-nonascii-names-under-utf8-locale "$T" "$SHA_M"
else skip_case co-nonascii-names-under-utf8-locale "no UTF-8 locale installed"; skip_case co-nonascii-names-under-utf8-locale-exact-output "no UTF-8 locale installed"
     skip_case co-nonascii-names-under-utf8-locale-rc-and-no-git "no UTF-8 locale installed"; SKIP_RUN_DEFICIT=$((SKIP_RUN_DEFICIT + 1)); fi
# boundary rows: "ref: refs/heads/" + a 495-char name + LF is exactly the 512-byte gate; one char more is over it
mk_long_ref() { # name length -> clone whose HEAD names a ref of <length> chars after "ref: refs/heads/"
  local t n="$2" f c1 c2 c3 c4; t="$(co_clone "$1" "$SHA_M")"
  c1="$(printf 'a%.0s' $(seq 1 120))"; c2="$c1"; c3="$c1"
  c4="$(printf 'a%.0s' $(seq 1 $(( n - 363 ))))"
  mkdir -p "$t/.git/refs/heads/$c1/$c2/$c3"
  printf '%s\n' "$SHA_M" > "$t/.git/refs/heads/$c1/$c2/$c3/$c4"
  printf 'ref: refs/heads/%s/%s/%s/%s\n' "$c1" "$c2" "$c3" "$c4" > "$t/.git/HEAD"
  printf '%s' "$t"
}
T="$(mk_long_ref long-ok 495)"; co_expect co-head-at-512-byte-gate "$T" "$SHA_M"
T="$(mk_long_ref long-over 496)"; co_expect co-head-over-512-byte-gate "$T" unknown
# a huge sparse HEAD must be refused by size BEFORE any read (read -n 512 alone took 38 s on 2 GiB of NULs)
T="$(co_clone sparse "$SHA_M")"; rm -f "$T/.git/HEAD"; dd if=/dev/null of="$T/.git/HEAD" bs=1 seek=2147483648 2>/dev/null
X_TIMEOUT=10 co_expect co-silent-sparse-2gib-head "$T" unknown
# the matching entry is the FIRST line, so without the size gate awk would find it and print a commit
T="$(co_clone bigpacked "$SHA_M")"; rm -f "$T/.git/refs/heads/main"; printf '%s refs/heads/main\n' "$SHA_M" > "$T/.git/packed-refs"
printf '\0' | dd of="$T/.git/packed-refs" bs=1 seek=5242879 conv=notrunc 2>/dev/null   # sparse hole: the file is now 5 MiB, over the 4 MiB cap
X_TIMEOUT=10 co_expect co-silent-oversize-packed-refs "$T" unknown
# a real-sized packed-refs (this repository's own is ~0.5 MB) with the wanted entry LAST must resolve
T="$(co_clone realsize "$SHA_M")"; rm -f "$T/.git/refs/heads/main"
seq 1 15000 | awk -v s="$SHA_X" '{ printf "%s refs/heads/b%d\n", s, $1 }' > "$T/.git/packed-refs"; printf '%s refs/heads/main\n' "$SHA_M" >> "$T/.git/packed-refs"
co_expect co-packed-refs-real-sized-accepts-the-last-entry "$T" "$SHA_M"
# an oversize or non-regular plugin.json is skipped before jq/awk could stall on it
T="$(co_clone bigmanifest "$SHA_M")"; printf '\0' | dd of="$T/plugins/soleur/.claude-plugin/plugin.json" bs=1 seek=2097151 conv=notrunc 2>/dev/null
X_TIMEOUT=10 co_expect co-oversize-manifest-is-skipped-not-parsed "$T" "$SHA_M"
# a FIFO named HEAD would hang an open(2); [[ -f ]] refuses it before any open
# (the row needs a timeout binary: without one a regression would hang the suite instead of reddening a row)
if command -v mkfifo >/dev/null 2>&1 && [[ -n "$TIMEOUT_BIN" ]]; then
  T="$(co_clone fifo "$SHA_M")"; rm -f "$T/.git/HEAD"; mkfifo "$T/.git/HEAD"
  X_TIMEOUT=10 co_expect co-silent-fifo-head "$T" unknown
  T="$(co_clone fifo-manifest "$SHA_M")"; rm -f "$T/plugins/soleur/.claude-plugin/plugin.json"; mkfifo "$T/plugins/soleur/.claude-plugin/plugin.json"
  X_TIMEOUT=10 co_expect co-silent-fifo-manifest "$T" unknown
else
  skip_case co-silent-fifo-head "no mkfifo or timeout"; skip_case co-silent-fifo-head-rc-and-no-git "no mkfifo or timeout"
  skip_case co-silent-fifo-manifest "no mkfifo or timeout"; skip_case co-silent-fifo-manifest-rc-and-no-git "no mkfifo or timeout"
  SKIP_RUN_DEFICIT=$((SKIP_RUN_DEFICIT + 2))
fi

# --- hostile repository config: it is data, never executed, never even a reason to call git
SENT="$SANDBOX/hostile.fired"; HK="$SANDBOX/hostile-hooks"; rm -f "$SENT"; rm -rf "$HK"; mkdir -p "$HK"
printf '#!/bin/sh\necho fired > "%s"\nexit 0\n' "$SENT" > "$HK/pre-commit"; chmod +x "$HK/pre-commit"
printf '#!/bin/sh\necho fired > "%s"\nexit 0\n' "$SENT" > "$SANDBOX/hostile-prog"; chmod +x "$SANDBOX/hostile-prog"
hostile_config() { # <git-dir>
  printf '[core]\n\thooksPath = %s\n\tfsmonitor = %s\n\tsshCommand = %s\n\tpager = %s\n' "$HK" "$SANDBOX/hostile-prog" "$SANDBOX/hostile-prog" "$SANDBOX/hostile-prog" > "$1/config"
  printf '[include]\n\tpath = %s/never-read.cfg\n[alias]\n\trev-parse = !%s\n[url "https://evil.invalid/"]\n\tinsteadOf = https://github.com/\n' "$SANDBOX" "$SANDBOX/hostile-prog" >> "$1/config"
}
T="$(co_clone hostile "$SHA_M")"; hostile_config "$T/.git"; mkdir -p "$T/.git/hooks"; cp "$HK/pre-commit" "$T/.git/hooks/pre-commit"
co_expect co-hostile-config-read-not-run "$T" "$SHA_M"
check co-hostile-config-sentinel-absent 0 "$([[ -e "$SENT" ]] && echo 1 || echo 0)"
# The checkout code names no git command at all (the stub shadows `git` by NAME, so an absolute-path or
# `command -p` call would bypass it; this is the row that sees those). Comments are stripped first.
CK_SRC="$(awk '/^# ---- local checkout/ {f=1} /^resolve_installed\(\)/ {f=0} f' "$SUT" | sed 's/[[:space:]]#.*$//; /^#/d')"
check co-checkout-code-has-a-body 1 "$([[ "$CK_SRC" == *"resolve_checkout_commit()"* ]] && echo 1 || echo 0)"
check co-checkout-code-names-no-git-command 0 "$(printf '%s\n' "$CK_SRC" | grep -cE '(^|[[:space:];&|(`])(/[^[:space:]]*/)?git[[:space:]]' || true)"
if [[ -n "$REAL_GIT" ]]; then
  # The witness: the SAME config text, in a repository real git understands, fires the hook...
  WT="$CO/witness"; assert_fixture_dir "$WT"; rm -rf "$WT"; mkdir -p "$WT"
  ( source "$DIR/lib/git-fixture-env.sh" && git_fixture_env "$WT" \
      && cd "$WT" && "$REAL_GIT" init -q . && hostile_config "$WT/.git" \
      && "$REAL_GIT" commit -q --allow-empty -m witness ) >/dev/null 2>&1
  check co-hostile-config-is-armed-for-real-git 1 "$([[ -e "$SENT" ]] && echo 1 || echo 0)"
  # ...and the resolver, run on that very repository, reads it without firing anything.
  rm -f "$SENT"; mkdir -p "$WT/plugins/soleur/.claude-plugin"; printf '{"name":"soleur"}\n' > "$WT/plugins/soleur/.claude-plugin/plugin.json"
  WREF="$(sed 's/^ref: //' "$WT/.git/HEAD")"; WSHA="$(cat "$WT/.git/$WREF" 2>/dev/null)"
  co_expect co-hostile-real-repo-read-not-run "$WT" "$WSHA"
  check co-hostile-real-repo-sentinel-absent 0 "$([[ -e "$SENT" ]] && echo 1 || echo 0)"
else
  skip_case co-hostile-config-is-armed-for-real-git "git not installed"
  skip_case co-hostile-real-repo-read-not-run "git not installed"; skip_case co-hostile-real-repo-read-not-run-exact-output "git not installed"
  skip_case co-hostile-real-repo-read-not-run-rc-and-no-git "git not installed"; skip_case co-hostile-real-repo-sentinel-absent "git not installed"
  SKIP_RUN_DEFICIT=$((SKIP_RUN_DEFICIT + 1))
fi
# the user-facing prose names the label the hook prints (a dropped `source=checkout` arm must not go unnoticed)
for doc in commands/version.md commands/help.md README.md; do
  check_has "co-label-in-$doc" "(local checkout)" "$(cat "$REPO_ROOT/plugins/soleur/$doc")"
done

# --- parity with real git (gated): the resolver and `git rev-parse HEAD` agree on real layouts
if [[ -n "$REAL_GIT" ]]; then
  PR="$CO/parity"; assert_fixture_dir "$PR"; rm -rf "$PR"; mkdir -p "$PR"
  ( source "$DIR/lib/git-fixture-env.sh" && git_fixture_env "$PR" && cd "$PR" && "$REAL_GIT" init -q -b main . \
      && mkdir -p plugins/soleur/.claude-plugin && printf '{"name":"soleur"}\n' > plugins/soleur/.claude-plugin/plugin.json \
      && "$REAL_GIT" add . && "$REAL_GIT" commit -q -m one && "$REAL_GIT" pack-refs --all --prune \
      && "$REAL_GIT" rev-parse HEAD > "$SANDBOX/parity.head" \
      && "$REAL_GIT" worktree add -q -b wtbranch "$PR-wt" >/dev/null \
      && ( cd "$PR-wt" && "$REAL_GIT" commit -q --allow-empty -m two && "$REAL_GIT" rev-parse HEAD > "$SANDBOX/parity.wthead" ) ) >/dev/null 2>&1
  PH="$(cat "$SANDBOX/parity.head" 2>/dev/null || true)"; PW="$(cat "$SANDBOX/parity.wthead" 2>/dev/null || true)"
  check co-parity-fixture-has-packed-refs-only 0 "$([[ -e "$PR/.git/refs/heads/main" ]] && echo 1 || echo 0)"
  run "$PR/plugins/soleur" "$XDG" --installed; check co-parity-packed-refs-matches-rev-parse "checkout/${PH:0:12}" "$(val source)/$(val commit)"
  run "$PR-wt/plugins/soleur" "$XDG" --installed; check co-parity-linked-worktree-matches-rev-parse "checkout/${PW:0:12}" "$(val source)/$(val commit)"
else
  skip_case co-parity-fixture-has-packed-refs-only "git not installed"
  skip_case co-parity-packed-refs-matches-rev-parse "git not installed"; skip_case co-parity-linked-worktree-matches-rev-parse "git not installed"
  SKIP_RUN_DEFICIT=$((SKIP_RUN_DEFICIT + 2))
fi

# --- relation and cache for a checkout: treated like a commit install
T="$(co_clone cmp "$SHA_M")"
new_env co-cmp; printf '%s' "$(body_pretty ahead modified)" > "$CMP"
run "$T/plugins/soleur" "$XDG" --compare --refresh
check co-compare-older "older" "$(val relation)"
check co-compare-one-curl-call 1 "$(ncalls curl)"
check co-compare-url-carries-only-12-hex 1 "$(grep -c "compare/${SHA_M:0:12}\.\.\.v3.335.10?per_page=1&page=2000" "$CALLS")"
check co-compare-no-marketplace-key 0 "$(nval marketplace)"
check co-compare-cache-is-one-stable-file "latest-release.checkout" "$(cd "$XDG/soleur" 2>/dev/null && ls latest-release.* 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
check co-compare-cache-records-the-commit "${SHA_M:0:12}" "$(cval checkout relation_for)"
# a second commit of the same checkout rewrites the one file rather than adding another
T2="$(co_clone cmp2 "$SHA_X")"; run "$T2/plugins/soleur" "$XDG" --compare --refresh
check co-compare-second-commit-reuses-the-file "latest-release.checkout/${SHA_X:0:12}" "$(cd "$XDG/soleur" && ls latest-release.* | tr '\n' ' ' | sed 's/ $//')/$(cval checkout relation_for)"
co_cmp_case() { # name body curl-rc want-relation want-reason
  new_env "co-$1"; printf '%s' "$2" > "$CMP"; STUB_CURL_RC="$3" run "$T/plugins/soleur" "$XDG" --compare --refresh
  check "co-$1" "$4/$5" "$(val relation)/$(val reason)"
}
co_cmp_case cmp-diverged "$(body_pretty diverged removed)" 0 unknown diverged
co_cmp_case cmp-failed '{}' 22 unknown compare-failed
new_env co-nocurl; X_PATH="$P_NOCURL" run "$T/plugins/soleur" "$XDG" --compare --refresh
check co-compare-no-curl "unknown/no-curl" "$(val relation)/$(val reason)"
# HEAD is the commit a release tag points at: current, no compare call at all
T3="$(co_clone attag "$SHA3")"; new_env co-attag; run "$T3/plugins/soleur" "$XDG" --compare --refresh
check co-attag-current "current" "$(val relation)"; check co-attag-no-curl 0 "$(ncalls curl)"
# another commit's cache entry reads as missing (not corrupt) for a checkout, and spawns no claim of corruption
T="$(co_clone cache "$SHA_M")"; new_env co-cache
put_cache checkout v3.335.10 "$SHA3" "$(date +%s)" older "" 1 "${SHA_X:0:12}"
run "$T/plugins/soleur" "$XDG" --cached-latest; check co-cache-other-commit-is-missing missing "$(val cache)"
put_cache checkout v3.335.10 "$SHA3" "$(date +%s)" older "" 1 "${SHA_M:0:12}"
run "$T/plugins/soleur" "$XDG" --cached-latest; check co-cache-same-commit-is-fresh "fresh/older" "$(val cache)/$(val relation)"
# ...while every OTHER source keeps `corrupt` for a mismatched entry (existing behaviour must not move)
new_env co-cache-ctl; put_cache b78d30e919ff v3.335.10 "$SHA3" "$(date +%s)" older "" 1 aaaaaaaaaaaa
run "$R_KEYLESS" "$XDG" --cached-latest; check co-cache-commit-install-mismatch-stays-corrupt corrupt "$(val cache)"
# an unreadable checkout has nothing to key a cache on: nothing persisted
T="$(silent_head cache-unk empty)"; new_env co-unk; run "$T/plugins/soleur" "$XDG" --compare --refresh
check co-unknown-checkout-relation "unknown/installed-unknown" "$(val relation)/$(val reason)"
check co-unknown-checkout-no-curl 0 "$(ncalls curl)"
check co-unknown-checkout-nothing-persisted "" "$(dirlist "$XDG")"

# ---- accounting and verdict -----------------------------------------------------------
if (( passes + fails != CASES )) || (( fails != ${#FAILURES[@]} )); then
  printf 'FATAL: verdict accounting broken -- passes(%d) + fails(%d) != CASES(%d), or fails != ledger(%d)\n' \
    "$passes" "$fails" "$CASES" "${#FAILURES[@]}" >&2
  exit 1
fi
MIN_CASES=618
if (( CASES != MIN_CASES )); then
  printf 'FATAL: %d cases ran, expected exactly %d -- cases were added or deleted, or the suite aborted early\n' "$CASES" "$MIN_CASES" >&2
  exit 1
fi
# The subject must actually have run: a harness that asserts on empty output for every row
# would still satisfy every "prints nothing" row.
MIN_RUNS=310
# Skipped rows (no jq, no timeout, no git, no mkfifo) did not drive the resolver, and skip_case
# already counted them as cases, so the exact run count is credited by what they would have run.
EXPECT_RUNS=$(( MIN_RUNS - SKIP_RUN_DEFICIT ))
if (( RUNS != EXPECT_RUNS )); then
  printf 'FATAL: subject ran %d times, expected exactly %d -- the harness asserted without driving the resolver\n' "$RUNS" "$EXPECT_RUNS" >&2
  exit 1
fi
printf '\n%d passed, %d failed (%d cases, %d subject invocations, %d skipped)\n' "$passes" "$fails" "$CASES" "$RUNS" "$SKIPS"
if (( ${#FAILURES[@]} > 0 )); then
  printf 'FAILURES:\n'; for f in "${FAILURES[@]}"; do printf '  - %s\n' "$f"; done
  exit 1
fi
printf 'ALL TESTS PASSED\n'
exit 0
