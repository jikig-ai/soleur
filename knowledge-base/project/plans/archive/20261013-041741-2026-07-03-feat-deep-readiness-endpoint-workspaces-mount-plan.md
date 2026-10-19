---
title: "feat(infra): deep-readiness endpoint gating /workspaces mount+identity before web-2 LB pooling"
issue: 5966
type: feature
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
date: 2026-07-03
branch: feat-one-shot-5966-deep-readiness-endpoint
---

# feat(infra): deep-readiness endpoint (`/internal/readyz`) gating `/workspaces` mount + populated before web-2 can be LB-pooled

✨ Sharp Edge C1 from Multi-host GA (ADR-068). GA-blocking prerequisite.

## Overview

`/health` is a **liveness** probe: `server/health.ts` `buildHealthResponse()` hardcodes
`status:"ok"` (gated only on the Node process being up) and probes the **shared** Supabase
project. Neither signal reflects whether the *responding host's own* `/workspaces` block
volume is mounted and populated. On the ADR-068 multi-host topology each web host serves its
**own** host-local `/workspaces` volume, so a bare web-2 (running, empty/unmounted
`/workspaces`, not in rotation) returns `200 / status:ok / supabase:connected` — a routing
lie. The Cloudflare LB monitor is *required* to be reachability-only (`expected_codes="2xx"`
on `/health`, never Supabase-body-coupled, because both hosts share one Supabase and body
coupling would eject the sole live origin on a DB blip — ADR-068 blue-green amendment
2026-07-03). That constraint is correct but means the monitor alone cannot distinguish a
ready host from a bare one.

**This plan adds a separate, internal deep-readiness endpoint** `/internal/readyz` (gated
loopback/Host-header identically to `/internal/metrics`) that returns **non-2xx unless the
responding host can actually serve** — i.e. its `/workspaces` is a real distinct mountpoint
AND is populated with host-local workspace state. The drain/undrain tooling and (at GA) the
LB pre-pool check consult it before a host receives live weight. `/health` stays unchanged
(liveness). This is a **necessary-but-not-sufficient** additional gate layered on top of the
unchanged HARD INVARIANT: no live LB weight to web-2 before BOTH the owner-side relay is
active AND git-data is cut over.

**Design fail-closed:** any uncertainty (stat error, unexpected exception, missing root) →
`ready:false` / 503. A false 2xx on a bare host is a workspace-gone incident; a false 503 on
web-1 drains the origin. Both are single-user-incident class, so every ambiguous branch
resolves to not-ready.

### Premise Validation (Phase 0.6)

All cited references verified against `origin/main` state — every premise holds:

- **#5946** (GA cutover runbook) — `gh issue view` → **OPEN**. Still the pre-pool consumer.
  It is an *issue*, not yet a committed runbook doc; the AC reference is satisfied via an
  issue comment + the blue-green plan's Sharp Edge C1 update (see ACs).
- **ADR-068** — present; blue-green amendment (lines 541-575) + Sharp Edge C1 in the
  blue-green plan (lines 273-277) confirm the deep-readiness endpoint is a *filed follow-up*,
  not yet built. This plan builds it.
- **ADR-082** (fresh-web2-boot-observability) — present; boot path emits `host_id` in
  `soleur-host-bootstrap.sh emit_fail`. Noted as a future composition point for strict
  identity, not a v1 dependency.
- **`server/health.ts` / `server/index.ts`** — ground truth exactly as the issue states:
  `status:"ok"` constant, shared-Supabase probe, loopback `isLoopbackHost` gate already on
  `/internal/metrics`.
- **No existing `/internal/readyz`** — `grep -rn "readyz|/internal/ready|deep-readiness"`
  over `apps/web-platform/**` returns zero. This is a **build**, not a fix.
- **ADR corpus** — no rejected "deep-readiness" alternative exists; this mechanism is not in
  any ADR's rejected-alternatives table. It *implements* ADR-068 Sharp Edge C1.

## User-Brand Impact

**If this lands broken, the user experiences (four modes, panel-enumerated):**
- **false-2xx on a bare/empty web-2** → LB-pooled with live weight → a live request hits an
  empty `/workspaces` → workspace appears gone (workspace-gone incident).
- **false-2xx on a read-only/degraded mount** → host pooled → the user's new work silently
  fails to persist (write-loss) while readyz reported healthy. (Closed by the write-probe.)
- **false-503 on the live web-1** → drains the sole origin → full ingress outage. Mitigated by
  the flap-safety AC: a live-origin drain requires N≥2 consecutive not-ready reads, never
  single-shot; readyz is NOT the continuous LB liveness monitor (that stays on `/health`).
- **flap / pool-thrash** during GA cutover from a transient probe error → mitigated by the
  same N≥2-consecutive consumer contract + fail-closed-never-throws route.

**If this leaks, the user's data/workflow is exposed via:** capacity/topology signals (mount
writability, workspace presence) are attacker-useful (DoS-tuning, cluster-shape scraping).
Gated on the **loopback transport peer** (`socket.remoteAddress`, unspoofable off-host) with
`isLoopbackHost` as secondary; body carries only two booleans (no path echo). No new
external-facing disclosure beyond what `/internal/metrics` already gates.

**Brand-survival threshold:** single-user incident.

> CPO sign-off required at plan time before `/work` begins (carried by ADR-068 /
> ADR-082 single-user-incident substrate). `user-impact-reviewer` runs at review time.
> deepen-plan (pipeline step 2) supplies the substance-level review this threshold requires.

## Research Reconciliation — Spec vs. Codebase

No spec.md exists for this branch (fresh one-shot plan). All issue-body claims verified
against live code — no divergences found. Reuse precedents identified:

| Concern | Precedent in codebase | Plan response |
|---|---|---|
| Loopback gating | `server/index.ts:51-55` `isLoopbackHost` + `/internal/metrics` route `:94-104` | Reuse the route shape; **gate on `req.socket.remoteAddress` loopback (transport peer, unspoofable) as primary**, keep `isLoopbackHost` as secondary (security panel P1 — Host header is client-supplied). |
| Can-serve / mount verification | `server/plugin-mount-check.ts` (existsSync + readdir + `.seed-complete` sentinel, mirrors to Sentry) | Adapt to a **write+unlink probe** (topology-robust: catches unmounted/read-only/EIO inside the container) + a **latched boot-time Sentry mirror** (`verifyWorkspacesMountOnce`). |
| Workspace-populated scan | `server/session-metrics.ts` `getActiveWorkspaceCount()` (readdir, `isDirectory()` filter, excludes `.orphaned-`/`.cron`, ENOENT→0) | Reuse via a **root-parameterized** variant; exclude `lost+found`. `> 0` is the populated signal. |
| `WORKSPACES_ROOT` resolution | `session-metrics.ts:9` — **module-load `const`** (NOT call-time) | **CORRECTION (panel):** the plan's v1 claim that session-metrics resolves call-time was wrong. Resolve `WORKSPACES_ROOT` **once** in `readiness.ts` and pass it into the root-parameterized count so both signals provably read the **same** root. |
| git-data flag | `workspace-resolver.ts:56` `isGitDataStoreEnabled()` | **CUT from v1** (panel unanimous YAGNI): the `? true : true` tautology was dead code that fails-OPEN when the flag flips on. GA adds the field with its real probe. |

## Deepen-Plan Review Synthesis (8-agent panel)

A single-user-incident-threshold panel (architecture-strategist, data-integrity-guardian,
security-sentinel, code-simplicity, observability-coverage, user-impact-reviewer,
spec-flow-analyzer, verify-the-negative) rewrote the design. **Load-bearing ground-truth
correction (architecture + data-integrity, independently):** `buildReadinessResponse()` runs
**inside the webapp container**, where `/workspaces` is a docker `-v /mnt/data/workspaces:/workspaces`
bind mount (`ci-deploy.sh:915,1148`, `cloud-init.yml:574`) over an overlayfs root. So the v1
`st_dev(/workspaces) !== st_dev(/)` mountpoint check is **always true** and **cannot** detect
a failed Hetzner volume attach (docker auto-creates the source dir on the host root fs and
bind-mounts it). The whole false-2xx defense collapsed onto `populated`. Decisions applied:

1. **Replace the st_dev mount check with a write+unlink probe** (`workspaces_writable`) —
   topology-robust; catches absent (ENOENT), read-only (EROFS), permission, and I/O failure
   from *inside* the container. This also closes a **new third failure mode** the panel found
   (user-impact F1): a mounted-but-read-only volume passed the old checks → silent write-loss.
2. **Cut `git_data_consistent`** (unanimous) — dead `? true : true` tautology that fails-OPEN
   when the GA flag flips on. GA adds it with a real probe.
3. **Complete fail-closed** (data-integrity P1): wrap the route handler in try/catch → 503. As
   written, an unguarded throw became an unhandled rejection → `installCrashHandlers()` →
   `process.exit(1)` = a *restart* of live web-1, worse than a 503.
4. **Add `verifyWorkspacesMountOnce()` boot mirror** (observability P1): the plan's cited
   boot-coverage was false — `verifyPluginMountOnce` checks the *plugin* mount, not
   `/workspaces`, and passes on a bare volume. A latched one-shot readiness check at boot →
   `reportSilentFallback` gives a mis-mounted web-1 a Sentry event with no LB-poll flood.
5. **Resolve `WORKSPACES_ROOT` once** (security + data-integrity + spec-flow + user-impact):
   the v1 claim that `session-metrics.ts` resolves call-time was factually wrong (it is a
   module-load `const` at `:9`). Resolve once in `readiness.ts`, pass into a root-parameterized
   count so both signals read the same root.
6. **Gate on `socket.remoteAddress`** (security P1): the Host header is client-supplied; the
   transport peer is unspoofable off-host.
7. **`lost+found` exclusion** + document **RWO single-attach** as the v1 identity backstop
   (spec-flow/data-integrity P0-P1): "populated" is a proxy for "identity"; the Hetzner block
   volume's single-attach guarantee is what makes deferring the ADR-082 `host_id` sentinel
   safe — recorded explicitly in the ADR amendment.
8. **Consumer flap-safety is a hard AC of THIS plan** (user-impact P1): the drain/pre-pool
   consumer MUST require N consecutive not-ready reads before draining a *live* origin — do
   not let flap-safety escape to the out-of-scope GA PR.

Module-split disagreement (architecture: keep separate to enforce "/health untouched";
code-simplicity: fold into health.ts) resolved in favor of a **separate `readiness.ts`** — the
physical boundary structurally enforces the load-bearing invariant, and after adding the
writability probe + boot mirror the module is no longer trivial.

## Implementation Phases

### Phase 1 — Readiness builder (`server/readiness.ts`, new)

```ts
// apps/web-platform/server/readiness.ts
import { writeFileSync, unlinkSync } from "fs";
import { join } from "path";
import { randomBytes } from "crypto";
import { countWorkspaceDirsAt } from "./session-metrics"; // new root-parameterized export

export interface ReadinessResponse {
  ready: boolean;
  checks: {
    workspaces_writable: boolean;  // host can create+unlink under WORKSPACES_ROOT (mounted,
                                   // not read-only) — topology-robust inside the container
    workspaces_populated: boolean; // ≥1 host-local workspace dir (lost+found excluded)
  };
}

function getWorkspacesRoot(): string {
  return process.env.WORKSPACES_ROOT || "/workspaces";
}

// Write+unlink a dotfile probe. Inside the container /workspaces is a bind mount over
// overlay root, so the classic st_dev mountpoint check is inert (always distinct) — a
// writability probe is the only signal that actually proves "this host can serve": it
// fails on ENOENT (absent), EROFS (read-only), EACCES, EIO. The probe file is a dotfile
// AND a file (not a dir), so it never inflates the populated count. FAIL CLOSED on any error.
function isWorkspacesWritable(root: string): boolean {
  const probe = join(root, `.readyz-probe-${randomBytes(6).toString("hex")}`);
  try {
    writeFileSync(probe, "");
    return true;
  } catch {
    return false;
  } finally {
    try { unlinkSync(probe); } catch { /* best-effort cleanup */ }
  }
}

export function buildReadinessResponse(): ReadinessResponse {
  const root = getWorkspacesRoot();
  const workspaces_writable = isWorkspacesWritable(root);
  // Resolve root ONCE and pass it in — do NOT call getActiveWorkspaceCount() (module-load
  // cached root, would split-brain with `root` above). countWorkspaceDirsAt excludes
  // `.orphaned-`/`.cron`/`lost+found` and requires isDirectory().
  const workspaces_populated = countWorkspaceDirsAt(root) > 0;
  const ready = workspaces_writable && workspaces_populated;
  return { ready, checks: { workspaces_writable, workspaces_populated } };
}
```

**`session-metrics.ts` change:** extract the dir-scan into `countWorkspaceDirsAt(root: string)`
(root-parameterized, adds `lost+found` to the exclusion filter), and re-implement the existing
`getActiveWorkspaceCount()` as `countWorkspaceDirsAt(WORKSPACES_ROOT)` — no behavior change for
existing callers, `readiness.ts` passes its once-resolved root.

Rationale: `workspaces_writable` proves the host can actually serve (mounted + writable);
`workspaces_populated` rejects a fresh/empty volume. Together they cover bare web-2, an
unattached volume (empty root-fs dir), and a read-only/degraded mount. Residual gap
(wrong-volume attached) is bounded by Hetzner RWO single-attach — documented in the ADR
amendment as the v1 identity backstop; the ADR-082 `host_id` sentinel is the fast-follow that
closes it fully.

### Phase 2 — Route wiring (`server/index.ts`)

Add `/internal/readyz` after `/internal/metrics`, gating on the **transport peer** and
wrapping the handler fail-closed:

```ts
// Deep-readiness (#5966, ADR-068 Sharp Edge C1). Gated to the loopback transport peer
// (socket.remoteAddress) — mount/topology state is attacker-useful and the Host header is
// spoofable. 503 when the host cannot serve locally. FAIL CLOSED on any throw.
if (parsedUrl.pathname === "/internal/readyz") {
  const peer = req.socket.remoteAddress ?? "";
  const peerLoopback = peer === "127.0.0.1" || peer === "::1" || peer === "::ffff:127.0.0.1";
  if (!peerLoopback || !isLoopbackHost(req.headers.host)) {
    res.writeHead(403, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "forbidden" }));
    return;
  }
  try {
    const readiness = buildReadinessResponse();
    res.writeHead(readiness.ready ? 200 : 503, { "Content-Type": "application/json" });
    res.end(JSON.stringify(readiness));
  } catch {
    // Never propagate — an unhandled throw here restarts the process (crash-handlers).
    res.writeHead(503, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ ready: false, checks: {} }));
  }
  return;
}
```

`/health` and `/internal/metrics` remain untouched. (Keeping `isLoopbackHost` as the secondary
clause preserves the e2e-port-suffix tolerance for non-3000 test ports.)

### Phase 3 — Boot-time readiness mirror (`server/index.ts` + `readiness.ts`)

Add `verifyWorkspacesMountOnce()` (latched like `verifyPluginMountOnce`) to `readiness.ts` and
call it once in `app.prepare()` next to `verifyPluginMountOnce()`:

```ts
// readiness.ts
let _bootChecked = false;
export function verifyWorkspacesMountOnce(): void {
  if (_bootChecked) return;
  _bootChecked = true;
  const r = buildReadinessResponse();
  if (!r.ready) {
    reportSilentFallback(null, {
      feature: "workspaces-mount",
      op: "boot-readiness",
      message: "workspaces not ready at boot",
      extra: { checks: r.checks, workspacesRoot: process.env.WORKSPACES_ROOT || "/workspaces" },
    });
  }
}
```

One-shot at boot → a mis-mounted/read-only web-1 gets a Sentry event with no LB-poll flood.
This is the async/push observability layer the pull-only readyz endpoint otherwise lacks.

### Phase 4 — Tests (`test/server/readiness.test.ts`, new)

Mock `fs` (`writeFileSync`/`unlinkSync`) + `./session-metrics` (`countWorkspaceDirsAt`) using
the `health.test.ts` mock-before-import pattern. Cases:

1. writable + populated (count 5) → `ready:true`, both checks true.
2. **bare-host simulation** — writable but empty (`countWorkspaceDirsAt===0`) → `ready:false`,
   `workspaces_populated:false` (AC-required).
3. read-only/unmounted — `writeFileSync` throws (EROFS/ENOENT) → `ready:false`,
   `workspaces_writable:false` (catches the write-loss + unattached cases).
4. `buildReadinessResponse` never throws — any internal error resolves to `ready:false`
   (fail-closed).
5. **Root honored, not split-brained** — set `WORKSPACES_ROOT` to a temp dir and assert BOTH
   the write probe AND `countWorkspaceDirsAt` operate on that root (guards the once-resolved
   fix; do NOT mock `countWorkspaceDirsAt` wholesale for this case — pass a real root).
6. Route gating — non-loopback `socket.remoteAddress` → 403 (single case; the loopback helper
   is already covered by the metrics suite).
7. `lost+found` present + zero UUID dirs → `workspaces_populated:false` (fresh-volume guard).

### Phase 5 — ADR-068 amendment + C4 review

Add the ADR-068 amendment (Architecture Decision section) recording the readiness contract,
the writability+populated semantics, the container-topology rationale (why not st_dev), and
the **RWO single-attach identity backstop**. Read all three `.c4` files; record "no C4 impact"
with the enumeration (below).

### Phase 6 — Docs / runbook reference (post-merge, automatable)

- Update the blue-green plan Sharp Edge C1 (`knowledge-base/project/plans/2026-07-03-feat-multi-host-blue-green-ingress-prereqs-plan.md` lines 273-277) from "file the deep-readiness endpoint as a follow-up" to "delivered — `/internal/readyz`, pre-pool gate".
- `gh issue comment 5946` noting `/internal/readyz` is the pre-pool readiness gate for web-2 and MUST return 2xx before any live LB weight.

## Files to Create

- `apps/web-platform/server/readiness.ts` — `buildReadinessResponse()` + `ReadinessResponse` + `verifyWorkspacesMountOnce()`.
- `apps/web-platform/test/server/readiness.test.ts` — 7 cases above.

## Files to Edit

- `apps/web-platform/server/index.ts` — add `/internal/readyz` route (socket-peer gated, try/catch) + `verifyWorkspacesMountOnce()` call in `app.prepare()`.
- `apps/web-platform/server/session-metrics.ts` — extract `countWorkspaceDirsAt(root)` (root-parameterized, `lost+found` excluded); `getActiveWorkspaceCount()` delegates to it (no behavior change for existing callers).
- `knowledge-base/engineering/architecture/decisions/ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md` — amendment (readiness contract + RWO identity backstop + container-topology rationale).
- `knowledge-base/project/plans/2026-07-03-feat-multi-host-blue-green-ingress-prereqs-plan.md` — Sharp Edge C1 "delivered" update (same PR).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `GET /internal/readyz` (loopback peer) returns **503** JSON `{ready:false, checks:{...}}` when the write-probe throws (unmounted/read-only: `writeFileSync` → EROFS/ENOENT) OR `countWorkspaceDirsAt(root)===0` (empty), and **200** `{ready:true}` only when **writable AND populated**. (`test/server/readiness.test.ts` cases 1-3)
- [ ] Bare-host simulation (writable-but-empty `/workspaces`) → `ready:false` / non-2xx. (case 2)
- [ ] Read-only / unmounted mount (write-probe throws) → `ready:false` — covers the write-loss third failure mode. (case 3)
- [ ] Fail-closed: `buildReadinessResponse()` never throws; the route's try/catch returns 503 on any internal error (NOT a process crash). (case 4 + route test)
- [ ] `WORKSPACES_ROOT` is resolved once and honored by BOTH signals — a test sets `WORKSPACES_ROOT` to a real temp dir (does NOT mock `countWorkspaceDirsAt` wholesale) and asserts both the probe and the count operate on that root. (case 5)
- [ ] `lost+found` at the root with zero UUID dirs → `workspaces_populated:false`. (case 7)
- [ ] Endpoint gating: non-loopback `req.socket.remoteAddress` → 403, no readiness body. (case 6) No new external-facing capacity/topology disclosure (body carries only two booleans; no path echo).
- [ ] `verifyWorkspacesMountOnce()` mirrors a not-ready boot state to Sentry via `reportSilentFallback` (latched; fires once). Covered by a unit test asserting one `reportSilentFallback` call on a not-ready boot and zero on a ready boot.
- [ ] `/health` (`buildHealthResponse`) and `/internal/metrics` behavior unchanged (existing `test/server/health.test.ts` still green); `getActiveWorkspaceCount()` unchanged for existing callers (existing `session-metrics.test.ts` green).
- [ ] **Flap-safety contract (hard AC, not deferred):** the ADR-068 amendment records that any consumer draining a **live** origin on readyz not-ready MUST require **N≥2 consecutive** not-ready reads (bias fail-closed only for the *candidate*/pre-pool decision, never single-shot drain the sole live origin). The out-of-scope GA LB config inherits this as a stated precondition.
- [ ] ADR-068 amendment present recording the readiness contract, writability+populated semantics, container-topology rationale (why not st_dev), and RWO single-attach identity backstop; `### C4 views` records "no C4 impact" with the external-actor/system/relationship enumeration checked against all three `.c4` files.
- [ ] `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/readiness.test.ts test/server/health.test.ts test/server/session-metrics.test.ts` passes.
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] PR body uses `Closes #5966` + `Ref #5946`.

### Post-merge (operator/automatable)

- [ ] Blue-green plan Sharp Edge C1 updated to reference the delivered endpoint. Automation: inline `Edit` in this PR (docs change ships with code).
- [ ] `gh issue comment 5946` posted referencing `/internal/readyz` as the pre-pool readiness gate + the N≥2-consecutive drain precondition. Automation: `gh` CLI via `/soleur:ship` post-merge. `Ref #5946` (interim breadcrumb — re-gate on the committed runbook when #5946 produces a doc).

## Observability

```yaml
liveness_signal:
  what: /internal/readyz HTTP status (200 ready / 503 not-ready) + a latched boot-time
    reportSilentFallback (verifyWorkspacesMountOnce) on a not-ready boot
  cadence: readyz on-demand (drain/undrain tooling + GA pre-pool check); boot mirror once/process
  alert_target: Sentry (boot mirror, op=boot-readiness); LB monitor stays on /health (GA, out of scope)
  configured_in: apps/web-platform/server/index.ts route + boot call; server/readiness.ts
error_reporting:
  destination: non-2xx status is the synchronous fail-loud signal for a consuming caller; the
    boot-time reportSilentFallback covers the steady-state mis-mount window (no consumer polling)
  fail_loud: true (503 + false check fields on the pull path; Sentry event on the boot path)
failure_modes:
  - mode: /workspaces absent or unmounted (write-probe ENOENT)
    detection: checks.workspaces_writable=false in the readyz body + boot Sentry event
    alert_route: consulted by drain/pre-pool → host not pooled; boot mirror → Sentry
  - mode: /workspaces read-only / degraded (write-probe EROFS/EIO)
    detection: checks.workspaces_writable=false (catches the silent-write-loss mode)
    alert_route: same
  - mode: /workspaces writable but empty (bare/unattached web-2)
    detection: checks.workspaces_populated=false (lost+found excluded)
    alert_route: same — distinguishes empty-volume from read-only/absent
logs:
  where: readyz stays quiet per-call (probe endpoint; avoids Sentry flood under polling). The
    boot-time verifyWorkspacesMountOnce reportSilentFallback is the async/push layer for a
    mis-mounted host. (NOTE: verifyPluginMountOnce checks the PLUGIN mount, NOT /workspaces —
    it does not cover this surface; the boot mirror is why this plan adds one.)
  retention: Sentry default (boot events); no per-call log
discoverability_test:
  command: >
    curl -s -H 'Host: 127.0.0.1' http://127.0.0.1:3000/internal/readyz | jq '{code: .ready, checks}'
  expected_output: "ready:true + both checks true on a ready host; ready:false + the failing
    check on a bare/read-only host. Remote no-SSH signal: the boot-readiness Sentry event
    (op=boot-readiness) — readyz itself is loopback-gated so only on-host callers reach it."
```

**Affected-surface note (Phase 2.9.2).** `/internal/readyz` is the in-surface probe for a
**container readiness gate** the operator cannot otherwise inspect. The `checks` object
discriminates all **v1** competing root-cause hypotheses (absent/read-only vs empty-volume) in
a single response. The steady-state blind window (a mis-mounted host with no consumer polling)
is closed by the latched boot-time `reportSilentFallback` — the plan's own precedent
(`verifyPluginMountOnce`), which the panel confirmed does NOT cover `/workspaces`.

## Architecture Decision (ADR/C4)

Detected: a new internal endpoint + a new **readiness-vs-liveness gating contract** for LB
pooling eligibility (a cross-cutting invariant every pooling decision must honor). This
**extends ADR-068** (Sharp Edge C1 / blue-green amendment) rather than making a fresh
decision — so the deliverable is an **ADR-068 amendment**, matching how ADR-068 has tracked
every GA decision as a dated amendment.

### ADR

Amend `ADR-068` (`## Decision`, new dated amendment) — decision: "Deep-readiness lives on a
separate internal `/internal/readyz` endpoint (gated to the loopback transport peer), returning
non-2xx unless `/workspaces` is **writable** (a write+unlink probe — the st_dev mountpoint
check is inert inside the `-v /mnt/data/workspaces:/workspaces` container bind mount and cannot
detect a failed volume attach) AND **populated** (`lost+found` excluded). `/health` stays
liveness-only. **v1 identity = writable + populated; the Hetzner block-volume RWO single-attach
guarantee is the identity backstop** (a host cannot mount another host's live volume); the
ADR-082 `host_id` sentinel is the fast-follow that closes the wrong-volume residual. A boot-time
`reportSilentFallback` (`verifyWorkspacesMountOnce`) is the async observability layer
(`verifyPluginMountOnce` covers the plugin mount, not `/workspaces`). **Flap-safety:** a consumer
draining a *live* origin on not-ready MUST require N≥2 consecutive not-ready reads; fail-closed
single-shot bias applies only to the *candidate*/pre-pool decision. This is a
necessary-but-not-sufficient gate layered on the unchanged hard invariant (relay active +
git-data cut over)." No new ADR ordinal claimed — amendment only. (If a reviewer prefers a
standalone ADR, the next free ordinal is provisional **ADR-083**; re-verified at ship.)

### C4 views

**Checked all three `.c4` files** (`model.c4`, `views.c4`, `spec.c4`). Enumeration for this
change: (a) **external human actor** — none (internal ops endpoint, no correspondent);
(b) **external system / vendor** — the Cloudflare LB monitor would *consult* readyz, but the
CF Load Balancer is added by the GA blue-green work (#5946), NOT this PR; this PR adds no
external-facing edge (loopback-gated); (c) **container / data-store** — reads the existing
host-local `/workspaces` volume already implied by the `webapp` container; no new store;
(d) **access-relationship change** — none external (loopback only). The `cloudflare` system
(`model.c4:214`) and `webapp` container already exist. **No C4 impact** for this issue — the
readyz endpoint is internal to the existing `webapp` container; the CF-LB→readyz consumption
edge lands with the GA work, not here. Run `apps/web-platform/test/c4-code-syntax.test.ts` +
`c4-render.test.ts` unchanged (no `.c4` edit).

## Infrastructure (IaC)

**Skip — no new infrastructure.** This is a pure-code change (one server module + route +
tests) against the already-provisioned `webapp` container. No new server, systemd unit,
secret, DNS record, firewall rule, or vendor account. The CF LB monitor that *consumes*
readyz (with `expected_codes`/pre-pool config) is Terraform owned by the GA blue-green PR
(#5946), explicitly out of scope here — this issue's AC only requires the runbook to
*reference* the endpoint. The deferred `host_id` sentinel identity layer, if adopted later,
would touch cloud-init and route through this gate at that time.

## Domain Review

**Domains relevant:** engineering (CTO)

### Engineering (CTO)

**Status:** reviewed (inline CTO assessment + 8-agent deepen-plan panel — see Review Synthesis)
**Assessment:** Pure server-side change on a blind execution surface (container readiness gate).
The deepen-plan panel materially corrected the design: the container-topology reality
(bind-mount over overlay) made the original st_dev mount check inert, so the load-bearing
signal became a **write+unlink probe** (proves the host can actually serve, catches
read-only/unmounted from inside the container) + **populated** (`lost+found` excluded). Fail-closed
is now complete (route try/catch → 503, never a process crash). A boot-time Sentry mirror closes
the steady-state observability blind window. Consumer flap-safety (N≥2 consecutive not-ready to
drain a live origin) is a hard AC of THIS plan, not deferred. RWO single-attach is the documented
v1 identity backstop. CPO sign-off required (single-user-incident, carried from ADR-068/ADR-082).

### Product/UX Gate

Not relevant — no UI surface. `## Files to Create`/`## Files to Edit` contain no
`components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`. Tier: NONE.

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` bodies contain no reference to
`server/readiness.ts`, `server/index.ts` readyz, or `server/health.ts` — this is net-new
code.)

## GDPR / Compliance

Skip — no regulated-data surface. Reads only host-local mount/workspace-count state (infra
coordination), no personal data, no schema/auth/API-route change. Topology signals stay
loopback-internal (no new disclosure).

## Test Scenarios

| Scenario | Setup | Expected |
|---|---|---|
| Ready host | write-probe ok, count=5 | 200, `ready:true`, both checks true |
| Bare web-2 (empty) | write-probe ok, count=0 | 503, `ready:false`, `workspaces_populated:false` |
| Read-only / unmounted | `writeFileSync` throws (EROFS/ENOENT) | 503, `ready:false`, `workspaces_writable:false` |
| internal error | any throw in builder | 503, `ready:false` (route try/catch, no crash) |
| Root honored | `WORKSPACES_ROOT`=temp dir, real fs | both probe + count use that root (no split-brain) |
| `lost+found` only | root has only `lost+found`, 0 UUID dirs | `workspaces_populated:false` |
| Non-loopback peer | `socket.remoteAddress`=public | 403, no readiness body |
| Boot mirror | not-ready at boot | one `reportSilentFallback` (latched); zero when ready |

## Sharp Edges

- **The st_dev mountpoint check is INERT inside the container.** `buildReadinessResponse()` runs
  inside the webapp container where `/workspaces` is a docker `-v /mnt/data/workspaces:/workspaces`
  bind mount over an overlay root — so `st_dev(/workspaces) !== st_dev(/)` is always true and
  cannot detect a failed Hetzner volume attach (docker auto-creates the source dir on root fs).
  Use the **write+unlink probe** instead; do NOT reintroduce a parent-device comparison thinking
  it proves the volume attached.
- **Fail-closed must be COMPLETE — wrap the route in try/catch.** An unguarded throw in the
  handler becomes an unhandled rejection → `installCrashHandlers()` → `process.exit(1)` = a
  *restart* of live web-1, strictly worse than a 503. Every path terminates in a 503 body.
- **Resolve `WORKSPACES_ROOT` once and pass it in.** `session-metrics.ts:9` caches it as a
  module-load `const` (NOT call-time — the v1 plan claim was wrong). If `readiness.ts` resolves
  call-time but delegates the count to the cached-root helper, the two signals can split-brain.
  Extract `countWorkspaceDirsAt(root)` and pass the once-resolved root to both.
- **Exclude `lost+found`.** A freshly-formatted ext4/xfs volume carries a root `lost+found` dir
  that passes the dir filters → would false-`populated` on a truly-empty volume. (Prod today
  mounts at `/mnt/data` with `/workspaces` a subdir, so `lost+found` is invisible there — but
  the generic `WORKSPACES_ROOT` default invites the direct-mount case; exclude it defensively.)
- **Gate on the transport peer, not the Host header.** `req.socket.remoteAddress` loopback is
  unspoofable off-host; the Host header is client-supplied. Keep `isLoopbackHost` as a secondary
  clause (e2e port-suffix tolerance) but it must not be the sole control.
- **Boot mirror ≠ per-call mirror.** Do NOT `reportSilentFallback` on every readyz call (LB/drain
  polling would flood Sentry). Mirror ONCE at boot via `verifyWorkspacesMountOnce` (latched).
  Note `verifyPluginMountOnce` checks the *plugin* mount, not `/workspaces` — it does not cover
  this surface, which is why this plan adds a dedicated boot check.
- **Flap-safety belongs in THIS plan.** Do not defer the "N≥2 consecutive not-ready before
  draining a live origin" contract to the out-of-scope GA LB PR — that lets fail-closed bias
  silently drain the sole origin on a single transient probe error. It is a hard AC + ADR line here.
- **`/health` MUST stay untouched.** The LB monitor is reachability-only on `/health` by
  design (shared Supabase). Do not add mount coupling to `/health` — that reintroduces the
  DB-blip-ejects-sole-origin failure the blue-green amendment forbids. Readiness is a
  *separate* endpoint precisely so `/health` stays liveness-only.
- **This is necessary-but-not-sufficient.** Shipping readyz does NOT relax the hard invariant
  (no live LB weight to web-2 before relay active AND git-data cut over). Do not let the
  runbook update imply readyz alone unlocks pooling.
- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan`
  Phase 4.6 — this section is filled with concrete artifact/vector/threshold above.
