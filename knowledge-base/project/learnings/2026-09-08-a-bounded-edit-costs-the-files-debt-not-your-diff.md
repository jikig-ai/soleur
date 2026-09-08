---
title: "A bounded edit costs the file's debt, not your diff"
date: 2026-09-08
category: workflow-patterns
issue: 7937
pr: 7962
tags: [ci, linting, tooling-traps, scoping, harvest-debt, hooks]
---

# A bounded edit costs the file's debt, not your diff

## Problem

Issue #7937 is about as bounded as an issue gets: *"one bullet or one ≤3-line
clarification each — this is not a restructuring of the skill."* Two rules, one
file, `plugins/soleur/skills/ship/SKILL.md`.

The edit was two hunks. The commit was thirteen.

`git commit` bounced on sixteen markdownlint errors that were already in the file
— lefthook lints **staged** files, so the moment `ship/SKILL.md` entered the
index it was scored in full, not on the diff. None of the sixteen were mine.
Clearing them was not optional and not negotiable: the file cannot be committed
at all while they stand, and the only alternative is `--no-verify`.

## Root cause

Two facts compose into a trap, and neither is visible when you scope the work.

**The linter's version is unpinned.** `lefthook.yml:21` runs
`npx --yes markdownlint-cli`, which resolves the *latest* version on every
invocation. A rule addition upstream reddens the whole corpus with no repo change
at all.

**The debt is therefore invisible until you stage.** In `ship/SKILL.md` the MD038
offender was introduced 2026-04-22 (`9113c559d`) and the MD007 offenders
2026-07-11 (`09e9a3e82`). That file has been staged and committed **12 times in
the last 30 days**, passing this same hook each time. The regions did not change;
the verdict did.

It is not one file. Measured across the skill corpus:

```bash
tot=0; dirty=0
for f in plugins/soleur/skills/*/SKILL.md; do
  n=$(npx --yes markdownlint-cli "$f" 2>&1 | grep -cE ' MD[0-9]+' || true)
  tot=$((tot+1)); [ "$n" -gt 0 ] && dirty=$((dirty+1))
done
echo "$dirty of $tot"   # 38 of 95
```

**38 of 95** skill files cannot be staged without first clearing someone else's
debt. `work/SKILL.md` 12, `ship/SKILL.md` 16, `plan/SKILL.md` 5. The four open
per-file issues (#7817, #7832, #7837, #7957) read as separate incidents; they are
samples of a corpus-wide condition, which is what #7927 tracks.

## Solution

**Run the file's own gates on it before you scope the edit, not after you write
it.** One command answers "what will touching this cost me", and it is the same
command the hook will run. A two-bullet change and a two-bullet change plus
sixteen unrelated repairs are different pieces of work, and the difference is
knowable in advance for the price of one lint invocation.

**Then decide per finding, because a blind sweep damages files.** Nine of the
sixteen were MD007 on bullets that are *continuation content* aligned to a
numbered step's own 3-space indent. MD007 measures against a top-level list, so
"fixing" them would have misaligned them from the block they belong to. Those got
a narrow scoped disable naming why; the other seven — MD038
escaped-backticks-inside-a-code-span, MD031 fences, MD032 lists — were real and
were repaired. A corpus-wide `--fix` would silently do the wrong thing to the
larger population.

**And say which hunks are yours.** Eleven of thirteen hunks in this PR are
somebody else's debt. A reviewer who cannot tell those apart reviews the wrong
change; the commit message and PR body both partition them explicitly.

## Key insight

**A shared file's accumulated gate debt is part of the cost of touching it, and
it is charged to whoever touches it next — not to whoever incurred it.**

That makes it invisible in exactly the place estimates are made. Nobody planning
a two-bullet edit thinks to ask what the file's linter says about the other 2,600
lines, and under an unpinned linter the answer changes without anyone editing
anything. The bill is not proportional to your change; it is proportional to how
long the file has gone untouched and how much the tool moved in that window.

The corollary for a *repo*: an unpinned lint in a pre-commit hook converts a
silent upstream release into a distributed tax on future contributors, collected
one file at a time, from people who did not incur it and cannot see it coming.
Pinning the version does not clear the debt — it stops new debt arriving without
a commit.

## Session Errors

- **Scoped the work from the issue's description rather than from the file's
  gates**, and discovered the real scope only when `git commit` bounced.
  **Prevention:** run the file's own linters before scoping a "bounded" edit to
  a shared file; the debt is the scope.
- **Nearly ran a blanket fix on all sixteen findings.** Nine were MD007 on
  correct continuation indentation, where satisfying the rule would have
  misaligned the content. **Prevention:** decide per finding; a rule that
  measures against a structure your content is not part of gives wrong answers
  confidently.
- **Started to write the drift's cause as a hypothesis in the PR body**
  ("the likely cause is…") before checking it. Two `git log -S` calls dated both
  offender populations and one `git log` counted 12 intervening commits, which
  turned a guess into a measurement. **Prevention:** a causal sentence in a PR
  body is a claim; name the command that would falsify it and run it — the same
  rule as [[2026-09-08-i-grepped-the-config-for-a-gate-that-lives-in-a-test]].
- **Inherited a stale measurement from the issue.** #7937 cites `test-scripts` at
  27 min from run `34163673236` (2026-09-07); re-measuring over the five most
  recent completed `main` runs gave 34/36/36/35/36 min. The figure moved 27 → 35
  in a day, so the file now carries the derivation command instead of the number
  alone. **Prevention:** re-derive an inherited measurement at the granularity
  you are about to assert it.

## Related

- #7927 — the class tracker; this session's corpus measurement was added there
  rather than filed as a new issue.
- [`2026-09-08-i-grepped-the-config-for-a-gate-that-lives-in-a-test.md`](2026-09-08-i-grepped-the-config-for-a-gate-that-lives-in-a-test.md)
  — same session, same shape one level over: a cost paid because a cheap
  measurement was skipped in favour of an inference.
