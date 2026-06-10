---
date: 2026-06-10
topic: operator-inbox-delegation
status: complete
lane: cross-domain
brand_survival_threshold: single-user incident
tracking_issue: 5103
decision: overturn-deferral-build-narrow-read-only-triage
related: [4788, 4671, 4672, 5125]
---

# Brainstorm: Operator Inbox Delegation (read-only email triage)

## What We're Building

A **narrow, read-only inbound-email triage slice** so agents — not the operator — read
and prioritize vendor/billing/ops mail arriving at a dedicated company address:

```text
ops@soleur.ai (new $0 address on existing Proton Workspace)
  └─ Proton Sieve auto-forward
       └─ Resend Inbound (3rd multi-source ingress, alongside Stripe + GitHub/ADR-036)
            └─ webhook → Inngest
                 ├─ statutory-class deterministic fast-path (NO LLM) → operator + clock stated
                 └─ LLM summarize (read-only, no tools) → conversation inbox item + Slack ping
```

No mailbox credential exists anywhere in the system — agents see forwarded copies only.
No autonomous send; draft-then-approve replies are a later increment blocked on #4672.
Raw bodies are parsed and discarded (summary + headers + sender + WORM received-at kept).

### Operator override (recorded per premise-validation branch c)

This brainstorm **explicitly overturns** the 2026-06-02 business-validator FAIL /
#4788 deferral on the operator-dogfood framing. Of #4788's three ALL-required flip
conditions: (2) "one concrete action surfaced into the existing conversation inbox" is
**satisfied** (the inbox + `action_sends` substrate shipped via #1690 / PR #4077);
(3) "statutory-class mail never reaches the LLM act path" is **satisfied by design**
(deterministic fast-path before any LLM, read-only LLM with no act path at all);
(1) "named second consumer from the #1439 cohort" is **unmet and overridden** — the
operator accepts the build-for-ourselves risk as internal dogfood, judged on
operator-time ROI, with the #4825 actor-narrowing framing split as precedent. The
prompt-injection cap flagged by the validator (#4671 still open) is mitigated, not
dissolved: the triage agent is read-only with no tools, so injection can only distort a
summary, never trigger an action.

## User-Brand Impact

- **Artifact:** inbound senders' PII (uncontrolled free-text email from involuntary data
  subjects, special-category content will arrive) + the mailbox surface itself.
- **Vector:** (a) injection-poisoned summary steering the operator; (b) mis-triaged
  statutory-clock mail (DSAR Art. 12 / breach Art. 33 / service of process) with an audit
  trail proving the agent saw it; (c) mailbox credential leak — **eliminated** by the
  forwarding design (no credential exists; leak surface is one rotatable Resend webhook
  signing secret); (d) wrong outbound send — **out of scope** (no send authority).
- **Threshold:** single-user incident (founder-grade brand survival).

## Why This Approach

- The operator's real pain is recurring: low-leverage mail triage competing with strategic
  work, and "operator as human message bus" will recur for every Soleur company.
- The cheapest credible substrate reuses everything: webhook→Inngest ingress pattern,
  mig-052 dedup (`Message-ID` slots into `messages.source_ref`), scope-grants,
  `action_sends`, the shipped conversation inbox, and the K6 decisions pre-made on
  2026-06-02 (Resend Inbound front door, code-static handler registry, fail-loud
  no-match, hardened parser). Only the front door + parser are net-new.
- **IMAP/JMAP polling was rejected on corrected premises:** Proton has no JMAP at all,
  and IMAP requires Proton Bridge — a stateful daemon whose credential is send-capable
  and full-mailbox (Proton has no read-only token), needing unofficial Docker images and
  an egress-allowlist widening on the prod host. The issue body's "$0 IMAP slice" was the
  highest-risk option, not the cheapest.
- OAuth into the operator's personal mailbox is **infeasible** (Proton has no OAuth API)
  and was independently rejected by CLO (company would become controller of the
  operator's private correspondence). Paid shared-inbox vendors (Front $25-29/seat/mo,
  Missive $14/user/mo) rejected pre-revenue + new US sub-processor load.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| K1 | **Overturn the #4788 deferral; build the narrow read-only slice as operator dogfood.** | Operator override of validator condition (1); conditions (2)+(3) satisfied by shipped substrate + design. Recorded above. |
| K2 | **Substrate: Proton Sieve forward → Resend Inbound → webhook → Inngest.** No Bridge, no IMAP, no mailbox credential. | Reuses 3rd-ingress pattern; credential blast radius collapses to one rotatable webhook secret. Needs an ADR (3rd ingress, alongside ADR-036). |
| K3 | **Statutory-class fast-path is deterministic and runs BEFORE the LLM.** DSAR / breach / service-of-process / regulator mail escalates fail-loud to the operator with the clock stated (link `knowledge-base/legal/recommended-tools.md#dsar-request`, `#breach-notice-triage`). WORM received-at on every message. LLM never system-of-record for any deadline. | CLO floor carried unchanged from 2026-06-02 K6; learning 2026-05-16 (disclosure is the critical path). |
| K4 | **LLM is read-only with no tools; sanitization parity required.** Email subject/body/sender get `sanitizePromptString` treatment incl. `\x7f` + U+2028/U+2029; no write tools during summarization; no autonomous send. Draft-then-approve replies deferred until #4672, reusing PR #4077 send invariants verbatim. | Largest untrusted-injection surface the project has added (#4671 open); learnings 2026-05-06, 2026-05-19. |
| K5 | **Parse-and-discard retention.** Keep summary, headers, sender, WORM received-at; discard raw body after triage. | Smallest GDPR footprint; keeps third-party PII out of Supabase at rest and out of DSAR/breach blast radius. |
| K6 | **Anthropic Zero-Retention amendment: disclose-and-launch.** Launch with the default 30-day US-side retention, disclosed honestly in the Art. 30 PA row + privacy policy. Signing the ZR amendment stays an open follow-up. | Operator decision; parse-and-discard limits at-rest exposure on our side; PA §(g) names residual risk per #4954 precedent. |
| K7 | **Surface: existing conversation inbox item + Slack ping.** GitHub issues forbidden as a surface (third-party PII, wrong retention). Slack is ping-only, never system-of-record. | Condition (2) compliance; channel taxonomy learning (ops → Slack/ops-email). |
| K8 | **ops@soleur.ai is NEVER a recovery/login address for any vendor account.** Non-negotiable; recorded in spec. | A triaged mailbox must not become a password-reset interception channel. |
| K9 | **Companion increments (separate from the triage build):** (a) Better Stack usage-poll cron (Telemetry API → operator alert); (b) progressive vendor-contact migration to ops@ (excluding recovery/login). | Both $0; (a) prevents the inciting incident class natively per K5-2026-06-02 (webhooks-over-email); (b) consolidates the long tail where the pipeline can see it. |
| K10 | **Legal bundle ships with the build:** new Art. 30 PA row (Anthropic recipient, SCCs, retention), one Art. 6(1)(f) LIA, DPIA screening memo (concluding not-required, PA-22 brief style), Privacy Policy + DPD + GDPR Policy lockstep, Anthropic vendor-DPA scope-cell amendment, `gdpr-gate` mandatory at plan Phase 2.7. | CLO assessment; `hr-gdpr-gate-on-regulated-data-surfaces`. |
| K11 | **Out-of-band liveness for ingestion.** A quiet mailbox is indistinguishable from a broken pipeline; dead-man heartbeat on the Inngest cron substrate + Sentry monitor, with an independent freshness source. | Silent ingestion failure is the dominant risk (CTO); learning 2026-06-01 (#4706 froze 5 weeks). |
| K12 | **Inbox PII stays out of observability sinks.** Summaries/logs to pino/Sentry/Better Stack must not carry raw bodies or sender PII (pseudonymize or strip-and-tag). | Otherwise Better Stack/Sentry sub-processor disclosures change (P0 precedent, learning 2026-05-22). |

**Productize Candidate:** `vendor-quota-watch` — the Better Stack Telemetry poll (K9a)
generalizes to a scheduled vendor-usage/quota watcher across API-capable vendors
(Supabase Management API, Resend, etc.).

## Open Questions

1. **Slack transport for the ping:** server-side Slack does not exist (only the CI
   `SLACK_RELEASES_WEBHOOK_URL`); the `external.low_stakes.slack_dm_standard` action class
   exists with no transport behind it. Plan must pick: extend the CI webhook secret into
   the app, or web-push-first (notification hierarchy WS > push > email already exists).
2. **Resend Inbound setup specifics:** inbound MX/subdomain records (Terraform,
   `dns.tf`, single-resource-diff discipline per prior spec TR1) and Resend Inbound's
   exact webhook payload/signing — verify live at plan time.
3. **SPF/DMARC alignment** if replies are ever sent *as* ops@soleur.ai via Resend
   (Proton SPF include vs Resend's) — deferred with the draft-then-approve increment.
4. **Sender scoping at launch:** triage everything arriving at ops@ vs. start with an
   allowlisted vendor-sender set and widen. Leaning allowlist-first (matches K6
   reporter-allowlist precedent); decide at plan time.
5. **Supersede or amend** `knowledge-base/project/specs/feat-inbound-email-action-bus/spec.md`,
   whose Non-Goals currently prohibit exactly this (its FR1-FR3 buy path already shipped —
   `dns.tf:94` has the Postmark rua — but frontmatter still says `status: draft`).

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Neither duplicate-close nor proceed-as-is — re-scope. #5103 as written
re-smuggled the #4788 platform framing ("per company"); the honest framing is internal
ops tooling judged on operator-time ROI. Actor-narrowing dissolves the customer-demand
premise only; injection and statutory-clock premises stand. Recommended the deterministic
no-LLM slice first; the operator chose to overturn and build the narrow read-only slice
(recorded as override in K1). The inciting Better Stack incident was fixed at source the
same day (410c7dfbf) and its class is covered by K9a.

### Legal (CLO)

**Summary:** Operator-self-use narrowing materially reduces but does not zero the load: a
new Article 30 PA is still required (involuntary data subjects, uncontrolled free-text);
full DPIA drops to a screening memo; one Art. 6(1)(f) LIA suffices; three-document
lockstep applies. Anthropic DPA mechanics exist but scope must be amended; Zero-Retention
amendment is unsigned (operator chose disclose-and-launch, K6). Statutory floor
non-negotiable (K3). Personal-mailbox OAuth rejected; shared-inbox vendor would add a new
US sub-processor + full DPA chain. Runtime escalations must hard-link the legal-threshold
catalog rows.

### Engineering (CTO)

**Summary:** Issue premises corrected — Proton has no JMAP; IMAP requires Bridge (
send-capable full-mailbox credential, unofficial images, egress widening): rejected.
Recommended substrate is the forwarding chain (K2), reusing the 2-ingress precedent,
mig-052 dedup, scope-grants, `action_sends`, and ~40-cron Inngest substrate. Dominant
risk is silent ingestion failure (K11), then injection (mitigated to read-only summarize,
K4). DNS work is low-risk (no MX change; Proton-side Sieve rule + Resend inbound records
only) but lives on the brand-critical Terraform root. Recommends `/soleur:architecture`
ADR for the 3rd ingress. Complexity: medium (days) for the read-only slice.

### Operations (COO)

**Summary:** ~9 of 14 active vendors have native non-email channels — native signals
(K9a) cover the incident class that actually occurred; Better Stack free tier is
email-only by structure (`betterstack_paid_tier=false`). ops@ as an additional Proton
address is $0 (10 addresses/user included). Shared-inbox vendors rejected on cost
(Front $25-29/seat/mo verified live; not $19 as the issue claimed). Ledger hygiene flagged:
Slack absent from expense ledger; stale renewal dates to roll forward (ops-advisor, out of
band). Recurring burden of the forwarding path is low-medium (parser hardening +
per-sender onboarding) vs. high for any Bridge daemon.

## Capability Gaps

- **Untrusted-content triage agent profile (Engineering):** no agent profile exists for
  processing attacker-controlled text with no write tools. Evidence: CTO grep of
  `plugins/soleur/agents/**` found no such profile; #4671 tracks the general defense but
  the profile itself is unbuilt. Needed before any LLM touches email bodies.
- **Server-side Slack transport (Engineering):** zero server-side Slack code. Evidence:
  repo-research grep — `SLACK_RELEASES_WEBHOOK_URL` appears only in
  `.github/workflows/reusable-release.yml`; app-code "slack" hits are action-class string
  literals in `server/scope-grants/action-class-map.ts` with no transport. Needed for the
  K7 ping unless web push is chosen (Open Question 1).
- **Scheduled vendor-quota poller (Operations/Engineering):** no skill or cron polls
  vendor usage APIs. Evidence: COO/repo-research sweep of `cron-*.ts` (40 functions) and
  `scheduled-*.yml` (4 files) — none poll vendor telemetry. K9a / Productize Candidate.

## Session Errors

1. **Issue-body premise drift recorded:** #5103 asserted "IMAP/JMAP polling of a dedicated
   address on existing Proton Workspace ($0 marginal)" as the cheapest slice — wrong on
   JMAP (unsupported by Proton), wrong on IMAP cost (requires Bridge + send-capable
   credential), and shape 2 (OAuth) is infeasible on Proton. Corrected here before
   architecture selection; no greenfield re-derivation occurred.
