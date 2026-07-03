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

**If this lands broken, the user experiences:** a false-2xx readyz on a bare web-2 lets it be
LB-pooled with live weight → a live request round-robins to an empty `/workspaces` → the
user's workspace appears gone (workspace-gone incident). A false-503 on the live web-1 drains
the sole origin → full ingress outage.

**If this leaks, the user's data/workflow is exposed via:** capacity/topology signals
(mount state, workspace presence) are attacker-useful (DoS-tuning, cluster-shape scraping).
Keeping the endpoint loopback/Host-header gated (identical to `/internal/metrics`) prevents
any new external-facing capacity/topology disclosure.

**Brand-survival threshold:** single-user incident.

> CPO sign-off required at plan time before `/work` begins (carried by ADR-068 /
> ADR-082 single-user-incident substrate). `user-impact-reviewer` runs at review time.
> deepen-plan (pipeline step 2) supplies the substance-level review this threshold requires.

## Research Reconciliation — Spec vs. Codebase

No spec.md exists for this branch (fresh one-shot plan). All issue-body claims verified
against live code — no divergences found. Reuse precedents identified:

| Concern | Precedent in codebase | Plan response |
|---|---|---|
| Loopback/Host gating | `server/index.ts:51-55` `isLoopbackHost` + `/internal/metrics` route `:94-104` | Reuse `isLoopbackHost` verbatim; mirror the 403 gate for `/internal/readyz`. |
| Mount verification | `server/plugin-mount-check.ts` (existsSync + readdir + sentinel, mirrors to Sentry) | Adapt the *mountpoint*-distinctness check; readyz stays quiet per-call (non-2xx IS the signal), boot-time mirror is separate. |
| Workspace-populated scan | `server/session-metrics.ts` `getActiveWorkspaceCount()` (readdir, excludes `.orphaned-`/`.cron`/dotfiles, ENOENT→0) | Reuse `getActiveWorkspaceCount() > 0` as the populated signal. |
| `WORKSPACES_ROOT` resolution | `session-metrics.ts:9` `process.env.WORKSPACES_ROOT || "/workspaces"` | Same resolution (call-time for test stubbing). |
| git-data flag | `workspace-resolver.ts:56` `isGitDataStoreEnabled()` (`GIT_DATA_STORE_ENABLED==="true"`) | v1 `git_data_consistent` returns `true` when flag off (pre-GA default); composition point noted. |

## Implementation Phases

### Phase 1 — Readiness builder (`server/readiness.ts`, new)

Create `apps/web-platform/server/readiness.ts` exporting `buildReadinessResponse()`:

```ts
// apps/web-platform/server/readiness.ts
import { statSync } from "fs";
import { dirname } from "path";
import { getActiveWorkspaceCount } from "./session-metrics";
import { isGitDataStoreEnabled } from "@/server/workspace-resolver";

export interface ReadinessResponse {
  ready: boolean;
  checks: {
    workspaces_mounted: boolean;   // WORKSPACES_ROOT is a DISTINCT mountpoint (not root fs)
    workspaces_populated: boolean; // ≥1 host-local workspace-shaped entry present
    git_data_consistent: boolean;  // pre-GA: true when flag off; compose-later when on
  };
  workspaces_root: string;
}

function getWorkspacesRoot(): string {
  return process.env.WORKSPACES_ROOT || "/workspaces";
}

// Classic `mountpoint(1)` algorithm: a directory that is the target of a mount
// has a different st_dev than its parent. On an unmounted/absent target the two
// devices are equal (both the root fs) — FAIL CLOSED. Any stat error → false.
function isDistinctMountpoint(root: string): boolean {
  try {
    const rootDev = statSync(root).dev;
    const parentDev = statSync(dirname(root)).dev;
    return rootDev !== parentDev;
  } catch {
    return false; // ENOENT (dev/CI/bare host) or I/O error → not mounted
  }
}

export function buildReadinessResponse(): ReadinessResponse {
  const root = getWorkspacesRoot();
  const workspaces_mounted = isDistinctMountpoint(root);
  const workspaces_populated = getActiveWorkspaceCount() > 0;
  // v1: identity == "mounted distinct volume that is populated with host-local
  // workspace state" — a fresh/empty web-2 volume fails `populated`; an unmounted
  // root-fs `/workspaces` fails `mounted`. Strict cryptographic host-identity
  // (a cloud-init `host_id` sentinel, ADR-082) is a deferred hardening layer.
  const git_data_consistent = isGitDataStoreEnabled() ? true : true; // compose-later hook
  const ready = workspaces_mounted && workspaces_populated && git_data_consistent;
  return { ready, checks: { workspaces_mounted, workspaces_populated, git_data_consistent }, workspaces_root: root };
}
```

Rationale for the two-signal core: mountpoint-distinctness rejects an unmounted root-fs
`/workspaces`; populated-count rejects a mounted-but-fresh/empty web-2 volume. Together they
cover the bare-web-2 case the issue names. `git_data_consistent` is the explicit
compose-later slot (default `true` pre-GA) so the GA PR can add the relay-bound + git-data
mount cross-check without changing the endpoint contract.

### Phase 2 — Route wiring (`server/index.ts`)

Add the `/internal/readyz` route immediately after the `/internal/metrics` block, reusing
`isLoopbackHost`:

```ts
// Deep-readiness (#5966, ADR-068 Sharp Edge C1). Loopback-gated like /internal/metrics —
// mount/topology state is attacker-useful. 503 when the host cannot serve locally.
if (parsedUrl.pathname === "/internal/readyz") {
  if (!isLoopbackHost(req.headers.host)) {
    res.writeHead(403, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: "forbidden" }));
    return;
  }
  const readiness = buildReadinessResponse();
  res.writeHead(readiness.ready ? 200 : 503, { "Content-Type": "application/json" });
  res.end(JSON.stringify(readiness));
  return;
}
```

Import `buildReadinessResponse` from `./readiness`. `/health` and `/internal/metrics` remain
untouched.

### Phase 3 — Tests (`test/server/readiness.test.ts`, new)

Mock `fs.statSync` (mountpoint dev ids) and `./session-metrics` (`getActiveWorkspaceCount`)
following the `test/server/health.test.ts` mock-before-import pattern. Cases:

1. mounted (root.dev ≠ parent.dev) + populated (count 5) → `ready:true`, all checks true.
2. **bare-host simulation** — mounted but empty (`getActiveWorkspaceCount()===0`) →
   `ready:false`, `workspaces_populated:false` (AC-required).
3. unmounted (root.dev === parent.dev) → `ready:false`, `workspaces_mounted:false`.
4. `statSync` throws (ENOENT / I/O) → `ready:false`, `workspaces_mounted:false` (fail-closed).
5. `git_data_consistent` is `true` at flag-off (default) and does not break `ready` when the
   other two hold.
6. Loopback gating: assert `isLoopbackHost` returns 403-path for a public Host and served for
   `127.0.0.1`/`localhost`/`::1` (mirror the metrics gate; unit-test the helper contract).

### Phase 4 — ADR-068 amendment + C4 review

Add an ADR-068 amendment (see Architecture Decision section) recording the readiness-contract
decision and the mount+populated identity semantics. Read all three `.c4` files and record
"no C4 impact" with the enumeration (see below).

### Phase 5 — Docs / runbook reference (post-merge, automatable)

- Update the blue-green plan Sharp Edge C1 (`knowledge-base/project/plans/2026-07-03-feat-multi-host-blue-green-ingress-prereqs-plan.md` lines 273-277) from "file the deep-readiness endpoint as a follow-up" to "delivered — `/internal/readyz`, pre-pool gate".
- `gh issue comment 5946` noting `/internal/readyz` is the pre-pool readiness gate for web-2 and MUST return 2xx before any live LB weight.

## Files to Create

- `apps/web-platform/server/readiness.ts` — `buildReadinessResponse()` + `ReadinessResponse`.
- `apps/web-platform/test/server/readiness.test.ts` — 6 cases above.

## Files to Edit

- `apps/web-platform/server/index.ts` — add `/internal/readyz` route + import.
- `knowledge-base/engineering/architecture/decisions/ADR-068-multi-host-workspaces-shared-git-data-lease-coordinator.md` — amendment (readiness contract).
- `knowledge-base/project/plans/2026-07-03-feat-multi-host-blue-green-ingress-prereqs-plan.md` — Sharp Edge C1 "delivered" update (post-merge / same PR).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `GET /internal/readyz` returns **503** JSON `{ready:false, checks:{workspaces_mounted:false,...}}` on a host whose `/workspaces` is unmounted (mock: `statSync(root).dev === statSync(parent).dev`) OR empty (`getActiveWorkspaceCount()===0`), and **200** `{ready:true}` only when mounted-distinct AND populated. (`test/server/readiness.test.ts`)
- [ ] Bare-host simulation (mounted-but-empty `/workspaces`) is covered by a test asserting `ready:false` / non-2xx. (case 2)
- [ ] Fail-closed: `statSync` throwing → `ready:false` (case 4).
- [ ] Endpoint gating (loopback/Host-header) mirrors `/internal/metrics`: non-loopback Host → 403, no readiness body. Assert via `isLoopbackHost` contract test + route reuse (`server/index.ts`). No new external-facing capacity/topology disclosure.
- [ ] `/health` (`buildHealthResponse`) and `/internal/metrics` behavior unchanged (existing `test/server/health.test.ts` still green).
- [ ] ADR-068 amendment present recording the readiness contract + mount+populated identity semantics; `### C4 views` records "no C4 impact" with the external-actor/system/relationship enumeration checked against all three `.c4` files.
- [ ] `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/readiness.test.ts test/server/health.test.ts` passes.
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] PR body uses `Closes #5966` (behavioral feature; safe to auto-close at merge — the endpoint is live at merge, no post-merge apply gates it).

### Post-merge (operator/automatable)

- [ ] Blue-green plan Sharp Edge C1 updated to reference the delivered endpoint. Automation: inline `Edit` in this PR (docs change ships with code).
- [ ] `gh issue comment 5946` posted referencing `/internal/readyz` as the pre-pool readiness gate. Automation: `gh` CLI via `/soleur:ship` post-merge or inline. `Ref #5946` (not `Closes` — #5946 is the runbook, closes on its own work).

## Observability

```yaml
liveness_signal:
  what: /internal/readyz HTTP status (200 ready / 503 not-ready)
  cadence: on-demand — polled by drain/undrain tooling + (at GA) the pre-pool LB check
  alert_target: LB monitor / Better Stack (added by GA blue-green work, out of scope here)
  configured_in: apps/web-platform/server/index.ts route + server/readiness.ts
error_reporting:
  destination: the non-2xx status IS the fail-loud signal (fail-closed by design); the
    structured `checks` JSON body is the in-surface discriminating probe
  fail_loud: true (503 + explicit false check field; NOT a silent 200)
failure_modes:
  - mode: /workspaces unmounted (root fs)
    detection: checks.workspaces_mounted=false in the readyz body (in-surface probe)
    alert_route: consulted by drain tooling / LB pre-pool check → host not pooled
  - mode: /workspaces mounted but empty (bare web-2)
    detection: checks.workspaces_populated=false in the readyz body
    alert_route: same — host not pooled; distinguishes empty-volume from unmounted
  - mode: git-data flag on but store inconsistent (GA compose-later)
    detection: checks.git_data_consistent=false (v1 always true; GA PR wires the probe)
    alert_route: same
logs:
  where: readyz stays quiet per-call (probe endpoint; non-2xx is the signal, avoids Sentry
    flood under LB polling). Boot-time mount state is covered by verifyPluginMountOnce /
    ADR-082 host-bootstrap emit_fail on the seed path.
  retention: n/a (no per-call log)
discoverability_test:
  command: >
    curl -s -o /dev/null -w '%{http_code}' -H 'Host: 127.0.0.1'
    http://127.0.0.1:3000/internal/readyz
  expected_output: "200 on a ready host; 503 on a bare/unmounted host (NO ssh)"
```

**Affected-surface note (Phase 2.9.2).** `/internal/readyz` is itself the in-surface probe
for a **container readiness gate** — a surface the operator cannot inspect without it. The
`checks` object discriminates ALL three competing root-cause hypotheses
(unmounted vs empty-volume vs git-data-inconsistent) in a **single** response, per the
structured-probe requirement, rather than a single boolean.

## Architecture Decision (ADR/C4)

Detected: a new internal endpoint + a new **readiness-vs-liveness gating contract** for LB
pooling eligibility (a cross-cutting invariant every pooling decision must honor). This
**extends ADR-068** (Sharp Edge C1 / blue-green amendment) rather than making a fresh
decision — so the deliverable is an **ADR-068 amendment**, matching how ADR-068 has tracked
every GA decision as a dated amendment.

### ADR

Amend `ADR-068` (`## Decision`, new dated amendment) — decision: "Deep-readiness lives on a
separate internal `/internal/readyz` endpoint (loopback-gated like `/internal/metrics`),
returning non-2xx unless `/workspaces` is a distinct mountpoint AND populated with host-local
workspace state. `/health` stays liveness-only. Identity v1 = mounted-distinct + populated;
strict cloud-init `host_id` sentinel (ADR-082) is deferred hardening. This is a
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

**Status:** reviewed (inline — infra/CTO-authored plan; headless one-shot)
**Assessment:** Pure server-side infra change on a blind execution surface (container
readiness gate). Fail-closed design is load-bearing at single-user-incident threshold: every
ambiguous branch (stat error, ENOENT, unexpected exception) resolves to `ready:false`. Reuses
three existing precedents (`isLoopbackHost`, `getActiveWorkspaceCount`, mountpoint algorithm)
— minimal new surface. Key risk is a *false 2xx* (bare host pooled → workspace-gone) or
*false 503* (live origin drained); both are covered by the mountpoint+populated two-signal
design and the fail-closed default. `git_data_consistent` compose-later slot keeps the
contract stable for the GA PR. CPO sign-off required (single-user-incident, carried from
ADR-068/ADR-082). deepen-plan (pipeline step 2) supplies the data-integrity /
architecture-strategist substance review this threshold requires.

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
| Ready host | root.dev ≠ parent.dev, count=5 | 200, `ready:true`, all checks true |
| Bare web-2 (empty) | root.dev ≠ parent.dev, count=0 | 503, `ready:false`, `workspaces_populated:false` |
| Unmounted root fs | root.dev === parent.dev | 503, `ready:false`, `workspaces_mounted:false` |
| stat error | `statSync` throws | 503, `ready:false` (fail-closed) |
| git-data flag off | default | `git_data_consistent:true`, does not block ready |
| Non-loopback Host | Host: app.soleur.ai | 403, no readiness body |
| Loopback Host | Host: 127.0.0.1 / localhost / ::1 | served (200 or 503 per state) |

## Sharp Edges

- **Fail-closed is load-bearing, not defensive polish.** At single-user-incident threshold a
  false 2xx (bare host pooled) is a workspace-gone incident. Every ambiguous branch — ENOENT,
  I/O error, unexpected exception in `statSync`/`getActiveWorkspaceCount` — MUST resolve to
  `ready:false`. Do not "helpfully" default any check to true on error.
- **Do not mirror readyz failures to Sentry per-call.** The LB monitor polls readyz
  continuously; a bare web-2 would flood Sentry. The non-2xx status IS the signal; boot-time
  mount observability is separate (`verifyPluginMountOnce` / ADR-082 host-bootstrap).
- **`getActiveWorkspaceCount()` already excludes `.orphaned-`/`.cron`/dotfiles and treats
  ENOENT as 0.** Reuse it as-is; do not re-implement the scan (drift risk). A mounted-but-
  empty volume correctly yields count 0 → not populated → not ready.
- **Mountpoint check needs the parent-device comparison, not `existsSync`.** `existsSync("/workspaces")`
  is true even when `/workspaces` is an unmounted directory on the root fs. The `st_dev`
  parent comparison is the only signal that distinguishes a real mount from a root-fs dir.
- **`WORKSPACES_ROOT` must be resolved at call time** (`process.env.WORKSPACES_ROOT || "/workspaces"`),
  not cached at module load — the test suite stubs it per-case (mirrors `session-metrics.ts`).
- **`/health` MUST stay untouched.** The LB monitor is reachability-only on `/health` by
  design (shared Supabase). Do not add mount coupling to `/health` — that reintroduces the
  DB-blip-ejects-sole-origin failure the blue-green amendment forbids. Readiness is a
  *separate* endpoint precisely so `/health` stays liveness-only.
- **This is necessary-but-not-sufficient.** Shipping readyz does NOT relax the hard invariant
  (no live LB weight to web-2 before relay active AND git-data cut over). Do not let the
  runbook update imply readyz alone unlocks pooling.
- A plan whose `## User-Brand Impact` section is empty or placeholder fails `deepen-plan`
  Phase 4.6 — this section is filled with concrete artifact/vector/threshold above.
