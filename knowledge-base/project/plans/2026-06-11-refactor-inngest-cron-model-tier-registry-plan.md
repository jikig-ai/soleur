---
title: "refactor: Inngest cron model-tier registry + MODEL_PRICING parity"
issue: 5106
branch: feat-one-shot-inngest-model-tier-registry-5106
type: refactor
lane: single-domain
brand_survival_threshold: none
date: 2026-06-11
---

# refactor: Inngest cron model-tier registry + MODEL_PRICING parity (#5106) ♻️

## Overview

Centralize the ~18 inline Anthropic model-ID string literals scattered across
`apps/web-platform/server/inngest/functions/*.ts` into a single workload-class
registry module (`apps/web-platform/server/inngest/model-tiers.ts`), exporting
`EXECUTION_MODEL` (sonnet, for the execution-class crons) and `AUDIT_MODEL`
(opus-4-7, for the deep-audit crons). Refactor the `MODEL_PRICING` map keys in
`functions/agent-on-spawn-requested.ts` from hand-rolled literals to computed
properties referencing the registry constants, and add a parity/drift test.

**This is a pure SSOT extraction — no model assignment changes.** Every cron
keeps the model it has today (sonnet stays sonnet, opus-4-7 stays opus-4-7).
Per ADR-053, re-tiering a cron (e.g. sweeping the audit crons up to opus-4-8,
or any cron down to haiku) is a separate `clo-attestation-class` model-bump PR
and is explicitly **out of scope** here. The `cron-weekly-release-digest.ts`
file self-identifies as never-downgrade-shaped; this refactor preserves its
sonnet pin and carries its rationale comment forward.

This is the consolidation point ADR-053 line 38 defers to #5106 ("Inngest cron
constants (web platform) … registry consolidation deferred to #5106").

Governing precedents:
- **ADR-053** (`knowledge-base/engineering/architecture/decisions/ADR-053-per-call-model-tiering-for-workflow-subagent-spawns.md`) — pin-surface lifecycle; names #5106 as the consolidation point; defines the never-downgrade exemption list.
- **ADR-034** (`knowledge-base/engineering/architecture/decisions/ADR-034-action-class-registry-static-literals-and-enum-absence.md`) — the accepted registry shape: frozen `as const` + `Record<>` parity + `tsc` as the exhaustiveness enumerator.

## Research Reconciliation — Spec vs. Codebase

The issue body's "Corrected facts (verified 2026-06-10)" drifted between filing
and now. Re-greped 2026-06-11; the count moved because
`cron-weekly-release-digest.ts` (PR #5122, merged 2026-06-09) was added after
the issue. **Counts drift, lists don't** — the canonical inventory is the grep
output below, NOT the issue's "16 / 11 sonnet".

| Spec claim (issue #5106, 2026-06-10) | Reality (greped 2026-06-11) | Plan response |
|---|---|---|
| "16 cron/event files carry quoted model literals" | **17 files** carry code literals (+`cron-weekly-release-digest.ts`) | Use the live grep inventory below; AC has a directory-walk drift test, not a hardcoded count |
| "11 sonnet" | **12 sonnet code-selection literals** + 1 `MODEL_PRICING` sonnet key | Migrate all 12 selection sites + the pricing key |
| "5 opus-4-7" | **5 opus-4-7** (confirmed) | Unchanged |
| "`MODEL_PRICING` has only sonnet-4-6 + haiku dated keys" | Confirmed: `functions/agent-on-spawn-requested.ts:90,96` | Refactor both keys to computed properties |
| "`AnthropicModelId` is the 2-value union from leader-prompts/constants.ts:26" | Confirmed: `SONNET_MODEL \| HAIKU_MODEL` at `:23,24,26` | Parity test scoped to pricing-path-consumed values (see FR4) |
| "the :474 `?? fallback` is unreachable for opus today" | Confirmed: `agent-on-spawn-requested.ts:474` `MODEL_PRICING[leaderModule.model] ?? {zeros}`; `leaderModule.model` is `AnthropicModelId` (2-value) | AUDIT_MODEL/opus never flows through pricing → no opus pricing entry needed (FR4 option b) |
| "`leader-prompts/constants.ts` re-export must be covered" | `leader-prompts/index.ts:28-36` re-exports `SONNET_MODEL`, `HAIKU_MODEL`, `AnthropicModelId` | model-tiers.ts imports from constants.ts (no re-declaration); drift test asserts identity (FR3) |
| "Preserve `claude-haiku-4-5-20251001` dated form exactly" | Confirmed dated; `claude-sonnet-4-6`/`claude-opus-4-7` are alias==dated (no separate dated ID, per claude-api skill) | Preserve haiku dated literal byte-for-byte; document mixed convention inline (FR2) |
| "AUDIT_MODEL upgrade to opus-4-8 is separate model-bump-PR class" | Confirmed by claude-api skill: opus-4-8 exists ($5/$25) but bumping is a re-tier | **Out of scope.** Registry pins opus-4-7 exactly. |

**Model-ID verification (claude-api skill, cached 2026-06-04):** `claude-sonnet-4-6`
($3/$15), `claude-opus-4-7` ($5/$25), `claude-haiku-4-5` alias / `claude-haiku-4-5-20251001`
dated ($1/$5). All four IDs in scope are current/active. The `MODEL_PRICING`
sonnet ($3/$15/$0.30/$3.75) and haiku ($0.8/$4/$0.08/$1) values match the catalog.

**Stale aspirational reference (flag, out of scope):** `leader-prompts/index.ts:23`
and `constants.ts:11` reference a `constants-ssot.test.ts` drift-guard that does
**not** exist in the tree (`find` returns nothing). Not created here; the new
`model-tiers.test.ts` is the first mechanical guard over these constants.

### Canonical inventory (greped 2026-06-11)

**Sonnet `"claude-sonnet-4-6"` code-selection literals (12):**

| File | Line | Form |
|---|---|---|
| `functions/cron-bug-fixer.ts` | 148 | argv `"claude-sonnet-4-6"` |
| `functions/cron-campaign-calendar.ts` | 63 | argv |
| `functions/cron-community-monitor.ts` | 123 | argv |
| `functions/cron-compound-promote.ts` | 67 | `export const ANTHROPIC_MODEL = "claude-sonnet-4-6";` (consumed `:391`) |
| `functions/cron-content-generator.ts` | 78 | argv |
| `functions/cron-daily-triage.ts` | 141 | argv `"--model", "claude-sonnet-4-6"` |
| `functions/cron-follow-through-monitor.ts` | 238 | argv |
| `functions/cron-growth-execution.ts` | 94 | argv |
| `functions/cron-roadmap-review.ts` | 97 | argv |
| `functions/cron-seo-aeo-audit.ts` | 95 | argv |
| `functions/cron-weekly-release-digest.ts` | 45 | `const ANTHROPIC_MODEL = "claude-sonnet-4-6";` (consumed `:284`); never-downgrade comment `:40-44` |
| `functions/event-ship-merge.ts` | 51 | argv |

**Opus `"claude-opus-4-7"` code-selection literals (5):**

| File | Line |
|---|---|
| `functions/cron-agent-native-audit.ts` | 100 |
| `functions/cron-competitive-analysis.ts` | 103 |
| `functions/cron-growth-audit.ts` | 65 |
| `functions/cron-legal-audit.ts` | 104 |
| `functions/cron-ux-audit.ts` | 71 |

**Pricing-key literals in `functions/agent-on-spawn-requested.ts` (2):**
`:90` `"claude-sonnet-4-6"`, `:96` `"claude-haiku-4-5-20251001"`.

**Comment-line literals (NOT migrated — verbatim mirrors of GHA `claude_args`):**
e.g. `cron-roadmap-review.ts:91`, `cron-legal-audit.ts:25,98`,
`cron-agent-native-audit.ts:30,94`, `cron-competitive-analysis.ts:28,97`,
`cron-growth-audit.ts:56`, `cron-seo-aeo-audit.ts:22,89`,
`cron-growth-execution.ts:22,88`. These mirror the workflow YAML on purpose and
must stay verbatim → the drift test scans **code only**, excluding comment lines.

## User-Brand Impact

**If this lands broken, the user experiences:** a cron firing with the wrong
model (e.g. an audit cron silently running on sonnet instead of opus-4-7),
degrading the quality of an unattended weekly artifact (audit report, digest).
The most acute failure is a `MODEL_PRICING` key drifting out of byte-identity
with `SONNET_MODEL`/`HAIKU_MODEL`, which silently routes cost accounting through
the `?? {all-zeros}` fallback at `agent-on-spawn-requested.ts:474` — under-counting
spend with no error.

**If this leaks, the user's data / workflow / money is exposed via:** N/A — this
is an internal refactor of model-ID constants. No new data flow, no secret, no
external surface. Model IDs are public.

**Brand-survival threshold:** none — pure internal constant centralization; no
user-facing surface, no regulated data, no new infrastructure. (Cost-accounting
correctness is guarded by FR4's parity test; a wrong model assignment is a
quality regression on an unattended artifact, not a single-user incident.)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Registry module exists.** `apps/web-platform/server/inngest/model-tiers.ts` exists, imports `SONNET_MODEL`/`HAIKU_MODEL` from `./leader-prompts/constants` (no re-declared string literals), and exports `EXECUTION_MODEL` (= `SONNET_MODEL`) and `AUDIT_MODEL` (= `"claude-opus-4-7" as const`). Verify: `grep -nE "export const (EXECUTION_MODEL|AUDIT_MODEL)" apps/web-platform/server/inngest/model-tiers.ts` returns 2 lines; `grep -c '"claude-sonnet-4-6"' apps/web-platform/server/inngest/model-tiers.ts` returns 0 (sonnet comes via import, not literal).
- [ ] **AC2 — All 12 sonnet selection sites import the registry.** Each file in the sonnet inventory references `EXECUTION_MODEL` and no longer holds a `"claude-sonnet-4-6"` code literal. Verify the drift test (AC6) passes; spot-verify `grep -rn 'EXECUTION_MODEL' apps/web-platform/server/inngest/functions/ | wc -l` ≥ 12.
- [ ] **AC3 — All 5 opus selection sites import the registry.** Each opus cron references `AUDIT_MODEL` and no longer holds a `"claude-opus-4-7"` code literal (comment lines may retain it). Verify: `grep -rn 'AUDIT_MODEL' apps/web-platform/server/inngest/functions/ | wc -l` ≥ 5.
- [ ] **AC4 — MODEL_PRICING keys are computed properties.** `functions/agent-on-spawn-requested.ts` `MODEL_PRICING` uses `[SONNET_MODEL]:` and `[HAIKU_MODEL]:` (imported from `./leader-prompts/constants`) instead of literal string keys; the 8 numeric pricing values are byte-unchanged. Verify: `grep -nE '\[(SONNET_MODEL|HAIKU_MODEL)\]:' apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts` returns 2 lines; `grep -c '"claude-sonnet-4-6"\|"claude-haiku-4-5-20251001"' apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts` returns 0.
- [ ] **AC5 — haiku dated form preserved + mixed-convention documented.** The haiku key resolves to exactly `"claude-haiku-4-5-20251001"` (via `HAIKU_MODEL`), and `model-tiers.ts` carries an inline comment documenting the mixed alias (`claude-sonnet-4-6`, `claude-opus-4-7`) vs. dated (`claude-haiku-4-5-20251001`) convention so a future cleanup doesn't normalize it. Verify: `grep -c 'claude-haiku-4-5-20251001' apps/web-platform/server/inngest/leader-prompts/constants.ts` returns ≥ 1 (unchanged); comment present in model-tiers.ts.
- [ ] **AC6 — Drift/parity test passes and is the canonical enumerator.** `apps/web-platform/test/server/inngest/model-tiers.test.ts` exists and asserts: (a) **no-raw-literal**: a directory walk over `apps/web-platform/server/inngest/functions/*.ts` finds zero `"claude-sonnet-4-6"` / `"claude-opus-4-7"` string literals on **non-comment** code lines (the canonical-source mirrors in comments are excluded by stripping `//`-prefixed and block-comment lines before matching); (b) the walk asserts it found ≥ 17 cron/event files (sanity, so an empty walk can't pass vacuously); (c) **pricing parity**: every key of `MODEL_PRICING` is a member of `AnthropicModelId`, and every member of `AnthropicModelId` (`SONNET_MODEL`, `HAIKU_MODEL`) has a `MODEL_PRICING` entry; (d) **identity**: `EXECUTION_MODEL === SONNET_MODEL` and `AUDIT_MODEL === "claude-opus-4-7"`. Verify: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/model-tiers.test.ts` is green.
- [ ] **AC7 — `tsc` is clean.** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes (the canonical exhaustiveness enumerator — every `MODEL_PRICING`-key / union mismatch surfaces here, not via a hardcoded site count). NEVER `npm run -w apps/web-platform` (root `package.json` declares no `workspaces`).
- [ ] **AC8 — Full inngest suite green; no behavior change.** `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/` passes — existing tests (`cron-bug-fixer.test.ts`, `cron-weekly-release-digest.test.ts`, `cron-compound-promote.test.ts`, etc.) that assert on the literal model strings still pass because the resolved values are byte-identical.
- [ ] **AC9 — Function-registry count unchanged.** `cron-manifest`/`function-registry-count` invariants are untouched (this refactor edits only model-ID references, not served-function arrays). Verify: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/` includes any function-registry-count suite green.
- [ ] **AC10 — PR body uses `Closes #5106`.**

## Implementation Phases

### Phase 0 — Preconditions (verify, do not assume)
- Re-run the canonical greps above against current HEAD (counts drift between plan and /work).
- Confirm `./node_modules/.bin/vitest` and `./node_modules/.bin/tsc` resolve under `apps/web-platform/` (`cd apps/web-platform && ls node_modules/.bin/vitest node_modules/.bin/tsc`).
- Confirm `leader-prompts/index.ts:28-36` still re-exports `SONNET_MODEL`/`HAIKU_MODEL`/`AnthropicModelId` (the registry imports from `./leader-prompts/constants` directly per the cycle-avoidance note in `constants.ts:1-5`).

### Phase 1 — RED: write the drift/parity test first (cq-write-failing-tests-before)
- Author `apps/web-platform/test/server/inngest/model-tiers.test.ts` per AC6, following the existing inngest test idiom: top-of-file `vi.hoisted(() => { process.env.NEXT_PHASE = "phase-production-build"; })` BEFORE imports (the cron modules pull in the inngest client whose startup-key check must short-circuit — see `cron-roadmap-review.test.ts:19-30`).
- The no-raw-literal walk reads each `functions/*.ts` via `readFileSync`, strips comment lines (single-line `//…` and `/* … */` / `* …` block bodies) before matching `"claude-sonnet-4-6"` / `"claude-opus-4-7"`.
- Run RED: test fails (literals still inline, registry absent).

### Phase 2 — GREEN: create the registry + migrate consumers
- Create `apps/web-platform/server/inngest/model-tiers.ts`:
  - Import `SONNET_MODEL`, `HAIKU_MODEL` from `./leader-prompts/constants`.
  - `export const EXECUTION_MODEL = SONNET_MODEL;`
  - `export const AUDIT_MODEL = "claude-opus-4-7" as const;`
  - Inline comment block: workload-class rationale (EXECUTION=sonnet, AUDIT=opus-4-7), the no-re-tier/never-downgrade note (cite ADR-053 + `cron-weekly-release-digest.ts`), the mixed alias/dated convention note (AC5), and that opus pricing is intentionally absent from `MODEL_PRICING` because `leaderModule.model: AnthropicModelId` (2-value) never carries opus through the `:474` lookup (FR4 option b).
  - Optionally re-export `HAIKU_MODEL` for symmetry only if a consumer needs it — do NOT add an unused export (YAGNI; haiku is a pricing-only key, not a cron-selection tier).
- Migrate the 12 sonnet selection sites → import `EXECUTION_MODEL` from `@/server/inngest/model-tiers` (alias form, matching how `agent-on-spawn-requested.ts` imports leader-prompts; the module sits in `inngest/`, one level above `functions/`). Replace `"claude-sonnet-4-6"` argv literals with `EXECUTION_MODEL`; replace the two `ANTHROPIC_MODEL = "claude-sonnet-4-6"` consts with `ANTHROPIC_MODEL = EXECUTION_MODEL` (preserve the export on `cron-compound-promote.ts:67` and the never-downgrade comment on `cron-weekly-release-digest.ts:40-44`).
- Migrate the 5 opus selection sites → import `AUDIT_MODEL`, replace argv `"claude-opus-4-7"` literals. Leave doc-comment occurrences verbatim.

### Phase 3 — GREEN: refactor MODEL_PRICING keys
- In `functions/agent-on-spawn-requested.ts`, import `SONNET_MODEL`, `HAIKU_MODEL` from `./leader-prompts/constants` (or via the registry re-export) and change the two `MODEL_PRICING` keys to computed properties `[SONNET_MODEL]:` / `[HAIKU_MODEL]:`. The 8 numeric values stay byte-identical. The `Record<string, ModelPricing>` type is fine as-is; tightening to `Record<AnthropicModelId, ModelPricing>` is optional and only if it doesn't break the `[leaderModule.model] ?? {}` consumer at `:474` (it won't, since `leaderModule.model` is `AnthropicModelId`). Prefer leaving `Record<string, …>` to keep the diff minimal unless the parity test design needs the tighter type.

### Phase 4 — Verify
- GREEN the drift/parity test (AC6).
- `tsc --noEmit` (AC7) — fix any TS2322 the union/key change surfaces.
- Full inngest suite (AC8, AC9).

## Files to Edit
- `apps/web-platform/server/inngest/functions/cron-bug-fixer.ts`
- `apps/web-platform/server/inngest/functions/cron-campaign-calendar.ts`
- `apps/web-platform/server/inngest/functions/cron-community-monitor.ts`
- `apps/web-platform/server/inngest/functions/cron-compound-promote.ts`
- `apps/web-platform/server/inngest/functions/cron-content-generator.ts`
- `apps/web-platform/server/inngest/functions/cron-daily-triage.ts`
- `apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts`
- `apps/web-platform/server/inngest/functions/cron-growth-execution.ts`
- `apps/web-platform/server/inngest/functions/cron-roadmap-review.ts`
- `apps/web-platform/server/inngest/functions/cron-seo-aeo-audit.ts`
- `apps/web-platform/server/inngest/functions/cron-weekly-release-digest.ts`
- `apps/web-platform/server/inngest/functions/event-ship-merge.ts`
- `apps/web-platform/server/inngest/functions/cron-agent-native-audit.ts`
- `apps/web-platform/server/inngest/functions/cron-competitive-analysis.ts`
- `apps/web-platform/server/inngest/functions/cron-growth-audit.ts`
- `apps/web-platform/server/inngest/functions/cron-legal-audit.ts`
- `apps/web-platform/server/inngest/functions/cron-ux-audit.ts`
- `apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts`

## Files to Create
- `apps/web-platform/server/inngest/model-tiers.ts`
- `apps/web-platform/test/server/inngest/model-tiers.test.ts`

## Open Code-Review Overlap
None. Queried `gh issue list --label code-review --state open` (200) for `model-tiers` and `agent-on-spawn-requested` — zero matches.

## Functional Requirements

- **FR1 — Two workload-class constants.** `model-tiers.ts` exports exactly `EXECUTION_MODEL` (= imported `SONNET_MODEL`) and `AUDIT_MODEL` (= `"claude-opus-4-7" as const`). No re-declared model string literals for sonnet/haiku. Impl: `apps/web-platform/server/inngest/model-tiers.ts`. (AC1)
- **FR2 — Mixed alias/dated convention documented inline.** Impl: comment block in `model-tiers.ts` + preservation of `claude-haiku-4-5-20251001` in `constants.ts` unchanged. (AC5)
- **FR3 — Registry imports from constants.ts; no second SSOT.** `model-tiers.ts` imports `SONNET_MODEL`/`HAIKU_MODEL` from `./leader-prompts/constants`; the identity assertion in the test guards drift between the two modules. Impl: `model-tiers.ts` import line + `model-tiers.test.ts` identity assertion. (AC1, AC6d)
- **FR4 — Pricing parity scoped to consumed values (no opus pricing entry).** The parity test asserts `MODEL_PRICING` keys ⊆ `AnthropicModelId` and `AnthropicModelId` ⊆ `MODEL_PRICING` keys (both sonnet + haiku). It does NOT require an opus entry, because `leaderModule.model: AnthropicModelId` is the only thing that flows through `MODEL_PRICING[…]` at `agent-on-spawn-requested.ts:474`, and the union has no opus member. If a future PR makes opus reachable through that lookup, the parity test must be widened then (documented in the test comment). Impl: `model-tiers.test.ts` (c) + `agent-on-spawn-requested.ts` computed keys. (AC4, AC6c)
- **FR5 — Drift guard is a directory walk over code lines, not a hardcoded list.** Impl: `model-tiers.test.ts` no-raw-literal walk with comment-stripping + ≥17-file sanity assertion. (AC6a, AC6b)

## Test Scenarios

- **Runner:** vitest. Run via `cd apps/web-platform && ./node_modules/.bin/vitest run <path>` — NOT `npm run -w` (no root `workspaces`), NOT `bun test`.
- **Typecheck:** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- **Test file path:** `apps/web-platform/test/server/inngest/model-tiers.test.ts` — colocated with sibling inngest tests; vitest collects `test/**/*.test.ts` (confirm against `apps/web-platform/vitest.config.ts include:` at /work time before finalizing the path).
- **RED→GREEN:** drift test fails before registry exists / while literals remain inline; passes after migration.
- **Regression:** full `test/server/inngest/` suite (existing literal-asserting tests stay green because resolved values are byte-identical).
- **Negative (comment exclusion):** the no-raw-literal walk does NOT flag the verbatim `--model claude-sonnet-4-6` comment mirrors of GHA `claude_args` (it strips comment lines first) — assert this explicitly with a fixture line or by confirming the suite passes with those comments present.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change confined to
`apps/web-platform/server/inngest/`. No UI surface (no file under `components/**`,
`app/**/page.tsx`, `app/**/layout.tsx`), no marketing/legal/finance/product
implication. Pure constant centralization.

## Observability

This plan edits code-class files under `apps/web-platform/server/`, so the 5-field
schema applies — but the change introduces no new failure mode, error path, or
runtime process. It centralizes compile-time constants.

```yaml
liveness_signal:
  what: Existing per-cron Inngest run telemetry (unchanged) — each cron's success/failure already surfaces in the Inngest dashboard + Sentry.
  cadence: per cron schedule (unchanged)
  alert_target: existing per-cron alert routes (unchanged by this refactor)
  configured_in: apps/web-platform/server/inngest/* (existing)
error_reporting:
  destination: Sentry (existing reportSilentFallback/captureException paths in the edited crons are untouched)
  fail_loud: true (no new catch/fallback introduced)
failure_modes:
  - mode: MODEL_PRICING key drifts out of byte-identity with SONNET_MODEL/HAIKU_MODEL
    detection: model-tiers.test.ts pricing-parity assertion (AC6c) + tsc (AC7) at CI time
    alert_route: CI red on PR (pre-merge gate) — never reaches prod
  - mode: a cron's model literal not migrated to the registry (silent un-centralization)
    detection: model-tiers.test.ts no-raw-literal directory walk (AC6a)
    alert_route: CI red on PR
logs:
  where: existing Inngest run logs + Better Stack (unchanged)
  retention: existing (unchanged)
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/model-tiers.test.ts"
  expected_output: "all tests pass — registry centralized, pricing parity holds, no raw literals in cron code"
```

## Alternative Approaches Considered

| Approach | Why not chosen |
|---|---|
| Extend `leader-prompts/constants.ts` instead of a new module | `constants.ts` is scoped to the leader-loop SDK path (carries `LeaderPromptModule`/`LeaderActionClass`/prompt-version types). The cron subsystem is distinct (CLI-spawn argv). A standalone `model-tiers.ts` keeps concerns separated and is where ADR-053 points #5106. It still imports the sonnet/haiku strings from `constants.ts` to avoid a second SSOT. |
| Add an opus-4-7 `MODEL_PRICING` entry | `leaderModule.model` (`AnthropicModelId`, 2-value) is the only key that flows through the `:474` lookup; opus never reaches it. Adding an unused entry is YAGNI and would need a CFO-refreshed pricing comment for a value never consumed. Parity test is scoped to consumed values (FR4). Documented so a future PR that makes opus reachable widens the test then. |
| Bump AUDIT_MODEL to opus-4-8 while here | Out of scope per ADR-053 — re-tiering is a `clo-attestation-class` model-bump PR with action-pin sync (learning `2026-04-18-action-pin-sync-with-model-bump.md`). This PR is a pure SSOT extraction; preserves opus-4-7 exactly. |
| Hardcoded file-list drift guard | Issue inventory undercounted (16→17) the moment a new cron merged. Directory walk + ≥17 sanity assertion is the only form that survives the next cron addition ("counts drift, lists don't"). |
| Create the missing `constants-ssot.test.ts` | Out of scope — stale aspirational reference; flagged in Research Reconciliation. The new `model-tiers.test.ts` is the first mechanical guard over these constants. |

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.** This plan's threshold is `none` with a concrete artifact/exposure statement; do not blank it.
- **Comment-line literals are load-bearing mirrors, not drift.** Several crons carry `--model claude-sonnet-4-6` / `--model claude-opus-4-7` in doc comments that mirror `.github/workflows/scheduled-*.yml` `claude_args` verbatim. The drift test MUST strip comment lines before matching, or it false-positives on intentional mirrors. Conversely, do NOT migrate those comment occurrences to `${EXECUTION_MODEL}` — they document the external workflow contract and must stay verbatim.
- **MODEL_PRICING key byte-identity is the silent-failure surface.** The `[leaderModule.model] ?? {all-zeros}` fallback at `agent-on-spawn-requested.ts:474` means a key that drifts from `SONNET_MODEL`/`HAIKU_MODEL` does NOT throw — it silently bills at zero. Computed properties (`[SONNET_MODEL]:`) make divergence impossible by construction; the parity test (AC6c) is the compensating control. Never reintroduce a literal-string key.
- **Test runner / typecheck invocation.** `cd apps/web-platform && ./node_modules/.bin/{vitest run,tsc --noEmit}`. The repo-root `package.json` declares no `workspaces`, so `npm run -w apps/web-platform <script>` aborts with "No workspaces found". Test FILE PATH must satisfy `vitest.config.ts` `include:` globs — verify at /work time before finalizing `test/server/inngest/model-tiers.test.ts`.
- **`vi.hoisted` NEXT_PHASE shim is required.** Any test importing a cron module pulls in the inngest client whose startup-key check must be short-circuited via `vi.hoisted(() => { process.env.NEXT_PHASE = "phase-production-build"; })` placed BEFORE the imports (idiom from `cron-roadmap-review.test.ts:19-30`). Omitting it fails the import.
- **`tsc` is the canonical enumerator, not the plan's count.** If tightening `MODEL_PRICING` to `Record<AnthropicModelId, …>`, run `tsc --noEmit` and treat every TS2322 as a rail to fix — do not trust the "12 sonnet / 5 opus" counts as exhaustive (they were greped, but the compiler is authoritative for key/union parity).
- **Preserve `cron-compound-promote.ts:67` `export`.** That `ANTHROPIC_MODEL` is `export const` (consumed at `:391` and potentially imported elsewhere — grep before changing the export keyword). Change only the RHS literal to `EXECUTION_MODEL`, keep `export`.
