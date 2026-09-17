---
title: The watcher and the watched shared a lifetime, and my filter narrowed to empty
date: 2026-09-17
category: workflow-patterns
tags: [monitoring, vacuity, knowledge-base-archiving, ci]
---

# Learning: the watcher and the watched shared a lifetime

- **PRs:** #8233 (shipped), #8247 (this one)
- **Related:** [instruments reported green while measuring nothing](2026-09-07-my-instruments-reported-green-while-measuring-nothing.md), [archiving slug extraction must match branch naming conventions](2026-02-22-archiving-slug-extraction-must-match-branch-conventions.md)

Shipping a three-line frontmatter fix cost two full test batteries, three orphaned
process cleanups, and two rebuilt watchers. The fix was never in doubt. Every
problem was in the **instruments I built to watch my own work**, and each one
failed in the shape of success.

## 1. A watcher that HOSTS the work dies with the watcher

I ran the 35-minute battery as the Monitor's own command. The Monitor expires at
30 minutes by design, and expiry killed the run five minutes short.

The tell was not subtle, and it was written by the tool itself:

```
NOTE: this run ended before the repo-write boundary was re-read, so it is NOT evidence
      that no suite wrote to your repository. The absence of a [FATAL] line above means
      the check did not run, not that it passed.
```

No rc file, no suites-passed marker, runner gone — the documented reap signature,
which is UNRESOLVED and never a verdict. Reading it correctly is what stopped a
false green; it does not make the design right.

**The rule:** a watch and the work it watches must not share a lifetime. Launch
the work **detached** (`setsid nohup … &`) so it outlives any watch, and let the
watcher only *read* a completion artifact — an rc file, a marker. Re-armed that
way, the same run survived a subsequent expiry and finished. If the watcher can
kill the work, a watcher timeout and a real failure are indistinguishable from
the outside.

**Corollary, paid for three times in one session:** killing a runner does not reap
its children. Each time, `--capacity` still reported contention afterwards, and the
survivors were suites whose `cwd` had been deleted. Enumerate by the contention
lib's own scanner and kill by exact pid; a captured PID names a process, a pattern
does not.

## 2. A filter that can silently narrow to empty needs a floor

My release watch polled `gh run list --branch main --commit <sha>`. As `main`
advanced, that combination stopped matching the merge commit's push runs: the
release set went **10 → 0** while 26 unrelated `issues`/`dispatch` runs still
matched. The loop's settle test was `pending == 0`, which an empty set satisfies
perfectly, so it was one poll away from reporting ALL-SETTLED over nothing.

This is the *same vacuity class as mutation row M7 of the guard I was shipping in
that very PR* — "a bounded floor refuses a clean sweep over an empty corpus". The
guard had the floor. My watcher did not.

**The rule:** any poll whose population can shrink must (a) record the largest
population seen and refuse to settle below it, and (b) require the specific run it
is waiting for to be **present**, not merely non-failing. Absence of failure over
an absent set is not success. Drop the filter you cannot prove is stable —
`--commit <sha>` alone was correct; `--branch` was the part that rotted.

**Second-order:** the first rebuild of that watcher classified every `cancelled`
run as a release failure, and my own `gh issue create` calls triggered `issues`
workflows that were cancelled by concurrency. The watcher reported RELEASE-FAILURE
for runs my own filing had caused. Scope a release watch to `push`/`workflow_run`.

## 3. An archive glob keyed on the slug cannot see a topic-named plan

`archive-kb.sh` discovers plans with `plans/*<slug>*`. A plan named for its
*topic* — `2026-09-17-fix-duplicate-soleur-slash-command-entries-plan.md` on branch
`feat-one-shot-dedupe-harness-shim-skills` — contains none of the slug, so the
glob matched the spec directory and not its plan.

This is adjacent to the 2026-02-22 slug-prefix learning but is **not** the same
defect and no amount of prefix-stripping reaches it: there the slug was mangled,
here the filename never carried a slug at all. The failure is silent and
*asymmetric* — it archives half a pair, which is worse than archiving neither,
because the surviving half looks current.

**The rule:** when an archiver discovers by name, verify its output names every
artifact you expect before trusting it, and archive a pair under **one** timestamp
so the pair stays together. `--dry-run` answers this in seconds.

## 4. A pipe destroys the exit code you are about to read

Three times in one session I wrote `cmd | tail` or `grep … | head` and then read
`$?`, which is the *pipe's* status. Each produced a confident wrong verdict — "a
PIR is required", "soak signal fired" — that a re-run without the pipe reversed.
Already corpus-documented; recorded here only because knowing the rule did not
prevent it. Redirect to a file, read `$?`, then format.

## Session Errors

1. **Ran a 35-minute battery inside a 30-minute watcher.** Recovery: read the
   reap honestly as unresolved, relaunched detached. Prevention: §1.
2. **Left orphaned suite children three times** after killing a runner. Recovery:
   enumerated via the contention lib's scanner, killed by pid. Prevention: §1
   corollary.
3. **Built a release watcher that could report settled over an empty set.**
   Recovery: caught it when the count dropped 10 → 0; rebuilt with a floor and a
   deploy-arm presence requirement. Prevention: §2.
4. **Reported a false RELEASE-FAILURE caused by my own issue filings.**
   Recovery: verified `event=issues`, `jobs: []`, workflow `on:` is issues-only;
   rescoped the watcher. Prevention: §2 second-order.
5. **Told the operator ADR-224 cited the archived plan path.** It does not — the
   only citations were a generated index and a file inside the moved directory.
   I asserted a blocker without grepping for it. Recovery: measured, corrected in
   the archival commit. Prevention: the deferral-claim rule from #8233's own
   learning, which I had just written.
6. **Read `$?` after a pipe, three times.** Prevention: §4.

## Tags

category: workflow-patterns
module: plugins/soleur/skills/ship, plugins/soleur/skills/archive-kb
