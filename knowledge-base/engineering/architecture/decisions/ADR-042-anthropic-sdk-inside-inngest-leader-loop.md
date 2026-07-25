---
title: Anthropic SDK inside Inngest function bodies — leader-loop topology
status: accepted
date: 2026-05-25
related: [4379, 4124, 4378]
related_adrs: [ADR-030, ADR-041]
related_plans:
  - knowledge-base/project/plans/2026-05-25-feat-anthropic-leader-loop-pr-b-plan.md
related_specs:
  - knowledge-base/project/specs/feat-4379-anthropic-leader-loop/spec.md
brand_survival_threshold: single-user incident
---

# ADR-042: Anthropic SDK inside Inngest function bodies — leader-loop topology

## Status

**Accepted** (2026-05-25, PR #4379).

Lands in the same PR as ADR-041 and migration 069 per `requires_adr: true` in the PR-B plan frontmatter. This ADR is the load-bearing precondition for the first raw `@anthropic-ai/sdk` `messages.create` site to land inside `apps/web-platform/server/` — until this ADR is accepted, the deferred-stub shape from PR-A (#4378) stands.

## Context

PR-A (`#4378`, commit `7d5620a5`) shipped the operator-clicked "Spawn agent / Fix link" substrate: an `agent.spawn.requested` Inngest event, the `agent-on-spawn-requested.ts` function with `resolve-installation → post-acknowledgment → mark-acknowledged → persist-failure` step sequence, the `action_sends` WORM table with mig 064's reshape admitting UPDATEs on `acknowledged_at`/`artifact_url`/`failure_reason`, and the `createGitHubAppClient` factory with per-Octokit-call audit. The function is *acknowledgment-only*: every operator click produces a pre-templated PR comment or `soleur/acknowledged` issue label. No autonomous AI output.

PR-B replaces the body of `step.run("post-acknowledgment", …)` (`agent-on-spawn-requested.ts:149-174`) with a per-turn loop driven by `anthropic.messages.create` with tool-use rounds. The loop spans 5 per-action-class registries and enforces a $2.00 per-spawn cost ceiling, a flat 8-turn ceiling, and BYOK lease + cap gates (see ADR-041 for cap enforcement). This is the **first raw `@anthropic-ai/sdk` call site inside `apps/web-platform/server/`** — all existing Anthropic traffic flows through `@anthropic-ai/claude-agent-sdk` `query()` (sub-process, ADR-033) or type-only imports (e.g., `soleur-go-runner.ts:91`).

Functional-discovery (plan-time 2026-05-25) evaluated three reusable substrates and rejected each:

| Substrate | Rejection rationale |
|---|---|
| `@anthropic-ai/claude-agent-sdk` (`query()`) | Claude-Code-style harness (filesystem/shell/MCP); no per-turn token-usage hooks for `persistTurnCost`; no native cost-cap short-circuit. Owns its own permission model — incompatible with our per-class tool allowlist. |
| Vercel AI SDK `ToolLoopAgent` | Provider-abstraction; loses Anthropic-specific cache-aware accounting (`cache_read_input_tokens` + `cache_creation_input_tokens`) the dashboard depends on. Step-count cap only, no cost cap. |
| Temporal `agentic-loop` cookbook | Separate workflow substrate; would fork the Inngest-vs-Temporal substrate decision (ADR-030) for one feature. |

The leader loop is therefore custom — a thin wrapper around `anthropic.messages.create` (~40 lines per the Temporal cookbook precedent). The architectural risk is in the *Inngest integration*, not the SDK call itself.

**Brand-survival threshold: single-user incident.** Operator (`ops@jikigai.com`) is the sole dogfooder; cross-tenant guard inherited from PR-A; cost runaway is operator-funded (BYOK) but a single runaway during dogfood is brand-survival-relevant — the operator IS the brand at this stage.

## Decision

**The leader-loop topology pins five load-bearing invariants. Each invariant is enforced by a sentinel test that fails CI if drift is detected.**

### I1 — Per-turn `step.run` topology

For each turn `n` in `[1..maxTurns]`, the Inngest function body issues:

1. `step.run("turn-${n}-cap-check", …)` — pre-call BYOK cap gate via `recordByokUseAndCheckCap` (see ADR-041).
2. `step.run("turn-${n}-precheck-cost-ceiling", …)` — per-spawn $2.00 ceiling check against cumulative `byok_audit` rows.
3. `step.run("turn-${n}-cancel-check", …)` — operator-set `action_sends.cancellation_requested_at` short-circuit.
4. `step.run("turn-${n}-progress-write", …)` — UPDATE `current_turn = ${n}`, `current_turn_started_at = now()`. Triggers Supabase Realtime fanout.
5. `step.run("turn-${n}-claude", …)` — opens `runWithByokLease`, calls `anthropic.messages.create`, awaits `persistTurnCost`.
6. `step.run("turn-${n}-tool-${i}", …)` per tool_use block — invokes the GitHub tool via `createGitHubAppClient` Octokit.

Step names are deterministic and keyed off `actionSendId` + turn index. **Inngest replay determinism** memoizes successful step results: on retry, only failed steps re-run. This is the cost-correct shape per Inngest replay semantics — a transient SDK error in turn 5 does NOT re-bill turns 1-4.

**Sentinel test**: `apps/web-platform/test/server/inngest/agent-on-spawn-requested-leader-loop.test.ts` replays a forced-fail turn-2 and asserts only turn-2 re-runs.

### I2 — BYOK lease opens INSIDE each SDK-calling `step.run`

`runWithByokLease({ workspaceContextUserId, keyOwnerUserId }, fn)` (`byok-lease.ts:338`) uses AsyncLocalStorage to attach the operator's BYOK key to SDK calls inside the callback. **The ALS context CANNOT escape a `step.run` boundary** — Inngest serializes step results to durable storage; the next step starts with a fresh callback frame, no ALS context. Therefore:

- The lease MUST be acquired inside the `step.run("turn-${n}-claude", …)` callback, NOT outside.
- The lease scope MUST close BEFORE the `step.run` returns.
- On retry, ONLY the failing turn re-acquires the lease (matches `cfo-on-payment-failed.ts:198-217` precedent).

The reference impl at `cfo-on-payment-failed.ts:198-217` is currently a stub returning `{tokenCount:0, unitCostCents:0}` (carries the `byok-audit-writer-sweep: out-of-scope` marker). PR-B does real work and therefore the marker is absent; the `byok-audit-writer-sweep` lint (`apps/web-platform/test/server/byok-audit-writer-sweep.test.ts`) asserts a real `persistTurnCost(` call inside the new lease scope.

**Lease envelope inequality** (per learning `2026-05-24-token-cache-margin-vs-consumer-budget-envelope.md`): each per-turn lease must satisfy `lease.remaining_at_entry ≥ remaining_turns_max_wall_clock + slack`. For 8 turns × ~60s budget with slack, the lease factory must mint with `minRemainingMs ≥ 90s` floor on the per-turn re-acquisition.

**Sentinel test**: existing `byok-audit-writer-sweep.test.ts` covers the new lease site (SERVER_DIR scope). No marker comment; real `persistTurnCost` call asserted.

### I3 — Per-class enumerated tool allowlist

Each leader prompt module (`apps/web-platform/server/inngest/leader-prompts/{class}.ts`) exports an explicit `tools: AnthropicToolDef[]` array. The dispatcher inside `turn-${n}-tool-${i}` resolves the model's tool name against the per-class allowlist; an out-of-allowlist call short-circuits with `failure_reason = "leader_tool_invalid"`.

Per-class allowlists:

| Class | Tools |
|---|---|
| `engineering.pr_review_pending` | `createPullRequestReviewComment`, `createComment` |
| `engineering.ci_failed` | `createComment` |
| `triage.p0p1_issue` | `addLabels`, `createComment` |
| `security.cve_alert` | `createBranch`, `createBlob`, `createCommit`, `createPullRequest`, `createComment` |
| `knowledge.kb_drift` | `createBranch`, `createBlob`, `createCommit` |

All tool implementations route through `createGitHubAppClient(installationId, founderId)`. **NEVER `probeOctokit` (audit-skipping); NEVER raw `new Octokit()`.**

The system prompt for each class MUST enumerate the available tools by name. Per learning `2026-05-05-baseline-prompt-must-declare-capabilities-or-model-fabricates-missing-tools.md`, omitting the tool list from the system prompt leads to the model fabricating tool calls outside the allowlist.

**Sentinel tests**:

- `apps/web-platform/test/server/inngest/leader-prompts/tool-surface.test.ts` — `grep -nE "probeOctokit\(|new Octokit\(" leader-prompts/ agent-on-spawn-requested.ts` returns 0.
- `apps/web-platform/test/server/inngest/leader-prompts/prompt-version-stability.test.ts` — each module's system prompt enumerates its tools.

### I4 — Prompt versioning pinned at loop start

Each leader-prompt module exports `promptVersion: "v${number}.${number}.${number}"` — a **developer-maintained version string** bumped on every material edit to systemPrompt / userPromptTemplate / tools. At loop start (`turn-1-progress-write`), the active module's `promptVersion` is written to `action_sends.prompt_version`. In-flight runs are deterministic against the prompt-version they started with.

**Why developer-maintained instead of hashed source**: JS engine `.toString()` of arrow functions varies across Node major versions (whitespace, comment preservation). A `sha256(systemPrompt + userPromptTemplate.toString() + …)` hash would silently diverge between CI (Node 22) and prod (Node 24), breaking in-flight replay determinism on runtime upgrades. The manual bump trades type-checker enforcement (developers can forget to bump) for runtime stability (Kieran review M6, 2026-05-25).

**Sentinel test**: prompt-version-stability test asserts the type narrows to `\`v${number}.${number}.${number}\``.

### I5 — `cache_control: ephemeral` ON; cache tokens load-bearing in `persistTurnCost`

All Anthropic calls use `cache_control: { type: "ephemeral" }` markers on the system prompt + tool definitions. The `cache_read_input_tokens` + `cache_creation_input_tokens` fields from the SDK response MUST flow through `persistTurnCost(...)`'s usage object. Per learning `2026-05-12-stub-handlers-as-silent-undercount-vectors.md`, omitting these fields under-counts dashboard input cost by ~90% (with caching ON, the bulk of "real" input tokens land in `cache_read_input_tokens`).

`persistTurnCost` is **awaited** inside the per-turn `step.run` (Kieran review B2 fix); the cost row commits before the next step's progress-write triggers the Supabase Realtime fanout. This makes the Today card's cumulative cost display read the just-completed turn deterministically (no race window).

**Sentinel test**: `byok-audit-writer-sweep` lint + `agent-on-spawn-requested-leader-loop.test.ts` assertion that mocked SDK calls returning cache fields propagate to the RPC call args.

## Consequences

### Positive

- **Replay-safe**: per-turn `step.run` topology + Inngest memoization = no double-billing on retry.
- **Cap-safe**: ADR-041's pre-call gate runs inside each turn's step; never bypassed.
- **Tool-safe**: per-class allowlist + system-prompt enumeration kills the fabricated-tool risk.
- **Cache-correct**: dashboard cost reads match Anthropic Console (no 90% under-count).
- **Prompt-stable**: in-flight runs deterministic against `promptVersion` pin even across leader-prompt edits.

### Negative / accepted trade-offs

- **First raw `@anthropic-ai/sdk` site in `server/`**. PR-A's invariant I4 ("No Anthropic SDK in PR-A") is deliberately reversed in PR-B. The `byok-audit-writer-sweep` lint widens to cover the new site without the `out-of-scope` marker.
- **Developer-maintained `promptVersion`**: relies on developer discipline to bump; mitigation = code-review checklist item + test failure on type-narrowing violations.
- **Per-turn lease re-acquisition** is counterintuitive (cannot span turns). ADR-041 + this ADR explicitly document. Code comments at the lease-opening site reference both ADRs.
- **No fallback to `@anthropic-ai/claude-agent-sdk` `query()`** if `messages.create` fails at runtime — by design (single substrate; failure paths route through the `failure_reason` taxonomy in ADR-041's AC10).

### Sentinel test suite (load-bearing)

| Sentinel | Path | Asserts |
|---|---|---|
| Loop replay determinism | `test/server/inngest/agent-on-spawn-requested-leader-loop.test.ts` | I1 |
| BYOK audit writer sweep | `test/server/byok-audit-writer-sweep.test.ts` (existing, widened scope) | I2 + I5 |
| Tool surface allowlist | `test/server/inngest/leader-prompts/tool-surface.test.ts` | I3 |
| Prompt version stability | `test/server/inngest/leader-prompts/prompt-version-stability.test.ts` | I3 + I4 |
| ADR ordinal guard | `scripts/check-adr-ordinals.sh` | this ADR + ADR-041 exist with required headings |

## Alternatives Considered

1. **Adopt `@anthropic-ai/claude-agent-sdk`** — rejected; per-turn cost-cap + per-class tool allowlist + cache-aware token persistence are not first-class hooks in that SDK.
2. **Adopt Vercel AI SDK `ToolLoopAgent`** — rejected; provider-abstraction loses Anthropic-specific cache token accounting that the dashboard depends on.
3. **Move to Temporal `agentic-loop`** — rejected; forks the Inngest-vs-Temporal substrate decision (ADR-030) for one feature.
4. **Hash-based `promptVersion`** — rejected; JS engine `.toString()` is runtime-dependent (Kieran review M6).
5. **`persistTurnCost` fire-and-forget** — rejected; Kieran review B2 surfaced the cost-vs-Realtime race that the await closes.
6. **Inngest Realtime (`step.realtime.publish()`)** for in-flight progress channel — deferred to a follow-up issue post-PR-B per Reality-Check Findings row 3 (brainstorm locked Supabase Realtime).

## References

- Spec: `knowledge-base/project/specs/feat-4379-anthropic-leader-loop/spec.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-25-pr-b-anthropic-leader-loop-brainstorm.md`
- Plan: `knowledge-base/project/plans/2026-05-25-feat-anthropic-leader-loop-pr-b-plan.md`
- PR-A substrate (merged): #4378 (commit `7d5620a5`)
- Reference Inngest impls: `apps/web-platform/server/inngest/functions/cfo-on-payment-failed.ts:198-217`, `github-on-event.ts:208`
- BYOK lease: `apps/web-platform/server/byok-lease.ts:338`
- Cost writer: `apps/web-platform/server/cost-writer.ts:72-160`
- BYOK lint: `apps/web-platform/test/server/byok-audit-writer-sweep.test.ts`
- PR-A function body: `apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts:149-228`
- Critical learnings:
  - `2026-05-12-stub-handlers-as-silent-undercount-vectors.md` (I5)
  - `2026-05-05-baseline-prompt-must-declare-capabilities-or-model-fabricates-missing-tools.md` (I3)
  - `2026-05-24-token-cache-margin-vs-consumer-budget-envelope.md` (I2 envelope inequality)
  - `2026-05-19-inngest-substrate-five-bug-cascade.md` (smoke-test dev Inngest)
  - `2026-05-12-pr-a1-implementation-and-multi-reviewer-convergence.md` (onText cumulative — out of scope for v1 non-streaming)
