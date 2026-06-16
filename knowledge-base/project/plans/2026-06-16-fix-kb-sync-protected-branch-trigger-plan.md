---
title: "fix: KB-sync protected-branch trigger — route writes to soleur/kb-sync + PR"
type: fix
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
closes: 5426
brainstorm: knowledge-base/project/brainstorms/2026-06-16-kb-sync-trigger-fix-brainstorm.md
spec: knowledge-base/project/specs/feat-kb-sync-trigger-fix/spec.md
branch: feat-kb-sync-trigger-fix
pr: 5427
created: 2026-06-16
revised: 2026-06-16  # post plan-review: dropped safeCommitAndPr reuse (wrong-repo defect) → thin inline path
---

# 🐛 fix: KB-sync protected-branch trigger — route writes to `soleur/kb-sync` + PR

## Enhancement Summary

**Deepened:** 2026-06-16. **Gates:** 4.6 User-Brand Impact ✓, 4.7 Observability ✓, 4.8 PAT-shaped ✓ (none),
4.9 UI-wireframe ✓ (no UI surface → skip). **Round-1 verify-the-negative:** all load-bearing existing-behavior
claims confirmed by grep (safeCommitAndPr repo-binding, `runConnectedRepoGit` forbidden list, App scope, helper signatures).

**Key improvements (precedent-diff, Phase 4.4):**
1. **Use `createPullRequest` (`github-app.ts:1236`) + `getInstallationOctokit` (`github/app-client.ts:88`)** — generic, owner/repo-parameterized, non-cron PR + Octokit helpers. Replaces the rejected `safeCommitAndPr` entirely.
2. **Derive `{owner, repo}` via the `agent-runner.ts:1478-1590` `repo_url`→owner/repo parse + `GITHUB_NAME_RE` guard** (ADR-044 canonical workspace read) — not git-remote parsing.
3. **Accretion = tree-overlay, not cherry-pick** (see R1). Cherry-pick is *novel* (only in session-sync's forbidden list) and 3-way-conflict-prone across diverged histories; the conflict-free latest-KB-wins shape is simpler and correct for single-source KB.
4. **`createPullRequest` lacks a `draft` param** — open a **non-draft** PR (directly user-mergeable, reuses the helper verbatim) rather than extending it; "never auto-merged by Soleur" is the invariant, not "draft".

## Overview

Concierge auto-commits the user's `knowledge-base/**` back to their connected repo after every
session. `syncPush` (`apps/web-platform/server/session-sync.ts:551`) stages the allowlist, commits
onto the **checked-out default branch**, then issues a **bare `git push`** (`:601`). When the
user's default branch is protected, the push is rejected and the commit is stranded as an
un-pushable orphan — a "divergence treadmill" that PR #5423's downstream `selfHealNonFastForward`
(`workspace-sync.ts:185`) re-heals every session, leaving a permanent `soleur/recovered-kb-sync-<ts>`
ref each time.

**This plan fixes the trigger (item A of #5426).** On a push rejection classified as
*protected-branch*, `syncPush` accretes the latest KB tree onto a durable `soleur/kb-sync` side branch
in the **user's own repo**, opens/updates a **never-auto-merged** PR into the user's default branch,
then resets the local default branch back to `origin/<default>` so no orphan commit remains. The
common case (unprotected default) is behaviourally unchanged.

> **Plan-review correction (2026-06-16):** the brainstorm's "reuse `safeCommitAndPr` (ADR-054)"
> mechanism was rejected at plan-review. `safeCommitAndPr` is **hardcoded to the Soleur monorepo**
> (`_cron-shared.ts:10-11` `REPO_OWNER="jikig-ai"`/`REPO_NAME="soleur"`; `_cron-safe-commit.ts:614`
> `base:"main"`; `:543` `checkout -B` discards prior commits) — it cannot open a PR in an arbitrary
> user repo and cannot accrete onto a durable branch. Approach A is preserved; only the *implementation*
> changes from "call the cron helper" to a **thin inline push + create-or-update-PR against the user's
> repo** (~40-60 lines in `session-sync.ts`). Confirmed by grep + DHH + Kieran.

**Approach A** was chosen at brainstorm over B (uniform silent side branch — leaves writes
undelivered) and C (stop-the-bleed — drops writes). Item B (recovery-branch retention sweep) and the
in-product status surface are deferred (#5428, #5429).

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Codebase reality | Plan response |
|---|---|---|
| "Reuse `safeCommitAndPr` (ADR-054)" | Helper is **bound to jikig-ai/soleur + base:main** (`_cron-safe-commit.ts:16,609-632`); `checkout -B` (`:543`) resets the branch to current HEAD, discarding prior commits; clean-index precondition (`:470-478`) rejects a pre-staged index. **Unusable for a user-repo durable-branch PR.** | **Dropped.** Thin inline path against the user's repo instead. |
| GitHub App needs `pull_requests:write` (OQ2) | Already granted — `infra/github-app-manifest.json:26`. ✅ | No scope/IaC change. |
| `classifyGitSyncError` can classify the rejection | Lives in `workspace-sync.ts:34`, classifies **pull** aborts only; `syncPush` catches **push** errors generically; `reset`/`branch`/`push` are FORBIDDEN through `runConnectedRepoGit` (`session-sync.ts:39-56`). | Add `classifyPushError` keyed on `GH006` + `remote rejected`; run all branch/reset/push via `gitWithInstallationAuth`, never `runConnectedRepoGit`. |
| Single per-user side branch | ADR-044: repo state + `github_installation_id` live on `workspaces`; a push fans out to every workspace sharing `(installation_id, normalized repo_url)`. | `soleur/kb-sync` + its PR are **per-repo**; co-member sessions can race (R3, accretion + retry-next-session). |
| Default branch is `main` | User repos may use any default; `resolveDefaultBranch` (`workspace-sync.ts:54`, `symbolic-ref --short refs/remotes/origin/HEAD`) already resolves it dynamically. | Use it for the side-branch base + PR base; never hardcode `main`. |
| selfHeal recovery is downstream | Confirmed: `selfHealNonFastForward` runs on `/api/kb/sync` + webhook reconcile (`workspace-sync.ts`), distinct from `syncPush`; only branches-aside when `localCommits>0` on default (`:223`). | Default ending `== origin` makes selfHeal go cold for the protected path (consequence of AC3). |

## User-Brand Impact

**If this lands broken, the user experiences:** their post-session knowledge-base writes never reach
their connected repo (stranded on default, or dropped), so the product looks broken and their work
appears lost — `syncPush` (`session-sync.ts:551`) is the artifact.

**If this leaks, the user's data/workflow is exposed via:** a mis-targeted push/PR writing
`knowledge-base/**` to the wrong branch or base — but the destination is always the user's own
connected repo (no third-party recipient).

**Brand-survival threshold:** single-user incident. → `requires_cpo_signoff: true` (carried forward
from brainstorm CPO review); `user-impact-reviewer` runs at PR-review time.

## Compliance (GDPR gate)

GDPR-gate trigger (b) fired (single-user-incident threshold). **Determination: no new regulated-data
surface.** No schema/migration/auth/RLS change; no new recipient — `knowledge-base/**` already flows
to the user's own connected repo. The fix only changes the *branch* the writes land on and adds an
intra-repo draft PR of the user's own KB diff. No Art. 9 processing, no new sub-processor, no Art. 30
change. No critical findings; no `compliance-posture.md` write.

## Implementation Phases

Single atomic PR. Ordered contract-changing → consumer.

### Phase 1 — Push-error classification (contract)
- Add `classifyPushError(err)` in `session-sync.ts`, returning `protected_branch` when stderr contains
  `GH006` AND/OR `remote rejected` with a protection tail (`protected branch hook declined`,
  `Protected branch update failed`, `Changes must be made through a pull request`, `required status
  check`, `approving review`). Key on `GH006` + `remote rejected`; **tolerate varied tails** (Kieran P1).
- Distinguish a `persistent_other` class for non-protection persistent rejects that must NOT loop —
  notably `shallow update not allowed` (these are shallow clones, `syncPull:522`) — so they get a
  distinct Sentry op rather than silently retrying forever (SpecFlow G3).
- Auth/network/transient rejections do NOT match either class → existing best-effort retry.
- Unit-test against **synthesized** stderr fixtures (`cq-test-fixtures-synthesized-only`).

### Phase 2 — Protected-fallback path in `syncPush` (inline, user-repo-targeted)
Order operations so **default is reset only AFTER the side-branch push succeeds** — on any failure the
original commit stays on default and retries next session (no data loss; SpecFlow G2). All git via
`gitWithInstallationAuth` (NOT `runConnectedRepoGit` — forbids reset/branch/push).
1. Resolve `defaultBranch` (`resolveDefaultBranch`) and the user's `{owner, repo}` via the
   `agent-runner.ts:1478-1590` `repo_url`→owner/repo parse + `GITHUB_NAME_RE` guard (ADR-044 canonical
   workspace read) — not git-remote parsing.
2. `fetch origin <defaultBranch> soleur/kb-sync` (side branch may not exist yet).
3. Build `soleur/kb-sync` by **accretion via tree-overlay** (not cherry-pick — see R1): check out a
   local `soleur/kb-sync` tracking `origin/soleur/kb-sync` (or branch it from `origin/<defaultBranch>`
   if the side branch doesn't exist yet), overlay the latest KB tree
   (`git checkout <captured-default-HEAD> -- knowledge-base/`), and commit. Latest-KB-wins is correct
   for single-source KB and is conflict-free. This preserves prior sessions' writes (the side branch's
   non-KB history is untouched) and **naturally migrates an already-stranded clone** (its orphan KB
   state is in `<default-HEAD>`; the stale `recovered-kb-sync-*` refs are swept by #5428 — R4).
4. Push `soleur/kb-sync` with an explicit refspec, fast-forward (no `--force`). On non-fast-forward
   (concurrent co-member push, R3) → do NOT reset default; bail best-effort, retry next session.
5. Create-or-update the PR in the **user's repo**: `getInstallationOctokit(installationId)` →
   `GET /repos/{owner}/{repo}/pulls` (`head: "soleur/kb-sync"`, `base: <defaultBranch>`, `state: "open"`)
   to find an existing open PR; if none, `createPullRequest(installationId, owner, repo, "soleur/kb-sync",
   <defaultBranch>, title, body)` (`github-app.ts:1236`; **non-draft** — directly user-mergeable, never
   auto-merged by Soleur; body explains the protected default + how to merge); else no-op (the branch
   push already updates the existing PR).
6. Only now `reset --hard origin/<defaultBranch>` on default and restore HEAD to `<defaultBranch>`.
7. Emit observability (Phase 3).

### Phase 3 — Observability
- Two queryable, non-paging Sentry ops (simplicity: dropped the success `pr-opened` op — provable from
  the PR existing + `kb_sync_history`): `kb-sync.push-protected-fallback` (entry; payload carries the
  resulting PR number/URL + commit count) and `kb-sync.protected-fallback-failed` (the only
  paging-adjacent one; covers side-branch push failure, Octokit failure, `persistent_other`).
- Preserve operator-facing message strings.

### Phase 4 — Tests
- Extend `apps/web-platform/test/kb-route-helpers.test.ts`; add `test/server/session-sync-protected-fallback.test.ts`
  (matches `vitest.config.ts` `test/**/*.test.ts`).

## Files to Edit
- `apps/web-platform/server/session-sync.ts` — `classifyPushError`, the protected-fallback path, observability.
- `apps/web-platform/test/kb-route-helpers.test.ts` — extend coverage.

## Files to Create
- `apps/web-platform/test/server/session-sync-protected-fallback.test.ts`.

(No edit to `_cron-safe-commit.ts` — the inline path does not touch the cron write surface, so the
`cron-safe-commit-parity` test is unaffected.)

## Acceptance Criteria

### Pre-merge (PR)
- **AC1.** `classifyPushError` → `protected_branch` for `GH006`/`remote rejected (protected branch hook
  declined)` fixtures (incl. required-review/required-check tails); `persistent_other` for `shallow
  update not allowed`; neither for auth/network fixtures. (unit)
- **AC2.** On a protected rejection, the fallback pushes `soleur/kb-sync` to the **user's repo** (owner/repo
  from the `repo_url`→owner/repo parse, base = `resolveDefaultBranch`, never hardcoded `main`) and opens a
  PR via `createPullRequest` (non-draft, never auto-merged), base = the resolved default. (mocked Octokit/git)
- **AC3.** After a successful fallback, local default HEAD `== origin/<default>` and HEAD is on `<default>`
  (no orphan; selfHeal stays cold as a consequence). (git-state test)
- **AC4.** Two consecutive fallbacks accrete onto **one** `soleur/kb-sync` whose KB tree equals the
  latest session's (content-equality) while preserving the branch's prior commits, and reuse **one**
  open PR — built by tree-overlay onto `soleur/kb-sync`, never `checkout -B` from default. (test) —
  *this was the understated R1 defect.*
- **AC5.** Unprotected-default path unchanged: `git push` succeeds → no fallback, history recorded as today. (test)
- **AC6.** **Failure preserves writes:** if the side-branch push or PR call fails, the original commit
  remains on default (default NOT reset) and `kb-sync.protected-fallback-failed` is emitted; next session
  retries. (test — closes SpecFlow G2)
- **AC7.** Idempotent re-entry: a fallback that finds `origin/<default>..HEAD` empty (writes already
  delivered) is a no-op that reuses the existing PR and is NOT reported as failure. (test — Kieran P2)
- **AC8.** Typecheck `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`; tests
  `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/session-sync-protected-fallback.test.ts test/kb-route-helpers.test.ts`.

### Post-merge (operator)
- None. Deploys via `web-platform-release.yml` on merge (container restart is the deploy mechanism).
  `Ref #5426`; close #5426 after Phase 5 verification.

## Domain Review

**Domains relevant:** Engineering, Product (carry-forward from brainstorm `## Domain Assessments`).

### Engineering (CTO)
**Status:** reviewed (carry-forward)
**Assessment:** Simplest invariant = default stays `== origin` so selfHeal goes cold; key risk = migration
of already-stranded clones (now resolved by accretion, Phase 2 step 3). Endorsed deferring item B.

### Product (CPO)
**Status:** reviewed (carry-forward)
**Assessment:** Requires visible delivery (the draft PR) over a silent side branch — satisfied. App
`pull_requests:write` confirmed granted. Status surface deferred (#5429).

### Product/UX Gate
**Tier:** none — no UI-surface file in Files to Create/Edit (server `.ts` + tests only). User-facing
visibility is a GitHub draft PR in the user's own repo, not an in-product screen.
**Pencil available:** N/A (no UI surface)

CPO sign-off carried forward (threshold = single-user incident).

## Observability

```yaml
liveness_signal:
  what: kb_sync_history rows + "Sync push completed" info log per session syncPush
  cadence: per user session end
  alert_target: Sentry issue alert on kb-sync.protected-fallback-failed (non-paging)
  configured_in: apps/web-platform/infra/sentry/*.tf (add issue alert for the new op)
error_reporting:
  destination: Sentry via reportSilentFallback/warnSilentFallback (feature session-sync)
  fail_loud: protected-fallback-failed is reported; entry op is warn-level
failure_modes:
  - mode: protected-branch push rejection (expected, recovered to soleur/kb-sync + PR)
    detection: Sentry op kb-sync.push-protected-fallback (warn; payload has PR url + commit count)
    alert_route: dashboard query, non-paging
  - mode: fallback failed (side-branch push reject, Octokit error, or persistent_other/shallow)
    detection: Sentry op kb-sync.protected-fallback-failed
    alert_route: sentry_issue_alert, non-paging; writes stay on default for retry
  - mode: treadmill regression
    detection: existing op self-heal-recovered-diverged recurring for the SAME workspace
    alert_route: dashboard query (the #5426 re-eval signal)
logs:
  where: pino → Better Stack drain; Sentry for warn+
  retention: per existing platform retention
discoverability_test:
  command: "query Sentry op:kb-sync.push-protected-fallback (feature:session-sync) and confirm zero NEW op:self-heal-recovered-diverged for the affected workspace after a protected-repo session"
  expected_output: "≥1 push-protected-fallback (with PR url) per protected-repo session; self-heal-recovered-diverged stops recurring for that workspace"
```

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (63 open) returned zero matches for
`server/session-sync.ts`, `server/workspace-sync.ts`, or `_cron-safe-commit.ts`.

## Test Scenarios
1. Unprotected default → direct push succeeds, no fallback.
2. Protected default, first session → accrete onto new `soleur/kb-sync` + draft PR; default clean.
3. Protected default, second session → same branch (both commits), same PR.
4. Auth/network rejection → no fallback, retry next session.
5. Persistent `shallow update not allowed` → `persistent_other`, distinct op, no infinite loop.
6. Already-stranded clone (orphan commit on default) → first post-fix fallback accretes the orphan +
   new commit onto `soleur/kb-sync` (migration); `recovered-kb-sync-*` swept later by #5428.
7. Side-branch push / Octokit failure → default NOT reset, writes survive, failure op emitted.

## Risks & Mitigations
- **R1 (durable-branch accretion) — RESOLVED in design (was the understated defect).**
  **Precedent-diff (deepen-plan 4.4):** the only branch-manipulation precedent is
  `selfHealNonFastForward`'s `git branch <recovery> HEAD` (`workspace-sync.ts:288`) — but that branches
  *at the current HEAD*, a different shape from accreting onto a *diverged remote* branch. **Cherry-pick
  is novel** (appears only in session-sync's forbidden list) and risks 3-way conflicts across diverged
  histories. **Chosen: tree-overlay** (`git checkout soleur/kb-sync` → `git checkout <default-HEAD> --
  knowledge-base/` → commit) — conflict-free, latest-KB-wins (correct for single-source KB), no `-B`
  reset. AC4 (content-equality + prior-commits-preserved) is the guard. Pattern is otherwise novel —
  reviewers should scrutinize the git sequence at /work.
- **R2 (clean default without stranding) — RESOLVED in design.** `reset --hard origin/<default>` runs
  ONLY after a successful side-branch push, via `gitWithInstallationAuth`. Avoids the `reset --soft`
  staged-index trap entirely (no re-stage; we move existing commits).
- **R3 (shared-repo concurrency, ADR-044 fan-out).** Co-member sessions race on `soleur/kb-sync`; the
  non-fast-forward loser bails best-effort (no default reset) and retries next session. Risks entry +
  the failure op cover it; no new test.
- **R4 (already-stranded clones) — RESOLVED in design.** Accretion captures pre-existing orphan commits
  (Phase 2 step 3 / TS6). No separate migration step; recovery refs cleaned by #5428.
- **R5 (unmergeable PR, SpecFlow G6).** If the user's branch protection requires reviews/checks the bot
  PR can't satisfy, the PR can't auto-deliver — writes accrue on `soleur/kb-sync` until the user merges.
  The PR body states this; it is the user's repo policy, not a Soleur bug. Documented, not solved.
- **R6 (ADR-054 relationship).** No conflict: `safeCommitAndPr` is Soleur-repo-bound and session-sync
  already owns its own allowlisted persistence; the inline path extends that existing pattern, not the
  cron write surface. Consider a short ADR documenting the `soleur/kb-sync`-on-protected-default
  branch-topology decision (CTO suggestion) — defer to deepen-plan/work.

## Sharp Edges
- A plan whose `## User-Brand Impact` is empty/`TBD` fails deepen-plan Phase 4.6 — this one is filled.
- All branch/reset/push in the fallback MUST use `gitWithInstallationAuth`; `runConnectedRepoGit`
  forbids `reset`/`branch`/`push` (`session-sync.ts:39-56`) and will throw.
- Resolve owner/repo/base dynamically (clone origin + `resolveDefaultBranch`) — never hardcode
  `jikig-ai`/`soleur`/`main` (the exact defect that sank the `safeCommitAndPr`-reuse approach).
- Test path must be `test/**/*.test.ts` (vitest include); a co-located `server/*.test.ts` is skipped.
- The PR `head` qualifier is `{owner}:soleur/kb-sync` for same-repo PRs; confirm against the user-repo
  (not cross-fork) shape at /work.

## Alternative Approaches Considered
| Approach | Why rejected |
|---|---|
| **Reuse `safeCommitAndPr`** (original Approach-A mechanism) | Hardcoded to jikig-ai/soleru + base:main + `checkout -B`; cannot target a user repo or accrete. Replaced by inline. |
| **B — uniform silent side branch** | Changes the common case; leaves writes undelivered to default (invisible drift — CPO). |
| **C — stop-the-bleed only** | Stops the treadmill but drops the user's KB writes on a protected repo. |
| **Auto-merge the PR** | Default is protected precisely so it can't be auto-merged; `none`/user-merge is correct. |
| **Pre-flight GitHub-API protection check** | Adds a token-scoped API call + staleness on the common path; discovery-via-rejection pays cost only when rejected. |

## Phase 5 — Post-merge verification (close #5426)
After deploy, confirm via Sentry that a protected-repo session emits `kb-sync.push-protected-fallback`
(with a PR url) and that `self-heal-recovered-diverged` stops recurring **for the affected workspace**
(scope to the workspace from the original re-eval signal — pre-existing stranded clones may still emit
until #5428's sweep, so do not read the global count). Then `gh issue close 5426`.
