---
title: "legal: specify T&C acceptance mechanism for Web Platform signup"
type: fix
date: 2026-03-20
semver: patch
---

# legal: specify T&C acceptance mechanism for Web Platform signup

## Overview

The Web Platform signup flow at `app.soleur.ai/signup` currently collects an email address and sends a magic link -- but presents no T&C acceptance mechanism (no checkbox, no link to terms, no affirmative action). The DPD Section 8.1(g) claims "Users accept the updated Terms and Conditions when creating a Web Platform account" (marked FULFILLED), and T&C Section 4.3 says "By creating a Web Platform account, you accept these Terms." Neither document specifies _how_ acceptance is obtained. This creates a P1 legal enforceability gap under French law.

## Problem Statement / Motivation

Under French contract law and EU consumer protection rules, the enforceability of general terms and conditions requires demonstrable evidence that the user had reasonable notice and took an affirmative action to accept. The current "browsewrap" approach (implied acceptance by using the service) is the weakest form of consent and has been consistently rejected by French courts (Cour de cassation jurisprudence) when challenged.

The European Court of Justice (2015) established that clickwrap mechanisms create a "durable record" of binding agreement. Under GDPR Article 7, consent must be "freely given, specific, informed, and unambiguous" -- requiring an affirmative act such as ticking a checkbox or clicking a button. Pre-ticked checkboxes are explicitly prohibited (CJEU, Planet49, C-673/17).

Without a clickwrap mechanism:
- T&C acceptance is unenforceable if challenged in court
- DPD Section 8.1(g) "FULFILLED" status is inaccurate -- no mechanism exists to produce an acceptance record
- No audit trail of when each user accepted which version of the T&C

## Proposed Solution

Implement a clickwrap T&C acceptance mechanism on the signup page with a required checkbox, record the acceptance timestamp in the database, and update legal documents to specify the mechanism.

### Architecture

The solution has three layers:

1. **UI layer**: Add a required, unchecked checkbox to the signup form linking to T&C and Privacy Policy
2. **Data layer**: Add a `tc_accepted_at` timestamp column to the `users` table and record acceptance at signup time
3. **Legal documentation layer**: Update DPD Section 8.1(g) to specify the clickwrap mechanism; update T&C Section 4.3 to describe the acceptance flow

### Why clickwrap checkbox (not alternatives)

| Approach | Enforceability | Evidence Quality | GDPR Compliance |
|----------|---------------|-----------------|-----------------|
| Browsewrap (current) | Weak -- rejected by French courts | None | Non-compliant |
| Sign-in-wrap (button text says "I agree") | Medium | Moderate | Compliant if clear |
| Clickwrap checkbox (proposed) | Strong -- accepted by ECJ and French courts | Timestamped record | Fully compliant |

Clickwrap with a required unchecked checkbox is the gold standard because:
- It requires an affirmative action (checking a box)
- The unchecked default proves the user actively chose to accept
- Combined with a timestamp, it creates a durable, auditable record
- It is explicitly compliant with GDPR Article 7 requirements

## Technical Considerations

### Signup flow changes

The signup page (`apps/web-platform/app/(auth)/signup/page.tsx`) is a client component using Supabase `signInWithOtp`. The checkbox must:
- Be unchecked by default (GDPR requirement)
- Block form submission until checked (HTML `required` attribute + React state)
- Link to T&C and Privacy Policy with visible, underlined hyperlinks
- Use clear language: "I agree to the Terms & Conditions and Privacy Policy"

### Database migration

A new Supabase migration adds `tc_accepted_at timestamptz` to the `public.users` table. The column is `NOT NULL` for new users (enforced at application level during signup). Existing users have `NULL` (grandfathered -- they accepted via the browsewrap mechanism that was in place at their signup time).

The `handle_new_user()` trigger function in `001_initial_schema.sql` inserts rows into `public.users` on `auth.users` creation. The trigger fires _before_ the callback route processes the request. The `tc_accepted_at` timestamp should be set in the callback route's `ensureWorkspaceProvisioned` function when inserting a new user, not in the trigger (the trigger cannot know about the checkbox state).

However, the Supabase OTP flow creates the `auth.users` row (and fires the trigger) when `signInWithOtp` is called -- before the callback. The callback then exchanges the code for a session. The acceptance timestamp must be passed from the signup form to the callback route. Options:

**Option A (recommended): Record in callback with metadata.** Pass the acceptance signal via Supabase user metadata (`signInWithOtp` `data` option). The callback reads metadata and sets `tc_accepted_at` on the `public.users` row.

**Option B: Record directly from client.** After the magic link is clicked and the callback completes, call a separate API endpoint to record acceptance. This adds a network round-trip and a window where the user exists without recorded acceptance.

**Option C: Record in trigger via user metadata.** Modify the `handle_new_user()` trigger to read from `raw_user_meta_data` and set `tc_accepted_at`. This couples the trigger to application-level concerns.

Option A is preferred because it records acceptance atomically during the first-login provisioning flow, requires no additional API calls, and keeps the trigger simple.

### Legal document updates

Four files need updates (source + Eleventy copies):

1. **DPD Section 8.1(g)** (`docs/legal/data-protection-disclosure.md` + `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`): Change from vague "Users accept..." to specific: "Users accept the updated Terms and Conditions via a clickwrap checkbox on the Web Platform signup page (app.soleur.ai/signup). The checkbox is unchecked by default and must be actively checked before account creation. Acceptance is timestamped and recorded in the user database."

2. **T&C Section 4.3** (`docs/legal/terms-and-conditions.md` + `plugins/soleur/docs/pages/legal/terms-and-conditions.md`): Add specificity to "By creating a Web Platform account, you accept these Terms" -- describe that acceptance requires checking the T&C checkbox during signup.

### Non-goals

- Re-acceptance on T&C version changes (future work -- track in a separate issue)
- Separate consent checkboxes for T&C vs Privacy Policy (single checkbox linking to both is legally sufficient for contract acceptance; Privacy Policy acceptance is covered under contract performance basis, not consent)
- Login page changes (login is for returning users who already accepted at signup)
- Cookie consent (separate concern, handled by cookie policy)

## Acceptance Criteria

- [ ] Signup page displays an unchecked checkbox with text "I agree to the Terms & Conditions and Privacy Policy" where both document names are clickable links
- [ ] Form submission is blocked (button disabled or validation error) when checkbox is unchecked
- [ ] Checkbox links open T&C at `/pages/legal/terms-and-conditions.html` and Privacy Policy at `/pages/legal/privacy-policy.html` in new tabs
- [ ] Database migration adds `tc_accepted_at timestamptz` column to `public.users` table (nullable for existing users)
- [ ] New user creation records `tc_accepted_at = now()` when the acceptance checkbox was checked
- [ ] DPD Section 8.1(g) specifies the clickwrap mechanism (checkbox, unchecked default, timestamped record)
- [ ] T&C Section 4.3 describes the acceptance mechanism
- [ ] DPD and T&C changes are synced between source (`docs/legal/`) and Eleventy (`plugins/soleur/docs/pages/legal/`) copies
- [ ] Legal compliance auditor reports zero new P1/P2 findings after changes

## Test Scenarios

- Given a new user on the signup page, when they enter an email without checking the T&C checkbox, then form submission is prevented with a clear error message
- Given a new user on the signup page, when they check the T&C checkbox and submit their email, then the magic link is sent and `tc_accepted_at` is recorded upon first callback
- Given the T&C link in the checkbox label, when clicked, then the Terms & Conditions page opens in a new tab
- Given the Privacy Policy link in the checkbox label, when clicked, then the Privacy Policy page opens in a new tab
- Given an existing user (created before this change) in the database, when querying their record, then `tc_accepted_at` is NULL (not retroactively set)
- Given the DPD source and Eleventy files, when diffed for Section 8.1(g), then the clickwrap mechanism description is consistent (content identical, link format differs)
- Given the T&C source and Eleventy files, when diffed for Section 4.3, then the acceptance mechanism description is consistent

## Dependencies & Risks

| Risk | Mitigation |
|------|-----------|
| Supabase user metadata may not persist through OTP flow | Test the full OTP flow end-to-end; fall back to Option B if metadata is lost |
| Existing users have NULL `tc_accepted_at` | Documented as intentional -- they accepted under the browsewrap terms in effect at their signup time |
| T&C version tracking not included | Out of scope -- file a follow-up issue for version-aware re-acceptance |
| Checkbox reduces signup conversion | Necessary for legal compliance; the checkbox is standard practice and expected by EU users |

## References & Research

### Internal References

- Signup page: `apps/web-platform/app/(auth)/signup/page.tsx`
- Auth callback: `apps/web-platform/app/(auth)/callback/route.ts`
- DB schema: `apps/web-platform/supabase/migrations/001_initial_schema.sql`
- DPD source: `docs/legal/data-protection-disclosure.md` (Section 8.1(g), line ~245)
- DPD Eleventy: `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`
- T&C source: `docs/legal/terms-and-conditions.md` (Section 4.3, line ~66)
- T&C Eleventy: `plugins/soleur/docs/pages/legal/terms-and-conditions.md`
- Related tasks file: `knowledge-base/project/specs/legal-web-platform-703-736/tasks.md`
- Learning: `knowledge-base/project/learnings/2026-03-20-legal-doc-product-addition-prevention-strategies.md`
- Learning: `knowledge-base/project/learnings/2026-03-18-legal-cross-document-audit-review-cycle.md`
- Learning: `knowledge-base/project/learnings/2026-03-10-first-pii-collection-legal-update-pattern.md`

### External References

- CJEU, Planet49, C-673/17 (pre-ticked checkboxes prohibition)
- ECJ 2015 clickwrap "durable record" ruling
- Cour de cassation, 1re civ., 13 juillet 2016 (French T&C acceptance requirements)
- GDPR Article 7 (conditions for consent)
- [Clickwrap vs Browsewrap enforceability](https://secureprivacy.ai/blog/clickwrap-vs-browsewrap-agreements-understanding-enforceability-legal-considerations)
- [Clickwrap effectiveness in the EU](https://www.termsfeed.com/blog/clickwrap-eu/)
- [Best practices for clickwrap agreements](https://www.termsfeed.com/blog/clickwrap-best-practices/)

### Related Work

- Issue: #889 (this plan)
- PR: #880 (T&C update for Web Platform -- `legal-web-platform-703-736` branch)
- Issue: #736 (original T&C update requirement)
- Issue: #703 (legal doc verification for Web Platform)
