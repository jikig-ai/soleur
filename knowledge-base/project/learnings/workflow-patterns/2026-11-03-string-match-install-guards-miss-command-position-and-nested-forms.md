---
title: Guards that match npm install/npx as raw strings both false-positive on prose and silently miss nested/subcommand-position forms
date: 2026-11-03
category: ci-cd
tags: [workflow-patterns, ci-guards, shell-parsing, review-findings]
---

# Learning: Install-site guards need command-position parsing, not string matching

## Problem

The first draft of `adhoc-npm-install-pin-table.test.ts` scanned for `npm install`/`npx`
as raw patterns. Review reproduced **nine** silent-miss / false-green paths — several
are the natural shapes a future author writes by accident:

- `npm install -g -- lodash` — `--` is end-of-**options** for npm, not end-of-args; a
  parser that breaks on `--` misses the unpinned spec entirely.
- `npm exec --yes pkg@ver` / `npx npm@x install -g foo` — `npm exec` is the npx-equivalent;
  npx running npm nests a second install resolution that also floats.
- `npm --prefix /opt install …` / `sudo -- npm …` / `time -v npm …` — flags before the
  subcommand, `--` at command position, and arg-taking prefix flags borrowed from `env`
  (`-v` eats `npm` as its argument under `time`) all put the real command off `cmd+1`.
- Env-pin binding check: first-match regexes are shadowed by `JUNK_<VAR>:` names,
  commented-out `# VAR:` bindings, and `# see .bun-version` trailing comments that
  satisfy a pin-file check for a floating RHS.
- `npx pkg` "resolves a lockfile" checks must name *which* binding (per-row
  `resolves: [lockfile | same-file-install]`); the union of all lockfiles' package
  keys licenses floats on files that can't reach them.
- Conversely: `&&`/`;` inside quotes (`echo "… && npm install …"`, `die "…"`) is
  prose, and quoted spans must be preserved during tokenization or a quoted `--`
  becomes a fake nested-command boundary.

## Solution

Command-position extraction: split segments on `&&`/`||`/`;`/`|`/`&` **outside
quotes**, consume prefix words (`RUN`, `run:`, `env`+its arg-flags, `sudo`, `exec`,
`time`, `!`, `{`, `(`, env assignments) to find the command word, handle `--` as a
nested-command boundary in both directions (after another command, and at command
position), recurse into `npx npm@x install`/`npm exec`, and anchor env-binding
checks per uncommented line with trailing comments stripped. Anti-vacuity needs
floors near *measured* counts plus sentinel member assertions — a walk that drops
a whole surface class must redden, not pass floors a partial tree still meets.

## Key Insight

A guard whose contract is "no silent floats" must be mutation-tested with the
*plausible* miss-forms, not just the current file contents — every finding above
was a real reproducible line, and all of them passed the naive version green.

## Related

- Merge-queue mechanics re-confirmed (PR #11961): `removed_from_merge_queue` by
  `github-merge-queue[bot]` on regroup is benign — re-queue (`gh pr merge --squash
  --auto`), don't close+reopen; `autoMergeRequest` drops once the queue owns the
  PR; AWAITING_CHECKS with no own group run means a *combined* group is running
  (`gh run list --event merge_group`). CANCELLED jobs in `gh pr checks` on a
  re-pushed head are superseded attempts, not failures — key RED detection on
  current-head run conclusions only.
