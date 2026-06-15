---
title: "Recent Conversations rail showed empty for joined workspace members — repo_url source-of-truth divergence (ADR-044 consumer-sweep gap)"
date: 2026-06-15
incident_pr: 5317
incident_window: "since ADR-044 read-cutover (exact landing date unverified) — surfaced 2026-06-15"
recovery_at: "2026-06-15 (PR #5317 merge)"
suspected_change: "ADR-044 moved the repo source-of-truth to workspaces.repo_url but left the client hook use-conversations.ts reading the deprecated users.repo_url"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - availability/UX defect (empty Recent Conversations rail)
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a"
---

## Actor key

- `agent` — Claude Code did this autonomously.
- `agent-with-ack` — Claude Code did this AFTER operator confirmation.
- `human` — Operator did this directly.

# Incident Overview

The **Recent Conversations** rail in the chat shell rendered the empty state
("No conversations yet. — Start one →") even while a user was actively in a
conversation with the Soleur Concierge. The client hook `use-conversations.ts`
scoped the conversation list by the **deprecated** `users.repo_url` column,
while the server stamps every conversation with `workspaces.repo_url` (the
ADR-044 source of truth). For a joined workspace member (whose own
`users.repo_url` is empty) and for any user whose repo state lived only in
`workspaces` post-ADR-044, the two diverged and the client filtered out every
conversation, hard-returning an empty list.

## Status

resolved — fixed in PR #5317.

## Symptom

Recent Conversations rail permanently empty ("No conversations yet") for
affected users despite active/recent conversations existing and being correctly
persisted server-side. No error surfaced; the rail simply read as "you have no
conversations."

## Incident Timeline

- **Start time (detected):** 2026-06-15 (operator report with screenshot)
- **End time (recovered):** 2026-06-15 (PR #5317)
- **Duration (MTTR):** same-day (fix authored, reviewed, and shipped in one session)

| Actor | Time (UTC) | Action |
|---|---|---|
| human | 2026-06-15 | Operator reported the empty rail via `/soleur:go` with a screenshot. |
| agent | 2026-06-15 | Root cause traced to client `users.repo_url` vs server `workspaces.repo_url` divergence (ADR-044). |
| agent | 2026-06-15 | Fix: hook reads repo scope from GET /api/workspace/active-repo; sibling tests swept; PR #5317 shipped. |

## Participants and Systems Involved

Soleur web-platform chat shell (`apps/web-platform`): `hooks/use-conversations.ts`,
`components/chat/conversations-rail.tsx`, `app/api/workspace/active-repo/route.ts`
(canonical repo-scope source). No infrastructure or external vendor involved.

## Detection (+ MTTD)

- **How detected:** external/manual — operator noticed the empty rail while in a conversation. Not caught by monitoring (the empty list returns HTTP 200 with no error; there is no metric for "rail empty while conversation active").
- **MTTD:** unknown — the divergence existed silently since ADR-044's read-cutover; detection was incidental on operator use.

## Triggered by

System — an internal architecture migration (ADR-044) that re-pointed the repo
source of truth without sweeping all client read consumers.

## Root-cause hypothesis (triage)

| Hypothesis | Supporting evidence | Disconfirming evidence | Status |
|---|---|---|---|
| Conversations not persisted until some event | — | `createConversation` persists immediately and aborts if no repo connected (`ws-handler.ts:855`) | rejected |
| List query scoped by the wrong repo_url source | client reads `users.repo_url`; server stamps `workspaces.repo_url` (ADR-044) | — | confirmed |
| RLS hides the rows | — | conversations SELECT policies (075/059) have no repo_url predicate; empty list is the client app-filter | rejected |

## Resolution

`use-conversations.ts` now derives `repoUrl` + `workspaceId` from
`GET /api/workspace/active-repo` (the ADR-044-correct, IDOR-safe, self-healing
route already consumed by `use-active-repo.ts`), instead of reading
`users.repo_url`. The dead cross-tab `users` UPDATE realtime channel and the
now-unused `normalizeRepoUrl` import were removed. Review additionally added a
`workspace_id` filter to the list query (matching the server-side list tool, to
separate two of a user's own workspaces sharing a repo) and a retryable rail
error state so a transient route failure no longer flashes the misleading empty
CTA.

## Recovery verification

Full web-platform vitest suite green (787 files / 9898 tests, 0 failures) +
`tsc --noEmit` clean. New RED→GREEN regression test
(`conversations-active-repo-scope.test.tsx`) fails against the pre-fix hook and
passes against the fix. Post-merge: `web-platform-release.yml` redeploys on
merge; `/soleur:postmerge` verifies production health.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why was the rail empty?** The client filtered the conversation list by a `repo_url` that didn't match the stamped value.
2. **Why didn't it match?** The client read `users.repo_url`; the server stamps `workspaces.repo_url`.
3. **Why did those diverge?** ADR-044 moved the repo source of truth to `workspaces.repo_url` and left `users.repo_url` deprecated/empty for joined members.
4. **Why did the client keep reading the deprecated column?** ADR-044's consumer migration swept server read paths but missed this client hook — a read consumer that "appeared to work" for the solo-owner case (where `users.repo_url` was still populated) and only broke for joined members / post-cutover users.
5. **Why was it not caught?** The empty list returns HTTP 200 with no error; there is no test or metric distinguishing "genuinely no conversations" from "conversations filtered out by a divergent scope," so it ran silently until an operator noticed.

**Final root cause:** an ADR-044 source-of-truth migration that did not sweep every client read consumer — the same class as the 2026-06-02 chat-RLS outage (migration made a column required but INSERT sites weren't swept).

## Versions of Components

- **Version(s) that triggered:** web-platform builds since the ADR-044 read-cutover (exact version unverified).
- **Version(s) that restored:** the build merging PR #5317.

## Impact details

### Services Impacted

Recent Conversations rail (chat shell navigation) — read-only display. Conversation persistence, dispatch, and RLS isolation were unaffected.

### Customer Impact (by role)

- Prospect: none (unauthenticated, no rail).
- Authenticated app user (joined workspace member): **affected** — empty rail, could not navigate back to prior conversations from the nav rail.
- Authenticated app user (solo owner, pre-cutover `users.repo_url` populated): not affected (the deprecated column still matched).
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none (no billing surface touched).
- OAuth installation owner: none.

### Revenue Impact

None.

### Team Impact

Single same-day session (root-cause trace + fix + review + ship).

## Lessons Learned

### Where we got lucky

The divergence only ever *hid* the user's own conversations (under-display). RLS independently gates by `user_id`/workspace membership, so the wrong-source read never leaked another tenant's conversations — a cross-tenant leak was structurally impossible, not merely avoided.

### What went well

Root cause was traced by reading the actual producer/consumer (server stamp vs client read) rather than trusting the symptom; the fix adopted the existing canonical client pattern (`use-active-repo.ts`) instead of inventing one; multi-agent review caught a second same-class gap (list query missing the `workspace_id` discriminator) and the unsurfaced error state.

### What went wrong

An architecture migration (ADR-044) changed a source of truth without an enforced "sweep every consumer to 0" check, so a client read consumer silently kept the old, now-divergent source — invisible because the failure returns 200 with an empty list.

## Action Items & Follow-ups

_No action items — incident fully resolved in the source PR with no residual work._
