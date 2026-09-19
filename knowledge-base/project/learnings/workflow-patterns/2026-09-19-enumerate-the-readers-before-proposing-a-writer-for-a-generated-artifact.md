---
title: "Enumerate the readers before proposing a writer for a generated artifact"
module: Development Workflow
date: 2026-09-19
problem_type: workflow_issue
component: development_workflow
symptoms:
  - "Brainstorm for #8377 opened with three 'who regenerates INDEX.md on main' mechanisms before anyone had asked who reads INDEX.md"
  - "The line that guaranteed every INDEX.md merge conflict (`> Total files: N`) has zero readers outside the machinery that guards it"
  - "Two 'X reads this file' claims (GitHub landing page; web-platform input) were each falsified by a single grep"
root_cause: missing_workflow_step
resolution_type: workflow_improvement
severity: medium
tags: [brainstorm, generated-artifacts, kb-index, merge-conflicts, premise-validation, readers-before-writers]
category: workflow-patterns
synced_to: [brainstorm]
related_issues: [8377, 8116, 8151, 8370, 8177, 7935, 6109]
---

# Troubleshooting: Enumerate the readers before proposing a writer for a generated artifact

## Problem

Issue #8377 proposed "stop committing `knowledge-base/INDEX.md` on feature branches;
regenerate on `main` post-merge" to end the DIRTY livelock every open PR suffers on
every `main` advance. The brainstorm's first framing question inherited that shape and
offered the operator three *writer* mechanisms (per-merge push, debounced job, nightly
job) — each needing a GitHub-App bypass actor on the `CI Required` ruleset and each
adding a `main` advance that re-`BEHIND`s every open PR under the strict up-to-date
policy.

The operator asked the question the brainstorm had skipped: *"why do we need to
regenerate those? which parts do we need to regenerate?"* Answering it collapsed the
option space:

| Line class in `INDEX.md` | Readers | Conflict behaviour |
|---|---|---|
| rows (`[title](path)`) | `kb-search` Tier 1, `learnings-researcher` Step 0, `learning-retrieval-bench.sh` — all agent-side tooling in this repo | additive; conflict only on adjacent same-day inserts |
| `> Total files: N` header | **none** — only the merge driver, AC17 and their own tests | both sides always edit the same line → guaranteed conflict |
| `kb-tags.txt` / `kb-categories.txt` | `kb-search --tag/--category` validation | additive |

With no product or human consumer, the artifact is a cache of the tree and the correct
move is to stop committing it — the row ADR-210 had recorded as "coherent, deferred on
scope". Two further operator assertions ("INDEX.md is the GitHub landing page",
"INDEX.md is used by the webapp") were each checked and refuted in one command
(`git ls-tree main knowledge-base/ | grep -i readme` → none, nothing links to it;
`git grep -l INDEX.md -- apps | grep -v /test/` → one unrelated SQL comment).

## Environment

- Soleur repo, worktree `feat-kb-index-untrack`, brainstorm phase, 2026-09-19.
- `scripts/generate-kb-index.sh` regenerates all three files in 3.0 s on this host
  (7–11 s measured on slower hosts in `2026-09-08-i-grepped-the-config-for-a-gate-that-lives-in-a-test.md`).
- 42 of 71 first-parent `main` commits in the prior 7 days touched INDEX.md; the last
  10 diffs were exactly 2 lines each (one new row + the count header).

## Symptoms

- Brainstorm dialogue spent its first `AskUserQuestion` on cadence for a writer nobody
  had justified.
- Every conflict measurement cited in the issue (#8319: 7 syncs, #8321: 11, #8347: 3)
  traced to a header line with no reader.

## What Didn't Work

- **Starting from the issue's mechanism.** The issue was written from the writer's seat
  ("the hook regenerates it, so something must regenerate it on `main`"); inheriting that
  frame produced internally consistent options for the wrong problem.
- **Treating "X reads this" as context.** Both consumer claims came from the operator and
  sounded authoritative; each was a claim about the repo that the repo could answer.

## Session Errors

1. **Scratchpad directory absent** — `gh issue view > $SCRATCHPAD/8377-body.md` failed with
   `No such file or directory`. Recovery: `mkdir -p "$S"` and re-run.
   **Prevention:** `mkdir -p` the scratchpad before the first redirect into it; the
   system prompt describes it as usable, not as pre-created.
2. **Writers-before-readers framing** — offered "regen on main" cadences before
   enumerating readers. Recovery: operator's question; rebuilt the framing from the
   reader table above. **Prevention:** for any committed generated artifact, table
   `line class → readers → conflict behaviour` before proposing a writer (routed to the
   brainstorm skill's premise-validation section).
3. **"X reads this file" accepted provisionally** — landing-page and webapp claims were
   each folded into the next reply before the grep ran. Recovery: one `git ls-tree` /
   `git grep` per claim. **Prevention:** a consumer claim is a repo fact — grep the
   consumer's source (excluding `/test/` fixtures that use the name as an arbitrary
   string) before it bounds an option.
4. **`soleur:go` Step 0.0 / 0.5 / 0 all reported `plugin-root-unverified`** — neither
   `GROK_PLUGIN_ROOT` nor `CLAUDE_PLUGIN_ROOT` was set, so the readiness probe,
   cloud-detect and session-start `cleanup-merged` were skipped (the #7442 markers
   fired as designed). Recovery: proceeded on the bare `git rev-parse` fallback.
   **Prevention:** already tracked by the `SOLEUR_GIT_REPO_DIAG source=probe-unreachable`
   marker family; no new action.
5. **Self-correction leaked into operator-facing text** — an `AskUserQuestion` option
   description read "…~5-12 extra main advances/day instead of ~42/week per-merge…
   wait, per-merge is ~6/day". Recovery: none needed; the operator redirected the
   question. **Prevention:** compose option descriptions from settled numbers only;
   re-derive before, not inside, the prompt.
6. **The brainstorm commit reproduced the defect** — lefthook `generate-kb-index`
   regenerated and re-staged INDEX.md (`6659 files indexed`) on the branch that exists to
   stop that. Recovery: none; expected until FR1/FR4 land. **Prevention:** the feature
   itself; the spec's FR7 carries the one-time `git rm` transition for open branches.

## Solution

Reframed the brainstorm around artifact *kind*, confirmed with the operator, and folded
in the two sibling artifacts once their kinds were classified:

```text
kind                         example                         fix
cache of the tree            INDEX.md, kb-tags/categories    untrack; regenerate on demand
cache of gitignored data     rule-metrics.json (ADR-091)     untrack; regenerate on demand
product artifact             model.likec4.json               keep committed; regenerate on conflict
```

Artifacts: `knowledge-base/project/brainstorms/2026-09-19-kb-index-untrack-generated-artifacts-brainstorm.md`,
`knowledge-base/project/specs/feat-kb-index-untrack/spec.md`, draft PR #8384.

## Why This Works

A conflict is a property of a *line* and a *pair of writers*; a regeneration mechanism
is a cost paid for *readers*. Enumerating readers per line class shows which lines earn
a writer at all. When the only guaranteed-conflict line has no reader, the mechanism
debate (which cadence, which bypass actor) is moot — delete the line or the file.
The same table classifies sibling artifacts in seconds: a product consumer that cannot
regenerate the file keeps it committed; anything else is a cache.

## Prevention

- In brainstorm premise validation, when the feature description names a committed
  generated file: `git log -p -<n> -- <file> | grep '^[+-][^+-]'` to see which lines
  change per commit; `git grep -n '<basename>' -- ':!**/test/**' ':!**/*.test.*'` to
  list readers; then ask which reader depends on each conflict-bearing line.
- Treat operator-supplied consumer claims as claims in both directions — "nobody reads
  it" and "the webapp reads it" each get one grep.
- Check the governing ADR's rejected-alternatives table for the "don't commit it" row
  and whether it was rejected on merits or on scope.

## Related Issues

- #8377 (this brainstorm), #8116 / #8151 (option 2 shipped), #8370 (AC17 on the merge
  ref — closes with this), #8177 (stale branch index), #7935 / ADR-210 (the merge
  driver and its deferred "stop committing" challenge), #6109 (rule-metrics
  completeness).
- `knowledge-base/project/learnings/workflow-patterns/2026-06-04-kb-index-regen-bundles-stale-drift-prefer-surgical-edit.md`
- `knowledge-base/project/learnings/2026-07-22-no-consumer-claim-is-a-producer-consumer-contract-mismatch.md`
  (the mirror case: a "no consumer" claim that had two).
