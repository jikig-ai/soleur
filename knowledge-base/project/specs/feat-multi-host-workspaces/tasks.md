---
feature: multi-host-workspaces
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-06-29-feat-multi-host-workspaces-layer-plan.md
issue: 5274
status: epic — each phase is its own PR / /soleur:plan
---

# Tasks: Multi-host `/workspaces` layer (staged Approach A)

> Epic-level breakdown. Each phase below is its own PR and warrants its own
> `/soleur:plan` + spec at execution time. Substrates are deferred to the phase
> that needs them (Redis → Phase 3; Nomad → Phase 4a) per plan-review.

## Phase 0 — Architecture decision (this epic's lifecycle)
- [ ] 0.1 Author ADR-068 via `/soleur:architecture` (`status: adopting`)
- [ ] 0.2 Amend ADR-027 (`## Decision` + `## Alternatives Considered`); reference ADR-059
- [ ] 0.3 Edit `model.c4` (add sessionStore, gitDataStore, scheduler, coordinator + relationships; widen `hetzner` desc) and `views.c4` (`view containers` include lines); run c4-code-syntax + c4-render tests

## Phase 1 — Host-local correctness (NO new infra)
- [ ] 1.1 Add host-local owning-host guard before `runDisconnectGraceAbort` (ws-handler.ts:228-240); race-free on single event loop
- [ ] 1.2 Confirm `userWorkspaces` restart-survival via #5338 rehydrate (registry:288-327); routing truth = Postgres
- [ ] 1.3 Audit legacy abort: confirm `agent-runner.ts:944` AbortController rides in `activeSessions`; add `session-registry.ts` to scope
- [ ] 1.4 RED→GREEN: grace-guard unit test (reconnect-before-fire cancels); restart-survival integration test on **dev** Supabase

## Phase 2 — git-data / worktree split + lease + fencing
- [ ] 2.1 Migration 114: `worktree_write_lease` table with `lease_generation` fencing column (+ `.down.sql`)
- [ ] 2.2 Enforce fencing token at the git-data ref-write boundary (stale generation rejected)
- [ ] 2.3 `git-data.tf`: shared bare-repo host over private net; worktrees → host-local NVMe
- [ ] 2.4 One-time cutover: drain + rsync objects/refs; verify `git rev-list --all` count match
- [ ] 2.5 RED→GREEN: stale-generation write rejected; lease acquire/release crash-safe

## Phase 3 — 2nd host + coordinator + Redis (concurrent multi-host, G1)
- [ ] 3.1 IaC PR-A: provision `SESSION_REDIS_PASSWORD` into Doppler `prd_terraform` (before any `.tf` merge)
- [ ] 3.2 IaC PR-B: `network.tf`, `redis-session.tf` + bootstrap, 2nd `hcloud_server`, `hcloud_placement_group type=spread`, `moved` blocks (verify `0 to destroy`)
- [ ] 3.3 `session-coordinator.ts`: lease-keyed routing + cross-host control forwarding (abort/gate/grace → owning host)
- [ ] 3.4 Affinity: reconnect routes back to lease-holder (TR2 cross-host fix); cancel stays host-local
- [ ] 3.5 `session-store.ts` Redis adapter; move replay buffer (preserve counter-outlives-clear); edit tunnel `service` → coordinator
- [ ] 3.6 RED→GREEN: two-users/two-hosts/one-workspace no-corruption; control-forward; affinity; replay no-rewind

## Phase 4a — Nomad + reschedule + lease-expiry reclaim (seamless crash, committed state)
- [ ] 4a.1 `nomad.tf` + jobspec; health-based reschedule + rolling deploys
- [ ] 4a.2 Fenced lease-expiry reclaim (new `lease_generation` on takeover) + re-provision from shared store / GitHub
- [ ] 4a.3 FR5: coordinator places session before start (bwrap mount/cwd never re-derived mid-turn, #5313)
- [ ] 4a.4 RED→GREEN: killed host → resume on survivor, no fresh-session greeting, committed work intact

## Phase 4b — Continuous worktree checkpoint (expensive tail — build after evidence)
- [ ] 4b.1 (Gated on OQ2 + a real crash-loss incident / operator GA requirement) checkpoint uncommitted state to durability store at cadence N
- [ ] 4b.2 DSAR/Art.17 erasure reaches checkpoints; TTL ≤ conversation retention

## Cross-cutting (every phase)
- [ ] Observability: op slugs (session_store_op, control_plane_route, worktree_lease, worktree_checkpoint) + Better Stack monitors + Sentry alerts; no-ssh discoverability test
- [ ] GDPR: run `/soleur:gdpr-gate` per-PR when its concrete regulated-data surface materializes; EU-pin every substrate; per-tenant isolation; no new sub-processor (self-host)
- [ ] `user-impact-reviewer` at each PR review (single-user-incident threshold)
- [ ] PR body uses `Ref #5274` (not `Closes`) until Phase 4 completes the epic
