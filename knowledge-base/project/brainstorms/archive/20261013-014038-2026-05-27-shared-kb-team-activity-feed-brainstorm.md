---
date: 2026-05-27
status: committed
decision: three-pr-decomposition-behind-invite-flag
brand_survival_threshold: single-user incident
lane: cross-domain
related:
  - knowledge-base/project/brainstorms/2026-05-21-team-workspace-multi-user-brainstorm.md
  - knowledge-base/project/brainstorms/2026-05-25-attachments-workspace-shared-pr2-bundle-brainstorm.md
  - knowledge-base/project/brainstorms/2026-04-10-kb-document-sharing-brainstorm.md
  - knowledge-base/project/brainstorms/2026-04-12-conversation-history-visibility-brainstorm.md
  - knowledge-base/product/roadmap.md
closes_issues:
  - 4521
---

# Shared Knowledge Base + Team Activity Feed (Phase 4) Brainstorm

## What We're Building

Three collaboration features for team workspaces, decomposed into independent PRs behind the existing `TEAM_WORKSPACE_INVITE_ENABLED` feature flag:

1. **PR-A: Conversation visibility controls** — per-conversation opt-in sharing within a workspace (default private)
2. **PR-B: Team activity feed** — dedicated `workspace_activity` table with polling-based UI showing membership, conversation, KB, and agent-run events
3. **PR-C: KB files metadata table** — hybrid DB metadata + filesystem content model with per-file visibility and uploader attribution

## User-Brand Impact

`USER_BRAND_CRITICAL=true` — operator selected all three failure modes.

**Artifact at risk:** KB files, conversation threads, activity feed entries.

**Vectors named:**

1. **Trust breach / cross-tenant read** — RLS predicate misconfiguration on any of the three surfaces could expose User A's private conversations or KB files to User B from another org, or to an unauthorized workspace member. Load-bearing risk per CTO + CLO.
2. **Data loss / corruption** — shared KB files or conversations could be lost, duplicated, or corrupted during cross-workspace operations or member departure cascades. WORM trigger + FK CASCADE interactions (per 2026-05-25 Art-17 cascade deadlock learning) are a known risk surface.
3. **User data exposure** — activity feed entries could leak user behavior metadata (conversation creation patterns, agent run frequency) to unauthorized viewers. Activity feed is a net-new data processing surface with zero existing legal coverage.

**Threshold:** `single-user incident` — one mis-written RLS predicate that leaks a founder's private conversation to an invited workspace member is brand-survival territory.

## Lane

`cross-domain` (forced by `USER_BRAND_CRITICAL=true`).

## Why This Approach

### Three-PR decomposition

The CTO recommended sequencing conversations → activity feed → KB metadata based on readiness:
- **Conversations**: DB layer is 100% done (mig 059). Gap is client-side call-site sweep + visibility column.
- **Activity feed**: Net-new but independent of KB. Needs architecture decision (resolved: dedicated table + polling).
- **KB metadata**: Blocked on the non-existence of `kb_files`/`kb_chunks` tables. Largest scope.

Each PR ships behind the same `TEAM_WORKSPACE_INVITE_ENABLED` flag. Zero behavior change in production until flag flip.

### Key premise corrections

The issue body (#4521) assumed `kb_files`, `kb_chunks`, and `kb_sync_history` are Postgres tables. **This is incorrect:**
- `kb_files` and `kb_chunks` do NOT exist (mig 073 explicitly audited this)
- `kb_sync_history` is a JSONB column on `public.users`, not a standalone table
- KB content lives on the filesystem at `workspace_path`; only `kb_share_links` is a real KB table in Postgres

KB files are already implicitly shared within a workspace because both members share the same filesystem directory via `workspace_path`. The hybrid model (DB metadata + filesystem content) creates the missing visibility/attribution layer.

### Conversation visibility: default private, opt-in share

The current RLS (mig 059) makes ALL workspace conversations visible to ALL members unconditionally. This is a brand-survival risk: flipping the invite flag ON would instantly expose every pre-invite conversation (including those with sensitive BYOK cost data, personal brainstorms, etc.) to new members.

The `default private` model:
- Adds `visibility TEXT CHECK (visibility IN ('private','workspace')) DEFAULT 'private'` to conversations
- Updates RLS: `(user_id = auth.uid()) OR (visibility = 'workspace' AND is_workspace_member(workspace_id, auth.uid()))`
- Backfills all existing conversations to `'private'` — safe default
- Requires share/unshare toggle in conversation UI

### Activity feed: dedicated table + polling (not Realtime)

Migration 039 removed `messages` from the Supabase Realtime publication due to disk I/O regression. Activity events are similarly high-volume. The chosen architecture:
- INSERT-only `workspace_activity` table, NOT in `supabase_realtime` publication
- Client polls on page load + 30s interval (established pattern in `use-conversations.ts`)
- pg_cron 90-day retention purge to bound table growth
- SECURITY DEFINER RPC writers only — no client INSERT policy

## Key Decisions

| # | Decision | Rationale | Source |
|---|----------|-----------|--------|
| 1 | **Three independent PRs** (A: conversations, B: activity, C: KB metadata) | Smallest blast radius; each independently reviewable and testable. CTO recommended this sequencing. | CTO + operator |
| 2 | **All behind existing `TEAM_WORKSPACE_INVITE_ENABLED` flag** | Zero behavior change in production. Flag is OFF. | CPO, CTO |
| 3 | **Conversation visibility: default private, opt-in share** | Prevents pre-invite conversation exposure on flag flip. Brand-survival prerequisite. | Operator choice; CTO brand-survival analysis |
| 4 | **KB model: hybrid DB metadata + filesystem content** | `kb_files` table for visibility/attribution/workspace_id; actual content stays on disk. Designed for future embeddings extension. | Operator choice; CTO premise correction |
| 5 | **Activity feed: dedicated table + polling** | Avoids mig-039 disk I/O regression. Queryable, paginated, persistent. pg_cron 90-day retention. | Operator choice; CTO architecture options |
| 6 | **Activity event types: membership + conversations + KB + agent runs** | Medium volume (~50-200 events/day for small team). Excludes per-message events (high volume). | Operator choice |
| 7 | **`/soleur:gdpr-gate` mandatory at plan Phase 2.7** for all three PRs | All three components involve PII, schemas, and API routes touching regulated data. Per `hr-gdpr-gate-on-regulated-data-surfaces`. | CLO |
| 8 | **Legal scaffolding ships IN LOCKSTEP with code PRs** | Per PR #4289 precedent pattern. Activity feed needs Privacy Policy, DPD, GDPR Policy, Art. 30 amendments. KB needs PA-2 recipients amendment. | CLO |
| 9 | **Fix latent bug: `ws-handler.ts:806` conversation INSERT omits `workspace_id`** | Discovered by repo-research. Must be fixed regardless of #4521 scope. | Repo-research |
| 10 | **20+ `.from("conversations")` call sites need sentinel sweep** | Per `hr-write-boundary-sentinel-sweep-all-write-sites`. Client code filters by `user_id`; must audit each for workspace-scoped semantics. | CTO |

## Open Questions

1. **Conversation INSERT workspace_id gap** — `ws-handler.ts:806` doesn't include `workspace_id`. Is this covered by a DB trigger/default, or is it a latent bug that only works because of the N2 invariant (solo user: workspace_id === user_id)? **Must verify before PR-A.**
2. **kb_files table schema alignment with embeddings ADR** (`feat-adr-embeddings-kb-retrieval-4206`) — if that ADR introduces `kb_files`/`kb_chunks`, PR-C must align. If the ADR is unplanned, PR-C defines the schema independently.
3. **Activity feed DSAR coverage** — if `workspace_activity` is persisted, it must be added to `DSAR_TABLE_ALLOWLIST` with OR-semantics over `actor_user_id`. What about `target_user_id` fields (e.g., "User A shared conversation with User B")?
4. **Art-17 cascade for activity feed** — follow WORM pattern with anonymise-RPC? Or treat as ephemeral (90-day purge covers it)? CLO recommends WORM + anonymise-RPC for consistency.
5. **Realtime subscription filter widening** — `use-conversations.ts:239` uses `user_id=eq.${userId}`. Supabase Realtime's `filter` accepts one equality predicate per subscription. Widening to `workspace_id` requires client-side cross-user drop logic. How does this interact with opt-in visibility?
6. **`action_sends` workspace-keying** — still uses `user_id = auth.uid()` RLS (mig 051). Needs sweep to `is_workspace_member` if activity feed includes leader-loop events. Separate PR or bundle with PR-B?
7. **TC_VERSION bump** — if ToS §3b is amended for activity feed + KB visibility, TC_VERSION 2.2.0 may need bump to 2.3.0 per `knowledge-base/legal/tc-version-bump-policy.md`.

## Deferred Items

| Item | Why deferred | Re-evaluation criteria |
|------|-------------|----------------------|
| Cross-workspace KB access | Different workspaces sharing KB files requires a sharing model that doesn't exist. Current scope is intra-workspace only. | When workspace federations or project-sharing across orgs becomes a user request. |
| Per-message activity events | High volume — risks mig-039 disk I/O regression. | When message volume data from early workspace usage shows the actual write rate is manageable. |
| KB embeddings/retrieval | Separate ADR (`feat-adr-embeddings-kb-retrieval-4206`). PR-C's `kb_files` schema is designed to be extended. | When the embeddings ADR is written and planned. |
| Supabase Realtime for activity feed | Polling is sufficient for small teams. Realtime adds disk I/O risk. | When polling latency becomes a user complaint (>30s feels stale). |
| Conversation participant model | True multi-participant conversations (vs. visibility toggle). | When teams request collaborative real-time conversations, not just visibility. |

## Productize Candidate

`soleur:rls-cascade-to-direct` skill — the pattern of widening per-user RLS predicates to workspace-scoped dual predicates repeats across conversations, messages, KB, attachments, and future tables. Each instance follows the same shape: add `visibility` column, update RLS predicate to `(owner OR (visible AND member))`, sweep client call sites. A codified skill could reduce the per-table cost from days to hours.

## Domain Assessments

**Assessed:** Product (CPO), Engineering (CTO), Legal (CLO)

### Product (CPO)

**Summary:** Strong "keep deferred" recommendation. Re-evaluation criteria not met (zero co-members, invite flag OFF). Validated thesis is solo founders — team collaboration is a thesis expansion, not a feature. Phase 4 exit criteria are about solo-founder validation. However, if brainstorming proceeds, conversations are the most ready component (DB done), and KB architecture mismatch (filesystem vs assumed DB) must be corrected in the issue framing.

### Engineering (CTO)

**Summary:** `kb_files`/`kb_chunks` tables do not exist — issue premise is partially false. Conversations RLS is already workspace-keyed (mig 059) but client code is not: 20+ `.from("conversations")` call sites filter by `user_id` and need sweeping. Brand-survival risk: flag flip without opt-in visibility exposes ALL pre-invite conversations. Activity feed is net-new; disk I/O concern from mig 039 precedent recommends polling over Realtime. Recommended sequence: conversations → activity feed → KB metadata. Estimated total: week+ for all three, days per component.

### Legal (CLO)

**Summary:** Shared conversations are legally well-covered (ToS §3b, Privacy §4.11, DPD §2.3(u), Art. 30 PA-2 — all shipped in PRs #4289, #4351, #4491). KB access partially covered (DPD names the tables but Privacy Policy and Art. 30 recipients limb need amendment). Activity feed is completely uncovered — net-new data processing surface requiring disclosure across all six legal documents, new Art. 30 processing activity, DSAR coverage, and Art-17 cascade decision. Two design decisions gate legal work: (a) activity feed persistence model (resolved: dedicated table with WORM pattern), (b) KB file ownership model (resolved: per-user upload with workspace visibility). `/soleur:gdpr-gate` mandatory at plan Phase 2.7.

## Capability Gaps

None identified by any domain leader. The engineering, legal, and product domains have the necessary agents and skills to execute all three components once the architecture decisions are resolved.

## Session Errors

None.
