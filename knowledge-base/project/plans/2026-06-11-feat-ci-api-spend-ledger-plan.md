---
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
closes: 5086
related: [5085, 5173]
brainstorm: knowledge-base/project/brainstorms/2026-06-11-loop-token-cost-ledger-brainstorm.md
spec: knowledge-base/project/specs/feat-loop-token-cost-ledger/spec.md
---

# Plan: Monthly metered-API-spend rollup for engineering automation (#5086)

## Overview

Capture the genuinely-metered Anthropic API spend from the two CI `claude-code-action`
jobs (`claude-code-review.yml`, `test-pretooluse-hooks.yml`, both `anthropic_api_key`-authed →
real per-token charges) and surface it as **one** monthly R&D rollup line in the ops ledger.

Local autonomous loops (`one-shot`, `drain-labeled-backlog`, `test-fix-loop`, `*.workflow.js`)
run on the flat Max-20x subscription → **$0 marginal**; they are framed "$0 extra, covered by
subscription" and get **no** per-loop dollar figure (per the brainstorm reframe — per-loop dollars
on $0-marginal runs manufacture a false billing surprise and break BYOK trust).

**Capture mechanism (the key architecture decision, ADR-056):** each CI run extracts only an
allowlisted record `{run_id, sha, workflow, timestamp, model, input_tokens, output_tokens,
total_cost_usd, provenance}` from the action's `execution_file` output and **uploads it as a
GitHub Actions artifact** — NOT a per-run commit back to the repo. A monthly agent-run
reconciliation (ops-advisor; runbook in this PR, automated later by #5173) downloads the period's
artifacts, appends them to a committed `knowledge-base/finance/api-spend-ledger.jsonl` in **one**
commit, sums `total_cost_usd`, and updates the single `expenses.md` rollup line + `cost-model.md`.

Rejected: per-CI-run write-back to a committed JSONL (concurrency conflicts on parallel PR runs,
noisy per-run commits, ambiguous branch targeting). Artifacts are per-run, conflict-free, and
90-day-durable — long enough for monthly aggregation and for #5173's deviation baseline.

## Premise Validation

All cited references verified fresh in the 2026-06-11 brainstorm and re-confirmed here:
- #5086 OPEN (target), #5085 OPEN (digest, sequence-after), #5173 OPEN (deferred Phase 2). Held.
- `claude-code-action@v1.0.101` exposes `execution_file` output (verified via `gh api` on the
  pinned SHA `ab8b1e64…`). Both Soleur workflows pass `anthropic_api_key` (not
  `claude_code_oauth_token`) → metered. Held.
- `expenses.md` + `cost-model.md` exist; ledger row shape ("Anthropic API (ux-audit)") is the
  mirror precedent. Held.
- **Stale-reference note (non-blocking):** `expenses.md`'s ux-audit line cites
  `.github/workflows/scheduled-ux-audit.yml`, which does not exist at that path. Out of scope — we
  mirror the row *shape*, not that workflow. Flagged for a future ledger-hygiene pass.

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Codebase reality | Plan response |
|---|---|---|
| "committed machine-written sidecar" (spec FR2) | Per-run commit-from-CI is conflict-prone | Sidecar is committed, but written **once per month** by the reconciliation step from artifacts — not per CI run. ADR-056 records this. |
| `execution_file` → `total_cost_usd` | **Verified at plan time:** `execution_file` is a JSON **array**; its final element is `{"type":"result","total_cost_usd":0.0347,"duration_ms":…}`. `total_cost_usd` is present and read (`anthropics/claude-code-action@v1.0.101` `src/entrypoints/format-turns.ts:400`; fixture `test/fixtures/sample-turns.json:191-192`). jq path: `map(select(.type=="result"))[-1].total_cost_usd`. | Path pinned in `extract-api-spend.sh`. Phase 0 only **confirms against one real run** (defense vs upgrade drift), no longer discovers the shape. |
| "ops-advisor updates the line" | `test-all.sh` runs top-level `scripts/*.test.sh` only via explicit `run_suite` (line 121), not glob | New test gets an explicit `run_suite` line in `test-all.sh` (orphan-suite sharp edge). |
| ADR for data-model | Highest existing ADR is ADR-055 | New ADR is **ADR-056**. |

## User-Brand Impact

**If this lands broken, the user experiences:** a wrong or stale cost figure in the ops ledger —
either a phantom charge (false billing surprise) or a silently-empty rollup that falsely reassures
the operator their automation is free when it isn't.

**If this leaks, the user's data/money is exposed via:** the `execution_file` contains full
Claude Code message logs (prompts, diffs, tool output) and is authenticated with `ANTHROPIC_API_KEY`.
Persisting the raw file — or an un-allowlisted extract — could commit an API key, org id, or PR
source into a public-history git file. The extract allowlist + its test is the redaction boundary.

**Brand-survival threshold:** single-user incident. `requires_cpo_signoff: true` — CPO sign-off
carried forward from the brainstorm `## Domain Assessments` (CPO assessed the reframe). `user-impact-reviewer`
runs at PR review.

## Architecture Decision (ADR-056 — to author in Phase 0)

- **Sidecar:** `knowledge-base/finance/api-spend-ledger.jsonl` (finance-rooted: cost-model.md is the
  primary derived consumer; CFO classifies CI spend as R&D).
- **Cost source (verified):** `execution_file` is a JSON array; cost = `map(select(.type=="result"))[-1].total_cost_usd`.
- **Capture:** per-run GH artifact `api-spend-${{ github.run_id }}` carrying only the allowlist record.
- **Persistence:** monthly agent-run reconciliation appends artifacts → committed JSONL (one commit/mo).
- **Redaction boundary:** raw `execution_file` is read transiently on the runner; only the allowlisted
  record is ever uploaded or committed. Never upload the raw `execution_file`.
- **Classification:** R&D / dev-tooling (engineering accelerator), distinct from the COGS ux-audit line.

## Implementation Phases

### Phase 0 — Preconditions (verify before coding)
1. **Confirm** (not discover — shape is verified above) the pinned jq path
   `map(select(.type=="result"))[-1].total_cost_usd` against ONE real `claude-code-review` run's
   `execution_file`, guarding against an action-upgrade drift. Record in the ADR.
2. Add `id: claude-hooks-test` to the `claude-code-action` step in `test-pretooluse-hooks.yml` (it has
   none today; `claude-code-review.yml`'s is `claude-review`).
3. Author **ADR-056** (`/soleur:architecture`) capturing the decision + the verified jq path.

### Phase 1 — Extract helper (tested redaction boundary)
- `scripts/extract-api-spend.sh <execution_file>`: jq pipeline that **explicitly key-projects** the 9
  allowlist fields (never passthrough/merge) AND **type-coerces** numerics (`total_cost_usd|tonumber`,
  token fields `|tonumber`) so a string injection cannot ride in a numeric field. Tokens summed from
  assistant-turn `usage`; cost from the result object. Fail-closed to empty + exit≠0 on malformed input.
- `scripts/extract-api-spend.test.sh` + `scripts/fixtures/execution-file-sample.json` (synthetic,
  `<<…>>` placeholder tokens per the push-protection sharp edge). Cases: (a) happy path emits EXACTLY
  the 9 allowlist keys, nothing else; (b) fixture seeded with a fake `sk-ant-<<…>>`/`org_id` in an
  **excluded** field → absent from output; **(c) fake key seeded INSIDE an allowlisted value field
  (e.g. model `"claude-3-sk-ant-<<…>>"`) → output contains no `sk-ant`/`org_` substring anywhere**
  (Kieran value-injection case); (d) malformed/empty input → empty output + exit≠0.
- Add an explicit `run_suite "extract-api-spend" bash scripts/extract-api-spend.test.sh` line to
  `scripts/test-all.sh` (top-level `scripts/*.test.sh` is NOT auto-globbed — see SE; 4 suites already orphaned).

### Phase 2 — CI capture steps (both workflows)
- After the `claude-code-action` step, add a step
  `if: steps.<id>.outputs.execution_file != ''` (`<id>` = `claude-review` / `claude-hooks-test`) with
  **`continue-on-error: true`** (cost-capture flakiness must NEVER red the gating review — a guarded
  shell that `exit 1`s still fails the job) that runs `extract-api-spend.sh` on the output file, writes
  the record to a temp file, and uploads it via
  `actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4.6.2` (repo SHA-pin convention,
  per `ci.yml:475`) named `api-spend-${{ github.run_id }}`. Upload ONLY the extracted record — never
  the raw `execution_file`. (Optional: echo the one-line cost to `$GITHUB_STEP_SUMMARY`.)

### Phase 3 — Ledger seed + reconciliation runbook
- Seed empty `knowledge-base/finance/api-spend-ledger.jsonl`.
- `knowledge-base/engineering/operations/runbooks/api-spend-reconciliation.md`: a **concise command
  block** (not a failure-mode doc — that lives in Observability), agent-run monthly:
  `gh run list --workflow claude-code-review.yml --json databaseId,createdAt` → `gh run download -n
  api-spend-<id>` → append to JSONL → `jq -s 'map(.total_cost_usd)|add'` → update the expenses line +
  cost-model. No-SSH. One line noting the 90-day artifact window (#5173 cron closes it).
- `expenses.md`: add ONE R&D/dev-tools line "Anthropic API (CI claude-code-action)", status
  `accruing`, amount seeded `0.00` (provenance: estimate/accruing — first real reconciliation due next
  month), notes → cross-link the sidecar (`finance/api-spend-ledger.jsonl`) + runbook + provenance.
- `cost-model.md`: reference the new line under **R&D / Dev Tooling** (initially $0/accruing), plus a
  **one-line** Max-20x token-ceiling-spillover exposure note (CFO carry-forward; documented future-watch,
  no automated quota signal exists today — re-evaluate on rate-limit/slowdown symptoms).

## Files to Create
- `knowledge-base/engineering/architecture/decisions/ADR-056-ci-api-spend-ledger.md`
- `scripts/extract-api-spend.sh`
- `scripts/extract-api-spend.test.sh`
- `scripts/fixtures/execution-file-sample.json`
- `knowledge-base/finance/api-spend-ledger.jsonl` (empty seed)
- `knowledge-base/engineering/operations/runbooks/api-spend-reconciliation.md`

## Files to Edit
- `.github/workflows/claude-code-review.yml` (extract + upload step after `claude-review`)
- `.github/workflows/test-pretooluse-hooks.yml` (same; verify/add the action step id)
- `scripts/test-all.sh` (`run_suite` line for the new test)
- `knowledge-base/operations/expenses.md` (one rollup line)
- `knowledge-base/finance/cost-model.md` (R&D reference + spillover trigger note)

## Acceptance Criteria

### Pre-merge (PR)
1. `extract-api-spend.sh` on the fixture emits a record whose keys are EXACTLY the 9-field allowlist;
   numeric fields are typed (`total_cost_usd` is a number, token fields are ints). Test-asserted.
2. Seeded fake `sk-ant-…`/`org_id` in an EXCLUDED fixture field → absent from output.
3. **(value-injection)** Seeded fake `sk-ant-…` INSIDE an allowlisted value (model string) → output
   contains no `sk-ant`/`org_` substring anywhere. Test-asserted.
4. Malformed/empty `execution_file` → empty output + exit≠0; no artifact uploaded.
5. AC3 of `test-all.sh`: `grep -q 'run_suite "extract-api-spend"' scripts/test-all.sh` returns 0 (the
   line is present in source — a missing line still exits 0, so assert the source, not the run output).
6. Both workflows' extract step has BOTH `if: steps.<id>.outputs.execution_file != ''` AND
   `continue-on-error: true` (grep both).
7. Neither workflow's upload `path:` is the raw `execution_file` — only the extracted record (grep).
8. `upload-artifact` is SHA-pinned to `@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4.6.2` in both.
9. `expenses.md` has exactly one new line that cross-links `finance/api-spend-ledger.jsonl` + the
   runbook; `cost-model.md` references the line + carries the one-line spillover note.
10. ADR-056 exists and records the artifact-vs-commit decision + the verified jq path.
11. `knowledge-base/finance/api-spend-ledger.jsonl` exists (empty); the runbook names its path and the
    `expenses.md` note links back to it (bidirectional cross-link).

### Post-merge (operator/agent — automatable, no SSH)
12. After the first post-merge `claude-code-review` run, confirm an `api-spend-<run_id>` artifact exists
    (`gh run view <id> --json …` / `gh api`). Automatable via `gh`; not an operator dashboard step.
13. First monthly reconciliation (≥1 run accrued): run the runbook, confirm the JSONL gains records and
    the expenses line flips from `accruing` to a `recorded-actual` dollar figure. Agent-run; tracked by #5173 for automation.

## Observability

```yaml
liveness_signal:
  what: presence of an api-spend-<run_id> artifact per claude-code-action run
  cadence: per CI run (PR events)
  alert_target: monthly reconciliation gap (zero artifacts in a month where CI ran)
  configured_in: .github/workflows/{claude-code-review,test-pretooluse-hooks}.yml upload step
error_reporting:
  destination: GitHub Actions run log + step annotation (extract step is non-fatal:
    a parse failure logs ::warning:: and skips upload; it must NOT fail the review job)
  fail_loud: true (annotation), fail_safe (does not block the gating review)
failure_modes:
  - mode: execution_file absent (action skipped via preflight)
    detection: if-guard skips the step
    alert_route: none needed (expected)
  - mode: execution_file shape drift (jq path no longer matches after an action upgrade)
    detection: extract-api-spend.sh emits empty record / non-zero
    alert_route: ::warning:: annotation in the run; reconciliation sees a gap
  - mode: artifact retention lapse (>90d before reconciliation)
    detection: runbook step counts runs vs downloadable artifacts
    alert_route: runbook notes the window; #5173 cron closes it
logs:
  where: GitHub Actions run logs + the committed JSONL
  retention: artifacts 90d; JSONL permanent (git history)
discoverability_test:
  command: gh run list --workflow claude-code-review.yml --json databaseId --limit 1 && echo "artifact check via gh run view"
  expected_output: a run id; artifact enumerable without SSH
```

## Domain Review

**Domains relevant:** Engineering, Operations, Finance, Product, Legal (carried forward from brainstorm `## Domain Assessments`)

### Engineering (CTO)
**Status:** reviewed (carry-forward)
**Assessment:** Only CI claude-code-action is real spend. Reuse execution_file → total_cost_usd; land in a committed sidecar via a monthly aggregate, not per-run commits. Verify the jq shape against a real artifact.

### Operations (COO)
**Status:** reviewed (carry-forward)
**Assessment:** Never per-run rows in expenses.md — one monthly rollup line, ux-audit-style, ops-advisor-owned, pulled not eyeballed. Reconciliation lifecycle prevents an orphan ledger.

### Finance (CFO)
**Status:** reviewed (carry-forward)
**Assessment:** Loops move burn by $0 (already in the R&D Max-seat line). CI spend is R&D, not COGS. Add a Max-20x ceiling spillover trigger. One reconciled monthly figure, no second ledger.

### Legal (CLO)
**Status:** reviewed (carry-forward)
**Assessment:** No material obligation (operator self-use, single tenant). Two prudence flags — secret hygiene (codified as the extract allowlist + test) and provenance labeling (recorded-actual vs estimate, codified in the JSONL `provenance` field + the seeded `accruing` status).

### Product/UX Gate
**Tier:** none
**Decision:** N/A — Files to Create/Edit contain no UI-surface paths (workflows, scripts, JSONL, markdown ledgers/runbooks/ADR). No `.tsx`/`page.tsx`/component files. `.pen` not required (consistent with brainstorm Phase 3.55 skip).
**Pencil available:** N/A (no UI surface)

## GDPR / Compliance Gate

`gdpr-gate` trigger **(b)** fired mechanically (brand-survival = single-user incident). Considered,
not skipped silently. Assessment: **no regulated-data surface** — the canonical regex (schemas,
migrations, auth, API routes, `.sql`) matches nothing here, and the captured data is the operator's
own non-personal cost metadata (token counts + dollars + run ids), not PII or third-party data
subjects. The CLO brainstorm assessment reached the same conclusion. The one genuine data-handling
risk — committing an API key / org id / raw message log — is a **secret-hygiene** concern, codified
as the extract-allowlist redaction boundary (Phase 1) + its test (AC1, AC2), not a GDPR obligation.
No `compliance/critical` finding; no `compliance-posture.md` write. A full `/soleur:gdpr-gate` skill
run would only re-affirm this — documented decision in lieu, proportionate to a non-regulated surface.

## Infrastructure (IaC)

**None.** No new server, secret, vendor, DNS, cron, or persistent runtime process. `ANTHROPIC_API_KEY`
already exists; artifact upload uses existing GitHub Actions primitives. The scheduled aggregation
job (which *would* be a new runtime surface) is deferred to **#5173** and will carry its own IaC
treatment there. Phase 2.8 gate skips.

## Risks & Sharp Edges

- **`execution_file` shape is verified** (JSON array; final `{"type":"result","total_cost_usd":…}`;
  jq `map(select(.type=="result"))[-1].total_cost_usd`). Phase 0 only re-confirms against one real run
  to catch action-upgrade drift — it is no longer a discovery step.
- **Value-injection beats key-projection alone.** A leak can ride inside an allowlisted *value*, not
  just an excluded key — hence AC3's injection case + numeric type-coercion in the extract. Key-shape
  assertion (AC1) is necessary but not sufficient.
- **Never upload the raw `execution_file`** — it carries prompts, diffs, and runs under an API key.
  Only the allowlisted record. This is the single-user-incident leak vector; AC5 guards it.
- **Extract step must be non-fatal** — a parse failure must `::warning::` and skip upload, never fail
  the gating review job (`continue-on-error` or guarded shell), else cost-capture flakiness blocks PRs.
- **Orphan test suite:** `test-all.sh` runs top-level `scripts/*.test.sh` only via explicit `run_suite`
  — add the line or the test is invisible to the exit gate.
- **Synthetic fixtures only**, with `<<…>>` placeholder tokens — GitHub push protection rejects
  literal `sk-ant-…`/`ghp_…` shapes even in fixtures (per the plan-prose push-protection sharp edge).
- **Empty `## User-Brand Impact` would fail deepen-plan Phase 4.6** — it is filled above.
- **Provenance honesty:** the seeded expenses line is `accruing`/estimate until the first real
  reconciliation; do not present $0 as a measured actual.

## Test Scenarios
1. `extract-api-spend.sh` on the happy-path fixture → exactly the 9 allowlist keys.
2. Fixture with embedded fake key/org_id → output contains neither.
3. Malformed/empty `execution_file` → empty output, exit≠0, no artifact uploaded.
4. `test-all.sh` includes and passes the new suite.
5. Workflow lint (`actionlint`) passes on both edited workflows; embedded `run:` shell parses via `bash -c`.

## Non-Goals (deferred to #5173 unless noted)
- Scheduled/automated monthly reconciliation (this PR ships the agent-run runbook bridge).
- Baseline-deviation alerting.
- #5085 digest surfacing of the reassurance line (sequence after #5085; do not block it).
- Per-loop token/cost display for local subscription loops (out of the ledger entirely).
- Anthropic Console/usage-API pull (execution_file is the source; Console is a later fallback).
