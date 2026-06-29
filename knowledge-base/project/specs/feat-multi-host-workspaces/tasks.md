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
- [ ] 0.1 Author ADR-068 via `/soleur:architecture` (`status: adopting`); record coordinator-statelessness property
- [ ] 0.2 **Supersede** ADR-027 (`superseded-by: ADR-068`, not amend) — carries Bucket-A migration; **re-open** ADR-059 (it rejected Redis — buffer→Redis lands Phase 4a)
- [ ] 0.3 Edit `model.c4` (add sessionStore, gitDataStore, scheduler, coordinator[stateless] + relationships; widen `hetzner` desc) and `views.c4` (`view containers` include lines); run c4-code-syntax + c4-render tests

## Phase 1 — Host-local correctness (NO new infra)
- [ ] 1.1 Add host-local owning-host guard before `runDisconnectGraceAbort` (ws-handler.ts:228-240); race-free on single event loop
- [ ] 1.2 Confirm `userWorkspaces` restart-survival via #5338 rehydrate (registry:288-327); routing truth = Postgres
- [ ] 1.3 Audit legacy abort: confirm `agent-runner.ts:944` AbortController rides in `activeSessions`; add `session-registry.ts` to scope
- [ ] 1.4 Make `abortSession` (registry:190-213) return a found-count (mirror `drainAutonomousDisclosureGates`) — coordinator-forward affordance; harmless at replicas=1
- [ ] 1.5 RED→GREEN: grace-guard unit test (reconnect-before-fire cancels); restart-survival integration test on **dev** Supabase

## Phase 2 — git-data / worktree split + lease + fencing
- [ ] 2.1 Migration 114 `worktree_write_lease` (+ `.down.sql`) — mirror `029_*.sql:101-210`/`093_*.sql:50-125`: `pg_advisory_xact_lock` + `INSERT…ON CONFLICT DO UPDATE…WHERE heartbeat_at<now()-120s RETURNING`, `gen+1` in-statement, server-side `now()`; `touch_worktree_lease` RPC returns row_count
- [ ] 2.2 RLS: `revoke` from anon/authenticated/public; service_role SECURITY DEFINER RPCs only; SELECT gated `is_workspace_member` (059:71); `on delete cascade`; pin `search_path=public,pg_temp`
- [ ] 2.3 Fencing = **writer-side CAS** (NOT pre-check): git-data host holds per-ref monotonic max, atomically rejects `gen<max` at the write (pre-check is TOCTOU across a GC pause)
- [ ] 2.4 `git-data.tf` + `network.tf`: shared bare-repo host over private net; worktrees → host-local NVMe
- [ ] 2.5 Cutover: capture old state first (#5542), drain + rsync objects/refs; verify `git rev-list --all` count match
- [ ] 2.6 RED→GREEN: two concurrent acquires → one holder/loser-zero-rows; stale-gen write rejected by git-data host; RLS revoke + cascade verified

## Phase 3 — 2nd host + coordinator (concurrent multi-host, G1)
- [ ] 3.1 IaC: `2nd hcloud_server`, `hcloud_placement_group type=spread`, `moved` blocks (verify `0 to destroy`); coordinator service; tunnel `service` → coordinator
- [ ] 3.2 `session-coordinator.ts`: **stateless** lease-keyed routing + cross-host control forwarding (abort/gate/grace → owning host); local-resolve → not-found → RPC-forward → same resolver (composes with existing broadcast)
- [ ] 3.3 Cross-tenant git-data isolation: **per-`workspace_id` credential/mTLS** (reuse `resolve_workspace_installation_id` shape); NO cluster-wide mount cred; encryption-at-rest. (bwrap does NOT cover the Node-process fetch)
- [ ] 3.4 Coordinator authz: mTLS coordinator↔host + owning-host re-verifies conversation/lease ownership before honoring a forwarded op; control ports private-subnet only
- [ ] 3.5 Affinity: reconnect routes back to lease-holder (TR2 cross-host fix); cancel stays host-local (buffer host-local-sufficient here — Redis deferred to 4a)
- [ ] 3.6 RED→GREEN: two-users/two-hosts/one-workspace no-corruption; host-A cannot read tenant-B git-data (negative); forged control op rejected at owning host; affinity

## Phase 4a — Nomad + reschedule + lease-expiry reclaim + Redis buffer (seamless crash, committed state)
- [ ] 4a.1 `nomad.tf` + jobspec; health-based reschedule + rolling deploys
- [ ] 4a.2 `cron-worktree-lease-reclaim.ts` — Inngest **pure-TS** reclaim sweep (mirror `cron-workspace-sync-health.ts`, ADR-033; NOT GH Actions, NO spawn) + Sentry cron monitor; fenced `gen+1` takeover + re-provision
- [ ] 4a.3 `redis-session.tf`: dedicated EU node, **TLS**, `requirepass`/ACL, private-subnet firewall, no public IP; secrets via `random_password`→`doppler_secret`→runtime env (never argv, #5560)
- [ ] 4a.4 `session-store.ts` Redis adapter: move replay buffer (preserve counter-outlives-clear) with per-`workspace_id` key namespacing + read scope-check + TTL ≤ retention; capture-before-cutover (#5542)
- [ ] 4a.5 FR5: coordinator places session before start (bwrap mount/cwd never re-derived mid-turn, #5313)
- [ ] 4a.6 RED→GREEN: killed host → resume on survivor, no fresh-session greeting, committed work intact; cross-host replay no-rewind; Redis cross-tenant key read denied

## Phase 4b — Continuous worktree checkpoint (expensive tail — build after evidence)
- [ ] 4b.1 (Gated on OQ2 + a real crash-loss incident / operator GA requirement) checkpoint uncommitted state to durability store at cadence N
- [ ] 4b.2 DSAR/Art.17 erasure reaches checkpoints; TTL ≤ conversation retention

## Cross-cutting (every phase)
- [ ] Observability: op slugs (session_store_op, control_plane_route, worktree_lease, worktree_checkpoint) + Better Stack monitors + Sentry alerts; no-ssh discoverability test
- [ ] GDPR: run `/soleur:gdpr-gate` per-PR when its concrete regulated-data surface materializes; EU-pin every substrate; per-tenant isolation; no new sub-processor (self-host)
- [ ] `user-impact-reviewer` at each PR review (single-user-incident threshold)
- [ ] PR body uses `Ref #5274` (not `Closes`) until Phase 4 completes the epic
