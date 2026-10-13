# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-3033-canary-layer3/knowledge-base/project/plans/2026-04-29-fix-canary-layer3-mount-and-bundle-discovery-plan.md
- Status: complete

### Errors
None

### Decisions
- Drop the docker `-v apps/` mount approach in favor of the `terraform_data.deploy_pipeline_fix` file-provisioner pattern shipping the script to `/usr/local/bin/canary-bundle-claim-check.sh`. The issue's proposed mount fix would mount an empty path -- `/mnt/data/apps/` is never populated. `CANARY_LAYER_3_SCRIPT` default updated accordingly.
- Mirror PR #3029's preflight Check 5 dynamic-chunk-discovery pattern in the canary script (cap-of-20 traversal, path-validation regex, `--max-time`/`--max-filesize` hardening, redirected-stdin `while read` loop) -- same load-bearing semantics scaled to the canary's localhost target.
- Preserve the `canary_layer3_jwt_claims` reason-string contract in ci-deploy.sh state file (cross-repo blast radius via `cat-deploy-state.sh` <-> `reusable-release.yml` substring match). Route specific failure reasons through journalctl side-channel via `logger -t "$LOG_TAG" -p user.warning` with `${PIPESTATUS[0]}` rc-preservation.
- Keep `set -uo pipefail` (NOT `-euo`) -- chunk-traversal loop intentionally tolerates per-iteration failures; `-e` would re-introduce the brittle behavior. Pinned in Acceptance Criteria + Sharp Edges.
- Single new test file `canary-bundle-claim-check.test.sh` with 13 fixtures (F1-F13) covering both bundle layouts, all SKIP-vs-FAIL matrix rows, and a log-injection guard test (F12). OS-allocated ephemeral port via python3 for parallel-CI safety.
- Out-of-scope discovery: `/mnt/data/plugins/soleur` mount is also empty in production despite app code referencing `/app/shared/plugins/soleur`. Tracked as follow-up issue.
- Plan threshold: `none`. `requires_cpo_signoff: false`.

### Components Invoked
- gh issue view 3033
- Read / Bash / Edit / Write for repo investigation and plan authoring
- Live curl against https://app.soleur.ai/login for current bundle-layout verification
- skill: soleur:plan
- skill: soleur:deepen-plan
