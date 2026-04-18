---
category: infrastructure
tags: [multi-user, signup, workspace, provisioning, bubblewrap, verification]
date: 2026-04-18
last_verified: 2026-04-18
---

# MU1: Signup Workspace Provisioning — Re-verification Runbook

Use this runbook to re-prove the four acceptance criteria of the
Multi-User Readiness Gate item MU1 (issue [#1448][i1448]). Run it:

- Before every founder-recruitment outreach wave.
- Before any Phase-4 deploy that touches `server/workspace.ts`,
  `server/sandbox.ts`, `supabase/migrations/`, or `infra/ci-deploy.sh`.
- On demand when the audit script at
  `apps/web-platform/infra/audit-bwrap-uid.sh` or the integration test
  at `apps/web-platform/test/mu1-integration.test.ts` changes.

The enforcing roadmap entry is `knowledge-base/product/roadmap.md`
"Pre-Phase 4: Multi-User Readiness Gate", row MU1.

[i1448]: https://github.com/jikig-ai/soleur/issues/1448

## Acceptance Criteria Under Verification

| # | Criterion | Primary evidence |
|---|-----------|------------------|
| AC-1 | Signup triggers automatic workspace-row creation | `MU1 AC-1` describe block in `mu1-integration.test.ts` (requires `MU1_INTEGRATION=1`) |
| AC-2 | Workspace clones the user's connected GitHub repo | Manual verification in staging (see below) until fixture repo lands — follow-up tracked |
| AC-3 | Latest Soleur plugin is installed in the workspace | `MU1 AC-3` describe block (always runs) |
| AC-4 | Workspace is isolated per user | `MU1 AC-4` describe block (always runs) + `audit-bwrap-uid.sh` |

## Pre-check

Before running the automation, confirm the surrounding environment has not
drifted in ways the automation does not cover.

- [ ] `git diff --name-only main...HEAD -- apps/web-platform/supabase/migrations/`
      returns no results on the branch under test. (MU1 itself must never
      ship a schema change — see plan Pre-merge AC.)
- [ ] The production container is running and healthy:

  ```bash
  ssh <prod-host> docker inspect --format '{{.State.Health.Status}}' soleur-web-platform
  # Expect: healthy
  ```

- [ ] The custom security profiles are present on the host. Missing
      profiles cause the bwrap audit check 2 to FAIL even if CLONE_NEWUSER
      happens to succeed:

  ```bash
  ssh <prod-host> ls -l /etc/apparmor.d/soleur-bwrap \
                      /etc/docker/seccomp-profiles/soleur-bwrap.json
  ```

## Apply — Run the Verification

### 1. Offline tests (AC-3, AC-4)

Runs from any worktree. No secrets, no network.

```bash
cd apps/web-platform
./node_modules/.bin/vitest run test/mu1-integration.test.ts
```

Expected output: 5 passed, 2 skipped (AC-1 gated, AC-2 deferred).

### 2. Gated trigger test (AC-1)

Requires dev Supabase credentials. Use the synthetic-identifier prefix
allowlist (`mu1-integration-*@soleur-test.invalid`) that the test file
enforces; do not run this with production credentials.

```bash
cd apps/web-platform
MU1_INTEGRATION=1 doppler run -p soleur -c dev -- \
  ./node_modules/.bin/vitest run test/mu1-integration.test.ts
```

Expected output: 6 passed, 1 skipped (AC-2 deferred).

Cleanup: the test deletes the synthetic user in `finally`. If the test
crashes before cleanup, sweep manually:

```bash
doppler run -p soleur -c dev -- node -e '
  const { createClient } = require("@supabase/supabase-js");
  const c = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);
  c.auth.admin.listUsers({ perPage: 200 }).then(async ({ data }) => {
    const synth = (data?.users ?? []).filter(
      (u) => /^mu1-integration-[0-9a-f-]+@soleur-test\.invalid$/i.test(u.email || "")
    );
    for (const u of synth) {
      console.log("deleting", u.email);
      await c.auth.admin.deleteUser(u.id);
    }
  });
'
```

### 3. Bubblewrap UID audit (AC-4, OS layer)

Run against the live production container:

```bash
ssh <prod-host> "cd soleur && bash apps/web-platform/infra/audit-bwrap-uid.sh"
```

Expected output (baseline today, single namespace-mapped UID):

```text
--- MU1 bubblewrap UID audit --- container=soleur-web-platform
PASS: CLONE_NEWUSER works — bwrap can create a user namespace
PASS: HostConfig.SecurityOpt includes apparmor=soleur-bwrap
PASS: HostConfig.SecurityOpt includes seccomp=/etc/docker/seccomp-profiles/soleur-bwrap.json
INFO: observed UID inside bwrap namespace = 0
INFO: baseline today = single namespace-mapped UID (pre-container-per-workspace)
--- MU1 bubblewrap UID audit complete — failures=0 ---
```

### 4. AC-2 — Manual repo-clone verification (temporary)

Until the fixture repo lands (see Known Deferrals), verify AC-2 manually
once per verification cycle:

1. In staging, sign up with a synthetic email that matches the MU1
   allowlist regex.
2. Connect a test GitHub repo via the onboarding flow.
3. SSH into the staging container and confirm the workspace contains
   top-level files from the connected repo:

   ```bash
   ssh <staging-host> docker exec soleur-web-platform \
     ls -la /workspaces/<user-uuid>/
   ```

4. Delete the staging account via the in-app settings flow once verified.

## Verify — Post-run Checklist

- [ ] Output of step 1 attached to the verification issue or PR comment.
- [ ] If step 2 was run, deletion count of synthetic users = count of
      synthetic users created (no leftovers).
- [ ] Output of step 3 attached, with `failures=0` highlighted.
- [ ] Step 4 evidence captured (screenshot or `ls` output).
- [ ] Observed bwrap UID from step 3 matches the baseline recorded in
      this runbook. If it differs, a container-per-workspace change is
      likely in flight — update this runbook's baseline in the same PR.

## Failure Remediation

- **Step 1 fails** — the verification artifact itself is broken.
  Investigate in the worktree; AC-3/AC-4 rely on local FS only, so a
  failure points to a regression in `provisionWorkspace` or
  `isPathInWorkspace`. Do NOT sign off on MU1 until resolved.
- **Step 2 fails** — either dev Supabase is down, or the
  `handle_new_user` trigger has regressed. Check
  `apps/web-platform/supabase/migrations/001_initial_schema.sql`; if
  unchanged, connect to dev and run
  `SELECT * FROM pg_trigger WHERE tgname = 'on_auth_user_created'`.
- **Step 3 check 1 fails** — production sandbox is non-functional.
  This is a P0. Roll back the most recent deploy that touched
  `infra/ci-deploy.sh` or the Dockerfile. Cross-reference learning
  `docker-seccomp-blocks-bwrap-sandbox-20260405`.
- **Step 3 check 2 fails** — security profile not attached. P0.
  Inspect `docker inspect soleur-web-platform` for
  `HostConfig.SecurityOpt` and the most recent `ci-deploy.sh` run.
- **Step 4 fails** — manually verify the repo-connect onboarding is
  not broken. File a P1 issue and block MU1 sign-off.

## Rollback

MU1 itself adds no runtime behavior — only verification artifacts — so
there is no rollback SQL or infra change to reverse. If the verification
surfaces a real regression, rollback the commit that introduced the
regression (not this runbook).

## Known Deferrals

Scoped out of MU1 per the plan. Each gap has a tracking issue; none
blocks the MU1 sign-off, but each must be present in Phase-4 exit
criteria or explicitly accepted.

- **Fixture repo for AC-2** — no public clonable repo exists under
  `soleur-ai/` today; AC-2 is verified manually per step 4.
  Tracking: [#2605](https://github.com/jikig-ai/soleur/issues/2605).
- **CI wiring of the bwrap audit** — the script is runbook-invokable;
  automating it post-deploy is additive. Tracking:
  [#2606](https://github.com/jikig-ai/soleur/issues/2606).
- **Orphaned workspace GC** — when a user is deleted outside the
  in-app flow, `/workspaces/<uuid>` lingers. Phase-4 operability
  concern. Tracking:
  [#2607](https://github.com/jikig-ai/soleur/issues/2607).
- **Plugin freshness rotation** — the plugin symlink points to a
  container path, so "latest plugin" is tied to image deploy cadence.
  Tracking: [#2608](https://github.com/jikig-ai/soleur/issues/2608).
- **Container-per-workspace UID isolation** — already on the Phase-4
  trigger list ("triggered at 5+ concurrent users"). The audit script's
  check 3 records the current single-UID baseline so drift is visible
  at that transition.
- **Docker sandbox availability** — broader than MU1; tracked by
  [#1557](https://github.com/jikig-ai/soleur/issues/1557).
- **bwrap UID investigation** — adjacent to MU1; tracked by
  [#1546](https://github.com/jikig-ai/soleur/issues/1546).

## Sign-off Checklist

Attach this completed checklist to [#1448][i1448] before marking MU1
green on the roadmap.

- [ ] Pre-check items all green on the day of verification.
- [ ] Step 1 output pasted (5 passed, 2 skipped).
- [ ] Step 2 output pasted (6 passed, 1 skipped) OR justification for
      skipping this cycle.
- [ ] Step 3 output pasted (all three checks PASS, UID recorded).
- [ ] Step 4 output pasted (staging clone evidence).
- [ ] Any failure remediated before sign-off.
- [ ] `last_verified` frontmatter on this runbook updated to today's
      date and committed.

## Cross-references

- Plan: `knowledge-base/project/plans/2026-04-18-ops-verify-signup-workspace-provisioning-plan.md`
- Issue: [#1448][i1448]
- Roadmap row: `knowledge-base/product/roadmap.md` Pre-Phase 4 MU1.
- Learning: `knowledge-base/project/learnings/security-issues/docker-seccomp-blocks-bwrap-sandbox-20260405.md`
- Learning: `knowledge-base/project/learnings/runtime-errors/workspace-permission-denied-two-phase-cleanup-20260405.md`
- Learning: `knowledge-base/project/learnings/security-issues/bwrap-sandbox-three-layer-docker-fix-20260405.md`
- Related issues: [#1546](https://github.com/jikig-ai/soleur/issues/1546),
  [#1557](https://github.com/jikig-ai/soleur/issues/1557).
