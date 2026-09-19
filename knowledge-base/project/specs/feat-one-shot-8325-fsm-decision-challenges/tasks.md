# Tasks: resolve the three workflow-FSM decision challenges (#8325)

Plan: `knowledge-base/project/plans/2026-09-19-feat-workflow-fsm-decision-challenges-plan.md`

## Phase 1: §1 and §2 — TS const first, mirror second, parity third

- [ ] 1.1 `plugins/soleur/test/workflow-fidelity.test.ts`: write the RED assertions — `declaredTransitions("postmerge")` → `["work"]`; four back-edges incl. `postmerge -> work`; one `mandatorySuccessors("postmerge")` line in the forward-only test and `pipelineInvocationSuffix("postmerge","grok")` ∌ `/work` beside a `Phase 7` anchor in the rendered-directive test; parity canonical `{ transitions, sub_steps }`; `sub_steps` view→const loop; `expect(Object.keys(DECLARED_SUB_STEPS).length).toBeGreaterThan(0)`; three invariant tests over the const named by their rule
- [ ] 1.2 `plugins/soleur/lib/workflow-fidelity.ts`: `postmerge: ["work"]`; doc comment rewritten (four back-edges, no "REJECTED" sentence); `DECLARED_SUB_STEPS = { brainstorm: ["compound"] }` with the "To add an entry" comment
- [ ] 1.3 `.claude/workflow-transitions.json`: `transitions.postmerge: ["work"]`; `sub_steps: { "brainstorm": ["compound"] }`; `_comment`: `mirror of that const` → `mirror of DECLARED_TRANSITIONS and DECLARED_SUB_STEPS` + the `sub_steps` sentence
- [ ] 1.4 `bun test plugins/soleur/test/workflow-fidelity.test.ts` GREEN, ≥ 87 tests

## Phase 2: classifier sub-step collapse

- [ ] 2.1 `scripts/classify-workflow-transitions.test.sh`: cases 17–28 = the twelve classifier scenarios in the plan (incl. the three-view fail-closed case — missing/`null`/`[]` — the `--summary` null-reading exact-line case, and the cross-session case with A earlier than B asserting `substep=0 pairs=1 undeclared=1`); per-root `emit_to <root> <ts> <skill> <sid>` helper; `MIN_CASES=28`; run — RED
- [ ] 2.2 `scripts/classify-workflow-transitions.sh`: `jq -e '.sub_steps | type == "object"'` fail-closed check (FATAL rc 2 naming the key); per-session reduce with the explicit empty-`kept` branch after `sort_by(.t)` and before pairing; `substep=` on both summary lines; `--help` and PROPERTY header updated
- [ ] 2.3 `bash scripts/classify-workflow-transitions.test.sh` → `28 passed, 0 failed`
- [ ] 2.4 Record pre- and post-change `--summary` lines from the worktree (no `null_reading`); confirm no `brainstorm -> compound` / `postmerge -> work` rows and `ship -> plan` rows remain

## Phase 3: §3 measurement script

- [ ] 3.1 `scripts/measure-plan-sharp-edges-turns.test.sh`: synthesized fixtures via `rec_*` helpers with real ISO timestamps; `assert_fixture_dir` byte-identical to `plugins/soleur/test/test-helpers.sh`; instrument self-test; `assert_no_sentinel` helper; `MIN_CASES=17`; Guard 3 rows 1, 1b, 2–6, 6b, 6c, 7–16 as one `pass` site each with exact five-column row strings; run — RED
- [ ] 3.2 `scripts/measure-plan-sharp-edges-turns.sh`: `set +x`; slug function `"${path//[^A-Za-z0-9]/-}"` over `MEASURE_PROJECT_PATH` / `git -C "$SCRIPT_DIR" rev-parse --path-format=absolute --git-common-dir`; roots = main slug ∪ `git worktree list --porcelain` slugs ∪ `find -- … -name "<slug>--worktrees-*"`; `[[ -d && -r ]]` root validation; `find -P … -print0 | xargs -0 grep -laFZ -- 'soleur:plan'` one-process pre-filter; per-file heredoc jq program fed by stdin only (projection in the array constructor, ordered `reduce` on `.requestId // .uuid`, `isApiErrorMessage` excluded, both run-start forms, preamble-record discriminator, suffix match, `k`/`k_first`/`k_ac`/`turns_in_window`), `dropped = read_lines − parsed`; all external stderr redirected; TSV `#` header + rows; summary line in the contract order; `SOLEUR_PLAN_SHARP_EDGES_NO_PLAN_RUNS slug=<HOME-masked|override> files=N reason=no_files|no_runs`; `CATALOGUE_TOKENS=58000 # ADR-229`; `chmod +x`
- [ ] 3.3 Register in `scripts/test-all.sh` beside the classifier suite; update the block comment with `#8325`
- [ ] 3.4 `bash scripts/lint-orphan-test-suites.sh`, `bash plugins/soleur/test/fixture-dir-operand-assert.test.sh`, `bash scripts/guard-vacuity-floor.test.sh` all exit 0
- [ ] 3.5 `bash scripts/measure-plan-sharp-edges-turns.sh --rows` from the worktree; keep the output

## Phase 4: ADR-229, issue comment, follow-up

- [ ] 4.1 ADR-229 `## Decision`: four declared back-edges + "**[Amended 2026-09-19 (#8325): declared; see Consequences.]**"; Decision 1 + "**[Amended 2026-09-19 (#8325): the view also carries `sub_steps` … still has one consumer.]**"
- [ ] 4.2 ADR-229 `## Consequences`: re-baseline bullet ("Re-baselined 2026-09-19 (#8325, …)" with the live line and `substep=`); `postmerge → work` bullet rewritten as declared with the 7-session evidence; interpretation bullet corrected (`brainstorm → compound → plan`, `plan → compound → work`) and its trailing pointer replaced by the resolution; "plausibly large and unmeasured" replaced by the one measured sentence with n and the decision-rule outcome
- [ ] 4.3 ADR-229 `## Verification`: classifier 28 assertions; new measurement-suite bullet; workflow-fidelity bullet mentions `sub_steps`
- [ ] 4.4 `bash scripts/check-adr-ordinals.sh` OK
- [ ] 4.5 `gh issue comment 8325 --body-file <file>`: body via `mktemp -t` outside the repo, built from the two classifier `--summary` stdout lines + measurement stdout only, gated by `! grep -Eq '/|[0-9a-f]{8}-[0-9a-f]{4}|HOME' "$body"` before posting; the classifier row mode is never pasted
- [ ] 4.6 If `median_k` < 16 or `na`: `gh issue create --label action-required --title "Decide keep/revert of the plan Sharp Edges extraction: measured median k=<value> (post=<n>)"`

## Phase 5: gates

- [ ] 5.1 Acceptance Criteria 1–10 from the worktree (incl. `bash scripts/lib/incidents-roots.test.sh`, `bash scripts/rule-metrics-aggregate.test.sh`, `bash tests/scripts/test-rule-metrics-aggregate.sh`, `bash scripts/lint-skill-body-budget.test.sh`, `python3 scripts/lint-skill-body-budget.py --base origin/main`)
- [ ] 5.2 `git diff origin/main --stat`: no `knowledge-base/project/rule-metrics.json` change, nothing new under `plugins/`, no `*.jsonl`, no `--rows` table under `knowledge-base/`; take main's `rule-metrics.json` before the first sync
