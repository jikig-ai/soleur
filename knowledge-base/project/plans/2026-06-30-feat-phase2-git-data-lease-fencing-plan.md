---
title: "feat: Phase 2 — split git-data from worktrees + Postgres write-lease + writer-side CAS fencing"
date: 2026-06-30
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issue: 5274
epic_plan: knowledge-base/project/plans/2026-06-29-feat-multi-host-workspaces-layer-plan.md
spec: knowledge-base/project/specs/feat-multi-host-workspaces/spec.md
adr: ADR-068
related: [5240, 5273, 5275, 5338, 5542, 5546, 5723]
branch: feat-5274-phase2-git-data-lease-fencing
phase: 2
status: plan
---

# ✨ Phase 2 — split git-data from worktrees + Postgres write-lease + writer-side CAS fencing

> **Phase 2 of the `#5274` multi-host `/workspaces` epic.** Phase 0 (ADR-068 + C4,
> PR #5710) and Phase 1 (host-local grace guard + `abortSession` found-count, PR
> #5761) are merged + deployed. This plan scopes **tasks 2.1–2.7** of the live spec
> (`specs/feat-multi-host-workspaces/tasks.md`) plus the **2.8 IaC gate**. The epic
> plan, spec, and ADR-068 stay LIVE (not archived). The decision frame (writer-side
> CAS, lease-mirrors-`acquire_conversation_slot`, self-host EU, GA-at-Phase-3) is
> fixed by **ADR-068** — this plan instantiates it; it does not re-decide it.
>
> **`Ref #5274` (never `Closes`)** — the epic stays open through Phase 3 (GA).

## Overview

Today the backend is single-host: one Hetzner server → one RWO block volume
(`apps/web-platform/infra/server.tf:926-940`, `hcloud_volume.workspaces` =
`soleur-web-platform-data`) → `/workspaces/<workspace_id>` holding **both** each
workspace's git objects/refs **and** its working tree → one Node process. The RWO
single-attach volume **cannot** back a second host (Gap 2, confirmed). Phase 2
performs the architectural reframe ADR-068 §1 fixes: **bare git data
(objects/refs) on a shared `git-data` host over a private network; per-user
worktrees on host-local NVMe.** Concurrent multi-host serving is Phase 3 — Phase 2
*provisions the substrate and the safety primitives* that make a second host safe
to add:

1. A per-`(workspace_id, worktree_id)` **write-lease in Postgres** (migration 114),
   mirroring the canonical `acquire_conversation_slot` fenced upsert (ADR-068 §2).
2. **Writer-side compare-and-swap fencing** at the git-data host (ADR-068 §3) — the
   load-bearing data-integrity invariant, built + tested here, live-but-non-triggering
   at `replicas = 1`, load-bearing once Phase 3 adds the second writer.
3. A one-time **cutover** of the single host's git data onto the shared store, with
   GitHub as the durable rehydration source (`ensure-workspace-repo.ts`, #5546).

Phase 2 is the **highest-blast-radius** phase of the epic (it moves live data off
the volume that has held it since launch). It still runs `replicas = 1`; the
`ADR-027` invariant ADR-068 supersedes does not relax until the Phase-3 GA line.

This plan also lands **task 2.7**, a live-DB restart-survival integration test
deferred from Phase 1 (operator decision 2026-06-30).

## Research Reconciliation — Spec vs. Codebase

Focused code research (repo-research-analyst + learnings-researcher, 2026-06-30)
falsifies four premises the task descriptions inherited. **These corrections are
load-bearing — the plan is shaped by reality, not by the spec's prose.**

| Spec / task claim | Codebase reality (file:line) | Plan response |
|---|---|---|
| 2.7: "repo's **FIRST** `*.integration.test` — **set the vitest glob / env-gating** here." | **False — ≥10 `*.integration.test.ts` already exist** (`concurrency-acquire-slot-workspace-id.integration.test.ts`, `account-delete.cascade.integration.test.ts`, `byok.integration.test.ts`, `dsar-*.integration.test.ts`, …). The vitest `node` project already globs them (`vitest.config.ts:44` `include: ["test/**/*.test.ts", …]`); an established env-gate + synthetic-allowlist + teardown convention exists. | **Do NOT invent a harness.** Task 2.7 ADDS a file FOLLOWING the convention: `describe.skipIf(!INTEGRATION_ENABLED)`, `<NAME>_INTEGRATION_TEST=1`, run via `doppler run -p soleur -c dev -- env … ./node_modules/.bin/vitest run <path>`. No glob/config change. (`concurrency-acquire-slot-workspace-id.integration.test.ts:33-61` is the verbatim template — and it exercises the `acquire_conversation_slot` precedent Phase 2 mirrors.) |
| 2.2 / epic AC: "`references workspaces(id) on delete **cascade**` (Art.17 erasure)." | Every existing `workspace_id` FK uses **`ON DELETE RESTRICT`** (`059_workspace_keyed_rls_sweep.sql:206`) — intentional, to force explicit Art.17 *anonymisation* of audit lineage over silent cascade-drop (learning `2026-03-20…` §5). | **Honor the explicit CASCADE instruction for the lease table specifically**, because the lease is **ephemeral operational state with zero lineage value** (unlike `user_concurrency_slots`/`workspace_member_actions`, which carry audit lineage and therefore use RESTRICT). For ephemeral state, `CASCADE` is the *correct* Art.17 behavior — erasure reaches it automatically without blocking workspace deletion (TR4). Surfaced to **data-integrity-guardian** for confirmation; the divergence rationale is recorded so review does not re-flag it. **Verify the new lease table carries no WORM `BEFORE` trigger** that would deadlock the cascade (learning `2026-05-25-art17-cascade-deadlock…`) — it is a new table with none. |
| 2.7: "teardown via **`anonymise_user`** RPC, never DELETE." | No `anonymise_user` RPC. The canonical synthetic-user teardown is a **sequence**: delete slots/conversations → `rpc("anonymise_workspace_members", {p_user_id})` → `rpc("anonymise_workspace_member_actions", {p_user_id})` → delete workspaces/org → `auth.admin.deleteUser` (`concurrency-acquire-slot-workspace-id.integration.test.ts:131-164`). A *direct* `workspace_members` delete re-fires the WORM audit trigger and re-blocks `deleteUser`. | Copy the established teardown sequence **verbatim**. `anonymise_user` in the task is shorthand for it. |
| 2.4: implicit assumption of an existing private network. | **No `hcloud_network` exists** (Gap 3) — every server is on Hetzner public network only. | `network.tf` creates the **first** `hcloud_network` + subnet. (Confirms the task: "new shared bare-repo host over a private `hcloud_network`.") |
| Mechanism of the fence ("git-data host holds the monotonic max, rejects `gen<max` under a per-ref lock"). | ADR-068 §3 / epic plan fix the *decision* but **no implementation mechanism exists or is specified**; **no in-repo precedent for git server-side hooks** (Gap 9 — no bare-repo/split pattern today). | The plan **names a recommended mechanism** (server-side `pre-receive` hook + per-ref `flock` + monotonic-gen sidecar; lease-gen delivered via `git push --push-option`) and marks the exact delivery/storage form a **deepen-plan concretization** with a "novel pattern — no precedent" note. See Implementation Phase 2.3. |

**Carry-forward (NOT Phase 2 work, recorded for Phase 3):** `abortSession`'s
found-count (registry:208-235) counts **`activeSessions` only** (legacy lineage);
the dominant `cc-soleur-go` turn lives in `activeQueries` and returns 0 (Gap 1,
confirmed; comment warns at registry:190-206). A Phase-3 "lives on this host?"
predicate MUST `OR` it with a cc-registry count. No action this phase.

**Capability claims verified (`hr-verify-repo-capability-claim-before-assert`):**
existing infra root has the R2 backend (`infra/main.tf:1-20`), `infra-validation.yml`
(validate CI) + `apply-web-platform-infra.yml` (auto-apply on `infra/*.tf` merge)
exist; bootstrap precedents `inngest-redis-bootstrap.sh` et al.; migrations top out
at **113** (114 free — re-verify at /work, main moves fast); C4 `gitDataStore` +
`claude -> gitDataStore` already modeled (see ADR/C4 section).

## User-Brand Impact

**If this lands broken, the user experiences:** their workspace resumes showing a
**blank/fresh tree** (the #5240 regression) because the cutover lost refs or the
worktree-on-NVMe split mis-resolves the bare store; a commit silently failing to
persist because a push is rejected by a mis-built fence; or — worst — a corrupted
git index from a write that should have been fenced but was not.

**If this leaks, the user's data/workflow is exposed via:** the shared git-data
store or the private-network transport carrying another tenant's bare objects/refs
without per-tenant scoping. (Per-`workspace_id` credential/mTLS scoping is the
Phase-3 deliverable, ADR-068 §6; **Phase 2 must not bake in a cluster-wide mount
credential** a Phase-3 migration would have to rip out — single-web-host private-net
SSH trust only.)

**Brand-survival threshold:** single-user incident. **Blast-radius arithmetic (CPO condition):** the cutover's *raw* radius is **all workspaces** (it migrates every workspace's git data); "single-user incident" is the **post-mitigation residual** — the capture-first + ref-set-verify-before-destroy gate + GitHub rehydration are what collapse an all-user failure into a per-user one. `user-impact-reviewer` MUST confirm at PR review that that gate genuinely collapses all-user → single-user. **Encryption-at-rest on the git-data volume + per-`workspace_id` mTLS are Phase-3 GA-blocking (NFR-026)** — posture-neutral vs today's single volume (one host, all tenants, bwrap process isolation unchanged, ADR-068 §6), so not a Phase-2 control, but logged here so they do not fall through the cutover.

**CPO plan-time sign-off: APPROVED-WITH-CONDITIONS** (4 conditions, all folded: AC6 ref-set equality [load-bearing]; blast-radius arithmetic above; PR split per OQ1; encryption-at-rest logged Phase-3). Carried forward from the 2026-06-29 brainstorm `USER_BRAND_CRITICAL` triad **and re-affirmed at this plan** (`requires_cpo_signoff: true`). `user-impact-reviewer` runs at this PR's review.

## Implementation Phases

> **Split into PRs A / A′ / B / C — committed, NOT one PR (OQ1; Kieran P1-4).** All
> `Ref #5274` (never `Closes`). RED→GREEN per `cq-write-failing-tests-before`.
> Dependency order is load-bearing ACROSS the PRs (`2026-05-10-plan-phase-order…`): the
> **lease contract (2.1/2.2, PR A) precedes** the fence (2.3, consumes the gen) and the
> app-wiring (2.4, PR B — **behind the volume-default read flag, so B changes no read
> path until C flips it**; B's blast radius is "no read-path change pre-flip", not
> "inert"), which precede the cutover (2.5, PR C — the one irreversible step, lands last
> behind an already-deployed B).

### Phase 0 (this PR's pre-work — at `/work` start)
- Re-verify **114** is free: `git ls-tree -r --name-only origin/main apps/web-platform/supabase/migrations/ | grep -oE '/(11[0-9])_' | sort -u` — confirm `114_` absent AND the command lists `110_…113_` (an empty result is a malformed command, not a clean check — learning `2026-05-30-migration-number-collision…`). If a sibling PR took 114, renumber.
- Read `workspace-resolver.ts:240-260` (`readWorkspaceIdFromDb` signature + the `user_session_state.current_workspace_id` source) and `agent-session-registry.ts:296-342` (`resolveUserWorkspaceBinding` closure shape) to pin the 2.7 spy target. **Go/no-go for the 2.7 test design (Kieran P2-2):** confirm the DB read is **spy-able** — `resolveUserWorkspaceBinding` takes the reader as an injected arg (`(uid) => readWorkspaceIdFromDb(uid, tenant)`, registry:296), so the test injects a spy wrapper rather than `vi.spyOn`-ing a module local. If it were a closure-captured local, AC7 ("fired exactly once") would be unsatisfiable and the test must pass an injected reader.

### 2.1 — Migration 114 `worktree_write_lease` (+ `.down.sql`)
Mirror `029_plan_tier_and_concurrency_slots.sql:86-210` / `093_acquire_slot_workspace_id.sql:50-91` — **do not invent**.

- **Table:** `public.worktree_write_lease (workspace_id uuid not null references public.workspaces(id) on delete cascade, worktree_id text not null, host_id text not null, lease_generation bigint not null default 1, acquired_at timestamptz not null default now(), heartbeat_at timestamptz not null default now(), primary key (workspace_id, worktree_id))`. `host_id` is **infra identity** (text, NOT an `auth.uid()` — never an `auth.uid()=host_id` predicate; category error per task 2.2). `on delete cascade` per the Research Reconciliation row (ephemeral state; **data-integrity-guardian APPROVED** — RESTRICT would add friction with no accountability gain; the workspaces DELETE is still gated by the lineage tables' RESTRICT FKs). **Add an inline FK SQL comment** stating the chosen scope + Art.17 rationale (else every future migration reviewer re-flags it against the 059 RESTRICT norm), **and a note that no WORM `BEFORE` trigger may be added to this table later** without revisiting the cascade (pre-empts the `2026-05-25-art17-cascade-deadlock` class — the lease has none today).
- **`acquire_worktree_lease(p_workspace_id uuid, p_worktree_id text, p_host_id text)` → `table(host_id text, lease_generation bigint)`**, `security definer set search_path = public, pg_temp` (exact pin, `pg_temp` LAST — `cq-pg-security-definer-search-path-pin-pg-temp`, 029:107-108). Body: `perform pg_advisory_xact_lock(hashtextextended(p_workspace_id::text || ':' || p_worktree_id, 0));` (two-arg form, mirrors 029:125) then **one atomic statement**:
  ```sql
  insert into public.worktree_write_lease (workspace_id, worktree_id, host_id)
  values (p_workspace_id, p_worktree_id, p_host_id)
  on conflict (workspace_id, worktree_id) do update
    set host_id = excluded.host_id,
        lease_generation = case
          when public.worktree_write_lease.host_id = excluded.host_id
            then public.worktree_write_lease.lease_generation       -- same host: keep gen (idempotent refresh)
          else public.worktree_write_lease.lease_generation + 1     -- cross-host takeover: bump
        end,
        acquired_at = case
          when public.worktree_write_lease.host_id = excluded.host_id
            then public.worktree_write_lease.acquired_at
          else now()
        end,
        heartbeat_at = now()
    where public.worktree_write_lease.host_id = excluded.host_id
       or public.worktree_write_lease.heartbeat_at < now() - interval '120 seconds'
  returning host_id, lease_generation;
  ```
  **data-integrity-guardian P1 (self-lockout fix):** the WHERE must include `host_id = excluded.host_id`, else a **same-host re-acquire of its own still-fresh lease** (overlapping agent runs / crash-restart <120s) no-ops → zero rows → the host wrongly concludes "lost" and self-locks out of its own worktree for up to 120s (the exact "commit silently failing to persist" User-Brand failure, at `replicas=1`, self-inflicted). The CASE keeps gen stable on same-host refresh (idempotent, mirrors `acquire_conversation_slot`'s unconditional `do update`) and bumps only on cross-host takeover. `gen+1` is in-statement (no TOCTOU). A **live lease held by ANOTHER host ⇒ zero rows ⇒ caller lost**. Expiry uses **server-side `now()` only** (clock-skew hazard, ADR-068 §2). Use `'120 seconds'` to match the precedent string. **Atomicity rests on the `ON CONFLICT … WHERE` EvalPlanQual re-check** (two takeover racers: first sets `heartbeat_at=now()`, second re-evaluates against the updated row, no-ops, gets zero rows) — the `pg_advisory_xact_lock(hashtextextended(p_workspace_id::text || ':' || p_worktree_id, 0))` is redundant-but-harmless here (no multi-statement window like 029's sweep+count+cap) and kept only for shape-parity.
- **`touch_worktree_lease(p_workspace_id uuid, p_worktree_id text, p_host_id text, p_lease_generation bigint)` → `integer`** (Kieran P1-1: the gen-match WHERE needs a bound param — the 3-arg form had nothing to bind `<held gen>` to) (row_count via `get diagnostics v := row_count`, mirror `touch_conversation_slot` 029:174-191): `update … set heartbeat_at = now() where workspace_id=… and worktree_id=… and host_id=p_host_id and lease_generation=p_lease_generation`. **A 0 return ⇒ the lease was reclaimed** (a host learns it lost). No time predicate ⇒ no clock-skew false-zero (data-integrity-guardian). The host MUST `touch` with the gen returned by its **most-recent successful `acquire`** (the CASE above keeps that gen stable across same-host refresh, so `touch` never spuriously returns 0). Cadence comfortably `<< 120s`.
- **`release_worktree_lease(p_workspace_id uuid, p_worktree_id text, p_host_id text, p_lease_generation bigint)`** — delete the row only if `host_id` **and** `p_lease_generation` still match (no stomp of a reclaimer; the gen param is required for the match — Kieran P1-1).
- **Lease lifecycle — STATE IT EXPLICITLY (Kieran P1-3, else 2.4 "around write ops" vs the SIGTERM/heartbeat wiring imply different answers):** **acquire at session/turn start**; **heartbeat (`touch`) ≤30s while held**; the returned `lease_generation` is **captured in-memory and reused as the `lease-gen` push-option for every push in that session**; **release on session-end AND on SIGTERM**. (A per-push lease would need no heartbeat and hold nothing at SIGTERM — so the design is per-session.)
- **`host_id` MUST be host-stable, with a CONCRETE source (Kieran P1-2 — the container's default `hostname` is a fresh random id every `docker run`, i.e. the forbidden per-container value).** Source it from the **Hetzner server ID injected at cloud-init into an env var the container reads** (or `docker run --hostname=<stable>` in `ci-deploy.sh`) — NOT the container hostname. **NOT per-container/per-process** (spec-flow P0-2). Deploys are **recreate** (`ci-deploy.sh:842-884` — `docker stop` then `docker run`); a host-stable `host_id` hits the `OR host_id = excluded.host_id` carve-out and re-acquires **immediately** (the SIGTERM-release masks the graceful path; host-stability is what covers the crash/SIGKILL/grace-timeout path the lockout actually bites on). Add the id-injection to Files-to-Edit (cloud-init / `ci-deploy.sh`) + AC2(d) must test the **crash-path** (not just graceful) re-acquire.
- **Release on shutdown (spec-flow P0-2):** the existing SIGTERM drain handler (`index.ts:240-286` — `abortAllSessions`/`drainCcQueriesForShutdown`, 8s budget under the 12s docker grace) MUST also `release_worktree_lease` for every held lease before `process.exit`. Defense + correctness for a genuine host-down (a crashed host's lease then expires at 120s and a surviving host reclaims — Phase 3/4a).
- **On `touch` returning 0 (spec-flow P1-B):** the host MUST **fail loud** — abort the in-flight write, surface via Sentry (`worktree_lease` op slug), never silently retry into a no-op'd write. Add to the Observability failure-modes table.
- **Heartbeat cadence ≤ 30s** (spec-flow P1-C) — well under the 120s expiry so a long push/clone/turn cannot let the lease lapse with one host.
- **GRANTs (029:205-210):** `revoke all on function … from public; grant execute … to service_role;` for all three. Give every function the **full `revoke … from public` form even if INVOKER** (lazy-regex lint `test/migration-rpc-grants.test.ts` conflates an INVOKER fn before a DEFINER — learning `2026-05-29-…-rpc-grants-invoker-before-definer`).
- **`.down.sql`:** drop the three functions (all signatures) then the table.
- **Lawful-basis annotation (`gdpr-gate GDPR-Art-6`):** head the migration with `-- LAWFUL_BASIS: legitimate interest (service operation — per-worktree write coordination across hosts)`. The lease columns are operational, not special-category (no `GDPR-Art-9` match).

### 2.2 — RLS
- `alter table public.worktree_write_lease enable row level security;`
- `revoke all on public.worktree_write_lease from anon, authenticated, public;` — **no write policies** (writes via the service_role SECURITY DEFINER RPCs only; mirror 029:86-93; `FOR ALL USING` would apply to writes — avoid).
- **SELECT policy** (mirror 059:227-229): `create policy worktree_write_lease_member_select on public.worktree_write_lease for select to authenticated using (public.is_workspace_member(workspace_id, auth.uid()));`. `is_workspace_member` is **plpgsql, non-inlinable** (Gap 6, 053:115-140) — do not reimplement as `sql STABLE`.
- FK `references public.workspaces(id) on delete cascade` (Art.17 — see Research Reconciliation).

### 2.3 — Fencing = writer-side CAS at the git-data host (NOT a pre-check) — **load-bearing**
ADR-068 §3 / Risks: a generation check *before* the ref write is TOCTOU (a GC-paused holder reads `gen=N` current, is reclaimed to `N+1`, resumes, writes — check passed, write corrupts). The git-data host (the resource server, Kleppmann) must atomically reject any write with `gen < max` under a per-`(workspace,worktree)` lock.

- **Recommended mechanism (novel — no in-repo precedent, Gap 9):** a server-side **`pre-receive` hook** on each bare repo at the git-data host. The web host, holding lease `gen=N`, pushes refs over the private net and presents BOTH **`--push-option=lease-gen=N` AND `--push-option=worktree-id=<id>`** (read in the hook from `GIT_PUSH_OPTION_*`). **Kieran P0-1 (buildability):** the bare repo is per-*workspace* but the sidecar/lock is per-`(workspace,worktree)`, so the hook MUST be told which worktree is pushing — `lease-gen` alone leaves the hook unable to pick `<worktree_id>.gen`, making the fence unbuildable. A missing `worktree-id` is fail-closed (reject), same as a missing `lease-gen`. The hook, under a **per-`(workspace,worktree)` `flock`**, reads the stored monotonic max (sidecar `$GIT_DIR/fence/<worktree_id>.gen`), **rejects (`exit 1`) if `N < stored_max`** (strict `<` — **equal gen is allowed** for an idempotent retry of a partial/timed-out push; `acquire`'s atomic `gen+1` guarantees a given gen is held by exactly one host, so equal never admits a competing writer — data-integrity-guardian: do NOT change to `<=`), else sets `stored_max = max(stored_max, N)` and allows the push. The `flock` makes read-check-write atomic per `(workspace, worktree)` (one lock for the whole push — see Fail-closed contract). **`pre-receive` (not `update`/`post-receive`)** so the whole push is rejected atomically before any ref is written. **Initial / missing sidecar ⇒ `stored_max = 0`, accept, then write `N`** (data-integrity-guardian P2 — a read-failure-on-absent-file would brick the first push at `gen=1`/post-cutover; defaults make `1 >= 0` pass). **The sidecar + flock target MUST live on the persistent git-data volume, never tmpfs** — a reboot resetting max to 0 would let a stale `gen=5` writer beat a fresh `0` (the one silent fence regression; raise at deepen-plan 4.4).
- **Fail-closed contract (spec-flow P0-3 / P1-E / P1-F):** (a) a push with **no `lease-gen` push-option** (`GIT_PUSH_OPTION_COUNT=0` — a manual operator push, a future code path that forgets the wrapper) MUST be **rejected (`exit 1`)**, never treated as gen 0 / fall-through (else the fence is fail-OPEN — the exact silent-corruption path this phase exists to prevent); (b) **one `flock` per `(workspace, worktree)` for the WHOLE push** (read gen once, check once, advance `stored_max` once **after all refs accepted** — a single `pre-receive` can carry many refs on stdin; resolve the "per-ref" vs "per-worktree" wording to per-`(workspace,worktree)`); (c) write the sidecar **atomically** (tmp + `mv` under the flock); **unparseable/partial `.gen` ⇒ fail-closed (reject)**. Confirm the worktree↔ref↔bare-repo mapping at deepen-plan (if two worktrees of one workspace can push the *same* ref, a worktree-keyed fence does not serialize them on that ref — a correctness hole to close or rule out).
- **Lease↔fence coupling (make explicit):** the gen presented to git-data is the *same* gen `acquire_worktree_lease` RETURNs. On reclaim by another host the gen becomes `N+1`; the old host's `gen=N` push is now `< max` → rejected. Fencing — not the 120s heartbeat — is what makes a late write from a stale/GC-paused holder a **no-op rather than corruption**.
- **At `replicas = 1` the fence is LIVE but never rejects** — the acquire CASE keeps `lease_generation` stable for the single (same-`host_id`) host even across a reclaim-after-expiry, so gen never increments → no `gen<max` ever arises (spec-flow P1-A: the precise claim is "no cross-host reclaim ⇒ gen never climbs ⇒ no rejection," NOT "gen literally never changes by any path"). Not dormant code, live-but-non-rejecting. It becomes load-bearing at Phase 3's second writer. This is the safest foundations shape (learning `2026-05-07-foundations-pr-must-not-declare-downstream-contracts`): nothing downstream *consumes* a rejection until a 2nd host exists, and the git-data host enforces from day one.
- **Deepen-plan concretization (in-scope task, not deferred):** the exact gen-delivery (push-option vs `pre-receive` env) and storage (sidecar file vs a `refs/fence/<wt>` ref) carry a `## Risks` precedent-diff at deepen-plan Phase 4.4 with a "novel pattern — no precedent" note (no git-server-side-hook precedent in repo).

### 2.4 — IaC + app-wiring for the git-data split
**IaC** (extends the existing `apps/web-platform/infra/` root — **see the corrected `## Infrastructure (IaC)` section, which supersedes any summary here**): `network.tf` (first `hcloud_network` + subnet) and `git-data.tf` (new `hcloud_server` with **egress IPv4 + zero-inbound-rule firewall = deny-all public ingress**; private-net transport needs no allow rule + its own `hcloud_volume` for bare repos + cloud-init that installs git, creates the bare-repo root, installs only a **placeholder** hook — the real `pre-receive` fence hook ships via the deploy pipeline). **Cloud-init-only** for the new host (no SSH provisioner → no apply-time SSH dependency → the plan-skill network-outage gate does not fire) + a non-provisioner readiness gate before cutover; idempotent `git-data-bootstrap.sh` (mirror `inngest-redis-bootstrap.sh`); scripts embedded via `base64encode(file(...))` (learning `2026-03-20-terraform-base64encode-cloud-init`).

**App-wiring** (the worktree/bare split, `replicas = 1`): worktrees move to host-local NVMe; objects/refs to the git-data host; the web host acquires the lease around write ops and pushes through the fence. Edit set (precise refactor depth + the lease-acquire call sites are a **deepen-plan deliverable** — anchors below):
- `workspace-resolver.ts:39,792-797` — split `WORKSPACES_ROOT` into a host-local worktree root + the remote bare-store address, **behind a read-source flag defaulting to the volume** (spec-flow P0-5) — deployed-on-merge code keeps reading the volume until the cutover verify gate flips the flag to git-data (2.5).
- `ensure-workspace-repo.ts:144-303` (`ensureWorkspaceRepoCloned`, `realGraftRepoClone`) — provision a worktree on local NVMe wired to the shared bare store; GitHub stays the rehydration source (#5546; the `isValidGitWorkTree` / empty-corrupt-fingerprint heal at :150-161 still gates).
- `worktree-manager.sh` / `agent-runner.ts` — worktree creation on local NVMe.
- **New `apps/web-platform/server/worktree-write-lease.ts`** — `acquire/touch/release_worktree_lease` RPC client + the `git push --push-option=lease-gen=<N>` wrapper; mirror `concurrency.ts:77-129` for the RPC-call shape.
- `git-auth.ts` — private-net git transport to the git-data host (single SSH keypair, **random-generated** via the `tls`/`random` providers — NOT operator-minted, no no-default `TF_VAR`; see IaC).

### 2.5 — One-time cutover (the one irreversible step — lands last, behind verification)
- **Write-freeze the cutover window (spec-flow P0-4):** "drain" stops in-flight sessions but does NOT prevent a NEW session writing between capture and switchover (→ a lost ref / nondeterministic verify). Hard-freeze writes for the window — cleanest is to **stop the web container for the rsync** (consistent with the recreate-deploy semantics at `ci-deploy.sh:842`); the volume "untouched until verify" claim only holds under a real freeze, not drain alone.
- **Capture-before-cutover (#5542):** capture the OLD `/workspaces` git state to a persistent medium FIRST — a per-workspace **`git for-each-ref` `name→sha` manifest** (NOT `rev-list | wc -l`, a proxy); never re-read the new (empty) store and silently lose refs.
- `rsync` `objects/refs` from the volume to the git-data host's bare store per workspace. **Skip non-repo / never-cloned workspace dirs** (no `objects/refs` ⇒ `git rev-list` exits non-zero ⇒ `set -e` would kill the whole cutover — spec-flow P1-G): detect + count 0 + continue. **rsync partial-failure contract (spec-flow P1-H):** reset/clean the destination on a transient rsync error (or rely on rsync incremental) so an idempotent re-run is safe; distinguish a transient rsync error from a verify mismatch.
- **Verify pre == post:** per-workspace **ref-set equality** (`git for-each-ref` `name→sha`, sorted) on the source equals the shared bare store, plus `git rev-list --all --count` as a secondary check (CPO: count alone masks a dropped branch/HEAD ref — the #5240 blank-tree class). Any mismatch ⇒ abort + roll back to the volume (the volume is untouched until verification passes).
- **Switchover via a read-source flag (spec-flow P0-5 — the load-bearing sequencing gap):** the app-wiring (2.4) that reads from git-data deploys **on merge**, but the cutover that POPULATES git-data is a **separate post-merge script**. If deployed code reads the empty git-data store before rsync, EVERY workspace resolves blank (mass #5240). Gate the read source behind a flag **defaulting to the volume**; the cutover flips it to git-data **only after the verify gate passes**, then triggers a controlled restart. An empty/unpopulated git-data store is **never read as truth**. (This is the within-host switchover the PR-split — OQ1 — does not by itself solve.)
- **GitHub is the durable rehydration source** (`ensure-workspace-repo.ts` self-heal, #5546) **for pushed refs only**: a workspace whose bare data is missing/corrupt post-cutover re-clones from GitHub — honest, never a silent fresh tree. **But local-only commits/branches never pushed to GitHub are NOT recoverable by rehydration (spec-flow P1-I)** — so the **capture + ref-set verify (not rehydration) is the safety net for local-only refs**; the verify MUST cover all local refs, not just GitHub-mirrored ones.

### 2.6 — Art.17 erasure reaches the bare git data (gdpr-gate `GDPR-Art-17` fold-in)
Phase 2 creates the **first concrete user-content store on a new host** (bare objects/refs on the git-data host). The lease row cascade-deletes with its workspace (2.2), but a workspace/account erasure does **not** otherwise reach the bare repo on the git-data host — the existing `anonymise_*` / account-delete flow has no step for it. A new PII store must wire its own erasure (TR4; `cq-write-boundary-sentinel-sweep-all-write-sites` analogue for the erasure boundary).
- Wire the workspace/account-deletion path to **remove the workspace's bare repo directory from the git-data host** (over the private-net transport), idempotently (missing dir = already-erased = ok). Identify the call site by grepping the existing erasure flow (`anonymise_organization_membership` / the `account-delete.cascade` path the `*.cascade.integration.test.ts` exercises) — name it at deepen-plan with file:line.
- This is the Phase-2 instance of the epic's cross-cutting TR4 ("erasure must reach worktree checkpoints/snapshots"); do not defer it — the store is created here, so its erasure is wired here.

### 2.7 — Live-DB restart-survival integration test (deferred from Phase 1)
New `apps/web-platform/test/workspace-binding-restart-survival.integration.test.ts`, **following the existing convention** (NOT a new harness — Research Reconciliation row 1). Template: `concurrency-acquire-slot-workspace-id.integration.test.ts`.
- Env-gate `describe.skipIf(process.env.WORKSPACE_BINDING_INTEGRATION_TEST !== "1")`; run `cd apps/web-platform && doppler run -p soleur -c dev -- env WORKSPACE_BINDING_INTEGRATION_TEST=1 ./node_modules/.bin/vitest run test/workspace-binding-restart-survival.integration.test.ts`.
- Synthetic-email allowlist (`hr-destructive-prod-tests-allowlist`, `cq-test-fixtures-synthesized-only`): `/^wsbinding-[a-f0-9]{16}@soleur\.test$/` + `assertSynthetic`.
- `service.auth.admin.createUser({email, email_confirm:true})` → the mig-053 `handle_new_user` trigger auto-creates the solo workspace (`workspaces.id = user.id`, ADR-038 N2) + owner membership + WORM audit row. **No explicit workspace-create.**
- Seed `user_session_state.current_workspace_id` for the user (the #5338 source `readWorkspaceIdFromDb` reads — confirm table/column at Phase 0).
- **Assertions — call TWICE (spec-flow P2-A, to prove restart-survival AND memoization, which are distinct):** wrap the DB-read closure in a spy. **Call 1 (cold, Map empty — the restart):** `readWorkspaceIdFromDb` fires, returns the seeded workspace_id, Map written back. **Call 2 (warm, Map populated):** spy does **NOT** fire again. Assert the spy fired **exactly once across both**. Construct a **brand-new registry instance** (all maps empty), not merely `userWorkspaces.clear()` (spec-flow P2-B) — a faithful restart proxy must not leave other in-memory state a real restart would lose; confirm the registry-construction shape at Phase 0.
- **Teardown — verbatim established sequence** (registry-test:131-164): delete slots/conversations → `anonymise_workspace_members` → `anonymise_workspace_member_actions` → delete workspaces/org → `deleteUser`. NEVER a direct `workspace_members` delete (re-fires WORM audit → re-blocks).
- **DEV only** (`hr-dev-prd`); precondition: DEV schema matches main's migration history (learning `2026-05-21-dev-supabase-drift…` — unmerged feature branches poison shared dev). Avoid strict cross-clock `now()` vs GoTrue `iat` comparisons (learning `2026-05-30-…clock-skew-flake`); this test asserts identity/call-count, not near-now timestamp boundaries, so it is structurally safe.

## Files to Create
- `apps/web-platform/supabase/migrations/114_worktree_write_lease.sql` + `114_worktree_write_lease.down.sql` (2.1/2.2)
- `apps/web-platform/infra/network.tf` (2.4 — first `hcloud_network` + subnet)
- `apps/web-platform/infra/git-data.tf` (2.4 — `hcloud_server` + `hcloud_volume` + firewall + cloud-init)
- `apps/web-platform/infra/git-data-bootstrap.sh` (2.4 — idempotent re-apply; the `pre-receive` fence hook payload)
- `apps/web-platform/server/worktree-write-lease.ts` (2.4 — lease RPC client + push-with-gen wrapper)
- `apps/web-platform/test/workspace-binding-restart-survival.integration.test.ts` (2.7)
- RED→GREEN unit/integration tests for 2.1/2.3 (see Acceptance Criteria)

## Files to Edit
- `apps/web-platform/server/workspace-resolver.ts` (`:39`, `:792-797` path composition) — 2.4
- `apps/web-platform/server/ensure-workspace-repo.ts` (`:144-303`) — 2.4 (GitHub rehydration preserved, #5546)
- `apps/web-platform/server/agent-runner.ts` + `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` (worktree on local NVMe) — 2.4
- `apps/web-platform/server/git-auth.ts` (private-net transport; consume `GIT_TRANSPORT_SSH_PRIVATE_KEY` from Doppler at runtime) — 2.4
- `apps/web-platform/server/index.ts:240-286` (SIGTERM drain handler — add `release_worktree_lease` for held leases before exit; spec-flow P0-2) — 2.4
- `apps/web-platform/infra/variables.tf`, `firewall.tf` (private subnet rules), `cloud-init.yml` if the web host mounts change — 2.4
- The workspace/account-erasure flow (the `account-delete.cascade` path + `anonymise_organization_membership` call site) — add the git-data bare-repo removal step (2.6, `gdpr-gate GDPR-Art-17`)
- `knowledge-base/legal/article-30-register.md` (new processing/storage location: git-data host — `gdpr-gate GDPR-Art-30`; grep `^## Processing Activity` for the next free PA-id before assigning) — 2.4
- `knowledge-base/operations/expenses.md` (record the new git-data host recurring spend — `wg-record-recurring-vendor-expense-before-ready`) — 2.4
- `knowledge-base/project/specs/feat-multi-host-workspaces/tasks.md` (check off 2.1–2.7) — at ship

## Acceptance Criteria

### Pre-merge (PR)
- **AC1 — migration round-trips on DEV:** `114_worktree_write_lease.sql` applies and `114_…down.sql` reverses cleanly against **dev** Supabase (`hr-dev-prd`, never prod).
- **AC2 — lease atomicity (the concurrency invariant):** (a) two overlapping `acquire_worktree_lease` calls for the same `(workspace_id, worktree_id)` from two distinct `host_id`s ⇒ **exactly one returns a row (one holder); the loser gets zero rows;** (b) **same-host re-acquire of its own fresh lease RETURNS its own row with the SAME `lease_generation`** (idempotent — the self-lockout regression test, data-integrity-guardian P1); (c) cross-host re-acquire after `heartbeat_at` ages past 120s succeeds with `lease_generation` incremented by 1; (d) **SIGTERM releases held leases and a fresh process re-acquires immediately (no 120s wait)**, AND the **crash-path** (SIGKILL/grace-timeout, no release) re-acquire by the same host-stable `host_id` also returns its own row immediately — the per-deploy lockout regression (spec-flow P0-2, Kieran P1-2); (e) **`touch` against a reclaimed / gen-bumped lease returns 0 and the caller aborts the in-flight write + emits the `worktree_lease` Sentry slug** (fail-loud, Kieran P1-5); (f) **`release` with a stale `lease_generation` is a no-op** (no stomp of a reclaimer, Kieran P1-5).
- **AC3 — fencing CAS (the load-bearing AC, sharper than heartbeat timeout):** a write presented at `gen=N` is **rejected by the git-data host after any `gen>N` has been observed for that ref, even if the writer still believes it holds `N`** (deterministic test: write at N, observe N+1, attempt write at N → rejected; no two real hosts required). Also assert: **a push missing EITHER the `lease-gen` OR the `worktree-id` push-option is rejected (fail-closed, spec-flow P0-3 / Kieran P0-1)**; the **first push at `gen=1` against an absent sidecar is accepted** (`stored_max=0`); an **equal-gen retry (`N==max`) is accepted** (idempotent partial-push recovery); an **unparseable sidecar rejects**.
- **AC4 — RLS:** `pg_policy` shows the lease table has **no write policy** and a single `is_workspace_member`-gated SELECT policy; `revoke`d from anon/authenticated/public; a `BEGIN; SET LOCAL ROLE authenticated; …; ROLLBACK;` dry-run shows a non-member cannot SELECT and no role can write directly (writes only via service_role RPC). Verified read-only — **no synthetic users created against prod** (`hr-dev-prd`, the learning `2026-05-16-…prod-synthetic-users` class).
- **AC5 — cascade erasure:** deleting a `workspaces` row removes its lease rows (cascade), with **no WORM `BEFORE`-trigger deadlock** on the lease table (it has none).
- **AC6 — cutover loses no refs (assert the invariant, not a proxy — CPO load-bearing condition):** for each migrated workspace, **per-ref `name→sha` set equality** pre==post via `git for-each-ref --format='%(refname) %(objectid)'` (sorted) — NOT only `git rev-list --all --count`. Count equality masks a dropped branch/HEAD ref whose commits stay reachable from another ref (the exact #5240 blank-tree class). **Go/no-go = `git fsck --full --strict` exit 0 (recomputes every object hash + connectivity — the actual corruption detector for count-equal-but-corrupt rsync) AND `git for-each-ref` `name→sha` OID parity source-vs-destination** (data-integrity-guardian P1). `rev-list --all --count` is a secondary check only — count equality passes on both corrupt objects and diverged refs. Optional: `git rev-list --objects --all | sort` set-compare for the exact blob+tree+commit set.
- **AC7 — 2.7 integration test passes on DEV** (env-gated, opt-in): spy asserts `readWorkspaceIdFromDb` fired exactly once, `userWorkspaces` Map empty at call / written back after; teardown leaves no synthetic residue.
- **AC6b — switchover safety (spec-flow P0-4/P0-5):** deployed code reads the **volume** until the cutover verify gate flips the read-source flag to git-data; an **empty/unpopulated git-data store is never read as truth** (test: with the flag defaulted, the app resolves workspaces from the volume even though git-data is empty). No workspace write can commit between capture and switchover (write-freeze gate, not drain alone).
- **AC7b — Art.17 erasure reaches bare git data (`gdpr-gate GDPR-Art-17`):** a workspace/account-erasure removes the workspace's bare repo from the git-data host (test: erase → the bare-repo dir is gone, idempotent on a second call); migration 114 carries the `-- LAWFUL_BASIS:` annotation (`GDPR-Art-6`); the git-data host has an `article-30-register.md` entry (`GDPR-Art-30`).
- **AC8 — `tsc` clean:** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (NOT `npm run -w …` — no root `workspaces` field, learning `2026-05-13-npm-workspaces-flag…`).
- **AC9 — `terraform validate` clean** on the extended root (CI `infra-validation.yml`); `terraform plan` shows the git-data host + network as **`+create`, `0 to destroy`** (no churn of the existing web host / volume).

### Post-merge (operator) — automation-gated
- IaC auto-applies via `apply-web-platform-infra.yml` on the `infra/*.tf` merge (no operator SSH/dashboard — `hr-all-infrastructure-provisioning-servers`). Migration 114 applies via `web-platform-release.yml#migrate` (the canonical mechanism). **The cutover (2.5)** is the one step needing a gated, verified run: prescribe it as an **idempotent script with the capture-first + rev-list-verify built in** so it is re-runnable and self-checking, run post-merge against prod with the verification as the go/no-go (read-only verification queries per `hr-no-dashboard-eyeball-pull-data-yourself`). `Ref #5274`; do **not** `Closes`.

> All `awk`/`grep` AC verification commands use flag-based ranges, not `/start/,/end/` (self-match trap, learning `2026-05-15-plan-ac-verification-commands-awk-self-match`), and assert the **invariant**, not a proxy (count vs identity).

## Domain Review

**Domains relevant:** Engineering, Legal, Operations (carry-forward from the
2026-06-29 brainstorm `## Domain Assessments` + this plan's research). Product = NONE.

### Engineering (CTO)
**Status:** reviewed (carry-forward + this plan's research; CTO gate re-run at plan time — see findings folded below).
**Assessment:** the lease mirrors a proven precedent; the load-bearing novelty is the fence mechanism (no in-repo precedent) and the cutover blast radius. The foundations discipline (fence live-but-non-triggering at `replicas=1`; no Phase-3 contract declared ahead of delivery) is the correctness frame.

### Product/UX Gate
**Tier:** none — no UI surface (`## Files to Create`/`Edit` contain no `components/**`, `app/**/page.tsx`, `app/**/layout.tsx`; mechanical UI-surface scan negative). Backend infra/orchestration only.
**Pencil available:** N/A (no UI surface)

### Legal (CLO) + GDPR Gate (Phase 2.7)
**Status:** `/soleur:gdpr-gate` run against the migration 114 + RLS + git-data transport surface. **No Critical (no Art. 9 special-category).** Three `Important` fold-ins, all wired into this plan: **`GDPR-Art-17`** — erasure must reach the bare git data on the new host (task 2.6 + AC7b); **`GDPR-Art-6`** — `-- LAWFUL_BASIS:` annotation on migration 114 (task 2.1); **`GDPR-Art-30`** — register the git-data host (`article-30-register.md`, Files to Edit). `GDPR-Chapter-V` PASS (Hetzner EU, self-host, **no new sub-processor**). The lease row is operational state (host_id, generation, timestamps) keyed to `workspace_id`. Cross-tenant git-data isolation (per-`workspace_id` cred/mTLS) is the **Phase-3** GA-blocking control (ADR-068 §6) — Phase 2's single-host private-net trust is the floor, not the GA posture.

### Operations (COO)
**Status:** carry-forward — +1 git-data host + private network is first-class recurring cost (recorded in `expenses.md` at this PR, `wg-record-recurring-vendor-expense-before-ready`); Better Stack monitor added (Observability).

## Infrastructure (IaC)

> **terraform-architect review folded in (1 P0 + 3 P1 + 2 P2).** The corrected shape below supersedes the draft's "no public IP / fence-in-cloud-init" design.

### Terraform changes
- **Root:** **extends the existing `apps/web-platform/infra/`** (R2 backend `infra/main.tf:1-20`, `use_lockfile=false`). **No new root** ⇒ `hr-every-new-terraform-root` does **not** fire; `infra-validation.yml` already gates `terraform validate`; providers (`hcloud ~>1.49`, `tls ~>4.0`, `random ~>3.0`) already pinned + locked. Confirmed by terraform-architect.
- **`network.tf` (first `hcloud_network`):** `hcloud_network` (`10.0.0.0/16`) + `hcloud_network_subnet` (`network_zone = "eu-central"` — `hel1`/`fsn1`/`nbg1`; `var.location=hel1` is eu-central, state it) + **`hcloud_server_network` (separate resource, NOT inline `network{}`)** attaching the **existing** web host (additive, does NOT replace `hcloud_server.web`) at a stable private IP + the git-data host. `git-auth.ts` targets git-data's private IP.
- **`git-data.tf`:** `hcloud_server` (`var.git_data_server_type` default **`cax11`** ARM64 — cheaper, git/sshd-compatible) + **`public_net { ipv4_enabled = true; ipv6_enabled = true }` (P0 — egress for `apt`/GitHub; cloud-init `apt-get install git` has NO internet on a no-public-IP host since no NAT gateway exists)** + `hcloud_volume` (`var.git_data_volume_size`, min 10 GB, same location) + `hcloud_volume_attachment` + **`hcloud_firewall` with ZERO inbound rules = deny-all PUBLIC ingress (P1 — Hetzner firewalls filter only the public interface; intra-`hcloud_network` traffic is open by membership and needs no allow rule)**. **Do NOT pre-set `lifecycle.ignore_changes=[user_data]`** on this fresh host — the web host carries it only as an *import artifact* (server.tf:66-72); a fresh host has no spurious diff, and omitting it preserves a clean replace-to-reprovision path during the fence-iteration window (P1).
- **In-band transport key (no operator mint, no no-default `TF_VAR` — `hr-tf-variable-no-operator-mint-default`):** a **dedicated** `tls_private_key.git_transport` (ED25519; NOT reused from `ci_ssh`); public half → git-data `authorized_keys` via cloud-init **with a `command="git-shell"` restricted forced-command**; private half → **`doppler_secret` `GIT_TRANSPORT_SSH_PRIVATE_KEY` (masked)** consumed by `git-auth.ts` at runtime (NOT cloud-init — the web host carries `ignore_changes=[user_data]` so cloud-init can't reach the running container; mirror `doppler_secret.deploy_ssh_private_key` ci-ssh-key.tf:51-57). (P2) **This single shared key is intentionally throwaway (Kieran P2-4):** the Phase-2 floor (one web host, git-shell-scoped); Phase 3's per-`workspace_id` mTLS (ADR-068 §6) replaces it (the Phase-3 plan must plan its removal). It is NOT a cluster-wide *mount* credential (the §6-forbidden thing), so the swap is additive-then-remove, not a rip-out.
- **Fence hook delivery (P1 — load-bearing):** cloud-init installs only the **durable substrate** (git, bare-repo root, volume mount, the transport pubkey, a *placeholder* hook). The **real `pre-receive` fence hook ships via the web-platform deploy payload** — the web host pushes it to git-data over the private net during `ci-deploy.sh`. This keeps the most-likely-to-change, safety-critical artifact **iterable through the existing automated pipeline** instead of stranded behind un-reachable cloud-init (CI cannot SSH to either host — `ci-ssh-key.tf` header; no host replacement per fence edit).

### Apply path
- **(a) cloud-init-only on git-data** — correct **and required** (the CI runner cannot SSH to either host, so any `remote-exec` would hang the merge-triggered auto-apply). Pair with the **egress-IPv4 fix (P0)** and a **non-provisioner readiness gate**: `terraform apply` returns green on server *create* without waiting for cloud-init, so the post-merge bootstrap/cutover script (web-host-driven over the private net) must verify git + bare-repo root + hook are live on git-data **before** cutover (`hr-fresh-host-provisioning-reachable-from-terraform-apply`).
- Migration 114 = online Supabase migration via `web-platform-release.yml#migrate`.
- **Cutover** = a separate idempotent, capture-first, **ref-set-verifying** script run post-merge (highest-blast-radius; the volume is untouched until verification passes → rollback is "keep using the volume").

### Distinctness / drift safeguards
- Root is **prd-only**; dev is a separate Supabase project (`hr-dev-prd`).
- R2 backend has **no lock** (`use_lockfile=false`); the GHA concurrency group is the sole serializer — the new resources are pure **`+create`, `0 to destroy`** (`hcloud_server.web` + `hcloud_volume.workspaces` untouched; `hcloud_server_network.web` is an additive online attach). No `for_each` churn this phase (Phase 3).
- The git-data host is **distinct** from the web host and the loopback Inngest Redis — different node/volume; **public ingress deny-all**, transport on the private net only.

### Vendor-tier reality check
+1 Hetzner `cax11` (ARM) + 1 `hcloud_volume` (≥10 GB) + private network (free) + **egress IPv4 (~€0.50/mo — do not miss this line in `expenses.md`)**. **No new sub-processor / DPA** (self-host on Hetzner EU — the deciding reason). *Verify current Hetzner pricing at the provider page before the budget decision.*

## Observability

```yaml
liveness_signal:
  what: git-data reachability over the private net — a web-host cron probes git-data (git ls-remote / ssh) and pings a Better Stack HEARTBEAT (push) URL on success (terraform-architect P1 — Better Stack cannot PULL a deny-all-public-ingress host; absence-of-ping alerts)
  cadence: 60s
  alert_target: Better Stack Heartbeat monitor (web-host-driven)
  configured_in: apps/web-platform/infra/git-data.tf (betteruptime_monitor type=heartbeat) + the web-host probe cron + infra/sentry/*.tf
error_reporting:
  destination: Sentry (server) — new op slug worktree_lease (acquire/touch/release + fence-reject)
  fail_loud: true (mirror silent fallbacks via reportSilentFallback; cq-silent-fallback-must-mirror-to-sentry)
failure_modes:
  - {mode: lease acquire returns zero rows from ANOTHER host (lost), detection: worktree_lease op slug, alert_route: Sentry issue alert}
  - {mode: touch returns 0 mid-op (lease reclaimed) — host aborts the in-flight write + fails loud, detection: worktree_lease op slug, alert_route: Sentry}
  - {mode: fence rejects a push (gen<max OR missing lease-gen option — fail-closed), detection: pre-receive hook stderr -> push failure + worktree_lease op slug, alert_route: Sentry}
  - {mode: git-data unreachable over private net, detection: web-host probe fails -> Better Stack heartbeat absence, alert_route: Better Stack + Sentry}
  - {mode: cutover ref-set / fsck mismatch, detection: cutover script exit!=0 + for-each-ref + fsck diff, alert_route: script fails closed; operator sees verification output}
logs:
  where: pino -> existing server log pipeline; git-data host journald (cloud-init unit)
  retention: per existing retention (EU)
discoverability_test:
  command: "gh api /repos/<org>/<repo>/actions/workflows + Sentry issues?query=op:worktree_lease (no shell access required)"
  expected_output: "200 OK + worktree_lease op slug present in Sentry after the first lease acquire on dev"
```

## Architecture Decision (ADR/C4)

### ADR — no new ADR; Phase 2 instantiates ADR-068
ADR-068 (`status: adopting`, authored Phase 0) already fixes every Phase-2 decision
(§1 split, §2 lease, §3 fence, §6 isolation floor). Phase 2 **instantiates** it; it
does **not** make a new architectural decision. ADR-068's status flips
`adopting → accepted` at the **Phase-3 GA** PR (ADR-068 status line), **not** here —
the `replicas=1` invariant remains operationally in force.

### C4 views — no `.c4` edit (completeness mandate satisfied)
Read all three model files. The Phase-2 element + relationship are **already
modeled** (Phase 0): `gitDataStore` database (`model.c4:180`, desc "Shared bare git
repos (objects/refs) over private net; writer-side CAS fence — reject `gen<max`"),
`claude -> gitDataStore "Bare repo data; worktrees local"` (`model.c4:281`), and
`gitDataStore` is in the `view containers of platform` `include` block
(`views.c4:35`). **External-actor / external-system / data-store / access-relationship
enumeration for Phase 2:** the only new infra element is the git-data host =
`gitDataStore` (modeled); the private `hcloud_network` is infra topology, not a C4
container; no new external human actor or vendor (self-hosted, no sub-processor); the
worktree-on-NVMe split changes no C4 access relationship. **Conclusion: no `.c4`
edit.** (If `/work` nonetheless edits any `.c4`, run `bash scripts/regenerate-c4-model.sh`
+ `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.)

## Risks & Mitigations
- **Pre-check ≠ atomic fence (TOCTOU)** → writer-side CAS at the git-data host (2.3); fencing, not the heartbeat timeout, makes a stale/GC-paused holder's late write a no-op.
- **Defense ceilings (name them — learning `2026-05-05-defense-relaxation-must-name-new-ceiling`):** the **120s heartbeat timeout** governs *when reclaim is allowed*; the **monotonic-gen fence** governs *whether a stale write corrupts* (it cannot). Two distinct roles, two distinct mechanisms — neither substitutes for the other. Nothing pre-existing is relaxed (both are new).
- **Cutover loses refs / blank tree (#5240 regression)** → capture-first (#5542) + pre/post `git rev-list --all --count` equality + volume untouched until verify passes (rollback = keep the volume) + GitHub rehydration (#5546).
- **Foundations PR declaring a Phase-3 contract** → the fence is live-but-non-triggering at `replicas=1`; nothing consumes a rejection until a 2nd host; **no cluster-wide mount cred** baked in (per-`workspace_id` scoping is Phase 3, ADR-068 §6).
- **CASCADE vs the RESTRICT precedent** → justified (ephemeral lease, no lineage; CASCADE satisfies Art.17-reaches-erasure without blocking workspace deletion); data-integrity-guardian confirms; no WORM trigger on the new table.
- **Same-host self-lockout (spec-flow/data-integrity P0/P1)** → the acquire CASE (`OR host_id = excluded.host_id`, keep-gen on same host) + host-stable `host_id` + SIGTERM lease-release: a recreate-deploy or crash-restart re-acquires its own lease immediately, never the 120s lockout.
- **Reading the empty git-data store before cutover (mass #5240)** → read-source flag defaults to the volume; flips to git-data only after the verify gate passes (spec-flow P0-5); write-freeze for the cutover window (P0-4).
- **Local-only (un-pushed) refs lost on a dropped cutover ref** → GitHub rehydration covers pushed refs only; capture + ref-set verify is the safety net for local-only refs (spec-flow P1-I).
- **DEV Supabase drift poisons the 2.7 test** → precondition that DEV schema == main migration history (learning `2026-05-21-dev-supabase-drift…`).
- **`migration-rpc-grants` lazy-regex conflation** → full `revoke … from public` form on every function (learning `2026-05-29-…-invoker-before-definer`).
- **New user-content store outruns erasure (Art.17)** → Phase 2 is the first store of bare git data on a separate host; the cascade reaches the lease row but not the filesystem bare repo → task 2.6 wires the erasure-reach + AC7b (gdpr-gate fold-in). A store created without its erasure path is the recurring single-user-incident GDPR gap.
- **git-data host is a residual SPOF** vs "user never notices a crash" → accepted at the Phase-3 GA line with honest reconnect; #5723 (Garage) closes post-GA (OQ1, epic). Not a Phase-2 gate.

## Sharp Edges
- A `## User-Brand Impact` that is empty/`TBD` fails `deepen-plan` Phase 4.6 — this one is filled (threshold = single-user incident).
- `tsc` for `apps/web-platform` is `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — NOT `npm run -w …` (no root `workspaces`).
- New `*.integration.test.ts` must match `vitest.config.ts:44` `include: test/**/*.test.ts` — place under `test/`, not co-located.
- Verify **114** free at `/work` start with a command that also lists known migrations (empty grep = malformed command, not clean).
- The cutover script's region/markers: keep capture, rsync, and verify as **separate idempotent steps**; never re-read the empty destination as truth (#5542).

## Open Questions (carry to deepen-plan / per-step)
1. **PR split — COMMITTED (CPO + simplicity-reviewer converged; no longer an open question).** The bundle (migration + RLS + network.tf + git-data.tf + bootstrap + fence + 5-file app refactor + cutover + Art.17 erasure + the 2.7 test) is not safely reviewable as one unit. Recommended structure:
   - **PR A (now, near-zero blast radius):** migration 114 + `.down.sql` + RLS + the lease RPC client. Reversible; mirrors `acquire_conversation_slot`.
   - **PR A′ (now, independent):** the 2.7 integration test — it is unrelated to git-data/leases (it tests `readWorkspaceIdFromDb` binding memoization, #5338); bundled only by the operator's 2026-06-30 deferral decision. Ship as its own one-file PR (simplicity-reviewer item 4).
   - **PR B:** infra (network.tf, git-data.tf, bootstrap, egress fix, placeholder hook) + app-wiring **behind the volume-default read flag** + (the fence enforcement, IF kept in Phase 2 — see OQ5). No live data moves.
   - **PR C:** the cutover script + the read-source flip + the Art.17 erasure step (the store holds real data only after cutover) — the one irreversible step, behind an already-green, already-deployed B.
   The fence, if kept, rides B or its own PR — **never with the cutover.** Final gating mechanism = operator + plan-review.
2. **Fence storage/delivery** (sidecar vs `refs/fence/<wt>`; push-option vs receive env) — deepen-plan Phase 4.4 precedent-diff (novel pattern, no in-repo precedent).
3. **Exact app-refactor depth** for the worktree/bare split (how invasive in `workspace-resolver.ts`/`ensure-workspace-repo.ts`) — deepen-plan with the file:line anchors above.
4. Shared-git-data SPOF: Garage (#5723) vs GitHub-rehydration — carried from epic OQ1, GA-gated (Phase 3), not Phase 2.
5. **Fence + live-lease-wiring scope — OPERATOR DECISION (simplicity-reviewer challenge vs ADR-068 + operator scope).** The simplicity-reviewer argues the **fence enforcement** (pre-receive CAS + sidecar/flock + AC3) and the **live lease app-wiring** (acquire/touch/release in the write path, SIGTERM-release, ≤30s heartbeat, fail-loud-on-touch-0) **cannot reject/block anything at `replicas=1`** (one writer, gen never climbs), are the most novel/risky/untested-against-a-real-threat code, and could defer to Phase 3 where the 2nd writer makes them testable against a real threat — landing only the gen-on-the-wire plumbing (column + acquire RPC + push-option wrapper + placeholder hook) in Phase 2. **Counter (why the plan keeps them in Phase 2 by default):** ADR-068 §3 fixes the fence as a Phase-2 deliverable; `gitDataStore` ships Phase 2 with "writer-side CAS fence"; task 2.3 + the epic AC scope it here; the foundations philosophy is "build + synthetically-test the safety primitive before the 2nd host, so Phase 3 is just 'add host + prove rejection.'" This is a **strategy call the operator owns** (a plan corrects upstream *technical facts*, not upstream *strategy*). Default = keep in Phase 2 per ADR-068; operator may elect the defer.
