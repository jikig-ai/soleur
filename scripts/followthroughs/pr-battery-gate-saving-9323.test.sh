#!/usr/bin/env bash
# pr-battery-gate-saving-9323.test.sh — drives the soak probe through a fake `gh` and pins its exit-code
# contract (0 PASS, 1 FAIL, 2 NOT YET, 3 CANNOT ESTABLISH, 78 xtrace refusal). An exit-code contract
# nothing drives is a comment.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE="$REPO_ROOT/scripts/followthroughs/pr-battery-gate-saving-9323.sh"
command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 2; }
TMP="$(mktemp -d "$TMPDIR/pbg-saving.XXXXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT

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
passes=0; fails=0; asserted=0
pass() { passes=$((passes + 1)); asserted=$((asserted + 1)); printf '  PASS: %s\n' "$1"; }
fail() { fails=$((fails + 1)); asserted=$((asserted + 1)); printf '  FAIL: %s\n' "$1"; }

# --- the fake gh: answers the endpoints the probe reads from $FX/*.json, applying --jq with real jq ---
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'FAKE'
#!/usr/bin/env bash
[ "$1" = "api" ] || exit 64
ep="$2"; shift 2
printf '%s\n' "$ep" >> "$FX/requests.log"
jqx=""; while (( $# )); do if [ "$1" = "--jq" ]; then jqx="$2"; shift; fi; shift; done
case "$ep" in
  repos/*/pulls/9324) f="$FX/pr-9324.json" ;;
  repos/*/pulls/*/files*) n="${ep#*pulls/}"; f="$FX/files-${n%%/*}.json" ;;
  repos/*/pulls?head=*)
    # head-branch resolution: fixture is head-<branch>.json with '/' folded to '_'; an absent fixture
    # is a branch with no PR (empty list), not an API failure. The empty list must flow through the
    # --jq tail below like a real response, so it is materialised rather than printed directly.
    b="${ep##*head=}"; b="${b%%&*}"; b="${b#*:}"
    f="$FX/head-${b//\//_}.json"
    [ -f "$f" ] || { f="$FX/.empty-head.json"; printf '[]\n' > "$f"; } ;;
  repos/*/pulls/*) f="$FX/pr-${ep##*/}.json" ;;
  repos/*/actions/workflows/ci.yml/runs?event=pull_request*page=*)
    pg="${ep##*page=}"; pg="${pg%%&*}"
    if [ "$pg" = 1 ]; then f="$FX/runs.json"
    else f="$FX/runs-p$pg.json"; [ -f "$f" ] || { f="$FX/.empty-runs.json"; printf '{"workflow_runs":[]}\n' > "$f"; }
    fi ;;
  repos/*/actions/workflows/ci.yml/runs?event=pull_request*) f="$FX/runs.json" ;;
  repos/*/actions/workflows/ci.yml/runs?event=push*) f="$FX/push-${ep##*head_sha=}.json" ;;
  repos/*/actions/runs/*/jobs*) r="${ep#*runs/}"; f="$FX/jobs-${r%%/*}.json" ;;
  *) exit 64 ;;
esac
[ -f "$f" ] || exit 1
if [ -n "$jqx" ]; then jq -r "$jqx" "$f"; else cat "$f"; fi
FAKE
chmod +x "$TMP/bin/gh"

# build_fx <dir> <n-runs> <minutes-per-run> [bot-count] [machinery-count] [escape-pr]
build_fx() {
  local fx="$1" n="$2" mins="$3" bots="${4:-0}" mach="${5:-0}" esc="${6:-}"
  assert_fixture_dir "$fx"
  mkdir -p "$fx"
  printf '{"merged_at":"2026-10-01T00:00:00Z","merge_commit_sha":"gate"}\n' > "$fx/pr-9324.json"
  local runs="" i pr sha actor files conc
  for ((i = 1; i <= n; i++)); do
    pr=$((100 + i)); sha="sha$pr"
    actor="User"; (( i <= bots )) && actor="Bot"
    files='[{"filename":"docs/x.md"}]'; (( i > bots && i <= bots + mach )) && files='[{"filename":"scripts/test-all.sh"}]'
    printf '%s\n' "$files" > "$fx/files-$pr.json"
    printf '{"merged_at":"2026-10-02T00:00:00Z","merge_commit_sha":"%s","state":"closed"}\n' "$sha" > "$fx/pr-$pr.json"
    conc="success"; [ "$esc" = "$pr" ] && conc="failure"
    printf '{"workflow_runs":[{"conclusion":"%s"}]}\n' "$conc" > "$fx/push-$sha.json"
    # one real job of $mins minutes, one skipped job carrying a huge duration that must NOT count,
    # one test-scripts job with a 10-minute queue wait
    jq -n --argjson m "$mins" '{jobs:[
      {name:"test-scripts (1/7)", conclusion:"success", created_at:"2026-10-02T00:00:00Z", started_at:"2026-10-02T00:10:00Z", completed_at:("2026-10-02T00:10:00Z" | fromdateiso8601 + ($m * 60) | todateiso8601)},
      {name:"skipped-job", conclusion:"skipped", created_at:"2026-10-02T00:00:00Z", started_at:"2026-10-02T00:00:00Z", completed_at:"2026-10-02T09:00:00Z"}]}' > "$fx/jobs-$i.json"
    runs="$runs{\"id\":$i,\"conclusion\":\"success\",\"actor\":{\"type\":\"$actor\"},\"pull_requests\":[{\"number\":$pr}]},"
  done
  printf '{"workflow_runs":[%s]}\n' "${runs%,}" > "$fx/runs.json"
}

# expect <label> <want-rc> <want-text> <fx> [env...]
expect() {
  local label="$1" want="$2" text="$3" fx="$4"; shift 4
  local out rc
  out="$(env FX="$fx" PATH="$TMP/bin:$PATH" GH_TOKEN=x "$@" bash "$PROBE" 2>&1)"; rc=$?
  if [[ "$rc" == "$want" && "$out" == *"$text"* ]]; then pass "$label (rc=$rc)"; else fail "$label: want rc=$want containing '$text', got rc=$rc: $(printf '%s' "$out" | head -3 | tr '\n' '|')"; fi
}

build_fx "$TMP/s1" 25 40;           expect "PASS: 25 runs at 40 runner-min (>= 20 under the 76 baseline), a skipped job is not counted" 0 "PASS" "$TMP/s1"
build_fx "$TMP/s2" 25 70;           expect "FAIL: mean 70 is not 20 below the baseline" 1 "FAIL: mean" "$TMP/s2"
build_fx "$TMP/s3" 25 40 0 0 110;   expect "FAIL: a green PR whose merge-commit push run is red is an escape" 1 "ESCAPE: PR 110" "$TMP/s3"
build_fx "$TMP/s4" 5 40;            expect "NOT YET: 5 qualifying runs (< 20)" 2 "NOT YET" "$TMP/s4"
build_fx "$TMP/s5" 25 40; printf '{"merged_at":null}\n' > "$TMP/s5/pr-9324.json"
                                    expect "NOT YET: the gate PR is not merged" 2 "not merged" "$TMP/s5"
build_fx "$TMP/s6" 25 40; rm -f "$TMP/s6/runs.json"
                                    expect "CANNOT ESTABLISH: the runs read fails" 3 "CANNOT ESTABLISH" "$TMP/s6"
build_fx "$TMP/s7" 25 40 0 10;      expect "machinery-touching PRs are excluded (25 - 10 = 15 < 20)" 2 "NOT YET: 15" "$TMP/s7"
build_fx "$TMP/s8" 25 40 10;        expect "bot PRs are excluded (25 - 10 = 15 < 20)" 2 "NOT YET: 15" "$TMP/s8"
build_fx "$TMP/s9" 25 40;           expect "an unset GH_TOKEN is CANNOT ESTABLISH, never a pass" 3 "GH_TOKEN is not set" "$TMP/s9" GH_TOKEN=
# --- boundaries and the qualification rules a reviewer found unpinned -----------------------------------
build_fx "$TMP/b1" 20 56;           expect "boundary: exactly 20 runs at a 56.0 mean (= baseline - 20) PASSES" 0 "PASS" "$TMP/b1"
build_fx "$TMP/b2" 20 56.1;         expect "boundary: a 56.1 mean is NOT 20 below the baseline" 1 "FAIL: mean" "$TMP/b2"
build_fx "$TMP/b3" 19 40;           expect "boundary: 19 qualifying runs is NOT YET" 2 "NOT YET: 19" "$TMP/b3"
build_fx "$TMP/b4" 25 2; sed -i 's/"conclusion":"success"/"conclusion":"failure"/g' "$TMP/b4/runs.json"
                                    expect "red runs are excluded: 25 cheap FAILED runs must not read as a saving" 2 "NOT YET: 0" "$TMP/b4"
build_fx "$TMP/b5" 25 40; for i in $(seq 1 25); do sed -i 's/test-scripts (1\/7)/lint/' "$TMP/b5/jobs-$i.json"; done
                                    expect "a run with no test-scripts job measures nothing and is excluded" 2 "NOT YET: 0" "$TMP/b5"
build_fx "$TMP/b6" 25 40; rm -f "$TMP/b6/push-sha101.json"; printf '{"workflow_runs":[]}\n' > "$TMP/b6/push-sha101.json"
                                    expect "an absent push run is NOT YET, never 'no escape'" 2 "no completed push run" "$TMP/b6"
build_fx "$TMP/b7" 25 40; printf '{"workflow_runs":[{"conclusion":"timed_out"}]}\n' > "$TMP/b7/push-sha102.json"
                                    expect "a timed_out push run on a green PR is an escape" 1 "ESCAPE: PR 102" "$TMP/b7"
build_fx "$TMP/b8" 25 40; bash -c 'FX="'"$TMP/b8"'" PATH="'"$TMP/bin"':$PATH" GH_TOKEN=x bash "'"$PROBE"'"' >/dev/null 2>&1
if grep -q 'created=%3E2026-10-01T00:00:00Z' "$TMP/b8/requests.log" && grep -q 'status=completed' "$TMP/b8/requests.log" && grep -q 'event=pull_request' "$TMP/b8/requests.log"; then
  pass "the runs query is windowed after the merge time, completed and pull_request-only"
else fail "the runs query lost its created=/status=/event= parameters: $(grep 'ci.yml/runs?event=pull_request' "$TMP/b8/requests.log" | head -1)"; fi
# --- ADR-276 S3 (#9728): the draft light run must not move this probe -----------------------------------------------
# With CI_DRAFT_LIGHT on, a draft push's pull_request run concludes `failure` (Option R: the `test` aggregator is red by
# design) and its four heavy families (test-scripts*, test-webplat, shard-totality-mutations) are SKIPPED. Neither the
# baseline mean nor the escape count may see such a run: the probe's own rules (conclusion `success` only, a test-scripts*
# job that actually ran) already exclude it. These rows pin that, so a later edit to either rule cannot turn the soak of
# #9323 into a measurement of the draft policy. add_light <fx> <n-runs> <conclusion> appends <n> light runs for PRs 101..
add_light() {
  local fx="$1" n="$2" conc="$3" i pr
  for ((i = 1; i <= n; i++)); do
    pr=$((100 + i))
    jq -n '{jobs:[
      {name:"test-scripts (1/7)", conclusion:"skipped", created_at:"2026-10-02T00:00:00Z", started_at:"2026-10-02T00:00:00Z", completed_at:"2026-10-02T00:00:00Z"},
      {name:"lint", conclusion:"success", created_at:"2026-10-02T00:00:00Z", started_at:"2026-10-02T00:00:00Z", completed_at:"2026-10-02T10:00:00Z"}]}' > "$fx/jobs-$((900 + i)).json"
    jq --arg c "$conc" --argjson id "$((900 + i))" --argjson pr "$pr" \
      '.workflow_runs += [{id: $id, conclusion: $c, actor: {type: "User"}, pull_requests: [{number: $pr}]}]' "$fx/runs.json" > "$fx/runs.tmp" && mv "$fx/runs.tmp" "$fx/runs.json"
  done
}
build_fx "$TMP/c1" 25 40; add_light "$TMP/c1" 25 failure
                                    expect "S3: 25 failed light draft runs (600 runner-min each, heavy families skipped) leave the mean at 40.0 over 25 runs" 0 "qualifying_runs=25 mean_runner_min=40.0" "$TMP/c1"
build_fx "$TMP/c2" 25 40; add_light "$TMP/c2" 25 success
                                    expect "S3: even a light run reading success is excluded (no test-scripts job ran): still 25 runs, mean 40.0" 0 "qualifying_runs=25 mean_runner_min=40.0" "$TMP/c2"
build_fx "$TMP/c3" 25 40 0 0 110; add_light "$TMP/c3" 25 failure
                                    expect "S3: a real escape (push run red) is still found beside the light runs" 1 "ESCAPE: PR 110" "$TMP/c3"
build_fx "$TMP/c4" 0 40; add_light "$TMP/c4" 25 failure
                                    expect "S3: only failed light runs is NOT YET 0 (they are not a saving, not an escape)" 2 "NOT YET: 0" "$TMP/c4"
# --- pagination + head-branch resolution (the window-starvation fix) --------------------------------
# One runs page is ~24 h of PRs and `pull_requests` is populated only while a PR is open, so a merged
# PR's run needs the pulls?head= lookup. Page 1 here is 100 runs (90 bots + 10 head-resolvable humans);
# page 2 carries 15 runs with the association present. Both halves are needed for a PASS.
job40() { jq -n '{jobs:[{name:"test-scripts (1/7)", conclusion:"success", created_at:"2026-10-02T00:00:00Z", started_at:"2026-10-02T00:10:00Z", completed_at:"2026-10-02T00:50:00Z"}]}'; }
mk_pr_files() {  # <fx> <pr>
  printf '[{"filename":"docs/x.md"}]\n' > "$1/files-$2.json"
  printf '{"merged_at":"2026-10-02T00:00:00Z","merge_commit_sha":"psha%s","state":"closed"}\n' "$2" > "$1/pr-$2.json"
  printf '{"workflow_runs":[{"conclusion":"success"}]}\n' > "$1/push-psha$2.json"
}
build_paged_fx() {  # <fx>
  local fx="$1" i pr runs=""
  assert_fixture_dir "$fx"
  build_fx "$fx" 0 40                     # pr-9324.json; runs.json is overwritten below
  for ((i = 1; i <= 90; i++)); do
    runs="$runs{\"id\":$((90000 + i)),\"conclusion\":\"success\",\"actor\":{\"type\":\"Bot\"},\"pull_requests\":[{\"number\":$((900 + i))}],\"head_branch\":\"bot$i\"},"
  done
  for ((i = 1; i <= 10; i++)); do
    pr=$((300 + i)); mk_pr_files "$fx" "$pr"; job40 > "$fx/jobs-$((70000 + i)).json"
    printf '[{"number":%s}]\n' "$pr" > "$fx/head-pb$i.json"
    runs="$runs{\"id\":$((70000 + i)),\"conclusion\":\"success\",\"actor\":{\"type\":\"User\"},\"pull_requests\":[],\"head_branch\":\"pb$i\",\"head_repository\":{\"full_name\":\"jikig-ai/soleur\"}},"
  done
  printf '{"workflow_runs":[%s]}\n' "${runs%,}" > "$fx/runs.json"
  runs=""
  for ((i = 1; i <= 15; i++)); do
    pr=$((400 + i)); mk_pr_files "$fx" "$pr"; job40 > "$fx/jobs-$((80000 + i)).json"
    runs="$runs{\"id\":$((80000 + i)),\"conclusion\":\"success\",\"actor\":{\"type\":\"User\"},\"pull_requests\":[{\"number\":$pr}],\"head_branch\":\"pbx$i\"},"
  done
  printf '{"workflow_runs":[%s]}\n' "${runs%,}" > "$fx/runs-p2.json"
}
build_paged_fx "$TMP/pg1"
expect "pagination + head resolution: 10 head-resolved on page 1 + 15 direct on page 2 PASS" 0 "qualifying_runs=25" "$TMP/pg1"
if grep -q 'page=2' "$TMP/pg1/requests.log"; then pass "a full page 1 triggers a page-2 fetch"; else fail "the probe did not paginate past a full page 1"; fi
if grep -q 'pulls?head=' "$TMP/pg1/requests.log"; then pass "merged-PR runs resolve through pulls?head="; else fail "no head-branch PR lookup was issued"; fi
build_fx "$TMP/h1" 20 40
jq '.workflow_runs += [{id:70001,conclusion:"success",actor:{type:"User"},pull_requests:[],head_branch:"merged-a",head_repository:{full_name:"jikig-ai/soleur"}}]
                   | .workflow_runs += [{id:70002,conclusion:"success",actor:{type:"User"},pull_requests:[],head_branch:"no-pr",head_repository:{full_name:"jikig-ai/soleur"}}]
                   | .workflow_runs += [{id:70003,conclusion:"success",actor:{type:"User"},pull_requests:[],head_branch:"fork-br",head_repository:{full_name:"ext-contrib/soleur"}}]' \
   "$TMP/h1/runs.json" > "$TMP/h1/runs.tmp" && mv "$TMP/h1/runs.tmp" "$TMP/h1/runs.json"
printf '[{"number":555}]\n' > "$TMP/h1/head-merged-a.json"
printf '[{"filename":"scripts/test-all.sh"}]\n' > "$TMP/h1/files-555.json"
expect "head resolution: a machinery-touching PR found via head_branch is still excluded" 0 "qualifying_runs=20" "$TMP/h1"
if grep -q 'pulls?head=jikig-ai:merged-a' "$TMP/h1/requests.log"; then pass "the head lookup names owner:branch"; else fail "no head lookup for merged-a: $(cat "$TMP/h1/requests.log")"; fi
if grep -q 'pulls?head=jikig-ai:no-pr' "$TMP/h1/requests.log"; then pass "a branch with no PR gets a lookup, then is skipped"; else fail "no head lookup for no-pr"; fi
if grep -q 'pulls?head=jikig-ai:fork-br' "$TMP/h1/requests.log"; then fail "a fork-head run must never be resolved — its head_branch can collide with a same-repo branch"; else pass "a run whose head_repository is a fork gets no head lookup"; fi
build_fx "$TMP/d1" 20 40
# a qualifying PR closed UNMERGED: no merge commit will ever exist, so it must drop out of the escape
# check rather than pend forever (head-branch resolution makes this state reachable; pre-resolution it
# was not — the association only existed on open PRs). NB: the API still reports the TEST-merge sha in
# merge_commit_sha on closed-unmerged PRs (verified on #11038) — the discriminator is merged_at=null.
printf '{"merged_at":null,"merge_commit_sha":"tms105","state":"closed"}\n' > "$TMP/d1/pr-105.json"
expect "a closed-unmerged qualifying PR drops out of the escape check" 0 "closed unmerged" "$TMP/d1"
build_fx "$TMP/d2" 20 40
# the twin state that must NOT drop: an OPEN qualifying PR — its merge_commit_sha is the test merge, no
# push run can exist for it yet, so it pends (it may merge) rather than disappearing from the arm.
printf '{"merged_at":null,"merge_commit_sha":"tms105","state":"open"}\n' > "$TMP/d2/pr-105.json"
printf '{"workflow_runs":[]}\n' > "$TMP/d2/push-tms105.json"
expect "an open qualifying PR still pends on its future merge-commit push run" 2 "no completed push run" "$TMP/d2"
if grep -qE 'page=[2-9]' "$TMP/s1/requests.log"; then fail "a short page 1 must not trigger a second-page fetch"; else pass "a short page 1 (<100 runs) does not paginate"; fi
out="$(env FX="$TMP/s1" PATH="$TMP/bin:$PATH" GH_TOKEN=x bash -x "$PROBE" 2>&1)"; rc=$?
if [[ "$rc" == 78 ]]; then pass "xtrace with a live GH_TOKEN is refused (rc=78)"; else fail "xtrace refusal: rc=$rc"; fi

printf 'pr-battery-gate-saving-9323: %d passed, %d failed, %d assertion(s) executed\n' "$passes" "$fails" "$asserted"
PBGS_MIN_ASSERTIONS=22
if (( asserted < PBGS_MIN_ASSERTIONS )); then
  printf '[FATAL] assertion floor: executed %d < PBGS_MIN_ASSERTIONS=%d\n' "$asserted" "$PBGS_MIN_ASSERTIONS" >&2
  exit 1
fi
(( fails == 0 )) || exit 1
exit 0
