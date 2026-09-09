---
title: "The rule propagated; the distrust stopped at commands I wrote"
date: 2026-09-08
issue: 7909
pr: 7912
category: workflow-issues
module: verification
tags: [verification, anti-vacuity, exit-codes, harness, background-tasks, mutation-testing, git]
---

# The rule propagated; the distrust stopped at commands I wrote

## Problem

[2026-09-07](2026-09-07-every-instrument-i-built-to-check-my-own-work-could-not-tell-clean-from-never-ran.md)
documented a class one day earlier: *an instrument that cannot distinguish "measured,
and it was fine" from "did not measure."* Its Prevention section says, in terms:
never pipe a command whose exit code IS the result — redirect and read `$?`.

That rule propagated. I applied it, and it is the only reason this session's worst
misreport was caught. Then the same class landed **three more times**, each time on an
instrument I had not written and therefore had not thought to distrust:

**1. The harness's own completion notification.** Three background `git commit` runs
reported `completed (exit code 0)` while the commit returned 1. The task's exit code is
the *last* command in the backgrounded string, and mine ended with `git log --oneline -1`
for convenience. The convenience line became the verdict.

```
<task-notification> ... completed (exit code 0)
$ grep COMMIT_RC= /var/tmp/c5.log
COMMIT_RC=1
```

I caught it only because I had written `echo "COMMIT_RC=$?" >> log` — the 2026-09-07
rule, applied. Had I trusted the notification, I would have pushed an uncommitted tree
and reported a green gate that returned 1.

**2. `Terminated` rendered as "completed".** One 40-minute gate was killed mid-`tsc` by
the memory reaper. The log ends in the bare word `Terminated`; the notification said
completed, exit code 0. Could-not-measure presenting as measured-good, which is the
parent class exactly.

**3. `comm` on unsorted input.** Twice, `comm -12` printed a plausible file list *and* a
`comm: input is not in sorted order` warning on stderr, which I read past. The overlap
it reported was wrong. `LC_ALL=C sort` on both sides changed the answer.

Same shape, three surfaces, none of them a command I authored.

## The second finding: a fixture that proves the adjacent property

`roster-entry-gate.ts` told its reader that editing the `--` pathspec separator "reddens
a suite two directories away." A decoy fixture existed for it — an anchor planted in a
second path, asserting the derivation stays scoped.

Measured: dropping `--` from **either** implementation left the suite green.

Git applies a trailing pathspec with or without `--`. The decoy proves the path scope is
honoured, which is a *different property*. What `--` guards is **ambiguity**:

```
$ git branch docs/legal/individual-cla.md      # git creates this without complaint
$ git log --first-parent -S"hi" --format=%cI docs/legal/individual-cla.md
fatal: ambiguous argument 'docs/legal/individual-cla.md': both revision and filename
rc=128
```

The fixture now creates the ambiguous ref directly. Dropping `--` reddens both sides.
The prose claim was written before the fixture that would have falsified it, and the
fixture that *looked* like it covered the claim covered its neighbour.

## The third: a true statement in the wrong field disarms a gate

The plan declared `discoverability_test.credentials_required`. Preflight Check 10 honours
that by **skipping without executing**. The command it waived claimed the probe `exits 0`;
it exits 2. A person caught the false claim; the gate that exists to catch it had been
told not to look.

The declaration was *accurate about credentials* — `--print-epoch` performs no fetch and
needs nothing. It was still the wrong field, because the question `credentials_required`
answers is not "does this need a credential" but "**is there no unauthenticated probe of
the same property**". A truthful value in a field whose semantics you have not read is a
waiver you did not know you were signing.

## Root cause

The 2026-09-07 learning is scoped to instruments **I build**: guards, suites, floors,
wrappers. Everything in its Prevention section is phrased as authoring advice. Nothing in
it — or in `AGENTS.rules.md` — says the same suspicion applies to instruments I merely
**read**: a harness notification, a tool's stderr warning, a field in a schema someone
else defined, a fixture someone else wrote that names the property I care about.

Those are the instruments with no author to blame and therefore no review step. They are
also the ones a session leans on hardest when it is tired and wants to be finished.

## Solution

1. **A backgrounded command's exit code is the LAST command in the string.** Never end one
   with a convenience line. Write the real verdict to a file (`echo "RC=$?" >> log`) and
   read that, never the notification. This applies to every wrapper, not just `| tail`.
2. **Read stderr on a command whose stdout looks plausible.** `comm`, `sort`, `join` and
   `diff` all emit usable-looking output alongside a warning that invalidates it.
3. **Before a fixture is allowed to support a prose claim, mutate the thing the claim names.**
   If the mutation stays green, the fixture proves an adjacent property; find what the
   flag actually guards and fixture *that*.
4. **Before setting a schema field that changes a gate's behaviour, read what the gate does
   with it.** "My value is true" and "this field is the right one" are independent.

## Prevention

- **Not yet enforced anywhere — tracked as #7957.** *(Superseded 2026-09-09: enforced —
  see the update below.)* The natural home is
  `work/SKILL.md`'s wrapper-as-guard paragraph, which is also where the false clause
  lives ("a backgrounded command emits a completion notification precisely so you need
  not infer from a tail"). The corrected text is in #7957.

  > **Update 2026-09-09 (#7957):** applied. `work/SKILL.md`'s wrapper-as-guard
  > paragraph now carries the corrected clause, so this item is enforced rather than
  > filed. Both blockers recorded below are also gone: #7955 repaired the 12
  > markdownlint violations (`markdown-lint: 1 file(s) clean`), and the correction
  > landed as prose in an existing paragraph, so it never needed a new
  > `AGENTS.rules.md` entry and the byte ratchet was never engaged.
- It was NOT applied in this PR for two reasons, both worth recording: `AGENTS.rules.md`
  is at `[WARN]` on exactly its 46000-byte ratchet, so a new rule would push the linter
  to `[REJECT]`; and `work/SKILL.md` carries 12 pre-existing markdownlint violations at
  `HEAD`, so lefthook blocks *any* edit to that file until all 12 are repaired — and they
  are not uniform trivia (`` `## ` `` and `` `bash ` `` hold a load-bearing trailing
  space; lines 640/689 look like unbalanced backticks). Repairing them from inside a CLA
  PR is a different subsystem.
- So the honest status is: **measured, documented, filed, not enforced.** The gap between
  the third and fourth of those is the thing this file exists to make visible.

  > **Closed 2026-09-09 (#7957):** the status is now **enforced** — the corrected clause is
  > in `work/SKILL.md`. The gap this bullet named lasted one day. It is left standing rather
  > than rewritten because the interval between filing and enforcing is the measurement, and
  > deleting it would delete the evidence for the claim the file makes.
- The 2026-09-07 learning's Prevention section should be read as covering consumed
  instruments too; this file is the cross-reference for that.

## Session Errors

- **Two concurrent `git commit` processes on one worktree index.** The harness reaped the
  parent Bash call; lefthook survived and kept running. I started a retry, so two writers
  shared one index. — Recovery: enumerated `pgrep lefthook` + `/proc/<pid>/cwd`, walked up
  to both `git commit` parents, killed only the orphaned tree, confirmed the retry alive.
  — Prevention: before retrying any git write, check for a surviving hook process in THIS
  worktree; a reaped harness task does not imply a reaped process tree.
- **Three background tasks reported "exit code 0" for a `git commit` that returned 1.**
  — Recovery: read `COMMIT_RC=$?` from the log. — Prevention: rule 1 above.
- **A killed gate (`Terminated`) reported as completed.** — Recovery: grepped the log tail.
  — Prevention: treat a missing verdict line as unresolved, never as pass.
- **A mutation-test harness corrupted its own SUT.** A `sed` with bad quoting mangled
  `ccla-add.sh`; the run produced 56 failures I first read as a real result. — Recovery:
  `bash -n` on the mutant before running it. — Prevention: every mutation must assert it
  LANDED (`cmp`/`diff -q`) and that the mutant still parses, before its verdict counts.
- **`comm` on unsorted input, twice.** — Recovery: `LC_ALL=C sort` both sides.
- **An assertion floor set by arithmetic rather than measurement.** Computed 119, actual
  118; the floor correctly fired. — Recovery: read the measured count. — Prevention: floors
  are transcribed from a run, never derived from a delta.
- **`<TRACKER>` placeholders were never substituted in the #7922 tracker body** — a plan
  task (Phase 4 step 2) silently not done. The sweeper would have resolved a literal
  `<TRACKER>` path and failed as a daily stderr line nobody reads. — Recovery: substituted
  3 occurrences, verified 0 remain via `gh issue view`. — Prevention: a plan task that
  writes to an external system needs a post-write read-back assertion, not a checkbox.
- **Two pre-existing MD032 violations blocked a commit** (both on `origin/main`, far from
  my edit). — Recovery: fixed the two blank lines, disclosed in the commit message.
- **Local tmpfs exhaustion** from my own planning-phase clones (930M). — Recovery: removed
  only my own session scratch.
- **Two full-gate runs reddened on external causes** — an upstream release tag, then a
  sibling worktree's `merge.kb-index.*` config write. Both attributed by measurement and
  added to #7919; the local-only `memory-backstop` ancestor-walk failure filed as #7956.

## Forwarded from session-state.md (planning phases)

- `#7909`'s suggested filename `ccla-<counterparty>-<issue>.sh` was changed — a natural-person
  legal name in a tracked filename is a CLO re-evaluation trigger.
- No `spec.md` for this branch, so `lane:` defaulted fail-closed to `cross-domain`.
- Two markdownlint failures and two stale path citations caught before commit.
