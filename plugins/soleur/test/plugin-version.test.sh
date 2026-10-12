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
BASE_TOOLS="bash sh sed grep awk sort date stat mktemp mv rm chmod mkdir basename tail head tr cat dirname cut sleep touch ln env"
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

# ---- verdict helpers -----------------------------------------------------------
passes=0; fails=0; CASES=0; RUNS=0; SKIPS=0; QUIET=0
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
#   Per-call knobs (set as prefix assignments): X_CWD X_PATH X_SUT X_HOME LSR STUB_*.
#   ENVS=(A=b ...) is consumed by the next run.
run() {
  local root="$1" xdg="$2"; shift 2
  local -a ex=() e=(env -u CLAUDE_PLUGIN_ROOT -u XDG_CACHE_HOME)
  if (( ${#ENVS[@]} )); then ex=("${ENVS[@]}"); fi
  ENVS=()
  [[ "$root" != - ]] && e+=("CLAUDE_PLUGIN_ROOT=$root")
  [[ "$xdg" != - ]] && e+=("XDG_CACHE_HOME=$xdg")
  RUNS=$((RUNS + 1))
  OUT="$(cd "${X_CWD:-$SANDBOX/cwd}" && "${e[@]}" PATH="${X_PATH:-$STUBS:$PATH}" HOME="${X_HOME-$SANDBOX/home}" \
    STUB_CALLS="$CALLS" STUB_GITLOG="$GITLOG" STUB_CURLARGS="$CURLARGS" \
    STUB_LSREMOTE="$LSR" STUB_COMPARE_BODY="$CMP" \
    STUB_GIT_RC="${STUB_GIT_RC:-0}" STUB_CURL_RC="${STUB_CURL_RC:-0}" STUB_GIT_SLEEP="${STUB_GIT_SLEEP:-}" \
    ${ex[@]+"${ex[@]}"} "$REAL_BASH" "${X_SUT:-$SUT}" "$@" 2>&1)"
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
# running the real script from the repo: plugins/soleur is not a commit dir and is keyless
run - "$XDG" --installed
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
    skip_case "jq-$1" "jq not installed"
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

# ---- accounting and verdict -----------------------------------------------------------
if (( passes + fails != CASES )) || (( fails != ${#FAILURES[@]} )); then
  printf 'FATAL: verdict accounting broken -- passes(%d) + fails(%d) != CASES(%d), or fails != ledger(%d)\n' \
    "$passes" "$fails" "$CASES" "${#FAILURES[@]}" >&2
  exit 1
fi
MIN_CASES=408
if (( CASES != MIN_CASES )); then
  printf 'FATAL: %d cases ran, expected exactly %d -- cases were added or deleted, or the suite aborted early\n' "$CASES" "$MIN_CASES" >&2
  exit 1
fi
# The subject must actually have run: a harness that asserts on empty output for every row
# would still satisfy every "prints nothing" row.
MIN_RUNS=215
if (( RUNS != MIN_RUNS )); then
  printf 'FATAL: subject ran %d times, expected exactly %d -- the harness asserted without driving the resolver\n' "$RUNS" "$MIN_RUNS" >&2
  exit 1
fi
printf '\n%d passed, %d failed (%d cases, %d subject invocations, %d skipped)\n' "$passes" "$fails" "$CASES" "$RUNS" "$SKIPS"
if (( ${#FAILURES[@]} > 0 )); then
  printf 'FAILURES:\n'; for f in "${FAILURES[@]}"; do printf '  - %s\n' "$f"; done
  exit 1
fi
printf 'ALL TESTS PASSED\n'
exit 0
