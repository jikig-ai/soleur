---
title: "The errexit model must be judged at the command's position, and every 'harmless text' channel a regex can't see is a false-positive vector"
date: 2026-09-25
category: workflow-patterns
tags: [lint, errexit, shell, baseline, review-panel, false-positives, port-fidelity]
issue: 8784
pr: 8836
related:
  - knowledge-base/project/learnings/2026-08-09-the-shell-capture-trap-recurred-three-times-and-finally-earned-a-lint.md
  - knowledge-base/project/learnings/2026-09-19-i-simulated-the-regex-and-segmented-the-pipeline-by-eye.md
---

# The errexit model must be judged at the command's position, and every 'harmless text' channel a regex can't see is a false-positive vector

## Problem

#8784 extended `scripts/lint-shell-capture-exit.py` with S3 (a command runs armed under
`set -e`, then `rc=$?` tries to read its status — dead) and S4 (`test && action` as a
function's last statement leaks the test's false status). A first implementation scanned
the real tree and produced ~80 findings; roughly a third were not the defect class — they
were text channels the resolver had treated as code:

- `trap 'rc=$?; ...'`, `bash -c '...'`, `ssh host '...'` — the read is evaluated by a
  different context (fire-time shell, `-c`'d interpreter, remote), never this line's
  errexit.
- `x=$(cmd) || { rc=$?; ... }` — the read inside the failure block sees the status that
  selected it; it is the protection idiom itself, not a leak.
- `if x=$(cmd); then rc=0; else rc=$?; fi` — the gate's own recommended rewrite, flagged
  by its own rule.
- `echo rc=$?` — a read inside an argument, deliberately scoped out in the docstring and
  flagged anyway with the wrong antecedent (`echo`, not the real command).
- `2>&1` — `&` as a statement separator split redirections into phantom commands.
- `x=$(a; b)` — `;` inside `$(` left `b)` as a phantom segment that hit the case-arm
  exemption.
- `${var}` in `before` — a substring `{` check swallowed the codebase's most common
  quoting idiom.
- `a || b; rc=$?` — a substring `||` check couldn't see the `;` that made the read a new
  statement.
- `cmd; set +e; rc=$?` — a `set` verdict folded after the command it follows, so the
  canonical mis-fix went silent on one line while its multi-line twin fired.

Then the panel found the model bugs that produced wrong-direction findings: `set +e`
inside `$( )` had been honored as a file-wide clear (fail-open — the whole second half of
`ci-deploy.test.sh` was invisible to S1); `set -e` inside `$( )` phantom-armed regions
(seven S1s nobody could reproduce); `set -uo pipefail # deliberately NOT -e` tokenized
the comment's `-e` and armed errexit for the rest of the file; `PIPESTATUS` reads after
`set +o pipefail` (a deliberate contract in `ci-deploy.sh`) flagged as dead; `}`-only
lines popped the enclosing function even when they closed an inner `{` group (seven
false S4 tails in one file); and `name() {` opener lines `continue`d past the S1 checks
that had always run on them — a silent regression of the gate's original class.

## Solution

The rewrite that survived review is a statement-segment model, not a regex on `before`:

- Split `before` on `;` only. `|`, `||`, `&&`, `&` belong to the command being resolved
  (pipeline stages, operands, `2>&1`), never to statement boundaries.
- Fold `set` verdicts FORWARD with a state snapshot per segment — `set +e; out=$(cmd);
  rc=$?` is judged disarmed; `cmd; set +e; rc=$?` fires, because the clear ran after.
- Text between the last `;` and the read that isn't a declaration prefix or a `set` is
  an argument (`echo rc=$?`, `then`, `else`) — the bare-in-arguments class, silent.
- `set` produces errexit AND pipefail deltas (cluster-final `o` consumes the next token:
  `set -euo pipefail`), gated symmetrically on `depth == 0` — inside `$( )`/`( )` a
  `set` neither arms nor clears the outer model.
- `PIPESTATUS` reads after a pipeline are silent unless pipefail is armed at the
  command's line.
- Func tracking counts inner `{` groups so `}`-only closers don't mis-pop; the tail
  shares the opener line in `f() { tail` form and is checked after stripping the opener.
- Quoted spans are blanked before `||`/`&&` checks (inside substitution bodies too —
  `grep 'a||b'` stopped being a false protection).

## Key Insight

**Judge state at the construct's position, and treat every character class that isn't
code — quoted strings, comments, subshell boundaries, statement separators inside
groups — as a false-positive vector until proven otherwise.** The ported sibling
semantics were correct *for workflow `run:` blocks*; the real tree's idioms (trap
strings, `|| {` failure blocks, same-line `set` sandwiches, `PIPESTATUS` contracts) are
where a regex-first scanner learns what it can't see. The first live-run triage IS the
false-positive survey — budget for it.

Second-order: the gate immediately earned its keep — of ~90 triaged findings, **eleven
were live bugs with unreachable error paths** (`git branch -D`, `docker exec`, `git
diff --cached`, `git log` dead-reads whose carefully-written failure arms could never
run), fixed in-PR rather than baselined. A gate that only ever baselines is decoration;
the disposition question that makes it load-bearing is "does the error path this read
feeds actually run today?"

## Session Errors

1. Planning subagent interrupted mid-run → recovered from on-disk artifacts. **Prevention:**
   existing plan-artifact-recovery protocol worked; none needed.
2. `--write-baseline` emitted duplicate fingerprint rows (identical normalized text at
   multiple sites) → set-dedup added. **Prevention:** dedup on write; the diff now reads
   clean.
3. Baseline fixture broke when `--write-baseline` refused explicit paths → reworked to a
   mini-git-root fixture. **Prevention:** refusal + fixture shipped together; sibling parity.
4. `test-all.sh --affected` degraded to `full` (diff touches `test-all.sh`) then refused on
   sibling contention. **Prevention:** directly-covering suites + CI gate covered it; no rule
   change.
5. Plugin review seats unavailable on Devin → 4/8 dominant seats via `run_subagent`; trailer
   marks degraded coverage. **Prevention:** none — honest coverage reporting is the mechanism.
6. Iterative false-positive classes (ten shapes above) found across implementation + review.
   **Prevention:** fixtures for every class shipped in the suite (61 assertions); the
   real-tree triage is now a deliberate phase, not a surprise.

## Tags

lint, errexit, set-e, regex-scanner, false-positives, baseline, review-panel, port-fidelity
