#!/usr/bin/env bash
# drift-autoclose-verdict-9061.sh — follow-through probe for the drift-autoclose
# fresh-plan gate (PR #11296, issue #9061, leak issue #11294).
#
# On the FIRST apply-deploy-pipeline-fix run whose apply job actually executes
# the "Post-apply full-root drift plan" step, verify:
#
#   1. the step emitted its verdict line — `::notice::Post-apply full-root plan
#      is clean` (exit 0) or `... still shows changes — every drift issue stays
#      open.` (exit 2). `::error::Post-apply full-root plan FAILED` or silence
#      is a FAIL: the gate produced no readable evidence.
#   2. no raw terraform plan output leaked into the step's log — the step keeps
#      PLAN_OUTPUT in a shell variable by design because plan refresh lines
#      print random_id key bytes in base64url (#11294). Only the ^Plan: count
#      line may leave the step, and it goes to the step SUMMARY, which has no
#      public API — so that leg is verified by the verdict line plus this
#      absence check, not by reading the summary.
#   3. when the verdict is "still shows changes", infra-drift issues #10835 and
#      #10768 are still OPEN — residual drift stands (the hcloud_server.inngest
#      replace rides the host-replace window, and the google_gws_recovery
#      record rides PR #10678), so a close is the #8754 defect re-opened. A
#      "clean" verdict may close them legitimately, so that arm asserts nothing
#      about issue state.
#
# Runs that skip the step (a no-change apply, or an unverified infra-config
# gate) exercise nothing and do not count — the probe keeps waiting. The step
# did not exist before PR #11296, so any run that executed it is post-merge.
#
# Credential posture: none — public GitHub API reads via the caller's gh auth.
# RETIREMENT: delete with the tracker issue; no other references.
#
# Exit semantics (sweep-followthroughs.sh contract):
#   0 = PASS · 1 = FAIL · 2 = NOT YET · 3 = CANNOT ESTABLISH

set -uo pipefail
export LC_ALL=C

REPO="${GH_REPO:-jikig-ai/soleur}"
WORKFLOW="apply-deploy-pipeline-fix.yml"
STEP_NAME="Post-apply full-root drift plan"
DRIFT_ISSUES="10835 10768"

for tool in gh jq unzip; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "CANNOT ESTABLISH: $tool unavailable" >&2
    exit 3
  fi
done

runs="$(gh run list --repo "$REPO" --workflow "$WORKFLOW" --status completed \
        -L 20 --json databaseId --jq '.[].databaseId' 2>/dev/null)"; rc=$?
if [[ "$rc" -ne 0 ]]; then
  echo "CANNOT ESTABLISH: gh run list for ${WORKFLOW} failed (rc ${rc})" >&2
  exit 3
fi
if [[ -z "$runs" ]]; then
  echo "NOT YET: no completed ${WORKFLOW} run" >&2
  exit 2
fi

# Newest first: the first run whose apply job ran the step (conclusion set, not
# skipped) is the verification sample.
sample_id=""
for id in $runs; do
  jobs="$(gh api --paginate "repos/${REPO}/actions/runs/${id}/jobs?per_page=100" 2>/dev/null)"; rc=$?
  if [[ "$rc" -ne 0 || -z "$jobs" ]]; then
    echo "CANNOT ESTABLISH: jobs read failed for run ${id} (rc ${rc})" >&2
    exit 3
  fi
  concl="$(jq -sr --arg step "$STEP_NAME" \
    '[.[].jobs[] | select(.name == "apply") | .steps[] | select(.name == $step) | .conclusion] | .[0] // ""' \
    <<<"$jobs")"
  case "$concl" in
    success|failure) sample_id="$id"; break ;;
  esac
done
if [[ -z "$sample_id" ]]; then
  echo "NOT YET: completed ${WORKFLOW} runs exist but none exercised '${STEP_NAME}'" >&2
  exit 2
fi

# The run log archive holds one file per step ("<job>/<NN>_<step>.txt"), which
# isolates this step's stdout from the targeted pre-apply plan's raw output.
tmpdir="$(mktemp -d -t soleur-followthrough.XXXXXXXX)"
zip="$tmpdir/run-logs.zip"
if ! gh api "repos/${REPO}/actions/runs/${sample_id}/logs" > "$zip" 2>/dev/null; then
  echo "CANNOT ESTABLISH: log archive fetch failed for run ${sample_id}" >&2
  rm -rf "$tmpdir"
  exit 3
fi
entry="$(unzip -Z1 "$zip" 2>/dev/null | grep -i 'full-root drift plan' | head -1)"
if [[ -z "$entry" ]]; then
  echo "CANNOT ESTABLISH: no '${STEP_NAME}' step file in run ${sample_id} log archive" >&2
  rm -rf "$tmpdir"
  exit 3
fi
unzip -p "$zip" "$entry" > "$tmpdir/step.txt" 2>/dev/null
step_log="$tmpdir/step.txt"

verdict=""
if grep -qF "Post-apply full-root plan is clean" "$step_log"; then
  verdict=clean
elif grep -qF "Post-apply full-root plan still shows changes" "$step_log"; then
  verdict=drift
elif grep -qF "Post-apply full-root plan FAILED" "$step_log"; then
  echo "FAIL: run ${sample_id} drift_plan emitted ::error:: — the diagnostic failed closed; the gate produced no evidence" >&2
  rm -rf "$tmpdir"
  exit 1
fi
if [[ -z "$verdict" ]]; then
  echo "FAIL: run ${sample_id} drift_plan log carries no verdict notice — the step produced no readable evidence" >&2
  rm -rf "$tmpdir"
  exit 1
fi

# Raw plan output must never reach the public log. The targeted pre-apply plan
# prints its output by design, so only THIS step's file is checked.
leak="$(grep -nE 'Terraform (will|has|planned) perform|Refreshing state\.|random_id|will be (created|updated|destroyed)|must be replaced|Plan: [0-9]+ to (add|change|destroy)|<= read \(data resources\)' "$step_log" || true)"
if [[ -n "$leak" ]]; then
  echo "FAIL: run ${sample_id} drift_plan leaked raw plan output into the public log (#11294):" >&2
  printf '%s\n' "$leak" | head -20 >&2
  rm -rf "$tmpdir"
  exit 1
fi
rm -rf "$tmpdir"

if [[ "$verdict" == "drift" ]]; then
  for iss in $DRIFT_ISSUES; do
    st="$(gh issue view "$iss" --repo "$REPO" --json state --jq .state 2>/dev/null)"; rc=$?
    if [[ "$rc" -ne 0 || -z "$st" ]]; then
      echo "CANNOT ESTABLISH: gh issue view #${iss} failed (rc ${rc})" >&2
      exit 3
    fi
    if [[ "$st" != "OPEN" ]]; then
      echo "FAIL: infra-drift issue #${iss} is ${st} while residual drift stands — the #8754 defect recurs" >&2
      exit 1
    fi
  done
fi

echo "PASS: run ${sample_id} drift_plan verdict='${verdict}'; notice in log; no raw plan output; drift-issue state consistent."
exit 0
