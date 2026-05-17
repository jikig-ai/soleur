---
title: "Sentry support ticket drafts — PR-γ §17"
date: 2026-05-17
incident_pr: 3946
incident_ref: 3861
audience: operator
status: drafts-awaiting-paste-and-submit
---

## Purpose

Two separate Sentry support tickets to submit via `https://sentry.io/support/` per `knowledge-base/project/brainstorms/2026-05-16-sentry-residency-a2-branch-c-brainstorm.md` Decision #9. Submit each via a **new** form (not threaded) — the routing logic at Sentry differs for billing vs forensics, and threading them risks one decision dragging on the other.

Operator action: paste each ticket body into the Sentry support form, submit, then capture the ticket ID (e.g., `#1234567`) in PR #3946 body under `## AC13 — Sentry support ticket IDs`. T+14d countdown for PIR Phase 8 Gate 3 anchors on Ticket 2 submission timestamp.

---

## Ticket 1 — Billing (refund + cancellation)

**Subject:** Prorated refund for Team trial activated in error during IaC misconfiguration

**Body:**

```
Hello Sentry billing,

We activated a Team-plan trial on the `jikigai` organization on the US cluster (`sentry.io`) on 2026-05-16 in error. The activation was a side-effect of an internal IaC misconfiguration during a Sentry residency cleanup project — our intended production residency is the EU cluster, and we have since stood up a fresh DE org (`jikigai-eu`) on `eu.sentry.io` with our own admin control and runtime DSN.

The US `jikigai` Team subscription has been cancelled with the standard end-of-billing-cycle effective date of 2026-06-14 via the org's General Settings page.

We are requesting a prorated refund for:

  1. The unused portion of the US Team plan (cancellation effective 2026-06-14 — we have not used the Team-tier features since the cluster cutover on 2026-05-17).

  2. The $5.46 of pay-as-you-go burn that accrued on the US org during the IaC misconfiguration window, prior to our cluster cutover.

We are not requesting any contractual concession beyond the prorated refund — the IaC mistake was ours, and we want to settle the billing record cleanly so we can continue using `eu.sentry.io` as a long-term customer.

If you need invoice / charge IDs or org IDs for the audit trail, our US `jikigai` org's settings page is at `https://sentry.io/settings/jikigai/`. Happy to provide whatever billing artifacts make the refund clean to process on your side.

Thank you,
Jean Deruelle
Jikigai
jean.deruelle@jikigai.com
```

**After submission:**

- Capture ticket ID in PR #3946 body under `AC13 — Sentry support ticket IDs`.
- Note submission timestamp.

---

## Ticket 2 — Forensics (owner-history confirmation)

**Subject:** Owner-history confirmation for org ID 4511123328466944 — closing Article 30 sub-processor audit

**Body:**

```
Hello Sentry support,

I am reaching out separately from a billing matter (filed under a separate ticket) on a forensics question that we need an authoritative answer on to close an internal Article 30 (GDPR sub-processor) audit.

Our prd runtime Sentry DSN was, between 2026-03-28 and 2026-05-16, configured to point at:

  https://o4511123328466944.ingest.de.sentry.io/4511123344654416

Destination org ID: 4511123328466944
Destination project ID: 4511123344654416
Cluster: de.sentry.io (ingest)

This DSN was introduced into our Doppler prd secret store via an internal PR (#1235, 2026-03-28). When we attempted to audit the destination org as part of a residency cleanup project on 2026-05-16, we discovered:

  - Our account (jean.deruelle@jikigai.com) has no admin or member visibility into org ID 4511123328466944.
  - `eu.sentry.io/auth/login/` returns an org-membership banner when we attempt to authenticate against any org slug on the EU cluster ("not a member of the eu organization").
  - Our runtime `SENTRY_AUTH_TOKEN` returns 302→401 against `/api/0/organizations/jikigai/` on the EU edge — i.e., no `jikigai` slug exists on `eu.sentry.io` that we are members of.
  - The DSN was nonetheless accepting envelope POSTs (200 responses on ingest), routing user-error envelopes for approximately 49 days to a destination we cannot enumerate, audit, or administer.

We have since cut over runtime ingestion to a freshly-provisioned DE org (`jikigai-eu`) under our admin control. The phantom-org DSN is fully drained from all secret stores and no further envelopes are being emitted.

For our Article 30 sub-processor audit, we need an authoritative answer to the following:

  1. Is org ID 4511123328466944 currently owned by an entity other than Jikigai?

  2. If yes — at what date was that org created, and (to the extent your privacy policy permits) is the owning entity a separate Sentry customer (in which case we would treat them as an unintended cross-org-routing recipient and document the residual under GDPR Article 30 §5(2)) or a Sentry-internal / staging / test entity?

  3. If no (i.e., the org was originally provisioned under our account and we simply lost discovery / privilege visibility) — please provide whatever evidence is appropriate so we can re-establish admin control and treat this as a self-org recovery rather than a cross-org disclosure event.

We understand owner-history may be restricted by privacy policy or by Sentry-internal escalation review. If a determinate answer is not available, a clear statement of policy ("Sentry does not disclose owner-history for orgs you are not a member of") is also useful — we will document the enumeration-gap as the residual ceiling under our internal post-incident review (currently published at our internal runbook for this incident).

We are not seeking a contractual remedy here — only the forensics signal we need to close the audit cleanly. Happy to provide any additional context.

Thank you,
Jean Deruelle
Jikigai
jean.deruelle@jikigai.com
```

**After submission:**

- Capture ticket ID in PR #3946 body under `AC13 — Sentry support ticket IDs`.
- Capture submission timestamp — this is the **anchor for T+14d countdown** on PIR Phase 8 Gate 3 (`knowledge-base/engineering/ops/runbooks/sentry-phantom-ingest-destination-unreachable-postmortem.md`).
- T+14d resolution branch (3a/3b/3c/3d) is selected at countdown expiry and recorded in-place in the PIR.

---

## Submission checklist

- [ ] Ticket 1 (billing) submitted via `sentry.io/support/`. ID: `__________`. Submitted: `____-__-__T__:__Z`.
- [ ] Ticket 2 (forensics) submitted via `sentry.io/support/`. ID: `__________`. Submitted: `____-__-__T__:__Z`.
- [ ] Both ticket IDs + submission timestamps captured in PR #3946 body (AC13).
- [ ] T+14d gate clock noted in operator calendar.
