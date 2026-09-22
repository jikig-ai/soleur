---
title: "The record PR was inert at merge except for a comment edit and a probe that aged into a false reopen"
date: 2026-09-21
category: workflow-patterns
module: encryption-posture / follow-through probes
issue: 8296
pr: 8514
tags: [follow-through, notify-only, merge-side-effects, encryption-posture, article-30, review]
---

# Learning: a "merging mutates nothing" PR had two hidden mutations

## Problem

PR-2 of #8296 was scoped to be inert at merge: it flips the encryption-posture ledger row
`hcloud_volume.inngest_redis_luks` to `luks`, amends the Article 30 register, and adds a notify-only
follow-through probe. The plan measured, for its planned file set, that no apply, deploy or image
build fires. Two things broke that property after the plan was written, and neither was visible to
any suite:

1. **A one-line comment fix in `plugins/soleur/test/fixture-relative-assert.baseline.txt`** (a stale
   `:120` line citation) put a `plugins/soleur/**` path in the diff. That path is in
   `version-bump-and-release.yml`'s push filter, and `reusable-release.yml`'s `path_filter:
   "plugins/soleur/"` does not exclude `test/`, so merging would publish a plugin patch release and
   chain a docs deploy. The plan's own AC-G3 union grep includes `plugins/soleur/` and would have
   caught it; it was simply not run before review.
2. **The retained cutover probe `inngest-luks-cutover-6894.sh`** proves a one-time event through
   `--since 48h --grep cutover-complete`. The only such row was 2026-09-20 15:29Z. Its tracker
   #8295 was closed by the operator with `earliest=2026-09-23`, so the first sweep from 09-23 would
   have exited 1 and the sweeper's closed-set path would have **reopened** #8295 with a public
   "verification FAILED" comment, every day thereafter. The plan (R7) had kept it precisely to
   "reopen #8295 if the cutover regresses".

## Solution

- Reverted the baseline comment edit; re-ran the AC-G3 union grep on the final diff (`0`).
- Retired both follow-through directives (#8295, #8294) in the issue bodies with a dated note, and
  rewrote the 6894 probe's RETIREMENT line to say it is inert. The file itself is kept only because
  deleting it would drop a row from the same `plugins/soleur/` baseline and fire a release.
- The review panel (10 agents, report-only against one SHA) also tightened the new property probe:
  host pin on `.host` + `.host_name`, first-wins `host_role`, strict and non-future `dt`, a
  backstop-row count, the xtrace refusal first with the EXIT trap directly after it, and static bans
  on `exec`, `kill` and a second `trap`. Each new guard was mutation-checked red on a scratch copy.

## Key Insight

A PR's "merge is inert" claim is a property of its **final** file set, not its planned one, and a
follow-through probe's claim is a property of its **window**, not its logic. Re-run the push-filter
union on the final diff at work exit, and when a one-time event's tracker closes, retire the
directive rather than trusting the probe to keep PASSing.

## Session Errors

1. **The D1 filing was refused twice by the filing hook** (no `Mandated-By:` line, then a
   `--body-file "$F"` the hook cannot expand). Recovery: appended the mandate line to the body in a
   separate call, then passed a literal absolute path. **Prevention:** already hook-enforced; write
   the body file first, file with a literal path.
2. **markdownlint MD037 on the PA-13 amendment** (`**[… .** …]**` adjacent to an existing dangling
   `]**`). Recovery: self-contained `**[… .]**` header. **Prevention:** close the bold inside the
   bracket when appending next to an existing amendment.
3. **Turns ended on a first-person commitment while background agents ran** (stop-hook fired
   twice). Recovery: ended with an explicit BLOCKED stop. **Prevention:** when waiting on an async
   agent, end with the BLOCKED marker, not "I'll …".
4. **The plan quoted a stale floor (665) for `cutover-inngest-workflow.test.sh`;** it is an exact
   anti-deletion floor at 753 on main. **Prevention:** re-measure plan-quoted floors at work start
   (existing rule).
5. **The plan pinned the register amendment date to the cutover date (2026-09-20)** while the
   amendment's own body records 2026-09-21 events ("only then was this cell amended"). Four agents
   flagged it; relabelled to 2026-09-21. **Prevention:** date an append-only amendment by when it
   is written; put the event date in its body.
6. **A comment-only edit under `plugins/soleur/test/` would have fired a plugin release** (see
   Problem 1). **Prevention:** run the plan's production-reaching push-filter grep (AC-G3) at work
   exit, before review, not only at ship.
7. **The retained 6894 probe would have falsely reopened #8295 from 2026-09-23** (see Problem 2).
   **Prevention:** followthrough-convention.md now says: retire a one-time-event directive when its
   tracker closes, or key on a recurring terminal-state row.
8. **The probe shipped without the plan's host pin and with a loose `dt`/`host_role` parse.** The
   delegated agent documented the omission as a deviation. **Prevention:** the structural-enumeration
   seat found it; the convention runbook now requires pinning `.host` and `.host_name`.
9. **Two bugs in checks I added during review** (a regex that rejected `marker() { # …`; a
   `sed -n "a,bp"` with a > b, which prints line a). Recovery: both surfaced as reds on the first
   run. **Prevention:** guard `sed` ranges with `(( a <= b ))`.
10. **Moving the EXIT trap first conflicted with the credential-refusal lint's prologue rule.**
    Recovery: refusal first (it can only exit 78), trap directly after; the suite pins the order.
    **Prevention:** recorded in followthrough-convention.md.
11. **A Python edit assert failed on raw-string escaping** (`\\(` vs the file's `\(`). Recovery:
    grepped the exact line first. **Prevention:** copy the anchor from `grep -n` output, not memory.
12. **`xxd` is not installed on this host.** One-off.
13. **`lint-shell-trace-credential-refusal.py --changed` scanned 0 files before the commit** — it
    reads committed diffs, so an uncommitted edit reads as a clean pass. **Prevention:** commit
    before running any `--changed` lint, and treat "0 scanned" as not-run.
14. **The squash-merge shut the backstop tracker by accident.** *(Post-merge, 2026-09-21.)* A branch
    commit body wrapped at 100 columns put the keyword `auto-close` at the end of one line and the
    tracker's `#N` at the start of the next. GitHub treats the newline as whitespace, so merging
    `7f7d9c3d9` shut the one issue this PR exists to keep open, and with it the new probe's only
    delivery channel. AC-39b had scanned the PR body only. Ship's commit-message scan did run, but
    `auto-close-scan.sh` greps one line at a time. Recovery: reopened within minutes, with a
    comment. **Prevention:** #8523 adds a cross-line pass to the scanner, with the real text as a
    test. Until it merges, do not wrap a sentence so that a closing keyword ends a line in a commit
    body that names an issue you intend to keep open.
15. **A stray `git checkout origin/main --` detached the merged branch's worktree.** It was harmless
    after merge (post-merge work runs from `origin/main` anyway). One-off.

## Tags
category: workflow-patterns
module: follow-through probes, encryption-posture ledger
