# Decision challenges: #9622 plan review (2026-10-06)

Persisted by plan-review (headless). Taste / user-challenge findings were NOT auto-applied.
Mechanical findings were applied to the plan.

## Taste

1. **Cut R12c / R12d (capability-refusal and classifier-absent arm rows).** DHH and the simplicity
   seat: the guard has no arm-specific code, so R12 covers all arms by construction. Kept: the Guard
   Contract's assembly names three `DO_RESTORE` arms, and the CTO seat judged the cost justified.
2. **Cut R12f (unborn-HEAD rows).** Simplicity seat: the code form already embodies the policy.
   Kept: it is the only row that pins "any non-zero probe status keeps the file" and the `ls-files`
   conjunct, and Kieran and DHH retained it.
3. **Trim the Guard Contract** (drop mutations 4, 5, 6, the H-a/H-b rows, the Anchor paragraph).
   DHH and the simplicity seat. Kept in full because plan Phase 2.12 requires the section.
4. **Flip the fixture default** (make `stale` the default, `dirty` opt-in). Kieran P2.1 and the
   simplicity seat. Kept `dirty` as default with named modes and a loud comment, to avoid running ~30
   indifferent rows on a different branch; revisit if the footgun bites.
5. **Equal-to-main silent branch** (CTO option 1) to stop a recurring false `mcp-json-dirty` after the
   gate's own refresh. Cut as YAGNI; CTO accepted option 2 (the prose remedy names the self-refresh case).
6. **Single-probe `git status --porcelain` form.** Simplicity seat noted it and did not recommend it
   (a failing status reads as clean and overwrites; loses fail-toward-keeping).

## User-Challenge

7. **Stop refreshing TRACKED `.mcp.json` entirely** (restore only untracked files). DHH, CTO and Kieran
   P2.3 each observe that the refresh of a tracked file is the root of the self-disabling refresh and of
   the status-quo revert-on-commit hazard, and that it would delete the `HEAD` probe, the exit-code
   policy, the stale fixture and five re-points. It contradicts the stated ask "a clean-tracked/untracked
   row still restoring", so the operator's direction was kept. Decide whether to file a follow-up issue.
