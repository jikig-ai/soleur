---
title: "Six instruments reported could-not-measure as measured-clean, and I wrote one of them"
date: 2026-09-10
issue: 7947
pr: 7975
category: workflow-issues
tags: [instruments, vacuity, ci, monitoring, false-all-clear, guards, anchoring]
---

# Six instruments reported could-not-measure as measured-clean, and I wrote one of them

Sibling record: [2026-09-09 — every defect was in the guard](2026-09-09-every-defect-was-in-the-guard-and-my-own-prescribed-command-defeated-it.md)
covers the two review rounds (19 P1s, all inside the guards). This file covers
everything after it: the ship-gate consult, the full battery, and the merge.

PR #7975 shipped with **32 defects found, every one inside my own guards rather
than the code they protect** — 19 from review, 6 from a consult run against the
real CLI, 6 from a battery, 1 telemetry sink. That distribution is the sibling
file's thesis. This file is about the level above it: **the instruments.**

## The central finding

In one session, six different instruments rendered "I could not measure" and "I
measured, it is clean" identically.

1. **`test-all.sh` rc=4 is REFUSED, and looks like a pass.** It exits in under a
   second with no `[FAIL]` lines because a sibling full-gate run held the lock.
   Every "all gates green" claim on this branch had rested on individually-run
   suites; **the full battery had never once executed.** When it finally did:
   387/398, six red, all six mine.
2. **A background task's completion notification reports the WRAPPER's exit.**
   It said "exit code 0" for a run whose rc file said `1` — twice (the battery,
   and the infra suites). The repo already says read the rc file. This is why.
3. **An OOM kill presents as a task failure.** "Stopped because the system is
   running low on memory" reads as "the tests failed". Nothing ran.
4. **An empty API page is a zero, not an answer.** `gh run list` returned an
   empty set; `total=0` satisfied a naive `pending==0` check.
5. **Zero is stable.** I wrote a release monitor that required
   `total == prev_total` before trusting `pending=0`, specifically to defeat the
   registration race. Its working directory was deleted mid-run (a sibling
   session reaped the worktree), `gh` returned nothing, and `0 == 0` twice
   printed `ALL COMPLETE` while **37 runs were in flight**. The guard I built
   against false all-clears produced one, minutes after I explained the hazard.
6. **A run-level status field is not an aggregate.** GitHub reported
   `status: queued` for a CI run whose jobs were already succeeding. I said "CI
   has not started" before checking the jobs.

**The rule:** for any instrument, ask what it prints when it *cannot* measure,
and make that distinguishable from a clean result. An exit code, a count, an
empty set, and a status field can each render "I did not look" exactly like "I
looked and it was fine". Prefer a terminal marker plus an rc file over either
alone; treat an empty result as transient and never as evidence; and when a
stability check guards a count, exclude the degenerate value the failure mode
produces.

### A seventh, found while writing this file

`markdown-lint` reported on this very learning: *"none of the 1 given path(s)
are in scope (excluded by `.markdownlintignore`, or not tracked `*.md`) --
nothing to lint."* I could not tell from that which condition held, so I checked:
`knowledge-base/project/` is excluded **by policy** (#7927 — session artifacts
are read, not rendered; linting 8,231 files yields 29,200 findings). The pass is
legitimate.

The message is still the defect in miniature. It ORs together "deliberately out
of scope" and "silently skipped", which are opposite facts about whether anything
was measured, and prints one sentence for both. A single word — which condition
matched — would separate them. Keep this in view when writing any skip message:
the reader's next question is always *did you not look, or was there nothing to
look at?*

## A secret-gate script is enrolled by NAME, and the whole corpus must follow

`redact-a11y-snapshot.py` matched the repo's `GATE_SCRIPT_RE`, which silently
enrolled it in the ADR-179 **secret-gate** population. That population requires
the canonical reference form — bare `${CLAUDE_PLUGIN_ROOT}/…`, quoted, plus a
fail-closed plugin-identity preflight in every referencing skill.

My corpus sweep used `"${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}"` in 24 places and
a bare repo-relative path in 4 more: **zero of 28 canonical.** ADR-179 rejects
the `:-default` form for this PR's own reason — the fallback resolves to a repo
path that exists on no customer machine, so a missing anchor degrades SILENTLY
instead of failing loudly.

Round 1 had already fixed **one** such path on exactly that reasoning. It fixed
the instance, not the class. When a review finding names a mechanism, grep the
mechanism, not the line.

Corollary: **the lint's own remedy string and the hook's printed remedy both
taught the rejected form.** A guard that prints the wrong remedy is the same
defect as one that accepts the wrong command — the operator pastes what it says.

## My anti-vacuity floors were themselves unmeasurable

Two independent reasons, and neither is visible from the suite's own green:

- **Unconstructible.** `guard-vacuity-floor` builds its mutant by slicing the
  floor block and widening BACKWARD over *contiguous* assignments. With
  `MIN_ASSERTIONS` declared at the top of the file, it is unbound in that slice,
  so the mutant dies on `set -u` before reaching the floor — scored
  "unconstructible", which is indistinguishable from "does not fire". Bind the
  threshold ADJACENT to the floor block.
- **Wrong vocabulary.** Once constructible, both floors scored "does not fire"
  because the FIRES sentinel list is lowercase `vacuit` and my floors printed
  `VACUITY:`. A floor that genuinely fired was read as a construction failure.

Net: **nothing had ever verified those two floors could fire at all** — in a PR
whose subject is guards that fail silently.

## A fail-closed halt that reaches no sink

My ADR-179 preflight emitted `SOLEUR_SNAPSHOT_HALT`, matched by no consumer. The
guard would have halted correctly and **silently**. This is the identical defect
#7450 round 2 recorded in that very file's own comment ("shipped these markers
into payload markdown while NO consumer matched them"), reproduced one release
later. A refusal that reaches no sink is indistinguishable from a run that never
happened.

## Merging append-only registries recreates count drift

Four conflicts, all in shared legal registries a sibling session (#7500 /
ADR-211) had also edited. All resolved as **unions**, never by choosing a side —
a dated record is append-only, and picking a side silently deletes the other
session's legal record.

But both sides had independently bumped the breach-register preamble count by
one, so the merged file claimed "twelve" against 13 rows. I had **already fixed
that same count on this branch** (stale at "ten" against eleven before this work
touched it). Re-derive counts by counting; a count that no gate reads drifts
every time two branches touch it.

For the PA-8 cell, each side had appended a *different* dated amendment. Both
preserved chronologically, with the union derived from the two sides' shared
prefix rather than hand-spliced, so neither body could be truncated.

## What the auto-close traps were worth

Two were caught pre-merge, and the merge proved both real: **#7980 stayed OPEN.**
It tracks this PR's own stated residual (property P7 unachieved on the
Playwright-MCP path). A negated `close #7980` in a commit body — GitHub ignores
negation, and this repo composes squash bodies from `COMMIT_MESSAGES` — would
have closed the record of the gap the shipped guard does not cover.

## Session Errors

**`test-all.sh` rc=4 read as a clean run, so the branch's "all gates green"
claim was never true.** **Prevention:** never accept a battery result without
reading the rc file AND the terminal marker; rc=4 means nothing executed.

**A task-completion notification reported exit 0 over a run whose rc file said
1, twice.** **Prevention:** the notification reports the wrapper's exit. Read the
rc file the run wrote, never the notification.

**Two OOM kills read as test failures.** **Prevention:** distinguish "killed" from
"failed" before diagnosing; check for orphaned children and a leftover
`index.lock` before retrying.

**An empty `gh` page produced `total=0`, satisfying a `pending==0` check.**
**Prevention:** treat an empty API result as transient and never as evidence.

**My own monitor printed ALL COMPLETE over 37 in-flight runs, because zero is
stable.** **Prevention:** when a stability check guards a count, exclude the
degenerate value the failure mode produces; assert the count is non-zero before
trusting that it stopped changing.

**I said "CI has not started" from a run-level `status: queued` while its jobs
were succeeding.** **Prevention:** a run-level status is not an aggregate over
jobs — read the jobs.

**`ps -e … -C claude` reported 650 processes / 22 GB; the truth was 19 / 8.5 GB.**
`-e` overrides `-C`, so it listed every process. Caught by noticing kernel-thread
states in the output. **Prevention:** when a measurement is surprising by an
order of magnitude, re-derive it a second way before reporting it.

**I piped `shellcheck` through `tail` and read the pipe's exit code.** The repo's
own learnings already name this. **Prevention:** never pipe a command whose exit
code IS the result; redirect and read `$?`.

**My PR body described the negated-close trap verbatim, which would have
re-created it.** GitHub's parser is markdown-blind, backticks included. **Prevention:**
when documenting a trap that is detected by pattern, describe it without
reproducing the pattern.

**A merge union recreated a count drift I had already fixed on the same branch.**
**Prevention:** after resolving a conflict in an append-only registry, re-derive
every count in the merged file rather than trusting either side's number.

**Three retries of a 51-minute battery under memory pressure before changing
approach.** **Prevention:** after the second identical resource kill, change the
approach rather than the timing — here, `LEFTHOOK_EXCLUDE` for the single
OOM-prone step, with the substitution documented in the commit message.
