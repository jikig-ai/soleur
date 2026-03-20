# Tasks: Update Legal Documents for Web Platform Cloud Services

## Phase 1: Terms & Conditions Update (#736)

### 1.1 Update T&C source file

- [ ] 1.1.1 Update frontmatter `Last Updated` date to March 20, 2026
- [ ] 1.1.2 Add "Web Platform" and "Subscription" definitions to Section 2
- [ ] 1.1.3 Scope Section 4.1 to Plugin only, add Section 4.1b for Web Platform architecture
- [ ] 1.1.4 Add Section 4.3: Web Platform Service (account, subscription, workspace, BYOK)
- [ ] 1.1.5 Scope Section 7.1 to Plugin only, add Section 7.1b for Web Platform data practices
- [ ] 1.1.6 Update Section 7.4 to include Web Platform GDPR rights
- [ ] 1.1.7 Update Section 9.1 to cover both Plugin and Web Platform
- [ ] 1.1.8 Add Section 13.1b for Web Platform account termination
- [ ] 1.1.9 Update Section 13.3 to include Web Platform data deletion
- [ ] 1.1.10 Update Section 15.1 to reference both Plugin and Web Platform

### 1.2 Sync T&C Eleventy copy

- [ ] 1.2.1 Apply all content changes to `plugins/soleur/docs/pages/legal/terms-and-conditions.md`
- [ ] 1.2.2 Maintain Eleventy-specific differences (frontmatter, HTML wrapper, link paths, template variables)
- [ ] 1.2.3 Diff source vs Eleventy to verify consistency

## Phase 2: Verification Pass (#703)

### 2.1 Privacy Policy verification

- [ ] 2.1.1 Verify Section 4.7 (web platform data) is complete
- [ ] 2.1.2 Verify Sections 5.5-5.8 (processors) are complete
- [ ] 2.1.3 Verify international transfers section includes all web platform processors
- [ ] 2.1.4 Diff source vs Eleventy copy for consistency

### 2.2 DPD verification

- [ ] 2.2.1 Verify Section 2.1b (web platform processing) is complete
- [ ] 2.2.2 Verify Section 4.2 processor table includes all vendors
- [ ] 2.2.3 Verify Section 8 transition status is fulfilled
- [ ] 2.2.4 Diff source vs Eleventy copy for consistency

### 2.3 GDPR Policy verification

- [ ] 2.3.1 Verify Section 3.7 (web platform legal basis) is complete
- [ ] 2.3.2 Verify Section 4.2 (data categories) includes web platform data
- [ ] 2.3.3 Verify Article 30 register entries 7-9 are present
- [ ] 2.3.4 Verify DPIA evaluation is complete
- [ ] 2.3.5 Diff source vs Eleventy copy for consistency

## Phase 3: Cross-Document Audit

- [ ] 3.1 Run legal-compliance-auditor on all four documents
- [ ] 3.2 Fix any P1/P2 findings
- [ ] 3.3 Re-run auditor to verify zero P1/P2 findings

## Phase 4: grep Verification

- [ ] 4.1 Grep all four source documents for unscoped "does not collect/operate/store/transmit" statements
- [ ] 4.2 Confirm all matches are scoped to "the Plugin" or "Plugin itself"

## Phase 5: Commit and PR

- [ ] 5.1 Run compound before commit
- [ ] 5.2 Commit with message referencing both #703 and #736
- [ ] 5.3 Create PR with `Closes #703` and `Closes #736` in body
