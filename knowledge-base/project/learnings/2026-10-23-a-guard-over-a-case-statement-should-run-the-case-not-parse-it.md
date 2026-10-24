# Learning: a guard over a `case` statement should run the `case`, not parse it

## Problem
The apply workflow's restore step maps the restore engine's exit codes to operator-facing `::error::` lines through a `case "$rc"`. Exit 78 had no arm and fell into the `*)` text that called it "a defect worth filing", and arms 2 and 5 described only their older meaning. The first guard (W9) text-parsed the `case` for a labelled line per code. Two consecutive review rounds bypassed it: a case subject changed to another variable, `exit "$rc"` replaced by `exit 0`, a dead-branch copy of the arm, an arm nested inside another arm, an extra command inside an arm. Each bypass kept the suite green because the guard asserted the PRESENCE of a line, not the chain rc -> arm -> annotation -> step exit status. The first fix commit also introduced new defects (a false exit-1 comment, thin control coverage).

## Solution
W9 now RUNS the step's real `run:` body (PyYAML extracts it) with `doppler`, `sleep` and the engine stubbed, once per engine code, and asserts what an operator and the runner would see: the step's exit status, the emitted annotation naming the code, the engine call count (the step's own `max=` for exit 3). Round 2 added a recovery run (3, 3, 0), a Doppler-failure run, an exact pin on the first engine call's arguments plus a not-traced check, step uniqueness and a refusal of step keys the harness does not model, and a hermetic harness (PATH-only env, own cwd, stdin closed, timeout, signal traps). Fifteen controls mutate the REAL workflow text and require the same check to refuse each with a message naming the right thing. The exit-code population is derived from the engine's own header table, cross-checked against its `die N` / `exit N` sites, via one shared extractor (`tests/scripts/lib/restore-engine-header.sh`).

## Key Insight
When the property is "input X reaches output Y through control flow", a text predicate over the control flow is a claim about layout and can always be satisfied by a layout that does not execute. Run the code with its dependencies stubbed. Then grade the controls: each must mutate the real artifact (not a hand-built copy), assert the mutation landed, and require the refusal to name the right cause, otherwise a control can pass for the wrong reason. A fix commit is the least-audited surface: read its new code for the same class it claims to close, and stop the loop with an explicit stop rule (one more targeted round, then a verification pass by the lead only).

## Session Errors
- **Scratch-tree mutation control void** (scratch copy lacked `cloud-init.yml`, so the suite failed for the wrong reason) — Recovery: copy every file the suite reads. Prevention: controls assert the refusal message naming the cause, not a non-zero exit.
- **Mutator anchors matched more than once; a malformed dead-branch control** — Recovery: `once()` requires exactly one anchor match; the mutation-landed row fails otherwise. Prevention: assert uniqueness before replacing.
- **Text-parse guard bypassed in two consecutive rounds; first fix introduced new defects** — Recovery: behavioural W9 (CTO ruling "F3 amended"). Prevention: grade fix commits as their own change; set a stop rule.
- **PreToolUse hook rejected a `git commit` combined with `bash -c "$VAR..."`** — Recovery: run the commit as its own command with a literal `cd <abs path> &&`. Prevention: keep commits separate.
- **Issue filing refused by a hook** — Recovery: re-filed with the machinery label (#10932). Prevention: include the machinery label on pipeline follow-ups.
- **decision-challenges.md failed the ruling gate twice** — Recovery: fixed, gate passes. Prevention: run the gate before the first commit.
- **A multi-lint foreground sweep exceeded the 120s tool timeout** — Recovery: moved to background and waited. Prevention: run lint sweeps in the background.
- **Guessed where fixture lints are invoked** — Recovery: `scripts/pre-push-ratchet-lane.sh` lists them. Prevention: read the lane file first.
- **`emit-review-trailer.sh` refused with a staged file** — Recovery: committed first, re-ran. Prevention: commit session-state before emitting trailers.
- **Stop hook flagged a closing sentence naming an action not yet taken** — Recovery: continued the pipeline. Prevention: end a waiting turn with a `Paused:` sentence.

## Tags
category: workflow-issues
module: apply-web-platform-infra, tests/scripts
