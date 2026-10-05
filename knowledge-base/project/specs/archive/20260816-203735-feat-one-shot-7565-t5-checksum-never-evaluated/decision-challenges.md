# Decision Challenges — feat-one-shot-7565-t5-checksum-never-evaluated

Emergent decisions taken during `/work` that departed from the plan, recorded per ADR-084.
Classification: both are **Mechanical** (a measurement falsified a plan-stated prediction; the
remedy is determined by the measurement, not by preference), so they were auto-decided and are
recorded here rather than surfaced as a mid-pipeline pause.

## 1. The plan's Guard 1 mutation row 2 is unsound as specified — replaced, not skipped

**Plan text.** Guard 1, row 2: *"Delete the `$` anchor from the pattern (`: FAILED` for
`: FAILED$`); **CDN blocked, apt healthy** → GREEN, and that is the finding — `FAILED open or
read` satisfies a checksum-specific assertion, i.e. bug #1 in a new disguise."*

**What was measured.** The row was executed exactly as written. It came back **RED**
(`rc=1`, 45 passed / 2 failed) with the checksum assertion *failing*, not passing. The cause:
`grep -ac 'FAILED open or read'` over the entire run returns **0**.

With `set -e` armed — which is the primary arm's whole configuration — a blocked CDN makes
`curl` exit non-zero and the chain aborts into `on_err` **before `sha256sum` ever runs**. No
tarball is opened, so no `FAILED open or read` is emitted, so there is no string for an
unanchored pattern to over-match. Dropping the anchor is a no-op in this cell.

The plan derived the row from its own probe matrix cell **(d)**, which is labelled
*"CDN blocked + no `set -e` (mutant)"* — the mutation arm's configuration, not the primary
arm's. The row silently transplanted a mutant-path observation onto the errexit-armed path.

**Why this matters beyond the row.** The row was the plan's sole evidence that the `$` anchor
is load-bearing. Had it been reported as "executed, GREEN as predicted" on the strength of the
plan's prediction, the PR would have carried a mutation transcript asserting a property its own
transcript disproves — the exact defect class (#7565) this PR exists to close, reproduced in
the PR that closes it.

**Decision.** The anchor is retained — it is still correct, and the cell it defends is
genuinely reachable. Its demonstration is rebuilt so that `sha256sum` actually runs against a
missing tarball, which requires curl's failure not to abort the chain. Rows **g1-2a / g1-2b**
append `|| true` to the curl line with the CDN blocked and differ only in the anchor:

- **g1-2a** (anchor dropped): the checksum assertion must **PASS** — the false green.
- **g1-2b** (anchor present): the checksum assertion must **FAIL** on identical input.

That pair is what makes the anchor load-bearing rather than decorative. The plan's original
row is recorded above as executed-and-falsified rather than quietly replaced.

**Residual, stated plainly.** The `|| true` is a harness contrivance: no arm in the committed
suite relaxes errexit on the curl line, so the over-match cell is not reachable in the suite as
it ships today. The anchor is therefore defence-in-depth against a future edit, not a guard on
a live path. That is a weaker claim than the plan made, and it is the true one.

## 2. Harness row H1's first execution proved nothing and was redone

**What happened.** H1 ("neuter `pass()`/`fail()` to no-ops, expect the floor to fire") was
first implemented with a python edit that injected an unbalanced `{`. The suite died with
`syntax error: unexpected end of file`, `rc=2`.

**Why it was not counted.** `rc=2` is non-zero, and a careless reading of "the row must go RED"
would have accepted it. But a bash syntax error is not the floor firing — the run never reached
`total=$((passes + fails))` at all, so the row measured nothing about the dispatch layer it
targets. A mutation that does not land reports the baseline; a mutation that lands *wrongly*
reports a different guard entirely, which is worse because it looks like a result.

**Decision.** Redone as a clean two-line substitution (`pass() { :; }` / `fail() { :; }`) that
leaves the file syntactically valid, so the floor is genuinely the detector under test. The
failed first attempt is recorded rather than discarded.
