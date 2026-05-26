---
title: "refactor: Remove env-allowlist dual-control gate from team-workspace-invite and byok-delegations"
type: refactor
date: 2026-05-26
lane: single-domain
requires_cpo_signoff: false
---

# refactor: Remove env-allowlist dual-control gate from team-workspace-invite and byok-delegations

## Overview

PR-2 (#4469, umbrella #4456) migrated `team-workspace-invite` and `byok-delegations` from ENV_FLAGS to RUNTIME_FLAGS under Flagsmith with per-org targeting via the `org-targeted` segment (ADR-043). The segment's `orgId IN [...]` rule already IS the per-org allowlist. The env-allowlist (`TEAM_WORKSPACE_ALLOWLIST_ORG_IDS`, `BYOK_DELEGATIONS_ALLOWLIST_ORG_IDS`) is now redundant defense-in-depth that requires a container redeploy to update -- defeating the deploy-free rollout that Flagsmith was adopted for.

This PR removes the dual-control gate, making Flagsmith the sole per-org gate. The `FLAG_*` env vars (Flagsmith outage fallback) remain untouched.

## Problem Statement / Motivation

The dual-control architecture (Flagsmith boolean AND env-allowlist) was correct as a migration safety net. Now that both flags are stable in Flagsmith with the `org-targeted` segment handling per-org targeting, the env-allowlist is:

1. **Operationally redundant:** The Flagsmith segment rule `orgId IN [...]` already gates per-org access.
2. **Deploy-blocking:** Adding an org to the allowlist requires editing a Doppler secret + redeploying the container. This defeats Flagsmith's deploy-free rollout capability.
3. **Maintenance overhead:** Two control surfaces to keep in sync (Flagsmith segment + Doppler env var) for the same logical decision.

## Proposed Solution

Remove the env-allowlist check from both feature-flag gate functions, delete the allowlist parsing code and cache, and update all test/consumer/CI references.

## User-Brand Impact

- **If this lands broken, the user experiences:** A user whose org IS in the Flagsmith segment but WAS NOT in the env-allowlist (hypothetical) would gain access. In practice both are currently in sync, so no behavioral change.
- **If this leaks, the user's [data / workflow / money] is exposed via:** N/A -- this simplifies a gate, it does not remove the gate. Flagsmith remains the access control.
- **Brand-survival threshold:** `none`, reason: simplification removes redundant check; Flagsmith segment is the canonical gate and is not being removed.

## Observability

This is a pure code simplification with no new infrastructure. Existing observability surfaces are unchanged:

```yaml
liveness_signal:
  what: Flagsmith SDK getIdentityFlags health (existing)
  cadence: per-request (30s cache TTL)
  alert_target: Sentry web-platform via reportSilentFallback
  configured_in: apps/web-platform/lib/feature-flags/server.ts:109

error_reporting:
  destination: Sentry web-platform via SENTRY_DSN
  fail_loud: reportSilentFallback logs + Sentry breadcrumb on Flagsmith outage

failure_modes:
  - mode: Flagsmith outage
    detection: reportSilentFallback fires, Sentry event
    alert_route: Sentry issue alert to operator
  - mode: Flag misconfiguration (wrong segment rule)
    detection: User reports feature missing / present unexpectedly
    alert_route: Support ticket

logs:
  where: Docker container stdout (pino) + Sentry breadcrumbs
  retention: 30d Sentry, container log rotation

discoverability_test:
  command: "doppler run -p soleur -c prd -- node -e \"const f = require('./apps/web-platform/lib/feature-flags/server'); console.log(f.getRuntimeFlag);\""
  expected_output: "[AsyncFunction: getRuntimeFlag]"
```

## Open Code-Review Overlap

None. No open code-review issues touch files in this plan's edit list.

## Implementation Phases

### Phase 1: Core gate simplification (`server.ts`)

**Files to edit:**

- `apps/web-platform/lib/feature-flags/server.ts`

**Changes:**

1. **Simplify `isTeamWorkspaceInviteEnabled`** (line 164-168): Remove the `getTeamWorkspaceAllowlist().has(orgId)` check. Keep the `!orgId` early return. Body becomes:
   ```ts
   export async function isTeamWorkspaceInviteEnabled(orgId: string, identity: Identity): Promise<boolean> {
     if (!orgId) return false;
     return getRuntimeFlag("team-workspace-invite", identity);
   }
   ```

2. **Simplify `isByokDelegationsEnabled`** (line 191-195): Remove the `getByokDelegationsAllowlist().has(orgId)` check. Keep the `!orgId` early return. Body becomes:
   ```ts
   export async function isByokDelegationsEnabled(orgId: string | null | undefined, identity: Identity): Promise<boolean> {
     if (!orgId) return false;
     return getRuntimeFlag("byok-delegations", identity);
   }
   ```

3. **Delete dead code:**
   - `cachedAllowlist` variable and its type (line 149)
   - `getTeamWorkspaceAllowlist()` function (lines 151-162)
   - `cachedByokDelegationsAllowlist` variable (line 174)
   - `getByokDelegationsAllowlist()` function (lines 176-189)
   - Comment block about dual-control (lines 170-173)
   - Comment block about cache keyed on raw env-var string (lines 145-148)

4. **Update `__resetFeatureFlagsForTests`** (lines 197-203): Remove `cachedAllowlist = null;` and `cachedByokDelegationsAllowlist = null;`.

5. **Update the comment block** (lines 14-29): Replace the dual-control reference with single-control architecture. Lines 24-26 currently say dual-control; update to reflect that the env-allowlist has been removed and Flagsmith segment is the sole per-org gate.

### Phase 2: Test updates (`server.test.ts`)

**Files to edit:**

- `apps/web-platform/lib/feature-flags/server.test.ts`

**Changes:**

1. **Remove `getTeamWorkspaceAllowlist` import** from line 21.

2. **Delete entire `describe("getTeamWorkspaceAllowlist", ...)`** block (lines 191-233). This tested the env-var parsing which is now dead code.

3. **Rewrite `describe("isTeamWorkspaceInviteEnabled (async, dual-control)", ...)`** (lines 235-270):
   - Rename describe to `"isTeamWorkspaceInviteEnabled (async, single-control)"`.
   - Remove all `vi.stubEnv("TEAM_WORKSPACE_ALLOWLIST_ORG_IDS", ...)` / `process.env.TEAM_WORKSPACE_ALLOWLIST_ORG_IDS = ...` assignments.
   - Simplify truth table: Flagsmith=ON -> true, Flagsmith=OFF -> false. Remove the "not allowlisted" test case.
   - Keep the Flagsmith outage -> env-fallback test (the FLAG_* env var fallback still matters).

4. **Rewrite `describe("isByokDelegationsEnabled (async, dual-control)", ...)`** (lines 272-308):
   - Same pattern: rename to single-control, remove allowlist env stubs, simplify truth table.
   - Keep the orgId=null -> false test.

### Phase 3: Boot breadcrumb simplification

**Files to edit:**

- `apps/web-platform/server/team-workspace-boot.ts`
- `apps/web-platform/server/byok-delegations-boot.ts`
- `apps/web-platform/test/team-workspace-boot.test.ts`

**Changes:**

1. **`team-workspace-boot.ts`**: Remove `getTeamWorkspaceAllowlist` import. Remove the `allowlist.size === 0` early return. Update the Sentry breadcrumb: change `message` from "two-key gate" to "single-control gate". Remove `allowlistSize` from breadcrumb data.

2. **`byok-delegations-boot.ts`**: Same pattern -- remove `getByokDelegationsAllowlist` import, remove allowlist check, update breadcrumb message and data.

3. **`team-workspace-boot.test.ts`**: Remove all `process.env.TEAM_WORKSPACE_ALLOWLIST_ORG_IDS = ...` assignments. Remove the "flag ON but allowlist empty" test case. Update the "both keys evaluate true" test to just test "flag ON". Update breadcrumb assertion to match new message.

### Phase 4: Consumer comment updates

**Files to edit (comment-only changes):**

- `apps/web-platform/app/api/workspace/invite-member/route.ts` (line 13): Remove reference to `TEAM_WORKSPACE_ALLOWLIST_ORG_IDS` from comment.
- `apps/web-platform/app/(dashboard)/dashboard/settings/team/page.tsx` (line 8): Remove reference to `TEAM_WORKSPACE_ALLOWLIST_ORG_IDS` from comment.
- `apps/web-platform/e2e/team-membership.e2e.ts` (line 7): Update comment about the gate.
- `apps/web-platform/test/team-membership-resolver.test.ts` (line 5): Update comment about the gate.

**Note:** Consumer call-sites (`team-membership-resolver.ts:69`, `invite-member/route.ts:39`, `remove-member/route.ts:31`, `settings/layout.tsx:23`, `byok-resolver.ts:137`) do NOT need code changes -- they call `isTeamWorkspaceInviteEnabled(orgId, identity)` / `isByokDelegationsEnabled(orgId, identity)` which keep the same signature. The `orgId` parameter is still needed for Identity construction inside `getRuntimeFlag`.

### Phase 5: Consumer test cleanup

**Files to edit:**

- `apps/web-platform/test/team-membership-resolver.test.ts`: Remove all `vi.stubEnv("TEAM_WORKSPACE_ALLOWLIST_ORG_IDS", ...)` lines (6 occurrences at lines 80, 87, 107, 127, 142, 185). Update the "2-key gate" comment on line 5 to "Flagsmith gate".

### Phase 6: Agent env-allowlist test update

**Files to edit:**

- `apps/web-platform/test/server/agent-env-allowlist.test.ts`

**Changes:**

The `KEYS_TO_VERIFY` array (line 19-22) currently lists `TEAM_WORKSPACE_ALLOWLIST_ORG_IDS`. After this PR, the env var is removed from the app entirely. However, the test's purpose (CWE-526 guard) is to verify that server-only secrets don't leak to agent subprocesses. The allowlist var is being deleted from the app, so remove it from this test. Keep `FLAG_TEAM_WORKSPACE_INVITE` in the test (the FLAG var still exists). Remove the dedicated "does NOT include TEAM_WORKSPACE_ALLOWLIST_ORG_IDS" test case (line 52-54). Update the comment block at the top.

### Phase 7: `.env.example` cleanup

**Files to edit:**

- `apps/web-platform/.env.example`

**Changes:** This file does NOT contain `TEAM_WORKSPACE_ALLOWLIST_ORG_IDS` or `BYOK_DELEGATIONS_ALLOWLIST_ORG_IDS` -- they were never added there (they live only in Doppler). No changes needed.

**Note:** `FLAG_TEAM_WORKSPACE_INVITE=0` and `FLAG_BYOK_DELEGATIONS=0` on lines 107-108 MUST remain (Flagsmith outage fallback).

### Phase 8: `verify-required-secrets.sh` -- no changes needed

**File reviewed:** `apps/web-platform/scripts/verify-required-secrets.sh`

The script's env-fallback mirror invariant (lines 225-240) checks `FLAG_TEAM_WORKSPACE_INVITE` and `FLAG_BYOK_DELEGATIONS` in Doppler. These are the FLAG_* env-fallback vars, NOT the allowlist vars. The allowlist vars (`TEAM_WORKSPACE_ALLOWLIST_ORG_IDS`, `BYOK_DELEGATIONS_ALLOWLIST_ORG_IDS`) do not appear in this script at all. No changes needed.

### Phase 9: Followthrough script update

**Files to edit:**

- `scripts/followthroughs/team-workspace-flag-flip-4284.sh`

**Changes:** This script checks 3 preconditions, the third being the allowlist. After this PR, the third check is obsolete. Two options:

- **Option A:** Delete the script entirely if the follow-through issue #4277 is already resolved.
- **Option B:** Remove precondition (3) and update exit messaging.

Decision: Check `gh issue view 4277 --json state` at work time. If closed, delete the file. If open, remove the allowlist precondition.

### Phase 10: ADR-043 update

**Files to edit:**

- `knowledge-base/engineering/architecture/decisions/ADR-043-flagsmith-per-org-targeting.md`

**Changes:** Update the Consequences section (line 49):
- Change "Dual-control preserved: Flagsmith boolean AND env-allowlist must both hold (defense-in-depth)" to "Single-control: Flagsmith segment rule is the sole per-org gate; env-allowlist removed. FLAG_* env vars remain as Flagsmith outage fallback."

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling simplification removing redundant code path.

## Sharp Edges

- **Do NOT remove `FLAG_TEAM_WORKSPACE_INVITE` / `FLAG_BYOK_DELEGATIONS` env vars.** These are the Flagsmith outage fallback (env-fallback mirror per ADR-038), not the allowlist.
- **`orgId` parameter stays on both gate functions.** It is needed for Identity construction (passed to `getRuntimeFlag` via the identity object for Flagsmith per-org segment evaluation).
- **Post-merge Doppler cleanup.** After merge, `TEAM_WORKSPACE_ALLOWLIST_ORG_IDS` and `BYOK_DELEGATIONS_ALLOWLIST_ORG_IDS` become orphaned secrets in Doppler. Clean up via `doppler secrets delete TEAM_WORKSPACE_ALLOWLIST_ORG_IDS BYOK_DELEGATIONS_ALLOWLIST_ORG_IDS -p soleur -c prd`. This is a post-merge operator action, not automatable via MCP (Doppler MCP does not support secret deletion). Automation: not feasible because Doppler MCP does not expose a delete-secret capability.
- **The followthrough script `team-workspace-flag-flip-4284.sh` may need deletion.** Check issue #4277 status at work time.

## Files to Edit

| File | Change |
|------|--------|
| `apps/web-platform/lib/feature-flags/server.ts` | Remove allowlist functions, caches, dual-control checks |
| `apps/web-platform/lib/feature-flags/server.test.ts` | Remove allowlist test suite, simplify dual-control -> single-control |
| `apps/web-platform/server/team-workspace-boot.ts` | Remove allowlist import + check |
| `apps/web-platform/server/byok-delegations-boot.ts` | Remove allowlist import + check |
| `apps/web-platform/test/team-workspace-boot.test.ts` | Remove allowlist env stubs, simplify |
| `apps/web-platform/test/team-membership-resolver.test.ts` | Remove allowlist env stubs |
| `apps/web-platform/test/server/agent-env-allowlist.test.ts` | Remove allowlist var from guard |
| `apps/web-platform/app/api/workspace/invite-member/route.ts` | Comment update only |
| `apps/web-platform/app/(dashboard)/dashboard/settings/team/page.tsx` | Comment update only |
| `apps/web-platform/e2e/team-membership.e2e.ts` | Comment update only |
| `scripts/followthroughs/team-workspace-flag-flip-4284.sh` | Remove or delete (depends on #4277 state) |
| `knowledge-base/engineering/architecture/decisions/ADR-043-flagsmith-per-org-targeting.md` | Update dual-control -> single-control |

## Files to Create

None.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `isTeamWorkspaceInviteEnabled("org-x", identity)` returns `getRuntimeFlag("team-workspace-invite", identity)` when orgId is truthy.
- [ ] AC2: `isByokDelegationsEnabled("org-x", identity)` returns `getRuntimeFlag("byok-delegations", identity)` when orgId is truthy.
- [ ] AC3: `getTeamWorkspaceAllowlist` and `getByokDelegationsAllowlist` are no longer exported from `server.ts`. Verify: `grep -c "getTeamWorkspaceAllowlist\|getByokDelegationsAllowlist" apps/web-platform/lib/feature-flags/server.ts` returns 0.
- [ ] AC4: `TEAM_WORKSPACE_ALLOWLIST_ORG_IDS` and `BYOK_DELEGATIONS_ALLOWLIST_ORG_IDS` do not appear in any `.ts` or `.tsx` file under `apps/web-platform/lib/` or `apps/web-platform/server/`. Verify: `grep -rn "TEAM_WORKSPACE_ALLOWLIST_ORG_IDS\|BYOK_DELEGATIONS_ALLOWLIST_ORG_IDS" apps/web-platform/lib/ apps/web-platform/server/ --include="*.ts" --include="*.tsx"` returns empty.
- [ ] AC5: `FLAG_TEAM_WORKSPACE_INVITE` and `FLAG_BYOK_DELEGATIONS` remain in `.env.example` and `verify-required-secrets.sh`. Verify: `grep -c "FLAG_TEAM_WORKSPACE_INVITE\|FLAG_BYOK_DELEGATIONS" apps/web-platform/.env.example` returns >=2.
- [ ] AC6: All vitest tests pass: `./node_modules/.bin/vitest run apps/web-platform/lib/feature-flags/server.test.ts apps/web-platform/test/team-workspace-boot.test.ts apps/web-platform/test/team-membership-resolver.test.ts apps/web-platform/test/server/agent-env-allowlist.test.ts`.
- [ ] AC7: ADR-043 Consequences section documents single-control decision.
- [ ] AC8: No TypeScript errors: `npx tsc --noEmit --project apps/web-platform/tsconfig.json` (or equivalent).

### Post-merge (operator)

- [ ] AC9: Delete orphaned Doppler secrets: `doppler secrets delete TEAM_WORKSPACE_ALLOWLIST_ORG_IDS BYOK_DELEGATIONS_ALLOWLIST_ORG_IDS -p soleur -c prd`. Automation: not feasible because Doppler MCP does not expose a delete-secret capability.

## Test Scenarios

- Given Flagsmith returns ON for `team-workspace-invite`, when `isTeamWorkspaceInviteEnabled("org-x", identity)` is called, then it returns `true`.
- Given Flagsmith returns OFF for `team-workspace-invite`, when `isTeamWorkspaceInviteEnabled("org-x", identity)` is called, then it returns `false`.
- Given orgId is empty/null, when `isTeamWorkspaceInviteEnabled("", identity)` is called, then it returns `false` (early return preserved).
- Given Flagsmith is unreachable, when `isTeamWorkspaceInviteEnabled("org-x", identity)` is called, then it falls back to `FLAG_TEAM_WORKSPACE_INVITE` env var.
- Given Flagsmith returns ON for `byok-delegations`, when `isByokDelegationsEnabled("org-x", identity)` is called, then it returns `true`.
- Given orgId is null, when `isByokDelegationsEnabled(null, identity)` is called, then it returns `false`.

## References

- ADR-043: `knowledge-base/engineering/architecture/decisions/ADR-043-flagsmith-per-org-targeting.md`
- ADR-038: Feature flag architecture
- PR #4469: PR-2 (Flagsmith migration, umbrella #4456)
- Label: `semver:patch`
