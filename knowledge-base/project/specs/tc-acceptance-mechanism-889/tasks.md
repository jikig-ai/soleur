# Tasks: T&C Acceptance Mechanism for Web Platform Signup

## Phase 1: Database Migration + Trigger Update

- [ ] 1.1 Create new Supabase migration file `005_add_tc_accepted_at.sql`
  - [ ] 1.1.1 Add `tc_accepted_at timestamptz` column to `public.users` (nullable for existing users)
  - [ ] 1.1.2 Add column comment explaining NULL means user signed up before clickwrap was introduced
  - [ ] 1.1.3 Replace `handle_new_user()` trigger function to include `tc_accepted_at` from `new.raw_user_meta_data->>'tc_accepted'`
  - [ ] 1.1.4 Verify CASE WHEN expression handles: `'true'`, `'false'`, missing key (NULL), unexpected values

## Phase 2: Signup UI (Clickwrap Checkbox)

- [ ] 2.1 Update signup page (`apps/web-platform/app/(auth)/signup/page.tsx`)
  - [ ] 2.1.1 Add `tcAccepted` boolean state (default `false`)
  - [ ] 2.1.2 Add native HTML checkbox input (unchecked by default, `required` attribute) with proper `<label>` association (WCAG)
  - [ ] 2.1.3 Add label text: "I agree to the [Terms & Conditions] and [Privacy Policy]" with hyperlinks (`target="_blank"`, `rel="noopener noreferrer"`) to live docs site URLs
  - [ ] 2.1.4 Disable submit button when `!tcAccepted` (add to existing `disabled={loading}` condition)
  - [ ] 2.1.5 Pass `data: { tc_accepted: true }` in Supabase `signInWithOtp` `options` (metadata persists on first signup via `raw_user_meta_data`)
  - [ ] 2.1.6 Style checkbox and label consistent with existing form design (neutral-700 border, neutral-400 text, white underlined links)
  - [ ] 2.1.7 Test that clicking T&C/PP links opens new tab without toggling checkbox (add `onClick stopPropagation` on anchors if needed)

## Phase 3: Legal Document Updates

- [ ] 3.1 Pre-edit grep inventory: search all `docs/legal/*.md` and `plugins/soleur/docs/pages/legal/*.md` for acceptance-related references
- [ ] 3.2 Update DPD Section 8.1(g) in source file (`docs/legal/data-protection-disclosure.md`)
  - [ ] 3.2.1 Replace vague "Users accept the updated Terms and Conditions when creating a Web Platform account" with specific clickwrap mechanism description (checkbox, unchecked default, timestamped record)
  - [ ] 3.2.2 Update `Last Updated` date and change description
- [ ] 3.3 Sync DPD Eleventy copy (`plugins/soleur/docs/pages/legal/data-protection-disclosure.md`)
  - [ ] 3.3.1 Apply same content changes as 3.2
  - [ ] 3.3.2 Convert link format (.md relative to /pages/legal/*.html absolute)
  - [ ] 3.3.3 Update hero section last-updated text
- [ ] 3.4 Update T&C Section 4.3 in source file (`docs/legal/terms-and-conditions.md`)
  - [ ] 3.4.1 Add sentence specifying the clickwrap checkbox mechanism after "By creating a Web Platform account, you accept these Terms"
  - [ ] 3.4.2 Update `Last Updated` date and change description
- [ ] 3.5 Sync T&C Eleventy copy (`plugins/soleur/docs/pages/legal/terms-and-conditions.md`)
  - [ ] 3.5.1 Apply same content changes as 3.4
  - [ ] 3.5.2 Convert link format
  - [ ] 3.5.3 Update hero section last-updated text

## Phase 4: Verification

- [ ] 4.1 Post-edit grep verification across all legal docs
  - [ ] 4.1.1 Grep for unspecified "accept" claims without mechanism detail
  - [ ] 4.1.2 Diff source vs Eleventy copies for content consistency (DPD Section 8.1(g) and T&C Section 4.3)
- [ ] 4.2 Run legal-compliance-auditor on all source documents
- [ ] 4.3 Fix any P1/P2 findings from audit (budget for one fix-reverify cycle per learning `2026-03-18-legal-cross-document-audit-review-cycle.md`)

## Phase 5: Commit and PR

- [ ] 5.1 Run compound before commit
- [ ] 5.2 Commit with message referencing #889
- [ ] 5.3 Create PR with `Closes #889` in body
- [ ] 5.4 Set `semver:patch` label (legal doc + minor UI change, no new plugin components)
