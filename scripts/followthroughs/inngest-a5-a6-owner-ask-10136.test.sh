#!/usr/bin/env bash
# Companion suite for scripts/followthroughs/inngest-a5-a6-owner-ask-10136.sh.
#
# The probe's state comes from four reads (three issue states and the trusted anchors on the
# epic) plus a date. This suite puts a `gh` shim first on PATH: the shim answers the issue-state
# reads from GH_ISSUE_<n>, serves the epic's comments from a fixture file by running the REAL jq
# expression the trusted-verdict lib hands it, and answers the author-permission lookup from
# GH_PERM_<login>. The real trusted-verdict lib therefore runs unmodified, so "an untrusted author
# cannot post the done anchor" and "a fenced anchor does not count" are tested through the lib the
# probe actually uses, not through a fake of it. The shim exits 64 on any request it was not built
# to answer, so a probe asking the wrong question fails loudly instead of reading a fixture.
set -uo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE="$REPO_ROOT/scripts/followthroughs/inngest-a5-a6-owner-ask-10136.sh"

passes=0
fails=0
cases=0
pass() { passes=$((passes + 1)); echo "[ok]   $1"; }
fail() { fails=$((fails + 1)); echo "[FAIL] $1"; }
abort() { printf 'harness: %s\n' "$1" >&2; exit 2; }

[[ -f "$PROBE" ]] || abort "the probe is missing at $PROBE"

WORK="$(mktemp -d "${TMPDIR}/owner-ask.XXXXXXXX")" || abort "mktemp failed"
trap 'rm -rf "$WORK"' EXIT
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; a write would land in %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}
assert_fixture_dir "$WORK"
mkdir -p "$WORK/bin" || abort "mkdir failed"

# --- the gh shim -----------------------------------------------------------------------------------------------
cat > "$WORK/bin/gh" <<'SHIM'
#!/usr/bin/env bash
if [[ "$1 $2" == "issue view" ]]; then
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
  if [[ "$json" == "comments" ]]; then
    [[ "$n" == "10136" ]] || { echo "gh shim: comments read for #$n, expected the epic 10136" >&2; exit 64; }
    [[ -z "${GH_COMMENTS_FAIL-}" ]] || exit 1
    jq -r "$jqx" "$GH_COMMENTS_JSON"
    exit $?
  fi
  if [[ "$json" == "state,stateReason" ]]; then
    var="GH_ISSUE_$n"
    val="${!var-}"
    [[ -n "$val" ]] || { echo "gh shim: no fixture for #$n" >&2; exit 64; }
    [[ "$val" != "FAIL" ]] || exit 1
    [[ "$val" != "GARBAGE" ]] || { echo "<html>not json</html>"; exit 0; }
    printf '%s %s\n' "${val%%:*}" "${val#*:}"
    exit 0
  fi
  echo "gh shim: unexpected --json '$json'" >&2; exit 64
fi
if [[ "$1" == "api" ]]; then
  path="$2"
  login="${path#repos/jikig-ai/soleur/collaborators/}"; login="${login%/permission}"
  [[ "$login" != "$path" ]] || { echo "gh shim: unexpected api path '$path'" >&2; exit 64; }
  var="GH_PERM_${login//-/_}"
  printf '{"permission":"%s"}' "${!var-none}" | jq -r '.permission // empty'
  exit $?
fi
echo "gh shim: unexpected command '$*'" >&2; exit 64
SHIM
chmod +x "$WORK/bin/gh" || abort "chmod failed"

# Build the epic's comments fixture from "login|body" pairs (body may contain \n).
mk_comments() {
  local out="$WORK/comments.json" first=1 pair login body
  printf '{"comments":[' > "$out"
  for pair in "$@"; do
    login="${pair%%|*}"; body="${pair#*|}"
    [[ $first -eq 1 ]] || printf ',' >> "$out"
    first=0
    jq -nc --arg l "$login" --arg b "$body" '{author:{login:$l},body:$b,createdAt:"2026-10-27T10:00:00Z"}' >> "$out"
  done
  printf ']}' >> "$out"
}

# run_case <today> -- runs the probe with the current GH_* fixture env; sets OUT and RC.
run_case() {
  local today="$1"
  OUT="$(env -i PATH="$WORK/bin:/usr/bin:/bin" HOME="$WORK" GH_TOKEN=fixture \
        GH_COMMENTS_JSON="$WORK/comments.json" ${GH_COMMENTS_FAIL:+GH_COMMENTS_FAIL=1} \
        GH_PERM_owner1="${GH_PERM_owner1-admin}" GH_PERM_drive_by="${GH_PERM_drive_by-none}" \
        GH_ISSUE_11215="${GH_ISSUE_11215-OPEN:}" GH_ISSUE_10540="${GH_ISSUE_10540-OPEN:}" \
        GH_ISSUE_10543="${GH_ISSUE_10543-OPEN:}" \
        ${today:+OWNER_ASK_TODAY=$today} bash "$PROBE" 2>&1)"
  RC=$?
  ALL_RCS+=("$RC")
  ALL_OUT+="$OUT"$'\n'
}
ALL_RCS=()
ALL_OUT=""

expect() {   # <name> <want-rc> <needle> [absent-needle]
  local name="$1" want="$2" needle="$3" absent="${4-}"
  cases=$((cases + 1))
  if [[ "$RC" -ne "$want" ]]; then fail "$name: rc=$RC, wanted $want ($(head -c 200 <<<"$OUT"))"; return; fi
  if [[ -n "$needle" ]] && ! grep -qF -- "$needle" <<<"$OUT"; then fail "$name: output lacks '$needle' ($(head -c 200 <<<"$OUT"))"; return; fi
  if [[ -n "$absent" ]] && grep -qF -- "$absent" <<<"$OUT"; then fail "$name: output contains forbidden '$absent'"; return; fi
  pass "$name"
}

reset_fixture() {
  unset GH_COMMENTS_FAIL
  GH_PERM_owner1="admin"; GH_PERM_drive_by="none"
  GH_ISSUE_11215="OPEN:"; GH_ISSUE_10540="OPEN:"; GH_ISSUE_10543="OPEN:"
  mk_comments
}

# --- instrument self-test: both helpers move their counters, and expect() can REJECT -----------------------------
p0=$passes; f0=$fails; c0=$cases
pass "self-test pass helper" >/dev/null; fail "self-test fail helper" >/dev/null
if [[ $((passes - p0)) -ne 1 || $((fails - f0)) -ne 1 ]]; then abort "assertion helpers do not move their counters"; fi
passes=$p0; fails=$f0
# expect() owns its own verdict, so the pass/fail control above cannot see it going soft: drive it once per
# rejection arm (wrong rc, missing needle, forbidden needle) and once accepting, and require exactly the right moves.
RC=5; OUT="needle-present"
expect "self-test: wrong rc" 2 "needle-present" >/dev/null
[[ $((fails - f0)) -eq 1 && $passes -eq $p0 ]] || abort "expect() accepted a wrong exit code"
expect "self-test: missing needle" 5 "absent-needle" >/dev/null
[[ $((fails - f0)) -eq 2 && $passes -eq $p0 ]] || abort "expect() accepted a missing needle"
expect "self-test: forbidden needle" 5 "needle-present" "needle-present" >/dev/null
[[ $((fails - f0)) -eq 3 && $passes -eq $p0 ]] || abort "expect() accepted a forbidden needle"
expect "self-test: accepting" 5 "needle-present" "other" >/dev/null
[[ $((fails - f0)) -eq 3 && $((passes - p0)) -eq 1 ]] || abort "expect() rejected a correct call"
passes=$p0; fails=$f0; cases=$c0

# --- row 1: A6 recorded ----------------------------------------------------------------------------------------
reset_fixture
mk_comments "owner1|S5-A5-DONE: 2026-11-01T10:00:00Z" "owner1|S6-A6-DONE: 2026-11-20T10:00:00Z"
run_case 2026-11-21
expect "row 1: a trusted S6 anchor ends the asks" 2 "Close this tracker"

# untrusted author posting the S6 anchor does not end the asks (soak open => row 4)
reset_fixture
mk_comments "drive-by|S6-A6-DONE: 2026-11-20T10:00:00Z"
run_case 2026-10-30
expect "row 1 guard: an author without write permission cannot post the done anchor" 2 "waiting on the 48-hour check" "Close this tracker"

# a trusted but malformed anchor (no ISO time) does not count
reset_fixture
mk_comments "owner1|S6-A6-DONE: soon"
run_case 2026-10-30
expect "row 1 guard: an anchor without an ISO time does not count" 2 "waiting on the 48-hour check" "Close this tracker"

# an anchor inside a code fence does not count
reset_fixture
mk_comments "owner1|$(printf '```\nS6-A6-DONE: 2026-11-20T10:00:00Z\n```')"
run_case 2026-10-30
expect "row 1 guard: a fenced anchor does not count" 2 "waiting on the 48-hour check" "Close this tracker"

# --- row 3: A5 recorded, A6 asked ------------------------------------------------------------------------------
reset_fixture
mk_comments "owner1|$(printf 'S5-A5-DONE: 2026-11-01T10:00:00Z\nCANARY-LEAK-7f3')"
run_case 2026-11-05
expect "row 3: a trusted S5 anchor asks for A6" 5 "no-known-access" "Close this tracker"
cases=$((cases + 1)); grep -qF "lapses 2026-12-10 (35 days left)" <<<"$OUT" \
  && pass "row 3: the A6 ask prints the lapse date and exactly 35 days left on 2026-11-05" \
  || fail "row 3: the A6 ask lacks the lapse date or the right days left"

# row 3 takes precedence over row 2 (anchor present, route still open, date past the dead-man)
reset_fixture
mk_comments "owner1|S5-A5-DONE: 2026-11-01T10:00:00Z"
run_case 2026-11-12
expect "row 3 beats row 2: A5 recorded while the route is open still asks A6" 5 "no-known-access" "schedule"

# --- row 2: the bridge-risk ask ---------------------------------------------------------------------------------
reset_fixture
run_case 2026-11-09
expect "row 2: from 2026-11-09 with the route open the bridge-risk ask fires" 5 "Ways out"
reset_fixture
run_case 2026-11-08
expect "row 2 boundary: the day before the dead-man stays quiet" 2 "waiting on the 48-hour check"
reset_fixture
run_case 2026-11-13
expect "row 2: after the bridge date the text says it has passed" 5 "has passed"
reset_fixture; GH_ISSUE_10540="CLOSED:NOT_PLANNED"
run_case 2026-11-09
expect "row 2: a route closed as not planned is not a landed route" 5 "Ways out"
reset_fixture; GH_ISSUE_10540="CLOSED:COMPLETED"
run_case 2026-11-09
expect "dead-man: route landed but the soak still open past 2026-11-09 still warns" 5 "has not finished" "is not done"
reset_fixture; GH_ISSUE_10540="CLOSED:COMPLETED"; GH_ISSUE_11215="CLOSED:NOT_PLANNED"
run_case 2026-11-09
expect "dead-man: a soak closed without a completed result warns" 5 "closed without a completed result"
reset_fixture; GH_ISSUE_10540="CLOSED:COMPLETED"; GH_ISSUE_11215="CLOSED:COMPLETED"
run_case 2026-11-09
expect "dead-man off: soak and route both complete means the A5 ask, not the warning" 5 "A5 is ready" "cannot start yet"
reset_fixture
run_case 2026-11-12
expect "row 2 boundary: on the bridge date itself the text says it ends" 5 "ends 2026-11-12" "The legal bridge date of"
reset_fixture
run_case 2026-12-11
expect "row 2: after the extended date the text says so" 5 "extended date of 2026-12-10 has also passed"
# soak open and past the date: the bridge-risk row must come BEFORE the soak rows
reset_fixture; GH_ISSUE_11215="OPEN:"
run_case 2026-11-10
expect "ordering: the date risk is evaluated before the soak rows" 5 "Ways out"

# --- rows 4 to 6: the soak and the route -----------------------------------------------------------------------
reset_fixture
run_case 2026-10-30
expect "row 4: the soak tracker open means wait" 2 "waiting on the 48-hour check"
reset_fixture; GH_ISSUE_11215="CLOSED:NOT_PLANNED"; GH_ISSUE_10540="CLOSED:COMPLETED"
run_case 2026-10-30
expect "row 5: a soak closed without a completed result cannot be established" 3 "was closed without a completed result"
reset_fixture; GH_ISSUE_11215="CLOSED:COMPLETED"
run_case 2026-10-30
expect "row 6: the soak passed but the route is open" 2 "blocked on #10540"

# --- row 7: the A5 ask ------------------------------------------------------------------------------------------
reset_fixture; GH_ISSUE_11215="CLOSED:COMPLETED"; GH_ISSUE_10540="CLOSED:COMPLETED"; GH_ISSUE_10543="OPEN:"
run_case 2026-10-30
expect "row 7: soak passed and route landed asks for A5" 5 "replaces the scheduler's signing key" "time-sensitive"
cases=$((cases + 1)); grep -qF "quiet window" <<<"$OUT" && grep -qF "S5-A5-DONE" <<<"$OUT" \
  && pass "row 7: with #10543 open the ask names the quiesced window and the done line" \
  || fail "row 7: the ask lacks the quiesced window or the done line"
reset_fixture; GH_ISSUE_11215="CLOSED:COMPLETED"; GH_ISSUE_10540="CLOSED:COMPLETED"; GH_ISSUE_10543="CLOSED:COMPLETED"
run_case 2026-10-30
expect "row 7: with #10543 fixed the ask drops the quiesced window" 5 "replaces the scheduler's signing key" "quiet window"

reset_fixture; GH_ISSUE_11215="CLOSED:COMPLETED"; GH_ISSUE_10540="CLOSED:COMPLETED"
run_case 2026-11-10
expect "row 7: past the dead-man date the A5 ask carries the bridge urgency" 5 "so this is time-sensitive"

# --- the A6 ask around the bridge and lapse dates; A6 without A5; malformed anchors ----------------------------------
# Equivalence note: clearing ST/REASON at the top of issue_state() is defence in depth, not a behaviour the suite can
# observe: every caller (the dead-man soak and route reads, the soak, route and replay reads) returns 3 on a failed
# read, so a stale value is never consulted. A mutant removing the clearing therefore survives, by design.
reset_fixture
mk_comments "owner1|S5-A5-DONE: 2026-11-01T10:00:00Z"
run_case 2026-11-20
expect "row 3: between the bridge date and the lapse date the A6 ask hedges and counts down" 5 "If the bridge was extended, the Inngest accepted-risk entry lapses 2026-12-10 (20 days left)"
reset_fixture
mk_comments "owner1|S5-A5-DONE: 2026-11-01T10:00:00Z"
run_case 2026-12-10
expect "row 3 boundary: on the lapse date it is 0 days left, not yet lapsed" 5 "(0 days left)" "lapsed on"
reset_fixture
mk_comments "owner1|S5-A5-DONE: 2026-11-01T10:00:00Z"
run_case 2026-12-09
expect "row 3: one day left is singular" 5 "(1 day left)" "1 days"
reset_fixture
run_case 2026-12-10
expect "row 2 boundary: on the lapse date the bridge has passed but the extended date has not" 5 "has passed" "extended date"
reset_fixture
mk_comments "owner1|S5-A5-DONE: 2026-11-01T10:00:00Z" "owner1|S6-A6-DONE: soon"
run_case 2026-11-05
expect "anchor: a malformed S6 line is named in the A6 ask" 5 "S6-A6-DONE: was found" "both recorded"
reset_fixture
mk_comments "owner1|S5-A5-DONE: 2026-11-01Tgarbage"
run_case 2026-11-10
expect "anchor: a malformed S5 line is named in the dead-man warning too" 5 "S5-A5-DONE: was found"
reset_fixture
mk_comments "owner1|S5-A5-DONE: 2026-13-45T99:99:99Z"
run_case 2026-10-30
expect "anchor: a well-shaped but impossible time is not an anchor" 2 "waiting on the 48-hour check"
reset_fixture
mk_comments "owner1|S5-A5-DONE: 2026-11-01T10:00:00Z"
run_case 2026-12-13
expect "row 3: past the lapse date the A6 ask says it lapsed" 5 "lapsed on 2026-12-10 (3 days ago)" "days left"
reset_fixture
mk_comments "owner1|S6-A6-DONE: 2026-11-20T10:00:00Z"
run_case 2026-11-10
expect "row 1 guard: A6 recorded without A5 cannot establish (never 'both recorded')" 3 "A6 is recorded" "both recorded"
reset_fixture
mk_comments "owner1|S5-A5-DONE: 2026-11-01Tgarbage"
run_case 2026-10-30
expect "anchor: a malformed time is not an anchor (soak still gates)" 2 "waiting on the 48-hour check"
reset_fixture; GH_ISSUE_11215="CLOSED:COMPLETED"; GH_ISSUE_10540="CLOSED:COMPLETED"
mk_comments "owner1|S5-A5-DONE: 2026-11-01Tgarbage"
run_case 2026-10-30
expect "anchor: a malformed S5 line is named in the A5 ask" 5 "not a real UTC time"
reset_fixture; GH_ISSUE_11215="CLOSED:COMPLETED"; GH_ISSUE_10540="CLOSED:COMPLETED"; GH_ISSUE_10543="CLOSED:NOT_PLANNED"
run_case 2026-10-30
expect "row 7: a replay-defect tracker closed as not planned is not 'fixed'" 5 "quiet window" "is fixed"

# --- read failures are exit 3, never an ask ---------------------------------------------------------------------
reset_fixture; GH_ISSUE_11215="FAIL"
run_case 2026-10-30
expect "read failure: the soak tracker read" 3 "could not read the soak tracker"
reset_fixture; GH_ISSUE_10540="FAIL"
run_case 2026-11-09
expect "read failure: the route read (row 2)" 3 "could not read the rotation route tracker"
reset_fixture; GH_ISSUE_11215="CLOSED:COMPLETED"; GH_ISSUE_10540="FAIL"
run_case 2026-10-30
expect "read failure: the route read (row 6) is not read as landed" 3 "could not read the rotation route tracker"
reset_fixture; GH_ISSUE_11215="CLOSED:COMPLETED"; GH_ISSUE_10540="CLOSED:COMPLETED"; GH_ISSUE_10543="FAIL"
run_case 2026-10-30
expect "read failure: the replay-defect read (row 7)" 3 "could not read the dashboard-send defect tracker"
reset_fixture; GH_COMMENTS_FAIL=1
run_case 2026-10-30
expect "read failure: the anchor read" 3 "could not read the owner's done lines"
unset GH_COMMENTS_FAIL
reset_fixture; GH_ISSUE_11215="GARBAGE"
run_case 2026-10-30
expect "malformed gh output is exit 3" 3 "could not read the soak tracker"
reset_fixture
run_case "not-a-date"
expect "a malformed date is exit 3" 3 "is not YYYY-MM-DD"
reset_fixture
run_case "2026-13-45"
expect "an impossible date is exit 3" 3 "does not parse"

# --- never exit 0 or 1; output hygiene --------------------------------------------------------------------------
cases=$((cases + 1))
bad_rc=""
for r in "${ALL_RCS[@]}"; do case "$r" in 2|3|5) : ;; *) bad_rc="$bad_rc $r" ;; esac; done
[[ -z "$bad_rc" ]] && pass "no case exited with a code outside 2, 3 and 5" || fail "exit codes outside 2/3/5 seen:$bad_rc"

cases=$((cases + 1))
hyg=""
for tok in owner1 drive-by hetzner- "CLO-internal" INNGEST_SIGNING_KEY INNGEST_EVENT_KEY CANARY-LEAK-7f3; do
  grep -qF -- "$tok" <<<"$ALL_OUT" && hyg="$hyg $tok"
done
[[ -z "$hyg" ]] && pass "no output line names a login, a host, a key name or internal text" || fail "output hygiene: found:$hyg"

# --- static: the anchors come from the trusted lib, never from a raw comment read -------------------------------
cases=$((cases + 1))
[[ "$(grep -cF 'trusted_verdict_bodies "$EPIC"' "$PROBE")" -ge 1 ]] \
  && pass "the probe reads anchors through trusted_verdict_bodies on the epic" \
  || fail "the probe does not call trusted_verdict_bodies on the epic"
cases=$((cases + 1))
gh_calls="$(grep -nE '(^|[^[:alnum:]_./-])gh[[:space:]]+[a-z]' "$PROBE" | grep -vE '^[0-9]+:[[:space:]]*#' | grep -v 'for need in' || true)"
if [[ "$(grep -c . <<<"$gh_calls")" -eq 1 ]] && grep -qF 'gh issue view "$1" --repo "$REPO" --json state,stateReason' <<<"$gh_calls"; then
  pass "the probe's only gh call is the state read (every comment read goes through the trusted lib)"
else
  fail "the probe makes a gh call other than the state read: $(head -c 200 <<<"$gh_calls")"
fi

echo "---"
echo "Total: $passes passed, $fails failed ($cases cases)"
if [[ $((passes + fails)) -ne "$cases" ]]; then
  printf 'ACCOUNTING: %s assertions recorded but %s cases counted — an assertion site is unpaired\n' \
    "$((passes + fails))" "$cases" >&2
  exit 1
fi
# Exact on purpose: deleting any case must red the suite (a floor with slack is attack budget).
MIN_ASSERTIONS=48
if [[ $((passes + fails)) -lt "$MIN_ASSERTIONS" ]]; then
  printf 'ANTI-VACUITY: only %s assertions ran, expected at least %s\n' "$((passes + fails))" "$MIN_ASSERTIONS" >&2
  exit 1
fi
[[ "$fails" -eq 0 ]] || exit 1
exit 0
