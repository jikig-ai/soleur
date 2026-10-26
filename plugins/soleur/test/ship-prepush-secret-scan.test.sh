#!/usr/bin/env bash
# Mutation-proven suite for plugins/soleur/skills/ship/scripts/prepush-secret-scan.sh (P4a of #10924).
#
# The script scans the non-merge commits of origin/main..HEAD with gitleaks BEFORE a push. Its contract
# (exit 0 CLEAN / 1 FINDINGS / 43 NOT_RUN continue / 44 INCOMPLETE stop, everything else a stop) is what
# the ship skill branches on, so this suite pins three things at once: the VERDICT for known answers
# (real gitleaks, real git), the EXIT CODE for every way the scan can fail to run or to finish
# (argv-strict PATH stubs), and the WIRING (the call in SKILL.md precedes the push; the range string
# equals CI's range arm plus --text).
#
# Layering. "stub" arms need no gitleaks and always run; "real" arms drive the pinned binary and are
# per-arm skips locally with the cause named, but FAIL the suite under CI=true (ADR-188: a guard that
# can silently disarm must fail in CI). PASS counts stub arms only, so a locally skipped real arm can
# never lower the stub floor; RPASS has its own floor, enforced wherever the real arms can run.
#
# Mutation matrix (a mutant is a copy of the script with ONE literal edited; a row passes when the
# known-answer assertion it targets would FAIL against the mutant):
#   range   M1 HEAD..HEAD, M6a `-m`, M6b --no-merges dropped (CI-parity pin), M22 --text dropped
#   dispatch M2a gitleaks call -> `true`, M2b missing report -> CLEAN, M12 default verdict -> 43,
#            M14 scan-errors -> CLEAN, M15 rc<=1 accepted as CLEAN, M3 summary keeps 1 finding
#   env/argv M4 colour pins removed, M9 relative PATH kept, M10 symlink loop off, M11 resolved
#            binary run, M16 fetch refspec bare, M17 GIT_INDEX_FILE not scrubbed, M18 attribute
#            pin removed, M19 working-tree config read, M8 --base regex removed
#   M5 (REORDER) lives in the SKILL.md section. Measured-equivalent mutants are RECORDED, not
#   asserted green: dropping `--config` and dropping the COUNT-only colour pin.
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
REVIEW_SKILL="$REPO_ROOT/plugins/soleur/skills/review/SKILL.md"
HOOK="$REPO_ROOT/.claude/hooks/ship-unpushed-commits-gate.sh"
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
fail "instrument: fail() moves FAIL (EXPECTED, retracted below)" >/dev/null
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
# mkrepo <name> [notoml] — a work tree on branch feat with a pushed origin/main and (unless notoml) the
# repo's own committed toml.
mkrepo() {
  local d="$TMP/w/$1"
  mkdir -p "$d"
  git init -q --bare "$d/origin.git"
  git init -q -b main "$d/repo"
  [ "${2:-}" = notoml ] || cp "$CONFIG" "$d/repo/.gitleaks.toml"
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
for _t in bash env git sed tr cut mktemp rm cat dirname basename readlink jq timeout gtimeout head tail sort awk grep sleep ls mkdir cp mv date printf wc; do
  _tp=$(type -P "$_t" 2>/dev/null) || _tp=""
  [ -z "$_tp" ] || ln -sf "$_tp" "$TMP/links/$_t"
done

# The stub: argv-strict (exits 64 on any shape the script is not specified to send), multi-call-binary
# shaped (exits 70 unless it is run under the name `gitleaks`) and driven by STUB_MODE.
cat >"$TMP/stubdir/gitleaks" <<'STUB'
#!/usr/bin/env bash
: "${STUB_LOG:=/dev/null}"
[ "$(basename "$0")" = gitleaks ] || exit 70
{ printf 'argv:'; printf ' %s' "$@"; printf '\n'; } >>"$STUB_LOG"
if [ "${1:-}" = version ]; then
  case "${STUB_MODE:-}" in unrunnable) exit 127 ;; esac
  echo "8.99.9"
  exit 0
fi
refuse() { printf 'stub: unexpected argv: %s\n' "$*" >>"${STUB_REFUSE:-/dev/null}"; exit 64; }
[ "$#" -eq 15 ] || refuse "$@"
[ "$1" = git ] && [ "$2" = --redact ] && [ "$3" = --no-banner ] && [ "$4" = --exit-code ] && [ "$5" = 1 ] || refuse "$@"
[ "$6" = --config ] && [ -f "$7" ] && [ "$8" = --gitleaks-ignore-path ] && [ -f "$9" ] || refuse "$@"
[ "${10}" = --report-format ] && [ "${11}" = json ] && [ "${12}" = --report-path ] && [ -n "${13}" ] || refuse "$@"
[ -f "${14}/HEAD" ] && [ -d "${14}/objects" ] || refuse "$@"
[[ "${15}" =~ ^--log-opts=--no-merges\ --text\ [0-9a-f]{40}\.\.[0-9a-f]{40}$ ]] || refuse "$@"
printf 'source: %s\n' "${14}" >>"$STUB_LOG"
{
  printf 'env.GITLEAKS_CONFIG=%s\n' "${GITLEAKS_CONFIG-unset}"
  printf 'env.GIT_NO_REPLACE_OBJECTS=%s\n' "${GIT_NO_REPLACE_OBJECTS-unset}"
  printf 'env.GIT_DIR=%s\n' "${GIT_DIR-unset}"
  printf 'env.GIT_INDEX_FILE=%s\n' "${GIT_INDEX_FILE-unset}"
  printf 'env.GIT_EXTERNAL_DIFF=%s\n' "${GIT_EXTERNAL_DIFF-unset}"
  printf 'env.GIT_REPLACE_REF_BASE=%s\n' "${GIT_REPLACE_REF_BASE-unset}"
  printf 'env.GIT_WORK_TREE=%s\n' "${GIT_WORK_TREE-unset}"
  printf 'env.GIT_ATTR_SOURCE=%s\n' "${GIT_ATTR_SOURCE-unset}"
  printf 'env.GIT_CONFIG_GLOBAL=%s\n' "${GIT_CONFIG_GLOBAL-unset}"
  printf 'env.HOME=%s\n' "${HOME-unset}"
  printf 'cfgbytes: %s\n' "$(wc -c <"$7" | tr -d ' ')"
} >>"$STUB_LOG"
report=${13}
say() { printf '%s\n' "${STUB_SCANLINE:-INF ${1} commits scanned.}" | sed "s/@N@/${1}/" >&2; }
case "${STUB_MODE:-clean}" in
  clean) printf '[]' >"$report"; say "${STUB_N:-1}"; exit 0 ;;
  clean-unparseable) printf '[]' >"$report"; echo "finished" >&2; exit 0 ;;
  err-fatal) printf '[]' >"$report"; say "${STUB_N:-1}"; printf 'ERR [git] fatal: unable to read abcdef\n' >&2; exit 0 ;;
  rc1-empty) printf '[]' >"$report"; say "${STUB_N:-1}"; exit 1 ;;
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

# --- mutants: ONE literal edited in a copy of the script; the mutation must land ---------------------
PRISTINE="$TMP/mut/pristine.sh"
cp "$SCRIPT" "$PRISTINE"
# lit_mutant <name> <old> <new> — literal first-occurrence replacement.
lit_mutant() {
  local name=$1 old=$2 new=$3 s
  s=$(<"$PRISTINE")
  if [[ "$s" != *"$old"* ]]; then fail "mutant $name: anchor [$old] not found in the script"; return 1; fi
  printf '%s\n' "${s/"$old"/"$new"}" >"$TMP/mut/$name.sh"
  if cmp -s "$PRISTINE" "$TMP/mut/$name.sh"; then fail "mutant $name did not land"; return 1; fi
  if ! bash -n "$TMP/mut/$name.sh" 2>/dev/null; then fail "mutant $name does not parse (a syntax error would read as RED)"; return 1; fi
  return 0
}
# smut <label> <mutant> <repo> <mode> <expected rc under the PRISTINE script> [VAR=val ...] — the stub arm
# passes when the mutant no longer yields that known answer. A mutant that merely crashes (rc 2, 127)
# would also differ, so each caller pairs this with a pristine want_rc on the same fixture first.
smut() {
  local label=$1 m=$2 d=$3 mode=$4 want=$5
  shift 5
  SCRIPT_UNDER_TEST="$TMP/mut/$m.sh"
  sscan "$d" "$mode" "$@"
  SCRIPT_UNDER_TEST=""
  if [ "$RC" != "$want" ]; then pass "$label: the stub row goes RED (rc=$RC, pristine answer was $want)"; else fail "$label: mutant SURVIVED (rc=$RC)"; fi
}

# ============================== STUB ARMS (always run) =================================================
K=stub
echo "== 1. verdicts by exit code (stub gitleaks, argv-strict)"
mkrepo st
addfile app/a.txt "benign one" "c1"
addfile app/b.txt "benign two" "c2"
ST=$R
# Positive control for the mutant driver: an IDENTITY mutant must be reported as SURVIVED.
cp "$PRISTINE" "$TMP/mut/identity.sh"
_f0=$FAIL
smut "control: the identity mutant" identity "$ST" clean 0 STUB_N=2 >/dev/null
if [ "$FAIL" -ne $((_f0 + 1)) ]; then echo "FATAL: smut cannot report a surviving mutant" >&2; exit 2; fi
FAIL=$((FAIL - 1))
BASE_TOML_BYTES=$(git -C "$ST" show refs/remotes/origin/main:.gitleaks.toml | wc -c | tr -d ' ')

sscan "$ST" clean STUB_N=2
want_rc "stub clean: exits 0" 0
verdict_is "stub clean: verdict CLEAN" CLEAN
want_in "stub clean: scanned parsed from the real line shape" "$OUTV" "scanned=2"
want_in "stub clean: range=2" "$OUTV" "range=2"
if [ -s "$STUB_REFUSEF" ]; then fail "stub refused the script's argv: $(cat "$STUB_REFUSEF")"; else pass "pristine run: the argv-strict stub refused nothing"; fi
if [[ "$OUTV" =~ base=[0-9a-f]{40}\ head=[0-9a-f]{40}\  ]]; then pass "receipt carries full 40-hex base= and head="; else fail "receipt lacks full SHAs: $OUTV"; fi
_rline=$(printf '%s\n' "$OUTV" | tail -n 1)
if [[ "$_rline" =~ ^PREPUSH_SECRET_SCAN\ verdict=CLEAN\ base=[0-9a-f]{40}\ head=[0-9a-f]{40}\ fetch=skipped\ range=2\ scanned=2\ cfg_changed=0\ cfg=base\ published=0\ attr=(pinned|unpinned)\ gitleaks=8\.99\.9\ reason=no-findings$ ]]; then
  pass "the receipt is ONE line of the documented keys in the documented order"
else
  fail "receipt line shape drifted: $_rline"
fi
want_in "the scan read the BASE's committed config (byte count)" "$(cat "$STUB_LOGF")" "cfgbytes: $BASE_TOML_BYTES"
want_in "gitleaks is pointed at the git dir, not the work tree" "$(cat "$STUB_LOGF")" "source: $ST/.git"

sscan "$ST" clean-unparseable
want_rc "unparseable scanned line: still exits 0 (format drift must not disable the scan)" 0
want_in "unparseable scanned line: scanned=?" "$OUTV" "scanned=?"

# INCOMPLETE (44) is a STOP; every one of these can be induced by the PR's own content.
sscan "$ST" clean STUB_N=0
want_rc "scanned=0 for a range with a patch: INCOMPLETE" 44
reason_is "scanned=0: reason scanned-mismatch" scanned-mismatch
verdict_is "scanned=0: verdict INCOMPLETE" INCOMPLETE
want_in "INCOMPLETE says STOP on stderr" "$ERRV" "STOP: secret-scan INCOMPLETE"
want_notin "INCOMPLETE prints no PR-body line (it is not a continue)" "$OUTV" "secret-scan: not run"
sscan "$ST" clean STUB_N=99
want_rc "scanned > range: INCOMPLETE" 44
reason_is "scanned > range: reason scanned-mismatch" scanned-mismatch
if lit_mutant m12 '    *) final_rc=44 ;;' '    *) final_rc=43 ;;'; then smut "M12 the default verdict arm returns 43 instead of 44" m12 "$ST" clean 44 STUB_N=0; fi

for m in rc1-noreport rc1-zero rc0-noreport; do
  sscan "$ST" "$m"
  want_rc "$m: INCOMPLETE (a missing or zero-byte report is never CLEAN)" 44
  reason_is "$m: reason empty-report" empty-report
done
sscan "$ST" err-fatal STUB_N=2
want_rc "rc 0 + [] + an ERR/fatal line (an unreadable object): INCOMPLETE" 44
reason_is "err-fatal: reason scan-errors" scan-errors
if lit_mutant m14 '    finish INCOMPLETE scan-errors' '    finish CLEAN scan-errors'; then smut "M14 scan-errors treated as CLEAN" m14 "$ST" err-fatal 44 STUB_N=2; fi
sscan "$ST" rc1-empty STUB_N=2
want_rc "rc 1 with a [] report is never CLEAN" 1
if lit_mutant m15 "if [ \"\$scan_rc\" -eq 0 ] && [ \"\$REPORT\" = '[]' ]; then" "if [ \"\$scan_rc\" -le 1 ] && [ \"\$REPORT\" = '[]' ]; then"; then smut "M15 rc<=1 accepted as CLEAN" m15 "$ST" rc1-empty 1 STUB_N=2; fi
if lit_mutant m2b 'finish INCOMPLETE empty-report # mut:emptyreport' 'finish CLEAN empty-report # mut:emptyreport'; then smut "M2b a missing report treated as CLEAN" m2b "$ST" rc0-noreport 44; fi

sscan "$ST" rc1-garbage
want_rc "rc 1 with an unparseable non-empty report: FINDINGS" 1
verdict_is "unparseable report: verdict FINDINGS" FINDINGS
sscan "$ST" rc0-nonempty
want_rc "rc 0 with a non-[] report: FINDINGS (defensive)" 1
sscan "$ST" rc2
want_rc "gitleaks rc 2: INCOMPLETE" 44
reason_is "gitleaks rc 2: reason gitleaks-rc-2" gitleaks-rc-2

# NOT_RUN (43) is the ENVIRONMENT lacking something, and only that.
sscan "$ST" unrunnable
want_rc "gitleaks version exits 127: NOT_RUN" 43
reason_is "unrunnable: reason gitleaks-unrunnable" gitleaks-unrunnable
scan "$ST" "PATH=$TMP/links" "TMPDIR=$TMP/td"
want_rc "no gitleaks on PATH: NOT_RUN" 43
reason_is "absent: reason gitleaks-absent" gitleaks-absent
want_in "NOT_RUN prints the PR-body line" "$OUTV" "secret-scan: not run (gitleaks-absent)"
want_in "NOT_RUN warns loudly on stderr" "$ERRV" "NOT RUN"

mkdir -p "$ST/bin"
cp "$TMP/stubdir/gitleaks" "$ST/bin/gitleaks"
scan "$ST" "PATH=$ST/bin:$TMP/links" "STUB_MODE=clean" "TMPDIR=$TMP/td"
want_rc "a gitleaks in an in-repo PATH entry is filtered out: NOT_RUN" 43
reason_is "in-repo PATH entry: reason gitleaks-absent (the entry is dropped, not trusted)" gitleaks-absent
# A symlink OUTSIDE the repo that points INTO it is the PR-controlled-shim vector.
mkdir -p "$TMP/slink"
ln -sf "$ST/bin/gitleaks" "$TMP/slink/gitleaks"
scan "$ST" "PATH=$TMP/slink:$TMP/links" "STUB_MODE=clean" "TMPDIR=$TMP/td"
want_rc "a symlink on PATH that resolves into the repo: NOT_RUN" 43
reason_is "symlinked in-repo shim: reason gitleaks-in-repo" gitleaks-in-repo
if lit_mutant m10 'while [ -L "$_p" ]; do' 'while false; do'; then
  SCRIPT_UNDER_TEST="$TMP/mut/m10.sh"
  scan "$ST" "PATH=$TMP/slink:$TMP/links" "STUB_MODE=clean" "STUB_LOG=$STUB_LOGF" "TMPDIR=$TMP/td"
  SCRIPT_UNDER_TEST=""
  if [ "$RC" != 43 ]; then pass "M10 symlink resolution off: the symlinked-shim row goes RED (rc=$RC)"; else fail "M10 survived"; fi
fi
rm -rf "${ST:?}/bin" "${TMP:?}/slink"

# A multi-call binary (mise shim -> one binary that reads argv[0]) must be run AS FOUND, not as resolved.
mkdir -p "$TMP/mc/bin"
cp "$TMP/stubdir/gitleaks" "$TMP/mc/gitleaks-real"
ln -sf "$TMP/mc/gitleaks-real" "$TMP/mc/bin/gitleaks"
: >"$STUB_LOGF"
scan "$ST" "PATH=$TMP/mc/bin:$TMP/links" "STUB_MODE=clean" "STUB_N=2" "STUB_LOG=$STUB_LOGF" "TMPDIR=$TMP/td"
want_rc "a symlinked multi-call gitleaks outside the repo: the scan runs it as found" 0
if lit_mutant m11 '      "$GL" git \' '      "$GLREAL" git \'; then
  SCRIPT_UNDER_TEST="$TMP/mut/m11.sh"
  scan "$ST" "PATH=$TMP/mc/bin:$TMP/links" "STUB_MODE=clean" "STUB_N=2" "STUB_LOG=$STUB_LOGF" "TMPDIR=$TMP/td"
  SCRIPT_UNDER_TEST=""
  if [ "$RC" != 0 ]; then pass "M11 resolved binary run: the multi-call row goes RED (rc=$RC)"; else fail "M11 survived"; fi
fi

# The toml: neither the base nor the head has one -> NOT_RUN; a deleted/edited/broken working tree one is moot.
mkrepo nt notoml
addfile app/x.txt "benign" "x"
sscan "$R" clean
want_rc "no committed .gitleaks.toml anywhere: NOT_RUN" 43
reason_is "no toml: reason gitleaks-toml-absent" gitleaks-toml-absent
# A base WITHOUT a config never falls back to the PR's own (the PR could ship an allowlist).
mkrepo nh notoml
addfile .gitleaks.toml "$(cat "$CONFIG")" "the PR adds a config"
sscan "$R" clean STUB_N=1
want_rc "base without a toml, PR adds one: NOT_RUN, never the PR's config" 43
reason_is "no base toml: reason gitleaks-toml-absent" gitleaks-toml-absent
# A range that only DELETES (or renames) adds no lines: gitleaks scans 0 commits and that is not a mismatch.
mkrepo del
git -C "$R" rm -q README.md
git -C "$R" commit -qm "delete only"
sscan "$R" clean STUB_N=0
want_rc "a deletion-only range with scanned=0: CLEAN, not a false stop" 0
want_in "...range=1" "$OUTV" "range=1"
if lit_mutant m24 '$1 ~ /^[0-9]+$/ && $1 > 0' '$1 ~ /^[0-9]+$/ && $1 >= 0'; then smut "M24 added-lines test loosened" m24 "$R" clean 0 STUB_N=0; fi
cp "$ST/.gitleaks.toml" "$TMP/toml.hold"
printf 'garbage = [[[\n' >"$ST/.gitleaks.toml"
sscan "$ST" clean STUB_N=2
want_rc "a broken UNCOMMITTED working-tree toml does not stop the scan" 0
want_in "...which still read the BASE config (byte count)" "$(cat "$STUB_LOGF")" "cfgbytes: $BASE_TOML_BYTES"
if lit_mutant m19 '(cd "$TOP" && git show "$BASE_SHA:.gitleaks.toml")' '(cd "$TOP" && cat .gitleaks.toml)'; then
  SCRIPT_UNDER_TEST="$TMP/mut/m19.sh"
  sscan "$ST" clean STUB_N=2
  SCRIPT_UNDER_TEST=""
  case "$(cat "$STUB_LOGF")" in *"cfgbytes: $BASE_TOML_BYTES"*) fail "M19 survived: the working-tree config was never read" ;; *) pass "M19 working-tree config read: the base-config row goes RED" ;; esac
fi
cp "$TMP/toml.hold" "$ST/.gitleaks.toml"
git -C "$ST" rm -q .gitleaks.toml
git -C "$ST" commit -qm "delete the gitleaks config in the PR"
sscan "$ST" clean STUB_N=3
want_rc "a PR that DELETES the config still scans with the base's" 0
want_in "...cfg=base" "$OUTV" "cfg=base"
want_in "...cfg_changed=1" "$OUTV" "cfg_changed=1"
git -C "$ST" reset -q --hard HEAD~1

if [ -x "$(type -P timeout 2>/dev/null)" ] || [ -x "$(type -P gtimeout 2>/dev/null)" ]; then
  SECONDS=0
  sscan "$ST" sleep SOLEUR_PREPUSH_SCAN_TIMEOUT=2
  want_rc "a scan that outlives SOLEUR_PREPUSH_SCAN_TIMEOUT: INCOMPLETE, never a skip" 44
  reason_is "timeout: reason timeout" timeout
  if [ "$SECONDS" -lt 60 ]; then pass "timeout fired near its bound (${SECONDS}s)"; else fail "timeout did not bound the scan (${SECONDS}s)"; fi
  sscan "$ST" slow-clean SOLEUR_PREPUSH_SCAN_TIMEOUT=abc STUB_SLEEP=3
  want_rc "a non-integer timeout knob falls back to the default and the scan completes" 0
else
  note "SKIP timeout rows: neither timeout nor gtimeout on this host (the script degrades to unbounded)"
fi

# PATH hygiene: an empty or relative entry would run a repo-local timeout/git/jq/env as the operator.
mkdir -p "$TMP/evil"
(cd "$TMP/evil" && git init -q . 2>/dev/null)
# (a fake `git`: it is the FIRST command the script runs from the repo cwd, so no bash command hash can mask it)
_realgit=$(type -P git)
printf '#!/bin/sh\n: >"%s/PWNED"\nexec "%s" "$@"\n' "$TMP" "$_realgit" >"$ST/git"
chmod +x "$ST/git"
rm -f "$TMP/PWNED"
scan "$ST" "PATH=.:$TMP/stubdir:$TMP/links" "STUB_MODE=clean" "STUB_N=2" "STUB_LOG=$STUB_LOGF" "TMPDIR=$TMP/td"
if [ ! -e "$TMP/PWNED" ]; then pass "a relative PATH entry never ran the repo-local git"; else fail "the repo-local timeout ran as the operator"; fi
want_rc "...and the scan still completed" 0
if lit_mutant m9 '  case "$_e" in /*) _np' '  case "$_e" in *) _np'; then
  rm -f "$TMP/PWNED"
  SCRIPT_UNDER_TEST="$TMP/mut/m9.sh"
  scan "$ST" "PATH=.:$TMP/stubdir:$TMP/links" "STUB_MODE=clean" "STUB_N=2" "STUB_LOG=$STUB_LOGF" "TMPDIR=$TMP/td"
  SCRIPT_UNDER_TEST=""
  if [ -e "$TMP/PWNED" ] || [ "$RC" != 0 ]; then pass "M9 relative PATH kept: the repo-local git row goes RED (rc=$RC; the git-in-repo guard may refuse it first)"; else fail "M9 survived"; fi
fi
rm -f "$ST/git" "$TMP/PWNED"
# An ABSOLUTE PATH entry inside the repo (direnv PATH_add, node_modules/.bin) is dropped too.
mkdir -p "$ST/bin"
printf '#!/bin/sh\n: >"%s/PWNED"\nexec "%s" "$@"\n' "$TMP" "$(type -P timeout)" >"$ST/bin/timeout"
chmod +x "$ST/bin/timeout"
rm -f "$TMP/PWNED"
scan "$ST" "PATH=$ST/bin:$TMP/stubdir:$TMP/links" "STUB_MODE=clean" "STUB_N=2" "STUB_LOG=$STUB_LOGF" "TMPDIR=$TMP/td"
if [ ! -e "$TMP/PWNED" ]; then pass "an absolute in-repo PATH entry never ran the repo-local timeout"; else fail "the in-repo timeout ran as the operator"; fi
want_rc "...and the scan still completed" 0
if lit_mutant m21 '  case "$_ed/" in "$TOPREAL"/*) continue ;; esac' '  :'; then
  rm -f "$TMP/PWNED"
  SCRIPT_UNDER_TEST="$TMP/mut/m21.sh"
  scan "$ST" "PATH=$ST/bin:$TMP/stubdir:$TMP/links" "STUB_MODE=clean" "STUB_N=2" "STUB_LOG=$STUB_LOGF" "TMPDIR=$TMP/td"
  SCRIPT_UNDER_TEST=""
  if [ -e "$TMP/PWNED" ]; then pass "M21 in-repo PATH entries kept: the repo-local timeout row goes RED"; else fail "M21 survived"; fi
fi
rm -f "$ST/bin/timeout" "$TMP/PWNED"
printf '#!/bin/sh\n: >"%s/PWNED"\nexec "%s" "$@"\n' "$TMP" "$_realgit" >"$ST/bin/git"
chmod +x "$ST/bin/git"
scan "$ST" "PATH=$ST/bin:$TMP/links" "TMPDIR=$TMP/td"
want_rc "a git that lives in an in-repo PATH entry is refused before it runs" 43
reason_is "in-repo git: reason git-in-repo" git-in-repo
if [ ! -e "$TMP/PWNED" ]; then pass "...and it never ran"; else fail "the in-repo git ran"; fi
rm -rf "${ST:?}/bin" "$TMP/PWNED"

echo "== 2. --base is a selector, never a command line"
for b in "a b" "-x" "HEAD~1" "nonexistent" "--all"; do
  SCAN_ARGS=(--no-fetch --base "$b")
  sscan "$ST" clean
  SCAN_ARGS=(--no-fetch)
  want_rc "--base [$b]: NOT_RUN" 43
  reason_is "--base [$b]: reason base-unresolvable" base-unresolvable
  if [ "$(grep -c 'argv: git ' "$STUB_LOGF")" = 0 ]; then pass "--base [$b]: no scan was started"; else fail "--base [$b]: gitleaks git was invoked"; fi
done
# The regex is NOT defence in depth: `HEAD~1` resolves, so only the regex stops a narrowed scan.
if lit_mutant m8 '[[ "$BASE_REF" =~ ^[A-Za-z0-9._/-]+$ ]] || finish NOT_RUN base-unresolvable # mut:baseregex' ': # mut:baseregex'; then
  SCAN_ARGS=(--no-fetch --base "HEAD~1")
  smut "M8 --base regex removed (HEAD~1 resolves and narrows the scan)" m8 "$ST" clean 43 STUB_N=1
  SCAN_ARGS=(--no-fetch)
fi
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
want_in "...and the scan STILL read the base's config, not the edited one" "$(cat "$STUB_LOGF")" "cfgbytes: $BASE_TOML_BYTES"
git -C "$ST" reset -q --hard HEAD~1

# published=: part of the range already on origin/<branch>.
R=$ST
git -C "$ST" push -q origin feat
sscan "$ST" clean STUB_N=2
want_in "a fully pushed range: published=1" "$OUTV" "published=1"
addfile app/c.txt "benign three" "c3"
sscan "$ST" clean STUB_N=3
want_in "a partly pushed range: published=1" "$OUTV" "published=1"
git -C "$ST" reset -q --hard HEAD~1

# Single-branch (CI-style) clone: only an explicit refspec creates refs/remotes/origin/main.
mkrepo sbr
addfile app/one.txt "one" "feat one"
addfile app/two.txt "two" "feat two"
git -C "$R" push -q origin feat
git clone -q --single-branch --branch feat "file://$TMP/w/sbr/origin.git" "$TMP/w/sbr/clone" 2>/dev/null
SCAN_ARGS=()
sscan "$TMP/w/sbr/clone" clean STUB_N=2
SCAN_ARGS=(--no-fetch)
want_rc "single-branch clone: the explicit refspec makes origin/main resolvable" 0
want_in "single-branch clone: fetch=ok" "$OUTV" "fetch=ok"
if lit_mutant m16 "'+refs/heads/main:refs/remotes/origin/main'" 'main'; then
  SCAN_ARGS=()
  git -C "$TMP/w/sbr/clone" update-ref -d refs/remotes/origin/main
  smut "M16 bare 'git fetch origin main'" m16 "$TMP/w/sbr/clone" clean 0 STUB_N=2
  SCAN_ARGS=(--no-fetch)
fi

sscan "$ST" clean STUB_N=2 "GIT_DIR=$TMP/w/nope" "GIT_WORK_TREE=$TMP/w/nope" "GIT_INDEX_FILE=$TMP/foreign-index" "GIT_EXTERNAL_DIFF=/bin/false" \
  "GITLEAKS_CONFIG=$TMP/w/nope.toml" "GIT_REPLACE_REF_BASE=refs/replace-evil/" "GIT_CONFIG_GLOBAL=$TMP/nope.gitconfig" "GIT_ATTR_SOURCE=HEAD"
want_rc "hostile git/gitleaks environment: still the right verdict" 0
if [ ! -e "$TMP/foreign-index" ]; then pass "the foreign GIT_INDEX_FILE was never touched"; else fail "the foreign GIT_INDEX_FILE was created"; fi
_log=$(cat "$STUB_LOGF")
for _kv in GITLEAKS_CONFIG=unset GIT_DIR=unset GIT_WORK_TREE=unset GIT_INDEX_FILE=unset GIT_EXTERNAL_DIFF=unset GIT_REPLACE_REF_BASE=unset \
  GIT_NO_REPLACE_OBJECTS=1 GIT_ATTR_SOURCE=4b825dc642cb6eb9a060e54bf8d69288fbee4904 GIT_CONFIG_GLOBAL=/dev/null; do
  want_in "the child sees env.$_kv" "$_log" "env.$_kv"
done
want_in "HOME is passed through (a version-manager shim needs it)" "$_log" "env.HOME=$HOME"
if lit_mutant m17 'GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR' 'GIT_WORK_TREE GIT_COMMON_DIR'; then
  SCRIPT_UNDER_TEST="$TMP/mut/m17.sh"
  sscan "$ST" clean STUB_N=2 "GIT_INDEX_FILE=$TMP/foreign-index"
  SCRIPT_UNDER_TEST=""
  case "$(cat "$STUB_LOGF")" in *"env.GIT_INDEX_FILE=unset"*) fail "M17 survived: GIT_INDEX_FILE was still scrubbed" ;; *) pass "M17 GIT_INDEX_FILE left in the environment: the scrub row goes RED" ;; esac
fi
if lit_mutant m18 $'  "GIT_ATTR_SOURCE=$EMPTY_TREE"\n' ''; then
  SCRIPT_UNDER_TEST="$TMP/mut/m18.sh"
  sscan "$ST" clean STUB_N=2
  SCRIPT_UNDER_TEST=""
  case "$(cat "$STUB_LOGF")" in *"env.GIT_ATTR_SOURCE=4b825dc642cb6eb9a060e54bf8d69288fbee4904"*) fail "M18 survived: the attribute pin was still set" ;; *) pass "M18 attribute pin removed: the pin row goes RED" ;; esac
fi

rm -rf "${TMP:?}/td" && mkdir -p "$TMP/td"
sscan "$ST" clean STUB_N=2
sscan "$ST" rc1-garbage
if [ -z "$(ls -A "$TMP/td")" ]; then pass "the private temp dir is removed after both a CLEAN and a FINDINGS run"; else fail "temp residue: $(ls -A "$TMP/td")"; fi

echo "== 4. clones the scan cannot (or must not) measure"
mkrepo shal
addfile app/one.txt "one" "feat one"
addfile app/two.txt "two" "feat two"
git -C "$TMP/w/shal/repo" push -q origin feat
git clone -q --depth 1 --branch feat "file://$TMP/w/shal/origin.git" "$TMP/w/shal/clone" 2>/dev/null
git -C "$TMP/w/shal/clone" fetch -q --depth 1 origin main:refs/remotes/origin/main 2>/dev/null
sscan "$TMP/w/shal/clone" clean
want_rc "depth-1 clone: NOT_RUN (the environment is the cause)" 43
reason_is "depth-1 clone: reason no-merge-base" no-merge-base
# An orphan branch in a FULL clone is a PR-content choice, so it is a STOP.
mkrepo orp
git -C "$R" checkout -q --orphan solo
git -C "$R" rm -rfq . 2>/dev/null
printf 'unrelated\n' >"$R/f.txt"
git -C "$R" add -A
git -C "$R" commit -qm "unrelated root"
sscan "$R" clean
want_rc "an orphan branch in a full clone: INCOMPLETE" 44
reason_is "orphan branch: reason no-merge-base" no-merge-base

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
  want_in "FINDINGS prints the merge-base remedy" "$ERRV" 'git reset --soft "$(git merge-base origin/main HEAD)"'
  want_in "an unpublished finding is told no finding commit is on origin" "$ERRV" "No finding commit is on origin"
  want_in "...and that a rebased or amended branch may still have been pushed" "$ERRV" "EVER pushed"
  want_in "...and an automated agent is told to stop" "$ERRV" "If you are an automated agent: STOP"
  _attr_pinned=1
  case "$OUTV" in *"attr=pinned"*) ;; *) _attr_pinned=0 ;; esac

  scan "$KN" "TMPDIR=$TMP/td" "GIT_CONFIG_PARAMETERS='color.diff'='always'" "GIT_EXTERNAL_DIFF=/bin/false" "GIT_INDEX_FILE=$TMP/foreign-index2"
  want_rc "hostile colour and diff environment: still FINDINGS" 1
  if [ ! -e "$TMP/foreign-index2" ]; then rpass "the foreign index file stayed untouched"; else fail "the foreign index file was created"; fi
  scan "$KN" "TMPDIR=$TMP/td" "GIT_CONFIG_COUNT=1" "GIT_CONFIG_KEY_0=diff.noprefix" "GIT_CONFIG_VALUE_0=true"
  want_rc "a caller's diff.noprefix=true: still FINDINGS" 1
  want_in "...and the path keeps its first component" "$ERRV" "app/key.txt"

  # The scan reads the BASE's config: a PR that breaks, deletes or widens it cannot scan itself clean.
  mkrepo bad
  addfile app/key.txt "$(mk_pem)" "add key"
  printf '[[[[ not toml\n' >>"$R/.gitleaks.toml"
  git -C "$R" commit -qam "break the gitleaks config"
  scan "$R" "TMPDIR=$TMP/td"
  want_rc "a PR that BREAKS .gitleaks.toml: still FINDINGS (the base config is used)" 1
  want_in "...with cfg_changed=1 visible" "$OUTV" "cfg_changed=1"
  git -C "$R" rm -q .gitleaks.toml
  git -C "$R" commit -qm "delete the gitleaks config"
  scan "$R" "TMPDIR=$TMP/td"
  want_rc "a PR that DELETES .gitleaks.toml: still FINDINGS" 1
  mkrepo wid
  addfile app/key.txt "$(mk_pem)" "add key"
  printf '\n[[allowlists]]\ndescription = "widened by the PR"\npaths = [%s]\n' "'''app/key\.txt'''" >>"$R/.gitleaks.toml"
  git -C "$R" commit -qam "widen the allowlist"
  scan "$R" "TMPDIR=$TMP/td"
  want_rc "a PR that ALLOWLISTS its own secret: still FINDINGS" 1
  printf '\n# dirty\n' >>"$R/.gitleaks.toml"
  scan "$R" "TMPDIR=$TMP/td"
  want_rc "...and an uncommitted toml edit changes nothing either" 1

  # Blind spots closed by GIT_ATTR_SOURCE and --text (git >= 2.40 for the first two).
  if [ "$_attr_pinned" = 1 ]; then
    mkrepo adi
    printf '*.cfg -diff\n' >"$R/.gitattributes"
    mkdir -p "$R/app"
    mk_pem >"$R/app/s.cfg"
    git -C "$R" add -A
    git -C "$R" commit -qm "attribute plus secret"
    addfile app/ok.txt "benign" "benign"
    scan "$R" "TMPDIR=$TMP/td"
    want_rc "a committed root '-diff' attribute does not hide the secret: FINDINGS" 1
    mkrepo adj
    mkdir -p "$R/sub"
    printf '* -diff\n' >"$R/sub/.gitattributes"
    mk_pem >"$R/sub/x.txt"
    git -C "$R" add -A
    git -C "$R" commit -qm "subdir attribute plus secret"
    addfile app/ok.txt "benign" "benign"
    scan "$R" "TMPDIR=$TMP/td"
    want_rc "a committed SUBDIRECTORY '-diff' attribute does not hide the secret: FINDINGS" 1
    mkrepo adg
    printf '* -diff\n' >"$TMP/global-attrs"
    mk_pem >"$R/g.txt"
    git -C "$R" add -A
    git -C "$R" commit -qm "secret under a global -diff attributes file"
    addfile app/ok.txt "benign" "benign"
    scan "$R" "TMPDIR=$TMP/td" "GIT_CONFIG_COUNT=1" "GIT_CONFIG_KEY_0=core.attributesFile" "GIT_CONFIG_VALUE_0=$TMP/global-attrs"
    want_rc "a caller's core.attributesFile '-diff' does not hide the secret: FINDINGS" 1
  else
    note "SKIP attribute rows: git < 2.40 ignores GIT_ATTR_SOURCE (the receipt says attr=unpinned)"
  fi
  mkrepo nul
  addfile app/a.txt "benign" "benign first"
  { mk_pem; printf '\0'; } >"$R/app/nul.txt"
  git -C "$R" add -A
  git -C "$R" commit -qm "binary-detected secret"
  git -C "$R" rm -q app/nul.txt
  git -C "$R" commit -qm "delete it again"
  scan "$R" "TMPDIR=$TMP/td"
  want_rc "a secret in a NUL-containing file, deleted later: FINDINGS (--text)" 1

  # An unreadable object: gitleaks exits 0 with [] and a partial count, which must never be CLEAN.
  mkrepo ubl
  addfile app/a.txt "benign" "first"
  addfile app/k.txt "$(mk_pem)" "secret"
  addfile app/z.txt "benign two" "last"
  _blob=$(git -C "$R" rev-parse HEAD:app/k.txt)
  rm -f "$R/.git/objects/${_blob:0:2}/${_blob:2}"
  scan "$R" "TMPDIR=$TMP/td"
  case "$RC" in
    0 | 43) fail "an unreadable blob in the range must be neither CLEAN nor a continue (rc=$RC) :: $OUTV" ;;
    *) rpass "an unreadable blob in the range is a STOP (rc=$RC, never CLEAN)" ;;
  esac

  # published=1: the remedy starts with rotation.
  mkrepo pubr
  addfile app/key.txt "$(mk_pem)" "add key"
  git -C "$R" push -q origin feat
  scan "$R" "TMPDIR=$TMP/td"
  want_rc "a pushed secret: FINDINGS" 1
  want_in "a published range: published=1" "$OUTV" "published=1"
  want_in "...and the remedy says PUBLISHED / rotate first" "$ERRV" "PUBLISHED"
  want_in "...and tells the operator to look for a collaborator's commits before any force-push" "$ERRV" 'git log --oneline HEAD..origin/feat'
  want_in "...with the lease pinned to the branch" "$ERRV" 'force-with-lease=feat:'
  want_notin "...and does not claim no finding commit is on origin" "$ERRV" "No finding commit is on origin"

  # A clean first commit is on origin, the secret commit is not: the secret is NOT published.
  mkrepo prt
  addfile app/clean.txt "benign" "clean first"
  git -C "$R" push -q origin feat
  addfile app/key.txt "$(mk_pem)" "secret, unpushed"
  scan "$R" "TMPDIR=$TMP/td"
  want_rc "a clean pushed commit plus an unpushed secret commit: FINDINGS" 1
  want_in "...the range is partly published but the SECRET is not" "$ERRV" "No finding commit is on origin"
  want_notin "...so it does not tell the operator to force-push over the clean commit" "$ERRV" "force-with-lease"

  # Ranges that add no lines (deletion, rename) are not a mismatch.
  mkrepo dlr
  git -C "$R" rm -q README.md
  git -C "$R" commit -qm "delete only"
  scan "$R" "TMPDIR=$TMP/td"
  want_rc "a deletion-only range: CLEAN (gitleaks reads added lines only)" 0

  # A checked-out .gitleaksignore is controlled by the PR: it must not allowlist the PR's own secret.
  mkrepo ign
  addfile app/key.txt "$(mk_pem)" "add key"
  scan "$R" "TMPDIR=$TMP/td"
  want_rc "ignore-file fixture, before the ignore file exists: FINDINGS" 1
  _c12=$(printf '%s\n' "$ERRV" | sed -n 's/^  finding: \([0-9a-f]*\) .*/\1/p' | head -n 1)
  _ln=$(printf '%s\n' "$ERRV" | sed -n 's/^  finding: [0-9a-f]* app\/key\.txt:\([0-9]*\) .*/\1/p' | head -n 1)
  printf '%s:app/key.txt:private-key:%s\n' "$(git -C "$R" rev-parse "$_c12")" "$_ln" >"$R/.gitleaksignore"
  scan "$R" "TMPDIR=$TMP/td"
  want_rc "a work-tree .gitleaksignore that fingerprints the PR's own secret changes nothing" 1
  git -C "$R" add .gitleaksignore
  git -C "$R" commit -qm "ignore my own secret"
  scan "$R" "TMPDIR=$TMP/td"
  want_rc "...and neither does one the PR COMMITS" 1
  if lit_mutant m20 $'      "$GITCOMMON" \\\n' ''; then
    SCRIPT_UNDER_TEST="$TMP/mut/m20.sh"
    scan "$R" "TMPDIR=$TMP/td"
    SCRIPT_UNDER_TEST=""
    if [ "$RC" != 1 ]; then rpass "M20 gitleaks pointed at the work tree again: the ignore-file row goes RED (rc=$RC)"; else fail "M20 survived: the checked-out .gitleaksignore was never read"; fi
  fi

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
  want_in "an empty commit: range=1" "$OUTV" "range=1"

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

  echo "== 7. mutation matrix (real gitleaks)"
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
  # caught() owns its verdict: an IDENTITY mutant must be reported as SURVIVED.
  cp "$PRISTINE" "$TMP/mut/identity2.sh"
  _f0=$FAIL
  caught "control: the identity mutant" identity2 "$KN" 1 >/dev/null
  if [ "$FAIL" -ne $((_f0 + 1)) ]; then echo "FATAL: caught cannot report a surviving mutant" >&2; exit 2; fi
  FAIL=$((FAIL - 1))

  if lit_mutant m1 '--no-merges --text ${BASE_SHA}..${HEAD_SHA}" # mut:range' '--no-merges --text ${HEAD_SHA}..${HEAD_SHA}" # mut:range'; then caught "M1 empty range" m1 "$KN" 1; fi
  if lit_mutant m2a '      "$GL" git \' '      true git \'; then caught "M2a gitleaks call replaced by true" m2a "$KN" 1; fi
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
  _p_line='  "GIT_CONFIG_PARAMETERS=$gl_params" # mut:colorparams'
  _c_line='  "GIT_CONFIG_COUNT=$((gl_cfg_n + ${#GL_PINS[@]}))" # mut:colorcount'
  if lit_mutant m4p "$_p_line"$'\n' ''; then
    SCRIPT_UNDER_TEST="$TMP/mut/m4p.sh"
    scan "$KN" "TMPDIR=$TMP/td" "GIT_CONFIG_PARAMETERS='color.diff'='always'"
    SCRIPT_UNDER_TEST=""
    if [ "$RC" != 1 ]; then rpass "M4a PARAMETERS pin removed: RED under color.diff=always (rc=$RC)"; else fail "M4a PARAMETERS pin removed SURVIVED the hostile colour fixture"; fi
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

  if lit_mutant m6a '--no-merges --text ${BASE_SHA}..${HEAD_SHA}" # mut:range' '-m --text ${BASE_SHA}..${HEAD_SHA}" # mut:range'; then caught "M6a -m added to the range (the merge-only row)" m6a "$MG" 0; fi
  if lit_mutant m22 '--no-merges --text ${BASE_SHA}..${HEAD_SHA}" # mut:range' '--no-merges ${BASE_SHA}..${HEAD_SHA}" # mut:range'; then
    mkrepo nulm
    { mk_pem; printf '\0'; } >"$R/nul.txt"
    git -C "$R" add -A
    git -C "$R" commit -qm "binary-detected secret"
    git -C "$R" rm -q nul.txt
    git -C "$R" commit -qm "delete it again"
    caught "M22 --text dropped (a NUL-file secret deleted later)" m22 "$R" 1
  fi
  if lit_mutant m6b '--no-merges --text ${BASE_SHA}..${HEAD_SHA}" # mut:range' '--text ${BASE_SHA}..${HEAD_SHA}" # mut:range'; then
    SCRIPT_UNDER_TEST="$TMP/mut/m6b.sh"
    scan "$KN" "TMPDIR=$TMP/td"
    SCRIPT_UNDER_TEST=""
    note "M6b --no-merges dropped is behaviourally equivalent on its own (git log -p emits no diff for a merge without -m, rc=$RC); it is caught ONLY by the CI-parity pin below"
  fi

  if lit_mutant m7 $'      --config "$TMP/gitleaks.toml" \\\n' ''; then
    SCRIPT_UNDER_TEST="$TMP/mut/m7.sh"
    scan "$R" "TMPDIR=$TMP/td"
    SCRIPT_UNDER_TEST=""
    note "M7 --config dropped: gitleaks auto-discovers .gitleaks.toml from the repo it scans, so this is a measured EQUIVALENT mutant for a repo whose working tree equals its base (rc=$RC)"
  fi
fi

echo "== 8. wiring: CI parity and the SKILL.md call site"
LIT='--log-opts="--no-merges ${BASE_SHA}..${HEAD_SHA}"'
K=stub
# CI carries the range shape in BOTH its arms (pull_request and merge_group); the script carries it plus --text.
_ci_n=$(grep -cF -- "$LIT" "$WORKFLOW")
if [ "$_ci_n" -ge 2 ]; then pass "CI's range arms still scan $LIT (both arms: $_ci_n)"; else fail "secret-scan.yml carries the range shape $_ci_n time(s), want both arms: the local scan has drifted from CI"; fi
script_parity_ok() { # script_parity_ok <script> — the script's range line equals CI's plus ` --text`
  local l
  l=$(grep -F -- 'mut:range' "$1")
  [[ "${l// --text/}" == *"$LIT"* ]]
}
if script_parity_ok "$SCRIPT"; then pass "the script scans CI's range string plus --text"; else fail "the script's range string differs from CI's"; fi
if lit_mutant m6bp '--no-merges --text ${BASE_SHA}..${HEAD_SHA}" # mut:range' '--text ${BASE_SHA}..${HEAD_SHA}" # mut:range'; then
  if script_parity_ok "$TMP/mut/m6bp.sh"; then fail "M6b survived the parity pin"; else pass "M6b --no-merges dropped: the CI-parity pin goes RED"; fi
fi

# skill_order_ok <SKILL.md copy> — within the Phase 6 block, the scan call precedes `git push -u origin BRANCH_NAME`.
# A property about ORDER: deleting the line proves nothing, so M5 below MOVES it.
skill_order_ok() {
  awk '/^## Phase 6: Push and Create PR/ { in6 = 1; next }
       /^## / { if (in6) exit }
       in6 && !p && index($0, "**Secret scan — BEFORE every") == 1 { p = NR }
       in6 && !g && $0 == "git push -u origin BRANCH_NAME" { g = NR }
       END { if (p && g && p < g) exit 0; exit 1 }' "$1"
}
phase_block() { # phase_block <file> <heading-prefix> — the lines of one `## ` section
  awk -v h="$2" 'index($0, h) == 1 { on = 1; print; next } /^## / { if (on) exit } on { print }' "$1"
}
# push_sites_ok <file> <comment-regex> <expected-sites> <exempt-regex> — EVERY `git push` command line inside a
# fenced block (comment lines and the exempt line excluded) has the scan comment as the previous non-blank line,
# and the number of such sites is exactly the expected one: a new unguarded push site reds on both counts.
push_sites_ok() {
  awk -v cm="$2" -v want="$3" -v ex="$4" '
    /^ *```/ { fence = !fence; prev = ""; next }
    fence {
      if ($0 ~ /(^|[^A-Za-z-])git push( |$)/ && $0 !~ /^ *#/ && !(ex != "" && $0 ~ ex)) { sites++; if (prev !~ cm) bad++ }
      if ($0 !~ /^[[:space:]]*$/) prev = $0
    }
    END { exit (sites == want && !bad) ? 0 : 1 }' "$1"
}
# pointer_ok <file> — the exact pointer line appears once, outside any code fence and any HTML comment.
pointer_ok() {
  awk '/^ *```/ { fence = !fence; next }
       { line = $0
         if (incom) { if (index(line, "-->")) incom = 0; next }
         if (index(line, "<!--")) { if (!index(line, "-->")) incom = 1; next }
         if (!fence && index(line, "**Secret scan — BEFORE every `git push`") == 1) n++ }
       END { exit (n == 1) ? 0 : 1 }' "$1"
}
if skill_order_ok "$SKILL"; then pass "SKILL.md: the Phase 6 secret scan precedes the first push"; else fail "SKILL.md: the scan call is missing from Phase 6 or does not precede git push -u origin BRANCH_NAME"; fi
_p6=$(phase_block "$SKILL" "## Phase 6: Push and Create PR")
_ptr=$(printf '%s\n' "$_p6" | grep -F -- 'prepush-secret-scan.sh"; echo' | head -n 1)
want_in "the pointer line starts as the secret-scan instruction" "${_ptr:0:60}" '**Secret scan — BEFORE every `git push`'
want_notin "the pointer line is not commented out" "$_ptr" "<!--"
want_in "the pointer carries the runnable command with the rc echo" "$_ptr" 'bash "${CLAUDE_PLUGIN_ROOT}/skills/ship/scripts/prepush-secret-scan.sh"; echo "SCAN_RC=$?"'
want_in "the pointer carries the Bash timeout" "$_ptr" 'Bash `timeout: 400000`'
want_in "the pointer carries the whole 0 / 43 / else rule" "$_ptr" '0 continue; 43 append the printed `secret-scan:` line to the PR body (re-add after any body rewrite), continue; else STOP (44: show the operator the reason; 127: plugin root unset, see Cloud Mode).'
want_in "the pointer says headless FINDINGS aborts and never edits the gitleaks config" "$_ptr" "Headless FINDINGS/44: abort, never rewrite history or edit the gitleaks config."
_p64=$(phase_block "$SKILL" "## Phase 6.4: Unpushed-Commits Gate")
want_in "Phase 6.4 carries the hook-paragraph pointer" "$_p64" "Run the Phase 6 secret scan before the \`git push\` it asks for."
want_in "the Phase 6.4 headless echo names the scan" "$_p64" "Run the Phase 6 secret scan, then 'git push'."
want_in "Phase 6.4 still names the fail-closed fetch behaviour" "$_p64" "Fail-closed on fetch failure"
want_in "Phase 6.4 still names chained forms" "$_p64" "(chained forms too)"
want_in "the Phase 6.4 enforcement tag is unchanged" "$_p64" "[skill-enforced: ship Phase 6.4 + hook ship-unpushed-commits-gate.sh]"
if push_sites_ok "$SKILL" '^ *# Phase 6 secret scan first$' 4 'git push -u origin BRANCH_NAME'; then pass "SKILL.md: all 4 later push sites (6.45, 6.5 x2, 7) carry the scan comment directly above, and there are no others"; else fail "SKILL.md: a git push site lacks the scan comment, or the site count changed (want exactly 4)"; fi
if pointer_ok "$SKILL"; then pass "SKILL.md: the pointer line is live (outside fences and HTML comments)"; else fail "SKILL.md: the pointer line is missing, duplicated, fenced or commented out"; fi
if push_sites_ok "$REVIEW_SKILL" "^ *# ship's prepush-secret-scan.sh first$" 1 ''; then pass "review SKILL.md: the fix/artifact push carries the scan comment (and is the only push site)"; else fail "review SKILL.md: the push block lacks the scan comment or a new push site appeared"; fi
want_in "review SKILL.md: the pre-panel push names the script" "$(grep -F 'Push the branch before spawning the panel' "$REVIEW_SKILL")" "prepush-secret-scan.sh"
_hookline=$(grep -F 'permissionDecisionReason: ("BLOCKED: " + $n' "$HOOK")
want_in "the unpushed-commits hook's deny text names the scan script" "$_hookline" "prepush-secret-scan.sh"
want_in "...and the stop rule" "$_hookline" "anything else STOP"
if [ -f "$REPO_ROOT/plugins/soleur/skills/ship/scripts/prepush-secret-scan.sh" ]; then pass "the script path named in the pointer exists"; else fail "the pointer names a script that does not exist"; fi

# M5 REORDER: move the call line after the push line in a sandbox copy; the order check must go RED.
cp "$SKILL" "$TMP/mut/skill.pristine.md"
_P=$(awk -v h="## Phase 6: Push and Create PR" 'index($0, h) == 1 { on = 1; next } /^## / { if (on) exit } on && index($0, "**Secret scan — BEFORE every") == 1 { print NR; exit }' "$SKILL")
_G=$(awk -v h="## Phase 6: Push and Create PR" 'index($0, h) == 1 { on = 1; next } /^## / { if (on) exit } on && $0 == "git push -u origin BRANCH_NAME" { print NR; exit }' "$SKILL")
if [[ "$_P" =~ ^[0-9]+$ ]] && [[ "$_G" =~ ^[0-9]+$ ]] && [ "$_P" -lt "$_G" ]; then
  awk -v P="$_P" -v G="$_G" 'NR == P { held = $0; next } { print } NR == G { print held }' "$SKILL" >"$TMP/mut/skill.reorder.md"
  if cmp -s "$SKILL" "$TMP/mut/skill.reorder.md"; then fail "M5: the reorder did not land"; elif skill_order_ok "$TMP/mut/skill.reorder.md"; then fail "M5: REORDER survived the order check"; else pass "M5 REORDER: the call moved after the push goes RED (line $_P -> after $_G)"; fi
else
  fail "M5: could not locate the call line ($_P) and the push line ($_G) inside the Phase 6 block"
fi
# Reject controls: each verdict-owning pin helper must be able to say NO, or its green certifies nothing.
printf '```bash\n# Phase 6 secret scan first\ngit push\n```\n' >"$TMP/mut/ps-good.md"
printf '```bash\n# Phase 6 secret scan first\necho hi\ngit push\n```\n' >"$TMP/mut/ps-gap.md"
printf '```bash\n# Phase 6 secret scan first\ngit push\ngit push && echo second\n```\n' >"$TMP/mut/ps-extra.md"
if push_sites_ok "$TMP/mut/ps-good.md" '^ *# Phase 6 secret scan first$' 1 '' && ! push_sites_ok "$TMP/mut/ps-gap.md" '^ *# Phase 6 secret scan first$' 1 '' && ! push_sites_ok "$TMP/mut/ps-extra.md" '^ *# Phase 6 secret scan first$' 1 ''; then
  pass "push_sites_ok accepts a guarded site and rejects a gap and an unguarded extra site"
else
  fail "push_sites_ok cannot tell a guarded push from an unguarded one"
fi
printf '**Secret scan — BEFORE every `git push` x\n' >"$TMP/mut/pt-good.md"
printf '```text\n**Secret scan — BEFORE every `git push` x\n```\n' >"$TMP/mut/pt-fence.md"
printf '<!--\n**Secret scan — BEFORE every `git push` x\n-->\n' >"$TMP/mut/pt-html.md"
printf '**Secret scan — BEFORE every `git push` x\n**Secret scan — BEFORE every `git push` y\n' >"$TMP/mut/pt-dup.md"
if pointer_ok "$TMP/mut/pt-good.md" && ! pointer_ok "$TMP/mut/pt-fence.md" && ! pointer_ok "$TMP/mut/pt-html.md" && ! pointer_ok "$TMP/mut/pt-dup.md"; then
  pass "pointer_ok accepts a live pointer and rejects a fenced, commented-out and duplicated one"
else
  fail "pointer_ok cannot tell a live pointer from an inert one"
fi

# ============================== floor and reporting ====================================================
_t_ci_contract() {
  local body rc
  body=$(awk '/^# >>> ci-contract-epilogue$/{f=1;next} /^# <<< ci-contract-epilogue$/{f=0} f' "${BASH_SOURCE[0]}")
  if [[ -z "${body//[[:space:]]/}" ]]; then
    fail "CI fail-on-skip contract: epilogue markers matched nothing, the extraction is broken"
    return
  fi
  rc=0; ( set +e; eval 'SKIPPED_ARMS=(x); CI=true; FAIL=0'"
$body" ) >/dev/null 2>&1 || rc=$?
  if [ "$rc" != 1 ]; then fail "CI fail-on-skip contract: CI=true with skips did not exit 1"; return; fi
  rc=0; ( set +e; eval 'SKIPPED_ARMS=(x); unset CI; FAIL=0'"
$body" ) >/dev/null 2>&1 || rc=$?
  if [ "$rc" = 1 ]; then fail "CI fail-on-skip contract: a local skip (no CI) exited 1"; return; fi
  rc=0; ( set +e; eval 'SKIPPED_ARMS=(); CI=true; FAIL=0'"
$body" ) >/dev/null 2>&1 || rc=$?
  if [ "$rc" = 1 ]; then fail "CI fail-on-skip contract: CI=true with no skips exited 1"; return; fi
  rc=0; ( set +e; eval 'SKIPPED_ARMS=(); unset CI; FAIL=1'"
$body" ) >/dev/null 2>&1 || rc=$?
  if [ "$rc" != 1 ]; then fail "final exit gate: a recorded failure did not exit 1"; return; fi
  pass "CI fail-on-skip contract and the final exit gate (4-row truth table on the real epilogue)"
}
_t_ci_contract

echo ""
echo "stub-arm assertions: $PASS, real-arm assertions: $RPASS, failed: $FAIL"
if [ "${#SKIPPED_ARMS[@]}" -gt 0 ]; then
  echo "SKIPPED arms: ${SKIPPED_ARMS[*]}"
fi
FLOOR=150
if [ "$PASS" -lt "$FLOOR" ]; then
  printf 'FATAL: only %s stub-arm assertions passed; floor is %s (a stub or a gutted suite)\n' "$PASS" "$FLOOR" >&2
  exit 1
fi
RFLOOR=62
if [ "$HAVE_GITLEAKS" = 1 ] || [ "${CI:-}" = "true" ]; then
  if [ "$RPASS" -lt "$RFLOOR" ]; then
    printf 'FATAL: only %s real-arm assertions passed; floor is %s (real arms gutted, or skipped under CI)\n' "$RPASS" "$RFLOOR" >&2
    exit 1
  fi
fi
# >>> ci-contract-epilogue
if [ "${#SKIPPED_ARMS[@]}" -gt 0 ]; then
  if [ "${CI:-}" = "true" ]; then
    printf 'FAIL: %s arm(s) were skipped under CI=true (ADR-188: CI installs the pinned binary, so a skip is a broken environment)\n' "${#SKIPPED_ARMS[@]}" >&2
    exit 1
  fi
fi
[ "$FAIL" -eq 0 ] || exit 1
# <<< ci-contract-epilogue
exit 0
