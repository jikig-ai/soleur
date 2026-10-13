---
lane: single-domain
issue: 3924
---

# Spec: rewrite cla-evidence runbook §7 admin-override for R2 Lock Rules

## Summary

Close the legal-ops gap created by PR #3920: the runbook §7 still documents the S3 Object Lock `--bypass-governance-retention` path that R2 does not implement. Ship a tested driver (`apps/cla-evidence/scripts/gdpr-override.sh`), a dry-run test, and a rewritten §7.1/§7.3.

## Functional Requirements

- **FR1.** `gdpr-override.sh` mints/accepts a one-hour CF admin token, performs GET → modify → PUT → DELETE → PUT-restore → tombstone → self-revoke against the `soleur-cla-evidence` R2 bucket.
- **FR2.** Three rule-edit shapes are supported (`enabled-false` default; `age-1s` fallback; `narrow-prefix` gated behind explicit ack flag).
- **FR3.** Dry-run mode (`--dry-run`) stubs all network IO and prints the planned sequence.
- **FR4.** PUT-restore must be byte-equal to the GET-time snapshot. Verified via `main.test.sh --live --strict-rule-count`.
- **FR5.** Tombstone (§7.4 schema, unchanged) is written ONLY after DELETE + restore both succeed.
- **FR6.** Self-revoke is skipped if restore fails (operator needs the token).
- **FR7.** Runbook §7.1 and §7.3 are rewritten to reference the driver; stale-warning banners are dropped from header + §7.1 + §7.3.
- **FR8.** Legal-prose at `docs/legal/gdpr-policy.md` §3.4 sub-bullet (3) is unchanged; re-verified against the runbook rewrite.

## Test Strategy

PATH-stub bash tests (matching `upload-bypass.test.sh` convention); 10 cases covering happy paths × 3 shapes, 3 failure modes, 4 validation errors. No live network IO in tests.

## Non-functional Requirements

- ShellCheck clean.
- No secrets in argv or stdout/stderr (TS-OVERRIDE.j asserts).
- No new package.json dependencies.
- Idempotent on retry (verify steps are read-only).

## Provenance

PR #3920 multi-agent review finding #2 (git-history-analyzer); plan at `knowledge-base/project/plans/2026-05-17-feat-r2-lock-rules-gdpr-override-plan.md`.
