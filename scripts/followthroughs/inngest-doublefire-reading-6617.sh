#!/usr/bin/env bash
# Follow-through verification for #6617 task B4.2.b — the doublefire reading.
#
# WHY THIS EXISTS
# PR #6748 (A+B) answered half of H4. `op=registry-probe` returned
# registry_empty=true function_count=0 — no SDK has registered against the
# dedicated host. The OTHER half is unanswered: an empty registry proves
# nothing is registered NOW, not that nothing EXECUTED earlier. Only
# `op=doublefire-probe` proves the harm itself.
#
# That reading could not be taken pre-merge: the first dispatch surfaced a
# defect in the shipped script (build_request_body used printf '%s', so an
# empty CSV produced zero bytes and `jq --argjson fnids ""` aborted — the
# DEFAULT path, which is why op=verify step 2.6's exactly-once check had
# never returned a verdict). The host runs the DEPLOYED copy, so the fix
# reaches it only via the post-merge deploy_pipeline_fix auto-apply.
#
# Without this enrollment, "re-dispatch after the apply lands" is a line in
# tasks.md that depends on someone remembering. That is exactly the rot the
# sweeper exists to prevent.
#
# Exit semantics (enforced by scripts/sweep-followthroughs.sh):
#   0 = PASS       verdict recorded; sweeper closes #6617
#   1 = FAIL       not yet satisfied; sweeper comments, leaves open
#   * = TRANSIENT  API/network error; sweeper retries next sweep
#
# Convention: knowledge-base/engineering/operations/runbooks/followthrough-convention.md

set -uo pipefail

ISSUE=6617
WORKFLOW=apply-deploy-pipeline-fix.yml

# --- Gate 1 (mechanical): has delivery landed? -------------------------------
# The fixed inngest-doublefire-probe.sh reaches the host only when the
# deploy_pipeline_fix auto-apply succeeds. Until then B4.2.b is BLOCKED, not
# forgotten — report that distinctly so a reader can tell "not yet possible"
# from "possible but not done".
#
# SCOPING IS LOAD-BEARING. An unscoped `--status success --limit 1` query
# passes on ANY historical apply — including ones that predate this fix — so
# the gate would report "delivered" before PR #6748 ever merged. Verified: the
# unscoped form returned success while the PR was still open. Scope to applies
# created on/after the merge date so only a post-fix delivery can satisfy it.
MERGE_DATE=2026-07-20
delivery=$(gh run list --workflow "$WORKFLOW" --status success \
  --created ">=$MERGE_DATE" --limit 1 --json databaseId --jq 'length' 2>/dev/null)
rc=$?
if [[ $rc -ne 0 || -z "$delivery" ]]; then
  echo "TRANSIENT: could not query $WORKFLOW runs (gh rc=$rc)" >&2
  exit 2
fi
if [[ "$delivery" -eq 0 ]]; then
  echo "FAIL: no successful $WORKFLOW run on/after $MERGE_DATE — the fixed" >&2
  echo "      doublefire probe has not reached the host. B4.2.b is BLOCKED" >&2
  echo "      (not neglected)." >&2
  exit 1
fi

# --- Gate 2 (judgment): has the verdict been recorded? -----------------------
# The reading itself is NOT a pass/fail probe — it is a branch:
#   zero runs      -> H4 answered clean, #6617 may close
#   non-empty runs -> a live double-scheduler condition, escalate to an
#                     incident and do NOT close (plan branch C6.3)
# A script must not make that call. It reads the recorded verdict instead —
# the sanctioned operator-confirmed pattern (the script reads the human
# verdict; the human does not read a dashboard).
comments=$(gh issue view "$ISSUE" --comments --json comments --jq '.comments[].body' 2>/dev/null)
rc=$?
if [[ $rc -ne 0 ]]; then
  echo "TRANSIENT: could not read #$ISSUE comments (gh rc=$rc)" >&2
  exit 2
fi

if printf '%s' "$comments" | grep -qE '^RESULT: FAIL'; then
  echo "FAIL: #$ISSUE carries RESULT: FAIL — the doublefire probe found runs on" >&2
  echo "      the dedicated host. This is a live double-scheduler condition." >&2
  echo "      Do NOT close; escalate per plan branch C6.3." >&2
  exit 1
fi

if printf '%s' "$comments" | grep -qE '^RESULT: PASS'; then
  echo "PASS: delivery landed and the doublefire verdict is recorded on #$ISSUE."
  exit 0
fi

echo "FAIL: delivery has landed, so B4.2.b is now UNBLOCKED, but no verdict is" >&2
echo "      recorded on #$ISSUE. Re-dispatch the probe and post the result:" >&2
echo "        gh workflow run cutover-inngest.yml -f op=doublefire-probe" >&2
echo "      Then comment on #$ISSUE with a line starting 'RESULT: PASS'" >&2
echo "      (zero runs on the dedicated host) or 'RESULT: FAIL' (any runs)." >&2
exit 1
