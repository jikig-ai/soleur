---
title: "legal: update AUP, Cookie Policy, and privacy docs for Web Platform"
type: feat
date: 2026-03-29
---

# legal: update AUP, Cookie Policy, and privacy docs for Web Platform

## Enhancement Summary

**Deepened on:** 2026-03-29
**Sections enhanced:** 5 (Technical Considerations, Acceptance Criteria, Test Scenarios, Dependencies, References)
**Research sources:** 6 institutional learnings, Supabase SSR source code, middleware analysis

### Key Improvements

1. Added pre-implementation grep inventory strategy (from learning: product-addition-prevention-strategies)
2. Added post-edit compliance auditor cycle (from learning: cross-document-audit-review-cycle)
3. Corrected Supabase cookie duration from "Session / persistent (configurable)" to "Persistent (400 days, SameSite=Lax)"
4. Added blanket-statement grep verification as a validation step
5. Added cross-reference integrity checks for conversation data across secondary sections (rights, retention, breach scenarios)

### New Considerations Discovered

- Privacy Policy Section 8 (Rights) already mentions Web Platform but may need conversation-specific data subject right language (right to export conversation history)
- GDPR Policy Section 11 (Breach Notification) scenarios should include conversation data compromise
- The `tool_calls` JSONB column in messages table may contain structured data that qualifies as a sub-category -- document as "tool call metadata" rather than expanding the PII definition

## Overview

Three legal documents need updating before beta invites (Phase 2 items 2.7-2.9). The CLO review identified:

1. **AUP** is still scoped to "Plugin" and "Local Execution Model" -- does not cover the Web Platform
2. **Cookie Policy** does not document app.soleur.ai session cookies (Supabase auth, CSRF, Stripe)
3. **Privacy docs** (3 files) do not list conversation history as a PII data category

Source: CLO review, tracked as #1048, milestone "Phase 2: Secure for Beta".

## Problem Statement / Motivation

The Web Platform (app.soleur.ai) introduced server-side data processing (Supabase auth, Stripe payments, conversation storage). The Privacy Policy, Data Protection Disclosure, and GDPR Policy were updated in the March 20 2026 batch to cover account data, workspace data, and subscription data. However, three gaps remain:

1. The AUP still defines Soleur as "the Plugin" and describes only local execution. A user on the Web Platform who violates the AUP could argue the policy does not apply to cloud usage.
2. The Cookie Policy covers only the docs site (soleur.ai) and explicitly states the plugin "does not use cookies." It says nothing about app.soleur.ai session cookies (Supabase auth JWT stored in cookies, SameSite=Lax), CSRF origin validation, or Stripe Checkout cookies.
3. Conversation history (messages table: role, content, tool_calls; conversations table: domain_leader, status, session_id) is stored server-side but is not listed as a PII data category in any privacy document. The CLO assessment states: "If conversation data is stored server-side, it is a new PII category that must be added to all three privacy/GDPR documents."

## Proposed Solution

Update the existing legal documents in lockstep, following the pattern established by the 2026-02-21 cookie-free analytics learning. All edits are additive (extending existing sections) except the AUP which requires structural changes to Section 1, Section 2, Section 5, and Section 6.

### Dual-file locations

Per the cookie-free analytics learning, legal docs exist in two locations that must be updated in lockstep:

- `docs/legal/*.md` (Eleventy source with type/jurisdiction frontmatter)
- `plugins/soleur/docs/pages/legal/*.md` (plugin docs with layout/permalink frontmatter)

Body content must match across both locations. Update `docs/legal/` first, then sync to `plugins/soleur/docs/pages/legal/`.

## Technical Considerations

### Pre-Implementation: Exhaustive Grep Inventory

Per learning `2026-03-20-legal-doc-product-addition-prevention-strategies.md`, run these greps BEFORE making any edits to build a complete change inventory:

```bash
# AUP: Find every "Plugin" reference that may need Web Platform qualifier
grep -n "the Plugin\|Local Execution\|locally\|your machine" docs/legal/acceptable-use-policy.md

# Cookie Policy: Verify no blanket "no cookies" statements survive
grep -n "does not use cookies\|does not set\|no cookies" docs/legal/cookie-policy.md

# Privacy docs: Find all sections referencing Web Platform data
grep -n "conversation\|message\|chat" docs/legal/privacy-policy.md docs/legal/data-protection-disclosure.md docs/legal/gdpr-policy.md

# Blanket statement scan across ALL legal docs
grep -rn "does not collect\|does not store\|does not transmit\|does not process" docs/legal/
```

Classify each match into: **false statement** (P1 fix), **incomplete scope** (P2 fix), or **correctly scoped** (no action, with justification).

### Document 1: Acceptable Use Policy (`acceptable-use-policy.md`)

**Section 1 (Introduction):** Replace the parenthetical definition `("Soleur," "the Platform," "the Plugin"), a Claude Code plugin providing agents for software development workflows` with a definition that covers both the Plugin and the Web Platform. Reference `app.soleur.ai` explicitly.

**Section 2 (Scope):** Add Web Platform activities to the bullet list:

- Cloud-hosted conversation sessions via the Web Platform
- Account creation and workspace management on app.soleur.ai
- Subscription and payment processing through the Web Platform

Remove or qualify the statement "Soleur operates locally on your machine" -- it is no longer universally true. Replace with language that distinguishes Plugin (local) from Web Platform (cloud).

**Section 5.1 (Local Execution Model):** Rename heading to "User Responsibilities" or "Platform-Specific Responsibilities". Add Web Platform responsibilities:

- Securing account credentials for app.soleur.ai
- Not sharing or transferring account access to unauthorized third parties
- Compliance with usage limits and fair-use thresholds of the Web Platform
- Reporting unauthorized access to your Web Platform account

**Section 6 (Enforcement):** Add Web Platform enforcement mechanisms:

- Temporary or permanent suspension of Web Platform account access
- Termination of Web Platform account and deletion of associated data
- Restriction of specific Web Platform features or capabilities

Update Section 6.1 to acknowledge that the Web Platform enables server-side monitoring (unlike the purely local Plugin).

**Frontmatter:** Update `generated-date` or add a `last-updated` field.

### Document 2: Cookie Policy (`cookie-policy.md`)

**Section 3 (Our Cookie Usage):** Add a new subsection `3.3 The Web Platform (app.soleur.ai)` documenting:

| Cookie | Provider | Purpose | Type | Duration |
|--------|----------|---------|------|----------|
| `sb-*-auth-token` | Supabase (via app.soleur.ai) | Authentication session (JWT) | Strictly necessary (first-party) | Persistent (400 days; SameSite=Lax, HttpOnly=false per Supabase SSR defaults in `@supabase/ssr/src/utils/constants.ts`) |
| `sb-*-auth-token-code-verifier` | Supabase (via app.soleur.ai) | PKCE code verifier for OAuth flow | Strictly necessary (first-party) | Session (consumed and cleared after OAuth exchange) |
| `__stripe_mid` / `__stripe_sid` | Stripe (via Stripe Checkout redirect) | Fraud prevention during checkout | Strictly necessary (third-party) | Session / 1 year |

**Note on CSRF protection:** The Web Platform validates the `Origin` header on state-changing requests as CSRF protection (`lib/auth/validate-origin.ts`). This is not a cookie but is documented here for transparency. No CSRF token cookie is set -- the protection relies on Origin header checking.

**Section 4.1 (Strictly Necessary Cookies):** Add the app.soleur.ai cookies to the table.

**Section 4.4 (Functional Cookies):** Update to note that no functional cookies are set, but session cookies for authentication are strictly necessary (already covered in 4.1).

**Section 5 (Third-Party Cookies):** Add Stripe cookie disclosure with link to Stripe's cookie policy.

**Section 7 (Legal Basis):** Add that app.soleur.ai session cookies are strictly necessary and exempt from consent under ePrivacy Directive Article 5(3) -- they are required for the service the user explicitly requested (authentication, payment).

**Frontmatter:** Update `Last updated` date.

### Document 3: Privacy Policy (`privacy-policy.md`)

**Section 4.7 (Data Collected by the Web Platform):** Add conversation history as a new data category:

- **Conversation data:** Conversation metadata (domain leader, status, timestamps) and message content (user messages, assistant responses, tool call metadata) stored in the Supabase database. Conversations are associated with the user's account via user_id.

Update the Purpose and Retention bullets accordingly:

- **Purpose:** Providing the Web Platform service, including conversational AI interactions with domain-specific agents.
- **Retention:** Conversation data is retained while the user's account is active and deleted upon account deletion request (cascade delete via foreign key).

**Section 7 (Data Retention):** Add conversation data retention to the Web Platform bullet (currently covers account data and payment records but not conversations).

**Section 12 (Cookies):** Add a paragraph about app.soleur.ai cookies cross-referencing the Cookie Policy.

**Frontmatter:** Update `Last Updated` date and changelog note.

#### Research Insight: Secondary Section Propagation

Per learning `2026-03-18-split-legal-basis-cross-section-consistency.md`, adding a new data category propagates beyond the primary disclosure section. Grep for "Web Platform" and "conversation" across all sections to find secondary references. Known secondary sections:

- Section 7 (Retention) -- needs conversation-specific retention clause
- Section 8 (Rights) -- already mentions Web Platform; verify conversation data is covered by existing language
- Section 11 (Security) -- already covers Web Platform; no change needed

### Document 4: Data Protection Disclosure (`data-protection-disclosure.md`)

**Section 2.3 (Limited Processing by Soleur):** Add a new subsection (i) for conversation data processing:

- **(i)** **Web Platform conversation management:** The Web Platform stores conversation metadata and message content associated with user accounts. Data processed: conversation status, domain leader assignment, user messages, assistant responses, tool call metadata. Legal basis: contract performance (Article 6(1)(b) GDPR). Retention: while account is active; deleted on account deletion request (cascade delete).

**Section 2.1b(c) (Web Platform Data Processing):** Add conversation data to the list: "conversation metadata, message content".

**Section 4.2 (Web Platform Processors table):** Update Supabase row to include conversation data in "Data Processed" column.

**Section 10.3 (Web Platform Account Deletion):** Add that conversation data (messages and conversation metadata) is deleted on account deletion.

**Frontmatter:** Update `Last Updated` date and changelog note.

### Document 5: GDPR Policy (`gdpr-policy.md`)

**Section 3.7 (Web Platform Service Delivery):** Add conversation data processing under the account creation bullet or as a new bullet:

- **Conversation management:** The lawful basis is **contract performance** (Article 6(1)(b)) -- processing is necessary to provide the conversational AI service. Data processed: conversation metadata (domain leader, status, timestamps), message content (user messages, assistant responses, tool call metadata).

**Section 4.2 (Data That May Be Processed by Third Parties table):** Add a row for conversation data processed by Supabase.

**Section 8.4 (Web Platform Data retention):** Add that conversation data is retained while the account is active and deleted on account deletion.

**Section 10 (Record of Processing Activities -- Article 30 register):** Add a 10th processing activity:

10. **Web Platform conversation management** (app.soleur.ai via Supabase) -- conversation metadata (domain leader, status, timestamps) and message content (user messages, assistant responses, tool call metadata). Legal basis: contract performance (Article 6(1)(b)). Data is processed by Supabase Inc (project deployed to AWS eu-west-1, Ireland, EU -- no international data transfer). Retention: while account is active; deleted on account deletion request.

Update the register count from "nine processing activities" to "ten processing activities".

**Section 9 (DPIA):** Add re-evaluation note: conversation data does not change the DPIA conclusion (no special categories, no systematic monitoring, no automated decision-making).

**Section 11.2 (Breach Notification -- Practical Context):** Add conversation data compromise as a breach scenario: "(e) unauthorized access to conversation history stored in the Supabase database (user messages, assistant responses)."

**Frontmatter:** Update `Last Updated` date and changelog note.

#### Research Insight: Article 30 Register Consistency

Per learning `2026-02-21-gdpr-article-30-compliance-audit-pattern.md`, the public GDPR Policy references a processing activity count. If a private Article 30 register exists, it must also be updated. Verify no private register exists out-of-band.

## Acceptance Criteria

- [ ] AUP Section 1 defines Soleur to include both Plugin and Web Platform
- [ ] AUP Section 2 lists Web Platform activities in scope
- [ ] AUP Section 5 covers Web Platform user responsibilities (not just local execution)
- [ ] AUP Section 6 includes account suspension/termination as enforcement mechanisms
- [ ] Cookie Policy documents app.soleur.ai session cookies (Supabase auth)
- [ ] Cookie Policy documents Stripe checkout cookies
- [ ] Cookie Policy notes CSRF protection mechanism
- [ ] Cookie Policy legal basis covers app.soleur.ai strictly necessary cookies
- [ ] Privacy Policy Section 4.7 lists conversation history as a data category
- [ ] Data Protection Disclosure Section 2.3 includes conversation data processing
- [ ] GDPR Policy Article 30 register includes conversation management as processing activity #10
- [ ] All docs updated in both locations (`docs/legal/` and `plugins/soleur/docs/pages/legal/`)
- [ ] `Last Updated` dates and changelog notes updated in all modified documents
- [ ] `npx markdownlint-cli2 --fix` passes on all changed files
- [ ] GDPR Policy Section 9 (DPIA) includes re-evaluation note for conversation data
- [ ] GDPR Policy Section 11.2 (Breach Notification) includes conversation data compromise scenario
- [ ] Privacy Policy Section 7 (Retention) includes conversation data retention clause
- [ ] Post-edit blanket statement grep returns zero unaddressed "does not collect/store/transmit" matches
- [ ] legal-compliance-auditor run returns zero P1/P2 findings (post-edit verification)

## Test Scenarios

- Given the AUP, when a reader searches for "Web Platform" or "app.soleur.ai", then at least one match appears in Sections 1, 2, 5, and 6
- Given the AUP, when a reader searches for "account suspension" or "account termination", then enforcement mechanisms are documented in Section 6
- Given the Cookie Policy, when a reader searches for "app.soleur.ai", then session cookies are documented in a dedicated subsection
- Given the Cookie Policy, when a reader searches for "Stripe", then checkout cookies are documented
- Given the Privacy Policy Section 4.7, when a reader searches for "conversation", then conversation data is listed as a PII category
- Given the DPD Section 2.3, when a reader lists all lettered subsections, then conversation data appears
- Given the GDPR Policy Section 10, when a reader counts processing activities, then the count is 10 and includes conversation management
- Given any modified file, when `npx markdownlint-cli2` is run, then zero errors are reported
- Given both file locations (`docs/legal/` and `plugins/soleur/docs/pages/legal/`), when body content is compared for each modified document, then the content matches (frontmatter may differ)
- Given the AUP, when `grep -c "the Plugin" docs/legal/acceptable-use-policy.md | grep -v "Web Platform"` is run, then every remaining "the Plugin" reference is either correctly scoped to Plugin-only context or paired with "Web Platform"
- Given all legal docs, when `grep -rn "does not collect\|does not store\|does not transmit" docs/legal/` is run, then zero blanket statements contradict the new conversation data processing

### Post-Edit Verification Commands

Per learning `2026-03-20-legal-doc-product-addition-prevention-strategies.md`, run these after all edits are complete:

```bash
# 1. Section ordering -- verify monotonic order in all modified docs
for f in acceptable-use-policy cookie-policy privacy-policy data-protection-disclosure gdpr-policy; do
  echo "--- $f ---"
  grep -E '^#{2,3} [0-9]+' "docs/legal/${f}.md"
done

# 2. Product completeness -- find remaining Plugin-only references in AUP
grep -n "the Plugin" docs/legal/acceptable-use-policy.md | grep -v "Web Platform" | grep -v "Plugin only"

# 3. Blanket statement scan across ALL legal docs
grep -rn "does not collect\|does not store\|does not transmit\|does not process" docs/legal/

# 4. Conversation data completeness -- verify all three privacy docs mention conversation
for f in privacy-policy data-protection-disclosure gdpr-policy; do
  echo "--- $f ---"
  grep -c "conversation" "docs/legal/${f}.md"
done
```

## Dependencies and Risks

- **No code changes required.** All changes are to Markdown legal documents.
- **T&C already updated.** The Terms and Conditions was updated in the March 20 batch to include Web Platform scope (Section 4.3, definitions for "Web Platform", "Account Data", "Subscription"). No T&C changes needed in this PR.
- **Dual-file sync risk.** Five documents exist in two locations. Missing one location creates contradictions. Mitigated by updating `docs/legal/` first, then syncing.
- **Article 30 register count.** The GDPR Policy references "nine processing activities" -- this must be incremented to ten. If any other PR has modified the count concurrently, a merge conflict is expected but trivially resolvable.
- **DPIA re-evaluation.** Adding conversation data as a new PII category may trigger DPIA re-evaluation. However, conversation data does not involve special categories (Art. 9), systematic monitoring, or automated decision-making -- the existing DPIA assessment (GDPR Policy Section 9) conclusion remains valid. A sentence noting the re-evaluation should be added.
- **Compliance auditor cycle.** Per learning `2026-03-18-legal-cross-document-audit-review-cycle.md`, always run the legal-compliance-auditor agent AFTER all edits are complete, not during. Budget for one fix-reverify cycle. The auditor checks cross-document consistency, missing disclosures, and stale conditionals that are invisible in a section-by-section plan.

## Domain Review

**Domains relevant:** Legal

### Legal

**Status:** reviewed (self-assessed -- this IS the legal domain task)
**Assessment:** The CLO identified these three gaps in the original issue #1048. The plan addresses all three with specific section-level edits. No new legal frameworks are introduced -- all changes extend existing GDPR/ePrivacy patterns. The conversation data category follows the same contract-performance legal basis used for other Web Platform data. Cookie disclosures follow the strictly-necessary exemption under ePrivacy Directive Article 5(3). AUP changes add enforcement mechanisms consistent with cloud SaaS best practices.

## References and Research

### Internal References

- Issue: #1048 (legal: update AUP, Cookie Policy, and privacy docs for Web Platform)
- Milestone: Phase 2: Secure for Beta
- Schema: `apps/web-platform/supabase/migrations/001_initial_schema.sql` (conversations and messages tables, lines 46-90)
- Cookies: `apps/web-platform/middleware.ts` (Supabase auth cookie config, SameSite=Lax)
- Cookie defaults: `apps/web-platform/node_modules/@supabase/ssr/src/utils/constants.ts` (maxAge=400 days, httpOnly=false)
- CSRF: `apps/web-platform/lib/auth/validate-origin.ts` (Origin header validation)
- Auth callback: `apps/web-platform/app/(auth)/callback/route.ts` (cookie handling)

### Institutional Learnings Applied

| Learning | Key Insight Applied |
|----------|-------------------|
| `2026-02-21-cookie-free-analytics-legal-update-pattern.md` | Dual-file location sync pattern; lockstep update requirement |
| `2026-03-10-first-pii-collection-legal-update-pattern.md` | Grep verification for blanket "does not" statements after targeted edits |
| `2026-02-20-dogfood-legal-agents-cross-document-consistency.md` | Budget for audit-fix-reaudit cycle; cross-document consistency is invisible in section plans |
| `2026-03-20-legal-doc-product-addition-prevention-strategies.md` | Exhaustive grep inventory before implementation; section-by-section checklist; anchor-based insertion |
| `2026-03-18-legal-cross-document-audit-review-cycle.md` | Run compliance auditor AFTER all edits; budget for one fix-reverify cycle |
| `2026-03-18-split-legal-basis-cross-section-consistency.md` | New data category propagates to retention, rights, and processor sections -- not just primary disclosure |

### Files to Modify (10 files -- 5 documents x 2 locations)

| Document | Location 1 | Location 2 |
|----------|-----------|-----------|
| Acceptable Use Policy | `docs/legal/acceptable-use-policy.md` | `plugins/soleur/docs/pages/legal/acceptable-use-policy.md` |
| Cookie Policy | `docs/legal/cookie-policy.md` | `plugins/soleur/docs/pages/legal/cookie-policy.md` |
| Privacy Policy | `docs/legal/privacy-policy.md` | `plugins/soleur/docs/pages/legal/privacy-policy.md` |
| Data Protection Disclosure | `docs/legal/data-protection-disclosure.md` | `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` |
| GDPR Policy | `docs/legal/gdpr-policy.md` | `plugins/soleur/docs/pages/legal/gdpr-policy.md` |
