---
date: 2026-06-15
type: feat
issue: 5325
deferred_issue: 5331
branch: feat-agent-native-outbound-email
pr: 5326
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-06-15-agent-native-outbound-email-brainstorm.md
spec: knowledge-base/project/specs/feat-agent-native-outbound-email/spec.md
---

# Plan: Agent-Native Outbound Email (Pilot Slice) — #5325

✨ **feat** · cross-domain · brand-survival threshold **single-user incident** (CPO sign-off required before `/work`)

## Enhancement Summary (deepen-plan)

**Deepened on:** 2026-06-15 · **Agents:** data-integrity-guardian, security-sentinel, architecture-strategist (single-user-incident triad) + verify-the-negative grep.
The triad caught 5 brand-survival P0s that style/scope plan-review structurally missed. Key improvements:
1. **Reuse the existing `action_sends` + `scope_grants` + review-gate approval primitive** (migration 051) for body-hash-bound, single-use, recipient-bound approval written *outside* the agent — instead of a forgeable bare `approved_at`. Net-new schema shrinks to just `email_suppression`.
2. **Deterministic keyed recipient hash** (HMAC-SHA-256 + app-wide pepper, canonicalized) — a random/per-row salt would silently break cross-campaign suppression = the exact incident.
3. **Recipient exfiltration + header-injection controls** at the chokepoint (LLM-in-the-loop inverts the threat model vs transactional send).
4. **Domain-verified runtime precondition** — block sends until `mail.jikigai.com` is Resend-verified (else first send burns reputation in the merge→verify window).
5. **Transactional suppression re-check** (close the TOCTOU between check and Resend).

## Deepen-Plan Hardening — required before /work

**P0-1 (reuse action_sends for approval).** The bare `approved_at` is self-writable by the same `email_send` RPC and body-unbound → an approval for draft A authorizes mutated draft B, and replays across recipients. **Fix:** the chokepoint records the send into `action_sends` (precedent `051_…sql`, with `action_sends_no_mutate` WORM trigger + `anonymise_action_sends` Art.17 carve-out) bound to `per_send_body_sha256` + approval signature + a `scope_grants` grant; approval is written by the **review-gate path** (`server/review-gate.ts`/`permission-callback.ts` — the human trust boundary the `gated` tier already routes through), NEVER by the `email_send` RPC. The chokepoint recomputes the body hash from the actual payload at send time and rejects on mismatch (single-use, recipient-bound). Record bare-`approved_at`-vs-`action_sends` as the rejected alternative in ADR-060.

**P0-2 (deterministic recipient hash).** `email_suppression`/audit lookups must match the same address across campaigns. **Fix:** `recipient_hash = HMAC-SHA-256(pepper, normalize(email))` where `normalize` = lowercase + trim (document plus/dot handling); pepper from Doppler (`EMAIL_HASH_PEPPER`), never a per-row/random salt. Pin the algorithm in the migration header + a code constant; add a test asserting `hash(x)` is stable across calls. (Tradeoff: linkable keyed hash, necessary because matching forecloses per-row salts.)

**P0-3 (recipient exfiltration).** A prompt-injected agent could set `to:` to an attacker address + put inbound PII in the body. **Fix:** `email_reply` recipient is derived **server-side** from the persisted inbound `message_id`, never from agent args; `email_send` recipient must equal the human-approved campaign target (bound via the approval hash); reject internal/own-domain (`*@jikigai.com`, `*@soleur.ai`) and bare/role addresses unless allow-listed.

**P0-4 (header injection).** Do NOT repurpose the display/prompt `sanitizeDisplayString` as an email-header guard. **Fix:** a dedicated header validator in `outbound-compliance.ts` — RFC-5322-validate each `to`/`reply-to`/`from`; reject any address/display-name field containing `\r \n \x00-\x1f \x7f    `; cap recipient count. Add a test asserting ` `/CRLF in `to`/`subject` throws.

**P1 (domain-verified precondition).** Code merges (`Closes #5325`) while DNS apply + Resend `verified` are post-merge → a send in that window fails SPF/DKIM and burns reputation. **Fix:** `sendCompliantOutbound()` gates on a runtime domain-verified check (Resend domain status or a flag set only post-verification) that throws until live — a hard precondition alongside C1–C5, not an operator memo.

**P1 (suppression TOCTOU).** **Fix:** re-check suppression *inside the send RPC transaction* (serializable / `FOR UPDATE`) immediately before recording the send, not an app-layer SELECT before Resend. Canonicalize before hashing at both write and check. Order: validate → in-txn suppression recheck → Resend → append send row (Resend is the un-rollback-able side effect).

**P1 (sentinel scope + third invariant).** Scope the sentinel to `apps/web-platform/server/**` excluding `**/*.test.ts` (the brand-compliance test legitimately calls `emails.send`). Add a **typed `FromDomain` discriminant** so the transactional callers (`notifications.ts`, `cron-email-ingress-probe.ts`) structurally cannot set the cold `mail.jikigai.com` value — invariant (a) literal-in-one-file + (b) caller allowlist + (c) no non-`outbound.ts` file references `mail.jikigai.com` in any form.

**P1 (CF token scope).** `CF_API_TOKEN_JIKIGAI` = **DNS:Edit on jikigai.com zone ONLY** (not Zone:Edit, not account-wide), minted into `prd_terraform` only. AC: the token-reach gate returns 403 on any zone other than jikigai.com. `RESEND_API_KEY` is shared — a leak now also burns the outreach domain; note in Risks.

**P2:** `email_suppression` is upsert with `UNIQUE(owner_id, recipient_hash)` + `INSERT … ON CONFLICT DO NOTHING` (monotonic set, never un-suppressed; NO un-suppress RPC — explicit AC) · RPCs `authenticated` + `auth.uid()` owner-pinned (mirror `set_email_triage_status`) · DMARC `rua` mailbox must ingest before `p=quarantine` · test asserts pino logs AND `captureException` values are PII-free (raw Resend error can echo recipient) · confirm `email_reply` needs only founder-supplied thread context (no #5331 thread-matcher dependency).

## Overview

Add a **human-approval-gated** agent send/reply capability so outreach (the #5314 listicle
campaign) becomes agent-drafted + agent-sent on the founder's behalf, with CLO conditions
C1–C5 enforced **in code** at a single send chokepoint. Cold mail sends from a dedicated
**`mail.jikigai.com`** subdomain (onboarded to Terraform). The generic subsystem (automated
campaign state machine, jurisdiction auto-tagging, approval-queue UI, auto-send) is deferred
to **#5331**.

The send *primitive* already exists (`notifications.ts` → Resend); this plan builds the
**agent-callable cold-outbound path + compliance chokepoint + campaign/suppression persistence
+ jikigai.com domain auth + the legal basis** to use it.

## Research Reconciliation — Spec vs. Codebase

| Spec / issue claim | Codebase reality | Plan response |
|---|---|---|
| "Neither a human nor an agent can send email today" | `resend.emails.send()` exists at `notifications.ts:323/364/537/575` + `cron-email-ingress-probe.ts:224`, with `sanitizeDisplayString`+`escapeHtml` header-injection hygiene. | Build = expose + gate + persist, NOT send-from-scratch. Reuse `getResend()`; the chokepoint imports it. |
| "Add SPF/DKIM/DMARC for jikigai.com" (checklist item) | `infra/dns.tf` is single-zone (`var.cf_zone_id`=soleur.ai); jikigai.com in zero Terraform (`variables.tf:152` recipient string only). No DMARC anywhere. | Blocking prereq, sequenced first (Phase 0). Multi-zone extension + token-reach gate. See `## Infrastructure (IaC)`. |
| "Agent tool `email_send`/`email_reply` added to `buildEmailTriageTools`" | `tool-tiers.ts:82-83` already states: *"there is NO email_triage write tool — if one ever ships it must be `gated`, never auto-approve."* | Tools = tier **`gated`** (fail-closed map requires explicit entry). Update the FR9-boundary comment to point at the now-shipped write tools. |
| "Reuse inbound triage to detect replies/declines" | `email_triage_items` is a WORM table (`102_…sql`), RLS SELECT-owner, RPC-only writes. Inbound classifier in `summarize.ts`/`events.ts`. | **[plan-review]** Automated reply-matcher DEFERRED to #5331. Pilot: a minimal agent-invoked `email_suppress` adds a recipient on a founder-observed decline. New tables (104) mirror the WORM-adjacent RLS/RPC posture; do NOT reuse the WORM table. |
| "Tool tier `ask-approval`" (spec FR1 / brainstorm D3) | `tool-tiers.ts:13` union is `"auto-approve" \| "gated" \| "blocked"` — `"ask-approval"` is not a valid value. | **[plan-review]** Plan uses `"gated"`; this supersedes the spec/brainstorm "ask-approval" wording. Implementer must NOT introduce an invalid literal. |
| "Outbound authority" | LIA `2026-06-11-operator-inbox-triage-lia.md` explicitly defers it ("no send authority added to pipeline"). | New/amended LIA is a Phase 5 deliverable (overturns the recorded deferral). |

Premise validation: #5325 OPEN; brainstorm/spec exist; jikigai.com-not-in-TF verified live; CLO C1–C5 audit + 2026-06-11 LIA confirmed present. ADR corpus grep: ADR-055 is the inbound counterpart; **no ADR rejects an outbound chokepoint or a second sending domain** → author ADR-060.

## User-Brand Impact

**If this lands broken, the user experiences:** an agent sends a malformed, mis-personalized, or
duplicate cold email from the founder's brand to a high-visibility recipient (a journalist/author),
or fails to send and the campaign silently stalls.

**If this leaks, the user's workflow/reputation is exposed via:** a non-compliant cold send
(missing postal address / opt-out / EU-UK disclosure), a send to a suppressed/opted-out contact,
or inbound PII echoed into an outbound message — a CAN-SPAM/GDPR incident plus an irreversible
sender-reputation and brand hit.

**Brand-survival threshold:** single-user incident.

CPO sign-off required at plan time before `/work` (carried forward: CPO reviewed the brainstorm and
recommended the pilot slice). `user-impact-reviewer` runs at review time.

## Implementation Phases

Phases are ordered by **dependency direction** (contract before consumer): infra → data model →
chokepoint → tools → wiring → legal. Tests-first per `cq-write-failing-tests-before`.

### Phase 0 — Blocking prereq: onboard jikigai.com sending domain (infra)
0.1 **Token-reach gate FIRST** (before any TF plan): curl the jikigai.com zone (see IaC section). If it fails, mint a narrow `CF_API_TOKEN_JIKIGAI` + aliased provider.
0.2 Add `resend-sending-bootstrap.sh` (generalize `resend-inbound-bootstrap.sh`, sending-only, `mail.jikigai.com`, eu-west-1) to mint DKIM/SPF values from Resend (no dashboard step).
0.3 Add `var.cf_jikigai_zone_id` + 4 `cloudflare_record` resources (DKIM, SPF, MX-bounce, DMARC `p=quarantine`+`rua`).
0.4 Confirm Resend domain-count tier impact; disclose if it forces the paid tier (ledger entry).

### Phase 1 — Data model (migration 104) [reworked per deepen-plan]
1.1 (RED) Tests for: RLS owner-SELECT; REVOKE INSERT/UPDATE from `authenticated`; `auth.uid()` owner-pin on RPCs; `email_suppression` upsert idempotency on `(owner_id, recipient_hash)`; `recipient_hash` stability (`hash(x)` deterministic across calls); no un-suppress path.
1.2 **Reuse `action_sends` (migration 051) for the send-audit + approval binding.** [work-verified] `action_sends` already carries `per_send_body_sha256`, `recipient_id_hash`, `template_hash`, `approval_signature_sha256`, `grant_id`→`scope_grants`, the `action_sends_no_mutate` WORM trigger, owner-select/insert RLS, the `action_sends_message_unique` idempotency index, and `anonymise_action_sends` (Art.17). Its `action_class` is **open text with only an enum-*absence* CHECK** (`!~ '^(payment|legal|auth)\.'`), so `marketing.outreach` is admissible with **NO enum/migration change**. An outbound send records an `action_sends` row. **Do NOT add an `outbound_sends` table; do NOT widen any enum.** Net-new in `104_outbound_email.sql`: only `email_suppression` (owner_id FK `ON DELETE RESTRICT`, `recipient_hash`, `reason`, `added_at`; `UNIQUE(owner_id, recipient_hash)`; **upsert** RPC `suppress_recipient` `INSERT … ON CONFLICT DO NOTHING`; `is_recipient_suppressed` check RPC; `anonymise_email_suppression` Art.17 RPC; monotonic — no un-suppress RPC). ENABLE RLS SELECT-owner-only, REVOKE writes, SECURITY DEFINER RPCs `authenticated`+`auth.uid()`-pinned with `SET search_path = public, pg_temp` (`cq-pg-security-definer-search-path-pin-pg-temp`). `recipient_hash` = HMAC-SHA-256(`EMAIL_HASH_PEPPER` from Doppler, `normalize(email)`); pin algorithm in header comment. `.down.sql` sibling. Latest migration on origin/main is 103 (collision-checked) → 104 is free.

### Phase 2 — Compliance chokepoint (the load-bearing component)
2.1 (RED) `outbound-compliance.test.ts`: each of C1–C4 absent → refuse-to-send throws; suppressed recipient → throws; jurisdiction unknown → defaults EU/UK-strict. **C3 EU/UK disclosure = presence of EACH of the 6 Art. 14 elements as 6 discrete predicates** (identity, purpose, legal-basis=legitimate-interest, source/category, retention, rights) — mechanical per-element presence, NOT fuzzy semantic NLP. The human approver owns semantic correctness (every cold send is human-approved).
2.2 `outbound-compliance.ts`: pure C1–C5 validators (testable, no IO); C3 = 6 independent element predicates.
2.3 `outbound.ts`: `sendCompliantOutbound()` — the ONLY module importing `getResend()` for cold outbound AND the ONLY holder of the `mail.jikigai.com` FROM literal. Order: validate C1–C5 + header-field RFC-5322 validator + recipient allow-list + **domain-verified precondition** + **content-hash approval match** (recompute `per_send_body_sha256`, match the `action_sends`/scope-grant approval written by the review-gate, not the agent) + **in-txn suppression recheck** → throw on any failure before Resend → Resend → record `action_sends` row → Sentry-mirror failures. `email_reply` recipient is derived server-side from the persisted inbound `message_id`.
2.4 (RED) sentinel test (in `outbound-chokepoint.test.ts`), scoped to `apps/web-platform/server/**` excluding `**/*.test.ts`, asserts **three** invariants: (a) `mail.jikigai.com` FROM literal in exactly one file (`outbound.ts`); (b) `resend.emails.send` callers limited to allowlist `{notifications.ts, server/inngest/functions/cron-email-ingress-probe.ts, outbound.ts}`; (c) no file other than `outbound.ts` references `mail.jikigai.com` in any form, enforced by a typed `FromDomain` discriminant the transactional callers cannot set to the cold value (`hr-write-boundary-sentinel-sweep-all-write-sites`).

### Phase 3 — Agent tools + tiers
3.1 (RED) tool tests (in `outbound-chokepoint.test.ts`): `email_send`/`email_reply`/`email_suppress` route through the chokepoint; refuse when not approved; persisted `approved_at` re-verified at the chokepoint (UI tier advisory, chokepoint authoritative).
3.2 Extend `buildEmailTriageTools` with `email_send`/`email_reply` + a minimal `email_suppress` (add-to-suppression on a founder-observed decline). Untrusted-content envelope carried over.
3.3 `tool-tiers.ts`: add all three = `"gated"`; update the FR9-boundary comment (`:82-83`).
3.4 `agent-runner.ts`: register `mcp__soleur_platform__email_send`/`email_reply`/`email_suppress` (real anchors `:1315` prose + `:1533` tool-name array — grep exact lines at /work, do NOT assume `:54/:393`); update tool-description prose.

### Phase 4 — (deferred) Automated reply/decline detection → #5331
The thread/message-id classifier matcher that auto-flips state + auto-suppresses is the auto-send-adjacent
subsystem; deferred to #5331. Pilot suppression is the manual/agent `email_suppress` from Phase 3. Touch-2
is a **manual founder re-trigger** (no auto-send).

### Phase 5 — Legal artifacts (docs)
5.1 New/amended LIA `2026-06-15-outbound-email-authority-lia.md` (overturns the 2026-06-11 deferral; inherit its "if/when built" decisions verbatim; comment a partial override on the source so it stays OPEN for the un-overridden remainder).
5.2 Article 30 register entry (grep `^## Processing Activity` + `PA-` to pick the next free PA id — do NOT assume a number; collisions documented).
5.3 ADR-060 `outbound-email-sending-domain-and-compliance-chokepoint.md`.

## Files to Create

- `apps/web-platform/server/email-triage/outbound.ts` — `sendCompliantOutbound()` chokepoint (records into `action_sends`)
- `apps/web-platform/server/email-triage/outbound-compliance.ts` — pure C1–C5 validators (6 Art.14 predicates) + RFC-5322 header-field validator + recipient allow-list
- `apps/web-platform/supabase/migrations/104_outbound_email.sql` (+ `.down.sql`) — `email_suppression` table + outbound `action_class` extension on `action_sends` (NO new `outbound_sends` table)
- `apps/web-platform/infra/resend-sending-bootstrap.sh`
- `apps/web-platform/test/server/outbound-compliance.test.ts` — C1–C5 validators (incl. 6 Art.14 predicates)
- `apps/web-platform/test/server/outbound-chokepoint.test.ts` — send-path + tools-route-through + 2-invariant sentinel + RLS (3 test files total, collapsed from 5 per plan-review)
- `knowledge-base/legal/legitimate-interest-assessments/2026-06-15-outbound-email-authority-lia.md`
- `knowledge-base/engineering/architecture/decisions/ADR-060-outbound-email-sending-domain-and-compliance-chokepoint.md` — **one paragraph** (decision + rejected alternative; resist full template)

## Files to Edit

- `apps/web-platform/server/email-triage-tools.ts` — add `email_send`/`email_reply`/`email_suppress` (route through chokepoint)
- `apps/web-platform/server/tool-tiers.ts` — add all three = `"gated"`; update FR9-boundary comment (`:82-83`)
- `apps/web-platform/server/agent-runner.ts` — register tools (real anchors `:1315` prose + `:1533` array; grep exact lines at /work — `:54/:393` were unverified paraphrase) + tool-description prose
- `apps/web-platform/server/review-gate.ts` + `apps/web-platform/server/permission-callback.ts` — wire `gated`-tier approval write for the new tools (human trust boundary; approval NOT written by the agent RPC)
- `apps/web-platform/supabase/migrations/051_action_class_widening_and_action_sends.sql` — reference for the `action_class`/`scope_grants`/`action_sends_no_mutate`/`anonymise_action_sends` pattern reused by 104 (extend `action_class` enum)
- `apps/web-platform/infra/dns.tf` — 4 `cloudflare_record` resources on `var.cf_jikigai_zone_id`
- `apps/web-platform/infra/variables.tf` — `cf_jikigai_zone_id`
- `knowledge-base/legal/article-30-register.md` — outbound processing entry (next free PA id)
- `knowledge-base/project/specs/feat-agent-native-outbound-email/spec.md` — link FRs to chokepoint files

## Infrastructure (IaC)

### Terraform changes
**Extend the single-zone `dns.tf` to multi-zone — do NOT stand up a new root.** A new root needs its
own R2 backend, Doppler wiring, provider set, CI concurrency group — pure overhead for ~4 DNS records.
Zone isolation in Cloudflare is per-zone-ID, not per-root, so `dev != prd` distinctness is satisfied by
the zone-ID variable. Add `var.cf_jikigai_zone_id` (`variables.tf`); add to `dns.tf` (all
`zone_id = var.cf_jikigai_zone_id`, values minted by Resend):
- `jikigai_dkim` — `resend._domainkey.mail` TXT (DKIM from Resend)
- `jikigai_spf` — `send.mail` TXT = `v=spf1 include:amazonses.com ~all`
- `jikigai_mx_bounce` — `send.mail` MX → `feedback-smtp.eu-west-1.amazonses.com` priority 10
- `jikigai_dmarc` — `_dmarc.mail` TXT = `v=DMARC1; p=quarantine; rua=mailto:dmarc-reports@jikigai.com; pct=100` (→ `p=reject` post-alignment). Apex DMARC stays out of scope.

No `versions.tf`/backend additions — inherited from the existing root.

### Apply path
DNS-only (no SSH/provisioner). Resend domain verification mints DKIM/SPF values, sequenced via a new
`resend-sending-bootstrap.sh` (generalize `resend-inbound-bootstrap.sh`; `DOMAIN_NAME="mail.jikigai.com"`,
eu-west-1, sending-only — no receiving/webhook steps): `doppler run -p soleur -c prd -- bash apps/web-platform/infra/resend-sending-bootstrap.sh`
prints the record set → author the four resources from those rows → standard nested-Doppler `plan`/`apply`.
After Resend reports `verified`, flip DMARC `p=quarantine` → `p=reject` in a follow-up.

### Distinctness / drift safeguards
All four records carry `zone_id = var.cf_jikigai_zone_id` (physically isolated from soleur.ai). Mint
`cf_jikigai_zone_id` into Doppler `prd_terraform` only (no `dev` mint; `hr-tf-variable-no-operator-mint-default`).
Records are additive on `mail.jikigai.com` — zero diff on existing `ops@jikigai.com` inbound. Comment the
block: subdomain-only, apex/ops mail untouched, eu-west-1 to match SES region.

### Vendor-tier reality check
**Token-reach is the load-bearing pre-apply gate** (run BEFORE plan — create-only plan won't surface a
scope error until apply):
```
curl -s -H "Authorization: Bearer $CF_API_TOKEN" \
  "https://api.cloudflare.com/client/v4/zones/$CF_JIKIGAI_ZONE_ID/dns_records?per_page=1" | jq .success
```
If `false`/empty → mint a narrow `CF_API_TOKEN_JIKIGAI` (DNS:Edit on jikigai.com) + `provider "cloudflare" { alias = "jikigai" }` (precedent: `cf_api_token_rulesets`). **Resend free tier caps sending domains** — adding `mail.jikigai.com` likely forces the $20/mo Pro tier; disclose before bootstrap (`hr-autonomous-loop-skill-api-budget-disclosure`). *Verify current pricing at resend.com/pricing.*

## Observability

```yaml
liveness_signal:
  what: outbound send success + DMARC rua aggregate-report ingestion
  cadence: per-send (success/failure event) + daily DMARC rua
  alert_target: Sentry (issue alert on op:outbound.send_error / op:outbound.gate_reject)
  configured_in: outbound.ts (emit) + apps/web-platform/infra/sentry/*.tf (alert rule)
error_reporting:
  destination: Sentry via reportSilentFallback (cq-silent-fallback-must-mirror-to-sentry)
  fail_loud: true   # refuse-to-send THROWS; never silent
failure_modes:
  - {mode: C1-C4/suppression gate reject, detection: Sentry op=outbound.gate_reject, alert_route: Sentry issue alert}
  - {mode: Resend send error, detection: Sentry op=outbound.send_error, alert_route: Sentry issue alert}
  - {mode: send to suppressed recipient, detection: chokepoint throws + structured log, alert_route: Sentry}
  - {mode: deliverability/spam (DMARC fail), detection: DMARC rua reports to dmarc-reports@jikigai.com, alert_route: weekly review}
logs:
  where: pino structured logs — campaignId/emailId only, never recipient PII or body (TR3 parity)
  retention: platform default
discoverability_test:
  command: "curl -s -H 'Authorization: Bearer $SENTRY_TOKEN' 'https://sentry.io/api/0/projects/<org>/<proj>/events/?query=op:outbound.send_error' | jq '.[0].eventID'"
  expected_output: "event id present after a forced gate-reject in staging (NO ssh)"
```

## Domain Review

**Domains relevant:** Product, Legal, Engineering, Marketing, Operations (carried forward from brainstorm `## Domain Assessments`).

### Legal (CLO)
C1–C4 are refuse-to-send preconditions; C5 suppression-check is a precondition (honoring is operational).
GDPR Art. 14 triggered (third-party-collected emails) → C3 EU/UK disclosure content-validated. No auto-send
for cold mail; default-to-EU/UK-strict. External counsel reviews EU/UK posture before first EU/UK send.

### Engineering (CTO)
Single chokepoint (`outbound.ts`) — gate in the tool layer alone is bypassable. New tables mirror
`email_triage_items` posture; reuse inbound classifier for reply matching. Author ADR-060.

### Marketing (CMO)
Earned-media lever, build lean. Dedicated send subdomain non-negotiable; biggest risk = mis-personalized
autonomous send to a journalist. Human approval for all cold sends, permanently.

### Operations (COO)
jikigai.com onboarding to Terraform is the prerequisite; dedicated `mail.jikigai.com`, DMARC quarantine→reject;
Resend domain-count tier impact to verify.

### Product/UX Gate
**Tier:** none. **Decision:** N/A — no UI surface. Approval rides the existing agent chat; outreach bodies are
plain-text 1:1. Mechanical UI-surface scan of Files to Create/Edit: no `components/**/*.tsx`, `app/**/page.tsx`,
or `app/**/layout.tsx` match. **Pencil available:** N/A (no UI surface). A dedicated approval-queue UI is deferred to #5331.

## GDPR / Compliance

Regulated-data surfaces touched (migration 104; processing of third-party contact PII) → compliance is
load-bearing at single-user-incident threshold. The brainstorm CLO assessment already produced the
Art. 14 / C1–C5 analysis; this plan encodes it. `/soleur:gdpr-gate` MUST run at **deepen-plan Phase 4.6**
(or `/work` Phase 0) against the FR/TR sections — recorded here, not skipped.

- **C1** postal-address footer · **C2** opt-out line · **C3** US-vs-EU/UK tag + EU/UK data-source/Art.14
  disclosure (content-validated) · **C4** FTC material-connection on free-access pitch · **C5** suppress
  opt-outs ≤10 business days, permanent (send-time corollary = refuse-to-send if suppressed).
- **GDPR Art. 14** (data not from subject) — first EU/UK communication discloses identity, purpose, legal
  basis (legitimate interest), data source/category, retention, rights. Content requirement, deeper than presence.
- **Art. 30 register** — outbound processing entry (Resend already a documented sub-processor; verify DPA + region).
- **LIA** — new/amended outbound-authority LIA overturns the 2026-06-11 deferral.
- **Default EU/UK-strict** when jurisdiction unknown/low-confidence; never fall through to lenient US path.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] Sentinel test green on BOTH invariants: (a) `mail.jikigai.com` FROM literal in exactly one file (`outbound.ts`); (b) `resend.emails.send` callers limited to allowlist `{notifications.ts, server/inngest/functions/cron-email-ingress-probe.ts, outbound.ts}`.
- [ ] Chokepoint throws on each of C1–C4 absent + suppressed recipient + unknown→EU/UK-strict (tests green).
- [ ] C3 = each of the 6 Art. 14 elements present as 6 discrete predicates (6 RED tests); semantic correctness is the human approver's responsibility (documented, not coded).
- [ ] `email_send`/`email_reply`/`email_suppress` = `"gated"` in `TOOL_TIER_MAP`; FR9-boundary comment updated; tools route through chokepoint.
- [ ] **Approval is body-hash-bound + single-use** via `action_sends`/`scope_grants` written by the review-gate path (NOT the agent RPC); chokepoint recomputes `per_send_body_sha256` and rejects on mismatch or a mutated field (test: approval for draft A rejects mutated draft B; replay across recipients rejected).
- [ ] **Recipient controls:** `email_reply` recipient derived server-side from inbound `message_id`; `email_send` recipient bound to the approved target; internal/own-domain + bare/role addresses rejected (test).
- [ ] **Header validator:** CR/LF/`\x00-\x1f`/U+2028/U+2029 in `to`/`reply-to`/`subject` throws (test); recipient count capped.
- [ ] **Domain-verified precondition:** `sendCompliantOutbound()` throws until `mail.jikigai.com` is Resend-verified (test).
- [ ] Migration 104: reuses `action_sends` (no new `outbound_sends` table) + `email_suppression` with `UNIQUE(owner_id, recipient_hash)` + upsert `ON CONFLICT DO NOTHING`; RLS SELECT-owner-only, INSERT/UPDATE revoked from `authenticated`, RPCs `auth.uid()`-pinned + `search_path` pinned; `recipient_hash` deterministic (HMAC + pepper, stability test green).
- [ ] **Suppression TOCTOU:** suppression re-checked inside the send RPC transaction immediately before recording the send (not app-layer before Resend); canonicalize before hashing.
- [ ] `email_suppress` adds a recipient (upsert, no un-suppress RPC); chokepoint refuses sends to suppressed; NO auto-send path for cold mail (decline-matcher deferred to #5331).
- [ ] Logs + `captureException` values are PII-free (no recipient address even in a raw Resend error) — test.
- [ ] New/amended LIA + Art. 30 entry + ADR-060 committed.
- [ ] Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`. Tests: per `package.json scripts.test` (vitest — `./node_modules/.bin/vitest run <path>`).
- [ ] `/soleur:gdpr-gate` run recorded (deepen-plan/work); Critical findings folded or tracked.
- [ ] PR body uses `Closes #5325` (code lands at merge); jikigai.com DNS apply is a tracked post-merge step (use `Ref` for that sub-task, not auto-close).

### Post-merge (operator/automated)
- [ ] Run `resend-sending-bootstrap.sh` → author DNS record values → `terraform apply` (token-reach gate first). Automatable via bootstrap + nested-Doppler TF; not a dashboard step.
- [ ] `CF_API_TOKEN_JIKIGAI` scoped to **DNS:Edit on jikigai.com ONLY** (minted into `prd_terraform` only); verify the token returns 403 on any other zone.
- [ ] After Resend reports `mail.jikigai.com` verified, flip DMARC `p=quarantine` → `p=reject`.
- [ ] Verify first staging send through the chokepoint emits a Sentry liveness event (discoverability_test).

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` returns no issue touching the new `email-triage/outbound*`, `infra/dns.tf`, or `tool-tiers.ts` lines this plan edits. (Re-run at Step 2 if the file list grows.)

## Risks & Mitigations

- **Gate correctness unproven** → the chokepoint is the load-bearing component; user-impact-reviewer + CLO sign-off before first live send; tests cover every C1–C5 refuse path.
- **Sender-reputation burn** → dedicated subdomain, DMARC quarantine→reject, plain-text 1:1, human approval per send, volume well within Resend tier.
- **jikigai.com token unreachable** → pre-apply token-reach gate + narrow aliased token fallback (no apply-time surprise).
- **Approval forge/replay** → body-hash-bound single-use approval via `action_sends` written by the review-gate (outside the agent); chokepoint recomputes the hash and rejects mutation/replay (deepen P0-1).
- **Suppression TOCTOU** → re-check inside the send RPC transaction immediately before recording; canonicalize before hashing (deepen P1).
- **Cold send before DNS verified** → runtime domain-verified precondition throws until Resend reports `mail.jikigai.com` verified (deepen P1).
- **Shared `RESEND_API_KEY`** → the cold-send domain shares the existing key, so a key leak now also burns the outreach domain's reputation; rotation runbook must note both surfaces.
- **Transactional vs cold send conflation** → 3-invariant sentinel + typed `FromDomain` discriminant make cold sends structurally impossible from `notifications.ts`/`cron-email-ingress-probe.ts`.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty/`TBD`/threshold-less fails `deepen-plan` Phase 4.6 — this plan's section is filled.
- `tool-tiers.ts` is fail-closed: omitting an explicit tier for a new tool blocks it. Both new tools MUST be added as `"gated"`.
- Art. 30 PA numbers collide across sibling PRs — grep the register for the next free `PA-` id at /work, do not assume.
- The sentinel must isolate the *cold-outbound FROM literal*, NOT all `resend.emails.send` calls — `notifications.ts`/`cron-email-ingress-probe.ts` legitimately send transactional mail from soleur.ai.

## Test Scenarios

1. Each of C1–C4 missing → `sendCompliantOutbound()` throws; no Resend call.
2. Recipient on suppression list → throws.
3. Unknown jurisdiction → EU/UK-strict path selected; each of the 6 Art. 14 element predicates required.
4. `email_send` without persisted approval → refused at chokepoint.
5. `email_suppress` adds a recipient → subsequent `email_send` to that recipient throws; Touch-2 cannot fire.
6. Sentinel invariant (a): `mail.jikigai.com` FROM literal in exactly one file.
7. Sentinel invariant (b): `resend.emails.send` callers == the allowlist (a new caller fails the test).
8. RLS: a non-owner cannot SELECT another owner's `outbound_sends`/`email_suppression` rows; `authenticated` cannot INSERT/UPDATE directly.
