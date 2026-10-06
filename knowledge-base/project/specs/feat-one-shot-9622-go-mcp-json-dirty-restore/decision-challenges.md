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

## Deepen-plan additions (2026-10-06)

8. **Pre-existing arbitrary-path write via a `.mcp.json.soleur-tmp` symlink** (security-sentinel, medium). A hostile repo that tracks that
   symlink plus a `.mcp.json` on main makes `git show main:.mcp.json > .mcp.json.soleur-tmp` write main's bytes through the link. The
   one-line fix (`rm -f .mcp.json.soleur-tmp` before the redirect) sits inside the restore block but answers no ask, so it was NOT applied.
   Recommend applying it in this PR or filing a follow-up issue.
9. **Untracked `.mcp.json` that differs from main is still overwritten** (spec-flow gap 4). Same loss class as #9622; the brief's
   "untracked -> existing behavior" and ask 9 pin it, and R12e asserts it. Option: keep untracked-and-differing files too (skip with the
   marker; restore only an absent file). Decide whether to change the brief.
10. **Byte-compare guard alternative** (security-sentinel): decide dirtiness by `git cat-file blob HEAD:.mcp.json | cmp -s - .mcp.json`
    instead of index state. It would also cover clean filters and a staged deletion, at the cost of a `cmp` dependency and a different
    failure shape. The applied fix covers `skip-worktree`/`assume-unchanged` and symlinks through `ls-files -v` and `[ -L ]` instead.

## Review-phase additions (2026-10-06)

11. **Steady state after the gate's own refresh (accepted trade-off).** Architecture, code-quality and test-design all observed that a
    refreshed stale tracked file differs from HEAD, so once `main` moves on it is KEPT, never refreshed again, and the marker prints
    every session although nobody edited it. Fixing it needs state (a recorded hash of the gate's own write) or option 7 above, both
    rejected at plan time. Applied instead: the marker carries `cause=differs-from-head`, and the prose after the fence says plainly
    that this includes a stale copy the gate refreshed earlier and that an agent must not run `git checkout`/`update-index` on it.
12. **#8 applied.** The temp-path symlink write is inside the restore block and a one-line `rm -f`; the security seat re-confirmed it
    and it now has a row (R12n).
13. **Writers outside the restore block (not applied: outside the operator's stated scope).** `worktree-manager.sh cleanup-merged`'s
    non-bare tail (`reset --hard HEAD`, `sync_bare_files` `checkout-index -f`) and `AGENTS.rules.md` rule
    `wg-at-session-start-after-cleanup-merged` (prescribes the unguarded `git show main:.mcp.json > .mcp.json`) can still overwrite a
    tracked, dirty `.mcp.json`. Tracked in #9663. (The cwd-relative write from a subdirectory was inside the block and is fixed: R12o.)
