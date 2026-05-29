---
title: "fix: gate invite-accept UI on invitee-email match + humanize mismatch message"
type: fix
date: 2026-05-29
branch: feat-one-shot-fix-invite-accept-email-mismatch
lane: single-domain
status: planned
requires_cpo_signoff: false
brand_survival_threshold: single-user incident
---

# 🐛 fix: gate invite-accept UI on invitee-email match + humanize mismatch message

## Enhancement Summary

**Deepened on:** 2026-05-29
**Sections enhanced:** Observability (5-field schema), Research Insights (new),
Research Reconciliation (premise verified live)

### Key Improvements
1. **Premise verified live** — `gh` confirmed PR #4545 MERGED and issue #4544 CLOSED;
   the server-side security enforcement (route 403 + DB RPC identity binding, mig 076)
   is already on `main`. This plan is correctly scoped to the **client UX follow-on**,
   not a server security fix.
2. **Precedent-diff grounded** — the Server-Component-computes-a-flag → `"use client"`
   child pattern already exists in `page.tsx` + `pending-invite-banner.tsx`; the neutral
   `text-[#9a9a9a]` copy styling (vs the red error box) is the design distinction the
   fix turns on. No novel pattern introduced.
3. **Observability promoted to 5-field schema** with a non-SSH discoverability test
   that runs both the new client gating test and the existing server identity test.

### New Considerations Discovered
- Client gate is **email-based** (lookup result lacks `invitee_user_id`); the stronger
  `invitee_user_id`-OR-email check stays at the route + RPC layers as the security floor.
- `user.email` undefined → comparison `false` → Accept disabled (fail-closed CTA).
- Decline gating symmetry decided: gate both Accept and Decline on mismatch (Sharp Edges).

## Overview

On the public invite-acceptance screen (`/invite/[token]`), when the currently
signed-in account does **not** match the invited email, the UI still renders an
**enabled** "Accept invitation" button. Clicking it makes the server correctly
reject the acceptance with HTTP 403 `{ error: "not_intended_invitee" }`, and the
client surfaces that **raw error code** in a red error box — the exact symptom in
the operator screenshot (red `not_intended_invitee` text, enabled Accept/Decline).

**Root cause (client-only):** `app/(public)/invite/[token]/page.tsx` receives
`result.invitee_email` from the `lookup_invitation_by_token` RPC and the signed-in
user from `supabase.auth.getUser()`, but it **discards both** — it never passes the
invitee email (or a computed mismatch flag) into `<InviteActions>`. `InviteActions`
therefore has no signal to disable the CTA, and its only failure surface is the
generic `setError(data.error)` path that prints the raw server reason verbatim.

**The server-side enforcement is already correct and tested** — this is the key
premise correction (see Research Reconciliation). It must be *verified*, not
re-added:

- **Route layer** (`accept-invite/route.ts:38-50`, `decline-invite/route.ts:35-49`):
  explicit `isInvitee` check returning 403 `not_intended_invitee`.
- **DB RPC layer** (migration `076_invitation_invitee_identity_check.sql`, shipped
  in PR #4545 fixing #4544): identity binding inside both
  `accept_workspace_invitation` and `decline_workspace_invitation`, covering both
  the `invitee_user_id` arm and the case-insensitive `invitee_email` arm, executed
  under `SECURITY DEFINER`.
- **Existing regression coverage:** `test/server/workspace-invitation-identity.test.ts`
  already asserts 403 for both accept and decline, for both identity arms, plus the
  positive (matching-user) paths.

So the fix is: (1) **client gating** — pass the mismatch signal into `InviteActions`
and disable Accept (and show a clear, non-error-styled message) when the signed-in
user is not the intended invitee; (2) **client copy** — map the `not_intended_invitee`
server reason to human-readable text so it never leaks as a raw code even on the
defensive 403 path; (3) **regression test** — a `.test.tsx` (happy-dom) test for the
`InviteActions` gating behavior. Server layer changes: **none** (verify only).

This is a `single-domain` (frontend, web-platform) change with a security-adjacent
surface that is already defended at two server layers.

## User-Brand Impact

**If this lands broken, the user experiences:** the invited person opens the invite
link while signed into the wrong account and sees a cryptic red `not_intended_invitee`
code next to an enabled "Accept invitation" button — looks like a broken app, erodes
trust at the exact moment a new teammate is being onboarded.

**If this leaks, the user's workspace membership is exposed via:** N/A for this change
— the server already rejects mismatched acceptance at two layers (route 403 + DB RPC
identity binding). This change does not relax, move, or remove any server-side check;
it only adds a client-side disable + humanized copy on top of the existing defenses.
No new exposure vector is introduced.

**Brand-survival threshold:** single-user incident — a non-technical invitee hitting a
raw error code on the onboarding screen is a per-user trust event. The threshold is set
by the user-facing-broken artifact, not by a data-exposure vector (there is none here).

> Note: threshold is `single-user incident` because of the *broken-UX* artifact, not a
> security regression. CPO sign-off is **not** required (`requires_cpo_signoff: false`)
> because no server-side authorization behavior changes — the diff is client gating +
> copy + a client test. If review disagrees, escalate per the threshold rules.

## Research Reconciliation — Spec vs. Codebase

| Task-description claim | Codebase reality | Plan response |
|---|---|---|
| "the server must reject acceptance by a non-intended invitee" (implied: it currently does not) | Server **already rejects** at two layers: route `isInvitee` 403 (`accept-invite/route.ts:38-50`) **and** DB RPC identity binding (mig 076, PR #4545, fixing #4544). Both arms (user_id + case-insensitive email) covered. | **Verify only — do not re-add.** Plan adds an Acceptance Criterion that runs the existing `workspace-invitation-identity.test.ts` green and reads mig 076 to confirm the binding is present. No server file is edited. |
| "fix client + server" | Server is correct; only the client gating + copy is wrong. | Reframe to **client-only fix**. Server changes: none. |
| "red `not_intended_invitee` text … suggests the UI still lets them proceed" | Correct. `page.tsx` discards `result.invitee_email` + `user.email`; `InviteActions` has no mismatch prop and prints `data.error` verbatim on 403. | Pass mismatch signal into `InviteActions`; disable Accept; humanize the error map. |
| "add a regression test for the email-mismatch acceptance path" | Server path already tested. The *untested* path is the **client gating** (Accept disabled / message shown when mismatched). | Add a `InviteActions` `.test.tsx` (happy-dom) regression test. |

## Files to Edit

- `apps/web-platform/app/(public)/invite/[token]/page.tsx` — compute
  `isIntendedInvitee` server-side (compare `user?.email?.toLowerCase()` to
  `result.invitee_email?.toLowerCase()`); pass `inviteeEmail` and
  `isIntendedInvitee` (and the signed-in email for the helper message) into
  `<InviteActions>`. The page already has both `result.invitee_email` and `user`
  in scope (lines 19, 37-39) — no new data fetch needed.
- `apps/web-platform/app/(public)/invite/[token]/invite-actions.tsx` —
  (a) add props `inviteeEmail: string` and `isIntendedInvitee: boolean`;
  (b) when authenticated **and** `!isIntendedInvitee`, render a clear,
  **non-error-styled** notice (e.g., neutral `#9a9a9a` text, not the red
  `bg-red-500/10` box) — "This invitation was sent to **{inviteeEmail}**. You're
  signed in as **{signed-in email}**. Sign in with the invited account to accept."
  — and render the Accept button **disabled** (Decline may remain enabled only if
  the signed-in user is the invitee; otherwise also gate it — see Sharp Edges);
  (c) add a `reasonToMessage()` map so the catch-path `setError` never prints a raw
  server code (`not_intended_invitee` → "This invitation isn't addressed to your
  account."; `expired` → "This invitation has expired."; `already_accepted` /
  `already_member` → "You've already joined this workspace."; default → existing
  generic text).

## Files to Create

- `apps/web-platform/test/invite-actions-gating.test.tsx` — happy-dom regression
  test for `InviteActions` (runner: **vitest**, `.test.tsx` → `happy-dom` project per
  `vitest.config.ts`; model after existing `test/invite-member-modal.test.tsx`).
  Cases:
  1. **mismatch:** `isAuthenticated=true`, `isIntendedInvitee=false` → Accept button
     is `disabled`; the neutral mismatch notice is present; the red error box is
     **absent**; `inviteeEmail` is shown.
  2. **match:** `isAuthenticated=true`, `isIntendedInvitee=true` → Accept button is
     **enabled**; no mismatch notice.
  3. **unauthenticated:** `isAuthenticated=false` → "Create an account to join" CTA
     (unchanged behavior).
  4. **humanized error:** simulate a 403 `{ error: "not_intended_invitee" }` fetch
     response on the match path (defensive) and assert the rendered text is the
     human string, **not** the raw `not_intended_invitee` token. (Mock `fetch`.)

## Implementation Phases

### Phase 1 — RED: write the failing client gating test
Add `test/invite-actions-gating.test.tsx` with the four cases above. Run
`./node_modules/.bin/vitest run test/invite-actions-gating.test.tsx` (from
`apps/web-platform/`) — confirm cases 1 and 4 fail against current `InviteActions`
(no mismatch prop, raw error string).

### Phase 2 — GREEN: client gating + humanized copy
1. Edit `page.tsx`: compute `isIntendedInvitee` and pass `inviteeEmail` +
   `isIntendedInvitee` + signed-in email into `<InviteActions>`.
2. Edit `invite-actions.tsx`: add props, the disabled-Accept + neutral-notice
   branch, and the `reasonToMessage()` map.
3. Re-run the test file → green. Run `./node_modules/.bin/tsc --noEmit` (or the
   package's typecheck script) to confirm prop-type changes thread cleanly.

### Phase 3 — VERIFY server enforcement (no edits)
1. `./node_modules/.bin/vitest run test/server/workspace-invitation-identity.test.ts`
   → green (proves route-layer 403 both routes, both arms).
2. Read `supabase/migrations/076_invitation_invitee_identity_check.sql` and confirm
   the identity binding is present in both RPCs (cite lines in PR body). No migration
   is added or modified.

### Phase 4 — full suite + lint
Run the package test suite (`vitest run`) scoped to changed areas and the lint/typecheck
the repo CI runs, to catch any prop-threading regressions.

## Acceptance Criteria

### Pre-merge (PR)
- [x] `InviteActions` renders the **Accept button disabled** and a **non-error-styled**
      mismatch notice (no `bg-red-500/10` box) when `isAuthenticated && !isIntendedInvitee`.
      Verify: case 1 of `invite-actions-gating.test.tsx` asserts `accept.disabled === true`
      and `queryByText(/not_intended_invitee/)` is `null`.
- [x] `page.tsx` computes `isIntendedInvitee` by comparing lower-cased
      `user?.email` to lower-cased `result.invitee_email` and passes it +
      `inviteeEmail` to `<InviteActions>`. Verify: grep `page.tsx` for
      `toLowerCase()` comparison and the new props on `<InviteActions>`.
- [x] No raw `not_intended_invitee` (or other server reason code) is ever rendered to
      the user. Verify: case 4 asserts the humanized string renders and the raw token
      does not.
- [x] Existing server identity test stays green:
      `./node_modules/.bin/vitest run test/server/workspace-invitation-identity.test.ts`
      exits 0.
- [x] No server file changed: `git diff --name-only origin/main` lists **zero** paths
      under `app/api/workspace/`, `server/workspace-invitations.ts`, or
      `supabase/migrations/`.
- [x] Typecheck clean for the touched files.

### Post-merge (operator)
- _None._ Pure client code change against an already-provisioned, already-deployed
  surface. The `web-platform-release.yml` pipeline rebuilds + restarts the container on
  merge to `main` touching `apps/web-platform/**`; no migration apply, no Doppler/Terraform
  step. (PR merge IS the remediation per AGENTS.md automation-feasibility gate.)

## Test Scenarios

- Signed-in user **is** the invitee (by user_id) → Accept enabled, accepts cleanly.
- Signed-in user **is** the invitee (by case-insensitive email, `invitee_user_id` null)
  → Accept enabled.
- Signed-in user **is not** the invitee → Accept disabled, neutral notice naming the
  invited email + the signed-in email; server 403 path never reached via the button.
- Defensive: a 403 still occurs (e.g., race / direct POST) → client shows humanized
  copy, not the raw code.
- Unauthenticated visitor → unchanged signup/login CTA.

## Domain Review

**Domains relevant:** Product (UX surface)

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A

#### Findings

Modifies an **existing** user-facing component (`InviteActions`) without adding a new
page/route/component file — ADVISORY tier (no new `components/**/*.tsx`,
`app/**/page.tsx`, or `layout.tsx` files created; the new file is a test under `test/`).
Running in pipeline → auto-accepted. The UX change is a disable + a copy swap on an
existing screen; the copy should follow the existing neutral `#9a9a9a` styling already
used for the expiry line in `page.tsx`. Deepen-plan / review may invoke copywriter for
the mismatch-notice wording if desired.

## Sharp Edges

- **Decline gating symmetry.** The current `InviteActions` Decline button is always
  enabled when authenticated. The server's `decline-invite` route AND
  `decline_workspace_invitation` RPC already reject a non-invitee with 403, so leaving
  Decline enabled is not a security hole — but for UX consistency, gate Decline the
  same way as Accept (disable when `!isIntendedInvitee`), since a non-invitee declining
  someone else's invite is nonsensical. Decide explicitly in /work; default to gating both.
- **Test runner is vitest, not bun test.** `apps/web-platform/bunfig.toml` sets
  `[test] pathIgnorePatterns = ["**"]` to block bun test discovery (#1469). Use
  `./node_modules/.bin/vitest run <path>` (package script `test` = `vitest`). A
  `bun test` invocation will report "filter did not match" even though the file exists.
- **`.test.tsx` → happy-dom, `.test.ts` → node.** Per `vitest.config.ts` two-project
  split, the new client test MUST be `.test.tsx` to land in the happy-dom (DOM-capable)
  project. A `.test.ts` extension would run under node with no DOM and fail to render.
- **`page.tsx` is a Server Component; `InviteActions` is `"use client"`.** Compute the
  mismatch on the server (in `page.tsx`) and pass the boolean down — do not move
  `getUser()` into the client component. The page already has `user` in scope.
- **`user.email` can be undefined.** Guard with `?.toLowerCase()` on both sides exactly
  as the route does (`accept-invite/route.ts:42`); never `===` raw values.
- A plan whose `## User-Brand Impact` section is empty, contains only TBD/placeholder,
  or omits the threshold will fail `deepen-plan` Phase 4.6. (Section is filled above.)

## Observability

This change touches `.tsx` files under `apps/web-platform/` so the gate applies. The
change adds **no new server emit site, no new infra, and no new persistent process** —
it gates an existing client component and humanizes an existing error string. The
existing server rejection telemetry is unchanged and is what an operator watches; the
5-field schema below points at those existing signals.

```yaml
liveness_signal:
  what: "Invite-accept route 403 rate (existing) — POST /api/workspace/accept-invite returning not_intended_invitee"
  cadence: "on-demand / per-request (no scheduled job introduced)"
  alert_target: "no new alert; this fix should REDUCE the 403 rate as the disabled CTA stops mismatched clicks"
  configured_in: "existing Next.js route handler app/api/workspace/accept-invite/route.ts (unchanged)"
error_reporting:
  destination: "client render errors surface in-UI (humanized copy); server-side query failures already route to Sentry via reportSilentFallback in server/workspace-invitations.ts (unchanged)"
  fail_loud: "yes — server query failures already mirror to Sentry; this PR adds no silent fallback"
failure_modes:
  - mode: "page.tsx mis-computes isIntendedInvitee (e.g., case-sensitivity bug)"
    detection: "invite-actions-gating.test.tsx cases 1+2 (mismatch disabled / match enabled) fail in CI"
    alert_route: "CI vitest gate (pre-merge); no runtime alert needed"
  - mode: "server still 403s a legitimate invitee (regression in route/RPC)"
    detection: "existing workspace-invitation-identity.test.ts positive-path cases fail in CI"
    alert_route: "CI vitest gate (pre-merge)"
  - mode: "raw error code leaks to UI again (reasonToMessage map regresses)"
    detection: "invite-actions-gating.test.tsx case 4 asserts raw token absent"
    alert_route: "CI vitest gate (pre-merge)"
logs:
  where: "no new logs; existing pino child logger 'workspace-invitations' covers server query failures"
  retention: "existing platform log retention (unchanged)"
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/invite-actions-gating.test.tsx test/server/workspace-invitation-identity.test.ts"
  expected_output: "both files green: client gating asserted (Accept disabled on mismatch, no raw code) AND server 403 enforcement asserted (both routes, both identity arms)"
```

## Research Insights

**Premise validation (verified live, 2026-05-29):**
- `gh pr view 4545 --json state,title` → `MERGED` — "fix(security): add invitee
  identity check to accept/decline workspace invitation RPCs". Confirms the DB-layer
  identity binding (migration 076) is on `main`.
- `gh issue view 4544 --json state,title` → `CLOSED` — "security: add invitee identity
  check to accept_workspace_invitation RPC". The server-side security bug this fix
  *appears* to be about is already closed; this plan is the **client UX follow-on**.
- `git diff --name-only origin/main` → no paths under `app/api/workspace/`,
  `server/workspace-invitations.ts`, or `supabase/migrations/`. Confirms the plan's
  "server changes: none" claim holds at plan time.

**Precedent-Diff (Phase 4.4) — Server Component computes a flag, passes to `"use client"` child:**
The canonical shape already exists in this exact directory and its sibling:
- `page.tsx` is a Server Component that already calls `supabase.auth.getUser()` and
  resolves the invitation via the service-role RPC, then passes primitive props
  (`invitationId`, `token`, `isAuthenticated`, `expiresAt`) into the `"use client"`
  `InviteActions`. Adding `isIntendedInvitee: boolean` + `inviteeEmail: string` follows
  the identical pattern — **no new precedent invented.**
- `components/dashboard/pending-invite-banner.tsx` is the sibling `"use client"` invite
  surface; it takes computed props (`inviterName`, `workspaceName`) from a Server
  Component. Same pattern.
- **Neutral (non-error) copy styling precedent:** `page.tsx` already uses
  `text-[#9a9a9a]` (lines 28, 51) and `text-[#6a6a6a]` (line 64) for informational
  text. The mismatch notice MUST reuse `text-[#9a9a9a]`, NOT the red `bg-red-500/10`
  error box — that red box is reserved for *failed actions*, and reusing it for the
  mismatch state is exactly the current bug (the raw `not_intended_invitee` renders in
  it). This is the design distinction the fix turns on.

**Implementation detail — compute the flag on the server, not the client:**
```tsx
// page.tsx (Server Component) — user + result already in scope (lines 19, 36-39)
const isIntendedInvitee =
  !!user &&
  result.invitee_email?.toLowerCase() === user.email?.toLowerCase();
// pass isIntendedInvitee + result.invitee_email + (user?.email ?? "") into <InviteActions>
```
The lower-cased email comparison mirrors the existing route guard
(`accept-invite/route.ts:42`) exactly — single source of comparison semantics. Note the
page only has `invitee_email`, not `invitee_user_id`, in the lookup result, so the
client gate is an **email-based** check; the route + RPC retain the stronger
`invitee_user_id`-OR-email check as the security floor. The client gate is a UX
convenience layered on top of (never a replacement for) the two server layers.

**Edge cases:**
- `user.email` undefined (OAuth account with no email) → comparison is `false` →
  Accept disabled, notice shown. Correct fail-closed behavior for the CTA.
- Whitespace/case variance in invitee email → `.toLowerCase()` on both sides; the DB
  stores `invitee_email` already lower-cased (`getPendingInvitesForUser` queries
  `email.toLowerCase()`), so this is consistent.
- Stale page (user signs into a different account in another tab, then clicks) → server
  still 403s; the humanized `reasonToMessage()` covers it. Belt-and-suspenders.

## Scope Addendum — Brand / Visual Identity (operator request, 2026-05-29)

The operator added two visual requests on the same `/invite/[token]` screen while
this plan was in flight. Both land in the **same two files** already being edited, so
they fold into this PR rather than a separate one:

1. **Replace the "S" letter avatar with the Soleur logo mark.** `page.tsx` lines 45-47
   currently render a blue circle (`bg-[#2563eb]/10`) with a bold blue `S` glyph. Replace
   with the real logo asset `public/icons/soleur-logo-mark.png`, reusing the exact pattern
   in `components/leader-avatar.tsx:74-80` (`<img src="/icons/soleur-logo-mark.png" alt="" className="h-full w-full object-cover" />` inside a fixed-size `overflow-hidden` container). Keep the `h-12 w-12` sizing; drop the colored background tint so the mark reads on the surface.

2. **Replace off-brand colors with Solar Forge brand tokens.** The screen uses raw hex
   and an **off-brand blue `#2563eb` / `#1d4ed8`** that appears nowhere in the brand guide
   (`knowledge-base/marketing/brand-guide.md` §Color Palette). The guide mandates: *"never
   raw hex in components"* — use the wired theme-aware Tailwind tokens (`apps/web-platform/app/globals.css`
   `--color-soleur-*`). Mapping (applies across `page.tsx` **and** `invite-actions.tsx`,
   including the unauthenticated and error branches):

   | Current (off-brand / raw hex) | Brand token utility |
   |---|---|
   | `bg-[#0A0A0A]` (page) | `bg-soleur-bg-base` |
   | `bg-[#141414]` (card) | `bg-soleur-bg-surface-1` |
   | `border-[#2A2A2A]` | `border-soleur-border-default` |
   | `text-white` (headings) | `text-soleur-text-primary` |
   | `text-[#9a9a9a]` (incl. mismatch notice from Phase 2) | `text-soleur-text-secondary` |
   | `text-[#6a6a6a]` (expiry) | `text-soleur-text-muted` |
   | `bg-[#2563eb] hover:bg-[#1d4ed8] text-white` (primary CTA — Accept + "Create an account") | `bg-gradient-to-r from-soleur-accent-gradient-start to-soleur-accent-gradient-end text-soleur-text-on-accent hover:opacity-90` — **forge ink on gold, never white on gold** (brand guide: white-on-gold fails AA). Match the sibling public auth CTA in `app/(auth)/signup/page.tsx` if it already uses a token convention. |
   | `text-[#2563eb] hover:underline` (Sign in link) | `text-soleur-accent-gold-fg hover:underline` |
   | red `bg-red-500/10 text-red-400` error box | **unchanged** — red is the correct semantic for a *failed action*; only the mismatch *notice* (Phase 2) must avoid it. |

   Disabled-state gold CTA keeps `disabled:opacity-50` (already present).

**Brand corners note (out of scope, flagged):** the brand guide §Design Principles
mandates *sharp 0px corners* ("No rounded corners"), but the screen uses `rounded-lg`/
`rounded-md`/`rounded-full`. The operator asked specifically for **colors + logo**, so
corner-radius is left unchanged here to avoid scope creep; noted in the PR body as a
follow-up candidate (do not silently expand).

### Brand scope — Files to Edit (same files, no new files)
- `page.tsx` — logo swap (item 1) + token swap (item 2) on the page-level surfaces and
  both the valid and "Invitation not available" branches.
- `invite-actions.tsx` — token swap on the authenticated CTA, the unauthenticated
  signup/sign-in CTA + link, and the Phase-2 mismatch notice (use `text-soleur-text-secondary`).

### Brand scope — Acceptance Criteria (additive)
- [x] No `#2563eb` / `#1d4ed8` (or any raw hex color) remains in `page.tsx` or
      `invite-actions.tsx`. Verify: `grep -nE '#(2563eb|1d4ed8|[0-9a-fA-F]{6})' apps/web-platform/app/\(public\)/invite/\[token\]/{page,invite-actions}.tsx` returns only the red `red-500/red-400` semantic utility (which is a Tailwind name, not a hex) — i.e. zero `#hex` matches.
- [x] The "S" `<span>` is gone; `page.tsx` renders `<img src="/icons/soleur-logo-mark.png" …>`. Verify: grep for `soleur-logo-mark.png` in `page.tsx`; grep confirms no `>S<` glyph span remains.
- [x] Primary CTA uses the gold gradient + `text-soleur-text-on-accent` (no `text-white` on the gold button). Verify by reading the className.
- [x] Visual QA (Phase 5.5): screenshot `/invite/[token]` for valid + mismatch states; the avatar shows the gold logo mark, CTA is gold, no blue anywhere.

### Brand scope — RED test note
The gating test (`invite-actions-gating.test.tsx`) asserts behavior, not exact colors;
color is verified by the grep AC + visual QA rather than brittle className assertions in
the unit test. Do **not** assert raw hex strings in the test (they'd lock the component to
literal values and break on the token migration). If a styling assertion is added, assert
the **absence** of the blue token / presence of a gold token class name, not a hex.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Add server-side rejection (treat as a security bug) | Server already rejects at route + DB RPC (mig 076 / PR #4545). Re-adding would be redundant and risk regressing the existing tested behavior. |
| Hide the invite screen entirely for mismatched users | Worse UX — the invitee needs to *see* which email the invite was sent to so they know which account to sign in with. A disabled CTA + explanatory notice is more actionable. |
| Only humanize the error code, leave button enabled | Leaves the misleading enabled-CTA state; the user still clicks, fails, and re-reads an error. Gating the button is the primary fix. |
