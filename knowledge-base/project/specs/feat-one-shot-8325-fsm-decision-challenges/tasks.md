# Tasks: resolve the three workflow-FSM decision challenges (#8325)

Plan: `knowledge-base/project/plans/2026-09-19-feat-workflow-fsm-decision-challenges-plan.md`

## Phase 1: §1 and §2 — TS const first, mirror second, parity third

- [ ] 1.1 `plugins/soleur/test/workflow-fidelity.test.ts`: write the RED assertions — `declaredTransitions("postmerge")` → `["work"]`; four back-edges incl. `postmerge -> work`; one `mandatorySuccessors("postmerge")` line in the forward-only test; parity canonical `{ transitions, sub_steps }`; `sub_steps` view→const loop; three invariant tests over the const named by their rule
- [ ] 1.2 `plugins/soleur/lib/workflow-fidelity.ts`: `postmerge: ["work"]`; doc comment rewritten (four back-edges, no "REJECTED" sentence); `DECLARED_SUB_STEPS = { brainstorm: ["compound"] }` with the "To add an entry" comment
- [ ] 1.3 `.claude/workflow-transitions.json`: `transitions.postmerge: ["work"]`; `sub_steps: { "brainstorm": ["compound"] }`; `_comment` sentence
- [ ] 1.4 `bun test plugins/soleur/test/workflow-fidelity.test.ts` GREEN, ≥ 87 tests

## Phase 2: classifier sub-step collapse

- [ ] 2.1 `scripts/classify-workflow-transitions.test.sh`: cases 17–28 = the twelve classifier scenarios in the plan (incl. the two-view fail-closed case and the `--summary` null-reading `substep=0` case); `MIN_CASES=28`; run — RED
- [ ] 2.2 `scripts/classify-workflow-transitions.sh`: `jq -e '.sub_steps | type == "object"'` fail-closed check (FATAL rc 2 naming the key); per-session reduce with the explicit empty-`kept` branch after `sort_by(.t)` and before pairing; `substep=` on both summary lines; `--help` and PROPERTY header updated
- [ ] 2.3 `bash scripts/classify-workflow-transitions.test.sh` → `28 passed, 0 failed`
- [ ] 2.4 Record pre- and post-change `--summary` lines from the worktree (no `null_reading`); confirm no `brainstorm -> compound` / `postmerge -> work` rows and `ship -> plan` rows remain

## Phase 3: §3 measurement script

- [ ] 3.1 `scripts/measure-plan-sharp-edges-turns.test.sh`: synthesized fixtures via `rec_*` helpers; `assert_fixture_dir` byte-identical to `plugins/soleur/test/test-helpers.sh`; instrument self-test; `MIN_CASES` literal; the fifteen measurement scenarios in the plan; run — RED
- [ ] 3.2 `scripts/measure-plan-sharp-edges-turns.sh`: slug function (`MEASURE_PROJECT_PATH` / `git rev-parse --git-common-dir`, non-alphanumeric → `-`), `find`-based root enumeration, `grep -qF` pre-filter, per-file jq pass (turns by `.requestId // .uuid`, `isApiErrorMessage` excluded, both run-start forms, preamble-record discriminator, suffix match, `k`/`k_first`/`k_ac`/`turns_in_window`), `#` header + rows, grouped summary line, two-reason null line, `CATALOGUE_TOKENS=58000`; `chmod +x`
- [ ] 3.3 Register in `scripts/test-all.sh` beside the classifier suite; update the block comment with `#8325`
- [ ] 3.4 `bash scripts/lint-orphan-test-suites.sh`, `bash plugins/soleur/test/fixture-dir-operand-assert.test.sh`, `bash scripts/guard-vacuity-floor.test.sh` all exit 0
- [ ] 3.5 `bash scripts/measure-plan-sharp-edges-turns.sh --rows` from the worktree; keep the output

## Phase 4: ADR-229, issue comment, follow-up

- [ ] 4.1 ADR-229 `## Decision`: four declared back-edges + "Amended 2026-09-19 (#8325): declared; see Consequences."
- [ ] 4.2 ADR-229 `## Consequences`: re-baseline bullet ("Re-baselined 2026-09-19 (#8325, …)" with the live line and `substep=`); `postmerge → work` bullet rewritten as declared with the 7-session evidence; interpretation bullet corrected (`brainstorm → compound → plan`, `plan → compound → work`) and its trailing pointer replaced by the resolution; "plausibly large and unmeasured" replaced by the one measured sentence with n and the decision-rule outcome
- [ ] 4.3 ADR-229 `## Verification`: classifier 28 assertions; new measurement-suite bullet; workflow-fidelity bullet mentions `sub_steps`
- [ ] 4.4 `bash scripts/check-adr-ordinals.sh` OK
- [ ] 4.5 `gh issue comment 8325 --body-file <file>`: both classifier summary lines, the measurement summary line, the `--rows` table (numbers only)
- [ ] 4.6 If `median_k` < 16 or `na`: `gh issue create --label action-required --title "Decide keep/revert of the plan Sharp Edges extraction: measured median k=<value> (post=<n>)"`

## Phase 5: gates

- [ ] 5.1 Acceptance Criteria 1–10 from the worktree (incl. `bash scripts/lib/incidents-roots.test.sh`, `bash scripts/rule-metrics-aggregate.test.sh`, `bash tests/scripts/test-rule-metrics-aggregate.sh`, `bash scripts/lint-skill-body-budget.test.sh`, `python3 scripts/lint-skill-body-budget.py --base origin/main`)
- [ ] 5.2 `git diff origin/main --stat`: no `knowledge-base/project/rule-metrics.json` change, nothing new under `plugins/`; take main's `rule-metrics.json` before the first sync
