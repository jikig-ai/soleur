# Tasks: fix-signup-email

## Phase 1: Resend Account & Domain Setup

- [ ] 1.1 Create Resend account at https://resend.com (or use existing account)
- [ ] 1.2 Add `soleur.ai` as a sending domain in Resend dashboard
- [ ] 1.3 Generate a dedicated API key for Supabase SMTP (starts with `re_`)
- [ ] 1.4 Collect DNS verification records from Resend dashboard (SPF: `include:amazonses.com`, DKIM: CNAME records)
- [ ] 1.5 Pre-check: run `dig TXT soleur.ai +short` and `dig TXT _dmarc.soleur.ai +short` to check for existing SPF/DKIM/DMARC records

## Phase 2: DNS Configuration (Terraform)

- [ ] 2.1 Add SPF TXT record to `apps/web-platform/infra/dns.tf` -- use `~all` soft fail initially; merge with existing SPF if one exists
- [ ] 2.2 Add DKIM CNAME record(s) to `apps/web-platform/infra/dns.tf` (Resend uses CNAME, not TXT)
- [ ] 2.3 Add DMARC TXT record to `apps/web-platform/infra/dns.tf` with `p=none` initially for monitoring, `rua=mailto:dmarc-reports@soleur.ai`
- [ ] 2.4 Run `terraform plan` and `terraform apply` to create DNS records
- [ ] 2.5 Verify DNS propagation with `dig` and confirm domain verification passes in Resend dashboard

## Phase 3: Supabase Project Configuration (Management API)

- [ ] 3.1 Obtain Supabase access token from https://supabase.com/dashboard/account/tokens
- [ ] 3.2 Apply all config in a single Management API call (`PATCH /v1/projects/$PROJECT_REF/config/auth`):
  - [ ] 3.2.1 Set `site_url` to `https://app.soleur.ai`
  - [ ] 3.2.2 Set `uri_allow_list` to `http://localhost:3000/**,https://app.soleur.ai/**`
  - [ ] 3.2.3 Set SMTP: `smtp_host=smtp.resend.com`, `smtp_port=465`, `smtp_user=resend`, `smtp_pass=<api-key>`, `smtp_admin_email=noreply@soleur.ai`, `smtp_sender_name=Soleur`
  - [ ] 3.2.4 Set `mailer_subjects_magic_link` to `Sign in to Soleur`
  - [ ] 3.2.5 Set `mailer_templates_magic_link_content` to branded HTML template (uses `{{ .ConfirmationURL }}` for PKCE flow)

## Phase 4: Email Template Version Control

- [ ] 4.1 Create `apps/web-platform/supabase/templates/` directory
- [ ] 4.2 Write magic link email template HTML to `apps/web-platform/supabase/templates/magic-link.html`
  - Uses `{{ .ConfirmationURL }}` (correct for PKCE flow with `exchangeCodeForSession`)
  - Dark theme matching app.soleur.ai design
  - Includes: preheader text, `role="presentation"` tables, Outlook MSO conditionals, footer with CAN-SPAM compliance
- [ ] 4.3 Write configuration script to `apps/web-platform/supabase/scripts/configure-auth.sh` for reproducible setup

## Phase 5: Verification

- [ ] 5.1 Sign up with a test email at `app.soleur.ai` and verify sender is `noreply@soleur.ai`
- [ ] 5.2 Verify email body shows Soleur branding (dark theme, branded copy, footer)
- [ ] 5.3 Click magic link and verify redirect goes to `https://app.soleur.ai/callback` (PKCE code exchange)
- [ ] 5.4 Verify auth callback completes successfully (user lands on dashboard or setup-key page)
- [ ] 5.5 Test login flow (existing user) -- same email and redirect expectations
- [ ] 5.6 Test local development flow -- verify `http://localhost:3000` redirect still works
- [ ] 5.7 Check email deliverability via mail-tester.com (SPF, DKIM, DMARC pass, score 9+/10)
- [ ] 5.8 Test email rendering in Gmail (web + mobile), Apple Mail, and Outlook
