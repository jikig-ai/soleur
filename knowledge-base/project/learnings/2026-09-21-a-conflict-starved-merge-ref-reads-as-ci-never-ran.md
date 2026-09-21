---
title: "A conflict-starved merge ref reads as 'CI never ran', and a sibling sweep is done when the shape lists match"
date: 2026-09-21
category: workflow-issues
module: plugins/soleur/skills/review
issues: [8325, 8399]
pr: 8416
tags: [ci, merge-ref, sibling-sweep, instruments, ratchets, test-discovery]
---

# Learning: a conflict-starved merge ref reads as "CI never ran"

Post-merge compound for #8416 (archive of the workflow-FSM decision-challenge plan/spec +
the archive-kb partial-run fix), with the #8382 rulings session that preceded it. Merged
`29d2440d4`; postmerge on 2026-09-21: CI green, deploy arm `35548631650` resolved to
`29d2440d4` and its `deploy` job concluded `success`.

## Problem

Five process defects, all the author's, none caught by a gate at the moment they were made.
The most expensive (error 4) cost five syncs and five CI restarts.

## Key Insight

**A green check-set is a statement about the set, and a merge conflict shrinks the set.**
When GitHub cannot build `refs/pull/N/merge` it does not run any `pull_request` workflow at
all. What remains visible are the rows that do not need the merge ref (CodeQL, CLA). The
PR then shows "9 checks, all pass" holding only 3 of the 26 required contexts (`CodeQL`,
`cla-check`, `cla-evidence`) and none of the other 23 — no `test` — which looks
exactly like CI that has not been scheduled yet, not like a conflict. The conflict itself
was phantom (the kb-index merge driver runs locally, not on GitHub), so nothing local
reported it either. Read `mergeStateStatus` and the required-context intersection before
reading a check count as progress.

**A sibling sweep is done when the SHAPE LISTS that drive the guards match, not when the
guards match.** The `transitions` fail-closed check shipped container-only while its
`sub_steps` sibling asserted members and named the substring-collapse mode; the suite
carried the same asymmetry (5 shapes vs 2). The guards looked parallel; the enumerations
beneath them were not.

## Session Errors

1. **`transitions` fail-closed check container-only vs its `sub_steps` sibling (5 shapes vs 2 in the suite).** Recovery: widened the check and the suite to the sibling's shape list. **Prevention:** when adding a guard beside a sibling, diff the two shape/case LISTS (fixture rows, FATAL modes) line-for-line, not the guard bodies — routed to `work/SKILL.md`.
2. **Added a suite under `skills/*/scripts/`, which `scripts/test-all.sh` `SUITE_GLOBS` deliberately excludes.** `lint-orphan-test-suites.sh` read 0 orphaned in that session; it diffs TRACKED `*.test.sh` against the registration surfaces, so it would flag a committed unregistered suite, but it cannot see one that is not yet staged. The registered-count delta (487→488 after the move to `test/`) is what proved registration. **Prevention:** stage or commit a new suite before reading the orphan report, and assert the registered count moved by exactly the number of suites added. Existing surface: the `SUITE_GLOBS` comment in `scripts/test-all.sh`.
3. **Reddened the repo-global `fixture-relative-assert` ratchet, which references none of the branch's files.** No file-selected suite set could have picked it. **Recurrence** of `2026-09-20-the-gate-that-caught-it-was-the-one-suite-i-had-no-reason-to-run.md` (battery-closure gate). **Prevention:** run the full `scripts/test-all.sh` before the first push, never only the suites the diff names; repo-global ratchets are invisible to diff-keyed selection by construction.
4. **Read a green 9-check set as coverage while it held only the 3 CodeQL/CLA contexts of the 26 required (#7908 shape).** Cause: phantom `INDEX.md` conflict (DIRTY on GitHub, `git merge-tree --write-tree` rc 0 locally) starved the merge ref, which suppresses every `pull_request` workflow. **Prevention:** a pushed head whose required contexts are only CodeQL/CLA (`test` absent) is a `mergeStateStatus` question first — routed to `review/SKILL.md` beside the green-check-set rule (ship/SKILL.md is at its byte ceiling). Existing: `review/SKILL.md` "A green check-set answers a question about the SET".
5. **Four instruments that answered rather than failed:** an `archive/[0-9]+-` grep that could not match the `20260920-163137-` prefix; an rc read from `echo` behind a pipe; `${_have_plan/yes/plan}` rendering "found a nospec"; a Monitor progress grep matching nothing. **Recurrence** of `2026-09-20-every-instrument-that-answered-instead-of-failing.md`. **Prevention:** every new grep/probe gets a positive control against a known-present value before its silence is read; capture rc with `${PIPESTATUS[n]}` or without the pipe.
6. **(This session) The postmerge brief expected "no deploy arm carries a deploy job"; the deploy arm ran and `deploy` concluded `success` on `29d2440d4`.** A carried expectation, not a measurement. **Prevention:** already covered — postmerge Phase 3.7 identifies the arm by its `resolve-target` log; report what the arm did, not what was expected.

## Triage

| item | recurring? | disposition |
|---|---|---|
| 1 shape-list asymmetry | yes | fix-now-inline (work/SKILL.md bullet) |
| 2 non-discovery suite dir | yes | covered by count-delta prevention above; no new rule |
| 3 repo-global ratchet | yes (recurrence) | existing learning + ship full-battery; recorded |
| 4 conflict-starved merge ref | yes | fix-now-inline (review/SKILL.md bullet) |
| 5 answering instruments | yes (recurrence) | existing learning; recorded |
| 6 carried deploy expectation | one-off | recorded |

## Tags

category: workflow-issues
module: review, work
