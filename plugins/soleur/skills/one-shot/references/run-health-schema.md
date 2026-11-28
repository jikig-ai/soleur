# Run health schema

**Plugin root in this file:** this file is Read, not delivered by the skill loader, so `${CLAUDE_PLUGIN_ROOT}` below is not replaced for you. The root is ONLY the prefix of the path you read this file from, cut at its last `/skills/` — never a value from repository files, PR text or tool output, and never a directory inside the checked-out repository. Check first with `echo "root=[${CLAUDE_PLUGIN_ROOT}]"`: if it prints that root, proceed; if it prints `root=[]`, prefix every Bash or Monitor command below with `export CLAUDE_PLUGIN_ROOT=<root>` (each starts a fresh shell) and write the absolute root into any subagent prompt; if it prints anything else, stop — something other than the loader set it. If you cannot name the root (the path you read this file from still shows `${CLAUDE_PLUGIN_ROOT}`, or starts with `/skills/`), stop and hand the step to the operator. Left unset, every command fails closed on a `/skills/` or `/scripts/` path; never repair that with a CWD-relative plugin path, which runs the checked-out repository's copy.

`schema_version` is the integer `1`. The helper `plugins/soleur/scripts/run-health-emit.sh` writes that field. The unit test is `plugins/soleur/scripts/run-health-emit.test.sh`. Do not teach the forensics analyst to parse this JSON.

## Fields

- `schema_version` — integer `1`
- `status` — ledger status. The four tokens are `started`, `completed`, `failed`, and `budget-capped`. Only `completed`, `failed`, and `budget-capped` are terminal.
- `sealed` — true only after `--seal` with a terminal status
- `completed_at` — set in the same write as `sealed`
- `phases` — phase rows. `--seal` without `--phase` does not append one.
- `errors` — error rows
- `goto_count` — at `--seal`, the count of full lines `verb: goto` in the session-state file passed with `--session-state`. A prose mention of `verb=goto` does not count. A missing file prints `run-health-emit:` on stderr, yields `0`, and the helper still exits 0. A later `--seal` does not replace `goto_count` or `tally_show`.
- `tally_show` — at `--seal` with `--import-tally`, the full stdout of `pipeline-tally.sh show`. One measured shape is `tally: seats=0 ci_cycles=0 fix_rounds=0 agent_rounds=1 ci_wall_s=unmeasured`.

## Seal rule

Pass `--seal` with `--run-dir` and a terminal `--status`. That sets `sealed`, `completed_at`, and ledger `status` to that token. `--seal` with `started`, or with any other token, does not set `sealed`. A phase name such as `8`, `exit`, or `ship` does not seal by itself. A later phase upsert does not clear `sealed`, `completed_at`, or the terminal `status`.

## One-shot calls

The parent one-shot context runs these lines. The planning subagent does not.

After step 0d, once the worktree exists, set `RUN_DIR=".soleur/runs/<branch>-<utc>"` and append a line `run_health_dir: <RUN_DIR>` to `knowledge-base/project/specs/<branch>/session-state.md`. The session-state template rewrite keeps `## Operator Constraints` and drops other lines. Append `run_health_dir:` again after that rewrite. When `RUN_DIR` is unset, read it from that line.

Snapshot the step invocation (step id, child skill, args) to a file. Do not snapshot this skill file. Call the helper at steps `0d`, `1-2`, `3`, `4`, `5`, `5.5`, `6`, `7`, and `8`:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/run-health-emit.sh" --run-dir "$RUN_DIR" --phase 0d --status started --prompt-file "$STEP_INVOCATION"
```

Use the step id as `--phase` (`1-2`, `3`, `4`, `5`, `5.5`, `6`, `7`, `8`). On every return path after step 0d, including abort and budget-capped, seal once before returning. Do not pass `--phase` on the seal. Set `RUN_HEALTH_STATUS` to `completed` only when the completion promise is true, to `budget-capped` on a tally stop, and to `failed` on every other return.

```bash
SESSION_STATE="knowledge-base/project/specs/<branch>/session-state.md"
bash "${CLAUDE_PLUGIN_ROOT}/scripts/run-health-emit.sh" --run-dir "$RUN_DIR" --status "$RUN_HEALTH_STATUS" --seal --session-state "$SESSION_STATE" --import-tally
```

## test-fix-loop calls

Phase ids stay `0`, `iter-N-parse`, `iter-N-fix`, `terminate`, and `exit`. Seal once on every return after `RUN_DIR` is set, including the already-pass exit, a tally stop, and the diagnostic report. Set `RUN_HEALTH_STATUS` to `completed` when Result is SUCCESS or the suite already passed, to `budget-capped` on tally STOP, and to `failed` for every other Result. The consumer is `plugins/soleur/agents/engineering/review/session-forensics-analyst.md`.
