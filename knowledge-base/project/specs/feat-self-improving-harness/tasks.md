---
feature: self-improving-harness
plan: knowledge-base/project/plans/2026-07-05-feat-weakness-miner-plan.md
issue: 6037
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Tasks: Read-Only Weakness-Miner (#6037)

## Phase 0 — Preconditions

- [x] 0.1 Confirm the test runner: read the sibling `rule-metrics-aggregate` test + `bunfig.toml`;
  pick harness (`.test.sh` vs bun/vitest) + discovery glob. Freeze the test path only after confirming.
- [x] 0.2 Read `scripts/rule-metrics-aggregate.sh` header + `bot-pr-with-synthetic-checks` `action.yml`
  inputs; capture the exact PR contract (add-paths, branch-prefix, commit-message, pr-body ≥50%
  path-cited).
- [x] 0.3 Verify the first-appearance recency command (`git log --diff-filter=A --format=%cI -- <file>
  | tail -1`) against a real learning file; reuse canonical gsub awk for frontmatter reads only.

## Phase 0.4 — Clustering-key go/no-go spike (BEFORE the pipeline)

- [x] 0.4.1 Run a ≤20-line awk/jq spike applying the frontmatter key to the real last-7-day corpus.
- [x] 0.4.2 Eyeball top clusters: genuine failure patterns → keep frontmatter key; taxonomy echoes →
  switch to `## Session Errors` body error-signature n-grams. Record the chosen key + spike output in
  the PR body.

## Phase 1 — Deterministic miner script (RED → GREEN)

- [x] 1.1 Write failing test (AC8): synthetic fixture learnings dir with controlled git
  first-appearance dates; cases for ≥3 threshold, in/out-of-window, first-run bounding, both
  zero-mutation boundaries.
- [x] 1.2 Implement `scripts/weakness-miner.sh`:
  - [x] 1.2.1 Select learnings by 7-day git first-appearance window (`--diff-filter=A`, `>=` lower).
  - [x] 1.2.2 Cluster by Phase-0.4 key + column-anchored `^## Session Errors`; count occurrences.
  - [x] 1.2.3 Rank clusters with ≥3 members (AC2).
  - [x] 1.2.4 Emit `weakness-digest.md` through a single write sink (AC4a).
- [x] 1.3 GREEN the test (AC1, AC2, AC3, AC8).

## Phase 2 — Workflow + wiring

- [x] 2.1 `.github/workflows/weakness-miner.yml`: weekly `schedule` + `workflow_dispatch`; run script;
  `bot-pr-with-synthetic-checks` PR with single-path `add-paths` (AC4b/AC5); pin action SHAs.
- [x] 2.2 `notify-ops-email` on `failure()` (AC6). No SSH.
- [x] 2.3 Dev-facing pointer to `weakness-digest.md` (AC7) — placed in the **compound-promote
  runbook**, NOT operator-digest: its L1 scope guardrail forbids a 5th source and a non-technical
  founder's digest must not carry dev-harness internals. Discoverability = the weekly bot-PR (sibling
  rule-metrics-aggregate pattern) + the runbook pointer.
- [x] 2.4 Seed initial `weakness-digest.md` (header + "first run pending"); AC3 guards backlog exclusion.
- [x] 2.5 `actionlint` the workflow; `bash -c` the extracted `run:` snippet.

## Phase 3 — Verify

- [x] 3.1 Full test suite via the Phase-0 runner; `actionlint`.
- [x] 3.2 Dry-run the script against the real 7-day window; eyeball digest; assert `git status
  --porcelain` touches only the digest path (AC4a).

## Out of scope (tracked)

- LLM theme-naming pass → v1.1 (#TBD; substrate-lock: likely Inngest per ADR-033).
- Obsolescence / rule-fire output → #6042 (CI incidents-log gap).
- Additive-only auto-proposer → #6038. Product changelog → #6039.
