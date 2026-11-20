---
title: "feat(engineering): arbitration adjudication when retry budgets exhaust — continue/goto/fail ruling agent"
type: feat
date: 2026-11-16
slug: feat-retry-budget-ruling
branch: feat-12526-retry-budget-arbitration
issue: 12526
closes: 12526
priority: p3
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Enhancement Summary

**Deepened on:** 2026-11-17
**Sections enhanced:** 4 (Research Insights, Phase 3, Files to Edit, Acceptance Criteria)
**Research agents used:** none in this pass. The 2026-11-16 plan-review panel is not re-run. External research stays skipped under the clean-room ceiling.

### Key Improvements

1. The two halt cues have a named same-edit payment, so the 52000-byte ceiling is a measured remainder.
2. The stop-hook reorder is a change to the current file. The first-frontmatter awk and its `mv` run before `pipeline-tally.sh show` today.
3. `Read references/` is a new cue. No skill body uses that phrase. The token-discipline load stays a markdown link, and that link is not the payment.

### New Considerations Discovered

- The cue `Read references/retry-budget-ruling.md` is 38 bytes. With a leading space and a trailing period the insertion is 40 bytes at each halt, 80 together. Headroom on the 51968-byte file is 32, so the edit deletes 56 bytes that are not conditions.
- The payment is the second `dispose of it` in the prose-Ref bullet, including the space before those words (14 bytes), and the parenthetical on the token-discipline Read whose text is `moved verbatim; byte-ceiling extraction`, including the space before the opening parenthesis (42 bytes). Net is +24. When `wc -c` is still 51968 the file ends at 51992.
- Today's capped path exits 0 after appending `budget-capped:` and before any keep-alive block. The no-grant path keeps that exit. The grant path rewrites the line in that same awk and reads it back after the `mv`.

## Overview

When a parent pipeline halt is caused by a child's classified budget stop, a fresh context reads the attempt evidence and returns one verb. `continue` records `applied: not-run` and the parent runs no unit. `goto` moves to an earlier allow-listed phase. `fail` keeps today's halt and writes a ledger. The classified stop stays in force. The cap is not raised.

## Research Insights

### Premise Validation

Checked this session: issue #12526 is OPEN, parent epic #12533 is OPEN, and ADR-268 is the accepted constraint this plan extends. The draft PR for this branch is #12815. A prior `collision-precheck.sh 12526` exited 10 because that draft is the only open PR naming the issue; foreign `test-all` processes belonged to the sibling worktree `feat-one-shot-12757-cron-gitconfig-containment`. Those hits are not a reason to stop planning, and this plan does not start a test run. No premise-blocker token is in the issue. The brainstorm of 2026-11-16 is the context for this plan.

`lane: cross-domain` is copied from `spec.md` at Save Tasks.

### Property List

1. On a child's `budget-capped` halt, a fresh context returns one verb the parent executes.
2. `continue` records `applied: not-run` and runs no unit, without clearing the latch or raising the cap.
3. `goto` moves the parent only to `plan`, `work`, `review`, `qa`, or `test-fix-loop`.
4. `fail` leaves today's halt and writes a readable on-disk ledger.
5. A missing or bad verb fails closed, and empty history does not spawn.
6. A second exhaustion does not spawn again.

### Cut List

- `init --max-*` as `continue`. It already exists and clears the latch (`capped-reset`). It buys a raised-cap resume, not property 2.
- A new sixth tally dimension. The grant is one consumed exemption on the existing latch.
- A new phase skill. The parent that already owns the phase list executes `goto`.
- Attaching at QA's prose retry, review's two-round prose cap, one-shot's own `agent_rounds` gate, or `test-fix-loop`'s max-iterations revert. Those stops do not have the attempt history this ruling reads.
- Folding #12532 per-run forensics into the ruling. That agent must not auto-apply.
- Replacing the three verbs with a fail-only report. That was CPO advice. The binding CTO ruling rejected it as a scope cut.

ADR-268 plus the one-shot `grep -q budget-capped` halt plus `write-budget-marker.sh`'s raised-cap resume line do not buy property 1. Nothing in a fresh context reads attempt evidence and returns one verb.

### External research

Skipped. ADR-268, `pipeline-tally.sh`, `stop-hook.sh`, and the skill halt sites are the local authority. Fetching the compared peer's repository is forbidden by the clean-room ceiling. No external URL is a source for the prompt, the ledger fields, or the tests.

### Deepen measurement

Measured 2026-11-17 on `plugins/soleur/skills/one-shot/SKILL.md` at 51968 bytes. The `one-shot` ceiling is still 52000. A search for `Read references/` across `plugins/soleur/skills/*/SKILL.md` returned no matches. The token-discipline line is a markdown link, and that link stays. The halt sites add the bare cue because a filename mention does not load a reference.

In `plugins/soleur/hooks/stop-hook.sh` the awk that rewrites the first frontmatter block writes a temp file and `mv`s it onto the ralph file. The tally floor calls `pipeline-tally.sh show` after that `mv`. On a cap it prints `SOLEUR_TALLY_CAPPED`, appends `budget-capped:`, and exits 0. Phase 2 moves `show` to before that awk. A capped stop whose grant line is absent keeps this exit. The grant path rewrites the line inside that same awk and reads the line back after the `mv` before it emits the keep-alive block.

### Community and functional discovery

Community discovery skipped. The worktree root has no `pubspec.yaml`, `Cargo.toml`, `mix.exs`, `go.mod`, `Package.swift`, `build.gradle`, or `composer.json` (checked 2026-11-16).

Functional discovery ran and returned skip-all. Registries responded. Do not install anything. The only trusted neighbor that is close is agent-harness (claudepluginhub.com, alirezarezvani, Verified, MIT): it loops execute and verify under retry caps and escalates to a human. It does not read an attempt ledger and it does not return exactly one of `continue`, `goto`, or `fail`. Installing it would not close either gap.

### CLI tokens

`pipeline-tally.sh` subcommands `init`, `show`, `gate`, `incr`, and `selfcheck` were read from that script's header on 2026-11-16. This plan does not change them. `--probe` is not an existing flag. It is the contract of the script this plan creates, and the observability probe below is that future command. It has not been run.

One-shot's `description:` line is not edited. The skill-description budget check is skipped.

Measured 2026-11-16: `plugins/soleur/skills/one-shot/SKILL.md` is 51968 bytes. The `one-shot` ceiling in `plugins/soleur/test/skill-body-budget.json` is 52000. Headroom is 32 bytes. `scripts/lint-skill-body-budget.py` rejects a ceiling raise unless that json file is the only path in the diff. This plan does not raise the ceiling. The ruling procedure goes in a reference file. Each halt site contains a leading space, then `Read references/retry-budget-ruling.md`, then a period A filename mention does not load the reference. Measured 2026-11-17: the cue without the space or the period is 38 bytes, one insertion is 40 bytes, and both sites are 80 bytes. Headroom is 32. The same edit deletes 56 bytes that are not conditions. Delete the second `dispose of it` in the prose-Ref bullet, including the space before those words (14 bytes), leaving `Dispose of it through`. Delete the parenthetical on the token-discipline Read whose text is `moved verbatim; byte-ceiling extraction`, including the space before the opening parenthesis (42 bytes). The Read target, `before Step 0`, and the following load-bearing sentence stay. Net is +24. When `wc -c` is still 51968 the file ends at 51992. Re-measure before editing. If that sum exceeds 52000, stop. Do not raise the ceiling, and do not pay by deleting a condition. Fitting the procedure by compressing it into the skill body drops conditions, so that is not the fit.

### Code anchors

- `plugins/soleur/skills/one-shot/SKILL.md` — the header tally contract and the tally note before steps 3, 4, 5.5, and 7 both `grep -q budget-capped` on the child's session state and halt. Step 0d gates `agent_rounds` and can stop before attempt history exists. That step is not the attachment.
- `plugins/soleur/hooks/stop-hook.sh` — the ralph file is `${GIT_COMMON_ROOT}/.claude/ralph-loop.${RALPH_LOOP_PID:-PPID}.local.md`. The stale-file sweep does not remove the current session's file before the grant read. If that file is absent after the sweep, the hook exits 0 before the tally floor. The tally floor prints `SOLEUR_TALLY_CAPPED`, appends `budget-capped:` to the ralph state file, and exits 0 with no `decision: block`. Today the awk rewrite above that floor persists iteration fields only and runs before `show`. This plan reads `show` first. A missing or empty rewrite exits 0. The grant line is written only inside the first frontmatter block of this existing file.
- `plugins/soleur/scripts/pipeline-tally.sh` — `incr` does not read the latch. `init` with any `--max-*` while latched is `capped-reset` and clears it. Bare `init` on a latched ledger is `continued capped=<dim>`. Do not edit this script so that `init --max-*` means the one-iteration grant.
- `plugins/soleur/scripts/write-budget-marker.sh` — the resume line stays the raised-cap halt. Do not edit it to mean `continue`.
- `plugins/soleur/test/ralph-loop.test.sh` — the no-block cases stay. They are the control arm for a capped hook with no grant.
- `plugins/soleur/scripts/pipeline-tally.test.sh` — locks `capped-reset`. This plan does not retune those tests.
- No `attempt-ledger` file and no verb parser exist under `plugins/soleur` or `knowledge-base` except the brainstorm, spec, and this plan.
- The git-lock marker drift guard walks `plugins/soleur/skills/*/scripts/*.sh` and the `echo "` / `printf '` forms in each skill's `SKILL.md`. It does not walk `plugins/soleur/scripts/*.sh`. `SOLEUR_RETRY_BUDGET_RULING` is printed by the new script. This plan does not edit `apps/web-platform/server/git-lock-marker-telemetry.ts` and does not add a hosted mirror.
- `scripts/test-all.sh` `SUITE_GLOBS` already includes `plugins/soleur/scripts/*.test.sh`. The new suite is covered by that glob, the same way `pipeline-tally.test.sh` is. This plan does not edit `scripts/test-all.sh`. A registration edit of that file is what degrades `--affected` to the full battery.

Writers of the `budget-capped` marker that this plan does not change: `test-fix-loop`, `review` (seat tally and fix-round seats), `work`, `ship`, `merge-pr`, `drain-labeled-backlog`, `eval-harness`, `resolve-pr-parallel`, `resolve-todo-parallel`, and `run-health-emit.sh` (a status enum, not this ruling). The parent grep and the stop-hook floor are the two consumers that change.

### Learnings that bound the design

- `2026-05-05-defense-relaxation-must-name-new-ceiling.md` — the ceiling is one pass, `capped=` stays set, the cap is not raised.
- `2026-09-18-the-measured-facts-my-resume-brief-handed-me-were-the-defects.md` — re-measure the child's marker from the run log.
- `workflow-patterns/2026-10-19-the-dedup-ledger-died-with-the-session-that-wrote-it.md` — write the second-exhaustion ledger to `session-state.md` at ruling time.
- `2026-11-08-a-strict-read-reached-one-of-two-role-providers-and-a-ruling-rested-on-a-count-that-counted-something-else.md` — the exhaustion count is the child's marker plus tally `show`, and the strict read applies to both `continue` and `goto`. The last `budget-capped` line whose dimension `show` still reports capped is the one that counts. An earlier line that `show` does not cap does not.
- `2026-10-28-a-branch-scoped-ledger-read-as-a-cwd-bug-from-the-wrong-checkout.md` — name toplevel, branch, and `git` common dir before any ledger read or write.
- `workflow-issues/2026-11-06-a-fixer-agent-that-says-waiting-has-not-reported-a-result.md` — a launcher exit 0 is not the halt. The ruling reads the log's marker.
- `2026-11-11-each-fix-round-found-the-next-sibling-until-the-test-stated-its-residuals.md` — the exemption leaves the excluded stops open.
- `2026-03-03-and-stop-halt-language-breaks-pipeline.md` — the inserted handoff must not say "and stop", "done", or "announce".
- `2026-05-07-one-shot-stops-on-review-summary-as-pseudo-handoff.md` — no heading-plus-Next-Steps block. A compact marker plus a continuation gate.
- `bug-fixes/2026-06-03-always-create-cron-turn-budget-exhaustion-drops-last-step-artifact.md` — write the ledger before the verb is acted on.
- `workflow-patterns/2026-10-29-shared-exemption-set-consumer-census-misses-untyped-parsers.md` — the marker's parsers are the census above. The set of verbs is `continue` and `goto`, which share one spawn exemption, plus `fail`.
- `workflow-issues/2026-10-14-a-gitignored-run-ledger-dies-with-its-worktree-so-keep-a-renamed-copy.md` — `session-state.md` under the feature spec directory is not gitignored. An uncommitted copy still dies with the worktree. Say that where it is written. Do not add a gitignored twin.
- `workflow-patterns/2026-11-01-followthrough-probes-need-one-wall-deadline-and-a-budget-sentinel.md` — the first cap stays `budget-capped`. The second exhaustion uses `reason=spent`.
- `2026-10-13-a-classifier-that-reads-absent-as-skip-fails-open-on-name-drift.md` — a missing verb, an absent marker, and an unknown line are `fail`. "Does not clear `capped=`" is measured.
- `2026-06-01-resumed-session-artifacts-from-contaminated-tool-layer-are-unverified.md` — re-derive the marker from the child's session state and from tally `show`.
- `2026-11-05-an-orphaned-pipeline-arm-is-silent-not-pending-and-session-state-is-the-rescue.md` — write `session-state.md` before the continuation.
- `workflow-issues/contradictory-oneshot-handoff-stops-pipeline-20260412.md` — do not put "do not clear the latch" in the same handoff sentence as the continue grant.

### gdpr-gate

Invoked at plan Phase 2.7 because the brand-survival threshold is `single-user incident` and the fresh-context spawn may send attempt history to the existing model path. The canonical path regex matched none of the planned files. The checklist stays in the session output and is not copied into this plan (ADR-026).

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| No attempt ledger and no verb parser exist. | Confirmed. The tally file stores counts, caps, and one `capped=` dimension. | Phase 1 adds the parser and the ledger write. |
| The parent halt does not read a verb. | One-shot greps the child's marker and halts. Step 0d can stop on `agent_rounds` with no history. | Phase 3 attaches only at the two child-marker greps. |
| One iteration is possible while the latch stays set, because `incr` does not read it. | The stop hook exits 0 with no keep-alive block while capped, so that iteration never runs. ADR-268 Consequences still say a capped run resumes only by raised caps or `--reset`. | Phase 2 teaches the hook one grant. Phase 4 amends ADR-268. The script does not call `init --max-*`. |

## Problem Statement / Motivation

A classified budget stop already halts the parent and writes a raised-cap resume line. The operator gets a stall, or a loop that cannot spend one more bounded iteration unless someone raises the cap. Raising the cap clears the latch. That is the opposite of this feature.

## Proposed Solution

A new script is the only verb parser. One-shot calls it when it is about to halt on a child's `budget-capped` marker. The script writes a ledger section to the feature `session-state.md` in the checkout that owns the counter, then prints one verdict line. The parent applies that line as Phase 3 states. It does not treat a shared exit status as the verb.

Checks run in this order: identity, then `ruling_spawn: used`, then `--not-capped`, then empty history, then stdin. An earlier check wins.

- `continue` runs no unit. The parent does not re-enter a child skill and does not start the next one-shot step, `ship`, or `merge`. It does not write `retry_budget_grant: 1`. The script records `spawn-line: continue`, `reason: not-run`, the exact line `applied: not-run`, and `ruling_spawn: used`, and it prints `verb=fail reason=not-run`. `capped=` stays set. The cap is not raised. A later halt is `reason=spent`.
- `goto` spends the same spawn exemption and names only `plan`, `work`, `review`, `qa`, or `test-fix-loop`. It does not write the ralph keep-alive bit. The parent re-enters that phase in the same turn only when the phase is earlier than the halt. `test-fix-loop` sits after step 5.5 and before step 7. It must not resume `ship` or `merge`.
- `fail`, an empty history, or an unparseable line keeps today's halt. Empty history does not spawn. A matching identity with empty history still appends one ruling section, and that section does not contain `ruling_spawn: used`.
- A call with non-empty history sets `ruling_spawn: used` before the parent acts, including when stdin is empty, unparseable, or `fail`. A later halt with that line is `fail` with no second spawn. The verb field records `goto` or `fail`. A continue spawn line is `spawn-line: continue` and is not the verb. The applied outcome is `applied: not-run` and the printed verb is `fail`. There is no `ruling_grant` bit. An identity mismatch writes nothing, so it does not set the spawn bit.

The spawn prompt is written from this spec and from Soleur's tally. It asks for one line. It does not use the words "and stop", "done", or "announce", and it does not emit a heading followed by a Next Steps block. It does not pair a prohibition on clearing the latch with the continue grant in one sentence. The latch stays set. A continue line is recorded as `applied: not-run` and is not a grant. Those facts live in the script and the reference, not in a contradictory handoff.

PR trailer, in the implementation PR body: derived from Soleur's ledger and this functional spec; zero peer source inspected.

## Implementation Phases

### Phase 1: Parser and ledger

Add `plugins/soleur/scripts/retry-budget-ruling.sh` and `plugins/soleur/scripts/retry-budget-ruling.test.sh`. Write the tests first.

The script:

- `--probe` prints `ok` and exits 0. It does not read a ledger, a tally, or a credential.
- Identity is first. The script refuses to write unless it was given the git toplevel, the branch, and the git common dir, and the ledger path's spec directory name is that branch. Otherwise it prints `verb=fail` with `reason=identity` and does not create or append a file. A failed identity does not set `ruling_spawn: used`. A missing session-state file is not an identity failure.
- A session-state file that already contains `ruling_spawn: used` is next, before history and before stdin. It prints `verb=fail` with `reason=spent` and does not append a section, including when history is empty and when stdin is `continue`.
- When identity matches and `--history` is missing or empty, including a missing session-state file at a matching path, the script prints `verb=fail` with `reason=empty-history` even if stdin is `continue`. It appends one `## Retry budget ruling` section that does not contain `ruling_spawn: used` and does not contain `ruling_grant`. It does not treat that call as a spawn. This check runs after the spent check and after `--not-capped`, so a spent ledger does not also get an empty-history section. A history path that is a symlink, or that is not a regular file under the toplevel, is this empty history.
- Stdin is last, and only when history is non-empty and `ruling_spawn: used` is absent. The script reads at most 64 bytes. One trailing LF is the line delimiter, so `continue` and `goto plan` with that single LF are accepted. A second line, a CR, a NUL, any other control byte, and any byte after the delimiter are `verb=fail` with `reason=unparseable`. The script does not trim spaces, strip quotes, or apply Unicode normalization. The accepted line is exactly `continue`, `fail`, or `goto` plus one of `plan`, `work`, `review`, `qa`, `test-fix-loop`. `goto ship` and `goto merge` are the same fail. The suite feeds four fixtures only when identity matches, `ruling_spawn: used` is absent, and history is non-empty: 256 KB of newlines, 256 KB of spaces, a repeated URL-scheme flood, and an unterminated comment. Each exits 2 with `verb=fail` and `reason=unparseable`, and the read stops at 64 bytes. A newline flood is not `reason=empty`.
- When history is non-empty, empty stdin, an unparseable line, and `fail` each append one section that contains `ruling_spawn: used` and does not contain `ruling_grant`. A spawn that returned no line is this empty-stdin case.
- Appends `## Retry budget ruling` to the ledger before it prints the verdict, except identity and spent, which write nothing. The section records only the fixed fields: branch, toplevel, git common dir, verb, phase, and reason, plus one path to the child session. It does not take a free-text evidence body. An extra evidence argument is not written.
- On `continue`, the section records `verb: fail`, `reason: not-run`, `spawn-line: continue`, `applied: not-run`, and `ruling_spawn: used`. On an allow-listed `goto`, and on `fail` after a non-empty history, the section includes `ruling_spawn: used` and does not contain `ruling_grant`. The verb field records `goto` or `fail`. On every verdict other than `goto`, `phase` is empty or one of `plan`, `work`, `review`, `qa`, `test-fix-loop`. `child-session` is empty, or one existing path under the toplevel that is not a symlink. The parent passes an empty value when the path is missing, a symlink, or outside the toplevel. A sentence, an email, a user id, a missing path, a symlink, or a path outside the toplevel is `reason=identity` and writes nothing. A trailing slash does not hide a symlink. `goto` still stores only the parsed token.
- Does not invoke `pipeline-tally.sh`. Does not spawn a process. Does not clear a `capped=` file.
- A failed append that already spawned prints `verb=fail reason=write-failed` and truncates that write back to the size from before it. That failure is not `reason=identity`. `reason=identity` stays the path refusal, before any append.
- Exit 0 only for an allow-listed `goto`, and only when history was non-empty. Exit 2 for `continue` (`verb=fail reason=not-run`) and for every other `fail`, and the fail line is still printed. When the stdin check is reached and stdin is empty, the reason is `empty`, the status is 2, and the section still records `ruling_spawn: used`. The script never exits 0 with no verdict line.

The verdict is one line: `SOLEUR_RETRY_BUDGET_RULING verb=<verb> reason=<reason>`. When the verb is `fail` and the reason is not `spent`, the script prints one additional plain line that names the verb and the reason. `reason=spent` prints the verdict line only and appends nothing. Today's stop-hook stderr stays as it is.

### Phase 2: One keep-alive grant

In `plugins/soleur/hooks/stop-hook.sh`, the ralph file is `${GIT_COMMON_ROOT}/.claude/ralph-loop.${RALPH_LOOP_PID:-$PPID}.local.md`. The hook exits 0 before the tally floor when that file is absent. Extend the existing awk rewrite of that file's first frontmatter block.

The stale-file sweep does not remove the current session's ralph file before the grant is read. Dead-owner cleanup of other sessions stays. If the current file is missing after that sweep, the hook exits 0 and emits no block.

The hook reads tally `show` before the awk pass. It reads `retry_budget_grant` from the first frontmatter block. Only the exact unquoted line `retry_budget_grant: 1` is a grant. A quoted 1, any other value, a 1 outside that block, and a missing field are not. A real ralph file has other digits. The read-back is that line, not a search for the character 0 or 1 anywhere in the file.

While the tally is capped:

- The grant line is not that exact unquoted 1: keep today's behavior. Print `SOLEUR_TALLY_CAPPED`, append the `budget-capped:` line, exit 0, no `decision: block`. Do not change the grant field.
- The grant line is that exact unquoted 1, and the first block does not already contain `retry_budget_consumed: 1`: in the same awk pass, rewrite the grant line to `retry_budget_grant: 0` and set `retry_budget_consumed: 1`. Never clear the consumed line in that pass. Emit the existing keep-alive block only when a read-back after the move shows the exact line `retry_budget_grant: 0`. If that line is anything else, the rewrite is empty, or the move fails: exit 0 and do not emit the block.
- While `retry_budget_consumed: 1` is in the first frontmatter block, do not emit another block even if the grant line is `1` again. The keep-alive turn does not write grant 1 again.
- The hook never writes the tally file and never clears `capped=`.

When the tally is not capped, the hook does not change the grant and does not take the capped halt. Today's non-capped keep-alive stays.

`plugins/soleur/test/ralph-loop.test.sh` gains the grant cases beside the existing no-block cases. Those no-block cases stay.

The parent does not write `retry_budget_grant: 1`. Exit 0 is an allow-listed `goto`, not `continue`. A `continue` line is `applied: not-run` in the same append as `ruling_spawn: used`. The parent runs no unit and does not invent a ralph file.

### Phase 3: Parent halt

The procedure below is the body of a new file, `plugins/soleur/skills/one-shot/references/retry-budget-ruling.md`. Edit the two child-marker halts in `plugins/soleur/skills/one-shot/SKILL.md`, the header tally contract and the tally note before steps 3, 4, 5.5, and 7, so each ends with a leading space, then `Read references/retry-budget-ruling.md`, then a period The same edit pays with the two deletions named in Research Insights. Do not edit step 0d. Do not edit the `description:` line. Do not delete the token-discipline Read target.

Measured 2026-11-16, and again 2026-11-17, `wc -c` of that skill is 51968 and the ceiling is 52000. Headroom is 32 bytes. The two insertions are 80 bytes and the two deletions are 56, so the net is +24 and the file ends at 51992 when the re-measure is still 51968. Re-measure before the edit. If the result exceeds 52000, stop. Do not raise the ceiling. Do not shorten the reference to fit the skill. `scripts/lint-skill-body-budget.py --base origin/main` exits 0 after the edit. The skill text does not contain `SOLEUR_RETRY_BUDGET_RULING`. The existing `SOLEUR_SESSION_STATE_UNAVAILABLE` echo stays.

Before any spawn, in this order, matching the script:

- Re-read the child's `budget-capped` lines and tally `show` from the checkout that owns the counter. The last line whose dimension `show` still reports capped selects the dimension. An earlier line that `show` does not cap does not select the dimension and does not force empty history.
- Resolve git toplevel, branch, and git common dir. If they do not match the ledger path, do not spawn. The script prints `reason=identity` and writes nothing.
- If session-state already contains `ruling_spawn: used`, call the script and do not spawn. The verdict is `reason=spent` and the script appends nothing. Do not also write an empty-history section.
- If `show` is readable and no line is selected, pass `--not-capped` and do not spawn. The verdict is `verb=fail reason=not-capped`. The section does not contain `ruling_spawn: used`. Do not label that `empty-history`.
- If `show` is missing or `UNKNOWN`, or history is missing or empty, pass empty history and do not spawn. A history path that is a symlink, or that is not a regular file under the toplevel, is empty history. This check is after `--not-capped`. Do not spawn before it.
- Otherwise spawn one fresh context and feed it the attempt history. The call is the blank spawn the reference names for this harness. The prompt's first line is `Rule on this technical question. Do NOT use AskUserQuestion.` Do not pass a registered Soleur agent id. If that call is rejected, do not invent a line and do not spawn a Soleur agent. Pipe its stdout, including no line, to the script. The ledger arguments are the fixed fields plus one path to the child session. Do not pass a free-text evidence body. The spawn does not increment the dimension named on the child's marker.

The parent then applies the printed verb.

- `continue`: the parent runs no unit. It does not re-enter a child skill and does not start the next one-shot step, `ship`, or `merge`. Do not write `retry_budget_grant: 1` and do not write the compact marker `retry-budget-ruling: verb=continue`. The script prints `verb=fail reason=not-run` and writes `applied: not-run` and `ruling_spawn: used` in that same append. A later halt is `reason=spent`.
- `goto`: write no ralph bit. In the same turn, re-enter only a phase that is earlier than the halt boundary. `plan` is steps 1–2. `work` is step 3. `review` is step 4. `qa` is step 5.5. `test-fix-loop` sits after step 5.5 and before step 7: Read `plugins/soleur/skills/test-fix-loop/SKILL.md` and run that skill. A halt before step 7 may enter it and must not enter step 7 or step 8. A halt at step 3, step 4, or step 5.5, or earlier, treats `goto test-fix-loop` as not earlier: the parent halts and does not start that skill. The script has no `not-earlier` reason and does not receive the halt boundary. Do not resume `ship` or `merge`. A `goto` that is not earlier than the halt boundary halts. The sticky `budget-capped` line does not start another ruling until that action has started. The compact marker is `retry-budget-ruling: verb=goto phase=` followed by the allow-listed name.
- `fail`: today's halt. When the reason is not `spent`, the script has already printed the verdict line and one plain line that names the verb and the reason. `reason=spent` prints the verdict line only and appends nothing. The ledger section for a first fail is already written.

The continuation marker is not a section heading. It must not say "and stop", "done", or "announce".

### Phase 4: ADR-268 and C4 descriptions

Amend `knowledge-base/engineering/architecture/decisions/ADR-268-pipeline-tally-per-branch-counters.md` Consequences. The capped halt stays durable. Raised caps and `--reset` remain the way to clear `capped=`. A `continue` ruling records `applied: not-run` and runs no unit, while `capped=` stays set and the cap is not raised. `goto` may move the parent to an allow-listed earlier phase. A second exhaustion is `fail` with no second spawn. `init --max-*` remains `capped-reset` and is not that record.

Amend two descriptions in `knowledge-base/engineering/architecture/diagrams/model.c4`, and no other element:

- The plugin system sentence that says `hooks/stop-hook.sh` reads `capped` as a hard-cap floor. State that the floor still holds. A continue ruling records `applied: not-run` and runs no unit, without clearing the latch and without a ralph keep-alive grant.
- The `oneshot` component description. State that a child `budget-capped` marker is read by the ruling before the parent halts, and that continue is recorded as `applied: not-run` and does not write a ralph grant.

Do not add an actor, a system, a container, a database, or a `views.c4` include. `spec.c4` needs no new kind. Do not edit edge sentences that carry cardinalities. Run `plugins/soleur/test/c4-count-parity.test.sh` after the description edit.

The implementation PR body carries the clean-room trailer from the Proposed Solution. The new script and the hook must not name the compared peer.

## Technical Considerations

- `continue` is recorded as `applied: not-run` and runs no unit. It is not a pass. Clearing `capped=` would dissolve the cap's other job. The latch, the cap, the next `gate` STOP, and the second-exhaustion `fail` stay in force.
- `goto` and `continue` share `ruling_spawn: used`. They do not share the ralph keep-alive bit. Sharing that bit would continue the exhausted loop and also change phase.
- Tally `show` is read before the awk pass. The grant line is read from the first frontmatter block before it is rewritten. The block is emitted only when that same line is exactly `retry_budget_grant: 0` after the move. Emitting because some other character in the file is 0, or because the replacement file is non-empty, would keep the loop alive when the grant was absent. Emitting while `retry_budget_consumed: 1` is already set would livelock if a later turn wrote grant 1 again.
- A runtime write to `session-state.md` is not a planned source edit. The file is not gitignored. An acceptance check that lists the implementation diff names the planned files. It does not treat that runtime ledger as one of them, and it does not claim the diff is only the planned files while omitting a ledger the PR also commits.
- The ledger file is the feature `session-state.md` already used by `write-budget-marker.sh`. Lifetime: it is a normal spec file, not gitignored, and an uncommitted copy is lost if the worktree is removed before commit. The write happens before the parent acts, in the toplevel whose branch matches the spec directory.
- No product NFR in `knowledge-base/engineering/architecture/nfr-register.md` names this tally. This plan does not change a latency, availability, or data-residency NFR.
- Encryption posture and Task Design do not fire. The ledger is the existing spec file, not a new store or a new network connection. No new workflow, timer, or Inngest function is created.
- Infrastructure-as-code does not fire. Nothing is provisioned.
- One-shot `description:` is unchanged.

### Attack surface

The new parser is a trust boundary for a model-written line. The only acceptance path is the script's one-line grammar. One-shot must not decide the verb by reading prose. The stop hook must not treat a model sentence as a grant. The parent does not write `retry_budget_grant: 1`. A spawn line `continue` is recorded as `applied: not-run` with verb `fail`. A model that prints `continue` twice, or prints `goto ship`, becomes `fail` at the script. The script does not receive a shell to execute.

Unchecked on purpose: every other skill that writes `budget-capped` still halts as it does today. They are safe because the parent is the only reader that executes a verb, and this plan does not add a verb reader to those skills.

## Files to Edit

- `plugins/soleur/skills/one-shot/SKILL.md` — the two child-marker halts, each ending with a leading space, then `Read references/retry-budget-ruling.md`, then a period The same edit deletes the duplicated `dispose of it` in the prose-Ref bullet and the token-discipline parenthetical `moved verbatim; byte-ceiling extraction`, including the space that precedes each. Not step 0d. Not the `description:` line. The token-discipline Read target stays. Net bytes stay inside the 52000 ceiling.
- `plugins/soleur/hooks/stop-hook.sh` — one grant in the existing awk rewrite and the tally floor.
- `plugins/soleur/test/ralph-loop.test.sh` — grant cases beside the existing no-block cases.
- `knowledge-base/engineering/architecture/decisions/ADR-268-pipeline-tally-per-branch-counters.md` — Consequences amendment.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — plugin-system description and the `oneshot` component description.

## Files to Create

- `plugins/soleur/scripts/retry-budget-ruling.sh`
- `plugins/soleur/scripts/retry-budget-ruling.test.sh`
- `plugins/soleur/skills/one-shot/references/retry-budget-ruling.md`

## User-Brand Impact

Carried forward from the 2026-11-16 brainstorm. The artifact is the retry-budget ruling. The vector is a wrong ruling that silently continues a broken loop, or stops a fix, with no readable reason.

- **If this lands broken, the user experiences:** the retry-budget ruling continues a broken loop, or stops a fix, with no readable ledger.
- **If this leaks, the user's workflow is exposed via:** personal data, a users foreign key, or customer content in the ledger.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one wrong ruling on one run is the incident. The artifact is the ruling itself.

`requires_cpo_signoff: true`. The brainstorm CPO review does not discharge plan-time sign-off. The plan-review CPO advisory on 2026-11-16 is the ack: keep the three verbs, and do not hold implementation for a second CPO review. Fail-only stays recorded dissent. `soleur:engineering:review:user-impact-reviewer` runs at review time.

A plan whose User-Brand Impact section is empty, contains only placeholder text, or omits the threshold will fail deepen-plan Phase 4.6.

## Observability

```yaml
liveness_signal:
  what: "stdout line SOLEUR_RETRY_BUDGET_RULING on each ruling, and ok from --probe"
  cadence: per-run
  alert_target: "the operator session stdout. No Sentry project. Harness-local."
  configured_in: plugins/soleur/scripts/retry-budget-ruling.sh
error_reporting:
  destination: "stdout marker, not Sentry"
  fail_loud: "SOLEUR_RETRY_BUDGET_RULING verb=fail reason=unparseable"
failure_modes:
  - mode: "parser prints no verb line"
    detection: "retry-budget-ruling.test.sh asserts a verb= line on empty stdin"
    alert_route: "the plugin test run in CI"
  - mode: "stop hook emits a second keep-alive while capped"
    detection: "ralph-loop.test.sh asserts the second invocation prints SOLEUR_TALLY_CAPPED and no decision block"
    alert_route: "the plugin test run in CI"
  - mode: "fail returns before the ledger section exists"
    detection: "retry-budget-ruling.test.sh asserts the ruling section is in the fixture before the process exits"
    alert_route: "the plugin test run in CI"
logs:
  where: "command stdout and the feature session-state.md Retry budget ruling section"
  retention: "session-state.md is a spec file and is not gitignored. An uncommitted copy lasts while the worktree does."
discoverability_test:
  command: bash plugins/soleur/scripts/retry-budget-ruling.sh --probe
  expected_output: "ok"
```

## Guard Contract

### Guard 1 — verb parser

**Property.** The parser accepts exactly one line that is `continue`, `fail`, or `goto` plus one allow-listed phase. One trailing LF is the delimiter and is accepted. Every other input, including empty input, a second line, and a control byte other than that delimiter, is `fail`.

**Assembly.** The only chokepoint is `plugins/soleur/scripts/retry-budget-ruling.sh` reading stdin. One-shot executes the printed verdict and does not parse the verb itself. There is no second parser.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Stdin is `continue please` | RED |
| 2 | Stdin is empty and the script exits 0 with no verb line | RED |
| 3 | Stdin is `continue` followed by a second line `goto plan` | RED |
| 4 | Stdin is `goto ship` | RED |
| 5 | Stdin is exactly `continue` and the script clears a fixture `capped=` | RED |
| 6 | Delete the suite assertion that the verb line exists and assert only the exit status | RED |
| 7 | Stdin is `goto plan` followed by one LF | PASS |
| 8 | Stdin is exactly `fail` | PASS |
| 9 | Identity does not match, stdin is `continue`, and the script writes a section | RED |
| 10 | History is empty, stdin is `continue`, and the script prints `verb=continue` | RED |
| 11 | The ledger already has `ruling_spawn: used`, stdin is `continue`, and the script appends a section | RED |
| 12 | Stdin is 256 KB of newlines and the script reads past 64 bytes, reports reason=empty, or exits 0 | RED |

### Guard 2 — one keep-alive grant

**Property.** While the tally is capped, the stop hook emits the keep-alive block at most once, only after the first-frontmatter grant line was exactly `retry_budget_grant: 1` and a read-back of that same line is exactly `retry_budget_grant: 0`. While `retry_budget_consumed: 1` is in that block, a later grant 1 emits no block. The hook never clears `capped=`. A stop that is not capped does not change the grant.

**Assembly.** The only chokepoint is the tally floor in `plugins/soleur/hooks/stop-hook.sh`, after the awk rewrite of the ralph state file. The grant field flows only through that rewrite. There is no second emit site.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Capped, grant field absent, and the hook emits `decision: block` | RED |
| 2 | Grant is 1, the awk rewrite is empty, and the hook emits the block | RED |
| 3 | The first frontmatter contains retry_budget_consumed: 1, the grant line is 1 again, and the hook emits another block | RED |
| 4 | The block is emitted and only then is the grant rewritten to 0 | RED |
| 5 | Capped, the block is emitted, and the fixture `capped=` is cleared | RED |
| 6 | Delete the suite's no-grant assertion that the existing test names | RED |
| 7 | The grant line is exactly retry_budget_grant: 1, the capped dimension is fix_rounds, the read-back line is exactly retry_budget_grant: 0, one block is emitted, and capped= is unchanged | PASS |
| 8 | Grant is absent and the capped dimension is `seats` | PASS |
| 9 | After the move the first-frontmatter grant line is not exactly retry_budget_grant: 0, and the hook emits the block | RED |
| 10 | The tally is not capped, the grant is 1, and the hook rewrites it to 0 | RED |
| 11 | The grant line is a quoted 1 and the hook emits the block while capped | RED |
| 12 | The ruling script exits 0 on `goto plan` and the parent writes `retry_budget_grant: 1` | RED |

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-268. Do not open a new ADR. The Consequences change is Phase 4. The ordinal stays 268. Status stays the ADR's current accepted status. The continue record is `applied: not-run`. It extends the classified stop and does not reverse the latch.

### C4 views

Read at plan time: `model.c4`, `views.c4`, and `spec.c4`.

- External human actors already modeled: founder, emailSender, betaContact, contributor, publicReader, supportUser. None gain a relationship. No new actor.
- External systems already modeled include the harness surfaces the plugin already runs on. No new vendor, webhook, or store.
- No new container or database. The ledger is the same class of machine-local repo state as the tally counters already described on the plugin system.
- The access relationship that changes is descriptive: a continue ruling records `applied: not-run` and runs no unit. The plugin description names that record. The `oneshot` description names the child-marker ruling. Both edits are in Phase 4. The hook still emits one keep-alive only when a file already contains the exact grant line. A conforming parent does not write that line.
- `views.c4` already includes `platform.plugin` and `platform.plugin.oneshot`. No new include.
- `spec.c4` element kinds stay actor, system, container, database, and component. Tags stay `external` and `selfhosted`. No new kind.
- `plugins/soleur/test/c4-count-parity.test.sh` is the cardinality gate. A description edit can fail it. The edit must not change counted cardinalities, and the test is run after the edit.

### Sequencing

The amendment is true when this change lands. It is not soak-gated and it is not a follow-up issue.

## Open Code-Review Overlap

None. On 2026-11-16, 96 open issues labeled `code-review` were searched for each path then listed in Files to Edit and Files to Create. No body contained any of those paths. A later search for `retry-budget-ruling` returned no open code-review issue. The reference file added after that census is a new path and was not in an issue body.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "spawn a fresh-context agent fed the attempt ledger (checkpoint diffs, failure reasons, gate outputs) whose output is one of three machine-readable verbs consumed by the orchestrating skill." | Phase 1, Phase 3, `retry-budget-ruling.sh`, `one-shot/SKILL.md` | mapped |
| 2 | "decides `continue` / `goto <phase>` / `fail`" | Phase 1 verb grammar, Phase 2 `continue` grant, Phase 3 `goto` routing | mapped |
| 3 | "When a Soleur loop (test-fix-loop, review fix-rounds, qa, one-shot phases) exhausts its retry budget, the run surfaces to the operator or stalls — no agent reads the attempt history and makes an evidence-based call." | — | descoped — justification: Ruled by CTO agent, 2026-11-16, Decision C. The evidence-based call in this sentence is row 1, attached only where one-shot halts on a child's marker. test-fix-loop's max-iterations revert, review's two-round prose cap, QA's three-try prose retry, and one-shot's own agent_rounds gate stay excluded. A review seat stop is in scope only after that seat has written the child marker row 1 consumes. |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| Phase 1 parser and ledger | "spawn a fresh-context agent fed the attempt ledger (checkpoint diffs, failure reasons, gate outputs) whose output is one of three machine-readable verbs consumed by the orchestrating skill." | asked |
| Phase 2 stop-hook grant | — | inferred — justification: `continue` cannot run one iteration while the hook exits 0 with no keep-alive block. The grant is the enforcement of the classified stop, not a new ask. |
| Phase 3 one-shot parent halt | "whose output is one of three machine-readable verbs consumed by the orchestrating skill." | asked |
| Phase 4 ADR-268 amendment | — | inferred — justification: ADR-268 Consequences still say a capped run resumes only by raised caps or `--reset`. Shipping the grant without amending that sentence leaves the ADR contradicting the code. |
| Phase 4 model.c4 descriptions | — | inferred — justification: the plugin description says the hook reads `capped` as a hard-cap floor, and the oneshot description does not mention a ruling. Both become false by omission when the grant lands. |
| `plugins/soleur/skills/one-shot/SKILL.md` | "consumed by the orchestrating skill." | asked |
| `plugins/soleur/hooks/stop-hook.sh` | — | inferred — justification: same enforcement contract as Phase 2. The hook is the keep-alive chokepoint. |
| `plugins/soleur/test/ralph-loop.test.sh` | — | inferred — justification: the existing no-block tests lock the floor. The one-grant case has to land beside them or those tests forbid the grant. |
| `plugins/soleur/scripts/retry-budget-ruling.sh` | "three machine-readable verbs" | asked |
| `plugins/soleur/scripts/retry-budget-ruling.test.sh` | — | inferred — justification: Guard 1's mutation matrix has to execute in a suite. A parser with no RED rows is vacuous. |
| `plugins/soleur/skills/one-shot/references/retry-budget-ruling.md` | — | inferred — justification: one-shot SKILL.md is 51968 bytes against a 52000 ceiling, measured 2026-11-16. The procedure cannot be inlined, and the linter rejects a ceiling raise on a diff that also edits the skill. The reference holds the conditions so they are not compressed away. |
| ADR-268 file | — | inferred — justification: same as Phase 4. The decision record is a deliverable of this plan. |
| `model.c4` | — | inferred — justification: same as the C4 description row. The cardinality test is the check that the prose edit did not move a count. |
| PR trailer sentence | — | inferred — justification: CLO advisory guardrail. The diff must say it was derived from Soleur's ledger and this spec, with zero peer source inspected. |

### Split Assessment

- Subsystems touched: 2 — `plugins/soleur`, `knowledge-base`
- Planned files: 8 | Estimated changed lines: 780
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md -->

- [x] `bash plugins/soleur/scripts/retry-budget-ruling.sh --probe` prints `ok` and exits 0.
- [x] When history is non-empty and stdin is empty, stdout is `SOLEUR_RETRY_BUDGET_RULING verb=fail reason=empty`, the status is 2, and the appended section contains `ruling_spawn: used` and does not contain `ruling_grant`.
- [x] When identity matches, history is non-empty, and the spawn bit is absent, stdin `continue` prints `verb=fail reason=not-run`, status 2, and the section contains `spawn-line: continue` and `applied: not-run`. The parent runs no unit. A fixture `capped=` stays unchanged. The script does not invoke `pipeline-tally.sh`. A single trailing LF on that line is accepted. `continue` stays a parser token.
- [x] Stdin `goto plan` followed by one LF prints `verb=goto` when history is non-empty. Stdin `goto ship`, a two-line stdin, a CR, a NUL, and any byte after the delimiter print `verb=fail` with `reason=unparseable`.
- [x] When the toplevel, branch, or git common dir does not match the ledger path, the script prints `verb=fail reason=identity`, does not create or append a file, and the parent does not spawn.
- [x] When identity matches and history is empty, stdin `continue` still prints `verb=fail reason=empty-history`. The script appends one ruling section that does not contain `ruling_spawn: used` and does not contain `ruling_grant`. The parent does not spawn. A ledger that already contains `ruling_spawn: used` does not take this path.
- [x] A ledger that already contains `ruling_spawn: used` prints `verb=fail reason=spent` and appends nothing, including when history is empty and when stdin is `continue`.
- [x] When history is non-empty and stdin is unparseable or `fail`, the script prints `verb=fail` and appends one section that contains `ruling_spawn: used` and does not contain `ruling_grant`.
- [x] The ledger section written for a non-empty history contains only the fixed fields and one path to the child session. An extra evidence argument is not written.
- [x] `continue` and an allow-listed `goto` append `ruling_spawn: used` and do not append `ruling_grant`. `continue` records `verb: fail`, `reason: not-run`, `spawn-line: continue`, and `applied: not-run`. `goto` records `verb: goto`.
- [x] When identity matches, `ruling_spawn: used` is absent, and history is non-empty, a fixture of 256 KB of newlines, of 256 KB of spaces, of a repeated URL-scheme flood, and of an unterminated comment each makes the script exit 2 with `verb=fail` and `reason=unparseable`, and the script stops reading stdin at 64 bytes. A newline flood is not `reason=empty`.
- [x] When tally `show` is missing or `UNKNOWN`, the parent passes empty history and does not spawn. The last `budget-capped` line whose dimension `show` still reports capped selects the dimension. An earlier line that `show` does not cap does not select the dimension and does not force empty history. When `show` is readable and no line is selected, the parent passes `--not-capped`, does not spawn, and the script prints `verb=fail reason=not-capped` with one section that does not contain `ruling_spawn: used`.
- [x] With the tally capped and no grant, `stop-hook.sh` still prints `SOLEUR_TALLY_CAPPED` and does not emit `decision: block`. The existing ralph-loop cases that lock this stay in the file.
- [x] The hook reads tally `show` before the awk pass. While the tally is capped, only the exact unquoted line `retry_budget_grant: 1` in the first frontmatter block arms the hook. The same pass rewrites that line to `retry_budget_grant: 0` and sets `retry_budget_consumed: 1`. The hook emits one `decision: block` only when a read-back of that same line is exactly `retry_budget_grant: 0`. A quoted 1, a 1 outside the first block, any other read-back line, an empty rewrite, and a failed move emit no block. While `retry_budget_consumed: 1` is set, a later grant 1 emits no block. The tally `capped=` value is unchanged. The stale-file sweep does not remove the current session file before that read. If the current file is missing after the sweep, the hook exits 0 with no block.
- [x] A stop that is not capped does not change the grant and does not take the capped halt.
- [x] On `continue`, the parent runs no unit. It does not write `retry_budget_grant: 1`, so the stop hook does not emit the keep-alive block. It does not write the compact marker `retry-budget-ruling: verb=continue`. The script writes `applied: not-run` in the same append as `ruling_spawn: used`. The parent does not invent a ralph file. `goto` does not write a ralph bit.
- [x] On `continue`, the reference says the parent runs no unit. That is not a child re-entry, and it is not the next one-shot step, `ship`, or `merge`. The reference does not tell the parent to write `retry_budget_grant: 1`. It does not tell the parent to write a continue compact marker. A later halt is `reason=spent`.
- [x] On `goto`, the reference sends the parent, in the same turn, to an earlier phase only: `plan` at steps 1–2, `work` at step 3, `review` at step 4, `qa` at step 5.5, and `test-fix-loop` after step 5.5 and before step 7. A halt before step 7 may enter `test-fix-loop` and must not enter step 7 or step 8. A halt at step 3, step 4, or step 5.5, or earlier, does not start `test-fix-loop`. The script has no `not-earlier` reason. A `goto` that is not earlier halts. The text does not send `goto` to step 7, step 8, `ship`, or `merge`. The sticky marker does not start another ruling until that action has started.
- [x] When the verb is `fail` and the reason is not `spent`, stdout is the verdict line plus one plain line that names the verb and the reason. When the reason is `spent`, stdout is the verdict line only and the script appends nothing.
- [x] One-shot's two child-marker halts each contain `Read references/retry-budget-ruling.md`. That reference names the ruling script. Step 0d does not. The same edit deletes the duplicated `dispose of it` and the token-discipline parenthetical `moved verbatim; byte-ceiling extraction`, and it keeps that Read target. `wc -c` of `plugins/soleur/skills/one-shot/SKILL.md` is at most 52000, and `scripts/lint-skill-body-budget.py --base origin/main` exits 0. The skill body does not contain `SOLEUR_RETRY_BUDGET_RULING`. The existing `SOLEUR_SESSION_STATE_UNAVAILABLE` echo stays.
- [x] `scripts/test-all.sh` is not edited. The new suite path is `plugins/soleur/scripts/retry-budget-ruling.test.sh`.
- [x] ADR-268 Consequences state that a `continue` ruling records `applied: not-run` and runs no unit, does not clear `capped=`, and is not `init --max-*`. The raised-cap and `--reset` resume paths remain. That record is not a consumed ralph grant.
- [x] `model.c4` plugin description names that `applied: not-run` record, and the `oneshot` description names the child-marker ruling and the same record. `plugins/soleur/test/c4-count-parity.test.sh` passes.
- [x] The new script and `stop-hook.sh` do not contain the compared peer's repository name.

## Domain Review

**Domains relevant:** Product, Legal, Engineering, Marketing

Carried forward from the 2026-11-16 brainstorm. Those leaders are not re-spawned. No brainstorm assessment named a later specialist.

**Brainstorm-recommended specialists:** none beyond the domain leaders already consulted.

**Product/UX tier:** NONE. Files are a skill, a hook, scripts, an ADR, and two C4 description sentences. `ui-surface-terms.md` excludes orchestration. The mechanical UI glob does not match. No Product/UX Gate subsection.

### Product

**Status:** reviewed
**Assessment:** The brainstorm CPO review does not discharge plan-time sign-off. The plan-review CPO advisory on 2026-11-16 grants that ack and says not to hold implementation for a second CPO review. Fail-only stays recorded dissent beside the binding CTO ruling, which kept the three verbs. This stays internal orchestration. Do not productize a customer surface. `user-impact-reviewer` runs at review time.

### Legal

**Status:** reviewed
**Assessment:** CLO advisory, 2026-11-16. Permitted with guardrails. Draft, not legal advice. Not a CLO ruling line. Ceiling is the three outcome words and Soleur's own ledger. No legal-doc edit, no Article 30 row, no NOTICE edit, no `TC_VERSION` bump. Ruled by CLO agent, 2026-11-19. Draft, not legal advice. Absolute git toplevel and git common dir may stay when `git rev-parse` does not name a natural person. Non-goto phase is an allow-listed token or empty. Child-session is empty or one path under the toplevel. No Article 30 row, no NOTICE edit, and no compliance-posture.md sentence. Re-open if `git rev-parse` on the operator host starts returning a path that names a natural person. PR trailer as in Proposed Solution.

### Engineering

**Status:** reviewed
**Assessment:** Ruled by CTO agent, 2026-11-16. Decision A: one shared exemption, latch and cap stay. Decision C: first attachment is the parent halt on a child's marker. Amended by the CTO on 2026-11-17: on continue the one iteration is the in-process unit, then stop, and the parent does not write a ralph grant. Amended again by the CTO on 2026-11-19: there is no legal in-process unit, so continue is recorded as `applied: not-run` and the parent runs nothing. A readable show with no selected line is `reason=not-capped` and does not spawn. Ruled by CLO agent, 2026-11-19: absolute git toplevel and git common dir may stay; non-goto phase is an allow-listed token or empty; child-session is empty or one path under the toplevel.

### Marketing

**Status:** reviewed
**Assessment:** Out of scope. Do not claim this ships the compared peer. Do not adopt that peer's unattended-autopilot line as public positioning.

## Test Scenarios

- unit: Given empty stdin, when the ruling script runs, then stdout contains `verb=fail reason=empty` and the status is 2.
- unit: Given stdin `goto plan`, when the script runs, then stdout contains `verb=goto` and the status is 0. Given stdin `goto ship`, then `verb=fail`.
- unit: Given stdin `continue` and a fixture tally with `capped` set, when the script runs, then the fixture `capped` value is unchanged and the script's source contains no `pipeline-tally.sh` invocation.
- unit: Given an extra evidence argument, when the script writes the ledger, then that argument is absent and the section has only the fixed fields plus one child-session path.
- unit: Given a ledger that already contains `ruling_spawn: used`, when the script runs, then the verdict is `reason=spent` and the ruling heading occurs once.
- unit: Given a capped tally and no grant, when the stop hook runs, then stderr contains `SOLEUR_TALLY_CAPPED` and stdout has no `decision` block. This is the existing control arm.
- unit: Given a capped tally and the exact line `retry_budget_grant: 1`, when the hook runs and the read-back line is exactly `retry_budget_grant: 0`, then one `decision` block is emitted and `retry_budget_consumed: 1` is set. When that read-back line is anything else, then no block is emitted.
- unit: Given grant 1 and a tally that is not capped, when the hook runs, then the grant field is unchanged and the capped halt is not taken.
- unit: Given the exact grant line and capped dimension `fix_rounds`, when the hook runs and the read-back line is exactly `retry_budget_grant: 0`, then one block is emitted and `capped=` is unchanged.
- unit: Given `retry_budget_consumed: 1` already set and grant 1 again, when the hook runs while capped, then no decision block is emitted.
- unit: Given stdin `continue` followed by one LF and non-empty history, when the script runs, then the status is 2, stdout contains `verb=fail reason=not-run`, and the section contains `spawn-line: continue` and `applied: not-run` and does not contain `verb: continue`. Given a CR or a second line, then `verb=fail` and `reason=unparseable`.
- unit: Given 256 KB of newlines on stdin when identity matches, the spawn bit is absent, and history is non-empty, when the script runs, then the status is 2, the reason is `unparseable`, and the read stops at 64 bytes.
- unit: Given stdin `continue` and non-empty history, when the script runs, then the ruling section contains `applied: not-run` and `ruling_spawn: used`, stdout is `verb=fail reason=not-run`, and the parent runs no unit.
- unit: Given stdin `fail` and non-empty history, when the script runs, then stdout has the verdict line and one plain line that names fail. Given a ledger that already contains `ruling_spawn: used`, then stdout is the verdict line only.
- integration: Given one-shot's skill text, when the two child-marker halt sites are read, then each points at the ruling reference, step 0d does not, and the file is at most 52000 bytes.

No end-to-end browser scenario. This change has no page.

## Success Metrics

- A capped child marker produces one parsed verdict line and one ledger section.
- A second halt on the same run produces `reason=spent` and no second spawn.
- The no-grant stop-hook tests still pass, so a capped loop without a grant still halts.

## Dependencies & Risks

- The stop-hook rewrite is the riskiest phase. Emitting the block when the first frontmatter line is not exactly `retry_budget_grant: 0`, emitting it because some other digit in the file is 0, emitting another block after `retry_budget_consumed: 1` is set, or clearing `capped=`, reopens the livelock ADR-268 closed. A sticky `budget-capped` line that starts a second ruling after `ruling_spawn: used` is `reason=spent`. Recording `verb: continue` as the applied outcome would claim a pass that did not run.
- A handoff that says "and stop", "done", or "announce", or that uses a Next Steps heading, makes one-shot treat the continuation as a finished handoff.
- Writing the ledger from the wrong checkout records another branch's numbers. The identity check is the mitigation.
- The clean-room ceiling is the three verbs. The implementer does not open the peer repository. If a session has already read that source, a different author writes the prompt.
- CPO's fail-only advice remains dissent. Dropping a verb is an operator scope cut and is not applied in this plan.

## References & Research

- Issue #12526, epic #12533, draft PR #12815.
- Brainstorm `knowledge-base/project/brainstorms/2026-11-16-retry-budget-arbitration-brainstorm.md`.
- Spec `knowledge-base/project/specs/feat-12526-retry-budget-arbitration/spec.md`.
- Decisions `knowledge-base/project/specs/feat-12526-retry-budget-arbitration/decision-challenges.md`.
- ADR-268 `knowledge-base/engineering/architecture/decisions/ADR-268-pipeline-tally-per-branch-counters.md`.
- Related tally work already shipped: #9403. Forensics #12532 stays a non-goal. Run-health emission #12573 and #12574 stay outside this ruling.
