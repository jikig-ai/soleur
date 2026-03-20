# Tasks: T&C Acceptance Mechanism for Web Platform Signup

## Phase 1: Database Migration

- [ ] 1.1 Create new Supabase migration file `005_add_tc_accepted_at.sql`
  - [ ] 1.1.1 Add `tc_accepted_at timestamptz` column to `public.users` (nullable for existing users)
  - [ ] 1.1.2 Add comment explaining NULL means user signed up before clickwrap was introduced

## Phase 2: Signup UI (Clickwrap Checkbox)

- [ ] 2.1 Update signup page (`apps/web-platform/app/(auth)/signup/page.tsx`)
  - [ ] 2.1.1 Add `tcAccepted` boolean state (default `false`)
  - [ ] 2.1.2 Add checkbox input (unchecked by default, `required` attribute)
  - [ ] 2.1.3 Add label text: "I agree to the [Terms & Conditions] and [Privacy Policy]" with hyperlinks opening in new tabs
  - [ ] 2.1.4 Disable submit button when `tcAccepted` is false
  - [ ] 2.1.5 Pass `tc_accepted: true` in Supabase `signInWithOtp` `options.data` metadata
  - [ ] 2.1.6 Style checkbox and label consistent with existing form design (neutral-700 border, neutral-400 text, white links)

## Phase 3: Backend -- Record Acceptance Timestamp

- [ ] 3.1 Update callback route (`apps/web-platform/app/(auth)/callback/route.ts`)
  - [ ] 3.1.1 In `ensureWorkspaceProvisioned`, read `user.user_metadata.tc_accepted` flag
  - [ ] 3.1.2 When inserting a new user row, set `tc_accepted_at: new Date().toISOString()` if metadata flag is true
  - [ ] 3.1.3 For existing users (re-login), do not overwrite `tc_accepted_at`

## Phase 4: Legal Document Updates

- [ ] 4.1 Update DPD Section 8.1(g) in source file (`docs/legal/data-protection-disclosure.md`)
  - [ ] 4.1.1 Replace vague "Users accept the updated Terms and Conditions when creating a Web Platform account" with specific clickwrap mechanism description (checkbox, unchecked default, timestamped record)
  - [ ] 4.1.2 Update `Last Updated` date and change description
- [ ] 4.2 Sync DPD Eleventy copy (`plugins/soleur/docs/pages/legal/data-protection-disclosure.md`)
  - [ ] 4.2.1 Apply same content changes as 4.1
  - [ ] 4.2.2 Convert link format (.md relative to /pages/legal/*.html absolute)
  - [ ] 4.2.3 Update hero section last-updated text
- [ ] 4.3 Update T&C Section 4.3 in source file (`docs/legal/terms-and-conditions.md`)
  - [ ] 4.3.1 Add sentence specifying the clickwrap checkbox mechanism after "By creating a Web Platform account, you accept these Terms"
  - [ ] 4.3.2 Update `Last Updated` date and change description
- [ ] 4.4 Sync T&C Eleventy copy (`plugins/soleur/docs/pages/legal/terms-and-conditions.md`)
  - [ ] 4.4.1 Apply same content changes as 4.3
  - [ ] 4.4.2 Convert link format
  - [ ] 4.4.3 Update hero section last-updated text

## Phase 5: Verification

- [ ] 5.1 Grep verification across all legal docs
  - [ ] 5.1.1 Grep for unspecified "accept" claims without mechanism detail
  - [ ] 5.1.2 Verify source and Eleventy copies are content-consistent
- [ ] 5.2 Run legal-compliance-auditor on all source documents
- [ ] 5.3 Fix any P1/P2 findings from audit
- [ ] 5.4 End-to-end test: verify full signup flow (email + checkbox -> magic link -> callback -> user row with `tc_accepted_at`)

## Phase 6: Commit and PR

- [ ] 6.1 Run compound before commit
- [ ] 6.2 Commit with message referencing #889
- [ ] 6.3 Create PR with `Closes #889` in body
- [ ] 6.4 Set `semver:patch` label (legal doc + minor UI change, no new plugin components)
