# ADR-054: safeCommitAndPr is the sole write path for bot cron PRs

- **Status:** Accepted
- **Date:** 2026-06-10
- **Issue:** #5111 (consolidation batch; ADR deferred from #5091 because the "sole write path" claim only became true once the parity-test exemption list emptied)
- **Lineage:** ADR-033 (Inngest crons invoke Claude Code via child-process spawn — this ADR governs how those runs, and the pure-TS data-refresh crons beside them, persist their output)

## Context

PR #5026 was a destructive bot PR: a prompt-level `git add -A` staged 654 structural deletions produced by the ephemeral-workspace scaffolding, and the PR auto-merged. The root cause was architectural, not a prompt bug — **the prompt is a suggestion to a model; persistence is a platform responsibility.** Issue #5091 (merged via PR #5098) introduced `safeCommitAndPr()` (`apps/web-platform/server/inngest/functions/_cron-safe-commit.ts`): a deterministic, non-throwing, replay-idempotent handler-side commit/PR pipeline with scoped staging (allowlist), a clean-index precondition, structural exclusion, a loud dropped-path warn (Sentry + PR-body ⚠️ marker), and a mass-deletion guard — and migrated the 3 blanket-add crons.

Nine other bot pipelines still carried their own persistence in two shapes: 4 prompt-level scoped-add crons (Tier-2 dormant) whose prompts instructed the spawned model to run `git add … gh pr merge`, and 5 live pure-TS pipelines each holding a private `spawnGitChecked` staging/commit/push/PR/check-run/merge copy. #5111 migrated all 9.

## Decision

**`safeCommitAndPr` is THE write path for bot cron PRs.** Prompt-side persistence instructions and per-cron handler-side persistence copies are forbidden. New bot pipelines call the helper; they do not reimplement staging, commit, push, PR creation, or merge.

### The three merge modes

| Mode | Behavior | When it applies |
|---|---|---|
| `auto` (default) | `enablePullRequestAutoMerge` (squash), with a clean-status direct-merge fallback | Claude-spawn output PRs (seo-aeo-audit, content-generator, growth-execution, campaign-calendar, growth-audit, community-monitor, competitive-analysis) — required checks must pass before merge |
| `direct` + `syntheticChecks` | Post synthetic check-runs on the head SHA, then `PUT …/merge` immediately; on failure, fall back to arming auto-merge, then fail loudly at stage `auto-merge` (PR stays open) | Deterministic data-refresh PRs (weekly-analytics, content-publisher, content-vendor-drift, rule-prune) — production-proven mechanics (e.g. `ci/content-publisher-2026-05-19-164226` merged +54 s) |
| `none` + `prDraft` | Create the PR only; never touch merge endpoints | Human-review proposal PRs (compound-promote's `self-healing/auto-*` drafts) |

This PR-class split deliberately preserved each live cron's production-proven merge mechanics — the #5111 batch changed the staging/guard layer only, never merge semantics. Unifying onto auto-merge was rejected (two variables in one change); it is revisitable at Tier-2 restoration.

### The two permanent exemptions

| Cron | Rationale |
|---|---|
| `cron-roadmap-review.ts` | Live Tier-1: the model improvises git within its finite bash allowlist; the containment hook's blanket-staging deny set + the prompt STAGING RULE are its guard model. Routing it through the helper would conflict with its allowlist-validated self-commit design. |
| `cron-bug-fixer.ts` | The commit step lives in `plugins/soleur/skills/fix-issue` (scoped add since #5091), not in the cron's prompt or handler — the skill owns persistence. |

## Enforcement

`apps/web-platform/test/server/inngest/cron-safe-commit-parity.test.ts` — a self-discovering parity guard (walks `server/inngest/functions/` at run time) with four invariants:

1. No cron/event source (nor the containment hook) contains a blanket git-add literal.
2. Migrated crons route through `safeCommitAndPr`. Two cohorts: `MIGRATED_PROMPT` (claude-spawn crons — full assertions: import, call, `PERSISTENCE: Do NOT run git add` prompt anchor, the `heartbeatOk && !spawnResult.abortedByTimeout` gate regex, no `MANDATORY FINAL STEP`) and `MIGRATED_HANDLER` (pure-TS crons — import + call + no `spawnGitChecked` staging; prompt anchors are unsatisfiable where there is no prompt).
3. **Tier-2 restoration constraint:** a migrated cron's `CRON_BASH_ALLOWLISTS` entry must NOT re-arm prompt-side persistence verbs (`git add/commit/push`, `gh pr create/merge`). A restoration that re-adds them fails CI here instead of relying on a PR-body memo (the #5026 sequencing hazard).
4. Self-discovery: every cron with a staging pathway must be classified as migrated or exempt (a NEW cron cannot dodge the cohorts), AND migration is a constraint, not a terminal state — a migrated cron must have NO staging pathway outside the helper. The exemption list itself is explicit, rationale-carrying, and now permanently two entries (asserted under invariant 2's disjointness check).

## Consequences

- All 12 migrated pipelines gain the deletion guard, dirty-index precondition, dropped-path warn (Sentry + PR-body marker), replay-resume idempotency, token-scrubbed failure messages, and operator-visibility issue comments.
- Tier-2 restoration of the dormant prompt crons cannot silently re-arm prompt-side persistence (invariant 3 is the tripwire).
- **~~Deferred~~ Resolved (#5138):** the stale-`ci/*` bot-PR watchdog. Auto-merge silently disarms on merge conflict — the only invisible-stale mode. After #5111 every `mergeMode: "auto"` pipeline is Tier-2 dormant, so the FIRST-rung exposure is zero until restoration. A narrow live window remains: a `direct` pipeline whose immediate merge fails falls back to ARMING auto-merge (Sentry op `safe-commit-direct-merge-fell-back` marks the entry into that state), so #5138's scope includes live direct pipelines, not just the dormant auto cohort. Shipped in `cron-cloud-task-heartbeat` as a daily merge-mode-agnostic age scan over `ci/*` / non-draft `self-healing/auto-*` heads (warn + owning-issue comment, routed via `sentry_issue_alert.stale_bot_pr`); the Tier-2 restoration gate on the PR-flow crons is now cleared.
- **Monitoring semantics change for the 5 live pipelines:** the old throwing git pipelines turned persistence failures into Inngest step retries + a red heartbeat; the non-throwing helper resolves them inline, so their cron monitors stay GREEN and Sentry ops (`safe-commit-failed`, `safe-commit-deletion-guard`) are the failure signal, with the next scheduled run as the retry. This matches the #5091 contract for the claude-spawn crons (monitor = "the cron ran"; persistence health is a Sentry-op concern) and is documented in the runbook's comment-channel scope note.
- **Deferred:** a tri-state output-verify gate (#5139) — `resolveOutputAwareOk` falls back to the spawn exit code when its GitHub verify-read throws, so persistence can be gated on a fallback-green.
- A legitimate mass deletion (e.g. content-vendor-drift re-vendoring a large upstream restructure) trips the deletion guard by design: Sentry `safe-commit-deletion-guard` + PR-withheld comment; the runbook (`knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md` §"PR Withheld by safe-commit") documents the `DEFAULT_MAX_DELETIONS` raise path.

## Alternatives considered

| Alternative | Why rejected |
|---|---|
| Unify all 12 pipelines on auto-merge, delete synthetic checks | Changes live merge semantics of 5 production crons in the same PR that rewires their staging — two variables at once; synthetic+direct is production-proven for these crons, auto-merge is not. Revisit at Tier-2 restoration. |
| Keep compound-promote exempt (shape too divergent) | Falsifies the "sole write path" claim and keeps a third exemption rationale alive. The option surface it needs (branchName/commitBody/prTitle/prDraft/prLabels/mergeMode none) is additive. |
| Implement the stale-PR watchdog inline | Exposure window is entirely Tier-2-dormant after #5111; deferral is made un-droppable by gating restoration on #5138. |
| Per-cron `maxDeletions` override | YAGNI per #5091 plan review — no evidence any cron legitimately deletes >10 files; the guard firing on a mass re-vendor is the guard working. |

## References

- #5026 (destructive incident) · #5091 / PR #5098 (helper) · #5111 (consolidation batch) · #5138 (watchdog, gates Tier-2 restoration) · #5139 (tri-state verify gate)
- ADR-033 (claude-spawn substrate) · #5018 / #5046 (Tier-2 deferral and partial restoration)
