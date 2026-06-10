# Learning: Proton capability facts (no API/JMAP/OAuth; IMAP = Bridge) and how to overturn a recorded deferral without forking it

## Problem

The #5103 brainstorm (operator inbox delegation) hit three intertwined issues:

1. The issue body's architecture premises were wrong: it proposed "IMAP/JMAP polling of a
   dedicated address on existing Proton Workspace ($0 marginal)" as the cheapest slice and
   "OAuth (Gmail/Microsoft Graph/IMAP bridge) read + draft scopes" as an alternative.
2. The capability it proposed had been validated and **FAILED** a week earlier
   (2026-06-02 brainstorm → deferred #4788 with three ALL-required flip conditions), and
   the operator wanted to proceed anyway.
3. The spec Write was blocked by the IaC routing gate because Proton-side steps (create
   an address, set a Sieve rule) pattern-matched manual provisioning.

## Solution

1. **Proton capability facts (verified live 2026-06-10; no prior KB learning existed):**
   - Proton has **no JMAP support at all** (JMAP is Fastmail's protocol).
   - Proton has **no public management API, no OAuth, and no Terraform provider** —
     mailbox addresses and Sieve filters are admin-UI-only configuration.
   - **IMAP/SMTP exist only via Proton Bridge**, a stateful desktop-class daemon: headless
     operation needs community (not official) Docker images, an interactive first login,
     and a local keychain. Critically, the Bridge credential is **send-capable and
     full-mailbox — Proton has no read-only or scoped token**. "Read-only polling" on
     Proton is a convention in caller code, not a property of the credential.
   - Consequence: for agent ingestion of Proton mail, **Sieve auto-forward to a webhook
     front door (e.g., Resend Inbound) strictly dominates polling** — no credential exists
     anywhere, and the leak surface collapses to one rotatable webhook signing secret.
2. **Deferral-override recording pattern:** when an operator explicitly overturns a
   recorded validator FAIL / deferral, (a) state in the new brainstorm exactly which
   deferral conditions are satisfied vs. overridden and why; (b) post a comment on the
   deferred issue itself recording the partial override and its scope, keeping the issue
   open for the un-overridden remainder; (c) inherit the deferral's captured
   build-decisions (K6-style "if/when built" lists) verbatim into the new spec instead of
   re-deriving. This keeps one source of truth and avoids a silent fork.
3. **IaC gate + API-less vendors:** when a vendor genuinely exposes no API/provider
   (verified, not assumed — `hr-verify-repo-capability-claim-before-assert`), satisfy the
   IaC routing gate with `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->` plus an
   `## Infrastructure (IaC)` section that routes everything Terraform-manageable (DNS,
   Sentry monitors, secrets) through the existing roots and names the API-less remainder
   explicitly, with in-session browser automation per
   `hr-exhaust-all-automated-options-before`.

## Key Insight

An issue body's "cheapest option" claim is an architecture decision made without
verification — here the "$0 IMAP slice" was actually the *highest-risk* option (full
send-capable credential + unofficial daemon + egress widening), and the genuinely cheap
option (forward-to-webhook) only surfaced because leaders verified vendor capabilities
live instead of accepting the enumeration. Pair every "cheapest" label with a credential
blast-radius column before choosing.

## Session Errors

1. **IaC routing gate denied the first spec Write** (manual-provisioning patterns from
   Proton-side steps). Recovery: ack comment + `## Infrastructure (IaC)` section
   separating Terraform-routed resources from the verified API-less remainder.
   **Prevention:** when a spec includes vendor-side steps, verify the vendor's API/provider
   surface first; if none exists, write the IaC section + ack in the first draft.
2. **Issue-body premise drift propagated into the brainstorm framing** (JMAP unsupported;
   IMAP cost mischaracterized; OAuth infeasible on Proton). Recovery: CTO/COO live
   verification corrected all three before approach selection; corrections recorded in the
   brainstorm's Session Errors and the issue's Artifacts note. **Prevention:** this file
   now carries the Proton facts; future email-surface brainstorms should grep learnings
   for `proton` before accepting any polling/OAuth premise.
3. **Wireframe subagent needed a placeholder commit before `open_document`** (pre-open
   git guard), producing two commits instead of one. One-off, by-design guard.
   **Prevention:** none needed; guard behaved as intended.

## Tags

category: integration-issues
module: email-infrastructure, brainstorm-workflow
