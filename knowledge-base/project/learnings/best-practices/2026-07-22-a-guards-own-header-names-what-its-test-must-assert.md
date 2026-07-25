---
title: A guard's own header names what its test must assert
date: 2026-07-22
category: best-practices
tags: [testing, mutation-testing, ci-guards, non-vacuity, code-review]
issue: 6757
pr: 6826
---

# A guard's own header names what its test must assert

## Problem

The #6757 varq-ban guard (`scripts/lint-followthrough-varq-ban.sh`) shipped from
`/work` with a genuinely good both-directions mutation test — GREEN compliant,
RED-A (`:?`), RED-B (colon-less `?`), COMMENT-GREEN + a mutation control. It
passed 208/208. Yet post-implementation review (`test-design-reviewer`)
reproduced **three surviving mutants**, and the most important one was the guard's
own *stated* core value:

- The guard header says, verbatim: *"naming the offender accurately is the whole
  value of the guard"* and warns against the exact `grep -v '^#' | grep -n`
  re-index anti-pattern that mis-cites line numbers.
- The test asserted only the **filename** (`grep -q 'banned-colon-q.sh'`), never
  the **line**. So a guard mutated to that warned-against pipeline — the precise
  failure the header exists to prevent — passed the test GREEN.

The other two survivors were the same shape: the `scanned < MIN_PROBES`
anti-vacuity floor and the missing-dir → exit 2 path both had zero coverage;
neutering the floor shipped green.

## Key insight

**A guard's header/docstring that declares "X is load-bearing / the whole point /
must never Y" is a test checklist, not just prose.** Whoever wrote the warning
understood the failure mode precisely — and then wrote a test that didn't cover
it. The cheapest reviewer gate for any guard-with-a-test PR:

> For each "X is load-bearing" / "the whole value is X" / "must fail closed on Y"
> claim in the guard's own comments, `grep` the test for an assertion that pins X.
> If the guard names its core invariant and the test only checks the exit code,
> the test is vacuous w.r.t. that invariant.

This is the concrete, self-sourced form of the repo's standing rule *"assert on
the guard's diagnostic payload (file:line, scanned-count, error text), not just
its exit code"* — the guard's prose tells you which payload fields to assert.

## Fix applied (all inline, pr-introduced)

- RED-A/RED-B now pin `file:LINE` (banned form placed below a shebang + full-line
  comment so a re-index mis-cites it as `:2` instead of `:4`).
- Added MISSING-DIR (exit 2) and FLOOR-breach (exit 2) cases; the floor case forces
  a breach on the real tree via a **test-only** `VARQ_BAN_MIN_PROBES` override
  (production CI never sets it; default stays 10).
- Added an INLINE-COMMENT contract case asserting the current fail-**closed**
  behavior (a banned form in a *trailing* comment is flagged) rather than making
  the strip inline-aware — correct trailing-`#` stripping in shell is the
  fragile-lexer path that risks a fail-**open** regression.
- Each new assertion mutation-verified against a **sandbox copy** of the guard:
  the re-index, floor-neuter, and `exit 1`→`0` mutants each redden the enhanced
  suite.

## Session Errors

- **Two mutation-verify mutants "did not land"** (fragile `perl` regexes against
  the guard's complex detection line and an indented `exit 1`). The suite then
  reported the **baseline** result, which is indistinguishable from a real pass.
  Recovery: caught by a byte-diff landing check before trusting the run; redone
  with `python3` substitutions that `assert` the anchor exists and confirm the
  file changed. Prevention: this is the repo's existing rule *"a mutation that
  does not mutate reports a false result — assert the mutation LANDED"* (#6537);
  applying it caught the false-negative. Bake a landing check (`diff -q` /
  `git diff --quiet` on a **backup or sandbox copy**) into every ad-hoc mutation
  loop by default.
- **`count('exit 1')==1` tripped** — a second `exit 1` lived in a header comment.
  Recovery: switched to a precise code-line anchor (`\n  exit 1\nfi\n`).
  Prevention: anchor a mutation substitution on syntax/indentation, never a bare
  token that also appears in prose (the same anchor-not-token rule that governs
  the guard's own grep).
- **Pre-push gate 207/208** — the `changelog-data` live-GitHub-API test flaked on
  a 5 s timeout, unrelated to this diff. Recovery: isolated re-run passed 3/3;
  filed as recurring tech debt (#6842, different subsystem). Prevention: mock or
  skip live-network calls in gating unit suites.

## Related

- [[2026-07-16-a-mutation-battery-only-covers-what-you-mutate]] — the sibling
  rule; this learning adds "the guard's own prose tells you what the battery
  missed."
- [[2026-07-16-a-gate-certifies-placement-not-correctness-and-a-documented-class-recurred-again]]
- #6842 — changelog-data live-API flake (filed this session).
