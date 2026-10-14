# Learning: the two-PR-rule monitor routing recipe is four greppable moves, and the "regenerate the artifact" step has a local equivalent

## Problem

#9959 asked to route `scheduled_integration_suites` — a Sentry cron monitor created under the
two-PR rule — into `sentry_alert.cron_monitor_failure` once its detector id existed and its first
measured check-in landed. The issue's checkbox prescribes regenerating `alert-reference.json`
"from the `sentry-alert-reference-expected-<run>` CI artifact," which reads like a required
round-trip: push the `.tf` change, let the `plan_pr` reference gate fail, download the artifact,
commit it.

The actual work was four small moves, all locally verifiable:

1. Delete the monitor's entry (+ its comment block) from `local.cron_monitor_alert_unrouted`.
2. Insert `sentry_cron_monitor.<label>.id` into `monitor_ids` at the LC_ALL=C sorted position.
3. Append the live detector id (read once via the detectors API, e.g. `2403709`) to the
   `cron-monitor-failure.detectorIds` tail — it is a string-sorted array, and new ids typically
   land last.
4. Verify: `sentry-cron-monitor-routing-parity.test.ts` (XOR: routed XOR unrouted),
   `terraform fmt -check`, `jq -S` canonicality + `detectorIds | . == sort` + count, then let the
   `plan_pr` reference gate prove the committed file equals the plan projection.

The `plan_pr` gate greened on the first run — the local derivation was equivalent, so the
artifact-download contingency (the issue's literal text, recorded as a plan task) was never
needed. Same shape as the prior routings (#9234, #9511): the artifact path is the contingency,
not the default.

## Solution

- Preconditions are two facts, not vibes: detector id exists (read it live, record it in the
  plan) AND a measured check-in posted (a real `error` status counts — vacuous `ok` would not
  exercise the monitor).
- The detectorId the reference needs is the LIVE one from the detectors API, not anything
  derivable from the repo — that read is the plan phase's one credentialed dependency, and the
  recorded id is what the work phase consumes.
- Every invariant in this surface is mechanically checkable: sorted list, canonical JSON,
  XOR membership, one-appearance rule for the label. Write the AC as the greps, run the greps.
- The merge-time `sentry-monitors-audit` emits one advisory `::warning::` naming the monitor as
  Class A unrouted before the apply lands — expected, self-heals in the same apply; leave a note
  in the PR body so the warning isn't misread as drift.

## Key Insight

"Regenerate from the CI artifact" reads as a mandatory two-round-trip, but the artifact exists to
RECOVER a stale committed reference — if you can derive the delta locally and the `plan_pr` gate
validates it, the artifact never needs to exist. The gate is the enforcement; the artifact is the
remedy. Also: a review panel on a 3-line infrastructure diff earns its keep differently than on
code — all six seats green-lit it, but two still caught a wrong indent in the plan doc and a
channel-primacy note worth writing into the PR body.

## Session Errors

1. **`pipeline-tally.sh` printed `UNKNOWN` / `SOLEUR_TALLY_ERROR reason=missing-file` in the new
   worktree.** Recovery: `pipeline-tally.sh init` creates the per-branch tally ledger.
   **Prevention:** when starting a second one-shot pipeline in a fresh worktree, run
   `pipeline-tally.sh init` before the first `gate` call — the ledger is per-worktree, not
   per-repo.
2. **Brief named `worktree-lease.sh`, which does not exist.** Recovery: the plan subagent found
   the correct helper (`worktree-manager.sh create`) itself. **Prevention:** name the family
   ("the worktree/lease helper under `plugins/soleur/scripts/` or
   `plugins/soleur/skills/git-worktree/`"), not a guessed filename, in agent briefs.
