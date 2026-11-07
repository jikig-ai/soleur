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
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
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
if [[ "$1 $2" == "run view" ]]; then
  # a run read: GH_RUN_<id> holds "workflowName|event|status|conclusion|displayTitle" ("FAIL" = the read fails); the probe's
  # own jq expression runs on the JSON built from it, as for the comments
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
  [[ "$json" == "workflowName,event,status,conclusion,displayTitle,headBranch,updatedAt" ]] || { echo "gh shim: unexpected --json '$json'" >&2; exit 64; }
  var="GH_RUN_$n"
  val="${!var-}"
  [[ -n "$val" ]] || { echo "gh shim: no fixture for run $n" >&2; exit 64; }
  [[ "$val" != "FAIL" ]] || exit 1
  [[ "$val" != "EMPTY" ]] || exit 0
  [[ "$val" != "GARBAGE" ]] || { echo "<html>not json</html>"; exit 0; }
  IFS='|' read -r f_name f_event f_status f_concl f_title f_branch f_updated <<<"$val"
  jq -nc --arg a "$f_name" --arg b "$f_event" --arg c "$f_status" --arg d "$f_concl" --arg e "$f_title" --arg f "$f_branch" --arg g "$f_updated" \
    '{workflowName:$a,event:$b,status:$c,conclusion:(if $d == "" then null else $d end),displayTitle:$e,headBranch:$f,updatedAt:$g}' | jq -r "$jqx"
  exit $?
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
  local today="$1" runenv=() v
  # every GH_RUN_<id> fixture reaches the probe (it runs under env -i); the id is the run number a RELAYED line names
  while IFS= read -r v; do runenv+=("$v=${!v}"); done < <(compgen -A variable GH_RUN_)
  OUT="$(env -i PATH="$WORK/bin:/usr/bin:/bin" HOME="$WORK" GH_TOKEN=fixture "${runenv[@]}" \
        GH_COMMENTS_JSON="$WORK/comments.json" ${GH_COMMENTS_FAIL:+GH_COMMENTS_FAIL=1} \
        GH_PERM_owner1="${GH_PERM_owner1-admin}" GH_PERM_drive_by="${GH_PERM_drive_by-none}" \
        GH_ISSUE_11215="${GH_ISSUE_11215-OPEN:}" GH_ISSUE_10540="${GH_ISSUE_10540-OPEN:}" \
        GH_ISSUE_10543="${GH_ISSUE_10543-OPEN:}" \
        ${today:+OWNER_ASK_TODAY=$today} bash "${PROBE_UNDER:-$PROBE}" 2>&1)"
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

# shellcheck disable=SC2034  # the GH_RUN_<id> values reach the probe through run_case's compgen loop, which shellcheck cannot follow
reset_fixture() {
  unset GH_COMMENTS_FAIL
  GH_PERM_owner1="admin"; GH_PERM_drive_by="none"
  GH_ISSUE_11215="OPEN:"; GH_ISSUE_10540="OPEN:"; GH_ISSUE_10543="OPEN:"
  # the rotation runs a RELAYED line may name ("workflowName|event|status|conclusion|displayTitle|headBranch|updatedAt"): 8001 is the
  # good one (finished 13:50, before the 13:58 owner reply the fixtures use), the rest are each refused for one reason
  # shellcheck disable=SC2086  # the names are identifiers; unquoted so that no match unsets nothing
  unset ${!GH_RUN_@}
  local ok="Inngest Key Rotate|workflow_dispatch|completed|success|inngest-key-rotate rotate signing"
  GH_RUN_8001="$ok|main|2026-11-20T13:50:00Z"
  GH_RUN_8002="Inngest Key Rotate|workflow_dispatch|completed|failure|inngest-key-rotate rotate signing|main|2026-11-20T13:50:00Z"
  GH_RUN_8003="Inngest Key Rotate|workflow_dispatch|completed|success|inngest-key-rotate plan signing|main|2026-11-20T13:50:00Z"
  GH_RUN_8004="FAIL"
  GH_RUN_8005="Apply Web Platform Infra|workflow_dispatch|completed|success|inngest-key-rotate rotate signing|main|2026-11-20T13:50:00Z"
  GH_RUN_8006="Inngest Key Rotate|workflow_dispatch|completed|success|inngest-key-rotate rotate event|main|2026-11-20T13:50:00Z"
  GH_RUN_8007="Inngest Key Rotate|workflow_dispatch|completed|success|inngest-key-rotate converge both|main|2026-11-20T13:50:00Z"
  GH_RUN_8008="Inngest Key Rotate|push|completed|success|inngest-key-rotate rotate signing|main|2026-11-20T13:50:00Z"
  GH_RUN_8009="Inngest Key Rotate|schedule|completed|success|inngest-key-rotate rotate signing|main|2026-11-20T13:50:00Z"
  GH_RUN_8010="$ok|feat-x|2026-11-20T13:50:00Z"
  GH_RUN_8011="$ok|main|2026-11-20T13:58:01Z"
  GH_RUN_8012="EMPTY"
  GH_RUN_8013="GARBAGE"
  GH_RUN_8014="$ok|main|2026-11-20T13:58:00Z"
  GH_RUN_8015="Inngest Key Rotate|workflow_dispatch|in_progress||inngest-key-rotate rotate signing|main|2026-11-20T13:50:00Z"
  GH_RUN_8016="$ok|main|not-a-time"
  GH_RUN_9="$ok|main|2026-11-20T13:50:00Z"
  GH_RUN_123456789012345678="$ok|main|2026-11-20T13:50:00Z"
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

# The A5 ask names the exact dispatch lines of the rotation route and the S5-A5-DONE handoff (#10540, ADR-307).
reset_fixture; GH_ISSUE_11215="CLOSED:COMPLETED"; GH_ISSUE_10540="CLOSED:COMPLETED"; GH_ISSUE_10543="CLOSED:COMPLETED"
run_case 2026-10-30
expect "row 7: the ask names the read-only plan rehearsal line" 5 "gh workflow run inngest-key-rotate.yml -f mode=plan -f keys=signing"
expect "row 7: the ask names the exact rotate line with its typed confirm" 5 "-f mode=rotate -f keys=signing -f confirm=ROTATE-INNGEST-SIGNING-YYYY-MM-DD -f quiet_window=true"
expect "row 7: the ask names the converge line and says it needs its own go" 5 "-f mode=converge -f keys=signing -f confirm=CONVERGE-INNGEST-SIGNING-YYYY-MM-DD" "restart-inngest-server"
expect "row 7: the ask says only the owner dispatches and that a go on another issue does not count" 5 "only you dispatch it" "run the manual"
expect "row 7: the ask is a one-reply ask: tell your session to continue A5, and the relay line names the run and quotes the reply" 5 "tell your session to continue A5" "Post that line yourself"
expect "row 7: the ask still offers the owner's own done line, as a comment on the epic" 5 "post the done line yourself: the green run prints S5-A5-DONE"
cases=$((cases + 1)); grep -qF "a DONE line posted by an agent or by the workflow does not count" <<<"$OUT" && grep -qF "S5-A5-DONE: YYYY-MM-DDTHH:MM:SSZ" <<<"$OUT" \
  && pass "row 7: the ask states the agent-posted-DONE-line rule and the done-line format" \
  || fail "row 7: the ask lacks the agent-posted-DONE-line rule or the done-line format"
expect "row 7: the ask keeps the rule that no agent dispatches the rotation" 5 "no agent runs it"
cases=$((cases + 1)); grep -qF "the Inngest host is down for a few minutes" <<<"$OUT" \
  && pass "row 7: the ask tells the owner what the go must say about downtime" \
  || fail "row 7: the ask lacks the downtime sentence"
# The go text carries everything the runbook's A5 row requires (a go composed from the daily ask must pass that precondition):
# each fragment is one case, anchored on the phrase the probe prints.
for frag in \
  "budget 10 to 15 minutes" \
  "may be skipped and not replayed" \
  "live on the host before web catches up" \
  "rejected with a 401" \
  "Stripe payment_failed send" \
  "has never been rebooted with its LUKS volume and live scheduler, so the LUKS reopen is unverified" \
  "does not add TLS or close A6" \
  "the rollback is the link flip off with its extra confirmation, and a re-rotation follows" \
  "approve only if still quiet" \
  "keys=both is a superset" \
  "gh run view <run id> --log | grep 'inngest-key-rotate verdict='" \
  "plan_blocked naming the first failing check" \
  "If the first apply itself fails, converge refuses; dispatch the rotation again" \
  "the confirm date is the UTC date of that dispatch"; do
  cases=$((cases + 1))
  grep -qF -- "$frag" <<<"$OUT" && pass "row 7 go text: carries '$frag'" || fail "row 7 go text: lacks '$frag'"
done
reset_fixture
run_case 2026-11-09
expect "row 2: the bridge-risk ask no longer points at a manual rotation procedure" 5 "Ways out" "manual key rotation procedure"

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

# --- the RELAYED record: the agent posts it from the owner's one reply, the DONE lines stay the owner's ----------------------
# A relayed record is lines after the marker (relayed-by, owner-words, owner-reply-at; S5 adds run=). The agent posts it from
# the owner's login, so the probe checks the shape, the order of the two times and (S5) that the run is a successful rotation.
relay_block() {  # <marker> <post ts> <line>...   (a line given as "-" is left out)
  local out="$1: $2" x
  shift 2
  for x in "$@"; do [[ "$x" == "-" ]] || out+=$'\n'"$x"; done
  printf '%s' "$out"
}
BY="relayed-by: agent"
WORDS="owner-words: «I know of no access beyond the measured list. CANARY-LEAK-7f3»"
REPLY="owner-reply-at: 2026-11-25T09:29:00Z"
S5WORDS='owner-words: "I dispatched it and it is green."'
S5REPLY="owner-reply-at: 2026-11-20T13:58:00Z"
GOOD6="$(relay_block S6-A6-RELAYED 2026-11-25T09:30:00Z "$BY" "$WORDS" "$REPLY")"
GOOD5="$(relay_block S5-A5-RELAYED 2026-11-20T14:00:00Z "$BY" "$S5WORDS" "$S5REPLY" run=8001)"
S5DONE="owner1|S5-A5-DONE: 2026-11-20T14:00:00Z"

reset_fixture
mk_comments "$S5DONE" "owner1|$GOOD6"
run_case 2026-11-26
expect "relay: a well-formed S6-A6-RELAYED ends the nag, and the output says it was recorded by relay" 2 "A6 recorded by relay" "was found"
expect "relay: the ended tracker is told to close, and the relayed record is not called a line the owner typed" 2 "Close this tracker" "both recorded on #10136."
expect "relay: the output says a relayed record is not a typed line, and never echoes the owner's words" 2 "not a line the owner typed" "CANARY-LEAK-7f3"
reset_fixture
mk_comments "owner1|$GOOD5" "owner1|$GOOD6"
run_case 2026-11-26
expect "relay: S5 and S6 both relayed end the nag" 2 "A5 and A6 recorded by relay"
reset_fixture
mk_comments "owner1|$GOOD5"
run_case 2026-11-26
expect "relay: a well-formed S5-A5-RELAYED stops the A5 ask and asks for A6" 5 "A5 is recorded (A5 recorded by relay)" "A5 is ready"
expect "relay: the A6 ask is a one-reply ask: tell your session to continue A6 with the owner's own sentence" 5 "tell your session to continue A6 and include that sentence" "Write it in the legal audits folder"
expect "relay: the A6 ask keeps the owner-typed DONE line and says an agent-posted DONE line does not count" 5 "S6-A6-DONE: YYYY-MM-DDTHH:MM:SSZ. A DONE line posted by an agent does not count"
expect "relay: the A6 ask says the knowledge claim is the owner's own words" 5 "in your own words" "S6-A6-RELAYED: was found"
reset_fixture
mk_comments "owner1|$GOOD5"
run_case 2026-11-26
expect "relay: a relayed S5 beats the dead-man warning (soak and route still open) and the A5 ask" 5 "A5 is recorded" "cannot start yet"
run_case 2026-11-12
expect "relay: an S5 reply dated after today is refused: named, and the dead-man warning stays" 5 "S5-A5-RELAYED: was found" "A5 is recorded"
expect "relay: the dead-man warning still says the rotation cannot start" 5 "cannot start yet"
reset_fixture
mk_comments "owner1|$(relay_block S5-A5-RELAYED 2026-11-20T14:00:00Z "$BY" 'owner-words: "done"' "$S5REPLY" run=8007)"
run_case 2026-11-26
expect "relay: a converge run of keys both is a good S5 run, and straight double quotes hold the owner's words" 5 "A5 is recorded (A5 recorded by relay)"

# a RELAYED line that is not well-formed is named, like a malformed DONE line, and records nothing
for variant in \
  "missing relayed-by|$(relay_block S6-A6-RELAYED 2026-11-25T09:30:00Z - "$WORDS" "$REPLY")" \
  "wrong relayed-by|$(relay_block S6-A6-RELAYED 2026-11-25T09:30:00Z 'relayed-by: owner' "$WORDS" "$REPLY")" \
  "missing owner-words|$(relay_block S6-A6-RELAYED 2026-11-25T09:30:00Z "$BY" - "$REPLY")" \
  "owner-words not quoted|$(relay_block S6-A6-RELAYED 2026-11-25T09:30:00Z "$BY" 'owner-words: I know of no access' "$REPLY")" \
  "owner-words empty quote|$(relay_block S6-A6-RELAYED 2026-11-25T09:30:00Z "$BY" 'owner-words: «  »' "$REPLY")" \
  "missing owner-reply-at|$(relay_block S6-A6-RELAYED 2026-11-25T09:30:00Z "$BY" "$WORDS")" \
  "owner-reply-at not a time|$(relay_block S6-A6-RELAYED 2026-11-25T09:30:00Z "$BY" "$WORDS" 'owner-reply-at: yesterday')" \
  "owner-reply-at after the post|$(relay_block S6-A6-RELAYED 2026-11-25T09:30:00Z "$BY" "$WORDS" 'owner-reply-at: 2026-11-25T09:31:00Z')" \
  "post time not a real time|$(relay_block S6-A6-RELAYED 2026-13-45T99:99:99Z "$BY" "$WORDS" "$REPLY")" \
  "only the marker line|$(relay_block S6-A6-RELAYED 2026-11-25T09:30:00Z)"; do
  reset_fixture
  mk_comments "$S5DONE" "owner1|${variant#*|}"
  run_case 2026-11-26
  expect "relay malformed (${variant%%|*}): named in the A6 ask and does not end the tracker" 5 "S6-A6-RELAYED: was found on #10136 but is malformed" "Close this tracker"
done
# the lines must follow the marker, and another marker line closes the block
reset_fixture
mk_comments "$S5DONE" "owner1|$(printf '%s\n%s\n%s\nS6-A6-RELAYED: 2026-11-25T09:30:00Z' "$BY" "$WORDS" "$REPLY")"
run_case 2026-11-26
expect "relay malformed (the lines come before the marker): not a record" 5 "S6-A6-RELAYED: was found" "Close this tracker"
reset_fixture
mk_comments "$S5DONE" "owner1|$(printf 'S6-A6-RELAYED: 2026-11-25T09:30:00Z\nS6-A6-DONE: soon\n%s\n%s\n%s' "$BY" "$WORDS" "$REPLY")"
run_case 2026-11-26
expect "relay malformed (another marker line cuts the block short): not a record" 5 "S6-A6-RELAYED: was found" "Close this tracker"
# a later well-formed relay is the record even after an earlier malformed one
reset_fixture
mk_comments "$S5DONE" "owner1|$(relay_block S6-A6-RELAYED 2026-11-25T09:30:00Z - "$WORDS" "$REPLY")" "owner1|$GOOD6"
run_case 2026-11-26
expect "relay: a well-formed record after a malformed one is the record" 2 "A6 recorded by relay" "was found"

# a fenced or HTML-commented RELAYED block is a quoted template, not a record (same lib rule as for the DONE lines)
reset_fixture
mk_comments "$S5DONE" "owner1|$(printf '```\n%s\n```' "$GOOD6")"
run_case 2026-11-26
expect "relay guard: a fenced RELAYED block is ignored (the A6 ask continues, nothing is named)" 5 "continue A6" "recorded by relay"
reset_fixture
mk_comments "$S5DONE" "owner1|$(printf '<!--\n%s\n-->' "$GOOD6")"
run_case 2026-11-26
expect "relay guard: an HTML-commented RELAYED block is ignored" 5 "continue A6" "recorded by relay"
reset_fixture
mk_comments "$S5DONE" "owner1|$(printf 'S6-A6-RELAYED: 2026-11-25T09:30:00Z\n%s\n```\n%s\n```\n%s' "$BY" "$WORDS" "$REPLY")"
run_case 2026-11-26
expect "relay guard: a fenced owner-words line does not complete the block" 5 "S6-A6-RELAYED: was found" "recorded by relay"
reset_fixture
mk_comments "drive-by|$GOOD6" "$S5DONE"
run_case 2026-11-26
expect "relay guard: an author without write permission cannot post the relayed record" 5 "continue A6" "recorded by relay"

# S6 without S5 is inconsistent, however it was recorded
reset_fixture
mk_comments "owner1|$GOOD6"
run_case 2026-11-26
expect "relay: S6-A6-RELAYED without any S5 record cannot establish" 3 "A6 is recorded" "both recorded"
reset_fixture
mk_comments "owner1|$GOOD6" "owner1|$(relay_block S5-A5-RELAYED 2026-11-20T14:00:00Z "$BY" 'owner-words: "done"' "$S5REPLY" run=8002)"
run_case 2026-11-26
expect "relay: S6-A6-RELAYED with a refused S5 relay still cannot establish" 3 "A6 is recorded"

# S5-A5-RELAYED needs a run that is a successful rotation; each refusal is named, and none records A5
for variant in \
  "run failed|run=8002" \
  "run is a plan rehearsal|run=8003" \
  "run is another workflow|run=8005" \
  "run rotates the event key only|run=8006" \
  "run id not a number|run=abc" \
  "run id with a leading zero|run=0123" \
  "run line missing|-"; do
  reset_fixture; GH_ISSUE_11215="CLOSED:COMPLETED"; GH_ISSUE_10540="CLOSED:COMPLETED"
  mk_comments "owner1|$(relay_block S5-A5-RELAYED 2026-11-20T14:00:00Z "$BY" 'owner-words: "I ran it."' "$S5REPLY" "${variant#*|}")"
  run_case 2026-11-26
  expect "relay S5 (${variant%%|*}): refused and named in the A5 ask, which keeps asking" 5 "S5-A5-RELAYED: was found on #10136 but is malformed" "A5 is recorded"
  expect "relay S5 (${variant%%|*}): the ask at the boundary is the A5 ask" 5 "A5 is ready" "recorded by relay"
done
reset_fixture; GH_ISSUE_11215="CLOSED:COMPLETED"; GH_ISSUE_10540="CLOSED:COMPLETED"
mk_comments "owner1|$(relay_block S5-A5-RELAYED 2026-11-20T14:00:00Z "$BY" 'owner-words: "I ran it."' "$S5REPLY" run=8004)"
run_case 2026-11-26
expect "relay S5: a failed read of the run is exit 3, never an ask and never a record" 3 "could not read the rotation run" "A5 is ready"
reset_fixture; GH_ISSUE_11215="CLOSED:COMPLETED"; GH_ISSUE_10540="CLOSED:COMPLETED"
mk_comments "$S5DONE" "owner1|$(relay_block S5-A5-RELAYED 2026-11-20T14:00:00Z "$BY" 'owner-words: "I ran it."' "$S5REPLY" run=8004)"
run_case 2026-11-26
expect "relay S5: with the owner's own DONE line present the run is not read at all, and A5 is not reported as relayed" 5 "A5 is recorded." "recorded by relay"

# --- the RELAYED record: boundaries and hardening --------------------------------------------------------------------
s5ctx() { reset_fixture; GH_ISSUE_11215="CLOSED:COMPLETED"; GH_ISSUE_10540="CLOSED:COMPLETED"; }
S6POST=2026-11-25T09:30:00Z
S5POST=2026-11-20T14:00:00Z
RUN1="run=8001"
# relay_block_at <marker> <post ts> <position> <required line>...: the required lines come last, the final one being the
# <position>th non-blank line after the marker (filler lines before them); BLANKS=1 puts a blank line between every two lines.
relay_block_at() {
  local m="$1" ts="$2" pos="$3" out k i x sep=$'\n'
  shift 3
  [[ -z "${BLANKS-}" ]] || sep=$'\n\n'
  out="$m: $ts"
  k=$(( pos - $# ))
  for ((i = 1; i <= k; i++)); do out+="${sep}note: filler $i"; done
  for x in "$@"; do out+="${sep}$x"; done
  printf '%s' "$out"
}

# the block is the marker line plus up to 8 non-blank lines: the last required line at line 7 or 8 counts, at line 9 it does not
for pos in 7 8 9; do
  reset_fixture
  mk_comments "$S5DONE" "owner1|$(relay_block_at S6-A6-RELAYED $S6POST $pos "$BY" "$WORDS" "$REPLY")"
  run_case 2026-11-26
  if [[ $pos -le 8 ]]; then
    expect "relay block length (S6): the last required line at non-blank line $pos is inside the block" 2 "A6 recorded by relay" "was found"
  else
    expect "relay block length (S6): the last required line at non-blank line $pos is outside the block" 5 "S6-A6-RELAYED: was found" "recorded by relay"
  fi
  s5ctx
  mk_comments "owner1|$(relay_block_at S5-A5-RELAYED $S5POST $pos "$BY" "$S5WORDS" "$S5REPLY" "$RUN1")"
  run_case 2026-11-26
  if [[ $pos -le 8 ]]; then
    expect "relay block length (S5): the last required line at non-blank line $pos is inside the block" 5 "A5 is recorded (A5 recorded by relay)" "A5 is ready"
  else
    expect "relay block length (S5): the last required line at non-blank line $pos is outside the block" 5 "S5-A5-RELAYED: was found" "recorded by relay"
  fi
done
reset_fixture
mk_comments "$S5DONE" "owner1|$GOOD6$(printf '\nnote: x%.0s' {1..20})"
run_case 2026-11-26
expect "relay block length: lines after the required ones are free" 2 "A6 recorded by relay" "was found"
# blank lines are skipped and are not counted
reset_fixture
mk_comments "$S5DONE" "owner1|$(BLANKS=1 relay_block_at S6-A6-RELAYED $S6POST 8 "$BY" "$WORDS" "$REPLY")"
run_case 2026-11-26
expect "relay block: blank lines inside the block are skipped, and do not use up the 8 lines" 2 "A6 recorded by relay" "was found"
reset_fixture
mk_comments "$S5DONE" "owner1|$(BLANKS=1 relay_block_at S6-A6-RELAYED $S6POST 9 "$BY" "$WORDS" "$REPLY")"
run_case 2026-11-26
expect "relay block: blank lines do not buy room past the 8th line" 5 "S6-A6-RELAYED: was found" "recorded by relay"

# the times: the reply may equal the post, may not be later than it, and may not be in the future
reset_fixture
mk_comments "$S5DONE" "owner1|$(relay_block S6-A6-RELAYED $S6POST "$BY" "$WORDS" "owner-reply-at: $S6POST")"
run_case 2026-11-26
expect "relay times: owner-reply-at equal to the post time is accepted" 2 "A6 recorded by relay"
reset_fixture
mk_comments "$S5DONE" "owner1|$(relay_block S6-A6-RELAYED 2026-11-26T23:59:59Z "$BY" "$WORDS" "owner-reply-at: 2026-11-26T23:59:59Z")"
run_case 2026-11-26
expect "relay times: a reply at the last second of today is not in the future" 2 "A6 recorded by relay"
reset_fixture
mk_comments "$S5DONE" "owner1|$(relay_block S6-A6-RELAYED 2026-11-27T00:00:00Z "$BY" "$WORDS" "owner-reply-at: 2026-11-27T00:00:00Z")"
run_case 2026-11-26
expect "relay times: a reply after today is in the future and is refused" 5 "S6-A6-RELAYED: was found" "recorded by relay"

# a label twice in one block is malformed, never last-wins; so is a curly quote
for variant in \
  "duplicate relayed-by|$(relay_block S6-A6-RELAYED $S6POST "$BY" "$BY" "$WORDS" "$REPLY")" \
  "relayed-by owner then agent|$(relay_block S6-A6-RELAYED $S6POST 'relayed-by: owner' "$BY" "$WORDS" "$REPLY")" \
  "duplicate owner-words|$(relay_block S6-A6-RELAYED $S6POST "$BY" "$WORDS" 'owner-words: "a second sentence"' "$REPLY")" \
  "duplicate owner-reply-at|$(relay_block S6-A6-RELAYED $S6POST "$BY" "$WORDS" "$REPLY" "$REPLY")" \
  "curly quotes are not the documented quotes|$(relay_block S6-A6-RELAYED $S6POST "$BY" 'owner-words: “I know of no access”' "$REPLY")" \
  "owner-words with an unmatched quote|$(relay_block S6-A6-RELAYED $S6POST "$BY" 'owner-words: «I know of no access"' "$REPLY")"; do
  reset_fixture
  mk_comments "$S5DONE" "owner1|${variant#*|}"
  run_case 2026-11-26
  expect "relay malformed (${variant%%|*}): named in the A6 ask and does not end the tracker" 5 "S6-A6-RELAYED: was found on #10136 but is malformed" "Close this tracker"
done
for variant in \
  "duplicate run=|$(relay_block S5-A5-RELAYED $S5POST "$BY" "$S5WORDS" "$S5REPLY" "$RUN1" "$RUN1")" \
  "two different run=|$(relay_block S5-A5-RELAYED $S5POST "$BY" "$S5WORDS" "$S5REPLY" "$RUN1" run=8002)" \
  "duplicate relayed-by|$(relay_block S5-A5-RELAYED $S5POST "$BY" "$BY" "$S5WORDS" "$S5REPLY" "$RUN1")" \
  "duplicate owner-words|$(relay_block S5-A5-RELAYED $S5POST "$BY" "$S5WORDS" "$S5WORDS" "$S5REPLY" "$RUN1")" \
  "duplicate owner-reply-at|$(relay_block S5-A5-RELAYED $S5POST "$BY" "$S5WORDS" "$S5REPLY" "$S5REPLY" "$RUN1")"; do
  s5ctx
  mk_comments "owner1|${variant#*|}"
  run_case 2026-11-26
  expect "relay S5 malformed (${variant%%|*}): named, and the A5 ask continues" 5 "S5-A5-RELAYED: was found on #10136 but is malformed" "recorded by relay"
done

# the S5 run: what gh returns decides it
for variant in \
  "run was a push|run=8008" \
  "run was a schedule|run=8009" \
  "run was on another branch|run=8010" \
  "run finished after the owner reply|run=8011" \
  "run still in progress|run=8015" \
  "run id of 19 digits|run=1234567890123456789" \
  "run id of 21 digits|run=123456789012345678901" \
  "run id empty|run="; do
  s5ctx
  mk_comments "owner1|$(relay_block S5-A5-RELAYED $S5POST "$BY" "$S5WORDS" "$S5REPLY" "${variant#*|}")"
  run_case 2026-11-26
  expect "relay S5 (${variant%%|*}): refused, named, and the A5 ask continues" 5 "S5-A5-RELAYED: was found on #10136 but is malformed" "recorded by relay"
done
for variant in \
  "run finished exactly at the owner reply|run=8014" \
  "a one-digit run id|run=9" \
  "an 18-digit run id|run=123456789012345678"; do
  s5ctx
  mk_comments "owner1|$(relay_block S5-A5-RELAYED $S5POST "$BY" "$S5WORDS" "$S5REPLY" "${variant#*|}")"
  run_case 2026-11-26
  expect "relay S5 (${variant%%|*}): accepted" 5 "A5 is recorded (A5 recorded by relay)" "A5 is ready"
done
for variant in \
  "gh returns nothing|run=8012" \
  "gh returns something that is not a run|run=8013" \
  "gh returns an unparseable completion time|run=8016"; do
  s5ctx
  mk_comments "owner1|$(relay_block S5-A5-RELAYED $S5POST "$BY" "$S5WORDS" "$S5REPLY" "${variant#*|}")"
  run_case 2026-11-26
  expect "relay S5 (${variant%%|*}): a read failure, exit 3, not a malformed record and not an ask" 3 "could not read the rotation run" "was found"
done

# the marker is case-sensitive
for variant in \
  "lowercase marker|$(relay_block s6-a6-relayed $S6POST "$BY" "$WORDS" "$REPLY")" \
  "mixed-case marker|$(relay_block S6-A6-Relayed $S6POST "$BY" "$WORDS" "$REPLY")"; do
  reset_fixture
  mk_comments "$S5DONE" "owner1|${variant#*|}"
  run_case 2026-11-26
  expect "relay (${variant%%|*}): not a marker at all, nothing is named or recorded" 5 "continue A6" "was found"
done

# several blocks in one comment, in both orders
MAL6="$(relay_block S6-A6-RELAYED $S6POST - "$WORDS" "$REPLY")"
reset_fixture
mk_comments "$S5DONE" "owner1|$GOOD6"$'\n'"$MAL6"
run_case 2026-11-26
expect "relay blocks: a good block followed by a malformed one records the act" 2 "A6 recorded by relay" "was found"
reset_fixture
mk_comments "$S5DONE" "owner1|$MAL6"$'\n'"$GOOD6"
run_case 2026-11-26
expect "relay blocks: a malformed block followed by a good one records the act" 2 "A6 recorded by relay" "was found"
s5ctx
mk_comments "owner1|$(relay_block S5-A5-RELAYED $S5POST "$BY" "$S5WORDS" "$S5REPLY" run=8004)"$'\n'"$GOOD5"
run_case 2026-11-26
expect "relay blocks: a failed run read on the first block does not hide a good second block" 5 "A5 is recorded (A5 recorded by relay)"
s5ctx
mk_comments "owner1|$GOOD5"$'\n'"$(relay_block S5-A5-RELAYED $S5POST "$BY" "$S5WORDS" "$S5REPLY" run=8004)"
run_case 2026-11-26
expect "relay blocks: a good first block records the act whatever follows" 5 "A5 is recorded (A5 recorded by relay)"
s5ctx
mk_comments "owner1|$(relay_block S5-A5-RELAYED $S5POST "$BY" "$S5WORDS" "$S5REPLY" run=8002)"$'\n'"$(relay_block S5-A5-RELAYED $S5POST "$BY" "$S5WORDS" "$S5REPLY" run=8004)"
run_case 2026-11-26
expect "relay blocks: a refused block then a failed read is a read failure, exit 3" 3 "could not read the rotation run"
s5ctx
mk_comments "owner1|$(relay_block S5-A5-RELAYED $S5POST "$BY" "$S5WORDS" "$S5REPLY" run=8004)"$'\n'"$(relay_block S5-A5-RELAYED $S5POST "$BY" "$S5WORDS" "$S5REPLY" run=8002)"
run_case 2026-11-26
expect "relay blocks: a failed read then a refused block is still a read failure, exit 3" 3 "could not read the rotation run"

# DONE and RELAYED together
reset_fixture
mk_comments "$S5DONE" "owner1|S6-A6-DONE: 2026-11-25T09:30:00Z" "owner1|$GOOD6"
run_case 2026-11-26
expect "relay with DONE: S6 DONE plus a good RELAYED is recorded by the DONE line" 2 "both recorded on #10136." "recorded by relay"
reset_fixture
mk_comments "$S5DONE" "owner1|S6-A6-DONE: soon" "owner1|$GOOD6"
run_case 2026-11-26
expect "relay with DONE: a malformed S6 DONE plus a good RELAYED is recorded by relay, and the bad DONE is not named" 2 "A6 recorded by relay" "was found"
reset_fixture
mk_comments "$S5DONE" "owner1|$MAL6" "owner1|S6-A6-DONE: 2026-11-25T09:30:00Z"
run_case 2026-11-26
expect "relay with DONE: a malformed RELAYED plus a good S6 DONE is recorded by the DONE line, and the bad RELAYED is not named" 2 "both recorded on #10136." "was found"
reset_fixture
mk_comments "owner1|S6-A6-DONE: soon" "owner1|$GOOD6"
run_case 2026-11-26
expect "relay with DONE: with no S5 record a good RELAYED beside a malformed S6 DONE cannot establish, and the bad DONE is not named" 3 "A6 is recorded" "S6-A6-DONE: was found"
reset_fixture
mk_comments "owner1|$MAL6" "owner1|S6-A6-DONE: 2026-11-25T09:30:00Z"
run_case 2026-11-26
expect "relay with DONE: with no S5 record a good S6 DONE beside a malformed RELAYED cannot establish, and the bad RELAYED is not named" 3 "A6 is recorded" "S6-A6-RELAYED: was found"
s5ctx
mk_comments "$S5DONE" "owner1|$(relay_block S5-A5-RELAYED $S5POST "$BY" "$S5WORDS" "$S5REPLY" run=8002)"
run_case 2026-11-26
expect "relay with DONE: a good S5 DONE beside a refused S5 RELAYED asks for A6 and does not name the relay" 5 "A5 is recorded." "malformed"

# Behaviour pin for "a DONE line posted by an agent does not count": the probe cannot see who typed a line, so a DONE line that
# is followed by relay lines is read as the DONE line it is and never as a relayed record. The asks say the rule rests on agents.
reset_fixture
mk_comments "owner1|S5-A5-DONE: 2026-11-20T14:00:00Z"$'\n'"$BY"$'\n'"$S5WORDS"$'\n'"$S5REPLY"
run_case 2026-11-26
expect "relay pin: a DONE line followed by relayed-by lines is a DONE line, never a relayed record" 5 "A5 is recorded." "recorded by relay"
reset_fixture
mk_comments "$S5DONE" "owner1|S6-A6-DONE: 2026-11-25T09:30:00Z"$'\n'"$BY"$'\n'"$WORDS"$'\n'"$REPLY"
run_case 2026-11-26
expect "relay pin: an S6 DONE line followed by relayed-by lines is a DONE line, never a relayed record" 2 "both recorded on #10136." "recorded by relay"

# the asks say plainly what the probe cannot enforce, and who writes the knowledge claim
reset_fixture
mk_comments "owner1|$GOOD5"
run_case 2026-11-26
expect "asks: the A6 ask says the probe cannot see who typed a line" 5 "The check cannot see who typed a line, because every comment comes from your login"
expect "asks: the A6 ask says the knowledge claim is never drafted by Soleur" 5 "Soleur never drafts it: it posts only the sentence you type yourself" "does not write it for you"
s5ctx
run_case 2026-11-26
expect "asks: the A5 ask says the probe cannot see who typed a line" 5 "The check cannot see who typed a line, because every comment comes from your login"
expect "asks: the A5 ask states which run counts for a relayed record" 5 "successful signing-key rotate or converge on main that finished before your reply"

# the final internal-error arm: a probe whose body returns something other than 2, 3 or 5 (here, a lib that exits the body's
# subshell) must still exit 3 with a named internal error, never 0 or 1
FORCED="$WORK/forced"
assert_fixture_dir "$FORCED"
mkdir -p "$FORCED/scripts/followthroughs" "$FORCED/scripts/lib" || abort "mkdir failed"
cp "$PROBE" "$FORCED/scripts/followthroughs/probe.sh" || abort "cp failed"
cp "$REPO_ROOT/scripts/lib/relayed-verdict.sh" "$FORCED/scripts/lib/relayed-verdict.sh" || abort "cp failed"
for forced_rc in 0 1 7; do
  printf 'exit %s\n' "$forced_rc" > "$FORCED/scripts/lib/trusted-verdict.sh"
  reset_fixture
  PROBE_UNDER="$FORCED/scripts/followthroughs/probe.sh"
  run_case 2026-10-30
  unset PROBE_UNDER
  expect "exit contract: a body that returns $forced_rc lands on the internal-error arm, exit 3" 3 "probe internal error (rc=$forced_rc)"
done

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

# --- the xtrace refusal: tracing with the credential bound must refuse (78) before anything is read ---------------
reset_fixture
OUT="$(env -i PATH="$WORK/bin:/usr/bin:/bin" HOME="$WORK" GH_TOKEN=fixture GH_COMMENTS_JSON="$WORK/comments.json" bash -x "$PROBE" 2>&1)"; RC=$?
expect "xtrace: tracing with a live credential refuses with 78" 78 "refusing to trace with a live credential set"

# --- never exit 0 or 1; output hygiene --------------------------------------------------------------------------
cases=$((cases + 1))
bad_rc=""
# a census over zero cases would pass vacuously: the cases above must have recorded their exit codes, and each of the three allowed codes was seen
for r in "${ALL_RCS[@]}"; do case "$r" in 2|3|5) : ;; *) bad_rc="$bad_rc $r" ;; esac; done
[[ "${#ALL_RCS[@]}" -ge 100 && " ${ALL_RCS[*]} " == *" 2 "* && " ${ALL_RCS[*]} " == *" 3 "* && " ${ALL_RCS[*]} " == *" 5 "* ]] \
  || bad_rc="$bad_rc (census saw only ${#ALL_RCS[@]} cases or lacks one of 2, 3, 5)"
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
# The four *_LINE constants hold the dispatch lines and the verdict-reading recipe the A5 ask prints as TEXT; they are authored constants, never executed.
gh_calls="$(grep -nE '(^|[^[:alnum:]_./-])gh[[:space:]]+[a-z]' "$PROBE" | grep -vE '^[0-9]+:[[:space:]]*#' | grep -vE '^[0-9]+:(PLAN|ROTATE|CONVERGE|VERDICT)_LINE="' | grep -v 'for need in' || true)"
if [[ "$(grep -c . <<<"$gh_calls")" -eq 2 ]] && grep -qF 'gh issue view "$1" --repo "$REPO" --json state,stateReason' <<<"$gh_calls" \
  && grep -qF 'gh run view "$1" --repo "$REPO" --json workflowName,event,status,conclusion,displayTitle' <<<"$gh_calls"; then
  pass "the probe's only gh calls are the state read and the rotation-run read (every comment read goes through the trusted lib)"
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
MIN_ASSERTIONS=180
if [[ $((passes + fails)) -lt "$MIN_ASSERTIONS" ]]; then
  printf 'ANTI-VACUITY: only %s assertions ran, expected at least %s\n' "$((passes + fails))" "$MIN_ASSERTIONS" >&2
  exit 1
fi
[[ "$fails" -eq 0 ]] || exit 1
exit 0
