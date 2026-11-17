# Retry budget ruling

Loaded when a child's `budget-capped` marker is about to halt one-shot. The parent runs this procedure and branches on the verdict line from `plugins/soleur/scripts/retry-budget-ruling.sh`. It does not decide the verb by reading prose, and it does not treat exit status 0 as `continue`, because an allow-listed `goto` shares that exit.

The script is the only parser. Call it as:

```bash
bash plugins/soleur/scripts/retry-budget-ruling.sh \
  --toplevel "$TOP" \
  --branch "$BRANCH" \
  --git-common-dir "$COMMON" \
  --ledger "$LEDGER" \
  --history "$HISTORY" \
  --child-session "$CHILD" \
  --phase "$PHASE"
```

Pipe the spawned line on stdin. Omit `--history` when history is empty. Do not pass `--evidence`. The ledger is the feature `knowledge-base/project/specs/<branch>/session-state.md` in the checkout that owns the counter. The script writes only when the spec directory name is the branch and the path sits under the toplevel.

Checks run in this order. An earlier check wins.

## Before any spawn

1. Re-read the child's `budget-capped` lines and tally `show` from the checkout that owns the counter. The last line whose dimension `show` still reports capped selects the dimension. An earlier line that `show` does not cap does not select the dimension and does not force empty history.
2. Resolve git toplevel, branch, and git common dir. If they do not match the ledger path, do not spawn. The script prints `SOLEUR_RETRY_BUDGET_RULING verb=fail reason=identity` and writes nothing.
3. If session-state already contains `ruling_spawn: used`, call the script and do not spawn. The verdict is `reason=spent`. The script appends nothing. Do not also write an empty-history section.
4. If `show` is missing or `UNKNOWN`, or history is missing or empty, pass empty history and do not spawn. The script prints `verb=fail reason=empty-history` and appends one ruling section that does not contain `ruling_spawn: used`.
5. Otherwise spawn one fresh context and feed it the attempt history for the selected dimension. Pipe its stdout, including no line, to the script. The ledger arguments are the fixed fields plus one path to the child session. The spawn does not increment the dimension named on the child's marker.

The spawn prompt opens with this line and no other instruction before it:

```text
Rule on this technical question. Do NOT use AskUserQuestion.
```

Then ask for exactly one line: `continue`, `fail`, or `goto` plus one of `plan`, `work`, `review`, `qa`, or `test-fix-loop`. Put the attempt history after that request. Do not add a heading that introduces a next-step list. `goto ship` and `goto merge` are not in the request.

## Apply the printed verb

`continue`: run one bounded unit of the exhausted work, then stop. That unit is not a child re-entry whose `gate` on the capped dimension exits before any work, and it is not the next one-shot step, `ship`, or `merge`. Write the unquoted line `retry_budget_grant: 1` only inside the first frontmatter block of the ralph file that already exists (`${GIT_COMMON_ROOT}/.claude/ralph-loop.${RALPH_LOOP_PID:-$PPID}.local.md`), only after the script printed `verb=continue`, and only once. A line outside that block does not arm the hook. Do not write it on the keep-alive turn or after `retry_budget_consumed: 1` is set. Write the compact marker `retry-budget-ruling: verb=continue grant=1`. The `grant=1` in that marker is the ralph line, not a ledger bit. `reason=spent` does not apply during that unit. The `budget-capped` line that triggered this ruling does not start another ruling during that unit. If the ralph file is absent and the parent cannot run the unit in-process, append `applied: not-run` to the ruling section and halt. Do not leave `continue` as the applied outcome, and do not invent a ralph file.

`goto`: write no ralph bit. In the same turn, re-enter only a phase that is earlier than the halt boundary. `plan` is steps 1–2. `work` is step 3. `review` is step 4. `qa` is step 5.5. `test-fix-loop` sits after step 5.5 and before step 7: read `plugins/soleur/skills/test-fix-loop/SKILL.md` and run that skill. A halt before step 7 may enter it and must not enter step 7 or step 8. A halt at step 3, step 4, or step 5.5, or earlier, treats `goto test-fix-loop` as not earlier: the parent halts and does not start that skill. The script has no `not-earlier` reason and does not receive the halt boundary. Do not resume `ship` or `merge`. A `goto` that is not earlier than the halt boundary halts. The sticky `budget-capped` line does not start another ruling until that action has started. The compact marker is `retry-budget-ruling: verb=goto phase=` followed by the allow-listed name.

`fail`: today's halt. When the reason is not `spent`, the script has already printed the verdict line and one plain line that names the verb and the reason. `reason=spent` prints the verdict line only and appends nothing. The ledger section for a first fail with non-empty history is already written and contains `ruling_spawn: used`. There is no `ruling_grant` bit. The verb field records continue, goto, or fail.

The continuation marker is one line. It is not a section heading.

## Latch

`capped=` stays set. The cap is not raised. The parent does not clear the tally latch and does not treat `init --max-*` as this grant. A later halt after the one unit, or a second exhaustion while `ruling_spawn: used` is set, is `fail` with no second spawn.
