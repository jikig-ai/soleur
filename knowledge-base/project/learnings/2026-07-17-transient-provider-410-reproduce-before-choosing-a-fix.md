# Learning: a reported provider-API break (410/5xx) may be transient — reproduce on the pinned version before choosing a fix

## Problem

Issue #6636 reported that Sentry retired the legacy issue-alert **read** API
(`GET /projects/{org}/{project}/rules/{id}/`), returning `410 "This API no longer
exists"` on every one of 23 `sentry_issue_alert` resources — wedging the required
`sentry-destroy-required` gate + `apply-sentry-infra.yml` (the break was CI-fatal
because #6589, same day, had switched the apply to a full-root plan). The issue
proposed a heavy fix: migrate all 23 `sentry_issue_alert` → `sentry_alert` with
23× cross-type `state rm`+`import`.

## Solution

Phase 0 was a **measurement gate**: reproduce the break on the *pinned* provider
(`jianyuan/sentry 0.15.0-beta2`) against live Sentry state before choosing a fix.

- `terraform plan` on beta2 returned a **clean full-root no-op (0/0/0), zero 410s**
  — the retirement was **transient**; Sentry had restored the legacy endpoint by
  fix time. The heavy migration the issue proposed was not needed.
- The durable fix was a **provider version bump** to the stable `0.15.4`: per the
  v0.15.3 release notes, PR `jianyuan/terraform-provider-sentry#885` ("fix: Update
  reads from GET endpoint") moved `sentry_issue_alert` reads OFF the legacy
  endpoint, so 0.15.4 no longer depends on the retired read path — future-proofing
  against a *permanent* retirement without any state surgery.
- The `sentry_alert` migration stayed **deferred**: the `monitor_ids` blocker
  (#4610) persists at 0.15.4. ADR-031 amended; re-eval criterion updated to the
  default-monitor data sources.

Provider-version-only change (`versions.tf` + regenerated `.terraform.lock.hcl`);
no dropped paging rule (verified: full-root plan no-op across 23 issue + 49 cron +
4 uptime). 6-agent review found 0 P1s; security cryptographically verified the
lockfile against upstream signed SHA256SUMS.

## Key Insight

A reported external-API break is a **claim to reproduce**, not a fact to route on.
A 410/5xx-class provider failure can be a transient vendor incident that self-
resolves — reproducing it on the pinned version first (a) tells you whether *any*
fix is even needed and (b) prevents over-fixing (a 23-resource state-surgery
migration) when a version-only bump both clears the current failure AND future-
proofs against recurrence. State the durability differentiator's provenance
honestly: with the endpoint restored, `terraform plan` cannot observe the
read-path rework, so it is changelog-sourced, not plan-measured. This is
`hr-verify-repo-capability-claim-before-assert` applied to a vendor-API break.

## Session Errors

1. **`apps/web-platform/infra/sentry/README.md` §Local invocation was stale for
   the installed Doppler CLI** — the documented
   `doppler secrets get … --no-quote --plain --format env` failed with
   `unknown flag: --no-quote`; the cred eval then produced no exports, so the first
   `terraform init` errored on an AWS SSO fallback (R2 backend creds absent).
   **Recovery:** export each secret via `doppler secrets get <NAME> --plain`.
   **Prevention:** fixed the README inline to the per-secret `--plain` form AND to
   source `SENTRY_AUTH_TOKEN` from the Doppler `SENTRY_IAC_AUTH_TOKEN` (no
   personal-token mint — the operator-step the old snippet implied is unnecessary).

2. **Bash-tool CWD persistence** — a later `cd apps/web-platform/infra/sentry`
   failed (`No such file or directory`) because the CWD had already persisted into
   that dir from a prior call. Non-fatal (commands ran in the right dir).
   **Prevention:** use absolute paths or a single `cd <abs> && <cmd>` per call.

## Tags
category: integration-issues
module: apps/web-platform/infra/sentry
