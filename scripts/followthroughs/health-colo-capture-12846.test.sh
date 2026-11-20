#!/usr/bin/env bash
# Companion suite for scripts/followthroughs/health-colo-capture-12846.sh.
#
# The probe's verdict comes from one read (the trusted comments on #12846, through the REAL trusted-verdict lib) and a
# clock. The suite runs the probe under `env -i` with PATH set to a curated tool directory that holds a `gh` shim and
# symlinks to the system tools the probe and the lib need, and nothing else, so no real `gh` can ever run (no network).
# The shim serves #12846's comments from a synthesized fixture by running the REAL jq expression the lib hands it, and
# answers the lib's author-permission call (`gh api repos/jikig-ai/soleur/collaborators/<login>/permission`) from
# GH_PERM_<login> (admin|write|read|none, FAIL = an HTTP 500, 404 = "not a user"). It exits 64 on any request it was not
# built to answer, so a probe asking the wrong question fails loudly instead of reading a fixture.
#
# Named rows are functions (row_<id>), so the mutation rows can re-run the exact row a mutant must turn red. Mutants are
# edited copies of the probe inside this suite's own temp dir (with the lib copied beside them, so it resolves), each
# edit made at an anchor that must occur exactly once in the probe.
set -uo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE="$REPO_ROOT/scripts/followthroughs/health-colo-capture-12846.sh"
LIB="$REPO_ROOT/scripts/lib/trusted-verdict.sh"

passes=0
fails=0
cases=0
pass() { passes=$((passes + 1)); echo "[ok]   $1"; }
fail() { fails=$((fails + 1)); echo "[FAIL] $1"; }
abort() { printf 'harness: %s\n' "$1" >&2; exit 2; }

[[ -f "$PROBE" ]] || abort "the probe is missing at $PROBE"
[[ -f "$LIB" ]] || abort "the trusted-verdict lib is missing at $LIB"

WORK="$(mktemp -d "${TMPDIR}/health-colo-capture.XXXXXXXX")" || abort "mktemp failed"
trap 'rm -rf "$WORK"' EXIT
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY\n' >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}
assert_fixture_dir "$WORK"

# --- the curated tool directory: the shim plus the system tools, and no real gh ---------------------------------------
TOOLS=(bash dirname mktemp rm grep base64 jq awk date tr)
mk_bin() {   # mk_bin <dir> <tool to leave out | ""> [--no-gh]
  local d="$1" skip="$2" t p
  assert_fixture_dir "$d"
  mkdir -p "$d" || abort "mkdir $d failed"
  for t in "${TOOLS[@]}"; do
    [[ "$t" != "$skip" ]] || continue
    p="$(type -P "$t")" || abort "the system tool $t is not installed"
    ln -sf "$p" "$d/$t" || abort "ln $t failed"
  done
  if [[ "${3-}" != "--no-gh" ]]; then cp "$WORK/gh-shim" "$d/gh" && chmod +x "$d/gh" || abort "shim install failed"; fi
}

cat > "$WORK/gh-shim" <<'SHIM'
#!/usr/bin/env bash
[[ -z "${GH_CALL_LOG-}" ]] || { a="$*"; printf '%s\n' "${a//$'\n'/ }" >> "$GH_CALL_LOG"; }
if [[ "${1-} ${2-}" == "issue view" ]]; then
  n="$3"; shift 3
  repo=""; json=""; jqx=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --repo) repo="$2"; shift 2 ;;
      --json) json="$2"; shift 2 ;;
      --jq) jqx="$2"; shift 2 ;;
      *) echo "gh shim: unexpected argument '$1'" >&2; exit 64 ;;
    esac
  done
  [[ "$repo" == "jikig-ai/soleur" ]] || { echo "gh shim: wrong --repo '$repo'" >&2; exit 64; }
  [[ "$json" == "comments" ]] || { echo "gh shim: unexpected --json '$json'" >&2; exit 64; }
  [[ "$n" == "12846" ]] || { echo "gh shim: comments read for #$n, expected 12846" >&2; exit 64; }
  [[ -n "$jqx" ]] || { echo "gh shim: no --jq expression" >&2; exit 64; }
  [[ -z "${GH_COMMENTS_FAIL-}" ]] || { echo "gh: HTTP 502" >&2; exit 1; }
  jq -r "$jqx" "$GH_COMMENTS_JSON"
  exit $?
fi
if [[ "${1-}" == "api" ]]; then
  path="${2-}"
  [[ "${3-} ${4-}" == "--jq .permission // empty" && $# -eq 4 ]] || { echo "gh shim: unexpected api arguments '$*'" >&2; exit 64; }
  login="${path#repos/jikig-ai/soleur/collaborators/}"; login="${login%/permission}"
  [[ "$login" != "$path" && "$path" == */permission ]] || { echo "gh shim: unexpected api path '$path'" >&2; exit 64; }
  var="GH_PERM_${login//-/_}"
  val="${!var-none}"
  case "$val" in
    FAIL) echo "gh: Server Error (HTTP 500)" >&2; exit 1 ;;
    404) echo "gh: $login is not a user (HTTP 404)" >&2; exit 1 ;;
  esac
  printf '{"permission":"%s"}' "$val" | jq -r '.permission // empty'
  exit $?
fi
echo "gh shim: unexpected command '$*'" >&2; exit 64
SHIM
mk_bin "$WORK/bin" ""
mk_bin "$WORK/bin-nogh" "" --no-gh
mk_bin "$WORK/bin-nojq" jq

# Build #12846's comments fixture from "login|body" pairs (a body may hold newlines).
mk_comments() {
  local out="$WORK/comments.json" first=1 pair login body
  printf '{"comments":[' > "$out"
  for pair in "$@"; do
    login="${pair%%|*}"; body="${pair#*|}"
    [[ $first -eq 1 ]] || printf ',' >> "$out"
    first=0
    jq -nc --arg l "$login" --arg b "$body" '{author:{login:$l},body:$b,createdAt:"2026-11-21T10:00:00Z"}' >> "$out"
  done
  printf ']}' >> "$out"
}

reset_fixture() {
  unset GH_COMMENTS_FAIL NO_TOKEN
  GH_PERM_owner1="admin"; GH_PERM_writer2="write"; GH_PERM_reader3="read"; GH_PERM_drive_by="none"; GH_PERM_ghost="404"
  BIN="$WORK/bin"
  : > "$WORK/calls.log"
  mk_comments
}

# run_case <clock | ""> -- runs the probe (or PROBE_UNDER) with the current fixture env; sets OUT and RC.
run_case() {
  local now="$1" tok=(GH_TOKEN=fixture)
  [[ -z "${NO_TOKEN-}" ]] || tok=()
  OUT="$(env -i PATH="$BIN" HOME="$WORK" ${tok[@]+"${tok[@]}"} \
        GH_COMMENTS_JSON="$WORK/comments.json" GH_CALL_LOG="$WORK/calls.log" ${GH_COMMENTS_FAIL:+GH_COMMENTS_FAIL=1} \
        GH_PERM_owner1="$GH_PERM_owner1" GH_PERM_writer2="$GH_PERM_writer2" GH_PERM_reader3="$GH_PERM_reader3" \
        GH_PERM_drive_by="$GH_PERM_drive_by" GH_PERM_ghost="$GH_PERM_ghost" \
        ${now:+HEALTHCOLO_CAPTURE_NOW=$now} "$BASH" "${PROBE_UNDER:-$PROBE}" 2>&1)"
  RC=$?
  ALL_RCS+=("$RC")
  ALL_OUT+="$OUT"$'\n'
}
ALL_RCS=()
ALL_OUT=""

# row_ok <want-rc> <needle> [absent-needle]: rc 0 when the last run matches, without counting anything.
row_ok() {
  local want="$1" needle="$2" absent="${3-}"
  [[ "$RC" -eq "$want" ]] || return 1
  [[ -z "$needle" ]] || grep -qF -- "$needle" <<<"$OUT" || return 1
  [[ -z "$absent" ]] || ! grep -qF -- "$absent" <<<"$OUT" || return 1
  return 0
}
expect() {   # <name> <want-rc> <needle> [absent-needle]
  local name="$1" want="$2" needle="$3" absent="${4-}"
  cases=$((cases + 1))
  if row_ok "$want" "$needle" "$absent"; then pass "$name"; else fail "$name: rc=$RC, wanted $want / '$needle' / not '$absent' ($(head -c 240 <<<"$OUT" | tr '\n' '|'))"; fi
}

# --- instrument self-test: both helpers move their counters, and expect() can REJECT ----------------------------------
p0=$passes; f0=$fails; c0=$cases
pass "self-test pass helper" >/dev/null; fail "self-test fail helper" >/dev/null
if [[ $((passes - p0)) -ne 1 || $((fails - f0)) -ne 1 ]]; then abort "assertion helpers do not move their counters"; fi
passes=$p0; fails=$f0
RC=5; OUT="needle-present"
expect "self-test: wrong rc" 0 "needle-present" >/dev/null
[[ $((fails - f0)) -eq 1 && $passes -eq $p0 ]] || abort "expect() accepted a wrong exit code"
expect "self-test: missing needle" 5 "absent-needle" >/dev/null
[[ $((fails - f0)) -eq 2 && $passes -eq $p0 ]] || abort "expect() accepted a missing needle"
expect "self-test: forbidden needle" 5 "needle-present" "needle-present" >/dev/null
[[ $((fails - f0)) -eq 3 && $passes -eq $p0 ]] || abort "expect() accepted a forbidden needle"
expect "self-test: accepting" 5 "needle-present" "other" >/dev/null
[[ $((fails - f0)) -eq 3 && $((passes - p0)) -eq 1 ]] || abort "expect() rejected a correct call"
passes=$p0; fails=$f0; cases=$c0

# --- the named rows ----------------------------------------------------------------------------------------------------
BEFORE="run the H handoff loop now (runbook knowledge-base/engineering/operations/runbooks/origin-tls-strict-flip.md, addendum 2026-11-19) before 2026-11-24, then post the S1-HEALTHCOLO-CAPTURED: line on #12846"
AFTER="ACTION REQUIRED: deadline passed without a capture: record the runbook's fallback Unverified: line on #12846 and close this tracker"
PASSMSG="PASS: the per-colo H capture is recorded on #12846"
BADNOTE="its time is not a real UTC time"
GOODLINE="S1-HEALTHCOLO-CAPTURED: 2026-11-21T09:15:02Z kept 2026-11-12T12-analytics-health-colo-216h.json on branch evidence-x CANARY-7c1"
NOW="2026-11-21T08:00:00Z"

# Each row_<id> sets ROW_NAME, ROW_WANT, ROW_NEEDLE, ROW_ABSENT and runs the probe once.
declare -A ROWS_SEEN=()
row() { ROW_NAME="$1"; ROW_WANT="$2"; ROW_NEEDLE="$3"; ROW_ABSENT="${4-}"; }
run_row() { "row_$1"; ROWS_SEEN[$1]=1; expect "$ROW_NAME" "$ROW_WANT" "$ROW_NEEDLE" "$ROW_ABSENT"; }

row_trusted()     { reset_fixture; mk_comments "owner1|$GOODLINE"; run_case "$NOW"
                    row "trusted admin marker => 0 (PASS, closes)" 0 "$PASSMSG" "ACTION REQUIRED"; }
row_writer()      { reset_fixture; mk_comments "writer2|$GOODLINE"; run_case "$NOW"
                    row "trusted write-permission marker => 0" 0 "$PASSMSG"; }
row_latepass()    { reset_fixture; mk_comments "owner1|$GOODLINE"; run_case 2026-11-30T00:00:00Z
                    row "a trusted marker after the deadline still closes => 0" 0 "$PASSMSG" "deadline passed"; }
row_secondline()  { reset_fixture; mk_comments "owner1|$(printf 'Capture done.\n%s' "$GOODLINE")"; run_case "$NOW"
                    row "the marker on a later line of the comment counts => 0" 0 "$PASSMSG"; }
row_baremarker()  { reset_fixture; mk_comments "owner1|S1-HEALTHCOLO-CAPTURED: 2026-11-21T09:15:02Z"; run_case "$NOW"
                    row "a marker with the time and no free text counts => 0" 0 "$PASSMSG"; }
row_badthengood() { reset_fixture; mk_comments "owner1|S1-HEALTHCOLO-CAPTURED: soon" "owner1|$GOODLINE"; run_case "$NOW"
                    row "a bad marker line then a good one => 0" 0 "$PASSMSG"; }
row_crlf()        { reset_fixture; mk_comments "owner1|$GOODLINE"$'\r\n'"more"; run_case "$NOW"
                    row "a CRLF comment body still counts => 0" 0 "$PASSMSG"; }
row_untrusted()   { reset_fixture; mk_comments "drive-by|$GOODLINE"; run_case "$NOW"
                    row "untrusted author (permission none) marker => 5" 5 "$BEFORE" "PASS"; }
row_reader()      { reset_fixture; mk_comments "reader3|$GOODLINE"; run_case "$NOW"
                    row "read-permission author marker => 5" 5 "$BEFORE" "PASS"; }
row_ghost()       { reset_fixture; mk_comments "ghost|$GOODLINE"; run_case "$NOW"
                    row "a marker author the permission API calls 'not a user' (404) is dropped => 5, not 3" 5 "$BEFORE" "CANNOT ESTABLISH"; }
row_fenced()      { reset_fixture; mk_comments "owner1|$(printf '```\n%s\n```' "$GOODLINE")"; run_case "$NOW"
                    row "marker inside a fenced block => 5" 5 "$BEFORE" "PASS"; }
row_tildefence()  { reset_fixture; mk_comments "owner1|$(printf '~~~text\n%s\n~~~' "$GOODLINE")"; run_case "$NOW"
                    row "marker inside a tilde fence => 5" 5 "$BEFORE" "PASS"; }
row_htmlcomment() { reset_fixture; mk_comments "owner1|$(printf '<!--\n%s\n-->' "$GOODLINE")"; run_case "$NOW"
                    row "marker inside an HTML comment => 5" 5 "$BEFORE" "PASS"; }
row_htmlinline()  { reset_fixture; mk_comments "owner1|<!-- $GOODLINE -->"; run_case "$NOW"
                    row "marker inside a one-line HTML comment => 5" 5 "$BEFORE" "PASS"; }
row_badtime()     { reset_fixture; mk_comments "owner1|S1-HEALTHCOLO-CAPTURED: 2026-13-45T99:99:99Z kept x"; run_case "$NOW"
                    row "a well-shaped but impossible time => 5, and the bad line is named" 5 "$BADNOTE" "PASS"; }
row_hour24()      { reset_fixture; mk_comments "owner1|S1-HEALTHCOLO-CAPTURED: 2026-11-21T24:00:00Z kept x"; run_case "$NOW"
                    row "hour 24 is not a time (it does not print back) => 5" 5 "$BADNOTE" "PASS"; }
row_feb30()       { reset_fixture; mk_comments "owner1|S1-HEALTHCOLO-CAPTURED: 2026-02-30T10:00:00Z kept x"; run_case "$NOW"
                    row "February 30 is not a time => 5" 5 "$BADNOTE" "PASS"; }
row_badshape()    { reset_fixture; mk_comments "owner1|S1-HEALTHCOLO-CAPTURED: soon"; run_case "$NOW"
                    row "a marker with no ISO time => 5, named" 5 "$BADNOTE" "PASS"; }
row_nosecs()      { reset_fixture; mk_comments "owner1|S1-HEALTHCOLO-CAPTURED: 2026-11-21T09:15Z kept x"; run_case "$NOW"
                    row "a time without seconds is not the documented form => 5" 5 "$BADNOTE" "PASS"; }
row_glued()       { reset_fixture; mk_comments "owner1|S1-HEALTHCOLO-CAPTURED: 2026-11-21T09:15:02Zkept"; run_case "$NOW"
                    row "free text glued to the Z is not a time => 5" 5 "$BADNOTE" "PASS"; }
row_indented()    { reset_fixture; mk_comments "owner1|  $GOODLINE"; run_case "$NOW"
                    row "an indented marker is not at line start => 5, not named" 5 "$BEFORE" "$BADNOTE"; }
row_lowercase()   { reset_fixture; mk_comments "owner1|s1-healthcolo-captured: 2026-11-21T09:15:02Z"; run_case "$NOW"
                    row "a lower-case marker is not the marker => 5" 5 "$BEFORE" "PASS"; }
row_othermarker() { reset_fixture; mk_comments "owner1|S2-HEALTHCOLO-CAPTURED: 2026-11-21T09:15:02Z"; run_case "$NOW"
                    row "another S<n> marker is not this one => 5" 5 "$BEFORE" "PASS"; }
row_before()      { reset_fixture; mk_comments "owner1|Working on the capture." "drive-by|+1"; run_case "$NOW"
                    row "no marker before the deadline => 5 with the before-deadline ask" 5 "$BEFORE" "deadline passed"; }
row_lastsecond()  { reset_fixture; run_case 2026-11-24T23:59:59Z
                    row "no marker at 2026-11-24T23:59:59Z is still before the deadline => 5" 5 "$BEFORE" "deadline passed"; }
row_after()       { reset_fixture; run_case 2026-11-25T00:00:00Z
                    row "no marker at 2026-11-25T00:00:00Z => 5 with the after-deadline ask" 5 "$AFTER" "handoff loop now"; }
row_wellafter()   { reset_fixture; mk_comments "owner1|S1-HEALTHCOLO-CAPTURED: soon"; run_case 2026-12-05T12:00:00Z
                    row "a bad marker after the deadline => 5 with the after-deadline ask and the bad line named" 5 "$BADNOTE" "handoff loop now"; }
row_realclock()   { reset_fixture; run_case ""
                    row "no clock override reads the real clock => 5 (either ask)" 5 "ACTION REQUIRED: "; }
row_commentsfail() { reset_fixture; GH_COMMENTS_FAIL=1; run_case "$NOW"
                    row "the gh comment read fails => 3" 3 "CANNOT ESTABLISH: could not read the trusted comments on #12846" "ACTION REQUIRED"; }
row_permfail()    { reset_fixture; GH_PERM_owner1="FAIL"; mk_comments "owner1|$GOODLINE"; run_case "$NOW"
                    row "the permission read fails (HTTP 500, not 404) => 3" 3 "CANNOT ESTABLISH: could not read the trusted comments" "PASS"; }
row_notoken()     { reset_fixture; NO_TOKEN=1; mk_comments "owner1|$GOODLINE"; run_case "$NOW"
                    row "GH_TOKEN unset => 3" 3 "GH_TOKEN is not set" "PASS"; }
row_nogh()        { reset_fixture; BIN="$WORK/bin-nogh"; mk_comments "owner1|$GOODLINE"; run_case "$NOW"
                    row "gh missing => 3" 3 "gh is not installed"; }
row_nojq()        { reset_fixture; BIN="$WORK/bin-nojq"; mk_comments "owner1|$GOODLINE"; run_case "$NOW"
                    row "jq missing => 3" 3 "jq is not installed"; }
row_clockshape()  { reset_fixture; run_case 2026-11-21
                    row "a clock override that is not YYYY-MM-DDTHH:MM:SSZ => 3" 3 "is not YYYY-MM-DDTHH:MM:SSZ"; }
row_clockreal()   { reset_fixture; run_case 2026-11-21T25:00:00Z
                    row "an impossible clock override => 3" 3 "is not a real UTC time"; }

# lib-placement rows: a copy of the probe with no lib directory, an empty one, and a lib that exits the body
PLACE="$WORK/place"
assert_fixture_dir "$PLACE"
mkdir -p "$PLACE/nolib/scripts/followthroughs" "$PLACE/emptylib/scripts/followthroughs" "$PLACE/emptylib/scripts/lib" \
         "$PLACE/forced/scripts/followthroughs" "$PLACE/forced/scripts/lib" || abort "mkdir failed"
cp "$PROBE" "$PLACE/nolib/scripts/followthroughs/probe.sh" || abort "cp failed"
cp "$PROBE" "$PLACE/emptylib/scripts/followthroughs/probe.sh" || abort "cp failed"
cp "$PROBE" "$PLACE/forced/scripts/followthroughs/health-colo-capture-12846.sh" || abort "cp failed"
row_nolibdir()    { reset_fixture; mk_comments "owner1|$GOODLINE"; PROBE_UNDER="$PLACE/nolib/scripts/followthroughs/probe.sh" run_case "$NOW"
                    row "the lib directory is missing => 3" 3 "trusted-verdict lib directory unresolved"; }
row_nolib()       { reset_fixture; mk_comments "owner1|$GOODLINE"; PROBE_UNDER="$PLACE/emptylib/scripts/followthroughs/probe.sh" run_case "$NOW"
                    row "the lib file is missing => 3" 3 "trusted-verdict lib unavailable"; }
row_forced0()     { local b="${MUT_BASE:-$PLACE/forced}"; printf 'exit 0\n' > "$b/scripts/lib/trusted-verdict.sh"
                    reset_fixture; mk_comments "owner1|$GOODLINE"; PROBE_UNDER="$b/scripts/followthroughs/health-colo-capture-12846.sh" run_case "$NOW"
                    row "a lib that runs 'exit 0' inside the body lands on the internal-error arm => 3, never a close" 3 "probe internal error (rc=0)" "PASS"; }
row_forced1()     { printf 'exit 1\n' > "$PLACE/forced/scripts/lib/trusted-verdict.sh"
                    reset_fixture; PROBE_UNDER="$PLACE/forced/scripts/followthroughs/health-colo-capture-12846.sh" run_case "$NOW"
                    row "a lib that runs 'exit 1' inside the body => 3, never 1" 3 "probe internal error (rc=1)"; }
row_nofunc()      { printf 'return 0\n' > "$PLACE/forced/scripts/lib/trusted-verdict.sh"
                    reset_fixture; PROBE_UNDER="$PLACE/forced/scripts/followthroughs/health-colo-capture-12846.sh" run_case "$NOW"
                    row "a lib that defines no trusted_verdict_bodies => 3" 3 "trusted-verdict lib unavailable"; }

ROW_IDS=(trusted writer latepass secondline baremarker badthengood crlf untrusted reader ghost fenced tildefence htmlcomment
         htmlinline badtime hour24 feb30 badshape nosecs glued indented lowercase othermarker before lastsecond after
         wellafter realclock commentsfail permfail notoken nogh nojq clockshape clockreal nolibdir nolib forced0 forced1 nofunc)
for id in "${ROW_IDS[@]}"; do run_row "$id"; done

# the shim answered the permission call: a trusted row reads the comments once and looks the marker author up once
row_trusted
cases=$((cases + 1))
if [[ "$(grep -c '^issue view 12846 --repo jikig-ai/soleur --json comments --jq ' "$WORK/calls.log")" -eq 1 \
   && "$(grep -cx 'api repos/jikig-ai/soleur/collaborators/owner1/permission --jq .permission // empty' "$WORK/calls.log")" -eq 1 \
   && "$(grep -c . "$WORK/calls.log")" -eq 2 ]]; then
  pass "a trusted row makes exactly one comment read of #12846 and one permission call for the marker author"
else
  fail "unexpected gh calls: $(tr '\n' '|' < "$WORK/calls.log")"
fi

# --- the xtrace refusal ------------------------------------------------------------------------------------------------
reset_fixture
OUT="$(env -i PATH="$WORK/bin" HOME="$WORK" GH_TOKEN=fixture GH_COMMENTS_JSON="$WORK/comments.json" GH_CALL_LOG="$WORK/calls.log" "$BASH" -x "$PROBE" 2>&1)"; RC=$?
expect "xtrace with GH_TOKEN set refuses with 78" 78 "refusing to trace with a live credential set"
cases=$((cases + 1))
[[ ! -s "$WORK/calls.log" ]] && pass "the xtrace refusal happens before any gh call" || fail "gh was called before the xtrace refusal"
OUT="$(env -i PATH="$WORK/bin" HOME="$WORK" GH_COMMENTS_JSON="$WORK/comments.json" "$BASH" -x "$PROBE" 2>&1)"; RC=$?
expect "xtrace without GH_TOKEN is not refused (the token check then gives 3)" 3 "GH_TOKEN is not set" "refusing to trace"

# --- mutation rows: each edit at an exactly-once anchor must turn its named row(s) red --------------------------------
MUTANTS=0
mutate() {   # mutate <label> <anchor> <replacement> <row-id>...
  local label="$1" anchor="$2" repl="$3" d="$WORK/mut-$1" src n id red=0 total=0 r
  shift 3
  MUTANTS=$((MUTANTS + 1))
  cases=$((cases + 1))
  n="$(grep -cF -- "$anchor" "$PROBE")"
  if [[ "$n" -ne 1 ]]; then fail "MUT-$label: the anchor occurs $n times in the probe, wanted exactly 1"; return; fi
  assert_fixture_dir "$d"; rm -rf "$d"; mkdir -p "$d/scripts/followthroughs" "$d/scripts/lib" || abort "mkdir failed"
  cp "$LIB" "$d/scripts/lib/trusted-verdict.sh" || abort "cp failed"
  src="$(cat "$PROBE"; printf x)"; src="${src%x}"
  printf '%s' "${src/"$anchor"/"$repl"}" > "$d/scripts/followthroughs/health-colo-capture-12846.sh"
  if cmp -s "$PROBE" "$d/scripts/followthroughs/health-colo-capture-12846.sh"; then fail "MUT-$label: the edit did not land"; return; fi
  for id in "$@"; do
    [[ -n "${ROWS_SEEN[$id]+x}" ]] || { fail "MUT-$label: names row '$id', which is not a registered row"; return; }
    total=$((total + 1))
    MUT_BASE="$d" PROBE_UNDER="$d/scripts/followthroughs/health-colo-capture-12846.sh" "row_$id"
    if row_ok "$ROW_WANT" "$ROW_NEEDLE" "$ROW_ABSENT"; then r="$r $id(still green)"; else red=$((red + 1)); fi
  done
  if (( total > 0 && red == total )); then pass "MUT-$label: turns red: $*"
  else fail "MUT-$label: survived on${r}"; fi
}
mutate DEADLINE-INVERTED 'if [ "$now_e" -lt "$deadline_e" ]; then' 'if [ "$now_e" -ge "$deadline_e" ]; then' before after
mutate TRUST-BYPASS 'bodies="$(trusted_verdict_bodies "$ISSUE" "$REPO")"' \
  "bodies=\"\$(gh issue view \"\$ISSUE\" --repo \"\$REPO\" --json comments --jq '.comments[].body')\"" untrusted fenced htmlcomment
mutate CAPTURED-GUARD 'if [ "$captured" -eq 1 ]; then' 'if [ "$captured" -eq 0 ]; then' before
mutate RC2-TO-5 '(comment or permission read failed)"; return 3; }' '(comment or permission read failed)"; return 5; }' commentsfail permfail
mutate TIMEPARSE-DROPPED 'real_utc "$ts" || { bad=1; continue; }' ':' badtime hour24 feb30
mutate SENTINEL-ZERO 'CAPTURED=10' 'CAPTURED=0' forced0

# --- census: never 1, and each of 0, 3 and 5 was seen ------------------------------------------------------------------
cases=$((cases + 1))
bad_rc=""
for r in "${ALL_RCS[@]}"; do case "$r" in 0|3|5) : ;; *) bad_rc="$bad_rc $r" ;; esac; done
[[ " ${ALL_RCS[*]} " == *" 0 "* && " ${ALL_RCS[*]} " == *" 3 "* && " ${ALL_RCS[*]} " == *" 5 "* ]] || bad_rc="$bad_rc (one of 0, 3, 5 never seen)"
[[ -z "$bad_rc" ]] && pass "no run exited outside 0, 3 and 5 (never 1), across ${#ALL_RCS[@]} runs" || fail "exit codes outside 0/3/5 seen:$bad_rc"
WANT_RUNS=53
cases=$((cases + 1))
[[ "${#ALL_RCS[@]}" -eq "$WANT_RUNS" ]] && pass "the census covers exactly $WANT_RUNS probe runs" || fail "the census covers ${#ALL_RCS[@]} probe runs, wanted $WANT_RUNS"

# --- output hygiene: nothing from the comments reaches the public output ----------------------------------------------
cases=$((cases + 1))
hyg=""
for tok in owner1 writer2 reader3 drive-by ghost CANARY-7c1 evidence-x analytics-health-colo-216h "Working on" "S1-HEALTHCOLO-CAPTURED: 2026"; do
  grep -qF -- "$tok" <<<"$ALL_OUT" && hyg="$hyg [$tok]"
done
[[ -z "$hyg" ]] && pass "no output line names a login or echoes comment text" || fail "output hygiene: found:$hyg"

# --- static shape ------------------------------------------------------------------------------------------------------
code="$(grep -vE '^[[:space:]]*#' "$PROBE")"
cases=$((cases + 1))
[[ "$(grep -cF 'trusted_verdict_bodies "$ISSUE" "$REPO"' <<<"$code")" -eq 1 ]] \
  && pass "the probe reads the marker through trusted_verdict_bodies on #12846, once" \
  || fail "the probe does not call trusted_verdict_bodies on #12846 exactly once"
cases=$((cases + 1))
gh_calls="$(grep -nE '(^|[^[:alnum:]_./-])gh[[:space:]]+[a-z]' <<<"$code" | grep -v 'for need in' || true)"
[[ -z "$gh_calls" ]] && pass "the probe makes no direct gh call (every comment read goes through the lib)" || fail "direct gh call: $gh_calls"
cases=$((cases + 1))
if ! grep -qE '(^|[^[:alnum:]_])(exec|trap|kill)([[:space:]]|$)' <<<"$code" && ! grep -qE 'exit 1([^0-9]|$)' <<<"$code"; then
  pass "the probe has no exec, trap, kill or exit 1"
else
  fail "the probe carries exec/trap/kill or an exit 1"
fi
cases=$((cases + 1))
first_cmd="$(grep -nvE '^[[:space:]]*(#|$)|^set -uo pipefail$' "$PROBE" | head -n 1)"
[[ "$first_cmd" == *'case "$-" in'* ]] && pass "the xtrace refusal is the first command after set" || fail "the first command is not the xtrace refusal: $first_cmd"
cases=$((cases + 1))
grep -qE '^# RETIREMENT\.' "$PROBE" && grep -qF 'scripts/followthroughs/health-colo-capture-12846.test.sh' "$PROBE" \
  && grep -qF 'scripts/test-all.sh' "$PROBE" && grep -qF 'suite-shard-legs.tsv' "$PROBE" && grep -qF 'suite-durations.tsv' "$PROBE" \
  && pass "the header's RETIREMENT block lists the suite, the run_suite line and the manifest rows" \
  || fail "the RETIREMENT block is incomplete"

# --- floors ------------------------------------------------------------------------------------------------------------
echo "---"
echo "Total: $passes passed, $fails failed ($cases cases, $MUTANTS mutants)"
if [[ $((passes + fails)) -ne "$cases" ]]; then
  printf 'ACCOUNTING: %s assertions recorded but %s cases counted: an assertion site is unpaired\n' "$((passes + fails))" "$cases" >&2
  exit 1
fi
# Exact on purpose: adding or deleting a row or a mutant must be a deliberate edit here. Each count is pinned from below
# by a floor whose threshold is a plain assignment directly above its `if` (the shape scripts/guard-vacuity-floor.test.sh
# slices and runs with the assertion helpers neutered), and from above by a ceiling on the same threshold.
ASSERT_FLOOR=58
if [[ $((passes + fails)) -lt "$ASSERT_FLOOR" ]]; then
  printf 'anti-vacuity floor: only %s assertions ran, expected exactly %s\n' "$((passes + fails))" "$ASSERT_FLOOR" >&2
  exit 1
fi
CASE_FLOOR=58
if [[ "$cases" -lt "$CASE_FLOOR" ]]; then
  printf 'anti-vacuity floor: only %s cases counted, expected exactly %s\n' "$cases" "$CASE_FLOOR" >&2
  exit 1
fi
MUTANT_FLOOR=6
if [[ "$MUTANTS" -lt "$MUTANT_FLOOR" ]]; then
  printf 'anti-vacuity floor: only %s mutants ran, expected exactly %s\n' "$MUTANTS" "$MUTANT_FLOOR" >&2
  exit 1
fi
if [[ $((passes + fails)) -gt "$ASSERT_FLOOR" || "$cases" -gt "$CASE_FLOOR" || "$MUTANTS" -gt "$MUTANT_FLOOR" ]]; then
  printf 'anti-vacuity ceiling: %s assertions, %s cases, %s mutants; expected exactly %s, %s and %s (bump the floors deliberately)\n' \
    "$((passes + fails))" "$cases" "$MUTANTS" "$ASSERT_FLOOR" "$CASE_FLOOR" "$MUTANT_FLOOR" >&2
  exit 1
fi
WANT_ROWS=40
if [[ "${#ROW_IDS[@]}" -ne "$WANT_ROWS" || "${#ROWS_SEEN[@]}" -ne "$WANT_ROWS" ]]; then
  printf 'anti-vacuity: %s rows registered and %s run, expected exactly %s\n' "${#ROW_IDS[@]}" "${#ROWS_SEEN[@]}" "$WANT_ROWS" >&2
  exit 1
fi
[[ "$fails" -eq 0 ]] || exit 1
exit 0
