---
title: "A conflicted PR runs no suites; merge rather than rebase after an attestation, and stage the resolution before a whole-repo ratchet reads the index"
date: 2026-10-12
category: workflow-patterns
tags: [merge-conflict, ci, ratchet, attestation, unpark-checklist, scope-out, cto-ruling, review]
issue: 9786
pr: 10081
branch: feat-one-shot-9786-strip-plain-id-resolver
---

# Learning: five process traps from parking a reviewed draft (#9786 / PR #10081)

## Problem

PR #10081 is a parked draft: reviewed, attested, and deliberately never merged until an approved
host-replace window. Three review rounds and two attestations later, `gh pr view` read
`mergeable=CONFLICTING`, `mergeStateStatus=DIRTY`. Sibling PRs (#10073, #10107) had landed in the
same template and capture script while the panel ran.

## Solution / Key Insights

1. **A conflicted PR runs no `pull_request` suites, so a parked draft goes silently unverified.**
   GitHub builds no merge ref for a DIRTY PR; the checks that do report are the push-triggered
   ones, and the suites (including the loopback suite whose first real run only CI can give) are
   absent, not failing. Check `gh pr view --json mergeable,mergeStateStatus` at every park point,
   not only before the panel.
2. **After an attestation names commit ids, merge `origin/main` into the branch; do not rebase.**
   `emit-review-trailer.sh` records `Reviewed-Commit:` and the fix-round range by id; a rebase
   rewrites them. A merge commit keeps every id.
3. **Resolve by taking main's file and re-applying your additions, not by splicing interleaved
   hunks.** Upstream had generalised `luks_failed_check` into `inngest_failed_check`; the clean
   resolution was `git checkout --theirs`, then re-adding the new function, its three call sites,
   the five test arms and the floor (36 + 5 = 41, exact).
4. **`git add` the resolved files BEFORE running a whole-repo ratchet.** A resolved but unstaged
   path is still in the index at stages 1, 2 and 3, so a scanner over `git ls-files` counted the
   capture test three times (`fixture-relative-assert` 2 became 6, baseline 2). The baseline
   ratchets down only, and the fix was staging, not editing it. Measuring the file in isolation
   (a one-file temp repo) told apart "my code changed the count" from "the index did".
5. **An operator checklist is a set of claims about other workflows; falsify each against the
   workflow file.** The first unpark checklist (rewritten twice) asked to dispatch the rehearsal
   workflow against the branch, but its environment is main-only; omitted that a replace under
   `INNGEST_CUTOVER_FLIP=done` strands the scheduler until an approval-gated `op=resume` (#7228);
   omitted `dry_run=false` and the confirm token (a default dispatch produces no capture and would
   clear the gate vacuously); and claimed the capture script checks positive evidence it does not.
   Also: only `done` and `flushed` recover, so any other flag value is a STOP.
6. **Route a scope-out dissent by what kind of item it is.** The code-simplicity reviewer
   dissented on filing two of four residuals. One was a recorded design decision (keep an inert
   Terraform input and retire it later): that is a CTO ruling, not an operator question, and the
   ruling pulled it in because a later retirement would change `user_data` again and replace the
   sole scheduler a second time. The other was inside the operator's explicit scope exclusion for
   the run, so it was filed (#10112) with the dissent recorded and a note that it is the first
   candidate if the exclusion lifts.

## Session Errors

1. **Conflict discovered only at pipeline step 5, after three rounds** — Recovery: merge commit
   `ea10352a7e` — Prevention: run `git merge-tree` and read `mergeStateStatus` at each park point.
2. **Resolved files left unstaged during a whole-repo ratchet** — Recovery: `git add` — Prevention:
   stage the resolution first; compare a one-file temp-repo measurement before touching a baseline.
3. **Unpark checklist claims were wrong three times (branch dispatch of a main-only workflow;
   a refusal that "restarts services"; `flushed` needing `op=resume`)** — Recovery: each caught by
   a seat that read the workflow, fixed in the plan — Prevention: for every operational sentence in
   a checklist, name the file that falsifies it and read it before writing it.
4. **A finished review seat kept re-notifying on its own timers** — Recovery: `TaskStop` —
   Prevention: stop a seat whose report is final before editing the worktree.
5. **A no-pathspec `git checkout -q --` (a no-op) and an in-place `sed -i` on my own battery script**
   — Recovery: none needed — Prevention: copy a script before templating it with `sed`.
