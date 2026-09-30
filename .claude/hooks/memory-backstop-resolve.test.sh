#!/usr/bin/env bash
# Suite for .claude/hooks/memory-backstop-resolve.sh (#9239, ADR-261).
#
# PURE FIXTURE — always runs, including CI, Docker, macOS, non-systemd Linux.
# The resolver's contract is filesystem-only: fixture candidate trees under a
# mktemp root stand in for the checkout copy, the managed copy under
# ${XDG_DATA_HOME}/soleur/hooks/, and the two plugin caches under $HOME.
#
# NO INJECTION SEAMS — same posture as memory-backstop.test.sh. The resolver
# is exercised by EXECUTING a staged copy of the real file (`bash <fixture>`)
# against fixture directories. The variables it honours — HOME, XDG_DATA_HOME
# — ARE the mechanism under test, so they are set per-invocation in the child
# environment, never as magic globals the suite mutates. Where a unit test
# needs the functions directly it SOURCES the shim, which is safe because the
# shim runs main only under the `BASH_SOURCE == $0` guard.
#
# WHAT IS ASSERTED (plan M1):
#   * Revision extraction is GREP-ONLY — absent and non-numeric markers read
#     as 0, and the shim never sources/evals/dots a candidate to learn its
#     version (ADR-156 posture: candidate bodies are unverified code).
#   * Highest revision wins; ties resolve to the FIRST candidate in
#     precedence order — checkout beats managed beats the plugin caches, so a
#     local uncommitted edit wins over an equally-versioned install.
#   * A winner failing `bash -n` demotes to the next candidate.
#   * Publish happens BEFORE exec: a strictly-newer non-managed winner is
#     installed atomically (install -m 0755 to a $$-suffixed sibling, then mv)
#     under ${XDG_DATA_HOME}/soleur/hooks/, carrying lib/log-rotation.sh.
#     Equal-or-lower managed revisions are never overwritten.
#   * NEVER BLOCKS: exit 0 on every path, including total failure — a
#     `systemMessage` JSON line is emitted via jq, with a printf fallback when
#     jq is absent.
#   * `--print-resolution` prints `resolved=<path> revision=<n>` and performs
#     no publish and no exec — the read-only observability probe.
#   * Portability floor: no `timeout`, `readlink`, `stat`, `sed -i`,
#     `realpath` or namerefs — the shim runs on every host a checkout does.

set -uo pipefail

# Redirect incident telemetry into a per-suite sandbox BEFORE any case runs.
# Convention for every suite in this directory — see the helper's header.
. "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lib/test-incident-sandbox.sh"

cd "$(git rev-parse --show-toplevel)" || exit 2

SHIM=".claude/hooks/memory-backstop-resolve.sh"
export TMPDIR="${TMPDIR:-/var/tmp}"

passes=0
fails=0
skips=0

pass() { printf '  ✓ %s\n' "$1"; passes=$((passes + 1)); }
fail() { printf '  ✗ %s\n' "$1" >&2; fails=$((fails + 1)); }
skip() { printf '  ~ SKIP %s (%s)\n' "$1" "${2:-skipped}"; skips=$((skips + 1)); }

# The canonical fixture-dir assertion, byte-equal to the definition in
# plugins/soleur/test/test-helpers.sh. fixture-dir-operand-assert.test.sh
# compares every copy in the tree against that one with comments stripped —
# edit there, then re-sync here.
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}

TMPDIRS=()
teardown() {
  local d
  for d in "${TMPDIRS[@]:-}"; do
    [[ -n "$d" && -d "$d" ]] || continue
    assert_fixture_dir "$d"
    rm -rf "$d"
  done
  return 0
}
trap teardown EXIT INT TERM HUP

# One scratch root for the whole suite; per-case subtrees hang off it.
FX="$(mktemp -d -t membackstop-resolve.XXXXXXXX)" || { echo "FATAL: mktemp failed" >&2; exit 2; }
# Canonicalize once: the shim resolves the checkout candidate via cd -P/pwd -P,
# and under macOS mktemp roots traverse a symlink (/var -> /private/var) —
# comparing canonical output to the raw path would false-RED there.
FX="$(cd -P "$FX" && pwd -P)"
TMPDIRS+=("$FX")
assert_fixture_dir "$FX"

echo "memory-backstop-resolve: candidate enumeration, revision ordering, publish, exec, never-blocks"

# ---------------------------------------------------------------- helpers --

# mk_candidate <dir> <rev> [extra-body-line] — write a fixture "hook" carrying
# `BACKSTOP_REVISION=<rev>` that, when exec'd, prints the path it was invoked
# by plus the resolver's exported resolution env. The body uses printf and
# BASH_SOURCE only — builtins, so it also runs under the minimal-PATH arm.
mk_candidate() {
  local dir="$1" rev="$2" extra="${3:-}"
  assert_fixture_dir "$dir"
  mkdir -p "$dir" || return 1
  {
    printf '#!/usr/bin/env bash\n'
    printf 'BACKSTOP_REVISION=%s\n' "$rev"
    printf 'printf "executed_from=%%s resolved_from=%%s resolved_rev=%%s\\n" "${BASH_SOURCE[0]}" "${SOLEUR_BACKSTOP_RESOLVED_FROM:-}" "${SOLEUR_BACKSTOP_RESOLVED_REVISION:-}"\n'
    if [[ -n "$extra" ]]; then printf '%s\n' "$extra"; fi
  } > "$dir/memory-backstop.sh"
  chmod 0755 "$dir/memory-backstop.sh" 2>/dev/null || true
}

# stage_shim <checkout-dir> — copy the real resolver into a fixture checkout.
# The checkout candidate is $(dirname BASH_SOURCE)/memory-backstop.sh, so a
# staged copy beside a fixture hook reproduces the production shape exactly.
stage_shim() {
  local dir="$1"
  assert_fixture_dir "$dir"
  mkdir -p "$dir" || return 1
  cp "$SHIM" "$dir/memory-backstop-resolve.sh" || return 1
}

# run_case <shim> <home> <xdg> [args...] — exec the resolver in a CHILD env;
# HOME and XDG_DATA_HOME are the mechanism under test. Stdout+stderr land in
# RES_OUT, the exit status in RES_RC.
RES_OUT=""
RES_RC=0
run_case() {
  local shim="$1" home="$2" xdg="$3"; shift 3
  RES_OUT=$(HOME="$home" XDG_DATA_HOME="$xdg" bash "$shim" "$@" </dev/null 2>&1)
  RES_RC=$?
}

# expect_exec <path> <rev> <label> — the resolved copy ran, with the resolver's
# exports pointing at it, and the run exited 0.
expect_exec() {
  local want_path="$1" want_rev="$2" label="$3"
  if [[ "$RES_OUT" == *"executed_from=$want_path "* \
     && "$RES_OUT" == *"resolved_from=$want_path "* \
     && "$RES_OUT" == *"resolved_rev=$want_rev"* \
     && "$RES_RC" == 0 ]]; then
    pass "$label"
  else
    fail "$label — rc=$RES_RC out: ${RES_OUT:0:200}"
  fi
}

# ================================================================ T1: shape
if [[ ! -f "$SHIM" ]]; then
  fail "T1 $SHIM not found — the file under test is missing (repo-owned)"
  echo "RESULT: FAILED $fails (passed $passes)" >&2
  exit 1
fi

if bash -n "$SHIM" 2>/dev/null; then
  pass "T1 shim parses under bash -n"
else
  fail "T1 $SHIM has a syntax error — nothing below can run"
fi

# The resolver carries its own marker — it is the one component that cannot
# self-upgrade, so the marker is how future resolver copies order themselves.
if grep -q 'RESOLVER_REVISION=' "$SHIM"; then
  pass "T1 shim carries a RESOLVER_REVISION marker"
else
  fail "T1 $SHIM carries no RESOLVER_REVISION marker"
fi

# Source-safe: the suite may `source` the shim to reach its functions without
# triggering main or the exec.
# shellcheck source=/dev/null
if source "$SHIM" 2>/dev/null && declare -F main >/dev/null 2>&1 \
   && declare -F candidate_revision >/dev/null 2>&1 \
   && declare -F enumerate_candidates >/dev/null 2>&1; then
  pass "T1 sourcing exposes functions without executing main"
else
  fail "T1 sourcing $SHIM did not expose its functions — BASH_SOURCE==\$0 guard missing?"
fi

# ============================= T2: revision extraction is grep-only and safe
RV="$FX/rev"
assert_fixture_dir "$RV"
mkdir -p "$RV"

printf '#!/usr/bin/env bash\nBACKSTOP_REVISION=7\necho hi\n' > "$RV/r7.sh"
printf '#!/usr/bin/env bash\nreadonly BACKSTOP_REVISION=12\n' > "$RV/r12.sh"
printf '#!/usr/bin/env bash\necho no marker here\n' > "$RV/none.sh"
printf '#!/usr/bin/env bash\nBACKSTOP_REVISION=abc\n' > "$RV/nonnum.sh"
printf '#!/usr/bin/env bash\nBACKSTOP_REVISION=\n' > "$RV/empty.sh"
printf '#!/usr/bin/env bash\nBACKSTOP_REVISION=3\nBACKSTOP_REVISION=9\n' > "$RV/two.sh"
printf '#!/usr/bin/env bash\n# BACKSTOP_REVISION=99 — a decoy comment must not parse\n' > "$RV/comment.sh"
mkdir -p "$RV/adir"

check_rev() {  # <path> <want> <label>
  local got; got=$(candidate_revision "$1")
  if [[ "$got" == "$2" ]]; then
    pass "T2 revision($3) == $2"
  else
    fail "T2 revision($3) returned '$got', expected '$2'"
  fi
}

check_rev "$RV/r7.sh"     7  "plain marker"
check_rev "$RV/r12.sh"    12 "readonly-prefixed marker (the hook's own spelling)"
check_rev "$RV/none.sh"   0  "absent marker"
check_rev "$RV/nonnum.sh" 0  "non-numeric marker"
check_rev "$RV/empty.sh"  0  "empty marker"
check_rev "$RV/two.sh"    3  "first of two markers wins (grep -m1)"
check_rev "$RV/comment.sh" 0 "commented marker decoy does not parse (line-anchored regex)"
check_rev "$RV/missing.sh" 0 "missing file"
check_rev "$RV/adir"      0  "directory is not a candidate"

# The resolver must never run candidate code to learn the version. Check CODE
# lines only — comments are allowed to name the forbidden verbs (and do).
code_lines=$(grep -vE '^[[:space:]]*#' "$SHIM")
if grep -nE '(^|[[:space:];&|{}])(source|eval)[[:space:]]' <<<"$code_lines" >/dev/null 2>&1; then
  fail "T2 shim sources or evals code — ADR-156 violation:"
  grep -nE '(^|[[:space:];&|{}])(source|eval)[[:space:]]' <<<"$code_lines" | head -5 >&2
else
  pass "T2 shim never sources or evals anything"
fi
if grep -nE '(^|[[:space:];&|{}])\.[[:space:]]' <<<"$code_lines" >/dev/null 2>&1; then
  fail "T2 shim dot-sources a file — ADR-156 violation:"
  grep -nE '(^|[[:space:];&|{}])\.[[:space:]]' <<<"$code_lines" | head -5 >&2
else
  pass "T2 shim never dot-sources anything"
fi

# Portability floor — the shim runs on every host a checkout does, incl. macOS.
if grep -nE '\b(timeout|readlink|stat|realpath|mapfile|sed)\b|local +-n' <<<"$code_lines" >/dev/null 2>&1; then
  fail "T2 shim uses a non-portable primitive (timeout/readlink/stat/realpath/mapfile/sed/local -n):"
  grep -nE '\b(timeout|readlink|stat|realpath|mapfile|sed)\b|local +-n' <<<"$code_lines" | head -5 >&2
else
  pass "T2 shim stays inside the portability floor"
fi

# ============================================ T3: enumeration order and shape
E="$FX/enum"
assert_fixture_dir "$E"
mkdir -p "$E/checkout" "$E/home" "$E/xdg"
stage_shim "$E/checkout"

# Bare layout: only a checkout exists. The managed path is still ENUMERATED
# (a candidate, not yet a file); the globs match nothing and contribute zero
# lines. Order: checkout first — precedence order is the tie-break order.
enum_out=$(HOME="$E/home" XDG_DATA_HOME="$E/xdg" \
  bash -c 'source "$1"; enumerate_candidates' _ "$E/checkout/memory-backstop-resolve.sh" 2>/dev/null)
enum_co="$(cd -P "$E/checkout" && pwd -P)/memory-backstop.sh"
enum_want="${enum_co}
$E/xdg/soleur/hooks/memory-backstop.sh"
if [[ "$enum_out" == "$enum_want" ]]; then
  pass "T3 enumeration order: checkout then managed, in that order"
else
  fail "T3 enumeration mismatch: got $(printf '%s' "$enum_out" | tr '\n' '|')"
fi

# Both plugin caches appear after the managed path, each existing glob match
# contributing exactly one line.
mk_candidate "$E/home/.claude/plugins/cache/mkt/soleur/1.0.0/hooks" 5
mk_candidate "$E/home/.local/share/devin/cli/plugins/cache/soleur-slug/0.0.0/hooks" 7
enum_out=$(HOME="$E/home" XDG_DATA_HOME="$E/xdg" \
  bash -c 'source "$1"; enumerate_candidates' _ "$E/checkout/memory-backstop-resolve.sh" 2>/dev/null)
enum_want="${enum_want}
$E/home/.claude/plugins/cache/mkt/soleur/1.0.0/hooks/memory-backstop.sh
$E/home/.local/share/devin/cli/plugins/cache/soleur-slug/0.0.0/hooks/memory-backstop.sh"
if [[ "$enum_out" == "$enum_want" ]]; then
  pass "T3 both plugin-cache glob families enumerate after the managed path"
else
  fail "T3 plugin-cache enumeration mismatch: got $(printf '%s' "$enum_out" | tr '\n' '|')"
fi

# Anchor check: a namesake file under a NON-soleur cache path is NOT a
# candidate — the caches are plugin-namespaced, and a foreign plugin's
# identically-named file must never enter selection (PR #9241 review). A
# rev-99 file at a matching shape but foreign path must be invisible.
mk_candidate "$E/home/.claude/plugins/cache/mkt/otherplug/9.9.9/hooks" 99
mk_candidate "$E/home/.local/share/devin/cli/plugins/cache/foreignslug/9.9.9/hooks" 99
enum_out=$(HOME="$E/home" XDG_DATA_HOME="$E/xdg" \
  bash -c 'source "$1"; enumerate_candidates' _ "$E/checkout/memory-backstop-resolve.sh" 2>/dev/null)
if [[ "$enum_out" == "$enum_want" ]]; then
  pass "T3 non-soleur cache paths are not enumerated (foreign namesakes excluded)"
else
  fail "T3 a non-soleur namesake leaked into candidates: $(printf '%s' "$enum_out" | tr '\n' '|')"
fi

# Ancestor-trap: when the fixture's scratch root itself contains "soleur"
# (CI runs under soleur-run.*), a full-path match would admit EVERY cache
# entry. The check must compare the path AFTER the cache root only.
A="$FX/soleur-tainted/enum"; mkdir -p "$A/checkout" "$A/home" "$A/xdg"
stage_shim "$A/checkout"
mk_candidate "$A/home/.claude/plugins/cache/mkt/otherplug/9.9.9/hooks" 99
mk_candidate "$A/home/.claude/plugins/cache/mkt/soleur/1.0.0/hooks" 7
mk_candidate "$A/home/.local/share/devin/cli/plugins/cache/foreignslug/9.9.9/hooks" 99
mk_candidate "$A/home/.local/share/devin/cli/plugins/cache/soleur-slug/0.0.0/hooks" 5
a_out=$(HOME="$A/home" XDG_DATA_HOME="$A/xdg" \
  bash -c 'source "$1"; enumerate_candidates' _ "$A/checkout/memory-backstop-resolve.sh" 2>/dev/null)
if [[ "$a_out" != *otherplug* && "$a_out" != *foreignslug* \
   && "$a_out" == *soleur/1.0.0* && "$a_out" == *soleur-slug* ]]; then
  pass "T3 a *soleur* ancestor dir does not admit foreign plugins (check is post-cache-root)"
else
  fail "T3 ancestor-trap leak: $(printf '%s' "$a_out" | tr '\n' '|')"
fi

# XDG_DATA_HOME empty falls back to $HOME/.local/share; both unset leaves only
# the checkout candidate.
enum_out=$(HOME="$E/home" XDG_DATA_HOME="" \
  bash -c 'source "$1"; enumerate_candidates' _ "$E/checkout/memory-backstop-resolve.sh" 2>/dev/null)
if [[ "$enum_out" == *"$E/home/.local/share/soleur/hooks/memory-backstop.sh"* ]]; then
  pass "T3 empty XDG_DATA_HOME falls back to HOME/.local/share"
else
  fail "T3 empty-XDG fallback missing the HOME-based managed path: $(printf '%s' "$enum_out" | tr '\n' '|')"
fi
enum_out=$(env -u HOME -u XDG_DATA_HOME \
  bash -c 'source "$1"; enumerate_candidates' _ "$E/checkout/memory-backstop-resolve.sh" 2>/dev/null)
if [[ "$enum_out" == "$enum_co" ]]; then
  pass "T3 absent HOME and XDG_DATA_HOME leaves only the checkout candidate"
else
  fail "T3 absent-HOME enumeration leaked extra candidates: $(printf '%s' "$enum_out" | tr '\n' '|')"
fi

# ============================== T4: selection — precedence, order, demotion
# A: managed beats checkout when strictly newer.
A="$FX/sel-a"; mkdir -p "$A/checkout" "$A/home" "$A/xdg"
stage_shim "$A/checkout"; mk_candidate "$A/checkout" 1
mk_candidate "$A/xdg/soleur/hooks" 3
run_case "$A/checkout/memory-backstop-resolve.sh" "$A/home" "$A/xdg"
expect_exec "$A/xdg/soleur/hooks/memory-backstop.sh" 3 "T4 managed rev3 beats checkout rev1"

# B: a plugin-cache copy beats both, and self-publishes to managed.
B="$FX/sel-b"; mkdir -p "$B/checkout" "$B/home" "$B/xdg"
stage_shim "$B/checkout"; mk_candidate "$B/checkout" 1
mk_candidate "$B/xdg/soleur/hooks" 3
mk_candidate "$B/home/.claude/plugins/cache/mkt/soleur/2.0.0/hooks" 5
run_case "$B/checkout/memory-backstop-resolve.sh" "$B/home" "$B/xdg"
expect_exec "$B/home/.claude/plugins/cache/mkt/soleur/2.0.0/hooks/memory-backstop.sh" 5 \
  "T4 plugin-cache rev5 beats managed rev3 and checkout rev1"
if [[ -f "$B/xdg/soleur/hooks/memory-backstop.sh" ]] \
   && cmp -s "$B/xdg/soleur/hooks/memory-backstop.sh" \
             "$B/home/.claude/plugins/cache/mkt/soleur/2.0.0/hooks/memory-backstop.sh"; then
  pass "T4 winner self-published to the managed path"
else
  fail "T4 managed path was not populated with the winning copy"
fi
# A second session on a STALE checkout (rev1) now resolves the managed copy —
# that is the whole point of the publish: one fresh run upgrades the host.
B2="$FX/sel-b2"; mkdir -p "$B2/checkout"
stage_shim "$B2/checkout"; mk_candidate "$B2/checkout" 1
run_case "$B2/checkout/memory-backstop-resolve.sh" "$B/home" "$B/xdg"
expect_exec "$B/xdg/soleur/hooks/memory-backstop.sh" 5 \
  "T4 a stale checkout's second run resolves the published managed copy"

# C: equal revisions — checkout wins the tie (dev flow), and publish does NOT
# fire because the winner is not strictly newer than managed.
C="$FX/sel-c"; mkdir -p "$C/checkout" "$C/home" "$C/xdg"
stage_shim "$C/checkout"; mk_candidate "$C/checkout" 4
mk_candidate "$C/xdg/soleur/hooks" 4
printf '# sentinel — the managed copy must not be overwritten on a tie\n' \
  >> "$C/xdg/soleur/hooks/memory-backstop.sh"
run_case "$C/checkout/memory-backstop-resolve.sh" "$C/home" "$C/xdg"
expect_exec "$C/checkout/memory-backstop.sh" 4 "T4 equal revisions resolve to the checkout copy"
if grep -q 'sentinel' "$C/xdg/soleur/hooks/memory-backstop.sh"; then
  pass "T4 tie did not republish over the equally-versioned managed copy"
else
  fail "T4 managed copy was overwritten on an equal-revision tie"
fi

# D: managed beats a plugin cache on a tie — managed precedes the caches in
# precedence order.
D="$FX/sel-d"; mkdir -p "$D/checkout" "$D/home" "$D/xdg"
stage_shim "$D/checkout"; mk_candidate "$D/checkout" 1
mk_candidate "$D/xdg/soleur/hooks" 4
mk_candidate "$D/home/.local/share/devin/cli/plugins/cache/soleur-slug/0.0.0/hooks" 4
run_case "$D/checkout/memory-backstop-resolve.sh" "$D/home" "$D/xdg"
expect_exec "$D/xdg/soleur/hooks/memory-backstop.sh" 4 \
  "T4 managed wins the tie over a plugin-cache copy at the same revision"

# E: bash -n demotion — the newest candidate is syntactically broken, so the
# resolver falls to the next-highest and still execs.
G="$FX/sel-g"; mkdir -p "$G/checkout" "$G/home" "$G/xdg/soleur/hooks"
stage_shim "$G/checkout"; mk_candidate "$G/checkout" 2
# Poisoned managed copy: valid marker, invalid syntax (truncated mid-write).
printf '#!/usr/bin/env bash\nBACKSTOP_REVISION=9\necho "unterminated\n' \
  > "$G/xdg/soleur/hooks/memory-backstop.sh"
mk_candidate "$G/home/.local/share/devin/cli/plugins/cache/soleur-slug/0.0.0/hooks" 5
run_case "$G/checkout/memory-backstop-resolve.sh" "$G/home" "$G/xdg"
expect_exec "$G/home/.local/share/devin/cli/plugins/cache/soleur-slug/0.0.0/hooks/memory-backstop.sh" 5 \
  "T4 a bash -n-failing rev9 demotes to the devin-cache rev5"
# A bash -n-BROKEN managed copy counts as revision 0 for the publish
# predicate (publish_managed_rev): it can never exec, so it must not veto
# publishes — the working rev5 winner replaces it outright. A marker-reading
# veto here would starve every future publish on the host (PR #9241 review).
if grep -q 'unterminated' "$G/xdg/soleur/hooks/memory-backstop.sh"; then
  fail "T4 the syntax-broken managed copy vetoed the publish — it should have been replaced"
else
  pass "T4 the syntax-broken managed copy was replaced by the working winner"
fi

# Multi-demotion: TWO broken candidates ahead of the working one. A while→if
# refactor would demote once and exec nothing (or exec the second broken
# copy) — invisible to single-demotion arms.
G2="$FX/sel-g2"; mkdir -p "$G2/checkout" "$G2/home" "$G2/xdg/soleur/hooks"
stage_shim "$G2/checkout"; mk_candidate "$G2/checkout" 5
printf '#!/usr/bin/env bash\nBACKSTOP_REVISION=9\necho "unterminated\n' \
  > "$G2/xdg/soleur/hooks/memory-backstop.sh"
printf '#!/usr/bin/env bash\nBACKSTOP_REVISION=8\necho "unterminated\n' \
  > "$G2/home/.local/share/devin/cli/plugins/cache/soleur-slug/hooks.tmp"
mkdir -p "$G2/home/.local/share/devin/cli/plugins/cache/soleur-slug/9.9.9/hooks"
mv "$G2/home/.local/share/devin/cli/plugins/cache/soleur-slug/hooks.tmp" \
   "$G2/home/.local/share/devin/cli/plugins/cache/soleur-slug/9.9.9/hooks/memory-backstop.sh"
run_case "$G2/checkout/memory-backstop-resolve.sh" "$G2/home" "$G2/xdg"
expect_exec "$G2/checkout/memory-backstop.sh" 5 \
  "T4 two broken higher-rev candidates both demote to the working rev5"

# =============================================== T5: publish semantics
# Atomicity contract: install -m 0755 to a tmp sibling, then mv; the managed
# copy carries mode 0755 and the hook's lib/log-rotation.sh rides along when
# the winner's own lib/ has it.
P="$FX/pub"; mkdir -p "$P/checkout/lib" "$P/home" "$P/xdg"
stage_shim "$P/checkout"; mk_candidate "$P/checkout" 6
printf '#!/usr/bin/env bash\nrotate_if_needed() { :; }\n' > "$P/checkout/lib/log-rotation.sh"
run_case "$P/checkout/memory-backstop-resolve.sh" "$P/home" "$P/xdg"
if [[ -f "$P/xdg/soleur/hooks/memory-backstop.sh" ]] \
   && cmp -s "$P/xdg/soleur/hooks/memory-backstop.sh" "$P/checkout/memory-backstop.sh"; then
  pass "T5 newer checkout published to managed before exec"
else
  fail "T5 publish did not install the checkout copy at the managed path"
fi
if [[ -n "$(find "$P/xdg/soleur/hooks/memory-backstop.sh" -maxdepth 0 -perm 0755 2>/dev/null)" ]]; then
  pass "T5 published managed copy is mode 0755"
else
  fail "T5 published managed copy is not mode 0755"
fi
if [[ -f "$P/xdg/soleur/hooks/lib/log-rotation.sh" ]] \
   && cmp -s "$P/xdg/soleur/hooks/lib/log-rotation.sh" "$P/checkout/lib/log-rotation.sh"; then
  pass "T5 publish carried the winner's lib/log-rotation.sh"
else
  fail "T5 lib/log-rotation.sh was not carried into the managed hooks dir"
fi
# A winner with NO lib still gets the managed lib/ directory created (the hook
# sources it opportunistically; absence is not an error) but no lib file.
P2="$FX/pub-nolib"; mkdir -p "$P2/checkout" "$P2/home" "$P2/xdg"
stage_shim "$P2/checkout"; mk_candidate "$P2/checkout" 6
run_case "$P2/checkout/memory-backstop-resolve.sh" "$P2/home" "$P2/xdg"
if [[ -d "$P2/xdg/soleur/hooks/lib" && ! -f "$P2/xdg/soleur/hooks/lib/log-rotation.sh" ]]; then
  pass "T5 managed lib/ created empty when the winner carries none"
else
  fail "T5 managed lib/ state wrong (dir: $([[ -d "$P2/xdg/soleur/hooks/lib" ]] && echo yes || echo no), file: $([[ -f "$P2/xdg/soleur/hooks/lib/log-rotation.sh" ]] && echo yes || echo no))"
fi

# Publish BEFORE exec: a winner that exits non-zero still leaves its copy
# installed — a crashing hook cannot strand the upgrade.
P3="$FX/pub-crash"; mkdir -p "$P3/checkout" "$P3/home" "$P3/xdg"
stage_shim "$P3/checkout"; mk_candidate "$P3/checkout" 8 "exit 7"
run_case "$P3/checkout/memory-backstop-resolve.sh" "$P3/home" "$P3/xdg"
if [[ -f "$P3/xdg/soleur/hooks/memory-backstop.sh" ]] \
   && cmp -s "$P3/xdg/soleur/hooks/memory-backstop.sh" "$P3/checkout/memory-backstop.sh"; then
  pass "T5 publish landed before the exec'd winner exited non-zero"
else
  fail "T5 a failing winner blocked its own publish (ordering violation)"
fi

# Serialization: four concurrent resolvers against an empty managed dir
# converge on the same published copy — flock-guarded where flock exists.
have_flock=0
command -v flock >/dev/null 2>&1 && have_flock=1
P4="$FX/pub-race"; mkdir -p "$P4/checkout" "$P4/home" "$P4/xdg"
stage_shim "$P4/checkout"; mk_candidate "$P4/checkout" 6
pids=""
for i in 1 2 3 4; do
  ( HOME="$P4/home" XDG_DATA_HOME="$P4/xdg" \
      bash "$P4/checkout/memory-backstop-resolve.sh" </dev/null >"$P4/out.$i" 2>&1 ) &
  pids="$pids $!"
done
race_rc=0
for p in $pids; do wait "$p" || race_rc=1; done
race_ok=1
for i in 1 2 3 4; do
  grep -q 'executed_from=' "$P4/out.$i" 2>/dev/null || race_ok=0
done
if [[ "$race_rc" == 0 && "$race_ok" == 1 ]] \
   && [[ -f "$P4/xdg/soleur/hooks/memory-backstop.sh" ]] \
   && cmp -s "$P4/xdg/soleur/hooks/memory-backstop.sh" "$P4/checkout/memory-backstop.sh"; then
  pass "T5 four concurrent publishers converged on one managed copy (flock-serialized: $have_flock)"
else
  fail "T5 concurrent publish did not converge (rc=$race_rc ok=$race_ok)"
fi
# Structural pins for the serialization shape (the mechanism, not just the
# outcome): a .publish.lock target, a command -v-guarded flock, and a managed
# revision re-read AFTER the pre-check (TOCTOU).
if grep -q '\.publish\.lock' "$SHIM" && grep -q 'command -v flock' "$SHIM"; then
  pass "T5 publish is serialized under .publish.lock with a command -v-guarded flock"
else
  fail "T5 publish lacks the flock/.publish.lock serialization"
fi
# Ordering, not count: a `publish_managed_rev` call AFTER the `flock -w` line
# is the in-lock re-read — a count of two would also pass if both calls sat
# outside the lock.
flock_ln=$(grep -n 'flock -w ' "$SHIM" | head -1 | cut -d: -f1)
inlock_ln=$(grep -n 'publish_managed_rev "\$managed"' "$SHIM" \
  | awk -F: -v l="${flock_ln:-0}" '$1 > l {print $1}' | head -1)
if [[ -n "${flock_ln:-}" && -n "${inlock_ln:-}" ]]; then
  pass "T5 the managed revision is re-read INSIDE the publish lock (line $inlock_ln after flock at $flock_ln)"
else
  fail "T5 no publish-time re-read inside the lock — TOCTOU re-check missing"
fi

# An unwritable publish target must not block exec.
P5="$FX/pub-readonly"; mkdir -p "$P5/checkout" "$P5/home" "$P5/xdg/soleur/hooks"
stage_shim "$P5/checkout"; mk_candidate "$P5/checkout" 5
chmod 0555 "$P5/xdg/soleur" 2>/dev/null || true
run_case "$P5/checkout/memory-backstop-resolve.sh" "$P5/home" "$P5/xdg"
if [[ "$RES_RC" == 0 && "$RES_OUT" == *"executed_from="* ]]; then
  pass "T5 an unwritable publish target still execs the winner and exits 0"
else
  fail "T5 unwritable publish target broke exec (rc=$RES_RC)"
fi
if [[ "$EUID" -ne 0 ]]; then
  if [[ ! -f "$P5/xdg/soleur/hooks/memory-backstop.sh" ]]; then
    pass "T5 unwritable managed dir left no installed copy"
  else
    fail "T5 publish wrote into a 0555 directory — the failure was not contained"
  fi
else
  skip "T5 0555-dir publish refusal" "running as root — mode bits do not bind"
fi
chmod 0755 "$P5/xdg/soleur" 2>/dev/null || true   # restore so teardown can rm -rf

# =============================================== T6: never blocks, exit 0
# No candidates at all — a staged shim in a bare dir, empty fixture home.
N="$FX/none"; mkdir -p "$N/checkout" "$N/home" "$N/xdg"
stage_shim "$N/checkout"
run_case "$N/checkout/memory-backstop-resolve.sh" "$N/home" "$N/xdg"
if [[ "$RES_RC" == 0 && "$RES_OUT" == *'"systemMessage"'* ]]; then
  pass "T6 zero candidates exits 0 with a systemMessage line"
else
  fail "T6 zero candidates: rc=$RES_RC out: ${RES_OUT:0:200}"
fi

# Every candidate fails bash -n — same exit-0-plus-message contract.
N2="$FX/none-bad"; mkdir -p "$N2/checkout" "$N2/home" "$N2/xdg/soleur/hooks"
stage_shim "$N2/checkout"
printf '#!/usr/bin/env bash\nBACKSTOP_REVISION=9\necho "unterminated\n' \
  > "$N2/xdg/soleur/hooks/memory-backstop.sh"
run_case "$N2/checkout/memory-backstop-resolve.sh" "$N2/home" "$N2/xdg"
if [[ "$RES_RC" == 0 && "$RES_OUT" == *'"systemMessage"'* ]]; then
  pass "T6 all-candidates-broken exits 0 with a systemMessage line"
else
  fail "T6 all-broken: rc=$RES_RC out: ${RES_OUT:0:200}"
fi

# Absent HOME and XDG_DATA_HOME — only the checkout copy can resolve.
N3="$FX/none-home"; mkdir -p "$N3/checkout"
stage_shim "$N3/checkout"; mk_candidate "$N3/checkout" 1
N3_OUT=$(env -u HOME -u XDG_DATA_HOME bash "$N3/checkout/memory-backstop-resolve.sh" </dev/null 2>&1)
N3_RC=$?
if [[ "$N3_RC" == 0 && "$N3_OUT" == *"executed_from="* ]]; then
  pass "T6 absent HOME/XDG_DATA_HOME still resolves the checkout copy and exits 0"
else
  fail "T6 absent HOME: rc=$N3_RC out: ${N3_OUT:0:200}"
fi

# Minimal PATH — no jq, no flock: the printf fallback must still emit a
# systemMessage, and the unlocked publish path must still exec. The fixture
# body is builtins-only so it runs here too.
M="$FX/minenv"; mkdir -p "$M/checkout" "$M/home" "$M/xdg" "$M/minbin"
stage_shim "$M/checkout"; mk_candidate "$M/checkout" 2
for t in bash grep mkdir install mv dirname rm chmod cat find cp; do
  t_path="$(command -v "$t" 2>/dev/null)" || true
  [[ -n "$t_path" ]] && ln -s "$t_path" "$M/minbin/$t" 2>/dev/null
done
M_OUT=$(env -i PATH="$M/minbin" HOME="$M/home" XDG_DATA_HOME="$M/xdg" \
  bash "$M/checkout/memory-backstop-resolve.sh" </dev/null 2>&1)
M_RC=$?
if [[ "$M_RC" == 0 && "$M_OUT" == *"executed_from="* ]]; then
  pass "T6 minimal PATH (no jq, no flock) still resolves and execs, exit 0"
else
  fail "T6 minimal PATH: rc=$M_RC out: ${M_OUT:0:200}"
fi
# The no-flock branch's EFFECT, not just its exit: the rev2 checkout is
# strictly newer than the absent managed copy, so the unlocked publish must
# have installed it.
if cmp -s "$M/xdg/soleur/hooks/memory-backstop.sh" "$M/checkout/memory-backstop.sh"; then
  pass "T6 no-flock publish path still installs the managed copy"
else
  fail "T6 no-flock publish did not land the managed copy"
fi
# Same minimal PATH, total failure — exercises the no-jq printf fallback.
M2="$FX/minenv-fail"; mkdir -p "$M2/checkout" "$M2/home" "$M2/xdg"
stage_shim "$M2/checkout"
M2_OUT=$(env -i PATH="$M/minbin" HOME="$M2/home" XDG_DATA_HOME="$M2/xdg" \
  bash "$M2/checkout/memory-backstop-resolve.sh" </dev/null 2>&1)
M2_RC=$?
if [[ "$M2_RC" == 0 && "$M2_OUT" == *'"systemMessage"'* ]]; then
  pass "T6 minimal-PATH total failure emits systemMessage via the printf fallback, exit 0"
else
  fail "T6 minimal-PATH failure: rc=$M2_RC out: ${M2_OUT:0:200}"
fi

# =============================================== T7: --print-resolution
R="$FX/print"; mkdir -p "$R/checkout" "$R/home" "$R/xdg"
stage_shim "$R/checkout"; mk_candidate "$R/checkout" 4
run_case "$R/checkout/memory-backstop-resolve.sh" "$R/home" "$R/xdg" --print-resolution
if [[ "$RES_RC" == 0 && "$RES_OUT" =~ ^resolved=.+\ revision=[0-9]+\ managed=.+\ managed_rev=[0-9-]+$ ]]; then
  pass "T7 --print-resolution emits 'resolved=<path> revision=<n> managed=<path> managed_rev=<n>'"
else
  fail "T7 --print-resolution shape: rc=$RES_RC out: ${RES_OUT:0:200}"
fi
# Read-only: no exec (no executed_from line) and NO publish — even though the
# checkout copy is strictly newer than the absent managed copy.
if [[ "$RES_OUT" != *"executed_from="* && ! -f "$R/xdg/soleur/hooks/memory-backstop.sh" ]]; then
  pass "T7 --print-resolution is read-only: no exec, no publish"
else
  fail "T7 --print-resolution had side effects (exec line or managed write)"
fi
# Print mode on total failure still exits 0 through the systemMessage path.
R2="$FX/print-none"; mkdir -p "$R2/checkout" "$R2/home" "$R2/xdg"
stage_shim "$R2/checkout"
run_case "$R2/checkout/memory-backstop-resolve.sh" "$R2/home" "$R2/xdg" --print-resolution
if [[ "$RES_RC" == 0 && "$RES_OUT" == *'"systemMessage"'* ]]; then
  pass "T7 --print-resolution on zero candidates exits 0 with a message"
else
  fail "T7 print-mode failure: rc=$RES_RC out: ${RES_OUT:0:200}"
fi

# Discoverability probe on the REAL shim (the plan's observability contract):
# read-only, so safe to run here — a fixture env keeps it off the real HOME.
PR="$FX/print-real"; mkdir -p "$PR/home" "$PR/xdg"
PR_OUT=$(HOME="$PR/home" XDG_DATA_HOME="$PR/xdg" \
  bash "$SHIM" --print-resolution </dev/null 2>&1)
PR_RC=$?
if [[ "$PR_RC" == 0 && "$PR_OUT" =~ ^resolved=.*/\.claude/hooks/memory-backstop\.sh\ revision=[0-9]+\ managed= ]]; then
  pass "T7 real shim --print-resolution resolves the checkout copy read-only"
else
  fail "T7 real-shim probe: rc=$PR_RC out: ${PR_OUT:0:200}"
fi
if [[ ! -f "$PR/xdg/soleur/hooks/memory-backstop.sh" ]]; then
  pass "T7 real-shim probe performed no publish"
else
  fail "T7 real-shim probe PUBLISHED — --print-resolution must be read-only"
fi

# Structural pins: the pieces a regression could remove while keeping the
# happy-path tests green.
if grep -q 'exec bash ' "$SHIM"; then
  pass "T7 exec is bash-prefixed (mode-bit immunity, #7151)"
else
  fail "T7 winner is not exec'd via 'bash <path>'"
fi
for v in SOLEUR_BACKSTOP_RESOLVED_FROM SOLEUR_BACKSTOP_RESOLVED_REVISION; do
  if grep -q "$v" "$SHIM"; then
    pass "T7 shim exports $v"
  else
    fail "T7 $v never referenced — the ledger loses attribution"
  fi
done

echo
if (( fails == 0 )); then
  echo "RESULT: PASSED $passes"
  exit 0
fi
echo "RESULT: FAILED $fails (passed $passes)" >&2
exit 1
