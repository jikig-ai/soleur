# `approval-queue` flag: creation hand-over (not done by the PR)

The PR registers the flag in code only (`lib/feature-flags/server.ts` RUNTIME_FLAGS, `.env.example` `FLAG_APPROVAL_QUEUE=0`, `flip.sh` map). Nothing is created in Flagsmith or Doppler and nothing is flipped. Absent means OFF, so the merge does not depend on it.

## Operator steps (typed-yes, each a production write; run only after the legal commit and the post-merge checks below are green)

1. Create the feature with `soleur:flag-create` (name `approval-queue`, default OFF, mirror `FLAG_APPROVAL_QUEUE=0` in Doppler dev and prd).
2. Do NOT flip it as part of the create. Enabling is a separate decision per workspace cohort via a per-workspace segment override (`soleur:flag-set-role`), evaluated per workspace identity.

## Preconditions before anyone enables it

- Migration 180 applied in prd (release workflow `verify-migrations` green) and the cron monitor `cron-approval-expiry` checking in (Sentry).
- ADR-307 adopted; the legal records in this PR merged.
- Evidence gates #9776 and #10111 closed before the ask path is described as measured.
- Autonomous-mode (`workspace_set_autonomous`) card copy still PROVISIONAL: needs CPO and CLO sign-off before the first workspace is enabled.
