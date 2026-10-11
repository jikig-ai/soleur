#!/usr/bin/env bash
# Guard suite for plugins/soleur/scripts/plugin-version.sh.
#
# The resolver feeds the SessionStart banner, /soleur:version and /soleur:help, so the
# properties pinned here are the ones a user would be misled by if they broke:
#   * it never reports a version it did not read;
#   * "cannot tell" (offline, timeout, diverged, parse failure) is never rendered as
#     "current";
#   * the tag filter excludes the repo's other tag families (web-v*, vinngest-v*,
#     zot-image-*, prereleases) and orders numerically, not lexically;
#   * it always exits 0 and works without jq and with an unwritable cache.
# Network is stubbed: PATH carries a fake `git` and `curl` that record argv and exit 64
# on any shape the resolver is not supposed to send.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -P "$DIR/../../.." && pwd -P)"
SUT="$REPO_ROOT/plugins/soleur/scripts/plugin-version.sh"

# shellcheck source=plugins/soleur/test/test-helpers.sh
source "$DIR/test-helpers.sh" || { echo "FATAL: could not source test-helpers.sh" >&2; exit 2; }
set +e -uo pipefail

SANDBOX="$(mktemp -d -t plugver.XXXXXXXX)" || { echo "FATAL: mktemp failed" >&2; exit 2; }
assert_fixture_dir "$SANDBOX"
trap 'rm -rf "$SANDBOX"' EXIT INT TERM HUP

STUBS="$SANDBOX/stubs"; mkdir -p "$STUBS"
ROOTS="$SANDBOX/roots"; mkdir -p "$ROOTS"
CALLS="$SANDBOX/calls"; : > "$CALLS"

cat > "$STUBS/git" <<'STUB'
#!/usr/bin/env bash
echo "git $*" >> "$STUB_CALLS"
if [[ "${1:-}" == ls-remote && "$*" == *"refs/tags/v*"* ]]; then
  [[ "${STUB_GIT_RC:-0}" != 0 ]] && exit "$STUB_GIT_RC"
  cat "$STUB_LSREMOTE"; exit 0
fi
exit 64
STUB
cat > "$STUBS/curl" <<'STUB'
#!/usr/bin/env bash
echo "curl $*" >> "$STUB_CALLS"
[[ "$*" == *"/compare/"* ]] || exit 64
[[ "${STUB_CURL_RC:-0}" != 0 ]] && exit "$STUB_CURL_RC"
cat "$STUB_COMPARE_BODY"; exit 0
STUB
chmod +x "$STUBS/git" "$STUBS/curl"

# A PATH with the tools the resolver needs and no jq (the sed fallback must work).
NOJQ="$SANDBOX/nojq"; mkdir -p "$NOJQ"
for t in bash sh sed grep awk sort date stat mktemp mv rm chmod mkdir basename tail head tr cat timeout dirname; do
  p="$(command -v "$t" 2>/dev/null)" && ln -sf "$p" "$NOJQ/$t"
done

passes=0; fails=0; CASES=0; FAILURES=()
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); FAILURES+=("$1"); }
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

# Instrument self-test: drive both verdict paths once and require every observable
# to move, before any assertion is trusted.
_p0=$passes; _f0=$fails; _c0=$CASES; _n0=${#FAILURES[@]}
check selftest-pass a a; check selftest-fail a b
if (( passes != _p0 + 1 || fails != _f0 + 1 || CASES != _c0 + 2 || ${#FAILURES[@]} != _n0 + 1 )); then
  echo "FATAL: instrument self-test failed -- verdict helpers do not move their counters" >&2; exit 1
fi
passes=$_p0; fails=$_f0; CASES=$_c0; FAILURES=("${FAILURES[@]:0:$_n0}")

mkroot() { # dirname manifest-json -> prints root path
  local r="$ROOTS/$1"
  mkdir -p "$r/.claude-plugin"
  printf '%s\n' "$2" > "$r/.claude-plugin/plugin.json"
  printf '%s' "$r"
}

new_env() { # fresh cache + call log per scenario
  XDG="$SANDBOX/xdg.$1"; rm -rf "$XDG"; mkdir -p "$XDG"; : > "$CALLS"
}

# run <root|-> <cache-dir> args... ; sets OUT and RC
run() {
  local root="$1" xdg="$2"; shift 2
  local -a e=(env -u CLAUDE_PLUGIN_ROOT)
  [[ "$root" != - ]] && e=(env CLAUDE_PLUGIN_ROOT="$root")
  OUT="$("${e[@]}" PATH="$STUBS:$PATH" XDG_CACHE_HOME="$xdg" HOME="$SANDBOX/home" \
    STUB_CALLS="$CALLS" STUB_LSREMOTE="$LSR" STUB_COMPARE_BODY="$CMP" \
    STUB_GIT_RC="${STUB_GIT_RC:-0}" STUB_CURL_RC="${STUB_CURL_RC:-0}" \
    bash "$SUT" "$@" 2>&1)"
  RC=$?
}
val() { printf '%s\n' "$OUT" | sed -n "s/^$1=//p" | head -1; }
ncalls() { grep -c "^$1 " "$CALLS" 2>/dev/null || true; }

mkdir -p "$SANDBOX/home"
LSR="$SANDBOX/lsremote"; CMP="$SANDBOX/compare.json"
SHA1=1111111111111111111111111111111111111111
SHA2=2222222222222222222222222222222222222222
SHA3=3333333333333333333333333333333333333333
printf '%s\t%s\n' \
  "$SHA1" "refs/tags/vinngest-v1.1.50" "$SHA1" "refs/tags/web-v0.9.9" "$SHA1" "refs/tags/zot-image-v2.1.20" \
  "$SHA1" "refs/tags/v3.335.8-rc1" "$SHA1" "refs/tags/v3.335.8" \
  "$SHA2" "refs/tags/v3.335.10" "$SHA3" "refs/tags/v3.335.10^{}" \
  "$SHA1" "refs/tags/v3.9.0" > "$LSR"
printf '{"url":"x","status":"ahead","ahead_by":3,"files":[{"status":"modified"}]}\n' > "$CMP"

# ---- installed ---------------------------------------------------------------
R_STAMPED="$(mkroot 3.335.8 '{"name":"soleur","version":"3.335.8"}')"
R_KEYLESS="$(mkroot b78d30e919ff '{"name":"soleur"}')"
R_SUFFIX="$(mkroot b78d30e919ff-1a2b3c4d '{"name":"soleur"}')"
R_NEITHER="$(mkroot plain-dir '{"name":"soleur"}')"
R_GARBAGE="$(mkroot abcdef012345 '{"name":"soleur","version":"latest"}')"

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
run - "$XDG" --installed
check inst-noroot-source none "$(val source)"; check inst-noroot-rc 0 "$RC"
run "$R_GARBAGE" "$XDG" --installed
check inst-garbage-ignored commit "$(val source)"; check inst-garbage-no-version "" "$(val version)"
OUT="$(env CLAUDE_PLUGIN_ROOT="$R_STAMPED" PATH="$NOJQ" XDG_CACHE_HOME="$XDG" HOME="$SANDBOX/home" "$NOJQ/bash" "$SUT" --installed 2>&1)"
check inst-nojq-version 3.335.8 "$(val version)"
run "$R_STAMPED" "$XDG" --bogus-flag
check bogus-flag-rc 0 "$RC"

# ---- latest: tag filter and ordering ------------------------------------------
new_env tags
run "$R_KEYLESS" "$XDG" --latest --refresh
check tags-latest v3.335.10 "$(val latest)"
check tags-latest-commit-peeled "$SHA3" "$(val latest_commit)"
check tags-status ok "$(val latest_status)"
check_lacks tags-no-web-tag web-v "$OUT"; check_lacks tags-no-rc rc1 "$OUT"
check tags-ls-remote-called 1 "$(ncalls git)"
check tags-fixed-url 1 "$(grep -c 'github.com/jikig-ai/soleur.git' "$CALLS")"

# ---- latest vs --latest on stamped/keyless: same latest section -----------------
new_env same-a; run "$R_STAMPED" "$XDG" --latest --refresh; A="$(printf '%s\n' "$OUT" | grep -E '^(latest|latest_commit|latest_status)=')"
new_env same-b; run "$R_KEYLESS" "$XDG" --latest --refresh; B="$(printf '%s\n' "$OUT" | grep -E '^(latest|latest_commit|latest_status)=')"
check latest-independent-of-manifest-key "$A" "$B"

# ---- relation: manifest installs (semver) ------------------------------------
new_env rel-a; run "$R_STAMPED" "$XDG" --compare --refresh
check rel-manifest-older older "$(val relation)"
check rel-manifest-no-compare-call 0 "$(ncalls curl)"
R_NEW="$(mkroot 3.335.10 '{"name":"soleur","version":"3.335.10"}')"
new_env rel-b; run "$R_NEW" "$XDG" --compare --refresh
check rel-manifest-current current "$(val relation)"
R_AHEAD="$(mkroot 4.0.0 '{"name":"soleur","version":"4.0.0"}')"
new_env rel-c; run "$R_AHEAD" "$XDG" --compare --refresh
check rel-manifest-downgrade-is-current current "$(val relation)"

# ---- relation: commit installs (compare API) ----------------------------------
cmp_case() { # name body curl-rc want-relation want-reason
  new_env "$1"
  printf '%s' "$2" > "$CMP"
  STUB_CURL_RC="$3" run "$R_KEYLESS" "$XDG" --compare --refresh
  check "cmp-$1-relation" "$4" "$(val relation)"
  check "cmp-$1-reason" "$5" "$(val reason)"
  check "cmp-$1-one-call" 1 "$(ncalls curl)"
}
cmp_case ahead      '{"status":"ahead","ahead_by":3,"files":[{"status":"modified"}]}' 0 older ""
cmp_case behind     '{"status":"behind","ahead_by":0,"files":[{"status":"added"}]}'   0 current ""
cmp_case identical  '{"status":"identical","ahead_by":0}'                             0 current ""
cmp_case diverged   '{"status":"diverged","ahead_by":6,"behind_by":2}'               0 unknown diverged
cmp_case failed     '{}'                                                              22 unknown compare-failed
cmp_case garbage    'not json at all'                                                 0 unknown compare-unparseable
check cmp-url-has-sha-and-tag 1 "$(grep -c 'compare/b78d30e919ff...v3.335.10?per_page=1' "$CALLS")"
check cmp-no-up-to-date-wording-when-unknown "" "$(printf '%s' "$OUT" | grep -i 'up to date' || true)"

# ---- failure statuses never read as current -----------------------------------
new_env off; STUB_GIT_RC=128 run "$R_KEYLESS" "$XDG" --compare --refresh
check off-status offline "$(val latest_status)"; check off-rc 0 "$RC"
check_lacks off-no-current "relation=current" "$OUT"; check off-no-latest "" "$(val latest)"
new_env tmo; STUB_GIT_RC=124 run "$R_KEYLESS" "$XDG" --compare --refresh
check tmo-status timeout "$(val latest_status)"
new_env notags; : > "$SANDBOX/empty"; ( LSR="$SANDBOX/empty"; run "$R_KEYLESS" "$XDG" --compare --refresh; echo "$OUT" > "$SANDBOX/notags.out" )
check_has notags-status latest_status=no-tags "$(cat "$SANDBOX/notags.out")"

# ---- cache -------------------------------------------------------------------
new_env c1; run "$R_STAMPED" "$XDG" --latest --refresh
check cache-written-0600 600 "$(stat -c %a "$XDG/soleur/latest-release" 2>/dev/null || stat -f %Lp "$XDG/soleur/latest-release")"
check cache-dir-0700 700 "$(stat -c %a "$XDG/soleur" 2>/dev/null || stat -f %Lp "$XDG/soleur")"
: > "$CALLS"; run "$R_STAMPED" "$XDG" --latest
check cache-fresh-no-network 0 "$(ncalls git)"; check cache-fresh-state fresh "$(val cache)"
run "$R_STAMPED" "$XDG" --cached-latest
check cached-latest-no-network 0 "$(ncalls git)"; check cached-latest-value v3.335.10 "$(val latest)"
run "$R_STAMPED" "$XDG" --latest --refresh
check cache-refresh-forces-call 1 "$(ncalls git)"
# relation is only trusted for the install it was computed for
run "$R_KEYLESS" "$XDG" --cached-latest
check cache-relation-other-install unknown "$(val relation)"

mkold() { # name fetched-epoch
  new_env "$1"; mkdir -p "$XDG/soleur"
  printf 'tag=v3.0.0\nsha=%s\nfetched=%s\nrelation=older\nrelation_for=3.335.8\nreason=\n' "$SHA1" "$2" > "$XDG/soleur/latest-release"
}
mkold stale "$(( $(date +%s) - 200000 ))"
run "$R_STAMPED" "$XDG" --cached-latest; check stale-state stale "$(val cache)"
run "$R_STAMPED" "$XDG" --latest;        check stale-refetches 1 "$(ncalls git)"; check stale-new-tag v3.335.10 "$(val latest)"
mkold future "$(( $(date +%s) + 99999 ))"
run "$R_STAMPED" "$XDG" --cached-latest; check future-dated-is-stale stale "$(val cache)"
new_env corrupt; mkdir -p "$XDG/soleur"; printf 'garbage\n' > "$XDG/soleur/latest-release"
run "$R_STAMPED" "$XDG" --cached-latest; check corrupt-state corrupt "$(val cache)"; check corrupt-rc 0 "$RC"
new_env missing
run "$R_STAMPED" "$XDG" --cached-latest; check missing-state missing "$(val cache)"; check missing-no-latest "" "$(val latest)"

# unwritable cache dir: still answers from the fetch, still exits 0
new_env ro; : > "$SANDBOX/blocker"
run "$R_STAMPED" "$SANDBOX/blocker" --latest --refresh
check unwritable-rc 0 "$RC"; check unwritable-status ok "$(val latest_status)"

# ---- accounting --------------------------------------------------------------
if (( passes + fails != CASES )); then
  printf 'FATAL: verdict accounting broken -- passes(%d) + fails(%d) != CASES(%d)\n' "$passes" "$fails" "$CASES" >&2
  exit 1
fi
MIN_CASES=69
if (( CASES < MIN_CASES )); then
  printf 'FATAL: only %d cases ran, floor is %d -- the suite asserted less than it claims\n' "$CASES" "$MIN_CASES" >&2
  exit 1
fi
printf '\n%d passed, %d failed (%d cases)\n' "$passes" "$fails" "$CASES"
if (( ${#FAILURES[@]} > 0 )); then
  printf 'FAILURES:\n'; for f in "${FAILURES[@]}"; do printf '  - %s\n' "$f"; done
  exit 1
fi
printf 'ALL TESTS PASSED\n'
exit 0
