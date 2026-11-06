# Learning: a guard-shaped PR passed an eight-seat review with no P1, and its fixes still needed two more rounds

## Problem

PR #11542 added the read-only `ci-head-verdict.sh required <pr>` subcommand, which closes the gap where a green `verdict` plus an armed auto-merge does not prove every ruleset-required context reported on the head. The first implementation was green on its own suite (143 passed, 86/86 mutants killed). The eight-seat review found no P1 and about 49 P2/P3 items. Applying those fixes produced a second review round that found two P2s inside the fixes themselves, and a verification pass that found four P3s.

## Solution

- Delegated the implementation, the first fix batch and the second fix batch to one fix agent each, with a persisted fix brief (`<git-dir>/review-fix-brief.md`) naming every item by ID.
- Reviewed the first fix range with four targeted seats (security, test-design, code-quality, agent-native) instead of the full eight, and said so in the evidence comment.
- Ran exactly one verification pass over the second fix range, and re-ran the suites myself against the pushed HEAD each time, reading the rc from its own line.
- Settled the one AC the delegate reported as covered by running its literal command (QA found it failing).

## Key Insight

1. **A fix batch is where the next defects are.** The first fix batch added control-character handling whose set was only half pinned (the mutants dropping DEL, U+2029, or moving the C1 bound all survived) and a hermetic-RE6 test that was not hermetic (an outer `ADMIN_MERGE_READY_BIN` could make it pass with the production default path broken). Both were caught only because the fix range got its own targeted review. A clean first panel says the original diff is sound; it says nothing about the fixes it prompted.
2. **A summary count is not a pin.** Delegates reported "all items DONE" with matching suite totals both times; the review of the fix range still found surviving mutants. Re-drive the specific mutants the previous round named.
3. **An AC literal can fail on spelling while the behaviour is right.** AC13 greps for `ci-head-verdict.sh required`; the doc only showed `"${CLAUDE_PLUGIN_ROOT}/scripts/ci-head-verdict.sh" required PR_NUMBER`. The delegate had ticked it. Running the literal at QA is what caught it.
4. **Delegates that run long suites stop on a status line.** Three agents ended a turn with "waiting for my background watcher". Nothing resumes them unless you do (`SendMessage`), and the worktree can hold uncommitted work meanwhile.
5. **The ruling gate reads the shape of a technical row.** Planner rows written as "Applied by the planner under the CTO's standing ruling" fail `technical-ruling-gate.sh`; a batched CTO spawn rewrote seven in one pass and all of the planner's choices stood.

## Session Errors

1. **Forwarded from planning: hook-refused `gh issue create`, and a 77-of-343-line read of `plan-sharp-edges.md`** — Recovery: body in a file with `Mandated-By:`; grepped the remainder. **Prevention:** none beyond the existing hook text; one-off.
2. **A Bash chain redirected into a scratchpad directory that did not exist** — Recovery: the `&&` chain aborted before `gh issue edit` ran; `mkdir -p` then rerun. **Prevention:** `mkdir -p` the scratch path in the same command that writes to it.
3. **Read "Do it via playwright for me" as a GitHub issue edit and opened another comment's edit box** — Recovery: cancelled without saving; the user clarified they meant the Hetzner items. **Prevention:** when "it" has two plausible referents and one is outward-facing, ask which before any browser write, or name the interpretation in one line first.
4. **A Playwright click used a bare snapshot ref that did not resolve in the console iframe** — Recovery: frame-prefixed ref. **Prevention:** use the ref exactly as the snapshot prints it, frame prefix included.
5. **The Hetzner support form's project dropdown ignored mouse clicks (the textarea intercepted pointer events)** — Recovery: keyboard ArrowDown + Enter. **Prevention:** when `click` reports "subtree intercepts pointer events", switch to keyboard selection instead of dispatching synthetic events.
6. **Guessed the path of `admin-merge-ready.test.sh` (rc 127)** — Recovery: `git ls-files | grep`. **Prevention:** resolve a test path with `git ls-files` before running it.
7. **`pgrep -f` was blocked by a hook** — Recovery: `source proc.sh && list_runs`. **Prevention:** none; the hook message already prescribes it.
8. **`technical-ruling-gate.sh` rejected seven planner rows** — Recovery: one batched `soleur:engineering:cto` spawn rewrote the Ruling cells. **Prevention:** a technical row is written as `Ruled by CTO agent, <date>: <decision> - <rationale>` or spawns the CTO; routed as a bullet in `plan-sharp-edges.md`.
9. **A fix agent stopped on an interim "waiting on my own background watcher" with uncommitted edits** — Recovery: `SendMessage` resume asking for foreground suite runs. **Prevention:** put "run suites in the foreground; the final message is the report" in the spawn prompt; routed as a bullet in `work-subagent-fanout.md`.
10. **Review seats and a verification seat repeatedly sent interim messages while their own suites ran** — Recovery: waited for the final notification. **Prevention:** same bullet as 9.
11. **The stop hook twice flagged a turn that ended on a next action I had named but not taken** — Recovery: ended with a `Paused:` sentence naming the one blocker. **Prevention:** when a background task is the blocker, state it as `Paused: <what>` rather than a first-person plan.
12. **QA's literal AC13 grep found 0 hits; the delegate had reported the AC covered** — Recovery: named the command in the section's lead sentence, re-ran the suite. **Prevention:** run each AC's literal command at the end of the work phase, not only at QA, including for delegated work.
13. **Fix batch 2 commit 1 leaves the suite red until commit 2** — Recovery: only the final HEAD was pushed and verified. **Prevention:** order commits so each is green, or squash the pair; low value on a branch that squash-merges.

## Tags
category: workflow-issues
module: review, ci-head-verdict
