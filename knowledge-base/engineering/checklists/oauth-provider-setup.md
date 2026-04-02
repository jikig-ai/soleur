# OAuth Provider Setup Checklist

Use this checklist when adding a new OAuth provider to Soleur (or any Supabase-backed app). Skipping consent screen branding causes users to see raw Supabase project URLs instead of your app name.

## Pre-Setup

- [ ] Identify the provider's developer console URL (see [Provider Reference](#provider-reference))
- [ ] Ensure you have admin access to the provider's developer console
- [ ] Have these URLs ready:
  - Homepage: `https://soleur.ai`
  - Privacy policy: `https://soleur.ai/pages/legal/privacy-policy.html`
  - Terms of service: `https://soleur.ai/pages/legal/terms-and-conditions.html`
  - Auth callback: `https://<SUPABASE_URL>/auth/v1/callback`

## 1. Provider Developer Console Setup

### Create OAuth App/Client

- [ ] Create a new OAuth application in the provider's developer console
- [ ] Set the app name to match your product name (e.g., "Soleur")
- [ ] Set the callback/redirect URL to `https://<SUPABASE_URL>/auth/v1/callback`
- [ ] Note the Client ID and Client Secret

### Configure Consent Screen Branding

This is the step most commonly skipped. Without it, users see the raw Supabase URL on the consent screen.

- [ ] Set app name (must match your product, not the GCP project name)
- [ ] Upload app logo (see provider-specific requirements below)
- [ ] Set homepage URL
- [ ] Set privacy policy URL
- [ ] Set terms of service URL
- [ ] Add your domain to authorized/allowed domains
- [ ] Set developer contact email

### Submit for Verification (if required)

- [ ] Check whether brand/app verification is required for your scopes
- [ ] If required, submit for verification and track the timeline
- [ ] Verify domain ownership if requested (DNS TXT record or meta tag)

## 2. Supabase Configuration

- [ ] Enable the provider in Supabase Auth settings (dashboard or `configure-auth.sh`)
- [ ] Store Client ID and Client Secret in Doppler (`GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, etc.)
- [ ] Pass credentials to Supabase via Management API or dashboard
- [ ] Add the callback URL to `uri_allow_list` if using a custom domain

## 3. Post-Setup Verification

- [ ] **Live sign-in test**: Click the provider button on the login page and complete the full OAuth flow
- [ ] Verify the consent screen shows your app name (not the Supabase URL)
- [ ] Verify the consent screen shows your logo
- [ ] Verify privacy policy and ToS links are visible on the consent screen
- [ ] Verify the redirect URL in the browser address bar matches expectations
- [ ] Verify the user account is created in Supabase Auth after sign-in
- [ ] Test sign-out and re-sign-in

> **Important**: Unit tests that mock `signInWithOAuth()` cannot catch consent screen branding issues. The live sign-in test above is the only way to verify branding is correct.

## Provider Reference

| Provider | Console URL | Logo Requirements | Verification |
|----------|------------|-------------------|-------------|
| Google | [Cloud Console](https://console.cloud.google.com/auth/branding) | 120x120px, JPG/PNG/BMP, <1MB | Brand verification: 2-3 days. App verification only for sensitive/restricted scopes |
| GitHub | [Developer Settings](https://github.com/settings/developers) | Any size logo upload | No verification required |
| Apple | [Developer Portal](https://developer.apple.com/account/resources/identifiers/) | N/A (uses Apple UI) | Requires Apple Developer Program membership |
| Microsoft | [Entra Admin Center](https://entra.microsoft.com/) | Square PNG, <=36KB | Publisher verification via Microsoft Partner Network |

## Custom Domain Considerations

If using a Supabase custom domain (e.g., `api.soleur.ai` instead of `<ref>.supabase.co`):

- [ ] Update ALL OAuth providers' redirect URIs to use the custom domain BEFORE activating the Supabase custom domain
- [ ] Verify the old Supabase URL still works during the transition (both URLs function simultaneously)
- [ ] After activation, verify OAuth flows use the new callback URL
- [ ] Update `NEXT_PUBLIC_SUPABASE_URL` in Doppler and rebuild the Docker image (NEXT_PUBLIC vars are baked at build time)

## Common Mistakes

1. **Skipping consent screen branding** -- Users see "Sign in to `<ref>.supabase.co`" instead of your app name
2. **Not adding your domain to authorized domains** -- Google rejects the OAuth flow
3. **Testing only with mocked OAuth** -- Mocks pass even when branding is misconfigured
4. **Forgetting to update redirect URIs before custom domain activation** -- OAuth breaks because providers don't have the new callback URL whitelisted
5. **Not rebuilding Docker after URL change** -- `NEXT_PUBLIC_SUPABASE_URL` is baked at build time, not read at runtime
