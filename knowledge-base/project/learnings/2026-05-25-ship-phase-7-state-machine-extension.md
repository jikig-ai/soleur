---
title: 'ship Phase 7 poll loop extended for required-check failure, BEHIND saturation, and DIRTY exit'
date: 2026-05-25
category: workflow-adherence
tags: [ship, phase-7, poll, state-machine, required-checks, behind, dirty]
related:
  - 4303
  - 4377
  - 4387
related_rules: [hr-when-a-workflow-concludes-with-an, hr-exhaust-all-automated-options-before, hr-no-dashboard-eyeball-pull-data-yourself]
---

# ship Phase 7 poll loop extended for required-check failure, BEHIND saturation, and DIRTY exit

## What happened

PR #3984 (2026-05-18) added a BEHIND auto-sync handler to `/soleur:ship` Phase 7 capped at `MAX_BEHIND_SYNCS=3`. Two subsequent incidents showed the cap was reached on long-running PRs while origin/main kept churning, after which the loop fell through to the heartbeat path and timed out at 15 minutes with no operator-actionable signal:

- **PR #4303** (TR9 PR-4, merged 2026-05-22): mid-flight BEHIND cycle exhausted the 3-sync budget.
- **PR #4377** (TR9 PR-5, merged 2026-05-25 at 05:12 UTC): same pattern, required overnight operator prompts ("check on the PR") to drive merge forward.

The poll also had no handler for the symmetrical class — a required CI check failing while auto-merge sat queued. The loop heartbeated through `BLOCKED` for the full 15-minute budget; the operator saw "timeout" with no failed-check identification.

## The fix

Extended `plugins/soleur/skills/ship/SKILL.md` Phase 7 (and mirrored into the two sibling polling sites: `merge-pr/SKILL.md` §5.2, `product-roadmap/SKILL.md`) along three axes:

1. **Required-check-failure scan.** Fetch the repo's required-check name set ONCE at loop entry via `gh api 'repos/{owner}/{repo}/rules/branches/main'`. Each tick, intersect `gh pr checks --json name,bucket` failures (`bucket == "fail"`) with that set. On first intersection, exit with the failing check name + a `gh pr checks <number>` / `gh run view --log-failed` pointer.
2. **BEHIND cap raised to 6 with structured warning.** When `behind_syncs` reaches `MAX_BEHIND_SYNCS=6`, emit `BEHIND budget exhausted after 6 auto-syncs in ${elapsed}s. origin/main is moving faster than this PR's CI cycle. Recommendation: stop ship pipeline; merge during a quieter window.` exactly once, then fall through to heartbeat (the PR may still merge if main calms down).
3. **DIRTY exit.** Top-level branch (sibling to BEHIND) for `mergeStateStatus == DIRTY`: exit, dump `git diff --name-only --diff-filter=U` for the local conflict view, print a `git fetch origin && git merge origin/main` recovery pointer.

## Why this approach (vs. a new soleur:pr-watch skill)

The issue body proposed extracting the state machine into a new `soleur:pr-watch` skill. Rejected because:

1. **Total bash diff < 200 LoC.** A skill carries `~50 LoC of YAML frontmatter + description-budget cost + token cost on every session start`. The state machine fits inline in the three call sites; the duplication cost is < 100 lines.
2. **No invocation surface beyond the three sites.** Skills are valuable when reusable. The three current consumers all invoke from inside a parent skill that already owns the merge intent — extracting the state-machine as a separate skill adds an indirection layer with no parallel consumer.
3. **Description budget headroom.** Cumulative skill description word count is enforced at 1950 words by `plugins/soleur/test/components.test.ts` (the tokenizer is `desc.split(/\s+/).filter(Boolean).length` against YAML values only — the AGENTS.md `grep -h 'description:' | wc -w` form inflates counts by ~5 words per skill via YAML framing and is NOT the authoritative budget; see `knowledge-base/project/learnings/2026-04-19-skill-description-word-budget-tokenizer.md`). Adding a new skill description would consume the remaining headroom and force a sibling trim. In-place extension is zero description-budget cost.

The issue body also referenced a `ScheduleWakeup` primitive that does not exist in this codebase (grep returns zero hits in `plugins/`, `.claude/hooks/`, `apps/web-platform/`). The actual polling primitive is the **Monitor tool** + bash loop, which Phase 7 already uses.

## Synthesized test fixture

`plugins/soleur/test/ship-phase-7-poll-fixtures.sh` extracts the Phase 7 bash block from `ship/SKILL.md`, substitutes `<number>` with a test PR id, shadows `gh` / `git` / `sleep` with bash functions, and runs four scenarios:

1. **Clean MERGED on tick 3** — `gh pr view` returns `OPEN BLOCKED`, `OPEN CLEAN`, `MERGED CLEAN`. Loop exits with `MERGED CLEAN`.
2. **Required-check failure on tick 5** — `gh pr checks` returns `test` as failing on tick 5; required set = `["test", "e2e"]`. Loop exits with `required check 'test' FAILED`.
3. **BEHIND saturation** — `gh pr view` returns `OPEN BEHIND` for all ticks; mocked `git fetch`/`merge`/`push` succeed. Loop performs 6 syncs, emits `BEHIND budget exhausted after 6 auto-syncs`, heartbeats through tick 15.
4. **DIRTY on tick 2** — `gh pr view` returns `OPEN DIRTY` from tick 2. Loop exits with `DIRTY (merge conflict)`.

The fixture also runs `bash -n` against the extracted block to catch heredoc/syntax fragility before the next live `/ship` invocation.

## How to prevent this class going forward

When extending a state-driven poll loop, enumerate the **full mergeStateStatus enum coverage matrix** (BEHIND, BLOCKED, CLEAN, DIRTY, DRAFT, HAS_HOOKS, UNKNOWN, UNSTABLE) at plan time and decide per-state: exit / heartbeat / auto-recover. The original PR #3984 fix covered BEHIND but left BLOCKED-with-required-failure and DIRTY unhandled — both surfaced as 15-minute silent timeouts within four days. The matrix is a checklist; the failure modes are not surprising once you list them.

Each new exit branch should emit a single structured stderr line at the inflection point (not at the timeout) so the Monitor tool surfaces it as a notification immediately. "Timed out, last state was BEHIND" is a strict subset of "BEHIND budget exhausted after 6 auto-syncs at 6 minutes" — the latter is operator-actionable; the former requires log archaeology.

## Files changed

- `plugins/soleur/skills/ship/SKILL.md` — Phase 7 poll loop and surrounding prose
- `plugins/soleur/skills/merge-pr/SKILL.md` — §5.2 Poll for Merge (replaced naive `--json state` form with the full state machine)
- `plugins/soleur/skills/product-roadmap/SKILL.md` — roadmap-merge polling step (pointer to ship Phase 7 state machine)
- `plugins/soleur/test/ship-phase-7-poll-fixtures.sh` — new bash fixture (AC9)
- `knowledge-base/project/learnings/2026-05-25-ship-phase-7-state-machine-extension.md` — this file
