# Retry budget ruling

Loaded when a child's `budget-capped` marker is about to halt one-shot. The parent runs this procedure and branches on the verdict line from `plugins/soleur/scripts/retry-budget-ruling.sh`. It does not decide the verb by reading prose. Exit status 0 is an allow-listed `goto`, not `continue`.

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

Pipe the spawned line on stdin. Omit `--history` when history is empty. Do not pass `--evidence`. The ledger is the feature `knowledge-base/project/specs/<branch>/session-state.md` in the checkout that owns the counter. The script writes only when the spec directory name is the branch, the final component is `session-state.md`, and the path sits under the toplevel. Pass `--not-capped` with no value only in step 5. It is not part of the spawn call.

Set `--toplevel` and `--git-common-dir` only from `git rev-parse --show-toplevel` and `git rev-parse --path-format=absolute --git-common-dir`. Do not pass `$PWD`, a logical path, or a hand-rewritten path. Do not pass a path that contains a person's name, an email address, or an account identifier. If either git command prints such a path, do not call the script and do not write the section.

On every verdict other than `goto`, `--phase` is empty or one of `plan`, `work`, `review`, `qa`, `test-fix-loop`. It is not a sentence, an email, a user id, or other prose. Do not copy the child marker, the attempt history, or customer content into it. `goto` still records only the token the script parsed.

`--child-session` is empty, or one path under the toplevel. It is not free text, not a sentence, and not a path outside the toplevel. If the child session file is not under the toplevel, pass an empty value. Do not copy the child's contents.

Checks run in this order. An earlier check wins.

## Before any spawn

1. Re-read the child's `budget-capped` lines and tally `show` from the checkout that owns the counter. The last line whose dimension `show` still reports capped selects the dimension. An earlier line that `show` does not cap does not select the dimension and does not force empty history.
2. Resolve git toplevel, branch, and git common dir. If they do not match the ledger path, do not spawn. The script prints `SOLEUR_RETRY_BUDGET_RULING verb=fail reason=identity` and writes nothing.
3. If session-state already contains the exact line `ruling_spawn: used`, call the script and do not spawn. The verdict is `reason=spent`. The script appends nothing. Do not also write an empty-history section. A prose mention of that line is not the bit.
4. If `show` is missing or `UNKNOWN`, or history is missing or empty, pass empty history and do not spawn. Do not pass `--not-capped` for this case. The script prints `verb=fail reason=empty-history` and appends one ruling section that does not contain `ruling_spawn: used`.
5. If `show` is readable and step 1 selected no line, do not spawn. Do not write `retry_budget_grant: 1` and do not write `ruling_spawn: used`. Call the script with `--not-capped` and do not pipe a ruling line. The verdict is `verb=fail reason=not-capped`. The script appends one section that does not contain `ruling_spawn: used`. Do not label that `empty-history`. An already spent bit still wins at step 3.
6. Otherwise spawn one fresh context and feed it the attempt history for the selected dimension. This one call is the exception to never-improvise, because the ruling is not a registered agent. No Soleur definition, skill body, or other instruction comes before the prompt's first line. Do not pass `soleur:engineering:cto` or any registered Soleur id. Claude: Task tool, `subagent_type` `general-purpose`. Devin: `run_subagent` profile `subagent_general`, with no definition path before the rule line. Grok: `spawn_subagent` with `subagent_type` omitted, and `run_in_background` false or an explicit wait before piping. Do not pass the string `general-purpose` and do not pass a `.grok/agents` stem. Codex: `spawn_agent` with the tool's default type, the ruling text as the message, and no Soleur definition path prepended. Antigravity: `invoke_subagent` with built-in TypeName `self` and the Prompt starting at the rule line. Do not `define_subagent` from a Soleur agent file. OpenCode and Cursor have no verified blank call. Unknown harness: Task `general-purpose`. If the named call is rejected, or the harness has no blank call, do not invent a line, do not ask the operator, and do not spawn a Soleur agent. Pipe no bytes to the script. That empty section is `verb=fail reason=empty` with `ruling_spawn: used`, and it means the blank spawn did not run. The next halt is `reason=spent`. Pipe the spawn's stdout, including no line, to the script. The ledger arguments are the fixed fields plus one path to the child session. The spawn does not increment the dimension named on the child's marker. Do not pass `--not-capped`. A history path that is a symlink, or that is not a regular file under the toplevel, is empty history.

The spawn prompt opens with this line and no other instruction before it:

```text
Rule on this technical question. Do NOT use AskUserQuestion.
```

Then ask for exactly one line: `continue`, `fail`, or `goto` plus one of `plan`, `work`, `review`, `qa`, or `test-fix-loop`. Put the attempt history after that request. Do not add a heading that introduces a next-step list. `goto ship` and `goto merge` are not in the request.

## Apply the printed verb

`continue`: the parent runs no unit. It does not re-enter a child skill, and it does not start the next one-shot step, `ship`, or `merge`. Do not write `retry_budget_grant: 1`. Do not write a ralph grant. Do not write the compact marker `retry-budget-ruling: verb=continue`. The script records the spawn's word on `spawn-line: continue`, writes `reason: not-run` and the exact line `applied: not-run`, and writes `ruling_spawn: used`. Stdout is `SOLEUR_RETRY_BUDGET_RULING verb=fail reason=not-run` plus the plain line. Do not leave `verb: continue` as the applied outcome, and do not invent a ralph file. A later halt is `reason=spent`. Do not delete the spawn bit.

`goto`: write no ralph bit. Read `phase=` from the verdict line. Do not read the phase from `--phase` or from the spawn line. In the same turn, re-enter only a phase that is earlier than the halt boundary. `plan` is steps 1–2. `work` is step 3. `review` is step 4. `qa` is step 5.5. `test-fix-loop` sits after step 5.5 and before step 7: read `plugins/soleur/skills/test-fix-loop/SKILL.md` and run that skill. A halt before step 7 may enter it and must not enter step 7 or step 8. A halt at step 3, step 4, or step 5.5, or earlier, treats `goto test-fix-loop` as not earlier: the parent halts and does not start that skill. The script has no `not-earlier` reason and does not receive the halt boundary. Do not resume `ship` or `merge`. A `goto` that is not earlier than the halt boundary halts. The sticky `budget-capped` line does not start another ruling until that action has started. The compact marker is `retry-budget-ruling: verb=goto phase=` followed by the allow-listed name.

`fail`: today's halt. When the reason is not `spent`, the script has already printed the verdict line and one plain line that names the verb and the reason. `reason=spent` prints the verdict line only and appends nothing. The ledger section for a first fail with non-empty history is already written and contains `ruling_spawn: used`. There is no `ruling_grant` bit. The verb field records goto or fail. A `continue` spawn line is `spawn-line: continue` and is not the verb. A failed append that already spawned prints `verb=fail reason=write-failed`. When the file can take a whole section, that section contains `ruling_spawn: used` and the next halt is `reason=spent`. When it cannot, the script writes nothing and a later process can spawn. A read of the existing ledger that fails prints `verb=fail reason=write-failed` and writes nothing. `reason=identity` stays the path refusal, before any append.

The continuation marker is one line. It is not a section heading.

## Latch

`capped=` stays set. The cap is not raised. The parent does not clear the tally latch and does not treat `init --max-*` as this record. A later halt after `applied: not-run`, or a second exhaustion while `ruling_spawn: used` is set, is `fail` with no second spawn.
