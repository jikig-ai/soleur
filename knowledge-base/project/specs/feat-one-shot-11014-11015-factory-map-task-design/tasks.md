# Tasks: factory-map + task-design questions (#11014, #11015)

Plan: `knowledge-base/project/plans/2026-10-24-feat-factory-map-task-design-plan.md`

## Phase 1: factory-map + glossary + attribution (#11014)

- [ ] 1.1 Write `knowledge-base/engineering/architecture/factory-map.md` — six-slot table
      (ticket tracker / ticket source / git host / orchestrator / runner / observability
      platform) with concrete Soleur fillings; peer→Soleur term map for Task / Trigger /
      Run / Runner including honest divergences (Soleur "session", "sandbox"); MIT
      attribution footer (vocabulary/methodology only).
- [ ] 1.2 Add four pointer entries to `knowledge-base/project/glossary.md`
      (`Run`, `Trigger`, `Runner`, `Task`) per `glossary-format.md` — body names
      `factory-map.md` + §anchor; `_Avoid_` lines where a wrong sense produces a wrong
      commit.
- [ ] 1.3 Extend `plugins/soleur/NOTICE` `mattpocock/skills` entry: `Used in` +=
      `knowledge-base/engineering/architecture/factory-map.md`,
      `plugins/soleur/skills/schedule/SKILL.md`; `Portions adopted` += the factory-slot
      ontology vocabulary + question-every-task checklist.

## Phase 2: schedule create flow (#11015, surface a)

- [ ] 2.1 `plugins/soleur/skills/schedule/SKILL.md` Step 1: add collection of the five
      non-derived answers (services read/write, triggers-next, human re-entry, semantic
      dedupe — must name something beyond `concurrency: group:`, source dedupe or
      "not a ticket source").
- [ ] 2.2 Step 0b: add `--design-services`, `--design-next`, `--design-reentry`,
      `--design-dedupe`, `--design-source-dedupe`; non-interactive invocation with a
      missing design answer is a hard error.
- [ ] 2.3 Step 3a template: prepend `# Task design:` header block above `name:` with all
      six answers (trigger derived from cron + `workflow_dispatch`).
- [ ] 2.4 Step 3b template: same block with D1–D5-derived answers; no new `--once` flags.

## Phase 3: plan-time gate + Inngest runbook (#11015, surface b)

- [ ] 3.1 `plugins/soleur/skills/plan/references/plan-issue-templates.md`: add conditional
      `## Task Design` schema to all three templates (after `## Observability`).
- [ ] 3.2 `plugins/soleur/skills/plan/SKILL.md`: new `#### 2.9.3. Task-Design Gate
      (Conditional)` — Files-to-Create detection (new `scheduled-*.yml`, new
      `cron-*/oneshot-*` Inngest function, new registered check); emit + reject rules
      incl. concurrency-only dedupe reject.
- [ ] 3.3 `plugins/soleur/skills/deepen-plan/SKILL.md`: new `### 4.13. Task-Design Halt
      (Conditional)` mirroring §4.10's shape.
- [ ] 3.4 `plugins/soleur/skills/deepen-plan/workflows/deepen-plan.workflow.js`: mirror
      the new gate bullet.
- [ ] 3.5 `knowledge-base/engineering/operations/runbooks/inngest-oneshot-and-reminder-patterns.md`:
      require the six answers in the design issue/plan for new oneshots/cron functions and
      in the arming record for new registered checks.

## Phase 4: test + registration

- [ ] 4.1 Create `plugins/soleur/test/schedule-task-design.test.sh` (test-helpers.sh):
      both templates carry the `# Task design:` block + all six keys; Step 1 collects;
      Step 0b documents flags; create-time-only scoping asserted.
- [ ] 4.2 Add `AFFECTED_PLUGINS_SOLEUR_TEST_SCHEDULE_TASK_DESIGN_TEST_SH_PATHS` to
      `scripts/lib/test-affected-paths.sh` (suite, SKILL.md, both template surfaces,
      index file).
- [ ] 4.3 Green: `bash plugins/soleur/test/schedule-task-design.test.sh`,
      `bash plugins/soleur/test/schedule-skill-once.test.sh`,
      `bun test plugins/soleur/test/observability-schema-parity.test.ts`,
      `bun test plugins/soleur/test/plan-scope-check.test.ts`,
      `bun test plugins/soleur/test/plan-skeleton-checkpoint.test.ts`,
      `python3 scripts/lint-skill-body-budget.py`, `bash scripts/lint-orphan-test-suites.sh`.
- [ ] 4.4 Markdownlint the touched `.md` files.
