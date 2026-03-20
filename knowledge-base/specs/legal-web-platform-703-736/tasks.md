# Tasks: Update Legal Documents for Web Platform Cloud Services

## Phase 1: Terms & Conditions Update (#736)

### 1.1 Update T&C source file (`docs/legal/terms-and-conditions.md`)

- [x] 1.1.1 Update frontmatter `Last Updated` date to March 20, 2026 with change description
- [x] 1.1.2 Update Section 1 (Introduction) to include "the Web Platform" in scope definition and acceptance clause
- [x] 1.1.3 Add "Web Platform," "Subscription," and "Account Data" definitions to Section 2
- [x] 1.1.4 Scope Section 4.1 to Plugin only: change "Soleur does not operate cloud servers" to "The Plugin does not..." and add cross-reference to Section 4.3
- [x] 1.1.5 Add Section 4.3: Web Platform Service (account, payment via Stripe Checkout, workspace, BYOK, data processing acknowledgment)
- [x] 1.1.6 Add cross-reference in Section 7.1 to new Section 7.1b for Web Platform data practices
- [x] 1.1.7 Add Section 7.1b: Web Platform Data Practices (Supabase account data, Stripe payment, Hetzner workspace, Cloudflare CDN)
- [x] 1.1.8 Rewrite Section 7.4 to split Plugin (local control) and Web Platform (exercisable via legal@jikigai.com) GDPR rights
- [x] 1.1.9 Update Section 9.1 and 9.2 to cover both Plugin and Web Platform
- [x] 1.1.10 Update Section 10.1 and 10.2 liability language to cover both Plugin and Web Platform; add EUR 100 floor
- [x] 1.1.11 Add Section 13.1b: Web Platform Account Termination (data deletion, payment retention per French tax law)
- [x] 1.1.12 Update Section 13.3 to include Web Platform data deletion on termination
- [x] 1.1.13 Update Section 15.1 to reference both Plugin and Web Platform

### 1.2 Sync T&C Eleventy copy (`plugins/soleur/docs/pages/legal/terms-and-conditions.md`)

- [x] 1.2.1 Apply all content changes from 1.1
- [x] 1.2.2 Convert link format: `.md` relative links to `/pages/legal/*.html` absolute links
- [x] 1.2.3 Maintain Eleventy-specific frontmatter (description, layout, permalink)
- [x] 1.2.4 Maintain Eleventy-specific HTML wrapper (page-hero section, content section, prose div)
- [x] 1.2.5 Maintain template variables ({{ stats.agents }}, {{ stats.skills }}, etc.)
- [x] 1.2.6 Diff source vs Eleventy to verify consistency (content identical, format differences only)

## Phase 2: Verification Pass (#703)

**Status: COMPLETE (verified during plan deepening)**

All three documents (Privacy Policy, DPD, GDPR Policy) confirmed complete and in sync between source and Eleventy copies.

- [x] 2.1 Privacy Policy: Section 4.7, Sections 5.5-5.8, international transfers, data retention all present
- [x] 2.2 DPD: Section 2.1b, processor table 4.2, Section 8 transition fulfilled
- [x] 2.3 GDPR Policy: Section 3.7, Section 4.2, Article 30 entries 7-9, DPIA evaluation complete
- [x] 2.4 Source vs Eleventy sync confirmed for all three documents

## Phase 3: Cross-Document Audit

- [x] 3.1 Run legal-compliance-auditor on all four source documents (benchmark mode)
- [x] 3.2 Verify T&C acceptance clause matches DPD Section 8.1(g)
- [x] 3.3 Fix any P1/P2 findings in both source and Eleventy locations
  - Fixed P1 #1: Section numbering (4.3 before 4.2) in both files
  - Fixed P3 #14: Section 12 now mentions Web Platform
  - Fixed P3 #16: Survival clause now includes Section 7
  - Filed #888: DPD missing Web Platform data subject rights (P1 pre-existing)
  - Filed #889: T&C acceptance mechanism unspecified (P1 product concern)
  - Filed #890: Pre-existing P2/P3 findings across PP, DPD, GDPR Policy
- [x] 3.4 Re-run auditor to verify zero P1/P2 findings — remaining P1s are pre-existing in other docs (tracked in #888, #889)

## Phase 4: grep Verification

- [x] 4.1 Grep T&C for unscoped "does not collect/operate/store/transmit" -- all scoped to "the Plugin" ✓
- [x] 4.2 Grep T&C for "Soleur does not" blanket statements -- zero matches ✓
- [x] 4.3 Grep all four source documents for remaining unscoped blanket statements -- all context-specific ✓
- [x] 4.4 Grep T&C for stale conditional language ("if cloud features," "when cloud," "future cloud") -- zero matches ✓

## Phase 5: Commit and PR

- [ ] 5.1 Run compound before commit
- [ ] 5.2 Commit with message referencing both #703 and #736
- [ ] 5.3 Create PR with `Closes #703` and `Closes #736` in body
- [ ] 5.4 Set `semver:patch` label (legal doc update, no plugin component changes)
