# Runbook — a failed web-platform release image push (`SOLEUR_GHCR_PUSH_FAILED`)

What to do when the `Build and push Docker image` step of a web-platform release fails, and the step after it
prints a `SOLEUR_GHCR_PUSH_FAILED` line.

- **Who emits the marker:** the `Report a failed image push (GHCR)` step (`id: push_failed_marker`) in
  `reusable-release.yml`. It runs only when `docker_build` failed, it is `continue-on-error`, and it never changes
  the job's verdict.
- **Who sends the email:** the existing `Email notification (release FAILED)` step of the same job.
- **What it is:** diagnostics only. Nothing retries the push (CTO ruling C1, 2026-11-10), and CI never reads billing
  (C3).
- **Irreversible:** nothing in this runbook is. Re-running failed jobs rebuilds the same SHA.
- **Pinned by:** `plugins/soleur/test/reusable-release-push-failed-marker.test.sh` (Guard 4, #8211).

## Triggers

Any one of these sends you here:

- the `[BLOCKED] Soleur Web Platform release failed — nothing was shipped` email;
- a `SOLEUR_GHCR_PUSH_FAILED` annotation on the push-arm run;
- a deploy-arm (`workflow_run`) run whose `resolve-target` job failed with `release=skipped`. That run carries no
  marker of its own; the marker is on the push-arm run for the same SHA.

## Read the marker

Find the push-arm run for the SHA. A push starts one release run per SHA, and a re-run reuses that run's id (it adds
an attempt), so this read lists one run; `last` only keeps the answer to one row:

```bash
gh run list -R jikig-ai/soleur --workflow web-platform-release.yml --commit <sha> --event push \
  --json databaseId,createdAt,conclusion --jq 'sort_by(.createdAt) | last'
```

Then read the marker from that run. It shows in the run's `ANNOTATIONS` block:

```bash
gh run view <run-id> -R jikig-ai/soleur
```

or from the full log. The marker step is `continue-on-error` and exits 0, so `--log-failed` never shows it. The
second `grep` drops the log's copy of the step's own script, which also contains the marker prefix:

```bash
gh run view <run-id> -R jikig-ai/soleur --log | grep -F 'SOLEUR_GHCR_PUSH_FAILED image=' | grep -vF '${image}'
```

During the gap, the prod version-drift alert is expected to fire. It is the same incident, not a separate one.

## Read the class first

The marker line has one closed grammar:

```text
SOLEUR_GHCR_PUSH_FAILED image=<ref> version=<v> attempt=<n|invalid> run=<url> class=<class> denial=<text> runbook=<this file>
```

| `class` | `denial` | What it means | Next |
|---|---|---|---|
| `push_denied` | `denied: <code>: <reason>` (for v0.402.0: `denied: permission_denied: write_package`) | The registry refused the push. | [First read](#first-read-before-anything-else): the Packages budget and usage. |
| `push_other` | `withheld` | The push failed, and the registry text does not match the allowlist shape, so it is not copied into a public log. | Read the push step's log, then [recover](#recovery). |
| `not_push` | `see-step-log` | The error was not classified as an image-push failure, for example a failed `RUN npm run build`. It does not prove the push was not refused (see the drift note below). | Read the build step's log. A build error: fix the build. A `denied:` or `failed to push` line: treat it as `push_denied` and go to the [first read](#first-read-before-anything-else). |
| `unknown` | `see-step-log` | The build history could not be read, so nothing was classified. | Read the push step's log; it has the full error. |
| `unmeasured` | none | Shown by the email or Slack, never by a marker line: the marker step did not report (it did not run, or it failed or timed out before writing its output). | Read the push step's log; it has the full error. |

**Drift.** The parser was measured on buildx 0.38.1, and the runner's version is not pinned. A changed build-record
shape reads as `class=unknown`, and a reworded error message reads as `class=not_push`. If either class sits next to a
push step log that shows a registry denial, treat the class as unmeasured, not as a finding.

`attempt` is the run attempt that failed. A marker on attempt 2 or higher means a re-run failed too.

`denial` reaches only the run log and the step summary. The email and the Slack message carry the class and the
attempt, never the denial text.

## Residual: a cancelled or timed-out job reports nothing

A job that is cancelled or runs out of time emits neither the marker nor the email, because `failure()` is false
there. The run's `cancelled` conclusion is the only signal. Read the push step's log before any re-run:

```bash
gh run view <run-id> -R jikig-ai/soleur --log | grep -F 'Build and push Docker image' | tail -n 50
```

The marker step itself is bounded by `timeout-minutes: 1`, so it cannot be the step that runs the job out of time.

## First read, before anything else

Read the GitHub Packages budget and this month's Packages usage. Both are read-only GETs, and an agent can run them:

```bash
gh api --paginate /orgs/jikig-ai/settings/billing/budgets --jq '.budgets[] | select(.budget_product_sku=="packages")'
gh api --paginate "orgs/jikig-ai/settings/billing/usage?year=$(date -u +%Y)&month=$(date -u +%-m)" \
  --jq '[.usageItems[] | select((.product // "") | test("packages"; "i"))]
        | {lines: length, gross: (map(.grossAmount // 0) | add // 0), net: (map(.netAmount // 0) | add // 0)}'
```

The usage read is the same endpoint `scripts/lib/watch-notify-once.sh` reads (`wn_billing_month`), filtered to
Packages instead of code quality. `--paginate` makes `jq` run once per page; the usage read prints one object per
page, so add them up if it prints more than one.

**Rule.** Read the two results in this order and stop at the first that applies:

1. **Usage unmeasured.** If the usage read gives `lines: 0`, this endpoint does not report Packages for this org, and
   its `net: 0` is not a measurement of zero. Carry `unmeasured` into the next rules.
2. **No refusal.** If `prevent_further_usage` is `false`, or no Packages budget comes back, the budget refuses
   nothing, so it is not the cause.
3. **Possible.** If the budget is `0` with `prevent_further_usage: true`, a billing block is possible: any Packages
   usage past the included quota is refused. Neither read can show that it caused this denial.
4. **Blocked or not.** If the budget is above `0` with `prevent_further_usage: true`, Packages reads as **blocked**
   when usage was measured and `net` is greater than or equal to `budget_amount`, as **possible** when usage is
   unmeasured, and as not blocked otherwise.

Measured on 2026-11-09: the Packages budget was `0` with `prevent_further_usage: true`, and the usage read returned no
Packages line. Rules 1 and 3 apply: a block is possible and unconfirmed, and the cause of the v0.402.0 denial is still
open. Each read is a snapshot of the moment it runs. It cannot show whether a block was in force when the push ran.

**Owner-only step (the fallback).** If either API read fails (a 401, 403 or 404 means the token cannot read org
billing), or usage is unmeasured and the decision needs the number, an org owner opens Billing > Packages and records
what it shows. The agent cannot do this step; it names it and stops there.

## What a failed push did not do

It consumed no semver version, created no git tag and published no release notes. The release is still an
unpublished draft, so nothing was half-shipped.

## Recovery

Release re-runs are owner-gated. The agent prepares both run ids and the commands below, then reads the outcome
after the owner acts. In this order:

1. **First, "Re-run failed jobs" on the release (push-arm) run**
   (`gh run rerun <push-run-id> -R jikig-ai/soleur --failed`). Find its id with the push-arm read in
   [Read the marker](#read-the-marker).
2. **Once that run succeeds, "Re-run failed jobs" on the deploy-arm run** for the same SHA. This step applies only
   to a release started by a push: a `workflow_dispatch` release deploys in the same run, so step 1 covers it. Find
   the deploy-arm run with:

   ```bash
   gh run list -R jikig-ai/soleur --workflow web-platform-release.yml --commit <sha> --event workflow_run \
     --json databaseId,createdAt,conclusion --jq 'sort_by(.createdAt) | last'
   ```

   Each CI completion for the SHA starts one such run, so a CI re-run adds a second; the read takes the newest.
   Re-running the push arm does not start one. If the read returns nothing, CI has not completed yet, and the deploy
   arm will start when it does. Otherwise re-run it itself
   (`gh run rerun <deploy-run-id> -R jikig-ai/soleur --failed`).
3. **Never a fresh "Run workflow" dispatch.** A dispatch short-circuits the PR lookup to `labels=`, defaults the
   bump to `patch`, loses a minor or major bump and orphans the draft.

## Operator decision (money): the GitHub Packages budget

Whether to raise the org's Packages budget for private GHCR images, or keep it, is the operator's decision about
money. This runbook does not prescribe a value. The agent stops at this point and reports what it read. It does not
work around the budget, by any route (CPO condition 7).

## When to reconsider a retry

Re-evaluate the no-retry ruling (C1) when a run is classified `push_denied` while the Packages budget is above `0` or
its `prevent_further_usage` is `false` (read with the [first read](#first-read-before-anything-else)). Under the
measured budget (`0`, `prevent_further_usage: true`) a denial cannot rule billing out, so it does not trigger this.
The change then is one bounded retry that still prints the marker on the first denial.

## Out of scope

Pointing the release at the self-hosted Zot registry instead of GHCR (prior CTO ruling).
