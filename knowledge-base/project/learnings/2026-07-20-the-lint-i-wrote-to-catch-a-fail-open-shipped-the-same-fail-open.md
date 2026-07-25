---
title: "The lint I wrote to catch a fail-open shipped the same fail-open"
date: 2026-07-20
category: best-practices
tags: [guards, mutation-testing, fail-open, scope, gh-cli, review]
issues: [6786, 6793, 6608]
---

# The lint I wrote to catch a fail-open shipped the same fail-open

## Problem

Issue #6786 fixed a collision-gate probe that returned zero rows for every input — a guard
that had never fired. The fix added a lint asserting every `gh pr|issue list --search` in the
skills tree carries an explicit `--state`.

**The lint shipped with the defect class it was written to catch.** Its extraction regex used
`` [^`]* ``, which spans newlines. Inside a ```` ```fence ```` the capture therefore ran from
the command to the *closing fence*, swallowing every following line into one string — so a
`--state` belonging to a **different command** satisfied the check and laundered its stateless
neighbour. Reproduced first try:

```
fence containing:  gh pr list --search "#1 in:body is:merged"   <- offender
                   gh issue list --state open --label foo       <- unrelated
offenders detected: 0
```

Four review agents converged on it independently. It is the same block-scoping shape the repo
already documents for `indexOf`/`slice`, in regex form — `` [^`]* `` is a delimiter-pairing scan
with no notion of the boundary it is crossing.

## Solution

Line-bounded, fence-aware extraction: one entry per command, `` [^`\n]* `` so a capture can
never cross a line, with an explicit fence-state flag used to assert both structural classes
stay represented.

Three further gaps surfaced from the same root — **the guard's scope was drawn around where I
had already looked**:

- Scoping to `skills/*/SKILL.md` could not see `skills/review/references/review-todo-structure.md`,
  whose dedupe probe carried the identical defect. Widened to `skills/**/*.md`.
- `.openhands/hooks/pre-merge-rebase.sh` had silently drifted from its `.claude` twin, missing
  both `--state all` and an exact-phrase fix the twin had carried since #2186. Outside
  `plugins/` entirely, so no glob widening would have found it — only a class-indexed sweep did.
- The lint checked *presence* of `--state`, so the defect written **explicitly**
  (`--search "… is:merged" --state open`) passed. Now rejected as a query/flag contradiction.

## Key Insight

**A guard's blind spot is shaped like the search that found the bug.** I enumerated offenders
with a grep requiring `--search` adjacent to `list`; two of four real offenders put `--label`
between them and were invisible. I then scoped the lint to the directory those four lived in,
which hid a fifth. Each narrowing felt like precision and was actually a copy of my own
sampling bias. The corrective is to index the sweep by the **defect class** (what shape can
fail?) and let that pick the scope — never by the set you already found.

## Mutation batteries: two ways to record a result that never happened

Both bit in this session, and both produce output indistinguishable from a real green.

1. **A sandbox whose baseline is already red.** My first battery copied only `plugins/` into a
   temp dir; path resolution broke and the un-mutated baseline was `0 pass / 1 fail`. Every
   mutation "result" after that was noise. **Always run the un-mutated baseline in the same
   harness first and require it GREEN** before any mutation result counts.

2. **A mutation that changes the file without changing the construct.** My `M4 glob narrowed`
   perl replaced the *first* occurrence of the glob string — which was in a **comment** three
   lines above the real `new Glob(...)` call. The file changed, so a `diff`-based "did it land?"
   check passed, and the surviving-mutant verdict was fabricated. **Verify the intended target
   changed**: assert the old string occurs exactly once, or grep the specific construct
   post-edit. `diff -q` proves *something* changed, not that the *right* thing did.

This is the sibling of the documented "a `sed` that silently fails reports the baseline count"
trap — same failure surface, opposite cause. There the edit didn't happen; here it happened in
the wrong place. Both report a number that reads like evidence.

Corrected battery (M1 restore-old-regex, M3 fence-flag, M4 glob-narrowing all RED). Two
mutations survive and are named rather than hidden: the corpus assertions compare `[]` to `[]`
while the corpus is clean, so **the synthesized fixtures carry all discriminating power** — which
is precisely why a clean-corpus lint needs permanent negative controls, not just a live scan.

## Also: I reported a wrong root cause with confidence

I told the operator GitHub strips the leading `#`, and filed that into #6786's body. The
planning subagent falsified it (`gh search prs` returns byte-identical results with and without
the `#`). The real mechanism is `gh pr list` appending its default `--state open` unless it
detects an in-query state qualifier, which a leading `#` defeats.

The fix direction survived, but the *invariant* changed: a `#`-prefix lint would have guarded
the wrong property entirely. **A plausible mechanism that predicts the observed symptom is not
a verified mechanism** — the discriminating experiment here cost one command (`gh search prs`
with and without the `#`) and I ran it only after being contradicted. Issue #6786 now carries a
correction comment so the wrong explanation does not propagate.

## Session Errors

- **Wrong root cause reported and filed.** — Recovery: planning subagent's premise-validation
  falsified it; corrected via a comment on #6786. **Prevention:** before asserting a mechanism,
  name the experiment that would distinguish it from the nearest alternative, and run that one.
- **Offender enumeration missed 2 of 4** (grep required `--search` adjacent to `list`). —
  Recovery: the lint's own regex re-derived the population. **Prevention:** derive the work-list
  from the class predicate, not from a convenience grep.
- **The lint carried the defect class it guards.** — Recovery: 4-agent convergence at review,
  reproduced, rewritten line-bounded. **Prevention:** for any new guard, ask "what input makes
  this report clean while the thing it protects is broken?" before writing the assertion.
- **Lint scoped to `SKILL.md`, hiding a 5th offender.** — Recovery: widened glob surfaced it
  immediately; added a floor test pinning the widening. **Prevention:** scope by defect class.
- **`.openhands` hook mirror never checked.** — Recovery: agent-native review found it.
  **Prevention:** when fixing a file with a known twin, diff the twins.
- **Mutation battery #1 invalid (red baseline).** — Recovery: rerun in-place with a pristine
  backup. **Prevention:** require a GREEN un-mutated baseline in the same harness.
- **Mutation M4 mutated a comment, not the code.** — Recovery: re-ran with exact-target
  verification (`count == 1`). **Prevention:** verify the construct changed, not just the file.
- **12 suite failures were sibling-worktree contention.** — Recovery: isolated re-run 72/0 on
  both this branch and clean `main`; confirmed a parallel session's `test-all.sh`.
  **Prevention:** already documented in `work/SKILL.md`; `ps -ef` before diagnosing.
- **markdownlint AC13 unmet** (17 pre-existing violations). — Recovery: measured baseline
  17→17, introduced set empty; recorded as no-regression. **Prevention:** ACs that assert a
  tool is "clean" should first confirm the tool is CI-gated — this one is not.
- **Assumed the REST search rate limit applied** to the probe. — Recovery: perf-oracle measured
  it on the GraphQL bucket, and `-L 100` costs the same as `-L 30`. **Prevention:** measure the
  bucket before reasoning about a limit.
