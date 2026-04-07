# Tasks: Buttondown Newsletter Onboarding

## Phase 1: Newsletter Branding via API

- [ ] 1.1 Set newsletter description via `PATCH /v1/newsletters/{id}` -- "Monthly updates about Soleur -- new agents, skills, and what we are building next."
- [ ] 1.2 Set tint color to brand gold `#C9A962` via API
- [ ] 1.3 Set header content (Markdown: Soleur heading + tagline) via API
- [ ] 1.4 Set footer content (Markdown: brand tagline + social links) via API
- [ ] 1.5 Set timezone to `Europe/Paris` via API
- [ ] 1.6 Verify all branding fields via API GET and confirm values match targets

## Phase 2: Icon and Share Image via Playwright

- [ ] 2.1 Check for existing brand assets in `plugins/soleur/docs/images/` and `knowledge-base/design/brand/`
- [ ] 2.2 Generate newsletter icon (300x300 square PNG) if no suitable asset exists -- use `soleur:gemini-imagegen` or extract from existing logo
- [ ] 2.3 Generate share image (1200x630 PNG) if no suitable asset exists
- [ ] 2.4 Upload icon via Playwright MCP to `https://buttondown.com/settings`
- [ ] 2.5 Upload share image via Playwright MCP
- [ ] 2.6 Verify icon and image fields are non-null via API GET

## Phase 3: Sending Domain Setup

- [ ] 3.1 Navigate to Buttondown Settings > Domains via Playwright MCP
- [ ] 3.2 Enter `mail.soleur.ai` as the sending domain
- [ ] 3.3 Select managed DNS option and capture the two NS record values
- [ ] 3.4 Add `cloudflare_record` resources for both NS records to `apps/web-platform/infra/dns.tf`
- [ ] 3.5 Run `terraform plan` to validate the new DNS resources
- [ ] 3.6 Run `terraform apply` to create the NS records
- [ ] 3.7 Verify DNS propagation with `dig NS mail.soleur.ai +short`
- [ ] 3.8 Verify sending domain shows as verified in Buttondown dashboard via Playwright
- [ ] 3.9 Update newsletter `email_domain` via API if not automatically set

## Phase 4: First Newsletter Draft

- [ ] 4.1 Draft first email content (introduction to Soleur, set expectations for future newsletters)
- [ ] 4.2 Create draft via `POST /v1/emails` API (or Playwright if draft status not supported)
- [ ] 4.3 Preview draft in Buttondown dashboard via Playwright to verify branding renders correctly
- [ ] 4.4 Decision gate: send or hold for user review

## Phase 5: Expense Tracking and Documentation

- [ ] 5.1 Add Buttondown free-tier entry to `knowledge-base/operations/expenses.md`
- [ ] 5.2 Run markdownlint on modified files
