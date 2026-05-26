---
title: "feat: post-ship autonomous monitor — CI auto-fix, postmerge chain, Sentry verification"
type: feat
date: 2026-05-26
classification: ops-only-prod-write
lane: single-domain
brand_survival_threshold: none
---

# feat: post-ship autonomous monitor

[Updated 2026-05-26] Applied 3-agent plan review findings: delegated CI auto-fix to `test-fix-loop`, dropped speculative error count comparison, dropped work/SKILL.md phase, fixed token naming, corrected exit-path handling.

## Overview

Close the gap between "auto-merge enabled" and "verified in production" by extending the ship and postmerge skills:

1. **Ship Phase 7 CI auto-fix**: When a required check fails during the merge poll, delegate to `test-fix-loop` then push and re-queue auto-merge.
2. **Ship → postmerge chain**: After merge + release workflows pass, automatically invoke `/soleur:postmerge`.
3. **Postmerge Phase 3.5 Sentry check**: Query Sentry API for cron monitor health.

All changes are SKILL.md edits — no application code, no infra changes. Two files: `ship/SKILL.md` and `postmerge/SKILL.md`.

## User-Brand Impact

- **If this lands broken, the user experiences:** no direct impact — this is operator-side CI/deploy tooling. A broken auto-fix loop could delay a bugfix delivery by one session.
- **If this leaks, the user's data/workflow/money is exposed via:** N/A — reads Sentry API (read-only) and gh CLI (already authenticated). No new write surfaces.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: operator-only workflow automation; no new code paths reach founders; Sentry API token is read-only and already provisioned`

## Implementation Phases

### Phase 0: Verify prerequisites

0.1. Verify `SENTRY_AUTH_TOKEN` exists in Doppler `prd` (canonical name per `sentry-monitors-audit.sh:38`; fall back to `SENTRY_API_TOKEN`):
```bash
doppler secrets get SENTRY_AUTH_TOKEN -p soleur -c prd --plain 2>/dev/null | head -c 10 || \
  doppler secrets get SENTRY_API_TOKEN -p soleur -c prd --plain | head -c 10
```

0.2. Verify Sentry org slug and live-test the monitors endpoint:
```bash
SENTRY_ORG=$(doppler secrets get SENTRY_ORG -p soleur -c prd --plain 2>/dev/null || echo "jikigai")
SENTRY_TOKEN=$(doppler secrets get SENTRY_AUTH_TOKEN -p soleur -c prd --plain 2>/dev/null || \
  doppler secrets get SENTRY_API_TOKEN -p soleur -c prd --plain)
curl -sS -w "\n%{http_code}" -H "Authorization: Bearer ${SENTRY_TOKEN}" \
  "https://${SENTRY_ORG}.sentry.io/api/0/organizations/${SENTRY_ORG}/monitors/?per_page=1"
```
Must return HTTP 200. If 401, token lacks `org:read` scope.

0.3. Verify `test-fix-loop` skill exists and is loadable:
```bash
ls plugins/soleur/skills/test-fix-loop/SKILL.md
```

### Phase 1: Ship Phase 7 — CI auto-fix via `test-fix-loop` delegation

**File:** `plugins/soleur/skills/ship/SKILL.md`

The Phase 7 poll loop has two CI-failure exit paths:
1. **Required-check failure exit** (lines 1114–1130): loop breaks with `required_failed` set, PR is still OPEN, auto-merge still queued.
2. **CLOSED exit** (line 1106 + handler at line 1215): PR transitioned to CLOSED state (rare — merge queue rejection or manual close).

**Replace lines 1215–1225 with:**

```markdown
**If the poll loop exits due to a required-check failure (PR still OPEN) or CLOSED state:**

The agent maintains a `fix_attempt_count` counter (agent-level state, not a bash variable — each Monitor invocation is a fresh shell).

1. Read the failure details:

   ```bash
   gh pr checks <number> --json name,state,description,detailsUrl \
     | jq '.[] | select(.state != "SUCCESS")'
   ```

2. Identify the failing workflow run and read its logs:

   ```bash
   gh run list --branch <branch> --limit 5 --json databaseId,status,conclusion,workflowName \
     | jq '.[] | select(.conclusion == "failure")'
   gh run view <failing-run-id> --log-failed 2>&1 | tail -80
   ```

3. **If `fix_attempt_count >= 1`:** Escalate to the operator. **Headless mode:** abort with structured error naming the failing check. **Interactive mode:** present failure details and ask whether to investigate manually or abort.

4. **If `fix_attempt_count == 0`:** Increment `fix_attempt_count`. Attempt autonomous fix:

   a. If the failure is in tests or lint: invoke `skill: soleur:test-fix-loop` to diagnose, fix, and commit. After test-fix-loop completes, push and re-queue auto-merge:
      ```bash
      git push
      gh pr merge <number> --squash --auto
      ```
      Note: `gh pr reopen` is NOT needed — when auto-merge is cancelled due to CI failure, the PR remains OPEN. Re-queuing auto-merge is sufficient.

   b. If the failure is in a flaky or unrelated check (not reproducible locally): **Headless mode:** abort. **Interactive mode:** ask whether to wait for a re-run or abort.

5. After re-queuing auto-merge, re-invoke the Phase 7 Monitor poll loop from the beginning. The agent carries `fix_attempt_count` across poll invocations.
```

**Mirror note:** The CI auto-fix logic is OUTSIDE the Phase 7 poll block (`<!-- phase-7-poll-block:start/end -->` markers at lines 1071/1191). The mirror in `merge-pr/SKILL.md §5.2` and fixture at `test/ship-phase-7-poll-fixtures.sh` are NOT affected.

### Phase 2: Ship Phase 7 — chain to postmerge after release verification

**File:** `plugins/soleur/skills/ship/SKILL.md` (insert before "4. Clean up worktree" at line ~1626)

After all release/deploy workflows pass and migration verification completes, add:

```markdown
3.8. **Chain to postmerge verification.** After release workflows pass and migration verification completes, invoke `/soleur:postmerge` to verify production health, Sentry cron monitors, and file freshness:

   ```
   skill: soleur:postmerge <PR-number>
   ```

   If postmerge reports any FAILED phase (production health, Sentry warning, browser regression), display the failures prominently but do NOT block cleanup — the deploy has already happened; the signal is for immediate operator attention, not rollback.
```

### Phase 3: Postmerge Phase 3.5 — Sentry cron monitor health

**File:** `plugins/soleur/skills/postmerge/SKILL.md` (insert between line 97 and line 99, i.e., between Phase 3 and Phase 4)

Add a new phase:

```markdown
## Phase 3.5: Sentry Cron Monitor Health

Verify scheduled functions are healthy post-deploy by querying Sentry cron monitors.

**Prerequisites:** `SENTRY_AUTH_TOKEN` (or `SENTRY_API_TOKEN` fallback) must be available. If missing, warn and skip:

```text
WARNING: SENTRY_AUTH_TOKEN not set. Skipping Sentry health verification.
```

Query cron monitors:

```bash
SENTRY_TOKEN=$(doppler secrets get SENTRY_AUTH_TOKEN -p soleur -c prd --plain 2>/dev/null || \
  doppler secrets get SENTRY_API_TOKEN -p soleur -c prd --plain)
SENTRY_ORG=$(doppler secrets get SENTRY_ORG -p soleur -c prd --plain 2>/dev/null || echo "jikigai")
API_HOST="${SENTRY_ORG}.sentry.io"

curl -sS -H "Authorization: Bearer ${SENTRY_TOKEN}" \
  "https://${API_HOST}/api/0/organizations/${SENTRY_ORG}/monitors/" \
  | jq '[.[] | {slug: .slug, status: .status}] | map(select(.status != "ok" and .status != "active"))'
```

- If all monitors report `ok` or `active`: "Sentry cron monitors: all healthy"
- If any monitor reports `error` or `missed`: flag with monitor name and status. This is a WARNING, not a blocker — the monitor may have been unhealthy before this deploy.
- If Sentry API is unreachable or returns non-200: warn and skip (do not block on Sentry outages).

**Graceful degradation:** This check is advisory. A Sentry API failure does not block the postmerge pipeline.
```

Also update Phase 7 report template (line ~157) to include:
```
Sentry monitors: <HEALTHY/WARNING/SKIPPED>
```

And update Phase 6 issue comment template (line ~140) to include the Sentry result.

## Files to Edit

| File | Change |
|------|--------|
| `plugins/soleur/skills/ship/SKILL.md` | Phase 7 CI auto-fix via test-fix-loop (lines 1215–1225), postmerge chain (insert before line ~1626) |
| `plugins/soleur/skills/postmerge/SKILL.md` | New Phase 3.5 Sentry cron monitor check (insert between lines 97–99), update Phase 7 report + Phase 6 comment templates |

## Files to Create

None.

## Open Code-Review Overlap

None.

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC1: Ship SKILL.md Phase 7 CI failure handler delegates to `test-fix-loop` (1 attempt, then escalate)
- [x] AC2: Ship SKILL.md Phase 7 CI failure handler distinguishes required-check-failure exit (PR OPEN) from CLOSED exit — no `gh pr reopen` needed for the primary path
- [x] AC3: Ship SKILL.md Phase 7 contains `skill: soleur:postmerge` invocation after release workflow verification passes
- [x] AC4: Postmerge SKILL.md contains Phase 3.5 with Sentry cron monitor health check using `SENTRY_AUTH_TOKEN` (with `SENTRY_API_TOKEN` fallback)
- [x] AC5: Postmerge Phase 7 report and Phase 6 issue comment include Sentry monitor results
- [x] AC6: Phase 7 poll block mirror note (`merge-pr/SKILL.md §5.2`) is NOT affected (CI auto-fix is outside the poll block)
- [x] AC7: Sentry check is advisory (warn, don't block) with graceful degradation on API failure

### Post-merge (operator)

- [ ] AC8: Verify `SENTRY_AUTH_TOKEN` in Doppler `prd` has `org:read` scope (required for monitors API)
- [ ] AC9: Live-test the Sentry monitors API query against production to confirm response shape

## Test Scenarios

- Given a PR where a required CI check fails (PR still OPEN), when ship Phase 7 detects the required-check failure exit, then it invokes `test-fix-loop`, pushes the fix, and re-queues auto-merge
- Given `test-fix-loop` fails to resolve the issue, when the fix attempt is exhausted (1 attempt), then the agent escalates to the operator
- Given a PR that merges and release workflows pass, when ship Phase 7 completes, then `/soleur:postmerge` is automatically invoked
- Given `SENTRY_AUTH_TOKEN` is set, when postmerge Phase 3.5 runs, then cron monitors are queried and any `error`/`missed` status is flagged as WARNING
- Given `SENTRY_AUTH_TOKEN` is not set, when postmerge Phase 3.5 runs, then it warns and skips without blocking
- Given postmerge reports a WARNING (unhealthy Sentry monitor), when ship Phase 7 receives the result, then the warning is displayed but cleanup is NOT blocked

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal operator workflow automation. All changes are SKILL.md instruction edits, no application code.

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| CI auto-fix via test-fix-loop introduces a bad fix | Single attempt cap; test-fix-loop has built-in regression detection and circular-fix detection |
| Sentry API shape differs from expected | Phase 0 prerequisite live-tests the monitors endpoint before implementation |
| Postmerge adds latency to the ship pipeline | Postmerge is advisory-only post-merge; failures don't block cleanup |
| Phase 7 poll block mirror in merge-pr diverges | CI auto-fix is outside the poll block; mirror is unaffected |
| `SENTRY_AUTH_TOKEN` vs `SENTRY_API_TOKEN` confusion | Plan uses `SENTRY_AUTH_TOKEN` (canonical per existing scripts) with `SENTRY_API_TOKEN` fallback |

## Sharp Edges

- The Phase 7 poll loop runs in a fresh shell on each Monitor invocation. `fix_attempt_count` is agent-level conversational state, not a bash variable. The agent tracks it across poll invocations.
- When auto-merge is cancelled due to CI failure, the PR typically remains OPEN (auto-merge queue entry is cancelled, not the PR). `gh pr reopen` is wrong for this case — just push the fix and re-queue.
- The DIRTY (merge conflict) exit at ship line 1137 is already handled in the poll block. The CI auto-fix handler should NOT duplicate merge conflict resolution.

## Research Insights

- **Sentry API host:** `${SENTRY_ORG}.sentry.io` (org-subdomain) per `apps/web-platform/scripts/sentry-monitors-audit.sh:65`
- **Sentry org:** `jikigai` per `sentry-monitors-audit.sh:39`
- **Token naming:** `SENTRY_AUTH_TOKEN` is canonical in existing scripts; `SENTRY_API_TOKEN` exists as a wider-scope fallback per `audit-sentry-extra-text-references.sh:94-101`
- **Existing `test-fix-loop` skill:** Already handles test runner detection, failure parsing, minimal fixes, checkpoint commit isolation, and regression detection. Delegation avoids reimplementing all of this.
- **Phase 7 mirror:** Poll block (lines 1070–1192) has explicit `<!-- phase-7-poll-block:start/end -->` markers. CI auto-fix logic is in the post-loop handler (lines 1215+), outside the mirror boundary.
- **Fail-closed pattern:** Per learning `2026-03-19-ci-squash-fallback-bypasses-merge-gates.md`, merge retry must preserve safety flags.

## Plan Review Applied

| ID | Source | Finding | Resolution |
|----|--------|---------|------------|
| P0-1 | DHH | CI auto-fix reimplements test-fix-loop | Delegated to test-fix-loop |
| P0-1 | Kieran | `gh pr reopen` wrong for primary exit path | Removed; distinguished required-check-failure (OPEN) from CLOSED |
| P0-2 | Kieran | `fix_attempts` is agent-level, not bash var | Clarified in Sharp Edges |
| P0-3 | Kieran | Token naming: `SENTRY_API_TOKEN` vs `SENTRY_AUTH_TOKEN` | Fixed to `SENTRY_AUTH_TOKEN` with fallback |
| P0-2 | Simplicity | Sentry error count comparison uses fabricated header | Dropped Check 2 entirely |
| P1-1 | DHH | Error count comparison speculative and useless | Dropped |
| P1-2 | DHH | Phase 4 (work) creates double-invocation | Dropped Phase 4 |
| P1-3 | Kieran | Required-check failure is primary trigger, not CLOSED | Reframed entry point |
| P1-3 | Simplicity | Reduce to 1 auto-fix attempt | Applied |
| P1-4 | Simplicity | Phase 4 (work) redundant | Dropped |
| P1-5 | Kieran | Missing Sentry in report/comment templates | Added to Phase 3 |
