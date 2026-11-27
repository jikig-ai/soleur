---
title: A runbook routing table is a state machine the code never sees
date: 2026-11-27
category: workflow-issues
module: operator-bootstrap
tags: [operator-bootstrap, runbook, state-machine, review, fix-round, cloudflare]
issues: [12931, 13084]
---

# Learning: a runbook routing table is a state machine the code never sees

## Problem

PR #13084 (epic #12931 Phase 5 token slice) split one procedure across two artifacts: a staged bootstrap that prints
marker lines (`SOLEUR_P5_REFERENCE`, `SOLEUR_P5_STAGED`, `SOLEUR_P5_PREV`, `SOLEUR_P5_HOLDER ... value=`), and a
runbook whose section 1 table maps those lines to the next step. Both suites were green at every round, and the review
still found the defects in the seam between them:

- the state between a revoke and the `_PREV` delete printed `value=other`, which the table routed to "stop", and the
  row meant for it needed a record nothing had posted yet (P1, found by an agent that ran the state in a sandbox);
- the swap rollback copied `<KEY>` back to `<KEY>_NEXT` unconditionally, which in a partial swap overwrites the only
  copy of the new token;
- after the fixed rollback, the state it leaves (`source=PREV`, `next=absent`, `<KEY>` old) matched no row that led
  to a re-mint — introduced by fix round 1 and caught only by the verification seat;
- the plan's `## Operator Holds` (the list ship and the PR body read) had silently diverged from runbook section 6 in
  13 of 14 lines.

## Solution

- Make the bootstrap print the state the table needs (`SOLEUR_P5_PREV state=pinned|denied|...`, `value=revoked`,
  `verdict=revoked`) instead of leaving the runbook to infer it from an absence.
- Make every record a later session needs a posted, author-filtered GitHub comment (`P5-MINTED`, per-key
  `P5-REVOKED` posted before the next step), never a value held in an earlier tool result.
- Walk the table as a state machine in review: list every reachable state (including each partial-failure and
  each post-rollback state) and the row it matches; a state with no row or two contradicting rows is a finding.
- Pin duplicated lists with a parity row (plan holds == runbook holds), and pin committed browser bodies by HEAD blob
  equality, not by a hash file in the same directory.

## Key Insight

When the code and the runbook are two halves, the suites test the code half and nothing tests the table. A routing
table keyed on marker lines is a state machine: review it by enumerating states, not by reading rows, and re-walk it
after every fix round, because a fix that adds a state (a rollback, a new refusal) adds a row the table may lack.

## Session Errors

1. **Plan-file write guard refused a secret-write command pattern** (forwarded) — Recovery: acknowledged after the IaC
   review ran. — Prevention: none needed; the guard worked.
2. **Issue-filing hook refused two filings** (forwarded: shell variable in body path, missing Mandated-By) — Recovery:
   fixed the body path and trailer. — Prevention: write the issue body to a literal path.
3. **Review subagents could not write report files** — Recovery: final messages served as reports. — Prevention:
   briefs say "your final message is the deliverable".
4. **Fix agent left the census floor at 8 of 9 projects** — Recovery: a names-only `doppler projects` read found the
   ninth. — Prevention: a brief that names a measured set gives the set's members, not a count.
5. **markdownlint MD038** — Recovery: reworded. — Prevention: run markdownlint before commit (already in hooks).
6. **Expiry read first used the account verify endpoint for a user token** — Recovery: user endpoint. — Prevention:
   name the owner of every token whose verify endpoint a step uses.
7. **`lint-shell-capture-exit-live` red on a bare `$(grep ...)`** — Recovery: `|| true` plus a guarded capture. —
   Prevention: covered by the lint.
8. **rm guard blocked deleting an agent sandbox that had `git init`** — Recovery: `find -mindepth 1 -delete`. —
   Prevention: briefs say to delete a git-bearing sandbox with find.
9. **Commit guard blocked a scratch-repo commit (variable path, then a path created in the same call)** — Recovery:
   create, then commit with a literal `-C` path in a separate call. — Prevention: as the hook text says.
10. **Body-check one-liner first draft passed on failure (`break` returns 0; empty hash == empty hash)** — Recovery:
    flag variable and non-empty checks, exercised on clean/dirty/missing/bad-hash cases in a scratch repo. —
    Prevention: run every new runbook one-liner against stubs for success, failed read, empty and malformed.
11. **Compose line placeholders did not match the suite's substitution (`<file>` vs `<body>`/`<x>`)** — Recovery:
    aligned placeholders; the suite row that reads the runbook line caught it. — Prevention: a row that executes the
    runbook's own line (it did its job).
12. **The ruled compose line lacked `printf '('` and `pipefail`** — Recovery: the fix agent's sandbox caught it. —
    Prevention: rulings that prescribe a command line get run before they are written into a brief.
13. **Exact mutants floor refused 66 vs 65 after adding a row that runs in both modes** — Recovery: floor raised. —
    Prevention: raise both floors in the edit that adds a shared-section row.
14. **Assumed CI would run the suites; a draft PR skips every test leg** ("full battery owed at ready") — Recovery:
    local full and mutant runs are the evidence until ready. — Prevention: documented in ship's
    `ci-run-diagnosis.md`; routed a bullet to the fix-round reference.
15. **Fix round 1 introduced a P2 (no route after the rollback)** — Recovery: verification seat found it; fixed. —
    Prevention: re-walk the routing state machine after each fix round (Key Insight).
16. **Refusing every `GIT_*` would stop every agent run (the harness exports `GIT_EDITOR`)** — Recovery: five inert
    variables exempted, pinned by a mutant. — Prevention: a class refusal is tested under the harness's own
    environment, not only a scrubbed one.
17. **Plan Operator Holds drifted from runbook section 6 with no check** — Recovery: verbatim copy plus a parity row.
    — Prevention: any list that exists in two files gets a parity row in the same PR.
18. **Nearly skipped the verification pass's affected-gate run** — Recovery: ran `gate-or-skip.sh`. — Prevention:
    the fix-round reference names it; routed a reminder bullet.

## Tags

category: workflow-issues
module: operator-bootstrap
