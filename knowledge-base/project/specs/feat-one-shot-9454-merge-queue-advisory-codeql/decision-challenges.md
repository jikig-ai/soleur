# Decision challenges — feat-one-shot-9454-merge-queue-advisory-codeql

Persisted by `soleur:plan` (headless) for `ship` to fold into the PR body and file as an `action-required` issue. The brief's direction stays the default; none of these is applied.

## User-Challenge 1 — "advisory" removes PR-head blocking, not only interaction-only coverage

- **Brief's direction:** CodeQL stays advisory (pull_request scan pre-merge plus a push-to-main alert gate); the issue's residual-risk section names interaction-only findings and stale-head drift.
- **New evidence:** the required `CodeQL` rollup check currently blocks a PR whose own head introduces a new critical/high alert (live ruleset 14145388 requires it; `gh api repos/jikig-ai/soleur/rulesets/14145388` lists it at index 15 of 24 required checks). After removal nothing blocks that PR; the post-merge gate detects it about 3-5 minutes after the push, and a production deploy follows the push on a comparable timescale.
- **Alternative (not adopted):** a required Pattern-B Actions job that waits for the PR head's CodeQL analyses, fails on a new critical/high alert on `refs/pull/N/merge`, and passes through on `merge_group` on the entry-gate premise. It reports on `merge_group` (it is a normal Actions job), so it does not recreate the #5800 deadlock, and it keeps pre-merge blocking without a status shim on CodeQL's own context.
- **Cheaper mitigation (also not adopted):** an agent-side pre-enqueue check in ship, drain-prs and `admin-merge-ready` that the PR's `CodeQL` conclusion is not a failure, which keeps most of the pre-merge control without a required check.
- **Default if no response:** keep the brief (advisory). The plan's Risks table and ADR-269 record the loss.

## Taste 1 — `max_entries_to_build`

Plan sets 2 (CTO: limit hosted-runner contention, each entry runs all 25 contexts) instead of 3. Raise after the canary shows contention is not binding.

## Taste 2 — plan-review simplification proposals (not applied; plan keeps the larger scope)

From the DHH and code-simplicity reviewers (all tagged taste). Default if no response: keep the plan as written.

- Trim Guard 1 rows 7 and 8 and the allowlist cross-check; trim Guard 3 rows 10-11 and the U+2028/U+2029 handling; drop the per-call `timeout 60 gh` (job `timeout-minutes` already bounds it) and the Guard 3 harness row H4.
- Make ADR-269 a short ADR-032 amendment instead of a new ADR (the CTO assessment asked for a new ADR because this reverses a recorded decision and downgrades a security control).
- Drop the runbook edit and the one-line CLO determination in the 2026-08-17 ruling (CLO listed the latter as optional).
- Drop Phase 0 rows 0.2 and 0.3 (they restate findings already in Research Reconciliation); keep them as paste-into-PR evidence if cheap.
- Ship the `sync-pr-behind.sh` queued-skip only and defer `pr-merge-poll.ts`/ship/merge-pr edits to canary evidence — **applied** (made conditional in the plan, Phase 4).
