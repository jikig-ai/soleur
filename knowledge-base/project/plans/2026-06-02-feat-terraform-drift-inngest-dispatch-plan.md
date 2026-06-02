---
title: "feat: Migrate scheduled-terraform-drift to Inngest-dispatched trigger"
date: 2026-06-02
branch: feat-one-shot-terraform-drift-inngest-dispatch
type: feat
lane: cross-domain
brand_survival_threshold: none
status: planned
---

# feat: Migrate scheduled-terraform-drift from GHA `schedule:` to Inngest-dispatched trigger ✨

## Overview

`scheduled-terraform-drift` is the last hourly/twice-daily cron still fired by a GitHub
Actions `schedule:` trigger. Every other recurring job has moved to Inngest cron (TR9
substrate migration). GHA `schedule:` delivery jitter is severe — a 58-day survey (2026-06-02,
PR #4772 / commit `9e88d61e`) of 115 scheduled runs showed ~11% exceeding 180 min late with an
observed MAX of 339 min, which forced the Sentry monitor margin to be widened 180 → 480 min just
to suppress false "missed check-in" alarms.

This PR removes the jitter **at its source** by making Inngest the single scheduling substrate.
A **new Inngest cron function** fires on `{ cron: "0 6,18 * * *" }` and triggers the **existing**
`.github/workflows/scheduled-terraform-drift.yml` workflow via a `workflow_dispatch` API call.
The GHA `schedule:` block is removed; `workflow_dispatch:` is kept. **terraform still runs in the
ephemeral GHA runner exactly as today** — the Inngest function ONLY dispatches; it does NOT run
terraform in-process. With jitter removed (Inngest fires ≤2-min jitter), the Sentry monitor margin
tightens back 480 → 60 min.

### Architecture: DISPATCH HYBRID (approved — do not deviate)

```
Inngest cron (≤2-min jitter)                 GHA runner (unchanged executor)
  cron-terraform-drift.ts                       scheduled-terraform-drift.yml
  ─ mint installation token  ─────────────►   ─ setup-terraform (wrapper:false)
  ─ POST .../dispatches {ref:main}             ─ Doppler prd_terraform / R2 / AWS
  (NO terraform; NO Sentry check-in here)      ─ terraform plan -detailed-exitcode
                                               ─ drift/error email
                                               ─ sentry-heartbeat (UNCHANGED)
                                                 → scheduled-terraform-drift monitor
```

The `scheduled-terraform-drift` Sentry monitor keeps watching the **GHA run's** end-of-job
heartbeat (unchanged). The Inngest function does NOT check in to that monitor.

### HARD NON-GOAL

Do NOT run terraform in-process inside the Inngest function (no git-clone-and-run-terraform like
`cron-weekly-analytics.ts` does for the analytics script). terraform-drift needs the terraform
binary + R2/AWS/Doppler `prd_terraform` cloud-admin credentials; running it inside the Node app
server would park cloud-admin creds on the prod host — a security/complexity regression. terraform
MUST stay in the ephemeral GHA runner.

## Research Reconciliation — Spec vs. Codebase (live-verified 2026-06-02)

| Claim (from ARGUMENTS) | Codebase reality (verified) | Plan response |
| --- | --- | --- |
| GitHub App installation token has `actions: write` | **CONFIRMED.** `apps/web-platform/infra/github-app-manifest.json:19` → `"actions": "write"`; asserted by `test/github-app-manifest-parity.test.ts:62` (`EXPECTED_PERMISSION_KEYS` includes `"actions"`). **Prerequisite blocker CLEARED — not a blocker.** | Proceed with installation-token dispatch. No app-permission widening needed. |
| Reuse `getInstallationToken` helper from cron-weekly-analytics | Helper is named **`mintInstallationToken({ tokenMinLifetimeMs })`**, exported from `server/inngest/functions/_cron-shared.ts:99`. (`getInstallationToken` does not exist; `generateInstallationToken(installationId, …)` is the lower-level mint in `server/github-app.ts`.) | Use `mintInstallationToken` (the cron-shared wrapper that does installation discovery + mint). |
| Octokit `POST .../actions/workflows/scheduled-terraform-drift.yml/dispatches` with `ref: main` | `cron-weekly-analytics.ts:266` uses `new OctokitCtor({ auth: installationToken })` + `octokit.request("POST …")`. A sibling helper `server/trigger-workflow.ts` + `githubApiPost` (server/github-api.ts:152) also exist but take a numeric `workflowId` and an `installationId` (the MCP-tool path), not the cron token shape. | Use the **weekly-analytics Octokit pattern** (`@octokit/core` + `octokit.request`) with the workflow **filename** `scheduled-terraform-drift.yml` as `{workflow_id}` — the dispatches endpoint accepts the file basename. Keeps the cron self-contained on its minted token. |
| Remove `schedule:` lines 11-12, keep `workflow_dispatch:` | Confirmed: `.github/workflows/scheduled-terraform-drift.yml` lines 10-13 are `on: / schedule: / - cron … / workflow_dispatch:`. | Delete the `schedule:` block; keep `workflow_dispatch:`. |
| Sentry monitor `scheduled_terraform_drift` margin 480 → ~60 | Confirmed at `infra/sentry/cron-monitors.tf:68-78`, `checkin_margin_minutes = 480`, with a long GHA-jitter rationale comment (lines 48-67). Resource is ALREADY in `apply-sentry-infra.yml` `-target=` list (line 187). | Change to `60`; rewrite the rationale comment for Inngest-dispatched trigger. Auto-applies on merge. |
| Register in `cron-manifest.ts` `EXPECTED_CRON_FUNCTIONS` + update function-registry-count test | Manifest at `server/inngest/cron-manifest.ts:22-56` (32 entries). Test `test/server/inngest/function-registry-count.test.ts` guard (a) asserts route array length `== 43`; guard (e) asserts `EXPECTED_CRON_FUNCTIONS` set `==` cron-*.ts file set. | Add `"cron-terraform-drift"` to manifest; bump guard (a) `43 → 44`. |
| Register in the Inngest client served array | `app/api/inngest/route.ts:74-122` — 43 entries; new functions imported + listed. | Add import + `cronTerraformDrift,` to the array. |
| Manual-trigger allowlist + trigger-cron route reconcile | `lib/inngest/manual-trigger-allowlist.ts` DERIVES `MANUAL_TRIGGER_EVENTS` from `EXPECTED_CRON_FUNCTIONS` — **no second list to edit.** `app/api/internal/trigger-cron/route.ts` forwards any allowlisted event. | Add `{ event: "cron/terraform-drift.manual-trigger" }` as a second trigger on the function so the route can fire it. Manifest add → allowlist updates automatically. |
| cron-inngest-cron-watchdog covers the new function's liveness | Confirmed: watchdog is a 4-hourly liveness beacon; the function-registry parity guard (e) keeps the manifest == file set so the watchdog tracks the new cron. | Rely on watchdog + manifest for scheduler-liveness (see Liveness Decision below). |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing — terraform-drift is an
internal infra-observability cron. The worst broken-state is operator-facing: drift goes
undetected (the GHA run is never dispatched) until the `scheduled-terraform-drift` Sentry monitor
pages on a missed heartbeat. No tenant-visible surface, no data path.

**If this leaks, the user's data is exposed via:** N/A — the Inngest function holds only a
short-lived GitHub App installation token scoped to `actions: write` on the soleur repo; it never
touches tenant data, BYOK keys, or cloud-admin (R2/AWS/Doppler `prd_terraform`) credentials. Those
stay in the ephemeral GHA runner. The token is redacted from any error message via
`redactToken(...)` per the weekly-analytics precedent.

**Brand-survival threshold:** none.

> threshold: none, reason: internal infra-observability cron with no tenant-facing surface and no
> tenant/credential data path; the dispatcher holds only a short-lived repo-scoped App token.
> (Touches `.github/workflows/*` + `apps/*/infra/*` — sensitive paths — so this scope-out bullet
> is required by preflight Check 6.)

## Key Design Decision — Dispatcher Liveness Story (recommend A; B documented)

The ARGUMENTS state the Inngest function does NOT check in to `scheduled-terraform-drift` (that
monitor watches the GHA run). The open question is whether the **dispatcher itself** needs its OWN
Sentry monitor.

**Codebase convention (verified):** ALL 32 existing `cron-*.ts` files define a
`SENTRY_MONITOR_SLUG` + call `postSentryHeartbeat` + have a `sentry_cron_monitor` resource (or a
`KNOWN_UNMONITORED_SLUGS` exemption). There is **no slug-less cron precedent.**

**Test interaction (verified against `function-registry-count.test.ts`):**
- Guard (c)/(d)/(c2) iterate only files that DEFINE `SENTRY_MONITOR_SLUG`. A file WITHOUT the
  constant is simply skipped → no tf monitor required, no exemption needed.
- Guard (e) requires the file in `EXPECTED_CRON_FUNCTIONS` regardless.
- So a dispatcher with **no** `SENTRY_MONITOR_SLUG` passes all guards cleanly.

### Design A (RECOMMENDED) — no own Sentry monitor; two-layer liveness
The dispatcher defines NO `SENTRY_MONITOR_SLUG` and does NOT call `postSentryHeartbeat`. Liveness
is covered by two existing layers:
1. **Scheduler liveness:** `cron-inngest-cron-watchdog` (4-hourly beacon) + the parity guard (e)
   keep the new cron in the watchdog's purview. If the Inngest scheduler dies, the watchdog's own
   monitor pages.
2. **End-to-end liveness:** if the dispatch silently fails to trigger the GHA run, no GHA heartbeat
   arrives and the **existing `scheduled-terraform-drift` monitor goes red** within the 60-min
   margin. The downstream monitor IS the dispatcher's end-to-end proof.
3. **Dispatch error path:** an Octokit/token failure is reported to Sentry's **issues** stream via
   `reportSilentFallback` (matching `cron-github-app-drift-guard.ts` error handling) — loud, but
   not a separate cron monitor.

Rationale: aligns with the ARGUMENTS' stated liveness intent ("watchdog covers the new function's
liveness"); avoids a redundant second monitor for one logical cron; the downstream monitor already
covers the only failure that matters (dispatch didn't reach the runner).

### Design B (ALTERNATIVE) — own `scheduled-terraform-drift-dispatcher` monitor
The dispatcher defines `SENTRY_MONITOR_SLUG = "scheduled-terraform-drift-dispatcher"` and checks in
ok after a successful dispatch. Requires: a new `sentry_cron_monitor` resource in cron-monitors.tf
+ a new `-target=` line in apply-sentry-infra.yml (guards c/c2/f). Matches every existing
precedent. Cost: a second monitor whose red state lags the downstream monitor's red state, for the
same logical job.

**Recommendation:** ship **Design A**. Flag this for plan-review + deepen-plan adjudication — it is
the single substantive design choice and the only place this PR diverges from unanimous codebase
convention. If reviewers prefer convention-alignment, fall back to Design B (the plan's
`Files to Edit` notes the two extra edits B requires).

## Infrastructure (IaC)

This PR edits an EXISTING terraform resource (Sentry monitor margin) and an EXISTING GHA workflow;
it provisions NO new server, secret, vendor, or runtime process. The new Inngest function runs in
the already-provisioned web-platform app container (the Inngest substrate from PR-F #3940).

### Terraform changes
- `apps/web-platform/infra/sentry/cron-monitors.tf` — `sentry_cron_monitor.scheduled_terraform_drift`
  `checkin_margin_minutes` 480 → 60; rationale comment rewritten. No new resource (Design A).
  (Design B would add `sentry_cron_monitor.scheduled_terraform_drift_dispatcher`.)
- No new providers, version pins, or sensitive variables.

### Apply path
- **cloud-init + auto-apply workflow.** The margin change auto-applies on merge: `apply-sentry-infra.yml`
  already `-target=sentry_cron_monitor.scheduled_terraform_drift` (line 187). No operator apply.
  (Design B would also require adding the new `-target=` line to apply-sentry-infra.yml.)

### Distinctness / drift safeguards
- The new `60`-min margin must stay well under the 720-min inter-fire gap (06:00 → 18:00) so a
  maximally-late run of one slot is never misread as a missed run of the next. 60 ≪ 720 — safe.
- No `lifecycle.ignore_changes`; no state-secret exposure (Sentry monitor carries no secret).

### Vendor-tier reality check
- The `jianyuan/sentry` provider's `sentry_cron_monitor` is a Crons resource (not the beta
  uptime/import-only path that bit PR #3811). No free-tier gate. The margin is an in-place field
  update on an existing resource — no create.

## Observability

```yaml
liveness_signal:
  what: "GHA scheduled-terraform-drift run heartbeat (end-of-job sentry-heartbeat step, UNCHANGED) + cron-inngest-cron-watchdog tracking the new Inngest cron via the parity-guarded manifest"
  cadence: "twice daily 06:00/18:00 UTC (drift run); 4-hourly (watchdog beacon)"
  alert_target: "Sentry cron monitor scheduled-terraform-drift (margin tightened 480→60); Sentry cron monitor scheduled-inngest-cron-watchdog (scheduler liveness)"
  configured_in: "apps/web-platform/infra/sentry/cron-monitors.tf:scheduled_terraform_drift + scheduled_inngest_cron_watchdog"
error_reporting:
  destination: "Sentry issues stream via reportSilentFallback (dispatch/token failure in cron-terraform-drift.ts) + the GHA workflow's existing drift/error email path"
  fail_loud: true
failure_modes:
  - mode: "Inngest dispatch fails (Octokit throws / token mint fails)"
    detection: "reportSilentFallback Sentry issue from the handler catch block"
    alert_route: "Sentry issues stream (feature: cron-terraform-drift)"
  - mode: "Dispatch succeeds but GHA run never heartbeats (runner failure / workflow broke)"
    detection: "missed check-in on scheduled-terraform-drift monitor within 60-min margin"
    alert_route: "Sentry cron monitor scheduled-terraform-drift"
  - mode: "Inngest scheduler stops firing the new cron (de-planned / dropped trigger)"
    detection: "cron-inngest-cron-watchdog missed-checkin (manifest parity keeps the new cron in purview)"
    alert_route: "Sentry cron monitor scheduled-inngest-cron-watchdog"
  - mode: "terraform drift detected (exit 2) or plan error (exit 1)"
    detection: "GHA job branches status; drift/error email + issue (UNCHANGED from today)"
    alert_route: "notify-ops-email + issue filer (existing workflow behavior)"
logs:
  where: "Inngest run logs (app container stdout, sentry-correlation middleware tags inngest.run_id/fn_id); GHA run logs for the terraform execution"
  retention: "Inngest/app-container stdout per host policy; GHA run logs per GitHub retention"
discoverability_test:
  command: "gh workflow run scheduled-terraform-drift.yml --ref main && gh run list --workflow=scheduled-terraform-drift.yml --limit 3"
  expected_output: "A new queued/in-progress run appears (proves the workflow_dispatch path the Inngest function uses is live); the Inngest fire can be exercised via POST /api/internal/trigger-cron with event cron/terraform-drift.manual-trigger"
```

## Implementation Phases

### Phase 1 — New Inngest cron function (dispatch-only)
Create `apps/web-platform/server/inngest/functions/cron-terraform-drift.ts`:
- Header comment: dispatch-hybrid rationale, HARD NON-GOAL (no in-process terraform), ADR-033
  reference, ADR-033 §"Inngest > GH Actions cron" precedent.
- Constants: `FUNCTION_NAME = "cron-terraform-drift"`, `WORKFLOW_FILE = "scheduled-terraform-drift.yml"`,
  `TOKEN_MIN_LIFETIME_MS` (short — one API call; mirror weekly-analytics' `15 * 60 * 1000` or
  smaller).
- Handler `cronTerraformDriftHandler({ step, logger }: HandlerArgs)`:
  - `step.run("mint-installation-token", () => mintInstallationToken({ tokenMinLifetimeMs }))`.
  - `step.run("dispatch-workflow", …)`: `const { Octokit } = await import("@octokit/core")`;
    `new Octokit({ auth: token })`; `octokit.request("POST /repos/{owner}/{repo}/actions/workflows/{workflow_id}/dispatches", { owner: REPO_OWNER, repo: REPO_NAME, workflow_id: WORKFLOW_FILE, ref: "main" })`.
  - On success: `logger.info(...)`, `return { ok: true }`. NO `postSentryHeartbeat` (Design A).
  - `catch`: `redactToken(e.message, token)`, `reportSilentFallback(redacted, { feature: FUNCTION_NAME, op: "dispatch-workflow", message: "terraform-drift workflow_dispatch failed" })`, `return { ok: false }`.
- `export const cronTerraformDrift = inngest.createFunction(`
  - `{ id: "cron-terraform-drift", concurrency: [{ scope: "fn", limit: 1 }, { scope: "account", key: '"cron-platform"', limit: 1 }], retries: 1 }`,
  - `[{ cron: "0 6,18 * * *" }, { event: "cron/terraform-drift.manual-trigger" }]`,
  - `cronTerraformDriftHandler as unknown as Parameters<typeof inngest.createFunction>[2]`.
- Mock filenames for tests: `cron-terraform-drift.test.ts` (registration-shape smoke +
  dispatch-call assertion via injected/mocked octokit, mirroring `cron-weekly-analytics.test.ts`).

### Phase 2 — Remove `schedule:` from the GHA workflow (keep `workflow_dispatch:`)
Edit `.github/workflows/scheduled-terraform-drift.yml`:
- Delete lines 11-12 (`schedule:` + `- cron: '0 6,18 * * *'`); keep `workflow_dispatch:`.
- Update the header comment (line 7 `# To test manually:`) and add a one-line note that the
  twice-daily fire is now Inngest-dispatched (`cron-terraform-drift.ts`), `workflow_dispatch`-only.
- Leave the entire `jobs.drift-check` block UNCHANGED (setup-terraform wrapper:false, Doppler
  prd_terraform, R2/AWS extract, `terraform plan -detailed-exitcode`, drift/error email,
  `sentry-heartbeat` step → `scheduled-terraform-drift` monitor).

### Phase 3 — Register the function (manifest, client array, test parity)
- `server/inngest/cron-manifest.ts`: add `"cron-terraform-drift"` to `EXPECTED_CRON_FUNCTIONS`
  (keep alphabetical position: insert before `cron-ux-audit`). This also auto-adds
  `cron/terraform-drift.manual-trigger` to the manual-trigger allowlist (derived) — NO edit to
  `lib/inngest/manual-trigger-allowlist.ts`.
- `app/api/inngest/route.ts`: add `import { cronTerraformDrift } from "@/server/inngest/functions/cron-terraform-drift";`
  and `cronTerraformDrift,` in the served array (alphabetical).
- `test/server/inngest/function-registry-count.test.ts`: bump guard (a) `expect(routeEntries.length).toBe(43)` → `44`. Guard (e) auto-passes (manifest == file set). Guards (c)/(d)/(c2)/(f) unaffected — the new file defines no `SENTRY_MONITOR_SLUG` (Design A).

### Phase 4 — Retune the Sentry monitor margin
Edit `apps/web-platform/infra/sentry/cron-monitors.tf`,
`sentry_cron_monitor.scheduled_terraform_drift`:
- `checkin_margin_minutes` 480 → 60.
- Rewrite the rationale comment (lines 48-67): the GHA-schedule-jitter rationale no longer applies;
  the trigger is now Inngest-dispatched (`cron-terraform-drift.ts`, ≤2-min jitter). New rationale:
  Inngest fires ≤2-min jitter + dispatch seconds + runner queue + terraform ~2-3 min → check-in
  lands ~5-10 min after schedule; 60 gives comfortable headroom while staying well under the
  720-min inter-fire gap. Cite this PR + the superseded PR #4772.
- No `-target=` change (resource already targeted, line 187). Auto-applies on merge via
  apply-sentry-infra.yml.

### Phase 5 — ADR / docs (lightweight)
- Verify ADR-033's "Inngest > GH Actions cron" precedent covers this dispatch-hybrid variant; if it
  enumerates an explicit migration list, append this cron (read first — do not assume the shape).

## Acceptance Criteria

### Pre-merge (PR)
- [ ] **AC1** `apps/web-platform/server/inngest/functions/cron-terraform-drift.ts` exists, exports
  `cronTerraformDrift`, fires on `{ cron: "0 6,18 * * *" }` + `{ event: "cron/terraform-drift.manual-trigger" }`,
  and its handler calls `octokit.request("POST …/actions/workflows/{workflow_id}/dispatches", { …, workflow_id: "scheduled-terraform-drift.yml", ref: "main" })`. Verify: `grep -n 'dispatches\|0 6,18\|scheduled-terraform-drift.yml\|ref: "main"' apps/web-platform/server/inngest/functions/cron-terraform-drift.ts`.
- [ ] **AC2** The handler runs NO terraform and clones NO repo. Verify: `! grep -qE 'mkdtemp|git.*clone|terraform|spawn\(' apps/web-platform/server/inngest/functions/cron-terraform-drift.ts` returns true.
- [ ] **AC3** `.github/workflows/scheduled-terraform-drift.yml` no longer contains a `schedule:`
  block and still contains `workflow_dispatch:`. Verify: `! grep -qE '^\s+schedule:' .github/workflows/scheduled-terraform-drift.yml && grep -q 'workflow_dispatch:' .github/workflows/scheduled-terraform-drift.yml`.
- [ ] **AC4** The workflow's `terraform plan -detailed-exitcode` step and the end-of-job
  `sentry-heartbeat` step (monitor-slug `scheduled-terraform-drift`) are UNCHANGED. Verify: `grep -q 'monitor-slug: scheduled-terraform-drift' .github/workflows/scheduled-terraform-drift.yml && grep -q 'detailed-exitcode' .github/workflows/scheduled-terraform-drift.yml`.
- [ ] **AC5** `"cron-terraform-drift"` is in `EXPECTED_CRON_FUNCTIONS` (cron-manifest.ts). Verify: `grep -q '"cron-terraform-drift"' apps/web-platform/server/inngest/cron-manifest.ts`.
- [ ] **AC6** `cronTerraformDrift` is imported and listed in `app/api/inngest/route.ts`. Verify: `grep -c 'cronTerraformDrift' apps/web-platform/app/api/inngest/route.ts` returns `2`.
- [ ] **AC7** `function-registry-count.test.ts` guard (a) asserts `44` and the full file passes.
  Verify: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/function-registry-count.test.ts` (runner is **vitest**, not bun — see Sharp Edges).
- [ ] **AC8** `sentry_cron_monitor.scheduled_terraform_drift` has `checkin_margin_minutes = 60`
  and its rationale comment references the Inngest-dispatched trigger. Verify: `grep -A8 'resource "sentry_cron_monitor" "scheduled_terraform_drift"' apps/web-platform/infra/sentry/cron-monitors.tf | grep -q 'checkin_margin_minutes  = 60'`.
- [ ] **AC9** `cron/terraform-drift.manual-trigger` is allowlisted (derived). Verify (unit):
  `cd apps/web-platform && ./node_modules/.bin/vitest run` over the manual-trigger-allowlist test,
  OR assert `MANUAL_TRIGGER_EVENTS` contains the event.
- [ ] **AC10** `tsc --noEmit` and the full vitest suite are green (no exhaustiveness/type
  regressions from the new function registration).

### Post-merge (operator / automated)
- [ ] **AC11** Margin change auto-applied: `apply-sentry-infra.yml` runs on merge and the Sentry
  monitor `scheduled-terraform-drift` shows `checkin_margin_minutes = 60`. **Automation:** verify via
  the apply-sentry-infra workflow run (`gh run list --workflow=apply-sentry-infra.yml --limit 1`),
  NOT a dashboard eyeball.
- [ ] **AC12** First Inngest-dispatched fire succeeds: confirm a `scheduled-terraform-drift` GHA run
  was triggered without a `schedule:` event. **Automation:** `gh run list --workflow=scheduled-terraform-drift.yml --limit 3 --json event,createdAt,conclusion` — the new run's `event` is `workflow_dispatch` (not `schedule`). Can be exercised immediately via `POST /api/internal/trigger-cron` (event `cron/terraform-drift.manual-trigger`, Bearer `INNGEST_MANUAL_TRIGGER_SECRET` read read-only from Doppler) without waiting for the natural 06:00/18:00 fire.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change. The migration moves the
scheduling substrate of an internal infra-observability cron from GHA `schedule:` to Inngest;
terraform execution, credentials, and the user-facing product are all untouched. Product/UX gate:
NONE (no user-facing page, flow, or component; no new file under `components/**`, `app/**/page.tsx`,
or `app/**/layout.tsx`).

## Files to Edit
- `apps/web-platform/server/inngest/cron-manifest.ts` — add `"cron-terraform-drift"`.
- `apps/web-platform/app/api/inngest/route.ts` — import + array entry.
- `apps/web-platform/test/server/inngest/function-registry-count.test.ts` — guard (a) `43 → 44`.
- `apps/web-platform/infra/sentry/cron-monitors.tf` — margin 480 → 60 + rationale rewrite.
- `.github/workflows/scheduled-terraform-drift.yml` — remove `schedule:` block; header note.
- `knowledge-base/engineering/architecture/decisions/ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md` — append migration entry IF it carries an enumerated list (read first).
- _(Design B only, if chosen at review):_ add `sentry_cron_monitor.scheduled_terraform_drift_dispatcher`
  to cron-monitors.tf AND a matching `-target=` line to `.github/workflows/apply-sentry-infra.yml`.

## Files to Create
- `apps/web-platform/server/inngest/functions/cron-terraform-drift.ts` — the dispatch-only cron.
- `apps/web-platform/test/server/inngest/cron-terraform-drift.test.ts` — registration-shape +
  dispatch-call test (mock octokit; assert POST .../dispatches with `workflow_id` + `ref: "main"`).

## Open Code-Review Overlap
None — checked after the Files-to-Edit list was finalized. (Run `gh issue list --label code-review --state open` at /work time and re-check against the final paths if any new scope-outs landed.)

## Test Scenarios
- New function fires on cron → mints token → POSTs `/dispatches` with `ref: main` → returns `{ ok: true }` (mocked octokit asserts the request shape).
- Dispatch throws → handler reports to Sentry via `reportSilentFallback` (token redacted) → returns `{ ok: false }`; no unhandled rejection.
- `function-registry-count.test.ts` guards (a)/(b)/(e) all green with the new file + bumped count.
- The new cron defines NO `SENTRY_MONITOR_SLUG` → guards (c)/(d)/(c2) skip it; no tf monitor required (Design A).

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above — threshold `none`
  with a sensitive-path scope-out reason.)
- **Test runner is vitest, not bun.** `apps/web-platform/bunfig.toml` blocks bun test discovery;
  use `./node_modules/.bin/vitest run <path>`. Test FILE PATHS must satisfy vitest's `include:`
  globs (`test/**/*.test.ts`) — place new tests under `test/server/inngest/`, not co-located.
- **The dispatches endpoint takes the workflow FILE BASENAME** (`scheduled-terraform-drift.yml`) as
  `{workflow_id}` — no numeric ID lookup needed. The sibling `triggerWorkflow`/`githubApiPost`
  helpers take a numeric `workflowId` + `installationId` (MCP-tool shape) — do NOT adopt them; the
  cron uses its own minted token + filename, matching the weekly-analytics Octokit pattern.
- **`mintInstallationToken`, not `getInstallationToken`.** The ARGUMENTS named the helper
  imprecisely; the real export from `_cron-shared.ts` is `mintInstallationToken({ tokenMinLifetimeMs })`.
- **`actions: write` is already granted** (`github-app-manifest.json:19`, parity-tested). No app
  permission widening, no PAT (per `hr-github-app-auth-not-pat`).
- **Liveness is the one substantive design choice** — see "Key Design Decision". Design A (no own
  monitor) is novel vs. the unanimous slug-per-cron convention; if plan-review/deepen-plan prefer
  convention, switch to Design B (two extra edits, noted in Files to Edit).
- The new 60-min margin must stay ≪ the 720-min inter-fire gap so a late run of one slot is never
  read as a missed run of the next — 60 ≪ 720, safe.
