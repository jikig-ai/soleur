---
lane: cross-domain
brand_survival_threshold: single-user incident
parent_epic: "#3244"
parent_pr_merged: "#3940 (PR-F, 2026-05-17)"
sibling_open: "#3947 (PR-G — cohort onboarding)"
issue: "#3948"
type: focused
---

# TR9 — Group-(c) Agent-Loop Crons → Inngest Migration (Brainstorm)

**Date:** 2026-05-18
**Worktree:** `.worktrees/feat-agent-loop-crons-inngest-tr9`
**Branch:** `feat-agent-loop-crons-inngest-tr9`
**Draft PR:** [#3985](https://github.com/jikig-ai/soleur/pull/3985)
**Parent epic:** [#3244](https://github.com/jikig-ai/soleur/issues/3244) — *Command Center server-side agentic runtime*
**Direct predecessor:** PR-F [#3940](https://github.com/jikig-ai/soleur/pull/3940) — MERGED 2026-05-17, shipped Inngest substrate self-hosted on Hetzner.

## Scope of this brainstorm

PR-F's K14 explicitly deferred this work: *"Move ZERO cron workflows in PR-F. ~14 group-(c) agent loops are eventual TR9 scope; even those move per-workflow in follow-up issues."* This brainstorm reshapes #3948 from "one big migration" into:

1. **Out-of-scope removals (3 workflows).** Three named candidates are self-disabling one-shots, not recurring crons; subtract them from the migration set.
2. **PR-1 proof-of-pattern (1 workflow).** Operator-chosen target: `scheduled-daily-triage` — lands the full primitive stack (claude-code spawn + cron_run_ledger + Sentry heartbeat + `actor: "platform"` invariant + delete-GHA-YAML-same-commit) on a high-blast-radius write-class workflow.
3. **#3948 reshapes into umbrella.** Each of the remaining 10 recurring workflows gets a child issue, migrated per-workflow.
4. **gdpr-gate-50d as one-shot Inngest function.** Converted to `inngest.send`-triggered (not cron-scheduled) because it has never fired (June 29 schedule, today is 2026-05-18) and the one-shot UX preserves its self-neutralizing design.

## What We're Building

**Three workflow-class outputs from this issue:**

- **PR-1 (proof-of-pattern):** Migrate `scheduled-daily-triage` to Inngest cron function `cron-daily-triage.ts`. Validates the full primitive stack so subsequent migrations are mechanical. ADR (`/soleur:architecture create "Inngest cron functions invoke claude-code via child_process.spawn"`) lands BEFORE PR-1 code (status `proposed`; flipped `accepted` on merge).
- **PR-cleanup (out-of-scope removal):** Delete `scheduled-dogfood-once-3049.yml` + `-v2.yml` outright — both already fired 2026-05-04, parent issue #3049 closed. Could bundle with PR-1 or land as a tiny independent PR.
- **PR-1.5 (gdpr-gate-50d):** Convert `scheduled-gdpr-gate-preflight-eval-50d` to event-triggered Inngest function (not cron). Issue body lists it under TR9, but its semantics are one-shot — `inngest.send` preserves intent better than cron.
- **#3948 umbrella reshape:** Issue body updated to list 10 recurring child workflows as checkboxed items; close criterion = all 10 children merged + GHA `.github/workflows/scheduled-*.yml` files for those 10 deleted.

**Substrate primitives PR-1 establishes (binding the next 10 PRs):**

1. **`apps/web-platform/server/inngest/functions/cron-*.ts`** naming convention. Confirmed by repo research: zero cron-scheduled Inngest functions exist today; the only registered function is `cfo-on-payment-failed.ts` (event-triggered). `inngest.createFunction({id}, {cron: "0 4 * * *"}, handler)` is the verified registration shape from `node_modules/inngest/types.d.ts:154-161`.
2. **`child_process.spawn('claude-code', ...)` inside `step.run('claude-eval', ...)`** for replay memoization. Preserves existing claude-code-action agent-prompt files as-is. Decided over SDK rewrite as the lower-risk port (CTO recommendation, operator-confirmed).
3. **`cron_run_ledger(function_name, last_run_at)` Supabase table** — jitter-guard primitive. First step of every cron function reads the ledger and early-returns if `<80%` of the cron interval has elapsed. Defense against Inngest replay storms AND duplicate-fire on cron edge cases.
4. **Sentry check-in heartbeat at end-of-`step.run`** (single POST, `if: always()`-style) — per `2026-05-18-vendor-cron-heartbeat-silent-fail-pattern.md`. NO two-step in_progress→ok shape (the trap pattern just got cleaned up across 7 sister workflows).
5. **`actor: "platform"` event-payload tag** — load-bearing boundary marker that lets platform-loop crons and per-founder runtime share one Inngest server. Inverse-assertion in `byok-audit-writer-sweep.test.ts`: files matching `cron-*.ts` MUST NOT import `runWithByokLease`.
6. **Delete GHA YAML in same commit Inngest function lands** — per learning `2026-05-16-migration-mandates-must-have-wired-call-sites-in-same-pr.md`. Rollback = revert the PR.

## Why This Approach

**Why proof-of-pattern on the hardest target (`scheduled-daily-triage`):** the CPO recommended `scheduled-strategy-review` as PR-1 (shell-only, sidesteps the `claude-code` spawn problem entirely). The operator overrode to pick `scheduled-daily-triage` — daily 4am, 60-min timeout, label-mutator + comment-writer, claude-code-action. This is the deliberate harder path: PR-1 lands the FULL primitive stack — including the `claude-code` spawn substrate gap — in one decisive review, so the remaining 10 migrations are mechanical reuse instead of re-litigating architecture per-PR.

**Why per-workflow PR shape (K14 preserved):** CTO argued for bundling 5 read-only audits. CPO held per-workflow with #3948 as umbrella. Operator confirmed per-workflow. Trade-off: slower migration, but each PR is independently reviewable + revertable. Write-class workflows (triage, sweeper, bug-fixer, follow-through, community-monitor) have genuinely different blast radii — bundling would inherit the worst-case review surface across the bundle. Audit workflows are slow-cadence (monthly/quarterly), so per-workflow review cost is amortized.

**Why ship TR9 BEFORE PR-G (#3947):** CPO + CLO converged. PR-G gates `SOLEUR_FR5_ENABLED=true` cohort exposure. While `SOLEUR_FR5_ENABLED=false`, no founder cohort touches the runtime — platform-loop crons execute against operator data only. Landing TR9 ahead of PR-G consolidates scheduling onto Inngest before founder traffic, so the SRE surface PR-G inherits is one substrate, not two.

**Why self-host (not Inngest Cloud):** carry-forward from PR-F K12. Self-hosted on Hetzner avoids a new sub-processor disclosure cycle, no Article 30 amendment for the substrate itself. Re-evaluation criteria: third hosted founder OR concurrency cap pressure → revisit Cloud Hobby. Math today: 14 daily-or-weekly crons → ~420 executions/mo. Hobby's binding constraint is the 5-concurrent-step cap, which self-hosted bypasses entirely (CPU/memory of Hetzner node is the bound). No tier change needed.

## Key Decisions

### Carry-forward from PR-F (Increment 3) + ADR-030

| # | Decision | Source |
|---|----------|--------|
| K1 | Inngest substrate is `inngest@^3` self-hosted on Hetzner; signing key throws at boot. | PR-F K1 + K8 + K12 |
| K2 | CEL concurrency expression for fn-scope + account-scope limits. | PR-F K2 |
| K3 | `event.v` envelope schema versioning at consumer boundary; MIN=MAX=1; `if v > MAX throw; if v < MIN deadletter`. | PR-F K3 |
| K4 | `step.run` memoizes — verify-external-state must NOT live inside `step.run`. | PR-F K4 + ADR-030 §I6 |
| K5 | `runWithByokLease` opens INSIDE each `step.run` that calls the Anthropic SDK. (Platform-loop crons exempt — operator key only.) | PR-F K13 + ADR-030 §I1 |
| K6 | Inngest Pro is $75/mo; self-hosted has no Inngest-side cost. Hobby tier: 50k executions/mo, 5 concurrent steps, 24h trace retention. | PR-F K6 |

### New decisions for TR9 (deltas this brainstorm introduces)

| # | Decision | Why |
|---|----------|-----|
| K7 | **PR-1 = `scheduled-daily-triage`** (operator override on CPO recommendation). | Operator-confirmed 2026-05-18. Picking the highest-blast-radius target as proof-of-pattern means the full primitive stack lands in one decisive review; subsequent 10 migrations are mechanical. The other 10 are blocked on PR-1 (substrate primitives + ADR). |
| K8 | **Per-workflow PR shape; #3948 reshaped as umbrella with 10 child checkboxes.** | K14 preserved (PR-F discipline). Each migration is one PR with one acceptance criterion: behavior preserved + GHA YAML deleted in same commit. Write-class blast radii are heterogeneous; bundling inherits worst-case review surface. |
| K9 | **`child_process.spawn('claude-code', ...)` inside `step.run`** is the claude-code invocation primitive. | Lower-risk port than SDK rewrite. Preserves existing agent-prompt files. ADR written via `/soleur:architecture create "Inngest cron functions invoke claude-code via child_process.spawn"` BEFORE PR-1 code lands (status `proposed`, flipped `accepted` on merge). |
| K10 | **`cron_run_ledger` Supabase table** as jitter-guard primitive (first `step.run` of every cron function). | Defense against Inngest replay storms + cron edge-case duplicate-fire. Behavior is "if last_run_at within 80% of cron interval → early return." Dev/prd-distinct projects per `hr-dev-prd-distinct-supabase-projects`. |
| K11 | **Sentry check-in heartbeat at end-of-`step.run`** (single POST). | Per today's `2026-05-18-vendor-cron-heartbeat-silent-fail-pattern.md` learning. NO two-step in_progress→ok shape. Each migrated function provisions its own Sentry monitor via IaC. |
| K12 | **`actor: "platform"` event-payload tag** required on every migrated cron's emitted event. Inverse-assertion in `byok-audit-writer-sweep.test.ts`: `cron-*.ts` files MUST NOT import `runWithByokLease`. | Boundary marker between platform-loop + per-founder runtime on one Inngest server. Without it, regulated-data-surface flag fires under `hr-gdpr-gate-on-regulated-data-surfaces` once PR-G ships. |
| K13 | **Delete GHA YAML in same commit Inngest function lands.** No dual-fire window. | Per `2026-05-16-migration-mandates-must-have-wired-call-sites-in-same-pr.md`. Rollback = revert. |
| K14 | **3 self-disabling one-shots OUT of #3948 scope:** `scheduled-dogfood-once-3049.yml` (DELETE — fired 2026-05-04, issue #3049 closed); `scheduled-dogfood-once-3049-v2.yml` (DELETE — fired 2026-05-04, issue closed); `scheduled-gdpr-gate-preflight-eval-50d.yml` (CONVERT — never fired, schedule June 29; migrate to `inngest.send`-triggered Inngest function preserving one-shot UX). | Verified via `gh run list` + `gh issue view 3049`. Issue body lists 14; actual recurring migration set is 11 (15 candidates − 3 one-shots − 1 already chosen as PR-1 = 10 remaining for umbrella children). |
| K15 | **TR9 ships BEFORE PR-G (#3947).** | CPO + CLO convergence. While `SOLEUR_FR5_ENABLED=false`, no founder cohort touches the runtime; consolidate substrate before founder traffic. PR-G inherits one substrate, not two. |
| K16 | **NO key rotation required at migration.** `ANTHROPIC_API_KEY` is same trust boundary (operator runtime) in GHA secrets vs Doppler. CLO: defense-in-depth optional, not compliance-required. Log key-source transition in migration ADR for audit trail. | CLO assessment (d). |
| K17 | **`hr-autonomous-loop-skill-api-budget-disclosure` is a NO-OP for TR9 today** (operator-key, not founder-BYOK). Guard ADR records carry-forward: re-evaluate disclosure if any cron transitions to per-founder. | CLO assessment (c). |
| K18 | **Per-workflow data-class audit required before each non-PR-1 migration.** Workflows touching potentially-founder-PII-adjacent data (`scheduled-followthrough-sweeper`, `scheduled-community-monitor`, `scheduled-follow-through`) trigger Article 30 register amendment naming the founder-PII processing activity even though substrate is unchanged. | CLO assessment (a). |
| K19 | **No new sub-processor.** Self-hosted Inngest on Hetzner preserves PR-F's sub-processor posture; no DPA refresh, no Privacy/DPD update for substrate. | CLO assessment (a) + carry-forward from PR-F. |

## Migration set (after K14 scope reshape)

**PR-1 proof-of-pattern (1 workflow):**
- [ ] `scheduled-daily-triage` (`0 4 * * *`, 60min, label-mutator + comment-writer, claude-code-action)

**Out-of-scope removals (3 workflows, 1 small PR or bundled with PR-1):**
- [ ] DELETE `scheduled-dogfood-once-3049.yml` (fired 2026-05-04, issue #3049 closed)
- [ ] DELETE `scheduled-dogfood-once-3049-v2.yml` (fired 2026-05-04, issue closed)
- [ ] CONVERT `scheduled-gdpr-gate-preflight-eval-50d.yml` → `inngest.send`-triggered function preserving one-shot UX

**Umbrella children (10 workflows, per-workflow follow-up issues):**
- [ ] `scheduled-followthrough-sweeper` (`0 18 * * *`, 10min, comment-writer, NO Anthropic) — CLO bucket (ii), Article 30 audit before migration
- [ ] `scheduled-bug-fixer` (`0 6 * * *`, 45min, pr-creator, claude-code-action)
- [ ] `scheduled-strategy-review` (`0 8 * * 1`, 5min, issue-creator via shell, NO Anthropic) — CPO's original PR-1 pick; trivial migration after PR-1
- [ ] `scheduled-roadmap-review` (`0 9 * * 1`, 30min, issue-creator + pr-creator, claude-code-action)
- [ ] `scheduled-community-monitor` (`0 8 * * *`, 30min, kb-writer + pr-creator, claude-code-action) — CLO bucket (ii), Article 30 audit
- [ ] `scheduled-ux-audit` (`0 9 1 * *`, 45min, read-only artifact-only, claude-code-action)
- [ ] `scheduled-legal-audit` (`0 11 1 1,4,7,10 *`, 60min, issue-creator, claude-code-action)
- [ ] `scheduled-competitive-analysis` (`0 9 1 * *`, 45min, kb-writer + pr-creator + issue-creator, claude-code-action)
- [ ] `scheduled-compound-promote` (`0 0 * * 0`, 15min, pr-creator, direct ANTHROPIC_API_KEY shell driver)
- [ ] `scheduled-agent-native-audit` (`0 9 15 * *`, 45min, issue-creator, claude-code-action)
- [ ] `scheduled-follow-through` (`0 9 * * 1-5`, 15min, comment-writer + label-mutator, claude-code-action) — CLO bucket (ii), Article 30 audit

Wait — that's 11 children, not 10. Re-counting: 15 candidates − 1 (PR-1: daily-triage) − 3 (one-shots) = **11 umbrella children**. Brainstorm aside fixed to 11.

## Open Questions (for plan-time)

1. **`claude-code` binary path on Hetzner runtime.** Spawning `child_process.spawn('claude-code', ...)` assumes the binary is in the runtime's $PATH and matches the claude-code-action version. Plan-time: confirm via `apps/web-platform/infra/server.tf` or cloud-init script that `claude-code` CLI is installed, AND pin a version (consider `npm install -g @anthropic-ai/claude-code@<version>` in cloud-init). If not, IaC needs an addendum before PR-1.

2. **Agent-prompt file layout for Inngest functions.** The existing `claude-code-action` invocation reads the agent prompt inline in the workflow YAML. For Inngest functions, where do agent prompts live? Options: (a) inline TS string literals, (b) co-located `*.prompt.md` files alongside `cron-*.ts`, (c) reuse the same prompt files as `claude-code-action`. Recommendation lean: option (b) for grep-ability + version control of prompt changes. Resolve at PR-1 plan time.

3. **`cron_run_ledger` table shape.** Single row per function (UPSERT on `function_name`) or append-only? Append-only enables forensics on missed runs; single-row is simpler. Plan-time decision; default to single-row UPSERT unless plan finds a forensic requirement.

4. **Sentry monitor IaC pattern.** PR-F shipped Sentry Crons monitor IaC (`apps/web-platform/infra/sentry/cron-monitors.tf` per the 2026-05-18 learning). Each migrated Inngest function needs an entry. Pattern: terraform module per function, or one big monitor list? Plan-time.

5. **GHA `ANTHROPIC_API_KEY` org secret → Doppler migration moment.** PR-F already has `ANTHROPIC_API_KEY` in Doppler `prd` (used by the Stripe→CFO runtime). PR-1 reuses; no migration needed. But: the GH Actions secret is currently still consumed by the OTHER 14 scheduled workflows. Don't touch the GH org secret until all migrations land — or each migration would break the unmigrated workflows. Plan-time: confirm secret stays in both places until #3948 umbrella closes.

6. **Should the ADR (`/soleur:architecture create`) live in the proof-of-pattern PR or land separately?** PR-F K19 prescribed "ADR before code." For PR-1 specifically, the ADR is small (single decision: spawn-child vs SDK). Bundling reduces review fragmentation; landing separately satisfies K19 literally. Recommendation lean: write ADR as `proposed` in PR-1, flip to `accepted` on merge.

7. **`scheduled-followthrough-sweeper` data-class verification.** Uses NEITHER Anthropic nor claude-code-action — it's a pure shell sweeper. Its 10-min timeout suggests a fast operation. Read what it actually does before migration: if it only reads operator GitHub issues (no founder-PII), CLO bucket (i) and skip Article 30 amendment. If it reads founder-tagged issues (post-PR-G), bucket (ii). Plan-time per K18.

## User-Brand Impact

**Threshold:** `single-user incident` (carry-forward from PR-F; operator re-affirmed 2026-05-18, selected all of cross-tenant + silent failure + credential leak). CPO refined: the vector applicable to TR9 specifically is **"platform agent-loop misbehavior degrades the experience for every cohort founder simultaneously"** — not per-founder cross-tenant, because these crons are single-operator today.

**Vectors:**

| Vector | Worst-case user experience | Load-bearing invariant |
|--------|----------------------------|------------------------|
| Cross-tenant agent action (forward-looking) | A future refactor accidentally couples a cron to per-founder context; cron runs as Founder A but reads Founder B's data | K12 `actor: "platform"` event-payload tag + inverse-assertion in sentinel sweep (`cron-*.ts` MUST NOT import `runWithByokLease`). Both directions enforced; drift detected at CI. |
| Silent loop failure | Founder's scheduled triage/sweeper/audit stops running, no notification, work silently rots until manual discovery (days/weeks) | K11 Sentry check-in heartbeat at end-of-`step.run`. No `\|\| true`-wrapped silencers. Sentry monitor cadence matches actual fire interval. |
| Credential / token leak | Per-founder GitHub PATs or Doppler service tokens exposed via Inngest event payloads, logs, or misrouted execution | K12 platform-only invariant — operator key only, NO founder credentials in event payloads. Existing PR-F sentinel pattern (writer-sweep) already gates per-founder credential writes elsewhere. |
| Replay-cost runaway | Inngest replays a `step.run` containing a Claude Code session; same expensive call fires multiple times unbilled | K9 spawn-child inside `step.run` for memoization. K10 `cron_run_ledger` jitter-guard. Plan-time: assert deterministic output capture so memoization fires reliably. |

**Plan-time gates:**

- `user-impact-reviewer` MUST sign off (operator confirmed `single-user incident` threshold).
- preflight Check 6 fires on `apps/web-platform/server/inngest/functions/cron-*.ts`, `apps/web-platform/test/server/byok-audit-writer-sweep.test.ts`, `apps/web-platform/infra/inngest.tf`, `apps/web-platform/infra/sentry/cron-monitors.tf`, and any new `cron_run_ledger`-touching migration files under `apps/web-platform/supabase/migrations/**`.
- `/soleur:gdpr-gate` invoked at plan Phase 2.7 for any bucket (ii) workflow (`scheduled-followthrough-sweeper`, `scheduled-community-monitor`, `scheduled-follow-through`).

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support.

Triad spawned mandatory (`USER_BRAND_CRITICAL=true`): CPO + CLO + CTO. COO/Sales/Finance/Marketing/Support not spawned (no external surface, no pipeline impact, no cohort exposure yet — TR9 is operator-internal infrastructure).

### Engineering (CTO)

**Summary:** Substrate gap identified: `claude-code-action` spawns a fresh sandboxed process per run; Inngest functions are long-lived workers. Resolution = `child_process.spawn('claude-code', ...)` inside `step.run` for replay memoization (K9). Idempotency primitives differ per archetype (label-mutator = set-union natural key; issue-creator = search-before-create; read-only = pure-function step.run memoization). Hobby tier execution budget has 15× headroom; binding constraint is 5-concurrent-step cap, sidestepped by self-hosted. Sentinel sweep needs inverse-assertion guarding the platform-only invariant.

### Product (CPO)

**Summary:** Ship TR9 BEFORE PR-G #3947. Recommended `scheduled-strategy-review` as PR-1 (shell-only, simplest); operator override picked `scheduled-daily-triage` for a more decisive proof. #3948 reshapes to umbrella with per-workflow children. Encode `actor: "platform"` invariant in spec. Re-evaluation criteria for any unmigrated workflow: (1) silent-failure incident, (2) sub-hourly drift causes founder-visible SLA miss, (3) Hobby execution budget >70%, (4) any remaining GHA cron touched by founder-facing PR (coupling signal).

### Legal (CLO)

**Summary:** Self-hosted Inngest avoids new sub-processor cycle (K19). Per-workflow Article 30 audit required for bucket (ii) workflows touching potentially-founder-PII-adjacent data (`followthrough-sweeper`, `community-monitor`, `follow-through`). `hr-autonomous-loop-skill-api-budget-disclosure` is NO-OP for platform-loop crons today; guard ADR records re-evaluation criteria (K17). No key rotation required at migration (K16). TR9 does NOT need PR-G first as long as `actor: "platform"` invariant is enforced (K12, K15).

## Capability Gaps

**1. `claude-code` binary on Hetzner runtime.**
- **What is missing:** Confirmation that `claude-code` CLI is installed on the Hetzner Inngest worker host with a pinned version.
- **Domain:** Engineering/Operations.
- **Why needed:** K9 prescribes `child_process.spawn('claude-code', ...)`. If binary is missing or version-unpinned, PR-1 cannot run.
- **Evidence:** `apps/web-platform/infra/server.tf` exists per repo research B; cloud-init script presence + claude-code install verified at plan time, not brainstorm time.

**2. `cron_run_ledger` Supabase primitive.**
- **What is missing:** No shared module/table for cron-function last-run-at reads/writes.
- **Domain:** Engineering/Data.
- **Why needed:** K10 jitter-guard is the load-bearing primitive for all 11 migrations; hand-rolling 11× invites drift.
- **Evidence:** `grep -rEn 'cron_run_ledger' apps/web-platform/` returns no matches (verify at plan time); no migration file under `apps/web-platform/supabase/migrations/` references it.

**3. Inngest cron-function scaffolder skill (CTO-flagged).**
- **What is missing:** No skill scaffolds an Inngest scheduled function with built-in jitter-guard + Sentry heartbeat + replay-memoized claude-code spawn + actor:platform tag.
- **Domain:** Engineering.
- **Why needed:** Reduces drift on the failure-mode-prevention contract across 11 migrations.
- **Evidence:** `ls plugins/soleur/skills/ | grep -i cron` returns no match (verify at plan time).
- **Note:** This is the **Productize Candidate** flagged at Phase 2.5 (see below). May be a follow-up issue rather than a PR-1 prereq if the first 2-3 migrations are mechanical enough that the skill payoff is unclear.

## Productize Candidate

Per Phase 2.5: the inciting work pattern (migrate one GHA cron to an Inngest function with claude-code spawn + jitter-guard + Sentry heartbeat + actor tag + delete-YAML-same-commit) recurs 11 times. **Candidate skill: `/soleur:migrate-cron-to-inngest <workflow-name>`** — scaffolds the `cron-<name>.ts` file from the GHA YAML, generates the integration test, and enforces the delete-YAML-same-commit invariant via a check in the skill flow. Filed as a follow-up issue at brainstorm close (do NOT pivot this brainstorm's scope).

## Deferred to follow-up issues

- **The 11 umbrella children** (per K8, listed in Migration set above) — each is a follow-up issue parented to #3948 as umbrella.
- **`/soleur:migrate-cron-to-inngest` skill** (Productize Candidate above) — file separately; evaluate after PR-1 + 1-2 mechanical follow-ups land.
- **Migration of remaining group-(b) content production workflows** (~8 workflows, per PR-F K14 classification) — explicitly out of TR9 scope; stays on GH Actions.
- **Migration of group-(a) CI infra workflows** (~18 workflows, per PR-F K14 classification) — STAYS on GH Actions; never migrates.

## References

- **Parent epic:** `#3244` — Command Center server-side agentic runtime.
- **Direct predecessor:** `#3940` (PR-F) — MERGED 2026-05-17; shipped Inngest substrate, IaC, ADR-030.
- **Direct predecessor brainstorm:** `knowledge-base/project/brainstorms/archive/20260517-203729-2026-05-17-pr-f-inngest-trigger-layer-brainstorm.md` — K14 deferred this migration, K12 locked self-hosted-on-Hetzner.
- **Parent plan:** `knowledge-base/project/plans/2026-05-05-feat-soleur-server-side-agentic-runtime-plan.md` §3.7 "TR9 failure-mode prevention summary" (line 745) + Increment 3 maps to TR1/TR6/TR7/TR9 (line 28).
- **ADR-030** `knowledge-base/engineering/architecture/decisions/ADR-030-inngest-as-durable-trigger-layer.md` — Inngest as durable trigger layer; invariants I1 (BYOK lease per step.run), I2 (JWT per step.run), I3 (concurrency), I4 (signing key throws at boot), I6 (no verify-external-state in step.run).
- **Sibling open:** `#3947` (PR-G) — cohort onboarding, gates `SOLEUR_FR5_ENABLED=true`. TR9 ships before per K15.
- **Substrate inventory** (per repo research): `apps/web-platform/server/inngest/client.ts`, `apps/web-platform/server/inngest/functions/cfo-on-payment-failed.ts`, `apps/web-platform/app/api/inngest/route.ts`, `apps/web-platform/infra/inngest.tf`. Zero cron-scheduled Inngest functions exist today.
- **Cron registration shape** (verified): `inngest.createFunction({id}, {cron: "0 4 * * *"}, handler)` per `apps/web-platform/node_modules/inngest/types.d.ts:154-161`.
- **AGENTS.md rules touched:** `hr-weigh-every-decision-against-target-user-impact`, `hr-write-boundary-sentinel-sweep-all-write-sites`, `hr-dev-prd-distinct-supabase-projects`, `hr-gdpr-gate-on-regulated-data-surfaces`, `hr-autonomous-loop-skill-api-budget-disclosure`, `hr-new-skills-agents-or-user-facing` (productize candidate), `cq-silent-fallback-must-mirror-to-sentry`.
- **Learnings carried forward:**
  - `2026-05-18-vendor-cron-heartbeat-silent-fail-pattern.md` (K11 Sentry heartbeat shape)
  - `2026-05-18-composite-action-extraction-inline-on-multi-file-rollout.md` (per-workflow PR shape vs cross-cutting-refactor scope-out)
  - `2026-05-16-migration-mandates-must-have-wired-call-sites-in-same-pr.md` (K13 delete-YAML-same-commit)
  - `2026-05-07-claude-code-action-boundaries-and-once-schedule-bundle.md` (claude-code-action semantics)
  - `2026-05-04-claude-code-action-app-token-lacks-actions-write.md` (token caveats — informs spawn permissions on Inngest worker)
  - `2026-03-20-claude-code-action-max-turns-budget.md` (~10-turn plugin overhead per invocation; informs cost ceiling)
  - `2026-05-12-type-widening-cascades-and-write-boundary-sentinels.md` (K12 sentinel-sweep inverse assertion)
  - `2026-04-18-schema-version-must-be-asserted-at-consumer-boundary` (K3 event.v envelope, carry-forward from PR-F K3)
