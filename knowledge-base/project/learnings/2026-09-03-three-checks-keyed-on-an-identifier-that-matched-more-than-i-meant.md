---
date: 2026-09-03
category: workflow-patterns
module: verification
issues: [7460]
pr: 7784
tags: [mutation-testing, vacuous-guard, identifier-collision, verification]
related:
  - 2026-09-03-every-check-i-shipped-was-narrower-than-the-name-it-carried.md
  - 2026-09-03-the-deviation-ledger-was-an-hour-of-my-own-test-fixtures.md
  - 2026-09-02-every-guard-i-wrote-was-satisfiable-by-a-guard-that-asserts-nothing.md
  - 2026-08-01-my-battery-was-green-and-my-own-tests-pinned-the-bug.md
---

# Learning: three checks keyed on an identifier that matched more than I meant

## Problem

One session, three tools, one shape. Each time I keyed a check on an identifier
without asking **what else that key matches** — and each time the thing that would
have caught it was keyed the same way, so it agreed.

### 1. `basename` — I destroyed a file and my own check certified the wreckage

A mutation battery saved pristine backups as `/tmp/$(basename $f).pristine`. Both
Terraform roots carry a file named `variables.tf`
(`apps/web-platform/infra/` and `apps/web-platform/infra/rung2-rehearsal/`), so the
second backup clobbered the first. "Restore" then wrote the **rehearsal** root's
file over the **prod** root's: 53 variables down to 10. I committed it. `terraform
validate` went to 39 `Reference to undeclared input variable` errors.

The verification loop was:

```sh
for f in "${FILES[@]}"; do diff -q "$f" "/tmp/$(basename $f).pristine" || echo "NOT RESTORED"; done
echo "all restored byte-identical"
```

It printed clean — because it compared *both* files against the one surviving
backup, and the damaged file now matched it. **The check was vacuous for exactly
the reason the mutation was wrong.**

### 2. A marker comment — the arm asserted the presence of my own comment

`FATAL_SQL` carried `/* __FATALROWS__ ... */`, a marker *I* had written. The test
stub dispatched on it:

```sh
elif printf '%s' "$sql" | grep -q '__FATALROWS__'; then cat "$_fatal"
```

So no fixture could reach any semantic clause of the query. Measured: dropping the
`level = 'fatal'` filter, dropping the `host_name` filter, `LIMIT 1000` → `LIMIT 1`,
and making the query **semantically identical to the one it exists to differ from**
all left the suite at 56/0. The entire fix was silently revertible.

### 3. `pgrep -f` — the loop matched itself

```sh
until ! pgrep -f "run-registered-suites.sh" >/dev/null 2>&1; do sleep 10; done
```

The loop's own command line contains that string, so `pgrep -f` matches the shell
running it. Two such loops spun for ~40 minutes after the runner had finished
108/108, each seeing itself and the other. `pgrep -f` also matched sibling
worktrees' runs, so even without the self-match the condition was not mine to own.

## Root cause

Not carelessness about any one key — a missing question. For each of these I asked
*"does this key match the thing I want?"* and never *"what is the full set this key
matches?"* The first question is satisfied by one positive example. The second
requires enumerating.

The compounding failure is that the **verification shared the key**. A backup keyed
on basename, checked by a diff keyed on basename. A query keyed on a marker,
asserted by a stub keyed on the same marker. That is why all three presented as
green rather than as errors.

## The adjacent failure, same session

My mutation battery for this PR was six rows — and **1-for-1, not 6-for-6**. Every
row perturbed the same axis: the exact token the assertion greps for (rename the
resource, drop the helper, add the `default`, add the name to the allowlist…). It
proved each grep was wired to its literal and nothing else.

An 11-agent panel then measured the axes the battery never touched, and the PR's
**central artifact** turned out to be untested five separate ways: deleting the
`write_files` entry outright, flipping its mode to `0644`, deleting the emitter's
load block, reverting `curl -K -` to `-H` on argv, and gutting the silent-fallback
mirror each left **all six suites green**.

## Solution

**Enumerate the key's match set before trusting it.**

| Key | The question | The fix used here |
|---|---|---|
| `basename` | do two files in scope share it? | key on the full path: `/tmp/$(echo "$f" \| tr '/' '_').pristine` |
| a marker you authored | could the SUT satisfy this without being correct? | dispatch on **semantics** — the stub now requires the level filter, the host filter *and* `LIMIT >= 1000` |
| `pgrep -f <string>` | does the matcher's own cmdline contain it? | wait on a captured child PID, or a sentinel the loop does not itself contain |

**Count mutation rows by axis, not by row.** Six edits to "the token the assertion
greps for" is one row. Before declaring a battery done, list the axes — fixture
direction, extractor scoping, set cardinality, dispatch, and *the SUT itself* — and
name which rows cover each. An axis with no row is untested however many rows there are.

**A mutation must be proven to land ON ITS TARGET, not merely in the file.** One
mutation here replaced `project = doppler_config.git_data_prd.project` and reported
green; the string occurs in several `doppler_secret` blocks and the edit hit the
wrong one. Scope the mutation to the block, then assert the *block* changed.

**Run the gates the repo has, not the ones you thought of.** I ran `terraform
validate` and `terraform fmt` and never `terraform test`, which this repo has and CI
runs. It caught a 5-char stub fixture that a new variable validation correctly
rejects — the validation was right, the fixture was wrong, and only the gate I
skipped knew.

## Key Insight

**A check and the thing it checks must not share a key.** When they do, the check
cannot fail for the reason you built it — it can only agree.

This sits one level below [the deviation ledger
learning](2026-09-03-the-deviation-ledger-was-an-hour-of-my-own-test-fixtures.md)
(a signal that measures the instrument rather than the world) and beside [every
guard I wrote was satisfiable by a guard that asserts
nothing](2026-09-02-every-guard-i-wrote-was-satisfiable-by-a-guard-that-asserts-nothing.md)
(an assertion whose predicate is trivially true). Those two are about the
*assertion*. This one is about the *identifier*: the assertion is fine, and it is
pointed at a set you did not enumerate.

Landed on `main` the same day from unrelated work: [every check I shipped was
narrower than the name it
carried](2026-09-03-every-check-i-shipped-was-narrower-than-the-name-it-carried.md).
Different subject (a model-launch auditor), same family — a check whose real scope
is narrower than the one its name advertises. Read together they bracket the
question: that one asks *"is the check as wide as its name?"*, this one asks *"is
the key as narrow as I think?"*

## Session Errors

- **Mutation-battery backups keyed on `basename`; destroyed `variables.tf` and committed it.** — Recovery: restored from the pre-battery commit, re-audited every file the battery touched against the correct baseline. — **Prevention:** key temp artifacts on the full path; never `basename` when more than one file is in scope.
- **Test stub dispatched on a marker comment authored by the same change it tests.** — Recovery: stub now dispatches on the query's semantics; four previously-surviving mutations redden. — **Prevention:** a fixture must not key on a token the SUT's author chose; key on the property.
- **`pgrep -f` wait-loops matched themselves; two shells spun ~40 min.** — Recovery: `TaskStop` on both. — **Prevention:** wait on a captured PID, not a `-f` pattern the waiter's own cmdline contains.
- **Six-row mutation battery covered one axis.** — Recovery: an authorised review panel found the untested axes; re-run per-axis with each mutation restored byte-identical. — **Prevention:** enumerate axes and map rows to them before declaring a battery complete.
- **Ran `terraform validate`/`fmt` but not `terraform test`.** — Recovery: CI caught it; fixture lengthened. — **Prevention:** before pushing infra, run every gate the CI job runs, read off the workflow rather than from memory.
- **Redactor fix wrote its sed script to a fixed `/run` path, unwritable unprivileged.** — Recovery: switched to `mktemp` (atomic 0600, honours `TMPDIR`). — **Prevention:** a path that must work as root on a host and unprivileged in a suite is `mktemp`, not a literal.
- **CI monitor fed `comm` unsorted, newline-less input.** — Recovery: re-armed with a seen-set file. — **Prevention:** `comm` needs both inputs sorted *and* newline-terminated; prefer `grep -vxF -f seen`.
- **`git stash list` reflex, hook-denied twice.** — Recovery: removed the line. — **Prevention:** already hook-enforced (`hr-never-git-stash-in-worktrees`); the reflex is mine, not a gap.
- **Filed #7765 duplicating #7486 without running `gh issue list` first.** — Recovery: folded the unique findings into #7486, closed #7765. — **Prevention:** already covered by `hr-when-triaging-a-batch-of-issues-never`; run `gh issue list` for the class before filing.

## Tags

category: workflow-patterns
module: verification
