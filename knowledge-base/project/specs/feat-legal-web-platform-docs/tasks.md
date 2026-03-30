# Tasks: legal: update AUP, Cookie Policy, and privacy docs for Web Platform

Closes #1048

## Phase 0: Pre-Implementation Grep Inventory

- [ ] 0.1 Run exhaustive grep for "the Plugin", "locally", "your machine" in AUP -- classify each match as false-statement / incomplete-scope / correctly-scoped
- [ ] 0.2 Run blanket statement grep across ALL legal docs: `grep -rn "does not collect\|does not store\|does not transmit\|does not process" docs/legal/`
- [ ] 0.3 Run "conversation" grep in privacy docs to identify all sections needing updates (primary + secondary)

## Phase 1: Acceptable Use Policy

- [ ] 1.1 Update Section 1 (Introduction) -- expand definition of Soleur to cover both Plugin and Web Platform, reference app.soleur.ai
- [ ] 1.2 Update Section 2 (Scope) -- add Web Platform activities, qualify "operates locally" statement
- [ ] 1.3 Update Section 5.1 -- rename heading, add Web Platform user responsibilities
- [ ] 1.4 Update Section 6 (Enforcement) -- add account suspension/termination, update Section 6.1 monitoring
- [ ] 1.5 Update frontmatter dates
- [ ] 1.6 Post-edit verification: `grep -n "the Plugin" docs/legal/acceptable-use-policy.md | grep -v "Web Platform" | grep -v "Plugin only"` -- verify zero unaddressed matches
- [ ] 1.7 Sync `docs/legal/acceptable-use-policy.md` to `plugins/soleur/docs/pages/legal/acceptable-use-policy.md`

## Phase 2: Cookie Policy

- [ ] 2.1 Add Section 3.3 (The Web Platform) -- document Supabase auth cookies (400-day persistent, SameSite=Lax), PKCE code verifier, Stripe checkout cookies; add CSRF note as prose (not table row)
- [ ] 2.2 Update Section 4.1 (Strictly Necessary Cookies) -- add app.soleur.ai cookies to table
- [ ] 2.3 Update Section 5 (Third-Party Cookies) -- add Stripe cookie disclosure
- [ ] 2.4 Update Section 7 (Legal Basis) -- add ePrivacy exemption for app.soleur.ai strictly necessary cookies
- [ ] 2.5 Update frontmatter dates
- [ ] 2.6 Sync `docs/legal/cookie-policy.md` to `plugins/soleur/docs/pages/legal/cookie-policy.md`

## Phase 3: Privacy Policy

- [ ] 3.1 Update Section 4.7 -- add conversation data as new PII category (conversation metadata, message content, tool call metadata)
- [ ] 3.2 Update Section 7 (Retention) -- add conversation data retention clause to Web Platform bullet
- [ ] 3.3 Update Section 12 (Cookies) -- add paragraph about app.soleur.ai cookies, cross-reference Cookie Policy
- [ ] 3.4 Update frontmatter dates and changelog note
- [ ] 3.5 Sync `docs/legal/privacy-policy.md` to `plugins/soleur/docs/pages/legal/privacy-policy.md`

## Phase 4: Data Protection Disclosure

- [ ] 4.1 Add Section 2.3(i) -- Web Platform conversation management processing activity
- [ ] 4.2 Update Section 2.1b(c) -- add conversation data to Web Platform data list
- [ ] 4.3 Update Section 4.2 Supabase row -- add conversation data to "Data Processed" column
- [ ] 4.4 Update Section 10.3 -- add conversation data deletion on account deletion
- [ ] 4.5 Update frontmatter dates and changelog note
- [ ] 4.6 Sync `docs/legal/data-protection-disclosure.md` to `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`

## Phase 5: GDPR Policy

- [ ] 5.1 Update Section 3.7 -- add conversation management lawful basis
- [ ] 5.2 Update Section 4.2 table -- add conversation data row for Supabase
- [ ] 5.3 Update Section 8.4 -- add conversation data retention
- [ ] 5.4 Update Section 10 (Article 30 register) -- add processing activity #10, update count from nine to ten
- [ ] 5.5 Update Section 9 (DPIA) -- add re-evaluation note for conversation data
- [ ] 5.6 Update Section 11.2 (Breach Notification) -- add conversation data compromise scenario
- [ ] 5.7 Update frontmatter dates and changelog note
- [ ] 5.8 Sync `docs/legal/gdpr-policy.md` to `plugins/soleur/docs/pages/legal/gdpr-policy.md`

## Phase 6: Validation

- [ ] 6.1 Run `npx markdownlint-cli2 --fix` on all 10 changed files
- [ ] 6.2 Run post-edit verification commands (section ordering, product completeness, blanket statements, conversation grep)
- [ ] 6.3 Verify body content matches between `docs/legal/` and `plugins/soleur/docs/pages/legal/` for all 5 documents
- [ ] 6.4 Verify "Web Platform" or "app.soleur.ai" appears in AUP Sections 1, 2, 5, 6
- [ ] 6.5 Verify "conversation" appears in Privacy Policy Section 4.7, DPD Section 2.3, GDPR Section 10
- [ ] 6.6 Verify Article 30 register count is "ten" in GDPR Policy Section 10
- [ ] 6.7 Run legal-compliance-auditor agent on all source documents -- fix any P1/P2 findings and re-verify (budget for one cycle)
