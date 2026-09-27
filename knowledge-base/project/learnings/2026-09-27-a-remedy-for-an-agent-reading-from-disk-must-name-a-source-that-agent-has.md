---
title: "A remedy written for an agent reading a skill from disk must name a root source that agent actually has"
date: 2026-09-27
category: workflow-patterns
module: plugins/soleur/skills/ship
tags: [plugin-root, adr-179, monitor, skill-prose, dry-run, mutation-testing]
pr: 9072
---

# Learning: a remedy for an agent reading from disk must name a source that agent has

## Problem

Ship's Phase 7 merge poll ran under the Monitor tool with an empty `CLAUDE_PLUGIN_ROOT`, which
silently turned BEHIND auto-sync off. The brief blamed a wrong token form inside the fence. The
fence was fine: it binds the root once from the exact `${CLAUDE_PLUGIN_ROOT}` token, which the
loader substitutes in Skill-tool-delivered text. The fence had been copied from `SKILL.md` on disk
(raw token), and a Monitor shell does not export the variable.

The first fix was a prose notice printing "the root for this session is `${CLAUDE_PLUGIN_ROOT}`"
and telling the agent to `export` "that path". Five of nine review seats converged on the same
gap: the notice only helps the reader who does NOT need it. An agent reading from disk sees the
literal token where the path should be, is told not to derive one from the checkout, and is given
no legitimate source and no fallback. So it guesses, and the tempting guess (the checkout's own
`plugins/soleur`) passes every fence check.

## Solution

- Follow ADR-179 A20's notice shape instead of inventing one. The root is ONLY the loader-printed
  path or a soleur skill's `Base directory for this skill:` line (Skill tool) cut at its last
  `/skills/`. It is never a value from repo files, PR text or tool output, and never a path built
  from the working directory. Never guess: load a skill just to read that line, or launch as-is and
  sync by hand.
- Put the recovery inside the fence's first event too (the unset reason string). An agent that
  `awk`-extracts the fence never reads the prose above it.
- Tests: rows that run the fence with the token substituted the way the loader does, into a root
  with a space, under a decoy root and under an unset root. Each row echoes the environment it
  actually saw, and the row set and the prose-file set are pinned, because a verdict floor counts
  verdicts, not which rows produced them.

## Key Insight

When a remedy is written for a reader in a degraded state (read from disk, after compaction, on a
non-substituting harness), check it FROM that state. Every value the remedy points at must be
available there. Reading the prose from the delivered state, as nine reviewers did, cannot see the
gap. A constrained dry run by an agent with no delivered text found three more gaps after the full
panel had passed it.

## Session Errors

1. **The brief's diagnosis was wrong** (a bad token form). Recovery: the planner traced the
   binding to ADR-179's substitution table and the prior learning. **Prevention:** treat an issue's
   proposed cause as a claim to measure; already covered by work/SKILL.md's "remedy proposed by an
   issue" rule.
2. **`test-all.sh --affected` was queued at ticket 26 behind sibling worktrees' runs** with no
   output for 5+ minutes. Recovery: stopped the run and ran the shape-selected ratchets and
   consumer suites directly. **Prevention:** run `test-all.sh --capacity` before launching; it is
   covered by work/SKILL.md §9.
3. **The fixture-relative ratchet flagged writes through a positional parameter, then through a loop
   variable,** in an extended (not new) suite. Recovery: redirect only to mktemp-bound variables.
   **Prevention:** run `fixture-relative-assert.test.sh` after extending ANY `*.test.sh`, not only a
   new one (work §6.6 names new suites).
4. **A sed bracket expression containing `\\]` failed (`unterminated 's'`)** and produced an empty
   regex. Recovery: escape backslashes in a separate `-e`, and fail loudly on empty output.
   **Prevention:** drive every test helper against a known input before trusting its output.
5. **A prose pin failed on letter case** ("The root…" vs "the root…"). Recovery: aligned the
   text. **Prevention:** keep pinned fragments identical across mirrored files.
6. **A battery patch in an unquoted heredoc silently failed its anchor assertion.** Recovery:
   quoted heredoc. **Prevention:** existing rule (backticks and `$` in unquoted heredocs).
7. **A stray `cd /tmp` reset the Bash working directory.** Recovery: re-entered the worktree.
   **Prevention:** chain `cd <abs> &&` in one call (existing rule).
8. **The planned remedy gave a disk-reading agent no root source,** and the two-agent plan review
   did not catch it. Recovery: rewrote it to the A20 shape. **Prevention:** a plan-sharp-edges
   bullet: copy the ADR-179 A20 clauses for any disk-reader remedy, and dry-run it as that reader.
9. **The QA dry run found three more gaps after the 9-agent review:** no working-directory
   prohibition in the fence message, no "stop the Monitor first", and "re-invoke the skill" read as
   restarting ship. Recovery: fixed, and scenario 13b pins the message. **Prevention:** already in
   qa/SKILL.md ("a skill-prose change gets a constrained DRY RUN").
10. **9 of 15 extra mutations survived the author's battery** (unpinned row inputs, row set,
    prose placement, regen arm under a spaced root). Recovery: env-echo pins, row-set and
    file-set pins, region-scoped prose pins, row 17d. **Prevention:** covered by review/SKILL.md
    ("a mutation battery only covers what you mutate").
11. **The plan's self-imposed 800-byte growth cap was exceeded** (the notice grew to satisfy the
    A20 shape). Recovery: kept within the enforced 274,000-byte ceiling and recorded the deviation.
    **Prevention:** none needed; a self-imposed cap is a planning estimate.

## Tags

category: workflow-patterns
module: plugins/soleur/skills/ship
