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

## Work Phase
- Status: complete (implementation + local verification); review, QA, ship follow.
- RED set recorded before the shipper edit (zot-log-shipper.test.sh): T9 x2, T19 floor, T21 S1, S2, S3 x2, S8 (8 failed / 178 passed); GREEN after: 186 passed, 0 failed.
- Guard Contract mutation rows 1-5 (+ raw-line widening variant) each went RED; counters' new cases RED on the old probes (7440 C15b, 7341 case 28).
- user_data: stored 20,944 B -> 21,012 B (+68 B); REGISTRY_GZIP_BUDGET 21,000 -> 21,600; headroom 11,756 B under the 32,768 B cap.
- Local lane disclosure: scripts/pre-push-ratchet-lane.sh REDs only on alarm-issue-filing-guard and lint-workflow-step-env-refs, both ModuleNotFoundError yaml (no PyYAML in the lane env); both pass when run directly with PyYAML on PYTHONPATH. cloud-init is not installed locally, so validate-infra-templates.sh fails closed (rc=6); registry-userdata-budget.sh renders the template through terraform and passed. typecheck, vitest (incl. cloud-init-user-data-size.test.ts) and the broad battery are left to CI (stale node_modules, contended machine).
