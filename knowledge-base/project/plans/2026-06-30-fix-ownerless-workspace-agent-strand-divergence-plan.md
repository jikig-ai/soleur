---
title: "Verify (post-merge): 754ee124 strand fix #5734 executes on the agent surface — de-anomalize via data check + Sentry exec-path confirmation (implementation already merged)"
type: fix
date: 2026-06-30
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issues: "#5733 #5591"
prior_fixes: "#5716 #5584 #5730"
implemented_by: "#5734 (commit 190ab58a5, merged 2026-06-30 16:32)"
posture: "verification-only (code already on main)"
---

# Verify (post-merge): `754ee124` strand fix `#5734` on the agent surface — implementation already merged

## ⚠️ STALE-PREMISE RECONCILIATION (2026-06-30, planning pass)

**The implementation this plan describes is ALREADY MERGED TO MAIN.** Commit
`190ab58a5` (PR #5734, *"heal gitdir-pointer strands + observe agent self-stop +
tolerate N co-owners (#5734)"*, merged 2026-06-30 16:32) ships **all three
committed deliverables** of the original plan, verified present in this worktree's
tree (`git merge-base --is-ancestor 190ab58a5 origin/main` ⇒ YES; branch is 0
commits behind main):

| Original deliverable | Shipped in #5734 as |
|---|---|
| **H2 gitdir-pointer strand heal** (primary hypothesis) | `isStrandingFilePointer` + escaping-pointer unlink/re-clone in `ensure-workspace-repo.ts:154` |
| **Phase 1b agent-surface strand observability** | `reportAgentReadinessSelfStop` (distinct Sentry issue, pseudonymized) in `repo-resolver-divergence.ts:98` |
| **#5591 owner-less de-anomalization** | **Reframed + fixed**: 754ee124 is NOT owner-less — it has **2 legitimate co-owners**; the `.maybeSingle()` ERRORED on ≥2 rows → false "owner-less" warn. Fixed via select-all-owners + deterministic pick in `workspace-reconcile-on-push.ts:254-293`. **No owner-canary row is missing; Phase 1a "restore the canary" is REFUTED.** |

**Consequence — this plan is now VERIFICATION-ONLY.** There is NO fourth code
fix to write (writing one would duplicate merged code — the exact
already-resolved trap Phase 0.6 + `hr-before-asserting-github-issue-status`
guard against). #5733/#5591 remain OPEN only because their closure is gated on
**post-merge operator verification** (#5591 also has its own open PR #5783).

**What remains (the investigate-first ask, intact):** confirm via live Supabase +
Sentry that the merged fix actually executes on the **agent's** exec-path surface
(the `2026-06-30-verify-the-fixed-code-path-actually-executes` discipline),
reproduce `/soleur:go` on `754ee124`, then close #5733. The Implementation Phases
below are **superseded by the "Verification Plan (active)" section** added at the
end; the original H2/H3/H1 branching + Phase 1a canary restore are retained ONLY
as the historical pre-merge analysis that #5734 acted on.

## Enhancement Summary (deepen-plan, 2026-06-30)

**Sections enhanced:** Overview, Hypotheses, Research Reconciliation, Phases 0-3, Observability, Architecture Decision, User-Brand Impact, Acceptance Criteria, Files-to-Edit, Sharp Edges.
**Review panel (6 agents):** architecture-strategist, data-integrity-guardian, security-sentinel, spec-flow-analyzer, observability-coverage-reviewer, verify-the-negative/simplicity. Verify-the-negative CONFIRMED all five code-level factual claims (one container/one volume; directive self-stop emits no server event; reset-to-solo already instrumented; non-solo audit zero-row mechanism; membership probe role-agnostic).

### Load-bearing corrections applied
1. **`workspaces.owner_user_id` does NOT exist** (security + data-integrity + architecture, P1). Ownership lives only in the `workspace_members(role='owner')` canary (the missing row) or derives via `organizations.owner_user_id` through `workspaces.organization_id`. For a non-solo anomaly workspace that org-owner may itself be the corrupted value. The restore IS the act of granting GitHub-installation-token access — it must org-join, gate on `owner_user_id IS NOT NULL` (Art. 17 erasure), surface the resolved principal (user_id + email + org lineage) for operator ack, and use **check-then-INSERT-or-UPDATE** (not blind `ignoreDuplicates`).
2. **Add H3 + re-rank hypotheses** (architecture, P0). A third resolution outcome — `claim === userId` early-exit (`workspace-resolver.ts:376-378`, when `current_workspace_id` is null or already the operator's solo id) — produces a strand with the operator a valid member but the active workspace pointing elsewhere; the canary restore has **zero** effect there. H1 (reset-to-solo) CANNOT produce the observed `not a git repository` strand (it shows the switcher or runs the wrong repo). **Re-rank: H2 + H3 primary; H1 a low-probability tail.** Reposition the canary restore as **invariant-repair + audit-unblock**, valid as a *strand* fix only under the narrow H1 conjunction.
3. **DROP the reconcile auto-self-heal** (security + architecture + simplicity, P0/P1). An unattended per-push service-role `workspace_members(role='owner')` insert bypasses the sanctioned `transfer_workspace_ownership` path (caller-is-owner, single-owner enforcement #4520, attestation R6, audit actor), contradicts the Phase 1a ack gate, masks the creation-path bug, and could self-perpetuate a wrong-principal grant. The systemic guard belongs at the **provisioning/creation write-site** or a dedicated **ack-gated repair routine**; reconcile keeps the `ownerless-reconcile` warn + defers.
4. **Observability deliverable hardened** (observability + spec-flow, P1). The self-stop is **prompt-driven** (`/soleur:go` Step 0.0; `routine-authoring-directive.ts:20` only on `routineAuthoring=true`) — confirm the actual driver in Phase 0. A **server-side `git rev-parse` runs OUTSIDE the agent's frozen bwrap mount** and can pass while the agent's in-sandbox probe fails — so the mirror must read the agent's own bwrap mount/cwd (or reuse the dispatch readiness-gate result), else it reproduces the blind spot. The discoverability command must use the EU host `jikigai-eu.sentry.io` + `SENTRY_ISSUE_RO_TOKEN` via `scripts/sentry-issue.sh`, and the mirror needs a **distinct `Error` message** (the shared `repo_resolver_divergence` helper groups all ops into one issue → `jq length` mis-counts).
5. **C4 split to a separate docs PR** (simplicity); **ADR scoped to the invariant + the keying-divergence trust boundary** (claim-source vs installation+repo), one owner (ADR-044 amends ADR-038), mechanism "under investigation" until Phase 0 resolves.
6. **Audit-unblock description corrected** (data-integrity): after restore the code path **switches** to `appendKbSyncRow(ownerId)` (mints an owner JWT, calls `append_kb_sync_row` keyed on `auth.uid()=ownerId`) — NOT `append_kb_sync_row_for_user`; the recovered row lands in the **owner's** `kb_sync_history`.

## Overview

The operator's containerized `/soleur:go` Concierge agent still strands on
`fatal: not a git repository` for workspace `754ee124` (→ `jikig-ai/soleur`)
after three merged + deployed server-side fixes (#5716, #5584, #5730). Issue
#5733 proposes the agent runs in a **separate container with a divergent
`/workspaces` volume** and asks the fresh session to verify that FIRST.

**Plan-time investigation REFUTES the separate-container hypothesis** (one
container, one volume) and surfaces a **workspace-ID divergence on the same
filesystem**, rooted in the **owner-less `754ee124` anomaly** (#5591
continuation). The exact strand mechanism has **three** code-grounded
hypotheses (H2/H3 primary, H1 tail) that only **production evidence** can
distinguish — and per the load-bearing learning
`2026-06-30-verify-the-fixed-code-path-actually-executes-on-the-affected-surface.md`,
this plan is **investigation-first**: Phase 0 pulls live Supabase + Sentry
evidence and selects the fix branch. It does **not** ship a fourth code fix on
code-reading alone.

A layer-independent finding holds under every hypothesis and is the deepest
reason all three prior fixes left "zero events on the agent surface": **the
agent's final self-stop is prompt-driven** — `/soleur:go` Step 0.0 (and, on the
routines tab, `routine-authoring-directive.ts:20`) tells the agent to run `git
rev-parse --is-inside-work-tree` inside its bwrap sandbox and STOP if it is not
a work tree (`git-worktree-validity.ts:8-9` documents this exact symptom). That
self-stop is the agent *reasoning over prompt text* — it emits **no server-side
Sentry event**. Making the strand observable is a committed deliverable.

## Problem Statement

### Confirmed facts (code-verified at plan time; CONFIRMED by the verify-the-negative pass)
- **One container, one volume.** Prod + canary `docker run` both mount the
  single Hetzner block volume `-v /mnt/data/workspaces:/workspaces`
  (`apps/web-platform/infra/ci-deploy.sh:640-661,865-880`,
  `infra/cloud-init.yml:681-693`). The `/soleur:go` agent runs **in-process** in
  the web-platform container via the Claude Agent SDK `query()`
  (`cc-dispatcher.ts:1481` `realSdkQueryFactory`), confined by an **in-process
  bubblewrap sandbox** (`agent-runner-sandbox-config.ts:70`), NOT a separate
  container. `agent-on-spawn-requested.ts` is the GitHub leader-loop — unrelated.
- **Bash runs in a frozen bwrap sandbox.** The agent's Bash tool (which runs
  `git rev-parse`) executes in a bwrap namespace whose `cwd` + mount set are
  **frozen once per `query()`** (`agent-runner-query-options.ts:149` `cwd:
  args.workspacePath`; `agent-runner-sandbox-config.ts:93-94` `allowWrite:
  [workspacePath]`, `denyRead: ["/workspaces","/proc"]`). File tools run
  in-process with full-container FS visibility. A Bash-vs-file asymmetry is a
  **mount/path** problem (learning `2026-06-15-bash-bwrap-sandbox-mount-visibility-vs-cwd-persistence.md`).
- **Two consumers key the workspace path by DIFFERENT identifiers** (the
  architectural root). Reconcile-on-push heals `/workspaces/<id>` keyed on
  `(installation_id, repo_url)` → `/workspaces/754ee124`
  (`workspace-reconcile-on-push.ts:160-167,301`), **independent of the operator's
  session claim**. The agent resolves its cwd from the user's **active
  workspace** (`user_session_state.current_workspace_id` →
  membership-verified → fail-closed to solo `userId`;
  `workspace-resolver.ts:365-450`). These two keys can point at different dirs.
- **`754ee124` is owner-less + non-solo.** The `workspace_members(role='owner')`
  canary is missing (ADR-038 N2 invariant drift) → `owner-less workspace
  reconciled` fires every push (`workspace-reconcile-on-push.ts:279-299`).
  `754ee124` is **non-solo** (`workspaces.id != organizations.owner_user_id`).
  The `workspace_members` PK is `(workspace_id, user_id)` (migration 053 L91) —
  one row per user per workspace, so "owner-less" for the operator-as-owner means
  the operator has **no** membership row at all.
- **Non-solo owner-less ⇒ recovery audit silently dropped.** With `ownerId=null`,
  reconcile writes the audit via `appendKbSyncRowForWorkspace(service, 754ee124)`
  → `append_kb_sync_row_for_user(p_user_id=754ee124)` → UPDATE `WHERE id=754ee124`
  against `users` → **zero rows** (754ee124 is not a users.id; migration
  `100_append_kb_sync_row_for_user_rpc.sql:46-73` documents this). The
  `kb_sync_history recovered=true` signal cannot land.

### What is NOT yet proven (the Phase 0 gate)
The reset-to-solo path is **already observable and gracefully handled** by
ADR-044 PR-1/#5394: `cc-dispatcher.ts:1552` fires
`reportRepoResolverDivergence(op:"non-member-claim-reset")` and `:1644` throws
`WorkspaceNotReadyError(no-repo-switch)` (switcher copy) when reset + no repo. So
"reset-to-solo" (H1) does **not** produce the observed raw git strand — it must
be distinguished by live data from H2/H3.

## Research Reconciliation — Issue Hypothesis vs. Codebase

| Issue / draft claim | Reality (code-verified) | Plan response |
|---|---|---|
| "Agent container `/workspaces/<id>` is a **different filesystem/host**" | ONE container, ONE `/mnt/data/workspaces` volume; agent is an in-process bwrap sandbox | Drop separate-container framing → workspace-ID divergence on the same volume + bwrap frozen mount. |
| "Fix layer is agent-container provisioning/entrypoint" | No separate agent container exists | Fix lives in active-workspace-ID resolution / owner-less de-anomalization / agent-surface observability (all web-platform server). |
| #5591: "`52af49c2` & `754ee124` are same-repo duplicates → de-dup" | #5733 live: different repos (chatte vs soleur); **do NOT de-dup** | De-anomalize the owner-less canary; never de-dup. |
| (draft) "restore `owner_user_id` from `workspaces` (source of truth)" | **`workspaces` has no `owner_user_id` column** (053:61-73); owner derives via `organizations.owner_user_id` and may itself be corrupt for this anomaly | Org-join derivation + `NOT NULL` gate + operator-confirmed principal display; restore is an access-control grant. |
| (draft) "reset-to-solo is the silent zero-Sentry path" | Already instrumented (#5394) | True zero-event root is the **prompt-driven Step 0.0 self-stop** (no server event). Add agent-surface observability. |
| (draft) "H1 canary restore is the operative strand fix" | H1 cannot produce the raw git strand (switcher/wrong-repo instead) | Re-rank H2/H3 primary; canary restore = invariant-repair + audit-unblock. |

## Proposed Solution

**Investigation-first, branched.** Phase 0 pulls live evidence and selects the
mechanism. Two committed deliverables hold regardless of branch:
1. **De-anomalize the owner-less `754ee124`** (restore the owner canary;
   #5591) — a confirmed ADR-038 N2 invariant drift, valuable independent of the
   strand and required to unblock the recovery audit signal.
2. **Agent-surface strand observability** — make the prompt-driven readiness
   self-stop emit a server-side Sentry signal so the next strand is visible.

### Hypotheses (ranked)
- **H2 (PRIMARY) — member-of-`754ee124`, `.git` invalid to the bwrap probe.**
  Operator has a `(754ee124, operator)` row → dispatch against `/workspaces/754ee124`;
  but its `.git` is invalid to the agent's bwrap `git rev-parse` at dispatch.
  Most likely realization (architecture review): a `.git` **file** gitdir-pointer
  whose target lives under `/workspaces` (unreadable inside the sandbox's
  `denyRead:["/workspaces"]`) — a **mount-visibility strand no server-side heal
  can repair**; or a heal landing after the bwrap mount freeze; or
  lstat-valid-but-`rev-parse`-invalid HEAD/objects. Fix: gate the dispatch
  self-heal on the **same signal the agent uses** (`git rev-parse`, not lstat
  `isValidGitWorkTree`) across **all** call sites, and probe the gitdir-pointer
  case in Phase 0.
- **H3 (PRIMARY) — `current_workspace_id` never `754ee124`.** The `claim ===
  userId` early-exit (`workspace-resolver.ts:376-378`) returns the solo id with
  no membership probe and no `resetFromClaim`; reconcile heals `754ee124` but the
  agent reads elsewhere. Canary restore has **no** effect here. Fix surface:
  workspace-activation (ensure `current_workspace_id → 754ee124`), plus the
  observability signal so this is no longer silent.
- **H1 (TAIL) — non-member reset to solo.** Already instrumented (`:1552`) and
  terminally handled (`:1644` switcher / self-heal clones the solo repo) — so it
  yields the switcher or a wrong-repo run, NOT the observed strand, UNLESS the
  solo dir is itself `.git`-invalid while `repoUrl` is present. The owner-canary
  restore is the H1 fix **only iff** `organizations.owner_user_id == operator AND
  the operator has no member row` (otherwise it is purely invariant-repair).

## Implementation Phases

### Phase 0 — Live exec-path verification (BLOCKING; no code ships until complete)
0.0 **Read the resolver predicate.** Read `workspace-resolver.ts:365-450` and
   record the EXACT membership gate (role filter? `attestation_id`? `org_id`?) so
   "a row exists" is converted to "the resolver returns `754ee124`."
0.1 **Supabase (read, via Supabase MCP):**
   - `workspaces`: `id, organization_id, repo_url, repo_status, repo_last_synced_at, github_installation_id` for `754ee124` and `52af49c2` (**note: no `owner_user_id` column** — derive owner via the org join below).
   - `organizations`: `owner_user_id` via `SELECT o.owner_user_id FROM workspaces w JOIN organizations o ON o.id=w.organization_id WHERE w.id='754ee124…'`. Record whether it is NULL (Art. 17 erasure → abort restore) and whether it equals the operator.
   - `workspace_members`: ALL rows for `754ee124` — classify the operator's row topology: **(a) zero rows → H1**; **(b) a non-owner row, owner row absent → H2-eligible**; **(c) owner row present → contradicts the confirmed owner-less state, re-investigate**.
   - `user_session_state.current_workspace_id` for the operator — **if `!= 754ee124` → H3** (decisive; the closest proxy for which dir the agent reads).
0.2 **Confirm the self-stop driver.** Determine whether the failing dispatch is general `/soleur:go` Step 0.0 vs `routineAuthoring=true` (`cc-dispatcher.ts:2085`) so the observability mirror instruments the real precondition path.
0.3 **Sentry (read, EU host).** Use `scripts/sentry-issue.sh` (host `jikigai-eu.sentry.io`, `SENTRY_ISSUE_RO_TOKEN`): search the operator/`754ee124` for `non-member-claim-reset`, `ownerless-reconcile` (expect ≥1 given the 28× claim — its absence impeaches reconcile observability too), `corrupt-worktree-reclone`, `repo-readiness-gate`. Sentry is **corroboration**; the Supabase predicate + `current_workspace_id` are the **decisive** discriminators.
0.4 **Decision table → branch.** Record evidence in the spec. Rank by 0.1(d)/(c)/(b)/(a) + `current_workspace_id`, with Sentry corroboration. If evidence is ambiguous, ship ONLY Phase 1a (canary restore — resolves the operator iff truth is H1) + Phase 1b observability, then **re-enter Phase 0.4 when the new `agent-readiness-self-stop` event lands** (named re-entry: a tracking issue + the specific Sentry query that reopens branch selection).

### Phase 1a — De-anomalize owner-less `754ee124` (data remediation; #5591)
- Resolve the owner principal via the **org join** (`organizations.owner_user_id`), gate on `IS NOT NULL` (abort on Art. 17 erasure — never fabricate an owner). Operator ack (`hr-menu-option-ack-not-prod-write-auth`) MUST surface the resolved `user_id` + that user's **email** + the org lineage (this is a GitHub-token-bearing grant).
- **Check-then-write** (Supabase MCP): assert zero pre-existing `role='owner'` rows for `754ee124` (protect the reconcile `.maybeSingle()` at `:255-260`); then `SELECT role FROM workspace_members WHERE workspace_id=754ee124 AND user_id=<owner>` → absent ⇒ INSERT `role='owner', attestation_id=NULL`; present non-owner ⇒ `UPDATE … SET role='owner'` (NOT `ignoreDuplicates`, which would no-op a `member` row).
- Re-verify: `ownerless-reconcile` stops firing; a subsequent reconcile writes a `kb_sync_history recovered=true` row **on the owner's user row** (mechanism: with `ownerId` resolved, `writeAuditRow` switches to `appendKbSyncRow(ownerId)` → mints an owner JWT (`tenant.ts:255-262`) → `append_kb_sync_row` keyed on `auth.uid()=ownerId`; NOT `append_kb_sync_row_for_user`).

### Phase 1b — Agent-surface strand observability (committed; all branches)
- Add a server-side Sentry mirror for the readiness self-stop carrying
  `activeWorkspaceId`, resolved `workspacePath`, `gitValid` — **no
  `installationId`/`repo_url`** (credential-grant identifiers), `userId`
  pseudonymized (mirror the reconcile `breadcrumbUserId` at `:302-304`). Use a
  **distinct `Error` message** so it groups into its own Sentry issue (reuse the
  dedup KEYING of `repo-resolver-divergence.ts:65`, not the shared message).
- **Detection must read the agent's own bwrap context** (same mount/cwd) or reuse
  the dispatch readiness-gate's result — a host-side `git rev-parse` runs outside
  the frozen `denyRead:["/workspaces"]` namespace and can pass on a real strand,
  reproducing the blind spot (Sharp Edges). Drop the unwired "directive marker"
  alternative unless `routine-authoring-directive.ts` is added to Files-to-Edit to
  emit a structured marker.
- Failing test FIRST: a strand → exactly one deduped Sentry event with the
  resolved id + path; the test exercises the bwrap-mount-divergence path, not only
  a synthetic stop.

### Phase 2 — Branch-specific strand fix (chosen at Phase 0)
- **If H2:** gate the dispatch self-heal on `git rev-parse` (the agent's signal),
  not lstat `isValidGitWorkTree` — and **sweep ALL call sites** (cold
  `cc-dispatcher.ts:1791-1793,1839`; warm `cc-reprovision.ts`; reconcile
  `:310/:321`) per `hr-write-boundary-sentinel-sweep`. For the gitdir-pointer /
  `denyRead` realization (no server heal can repair via a pointer), clone a
  **self-contained** `.git` directory into `workspacePath` (not a pointer to a
  `/workspaces`-parent gitdir) before `query()` constructs.
- **If H3:** ensure/repair `user_session_state.current_workspace_id → 754ee124`
  (workspace-activation), with the observability signal making future drift
  visible. (New surface — not in the H2/H1 file set.)
- **If H1 (tail):** Phase 1a canary restore is the operative fix iff the 0.1
  conjunction holds; additionally scope the `cc-dispatcher.ts:1644` hardening to
  the narrow `resetFromClaim && repoUrl-present && git-invalid` case (`:1644`
  already handles `!repoUrl`).
- **Owner-canary systemic guard (NOT in reconcile).** Do NOT add an unattended
  per-push owner insert. Place the systemic guard at the provisioning/creation
  write-site (invariant-at-write) OR a dedicated **ack-gated repair routine**
  carrying the same principal-display + audit-actor discipline as Phase 1a, routed
  through an owner-mutation path that preserves single-owner enforcement +
  attestation. Reconcile keeps the `ownerless-reconcile` warn and defers.

### Phase 3 — Verify on the operator surface + origin (#5591)
- Reproduce `/soleur:go` post-fix on `754ee124`. **Failure branch:** if it still
  strands, the new `agent-readiness-self-stop` event now carries `gitValid` +
  resolved id → return to Phase 0.4. Assert the H2 fix's ordering guarantee
  **structurally** (await before `query()`), not by N=1 reproduction.
- Confirm the observability mirror covers dispatch surfaces beyond the
  routine-authoring path (general `/soleur:go`, cron routines).
- Origin: determine which flow created the owner-less/non-solo `754ee124`
  (duplicate-workspace creation, #5591/#5673). If covered by #5673, add a re-eval
  note + `Ref` it; else file a guard-the-creation-path follow-up. Do NOT silently
  leave it.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Ship a 4th server-side heal fix from code-reading | The exact failure of the prior three (learning mandates live exec-path evidence first). |
| Provision/entrypoint fix in a separate agent container | No separate container exists. |
| De-duplicate `52af49c2`/`754ee124` | Different repos; #5591's "same-repo" premise is stale. |
| Reconcile auto-self-heals the owner canary per push | DROPPED — bypasses `transfer_workspace_ownership` guards (single-owner, attestation, audit actor), unattended privilege grant, self-perpetuates a wrong-principal grant, masks the creation-path bug, contradicts the Phase 1a ack gate. Systemic guard moves to provisioning / ack-gated repair. |
| Migration backfilling the canary for ALL owner-less workspaces | Over-broad; the single confirmed row is an operator-acked targeted remediation. |
| Make `append_kb_sync_row_for_user` workspace-keyed | Larger contract change; deferred — canary restore unblocks the audit via the owner path. File a follow-up if non-solo audit gaps recur. |

## User-Brand Impact

- **If this lands broken, the user experiences:** the operator's flagship
  `/soleur:go` Concierge continues to strand on `not a git repository` with the
  misleading "Settings → Repository" honest-stop — the product's core surface is
  non-functional, with no observable signal that anything fired.
- **UPDATED at implementation (multi-owner-by-design; Phase 1a DROPPED).** The
  owner-canary restore in the original plan was REMOVED — multi-owner is by
  design, so there is **no data write** and no owner-canary access-control change.
  The shipped change is server-side TypeScript only. The two residual user-facing
  vectors are:
  - **Destructive re-clone discards user work.** The gitdir-pointer heal
    (`ensure-workspace-repo.ts`) unlinks a stale `.git` FILE and re-clones from
    origin HEAD. Artifact: uncommitted/un-pushed work at `/workspaces/<id>`.
    Mitigations: (a) it fires ONLY on a STRANDING (escaping/unclassifiable)
    pointer — a functional non-escaping in-workspace pointer is left untouched
    (`isStrandingFilePointer`); (b) a `.git` FILE pointer holds NO objects (they
    live at the gitdir target, which an escaping pointer abandons because the
    sandbox can't read it anyway — there is no in-workspace work to lose); (c) a
    personal workspace root is never a legitimate linked worktree (invariant); (d)
    single-file `force` unlink, NOT a recursive `.git`-dir rm; lock-guarded with an
    under-lock re-check.
  - **Observability PII leak.** The new `agent-readiness-self-stop` Sentry event.
    Artifact: for a SOLO workspace `workspace_id == user_id`, so the active id IS
    the raw userId. Mitigation: the id is pre-hashed to `activeWorkspaceIdHash`,
    the raw `workspacePath` is NOT emitted, `userId` → `userIdHash` at the
    boundary, and NO `installationId`/`repoUrl`/`gitdirTarget` ride along.
- **If this lands broken (residual):** the operator stays stranded — but the new
  `agent-readiness-self-stop` event now fires with the `.git` shape, so a residual
  strand is observable (no longer silent), and Phase 0.4 re-entry is data-driven.
- **Brand-survival threshold:** `single-user incident`

CPO sign-off required at plan time before `/work` begins (`requires_cpo_signoff:
true`). `user-impact-reviewer` runs at review time.

## Observability

```yaml
liveness_signal:
  what: "Server-side Sentry mirror for the agent readiness self-stop (new distinct op:agent-readiness-self-stop, own issue group) + existing ownerless-reconcile warn + reportRepoResolverDivergence(non-member-claim-reset)"
  cadence: "per agent dispatch (strand) / per push (reconcile)"
  alert_target: "Sentry web-platform issue (operator triage)"
  configured_in: "apps/web-platform/server/cc-dispatcher.ts (dispatch mirror), apps/web-platform/server/repo-resolver-divergence.ts (dedup keying; distinct Error message), apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts:279-299"
error_reporting:
  destination: "Sentry web-platform via SENTRY_DSN (reportSilentFallback / reportRepoResolverDivergence); op emitted as a searchable tag (observability.ts:189)"
  fail_loud: "Sentry event with activeWorkspaceId + resolved workspacePath + gitValid on every strand (today: silent). No installationId/repo_url; userId pseudonymized."
failure_modes:
  - mode: "Agent dispatched but readiness probe self-stops (workspacePath has no git-rev-parse-valid worktree, incl. gitdir-pointer under denyRead)"
    detection: "new deduped Sentry op:agent-readiness-self-stop read in the agent's own bwrap context (Phase 1b) — NOT a host-side git rev-parse, NOT operator-eyeball"
    alert_route: "operator via Sentry issue"
  - mode: "Owner-less workspace (missing role='owner' canary) — invariant drift"
    detection: "ownerless-reconcile Sentry warn per push (existing, debounced)"
    alert_route: "operator via Sentry issue"
  - mode: "Recovery audit row silently dropped (non-solo owner-less → append_kb_sync_row_for_user UPDATE 0 rows)"
    detection: "emit a positive info/warn Sentry event when the audit RPC reports 0 rows updated (added) — not inferred from a missing kb_sync_history row"
    alert_route: "operator via Sentry issue"
logs:
  where: "Sentry issues API (EU org jikigai-eu.sentry.io); host/container logs via Better Stack (no-SSH per runbook sentry-issue-read.md)"
  retention: "Sentry project retention (90d); Better Stack per plan"
discoverability_test:
  command: "SENTRY_QUERY='op:agent-readiness-self-stop statsPeriod:24h' bash scripts/sentry-issue.sh search"
  expected_output: "0 issues when no strand in the last 24h; >=1 issue (latest event carries activeWorkspaceId + workspacePath) when a strand occurred. Uses jikigai-eu.sentry.io + SENTRY_ISSUE_RO_TOKEN; reads the events/latest-event endpoint to surface extra, not just issue count."
```

## Architecture Decision (ADR/C4)

This plan clarifies a **trust/dispatch boundary** (the two writers/readers of the
`/workspaces` volume key it by DIFFERENT identifiers — agent via
session-claim/membership resolution, reconcile via `installation_id+repo_url`) and
records an **invariant** (owner canary required; agent strand must be observable),
so an ADR amendment is an in-scope deliverable (`wg-architecture-decision-is-a-plan-deliverable`).

### ADR
- **Amend ADR-044** (workspace repo ownership; it amends ADR-038) — single owner,
  not "and/or." Record: (a) the owner-canary-loss failure mode (owner-less +
  non-solo → resolution diverges from the reconcile heal target → strand); (b) the
  **keying-divergence trust boundary** as the root cause; (c) canary-repair
  responsibility lives at provisioning / an ack-gated repair path, **NOT** in
  reconcile; (d) the agent strand MUST emit a server-side observability signal.
  Scope the ADR to the **invariant**; mark the strand mechanism "under
  investigation" until Phase 0 resolves (do NOT assert an `accepted` self-heal
  mechanism the evidence may discard). Author via `/soleur:architecture`.

### C4 views
Reviewed all three `.c4` files. The `/mnt/data/workspaces` **persistent volume**
is not modeled, and neither the `engine.claude -> workspaces` (active-workspace
resolution) nor `inngest -> workspaces` (reconcile heal) edge exists — both
gaps. **Split this to a standalone docs PR** (the modeling-gap fill is genuine but
NOT load-bearing for the incident fix and should not gate it). When done, add the
`workspaces` data store + the two edges **labeled with their resolution key**
(claim/membership vs installation+repo — the divergence axis is the architectural
point), plus the `view containers` include lines; run
`c4-code-syntax.test.ts` + `c4-render.test.ts`.

## Infrastructure (IaC)

Skip — no new infrastructure. One container/volume already provisioned; changes
are server-side TypeScript + a single operator-acked Supabase data remediation.

## Domain Review

**Domains relevant:** engineering (CTO) — infrastructure/runtime bug fix.

No legal / finance / marketing / sales / ops / support business-domain
implications. **Product/UX: NONE** — no UI-surface file in Files-to-Edit (the
honest-stop copy is server strings already shipped; no `components/**`,
`app/**/page.tsx`, `app/**/layout.tsx` created/edited). CTO/architecture depth
provided by the deepen-plan panel (architecture-strategist + data-integrity-guardian
+ security-sentinel + spec-flow-analyzer + observability-coverage-reviewer) and
the review-time `user-impact-reviewer` (single-user-incident threshold). **GDPR
gate (Phase 2.7) advisory:** the owner-canary restore is an access-control grant
on regulated membership data — invoke `/soleur:gdpr-gate` at /work against the
Phase 1a remediation + the Art. 17 `owner_user_id IS NULL` abort gate (migration
065 `ON DELETE SET NULL`). The restore grants the *legitimate* owner access,
fail-closed otherwise — no cross-tenant grant.

## Open Code-Review Overlap

`None` for the core fix files (`workspace-resolver.ts`, `workspace-reconcile-on-push.ts`,
`cc-reprovision.ts`). `cc-dispatcher.ts` overlaps **#3243** (decompose
cc-dispatcher) and **#3242** (tool_use WS raw name) — both unrelated.
**Disposition: Acknowledge** — this PR makes a surgical add at the dispatch
boundary, not a decomposition; the scope-outs remain open. (Keeping canary-repair
OUT of reconcile aligns with #3243's reduce-responsibilities direction.)

## Acceptance Criteria

### Pre-merge (PR)
- [ ] Phase 0 evidence recorded in the spec: resolver predicate (0.0); `754ee124`
      org-derived `owner_user_id` (incl. NULL / `==operator` check); operator row
      topology (a/b/c); `current_workspace_id`; self-stop driver; Sentry verdict;
      branch decision (H2/H3/H1) justified.
- [ ] Failing test first, then green: an agent readiness self-stop produces
      exactly one deduped server-side Sentry event (own issue group) carrying
      `activeWorkspaceId` + resolved `workspacePath` + `gitValid`, read in the
      agent's bwrap context; no `installationId`/`repo_url`; `userId` pseudonymized.
- [ ] Branch fix per Phase 0: H2 → self-heal gates on `git rev-parse` across all
      dispatch/reconcile call sites + handles the gitdir-pointer case (test);
      H3 → `current_workspace_id` activation repair (test); H1 → `:1644` hardening
      scoped to `repoUrl-present/git-invalid` (test).
- [ ] No unattended owner-canary write added to reconcile; any systemic guard in
      this PR is provisioning-side or an ack-gated repair routine with
      principal-display + audit-actor + single-owner enforcement.
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean; the
      package's actual test runner green (read `package.json` scripts +
      `vitest.config.ts` include globs for any new test path).
- [ ] ADR-044 amended (invariant + keying-divergence boundary; mechanism under
      investigation). C4 data-store edit is a SEPARATE docs PR (not gating).
- [ ] PR body uses `Ref #5733` and `Ref #5591` (ops-remediation: the data fix +
      operator-surface verification are post-merge — do NOT `Closes`).

### Post-merge (operator-acked)
- [ ] Phase 1a: restore the `754ee124` owner canary via Supabase MCP
      (`mcp__plugin_supabase_supabase__*`) — operator-acked with principal display;
      org-join derivation; `NOT NULL` gate; check-then-INSERT-or-UPDATE; assert
      zero pre-existing `role='owner'` rows first. Automation: feasible (Supabase
      MCP), baked into /work with the ack gate.
- [ ] Phase 3: reproduce `/soleur:go` on `754ee124` — no strand, agent reads the
      soleur repo; `gh issue close #5733` after verification (failure branch →
      Phase 0.4).
- [ ] `ownerless-reconcile` no longer fires for `754ee124`; a reconcile recovery
      writes `kb_sync_history recovered=true` on the owner's user row.
- [ ] #5591 origin: re-eval note on #5673 (or a new guard-the-creation-path issue)
      with milestone from `knowledge-base/product/roadmap.md`.

## Test Scenarios

- Given an owner-less + non-solo workspace, when the agent dispatches and the
  readiness probe finds no `git rev-parse`-valid worktree, then exactly one
  deduped Sentry `op:agent-readiness-self-stop` event (own issue) fires with the
  resolved `workspacePath`, read in the agent's bwrap context.
- Given `current_workspace_id != 754ee124` (H3), when the agent dispatches, then
  resolution returns the solo id (no probe, no reset) and the strand is now
  observable; the activation repair re-points the claim.
- Given (H2) a member whose active `/workspaces/<id>` has a gitdir-pointer under
  `/workspaces` (denyRead), when dispatch runs, then the self-heal clones a
  self-contained `.git` keyed on the resolved active id before `query()`.
- Given (H1) a non-member reset onto a `.git`-invalid solo dir with `repoUrl`
  present, when the agent dispatches, then the switcher/honest copy is surfaced.
- Given the canary restore, when reconcile next runs, then `appendKbSyncRow(ownerId)`
  writes `recovered=true` on the owner's user row (not via append_kb_sync_row_for_user).
- Regression: a genuine solo OWNER with no repo (no `resetFromClaim`) flows
  through the existing repo-less path unchanged.
- Data-safety: a restore against an org whose `owner_user_id IS NULL` aborts (no
  fabricated owner); a pre-existing `role='owner'` row blocks a second insert.

## Files to Edit (candidate — final set fixed by Phase 0 branch)
- `apps/web-platform/server/cc-dispatcher.ts` — agent-surface strand Sentry mirror (Phase 1b, distinct Error, bwrap-context read); H1 switcher hardening (`:1644`, narrow case); H2 `git rev-parse` gate at cold dispatch (`:1791-1793,1839`).
- `apps/web-platform/server/repo-resolver-divergence.ts` — dedup keying for the new distinct-message op.
- `apps/web-platform/server/cc-reprovision.ts` — (H2) `git rev-parse` validity gate keyed on the resolved active id before `query()`.
- `apps/web-platform/server/git-worktree-validity.ts` — (H2) add a `git rev-parse`-equivalent check (or sibling) since lstat alone is insufficient.
- `apps/web-platform/server/inngest/functions/workspace-reconcile-on-push.ts` — (H2) align the reconcile validity gate (`:310/:321`); **no** owner-canary write.
- `apps/web-platform/server/workspace-resolver.ts` — only if Phase 0 shows the predicate must change; otherwise untouched.
- (H3) workspace-activation surface for `current_workspace_id` — TBD by Phase 0 (new surface).
- `knowledge-base/engineering/architecture/decisions/ADR-044-workspace-repo-ownership.md` — amendment.

## Files to Create
- `apps/web-platform/test/<agent-readiness-self-stop>.test.ts` — Phase 1b observability test (bwrap-divergence path; path per `vitest.config.ts` globs).
- branch-specific test(s) per Phase 0 (H2 git-rev-parse-gate / H3 activation / H1 switcher).

## Sharp Edges
- `## User-Brand Impact` is filled; threshold = `single-user incident` (passes deepen-plan Phase 4.6).
- **Do NOT ship a 4th fix on code-reading alone.** Phase 0 live evidence selects H2/H3/H1; a green check on the wrong branch is worse than red (#5716/#5584 trap).
- **`workspaces` has NO `owner_user_id` column** — derive the owner via `organizations.owner_user_id` through `workspaces.organization_id`; gate `IS NOT NULL`; never fabricate an owner; surface the principal for ack.
- **The owner-canary restore is a GitHub-token-bearing access-control grant.** Single-row, operator-acked with user_id + email + org lineage; treat the org-derived owner as a hypothesis given the duplicate-creation lineage.
- **A server-side `git rev-parse` runs OUTSIDE the agent's frozen bwrap mount** (`denyRead:["/workspaces"]`) — it can pass on a real strand. The observability mirror AND the H2 heal must read the signal the agent uses, or they are proxies.
- `isValidGitWorkTree` is lstat-only and returns `true` for a `.git` **file** pointer (`git-worktree-validity.ts:60`); the agent gates on `git rev-parse`. The H2 fix must sweep ALL dispatch/reconcile call sites, not just `cc-reprovision.ts`.
- The most likely H2 realization (gitdir-pointer to a `/workspaces`-parent gitdir, unreadable in the sandbox) is a mount-visibility strand **no server heal repairs via a pointer** — clone a self-contained `.git`, don't repoint.
- The audit-unblock works via the **owner path** (`appendKbSyncRow(ownerId)` + minted JWT), not `append_kb_sync_row_for_user`; the recovered row lands on the owner's user row.
- Test runner/typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` and the package's real runner (NOT `npm run -w`, NOT assumed `bun test`).

## Verification Plan (active — supersedes the pre-merge Implementation Phases above)

Since #5734 already merged the code, the only remaining work is **investigate-first
verification on the agent surface**. No code ships from this branch unless V3
re-opens a fix branch with NEW live evidence.

### V0 — Confirm the merged fix is deployed (read-only)
- Confirm `190ab58a5` is in the live web-platform image: query the deploy webhook
  `deploy.soleur.ai/hooks/deploy-status` (HMAC + CF Access via Doppler
  `prd_terraform`) for the running SHA/version, OR confirm the post-merge release
  workflow for #5734 completed. Record the deployed version.

### V1 — Exec-path confirmation via Sentry (the load-bearing learning)
- Using `scripts/sentry-issue.sh` (host `jikigai-eu.sentry.io`,
  `SENTRY_ISSUE_RO_TOKEN`), search the EU org for the NEW
  `agent_readiness_self_stop` op scoped to `754ee124`'s `activeWorkspaceIdHash`
  and recent window. Its presence proves the dispatch readiness gate (the merged
  observability) **executes on the strand surface**; its absence on a fresh strand
  means the strand is no longer reached (healed) OR the op never fires there →
  re-trace.
- Cross-check `ownerless-reconcile` STOPPED firing for `754ee124` after the merge
  (the N-co-owner fix). The pre-fix data showed it firing 28×; post-fix expect 0.

### V2 — Live Supabase de-anomalization data check (read-only, Supabase MCP)
- `workspace_members` for `754ee124`: confirm **≥2 `role='owner'` rows** (the
  co-owner topology that triggered the `.maybeSingle()` false positive). This
  **refutes** the "missing canary" premise and **confirms** #5591's reframing.
- `user_session_state.current_workspace_id` for the operator: record whether it is
  `754ee124` (rules H3 in/out for any residual strand).
- `organizations.owner_user_id` via the `workspaces.organization_id` join: record
  the org-owner lineage (no write — multi-owner is by design, nothing to restore).

### V3 — Reproduce on the operator surface + close-out
- Reproduce `/soleur:go` on `754ee124`. **PASS:** agent reads `jikig-ai/soleur`, no
  `not a git repository` strand → `gh issue close #5733` with a comment citing
  #5734 + the V1/V2 evidence.
- **FAIL (residual strand):** the merged `agent_readiness_self_stop` event now
  carries `gitValid` + `gitKind` + the hash — capture it, and ONLY THEN open a new
  fix branch with that NEW live evidence (the next layer is now data-driven, not
  code-read). Do NOT pre-author a fix here.
- #5591: it has its own open PR **#5783** — add a `Ref #5733` cross-link note;
  do NOT duplicate its scope on this branch.

### V-Disposition — the WIP PR #5788 on this branch
This branch (`feat-one-shot-5733-...`) currently has WIP PR **#5788** over a tree
identical to main (0 commits ahead). Because the fix is already merged, the
correct disposition is one of: **(a)** convert #5788 to a verification-evidence PR
(this reconciled plan + tasks + the V0–V3 findings recorded in the spec, no code),
or **(b)** close #5788 and record the verification directly on #5733. Decide at
/work time based on whether V3 surfaces residual work. Do NOT push a
re-implementation.

## References
- Issue: #5733 (this), #5591 (owner-less root → its own PR #5783). Implemented by: **#5734 (commit `190ab58a5`)**. Prior: #5716, #5584, #5730. Related: #5673 (repo-connect-block-duplicate), #5394/ADR-044 PR-1 (reset-to-solo instrumentation), #4520 (single-owner enforcement, SUPERSEDED by N-co-owner #5733/#5734).
- Learnings: `2026-06-30-verify-the-fixed-code-path-actually-executes-on-the-affected-surface.md`, `2026-06-15-bash-bwrap-sandbox-mount-visibility-vs-cwd-persistence.md`, `2026-06-12-resumability-claim-must-verify-workspace-lifecycle.md`, `2026-06-18-multi-workspace-per-installation-breaks-founder-resolve-and-ready-clone.md`, `2026-06-29-recurring-failure-root-cause-is-residual-bad-data-not-patched-code.md`.
- ADRs: ADR-038 (workspace_members canary, N2), ADR-044 (workspace repo ownership), ADR-033 I7 (bwrap sandbox / spawn), ADR-030 (Inngest).
- Code: `workspace-resolver.ts:365-450`, `cc-dispatcher.ts:1540-1653,1791-1793,2085`, `cc-reprovision.ts:54-138`, `workspace-reconcile-on-push.ts:251-369`, `git-worktree-validity.ts:49-67`, `agent-runner-query-options.ts:149`, `agent-runner-sandbox-config.ts:70-94`, `session-sync.ts:686-767`, `lib/supabase/tenant.ts:255-262`, migrations `053`, `075`, `079`, `100`, `109`.
