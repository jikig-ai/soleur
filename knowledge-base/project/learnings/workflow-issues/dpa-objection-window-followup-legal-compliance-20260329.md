---
module: Legal Compliance
date: 2026-03-29
problem_type: workflow_issue
component: documentation
symptoms:
  - "DPA contractual objection window (5 days) expired before vendor responded to compliance questions"
  - "Conflicting notice periods: DPA Section 6.5 says 5 days, vendor email stated 30 days"
  - "No defined escalation process for DPA sub-processor objection deadlines"
root_cause: missing_workflow_step
resolution_type: workflow_improvement
severity: high
tags: [dpa, gdpr, supabase, objection-window, sub-processor, compliance]
---

# Troubleshooting: DPA Sub-Processor Objection Window Expired Before Vendor Response

## Problem

Supabase notified us on 2026-03-23 of a new sub-processor (Braintrust Data, Inc). We sent 10 compliance questions the same day. By 2026-03-29 (6 days later), the 5-day contractual objection window under DPA Section 6.5 had expired with no response from the vendor, leaving our compliance position ambiguous.

## Environment

- Module: Legal Compliance / DPA Management
- Affected Component: Supabase DPA (August 5, 2025 version, signed 2026-03-19)
- Issue: #1056
- Date: 2026-03-29

## Symptoms

- DPA Section 6.5 objection window (5 days from notice) expired on 2026-03-28
- Vendor email stated 30-day notice period, contradicting the 5-day contractual period
- 10 substantive compliance questions sent 2026-03-23 remained unanswered after 6 days
- Unable to evaluate whether new sub-processor (Braintrust) processes data from all projects or only AI Assistant users
- Compliance posture document showed status "PENDING RESPONSE" with no escalation trigger

## What Didn't Work

**Direct solution:** The problem was identified and resolved on first CLO assessment. No failed attempts.

## Session Errors

None detected.

## Solution

CLO assessment determined the position is defensible despite the expired contractual window, based on three factors:

1. **Same-day engagement:** Questions sent within hours of notice demonstrates active oversight, not passive acceptance
2. **Estoppel argument:** Vendor's own email stated 30 days; under Irish law (DPA governing law), the vendor cannot enforce the shorter contractual deadline when their communication created a reasonable expectation of the longer period
3. **Unanswered threshold questions:** Acceptance cannot be inferred when the controller's lawfulness questions remain open

**Action taken:** Follow-up email sent 2026-03-29 to `privacy@supabase.io` that:

- Referenced the March 23 notification and its stated 30-day period
- Formally reserved objection rights under Section 6.5 until questions are answered
- Reiterated blocking questions (#1 scope, #2 data categories, #4 data residency, #5 eu-west-1 compliance)
- Set a 7-day response deadline (2026-04-05) with formal objection warning

**Tracking updated:** `compliance-posture.md` updated from "PENDING RESPONSE" to "FOLLOW-UP SENT" with 2026-04-05 deadline.

## Why This Works

The root cause was a missing escalation workflow: when a DPA sub-processor notice arrives with an objection window, there was no defined process for what happens if the vendor doesn't respond before the window closes.

The follow-up email works because:

1. It creates a documented paper trail showing active exercise of controller oversight obligations under GDPR Article 28(2)
2. The estoppel argument (vendor represented 30 days, cannot enforce 5) is strongest when the controller can show continuous engagement from day one
3. Setting a concrete deadline with a formal objection warning forces the vendor to either respond or face a documented objection

## Prevention

- **When receiving any DPA sub-processor notice:** Immediately check both the email's stated period AND the contractual objection period (they may differ)
- **If the contractual period is shorter than communicated:** Send a same-day response that explicitly references the longer communicated period and reserves rights under the contractual clause
- **Set a calendar deadline at contractual_window - 2 days** for a follow-up if no response received, rather than waiting until after expiry
- **Add a deadline field to compliance-posture.md** for all active items with objection windows (done in this session)
- **Decision tree:** If vendor doesn't respond within the contractual window and questions are blocking, send a formal follow-up preserving rights before the communicated window closes

## Related Issues

- See also: [2026-03-19-dpa-vendor-response-verification-lifecycle.md](./dpa-vendor-response-verification-lifecycle-20260319.md) (lifecycle for when vendors DO respond)
- See also: [2026-03-11-third-party-dpa-gap-analysis-pattern.md](../2026-03-11-third-party-dpa-gap-analysis-pattern.md) (Art. 28(3) compliance matrix)
- Issue: #1056 (tracking issue for this DPA review)
