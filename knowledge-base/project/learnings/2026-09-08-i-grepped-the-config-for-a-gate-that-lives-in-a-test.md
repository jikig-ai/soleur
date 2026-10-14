---
title: "I grepped the config for a gate that lives in a test"
date: 2026-09-08
category: workflow-patterns
issue: 7935
pr: 7938
tags: [guards, verification-grep, grep-scoping, ci, test-discovery, tooling-traps, review]
---

# I grepped the config for a gate that lives in a test

## Problem

PR #7938 adds a git merge driver for `knowledge-base/INDEX.md`. Three of its files
argue that two silent-corruption modes are **loud** rather than silent, and all
three name the same speaker: `scripts/generate-kb-index.sh --check`.

Reviewing my own branch, I set out to verify that claim the obvious way:

```bash
grep -rn -- '--check' .github/workflows/ lefthook.yml scripts/test-all.sh
```

Nothing. No workflow step, no hook, no runner line. I concluded the claim was
false — that the guard had no caller, that both failure modes were in fact silent,
and that AC3 ("make the unregistered case fail loudly") rested on a gate that did
not exist.

So I wrote a new suite. `plugins/soleur/test/kb-index-freshness.test.sh`: seven
assertions, a real-corpus `--check`, per-artifact discrimination cases, a
does-it-repair-what-it-reports case, an assertion-helper positive control. It ran
green on the first try.

Then I went to correct the "false" prose, opened
`plugins/soleur/test/kb-index-merge-driver.test.sh`, and found this at line 430:

```
=== AC17: the COMMITTED artifacts are fresh — the guard's only real-tree caller ===
```

The gate existed. It had existed for eleven commits. Its own comment says it is
"THE WIRING, NOT A NICETY". Every case I had just written was already covered:
`C3`/`C4`/`C5` in `kb-index-check-guard-mutation.test.sh` prove `--check` compares
each of the three artifacts; `C6` proves it does not regenerate over what it
inspects; `C1`/`C2`/`C8` prove its exit status is a measurement rather than a
constant. My suite was a second real-corpus generation — 7-11 s — added to every
CI run to buy nothing.

## Root cause

**In this repository a CI gate can have zero representation in any configuration
file.** `scripts/test-all.sh` discovers suites through `SUITE_GLOBS`
(`plugins/soleur/test/*.test.sh` among them), and CI runs `test-all.sh` by group.
So the full chain from "a workflow runs" to "this specific command executes
against the real tree" is:

```
.github/workflows/ci.yml (test-scripts)
  -> scripts/test-all.sh, TEST_GROUP=scripts
    -> SUITE_GLOBS glob match
      -> plugins/soleur/test/kb-index-merge-driver.test.sh
        -> the AC17 case
          -> bash scripts/generate-kb-index.sh --check
```

Only the last two links contain the string `--check`, and both live in a **test
file**. The three surfaces I searched are exactly the three that auto-discovery
removed the need to touch — the repo did this on purpose, and #7942 plus this
PR's own rename commit argue *for* derive-don't-restate discovery. The property
that makes registration unnecessary is the same property that makes the gate
un-greppable from the config side.

This is the inverse of the failure this repo usually hits. The usual one is a
prose claim that is false and reads as true. This one was a prose claim that was
**true and read as false**, and the cost was not a missed defect — it was
work: a redundant suite, a permanent CI cost, and very nearly a commit "fixing"
four accurate sentences into hedges.

## Solution

Two moves, in this order.

**1. Search the executable surface, not the declarative one.** The question "is X
gated in CI?" is answered by grepping for X repo-wide, then following each hit up
to a runner — never by grepping the places a gate *would* be declared. A
config-surface grep answers "is there a step named X", which is a different
question and, under auto-discovery, a strictly weaker one. The concrete form:

```bash
# Wrong: asks whether a STEP exists.
grep -rn -- '--check' .github/workflows/ lefthook.yml scripts/test-all.sh

# Right: asks whether anything CALLS it, then walks up to a runner.
grep -rn -- 'generate-kb-index.sh --check' --include='*.sh' --include='*.ts' \
     --include='*.yml' . | grep -v node_modules
```

**2. When a claim names a guard, name the guard's caller with it.** The remedy
is a comment, not a test — the redundant suite was deleted rather than committed.
`.gitattributes` now carries:

> THAT GUARD'S CI CALLER IS NAMED HERE ON PURPOSE. `--check` is invoked against
> the real tree from the `AC17` case in
> `plugins/soleur/test/kb-index-merge-driver.test.sh`, which reaches the
> `test-scripts` job through `SUITE_GLOBS` in `scripts/test-all.sh` — not from
> any step in `.github/workflows/` or `lefthook.yml`.

A sentence asserting that something is enforced owes the reader the address. The
reader's first move is to grep for it, and under auto-discovery that grep comes
back empty from every surface where enforcement is normally declared.

## Key insight

**Auto-discovery is a property of the runner and an absence in the configuration.
Both halves are real, and only one of them is greppable.**

The repo has been moving deliberately toward derived discovery — `SUITE_GLOBS`
over hand-written `run_suite` lines, the `*-mutation.test.sh` naming convention
(#7942), and this PR's own rename commit which deleted two manual registrations
and called that the fix. Every one of those changes is right. Every one of them
also removes a line that a future reader would have found by searching where
gates are declared.

So the discovery convention has a documentation obligation attached to it: **when
you delete a registration line because the name now carries it, the claim that
cited that line has to start citing the convention instead.** Otherwise each
derive-don't-restate win converts one greppable fact into an inference the next
reader has to reconstruct — and the next reader, on the evidence here, will
reconstruct it wrong and build something.

## Session Errors

- **Concluded a gate did not exist from a three-file grep, and built a redundant
  suite on that conclusion.** The suite was written, run green, and only then
  discovered to duplicate `AC17` plus `C3`-`C6`. Recovery: deleted it before
  committing; added the caller citation to `.gitattributes` instead.
  **Prevention:** answer "is X gated" by grepping for X repo-wide and walking up
  to a runner, never by grepping the surfaces where a gate would be declared.
- **Assertion anchored on a bare token, five times in one branch
  (`cq-assert-anchor-not-bare-token`).** The worst was `AC18`, which was live and
  fail-open; my *first* repair — anchoring on the `run:` line — was **also**
  satisfiable, because the comment naming the files sits inline on that very
  line. Recovery: strip trailing comments (`sed 's/#.*//'`) before matching.
  **Prevention:** an anchor is not sufficient until the haystack is
  comment-stripped, scoped to the region under test, and the match is unique
  within it.
- **Two tests had pinned a defect rather than caught it.** When `%P` refusal was
  corrected to stop writing a sentinel, `T19` and probe `P2` both failed —
  because both asserted the sentinel *was* written. **Prevention:** when a test
  fails after a fix, first ask whether the test encoded the old behaviour; a
  refusal on a path the driver does not own must write nothing at all.
- **Committed while a battery was red**, by batching verification and `git commit`
  into one tool call so the non-zero exit had nowhere to stop the sequence.
  **Prevention:** `hr-when-a-command-exits-non-zero-or-prints` — never put a
  verification and the action it gates in the same call.
- **A backgrounded `git commit` reported exit 0 without landing**, because the
  command ended in `echo` and the notification reported the echo's status.
  Recovery: relaunched detached with an explicit `rc` file.
  **Prevention:** never take a verdict from a command whose exit status is not
  the last thing in the pipeline; write the rc to a file and read it.
- **A `Monitor` `*.rc` glob missed dotfiles** and reported "24 suites, 0
  non-zero" while two `.claude/hooks` suites were red. **Prevention:** the
  clean/never-ran collapse — make "the loop ran" observable, separately from
  "the loop found nothing".
- **Set an assertion floor from expectation (66) rather than from a green run
  (64).** **Prevention:** a floor is a measurement; read it off a green run.
- **`python3 str.replace` silently no-oped** on an anchor repair because the
  needle had drifted. **Prevention:** assert the occurrence count before
  replacing — this session's second edit did (`assert s.count(old) == 1`).
- **Misread `test-all.sh` rc=4** as a failure. It is REFUSED: a sibling full-gate
  run was in flight (#7553), so nothing ran. **Prevention:** rc 1 = failure,
  rc 3 = UNRESOLVED, rc 4 = REFUSED-before-anything-ran.
- **Forwarded from `session-state.md`:** the `iac-plan-write-guard.sh` hook
  blocked the plan write on the phrase "out-of-band" (rephrased, not
  acknowledged — no infrastructure step existed to acknowledge); the Kieran
  reviewer ran ~29 min and returned against a superseded draft; an AC insertion
  briefly duplicated numbers 15-17; two agents disagreed on whether
  `npm install --package-lock-only` fires `prepare`, resolved by adopting the
  empirical fixture run.

## Related

- [`2026-09-07-my-instruments-reported-green-while-measuring-nothing.md`](2026-09-07-my-instruments-reported-green-while-measuring-nothing.md)
  — instruments that cannot distinguish clean from never-ran. This learning is
  the search-strategy sibling: a *grep* that could not distinguish "not gated"
  from "gated somewhere I did not look".
- [`2026-09-07-i-committed-the-defect-class-i-was-reviewing-for.md`](2026-09-07-i-committed-the-defect-class-i-was-reviewing-for.md)
  — `cq-assert-anchor-not-bare-token`, which recurred five times here.
- #7942 — the `*-mutation.test.sh` naming convention whose derive-don't-restate
  argument this learning accepts and then qualifies.
