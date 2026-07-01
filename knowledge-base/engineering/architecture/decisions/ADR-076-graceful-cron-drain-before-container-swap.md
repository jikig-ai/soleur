# ADR-076: Graceful cron drain before container swap; isolated cron-worker deferred

- **Status:** Accepted
- **Date:** 2026-06-29
- **Deciders:** Jean (operator), CPO sign-off (single-user-incident threshold), CTO agent (binding mechanism ruling), deepen-plan review (CTO, platform-strategist, spec-flow-analyzer)
- **Relates to:** #5669 (this change), #5417 / #5420 / ADR-062 (memory-safety + restart/OOM attribution — the predecessor that resolved every OOM/crash harm but, by scope, never targeted deploy frequency), ADR-033 (cron `claude` spawned inside the web-platform container), ADR-030 (Inngest durable trigger layer), ADR-027 (single-replica invariant)

## Context

Every merge to `main` touching `apps/web-platform/**` runs
`web-platform-release.yml` → `ci-deploy.sh`, which canary-probes the new image
then **stops and removes the old prod container**
(`docker stop --time=12 soleur-web-platform`, `ci-deploy.sh`). That stop kills
any in-flight cron `claude` child — the `_cron-claude-eval-substrate.ts:706`
symptom (`spawn cwd … no longer exists`). ADR-062 / #5420 resolved every
OOM/crash restart but, by scope, could not reach the AC11/AC12 "Server startup"
≤1/day proxy because it never targeted **deploy frequency**: each redeploy can
still kill a long-running (up to ~70-min) Claude-eval cron that lands mid-flight.

A killed cron is not lost (`retries: 1` re-runs it on the new container), but it
is wasteful — a fresh clone, fresh agent, fresh Anthropic spend — and it is the
exact `:706` symptom. Survival of an in-flight cron across a redeploy is the
acceptance bar.

Two durable options were deferred in #5417's RCA:

1. **Graceful drain** — the deploy pauses *new* cron starts and waits for the
   in-flight `claude` child to finish before swapping the container.
2. **Isolated cron worker** — run the heavy crons in a separate, deploy-stable
   worker container so app redeploys never touch them.

## Decision

**Option 1 (graceful drain), implemented with a host-mounted deploy LEASE — not
native Inngest `pause`/`resume`.** Option 2 is **deferred** (re-eval criteria
below).

The drain lives host-side in `ci-deploy.sh` (the only place a multi-minute wait
can sit — the container's `SIGTERM` handler is hard-bounded to
`SHUTDOWN_TIMEOUT_MS = 8_000` < the 12s `docker stop`). After the canary is torn
down (memory-dwell fix, below) and before the old-prod stop, `ci-deploy.sh`:

1. **Writes a lease file** at `${CRON_WORKSPACE_ROOT}/.deploy-lease` (host
   `/mnt/data/workspaces/.deploy-lease` == container `/workspaces/.deploy-lease`,
   the same host-mounted volume both the old and new container see). The cron
   substrate (`setupEphemeralWorkspace`, the single pre-spawn choke point every
   heavy claude-eval cron funnels through) reads this lease at step entry; a
   FRESH lease → it defers (`DeployInProgressError`) before `mkdtemp`/clone, so
   the imminent stop cannot kill a *new* claude child. This closes the
   start-race (a new run launching claude into the about-to-die container while
   the loop drains the current one).
2. **Drains**: `while cron_in_flight; do …` waits for any live in-container
   `claude` child, bounded by `CRON_DRAIN_TIMEOUT` (default = the **MAX** of every
   per-function `MAX_TURN_DURATION_MS` = `cron-growth-audit` 70min/4200s; a test
   asserts `≥` that max). Detection is **pool-agnostic** (`docker exec … pgrep -f
   claude`) because claude-eval runs in `cron-platform` (limit:1) AND
   `agent-runtime` (limit:50) AND cc-soleur-go endpoints — an Inngest-pool-scoped
   query would miss agent-runtime children. `wait = max, not sum` (the lease
   stops new dispatch globally while the loop drains the in-flight ones).
3. **Clears the lease on swap success**; on failure the lease is left for the
   substrate's TTL fail-open backstop (see guardrails).

The deploy wall-clock is a **four-constant fail-closed invariant** raised in
lockstep to 4800s (≥ `CRON_DRAIN_TIMEOUT` + overhead): `ci-deploy-wrapper.sh`
`timeout … 4800s`, and `web-platform-release.yml` `STATUS_POLL_MAX_ATTEMPTS 960`
(×5s), `HEALTH_POLL_MAX_ATTEMPTS 480` (×10s), `IN_FLIGHT_CEILING_S 4800`. The
wrapper literal is a **fixed number** (not a `$((…))` expression), because the
wrapper `exec`s into `ci-deploy.sh` and an in-script constant is unset across the
exec boundary — a dynamic expression would evaluate to an empty/short value and
SIGKILL the deploy at ~10 min, worse than today. `ci-deploy-wrapper.test.sh`
Test 6 enforces wrapper == `IN_FLIGHT_CEILING_S` parity.

## Why lease over native `inngest pause`/`resume` (CTO binding ruling)

The plan's original primary mechanism was native `inngest pause`/`resume`. Its
load-bearing safety precondition — *pause stops new dispatch but does NOT abort
the in-flight `claude` child* (plan gate G1) — is **unverifiable pre-merge** in
an autonomous one-shot: there is no prod SSH (`hr-no-ssh-fallback-in-runbooks`),
and the only confirming probe would `inngest pause` production, freezing ALL
server-global event-driven functions for up to ~70 min — itself an unacceptable
production action. The only existing pause usage (`inngest-bootstrap.sh:85-94`)
documents *event-queue-persistence* semantics ("the in-memory queue drains to the
SQLite store before replacing the binary"), with zero evidence it shields a
running function step — ambiguous-to-negative on G1.

The lease wins on three load-bearing points:

1. **Verifiable.** The lease's equivalent claim ("a fresh lease at step entry
   early-returns before spawn") is proven by a vitest unit test
   (`test/server/cron-drain-lease.test.ts`), in-code, where G1 could not be.
2. **Smaller blast radius + fail-SAFE failure mode.** The lease gates ONLY the
   cron claude-eval substrate; pause is server-global. If the lease misbehaves,
   the worst case is a cron *skips one fire* (benign, self-correcting). If the
   pause precondition is wrong, pause *kills the in-flight child* — the exact
   `:706` incident this ADR exists to prevent. Pause's failure mode is the
   incident; the lease's is a no-op.
3. **Deletes the three highest-risk gaps outright.** Pause requires composing
   `resume` into the `ci-deploy.sh` EXIT (`:137`) + TERM/INT (`:171`) traps (G2 —
   a botched `trap … EXIT` clobbers deploy-state finalization under
   `set -euo pipefail`), a resume-if-paused wedge recovery for untrappable
   SIGKILL (G3), and resume-gated-on-swap-success (G4). The lease needs none:
   a TTL'd file with no resume verb, no trap surgery, no server-global wedge.
   The `ci-deploy.sh` traps at `:137`/`:171` are left untouched.

The one cost — a substrate code change shipping in the container image, plus a
`_cron-shared.ts` helper and a test — is cheap and buys verifiability.

## Alternatives Considered

| Option | Verdict | Why |
|---|---|---|
| **Graceful drain via host-mounted lease (this ADR)** | **Chosen** | Verifiable, cron-scoped blast radius, fail-safe failure mode; no topology change; ships in one PR; satisfies "crons survive a redeploy landing mid-flight" |
| Native Inngest `pause`/`resume` in `ci-deploy.sh` | **Rejected** | Load-bearing safety precondition (pause does not abort the in-flight child, gate G1) is unverifiable pre-merge in an autonomous local one-shot without an unacceptable production-freeze probe; server-global blast radius; the trap-composition (G2), wedge-recovery (G3), and resume-gating (G4) complexity the plan itself flags as its highest-risk gaps. At a single-user/brand-survival threshold, an unprovable safeguard with a fail-dangerous failure mode is inadmissible |
| pause-with-lease belt-and-suspenders | **Rejected** | Strictly worse than lease-alone: imports the entire pause cost surface (server-global freeze, G2/G3/G4) on top of the lease, for redundancy on a start-race the lease already closes deterministically. Redundancy only pays when the primary is unproven — here the lease is the *more* proven of the two |
| **Option 2: isolated cron-worker container** | **Deferred** (re-eval criteria + AC9 tracking issue) | Strongest fix but the 8GB cx33 deploy-window peak is already ~6.9GB (ADR-062) → needs a host upsize (recurring cost); duplicates the entire Claude-Code runtime surface (sandbox overlay, containment hook, ephemeral-workspace provisioning, ADR-052 egress allowlist, Doppler/systemd patterns); needs Inngest multi-app registration; the #4017/#4079 five-bug cascade shows multi-component Inngest deploys are high-risk. Wrong scope for a one-shot |
| Drain inside the Node SIGTERM handler | Rejected | `server/index.ts` is bound to `SHUTDOWN_TIMEOUT_MS = 8_000` < `docker stop --time=12`; cannot wait tens of minutes |
| Unbounded drain | Rejected | Deploy starvation; bounded by the cron's own ceiling instead |
| Do nothing / rely on #5420 | Rejected | #5420 fixed OOM/crash restarts but not deploy-driven kills — the explicit residual #5669 targets |

## Trade-offs named (what the four-constant bump loosens)

- The raised `IN_FLIGHT_CEILING_S` (1800→4800s) also gates the **pre-rerun
  stale-lock probe** in `web-platform-release.yml`, so a wedged prior deploy now
  reads as "alive" for ~80 min and hung-deploy failure surfaces ~80 min slower.
- `cancel-in-progress: false` on the deploy job serializes queued deploys behind
  a max-length drain (a wedged drain holds the lock for the whole wall-clock).
- A deploy landing mid-cron now incurs an up-to-~70-min drain wait on the
  prod-swap path (the in-flight cron's remaining budget). This is the cost of
  survival; it is loud (`cron_drain_wait_secs` in the deploy-status webhook) and
  bounded.

## Memory-dwell ordering (platform-strategist)

The drain runs **after** the canary is torn down, not with it resident: draining
with canary (1536m) + old-prod (4096m) + cron + ~1.3GB ≈ ~6.9GB sustained for up
to ~70 min on the 8GB host risks an OOM that kills the very cron being protected.
Tearing the canary down first holds ≈ 5.4GB during the drain.

## Re-eval criteria for Option 2 (any one triggers a revisit)

(a) a 2nd hosted founder is onboarded (cron cohort grows; starvation/blast-radius
risk rises); (b) deploys empirically time out (`cron_drain_timed_out`) more than
~1×/week; (c) the host is upsized to ≥16 GB for unrelated reasons (the memory
blocker dissolves); (d) any claude-spawn pool's effective concurrency makes the
drain wait Σ rather than max (e.g. `cron-platform` limit raised, or
`agent-runtime` heavily used during deploy windows); (e) sustained OOM-kills are
observed during a drain window (argues for Option 2 independent of host size).

## Observability (no-SSH)

`cat-deploy-state.sh` adds `cron_drain_wait_secs` (int) + `cron_drain_timed_out`
(bool) to the `/hooks/deploy-status` webhook (HMAC + CF-Access gated), with safe
sentinels (`-1` / `false`) so a deploy that never reached the drain is
distinguishable from a real 0-wait drain. The timeout path — the only path that
kills a cron — emits a Sentry event (`feature=ci-deploy`,
`op=cron-drain-timeout`) and a journald WARN (→ Better Stack). The substrate's
lease-deferral mirrors to Sentry (`reportSilentFallback`, `op=deploy-lease-fresh`)
so "why did cron X skip during the 14:03 deploy?" is answerable with no SSH.

## C4 impact

**None** — enumeration cited. No new external actor, vendor, container, data
store, or access relationship. The existing `hetzner` Compute, `inngest` Server,
and `api` containers are unchanged; the drain is a behavior of the deploy script
that runs *between* container instances, below C4 component granularity. Option 2
*would* have added a `cron-worker` container element + a second `serve()` edge —
that diagram change is deferred with this ADR.

## Consequences

- Survival of an in-flight cron across a redeploy is now a deploy-time invariant
  (modulo `CRON_DRAIN_TIMEOUT`).
- The deploy wall-clock rises to a worst-case ~80 min when a deploy lands mid-cron
  (common case unchanged: zero-wait drain, immediate swap).
- A crashed/SIGKILLed deploy can leave a stale lease; the substrate's TTL
  fail-open (`DEPLOY_LEASE_MAX_AGE_MS`, default 90 min > drain + overhead) ignores
  it, so a crashed deploy never darks crons indefinitely.
