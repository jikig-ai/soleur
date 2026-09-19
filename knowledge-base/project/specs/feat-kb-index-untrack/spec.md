---
title: "Spec: untrack generated KB caches, regenerate products on conflict"
feature: feat-kb-index-untrack
closes: 8377
also_closes: [8370]
related: [8116, 8151, 8177, 6109, 7935]
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-09-19-kb-index-untrack-generated-artifacts-brainstorm.md
status: draft
tags: [kb-index, merge-conflicts, generated-artifacts, ci, ship]
category: spec
---

# Feature: untrack generated KB caches, regenerate products on conflict

## Problem Statement

Three committed machine-generated files conflict on every advance of `main` because
GitHub's server-side merge cannot run the local merge driver that resolves them
(ADR-210). `knowledge-base/INDEX.md` alone was touched by 42 of 71 first-parent `main`
commits in 7 days; PRs #8319 / #8321 / #8347 paid 7 / 11 / 3 forced resyncs (~6 h each
for the first two). #8151 shortened the resync; it did not remove the class. AC17
(`generate-kb-index.sh --check`) additionally fails on `refs/pull/N/merge` (#8370).

The three files are different kinds of artifact — a cache of the tree, a cache of
gitignored local data, and a product artifact — and need different fixes.

## Goals

- No feature branch ever carries a diff on a regenerable cache.
- Every reader of the KB index finds a fresh, branch-local index (fixes the #8177 class).
- The `kb-index` merge driver, its installer, its `.gitattributes` routing, the guardrails
  sentinel and AC17 are removed; #8370 closes as a side effect.
- `rule-metrics.json` stops being a per-branch write.
- A `model.likec4.json` conflict is resolved by regeneration inside the existing sync
  path, with no human step.
- The classification is recorded in an ADR so the next generated file lands in the
  right column.

## Non-Goals

- Strict-up-to-date `BEHIND` restarts for code PRs (merge queue; ADR-032 lineage).
- Rule-metrics cross-worktree completeness / `first_observed` (#6109).
- Cleaning stray values out of `kb-tags.txt`.
- A committed, browsable KB index for GitHub web visitors (no consumer today).

## Functional Requirements

### FR1: KB index caches are untracked and regenerated on demand

`knowledge-base/INDEX.md`, `knowledge-base/kb-tags.txt`, `knowledge-base/kb-categories.txt`
are removed from git (`git rm --cached`) and listed in `.gitignore` at their existing
paths. A new `scripts/ensure-kb-index.sh` regenerates them when absent or stale
(staleness: any `knowledge-base` entry newer than `INDEX.md`, via `find -newer -print -quit`)
and is a no-op otherwise. The `> Total files:` header and `--check` mode are removed from
the generator; `--out` is kept.

### FR2: Readers regenerate before they read

`plugins/soleur/skills/kb-search/SKILL.md` (Tier-1 grep and `--tag/--category`
validation), `plugins/soleur/agents/engineering/research/learnings-researcher.md` Step 0,
its copy at `.openhands/skills/learnings-researcher/SKILL.md`, and
`scripts/learning-retrieval-bench.sh` call `ensure-kb-index.sh` **before** reading. When
neither the file nor `scripts/generate-kb-index.sh` exists (customer repos), `kb-search`
degrades to a frontmatter grep for tag/category validation and to content grep for
Tier 1 — it never hard-exits with a Soleur-only remediation and never reports "no prior
art" on the strength of an absent index.

### FR3: New checkouts and sessions start warm

`package.json` `prepare` runs `ensure-kb-index.sh` (replacing
`install-kb-merge-driver.sh`), which covers `worktree-manager.sh feature` via its
existing `bun install`. The `.claude/settings.json` SessionStart entry that ran the driver
installer runs `ensure-kb-index.sh` instead. Both exit 0 when `knowledge-base/` is absent.

### FR4: Merge-driver surface retired

Deleted: `scripts/merge-kb-index.sh`, `scripts/lib/kb-index-render.sh`,
`scripts/install-kb-merge-driver.sh`, the guardrails `INDEX.md` conflict-sentinel arm and
its tests, `plugins/soleur/test/kb-index-merge-driver.test.sh`,
`kb-index-merge-driver-registration.test.sh`, `merge-kb-index-driver-mutation.test.sh`,
`kb-index-check-guard-mutation.test.sh`, `kb-index-freshness.test.sh`. Edited:
`.gitattributes` (kb block), `lefthook.yml` (`generate-kb-index` step and the comments
that cite it), `.github/CODEOWNERS` rows, `.devin/config.json`, `devin-dispositions.tsv`,
`generate-kb-index.test.sh`, and the prose in `merge-pr`, `ship`, `compound`, `archive-kb`,
`spec-templates`, `work`, `brainstorm` SKILL.md files that instruct staging or merging
these files.

### FR5: rule-metrics.json is untracked

`knowledge-base/project/rule-metrics.json` is removed from git and gitignored.
`soleur:compound` still runs the aggregator locally but no longer stages the output.
`scripts/rule-prune.sh` runs the aggregator before reading. The CI `rule-metrics-shape`
step keeps its skip-when-absent path (or moves into the aggregator's test).
`.github/workflows/rule-metrics-aggregate.yml` and the `ALLOWED_PATHS` entry in
`bot-pr-with-synthetic-checks/action.yml` retire.

### FR6: model.likec4.json is regenerated on conflict

A manifest (`scripts/regenerable-artifacts.tsv` or equivalent: `path<TAB>regen command`)
lists `knowledge-base/engineering/architecture/diagrams/model.likec4.json →
bash scripts/regenerate-c4-model.sh`. `plugins/soleur/scripts/sync-pr-behind.sh` and
`.claude/hooks/pre-merge-rebase.sh`, on a `git merge-tree` failure whose `CONFLICT`
paths are all manifest paths, complete the merge (`git merge`, take either side for the
manifest paths, run each regen command, stage, commit, push) and emit a
`SOLEUR_REGEN_ON_CONFLICT path=… rc=…` stdout marker. Any non-manifest conflict keeps
today's abort-and-surface behaviour. A regen command failure aborts the merge and
surfaces (never pushes a stale or empty model).

### FR7: Transition for open PRs

`merge-pr` and `ship` carry a one-paragraph transition note: a branch that still carries
`INDEX.md` / `kb-*.txt` / `rule-metrics.json` hits a one-time modify/delete conflict on
sync — resolve with `git rm <path>`.

### FR8: Decision record

A new ADR supersedes ADR-210 and amends ADR-091: *caches (derived from the tree or from
gitignored local data) are untracked and regenerated on demand; products (read by a
consumer that cannot regenerate them) are committed and regenerated on conflict; no
regenerable artifact is resolved by a merge driver.*

## Technical Requirements

### TR1: Staleness test cost

`ensure-kb-index.sh` must complete in < 100 ms when the index is fresh (measured
baseline: `find -newer -print -quit` ≈ 50 ms; `git ls-files -s` fingerprint ≈ 60 ms).
Regeneration (≈ 3 s locally, 7–11 s on slow hosts) runs only when stale.

### TR2: Determinism and privacy of the local index

The generator's output remains deterministic for an unchanged tree. Plan-time decision
whether enumeration switches from `find` to `git ls-files` + non-ignored untracked files
so a local `knowledge-base/private/` is excluded; either is acceptable once the file is
untracked.

### TR3: Observability

Readers that regenerate emit a one-line `SOLEUR_KB_INDEX_REGEN reason=<absent|stale>
ms=<n>` marker on stdout (observability layer 7, `cli-stdout-artifact`, per
`hr-observability-layer-citation`). The regenerate-on-conflict path emits
`SOLEUR_REGEN_ON_CONFLICT`. No Soleur-side sink is added for self-hosted CLI runs
(ADR-171).

### TR4: Tests

- `ensure-kb-index.sh`: absent → regenerates; fresh → no-op (< 100 ms); a touched `.md`
  → regenerates; missing `knowledge-base/` → exit 0.
- `kb-search` tag fallback: no file + no generator → frontmatter grep path taken, exit 0.
- `sync-pr-behind.sh`: manifest-only conflict → regenerated and pushed; mixed conflict →
  abort; regen failure → abort, nothing pushed.
- Existing `c4-model-freshness.test.sh` and `rule-metrics-aggregate.test.sh` stay green.
- No `git grep` hit for `merge=kb-index`, `install-kb-merge-driver`, or
  `Total files:` outside `**/archive/**` and learnings after the change.

### TR5: Rollback

`git revert` of the PR followed by `bash scripts/generate-kb-index.sh && git add
knowledge-base/INDEX.md knowledge-base/kb-*.txt` restores the committed artifacts; the
generator is not removed.
