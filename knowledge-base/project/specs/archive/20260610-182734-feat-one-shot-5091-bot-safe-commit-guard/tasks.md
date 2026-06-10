# Tasks — fix: deterministic safe-commit guard for soleur-ai bot PR pipelines (#5091)

Plan: `knowledge-base/project/plans/2026-06-10-fix-bot-cron-safe-commit-guard-plan.md`
Lane: cross-domain (fail-closed default; no spec.md)

## Phase 0 — Substrate spike (decision gate, timebox ~1h)

- [x] 0.1 Replicate `setupEphemeralWorkspace` locally minus rm+symlink: fresh `git clone --depth=1` of this repo, write `.claude/settings.json` overlay + `cron-allow.txt`
- [x] 0.2 Probe `claude --print --plugin-dir plugins/soleur -- "Run /soleur:help"` against the clone's own tracked tree; record skill-resolution result
- [x] 0.3 Probe `--plugin-dir <absolute host plugin path>` variant; record result
- [x] 0.4 Decision: Outcome A (either works → remove rm+symlink from substrate in Phase 2.0; exclusion = `.claude/` only; no symlink-shadow issue) or Outcome B (keep symlink; exclusion = `.claude/` + `plugins/soleur/` prefixes; file symlink-shadow issue in Phase 6). Record outcome + evidence for the PR body.

## Phase 1 — Helper + unit tests (RED → GREEN, contract first)

- [x] 1.1 RED: create `apps/web-platform/test/server/inngest/cron-safe-commit.test.ts` with scratch git fixture repo (~15 tracked files); failing tests for AC4 (a)-(g)
- [x] 1.2 GREEN: create `apps/web-platform/server/inngest/functions/_cron-safe-commit.ts` — `safeCommitAndPr()` per plan algorithm (steps 1-12), 3-variant `SafeCommitResult`, `DEFAULT_MAX_DELETIONS = 10`, non-throwing, relative `./_cron-shared` imports
- [x] 1.3 Extract auto-merge GraphQL mutation from `cron-bug-fixer.ts:441-481` into the helper module; add clean-status → direct-merge fallback; re-point bug-fixer's import (no behavior change; bug-fixer test stays green)
- [x] 1.4 Verify: `./node_modules/.bin/vitest run test/server/inngest/cron-safe-commit.test.ts` green

## Phase 2 — Migrate the 3 blanket-add crons

- [x] 2.0 (Outcome A only) Remove rm+symlink from `_cron-claude-eval-substrate.ts` setupEphemeralWorkspace; keep manifest sentinel against the resolved plugin dir
- [x] 2.1 `cron-seo-aeo-audit.ts`: remove MANDATORY FINAL STEP block + scrub header comments referencing it; add PERSISTENCE anchor paragraph; wire `safe-commit-pr` step.run gated on `heartbeatOk && !spawnResult.abortedByTimeout`; allowedPaths `["plugins/soleur/docs/"]` (Outcome-B dead-config comment if applicable); verify `run-started-at` is memoized
- [x] 2.2 `cron-seo-aeo-audit.test.ts`: replace anchors (sentinels: `Do NOT run git add`, `opens a PR for your changes` — verify against as-written literal); assert gating + safeCommitAndPr call
- [x] 2.3 `cron-content-generator.ts` + test: same (allowedPaths `["knowledge-base/marketing/", "plugins/soleur/docs/blog/"]`)
- [x] 2.4 `cron-growth-execution.ts` + test: same (allowedPaths `["knowledge-base/marketing/", "plugins/soleur/docs/"]`)
- [x] 2.5 Read `cron-producer-output-wiring.test.ts`; extend only if it asserts prompt commit blocks

## Phase 3 — Hook hardening (live-path P1 fix)

- [x] 3.1 `cron-bash-allowlist-hook.mjs` gitVerbReason: flag-position-independent deny for `git add` -A/--all/-u/--update (incl. clustered -fA/-vA), `.`/`./`/`:/` pathspec, literal `*`, pathspec under `plugins/soleur` or `.claude`; `git commit` -a/--all/-am; instructive deny reasons with retry guidance. No `git add -A` literal in comments.
- [x] 3.2 `cron-bash-allowlist-hook.test.ts`: flip :46 to deny; full deny/allow matrix per AC6
- [x] 3.3 `cron-roadmap-review.ts` prompt: add "stage only the specific files you edited — never `git add -A`, `-u`, or `.`"; update `cron-roadmap-review.test.ts` anchor

## Phase 4 — fix-issue skill

- [x] 4.1 `plugins/soleur/skills/fix-issue/SKILL.md:160`: `git add -A` → scoped add of enumerated changed files from the fix phase (fix file + test file)

## Phase 5 — Parity test + full gates

- [x] 5.1 Create `cron-safe-commit-parity.test.ts`: (1) literal scan (no `git add -A|--all|-u` in any `^(cron|event)-.*\.ts$` + hook .mjs, comments included); (2) explicit migrated list (3 crons import+call safeCommitAndPr + anchor present; minimum-bound assertion); (3) Tier-2 constraint: migrated crons' CRON_BASH_ALLOWLISTS entries (if present) contain no git add/commit/push/gh pr prefixes; (4) 10-entry exempt list with rationale comments
- [x] 5.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean
- [x] 5.3 `./node_modules/.bin/vitest run test/server/inngest/ test/server/cron-substrate-imports.test.ts test/server/cron-no-byok-lease-sweep.test.ts` green
- [x] 5.4 AC1/AC2 greps return stated counts (baseline AC1: 4 hits → 0)

## Phase 6 — Follow-up issues + PR body

- [x] 6.1 (filed #5111) Verify labels exist (`gh label list`); create consolidation-migration issue (4 scoped prompt crons [growth-audit path verbatim `knowledge-base/marketing/audits/soleur-ai/`] + 5 legacy spawnGitChecked pipelines + stale-ci/*-PR watchdog decision line + deferred ADR)
- [x] 6.2 N/A — Outcome A confirmed (symlink removed; defect dissolved, no issue needed)
- [x] 6.3 PR body per AC9: Closes #5091; Phase 0 outcome + evidence; AC2 reinterpretation + N=10-vs-50 divergence; Tier-2 sequencing note → parity test; AC3 renegotiation (2026-06-15 run is a deferral no-op); follow-up links; mass-modification non-goal
