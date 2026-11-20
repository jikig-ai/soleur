# Run health schema

`schema_version` is the integer `1`. The helper `plugins/soleur/scripts/run-health-emit.sh` writes that field. The unit test is `plugins/soleur/scripts/run-health-emit.test.sh`. Do not teach the forensics analyst to parse this JSON.

## Fields

- `schema_version` — integer `1`
- `status` — ledger status. The four tokens are `started`, `completed`, `failed`, and `budget-capped`. Only `completed`, `failed`, and `budget-capped` are terminal.
- `sealed` — true only after `--seal` with a terminal status
- `completed_at` — set in the same write as `sealed`
- `phases` — phase rows. `--seal` without `--phase` does not append one.
- `errors` — error rows
- `goto_count` — at `--seal`, the count of full lines `verb: goto` in the session-state file passed with `--session-state`. A prose mention of `verb=goto` does not count. A missing file yields `0` and the helper still exits 0.
- `tally_show` — at `--seal` with `--import-tally`, the full stdout of `pipeline-tally.sh show`. One measured shape is `tally: seats=0 ci_cycles=0 fix_rounds=0 agent_rounds=1 ci_wall_s=unmeasured`.

## Seal rule

Pass `--seal` with `--run-dir` and a terminal `--status`. That sets `sealed`, `completed_at`, and ledger `status` to that token. `--seal` with `started`, or with any other token, does not set `sealed`. A phase name such as `8`, `exit`, or `ship` does not seal by itself. A later phase upsert does not clear `sealed`, `completed_at`, or the terminal `status`.

## One-shot calls

The parent one-shot context runs these lines. The planning subagent does not.

After step 0d, once the worktree exists, set `RUN_DIR=".soleur/runs/<branch>-<utc>"` and append a line `run_health_dir: <RUN_DIR>` to `knowledge-base/project/specs/<branch>/session-state.md`.

Snapshot the step invocation (step id, child skill, args) to a file. Do not snapshot this skill file. Call the helper at steps `0d`, `1-2`, `3`, `4`, `5`, `5.5`, `6`, `7`, and `8`:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/run-health-emit.sh" --run-dir "$RUN_DIR" --phase 0d --status started --prompt-file "$STEP_INVOCATION"
```

Use the step id as `--phase` (`1-2`, `3`, `4`, `5`, `5.5`, `6`, `7`, `8`). On every return path, including abort and budget-capped, seal before returning. Do not pass `--phase` on the seal:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/run-health-emit.sh" --run-dir "$RUN_DIR" --status failed --seal --session-state "$SESSION_STATE" --import-tally
```

Step 8 uses `--status completed` only when the completion promise is true. Otherwise use `--status failed`. A budget cap uses `--status budget-capped`.

## test-fix-loop calls

Phase ids stay `0`, `iter-N-parse`, `iter-N-fix`, `terminate`, and `exit`. Seal once, on the way to the diagnostic report, with `completed`, `failed`, or `budget-capped`. The consumer is `plugins/soleur/agents/engineering/review/session-forensics-analyst.md`.
