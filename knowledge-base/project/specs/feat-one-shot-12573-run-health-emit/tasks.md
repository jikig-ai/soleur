# Tasks: emit run health artifacts

## Phase 1: Setup

- [ ] 1.1 Write `plugins/soleur/skills/one-shot/references/run-health-schema.md` with schema version 1, the four status tokens, the seal rule, `goto_count` as a count of full lines `verb: goto` in the passed session-state file, the tally line shape, and the one-shot call list (parent context, step ids, `run_health_dir:`, `--seal` on every return path).
- [ ] 1.2 Leave `plugins/soleur/agents/engineering/review/session-forensics-analyst.md` unchanged.

## Phase 2: Core Implementation

- [ ] 2.1 Extend `plugins/soleur/scripts/run-health-emit.sh`: write `schema_version` 1, add `--seal`, `--session-state`, `--import-tally`, and `--discover`, refuse a bad phase token in the shell before `mkdir -p`, and delete the phase-name seal heuristic. Refuse `.`, `..`, and any token containing `..`. `--seal` does not require `--phase` and does not append a phase row. Keep `os.replace` of a same-directory temp file and do not add `fsync`. Keep fail-open exit 0.
- [ ] 2.2 Edit `plugins/soleur/skills/one-shot/SKILL.md`: insert the `run-health-emit` block from the plan, delete the two dated history sentences in the paragraph that starts `**Why this gate exists.**`, and stop when `wc -c` is at most 51950. Do not edit pinned paragraphs or the `description:` line. Do not change `plugins/soleur/test/skill-body-budget.json`.
- [ ] 2.3 Replace the Run Health Emission section in `plugins/soleur/skills/test-fix-loop/SKILL.md` with `bash` calls of the helper, a markdown link to the schema, and one `--seal` on the real exit. Do not cite a closed issue number. Do not change the `description:` line.

## Phase 3: Testing

- [ ] 3.1 Extend `plugins/soleur/scripts/run-health-emit.test.sh` with the cases in the plan's Test Scenarios, including phase token `..` and `--seal` with no `--phase`. Do not add a new suite file. Stub `pipeline-tally.sh` on `PATH`. Do not edit the real tally script.
- [ ] 3.2 Run `bash plugins/soleur/scripts/run-health-emit.test.sh` and require `fails=0`.
- [ ] 3.3 Run `wc -c plugins/soleur/skills/one-shot/SKILL.md` and require a value at most 51950. Run `python3 scripts/lint-skill-body-budget.py --base origin/main` and require OK. Leave `ceilings.one-shot` in `plugins/soleur/test/skill-body-budget.json` at 52000.
- [ ] 3.4 Run `git check-ignore -q -- .soleur/runs/example/run_health.json` and the same for `.soleur/runs/example/phase_prompts/0.md`. Both exit 0 with no new `.gitignore` line.
