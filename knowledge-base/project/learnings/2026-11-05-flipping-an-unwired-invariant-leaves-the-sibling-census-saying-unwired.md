# Learning: flipping a "cc is unwired" invariant left a second census saying unwired

## Problem

Wiring the approval gate and a per-Query grants object into the cc dispatcher (Ref #11635, epic Ref #9601) flipped one census
that asserted the cc runner never builds the gate dependency. A second census (`decide-boundary.test.ts`, an allowlist keyed on
"cc passes no `approval`") made the same claim, stayed green, and kept a reason string that was now false: it only stayed green
because cc passes `deps: ccDeps`, a variable, and that census parses the literal arguments of the `createCanUseTool(` call. Three
review seats found it independently; the author had flipped the census named in the plan and not searched for the claim's subject.

Two smaller shapes recurred in the same branch: assertions for an "approval absent" mode that checked a mock that mode can never
reach (vacuous), and earlier-exit tests that asserted "denied" without asserting which path denied.

## Solution

- Flip an invariant by grepping every test and doc that states it by SUBJECT (here: `cc-dispatcher`, "no approval wiring"), not by the
  one file the plan names. A "stale allowlist entry is a lie" test only catches the opposite drift.
- Attribute every deny: assert the message differs from the new site's text and that the decision log carries the reason the
  earlier exit emits, so the test fails if the late fail-closed site answers instead.
- In an absent-dependency mode, assert on something reachable (a Sentry event, the audit-log reason), never on the mock of the
  missing dependency.
- Make a self-test drive the production helper (a shared regex or function), not a private copy, and give each pre-gate allow
  set a positive control so its pin cannot pass on an empty or stubbed predicate.

## Key Insight

A guard that fails closed in one runner changes the truth of every prior statement about that runner. The cheap, reliable sweep is
by claim subject across tests, ADRs and comments; a residual-zero count of one phrasing is not evidence the claim is gone.

## Session Errors

1. **A scan meant to block a pre-excluded issue number printed a hit and I read it as clean.** I appended this branch's issue
   number to an ADR frontmatter line that already carried the excluded number, so the net diff held the number; the first scan
   printed that line and I continued. The blocking scan at the review push stopped it, and I rewrote the unpushed commit.
   Recovery: reset the unpushed commit, restore the original line, re-commit, rescan the whole history. **Prevention:** assert the
   scan is EMPTY (`[ -z "$HITS" ]`) rather than reading printed output, and never edit a line that carries an excluded token; put
   the new reference on a different line.
2. **A mutation script's block slice searched from the file start, duplicated the file, and rows 1 and 5 reported "no tests".**
   Recovery: anchor the end marker search at the start index. **Prevention:** a collection failure is not RED; read the failure
   cause, and run the control and a landing check before any row.
3. **A second mutation script targeted an anchor that did not exist and mutated nothing, then printed the baseline pass count.**
   Recovery: re-targeted the real array literal. **Prevention:** a mutation that does not land reports the baseline; assert the
   file changed before reading the result.
4. **A verification command contained `git stash list` and the hook denied the whole call.** Recovery: re-ran without it.
   **Prevention:** never include a stash verb, even read-only, in a worktree command.
5. **The planning subagent's decision-challenges rows failed the ruling-shape gate** (non-CTO rows classed technical).
   Recovery: reclassified the CPO and review-panel rows as taste. **Prevention:** already in the plan skill's Sharp Edges; run the
   gate before returning the plan.
6. **Assertions in my own new test were vacuous in absent-dependency mode and one test title promised a check I had deleted.**
   Found by the test-design seat. **Prevention:** see Solution; re-read titles after deleting an assertion.

## Tags

category: test-design
module: apps/web-platform/server/permission-callback.ts, apps/web-platform/server/cc-dispatcher.ts, ADR-309
