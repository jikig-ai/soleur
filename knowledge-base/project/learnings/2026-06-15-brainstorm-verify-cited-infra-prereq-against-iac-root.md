# Learning: A cited infra/domain-auth requirement must be verified against the IaC root before treating it as an in-feature checklist item

## Problem

The #5325 brainstorm (agent-native outbound email) opened with an issue body whose
checklist treated three things as if they were equal-weight in-feature line items:

1. "Neither a human nor an agent can send an email from Soleur today" — **false**. The
   send *primitive* already existed: `apps/web-platform/server/notifications.ts` wraps
   `resend.emails.send()` with header-injection hygiene, and
   `cron-email-ingress-probe.ts` also sends. The real gap was narrower: an
   agent-callable cold-outbound tool + a compliance gate + campaign/suppression
   persistence + domain auth.
2. "SPF/DKIM/DMARC for jikigai.com" listed as one checkbox among many — but
   `apps/web-platform/infra/dns.tf` is a **single-zone root** (`var.cf_zone_id` =
   soleur.ai). `jikigai.com` appears in **zero** Terraform; it exists only as the
   operator `ops@` recipient string for jikigai.com in `infra/variables.tf`. So the
   "domain auth" checkbox is actually a **blocking zone-onboarding prerequisite**, not an in-feature task.
3. The issue proposed adding outbound send/reply authority, but a prior LIA
   (`knowledge-base/legal/legitimate-interest-assessments/2026-06-11-operator-inbox-triage-lia.md`)
   **explicitly deferred** that authority ("Not pursued under this LIA: any outbound
   reply authority"). #5325 overturns a recorded deferral.

## Solution

Three pre-spawn verification probes (run from inside the worktree, against `main`/IaC,
before committing to the issue's framing):

1. **Capability-claim probe:** grep for the *primitive symbol* the claimed-missing
   capability would need (`resend.emails.send`) before accepting "X doesn't exist."
   (Already covered by `hr-verify-repo-capability-claim-before-assert` and the brainstorm
   skill's "Verify … claims" Sharp Edges.)
2. **Infra-prereq probe (net-new):** for any cited infra/domain-auth requirement
   (SPF/DKIM/DMARC/MX for domain X, a Cloudflare zone, a Terraform-managed resource),
   grep the IaC root (`infra/dns.tf`, `*.tf`) for the domain/zone *before* sizing it as
   an in-feature checklist item. If the zone is absent from IaC, it is a **blocking
   prerequisite** with its own onboarding cost and token-reachability question
   (`hr-fresh-host-provisioning-reachable-from-terraform-apply`), not a checkbox. The
   "inbound already works at the operator ops@ address on jikigai.com" fact does NOT imply the zone is IaC-managed.
3. **Overturned-deferral probe:** when adding an authority, grep the
   legitimate-interest-assessments / ADR / deferred-issue corpus for a prior decision
   that *declined* it. If found, the brainstorm needs the superseding artifact (new/amended
   LIA, ADR) as a first-class deliverable — not just code.

## Key Insight

A capability-existence claim and an infra-readiness claim fail in **opposite directions**
and need **different probes**: the capability claim tends to *understate* what exists
(grep the primitive), while the infra/domain-auth claim tends to *overstate* readiness by
listing a not-yet-provisioned zone as a checkbox (grep the IaC root). Verifying both before
leader spawn turns a flat issue checklist into a correctly-sequenced plan: blocking prereq
(zone onboarding + LIA) → pilot capability (gate + tool + tables).

## Session Errors

Session error inventory: none detected. All three premise refinements were caught by
pre-spawn verification probes, which is the intended behavior — they are documented here as
the reusable *method*, not as session errors.

## Tags
category: workflow-patterns
module: brainstorm
related: 2026-06-12-brainstorm-verify-capability-claims-against-code-and-decouple-build-from-news-window.md, 2026-05-05-brainstorm-capability-gaps-need-repo-grep.md
