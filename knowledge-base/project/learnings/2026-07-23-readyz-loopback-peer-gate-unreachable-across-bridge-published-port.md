---
title: A loopback-peer-gated endpoint is topology-permanently 403 across a bridge-published container port — probe inside the container
date: 2026-07-23
category: integration-issues
module: workspaces-luks / server-readiness
tags: [docker, bridge-network, loopback-gate, readyz, workspaces-luks, cutover, false-boot-race]
issues: [6812]
---

# A loopback-peer gate is unreachable via a bridge-published port — and it masqueraded as a "boot race"

## Problem

The workspaces-luks at-rest encryption cutover (#6604 / ADR-119) kept failing at its `app_canary`
step with `reason=readyz_gate_regression code=403`. On 2026-07-20 this abort (framed at the time as a
"Cloudflare 521 boot race") let the host-local dead-man timer remount the plaintext volume over a
freshly-cut LUKS mount, stranding 27 minutes of sole-copy writes — incident #6812. On 2026-07-23 the
re-cut reproduced the SAME failure: recut → dry-run (green) → real freeze copied 8 workspaces clean
(git-fsck differential green), repointed the mapper, host canary PASSED — then `app_canary` died on
`/internal/readyz` returning **403**.

A verify run 2h later, at steady state, reproduced the 403 (`probe_last_code=403 probe_attempts=1`).
So it was **not** a boot transient. The endpoint returns 403 *always* in this deployment.

## Root cause

`apps/web-platform/server/readiness.ts:handleReadyzRequest` gates `/internal/readyz` on **both**
`isLoopbackPeer(req.socket.remoteAddress)` AND `isLoopbackHost(req.headers.host)`. `isLoopbackPeer`
accepts only `{127.0.0.1, ::1, ::ffff:127.0.0.1}`.

The prod app container runs on the **default docker bridge** with `-p 0.0.0.0:3000:3000`
(`ci-deploy.sh`, NOT `--network host`). A host-side `curl http://127.0.0.1:3000/internal/readyz`
is forwarded by docker into the container, where `req.socket.remoteAddress` is the **docker bridge
gateway** (e.g. `172.17.0.1`) — never loopback. So the peer gate answers 403, structurally, on every
probe. The endpoint has therefore **never** been reachable-as-ready from a host-side probe in this
topology; `app_canary` (which adopted the shared `wl_probe_readyz` helper) could never pass.

`/internal/metrics` is unaffected because it gates on `isLoopbackHost` **only** — a host curl sends
`Host: 127.0.0.1:3000`, which passes. That asymmetry is exactly why "metrics works but readyz 403"
looked like an endpoint-specific bug rather than a topology fact.

## Solution

Run the on-host readyz probe **inside** the container so the socket peer is a genuine loopback:
`docker exec soleur-web-platform curl -sS http://127.0.0.1:3000/internal/readyz`. Centralized in the
shared `wl_probe_readyz` helper (`apps/web-platform/infra/workspaces-luks-emit.sh`), so all three
consumers (cutover `app_canary`, the daily `luks-monitor`, the verify workflow) inherit it. **Zero
gate-logic change** — the trust boundary (`readiness.ts` / `loopback.ts`) is untouched, so an
off-host / tunnel caller still gets 403 by construction. Fail-closed preserved: container down / curl
absent → `docker exec` non-zero → `|| printf '\n000'` → code 000 → `readyz_unreachable`.

**Rejected: widening `isLoopbackPeer` to accept the bridge gateway.** Under docker's default
`userland-proxy=true`, EVERY connection through the published `0.0.0.0:3000:3000` port — including
genuine off-host traffic — presents to the container as the bridge gateway. Accepting `172.17.0.1`
would collapse the off-host boundary to the attacker-controlled Host header. The rationale is now
embedded at the gate as a `do-NOT-widen` comment.

## Key insight

**A `req.socket.remoteAddress`-based loopback gate on an endpoint published via a bridge-networked
container port is unreachable from the host by design — the in-container peer is the bridge gateway,
not loopback.** When an internal/loopback-gated endpoint must be probed by an on-host consumer, probe
from *inside* the container (`docker exec`), never a host curl of the published port. And when a
health/canary probe fails with a *structural* HTTP status (403/401/404) that "retrying can't fix,"
distrust a transient-boot-race framing until you reproduce it at steady state — a topology-permanent
403 and a boot race look identical for the first 30 seconds, and the difference is what determines
whether the dead-man silently undoes your cutover.

## Session Errors

1. **Guessed the terraform-drift workflow filename** (`gh run list --workflow=terraform-drift.yml` →
   HTTP 404). **Recovery:** `gh workflow list` → the workflow is "Terraform Drift Detection" (id
   249470510). **Prevention:** resolve a workflow by `gh workflow list` before referencing a `.yml`
   name; display names and filenames differ.
2. **`test-all.sh` (full monorepo exit gate) timed out at 10 minutes** on a surgical infra diff.
   **Recovery:** scoped verification to the actual blast radius — the affected workspaces-luks infra
   suites (all green) + the one changed vitest file — and confirmed `test-all.sh` structurally
   excludes `apps/web-platform/infra/` anyway (those gate via `infra-validation.yml`). **Prevention:**
   for a small diff whose blast radius is enumerable, run the affected suites directly; the full-suite
   run is CI's job. (Already documented in `plugins/soleur/skills/work/SKILL.md`.)
3. **First `soleur:one-shot` invocation embedded `#6812`** (a heavily-cross-referenced OPEN incident)
   in its args. **Recovery:** recognized it would trip the Step 0a.5 collision machinery against the
   whole cutover saga's prior PRs, and re-invoked with the ref scrubbed to date-anchored prose.
   **Prevention:** already covered by the go.md sharp edge — scrub contextual `#N` citations from
   one-shot args; only OPEN work-target refs belong in `#N` form.
