---
title: "feat(schedule): scheduled domain-model drift-check cron that auto-files drift issues"
issue: 5872
branch: feat-one-shot-5872-domain-model-drift-cron
date: 2026-07-02
type: feat
lane: single-domain
brand_survival_threshold: none
related_adrs: [ADR-076, ADR-033]
related_issues: [5754, 5871, 5773]
---

# feat(schedule): scheduled domain-model drift-check cron (auto-file drift issues) — #5872

## Overview

Catch domain-model **register drift** on a weekly cadence without a human remembering to run
`/soleur:sync domain-model`. A new Inngest cron fires weekly and dispatches a GitHub Actions
executor that runs the deterministic analyzer `scripts/domain-model-drift.sh drift`, parses the
**stale-citation sub-count**, and — only when the register cites a migration/symbol that no longer
resolves (`stale > 0`) — files (or updates) a single idempotent GitHub issue.

This is the recurring-work productization of the #5754 analyzer, anticipated by ADR-076
(`related: [... 5872]`, "a scheduled drift cron in #5872"). It consumes ADR-076's existing
exit-code / stale-count contract and adds **no** new analyzer behaviour.

**Two load-bearing decisions diverge from the literal feature wording** (see Research Reconciliation):
1. **No `claude-code-action` / no LLM.** Drift detection is 100% deterministic bash (ADR-076 §1: the
   LLM is *never* in the drift-detection path). The wrapper adds nothing — this is the wrapper-vs-curl
   call.
2. **`workflow_dispatch` executor fired by an Inngest cron, not a raw GHA `schedule:` trigger.** ADR-033
   makes Inngest the single scheduling substrate; a raw `schedule:` write is blocked by the
   `new-scheduled-cron-prefer-inngest` PreToolUse hook.

## Premise Validation

- **#5872 (work target):** OPEN. `type/feature`, `priority/p3-low`, `domain/engineering`. Not stale.
- **#5754 (dependency — the analyzer):** CLOSED/merged. `scripts/domain-model-drift.sh` (12 KB) and
  `scripts/lib/domain-model-lib.sh` exist and run. ✓
- **#5871 (enforcement gates):** shipped 2026-07-02. Preflight **Check 11** consumes the analyzer via
  the exact stale-count parser this cron reuses. ✓
- **ADR-076:** present, `status: accepted`, `related: [5754, 5871, 5872, 5773]`. The 2026-07-02
  enforcement amendment (§"Enforcement gates") is the authority for gating on the stale sub-count, not
  the exit code. ✓
- **Cited convention file `scheduled-daily-triage.yml`: DOES NOT EXIST** in this repo (the feature
  description's example is stale — daily triage now lives in `cron-daily-triage.ts` on Inngest). The
  real, freshest drift-class convention is `scheduled-terraform-drift.yml` + `cron-terraform-drift.ts`
  and `scheduled-dev-migration-drift.yml` + `cron-dev-migration-drift.ts`. Plan re-scoped to those.
- **Mechanism vs ADR corpus:** raw GHA `schedule:` cron is the mechanism ADR-033 rejected (Inngest is
  the single substrate). Plan adopts the Inngest-dispatch mechanism, not the rejected one.
- **Live analyzer run (2026-07-02, on `main`):** `drift` exits **1** with **0 stale citations / 35
  undocumented facts / 47 blind spots**. This is the steady state by design — proof that gating on the
  raw exit code would file a spurious issue every week. Gate keys on `stale` only.

## Research Reconciliation — Spec vs. Codebase

| Feature-description claim | Codebase reality | Plan response |
|---|---|---|
| "Reuse the … `claude-code-action` pattern" | Drift detection is deterministic bash (ADR-076 §1); the only `claude-code-action` crons are LLM-judgment ones (bug-fixer, daily-triage). Every deterministic-script drift cron (terraform, dev-migration, rule-prune) avoids the wrapper. | **No `claude-code-action`.** Executor = checkout + `bash …drift.sh` + `gh issue`. Wrapper-vs-curl: the LLM adds nothing. |
| "A scheduled GitHub Actions workflow … on a weekly cadence" (implying a GHA `schedule:` cron) | ADR-033: Inngest is the single scheduling substrate. `new-scheduled-cron-prefer-inngest` hook **blocks** a raw `schedule:` YAML write. The two newest drift workflows use `workflow_dispatch: {}` fired by an Inngest cron. | **`workflow_dispatch` executor + Inngest cron dispatcher.** Weekly cadence lives on the Inngest cron (`0 8 * * 1`), mirroring `cron-dev-migration-drift.ts`. |
| "see … existing `scheduled-daily-triage.yml`" | File does not exist; daily triage is `cron-daily-triage.ts`. | Re-based on `scheduled-terraform-drift.yml` (executor template) + `cron-dev-migration-drift.ts` (dispatcher template). |
| "auto-files a GitHub issue when register and source have diverged" (exit-code framing) | `drift` exits 1 on `stale>0 OR undoc>0`; undocumented facts = ~every un-curated table by design (ADR-076 enforcement §1). | Gate on **stale-citation sub-count > 0** only (reuse preflight Check 11 Step 11.2 parser verbatim). Undocumented/blind-spots are advisory context, never the trigger. |

## User-Brand Impact

**If this lands broken, the user experiences:** at worst, a *spurious* weekly maintenance issue in the
repo (noise for the operator) or a *missed* drift issue (register silently rots until the next PR trips
preflight Check 11 — which is the pre-existing backstop). No product surface is touched.

**If this leaks, the user's data is exposed via:** N/A — the cron reads repo schema *structure*
(table/policy names) and files an internal maintenance issue. No personal data is processed. The only
secret handled is a short-lived GitHub App installation token, redacted on error via `redactToken`
(same pattern as every dispatcher).

**Brand-survival threshold:** none — read-only drift-detection dev-tooling; files a maintenance issue,
touches no user data, no auth/session/PII surface. (Scope-out bullet for preflight Check 6: the diff
touches `apps/web-platform/server/inngest/` + `infra/`, but the change is a deterministic,
operator-facing CI cron with no user-data path. `threshold: none, reason: read-only structural
drift-detection cron; no user-data, auth, or session surface.`)

## Architecture Decision (ADR/C4)

This plan makes **no new** architectural decision — it *applies* two existing ADRs:

- **ADR-033** (Inngest is the single scheduling substrate) → dispatch-hybrid shape.
- **ADR-076** (domain-model drift extraction; stale-citation-not-exit-code gate) → the correctness contract.

### ADR
- **Amend ADR-076** with a one-line note under its 2026-07-02 enforcement section: the scheduled drift
  cron anticipated in `related: [5872]` is now built; it consumes the **stale-citation sub-count** (not
  the raw exit code) and the `rc 0/1/2/3` contract, mirroring preflight Check 11. This is an *amendment*
  (the decision already exists), not a new ADR. Do it via the `architecture` skill / Edit tool in this
  PR — not a deferred issue.

### C4 views
- **Task (must run before concluding):** read all three model files —
  `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` — and confirm no new
  element/relationship is required. Enumeration to check:
  - **External human actor:** none new (the cron reads the repo; no correspondent/reviewer/recipient).
  - **External system/vendor:** GitHub Actions + Inngest + Sentry are pre-existing CI/observability
    substrate (or out-of-boundary `#external`); the cron introduces none.
  - **Container / data store:** none new (files a GitHub issue; writes nothing to Supabase).
  - **Access/ownership relationship:** unchanged (no tenancy/ownership edge moves).
  - ADR-076 already concluded "None" for the analyzer's C4 impact; scheduling it changes no ownership
    edge, so the conclusion holds — cite this enumeration in the plan/PR, do not write a bare "None".

## Infrastructure (IaC)

Introduces (a) an Inngest cron function (code, deployed via the normal web-platform release pipeline —
container auto-restarts on merge; no provisioning step) and (b) **one Sentry cron monitor** (Terraform).

### Terraform changes
- `apps/web-platform/infra/sentry/cron-monitors.tf` — add `resource "sentry_cron_monitor"
  "scheduled_domain_model_drift"` (name/slug `"scheduled-domain-model-drift"`, `schedule.crontab`
  matching the Inngest cron `0 8 * * 1`, `checkin_margin_minutes = 120`, `max_runtime_minutes = 15`,
  `failure_issue_threshold = 1`, `recovery_threshold = 1`, `timezone = "UTC"`). Model verbatim on the
  `scheduled_terraform_drift` block (`cron-monitors.tf:83-93`).
- `.github/workflows/apply-sentry-infra.yml` — add `-target=sentry_cron_monitor.scheduled_domain_model_drift`
  to the plan/apply `-target=` allowlist. (Scope-guard `tests/scripts/test-destroy-guard-sentry-scope-guard.sh`
  keys on resource *type* `sentry_cron_monitor` — already allowlisted — so **no** scope-guard edit needed.)
- No provider/version changes; no new `TF_VAR_*`; the Sentry provider + creds already resolve for the
  existing 47 monitors.

### Apply path
- **Auto-apply on merge:** `apply-sentry-infra.yml` fires on push to `main` touching `cron-monitors.tf`
  and applies the `-target`-scoped set. No operator SSH, no manual `terraform apply`. Blast radius: one
  new monitor resource; existing monitors untouched (targeted apply).

### Distinctness / drift safeguards
- Single prd Sentry project (monitors are not dev/prd-split). No `lifecycle.ignore_changes` needed. The
  monitor value lands in Sentry SaaS state, not local tfstate secrets.

### Vendor-tier reality check
- Sentry cron monitors are within the existing paid tier (47 already provisioned). No tier gate.

## Observability

```yaml
liveness_signal:
  what: "scheduled-domain-model-drift Sentry cron monitor — heartbeat POSTed each executor run (ok on clean OR drift-filed; error on analyzer rc 2/3). Scheduler liveness also covered by cron-inngest-cron-watchdog via EXPECTED_CRON_FUNCTIONS."
  cadence: "weekly (Mon 08:00 UTC); missed run pages within the 120-min check-in margin"
  alert_target: "Sentry issues stream (monitor failure + failure_issue_threshold=1)"
  configured_in: "apps/web-platform/infra/sentry/cron-monitors.tf (monitor) + .github/workflows/scheduled-domain-model-drift.yml (heartbeat step) + apps/web-platform/server/inngest/cron-manifest.ts (watchdog purview)"
error_reporting:
  destination: "Dispatcher errors → reportSilentFallback (token-redacted) → Sentry issues. Executor analyzer rc==2/3 → heartbeat status=error + the job fails loudly (non-zero exit)."
  fail_loud: true
failure_modes:
  - mode: "Inngest dispatch fails (token mint / Octokit)"
    detection: "reportSilentFallback Sentry event (fn=cron-domain-model-drift, op=dispatch-workflow) + watchdog notices the cron did not run"
    alert_route: "Sentry issues"
  - mode: "Analyzer error (rc==2) — unanalyzable source / jq failure"
    detection: "heartbeat status=error; GHA job red; job-summary line prints rc + parsed stale=n/a"
    alert_route: "Sentry cron-monitor failure + GHA run failure"
  - mode: "Secret-refuse (rc==3) — secret-shaped substring in extracted structural text"
    detection: "heartbeat status=error; job-summary prints rc==3; NO drift issue filed"
    alert_route: "Sentry cron-monitor failure + GHA run failure"
  - mode: "Stale citation drift (stale>0)"
    detection: "idempotent GitHub issue filed/commented under label domain-model-drift"
    alert_route: "GitHub issue (operator-visible) + heartbeat status=ok (drift is a success path for the workflow)"
  - mode: "Duplicate issue on repeated runs"
    detection: "prevented — existing open issue with the exact title is commented, not re-created"
    alert_route: "n/a (idempotency invariant)"
logs:
  where: "GitHub Actions run logs (gh run view) + the executor's GITHUB_STEP_SUMMARY (rc + stale count) + Sentry"
  retention: "GHA default (90 days) + Sentry retention"
discoverability_test:
  command: "gh run list --workflow=scheduled-domain-model-drift.yml --limit 5  &&  gh issue list --label domain-model-drift --state all --limit 5"
  expected_output: "recent workflow runs (conclusion success) and any filed drift issue — NO ssh"
```

**§2.9.2 affected-surface (the executor is a blind cron surface):** the executor emits a **structured,
discriminating** signal into `GITHUB_STEP_SUMMARY` — `rc` (0/1/2/3) AND the parsed `stale` count AND
`undoc` count — so a single run event distinguishes clean (rc0), advisory-only-drift (rc1/stale0),
actionable drift (stale>0), analyzer error (rc2), and secret-refuse (rc3) without re-running or SSH.

## Implementation Phases

Phase order is dependency-directed (contract before consumer).

### Phase 0 — Preconditions (RED-supporting facts)
1. Confirm `scripts/domain-model-drift.sh drift --repo . --register knowledge-base/engineering/architecture/domain-model.md`
   runs and prints `## Stale register citations (N)` at column 0 (it does — verified 2026-07-02, rc=1, N=0).
2. Confirm the executor's runner needs only checkout + `bash`/`jq`/`sed`/`awk` + a GH token (no Doppler,
   no vendor cred). The analyzer reads migrations + the register from the checked-out tree; `jq` is
   present on `ubuntu-latest`.
3. Read `apps/web-platform/test/server/inngest/cron-dev-migration-drift.test.ts` — the exact test template.

### Phase 1 — Executor workflow (`.github/workflows/scheduled-domain-model-drift.yml`)
Model on `scheduled-terraform-drift.yml`. Contents:
- `on: workflow_dispatch: {}` **only** (no `schedule:`); `concurrency: { group: scheduled-domain-model-drift, cancel-in-progress: false }`; `permissions: { contents: read, issues: write }`; `timeout-minutes: 10`.
- Step: `actions/checkout` (SHA-pinned, `fetch-depth: 1`).
- Step "Run drift analyzer" (`id: drift`, `set +e`): run the analyzer to a temp file, capture `rc`, parse
  `stale`/`undoc` using the **preflight Check 11 Step 11.2 parser verbatim**:
  ```bash
  bash scripts/domain-model-drift.sh drift --repo . \
    --register knowledge-base/engineering/architecture/domain-model.md > "$RUNNER_TEMP/dm-drift.txt" 2>&1; rc=$?
  stale=$(grep -oE '^## Stale register citations \([0-9]+\)' "$RUNNER_TEMP/dm-drift.txt" | head -1 | grep -oE '[0-9]+'); stale=${stale:-0}
  undoc=$(grep -oE '^## Undocumented source facts \([0-9]+' "$RUNNER_TEMP/dm-drift.txt" | head -1 | grep -oE '[0-9]+'); undoc=${undoc:-0}
  { echo "rc=$rc"; echo "stale=$stale"; echo "undoc=$undoc"; } >> "$GITHUB_OUTPUT"
  { echo "### domain-model drift"; echo "rc=$rc stale=$stale undoc=$undoc"; } >> "$GITHUB_STEP_SUMMARY"
  ```
  On `rc==2` or `rc==3`: `echo "::error::…"; exit 1` (fail the job loudly; NOT a drift issue).
- Step "Ensure label" (`if: rc==0 or rc==1` i.e. analyzer succeeded, and `stale>0`): `gh label create "domain-model-drift" --description "domain-model register cites an unresolvable source (stale citation)" --color "FBCA04" 2>/dev/null || true`.
- Step "Create or update drift issue" (`if: steps.drift.outputs.stale > 0`): mirror
  `scheduled-terraform-drift.yml:131-197` idempotency — `TITLE="domain-model: register has stale citation(s)"`,
  `gh issue list --label domain-model-drift --state open --json number,title --jq 'select(.title==$T).number'`
  → if found `gh issue comment`, else `gh issue create --label domain-model-drift --milestone "Post-MVP / Later"`.
  Body: the stale section verbatim + run link + `## Next Steps` (run `/soleur:sync domain-model`; if a
  citation backticks a *filename*, unbacktick it — cite the citation-parser false-positive learning) +
  an advisory footer noting `undoc` count is expected-nonzero by design (never actionable).
- Step "Sentry check-in (final)" (`if: always()`, `continue-on-error: true`): `./.github/actions/sentry-heartbeat`,
  `monitor-slug: scheduled-domain-model-drift`, `status: ${{ (steps.drift.outputs.rc == '0' || steps.drift.outputs.rc == '1') && 'ok' || 'error' }}`, forward the three `secrets.SENTRY_*`.

### Phase 2 — Dispatcher (`apps/web-platform/server/inngest/functions/cron-domain-model-drift.ts`)
Copy `cron-dev-migration-drift.ts` and adjust: `FUNCTION_NAME="cron-domain-model-drift"`,
`WORKFLOW_FILE="scheduled-domain-model-drift.yml"`, cron `0 8 * * 1`, trigger event
`cron/domain-model-drift.manual-trigger`, `id: "cron-domain-model-drift"`. Same
`concurrency: [{scope:"fn",limit:1},{scope:"account",key:'"cron-platform"',limit:1}]`, `retries: 1`,
`mintInstallationToken({tokenMinLifetimeMs: 5*60*1000})`, `redactToken` on error, `reportSilentFallback`.
Keep the HARD NON-GOAL comment (dispatch-only; no clone, no spawn) so the test's negative anchors pass.

### Phase 3 — Registration + parity (the hand-maintained-allowlist sweep)
Per the routine-authoring directive (`apps/web-platform/server/routine-authoring-directive.ts:23-28`) + the two enumeration sweeps:
- `apps/web-platform/app/api/inngest/route.ts` — add `import { cronDomainModelDrift } …` and
  `cronDomainModelDrift,` to the `functions: [ … ]` array.
- `apps/web-platform/server/inngest/cron-manifest.ts` — add `"cron-domain-model-drift",` to
  `EXPECTED_CRON_FUNCTIONS` (alphabetical). (Auto-derives the manual-trigger allowlist + watchdog purview.)
- `apps/web-platform/server/inngest/routine-metadata.ts` — add a `"cron-domain-model-drift": { description, domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Weekly (Mon 08:00 UTC)", manualTrigger: "allowed" }` entry (capitalization matches sibling `:59`).

### Phase 4 — Sentry monitor IaC
- `apps/web-platform/infra/sentry/cron-monitors.tf` — add the `sentry_cron_monitor` resource (Phase = IaC section above).
- `.github/workflows/apply-sentry-infra.yml` — add the `-target=sentry_cron_monitor.scheduled_domain_model_drift` line.

### Phase 5 — Tests (write failing first where meaningful)
- New `apps/web-platform/test/server/inngest/cron-domain-model-drift.test.ts` — mirror
  `cron-dev-migration-drift.test.ts` (registration source-shape anchors, dispatch-hybrid anchors, HARD
  NON-GOAL negative anchors `mkdtemp`/`spawn(`/`child_process`, behaviour: mints token → POST dispatch
  `toEqual({owner,repo,workflow_id,ref})` → `{ok:true}`; on throw → Sentry + `{ok:false}` + token redacted).
- `apps/web-platform/test/server/inngest/function-registry-count.test.ts` — bump the hardcoded route
  count `toBe(58)` → `toBe(59)` (test (a)); add `"scheduled-domain-model-drift"` to the
  `NON_INNGEST_MONITORS` set (test (c2), lines 109-116) so the new GHA-fired monitor is not a "phantom".
- (Auto-green, no edit — verify they pass: `routine-metadata-parity.test.ts`, `manual-trigger-allowlist.test.ts`,
  `plugins/soleur/test/trigger-cron-allowlist-parity.test.ts`, `list-routines.test.ts`, `sentry-monitor-iac-parity.test.ts`.)

### Phase 6 — ADR-076 amendment + C4 confirmation
- Amend ADR-076 (one line, enforcement section). Read the three `.c4` files; cite the "no C4 impact"
  enumeration (Architecture Decision section). Run `apps/web-platform/test/c4-code-syntax.test.ts` +
  `c4-render.test.ts` only if a `.c4` edit is made (expected: none).

### Phase 7 — Verify
- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-domain-model-drift.test.ts test/server/inngest/function-registry-count.test.ts test/server/inngest/routine-metadata-parity.test.ts test/lib/inngest/manual-trigger-allowlist.test.ts test/server/inngest/sentry-monitor-iac-parity.test.ts`.
- `actionlint .github/workflows/scheduled-domain-model-drift.yml` (workflow) + `bash -n`-equivalent on the extracted `run:` shell.
- Dry-run the executor's drift+parse block locally against `main` (expect `rc=1 stale=0 undoc=35` → **no** issue filed).

## Files to Create
- `.github/workflows/scheduled-domain-model-drift.yml` — executor (workflow_dispatch; deterministic bash + idempotent `gh issue` + Sentry heartbeat).
- `apps/web-platform/server/inngest/functions/cron-domain-model-drift.ts` — Inngest weekly dispatcher (mirror `cron-dev-migration-drift.ts`).
- `apps/web-platform/test/server/inngest/cron-domain-model-drift.test.ts` — dispatcher test (mirror `cron-dev-migration-drift.test.ts`).

## Files to Edit
- `apps/web-platform/app/api/inngest/route.ts` — import + `functions:[…]` array entry.
- `apps/web-platform/server/inngest/cron-manifest.ts` — `EXPECTED_CRON_FUNCTIONS += "cron-domain-model-drift"`.
- `apps/web-platform/server/inngest/routine-metadata.ts` — `ROUTINE_METADATA` entry.
- `apps/web-platform/test/server/inngest/function-registry-count.test.ts` — bump `toBe(58)`→`toBe(59)`; add slug to `NON_INNGEST_MONITORS`.
- `apps/web-platform/infra/sentry/cron-monitors.tf` — add `sentry_cron_monitor.scheduled_domain_model_drift`.
- `.github/workflows/apply-sentry-infra.yml` — add the `-target=` line.
- `knowledge-base/engineering/architecture/decisions/ADR-076-domain-model-drift-extraction.md` — one-line amendment.

## Acceptance Criteria

### Pre-merge (PR)
1. `scheduled-domain-model-drift.yml` exists, has `on: workflow_dispatch` with **no `schedule:` key**
   (`! grep -qE '^\s*schedule:' .github/workflows/scheduled-domain-model-drift.yml`), and its drift step
   uses the Check-11 parser (`grep -qF '^## Stale register citations' <workflow>` matches the anchored parse).
2. The workflow files an issue **only** when `steps.drift.outputs.stale > 0` — grep the create/comment
   step's `if:` for `stale` (and confirm it does NOT gate on `rc == '1'` or raw exit).
3. `cron-domain-model-drift.ts` registers `{ cron: "0 8 * * 1" }` and `{ event: "cron/domain-model-drift.manual-trigger" }`,
   dispatches `workflow_id: "scheduled-domain-model-drift.yml"`, `ref: "main"`, and contains **no**
   `mkdtemp`/`spawn(`/`child_process` (dispatch-only).
4. `EXPECTED_CRON_FUNCTIONS` contains `"cron-domain-model-drift"`; `route.ts` `functions` array contains
   `cronDomainModelDrift`; `ROUTINE_METADATA` has the entry.
5. `function-registry-count.test.ts` route-count is `59` and `NON_INNGEST_MONITORS` contains `"scheduled-domain-model-drift"`.
6. `cron-monitors.tf` has `sentry_cron_monitor "scheduled_domain_model_drift"` (name `"scheduled-domain-model-drift"`, crontab `0 8 * * 1`); `apply-sentry-infra.yml` `-target=` list contains `sentry_cron_monitor.scheduled_domain_model_drift`.
7. `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes; the vitest set in Phase 7 passes; `actionlint` passes on the new workflow.
8. Local dry-run of the parse block against `main` yields `stale=0` → **no** `gh issue create` invoked
   (idempotency + no-false-positive proof).
9. ADR-076 amended in-PR (not a follow-up issue); "no C4 impact" line cites the external-actor/system/relationship enumeration against all three `.c4` files.

### Post-merge (operator — all automatable, none SSH)
10. Sentry monitor auto-applies: `apply-sentry-infra.yml` fires on the `cron-monitors.tf` change (verify:
    `gh run list --workflow=apply-sentry-infra.yml --limit 3` shows success). — automatable, no operator step.
11. Manual smoke: `gh workflow run scheduled-domain-model-drift.yml --ref main` after merge → the run
    completes success and files **no** issue (main is stale=0). Then optionally fire the Inngest manual
    trigger via `/soleur:trigger-cron` (`cron/domain-model-drift.manual-trigger`) to prove the dispatch path.

## Test Scenarios
- **Clean register (main today):** rc=1, stale=0 → no issue, heartbeat ok. (The core no-false-positive case.)
- **Injected stale citation** (fixture: a register row citing a nonexistent migration): rc=1, stale=1 →
  issue created; second run → same issue commented, **not** duplicated.
- **Analyzer error (rc=2)** / **secret-refuse (rc=3):** job fails loudly, heartbeat error, no drift issue.
- **Dispatch failure** (Octokit throws in the Inngest fn): `reportSilentFallback` fires, token redacted, `{ok:false}`.

## Alternatives Considered
| Alternative | Rejected because |
|---|---|
| **`claude-code-action` executor** (literal feature wording) | Drift detection is deterministic bash (ADR-076 §1); the wrapper adds an LLM to a pure set-diff. Wrapper-vs-curl: skip it. Every deterministic drift cron in-repo avoids it. |
| **Raw GHA `schedule:` cron** (no Inngest) | ADR-033-rejected mechanism; blocked by `new-scheduled-cron-prefer-inngest` hook. |
| **In-process Inngest (mirror `cron-rule-prune.ts`, no GHA workflow)** | rule-prune clones + spawns in-process because it opens a **PR** (needs commit/branch/synthetic-checks). domain-model-drift only reads the repo + files an **issue** — porting idempotent `gh issue` list/create/comment into TS + adding ephemeral-clone/disk management is *more* code than reusing `scheduled-terraform-drift.yml`'s battle-tested block. Dispatch-hybrid also matches the literal "GitHub Actions workflow" ask and the two freshest drift precedents. *(CTO to bless — see Domain Review.)* |
| **Gate on raw exit code (rc==1 → file issue)** | Files a spurious issue every week (undoc=35 by design). ADR-076 enforcement §1 mandates the stale sub-count. |
| **Design A, no own Sentry monitor** (mirror `cron-dev-migration-drift.yml`) | Simpler (no `cron-monitors.tf`/`apply-sentry-infra.yml` edit), but a weekly mostly-clean cron has weak absence-based liveness — a broken executor that files nothing is invisible. The own-monitor cost is fully-automated IaC (auto-apply on merge). *(CTO to weigh — Domain Review.)* |

## Open Code-Review Overlap
Scanned 61 open `code-review` issues against the planned file set. The only hits were three issues
mentioning `route.ts` — **#3739** (`reportSilentFallbackWithUser` helper), **#3351** (kb-upload multipart
streaming), **#2246** (kb polish) — all reference *other* `route.ts` files (kb-upload / kb routes), **not**
`app/api/inngest/route.ts` (this plan only adds one import + one array entry there). **Disposition:
Acknowledge** — no genuine overlap; no fold-in required. All other planned files: no matches.

## Domain Review
Product = NONE (no UI-surface file: no `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`
created — mechanical override does not fire). Only engineering/CTO is relevant.

**Domains relevant:** engineering (CTO)

### Engineering (CTO)
**Status:** reviewed
**Assessment:** All cited precedents verified. Dispatch-hybrid is correct — the decisive reason is
*sharper* than "mirror dev-migration": the in-process sibling `cron-rule-prune` runs on-host **only
because it opens a PR** (`safeCommitAndPr`, depth-1 clone, disk guard); domain-model-drift **writes
nothing** (files an issue), so the in-process rationale is entirely absent. **The executor's closest
template is `scheduled-terraform-drift.yml`** (also a dispatch-hybrid that files an idempotent GH issue +
posts a Sentry heartbeat) — mirror it, not dev-migration (which only emits `::warning::` and files no
issue). Own Sentry monitor: **provision it** (Design A watchdog-only absence-liveness is too weak at
weekly cadence — up to 7 days undetected rot). No new ADR (instance of ADR-033 + ADR-076); capture the
own-monitor rationale in the plan (done). ~1 day, 7-site sweep is the risk (not difficulty). No
capability gaps.

**CTO-surfaced refinements folded into this plan:**
- **[HIGH] Empty-stale-string guard (unattended path).** Under rc∈{0,1}, distinguish *parse succeeded →
  stale=0* from *empty/missing stale string* (truncated report / format drift). Do NOT blanket-coerce
  empty→0 (silently suppresses a real drift issue). Treat empty-stale-with-rc∈{0,1} as an **anomaly →
  error heartbeat, file nothing.** Preflight Check 11 runs *attended* against a known-good report and
  doesn't need this; the cron runs unattended and does. (Folded into Phase 1.2 + AC + Sharp Edges.)
- **[MEDIUM] Constant idempotency title.** terraform-drift keys idempotency on **exact title match** —
  the title MUST be a fixed literal (`"domain-model: register drift detected"`); timestamp + stale count
  + advisory undoc/blind-spot context live in the **body/comment only**. (Folded into Phase 1.4 + AC.)
- **Monitor margin = 60 min** (Inngest-dispatch cohort convention), not 120. (Folded into IaC section.)
- **Heartbeat status = ok on rc∈{0,1}, error on rc∈{2,3}** — issue-filing is orthogonal to status.
- **Confirm #5754 artifacts are on `origin/main`** before first dispatch (executor checks out `main`).
  (Folded into Phase 0.)

## Deepen-Plan Research Insights (2026-07-02)

**Halt-gates:** 4.6 User-Brand Impact ✓ (threshold `none` + scope-out reason), 4.7 Observability ✓
(all 5 fields, no `ssh` in `discoverability_test`), 4.8 PAT-shaped-var ✓ (none), 4.9 UI-wireframe ✓
(no UI surface — skipped). 4.4 Scheduled-work precedent check ✓ (44 `cron-*.ts` Inngest functions
exist → Inngest is canonical; GHA `schedule:` is the rejected mechanism).

**Every load-bearing concrete fact verified against `main` (2026-07-02):**
- `apps/web-platform/test/server/inngest/function-registry-count.test.ts:135` = `expect(routeEntries.length).toBe(58)` → bump to **59**. `NON_INNGEST_MONITORS` set at **line 109** (the GHA-fired slug must be added there — test (c2) at line 175 reds otherwise).
- `EXPECTED_CRON_FUNCTIONS` array (`cron-manifest.ts:22`) contains `"cron-dev-migration-drift"` (:36), `"cron-terraform-drift"` (:62) — insert `"cron-domain-model-drift"` alphabetically.
- `route.ts`: import at top (pattern `import { cronDevMigrationDrift } from "@/server/inngest/functions/cron-dev-migration-drift";` :35) + array entry (`cronDevMigrationDrift,` :134).
- **Monitor resource — exact template (`cron-monitors.tf:83-92`, verbatim shape):**
  ```hcl
  resource "sentry_cron_monitor" "scheduled_domain_model_drift" {
    organization            = var.sentry_org
    project                 = data.sentry_project.web_platform.slug
    name                    = "scheduled-domain-model-drift"
    schedule                = { crontab = "0 8 * * 1" }
    checkin_margin_minutes  = 60
    max_runtime_minutes     = 15
    failure_issue_threshold = 1
    recovery_threshold      = 1
    timezone                = "UTC"
  }
  ```
  `apply-sentry-infra.yml` `-target=` list starts at **line 197** (add the new resource there).
- **`routine-metadata.ts` entry — match sibling capitalization exactly** (`:59`): `domain: "Engineering"`
  (capital E, not `engineering`), `ownerRole: "CTO"`, `manualTrigger: "allowed"`,
  `scheduleLabel: "Weekly (Mon 08:00 UTC)"`.
- `sentry-heartbeat` composite action: `monitor-slug` input is `required: true`; the executor forwards
  `secrets.SENTRY_INGEST_DOMAIN` / `SENTRY_PROJECT_ID` / `SENTRY_PUBLIC_KEY` (as `scheduled-terraform-drift.yml:257-259`).

**Precedent-diff (executor idempotency):** the create/update-issue block mirrors
`scheduled-terraform-drift.yml:131-197` — exact-title match via
`gh issue list --label <l> --state open --json number,title --jq '.[] | select(.title=="<T>") | .number' | head -1`,
comment if found else create. No novel pattern.

## Deepen-Plan Research Insights (2026-07-02)

**Halt-gates:** 4.6 User-Brand Impact ✓ (threshold none + scope-out reason), 4.7 Observability ✓ (all 5
fields, no ssh in discoverability_test), 4.8 PAT-shaped variable ✓ (none), 4.9 UI-wireframe ✓ (no
UI-surface file — skip). Precedent-diff §4.4 scheduled-work check: 44 `cron-*.ts` Inngest functions
exist → Inngest dispatch is canonical (ADR-033). ✓

**Load-bearing facts verified live against `main`:**
- `function-registry-count.test.ts:135` — `expect(routeEntries.length).toBe(58)` → bump to **59**.
- `NON_INNGEST_MONITORS` set at `function-registry-count.test.ts:109` (used at `:175`) — add
  `"scheduled-domain-model-drift"` (heartbeat comes from a GHA executor, not an Inngest slug, else parity
  test (c2) reds).
- `EXPECTED_CRON_FUNCTIONS` at `cron-manifest.ts:22` (array of strings; `"cron-dev-migration-drift"`
  `:36`, `"cron-terraform-drift"` `:62`) — add `"cron-domain-model-drift"` alphabetically.
- `route.ts` — import at `:35` (`import { cronDevMigrationDrift } from "@/server/inngest/functions/cron-dev-migration-drift";`) + array entry at `:134`. Mirror for the new fn.
- **Sentry monitor block (copy `cron-monitors.tf:83-92` verbatim; substitute name/crontab):**
  ```hcl
  resource "sentry_cron_monitor" "scheduled_domain_model_drift" {
    organization            = var.sentry_org
    project                 = data.sentry_project.web_platform.slug
    name                    = "scheduled-domain-model-drift"
    schedule                = { crontab = "0 8 * * 1" }
    checkin_margin_minutes  = 60
    max_runtime_minutes     = 15
    failure_issue_threshold = 1
    recovery_threshold      = 1
    timezone                = "UTC"
  }
  ```
- `apply-sentry-infra.yml` `-target=` list starts `:197` — append `-target=sentry_cron_monitor.scheduled_domain_model_drift`.
- `sentry-heartbeat` composite action requires input `monitor-slug` (`.github/actions/sentry-heartbeat/action.yml`) — pass `scheduled-domain-model-drift`.

**Correction (routine-metadata shape):** sibling entry is
`"cron-dev-migration-drift": { description, domain: "Engineering", ownerRole: "CTO", scheduleLabel: "Every 6h (:15)", manualTrigger: "allowed" }` (`routine-metadata.ts:59`). Use `domain: "Engineering"`
(capital E) + `ownerRole: "CTO"` + `scheduleLabel: "Weekly (Mon 08:00 UTC)"` to match the parity test's
casing expectations.

## Sharp Edges
- **The stale-count gate is the whole feature.** Do not "simplify" the executor to gate on `rc`/exit code
  — `undoc` is nonzero by design; only `stale` is the signal. Reuse the Check 11 parser verbatim; a
  divergent parser is a drift-between-two-parsers bug.
- **`^`-anchor + `head -1` on the stale grep is load-bearing** — an unanchored grep can match a
  verbatim-SQL predicate line echoing the substring, breaking the numeric test (per Check 11's own note).
- **No `schedule:` key in the workflow** — the `new-scheduled-cron-prefer-inngest` hook blocks it; the
  cadence lives on the Inngest cron. If a raw `schedule:` is ever needed, it requires an explicit
  `<!-- gate-override: new-scheduled-cron-prefer-inngest -->` marker (not the case here).
- **`function-registry-count.test.ts` has a HARDCODED route count** (`toBe(58)`) — adding the dispatcher
  requires bumping it to `59`, and adding the GHA slug to `NON_INNGEST_MONITORS` or test (c2) reds.
- **The Inngest fn's trigger event string must match the derived allowlist** — `cron-domain-model-drift`
  → `cron/domain-model-drift.manual-trigger` (derived in `cron-manifest.ts`); a mismatch fails
  `manual-trigger-allowlist.test.ts`.
- A plan whose `## User-Brand Impact` section is empty, `TBD`, or omits the threshold fails deepen-plan
  Phase 4.6. It is filled above (threshold: none, with sensitive-path scope-out reason).

## Non-Goals
- No change to `scripts/domain-model-drift.sh` or the analyzer's contract (consume-only).
- No approval-gated `write-row` / auto-inference in the cron (that stays the interactive `/soleur:sync domain-model` path; the cron only *detects* and *notifies*).
- No gating on undocumented facts / blind spots (advisory-only, by ADR-076 design).
- No update to the `/soleur:schedule` skill (its Inngest-routing gate already covers this class; out of scope).
