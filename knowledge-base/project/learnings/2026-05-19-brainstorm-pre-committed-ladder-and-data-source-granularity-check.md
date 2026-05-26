---
title: 'Brainstorm: Pre-committed action ladder + data-source granularity check'
date: 2026-05-19
category: workflow-patterns
tags: [brainstorm, pre, committed, ladder, data, source, granularity, check]
description: Two compounding patterns surfaced in the
metadata: {'type': 'workflow-patterns', 'applies_to': 'brainstorm, plan, premise-validation', 'surfaced_in': ['#4042 (learnings-decay reframe via R@K from #4043)', '#4043 (retrieval-bench one-shot reshape)']}
name: brainstorm-pre-committed-ladder-and-data-source-granularity-check
---

# Brainstorm: Pre-committed action ladder + data-source granularity check

## Pattern 1 — Data-source granularity probe (10 seconds, saves multi-leader spawn)

When an issue body proposes a mechanism keyed on "read `<file>` for per-X counts" (e.g., "read `rule-metrics.json` for per-learning hit counts"), the cheapest premise check is to inspect the file's actual entity granularity, not its existence.

The existence probe (`ls path/to/file`) is necessary but insufficient — a file present on `main` can still be the wrong substrate for the proposed query. The granularity probe is:

```bash
git show main:<path> | jq 'keys, (.rules // .entries // [])[0]'
```

For `rule-metrics.json`, this returns top-level keys `[generated_at, rules, schema, summary]` and a sample entry shaped `{id: "cm-challenge-reasoning-instead-of", section: "Communication", hit_count: 0, ...}`. The `id` field is an AGENTS.md rule slug, not a file path. The aggregator producing this file consumes `AGENTS.md` rule IDs + `.claude/.rule-incidents.jsonl` — it has no learning-corpus consumer. The proposed mechanism in the issue body cannot work as written.

Caught at premise probe (Phase 1.0.5), cost: 10 seconds. Missed → Phase 0.5 leader fan-out spawns CTO/CPO/COO assessments on a wrong premise; mid-assessment reframe forces re-prompt and re-spawn. Estimated cost of the miss: 3–5 minutes of parallel agent compute + the framing already committed to prose by the orchestrator.

**Rule shape:** When the issue body or feature description names a JSON/aggregator file as the data source for a per-X query (`per-learning`, `per-user`, `per-tenant`, `per-rule`, `per-skill`), one of the Phase 1.1 research bullets MUST verify the actual entity granularity via `jq 'keys'` + sample-entry inspection — NOT just `ls` existence. Document the granularity as a finding before any leader spawn.

## Pattern 2 — Pre-committed action ladder (second occurrence same-day)

When input data won't exist until an operator explicitly runs a one-shot script (or until a telemetry window opens), the brainstorm output should be a **decision document with branches keyed on the eventual data shape**, not a script built against a hypothetical distribution.

Concretely:

| Sibling brainstorm (#4043 → PR #4045) | Today's brainstorm (#4042) | Pattern |
|---|---|---|
| Bench produces R@5; thresholds 0.7 / 0.4 | Bench's `worst_n` produces candidate list; thresholds `length ≤ 5` / `length ∈ [6, 20]` / `length == 20` | Branches keyed on **shape of eventual data** |
| Action per bucket: vindicate / surface-rewrites / reopen-rag | Action per branch: inline triage / build enrichment script / extend bench first | Each branch has a pre-committed concrete action |
| Pre-commit FIRST, run bench SECOND, act THIRD | Identical sequence | Sequence is the rule |

The strength of this pattern over plain YAGNI: YAGNI says "don't build what you don't need yet." The pre-committed ladder is stronger — it says "**commit the response curve before the data arrives so the operator does not rationalize the threshold after seeing the number.**" Threshold-after-number is the failure mode of "we'll decide when we see what comes back" framings; the operator anchors to whatever the data says is plausible.

Two occurrences same-day (2026-05-19) on adjacent issues (#4043, #4042) is the second data point. After a third independent occurrence, this pattern is ripe for promotion to a Brainstorm-skill workflow gate (e.g., "When the proposed input data does not exist yet, the brainstorm output must be a pre-committed ladder, not a script.")

## Pattern 3 — Auto-archive proposals default to candidate-list-with-rationale, not `git mv` PR

CTO's reshape during the #4042 brainstorm generalizes:

> "Any auto-archive proposal where reversibility cost > computation cost should default to 'list with rationale + human sign-off' not 'PR with proposed mutations'."

The original issue framing was "draft PR with `git mv` moves to archive/." This sounds reversible (git history preserves moves) but inverts the cost balance: re-deriving an institutional learning whose original context drifted is far more expensive than reading a markdown report and authoring the PR by hand. The cheap action is the irreversible-feeling one (read the rationale, decide); the expensive action is the auto-mutation (recover from a false-positive archive when nobody noticed because the draft PR got rubber-stamped).

Applies to: log rotation, branch cleanup, issue auto-close, dependency removal, dead-code elimination. The default for any "auto-archive on heuristic" proposal should be:

1. Heuristic emits a **report** (markdown + per-candidate rationale).
2. Human triages the report, makes per-candidate decisions.
3. Human authors the mutation PR.

NOT:

1. Heuristic emits a draft PR with proposed mutations.
2. Human reviews the PR and merges or rejects.

The two look equivalent on paper. They differ on the asymmetry: false-positive mutations in a draft PR can survive review by attention drift; false-positive items in a markdown report require the human to actively author the next step, exposing each decision.

## Session Errors

- **Bare-repo CWD file-existence false negative** — `ls knowledge-base/project/rule-metrics.json` from `/home/jean/git-repositories/jikig-ai/soleur` (bare-repo root) returned "No such file" because bare repositories have no working tree. The file does exist on `main`. Brief misread; corrected via `git show main:`. **Prevention:** when probing file existence from the bare-repo CWD (no `.worktrees/` in `pwd`), use `git show main:<path>` for existence and `git show main:<path> | jq` for content shape. Existing rule `hr-when-in-a-worktree-never-read-from-bare` covers the inverse direction (worktrees reading from bare); this is the symmetric case worth a Sharp Edges entry in the brainstorm skill.

- **Ambiguous `#3883` reference** — user wrote "Do 1. and #3883 as #4043 was done in a separate session." `#3883` is the unrelated tenant-isolation PR-D; likely typo for `#3683` (rule-retirement-via-telemetry sibling). Treated as typo with the assumption surfaced explicitly. **Prevention:** when a user message references a number that doesn't fit the topical context, run `gh pr view N`, `gh issue view N`, AND a `gh issue list --search` against the sibling number bracket (±200) before assuming typo. I did the first two checks but only mentally enumerated sibling candidates — a single `gh issue list --search "rule retirement OR learnings decay"` would have made the typo hypothesis falsifiable.
