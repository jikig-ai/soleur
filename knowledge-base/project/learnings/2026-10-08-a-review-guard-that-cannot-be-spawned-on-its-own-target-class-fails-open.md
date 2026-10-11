---
title: "A review guard that cannot be spawned on its own target class fails open"
date: 2026-10-08
type: learning
related:
  - knowledge-base/project/learnings/2026-09-19-i-simulated-the-regex-and-segmented-the-pipeline-by-eye.md
  - plugins/soleur/skills/review/SKILL.md
  - plugins/soleur/skills/review/workflows/review.workflow.js
tags: [review, guard-coverage, test-pyramid, spawn-triggers]
---

# Learning: a review guard that cannot be spawned on its own target class fails open

## Problem

PR #9766 added a `## Pyramid & Fast-Feedback Check` to the `test-design-reviewer` agent
whose only FAIL verdict targets *new e2e-layer tests*. Three independent review seats
(agent-native, pattern-recognition, and the structural-enumeration map) found the same
defect in different form: the canonical file class the FAIL rule exists for —
`*.e2e.*` files under `e2e/` directories — matched **none** of the seat's spawn
predicates. `review/SKILL.md`'s "When to run test review agent" list, `review.workflow.js`'s
`hasTests` regex + schema description + classifier prompt, and `fix-round-seats.sh`'s
parity-pinned `TEST_RE` all enumerated `*.test.*`, `*.spec.*`, `test_*.py`,
`__tests__/`/`spec/`/`test/` — no `e2e`. A PR adding only an unjustified slow
`apps/web-platform/e2e/foo.e2e.ts` — the exact motivating case — could never reach the
seat that would FAIL it.

## Solution

The enumeration seat's map ordered reachability defects **before** verdict defects —
spawn coverage is the first conjunction in every guard's assembly. Fixes shipped in the
same PR: e2e conventions added to all five trigger surfaces (SKILL.md list, `hasTests`
regex, schema description, classifier prompt, `TEST_RE`), kept byte-identical where
`review-tier-parity.test.ts` pins them; a framework-import clause added so content
signals (not only path globs) can admit the seat; and a drift pin asserting the e2e
conventions stay in the trigger list.

## Key Insight

When adding a verdict rule for a file class, enumerate reachability first: seat-spawn
predicates → diff-granularity (adds vs modifies) → classifier vocabulary → verdict arm.
Every stage is a conjunct where the artifact can silently escape — a perfectly-specified
FAIL rule behind an incomplete trigger list is indistinguishable from the guard not
existing. Three seats found the same window independently; the enumeration seat's map is
what made "the largest window" legible instead of three anecdotes.

Companion lesson (same PR): presence-level drift pins (`grep -q <token>`) verify
vocabulary, not semantics — a `FAIL → WARN` softening kept all pins green until the
suite anchored the rule's text shape (`pyramid-justified: <reason>` definition, the
FAIL-rule line, per-block awk coverage). Pin the rule, not the keyword.

## Session Errors

- `gh issue create` filing-guard refusals ×2 (missing `--milestone`, then filing exit) — Recovery: re-filed #9771 with both flags — **Prevention:** the guard names the missing flag in its refusal; read the full refusal text before retrying.
- `lint-guard-contract.py` rejected numbered-list field markers — Recovery: reformatted to line-start `**Property.**` markers — **Prevention:** copy the field-marker shape from a lint-passing plan, not memory.
- Deepen self-check rejected multi-word `discoverability_test.expected_output` — Recovery: single-token value — **Prevention:** schema treats multi-word values as prose.
- No Task/Workflow spawn on Devin CLI — Recovery: inline passes recorded in the plan — **Prevention:** documented harness limitation (#8160); disclose inline execution rather than implying independent agents.
- Three background fan-out subagents died on connection errors — Recovery: inspected tree for partial work, resumed/completed inline — **Prevention:** resume dead agents rather than respawning (review Gate 2b convention); check for partial diffs first.
- `Closes #N` placed in PR title — Recovery: moved to own body line — **Prevention:** `wg-use-closes-n-in-pr-body-not-title-to` — the keyword triggers anywhere; keep it out of the title by construction.
- `hasTests` regex updated in one of two parity-pinned copies — Recovery: `review-tier-parity.test.ts` red, updated `TEST_RE` — **Prevention:** when a regex has a pinned twin, grep for the pattern before committing the first copy.
- `MIN_ASSERTIONS` guessed 48 vs actual 47 — Recovery: set to measured count — **Prevention:** the floor is set AT the running count — count, don't estimate.
- Three new pin-regex bugs on first suite run — Recovery: suite output named each — **Prevention:** write pin patterns against actual file text and run before committing.
- Awk per-block check lacked `## ` boundary reset — Recovery: own M12 mutation probe stayed green, exposed it — **Prevention:** mutation-test every new assertion, including the "keeps-count" evasion shape.
- A second `### Pyramid` heading in `## Output Format` would have broken the `^### Pyramid` count pin — Recovery: emitted the reference as a bold line instead — **Prevention:** when a heading level is a pin's anchor, adding a same-level heading IS a semantic change; check anchor counts before inserting.
- `tasks.md` quoted pre-trim measurement (2874w) — Recovery: fix-round seats re-measured (2852w) — **Prevention:** re-measure at write time, not at first measurement.
- `test-all.sh` capacity-contended by sibling worktree — Recovery: `--capacity` verdict read first; relied on targeted suites — **Prevention:** the #9505 learning already prescribes this; keep reading the verdict before queuing.

## Tags

review, guard-coverage, spawn-triggers, test-pyramid, drift-pins, structural-enumeration
