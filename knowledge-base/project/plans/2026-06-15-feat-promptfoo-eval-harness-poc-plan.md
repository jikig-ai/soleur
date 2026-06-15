---
title: "feat: promptfoo eval harness POC (PR B) — soleur:go routing + ticket-triage P-level"
date: 2026-06-15
branch: feat-one-shot-promptfoo-eval-harness
type: feature
semver: minor
lane: cross-domain
status: draft
closes: []
brand_survival_threshold: none
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# feat: promptfoo eval harness (PR B) — empirical prompt/agent regression checking

🧪 Proof-of-concept eval harness adapting the ponytail (github.com/DietrichGebert/ponytail, MIT)
benchmark methodology to Soleur, against ONE high-traffic surface. This is **PR B** of a
two-PR engineering-quality effort; **PR A** (the YAGNI minimalism-ladder principle) shipped
separately as `feat-yagni-ladder-and-soleur-debt-markers` (commit `d2c9a5c1c`) and explicitly
deferred this harness ("promptfoo eval harness — explicitly a SEPARATE later PR (PR B). Not
built here." — `knowledge-base/project/plans/2026-06-15-feat-yagni-ladder-and-soleur-debt-markers-plan.md:351`).

## Enhancement Summary

**Deepened on:** 2026-06-15
**Research agents used:** promptfoo-API-verifier (live docs), implementation-realism grep pass, learnings-researcher, repo/conventions research.

### Key Improvements (corrections folded in)
1. **Provider id corrected** to `anthropic:messages:<id>` (the bare `anthropic:<id>` form is wrong).
2. **"Median reported" corrected** — promptfoo has no native median; computed in the assert + post-processing.
3. **No-spend validation corrected** to `promptfoo validate config` (bare `validate`/`validate target` are wrong/spend).
4. Custom-assert signature, two-arm `prompts:` mechanism, and `tests: file://...jsonl` loading all verified against live docs.
5. All 7 codebase claims (budget, autonomous-loop list, model-ID registry, 7-route enum, docs count, test glob, audit-models exclude) verified verbatim at file:line.

### Gates passed
User-Brand Impact (`none`, justified), Observability (justified skip), IaC (justified skip), PAT-shaped-var (none), UI-wireframe (no UI surface). All deepen-plan hard halts cleared.

## Overview

Soleur has **90 skills** (measured) and 60+ agents but **zero empirical validation** that a
prompt/agent edit improves behavior. Research confirmed the gap: no `promptfooconfig.yaml`, no
`promptfoo` dependency, no golden-task or prompt-output-assertion tests exist anywhere. The
existing `*-eval` artifacts (`apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts`,
`oneshot-gdpr-gate-50d-eval.ts`) are **sandbox/spawn infrastructure and code-behavior unit
tests** — they evaluate substrate health and orchestration, never prompt-output quality. The
harness this plan builds is genuinely net-new.

We adapt the four ponytail patterns:
1. **promptfoo-driven harness** (`promptfooconfig.yaml`): arms × models × tasks, N runs (`repeat:`/`--repeat`).
   **Correction (researched):** promptfoo has **no native median** statistic — `repeat:` yields N runs and
   per-cell (prompt×provider) aggregate pass rates. The median/aggregate routing-correct rate is computed
   **in the measurement assert + a small post-processing step** (or read off promptfoo's aggregate score per
   cell), NOT from a built-in median feature.
2. **MEASUREMENT assert** that ALWAYS passes and records a number (ponytail: LOC via `loc.js`).
   For Soleur the recorded number is **classification-correct rate** (1.0 if the model's emitted
   label matches the golden label, else 0.0 — recorded, never gating). ONE generic assert serves
   both targets: implemented as a promptfoo custom `javascript` assert
   (`module.exports = (output, context) => ({ pass: true, score, reason })`); the golden label
   arrives via `context.vars.golden_label` (the route for `/go`, the P-level for triage).
3. **GATE assert** that FAILS on wrong output (ponytail: `correctness.js` executes generated code).
   For Soleur the deterministic gate is **"the emitted label is a member of the target's closed
   enum"** (the 7-route enum for `/go`, the 3-class `P1`/`P2`/`P3` enum for triage). A malformed /
   hallucinated label fails the contract regardless of correctness. ONE generic gate assert reads
   the allowed set from `context.vars.enum` (sourced per-target from `enums/<target>.json`).
4. **BASELINE/CONTROL arm**: run the same tasks WITHOUT the classifier prose (routing table / triage
   rubric) so the delta proves the skill *produces* the behavior — "that delta is the point."

**v1 is deliberately minimal and additive.** It adds one skill, **two** promptfoo configs (one per
target, sharing the same generic assert scripts + model source), two **classification-generic**
assert scripts, 2–3 golden tasks **per target**, and a README. It wires nothing into per-PR CI
(cost). Adding a third target later is cheap and now *demonstrated*: a new `promptfooconfig.<target>.yaml`
+ `tasks/<target>.jsonl` + `enums/<target>.json` + two arm-prompt files, reusing the generic
measure/gate asserts and `models.generated.json` unchanged.

### Targets — chosen and justified: `soleur:go` routing (primary) + ticket-triage P-level (second)

The prompt asked the plan to pick from three candidates by traffic/risk; the operator approved
shipping **two** targets in v1 to prove the "adding a target is cheap" claim immediately. **Picks:
`soleur:go` routing accuracy (primary) and ticket-triage P-level assignment (second).** The third
candidate (code-simplicity-reviewer diff-shrink) remains deferred — it has no enum assert and needs
an apply-then-measure pipeline. Justification (researched):

| Candidate | Output machine-checkability | Baseline-arm cleanliness | Traffic / risk | Verdict |
|-----------|----------------------------|--------------------------|----------------|---------|
| **`soleur:go` routing** (primary) | High — closed **7-route enum** (`fix`/`drain`/`clo-attestation`/`review`/`legal-threshold`/`incident`/`default`), routing table at `plugins/soleur/commands/go.md:47-55`. Constrain output to a single route token → exact-match assert. | **Cleanest A/B**: the skill text *is* the routing table; control = same prompt, no table. | **Highest** — THE unified entry point; every Soleur session enters here. Routing regression has the largest blast radius. | **CHOSEN** |
| **ticket-triage P-level** (second) | High — closed **3-class enum** (`P1`/`P2`/`P3`), priority rubric in `plugins/soleur/agents/support/ticket-triage.md`. Constrain output to a single P-level token → exact-match assert. | Clean A/B: the agent's priority rubric *is* the classifier; control = same issue body, no rubric. | Medium — GitHub-issue intake + daily triage cron (`scheduled-daily-triage.yml`), not every session. | **CHOSEN** — proves cheap-to-add; reuses the generic asserts verbatim. |
| code-simplicity-reviewer diff-shrink | **Lowest** — free-form prose; "diff-shrink" is a self-*estimate*, not an applied measurable delta. Needs an apply-then-measure pipeline. | Noisy — requires LLM-judge or apply+remeasure. | Medium — per-PR review. | **Deferred** — not an enum assert. |

`soleur:go` wins on traffic+risk decisively (it is the surface whose WHY motivates the whole effort —
routing is the front door); ticket-triage is the cheapest second target and its 3-class enum is
checked by the *same* generic assert scripts, so it directly demonstrates the additive design. Both
are cleanly machine-checkable once output is format-constrained to a single token. **Operator
approved both targets.**

> **Scope note on the source surfaces.** `/go`'s routing lives in a **command** (`plugins/soleur/commands/go.md`),
> not in `skills/go/SKILL.md`; ticket-triage's priority rubric lives in the **agent**
> (`plugins/soleur/agents/support/ticket-triage.md`). The harness does NOT modify either; it reads
> each surface's classifier prose as the "skill arm" system prompt and a table/rubric-less prompt as
> the "baseline arm." This keeps the harness purely additive and read-only against the production surfaces.

## Research Reconciliation — Spec vs. Codebase

| Claim (from feature description) | Reality (researched) | Plan response |
|---|---|---|
| skill-description word budget "currently 2222, near cap" | **Exact: 2222/2222, ZERO headroom** (`plugins/soleur/test/components.test.ts:15`; measured cumulative = 2222 across 90 skills). | Plan MUST bump `SKILL_DESCRIPTION_WORD_BUDGET` by the new skill's EXACT description word count and append a matching bump comment. New description budgeted ≤ ~30 words. |
| "Use current Claude model IDs … sourced from ONE place" | Model IDs are single-sourced as TS `as const`: `apps/web-platform/server/inngest/leader-prompts/constants.ts` (`SONNET_MODEL`, `HAIKU_MODEL`) + `apps/web-platform/server/inngest/model-tiers.ts` (`EXECUTION_MODEL`, `AUDIT_MODEL = "claude-opus-4-8"`). **promptfoo YAML cannot `import` TS.** | Harness sources model IDs via a single **generated** `models.generated.json` produced by a script that reads the TS SSOT; `promptfooconfig.yaml` references the generated file. No model literal is hardcoded in any config-class file. (See Sharp Edges — model-launch-review auto-fix exclusion.) |
| "cross-check against model-launch-review expectations" | `model-launch-review/scripts/audit-models.sh` auto-fixes stale Opus IDs to `claude-opus-4-8` and **EXCLUDES** `*/test/*`, `*.test.*`, `knowledge-base/project/**`, and its own dir from auto-fix. It names `leader-prompts/constants.ts` as the SSOT and says the grep target collapses to the registry once `model-tiers.ts` lands (it has). | The harness generator reads from the registry → zero literals to go stale. Any *documentation* literal in the README is in `knowledge-base`/skill-doc (excluded from auto-fix) AND will match the registry, so no drift. Cross-check holds. |
| `hr-autonomous-loop-skill-api-budget-disclosure` (DISCLOSE per-run API cost) | HARD RULE. `components.test.ts:243-274` asserts every skill in `AUTONOMOUS_LOOP_SKILLS` carries a `<decision_gate>` block containing sentinel `"disclaims warranty for runtime cost"`. | New skill is added to `AUTONOMOUS_LOOP_SKILLS` AND carries a `<decision_gate>` with the verbatim sentinel + a per-run cost model. This IS the decision-gate-style cost disclosure the prompt requested. |
| "do NOT wire into per-PR CI — explicit opt-in/manual run only" | No CI step would run the harness; promptfoo is not a dependency. | Harness invoked via `npx promptfoo eval` (no package.json dependency added). README documents the manual reproduce command. The skill's own scripts/tests (bash + the components test) ARE CI-gated; the harness *run* is not. |
| "PR A was deferred; PR B is this" | PR A = `feat-yagni-ladder-and-soleur-debt-markers` merged at `d2c9a5c1c`; its plan line 351 explicitly defers this. No GitHub deferral tracking issue exists for PR B (deferral was recorded only in plan prose). | Plan files a deferral-tracking issue for the **future targets** (the items v1 scopes out) per the deferral-tracking gate. |
| no prompt-level eval exists | Confirmed (grep returned zero promptfoo refs, zero golden/assertion tests). | Net-new build. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing — the harness is an
internal, opt-in developer tool. A broken harness produces a wrong benchmark number or fails to
run; it never touches a Soleur user's session, data, or workflow. Worst realistic case: an
operator running `npx promptfoo eval` is surprised by Anthropic API cost (mitigated by the
mandatory `<decision_gate>` disclosure).

**If this leaks, the user's data is exposed via:** not applicable — golden tasks are
synthesized fixtures (synthetic issue bodies / routing prompts), no real user data, no secrets.
The harness reads only the public `/go` routing table prose.

**Brand-survival threshold:** `none` — internal tooling, synthesized fixtures, no user-facing
surface, no regulated-data surface. (Diff touches no sensitive path per the preflight Check 6
canonical regex; no scope-out bullet required.)

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — skill exists & compliant.** `plugins/soleur/skills/eval-harness/SKILL.md` exists with
  valid frontmatter: `name: eval-harness` (matches dir, kebab-case), `description:` starts with
  `"This skill"`, third person, ≤1024 chars. `bun test plugins/soleur/test/components.test.ts` is green.
- [x] **AC2 — word budget bumped by exact count.** `SKILL_DESCRIPTION_WORD_BUDGET` in
  `components.test.ts:15` is bumped from `2222` by EXACTLY the new description's word count, with a
  bump comment appended in the existing style (`bumped +N for <issue> (eval-harness skill description,
  N words, against a 2222/2222 zero-headroom baseline)`). Verify: re-run the Node cumulative
  one-liner; `total == new budget` exactly (zero residual headroom is acceptable, negative is not).
- [x] **AC3 — cost disclosure gate.** `eval-harness` is added to the `AUTONOMOUS_LOOP_SKILLS` array in
  `components.test.ts:243`, AND `SKILL.md` contains a `<decision_gate>` block containing the verbatim
  sentinel `disclaims warranty for runtime cost` and a per-run cost model (arms × models × tasks × N).
  The new `components.test.ts` row for `eval-harness` passes.
- [x] **AC4 — promptfoo configs present & valid (one per target).**
  `plugins/soleur/skills/eval-harness/promptfooconfig.go-routing.yaml` AND
  `plugins/soleur/skills/eval-harness/promptfooconfig.ticket-triage.yaml` each exist and declare:
  providers as `anthropic:messages:<id>` (the 3 current IDs from `models.generated.json` — note the
  **`anthropic:messages:`** prefix, NOT bare `anthropic:`), two arms as two `prompts:` entries (a
  `skill` prompt embedding the target's classifier prose + a `baseline` prompt without it), the
  target's `tests: file://tasks/<target>.jsonl`, `repeat: 3` for N runs, and the two generic asserts
  (measurement + gate) with the target's `enum` wired via `defaultTest.vars.enum: file://enums/<target>.json`.
  `npx promptfoo@latest validate config -c <each file>` (the no-spend subcommand — NOT bare `validate`,
  NOT `validate target` which spends) exits 0 for BOTH configs. Keeping one config per target keeps the
  prompt×test cartesian clean (go tasks never run against the triage arms and vice-versa) and IS the
  additive recipe.
- [x] **AC5 — measurement assert (generic, both targets).** `scripts/measure-classification.js` (or
  `.cjs`) implements a promptfoo custom assert that parses the emitted label token, compares to
  `context.vars.golden_label`, returns `{ pass: true, score: <1.0|0.0> }` ALWAYS (never fails). It is
  classifier-agnostic (works for routes and P-levels). Unit-tested deterministically (no LLM) via
  `test/measure-classification.test.sh` with stubbed provider outputs for BOTH a route and a P-level.
- [x] **AC6 — gate assert (generic, both targets).** `scripts/gate-classification.js` implements the
  GATE assert: `pass: false` iff the emitted label is NOT a member of the target's closed enum
  (`context.vars.enum`). Enum sourced from a single per-target file (`enums/go-routes.json` = 7 routes;
  `enums/triage-levels.json` = `P1`/`P2`/`P3`) — never duplicated, never hardcoded in the assert.
  Unit-tested via `test/gate-classification.test.sh` with in-enum (pass) and out-of-enum (fail) stubbed
  outputs for BOTH enums.
- [x] **AC7 — model IDs single-sourced, no literals.** `scripts/gen-models.<sh|js>` reads the three
  current model IDs from `apps/web-platform/server/inngest/{model-tiers,leader-prompts/constants}.ts`
  and writes `models.generated.json`. `grep -REn 'claude-(opus|sonnet|haiku)-[0-9]' plugins/soleur/skills/eval-harness/`
  returns ONLY matches inside `models.generated.json` (a generated artifact) and the README doc — zero
  hardcoded literals in either `promptfooconfig.*.yaml` or the assert scripts.
- [x] **AC8 — golden tasks (per target).** `tasks/go-routing.jsonl` contains 2–3 synthesized golden
  tasks: each = `{ input: <user message>, golden_label: <one of the 7 routes> }`, covering at minimum
  one `fix`, one `default`, and one non-default-non-fix route (e.g. `incident` or `review`).
  `tasks/ticket-triage.jsonl` contains 2–3 synthesized golden tasks: each =
  `{ input: <synthetic GitHub issue body>, golden_label: <P1|P2|P3> }`, covering at minimum one of
  each P-level. No real user data; fixtures synthesized only (`cq-test-fixtures-synthesized-only`).
- [x] **AC9 — README with reproduce command + delta interpretation.** `README.md` in the skill dir gives:
  (a) the reproduce command for EACH target (`npx promptfoo eval -c promptfooconfig.go-routing.yaml`
  and `... -c promptfooconfig.ticket-triage.yaml`), (b) the per-run cost estimate (per target and
  combined), (c) how to read the **baseline-vs-skill delta** ("skill-arm classification-correct rate
  minus baseline-arm rate; a positive delta is the evidence the classifier prose produces the
  behavior"), (d) how to add a future target (the additive recipe — and a note that ticket-triage was
  added in v1 specifically to prove it).
- [x] **AC10 — bash test/lint clean.** All `plugins/soleur/skills/eval-harness/test/*.test.sh` pass via
  `bash scripts/test-all.sh scripts`. Scripts use `set -euo pipefail`. (No shellcheck CI step exists in
  this repo — tests are the `.test.sh` companion convention; run shellcheck locally as a courtesy and
  note the result, but the gating signal is `.test.sh`.)
- [x] **AC11 — docs registration.** `eval-harness` added to `SKILL_CATEGORIES` in
  `plugins/soleur/docs/_data/skills.js` (category: `"Review & Planning"`), the header `Last verified`
  count bumped from 86→87 (and the relevant per-category count), `scripts/sync-readme-counts.sh` run and
  committed. Post-condition: `./node_modules/.bin/eleventy` build from repo root, then
  `grep -c 'Uncategorized' _site/skills/index.html` returns `0`.
- [ ] **AC12 — CHANGELOG.** PR body includes a `## Changelog` section (semver:minor — adds a component).
  `plugin.json` version stays `0.0.0-dev` (do NOT edit).

### Post-merge (operator)

- [ ] **AC13 — first real run is operator-gated.** The harness `npx promptfoo eval` run is NOT executed
  in CI and NOT required for merge. An operator may run it manually post-merge to record the first
  baseline-vs-skill delta. `Automation: not feasible without spending operator Anthropic budget` — by
  design (cost), this is opt-in. Recording the first delta in the README/a results file is optional.

## Implementation Phases

> Phase order is load-bearing: the model-ID generator (Phase 1) must exist before the config that
> references its output (Phase 2); asserts + golden tasks (Phase 3) before the config wires them.

### Phase 0 — Preconditions (verify at /work start)
- Re-measure word-budget headroom (`node` one-liner) — confirm still `2222/2222` (or adjust bump if a
  sibling PR changed it).
- Confirm the three model IDs still resolve in `model-tiers.ts` + `constants.ts`:
  `claude-sonnet-4-6` (EXECUTION/SONNET), `claude-opus-4-8` (AUDIT), `claude-haiku-4-5-20251001` (HAIKU).
- `npx promptfoo --version` (proves the npx-only invocation works on Node 22; no dependency added).

### Phase 1 — Model-ID generator (single source)
- `scripts/gen-models.sh` (or `.js`): extracts the 3 IDs from the TS registry files (grep the
  `as const` exports — do NOT re-type the literals) and emits `models.generated.json` as
  `[{id, label}]`. Bash test asserts the 3 IDs match the registry verbatim (`test/gen-models.test.sh`).

### Phase 2 — promptfoo configs (one per target: arms × models × tasks)
- **One config file per target** (`promptfooconfig.go-routing.yaml`, `promptfooconfig.ticket-triage.yaml`)
  — keeps each prompt×test cartesian clean and IS the additive recipe. Both share the generic asserts +
  `models.generated.json`.
- Providers: `anthropic:messages:<id>` for each of the 3 IDs from `models.generated.json` (the
  `anthropic:messages:` prefix is required; reads `ANTHROPIC_API_KEY` from env). Generate the provider
  list from the JSON so no literal is hardcoded in either YAML.
- Two arms per config as **two `prompts:` entries** (the canonical promptfoo mechanism — each becomes a
  grid column): a `skill` prompt file (embeds the target's classifier prose — `/go` routing table, or
  the triage priority rubric) and a `baseline` prompt file (no table/rubric).
- `repeat: 3` for N runs per cell. promptfoo reports aggregate pass rate per (prompt×provider) cell; the
  classification-correct **median/rate** is computed by the measurement assert + post-processing (no native median).
- `tests: file://tasks/<target>.jsonl`; each row is `{ vars: { input, golden_label }, assert: [...] }`
  wiring both generic asserts. `defaultTest.vars.enum: file://enums/<target>.json` supplies the gate's
  allowed set. The asserts read `context.vars.golden_label` and `context.vars.enum`.

### Phase 3 — generic assert scripts + per-target golden tasks + enum SSOTs + arm prompts
- `enums/go-routes.json` — the closed 7-route enum; `enums/triage-levels.json` — `["P1","P2","P3"]`
  (single source per target for the gate).
- `scripts/measure-classification.js` (measurement, always-pass, records score; classifier-agnostic).
- `scripts/gate-classification.js` (gate, fails on out-of-enum label; reads `context.vars.enum`).
- `prompts/go-skill.txt` + `prompts/go-baseline.txt`; `prompts/triage-skill.txt` + `prompts/triage-baseline.txt`
  (each arm's system-prompt template; the skill arm embeds the production classifier prose read from the
  source surface).
- `tasks/go-routing.jsonl` + `tasks/ticket-triage.jsonl` — 2–3 synthesized golden tasks each.
- `test/*.test.sh` for each generic assert (deterministic, stubbed outputs, no LLM; cover BOTH enums).

### Phase 4 — SKILL.md + decision_gate + README
- `SKILL.md`: frontmatter (≤30-word description), body explaining the harness, and the mandatory
  `<decision_gate>` cost-disclosure block (verbatim sentinel + per-run cost model + arms×models×tasks×N
  arithmetic, stated **per target** and for running both — 2 arms × 3 models × ~3 tasks × 3 repeats = ~54
  API calls per target).
- `README.md`: reproduce command, cost estimate, baseline-vs-skill delta interpretation, additive
  recipe for future targets.

### Phase 5 — registration + budgets
- Add to `AUTONOMOUS_LOOP_SKILLS` (`components.test.ts:243`).
- Bump `SKILL_DESCRIPTION_WORD_BUDGET` by exact word count + comment.
- Add to `SKILL_CATEGORIES` (`docs/_data/skills.js`) + bump header count.
- `bash scripts/sync-readme-counts.sh` + commit.

### Phase 6 — verify
- `bun test plugins/soleur/test/components.test.ts` green.
- `bash scripts/test-all.sh scripts` green (eval-harness `.test.sh` discovered + passing).
- `./node_modules/.bin/eleventy` from root; `grep -c 'Uncategorized' _site/skills/index.html == 0`.
- `npx promptfoo@latest validate config -c .../promptfooconfig.go-routing.yaml` AND
  `... -c .../promptfooconfig.ticket-triage.yaml` each exit 0 (no API spend).

## Files to Create
- `plugins/soleur/skills/eval-harness/SKILL.md`
- `plugins/soleur/skills/eval-harness/README.md`
- `plugins/soleur/skills/eval-harness/promptfooconfig.go-routing.yaml`
- `plugins/soleur/skills/eval-harness/promptfooconfig.ticket-triage.yaml`
- `plugins/soleur/skills/eval-harness/enums/go-routes.json` (closed 7-route enum SSOT)
- `plugins/soleur/skills/eval-harness/enums/triage-levels.json` (closed P1/P2/P3 enum SSOT)
- `plugins/soleur/skills/eval-harness/scripts/gen-models.sh`
- `plugins/soleur/skills/eval-harness/scripts/measure-classification.js` (generic, both targets)
- `plugins/soleur/skills/eval-harness/scripts/gate-classification.js` (generic, both targets)
- `plugins/soleur/skills/eval-harness/prompts/go-skill.txt` + `prompts/go-baseline.txt`
- `plugins/soleur/skills/eval-harness/prompts/triage-skill.txt` + `prompts/triage-baseline.txt`
- `plugins/soleur/skills/eval-harness/tasks/go-routing.jsonl`
- `plugins/soleur/skills/eval-harness/tasks/ticket-triage.jsonl`
- `plugins/soleur/skills/eval-harness/test/gen-models.test.sh`
- `plugins/soleur/skills/eval-harness/test/measure-classification.test.sh`
- `plugins/soleur/skills/eval-harness/test/gate-classification.test.sh`
- `models.generated.json` is generated (committed or gitignored — decide at /work; committing makes the
  configs self-contained and is the simpler choice for v1).

## Files to Edit
- `plugins/soleur/test/components.test.ts` — bump `SKILL_DESCRIPTION_WORD_BUDGET` (+exact count, +comment);
  add `"eval-harness"` to `AUTONOMOUS_LOOP_SKILLS`.
- `plugins/soleur/docs/_data/skills.js` — add `"eval-harness": "Review & Planning"`; bump header count 86→87.
- `plugins/soleur/README.md` + root `README.md` — via `scripts/sync-readme-counts.sh` (do not hand-edit).

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returned zero issues whose body references
`components.test.ts`, `skills.js`, `model-tiers`, or `promptfoo`.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal engineering/tooling change. No UI surface
(`## Files to Create`/`Files to Edit` contain no `components/**/*.tsx`, `app/**/page.tsx`, or
`app/**/layout.tsx`), so the mechanical UI-surface override does not fire; Product/UX Gate skipped.

## Observability

Skipped — this plan adds no code under `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, and introduces
no new runtime infrastructure surface (no server, service, cron, secret, or persistent process). The
harness is a manual developer tool (`npx promptfoo eval`) plus skill docs + bash test scripts; the only
runtime is the operator's own terminal, observable directly in promptfoo's stdout/web view. The skill's
own `.test.sh` and the components test ARE CI-gated (the test job is the observability surface for the
harness scripts). No `apps/*` code-class file is touched.

## Infrastructure (IaC)

Skipped — no new infrastructure. promptfoo runs locally via `npx` against the operator's existing
Anthropic key (no new vendor account, no secret to provision, no server/cron/DNS/cert). No remote-host
provisioning, no secret-store mutation, no dashboard configuration. The Anthropic key is already present
in the operator's Claude Code session; the harness consumes it the same way every other autonomous-loop
skill does (disclosed via the `<decision_gate>`). The `iac-routing-ack` marker is present only because
the model-launch-review prose below names a secret-store CLI verb as a risk-to-avoid; the plan introduces
no such step.

## Deferred / Out of Scope (file tracking issue)

v1 ships TWO enum-based targets (`soleur:go` routing + ticket-triage P-level). The following remain
deferred and require a GitHub tracking issue (deferral-tracking gate), with re-evaluation criteria
"after the POC proves the rig pays off (first baseline-vs-skill delta recorded)":
- **Target 3 — code-simplicity-reviewer diff-shrink** (needs apply-then-measure pipeline; not an enum assert).
- **CI integration** — wiring the harness into any workflow (cost; separate later decision per the prompt).
- **LLM-judge asserts** for prose-output surfaces (only enum/deterministic asserts in v1).

## Risks & Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text,
  or omits the threshold will fail `deepen-plan` Phase 4.6.** This section is filled with a `none`
  threshold and concrete artifact/exposure lines.
- **Model-ID literals must never be hardcoded in config-class files.** `model-launch-review`'s
  `audit-models.sh --fix` auto-rewrites stale Opus IDs repo-wide but EXCLUDES `*/test/*`, `*.test.*`,
  `knowledge-base/project/**`, and its own dir. A literal `claude-opus-4-8` in `promptfooconfig.yaml`
  (a config-class, non-excluded file) would be auto-swapped on the next model bump AND could drift
  from the registry. Mitigation: the generator (`gen-models.sh`) reads from the TS registry; the
  config references `models.generated.json`. The README's documentation literals live in skill-doc
  (effectively `knowledge-base`-class doc, excluded) AND match the registry, so no drift.
- **promptfoo is NOT a npm dependency** — invoked via `npx promptfoo`. Do not add it to any
  `package.json` (would bloat install for a manual-only tool). Verify `npx promptfoo --version` works on
  Node 22 at Phase 0. If a future PR CI-wires the harness, pinning becomes a separate decision.
- **`.test.sh` discovery glob.** `scripts/test-all.sh` discovers `plugins/soleur/skills/*/test/*.test.sh`
  (a `test/` subdir) — NOT `scripts/*.test.sh`. Put all bash tests under the skill's `test/` dir or they
  are silently never run.
- **Word budget is at zero headroom (2222/2222).** The bump MUST equal the new description's exact word
  count; an off-by-one leaves the suite red. Keep the description ≤30 words and count it precisely
  before bumping.
- **Skill loader does not recurse.** `scripts/`, `tasks/`, `test/`, `enums/`, `prompts/`, and the
  `promptfooconfig.*.yaml` files are invisible to the skill component loader (only `SKILL.md` is the
  component) — but they MUST be linked from `SKILL.md` body as markdown links `[file](./scripts/file.js)`,
  never bare backticks (`components.test.ts:226-236` rejects bare `` `scripts/...` `` refs).
- **Deterministic asserts only.** The measurement/gate asserts MUST be tested with stubbed provider
  outputs (no live LLM in the test path) — the LLM is non-deterministic; a green `.test.sh` must prove
  the assert logic, not model compliance.
- **Eleventy build must use pinned binary.** Use `./node_modules/.bin/eleventy` from repo root, NOT
  global `npx @11ty/eleventy` (resolves a drifted cached version without the project filters).

## Research Insights (deepen-plan)

**promptfoo API shapes — verified live against promptfoo.dev (2026), not memory:**
- **Custom assert signature** (https://www.promptfoo.dev/docs/configuration/expected-outputs/javascript/):
  `module.exports = (output, context) => { ... }`. `output` = LLM response (string, or parsed object if JSON);
  `context.vars.<name>` = per-row test vars; `context.test` = full row. Return accepts boolean, number, or a
  GradingResult `{ pass, score, reason, componentResults? }`. **Both** the always-pass measurement assert
  (`{pass:true, score}`) and the fail-on-bad gate (`{pass:false, score:0, reason}`) are expressible verbatim.
- **Anthropic provider** (https://www.promptfoo.dev/docs/providers/anthropic/): id is
  `anthropic:messages:claude-<model>` — the `messages:` segment is **required**. Reads `ANTHROPIC_API_KEY`.
- **Two arms**: canonical mechanism is multiple `prompts:` entries (each a `file://` template → one grid column).
- **N runs**: `repeat: N` (config) / `--repeat N` (CLI). **No native median** — promptfoo surfaces aggregate
  per-cell pass rates; compute the median/rate in the assert + post-processing.
- **External tests**: `tests: file://tasks/go-routing.jsonl` supported; each row `{ vars, assert }`.
- **No-spend validation**: `promptfoo validate config` (NOT bare `validate`; NOT `validate target`, which spends).
- **npx**: `npx promptfoo@latest eval -c <config>` and `npx promptfoo@latest --version` are documented run-without-install
  forms. Requires Node `^20.20.0` or `>=22.22.0` (worktree has v22.22.1 — OK).

**Codebase claims — all 7 verified verbatim (file:line):**
`SKILL_DESCRIPTION_WORD_BUDGET=2222` @ `components.test.ts:15` (zero headroom); `AUTONOMOUS_LOOP_SKILLS`
(6 members) @ `:243`, sentinel @ `:254`; `AUDIT_MODEL="claude-opus-4-8"` @ `model-tiers.ts:45`,
`SONNET_MODEL="claude-sonnet-4-6"` @ `constants.ts:23`, `HAIKU_MODEL="claude-haiku-4-5-20251001"` @ `:24`;
7-route enum @ `go.md:47-55`; `SKILL_CATEGORIES` + `(4 categories, 86 skills)` @ `skills.js:11`;
test glob `plugins/soleur/skills/*/test/*.test.sh` @ `test-all.sh:183`; `AUTOFIX_TO="claude-opus-4-8"` +
exclude regex @ `audit-models.sh:39,45`.

## Test Scenarios

1. `bun test plugins/soleur/test/components.test.ts` — budget, char limit, decision_gate, no-bare-ref all green.
2. `bash plugins/soleur/skills/eval-harness/test/gen-models.test.sh` — generated JSON matches the 3 registry IDs.
3. `bash .../test/gate-classification.test.sh` — in-enum label → pass, out-of-enum → fail, for BOTH the
   7-route enum and the P1/P2/P3 enum.
4. `bash .../test/measure-classification.test.sh` — correct label → score 1.0 + pass; wrong label →
   score 0.0 + pass (never fails); exercised for both a route and a P-level.
5. `npx promptfoo@latest validate config -c .../promptfooconfig.go-routing.yaml` AND
   `... -c .../promptfooconfig.ticket-triage.yaml` — each exits 0 (config-only, no API spend).
6. `./node_modules/.bin/eleventy` + `grep -c 'Uncategorized' _site/skills/index.html == 0`.
