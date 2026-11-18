---
title: "An acceptance criterion contradicted the edit its own plan prescribed, and a renewal record claimed a future fact"
date: 2026-11-18
category: workflow-issues
tags: [plan, acceptance-criteria, legal-records, supersession, encryption-posture]
related: [12742, 12884, 12895, 12887]
---

# Learning: an AC that contradicts the prescribed edit

## Problem

PR #12884 renewed the leg-2 Inngest accepted-risk exception, ledger row 6, to 2026-12-10. Review found no P1 issues, but it found five P2s.

- **AC7 could never pass.** It required runbook and ADR diffs with no `-` line. Phase 4 step 2 of the same plan prescribed an in-cell append to a markdown table row, which rewrites the row. Task 4.3 was ticked anyway.
- **The record stated a future fact as done.** It said the merge-day re-read "is recorded in the body of PR #12884" while that body was still a placeholder.
- **"Met" and "not discharged" in one sentence.** The runbook's precondition-4 marker used both for the same record. They mean opposite things in this corpus.
- **A dead date read as live.** The runbook #10538 cell kept "the 2026-12-10 extension is dead", and its new marker said "now runs to 2026-12-10". Nothing distinguished the dead 2026-11-02 conditional extension from the 2026-11-17 renewal.
- **The record left out when the owner answered.** The owner's renewal (16:54:35Z) came before the 2026-11-16 leg-1 event was first measured (about 17:06Z). The record did not say so, or that the owner may withdraw.

The sweep also missed one twin outside the files it opened. A public follow-through probe still printed that 2026-12-10 is a conditional extension (#12895).

## Solution

All five P2s were fixed before merge. The fixes are in commit 7ca2fd51f6.

- **AC7** now carves out the in-cell row and gives the exact filtering grep.
- **The record** now says the re-read is "to be written in the PR body before enqueue; absent means none was made". It also states that the answer came before the event and that the owner may withdraw.
- **The markers** now say "superseded, not discharged". They name the dead extension and the renewal as two separate things.
- **The probe text** is a code change. It is tracked in #12895 rather than widening an exception-only PR.

## Key Insight

Check every "additions only" acceptance criterion against the edits the plan itself prescribes. In markdown, a table cell and a frontmatter field cannot be appended to without rewriting their line. Words that assert legal status ("met", "recorded", "runs to") need the same care. Write them for the state at merge time, and keep the dead mechanism and the live one in separate sentences.

## Session Errors

1. **The scratchpad was cleared on restart, so `tls.jq` was gone.** Recovery: restored it from the plan's jq block. **Prevention:** keep any read-only query a plan relies on inside the plan, as this one did.
2. **`PUSH_RC=1` was grep's exit code, not the push's.** Recovery: confirmed the push with `git rev-parse` against the origin branch. **Prevention:** capture `$?` right after the command that matters (work skill rule).
3. **A two-dot diff against origin/main showed main's newer files.** Recovery: re-checked from the merge base. **Prevention:** use `origin/main...HEAD` (three dots) for the scope of a PR.
4. **AC7 contradicted the prescribed in-cell edit.** Recovery: rewrote the AC with a carve-out. **Prevention:** the plan sharp edge added in this PR.
5. **The filing hook blocked twice.** First, the body file was written in the same command. Second, the filing had no exit. Recovery: wrote the file first, then filed with `meta/machinery`. **Prevention:** write the body file in its own step. Choose the filing exit before calling `gh issue create`.
6. **A Stop hook fired while I waited on agents.** My closing text promised an action. Recovery: ended with a `Paused:` line. **Prevention:** while waiting, end with the `Paused:` label, not a promise.
7. **The record claimed the merge-day re-read "is recorded" before merge.** Recovery: reworded it as a future step. **Prevention:** existing learning `2026-09-15-my-legal-record-said-the-change-had-landed-inside-the-pr-that-lands-it.md`. Grep new records for present-tense claims about this PR.
8. **The supersession sweep missed live twins.** They were the probe script, runbook item 6 and counsel-review line 31. Recovery: marked them, or tracked them in #12895. **Prevention:** grep the subject repo-wide (`2026-12-10`, "extension"), not only the files in the diff (work skill "PROPAGATED" rule).
9. **`markdown-lint.sh` was run with no arguments and printed its usage error.** Recovery: passed the changed `.md` paths. **Prevention:** read a script's usage line before calling it.
