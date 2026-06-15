---
title: "fix: Concierge workspace re-provision fails when workspace dir is missing on disk"
type: bug
date: 2026-06-15
branch: feat-one-shot-workspace-reprovision-ensure-dir
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# 🐛 fix: Re-provision self-heal must create the workspace dir before cloning

## Overview

Running an agent task fails with **"the configured CWD `/workspaces/<uuid>` doesn't exist on disk"** and git reporting **"No Git repository found"**. The self-heal / re-provision clone path assumes the workspace directory already exists on disk and clones into a temp subdir of it — but after a sandbox/host reclaim the workspace root itself is gone, so the clone fails on the missing parent directory and recovery never converges.

The CWE-22 UUID-validation hardening merged on 2026-06-15 (`fix(workspace-resolver): validate workspaceId shape before join()` — PR #5352, commit `f6b941707`) did **NOT** fix this. That change validates the `workspaceId` *shape* before `join()` in `workspace-resolver.ts`; it never creates the directory.

**Root cause.** In `apps/web-platform/server/ensure-workspace-repo.ts`, `realGraftRepoClone()` (line 154) builds `const tmp = join(workspacePath, ".ensure-repo-tmp-<uuid>")` (line 159) and runs `gitWithInstallationAuth(["clone", "--depth", "1", "--", repoUrl, tmp], …)`. When `workspacePath` does not exist on disk, `git clone <tmp>` fails because the parent directory (`workspacePath`) is missing — git creates the final leaf component, not missing intermediate parents.

The signup provisioning path (`apps/web-platform/server/workspace.ts:111`, inside `provisionWorkspace`) correctly calls `ensureDir(workspacePath)` first. The re-provision / self-heal path — reached via both the **leader** half (`agent-runner.ts:1067 startAgentSession`) and the **Concierge** half (`cc-reprovision.ts:52` → `cc-dispatcher.ts realSdkQueryFactory`), both of which call `ensureWorkspaceRepoCloned()` → `realGraftRepoClone()` — skips it.

**Fix.** Ensure the workspace directory exists (`mkdir(workspacePath, { recursive: true })`) at the top of `realGraftRepoClone()`, before computing `tmp` / cloning, mirroring what `workspace.ts:111` does on the signup path. This is the only change to production code. The resolver's UUID validation is upstream of this function and untouched — verify it stays green.

## Premise Validation

All cited artifacts confirmed against current worktree state (none stale):

- **PR #5352 / commit `f6b941707`** — `git log` confirms `fix(workspace-resolver): validate workspaceId shape before join() (CWE-22 defense-in-depth)` merged 2026-06-15. The fix added `UUID_RE.test()` guards in `workspacePathForWorkspaceId` (workspace-resolver.ts:738) and `resolveWorkspacePathForUser` (line 721) — shape validation only, no `mkdir`. Premise holds.
- **`ensure-workspace-repo.ts:159`** — `const tmp = join(workspacePath, \`.ensure-repo-tmp-${randomUUID()}\`)` confirmed verbatim; clone at line 162. The temp-dir suffix is `randomUUID()` (concurrency hardening from PR #4890), not the bare `.ensure-repo-tmp` the issue body paraphrased — corrected below.
- **`workspace.ts:111`** — `ensureDir(workspacePath)` confirmed inside `provisionWorkspace`. `ensureDir` is a **private (non-exported)** function (workspace.ts:365); it cannot be imported into `ensure-workspace-repo.ts`. The fix therefore inlines `mkdir(..., { recursive: true })`, which is the operative behavior of `ensureDir`'s final line (`mkdirSync(dirPath, { recursive: true })`).
- **Call sites** — `ensureWorkspaceRepoCloned` is invoked from `agent-runner.ts:1067` (leader) and `cc-reprovision.ts:52` (Concierge), both gated on `.git`-absent. Confirmed via grep.
- **`mkdir` not yet imported** in `ensure-workspace-repo.ts` — confirmed; the import line at file top must be extended.

No external premises to validate beyond the above (no GitHub-issue blockers cited).

## Research Reconciliation — Spec vs. Codebase

| Issue-body claim | Codebase reality | Plan response |
| --- | --- | --- |
| `tmp = join(workspacePath, '.ensure-repo-tmp-<uuid>')` at "~line 159" | Exactly correct (line 159; `randomUUID()` suffix). | Fix sits at the top of `realGraftRepoClone`, before line 159. |
| "Mirror what workspace.ts:111 does (`ensureDir`)" | `ensureDir` is **private** to workspace.ts — not importable. | Inline `mkdir(workspacePath, { recursive: true })` (the operative call `ensureDir` makes). Do **not** export `ensureDir` (avoids widening workspace.ts's surface for a one-liner). |
| "Verify resolver UUID validation is preserved" | Validation lives in `workspace-resolver.ts` (`workspacePathForWorkspaceId`, `resolveWorkspacePathForUser`), upstream of and unrelated to this function. | The fix touches neither file; preservation is verified by the existing `workspace-resolver-id-shape-guard.test.ts` staying green (AC5). |

## User-Brand Impact

**If this lands broken, the user experiences:** every agent turn (Concierge *and* leader) dead-ends after a sandbox/host reclaim with "the configured CWD `/workspaces/<uuid>` doesn't exist on disk" / "No Git repository found" — the workspace is permanently unusable until manual intervention. This is the exact prod symptom the re-provision self-heal exists to recover from.

**If this leaks, the user's data/workflow is exposed via:** N/A — the change is a `recursive mkdir` of the caller-resolved, already-UUID-validated, per-tenant workspace path. No new data surface, no new external call, no credential handling (the token still rides GIT_ASKPASS inside `gitWithInstallationAuth`, untouched).

**Brand-survival threshold:** single-user incident — a single user hitting a reclaimed host with a missing workspace dir is permanently locked out of agent work until this fixes the recovery. (Matches the `single-user incident` threshold the surrounding `ensure-workspace-repo.ts` code already declares from PR #4890.)

CPO sign-off required at plan time before `/work` begins; `user-impact-reviewer` runs at review-time (review SKILL conditional-agent block). The fix is minimal and the failure modes are enumerated; CPO ack is the single product-owner sign-off on the approach.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (RED first).** A new failing test in `apps/web-platform/test/ensure-workspace-repo-graft-race.test.ts` asserts that `realGraftRepoClone` calls `mkdir(workspacePath, { recursive: true })` **before** `gitWithInstallationAuth` is invoked (ordering matters — the dir must exist before the clone). On `origin/main` this test FAILS (no `mkdir` call exists).
- [ ] **AC2.** A second failing test asserts the `mkdir` is invoked with the exact `workspacePath` (`WS`) and `{ recursive: true }` (recursive so a missing parent chain is created, idempotent when the dir already exists).
- [ ] **AC3 (GREEN).** After the fix, both new tests pass and all pre-existing tests in `ensure-workspace-repo-graft-race.test.ts` AND `ensure-workspace-repo.test.ts` still pass (the `mkdir` mock must be added to the graft-race suite's `node:fs/promises` mock; the orchestration suite mocks only `node:fs` so it is unaffected — but run it to prove no regression).
- [ ] **AC4.** The fix adds `mkdir` to the existing `import { … } from "node:fs/promises";` line in `ensure-workspace-repo.ts` and calls `await mkdir(workspacePath, { recursive: true })` as the first statement inside `realGraftRepoClone` (before the `tmp` assignment). No other production file changes.
- [ ] **AC5 (resolver preserved).** `./node_modules/.bin/vitest run test/workspace-resolver-id-shape-guard.test.ts test/workspace-resolver.test.ts` passes unchanged — confirms the CWE-22 UUID shape guard is untouched and still green.
- [ ] **AC6 (typecheck).** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes (NOT `npm run -w` — the repo root declares no `workspaces` field).
- [ ] **AC7.** `realGraftRepoClone`'s existing `finally { rm(tmp, …) }` cleanup is unchanged; the `mkdir` is outside the `try` (it must succeed before `tmp` is even computed) — a failed `mkdir` propagates to the caller's `try/catch` in `ensureWorkspaceRepoCloned` and is reported via `reportSilentFallback` (existing fail-soft posture preserved; AC verified by reading the catch site, no new code).

## Implementation Phases

### Phase 1 — RED: write the failing tests

In `apps/web-platform/test/ensure-workspace-repo-graft-race.test.ts`:

1. Add `mockMkdir: vi.fn()` to the `vi.hoisted(() => ({ … }))` block.
2. Extend the `vi.mock("node:fs/promises", () => ({ … }))` factory to include `mkdir: mockMkdir` alongside the existing `readdir, cp, rename, rm`.
3. In `beforeEach`, add `mockMkdir.mockResolvedValue(undefined);`.
4. Add a `describe`/`it` block:

```ts
// Re-provision into a workspace dir that does NOT yet exist on disk (post
// host/sandbox reclaim). The clone targets <ws>/.ensure-repo-tmp-<uuid>, so
// the parent <ws> MUST exist first — git clone creates the leaf, not missing
// parents. RED on origin/main: realGraftRepoClone never mkdir's <ws>.
it("creates the workspace dir (recursive) BEFORE cloning", async () => {
  mockExistsSync.mockReturnValue(false);
  await realGraftRepoClone(WS, REPO, 123);
  expect(mockMkdir).toHaveBeenCalledWith(WS, { recursive: true });
  // ordering: mkdir must precede the clone
  const mkdirOrder = mockMkdir.mock.invocationCallOrder[0];
  const cloneOrder = mockGitWithInstallationAuth.mock.invocationCallOrder[0];
  expect(mkdirOrder).toBeLessThan(cloneOrder);
});
```

5. Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/ensure-workspace-repo-graft-race.test.ts` and confirm the new test(s) FAIL (RED) — `mockMkdir` is never called on `origin/main`.

### Phase 2 — GREEN: the one-line fix

In `apps/web-platform/server/ensure-workspace-repo.ts`:

1. Extend the import at line 2: `import { rm, rename, cp, readdir, mkdir } from "node:fs/promises";`
2. Inside `realGraftRepoClone` (line 154), add as the **first statement**, before `const tmp = …`:

```ts
// Ensure the workspace root exists before cloning into a temp subdir of it.
// After a sandbox/host reclaim `workspacePath` may be gone; `git clone` creates
// only the leaf (`.ensure-repo-tmp-<uuid>`), not missing parents — mirroring the
// signup path's ensureDir(workspacePath) (workspace.ts:111). recursive => idempotent.
await mkdir(workspacePath, { recursive: true });
```

3. Run the graft-race suite — the new tests pass (GREEN). Run `ensure-workspace-repo.test.ts` to confirm no regression.

### Phase 3 — Verify resolver preservation + typecheck

1. `cd apps/web-platform && ./node_modules/.bin/vitest run test/workspace-resolver-id-shape-guard.test.ts test/workspace-resolver.test.ts test/ensure-workspace-repo.test.ts test/ensure-workspace-repo-graft-race.test.ts` — all green.
2. `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — clean.

## Files to Edit

- `apps/web-platform/server/ensure-workspace-repo.ts` — add `mkdir` to the `node:fs/promises` import; add `await mkdir(workspacePath, { recursive: true })` as the first statement in `realGraftRepoClone`.
- `apps/web-platform/test/ensure-workspace-repo-graft-race.test.ts` — add `mkdir` to the hoisted mocks + `node:fs/promises` mock factory + `beforeEach`; add the RED-first ordering test.

## Files to Create

None.

## Open Code-Review Overlap

None checked at draft time — to be verified at Phase 1.7.5 against `gh issue list --label code-review --state open` for the two files above. (Pure two-file bug fix; overlap unlikely.)

## Observability

```yaml
liveness_signal:
  what: "ensure-workspace-repo clone success breadcrumb (log.info { action: 'cloned' })"
  cadence: "per cold dispatch with a connected repo and no .git on disk"
  alert_target: "n/a — success path; failures route to error_reporting below"
  configured_in: "apps/web-platform/server/ensure-workspace-repo.ts:108"
error_reporting:
  destination: "Sentry via reportSilentFallback (feature='ensure-workspace-repo', op='clone')"
  fail_loud: "yes — existing catch in ensureWorkspaceRepoCloned mirrors any clone/mkdir failure to Sentry; a failed mkdir now surfaces here instead of an undiagnosed clone failure"
failure_modes:
  - mode: "mkdir(workspacePath) fails (EACCES / ENOSPC / non-dir entry at path)"
    detection: "thrown from realGraftRepoClone → caught in ensureWorkspaceRepoCloned"
    alert_route: "Sentry op='clone' (existing reportSilentFallback site, ensure-workspace-repo.ts:114)"
  - mode: "git clone fails after dir creation (token expired / network / repo gone)"
    detection: "existing — gitWithInstallationAuth rejects"
    alert_route: "Sentry op='clone'; function returns 'failed' → cc honest 'workspace reclaimed' message"
logs:
  where: "pino child logger 'ensure-workspace-repo' → stdout → Better Stack; Sentry for errors"
  retention: "per existing platform retention (unchanged)"
discoverability_test:
  command: "rg -n 'await mkdir\\(workspacePath' apps/web-platform/server/ensure-workspace-repo.ts && ./node_modules/.bin/vitest run test/ensure-workspace-repo-graft-race.test.ts"
  expected_output: "mkdir call present; graft-race suite all green incl. the ordering test"
```

No new observability surface — the fix reuses the existing fail-soft Sentry mirror. A failed `mkdir` is now reported under the same `op='clone'` slug rather than presenting as an opaque clone failure.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — single-file backend bug fix on an already-provisioned code surface. No UI surface (no `components/**`, `app/**/page.tsx`, or `app/**/layout.tsx` touched), no infrastructure, no schema/migration/auth/API-route surface, no regulated-data surface. Product/UX Gate: NONE (mechanical UI-surface override did not fire — Files to Edit contain no UI-surface path).

## Test Scenarios

| Scenario | Expectation |
| --- | --- |
| `workspacePath` missing on disk, `.git` absent, valid repo → `realGraftRepoClone` | `mkdir(ws,{recursive:true})` runs, then clone, then graft converges (`.git` moved in last) |
| `workspacePath` already exists → `mkdir` recursive | no-op (recursive mkdir is idempotent), clone proceeds |
| `mkdir` rejects (permission) | error propagates → `ensureWorkspaceRepoCloned` catch → Sentry op='clone' → returns 'failed' (fail-soft, no throw into conversation) |
| Resolver UUID guard | `workspace-resolver-id-shape-guard.test.ts` unchanged + green |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above.)
- **Do NOT export `ensureDir` from workspace.ts** to "share" it — it carries TOCTOU/symlink-rejection semantics (#2333) scoped to KB scaffolding paths that are irrelevant here, and exporting it widens workspace.ts's surface for a one-liner. The workspace path is already UUID-validated upstream by the resolver, so the inline `mkdir(..., {recursive:true})` is sufficient and matches the operative behavior of `ensureDir`'s final line.
- **Ordering is load-bearing.** `mkdir` must precede `const tmp = join(...)` / the clone — assert ordering in the test via `invocationCallOrder`, not just "was called". A `mkdir` after the clone is useless.
- **Mock surface drift.** The graft-race suite mocks `node:fs/promises` with an explicit object factory. Adding `mkdir` to `realGraftRepoClone` without adding `mkdir` to that mock makes the real `mkdir` run against a fake path and the test throws — the `mkdir: mockMkdir` entry in the mock factory is mandatory, not optional.
- The `mkdir` sits **outside** the existing `try` block so a creation failure is not masked by the `finally { rm(tmp) }` cleanup (tmp isn't computed yet); it propagates to the caller's fail-soft catch.
