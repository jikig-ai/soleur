# Tasks: record the verified Slack wake path for Better Stack Logs alerts (Ref #10455)

> Superseded at review: items 1.3, 3.1 and 4.1 describe the first draft (unscoped flag claim, original ADR heading, "done / verified" status). The landed wording is narrower; see `decision-challenges.md` row I and `session-state.md`, "Review Phase".

Plan: knowledge-base/project/plans/2026-11-05-docs-record-slack-wake-verified-for-logs-alerts-plan.md

## Phase 1: canonical record

- 1.1 Re-read `knowledge-base/engineering/operations/runbooks/canary-probe-set.md` around the "Tenant-visible helper notice" paragraph and the "Slack wake check, run 2026-10-19" section.
- 1.2 Replace the sentence "The wake path for both alerts is email-only ... until the ADR-260 Slack integration is verified." with the pointer sentence (alert's own channel email only; Slack post recorded below, inferred for these two alerts).
- 1.3 Leave the 2026-10-19 section unchanged; add the bold-led paragraph "Slack wake check, dashboard read 2026-11-05 (#10455 item 4)" directly after its closing paragraph (Observed / Inferred / Unchanged / Limits; no person names; no new heading).

## Phase 2: runbook pointers

- 2.1 `betterstack-log-query.md`, `agent_sandbox_bash_denial` entry: replace the multi-line "Wake path: email only ..." span with a one-sentence pointer; keep "Accepted limitation" text.
- 2.2 `betterstack-log-query.md`, `faithful_canary_sandbox_broken` entry: replace "Wake path: email only (the same unverified Slack caveat ...)" with the short pointer sentence; keep "Positive control".

## Phase 3: ADR-218

- 3.1 Append `## Amendment — 2026-11-05 (#10455): the Slack post for Logs-alert incidents is observed` at the end of ADR-218 (3-4 lines: supersedes the old "Wake path" bullet, pointer to the runbook record, no decision change); do not edit the old bullet.

## Phase 4: post-mortem row

- 4.1 Flip the hosted-agent PIR action-item row "(item 4)" to `done 2026-11-05 (verified in the dashboard)` with the reworded text and pointer.

## Phase 5: verification (no writes)

- 5.1 Run the Acceptance Criteria greps (diff is markdown-only; stale phrases gone; record present; channel-flag sentence present; Sentry paragraph and `.tf` untouched; no person names).
- 5.2 Run `faithful-canary-sandbox-alert.test.sh`, `bwrap-probe-rollback-alert.test.sh`, `sandbox-canary-soak.test.sh` and `scripts/lint-infra-no-human-steps.py`.
- 5.3 PR body: `Ref #10455` (not Closes), state `.tf` deliberately untouched and why.
