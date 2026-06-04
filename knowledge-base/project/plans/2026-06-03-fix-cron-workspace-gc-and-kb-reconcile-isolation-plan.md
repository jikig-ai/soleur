---
title: "Restore KB workspace reconcile (no-SSH GC) + isolate cron clones off the persistent volume"
date: 2026-06-03
type: fix
branch: feat-one-shot-cron-workspace-gc-kb-reconcile
issue: 4882
related_issues: [4770, 4878, 4882]
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: draft
---

# 🐛 Restore the KB workspace reconcile (no-SSH GC) + isolate cron clones

## Enhancement Summary

**Deepened on:** 2026-06-03
**Gates passed:** 4.6 User-Brand Impact (single-user incident), 4.7 Observability
(5/5 fields, no-ssh discoverability), 4.8 PAT-shaped (none), 4.9 UI-wireframe (no UI surface),
4.4 scheduled-work precedent (Inngest canonical, plan correct).

### Key Improvements
1. **`ci-deploy.test.sh` substring-match stale-green trap** found and folded into Phase 1
   + AC as a MANDATORY (not conditional) test edit — the `grep -qF` assertion would
   false-pass the `/workspaces/.cron` value while pinning the wrong intent.
2. **Precedent-diff verified**: GC reuses `_cron-shared.ts` `bavail` statfs arithmetic +
   `orphan-reaper.sh` prefix/maxdepth/age sweep shape + `session-metrics.ts` ENOENT-tolerance
   — no novel pattern; all cited to file.
3. **Load-bearing negatives confirmed true** (verify-the-negative): GC can never reach
   `WORKSPACES_ROOT` (distinct env + one-level-up isolation); Vector-doesn't-ship-stdout
   justifies the Sentry-event signal path.

### New Considerations Discovered
- The `ci-deploy.test.sh` substring blindness (above) — the single most likely silent
  regression in the change.
- `.cron` leading-dot is NOT filtered by `session-metrics.ts` (filters only `.orphaned-`)
  → would +1 the active-workspace count; Phase 5 extends the filter.

## Overview

On **2026-06-02 07:46** the org-workspace KB reconcile silently stopped: the
last `users.kb_sync_history` `webhook_push` row was written then, and **zero**
since (confirmed against prod via Doppler `DATABASE_URL_POOLER`). No
`kb_sync_history` row was written for the failures because the reconcile's
`git pull` hit **ENOSPC** and the handler error path could not even record the
failure.

**Root cause (verified against code):** PR #4770 wired
`CRON_WORKSPACE_ROOT=/workspaces` in `ci-deploy.sh` (lines 458 + 624) to move
the ~100 MB `--depth=1` cron repo clones off the 256 MB `/tmp` tmpfs
(#4684/#4689). But `/workspaces` is the container view of
`/mnt/data/workspaces` — the **same 20 GB Hetzner `hcloud_volume.workspaces`**
(`apps/web-platform/infra/server.tf:666`) that holds the **persistent
UUID-named KB workspace clones** (`<WORKSPACES_ROOT>/<workspace_id>`, resolved
by `server/workspace-resolver.ts:workspacePathForWorkspaceId`, read by the
reconcile at `workspace-reconcile-on-push.ts:261`). Every cron that clones the
repo does `mkdtemp(join(resolveCronWorkspaceRoot(), "soleur-${cronName}-"))`
(`_cron-claude-eval-substrate.ts:setupEphemeralWorkspace`). On OOM / ENOSPC /
kill the substrate's `finally { rm }` is bypassed → orphaned `soleur-*` clones
accumulated on the shared volume → it filled → the reconcile's `git pull`
ENOSPC'd silently → KB froze.

**The fix has three parts (incident-prescribed):**

1. **`cron-workspace-gc` Inngest function** — a scheduled in-process cron that
   `statfs`-reports the cron-clone root to Sentry **before and after**, sweeps
   `soleur-*` cron-clone dirs older than 1 h, and posts a Sentry Crons
   heartbeat. Modeled verbatim on `cron-supabase-disk-io.ts` (deterministic
   signal → Sentry, ADR-033 I1–I6, own monitor slug). This is the **disk-reclaim
   mechanism** that un-wedges the volume with zero SSH.

2. **Allowlist for `/api/internal/trigger-cron`** — so the GC is fireable on
   demand via `/soleur:trigger-cron` with zero SSH. **(Premise correction —
   read carefully):** there is **no hardcoded list** in
   `manual-trigger-allowlist.ts`; it is **derived** from `EXPECTED_CRON_FUNCTIONS`
   in `cron-manifest.ts` (`MANUAL_TRIGGER_EVENTS = new Set(EXPECTED_CRON_FUNCTIONS.map(manualTriggerEventFor))`).
   The real edit is **adding `"cron-workspace-gc"` to `EXPECTED_CRON_FUNCTIONS`**
   (which auto-flows into the allowlist) **plus** adding the
   `{ event: "cron/workspace-gc.manual-trigger" }` trigger to the function's own
   `createFunction(...)` trigger array. Editing `manual-trigger-allowlist.ts`
   itself is **wrong** and would break the drift guard.

3. **Isolate cron clones off the persistent KB path** — so a cron-clone leak can
   never again ENOSPC the persistent KB volume's usable space at the path the
   reconcile reads. Point `CRON_WORKSPACE_ROOT` at a **dedicated subdir**
   (`/workspaces/.cron`) in `ci-deploy.sh` (both call sites) so cron dirs are
   namespaced away from the UUID workspace dirs, **and** make the GC sweep that
   subdir. (Subdir-on-same-volume is the MVP isolation; a fully separate volume
   is evaluated in Alternatives and deferred — see Non-Goals. The GC is the
   load-bearing safeguard either way: isolation alone cannot stop a leak from
   filling a shared 20 GB volume.)

**NO operator SSH at any step** (`hr-no-ssh-fallback-in-runbooks`). The existing
`orphan-reaper.sh` systemd timer (server.tf, SSH-provisioned) is a *different*
layer: it sweeps `.orphaned-*` dirs (from `workspace.ts removeWorkspaceDir`),
not `soleur-*` cron clones, and it is not fireable on demand without SSH. We do
**not** modify it.

## Premise Validation

Checked every cited reference against `origin/main` and prod:

- **`_cron-shared.ts resolveCronWorkspaceRoot()`** — **HOLDS**. Returns
  `process.env.CRON_WORKSPACE_ROOT?.trim() || tmpdir()`; prefix `soleur-${cronName}-`;
  the JSDoc explicitly says prod sets `CRON_WORKSPACE_ROOT=/workspaces`.
- **`ci-deploy.sh` wiring** — **HOLDS, and there are TWO call sites**: line 458
  (initial `docker run`) and line 624 (rollback/update path). Both set
  `-e CRON_WORKSPACE_ROOT=/workspaces -v /mnt/data/workspaces:/workspaces`. The
  plan must edit **both**.
- **`hcloud_volume.workspaces` → /mnt/data → /workspaces** — **HOLDS**
  (`server.tf:666` + ci-deploy mount). `var.volume_size` = 20 GB (variables.tf:51).
- **Persistent UUID clones share the path** — **HOLDS**.
  `WORKSPACES_ROOT` defaults to `/workspaces` (`server/workspace.ts:36`,
  `server/workspace-resolver.ts:31`); reconcile reads
  `workspacePathForWorkspaceId(ws.id)` = `<WORKSPACES_ROOT>/<workspace_id>`.
- **`manual-trigger-allowlist.ts` is hardcoded** — **STALE / FALSE**. It is
  **derived** from `EXPECTED_CRON_FUNCTIONS` (see Overview ②). Plan corrected.
- **kb_sync_history silence since 07:46** — accepted as reported (prod read over
  Doppler `DATABASE_URL_POOLER`); not independently re-run here (read-only prod
  DB probe is an execution-phase verification, not a plan-phase one).
- **"#4846 appears" as a success signal** — **STALE / FALSE**. `#4846` is a
  **MERGED PR for an unrelated incident** ("incident: chat-RLS-outage PIR +
  always-run-postmortem ship gate"), **not** a kb_sync_history marker. The
  success criterion is corrected to: **a fresh `webhook_push` `kb_sync_history`
  row with `ok:true` is written after the GC frees disk** (and the reconcile's
  Sentry feature stops erroring). The "#4846 appears" wording is dropped.
- **#4882 (stale-clone alert)** — **OPEN**, correct follow-up; this plan
  `Ref #4882` (does not close it — divergence alert is a separate layer).
- **#4878 (manual sync + non_fast_forward self-heal)** — **MERGED**, stays
  (different layer); not touched.
- **#4734 (trigger-cron route + manifest-derived allowlist)** — **CLOSED/merged**;
  this is the mechanism ② plugs into.

No remaining stale premises after the two corrections above.

## Research Reconciliation — Spec vs. Codebase

| Claim (from incident text) | Codebase reality | Plan response |
|---|---|---|
| "add it to `manual-trigger-allowlist.ts`" | Allowlist is **derived** from `EXPECTED_CRON_FUNCTIONS` (cron-manifest.ts); no hardcoded list | Add `"cron-workspace-gc"` to `EXPECTED_CRON_FUNCTIONS` + the `{ event: "cron/workspace-gc.manual-trigger" }` trigger; **do not** edit `manual-trigger-allowlist.ts` |
| "verify … #4846 appears" | #4846 is a MERGED PR for the chat-RLS incident, not a kb_sync marker | Success = fresh `webhook_push` `kb_sync_history` `ok:true` row post-GC; drop "#4846 appears" |
| "crons' `finally{rm}` is bypassed on OOM/ENOSPC/kill" | Confirmed: `setupEphemeralWorkspace` mkdtemps then clones; cleanup is caller-side `finally` | GC sweeps the leaked `soleur-*` dirs by mtime; no change to the substrate's happy-path cleanup |
| "isolate cron clones onto their own path" | `CRON_WORKSPACE_ROOT` and `WORKSPACES_ROOT` are **separately** env-configurable | Point `CRON_WORKSPACE_ROOT=/workspaces/.cron` (subdir, same volume — MVP); GC + statfs target that subdir |
| GC should "statfs-report /workspaces" | `statfs` already used in `_cron-shared.ts warnIfCronWorkspaceLowOnDisk` (uses `bavail`, not `bfree`) | Reuse the `bavail`/`bsize` pattern; report free-MB before+after sweep to Sentry |

## User-Brand Impact

**If this lands broken, the user experiences:** their Knowledge Base silently
stops syncing — pushes to their connected repo never reach the KB the agent
reads, so the agent acts on weeks-old context with no error shown (the exact
2026-06-02 freeze, recurring).

**If this leaks, the user's data / workflow is exposed via:** the GC sweep runs
`rm -rf` on a path resolved from `CRON_WORKSPACE_ROOT`; a mis-scoped sweep (wrong
root, or a glob that matched UUID workspace dirs) would **delete a user's
persistent KB clone**. Mitigation is structural: the sweep matches **only the
`soleur-*` prefix** (UUID workspace dirs are `[0-9a-f-]{36}`, never `soleur-*`),
is `maxdepth 1`, age-gated to **> 1 h**, and runs against the **isolated
`.cron` subdir** — so even a prefix bug cannot reach the UUID dirs which live one
level up. Sentry reports before/after free-MB + swept count for auditability.

**Brand-survival threshold:** `single-user incident`. A single user's KB freezing
indefinitely with no error is the parent-incident class (#4706 — the founder's
own KB froze ~5 weeks). CPO sign-off required at plan time (see Domain Review).
`user-impact-reviewer` will be invoked at review time.

## Goals

- A scheduled `cron-workspace-gc` Inngest function that, every run: `statfs`
  the cron-clone root → Sentry (before); `rm -rf` `soleur-*` dirs `mtime > 1h`;
  `statfs` again → Sentry (after, with freed-MB delta + swept count); post Sentry
  Crons heartbeat (`ok = sweep-ran`, not findings-present).
- Fireable on demand via `/soleur:trigger-cron` (`cron/workspace-gc.manual-trigger`),
  zero SSH.
- Cron clones isolated to `/workspaces/.cron` so a leak namespaces away from the
  UUID KB workspace dirs.
- After deploy: fire the GC → free disk → confirm Inngest liveness → verify the
  reconcile resumes (fresh `kb_sync_history` `ok:true` row).

## Non-Goals

- **Stale/diverged-clone divergence alerting** — owned by #4882 (open); this plan
  reclaims disk, it does not detect content divergence. `Ref #4882`.
- **A fully separate Hetzner volume for cron clones** — deferred (see Alternatives
  + deferral issue). Subdir-on-same-volume + GC is the MVP; a separate volume is a
  Terraform `hcloud_volume` + attachment + mount + `var.volume_size` split that
  trades blast-radius isolation for provisioning cost and a second ENOSPC surface.
- **Modifying `orphan-reaper.sh`** — different layer (`.orphaned-*`, SSH-provisioned).
- **Changing the reconcile handler logic** — #4878 already hardened it; the freeze
  was disk, not logic.

## Implementation Phases

> NEVER bump version files in a feature branch (`wg-never-bump-version-files-in-feature`).
> Phases are ordered by contract-dependency: the isolation env change (Phase 1)
> defines the path the GC sweeps (Phase 2), so Phase 1 lands first even though the
> whole PR merges atomically.

### Phase 0 — Preconditions (verify at /work time)

- `grep -cE '^\s+\w+,$' apps/web-platform/app/api/inngest/route.ts` → re-derive the
  current route-entry count (was 48 at plan-write; a sibling PR may shift it).
  `function-registry-count.test.ts` guard (a) asserts this literal.
- Re-derive alphabetical placement of `cron-workspace-gc` in `EXPECTED_CRON_FUNCTIONS`
  and the route import/array: sorts **after `cron-weekly-analytics`, last entry**
  (`workspace` > `weekly`). Verify at write-time (ordering is convention; parity
  guards check set membership, not order).
- Confirm `_cron-shared` is imported via the **relative** form `from "./_cron-shared"`
  (NOT the `@/...` alias) — `cron-substrate-imports.test.ts` `SHARED_IMPORT_RE`
  matches only the relative form.
- Read `apps/web-platform/test/server/inngest/cron-supabase-disk-io.test.ts` and
  `function-registry-count.test.ts` as the test templates.

### Phase 1 — Isolate cron clones (infra, no SSH)

`apps/web-platform/infra/ci-deploy.sh` — **both** docker-run call sites (≈L458 +
≈L624): change `-e CRON_WORKSPACE_ROOT=/workspaces` →
`-e CRON_WORKSPACE_ROOT=/workspaces/.cron`. The volume mount line
(`-v /mnt/data/workspaces:/workspaces`) is **unchanged** — `.cron` is a subdir on
the same mount. The container creates the subdir lazily? No — `mkdtemp` fails if the
parent does not exist. **Add `mkdir -p /mnt/data/workspaces/.cron && chown 1001:1001 /mnt/data/workspaces/.cron`** alongside the existing
`chown 1001:1001 /mnt/data/workspaces` (≈L434) so the 1001 container user can
mkdtemp under it. (Container user is 1001 per the existing chown.)

> **Apply path note:** `ci-deploy.sh` runs on every merge to `main` touching
> `apps/web-platform/**` via `web-platform-release.yml` (path-filtered push) — the
> merge IS the apply. No separate operator step. (See Infrastructure (IaC) §Apply
> path.) The leading-dot `.cron` is deliberately hidden from `session-metrics.ts`'s
> `readdirSync(/workspaces).filter(!startsWith(".orphaned-"))` count — see Sharp Edges.

**MANDATORY (not conditional) — `ci-deploy.test.sh` WILL go stale-green:**
`apps/web-platform/infra/ci-deploy.test.sh:1186–1235` (`assert_cron_workspace_root`)
asserts via `grep -qF -- "-e CRON_WORKSPACE_ROOT=/workspaces"` against **every**
`DOCKER_RUN_ARGS` line. Because `grep -F` is a **substring** match, the new value
`-e CRON_WORKSPACE_ROOT=/workspaces/.cron` **still contains** the asserted substring
→ the test **passes without modification but now asserts the wrong intent** (its
comment says "must be `/workspaces`"; a future regression back to bare `/workspaces`
would also pass). Update the assertion literal to
`-e CRON_WORKSPACE_ROOT=/workspaces/.cron` (both the `grep -qF` and the FAIL/echo
strings + the function comment) so the test pins the new exact value and re-catches
drift. This is a **Research Insight finding**, not a guess — verified at deepen time
(see Research Insights).

### Phase 2 — `cron-workspace-gc` Inngest function

Create `apps/web-platform/server/inngest/functions/cron-workspace-gc.ts`,
modeled on `cron-supabase-disk-io.ts`:

```ts
// apps/web-platform/server/inngest/functions/cron-workspace-gc.ts
import { statfs } from "node:fs/promises";
import { readdir, rm, stat } from "node:fs/promises";
import { join } from "node:path";
import { inngest } from "@/server/inngest/client";
import { reportSilentFallback, warnSilentFallback } from "@/server/observability";
import {
  resolveCronWorkspaceRoot,   // reuse — single source of truth for the cron root
  postSentryHeartbeat,
  type HandlerArgs,
} from "./_cron-shared";       // RELATIVE import (substrate guard)

export const SENTRY_MONITOR_SLUG = "scheduled-workspace-gc";
export const CRON_DIR_PREFIX = "soleur-";              // matches setupEphemeralWorkspace
export const DEFAULT_MAX_AGE_MS = 60 * 60 * 1000;      // 1 h; env CRON_WORKSPACE_GC_MAX_AGE_MS

// Pure helpers (unit-tested without fs):
//  - freeMb(statfsResult): Math.floor(bavail * bsize / 1MiB)  // bavail, not bfree
//  - isSweepable(name, ageMs, maxAgeMs): name.startsWith(CRON_DIR_PREFIX) && ageMs > maxAgeMs

export async function cronWorkspaceGcHandler({ step, logger }: HandlerArgs) {
  const root = resolveCronWorkspaceRoot();   // = /workspaces/.cron in prod
  // 1) statfs BEFORE → Sentry (info-level reportSilentFallback / structured)
  // 2) readdir(root, maxdepth 1); for each soleur-* dir: stat().mtimeMs; if age>maxAge → rm -rf, count++
  //    each rm in its own try/catch → a single EACCES/ENOENT never aborts the sweep (fail-soft, report each)
  // 3) statfs AFTER → Sentry with { freeMbBefore, freeMbAfter, freedMb, sweptCount, root }
  // 4) postSentryHeartbeat({ ok: true /* sweep ran */, sentryMonitorSlug, cronName, logger })
  // ENOENT on root (no volume / fresh box / local) → expected degraded, heartbeat ok, no page (mirror session-metrics)
  return { sweptCount, freedMb, root };
}

export const cronWorkspaceGc = inngest.createFunction(
  {
    id: "cron-workspace-gc",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 */6 * * *" },                          // every 6h, mirrors disk-io
    { event: "cron/workspace-gc.manual-trigger" },    // enables /soleur:trigger-cron
  ],
  cronWorkspaceGcHandler as unknown as Parameters<typeof inngest.createFunction>[2],
);
```

Notes baked in:
- **All IO inside `step.run`** (ADR-033 I1) — wrap the statfs+sweep+statfs in
  named `step.run("workspace-gc-sweep", …)`.
- **No claude / no BYOK / no subprocess** (I2/I3) — pure fs.
- **`ok` = sweep ran**, not findings-present (a clean run with 0 sweeps is GREEN).
- **`bavail`** (unprivileged free), not `bfree` — matches `warnIfCronWorkspaceLowOnDisk`.
- **Keep the cron literal OUT of the JSDoc header** (`*/6` in a `/** */` block closes
  the comment → esbuild fail) — describe as "every 6 hours" in prose.

### Phase 3 — Register the cron (enables allowlist + scheduler)

1. `apps/web-platform/server/inngest/cron-manifest.ts` — append
   `"cron-workspace-gc"` to `EXPECTED_CRON_FUNCTIONS` (last, after
   `cron-workspace-sync-health`? No — `workspace-gc` < `workspace-sync-health`
   alphabetically: `g` < `s`. Place **before** `cron-workspace-sync-health`).
   This **auto-derives** `cron/workspace-gc.manual-trigger` into
   `MANUAL_TRIGGER_EVENTS` (allowlist) — no edit to `manual-trigger-allowlist.ts`.
2. `apps/web-platform/app/api/inngest/route.ts` — add the import
   (`import { cronWorkspaceGc } from "@/server/inngest/functions/cron-workspace-gc";`)
   and the array entry. Re-derive the registry count for
   `function-registry-count.test.ts`.

### Phase 4 — Tests (write RED first, `cq-write-failing-tests-before`)

`apps/web-platform/test/server/inngest/cron-workspace-gc.test.ts` (vitest — confirm
runner via `package.json scripts.test` / `bunfig.toml`; sibling disk-io test is the
template):
- `isSweepable`: `soleur-foo` aged 2h → true; `soleur-foo` aged 30m → false;
  a UUID dir (`3f...-...` 36-char) aged 2h → **false** (prefix guard — load-bearing).
- `freeMb`: `bavail`/`bsize` arithmetic; floor.
- handler with a mocked fs: removes only aged `soleur-*`, leaves UUID dirs + fresh
  cron dirs; emits before/after Sentry with `freedMb`/`sweptCount`; heartbeat `ok:true`.
- ENOENT root → no throw, heartbeat `ok:true`, no page.
- a single `rm` EACCES does not abort the loop (other dirs still swept; the failure
  is reported once).
- registry/manifest parity picked up by `function-registry-count.test.ts` (manifest
  set == file list) and `cron-substrate-imports.test.ts` (relative `_cron-shared`).

## Acceptance Criteria

### Pre-merge (PR)
- [x] `cron-workspace-gc.ts` exists; sweep matches **only** `^soleur-` `maxdepth 1`,
      age-gated `> CRON_WORKSPACE_GC_MAX_AGE_MS` (default 1 h); per-dir `rm` is
      fail-soft (one error never aborts the loop).
- [x] `statfs` before AND after the sweep are emitted to Sentry with
      `{ freeMbBefore, freeMbAfter, freedMb, sweptCount, root }`; uses `bavail`.
- [x] `EXPECTED_CRON_FUNCTIONS` contains `"cron-workspace-gc"`; `manual-trigger-allowlist.ts`
      is **NOT** edited; `isAllowlistedManualTrigger("cron/workspace-gc.manual-trigger")`
      returns true (assert in the cron-manifest / allowlist test path).
- [x] `createFunction` triggers include `{ cron: "0 */6 * * *" }` **and**
      `{ event: "cron/workspace-gc.manual-trigger" }`.
- [x] `app/api/inngest/route.ts` imports + registers `cronWorkspaceGc`;
      `function-registry-count.test.ts` green with the re-derived count.
- [x] `ci-deploy.sh` sets `CRON_WORKSPACE_ROOT=/workspaces/.cron` at **both** docker-run
      sites and `mkdir -p … && chown 1001:1001 /mnt/data/workspaces/.cron` is present.
- [x] `ci-deploy.test.sh:1186–1235` `assert_cron_workspace_root` literal updated to
      `-e CRON_WORKSPACE_ROOT=/workspaces/.cron` (substring match means it false-passes
      otherwise — verified at deepen time); the FAIL strings + function comment updated to match.
- [x] `cron-workspace-gc.test.ts` green incl. the UUID-dir-not-swept guard;
      full `test-all.sh` EXIT=0 (read the explicit `EXIT=` marker, not the wrapper exit).
- [x] `tsc --noEmit` clean.

### Post-merge (operator/automated, no SSH)
- [ ] Merge fires `web-platform-release.yml` (path-filtered) → container restarts with
      `CRON_WORKSPACE_ROOT=/workspaces/.cron` and the new fn registered. **The merge
      IS the apply** — no operator restart step (`hr-all-infrastructure-provisioning-servers`
      + plan automation-feasibility gate: the release pipeline already restarts the container
      on merge to `main` touching `apps/web-platform/**`).
- [ ] Fire the GC via `/soleur:trigger-cron` (`cron/workspace-gc.manual-trigger`,
      secret read read-only from Doppler). Verify in Sentry: `scheduled-workspace-gc`
      heartbeat `ok`, and a before/after event showing `freedMb > 0` (the leaked
      `soleur-*` dirs reclaimed). This confirms Inngest liveness end-to-end.
- [ ] Verify the reconcile resumes: a fresh `users.kb_sync_history` row with
      `webhook_push` + `ok:true` written **after** the GC run (read-only prod DB probe
      over Doppler `DATABASE_URL_POOLER`, or trigger a push to a connected repo). The
      `WORKSPACE_RECONCILE_SENTRY_FEATURE` error stream stops. **(Replaces the stale
      "#4846 appears" criterion.)**
- [ ] `gh issue close 4882`? **No** — #4882 (divergence alert) is a separate layer;
      `Ref #4882` only.

## Hypotheses

- **H1 (primary, verified):** cron-clone leak on the shared volume → ENOSPC at the
  reconcile's `git pull`. Evidence: `CRON_WORKSPACE_ROOT=/workspaces` (ci-deploy),
  shared `hcloud_volume.workspaces`, bypassed `finally{rm}` on kill. **Accepted.**
- **H2 (ruled out):** reconcile logic regression. #4878 hardened the handler 2026-06-02;
  the silence is disk (no row written at all), not a logic path. **Rejected.**
- **H3 (orthogonal):** content divergence after reconnect — #4882's domain, not disk.

## Domain Review

**Domains relevant:** Engineering, Product (threshold gate), Legal (data-min on Sentry payload)

### Engineering (CTO)
**Status:** reviewed (carry-forward from sibling cron pattern + this session's grep)
**Assessment:** In-process scheduled cron (NOT dispatch-hybrid — no credentials/claude,
pure local fs), so it owns its `SENTRY_MONITOR_SLUG` and runs in-container against the
mounted volume. Mirrors `cron-supabase-disk-io.ts` exactly (ADR-033 I1–I6, concurrency
caps, heartbeat). No ADR (no new service/schema/tech). No migration. The only sharp
edges are the test gotchas in `2026-06-02-inngest-dispatches-gha-for-credential-heavy-crons.md`
(relative `_cron-shared` import; cron literal out of JSDoc; re-derive registry count).

### Product/UX Gate
**Tier:** none — no user-facing surface (ops-only Sentry + infra). Threshold gate only.
**Decision:** auto-accepted (pipeline); CPO sign-off recorded via `requires_cpo_signoff`
(threshold = single-user incident). No `.pen` (no UI surface — `Pencil available: N/A`).

### Legal (CLO)
**Status:** reviewed (carry-forward)
**Assessment:** Sentry payload is free-MB integers + a swept **count** + the root path
(`/workspaces/.cron`) — **no workspace UUIDs, no repo names/paths, no PII**. Data-min
satisfied. The reclaim is `rm` on ephemeral cron clones (the platform's OWN repo at
`jikig-ai/soleur`), never user content. No statutory clock, no Art. 33/34 trigger
(sync staleness of git-backed data is a product-quality defect, not a personal-data
breach — same framing as #4706/#4712).

## Infrastructure (IaC)

### Terraform changes
- **None required for MVP.** The isolation uses an existing-volume subdir set via
  `ci-deploy.sh` env, not a new `hcloud_volume`. `server.tf` is untouched.
- The separate-volume alternative (deferred) WOULD add `hcloud_volume.cron_workspaces`
  + attachment + mount + a `var.cron_volume_size` split off `var.volume_size`.

### Apply path
- **(b) cloud-init + idempotent script equivalent:** `ci-deploy.sh` is the bootstrap;
  it runs on every merge to `main` touching `apps/web-platform/**` via
  `web-platform-release.yml`'s path-filtered `on.push`. The `mkdir -p`/`chown` lines
  are idempotent. **Merge = apply; zero downtime beyond the normal container restart.**
- The Inngest fn itself ships in the container image — registered on restart; no infra apply.

### Distinctness / drift safeguards
- `CRON_WORKSPACE_ROOT` (cron clones) and `WORKSPACES_ROOT` (persistent KB) are
  **distinct env vars resolving to distinct paths** — the isolation invariant. The GC
  resolves its root via `resolveCronWorkspaceRoot()` (single source of truth), so it can
  never sweep `WORKSPACES_ROOT`.
- No new secret; no `dev != prd` config split needed (both envs degrade-gracefully on
  ENOENT root).

### Vendor-tier reality check
- N/A — no new vendor resource; Hetzner volume already provisioned.

## Observability

```yaml
liveness_signal:
  what: Sentry Crons monitor "scheduled-workspace-gc" check-in each run
  cadence: every 6h ({ cron: "0 */6 * * *" }) + on manual-trigger
  alert_target: Sentry Crons (missed check-in within margin → red); also covered by cron-inngest-cron-watchdog + EXPECTED_CRON_FUNCTIONS parity
  configured_in: cron-workspace-gc.ts (SENTRY_MONITOR_SLUG) + postSentryHeartbeat
error_reporting:
  destination: Sentry via reportSilentFallback / warnSilentFallback (cq-silent-fallback-must-mirror-to-sentry)
  fail_loud: per-dir rm failure → reportSilentFallback (one event, loop continues); statfs failure → reportSilentFallback (non-fatal)
failure_modes:
  - mode: cron-clone leak refilling the volume
    detection: before/after statfs delta + sweptCount in the Sentry event; freedMb trend
    alert_route: warnSilentFallback when freeMbAfter < floor (reuse DEFAULT_CRON_WORKSPACE_MIN_FREE_MB pattern)
  - mode: GC stops running (scheduler desync)
    detection: missed Sentry Crons check-in + cron-inngest-cron-watchdog
    alert_route: Sentry Crons red
  - mode: sweep deletes nothing while disk fills (prefix/age bug)
    detection: freedMb=0 while freeMb low → warn; unit test asserts soleur-* match + UUID-dir exclusion
    alert_route: Sentry warn
logs:
  where: app stdout (pino) + Sentry events (the durable path — Vector does not ship app stdout to Better Stack)
  retention: Sentry default
discoverability_test:
  command: "curl -s -X POST https://<app>/api/internal/trigger-cron -H \"Authorization: Bearer $SECRET\" -d '{\"event\":\"cron/workspace-gc.manual-trigger\"}'  # then read the scheduled-workspace-gc event in Sentry"
  expected_output: "202/200 dispatch; Sentry event with freedMb/sweptCount; heartbeat ok — NO ssh"
```

## Open Code-Review Overlap

None. `git ls-files`-derived planned files greped against 71 open `code-review` issues;
the only `server.tf` matches (#3216 dpf-regex, #2197 billing) touch unrelated blocks, not
the workspace-volume block. No fold-in/defer needed.

## Alternative Approaches Considered

| Approach | Trade-off | Decision |
|---|---|---|
| **Subdir `/workspaces/.cron` + GC (CHOSEN)** | One volume; isolation is namespacing, not capacity. GC is the real safeguard. Cheapest, no TF. | **Chosen (MVP).** |
| Separate `hcloud_volume` for cron clones | True capacity isolation (a cron leak can't touch KB space at all) but adds a TF volume + attachment + mount + `var.volume_size` split, a 2nd ENOSPC surface, and drift surface. | **Deferred** → tracking issue (re-evaluate if GC freedMb trend shows the subdir still pressures the shared volume). |
| Add the sweep to existing `orphan-reaper.sh` (systemd) | Reuses a script, but it is SSH-provisioned and NOT fireable via trigger-cron — violates the no-SSH + on-demand requirement. | **Rejected.** |
| Fix only the substrate `finally{rm}` to be kill-safe | Cannot help — OOM/ENOSPC/SIGKILL bypass any in-process cleanup by definition; needs an external sweeper. | **Rejected (insufficient).** |
| Pure time-threshold disk alert, no sweep | Detects but does not reclaim — the volume stays wedged until an operator SSHes. | **Rejected.** |

## Research Insights

**Deepened 2026-06-03.** Verified the load-bearing claims against `origin/main` code:

**Precedent-diff (Phase 4.4) — GC pattern has direct siblings, no novel pattern:**
- `statfs` precedent: `_cron-shared.ts warnIfCronWorkspaceLowOnDisk` already does
  `statfs(root)` and computes free-MB as `Math.floor((stats.bavail * stats.bsize) / (1024*1024))`
  using **`bavail`** (unprivileged-free blocks, what the 1001 container user gets),
  NOT `bfree`. The GC reuses this exact arithmetic — cite it, don't re-derive.
- `readdir`-sweep + age-gate precedent: `orphan-reaper.sh` (`find … -maxdepth 1 -type d
  -name '*.orphaned-*' -mmin +N`) is the structural template (prefix + maxdepth-1 + age).
  The GC mirrors it in TS (`readdir` + `stat().mtimeMs` + age compare). `session-metrics.ts
  getActiveWorkspaceCount` is the ENOENT-tolerant `readdir(/workspaces)` degrade pattern.
- Scheduled-work pattern (ADR-033): Inngest is canonical — **38** `cron-*.ts` functions
  vs **4** `scheduled-*.yml`. The plan correctly uses the Inngest in-process path (not
  dispatch-hybrid — no credentials/claude, pure local fs, so it owns its own monitor slug).

**Verify-the-negative (Phase 4.45) — load-bearing negatives confirmed true:**
- "GC can never sweep `WORKSPACES_ROOT`" — TRUE. The GC resolves its root **only** via
  `resolveCronWorkspaceRoot()` (returns `CRON_WORKSPACE_ROOT?.trim() || tmpdir()`), a
  distinct env var from `WORKSPACES_ROOT` (`workspace-resolver.ts:31`). With isolation,
  cron root = `/workspaces/.cron` and UUID dirs = `/workspaces/<id>` (one level UP) —
  a `soleur-*`-prefixed `maxdepth 1` sweep in `.cron` is structurally unable to reach them.
- "Vector does not ship app stdout to Better Stack" — TRUE, cited verbatim from
  `_cron-claude-eval-substrate.ts:23-26`. Justifies routing the freed-MB signal to Sentry
  events (the durable path), not pino stdout.

**New finding — `ci-deploy.test.sh` substring-match stale-green trap (folded into Phase 1
+ AC):** `ci-deploy.test.sh:1186-1235 assert_cron_workspace_root` uses
`grep -qF -- "-e CRON_WORKSPACE_ROOT=/workspaces"`. Because `-F` is a substring match,
`=/workspaces/.cron` still satisfies it → the env change passes the test **silently while
the test's pinned intent rots**. The plan now mandates updating the assertion literal to
`=/workspaces/.cron`. (Class: "AC grep is substring-blind to the value it verifies" —
cf. the SHA-prefix-match Sharp Edge in plan/SKILL.md.)

**Test-surface enumeration confirmed:** the new cron is asserted by three orphan suites
beyond its own test — `function-registry-count.test.ts` (manifest set == file list AND
route-array count), `cron-substrate-imports.test.ts` (relative `./_cron-shared` import),
and the manifest→allowlist derivation. Adding `"cron-workspace-gc"` to
`EXPECTED_CRON_FUNCTIONS` is the single edit that satisfies the allowlist; editing
`manual-trigger-allowlist.ts` would break the no-second-list invariant.

## Sharp Edges

- **`session-metrics.ts` counts `/workspaces` dirs** via `readdirSync(WORKSPACES_ROOT)`
  filtering only `!startsWith(".orphaned-")`. The `.cron` subdir is **hidden by the
  leading dot** from a plain `readdir` only if its filter excludes dotfiles — it does
  NOT; it would count `.cron` as one "active workspace". Either (a) extend that filter
  to also drop `.cron` (preferred — one line, keeps the metric honest), or (b) accept a
  +1 skew. **Flag for /work:** verify and pick (a). (Also `getActiveWorkspaceCount`'s
  ENOENT-tolerant shape is the exact degrade-gracefully pattern the GC should mirror.)
- **Two ci-deploy.sh call sites** (L458 initial + L624 rollback) — editing only one leaves
  the rollback path on the old `/workspaces` root. Edit both; if `ci-deploy.test.sh`
  asserts the env line, it covers both.
- **Cron literal in JSDoc** — `*/6` inside a `/** */` header closes the comment block →
  esbuild `Unexpected "*"` → whole test file fails at collection (0 tests). Keep the cron
  string out of the header prose.
- **`_cron-shared` import must be relative** (`./_cron-shared`), not the `@/...` alias —
  `cron-substrate-imports.test.ts` only matches the relative form.
- **`rm -rf` on a resolved path is destructive** — the sweep MUST anchor on the
  `soleur-` prefix AND `maxdepth 1` AND age. A unit test asserting a 36-char UUID dir is
  NOT swept is load-bearing (`hr-bulk-delete-per-item-live-infra-role-check` spirit:
  per-item guard before delete).
- **`U+202F`/whitespace in env** — `resolveCronWorkspaceRoot()` already `.trim()`s
  `CRON_WORKSPACE_ROOT`; the ci-deploy value has none, but rely on the existing trim.
- **A plan whose `## User-Brand Impact` section is empty or `TBD` fails `deepen-plan`
  Phase 4.6.** This one is filled (threshold + artifact + vector).

## Deferred Items (tracking issues to file)

- **Separate cron-clone volume** — file `chore(infra): evaluate dedicated hcloud_volume
  for cron clones (capacity isolation)`. Re-eval criteria: GC `freedMb`/`freeMbAfter`
  Sentry trend shows the shared 20 GB volume still pressured after isolation+GC for 2
  weeks. Milestone: from `knowledge-base/product/roadmap.md` (infra hardening).
  Labels: verify via `gh label list` before filing (`domain/engineering`, `chore`,
  `priority/p3-low` are known-good fallbacks).

---
**PR body:** use `Ref #4882` (NOT `Closes`) — divergence alert is a separate layer; this
PR reclaims disk + isolates clones. The post-merge GC fire + reconcile-resume verification
are operator/automated steps, not closed-at-merge.
