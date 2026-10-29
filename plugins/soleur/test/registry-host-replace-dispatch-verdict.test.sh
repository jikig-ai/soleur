#!/usr/bin/env bash
# Executes the `change`, `dispatch`, `verdict` and (#10650) `gate` run: bodies of
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
for sid in ("change", "verdict", "dispatch", "gate"):
    open(f"{sys.argv[2]}/{sid}.sh", "w").write(steps[sid]["run"])
PY

# gh stub: logs argv; answers the helper's three reads and the verdict's writes.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
# Anchored on argv POSITION: a verdict body quotes a `gh workflow run …` re-fire command, so a
# substring route would swallow that POST.
[[ "${1:-} ${2:-}" == "workflow run" ]] && exit 0
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
BASE_ENV=(RENDER_CHANGED= GATE_WHY= GATE_UNPROVEN= MERGE_SHA="$A" RUN_URL=https://r RUN_ATTEMPT=1 GATE_OUTCOME=success PREFLIGHT_OUTCOME=success DISPATCH_OUTCOME=success POLL_OUTCOME=success CHANGE_OUTCOME=success APPLY_RUN= APPLY_CONCLUSION= WATERMARK="$B" SUMMARY='PR #8272 (fix: thing <!-- @bob (#8272))' TARGETS=8272 PRS=8272 COMMITS="$A" RANGE=proven RANGE_NOTE= TRACKER=)
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

echo "dispatch step"
run_dispatch() {  # env overrides... -> $GH_LOG holds the `gh workflow run` argv (the reason)
  : > "$GH_LOG"; : > "$TMP/sum"; : > "$TMP/env"
  env GITHUB_STEP_SUMMARY="$TMP/sum" GITHUB_ENV="$TMP/env" MERGE_SHA="$A" MANUAL_REASON= COMMITS= RENDER_CHANGED= GATE_WHY= \
    SUMMARY='the cloud-init-registry.yml user_data at ccccccc (unchanged since the delivery watermark bbbbbbb)' "$@" \
    bash --noprofile --norc -eo pipefail "$TMP/dispatch.sh" > "$TMP/log" 2>&1; RC=$?
}
# (#7582) A delivery decided by a non-template render input has no template commit: the reason
# must carry what the gate measured, never the helper's "unchanged since the watermark".
run_dispatch RENDER_CHANGED=true GATE_WHY='rendered user_data differs (render inputs changed: zot-registry.tf)'
grep -q 'workflow run apply-web-platform-infra.yml' "$GH_LOG" && grep -q 'render inputs changed: zot-registry.tf' "$GH_LOG" && ! grep -q 'unchanged since' "$GH_LOG" && pass "D1: render-only delivery -> the reason names the gate's measurement" || fail "D1: rc=$RC $(head -c 300 "$GH_LOG")"
# With a template commit in range (e.g. a comment edit beside a digest bump) the gate's
# measurement is APPENDED, so the digest bump is still named.
run_dispatch RENDER_CHANGED=true COMMITS="$A" SUMMARY='PR #8272 (docs: comment)' GATE_WHY='rendered user_data differs (render inputs changed: cloud-init-registry.yml, zot-registry.tf)'
grep -q 'PR #8272' "$GH_LOG" && grep -q '\[gate: rendered user_data differs' "$GH_LOG" && pass "D2: template commit in range -> reason names the PR AND the gate's measurement" || fail "D2: rc=$RC $(head -c 300 "$GH_LOG")"

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

# V3b (#7582): the gate delivered on a NON-template render input (a zot digest bump in
# zot-registry.tf), so no commit in range touched the template and `commits=` is empty. That is NOT
# "unchanged": the render changed, and a refusal leaves it not live.
run_verdict JOB_STATUS=failure PREFLIGHT_OUTCOME=failure DISPATCH_OUTCOME=skipped POLL_OUTCOME=skipped SUMMARY='the cloud-init-registry.yml user_data at ccccccc' TARGETS= PRS= COMMITS= RANGE_NOTE='no commit in range touched x' RENDER_CHANGED=true GATE_WHY='rendered user_data differs (render inputs changed: zot-registry.tf)'
if grep -q 'NOT live' "$GH_LOG" && grep -q 'render inputs changed: zot-registry.tf' "$GH_LOG" && ! grep -q 'unchanged since' "$GH_LOG"; then pass "V3b: render changed via a non-template input -> NOT live naming the why, never 'unchanged'"; else fail "V3b: unchanged=$(grep -c 'unchanged since' "$GH_LOG") notlive=$(grep -c 'NOT live' "$GH_LOG")"; fi

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

# --- gate step (#10650): the compare API's 300-file cap must never default to deliver ----------
# The terraform-free cap rows. They live HERE (not only in apps/web-platform/infra/
# registry-render-delta.test.sh) because this suite is selected on EVERY edit to the workflow
# and runs in the always-on `test` job, while render-delta needs terraform and is not selected on
# a workflow-only diff (#11325). The gate runs under the SHARED refusing stub, with terraform off
# PATH and CI=1, so any render attempt fails closed instead of silently rendering.
echo "gate step (compare-API cap)"
GSTUB="$ROOT/plugins/soleur/test/lib/registry-gate-gh-stub.sh"
INFRA_REL=apps/web-platform/infra
CFG_REL="$INFRA_REL/cloud-init-registry.yml"; TF_REL="$INFRA_REL/zot-registry.tf"; VARS_REL="$INFRA_REL/variables.tf"
W=cccccccccccccccccccccccccccccccccccccccc   # the delivery watermark (BEFORE)
H=dddddddddddddddddddddddddddddddddddddddd   # github.sha (AFTER)
mkdir -p "$TMP/gbin"
cp "$GSTUB" "$TMP/gbin/gh"; chmod +x "$TMP/gbin/gh"
# No-op sleep: the retry and fetch_before delays must not cost wall time.
printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/gbin/sleep"; chmod +x "$TMP/gbin/sleep"
# PATH with every directory holding a `terraform` removed.
GATE_NO_TF_PATH=""
IFS=: read -ra _pp <<<"$PATH"
for _d in "${_pp[@]}"; do [[ -x "$_d/terraform" ]] || GATE_NO_TF_PATH="${GATE_NO_TF_PATH:+$GATE_NO_TF_PATH:}$_d"; done
GSB="$TMP/gsb"; GBF="$TMP/gbf"
reset_gate_trees() {  # head tree (= the gate's cwd) and watermark tree, both copies of the real inputs
  rm -rf "$GSB" "$GBF"; mkdir -p "$GSB/$INFRA_REL" "$GBF/$INFRA_REL" || exit 2
  for f in cloud-init-registry.yml zot-registry.tf variables.tf; do
    cp "$ROOT/$INFRA_REL/$f" "$GSB/$INFRA_REL/$f" || exit 2
    cp "$ROOT/$INFRA_REL/$f" "$GBF/$INFRA_REL/$f" || exit 2
  done
  cp "$ROOT/$INFRA_REL/registry-userdata-budget.sh" "$GSB/$INFRA_REL/" || exit 2   # K9 reaches the render arm
}
# gmutate <file> <python-expr over s>: asserts the edit LANDED (a no-op mutation reads as the baseline).
gmutate() {
  python3 - "$1" "$2" <<'PY2' || { echo "  FATAL: mutation did not land on $1"; exit 2; }
import re, sys
p, expr = sys.argv[1], sys.argv[2]
s = open(p).read()
n = eval(expr, {"re": re, "s": s})
assert n != s, "mutation changed nothing"
open(p, "w").write(n)
PY2
}
# A compare of exactly $1 files (default 300) naming NO render input: the shape a truncated list
# hides a change behind. Asserts its own preconditions, so editing a fixture to name a render
# input flips the row to FATAL rather than silently testing the file-list path.
gcompare() {
  local n="${1:-300}" j
  j="$(seq 1 "$n" | sed 's#^#docs/filler-#; s#$#.md#' | jq -R . | jq -sc '{status:"ahead", total_commits:64, files: map({filename: .})}')"
  [[ "$(jq '.files|length' <<<"$j")" -eq "$n" && "$(jq -r .status <<<"$j")" == ahead ]] || { echo "  FATAL: compare fixture precondition" >&2; exit 2; }
  [[ "$(jq -r '.files[].filename' <<<"$j" | grep -cE 'cloud-init-registry|zot-registry|variables\.tf' || true)" -eq 0 ]] || { echo "  FATAL: compare fixture names a render input" >&2; exit 2; }
  printf '%s' "$j"
}
run_gate() {  # extra env assignments... ; uses $GCOMPARE
  : > "$TMP/gout"; : > "$TMP/ggh.log"; : > "$TMP/gstub.err"
  ( cd "$GSB" && env PATH="$TMP/gbin:$GATE_NO_TF_PATH" GH_LOG="$TMP/ggh.log" STUB_ERR="$TMP/gstub.err" \
      STUB_WATERMARK="$W" STUB_AFTER="$H" STUB_COMPARE="$GCOMPARE" STUB_BEFORE="$GBF" STUB_HEAD="$GSB" \
      STUB_INPUTS="$CFG_REL $TF_REL $VARS_REL" \
      GITHUB_OUTPUT="$TMP/gout" GITHUB_REPOSITORY=jikig-ai/soleur GH_TOKEN=x CI=1 \
      EVENT_NAME=push AFTER_SHA="$H" CFG="$CFG_REL" SELF=registry-host-replace-dispatch.yml "$@" \
      bash --noprofile --norc -eo pipefail "$TMP/gate.sh" > "$TMP/glog" 2>&1 ); RC=$?
  # Harness row: a refusal means the gate asked something the stub did not expect.
  if [[ -s "$TMP/gstub.err" ]]; then fail "harness: the gate made a request the stub refused: $(head -1 "$TMP/gstub.err")"; fi
}
gout() { sed -n "s/^$1=//p" "$TMP/gout" | tail -1; }
blob_reads() { grep -cF -- '--jq select(.type=="file")|.sha' "$TMP/ggh.log" || true; }
reads_of() { grep -cF -- "contents/$1?ref=$2 --jq select" "$TMP/ggh.log" || true; }

# K1: a cap hit (EXACTLY 300 entries, none a render input) whose three inputs are byte-identical at
# both ends is NOT a delivery: six blob reads (3 inputs x 2 refs), no content fetch, no render.
reset_gate_trees; GCOMPARE="$(gcompare 300)"; run_gate
[[ "$RC" -eq 0 && "$(gout deliver)" == "false" ]] && pass "K1: 300 files + identical render-input blobs -> deliver=false, rc 0 (the old arm delivered)" || fail "K1: rc=$RC deliver=$(gout deliver) $(tail -2 "$TMP/glog" | tr '\n' ' ')"
[[ "$(blob_reads)" -eq 6 ]] && ! grep -qF -- '--jq .content' "$TMP/ggh.log" && pass "K1: exactly six blob reads (3 inputs x 2 refs) and no content fetch" || fail "K1: blob reads=$(blob_reads), content fetches=$(grep -cF -- '--jq .content' "$TMP/ggh.log" || true)"
grep -qF 'compare list truncated at 300 files' "$TMP/glog" && pass "K1: the derived cap hit is announced (::notice::)" || fail "K1: no truncation notice"
[[ -z "$(gout unproven)" && -z "$(gout render_changed)" ]] && pass "K1: no unproven / render_changed output on a proven-unchanged cap hit" || fail "K1: stray outputs"

# K1b: 299 files is a COMPLETE list: the file-list path decides and no blob is read (boundary of -ge 300).
reset_gate_trees; GCOMPARE="$(gcompare 299)"; run_gate
[[ "$RC" -eq 0 && "$(gout deliver)" == "false" && "$(blob_reads)" -eq 0 ]] && pass "K1b: 299 files is not capped -> file-list path, zero blob reads" || fail "K1b: rc=$RC deliver=$(gout deliver) blob reads=$(blob_reads)"

# K2: THE #10501 INCIDENT SHAPE (measured read-only on the live range): 300 files, the template and
# zot-registry.tf identical, variables.tf differing only by an unrelated new variable. The three
# by-value variables are equal, so the gate decides deliver=false with no render.
reset_gate_trees
printf '\nvariable "synthesized_unrelated_flag" {\n  description = "unrelated to the registry host (K2 fixture)"\n  type        = bool\n  default     = true\n}\n' >> "$GSB/$VARS_REL"
GCOMPARE="$(gcompare 300)"; run_gate
[[ "$RC" -eq 0 && "$(gout deliver)" == "false" ]] && pass "K2: #10501 replay (300 files, unrelated variables.tf block) -> deliver=false" || fail "K2: rc=$RC deliver=$(gout deliver) $(tail -2 "$TMP/glog" | tr '\n' ' ')"
[[ "$(blob_reads)" -eq 6 ]] && grep -qF -- "contents/$VARS_REL?ref=$W --jq .content" "$TMP/ggh.log" && pass "K2: variables.tf blobs differ -> it was compared BY VALUE at the watermark" || fail "K2: blob reads=$(blob_reads)"

# K3v: a cap hit HIDING a real change: registry_server_type differs. Must still deliver, through the
# existing by-value arm (a bare deliver=true would also satisfy the old cap arm; render_changed and
# the why carry the discrimination).
reset_gate_trees
gmutate "$GBF/$VARS_REL" "re.sub(r'(variable \"registry_server_type\" \\{.*?\n  default = )\"cpx22\"', r'\\1\"cx23\"', s, count=1, flags=re.S)"
GCOMPARE="$(gcompare 300)"; run_gate
[[ "$RC" -eq 0 && "$(gout deliver)" == "true" && "$(gout render_changed)" == "true" && "$(gout why)" == *"registry_server_type"* ]] && pass "K3v: cap hit + registry_server_type changed -> deliver=true, render_changed, why names it" || fail "K3v: rc=$RC deliver=$(gout deliver) render_changed=$(gout render_changed) why=$(gout why)"

# K6: UNPROVABLE. HTTP 502 on variables.tf at the HEAD ref, after two compliant inputs: refuse
# (rc 1), emit unproven=cap BEFORE exiting, write NO deliver line, name the cap and the input, and
# make exactly three attempts at that exact URL.
reset_gate_trees; GCOMPARE="$(gcompare 300)"; run_gate STUB_SHA_FAIL="$VARS_REL@$H"
[[ "$RC" -eq 1 && "$(gout unproven)" == "cap" && -z "$(gout deliver)" ]] && pass "K6: unreadable blob after a cap hit -> rc 1, unproven=cap, NO deliver line" || fail "K6: rc=$RC unproven=$(gout unproven) deliver=$(gout deliver)"
grep -q '::error::.*300 cap.*variables\.tf' "$TMP/glog" && pass "K6: the ::error:: names the cap and the unreadable input" || fail "K6: error text: $(grep '::error::' "$TMP/glog" | head -c 200)"
[[ "$(reads_of "$VARS_REL" "$H")" -eq 3 ]] && pass "K6: three attempts at the exact URL, then give up" || fail "K6: attempts=$(reads_of "$VARS_REL" "$H")"

# K6b: a render input ABSENT at the watermark (404) is unprovable too (a genuine add costs one re-fire).
reset_gate_trees; rm -f "$GBF/$TF_REL"; GCOMPARE="$(gcompare 300)"; run_gate
[[ "$RC" -eq 1 && "$(gout unproven)" == "cap" && -z "$(gout deliver)" ]] && grep -q '::error::.*zot-registry\.tf' "$TMP/glog" && pass "K6b: an input absent at one ref -> unprovable (rc 1), never 'unchanged'" || fail "K6b: rc=$RC unproven=$(gout unproven) deliver=$(gout deliver)"

# K6c: the watermark-side blob of the FIRST input fails: the gate stops at the first unprovable
# input and names IT (cloud-init-registry.yml), reading nothing for the later inputs.
reset_gate_trees; GCOMPARE="$(gcompare 300)"; run_gate STUB_SHA_FAIL="$CFG_REL@$W"
[[ "$RC" -eq 1 && "$(gout unproven)" == "cap" ]] && grep -q '::error::.*cloud-init-registry\.yml' "$TMP/glog" && [[ "$(reads_of "$TF_REL" "$W")" -eq 0 ]] && pass "K6c: first input unreadable -> named, later inputs not read" || fail "K6c: rc=$RC reads(tf)=$(reads_of "$TF_REL" "$W")"

# K9: a cap hit where the TEMPLATE blob differs reaches the render arm (terraform is off PATH under
# CI=1 here, so the head render fails closed: non-zero and NO deliver=false). Proves a changed blob
# falls into the existing downstream arms rather than being decided by the cap arm.
reset_gate_trees
gmutate "$GBF/$CFG_REL" "s.replace('#cloud-config\\n', '#cloud-config\\n# rationale-only line (K9)\\n', 1)"
GCOMPARE="$(gcompare 300)"; run_gate
[[ "$RC" -ne 0 && "$(gout deliver)" != "false" && -z "$(gout unproven)" ]] && grep -qi 'unmeasurable' "$TMP/glog" && pass "K9: a differing template blob enters the render arm (fails closed with no terraform), not the cap arm" || fail "K9: rc=$RC deliver=$(gout deliver) unproven=$(gout unproven) $(tail -2 "$TMP/glog" | tr '\n' ' ')"

# V16: the verdict for an unproven cap hit is its OWN kind, never gate-failed, and never claims the
# host is stale ("NOT live") or current ("unchanged since").
run_verdict JOB_STATUS=failure GATE_OUTCOME=failure GATE_UNPROVEN=cap PREFLIGHT_OUTCOME=skipped DISPATCH_OUTCOME=skipped POLL_OUTCOME=skipped TARGETS= PRS= COMMITS=
if [[ "$RC" -eq 0 ]] && grep -q 'kind=gate-unproven' "$GH_LOG" && ! grep -q 'kind=gate-failed' "$GH_LOG" && ! grep -q 'NOT live' "$GH_LOG" && ! grep -q 'unchanged since' "$GH_LOG"; then pass "V16: GATE_UNPROVEN=cap -> kind=gate-unproven, no NOT-live / unchanged-since claim"; else fail "V16: rc=$RC kinds=$(grep -o 'kind=[a-z-]*' "$GH_LOG" | tr '\n' ' ')"; fi
grep -q 'issue create' "$GH_LOG" && grep -qF -- 'kind=gate-unproven attempt=1 --> --label action-required' "$GH_LOG" && pass "V16: owner issue created when nothing is derivable; marker is the LAST line" || fail "V16: owner issue / marker position"
grep -q 'UNPROVEN' "$GH_LOG" && grep -q '300' "$GH_LOG" && pass "V16: the body names the cap and says UNPROVEN" || fail "V16: wording"
# V16b: a stale GATE_UNPROVEN without a gate failure must not select the arm.
run_verdict JOB_STATUS=failure GATE_OUTCOME=success GATE_UNPROVEN=cap PREFLIGHT_OUTCOME=failure DISPATCH_OUTCOME=skipped POLL_OUTCOME=skipped
grep -q 'kind=refused' "$GH_LOG" && ! grep -q 'kind=gate-unproven' "$GH_LOG" && pass "V16b: gate-unproven is keyed on the gate's own failure outcome" || fail "V16b"

# --- anti-vacuity: helper self-test + a floor that reads the append-only ledger ---------------
_cp=$PASS; _cf=$FAIL; _cl=${#FAILURES[@]}
pass "canary: pass() counts"; fail "canary: fail() counts (EXPECTED)"
if [[ "$PASS" -ne $((_cp+1)) || "$FAIL" -ne $((_cf+1)) || "${#FAILURES[@]}" -ne $((_cl+1)) ]]; then
  printf '  FATAL: the assertion helpers are not counting — every verdict above is void.\n' >&2; exit 2
fi
FAIL=$((FAIL-1)); unset 'FAILURES[-1]'
# A literal bound adjacent to the test, reported by a direct printf + exit 1 (never through the
# helpers it backstops), so scripts/guard-vacuity-floor.test.sh can construct its mutant.
if [[ "$PASS" -lt 50 ]]; then
  printf '  FATAL: anti-vacuity: only %s passes; the floor is 50 (fix the dispatch, do not lower it).\n' "$PASS" >&2
  exit 1
fi
echo "=== Results: $PASS/$((PASS+FAIL)) passed, $FAIL failed ==="
[[ "${#FAILURES[@]}" -eq 0 ]]
