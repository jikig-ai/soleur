# ops: Verify signup provisions workspace per-user (Multi-User Readiness MU1)

## Enhancement Summary

**Deepened on:** 2026-04-18
**Sections enhanced:** Risks (R3/R5), Fixture Strategy (AC-1 / AC-2),
Bubblewrap audit script spec, MU1 runbook structure, Follow-up issue list.
**Research sources used:** existing learnings (`docker-seccomp-blocks-bwrap-sandbox-20260405.md`,
`workspace-permission-denied-two-phase-cleanup-20260405.md`,
`posix-rename-mv-aside-root-owned-workspace-files-20260406.md`), existing
integration test patterns (`account-delete.test.ts`), infra ci-deploy
seccomp/apparmor config.

### Key Improvements

1. **Audit script now covers the real risk.** The plan's original audit
   was "run bwrap with `--unshare-user` and check UID." The deepen pass
   surfaced learning `docker-seccomp-blocks-bwrap-sandbox-20260405` —
   Docker's default seccomp profile blocks `CLONE_NEWUSER` entirely,
   which silently disables the whole sandbox. Production uses a custom
   seccomp (`/etc/docker/seccomp-profiles/soleur-bwrap.json`) and
   AppArmor (`soleur-bwrap`) to allow it. The audit script now asserts
   both: (a) `CLONE_NEWUSER` works in the deployed container, (b) the
   container's `HostConfig.SecurityOpt` lists the custom profiles.
2. **Fixture Supabase client matches existing test convention.** The
   original plan proposed `auth.admin.createUser`. Deepen pass confirmed
   `account-delete.test.ts` uses the same API via
   `createServiceClient()` from `@/lib/supabase/server`. AC-1 now
   mirrors that shape.
3. **Two-phase cleanup risk documented.** Learning
   `workspace-permission-denied-two-phase-cleanup-20260405` shows that
   `rm -rf` on a workspace can fail on root-owned files from prior
   bwrap sessions. The integration test's `afterAll` now uses
   `removeWorkspaceDir` (already exported from `workspace.ts`) rather
   than a naive `rmSync` — prevents test pollution between runs.
4. **Runbook gains a "Seccomp/AppArmor verification" pre-check.** Before
   the MU1 gate can sign off on "isolation works", the runbook now
   asserts the production container has both `apparmor=soleur-bwrap`
   and `seccomp=/etc/docker/seccomp-profiles/soleur-bwrap.json` via
   `docker inspect`. If either is missing, the gate fails.

### New Considerations Discovered

- **The existing ci-deploy canary bwrap check does NOT test UID
  namespacing.** `ci-deploy.sh:284` runs `bwrap --new-session
  --die-with-parent --dev /dev --unshare-pid --bind / / -- true` —
  note the absence of `--unshare-user`. It's a liveness check, not a
  UID-isolation check. The MU1 audit is strictly additive.
- **Follow-up filing count revised.** Corpus check of existing issues
  shows #1557 (Docker sandbox availability) and #1546 (bwrap UID
  investigation) already track the seccomp concern — the MU1 runbook
  cross-links these rather than filing new duplicates.

**Issue:** #1448
**Branch:** `feat-verify-signup-workspace-provisioning`
**Worktree:** `.worktrees/feat-verify-signup-workspace-provisioning/`
**Draft PR:** #2597
**Milestone:** Phase 4: Validate + Scale
**Priority:** P1 — gates Multi-User Readiness before any recruitment outreach.

## Overview

This plan closes the **verification gap** in the MU1 gate. All four acceptance
criteria are already implemented in code — the issue is that no evidence
artifact exists that proves they still hold for each release. The deliverables
are three verification artifacts, not feature work:

1. An integration-level test that exercises the full signup → workspace
   provisioning chain (trigger → `provisionWorkspaceWithRepo` → plugin
   symlink → per-user path isolation).
2. A bubblewrap UID audit script that can be re-run per release to confirm
   the OS-level sandbox still isolates users.
3. An MU1 re-verification runbook under
   `knowledge-base/engineering/ops/runbooks/` that ties the above together
   and is executable before recruitment outreach and before each Phase-4
   deploy.

**Scope is AC-literal.** Any gap found during verification that is NOT one
of the four ACs (orphaned-workspace GC, plugin-symlink freshness rotation,
repo-clone failure remediation, etc.) is filed as a follow-up GitHub issue
and referenced in the runbook's "Known Deferrals" section — never folded
into this PR.

## Research Reconciliation — Spec vs. Codebase

| AC claim (issue #1448)                                           | Codebase reality                                                                                                                                                                              | Plan response                                                                                        |
| ---------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| "New user signup triggers automatic workspace provisioning"     | `handle_new_user` trigger in `001_initial_schema.sql` sets `workspace_path = '/workspaces/<uuid>'` in `public.users`. Actual FS provisioning happens in `app/(auth)/callback/route.ts:162,182` and `app/api/workspace/route.ts:48`. | Test the full chain: DB trigger writes row → callback or `POST /api/workspace` provisions FS. Do not assert trigger creates FS. |
| "Workspace clones the user's connected GitHub repo"             | `provisionWorkspaceWithRepo` (server/workspace.ts:121-247) clones via GitHub-App installation token. Called from `app/api/repo/setup/route.ts:97` after repo connection.                     | Test clones a real fixture repo using the dev installation token; assert repo contents land in `$WORKSPACES_ROOT/<uuid>/`. |
| "Latest Soleur plugin is installed in the workspace"            | Both `provisionWorkspace` and `provisionWorkspaceWithRepo` symlink `plugins/soleur → $SOLEUR_PLUGIN_PATH` (default `/app/shared/plugins/soleur`). Not a copy — symlink to shared container path. | Assert the symlink exists and resolves. Do NOT assert "latest" beyond "target path exists"; plugin freshness is a separate concern (deferred). |
| "Workspace is isolated per user"                                | Path-level isolation via UUID namespacing + path-traversal hardening in `server/sandbox.ts`. Runtime isolation via bubblewrap (`bwrap --unshare-*` in `ci-deploy.sh:284`, AppArmor `soleur-bwrap`, seccomp). No per-user UID mapping today — all workspaces run under the same container UID. | Test at two layers: (a) FS path isolation (two users get distinct directories, neither can traverse into the other via the sandbox resolver), (b) bubblewrap UID audit script documents the current isolation model and detects regression. |

**Key nuance:** AC #4 has two interpretations — path-level (what the code
currently guarantees) and OS-level UID isolation (what bubblewrap provides
inside the sandbox but NOT between users sharing the container). The
runbook makes this explicit so the Phase-4 gate is not falsely signed off
on a UID model the code doesn't implement. See "Known Deferrals" for the
container-per-workspace follow-up (which is already tracked under Phase 4
itself per the milestone description).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC-1 (trigger):** Integration test asserts that a new row in
      `auth.users` (simulated via a direct insert under a test transaction)
      causes `public.users` to be populated with a `workspace_path` of the
      expected form `/workspaces/<uuid>` via the `handle_new_user` trigger.
- [ ] **AC-2 (clone):** Integration test asserts that calling
      `provisionWorkspaceWithRepo` with a fixture repo URL and a valid
      installation token produces a workspace directory containing the
      cloned repo's top-level files (e.g., `README.md` or `.git/`).
- [ ] **AC-3 (plugin):** Integration test asserts that both
      `provisionWorkspace` and `provisionWorkspaceWithRepo` produce a
      `plugins/soleur` symlink whose `readlink` result equals
      `$SOLEUR_PLUGIN_PATH`.
- [ ] **AC-4 (isolation):** Integration test asserts that two sequential
      provisionings with different UUIDs produce non-overlapping workspace
      paths, AND that `sandbox.ts` path-traversal guards reject an attempt
      from user A's context to resolve a path under user B's workspace.
- [ ] **Bubblewrap UID audit script:** `apps/web-platform/infra/audit-bwrap-uid.sh`
      exists, is executable, runs `docker exec soleur-web-platform bwrap ...`
      with a fixed namespace-unshare invocation, and emits a clear
      PASS/FAIL line that the runbook and future CI can pipe.
- [ ] **MU1 runbook:** `knowledge-base/engineering/ops/runbooks/mu1-signup-workspace-verification.md`
      exists, follows the same YAML frontmatter + section shape as
      `supabase-migrations.md`, and lists: what to run, expected output,
      failure remediation, known deferrals, sign-off checklist.
- [ ] All three artifacts are referenced from PR body; PR body contains
      `Closes #1448`.

### Post-merge (operator)

- [ ] Run the MU1 runbook once against production from the
      `feat-verify-signup-workspace-provisioning` branch merged state;
      attach the output to the issue before closing.
- [ ] File follow-up issues discovered during verification (orphaned
      workspace cleanup, plugin freshness rotation, etc.) with milestone
      "Phase 4: Validate + Scale" or "Post-MVP / Later" as appropriate.
      Link each from the runbook "Known Deferrals" section.
- [ ] No production migration applies in this PR (verify `ls apps/web-platform/supabase/migrations/`
      diff is empty vs `main`).

## Files to Edit

- `apps/web-platform/test/workspace.test.ts` — extend with an integration
  block gated on an env var (e.g., `MU1_INTEGRATION=1`) so CI's
  fast-unit lane stays green. Add AC-2 + AC-4 cross-user isolation tests.
- `apps/web-platform/test/workspace-error-handling.test.ts` — no change
  unless the new isolation test needs a shared helper; prefer adding the
  helper to a new file rather than modifying this one.

## Files to Create

- `apps/web-platform/test/mu1-integration.test.ts` — the new integration
  test file. Runs under `MU1_INTEGRATION=1` only; otherwise skips with a
  `describe.skip`. Exercises: (a) trigger behavior via Supabase client
  under a test schema, (b) `provisionWorkspaceWithRepo` against a small
  fixture repo (see "Fixture Strategy" below), (c) plugin symlink shape,
  (d) two-user path isolation + sandbox resolver rejection.
- `apps/web-platform/infra/audit-bwrap-uid.sh` — bash script with
  `set -euo pipefail`. Three checks, each emits `PASS:` / `FAIL:` on its
  own line:
  1. **CLONE_NEWUSER check:** `docker exec $CONTAINER bwrap --unshare-user
     --unshare-pid --dev /dev --bind / / -- id -u`. FAIL if exit != 0
     (means seccomp or AppArmor is blocking user-namespace creation —
     the whole sandbox is non-functional; see learning
     `docker-seccomp-blocks-bwrap-sandbox-20260405`).
  2. **Security-opt check:** `docker inspect $CONTAINER --format
     '{{json .HostConfig.SecurityOpt}}'`. FAIL if the output does not
     include both `apparmor=soleur-bwrap` and
     `seccomp=/etc/docker/seccomp-profiles/soleur-bwrap.json`.
  3. **UID-model check:** Capture the UID returned in check 1. Script
     header documents: today this is expected to be a single constant
     (the container's `soleur` UID, namespace-mapped — typically `0`
     inside the ns, 1001 outside). Post-container-per-workspace
     (Phase 4 trigger), this should become per-user. Script emits the
     observed UID so the runbook records the baseline and detects
     drift.

  Defaults: `CONTAINER=${CONTAINER:-soleur-web-platform}`. Exits non-zero
  if any of the three FAIL. Callable standalone (e.g., ssh'd into
  production), piped from the runbook, or wired into CI later.
- `knowledge-base/engineering/ops/runbooks/mu1-signup-workspace-verification.md` —
  the re-verification runbook. Mirrors the structure of
  `supabase-migrations.md`: YAML frontmatter, Pre-check, Apply
  (= run audit + integration test), Verify (= inspect a real signup
  path in staging if available), Rollback (= there is none; document
  what "regression detected" means and which issues to file), Known
  Deferrals, Sign-off checklist.

## Fixture Strategy

- **Trigger test (AC-1):** Use the Supabase service-role client via
  `createServiceClient()` from `@/lib/supabase/server` — same pattern
  as `account-delete.test.ts`. Under `doppler run -p soleur -c dev`,
  call `client.auth.admin.createUser({ email, email_confirm: true })`
  on a synthetic email (`mu1-integration-<randomUUID>@soleur-test.invalid`).
  Then `client.from('users').select('workspace_path').eq('id', user.id).single()`
  and assert `workspace_path === '/workspaces/' + user.id`.
  `afterEach` / `afterAll` calls `client.auth.admin.deleteUser(user.id)`
  — **gated** by an assertion on the synthetic email prefix
  (`mu1-integration-`). The guard helper:

  ```typescript
  const SYNTH_EMAIL_RE = /^mu1-integration-[0-9a-f-]+@soleur-test\.invalid$/i;
  function assertSynthetic(email: string): void {
    if (!SYNTH_EMAIL_RE.test(email)) {
      throw new Error(`Refusing to delete non-synthetic user: ${email}`);
    }
  }
  ```

  Per `cq-destructive-prod-tests-allowlist`.
- **Clone test (AC-2):** Use a small public fixture repo under the
  `soleur-ai` org — existing candidate: `.github-private/mu1-fixture`
  (if present) or a file an issue to create one. If none exists at
  plan time, the integration test's AC-2 block is marked `test.skip`
  with a follow-up issue; the runbook still passes because AC-2 has
  a manual one-time verification already documented.
  **(This is an example of the "corpus verification" gate — see
  Sharp-Edge call-out below. The planner MUST run the query before
  freezing AC-2.)**
- **Symlink test (AC-3):** No external fixture — `$SOLEUR_PLUGIN_PATH`
  set to a freshly-created temp dir in `beforeAll`.
- **Isolation test (AC-4):** Two `randomUUID()` calls, two
  `provisionWorkspace` invocations, assert distinct paths and that
  `resolveSandboxPath('/../<other-uuid>/.claude/settings.json')` from
  user A's context throws.
- **Cleanup in `afterAll` uses `removeWorkspaceDir`, not `rmSync`.**
  Learning `workspace-permission-denied-two-phase-cleanup-20260405`
  documents that workspaces touched by a real bwrap session can contain
  root-owned files that `fs.rmSync({ recursive: true, force: true })`
  cannot delete. The integration test calls `removeWorkspaceDir` from
  `@/server/workspace` for each test-created workspace path, which
  handles the two-phase cleanup. The existing unit test
  `workspace-cleanup.test.ts` already exercises this helper; reusing it
  avoids duplicating cleanup logic.

## Test Strategy

- **Runner:** `vitest` via `node node_modules/vitest/vitest.mjs run`
  from the worktree, scoped to `apps/web-platform/test/mu1-integration.test.ts`
  (per `cq-in-worktrees-run-vitest-via-node-node`).
- **Gating env var:** `MU1_INTEGRATION=1`. Fast unit lane skips by default;
  CI's `release` workflow or a new `mu1-check` workflow runs with
  the env var set. The runbook's "Apply" step runs it locally under
  `doppler run -p soleur -c dev --`.
- **Destructive-prod allowlist:** All `afterAll` cleanup hooks validate
  the target email/UUID against a synthetic-prefix regex before calling
  `auth.admin.deleteUser` or `rm -rf`. Per `cq-destructive-prod-tests-allowlist`.
- **Assertion style:** `.toBe(exactValue)` for mutations, never
  `.toContain([pre, post])`. Per `cq-mutation-assertions-pin-exact-post-state`.
- **Migration check:** Since this PR ships no schema change, the plan's
  CI gate is "diff of `apps/web-platform/supabase/migrations/` vs `main`
  is empty" — added as a `preflight` assertion in the runbook.
- **Bubblewrap audit:** The audit script is a bash smoke test, runnable
  locally against a running `soleur-web-platform` container OR in CI
  against the canary post-deploy. Runbook documents both invocations.

## Implementation Phases

### Phase 1 — Integration test (RED → GREEN)

1. Write `apps/web-platform/test/mu1-integration.test.ts` with all four
   AC blocks; the test file starts RED (the describe block exists, each
   AC block throws `new Error('not yet wired')` to prove the RED
   assertion runs).
2. Wire AC-3 (plugin symlink) first — simplest, no external fixtures.
3. Wire AC-4 (isolation + sandbox resolver) — depends only on local FS.
4. Wire AC-1 (trigger) — depends on Supabase dev client.
5. Wire AC-2 (clone) — depends on fixture repo; if fixture missing at
   plan-time corpus check, mark `test.skip` AND file follow-up issue in
   the same commit.

### Phase 2 — Bubblewrap audit script

1. Write `apps/web-platform/infra/audit-bwrap-uid.sh` with the exact
   invocation matching `ci-deploy.sh:284` plus `--unshare-user` (added
   for the UID audit specifically; ci-deploy's version is for sandbox
   liveness, not UID audit).
2. `chmod +x` and verify the header documents the assumed container name
   (default `soleur-web-platform`, overridable via `$CONTAINER`).
3. Smoke-test locally by invoking the script against a running container;
   record the output in the runbook as the "golden" expected value.

### Phase 3 — MU1 runbook

1. Copy the frontmatter + headings from `supabase-migrations.md`.
2. Populate Pre-check (ls migrations diff = empty, container running),
   Apply (run integration test + audit script), Verify (inspect a real
   signup in staging), Known Deferrals, Sign-off checklist.
3. Cross-link from `knowledge-base/product/roadmap.md` Phase-4 MU1 row
   (check whether that row references an issue — if yes, also reference
   the runbook path).

### Phase 4 — Follow-up issue filing

For each verification gap discovered during Phase 1-3 that is NOT one
of the four ACs, file a GitHub issue with:

- Title: `ops: <gap description>` (e.g., `ops: orphaned workspace GC
  for deleted users`).
- Label (verified via `gh label list`): `priority/p2-medium` or
  `priority/p3-low`, `type/chore`, `domain/operations`.
- Milestone: `Phase 4: Validate + Scale` if it gates recruitment,
  otherwise `Post-MVP / Later`.
- Body: what, why, re-evaluation criteria, link back to #1448 and this
  plan.

Link each from the runbook's "Known Deferrals" section in the same commit.

## Open Code-Review Overlap

None. (Check procedure: `gh issue list --label code-review --state open
--json number,title,body > /tmp/open-review-issues.json` then
`jq -r --arg p "apps/web-platform/server/workspace.ts" '.[] | select(.body // "" | contains($p)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json`
for each planned file. Result: zero matches as of plan time. The planner
MUST re-run this check before shipping if the labeled backlog has churned.)

## Domain Review

**Domains relevant:** Operations (COO)

Infrastructure verification artifact with no user-facing surface, no
content, no billing implication. Runs in subagent/pipeline mode so
domain leaders are skipped per the one-shot flow; full review falls on
the `/review` pass.

### Operations (COO) — carry-forward

**Status:** advisory (not invoked in pipeline mode)
**Assessment summary:** This plan is exactly the shape the MU1 gate was
designed around (verification evidence per release, not new features).
No vendor cost implication. No new Doppler secret. No new CI workflow.

## Research Insights

- **`handle_new_user` trigger:**
  `apps/web-platform/supabase/migrations/001_initial_schema.sql:101-116`.
  Writes `public.users.workspace_path` on `auth.users` insert — does NOT
  provision the FS. FS provisioning is a separate server-side call.
- **FS provisioning entry points:**
  - `apps/web-platform/app/(auth)/callback/route.ts:162,182` —
    first-login callback calls `provisionWorkspace` for new signups.
  - `apps/web-platform/app/api/workspace/route.ts:48` — explicit
    workspace provisioning API.
  - `apps/web-platform/app/api/repo/setup/route.ts:97` — repo-connect
    flow calls `provisionWorkspaceWithRepo`.
- **Plugin symlink target:** `$SOLEUR_PLUGIN_PATH` (default
  `/app/shared/plugins/soleur`). Symlink, not copy — "latest" means
  "whatever the container image ships with at the time of symlink
  resolution".
- **Bubblewrap invocation reference:** `ci-deploy.sh:284` uses
  `bwrap --new-session --die-with-parent --dev /dev --unshare-pid --bind / / -- true`
  as a liveness check. The UID audit script extends this with
  `--unshare-user` to verify UID namespacing works (today it shows the
  container's single UID; post-container-per-workspace it will show
  per-user UIDs).
- **Path-traversal hardening:** `apps/web-platform/server/sandbox.ts`
  contains the resolver logic that rejects cross-workspace path access.
  Test AC-4 depends on it.

### Bubblewrap sandbox research (from existing learnings)

**Learning `docker-seccomp-blocks-bwrap-sandbox-20260405`:**
> Docker's default seccomp profile blocks `CLONE_NEWUSER`, which means
> bwrap's automatic user namespace creation may fail entirely in
> production containers, silently disabling the entire OS-level sandbox
> layer.

Production mitigation (from `ci-deploy.sh:249-260,308-309`): custom
AppArmor profile `soleur-bwrap` and custom seccomp
`/etc/docker/seccomp-profiles/soleur-bwrap.json` that explicitly allow
the syscalls bwrap needs. The MU1 audit script's check #2 asserts both
remain present — closes the silent-regression gap this learning calls
out.

**Learning `workspace-permission-denied-two-phase-cleanup-20260405`:**
bwrap writes inside sandboxes can produce root-owned files from prior
sessions (legacy container leftover or kernel edge cases). Naive
`rmSync` fails with EPERM. The existing `removeWorkspaceDir` helper
already handles this with a `chmod -R u+rwX` + `find -delete` fallback.
The integration test reuses this helper rather than reimplementing.

**Learning `posix-rename-mv-aside-root-owned-workspace-files-20260406`:**
Reinforces R5 — the MU1 verification must not rely on `mv` for aside
semantics on root-owned paths.

### Institutional learnings applied

- `cq-destructive-prod-tests-allowlist` — synthetic email prefix
  `mu1-integration-` gates cleanup.
- `cq-mutation-assertions-pin-exact-post-state` — `.toBe(post)` not
  `.toContain`.
- `cq-in-worktrees-run-vitest-via-node-node` — vitest invocation form.
- `cq-for-local-verification-of-apps-doppler` — runbook prescribes
  `doppler run -p soleur -c dev --` for the integration test.
- `wg-when-deferring-a-capability-create-a` — follow-up issues filed
  in the same commit as the runbook "Known Deferrals" entry.
- Sharp-edge: **"Fixture repos are external-service entities, not
  DB-only."** AC-2 requires a real clonable repo. If one does not
  already exist, this plan marks AC-2 as `test.skip` + follow-up issue;
  it does NOT block the runbook, which can verify AC-2 manually until
  the fixture lands.
- Sharp-edge: **"For any AC that cites an external corpus, run the query
  first."** Before freezing AC-2's fixture repo reference, the
  implementer MUST run `gh repo view soleur-ai/mu1-fixture` (or the
  chosen path) and either confirm or scope-out.

## Non-Goals / Out of Scope

- **Container-per-workspace UID isolation** — already in Phase 4's
  trigger-gated list ("triggered at 5+ concurrent users"). This plan
  documents the current single-UID model in the audit script header so
  the follow-on work has a baseline.
- **Orphaned workspace cleanup** — follow-up issue during Phase 4.
  Filed at PR-open time, linked from runbook.
- **Plugin freshness rotation** — symlink points to container path;
  "latest" is tied to image deploy cadence. Separate concern from MU1.
- **CI wiring of the bubblewrap audit** — the script is standalone and
  runbook-invokable now. Wiring it into the deploy pipeline is a
  follow-up; the audit is still executable per release via the runbook.

## Risks

- **R1 — Fixture repo absent.** AC-2 depends on a public clonable repo.
  **Mitigation:** Corpus check before implementation (per sharp-edge);
  if absent, `test.skip` + follow-up issue, and the runbook retains the
  manual verification step until the fixture lands.
- **R2 — Dev Supabase pollution.** AC-1 creates and deletes real auth
  users in the dev project. **Mitigation:** Synthetic-prefix allowlist
  per `cq-destructive-prod-tests-allowlist`; `afterAll` throws if the
  target email doesn't match the prefix.
- **R3 — Bubblewrap audit false pass today.** The current single-UID
  model means the UID audit "passes" by returning the container's UID,
  not per-user UIDs. **Mitigation:** Audit script header explicitly
  documents this as the expected baseline and notes the expected
  transition point (container-per-workspace, Phase 4 trigger).
- **R4 — Runbook rot.** Three months from now, the runbook's "expected
  output" values will be stale. **Mitigation:** Runbook has a
  "Last-verified" line at the top; `/ship` Phase 5.5 could flag rot —
  separate enhancement, not scope for this PR.
- **R5 — Seccomp/AppArmor silently removed.** If a future deploy change
  drops `--security-opt apparmor=soleur-bwrap` or
  `--security-opt seccomp=…/soleur-bwrap.json` from `ci-deploy.sh`, the
  canary's `bwrap --unshare-pid -- true` check still passes (it only
  needs PID namespace), but `--unshare-user` would fail for real
  workloads. **Mitigation:** The audit script's check #2 is the
  explicit regression test for this drift — it reads
  `HostConfig.SecurityOpt` from `docker inspect` and fails if either
  profile is absent. This closes the gap identified in learning
  `docker-seccomp-blocks-bwrap-sandbox-20260405` without waiting for
  full container-per-workspace isolation.
- **R6 — Integration test polluting the dev Supabase project.** If
  `afterAll` cleanup crashes (e.g., service token expired), the
  synthetic users accumulate. **Mitigation:** Runbook includes a
  one-liner to sweep the dev project for leftover
  `mu1-integration-*@soleur-test.invalid` users — runnable at any time,
  guarded by the same `SYNTH_EMAIL_RE`.

## Sign-off Checklist

- [ ] Integration test committed and passing under `MU1_INTEGRATION=1`.
- [ ] Bubblewrap UID audit script committed and executable.
- [ ] MU1 runbook committed, cross-linked from roadmap Phase 4 MU1 row.
- [ ] Follow-up issues filed for every non-AC gap discovered during
      implementation; each linked from runbook "Known Deferrals".
- [ ] PR body contains `Closes #1448`.
- [ ] `Post-merge (operator)` section of this plan executed and output
      attached to #1448 before issue closes.
