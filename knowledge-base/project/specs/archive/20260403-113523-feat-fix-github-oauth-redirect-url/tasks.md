# Tasks: fix GitHub OAuth redirect URL branding

## Phase 1: GitHub OAuth App Branding (immediate)

- [x] 1.1 Retrieve GitHub OAuth App Client ID from Doppler (`doppler secrets get GITHUB_CLIENT_ID -p soleur -c prd --plain`)
- [x] 1.2 Navigate to GitHub Developer Settings and locate the Soleur OAuth App via Playwright MCP
- [x] 1.3 Update OAuth App name to "Soleur" (already set)
- [x] 1.4 Set Homepage URL to `https://soleur.ai` (already set)
- [x] 1.5 Set application description (already set)
- [x] 1.6 Upload Soleur logo (from `plugins/soleur/docs/images/`) (already uploaded)
- [x] 1.7 Verify consent screen shows updated branding by initiating a test GitHub OAuth flow

## Phase 2: Supabase Pro Plan Upgrade (requires user approval)

- [x] 2.1 Confirm cost approval with user (~$35/mo: Pro $25 + custom domain ~$10)
- [x] 2.2 Upgrade Supabase to Pro plan via Playwright MCP (navigate to billing, hand off for payment)
- [x] 2.3 Update expense entry in `knowledge-base/operations/expenses.md`

## Phase 3: Supabase Custom Domain Setup

- [x] 3.1 Add CNAME DNS record in Terraform (`apps/web-platform/infra/dns.tf`): `api.soleur.ai` -> `ifsccnjhymdmidffkzhl.supabase.co`
- [x] 3.2 Apply Terraform (CNAME only): `doppler run -c prd_terraform --name-transformer tf-var -- terraform apply -target=cloudflare_record.supabase_custom_domain`
- [x] 3.3 Create custom domain: `supabase domains create --custom-hostname api.soleur.ai --project-ref ifsccnjhymdmidffkzhl` -- capture `_acme-challenge` TXT record value from output
- [x] 3.4 Add TXT record to Terraform (`_acme-challenge.api.soleur.ai` with value from 3.3) and apply
- [x] 3.5 Verify domain: poll `supabase domains reverify --project-ref ifsccnjhymdmidffkzhl` until verified (may take up to 30 minutes)

## Phase 4: OAuth Provider Callback URL Updates (BEFORE activation)

- [x] 4.1 Update GitHub OAuth App callback URL to `https://api.soleur.ai/auth/v1/callback` via Playwright MCP
- [x] 4.2 Update Google OAuth authorized redirect URIs to add `https://api.soleur.ai/auth/v1/callback` via Playwright MCP
- [x] 4.3 Verify both providers have the new callback URL configured

## Phase 5: Custom Domain Activation and Deployment

- [x] 5.1 Activate custom domain: `supabase domains activate --project-ref ifsccnjhymdmidffkzhl`
- [x] 5.2 Update Doppler `prd` config: `NEXT_PUBLIC_SUPABASE_URL` to `https://api.soleur.ai`
- [x] 5.3 Update `configure-auth.sh` `uri_allow_list` to include `https://api.soleur.ai/**`
- [ ] 5.4 Rebuild and deploy Docker image (triggers via CI on push)
- [ ] 5.5 Verify end-to-end GitHub OAuth flow with new callback URL
- [ ] 5.6 Verify end-to-end Google OAuth flow with new callback URL
- [ ] 5.7 Verify old Supabase URL still works (backward compatibility)
