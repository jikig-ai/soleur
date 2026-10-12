# Decision Challenges — feat-one-shot-10017-mktemp-tmp-leak

Headless planning session (one-shot pipeline, plan subagent). Per
`plan/SKILL.md` Step 4.5 + Plan Review: Taste/User-Challenge/pending
technical rulings persist here for `ship` Phase 6 to render into the PR
body and file as an `action-required` issue.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Carry `Closes #9341` in the PR body | operator (scope) | assumed YES — the census ledger covers all six #9341-named candidates plus every class-b member under the enumerated dirs, and pays down every session-scoped site; bounded CI-only members get ledger dispositions rather than edits, which matches #9341's own "bounded + gated" framing. If the ship-time read is stricter (all 70 must be edited), downgrade to `Refs #9341`. |
| Phase-4 residual reaper: `soleur-tmp-purge` user timer vs literal systemd-tmpfiles age rule | technical | Ruled by CTO agent, 2026-10-12: ship optional `soleur-tmp-purge.{service,timer}` systemd USER units mirroring the `tmpfs-guard.{service,timer}` precedent 1:1, documenting the tmpfiles alternative and its rejection in `tmpfs-guard-install.md` - tmpfiles `e`/`d` age a matched directory's *contents*, never the top-level entry itself, so the literal route cannot express a count-shaped fix; #6991's ~1,500-false-candidate measurement rules out a blanket `/tmp` age rule, and `--apply` quarantines certain-attribution classes only (bare `tmp.*` stays protected). Dissent: flip if tmpfiles grows a type that reaps matched top-level entries by age, or a post-sweep census shows the covered classes at ~0. |
| `rung2-archive` fix shape: RETURN-trap `rm -rf` vs move under owned scratch root | technical | Ruled by CTO agent, 2026-10-12: `trap '… rm -rf "$_tmp"' RETURN` at the allocation site in `_git_data_rung2_hash_at_sha` (`tests/scripts/lib/git-data-birth-readiness-gate.sh:1440`), with a `/*`-rooted assertion before delete, a self-disarming handler (`trap - RETURN` first statement), removal of the stale `.soleur-owned` marker write, and `prefix:rung2-archive` kept in `tmp-classify.sh` - the tree is consumed function-locally and the sole caller is `$( )` at :1912, so RETURN covers every early-return path; an owned-root move relocates the leak (residue whenever no session root is bound), and the non-allocating `cat-file blob` route is already rejected in-tree (#8397). Dissent: none of substance — the mandated RETURN-under-`$()` probe and per-path residue assertion bound the residual edge. |
| Census enumeration authority: extend lint with `--census-files` vs replicate predicate with grep | technical | Ruled by CTO agent, 2026-10-12: extend `scripts/lint-trap-tempfile-ownership.py` with a `--census-files` population-listing mode riding `census_all` (:1265, the single chokepoint all counters flow through), plus `count(list) == --census` and the mutation-matrix asserts in its test - membership requires `strip_literals`/`strip_comment`, command-position `MKTEMP`, and `TRAP_EXIT` covering `EXIT\|RETURN`, so a parallel grep silently defines a second, drifting census. Dissent: none — enumerator and counter must be one implementation. |
| Advisor consult (plan Step 4.5) | technical | Ruled by CTO agent, 2026-10-12: discharged by the batched ruling spawn — plan sound to implement as written, no architecture gap blocks `work` - load-bearing claims verified against the worktree (producer at `git-data-birth-readiness-gate.sh:1440`, `TRAP_EXIT` RETURN coverage at lint :192, `census_all` chokepoint, `tc_is_protected` bare-`tmp.*` protection, shipped `tmpfs-guard` precedent units, highwater ratchet); do-not-touch dispositions for `session-state.sh`/`workspaces-cutover.sh` confirmed. Dissent: (i) `Closes #9341` downgrades to `Refs #9341` if ship's read requires all 70 class-b files edited rather than dispositioned; (ii) implementer must grep each ledger target for a *prior* `trap … EXIT` before adding one, not just assert absence. |

## Scope Check BLOCKED rows

None — every ask mapped or descoped with justification in the plan's
`## Scope Check`.
