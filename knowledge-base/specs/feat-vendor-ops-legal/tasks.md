# Tasks: vendor-ops-legal

## Phase 1: Ops -- Expense Ledger

- [ ] 1.1 Check if Hetzner CX22 (telegram-bridge) is still running (`apps/telegram-bridge/infra/` Terraform state)
- [ ] 1.2 Add Hetzner CX33 recurring entry (~EUR 15.37/mo, 4 vCPU, 8 GB RAM, hel1)
- [ ] 1.3 Add Hetzner Volume recurring entry (~EUR 0.88/mo, 20 GB, hel1)
- [ ] 1.4 Add Supabase free tier entry ($0, upgrade thresholds: 500MB DB, 50K MAU, Pro: $25/mo)
- [ ] 1.5 Add Stripe test mode entry ($0, per-txn: 2.9%+$0.30 US / 1.5%+EUR 0.25 EU when live)
- [ ] 1.6 Update Cloudflare entry with `app.soleur.ai` subdomain note
- [ ] 1.7 Consider adding Status column (active/test-mode/free-tier/deferred/decommissioned)
- [ ] 1.8 Update `last_updated` date in expenses.md
- [ ] 1.9 Fix constitution stale path: `knowledge-base/ops/expenses.md` -> `knowledge-base/operations/expenses.md`

## Phase 2: Legal -- DPA Verification

- [ ] 2.1 **URGENT**: Sign Hetzner DPA (AVV) via Cloud Console account settings (NOT automatic per ToS 6.2)
- [ ] 2.2 Verify Supabase DPA availability for free tier via dashboard Legal Documents section (PandaDoc)
- [ ] 2.3 Check Supabase project region from `NEXT_PUBLIC_SUPABASE_URL` -- US or EU?
- [ ] 2.4 Confirm Stripe DPA is automatic (part of Services Agreement -- no action needed)
- [ ] 2.5 Verify Cloudflare DPA applicability for free tier (Self-Serve Subscription Agreement = Main Agreement?)
- [ ] 2.6 Write DPA verification memo to `knowledge-base/specs/feat-vendor-ops-legal/dpa-verification-memo.md`
  - [ ] 2.6.1 Row per vendor: DPA URL, tier coverage, acceptance mechanism, transfer mechanism, data categories

## Phase 3: Privacy Policy Updates (2 files)

- [ ] 3.1 Add Section 4.7 "Data Collected by the Web Platform" (email, auth tokens, session data, subscription status, encrypted API keys)
- [ ] 3.2 Scope Section 4.1 title/content to plugin only -- ensure no blanket contradictions
- [ ] 3.3 Add Section 5.5 Supabase (auth + database, processor, DPA reference)
- [ ] 3.4 Add Section 5.6 Stripe (payments, Checkout integration, PCI SAQ-A, DPA reference)
- [ ] 3.5 Add Section 5.7 Hetzner (hosting, Helsinki EU-only, DPA reference)
- [ ] 3.6 Update Cloudflare mention to include `app.soleur.ai`
- [ ] 3.7 Add Section 6 lawful basis for web platform (contract performance Art. 6(1)(b))
- [ ] 3.8 Update Section 7 data retention for web platform (account active + French tax law 10yr for payment records)
- [ ] 3.9 Update Section 10 international transfers (Supabase SCCs, Stripe DPF+SCCs, Hetzner EU-only)
- [ ] 3.10 Update "Last Updated" date and change description
- [ ] 3.11 Apply to `docs/legal/privacy-policy.md`
- [ ] 3.12 Apply identical changes to `plugins/soleur/docs/pages/legal/privacy-policy.md`
- [ ] 3.13 Run grep verification for contradicting blanket statements

## Phase 4: Data Protection Disclosure Updates (2 files -- verify root copy exists)

- [ ] 4.1 Verify `docs/legal/data-protection-disclosure.md` exists and check sync status with Eleventy copy
- [ ] 4.2 Restructure Section 2.1: scope to plugin, add 2.1b for web platform
- [ ] 4.3 Add processing activities (f)(g)(h) to Section 2.3
- [ ] 4.4 Rename Section 4.2 to "Service Processors" and add Supabase, Stripe, Hetzner rows
- [ ] 4.5 Update Section 8: mark each 8.1 commitment as fulfilled/in-progress
- [ ] 4.6 Update "Last Updated" date and change description
- [ ] 4.7 Apply to `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`
- [ ] 4.8 Apply identical changes to root source copy

## Phase 5: GDPR Policy Updates (2 files)

- [ ] 5.1 Add web platform services to Section 2.2 (Supabase, Stripe, Hetzner, Cloudflare update)
- [ ] 5.2 Add Section 3.7 (contract performance Art. 6(1)(b) for web platform)
- [ ] 5.3 Add web platform data categories to Section 4.2 table
- [ ] 5.4 Add web platform transfer disclosures to Section 6 (Supabase SCCs, Stripe DPF+SCCs, Hetzner EU-only)
- [ ] 5.5 Update Section 9 DPIA assessment (acknowledge web platform, explain below threshold)
- [ ] 5.6 Add processing activities 7-9 to Section 10 Article 30 register
- [ ] 5.7 Update "Last Updated" date and change description
- [ ] 5.8 Apply to `docs/legal/gdpr-policy.md`
- [ ] 5.9 Apply identical changes to `plugins/soleur/docs/pages/legal/gdpr-policy.md`

## Phase 6: Vendor Checklist Gate

- [ ] 6.1 Replace self-check rule in constitution.md (line 109 area) with formal vendor checklist
- [ ] 6.2 Add "Vendor Compliance" section to `.github/PULL_REQUEST_TEMPLATE.md`
- [ ] 6.3 Verify checklist is actionable for future PRs

## Phase 7: Verification & Commit

- [ ] 7.1 Run grep verification across all legal docs for contradicting blanket statements
- [ ] 7.2 Cross-reference all updated documents for consistency (dates, vendor names, section numbers)
- [ ] 7.3 Verify Resend is NOT mentioned in any legal doc updates (out of scope until integration exists)
- [ ] 7.4 Run compound skill before commit
- [ ] 7.5 Commit in logical chunks (ops, DPA memo, legal docs, process gate)
- [ ] 7.6 Push all changes
