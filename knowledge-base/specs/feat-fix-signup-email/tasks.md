# Tasks: fix-signup-email

## Phase 1: SMTP Provider Setup

- [ ] 1.1 Choose and sign up for an email provider (Resend recommended)
- [ ] 1.2 Add `soleur.ai` as a sending domain in the provider dashboard
- [ ] 1.3 Collect SMTP credentials (host, port, user, password)
- [ ] 1.4 Collect DNS verification records from provider (SPF, DKIM values)

## Phase 2: DNS Configuration (Terraform)

- [ ] 2.1 Add SPF TXT record to `apps/web-platform/infra/dns.tf`
- [ ] 2.2 Add DKIM TXT record(s) to `apps/web-platform/infra/dns.tf`
- [ ] 2.3 Add DMARC TXT record to `apps/web-platform/infra/dns.tf`
- [ ] 2.4 Run `terraform plan` and `terraform apply` to create DNS records
- [ ] 2.5 Verify DNS propagation with `dig` or provider's verification tool

## Phase 3: Supabase Project Configuration

- [ ] 3.1 Update Site URL from `http://localhost:3000` to `https://app.soleur.ai` (Dashboard > Authentication > URL Configuration, or Management API)
- [ ] 3.2 Add `https://app.soleur.ai/**` to Redirect URLs allowed list (keep `http://localhost:3000/**` for dev)
- [ ] 3.3 Configure custom SMTP settings with provider credentials (Dashboard > Authentication > SMTP Settings, or Management API)
- [ ] 3.4 Update Magic Link email template with Soleur-branded HTML (Dashboard > Authentication > Email Templates)
- [ ] 3.5 Update Confirmation email template with Soleur-branded HTML (if separate from magic link)

## Phase 4: Email Template Version Control

- [ ] 4.1 Create `apps/web-platform/supabase/templates/` directory
- [ ] 4.2 Commit magic link email template HTML to `apps/web-platform/supabase/templates/magic-link.html`
- [ ] 4.3 Commit any other customized email templates (confirmation, password reset)

## Phase 5: Verification

- [ ] 5.1 Sign up with a test email at `app.soleur.ai` and verify sender is `noreply@soleur.ai`
- [ ] 5.2 Verify email body shows Soleur branding (dark theme, logo, branded copy)
- [ ] 5.3 Click magic link and verify redirect goes to `https://app.soleur.ai/callback`
- [ ] 5.4 Verify auth callback completes successfully (user lands on dashboard or setup-key page)
- [ ] 5.5 Test login flow (existing user) -- same email and redirect expectations
- [ ] 5.6 Test local development flow -- verify `http://localhost:3000` redirect still works
- [ ] 5.7 Check email deliverability via mail-tester.com (SPF, DKIM, DMARC pass, score 9+/10)
