# Learning: Supabase `signInWithOtp` creates new users by default, even on the login page

## Problem
The login page called `supabase.auth.signInWithOtp({ email })` to send a magic link. Despite the method name suggesting "sign in" (existing users only), Supabase's default behavior is to **create a new user** if the email does not already exist. This meant:

1. A user who had never signed up could enter their email on the **login** page and get a valid magic link
2. The new user record would be created without T&C acceptance metadata, bypassing the signup flow's clickwrap checkbox entirely
3. The `tc_accepted_at` column would remain NULL, creating a compliance gap — the user has a live account but never agreed to the Terms & Conditions

This is a dual-purpose API footgun: the same function handles both "sign in existing user" and "sign up new user" depending on whether the email exists, with no warning to the caller.

## Solution
Pass `shouldCreateUser: false` in the OTP options on the login page:

```typescript
const { error } = await supabase.auth.signInWithOtp({
  email,
  options: {
    shouldCreateUser: false,
    emailRedirectTo: `${origin}/auth/callback`,
  },
});
```

With this flag, Supabase returns an error if the email is not already registered, and the login page displays a "no account found" message directing the user to the signup page. New user creation is now exclusively handled by the signup flow, which enforces T&C acceptance.

## Key Insight
Supabase's `signInWithOtp` is a dual-purpose function: it silently creates users unless explicitly told not to with `shouldCreateUser: false`. Any application with distinct signup and login flows **must** set this flag on the login path. Without it, the login page becomes an unguarded signup backdoor that skips whatever validation the signup page enforces (T&C acceptance, invite codes, waitlist checks, etc.). This is not documented prominently — it is a single line in the API reference, easy to miss during initial implementation.

## Related
- [supabase-trigger-boolean-cast-safety](2026-03-20-supabase-trigger-boolean-cast-safety.md) — the trigger that records T&C acceptance, which this bypass circumvented
- [supabase-silent-error-return-values](2026-03-20-supabase-silent-error-return-values.md) — another Supabase API behavior that silently does the wrong thing
- Issues: #889

## Tags
category: logic-errors
module: web-platform/auth
