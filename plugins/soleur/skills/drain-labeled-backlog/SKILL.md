---
name: drain-labeled-backlog
description: "This skill should be used when draining a labeled issue backlog (deferred-scope-out, code-review, type/security) in one cleanup PR. Groups by code area and delegates to /soleur:one-shot."
---

# Drain Labeled Backlog

Drain a labeled-issue backlog by batching issues that touch the same code area into a single focused refactor PR. Defaults to `deferred-scope-out` (the original use case, inspired by PR #2486, which closed `#2467 + #2468 + #2469` in one cleanup). Any other label works via `--label` — e.g., `code-review` drains unresolved review findings, `type/security` drains the security backlog.

## When to use

- A labeled backlog has grown and needs a scheduled drain — `deferred-scope-out` (the original use case), `code-review` (unresolved review findings), `type/security` (open security issues), or any label validated by `gh label list`.
- Multiple open issues carrying the target label reference the same top-level directory (e.g., `apps/web-platform`) and are safe to batch.
- You want one PR to close 3+ issues instead of N separate PRs.

Use `/soleur:review` to file new scope-outs. Use this skill to close existing labeled issues.

## Prerequisites

- `gh` authenticated, `jq` and `python3` available.
- Current directory is a git worktree (not the bare root).
- At least one cluster of `min-cluster-size` open issues carrying the target label.

## Arguments

<arguments> #$ARGUMENTS </arguments>

Optional flags (any subset):

- `--label <name>` — which GitHub label drives the backlog query. Default: `deferred-scope-out`. Pass `code-review` to drain unresolved review findings; pass any other label for a custom drain. Validated against `gh label list` before querying (rule `cq-gh-issue-label-verify-name`).
- `--milestone "<title>"` — which milestone to drain. Default: `Post-MVP / Later` (where 15+ of the open scope-outs live at plan time). Takes the milestone **title**, never a numeric ID (rule `cq-gh-issue-create-milestone-takes-title`).
- `--top-n N` — how many clusters to consider. Default: `1`.
- `--min-cluster-size M` — minimum issues in a cluster before the skill will pick it. Default: `3`.
- `--dry-run` — print the selected cluster and the one-shot scope argument that would be built, without delegating.

## Workflow

### 1. Prerequisites check

Verify `gh`, `jq`, `python3` are on PATH. If any is missing, abort with installation guidance. Verify the current directory is a git repository with `git -C . rev-parse --git-dir >/dev/null 2>&1` (rule `hr-before-running-git-commands-on-a`).

### 2. Resolve milestone

```bash
MILESTONE="${ARG_MILESTONE:-Post-MVP / Later}"
```

Default is `Post-MVP / Later`: plan-time verification showed 15+ of the 22 open `deferred-scope-out` issues live there. Defaulting to the current phase milestone would return an empty cluster set on first run and make the skill appear broken.

### 3. Query and group issues

Delegate to the helper [group-by-area.sh](./scripts/group-by-area.sh):

```bash
bash plugins/soleur/skills/drain-labeled-backlog/scripts/group-by-area.sh \
  --label "${LABEL:-deferred-scope-out}" \
  --milestone "$MILESTONE" \
  --top-n "${N:-1}" \
  --min-cluster-size "${MIN_CLUSTER:-3}"
```

The helper:

- Validates the label exists via `gh label list` (rule `cq-gh-issue-label-verify-name`) and the milestone title exists via `gh api ...milestones` + `grep -Fxq` before querying.
- Uses two-stage piping (`gh --json ... | jq`), never `gh --jq` with `--arg` (learning `2026-04-15-gh-jq-does-not-forward-arg-to-jq`).
- Parses each issue body for file paths matching `(ts|tsx|js|jsx|py|rb|go|md|sh|yml|yaml|sql|tf|njk)` extensions via a non-capturing regex.
- Assigns each issue to an **area** = top two path segments (e.g., `apps/web-platform`, `plugins/soleur`) of its most-referenced file path.
- Reports ALL clusters sorted by size desc; does not pre-select one.
- Exits 0 with "No cleanup cluster available" if no area clears the floor.

### 4. Pick a cluster

- **Interactive:** display the top cluster(s) and confirm before proceeding. Allow the user to override with `--area <name>` or pick a different cluster from the listed output.
- **Headless** (pipeline mode — arguments include a path or `--headless`): auto-pick the first cluster (largest) whose `count >= min-cluster-size`. If none meets the floor, the helper already printed "No cleanup cluster available"; exit 0 — do NOT open a low-value PR.

### 5. Build the one-shot scope argument

For the picked cluster, compose a scope string the `one-shot` skill can consume directly. Mention the originating label so the downstream plan frames the work correctly (e.g., "deferred-scope-out backlog" vs. "code-review findings"):

```text
Drain the <label> backlog for code area <area> by closing
#<A> + #<B> + #<C> in a single focused refactor PR. Each issue names
specific files and proposed fixes; fold them all into one change.

Issues:
  - #<A>: <title>
    Files: <files parsed from body>
    Fix: <proposed-fix section from body>
  - #<B>: ...
  - #<C>: ...

PR body MUST include `Closes #<A>`, `Closes #<B>`, `Closes #<C>`.
Reference PR #2486 as the pattern — one PR, three closures.
```

Pull `## Problem`, `## Proposed Fix`, and `Location:` / file paths from each issue body via `gh issue view <N> --json body`.

### 6. Delegate to one-shot

Use the Skill tool: `skill: soleur:one-shot`, args: `<scope argument built above>`.

`/soleur:one-shot` handles worktree creation, plan, deepen, work, review, QA, compound, and ship. This skill does NOT run any lifecycle phases itself — it only assembles scope.

### 7. Report backlog delta

After `one-shot` returns (PR merged), re-query the milestone using the same label:

```bash
gh issue list --label "${LABEL:-deferred-scope-out}" --state open \
  --milestone "$MILESTONE" --json number --jq 'length'
```

Report: `Before: X, After: Y, Closed: Z` and the per-area drain.

## Post-merge follow-up — Scheduling

The `/soleur:schedule` skill accepts any soleur skill as `--skill <name>` and generates a standalone `.github/workflows/scheduled-<name>.yml`. After merging the PR that ships this skill, schedule a weekly cleanup:

```text
/soleur:schedule create --name weekly-deferred-scope-out-drain \
  --skill drain-labeled-backlog --cron "0 14 * * 1" --model claude-sonnet-4-6
```

This turns the skill from a manual cadence tool into a programmatic backlog opener. Tracked as a follow-up issue rather than bundled into this skill, so the skill lands clean.

## Pipeline detection

If `$ARGUMENTS` contains a `RETURN CONTRACT` section (i.e., this skill is being driven by another skill), run headless:

- Skip interactive cluster confirmation — auto-pick the first cluster meeting the floor.
- Skip `--dry-run` prompts.

Follows the same pattern as `plan`, `review`, and `ship` skills.

## Sharp edges

- The helper skips issues whose bodies name zero file paths. That is intentional — area grouping requires at least one path. If an issue has no paths but belongs to a cluster thematically, add a `Location:` line to its body and re-run.
- Sub-grouping by second-level directory is NOT implemented (YAGNI). Current backlogs never exceed 10 issues in a single top-level area. If that changes, track as a follow-up issue before adding the branch; don't build for cases that don't exist.
- `--milestone` takes the title literally (quote it). A numeric ID fails with `milestone 'N' not found` (rule `cq-gh-issue-create-milestone-takes-title`).
- Rule `rf-review-finding-default-fix-inline` governs the opposite direction (new findings default to fix-inline); this skill drains existing scope-outs. The two rules are complementary.
- When writing a data-reshape shell script that fetches JSON and groups it, default to a single pure-jq pipeline before reaching for python/awk. Multi-language serialization round-trips add dependencies, silent-fallback error paths, and ~2x the LOC without reshape capability jq already provides.
- `jq scan(...)` returns the **captured group** when the regex contains a capture, otherwise the full match. Alternations inside `scan` MUST be non-capturing: `(?:ts|tsx|js)` not `(ts|tsx|js)`. Otherwise `scan("[A-Za-z_./\\-]+\\.(?:ts|js)\\b")` returns full paths, whereas the capturing form would return just the extension.
- When binding `as` against a **multi-value** jq source (e.g., `.[] | select(...)`), the downstream expression runs once per yielded value, producing multiple top-level JSON outputs. This breaks callers that do `$(jq '.field' <<<"$VAR")` under `[[ -eq 0 ]]`. Collect into an array first: `[ .[] | select(...) ] as $meets | { ... }`.
- Sub-agent confirmation gates (like the second-reviewer gate in `review/SKILL.md`) need a **mechanical first-line output contract** (`CONCUR` / `DISSENT: <reason>`), not free-form prose interpretation. Treat anything other than `CONCUR` as `DISSENT` to fail-safe toward fix-inline.
- Per-issue "top path" ranking is **qualified-over-bare, deepest-first, frequency tie-break**. Review bodies typically cite one fully-qualified path (`apps/web-platform/components/chat/chat-input.tsx:107-127`) and then shorthand the rest (`chat-input.tsx:17-19, 58, 120-124`). Ranking by frequency alone lets shorthand outvote the qualified citation and produces singleton clusters keyed by bare filename. Ranking by depth alone lets a shallow shorthand `server/ws-handler.ts` beat a deep `apps/web-platform/server/rate-limiter.ts`. The combined rule handles both. Regression-tested in `shorthand-refs.json` (T8) and `mixed-depth.json` (T9).
- When the top cluster has **≥7 issues from ≥3 unrelated source PRs**, operator sub-selection beats "pick top cluster, delegate whole thing". The natural coherence heuristic is **originating review PR** — three scope-outs filed from the same review (same `Ref #NNNN` in their bodies) are almost always tight siblings, regardless of which subdirectory each path lives under. First dogfood run (PR #2499) hit this at `apps/web-platform` (9 issues spanning kb/chat/billing/analytics); operator read bodies and delegated a coherent 3-issue subset from the same originating review. See `knowledge-base/project/learnings/2026-04-17-cleanup-scope-outs-sub-cluster-selection.md`.

## Test

Unit tests live at [drain-labeled-backlog.test.sh](../../test/drain-labeled-backlog.test.sh). Run them with:

```bash
bash plugins/soleur/test/drain-labeled-backlog.test.sh
```

Covers: clustered fixtures, dispersed fixtures (no cluster), empty fixtures, JSON output shape, and sort order.
