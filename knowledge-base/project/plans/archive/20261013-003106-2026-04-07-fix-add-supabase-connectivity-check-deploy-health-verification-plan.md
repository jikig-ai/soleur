---
title: "fix: add supabase connectivity check to deploy health verification"
type: fix
date: 2026-04-07
deepened: 2026-04-07
---

# fix: add supabase connectivity check to deploy health verification

## Enhancement Summary

**Deepened on:** 2026-04-07
**Sections enhanced:** 3 (Edge Cases, Context, Acceptance Criteria)
**Research sources:** 3 institutional learnings, GitHub Actions runner environment audit

### Key Improvements

1. Added insight from Docker DNS/CNAME learning -- Supabase connectivity failures in containers are a documented production pattern, reinforcing the need for this check
2. Added note about `jq` availability on `ubuntu-latest` runners (confirmed present)
3. Strengthened the link between this fix and the post-merge verification workflow -- this check completes the deploy verification chain

## Overview

The deploy health verification step in `web-platform-release.yml` (lines 98-121) only checks `status == "ok"` and version match. It does NOT verify `supabase == "connected"`. This means deploys can pass health verification while Supabase connectivity is broken -- as happened with v0.14.9/v0.14.10 where the health endpoint reported `supabase: "error"` for days without being caught by CI.

## Problem Statement

The "Verify deploy health and version" step in `.github/workflows/web-platform-release.yml` currently:

1. Curls `https://app.soleur.ai/health`
2. Checks `status == "ok"`
3. Checks `version == expected`
4. Exits successfully if both match

The `/health` endpoint returns a JSON object with these fields (from `apps/web-platform/server/health.ts`):

```json
{
  "status": "ok",
  "version": "0.14.10",
  "supabase": "connected",
  "sentry": "configured",
  "uptime": 1234,
  "memory": 128
}
```

The `supabase` field can be `"connected"` or `"error"`, but the deploy verification never checks it. A deploy where Supabase connectivity is broken still passes verification.

## Proposed Solution

Add a `supabase == "connected"` assertion to the existing health verification loop in `web-platform-release.yml`. The check should:

1. Extract the `supabase` field from the health response JSON
2. Fail the deploy verification if `supabase != "connected"` after all retries
3. Log the supabase status on each attempt for debugging visibility

### Implementation Detail

In the existing `for i in $(seq 1 30)` loop in `.github/workflows/web-platform-release.yml` (line 98), after confirming `STATUS == "ok"` and version match, add a supabase connectivity check:

```yaml
# .github/workflows/web-platform-release.yml -- "Verify deploy health and version" step
# After the version match check (line 106-109), add:
SUPABASE_STATUS=$(echo "$HEALTH" | jq -r '.supabase // empty')
if [ "$SUPABASE_STATUS" != "connected" ]; then
  echo "Attempt $i/30: supabase not connected (status=$SUPABASE_STATUS)"
  sleep 10
  continue
fi
echo "Deploy verified: version $VERSION running, supabase connected"
echo "$HEALTH" | jq .
exit 0
```

This means the deploy only passes when ALL three conditions are met:

- `status == "ok"`
- `version == expected`
- `supabase == "connected"`

### Edge Cases

1. **Supabase field missing from health response:** The `jq -r '.supabase // empty'` returns empty string, which does not equal `"connected"`, so the check correctly fails and retries.

2. **Supabase slow to connect after container restart:** The 30-retry x 10s loop (300s total) gives Supabase time to become reachable. The health check itself has a 2s timeout per probe (`AbortSignal.timeout(2000)` in `health.ts`).

3. **Sentry status:** NOT checked. Sentry is informational only -- a missing `SENTRY_DSN` should not block deploys. The health endpoint already documents this: "Supabase/Sentry status is informational; a degraded dependency should not cause deploy verification or load balancer health checks to fail." However, Supabase IS a critical dependency (auth, data), so we override that comment for deploy verification specifically.

4. **AGENTS.md heredoc constraint:** The implementation must NOT use heredocs in the YAML `run:` block. The existing step already uses inline bash, so this is fine -- just adding more inline `jq` and `if` statements.

5. **`jq` availability on runner:** The `ubuntu-latest` GitHub Actions runner includes `jq` pre-installed. The existing step already uses `jq` for status and version extraction, so no new dependency is introduced.

### Research Insights

**Institutional learnings that reinforce this fix:**

- **Docker DNS/CNAME resolution failure (2026-04-06):** Production containers failed to resolve the Supabase custom domain CNAME chain (`api.soleur.ai` -> `*.supabase.co`), causing `/health` to report `supabase: "error"` while client-side auth worked fine. This is exactly the class of bug this deploy check would catch -- the container started successfully and served traffic, but Supabase connectivity was broken server-side. See `knowledge-base/project/learnings/runtime-errors/docker-dns-supabase-custom-domain-20260406.md`.

- **Post-merge release workflow verification (2026-03-29):** Five consecutive release runs failed silently after a merge because the deploy verification only checked version, not dependency health. The learning led to the AGENTS.md rule requiring post-merge release verification. This fix closes a remaining gap in that verification chain -- version match alone is insufficient if a critical dependency is unreachable.

- **Canary rollback pattern (2026-03-28):** The deploy uses a canary pattern where the new container is verified before traffic is switched. The health check's supabase probe uses a 2s timeout (`AbortSignal.timeout(2000)`). The 30x10s retry loop in the workflow gives the container 300s total -- more than enough for DNS propagation and initial Supabase connection establishment even in degraded network conditions.

## Acceptance Criteria

- [x] Deploy verification in `web-platform-release.yml` checks `supabase == "connected"` from the `/health` response
- [x] Deploy fails if supabase is not connected after 30 retries (300s)
- [x] Each retry attempt logs the supabase status for debugging
- [x] No heredocs or multi-line strings that break YAML indentation (per AGENTS.md)
- [x] The success message includes supabase status confirmation
- [x] No new dependencies introduced (jq already used by existing step)

## Test Scenarios

- Given a healthy deploy where `/health` returns `{"status":"ok","version":"1.0.0","supabase":"connected"}`, when the verify step runs, then it exits 0 with "Deploy verified: version 1.0.0 running, supabase connected"
- Given a deploy where `/health` returns `{"status":"ok","version":"1.0.0","supabase":"error"}`, when the verify step runs through all 30 retries, then it exits 1 with "Deploy verification failed"
- Given a deploy where supabase transitions from `"error"` to `"connected"` on attempt 5, when the verify step runs, then it exits 0 on attempt 5
- Given a deploy where `/health` response has no `supabase` field (old version edge case), when the verify step runs, then it treats the missing field as not connected and retries

**Integration verification:**

- **Workflow syntax:** `gh workflow view web-platform-release.yml` should parse without errors after the change
- **Dry run:** After merging, trigger a manual workflow dispatch and verify the supabase check appears in the logs

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change.

## Context

- Issue: #1703
- Discovered during #1686 verification
- Health check probe itself was fixed in PR #1698 (switched from anon key to service role key on `/rest/v1/users`)
- PR #1697 changed the health check to query the `users` table instead of `/rest/v1/` root
- Learning: `knowledge-base/project/learnings/integration-issues/supabase-health-check-anon-key-rest-root-20260407.md`
- Learning: `knowledge-base/project/learnings/integration-issues/2026-04-06-supabase-server-side-connectivity-docker-container.md`
- Learning: `knowledge-base/project/learnings/runtime-errors/docker-dns-supabase-custom-domain-20260406.md` (Docker DNS cannot resolve Supabase CNAME -- exact failure mode this check catches)
- Learning: `knowledge-base/project/learnings/2026-03-29-post-merge-release-workflow-verification.md` (silent release failures from incomplete deploy verification)

## MVP

### .github/workflows/web-platform-release.yml

The change is localized to the "Verify deploy health and version" step (lines 94-121). The modified step adds supabase status extraction and verification between the version match check and the success exit:

```yaml
      - name: Verify deploy health and version
        env:
          VERSION: ${{ needs.release.outputs.version }}
        run: |
          for i in $(seq 1 30); do
            HEALTH=$(curl -sf "https://app.soleur.ai/health" 2>/dev/null || echo "")
            if [ -z "$HEALTH" ]; then
              echo "Attempt $i/30: health endpoint unreachable"
            else
              STATUS=$(echo "$HEALTH" | jq -r '.status // empty')
              if [ "$STATUS" = "ok" ]; then
                DEPLOYED_VERSION=$(echo "$HEALTH" | jq -r '.version // empty')
                if [ "$DEPLOYED_VERSION" = "$VERSION" ]; then
                  SUPABASE_STATUS=$(echo "$HEALTH" | jq -r '.supabase // empty')
                  if [ "$SUPABASE_STATUS" != "connected" ]; then
                    echo "Attempt $i/30: version $VERSION deployed but supabase not connected (status=${SUPABASE_STATUS:-missing})"
                  else
                    echo "Deploy verified: version $VERSION running, supabase connected"
                    echo "$HEALTH" | jq .
                    exit 0
                  fi
                else
                  UPTIME=$(echo "$HEALTH" | jq -r '.uptime // "unknown"')
                  echo "Attempt $i/30: version mismatch (expected=$VERSION got=$DEPLOYED_VERSION uptime=${UPTIME}s)"
                fi
              else
                echo "Attempt $i/30: health status=$STATUS"
                echo "$HEALTH" | jq . 2>/dev/null || echo "$HEALTH"
              fi
            fi
            sleep 10
          done
          echo "::error::Deploy verification failed after 300s — expected version $VERSION with supabase connected"
          exit 1
```

## References

- Issue: [#1703](https://github.com/jikig-ai/soleur/issues/1703)
- Related PR: [#1698](https://github.com/jikig-ai/soleur/pull/1698) (health check fix: use service role key)
- Related PR: [#1697](https://github.com/jikig-ai/soleur/pull/1697) (health check: query users table)
- Related issue: [#1686](https://github.com/jikig-ai/soleur/issues/1686) (production verification where gap was discovered)
- Workflow file: `.github/workflows/web-platform-release.yml`
- Health check implementation: `apps/web-platform/server/health.ts`
