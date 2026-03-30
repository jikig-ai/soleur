# OAuth Sign-In Brainstorm

**Date:** 2026-03-27
**Status:** Complete
**Branch:** feat-oauth-sign-in

## What We're Building

Adding OAuth sign-up and sign-in to the Soleur web platform (`apps/web-platform/`) alongside the existing magic-link (email OTP) authentication. Four providers: Google, Apple, GitHub, and Microsoft.

### Current State

- **Auth**: Magic-link OTP only via Supabase (`signInWithOtp`)
- **Separate flows**: Login page uses `shouldCreateUser: false`; signup page allows creation
- **Post-auth chain**: `/callback` (code exchange + workspace provision + T&C check) -> `/accept-terms` -> `/setup-key` -> `/dashboard`
- **Security**: Nonce-based CSP, CSRF origin validation, middleware-based auth routing, cookie-based sessions via `@supabase/ssr`
- **Callback route**: Already uses `exchangeCodeForSession` (PKCE) -- works for OAuth without changes

### Target State

- OAuth buttons on both login and signup pages (unified flow -- auto-creates account if needed)
- Magic-link auth remains available alongside OAuth
- Same post-auth routing chain for all auth methods
- Auto-linking of accounts with matching verified emails

## Why This Approach

### Supabase Redirect Flow (PKCE)

Selected the Supabase-native redirect flow (`signInWithOAuth()`) over popup flow or provider-specific SDKs because:

1. **Minimal callback changes**: The existing `/callback` route already uses `exchangeCodeForSession`, which is the same PKCE flow OAuth uses
2. **No CSP changes for frame-src**: Redirect flow doesn't use iframes or popups -- avoids the `frame-src 'none'` conflict
3. **No popup blocker issues**: Full-page redirect is universally supported
4. **Consistent UX**: All four providers use the same interaction pattern
5. **Lower complexity**: One flow pattern vs four provider-specific SDK integrations

### Unified Flow (vs. Split Login/Signup)

OAuth buttons handle both signup and login in a single interaction. If the user's email doesn't exist in Supabase, an account is created. This is the industry standard for OAuth and avoids the confusing UX of "you need to sign up first" when a user tries to sign in with a provider.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Providers | Google, Apple, GitHub, Microsoft | Covers consumer (Google, Apple), developer (GitHub), and enterprise (Microsoft) audiences |
| Flow model | Unified | Single OAuth button handles both signup and login. Industry standard, simpler UX |
| Account linking | Auto-link on verified email | Supabase default behavior. User with magic-link account can seamlessly switch to OAuth |
| Magic link | Keep alongside OAuth | Fallback for email-only users. No migration needed |
| T&C acceptance | Post-auth redirect | OAuth users hit `/accept-terms` after first login, same as magic-link. Existing 3-layer enforcement (trigger -> API -> middleware) handles this with zero new code |
| OAuth UX pattern | Supabase redirect flow (PKCE) | Simplest, works with existing callback, no CSP frame-src changes needed |
| CSP impact | `connect-src` additions only | Add provider token endpoints to CSP. `frame-src` stays `'none'` since redirect flow doesn't use iframes |

## Open Questions

1. **Apple email relay**: Apple allows users to hide their real email. The `handle_new_user()` trigger and `public.users.email` column assume email is present and real. Need to decide: accept relay emails as-is, or require real email?
2. **Provider credentials management**: Where to store OAuth client IDs and secrets? Supabase dashboard config, Doppler, or `configure-auth.sh`?
3. **Button ordering**: Which provider appears first? GitHub (developer audience) vs Google (most familiar)?
4. **Signup page consolidation**: With unified OAuth, do we still need a separate signup page? Or merge into one auth page with magic-link + OAuth?
5. **Rate limiting**: Supabase handles OAuth rate limiting at the provider level, but should we add app-level rate limiting on the callback route?

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** The existing architecture is well-hardened but carries implicit assumptions that only email/OTP auth exists. Key risks: CSP `frame-src 'none'` blocks OAuth popups (mitigated by choosing redirect flow), Apple email suppression can cause NULL email in trigger, and `configure-auth.sh` needs provider enablement via Supabase Management API. The callback route's `exchangeCodeForSession` already handles PKCE -- low friction on the critical path.

### Product (CPO)

**Summary:** P1 has 6 unstarted items and 0 external users -- timing question on conversion optimization. However, OAuth is table-stakes for a web platform targeting developers (GitHub SSO is expected). The T&C post-auth redirect works as-is for OAuth users. The existing post-auth routing chain (callback -> accept-terms -> setup-key -> dashboard) is provider-agnostic and requires no changes.

### Legal (CLO)

**Summary:** 5 legal documents need updates: Privacy Policy, T&C, Cookie Policy, GDPR Policy, and Data Protection Disclosure. OAuth introduces new personal data categories not currently disclosed (provider user IDs, display names, avatars, OAuth tokens). Each provider has specific data processing requirements. Apple's private relay email feature has GDPR implications for data minimization.

### Marketing (CMO)

**Summary:** Provider button brand guidelines (Google, Apple, GitHub, Microsoft) override Soleur visual identity -- each has strict sizing, spacing, and color requirements. GitHub OAuth signals "developer tool" (fits audience). Reduced signup friction is a messaging opportunity but the feature itself is table-stakes, not differentiating. Privacy policy gaps must be closed before launch.

## Capability Gaps

| Gap | Domain | Why Needed |
|-----|--------|------------|
| Legal documents not updated for OAuth data categories | Legal | Privacy Policy, T&C, Cookie Policy, GDPR Policy, and Data Protection Disclosure must disclose new data from OAuth providers before launch |
| Provider button brand compliance | Marketing | Google, Apple, GitHub, Microsoft each have strict brand guidelines for sign-in buttons that must be followed |
| Apple email relay handling | Engineering | `public.users.email NOT NULL` constraint and downstream code assume real email. Apple's private relay needs a design decision |
