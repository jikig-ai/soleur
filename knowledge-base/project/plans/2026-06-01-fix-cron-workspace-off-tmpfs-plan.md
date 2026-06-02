---
title: "fix: relocate cron ephemeral workspaces off the 256 MB /tmp tmpfs onto /workspaces"
date: 2026-06-01
type: fix
branch: feat-one-shot-cron-workspace-off-tmpfs-4684
issues: [4684, 4689]
lane: cross-domain
brand_survival_threshold: none
status: ready
---

# fix: relocate cron ephemeral workspaces off the 256 MB `/tmp` tmpfs onto `/workspaces`

## Overview

Scheduled cron producers (`cron-content-generator`, `cron-roadmap-review`,
`cron-campaign-calendar`, and the other 21 substrate-based crons) fail with
`git clone: No space left on device` (ENOSPC). The shared cron substrate
`apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts`
(lines 109-110) creates its ephemeral workspace with
`mkdtemp(join(tmpdir(), \`soleur-${cronName}-\`))`. In prod, `os.tmpdir()`
resolves to the container `/tmp`, mounted by
`apps/web-platform/infra/ci-deploy.sh` as a **256 MB tmpfs**
(`--tmpfs /tmp:rw,nosuid,nodev,size=256m`, both the canary block at line 453
and the prod block at line 617; added in #2473 to cap overlayfs COW
write-amplification — never sized for repo clones). A `git clone --depth=1` of
the soleur working tree (~100 MB, `knowledge-base/` alone 79 MB and growing
every content PR) plus the shallow pack + checkout peak, and for
content-generator an in-run `npx @11ty/eleventy` build, exceeds 256 MB → ENOSPC.

**Root cause is CONFIRMED — this plan does NOT re-investigate it.** Evidence:
Sentry `WEB-PLATFORM-17` ("No space left on device", 6× since 2026-05-31 08:00,
grouping `cron-content-generator` AND `cron-campaign-calendar`); Better Stack
host filesystem metrics showed the host root volume flat at 27.2% (56 GB free)
throughout the window — host metrics are structurally blind to the container
tmpfs.

The fix: the platform **already** mounts the roomy volume
`-v /mnt/data/workspaces:/workspaces` (chowned `1001:1001`) in both docker run
blocks and uses it for USER workspaces; crons just never pointed at it. Resolve
the `mkdtemp` parent from a new env var `CRON_WORKSPACE_ROOT` (default
`os.tmpdir()`), wire `-e CRON_WORKSPACE_ROOT=/workspaces` on both docker run
blocks, and add a unit test for the base-dir resolution. One additional change
folded in: a **pre-clone free-space guard** that emits a Sentry warning before
ENOSPC, closing the observability blind-spot that let this class of failure run
6× before a human noticed.

This is a disk fix, not a turns fix. **Do NOT touch the cron prompts or
`--max-turns` / `MAX_TURN_DURATION_MS`** for any cron (the prompt anchors are
test-locked in `cron-roadmap-review.test.ts` / `cron-content-generator.test.ts`).

## Premise Validation

- **#4684** (`[cloud-task-silence] content-generator silent`) — verified OPEN
  via `gh issue view`. Premise holds.
- **#4689** (`[cloud-task-silence] roadmap-review silent`) — verified OPEN.
  Premise holds.
- **`_cron-claude-eval-substrate.ts:109-110`** — verified: `mkdtemp(join(tmpdir(), \`soleur-${cronName}-\`))` exact match. `import { tmpdir } from "node:os"` at line 4.
- **`ci-deploy.sh`** — verified: canary docker run block 448-460 and prod block
  612-625 both carry `--tmpfs /tmp:rw,nosuid,nodev,size=256m`,
  `-e INNGEST_BASE_URL=http://host.docker.internal:8288`, and
  `-v /mnt/data/workspaces:/workspaces`. The `-e CRON_WORKSPACE_ROOT` env line
  to be added mirrors the existing `-e INNGEST_BASE_URL` line exactly.
- **`ci-deploy.test.sh`** — verified: has structured `assert_tmpfs_flag` +
  `assert_apparmor_profile` helpers asserting per-docker-run-line flags
  (lines 1074-1182). A new `assert_cron_workspace_root` helper follows that
  exact pattern.
- **`/workspaces` collision** — verified safe: user workspaces are
  `/workspaces/<userId>/*` (UUID dirs per `server/workspace.ts`); crons create
  `/workspaces/soleur-<cronName>-XXXXXX/` (mkdtemp-suffixed, `soleur-` prefix).
  Distinct namespaces — no collision.
- **`statfs` API** — verified present in `node:fs/promises` (Node types
  `fs/promises.d.ts:833`), so the free-space guard needs no new dependency.

## Research Reconciliation — Spec vs. Codebase

The feature description's three "secondary observability gaps" were authored
against an earlier substrate. Two of the three are **already shipped**; the plan
reconciles against current `main` rather than re-implementing them.

| Description claim | Codebase reality (current `main`) | Plan response |
|---|---|---|
| "`stderrTail` capture returned EMPTY … consider capturing a bounded redacted stdout tail and/or surfacing `exitCode` in `scheduled-output-missing`" | `stderrTail` IS already captured (`_cron-claude-eval-substrate.ts:209-237`) and folded into the `scheduled-output-missing` Sentry extra (`_cron-shared.ts:268`). `spawnOk` is in the extra (`:265`) but the **raw `exitCode` is NOT**, and the max-turns notice (claude `--print` writes it to **stdout**) is still not captured into `stderrTail` (stdout goes only to `logger.info` at `:225`). | Fold in the **cheap half**: add `exitCode` to the `scheduled-output-missing` extra (one-line, the value is already in `SpawnResult`). **Defer** stdout-tail capture to a follow-up issue (it touches the readline path + a new cap constant + redaction; out of scope for a disk fix and not load-bearing for ENOSPC). |
| "betterstack runbook says Vector ships 'host metrics' … worth a one-line correction" | The runbook **already has** a `## Known coverage gap (discovered 2026-06-01)` section (`betterstack-log-query.md:66-73`) stating the app pino stdout is not shipped. It does **not** yet state that `_metrics` stores empty AggregateFunction values (metric JSON lives in `_logs` `raw`) or that it sees only HOST filesystems, not container tmpfs. | Append the **container-tmpfs / `_metrics`-emptiness** clarification to the existing section — this is the load-bearing correction for THIS incident (host metrics blind to the tmpfs). |
| "pre-clone free-space guard emitting a Sentry warning" | No disk-space guard exists in the substrate. `pdf-linearize.ts` has a concurrency gate but no free-space check. `statfs` is available. | **Fold in.** This is the observability fix that would have surfaced the incident before 6 silent failures. Cheap, self-contained, emits a non-paging WARN (`cron-workspace-low-disk`) when the resolved workspace root has less free space than a configurable floor. |

## User-Brand Impact

**If this lands broken, the user experiences:** scheduled content/roadmap/
campaign artifacts silently stop being produced (the marketing blog, roadmap
review issues, and campaign calendar go stale) — the exact silent-no-op the
`cloud-task-silence` issues describe. A bad `CRON_WORKSPACE_ROOT` value (e.g.
an unwritable path) would make EVERY substrate cron fail clone, a strict
regression from "some crons fail under disk pressure".

**If this leaks, the user's data / workflow is exposed via:** N/A — no
user-facing data surface is touched. The ephemeral workspace is a server-side
git clone of the public `jikig-ai/soleur` repo; the installation token is
already redacted at the clone-failure boundary (`redactToken`, unchanged) and
in the spawn stdout/stderr (unchanged). Relocating the clone from `/tmp` to
`/workspaces` (same container, same `1001:1001` owner, same teardown) does not
widen any exposure.

**Brand-survival threshold:** none — internal cron infrastructure; no
user-facing surface, no regulated data, no auth/payment path. The
`threshold: none` is justified because the diff touches only
`apps/*/server/inngest/functions/`, `apps/*/infra/*.sh`, a runbook, and a test;
none match the preflight Check 6 sensitive-path set.

## Implementation Phases

### Phase 1 — Substrate base-dir resolution (`_cron-claude-eval-substrate.ts`)

Contract change first (consumers in Phase 2/3 depend on it).

1. Add an exported helper resolving the workspace root from env, defaulting to
   `os.tmpdir()` when unset:
   ```ts
   // apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts
   /**
    * Base dir for the ephemeral cron workspace. In prod, ci-deploy.sh sets
    * CRON_WORKSPACE_ROOT=/workspaces (the roomy /mnt/data volume) so the
    * git clone of the ~100 MB soleur tree does not exhaust the 256 MB /tmp
    * tmpfs (#4684/#4689). Unset → os.tmpdir() preserves local/CI/test behavior.
    */
   export function resolveCronWorkspaceRoot(): string {
     return process.env.CRON_WORKSPACE_ROOT?.trim() || tmpdir();
   }
   ```
2. Change line 109-110 to use it as the `mkdtemp` parent, keeping the
   `soleur-${cronName}-` prefix (distinct from user-workspace UUID dirs under
   `/workspaces`, so no collision):
   ```ts
   const ephemeralRoot = await mkdtemp(
     join(resolveCronWorkspaceRoot(), `soleur-${cronName}-`),
   );
   ```
3. **Pre-clone free-space guard** (fold-in observability fix). After computing
   `ephemeralRoot` and BEFORE the `git clone`, statfs the workspace root and
   emit a non-paging WARN if free space is below a floor. Must NOT throw — it is
   a warning, not a gate (a wrong floor must never block a clone that would
   otherwise succeed):
   ```ts
   import { mkdtemp, rm, ... , statfs } from "node:fs/promises"; // add statfs

   // Soft floor: the soleur working tree is ~100 MB and grows; warn under 256 MB
   // free so the operator sees the squeeze BEFORE ENOSPC kills the clone. Tunable
   // via CRON_WORKSPACE_MIN_FREE_MB (parsed, NaN → default). Non-fatal.
   export const DEFAULT_CRON_WORKSPACE_MIN_FREE_MB = 256;
   // ... inside setupEphemeralWorkspace, after mkdtemp, before clone:
   try {
     const fs = await statfs(ephemeralRoot);
     const freeMb = Math.floor((fs.bavail * fs.bsize) / (1024 * 1024));
     const floorMb = Number(process.env.CRON_WORKSPACE_MIN_FREE_MB) ||
       DEFAULT_CRON_WORKSPACE_MIN_FREE_MB;
     if (freeMb < floorMb) {
       warnSilentFallback(
         new Error(
           `cron workspace root low on disk: ${freeMb} MB free < ${floorMb} MB floor at ${ephemeralRoot} — git clone may ENOSPC`,
         ),
         {
           feature: cronName,
           op: "cron-workspace-low-disk",
           message: "Cron ephemeral workspace low on free disk before clone",
           extra: { fn: cronName, ephemeralRoot, freeMb, floorMb },
         },
       );
     }
   } catch (err) {
     // statfs failure is itself non-fatal — never block a clone on a probe error.
     reportSilentFallback(err, {
       feature: cronName,
       op: "cron-workspace-statfs-failed",
       message: "Could not statfs cron workspace root (non-fatal)",
       extra: { fn: cronName, ephemeralRoot },
     });
   }
   ```
   Note: `warnSilentFallback` is already imported pattern in `_cron-shared.ts`;
   import it from `@/server/observability` alongside the existing
   `reportSilentFallback` import (line 8). Verify the named export exists in
   `observability.ts` at /work time (grep) before wiring.
4. **Teardown is unchanged** — `teardownEphemeralWorkspace` already
   `rm -rf`s the specific `ephemeralRoot` mkdtemp dir (line 163), which is
   correct regardless of parent. All ADR-033 invariants (I1-I6) and the
   redaction / clone-failure-reporting behavior are preserved (no change to
   `spawnSimple`, `buildAuthenticatedCloneUrl`, `redactToken`, or the
   `spawnCwd`/symlink/manifest-sentinel logic).

### Phase 2 — Surface `exitCode` in `scheduled-output-missing` (`_cron-shared.ts`)

Reconciliation fold-in (cheap half of observability gap #2). The
`scheduled-output-missing` extra already carries `spawnOk` and `stderrTail`;
add the raw `exitCode` so a turn-exhaustion vs hard-failure distinction is
visible without SSH. `resolveOutputAwareOk` already receives the spawn result
context; thread `exitCode?: number | null` into its args alongside the existing
`stderrTail`, and add it to the `scheduled-output-missing` `extra` object
(around `_cron-shared.ts:261-269`).

**Call-site scope (verified at plan-write time, do NOT trust from memory):**
`grep -rn "resolveOutputAwareOk(" functions/` returns **8** call sites:
`cron-growth-audit.ts:212`, `cron-roadmap-review.ts:288`,
`cron-competitive-analysis.ts:262`, `cron-campaign-calendar.ts:215`,
`cron-seo-aeo-audit.ts:241`, `cron-content-generator.ts:211`,
`cron-community-monitor.ts:309`, `cron-growth-execution.ts:249`. Of these, only
**4** currently pass `stderrTail` (`cron-content-generator`,
`cron-roadmap-review`, `cron-competitive-analysis`,
`cron-follow-through-monitor` — note the last builds its own SpawnResult and may
not route through `resolveOutputAwareOk`). Because `exitCode` is an **optional**
arg (`exitCode?: number | null`), the 4 sites NOT already passing `stderrTail`
need no change — they simply omit it and the extra records `undefined`, exactly
as `stderrTail` is undefined for them today. **Only the 4 sites that already
pass `stderrTail` get `exitCode` added** (they already hold the `SpawnResult`).
Re-grep at /work time and confirm each of the 4 has `result.exitCode` in scope
before threading. Stdout-tail capture is **deferred** to a follow-up issue (see
Deferred Items).

### Phase 3 — Wire `CRON_WORKSPACE_ROOT` in both docker run blocks (`ci-deploy.sh`)

Add `-e CRON_WORKSPACE_ROOT=/workspaces \` to BOTH docker run blocks, mirroring
the existing `-e INNGEST_BASE_URL=...` line. Do NOT change the
`--tmpfs /tmp:...:size=256m` line (intentional per #2473).

- Canary block: insert after line 456 (`-e INNGEST_BASE_URL=...`).
- Prod block: insert after line 620 (`-e INNGEST_BASE_URL=...`).

```sh
      -e INNGEST_BASE_URL=http://host.docker.internal:8288 \
      -e CRON_WORKSPACE_ROOT=/workspaces \
      -v /mnt/data/workspaces:/workspaces \
```

The `/mnt/data/workspaces` host dir is already chowned `1001:1001` at
`ci-deploy.sh:434` (`sudo chown 1001:1001 /mnt/data/workspaces`), so the
container's `1001` user can `mkdtemp` under `/workspaces`. No new mount, no new
chown.

### Phase 4 — Tests

1. **Substrate base-dir unit test** — extend the existing real-spawn test at
   `apps/web-platform/test/server/inngest/cron-claude-eval-substrate.test.ts`
   (this path matches the vitest `include: ["test/**/*.test.ts"]` glob;
   `bunfig.toml` blocks bun discovery, runner is vitest). Add a
   `describe("resolveCronWorkspaceRoot")` block:
   - env set → returns the env value (set `process.env.CRON_WORKSPACE_ROOT`,
     assert equality, restore in `afterEach`).
   - env unset → returns `os.tmpdir()` (delete the env var, assert
     `=== tmpdir()`).
   - env set to whitespace-only → falls back to `tmpdir()` (the `.trim() || `
     guard).
   Follow `cq-test-fixtures-synthesized-only` — no live tokens; the helper is
   pure env→string, no spawn needed. Optionally assert
   `setupEphemeralWorkspace` honors the root by pointing
   `CRON_WORKSPACE_ROOT` at an `mkdtemp`'d temp dir and asserting the returned
   `ephemeralRoot` is under it — but this requires a real `git clone`, so keep
   it behind the same offline-safe pattern the file already uses, or assert
   only the pure helper (preferred — the clone is not the unit under test).
2. **ci-deploy.test.sh assertion** — add `assert_cron_workspace_root` mirroring
   `assert_tmpfs_flag` (lines 1125-1182): for every `docker run` line, assert it
   contains `-e CRON_WORKSPACE_ROOT=/workspaces`. Register the assertion call
   next to the existing `assert_tmpfs_flag` invocation (line 1182).
3. **Substrate-imports guard** — no change needed; the new exports
   (`resolveCronWorkspaceRoot`, `DEFAULT_CRON_WORKSPACE_MIN_FREE_MB`) are not in
   the `FORBIDDEN_EVAL_LOCAL_DEFS` list and the guard only forbids LOCAL
   redefinition in `cron-*.ts` handlers, not new substrate exports.

### Phase 5 — Runbook correction (`betterstack-log-query.md`)

Append to the existing `## Known coverage gap (discovered 2026-06-01)` section
(do NOT create a new section): one-to-two lines clarifying that (a) the
`_metrics` table stores empty `AggregateFunction` values — metric values live as
JSON in the `_logs` `raw` column — and (b) the Vector host-metrics source sees
only HOST filesystems, **not** the container `/tmp` tmpfs, which is why the
256 MB-tmpfs ENOSPC (#4684/#4689) was invisible to Better Stack while the host
root showed 56 GB free.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `_cron-claude-eval-substrate.ts` exports `resolveCronWorkspaceRoot()`;
      `mkdtemp` parent is `resolveCronWorkspaceRoot()` not `tmpdir()` directly;
      `soleur-${cronName}-` prefix unchanged. (`grep -n resolveCronWorkspaceRoot`
      shows the export AND the use at the mkdtemp call.)
- [x] Pre-clone `statfs` guard emits `op: "cron-workspace-low-disk"` WARN when
      free < floor and `op: "cron-workspace-statfs-failed"` on probe error;
      neither throws (the clone still runs). (Code review: no `throw` in the
      guard block.)
- [x] `scheduled-output-missing` Sentry `extra` includes `exitCode`
      (`grep -n exitCode _cron-shared.ts` shows it in the extra object).
- [x] `ci-deploy.sh` canary AND prod docker run blocks each contain exactly one
      `-e CRON_WORKSPACE_ROOT=/workspaces` line; the `--tmpfs /tmp:…size=256m`
      line is byte-for-byte unchanged.
      (`grep -c 'CRON_WORKSPACE_ROOT=/workspaces' ci-deploy.sh` → 2;
      `grep -c 'tmpfs /tmp:rw,nosuid,nodev,size=256m' ci-deploy.sh` → 2.)
- [x] `ci-deploy.test.sh` `assert_cron_workspace_root` passes against both
      docker run lines (run `bash apps/web-platform/infra/ci-deploy.test.sh`).
- [x] Substrate unit test asserts env-set → env value, env-unset → `tmpdir()`,
      whitespace → `tmpdir()`. (`./node_modules/.bin/vitest run test/server/inngest/cron-claude-eval-substrate.test.ts` green.)
- [x] No change to any cron prompt or `--max-turns` / `MAX_TURN_DURATION_MS`.
      (`git diff` touches no `*.prompt` text and no turn/duration constant;
      `cron-roadmap-review.test.ts` and `cron-content-generator.test.ts`
      prompt-anchor assertions remain green.)
- [x] `betterstack-log-query.md` coverage-gap section gains the container-tmpfs
      + `_metrics`-emptiness clarification.
- [x] PR body uses `Closes #4684` and `Closes #4689` (code fix lands at merge;
      no post-merge prod-write step — the deploy IS the remediation, see below).

### Post-merge (operator)

- [ ] None requiring manual action. The `web-platform-release.yml` pipeline
      path-filters on `apps/web-platform/**` and re-runs `ci-deploy.sh` on merge
      to `main`, recreating the container with `-e CRON_WORKSPACE_ROOT=/workspaces`.
      The PR merge IS the remediation (per the automation-feasibility gate:
      container restart / re-deploy is handled by the release pipeline).
- [ ] Verification (automatable, fold into `/soleur:ship` post-merge): after the
      next deploy, confirm the env var is set on the running container via the
      deploy webhook or an `inngest.send` manual trigger of one cron + a Sentry
      check that no new `WEB-PLATFORM-17` ("No space left") events fire for the
      substrate crons. No SSH.

## Observability

```yaml
liveness_signal:
  what: "Each substrate cron's existing output-aware heartbeat (issue created in run window) + Sentry cron monitor; unchanged by this fix."
  cadence: "per cron schedule (Inngest)"
  alert_target: "Sentry cron monitors + cloud-task-silence GitHub issue auto-filer"
  configured_in: "_cron-shared.ts resolveOutputAwareOk + per-cron SENTRY_MONITOR_SLUG"
error_reporting:
  destination: "Sentry via reportSilentFallback / warnSilentFallback (@/server/observability)"
  fail_loud: "yes — ENOSPC clone failures already surface as scheduled-output-missing with stderrTail; this fix adds a PRE-failure cron-workspace-low-disk WARN and an exitCode field."
failure_modes:
  - mode: "Workspace root low on disk (pre-ENOSPC)"
    detection: "statfs(ephemeralRoot).bavail*bsize < floor"
    alert_route: "Sentry WARN op=cron-workspace-low-disk (non-paging)"
  - mode: "git clone ENOSPC (the bug being fixed)"
    detection: "spawnSimple non-zero exit; stderr folded into thrown Error"
    alert_route: "Sentry scheduled-output-missing extra.stderrTail + extra.exitCode"
  - mode: "statfs probe failure"
    detection: "statfs throws"
    alert_route: "Sentry reportSilentFallback op=cron-workspace-statfs-failed (non-fatal)"
  - mode: "CRON_WORKSPACE_ROOT set to unwritable path (regression)"
    detection: "mkdtemp throws ENOENT/EACCES → clone setup throws"
    alert_route: "existing setup-workspace error path → Sentry; caught next deploy via cron monitor RED"
logs:
  where: "app pino stdout (fn: cron-<name>) — NOT shipped to Better Stack today (documented gap); Sentry carries the diagnostic extras"
  retention: "Sentry default; container journal local"
discoverability_test:
  command: "./node_modules/.bin/vitest run test/server/inngest/cron-claude-eval-substrate.test.ts && bash apps/web-platform/infra/ci-deploy.test.sh"
  expected_output: "both green; ci-deploy.test asserts CRON_WORKSPACE_ROOT on both docker run lines"
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal cron/infrastructure change.
No user-facing surface, no regulated data, no auth/payment path. Product domain
NOT relevant (no UI, no flow). Engineering/ops only.

## Infrastructure (IaC)

The `-e CRON_WORKSPACE_ROOT=/workspaces` flag is added to `ci-deploy.sh`, which
is the existing deploy mechanism invoked by `web-platform-release.yml` on merge.
The `/mnt/data/workspaces` volume and its `1001:1001` chown already exist in
`ci-deploy.sh` (cloud-init-provisioned host dir) — no new Terraform resource, no
new server, no new secret, no new vendor. **This is a code/config change against
already-provisioned infra → IaC routing gate skipped.** The apply path is the
normal release pipeline (re-runs `ci-deploy.sh`, recreates the container); no
`terraform apply`, no SSH, no operator dashboard step.

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` queried; no open
scope-out references `_cron-claude-eval-substrate.ts`, `_cron-shared.ts`,
`ci-deploy.sh`, or `betterstack-log-query.md`.)

## Deferred Items

- **Stdout-tail capture for the max-turns notice** — claude `--print` writes the
  max-turns notice to **stdout**, which `spawnClaudeEval` sends only to
  `logger.info` (not into `stderrTail`). Capturing a bounded redacted stdout
  tail would make a turn-exhaustion exit self-diagnosing in Sentry. Deferred: it
  touches the readline path, a new cap constant, and redaction symmetry — out of
  scope for a disk fix, not load-bearing for ENOSPC. **File a follow-up issue**
  (label `type/bug` + `domain/engineering`; re-evaluate if a turn-exhaustion
  exit recurs undiagnosably) with: what was deferred, why, the
  `_cron-claude-eval-substrate.ts:222-230` insertion point, and a
  `STDOUT_TAIL_CAP_BYTES` sketch.
- **Route app pino stdout into Vector / Better Stack** — already noted as a
  follow-up in the runbook coverage-gap section; not opened here. Confirm the
  tracking issue exists at /work time; if not, file one.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan`
  Phase 4.6. This plan's threshold is `none` with a sensitive-path scope-out
  justification — verify it stays filled.
- `statfs` returns `bavail` (blocks available to **unprivileged** users), not
  `bfree` (total free blocks). Use `bavail` — the container runs as `1001`, not
  root, and `bavail` reflects the space `1001` can actually claim. Do not swap to
  `bfree`.
- The free-space guard must be **non-fatal**. A wrong `CRON_WORKSPACE_MIN_FREE_MB`
  floor or a `statfs` error must NEVER block a clone — both paths are
  warn-and-continue. A guard that throws would convert an observability
  improvement into a new outage class (the "relax a load-bearing defense" trap,
  inverted: do not add a NEW gate where only a warning was asked for).
- `-e CRON_WORKSPACE_ROOT=/workspaces` must be added to BOTH docker run blocks.
  Adding it to only one (e.g., prod but not canary) means the canary health probe
  runs a cron substrate under `/tmp` and the prod container under `/workspaces` —
  a silent environment skew. The `assert_cron_workspace_root` test (one assertion
  over ALL docker run lines, mirroring `assert_tmpfs_flag`) is the gate against
  this — do not scope the assertion to a single line.
- The substrate unit test must live under `test/**/*.test.ts` (vitest
  `include` glob); a co-located `server/**/*.test.ts` would be silently skipped,
  and `bunfig.toml` blocks `bun test` discovery entirely. Extend the existing
  `test/server/inngest/cron-claude-eval-substrate.test.ts`.
- Do NOT add `exitCode` to the `scheduled-output-missing` extra by widening the
  shared `SpawnResult` shape — it already has `exitCode`. Only thread it through
  `resolveOutputAwareOk`'s args (alongside `stderrTail`) and into the `extra`
  object; grep the call sites to enumerate them rather than trusting a count.
