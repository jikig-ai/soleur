# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-11-security-legacy-owner-gate-all-approval-tools-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)
- cto_spawns=2 (ruling-gate batch: rows 17, 29-32, 37, 38 and AC20)

### Errors
- gh issue create hook blocks (fixed; filed #12657, #12660-#12664). Scope Check format rewritten. Two markdownlint fixes.

### Decisions
- Owner-only legacy card for all 8 approval-required tools; fail closed; abort keeps gateExpiredDeny.
- Added by CTO: role re-read after Approve (S1); cap re-check after the role deny (F10, S3); role_read_timeout code (O1); log fields (O2-O4); email/trigger descriptions name the Owner (F5, F11); dev probe stub (F12).
- Battery: G1-LO1..G1-LO10; MIN_MUTANTS 366, MIN_KILLED 360, MIN_CHECKS 784; new FLOOR entry for legacy-push-owner-fallback.test.ts.
- AC20 pre-merge read-only check (CTO U1).

### Components Invoked
- soleur:plan, soleur:plan-review, soleur:deepen-plan, soleur:engineering:cto, soleur:product:cpo, soleur:legal:clo, soleur:gdpr-gate

## Operator Constraints

- constraint: no production writes
- constraint: do NOT touch the approval-queue flag and never put the flag-flip script name in a Bash command
- constraint: no byte change to docs/legal or Eleventy legal mirrors
- constraint: founder-acceptance-record.md sha256 must stay 10d283e02d4543d291468750655bbaf4375f807a585cd5138724a362b993a287
- constraint: LEGAL_COPY.PROVISIONAL stays true
- constraint: never edit apps/web-platform/infra/sentry
- constraint: Before every commit run markdownlint-cli2 on every touched .md
- constraint: Merge only via the merge queue after PR CI is green
- constraint: Operator instruction, rely on CI rather than long local full-battery runs.
- ci-is-the-gate: Operator instruction, rely on CI rather than long local full-battery runs.
