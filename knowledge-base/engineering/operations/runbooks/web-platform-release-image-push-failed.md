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

Find the push-arm run for the SHA. A CI re-run or a re-run of this workflow can leave more than one, so take the
newest:

```bash
gh run list --workflow web-platform-release.yml --commit <sha> --event push \
  --json databaseId,createdAt,conclusion --jq 'sort_by(.createdAt) | last'
```

Then read the marker from that run. It shows in the run's `ANNOTATIONS` block:

```bash
gh run view <run-id>
```

or from the full log. The marker step is `continue-on-error` and exits 0, so `--log-failed` never shows it. The
second `grep` drops the log's copy of the step's own script, which also contains the marker prefix:

```bash
gh run view <run-id> --log | grep -F 'SOLEUR_GHCR_PUSH_FAILED image=' | grep -vF '${image}'
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
| `not_push` | `see-step-log` | The build failed before the push (for example a failed `RUN npm run build`). This is not an image-push failure: this runbook is out of scope and Billing is not the cause. | Read the build step's log and fix the build. |
| `unknown` | `see-step-log` | The build history could not be read, so nothing was classified. | Read the push step's log; it has the full error. |

If the marker says `class=unknown` but the push step's log shows a real registry denial, the runner's buildx may have
changed its output format. The parser was measured on buildx 0.38.1, and the runner's version is not pinned. Read the
push step's log for the error, and treat the class as unmeasured, not as a finding.

`attempt` is the run attempt that failed. A marker on attempt 2 or higher means a re-run failed too.

`denial` reaches only the run log and the step summary. The email carries the class and the attempt, never the
denial text.

## Residual: a cancelled or timed-out job reports nothing

A job that is cancelled or runs out of time emits neither the marker nor the email, because `failure()` is false
there. The run's `cancelled` conclusion is the only signal. Read the push step's log before any re-run:

```bash
gh run view <run-id> --log | grep -F 'Build and push Docker image' | tail -n 50
```

The marker step itself is bounded by `timeout-minutes: 1`, so it cannot be the step that runs the job out of time.

## First read, before anything else

Read the GitHub Packages budget and this month's Packages usage. Both are read-only GETs, and an agent can run them:

```bash
gh api /orgs/jikig-ai/settings/billing/budgets --jq '.budgets[] | select(.budget_product_sku=="packages")'
gh api "orgs/jikig-ai/settings/billing/usage?year=$(date -u +%Y)&month=$(date -u +%-m)" \
  --jq '[.usageItems[] | select((.product // "") | test("packages"; "i"))]
        | {lines: length, gross: (map(.grossAmount // 0) | add // 0), net: (map(.netAmount // 0) | add // 0)}'
```

The usage read is the same endpoint `scripts/lib/watch-notify-once.sh` reads (`wn_billing_month`), filtered to
Packages instead of code quality.

**Rule.** Packages reads as **blocked** when the budget has `prevent_further_usage: true` **and** this month's
Packages `net` usage is greater than or equal to its `budget_amount`. Anything else reads as not blocked. With a
`budget_amount` of `0` the second half always holds, so the rule then says "any Packages usage past the included
quota is refused", which is the budget's actual policy.

If either API read fails (a 401, 403 or 404 means the token cannot read org billing), fall back to the Billing >
Packages page and record what it shows. The page is the fallback only.

Measured on 2026-11-09: the Packages budget was `0` with `prevent_further_usage: true`. A block is a lead, not a
finding: the cause of the v0.402.0 denial is unconfirmed. Each read is a snapshot of the moment it runs. It cannot
show whether a block was in force when the push ran.

## What a failed push did not do

It consumed no semver version, created no git tag and published no release notes. The release is still an
unpublished draft, so nothing was half-shipped.

## Recovery

Release re-runs are owner-gated. The agent prepares both run ids and the commands below, then reads the outcome
after the owner acts. In this order:

1. **"Re-run failed jobs" on the push-arm run** (`gh run rerun <push-run-id> --failed`). Find its id with the
   `gh run list ... --event push` read in [Read the marker](#read-the-marker).
2. **Once that run succeeds, "Re-run failed jobs" on the deploy-arm run** for the same SHA. Its `resolve-target`
   job failed when the release did. Find it with:

   ```bash
   gh run list --workflow web-platform-release.yml --commit <sha> --event workflow_run \
     --json databaseId,createdAt,conclusion --jq 'sort_by(.createdAt) | last'
   ```

   Measured on 2026-11-09: one such run existed for the SHA. CI completing creates it, before the push arm fails,
   and re-running the push arm does not start a new one. That is a measurement, not a rule: a CI re-run completes
   again and adds a second. The read above takes the newest. Re-run it itself
   (`gh run rerun <deploy-run-id> --failed`).
3. **Never a fresh "Run workflow" dispatch.** A dispatch short-circuits the PR lookup to `labels=`, defaults the
   bump to `patch`, loses a minor or major bump and orphans the draft.

## Operator decision (money): the GitHub Packages budget

Whether to raise the org's Packages budget for private GHCR images, or keep it, is the operator's decision about
money. This runbook does not prescribe a value. The agent stops at this point and reports what it read. It does not
work around the budget, by any route (CPO condition 7).

## When to reconsider a retry

Re-evaluate the no-retry ruling (C1) when a second, separate run is denied while the [budget read](#first-read-before-anything-else)
does not read as blocked.
The change then is one bounded retry that still prints the marker on the first denial.

## Out of scope

Pointing the release at the self-hosted Zot registry instead of GHCR (prior CTO ruling).
