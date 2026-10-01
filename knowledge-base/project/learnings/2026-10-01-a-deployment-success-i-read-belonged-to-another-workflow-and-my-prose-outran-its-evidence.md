# Learning: a "success" record from the wrong workflow, and prose that claimed a post-apply state before the apply

## Problem

Two PRs removed an obsolete cron monitor (#9303 deleted the function and unrouted the Sentry monitor; #9337 deletes the
monitor). Three separate claims outran their evidence, each caught by something other than the author's own checks.

1. **A deployment status read as proof our apply ran.** After #9303 merged, the Sentry apply run sat in `waiting` for ~52
   minutes with zero steps and no runner. The environment's deployments list showed a `success` for the same SHA on the
   `infra-privileged` environment, which read as "it applied, the run view is stale". Its `log_url` pointed at a different
   workflow (Apply web-platform infra). The live read of the alert (59 detectors, retired detector still bound to 60) said
   the Sentry apply had NOT happened. Cancelling the stuck run let the next main push run apply it.
2. **A plan premise that was false.** The plan said deleting the monitor makes the header bound "30-240 min" false because
   it held the only `checkin_margin_minutes = 240`. Measured: daily monitors already carried 360, 420 and 1440, so the
   bound was false before the PR.
3. **Past tense about a post-merge state.** The Article 30 note said the monitor "has been deleted from the Sentry
   organization" in a PR whose destroy only happens in the post-merge apply. Four review seats converged on it. A review
   note about exactly this class (document post-merge completion in the future tense) already existed and was in view.

A fourth item sat beside them: the plan's post-merge proof hard-coded "404 and 59 detectors", but `cron-monitors.tf`
records that a monitor removed from the file may be deactivated in Sentry rather than deleted, and a Sentry-tree commit
landing in between legitimately moves the count. A correct deletion could have printed a false FAIL and sent an agent into
the recovery path.

## Solution

- Read the **deployment's own `log_url`** (or the run that owns the job) before using a deployment status as evidence, and
  confirm the claim against the live object, not a status record.
- A Sentry apply job in `waiting` with zero steps and an environment that has no reviewers is a runner or concurrency stall,
  not an approval gate. Cancel it and the next main push run applies full-root main. For a **destroy** that does not hold:
  the next run carries no ack and fails closed, so recover by rerunning the ack-carrying run after checking nothing newer
  landed under `infra/sentry`.
- Measure a plan's "this becomes false" premise with the command that would falsify it before writing the edit.
- Word any note about a post-apply state as "is deleted by the apply that follows the merge of #N", and make the post-merge
  proof two-sided (apply log reads `1 destroyed` AND the object is 404 or no longer bound), comparing counts with a
  pre-merge read rather than a literal.
- Added the three edits a bare delete misses to the Sentry README's removal recipe, and a "stalled apply" bullet.

## Key Insight

A record that says "success" is a claim about the thing that wrote it. Before it licenses a conclusion, name the writer
(its workflow, its job) and check the claim against the live object. The same discipline applies to prose: a sentence
about a state that only exists after a later event is a measurement you have not taken yet, whatever tense it is written
in. A destroy changes the recovery rules too: the cheap "cancel and let the next run apply" path that worked for the
unrouting change is unavailable when the change needs a commit-body ack.

## Session Errors

1. **The `web-platform-typecheck` pre-commit hook ran out of Node heap on the first commit (host fault, not the diff).**
   Recovery: checked for surviving hook processes by name, then committed with the `--no-verify` the operator had
   authorized, relying on CI. **Prevention:** none needed; the hook is the right gate and the host is the problem.
2. **A malformed one-line `for` loop failed to parse and took the commit-message heredoc in the same command with it,
   so the commit saw a missing file (`rc=128`).** Recovery: wrote the file with the Write tool and re-ran.
   **Prevention:** write a commit message file in its own call, never in the same command as anything that can fail first
   (already documented under the heredoc-in-gated-command rule).
3. **`pgrep -f` was denied by the self-match hook and `TaskStop` was called with a Monitor parameter.** Recovery: `pgrep` by
   name; re-issued the tool call. **Prevention:** already hook-enforced.
4. **The plan said the deleted monitor held the only 240-minute margin.** Recovery: measured the margins (360/420/1440
   exist), updated the header to the derived range and named the outlier. **Prevention:** a plan edit premised on "X
   becomes false" needs the falsifying command run first (existing plan-quoted-claims rule).
5. **I read a `success` deployment status for the merge SHA as proof the Sentry apply had run; it belonged to a
   different workflow.** Recovery: followed `log_url`, then read the live alert (still bound) and cancelled the stuck run.
   **Prevention:** added to the Sentry README's stalled-apply bullet: read the deployment's `log_url`, and verify against
   the live object.
6. **The Article 30 note asserted a post-apply state in the past tense.** Recovery: reworded to "is deleted by the apply
   that follows the merge of #9337". **Prevention:** none new; the class is already documented in the review skill's
   post-merge-tense bullet and recurred anyway, which is evidence for a mechanical check if it recurs a third time.
7. **The plan's post-merge probe hard-coded a 404 and 59 detectors despite a repo note that removed monitors may be
   deactivated.** Recovery: made the proof two-sided and count-relative. **Prevention:** read the repo's own recorded
   residuals for the resource type before writing a post-merge proof.
8. **`c4-count-parity.test.sh` exited 1 under the host's `python3` (a mise shim missing the `yaml` module) with a bare
   traceback and no `FAIL:` line.** Recovery: re-ran with the system Python first on PATH (rc 0). **Prevention:** one-off
   host fault; a non-attributable crash is not a result, so re-run in a known-good environment before reading it.

## Tags
category: workflow-issues
module: sentry infra, post-merge verification, review
