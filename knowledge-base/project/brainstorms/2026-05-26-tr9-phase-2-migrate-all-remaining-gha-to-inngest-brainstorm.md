---
lane: cross-domain
brand_survival_threshold: single-user incident
parent_epic: "#3244"
parent_tracking: "#3948"
phase1_brainstorm: "2026-05-18-tr9-agent-loop-crons-inngest-migration-brainstorm.md"
issue: "#3948"
type: focused
---

# TR9 Phase 2 — Migrate All Remaining GHA Scheduled Workflows to Inngest (Brainstorm)

**Date:** 2026-05-26
**Worktree:** `.worktrees/feat-tr9-phase-2-inngest-migration`
**Branch:** `feat-tr9-phase-2-inngest-migration`
**Draft PR:** [#4483](https://github.com/jikig-ai/soleur/pull/4483)
**Parent tracking:** [#3948](https://github.com/jikig-ai/soleur/issues/3948) — TR9 umbrella
**Phase 1 brainstorm:** `knowledge-base/project/brainstorms/2026-05-18-tr9-agent-loop-crons-inngest-migration-brainstorm.md`

## Scope of this brainstorm

Phase 1 classified ~38 GHA workflows into three groups and only migrated group (c) agent-loops (14 functions, all live on main for 5+ weeks). Groups (a) CI infra and (b) content production were explicitly deferred. This brainstorm **reverses that classification** — migrating everything except two documented exceptions — based on 5 weeks of production reliability evidence and the mechanical repeatability of the migration pattern across 11 per-workflow PRs.

**27 `scheduled-*.yml` files remain on `main` HEAD** (verified via `git ls-tree HEAD .github/workflows/ | grep scheduled- | wc -l`).

## What We're Building

**25 workflows to migrate/delete. 2 permanent GHA exceptions.**

### Wave 0: Quick Wins (4 items)
| # | Workflow | Action | Rationale |
|---|---------|--------|-----------|
| W0-1 | `scheduled-dogfood-3155.yml` | **DELETE** | One-shot already fired 2026-05-05. `workflow_dispatch` only, no cron. |
| W0-2 | `scheduled-gdpr-gate-preflight-eval-50d.yml` | **DELETE** | Inngest oneshot `oneshot-gdpr-gate-50d-eval.ts` already on main (PR-G #4461). GHA YAML is a cleanup miss. |
| W0-3 | `scheduled-f2-defer-gate-review.yml` | **CONVERT** to Inngest oneshot | Fires May 29, 2026. Never fired yet. Convert before fire date. Same pattern as `oneshot-gdpr-gate-50d-eval.ts`. |
| W0-4 | `scheduled-recheck-4217-calibration.yml` | **CONVERT** to Inngest oneshot | Fires June 20, 2026. Convert to `inngest.send`-triggered oneshot with `ts` field. |

### Wave 1: Claude-code-spawn (5 items) — heavy pool
**Prerequisite:** #4472 substrate extraction must merge first.

| # | Workflow | Cron | Timeout | Pattern |
|---|---------|------|---------|---------|
| W1-1 | `scheduled-campaign-calendar.yml` | `0 16 * * 1` | 30min | Claude-eval spawn (PR-7 archetype) |
| W1-2 | `scheduled-content-generator.yml` | `0 10 * * 2,4` | 60min | Claude-eval spawn |
| W1-3 | `scheduled-growth-audit.yml` | `0 9 * * 1` | 55min | Claude-eval spawn |
| W1-4 | `scheduled-growth-execution.yml` | `0 10 1,15 * *` | 30min | Claude-eval spawn |
| W1-5 | `scheduled-seo-aeo-audit.yml` | `0 10 * * 1` | 30min | Claude-eval spawn |

### Wave 2: Event-triggered conversion (1 item) — heavy pool
| # | Workflow | Trigger | Pattern |
|---|---------|---------|---------|
| W2-1 | `scheduled-ship-merge.yml` | Manual dispatch only | Event-triggered Inngest function (`ship-merge.manual-trigger`). Not cron. |

### Wave 3: Pure-TS ports (15 items) — light pool
Ordered by fire frequency (highest first). All use Archetype B (Octokit + node:fs, no claude binary).

| # | Workflow | Cron | Timeout | External deps | GDPR-gate? |
|---|---------|------|---------|---------------|------------|
| W3-1 | `scheduled-membership-health.yml` | `17 * * * *` (hourly) | 5min | Supabase API | No |
| W3-2 | `scheduled-dev-migration-drift.yml` | `15 */6 * * *` (6h) | 5min | Supabase CLI | **Yes** |
| W3-3 | `scheduled-realtime-probe.yml` | `0 7 * * *` (daily) | 5min | WebSocket (native Node.js) | **Yes** |
| W3-4 | `scheduled-ruleset-bypass-audit.yml` | `13 6 * * *` (daily) | 5min | GitHub API (App auth) | No |
| W3-5 | `scheduled-gh-pages-cert-state.yml` | `0 3 * * *` (daily) | 5min | GitHub API | No |
| W3-6 | `scheduled-cloud-task-heartbeat.yml` | `30 9 * * *` (daily) | 5min | GitHub API | No |
| W3-7 | `scheduled-content-publisher.yml` | `0 14 * * *` (daily) | 15min | Discord, X, LinkedIn, Bluesky APIs | No |
| W3-8 | `scheduled-weekly-analytics.yml` | `0 6 * * 1` (weekly) | 10min | Plausible API + cascade dispatch | No |
| W3-9 | `scheduled-content-vendor-drift.yml` | `17 11 * * MON` (weekly) | 10min | `git clone` + diff | No |
| W3-10 | `scheduled-linkedin-token-check.yml` | `0 9 * * 1` (weekly) | 5min | LinkedIn API | No |
| W3-11 | `scheduled-nag-4216-readiness.yml` | `0 14 * * 1` (weekly) | 5min | GitHub API | No |
| W3-12 | `scheduled-cf-token-expiry-check.yml` | manual dispatch | 5min | Cloudflare API | No |
| W3-13 | `scheduled-plausible-goals.yml` | `0 7 1 * *` (monthly) | 5min | Plausible API | No |
| W3-14 | `scheduled-rule-prune.yml` | `0 9 1 1,4,7,10 *` (quarterly) | 10min | Git + GitHub API | No |
| W3-15 | `scheduled-skill-freshness.yml` | `0 2 1 * *` (monthly) | 5min | Filesystem scan | No |

### GHA Exceptions (2 items — stay permanently)
| Workflow | Rationale |
|---------|-----------|
| `scheduled-terraform-drift.yml` | Requires Terraform binary + provider plugins. CTO: image bloat + credential boundary violation. CLO: Art. 32 ephemeral-runner isolation is a genuine security advantage for infrastructure credentials. |
| `scheduled-followthrough-sweeper.yml` | Dynamically executes arbitrary scripts from issue body directives with selective secret injection. CTO + CLO: shared `process.env` on persistent worker defeats the current selective-secret TOM. Art. 32 + Art. 25(1) concern. |

## Why This Approach

**Why reverse the Phase 1 deferral:** 5 weeks of production reliability (14 functions, zero P1 incidents after the initial 5-bug cascade resolved in 48h). Pattern is proven mechanical across 11 per-workflow PRs. PR-G (#3947) shipped 2026-05-19, so the "consolidate before founders" rationale (K15) was satisfied AND is now moot.

**Why keep terraform-drift and followthrough-sweeper on GHA:** Not a substrate capability gap — it's a deliberate security boundary. Terraform needs ephemeral runners for credential isolation (state files + provider tokens). Followthrough-sweeper needs ephemeral runners for its dynamic script execution model with selective secret injection. Both CTO and CLO independently converged on this recommendation.

**Why dual concurrency pools:** The existing `cron-platform` limit:1 serializes ALL cron functions. With 14 existing + ~21 new = ~35 cron functions, Monday 09:00 UTC sees 6-8 functions competing for the single lock. Functions running 15-60 minutes would cause multi-hour queue delays. Solution: `cron-platform-heavy` (claude-code spawn, limit:1) and `cron-platform-light` (pure-TS, limit:3). Light functions finish in <5 min and don't consume Anthropic API budget. Requires ADR-033 amendment.

**Why #4472 as prerequisite:** Each claude-eval-spawn function carries ~165 LoC of duplicated substrate code. Adding 5 more Group A functions without extraction would push total duplication past 3,300 LoC. The shared `_cron-claude-eval-substrate.ts` is already spec'd in #4472.

**Why Sentry-only (drop email notifications):** Existing Inngest crons use Sentry heartbeats + Better Stack shipping. Adding a RESEND email path would be a second notification channel that's already covered. The email composite action (`notify-ops-email`) is a GHA artifact that doesn't need to be carried forward.

**Why per-workflow PR discipline:** K8 carry-forward from Phase 1. Write-class workflows (pr-creator, issue-creator, label-mutator) have heterogeneous blast radii — bundling inherits worst-case review surface. Proven across 11 PRs.

## Key Decisions

### Carry-forward from Phase 1

| # | Decision | Source |
|---|----------|--------|
| K1-K6 | Inngest substrate invariants (self-hosted, CEL concurrency, event.v envelope, step.run memoization, BYOK lease, tier budget) | Phase 1 K1-K6 |
| K8 | Per-workflow PR shape; #3948 as umbrella | Phase 1 K8 |
| K9 | `child_process.spawn('claude', ...)` inside `step.run` for claude-eval | Phase 1 K9 |
| K11 | Sentry single heartbeat at end-of-step.run | Phase 1 K11 |
| K12 | `actor: "platform"` event-payload tag + inverse-assertion in BYOK sweep | Phase 1 K12 |
| K13 | Delete GHA YAML in same commit Inngest function lands | Phase 1 K13 |
| K16 | No key rotation at migration (same trust boundary) | Phase 1 K16 |
| K19 | No new sub-processor (self-hosted preserves posture) | Phase 1 K19 |

### New decisions for Phase 2

| # | Decision | Why |
|---|----------|-----|
| K20 | **Terraform-drift stays on GHA permanently.** | CTO + CLO convergence: credential isolation requires ephemeral runners. Image bloat (Terraform binary + providers ~400MB) + Art. 32 concern. Operator confirmed. |
| K21 | **Followthrough-sweeper stays on GHA permanently.** | CTO + CLO convergence: selective secret injection (`secrets=` clause) is an Art. 32 TOM that becomes ineffective on a shared-env persistent worker. Operator confirmed. |
| K22 | **Dual concurrency pools:** `cron-platform-heavy` (claude-code spawn, limit:1) and `cron-platform-light` (pure-TS, limit:3). | Monday 09:00 pile-up with 35+ functions on limit:1 causes multi-hour queue delays. Requires ADR-033 amendment. Operator confirmed. |
| K23 | **#4472 substrate extraction is a hard prerequisite for Wave 1 (Group A).** | Prevents 5+ more functions duplicating ~165 LoC of claude-eval substrate code. Wave 0 (deletes/oneshots) can proceed in parallel. |
| K24 | **Drop email notification path (RESEND).** Sentry heartbeats + Better Stack is sufficient observability. | 14 of 25 remaining workflows used `notify-ops-email` GHA composite action. Sentry-only simplifies migration. Operator confirmed. |
| K25 | **Convert f2-defer-gate-review to Inngest oneshot NOW (before May 29 fire date).** | Same pattern as `oneshot-gdpr-gate-50d-eval.ts`. Operator prefers immediate conversion over wait-and-delete. |
| K26 | **Don't wait for `/soleur:migrate-cron-to-inngest` skill (#3990).** Proceed manually. Productize AFTER Phase 2 completes, informed by the full 38+ migration corpus. | CPO recommendation: the skill will be better designed after Phase 2 surfaces all edge cases. |
| K27 | **gh CLI is NOT in the production Dockerfile.** All Group C shell-to-TS ports MUST use Octokit, not bash spawn. | Critical learning from PR-6 (`2026-05-25-tr9-pr6-strategy-review-no-bash-spawn-octokit-port-pattern.md`). Enumerate each script's CLI deps and confirm against Dockerfile before porting. |
| K28 | **New secrets to Doppler:** Social API tokens (10 for content-publisher), Plausible API key, CF API token, LinkedIn org tokens, GH App driftguard keys, Doppler dev-scheduled token. | Per-workflow secret inventory in repo-research report. Mirror from GHA secrets to Doppler `prd` config before each function migrates. |
| K29 | **2 workflows need `/soleur:gdpr-gate` at plan time:** `scheduled-realtime-probe` and `scheduled-dev-migration-drift` (both access dev Supabase project). | CLO bucket (ii) classification. Dev-project access is PII-adjacent under `hr-dev-prd-distinct-supabase-projects`. |
| K30 | **Wave 3 cascade handling:** `scheduled-weekly-analytics` dispatches 3 CMO workflows on KPI miss. Convert the cascade to `inngest.send()` events. Migrate weekly-analytics and its 3 targets as a batch. | CTO recommendation: temporal coupling during partial migration creates ordering risk. Batch avoids it. |

## Open Questions (for plan-time)

1. **Docker image dependencies for Group C ports.** Some shell ports may need binaries beyond node:22-slim + git + bubblewrap + socat. Inventory per-workflow: `curl` (available via node `fetch`), `jq` (use JS), `git clone` (available). Verify at plan time.

2. **Sentry apply-infra -target= allowlist.** Each new `sentry_cron_monitor` resource must be added to the explicit `-target=` list in `apply-sentry-infra.yml` in the same commit. Verify count increments per PR.

3. **realtime-probe dev/prd boundary.** This probe runs against the dev Supabase instance using `DOPPLER_TOKEN_DEV_SCHEDULED`. Running inside the production Inngest worker (which IS the production web-platform process) creates a dev/prd boundary concern. Plan-time: consider spawning with scoped env vars.

4. **weekly-analytics cascade migration order.** The 3 dispatched workflows (`scheduled-seo-aeo-audit`, `scheduled-growth-execution`, `scheduled-content-generator`) are in Wave 1 (Group A). If Wave 1 completes before Wave 3 reaches weekly-analytics, the cascade targets are already on Inngest and the `inngest.send()` pattern works. If not, the weekly-analytics port must temporarily use Octokit `workflow_dispatch` as a bridge.

5. **Route registration file growth.** Adding ~21 more function imports to `app/api/inngest/route.ts` brings it to ~40 entries. Consider a barrel export from `functions/index.ts` at plan time.

6. **Concurrency pool assignment per function.** Decision tree: function spawns `claude` binary → `cron-platform-heavy`. Function is pure TS → `cron-platform-light`. Oneshots and event-triggered functions → `cron-platform-heavy` if they spawn claude, `cron-platform-light` otherwise.

## User-Brand Impact

**Threshold:** `single-user incident` (carry-forward from Phase 1; operator re-affirmed 2026-05-26, selected all three vectors: data loss, credential leak, no direct user impact).

**Vectors:**

| Vector | Worst-case user experience | Load-bearing invariant |
|--------|----------------------------|------------------------|
| Silent loop failure | Platform agent-loop stops running (missed content publishing, missed security audits, missed drift detection), no notification, work silently rots | K11 Sentry heartbeat + K22 dual pools prevent queue starvation |
| Credential / token leak | Social API tokens (X/Twitter OAuth, LinkedIn OAuth) or Terraform credentials exposed via Inngest event payloads, logs, or misrouted execution | K20 (terraform stays on GHA), K21 (sweeper stays on GHA), K28 (Doppler-only, no env passthrough) |
| Cross-tenant agent action | Future refactor couples a cron to per-founder context | K12 `actor: "platform"` + BYOK sweep inverse-assertion |
| Replay-cost runaway | Inngest replays a step.run containing a claude-code session | K9 spawn inside step.run for memoization, K10 cron_run_ledger jitter-guard |

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support.

Triad spawned mandatory (`USER_BRAND_CRITICAL=true`): CPO + CLO + CTO.

### Engineering (CTO)

**Summary:** Substrate gap is the concurrency model — `cron-platform` limit:1 causes Monday 09:00 pile-up with 35+ functions. Recommends dual pools (K22). Terraform-drift is the one workflow where GHA's ephemeral runners are genuinely superior (K20). #4472 substrate extraction is a hard prerequisite for Wave 1 to avoid 3,300+ LoC of duplicated infrastructure code. Followthrough-sweeper's dynamic script execution model requires process-level secret isolation that the persistent Inngest worker doesn't provide (K21). Estimated 3-4 weeks for full Phase 2.

### Product (CPO)

**Summary:** 5-week reliability evidence plus mechanical repeatability of 11 per-workflow PRs is sufficient to reverse the Phase 1 deferral. PR-G (#3947) shipped 2026-05-19, so K15 rationale is moot. Recommends Wave 0 (delete 3 one-shots) for immediate count reduction. Don't wait for skill #3990 — productize after Phase 2 completes (K26). Weekly-analytics cascade should migrate as a batch with its 3 dispatch targets. Promote #3948 from Post-MVP to active milestone.

### Legal (CLO)

**Summary:** No Article 30 register changes needed for Phase 2 (no new processing activities, no new sub-processors, no new data categories). Social API token migration to Doppler has no data-processing register impact (write-path marketing tokens, not user PII). Two workflows need `/soleur:gdpr-gate` at plan time: realtime-probe and dev-migration-drift (both access dev Supabase, bucket-ii per `hr-dev-prd-distinct-supabase-projects`). K16-K19 carry forward unchanged. Terraform-drift and followthrough-sweeper staying on GHA preserves Art. 32 TOM posture.

## Capability Gaps

**1. Dual concurrency pool configuration (ADR-033 amendment).**
- **What is missing:** The current ADR-033 documents a single `cron-platform` concurrency key. Phase 2 needs two pools.
- **Domain:** Engineering.
- **Why needed:** K22 — without dual pools, Monday 09:00 pile-up causes multi-hour queue delays.
- **Evidence:** `grep -c 'cron-platform' apps/web-platform/server/inngest/functions/cron-*.ts` returns 14 — all current functions use the single key.

**2. #4472 shared substrate extraction.**
- **What is missing:** `_cron-claude-eval-substrate.ts` and `_cron-shared.ts` shared helpers.
- **Domain:** Engineering.
- **Why needed:** K23 — prevents 5+ more functions duplicating ~165 LoC each.
- **Evidence:** Issue #4472 OPEN, active worktree at `feat-one-shot-4472-cron-substrate-extraction`.

**3. Doppler secrets for new workflows.**
- **What is missing:** Social API tokens, Plausible API key, CF API token, LinkedIn org tokens, GH App driftguard keys not yet in Doppler `prd`.
- **Domain:** Operations.
- **Why needed:** K28 — each migrated function reads secrets from Doppler, not GHA secrets.
- **Evidence:** Repo-research secret inventory per workflow.

## Productize Candidate

Per Phase 2.5: the migration pattern now proven across 14 + upcoming ~21 functions (35 total). **Candidate skill: `/soleur:migrate-cron-to-inngest <workflow-name>`** — issue #3990 (OPEN). Decision K26: build AFTER Phase 2 completes, not before.

## Deferred to follow-up issues

- **`/soleur:migrate-cron-to-inngest` skill (#3990):** Productize after Phase 2 completes.
- **ADR-034 (ephemeral cron workspace) + ADR-033 I3 amendment (#4381):** Per-handler timeout tuning. Open issue.
- **Inngest queue-depth + per-cron last-fire metric (#4131):** Observability follow-through.
- **cron-workspace helper extraction (#4382):** Post-PR-5 refactor.

## References

- **Phase 1 brainstorm:** `knowledge-base/project/brainstorms/2026-05-18-tr9-agent-loop-crons-inngest-migration-brainstorm.md`
- **ADR-033:** `knowledge-base/engineering/architecture/decisions/ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md`
- **Prompt file:** `.worktrees/feat-one-shot-4472-cron-substrate-extraction/knowledge-base/project/prompts/2026-05-26-tr9-phase-2-migrate-all-remaining-gha-to-inngest.md`
- **Key learnings carried forward:**
  - `2026-05-26-tr9-pr11-compound-promote-pure-ts-port-pattern.md` (PR-6/PR-7 decision tree)
  - `2026-05-25-tr9-pr6-strategy-review-no-bash-spawn-octokit-port-pattern.md` (gh CLI not in Dockerfile)
  - `2026-05-25-tr9-pr6-gray-matter-yaml11-date-coercion-trap.md` (frontmatter date coercion)
  - `2026-05-19-inngest-substrate-five-bug-cascade.md` (5-bug cascade self-check)
  - `2026-05-18-vendor-cron-heartbeat-silent-fail-pattern.md` (single heartbeat pattern)
  - `2026-05-25-yaml-prompt-to-template-literal-backtick-escaping.md` (backtick escaping)
  - `2026-05-20-inngest-heartbeat-doppler-env-injection.md` (Doppler env injection)
  - `2026-05-15-token-namespace-divergence-across-secret-stores.md` (cross-store token divergence)
