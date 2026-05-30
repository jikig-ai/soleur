---
date: 2026-05-29
topic: skip-api-key-onboarding
lane: cross-domain
brand_survival_threshold: single-user incident
status: brainstorm-complete
branch: feat-skip-api-key-onboarding
pr: 4640
---

# Brainstorm: Skippable "Connect your API key" onboarding (delegation-aware)

## What We're Building

Let users skip the mandatory "Connect your API key" onboarding step and enter the
app, with (a) an honest, factual warning that Soleur requires a key to function and
can be set up anytime in Settings, and (b) durable, loop-safe degraded-state
handling so a keyless user is never trapped or silently dead-ended.

**Critically, every gate is delegation-aware.** With multi-user workspaces, a member
may run on a workspace owner's **BYOK delegation** instead of their own key. Such a
user must never see the setup-key force-redirect, the skip affordance, or the
degraded warning — they already have a working (delegated) key.

## Why This Approach

Chosen scope: **Full loop-safe, made delegation-aware** (operator picked option 1 of
3, conditioned on "unless there is a BYOK delegation for that user").

Forcing a raw `sk-ant-...` field before a non-technical founder has seen any value is
the worse dead-end — they bounce before understanding what they bought. But a naive
skip just relocates the wall: a skipped user opens chat, hits the chat-time key gate,
and gets bounced right back to `/setup-key` (a redirect loop / quieter dead-end). The
full option is the only one that doesn't leave a trap. The two weaker options (minimal
skip, banner-only-no-flag) were rejected for reintroducing the loop and for losing the
never-onboarded-vs-deliberately-skipped distinction, respectively.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Add `setup_key_skipped_at timestamptz NULL` to `public.users` (migration **085**, with `.down.sql`) | Mirrors the established dismissal-flag pattern: `012_onboarding_state` (`onboarding_completed_at`, `pwa_banner_dismissed_at`), `049_runtime_explainer_state` (`runtime_explainer_dismissed_at`). Timestamptz gives "when skipped" for free. Server-authoritative (rejects localStorage). |
| 2 | **Gate on EFFECTIVE key, not own `api_keys` row** | The correct question is "own valid key OR active inbound delegation?" Authoritative source: Postgres RPC `resolve_byok_key_owner(caller, workspace)` (mig 083/084). |
| 3 | Add reusable TS helper `userHasEffectiveByokKey(userId, workspaceId, serviceClient): Promise<boolean>` wrapping `resolve_byok_key_owner` (non-empty result = has key). No such helper exists today. | Single source of truth for: callback redirect, accept-terms redirect, dashboard banner condition. Must mirror the runtime's org-level delegation feature-flag check so flag-disabled orgs don't count delegations. |
| 4 | Fix pre-existing bug inline: `callback/route.ts` (~L233-242) and `accept-terms/route.ts` `getRedirectDestination` (~L10-23) currently check only `api_keys` → delegated-but-no-own-key users are wrongly force-redirected to `/setup-key` TODAY. Replace with `userHasEffectiveByokKey`. | Per `wg-when-an-audit-identifies-pre-existing` — the fix IS the natural scope of this feature (the gate must be effective-key-aware anyway), so fixed inline, not deferred. |
| 5 | Force-redirect to `/setup-key` only when: no effective key **AND** `setup_key_skipped_at IS NULL`. Otherwise continue onboarding (→ `/connect-repo` if no repo, else `/dashboard`). | Preserves the first-run nudge; skip persists so login doesn't re-trap. |
| 6 | Add "Set up later" action on `/setup-key` → writes `setup_key_skipped_at = now()` and routes to the next onboarding step (`/connect-repo`). | The key step is not the last step; skip should advance onboarding, not jump to dashboard. |
| 7 | Replace chat-time hard-redirect with in-chat CTA. `lib/ws-client.ts` (~L184-192) currently does `window.location.href = "/setup-key"` on `errorCode: "key_invalid"`. Change to an in-chat "Add your API key" error/CTA linking to `/setup-key`, and stop the socket. | **Breaks the redirect loop** (decision's central hazard). A keyless user reaching chat is now an expected state, not an onboarding gap. |
| 8 | Persistent dashboard banner shown only when `!userHasEffectiveByokKey`: "Tasks are disabled until you add a key" + one-click CTA to Settings (`/dashboard/settings/services`). Concrete language, not "won't work well". | Durable, honest degraded surface. Avoids the "misled" feeling of a soft skip warning. Hidden for delegated users. |
| 9 | "Set it later in Settings" is honest TODAY — `/dashboard/settings/services` + `KeyRotationForm` (POSTs `/api/keys`) already exist. **Do NOT build a new Settings page.** Point skip copy + banner there. | Corrects the initial (stale bare-repo) research that claimed no Settings page. |
| 10 | Warning copy (CLO-approved, disclosure-strengthening, no external counsel needed): "Soleur requires your own Anthropic API key to function. You can add it anytime in Settings. Until then, tasks are disabled. Getting a key requires a separate, paid Anthropic account." | Three load-bearing points: **requires** (not "works better with"), the account is **separate and paid**, the **set-later path is real**. |
| 11 | ENFORCEMENT UNTOUCHED. Skip changes onboarding **routing only**. Do not touch `agent-runner.ts getUserApiKey`, `byok.ts`, `byok-lease.ts`, `byok-resolver.ts`, or `api_keys`. The chat-time gate (`getUserApiKey` → `KeyInvalidError` before any Anthropic call) remains authoritative. | Closes the credential-leak/auth-bypass worry: no keyless session can reach paid Anthropic calls; skip cannot pre-seed any lease/delegation path. |
| 12 | Visual design: no Pencil wireframes. Surfaces are minor modifications to existing components (a link on `/setup-key`, a dismissible banner mirroring the 012/049 banner pattern, an in-chat error state). Follow established component/token conventions. | YAGNI — no new screens; reuse existing patterns. |

## Open Questions

1. **"Granted but not yet accepted" delegation state.** A user who has been granted a
   delegation but hasn't accepted the current Side Letter version has **no effective
   key** (resolver fail-closes). For these users the right surface is the **delegation
   acceptance flow**, not "add your own key." Does the existing consent-gate work
   (#4627) already prompt acceptance on login/dashboard? If not, the banner/CTA should
   branch: pending-delegation → "Accept the delegation to start running tasks"; truly
   keyless → "Add your API key". Decide at plan time whether branching is in-scope or a
   fast-follow.
2. **Banner placement/dismissibility.** Persistent-but-recurring vs dismissible-per-
   session — mirror whichever 012/049 banner behavior fits. (Lean: non-dismissible
   while keyless, since the capability is genuinely blocked.)
3. **Skip landing destination edge case.** If repo is already connected for a skipper
   (unlikely pre-key, but possible), land on `/dashboard` instead of `/connect-repo`.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Skip is the right call only if paired with a persistent, concrete
"tasks disabled" dashboard banner + Settings CTA — without it, skip is just a quieter
dead-end. Settings already exists (`/dashboard/settings/services`, `KeyRotationForm`),
so "set later in Settings" is honest today; do not build a new Settings page. Verify
the dashboard has non-chat keyless value (browse KB / project setup) or skip merely
relocates the wall.

### Engineering (CTO)

**Summary:** Persist skip as nullable `setup_key_skipped_at` on `public.users`
(mirrors mig 012/049; next is 085). Central hazard is the chat-time hard-redirect to
`/setup-key` creating a skip→chat→/setup-key loop — fix by converting it to an in-chat
CTA. Enforcement path (`getUserApiKey` → `KeyInvalidError`) must stay untouched; skip
is routing-only, so no keyless session can reach paid calls. Small change set: 1
additive migration + ~4 localized edits + helper + banner.

### Legal (CLO)

**Summary:** Legally a near no-op — no change to encryption claim, data collection,
DPA, or the three-doc privacy rule (no new processing activity). One worth-doing copy
fix: "won't work well" understates reality and omits that the Anthropic account is
separate and paid; strengthen to "requires … separate, paid Anthropic account …
anytime in Settings." Disclosure-strengthening, safe to ship without external counsel.

## User-Brand Impact

- **Artifact:** the skip path + degraded-state surfaces on the BYOK onboarding flow.
- **Vector:** (a) credential/enforcement — a skip that weakened the key requirement
  could let keyless sessions reach paid Anthropic calls; (b) trust/churn — a soft or
  buried warning that users blow past then feel misled by; a redirect loop that traps
  skippers.
- **Threshold:** `single-user incident`. A single skipped (or delegated) user hitting
  a loop, a silent dead-end, or a misleading warning is a brand-survival event for a
  non-technical founder.
- **Mitigations baked into decisions:** enforcement untouched (D11), loop broken via
  in-chat CTA (D7), delegation-aware gating so delegated users are never warned/trapped
  (D2-D5), honest concrete copy (D10), persistent banner (D8).

## Capability Gaps

None. The `supabase` skill covers the additive migration; the existing
`useOnboarding.updateUserField` path (used by mig 012/049 flags) covers skip
persistence; `resolve_byok_key_owner` (mig 083/084) is the existing authoritative
resolver the new TS helper wraps. Evidence: `find apps/web-platform/app -path
'*settings*'` confirmed `/dashboard/settings/services/page.tsx` +
`components/settings/key-rotation-form.tsx`; `ls supabase/migrations | grep -iE
'onboard|explainer'` confirmed 012/049; migrations 083/084 read directly.
