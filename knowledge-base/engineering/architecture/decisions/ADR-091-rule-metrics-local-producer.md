# ADR-091: Rule-metrics aggregation is a local (compound-flow) producer, not a CI cron

- **Status:** Accepted
- **Date:** 2026-07-06
- **Issue:** [#6042](https://github.com/jikig-ai/soleur/issues/6042) (blocker cut from the weakness-miner [#6037](https://github.com/jikig-ai/soleur/issues/6037), merged as PR #6036)
- **Supersedes (in part):** ADR-3 of the [2026-04-14 rule-utility-scoring plan](../../../project/plans/2026-04-14-feat-rule-utility-scoring-plan.md) — its "single `flock`-guarded file, no per-session fragmentation" premise.
- **Diverges from:** [ADR-054](./ADR-054-safe-commit-and-pr-sole-write-path-for-bot-cron-prs.md) — the bot-cron-PR write-path precedent, *for this sink only*.

## Context

`knowledge-base/project/rule-metrics.json` scores AGENTS.md rule utility from `.claude/.rule-incidents.jsonl` (PreToolUse-hook telemetry). That raw incidents log is **gitignored and local-only by deliberate design**: its `command_snippet` field (≤1024 chars) verbatim-stores absolute paths, git/gh identity, and quoted PR-body text, so it must never be committed (mode `0600` locally).

The weekly CI cron `.github/workflows/rule-metrics-aggregate.yml` ran the aggregator on a **fresh checkout**, where the gitignored log does not exist → the aggregator read zero events → it committed `rule-metrics.json` with `total_rules_tagged: N, rules_unused_over_8w: N` (100% unused). This was **structural, not transient**: every weekly aggregate commit since the file's first ship (2026-04-15) showed 100% unused — the signal has **never once carried information** in its CI-cron form. Any consumer (compound's unused-rules hint; `scripts/rule-prune.sh` once real data flows) read an all-zero aggregate.

`.rule-incidents.jsonl`'s null-first-seen guard (rule-prune's `first_seen != null` filter, #3123) means the all-zero state yields **zero** prune candidates, so the bug is **inert dead telemetry**, not active mis-firing — but a committed file asserting false 97/97 is still wrong, and it blocked the obsolescence half of the self-improving harness.

## Decision

The **authoritative producer** of `rule-metrics.json` is the **local compound flow** (`plugins/soleur/skills/compound/SKILL.md` Phase 1.5 step 8), which already runs the aggregator on the operator's machine where `.rule-incidents.jsonl` exists. Concretely:

1. **Aggregator no-ops on zero rule-carrying lines** (`scripts/rule-metrics-aggregate.sh`). When the merged incident stream has zero valid `rule_id` rows — empty/absent log (fresh checkout) OR a sentinel-only log (non-empty, zero `rule_id` rows) — it exits 0 **without writing** and **without rotating**, leaving the committed aggregate byte-identical. Keyed on `valid_lines == 0`, not file size (a sentinel-only file is non-empty).
2. **compound becomes the authoritative local writer.** Step 8 runs the aggregator for real and stages the aggregate only if it changed (`git diff --quiet -- <OUT> || git add <OUT>`), so it lands in the session's compound commit. Only the redaction-safe aggregate (rule_id + counts + a 50-char public prefix) is committed — never the raw `command_snippet` log.
3. **The CI cron is removed as a producer.** The `schedule:` trigger is dropped from `rule-metrics-aggregate.yml` (only ever committed false zeros); `workflow_dispatch` is retained for on-demand manual runs, which self-no-op on a fresh checkout.

## Alternatives Considered

- **(A) Commit a rotated/aggregated raw incidents snapshot so CI has data.** Rejected — privacy: `command_snippet` carries absolute paths, git/gh identity, and PR-body text unscrubbed. Committing it is a secret-leak regression that defeats the deliberate gitignore. Only the aggregate is safe to commit.
- **(C) Accept CI-zero, derive the weakness signal from learnings only.** Rejected — status quo; leaves a *committed* file asserting false 97/97 that every consumer reads.
- **Write-path log centralization (single shared inode across worktrees).** Rejected (CTO) — mutates three fire-and-forget flock producers whose correctness needs byte-identical inode resolution; disproportionate risk. Read-time merge (deferred) delivers the same completeness safely.

## Consequences

- **Relationship to ADR-3.** This supersedes ADR-3's "single file, *no per-session fragmentation*" premise, empirically falsified today: events fragment across ~12 worktree-local logs (the bare-primary root holds the ~577 KB canonical log; sibling worktrees carry 4–16 KB scraps). This ADR does **not** restore the single-file invariant — cross-worktree completeness is **deferred** (see below). Until the follow-up lands read-merge, the committed metric reflects the **committing worktree's** log: real, but under-complete.
- **Divergence from ADR-054.** ADR-054's bot-cron-PR write-path is correct for sinks whose inputs are repo-tracked. It does not apply to this sink because the input log is gitignored and structurally invisible to a fresh CI checkout.
- **Metric goes stale/under-complete, never false-zero.** Between compound runs the aggregate is last-known-good. No consumer breaks: rule-prune reads the committed file, is quarterly + manually `/sync`-triggered, and its `first_seen != null` guard already prevents mass false-retirement; `weakness-miner.yml` is fully decoupled.
- **Lost automated locality-regression detector (deferred).** Dropping the cron removes the only *scheduled* detector of a future locality re-break. A read-only assertion (`jq -e '.summary.rules_unused_over_8w < .summary.total_rules_tagged'` on the *committed* file) inside an existing scheduled job would restore it with zero producer — but it can only go green once real local data has flowed, so it is added in the follow-up, not here.

## Deferred to follow-up

Tracked in one issue (`Ref #6042`, milestone `Post-MVP / Later`): (1) cross-worktree read-merge (aggregator reads all worktree logs read-only via `git worktree list --porcelain`, including the bare primary root); (2) a `first_observed` obsolescence age-proxy so never-fired-but-long-present rules become prunable; (3) the rule-prune proxy swap; (4) the read-only scheduled canary. Both simplification reviewers and both correctness reviewers converged on deferring these — they carry multiple concrete bugs best resolved against real accumulated data.
