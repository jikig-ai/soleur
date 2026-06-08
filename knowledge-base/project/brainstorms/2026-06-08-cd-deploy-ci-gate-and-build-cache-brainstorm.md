---
date: 2026-06-08
topic: cd-deploy-ci-gate-and-build-cache
status: brainstorm-complete
lane: cross-domain
brand_survival_threshold: single-user incident
issue: 5052
pr: 5051
branch: feat-cd-deploy-ci-gate-and-build-cache
---

# Brainstorm: Gate prod deploy on CI + speed up the CD critical path

## Origin

Operator question: *"I'm doubting whether re-running CI post-merge is useful at all,
and whether removing it would improve post-merge CD velocity / time to production."*

Read-only investigation **inverted the premise**, and the operator chose to (a) gate the
deploy on CI and (b) hunt for genuine CD-speed wins in the build/deploy path.

## Premise Correction (what the pipeline actually does)

The web-platform path to prod is a single job chain in `web-platform-release.yml`, triggered
by `push:[main]` filtered to `apps/web-platform/**`:

```
release (version + docker build + push)
  → migrate (needs: release)
  → verify-migrations (needs: migrate)
  → verify-doppler-secrets (no needs → parallel)
  → deploy (needs: [release, migrate, verify-migrations, verify-doppler-secrets])
        → webhook POST → poll deploy status → poll /health version (≤900s ceiling)
```

**`ci.yml` is nowhere in that chain.** No `needs: CI`, no `workflow_run` on CI, no
status-check wait. The full test suite (3 vitest shards + `next build` + ~12 lint/guard
jobs) runs **in parallel** with the deploy, gating nothing.

Consequences:

1. **Removing post-merge CI would save zero time-to-production** — the deploy never waited
   on it. The operator's original premise does not hold.
2. **Post-merge CI is the only per-push signal that `main` is healthy**, and it is the
   `workflow_run` trigger for `post-merge-monitor.yml`'s auto-revert of `[bot-fix]` commits.
   Removing it would widen the "broken main, undetected" window from minutes to the 6-hour
   `main-health-monitor` cron, and silently kill bot-fix auto-revert.
3. **The real latent risk (the inversion):** prod deploys are **not gated on tests at all.**
   A PR green in isolation but broken by a semantic conflict on `main` (builds, boots, health
   endpoint 200s) **ships to prod**. The post-deploy health poll catches *hard* failures
   (won't boot / wrong version / wrong SHA) but **not semantic** ones. Post-merge CI catches
   those only *after the fact*.

## What We're Building

Two workstreams in one PR:

### WS1 — Gate the prod cutover on CI (safety)

Gate the **`deploy` job** (not `release`/build) on `ci.yml`'s `test` aggregator succeeding
for the same commit SHA. The image still **builds in parallel** with CI, so wall-clock time
to prod becomes `max(build_chain, CI)` instead of `build_chain + CI`. Net: a semantically
broken `main` cannot reach prod, with ~zero added latency once the build is cached (WS2).

### WS2 — Speed up the CD critical path (velocity)

The Docker build re-executes **every** layer on **every** release — there is **no
`cache-from`/`cache-to` and no `setup-buildx`** on the `docker/build-push-action` step.
The runner stage installs (all pinned, rarely-changing) repeat each time:
`@anthropic-ai/claude-code`, `likec4`, `apt-get` (git/bubblewrap/socat/qpdf/jq), `gh`, and
**`npx playwright install --with-deps chromium`** (Chromium + system libs, ~1–2 min alone),
then `npm ci --omit=dev`.

Ranked levers:

| # | Lever | Risk | Expected win |
|---|-------|------|--------------|
| 1 | **Add Docker layer cache** (`setup-buildx-action` + `cache-from`/`cache-to: type=gha` or registry) | Low | Largest. Pinned runner-stage layers become cache hits; only `COPY . . → next build` rebuilds. |
| 2 | **Parallelize `migrate` with the Docker build** — split version-compute into its own lightweight job that both the build and `migrate` depend on, so migrations stop waiting on the image build | Medium | Removes the slow build from the migrate→deploy serial path |
| 3 | **Dockerfile layer-order audit** — ensure rarely-changing heavy installs sit above source-busting `COPY` so caching (lever 1) actually bites | Low | Maximizes lever 1's hit rate |

## Why This Approach

- **Gate `deploy`, not `release`:** keeps the slow build off the gate's critical path. `max()`
  not `sum()`. Directly answers "gate deploy on CI" without the velocity tax the operator
  feared from the (inverted) original framing.
- **Caching is the highest-ROI velocity lever** and is independent of WS1 — it can ship even
  if the gate is deferred, and it makes the gate effectively free.
- **YAGNI:** no trigger-model rewrite (`workflow_run`-driven release was considered and
  rejected — see Key Decisions). Smallest diff that achieves both goals.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| What to gate on CI | The `deploy` job only | Build runs in parallel; gate adds latency only if CI > build |
| How `deploy` waits for CI | Wait-for-check job keyed on the same SHA (e.g. poll `gh api` for the `test` check-run conclusion), added as a `needs:` of `deploy` | No trigger rewrite; reuses existing `test` required-context name |
| Trigger model | **Keep `push:[main]`** (rejected: `workflow_run`-on-CI-driven release) | `workflow_run` adds default-branch-context quirks and a second cold-start; gating the deploy job is far smaller |
| Post-merge CI itself | **Keep unchanged** | It is the only per-push main-health signal + the auto-revert trigger; removal is strictly worse |
| Build cache backend | `type=gha` (GitHub Actions cache) as default; revisit registry cache if gha eviction hurts hit rate | Zero extra infra; native to Actions |
| migrate parallelization (lever 2) | **In scope but secondary** — implement only if the version-compute split stays small | Real serial-path win but higher blast radius (touches release-gating logic) |
| Fail-safe if CI is slow/stuck | Define a bounded wait + explicit timeout behavior for the gate (fail-closed: no deploy on CI timeout) | A user-brand-critical surface must not deploy on an unknown CI state |

## Measured Baseline (2026-06-08, last 8 main runs)

| Pipeline | Range | Median |
|----------|-------|--------|
| `ci.yml` on main | 4–8 min | ~5 min |
| `web-platform-release.yml` (build+migrate+deploy) | 9–18 min | ~13 min |

**The deploy chain is 2–3× slower than CI.** This resolves the `max()` question: gating the
`deploy` job on CI adds **~zero wall-clock today** — CI finishes ~8 min before the build chain
is ready to cut over. The safety gate is effectively *free*. The velocity prize is entirely in
WS2 (the ~13-min uncached build). Even after caching drops the build toward ~CI duration, the
gate stays free because the two run concurrently.

## Open Questions

1. ~~CI vs build duration~~ **RESOLVED** — see Measured Baseline. Gate is free; caching is the
   velocity lever. A fast-smoke-subset is NOT needed (CI already < build).
2. **Wait-for-check mechanism:** roll a small inline `gh api` poll vs. a pinned third-party
   action (`fountainhead/action-wait-for-check`). Vendor-pin discipline applies if external.
3. **Same-SHA correctness:** ensure the gate waits for the CI run of *this* push's SHA, not a
   stale/concurrent run (the `concurrency` group on `main` lets prior runs finish).
4. **`type=gha` cache scope/eviction:** 10 GB repo cache limit — confirm the Playwright/Chromium
   layer fits and isn't evicted by sibling workflows' caches.
5. **migrate parallelization blast radius:** does splitting version-compute interact with the
   `release.outputs.version`/`docker_pushed` gates the deploy job already reads?

## Domain Assessments

**Assessed:** Engineering (CTO/platform). Marketing, Operations, Product, Legal, Sales,
Finance, Support — not relevant (internal CI/CD infra, no user-facing or legal surface).

### Engineering

**Summary:** Premise inverted — post-merge CI is off the deploy critical path, so removal
yields no velocity and loses the sole per-push main-health signal + bot-fix auto-revert. The
correct moves are (1) gate the `deploy` job (not the build) on CI for `max()`-not-`sum()`
safety, and (2) add Docker layer caching, which is the dominant CD-speed lever and currently
entirely absent. Both are low-risk and independently shippable.

## User-Brand Impact

- **Artifact:** the production web-platform deploy (prod cutover + migrations).
- **Vector:** a semantically broken `main` (two independently-green PRs conflicting) ships to
  prod undetected by the current gates (which check build/boot/health/SHA, not test
  semantics), surfacing to a user as a broken flow or — via a bad migration that still
  "verifies" — data corruption.
- **Threshold:** `single-user incident`. WS1 closes this vector at the deploy gate; WS2 must
  not weaken any existing gate while speeding the path.
