---
title: "Spec — feat-4379-anthropic-leader-loop (PR-B, replaces PR-A deterministic stub)"
date: 2026-05-25
issue: 4379
umbrella: 4124
substrate_pr: 4378
brainstorm: knowledge-base/project/brainstorms/2026-05-25-pr-b-anthropic-leader-loop-brainstorm.md
lane: cross-domain
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
---

# Spec — PR-B Anthropic SDK leader-prompt loop

Tracking issue: #4379. Umbrella: #4124. Substrate PR (merged): #4378 (commit `7d5620a5`).

## Problem Statement

PR-A shipped a deterministic acknowledgment stub for the Today-card spawn buttons: every operator click produces a pre-templated PR comment (`pr-*` sources) or `soleur/acknowledged` issue label (everything else). The operator gets *acknowledgment* but no *autonomous action* — no review summary, no triage comment, no CVE-bump draft, no fix-the-link branch. The empty-result UX is closed at the *receipt* level (an artifact lands), but the brand promise of an autonomous engineering co-pilot is unmet.

PR-B replaces the deterministic stub with an Anthropic-SDK leader-prompt loop that produces per-action-class autonomous outputs. The change crosses architectural boundaries (first raw `@anthropic-ai/sdk` site inside `apps/web-platform/server/`), introduces new processing activity on operator data + third-party PII (PR diffs, issue bodies) routed to Anthropic, and amplifies the trust surface (autonomous AI writes vs deterministic acknowledgment).

## Goals

1. Replace `agent-on-spawn-requested.ts` step `post-acknowledgment` body with a leader-prompt loop driving `anthropic.messages.create` with tool-use rounds.
2. Ship 5 per-action-class leader prompts: `engineering.pr_review_pending`, `engineering.ci_failed`, `triage.p0p1_issue`, `security.cve_alert`, `knowledge.kb_drift`.
3. Author ADR-042 (Anthropic-SDK-inside-Inngest pattern) + ADR-041 (BYOK cap enforcement model) BEFORE any Anthropic SDK call lands.
4. Wire BYOK lease + cap enforcement: per-turn `runWithByokLease` + pre-call `record_byok_use_and_check_cap` check + `persistTurnCost` after each call. Build the `recordByokUseAndCheckCap` TS wrapper (greenfield).
5. Ship migration 065 adding `reversal_handle jsonb` / `current_turn smallint` / `current_turn_started_at timestamptz` / `cancellation_requested_at timestamptz` / `prompt_version text` columns on `action_sends`. Extend WORM trigger admit-list to admit UPDATEs on these new columns.
6. Ship Today-card operator UX suite: in-flight progress (Supabase Realtime on `action_sends`), cancellation (Stop button → `cancellation_requested_at`), per-output undo (Today-card Undo button → reverse via `reversal_handle`), per-spawn cost visibility (cumulative cost from `byok_audit` rows).
7. Append PA-22 entry to `knowledge-base/legal/article-30-register.md`; amend the Anthropic Vendor Mapping row (line 412) to add PA-22 to Activities.
8. Verify Anthropic Zero-Retention amendment status; document the gap in PA-22 (f) if unsigned.
9. Ship PII-scrub TOM: commit-author email redaction in the prompt-assembly step before any Anthropic call.
10. Reality-check `main` pre-implementation for sibling PRs touching `action_sends` / today-card / `agent-on-spawn-requested.ts` since PR-A merged (per learnings).

## Non-Goals (filed as follow-up issues before merge)

1. Full DPIA on PA-22 — autonomous AI-driven decisioning affecting third-party data subjects in PR diffs.
2. One-time operator consent banner + ToS clause update for AI-generated GitHub artifacts.
3. Article 22 automated-decisioning analysis.
4. Per-class max-turns caps (CFO's kb_drift=3, triage=4, cve=5 recommendation).
5. Per-class brand-survival tiering (CPO's Tier 1/2/3 staged ship).
6. Cross-installation spawn (one founder, multiple installations).
7. Per-founder spawn quota / rate-limit.
8. Transactional outbox between `action_sends` INSERT and `inngest.send`.
9. WS-push channel for in-flight progress (PR-B uses Supabase Realtime; WS push deferred).
10. Prompt fixture/regression infrastructure (golden-file tests on leader prompts).
11. Per-vendor DPA file scaffolding (the `knowledge-base/legal/data-processing-agreements/` directory doesn't exist; Anthropic DPA is a Vendor Mapping row).
12. CVSS classification source-of-truth for `cve_alert` severity-aware prompts (v1 uses GitHub Advisory `severity` field).

## Functional Requirements

### FR1 — Leader loop replaces `post-acknowledgment` body

For each `agent.spawn.requested` event, the Inngest function runs a per-turn loop:

- For each turn `n` in `[1..max_turns]`:
  1. `step.run("turn-${n}-cap-check", ...)`: invoke `recordByokUseAndCheckCap` with cumulative spend; if `kill_tripped`, terminate with `failure_reason = "byok_cap_exceeded"`.
  2. `step.run("turn-${n}-precheck-cost-ceiling", ...)`: if cumulative spend ≥ $2.00, terminate with `failure_reason = "cost_ceiling_exceeded"`.
  3. `step.run("turn-${n}-cancel-check", ...)`: if `action_sends.cancellation_requested_at IS NOT NULL`, terminate with `failure_reason = "cancelled_by_operator"`.
  4. `step.run("turn-${n}-progress-write", ...)`: UPDATE `action_sends.current_turn = ${n}`, `current_turn_started_at = now()`.
  5. `step.run("turn-${n}-claude", ...)`: `runWithByokLease(..., async () => anthropic.messages.create(...))`; then `persistTurnCost(...)` with usage including `cache_read_input_tokens` + `cache_creation_input_tokens`.
  6. For each `tool_use` block: `step.run("turn-${n}-tool-${i}", ...)` invokes the tool through `createGitHubAppClient` Octokit instance.
  7. If `stop_reason === "end_turn"`: write artifact URL + `reversal_handle` and exit loop.
  8. If `stop_reason === "tool_use"`: append `tool_result` blocks to next-turn messages.
  9. If turn `n === max_turns` reached: terminate with `failure_reason = "leader_max_turns_exceeded"`.

### FR2 — Per-class leader prompt registry

`apps/web-platform/server/inngest/leader-prompts/` (new directory) carries one file per action class:

- `engineering.pr_review_pending.ts`: system prompt + user prompt template + tools `[createPullRequestReviewComment, createComment]` + model `claude-sonnet-4-6` + max_turns 8 + max_tokens 4096
- `engineering.ci_failed.ts`: tools `[createComment]` + model Sonnet + max_turns 8
- `triage.p0p1_issue.ts`: tools `[addLabels, createComment]` + model `claude-haiku-4-5-20251001` + max_turns 8
- `security.cve_alert.ts`: tools `[createBranch, createBlob, createCommit, createPullRequest, createComment]` + model Sonnet + max_turns 8
- `knowledge.kb_drift.ts`: tools `[createBranch, createBlob, createCommit]` + model Haiku + max_turns 8

Each prompt module exports `{ systemPrompt, userPromptTemplate, tools, model, maxTurns, maxTokens, promptVersion }`. `promptVersion` is a sha256 hash of `(systemPrompt + userPromptTemplate + JSON.stringify(tools))`; written to `action_sends.prompt_version` at loop start so in-flight runs are deterministic against the prompt version they started with.

### FR3 — In-flight progress via Supabase Realtime

Today card subscribes to `action_sends` UPDATEs on its own row via Supabase Realtime. The card renders:

- `current_turn IS NULL`: "Acknowledged — agent starting…" (pre-turn-1 state, expected <500ms)
- `current_turn IS NOT NULL AND acknowledged_at IS NULL AND failure_reason IS NULL`: "Working — turn ${current_turn} of ${max_turns}, ${elapsed} elapsed" with a Stop button
- `acknowledged_at IS NOT NULL`: "Done — ${artifact_kind} at ${artifact_url}" with an Undo button (renders if `reversal_handle IS NOT NULL`)
- `failure_reason IS NOT NULL`: per-reason failure copy + Retry button (creates new `messages` row)

Subscription scope: authed channel scoped to `auth.uid() = action_sends.user_id` (RLS-respecting). If Supabase Realtime cannot respect RLS on subscribed columns, the card falls back to 2s polling on a new GET endpoint.

### FR4 — Cancellation flow

Today card "Stop" button → POST `/api/dashboard/today/[id]/cancel` → server route validates owner via RLS-aware `messages` SELECT → UPDATE `action_sends.cancellation_requested_at = now()` via service-role client. The Inngest function's `turn-${n}-cancel-check` step reads the column at the start of each turn and short-circuits with `failure_reason = "cancelled_by_operator"`. Mid-turn cancellation is not supported (turn completes; cancellation honored on next turn boundary).

### FR5 — Per-output undo

Each successful artifact emit writes a per-class `reversal_handle` to `action_sends`:

- PR comment: `{ kind: "pr_comment", owner, repo, comment_id }`
- Issue label: `{ kind: "issue_label", owner, repo, issue_number, label_name }`
- Draft branch: `{ kind: "branch", owner, repo, branch_ref }`
- Draft PR (CVE bump): `{ kind: "pr", owner, repo, pr_number, branch_ref }`

Today card "Undo" button → POST `/api/dashboard/today/[id]/undo` → reads `reversal_handle` → reverses via `createGitHubAppClient` Octokit (deleteComment / removeLabel / deleteRef). On success, clears `artifact_url` + `reversal_handle` and sets a new `undone_at` column.

### FR6 — Per-spawn cost visibility

Today card fetches cumulative cost from `byok_audit` rows joined on `actionSendId` (via a new query path on `/api/dashboard/today/[id]/cost`). Displays `Cost: $X.XX (Y turns)`. Refreshes on each Realtime UPDATE.

### FR7 — PII-scrub TOM

Prompt-assembly step (pre-Anthropic call) runs commit-author email redaction on any PR diff content piped to Anthropic. Replaces matches of `/[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/` with `<email-redacted>`. Excludes the operator's own email (`users.email` lookup, redact-allowlist). Asserted by a pre-merge sentinel test that runs a known-PII fixture through the prompt-assembly step and greps the output for `@`.

### FR8 — Failure reason taxonomy

`action_sends.failure_reason` (text column from migration 064) admits these PR-B-introduced values: `byok_cap_exceeded`, `cost_ceiling_exceeded`, `byok_lease_unavailable`, `anthropic_timeout`, `anthropic_rate_limited`, `leader_max_turns_exceeded`, `leader_tool_invalid`, `cancelled_by_operator`, plus PR-A's existing set (`github_installation_unauthorized` / `github_target_not_found` / `github_api_error` / `acknowledgment_persist_failed` / `malformed_source_ref`). Today card per-reason copy lives in a single mapping module.

### FR9 — Cost ceiling enforcement

Per-spawn cost ceiling = $2.00 USD. Enforced at the start of each turn (`turn-${n}-precheck-cost-ceiling`). On hit: terminate with `failure_reason = "cost_ceiling_exceeded"`; the partial artifact (if any tool calls succeeded) is preserved with `artifact_url IS NULL` and `reversal_handle IS NOT NULL` (operator can undo partials).

## Technical Requirements

### TR1 — ADR-042 + ADR-041

Pre-merge ADRs:

- **ADR-042** "Anthropic SDK inside Inngest function bodies — leader-loop topology" — covers loop topology (per-turn `step.run`), BYOK lease scope (per-turn re-acquisition, AsyncLocalStorage cannot escape step boundaries), tool-surface allowlist (per-class enumerated Octokit endpoints), prompt versioning (sha256 of `system + user + tools`; pinned to `action_sends.prompt_version` at loop start).
- **ADR-041** "BYOK cap enforcement model" — covers pre-call `record_byok_use_and_check_cap` check vs post-call (pre-call chosen; fail-closed), per-spawn cost ceiling (primary gate) vs max-turns (secondary backstop), `kill_tripped` return-value semantics (no raise; `users.runtime_paused_at` flip), per-turn `persistTurnCost` pairing requirement (enforced by `byok-audit-writer-sweep` lint).

Pre-merge guard: `bash scripts/check-adr-ordinals.sh` (new) greps `knowledge-base/engineering/architecture/decisions/INDEX.md` for next free ordinal; fails CI if a collision exists.

### TR2 — Migration 065

`apps/web-platform/supabase/migrations/065_action_sends_leader_loop.sql`:

```sql
ALTER TABLE public.action_sends
  ADD COLUMN IF NOT EXISTS reversal_handle jsonb,
  ADD COLUMN IF NOT EXISTS current_turn smallint,
  ADD COLUMN IF NOT EXISTS current_turn_started_at timestamptz,
  ADD COLUMN IF NOT EXISTS cancellation_requested_at timestamptz,
  ADD COLUMN IF NOT EXISTS prompt_version text,
  ADD COLUMN IF NOT EXISTS undone_at timestamptz;

-- Extend WORM trigger admit-list. The trigger reshaped in mig 064
-- already admits UPDATEs on acknowledged_at / artifact_url / failure_reason;
-- mig 065 extends to admit the six new columns above + artifact_url
-- (when clearing on undo).
```

Down-migration restores mig 064's admit-list and drops the 6 new columns.

Test: `apps/web-platform/test/supabase-migrations/065-action-sends-leader-loop.test.ts` asserts (a) 6 new columns exist NULL-defaulting, (b) WORM trigger admits UPDATEs touching only the new columns, (c) WORM trigger still rejects UPDATEs touching any pre-065 immutable column, (d) RLS owner-SELECT still works.

### TR3 — `recordByokUseAndCheckCap` TS wrapper (greenfield)

`apps/web-platform/server/byok-cap-rpc.ts` (new):

```ts
export async function recordByokUseAndCheckCap(args: {
  invocationId: string;
  founderId: string;
  workspaceId: string;
  agentRole: "agent.spawn.requested";
  tokenCount: number;
  unitCostCents: number;
}): Promise<{ cumulativeCents: number; killTripped: boolean }>;
```

Service-role only. Wraps the 6-arg RPC from `supabase/migrations/061_byok_audit_workspace_id_rpcs.sql:81-148`. Unit tests assert the wrapper passes `workspaceId === founderId` per the N2 invariant (per `cost-writer.ts:65-69` precedent).

### TR4 — Realtime subscription auth

Today card uses Supabase Realtime client with `auth.uid()` scope. Server-side: confirm RLS policy on `action_sends` admits Realtime CHANNEL subscription (Postgres CDC must respect RLS for the subscribing role).

### TR5 — Tool definitions

Per-class tool definitions live alongside the prompt modules at `apps/web-platform/server/inngest/leader-prompts/`. All tools route through `createGitHubAppClient(installationId, founderId)` Octokit — NEVER `probeOctokit`, NEVER raw `new Octokit()`. Sentinel: `grep -nE "probeOctokit\\(|new Octokit\\(" apps/web-platform/server/inngest/leader-prompts/ apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts` returns `0`.

### TR6 — `persistTurnCost` integration

Every Anthropic call site MUST pair with `persistTurnCost` per the `byok-audit-writer-sweep` lint. The cost-write shape:

```ts
persistTurnCost(founderId, conversationId, leaderId, workspaceId, {
  totalCostUsd,
  usage: {
    input_tokens,
    output_tokens,
    cache_read_input_tokens,    // load-bearing
    cache_creation_input_tokens, // load-bearing
  },
});
```

`conversationId` = UUIDv5 derived from `actionSendId` (namespace `agent.spawn.requested.conversation`). `leaderId` = `"agent.spawn.requested:${actionClass}"`. `workspaceId === founderId` per N2.

### TR7 — Prompt caching

All Anthropic calls use `cache_control: { type: "ephemeral" }` markers on the system prompt + tool definitions. Verify cumulative input cost reduction empirically against `byok_audit` rows post-merge (CFO follow-up).

### TR8 — Inngest function timeout extension

Verify default Inngest function timeout against 8 turns × 60s = 8 min wall-clock. Raise `function.config.timeout` if needed.

### TR9 — Reality-check sentinel

Pre-implementation check: `git log --oneline --since="2026-05-25" origin/main -- apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts apps/web-platform/components/dashboard/today-card.tsx apps/web-platform/supabase/migrations/` and flag any in-flight PRs touching the substrate. Carry forward to plan-time.

### TR10 — PA-22 legal substrate

- Append PA-22 to `knowledge-base/legal/article-30-register.md` (after PA-21).
- Amend Vendor Mapping row at line 412: add PA-22 to Activities column.
- Verify Anthropic Zero-Retention status; document gap in PA-22 (f) if unsigned.
- Sentinel: `grep -c "^## Processing Activity 22" knowledge-base/legal/article-30-register.md` returns `1`.

## Acceptance Criteria

Encoded at plan-time as AC1-ACN. Carry-forward from brainstorm Key Decisions.

## Open Questions

Carried from brainstorm:

1. Anthropic Zero-Retention status verification.
2. `conversationId` mint strategy (UUIDv5 from `actionSendId` proposed).
3. Inngest function timeout vs 8-turn wall-clock.
4. `stop_reason === "max_tokens"` handling.
5. Realtime subscription RLS-respect (fallback to polling if not).

## Stakeholders

- **Operator** (`ops@jikigai.com`) — sole dogfooder; brand-survival threshold gate.
- **CPO** — sign-off encoded as ACs; user-impact-reviewer at PR review.
- **CTO** — ADR-042 author; technical-strategist at PR review.
- **CLO** — PA-22 author; Vendor Mapping amendment; Zero-Retention verification.
- **CFO** — per-spawn unit economics post-merge audit; BYOK cap calibration.
- **Review-time agents**: `data-integrity-guardian`, `security-sentinel`, `observability-coverage-reviewer`, `user-impact-reviewer`, `architecture-strategist`.

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-05-25-pr-b-anthropic-leader-loop-brainstorm.md`
- Substrate PR (merged): #4378 (commit `7d5620a5`)
- Umbrella issue: #4124
- Tracking issue: #4379
- PR-A plan (consolidated/archived): `knowledge-base/project/plans/archive/...` (post-merge consolidation)
- Reference Inngest impls: `apps/web-platform/server/inngest/functions/cfo-on-payment-failed.ts:199`, `github-on-event.ts:208`
- BYOK lease: `apps/web-platform/server/byok-lease.ts:338`
- Cost writer: `apps/web-platform/server/cost-writer.ts`
- BYOK lint: `apps/web-platform/test/server/byok-audit-writer-sweep.test.ts`
- Cap RPC: `apps/web-platform/supabase/migrations/061_byok_audit_workspace_id_rpcs.sql:81-148`
- Vendor Mapping row: `knowledge-base/legal/article-30-register.md:412`
- PA-21 register entry: `knowledge-base/legal/article-30-register.md:380`
