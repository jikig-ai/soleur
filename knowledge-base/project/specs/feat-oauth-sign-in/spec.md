# Feature: OAuth Sign-In

## Problem Statement

The Soleur web platform only supports magic-link (email OTP) authentication. Developer users expect OAuth sign-in with familiar providers (Google, GitHub), and enterprise users need Microsoft SSO. Apple Sign In is needed for privacy-conscious users and future iOS app compliance.

## Goals

- Add Google, Apple, GitHub, and Microsoft OAuth sign-in/sign-up
- Maintain existing magic-link auth as a fallback
- Preserve the post-auth routing chain (callback -> accept-terms -> setup-key -> dashboard)
- Auto-link OAuth accounts with matching verified emails
- Update legal documents to disclose OAuth data categories

## Non-Goals

- Replacing magic-link auth entirely
- Adding SAML/enterprise SSO beyond Microsoft OAuth
- Provider-specific native SDKs (Google One Tap, Apple JS SDK)
- Custom branding of provider consent screens
- Multi-factor authentication (separate feature)

## Functional Requirements

### FR1: OAuth Sign-In Buttons

Login and signup pages display OAuth buttons for Google, Apple, GitHub, and Microsoft below the existing magic-link form, separated by an "or" divider. Buttons follow each provider's brand guidelines (logo, sizing, color).

### FR2: Unified Authentication Flow

Clicking an OAuth button initiates Supabase's redirect flow (`signInWithOAuth()` with PKCE). If the user's email doesn't exist in Supabase, an account is automatically created. If the email matches an existing account, the OAuth identity is linked.

### FR3: Post-Auth Routing

OAuth users follow the same post-auth chain as magic-link users: `/callback` exchanges the code for a session, checks T&C acceptance, provisions workspace if needed, and routes to `/accept-terms`, `/setup-key`, or `/dashboard`.

### FR4: T&C Acceptance

First-time OAuth users are redirected to `/accept-terms` before accessing the dashboard. The existing 3-layer enforcement (DB trigger sets NULL -> server-side API records acceptance -> middleware enforces) applies without modification.

### FR5: Apple Email Relay Handling

Apple users who hide their email receive a `@privaterelay.appleid.com` address. This relay address is stored as the user's email and used for all communications. The system treats relay emails identically to real emails.

## Technical Requirements

### TR1: Supabase Provider Configuration

Enable Google, Apple, GitHub, and Microsoft OAuth providers in Supabase via the Management API or `configure-auth.sh`. Store client IDs and secrets in Doppler (production) and `.env` (development).

### TR2: CSP Policy Updates

Add OAuth provider token endpoints to `connect-src` in `lib/csp.ts`. No `frame-src` changes needed (redirect flow doesn't use iframes). Verify nonce-based CSP doesn't block the redirect flow.

### TR3: Callback Route Compatibility

Verify the existing `/callback` route (`exchangeCodeForSession`) handles OAuth PKCE responses correctly. The `code` parameter and exchange flow should be identical to magic-link, but test with each provider.

### TR4: Database Trigger Compatibility

Verify `handle_new_user()` trigger handles OAuth-created users correctly. OAuth inserts into `auth.users` with the same shape but may have different `raw_user_meta_data` structure. Ensure the trigger doesn't break on unexpected metadata.

### TR5: Provider Button Brand Compliance

Follow each provider's brand guidelines for sign-in buttons: Google Sign-In branding guidelines, Apple Human Interface Guidelines for Sign in with Apple, GitHub logos usage, Microsoft identity platform branding guidelines.

### TR6: Legal Document Updates

Update Privacy Policy, Terms & Conditions, Cookie Policy, GDPR Policy, and Data Protection Disclosure to disclose: OAuth provider user IDs, display names, avatar URLs, and the auto-linking behavior.

### TR7: Middleware Path Safety

Verify new OAuth-related paths (if any) are added to middleware public/exempt path lists using exact-or-prefix-with-slash matching (`pathname === p || pathname.startsWith(p + "/")`). No new paths should be needed since the existing `/callback` handles all providers.

### TR8: CSRF Coverage

Verify any new POST routes pass the existing CSRF negative-space test (`csrf-coverage.test.ts`). OAuth callback routes using provider state/nonce verification may need to be exempted with justification.
