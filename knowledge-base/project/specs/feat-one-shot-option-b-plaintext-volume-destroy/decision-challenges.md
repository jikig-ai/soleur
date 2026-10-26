# Decision Challenges — feat-one-shot-option-b-plaintext-volume-destroy

Persisted by plan-review (headless). `ship` renders this into the PR body.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Destroy workflow concurrency group | technical | Ruled by CTO agent, 2026-10-26: workflow-level `terraform-apply-web-platform-host` (R2 state serializer, no state lock) plus job-level `git-data-state` (mutex with cutover, rung-2 and root-key workflows), the shape `apply-web-platform-infra.yml:3743-3745` and `:5677` already use. Supersedes the earlier `git-data-state`-only ruling. The runtime cutover-polling assertion is dropped. |
| Merge ordering vs flip retry | technical | Ruled by CTO agent, 2026-10-26: merge only after the flip retry and any rotate it needs are done, because merging disables the git-data host rotate/replace/create routes (their gates demand the retired addresses). Recorded in Owner actions, runbook and ADR. |
| Replace/birth/rotate gates and `-target` lines | technical | Ruled by CTO agent, 2026-10-26: left byte-unchanged in this PR (brief rule 4; the parity test pins workflow `-target` lines, gate allow-sets and constants equal). `-target` on an absent address exits 0 (measured on 1.9.8 by the architecture seat). The disabled capability is a deliberate deferral, tracked by a filed issue, not "fails closed, fine". |
| Dangling `git_data_volume_id = "106867358"` literal | technical | Ruled by CTO agent, 2026-10-26: stays until a deliberate host replace sets `""`; sequenced behind the gate-retirement issue; `SOLEUR-DEBT:` marker at the call site with a trigger. |
| Fold the structural workflow test into `terraform-target-parity.test.ts` and the gate test | technical | Ruled by CTO agent, 2026-10-26 (and DHH/simplicity seats): applied — one new test file fewer. |
| Short-circuit "already destroyed" in the workflow, not the gate | technical | Applied (spec-flow + Kieran seats): the gate keeps refusing a missing `resource_changes`; the workflow skips plan/gate/apply when the pre-plan read proves the volume gone. |
| Drop the `confirm` token | taste | Not applied — owner-requested scope (DHH seat suggested dropping it; it is cheap and was asked for). |
| Split plan job from approval-gated apply job so the reviewer sees plan counts before approving | taste | Not applied in this PR — the gate runs before apply in the same job; the reviewer approves typed pins and a pinned plan gate. Candidate follow-up if the owner wants plan-before-approval. |
| Drop the pre-plan Hetzner read (DHH seat) | taste | Not applied — the read feeds the already-gone short-circuit and the partial-apply state table. The pre-plan LUKS check is trimmed (post-apply check kept). |
| Reviewer independence | taste | Recorded honestly in the ADR: `prevent_self_review=false`, so the owner can dispatch and approve their own run; the typed pins and the gate are the controls outside that approval. |
