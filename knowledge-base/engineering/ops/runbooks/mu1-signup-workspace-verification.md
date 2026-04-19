---
category: infrastructure
tags: [multi-user, signup, workspace, provisioning, bubblewrap, verification]
date: 2026-04-18
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
| AC-2 | Workspace clones the user's connected GitHub repo | `MU1 AC-2` describe block in `mu1-integration.test.ts` (requires `MU1_FIXTURE_REPO_URL` + `MU1_FIXTURE_INSTALLATION_ID` + `MU1_INTEGRATION=1` for the full `doppler run` wrap). Manual staging fallback retained in step 4 below. |
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

Expected output: 4 passed, 2 skipped (AC-1 gated, AC-2 gated).

### 2. Gated trigger test (AC-1)

Requires dev Supabase credentials. Use the synthetic-identifier prefix
allowlist (`mu1-integration-*@soleur-test.invalid`) that the test file
enforces; do not run this with production credentials.

```bash
cd apps/web-platform
MU1_INTEGRATION=1 doppler run -p soleur -c dev -- \
  ./node_modules/.bin/vitest run test/mu1-integration.test.ts
```

Expected output:

- 5 passed, 1 skipped when the fixture env vars
  (`MU1_FIXTURE_REPO_URL`, `MU1_FIXTURE_INSTALLATION_ID`) are not present in
  Doppler `dev` — AC-2 stays skipped.
- 6 passed, 0 skipped when the fixture env vars are set in Doppler `dev`.
  The `doppler run -p soleur -c dev` wrap injects them automatically; no
  extra flags needed.

Cleanup: the test deletes the synthetic user in `finally`. If the test
crashes before cleanup, sweep manually. The snippet below (a) is
hard-gated to `-c dev`, (b) re-asserts the Supabase URL looks like a
non-prod project before any delete runs, (c) uses the same v4-UUID
regex the test uses so it cannot match anything but its own leftovers:

```bash
doppler run -p soleur -c dev -- node -e '
  const url = process.env.SUPABASE_URL || "";
  if (!/(^|\.)dev\.|-dev\.|dev-/.test(url)) {
    throw new Error("Refusing to run cleanup against non-dev Supabase URL: " + url);
  }
  const { createClient } = require("@supabase/supabase-js");
  const c = createClient(url, process.env.SUPABASE_SERVICE_ROLE_KEY);
  const SYNTH = /^mu1-integration-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}@soleur-test\.invalid$/i;
  c.auth.admin.listUsers({ perPage: 200 }).then(async ({ data }) => {
    const synth = (data?.users ?? []).filter((u) => SYNTH.test(u.email || ""));
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
PASS: CLONE_NEWUSER works — bwrap can create a user namespace (observed UID=0)
INFO: baseline today = single namespace-mapped UID (pre-container-per-workspace)
PASS: HostConfig.SecurityOpt includes apparmor=soleur-bwrap
PASS: HostConfig.SecurityOpt includes seccomp=/etc/docker/seccomp-profiles/soleur-bwrap.json
--- MU1 bubblewrap UID audit complete — failures=0 ---
```

### 4. AC-2 — Manual repo-clone verification (fallback)

The `MU1 AC-2` describe block in step 2 is the primary evidence. Skip
this section when running under `doppler run -p soleur -c dev --` —
the automated block handles verification. Use this fallback only when
the fixture Doppler vars are intentionally unset for a local experiment,
or if `jikig-ai/mu1-fixture` is ever taken offline.

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

## Verify + Sign-off Checklist

Attach this completed checklist to [#1448][i1448] before marking MU1
green on the roadmap.

- [ ] Pre-check items all green on the day of verification.
- [ ] Output of step 1 attached to the verification issue or PR comment
      (4 passed / 2 skipped by default; 5 passed / 1 skipped or 6 passed /
      0 skipped if step 2 ran, depending on whether the fixture env vars
      are present).
- [ ] If step 2 ran, deletion count of synthetic users = count of
      synthetic users created (no leftovers).
- [ ] Output of step 3 attached, with `failures=0` highlighted and the
      observed bwrap UID matching the recorded baseline. If it differs, a
      container-per-workspace change is likely in flight — update this
      runbook's baseline in the same PR.
- [ ] Step 4 evidence captured (screenshot or `ls` output) OR
      justification for skipping this cycle.
- [ ] Any failure remediated before sign-off.

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

## Security Baseline — `soleur-ai` App on `mu1-fixture`

Expected install scope (confirm weekly or after any App settings
change):

- App: `soleur-ai`, installed on org `jikig-ai`.
- Repository access: "Only select repositories" → exactly
  `jikig-ai/mu1-fixture`. If this drifts to "All repositories", the App
  silently gains access to every new private repo — re-scope via
  `https://github.com/organizations/jikig-ai/settings/installations`.
- `GITHUB_APP_PRIVATE_KEY` exists in Doppler `dev` (copied from `prd` to
  enable the gated AC-2 block). Dev-Doppler readers can mint installation
  tokens for any `soleur-ai` installation; the App's org-scope (just
  `jikig-ai`) bounds the blast radius. Re-evaluate if dev-Doppler access
  widens beyond the founder team.

## Known Deferrals

Scoped out of MU1 per the plan. Each gap has a tracking issue; none
blocks the MU1 sign-off, but each must be present in Phase-4 exit
criteria or explicitly accepted.

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

## Cross-references

- Plan: `knowledge-base/project/plans/2026-04-18-ops-verify-signup-workspace-provisioning-plan.md`
- Issue: [#1448][i1448]
- Roadmap row: `knowledge-base/product/roadmap.md` Pre-Phase 4 MU1.
- Learning: `knowledge-base/project/learnings/security-issues/docker-seccomp-blocks-bwrap-sandbox-20260405.md`
- Learning: `knowledge-base/project/learnings/runtime-errors/workspace-permission-denied-two-phase-cleanup-20260405.md`
- Learning: `knowledge-base/project/learnings/security-issues/bwrap-sandbox-three-layer-docker-fix-20260405.md`
- Related issues: [#1546](https://github.com/jikig-ai/soleur/issues/1546),
  [#1557](https://github.com/jikig-ai/soleur/issues/1557).
