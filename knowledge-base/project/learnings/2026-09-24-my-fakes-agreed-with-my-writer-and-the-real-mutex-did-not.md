---
title: My fakes agreed with my writer, and the real mutex did not
date: 2026-09-24
category: test-failures
tags: [dev-supabase, migrations, ledger, test-fakes, mutation-testing, psql, adr-061]
pr: 8642
issues: [8605, 8606]
---

# Learning: my fakes agreed with my writer, and the real mutex did not

## Problem

PR #8642 added `dev-ledger-reconcile.sh`, a CI writer that discards a closed PR's applied-but-unmerged
migrations from the shared dev ledger. After the first implementation, 194 of 194 cases passed. The
11-agent review panel then found, among others:

- **A real bug the suite could not see.** The writer read the dev-suite mutex banner with
  `grep -m1 '^DEV_SUITE_MUTEX_[A-Z_]+'`. The real `scripts/dev-suite-mutex.sh acquire` prints
  `DEV_SUITE_MUTEX_WAITING` before `DEV_SUITE_MUTEX_ACQUIRED` whenever it waits, so the writer refused
  a lock it held. That is exactly the contended case its 600 s wait exists for. The fake mutex
  printed one line, so no case could observe it (test-design seat, reproduced with a two-line banner).
- **14 surviving mutants**, every one reaching a named property. Examples: dropping `-f state=all`
  (GitHub defaults to `state=open`, so the #8605 bug returns) survived because the fake `gh` ignored
  `state=`. `ON_ERROR_STOP=0` appended after `=1` survived because the fake `psql` did not apply the
  last value. A new step checking out `refs/pull/N/head` survived because the workflow pins matched
  substrings of the checkout step only.
- **A refusal that was a client-side re-lex of SQL.** The python classifier that refused `COMMIT`,
  `COPY` and `CASCADE` in a PR's `.down.sql` tokenized dollar quotes differently from Postgres (`$`
  after a high-bit identifier byte). The security seat got `COMMIT` and `CREATE INDEX CONCURRENTLY`
  through on a real PG16, and `COPY … FROM STDIN` swallowed the rest of the `-f` unit while the
  writer reported success.
- **A fail-open in a fail-closed classifier.** A 200 response whose PR objects lacked `state`,
  `head.sha` or `number`, or a page of exactly 100 PRs, reduced to `none` (so `in-flight`, a
  warning), not exit 2.

## Solution

- Make each fake model the real contract, not the writer's reading of it. The fake mutex prints
  WAITING then ACQUIRED with the real `::warning::` shapes and tracks the holder state file. The fake
  `gh` honours `state=` (default `open`) and `per_page`, and lists newest first. The fake `psql`
  applies the last `-v ON_ERROR_STOP`. The suite went from 194 to 256 cases, and all 14 mutants are
  killed (`mutations-8642.md`, scratchpad).
- Enforce on the server, keep the lexer as a mistake-guard. Each down body runs as
  `DO $t1$ BEGIN EXECUTE $t2$<body>$t2$; END $t1$;` with random tags checked absent from the body.
  PL/pgSQL `EXECUTE` rejects transaction control and client `COPY`, and `CONCURRENTLY`/`VACUUM`
  fail inside the transaction block. This was verified on a throwaway postgres:16-alpine against both
  bypass payloads, each failing atomically with nothing committed. After `psql`, the writer re-reads
  the ledger and checks each claimed discard.
- Shape-check every field the reduction reads, and treat a full page as could-not-measure.

## Key Insight

A fake is a claim about the real dependency's contract, and it is written by the same person who
wrote the consumer, so it encodes the consumer's reading. A consumer bug that lives in the gap
between that reading and the real contract is invisible to every case. The cheapest mutation axis is
the fake itself: replay the real tool's multi-line output, its defaults and its last-value-wins
flags. Separately, a refusal computed by re-lexing a language the server parses is a mistake-guard,
never a security control. Put the enforcement where the parse happens.

## Session Errors

1. **The planning subagent stopped on a usage limit (HTTP 429), and the resumed checkpoint had no
   Research Insights** (forwarded from session-state.md). Recovery: one re-run finished plan and
   deepen-plan in place. **Prevention:** none beyond the existing re-run-once rule; platform limit.
2. **The plan draft carried design defects that its own review caught** (forwarded):
   - `jq @base64d` failed on line-wrapped base64;
   - psql runs backslash meta-commands from `-f` (P0 on a `pull_request_target` runner);
   - the refusal regex matched 51 of 95 downs;
   - the fake psql was blind to `-f` payloads;
   - the close path failed silently.

   Recovery: folded in before work. **Prevention:** already covered by plan review; no change.
3. **markdownlint MD038/MD032 in the plan** (forwarded). Recovery: fixed before commit.
   **Prevention:** existing plan-sharp-edges bullet (lint plan and tasks.md before the summary).
4. **The Phase 1 commit hung in lefthook's bun-test full battery**, which tested the in-progress tree.
   Recovery: killed the process tree, re-committed with `LEFTHOOK_EXCLUDE=bun-test`.
   **Prevention:** `work/SKILL.md` already documents the exclusion; check for a surviving hook
   process before any git-write retry (existing rule).
5. **A `run_in_background` poll was blocked by a hook.** Recovery: Monitor.
   **Prevention:** hook-enforced (`hr-monitor-not-run-in-background-for-polling`).
6. **The primary working directory was reset to the repo root twice.** Recovery: absolute worktree
   paths. **Prevention:** existing practice (absolute paths in worktrees); one-off.
7. **PR #8602 went red on battery-tag-authorship** (five fixture fetches lacked `--no-tags`), then
   CONFLICTING on the `PROMOTED_FILES` union. Recovery: added `--no-tags`; merged main.
   **Prevention:** run the repo-global ratchets on any diff adding a fixture fetch (existing
   file-selected-suite rule in `work/SKILL.md`).
8. **The WAITING-before-ACQUIRED mutex bug and 14 surviving mutants shipped green through 194 cases**
   because the fakes modelled the writer's reading of the contracts. Recovery: fakes rebuilt on the
   real contracts; 256 cases; all mutants killed. **Prevention:** plan-sharp-edges bullet (routed in
   this PR): a plan prescribing a fake must name the real contract's multi-line output, defaults and
   last-value-wins flags it replays.
9. **A client-side SQL re-lex was used as the refusal control and was bypassable** (proven on PG16).
   Recovery: server-side `EXECUTE` wrapping plus a post-psql ledger re-read. **Prevention:** ADR-061
   amendment states the classifier is a mistake-guard, not a security control.
10. **The classifier failed open on a 200 with incomplete PR objects and on a 100-item page.**
    Recovery: both exit 2. **Prevention:** the existing readiness-gate sharp edge (decide from a
    positive, shape-checked count) covers it; the suite now pins both.
11. **The code agent hit a usage limit (429) mid-run.** Recovery: resumed with SendMessage; its
    partial edits were intact on disk. **Prevention:** none; resume rather than respawn.
12. **The docs agent and the code agent wrote divergent output tokens**
    (`refused merged` vs `refused (pr=N reason=merged)`, and the unit statement order) because the
    docs agent wrote against the ruling in parallel, not against the code. Recovery: the lead grepped
    the docs for the divergences the code agent reported and aligned them. **Prevention:** when docs describe
    tokens a concurrent code agent will emit, run the docs pass after the code lands, or grep the
    docs for the code's emitted literals before committing.
13. **The new label `ci/dev-ledger-reconcile` did not exist** (`gh api …/labels/…` returned 404).
    The workflow creates it best-effort on first filing. Recovery: created it via REST before merge.
    **Prevention:** one-off.
14. **The fixture-relative ratchet was already red at the branch's first writer commit** (8 flagged
    paths, no baseline). The code agent found it while fixing. Recovery: fixed in code to 0.
    **Prevention:** existing rule (a file-selected suite set cannot see a repo-global ratchet).
15. **The docs agent named `scripts/lint-diagnosis-claims.py`; the script is `.sh`.** Recovery: it
    located the real runner via `scripts/test-all.sh`. **Prevention:** one-off; briefs should name
    ratchets by their `run_suite` line.
