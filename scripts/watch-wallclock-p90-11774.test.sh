#!/usr/bin/env bash
# Suite for scripts/watch-wallclock-p90-11774.sh — the weekly required-check
# wall-clock p50/p90 probe + bound ratchet (#11774, epic #11556 Lever E). Mock
# `gh` serves workflow-runs-list / check-runs / issue / label verbs and records
# every argv; WATCH_* env seams feed fixture required-checks.txt, bounds TSVs,
# and sample sizes. One scenario per Guard Contract mutation row.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/watch-wallclock-p90-11774.sh"
WF="$SCRIPT_DIR/../.github/workflows/wallclock-p90-watch.yml"

PASS=0; FAIL=0; TOTAL=0
pass() { echo "PASS: $1"; PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); }
fatal() { printf 'FATAL: %s\n' "$*" >&2; exit 2; }
finish() { [[ "$FAIL" -eq 0 ]]; }

pass "self-test" >/dev/null; fail "self-test" >/dev/null
if [[ "$PASS" -ne 1 || "$FAIL" -ne 1 || "$TOTAL" -ne 2 ]]; then
  printf 'FATAL: verdict helpers are not dispatching\n' >&2; exit 2
fi
PASS=0; FAIL=0; TOTAL=0
if ( FAIL=1; finish ) || ! ( FAIL=0; finish ); then
  printf 'FATAL: finish() does not map FAIL to an exit status\n' >&2; exit 2
fi
if [[ "$(tail -n 1 "${BASH_SOURCE[0]}")" != 'finish || exit 1' ]]; then
  printf 'FATAL: last line is not `finish || exit 1`\n' >&2; exit 2
fi

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

TMPDIR="${TMPDIR:-/var/tmp}"; export TMPDIR
ROOT="$(mktemp -d "${TMPDIR%/}/watch-wallclock-p90.XXXXXXXX")" || fatal "mktemp failed"
assert_fixture_dir "$ROOT"
trap 'rm -rf "$ROOT"' EXIT
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Default small fixture population: three required names keep fixtures legible;
# Guard-2 scenarios rewrite WATCH_REQUIRED per scene.
REQ="$ROOT/required-checks.txt"; assert_fixture_dir "$ROOT"
printf '# fixture required set\n' > "$REQ"
printf 'test\ne2e\ncla-check\n' >> "$REQ"

# Default bounds fixture: tight 600 s bounds so hand-built latencies control the
# verdict deterministically (nearest-rank p90 over the scene's small sample).
BND="$ROOT/bounds.tsv"
printf '# fixture bounds\n' > "$BND"
printf 'test\t600\t600\t0.30\ne2e\t600\t600\t0.30\ncla-check\t600\t600\t0.30\n' >> "$BND"

N=0; MOCKD=""; OUT=""; ERR=""; RC=0
mkscene() {
  N=$((N + 1)); MOCKD="$ROOT/mock$N"; assert_fixture_dir "$MOCKD"
  mkdir -p "$MOCKD" || fatal "mkdir failed"
  : > "$MOCKD/calls"; : > "$MOCKD/bodies"; : > "$MOCKD/created"; : > "$MOCKD/edited"
  printf '[]' > "$MOCKD/issues.json"
  printf '{"number":505,"state":"OPEN","author":{"login":"github-actions"},"body":"","comments":[]}' > "$MOCKD/issue.json"
  cat > "$MOCKD/gh" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCKD/calls"
piped=""
case " $* " in *" --body-file - "*) piped="$(timeout 2 cat)" ;; esac
case "$1" in
  "api")
    ep=""; for a in "$@"; do case "$a" in repos/*) ep="$a" ;; esac; done
    case "$ep" in
      */actions/workflows/*/runs*)
        [[ -f "$MOCKD/fail_runlist" ]] && { echo "gh: boom" >&2; exit 1; }
        ev=""; case "$ep" in *"event="*) ev="${ep#*event=}"; ev="${ev%%&*}" ;; esac
        [[ -f "$MOCKD/runlist_$ev" ]] && cat "$MOCKD/runlist_$ev"; exit 0 ;;
      */check-runs*)
        [[ -f "$MOCKD/fail_api" ]] && { echo "gh: boom" >&2; exit 1; }
        sha="${ep#*/commits/}"; sha="${sha%%/check-runs*}"
        [[ -f "$MOCKD/checks_$sha.json" ]] && cat "$MOCKD/checks_$sha.json" || { echo "gh: no fixture checks $sha" >&2; exit 1; }
        exit 0 ;;
    esac ;;
  "issue")
    case "$2" in
      "list") cat "$MOCKD/issues.json"; exit 0 ;;
      "view") cat "$MOCKD/issue.json"; exit 0 ;;
      "comment") [[ -f "$MOCKD/fail_comment" ]] && { echo "gh: comment boom" >&2; exit 1; }
        printf '%s' "$piped" >> "$MOCKD/bodies"; exit 0 ;;
      "create") printf '%s' "$piped" >> "$MOCKD/created"; printf 'https://example.invalid/i/505\n'; exit 0 ;;
      "edit") printf '%s' "$piped" >> "$MOCKD/edited"; exit 0 ;;
    esac ;;
  "label")
    case "$2" in
      "create") exit 0 ;;
    esac ;;
esac
echo "mock gh: unexpected call: $*" >&2; exit 64
MOCK
  chmod +x "$MOCKD/gh"
}

# seed_run <event> <rid> <sha> <created-iso> <suite-id> : one sampled ci.yml run.
# The workflow-runs list returns id + check_suite_id + head_sha + created_at
# inline — the fixture is the post-jq TSV row the probe reads.
seed_run() {
  local ev="$1" rid="$2" sha="$3" created="$4" suite="$5"
  assert_fixture_dir "$MOCKD"
  printf '%s\t%s\t%s\t%s\n' "$rid" "$suite" "$sha" "$created" >> "$MOCKD/runlist_$ev"
}

# seed_checks <sha> <json-array> : the check-runs payload for a head sha.
seed_checks() { assert_fixture_dir "$MOCKD"; printf '{"check_runs":%s}\n' "$2" > "$MOCKD/checks_$1.json"; }

# cr <name> <conclusion> <suite-id> <started> <completed> : one check-run object.
cr() { printf '{"name":"%s","conclusion":%s,"check_suite":{"id":%s},"started_at":%s,"completed_at":%s}' \
  "$1" "$2" "$3" "$4" "$5"; }

run() {
  OUT=""; ERR=""; RC=0
  local o="$MOCKD/stdout" e="$MOCKD/stderr"
  ( cd "$REPO_ROOT" && env "PATH=$MOCKD:$PATH" "MOCKD=$MOCKD" GH_REPO=jikig-ai/soleur \
      WATCH_SAMPLE=10 WATCH_REQUIRED="$REQ" WATCH_BOUNDS="$BND" \
      bash "$SUT" "$@" ) > "$o" 2> "$e"
  RC=$?; OUT="$(cat "$o")"; ERR="$(cat "$e")"
}
ncalls() { grep -c "^$1" "$MOCKD/calls" || true; }
sentinel_of() { grep -oE 'drift=[0-9a-f]{40}' "$1" | tail -1; }

# A compact green fixture: one PR run + one MQ run, every required check green
# with latency 300 s (well inside every 600 s bound) -> zero findings.
seed_green_scene() {
  seed_run pull_request 101 shap1 "2026-11-02T08:00:00Z" 9001
  seed_checks shap1 "[$(cr test '"success"' 9001 '"2026-11-02T08:01:00Z"' '"2026-11-02T08:05:00Z"'),$(cr e2e '"success"' 9001 '"2026-11-02T08:01:00Z"' '"2026-11-02T08:05:00Z"'),$(cr cla-check '"success"' 9002 '"2026-11-02T08:01:00Z"' '"2026-11-02T08:05:00Z"')]"
  seed_run merge_group 201 sham1 "2026-11-02T09:00:00Z" 9003
  seed_checks sham1 "[$(cr test '"success"' 9003 '"2026-11-02T09:01:00Z"' '"2026-11-02T09:05:00Z"'),$(cr e2e '"success"' 9003 '"2026-11-02T09:01:00Z"' '"2026-11-02T09:05:00Z"'),$(cr cla-check '"success"' 9004 '"2026-11-02T09:01:00Z"' '"2026-11-02T09:05:00Z"')]"
}

# ---- G1-1: one (check, surface) p90 above bound x (1+margin) -> exit 1 -------
mkscene
seed_run pull_request 101 shap1 "2026-11-02T08:00:00Z" 9001
seed_run pull_request 102 shap2 "2026-11-02T08:10:00Z" 9011
# test latencies 300 s then 5000 s -> p90 = 5000 > 600*1.3 = 780
seed_checks shap1 "[$(cr test '"success"' 9001 '"2026-11-02T08:01:00Z"' '"2026-11-02T08:05:00Z"'),$(cr e2e '"success"' 9001 '"2026-11-02T08:01:00Z"' '"2026-11-02T08:05:00Z"'),$(cr cla-check '"success"' 9002 '"2026-11-02T08:01:00Z"' '"2026-11-02T08:05:00Z"')]"
seed_checks shap2 "[$(cr test '"success"' 9011 '"2026-11-02T08:11:00Z"' '"2026-11-02T09:33:20Z"'),$(cr e2e '"success"' 9011 '"2026-11-02T08:11:00Z"' '"2026-11-02T08:15:00Z"'),$(cr cla-check '"success"' 9012 '"2026-11-02T08:11:00Z"' '"2026-11-02T08:15:00Z"')]"
seed_run merge_group 201 sham1 "2026-11-02T09:00:00Z" 9003
seed_checks sham1 "[$(cr test '"success"' 9003 '"2026-11-02T09:01:00Z"' '"2026-11-02T09:05:00Z"'),$(cr e2e '"success"' 9003 '"2026-11-02T09:01:00Z"' '"2026-11-02T09:05:00Z"'),$(cr cla-check '"success"' 9004 '"2026-11-02T09:01:00Z"' '"2026-11-02T09:05:00Z"')]"
run
body="$(cat "$MOCKD/created")"
[[ "$RC" -eq 1 && "$body" == *"test"* && "$body" == *"pull_request"* \
   && "$body" == *'<!-- wallclock-p90-watch:v1 drift='* \
   && "$(ncalls 'issue create')" -eq 1 ]] \
  && pass "G1-1 breaching p90 -> exit 1, comment names (test, pull_request)" \
  || fail "G1-1 (rc=$RC creates=$(ncalls 'issue create'))"
[[ "$body" != *"e2e pull_request"* ]] \
  && pass "G1-1b in-bound check is not flagged" || fail "G1-1b"
# aggregate-only: no run id or head sha anywhere in the posted report
[[ "$body" != *"shap"* && "$body" != *" 101"* && "$body" != *" 102"* ]] \
  && pass "G1-1c report carries no run ids / head shas (ADR-057)" || fail "G1-1c"

# ---- G1-2: empty bounds TSV -> RED, never "0 checked" ------------------------
mkscene; seed_green_scene
printf '# empty fixture bounds\n' > "$BND"
run
[[ "$RC" -eq 1 && "$OUT$ERR$(cat "$MOCKD/created" 2>/dev/null)" == *"unbound"* ]] \
  && pass "G1-2 empty bounds TSV -> exit 1, every required context unbound" || fail "G1-2 (rc=$RC)"
# restore
printf '# fixture bounds\ntest\t600\t600\t0.30\ne2e\t600\t600\t0.30\ncla-check\t600\t600\t0.30\n' > "$BND"

# ---- G1-3: two breaching (check, surface) pairs -> both named -----------------
mkscene
seed_run pull_request 101 shap1 "2026-11-02T08:00:00Z" 9001
seed_run pull_request 102 shap2 "2026-11-02T08:10:00Z" 9011
seed_checks shap1 "[$(cr test '"success"' 9001 '"2026-11-02T08:01:00Z"' '"2026-11-02T08:05:00Z"'),$(cr e2e '"success"' 9001 '"2026-11-02T08:01:00Z"' '"2026-11-02T08:05:00Z"'),$(cr cla-check '"success"' 9002 '"2026-11-02T08:01:00Z"' '"2026-11-02T08:05:00Z"')]"
seed_checks shap2 "[$(cr test '"success"' 9011 '"2026-11-02T08:11:00Z"' '"2026-11-02T09:33:20Z"'),$(cr e2e '"success"' 9011 '"2026-11-02T08:11:00Z"' '"2026-11-02T08:15:00Z"'),$(cr cla-check '"success"' 9012 '"2026-11-02T08:11:00Z"' '"2026-11-02T08:15:00Z"')]"
seed_run merge_group 201 sham1 "2026-11-02T09:00:00Z" 9003
seed_checks sham1 "[$(cr test '"success"' 9003 '"2026-11-02T09:01:00Z"' '"2026-11-02T09:05:00Z"'),$(cr e2e '"success"' 9003 '"2026-11-02T09:01:00Z"' '"2026-11-02T10:25:00Z"'),$(cr cla-check '"success"' 9004 '"2026-11-02T09:01:00Z"' '"2026-11-02T09:05:00Z"')]"
run
body="$(cat "$MOCKD/created")"
[[ "$RC" -eq 1 && "$body" == *"test"*"pull_request"* && "$body" == *"e2e"*"merge_group"* ]] \
  && pass "G1-3 two breaching pairs both named in one flagged set" || fail "G1-3 (rc=$RC)"

# ---- G1-4: bound row removed for a required context -> unbound finding -------
mkscene; seed_green_scene
printf '# fixture bounds\ntest\t600\t600\t0.30\ne2e\t600\t600\t0.30\n' > "$BND"
run
[[ "$RC" -eq 1 && "$OUT$ERR$(cat "$MOCKD/created")" == *"cla-check"* ]] \
  && pass "G1-4 required context with no bound row -> unbound finding" || fail "G1-4 (rc=$RC)"
printf '# fixture bounds\ntest\t600\t600\t0.30\ne2e\t600\t600\t0.30\ncla-check\t600\t600\t0.30\n' > "$BND"

# ---- G1-5: p90 above bound but within margin band -> PASS --------------------
mkscene
seed_run pull_request 101 shap1 "2026-11-02T08:00:00Z" 9001
seed_run pull_request 102 shap2 "2026-11-02T08:10:00Z" 9011
# test latencies 300 then 750: bound 600 < p90 750 < 600*1.3=780 -> inside band
seed_checks shap1 "[$(cr test '"success"' 9001 '"2026-11-02T08:01:00Z"' '"2026-11-02T08:05:00Z"'),$(cr e2e '"success"' 9001 '"2026-11-02T08:01:00Z"' '"2026-11-02T08:05:00Z"'),$(cr cla-check '"success"' 9002 '"2026-11-02T08:01:00Z"' '"2026-11-02T08:05:00Z"')]"
seed_checks shap2 "[$(cr test '"success"' 9011 '"2026-11-02T08:11:00Z"' '"2026-11-02T08:22:30Z"'),$(cr e2e '"success"' 9011 '"2026-11-02T08:11:00Z"' '"2026-11-02T08:15:00Z"'),$(cr cla-check '"success"' 9012 '"2026-11-02T08:11:00Z"' '"2026-11-02T08:15:00Z"')]"
seed_run merge_group 201 sham1 "2026-11-02T09:00:00Z" 9003
seed_checks sham1 "[$(cr test '"success"' 9003 '"2026-11-02T09:01:00Z"' '"2026-11-02T09:05:00Z"'),$(cr e2e '"success"' 9003 '"2026-11-02T09:01:00Z"' '"2026-11-02T09:05:00Z"'),$(cr cla-check '"success"' 9004 '"2026-11-02T09:01:00Z"' '"2026-11-02T09:05:00Z"')]"
run
[[ "$RC" -eq 0 && "$(ncalls 'issue comment')" -eq 0 ]] \
  && pass "G1-5 p90 inside the margin band -> PASS (margin is load-bearing)" || fail "G1-5 (rc=$RC)"

# ---- G1-6: missing timestamps -> excluded, n drops, no breach no credit ------
mkscene
seed_run pull_request 101 shap1 "2026-11-02T08:00:00Z" 9001
seed_run pull_request 102 shap2 "2026-11-02T08:10:00Z" 9011
# run 102's test carries null timestamps -> excluded; n=1 not 2; e2e/cla lat=300
seed_checks shap1 "[$(cr test '"success"' 9001 '"2026-11-02T08:01:00Z"' '"2026-11-02T08:05:00Z"'),$(cr e2e '"success"' 9001 '"2026-11-02T08:01:00Z"' '"2026-11-02T08:05:00Z"'),$(cr cla-check '"success"' 9002 '"2026-11-02T08:01:00Z"' '"2026-11-02T08:05:00Z"')]"
seed_checks shap2 "[$(cr test '"success"' 9011 'null' 'null'),$(cr e2e '"success"' 9011 '"2026-11-02T08:11:00Z"' '"2026-11-02T08:15:00Z"'),$(cr cla-check '"success"' 9012 '"2026-11-02T08:11:00Z"' '"2026-11-02T08:15:00Z"')]"
seed_run merge_group 201 sham1 "2026-11-02T09:00:00Z" 9003
seed_checks sham1 "[$(cr test '"success"' 9003 '"2026-11-02T09:01:00Z"' '"2026-11-02T09:05:00Z"'),$(cr e2e '"success"' 9003 '"2026-11-02T09:01:00Z"' '"2026-11-02T09:05:00Z"'),$(cr cla-check '"success"' 9004 '"2026-11-02T09:01:00Z"' '"2026-11-02T09:05:00Z"')]"
run
body="$(cat "$MOCKD/created")"
[[ "$RC" -eq 0 ]] || fail "G1-6 (rc=$RC, expected 0)"
[[ "$body" == *"test | pull_request | 1"* ]] \
  && pass "G1-6 null-timestamp check run excluded; n drops to 1" || fail "G1-6 body=$(grep -c 'pull_request | 1' <<<"$body")"

# ---- G1-7: identical flagged set -> no repost, body still rewrites -----------
mkscene
seed_run pull_request 101 shap1 "2026-11-02T08:00:00Z" 9001
seed_run pull_request 102 shap2 "2026-11-02T08:10:00Z" 9011
seed_checks shap1 "[$(cr test '"success"' 9001 '"2026-11-02T08:01:00Z"' '"2026-11-02T08:05:00Z"'),$(cr e2e '"success"' 9001 '"2026-11-02T08:01:00Z"' '"2026-11-02T08:05:00Z"'),$(cr cla-check '"success"' 9002 '"2026-11-02T08:01:00Z"' '"2026-11-02T08:05:00Z"')]"
seed_checks shap2 "[$(cr test '"success"' 9011 '"2026-11-02T08:11:00Z"' '"2026-11-02T09:33:20Z"'),$(cr e2e '"success"' 9011 '"2026-11-02T08:11:00Z"' '"2026-11-02T08:15:00Z"'),$(cr cla-check '"success"' 9012 '"2026-11-02T08:11:00Z"' '"2026-11-02T08:15:00Z"')]"
seed_run merge_group 201 sham1 "2026-11-02T09:00:00Z" 9003
seed_checks sham1 "[$(cr test '"success"' 9003 '"2026-11-02T09:01:00Z"' '"2026-11-02T09:05:00Z"'),$(cr e2e '"success"' 9003 '"2026-11-02T09:01:00Z"' '"2026-11-02T09:05:00Z"'),$(cr cla-check '"success"' 9004 '"2026-11-02T09:01:00Z"' '"2026-11-02T09:05:00Z"')]"
run; sha="$(sentinel_of "$MOCKD/created")"; [[ -n "$sha" ]] || fatal "G1-7 setup: no sentinel"
[[ "$RC" -eq 1 ]] || fatal "G1-7 setup: expected breach rc=1, got $RC"
# Replay the created body back as the live tracker; second run must not repost
# the identical flagged set, but the body rewrite (issue edit) still happens.
python3 -c 'import json,sys; print(json.dumps({"number":505,"state":"OPEN","author":{"login":"github-actions"},"body":open(sys.argv[1]).read(),"comments":[]}))' \
  "$MOCKD/created" > "$MOCKD/issue.json"
printf '[{"number":505,"title":"ci-wallclock-p90: required-check wall-clock report","author":{"login":"github-actions"}}]' > "$MOCKD/issues.json"
: > "$MOCKD/calls"
run
[[ "$RC" -eq 1 && "$(ncalls 'issue comment')" -eq 0 && "$(ncalls 'issue edit')" -eq 1 \
   && "$(ncalls 'issue create')" -eq 0 ]] \
  && pass "G1-7 identical flagged set: no repost, body still rewritten" \
  || fail "G1-7 (rc=$RC comments=$(ncalls 'issue comment') edits=$(ncalls 'issue edit'))"

# ---- G1-8: no green runs listed at all -> exit 0 with a no-data report -------
# Zero listed runs is the reported missing-data state. (A surface that lists
# runs but resolves zero samples is NOT this case — see G3-1.)
mkscene
run
body="$(cat "$MOCKD/created")"
[[ "$RC" -eq 0 && ("$body" == *"No qualifying samples"* || "$OUT" == *"No qualifying samples"*) \
   && "$(ncalls 'issue comment')" -eq 0 ]] \
  && pass "G1-8 zero listed runs -> exit 0 no-data report, never a ratchet fail" \
  || fail "G1-8 (rc=$RC)"

# ---- G2-1: required-checks.txt +1 row with no bound -> unbound finding -------
mkscene; seed_green_scene
printf 'brand-new-gate\n' >> "$REQ"
run
[[ "$RC" -eq 1 && "$OUT$ERR$(cat "$MOCKD/created")" == *"brand-new-gate"* ]] \
  && pass "G2-1 added required row w/o bound -> unbound finding names it" || fail "G2-1 (rc=$RC)"
sed -i '/^brand-new-gate$/d' "$REQ"

# ---- G2-2: renamed required row carries no check run -> unmeasured finding ---
mkscene; seed_green_scene
printf 'nonexistent-required-name\n' >> "$REQ"
printf 'nonexistent-required-name\t600\t600\t0.30\n' >> "$BND"
run
[[ "$RC" -eq 1 && "$OUT$ERR$(cat "$MOCKD/created")" == *"nonexistent-required-name"* ]] \
  && pass "G2-2 zero-sample required context reported, not silently dropped" || fail "G2-2 (rc=$RC)"
sed -i '/^nonexistent-required-name$/d' "$REQ"; sed -i '/^nonexistent-required-name\t/d' "$BND"

# ---- G2-3: commented row -> population shrinks by exactly that name ----------
mkscene; seed_green_scene
printf '# fixture required set\ntest\n# e2e\ncla-check\n' > "$REQ"
run --print-report
[[ "$RC" -eq 0 && "$OUT" == *"test"* && "$OUT" == *"cla-check"* && "$OUT" != *"e2e"* ]] \
  && pass "G2-3 commented row leaves the derived population (name-level)" || fail "G2-3"
printf '# fixture required set\ntest\ne2e\ncla-check\n' > "$REQ"

# ---- G2-4: derivation returns empty while fixture file has rows -> RED -------
mkscene; seed_green_scene
printf '# every row commented\n# test\n# e2e\n' > "$REQ"
run
[[ "$RC" -ne 0 && "$(ncalls 'issue create')" -eq 0 && "$(ncalls 'issue comment')" -eq 0 ]] \
  && pass "G2-4 empty derived population can never reach a verdict" || fail "G2-4 (rc=$RC)"
printf '# fixture required set\ntest\ne2e\ncla-check\n' > "$REQ"

# ---- G2-5: non-required check-run names are excluded from measurement --------
mkscene
seed_run pull_request 101 shap1 "2026-11-02T08:00:00Z" 9001
seed_checks shap1 "[$(cr test '"success"' 9001 '"2026-11-02T08:01:00Z"' '"2026-11-02T08:05:00Z"'),$(cr e2e '"success"' 9001 '"2026-11-02T08:01:00Z"' '"2026-11-02T08:05:00Z"'),$(cr cla-check '"success"' 9002 '"2026-11-02T08:01:00Z"' '"2026-11-02T08:05:00Z"'),$(cr 'not-a-required-check' '"success"' 9001 '"2026-11-02T08:01:00Z"' '"2026-11-02T09:55:00Z"')]"
run
body="$(cat "$MOCKD/created")"
[[ "$RC" -eq 0 && "$body" != *"not-a-required-check"* ]] \
  && pass "G2-5 non-required check-run name excluded from measurement" || fail "G2-5 (rc=$RC)"

# ---- G3-1: dead surface — listed runs resolve to zero samples -> unsampled ----
# pull_request samples fine; merge_group lists a run whose check-runs ALL fail
# resolution (every check completed before the run was created — a stale batch
# on the same sha). The surface-level `unsampled` finding names the surface;
# it must NOT exit green.
mkscene
seed_run pull_request 101 shap1 "2026-11-02T08:00:00Z" 9001
seed_checks shap1 "[$(cr test '"success"' 9001 '"2026-11-02T08:01:00Z"' '"2026-11-02T08:05:00Z"'),$(cr e2e '"success"' 9001 '"2026-11-02T08:01:00Z"' '"2026-11-02T08:05:00Z"'),$(cr cla-check '"success"' 9002 '"2026-11-02T08:01:00Z"' '"2026-11-02T08:05:00Z"')]"
seed_run merge_group 201 sham1 "2026-11-02T09:00:00Z" 9003
seed_checks sham1 "[$(cr test '"success"' 9003 '"2026-11-02T08:01:00Z"' '"2026-11-02T08:05:00Z"'),$(cr e2e '"success"' 9003 '"2026-11-02T08:01:00Z"' '"2026-11-02T08:05:00Z"'),$(cr cla-check '"success"' 9004 '"2026-11-02T08:01:00Z"' '"2026-11-02T08:05:00Z"')]"
run
body="$(cat "$MOCKD/created")"
[[ "$RC" -eq 1 && "$body" == *'- unsampled: `merge_group` surface'* \
   && "$body" != *'- unmeasured: `test` (`merge_group`)'* ]] \
  && pass "G3-1 dead surface -> surface-level unsampled finding, exit 1" || fail "G3-1 (rc=$RC)"

# ---- G3-2: mis-shaped check-runs payload counts as a fetch failure ------------
# A 200 response whose body lacks the check_runs key yields zero rows per run;
# every listed run empty -> cannot-establish, exit 3 (not a green window).
mkscene; seed_green_scene
printf '{"runs":[]}\n' > "$MOCKD/checks_shap1.json"
printf '{"runs":[]}\n' > "$MOCKD/checks_sham1.json"
run
[[ "$RC" -eq 3 && "$(ncalls 'issue create')" -eq 0 && "$(ncalls 'issue comment')" -eq 0 ]] \
  && pass "G3-2 wrong-shape 200 payload is a fetch failure -> exit 3" || fail "G3-2 (rc=$RC)"

# ---- T1: standing tracker lifecycle ------------------------------------------
mkscene; seed_green_scene
run
[[ "$RC" -eq 0 && "$(ncalls 'issue create')" -eq 1 && "$(cat "$MOCKD/created")" == *"required-check wall-clock"* \
   && "$(ncalls 'issue close')" -eq 0 ]] \
  && pass "T1 green run files the standing tracker once, never closes it" || fail "T1 (rc=$RC)"

# ---- T2: foreign-authored same-title issue is never adopted ------------------
mkscene; seed_green_scene
printf '[{"number":505,"title":"ci-wallclock-p90: required-check wall-clock report","author":{"login":"mallory"}}]' > "$MOCKD/issues.json"
run
[[ "$RC" -eq 0 && "$(ncalls 'issue view')" -eq 0 && "$(ncalls 'issue edit')" -eq 0 \
   && "$(ncalls 'issue create')" -eq 1 ]] \
  && pass "T2 foreign-authored same-title issue ignored; watch files its own" || fail "T2"

# ---- T3: duplicate watch-authored trackers warn + lowest number wins ---------
mkscene; seed_green_scene
printf '[{"number":505,"title":"ci-wallclock-p90: required-check wall-clock report","author":{"login":"github-actions"}},{"number":777,"title":"ci-wallclock-p90: required-check wall-clock report","author":{"login":"github-actions[bot]"}}]' > "$MOCKD/issues.json"
run
[[ "$(grep -c '^issue view 505 ' "$MOCKD/calls")" -eq 1 \
   && "$(grep -c '^issue edit 505 ' "$MOCKD/calls")" -eq 1 && "$ERR" == *"::warning::"* ]] \
  && pass "T3 duplicate trackers warn; the lowest number is the tracker" || fail "T3"

# ---- T4: changed flagged set -> comment with new sentinel + body rewrite -----
mkscene
seed_run pull_request 101 shap1 "2026-11-02T08:00:00Z" 9001
seed_checks shap1 "[$(cr test '"success"' 9001 '"2026-11-02T08:01:00Z"' '"2026-11-02T08:05:00Z"'),$(cr e2e '"success"' 9001 '"2026-11-02T08:01:00Z"' '"2026-11-02T08:05:00Z"'),$(cr cla-check '"success"' 9002 '"2026-11-02T08:01:00Z"' '"2026-11-02T08:05:00Z"')]"
printf '[{"number":505,"title":"ci-wallclock-p90: required-check wall-clock report","author":{"login":"github-actions"}}]' > "$MOCKD/issues.json"
printf '{"number":505,"state":"OPEN","author":{"login":"github-actions"},"body":"prior body\\n<!-- wallclock-p90-watch:v1 drift=0000000000000000000000000000000000000001 -->","comments":[]}' > "$MOCKD/issue.json"
# breach: second run's test is slow -> flagged set changed vs sentinel 000...1
seed_run pull_request 102 shap2 "2026-11-02T08:10:00Z" 9011
seed_checks shap2 "[$(cr test '"success"' 9011 '"2026-11-02T08:11:00Z"' '"2026-11-02T09:33:20Z"'),$(cr e2e '"success"' 9011 '"2026-11-02T08:11:00Z"' '"2026-11-02T08:15:00Z"'),$(cr cla-check '"success"' 9012 '"2026-11-02T08:11:00Z"' '"2026-11-02T08:15:00Z"')]"
run
[[ "$RC" -eq 1 && "$(ncalls 'issue comment')" -eq 1 && "$(ncalls 'issue edit')" -eq 1 \
   && "$(sentinel_of "$MOCKD/bodies")" != "drift=0000000000000000000000000000000000000001" ]] \
  && pass "T4 changed flagged set comments once with a new sentinel; body rewritten" || fail "T4"

# ---- T14: failed drift comment must not burn the sentinel --------------------
# The comment posts BEFORE the body rewrite: a failed comment leaves the OLD
# sentinel in the un-rewritten body, so the next run reposts
# (duplicate-on-failure, never drop-on-failure).
mkscene
seed_run pull_request 101 shap1 "2026-11-02T08:00:00Z" 9001
seed_checks shap1 "[$(cr test '"success"' 9001 '"2026-11-02T08:01:00Z"' '"2026-11-02T08:05:00Z"'),$(cr e2e '"success"' 9001 '"2026-11-02T08:01:00Z"' '"2026-11-02T08:05:00Z"'),$(cr cla-check '"success"' 9002 '"2026-11-02T08:01:00Z"' '"2026-11-02T08:05:00Z"')]"
printf '[{"number":505,"title":"ci-wallclock-p90: required-check wall-clock report","author":{"login":"github-actions"}}]' > "$MOCKD/issues.json"
printf '{"number":505,"state":"OPEN","author":{"login":"github-actions"},"body":"prior body\\n<!-- wallclock-p90-watch:v1 drift=0000000000000000000000000000000000000001 -->","comments":[]}' > "$MOCKD/issue.json"
seed_run pull_request 102 shap2 "2026-11-02T08:10:00Z" 9011
seed_checks shap2 "[$(cr test '"success"' 9011 '"2026-11-02T08:11:00Z"' '"2026-11-02T09:33:20Z"'),$(cr e2e '"success"' 9011 '"2026-11-02T08:11:00Z"' '"2026-11-02T08:15:00Z"'),$(cr cla-check '"success"' 9012 '"2026-11-02T08:11:00Z"' '"2026-11-02T08:15:00Z"')]"
: > "$MOCKD/fail_comment"
run
[[ "$RC" -eq 1 && "$(ncalls 'issue comment')" -eq 1 && "$(ncalls 'issue edit')" -eq 0 \
   && ! -s "$MOCKD/bodies" && ! -s "$MOCKD/edited" ]] \
  && pass "T14a failed drift comment: body rewrite skipped, sentinel unburned" \
  || fail "T14a (rc=$RC comments=$(ncalls 'issue comment') edits=$(ncalls 'issue edit'))"
rm -f "$MOCKD/fail_comment"; : > "$MOCKD/calls"
run
[[ "$RC" -eq 1 && "$(ncalls 'issue comment')" -eq 1 && "$(ncalls 'issue edit')" -eq 1 \
   && "$(sentinel_of "$MOCKD/bodies")" =~ ^drift=[0-9a-f]{40}$ ]] \
  && pass "T14b next run reposts the drift comment then rewrites the body" || fail "T14b (rc=$RC)"

# ---- T13: ci/wallclock-p90 label contract — the digest §6 read's selector ----
mkscene; seed_green_scene
run
[[ "$RC" -eq 0 \
   && "$(grep -c '^label create ci/wallclock-p90 ' "$MOCKD/calls")" -eq 1 \
   && "$(grep -c '^issue create .*--label ci/wallclock-p90' "$MOCKD/calls")" -eq 1 ]] \
  && pass "T13a create path: label created idempotently + --label on the new tracker" \
  || fail "T13a (rc=$RC)"
[[ "$(cat "$MOCKD/created")" == *"Report refreshed: "* ]] \
  && pass "T13c report body carries the 'Report refreshed' staleness line" || fail "T13c"
# Tracker exists but its label was stripped -> the weekly body rewrite re-adds
# it (the digest's label-scoped read must never lose the standing tracker).
mkscene; seed_green_scene
printf '[{"number":505,"title":"ci-wallclock-p90: required-check wall-clock report","author":{"login":"github-actions"}}]' > "$MOCKD/issues.json"
printf '{"number":505,"state":"OPEN","author":{"login":"github-actions"},"body":"","comments":[]}' > "$MOCKD/issue.json"
run
[[ "$RC" -eq 0 && "$(grep -c '^issue edit 505 .*--add-label ci/wallclock-p90' "$MOCKD/calls")" -eq 1 ]] \
  && pass "T13b stripped tracker label self-heals via edit --add-label" || fail "T13b (rc=$RC)"

# ---- T5: malformed bounds rows -> cannot-establish, never silent skip --------
mkscene; seed_green_scene
printf 'test\tnonsense\t600\t0.30\ne2e\t600\t600\t0.30\ncla-check\t600\t600\t0.30\n' > "$BND"
run
[[ "$RC" -eq 3 && "$(ncalls 'issue create')" -eq 0 ]] \
  && pass "T5a unparsable bound number -> exit 3" || fail "T5a (rc=$RC)"
printf 'test\t600\t600\te2e\t600\t600\t0.30\ncla-check\t600\t600\t0.30\n' > "$BND"
run
[[ "$RC" -eq 3 && "$(ncalls 'issue create')" -eq 0 ]] \
  && pass "T5b wrong column count -> exit 3" || fail "T5b (rc=$RC)"
printf '# fixture bounds\ntest\t600\t600\t0.30\ne2e\t600\t600\t0.30\ncla-check\t600\t600\t0.30\n' > "$BND"

# ---- T6: same-sha suites resolve to the SAMPLED run's check suite ------------
# The sha carries two `test` check runs: the sampled run's own suite (green,
# fast) and a later retry's suite (slow). Own-suite id match must pick the
# green one — attributing the retry's check would fabricate a breach.
mkscene
seed_run pull_request 101 shap1 "2026-11-02T08:00:00Z" 9001
seed_checks shap1 "[$(cr test '"success"' 9999 '"2026-11-02T08:05:00Z"' '"2026-11-02T09:40:00Z"'),$(cr test '"success"' 9001 '"2026-11-02T08:01:00Z"' '"2026-11-02T08:05:00Z"'),$(cr e2e '"success"' 9001 '"2026-11-02T08:01:00Z"' '"2026-11-02T08:05:00Z"'),$(cr cla-check '"success"' 9002 '"2026-11-02T08:01:00Z"' '"2026-11-02T08:05:00Z"')]"
run
[[ "$RC" -eq 0 && "$(ncalls 'issue comment')" -eq 0 ]] \
  && pass "T6 same-sha retry suite: own check_suite.id wins, no fabricated breach" || fail "T6 (rc=$RC)"

# ---- T7: a check completed BEFORE the sampled run was created is unresolvable
# (it belongs to an earlier trigger batch on the same sha — a retry sees the
# stale suite). It must not be sampled for THIS run.
mkscene
seed_run pull_request 101 shap1 "2026-11-02T08:10:00Z" 9001
# cla-check completed at 08:05 < run created 08:10 -> unresolvable for this run;
# test+e2e green normally. cla-check is then unmeasured -> finding (exit 1).
seed_checks shap1 "[$(cr test '"success"' 9001 '"2026-11-02T08:11:00Z"' '"2026-11-02T08:15:00Z"'),$(cr e2e '"success"' 9001 '"2026-11-02T08:11:00Z"' '"2026-11-02T08:15:00Z"'),$(cr cla-check '"success"' 9002 '"2026-11-02T08:01:00Z"' '"2026-11-02T08:05:00Z"')]"
run
[[ "$RC" -eq 1 && "$OUT$ERR$(cat "$MOCKD/created")" == *"cla-check"* ]] \
  && pass "T7 stale-suite check (completed before run created) is not sampled" || fail "T7 (rc=$RC)"

# ---- T8: exit vocabulary ------------------------------------------------------
mkscene; run --bogus
[[ "$RC" -eq 2 && "$ERR" == *"usage:"* && ! -s "$MOCKD/calls" ]] \
  && pass "T8a unknown arg: exit 2 usage, no gh call" || fail "T8a (rc=$RC)"
mkscene; : > "$MOCKD/fail_runlist"; run
[[ "$RC" -eq 3 && "$(ncalls 'issue')" -eq 0 ]] \
  && pass "T8b run-list failure: exit 3" || fail "T8b (rc=$RC)"
mkscene; seed_green_scene; : > "$MOCKD/fail_api"; run
[[ "$RC" -eq 3 && "$(ncalls 'issue')" -eq 0 ]] \
  && pass "T8c check-runs API failure: exit 3" || fail "T8c (rc=$RC)"
mkscene; seed_green_scene
( cd "$REPO_ROOT" && env "PATH=$MOCKD:$PATH" "MOCKD=$MOCKD" GH_REPO=jikig-ai/soleur \
    WATCH_REQUIRED="$REQ" WATCH_BOUNDS="$BND" bash -x "$SUT" ) >/dev/null 2>"$MOCKD/stderr"; RC=$?
ERR="$(cat "$MOCKD/stderr")"
[[ "$RC" -eq 78 && "$ERR" == *"xtrace"* ]] && pass "T8d bash -x refused with exit 78" || fail "T8d (rc=$RC)"

# ---- T9: --dry-run prints the table, posts nothing ----------------------------
mkscene; seed_green_scene
run --dry-run
[[ "$RC" -eq 0 && "$OUT" == *"test"* && "$OUT" == *"pull_request"* \
   && "$(ncalls 'issue create')" -eq 0 && "$(ncalls 'issue comment')" -eq 0 && "$(ncalls 'issue edit')" -eq 0 ]] \
  && pass "T9 --dry-run prints the table and posts nothing" || fail "T9 (rc=$RC)"

# ---- T10: --print-report emits raw rows, zero issue calls ---------------------
mkscene; seed_green_scene
run --print-report
[[ "$RC" -eq 0 && "$OUT" == *"test"* && "$(ncalls 'issue')" -eq 0 ]] \
  && pass "T10 --print-report prints rows, no tracker reads or writes" || fail "T10 (rc=$RC)"

# ---- T11: workflow contract ---------------------------------------------------
[[ -s "$WF" ]] || fatal "workflow missing: $WF"
wf="$(grep -vE '^[[:space:]]*#' "$WF")"
wf_missing=""
grep -qF "cron: '7 9 * * 5'" <<<"$wf" || wf_missing="$wf_missing cron"
grep -qE '^permissions: \{\}' <<<"$wf" || wf_missing="$wf_missing permissions-top"
grep -qE '^      actions: read' <<<"$wf" || wf_missing="$wf_missing actions-read"
grep -qE '^      checks: read' <<<"$wf" || wf_missing="$wf_missing checks-read"
grep -qE '^      contents: read$' <<<"$wf" || wf_missing="$wf_missing contents-read"
grep -qE '^      issues: write$' <<<"$wf" || wf_missing="$wf_missing issues-write"
grep -qF 'group: wallclock-p90-watch' <<<"$wf" || wf_missing="$wf_missing concurrency"
grep -qF 'cancel-in-progress: false' <<<"$wf" || wf_missing="$wf_missing cancel"
grep -qE '^        run: bash scripts/watch-wallclock-p90-11774\.sh' <<<"$wf" || wf_missing="$wf_missing run"
grep -qE 'dry_run' <<<"$wf" || wf_missing="$wf_missing dry_run-input"
grep -qF "github.repository == 'jikig-ai/soleur'" <<<"$wf" || wf_missing="$wf_missing repo-scope"
grep -qF 'timeout-minutes: 15' <<<"$wf" || wf_missing="$wf_missing timeout"
[[ -z "$wf_missing" ]] && pass "T11 workflow contract: cron/permissions/concurrency/repo-scope/dry_run/run line" || fail "T11 missing:$wf_missing"

# ---- T12: observed gh call allowlist ------------------------------------------
bad=0
for d in "$ROOT"/mock*; do
  [[ -s "$d/calls" ]] || continue
  while IFS= read -r line; do
    case "$line" in
      "api "*|"issue list "*|"issue view "*|"issue comment "*|"issue create "*|"issue edit "*|"label create "*) ;;
      *) bad=$((bad + 1)); echo "unexpected call: $line" ;;
    esac
  done < "$d/calls"
done
[[ "$bad" -eq 0 ]] && pass "T12 gh call set is a subset of the allowlist" || fail "T12 ($bad unexpected)"

# Exit-gate check
if [[ -z "${WWP_INJECT_FAIL:-}" ]]; then
  WWP_INJECT_FAIL=1 bash "${BASH_SOURCE[0]}" >/dev/null 2>&1; nested_rc=$?
  [[ "$nested_rc" -eq 1 ]] || { printf 'FATAL: exit gate returned %s with one injected failure\n' "$nested_rc" >&2; exit 2; }
else
  fail "injected failure (exit-gate check)"
fi

echo; echo "PASS=$PASS FAIL=$FAIL TOTAL=$TOTAL"
MIN_ASSERTIONS=26
if [[ "$TOTAL" -lt "$MIN_ASSERTIONS" ]]; then
  printf 'FATAL: assertion floor breached (TOTAL=%s < %s)\n' "$TOTAL" "$MIN_ASSERTIONS" >&2; exit 2
fi
finish || exit 1
