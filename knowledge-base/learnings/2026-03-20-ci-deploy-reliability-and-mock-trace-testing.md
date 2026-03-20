# Learning: CI deploy reliability and mock trace testing

## Problem

Release workflows failed ~20% of the time with `no space left on device` during `docker pull` on the production server. Docker images accumulated without cleanup because `ci-deploy.sh` never pruned old images. Additionally, failed deploys could not be retried because the deploy job gated on `released == 'true'`, which was `'false'` when the release already existed.

## Solution

1. Added `docker system prune -f --filter "until=48h"` before `docker pull` in both component blocks of `ci-deploy.sh`
2. Changed deploy `if` from `needs.release.outputs.released == 'true'` to `needs.release.outputs.version != ''` — version output is already populated before the idempotency check in `reusable-release.yml`
3. Added shared `deploy-production` concurrency group to serialize deploys to the same server
4. Added `paths:` filters to reduce no-op workflow triggers

## Key Insight

**Deploy retry via output flow analysis:** When a reusable workflow has both idempotency checks and downstream consumers, trace the step execution order to find outputs that survive the idempotency gate. In `reusable-release.yml`, the `version` step runs before the `idempotency` check, so `version` output is set even when the release already exists — only the `released` output is blocked. Gating on `version` instead of `released` enables retry without any changes to the reusable workflow.

**Mock command ordering verification:** When testing that a bash script calls commands in a specific order (prune before pull), avoid temp files and PATH corruption. Instead, have the mock print trace markers to stdout (`echo "DOCKER_TRACE:$1"`), then grep the captured output for ordering. An earlier attempt using a temp trace file failed because `export PATH="$MOCK_DIR:\$PATH"` with escaped `$PATH` set PATH to the literal string `$PATH`, breaking all subsequent commands (`grep`, `head`, `cut`, `rm`). Stdout trace markers are simpler and immune to PATH corruption.

**`skip_deploy` preservation:** When changing a compound `if` condition, check every clause. The web-platform deploy had `released == 'true' && (... || !inputs.skip_deploy)` — changing only the first clause without preserving the second would silently remove the skip_deploy capability. Plan review caught this omission.

## Session Errors

1. Security reminder hook blocked the first Edit on each workflow file (3 occurrences) — expected behavior, resolved by retrying
2. Test mock PATH corruption: `\$PATH` escaping in heredoc-like context produced literal `$PATH` instead of expanded value, breaking subshell commands. Fixed by switching to stdout trace markers.
3. SpecFlow analyzer false positive: claimed all workflow files don't exist (searched from wrong directory context)

## Tags
category: ci-cd
module: .github/workflows, apps/web-platform/infra
