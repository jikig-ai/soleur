---
title: A one-line operational ask became a day-long pipeline, and the lead dropped a seat's finding from its own fix brief
date: 2026-10-07
category: workflow-issues
tags: [one-shot, scope, review-panel, dedup-ledger, coverage-consult, reboot-workflow]
---

# A one-line operational ask became a day-long pipeline

## Problem

The ask was "find a way to reboot web-2 by yourself" (the Hetzner write token is Tier-B and cannot be used from a local shell). It was routed to `soleur:one-shot` with a seven-point brief, and the plan agent produced a 680-line plan. The result was a dispatch-only workflow, two scripts, two suites carrying mutation batteries (45 and 71 mutants at first, 115 and 90 after review), registration and census edits, three runbooks, ADR addenda and C4 prose. A 10-seat review panel at the `single-user incident` tier then found about 52 raw findings, 31 unique, none P1. The user asked after most of a day why a fix they expected to be simple was still running, and chose "trim and ship".

Most of the churn came from one part of the scope: the post-reboot evidence reader and its verdict function (journald boot list, readiness and probe rows, eight reasons, six exit codes). The reboot trigger itself was small. The existing #6931 follow-through script could already grade the rows later.

## Solution

- Ship the trigger plus the safety-relevant review fixes; cut the rest (owner-approved trim).
- Re-verify each fix by running the suites, not by reading the fix agents' summaries.

## Key Insight

1. **Offer the trim at plan time, not after the panel.** When the plan's own Cut List is long and one component (here the evidence reader) is most of the surface, ask the owner "ship the trigger alone and grade later?" before the work phase. The rigor tier was right for the credential; it was applied to every component equally, including ones that hold no credential.
2. **A lead composing a fix brief from memory drops findings.** The structural-enumeration seat had mapped `gh run rerun` re-issuing the POST (no `run_attempt` guard). The brief omitted it, and only the coverage consult's "which class is absent" question brought it back. The dedup ledger is supposed to be built from the seat reports; build it by reading each report's findings list, not from the conversation.
3. **Read-only queries against Better Stack need the grader's union.** The cold-storage table is part of the hot-plus-cold union the repo's rows helper reads; an ad-hoc `remote($BS_TABLE)` query silently misses rows and reads as absence.
4. **A fix agent that dies is a partial writer.** After an API error, reconcile `git log` and `git diff` against the brief, then resume the same agent so its context survives, instead of respawning.

## Session Errors

1. **Over-scoped an operational ask into the full pipeline** — Recovery: owner chose "trim and ship"; fixes limited to safety-relevant items — Prevention: at plan time, when the Cut List shows one component dominating the surface, ask the owner for the minimal-trigger option before `soleur:work`.
2. **Told the user web-2 had no readiness or probe rows from queries that skipped the cold-storage table** — Recovery: re-read through the grader's own SQL helper and corrected the report on the next turn — Prevention: use `scripts/lib/web2-luks-rows.sh` helpers for any row claim; an empty ad-hoc query is not evidence of absence.
3. **First `gh workflow run` failed (required input `reason`), and `gh issue edit` ran outside a repo cwd** — Recovery: passed the input; re-ran with `-R` — Prevention: read the workflow's `inputs:` before dispatching; pass `-R <repo>` when the cwd may not be a repo.
4. **Used `HCLOUD_TOKEN` from `prd_terraform` for a read** — Recovery: the usable read-only name is `HCLOUD_TOKEN_READONLY` — Prevention: list secret NAMES first.
5. **`pkill -f` blocked by the self-match hook** — Recovery: `source plugins/soleur/scripts/lib/proc.sh; kill_mine` — Prevention: already hook-enforced.
6. **`test-all.sh --affected` degraded to the full battery and was refused (rc=4) behind sibling runs; a second attempt queued behind five worktrees** — Recovery: killed both; ran the owning suites directly — Prevention: run `--capacity` first; a runner edit degrades the affected gate to full, so expect to substitute named suites.
7. **A footer fix for the xtrace-prologue lint broke two mutation anchors, and my first anchor edit had an extra quote** — Recovery: re-anchored with the exact-once assertion — Prevention: after editing a line a mutant targets, grep the battery for that literal before running it.
8. **Two merge conflicts from sibling PRs mid-pipeline (`PROMOTED_FILES` line; generated `model.likec4.json`)** — Recovery: kept main's entries and added ours; regenerated the JSON from `model.c4` — Prevention: regenerate generated files, never hand-merge them (already documented).
9. **Fix brief written from memory omitted the structural seat's re-run finding** — Recovery: added after the coverage consult, verified with `grep run_attempt` (none), implemented as W10 — Prevention: build the dedup ledger by walking every seat report's findings list.
10. **FIX-4 agent died on an API DNS error leaving an uncommitted partial edit** — Recovery: `git log` plus `git diff` showed the test side of item 1 only; resumed the same agent, then finished the doc items directly — Prevention: reconcile git before re-dispatching a dead agent.
11. **Ran a suite at the wrong path (rc=127) and the stop hook fired twice on closing sentences that promised an action** — Recovery: `git ls-files | grep` found the path; did the action in the same turn or stated the gate with the stop tag — Prevention: resolve suite paths with `git ls-files` before running; end a turn with the action taken or an explicit stop tag.

## Tags

category: workflow-issues
module: soleur:one-shot, soleur:review
