---
title: "Generated artifacts: untrack the caches, regenerate the products on conflict"
date: 2026-09-19
issue: 8377
related: [8116, 8151, 8370, 8177, 6109, 7935]
status: complete
lane: cross-domain
brand_survival_threshold: single-user incident
tags: [kb-index, merge-conflicts, generated-artifacts, ci, ship, lefthook]
category: brainstorm
---

# Generated artifacts: untrack the caches, regenerate the products on conflict

## What We're Building

Three committed, machine-generated files make every open PR `DIRTY` (or textually
conflicted) on every advance of `main`, because GitHub's server-side merge cannot run
the local merge driver that resolves them. Each file is a different *kind* of artifact
and gets a different fix, shipped in one PR:

| File | Kind | Writer today | Fix |
|---|---|---|---|
| `knowledge-base/INDEX.md`, `kb-tags.txt`, `kb-categories.txt` | **cache of the tree** (pure function of `knowledge-base/**/*.md`; 3 s to regenerate) | lefthook pre-commit on every commit | **Untrack.** `.gitignore` + `git rm --cached`; regenerate on demand via a new `scripts/ensure-kb-index.sh` (regen-if-stale) called by the readers, by `package.json` `prepare`, and by the SessionStart slot the merge-driver installer vacates. Retire the `kb-index` merge driver, its installer, `.gitattributes` routing, guardrails sentinel, AC17 and the five `kb-index-*` test suites. |
| `knowledge-base/project/rule-metrics.json` | **cache of gitignored local data** (`.claude/.rule-incidents*.jsonl`; ADR-091: the authoritative producer is the operator machine) | `soleur:compound` Phase 1.5 on every feature branch | **Untrack.** Same shape as INDEX.md: the committed copy was a derived snapshot of data that is not in git. `rule-prune.sh` regenerates via the aggregator before reading; CI `rule-metrics-shape` already skips when absent; the on-demand bot workflow and its `ALLOWED_PATHS` entry retire. |
| `knowledge-base/engineering/architecture/diagrams/model.likec4.json` | **product artifact** (the web-platform C4 viewer reads the committed file from synced repos; regeneration needs the pinned `likec4@1.50.0` CLI) | lefthook on any `.c4` edit | **Stays committed; regenerate-on-conflict.** A small manifest of regenerable artifacts (`path → regen command`) that `sync-pr-behind.sh` / the pre-merge-rebase hook consult: when `git merge-tree` reports conflicts *only* on manifest paths, complete the merge by taking either side, running the regen command, staging, and pushing — no human resolution. |

## Why This Approach

**The count header had zero readers.** `> Total files: N` was the line that guaranteed a
conflict on every pair of branches; it is read only by the driver, AC17 and their own
tests. The rows are read by `kb-search` (Tier 1), `learnings-researcher` Step 0 and
`learning-retrieval-bench.sh` — all agent-side tooling in this repo, all running where
`scripts/generate-kb-index.sh` exists. Verified: the web-platform does not read
INDEX.md (only two tests use the name as an arbitrary fixture); `knowledge-base/` has no
README.md and nothing links to INDEX.md, so it is not a landing page either.

**Server-side merge is the constraint, not the driver.** ADR-210's regenerating driver is
correct locally and inert on GitHub (`refs/pull/N/merge`, `update-branch`, auto-merge).
#8151 (option 2 from #8116) shortened the resync loop but left the class: 42 of 71
first-parent `main` commits in the last 7 days touched INDEX.md; PRs #8319 / #8321 /
#8347 measured 7 / 11 / 3 forced resyncs (~6 h wall-clock each for the first two).

**Removing the diff converts DIRTY to BEHIND; it does not remove BEHIND.** `CI Required`
has `strict_required_status_checks_policy = true` and the merge queue was reverted
(CodeQL merge-group deadlock post-mortem), so a code PR still restarts checks when
`main` advances. What this buys: docs-only PRs become eligible for ship's
settle-then-admin-merge hatch (it keys on `BEHIND`, never `DIRTY`), #8370 (AC17 on the
merge ref) dissolves, and no branch carries a regenerable file at all.

**Why not the issue's literal option 1 (keep committed, regenerate on `main`)?** Every
regen commit on `main` is itself an advance that re-`BEHIND`s every open PR (~6/day),
spends a CI run, and needs either a GitHub-App `bypass_mode = always` actor on the
ruleset or a bot PR per merge that is itself subject to strict up-to-date. It also
leaves the branch-local index stale until merge (the #8177 shape). On-demand local
regeneration is fresh by construction and costs nothing on `main`.

**Why ADR-210's rejection no longer holds.** It deferred "stop committing" on scope, not
merits, pricing: ~10 s regen on every compaction (measured 3 s here, 7–11 s on slower
hosts; a `find -newer` staleness test is ~50 ms, so regen runs only when the tree
changed), worktrees starting without an index (`prepare` already runs on
`worktree-manager.sh feature` via `bun install`), and five readers grepping the file
(each already tolerates absence and now calls `ensure-kb-index.sh` first). One latent
defect closes for free: the generator enumerates with `find`, so a gitignored
`knowledge-base/private/` would have been indexed by title into the *committed public*
file; an untracked index stays local.

**Why rule-metrics.json is the same class.** Its input is gitignored and per-machine;
ADR-091 already states a fresh CI checkout cannot produce it and that compound is the
authoritative local producer. Every compound run on every branch bumps counters and
`generated_at` → guaranteed conflict (39 `main` commits in 30 d; #8321 neutralised it
mid-flight by resetting to `main`'s blob). The durable data is the local
`.rule-incidents*.jsonl(.gz)` archives; the committed aggregate was a cache of them.
#6109 (cross-worktree completeness, `first_observed`) is unaffected and its
`merge=ours` sub-item becomes moot.

**Why model.likec4.json is different.** It has a product consumer that reads it from a
synced repo without the compiler, and regeneration needs a pinned Node CLI, so it must
stay committed. Its exposure is narrower (only two PRs both editing `.c4` collide) and
regeneration is deterministic, so automating resolution at the point the sync loop
already detects the conflict removes the human step without changing what is tracked.

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | Untrack `INDEX.md`, `kb-tags.txt`, `kb-categories.txt`; keep the same paths, gitignored | Readers need no path edits; `kb-domain-allowlist-guard.sh:51` and `.markdownlintignore:2` already sanction the names |
| 2 | New `scripts/ensure-kb-index.sh`: regen-if-stale (`find knowledge-base -newer knowledge-base/INDEX.md -print -quit`, then `generate-kb-index.sh`) | ~50 ms when fresh; directory mtimes catch deletes/renames; avoids the per-compaction tax #7935 priced |
| 3 | Wire it in three places: readers (`kb-search`, `learnings-researcher` + its `.openhands` copy, `learning-retrieval-bench.sh`) **before** they read; `package.json` `prepare`; SessionStart (replacing `install-kb-merge-driver.sh`) | Readers = correctness (cloud harnesses without hooks); `prepare` = new worktrees; SessionStart = warm start |
| 4 | Readers must never conclude "no prior art" from an absent index; `kb-search --tag` degrades to a frontmatter grep when neither the file nor the generator exists (customer repos) | Today's `kb-search/SKILL.md:57-60` hard-exits with a Soleur-only remediation |
| 5 | Delete `--check` and the `> Total files:` header from the generator; keep `--out` | Their referent (a committed copy that can be stale) no longer exists |
| 6 | Retire: `scripts/merge-kb-index.sh`, `scripts/lib/kb-index-render.sh`, `scripts/install-kb-merge-driver.sh`, `.gitattributes` kb block, lefthook `generate-kb-index`, guardrails sentinel arm + its tests, `kb-index-merge-driver*.test.sh`, `merge-kb-index-driver-mutation.test.sh`, `kb-index-check-guard-mutation.test.sh`, `kb-index-freshness.test.sh`, CODEOWNERS rows, `.devin/config.json` + `devin-dispositions.tsv` entries | Each exists only to protect the committed artifact |
| 7 | Untrack `rule-metrics.json`; `rule-prune.sh` runs the aggregator before reading; retire `rule-metrics-aggregate.yml` and the `ALLOWED_PATHS` entry; CI `rule-metrics-shape` keeps its skip-when-absent | Cache of gitignored local data (ADR-091) |
| 8 | `model.likec4.json` stays committed; add a regenerable-artifacts manifest and teach `sync-pr-behind.sh` (+ `pre-merge-rebase.sh`) to resolve manifest-only conflicts by regenerating | Product consumer; pinned CLI; deterministic output |
| 9 | One new ADR supersedes ADR-210 and amends ADR-091: *caches are untracked and regenerated on demand; products are committed and regenerated on conflict; nothing regenerable is resolved by a merge driver* | Records the classification so the next generated file lands in the right column |
| 10 | Transition note in `merge-pr`/`ship`: open PRs carrying INDEX.md or rule-metrics.json hit a one-time modify/delete conflict — resolve with `git rm` | One-time cost on the ~20 open PRs |
| 11 | Rollback: `git revert` the PR, then `generate-kb-index.sh && git add knowledge-base/{INDEX.md,kb-*.txt}` | Generator is untouched |

## Non-Goals

- The strict-up-to-date `BEHIND` restart for code PRs (merge queue; ADR-032 amendment and its post-mortem own that).
- Cross-worktree completeness and `first_observed` for rule metrics (#6109, unchanged).
- Cleaning stray values in `kb-tags.txt` (`#4307`, `-target`, path-shaped tags) — data-quality nit in frontmatter, not a legal exposure (CLO), not this change.
- A committed, browsable KB index for GitHub web visitors — no consumer today; if one appears, a single-writer snapshot on `main` is the reversible follow-up.

## Open Questions

- Should `generate-kb-index.sh` switch from `find` to `git ls-files` + untracked-but-not-ignored enumeration so a local `knowledge-base/private/` is excluded from the local index too? (Plan-time call; either is safe once untracked.)
- The `prepare` hook runs on every `bun install`; confirm it stays a no-op when fresh (it will, via the staleness test) and that CI images without a `knowledge-base/` checkout exit 0.
- Regenerate-on-conflict for `model.likec4.json` needs `likec4@1.50.0` available where the sync runs (operator machine: yes via `bunx`; hosted ship clone: verify).

## User-Brand Impact

- **Artifact:** the KB index cache (`INDEX.md`, facet files), the rule-metrics cache, and the ship/merge-pr sync path that resolves `model.likec4.json`.
- **Vector:** a reader that silently searches a stale or absent index and reports "no prior art", or a sync step that regenerates the C4 model from broken sources and pushes an empty model to the viewer.
- **Threshold:** `single-user incident`.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering

**Summary:** CTO sized the KB-index half at ~one day; enumerated the retirement inventory (delete vs edit) and proposed `find -newer` staleness plus the `prepare`-hook wiring; flagged the `find`-based generator's latent `private/` leak; found no required status check depends on the files being in a checkout. Repo research confirmed no CI reader, mapped every prose site to sweep, and found the `.openhands` duplicate of learnings-researcher. Learnings research: regen measured 7–11 s on slower hosts (so regen-if-stale is load-bearing) and lazy regen must run before the search, never best-effort.

### Product

**Summary:** No customer consumer — the web-platform KB viewer renders whatever exists on disk via generic `fs.readdir` and never special-cases the files; no roadmap conflict; the #8177 residue is evidence *for* on-demand regeneration (the committed index was chronically behind `main`).

### Legal

**Summary:** No legal gate. One non-evidentiary prose mention in `knowledge-base/legal/audits/2026-09-counsel-review-8159.md:223`; the stray `kb-tags.txt` values disclose nothing not already public.

## Session Errors

- First framing question offered "regen on main" mechanisms before establishing who reads the files; the operator's "why regenerate at all / which parts" question was the right one and collapsed the option space. Lesson for the brainstorm skill: for a generated artifact, enumerate readers and the per-line reader of each *conflict-bearing* line before proposing writers.
- Two operator-side clarifications (INDEX.md as landing page; INDEX.md as webapp input) were each falsified by one grep — treat "X reads this" as a claim to verify in both directions.
