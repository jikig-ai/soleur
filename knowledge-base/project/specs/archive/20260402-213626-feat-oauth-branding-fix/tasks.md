# Tasks: fix Google OAuth consent screen branding

Source plan: `knowledge-base/project/plans/2026-04-02-fix-google-oauth-consent-screen-branding-plan.md`

## Phase 1: Google OAuth Consent Screen Branding (immediate)

- [ ] 1.1 Navigate to Google Cloud Console OAuth consent screen for project `972366012527` via Playwright MCP
- [ ] 1.2 Set app name to "Soleur"
- [ ] 1.3 Upload Soleur logo
- [ ] 1.4 Set application home page to `https://soleur.ai`
- [ ] 1.5 Set authorized domains to `soleur.ai`
- [ ] 1.6 Set privacy policy URL to `https://soleur.ai/pages/legal/privacy-policy.html`
- [ ] 1.7 Set terms of service URL to `https://soleur.ai/pages/legal/terms-and-conditions.html`
- [ ] 1.8 Check OAuth app publishing status (testing/production) and verification state
- [ ] 1.9 Submit for Google verification if needed (can take weeks; branding still shows for <100 users)
- [ ] 1.10 Save consent screen configuration
- [ ] 1.11 Verify by initiating Google OAuth from `https://app.soleur.ai/login` and checking consent screen

## Phase 2: Supabase Custom Domain (requires plan upgrade decision)

- [ ] 2.1 Confirm with user: proceed with Supabase Pro upgrade ($25/mo)?
- [ ] 2.2 Navigate to Supabase dashboard billing page via Playwright MCP, drive to payment step, hand off for payment
- [ ] 2.3 After upgrade confirmed, add CNAME record to `apps/web-platform/infra/dns.tf`:
  - `api.soleur.ai` -> `ifsccnjhymdmidffkzhl.supabase.co`
- [ ] 2.4 Run `terraform apply` to create DNS record
- [ ] 2.5 Run `supabase domains create --custom-hostname api.soleur.ai --project-ref ifsccnjhymdmidffkzhl`
- [ ] 2.6 Add TXT record for domain verification (value provided by Supabase) to `dns.tf`
- [ ] 2.7 Run `terraform apply` for TXT record
- [ ] 2.8 Run `supabase domains reverify --project-ref ifsccnjhymdmidffkzhl` until verified
- [ ] 2.9 Activate custom domain: `supabase domains activate --project-ref ifsccnjhymdmidffkzhl`
- [ ] 2.10 Update Doppler `prd` config: `NEXT_PUBLIC_SUPABASE_URL` -> `https://api.soleur.ai`
- [ ] 2.11 Rebuild and redeploy Docker image
- [ ] 2.12 Update ALL OAuth providers' redirect URIs (Google, GitHub; Apple/Microsoft per #1341)
- [ ] 2.13 Verify Supabase custom domain auto-updates auth callback URL, or update via Management API
- [ ] 2.14 Update Supabase auth config `uri_allow_list` via `configure-auth.sh`
- [ ] 2.15 Update `knowledge-base/operations/expenses.md` Supabase entry: $0 -> $25/mo
- [ ] 2.16 Verify end-to-end auth flow with new domain (all enabled providers)

## Phase 3: OAuth Setup Checklist (documentation)

- [ ] 3.1 Create `knowledge-base/engineering/checklists/oauth-provider-setup.md`
  - [ ] 3.1.1 Section: Provider Developer Console Setup (app creation, credentials)
  - [ ] 3.1.2 Section: Consent Screen Branding (app name, logo, domain, legal URLs)
  - [ ] 3.1.3 Section: Redirect URI Configuration (custom domain if available)
  - [ ] 3.1.4 Section: Credential Storage (Doppler `prd` config)
  - [ ] 3.1.5 Section: Supabase Provider Enablement (`configure-auth.sh`)
  - [ ] 3.1.6 Section: Post-Setup Verification Checklist
~~- [ ] 3.2 Removed per review -- `configure-auth.sh` enhancement is YAGNI; checklist document is sufficient~~

## Phase 4: Verification

- [ ] 4.1 Browser test: Google OAuth consent screen shows "Soleur" with logo and legal links
- [ ] 4.2 Browser test: redirect URL uses custom domain (if Part 2 completed)
- [ ] 4.3 Full auth flow test: Google sign-in -> callback -> dashboard
- [ ] 4.4 Verify other OAuth providers (GitHub) still work after any URL changes
