# Tasks — fix owner-less workspace 754ee124 strand + agent-surface observability (#5733)

lane: cross-domain  (no spec.md present → fail-closed default)
plan: knowledge-base/project/plans/2026-06-30-fix-ownerless-workspace-agent-strand-divergence-plan.md
threshold: single-user incident (requires_cpo_signoff: true)

> Investigation-first. Phase 0 is a BLOCKING gate: no Phase 2 code ships until live
> Supabase + Sentry evidence selects the branch (H2/H3/H1). Phase 1a (data) + Phase 1b
> (observability) are committed regardless of branch. DROP the reconcile auto-self-heal.

## STATUS (2026-06-30, post-implementation) — see `phase-0-evidence.md` for the decision of record
Phase 0 live evidence REFUTED the plan's premise (754 is the operator's SOLO workspace; canary PRESENT, in fact 2 legitimate owners; current_workspace_id correct). H1/H3 refuted; **H2** (gitdir-pointer strand) is the only survivor.
- [x] **Phase 0** — evidence recorded; branch = H2 + reconcile multi-owner code bug.
- [x] **B: reconcile multi-owner attribution** (`.maybeSingle()` → tolerate N owners; warn only on ZERO; info breadcrumb on ≥2). Committed `2a9a09f17`.
- [x] **Phase 1b: agent-readiness-self-stop observability** (`probeGitWorktreeShape` + `reportAgentReadinessSelfStop`, distinct issue group). Committed `bd0e06685`.
- [x] **Phase 2 (H2): gitdir-pointer heal** (file-pointer → unlink + self-contained re-clone; dispatcher + ensure-workspace-repo). Committed `bd0e06685`. (H3/H1 N/A — refuted.)
- [x] **ADR-044 amendment** (rev-parse-equivalent readiness + keying-divergence boundary + multi-owner supersedes #4520 note).
- [x] **Phase 1a (canary restore): DROPPED** — multi-owner is by design (founder-confirmed); the prod data is correct; no write, no operator-ack.
- [ ] Follow-ups (not this PR): dedicated multi-owner ADR + RPC reconcile; #5591/#5673 duplicate-creation origin.
- [ ] Phase 3: reproduce `/soleur:go` post-deploy (the new event now carries the `.git` shape if it still strands).

## Phase 0 — Live exec-path verification (BLOCKING)
- [ ] 0.0 Read `workspace-resolver.ts:365-450`; record the exact membership predicate (role? attestation_id? org_id?).
- [ ] 0.1 Supabase (read): `workspaces` (org_id, repo_url, repo_status, install_id) for 754ee124 + 52af49c2; `organizations.owner_user_id` via the org join (NULL? == operator?); ALL `workspace_members` rows for 754ee124 (classify operator topology a/b/c); `user_session_state.current_workspace_id`.
- [ ] 0.2 Confirm the self-stop driver: general `/soleur:go` Step 0.0 vs `routineAuthoring=true` (`cc-dispatcher.ts:2085`).
- [ ] 0.3 Sentry (EU `jikigai-eu.sentry.io`, `SENTRY_ISSUE_RO_TOKEN`, `scripts/sentry-issue.sh`): non-member-claim-reset, ownerless-reconcile, corrupt-worktree-reclone, repo-readiness-gate. Corroboration only.
- [ ] 0.4 Decision table → branch (H2/H3/H1), recorded in spec with justification. Ambiguous → ship 1a+1b only, define re-entry trigger.

## Phase 1a — De-anomalize owner canary (operator-acked prod data fix; #5591)
- [ ] Resolve owner via org join; gate `owner_user_id IS NOT NULL` (abort on Art.17 erasure).
- [ ] Operator ack surfacing resolved user_id + email + org lineage (token-bearing grant).
- [ ] Assert zero pre-existing `role='owner'` rows for 754ee124 (protect `.maybeSingle()`).
- [ ] Check-then-write: absent → INSERT role='owner', attestation_id=NULL; non-owner row → UPDATE SET role='owner' (NOT ignoreDuplicates).
- [ ] Verify ownerless-reconcile stops; next reconcile writes recovered=true on the owner's user row.

## Phase 1b — Agent-surface strand observability (committed; all branches)
- [ ] Failing test first: strand → exactly one deduped Sentry `op:agent-readiness-self-stop` (own issue, distinct Error message) with activeWorkspaceId + resolved workspacePath + gitValid; read in the agent's bwrap context (NOT host-side git rev-parse); no installationId/repo_url; userId pseudonymized.
- [ ] Implement the mirror in cc-dispatcher.ts + repo-resolver-divergence.ts (dedup keying).
- [ ] Add positive signal: emit when the audit RPC reports UPDATE 0 rows (non-solo owner-less).

## Phase 2 — Branch-specific strand fix (chosen at Phase 0)
- [ ] H2: gate self-heal on `git rev-parse` (not lstat isValidGitWorkTree) across ALL call sites (cc-dispatcher.ts:1791-1793,1839; cc-reprovision.ts; reconcile :310/:321); clone a self-contained `.git` for the gitdir-pointer/denyRead case before query().
- [ ] H3: repair/ensure `user_session_state.current_workspace_id → 754ee124` (workspace-activation surface).
- [ ] H1 (tail): scope cc-dispatcher.ts:1644 hardening to resetFromClaim && repoUrl-present && git-invalid.
- [ ] Owner-canary systemic guard: provisioning-side OR an ack-gated repair routine (single-owner + attestation + audit actor). NO unattended write in reconcile.

## Phase 3 — Verify + origin
- [ ] Reproduce `/soleur:go` on 754ee124 (failure → back to 0.4 via the new event); assert H2 ordering structurally.
- [ ] Confirm observability covers dispatch surfaces beyond routine-authoring.
- [ ] #5591 origin: re-eval note on #5673 (or new guard-the-creation-path issue) with roadmap milestone.

## Cross-cutting / quality gates
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean; package's real test runner green (check package.json + vitest.config.ts globs).
- [ ] ADR-044 amended (invariant + keying-divergence boundary; mechanism under investigation). C4 data-store edit = SEPARATE docs PR.
- [ ] `/soleur:gdpr-gate` at /work against the Phase 1a remediation (access-control on membership data).
- [ ] PR body uses `Ref #5733` + `Ref #5591` (ops-remediation; NOT Closes). CPO sign-off before /work.
