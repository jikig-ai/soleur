#!/usr/bin/env bash
# Mutation-proven suite for plugins/soleur/skills/ship/scripts/prepush-secret-scan.sh (P4a of #10924).
#
# The script scans the non-merge commits of origin/main..HEAD with gitleaks BEFORE a push. Its contract
# (exit 0 CLEAN / 1 FINDINGS / 43 NOT_RUN, everything else a STOP) is what the ship skill branches on, so
# this suite pins three things at once: the VERDICT for known answers (real gitleaks, real git), the
# EXIT CODE for every way the scan can fail to run (argv-strict PATH stubs), and the WIRING (the call
# in SKILL.md precedes the push; the range string equals CI's range arm).
#
# Layering. "stub" arms need no gitleaks and always run; "real" arms drive the pinned binary and are
# per-arm skips locally with the cause named, but FAIL the suite under CI=true (ADR-188: a guard that
# can silently disarm must fail in CI). PASS counts stub arms only, so a locally skipped real arm can
# never lower the anti-vacuity floor below its contract.
#
# Mutation matrix (a mutant is a copy of the script with ONE literal edited; a row passes when the
# known-answer assertion it targets would FAIL against the mutant):
#   M1 range -> HEAD..HEAD          M2 gitleaks call -> `true`; missing report -> CLEAN
#   M3 summary keeps 1 finding      M4 colour pins removed (params only / count only / both)
#   M6a `-m` replaces --no-merges   M6b --no-merges dropped (caught by the CI-parity pin only)
#   M5 (REORDER) lives in the SKILL.md section. Measured-equivalent mutants are RECORDED, not asserted
#   green: dropping `--config` (gitleaks auto-discovers .gitleaks.toml from the repo it scans) and
#   dropping the --base regex (the SHA resolution that follows rejects the same inputs).
#
# Synthesized secrets only (cq-test-fixtures-synthesized-only), assembled at runtime from split
# arguments: this path is scanned by CI's own secret scan, so a contiguous secret literal would trip it.
# Run via:  bash plugins/soleur/test/ship-prepush-secret-scan.test.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Owning trap installed BEFORE the helper is sourced (test-helpers.sh composes over an existing EXIT trap).
trap '[[ -z "${TMP:-}" ]] || rm -rf "${TMP:?}"' EXIT
# shellcheck source=plugins/soleur/test/test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh" || { echo "FATAL: could not source $SCRIPT_DIR/test-helpers.sh" >&2; exit 2; }
# shellcheck source=plugins/soleur/test/lib/git-fixture-env.sh
source "$SCRIPT_DIR/lib/git-fixture-env.sh" || { echo "FATAL: could not source git-fixture-env.sh" >&2; exit 2; }

set +e -uo pipefail

REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SCRIPT="$REPO_ROOT/plugins/soleur/skills/ship/scripts/prepush-secret-scan.sh"
SKILL="$REPO_ROOT/plugins/soleur/skills/ship/SKILL.md"
WORKFLOW="$REPO_ROOT/.github/workflows/secret-scan.yml"
CONFIG="$REPO_ROOT/.gitleaks.toml"

# shellcheck source=plugins/soleur/test/lib/gitleaks-probe.sh
source "$SCRIPT_DIR/lib/gitleaks-probe.sh"
gl_probe

HAVE_JQ=1
command -v jq >/dev/null 2>&1 || HAVE_JQ=0

PASS=0
RPASS=0
FAIL=0
K=stub
pass() {
  echo "  pass: $1"
  PASS=$((PASS + 1))
}
rpass() {
  echo "  pass: $1"
  RPASS=$((RPASS + 1))
}
fail() {
  echo "  FAIL: $1"
  FAIL=$((FAIL + 1))
}
ok() {
  if [ "$K" = real ]; then rpass "$1"; else pass "$1"; fi
}
note() { echo "  note: $1"; }

TMP=$(mktemp -d)
mkdir -p "$TMP/w" "$TMP/td" "$TMP/mut" "$TMP/stubdir" "$TMP/links"
git_fixture_env "$TMP/w/x" || { echo "FATAL: git_fixture_env refused" >&2; exit 2; }

_needs_jq() {
  [ "$HAVE_JQ" = 1 ] && return 0
  _skip_arm "$1" "jq is not on PATH"
  return 1
}

# --- assertion helpers (each returns 0/1 and records through ok/fail) -------------------------------
want_rc() { # want_rc <label> <expected rc>   (reads $RC)
  if [ "$RC" = "$2" ]; then ok "$1 (rc=$2)"; return 0; fi
  fail "$1: want rc=$2 got rc=$RC :: $(printf '%s' "$OUTV" | tail -n 2 | tr '\n' '|') :: $(printf '%s' "$ERRV" | tail -n 2 | tr '\n' '|')"
  return 1
}
want_in() { # want_in <label> <haystack> <needle>
  case "$2" in *"$3"*) ok "$1"; return 0 ;; esac
  fail "$1: missing [$3] in [$(printf '%s' "$2" | tail -n 3 | tr '\n' '|')]"
  return 1
}
want_notin() { # want_notin <label> <haystack> <needle>
  case "$2" in *"$3"*) fail "$1: [$3] must NOT appear"; return 1 ;; esac
  ok "$1"
  return 0
}
verdict_is() { want_in "$1" "$OUTV" "verdict=$2"; }
reason_is() { want_in "$1" "$OUTV" "reason=$2"; }

# --- instrument self-test: every helper must be able to move its counter BOTH ways ------------------
_p0=$PASS
pass "instrument: pass() moves PASS"
if [ "$PASS" -ne $((_p0 + 1)) ]; then echo "FATAL: pass() did not move PASS" >&2; exit 2; fi
_f0=$FAIL
fail "instrument: fail() moves FAIL (EXPECTED — retracted below)"
if [ "$FAIL" -ne $((_f0 + 1)) ]; then echo "FATAL: fail() did not move FAIL" >&2; exit 2; fi
FAIL=$((FAIL - 1))
RC=0 OUTV=x ERRV=y
_f0=$FAIL
want_rc "instrument: want_rc must REJECT a mismatch (EXPECTED FAIL)" 9 >/dev/null
if [ "$FAIL" -ne $((_f0 + 1)) ]; then echo "FATAL: want_rc cannot fail" >&2; exit 2; fi
FAIL=$((FAIL - 1))
_f0=$FAIL
want_in "instrument: want_in must REJECT a missing needle (EXPECTED FAIL)" "abc" "zzz" >/dev/null
if [ "$FAIL" -ne $((_f0 + 1)) ]; then echo "FATAL: want_in cannot fail" >&2; exit 2; fi
FAIL=$((FAIL - 1))
_f0=$FAIL
want_notin "instrument: want_notin must REJECT a present needle (EXPECTED FAIL)" "abc" "b" >/dev/null
if [ "$FAIL" -ne $((_f0 + 1)) ]; then echo "FATAL: want_notin cannot fail" >&2; exit 2; fi
FAIL=$((FAIL - 1))

echo "== 0. the script exists and is not a stub"
if [ -f "$SCRIPT" ]; then pass "script exists"; else fail "script missing: $SCRIPT"; fi
if [ -f "$SCRIPT" ] && bash -n "$SCRIPT" 2>/dev/null; then pass "script parses (bash -n)"; else fail "script does not parse"; fi
if [ ! -f "$SCRIPT" ]; then
  echo "FATAL: nothing further can be measured without the script" >&2
  exit 1
fi

# --- fixtures ---------------------------------------------------------------------------------------
mk_pem() {
  printf -- '%s%s%s\n%s\n%s%s%s\n' '-----' 'BEGIN' ' RSA PRIVATE KEY-----' \
    "MIIEowIBAAKCAQEA$(head -c 120 /dev/urandom | base64 | tr -d '\n')" '-----' 'END' ' RSA PRIVATE KEY-----'
}
mk_sol() { printf 'sk-soleur-%s' "$(printf 'aB3x%.0s' {1..10})"; }

R=""
# mkrepo <name> — a work tree on branch feat with a pushed origin/main and the repo's own toml.
mkrepo() {
  local d="$TMP/w/$1"
  mkdir -p "$d"
  git init -q --bare "$d/origin.git"
  git init -q -b main "$d/repo"
  cp "$CONFIG" "$d/repo/.gitleaks.toml"
  printf 'base\n' >"$d/repo/README.md"
  git -C "$d/repo" add -A
  git -C "$d/repo" commit -qm base
  git -C "$d/repo" remote add origin "$d/origin.git"
  git -C "$d/repo" push -q origin main
  git -C "$d/repo" checkout -q -b feat
  R="$d/repo"
}
# addfile <relpath> <content> <msg> — writes into $R and commits.
addfile() {
  mkdir -p "$R/$(dirname "$1")"
  printf '%s\n' "$2" >"$R/$1"
  git -C "$R" add -A
  git -C "$R" commit -qm "$3"
}

# Tool links for the constructed PATH: everything the script and the stubs use, and NO gitleaks.
for _t in bash env git sed tr cut mktemp rm cat dirname basename readlink jq timeout gtimeout head tail sort awk grep sleep ls mkdir cp mv date printf; do
  _tp=$(type -P "$_t" 2>/dev/null) || _tp=""
  [ -z "$_tp" ] || ln -sf "$_tp" "$TMP/links/$_t"
done

# The stub: argv-strict (exits 64 on any shape the script is not specified to send) and driven by STUB_MODE.
cat >"$TMP/stubdir/gitleaks" <<'STUB'
#!/usr/bin/env bash
: "${STUB_LOG:=/dev/null}"
{ printf 'argv:'; printf ' %s' "$@"; printf '\n'; } >>"$STUB_LOG"
if [ "${1:-}" = version ]; then
  case "${STUB_MODE:-}" in unrunnable) exit 127 ;; esac
  echo "8.99.9"
  exit 0
fi
refuse() { printf 'stub: unexpected argv: %s\n' "$*" >>"${STUB_REFUSE:-/dev/null}"; exit 64; }
[ "$#" -eq 12 ] || refuse "$@"
[ "$1" = git ] && [ "$2" = --redact ] && [ "$3" = --no-banner ] && [ "$4" = --exit-code ] && [ "$5" = 1 ] || refuse "$@"
[ "$6" = --config ] && [ -f "$7" ] && [ "$8" = --report-format ] && [ "$9" = json ] || refuse "$@"
[ "${10}" = --report-path ] && [ -n "${11}" ] || refuse "$@"
[[ "${12}" =~ ^--log-opts=--no-merges\ [0-9a-f]{40}\.\.[0-9a-f]{40}$ ]] || refuse "$@"
printf 'env: GITLEAKS_CONFIG=%s GIT_NO_REPLACE_OBJECTS=%s GIT_DIR=%s\n' "${GITLEAKS_CONFIG-unset}" "${GIT_NO_REPLACE_OBJECTS-unset}" "${GIT_DIR-unset}" >>"$STUB_LOG"
report=${11}
say() { printf '%s\n' "${STUB_SCANLINE:-INF ${1} commits scanned.}" | sed "s/@N@/${1}/" >&2; }
case "${STUB_MODE:-clean}" in
  clean) printf '[]' >"$report"; say "${STUB_N:-1}"; exit 0 ;;
  clean-unparseable) printf '[]' >"$report"; echo "finished" >&2; exit 0 ;;
  rc1-noreport) exit 1 ;;
  rc1-zero) : >"$report"; exit 1 ;;
  rc0-noreport) exit 0 ;;
  rc1-garbage) printf 'this is not json at all' >"$report"; exit 1 ;;
  rc0-nonempty) printf '[{"RuleID":"x"}]' >"$report"; exit 0 ;;
  rc2) printf '[]' >"$report"; exit 2 ;;
  slow-clean) sleep "${STUB_SLEEP:-4}"; printf '[]' >"$report"; say "${STUB_N:-1}"; exit 0 ;;
  sleep) exec sleep 600 ;;
  *) refuse "mode:${STUB_MODE:-}" ;;
esac
STUB
chmod +x "$TMP/stubdir/gitleaks"

# The `N commits scanned.` line shape is captured from the REAL binary once, not hand-written.
SCANLINE_TEMPLATE=""
if [ "$HAVE_GITLEAKS" = 1 ]; then
  mkrepo cap
  addfile app/note.txt "plain text" "cap"
  _capline=$(cd "$R" && gl_run 60 gitleaks git --no-banner --log-opts="--no-merges $(git rev-parse refs/remotes/origin/main)..HEAD" 2>&1 >/dev/null </dev/null | sed -n '/commits scanned/p' | tail -n 1)
  SCANLINE_TEMPLATE=$(printf '%s' "$_capline" | sed -E 's/[0-9]+ commits? scanned/@N@ commits scanned/')
fi
case "$SCANLINE_TEMPLATE" in *"@N@ commits scanned"*) ;; *) SCANLINE_TEMPLATE='INF @N@ commits scanned.' ;; esac

SCAN_ARGS=(--no-fetch)
STUB_LOGF="$TMP/stub.log"
STUB_REFUSEF="$TMP/stub.refuse"
RC=0 OUTV="" ERRV=""
SCRIPT_UNDER_TEST=""
# scan <repo> [VAR=val ...] — runs the script from inside <repo>; fills RC OUTV ERRV.
scan() {
  local d=$1
  shift
  (cd "$d" && env "$@" bash "${SCRIPT_UNDER_TEST:-$SCRIPT}" ${SCAN_ARGS[@]+"${SCAN_ARGS[@]}"}) </dev/null >"$TMP/o" 2>"$TMP/e"
  RC=$?
  OUTV=$(cat "$TMP/o")
  ERRV=$(cat "$TMP/e")
}
# sscan <repo> <mode> [VAR=val ...] — the stub on a constructed PATH.
sscan() {
  local d=$1 mode=$2
  shift 2
  : >"$STUB_LOGF"
  rm -f "$STUB_REFUSEF"
  scan "$d" "PATH=$TMP/stubdir:$TMP/links" "STUB_MODE=$mode" "STUB_LOG=$STUB_LOGF" "STUB_REFUSE=$STUB_REFUSEF" \
    "STUB_SCANLINE=$SCANLINE_TEMPLATE" "TMPDIR=$TMP/td" "$@"
}

# ============================== STUB ARMS (always run) =================================================
K=stub
echo "== 1. verdicts by exit code (stub gitleaks, argv-strict)"
mkrepo st
addfile app/a.txt "benign one" "c1"
addfile app/b.txt "benign two" "c2"
ST=$R

sscan "$ST" clean STUB_N=2
want_rc "stub clean: exits 0" 0
verdict_is "stub clean: verdict CLEAN" CLEAN
want_in "stub clean: scanned parsed from the real line shape" "$OUTV" "scanned=2"
want_in "stub clean: range=2" "$OUTV" "range=2"
if [ -s "$STUB_REFUSEF" ]; then fail "stub refused the script's argv: $(cat "$STUB_REFUSEF")"; else pass "pristine run: the argv-strict stub refused nothing"; fi
if [[ "$OUTV" =~ base=[0-9a-f]{40}\ head=[0-9a-f]{40}\  ]]; then pass "receipt carries full 40-hex base= and head="; else fail "receipt lacks full SHAs: $OUTV"; fi

sscan "$ST" clean-unparseable
want_rc "unparseable scanned line: still exits 0 (format drift must not disable the scan)" 0
want_in "unparseable scanned line: scanned=?" "$OUTV" "scanned=?"

sscan "$ST" clean STUB_N=0
want_rc "scanned=0 for a range with a patch: NOT_RUN" 43
reason_is "scanned=0: reason scanned-mismatch" scanned-mismatch
sscan "$ST" clean STUB_N=99
want_rc "scanned > range: NOT_RUN" 43
reason_is "scanned > range: reason scanned-mismatch" scanned-mismatch

for m in rc1-noreport rc1-zero rc0-noreport; do
  sscan "$ST" "$m"
  want_rc "$m: NOT_RUN (a missing or zero-byte report is never CLEAN)" 43
  reason_is "$m: reason empty-report" empty-report
done
want_in "NOT_RUN prints the PR-body line" "$OUTV" "secret-scan: not run (empty-report)"
want_in "NOT_RUN warns loudly on stderr" "$ERRV" "NOT RUN"

sscan "$ST" rc1-garbage
want_rc "rc 1 with an unparseable non-empty report: FINDINGS" 1
verdict_is "unparseable report: verdict FINDINGS" FINDINGS
sscan "$ST" rc0-nonempty
want_rc "rc 0 with a non-[] report: FINDINGS (defensive)" 1
sscan "$ST" rc2
want_rc "gitleaks rc 2: NOT_RUN" 43
reason_is "gitleaks rc 2: reason gitleaks-rc-2" gitleaks-rc-2

sscan "$ST" unrunnable
want_rc "gitleaks version exits 127: NOT_RUN" 43
reason_is "unrunnable: reason gitleaks-unrunnable" gitleaks-unrunnable
scan "$ST" "PATH=$TMP/links" "TMPDIR=$TMP/td"
want_rc "no gitleaks on PATH: NOT_RUN" 43
reason_is "absent: reason gitleaks-absent" gitleaks-absent

mkdir -p "$ST/bin"
cp "$TMP/stubdir/gitleaks" "$ST/bin/gitleaks"
scan "$ST" "PATH=$ST/bin:$TMP/links" "STUB_MODE=clean" "TMPDIR=$TMP/td"
want_rc "a gitleaks that resolves inside the repo: NOT_RUN" 43
reason_is "in-repo shim: reason gitleaks-in-repo" gitleaks-in-repo
rm -rf "${ST:?}/bin"

mv "$ST/.gitleaks.toml" "$TMP/toml.hold"
sscan "$ST" clean
want_rc "no .gitleaks.toml: NOT_RUN" 43
reason_is "no toml: reason gitleaks-toml-absent" gitleaks-toml-absent
mv "$TMP/toml.hold" "$ST/.gitleaks.toml"

if [ -x "$(type -P timeout 2>/dev/null)" ] || [ -x "$(type -P gtimeout 2>/dev/null)" ]; then
  SECONDS=0
  sscan "$ST" sleep SOLEUR_PREPUSH_SCAN_TIMEOUT=2
  want_rc "a scan that outlives SOLEUR_PREPUSH_SCAN_TIMEOUT: NOT_RUN" 43
  reason_is "timeout: reason timeout" timeout
  if [ "$SECONDS" -lt 60 ]; then pass "timeout fired near its bound (${SECONDS}s)"; else fail "timeout did not bound the scan (${SECONDS}s)"; fi
  sscan "$ST" slow-clean SOLEUR_PREPUSH_SCAN_TIMEOUT=abc STUB_SLEEP=3
  want_rc "a non-integer timeout knob falls back to the default and the scan completes" 0
else
  note "SKIP timeout rows: neither timeout nor gtimeout on this host (the script degrades to unbounded)"
fi

echo "== 2. --base is a selector, never a command line"
for b in "a b" "-x" "HEAD~1" "nonexistent" "--all"; do
  SCAN_ARGS=(--no-fetch --base "$b")
  sscan "$ST" clean
  SCAN_ARGS=(--no-fetch)
  want_rc "--base [$b]: NOT_RUN" 43
  reason_is "--base [$b]: reason base-unresolvable" base-unresolvable
  if [ "$(grep -c 'argv: git ' "$STUB_LOGF")" = 0 ]; then pass "--base [$b]: no scan was started"; else fail "--base [$b]: gitleaks git was invoked"; fi
done
SCAN_ARGS=(--no-fetch --base HEAD)
sscan "$ST" clean
SCAN_ARGS=(--no-fetch)
want_rc "--base HEAD: an empty range is CLEAN, not a skip switch that hides the receipt" 0
want_in "--base HEAD: range=0" "$OUTV" "range=0"
SCAN_ARGS=(--bogus)
sscan "$ST" clean
SCAN_ARGS=(--no-fetch)
want_rc "an unknown flag is a STOP (64), never a continue" 64

echo "== 3. fetch, config visibility, environment, temp files"
git -C "$ST" remote set-url origin "$TMP/w/does-not-exist.git"
SCAN_ARGS=()
sscan "$ST" clean STUB_N=2
SCAN_ARGS=(--no-fetch)
want_rc "unreachable origin: the scan still runs" 0
want_in "unreachable origin: fetch=stale" "$OUTV" "fetch=stale"
git -C "$ST" remote set-url origin "$TMP/w/st/origin.git"
SCAN_ARGS=()
sscan "$ST" clean STUB_N=2
SCAN_ARGS=(--no-fetch)
want_in "reachable origin: fetch=ok" "$OUTV" "fetch=ok"
sscan "$ST" clean STUB_N=2
want_in "--no-fetch: fetch=skipped" "$OUTV" "fetch=skipped"
want_in "cfg_changed=0 when the range leaves the gitleaks config alone" "$OUTV" "cfg_changed=0"
printf '# allowlist note\n' >>"$ST/.gitleaks.toml"
git -C "$ST" commit -qam "touch the toml"
sscan "$ST" clean STUB_N=3
want_in "cfg_changed=1 when the range edits .gitleaks.toml" "$OUTV" "cfg_changed=1"

sscan "$ST" clean STUB_N=3 "GIT_DIR=$TMP/w/nope" "GIT_INDEX_FILE=$TMP/foreign-index" "GIT_EXTERNAL_DIFF=/bin/false" \
  "GITLEAKS_CONFIG=$TMP/w/nope.toml" "GIT_REPLACE_REF_BASE=refs/replace-evil/"
want_rc "hostile git/gitleaks environment: still the right verdict" 0
if [ ! -e "$TMP/foreign-index" ]; then pass "the foreign GIT_INDEX_FILE was never touched"; else fail "the foreign GIT_INDEX_FILE was created"; fi
want_in "GITLEAKS_* is scrubbed before the child runs" "$(cat "$STUB_LOGF")" "GITLEAKS_CONFIG=unset"
want_in "GIT_DIR is scrubbed before the child runs" "$(cat "$STUB_LOGF")" "GIT_DIR=unset"
want_in "GIT_NO_REPLACE_OBJECTS=1 reaches the child" "$(cat "$STUB_LOGF")" "GIT_NO_REPLACE_OBJECTS=1"

rm -rf "${TMP:?}/td" && mkdir -p "$TMP/td"
sscan "$ST" clean STUB_N=3
sscan "$ST" rc1-garbage
if [ -z "$(ls -A "$TMP/td")" ]; then pass "the private temp dir is removed after both a CLEAN and a FINDINGS run"; else fail "temp residue: $(ls -A "$TMP/td")"; fi

echo "== 4. shallow (hosted-ship) clone has no merge base"
mkrepo shal
addfile app/one.txt "one" "feat one"
addfile app/two.txt "two" "feat two"
git -C "$TMP/w/shal/repo" push -q origin feat
git clone -q --depth 1 --branch feat "file://$TMP/w/shal/origin.git" "$TMP/w/shal/clone" 2>/dev/null
git -C "$TMP/w/shal/clone" fetch -q --depth 1 origin main:refs/remotes/origin/main 2>/dev/null
sscan "$TMP/w/shal/clone" clean
want_rc "depth-1 clone: NOT_RUN" 43
reason_is "depth-1 clone: reason no-merge-base" no-merge-base

# ============================== REAL ARMS ==============================================================
K=real
echo "== 5. known answers (real gitleaks, the repo's own pack)"
if _needs_gl "known-answer arms"; then
  # Precondition: the fixture secrets must be found by THIS pack before any RED assertion is trusted.
  mkdir -p "$TMP/pre"
  mk_pem >"$TMP/pre/key.txt"
  mk_sol >"$TMP/pre/tok.txt"
  _pre_rc=0
  gl_run 60 gitleaks dir --no-banner --redact --exit-code 1 -c "$CONFIG" "$TMP/pre" >/dev/null 2>&1 || _pre_rc=$?
  if [ "$_pre_rc" != 1 ]; then
    echo "FATAL: the synthesized fixtures are not detected by the repo's .gitleaks.toml (rc=$_pre_rc); no RED row can be trusted" >&2
    exit 2
  fi
  rpass "precondition: both fixture secrets are detected by the repo pack"

  mkrepo kn
  KN=$R
  _pem=$(mk_pem)
  addfile app/key.txt "$_pem" "add key"
  git -C "$KN" rm -q app/key.txt
  git -C "$KN" commit -qm "remove key"
  scan "$KN" "TMPDIR=$TMP/td"
  want_rc "secret added then removed: FINDINGS" 1
  verdict_is "add-then-remove: verdict FINDINGS" FINDINGS
  want_in "the finding names the file" "$ERRV" "app/key.txt"
  want_in "the finding names the rule" "$ERRV" "private-key"
  want_notin "no secret bytes in the output" "$OUTV$ERRV" "MIIEowIBAAKCAQEA"
  want_notin "no author email in the output" "$OUTV$ERRV" "fixture@example.com"
  want_in "FINDINGS prints the remedy" "$ERRV" "git reset --soft origin/main"

  scan "$KN" "TMPDIR=$TMP/td" "GIT_CONFIG_PARAMETERS='color.diff'='always'" "GIT_EXTERNAL_DIFF=/bin/false" "GIT_INDEX_FILE=$TMP/foreign-index2"
  want_rc "hostile colour and diff environment: still FINDINGS" 1
  if [ ! -e "$TMP/foreign-index2" ]; then rpass "the foreign index file stayed untouched"; else fail "the foreign index file was created"; fi

  mkrepo sol
  addfile app/tok.txt "$(mk_sol)" "add soleur token"
  scan "$R" "TMPDIR=$TMP/td"
  want_rc "a repo-custom rule token: FINDINGS (the repo pack is in use)" 1
  want_in "the custom rule is named" "$ERRV" "soleur-byok-key"

  mkrepo two
  addfile app/clean.txt "nothing here" "clean first"
  addfile app/k1.txt "$(mk_pem)" "secret one"
  addfile app/k2.txt "$(mk_pem)" "secret two"
  scan "$R" "TMPDIR=$TMP/td"
  want_rc "two secret commits after a clean first: FINDINGS" 1
  want_in "both secret files are named" "$ERRV" "app/k1.txt"
  want_in "the second secret file is named too" "$ERRV" "app/k2.txt"

  mkrepo emp
  scan "$R" "TMPDIR=$TMP/td"
  want_rc "empty range: exits 0" 0
  want_in "empty range: range=0" "$OUTV" "range=0"
  git -C "$R" commit -q --allow-empty -m "an empty commit"
  scan "$R" "TMPDIR=$TMP/td"
  want_rc "an empty commit (no patch): exits 0" 0
  want_in "an empty commit: range=1 scanned=0" "$OUTV" "range=1"

  mkrepo ben
  head -c 2048 /dev/urandom >"$R/app.bin"
  printf 'sha256 %s\n' "$(printf 'benign' | { sha256sum 2>/dev/null || shasum -a 256; } | cut -d' ' -f1)" >"$R/hash.txt"
  git -C "$R" add -A
  git -C "$R" commit -qm "binary and hash"
  addfile app/readme.txt "plain prose" "prose"
  addfile app/more.txt "more prose" "more"
  scan "$R" "TMPDIR=$TMP/td"
  want_rc "a clean 3-commit range with a binary file and a keyword-free hash: exits 0" 0
  verdict_is "benign range: verdict CLEAN" CLEAN

  mkrepo ansi
  _bad=$(printf 'app/a\033[31mred\nbreak.txt')
  mkdir -p "$R/app"
  printf '%s\n' "$(mk_pem)" >"$R/$_bad"
  git -C "$R" add -A
  git -C "$R" commit -qm "ansi named file"
  scan "$R" "TMPDIR=$TMP/td"
  want_rc "a secret in a file with an ANSI escape and a newline in its name: FINDINGS" 1
  case "$OUTV$ERRV" in *$'\033'*) fail "an ESC byte reached the output" ;; *) rpass "no ESC byte reaches the output" ;; esac
  if [ "$(printf '%s\n' "$ERRV" | grep -c '^  finding: ')" = 1 ]; then rpass "the hostile name stays on ONE finding line"; else fail "the finding was split across lines"; fi

  mkrepo many
  for i in 1 2 3 4 5 6 7; do mk_pem >"$R/app$i.txt"; done
  git -C "$R" add -A
  git -C "$R" commit -qm "seven secrets"
  scan "$R" "TMPDIR=$TMP/td"
  want_rc "seven findings: FINDINGS" 1
  want_in "findings beyond five are summarised" "$ERRV" "and 2 more"

  rm -rf "${TMP:?}/td" && mkdir -p "$TMP/td"
  scan "$KN" "TMPDIR=$TMP/td"
  if [ -z "$(ls -A "$TMP/td")" ]; then rpass "no temp residue after a real FINDINGS run"; else fail "temp residue: $(ls -A "$TMP/td")"; fi

  echo "== 6. merge-commit-only content is a MEASURED limitation, pinned as a known answer"
  mkrepo mrg
  MG=$R
  addfile conf.txt "base" "conf base"
  git -C "$MG" checkout -q -b side
  addfile conf.txt "side" "side edit"
  git -C "$MG" checkout -q feat
  addfile conf.txt "feat" "feat edit"
  git -C "$MG" merge -q --no-commit side >/dev/null 2>&1
  printf '%s\n' "$(mk_pem)" >"$MG/conf.txt"
  git -C "$MG" add -A
  git -C "$MG" commit -qm "resolve with a secret only the merge carries"
  scan "$MG" "TMPDIR=$TMP/td"
  want_rc "a secret that exists only in a conflict-resolution merge: exits 0 (documented limitation)" 0
  _mrg_rc=0
  gl_run 60 gitleaks dir --no-banner --redact --exit-code 1 -c "$CONFIG" "$MG" >/dev/null 2>&1 || _mrg_rc=$?
  if [ "$_mrg_rc" = 1 ]; then rpass "positive control: the merge tip really contains the secret (gitleaks dir finds it)"; else fail "positive control failed (rc=$_mrg_rc): the limitation row proves nothing"; fi

  echo "== 7. mutation matrix"
  PRISTINE="$TMP/mut/pristine.sh"
  cp "$SCRIPT" "$PRISTINE"
  LIT='--log-opts="--no-merges ${BASE_SHA}..${HEAD_SHA}"'
  # lit_mutant <name> <old> <new> — literal first-occurrence replacement; the mutation must land.
  lit_mutant() {
    local name=$1 old=$2 new=$3 s
    s=$(<"$PRISTINE")
    if [[ "$s" != *"$old"* ]]; then fail "mutant $name: anchor [$old] not found in the script"; return 1; fi
    printf '%s\n' "${s/"$old"/"$new"}" >"$TMP/mut/$name.sh"
    if cmp -s "$PRISTINE" "$TMP/mut/$name.sh"; then fail "mutant $name did not land"; return 1; fi
    return 0
  }
  # caught <label> <mutant> <repo> <expected rc under the PRISTINE script> — passes when the mutant
  # no longer yields that known answer.
  caught() {
    SCRIPT_UNDER_TEST="$TMP/mut/$2.sh"
    scan "$3" "TMPDIR=$TMP/td"
    SCRIPT_UNDER_TEST=""
    if [ "$RC" != "$4" ]; then rpass "$1: the suite goes RED (rc=$RC, pristine answer was $4)"; else fail "$1: mutant SURVIVED (rc=$RC)"; fi
  }
  scan "$KN" "TMPDIR=$TMP/td"
  want_rc "mutation control: the PRISTINE script gives the known answer" 1

  if lit_mutant m1 '--no-merges ${BASE_SHA}..${HEAD_SHA}" # mut:range' '--no-merges ${HEAD_SHA}..${HEAD_SHA}" # mut:range'; then caught "M1 empty range" m1 "$KN" 1; fi
  if lit_mutant m2a '"$GLREAL" git \' 'true git \'; then caught "M2a gitleaks call replaced by true" m2a "$KN" 1; fi
  if lit_mutant m2b 'finish NOT_RUN empty-report # mut:emptyreport' 'finish CLEAN empty-report # mut:emptyreport'; then
    SCRIPT_UNDER_TEST="$TMP/mut/m2b.sh"
    sscan "$ST" rc0-noreport
    SCRIPT_UNDER_TEST=""
    if [ "$RC" != 43 ]; then pass "M2b a missing report treated as CLEAN: the stub row (must be 43) goes RED"; else fail "M2b survived"; fi
  fi
  if _needs_jq "M3 summary row" && lit_mutant m3 '.[0:5][]' '.[0:1][]'; then
    mkrepo m3r
    addfile app/c.txt "clean" "clean first"
    addfile app/k1.txt "$(mk_pem)" "secret one"
    addfile app/k2.txt "$(mk_pem)" "secret two"
    SCRIPT_UNDER_TEST="$TMP/mut/m3.sh"
    scan "$R" "TMPDIR=$TMP/td"
    SCRIPT_UNDER_TEST=""
    case "$ERRV" in *app/k1.txt*app/k2.txt* | *app/k2.txt*app/k1.txt*) fail "M3 survived: both findings still named" ;; *) rpass "M3 summary stops after the first finding: the two-commit row goes RED" ;; esac
  fi

  # M4 colour pins, three separate mutants, MEASURED under a hostile GIT_CONFIG_PARAMETERS.
  _p_line='  "GIT_CONFIG_PARAMETERS=${GIT_CONFIG_PARAMETERS:+${GIT_CONFIG_PARAMETERS} }'"'color.ui'='never' 'color.diff'='never'"'" # mut:colorparams'
  _c_line='  "GIT_CONFIG_COUNT=$((gl_cfg_n + 2))" # mut:colorcount'
  if lit_mutant m4p "$_p_line" ''; then
    SCRIPT_UNDER_TEST="$TMP/mut/m4p.sh"
    scan "$KN" "TMPDIR=$TMP/td" "GIT_CONFIG_PARAMETERS='color.diff'='always'"
    SCRIPT_UNDER_TEST=""
    if [ "$RC" != 1 ]; then rpass "M4a PARAMETERS pin removed: RED under color.diff=always (rc=$RC)"; else note "M4a PARAMETERS-pin-only mutant SURVIVED the colour fixture (measured; recorded, not asserted)"; fi
  fi
  if lit_mutant m4c "$_c_line" '  "GIT_CONFIG_COUNT=${gl_cfg_n}" # mut:colorcount'; then
    SCRIPT_UNDER_TEST="$TMP/mut/m4c.sh"
    scan "$KN" "TMPDIR=$TMP/td" "GIT_CONFIG_PARAMETERS='color.diff'='always'"
    SCRIPT_UNDER_TEST=""
    if [ "$RC" = 1 ]; then note "M4b COUNT-pin-only removal is an EQUIVALENT mutant while the PARAMETERS pin exists (measured rc=1); kept as defense in depth"; else rpass "M4b COUNT pin removed: RED (rc=$RC)"; fi
  fi
  _m4=$(<"$TMP/mut/m4p.sh")
  if [[ "$_m4" != *"$_c_line"* ]]; then fail "M4c cannot build the both-removed mutant"; else
    printf '%s\n' "${_m4/"$_c_line"/'  "GIT_CONFIG_COUNT=${gl_cfg_n}" # mut:colorcount'}" >"$TMP/mut/m4both.sh"
    SCRIPT_UNDER_TEST="$TMP/mut/m4both.sh"
    scan "$KN" "TMPDIR=$TMP/td" "GIT_CONFIG_PARAMETERS='color.diff'='always'"
    SCRIPT_UNDER_TEST=""
    if [ "$RC" != 1 ]; then rpass "M4c both colour pins removed: RED (rc=$RC)"; else fail "M4c both colour pins removed SURVIVED"; fi
  fi

  if lit_mutant m6a '--no-merges ${BASE_SHA}..${HEAD_SHA}" # mut:range' '-m ${BASE_SHA}..${HEAD_SHA}" # mut:range'; then caught "M6a -m added to the range (the merge-only row)" m6a "$MG" 0; fi
  if lit_mutant m6b '--no-merges ${BASE_SHA}..${HEAD_SHA}" # mut:range' '${BASE_SHA}..${HEAD_SHA}" # mut:range'; then
    SCRIPT_UNDER_TEST="$TMP/mut/m6b.sh"
    scan "$KN" "TMPDIR=$TMP/td"
    SCRIPT_UNDER_TEST=""
    note "M6b --no-merges dropped is behaviourally equivalent on its own (git log -p emits no diff for a merge without -m, rc=$RC); it is caught ONLY by the CI-parity pin below"
  fi

  if lit_mutant m7 '      --config "$TOP/.gitleaks.toml" \'$'\n' ''; then
    SCRIPT_UNDER_TEST="$TMP/mut/m7.sh"
    scan "$R" "TMPDIR=$TMP/td"
    SCRIPT_UNDER_TEST=""
    note "M7 --config dropped: gitleaks auto-discovers .gitleaks.toml from the repo it scans, so this is a measured EQUIVALENT mutant (rc=$RC); kept for parity with the commit hook and for cwd-independence"
  fi
  if lit_mutant m8 '[[ "$BASE_REF" =~ ^[A-Za-z0-9._/-]+$ ]] || finish NOT_RUN base-unresolvable # mut:baseregex' ': # mut:baseregex'; then
    SCAN_ARGS=(--no-fetch --base "a b")
    SCRIPT_UNDER_TEST="$TMP/mut/m8.sh"
    scan "$KN" "TMPDIR=$TMP/td"
    SCRIPT_UNDER_TEST=""
    SCAN_ARGS=(--no-fetch)
    note "M8 --base regex removed: the SHA resolution that follows still rejects [a b] (measured rc=$RC); defense in depth, only the SHA reaches --log-opts"
  fi
fi

echo "== 8. wiring: CI parity and the SKILL.md call site"
LIT='--log-opts="--no-merges ${BASE_SHA}..${HEAD_SHA}"'
parity_ok() { grep -qF -- "$LIT" "$1"; }
K=stub
if parity_ok "$WORKFLOW"; then pass "CI's range arm still scans $LIT"; else fail "secret-scan.yml no longer carries the range shape: the local scan has drifted from CI"; fi
if parity_ok "$SCRIPT"; then pass "the script scans the same range string as CI"; else fail "the script's range string differs from CI's"; fi
if [ -f "$TMP/mut/m6b.sh" ]; then
  if parity_ok "$TMP/mut/m6b.sh"; then fail "M6b survived the parity pin"; else pass "M6b --no-merges dropped: the CI-parity pin goes RED"; fi
fi

# skill_order_ok <SKILL.md copy> — within the Phase 6 block, the scan call precedes `git push -u origin BRANCH_NAME`.
# A property about ORDER: deleting the line proves nothing, so M5 below MOVES it.
skill_order_ok() {
  awk '/^## Phase 6: Push and Create PR/ { in6 = 1; next }
       /^## / { if (in6) exit }
       in6 && !p && index($0, "prepush-secret-scan.sh\"") > 0 { p = NR }
       in6 && !g && $0 == "git push -u origin BRANCH_NAME" { g = NR }
       END { if (p && g && p < g) exit 0; exit 1 }' "$1"
}
phase_block() { # phase_block <file> <heading-prefix> — the lines of one `## ` section
  awk -v h="$2" 'index($0, h) == 1 { on = 1; print; next } /^## / { if (on) exit } on { print }' "$1"
}
if skill_order_ok "$SKILL"; then pass "SKILL.md: the Phase 6 secret scan precedes the first push"; else fail "SKILL.md: the scan call is missing from Phase 6 or does not precede git push -u origin BRANCH_NAME"; fi
_p6=$(phase_block "$SKILL" "## Phase 6: Push and Create PR")
want_in "the pointer carries the runnable command" "$_p6" 'bash "${CLAUDE_PLUGIN_ROOT}/skills/ship/scripts/prepush-secret-scan.sh"'
want_in "the pointer says to check the exit code with no pipe" "$_p6" "check the exit code, no pipe"
want_in "the pointer carries the 0 / 43 / else rule" "$_p6" "0 continue; 43 append the printed"
want_in "the pointer names the unset plugin root (127)" "$_p6" "127: plugin root unset"
want_in "the pointer says to put the printed line in the PR body" "$_p6" 'append the printed `secret-scan:` line to the PR body'
want_in "the pointer says headless FINDINGS aborts" "$_p6" "Headless FINDINGS: abort, never rewrite history unasked"
_p64=$(phase_block "$SKILL" "## Phase 6.4: Unpushed-Commits Gate")
want_in "Phase 6.4 carries the pointer" "$_p64" "Phase 6's secret scan"
want_in "the Phase 6.4 enforcement tag is unchanged" "$_p64" "[skill-enforced: ship Phase 6.4 + hook ship-unpushed-commits-gate.sh]"
if [ -f "$REPO_ROOT/plugins/soleur/skills/ship/scripts/prepush-secret-scan.sh" ]; then pass "the script path named in the pointer exists"; else fail "the pointer names a script that does not exist"; fi

# M5 REORDER: move the call line after the push line in a sandbox copy; the order check must go RED.
cp "$SKILL" "$TMP/mut/skill.pristine.md"
_P=$(awk -v h="## Phase 6: Push and Create PR" 'index($0, h) == 1 { on = 1; next } /^## / { if (on) exit } on && index($0, "prepush-secret-scan.sh\"") > 0 { print NR; exit }' "$SKILL")
_G=$(awk -v h="## Phase 6: Push and Create PR" 'index($0, h) == 1 { on = 1; next } /^## / { if (on) exit } on && $0 == "git push -u origin BRANCH_NAME" { print NR; exit }' "$SKILL")
if [[ "$_P" =~ ^[0-9]+$ ]] && [[ "$_G" =~ ^[0-9]+$ ]] && [ "$_P" -lt "$_G" ]; then
  awk -v P="$_P" -v G="$_G" 'NR == P { held = $0; next } { print } NR == G { print held }' "$SKILL" >"$TMP/mut/skill.reorder.md"
  if cmp -s "$SKILL" "$TMP/mut/skill.reorder.md"; then fail "M5: the reorder did not land"; elif skill_order_ok "$TMP/mut/skill.reorder.md"; then fail "M5: REORDER survived the order check"; else pass "M5 REORDER: the call moved after the push goes RED (line $_P -> after $_G)"; fi
else
  fail "M5: could not locate the call line ($_P) and the push line ($_G) inside the Phase 6 block"
fi

# ============================== floor and reporting ====================================================
echo ""
echo "stub-arm assertions: $PASS, real-arm assertions: $RPASS, failed: $FAIL"
FLOOR=87
if [ "$PASS" -lt "$FLOOR" ]; then
  printf 'FATAL: only %s stub-arm assertions passed; floor is %s (a stub or a gutted suite)\n' "$PASS" "$FLOOR" >&2
  exit 1
fi
if [ "${#SKIPPED_ARMS[@]}" -gt 0 ]; then
  echo "SKIPPED arms: ${SKIPPED_ARMS[*]}"
  if [ "${CI:-}" = "true" ]; then
    printf 'FAIL: %s arm(s) were skipped under CI=true (ADR-188: CI installs the pinned binary, so a skip is a broken environment)\n' "${#SKIPPED_ARMS[@]}" >&2
    exit 1
  fi
fi
[ "$FAIL" -eq 0 ] || exit 1
exit 0
