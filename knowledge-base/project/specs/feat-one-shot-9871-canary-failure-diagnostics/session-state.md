
## Work Phase
- Implemented: CANARY_DIAG bundle in ci-deploy.sh (two call sites), 29 test rows, runbook subsection, BASELINE_DECLARED_PROBES 52 -> 53 (main was already 52).
- ci-deploy.test.sh 551/551; fixture ratchets, capture-exit lint, guard-vacuity-floor, preflight-discoverability (179) green.
- Mutation battery (in-place + copies): M1 call removed, M3 diag after teardown, M4 unscrubbed, M5 no exec timeout, M7 faithful guard dropped all killed by intended rows; M6 (no read cap) killed only by a D3c hang; M2 (call without || true) killed only by the source census D5d (the function cannot fail).
- Local affected gate not run to completion: queued behind sibling worktrees at load; CI is the merge gate.
