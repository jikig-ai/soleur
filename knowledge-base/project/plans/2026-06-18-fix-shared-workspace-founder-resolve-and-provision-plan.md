---
title: "Fix multi-workspace-per-installation breakage: non-push founder resolver + ready-but-.git-gone shared-workspace provision"
date: 2026-06-18
type: fix
status: planned
branch: feat-one-shot-shared-workspace-founder-resolve-and-provision
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issues_ref: [5274, 4755]
adr: ADR-044
---

# Fix: multi-workspace-per-installation breaks non-push founder resolution AND shared-workspace cold provisioning

## Enhancement Summary

**Deepened on:** 2026-06-18
**Sections enhanced:** Implementation Phases (0/1/2), Acceptance Criteria, Infrastructure (IaC), Risks. All halt gates passed (4.6 User-Brand Impact, 4.7 Observability, 4.8 PAT-shape, 4.9 UI-wireframe — no UI surface).
**Agents used:** verify-the-negative (8/8 load-bearing code claims CONFIRMED), architecture-strategist (6 findings), spec-flow-analyzer (11 findings). No P0; the diagnosis matched the code exactly.

### Key improvements folded in from review
1. **AC6 was a proxy** ("clone returned `"ok"`" — 5-way overloaded incl. `.git`-present no-op + bad-URL skip). Rewritten to assert the INVARIANT: `.git`/work-tree materialized (`gitDirExists false→true`).
2. **Concurrency: the loser's terminal state was unverified.** Added AC6b + a RED test asserting the LOSER (not just the winner) ends ready-or-honest under the lock-free graft; this gates the lock-free-vs-RPC choice.
3. **Member split-write (migration 108) is now a FIRM fix, not conditional.** On a member-triggered heal FAILURE, `set_repo_status` writes the member's `users.repo_error` but the gate reads the OWNER's row → the member loops forever with no honest reason (the headline user). Re-target the write to the owner / `workspaces.repo_error` (requires a migration — IaC section updated).
4. **Recovery policy split by DB state:** keep `claim_repo_clone_lock` (thundering-herd guard) for `error`/stale-`cloning`; lock-free graft only for `ready`-but-`.git`-absent (the lock RPC cannot acquire a `ready` row).
5. **Hot-path:** `getFreshTenantClient` (a JWT round-trip) MUST stay behind the `existsSync` gate; AC7 now names it explicitly. Added AC7b (herd-guard regression), AC4b (the actual `check_suite` prod signal), AC4c (db-error→500 re-drivable), Phase-0 sole-consumer grep, and the pre-compose empty-`full_name` guard.

### New considerations discovered
- The prod `WEB-PLATFORM-3M` event header is `check_suite` — an UNMAPPED event that reaches the resolver BEFORE the `actionClass` guard; the fix must cover it (AC4b), and AC10 now pins install `122213433` to a zero-event post-deploy gate.
- Stale/corrupt `.git` (existsSync true but not a valid work tree) is a known residual the bare-`existsSync` sentinel does not recover; scoped explicitly (a Start-Fresh `.git` must not be blown away).

## Overview

Two production bugs share one root cause: a single user/account can have **multiple workspaces** for the same GitHub-App installation + repo (a solo workspace `id == userId` AND one or more team/shared workspaces with fresh-uuid ids; and across an org, one installation id spans MANY repos). Several code paths still assume "one solo workspace per installation," which ADR-044 deliberately made false (`github_installation_id` is intentionally NON-UNIQUE on `workspaces`; determinism comes from fan-out over `(installation_id, normalizeRepoUrl(repo_url))`).

**Both bugs were re-investigated read-only against prod + code on 2026-06-18. The investigation materially corrected the two premises in the task brief.** See Research Reconciliation.

- **BUG 1 — CONFIRMED via Sentry `WEB-PLATFORM-3M` (`Error: ambiguous founder for installation (>1 solo workspaces)`, `op: founder-ambiguous`, `feature: github-webhook`, `POST /api/webhooks/github`, release `0.154.3`, installation `122213433`, latest event header `x-github-event: check_suite`).** The brief says "the **push** webhook aborts on every push." That is **incorrect** — the **push** path and `workspace-reconcile-on-push.ts` ALREADY scope by `(installation_id, repo_url)` and fan out correctly (the `founderId` was already dropped, schema v=3). The actual abort is on the **NON-PUSH** path: `resolveSoloFounderForInstallation(installationId, service)` (`apps/web-platform/server/resolve-founder-for-installation.ts`) joins `workspaces` ONLY by `github_installation_id` (solo self-join), with NO `repo_url` filter. A multi-repo org install (one installation id across many repos, each with its own solo workspace) resolves `>1` solo workspaces → `{kind:"ambiguous"}` → `route.ts:330` `Sentry.captureException` + **404-drop** + page. Every non-push event (`pull_request`, `workflow_run`, `issues`, `repository_advisory`, `secret_scanning_alert`, and unmapped events like `check_suite` which reach the resolver BEFORE the `actionClass` guard) for that org is dropped. **Fix:** scope the non-push resolver by `(installation_id, normalizeRepoUrl(repo_url))`, consistent with ADR-044 Decision.1 (this is the same fan-out key the push path already uses). The `>1` fail-closed branch is **kept** for the genuinely-ambiguous residual (two users + same fork on the SAME repo + SAME install) — but that residual no longer fires for the multi-repo-org case.

- **BUG 2 — the user's actual blocker. Premise "RLS denies the non-owner member" is REFUTED.** Both credential reads are membership-checked, NOT owner-checked: `resolve_workspace_installation_id` RPC (migration `079`, gated on `is_workspace_member`) and the `workspaces_select_for_members` RLS SELECT policy (migration `053:169-171`, `USING is_workspace_member(...)`) both return non-null for a member. So `installationId` and `repoUrl` resolve correctly for the member's shared workspace, and the active-workspace path already threads the unified `activeWorkspaceId` (#4767 fix). The real gap: **a `repo_status='ready'` workspace whose physical clone is ABSENT on disk (`.git`-gone) is never deterministically re-cloned**, because the dispatch self-heal (`repo-readiness-self-heal.ts:120-124`) gates recovery on `decision.code === "error"` and the pure `evaluateRepoReadiness` (`repo-readiness.ts:91-92`) returns `{ok:true}` for `ready` WITHOUT ever checking `.git` on disk. The only thing that would clone a `ready`-but-`.git`-absent workspace is the unconditional fire-and-forget `ensureWorkspaceRepoCloned` at `cc-dispatcher.ts:1866` — whose `"failed"` return value is **discarded** on the ready path, and whose `.git`-present short-circuit (`ensure-workspace-repo.ts:142`) no-ops if any (possibly stale/empty) `.git` exists. The shared workspace's `repo_status='ready'` + recent `repo_last_synced_at` was set by a flow (share/connect, or session-sync stamping against a clone the interactive session can't materialize) that did not guarantee a clone at the member-session path. Result: the interactive Concierge session lands where `git rev-parse --is-inside-work-tree` returns false, persisting across retries (each retry re-takes the `ready` fast-path), with NO Sentry signal (the `ready` path never reaches the `op:"repo-readiness-self-heal"` mirror). **Fix:** make the dispatch readiness resolution treat `ready`-but-`.git`-absent as a recoverable condition that deterministically (re-)clones under the existing optimistic lock and consumes the `ensureWorkspaceRepoCloned` outcome, rather than fast-pathing on `repo_status` alone.

**OUT OF SCOPE (do NOT touch):** the ADR-044 service-role installation resolver shipped under #5470/#5481 (closed, working — the SERVICE-role install resolution is correct; only the non-push FOUNDER resolver's repo-scoping is wrong). The two NULL-install workspaces (`jikig-ai/shelter-me`, `soleur-synthetic/verify-harness-sentinel`) alarmed by `WEB-PLATFORM-W`. General workspace-GC or billing relocation. The full #4755 member KB write/sync surface (this plan fixes the dispatch CLONE provisioning, not the KB rename/delete/upload routes — those remain #4755's scope; a one-line note will be added to #4755 that the dispatch-path clone is now self-healing).

## Research Reconciliation — Brief vs. Codebase

| Brief claim | Reality (verified 2026-06-18) | Plan response |
| --- | --- | --- |
| "the GitHub **push** webhook aborts on every push" (Bug 1) | The **push** branch (`route.ts:260-306`) and `workspace-reconcile-on-push.ts` ALREADY fan out by `(installation_id, repo_url)`; `founderId` already dropped (schema v=3). The abort is on the **NON-PUSH** path via `resolveSoloFounderForInstallation` (`route.ts:313`). Sentry event header was `check_suite`. | Fix the **non-push** resolver scoping. Do NOT touch the push path or reconcile-on-push (already correct). |
| "`workspace-reconcile-on-push.ts:171` … check whether IT also needs repo_url scoping" | The reconcile already does `.eq("github_installation_id", installationId).eq("repo_url", targetRepoUrl)` (`inngest/functions/workspace-reconcile-on-push.ts:171-172`). | No change needed; cite as the precedent the non-push fix mirrors. |
| "stop requiring a single founder — fan out the webhook for EVERY workspace" (Bug 1) | Push ALREADY fans out. Non-push events (PR review, CI failure, issue triage) are deliberately SINGLE-founder per ADR-044 Amendment 2026-06-17b (fanning out grant-checks/dispatch N× multiplies the consent + installation-token surface — explicitly rejected). After repo-scoping, the non-push case resolves exactly ONE founder per `(install, repo)` in the normal case; the `>1` residual stays fail-closed. | Keep non-push SINGLE-founder; add repo_url scoping so the multi-repo-org false-ambiguity disappears. Do NOT fan out non-push. |
| "Confirm whether `founderId` is still needed downstream" | `founderId` (`== owner users.id`) is load-bearing for `isGranted(supabase, founderId, actionClass)` (`is-granted.ts` — the `.eq("founder_id", founderId)` IS the tenant gate under service-role) AND the Inngest dispatch payload. | `founderId` stays. The resolver still returns one `founderId`; only its SELECT gains a repo_url filter. |
| "a member … gets 'isn't ready' because RLS/credential boundary denies a non-owner member" (Bug 2 hypothesis) | REFUTED. `resolve_workspace_installation_id` (079) and `workspaces_select_for_members` (053) are **membership**-checked, not owner-checked — a member reads non-null install + repo_url. | Root cause is the `ready`-but-`.git`-gone self-heal gap, not member RLS denial. |
| "duplicate-workspace condition causes the session to resolve to a wrong workspace_id/path" (Bug 2 hypothesis) | The active-workspace path already threads ONE membership-verified `activeWorkspaceId` to path/install/repo/status (`cc-dispatcher.ts:1559-1602`, #4767 fix). Path resolution is correct. | Root cause is the readiness gate trusting `repo_status` without verifying `.git` presence — not path divergence. |
| "#5274 (deterministic re-provision) … multi-host" | #5274 verified `/workspaces` is a **single-instance persistent Hetzner volume**; multi-host is NOT a current trigger. The clone, once landed, survives. The gap is the *first* materialization on the `ready` path. | Single-host self-heal (re-clone the `ready`-but-absent clone in-session); does NOT require #5274's snapshot/restore. Add a re-eval note to #5274. |

## User-Brand Impact

**If this lands broken, the user experiences:**
- Bug 1: every PR-review / CI-failure / issue-triage draft silently stops being generated for every user under a multi-repo org installation (the inbox/draft surface goes dark) — currently 734×/24h drop rate on `WEB-PLATFORM-3M`.
- Bug 2: a member of a shared/team workspace opens `/soleur:go`, gets "Your workspace isn't ready yet," and CANNOT recover via retry or disconnect+reconnect — the shared workspace is permanently unusable for them in the Concierge.

**If this leaks, the user's data/workflow is exposed via:** mis-scoping the non-push resolver to the WRONG repo's founder would route one tenant's PR/CI/issue draft (and an installation token in the dispatch) to another founder — a cross-tenant action-attribution leak. The repo_url filter must use the SAME normalized matching contract as the push fan-out (`normalizeRepoUrl`), and the `>1` fail-closed branch must remain (dropping a re-drivable event is strictly safer than misattributing it).

**Brand-survival threshold:** single-user incident.

> CPO sign-off required at plan time before `/work` begins. CPO is invoked in the Domain Review gate below (or confirm CPO reviewed). `user-impact-reviewer` will run at review-time (review/SKILL.md conditional-agent block).

## Goals

1. Non-push GitHub webhook events resolve the correct founder by `(installation_id, normalizeRepoUrl(repo_url))` and stop 404-dropping under a multi-repo org installation.
2. A member's cold dispatch into a DB-`ready` shared workspace whose physical clone is absent deterministically (re-)clones it so the workspace becomes ready (and surfaces an honest message + Sentry signal if recovery genuinely fails).
3. Preserve every genuine fail-closed defense: non-push `>1` ambiguous (same repo + same install, two users + same fork) stays a 404 + page; clone failure on the ready path now surfaces honestly instead of silently degrading.

## Non-Goals / Out of Scope

- Push path / `workspace-reconcile-on-push.ts` changes (already correct).
- Fanning out non-push grant-checks/dispatch (ADR-044 rejected; would multiply the cross-tenant surface).
- The #4755 member KB write/refresh route surface (rename/delete/upload/manual-sync) — only the dispatch-path clone provisioning is in scope.
- #5274 snapshot/restore / multi-host durability (single-host self-heal suffices today).
- The two NULL-install workspaces (`WEB-PLATFORM-W` cron alarm), workspace-GC, billing relocation.

## Architecture Decision (ADR/C4)

### ADR
Amend **ADR-044** (`knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md`), the "Amendment 2026-06-17b — non-push webhook founder attribution" subsection (the one that defined `resolveSoloFounderForInstallation`). The original amendment specified the solo self-join keyed ONLY on `installation_id`, implicitly assuming "one solo workspace per installation." That assumption is false for a multi-repo org install (the same false assumption Decision.1 explicitly rejected for the push path). Add an amendment note: **non-push founder resolution MUST also be scoped by `(installation_id, normalizeRepoUrl(repo_url))`** — composing `https://github.com/<repository.full_name>` exactly like the push reconcile — so the solo self-join discriminates the correct per-repo workspace. The `>1` fail-closed branch is retained but now only fires for the genuine same-repo+same-install ambiguity. `founderId := w.id` and the SINGLE-founder (no fan-out) Steps 6/7 decision are UNCHANGED. This is an **amendment** to ADR-044's own Decision.1 contract, not a reversal — the ADR write is a task of THIS plan (per `wg-architecture-decision-is-a-plan-deliverable`), invoked via `/soleur:architecture`. Also document the Bug 2 `ready`-but-`.git`-gone self-heal as a Consequence: readiness must be the conjunction of `repo_status != cloning/error` AND physical `.git` presence at the resolved path.

### C4 views
Read all three model files — `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` — at /work time before concluding C4 impact. Enumeration for this change:
- **External human actors:** GitHub (webhook sender), the workspace Owner, and the shared-workspace **Member** (a member now triggers an in-session re-clone of a shared workspace's repo). Check whether a "Member" / "shared-workspace member" actor distinct from "Solo founder" is modeled; if a "Solo founder"-only actor description exists that the multi-member shared-workspace clone path falsifies, fix the description.
- **External systems:** GitHub App (installation-token clone), already modeled. No new vendor.
- **Containers/data stores:** the `/workspaces` persistent volume (clone materialization target) and `workspaces.repo_status`/`users.repo_error` — verify the repo-connection edge is modeled as Workspace-owned (ADR-044), and that the clone edge reflects "any member of a shared workspace can trigger the dispatch self-heal clone," not solo-only.
- **Access relationships:** the non-push webhook → founder edge changes from `(installation)` to `(installation, repo)`; the dispatch-clone edge gains a Member→Workspace-repo arrow.

If, after reading all three `.c4` files, the relevant actors/systems/edges are already modeled, the `### C4 views` task records "no C4 impact" CITING this enumeration (actors checked: GitHub, Owner, Member; systems: GitHub App; stores: /workspaces volume, workspaces.repo_status; edges: webhook→founder, member→workspace-clone). If any element is missing, add it to `model.c4` (+ `#external` tag if outside the boundary) + the relationship edges + the `view … include` line in `views.c4`, then run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.

### Sequencing
The ADR amendment describes the target state and ships in THIS feature's lifecycle (not deferred). Both code fixes ship in the same PR.

## Infrastructure (IaC)

No new server, secret, vendor, cron, or persistent runtime process. Bug 1 is TS-only (resolver + route). Bug 2's WHEN-the-self-heal-fires change is TS-only — BUT the deepen-plan review (spec-flow Critical 4.1) established that the **member split-write fix REQUIRES a migration** (108 amendment or successor): `set_repo_status` must re-target its `users.repo_error` write to the workspace owner (or move the reason to `workspaces.repo_error`) so a member-triggered heal failure surfaces the correct reason instead of looping silently. This is a SECURITY DEFINER plpgsql change (membership check already present), not new infra. **Migration discipline (plan Sharp Edge):** `ls apps/web-platform/supabase/migrations/` and read the 2-3 most recent files before writing DDL — the runner wraps each file in a transaction (no `CREATE INDEX CONCURRENTLY`/non-transactional DDL); follow the 108 REVOKE/GRANT + `search_path = public, pg_temp` precedent verbatim. No Terraform / cloud-init / vendor-dashboard step.

## Observability

```yaml
liveness_signal:
  what: "Bug 1 — Sentry issue WEB-PLATFORM-3M (op:founder-ambiguous) event rate; Bug 2 — Sentry op:repo-readiness-self-heal event rate (cc-dispatcher)."
  cadence: "per webhook event (Bug 1); per cold Concierge dispatch on a recoverable workspace (Bug 2)."
  alert_target: "existing Sentry alert rule for feature=github-webhook op=founder-ambiguous (already pages); existing reportSilentFallback Sentry sink for cc-dispatcher op=repo-readiness-self-heal."
  configured_in: "apps/web-platform/infra/sentry/ (existing rules — no new rule needed); the post-merge expectation is WEB-PLATFORM-3M event rate drops to ~0 for the multi-repo-org case."
error_reporting:
  destination: "Sentry via reportSilentFallback / Sentry.captureException (existing sites)."
  fail_loud: "Bug 1 non-push >1 SAME-repo ambiguity still pages (op:founder-ambiguous). Bug 2 ready-but-.git-gone recovery FAILURE now reaches op:repo-readiness-self-heal (today it is invisible because the ready path never enters the self-heal)."
failure_modes:
  - mode: "Non-push resolver still ambiguous after repo-scoping (genuine two-users-same-fork same repo)."
    detection: "Sentry op:founder-ambiguous with count>1."
    alert_route: "existing github-webhook page."
  - mode: "ready-but-.git-gone re-clone fails (token/network/repo-gone)."
    detection: "Sentry op:repo-readiness-self-heal (now reachable on the ready entry) + RepoNotReadyError honest message to client."
    alert_route: "existing cc-dispatcher reportSilentFallback sink."
  - mode: "repo_url read returns null/empty for a non-push event whose workspace exists."
    detection: "non-push event resolves kind:none → existing logger.warn + 404 (no new dark path)."
    alert_route: "Better Stack pino (info/warn)."
logs:
  where: "Better Stack (pino) for cc-dispatcher + github-webhook breadcrumbs; Sentry for the durable error signals."
  retention: "Better Stack WARN+/3-day; Sentry default."
discoverability_test:
  command: "doppler run -p soleur -c prd -- scripts/sentry-issue.sh --latest-event WEB-PLATFORM-3M  # post-merge: event rate trends to 0 for the multi-repo-org case"
  expected_output: "No new founder-ambiguous events attributable to multi-repo-org installs; any residual is a genuine same-repo two-users-same-fork ambiguity."
```

## Implementation Phases

> TDD: write the failing test(s) FIRST in each phase, confirm RED, then implement to GREEN. Test runner is **vitest** (`apps/web-platform/vitest.config.ts`), node project glob `test/**/*.test.ts`. Invoke as `cd apps/web-platform && ./node_modules/.bin/vitest run <path>`. Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (NOT `npm run -w`).

### Phase 0 — Preconditions (verify at /work start, before any edit)
1. `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` baseline-green.
2. Confirm `normalizeRepoUrl` signature + behavior in `apps/web-platform/lib/repo-url.ts` (the push path composes `normalizeRepoUrl(`https://github.com/${fullName}`)`; the non-push fix uses the SAME compose-before-normalize).
3. Confirm non-push webhook bodies carry `repository.full_name` — the route body type at `route.ts:199-207` already destructures `repository?: { full_name?: string }`. Verify each of the 5 mapped action classes + the unmapped reachable events (e.g. `check_suite`) carry `repository.full_name` (GitHub webhook payload reference; cite URL or `<!-- verified -->`).
4. Re-read `repo-readiness-self-heal.ts` + `repo-readiness.ts` + `ensure-workspace-repo.ts:134-178` + `cc-dispatcher.ts:1604-1871` to confirm the `ready` fast-path skips the `.git` check (the load-bearing Bug 2 fact).
5. Confirm the existing test mock shapes (see Files to Edit) — the supabase `from().select().eq().eq()` chain mock in `test/server/resolve-founder-for-installation.test.ts:30-55` (the mock returns the same `chain` from every `.eq`, so a third `.eq("repo_url", …)` is structurally compatible) and the route mock in `github-webhook-founder-attribution.test.ts:41-54`.
6. **Sole-consumer assertion (arch review P2):** `grep -rn "resolveSoloFounderForInstallation" apps/web-platform` — confirm the ONLY references are `route.ts:313` + the two test files. The signature gains a `repoUrl` param; an un-swept second consumer defaulting `repoUrl=""` would `.eq("repo_url","")` → zero rows → `none`/404 (a silent availability drop, fail-safe direction but still a regression to preclude).

### Phase 1 — BUG 1: repo-scope the non-push founder resolver (TDD)

1.1 **RED — extend `test/server/resolve-founder-for-installation.test.ts`:** add cases proving the resolver, given a `repoUrl`, returns the correct single founder when an installation has solo workspaces across DIFFERENT repos (today these would be `>1`/ambiguous), and still returns `ambiguous` only when `>1` solo workspaces share the SAME `(install, repo)`. The mock chain must record the second `.eq("repo_url", <normalized>)` call. Add a `none` case for a repo with no connected workspace under the install.

1.2 **GREEN — `apps/web-platform/server/resolve-founder-for-installation.ts`:** change the signature to `resolveSoloFounderForInstallation(installationId: number, repoUrl: string, service: ServiceClient)` (or accept a pre-normalized repoUrl; decide at /work — prefer passing the already-normalized URL so the route owns the compose-before-normalize, mirroring the push path). Add `.eq("repo_url", normalizedRepoUrl)` to the SELECT chain alongside `.eq("github_installation_id", installationId)`. Keep the TS-side solo-invariant filter (`m.user_id === row.id`), the discriminated union, and the `>1` fail-closed + `db-error` Sentry mirror UNCHANGED. Update the file header comment to document repo-scoping (cite ADR-044 Decision.1 + the amendment).

1.3 **GREEN — `apps/web-platform/app/api/webhooks/github/route.ts`:** at the non-push call site (`:313`), guard FIRST: `if (!body.repository?.full_name) → drop via the same none/404 path WITHOUT issuing the resolver SELECT` (arch review P2 + spec-flow 3.1 — `normalizeRepoUrl("https://github.com/")` returns `"https://github.com"`, NOT `""`, so a post-normalize `=== ""` check would never fire; the guard MUST be the pre-compose `!full_name` check). Otherwise compose `const targetRepoUrl = normalizeRepoUrl(`https://github.com/${body.repository.full_name}`)` and pass it to the resolver. Keep `founderId`, `isGranted`, dispatch payload unchanged.

1.4 **RED→GREEN — extend `test/github-webhook-founder-attribution.test.ts` + `test/server/webhooks/github-route.test.ts`:** assert (a) a non-push event under a multi-repo org install (resolver mocked to return `found` for the matching repo) dispatches correctly and does NOT 404; (b) the existing `>1` same-repo ambiguous case still 404s + Sentry `op:founder-ambiguous`; (c) a non-push event with no `repository.full_name` drops via `none`/404 (no ambiguous throw) AND does NOT issue the resolver SELECT (assert the pre-compose guard); (d) **the actual prod signal — an UNMAPPED event (`check_suite`, which reaches the resolver at `:313` BEFORE the `actionClass` guard at `:374`) under a multi-repo org install now resolves `kind:found` → falls through to the `actionClass` guard → `{received:true}` 200 ignore, NOT a 404-storm** (spec-flow 3.3); (e) **`db-error` from the now-repo-scoped resolver still returns 500 + `releaseDedupRow` (re-drivable), distinct from the 404 of none/ambiguous** — GitHub retries 5xx not 4xx, so this distinction is load-bearing for redelivery (spec-flow 3.2). Confirm `test/server/webhooks/webhook-push-dispatch.test.ts` still asserts push NEVER calls the resolver (no change to push).

### Phase 2 — BUG 2: deterministic re-clone for ready-but-.git-gone shared workspaces (TDD)

2.1 **RED — extend `test/repo-readiness.test.ts` (or a new sibling under `test/`) + `apps/web-platform/test/cc-reprovision.test.ts` / `agent-runner-reprovision.test.ts`:** add a case where `repo_status='ready'` AND `gitDirExists(workspacePath) === false` AND `installationId != null` AND `repoUrl != null` → the resolution invokes `ensureWorkspaceRepoCloned` (lock-free for the ready entry) and the test asserts the **INVARIANT**, not the proxy (spec-flow Critical 1.1): the `gitDirExists` seam transitions `false → true` (or, in a real-graft integration test, `.git` work-tree is materialized at the resolved path) — NOT merely that `ensureWorkspaceRepoCloned` "returned `"ok"`" (which is 5-way overloaded: `.git`-present no-op `:142`, bad-URL skip `:151`, not-connected `:138`, success `:162`, vs `"failed"` `:176` — a proxy assertion passes while `.git` is still absent). On clone `"failed"`, surfaces a `RepoNotReadyError`/honest block + the `op:repo-readiness-self-heal` Sentry mirror. **Stale/corrupt `.git` case (spec-flow 1.2):** add a case where `existsSync(.git)===true` but it is not a valid work tree — document that the current `.git`-presence sentinel (bare `existsSync`) does NOT recover this; either scope it out explicitly with rationale (a Start-Fresh `.git` is intentional and must NOT be blown away — `ensure-workspace-repo.ts:115-120`) OR note it as a known residual. Drive it through the injected seams (`evaluateRepoReadiness`, `claimCloneLock`, `setRepoStatus`, `ensureWorkspaceRepoCloned`, `gitDirExists`) so it stays DB/fs-free.

   **Concurrency RED case (arch review P1 + spec-flow Critical 2.1) — assert the LOSER's terminal state, not just the winner's:** two concurrent cold dispatches on `ready`+`.git`-absent both pass the `existsSync→false` gate and both enter the lock-free graft. Assert (a) at most one `.git` materializes (winner), AND (b) **the LOSER also terminates ready-or-honest** — either it observes the winner's `.git` (sentinel re-check at `ensure-workspace-repo.ts:239`) and returns `{ok:true}` with `.git` present, OR it honest-waits; it must NOT fast-path to `{ok:true}` with `.git` still absent. If the lock-free graft cannot guarantee the loser's terminal correctness, fall back to Phase 2.2 Option (b) (extend the RPC to acquire ready rows). This RED test gates the lock-free-vs-RPC choice.

2.2 **GREEN — `apps/web-platform/server/repo-readiness-self-heal.ts`:** add a NEW recoverable branch for `ready`-but-`.git`-absent — do NOT collapse it into the existing `error` branch. **Split the recovery POLICY by DB state (arch review P1):**
   - `error` / stale-`cloning` → KEEP `claimCloneLock` (`claim_repo_clone_lock`). This is the load-bearing thundering-herd guard: without it, N concurrent dispatches each fire a 120s `git clone` against a genuinely-erroring repo. Do NOT make this branch lock-free.
   - `ready`-but-`.git`-absent (NEW) → **lock-free** graft. `claim_repo_clone_lock` (migration 108) CANNOT acquire a `ready` row (its WHERE matches only `error`/stale-`cloning` — verified `108:97-110`), so the lock is unavailable here by construction. Rely on the graft's `.git`-sentinel re-check at `ensure-workspace-repo.ts:239` (per-attempt `randomUUID` temp dir + atomic rename) for concurrency. Option (b) — extend the RPC to acquire `ready` rows — requires a migration and is the fallback ONLY if a concrete loser-side race is demonstrated; default to lock-free.
   The current `decision.ok` early-return at `:116` must short-circuit ONLY when `gitDirExists(workspacePath) === true`. **Key constraint:** the fast-path zero-await property for the COMMON case (`ready` AND `.git` present) must be preserved — the only added cost is the local `existsSync`; do NOT add a DB/JWT round-trip (especially `getFreshTenantClient`) to that path.
   **Success-branch write (arch review P1):** on the `ready`-entry SUCCESS, the row is already `repo_status='ready'` — SKIP the `setRepoStatus(ready)` write (it is a no-op on `workspaces.repo_status` AND would spuriously write the MEMBER's `users.repo_error=NULL` via the 108 split-write, plus an RPC round-trip of no value). Only the `error`-entry and the `ready`-entry FAILURE sub-branch call `setRepoStatus`.

2.3 **GREEN — `apps/web-platform/server/cc-dispatcher.ts`:** route the `ready`-but-`.git`-absent case through `resolveRepoReadinessWithSelfHeal` instead of relying on the unchecked fire-and-forget `ensureWorkspaceRepoCloned` at `:1866`. Today the self-heal block + `getFreshTenantClient` mint sit inside `if (!repoReadiness.ok)` (`:1768-1771`), so the `ready` case skips them. Widen the entry condition to `!repoReadiness.ok || (repoReadiness.ok && !existsSync(join(workspacePath, ".git")))` — **the `existsSync` MUST be evaluated FIRST so `getFreshTenantClient` (a JWT round-trip) stays OFF the `ready`+`.git`-present hot path** (arch review P1; AC7). Consume the orchestrator outcome (an honest `RepoNotReadyError` on failure). The `ensureWorkspaceRepoCloned` at `:1866` may STAY (it no-ops via the `.git`-present short-circuit once the gate handles `ready`-but-absent, and still covers the not-connected/scaffold path) — but its `"failed"` outcome must no longer be the ONLY observation of a clone failure (the gate now observes it). Thread the unified `activeWorkspaceId` + `effectiveInstallationId` (already in scope).

2.4 **SOLEUR-DEBT split-write (migration 108:172-181) — this is a FIRM fix on the FAILURE branch, not a conditional (spec-flow Critical 4.1 + arch review P1):** `set_repo_status` writes `users.repo_error` to `auth.uid()` (the caller = the member), but `evaluateRepoReadiness` reads the OWNER's `users.repo_error`. For a non-owner member, on a clone FAILURE the member writes their own row, the gate re-reads the owner's (null/stale) row → next dispatch fast-paths `{ok:true}` → **member retries into the broken state forever with no honest reason** — the EXACT headline user this plan exists to unblock. Therefore: on the member-triggered `error`-write path, re-target `set_repo_status`'s `users.repo_error` write to the workspace OWNER (resolve the owner via `organizations.owner_user_id` / the membership owner row, server-side inside the SECURITY DEFINER RPC), OR move the reason onto `workspaces.repo_error` and have the gate read it there. This needs a migration (108 amendment or a successor). Keep the change minimal (the reason-targeting only); do NOT expand into the full #4755 KB-route surface. Add an AC asserting a member-triggered heal FAILURE surfaces the correct reason to the member on the next dispatch. The SOLEUR-DEBT marker's broader upgrade-trigger #4560 still stands for the rest of the shared-repo surface.

### Phase 3 — ADR-044 amendment + C4 (deliverable of this plan)
3.1 Amend `ADR-044-workspace-repo-ownership.md` (non-push amendment subsection) per the Architecture Decision section. Invoke `/soleur:architecture`.
3.2 Read all three `.c4` files; add/verify actors/systems/edges per the C4 enumeration; run `c4-code-syntax.test.ts` + `c4-render.test.ts`.

### Phase 4 — Full-suite gate + reconciliation
4.1 `cd apps/web-platform && ./node_modules/.bin/vitest run` (or the package's `test` script) — full suite green.
4.2 `./node_modules/.bin/tsc --noEmit` green.
4.3 Add a re-evaluation note to #5274 (single-host self-heal landed; multi-host snapshot/restore still deferred) and a scope note to #4755 (dispatch-path clone now self-heals; KB write/refresh routes still in #4755's scope).

## Files to Edit
- `apps/web-platform/server/resolve-founder-for-installation.ts` — add `repoUrl` param + `.eq("repo_url", …)`; update header comment.
- `apps/web-platform/app/api/webhooks/github/route.ts` — compose-before-normalize the non-push `targetRepoUrl`, pass to resolver, empty-full_name → none/404.
- `apps/web-platform/server/repo-readiness-self-heal.ts` — broaden `canRecover` to cover `ready`-but-`.git`-absent.
- `apps/web-platform/server/cc-dispatcher.ts` — route the `ready`-but-`.git`-absent case through the self-heal choke point; stop discarding the clone outcome. (Open code-review #3242/#3243 also touch this file — see Open Code-Review Overlap; both ACKNOWLEDGED, not folded in.)
- `apps/web-platform/server/repo-readiness.ts` — only if the pure decision needs to expose a `.git`-disk signal; PREFER keeping it pure and doing the `gitDirExists` check in the orchestrator (it already injects `gitDirExists`). Decide at /work; default = no change to the pure module.
- `apps/web-platform/test/server/resolve-founder-for-installation.test.ts` — repo-scope cases.
- `apps/web-platform/test/github-webhook-founder-attribution.test.ts` — multi-repo-org non-404 + retained ambiguous + missing-full_name cases.
- `apps/web-platform/test/server/webhooks/github-route.test.ts` — resolver call-site repo_url assertion.
- `apps/web-platform/test/repo-readiness.test.ts` and/or `apps/web-platform/test/cc-reprovision.test.ts` / `agent-runner-reprovision.test.ts` — ready-but-.git-gone re-clone cases.
- `knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md` — non-push repo-scope amendment + Bug 2 consequence.
- `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` — only if the C4 enumeration finds a missing actor/system/edge.
- A migration (108 amendment or successor) — **required** for Phase 2.4: re-target `set_repo_status`'s `users.repo_error` write to the workspace OWNER (or move the reason to `workspaces.repo_error`) so a member-triggered heal failure surfaces the correct reason. (Also covers Phase 2.2 lock-option (b) IF the concurrency RED test forces it; default is lock-free, no DDL for the lock.)

## Files to Create
- None expected (all tests extend existing files). If a new ready-but-.git-gone test file is cleaner than extending `repo-readiness.test.ts`, place it under `apps/web-platform/test/*.test.ts` (matches the vitest node glob — NOT co-located under `server/`).

## Open Code-Review Overlap
2 open code-review issues touch `cc-dispatcher.ts`:
- **#3242** (review: tool_use WS event lacks raw name field) — **Acknowledge.** Unrelated concern (WS event shape, not workspace provisioning). Remains open.
- **#3243** (arch: decompose cc-dispatcher.ts into focused modules) — **Acknowledge.** A large refactor out of scope for a targeted bug fix; folding it in would balloon the diff and the brand-survival blast radius. Remains open; this PR keeps the cc-dispatcher edit minimal (route the ready-but-.git-gone case through the existing self-heal seam).

## Acceptance Criteria

### Pre-merge (PR)
- AC1: `resolveSoloFounderForInstallation` SELECT filters by BOTH `github_installation_id` AND normalized `repo_url`; a multi-repo org install with one solo workspace per repo resolves `kind:found` for the pushing repo (not `ambiguous`). Verified by the extended `resolve-founder-for-installation.test.ts` (RED before, GREEN after).
- AC2: a non-push webhook event under a multi-repo org install dispatches (no 404) — `github-webhook-founder-attribution.test.ts`.
- AC3: a genuine same-repo + same-install `>1` solo ambiguity STILL returns `kind:ambiguous` → route 404 + Sentry `op:founder-ambiguous` (defense retained) — same test file.
- AC4: a non-push event with absent `repository.full_name` drops via the pre-compose `none`/404 guard, NOT an ambiguous throw, AND does NOT issue the resolver SELECT.
- AC4b: an UNMAPPED non-push event (`check_suite` — the actual `WEB-PLATFORM-3M` prod signal) under a multi-repo org install resolves `kind:found` → falls through to the `actionClass` guard → `{received:true}` 200 ignore (NOT 404).
- AC4c: `db-error` from the repo-scoped resolver still returns 500 + `releaseDedupRow` (re-drivable), distinct from the 404 of none/ambiguous (GitHub retries 5xx, not 4xx).
- AC5: push path + `webhook-push-dispatch.test.ts` unchanged (resolver never called on push).
- AC6: a cold dispatch into a `repo_status='ready'` workspace whose `.git` is absent (seam `gitDirExists → false`) re-clones and the workspace becomes git-ready — the test asserts the INVARIANT (the `gitDirExists` seam goes `false → true`, i.e. `.git`/work-tree materialized), NOT the proxy "`ensureWorkspaceRepoCloned` returned `"ok"`" (5-way overloaded). On clone `"failed"`, surfaces `RepoNotReadyError` + `op:repo-readiness-self-heal` Sentry mirror — `repo-readiness`/`cc-reprovision` test.
- AC6b: **concurrent** cold dispatches on `ready`+`.git`-absent → at most one `.git` materializes AND the loser also terminates ready-or-honest (never fast-paths `{ok:true}` with `.git` absent).
- AC6c: a MEMBER-triggered heal that FAILS surfaces the correct honest reason to the member on the next dispatch — i.e. the `set_repo_status(error)` reason is read back by the gate for that member (the 108 split-write is re-targeted to the owner / `workspaces.repo_error`), NOT silently lost so the member retries forever.
- AC7: the COMMON `ready` + `.git`-present path still fast-returns `{ok:true}` with no DB/JWT round-trip — assert NEITHER `getFreshTenantClient` NOR any clone/lock seam is called on the fast path (only a local `existsSync`).
- AC7b: the `error`/stale-`cloning` self-heal path STILL acquires `claim_repo_clone_lock` (the thundering-herd guard is not relaxed by the ready-entry change) — regression assertion.
- AC8: `./node_modules/.bin/tsc --noEmit` green; full vitest suite green.
- AC9: ADR-044 amendment written (non-push repo-scope + Bug 2 ready-but-.git-gone consequence); C4 enumeration recorded (actors/systems/edges checked) and `.c4` tests green.

### Post-merge (operator)
- AC10: `doppler run -p soleur -c prd -- scripts/sentry-issue.sh --latest-event WEB-PLATFORM-3M` shows ZERO new founder-ambiguous events attributable to installation `122213433` (the install id in the prod event) in the 24h after deploy; any residual founder-ambiguous event is a genuine same-repo two-users-same-fork ambiguity on a DIFFERENT install (verify the `extra.installationId` + `count`). *Automation: read-only Sentry probe, run via the existing script post-deploy.*
- AC11: add re-eval note to #5274 and scope note to #4755 (`Ref #5274`, `Ref #4755` — NOT `Closes`, these remain open). *Automation: `gh issue comment` post-merge.*

## Test Scenarios
- Non-push, multi-repo org, one solo workspace per repo → correct founder, dispatch.
- Non-push, same repo + same install, two distinct solo workspaces (two-users-same-fork) → ambiguous 404 + page.
- Non-push, no `repository.full_name` → none/404.
- Push → unchanged (no resolver call).
- Cold dispatch, `ready` + `.git` present → fast-path `{ok:true}`, no clone/lock seam calls.
- Cold dispatch, `ready` + `.git` absent + install+repo present → clone → `{ok:true}`.
- Cold dispatch, `ready` + `.git` absent + clone fails → `RepoNotReadyError` + Sentry self-heal mirror.
- Cold dispatch, `error` + `.git` absent → existing self-heal still acquires `claim_repo_clone_lock` (herd-guard regression — AC7b).
- Two concurrent cold dispatches, `ready` + `.git` absent → at most one clone materializes `.git` AND the loser also ends ready-or-honest (never `{ok:true}` with `.git` absent) — verifies the Phase 2.2 lock-free choice (AC6b).
- Member-triggered heal FAILS → the member sees the correct honest reason on the next dispatch (108 split-write re-targeted — AC6c), not a silent retry loop.
- Stale/corrupt `.git` present (existsSync true, not a valid work tree) → documented residual: NOT auto-recovered (Start-Fresh `.git` must not be blown away).

## Risks & Mitigations
- **Cross-tenant misattribution (Bug 1):** repo_url filter MUST use the exact `normalizeRepoUrl` compose-before-normalize contract (the push path's precedent at `workspace-reconcile-on-push.ts:150`); the `>1` fail-closed branch is retained as the backstop. The `normalizeRepoUrl` TS↔SQL parity test is the load-bearing matching guard (ADR-044 hard merge gate) — no change to it.
- **Hot-path regression (Bug 2):** broadening `canRecover` must NOT add a DB/JWT round-trip to the common `ready`+`.git`-present path; only a local `existsSync` is permitted there (AC7 asserts no lock/clone seam on the fast path).
- **Lock semantics for the `ready` entry:** `claim_repo_clone_lock` only acquires `error`/stale-`cloning` rows — it will NOT flip a `ready` row. The recovery policy is SPLIT by DB state: `error`/stale-`cloning` keeps the lock (herd guard — AC7b); `ready`-but-`.git`-absent is lock-free, relying on the graft's `.git`-sentinel re-check (`ensure-workspace-repo.ts:239`). Default lock-free; the concurrency RED test (AC6b — asserts the LOSER's terminal state) gates falling back to Option (b) (extend the RPC, needs migration).
- **Member split-write (108) — FIRM fix on the FAILURE branch:** `set_repo_status` writes the caller's `users.repo_error`; for a member healing a shared workspace this targets the member while the gate reads the OWNER's row. On clone FAILURE this loops the member forever with no honest reason (the headline user). Re-target the write to the owner / `workspaces.repo_error` (requires a migration — AC6c). On the ready-entry SUCCESS branch, SKIP the `setRepoStatus(ready)` write entirely (status already ready; avoids the spurious member-row write + an RPC round-trip). Do NOT expand into the #4755 KB-route surface.
- **ADR amendment vs reversal:** this is an amendment consistent with ADR-044 Decision.1 (the push fan-out already keys on `(install, repo)`); the non-push amendment merely completes the same contract. Not a reversal — no CPO re-sign beyond the plan-time sign-off.

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is complete.)
- The Sentry event header for `WEB-PLATFORM-3M` was `check_suite` — an UNMAPPED event (not in `HEADER_TO_ACTION_CLASS`) that still reaches `resolveSoloFounderForInstallation` at `route.ts:313` BEFORE the `actionClass` guard at `:374`. The fix's repo-scoping covers it; do NOT assume only the 5 mapped classes hit the resolver.
- Bug 2's "no Sentry error exists" clue is BECAUSE the `ready` fast-path never reaches the `op:repo-readiness-self-heal` mirror — the fix makes that signal reachable. Do not read the current Sentry silence as "the clone is fine."
- `claim_repo_clone_lock` (migration 108) cannot acquire a `ready` row — do not wire the `ready`-entry re-clone behind it without first extending the RPC (a migration). Default to the lock-free, sentinel-guarded graft (Option a in Phase 2.2).
