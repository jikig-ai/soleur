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

passes=0; fails=0; asserted=0
pass() { passes=$((passes + 1)); asserted=$((asserted + 1)); printf '  PASS: %s\n' "$1"; }
fail() { fails=$((fails + 1)); asserted=$((asserted + 1)); printf '  FAIL: %s\n' "$1"; }

# --- the fake gh: answers the endpoints the probe reads from $FX/*.json, applying --jq with real jq ---
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'FAKE'
#!/usr/bin/env bash
[ "$1" = "api" ] || exit 64
ep="$2"; shift 2
jqx=""; while (( $# )); do if [ "$1" = "--jq" ]; then jqx="$2"; shift; fi; shift; done
case "$ep" in
  repos/*/pulls/9324) f="$FX/pr-9324.json" ;;
  repos/*/pulls/*/files*) n="${ep#*pulls/}"; f="$FX/files-${n%%/*}.json" ;;
  repos/*/pulls/*) f="$FX/pr-${ep##*/}.json" ;;
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
  mkdir -p "$fx"
  printf '{"merged_at":"2026-10-01T00:00:00Z","merge_commit_sha":"gate"}\n' > "$fx/pr-9324.json"
  local runs="" i pr sha actor files conc
  for ((i = 1; i <= n; i++)); do
    pr=$((100 + i)); sha="sha$pr"
    actor="User"; (( i <= bots )) && actor="Bot"
    files='[{"filename":"knowledge-base/x.md"}]'; (( i > bots && i <= bots + mach )) && files='[{"filename":"scripts/test-all.sh"}]'
    printf '%s\n' "$files" > "$fx/files-$pr.json"
    printf '{"merged_at":"2026-10-02T00:00:00Z","merge_commit_sha":"%s"}\n' "$sha" > "$fx/pr-$pr.json"
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
build_fx "$TMP/s9" 25 40;           expect "an unset GH_TOKEN is NOT YET, never a pass" 2 "GH_TOKEN is not set" "$TMP/s9" GH_TOKEN=
out="$(env FX="$TMP/s1" PATH="$TMP/bin:$PATH" GH_TOKEN=x bash -x "$PROBE" 2>&1)"; rc=$?
if [[ "$rc" == 78 ]]; then pass "xtrace with a live GH_TOKEN is refused (rc=78)"; else fail "xtrace refusal: rc=$rc"; fi

printf 'pr-battery-gate-saving-9323: %d passed, %d failed, %d assertion(s) executed\n' "$passes" "$fails" "$asserted"
PBGS_MIN_ASSERTIONS=10
if (( asserted < PBGS_MIN_ASSERTIONS )); then
  printf '[FATAL] assertion floor: executed %d < PBGS_MIN_ASSERTIONS=%d\n' "$asserted" "$PBGS_MIN_ASSERTIONS" >&2
  exit 1
fi
(( fails == 0 )) || exit 1
exit 0
