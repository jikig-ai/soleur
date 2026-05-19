---
lane: cross-domain
brand_survival_threshold: single-user incident
parent_epic: "#3244"
parent_pr_merged: "#3940 (PR-F)"
issue: "#3948"
sibling_open: "#3947 (PR-G)"
status: brainstorm-complete
created: 2026-05-18
---

# feat: TR9 — Group-(c) Agent-Loop Cron Migration to Inngest (Proof-of-Pattern + Umbrella)

## Problem Statement

11 recurring agent-loop cron workflows live in `.github/workflows/scheduled-*.yml`, currently scheduled by GitHub Actions and invoked via `claude-code-action` against the operator `ANTHROPIC_API_KEY` org secret. GitHub Actions' scheduling has documented sub-hourly jitter (`*/5`/`*/15` schedules degrade to ~60-min effective cadence per `2026-05-18-vendor-cron-heartbeat-silent-fail-pattern.md`) AND no native replay/idempotency contract. PR-F (#3940, MERGED 2026-05-17) shipped the Inngest substrate self-hosted on Hetzner as the durable trigger layer; per parent plan TR9 "cron lives in Inngest, not GH Actions" — but PR-F deliberately deferred the migration (K14: "Move ZERO cron workflows in PR-F").

This spec scopes the proof-of-pattern migration + reshapes #3948 from "one big migration" into umbrella + child issues.

## Goals

- **G1.** Migrate `scheduled-daily-triage` to an Inngest cron function (`cron-daily-triage.ts`) preserving current label-mutator + comment-writer behavior.
- **G2.** Establish the substrate primitives binding the next 10 migrations: `claude-code` spawn pattern (ADR), `cron_run_ledger` jitter-guard, Sentry heartbeat at end-of-`step.run`, `actor: "platform"` event-payload invariant, delete-GHA-YAML-same-commit hygiene.
- **G3.** Reshape #3948 into umbrella with 11 child issues (10 recurring migrations + 1 one-shot conversion).
- **G4.** Remove 2 already-fired one-shot workflows (`scheduled-dogfood-once-3049{,-v2}`) outright.
- **G5.** Convert `scheduled-gdpr-gate-preflight-eval-50d` (never fired, due June 29) to an `inngest.send`-triggered Inngest function preserving its one-shot UX.
- **G6.** Land BEFORE PR-G (#3947) so the SRE substrate is consolidated before founder cohort exposure (`SOLEUR_FR5_ENABLED=true`).

## Non-Goals

- Migrating group-(a) CI infrastructure workflows (~18 workflows) — STAYS on GH Actions, never in scope.
- Migrating group-(b) content production workflows (~8 workflows) — STAYS on GH Actions, explicitly out of TR9 scope.
- Founder-BYOK consumption from any platform-loop cron — these workflows execute as `actor: "platform"` using the operator `ANTHROPIC_API_KEY` only.
- Migrating to Inngest Cloud — self-hosted Hetzner is locked per PR-F K12; re-evaluation criteria documented in ADR-030.
- Bundling multiple workflows into one PR — per-workflow shape preserved per PR-F K14 + this brainstorm K8.
- Rotating `ANTHROPIC_API_KEY` at migration — K16; same trust boundary, defense-in-depth optional.
- Cohort exposure decisions — those gate on PR-G #3947, not on TR9.

## Functional Requirements

**[Revised post plan-review 2026-05-18]** FR1, FR2, FR7, TR4, TR8 (the `cron_run_ledger` ledger primitive) are RETRACTED. The 5-agent plan-review panel (DHH, Kieran, Code Simplicity, Architecture Strategist, Spec Flow) converged that Inngest's native cron-trigger + `step.run` memoization is the load-bearing primitive; the ledger duplicated it at lower fidelity AND would have blocked legitimate operator manual-retry for 24 h AND its plpgsql cast chain would have thrown at runtime. FR3 is amended to inline the prompt as a TS template literal (esbuild bundling excludes `.md` assets, so `readFileSync(PROMPT_PATH)` would have thrown on first fire). FR8 is amended to KEEP the existing Sentry slug `scheduled-daily-triage` (continuity preserved across the GHA → Inngest migration; the resource id, `name`, and slug are unchanged — only `checkin_margin_minutes` is tightened from 240 to 30). TR2 is amended to install the binary via `apps/web-platform/package.json` dependency on `@anthropic-ai/claude-code` instead of Hetzner cloud-init — the existing deploy pipeline runs `npm install` on the worker. The CLI form is `claude --print --model claude-sonnet-4-6 --max-turns 80 --allowedTools <...> "<prompt>"` (the npm package installs the binary as `claude`, NOT `claude-code` — that's only the npm-registry package name; prompt is positional). See `knowledge-base/project/plans/2026-05-18-feat-pr-1-migrate-scheduled-daily-triage-to-inngest-cron-tr9-plan.md` §Research Reconciliation and §v1 → v2 changes for the full rationale.

### PR-1 (proof-of-pattern: `scheduled-daily-triage`)

- **FR1.** New file `apps/web-platform/server/inngest/functions/cron-daily-triage.ts` exports an Inngest function registered via `inngest.createFunction({id: "cron-daily-triage"}, {cron: "0 4 * * *"}, handler)`. Schedule matches the deleted GHA YAML.
- **FR2.** Function step 1 is `step.run('jitter-guard', ...)` reading `cron_run_ledger(function_name='cron-daily-triage')`. Early-returns if last_run_at within 80% of the cron interval (24h × 0.8 = 19.2h). UPSERTs ledger row on each non-early-return execution.
- **FR3.** Function step 2 is `step.run('claude-eval', ...)` invoking `child_process.spawn('claude-code', [...])` with the existing daily-triage agent prompt. Stdout/exit-code captured deterministically for step.run memoization. AbortSignal aborts at 55 min (preserves rollback headroom vs old 60-min GHA timeout).
- **FR4.** Function step 3 is `step.run('sentry-heartbeat', ...)` POSTing to Sentry Crons monitor (single end-of-job POST, `if: always()`-equivalent — runs regardless of prior step failure mode). NO two-step in_progress→ok shape per `2026-05-18-vendor-cron-heartbeat-silent-fail-pattern.md`.
- **FR5.** Event payload (if function emits internal events) carries `actor: "platform"` tag. No `founderId`, no per-founder context.
- **FR6.** Inverse-assertion test in `apps/web-platform/test/server/byok-audit-writer-sweep.test.ts`: files matching `server/inngest/functions/cron-*.ts` MUST NOT import `runWithByokLease`. Sentinel covers both the existing per-founder write-site invariant AND the new platform-only invariant.
- **FR7.** New Supabase migration `apps/web-platform/supabase/migrations/0NN_cron_run_ledger.sql` creates the `cron_run_ledger(function_name TEXT PRIMARY KEY, last_run_at TIMESTAMPTZ NOT NULL, run_count BIGINT NOT NULL DEFAULT 1)` table. RLS: service-role only (no founder access). Dev/prd-distinct projects per `hr-dev-prd-distinct-supabase-projects`.
- **FR8.** Sentry monitor IaC entry in `apps/web-platform/infra/sentry/cron-monitors.tf` for `cron-daily-triage` with `schedule.crontab = "0 4 * * *"` and `checkin_margin_minutes = 30`.
- **FR9.** Delete `.github/workflows/scheduled-daily-triage.yml` in the same commit `cron-daily-triage.ts` lands. Rollback = revert.
- **FR10.** Integration test fires the function twice in succession; second invocation MUST be jitter-guarded (no `claude-code` spawn in second run).
- **FR11.** ADR via `/soleur:architecture create "Inngest cron functions invoke claude-code via child_process.spawn"`. Lands as `status: proposed` in PR-1; flipped `status: accepted` on merge. Documents rejected alternatives (SDK-direct rewrite, no spawn primitive) and invariants (operator key only, no founder context, replay-memoized via step.run).

### PR-cleanup (one-shot removals)

- **FR12.** Delete `.github/workflows/scheduled-dogfood-once-3049.yml` (fired 2026-05-04 failure; issue #3049 CLOSED).
- **FR13.** Delete `.github/workflows/scheduled-dogfood-once-3049-v2.yml` (fired 2026-05-04 success; issue #3049 CLOSED).
- **FR14.** Convert `scheduled-gdpr-gate-preflight-eval-50d.yml` → `apps/web-platform/server/inngest/functions/event-gdpr-gate-preflight-eval-50d.ts` triggered by `inngest.send({name: "preflight.gdpr-gate-50d-eval"})`. Preserves one-shot semantics (no cron; fires manually or via scripted dispatch). DELETE the GHA YAML in same commit.

### Umbrella reshape

- **FR15.** Update #3948 body to list 11 children as checkboxed items (10 recurring migrations + 1 one-shot conversion FR14). Close criterion: all 11 children merged AND corresponding GHA YAML files deleted.
- **FR16.** File 10 child issues (one per remaining recurring workflow), each parented to #3948 with `Closes #3948-child-N` semantics. Body of each child names: workflow name, current schedule, side-effect class, CLO bucket (i)/(ii), Article 30 audit requirement if (ii).

## Technical Requirements

- **TR1.** PR-1 BLOCKED by ADR-merge. The `/soleur:architecture create` ADR must land before PR-1 code (or as the first commit in PR-1) so review can reason against an accepted invariant set.
- **TR2.** `claude-code` CLI installed on Hetzner Inngest worker host with pinned version. Verify cloud-init script in `apps/web-platform/infra/server.tf` (or addendum) before PR-1.
- **TR3.** Reuse PR-F's Inngest signature-verification + dev-mode-guards. Module-load throws if `INNGEST_SIGNING_KEY` / `INNGEST_EVENT_KEY` missing. `INNGEST_DEV=1` AND `NODE_ENV=production` simultaneously throws (PR-F K8).
- **TR4.** `cron_run_ledger` Supabase migration runs in same release as PR-1 (via `web-platform-release.yml` migrate job).
- **TR5.** Doppler `ANTHROPIC_API_KEY` in both `dev` and `prd` (already shipped by PR-F runtime). GH org secret stays in place until ALL 11 umbrella children merge — removal is the last umbrella step, NOT per-workflow.
- **TR6.** Sentry Cron monitor cadence MUST match actual Inngest fire interval (NOT GHA's degraded effective interval). Adjust `checkin_margin_minutes` ≥ 30 to absorb daytime jitter.
- **TR7.** Sentinel sweep regex (`byok-audit-writer-sweep.test.ts`) extended with inverse assertion. The regex previously checked `runWithByokLease(` literal presence; extension adds: for any file matching `server/inngest/functions/cron-*.ts`, MUST NOT match the import-or-call pattern. Negative-case fixture confirms a refactored wrapper (`withByokSession`) is caught.
- **TR8.** `cq-pg-security-definer-search-path-pin-pg-temp` applies to any plpgsql function in the `cron_run_ledger` migration (UPSERT helper, if needed).
- **TR9.** preflight Check 6 fires on `apps/web-platform/server/inngest/functions/cron-*.ts`, `apps/web-platform/test/server/byok-audit-writer-sweep.test.ts`, `apps/web-platform/infra/inngest.tf`, `apps/web-platform/infra/sentry/cron-monitors.tf`, `apps/web-platform/supabase/migrations/0NN_cron_run_ledger.sql`. User-impact threshold `single-user incident` carries from parent epic.
- **TR10.** `/soleur:gdpr-gate` invoked at plan Phase 2.7 for any bucket (ii) workflow migration (NOT applicable to PR-1; daily-triage operates on operator's own repo backlog).

## Acceptance Criteria (PR-1)

- [ ] ADR `/soleur:architecture create` document landed `status: accepted` for claude-code spawn pattern.
- [ ] `cron-daily-triage.ts` registered and visible in Inngest dev dashboard.
- [ ] Inngest function fires on schedule `0 4 * * *` and applies labels + comments equivalent to deleted GHA workflow.
- [ ] `cron_run_ledger` table exists in dev + prd; jitter-guard early-return verified via integration test.
- [ ] Sentry monitor for `cron-daily-triage` shows successful check-in within 24h of merge.
- [ ] Inverse-sentinel test passes; refactored-wrapper negative case fails as expected.
- [ ] `.github/workflows/scheduled-daily-triage.yml` is DELETED in the merge commit. Rollback path = revert.
- [ ] `user-impact-reviewer` sign-off recorded in PR description.
- [ ] No new sub-processor disclosure. Article 30 register unchanged for PR-1 (daily-triage = bucket (i) per CLO assessment).

## Domain Review (carry-forward)

| Domain | Status | Key Concern |
|--------|--------|-------------|
| CPO | ✓ signed off | Ship before PR-G. Umbrella reshape with per-workflow children. |
| CLO | ✓ signed off | Self-hosted preserves sub-processor posture. Per-workflow Article 30 audit before bucket (ii) migrations (NOT PR-1). NO-OP `hr-autonomous-loop-skill-api-budget-disclosure` for platform-loop crons; guard ADR records re-evaluation criteria. |
| CTO | ✓ signed off | Substrate gap = `claude-code` spawn-child primitive (K9). Idempotency archetype = label-mutator natural key (set-union via GitHub API). Hobby tier execution budget 15× headroom; concurrency cap sidestepped by self-hosted. Inverse-assertion in sentinel sweep. |
