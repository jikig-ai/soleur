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

### Phase 1 — Data model (migration 104) [simplified per plan-review]
1.1 (RED) Tests for RLS owner-SELECT, REVOKE INSERT/UPDATE from `authenticated`, RPC append-only writes.
1.2 `104_outbound_email.sql`: a **flat append-only `outbound_sends` log** (recipient hash, approved_at, sent_at, decline flag — NO multi-state machine; the state machine is deferred to #5331) + `email_suppression` (recipient hash, reason, added_at — append-only; CLO C5 requires a persisted list honored *across campaigns*, so it stays its own durable table). ENABLE RLS, SELECT-owner-only, REVOKE writes, SECURITY DEFINER RPCs with `SET search_path = public, pg_temp` (`cq-pg-security-definer-search-path-pin-pg-temp`). `.down.sql` sibling.

### Phase 2 — Compliance chokepoint (the load-bearing component)
2.1 (RED) `outbound-compliance.test.ts`: each of C1–C4 absent → refuse-to-send throws; suppressed recipient → throws; jurisdiction unknown → defaults EU/UK-strict. **C3 EU/UK disclosure = presence of EACH of the 6 Art. 14 elements as 6 discrete predicates** (identity, purpose, legal-basis=legitimate-interest, source/category, retention, rights) — mechanical per-element presence, NOT fuzzy semantic NLP. The human approver owns semantic correctness (every cold send is human-approved).
2.2 `outbound-compliance.ts`: pure C1–C5 validators (testable, no IO); C3 = 6 independent element predicates.
2.3 `outbound.ts`: `sendCompliantOutbound()` — the ONLY module importing `getResend()` for cold outbound AND the ONLY holder of the `mail.jikigai.com` FROM literal. Validates → throws before Resend → sends → appends to `outbound_sends` + Sentry-mirrors failures.
2.4 (RED) sentinel test (in `outbound-chokepoint.test.ts`) asserts **two** invariants (Kieran P0): (a) the `mail.jikigai.com` FROM literal appears in exactly one file (`outbound.ts`); (b) `resend.emails.send` callers are limited to an explicit allowlist `{notifications.ts, server/inngest/functions/cron-email-ingress-probe.ts, outbound.ts}` — a FROM-string grep alone cannot distinguish cold from transactional sends (`hr-write-boundary-sentinel-sweep-all-write-sites`).

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

- `apps/web-platform/server/email-triage/outbound.ts` — `sendCompliantOutbound()` chokepoint
- `apps/web-platform/server/email-triage/outbound-compliance.ts` — pure C1–C5 validators
- `apps/web-platform/supabase/migrations/104_outbound_email.sql` (+ `.down.sql`)
- `apps/web-platform/infra/resend-sending-bootstrap.sh`
- `apps/web-platform/test/server/outbound-compliance.test.ts` — C1–C5 validators (incl. 6 Art.14 predicates)
- `apps/web-platform/test/server/outbound-chokepoint.test.ts` — send-path + tools-route-through + 2-invariant sentinel + RLS (3 test files total, collapsed from 5 per plan-review)
- `knowledge-base/legal/legitimate-interest-assessments/2026-06-15-outbound-email-authority-lia.md`
- `knowledge-base/engineering/architecture/decisions/ADR-060-outbound-email-sending-domain-and-compliance-chokepoint.md` — **one paragraph** (decision + rejected alternative; resist full template)

## Files to Edit

- `apps/web-platform/server/email-triage-tools.ts` — add `email_send`/`email_reply`/`email_suppress` (route through chokepoint)
- `apps/web-platform/server/tool-tiers.ts` — add all three = `"gated"`; update FR9-boundary comment (`:82-83`)
- `apps/web-platform/server/agent-runner.ts` — register tools (real anchors `:1315` prose + `:1533` array; grep exact lines at /work — `:54/:393` were unverified paraphrase) + tool-description prose
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
- [ ] `email_send`/`email_reply`/`email_suppress` = `"gated"` in `TOOL_TIER_MAP`; FR9-boundary comment updated; tools route through chokepoint; chokepoint re-verifies persisted `approved_at`.
- [ ] Migration 104: flat append-only `outbound_sends` log + `email_suppression` table (NO multi-state machine); RLS SELECT-owner-only, INSERT/UPDATE revoked from `authenticated`, SECURITY DEFINER RPCs with `search_path` pinned (RLS test green).
- [ ] `email_suppress` adds a recipient; chokepoint refuses sends to suppressed; NO auto-send path exists for cold mail (automated decline-matcher deferred to #5331).
- [ ] New/amended LIA + Art. 30 entry + ADR-060 committed.
- [ ] Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`. Tests: per `package.json scripts.test` (vitest — `./node_modules/.bin/vitest run <path>`).
- [ ] `/soleur:gdpr-gate` run recorded (deepen-plan/work); Critical findings folded or tracked.
- [ ] PR body uses `Closes #5325` (code lands at merge); jikigai.com DNS apply is a tracked post-merge step (use `Ref` for that sub-task, not auto-close).

### Post-merge (operator/automated)
- [ ] Run `resend-sending-bootstrap.sh` → author DNS record values → `terraform apply` (token-reach gate first). Automatable via bootstrap + nested-Doppler TF; not a dashboard step.
- [ ] After Resend reports `mail.jikigai.com` verified, flip DMARC `p=quarantine` → `p=reject`.
- [ ] Verify first staging send through the chokepoint emits a Sentry liveness event (discoverability_test).

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` returns no issue touching the new `email-triage/outbound*`, `infra/dns.tf`, or `tool-tiers.ts` lines this plan edits. (Re-run at Step 2 if the file list grows.)

## Risks & Mitigations

- **Gate correctness unproven** → the chokepoint is the load-bearing component; user-impact-reviewer + CLO sign-off before first live send; tests cover every C1–C5 refuse path.
- **Sender-reputation burn** → dedicated subdomain, DMARC quarantine→reject, plain-text 1:1, human approval per send, volume well within Resend tier.
- **jikigai.com token unreachable** → pre-apply token-reach gate + narrow aliased token fallback (no apply-time surprise).
- **`approved_at` race / Touch-2 after decline** → no auto-send in pilot (Touch-2 manual); chokepoint re-checks suppression at send time.
- **Transactional vs cold send conflation** → sentinel isolates the `mail.jikigai.com` FROM literal to `outbound.ts`; `notifications.ts` transactional sends (soleur.ai) are a distinct, allowed class.

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
