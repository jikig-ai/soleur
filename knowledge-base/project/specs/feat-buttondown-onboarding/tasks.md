# Tasks: Buttondown Newsletter Onboarding

## Phase 1: Newsletter Branding via API

- [x] 1.1 Set newsletter description via `PATCH /v1/newsletters/{id}` -- "Monthly updates about Soleur -- new agents, skills, and what we are building next."
- [x] 1.2 Set tint color to brand gold `#C9A962` via API
- [x] 1.3 Set header content (Markdown: Soleur heading + tagline) via API
- [x] 1.4 Set footer content (Markdown: brand tagline + social links) via API
- [x] 1.5 Set timezone to `Europe/Paris` via API
- [x] 1.6 Verify all branding fields via API GET and confirm values match targets

## Phase 2: Icon and Share Image via Playwright

- [x] 2.1 Log into Buttondown dashboard via Playwright (user may need to enter credentials for login step)
- [x] 2.2 Navigate to `https://buttondown.com/settings`
- [x] 2.3 Upload icon: `plugins/soleur/docs/images/logo-mark-512.png` (512x512, Buttondown resizes to 300x300)
- [x] 2.4 Upload share image: `plugins/soleur/docs/images/og-image.png` (1200x630, exact match)
- [x] 2.5 Verify icon and image fields are non-null via API GET

## Phase 3: Sending Domain Setup

- [x] 3.1 Navigate to Buttondown Settings > Domains via Playwright MCP
- [x] 3.2 Enter `mail.soleur.ai` as the sending domain
- [x] 3.3 Select managed DNS option and capture the two NS record values
- [x] 3.4 Add `cloudflare_record` resources for both NS records to `apps/web-platform/infra/dns.tf` (use `name = "mail"`, not FQDN)
- [x] 3.5 Run `terraform fmt` on `dns.tf`
- [x] 3.6 Run `terraform plan` to validate the new DNS resources
- [x] 3.7 Run `terraform apply` to create the NS records
- [x] 3.8 Run `terraform plan` again to verify clean state (no drift)
- [x] 3.9 Verify DNS propagation with `dig NS mail.soleur.ai +short`
- [x] 3.10 Verify sending domain shows as verified in Buttondown dashboard via Playwright
- [x] 3.11 Update newsletter `email_domain` via API if not automatically set (auto-set by Buttondown)

## Phase 4: First Newsletter Draft

- [x] 4.1 Draft first email content (introduction to Soleur, set expectations for future newsletters)
- [x] 4.2 Create draft via `POST /v1/emails` API with `status: "draft"` (verified working)
- [x] 4.3 Preview draft in Buttondown dashboard via Playwright to verify branding renders correctly
- [x] 4.4 Decision gate: sent to subscribers on 2026-04-07

## Phase 5: Expense Tracking and Documentation

- [x] 5.1 Add Buttondown free-tier entry to `knowledge-base/operations/expenses.md`
- [x] 5.2 Run markdownlint on modified files
