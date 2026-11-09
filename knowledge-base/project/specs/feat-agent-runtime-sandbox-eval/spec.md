---
feature: agent-runtime-sandbox-eval
issue: 12517
lane: cross-domain
brand_survival_threshold: single-user incident
date: 2026-11-09
brainstorm: knowledge-base/project/brainstorms/2026-11-09-agent-runtime-sandbox-eval-brainstorm.md
---

# Feature: agent runtime sandbox evaluation (injector-first)

## Problem Statement

Web-egress-entitled hosted sessions hold no credential, so they cannot push, call `gh`, or use a connected provider from inside the sandbox. The route in progress, one approval-gated server-side tool per verb (#12467), costs about 41 files per gated write tool and grows with every verb. Egress-side credential injection would cover every HTTPS-credentialed tool with one mechanism, but nothing on our egress hop terminates TLS, the only in-SDK candidate did not substitute on our carrier (ADR-311), and a 2026-11-09 ruling to keep our own sandbox was made without a vendor comparison.

## Goals

- Record that egress credential injection is a substrate-independent hop, decided separately from the isolation runtime.
- Produce a go/no-go, against criteria fixed before the run, on a self-run TLS-terminating injector for GitHub hosts on today's hop.
- Produce a measured contingency: a Cloudflare Sandbox trial on synthetic data within USD 50 and 14 days.
- Record the flip facts that would make a managed sandbox platform the primary path.
- Keep #9842 as the owner of the isolation runtime, and feed it the results.

## Non-Goals

- Choosing or changing the isolation runtime (#9842, #9854).
- Shipping a credential-bearing surface to any tenant. The spike measures; it ships no broker (ADR-311 Decision 1).
- Injection for non-GitHub providers, SSH git, or database connection strings.
- Moving tenant data or real credentials to a vendor.
- Rewording any public or legal text (ADR-311 Decision 6).
- Further per-verb GitHub write tools while the spike runs (#12467 is paused).

## Functional Requirements

### FR1: Decision record

A decision record states that injection is a substrate-independent hop gated by ADR-309 approvals, lists the options ranked on the operator's criterion, and carries the flip facts and the CLO gates for a managed platform. It amends ADR-311 Decision 4 only if the spike measures a hook that satisfies it.

### FR2: Injector spike result

A results note records pass or fail for each of the seven criteria in the brainstorm's "Spike go/no-go criteria", with raw outcomes, on the production run tuple.

### FR3: Cloudflare trial result

A results note records each item in the brainstorm's "Cloudflare trial must measure" list, the amount spent, and confirmation that the trial resources were torn down.

### FR4: Disposition of dependent work

On a spike pass, #12467 is closed as superseded and #11637 proceeds from the measured mechanism. On a fail, #12467 resumes and the flip facts are evaluated.

### FR5: Epic alignment

S3 (#9845) is widened to generic per-host injection with approval attachment, and S0 Arm D (#9859) is widened from paperwork to the Cloudflare trial. Both link to this spec.

## Technical Requirements

### TR1: No credential observable in the sandbox

The real credential never appears in the sandbox's environment, files or process list. Only a placeholder is present.

### TR2: Approval attachment

Every mutating request consumes exactly one unconsumed ADR-309 action-bound row before the credential is attached. With the `approval-queue` flag off, every vend is denied. A denied mutating request creates the pending row. Allowlisted reads (GET/HEAD on a per-workspace path allowlist, repo-scoped token) vend without a row.

### TR3: CA scope

One ephemeral interception CA per session, name-constrained to the inject hosts, with its key held outside the sandbox. A shared CA is a fail.

### TR4: Tenant binding

The tenant is derived server-side from the authenticated session, never from a value the sandbox controls. A two-tenant probe proves session A cannot obtain session B's credential.

### TR5: No regression of ADR-278

Default-deny egress, blocked targets and the existing allowlists behave as before. The injector logs no request body.

### TR6: Legal gates before merge

The DPIA re-screen (trigger t3 of the 2026-10-05 screening) completes before any TLS-terminating gateway merges to a path that serves tenants. `soleur:gdpr-gate` runs at plan Phase 2.7.

### TR7: Trial hygiene

The Cloudflare trial uses synthetic workspaces and decoy credentials only, a hard ceiling of USD 50 over 14 days, and ends with a verified teardown. The exact account change is named and confirmed in-session before it is made.

### TR8: Observability

Every vend, refusal and approval consumption in the spike emits a monitored marker, and every refusal is mirrored to Sentry (ADR-311 Decision 5).

### TR9: Measurement record

Results state the machine class and date, label each claim as measured, read from a file, or unverified, and name the re-measure trigger (a change to the SDK pin or to the sandbox flags).
