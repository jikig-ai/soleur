# Decision Challenges — feat-one-shot-10017-mktemp-tmp-leak

Headless planning session (one-shot pipeline, plan subagent). Per
`plan/SKILL.md` Step 4.5 + Plan Review: Taste/User-Challenge/pending
technical rulings persist here for `ship` Phase 6 to render into the PR
body and file as an `action-required` issue.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Carry `Closes #9341` in the PR body | operator (scope) | assumed YES — the census ledger covers all six #9341-named candidates plus every class-b member under the enumerated dirs, and pays down every session-scoped site; bounded CI-only members get ledger dispositions rather than edits, which matches #9341's own "bounded + gated" framing. If the ship-time read is stricter (all 70 must be edited), downgrade to `Refs #9341`. |
| Phase-4 residual reaper: `soleur-tmp-purge` user timer vs literal systemd-tmpfiles age rule | technical | pending - assumed: ship optional `soleur-tmp-purge.{service,timer}` user units + runbook documents the tmpfiles alternative. Basis: the #6991 measurement — pure age on a shared /tmp cannot separate leaked artifacts from authored work; the classifier's attribution is the safer belt. A literal tmpfiles rule would only ever be scoped to soleur-owned name classes anyway. No Agent tool available for the CTO spawn; implementer may re-derive. |
| `rung2-archive` fix shape: RETURN-trap `rm -rf` vs move under owned scratch root | technical | pending - assumed: `trap … RETURN` with a provably-absolute operand (`/*` assertion before delete — the `assert_fixture_dir` idiom). The extracted tree is consumed only inside `_git_data_rung2_hash_at_sha`; moving under an owned root still leaves per-call residue when no session root is bound (the observed leak path). No Agent tool available for the CTO spawn; implementer may re-derive. |
| Census enumeration authority: extend lint with `--census-files` vs replicate predicate with grep | technical | pending - assumed: extend `lint-trap-tempfile-ownership.py` — the population must be printed by the same implementation that counts it (the lint's own merge-base design principle); a parallel grep defines a second, drifting census. |
| Advisor consult (plan Step 4.5) | — | skipped — no Task/Agent tool in this subagent context; plan is a sweep-class cleanup with the risk concentrated in the two do-not-touch landmines already enumerated by #6752. |

## Scope Check BLOCKED rows

None — every ask mapped or descoped with justification in the plan's
`## Scope Check`.
