# Learning: fixing the SOURCE of a path list left the classifier downstream of it failing open — and the new test preconditions collapsed "git failed" into "0"

## Problem

PR #12326 (issue #12251). `battery-owed.sh` decides whether the local test battery is owed. Its no-token arm built the changed-path list with `git diff --name-status -M | cut -f2- | tr '\t' '\n'`, so a C-quoted name (tab, `"`, `\`, non-ASCII) or a gitlink under `apps/web-platform/infra/` reached the `^`-anchored `INFRA_RE` as `"apps/web-platform/infra/\303\251.tf"` and read as non-infra. The fix (one line: `git -C <top> diff -z --no-renames --ignore-submodules=none --name-only ... | tr '\0' '\n'`) was ruled by the CTO before work started and was mutation-proven 14/14 by the author.

The ten-seat review then found, in code the author had just *finished*:

1. **The sink was unfixed.** The same gate's other classifier, `grep -qE "$INFRA_RE" <<<"$CHANGED"`, takes a here-string; bash writes a here-string over 64 KiB to a temp file, and with an unwritable `TMPDIR` grep never ran, the `if` was false, and the gate fell through to SKIPPABLE with an infra path present. The token arm already carried the sentinel fix and a comment naming exactly this failure (lines ~274-276). The author fixed the SOURCE of the list and the sibling ARM, not the SINK shared by the main arm. Found by the structural-enumeration seat (a map of every path to SKIPPABLE), not by any of the adversarial seats.
2. **Three new test preconditions could pass vacuously.** `t20_count` ended `git diff ... | grep -c ... || true`; when git itself fails it prints `0`, and three rows assert `"0"` ("the plain diff really drops the path"). A bogus ref left those three green and reddened only the four rows that expected `1`.
3. **Two new verdict-owning helpers (`assert_reason`, `t20_reason_sub`) had no negative control** — neutering either left 419/419 green.
4. **Fixture gaps.** `--diff-filter=ACDMR` (drops type change) and a control-byte-stripping `sed` both survived 419/419.

## Solution

- Sink: `printf '%s\n%s\n' "$CHANGED" 'apps/web-platform/infra/__sentinel__' | grep -cE "$INFRA_RE"` plus a numeric check that routes a non-numeric or zero count to UNDECIDABLE, with a T20f row that installs a grep shim failing on the infra pattern (pre-fix: SKIPPABLE; post-fix: UNDECIDABLE).
- `t20_count` captures the diff first (`l="$(git diff ...)" || exit 9`) and greps the variable, so a failing git prints nothing, never `0`.
- T19-style pass+fail controls for both helpers (the deliberate FAILs are subtracted); T20d (delete / type change), T20e (a near-miss `infra<TAB>/` directory must stay SKIPPABLE).
- 7-row round-2 mutation battery on exactly the guards added in the fix round (revert the sentinel, make the sentinel non-infra, add `--diff-filter`, strip control bytes, neuter each helper, bogus ref in `t20_count`): 7/7 killed.

## Key Insight

1. **When a fix repairs how a list is BUILT, enumerate every consumer of that list before calling the class closed.** "One chokepoint, one `CHANGED=` line" was the plan's own assembly claim; the enumeration seat's question — *name every path to the verdict that skips this chokepoint's protections* — found the second classifier in the same file. Sibling of `2026-11-05-an-allow-skipped-needs-allowance-leaked-...`: the fix was complete at the producer and silent at the consumer.
2. **`cmd | grep -c || true` is a failure-collapse, not an assertion helper.** It makes "could not measure" print the same `0` as "measured none", so a precondition of the form `== 0` is satisfiable by a broken harness. Capture the producer's status first; make an error produce *no output*, which can never equal the expected value.
3. **A review seat's factual claim about the diff is a hypothesis.** Two seats were simply wrong (one said `rc=$?` reads `tr`'s status — two other seats measured `pipefail` makes it reflect git; one said a registry file was edited by the PR — it is not in the diff). Re-derive against the tree before acting; the cheapest check was one `git diff --stat` and one shim run.
4. **Resolve the risk tier BEFORE spawning the panel.** The plan said `aggregate pattern`, which adds the user-impact seat; it was spawned after the first ten returned. Harmless here (no findings), but the trailer would have understated coverage had it been emitted first.

## Session Errors

1. **Panel spawned without the tier-required user-impact seat** — Recovery: spawned it before emitting the trailer; coverage recorded 11/11. **Prevention:** read the plan's `Brand-survival threshold` in the same call as the classification gate and add the seat to the first spawn batch.
2. **Two review seats made false factual claims** (a registry file "edited in this PR"; `rc=$?` "reads tr's status") — Recovery: checked `git diff --stat` and two seats' shim measurements before acting. **Prevention:** none beyond the existing reconcile-a-finding-against-the-artifact rule; recorded as evidence the rule is load-bearing.
3. **`gh issue create` for the scope-out was blocked by the filing gate** ("names no user-visible consequence") — Recovery: it is a finding about Soleur's own gate machinery, so added `--label meta/machinery` (the hook's exit 1). **Prevention:** none; the hook's text named the exit; a verification-machinery filing carries that label by default.
4. **The resume summary said the plan had no Test Scenarios section; it has one (prose only)** — Recovery: grepped the plan, found it, and skipped QA for the correct reason (no executable `Browser:`/`API verify:` steps). **Prevention:** a summary's "X does not exist" is a claim; grep before skipping a phase on its strength.

## Tags
category: logic-errors
module: plugins/soleur/skills/ship/scripts/battery-owed.sh
