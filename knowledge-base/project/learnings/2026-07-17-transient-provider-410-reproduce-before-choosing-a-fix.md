# Learning: a reported provider-API break (410/5xx) may be transient — reproduce on the pinned version before choosing a fix

> **SUPERSEDED 2026-08-19 (#7590) — the generalisable rule below is HALF retracted; read
> [§ Supersession](#supersession-2026-08-19-7590) before applying it.** "Reproduce before choosing
> a fix" stands. "A clean reproduce means the break was transient" does **not**: the #6636 endpoint
> was permanently deprecated on 2026-05-14 and served under scheduled brownouts, so the clean
> `terraform plan` that this file reads as *recovery* only means the probe landed between windows.
> This file is retrieved by `learnings-researcher` on vendor-API breaks — do not lift its Key
> Insight without the correction.

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

## Supersession (2026-08-19, #7590)

Dated record; measurements preserved. The Phase 0 plan really did return `0/0/0` with zero 410s on
beta2. The inference drawn from that observation is retracted.

**What is retracted.** "The retirement was **transient**; Sentry had restored the legacy endpoint by
fix time." Sentry restored nothing. It deprecated the alert-rule API family on **2026-05-14** and
serves it under **scheduled brownouts** — 410 inside a recurring window, 200 outside it. Measured on
2026-08-19 in a single session, same token, same host, nothing changed on our side: 410 at ~20:5x
UTC, then 200/200/200 at 21:23 UTC.

**Why this file matters more than the incident report it summarises.** Its Key Insight is written as
a *general rule* for any vendor-API break, so it is what a future search retrieves. Split it:

| Clause | Verdict |
|---|---|
| "A reported external-API break is a **claim to reproduce**, not a fact to route on." | **Stands.** This is the right instinct and it is why the over-fix was avoided. |
| "Reproducing it on the pinned version first tells you whether *any* fix is needed." | **Stands, weakened.** It bounds the blast radius of the fix; it does not establish the vendor's state. |
| "A 410/5xx-class provider failure **can be a transient vendor incident that self-resolves**." | **Retracted as the default reading.** A deprecation served under brownouts is observationally identical to a transient incident from a single probe, and is far likelier for a documented API family. |
| "…so the heavy migration was not needed." | **Retracted, and the replacement reason is retracted too.** The first correction to this file said `0.15.4` was right "because its read path is not in the deprecated family". That was changelog-sourced and never measured; CI has since refuted it (see below). Deferring the migration was still the right *call* — it is blocked on `monitor_ids` regardless — but the 410 is not fixed. |

**The durability claim was refuted too — by CI, on 2026-08-20.** This file's Solution says the
`0.15.4` bump "future-proof[s] against a *permanent* retirement", sourced from the v0.15.3 changelog
(`#885`, "fix: Update reads from GET endpoint"). It was never measured, and could not be: observing
it requires a request inside a brownout window. With `jianyuan/sentry v0.15.4` installed, run
`32362401543` (2026-08-20T11:09:07Z) took `410 "This API no longer exists"` on **29 of 29**
`sentry_issue_alert` reads and failed `terraform plan`; run `32362320701` **one minute earlier**
(11:08:09Z), same branch and same pin, passed. The alternation repeats on 2026-08-19 (17:43 pass /
18:26 fail; 21:21 pass / 21:30 fail). So `0.15.4` still reads the deprecated path and the sentry
Terraform root is still wedged by every brownout. Two lessons compound here: the probe-and-conclude
stopping rule below, and **a changelog datum standing in for a measurement the environment made
impossible at the time** — the second is what let a documented-as-unverified claim harden into
"future-proofed" across four artifacts.

**The corrected rule.** A single clean re-probe cannot distinguish *"restored"* from *"outside the
next window"*, so it is not a valid stopping condition for a schedule-shaped failure. Before
concluding "transient", read the response headers — `x-sentry-deprecation-date` and
`x-sentry-replacement-endpoint` named this retirement directly and were present the whole time —
or probe across more than one window. Prefer the header: it is the vendor asserting its own state,
where a probe only samples it. Generalised: **when the failure could be scheduled, absence of the
failure at one instant is not evidence of its absence.** #7590 ships that header check as a
tripwire so the next deprecation self-reports on its first **200**.

**Cross-references.**
`knowledge-base/engineering/operations/post-mortems/sentry-issue-alert-410-transient-wedge-postmortem.md`
(§ Supersession), `knowledge-base/project/plans/2026-07-17-fix-sentry-issue-alert-410-provider-bump-plan.md`
(§ Supersession), `apps/web-platform/infra/sentry/versions.tf`, ADR-031 §Amendment 2026-08-19
(#7590), and the successor learning
`knowledge-base/project/learnings/integration-issues/2026-08-19-a-vendor-brownout-is-not-a-flake-and-the-header-said-so-all-along.md`.
