---
title: "legal: specify T&C acceptance mechanism for Web Platform signup"
type: fix
date: 2026-03-20
semver: patch
---

# legal: specify T&C acceptance mechanism for Web Platform signup

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 6
**Research sources used:** Supabase docs (Context7), WCAG accessibility patterns, French/EU clickwrap case law, project learnings (3 relevant), Vercel React best practices

### Key Improvements

1. Revised architecture recommendation from Option A (callback metadata) to Option C (trigger-based) after Supabase docs confirmed `new.raw_user_meta_data->>'key'` is accessible in PL/pgSQL triggers -- simpler, atomic, zero application-layer coordination
2. Added WCAG accessibility requirements for the checkbox (native HTML checkbox, proper label association, no aria-checked)
3. Added concrete code examples for signup page, migration SQL, and trigger modification
4. Incorporated three project learnings: dual-file sync gap, Supabase silent error returns, legal cross-document audit cycle
5. Added edge case for Supabase `data` option first-signup-only limitation and mitigation

### New Considerations Discovered

- The `signInWithOtp` `data` option only persists metadata on first signup (not subsequent sign-ins) -- this is fine for T&C acceptance since acceptance only happens at signup
- The existing `handle_new_user()` trigger already accesses `new.id` and `new.email` -- extending it with `new.raw_user_meta_data->>'tc_accepted'` follows the established pattern
- WCAG requires native HTML checkbox elements with proper `<label>` association; `aria-checked` must NOT be used on `<input type="checkbox">`

---

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
2. **Data layer**: Add a `tc_accepted_at` timestamp column to the `users` table and record acceptance at signup time via the existing `handle_new_user()` trigger
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

#### Research Insights: UI Implementation

**Accessibility (WCAG compliance):**

- Use a native HTML `<input type="checkbox">` element -- never a custom div with `aria-checked` (the W3C APG Checkbox Pattern specifies that `aria-checked` must NOT be added to native checkbox inputs; browser determines checked state)
- Associate the label with `<label htmlFor="tc-checkbox">` wrapping the text content
- Links inside the label must be standard `<a>` elements with `target="_blank"` and `rel="noopener noreferrer"` for security
- Add `aria-required="true"` only if there is a visual indicator (asterisk or "required" text) -- per WCAG, the programmatic requirement must match visual cues

**React state pattern (from existing codebase conventions):**

- The signup page already uses `useState` for `email`, `sent`, `error`, `loading` -- add `tcAccepted` in the same pattern
- Disable the submit button when `!tcAccepted` (consistent with the existing `disabled={loading}` pattern)
- Show validation error text in the same `text-sm text-red-400` style as the existing error display

**Concrete implementation sketch** (`apps/web-platform/app/(auth)/signup/page.tsx`):

```tsx
const [tcAccepted, setTcAccepted] = useState(false);

// In signInWithOtp call, pass metadata:
const { error } = await supabase.auth.signInWithOtp({
  email,
  options: {
    emailRedirectTo: `${window.location.origin}/callback`,
    data: { tc_accepted: true },
  },
});

// In form JSX, before submit button:
<label className="flex items-start gap-3 text-sm text-neutral-400">
  <input
    type="checkbox"
    required
    checked={tcAccepted}
    onChange={(e) => setTcAccepted(e.target.checked)}
    className="mt-0.5 h-4 w-4 rounded border-neutral-700 bg-neutral-900"
  />
  <span>
    I agree to the{" "}
    <a
      href="https://soleur.ai/pages/legal/terms-and-conditions.html"
      target="_blank"
      rel="noopener noreferrer"
      className="text-white underline hover:text-neutral-300"
    >
      Terms & Conditions
    </a>{" "}
    and{" "}
    <a
      href="https://soleur.ai/pages/legal/privacy-policy.html"
      target="_blank"
      rel="noopener noreferrer"
      className="text-white underline hover:text-neutral-300"
    >
      Privacy Policy
    </a>
  </span>
</label>

// Update button disabled condition:
<button
  type="submit"
  disabled={loading || !tcAccepted}
  ...
>
```

**Edge case -- link clicks vs checkbox toggle:** Clicking a link inside a `<label>` element can inadvertently toggle the checkbox. The `<a>` elements have their own click handler that calls `stopPropagation` implicitly by navigating away (opening a new tab). Test that clicking the link opens the tab without toggling the checkbox. If this causes issues, move the links outside the `<label>` or use `onClick={(e) => e.stopPropagation()}` on the anchor elements.

### Database migration

A new Supabase migration adds `tc_accepted_at timestamptz` to the `public.users` table. The column is nullable -- existing users have `NULL` (grandfathered under the browsewrap terms in effect at their signup time).

#### Research Insights: Architecture Decision -- Trigger vs Callback

The original plan recommended Option A (recording in the callback). After researching Supabase's auth architecture, **Option C (trigger-based) is now recommended** as the simpler approach:

**Why Option C is better:**

1. **The trigger already has access to `raw_user_meta_data`.** The Supabase docs confirm that `new.raw_user_meta_data->>'key'` is accessible in PL/pgSQL trigger functions on `auth.users`. The existing `handle_new_user()` trigger already reads `new.id` and `new.email` -- adding `new.raw_user_meta_data->>'tc_accepted'` follows the same pattern.

2. **Atomic with user creation.** The trigger fires on `auth.users` INSERT, which happens when `signInWithOtp` creates the user. The `tc_accepted_at` timestamp is set in the same transaction as user creation -- no window of inconsistency.

3. **No application-layer coordination needed.** Option A required the callback route to read metadata and update `public.users` separately. Option C handles everything in a single SQL trigger.

4. **The `data` option works for first signup.** Supabase's `signInWithOtp` `data` option stores metadata in `raw_user_meta_data` on first signup. Subsequent sign-ins do not update metadata -- but T&C acceptance only happens once at signup, so this limitation is irrelevant.

| Option | Complexity | Atomicity | Application changes |
|--------|-----------|-----------|-------------------|
| A: Callback metadata | Medium | Two-step (trigger INSERT + callback UPDATE) | Modify callback route |
| B: Separate API call | High | Non-atomic (window of missing acceptance) | New API endpoint + client call |
| **C: Trigger (recommended)** | **Low** | **Atomic (single transaction)** | **Only modify trigger + signup page** |

**Concrete migration** (`apps/web-platform/supabase/migrations/005_add_tc_accepted_at.sql`):

```sql
-- Add T&C acceptance timestamp to users table
-- NULL means user signed up before clickwrap was introduced (grandfathered)
alter table public.users
  add column tc_accepted_at timestamptz;

comment on column public.users.tc_accepted_at is
  'Timestamp when user accepted T&C via clickwrap checkbox. NULL = signed up before clickwrap was introduced.';

-- Update handle_new_user() to record T&C acceptance from signup metadata
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.users (id, email, workspace_path, tc_accepted_at)
  values (
    new.id,
    new.email,
    '/workspaces/' || new.id::text,
    case
      when (new.raw_user_meta_data->>'tc_accepted')::boolean = true
      then now()
      else null
    end
  );
  return new;
end;
$$ language plpgsql security definer;
```

#### Research Insights: Supabase Gotchas (from project learnings)

**Silent error returns** (learning: `2026-03-20-supabase-silent-error-return-values.md`): The Supabase JS client returns `{ data, error }` without throwing. Every Supabase call must destructure and check `error`. The `signInWithOtp` call in the signup page already checks `error` correctly, but verify the metadata `data` option does not silently fail.

**Trigger failure blocks signups** (from Supabase docs): If the `handle_new_user()` trigger throws an error, the entire `auth.users` INSERT is rolled back and signup fails silently. Test the `CASE WHEN` expression with:

- `tc_accepted = 'true'` (string from metadata)
- `tc_accepted` missing from metadata (returns NULL, handled by `ELSE null`)
- Unexpected value (e.g., `'false'`, empty string)

The `(new.raw_user_meta_data->>'tc_accepted')::boolean` cast handles `'true'` -> `true` and `'false'` -> `false`. If the key is missing, `->>` returns SQL `NULL`, and `NULL::boolean` is `NULL`, so the `CASE` falls to `ELSE null`. This is safe.

### Legal document updates

Four files need updates (source + Eleventy copies):

1. **DPD Section 8.1(g)** (`docs/legal/data-protection-disclosure.md` + `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`): Change from vague "Users accept..." to specific: "Users accept the updated Terms and Conditions via a clickwrap checkbox on the Web Platform signup page (app.soleur.ai/signup). The checkbox is unchecked by default and must be actively checked before account creation. Acceptance is timestamped and recorded in the user database."

2. **T&C Section 4.3** (`docs/legal/terms-and-conditions.md` + `plugins/soleur/docs/pages/legal/terms-and-conditions.md`): Add specificity to "By creating a Web Platform account, you accept these Terms" -- describe that acceptance requires checking the T&C checkbox during signup.

#### Research Insights: Legal Document Dual-File Sync

**Dual-file sync gap** (learning: `2026-03-18-dpd-processor-table-dual-file-sync.md`): Legal docs exist in two locations with different frontmatter and link formats. Every edit must touch both files in the same PR. The Eleventy copies use `/pages/legal/*.html` absolute links; the source copies use `*.md` relative links.

**Cross-document audit cycle** (learning: `2026-03-18-legal-cross-document-audit-review-cycle.md`): Run the legal-compliance-auditor agent AFTER all edits are complete to catch cross-document inconsistencies. Budget for one fix-reverify cycle.

**Product addition prevention strategies** (learning: `2026-03-20-legal-doc-product-addition-prevention-strategies.md`): Before editing, grep for all "accept" references across all legal documents to ensure no other sections reference the acceptance mechanism in a way that becomes inaccurate after the update.

**Pre-edit grep checklist:**

```bash
# Find all acceptance-related references across legal docs
grep -n "accept.*Terms\|accept.*T&C\|accept.*conditions\|creating.*account.*accept" docs/legal/*.md
grep -n "accept.*Terms\|accept.*T&C\|accept.*conditions\|creating.*account.*accept" plugins/soleur/docs/pages/legal/*.md

# Verify no other DPD sections reference the acceptance mechanism
grep -n "8.1(g)\|acceptance.*mechanism\|clickwrap\|checkbox" docs/legal/data-protection-disclosure.md
```

### Non-goals

- Re-acceptance on T&C version changes (future work -- file a follow-up issue for version-aware re-acceptance with `tc_version` column)
- Separate consent checkboxes for T&C vs Privacy Policy (single checkbox linking to both is legally sufficient for contract acceptance; Privacy Policy acceptance is covered under contract performance basis, not consent)
- Login page changes (login is for returning users who already accepted at signup)
- Cookie consent (separate concern, handled by cookie policy)
- Storing T&C version hash in the database (future work for version tracking)

## Acceptance Criteria

- [x] Signup page displays an unchecked checkbox with text "I agree to the Terms & Conditions and Privacy Policy" where both document names are clickable links opening in new tabs
- [x] Checkbox uses native HTML `<input type="checkbox">` with proper `<label>` association (WCAG)
- [x] Form submission is blocked (button disabled) when checkbox is unchecked
- [x] Checkbox links point to the live docs site URLs: `https://soleur.ai/pages/legal/terms-and-conditions.html` and `https://soleur.ai/pages/legal/privacy-policy.html`
- [x] Database migration adds `tc_accepted_at timestamptz` column to `public.users` table (nullable for existing users)
- [x] `handle_new_user()` trigger records `tc_accepted_at = now()` when `raw_user_meta_data->>'tc_accepted'` is true
- [x] Signup form passes `data: { tc_accepted: true }` in `signInWithOtp` options
- [x] DPD Section 8.1(g) specifies the clickwrap mechanism (checkbox, unchecked default, timestamped record)
- [x] T&C Section 4.3 describes the acceptance mechanism
- [x] DPD and T&C changes are synced between source (`docs/legal/`) and Eleventy (`plugins/soleur/docs/pages/legal/`) copies with correct link formats
- [ ] Legal compliance auditor reports zero new P1/P2 findings after changes
- [x] Trigger handles missing or false `tc_accepted` metadata gracefully (returns NULL, does not block signup)

## Test Scenarios

- Given a new user on the signup page, when they enter an email without checking the T&C checkbox, then the submit button is disabled and form submission is prevented
- Given a new user on the signup page, when they check the T&C checkbox and submit their email, then the magic link is sent successfully
- Given a new user who signed up with the checkbox checked, when the `handle_new_user` trigger fires, then `public.users.tc_accepted_at` is set to the current timestamp
- Given the T&C link in the checkbox label, when clicked, then the Terms & Conditions page opens in a new tab without toggling the checkbox state
- Given the Privacy Policy link in the checkbox label, when clicked, then the Privacy Policy page opens in a new tab without toggling the checkbox state
- Given an existing user (created before this change) in the database, when querying their record, then `tc_accepted_at` is NULL (not retroactively set)
- Given a signup attempt where `raw_user_meta_data` does not contain `tc_accepted`, when the trigger fires, then `tc_accepted_at` is NULL and signup still succeeds
- Given the DPD source and Eleventy files, when diffed for Section 8.1(g), then the clickwrap mechanism description is consistent (content identical, link format differs)
- Given the T&C source and Eleventy files, when diffed for Section 4.3, then the acceptance mechanism description is consistent

## Dependencies & Risks

| Risk | Mitigation |
|------|-----------|
| `signInWithOtp` `data` option does not persist through OTP flow | Supabase docs confirm metadata is stored in `raw_user_meta_data` on first signup; test end-to-end with a real Supabase instance |
| Trigger modification blocks signups if SQL error | Test the `CASE WHEN` expression with all edge cases (true, false, missing key, null) in a staging environment before deploying |
| Existing users have NULL `tc_accepted_at` | Documented as intentional -- they accepted under the browsewrap terms in effect at their signup time |
| T&C version tracking not included | Out of scope -- file a follow-up issue (#TBD) for version-aware re-acceptance |
| Checkbox reduces signup conversion | Necessary for legal compliance; the checkbox is standard practice and expected by EU users |
| Link clicks inside `<label>` toggle the checkbox | Test interaction; use `onClick stopPropagation` on `<a>` elements if needed |
| Supabase JS client silently swallows errors | Verify `signInWithOtp` error handling includes metadata-related failures (learning: `2026-03-20-supabase-silent-error-return-values.md`) |

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
- Learning: `knowledge-base/project/learnings/2026-03-20-supabase-silent-error-return-values.md`
- Learning: `knowledge-base/project/learnings/2026-03-18-dpd-processor-table-dual-file-sync.md`

### External References

- CJEU, Planet49, C-673/17 (pre-ticked checkboxes prohibition)
- ECJ 2015 clickwrap "durable record" ruling
- Cour de cassation, 1re civ., 13 juillet 2016 (French T&C acceptance requirements)
- GDPR Article 7 (conditions for consent)
- [Clickwrap vs Browsewrap enforceability](https://secureprivacy.ai/blog/clickwrap-vs-browsewrap-agreements-understanding-enforceability-legal-considerations)
- [Clickwrap effectiveness in the EU](https://www.termsfeed.com/blog/clickwrap-eu/)
- [Best practices for clickwrap agreements](https://www.termsfeed.com/blog/clickwrap-best-practices/)
- [Supabase signInWithOtp API reference](https://supabase.com/docs/reference/javascript/auth-signinwithotp)
- [Supabase user metadata management](https://supabase.com/docs/guides/auth/managing-user-data)
- [W3C ARIA APG Checkbox Pattern](https://www.w3.org/WAI/ARIA/apg/patterns/checkbox/)
- [Supabase user metadata with magic link (GitHub issue #699)](https://github.com/supabase/gotrue/issues/699)

### Related Work

- Issue: #889 (this plan)
- PR: #880 (T&C update for Web Platform -- `legal-web-platform-703-736` branch)
- Issue: #736 (original T&C update requirement)
- Issue: #703 (legal doc verification for Web Platform)
