---
title: Fix signup OAuth helper hint + GitHub redirect_uri recurrence audit
type: fix
date: 2026-05-04
requires_cpo_signoff: true
---

# Fix signup OAuth helper hint + GitHub redirect_uri recurrence audit

## Enhancement Summary

**Deepened on:** 2026-05-04
**Sections enhanced:** 5 (Phase 1 hint code, Phase 2 test scaffold, Phase 3 probe extension, Phase 5 #3187 scope, Sharp Edges)
**Research sources:** WebSearch (W3C ARIA22, MDN aria-live, Supabase OAuth docs, `actions/create-github-app-token` README), live curl probes against GitHub edge, repo grep of `apps/web-platform/test/` conventions, `vitest.config.ts` project layout, sibling test file `cancel-retention-modal.test.tsx`.

### Key Improvements

1. **Live-region pattern corrected.** Original Phase 1 prescribed conditional render of the hint (`{!tcAccepted && <p role="status" aria-live="polite">…</p>}`). Per W3C ARIA22 + MDN: a live region "must already exist in the DOM" and contain content changes — first-render injection of a live-region element is unreliable on most screen readers. Pattern updated: render the `role="status"` container unconditionally, swap the inner text content based on `tcAccepted`. Persistent region + content swap is the supported announcement pattern.
2. **`actions/create-github-app-token` input names corrected.** Original Sharp Edges section cited `app-id` + `private-key`; the actual input names per the v2 README are `app-id` (deprecated) / `client-id` (preferred) + `private-key`. Phase 5 reflects the modern `client-id` form.
3. **Test placement matches codebase convention.** Vitest `component` project picks up `test/**/*.test.tsx` under happy-dom; the existing flat `apps/web-platform/test/cancel-retention-modal.test.tsx` is the canonical sibling. Plan no longer suggests `apps/web-platform/test/auth/` (the only file there is `sentry-tag-coverage.test.ts`).
4. **Phase 5 deferral default reaffirmed with stronger reasoning.** `actions/create-github-app-token@v2` is a 1-step action and `prd.GITHUB_APP_PRIVATE_KEY` already exists in Doppler — the JWT-mint cost is genuinely small. BUT the load-bearing user-shape regression guard is Probe 3g (Phase 3); #3187 closes a strictly-stronger but lower-frequency drift class. Default decision remains **defer** unless GREEN-phase complexity budget is comfortable; folding in is a one-paragraph addendum, not a separate plan.
5. **Probe 3g shape clarification.** The Supabase end-to-end leg must NOT pass cookies between the Supabase 302-leg and the GitHub `-L` follow leg — captured as a Sharp Edge after research showed Supabase `/auth/v1/authorize` sets a transient `sb-` cookie that can change GitHub's response surface if persisted. (Already in the plan; deepen confirms.)

### New Considerations Discovered

- **Live-region announcement requires the region to pre-exist** — the conditional-render pattern (`{cond && <p role="status">…</p>}`) does NOT reliably trigger announcements on first render because the DOM mutation observer that screen readers use needs the region to be present before its content changes. Fix: always render the `<p role="status">` element; toggle the text inside.
- **`role="status"` is implicitly `aria-live="polite"` + `aria-atomic="true"`** — explicit `aria-live="polite"` is redundant. Keep `aria-live="polite"` for explicit-intent grep-ability and to insulate against future React changes that strip implicit ARIA; the redundancy is documentation, not functional.
- **Supabase OAuth flow is `Browser → /auth/v1/authorize → 302 to GitHub /login/oauth/authorize → consent → /auth/v1/callback → SITE_URL`.** Probe 3g exercises the first two legs with curl; the GitHub leg is what historically broke at the redirect_uri check. End-to-end probe via `curl --max-redirs 0` capture of the 302, then re-issue with `-L` against GitHub.
- **`actions/create-github-app-token` outputs `token` (installation access token), not a JWT** — for `gh api /app` (which needs JWT-as-app, not installation token), the JWT-mint must be done inline (e.g., `gh-app-jwt`-style tools) OR using a different endpoint. The action returns an installation access token suitable for `gh api /installation/repositories` but NOT directly for `gh api /app`. Phase 5's deferral decision must factor this — folding #3187 in is more than a 1-step action call.

## Overview

Two related signup-page issues, sharing a brand-impact framing (the first 60s of every new user's journey) and the same PR if Issue B yields a code change.

**Issue A — UX polish (code fix).** On `apps/web-platform/app/(auth)/signup/page.tsx`, the OAuth provider buttons (Google, Apple, GitHub, Microsoft) and the "Send verification code" button render with `disabled` (Tailwind `disabled:opacity-50`) until the T&C checkbox is ticked. Users read the gray state as "OAuth is broken / Soleur ignores my click." Add a visible, accessible hint near the OAuth divider explaining the gating ("Accept the terms above to continue."), shown only while `!tcAccepted`. The native `disabled` attribute is already correctly set on each `<button>` (`components/auth/oauth-buttons.tsx:107`), so screen-reader semantics are correct — this is pure UX/affordance, not an a11y fix.

**Issue B — GitHub OAuth misconfig (config fix, audit).** A user reported GitHub returning *"The redirect_uri is not associated with this application"* when clicking "Continue with GitHub" on `https://app.soleur.ai/signup`. The captured authorize URL is the Supabase Flow A shape:

```
https://github.com/login/oauth/authorize
  ?client_id=Iv23li9p88M5ZxYv1b7V              # GitHub App `soleur-ai`
  &redirect_to=https%3A%2F%2Fapp.soleur.ai%2Fcallback
  &redirect_uri=https%3A%2F%2Fapi.soleur.ai%2Fauth%2Fv1%2Fcallback
  &response_type=code&scope=user%3Aemail&state=…
```

The `Iv23li…` prefix confirms a GitHub **App** (not a classic OAuth App). The merged precedent PR #3181 (4 h before this plan) shipped: a 3-URL synthetic probe on a 15-minute cron, an `oauth-probe-contract.test.ts` sentinel test, a closure gate, and the `github-app-callback-audit.md` runbook. PR #3181 itself observed the same self-healing pattern — symptom irreproducible after self-heal — and shipped its guardrails on that basis (`Closes #3183`).

Live evidence at plan time (2026-05-04T13:13Z):

```
[github_resolve]     http=200 err_match=0 suspended=0 pos_proof=2
[supabase_custom]    http=200 err_match=0 suspended=0 pos_proof=2
[supabase_canonical] http=200 err_match=0 suspended=0 pos_proof=2

# User-captured URL shape (with redirect_to + redirect_uri):
USER-CAPTURED-URL-SHAPE: http=200 err_match=0 pos_proof=2
<title>Sign in to GitHub · GitHub</title>
```

All three callbacks pass at the GitHub edge **right now**, including the user's exact authorize URL shape. The most recent scheduled probe runs (12:46Z, 13:10Z) are green; the 07:25Z run on the same day failed (separate cause — see #3187 trail). This plan therefore treats Issue B not as "fix the misconfig" (state is currently healthy) but as **"audit the recurrence and close the gate-detection gap that let the user hit the error inside the supposedly-protected window."** Per `wg-when-fixing-a-workflow-gates-detection`, the case that exposed the gap is **this** user report, and remediation must extend the gate to detect the failure mode that produced it.

## User-Brand Impact

- **If this lands broken, the user experiences:** for Issue A, a mute "click does nothing" gray state on the very first action of the very first user session (read as broken auth before they have an account); for Issue B, GitHub-rendered "redirect_uri is not associated" with no path back into the product, killing connect-repo/sign-up dead until manual escape — auth is the brand-truth surface.
- **If this leaks, the user's [data / workflow / money] is exposed via:** N/A for the UX hint; for Issue B the OAuth surface is already the documented attack surface — no new exposure beyond the existing GitHub App. Risk is unavailability, not confidentiality.
- **Brand-survival threshold:** `single-user incident`. Carried forward from PR #3181 / #3183 framing — one repro on a public Loom equals "Soleur's auth is broken" and there is no recovery from a public-comparison brand hit during prelaunch. CPO sign-off required at plan time before `/work`; `user-impact-reviewer` invoked at review time.

## Reproduction snapshot at plan time

| Probe | Result |
| --- | --- |
| `curl …/login/oauth/authorize?client_id=Iv23…&redirect_uri=app.soleur.ai/api/auth/github-resolve/callback` | HTTP 200, `err_match=0`, `pos_proof=2` |
| `curl …/login/oauth/authorize?client_id=Iv23…&redirect_uri=api.soleur.ai/auth/v1/callback` | HTTP 200, `err_match=0`, `pos_proof=2` |
| `curl …/login/oauth/authorize?client_id=Iv23…&redirect_uri=ifsccnjhymdmidffkzhl.supabase.co/auth/v1/callback` | HTTP 200, `err_match=0`, `pos_proof=2` |
| `curl …` with the user's exact captured URL (with `redirect_to` + `redirect_uri`) | HTTP 200, `err_match=0`, `pos_proof=2` |
| `dig CNAME api.soleur.ai +short` | `ifsccnjhymdmidffkzhl.supabase.co.` ✓ |
| Doppler `prd.GITHUB_CLIENT_ID` | `Iv23li9p88M5ZxYv1b7V` ✓ |
| Doppler `prd.GITHUB_APP_ID` | `3261325` |
| Doppler `prd.NEXT_PUBLIC_APP_URL` | `https://app.soleur.ai` ✓ |
| Doppler `prd.NEXT_PUBLIC_SUPABASE_URL` | `https://api.soleur.ai` ✓ |
| `gh run list --workflow scheduled-oauth-probe.yml` last 5 | success, success, success, success, **failure 07:25Z**, success… |

The `dev` Doppler config does NOT have `GITHUB_CLIENT_ID` / `GITHUB_CLIENT_SECRET` / `NEXT_PUBLIC_GITHUB_APP_SLUG` — only `GITHUB_APP_ID` + `GITHUB_APP_PRIVATE_KEY`. This is consistent with the dev/prd-distinct-Supabase-projects rule (`hr-dev-prd-distinct-supabase-projects`); dev has no GitHub OAuth flow registered against the App, so there is no dev-vs-prd App-mis-binding risk for the prd `Iv23li…` client_id.

## Hypotheses (Issue B)

Updated at plan time against live evidence:

- **H_A — Self-healed transient drift (custom-domain CNAME flap during Supabase cert renewal).** Highest plausibility. The Supabase canonical fallback URL exists for exactly this reason; if it had been missing during the flap window, Flow A would have broken for ≤15 min until either Supabase finished the flap OR the operator re-added the URL. Demoted to *post-hoc reconstruction* — current state is healthy and the 15-min probe cadence cannot reconstruct a sub-window flap.
- **H_B — Operator silently re-added the URL between the user report and the probe at 13:10Z.** Plausible but not independently verifiable without the GitHub App audit log (which we do not currently capture). The closure-gate from PR #3181 is the durable defense for THIS hypothesis class.
- **H_C — Probe-cadence blind spot (15 min) AND body-grep run on a single redirect_uri shape.** The probe checks the three callback URLs in isolation but does NOT exercise the user's actual authorize URL shape (with `redirect_to` + `redirect_uri` together, which is what Supabase emits). If GitHub's response differs across these shapes (it does not at the moment of the live probe — we just confirmed), a future drift could pass the probe while failing the real flow. Promoted to **the gate-detection-gap remediation target.**
- **H_D — App-suspension or App-identity swap.** Probe greps `Application suspended`; live state shows neither sentinel matched and `pos_proof=2` (both `authenticity_token` and `Sign in to GitHub` present). Demoted.
- **H_E — Supabase project re-provisioning (canonical ref drifted).** `dig CNAME` matches the registered `ifsccnjhymdmidffkzhl` ref byte-for-byte. Demoted.

## Research Reconciliation — Spec vs. Codebase

| Claim from issue framing | Codebase / live reality | Plan response |
| --- | --- | --- |
| "GitHub App's registered callback URL list does not include `https://api.soleur.ai/auth/v1/callback`" | Live curl probe at 13:13Z returns `err_match=0` for that exact URL with the prd client_id — the URL **is** currently associated. | Re-frame Issue B as recurrence-audit + gate-detection-gap fix; do NOT prescribe a "re-add the URL" operator step as the primary remediation (the step is a no-op against current state). Operator audit remains in the post-merge checklist as a belt-and-suspenders confirmation per the runbook. |
| "this is a GitHub App, not a classic OAuth App" | Confirmed — `client_id` prefix `Iv23li…`, `prd.GITHUB_APP_ID = 3261325`, `prd.GITHUB_CLIENT_ID = Iv23li9p88M5ZxYv1b7V`. | No change. |
| "Use `gh api` for GitHub App config reads where possible" | `GET /app` requires JWT-mint with the App private key; `prd.GITHUB_APP_PRIVATE_KEY` is in Doppler. The PRIVATE_KEY-based audit is exactly what was deferred via #3187 (open follow-up from PR #3181). | Re-evaluate #3187 in this plan's scope. If the JWT-mint cost is shippable inside this PR's complexity budget, fold it in (closes #3187). If not, leave #3187 open and ship the user-shape probe extension. |
| "PR #3181 should have caught this — find out why" | PR #3181's probe runs every 15 min, body-greps the rejection sentinel, and probes each callback URL in isolation. It does NOT probe the user's actual authorize URL shape (Supabase emits `redirect_to` + `redirect_uri` combined). The probe was green at 11:27Z, failure at 07:25Z (separate root cause), green at 12:46Z. | Extend the probe to add a fourth check exercising the **Supabase-shaped** authorize URL (`/auth/v1/authorize?provider=github&redirect_to=…` end-to-end) and assert it lands on a GitHub authorize page that does NOT contain the rejection sentinel. This closes the H_C gap. |

## Acceptance Criteria

### Pre-merge (PR)

- [x] Issue A: signup page (`apps/web-platform/app/(auth)/signup/page.tsx`) renders a persistent `<p role="status" aria-live="polite">` element between `</form>` close and the OAuth divider. Text content is **"Accept the terms above to continue."** when `!tcAccepted` and an empty string when `tcAccepted === true`. (Persistent element + content swap — NOT conditional render of the live region. See Phase 1 for the live-region invariant.)
- [x] Issue A: hint uses `text-xs text-neutral-500 text-center min-h-[1rem]` so layout does not shift when text empties (CLS regression guard). Native `disabled` attribute on each OAuth button is unchanged — the hint is additive, not a replacement for `disabled`.
- [x] Issue A: Vitest component test `apps/web-platform/test/signup-helper-hint.test.tsx` (new) — see Phase 2 scaffold. Asserts: (a) `role="status"` element exists at first render, (b) text is the hint pre-tick, (c) text is empty post-tick, (d) all four OAuth buttons (`Google`, `Apple`, `GitHub`, `Microsoft`) are `disabled` pre-tick AND not disabled post-tick.
- [x] Issue B: scheduled OAuth probe extended with **Probe 3g** that exercises the Supabase-shaped authorize URL (`GET https://api.soleur.ai/auth/v1/authorize?provider=github&redirect_to=https%3A%2F%2Fapp.soleur.ai%2Fcallback`) end-to-end, follows the 302 to GitHub's `/login/oauth/authorize`, and asserts the **rendered HTML body** contains zero matches for `redirect_uri is not associated` and at least one positive-proof anchor. (Today's probe stops at the 302 destination host check — it does not follow into GitHub.) This is the H_C gap-detection fix.
- [x] Issue B: `oauth-probe-contract.test.ts` extended with a sentinel for the Supabase-shaped authorize URL pattern (`/auth/v1/authorize?provider=github&redirect_to=`) so the workflow's regex/grep on this shape is locked in lockstep with the same constant it asserts against.
- [ ] Issue B: retroactive comment on **#3183** (the case that exposed the gap) confirming (a) Probe 3g now exercises the user's exact URL shape, (b) live curl probes at $RUN_TIME show all four checks green, (c) workflow run URL of the first post-merge probe firing. This is the `wg-when-fixing-a-workflow-gates-detection` retroactive-application step.
- [x] All existing tests stay green (`bun test` from app root); no regressions in `oauth-probe-contract.test.ts` (11 tests).
- [x] `npx tsc --noEmit` clean.
- [ ] PR body uses `Ref #3183` (already closed) and `Ref #3187` (deferred drift-guard, may be `Closes #3187` if scope permits the JWT-mint audit — see Phase 4).
- [ ] Decision recorded inline in PR body: **fold or defer #3187** (JWT-mint App-identity drift-guard). If folded, also `Closes #3187`. If deferred, the deferral note in #3187 is updated with re-evaluation criteria from this PR.

### Post-merge (operator)

- [ ] Trigger `gh workflow run scheduled-oauth-probe.yml` and verify HTTP 200 + green probe output (per `wg-after-merging-a-pr-that-adds-or-modifies`).
- [ ] If Probe 3g surfaces drift, follow `knowledge-base/engineering/ops/runbooks/github-app-callback-audit.md` to audit the GitHub App callback URL textarea against the canonical 3-URL list. Per `hr-never-label-any-step-as-manual-without`, attempt **Playwright MCP first** to read the textarea before falling back to a manual UI handoff (the GitHub Apps settings page is auth-walled but Playwright can be driven through GitHub session cookies; only the actual textarea edit is genuinely manual due to CSRF protection — `gh api PATCH /apps/...` does NOT mutate callback URLs per the existing learning).
- [ ] If folding #3187 (JWT-mint drift-guard) is deferred, leave a comment on #3187 with the re-evaluation criteria from this PR's scope decision.

## Test Scenarios

### Issue A — UX hint visibility

- **Given** a fresh visit to `/signup` with `tcAccepted === false`, **when** the page renders, **then** a persistent `role="status"` live region exists in the DOM with text content "Accept the terms above to continue." positioned between the email form and the OAuth divider.
- **Given** the helper hint text is visible, **when** the user ticks the T&C checkbox (`tcAccepted` flips to `true`), **then** the `role="status"` element STAYS in the DOM (live-region pre-exists invariant) but its text content empties — screen readers announce the transition; sighted users see only the layout-reserved space (`min-h-[1rem]`).
- **Given** the user has not ticked the checkbox, **when** they attempt to click any OAuth provider button, **then** the button is `disabled` (regression guard — the hint is additive, not a replacement for `disabled`).
- **Given** the page is in `otpSent === true` state (post-OTP-send flow), **when** the page renders, **then** the helper hint is NOT in the DOM (the live region lives in the pre-OTP form branch only — the OAuth buttons are not shown in the OTP step, so no hint is needed).

### Issue B — Probe 3g (Supabase-shape end-to-end)

- **Given** the GitHub App config is healthy, **when** the scheduled probe runs Probe 3g, **then** the probe receives HTTP 200 from GitHub's authorize page AND the body contains zero matches for `redirect_uri is not associated` AND at least one positive-proof anchor (`authenticity_token` or `Sign in to GitHub`).
- **Given** a deliberately-broken redirect_uri (synthetic test against the contract test, not the live probe), **when** the contract test asserts the workflow's grep target, **then** the assertion catches a sentinel rewording in the workflow before it ships (locks the grep target to the constant in `oauth-probe-contract.test.ts`).
- **Given** Probe 3g surfaces `redirect_uri is not associated`, **when** the failure-mode handler runs, **then** the tracking issue body includes the **user-shape URL** verbatim (so operator can re-paste into the GitHub App textarea audit) AND the existing 3-URL block.

### Verification commands (consumed by `/soleur:qa`)

- **Browser:** Navigate to `https://app.soleur.ai/signup`, observe the helper hint visible, click Microsoft button (still disabled — `aria-disabled` should match), tick the T&C checkbox, observe the hint disappears, click "Continue with GitHub", observe redirect to `github.com` with no error page.
- **Probe verify:** `gh workflow run scheduled-oauth-probe.yml --ref main && sleep 30 && gh run list --workflow scheduled-oauth-probe.yml --limit 1 --json conclusion --jq '.[0].conclusion'` expects `success`.
- **Live curl (user-shape):** `curl --max-time 10 -L -s "https://github.com/login/oauth/authorize?client_id=Iv23li9p88M5ZxYv1b7V&redirect_to=https%3A%2F%2Fapp.soleur.ai%2Fcallback&redirect_uri=https%3A%2F%2Fapi.soleur.ai%2Fauth%2Fv1%2Fcallback&response_type=code&scope=user%3Aemail&state=qa" | grep -c 'redirect_uri is not associated'` expects `0`.

## Implementation Phases

### Phase 1 — Issue A: signup page helper hint (~10 LoC)

`apps/web-platform/app/(auth)/signup/page.tsx`: insert a `<p>` above the OAuth divider (between the form `</form>` close and the divider's `<div className="relative …">`), or alternatively below the T&C checkbox label inside the form. Decision: **above the divider** so it acts as the explainer for the gray OAuth buttons (and the gray "Send verification code" button is already inside the form, with its own affordance via `disabled` — the hint speaks to the OAuth row that is most ambiguous).

**Live-region invariant (corrected from initial draft):** the `role="status"` container MUST be rendered unconditionally, with the text content swapped based on `tcAccepted`. Conditional render of the live region (`{!cond && <p role="status">…</p>}`) does NOT reliably trigger screen-reader announcements on the FIRST render because most screen readers (NVDA, JAWS, VoiceOver) attach mutation observers to live regions that already exist in the DOM at announcement time. See [W3C WAI ARIA22](https://www.w3.org/WAI/WCAG22/Techniques/aria/ARIA22) and [MDN ARIA live regions](https://developer.mozilla.org/en-US/docs/Web/Accessibility/ARIA/Guides/Live_regions): "Including an aria-live attribute or a specialized live region role works as long as you add the attribute before the changes occur".

```tsx
<p
  role="status"
  aria-live="polite"
  className="text-center text-xs text-neutral-500 min-h-[1rem]"
>
  {!tcAccepted ? "Accept the terms above to continue." : ""}
</p>
```

Notes:

- `role="status"` is implicitly `aria-live="polite"` + `aria-atomic="true"`. The explicit `aria-live="polite"` here is documentation/grep-ability, not behaviorally required.
- `min-h-[1rem]` reserves vertical space so the layout does not jump when the text disappears (avoids CLS regression).
- The empty-string content in the accepted state is intentional — emptying the text is the announcement signal; some screen readers will speak nothing on transition-to-empty (acceptable: no announcement is the correct UX once the user has acted).
- Place the element **between** `</form>` close and the OAuth divider (`<div className="relative flex items-center gap-4">…</div>`), so it visually anchors the explanation to the OAuth row that is most ambiguous.

### Phase 2 — Issue A: component test

Create `apps/web-platform/test/signup-helper-hint.test.tsx` (flat path matches the codebase convention — `vitest.config.ts` `component` project picks up `test/**/*.test.tsx` under happy-dom; sibling reference: `cancel-retention-modal.test.tsx`).

Test scaffolding (mirrors `cancel-retention-modal.test.tsx` imports + `next/navigation` mock pattern):

```tsx
import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";

vi.mock("next/navigation", () => ({
  useRouter: () => ({ push: vi.fn(), refresh: vi.fn() }),
  useSearchParams: () => new URLSearchParams(),
}));
vi.mock("@/lib/supabase/client", () => ({
  createClient: () => ({ auth: { signInWithOtp: vi.fn(), signInWithOAuth: vi.fn() } }),
}));

import SignupPage from "@/app/(auth)/signup/page";
```

Assertions (with the live-region-pre-exists pattern in mind):

- The `role="status"` element exists in the DOM at first render (regardless of `tcAccepted`) — `expect(screen.getByRole("status")).toBeInTheDocument()`.
- Pre-tick: hint text is "Accept the terms above to continue." — `expect(screen.getByRole("status")).toHaveTextContent("Accept the terms above to continue.")`.
- Tick the T&C checkbox via `userEvent.click(screen.getByRole("checkbox"))`.
- Post-tick: hint text is empty — `expect(screen.getByRole("status")).toHaveTextContent("")`.
- Regression guard: every OAuth button has the `disabled` attribute pre-tick — `for (const label of ["Google", "Apple", "GitHub", "Microsoft"]) { expect(screen.getByRole("button", { name: new RegExp(`Continue with ${label}`, "i") })).toBeDisabled(); }`.
- Regression guard: post-tick, OAuth buttons are NOT disabled (the click handler is reachable).

### Phase 3 — Issue B: extend probe with Probe 3g (Supabase-shape end-to-end)

Edit `.github/workflows/scheduled-oauth-probe.yml`. Insert a new probe block after step 3f (`probe_github_redirect_uri "supabase_canonical" …`), before step 4 (`/auth/v1/settings`):

- Construct the Supabase authorize URL: `https://${API_HOST}/auth/v1/authorize?provider=github&redirect_to=https%3A%2F%2F${APP_HOST}%2Fcallback`.
- `curl --max-time 10 -s -o /dev/null -w '%{http_code} %{redirect_url}'` with `--max-redirs 0` to capture the 302 location verbatim. Expect `302` + a redirect host of `github.com`.
- Then re-issue the captured GitHub URL with `-L` and grep the body for the rejection sentinel + positive-proof anchors using the **same** `strip_log_injection` and tmpfile pattern used by `probe_github_redirect_uri`. Naming: `probe_github_supabase_shape_e2e`. New failure modes: `github_oauth_supabase_shape_e2e_unregistered`, `github_oauth_supabase_shape_e2e_html_drift`, `github_oauth_supabase_shape_e2e_network`.
- Update the failure-mode block (the `case "$FAIL_MODE"` switch) to include the new `github_oauth_supabase_shape_e2e_unregistered` failure mode in the "Required GitHub App callback URLs" issue-body section so the operator gets the same in-issue remediation guidance.

### Phase 4 — Issue B: extend `oauth-probe-contract.test.ts`

Add a new exported constant `SUPABASE_SHAPE_AUTHORIZE_PATH = "/auth/v1/authorize?provider=github&redirect_to="` and assert the workflow contains the literal string. Add a sentinel-shape assertion that the new probe block calls `probe_github_supabase_shape_e2e` exactly once and that its `record_failure` calls reference the `redirect_uri_safe` variable (log-injection-strip invariant).

### Phase 5 — Issue B: scope decision on #3187 (JWT-mint drift-guard)

**Updated after deepen-plan research.** The action `actions/create-github-app-token` returns an **installation access token** (suitable for `gh api /installation/repositories`), NOT a JWT-as-app token. `gh api /app` (which is what #3187's drift-guard needs to read the App's own `client_id`) requires a **JWT signed by the App's private key**, not an installation token. The two are different authorization types per [GitHub Apps auth docs](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/making-authenticated-api-requests-with-a-github-app-in-a-github-actions-workflow). Therefore #3187 is NOT a 1-step `actions/create-github-app-token` substitution — it requires either:

- A separate JWT-mint step (~10 lines of bash + `openssl` + `printf` to base64url-encode the header/payload/signature), OR
- A dedicated action like [tibdex/github-app-token](https://github.com/tibdex/github-app-token) that exposes a JWT-as-app token (some forks expose this; the canonical action does not).

Decision tree:

- IF the Phase 3 + Phase 4 work fits inside ~80 LoC of workflow + ~20 LoC of test (estimated; verify at GREEN), AND the implementer is comfortable folding in the JWT-mint bash (~30 LoC) without growing the PR diff above ~250 LoC total, THEN fold #3187 in as a separate workflow `daily-github-app-drift-guard.yml` (cron: `0 9 * * *`) that mints the JWT, calls `gh api /app`, and asserts `client_id == OAUTH_PROBE_GITHUB_CLIENT_ID`. PR body uses `Closes #3187`.
- ELSE leave #3187 open with a `Ref #3187` comment naming the re-evaluation criteria from this PR's scope decision (specifically: the JWT-mint cost is genuinely higher than #3181's deferral note implied — `actions/create-github-app-token` returns the wrong token type for `gh api /app`).

**Default disposition: defer #3187.** The Phase 3 + 4 work is the load-bearing user-shape regression guard for the actual user-reported failure mode. #3187 is the strictly-stronger App-identity guard that becomes valuable after a recurrence of an App-identity swap (a class of failure not yet observed). Per `wg-when-deferring-a-capability-create-a`, #3187 already exists as the deferral tracking issue — update its body with the JWT-token-type clarification discovered during this deepen-plan pass.

### Phase 6 — Retroactive remediation of #3183

Per `wg-when-fixing-a-workflow-gates-detection`, post a retroactive comment on **#3183** (the case that exposed the H_C gap) once the PR is merged AND the first post-merge probe firing on `main` is green. Comment must include:

- Workflow run URL of the post-merge Probe 3g firing.
- Verbatim user-shape redirect_uri value tested.
- `pos_proof` count + `err_match=0` confirmation.
- Byte-count of the new `oauth-probe-contract.test.ts` constants block (per the closure-gate template introduced by PR #3181's `follow-through-closure-guard.yml`).

## Files to Edit

- `apps/web-platform/app/(auth)/signup/page.tsx` — add helper hint with conditional render gated on `!tcAccepted`.
- `.github/workflows/scheduled-oauth-probe.yml` — add Probe 3g (Supabase-shape end-to-end), extend `case "$FAIL_MODE"` switch, document the new failure modes inline.
- `apps/web-platform/test/oauth-probe-contract.test.ts` — add `SUPABASE_SHAPE_AUTHORIZE_PATH` sentinel + workflow-grep assertion.

## Files to Create

- `apps/web-platform/test/signup-helper-hint.test.tsx` — Vitest component test for Issue A (visibility + regression guard).

## Open Code-Review Overlap

None. (Queried via `gh issue list --label code-review --state open --json number,title,body --limit 50` and grep'd against each planned file path with `jq --arg`. No matches.)

## Domain Review

**Domains relevant:** Product, Engineering, User-impact (carry-forward from PR #3181).

### Product

**Status:** reviewed (carried forward from PR #3181 / #3183 framing — same domain blast-radius as the precedent: auth is the brand-truth surface; one repro on a public Loom equals "Soleur's auth is broken").

**Assessment:** Same `single-user incident` threshold as #3181. The UX hint (Issue A) is a small but high-leverage addition because it removes the "is this broken?" doubt at the moment of highest brand-impact ambiguity (the gray-button OAuth row at the very first interaction). The probe extension (Issue B) hardens the regression-detection envelope to the actual user-shape URL.

### Engineering

**Status:** reviewed.

**Assessment:** Phase 3's bash extension is consistent with the existing probe's structure (`record_failure` + `strip_log_injection` + tmpfile). `actions/create-github-app-token` is the canonical pattern for App-JWT in workflows; verify version-pinning at GREEN. No Terraform / no Doppler mutation. No migration. Risk concentrated in the workflow YAML — covered by the contract test.

### Product/UX Gate

**Tier:** advisory (modifying existing UI; adding a small explanatory paragraph; no new page, no new component).

**Decision:** auto-accepted (pipeline) per Phase 2.5 ADVISORY rule.

**Agents invoked:** none (no copywriter recommendation from any domain leader; the hint copy is 6 words mirroring the existing checkbox label — does not warrant a copywriter cycle).

**Skipped specialists:** none.

**Pencil available:** N/A (no wireframes needed for a single-line hint).

#### Findings

- Copy: **"Accept the terms above to continue."** mirrors the existing T&C label phrasing. No brand-voice review needed for 6 words of functional explainer.
- Placement: above the OAuth divider so it explains the gray state of the four OAuth buttons (the most ambiguous control set on the page); the "Send verification code" button is already inside the form and reads more naturally as gated.
- Live region: `aria-live="polite"` so the hint announcement is queued, not interrupting.

## Sharp Edges

- **Probe 3g must NOT enable cookie persistence between curl calls.** The Supabase `/auth/v1/authorize` endpoint sets a transient `sb-` cookie that, if persisted across the GitHub `-L` follow, can change GitHub's response surface (e.g., redirect to a `?return_to=` instead of the authorize page). Use a fresh `curl` invocation per leg with no `-c`/`-b`.
- **A plan whose `## User-Brand Impact` section is empty or contains placeholder text will fail `deepen-plan` Phase 4.6.** This plan inherits its threshold (`single-user incident`) from PR #3181 / #3183 — verify CPO sign-off is captured before `/work` begins.
- **`actions/create-github-app-token` is the WRONG primitive for #3187 if folded in.** Its output is an installation access token; `gh api /app` requires a JWT-as-app token. Folding #3187 in requires either a manual JWT-mint bash step (header/payload base64url + `openssl dgst -sha256 -sign`) or a different action that exposes JWT-as-app. Sibling secrets must be `OAUTH_PROBE_GITHUB_CLIENT_ID` (already set) + `OAUTH_PROBE_GITHUB_APP_PRIVATE_KEY` (new — `gh secret set GITHUB_*` returns HTTP 422 per the 2026-05-04 learning, hence the `OAUTH_PROBE_` prefix). The action's input names are `client-id` (preferred) / `app-id` (deprecated) + `private-key`.
- **Live region must pre-exist in DOM for first-render announcements.** Conditional render of the `role="status"` element (`{!cond && <p role="status">…</p>}`) does NOT reliably announce on the first state change because screen-reader mutation observers attach at announcement time to live regions that already exist. Pattern: persistent `<p role="status">` element with text content swapped between the hint string and the empty string. This is the load-bearing accessibility correction surfaced by deepen-plan research.
- **Issue A's hint must not regress the existing `disabled:opacity-50` affordance.** The hint is additive, not a replacement. The Vitest component test in Phase 2 includes the regression guard for this.
- **Per `hr-when-a-plan-specifies-relative-paths-e-g`,** verify `apps/web-platform/test/` exists and contains at least one `.test.tsx` file before authoring the new component test (`git ls-files apps/web-platform/test/ | head -5`). Confirmed: `oauth-probe-contract.test.ts` lives there; the directory is the right place.
- **Per `hr-never-label-any-step-as-manual-without`,** the post-merge audit step prefers Playwright MCP for reading the GitHub App callback URL textarea before any human handoff. Only the textarea **edit** is genuinely manual (CSRF-protected); reading is automatable.

## References & Research

- PR #3181 (merged 4 h before this plan): `fix(oauth): GitHub App callback URL probe + closure gate` — shipped the 3-URL probe, closure gate, runbook, sentinel test. This plan's Issue B extends that probe with the user-shape end-to-end leg.
- Issue #3183 (closed by #3181): the user-reported `redirect_uri is not associated` precedent. This plan posts a retroactive comment per `wg-when-fixing-a-workflow-gates-detection`.
- Issue #3187 (open, deferred from #3181): JWT-mint App-identity drift-guard. Phase 5 of this plan re-evaluates folding it in.
- Issue #1784 (closed): the original GitHub App callback URL configuration follow-through, which closed without verbatim verification and recurred as #3183.
- Learning: `knowledge-base/project/learnings/integration-issues/2026-05-04-github-app-callback-url-three-entries.md` — single client_id / two flows / three callbacks / body-grep-load-bearing invariants.
- Learning: `knowledge-base/project/learnings/2026-05-04-github-secrets-cannot-start-with-github-prefix.md` — `gh secret set GITHUB_*` returns HTTP 422; `OAUTH_PROBE_` prefix mandated.
- Runbook: `knowledge-base/engineering/ops/runbooks/github-app-callback-audit.md` — operator audit procedure.
- Runbook: `knowledge-base/engineering/ops/runbooks/oauth-probe-failure.md` — failure-mode-keyed triage.
- Code: `apps/web-platform/components/auth/oauth-buttons.tsx:107` — `disabled` prop already correctly wired.
- Code: `apps/web-platform/app/api/auth/github-resolve/route.ts` — Flow B redirect_uri construction (`${appUrl}/api/auth/github-resolve/callback`).
- AGENTS.md rules touched: `hr-weigh-every-decision-against-target-user-impact` (single-user-incident threshold), `wg-when-fixing-a-workflow-gates-detection` (retroactive remediation of #3183), `hr-never-label-any-step-as-manual-without` (Playwright-MCP-first audit), `hr-dev-prd-distinct-supabase-projects` (verified — dev has no GitHub OAuth secret-binding to the prd App).

## Research Insights

### ARIA live regions (Phase 1, Phase 2)

**Best practices:**

- Live regions must be present in the DOM **before** the content change that should be announced. First-render injection of a live region with non-empty content is unreliable on most screen readers (NVDA, JAWS, VoiceOver) because they attach mutation observers at announcement time rather than re-scanning the full DOM.
- `role="status"` is implicitly `aria-live="polite"` + `aria-atomic="true"`. Adding both explicitly is documentation, not behavioral.
- `polite` queues the announcement after the user finishes any current speech (correct for non-error informational hints). `assertive` interrupts and is reserved for `role="alert"` (errors, critical state changes).
- Reserve vertical space (`min-h-[1rem]`) so the layout does not shift when text empties — avoids a CLS regression and a visual "ghost" of the missing element.

**Anti-patterns:**

- `{cond && <p role="status">…</p>}` — conditional render of the live region itself: announcements unreliable.
- `aria-live="assertive"` for non-error hints: interrupts the user and is hostile in a sign-up flow.
- Hiding the live region via `display: none` (vs. emptying its text): some screen readers stop tracking the region entirely.

**References:**

- W3C WAI [ARIA22: Using role=status](https://www.w3.org/WAI/WCAG22/Techniques/aria/ARIA22)
- MDN [ARIA live regions](https://developer.mozilla.org/en-US/docs/Web/Accessibility/ARIA/Guides/Live_regions)
- MDN [ARIA: status role](https://developer.mozilla.org/en-US/docs/Web/Accessibility/ARIA/Reference/Roles/status_role)

### Supabase OAuth flow shape (Phase 3)

**Flow:** Browser → `/auth/v1/authorize?provider=github&redirect_to=…` → 302 to GitHub `/login/oauth/authorize?client_id=…&redirect_uri=…` → consent → `/auth/v1/callback` → SITE_URL.

**Implementation note for Probe 3g:**

- Capture the 302 from `/auth/v1/authorize` with `--max-redirs 0` and `-w '%{redirect_url}'` to inspect the GitHub URL Supabase advertises.
- Re-issue that GitHub URL with `-L` and grep the body for `redirect_uri is not associated` (load-bearing sentinel from `oauth-probe-contract.test.ts`).
- Do NOT pass cookies between the Supabase leg and the GitHub leg — Supabase sets a transient `sb-` cookie that can change GitHub's response surface.

**References:**

- Supabase [Login with GitHub](https://supabase.com/docs/guides/auth/social-login/auth-github)
- Supabase [Redirect URLs](https://supabase.com/docs/guides/auth/redirect-urls)

### GitHub Apps authentication in workflows (Phase 5)

**Important distinction:** `gh api /app` requires a JWT-as-app token (signed by the App's private key, RS256, 10-minute expiry). `actions/create-github-app-token` outputs an **installation access token** (suitable for `gh api /installation/repositories` and most repo-scoped operations) — these are different authorization types.

**For #3187 if folded in:**

- JWT-mint inline with `openssl dgst -sha256 -sign` + base64url encoding (~30 LoC bash), OR
- Use `actions/create-github-app-token` only as a building block — its `client-id` (preferred) / `app-id` (deprecated) input + `private-key` input return an installation token; the JWT-as-app step would still need to be inline.

**References:**

- GitHub Docs [Authenticating as a GitHub App in a GitHub Actions workflow](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/making-authenticated-api-requests-with-a-github-app-in-a-github-actions-workflow)
- GitHub Docs [Generating a JSON Web Token (JWT) for a GitHub App](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/generating-a-json-web-token-jwt-for-a-github-app)
- [`actions/create-github-app-token` README](https://github.com/actions/create-github-app-token)

### Vitest component-test placement (Phase 2)

**Codebase convention:** `apps/web-platform/vitest.config.ts` defines two projects:

- `unit` — `test/**/*.test.ts` + `lib/**/*.test.ts` under `node` environment.
- `component` — `test/**/*.test.tsx` under `happy-dom` with `test/setup-dom.ts` + `isolate: true` (per-file module-graph isolation, ~15-25% slower but reliable).

The new `signup-helper-hint.test.tsx` lands in the `component` project. The flat `apps/web-platform/test/` directory is the canonical location (sibling: `cancel-retention-modal.test.tsx`); avoid creating `apps/web-platform/test/auth/` for this PR — that subdirectory currently holds only one file (`sentry-tag-coverage.test.ts`) and adopting it would diverge from the dominant convention.

## Resume prompt

```
/soleur:work knowledge-base/project/plans/2026-05-04-fix-signup-oauth-helper-and-github-callback-recurrence-plan.md. Branch: feat-one-shot-signup-oauth-helper-github-callback. Worktree: .worktrees/feat-one-shot-signup-oauth-helper-github-callback/. Issue: refs #3183 (closed) #3187 (open). PR: pending. Plan reviewed and deepened, implementation next.
```
