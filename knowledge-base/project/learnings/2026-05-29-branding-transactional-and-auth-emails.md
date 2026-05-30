---
title: "Branding transactional + auth emails — literal hex, gradient-over-solid, Supabase templates"
date: 2026-05-29
category: best-practices
module: apps/web-platform/server/notifications.ts, apps/web-platform/supabase/templates
tags: [email, brand-guide, solar-forge, supabase-auth, resend, css, accessibility]
---

# Learning: branding transactional + auth emails

## Problem

Soleur's invite web page shipped off-brand (blue `#2563eb` CTA) — and the same
problem existed on EVERY outbound email: the 5 Resend templates in
`notifications.ts`, the Supabase magic-link OTP box, AND the signup confirmation
email (which used Supabase's unbranded default). None followed the Solar Forge
brand guide. The web-page fix (PR #4631) did not cover emails.

## Solution — the email-branding contract

Email HTML is a DIFFERENT surface from React components. Key constraints:

1. **Literal hex, never design tokens.** Email clients do NOT resolve CSS custom
   properties (`var(--soleur-*)`) or Tailwind classes. The brand guide's "never
   raw hex in components" rule explicitly EXCEPTS email — inline literal hex IS
   the correct, only-portable form. Centralize via one shared constant
   (`BRAND_EMAIL_COLORS` / `EMAIL_CTA_STYLE` in `notifications.ts`) so the 5
   templates share a single source.
2. **Solid `background-color` is load-bearing; gradient is enhancement.** Outlook
   (Word engine) and many clients strip `background-image: linear-gradient(...)`.
   Always set `background-color: #C9A962` (solid gold) first, then layer the
   gradient. A stripped gradient falls back to the AA-passing solid.
3. **Forge-ink on gold, NEVER white.** `color: #1A1612` on gold is the only
   AA-passing pair (8.00:1→6.18:1, brand-guide.md:213). White-on-gold fails AA.
4. **Sharp 0px corners** (`border-radius: 0`) per the brand guide.
5. **Center non-table `<a>` CTAs** by wrapping in `<div style="text-align:center">`
   (most portable for inline-block buttons). Table-based templates already center
   via `<td align="center">`.

## Supabase auth email wiring (the non-obvious part)

- Auth email templates (magic-link, **confirmation**, recovery, etc.) are NOT in
  `config.toml`. They are uploaded to the Supabase project via
  `apps/web-platform/supabase/scripts/configure-auth.sh`, which PATCHes the
  Management API (`/v1/projects/$REF/config/auth`) with
  `mailer_templates_<type>_content` + `mailer_subjects_<type>` keys (field names
  verified live against `api.supabase.com/api/v1-json`).
- The **signup confirmation** email uses `{{ .ConfirmationURL }}` (a link → gold
  `<a>` button), NOT `{{ .Token }}` (magic-link's OTP code box). A repo template
  must be created at `supabase/templates/confirmation.html` AND wired into
  `configure-auth.sh`; without the wiring, Supabase serves its default unbranded
  template.
- Applying templates to prod requires RUNNING `configure-auth.sh` against the prod
  project (a post-merge config push) — the PR ships the files; the push is separate.

## Key Insight

The brand guide is one contract but THREE rendering surfaces — React components
(tokens), Resend HTML emails (literal hex, light theme), and Supabase auth
templates (literal hex, dark table theme). A brand fix on one surface does not
propagate to the others; enumerate all three when "brand X" is the ask. For
Soleur users: their own emails need the same literal-hex treatment against their
own brand-guide palette — design tokens cannot reach email.

## Session Errors

1. **Test omitted a required `expiresAt: Date` arg** to `sendDsarExportReadyEmail`,
   throwing before the send. Recovery: read the full signature. Prevention: read
   the complete sender signature before writing test invocations.
2. **Over-broad `not.toContain("#262626")`** would false-fail on the legitimate
   footer border. Recovery: narrowed to `not.toMatch(/background-color:\s*#262626/i)`.
   Prevention: scope negative color assertions to the specific CSS property.
