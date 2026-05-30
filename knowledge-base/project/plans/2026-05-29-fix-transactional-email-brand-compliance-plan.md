---
title: Bring outbound transactional + auth emails into brand-guide compliance
type: fix
date: 2026-05-29
branch: feat-one-shot-brand-transactional-emails
lane: single-domain
brand_survival_threshold: aggregate pattern
status: planned
---

# 🐛 fix: Transactional + auth email brand compliance (gold CTAs, sharp corners)

## Enhancement Summary

**Deepened on:** 2026-05-29
**Sections enhanced:** Research Reconciliation, Research Insights (new), Risks & Mitigations (precedent-diff)

### Key Improvements
1. **Live-verified the Supabase Management API contract** — `mailer_templates_confirmation_content` + `mailer_subjects_confirmation` confirmed present (type `string`) in `api.supabase.com/api/v1-json`, removing the dominant paraphrase-without-verification risk for the configure-auth.sh wiring.
2. **Confirmed the confirmation-email variable is `{{ .ConfirmationURL }}`** (a link CTA), not `{{ .Token }}` (an OTP code) — sets confirmation.html's structure: mirror magic-link's chrome but use a gold `<a>` button, not a code box.
3. **Verify-the-negative pass executed** — 5 `#2563eb` / 0 `#1d4ed8` in notifications.ts; 0 Resend `tags:` (DSAR untracked-link + no-new-tracking claims hold); magic-link's only `<a>` is the footer link, so line 30 is a `<div>` code box (ARGUMENTS mis-labeled it an `<a>`).

### New Considerations Discovered
- The only table-based email precedent in the repo is `magic-link.html` itself; confirmation.html should adopt its `role="presentation"` table chrome verbatim (correct precedent, no novel pattern).
- Existing `test/notifications.test.ts` + `test/dsar-notifications.test.ts` do NOT assert on `#2563eb` (greped) — the CTA recolor will not break them, so no edits to those files are needed (Files-to-Edit note remains conditional but resolves to "no change").

## Overview

Every outbound Soleur email currently ships off-brand CTAs. Three surfaces:

- **(A)** `apps/web-platform/server/notifications.ts` — five inline-HTML email templates whose CTA buttons use off-brand blue `#2563eb` with white text (`#fff`), are **left-aligned**, and have rounded `border-radius: 6px` corners.
- **(B)** `apps/web-platform/supabase/templates/magic-link.html` — dark-branded, but its `{{ .Token }}` display box (~line 30) uses a near-white `#262626` fill with `#ffffff` text and `border-radius: 8px`. (Note: this is a **code-display box**, not an `<a>` button — see Research Reconciliation.)
- **(C)** The Supabase **signup confirmation** email uses Supabase's default unbranded template (plain blue link). No `confirmation.html` exists in `apps/web-platform/supabase/templates/` — only `magic-link.html`. A branded `confirmation.html` must be created and wired into `configure-auth.sh`.

The fix replaces all off-brand CTA styling with the Solar Forge **gold-on-forge-ink** contract (solid `#C9A962` base, `#1A1612` text, `0px` corners, centered), introduces one shared `BRAND_EMAIL_COLORS` constant in `notifications.ts`, and adds regression tests.

This is the email follow-on to an invite-acceptance **web-page** brand fix that merged earlier today. That PR is **context only** — not a work target here.

## Brand Contract (verified against `knowledge-base/marketing/brand-guide.md`)

| Token | Hex | Brand-guide line | Use |
|---|---|---|---|
| Gold base (solid) | `#C9A962` | 186, 226 | CTA `background-color` — reliable solid base (email clients strip gradients) |
| Gold gradient start | `#D4B36A` | 187, 229 | Optional `background-image: linear-gradient(135deg,#d4b36a,#b8923e)` layer for capable clients |
| Gold gradient end | `#B8923E` | 188, 230 | Gradient end stop |
| Forge ink (text-on-accent) | `#1A1612` | 210, 213, 245 | CTA text. Forge-ink-on-gold = 8.00:1 → 6.18:1 (AA). **Never white-on-gold — fails AA** (line 213). |
| Corners | `0px` | 266 | "Sharp (0px border-radius) in both palettes … No rounded corners." |

**Email-specific constraint (from ARGUMENTS, consistent with brand-guide line 195 "never raw hex in components"):** Email HTML CANNOT use the `soleur-*` Tailwind CSS-variable tokens — email clients do not resolve CSS custom properties. Emails use **literal brand hex inline** (the explicit, documented exception to the "never raw hex" component rule). Set `background-color: #C9A962` as the solid base; optionally layer `background-image: linear-gradient(135deg,#d4b36a,#b8923e)` for capable clients (clients that strip it fall back to the solid base).

## Research Reconciliation — Spec vs. Codebase

| Claim (from ARGUMENTS) | Reality (verified) | Plan response |
|---|---|---|
| notifications.ts five CTAs at ~lines 198/294/333/368/406 use `#2563eb` + white, left-aligned, `border-radius: 6px` | **Confirmed verbatim** — `grep -nE '#(2563eb\|1d4ed8)'` returns exactly those 5 lines; each is `background: #2563eb; color: #fff; … border-radius: 6px;` with no centering wrapper. No `#1d4ed8` present anywhere. | Fix all 5; introduce shared `BRAND_EMAIL_COLORS`. |
| magic-link.html CTA `<a>` at ~line 30-31 is a WHITE button (`background-color:#ffffff;color:#000000`) | **Partially off** — line 30 is a **`<div>` code-display box** (`{{ .Token }}` is an OTP code, not a link), styled `background-color:#262626;color:#ffffff;…border-radius:8px`. It is NOT `#ffffff` background and NOT an `<a>`. | Re-brand the code box to the gold-on-forge-ink contract + `0px` corners. The verification "magic-link CTA no longer `#ffffff` background" holds trivially (it never was) AND we additionally remove the off-brand `#262626`/`#ffffff` styling. Test asserts gold-present + `0px` + no white-CTA, all true post-fix. |
| confirmation.html must mirror magic-link's structure with a gold CTA | magic-link displays an **OTP code** (`{{ .Token }}`); the confirmation email uses **`{{ .ConfirmationURL }}`** (a link — verified against supabase/auth README). | confirmation.html mirrors magic-link's dark **table layout + header/footer** but the center cell is a gold `<a>` **button** wrapping `{{ .ConfirmationURL }}`, not a code box. |
| Wire confirmation into configure-auth.sh; magic-link registered via Management API | **Confirmed** — `configure-auth.sh:21-28` reads `magic-link.html` into `$MAGIC_LINK_TEMPLATE` and PATCHes `mailer_templates_magic_link_content` + `mailer_subjects_magic_link` to `api.supabase.com/v1/projects/$PROJECT_REF/config/auth` (lines 32-54). | Add a `CONFIRMATION_TEMPLATE` read + two new jq keys: `mailer_templates_confirmation_content` + `mailer_subjects_confirmation` (field names **verified against the live Supabase Management API OpenAPI spec** `https://api.supabase.com/api/v1-json` — both exist, type `string`). |
| Test runner is vitest | **Confirmed** — `apps/web-platform/vitest.config.ts`; `unit` project (env `node`) globs `test/**/*.test.ts`. Existing `test/notifications.test.ts` + `test/dsar-notifications.test.ts` mock Resend and assert on `mockResendSend.mock.calls[0][0].html`. | New test `test/email-brand-compliance.test.ts` lands in the `unit` node project; reuses the captured-HTML mock pattern for notifications.ts + fs-reads the two `.html` templates for source-scan. |

## User-Brand Impact

**If this lands broken, the user experiences:** an outbound transactional/auth email (signup confirmation, invite, DSAR export, agent-needs-input) that renders with an unreadable CTA (e.g. forge-ink text on a non-rendering background, or a gradient that collapses to no background) — at worst an invisible or illegible "Confirm"/"Accept" button that blocks signup or invite acceptance.

**If this leaks, the user's data is exposed via:** N/A — this is presentation-only styling of already-existing emails. No new data, recipients, links, or tracking are introduced. The DSAR emails retain their existing PII-free subject/preview-text and untracked-link contract (notifications.ts:218-224); this plan changes only CTA color/alignment/corners, not link content or `tags`.

**Brand-survival threshold:** aggregate pattern — off-brand emails are a consistency/polish concern across the email surface, not a single-user breach. (No per-PR CPO sign-off required.)

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — No off-brand blue remains in notifications.ts.** `grep -nE '#(2563eb|1d4ed8)' apps/web-platform/server/notifications.ts` returns nothing (exit non-zero / empty). (Host `grep` is ugrep; this is plain `grep -nE`, no `-z`.)
- [x] **AC2 — Shared constant exists and is the single source.** `notifications.ts` defines one `BRAND_EMAIL_COLORS` (or equivalently-named) constant carrying the gold base + forge-ink + gradient literals; all five CTAs reference it (no repeated `#C9A962`/`#1A1612` literals inline in the five template strings). Verify: the five gold literals appear in the constant definition, and each template interpolates the constant fields.
- [x] **AC3 — All five notifications.ts CTAs are gold + forge-ink + 0px + centered.** For each of the 5 senders (agent-needs-input, dsar-ready, dsar-failed, invite, invite-accepted), the rendered `<a>` has `background-color:#C9A962` (solid base), `color:#1A1612`, `border-radius:0` (or `0px`), and is wrapped in a `text-align:center` container (or a centered `<td>`). Verified by the captured-HTML regression test (AC8).
- [x] **AC4 — Invite CTA uses the gold hex.** The `sendInviteEmail` rendered HTML contains `#C9A962` on the "Accept invitation" `<a>` and contains no `#2563eb`. (Originally-reported case.)
- [x] **AC5 — magic-link.html re-branded.** `apps/web-platform/supabase/templates/magic-link.html` token box no longer uses `background-color:#ffffff` (it never did — assertion holds trivially) AND no longer uses the off-brand `#262626` fill / `#ffffff` text; it now uses `#C9A962` background + `#1A1612` text + `border-radius:0`. The existing centered table layout (`<td align="center">`) is preserved.
- [x] **AC6 — confirmation.html created and branded.** `apps/web-platform/supabase/templates/confirmation.html` exists, mirrors magic-link's dark table structure (`background-color:#0a0a0a` outer, `#171717` card), contains a gold `<a>` button (`background-color:#C9A962`, `color:#1A1612`, `border-radius:0`) wrapping `{{ .ConfirmationURL }}`, and contains no `#2563eb`/`#ffffff`-background CTA.
- [x] **AC7 — confirmation wired into configure-auth.sh.** `configure-auth.sh` reads `confirmation.html`, fails loudly if absent (mirroring the existing `magic-link.html` guard at lines 23-26), and the jq PATCH body includes `mailer_templates_confirmation_content` + `mailer_subjects_confirmation`. Verify the script still parses: `bash -n apps/web-platform/supabase/scripts/configure-auth.sh` exits 0.
- [x] **AC8 — Regression test passes.** `test/email-brand-compliance.test.ts`: (a) captures each of the 5 notifications.ts emails' HTML via the existing Resend mock and asserts gold-present / no-`#2563eb` / centered-wrapper; (b) fs-reads `magic-link.html` + `confirmation.html` and asserts gold-hex-present, no white-CTA (`#ffffff` background), `border-radius:0`. Run: `cd apps/web-platform && ./node_modules/.bin/vitest run test/email-brand-compliance.test.ts` → all green.
- [x] **AC9 — Existing email tests still pass.** `cd apps/web-platform && ./node_modules/.bin/vitest run test/notifications.test.ts test/dsar-notifications.test.ts` → green (the CTA-color change must not break their existing assertions; if any assert on `#2563eb`, update them in this PR).
- [x] **AC10 — Typecheck clean.** `cd apps/web-platform && npx tsc --noEmit` exits 0 (the new constant + edits introduce no type errors).

### Post-merge (operator / automatable)

- [x] **AC11 — Templates applied to prod Supabase.** `configure-auth.sh` is run against the **prod** Supabase project so the new `confirmation.html` + re-branded `magic-link.html` take effect. **Automation: feasible** via Supabase MCP or a one-shot CI step — see Observability + the post-merge note below. This does NOT block the PR (template files + script change are the deliverable; applying is a config push). Verify by triggering a real signup and confirming the gold-CTA confirmation email renders.

## Implementation Phases

### Phase 1 — Shared color constant + five notifications.ts CTAs (RED→GREEN)

1. **Write the failing test first** (`cq-write-failing-tests-before`): create `apps/web-platform/test/email-brand-compliance.test.ts` covering AC3/AC4/AC8(a). Mirror the Resend-mock + `mockResendSend.mock.calls[0][0].html` capture pattern from `test/notifications.test.ts` / `test/dsar-notifications.test.ts`. Drive all 5 senders with synthesized fixture args (no real PII — `cq-test-fixtures-synthesized-only`).
2. Add a module-level constant near the top of `notifications.ts`:
   ```ts
   // Solar Forge email CTA palette — literal brand hex (email clients do
   // not resolve the soleur-* CSS custom properties; see brand-guide.md
   // line 195 exception + line 213 "never white on gold; fails AA").
   const BRAND_EMAIL_COLORS = {
     ctaBackground: "#C9A962",                                  // solid base (brand-guide:186,226)
     ctaGradient: "linear-gradient(135deg, #D4B36A, #B8923E)",  // capable-client layer (187/188)
     ctaText: "#1A1612",                                        // forge ink, 8:1 on gold (210/213/245)
   } as const;
   ```
3. Replace each of the five CTA `<a>` blocks. Pattern per CTA (centered + gold + forge-ink + 0px):
   ```html
   <div style="text-align: center; margin: 8px 0 0;">
     <a href="${url}" style="display: inline-block; padding: 12px 24px; background-color: ${BRAND_EMAIL_COLORS.ctaBackground}; background-image: ${BRAND_EMAIL_COLORS.ctaGradient}; color: ${BRAND_EMAIL_COLORS.ctaText}; text-decoration: none; border-radius: 0; font-weight: 600;">Open conversation</a>
   </div>
   ```
   Apply to: agent-needs-input (line ~198), dsar-ready (~294), dsar-failed (~333), invite (~368), invite-accepted (~406). Keep each CTA's link variable + label text unchanged. **Do not** alter DSAR PII-free subject/preview-text or add Resend `tags` (preserves notifications.ts:218-224 contract).
4. Run AC1 grep + AC8(a)/AC9/AC10. Update any existing test in `notifications.test.ts`/`dsar-notifications.test.ts` that asserts on `#2563eb` (grep them first).

### Phase 2 — magic-link.html re-brand (GREEN extends test)

1. Extend the test with AC5 + AC8(b) fs-scan for `magic-link.html` (RED first).
2. Edit `magic-link.html` line ~30 code box: `background-color:#262626;color:#ffffff;…border-radius:8px` → `background-color:#C9A962;color:#1A1612;…border-radius:0`. Optionally layer `background-image:linear-gradient(135deg,#d4b36a,#b8923e);`. Preserve the surrounding `<td align="center">` (line 29) and monospace/letter-spacing for code legibility. Note: forge-ink `#1A1612` on `#C9A962` is the AA-passing pair for the OTP digits.

### Phase 3 — confirmation.html create + wire (GREEN extends test)

1. Extend the test with AC6 fs-scan for `confirmation.html` (RED first).
2. Create `apps/web-platform/supabase/templates/confirmation.html` mirroring magic-link's dark table chrome (outer `#0a0a0a`, card `#171717`, "Soleur" header, footer with `soleur.ai`), but the center cell is a gold CTA button:
   ```html
   <td align="center" style="padding-bottom:24px;">
     <a href="{{ .ConfirmationURL }}" style="display:inline-block;background-color:#C9A962;background-image:linear-gradient(135deg,#d4b36a,#b8923e);color:#1A1612;font-size:16px;font-weight:600;padding:16px 32px;border-radius:0;text-decoration:none;">Confirm your email</a>
   </td>
   ```
   Body copy: "Confirm your email to finish setting up your Soleur account." Use `{{ .ConfirmationURL }}` (NOT `{{ .Token }}` — verified). Set `<meta name="color-scheme" content="dark">` like magic-link.
3. Wire into `configure-auth.sh`:
   - After the `MAGIC_LINK_TEMPLATE` read (line 28), add a `CONFIRMATION_TEMPLATE` read with the same `[[ ! -f ... ]]` guard pattern (lines 23-26) for `$SCRIPT_DIR/../templates/confirmation.html`.
   - In the jq body (lines 36-54): add `--arg confirmation "$CONFIRMATION_TEMPLATE"` and two keys: `"mailer_subjects_confirmation": "Confirm your Soleur account"` and `"mailer_templates_confirmation_content": $confirmation`. (Field names verified against `api.supabase.com/api/v1-json`.)
   - Verify `bash -n` (AC7).

### Phase 4 — Full verification

Run AC1, AC7 (`bash -n`), AC8, AC9, AC10 together. Confirm no `#2563eb`/`#1d4ed8` anywhere in notifications.ts; confirm both templates pass the fs-scan.

## Files to Edit

- `apps/web-platform/server/notifications.ts` — add `BRAND_EMAIL_COLORS`; re-style 5 CTAs (lines ~198, ~294, ~333, ~368, ~406).
- `apps/web-platform/supabase/templates/magic-link.html` — re-brand code box (line ~30).
- `apps/web-platform/supabase/scripts/configure-auth.sh` — read + register `confirmation.html`.
- `apps/web-platform/test/notifications.test.ts` / `test/dsar-notifications.test.ts` — only IF they assert on `#2563eb` (grep first; likely no change).

## Files to Create

- `apps/web-platform/supabase/templates/confirmation.html` — branded signup confirmation email.
- `apps/web-platform/test/email-brand-compliance.test.ts` — regression test.

## Open Code-Review Overlap

None. (No open `code-review`-labeled issues were folded; verified at plan time the touched files are not named in an open scope-out — this is a fresh single-domain styling fix.)

## Observability

```yaml
liveness_signal:
  what: Resend email send result (error object on the resend.emails.send() call)
  cadence: per outbound email (event-driven, not scheduled)
  alert_target: existing Sentry mirror via reportSilentFallback (notifications.ts:376, 413) for invite/accept; log.error for the rest
  configured_in: apps/web-platform/server/notifications.ts (unchanged by this plan)
error_reporting:
  destination: Sentry (reportSilentFallback) + structured pino log.error
  fail_loud: yes — existing behavior preserved; this plan changes only CTA HTML styling, not the send/error path
failure_modes:
  - mode: CTA gradient strips in a client and solid base also fails to render
    detection: visual — caught by AC11 real-signup render check post-merge
    alert_route: none automated (presentation-only); operator visual verify
  - mode: confirmation.html not applied to prod (configure-auth.sh not re-run)
    detection: real signup still shows default blue link
    alert_route: AC11 post-merge verification (signup smoke)
  - mode: supabase rejects confirmation template PATCH (bad field name)
    detection: configure-auth.sh exits non-zero with HTTP code + body (lines 59-65 pattern)
    alert_route: CI step / operator sees non-zero exit
logs:
  where: pino structured logs (notifications child logger) + Sentry
  retention: existing platform retention (unchanged)
discoverability_test:
  command: cd apps/web-platform && ./node_modules/.bin/vitest run test/email-brand-compliance.test.ts && grep -nE '#(2563eb|1d4ed8)' server/notifications.ts; echo "exit=$?"
  expected_output: vitest all-green; grep prints nothing; exit=1 (no matches)
```

## Post-Merge Apply (AC11 detail)

Applying templates to prod requires running `configure-auth.sh` against the prod Supabase project with `SUPABASE_ACCESS_TOKEN` + `PROJECT_REF` + `RESEND_API_KEY` (read-only secret fetch from Doppler). **Automation feasibility:** the Supabase MCP server (`mcp__plugin_supabase_supabase__*`) or a one-shot `gh workflow run` step can push the auth config without an interactive operator. The PR ships the template files + script change (the reviewable deliverable); the config push is a single post-merge automatable action and does NOT block PR-ready. Per `hr-all-infrastructure-provisioning-servers` this is config-push, not server provisioning — no Terraform root is introduced (Supabase auth config is managed via the existing `configure-auth.sh` Management-API script, the established pattern in this repo).

## Domain Review

**Domains relevant:** Product (advisory)

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A

#### Findings

This modifies existing user-facing email surfaces (CTA color/alignment/corners) without adding new pages, flows, or interactive components — ADVISORY, not BLOCKING. No new file matches `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` (the two new files are `.html` email templates and a `.test.ts`). Running in pipeline (plan path provided as argument) → auto-accepted per Phase 2.5 Step 2. The brand contract is fully specified by `brand-guide.md`; no wireframes or copy review needed — the change applies an existing, AA-verified palette to existing copy.

## Test Scenarios

1. Each of the 5 notifications.ts senders → captured HTML has `#C9A962` + `#1A1612` + `border-radius:0` + a `text-align:center` wrapper; no `#2563eb`.
2. Invite email specifically → `#C9A962` present, `#2563eb` absent (AC4).
3. `magic-link.html` fs-scan → `#C9A962` present, `#ffffff`-background absent, `#262626` absent, `border-radius:0` present.
4. `confirmation.html` fs-scan → exists, `{{ .ConfirmationURL }}` present, `#C9A962` present, `border-radius:0` present, no `#2563eb`.
5. `bash -n configure-auth.sh` → exit 0; script body contains `mailer_templates_confirmation_content` + `mailer_subjects_confirmation`.
6. `grep -nE '#(2563eb|1d4ed8)' server/notifications.ts` → empty (AC1).

## Research Insights

### Email-client CTA rendering (best practices)

- **Solid `background-color` is the load-bearing layer; gradient is enhancement.** Outlook (Word rendering engine), older Gmail, and many mobile clients strip `background-image: linear-gradient(...)`. Always set `background-color: #C9A962` so a stripped gradient falls back to the AA-passing solid gold. The plan's CTA pattern does this (solid base first, gradient layered).
- **`display: inline-block` + explicit `padding` is the most portable button shape** for a non-table `<a>` (the notifications.ts pattern). Outlook ignores `padding` on inline elements in some versions; the existing notifications.ts emails already accept this minor degradation (they shipped with `display: inline-block; padding: 12px 24px`), and this fix preserves that shape — only color/corners/alignment change, so portability is unchanged from the already-shipping baseline.
- **Centering a non-table `<a>`:** wrapping in `<div style="text-align:center">` is the lowest-risk centering for inline-block buttons across clients (vs. `margin:auto`, which needs a block-level width). The `.html` Supabase templates already center via `<td align="center">` — keep that.
- **Forge-ink on gold is the only AA pairing** — verified in brand-guide.md (8.00:1 → 6.18:1 across the gradient; line 245). No client-rendering concern changes this; do not revert to white text to "improve contrast."

### Verified API / variable facts (load-bearing)

```text
$ curl -s https://api.supabase.com/api/v1-json | tr ',' '\n' | grep -iE 'mailer_(templates|subjects)_confirmation'
"mailer_subjects_confirmation":{"type":"string"
"mailer_templates_confirmation_content":{"type":"string"
# Confirmation template var is {{ .ConfirmationURL }} (supabase/auth README), not {{ .Token }}.
```

## Risks & Mitigations (Precedent-Diff)

- **Pattern-bound behavior: dark table-based branded email template.** Precedent: `apps/web-platform/supabase/templates/magic-link.html` (the only `role="presentation"` table email in the repo). confirmation.html adopts its chrome (outer `#0a0a0a`, card `#171717`, "Soleur" header, `soleur.ai` footer, `<meta name="color-scheme" content="dark">`) verbatim, diverging only in the center cell (gold `<a>` button vs. OTP `<div>`). **No novel pattern** — this is a direct precedent adoption, low review risk.
- **Risk: configure-auth.sh PATCH rejected** if a field name is wrong. Mitigated by live-verifying both field names against the OpenAPI spec (above) and reusing the existing HTTP-code error-surfacing block (lines 59-65).
- **Risk: applying templates to prod is forgotten.** Mitigated by AC11 (post-merge automatable via Supabase MCP / CI step) + the explicit signup-render verification.

## Sharp Edges

- The magic-link "CTA" is a **`{{ .Token }}` OTP code-display `<div>`**, not an `<a>` link — the ARGUMENTS described it as a white `<a>` button. The current fill is `#262626`/`#ffffff` (not `#ffffff` background). The "no longer `#ffffff` background" verification passes trivially; the substantive fix is re-branding `#262626`→`#C9A962` and `#ffffff`→`#1A1612`. Don't search for a non-existent `<a>` on that line.
- The confirmation email's variable is **`{{ .ConfirmationURL }}`** (a link), NOT `{{ .Token }}` (verified against supabase/auth README). confirmation.html mirrors magic-link's **chrome** but uses a gold `<a>` button, not a code box.
- Supabase config field names are **`mailer_templates_confirmation_content`** + **`mailer_subjects_confirmation`** — verified against the live Management API OpenAPI spec (`api.supabase.com/api/v1-json`), both type `string`. Do not paraphrase these.
- Email clients strip CSS gradients — `background-color: #C9A962` MUST be the load-bearing solid base; `background-image: linear-gradient(...)` is a progressive-enhancement layer only. Never rely on the gradient alone.
- Forge-ink-on-gold is the **only** AA-passing pairing (8.00:1→6.18:1); white-on-gold fails AA per brand-guide line 213. Do not "fix" the gold CTA by reverting text to white.
- A plan whose `## User-Brand Impact` section is empty, contains only TBD/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above; threshold = aggregate pattern.)
- Host `grep` is ugrep — all verification greps use plain `grep -nE` (no `-z`). If a `\0`-delimited scan is ever needed, use `tr '\0' '\n' | grep`.

## Alternative Approaches Considered

| Approach | Why not chosen |
|---|---|
| Extract a shared HTML email-layout helper for all 5 notifications.ts emails | Out of scope (YAGNI) — the ask is CTA brand compliance, not template refactor. A shared `BRAND_EMAIL_COLORS` constant is the minimal single-source-of-truth that satisfies the requirement without restructuring 5 working templates. |
| Server-render the gradient as an image (bulletproof gold button) | Over-engineering for a styling fix; `background-color` solid base is the documented reliable fallback. No deferral issue needed. |
| Use a `<table>`-cell-button MSO-bulletproof pattern in notifications.ts | The existing notifications.ts emails are `<div>`-based, not table-based; wrapping each `<a>` in a `text-align:center` container matches the existing structure and satisfies the centering requirement with minimal diff. The `.html` Supabase templates already use tables. |
