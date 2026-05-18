---
adr: ADR-033
title: Inngest cron functions invoke claude-code via child_process.spawn
status: active
date: 2026-05-18
---

# ADR-033: Inngest cron functions invoke claude-code via child_process.spawn

## Context

PR-F (#3940, MERGED 2026-05-17) shipped the Inngest substrate self-hosted on Hetzner as the durable trigger layer for server-side agents (see [ADR-030](./ADR-030-inngest-as-durable-trigger-layer.md)). The first registered function — `cfo-on-payment-failed.ts` — is event-triggered and invokes the Anthropic SDK directly via `runWithByokLease` inside `step.run`.

The TR9 slice (#3948) migrates ~11 recurring "agent-loop" cron workflows from `.github/workflows/scheduled-*.yml` (currently invoked by `anthropics/claude-code-action` on GitHub Actions runners) to Inngest cron functions running inside the long-lived Node worker on the Hetzner host. The substrate-gap question driving this ADR is: **how do Inngest cron functions invoke `claude-code`?**

The two execution models differ in posture:

- `claude-code-action` spawns a **fresh ephemeral runner** per invocation, with a pristine `~/.claude/`, a 60-min GitHub Actions timeout, and runtime-injected agent prompt text. State does not survive across runs.
- Inngest functions are **long-lived worker processes** with `step.run` memoization (each step re-emits its memoized result on replay). The worker process owns its filesystem state.

Without a deliberate choice, the next 11 migration PRs would each independently re-invent how to invoke the agent — guaranteeing drift on the failure-mode-prevention contract (idempotency, replay-safety, cost ceiling). The decision must be made BEFORE PR-1 (`scheduled-daily-triage` migration) lands code, so every subsequent migration cites a single accepted invariant set.

Operator confirmed the decision 2026-05-18 during brainstorm Phase 1.2; recorded as K9 in `knowledge-base/project/brainstorms/2026-05-18-tr9-agent-loop-crons-inngest-migration-brainstorm.md`. CTO assessment (h) and CPO sign-off both accepted the spawn-child path.

## Considered Options

- **Option A: `child_process.spawn('claude-code', [...args])` inside `step.run('claude-eval', ...)`.** Treats `claude-code` as an external binary executed per step. Stdout/stdin/exit-code captured deterministically so `step.run` memoizes correctly on replay. Agent prompt loaded from a co-located `*.prompt.md` file (or inline string). Operator `ANTHROPIC_API_KEY` passed via env. **Pros:** preserves existing claude-code-action agent prompts as-is (no rewrite); lower-risk port; per-step memoization comes for free if stdout capture is deterministic; the spawn boundary is a natural place to enforce a per-step timeout via `AbortSignal`. **Cons:** spawn surface is one more failure mode (binary missing, version drift, working-directory assumptions); requires `claude-code` CLI on the Hetzner worker image with a pinned version.

- **Option B: SDK rewrite — invoke `@anthropic-ai/sdk` directly inside Inngest functions.** Port each agent prompt + tool-use loop into TypeScript code running in-process. **Pros:** no subprocess surface; full control over conversation state; no binary version-pinning; tighter integration with Inngest's `AbortSignal` + step boundaries. **Cons:** re-implements claude-code's tool-use orchestration, MCP server connections, the agent loop, file-edit primitives, and prompt-caching logic; 11× the per-workflow port cost; loses the prompt-file portability that claude-code-action already provides; tool-use bugs ship per-workflow instead of being centralized in one well-tested binary.

- **Option C: Inngest "function-as-CI" — keep claude-code-action, just have Inngest dispatch a GitHub Actions workflow_dispatch.** Inngest function fires on schedule, calls the GitHub API to dispatch the same `claude-code-action`-based workflow that exists today. **Pros:** zero migration of the agent invocation itself; reuses existing battle-tested action. **Cons:** doesn't actually migrate cron off GitHub Actions — defeats the purpose of TR9 entirely (the rationale is replacing GitHub Actions' jitter + lack-of-replay/idempotency with Inngest's). The cron scheduling moves but the execution doesn't; the failure modes the migration is meant to fix (silent failure, replay safety, observability) remain.

## Decision

**Choose Option A.** Every Inngest cron function in `apps/web-platform/server/inngest/functions/cron-*.ts` invokes `claude-code` via `child_process.spawn` inside a `step.run('claude-eval', ...)` step.

The decision lands with PR-1 of #3948 (proof-of-pattern `scheduled-daily-triage` migration). This ADR may be superseded if a future operator decides the SDK-rewrite cost has dropped (e.g., after Anthropic ships a higher-level Node SDK matching claude-code's agent-loop primitives, or after 3+ workflows reveal spawn-boundary friction that the SDK avoids).

**Load-bearing invariants** (binding all 11 subsequent migrations):

- **I1.** `claude-code` is spawned INSIDE `step.run` (not at function entry). Step memoization is what protects against replay-cost runaway; spawning at entry escapes step memoization and triggers fresh Anthropic API calls on every replay.
- **I2.** Operator `ANTHROPIC_API_KEY` ONLY — never founder BYOK. Enforced via inverse-assertion in `apps/web-platform/test/server/byok-audit-writer-sweep.test.ts`: files matching `server/inngest/functions/cron-*.ts` MUST NOT import `runWithByokLease`. This is the "no-founder-context" boundary marker (see also I6).
- **I3.** `AbortSignal` aborts the spawned process at **60 minutes** (matches the old GitHub Actions `timeout-minutes: 60` ceiling and preserves the 0.75 min/turn peer-ratio floor for an 80-turn budget — see `2026-03-20-claude-code-action-max-turns-budget.md`). The `AbortSignal` is plumbed from Inngest's per-step timeout into the `child_process.spawn` options. Abort handler escalates with manual `process.kill(-child.pid, "SIGTERM")` then SIGKILL after 5 s on a `detached: true` process group so grandchildren (bash, gh) do not orphan. `[Refined 2026-05-18 post PR-1 plan review — 5-agent panel converged that the original 55-min figure under-fired the peer ratio; rollback-headroom rationale dropped since Inngest replays do not depend on spawn ceiling.]`
- **I4.** `claude` binary (npm package `@anthropic-ai/claude-code`) is **pinned via `apps/web-platform/package.json` dependency**. The existing deploy pipeline runs `npm install` on the Hetzner worker; the npm package's `postinstall` downloads the platform-native binary and exposes it at `node_modules/.bin/claude`. Inngest functions resolve the absolute path at module load via `createRequire(import.meta.url).resolve("@anthropic-ai/claude-code/package.json")`. The npm package installs the binary under the name `claude` (NOT `claude-code` — that is only the npm-registry package name). `[Refined 2026-05-18 post PR-1 plan review — original cloud-init pin was an extra IaC dance for no upside; the dep already ships via the same release artifact as the application code.]`
- **I5.** Stdout/exit-code captured **deterministically** so `step.run` memoization fires reliably. Inngest's memoization is keyed on the serialized step result; if claude-code's stdout includes nondeterministic timestamps or progress chatter, memoization breaks and replays re-spawn the agent. PR-1 must verify deterministic capture via the FR10 integration test (second invocation in succession MUST NOT re-spawn).
- **I6.** Event payloads emitted by `cron-*` functions carry `actor: "platform"` tag. This is the boundary marker that lets platform-loop crons + per-founder runtime share one Inngest server; without it, `hr-gdpr-gate-on-regulated-data-surfaces` fires the moment PR-G (#3947) ships founder cohort exposure.

## Consequences

**Easier:**

- Migration cost per workflow drops to "translate the YAML to a 50-line TS file" — agent prompts move as-is from inline-YAML to `*.prompt.md` files co-located with the function.
- Replay safety is in scope of the existing Inngest contract — every cron-* function inherits the same `step.run` memoization story without per-function reasoning.
- The `AbortSignal` + 55-min ceiling gives a single consistent cost-runaway primitive across all 11 migrations (where GitHub Actions had 11 different `timeout-minutes` values to reason about).
- Single point of CLI upgrade across all 11 workflows (Hetzner cloud-init), instead of bumping `claude-code-action` version across 11 YAML files.
- Future workflow additions are mechanical: drop a new `cron-*.ts` file and a new `*.prompt.md`, register in `inngest.createFunction({cron: "..."}, ...)` — no GitHub Actions YAML at all.

**Harder:**

- Hetzner Inngest worker image must include `claude-code` with a pinned version (cloud-init or systemd unit). One more thing to keep in IaC drift-check.
- Spawn boundary introduces a `child_process` failure mode class (binary not found, working-directory assumptions, env-var inheritance gotchas). Per-function integration tests must exercise the spawn path.
- Stdout determinism is load-bearing for replay-cost safety; any future `claude-code` upgrade that adds nondeterministic stdout chatter silently breaks memoization. Mitigation: FR10 jitter-guard integration test catches it (second invocation MUST early-return without spawning).
- The 11 follow-up PRs all depend on the spawn primitive landing in PR-1. If PR-1's spawn primitive is wrong, fixing it requires a cross-cutting touchup of every migrated cron-* file (mitigated by per-workflow PR shape — the substrate primitive lives in a shared helper, not per-function code).

## Cost Impacts

**None.** Inngest substrate is already in `knowledge-base/operations/expenses.md` (PR-F shipped self-hosted on existing Hetzner node; no new vendor, no billing-tier change). `claude-code` CLI install on Hetzner is free; binary pin is a config change, not a paid resource. Operator `ANTHROPIC_API_KEY` consumption stays in the same operator-Anthropic billing surface — the migration is a substrate swap (GitHub Actions runner → Hetzner node), not a budget increase.

If the Hetzner node ever needs to upsize for concurrency (e.g., multiple cron-* functions running simultaneously), that's an operations-side cost decision NOT bound by this ADR. The Inngest free-tier "5 concurrent steps" cap is irrelevant under self-hosted.

## NFR Impacts

This decision is the **architecture primitive** that enables NFR improvements in subsequent PR-1 acceptance criteria; the ADR itself does not tier-move any NFR at the register level. The downstream effects when the 11 migrations land:

- **Improves NFR-001 (Logging) / NFR-003 (Observability)** for migrated crons: GitHub Actions silent-failure traps (per `2026-05-18-vendor-cron-heartbeat-silent-fail-pattern.md`) are eliminated because Sentry check-in is at end-of-`step.run` (FR4 of PR-1 spec). Status improvement applies per-migrated-workflow, not at the substrate level.
- **Improves NFR-007 (Circuit Breaker / Cost Ceiling)** indirectly: the I3 `AbortSignal` at 55-min provides a deterministic cost ceiling that GitHub Actions' `timeout-minutes` could only approximate.
- **No impact on NFR-026 (Encryption In-Transit)** — `claude-code` invokes the Anthropic API over HTTPS regardless of host; substrate swap doesn't change transport.

NFR register entries are not updated as part of this ADR; PR-1 (and each subsequent migration PR) updates the per-workflow row when the migration lands.

## Principle Alignment

- **AP-008 (Doppler secrets): Aligned** — `ANTHROPIC_API_KEY` already in Doppler `prd` (PR-F runtime). The Hetzner worker reads from Doppler, not from a `.env` file. Cron-* functions inherit the operator key from the parent Node process env.
- **AP-001 (Terraform-only provisioning): Aligned** — `claude-code` binary pin lives in `apps/web-platform/infra/server.tf` (cloud-init or systemd unit), not a manual operator step.
- **`hr-dev-prd-distinct-supabase-projects`: Aligned** — `cron_run_ledger` ledger writes hit dev/prd-distinct Supabase projects per the parent project posture.
- **`hr-autonomous-loop-skill-api-budget-disclosure`: NO-OP at write time** — the rule targets founder-BYOK consumption unattended. These cron-* functions consume the OPERATOR key only (invariant I2). Guard clause: if any future cron-* function transitions to per-founder execution, this ADR MUST be superseded and the budget-disclosure rule re-evaluated before that transition merges.

## Diagram

```mermaid
C4Component
title Inngest cron function — claude-code spawn boundary (component view)

Container_Boundary(node, "Hetzner Node — long-lived Node process") {
  Component(inngest_worker, "Inngest worker", "@inngest v3", "Receives cron schedule, dispatches to function handler")
  Component(cron_fn, "cron-daily-triage.ts", "TypeScript", "Inngest function handler")
  Component(step_jitter, "step.run('jitter-guard')", "Inngest step", "Reads cron_run_ledger; early-returns if <80% interval elapsed")
  Component(step_eval, "step.run('claude-eval')", "Inngest step", "Spawns claude-code via child_process.spawn; captures stdout deterministically")
  Component(step_heartbeat, "step.run('sentry-heartbeat')", "Inngest step", "End-of-job POST to Sentry Crons monitor")
  Component(spawn, "claude-code CLI", "Pinned via cloud-init", "Executes agent prompt with operator ANTHROPIC_API_KEY")
}

ContainerDb(ledger, "cron_run_ledger", "Postgres / Supabase", "function_name, last_run_at, run_count")
System_Ext(anthropic, "Anthropic API", "Operator ANTHROPIC_API_KEY")
System_Ext(github, "GitHub API", "Label-mutator / issue-creator side effects")
System_Ext(sentry, "Sentry Crons", "Heartbeat check-in")

Rel(inngest_worker, cron_fn, "fires on schedule", "cron")
Rel(cron_fn, step_jitter, "step 1")
Rel(step_jitter, ledger, "read + UPSERT", "SQL")
Rel(cron_fn, step_eval, "step 2 (if not jitter-guarded)")
Rel(step_eval, spawn, "child_process.spawn", "stdio + 55-min AbortSignal")
Rel(spawn, anthropic, "tool-use loop", "HTTPS")
Rel(spawn, github, "label / comment writes", "HTTPS")
Rel(cron_fn, step_heartbeat, "step 3 (always)")
Rel(step_heartbeat, sentry, "POST status=ok|error", "HTTPS")
```
