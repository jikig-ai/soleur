---
title: A producer that runs where its gitignored input isn't structurally emits zeros
date: 2026-07-06
category: best-practices
tags: [telemetry, ci, gitignore, dry-run, orphan-test, rule-metrics]
issue: 6042
pr: 6099
adr: ADR-091
---

# A producer that aggregates a gitignored, local-only input must run locally, not in CI

## Problem

`scripts/rule-metrics-aggregate.sh` rolls up `.claude/.rule-incidents.jsonl` (PreToolUse-hook
telemetry) into the committed `knowledge-base/project/rule-metrics.json`. The incidents log is
**gitignored by deliberate design** — its `command_snippet` field verbatim-stores absolute paths,
git/gh identity, and PR-body text, so it must never be committed. The aggregator ran on a **weekly CI
cron** (`.github/workflows/rule-metrics-aggregate.yml`) over a **fresh checkout**, where the gitignored
log does not exist → it read zero events → it committed an all-zero (`97/97 unused`) snapshot **every
week**, clobbering any real local aggregate. The rule-utility signal had **never once carried
information** in its CI-cron form (100% unused in every commit since 2026-04-15).

## Key Insight

**When a producer aggregates an input that is gitignored / local-only / machine-local, the producer must
run where the data lives — not in a fresh-checkout CI job.** CI sees an empty input and, unless guarded,
commits a structurally-zero artifact that looks like real data to every consumer. The fix is three moves:

1. **Move the authoritative producer to the local surface** that already touches the data (here: the
   `compound` flow, which runs on the operator's machine where `.rule-incidents.jsonl` exists).
2. **Guard the write on DATA-presence, not FILE-presence.** The no-op guard keys on `valid_lines == 0`
   (zero rule-carrying rows), NOT `[[ -s file ]]` — a *sentinel-only* log is non-empty but carries zero
   real rows, and a file-size gate would still clobber real data with zeros. That distinction is the
   whole bug.
3. **Drop the false-zero producer** (the CI `schedule:`), keeping only `workflow_dispatch` for on-demand
   runs (which self-no-op on a fresh checkout).

Recorded as [ADR-091](../../../engineering/architecture/decisions/ADR-091-rule-metrics-local-producer.md);
supersedes the 2026-04-14 plan's ADR-3 single-log premise (events actually fragment across ~12 worktree
logs — cross-worktree read-merge is deferred).

## Session Errors

- **Promoting a `--dry-run` call to a real write can resurrect a latent downstream-staging bug.**
  `compound` step 8 previously ran the aggregator with `--dry-run` (never wrote). Making it write for
  real exposed that the aggregator's orphan gate `exit 5`s *after* writing `rule-metrics.json` (CI
  forensic context), and a later blanket `git add -A knowledge-base/` (compound-capture consolidation)
  would stage that rejected aggregate despite step 8's exit-code guard. Caught by review
  (git-history-analyzer). **Recovery:** step 8 now `git checkout -- "$OUT"` on aggregator failure.
  **Prevention:** when converting a `--dry-run`/no-write call into a real write, enumerate every
  downstream blanket-stage (`git add -A <dir>`) that could pick up a partial/failed output, and revert
  on failure — a per-call exit-code guard does not protect against a sibling blanket add.

- **The plan's authoritative test suite (`scripts/rule-metrics-aggregate.test.sh`) was an unregistered
  orphan** — `test-all.sh`'s `scripts` shard runs `plugins/**/*.test.sh` and `scripts/lib/*.test.sh`
  globs but not `scripts/*.test.sh`, and no explicit `run_suite` line existed for it. So its sentinel-only
  clobber regression guard (the exact bug being fixed) would never have gated in CI. **Recovery:** added
  an explicit `run_suite` line. **Prevention:** when a PR's central regression lives in a `scripts/*.test.sh`,
  confirm it is wired into `test-all.sh` (explicit line or glob) — a green local run is not a CI gate.

- **First-draft ADR cross-link used a fabricated filename** (`ADR-054-weakness-miner-ci-cron-bot-pr.md`;
  real: `ADR-054-safe-commit-and-pr-sole-write-path-for-bot-cron-prs.md`). Self-caught via `ls` before
  commit. **Prevention:** `ls` the target before writing any `ADR-NNN-...md` cross-link.

- **Forwarded from plan phase (session-state.md):** two `Write` calls initially blocked (main-checkout
  target; read-before-write) — both retried successfully. Already covered by existing worktree hard rules.

## Tags
category: best-practices
module: rule-metrics
