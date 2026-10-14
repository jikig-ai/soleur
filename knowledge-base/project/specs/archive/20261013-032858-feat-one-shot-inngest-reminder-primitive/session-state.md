# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-03-feat-inngest-oneshot-pattern-and-reminder-primitive-plan.md
- Status: complete

### Decisions
- Part B reminder primitive is ENDPOINT-armed (POST /api/internal/schedule-reminder → inngest.send with ts), NOT boot-armed → NO server/index.ts edit for the primitive; boot-arm path is documented for bespoke oneshots only.
- Allowlisted discriminated-union action (issue-comment | named-check) validated at BOTH endpoint and handler via a shared lib/inngest/scheduled-reminder-action.ts module (route file stays HTTP-only per cq-nextjs-route-files-http-only-exports). CHECK_REGISTRY membership reject lives in the handler (route can't import octokit).
- Endpoint mirrors trigger-cron verbatim for auth/shape; reuses INNGEST_MANUAL_TRIGGER_SECRET (no new IaC). Security: same capability operator already has, time-delayed; comment + read-only registered check only; no issue close/edit/label mutation.
- CSRF: EXEMPT_ROUTES in lib/auth/csrf-coverage.test.ts keys on RELATIVE route-file path (app/api/internal/schedule-reminder/route.ts), not URL. Must add it there.
- function-registry-count route array 49→50; do NOT add event-* fn to cron-only guards (EXPECTED_CRON_FUNCTIONS / KNOWN_UNMONITORED_SLUGS / cron-monitors.tf). New tests run in isolation to dodge the signature-verify env-leak flake.

### Components Invoked
soleur:plan, soleur:deepen-plan (gates 4.4-4.9), Bash/Read/Write/Edit
