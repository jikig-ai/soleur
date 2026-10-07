# Learning: Resend Inboxes evaluation — the "custom SNS stack" was already Resend

## Problem

The request framed the current inbound-email solution as "custom built with Amazon SNS and the probe". Evaluating Resend Inboxes against that description would have compared the vendor to a stack that does not exist.

## Solution

Grepped before spawning leaders: `git grep` on main and recent commits found no SNS, SES or `@aws-sdk` usage in `apps/web-platform` or infra. The real stack is Resend Inbound (ADR-055: Proton Sieve forward → Resend → svix webhook → Inngest → summary-only `email_triage_items`, plus `cron-email-ingress-probe`). Only Resend's receiving MX host (`inbound-smtp.eu-west-1.amazonaws.com`) is AWS, and it is Resend's own infrastructure. The correction was stated to the operator in the same message as the comparison, and all five parallel agents were handed it as a verified fact.

## Key Insight

An operator's description of an existing system is a claim about the repo, so verify it with one grep before it sets the baseline of a comparison. "Resend's MX is AWS" is the likely origin of the SNS memory: a vendor's infrastructure reads as ours when we only see the DNS record.

## Session Errors

1. **Premise stated by the request did not match the repo (SNS).** Recovery: `git grep` for SNS/SES/aws-sdk, correction surfaced alongside the comparison. Prevention: already covered by brainstorm Phase 1.0.5 premise validation; no new rule.
2. **`gh issue create --body-file "$D/issue-prep.md"` refused by the filing gate** (it does not expand `$VARIABLES`, and it refuses two filings chained in one command). Recovery: literal absolute path, one filing per Bash call. Prevention: added to brainstorm Phase 3.6 step 7 (the filing-gate bullet).

## Tags

category: workflow-issues
module: brainstorm
