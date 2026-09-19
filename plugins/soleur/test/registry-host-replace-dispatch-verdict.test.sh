#!/usr/bin/env bash
# Executes the `change` and `verdict` run: bodies of
# .github/workflows/registry-host-replace-dispatch.yml (#8279) under the runner's own shell
# (`bash --noprofile --norc -eo pipefail`) with a stubbed `gh`, and pins what each arm DECIDES.
#
# Why this exists: the verdict's composition lives in YAML, where nothing unit-tests it — the
# one real defect the review panel found on #8279 (the "unchanged since the watermark" sentence
# keyed on `prs=` instead of `commits=`) sat in exactly that code path. A body-grep AC pins
# spelling; this pins behaviour. Every fixture is synthesized (cq-test-fixtures-synthesized-only).
#
# Auto-globbed by scripts/test-all.sh (`plugins/soleur/test/*.test.sh`).

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WF="$ROOT/.github/workflows/registry-host-replace-dispatch.yml"

PASS=0; FAIL=0; FAILURES=()
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); FAILURES+=("$1"); }

TMP="$(mktemp -d)" || exit 2
trap 'rm -rf "$TMP"' EXIT

# Extract the two bodies with PyYAML (the interpreter the alarm guard already uses).
python3 - "$WF" "$TMP" <<'PY' || { echo "  FATAL: could not extract run bodies"; exit 2; }
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
steps = {s.get("id"): s for s in d["jobs"]["dispatch-replace"]["steps"]}
for sid in ("change", "verdict"):
    open(f"{sys.argv[2]}/{sid}.sh", "w").write(steps[sid]["run"])
PY

# gh stub: logs argv; answers the helper's three reads and the verdict's writes.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
case " $* " in
  *" issue list "*) printf '%s' "${GH_OWNER:-}" ;;
  *" issue create "*) echo "https://github.com/jikig-ai/soleur/issues/4242" ;;
  *" issue edit "*) exit "${GH_EDIT_RC:-0}" ;;
  *"/comments -f body="*) exit "${GH_POST_RC:-0}" ;;
  *"/pulls "*|*"/pulls") echo '[{"number":8272,"merged_at":"2026-09-19T00:00:00Z"}]' ;;
  *"compare/"*) printf '%s' "${GH_COMPARE:-{\"status\":\"ahead\",\"total_commits\":1,\"commits\":[{\"sha\":\"cccccccccccccccccccccccccccccccccccccccc\"}]}}" ;;
  *" -f path="*) echo '[{"sha":"cccccccccccccccccccccccccccccccccccccccc","commit":{"message":"fix: thing <!-- @bob (#8272)"}}]' ;;
  *) echo "stub: unrouted gh call: $*" >&2; exit 64 ;;
esac
STUB
chmod +x "$TMP/bin/gh"
export PATH="$TMP/bin:$PATH" GH_LOG="$TMP/gh.log" GITHUB_REPOSITORY=jikig-ai/soleur GITHUB_RUN_ID=1
A=cccccccccccccccccccccccccccccccccccccccc; B=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb

run_change() {  # env assignments... -> $TMP/out (GITHUB_OUTPUT), $TMP/log
  : > "$TMP/out"; : > "$TMP/sum"; : > "$GH_LOG"
  ( cd "$ROOT" && env GITHUB_OUTPUT="$TMP/out" GITHUB_STEP_SUMMARY="$TMP/sum" CFG=apps/web-platform/infra/cloud-init-registry.yml "$@" \
      bash --noprofile --norc -eo pipefail "$TMP/change.sh" > "$TMP/log" 2>&1 ); RC=$?
}
out() { sed -n "s/^$1=//p" "$TMP/out"; }
BASE_ENV=(MERGE_SHA="$A" RUN_URL=https://r RUN_ATTEMPT=1 GATE_OUTCOME=success PREFLIGHT_OUTCOME=success DISPATCH_OUTCOME=success POLL_OUTCOME=success CHANGE_OUTCOME=success APPLY_RUN= APPLY_CONCLUSION= WATERMARK="$B" SUMMARY='PR #8272 (fix: thing <!-- @bob (#8272))' TARGETS=8272 PRS=8272 COMMITS="$A" RANGE=proven RANGE_NOTE= TRACKER=)
run_verdict() {  # env overrides... -> $TMP/log ; $GH_LOG holds every gh argv (bodies included)
  : > "$GH_LOG"; : > "$TMP/sum"
  env GITHUB_STEP_SUMMARY="$TMP/sum" "${BASE_ENV[@]}" "$@" bash --noprofile --norc -eo pipefail "$TMP/verdict.sh" > "$TMP/log" 2>&1; RC=$?
}
body() { sed -n 's/^api -X POST [^ ]* -f body=//p' "$GH_LOG" | head -1; }

echo "change step"
run_change EVENT_NAME=push BEFORE="$B" AFTER="$A" TRACKER='#7960'
[[ "$RC" -eq 0 && "$(out targets)" == "8272 7960" ]] && pass "C1: targets = derived PR ∪ tracker, '#' stripped" || fail "C1: rc=$RC targets=$(out targets)"
grep -q '^summary=PR #8272' "$TMP/out" && pass "C1: every helper key lands in GITHUB_OUTPUT" || fail "C1: summary missing from GITHUB_OUTPUT"
grep -q '^```$' "$TMP/sum" && pass "C1: the step summary copy is fenced (contributor text)" || fail "C1: summary not fenced"
run_change EVENT_NAME=push BEFORE="$B" AFTER="$A" TRACKER=' #08272 '
[[ "$(out targets)" == "8272" ]] && pass "C2: whitespace + leading-zero tracker dedupes against the derived PR" || fail "C2: targets=$(out targets)"
run_change EVENT_NAME=push BEFORE="$B" AFTER="$A" TRACKER='PR-1'
[[ "$(out targets)" == "8272" ]] && grep -q '::warning::tracker input' "$TMP/log" && pass "C3: a non-numeric tracker is dropped with a ::warning::" || fail "C3: targets=$(out targets)"
GH_COMPARE='{"status":"diverged","total_commits":2,"commits":[]}' run_change EVENT_NAME=workflow_dispatch BEFORE="$B" AFTER="$A" TRACKER=7960
[[ "$(out targets)" == "7960" && "$(out range)" == "unproven" ]] && pass "C4: manual re-fire + unproven range -> targets are the tracker only" || fail "C4: targets=$(out targets) range=$(out range)"
GH_COMPARE='{"status":"diverged","total_commits":2,"commits":[]}' run_change EVENT_NAME=push BEFORE="$B" AFTER="$A" TRACKER=
[[ "$(out targets)" == "8272" ]] && grep -q '::warning::attribution unproven' "$TMP/log" && pass "C5: push + unproven keeps the derived PR and warns" || fail "C5: targets=$(out targets)"

echo "verdict step"
run_verdict JOB_STATUS=failure PREFLIGHT_OUTCOME=failure DISPATCH_OUTCOME=skipped POLL_OUTCOME=skipped
[[ "$RC" -eq 0 ]] && grep -q 'issues/8272/comments' "$GH_LOG" && pass "V1: refused -> one comment on the derived PR, rc 0" || fail "V1: rc=$RC $(head -c 200 "$GH_LOG")"
b="$(body)"
[[ "$b" == "Delivery REFUSED by the preflight for"* ]] && pass "V1: WHAT = refused" || fail "V1: body=$(printf '%s' "$b" | head -c 80)"
[[ "$b" == *"&lt;!-- &#64;bob"* && "$b" != *"<!-- @bob"* ]] && pass "V1: summary is HTML-escaped on the markdown surface" || fail "V1: raw <!-- reached the body"
[[ "$b" == *"are NOT live."* ]] && pass "V1: not-live sentence on the refused arm" || fail "V1: no not-live sentence"
grep -q -- '-f tracker=8272' "$GH_LOG" && pass "V1: re-fire command names the first target" || fail "V1: re-fire lacks the tracker"
grep -q 'refusing predicate' "$GH_LOG" && pass "V1: P1/P5 predicate notes on the refused arm" || fail "V1: predicate notes missing"
[[ "$(tail -1 "$GH_LOG")" == *"<!-- registry-delivery run=1 kind=refused attempt=1 -->" ]] && pass "V1: marker is the LAST line of the body" || fail "V1: marker not last"

run_verdict JOB_STATUS=failure PREFLIGHT_OUTCOME=failure DISPATCH_OUTCOME=skipped POLL_OUTCOME=skipped SUMMARY='commit ccccccc (direct push)' TARGETS= PRS= COMMITS="$A"
if grep -q 'issue create' "$GH_LOG" && grep -q 'are NOT live' "$GH_LOG" && ! grep -q 'unchanged since' "$GH_LOG"; then pass "V2: proven range, unattributed direct push -> NOT live (commits non-empty), owner issue created"; else fail "V2: $(grep -c 'issue create' "$GH_LOG") creates; unchanged=$(grep -c 'unchanged since' "$GH_LOG")"; fi
grep -q -- '--label action-required' "$GH_LOG" && grep -q 'issue edit .* --add-label domain/engineering' "$GH_LOG" && pass "V2: created with action-required; classification labels added afterwards" || fail "V2: label wiring"

run_verdict JOB_STATUS=failure PREFLIGHT_OUTCOME=failure DISPATCH_OUTCOME=skipped POLL_OUTCOME=skipped SUMMARY='the cloud-init-registry.yml user_data at ccccccc' TARGETS= PRS= COMMITS= RANGE_NOTE='no commit in range touched x'
grep -q "user_data is unchanged since the delivery watermark ${B:0:7}; this run was not applied" "$GH_LOG" && ! grep -q 'are NOT live' "$GH_LOG" && pass "V3: proven range with NO config touch -> 'unchanged' sentence, never NOT live" || fail "V3: sentence wrong"

GH_OWNER=4100 run_verdict JOB_STATUS=failure PREFLIGHT_OUTCOME=failure DISPATCH_OUTCOME=skipped POLL_OUTCOME=skipped TARGETS= PRS= COMMITS=
grep -q 'issues/4100/comments' "$GH_LOG" && ! grep -q 'issue create' "$GH_LOG" && pass "V4: an open owner issue receives the verdict instead of a new issue" || fail "V4: dedupe against the open owner issue failed"

run_verdict JOB_STATUS=failure PREFLIGHT_OUTCOME=failure DISPATCH_OUTCOME=skipped POLL_OUTCOME=skipped CHANGE_OUTCOME=cancelled SUMMARY= TARGETS= PRS= COMMITS= RANGE= TRACKER='../evil'
[[ "$RC" -eq 0 ]] && grep -q '::warning::dropping non-numeric verdict target' "$TMP/log" && grep -q 'issue create' "$GH_LOG" && pass "V5: change step killed + non-numeric raw tracker -> dropped loudly, owner issue still created" || fail "V5: rc=$RC"
grep -q 'attribution unavailable: derivation step cancelled' "$GH_LOG" && pass "V5: attribution-unavailable note when the change step did not succeed" || fail "V5: note missing"

run_verdict JOB_STATUS=failure PREFLIGHT_OUTCOME=failure DISPATCH_OUTCOME=skipped POLL_OUTCOME=skipped TARGETS= PRS= COMMITS= TRACKER='PR-1'
! grep -q '::warning::dropping' "$TMP/log" && pass "V6: a raw tracker is NOT re-read when the change step succeeded and emptied targets" || fail "V6: raw tracker re-read"

run_verdict JOB_STATUS=cancelled POLL_OUTCOME=cancelled APPLY_RUN=555
grep -q 'kind=cancelled' "$GH_LOG" && grep -q 'apply run 555; read it first' "$GH_LOG" && ! grep -q 'NOT live' "$GH_LOG" && ! grep -q 'refusing predicate' "$GH_LOG" && pass "V7: cancelled -> names the apply run, no NOT-live claim, no predicate notes" || fail "V7"

run_verdict JOB_STATUS=failure POLL_OUTCOME=failure APPLY_RUN=999 APPLY_CONCLUSION=failure
grep -q 'kind=apply-failed' "$GH_LOG" && grep -q 'run 999 concluded failure' "$GH_LOG" && ! grep -q 'NOT live' "$GH_LOG" && pass "V8: apply-failed -> names run + conclusion, no NOT-live claim" || fail "V8"

run_verdict JOB_STATUS=failure DISPATCH_OUTCOME=failure POLL_OUTCOME=skipped
grep -q 'kind=dispatch-failed' "$GH_LOG" && grep -q 'READ IT BEFORE RE-FIRING' "$GH_LOG" && pass "V9: dispatch-failed carries the double-replace remediation" || fail "V9"

run_verdict JOB_STATUS=success APPLY_CONCLUSION=unverified
grep -q 'kind=unverified' "$GH_LOG" && ! grep -q 'NOT live' "$GH_LOG" && pass "V10: unverified (green job) posts, without a NOT-live claim" || fail "V10"

run_verdict JOB_STATUS=failure GATE_OUTCOME=failure PREFLIGHT_OUTCOME=skipped DISPATCH_OUTCOME=skipped POLL_OUTCOME=skipped
grep -q 'kind=gate-failed' "$GH_LOG" && pass "V11: a gate failure has its own arm" || fail "V11: $(grep -o 'kind=[a-z-]*' "$GH_LOG" | head -1)"

run_verdict JOB_STATUS=failure GATE_OUTCOME=skipped PREFLIGHT_OUTCOME=skipped DISPATCH_OUTCOME=skipped POLL_OUTCOME=skipped
grep -q 'kind=undetermined' "$GH_LOG" && grep -q 'gate=skipped' "$GH_LOG" && pass "V12: checkout-failure shape -> undetermined, printing the outcomes" || fail "V12"

GH_POST_RC=1 run_verdict JOB_STATUS=failure PREFLIGHT_OUTCOME=failure DISPATCH_OUTCOME=skipped POLL_OUTCOME=skipped
[[ "$RC" -eq 1 ]] && grep -q '::error::could not post the delivery verdict to #8272' "$TMP/log" && pass "V13: a failed post is a ::error:: and exit 1, never swallowed" || fail "V13: rc=$RC"

run_verdict JOB_STATUS=failure PREFLIGHT_OUTCOME=failure DISPATCH_OUTCOME=skipped POLL_OUTCOME=skipped RANGE=unproven RANGE_NOTE='compare rc=22'
grep -q 'attribution unproven: compare rc=22' "$GH_LOG" && pass "V14: an unproven range is labelled 'unproven'" || fail "V14"
run_verdict JOB_STATUS=failure PREFLIGHT_OUTCOME=failure DISPATCH_OUTCOME=skipped POLL_OUTCOME=skipped RANGE_NOTE='PR #8272 attributed by commit subject, not by the API'
grep -q 'attribution note: PR #8272' "$GH_LOG" && ! grep -q 'attribution unproven' "$GH_LOG" && pass "V15: a note on a PROVEN range is a note, not 'unproven'" || fail "V15"

# --- anti-vacuity: helper self-test + a floor that reads the append-only ledger ---------------
_cp=$PASS; _cf=$FAIL; _cl=${#FAILURES[@]}
pass "canary: pass() counts"; fail "canary: fail() counts (EXPECTED)"
if [[ "$PASS" -ne $((_cp+1)) || "$FAIL" -ne $((_cf+1)) || "${#FAILURES[@]}" -ne $((_cl+1)) ]]; then
  printf '  FATAL: the assertion helpers are not counting — every verdict above is void.\n' >&2; exit 2
fi
FAIL=$((FAIL-1)); unset 'FAILURES[-1]'
# A literal bound adjacent to the test, reported by a direct printf + exit 1 (never through the
# helpers it backstops), so scripts/guard-vacuity-floor.test.sh can construct its mutant.
if [[ "$PASS" -lt 30 ]]; then
  printf '  FATAL: anti-vacuity: only %s passes; the floor is 30 (fix the dispatch, do not lower it).\n' "$PASS" >&2
  exit 1
fi
echo "=== Results: $PASS/$((PASS+FAIL)) passed, $FAIL failed ==="
[[ "${#FAILURES[@]}" -eq 0 ]]
