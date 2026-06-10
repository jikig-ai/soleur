---
title: "chore(inngest): consolidate remaining 9 bot commit pipelines onto safeCommitAndPr"
date: 2026-06-10
type: chore
lane: cross-domain
closes: "#5111"
brand_survival_threshold: aggregate pattern
---

# chore(inngest): consolidate remaining 9 bot commit pipelines onto safeCommitAndPr (#5111)

> Spec lacks valid `lane:` — defaulted to `cross-domain` (TR2 fail-closed; no spec.md exists for this branch).
> Pipeline mode: planning subagent has no Task tool — research ran inline (file-level verification of all 10 pipeline sources, parity test, ruleset IaC, live PR history); plan review performed as an inline three-lens pass (see `## Plan Review Synthesis`).

## Overview

PR #5098 (issue #5091) introduced `safeCommitAndPr()` (`apps/web-platform/server/inngest/functions/_cron-safe-commit.ts`) — a deterministic, non-throwing, replay-idempotent handler-side commit/PR pipeline with scoped staging, a clean-index precondition, structural exclusion, a loud dropped-path warn, and a mass-deletion guard (the #5026 destructive class) — and migrated the 3 blanket-`git add -A` crons. Nine bot pipelines still carry their own persistence:

- **4 prompt-level scoped-add crons (Tier-2 dormant, never spawn today):** `cron-campaign-calendar`, `cron-growth-audit`, `cron-community-monitor`, `cron-competitive-analysis`. Their prompts still instruct the spawned model to run `git add <paths> … gh pr merge --squash --auto`.
- **5 legacy handler-side `spawnGitChecked` pipelines (live, pure TS — no claude spawn):** `cron-weekly-analytics`, `cron-compound-promote`, `cron-content-publisher`, `cron-content-vendor-drift`, `cron-rule-prune`. Each carries a private copy of `spawnGit`/`spawnGitChecked` + octokit PR creation; all five post synthetic check-runs; four direct-merge, compound-promote opens draft PRs for human review.

This PR migrates **all 9 in one batch** (operator-confirmed scope), shrinks the parity-test EXEMPT list to the 2 permanent exemptions, authors the ADR deferred from #5091 ("deterministic handler-side commit pipeline as THE write path for bot cron PRs" — the claim only becomes true when the EXEMPT list empties, which this PR accomplishes), and decides the stale-`ci/*`-PR watchdog question (decision: **defer with a tracking issue gated on Tier-2 restoration** — rationale in Phase 6).

Refs: #5091 (helper, merged via #5098), #5026 (destructive-PR incident), #5018 (Tier-2 deferral), #5046 (PR-2 partial restoration). Closes #5111.

## Premise Validation

Issue #5111 is OPEN (verified `gh issue view 5111` 2026-06-10; labels `type/chore`, `domain/engineering`, `priority/p3-low`, milestone `Post-MVP / Later`). `safeCommitAndPr` exists at the cited path; parity test `apps/web-platform/test/server/inngest/cron-safe-commit-parity.test.ts` carries `MIGRATED` = [seo-aeo-audit, content-generator, growth-execution] and `EXEMPT` = the 9 targets + roadmap-review + bug-fixer, exactly as the issue claims. `TIER2_DEFERRED_CRONS` (`_cron-shared.ts:244-254`) still contains all 4 prompt-level targets (plus seo-aeo-audit, content-generator, growth-execution, bug-fixer, ux-audit) — Tier-2 restoration has NOT happened. No stale premises found. One **issue-body drift** found the other direction: a code comment at `cron-seo-aeo-audit.ts:279-281` says a tri-state verify gate "is tracked in the #5111 consolidation", but #5111's checklist does not contain it — handled in Phase 6.

## Research Reconciliation — Spec vs. Codebase

| Issue/spec claim | Reality (verified at file level, 2026-06-10) | Plan response |
|---|---|---|
| Only `cron-weekly-analytics` "uses synthetic check-runs + direct merge" | **All 5** legacy pipelines post `SYNTHETIC_CHECK_NAMES` check-runs (weekly-analytics:293, compound-promote:625, content-publisher:389, content-vendor-drift:618, rule-prune:346). Four direct-merge via `PUT /pulls/{n}/merge`; compound-promote posts checks but **never merges** (draft PR, "human review required", label `self-healing/auto`). | Fold BOTH behaviors into the helper as orthogonal options: `syntheticChecks?` + `mergeMode: "auto" \| "direct" \| "none"` (Phase 1). Default `"auto"` preserves the 3 already-migrated crons and serves the 4 prompt crons. |
| competitive-analysis allowedPaths = `competitive-intelligence.md` "+ cascade artifacts — audit the agent's actual write set first" | Audit done: `plugins/soleur/agents/product/competitive-intelligence.md` Phase 2 cascade table writes 4 additional artifacts: `knowledge-base/marketing/content-strategy.md`, `knowledge-base/product/pricing-strategy.md`, `knowledge-base/sales/battlecards/`, `knowledge-base/marketing/seo-refresh-queue.md`. Today's prompt commits ONLY `competitive-intelligence.md` — cascade outputs are silently discarded every run. | allowedPaths = all 5 paths (Phase 2). Deliberate improvement: prevents a guaranteed `safe-commit-paths-dropped` Sentry warn every cascade run AND stops discarding intended outputs. Documented in PR body as a behavior change. |
| "remove the prompt MANDATORY FINAL STEP block" for all 4 | community-monitor's commit block is instruction "5. **Persist via PR**" (`cron-community-monitor.ts:185-203`), NOT a `MANDATORY FINAL STEP` heading — but its preamble line 137 references "the MANDATORY FINAL STEP". | Remove BOTH the numbered persist instruction AND the preamble reference; renumber instruction 6 (Phase 2). Parity invariant 2's `not.toContain("MANDATORY FINAL STEP")` then passes mechanically. |
| "move all 9 to MIGRATED" | Parity invariant 2 asserts prompt anchors (`PERSISTENCE: Do NOT run git add`) and the `heartbeatOk && !spawnResult.abortedByTimeout` gate regex — assertions that **cannot hold** for the 5 pure-TS legacy crons (no prompt, no `spawnClaudeEval`, no `heartbeatOk`). | Split into two cohorts: `MIGRATED_PROMPT` (7) keeps full invariant-2 assertions; `MIGRATED_HANDLER` (5) asserts import + call + no `spawnGitChecked` staging only. Invariants 1, 3, 4 run over the union (Phase 4). |
| compound-promote is a like-for-like migration | Largest shape divergence: per-cluster branches `self-healing/auto-<hash>-<date>` (not `ci/<name>-<ts>`), commit trailers (`-m title -m trailer`), draft PR, custom body, label, NO merge, multiple PRs per run. | Helper gains `branchName?`, `commitBody?`, `prTitle?`, `prBody?`, `prDraft?`, `prLabels?` overrides (Phase 1); compound-promote calls the helper once per cluster inside its existing per-cluster step (Phase 3). |
| content-publisher add path | `CONTENT_DIR_REL = "knowledge-base/marketing/distribution-content"` — **no trailing slash**. The helper's allowlist matching is bare `startsWith` and its contract requires directory entries to end with `/`. | allowedPaths = `["knowledge-base/marketing/distribution-content/"]` (trailing slash added). |
| tri-state verify gate "tracked in #5111" (code comment) | `cron-seo-aeo-audit.ts:279-281` cites #5111 for the `resolveOutputAwareOk` exit-code-fallback caveat; #5111 does not track it; this PR closes #5111. | File a tracking issue for the tri-state gate; update the stale comment in the 3 already-migrated crons to cite the new issue number (Phase 6). |
| Merge mechanics context | Live evidence: legacy direct-merge works in production (`ci/content-publisher-2026-05-19-164226` merged +54 s after creation); prompt-level `gh pr merge --auto` also works (`ci/community-digest-*` merged daily through 2026-06-08, `ci/campaign-calendar-2026-05-25` merged). Required checks in `infra/github/ruleset-ci-required.tf` are integration-pinned to GitHub Actions (15368), yet Soleur-app synthetic checks + direct merge demonstrably succeed. | **Preserve each cron's current production-proven merge mechanics exactly** — this batch PR changes the staging/guard layer only, never merge semantics. Unification onto auto-merge is listed as a rejected alternative, revisitable at Tier-2 restoration. |

## User-Brand Impact

- **If this lands broken, the user experiences:** a bot cron's weekly/daily PR fails to appear (run work discarded or PR withheld), or a bot PR lands with a truncated file set. Every failure mode is loud by construction: `safeCommitAndPr` mirrors each failed stage to Sentry (`safe-commit-failed`, `safe-commit-deletion-guard`, `safe-commit-paths-dropped`) and comments "PR withheld: …" on the cron's scheduled issue. CI's 8 required checks remain the backstop on anything that does merge.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no new exposure surface — same installation-token scope, same spawn-env allowlists, same public-repo write targets as today. The helper *narrows* what bot runs can commit (allowlist + deletion guard) versus the legacy copies.
- **Brand-survival threshold:** aggregate pattern — a single broken bot PR is caught by required checks (proven by #5026 itself); brand cost accrues only if the pipeline degrades persistently across runs. Same classification and rationale as the #5091 plan (`2026-06-10-fix-bot-cron-safe-commit-guard-plan.md`, threshold `aggregate pattern`).

## Implementation Phases

### Phase 1 — Extend `safeCommitAndPr` option surface (tests first)

**File:** `apps/web-platform/server/inngest/functions/_cron-safe-commit.ts` + `apps/web-platform/test/server/inngest/cron-safe-commit.test.ts`

Widen `SafeCommitConfig` with optional, default-preserving fields (all existing callers compile unchanged — verify per `hr-type-widening-cross-consumer-grep` with `git grep -n "safeCommitAndPr({" apps/web-platform/`):

```ts
export interface SafeCommitConfig {
  // ...existing fields unchanged...
  /** Override the derived `ci/<name>-<ts>` branch (compound-promote's
   *  per-cluster `self-healing/auto-<hash>-<date>`). Must be refname-safe;
   *  the helper asserts no `:` `.` ` ` and fails stage "checkout" otherwise. */
  branchName?: string;
  /** Second `-m` paragraph (compound-promote provenance trailers). */
  commitBody?: string;
  /** Full PR title override (no date appended). Default stays
   *  `${commitMessage} ${YYYY-MM-DD}`. */
  prTitle?: string;
  /** PR body stem override. The dropped-path ⚠️ marker is appended
   *  regardless of override (the loud-truncation invariant survives). */
  prBody?: string;
  prDraft?: boolean;
  /** Labels applied after PR create (best-effort: label failure mirrors to
   *  Sentry, never fails the run — labels are advisory metadata). */
  prLabels?: readonly string[];
  /** Post synthetic check-runs on the head SHA after PR create (the
   *  bot-pr-with-synthetic-checks pattern carried by all 5 legacy crons). */
  syntheticChecks?: { names: readonly string[]; summary: string };
  /** "auto" (default): enablePullRequestAutoMerge + clean-status direct
   *  fallback — current behavior. "direct": PUT /pulls/{n}/merge squash
   *  immediately (legacy live pipelines); on failure falls back to arming
   *  auto-merge, then to failure stage "auto-merge" (preserves
   *  content-publisher's documented intent at cron-content-publisher.ts:416-419
   *  and keeps the PR open + loud). "none": create only (compound-promote
   *  human-review draft PRs). */
  mergeMode?: "auto" | "direct" | "none";
}
```

Implementation notes:

- `deriveBranchName` call site becomes `config.branchName ?? deriveBranchName(cronName, runStartedAt)`. The replay-resume check (`HEAD === branch && ahead > 0`) uses the resolved name — per-cluster replay-resume keeps working because compound-promote's per-cluster step memoization replays the whole cluster step.
- Commit becomes `["commit", "-m", commitMessage, ...(commitBody ? ["-m", commitBody] : [])]`.
- `syntheticChecks`: resolve head SHA via existing `runGit(spawnCwd, ["rev-parse", "HEAD"])`; `POST /repos/{owner}/{repo}/check-runs` per name with `status: "completed"`, `conclusion: "success"`, `output: { title: "Bot PR", summary }`. A check-run POST failure is mirrored via `reportSilentFallback` and does NOT abort (merge failure is the loud terminal signal — matches today's behavior where merge `.catch` is the only net).
- `mergeMode === "none"` returns `committed` immediately after PR create (+ labels/checks).
- `mergeMode === "direct"`: try `PUT …/merge` (squash); on failure, try `enableAutoMergeSquash`; if that also fails, existing `failure(config, "auto-merge", …)` path (PR stays open; Sentry + scheduled-issue comment; for legacy crons with no labeled open issue the comment is a silent no-op by `commentOnScheduledIssue`'s existing design — Sentry still fires). Do NOT widen the `stage` union — reuse `"auto-merge"` for all merge-tail failures (runbook row already describes it as "PR EXISTS but needs a manual merge").
- **Tests first** (`cron-safe-commit.test.ts`, scratch-git-repo fixture pattern already in the file): branchName override honored + refname-rejection; commitBody lands as second paragraph (`git log -1 --format=%B`); prTitle/prBody/prDraft/prLabels pass through to mocked octokit; syntheticChecks POSTs one check-run per name on the head SHA; mergeMode "direct" happy path, direct-fail→auto-merge-arm fallback, both-fail→`failed/auto-merge`; mergeMode "none" never calls merge endpoints; defaults unchanged (existing tests stay green untouched — regression net).

### Phase 2 — Migrate the 4 prompt-level crons (Tier-2 dormant)

**Files:** `cron-campaign-calendar.ts`, `cron-growth-audit.ts`, `cron-community-monitor.ts`, `cron-competitive-analysis.ts` (+ their 4 test files)

Each follows the canonical migrated shape (`cron-seo-aeo-audit.ts:274-298` verbatim pattern):

1. **Prompt edit:** delete the commit block (campaign-calendar:100-110, growth-audit:101-111, community-monitor instruction 5 at :185-203, competitive-analysis:136-153 incl. the escaped fenced block) AND every preamble reference to "the MANDATORY FINAL STEP" / "PR-based commit pattern" (campaign-calendar:74, growth-audit:76, community-monitor:137, competitive-analysis:127). Replace with the platform-persistence directive, adapted per cron:

   ```text
   PERSISTENCE: Do NOT run git add, git commit, git push, or gh pr create/merge.
   The platform commits and opens a PR for your changes automatically after the run.
   Only changes under <enumerated allowedPaths> are persisted — keep all edits inside those paths.
   Creating the <scheduled issue> above is REQUIRED: the platform only persists your changes after it verifies the issue exists.
   ```

   (community-monitor: renumber instruction 6 → 5 or keep numbering with a removed-step note — prefer renumbering for cleanliness; its DEDUP RULE and CLONE DEPTH RULE blocks are untouched.)

2. **allowedPaths consts** (verbatim from current prompts; competitive-analysis from the write-set audit):
   - `CAMPAIGN_CALENDAR_ALLOWED_PATHS = ["knowledge-base/marketing/campaign-calendar.md", "knowledge-base/marketing/content-strategy.md"]`
   - `GROWTH_AUDIT_ALLOWED_PATHS = ["knowledge-base/marketing/audits/soleur-ai/", "knowledge-base/product/roadmap.md"]`
   - `COMMUNITY_MONITOR_ALLOWED_PATHS = ["knowledge-base/support/community/"]`
   - `COMPETITIVE_ANALYSIS_ALLOWED_PATHS = ["knowledge-base/product/competitive-intelligence.md", "knowledge-base/marketing/content-strategy.md", "knowledge-base/product/pricing-strategy.md", "knowledge-base/sales/battlecards/", "knowledge-base/marketing/seo-refresh-queue.md"]` — with a comment citing the cascade table at `plugins/soleur/agents/product/competitive-intelligence.md` ("Cascade Delegation Table") and noting the CASCADE LIMIT-4 comment there: widening the cascade requires widening this list.

3. **Wire step 4.5** between `verify-output` and `sentry-heartbeat`, gated exactly as the parity regex requires:

   ```ts
   if (heartbeatOk && !spawnResult.abortedByTimeout) {
     await step.run("safe-commit-pr", async () =>
       safeCommitAndPr({
         spawnCwd: spawnCwd!,
         installationToken,
         cronName: "<cron-name>",
         commitMessage: "<current prompt's commit message, verbatim>",
         allowedPaths: <CONST>,
         runStartedAt,
         scheduledIssueLabel: SENTRY_MONITOR_SLUG,
         logger,
       }),
     );
   }
   ```

   Commit messages preserved verbatim: campaign-calendar `"ci: update campaign calendar and content-strategy review"`; growth-audit `"docs: weekly growth audit"`; community-monitor `"docs: daily community digest"`; competitive-analysis `"docs: update competitive intelligence report"`. Default `mergeMode "auto"` matches the prompts' current `gh pr merge --squash --auto`. PR titles default to `${commitMessage} ${date}` — matches the prompts' current `gh pr create --title` shapes (campaign-calendar's drops the "ci: update campaign calendar" vs commit-message wording difference; acceptable cosmetic drift, note in PR body).

4. **Anchor tests:** update the 4 test files. competitive-analysis's test explicitly preserves the MANDATORY FINAL STEP block verbatim (file comments say so) — replace those anchors with: `PERSISTENCE: Do NOT run git add` anchor, absence of `MANDATORY FINAL STEP`, absence of `git add` literals in the prompt, presence of the gated `safe-commit-pr` step (mirror `cron-seo-aeo-audit.test.ts:93` pattern). Same treatment for the other 3.

### Phase 3 — Migrate the 5 legacy handler-side pipelines (live)

**Files:** `cron-weekly-analytics.ts`, `cron-compound-promote.ts`, `cron-content-publisher.ts`, `cron-content-vendor-drift.ts`, `cron-rule-prune.ts` (+ their 6 test files incl. `cron-compound-promote-graymatter.test.ts` if it touches the pipeline — verify at work time)

Behavior-preserving per cron; each deletes its private `spawnGitChecked` staging/commit/push/PR/check-run/merge copy and keeps non-persistence logic (clone, scripts, cascade dispatch, Discord notify, labels detection, cluster guards) untouched:

| Cron | safeCommitAndPr call (inside the existing step.run) | Preserved semantics |
|---|---|---|
| weekly-analytics | `allowedPaths: ["knowledge-base/marketing/analytics/"]`, `commitMessage: "ci: weekly analytics snapshot"`, `syntheticChecks: { names: SYNTHETIC_CHECK_NAMES, summary: "Analytics snapshot only, no code changes" }`, `mergeMode: "direct"` | PLAUSIBLE env gate, KPI cascade dispatch, Discord notify, `ci/weekly-analytics-<ts>` branch (helper derivation matches), `prBody: "Automated weekly analytics snapshot from Plausible API."` |
| content-publisher | `allowedPaths: ["knowledge-base/marketing/distribution-content/"]` (trailing slash added), `commitMessage: "ci: update content distribution status"`, `prBody: "Automated status update from content publisher workflow."`, `syntheticChecks: { names: SYNTHETIC_CHECK_NAMES, summary: "Status metadata only, no code changes" }`, `mergeMode: "direct"` | publish/posting steps untouched; PR title default = commitMessage+date matches current |
| content-vendor-drift | `allowedPaths: ["plugins/soleur/skills/gdpr-gate/NOTICE", "plugins/soleur/skills/gdpr-gate/references/"]` (derive from `SKILL_PREFIX`), `commitMessage: "chore(vendor-drift): re-vendor gosprinto/compliance-skills"`, `prBody:` current runbook-pointer body verbatim, `prLabels: detectResult.labels`, `syntheticChecks`, `mergeMode: "direct"` | classifier/NOTICE-bump logic untouched; branch cosmetic change `ci/vendor-drift-<ts>` → `ci/content-vendor-drift-<ts>` (note in PR body) |
| rule-prune | `allowedPaths: ["scripts/retired-rule-ids.txt"]`, `commitMessage: "chore(rule-prune): propose retirement of stale rules"`, `prTitle: \`${pruneResult.prTitle} ${date}\`` (preserve dynamic title), `prBody:` current body, `syntheticChecks`, `mergeMode: "direct"` | HR-allowlist/staleness logic untouched; branch cosmetic change `ci/rule-prune-retire-<date>` → `ci/rule-prune-<ts>` (note in PR body) |
| compound-promote | Per cluster: `branchName: \`self-healing/auto-${clusterHash}-${dateSuffix}\``, `allowedPaths: [cluster.target_path, "knowledge-base/project/learnings/promotion-log.md"]`, `commitMessage: titleLine`, `commitBody: trailer`, `prTitle: \`self-healing(auto): promote cluster ${clusterHash} ${dateSuffix}\``, `prBody:` current body (incl. "human review required"), `prDraft: true`, `prLabels: ["self-healing/auto"]`, `syntheticChecks: { names: SYNTHETIC_CHECK_NAMES, summary: "self-healing/auto promotion — operator review required" }`, `mergeMode: "none"` | all cluster guards (TARGET_ALLOW_RE, hr-rule-edit refusal, byte budget, skill-conflict comment, BRANCH_SHAPE_RE, applyDiffToWorkspace) stay caller-side; `git checkout main` after each cluster stays caller-side (one `runGit`-equivalent spawn retained or plain `spawnGit`) |

Notes:

- Delete each file's now-unused `spawnGitChecked` (and `spawnGitCapture` where only used for `rev-parse`); keep `spawnGit` where still needed for `clone` / `checkout main` / `checkout -- .` rollback.
- `SYNTHETIC_CHECK_NAMES` is exported per-file today (5 copies) — consolidate to ONE exported const. Placement: `_cron-safe-commit.ts` (alongside the consumer option). Update the 5 imports + any test imports (`git grep -n "SYNTHETIC_CHECK_NAMES" apps/web-platform/` at work time; keep the name list identical: test, dependency-review, e2e, skill-security-scan PR gate, enforce, cla-check, cla-evidence — note rule-prune/vendor-drift copies may have drifted; diff all 5 lists first and preserve any per-cron difference as a per-call override if found).
- Net gain for all 5: deletion guard, dirty-index precondition, dropped-path warn + PR-body ⚠️ marker, replay-resume idempotency, token-scrubbed failure messages, operator-visibility comments.
- **Deletion-guard interplay:** vendor-drift re-vendoring can legitimately delete >10 files under `references/` on a large upstream restructure → guard aborts loudly (Sentry + runbook's documented `DEFAULT_MAX_DELETIONS` raise-path). Accepted: that is the guard working as designed for a mass-deletion event; no per-cron override (YAGNI per #5091 plan review).
- **Tests:** update the 5 (6) test files: replace spawn-argv git assertions with mocked-`safeCommitAndPr` call-shape assertions (config object equality: allowedPaths/branchName/mergeMode/syntheticChecks/draft/labels) plus keep all non-persistence test coverage untouched. Mirror the mocking approach used by `cron-seo-aeo-audit.test.ts` (vi.mock of `./_cron-safe-commit`).

### Phase 4 — Parity test restructure

**File:** `apps/web-platform/test/server/inngest/cron-safe-commit-parity.test.ts`

- `MIGRATED` → two cohorts:
  - `MIGRATED_PROMPT = [cron-seo-aeo-audit, cron-content-generator, cron-growth-execution, cron-campaign-calendar, cron-growth-audit, cron-community-monitor, cron-competitive-analysis]` — full invariant-2 assertions (import, call, `PERSISTENCE: Do NOT run git add` anchor, `heartbeatOk && !spawnResult.abortedByTimeout` gate regex, no `MANDATORY FINAL STEP`).
  - `MIGRATED_HANDLER = [cron-weekly-analytics, cron-compound-promote, cron-content-publisher, cron-content-vendor-drift, cron-rule-prune]` — asserts import + `safeCommitAndPr({` call + NO `spawnGitChecked` staging literal + no blanket-add literal (invariant 1 already covers the latter). No prompt-anchor/gate assertions (pure TS, no claude spawn — documented in a cohort comment).
- `EXEMPT` shrinks to exactly: `cron-roadmap-review.ts` ("hook-guarded Tier-1 self-commit") + `cron-bug-fixer.ts` ("fix-issue skill owns the commit step (scoped add)").
- Invariant 3 (allowlist must not re-arm persistence verbs) iterates `[...MIGRATED_PROMPT, ...MIGRATED_HANDLER]`; the canary stays. (Currently trivially green — none of the 12 has a `CRON_BASH_ALLOWLISTS` entry except roadmap-review which is EXEMPT; the invariant is the Tier-2 restoration tripwire, which is the point of (C).)
- Invariant 4's classifier keeps detecting staging pathways; with the 5 copies deleted, only MIGRATED/EXEMPT files may match.
- The "EXEMPT files must not CALL safeCommitAndPr" disjointness check now covers just the 2 permanent exemptions.

### Phase 5 — ADR

**File to create:** `knowledge-base/engineering/architecture/decisions/ADR-054-safe-commit-and-pr-sole-write-path-for-bot-cron-prs.md` (next free number verified: `ls … | sort -V | tail -1` → ADR-053; follow `plugins/soleur/skills/architecture/SKILL.md` template and frontmatter).

Content contract: ADR-033 lineage (claude-spawn substrate invariants); context = #5026 destructive incident → #5091 helper + 3-cron migration → #5111 emptying the exemption list; decision = `safeCommitAndPr` is THE write path for bot cron PRs (prompt-side and handler-side persistence copies are forbidden); the three merge modes and when each applies (auto = claude-spawn output PRs; direct+synthetic = deterministic data-refresh PRs, production-proven mechanics; none+draft = human-review proposal PRs); the two permanent exemptions with rationale (roadmap-review: hook-guarded Tier-1 self-commit inside its finite bash allowlist; bug-fixer: fix-issue skill owns the commit step); enforcement = the self-discovering parity test (invariants 1-4); consequences incl. the Tier-2 restoration constraint (restored allowlists must not re-arm persistence verbs — invariant 3) and the deferred stale-`ci/*`-PR watchdog (link the tracking issue from Phase 6).

### Phase 6 — Decisions, tracking issues, doc hygiene

1. **Stale-`ci/*`-PR watchdog — DECISION: defer with a tracking issue.** Reasoning recorded here and in the ADR: auto-merge silent-disarm-on-conflict is the only invisible-stale mode, and after this PR every `mergeMode:"auto"` pipeline is Tier-2 dormant (the 4 prompt crons + the 3 #5091 migrations); the 5 live pipelines use `mergeMode:"direct"`, whose failure is loud (Sentry `safe-commit-failed` stage `auto-merge` + PR-needs-manual-merge comment). The marketing-file conflict scenario (campaign-calendar × growth crons sharing `knowledge-base/marketing/`) can only materialize once Tier-2 restoration un-defers those crons. Create issue: "chore(inngest): stale `ci/*` bot-PR watchdog — required before Tier-2 restoration of PR-flow crons" — body: extend the `cron-cloud-task-heartbeat` family with an open-bot-PR age scan (open PRs with head `ci/*` or `self-healing/auto-*` older than 48h, excluding draft compound-promote proposals → Sentry warn + issue comment), re-evaluation criterion = Tier-2 restoration PR for any of the 7 auto-merge-mode crons MUST land this first (refs #5018, #5046, this PR). Labels (all verified existing on #5111): `type/chore`, `domain/engineering`, `priority/p3-low`; milestone "Post-MVP / Later".
2. **Tri-state verify-gate tracking issue.** `resolveOutputAwareOk` falls back to the spawn exit code when its GitHub verify-read throws — persistence can then be gated on a fallback-green. File: "chore(inngest): tri-state output-verify gate for safe-commit persistence" (same labels/milestone); update the stale "#5111 consolidation" comment in `cron-seo-aeo-audit.ts:279-281` — and the equivalent comment in `cron-content-generator.ts` / `cron-growth-execution.ts` if present (`git grep -n "tri-state" apps/web-platform/server/` at work time) — to cite the new issue number.
3. **Runbook touch-up.** `knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md` §"PR Withheld by safe-commit (#5091)" (line ~666): note that ALL bot cron PR pipelines now route through the helper (12 callers), document the three merge modes and that stage `auto-merge` covers direct-merge failures too, and add the vendor-drift large-restructure deletion-guard expectation.

## Files to Edit

1. `apps/web-platform/server/inngest/functions/_cron-safe-commit.ts` — option surface (Phase 1) + consolidated `SYNTHETIC_CHECK_NAMES`
2. `apps/web-platform/server/inngest/functions/cron-campaign-calendar.ts` — Phase 2
3. `apps/web-platform/server/inngest/functions/cron-growth-audit.ts` — Phase 2
4. `apps/web-platform/server/inngest/functions/cron-community-monitor.ts` — Phase 2
5. `apps/web-platform/server/inngest/functions/cron-competitive-analysis.ts` — Phase 2
6. `apps/web-platform/server/inngest/functions/cron-weekly-analytics.ts` — Phase 3
7. `apps/web-platform/server/inngest/functions/cron-compound-promote.ts` — Phase 3
8. `apps/web-platform/server/inngest/functions/cron-content-publisher.ts` — Phase 3
9. `apps/web-platform/server/inngest/functions/cron-content-vendor-drift.ts` — Phase 3
10. `apps/web-platform/server/inngest/functions/cron-rule-prune.ts` — Phase 3
11. `apps/web-platform/server/inngest/functions/cron-seo-aeo-audit.ts` — Phase 6 comment cite fix (+ `cron-content-generator.ts`, `cron-growth-execution.ts` if same comment present)
12. `apps/web-platform/test/server/inngest/cron-safe-commit.test.ts` — Phase 1 tests
13. `apps/web-platform/test/server/inngest/cron-safe-commit-parity.test.ts` — Phase 4
14. `apps/web-platform/test/server/inngest/cron-campaign-calendar.test.ts` — Phase 2
15. `apps/web-platform/test/server/inngest/cron-growth-audit.test.ts` — Phase 2
16. `apps/web-platform/test/server/inngest/cron-community-monitor.test.ts` — Phase 2
17. `apps/web-platform/test/server/inngest/cron-competitive-analysis.test.ts` — Phase 2 (anchors currently preserve the MANDATORY FINAL STEP block verbatim)
18. `apps/web-platform/test/server/inngest/cron-weekly-analytics.test.ts` — Phase 3
19. `apps/web-platform/test/server/inngest/cron-compound-promote.test.ts` (+ `cron-compound-promote-graymatter.test.ts` if pipeline-coupled) — Phase 3
20. `apps/web-platform/test/server/inngest/cron-content-publisher.test.ts` — Phase 3
21. `apps/web-platform/test/server/inngest/cron-content-vendor-drift.test.ts` — Phase 3
22. `apps/web-platform/test/server/inngest/cron-rule-prune.test.ts` — Phase 3
23. `knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md` — Phase 6

## Files to Create

1. `knowledge-base/engineering/architecture/decisions/ADR-054-safe-commit-and-pr-sole-write-path-for-bot-cron-prs.md` — Phase 5
2. `knowledge-base/project/specs/feat-one-shot-5111-safe-commit-consolidation/tasks.md` — plan artifact

## Acceptance Criteria

### Pre-merge (PR)

1. `git grep -l "spawnGitChecked" apps/web-platform/server/inngest/functions/` returns empty (all five private staging pipelines deleted; plain `spawnGit` may remain for clone/checkout-main).
2. `git grep -c "MANDATORY FINAL STEP" apps/web-platform/server/inngest/functions/` returns no matches (prompt blocks and preamble references gone); test-file anchors updated accordingly — `git grep -l "MANDATORY FINAL STEP" apps/web-platform/test/` matches only `cron-safe-commit-parity.test.ts` (the negative-assertion literal) if at all.
3. Parity test: `EXEMPT` contains exactly 2 keys (`cron-roadmap-review.ts`, `cron-bug-fixer.ts`); cohort union covers all 12 migrated crons; `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-safe-commit-parity.test.ts` green.
4. Each of the 4 prompt crons matches the gate regex `if \(heartbeatOk && !spawnResult\.abortedByTimeout\) \{[\s\S]{0,800}?safeCommitAndPr\(\{` (enforced mechanically by invariant 2 for the `MIGRATED_PROMPT` cohort).
5. Helper option tests green: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-safe-commit.test.ts` — including: defaults-unchanged regression block, branchName/commitBody/prTitle/prDraft/prLabels pass-through, syntheticChecks check-run POSTs, mergeMode direct happy + fallback + both-fail, mergeMode none.
6. Full inngest suite green: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/`.
7. Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (NOT `npm run -w` — no root `workspaces` field).
8. `ls knowledge-base/engineering/architecture/decisions/ADR-054-*.md` returns the new ADR; ADR names both permanent exemptions, the three merge modes, the parity test as enforcement, and links #5026/#5091/#5111 + the watchdog tracking issue.
9. Two tracking issues exist (`gh issue list --search "stale ci bot-PR watchdog"` / `"tri-state output-verify"`) with labels `type/chore`,`domain/engineering`,`priority/p3-low` (verified existing) and milestone "Post-MVP / Later"; the tri-state comment in the 3 #5091-migrated crons cites the new issue number (no remaining `git grep -n "tracked in the #5111" apps/web-platform/server/` hits).
10. PR body: `Closes #5111`; documents the two cosmetic branch-name changes (vendor-drift, rule-prune), the campaign-calendar PR-title wording drift, and the competitive-analysis allowedPaths widening (cascade artifacts now persisted) as deliberate behavior changes.
11. `allowedPaths` directory entries all end with `/` and file entries are exact repo-root-relative paths (helper contract): mechanical eyeball + the parity/unit suites.

### Post-merge (operator → automated)

12. Live verification of the 5 migrated live pipelines without waiting for natural fires: trigger via `/soleur:trigger-cron` (allowlisted manual-trigger events) for `cron-rule-prune` (cheapest deterministic producer) and observe either a `ci/rule-prune-*` PR or a structured `safe-commit-no-changes` log; remaining live crons verified at next natural fire (weekly-analytics Mon 06:00 UTC; compound-promote Sun 00:00 UTC). Automation: executed in-session via the trigger-cron skill + `gh pr list --search "head:ci/" --state all --limit 5`; no dashboard-eyeball steps (deterministic verdict: PR exists OR `safe-commit-no-changes`/`no clusters` log line via the deploy-status webhook is NOT needed — Sentry op query `safe-commit-failed` empty for the window = pass).
13. The 4 prompt crons remain Tier-2 dormant — no live verification possible or required (deferral heartbeat is the expected behavior); first live exercise lands with Tier-2 restoration, which the parity invariant 3 + the watchdog tracking issue now gate.

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` (200-cap query, 2026-06-10) matched zero open issues against all planned file paths.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed (inline CTO-lens; pipeline mode — no Task tool available to spawn the domain-leader agent, recorded per Phase 2.5 partial-findings rule)
**Assessment:** Consolidation direction is architecturally correct and was pre-approved by the #5091 CTO advisory ("ADR deferred to the consolidation follow-up (where 'sole write path' becomes true)"). The single risk axis is coupling 5 live pipelines' behavior to one helper in one batch: mitigated by (a) behavior-preserving merge modes (no live cron changes merge mechanics), (b) the option surface being purely additive with a defaults-unchanged regression block, (c) scratch-git-repo unit fixtures per #5091's verification story, (d) post-merge manual-trigger verification of the cheapest live producer. The cohort split in the parity test preserves invariant strength where it applies instead of weakening assertions to fit all 12.

### Product/UX Gate

Not applicable — no UI surface in Files to Edit/Create (mechanical UI-surface override checked: zero matches against `components/**`, `app/**`, `.tsx`, pages/flows). Tier: NONE.

## GDPR / Compliance Gate

Skipped (silently per Phase 2.7 contract, recorded here for the deepen pass): no regulated-data surface (no schema/migration/auth/API-route/.sql files), no new processing activity (same crons, same data flows, same LLM endpoints), threshold is `aggregate pattern`, no new cron reading learnings/specs (compound-promote already reads learnings today; unchanged), no new artifact distribution surface.

## Infrastructure (IaC)

Not applicable — no new infrastructure: pure code change against the already-provisioned Inngest substrate (no new service, secret, vendor, or persistent process; `infra/github/ruleset-ci-required.tf` is read-only context, not edited).

## Observability

```yaml
liveness_signal:
  what: per-cron Sentry Crons check-ins (existing slugs scheduled-weekly-analytics, scheduled-compound-promote, scheduled-content-publisher, scheduled-content-vendor-drift, scheduled-rule-prune, plus the 4 dormant prompt-cron slugs posting deferral heartbeats)
  cadence: each cron's existing schedule (unchanged by this PR)
  alert_target: Sentry cron-monitor alerts (existing, IaC-managed per ADR-031)
  configured_in: apps/web-platform/infra/sentry (pre-existing; no changes)
error_reporting:
  destination: Sentry via reportSilentFallback ops safe-commit-failed / safe-commit-deletion-guard / safe-commit-paths-dropped / safe-commit-issue-comment-failed (all pre-existing in the helper; the 5 live crons GAIN these on migration)
  fail_loud: true — every failed stage also posts a "PR withheld" comment on the cron's labeled scheduled issue (best-effort, Sentry-mirrored on comment failure)
failure_modes:
  - mode: deletion guard aborts a legitimate large vendor re-vendor
    detection: Sentry op safe-commit-deletion-guard (fn=cron-content-vendor-drift) + PR-withheld comment
    alert_route: Sentry issue alert; runbook cloud-scheduled-tasks.md §"PR Withheld by safe-commit" documents the DEFAULT_MAX_DELETIONS raise path
  - mode: direct merge fails (required checks / conflict) on a live pipeline
    detection: Sentry op safe-commit-failed stage=auto-merge; PR left open
    alert_route: Sentry; PR visible via `gh pr list --search "head:ci/" --state open`
  - mode: allowlist drops intended outputs (e.g. a new cascade artifact path)
    detection: Sentry op safe-commit-paths-dropped + ⚠️ marker in the PR body itself
    alert_route: Sentry; runbook row covers widen-vs-prompt-fix triage
  - mode: auto-merge silently disarms on conflict (dormant cohort only)
    detection: none until the deferred watchdog lands — explicitly gated on Tier-2 restoration via the Phase 6 tracking issue
    alert_route: tracking issue blocks restoration
logs:
  where: pino structured logs (fn/op keys: safe-commit-no-changes, safe-commit-pr) on the app container stdout
  retention: host journald/Better Stack pipeline as configured platform-wide (unchanged)
discoverability_test:
  command: gh pr list --repo jikig-ai/soleur --search "head:ci/" --state all --limit 5 --json number,title,state
  expected_output: recent bot-pipeline PRs with state MERGED (or OPEN within minutes of a fire); zero SSH required
```

## Test Scenarios

1. Helper defaults regression: existing `cron-safe-commit.test.ts` scenarios pass unmodified (no-changes, deletion guard, dirty index, replay-resume, 422 PR-create, clean-status fallback).
2. New option scenarios (Phase 1 list) on the scratch-git fixture.
3. Per prompt-cron: prompt contains PERSISTENCE anchor, lacks commit verbs; `safe-commit-pr` step fires only when `heartbeatOk && !abortedByTimeout` (4-way truth-table on one representative cron, gate-presence anchors on the rest — parity invariant 2 enforces the regex on all 7).
4. Per legacy cron: `safeCommitAndPr` called with the exact config table from Phase 3 (mocked helper, config snapshot assertions); non-persistence behavior (KPI cascade, labels detection, cluster guards) unchanged.
5. Parity invariants 1-4 green with cohorts + 2-entry EXEMPT.

## Test Strategy

vitest only (`apps/web-platform/vitest.config.ts` collects `test/**/*.test.ts` under the node project — all edited test files already live there). Invocation: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/`. TDD order per `cq-write-failing-tests-before`: Phase 1 helper tests RED → helper GREEN; Phase 4 parity cohort lists updated RED (fails on un-migrated files) → Phases 2-3 turn it GREEN per cron.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Batch-migrating 5 LIVE pipelines breaks a weekly producer silently | Behavior-preserving merge modes; defaults-unchanged regression tests; every helper failure stage is Sentry-mirrored + issue-commented (strictly more observable than the legacy copies); post-merge manual-trigger verification (AC12) |
| compound-promote per-cluster replay double-creates PRs | Helper's replay-resume (branch + ahead-count) and 422-already-exists tolerance both keyed on the overridden `branchName`; covered by a Phase 1 unit test |
| competitive-analysis allowedPaths widening commits unreviewed cascade artifacts | Cascade artifacts were always intended outputs (agent delegation table); PRs still pass required checks; dropped-path alternative would fire Sentry noise every run; PR body documents the change |
| vendor-drift large upstream restructure trips the deletion guard | Accepted by design (mass deletion = review-worthy); runbook raise-path documented; no per-cron override (YAGNI per #5091 review) |
| `SYNTHETIC_CHECK_NAMES` 5 copies have drifted from each other | Work-time diff of all 5 lists before consolidation; preserve any divergence as per-call override |
| Parity gate regex doesn't match new code formatting | The regex is the spec — write the gate block to match it (same literal shape as cron-seo-aeo-audit.ts:285); invariant 2 fails CI otherwise |
| Helper `stage` union reuse ("auto-merge" for direct-merge failures) confuses runbook triage | Runbook row updated in Phase 6.3 to cover both arming and execution failures |

## Alternative Approaches Considered

| Alternative | Why rejected |
|---|---|
| Unify all 12 pipelines on auto-merge and delete synthetic checks | Changes live merge semantics of 5 production crons in the same PR that rewires their staging — two variables at once. Synthetic+direct is production-proven (+54 s merges); auto-merge for THESE crons is not. Revisit at Tier-2 restoration (watchdog tracking issue is the natural host); the ADR documents modes so the future unification has a contract to amend. |
| Keep compound-promote EXEMPT (shape too divergent) | Operator-confirmed scope says all 9; leaving it exempt falsifies the ADR's "sole write path" claim and keeps a third rationale alive in EXEMPT. The option surface it needs (branchName/commitBody/prTitle/prDraft/prLabels/mergeMode none) is additive and reused by nothing else only for 3 of 6 fields — acceptable. |
| Implement the stale-`ci/*`-PR watchdog inline | Exposure window (auto-merge silent disarm) is entirely Tier-2-dormant after this PR; inline implementation expands an already-23-file batch; deferral is explicitly sanctioned by the issue and made un-droppable by gating Tier-2 restoration on the tracking issue. |
| Per-cron `maxDeletions` override for vendor-drift | YAGNI per #5091 plan review ("add an override param only when a cron actually needs one") — no evidence yet that re-vendor deletes >10. |
| Migrate opportunistically (issue's original migrate-when-touched framing) | Operator explicitly confirmed ALL 9 in one batch PR; the ADR and watchdog decision only make sense once the list empties. |

## Plan Review Synthesis (inline three-lens pass — pipeline mode, no reviewer subagents available)

- **DHH/simplicity lens:** option surface kept flat (8 optional fields, no nested config objects beyond `syntheticChecks`); `stage` union NOT widened; `SYNTHETIC_CHECK_NAMES` deduplicated 5→1; watchdog deferred instead of inline; no per-cron deletion override. Cut from draft: a `prTitleSuffixDate` boolean (folded into `prTitle` full-override semantics).
- **Kieran/correctness lens:** community-monitor's non-literal "MANDATORY FINAL STEP" handled explicitly; content-publisher's missing trailing slash caught against the helper's `startsWith` contract; parity invariant 2's prompt-anchor assertions shown to be unsatisfiable for pure-TS crons → cohort split; compound-promote's PR-title ≠ commit-message divergence caught (needs `prTitle`); content-publisher's "auto-merge fallback" comment verified to be a log-only aspiration (`cron-content-publisher.ts:416-424`) — the helper's direct→arm-auto-merge→fail ladder strictly improves it.
- **Flow lens (spec-flow):** persistence step ordering pinned (after `verify-output`, before `sentry-heartbeat`, mirroring the canonical migrated shape); the tri-state verify caveat is not silently inherited — tracked + comment-cited; post-merge verification path is deterministic (trigger-cron + PR-existence/Sentry-empty verdicts), no dashboard-eyeballing.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty/placeholder fails deepen-plan Phase 4.6 — section complete above.
- The parity gate regex (`{0,800}` window) is the contract for Phase 2's step placement — write code to the regex, don't loosen the regex to fit the code.
- `allowedPaths` matching is bare `startsWith`: every directory entry MUST end with `/` (content-publisher's current constant does not — fixed in Phase 3); file entries must be exact repo-root-relative paths.
- The 5 legacy crons keep `spawnGit` for clone/checkout-main — AC1 greps for `spawnGitChecked` (the checked wrapper), not `spawnGit`.
- Do NOT touch `cron-roadmap-review.ts` or `cron-bug-fixer.ts` — permanent exemptions with documented rationale; migrating them is out of scope and would break their distinct guard models.

## References

- `apps/web-platform/server/inngest/functions/_cron-safe-commit.ts` (#5091 helper, all invariants documented at implementation sites)
- `apps/web-platform/test/server/inngest/cron-safe-commit-parity.test.ts` (invariants 1-4)
- `knowledge-base/project/plans/2026-06-10-fix-bot-cron-safe-commit-guard-plan.md` (#5091 plan: consolidation follow-up contract at line 211; ADR + watchdog deferral provenance at lines 211/247)
- `knowledge-base/project/learnings/2026-06-10-bot-cron-safe-commit-substrate-symlink-removal.md`
- `knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md` §"PR Withheld by safe-commit (#5091)"
- `knowledge-base/engineering/architecture/decisions/ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md` (lineage)
- `infra/github/ruleset-ci-required.tf` (integration-pinned required checks context)
- `plugins/soleur/agents/product/competitive-intelligence.md` (cascade write-set audit source)
