---
title: "Fix Concierge gh-403 → No Git Repository cascade — workspace clone must consume the self-healed installation"
date: 2026-06-08
type: fix
branch: feat-one-shot-concierge-clone-self-heal-order
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
related_prs: [5031, 4946]
status: deepened
---

# fix: Workspace clone must consume the self-healed installation (close the gh-403 → "No Git Repository in Workspace" cascade)

## Enhancement Summary

**Deepened on:** 2026-06-08
**Sections enhanced:** Research Reconciliation (all 6 claims line-verified against `main`); verify-the-negative pass on the hoist-safety claim; precedent-diff gate; test-seam claim confirmed.
**Gates run:** 4.6 (User-Brand Impact ✓ — threshold `single-user incident`), 4.7 (Observability ✓ — all 5 fields, no SSH), 4.8 (PAT-shaped halt — no hits ✓), 4.9 (UI-wireframe — no UI surface, skip ✓), 4.4 (Precedent-Diff), 4.45 (verify-the-negative). Domain-leader Task spawn unavailable in this environment — inline grounded passes substituted; the security-sentinel / user-impact-reviewer triad runs at `/soleur:plan-review` and `/soleur:review`, mandatory here per the `single-user incident` exit-gate rule.

### Key Improvements
1. **Every ARGUMENTS claim line-verified against `main`** (this worktree): clone passes bare `installationId` (`cc-dispatcher.ts:1333`); mint consumes `effectiveInstallationId` (`:1464`); C4 write tool consumes `effectiveInstallationId` (`:1523`); `.git`-LAST sentinel (`ensure-workspace-repo.ts:166-168`); clone fail-soft catch (`:98-108`). The bug is purely that the clone is the one consumer still on the stored id, positioned before the self-heal computes the entitled one.
2. **Hoist-safety proven by verify-the-negative.** The region between the `Promise.all` resolve (`:1282`) and the current clone (`:1330`) reads NONE of `connectedOwner` / `connectedRepo` / `effectiveInstallationId` / `ensureWorkspaceRepoCloned` (grep returned zero) — it only normalizes the ack timestamp + registers the posture cell + sends `autonomous_posture`. The parse + self-heal can therefore be hoisted above the clone with zero behavioral change; `tsc --noEmit` is the mechanical proof that later read sites stay in scope.
3. **Test-seam confirmed.** `ensureWorkspaceRepoCloned` is mocked as an inline anonymous `vi.fn` (`cc-dispatcher-real-factory.test.ts:152`), so its call args are NOT currently inspectable — the plan's instruction to hoist it to a named top-level `mockEnsureWorkspaceRepoCloned` spy is load-bearing for AC1, not optional.
4. **`related_prs` citations verified live:** `gh pr view 5031` → MERGED (gh-403 self-heal hardening); `gh pr view 4946` → MERGED (repo-owner installation selection + honest 403). Both attribution claims hold.

### New Considerations Discovered
- The pattern class is an **in-function ordering correction**, NOT a pattern-bound DB/lock/atomic-write shape — no cross-file precedent applies (precedent-diff gate: "pattern is novel; the in-file precedent is the 3 sibling consumers of `effectiveInstallationId`"). Reviewers should scrutinize the fail-closed invariant (clone gets the stored install in every non-promotion branch), not a missing canonical form.
- `cc-dispatcher-self-heal-observability.test.ts` has **no** clone-vs-self-heal ordering assertion (grep confirmed) — so AC7 passes unchanged after the hoist; the Sharp Edge re-check at /work is a belt-and-suspenders note, the actual risk is nil.

🐛 The hosted Concierge clones the connected repo with the **stored** (cross-account / personal) installation id — the one that holds only `issues: read` on the org repo — so `git clone` 403s, fails fail-soft, leaves the workspace `.git`-less, and `worktree-manager.sh create` then fails with **"No Git Repository in Workspace."** Both errors in the user's screenshot are this single cascade. PR #5031 (commit `9556f1f4a`) hardened the *computation* of the correct installation (`effectiveInstallationId`) but that computation runs **after** the clone, so the clone never consumes it.

## Overview

`realSdkQueryFactory` in `apps/web-platform/server/cc-dispatcher.ts` resolves a `Promise.all` (line ~1255-1282) that yields `workspacePath`, `installationId` (the **stored** install from `resolveInstallationId`), and `repoUrl`. It then, in source order:

1. **(line ~1330)** calls `ensureWorkspaceRepoCloned({ userId, workspacePath, installationId, repoUrl })` — clones using the **stored** `installationId`.
2. **(lines ~1354-1368)** parses `connectedOwner` / `connectedRepo` from `repoUrl`.
3. **(lines ~1394-1459)** runs the installation self-heal: `getInstallationAccount` + `findRepoOwnerInstallationForUser` → computes `effectiveInstallationId` (the entitled repo-owner install) + mirrors deny/skip via `mirrorSelfHealSkip` / `reportSilentFallback`.
4. **(line ~1463)** mints `generateInstallationToken(effectiveInstallationId)` — correctly uses the self-healed install, but **only for GH_TOKEN + the C4 write tool (line ~1523), never for the clone**.

**Causal chain (verified against current `main`, post-#5031):** stored wrong install → `ensureWorkspaceRepoCloned` clones with it → `git clone` gets gh-403 (wrong scope on the org repo) → clone fails fail-soft (`reportSilentFallback`, no throw) → `realGraftRepoClone` moves `.git` LAST as the success sentinel, so a failed clone leaves the workspace `.git`-less → `worktree-manager.sh create` finds no git repo → **"No Git Repository in Workspace."**

**The fix is ORDERING, not new logic:** hoist the `connectedOwner`/`connectedRepo` parse (step 2) and the installation self-heal block (step 3, computation of `effectiveInstallationId` + its observability) to **before** `ensureWorkspaceRepoCloned`, then pass `effectiveInstallationId` — not the stored `installationId` — into `ensureWorkspaceRepoCloned`. The clone then uses the same entitled installation the token mint and the C4 write tool already use. No behavior of the self-heal changes; only the position of the clone call relative to it moves.

**Ordering safety (verified):** the self-heal block depends only on `installationId` (from `Promise.all`) and `connectedOwner` (parsed from `repoUrl`, also from `Promise.all`). It does **not** read anything produced between the `Promise.all` resolve (line ~1282) and the current clone call (line ~1330) — that intervening region only normalizes the ack timestamp, seeds the in-session ack-posture cell, registers the posture closure, and sends an `autonomous_posture` frame to the client. None of those values feed the clone or the self-heal. The clone (`ensureWorkspaceRepoCloned`) is self-contained: it takes `{ userId, workspacePath, installationId, repoUrl }` and depends on none of the self-heal's outputs **except** the installation id we are now correcting. Therefore hoisting the parse + self-heal above the clone is side-effect-free.

## Research Reconciliation — Spec vs. Codebase

No `spec.md` exists for this branch (`knowledge-base/project/specs/feat-one-shot-concierge-clone-self-heal-order/` is empty). The "spec" is the prompt ARGUMENTS, fully verified below.

| ARGUMENTS premise | Reality on `main` (this worktree) | Plan response |
| --- | --- | --- |
| `ensureWorkspaceRepoCloned` (~line 1330) clones using the STORED `installationId` | **Confirmed** — `cc-dispatcher.ts:1330-1335` passes `installationId` (the raw `resolveInstallationId` result from the `Promise.all`), not `effectiveInstallationId`. | Pass `effectiveInstallationId` instead, after hoisting the self-heal. |
| Self-heal computes `effectiveInstallationId` AFTER the clone (~lines 1370-1459) | **Confirmed** — the `let effectiveInstallationId = installationId` + probe block is at `cc-dispatcher.ts:1394-1459`, after the clone at `:1330`. The owner/repo parse it depends on is at `:1354-1368`, also after the clone. | Hoist both the parse (1354-1368) and the self-heal (1394-1459) above the clone. |
| `generateInstallationToken(effectiveInstallationId)` (~line 1463) uses the self-healed install only for the mint / C4 writes, NOT the clone | **Confirmed** — `:1464` mints for `effectiveInstallationId`; `:1523` passes `effectiveInstallationId` to the C4 write tool. The clone is the only consumer still on the stored id. | After the hoist, the clone joins the mint + C4 as a consumer of `effectiveInstallationId`. |
| `realGraftRepoClone` moves `.git` LAST as a success sentinel (~138-172), so a failed clone leaves the workspace `.git`-less | **Confirmed** — `ensure-workspace-repo.ts:166-168`: the `rename(tmp/.git → workspacePath/.git)` is the last mutation; a failure before it (e.g., a 403 in `gitWithInstallationAuth`) leaves no `.git`. | No change to `ensure-workspace-repo.ts` logic — its fail-soft sentinel behavior is correct; the bug is purely the installation id the caller supplies. |
| `gitWithInstallationAuth` → `generateInstallationToken(installationId)`; `generateInstallationToken` throws on non-401 incl. 403 | **Confirmed** — `git-auth.ts` mints via `generateInstallationToken`; a 403 from `git clone` surfaces as a clone failure that `ensureWorkspaceRepoCloned`'s try/catch routes to `reportSilentFallback`. | The fix prevents the 403 by supplying the entitled installation; no change to the auth/throw semantics. |

**Net:** every ARGUMENTS claim holds verbatim. This is a pure ordering bug; #5031 fixed the wrong layer (it improved the self-heal computation but did not move the clone to consume it).

## User-Brand Impact

- **If this lands broken, the user experiences:** the exact screenshot failure — the Concierge cannot clone the connected repo (`git clone` 403s), the workspace has no `.git`, and any worktree/branch/commit operation fails with **"No Git Repository in Workspace."** A non-technical Soleur founder dogfooding the Concierge is dead-in-the-water: no repo, no work, with an opaque error. The #5031 fix made `gh issue create` work via the entitled token but left the *clone* — the precondition for all git work — on the wrong install.
- **If this leaks, the user's workflow is exposed via:** the inverse risk is over-eager promotion — cloning with an installation the user is NOT entitled to. This plan does NOT change the entitlement gate: `effectiveInstallationId` is only promoted above the stored install through the existing `findRepoOwnerInstallationForUser` membership gate (PR #4946) which fail-closes on `not-member` / `indeterminate`. We pass the **already-computed** `effectiveInstallationId`; we add no new promotion path. When the self-heal denies promotion, `effectiveInstallationId === installationId` (the stored install) and the clone uses exactly what it uses today — so the fix can never widen access. The clone also remains gated by `ensureWorkspaceRepoCloned`'s own `GITHUB_HTTPS_REPO_RE` allowlist and the `.git`-absent no-op guard.
- **Brand-survival threshold:** `single-user incident` — one founder hitting a permanent "No Git Repository in Workspace" on a freshly-connected org repo is a brand-survival event. CPO sign-off required at plan time; `user-impact-reviewer` + `security-sentinel` at review time (the security concern is the entitlement-gate invariant — that the hoist passes only the already-gated `effectiveInstallationId`, never a newly-promoted one).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (regression — RED first).** In `test/cc-dispatcher-real-factory.test.ts`, the `installation self-heal` describe block's mismatch case (stored personal install whose login is an entitled org member) asserts that `ensureWorkspaceRepoCloned` is called with `installationId: OWNER` (the self-healed install), NOT `installationId: STORED`. Fails against current `main` (clone currently receives `STORED`). This requires the `ensureWorkspaceRepoCloned` mock to be hoisted to a named top-level const (see Files to Edit) so its call args are inspectable.
- [ ] **AC2 (negative control — promotion denied).** A test asserts that when the self-heal DENIES promotion (`findRepoOwnerInstallationForUser` → `{ installationId: null, outcome: "not-member" }`), `ensureWorkspaceRepoCloned` is called with `installationId: STORED` — i.e. the clone uses the stored install exactly as before, because `effectiveInstallationId === installationId` when no promotion occurs. Proves the fix never widens access.
- [ ] **AC3 (negative control — already-correct).** A test asserts that when the stored install already owns the repo (`alreadyCorrect` short-circuit, e.g. stored == OWNER, Organization type), `ensureWorkspaceRepoCloned` is called with that same install and `findRepoOwnerInstallationForUser` is never called. Confirms the no-op path is unaffected.
- [ ] **AC4 (probe-failure fail-soft).** A test asserts that when the probe throws (`getInstallationAccount` rejects), `ensureWorkspaceRepoCloned` is still called (with `STORED`, the fail-safe value), the dispatch proceeds, and `reportSilentFallback` fires for `op: "installation-self-heal-probe"`. Confirms a self-heal probe failure does NOT prevent the clone (the clone still runs, just with the stored install — same degraded posture as today).
- [ ] **AC5 (clone receives effective install end-to-end — observability parity).** The mint (`generateInstallationToken`) and the clone (`ensureWorkspaceRepoCloned`) receive the SAME installation id in every branch (mismatch → both OWNER; deny → both STORED; already-correct → both stored). A single assertion per branch keeps clone + mint in lockstep so a future edit cannot re-diverge them silently.
- [ ] **AC6 (no token logged — `hr-github-app-auth-not-pat`).** No new or moved `log.*` / `reportSilentFallback` payload introduced by this PR contains a `ghs_`/`gho_`/`ghp_` token substring. The hoist moves existing observability calls verbatim; this AC guards that the move did not inline a token. Mirrors the existing assertion in `github-app-mint-observability.test.ts`.
- [ ] **AC7 (self-heal observability unchanged).** `test/cc-dispatcher-self-heal-observability.test.ts` continues to pass unchanged — the deny/skip `reportSilentFallback` mirror (`op: "self-heal-skip"`, 4-field payload) fires identically after the hoist (the block moved, its emit calls did not change).
- [ ] **AC8 (full suite + typecheck green).** `cd apps/web-platform && ./node_modules/.bin/vitest run test/cc-dispatcher-real-factory.test.ts test/cc-dispatcher-self-heal-observability.test.ts test/ensure-workspace-repo.test.ts test/cc-dispatcher-gh-403-directive.test.ts test/github-app-mint-observability.test.ts` passes, and `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` is clean. (Runner is **vitest**, not bun — `bunfig.toml` blocks bun discovery; typecheck is in-package `tsc`, NOT `npm run -w` — no root `workspaces:`.)

### Post-merge (operator)

- [ ] **AC9 (no operator action).** None. Pure code reordering against an already-provisioned surface; the merge → `web-platform-release.yml` container restart is the deploy. **Automation: N/A — no operator step exists.** (Optional, not a gate: a founder re-connecting a repo and opening a fresh Concierge conversation should now get a successfully-cloned workspace and no "No Git Repository in Workspace" error.)

## Files to Edit

- `apps/web-platform/server/cc-dispatcher.ts` — the only production change. **Move two contiguous regions above the `ensureWorkspaceRepoCloned` call:**
  1. The `connectedOwner` / `connectedRepo` parse (currently `:1354-1368`).
  2. The installation self-heal block (currently `:1394-1459`): `let effectiveInstallationId = installationId; if (installationId !== null && connectedOwner) { … getInstallationAccount … findRepoOwnerInstallationForUser … mirrorSelfHealSkip / reportSilentFallback … }`.

  Place both **immediately after** the `Promise.all` destructure + ack-posture setup and **before** the `ensureWorkspaceRepoCloned` call. Then change the clone call from `installationId` to `effectiveInstallationId`:
  ```ts
  await ensureWorkspaceRepoCloned({
    userId: args.userId,
    workspacePath,
    installationId: effectiveInstallationId, // was: installationId (stored). Now the self-healed, entitled install.
    repoUrl,
  });
  ```
  Update the clone-call comment to note it now consumes the self-healed installation. Leave the GH_TOKEN mint (`:1461-1475`) and the C4 write block (`:1477+`) exactly where they are — they already read `effectiveInstallationId`, which is now computed earlier. **Do NOT move the `autonomous_posture` send / ack-posture registration** — those are independent of both the clone and the self-heal and have no ordering relationship; moving them would be gratuitous and risk a `setBashAutonomous`/posture-timing regression. The minimal diff is: cut the two regions, paste them above the clone, change one argument. Verify with `tsc --noEmit` that `effectiveInstallationId`, `connectedOwner`, `connectedRepo` are now all in scope at every later read site (mint, C4 block) — they are declared with `let`/`const` at function-body scope, so moving the declarations earlier keeps every later reference valid.

- `apps/web-platform/test/cc-dispatcher-real-factory.test.ts` — AC1-AC6. **Hoist the `ensureWorkspaceRepoCloned` mock to a named top-level const** so its call args are inspectable. Currently (`:152`) it is an inline anonymous `vi.fn(async () => undefined)` inside the `vi.mock("@/server/ensure-workspace-repo", …)` factory — replace with the codebase's standard top-level-spy pattern (declare `const mockEnsureWorkspaceRepoCloned = vi.fn(async () => undefined);` alongside the other `mock*` consts near the top, reference it in the `vi.mock` factory, and `mockEnsureWorkspaceRepoCloned.mockClear()` in `beforeEach` if the suite clears mocks per-test). Then extend the existing `installation self-heal` describe block (`:702-824`) with `ensureWorkspaceRepoCloned` call-arg assertions in the mismatch / deny / already-correct / probe-throw cases (AC1-AC5), plus a token-substring negative assertion (AC6). **Reuse the existing `STORED` / `OWNER` / `REPO` fixtures** already defined in that block (`:703-705`).

- `apps/web-platform/test/cc-dispatcher-self-heal-observability.test.ts` — AC7. Verify (no edit expected) that the deny/skip mirror assertions still hold after the hoist. If the suite invokes the factory and asserts ordering of `reportSilentFallback` relative to the clone, adjust only if the hoist changed an observable ordering the test pins; otherwise leave unchanged. **Read this file at /work to confirm whether it asserts any clone-vs-self-heal ordering** — if it mocks `ensureWorkspaceRepoCloned` and asserts it ran before/after the mirror, the ordering flipped (self-heal now precedes the clone) and the assertion must be updated to match.

## Files to Create

None. Both test homes named in the ARGUMENTS (`test/cc-dispatcher-real-factory.test.ts`, `test/cc-dispatcher-self-heal-observability.test.ts`) already exist and are the correct homes; the regression coverage extends the existing `installation self-heal` describe block rather than adding a new file.

## Observability

```yaml
liveness_signal:
  what: "Concierge workspace-clone success vs gh-403 failure (ensure-workspace-repo reportSilentFallback events tagged feature:ensure-workspace-repo, op:clone)"
  cadence: per-cold-dispatch (on-demand, not scheduled)
  alert_target: "Sentry issue search feature:ensure-workspace-repo op:clone — a 403-shaped clone failure after this fix means the SELF-HEAL itself denied (entitlement), not a wrong-install bug; correlate with the co-emitted feature:cc-dispatcher op:self-heal-skip event"
  configured_in: "apps/web-platform/server/ensure-workspace-repo.ts reportSilentFallback (clone catch) + cc-dispatcher.ts mirrorSelfHealSkip/reportSilentFallback (self-heal)"
error_reporting:
  destination: "Sentry (captureException/captureMessage via reportSilentFallback) + pino logger → container stdout → Better Stack"
  fail_loud: true  # clone failure is a captureException EVENT (queryable), self-heal skip is a captureMessage EVENT
failure_modes:
  - mode: "clone still 403s after the fix (self-heal correctly denied promotion → clone used stored install with insufficient scope)"
    detection: "feature:ensure-workspace-repo op:clone event CO-OCCURS with feature:cc-dispatcher op:self-heal-skip (effectiveInstallationId == storedInstallationId)"
    alert_route: "Sentry search; this is the entitlement-deny path, not a regression — the user genuinely lacks the owner install"
  - mode: "clone uses the wrong install (regression — hoist reverted or arg re-diverged)"
    detection: "absence is the signal — AC1/AC5 unit gates assert clone + mint receive the SAME install id; a re-divergence fails the suite pre-merge"
    alert_route: "pre-merge test gate (AC1/AC5), not runtime"
  - mode: "self-heal probe failure prevents the clone (ordering bug — clone now depends on the probe)"
    detection: "AC4 asserts the clone still runs when the probe throws (fail-soft to stored install)"
    alert_route: "pre-merge test gate (AC4)"
logs:
  where: "Sentry events + pino (container stdout, Better Stack). NO ssh required."
  retention: "Sentry default project retention; Better Stack per plan"
discoverability_test:
  command: "open Sentry → search 'feature:ensure-workspace-repo op:clone' and 'feature:cc-dispatcher op:self-heal-skip' (web UI, no shell)"
  expected_output: "after the fix, a clone-failure event should co-occur ONLY with a self-heal-skip (entitlement-deny) event; a clone failure WITHOUT a self-heal-skip would indicate the clone got the wrong install (the bug this fixes)"
```

## Test Scenarios

1. **Mismatch heals the clone:** stored personal install (`Elvalio` → org member), `findRepoOwnerInstallationForUser` → `{ OWNER, "member" }` ⇒ `ensureWorkspaceRepoCloned` called with `OWNER`, `generateInstallationToken` called with `OWNER` (AC1, AC5).
2. **Deny keeps the stored install for the clone:** `findRepoOwnerInstallationForUser` → `{ null, "not-member" }` ⇒ clone called with `STORED`, mint with `STORED`, skip mirrored (AC2, AC5, AC7).
3. **Already-correct:** stored == OWNER (Organization type) ⇒ no owner probe, clone + mint with stored (AC3, AC5).
4. **Probe throws → clone still runs:** `getInstallationAccount` rejects ⇒ clone called with `STORED` (fail-safe), dispatch proceeds, `op: "installation-self-heal-probe"` mirrored (AC4).
5. **No token in any payload:** every moved observability call asserted free of `ghs_`/`gho_`/`ghp_` (AC6).

## Hypotheses

(Network-outage checklist NOT triggered — the 403 here is an application-layer GitHub-App installation-SELECTION bug, not an SSH/firewall/`502/503/504` infra outage. The root cause is proven by direct source reading of `cc-dispatcher.ts:1330` vs `:1394-1464` and is a deterministic ordering defect, not a flaky/transient condition. The transient-probe robustness was already addressed by #5031's Bug A; this plan is strictly about WHICH installation the clone consumes.)

## Open Code-Review Overlap

Checked after Files-to-Edit was finalized: `gh issue list --label code-review --state open` → bodies grepped for `server/cc-dispatcher.ts`, `ensure-workspace-repo`, `ensureWorkspaceRepoCloned`, `effectiveInstallationId`.

- #3243 (decompose `cc-dispatcher.ts` into modules) — **Acknowledge:** structural refactor; this PR's edit is a small, localized reordering of two existing regions + one argument change. Folding a full module decomposition here would balloon scope and risk the brand-survival fix. Remains open; the decomposition can absorb these lines later. (If the decomposition lands first, the hoist is a trivial rebase — the two regions move together as a unit regardless of file structure.)

(No open code-review issue touches `ensure-workspace-repo.ts` or the clone-vs-self-heal ordering. #2246 and #3242 from the sibling #5031 plan are unrelated to this file region.)

## Domain Review

**Domains relevant:** Engineering (security — entitlement-gate invariance under the hoist), Product (the user-facing outcome: clone succeeds vs "No Git Repository in Workspace")

> Note: domain-leader sub-agent spawn (Task tool) is unavailable in this planning environment; the sweep below is an inline single-pass assessment. `deepen-plan` (next step) runs the security-sentinel / data-integrity-guardian / architecture-strategist triad — mandatory here because `brand_survival_threshold: single-user incident`.

### Engineering — Security (Status: reviewed, inline)

**Assessment:** The load-bearing security invariant is that the hoist passes the **already-gated** `effectiveInstallationId` to the clone, and introduces **no new promotion path**. `effectiveInstallationId` is `installationId` (stored) unless the existing `findRepoOwnerInstallationForUser` entitlement gate (PR #4946 / #5031) confirmed membership and returned the owner install. Moving the clone to consume this value cannot grant the clone any access the GH_TOKEN mint and C4 write tool don't already receive from the same variable. AC2 (deny → clone gets STORED) is the explicit fail-closed proof. The clone retains its own `GITHUB_HTTPS_REPO_RE` allowlist and `.git`-absent no-op guard. No service-role, no PAT, no token logging (`hr-github-app-auth-not-pat`, AC6). The one new risk the hoist introduces: a self-heal probe failure now precedes the clone — AC4 proves the probe's try/catch fail-soft keeps `effectiveInstallationId = installationId` and the clone still runs (no new clone-blocking dependency).

### Product/UX Gate

**Tier:** none
**Decision:** N/A — no UI-surface file in Files-to-Edit/Create (all `server/` + `test/`). The user-facing artifact is the OUTCOME (a cloned workspace, no "No Git Repository in Workspace" error), driven entirely by server logic, not a rendered surface. Brand-survival threshold `single-user incident` ⇒ `requires_cpo_signoff: true` (frontmatter) and `user-impact-reviewer` at review time. The mechanical UI-surface override did not fire. CPO sign-off confirms the fix targets the exact screenshot cascade (clone gh-403 → no `.git` → worktree-manager failure).

#### Findings

No new copy, no rendered surface, no wireframe applicable. The change makes the existing self-heal effective for the clone — it does not introduce any user-visible string.

## Infrastructure (IaC)

Skipped — no new infrastructure. Pure code reordering against an already-provisioned surface (`apps/web-platform/server/cc-dispatcher.ts` + `test/**`). No server, service, secret, vendor, cron, DNS, or persistent runtime process introduced. Deploy is the existing `web-platform-release.yml` container restart on merge to `main`.

## GDPR / Compliance Gate

Invoked-equivalent (inline): the edited file is GitHub-App-JWT auth-token-SELECTION code, not a regulated-data schema/migration/PII surface. No new processing activity on personal data — the change reorders which installation id the existing clone consumes and adds no new data field. `userId` in the (unchanged, merely relocated) `reportSilentFallback` payloads remains pseudonymized at the emit boundary (Recital 26). No Art. 9 special-category data, no new lawful-basis question, no DSAR/Art. 30 trigger. **No Critical findings.** (Trigger (b) single-user-incident threshold fired the gate-consideration; outcome: no new regulated surface.)

## Research Insights

### Verified call-site facts (read against this worktree's `main`)

| Fact | Location | Confirmed |
| --- | --- | --- |
| Clone consumes the STORED install | `cc-dispatcher.ts:1330-1335` (`installationId` arg) | ✓ |
| `connectedOwner`/`connectedRepo` parse | `cc-dispatcher.ts:1354-1368` | ✓ (after clone) |
| Self-heal computes `effectiveInstallationId` | `cc-dispatcher.ts:1394-1459` | ✓ (after clone) |
| Mint consumes `effectiveInstallationId` | `cc-dispatcher.ts:1464` | ✓ (already correct) |
| C4 write tool consumes `effectiveInstallationId` | `cc-dispatcher.ts:1523` | ✓ (already correct) |
| `.git` LAST as success sentinel | `ensure-workspace-repo.ts:166-168` (`rename` is last mutation) | ✓ |
| Clone fail-soft → no throw | `ensure-workspace-repo.ts:98-108` (catch → `reportSilentFallback`) | ✓ |
| Intervening region (1283-1330) has no clone/self-heal dep | `cc-dispatcher.ts:1283-1329` (ack-posture + `autonomous_posture` send only) | ✓ |

### Ordering-dependency audit (the load-bearing safety claim)

The self-heal block reads exactly two upstream values: `installationId` and `connectedOwner` (derived from `repoUrl`). Both come from the `Promise.all` (line ~1282), which resolves **before** any of the code being moved. The region between the `Promise.all` and the current clone (lines ~1283-1329) produces only: `parsedAck` / `autonomousAckAtMs` (ack normalization), `autonomousAckPosture` (mutable cell), `registerAutonomousAckPosture` (closure registration), `setBashAutonomous` call, and an `autonomous_posture` client send. **None** of these is read by the parse or the self-heal, and **none** is read by `ensureWorkspaceRepoCloned`. Therefore the parse + self-heal can be hoisted to immediately after the `Promise.all` setup with zero behavioral change to the ack/posture path, and the clone call simply moves down past them. `tsc --noEmit` is the mechanical proof that no later reference (`effectiveInstallationId`, `connectedOwner`, `connectedRepo` at the mint + C4 sites) goes out of scope.

### Test-seam fact (why the real-factory mock needs hoisting)

`test/cc-dispatcher-real-factory.test.ts:150-153` mocks `ensureWorkspaceRepoCloned` with an **inline anonymous** `vi.fn` inside the `vi.mock` factory — its call args are NOT captured to a top-level spy, so the current suite cannot assert which installation id the clone received. The fix's regression coverage (AC1) requires promoting that mock to a named top-level `const mockEnsureWorkspaceRepoCloned`, matching the pattern already used for `mockGetInstallationAccount`, `mockFindRepoOwnerInstallationForUser`, `mockGenerateInstallationToken`, etc. The `ensure-workspace-repo.test.ts` graft-level test (`mockGraftRepoClone` via `__setGraftForTests`, `:60`) already asserts the third positional arg is the installation id — that pattern confirms the clone's installation-id arg is the right assertion target, but the dispatcher-level wiring (stored vs effective) is only observable at the `ensureWorkspaceRepoCloned` boundary in the real-factory suite.

## Alternative Approaches Considered

| Approach | Why not |
| --- | --- |
| Re-clone after the self-heal if the first clone failed (keep the early clone, add a second pass with `effectiveInstallationId`) | Rejected — two clone attempts, more latency, more failure surface, and the first (wrong-install) attempt may partially populate the workspace. The clean fix is to clone ONCE with the right install. |
| Move only the self-heal, leave the parse where it is | Rejected — the self-heal reads `connectedOwner` from the parse; both must move together (the parse has no other upstream dep, so moving it is free). |
| Compute `effectiveInstallationId` inside `ensureWorkspaceRepoCloned` | Rejected — duplicates the self-heal logic + its observability inside the clone module, and the mint + C4 tool already consume the dispatcher-computed value. Single source of truth: compute once in the dispatcher, pass to all three consumers (clone, mint, C4). |
| Also reorder the `autonomous_posture` send / ack-posture registration | Rejected — gratuitous; those have no ordering relationship to the clone or self-heal and moving them risks a posture-timing regression. Minimal diff only. |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This section is filled with concrete artifact/vector/threshold.)
- **The hoist must move the parse AND the self-heal together** — the self-heal reads `connectedOwner` from the parse. Moving the self-heal without the parse leaves `connectedOwner` undefined at the moved site. `tsc --noEmit` will catch a half-move (use-before-declaration), but the cleanest sequence is: cut both regions as one contiguous unit and paste above the clone.
- **Fail-closed invariant under the hoist:** `effectiveInstallationId` equals the stored `installationId` in every non-promotion branch (deny, already-correct, org-type, probe-throw). The clone therefore gets the stored install in exactly the cases it does today, and the entitled owner install ONLY when the existing membership gate promoted. AC2/AC3/AC4 are the explicit proofs; security-sentinel must confirm no path passes a non-`effectiveInstallationId` value (other than the legitimate promotion) to the clone.
- **Real-factory mock must be hoisted to a named spy** — the current inline anonymous `vi.fn` for `ensureWorkspaceRepoCloned` (`:152`) cannot have its call args asserted. Promote it to a top-level `const mockEnsureWorkspaceRepoCloned` (matching the sibling `mock*` consts) before writing AC1.
- New/edited tests MUST live under `apps/web-platform/test/**/*.test.ts` (vitest node-project `include`); a co-located `server/*.test.ts` is silently skipped. Runner is **vitest**, not bun (`bunfig.toml` blocks bun discovery); typecheck is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (no root `workspaces:` — `npm run -w` fails).
- **Check `cc-dispatcher-self-heal-observability.test.ts` for clone-vs-self-heal ordering assertions at /work** — the hoist flips the order (self-heal now precedes the clone). If that suite pins the relative order of `reportSilentFallback` and the clone mock, the assertion must be updated; if it only asserts the mirror payload (independent of clone position), it passes unchanged (AC7).
