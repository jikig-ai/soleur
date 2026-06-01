---
date: 2026-05-31
topic: invite-accept-membership-byok
status: complete
lane: cross-domain
brand_survival_threshold: single-user incident
user_brand_critical: true
requires_cpo_signoff: true
---

# Brainstorm: Keyless Invitee Membership Deadlock + Owner Delegation Prompt

## What We're Building

Fix the live bug where a **keyless workspace invitee never completes membership
acceptance**, so the owner's invite stays `Pending` and the invitee lands in
their own empty isolated workspace instead of the shared one. Then close the
onboarding loop with a **post-membership owner prompt to delegate a BYOK key**.

Reported symptom (operator screenshots, 2026-05-31): `ops@jikigai.com` invited
`jean.deruelle@gmail.com`; invite accepted + account created, but the owner's
Members tab still shows the invite under **Pending invites**, and the invitee
signed in to a brand-new standalone account ("Tasks are disabled until you add a
key" / "No repo connected") with no visibility of the shared workspace.

## Root Cause (confirmed by code reading — original hypothesis REFUTED)

The original hypothesis ("the accept RPC never writes the membership row") is
**wrong**. `accept_workspace_invitation` (migration `075:273-351`), the
`/invite/[token]` page, and `/api/workspace/accept-invite` are all correct —
membership **is** written the instant "Accept" is clicked, and no key is
required at that page. The defect is upstream: **a keyless invitee never reaches
an Accept surface.**

Three things conspire:

1. **Acceptance is coupled to a mandatory key+repo funnel.** PR #4641 (merged
   2026-05-29) threaded the invite target through `signup → accept-terms →
   setup-key → connect-repo → auto-return to /invite → Accept`. The strand point
   is `app/api/accept-terms/route.ts` `getRedirectDestination` (lines 19-47):
   for a keyless user it wraps the invite next-hop **inside**
   `/setup-key?redirectTo=<invite>`. A keyless invitee (no paid Anthropic
   account) stalls at `/setup-key`, abandons, and on next login the callback
   provisions them a fresh **isolated solo workspace** (an invariant, not a bug
   — see below). The `accept_workspace_invitation` RPC is **never reached**.
   PR #4641's own post-merge verification box ("confirm the `workspace_members`
   row lands") was **never checked**.

2. **The recovery surface is under-mounted.** `PendingInviteBanner` (one-click
   accept-from-dashboard) is mounted **only** on `dashboard/chat/layout.tsx`, and
   chat is itself key-gated. A stranded invitee on Knowledge Base never sees it.

3. **BYOK delegation can't rescue them — it's the other half of the deadlock.**
   Delegations shipped (#4508, #4627; migrations 064/074/083/084) as
   **post-membership, opt-in, consent-gated** — a DB CHECK requires both parties
   to already be `workspace_members`. So a keyless invitee can't get a delegated
   key until they're a member, and can't become a member because acceptance is
   buried behind key setup. Chicken-and-egg.

## Why This Approach (Accept-first + post-join owner prompt)

**Membership is a grant of access to existing shared state, not a fresh
provisioning funnel.** The Members tab promise — "All members share the same
workspace data, agents, and billing" — means a member should land in the shared
workspace and see its repo/KB/agents/inbox immediately (viewing ungated; task
execution gated at chat-time). Treating a joiner like a net-new solo signup (the
#4641 funnel) is a category error. Accepting first writes the `workspace_members`
row immediately, which **also flips the owner's invite from Pending → Active for
free** (fixes symptom 1).

**CTO correction — the fix is redirect-precedence, NOT suppressing provisioning.**
The isolated solo workspace (`callback/route.ts:317-389` `ensureWorkspaceProvisioned`)
is **invariant-critical** (`workspace.id === user.id`, migration 053 §1.1.7 N2);
every user needs a home workspace and the accept RPC *adds* an org membership
rather than replacing it. Do NOT gate provisioning. The load-bearing change is
making a valid `/invite/` next-hop **outrank** the `/setup-key` gate in
`callback/route.ts:238-275` + `accept-terms/route.ts:19-47`, and unwinding the
`/setup-key?redirectTo=<invite>` wrapper. **No migration. No new schema.**

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Accept-first reorder.** A valid `/invite/<token>` next-hop short-circuits to the invite page BEFORE `shouldRouteToSetupKey` is consulted. | Root-cause fix. Edit sites: `accept-terms/route.ts:19-47`, `callback/route.ts:238-275`. |
| 2 | **Do NOT suppress solo-workspace provisioning.** | `workspace.id === user.id` is a permanent invariant (ADR-038 / mig 053). Accept adds membership, doesn't replace home workspace. |
| 3 | **Do NOT steer invitees through `connect-repo`/`setup-key`.** Repo is connected at the workspace level; a member repointing it is a data-integrity risk. | Member joins existing workspace; key setup becomes member-initiated & optional. |
| 4 | **Owner delegation prompt** inline on the keyless member's Members-tab row, beside the existing `DelegationToggle`. Trigger: member is keyless (`userHasEffectiveByokKey(memberId, {onErrorReturn:false})` === false) AND no delegation from anyone. CTA "Share a key" (reuses #4508 toggle) + low-emphasis "or ask them to add their own" text link. No modal, no auto-delegate. | Closes the keyless loop using shipped delegation infra; keeps the owner's spend an explicit, consent-gated click. |
| 5 | **Member-side non-dead-end empty state.** Replace the solo "requires a separate paid Anthropic account" copy for a joiner with "You can browse this workspace, but running tasks needs a key — ask your owner to share one, or add your own." Reuse the existing `pendingDelegation` banner branch + `no-api-key-banner.tsx`. | The current copy is correct for a solo user but discouraging/wrong for a joiner with a delegating owner. |
| 6 | **Accept screen MUST render the shared-data/billing visibility disclosure (Art. 13) at accept-time.** | CLO guardrail — T&C is the platform contract, not notice that all members share workspace data/agents/billing. |
| 7 | **T&C-record-before-membership-write is a hard ordering invariant.** | Lawful basis recorded before read access is granted. accept-terms precedes /invite in the chain, so structurally preserved — must not be reordered by a refactor. |
| 8 | **Owner prompt creates the GRANT only — never writes a `byok_delegation_acceptances` (074) row on the grantee's behalf.** | CLO guardrail (Art. 7). Lease stays SQL-gated on grantee consent in `resolve_byok_key_owner` (083/084). |
| 9 | **Ship as TWO PRs.** PR1 = redirect-precedence fix (brand-survival, ships first, doesn't wait on UI). PR2 = owner delegation prompt + member empty state. | CTO recommendation. |
| 10 | **BYOK-at-invite-time = NO (decided, do not re-litigate).** | DB CHECK requires both parties be members; consent-gated lease (Art. 26). Keys are per-user (HKDF on userId), never workspace-shared. The answer to "where does the owner delegate?" = post-membership, per-member Members-tab toggle. |

## Open Questions

- **Deploy check (PR1 prereq / parallel):** Is prod actually on #4641? The desktop
  app may be a stale build. If prod predates #4641, part of the live symptom is a
  deploy gap — but the coupling defect remains regardless, so the fix proceeds.
- **N-member key resolution cost:** `userHasEffectiveByokKey` is one service-role
  RPC per member. Batch or cap for large member lists (v1 lists are tiny — fine,
  but note it).
- **Flag gating:** Confirm the accept-first redirect itself is NOT gated behind
  `FLAG_TEAM_WORKSPACE_INVITE` — a flag-OFF invitee must still not be stranded.
- **Reject-vector tests:** accept-first adds a hop carrying `/invite/<token>`;
  every hop must re-validate via `safeReturnTo()` (already allowlists `/invite/`).
  Mandatory open-redirect reject tests on raw + percent-decoded forms.

## Domain Assessments

**Assessed:** Engineering (CTO), Product (CPO), Legal (CLO)

### Engineering (CTO)

**Summary:** GO. Single load-bearing change = redirect-precedence reordering so a
valid `/invite/` next-hop outranks `/setup-key` (`callback/route.ts:238-275`,
`accept-terms/route.ts:19-47`); the "suppress solo-workspace provisioning"
framing is a no-op-to-avoid (invariant-critical). Owner prompt needs a new
`hasEffectiveKey` field on the membership resolver via
`userHasEffectiveByokKey(memberId, {onErrorReturn:false})` (never read `api_keys`
directly). No migration. Open-redirect safe (per-hop `safeReturnTo()`
re-validation). T&C-first ordering structurally preserved. Ship as two PRs.

### Product (CPO)

**Summary:** Accept-first → land keyless in the shared workspace with full read
access (KB/repo/agents/inbox visible; tasks gated at chat-time) is the correct
experience and flips the owner's invite to Active for free. Do NOT re-run
connect-repo for invitees (data-integrity risk). Owner prompt = inline row hint
beside the existing `DelegationToggle`, "Share a key" CTA + low-emphasis "ask
them to add their own" link, no auto-delegate. Defer owner email notification.
Resist workspace-shared keys. Minimal-right-scope confirmed.

### Legal (CLO)

**Summary:** GO. The BYOK lease is SQL-gated at `resolve_byok_key_owner`
(083/084) independent of when membership is written, so moving membership earlier
cannot reach the key path or enable pre-consent spend. Guardrails to carry
forward: (1) accept screen renders the shared-data/billing disclosure (Art. 13)
at accept-time; (2) T&C-before-membership-write is a hard invariant; (3) owner
prompt creates GRANT only, never the grantee's 074 acceptance row. No new Art. 33
exposure.

## Inherited Contracts (do not re-litigate)

- `feat-team-workspace-multi-user` (#4229): membership model + **per-user** BYOK keys.
- `feat-workspace-invite-acceptance`: invitation table + accept-RPC contract.
- `feat-byok-delegations-4232` (#4232) + `feat-byok-delegation-consent` (#4625):
  delegation is **post-membership, opt-in, consent-gated**.
- `feat-one-shot-fix-invite-accept-workspace-linking` (PR #4641): the partial
  fix this work completes — it wired the funnel but left keyless invitees
  stranded.
