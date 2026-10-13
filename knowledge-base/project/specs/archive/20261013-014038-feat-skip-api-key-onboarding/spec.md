---
feature: skip-api-key-onboarding
date: 2026-05-29
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
branch: feat-skip-api-key-onboarding
pr: 4640
brainstorm: knowledge-base/project/brainstorms/2026-05-29-skip-api-key-onboarding-brainstorm.md
---

# Spec: Skippable "Connect your API key" onboarding (delegation-aware)

## Problem Statement

The "Connect your API key" step (`app/(auth)/setup-key/page.tsx`) is a mandatory
onboarding gate: the auth callback and `accept-terms` force-redirect any user without
a valid own Anthropic key to `/setup-key`, with no way past. Two problems:

1. **Non-technical founders bounce** at a raw `sk-ant-...` field before seeing any
   product value. They should be able to skip and explore, with an honest warning.
2. **Delegated users are wrongly trapped (pre-existing bug).** The redirect checks only
   the user's own `api_keys` row, ignoring BYOK delegation. A workspace member with a
   valid inbound delegation but no own key is force-redirected to `/setup-key` today,
   even though they can already run on the owner's delegated key.

## Goals

- G1: Let users skip the API-key step and continue onboarding, with a factual warning.
- G2: Make all onboarding key gates **effective-key-aware** (own valid key OR active,
  consented, non-withdrawn inbound delegation) — fixing the delegated-user trap.
- G3: Never strand or loop a keyless user; provide durable, honest degraded-state UX.
- G4: Keep BYOK enforcement strictly unchanged — no keyless session reaches paid calls.
- G5: "Set it later in Settings" must point at a real, working surface.

## Non-Goals

- NG1: No change to key storage, encryption, validation, `api_keys`, or the runtime
  key-resolution / lease / enforcement path.
- NG2: No new Settings page (`/dashboard/settings/services` + `KeyRotationForm` exist).
- NG3: No change to the delegation grant/consent/withdrawal model (mig 064/074/083/084).
- NG4: Building a dedicated "accept your pending delegation" flow is out of scope unless
  it already exists (see FR7 / Open Question 1) — fast-follow if needed.

## Functional Requirements

- FR1: `/setup-key` shows a "Set up later" action alongside "Save key". Activating it
  persists the skip and advances onboarding (→ `/connect-repo`, or `/dashboard` if repo
  already connected). It does NOT save any key.
- FR2: A skipped user is not force-redirected to `/setup-key` on subsequent logins.
- FR3: The auth callback and `accept-terms` redirect to `/setup-key` only when the user
  has **no effective key AND has not skipped**. Delegated users (effective key present)
  skip the gate entirely and proceed to repo-check/dashboard.
- FR4: Warning copy on the skip affordance is factual and concrete (D10): requires a
  key to function; account is separate and paid; addable anytime in Settings; tasks
  disabled until then.
- FR5: A persistent dashboard banner appears only when the user has no effective key,
  stating "Tasks are disabled until you add a key" with a one-click CTA to
  `/dashboard/settings/services`. Hidden for users with an effective key (own or
  delegated).
- FR6: Chat-time `key_invalid` no longer hard-redirects to `/setup-key`; it renders an
  in-chat "Add your API key" error/CTA (link to `/setup-key`) and stops the socket —
  breaking the skip→chat→/setup-key loop.
- FR7: (Conditional) If a user has a granted-but-not-accepted delegation (no effective
  key yet), the banner/CTA should point to the delegation acceptance flow rather than
  "add your own key", IF that flow exists today. Otherwise treat as keyless and
  fast-follow. Resolve at plan time.

## Technical Requirements

- TR1: Migration **085** adds `setup_key_skipped_at timestamptz NULL` to `public.users`
  (additive, no backfill), with matching `085_*.down.sql`. Mirror mig 012/049 shape.
- TR2: New helper `userHasEffectiveByokKey(userId, workspaceId, serviceClient):
  Promise<boolean>` wrapping the existing `resolve_byok_key_owner(caller, workspace)`
  RPC (non-empty result ⇒ true). Must mirror the runtime's org-level delegation
  feature-flag check (see `byok-resolver.ts resolveKeyOwnerThenLease`) so flag-disabled
  orgs don't count delegations. Single source of truth for FR3 and FR5.
- TR3: Skip persistence via the existing `useOnboarding.updateUserField` path (used by
  mig 012/049 flags) or an equivalent server write; do not invent a new mechanism.
- TR4: Edits are localized: `callback/route.ts` (~L233-242), `accept-terms/route.ts`
  `getRedirectDestination` (~L10-23), `setup-key/page.tsx`, `lib/ws-client.ts`
  (~L184-192), the dashboard banner component, and the new helper. Do NOT modify
  `agent-runner.ts getUserApiKey`, `byok.ts`, `byok-lease.ts`, `byok-resolver.ts` lease
  logic, or `api_keys`.
- TR5: `next/route` files keep HTTP-only exports (`cq-nextjs-route-files-http-only-exports`).
- TR6: Tests: redirect-gate unit coverage for the four effective-key states (own key /
  active delegation / granted-not-accepted / truly keyless) and skip-flag set; the
  in-chat CTA replaces redirect on `key_invalid`.

## Brand-Survival Threshold

`single-user incident` — a single skipped or delegated user hitting a loop, silent
dead-end, misleading warning, or (worst) a weakened enforcement path is a brand event
for a non-technical founder. The `user-impact-reviewer` agent is the load-bearing PR
gate; enforcement-path untouched (NG1/G4) is the hard invariant.
