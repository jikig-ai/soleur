---
title: "A fix to a shared helper/substrate is incomplete until you grep for inline copies of the same operation"
date: 2026-06-02
category: best-practices
tags: [fix-completeness, blast-radius, env-var-inert-without-code, cron, multi-agent-review]
pr: 4770
issues: [4684, 4689]
---

# Learning: a shared-substrate fix must enumerate every inline copy before claiming the blast radius

## Problem

PR #4770 fixed cron ENOSPC (#4684/#4689): substrate crons `mkdtemp`'d their
git-clone workspace under `os.tmpdir()` (a 256 MB `/tmp` tmpfs in prod), so a
`--depth=1` clone of the ~100 MB soleur tree exhausted the tmpfs. The plan's
premise asserted "the other 21 substrate-based crons" all route through the
shared `_cron-claude-eval-substrate.ts` `setupEphemeralWorkspace`, so fixing that
one helper (+ wiring `-e CRON_WORKSPACE_ROOT=/workspaces` on the docker run
blocks) would cover them all.

That premise was **false**. Six crons — `cron-content-vendor-drift`,
`cron-content-publisher`, `cron-compound-promote`, `cron-rule-prune`,
`cron-strategy-review`, `cron-weekly-analytics` — carry their **own inline**
`mkdtemp(join(tmpdir(), …))` + `git clone` and never call the substrate helper.
They run in the same prod container (so the new env var was in their env) but
their code never read it, leaving all six on the 256 MB tmpfs with the identical
ENOSPC exposure. The PR's `Closes #4684/#4689` would have been a false close.

Three independent review agents (code-quality-analyst, pattern-recognition-
specialist, test-design-reviewer) converged on the gap; it was invisible to the
plan, to tsc, and to the 79/79-passing infra test that asserted the env var was
*present* on the docker run lines (presence of the env var gave false confidence
that all crons were protected — six ignored it).

## Solution

1. Grep the literal operation across the whole module dir, not the abstraction:
   `grep -rn "mkdtemp" server/inngest/functions/*.ts` surfaced all 6 inline
   copies the substrate-only mental model missed.
2. Move the fix primitive to the canonical shared module (`resolveCronWorkspaceRoot`
   + `warnIfCronWorkspaceLowOnDisk` → `_cron-shared.ts`, next to
   `buildAuthenticatedCloneUrl`, which all 7 clone paths already import — zero new
   import edges) and route every repo-cloning `mkdtemp` parent through it.
3. Distinguish the small-temp-file use from the repo-clone use: `cron-compound-promote`
   also `mkdtemp`s a few-KB `.patch` file under `tmpdir()` — correctly left on
   tmpfs (not a clone).

## Key Insight

**An env var / config flag is inert for any code path that does not read it.**
When a fix is "set X in the environment + make the shared helper consume X," the
fix only covers callers of the shared helper. Before claiming the blast radius is
closed, grep for the **literal operation** the symptom names (here `mkdtemp` +
`clone`), not the abstraction you assume everyone uses — shared substrates are
frequently NOT universally adopted; handlers carry inline copies that predate or
bypass the helper. The plan's "all N use the substrate" enumeration is a
hypothesis; the grep is the work-list (see [[2026-05-18-sweep-class-fixes-grep-enumerated-not-intuited]]).

This is the config-layer sibling of [[2026-05-31-worm-bypass-fix-must-enumerate-all-mechanisms-not-just-the-reported-one]]:
the reported symptom (one cron) is a lower bound on the blast radius; the fix
must enumerate every mechanism/caller that can produce the same failure.

Corollary: a test asserting a config value is *present* (the env var on the
docker run line) does not prove the code *consumes* it everywhere — it can give
false "all covered" confidence. Pair presence-assertions with code-path coverage.

## Session Errors

1. **`set -uo pipefail` tripped `ZSH_VERSION: unbound variable`** in the agent's
   shell snapshot, masking a `has_source` grep during review classification.
   Recovery: derived the change-class from the file list directly. **Prevention:**
   avoid bare `set -u` in inline review-classification predicates run by the
   non-interactive Bash tool (its sourced profile references `ZSH_VERSION`), or
   guard with `${ZSH_VERSION:-}`.
2. **Agent type `soleur:engineering:review:git-history-analyzer` not found** — it
   lives under the `research` namespace (`soleur:engineering:research:git-history-analyzer`),
   not `review`. Recovery: re-spawned with the correct namespace. **Prevention:**
   the review skill's conditional-agent list names it bare as
   `git-history-analyzer`; the actual `subagent_type` is in `research/`.
3. **Three Edit-before-Read failures** (cron-content-generator/roadmap-review/
   competitive-analysis) — viewed via `sed`/`grep`, not the Read tool. Recovery:
   Read then Edit. **Prevention:** already covered by
   `hr-always-read-a-file-before-editing-it`; `sed`/`grep` viewing does not
   satisfy the harness's read-tracking — use the Read tool before Edit.

## Tags
category: best-practices
module: apps/web-platform/server/inngest/functions
