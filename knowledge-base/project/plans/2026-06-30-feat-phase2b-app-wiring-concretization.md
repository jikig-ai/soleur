---
title: "PR B app-wiring concretization — lease/fence write-path integration (OQ2/OQ3 resolved)"
date: 2026-06-30
type: concretization
parent_plan: knowledge-base/project/plans/2026-06-30-feat-phase2-git-data-lease-fencing-plan.md
issue: 5274
phase: 2
status: concretized
---

# PR B app-wiring concretization

Resolves the parent plan's **OQ2 (fence storage/delivery)** and **OQ3 (exact
app-refactor depth + lease-acquire call sites)**, which were explicitly deferred
to a deepen-plan step. Produced from a deep code-trace (2026-06-30). The fence
(task 2.3), infra (2.4 IaC), worktree/bare path-split + read flag (2.4), test
registration, and docs are ALREADY committed on `feat-5274-phase2b-git-data-split`
(commits 748d96638 → 460165145). This doc pins the REMAINING app-wiring.

## Design-shaping discoveries (the reason concretization was load-bearing)

1. **Two git-write layers — both must be fenced.**
   - **App-server `syncPush`** (`server/session-sync.ts:937`) pushes ONLY
     `knowledge-base/` auto-commits (path-scoped). Interceptable at the TS call
     site → add `--push-option=lease-gen=<N> --push-option=worktree-id=primary`
     to the `["push", …]` argv. Same at the protected-branch fallback push
     (`session-sync.ts:306`).
   - **In-sandbox agent `git push`** (the user's Claude Code running in bwrap,
     `cwd: workspacePath`) pushes the user's actual CODE — the dominant write.
     NOT interceptable at any TS call site. Push-options must be delivered via
     `GIT_PUSH_OPTION_COUNT` / `GIT_PUSH_OPTION_0=lease-gen=<N>` /
     `GIT_PUSH_OPTION_1=worktree-id=primary` env vars injected into the sandbox
     env at cold-Query construction (`cc-dispatcher.ts:1493`,
     `buildAgentQueryOptions`). REQUIRES `git config --system
     receive.advertisePushOptions true` on the git-data host (add to
     `git-data-bootstrap.sh`) — without it the hook never sees the options and
     the fence is fail-closed-rejects every in-sandbox push.

2. **The dual-push-site CAS is already correct.** Both push sites present the
   SAME lease generation (one lease per (workspace, "primary")). The shipped
   fence (`git-data-pre-receive.sh`) ACCEPTS equal gen (idempotent retry) and
   advances `max = max(stored_max, N)`, so two pushes at gen N both pass. Do NOT
   change the fence to "update-once-per-gen" — that would false-reject the second
   layer's push.

3. **cc-soleur-go holds ONE Query across many user turns.** The lease must be
   held for the Query lifetime, not one turn: acquire at cold-Query construction,
   release at `handleCcCloseQuery` (`cc-dispatcher.ts:1442`, fires from every
   close path). Heartbeat (≤25s) must run for the whole conversation; a long
   conversation that outlives a missed heartbeat would be fenced out.

## Integration table (file:line → approach)

| Concern | File:line | Approach |
|---|---|---|
| `host_id` source + injection | `infra/ci-deploy.sh` (resolve before the `case` block; inject in BOTH canary block ~640 AND prod block ~865) | `SOLEUR_HOST_ID=$(curl -sf --max-time 5 http://169.254.169.254/hetzner/v1/metadata/instance-id || cat /etc/machine-id \| head -c 32 \|\| echo "")`; pass `-e SOLEUR_HOST_ID="$SOLEUR_HOST_ID"` to both `docker run`. **ci-deploy.sh is a `deploy_pipeline_fix` trigger file → ship Phase 5.5 Deploy-Pipeline-Fix Drift Gate fires (auto-applies on merge); expected.** |
| host_id resolver (app) | NEW `server/host-identity.ts` | `resolveHostId()` reads `process.env.SOLEUR_HOST_ID`; throw/fail-loud if unset in prod (NEVER os.hostname()/per-container, NEVER auth.uid()). Guard `assertHostIdNotUserId(hostId, userId)` throws on equality (DSAR exclusion is load-bearing — handoff note 1/4). |
| Held-lease registry | NEW in `server/worktree-write-lease.ts` | module-level `heldLeases: Map<string, {workspaceId, worktreeId, hostId, leaseGeneration}>`; export `registerHeldLease`, `unregisterHeldLease`, `releaseAllHeldLeases(): Promise<void>` (mirrors the `userWorkspaces` Map pattern, but collocated with the lease concern). |
| Lease acquire — legacy | `agent-runner.ts:955` (just before `registerSession`) | `acquireWorktreeLease(workspaceId, "primary", hostId)`; on `null` → fail-closed (abort the write, `worktree_lease` Sentry slug). Gate the whole thing on `isGitDataStoreEnabled()` OR keep live-but-non-rejecting at replicas=1 per handoff note 3 (monitored fail-closed mode) — **operator/CTO call at implementation: live vs flag-gated.** |
| Lease acquire — cc path | `cc-dispatcher.ts:1493` (`realSdkQueryFactory` cold-Query) | acquire at cold-start; capture gen in the closure for both the push-option env injection AND the heartbeat. |
| Heartbeat | NEW (no per-turn interval exists; mirror `ws-handler.ts:2946` `touchSlot` 30s pattern) | `setInterval(() => touchWorktreeLease(workspaceId,"primary",hostId,gen), 25_000)`; on `false` → cancel + abort in-flight write + fail-loud. |
| Lease release — legacy | `agent-runner.ts:2633` (`unregisterSession` finally) | `releaseWorktreeLease(...)` after `syncPush` (2295), in the same finally. |
| Lease release — cc path | `cc-dispatcher.ts:1442` (`handleCcCloseQuery` start) | `releaseWorktreeLease(...)` before `cleanupCcBashGatesForConversation`. |
| SIGTERM release | `server/index.ts:267-268` (after `drainCcQueriesForShutdown`, before `server.close()`) | `await releaseAllHeldLeases()`. |
| Push-with-gen (app-server) | `session-sync.ts:937` + `:306` | add the two `--push-option=…` args to the push argv. |
| Push-with-gen (in-sandbox) | `cc-dispatcher.ts:1493` / `buildAgentQueryOptions` env | inject `GIT_PUSH_OPTION_COUNT=2` + the two options. |
| `receive.advertisePushOptions` | `infra/git-data-bootstrap.sh` | `git config --system receive.advertisePushOptions true` (REQUIRED for in-sandbox push-options to reach the hook). |
| SSH auth variant | `server/git-auth.ts:314` (after `gitWithInstallationAuth`) | `gitWithPrivateKeyAuth(args, privateKeyMaterial, opts)` using `GIT_SSH_COMMAND="ssh -i <key> -o StrictHostKeyChecking=accept-new -o IdentitiesOnly=yes"`; key written 0600 to a temp file (mirror `writeAskpassScriptTo`); keep `GIT_CONFIG_NOSYSTEM=1`/`GIT_CONFIG_GLOBAL=/dev/null`. Consumes Doppler `GIT_TRANSPORT_SSH_PRIVATE_KEY` (now in `prd`). |
| Clone wiring | `server/ensure-workspace-repo.ts:327` (`realGraftRepoClone`) | gate on `isGitDataStoreEnabled()`: swap `repoUrl` → bare-store SSH URL (`git+ssh://git@10.0.1.20/<workspace_id>.git`), swap `gitWithInstallationAuth` → `gitWithPrivateKeyAuth`; the `GITHUB_HTTPS_REPO_RE` guard (`:252`) must be branched for the internal SSH URL. |
| worktree_id | n/a | one tree per workspace today (`inflight-checkpoint.ts:14`, `ensure-workspace-repo.ts:75`) → stable opaque constant `"primary"`. Multi-worktree is Phase 3 (additive, non-breaking). |

## Implementation order (RED→GREEN where testable)

Low-ambiguity, self-contained units first (each its own commit + test):
1. `git config --system receive.advertisePushOptions true` in `git-data-bootstrap.sh` (+ a bootstrap assert).
2. `server/host-identity.ts` + guard test (host_id != auth.uid(); unset-in-prod fail-loud).
3. Held-lease registry (`registerHeldLease`/`unregisterHeldLease`/`releaseAllHeldLeases`) in `worktree-write-lease.ts` + test.
4. `gitWithPrivateKeyAuth` in `git-auth.ts` + test (GIT_SSH_COMMAND shape, no token leak).
5. push-with-gen on the app-server `syncPush` + fallback push (`session-sync.ts`) + test (argv carries both options).

Higher-ambiguity multi-path turn-boundary surgery (needs care + full-suite sweep of the cc + legacy test mocks — the WS-lifecycle-hook-covers-both-lineages learning):
6. host_id injection in `ci-deploy.sh` (canary + prod) — triggers the Deploy-Pipeline-Fix Drift Gate.
7. Lease acquire/heartbeat/release on the legacy path (`agent-runner.ts`) + tests.
8. Lease acquire/heartbeat/release + push-option env injection on the cc path (`cc-dispatcher.ts`/`ws-handler.ts`) + tests.
9. SIGTERM release in `index.ts` + test.
10. Clone wiring in `ensure-workspace-repo.ts` (gated, inert at flag-off) + test.

## Implementation status (2026-07-01 — PR B part 1)

The architecture fork below was **resolved by the CTO** and recorded as the
ADR-068 amendment (`…lease-coordinator.md`, commit `e20a8ef79`): dedicated-remote
replication-push, additive clone, **lease GATED behind `isGitDataStoreEnabled()`**
(not live at replicas=1), in-sandbox `GIT_PUSH_OPTION_*` injection deferred to
Phase 3. The remaining work was re-derived against that ruling, NOT the original
integration-table push rows.

Done (this branch — the complete lease-COORDINATION layer, gated + inert at
flag-off, full-suite green):

- [x] Step 1 — `receive.advertisePushOptions true` in `git-data-bootstrap.sh` (forward-compat).
- [x] Step 2 — `host-identity.ts` resolver + DSAR boundary guard.
- [x] Step 3 — held-lease registry (SIGTERM drain) + tests.
- [x] Core — `acquireAndHoldWorktreeLease` session-lifetime handle (acquire + 25s heartbeat + idempotent release) + tests.
- [x] Step 4 — `gitWithPrivateKeyAuth` private-net SSH transport + tests.
- [x] Steps 7-9 — lease lifecycle wired into BOTH lineages (legacy `agent-runner`, cc `cc-dispatcher`) + SIGTERM drain in `index.ts`, all gated.

Split to PR B part 2 (the git-data replication TRANSPORT — NOT a call-site edit):

- [ ] Step 10 — dedicated-remote replication push (session-end `git push git-data
      --push-option=lease-gen=<N>` via `gitWithPrivateKeyAuth`) + additive clone
      remote. **BLOCKER (architecture, route to CTO):** the bare target repo must
      exist on the git-data host before the first push, but the transport user is
      `git-shell`-restricted (forced-command authorized_keys permits only
      `git-receive-pack`/`upload-pack`, never `git init --bare`). HOW the per-
      workspace bare repo is provisioned (server-side hook on first connect, a
      provisioning RPC, or relaxing the forced command) is an unresolved
      engineering decision the ADR did not settle. The ADR also defers live
      git-data exercise to Phase 3. Tracked as a follow-up; needs a CTO ruling on
      provisioning before implementation.

## ARCHITECTURE FORK — route to CTO BEFORE implementing the push path

The deep trace surfaced a structural gap the parent plan did not resolve, and it
changes which push the fence guards. **This is an engineering/architecture
decision with material trade-offs → routes to the `cto` agent per the
architectural-fork rule (fires in pipeline mode too), NOT to improvisation.**

**The conflation to correct:** `syncPush` (`session-sync.ts:937`) pushes
`knowledge-base/` auto-commits to the user's **GitHub** origin via the GitHub-App
installation token. That is NOT a push to the git-data bare store and the
git-data fence hook never runs on GitHub. So adding `--push-option=lease-gen` to
`syncPush` is pointless. Likewise the in-sandbox agent's `git push origin` goes
to **GitHub**, not git-data.

**The unresolved question:** ADR-068 §1 says "bare git data (objects/refs) on a
shared git-data host; per-user worktrees on host-local NVMe." Git has no native
"remote git-dir": a worktree's objects must be local. So HOW do a worktree's
local commits reach the git-data bare store, and WHEN does the fence-guarded push
fire? Candidate models (CTO to choose):
  (a) the NVMe worktree is a clone whose dedicated remote IS the git-data bare
      store; a post-commit / session-end internal `git push git-data` (carrying
      the lease-gen push-options, via `gitWithPrivateKeyAuth`) replicates objects
      — the fence guards THIS push;
  (b) the `.git/objects` is an alternates/borrow against a network mount of the
      git-data volume (changes the fence substrate entirely);
  (c) bare store is authoritative; the NVMe worktree checks out from it and
      pushes back on each turn boundary.
Each has different fence-fire points, different failure/rehydration semantics
(#5546 GitHub rehydration still covers GitHub-pushed refs only), and different
cutover (PR C) shapes. The lease lifecycle call sites in the table above are
correct regardless; the PUSH-WITH-GEN sites depend entirely on this ruling.

**Action:** route to `cto` with this doc + ADR-068 §1/§3 + the trade-offs; record
the ruling as an ADR-068 amendment; then implement the push path against it. Do
NOT wire push-with-gen onto `syncPush` (the GitHub push) — that was the trace's
error.

## Open implementation decision (route to CTO at step 7)

**Live-but-non-rejecting vs flag-gated lease in the write path at replicas=1.**
Handoff note 3 wants the replicas=1 fail-closed write-block as a MONITORED mode
(lease in the write path live; acquire→null blocks the write + Sentry). But the
plan also says the app-wiring is "behind the volume-default read flag — inert."
These are in slight tension: a LIVE lease-around-writes at flag-off adds a
Postgres round-trip + a fail-closed dependency to EVERY turn on current prod,
before any git-data host is in use. Resolve at step 7 (route to `cto` agent):
(a) lease live always (handoff note 3, monitored), or (b) lease gated on
`isGitDataStoreEnabled()` (truly inert until cutover, simpler, but defers the
"prove the lease path under load" value to PR C). Record the ruling in an ADR
amendment.
