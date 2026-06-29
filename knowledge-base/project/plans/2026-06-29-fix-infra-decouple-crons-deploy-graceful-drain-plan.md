<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
Phase 2.8 reviewed: the only infra change is a host-side drain gate added to the
existing deploy orchestrator apps/web-platform/infra/ci-deploy.sh (the established
IaC deploy mechanism) plus a code-default, env-overridable named constant
CRON_DRAIN_TIMEOUT (the ADR-062 PROD_MEMORY_CAP precedent — no Doppler secret, no
new Terraform resource, no new server/vendor/systemd unit). No manual operator SSH
step is prescribed. See ## Infrastructure (IaC) below.
-->
---
title: "fix(infra): decouple heavy Claude-eval crons from the app deploy lifecycle — graceful cron drain before container swap (Option 1), with isolated-worker (Option 2) deferred"
issue: 5669
type: bug
classification: infra + observability
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
created: 2026-06-29
branch: feat-one-shot-5669-decouple-crons-deploy-lifecycle
---

# fix(infra): decouple heavy Claude-eval crons from the app deploy lifecycle 🐛

> Fixes #5669. Follow-up to #5417 (memory-safety + crash-attribution, merged as #5420 / ADR-062). #5420 resolved every OOM/crash harm but, by scope, never targeted **deploy frequency**, so it structurally cannot reach the ≤1/day "Server startup" proxy. Residual: each app redeploy can still kill a long-running (up to ~70-min) Claude-eval cron that lands mid-flight (`spawn cwd /tmp/soleur-cron-* no longer exists`). This plan closes that residual by **graceful drain** — the deploy pauses new dispatch and waits for the in-flight cron to finish before swapping the container.

## Overview

The Inngest cron functions (`apps/web-platform/server/inngest/functions/cron-*.ts`) invoke `claude-code` via `child_process.spawn` **inside the `soleur-web-platform` container's Node process** (ADR-033). Every merge to `main` touching `apps/web-platform/**` runs `web-platform-release.yml` → `ci-deploy.sh`, which canary-probes the new image on port 3001 then **stops and removes the old prod container** (`docker stop --time=12 soleur-web-platform` at `apps/web-platform/infra/ci-deploy.sh:721`). That stop kills any in-flight cron `claude` child — the `_cron-claude-eval-substrate.ts:706` symptom (`spawn cwd … no longer exists`).

Two durable options were deferred in #5417's RCA:

1. **Graceful drain (this PR).** Before the container stop, `ci-deploy.sh` pauses new Inngest dispatch and polls for an in-flight claude child, waiting (bounded by the longest per-function ceiling) for it to finish before stopping. **Cheaper interim; satisfies the acceptance limb "crons survive a redeploy landing mid-flight."**
2. **Isolated cron worker (deferred).** Run the heavy crons in a separate, deploy-stable worker container so app redeploys never touch them. Strongest fix, largest change — blocked from a one-shot by the 8GB host budget and a large duplicated-runtime surface (see Architecture Decision + Alternatives).

**Why drain is bounded — corrected by domain review (the original "limit:1 ⇒ exactly one cron, 60-min ceiling" proof was factually wrong on BOTH terms; see Domain Review):**

- **The ceiling is per-function, not a single 60.** `MAX_TURN_DURATION_MS` is defined per function and spans **15→70 min** (`cron-growth-audit.ts:52` = **70 min / 4200s** — the max; `cron-daily-triage.ts:153` = 60; `cron-content-generator.ts:52` = 55; many = 50; `cron-follow-through-monitor.ts:249` = 15; `cfo-on-payment-failed.ts:74` reads it from env). `CRON_DRAIN_TIMEOUT` default MUST be **`MAX()` of all per-function ceilings = 4200s** (with a test asserting `CRON_DRAIN_TIMEOUT ≥ max ceiling`), NOT 3600 — else a 70-min growth-audit run is still killed by timeout.
- **More than one claude child can be in flight.** The `cron-platform` pool is `limit:1`, but **claude-eval also runs OUTSIDE it**: `github-on-event.ts:267` + `cfo-on-payment-failed.ts:258` spawn `claude` under `{scope:"account", key:"agent-runtime", limit:50}`; the container also runs cc-soleur-go agent endpoints. So the correct invariant is **"the drain waits for ANY live `claude` child, each bounded by its own ceiling"** — wait = **max**, not sum, because `inngest pause` stops *new* dispatch globally while the loop drains the in-flight ones. This makes **detection necessarily pool-agnostic** (see Phase 0 / Sharp Edges) — an Inngest runs-API query scoped to `cron-platform` would miss agent-runtime children and let `docker stop` kill them.

**The deploy wall-clock is a FOUR-CONSTANT fail-closed invariant, not a single knob.** `web-platform-release.yml` runtime-asserts `STATUS_WINDOW (360×5s) == HEALTH_WINDOW (180×10s) == IN_FLIGHT_CEILING_S == ci-deploy-wrapper.sh timeout (1800s)` and **blocks the deploy on drift**. Raising only the wrapper fails-closed the next deploy. All four must move in lockstep to a **fixed literal** (≥ `CRON_DRAIN_TIMEOUT` + deploy-overhead; with 4200s drain ⇒ literal ≈ **4800s**, worst-case deploy ~80 min). Two further traps: (a) `ci-deploy-wrapper.sh` **execs into** `ci-deploy.sh`, so `CRON_DRAIN_TIMEOUT` (defined inside ci-deploy.sh) is **unset** in the wrapper scope — a `$(( CRON_DRAIN_TIMEOUT + 600 ))` wrapper expression evaluates to `600` → SIGKILL at 10 min, worse than today; the value must be a **shared sourced constant** and the AC must assert the wrapper's *resolved number*. (b) `IN_FLIGHT_CEILING_S` has a *second* consumer (pre-rerun stale-lock probe) — raising it slows hung-deploy failure detection and treats a wedged prior deploy as alive for ~80 min; **name this trade-off in ADR-068**.

**A killed cron is not lost, but it is wasteful.** Crons run with `retries: 1`; an interrupted `claude-eval` step re-runs in full on the new container (fresh clone, fresh agent, fresh Anthropic spend, fresh budget). The drain avoids that waste and the `:706` symptom — survival, not just eventual completion, is the acceptance bar.

**Why the drain lives in `ci-deploy.sh`, not the Node SIGTERM handler:** the container's `SIGTERM` handler (`server/index.ts:243`) is deliberately bounded to `SHUTDOWN_TIMEOUT_MS = 8_000` (< the 12s `docker stop --time`); it cannot wait tens of minutes. The host-side deploy orchestrator is the only place a multi-minute drain can sit without the kernel SIGKILLing it. Detection is host-local (no SSH): `ci-deploy.sh` already runs on the Hetzner host.

This is an **infra + observability change** routed through the existing IaC deploy mechanism (`ci-deploy.sh` + its `ci-deploy.test.sh` harness, the `cat-deploy-state.sh` no-SSH webhook, `logger`/journald, Sentry). No application data model changes.

## Premise Validation (Phase 0.6)

- **#5669** — `gh issue view 5669`: **OPEN**, no `closedByPullRequestsReferences`. Premise holds (the residual is real and unaddressed).
- **#5417 / #5420 / ADR-062** — read in full. #5420 shipped the cgroup memory cap + container-restart-monitor + crash attribution; ADR-062 `## Context` explicitly records "Each restart … kills any in-flight Claude-eval cron (≤55 min)" as an acknowledged, **un-fixed-by-scope** residual. This plan is the deferred follow-up, not a re-do.
- **ADR-033** (spawn model), **ADR-030** (Inngest durable trigger layer) — read; the spawn-inside-`step.run` + per-step `AbortSignal` + `cron-platform` concurrency invariants confirmed against current code. **Domain review corrected two of my initial reads:** the ceiling is per-function (15→70 min), not a single 60; and claude-eval also runs in the `agent-runtime` pool (limit:50), so it is NOT true that ≤1 claude runs at once. Both corrections are folded into the Overview + carried in Domain Review.
- **Mechanism vs ADR corpus** — grepped the decisions corpus for `drain`/`graceful`/`cron-worker`/`deploy`: no existing ADR decides cron-survival-across-deploy. The drain mechanism is **not** in any rejected-alternatives table. Option 2 (isolated worker) is named only as a deferred RCA recommendation, not a rejected alternative. No stale premise.
- **Capability self-checks** — stop sequence at `:721`, SIGTERM 8s bound at `:243`, the `cron-platform` `limit:1` declaration, workspace root, `cat-deploy-state.sh` fields, the wrapper `1800s` cap, and the four-constant assertion were confirmed by direct file read and domain-agent verification (`hr-verify-repo-capability-claim-before-assert`). The per-function-ceiling and agent-runtime-pool facts were surfaced by the CTO review against the function files.

## User-Brand Impact

**If this lands broken, the user experiences:** their scheduled Claude-eval crons (content-generator, follow-through-monitor, bug-fixer, community-monitor, roadmap/agent-native/legal audits) die mid-run on a deploy and never produce their output (a generated article, a triaged issue, a community digest) — the founder sees nothing was done and cannot tell why. Three NEW, worse failure modes the design must foreclose: (1) a **drain that silently times out** and stops the container anyway (reproduces today's failure — must page); (2) a **wedged-paused Inngest** left by an untrappable-SIGKILL/crashed deploy → **ALL** event-driven Inngest functions (not just crons — `inngest pause` is server-global) go dark until the next deploy's resume-if-paused reconcile (G3); (3) the drain's **~50–70-min server-global async freeze** on every deploy that lands mid-cron — a materially larger blast radius than "one cron," to be weighed against the survival gain (G12). All three must be loud (Sentry + `inngest_paused`/`cron_drain_timed_out` deploy-state fields), never silent.

**If this leaks, the user's workflow is exposed via:** the `/hooks/deploy-status` webhook gains a `cron_drain_wait_secs` / `cron_drain_timed_out` field. The webhook is HMAC-SHA256 + CF-Access gated and already redacts secrets (`cat-deploy-state.sh`). The new fields are integers/booleans carrying **no PII** (process-liveness only). No personal data is read, moved, or stored by the drain.

**Brand-survival threshold:** single-user incident. A single founder's cron cohort going dark is the brand-survival blast radius — the CaaS thesis is "the agents do the multi-domain work unattended"; if the deploy kills them, the thesis fails for that user. `requires_cpo_signoff: true`. `user-impact-reviewer` runs at review-time. CPO sign-off required at plan time before `/work` begins — invoke CPO if not covered by Phase 2.5 carry-forward.

## Research Reconciliation — Spec vs. Codebase

| Issue / prompt claim | Codebase reality | Plan response |
|---|---|---|
| Cron cwd is `/tmp/soleur-cron-*` | `mkdtemp(join(resolveCronWorkspaceRoot(), \`soleur-${cronName}-\`))` (`_cron-claude-eval-substrate.ts:561`); root = `CRON_WORKSPACE_ROOT` (prod `/workspaces` → host `/mnt/data` mount) else `tmpdir()`. Naming is `soleur-<cronName>-…`, not `soleur-cron-…`; the dir may be on a host volume (survives) while the **process** dies with the container | Drain targets the in-flight **process** (the real failure is the killed `claude` child, not a vanished dir). Detection is process-liveness, not dir-presence |
| "≤55-min" cron | `MAX_TURN_DURATION_MS` is **per-function**, 15→70 min (`cron-growth-audit.ts:52`=4200s max; daily-triage=60; content-gen=55; follow-through=15; cfo reads env) | Drain default = `MAX()` = **4200s**, with a test asserting `≥ max ceiling` — NOT a single 60 |
| Each redeploy can kill a long-running cron | Confirmed: `docker stop --time=12 soleur-web-platform` (`ci-deploy.sh:721`) is the sole forceful-kill point; SIGTERM handler (`:243`, 8s) drains HTTP/cc-go but **not** Inngest crons; the whole script is wrapped in `timeout 1800s` (`ci-deploy-wrapper.sh:15`) which itself caps the drain | Drain gate AFTER canary teardown, before `:721`; raise the four-constant wall-clock invariant |
| Crons run "concurrently" (ADR-062 wording) / "limit:1 ⇒ one cron" | `cron-platform` is `limit:1`, BUT claude-eval ALSO runs in `agent-runtime` (limit:50, `github-on-event.ts:267`/`cfo-on-payment-failed.ts:258`) + cc-go endpoints → **>1 claude child possible** | Detection must be **pool-agnostic**; safety = "drain waits for ANY live claude child, each bounded by its own ceiling; wait=max not sum because pause stops new dispatch" |

## Architecture Decision (ADR/C4)

### ADR

**Create ADR-068 — "Graceful cron drain before container swap; isolated cron-worker deferred."** This is an in-scope task of THIS plan (not a follow-up). It records:

- **Decision:** the deploy orchestrator (`ci-deploy.sh`) pauses new Inngest dispatch and drains any in-flight claude child (across all pools) before stopping the old prod container, bounded by `CRON_DRAIN_TIMEOUT` (default = the MAX per-function `maxTurnDurationMs` ceiling, 4200s). Survival of an in-flight cron across a redeploy is now a deploy-time invariant (modulo the timeout). The deploy wall-clock invariant (wrapper + 3 release-workflow window constants) rises in lockstep to accommodate the drain.
- **Alternatives Considered:** Option 2 (isolated cron-worker container) — **deferred**, re-eval criteria below. Drain-in-SIGTERM-handler — **rejected** (8s bound < ceiling). Unbounded drain — **rejected** (deploy starvation; bounded by the max per-function ceiling instead). Detection scoped to `cron-platform` only — **rejected** (misses agent-runtime claude children).
- **Trade-offs named (the four-constant bump loosens):** the raised `IN_FLIGHT_CEILING_S` makes hung-deploy failure surface ~80 min slower and treats a wedged prior deploy as alive for ~80 min; the `cancel-in-progress:false` lock serializes queued deploys behind a max-length drain; `inngest pause` is server-global, so a deploy landing mid-cron freezes ALL event-driven Inngest functions for the drain duration.
- **Re-eval criteria for Option 2** (any one triggers a revisit): (a) a 2nd hosted founder onboarded (cron cohort grows; starvation/blast-radius risk rises); (b) deploys empirically timed-out (`cron_drain_timed_out`) more than ~1×/week; (c) host upsized to ≥16 GB for unrelated reasons (the memory blocker dissolves); (d) **any claude-spawn pool's effective concurrency makes the drain wait Σ rather than max** (e.g. `cron-platform` limit raised, or `agent-runtime` heavily used during deploy windows); (e) **sustained OOM-kills observed during a drain window** — argues for Option 2 independent of host size.
- **Status:** accepted (drain is fully shipped in this PR; nothing soak-gated).

### C4 views

**No C4 impact — enumeration cited (read `model.c4` + `views.c4` + `spec.c4`, not a keyword grep):**

- **External human actors:** none new. The drain changes deploy *timing*, not who interacts with the system.
- **External systems / vendors:** none new. Anthropic, GitHub, Sentry, Inngest, Supabase, Doppler are all already modeled; the drain adds no edge to any.
- **Containers / data stores:** **none new** — this is precisely why Option 1 is chosen over Option 2. The existing `hetzner` Compute container, the `inngest` Inngest Server container, and the `api` container (`api -> inngest "Sends events; serves functions"`, `model.c4:241`) are unchanged. Option 2 *would* have added a `cron-worker` container element + a second `serve()` edge — that diagram change is deferred with the ADR.
- **Access relationships:** none change. The `api -> inngest` serve edge and `hetzner -> claude "Hosts"` edge are untouched; the drain is a behavior of the deploy script that runs *between* container instances, below C4 component granularity.

A "no C4 impact" conclusion is therefore supported by the actor/system/relationship enumeration above, per the Phase 2.10 completeness mandate. (No `.c4` edit; consequently the c4-render/c4-code-syntax tests are not exercised by this PR.)

## Implementation Phases

> Phase order is dependency-directed: the env-constant + detection helper land before the drain gate that consumes them; the lease guard lands before the substrate check that reads it; observability/tests land with the code that emits the signal.

### Phase 0 — Preconditions (verify, do not assume — resolve the Domain-Review gap checklist)

1. Read the stop sequence in `ci-deploy.sh` (`docker stop --time=12 soleur-web-platform` → `docker rm` → ADR-027 single-replica guard → `docker run`) AND locate exactly where the **canary is torn down** in the `:744–763` swap — the drain must sit AFTER canary teardown (platform-strategist memory-dwell fix).
2. Read the existing trap topology: EXIT (`:137`, deploy-state finalize + secrets cleanup), `TERM INT` (`:171`), ERR (`:176`), and `set -euo pipefail` (`:2`). The resume action MUST compose into these, never a bare `trap … EXIT` (G2).
3. **Run `inngest pause` against a LIVE in-flight cron** and observe the child (G1): confirm it (a) stops NEW dispatch, (b) does NOT abort/cut the running child, (c) gates **event-driven** invokes too (manual `/api/internal/trigger-cron`, `agent-runtime` events — G7), not just scheduled. `inngest-bootstrap.sh:9-10` calls pause "drains in-flight events" — this is evidence AGAINST assumption (b); the probe decides whether `pause`/`resume` is viable or the lease fallback is needed.
4. **Pin the detection signal by RUNNING it against a live cron (G8/G16).** Detection MUST be **pool-agnostic** — claude-eval runs both in `cron-platform` (limit:1) AND `agent-runtime` (limit:50, `github-on-event.ts:267`/`cfo-on-payment-failed.ts:258`) AND cc-go endpoints:
   - (a) `docker exec soleur-web-platform pgrep -f claude` — pool-agnostic, but **false-positives** on any in-container claude (cc-go/agent-runtime) and **false-negatives** if the bin path differs from the grep. Verify the actual spawned argv before trusting the pattern.
   - (b) Inngest `/v0/gql` `{ runs(status:Running) }` scoped to the cron+agent-runtime function IDs.
   Either way: give the probe its own `timeout`/`curl --max-time` (G5), and add a positive-detection probe (not just mocked tests).
5. Confirm `CRON_WORKSPACE_ROOT` prod value (lease-fallback path, if needed).
6. Enumerate every per-function `MAX_TURN_DURATION_MS` (`grep -rn MAX_TURN_DURATION_MS server/inngest/functions/`) to compute `MAX()` = the drain default (currently 4200s, `cron-growth-audit.ts:52`).

### Phase 1 — `CRON_DRAIN_TIMEOUT` (shared constant) + detection helper (RED→GREEN in `ci-deploy.test.sh`)

- Define `CRON_DRAIN_TIMEOUT` (default = **`MAX()` of all per-function `MAX_TURN_DURATION_MS` = 4200s**, not 3600) and `CRON_DRAIN_POLL` (default 10s) in a **shared sourced location** readable by BOTH `ci-deploy.sh` AND `ci-deploy-wrapper.sh` (the wrapper execs into ci-deploy.sh, so an in-script constant is invisible to the wrapper — P1-wrapper). A test asserts `CRON_DRAIN_TIMEOUT ≥ max per-function ceiling`. Plain constants, not Doppler secrets.
- `cron_in_flight()` wraps the Phase-0 signal (with internal `timeout`), returns 0 when any claude child is live; side-effect-free + mockable.

### Phase 2 — Close the start-race with native Inngest `pause`/`resume` (RED→GREEN)

- **Problem:** when an in-flight claude child finishes, a queued/event-driven run could be dispatched into the *old* container right as the deploy stops it — re-creating the kill. `pause` (Phase 0 G1) blocks new dispatch globally so the slot can't refill mid-drain.
- **Primary fix — native `pause`/`resume`** (`inngest-bootstrap.sh:88-95,408-421`), used today for in-place upgrades. **Crash-safety + correctness requirements (carried gaps):** compose `inngest_resume` into the existing EXIT handler + `TERM INT` (G2); `|| true`-guard `pause` under `set -e` (G6); resume = explicit exit-code check + bounded `--max-time` retry + loud alert, NOT best-effort `|| true` like `:421` (G4); sequence resume AFTER new-container Inngest function-sync, not just health (G11), and **only on swap success** (G14); recover an untrappable-SIGKILL wedge via an idempotent "resume-if-paused at deploy entry" reconcile in `ci-deploy.sh` (next deploy un-wedges — G3); `cat-deploy-state.sh` derives `inngest_paused` by querying Inngest, not self-report (G17).
- **`pause` is server-GLOBAL** — it freezes ALL event-driven Inngest functions for the drain duration (up to ~70 min), not just `cron-platform`. Model this blast radius in User-Brand Impact (G12).
- **Fallback (if Phase-0 G1 finds `pause` unsuitable):** host-visible **deploy-lease** file (`${CRON_WORKSPACE_ROOT}/.deploy-lease`, on the `/mnt/data` mount) checked at the substrate `claude-eval` step entry with a `LEASE_MAX_AGE` TTL (> max ceiling + slack); pino-logged early-return (NOT journald PRIORITY — learning `2026-06-02-docker-journald-driver-maps-stdout-to-priority-6…`).

### Phase 3 — Wall-clock as a FOUR-CONSTANT lockstep, then the drain gate (RED→GREEN)

**3a — raise the deploy wall-clock as a four-constant lockstep (do FIRST).** `web-platform-release.yml` runtime-asserts `STATUS_WINDOW (360×5s) == HEALTH_WINDOW (180×10s) == IN_FLIGHT_CEILING_S == ci-deploy-wrapper.sh timeout (1800s)` and blocks the deploy on drift (~`web-platform-release.yml:312–357`). Raise **all four** to a **fixed literal** (≥ `CRON_DRAIN_TIMEOUT` + overhead; 4200s drain ⇒ **4800s**, worst-case deploy ~80 min). Do NOT use a dynamic `$(( … ))` wrapper value — it (i) can't satisfy the static-equality assertion against the three literals and (ii) reads `CRON_DRAIN_TIMEOUT` as empty across the `exec` boundary → 600s → SIGKILL at 10 min, worse than today (P1-wrapper). Name in ADR-068 the trade-offs the bump loosens: `IN_FLIGHT_CEILING_S`'s second consumer (pre-rerun stale-lock probe) now treats a wedged deploy as alive for ~80 min, and hung-deploy failure surfaces ~80 min slower; and the `cancel-in-progress:false` lock (`:139`) serializes queued deploys behind a max-length drain (G18).

**3b — drain gate, placed AFTER canary teardown, BEFORE old-prod stop (memory-dwell fix).** Do NOT drain with the canary still resident (canary 1536m + old-prod 4096m + cron + ~1.3GB ≈ 6.9GB sustained ~50–70 min on 8GB → OOM risk that kills the very cron being protected). Tear the canary down once it has validated the image, THEN drain (resident ≈ 5.4GB), THEN stop old prod + run new prod:

```bash
# … canary probes pass (CANARY_HEALTHY==true) …
docker stop soleur-web-platform-canary; docker rm soleur-web-platform-canary   # free 1536m BEFORE draining
# Cron drain gate (#5669 / ADR-068): never stop old prod while a claude child is in
# flight. Bounded by CRON_DRAIN_TIMEOUT (= MAX per-function maxTurnDurationMs, 4200s).
inngest_pause || true                 # stop NEW dispatch (server-global; G1/G6)
add_exit_action inngest_resume        # COMPOSE into existing EXIT handler (:137) — NOT `trap … EXIT` (G2)
drain_start=$(date +%s)
while cron_in_flight; do               # cron_in_flight has its own probe timeout (G5)
  waited=$(( $(date +%s) - drain_start ))
  if (( waited >= CRON_DRAIN_TIMEOUT )); then
    logger -t "$LOG_TAG" "CRON_DRAIN: timeout ${waited}s — claude still in flight; stopping (killed, retries:1)"
    report_cron_drain_timeout "$waited" || true   # loud: Sentry + deploy-state field
    break
  fi
  sleep "$CRON_DRAIN_POLL"
done
CRON_DRAIN_WAIT_SECS=$(( $(date +%s) - drain_start ))
# … existing docker stop --time=12 soleur-web-platform / rm / ADR-027 guard / docker run new prod …
# inngest_resume fires via the composed EXIT action — AFTER new-prod health + function-sync,
# only on swap success (G14); on swap FAILURE the wedge auto-recovers via resume-if-paused-at-entry (G3).
```

- Resume must be fast + idempotent (hard `--max-time`); SIGKILL can't be trapped, so the `inngest_paused` field + next-deploy resume-if-paused reconcile are the PRIMARY recovery, the trap secondary (CTO/G3).
- Drain runs on the **prod-swap branch only**; never on a canary-only early exit (G10).
- `CRON_DRAIN_TIMEOUT` = MAX of all per-function ceilings (Phase 0 step 6) — do NOT hardcode 60.

### Phase 4 — Observability (no-SSH) + crash-safety

- `cat-deploy-state.sh`: add `cron_drain_wait_secs` (int) and `cron_drain_timed_out` (bool) to the webhook JSON (alongside the existing `restart_count`/`oom_killed`), with safe sentinels (`-1` / `false`) so a deploy that never reached the drain is distinguishable from a 0-wait drain.
- `report_cron_drain_timeout`: emit a Sentry event (`event_type=cron-drain-timeout`, `feature=ci-deploy`) — the only path that kills a cron, so it must page. Reuse the existing `ci-deploy` Sentry-emit shape if one exists; else mirror `container-restart-monitor.sh`'s host-side Sentry POST.
- This change introduces no new `process.on` handler (ADR-062 already installs crash handlers in `server/crash-handlers.ts`).

### Phase 5 — Tests

- `apps/web-platform/infra/ci-deploy.test.sh` (bash harness, mocked `docker`/`curl`/`date`/`inngest`): (T1) cron-in-flight → drain loops then stops once `cron_in_flight` non-zero; (T2) timeout past `CRON_DRAIN_TIMEOUT` → break, `cron_drain_timed_out=1`, Sentry-emit once; (T3) no cron → zero wait, immediate stop; (T4) `pause` before drain + `resume` via the composed EXIT handler on the happy path AND on an injected early-exit (no wedged-paused) — and the existing deploy-state finalization STILL runs (G2 no-clobber); (T5) resume-if-paused-at-entry reconcile un-wedges a pre-paused Inngest (G3); (T6) canary torn down BEFORE the drain loop (G10 + memory-dwell); (T7) `cron_in_flight` probe with a hung mock → its own timeout fires, loop still bounded (G5); (T8) `pause`/`report_*` returning non-zero does not abort the deploy under `set -e` (G6); (T9) `CRON_DRAIN_TIMEOUT ≥ max per-function ceiling` assertion.
- `apps/web-platform/test/server/…` (vitest, lease-fallback only): substrate `claude-eval` early-returns on fresh lease, proceeds on absent/stale. Place under `test/server/` (vitest `include:` collects `test/**/*.test.ts`; co-located `server/**` is NOT collected).
- `apps/web-platform/infra/cat-deploy-state.test.sh`: the three new fields appear with correct types + safe sentinels; `inngest_paused` reflects a queried (not self-reported) state.

## Files to Edit

- **Shared constant source** (new or existing sourced file readable by both `ci-deploy.sh` and `ci-deploy-wrapper.sh`) — `CRON_DRAIN_TIMEOUT` (4200), `CRON_DRAIN_POLL` (10), and the pinned `DEPLOY_WALL_CLOCK` literal (4800). The wrapper execs into ci-deploy.sh, so an in-script constant is invisible to it (P1-wrapper).
- `apps/web-platform/infra/ci-deploy-wrapper.sh` — change `timeout … 1800s` → the pinned literal (4800), sourced from the shared file. **Load-bearing — a dynamic/empty value SIGKILLs at 10 min.**
- `apps/web-platform/infra/ci-deploy.sh` — source the shared constants, `cron_in_flight()` (Phase-0 signal, own probe timeout), `inngest_pause`/`inngest_resume` helpers, `add_exit_action`/composed EXIT+TERM/INT handler (G2), resume-if-paused-at-entry reconcile (G3), `report_cron_drain_timeout`, the drain gate AFTER canary teardown / before the prod stop.
- `apps/web-platform/infra/ci-deploy.test.sh` — T1–T9 (see Phase 5).
- `apps/web-platform/infra/cat-deploy-state.sh` — `cron_drain_wait_secs` (int) + `cron_drain_timed_out` (bool) + `inngest_paused` (bool, derived by querying Inngest — G17) fields, safe sentinels.
- `apps/web-platform/infra/cat-deploy-state.test.sh` — assert the new fields + types.
- `.github/workflows/web-platform-release.yml` — raise the THREE window constants (`STATUS_WINDOW`/`HEALTH_WINDOW`/`IN_FLIGHT_CEILING_S`) in lockstep with the wrapper literal (the four-way equality assertion blocks the deploy otherwise — Phase 3a).
- `apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts` — **only if the lease fallback is chosen** over `pause`/`resume`: lease check + pino early-return at `claude-eval` step entry. (No substrate change if `pause`/`resume` is used.)
- `apps/web-platform/server/inngest/functions/_cron-shared.ts` — **lease-fallback only**: lease path/TTL helper (single source of truth), mirroring `resolveCronWorkspaceRoot`.
- `apps/web-platform/test/server/<cron-drain-lease>.test.ts` — **lease-fallback only**: substrate early-return test (path satisfies the vitest `test/**/*.test.ts` `include:` glob — NOT co-located under `server/**`, which vitest does not collect).

## Files to Create

- `knowledge-base/engineering/architecture/decisions/ADR-068-graceful-cron-drain-before-container-swap.md` — new ADR (via `/soleur:architecture`).
- The lease-fallback vitest file (above), only if the lease path is chosen.

## Open Code-Review Overlap

Ran `gh issue list --label code-review --state open` (200) and `jq --arg path` over each planned file. One match:

- **#3220** (`ci: postmerge verification of trigger-bearing migrations in prd`) — matched on the `web-platform-release.yml` substring only. **Disposition: Acknowledge.** Different concern (migration-trigger postmerge verification); this plan touches `web-platform-release.yml` only to extend the deploy-poll window for the longer max-drain deploy, not the migration-verify job. The scope-out remains open.

No matches for `ci-deploy.sh`, `ci-deploy-wrapper.sh`, `cat-deploy-state.sh`, `_cron-claude-eval-substrate.ts`, `_cron-shared.ts`.

## GDPR / Compliance (Phase 2.7)

Assessed — **N/A (no regulated-data surface).** The drain operates on process-liveness and deploy timing only; it reads, moves, and stores **zero** personal data. The new `cat-deploy-state.sh` fields (`cron_drain_wait_secs`/`cron_drain_timed_out`/`inngest_paused`) are integers/booleans behind the existing HMAC+CF-Access webhook. None of the canonical regex surfaces (schema/migration/auth/API/`.sql`) are touched. Trigger (b) (brand-survival `single-user incident`) is noted, but no new LLM/external processing of operator-session data is introduced (the crons themselves are unchanged), so the gate is not invoked.

## Infrastructure (IaC)

### Terraform changes
**None.** No new server, secret, vendor, systemd unit, DNS, or cert. The drain is a behavior change to the existing deploy orchestrator `ci-deploy.sh` (the established IaC deploy mechanism, shipped to the host via the existing release pipeline). `CRON_DRAIN_TIMEOUT`/`CRON_DRAIN_POLL`/`LEASE_MAX_AGE` are code-default, env-overridable named constants (the ADR-062 `PROD_MEMORY_CAP` precedent) — not Doppler secrets (no sensitivity).

### Apply path
**(a) Ship-with-the-app.** `ci-deploy.sh` + `cat-deploy-state.sh` already deploy to the host via the release pipeline / no-SSH `infra-config` push; no `terraform apply`. The substrate change ships in the container image. Blast radius: the first deploy after merge runs the new drain logic; if the drain has a bug it could *delay* a deploy (bounded by `CRON_DRAIN_TIMEOUT`) but cannot kill the host (the gate only loops + sleeps + logs before the unchanged stop/rm/run sequence). Downtime: none beyond the existing canary-swap window plus, at most, one bounded drain wait.

### Distinctness / drift safeguards
dev has no always-on cron host (ADR-062 Scope) — the drain is a prd-path behavior; it is inert in dev (no in-flight crons → `cron_in_flight` returns non-zero immediately → zero wait). No Terraform state, no `lifecycle.ignore_changes`.

### Vendor-tier reality check
N/A — no vendor resource created.

## Observability

```yaml
liveness_signal:
  what: "ci-deploy drain outcome — cron_drain_wait_secs + cron_drain_timed_out"
  cadence: "every prod deploy (per web-platform-release.yml run)"
  alert_target: "Sentry event_type=cron-drain-timeout (only the timeout path pages)"
  configured_in: "apps/web-platform/infra/cat-deploy-state.sh + report_cron_drain_timeout in ci-deploy.sh"
error_reporting:
  destination: "Sentry (host-side POST, mirroring container-restart-monitor.sh), feature=ci-deploy"
  fail_loud: "drain timeout that kills a cron emits a Sentry event AND sets cron_drain_timed_out=1; a stale-lease-blocking-crons condition is logged via pino at the substrate early-return — never silent (learning 2026-04-03-doppler-silent-fallback)"
failure_modes:
  - mode: "drain times out, cron killed anyway"
    detection: "cron_drain_timed_out=1 in deploy-status webhook + Sentry event"
    alert_route: "Sentry cron-drain-timeout"
  - mode: "Inngest wedged-paused by untrappable SIGKILL / crashed deploy (darks ALL event-driven fns, server-global)"
    detection: "inngest_paused=true (queried from Inngest, not self-reported — G17); next-deploy resume-if-paused-at-entry reconcile un-wedges (G3)"
    alert_route: "inngest_paused webhook field + existing cron Sentry missed-check-in monitors"
  - mode: "resume fires into a FAILED swap (old gone, new failed) → freed runs dispatch into containerless system (G14)"
    detection: "resume gated on swap success; on failure the wedge is the safe state (auto-recovered next deploy)"
    alert_route: "deploy-state reason + Sentry"
  - mode: "detection false-positive (pgrep matches cc-go/agent-runtime claude) → full false drain + false page (G16)"
    detection: "AC11 — cron_drain_timed_out/long wait on a no-cron deploy"
    alert_route: "Sentry event_type=cron-drain-timeout frequency"
  - mode: "detection false-negative (signal misses a running claude child) → stop kills it"
    detection: "original _cron-claude-eval-substrate.ts:706 spawn-cwd symptom still fires post-merge; positive-detection probe (G8) catches at Phase 0"
    alert_route: "existing cron-eval error self-report → Sentry"
logs:
  where: "journald via logger -t ci-deploy (CRON_DRAIN: lines); pino for substrate lease-skip"
  retention: "journald host default (existing)"
discoverability_test:
  command: "curl -s -H 'CF-Access-...' https://deploy.soleur.ai/hooks/deploy-status | jq '{cron_drain_wait_secs, cron_drain_timed_out}'"
  expected_output: "integer wait + boolean timed_out (safe sentinels -1/false when drain not reached) — NO ssh"
```

## Acceptance Criteria

### Pre-merge (PR)
- [ ] **AC1 (drain survival, max ceiling, pool-agnostic).** `ci-deploy.test.sh` T1: with `cron_in_flight` (the verified pool-agnostic signal) returning 0 for N polls then non-zero, `docker stop` is NOT issued until it is false (or timeout). `CRON_DRAIN_TIMEOUT` default = MAX per-function `MAX_TURN_DURATION_MS` (4200s), asserted ≥ max (T9) so the 70-min growth-audit cron survives.
- [ ] **AC2 (bounded, not infinite).** T2: in flight past `CRON_DRAIN_TIMEOUT` → break once, `cron_drain_timed_out=1`, `report_cron_drain_timeout` once, then normal stop/rm/run. T8: a non-zero `pause`/`report_*` does not abort the deploy under `set -e` (`|| true`, G6).
- [ ] **AC3 (no-cron fast path).** T3: `cron_in_flight` false on first poll → zero wait, immediate stop (no latency regression in the common case).
- [ ] **AC4 (pause/resume crash-safe, no trap clobber).** T4: `inngest_pause` before the drain; `inngest_resume` fires on the happy path AND on injected early-exit via the **composed** EXIT+TERM/INT handler — AND the existing deploy-state finalization + secrets cleanup STILL run (G2 no-clobber). T5: resume-if-paused-at-entry reconcile un-wedges a pre-paused Inngest (G3). `inngest_paused` is derived by querying Inngest, not self-reported (G17).
- [ ] **AC4b (four-constant wall-clock lockstep, resolved value).** The wrapper literal AND the three release-workflow window constants (`STATUS_WINDOW`/`HEALTH_WINDOW`/`IN_FLIGHT_CEILING_S`) are equal and ≥ `CRON_DRAIN_TIMEOUT` + overhead; an assertion proves the wrapper's **resolved numeric** value (not an expression that evaluates to 600 across the exec boundary — P1-wrapper) and that the four-way equality assertion passes.
- [ ] **AC4c (memory-dwell).** T6: the canary is stopped+removed BEFORE the drain loop (resident set during drain excludes the 1536m canary — platform-strategist).
- [ ] **AC4d (detection verified live).** Phase-0 positive-detection probe: the chosen `cron_in_flight` command was RUN against a real in-flight cron and returned a hit (recorded in the spec), and the probe has its own timeout (T7). Not just mocked T1–T9 (G8/G16).
- [ ] **AC5 (no-SSH observability).** `cat-deploy-state.test.sh`: `cron_drain_wait_secs` (int) + `cron_drain_timed_out` (bool) + `inngest_paused` (bool) present with safe sentinels; `discoverability_test` shape verified (no `ssh`).
- [ ] **AC6 (canary untouched + pause placement).** Drain + pause/trap run on the prod-swap branch only, strictly after `CANARY_HEALTHY==true` (G10); `ci-deploy.test.sh` asserts no drain on a canary-fail early exit and that prod can never reach `docker stop` having skipped `pause`.
- [ ] **AC7 (ADR-068 committed).** ADR-068 exists with Decision + Alternatives (Option 2 deferred + re-eval criteria) + status accepted; the "no C4 impact" enumeration is recorded.
- [ ] **AC8 (typecheck/tests green).** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean; `./node_modules/.bin/vitest run <new test>` green; `bash apps/web-platform/infra/ci-deploy.test.sh` + `cat-deploy-state.test.sh` green.
- [ ] **AC9 (Option-2 tracking issue).** A GitHub issue is filed for Option 2 (isolated cron-worker) with the ADR-068 re-eval criteria, labeled with a verified-existing label.

### Post-merge (operator / automated)
- [ ] **AC10 (real-deploy survival).** After merge, the first deploy that lands while a cron is in flight shows `cron_drain_wait_secs > 0` and `cron_drain_timed_out=false` in the deploy-status webhook, and the `_cron-claude-eval-substrate.ts:706` spawn-cwd symptom does NOT fire for that run. Read via the webhook (no SSH). **Automation:** `gh`/`curl` against the deploy-status webhook — no operator dashboard.
- [ ] **AC11 (no false-block).** Over the first 72h post-merge, no spurious `cron_drain_timed_out` on deploys where no cron was running (guards against detection false-positives). Read via Sentry `event_type=cron-drain-timeout` frequency (expected 0).

## Domain Review

**Domains relevant:** Engineering (CTO), Infrastructure (platform-strategist), Product flow (spec-flow-analyzer). Product/UX Gate: **NONE** — no UI-surface file in Files to Edit (mechanical UI-surface scan: no `components/**`, `app/**/page.tsx`, `app/**/layout.tsx`). Finance/Legal/Marketing/Sales/Support: not relevant (deploy-orchestration infra change; GDPR assessed N/A above).

**Brainstorm-recommended specialists:** none (no brainstorm preceded this one-shot).

### Engineering (CTO) — Status: reviewed

**Decision validated:** Option 1 (drain) over Option 2 (isolated worker) is the correct call — 8GB cx33 at ~6.9GB peak has no room for a second always-on claude-running container; Option 2 duplicates the sandbox/containment/egress/Inngest-multi-app surface (wrong scope for a one-shot). Deferral via ADR-068 + tracking issue is right. **Three P1 factual corrections (folded into Overview):** (P1-A) ceiling is per-function 15→70 min, `CRON_DRAIN_TIMEOUT` default = max = 4200s, not 3600; (P1-B) claude-eval runs outside `cron-platform` (`agent-runtime` limit:50 + cc-go) → detection must be pool-agnostic; (P1-wrapper) the wrapper execs into ci-deploy.sh so `CRON_DRAIN_TIMEOUT` is unset there → shared sourced constant + AC asserts resolved number. Trap must cover `EXIT TERM INT`, with the `inngest_paused` watchdog field as the PRIMARY recovery (trap secondary, since SIGKILL is untrappable). Re-eval criterion (d) reworded: "any claude-spawn pool's effective concurrency makes the drain wait Σ not max."

### Infrastructure (platform-strategist) — Status: reviewed

**Seam (drain in ci-deploy.sh vs SIGTERM) correct; cost-deferral correct.** P0/P1: (1) the wall-clock is a four-constant fail-closed invariant pinned to a fixed literal — name the loosened stale-lock/poll-failure detection as an ADR-068 trade-off; (2) compose `inngest_resume` into the existing EXIT trap (`:137`) — a bare `trap … EXIT` clobbers deploy-state finalization + secrets cleanup; (3) **sustained-memory dwell** — draining with the canary still resident holds ~6.9GB for up to ~50–70 min on 8GB (ADR-062 assumed seconds) → reorder so the drain runs **after canary teardown, before old-prod stop** (resident ≈ old-prod + cron ≈ 5.4GB). `inngest pause` is server-global (all functions, not just crons). Add re-eval criterion (e): sustained OOM-kills during a drain window argue for Option 2 independent of host size.

### Product flow (spec-flow-analyzer) — Status: reviewed

19 grounded gaps. **Highest-priority before /work** (carried as the deepen-plan/work checklist below): **G1** pause semantics — `inngest-bootstrap.sh:9-10` documents pause as "drains in-flight events," which is evidence *against* the plan's "does not abort in-flight" assumption; Phase 0 MUST run pause against a live in-flight cron and observe the child. **G2** trap clobber (= platform-strategist #2). **G3** SIGKILL-mid-drain wedge — the EXIT trap doesn't run on an untrappable SIGKILL (wrapper `--kill-after`, host OOM/reboot) → Inngest wedged paused, all crons dark; needs a resume path that does NOT depend on the dying script. **G16/G8** detection proxy — `pgrep -f claude` false-positives on cc-go/agent-runtime spawns (full false drain + false page) and false-negatives if the bin path differs; the gql option must filter to the cron+agent-runtime function IDs; the chosen signal's exact command MUST be run against a live in-flight cron before it's trusted (no synthetic test exercises the REAL signal today).

### Carried gap checklist (deepen-plan Phase 4 + /work Phase 0 MUST resolve each)

- **G1** Confirm `inngest pause` stops new dispatch AND does not abort/cut the in-flight run; confirm it gates **event-driven** invokes (manual `/api/internal/trigger-cron`, `agent-runtime`) too, not just scheduled (G7). Run it live against an in-flight cron.
- **G2** Compose `inngest_resume` into the existing `:137` EXIT handler (+ `:171` TERM/INT) — never a bare `trap … EXIT`; show the combined handler in the snippet; spell out the happy-path teardown (manual resume → `trap -` that preserves state cleanup) (G15).
- **G3** Recover a wedged-pause WITHOUT depending on the dying script (untrappable SIGKILL path): the preferred mechanism is an idempotent "resume-if-paused at deploy entry" reconcile in `ci-deploy.sh` itself (next deploy un-wedges; no new host unit); `cat-deploy-state.sh` should derive `inngest_paused` by querying Inngest itself rather than self-reporting (G17). Any host timer added for faster recovery routes through the existing IaC per Phase 2.8 — do NOT hand-provision.
- **G4** Resume = explicit exit-code check + bounded retry + dedicated loud alert (not best-effort `|| true` like `inngest-bootstrap.sh:421`); sequence resume AFTER new-container Inngest function-sync, not just health (G11), and only on swap success (G14 — resume into a failed swap dispatches freed runs into a containerless system).
- **G5/G19** `cron_in_flight` probe needs its own `timeout`/`curl --max-time`; re-derive margin so a max-length drain + poll + probe latency cannot reach the wrapper SIGKILL window.
- **G6** Under `set -euo pipefail` (`:2`), `inngest_pause`/`report_cron_drain_timeout` must be `|| true`-guarded so a nonzero helper doesn't abort the deploy after pause.
- **G8/G16** Pin the detection signal by RUNNING it against a live cron; rule out every other in-container `claude` exec or scope the gql query to cron+agent-runtime function IDs; add a positive-detection probe (not just mocked T1–T6).
- **G9** AbortSignal-fires-during-drain race: ensure the `retries:1` re-dispatch lands on the NEW container (pause must hold), and the 5s SIGTERM→SIGKILL dying child doesn't mis-extend the drain or mis-record success.
- **G10** Assert `pause`+trap are installed strictly after the `CANARY_HEALTHY==true` guard and that the prod path can never reach `docker stop` having skipped `pause`.
- **G12** Model the **server-global** pause blast radius in User-Brand Impact: a ~50–70-min global async freeze on every deploy landing during a cron freezes ALL event-driven Inngest functions, not just crons.
- **G18** Phase-3a poll-budget bump must account for queued-deploy starvation (`web-platform-release.yml:139` `cancel-in-progress:false`) — a wedged drain holds the lock for the whole wall-clock.

## Test Scenarios

- A growth-audit cron (70-min budget) is 20 min into its run when a merge triggers a deploy → canary validates + is torn down → drain holds for ~50 min → cron completes → deploy swaps → no kill. `cron_drain_wait_secs ≈ 3000`.
- A deploy lands with no claude child running → zero drain wait → normal swap.
- A cron hits its own ceiling mid-drain (AbortSignal fires) → `cron_in_flight` goes false at abort → drain proceeds; the `retries:1` re-dispatch is held by `pause` and lands on the new container (G9).
- A previous deploy was SIGKILLed mid-drain leaving Inngest paused → the next deploy's resume-if-paused-at-entry reconcile un-wedges it (G3); `inngest_paused=true` was visible in the webhook meanwhile.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`, or omits the threshold will fail `deepen-plan` Phase 4.6 — this one is filled.
- **The `ci-deploy-wrapper.sh` `timeout 1800s` (30 min) caps the WHOLE drain.** If `CRON_DRAIN_TIMEOUT` (~50 min) is not paired with a wrapper-cap bump (Phase 3a), the wrapper SIGKILLs `ci-deploy.sh` mid-drain at 30 min → the deploy fails AND a >25-min cron is still killed. The wrapper bump and the drain default must move together; a drain default that exceeds the wrapper budget is a silent best-effort regression. (This is the #1 GREEN-time trap in this plan.)
- **`inngest pause` left wedged darks EVERY event-driven function (server-global).** `inngest_resume` must be **composed into the existing EXIT handler** (`:137`) + `TERM INT` (`:171`) — a bare `trap … EXIT` clobbers deploy-state finalization (G2). SIGKILL is untrappable, so the PRIMARY recovery is the next-deploy resume-if-paused-at-entry reconcile (G3) + the queried `inngest_paused` field; the trap is secondary. Phase 0 must confirm `pause` stops only NEW dispatch and does NOT abort the in-flight run (`inngest-bootstrap.sh:9-10` "drains in-flight events" is evidence against this — verify live).
- **Detection signal must be *run*, not assumed.** Phase 0 step 2 picks between `docker exec … pgrep -f claude` and the Inngest `/v0/gql` `{ runs }` query only after one is *executed* against the real container model (note `inngest_crons` in the webhook is completion timestamps, NOT an in-flight signal — do not reuse it). A wrong signal makes the drain a no-op (cron still killed) while every test passes against the mock — the proxy-vs-invariant trap. Deepen-plan must pin the verified command.
- **`docker exec … pgrep` runs in the container PID namespace** — confirm the spawned `claude` child is visible to `pgrep` from a `docker exec` (it is a descendant of the container's PID 1; should be visible) before relying on it.
- **The lease must be visible to BOTH the old and new container** (a host-mounted path), and must carry a TTL — an un-TTL'd lease left by a crashed deploy darks every cron silently (worse than the bug being fixed).
- **`CRON_DRAIN_TIMEOUT` default must equal the cron ceiling**, not less — a lower default reintroduces best-effort kills. Lowering it is a deliberate operator trade-off (deploy speed vs survival), documented in ADR-068.
- **`docker restart` does not reload images** (learning `2026-03-19`) — the drain does NOT change the stop/rm/run swap; it only gates *when* the stop fires. Do not "optimize" the swap into a restart.
- **journald maps all stdout to PRIORITY=6** — substrate lease-skip logging must use pino fields, not journald-priority filtering, or the signal is invisible.

## Alternatives Considered

| Option | Verdict | Why |
|---|---|---|
| **1. Graceful drain in `ci-deploy.sh` (this PR)** | **Chosen** | Bounded by `pause` (stops new dispatch) + the MAX per-function ceiling (wait=max not sum) → survival of the in-flight cron; no topology change; ships in one PR; satisfies acceptance limb 1 |
| **2. Isolated cron-worker container** | **Deferred (ADR-068 re-eval criteria + AC9 tracking issue)** | Strongest fix but: 8GB cx33 deploy-window peak already ~6.9GB (ADR-062) → needs a host upsize (recurring cost); duplicates the entire Claude-Code runtime setup (sandbox overlay, containment hook I7/ADR-058, ephemeral workspace provisioning, ADR-052 egress allowlist, Doppler/systemd patterns); needs Inngest multi-app registration; five-bug-cascade precedent (#4017/#4079) shows multi-component Inngest deploys are high-risk. The issue itself calls it "the largest change." Wrong scope for a one-shot |
| **Drain inside the Node SIGTERM handler** | Rejected | `server/index.ts:243` is bound to `SHUTDOWN_TIMEOUT_MS=8_000` (< `docker stop --time=12`); cannot wait 60 min |
| **Unbounded drain** | Rejected | Deploy starvation; bound by the cron's own ceiling instead |
| **Do nothing / rely on #5420** | Rejected | #5420 fixed OOM/crash restarts but not deploy-driven kills — the explicit residual #5669 targets |
