---
title: "feat: Inngest-dispatch three more recurring crons (dev-migration-drift, main-health-monitor, review-reminder)"
type: feat
date: 2026-06-02
branch: feat-one-shot-inngest-dispatch-three-crons
lane: cross-domain
brand_survival_threshold: none
---

# feat: Inngest-dispatch three more recurring crons

## Enhancement Summary

**Deepened on:** 2026-06-02

### Halt gates (all passed)
- **4.6 User-Brand Impact** — section present, threshold `none` with a canonical `threshold: none, reason: …` scope-out bullet (required because the diff touches the sensitive path `apps/web-platform/server/**`).
- **4.7 Observability** — `## Observability` present; all 5 fields populated, `discoverability_test.command` is SSH-free (vitest invocation).
- **4.8 PAT-shaped variable halt** — no PAT-shaped vars/literals; auth is the existing GitHub App installation token (`actions: write`) via `mintInstallationToken`.

### Verifications performed live (this pass)
- **Registry count re-derived** with the test's exact regex `grep -cE '^[[:space:]]+\w+,$'` → **44** today; target **47**. (A naive comma-split gives 48 — comment-line artifacts — and is the trap to avoid.)
- **Precedent (Phase 4.4)** — 34 Inngest cron functions exist; Inngest is canonical per ADR-033. Dispatch-hybrid precedent is the just-merged `cron-terraform-drift.ts`; pattern is NOT novel.
- **PR attribution** — `#4787` (terraform-drift Inngest-dispatch) and `#4772` (superseded margin PR) confirmed as merged commits via `git log --grep`; template file present on `main`.
- **Cited rule IDs** (`hr-github-app-auth-not-pat`, `cq-write-failing-tests-before`, `hr-weigh-…`, `hr-observability-…`) all active in AGENTS.md; the learning-file path resolves.
- **Literal consistency** — the 3 cron strings, 3 workflow filenames, and the `44→47` count are internally consistent across Overview / Reconciliation / AC / Phases / Risks / Sharp Edges.
- **Substrate guards** — `cron-substrate-imports.test.ts` auto-discovers `cron-*.ts` and asserts the relative `./_cron-shared` import + no local symbol redefinition; the 3 new files pass by mirroring the template (no test edit needed). Slug-less files skip `function-registry-count` guards (c)/(d)/(c2)/(f)/(f2) cleanly.

### Note on depth
This is a near-mechanical, three-times-repeated migration against a literal merged template (`cron-terraform-drift.ts` + its test), at brand-survival threshold `none`. No external/framework research was warranted; the structural plan + the four documented test gotchas (in the cited learning) are the load-bearing content.

## Overview

Migrate THREE more recurring GitHub Actions crons from GHA `schedule:` triggers to **Inngest-dispatched** triggers, so Inngest becomes the single scheduling substrate across the platform. This repeats — three times, near-identically — the **dispatch-hybrid** pattern shipped for `scheduled-terraform-drift` in `cron-terraform-drift.ts` (merged 2026-06-02, PR #4787).

The pattern: a new dispatch-only Inngest cron fires on the workflow's existing cron expression, mints a short-lived GitHub App installation token (`actions: write`), and triggers the EXISTING GHA workflow via Octokit `POST /repos/{owner}/{repo}/actions/workflows/{workflow_id}/dispatches` (`workflow_id` = the workflow **filename** string, `ref: "main"`). The GHA `schedule:` block is removed; `workflow_dispatch:` and the entire job body stay UNCHANGED — the composite action / test suite / repo-walk all keep running in the ephemeral GHA runner. **Each Inngest function ONLY dispatches.**

The three workflows:

| # | Workflow file | Cron | New fn file | New fn id | Manual-trigger event (auto-derived) |
|---|---------------|------|-------------|-----------|--------------------------------------|
| 1 | `scheduled-dev-migration-drift.yml` | `15 */6 * * *` | `cron-dev-migration-drift.ts` | `cron-dev-migration-drift` | `cron/dev-migration-drift.manual-trigger` |
| 2 | `main-health-monitor.yml` | `0 */6 * * *` | `cron-main-health-monitor.ts` | `cron-main-health-monitor` | `cron/main-health-monitor.manual-trigger` |
| 3 | `review-reminder.yml` | `0 0 1 * *` | `cron-review-reminder.ts` | `cron-review-reminder` | `cron/review-reminder.manual-trigger` |

This migration ADDS first-time scheduler-liveness alerting for these three crons (via `cron-inngest-cron-watchdog` + the parity-guarded `EXPECTED_CRON_FUNCTIONS` manifest), which they did not have under raw GHA `schedule:`.

### Reference template (read first at /work time)

- **Function template:** `apps/web-platform/server/inngest/functions/cron-terraform-drift.ts` — copy literally, change only the 3 constants (`FUNCTION_NAME`, `WORKFLOW_FILE`, the cron string + manual-trigger event) and the comment header.
- **Test template:** `apps/web-platform/test/server/inngest/cron-terraform-drift.test.ts` — copy literally, change the SUT import, anchors (cron string, workflow filename), and the expected dispatch params.
- **Learning (mandatory read):** `knowledge-base/project/learnings/2026-06-02-inngest-dispatches-gha-for-credential-heavy-crons.md` — all four test gotchas live here.

## Research Reconciliation — Spec vs. Codebase (live-verified 2026-06-02)

The ARGUMENTS prose was largely accurate; one moving-target number was confirmed and pinned. Everything below was verified by reading the live files, not the prose.

| Claim (prose) | Reality (verified) | Plan response |
|---|---|---|
| Registry count `44 → 47` | Test guard (a) currently asserts **44**, and the test-exact regex `/^\s+(\w+),$/gm` matches exactly 44 entries in `route.ts` today (a naive comma-split gives 48 — it falsely catches comment-line artifacts; trust the test regex). | Guard (a) becomes **47**. Re-derive at /work time with the **test's exact regex**, not a naive count. |
| dev-migration-drift has `workflow_dispatch: {}` (no inputs) | Confirmed (`scheduled-dev-migration-drift.yml`). Runs `./.github/actions/dev-migration-drift-probe` with `DOPPLER_TOKEN_DEV_SCHEDULED`. No Sentry heartbeat step. | Dispatch with no `inputs` field. |
| main-health-monitor has `workflow_dispatch:` (no inputs) | Confirmed. Runs `bash scripts/test-all.sh` + files P1 issue on failure. No Sentry heartbeat step. | Dispatch with no `inputs` field. |
| review-reminder `workflow_dispatch` declares OPTIONAL `date_override` | Confirmed (`required: false`, `type: string`). Workflow defaults `today` to `date -u +%Y-%m-%d` when unset. No Sentry heartbeat step. | Dispatch with **no `inputs` field** (omit it) → workflow defaults date to today. Keep the `date_override` input block in the workflow for manual testing. |
| GitHub App token has `actions: write` | Confirmed at `apps/web-platform/infra/github-app-manifest.json:19` (`"actions": "write"`). | No PAT (`hr-github-app-auth-not-pat`); reuse `mintInstallationToken`. |
| `_cron-shared` must be imported relatively | Confirmed: `cron-substrate-imports.test.ts` `SHARED_IMPORT_RE = /from\s+["']\.\/_cron-shared["']/` matches ONLY the relative form. | Import `from "./_cron-shared"` — NOT the `@/` alias. (Note: `inngest` client and `reportSilentFallback` ARE imported via `@/` — only `_cron-shared` is relative, mirroring the template.) |
| No tf monitor / no `apply-sentry-infra` change | Confirmed: none of the 3 workflows has a Sentry cron monitor today; the new fns are slug-less. Guards (c)/(d)/(c2)/(f) in `function-registry-count.test.ts` iterate over `SENTRY_MONITOR_SLUG` matches / tf resources only — slug-less files are skipped cleanly. | Design A. No `SENTRY_MONITOR_SLUG`, no `postSentryHeartbeat`, no `cron-monitors.tf` change, no `apply-sentry-infra` `-target`. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing — these are internal infra/CI crons (dev migration-drift probe, main-branch test-suite monitor, doc-review reminders). A broken dispatch means a cron silently stops firing; the failure mode is operator-internal (drift undetected, a red main goes un-issued), not customer-visible.
**If this leaks, the user's data is exposed via:** N/A — the Inngest functions hold only a short-lived `actions: write`-scoped GitHub App installation token and dispatch a workflow by name; no operator/customer data is read, processed, or moved. The token is redacted from any error before it reaches Sentry (`redactToken` + `[REDACTED-INSTALLATION-TOKEN]` sentinel).
**Brand-survival threshold:** none — internal scheduling substrate change with no customer-data surface and no customer-facing artifact.

- `threshold: none, reason: diff touches apps/web-platform/server/** (code class) but only adds dispatch-only scheduler functions that hold a scoped GitHub App token and read/write no customer data — no schema, auth, API-route, or regulated-data surface.`

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Three new dispatch-only Inngest functions exist**, one per workflow, each a literal mirror of `cron-terraform-drift.ts` with only the per-workflow constants changed:
  - `cron-dev-migration-drift.ts`: `id: "cron-dev-migration-drift"`, `cron: "15 */6 * * *"`, `event: "cron/dev-migration-drift.manual-trigger"`, `WORKFLOW_FILE = "scheduled-dev-migration-drift.yml"`.
  - `cron-main-health-monitor.ts`: `id: "cron-main-health-monitor"`, `cron: "0 */6 * * *"`, `event: "cron/main-health-monitor.manual-trigger"`, `WORKFLOW_FILE = "main-health-monitor.yml"`.
  - `cron-review-reminder.ts`: `id: "cron-review-reminder"`, `cron: "0 0 1 * *"`, `event: "cron/review-reminder.manual-trigger"`, `WORKFLOW_FILE = "review-reminder.yml"`.
- [ ] **AC2 — Each fn dispatches with NO `inputs` field.** The Octokit request body is exactly `{ owner: "jikig-ai", repo: "soleur", workflow_id: <WORKFLOW_FILE>, ref: "main" }`. Verified by `toEqual` (exhaustive) in each new test. (review-reminder in particular omits `inputs` → the workflow defaults date to today.)
- [ ] **AC3 — HARD NON-GOAL: no in-process execution.** Each new fn source does NOT contain `mkdtemp`, `spawn(`, `child_process`, `buildAuthenticatedCloneUrl`, or `resolveCronWorkspaceRoot` (the AC2-anchor block from the template test). `main-health-monitor` especially must NOT run `test-all.sh` in-process.
- [ ] **AC4 — `schedule:` block removed from all three workflows**, `workflow_dispatch:` and the entire job body (composite action / test suite / repo-walk) kept UNCHANGED. For `scheduled-dev-migration-drift.yml`: keep `workflow_dispatch: {}`. For `main-health-monitor.yml`: keep bare `workflow_dispatch:`. For `review-reminder.yml`: keep `workflow_dispatch:` WITH its `inputs.date_override` block. Verify each workflow still has exactly one `on:` trigger (`workflow_dispatch`) and `actionlint` passes.
- [ ] **AC5 — All three registered in `route.ts`** (import line + served-array entry, alphabetical) AND in `EXPECTED_CRON_FUNCTIONS` (`cron-manifest.ts`, alphabetical).
- [ ] **AC6 — `function-registry-count.test.ts` guard (a) bumped 44 → 47.** Re-derive the literal at /work time with `grep -cE '^[[:space:]]+\w+,$' apps/web-platform/app/api/inngest/route.ts` against the as-written file; if a sibling PR shifted the baseline, set guard (a) to `<as-written count>` (which should be `<baseline> + 3`).
- [ ] **AC7 — Each fn imports `_cron-shared` via the RELATIVE form** `from "./_cron-shared"` (not the `@/` alias); `inngest` and `reportSilentFallback` via `@/` (mirrors the template exactly). `cron-substrate-imports.test.ts` passes for all three (auto-discovered; no edit needed).
- [ ] **AC8 — Per-fn dispatch test (3 files)** mirroring `cron-terraform-drift.test.ts`: registration-shape anchors, dispatch-hybrid source anchors, HARD-NON-GOAL anchors, happy-path (`toEqual` exhaustive params + `ok: true` + reporter not called), and failure-path (Sentry reported, `ok: false`, token redacted out of `Error.message` with the `[REDACTED-INSTALLATION-TOKEN]` positive control). All mock spies destructured from `.mock.calls[i]` are typed `(...args: unknown[])`.
- [ ] **AC9 — No Sentry-monitor surface added.** No `SENTRY_MONITOR_SLUG` in any new fn; no `postSentryHeartbeat` call; no `cron-monitors.tf` change; no `apply-sentry-infra.yml` `-target` change. Guards (c)/(d)/(c2)/(f)/(f2) stay green (slug-less files skip cleanly).
- [ ] **AC10 — Full webplat suite green:** `bash scripts/test-all.sh` (read the explicit `EXIT=` marker, not the wrapper exit — tail-masking class). In particular `function-registry-count.test.ts` (all guards a–f2), `cron-substrate-imports.test.ts`, and the three new test files pass; `tsc --noEmit` clean.

### Post-merge (operator)

- [ ] **AC11 — Container restart applies the new functions.** No separate operator step: `web-platform-release.yml` path-filtered `on.push` restarts the Docker container on every merge to `main` touching `apps/web-platform/**`, which re-registers the Inngest functions. Merge IS the remediation. (Automation: covered by existing release pipeline.)
- [ ] **AC12 — Optional smoke (automatable, not required for merge):** after deploy, fire each manual-trigger via `/soleur:trigger-cron` (or `POST /api/internal/trigger-cron` with the allowlisted `cron/<name>.manual-trigger` event) and confirm a corresponding `workflow_dispatch` run appears in `gh run list --workflow=<file>`. This is the end-to-end liveness check; do NOT block the PR on it.

## Implementation Phases

### Phase 0 — Preconditions (read, do not code)

1. Read `cron-terraform-drift.ts` and `cron-terraform-drift.test.ts` (the literal templates).
2. Read the learning file `2026-06-02-inngest-dispatches-gha-for-credential-heavy-crons.md` (4 gotchas).
3. Re-derive guard (a) baseline: `grep -cE '^[[:space:]]+\w+,$' apps/web-platform/app/api/inngest/route.ts`. Expect 44; new target = baseline + 3.
4. Confirm the 3 workflow files still have a `schedule:` block and the cron strings match the table above.

### Phase 1 — Three Inngest dispatch functions (TDD: write the 3 tests first, RED)

For each of the three (dev-migration-drift, main-health-monitor, review-reminder):

1. Write `test/server/inngest/cron-<name>.test.ts` by copying `cron-terraform-drift.test.ts` and substituting: SUT import path + symbol names, the cron-string anchor, the `WORKFLOW_FILE` anchor, the manual-trigger event anchor, and the expected dispatch params (`workflow_id` = the workflow filename). Keep the failure-path redaction test (`.message` inspect + `[REDACTED-INSTALLATION-TOKEN]` positive control) and `(...args: unknown[])`-typed spies. RED (SUT not yet present).
2. Write `server/inngest/functions/cron-<name>.ts` by copying `cron-terraform-drift.ts`:
   - Change `FUNCTION_NAME`, `WORKFLOW_FILE`, the `createFunction` `id`, the `cron:` string, and the manual-trigger `event:` string.
   - Keep the dispatch body identical: mint token → Octokit POST `dispatches` with `{ owner: REPO_OWNER, repo: REPO_NAME, workflow_id: WORKFLOW_FILE, ref: "main" }` (NO `inputs`).
   - Keep the catch arm: `redactToken` + `reportSilentFallback` with `feature: FUNCTION_NAME`.
   - Keep the concurrency block (`fn` limit 1 + `account` `"cron-platform"` lane) and `retries: 1`.
   - Rewrite the header comment to describe THIS workflow's executor (composite drift-probe / test-suite / repo-walk) and Design-A liveness. Do NOT mention terraform.
   - Import `_cron-shared` relatively; `inngest` + `reportSilentFallback` via `@/`. GREEN.

Phase-order note: tests before sources (RED→GREEN) per `cq-write-failing-tests-before`.

### Phase 2 — Register the three functions

1. `app/api/inngest/route.ts`: add 3 import lines (alphabetical among the `cron*` imports) and 3 served-array entries (alphabetical). `cronDevMigrationDrift`, `cronMainHealthMonitor`, `cronReviewReminder`.
2. `server/inngest/cron-manifest.ts`: add `"cron-dev-migration-drift"`, `"cron-main-health-monitor"`, `"cron-review-reminder"` to `EXPECTED_CRON_FUNCTIONS` (alphabetical — they slot between existing neighbours: dev-migration-drift after `cron-daily-triage`, main-health-monitor after `cron-linkedin-token-check`, review-reminder after `cron-roadmap-review` and before `cron-rule-prune`). Verify final ordering is alphabetical.
3. `test/server/inngest/function-registry-count.test.ts`: bump guard (a) to the Phase-0 re-derived target (44 → 47). No other edit (slug guards skip the slug-less new files; guard (b)/(e) parity is satisfied by steps 1–2).

### Phase 3 — Remove the `schedule:` block from the three workflows

For each workflow, delete ONLY the `schedule:` key and its `- cron: '...'` child under `on:`. Keep `workflow_dispatch` (and review-reminder's `inputs.date_override`). Keep `concurrency`, `permissions`, and the entire `jobs:` body byte-for-byte otherwise.

- `scheduled-dev-migration-drift.yml`: `on:` becomes just `workflow_dispatch: {}`. (Also update the trailing security-comment line that says "this workflow only triggers on `schedule` (no payload) and `workflow_dispatch`" → "only triggers on `workflow_dispatch`"; it is now dispatched by the Inngest cron.)
- `main-health-monitor.yml`: `on:` becomes just `workflow_dispatch:`.
- `review-reminder.yml`: `on:` becomes `workflow_dispatch:` WITH the existing `inputs.date_override` block retained.

Validate with `actionlint .github/workflows/<file>.yml` (workflows, NOT composite actions) and `bash -c '<extracted run snippet>'` if any run-block changed (none should).

### Phase 4 — Full verification

1. `cd apps/web-platform && bash scripts/test-all.sh` — read the explicit `EXIT=` log marker (tail-masking class). If a webplat file times out in the single-process local shard (signature-verify `importRoute()` 16s), re-run that file in isolation (CI shards into 2) before treating as a regression.
2. `tsc --noEmit` (webplat) clean.
3. `actionlint` on the three edited workflows.

## Files to Create

- `apps/web-platform/server/inngest/functions/cron-dev-migration-drift.ts`
- `apps/web-platform/server/inngest/functions/cron-main-health-monitor.ts`
- `apps/web-platform/server/inngest/functions/cron-review-reminder.ts`
- `apps/web-platform/test/server/inngest/cron-dev-migration-drift.test.ts`
- `apps/web-platform/test/server/inngest/cron-main-health-monitor.test.ts`
- `apps/web-platform/test/server/inngest/cron-review-reminder.test.ts`

## Files to Edit

- `apps/web-platform/app/api/inngest/route.ts` — 3 imports + 3 served-array entries (alphabetical).
- `apps/web-platform/server/inngest/cron-manifest.ts` — 3 `EXPECTED_CRON_FUNCTIONS` entries (alphabetical).
- `apps/web-platform/test/server/inngest/function-registry-count.test.ts` — guard (a) 44 → 47.
- `.github/workflows/scheduled-dev-migration-drift.yml` — remove `schedule:`; fix trailing security comment.
- `.github/workflows/main-health-monitor.yml` — remove `schedule:`.
- `.github/workflows/review-reminder.yml` — remove `schedule:`; keep `inputs.date_override`.

## Open Code-Review Overlap

None — no open `code-review`-labelled issues touch these files (no overlap query returned matches for the Inngest functions/route/manifest or the three workflows; these are net-new dispatcher files mirroring a just-merged template).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal infrastructure/scheduling change. No user-facing surface, no schema, no auth, no regulated-data movement. (Product/UX: NONE — no new component/page files. GDPR gate: skipped — no regulated-data surface; the new code holds only a scoped GitHub App token and reads/writes no customer data. IaC gate: skipped — no new infrastructure resource; the GitHub App `actions: write` permission and the Inngest substrate already exist and were provisioned by prior PRs.)

## Infrastructure (IaC)

Not applicable — no new infrastructure. The dispatch path reuses the already-provisioned GitHub App installation (with `actions: write`, `apps/web-platform/infra/github-app-manifest.json:19`) and the existing Inngest substrate. No Terraform change, no new secret, no new vendor, no `cron-monitors.tf` resource (Design A — slug-less). Deployment of the new functions happens via the existing `web-platform-release.yml` container restart on merge.

## Observability

```yaml
liveness_signal:
  what: "Each new Inngest cron fires on its schedule; cron-inngest-cron-watchdog classifies it against the running /v1/functions registry via the parity-guarded EXPECTED_CRON_FUNCTIONS manifest. End-to-end: if a dispatch never reaches the GHA runner, the downstream workflow simply does not run (dev-migration-drift surfaces drift via annotations; main-health-monitor files/clears a ci/main-broken issue; review-reminder files review-reminder issues) — absence is the operator-visible signal these workflows already use."
  cadence: "dev-migration-drift 15 */6 * * *; main-health-monitor 0 */6 * * *; review-reminder 0 0 1 * * (all UTC)"
  alert_target: "cron-inngest-cron-watchdog Sentry monitor (scheduler liveness, NEW for these 3); existing per-workflow GitHub-issue surfaces (end-to-end)"
  configured_in: "server/inngest/cron-manifest.ts (EXPECTED_CRON_FUNCTIONS) + cron-inngest-cron-watchdog.ts"
error_reporting:
  destination: "Sentry issues stream via reportSilentFallback (token redacted) on a token-mint / Octokit dispatch failure"
  fail_loud: true
failure_modes:
  - mode: "Token mint fails (GitHub App JWT/installation error)"
    detection: "step.run('mint-installation-token') throws → caught → reportSilentFallback"
    alert_route: "Sentry issue (feature: cron-<name>, op: dispatch-workflow)"
  - mode: "workflow_dispatch POST fails (404 workflow-not-found, 403 perms, network)"
    detection: "Octokit request throws → catch arm"
    alert_route: "Sentry issue with redacted Error.message ([REDACTED-INSTALLATION-TOKEN])"
  - mode: "Dispatch returns 2xx but the GHA run never executes"
    detection: "no downstream workflow run → no drift annotation / no main-broken issue update / no review-reminder issue in window"
    alert_route: "existing per-workflow issue surfaces (operator-visible absence); scheduler-side covered by watchdog"
  - mode: "Scheduler stops firing the Inngest cron entirely"
    detection: "cron-inngest-cron-watchdog finds the fn unplanned"
    alert_route: "cron-inngest-cron-watchdog Sentry monitor (red)"
logs:
  where: "logger.info on successful dispatch ({ fn, workflow }); Sentry on failure. App stdout is NOT shipped to a log warehouse — diagnostics ride the Sentry event extra."
  retention: "Sentry default project retention"
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-dev-migration-drift.test.ts test/server/inngest/cron-main-health-monitor.test.ts test/server/inngest/cron-review-reminder.test.ts test/server/inngest/function-registry-count.test.ts test/server/cron-substrate-imports.test.ts"
  expected_output: "all suites pass; guard (a) asserts 47; each fn passes substrate-imports relative-import + no-local-redef guards"
```

## Test Scenarios

Each new test file (mirroring the template) covers:

1. **Import-time smoke** — `createFunction` export is defined (object).
2. **Registration source anchors** — `id`, `cron:` string, manual-trigger `event:`, `scope: "fn"`, `scope: "account"`, `retries: 1`.
3. **Dispatch-hybrid anchors** — the `dispatches` endpoint string, the `WORKFLOW_FILE` literal, `ref: "main"`, `@octokit/core`, `reportSilentFallback`.
4. **HARD-NON-GOAL anchors** — source does NOT contain `mkdtemp` / `spawn(` / `child_process` / `buildAuthenticatedCloneUrl` / `resolveCronWorkspaceRoot`.
5. **Happy path** — mints token, POSTs `dispatches` with exhaustive `toEqual` params (no `inputs`), returns `{ ok: true }`, reporter NOT called.
6. **Failure path** — Octokit throws an Error containing the fake token → `reportSilentFallback` called once with `feature: cron-<name>`; the `Error.message` does NOT contain the token AND DOES contain `[REDACTED-INSTALLATION-TOKEN]`; returns `{ ok: false }`.

## Risks & Mitigations

- **Registry count drift between plan and /work.** A sibling PR can shift guard (a)'s baseline. Mitigation: AC6 mandates re-deriving the literal with the test's exact regex at /work time; the delta is always +3.
- **Alphabetical-insertion mistakes in route.ts / manifest.** Guard (b) (route↔file parity) and guard (e) (manifest↔file parity) catch a missing/misnamed entry; ordering itself is convention (no test enforces alpha order, but keep it for diff clarity).
- **Accidentally importing `_cron-shared` via the `@/` alias.** Passes tsc + the fn's own test but fails `cron-substrate-imports.test.ts` in the full shard. Mitigation: AC7 + copy the template's relative import verbatim.
- **Vacuous redaction test.** `JSON.stringify(new Error(msg))` is `"{}"`. Mitigation: inspect `Error.message` directly + positive `[REDACTED-INSTALLATION-TOKEN]` control (template already does this).
- **review-reminder accidentally passing `date_override`.** Mitigation: AC2 omits `inputs` entirely → the workflow's `else` branch defaults `today` to `date -u +%Y-%m-%d`. Keeping the `date_override` workflow input intact preserves manual testability.
- **Precedent diff (deepen-plan Phase 4.4):** scheduled jobs follow ADR-033 (Inngest > GHA cron); precedent is the just-merged `cron-terraform-drift.ts`. Dispatch-hybrid here is the same credential/execution split (token-only in-process, execution stays in the ephemeral runner). No novel pattern.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan fills it: threshold `none` with a sensitive-path reason.)
- `function-registry-count.test.ts` guard (a) is a literal that a naive comma-split of `route.ts` will MIS-count (48 vs the test-exact 44) because the comma-split catches comment-line and `serve({ client: inngest,` artifacts. Always re-derive with the test's own regex `/^\s+(\w+),$/gm` (shell: `grep -cE '^[[:space:]]+\w+,$'`).
- Read the `EXIT=` marker from the `test-all.sh` log, not the background-wrapper exit code (tail-masking class).
