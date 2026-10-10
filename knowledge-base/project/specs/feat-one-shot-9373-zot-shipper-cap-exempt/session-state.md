# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-10-fix-zot-shipper-cap-exempt-patchblobupload-func-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
None. A read-only registry-replace-preflight.sh run was left in its P3 drain-wait by the planning subagent; the real pre-merge run is the last gate before enqueue.

### Decisions
- Cap-exempt the PatchBlobUpload error line via the parsed `func` field (message-prefix arm matched zero rows in 7 days); keep benign `unexpected EOF` rows as evidence.
- Route the func-keyed row through the upload sub-quota (return code 2), not the shared lane.
- Parameter named `local func="$2"` for the closing probe; user-data tripwire bumped to about 21,600 B.
- Fix the same dead message-prefix counter in zot-fill-rate-7341.sh; refresh stale comments in zot-upload-ceiling-7556.sh and the runbook.
- Post-merge: new boot_id (pre-replace 04d90de2-...), zot_restarts=0, log_shipper_post_fail=0; 7341 reported "not yet observable" until 24 h of history.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; agents learnings-researcher, repo-research-analyst, dhh/kieran/code-simplicity reviewers, cto.
