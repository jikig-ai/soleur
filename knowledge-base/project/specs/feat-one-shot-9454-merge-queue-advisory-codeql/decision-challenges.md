# Decision challenges — feat-one-shot-9454-merge-queue-advisory-codeql

Persisted by `soleur:plan` (headless) for `ship` to fold into the PR body and file as an `action-required` issue. The brief's direction stays the default; none of these is applied. User-Challenges 1 to 3 were revised after the review round of PR #9455 (measured numbers replace an estimate that was wrong; challenges 2 and 3 are new). The rationale for the accepted residuals lives once, in `ADR-270`; this file records what the operator is being asked to accept or change.

## User-Challenge 1 — "advisory" removes PR-head blocking, and nothing in the deploy chain waits for the page

- **Brief's direction:** CodeQL stays advisory (pull_request scan pre-merge plus a push-to-main alert gate); the issue's residual-risk section names interaction-only findings and stale-head drift.
- **Evidence, measured (read-only `gh api`, review of 2026-10-04):**
  - The required `CodeQL` rollup check currently blocks a PR whose own head introduces a new critical/high alert (live ruleset 14145388 requires it; it sits at index 15 of 24 required checks). After removal nothing blocks that PR.
  - The deploy trigger is `workflow_run` of `ci.yml` completing with success on the main push (`.github/workflows/web-platform-release.yml`); any other conclusion is a clean skip. Merge-commit committer time to `deploy` job completed, real deploys only, n=12: 12.9 to 41.1 min, median about 19 (sorted: 12.9, 15.8, 16.3, 17.9, 18.6, 18.6, 18.9, 23.7, 25.9, 27.2, 30.7, 41.1). CI wall-clock on main pushes, n=40 successful runs: p50 17.6 min, p90 24.8 min, fastest 11.5 min, so the deploy cannot start earlier than about 11.5 min after the push.
  - Gate latency: about 9 to 11 min from the push, measured on n=1 (one commit, quiet main). The input to it is better sampled: the `Analyze (*)` check-runs finish p50 5.1 min, max 6.6 min after the commit (n=23 recent main commits).
  - Nothing in the deploy chain depends on the gate. That is deliberate (the workflow header forbids `needs:` and `workflow_run:` on it), so the page leads the deploy START by a margin that nothing consumes: a human has to act inside it, and n=1 does not prove it holds under a burst of queue merges.
  - The earlier text said the gate detects "about 3-5 minutes after the push, and a production deploy follows the push on a comparable timescale". Both halves were wrong: the measured page latency is 9 to 11 min, and the deploy completes 12.9 to 41.1 min after the merge.
- **Alternative (not adopted):** a required Pattern-B Actions job that waits for the PR head's CodeQL analyses, fails on a new critical/high alert on `refs/pull/N/merge`, and passes through on `merge_group` on the entry-gate premise. It reports on `merge_group` (it is a normal Actions job), so it does not recreate the #5800 deadlock, and it keeps pre-merge blocking without a status shim on CodeQL's own context.
- **Cheaper mitigation (also not adopted):** an agent-side pre-enqueue check in ship, drain-prs and `admin-merge-ready` that the PR's `CodeQL` conclusion is not a failure, which keeps most of the pre-merge control without a required check.
- **Third alternative (not adopted):** hold the deploy (`resolve-target` sets `should_deploy=false`, loudly) while the gate run for that SHA is red or unfinished, with a timeout so a gate outage fails open after a bounded wait. The gate run (10 to 12 min on n=1) finishes inside the CI window (min 11.5, p50 17.6), so the user-impact reviewer's inference is that the hold costs the median deploy little; that is an inference, not a measurement. A `workflow_dispatch` deploy skips the CI gate today and would bypass any such hold.
- **Default if no response:** keep the brief (advisory). The plan's Risks table and ADR-270 record the loss.

## User-Challenge 2 — the declared brand-survival threshold should be `single-user incident`

- **Brief's direction (as planned):** `brand_survival_threshold: aggregate pattern`, `requires_cpo_signoff: false` (plan frontmatter, ADR-270 frontmatter).
- **New evidence:** the user-impact reviewer found the threshold wrong. The weakened control guards a product that handles user data (BYOK provider keys, conversation bodies, workspace KB files, billing records); a critical/high finding that was blocked before and now merges can expose one user's data, and a revert does not un-log a key or un-leak a record. The plan itself concedes the control is "a security gate on a product that handles user data". Under `single-user incident` the plan must also set `requires_cpo_signoff: true` and replace the generic User-Brand Impact bullets with concrete artifact and vector pairs by role (the reviewer's role-by-role artifact and vector table).
- **Alternative (not adopted):** re-declare `single-user incident` and `requires_cpo_signoff: true` in the plan and ADR-270 frontmatter, and rewrite the User-Brand Impact section by role.
- **Default if no response:** keep `aggregate pattern` as the operator declared it (this is the operator's call, not an agent's), pending the go-ahead. If the operator keeps it, the deploy-hold decision in Challenge 1 is the minimum the reviewer asks for.

## User-Challenge 3 — an `actions`-language critical/high finding is live on main for the whole gate window

- **Brief's direction:** CodeQL advisory; the post-merge gate pages after the push.
- **New evidence:** CodeQL scans three languages here (`actions`, `javascript-typescript`, `python`). A critical/high `actions`-language finding (for example code injection in an `issue_comment` or `pull_request_target` workflow) takes effect on `main` the instant it merges, needs no deploy, and is triggerable by any GitHub user because the repository is PUBLIC and carries secrets. The window is the gate latency (about 9 to 11 min on n=1); secrets exfiltrated inside it are not recovered by a revert. The deploy hold in Challenge 1 does not cover this vector, because it never touches the deploy.
- **Alternatives (none applied):**
  1. A required PR-head gate limited to PRs that touch `.github/**` (works on `merge_group` the same way as Challenge 1's alternative).
  2. Enforce CODEOWNERS review on `.github/workflows/**` in the ruleset. Today `.github/CODEOWNERS` has rows for the workflows and the new scripts, but the CI Required ruleset does not require code-owner review, so they are review discipline, not a gate.
  3. A deploy hold on a red or unfinished gate for the SHA (Challenge 1). It does not help here and a `workflow_dispatch` deploy would bypass it.
- **Control in place today (not a gate):** `drain-prs` and `merge-pr` refuse to arm a cross-repository PR or a PR touching `.github/**` without explicit operator confirmation.
- **Default if no response:** keep the brief.

## What the operator should decide at the go-ahead

The go-ahead for the merge (which is the apply of `infra/github`) is not only the Terraform diff. State both of these in the go-ahead text:

1. **The deploy hold** (Challenge 1, third alternative): hold the deploy on a red or unfinished gate for the SHA, yes or no. Default no.
2. **The threshold** (Challenge 2): `aggregate pattern` (declared) or `single-user incident` with CPO sign-off. Default `aggregate pattern`.

Challenge 3's alternatives are listed above for the record; none is needed to proceed.

## Taste 1 — `max_entries_to_build`

Plan sets 2 (CTO: limit hosted-runner contention, each entry runs all 25 contexts) instead of 3. Raise after the canary shows contention is not binding.

## Taste 2 — plan-review simplification proposals (not applied; plan keeps the larger scope)

From the DHH and code-simplicity reviewers (all tagged taste). Default if no response: keep the plan as written.

- Trim Guard 1 rows 7 and 8 and the allowlist cross-check; trim Guard 3 rows 10-11 and the U+2028/U+2029 handling; drop the per-call `timeout 60 gh` (job `timeout-minutes` already bounds it) and the Guard 3 harness row H4.
- Make ADR-270 a short ADR-032 amendment instead of a new ADR (the CTO assessment asked for a new ADR because this reverses a recorded decision and downgrades a security control).
- Drop the runbook edit and the one-line CLO determination in the 2026-08-17 ruling (CLO listed the latter as optional).
- Drop Phase 0 rows 0.2 and 0.3 (they restate findings already in Research Reconciliation); keep them as paste-into-PR evidence if cheap.
- Ship the `sync-pr-behind.sh` queued-skip only and defer `pr-merge-poll.ts`/ship/merge-pr edits to canary evidence — **applied** (made conditional in the plan, Phase 4).

## Follow-up (not in this PR)

Each item names its re-evaluation trigger. File as issues in the ship step (`wg-when-deferring-a-capability-create-a`).

- **(a) Inngest dispatch cron for the stall probe.** New `apps/web-platform/server/inngest/functions/cron-merge-queue-stall-dispatch.ts`: every 10 min, POST `workflow_dispatch` to `merge-queue-stall-check.yml`, with the `schedule:` kept as fallback (the dispatch-hybrid precedent is `cron-actions-queue-health-dispatch.ts`). It needs rows in the cron manifest, execution placement, routine metadata, the route and the function-registry count, about 8 files. NOT implemented here: schedule delivery on this repo measured gaps of hours (`scheduled-inngest-health.yml` `*/15`: median gap about 275 min, max about 479; `scheduled-actions-queue-health.yml` `*/30`: gaps of 2.7 to 6 h), so the probe is best-effort and the detection window [45, 60] min is 15 min wide. Post-merge row: measure the `schedule`-event gap of `merge-queue-stall-check.yml`. **Trigger (event-grep):** `gh run list --workflow merge-queue-stall-check.yml --event schedule` shows a median gap wider than the 15-minute window, or the first stall that the probe failed to report before the queue ejected the entry.
- **(b) `codeql-to-issues.yml` fails closed.** Replace `|| true` with an exit-status check, paginate, and scope its dedupe to the bot author like the gate (pre-existing; after this PR the cron is the only control for an alert the gate degraded on). **Trigger (event-grep):** the first `codeql-gate-degraded` issue (`gh issue list --label meta/machinery --search 'codeql-gate-degraded'`), or the ADR-270 flip to `accepted`, whichever is first.
- **(c) Duplicate push CI run per queue merge (performance Q4).** With SQUASH the push-to-main `ci.yml` run re-runs about 36 jobs on a tree the `merge_group` run just built, and the deploy waits on that rerun (push CI p50 17.9 min on success). A skip must still emit a CI completion event for `web-platform-release.yml`. **Trigger (dependency):** canary 3 records that the push SHA equals `merge_group.head_sha`; once it does, the byte-identical premise is verified and the skip can be designed.
- **(d) Hook pre-enqueue sync skip (performance H1).** `.claude/hooks/pre-merge-rebase.sh` still syncs a behind PR that is not yet queued, which is a new head and a full PR CI cycle. When the queue rule is present, skip the sync unless `git merge-tree --write-tree HEAD origin/main` reports a conflict. **Trigger (counter):** canary 9 "sync pushes per merged PR" at or above the measured 1.3 break-even (performance Q5: about 1.3 removed resyncs per merged PR pays for the queue's extra `merge_group` fan-out).
