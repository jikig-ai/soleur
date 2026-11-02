---
date: 2026-10-31
pr: "#11665"
issue: "#11662"
severity: workflow-mechanism
title: Anti-regrow guards — totality counts and synthetic self-checks, not floors; and a vanished worktree almost dirtied main
tags: [test-all, durations, ratchet, enumerate-commands, fixture-isolation, worktree]
---

## Context

Shipped the #11662 anti-regrow guard set (ADR-312): G1 regen drift gate,
G2 corpus committed-weight cap + exemptions ledger, G3 always-on
justifications parity + non-live ceiling, G4 dead-registration census
(lint-orphan surface 7). Two new always-on suites, f1 floor 115→117 paired
with test-all-affected row f1.

## What works / what bites

- **Totality beats floors for census guards.** The first surface-7 draft used
  `s7_checked < 300` / `s7_infra < 50` floors — a producer losing ~60% of
  registrations still passed. The replacement asserts
  `checked + inline == exact SUITE_COMMAND count` (field-1 `awk` match) and
  drives a synthetic dead registration through `_s7_scan` requiring it flag.
  It found a real bug on first run: `grep -c '^SUITE_COMMAND'` also matches
  `SUITE_COMMAND_DECLINED` (shared prefix) — 715 vs 712. Totality counts need
  field-exact matching, never prefix greps.
- **Each mutation arm needs its target predicate as the SOLE red source.**
  Review caught four arms that reddened via unintended predicates (M5 via
  nojust+stale instead of the cap, M7b via over+slack instead of
  minimal-ledger). A "reds" assertion over a contaminated fixture certifies a
  predicate it never exercised — reviewers verify by deleting the predicate
  and watching the suite stay green.
- **Enumerate children inside a suite need the env scrub.** A child
  `bash test-all.sh --enumerate` inherits `SCRIPTS_SHARD`/`TEST_GROUP` and
  emits a subset — the P0 shape: a suite that reds on its own shard leg, or
  worse, certifies a subset within floor slack. Copy lint-orphan's
  `env -u TEST_GROUP -u SCRIPTS_SHARD -u SOLEUR_ENUM_DEADLINE_S` prefix.
- **A recorded ack must be re-emitted while its violation set is identical,
  and a new ack must REPLACE the stale stamp.** `return digest if
  allow_growth else None` evaporated the recorded `# growth-acked=` stamp on
  the non-incremental write path; the `not any(...)` append-guard made a stale
  stamp never-supersedable on the incremental path. Both halves of the scoped
  ack have to move together.
- **`git show <base>:<blob>` failure is not "blob absent"** — returning None
  for any non-zero rc turned a couldn't-measure into a bootstrap pass. Check
  `"does not exist" in stderr`; die on everything else.
- **The `adr:` frontmatter key is hard-blocked** by
  `scripts/check-adr-ordinals.sh` (the filename is the authoritative ordinal,
  #6800). New ADRs take `status: adopting`, `supersedes:`, `related:`,
  `related_adrs:`, `tags:` — no `adr:` key.
- **A worktree can be reaped mid-session** (this one was, by an external
  cleanup). `cd <worktree>` then fails — and because bash executes the
  remaining lines, the next commands ran in the MAIN checkout. Damage was nil
  only because both operations happened to no-op there. Chain `cd` with `&&`,
  or set -e and verify `pwd` after cd, in any multi-command exec against a
  worktree. Recovery: `git worktree add <path> <branch>` restores it.
- **`[[ x =~ #re ]]` silently comments**: an unquoted `#` at word-start inside
  `[[ ]]` begins a comment — `=~ "#"[0-9]+` is the fix. bash -n flags it only
  as a syntax error in some positions.
- **Instrument self-test isn't an assertion**: counting it in `cases` while
  netting the counters to zero broke `pass_n + fails == cases` conservation.

## Session Errors

- **Worktree reaped mid-command → commands ran in the main checkout** —
  Recovery: verified main clean (both ops no-op'd), recreated the worktree —
  Prevention: chain worktree `cd` with `&&` in every exec batch.
- **`SUITE_COMMAND` prefix count included DECLINED rows** — Recovery:
  field-1 `awk '$1=="SUITE_COMMAND"'` — Prevention: totality denominators
  always use field-exact matching.
- **Three contaminated fixture arms + two vacuous predicates** — Recovery:
  isolated fixtures (each predicate sole red source) + new arms for
  stale/empty/word-boundary — Prevention: derive each arm's fixture so the
  named predicate is the only possible red.
- **P0: enumerate children unscrubbed shard env** — Recovery:
  `env -u` prefix mirroring lint-orphan — Prevention: any child enumerate
  inside a suite carries the scrub.
- **fixture-relative-assert baseline drift (+2 legit sites)** — Recovery:
  `--write-baseline` in the same branch — Prevention: run the fixture
  ratchets after adding .test.sh files that write under mktemp roots.
