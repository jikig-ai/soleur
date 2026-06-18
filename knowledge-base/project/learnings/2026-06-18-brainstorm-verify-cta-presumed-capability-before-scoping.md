# Learning: A "connect X" CTA is a capability claim — grep the ingestion/config path before scoping it

## Problem

During the `/dashboard/inbox` surface brainstorm (#5512), the operator asked to add a CTA
"for the founder to sign up and set up an email address, or connect to an existing email
provider (Google, Proton…) if there is no setup yet." Taken at face value, that reads as a
small empty-state affordance to fold into an XS presentation PR.

The presumption baked into the CTA — that an email-connection / per-founder-setup capability
exists or is trivial — was false.

## Solution

Before folding the CTA into scope, a 2-command probe was run *during the brainstorm dialogue*:

1. `git grep -lniE "inbound|receive.*email|forward.*email|mailgun|postmark|ses.*receive"` and
   `git grep -lniE "email_triage_items"` → surfaced `app/api/webhooks/resend-inbound/route.ts`,
   `server/inngest/functions/email-on-received.ts`, and `infra/{dns,resend}.tf`.
2. Read the inbound webhook + the attribution logic → the inbox is **single-tenant**: one fixed
   inbound address (operator `ops@` → `inbound.soleur.ai`, Resend Inbound/AWS SES, provisioned in
   Terraform), and every received email is stamped to ONE hardcoded owner via the env var
   `EMAIL_TRIAGE_OWNER_USER_ID` (`email-on-received.ts:310`). No per-founder signup, no
   recipient-based routing, no Gmail/Proton OAuth ingestion (Proton has no public API — Bridge/IMAP
   only; Gmail OAuth = major GDPR/sub-processor surface).

The CTA had nothing real to link to. Correct move: **decouple**. Ship the XS presentation surface
(top-level nav entry + Command Center "View all →" link + list page + Active/Archived tabs +
reassuring empty-state with NO connect CTA), and file the email-onboarding/connection capability
as its own follow-up brainstorm (#5527, needs CLO+Ops+CTO).

## Key Insight

A CTA / empty-state that says "connect X" or "set up X" is a *claim that an X-connection
capability exists or is in scope*. Before sizing it, grep the data-ingestion/config path:
the webhook/receive route, the **env var or column that attributes records to a user/workspace**,
and the IaC for the address/credential. Single-tenant infra constants (`ONE_OWNER_ENV`, one
provisioned address) routinely masquerade as multi-tenant features in a feature request. The
probe is seconds; doing it *during dialogue* (not after) prevents a multi-week capability from
being silently folded into an XS PR, and produces the right decouple-and-defer split instead.

This is the ingestion-side mirror of the existing brainstorm Phase 1.1 checks ("is X mounted?",
"verify cited infra prereq against the IaC root") — applied to *attribution/tenancy* rather than
existence.

## Tags
category: workflow-patterns
module: brainstorm, email-triage
issues: 5512, 5527
