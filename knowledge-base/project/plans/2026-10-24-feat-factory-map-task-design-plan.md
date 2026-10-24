---
title: "feat: factory-map doc + required task-design answers for new autonomous tasks (#11014, #11015)"
type: feat
date: 2026-10-24
slug: feat-factory-map-task-design
branch: feat-one-shot-11014-11015-factory-map-task-design
issue: 11014
closes: [11014, 11015]
priority: p3-low
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

Spec lacks valid `lane:` (no spec.md — one-shot path); defaulted to `cross-domain` (TR2 fail-closed).

# feat: factory-map doc + required task-design answers for new autonomous tasks

## Overview

Two paired deliverables from the `mattpocock/skills` PR `#1316` (`software-factory`) audit
addendum — items SF1 (#11014) and SF2 (#11015), both recorded in
`knowledge-base/product/competitive-intelligence.md` §Addendum 2026-10-24 (ref #11000).

- **SF1 / #11014** — create `knowledge-base/engineering/architecture/factory-map.md`: one page
  naming Soleur's concrete filling for each agentic-factory service slot (ticket tracker, ticket
  source, git host, orchestrator, runner, observability platform) and mapping the peer vocabulary
  (Task / Trigger / Run / Runner) onto Soleur terms. Then add `glossary.md` pointer entries for
  run / trigger / runner / task resolving to the map.
- **SF2 / #11015** — make the six "question every task" answers required at design time for new
  autonomous tasks. Landing covers BOTH surfaces the issue names, because they guard disjoint
  creation paths: (a) `soleur:schedule` `create` collects the answers and stamps them into the
  generated workflow's `# Task design:` header comment; (b) plans that add a new autonomous-task
  surface must emit a conditional `## Task Design` section (Encryption-Posture precedent),
  enforced by a new deepen-plan halt. The Inngest runbook
  (`inngest-oneshot-and-reminder-patterns.md`) carries the same checklist for the
  server-side substrate that `schedule` Step 0 routes to.

## Problem Statement / Motivation

No single document names Soleur's factory slots; the map must be re-derived from ~296 ADRs and
scattered rules, and `glossary.md` defines none of the machinery words (run / trigger / runner /
task). Every answer to the six task-design questions exists *somewhere* (`concurrency: group:`,
idempotency prechecks, `action-required` re-entry, dedupe markers, observability gates) but none
is required at design time: a new autonomous task needs no declared answers to ship.

## Proposed Solution

1. Author `factory-map.md` as a two-table doc (slot → Soleur filling; peer term → Soleur term
   with honest divergences) plus `_Avoid_` synonym guidance adapted to local usage. Add four
   pointer-only `glossary.md` entries per the `glossary-format.md` contract. Record MIT
   attribution in `plugins/soleur/NOTICE` (vocabulary/methodology only — no prose port).
2. `schedule` `create`: recurring mode collects the five non-derived answers at Step 1 (trigger
   derives from the collected cron + `workflow_dispatch`); flag-driven invocations pass
   `--design-*` flags and missing answers in a non-interactive context are a hard error. The
   `--once` template stamps the same header with answers *derived* from the D1–D5 machinery —
   zero new flags.
3. Plan-side gate: new `## Task Design` conditional section (schema in
   `plan-issue-templates.md`, emit rule at plan §2.9.3, halt at deepen-plan §4.13, mirror in
   `deepen-plan.workflow.js`), firing only when the plan creates a NEW autonomous-task surface.
4. Inngest runbook: the six answers recorded in the design issue/plan for new oneshots and in
   the arming record for new registered reminder checks.
5. New content-assertion suite `plugins/soleur/test/schedule-task-design.test.sh` + its
   `AFFECTED_*_PATHS` edge in `scripts/lib/test-affected-paths.sh`.

## Technical Considerations

- **Schema parity.** `## Observability`'s 5-field schema is pinned by
  `observability-schema-parity.test.ts` across four surfaces. `## Task Design` is a *new
  conditional section*, not a 6th field — zero ripple into that parity surface.
- **Skill-body budget.** `schedule`/`plan`/`deepen-plan` SKILL.md bodies are budget-linted;
  keep additions tight (check `scripts/lint-skill-body-budget.py` output at work time).
- **Skill-description budget.** No `description:` frontmatter edits — the
  `SKILL_DESCRIPTION_WORD_BUDGET` check does not fire.
- **Once-template markers.** `<!-- once-template-begin/end -->` frame the extracted block; the
  header goes inside the yaml fence (comments are legal above `name:`).
- **No retroactive gate** (AC: applies to newly created tasks only). Detection is
  Files-to-**Create**-only; the 21 existing `scheduled-*.yml` are untouched.
- **Markdownlint.** Plan/tasks/`.md` edits lint under lefthook; markdown links not bare URLs.

## Research Insights

**Local research (in-process — this harness has no Task/Agent tool, so `repo-research-analyst`,
`learnings-researcher`, `functional-discovery`, domain leaders, spec-flow-analyzer and the
plan-review panel could not be spawned; equivalents were run inline and the residual is recorded
in `specs/<branch>/decision-challenges.md`).**

- `plugins/soleur/skills/schedule/SKILL.md` — Step 0 routing gate sends secret/server-side work
  to Inngest; Step 1 collects 6 recurring inputs via AskUserQuestion; Steps 3a/3b hold the two
  workflow templates (no header comment today). `--once` takes five mandatory flags.
- Seven observability layers: `plugins/soleur/agents/engineering/review/observability-coverage-reviewer.md`
  §The seven observability layers (cited by `hr-observability-layer-citation`, AGENTS.rules.md:59).
- `concurrency: group: schedule-<NAME>` is already in both generated templates — the
  *workflow-level* dedupe the sixth answer must distinguish from semantic double-work.
- Conditional-section precedent: `## Encryption Posture` (plan §2.11 / deepen-plan §4.10) is the
  shape `## Task Design` mirrors.
- Glossary contract: `plugins/soleur/skills/kb-glossary/references/glossary-format.md` — entries
  are pointers; a term needs a definer file first (factory-map IS the definer — order matters).
- NOTICE attribution precedent: `plugins/soleur/NOTICE` `mattpocock/skills` entry (MIT); it
  already references `knowledge-base/` paths in commentary.
- `plugins/soleur/test/*.test.sh` suites auto-register via `scripts/test-all.sh` globs; new
  suites need an `AFFECTED_<LABEL>_PATHS` edge in `scripts/lib/test-affected-paths.sh`.
- Upstream vocabulary verified verbatim via `gh api` on PR `#1316` branch
  `software-factory-skill` (Task/Trigger/Run/Runner + 5 service slots + six questions).
- Relevant learnings applied: verify named artifacts (all files above `ls`-verified); ACs must
  be checkable post-conditions; new suites need AFFECTED declarations; markdownlint before emit.

**Premise Validation (Phase 0.6).** #11014 and #11015 OPEN (p3/feature/engineering); #11000
merged; `glossary.md` lacks the four terms (full read); `architecture/` has no `factory-map.md`;
upstream PR `#1316` state OPEN and its SKILL.md fetched live; `concurrency: group:` confirmed in
both templates; `hr-observability-as-plan-quality-gate` confirmed at AGENTS.rules.md:57. No
stale premises.

**Property List (Phase 0.6b).** P1 one doc names all six slot fillings + peer→Soleur term map.
P2 glossary entries for run/trigger/runner/task pointing at the map. P3 a new
scheduled/autonomous task ships with written answers to all six questions. P4 the dedupe answer
distinguishes workflow-level concurrency from semantic double-work. P5 no gate retrofits onto
existing workflows.

**Cut List (Phase 0.6b).** (a) CI/lefthook lint enforcing the header on new `scheduled-*.yml` —
cut: the generator embeds the block and the plan gate covers plan-authored files; a
hand-authored file outside any plan is the same trust surface every skill-level rule already
relies on (revisit if a bypass is observed). (b) Extending `trigger-cron`/`cron-list`/`cron-delete` —
cut: not creation paths. (c) Requiring the six answers on every new *skill* — cut: "task" here
means a recurring autonomous unit; invoked skills are not autonomous tasks. (d) A `cron-list`
"has-design-header" column — cut: reporting nicety, buys no property in the list.

**Research decision (Phase 1.6):** no external-research spawn needed — the peer artifact was
fetched verbatim and all other surfaces are repo-local. (Discovery agents unavailable in this
harness anyway; noted.)

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality | Plan response |
|---|---|---|
| "`concurrency: group:` in every generated workflow" | Confirmed in Step 3a/3b templates | Header block names it as the workflow-level dedupe the semantic answer must exceed |
| "`glossary.md` defines none of run / trigger / runner / task" | Confirmed — full read, zero entries | Four new pointer entries |
| "the map must be re-derived from ~298 ADRs" | ~296 ADR files in `decisions/` | Doc's job is precisely this condensation |

## Implementation Phases

### Phase 1: factory-map + glossary + attribution (#11014)

- Write `knowledge-base/engineering/architecture/factory-map.md`: slot table (ticket tracker →
  GitHub Issues + label routing (`drain-labeled-backlog`, `action-required`, `scheduled-<NAME>`
  labels, standing-delegation markers); ticket source → Sentry monitors, `tmpfs-guard`,
  drift-detection and scheduled-* filings, operator-filed issues; git host → GitHub;
  orchestrator → GHA `schedule:`/`workflow_dispatch` + Inngest (cron functions, self-armed
  oneshots per ADR-046, reminder primitive); runner → GHA hosted runners / Devin cloud sessions /
  local worktrees / bwrap agent sandbox; observability platform → the seven enforced layers).
  Vocabulary map: Task → a defined-once run-many-times unit (skill / scheduled workflow /
  Inngest function); Trigger → cron / event / label / dispatch / upstream run; Run → a workflow
  run / Inngest execution / agent session, black-box trigger-to-finish, never waits on a human
  (`action-required` + `message_user` stall-as-defer); Runner → the disposable execution
  surface. Record where Soleur usage diverges from the peer `_Avoid_` list (e.g. Soleur
  "session" names an agent context, "sandbox" names the bwrap surface — not the runner).
  Attribution footer: vocabulary/methodology adapted from `mattpocock/skills` `software-factory`
  (MIT), no prose ported.
- `glossary.md`: four pointer entries (`Run`, `Trigger`, `Runner`, `Task`), each body naming
  `knowledge-base/engineering/architecture/factory-map.md` + §anchor; `_Avoid_` lines carried
  where a wrong sense produces a wrong commit (e.g. `Run` _Avoid_: "session" when meaning the
  black-box execution; `Runner` _Avoid_: "server/host/box" for the execution surface).
- `plugins/soleur/NOTICE`: extend the `mattpocock/skills` entry — `Used in` gains
  `knowledge-base/engineering/architecture/factory-map.md` and
  `plugins/soleur/skills/schedule/SKILL.md` (task-design checklist); `Portions adopted` gains
  "the factory-slot ontology vocabulary and the question-every-task checklist".

### Phase 2: schedule create flow stamps the six answers (#11015, surface a)

- Step 1 (recurring) gains items 7–10 collecting `services_read`/`services_write`,
  `triggers_next`, `human_reentry`, `dedupe_semantic` (answer MUST name something beyond
  `concurrency: group:` — e.g. idempotency precheck, marker dedupe, immutable ticket key),
  `source_dedupe` (required answer or explicit "not a ticket source"). Step 0b flag path gains
  `--design-services`, `--design-next`, `--design-reentry`, `--design-dedupe`,
  `--design-source-dedupe`; in a non-interactive context a missing design answer is a hard
  error, mirroring `--once`'s no-fallback posture.
- Step 3a template: prepend a `# Task design:` comment block above `name:` with all six
  answers (trigger derived: `cron '<CRON_EXPRESSION>' + workflow_dispatch`).
- Step 3b template: same block, answers derived from D1–D5 (trigger = one-time cron at
  `FIRE_DATE` + D3 date guard; re-entry = the pinned issue-comment thread; dedupe =
  D3 + D4 self-strip + `concurrency: group: schedule-once-<NAME>`; source = "not a ticket
  source" unless the spec files tickets).

### Phase 3: plan-time gate (#11015, surface b) + Inngest runbook

- `plugins/soleur/skills/plan/references/plan-issue-templates.md`: add the conditional
  `## Task Design` schema to all three templates (after `## Observability`), gated "required
  when the plan creates a new autonomous-task surface".
- `plugins/soleur/skills/plan/SKILL.md`: new `#### 2.9.3. Task-Design Gate (Conditional)` —
  detection = a `## Files to Create` path matching `\.github/workflows/scheduled-.*\.yml`,
  `apps/*/server/inngest/functions/(cron|oneshot)-.*\.ts`, or a new registered reminder/sweeper
  check; emit `## Task Design` with the six fields; reject on missing/placeholder answers and on
  a `dedupe` answer that names only workflow-level concurrency.
- `plugins/soleur/skills/deepen-plan/SKILL.md`: new `### 4.13. Task-Design Halt (Conditional)`,
  symmetric to §4.10 — same detection, halt on absent/incomplete section.
- `plugins/soleur/skills/deepen-plan/workflows/deepen-plan.workflow.js`: mirror the check in its
  gate enumeration (the `observability` bullet shape at ~line 242).
- `knowledge-base/engineering/operations/runbooks/inngest-oneshot-and-reminder-patterns.md`:
  new short section requiring the six answers in the design issue/plan for each NEW
  `oneshot-*`/`cron-*` function and in the arming record for each new registered check.

### Phase 4: test + registration

- New `plugins/soleur/test/schedule-task-design.test.sh` (test-helpers.sh conventions):
  asserts BOTH generated templates contain the `# Task design:` block and all six field keys,
  that SKILL.md Step 1 collects them and Step 0b documents the flags, and that no existing
  `.github/workflows/scheduled-*.yml` is retroactively gated (P5 — assert the skill's own text
  scopes the requirement to create-time).
- `scripts/lib/test-affected-paths.sh`: new
  `AFFECTED_PLUGINS_SOLEUR_TEST_SCHEDULE_TASK_DESIGN_TEST_SH_PATHS` covering the suite, the
  SKILL.md, both template surfaces, and the index file itself.

## Files to Create

- `knowledge-base/engineering/architecture/factory-map.md`
- `plugins/soleur/test/schedule-task-design.test.sh`
- `knowledge-base/project/specs/feat-one-shot-11014-11015-factory-map-task-design/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-11014-11015-factory-map-task-design/decision-challenges.md`

## Files to Edit

- `knowledge-base/project/glossary.md` — +4 pointer entries
- `plugins/soleur/NOTICE` — mattpocock/skills `Used in` + `Portions adopted`
- `plugins/soleur/skills/schedule/SKILL.md` — Steps 0b/1/3a/3b
- `plugins/soleur/skills/plan/SKILL.md` — new §2.9.3
- `plugins/soleur/skills/plan/references/plan-issue-templates.md` — `## Task Design` ×3
- `plugins/soleur/skills/deepen-plan/SKILL.md` — new §4.13
- `plugins/soleur/skills/deepen-plan/workflows/deepen-plan.workflow.js` — gate mirror
- `knowledge-base/engineering/operations/runbooks/inngest-oneshot-and-reminder-patterns.md`
- `scripts/lib/test-affected-paths.sh` — AFFECTED edge

## User-Brand Impact

- **If this lands broken, the user experiences:** an agent session that either skips the
  task-design contract entirely (silent regression to today) or halts `deepen-plan` on a false
  positive — internal tooling friction on the operator's own pipeline, not a shipped artifact.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure vector —
  the diff is docs + prompt-skill text + a test suite; it reads/writes no user data path.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** every touched path is internal engineering/docs; no
  customer-facing surface, no credential path, no data flow changes — `none`, not
  `single-user incident`.

## Observability

The diff's only executable artifact is a test suite — the observability IS the suite:

```yaml
liveness_signal:
  what:            # schedule-task-design.test.sh asserting both workflow templates carry the six-answer block
  cadence:         # per-PR via affected-test selection + full battery in CI
  alert_target:    # red required check on the PR (workflow run log — observability layer 6)
  configured_in:   # scripts/test-all.sh suite globs + scripts/lib/test-affected-paths.sh edge

error_reporting:
  destination:     # GHA workflow run log (FAIL: lines via test-helpers.sh print_results)
  fail_loud:       # non-zero suite exit -> red check

failure_modes:
  - mode:          # a generated template loses the task-design block (silent un-gating)
    detection:     # schedule-task-design.test.sh reds in CI (layer 6: workflow run log)
    alert_route:   # PR author via required-check failure
  - mode:          # plan/deepen-plan gate text drifts from the section schema
    detection:     # convention-only (skill text review); content assertions pin the write site
    alert_route:   # PR review

logs:
  where:           # GHA run log
  retention:       # GHA default

discoverability_test:
  command:         bash plugins/soleur/test/schedule-task-design.test.sh
  expected_output: "Failed: 0"
```

## Encryption Posture

Not applicable — no persistent data store and no new cross-component/network connection.

## Guard Contract

### Guard 1 — task-design requirement (plan §2.9.3 + deepen-plan §4.13 + schedule templates)

**Property.** Every NEW autonomous task is created only with written answers to all six
task-design questions — in the generated workflow's header, or in the creating plan's
`## Task Design` section — and the dedupe answer names a mechanism beyond workflow-level
concurrency.

**Assembly.** The detection predicate (a `## Files to Create` entry matching the
autonomous-task path set — `scheduled-*.yml`, `cron-*/oneshot-*` Inngest functions, new
registered checks) at both enforcement surfaces (plan emit §2.9.3, deepen-plan halt §4.13, plus
the workflow.js mirror); the `schedule` Step-1 collection + flag contract; and both generated
YAML templates that stamp `# Task design:`. The chokepoints are the create flow and the plan
gate — a hand-authored file outside either is out of every skill-level gate's reach by
construction (same trust surface as all skill rules).

**Mutation matrix.**

| # | Mutation | Expected |
|---|---|---|
| 1 | Plan creates `scheduled-foo.yml` with no `## Task Design` section | RED — §4.13 halts |
| 2 | Same plan emits `## Task Design` but `dedupe:` names only `concurrency: group:` | RED — concurrency-only dedupe reject |
| 3 | Plan creates a second new autonomous-task file after a compliant first and the section covers only the first | RED — the section must answer per created task |
| 4 | The recurring Step-3a template loses the `# Task design:` block | RED — schedule-task-design.test.sh asserts it |
| 5 | A plan's `## Task Design` carries the literal `TBD` as a field value | RED — placeholder reject |

**Harness rows.** (a) Suite row: `schedule-task-design.test.sh` runs against the edited
SKILL.md — if the suite itself never asserts (0 checks), `print_results` must still exit
non-zero on a missing template block. (b) Must-PASS non-canonical input: a `--once` workflow
whose answers are entirely template-derived (no free-text answers) still satisfies the property.
(c) Must-PASS: a plan that touches only docs emits no `## Task Design` and does not halt —
detection is Files-to-Create-scoped, not prose-scoped (P5).

## Open Code-Review Overlap

One open scope-out touches files this plan edits: **#4133** ("Schema parity test for `##
Observability` block" — names plan/SKILL.md, plan-issue-templates.md, deepen-plan/SKILL.md).
Disposition: **acknowledge** — this plan deliberately adds a *new conditional section* rather
than a 6th Observability field, so no new parity surface is created; the existing
`observability-schema-parity.test.ts` on main already implements #4133's ask (the issue appears
satisfiable but stays untouched — a stale-open review item, not this PR's scope).

## Domain Review

**Domains relevant:** Engineering.

### Engineering

**Status:** reviewed (in-process — no Task/Agent tool in this harness; leader spawn recorded in
decision-challenges.md)
**Assessment:** plugin-internal docs + skill-gate change. Conventions applied: glossary-format
pointer contract, conditional-plan-section precedent (Encryption Posture), test-helpers
conventions, NOTICE attribution convention, `cq-agents-md-tier-gate` (the new gate lives in the
enforcing skills, not AGENTS.rules.md). Product tier NONE — no Files-to-Create/Edit path matches
the UI-surface glob superset (all `.md`/`.sh`).

## Architecture Decision (ADR/C4)

**ADR: none (assumed — recorded as a pending technical ruling in decision-challenges.md).**
This change documents existing architecture (the map decides nothing new) and adds a
process-level design gate — the same class as the observability/encryption plan gates, which
are skill-enforced without ADRs.

**C4 views: no impact.** Read `model.c4`, `views.c4`, `spec.c4` — enumerated the change's (a)
external human actors: none added (the doc is internal agent-facing; `operator`/agent personas
already modeled), (b) external systems/vendors: none added (the map names already-modeled
systems — GitHub, Inngest, Sentry/Better Stack), (c) containers/data-stores touched: none — the
change adds a knowledge-base markdown file and edits skill text; C4 models runtime elements,
not KB docs, (d) actor↔surface access relationships: unchanged. The `plan`/`schedule` skill
components already exist in model.c4; no element or `include` line changes.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Create `knowledge-base/engineering/architecture/factory-map.md`: for each service slot (ticket tracker, ticket source, git host, orchestrator, observability platform) plus runner, name the concrete Soleur filling ... and map the peer vocabulary (Task / Trigger / Run / Runner) onto Soleur terms." [#11014] | Phase 1; Files-to-Create `factory-map.md` | mapped |
| 2 | "Then add `glossary.md` entries pointing at the map." / "`glossary.md` entries for run / trigger / runner / task point at it" [#11014] | Phase 1; Files-to-Edit `glossary.md` | mapped |
| 3 | "Peer-attribution convention followed (MIT — vocabulary/methodology only, no prose port)" [#11014] | Phase 1 NOTICE edit + attribution footer | mapped |
| 4 | "`soleur:schedule` `create` flow — require the answers in the generated workflow's header comment or the design issue" [#11015 option a] | Phase 2 | mapped |
| 5 | "extend the plan `## Observability` block (`hr-observability-as-plan-quality-gate`) with the trigger/chain/dedupe fields for plans that add autonomous tasks" [#11015 option b] | Phase 3 (`## Task Design` conditional section — sibling-gate form, see Decisions) | mapped |
| 6 | "The dedupe answer distinguishes workflow-level concurrency from semantic double-work" [#11015] | Phase 2 §Step-1 collection rule + §2.9.3 reject; Guard 1 row 2 | mapped |
| 7 | "No new gate for existing workflows — applies to newly created tasks only" [#11015] | Detection = Files-to-Create-only; Guard 1 harness row (c); test P5 assertion | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `factory-map.md` | asks 1 | asked |
| `glossary.md` entries | asks 2 | asked |
| NOTICE edit | asks 3 | asked |
| schedule SKILL.md Steps 0b/1/3a/3b | asks 4 | asked |
| plan §2.9.3 + templates + deepen-plan §4.13 + workflow.js | asks 5 | asked |
| dedupe/concurrency distinction rules | asks 6 | asked |
| create-only scoping | asks 7 | asked |
| `inngest-oneshot-and-reminder-patterns.md` section | "Soleur has an answer to each *somewhere*" + Step-0 routing makes Inngest the structural default for new autonomous work | inferred — justification: the plan-gate only fires on plan-authored files and `schedule` on GHA files; a new Inngest oneshot armed per the runbook would otherwise be an ungated creation path |
| `schedule-task-design.test.sh` + AFFECTED edge | — | inferred — justification: the Guard-Contract mutation matrix needs a harness; the repo convention is content-assertion suites for skill templates (`schedule-skill-once.test.sh`), and new suites need declared edges or the census reports UNCLASSIFIED |

### Split Assessment

- Subsystems touched: 3 — `knowledge-base/`, `plugins/soleur/`, `scripts/`
- Planned files: 11 | Estimated changed lines: ~650
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `knowledge-base/engineering/architecture/factory-map.md` exists; names all six slots
      (ticket tracker, ticket source, git host, orchestrator, runner, observability platform)
      with concrete Soleur fillings; maps peer → Soleur terms for Task / Trigger / Run / Runner;
      carries the MIT vocabulary-attribution note. Verify:
      `grep -cE 'ticket tracker|ticket source|git host|orchestrator|runner|observability' knowledge-base/engineering/architecture/factory-map.md` >= 6
- [ ] `glossary.md` carries exactly four new entries (`Run`, `Trigger`, `Runner`, `Task`), each
      pointing at `factory-map.md`. Verify:
      `grep -nE '^\*\*(Run|Trigger|Runner|Task)\*\*:' knowledge-base/project/glossary.md` returns 4 lines.
- [ ] `plugins/soleur/NOTICE` `mattpocock/skills` entry names `factory-map.md` and
      `schedule/SKILL.md` under `Used in` and records the vocabulary/checklist portions.
- [ ] `schedule` SKILL.md recurring flow requires the five non-derived answers (interactive or
      `--design-*` flags; non-interactive missing answer = hard error) and BOTH generated
      templates emit a `# Task design:` header carrying all six fields. Verify:
      `bash plugins/soleur/test/schedule-task-design.test.sh` prints `Failed: 0`.
- [ ] `plan-issue-templates.md` carries the conditional `## Task Design` schema in all three
      templates; `plan/SKILL.md` §2.9.3 exists; `deepen-plan/SKILL.md` §4.13 exists with the
      halt contract; `deepen-plan.workflow.js` mirrors the check. Verify:
      `grep -c '^## Task Design' plugins/soleur/skills/plan/references/plan-issue-templates.md` == 3
      and `grep -n 'Task-Design\|task-design\|Task Design' plugins/soleur/skills/deepen-plan/SKILL.md plugins/soleur/skills/plan/SKILL.md plugins/soleur/skills/deepen-plan/workflows/deepen-plan.workflow.js` hits in all three files.
- [ ] The dedupe rule distinguishes semantic double-work from `concurrency: group:` in both
      surfaces (skill collection text AND the §2.9.3/§4.13 reject).
- [ ] No existing `.github/workflows/scheduled-*.yml` is gated — the requirement is
      create-time only (suite assertion covers it).
- [ ] `inngest-oneshot-and-reminder-patterns.md` requires the six answers for new
      oneshots/cron functions and new registered checks.
- [ ] `scripts/lib/test-affected-paths.sh` declares the new suite's edge;
      `bash scripts/lint-orphan-test-suites.sh` stays green.
- [ ] Existing suites unaffected and green: `schedule-skill-once.test.sh`,
      `observability-schema-parity.test.ts`, `plan-scope-check.test.ts`,
      `plan-skeleton-checkpoint.test.ts`, `scripts/lint-skill-body-budget.py`.

## Test Scenarios

- Given a plan whose Files-to-Create lists `scheduled-foo.yml` and no `## Task Design`
  section, when deepen-plan §4.13 runs, then it halts naming the missing section (unit).
- Given a plan with `## Task Design` where `dedupe:` cites only `concurrency: group:`, when
  the gate runs, then it rejects as a concurrency-only answer (unit).
- Given `schedule` invoked recurring interactively, when Step 1 runs, then the operator is
  asked the five non-derived questions before the YAML is written (integration).
- Given `schedule --once --at <date> --issue <N> --comment <id> --name <n>`, when Step 3b
  generates, then the file's header already contains all six derived answers — no new flags
  required (unit — suite assertion).
- Given a docs-only plan, when §4.13 runs, then it does not halt (no Files-to-Create match)
  (unit).

## Context

Peer-attribution: MIT — vocabulary and checklist structure adopted, no prose ported; see NOTICE.
Upstream PR `mattpocock/skills#1316` is OPEN/unmerged — the map documents Soleur's own system;
the peer terms are a translation layer, not a dependency.

## Deepen Pass (soleur:deepen-plan — in-process)

This harness has no Task/Agent tool, so the per-section research fan-out, the
review-agent fan-out (Phase 5) and the domain-leader spawns could not run;
gate checks were applied in-process. Residual recorded in
`specs/feat-one-shot-11014-11015-factory-map-task-design/decision-challenges.md`
(review-stage `soleur:plan-review` remains available to the pipeline).

**Gate results (applied in-process):**

- Phase 4.6 User-Brand Impact halt — PASS (`## User-Brand Impact` present,
  `none` threshold with decision sentence; no sensitive-path match on the
  `SENSITIVE_PATH_RE` set — all edits are `.md`/`.sh` under `plugins/`,
  `knowledge-base/`, `scripts/lib/`).
- Phase 4.7 Observability gate — PASS: the diff's only executable surface is a
  test suite + a bash path-index lib, outside the §2.9 code roots; a compliant
  block is emitted anyway (`bash plugins/soleur/test/schedule-task-design.test.sh`,
  literal `Failed: 0`).
- Phase 4.8 PAT-shaped variable halt — PASS (no token-shaped variables).
- Phase 4.9 UI-wireframe halt — PASS/skip (no UI-surface file in Files lists).
- Phase 4.10 Encryption Posture halt — PASS/skip (no store or new connection).
- Phase 4.11 Guard Contract halt — PASS (`scripts/lint-guard-contract.py` on this
  file: 1 guard entry, matrix ≥3 rows incl. own-dispatch + harness rows).
- Phase 4.12 Scope Check halt — PASS (all asks mapped; two `inferred` items each
  carry a justification; split assessment under every threshold → single PR).
- Phase 4.5 network-outage / 4.55 downtime-cutover — not triggered.
- Precedent-diff (Phase 4.4): the `## Task Design` section byte-mirrors the
  `## Encryption Posture` conditional-section pattern (schema in all three
  templates, emit rule in plan, halt in deepen-plan, mirror in workflow.js).

**Corrections applied during the pass:** none needed — verification greps for
every named artifact were run before freezing Files lists (all paths exist);
the one open code-review overlap (#4133) is acknowledged with rationale.

## References

- Issues: #11014, #11015 (parent audit #11000)
- `knowledge-base/product/competitive-intelligence.md` §Addendum 2026-10-24 (SF1/SF2)
- `plugins/soleur/skills/kb-glossary/references/glossary-format.md` §The consumer pointer
- `plugins/soleur/agents/engineering/review/observability-coverage-reviewer.md` §The seven
  observability layers
- Conditional-section precedent: `## Encryption Posture` (plan §2.11 / deepen-plan §4.10)
- `scripts/lint-orphan-test-suites.sh` — AFFECTED_*_PATHS census requirement
- Upstream: `mattpocock/skills` branch `software-factory-skill`, `skills/in-progress/software-factory/SKILL.md`
