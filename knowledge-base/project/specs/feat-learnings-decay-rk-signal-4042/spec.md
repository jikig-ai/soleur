---
title: Pre-committed Action Ladder for Learnings Archive (Conditional)
status: draft
owner: engineering
issue: 4042
sibling_issue: 4043
sibling_pr: 4045
brainstorm: knowledge-base/project/brainstorms/2026-05-19-learnings-decay-rk-signal-brainstorm.md
created: 2026-05-19
lane: single-domain
brand_survival_threshold: none
---

# Spec: Pre-committed Action Ladder for Learnings Archive

**Issue:** #4042
**Branch:** feat-learnings-decay-rk-signal-4042
**Brainstorm:** [2026-05-19-learnings-decay-rk-signal-brainstorm.md](../../brainstorms/2026-05-19-learnings-decay-rk-signal-brainstorm.md)

## Problem Statement

`knowledge-base/project/learnings/archive/` exists; archival is purely manual. Issue #4042 proposed a recurring auto-archive workflow keyed off `rule-metrics.json` per-learning fire counts. **The proposed mechanism is mis-premised:** `rule-metrics.json` tracks AGENTS.md rule fires (78 rule IDs), not per-learning hits — `scripts/rule-metrics-aggregate.sh` has no per-learning telemetry source, and instrumenting one would be heavy.

Sibling PR #4045 (merged 2026-05-19) shipped `scripts/learning-retrieval-bench.sh`: a one-shot diagnostic producing per-corpus R@5/R@10/MRR + a `worst_n` array (cap 20) of files with `R@5(heavy, kbsearch) = 0`, classified by `cause` (`missing-frontmatter`, `slug-mismatch`, `cross-category-dup`, `content-shape`, `unknown`). The bench has not been run yet — no output file exists today.

This spec reshapes #4042 as a **pre-committed conditional action ladder**: when the operator runs the bench for the first time, the spec dictates the response branch based on `worst_n.length`. No script is built unless branch B fires. Mirrors the sibling-brainstorm pattern of pre-committing the outcome buckets BEFORE the number lands.

## Goals

- **G1.** Pre-commit a response curve before the bench is run, so the operator does not negotiate ad-hoc when the data arrives.
- **G2.** Re-use `worst_n` from the bench as the candidate pool (`R@5(heavy, kbsearch) = 0`). No new telemetry stream.
- **G3.** Distinguish "rewrite" candidates (sibling's `surface-rewrites` bucket) from "archive" candidates by `cause` classification — archive only `content-shape` / `cross-category-dup` / `unknown`.
- **G4.** Gate every archival on per-file human sign-off in a PR comment (no auto `git mv`).
- **G5.** Add forward-compatible opt-out frontmatter `archive: never` for learnings the operator marks load-bearing.

## Non-Goals

- **NG1.** Recurring infrastructure (no `.github/workflows/` file, no cron, no monthly schedule).
- **NG2.** Mutating `rule-metrics.json` schema or extending `scripts/rule-metrics-aggregate.sh` with per-learning counts.
- **NG3.** Auto-generating `git mv` PR. Output (when a script is built) is a markdown report; the operator authors the archive PR.
- **NG4.** Backfilling `archive: never` frontmatter across the corpus. Adoption is per-candidate at triage time.
- **NG5.** Replacing the sibling's `surface-rewrites` bucket. Slug/frontmatter rewrites stay routed to that bucket; archive is for genuinely stale content only.
- **NG6.** Acting on a single bench snapshot for the sibling rule-side workflow (#3683 covers that with an 8-week telemetry window post-2026-07-04).

## Functional Requirements

- **FR1 — Trigger.** Operator runs `bash scripts/learning-retrieval-bench.sh --confirm` against the corpus. The bench writes its output learning + sibling JSON. This spec's action ladder is evaluated against that JSON.

- **FR2 — Branch A: `worst_n.length ≤ 5`.** Operator triages inline in a single archive PR. No script is built. For each entry: read the file, decide archive vs. rewrite-and-keep vs. exempt-with-`archive: never`. Closes #4042 atomically via the archive PR's `Closes #4042` line.

- **FR3 — Branch B: `worst_n.length ∈ [6, 20]`.** Build `scripts/learning-archive-candidates.sh` per TR1–TR6 below. Script emits a markdown report; operator triages from report, authors archive PR. Closes #4042 atomically via the archive PR.

- **FR4 — Branch C: `worst_n.length == 20` (cap hit) AND `extraction_stats` suggests truncation.** Do not act on a truncated list. File a follow-up issue to extend `scripts/learning-retrieval-bench.sh` with `r5_zero_count` (total) reported alongside `worst_n`. Leave #4042 open with a pointer comment to the follow-up issue.

- **FR5 — Cause filter (Branch B only).** Drop `worst_n` entries whose `cause` ∈ {`missing-frontmatter`, `slug-mismatch`} from the archive candidate list. Those route to the sibling's `surface-rewrites` bucket. Archive considers only `cause` ∈ {`content-shape`, `cross-category-dup`, `unknown`}.

- **FR6 — Grep-rank gate (Branch B only).** For each remaining candidate at path `P` with title slug `S`: run `git grep -l "<S>" knowledge-base/project/learnings/`. If `P` appears in the first 3 results, drop it from the archive list — high grep recall = findable via the dominant lookup mechanism (per CTO's skill-ROI framing). Otherwise retain.

- **FR7 — Opt-out (Branches A and B).** Any learning whose YAML frontmatter contains `archive: never` is excluded from the candidate pool. Default absent = eligible. The operator may add the field during triage to exempt a candidate from future ladder runs.

- **FR8 — Output (Branch B).** `scripts/learning-archive-candidates.sh` writes a markdown report to `knowledge-base/project/learnings-archive-candidates-<YYYY-MM-DD>.md` (gitignored, transient). Report includes a table with columns: `path`, `cause`, `r5_heavy_kbsearch`, `grep_rank` (computed in FR6), `age_days` (from `git log --diff-filter=A --format=%ci -- <path>`), `inbound_link_count` (from `git grep -c "[[<title-slug>]]"`), `archive_ok` (frontmatter check), `recommendation` ∈ {`archive`, `keep`, `review`}.

- **FR9 — No auto `git mv`.** The script does not invoke `git mv` or modify files outside the report. The operator reads the report, makes per-file decisions, then authors the archive PR by hand.

- **FR10 — Closure.** Branch A or B success → `Closes #4042` in the operator-authored archive PR's body. Branch C → leave #4042 open, file follow-up, link both ways.

## Technical Requirements

- **TR1 — Script location (Branch B).** `scripts/learning-archive-candidates.sh`. Bash. Mirrors `scripts/learning-retrieval-bench.sh` location and shell choice. No new dependencies beyond what the bench already requires (`bash`, `jq`, `git`, `grep`, `awk`, `sed`).

- **TR2 — Input.** Reads sibling JSON output of the bench. Path resolution: prefer `knowledge-base/project/learnings-retrieval-bench-<latest>.json` (latest by lexical sort), fall back to flag `--bench-json <path>`. Exit 1 with clear message if no input found.

- **TR3 — Idempotency.** Re-running with the same input must produce byte-identical report output. Computations (age, grep-rank, inbound-link count) are derived from the git tree state and bench JSON, both reproducible.

- **TR4 — Self-test.** `--self-test` flag covers ≥5 cases via synthesized fixtures (per `cq-test-fixtures-synthesized-only`): (a) `cause=missing-frontmatter` correctly dropped, (b) `cause=slug-mismatch` correctly dropped, (c) `cause=content-shape` retained, (d) `archive: never` frontmatter excludes from pool, (e) grep-rank position-1 hit drops candidate.

- **TR5 — Cost.** Zero LLM calls. Pure shell + git. Per-run cost: $0. Wall time: < 30s for a 20-entry candidate list.

- **TR6 — Report location.** `knowledge-base/project/learnings-archive-candidates-<YYYY-MM-DD>.md`. Add `learnings-archive-candidates-*.md` to root `.gitignore` (the report is a transient triage artifact; the archive PR itself is the durable record).

## Acceptance Criteria

- **AC1 — Bench prerequisite.** Before evaluating any branch, verify the latest bench JSON exists and has `schema == 1` (per sibling spec AC5). If missing, exit 1 with "Run `bash scripts/learning-retrieval-bench.sh --confirm` first."

- **AC2 — Branch A demo.** When `worst_n.length ≤ 5`, the spec is satisfied by an operator-authored archive PR (no script). PR body must cite each archived path and the `cause` from the bench.

- **AC3 — Branch B AC (when script is built).** Script self-test passes. Running against the actual bench JSON produces a markdown report at the expected path. Report's `recommendation` column for any candidate with `grep_rank == 1` is `keep`. Report's `recommendation` for any `cause ∈ {missing-frontmatter, slug-mismatch}` is `review` (route to rewrites bucket) — explicitly not `archive`.

- **AC4 — Branch C AC.** When `worst_n.length == 20`, the action is: file follow-up issue against `scripts/learning-retrieval-bench.sh` to extend its AC5 schema with `r5_zero_count` (corpus-wide). Comment on #4042 linking the follow-up. Do not author any archival action until the bench is extended and re-run.

- **AC5 — Opt-out enforcement.** If a learning has `archive: never` frontmatter, the script (Branch B) and the operator (Branch A) must not include it in the archive recommendation. AC verified via TR4 self-test case (d).

- **AC6 — No auto-mv.** Grep `scripts/learning-archive-candidates.sh` (if built): zero occurrences of `git mv`, `mv `, `rm `, or destructive file operations. Confirmed via script review at PR time.

- **AC7 — Closure invariant.** PR title for the archive PR uses `Closes #4042` in the body (not title) per `wg-use-closes-n-in-pr-body-not-title-to`.

## Sharp Edges

- **The bench `worst_n` cap is 20.** A corpus of 841 files with R@5(heavy, kbsearch) = 0 could plausibly exceed 20. The spec's Branch C exists to prevent acting on a silently-truncated list. If the bench is re-run repeatedly without cap extension, archive candidates outside the top-20 silently never surface.
- **The grep-rank gate may over-exclude.** A learning whose title slug contains common words ("workflow", "session", "rule") may grep-match its own path AT rank 1 due to its own occurrence, but be effectively unfindable via meaningful query terms. The gate (FR6) is a conservative cut-off; the operator may override during PR authoring.
- **`synced_to:` cross-filings.** If file A is cross-filed at B and only A scores R@5=0, the archive script (Branch B) does not currently parse `synced_to[]`. Defer to operator triage; the bench's min-rank semantics may make this moot in practice (the cross-filing usually rescues the rank).
- **No cost to capture, real cost to revert.** Archived learnings are recoverable via `git mv`-from-archive. Re-deriving an institutional learning that gets archived and the original context drifts is more expensive. Per-file human sign-off (FR9) is the load-bearing safeguard, not git history.
