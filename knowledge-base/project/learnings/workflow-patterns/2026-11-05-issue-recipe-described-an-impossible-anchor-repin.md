---
title: "A filed fix recipe was mechanically impossible — verify the oracle's field semantics before planning around the issue's own remedy"
date: 2026-11-05
category: workflow-patterns
---

# An issue's fix recipe was impossible; the oracle's own output is the recipe

## Context

#12110 filed a CI defect (`affected-index-ratchet` red on every PR,
`reason=stale-accept`) with a recipe: "re-pin the accept rows' anchor SHA
field to `git log -1 --format=%H origin/main -- <file>`". Two facts made it
unexecutable:

1. `ci-pr-affected-audit.accept.tsv` col-3 anchors are 12-hex sha256 prefixes
   over `" ".join(line.split())` of the *live boundary line's content*
   (`ci-pr-affected-replay.py:125`), not git SHAs. A 40-hex value fails the
   col-3 `^[0-9a-f]{12}$` validator (:1521-1522) and drops every exemption.
2. `stale-accept` rows are delete-only per the script's own remedy
   (:2056, `--help`) — there is no re-pin path, and no "regenerate" command
   (`--print-baseline` writes nothing to disk).

And third: the issue's named stale rows were no longer the flagged set —
~20h of main drift had replaced them with 11 different stale rows plus 3
`new-pair` findings. The issue's enumeration is a point-in-time snapshot,
never the work list.

## Prevention

- For oracle-file defects (`*.accept.tsv`, baselines, ratchets), derive the
  fix from the oracle's OWN output (`--report`, `ref`/`stale` lines,
  `--all-refs`), never the issue's paraphrase. The report names rows by the
  exact (suite,path,anchor,ordinal) tuple to delete and the exact anchor to
  accept.
- Before believing a recipe naming a file format, grep the producer's
  validator (`ValueError`/`must be` sites in the script) — a field's
  semantics live there, not in the issue.
- On any "main is red" issue older than a few hours, re-run the check
  locally first: the flagged set drifts with every sibling merge, and fixing
  the issue's literal rows can leave the ratchet just as red.
