# Decision Classes: feat-one-shot-9703-stage-3b-retire-8296-probe

| Item | Class | Ruling |
|---|---|---|
| F1: stray tracked `scripts/*.tsv.n` files carry the 8296 row | technical | Ruled by CTO agent, 2026-10-12: remove the 8296 row from both strays, leave the files, file a one-line follow-up issue to delete them - residual-zero grep needs the rows gone; deleting the strays is scope creep |
| F2: archive Stage 3a plan/spec by script or by hand | technical | Ruled by CTO agent, 2026-10-12: manual `git mv` with the `<YYYYMMDD-HHMMSS>-<name>` naming - archive-kb.sh branch-diff discovery would also sweep this branch's own live plan and spec |
| F3: unchecked box in the legal audit record (L234) | technical | Ruled by CTO agent, 2026-10-12: leave the record untouched; note in the PR body and on #9703 that the condition is met - attestation-class, excluded in 3a too |
| F4: followthrough-convention.md names the retired script | technical | Ruled by CTO agent, 2026-10-12: reword to "the retired #8296 probe", keep the lesson and issue number - a dangling script path fails the residual-zero grep |
| F5: ledger `live_verification` wording | technical | Ruled by CTO agent, 2026-10-12: keep the `unavailable:` prefix, state the cross-read was retired and the heartbeat covers probe silence only, edit that single JSON line - minimises conflicts with #8626 and #10081; verify the ledger test accepts the string |
| F6: when to remove the directive from #9703 | technical | Ruled by CTO agent, 2026-10-12: late, after CI green and immediately before marking ready or enqueuing, with the heartbeat re-confirmed beating; verify by re-reading the body |
| Sentry routing apply on merge (scope item 3) writes `sentry_alert.cron_monitor_failure.monitor_ids` in production | operator (production-mutating) | Authorized by the operator's brief (scope item 3, 2026-10-12): the merge is the apply, stated in the PR body's first line. The #9703 and #8285 directive edits were asked first and approved by the operator before they were made |
| Closing #9703 after merge | operator (production-mutating) | Operator-only by the brief ("Close #9703 only if I ask"): not part of this PR, and tracked by the still-open #9703 itself, so no separate issue is filed |
