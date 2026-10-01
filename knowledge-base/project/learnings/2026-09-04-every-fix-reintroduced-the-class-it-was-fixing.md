# Every fix reintroduced the class it was fixing

## Problem

Merge B of #7695 (PR #7778) shipped two destroy guards over the Hetzner volume holding
the Inngest Redis AOF — user prompts and agent output, sole copy, on a host with no SSH
and no console. Across roughly ten review rounds on one branch, **every round found the
previous round's fix carrying the defect that round had just fixed.**

This is not the same lesson as
[[2026-09-02-every-guard-i-wrote-was-satisfiable-by-a-guard-that-asserts-nothing]]
(guards that assert nothing) or
[[2026-09-03-every-check-i-shipped-was-narrower-than-the-name-it-carried]]
(checks narrower than their names). Those describe a defect. This describes its
**recursion through its own remediation** — which is a different thing to defend against,
because the remediation commit is exactly where nobody looks for the defect.

## The shape

A commit whose subject is "fix the vacuous anchors" is read, by author and reviewer alike,
as the place the class was handled. It is therefore the least-audited surface in the diff,
and the author is writing new assertions fast, in the idiom they have just been criticised
for. Concretely, on this branch:

- `fc4d1774c` fixed **eight** comment-satisfiable anchors. The next two commits introduced
  **three more**, one of them (`T60i`) sitting a single function below `T60g`, whose entire
  point is that it comment-strips and job-scopes before grepping.
- The `--since 90m` arm was rewritten *specifically* to escape the class and reintroduced it
  in the rewrite: its second alternative is matched by a shell comment inside a `run:` block.
- I re-anchored five operator-facing claims on `echo "::error::` believing emission was
  sufficient, then measured that a commented-out line **carries its own `echo` prefix**. The
  emission anchor and the comment-strip are each necessary; neither alone is sufficient. I
  had shipped the first believing it was both.

## What actually generalizes

### 1. Bind the anchor to the REGION, and make the match UNIQUE within it

The existing rule (`cq-assert-anchor-not-bare-token`) says to anchor on a call-form a
comment cannot produce. That is necessary and it was **not sufficient three times**:

| Arm | Anchored on a call-form? | Still vacuous because |
|---|---|---|
| `T60i` | yes (`echo "::error::`) | grepped the RAW file — the commented line carries the same `echo` |
| Row 7b(b2) | yes | the token occurs on TWO code paths; any match satisfied it |
| `T1.9c` | n/a — used `grep -c '^exit 1$' >= 3` | the file has NINE; six units of slack on the guarded axis |

The complete rule is three-part: **strip comments from the haystack, scope it to the region
under test, and require the match to be unique within that region.** `T60g` — job-block
extraction, comment strip, block-relative offsets — is the reference implementation.

### 2. A `grep -c` is evidence about a file, never about a branch

`T1.9c` asserted "both identity refusals exit non-zero" by counting `^exit 1$` lines against
a floor of three, in a file containing nine. Flipping either refusal to `exit 0` — the exact
fail-open the comment names — left the suite at `23 passed, 0 failed` while printing
`ok - … each exiting non-zero`. The verdict line asserted as a pass a statement false in both
halves. A count is a property of a file; a placement claim needs the statement located.

### 3. Fixing the instance while leaving the class is the default outcome, not a lapse

I closed the `"actions": []` degraded shape at the two LUKS addresses and left every other
counter in the same jq filter blind to it. Measured: three destroys of sole-copy volumes —
the Inngest AOF and `hcloud_volume.workspaces` (every user's repository tree) — scored a
completely clean plan, `destroy_count` 0, so `[ack-destroy]` was never even demanded.

The aggravating detail: **this repo had already measured that shape.**
`gate-suite-harness.sh`'s own `rc_empty_actions` docstring records a real 18-address plan
carrying `hcloud_server.web["web-1"]` in exactly that form, scoring destroys=0 and PASSING.
The knowledge existed, in the file I was editing, and the general remedy was never applied.
When you fix a degraded-input shape at one address, the next question is not "is this fixed"
but "what else consumes this input", and the answer is usually written down somewhere already.

### 4. The instrument is the blind spot, recursively

Three layers, each discovered only after the previous was fixed:

1. `expect()` got a wrapper self-test; its three siblings did not. Neutering any one left
   `112 passed, 0 failed` with **both floors printing `ok`** — `predicate()` increments its
   own counter and appends to its own coverage list, so a floor cannot see it. A floor cannot
   see a wrapper that keeps counting.
2. `gate_harness_selftest` was then added — and wired into **1 of the 13** suites that source
   the harness. 280 assertions across six suites stayed green under a careful neuter.
3. That self-test's own counter-name resolution was broken twice: it read
   `${passes:-${pass_count:-0}}` and restored all four candidate names unconditionally, so
   (a) the restore CREATED the name the next read binds to, and a second call bound to a
   stale counter and **erased three real failures**; (b) a third naming (`pass`/`fail`, used
   by the suite guarding the destroy filter) fell through to a literal `0` and printed
   "every gate_check assertion is decorative" against a healthy `gate_check`.

`${x:-…}` tests emptiness; `${x+set}` tests **presence**. A restore that writes every
candidate name manufactures the condition the next read depends on.

### 5. "The fixture now discriminates" is a claim that needs a control

The strongest evidence structure found on this branch: run the **identical mutant** against
both the old and the new fixture and show they disagree.

| | fixture = bare `*` (new) | fixture = `image_ref='*'` (old) |
|---|---|---|
| `read -ra toks <<< "$msg"` | 115/0 | 115/0 |
| `toks=($msg)` (mutant) | **114/1** | **115/0** |

Same mutant, one fixture axis, opposite verdicts. Without the old-fixture column, "it
discriminates now" is an assertion. `image_ref='*'` globs against a directory where nothing
begins `image_ref=`, so bash leaves the pattern as its literal self and both implementations
agree — the fixture was measurably non-discriminating for a reason no amount of reading it
would reveal.

### 6. Recovery text was unreachable four times, the last time because it would not PARSE

Twice the recovery *instruction* named a dispatch route the gates refuse
(`inngest-volume-recut`, then `inngest-host`). Once the recovery *arm* was refused by an
additive-only guard. The fourth: three `'"'"'` sequences inside **double**-quoted strings.
That idiom escapes an apostrophe inside a *single*-quoted string; in a double-quoted one a
bare `'` is already literal, so the sequence closes the double quote and leaves one dangling
to EOF. The **entire** `Dispatch summary` `run:` body failed to parse — nothing executed, not
even the `>> "$GITHUB_STEP_SUMMARY"` redirect. That step is `if: always()`, and its failure
branch is the only place the recut's recovery route is written into the run.

Generalizes: recovery text is code. It has a reachability condition, and the condition is
usually a guard written by the same author in the same week. Extends
[[2026-09-03-my-guard-blocked-the-recovery-and-missed-the-hazard]].

### 7. Two CI signals were misleading in opposite directions

- The PR was `DIRTY` (merge conflict), so GitHub could not compute a merge commit and ran
  **only the two CLA workflows**. `gh pr checks` reported 9 checks, all green. I read that as
  a partial run. It was not partial — it was everything that was ever going to run, and no
  test had executed on the branch since main diverged. **`mergeStateStatus` is a precondition
  for believing a check count**, and a small total on a repo whose normal run is ~80 is the
  tell.
- `lint-workflows.sh` treats actionlint's `rc=1` as accepted (census tracked in #7042), so an
  unparseable `run:` body printed its error and the job went green. A gate whose failure mode
  is "prints the finding and passes" cannot close a class. Closed with
  `scripts/lint-workflow-run-body-syntax.py`, which `bash -n`s all 798 run bodies and exits
  non-zero.

### 8. A merge where both sides added a counter must UNION the shared validation list

`main` and this branch each added a destroy-guard counter to the same workflow step. The
`^[0-9]+$` validation `if` listed only each side's own counter. Taking either parent wholesale
leaves the other counter unvalidated — it reads empty on a jq failure and evaluates FALSE in
its own `-gt 0` HALT. A fail-open on the destroy path, produced by a *correct-looking* conflict
resolution. When resolving a conflict in a validation list, the resolution is the union; check
that every operand later compared is in it.

### 9. `rc=$?` after a pipe reports the LAST command, and it cost two false reports

Twice in one session I read a status that belonged to `tail`:

```bash
bash some-suite.sh | tail -6; echo "rc=$?"     # <- tail's rc, always 0
```

The first cost a false GREEN: `plugins/soleur/test/fixture-relative-assert.test.sh` had
been failing since the merge that brought it in, and I reported it passing to the
operator. CI found it. The second cost a false RED: I called a CI job hung at "~45
minutes" when it was at 29, inside that job's own band on `main`.

This is the same defect class the branch's review hunted for INSIDE the gates
(`local x="$(cmd)"` masking rc, `set -euo pipefail` + a no-match `grep` killing a
function) — committed in the VERIFICATION of the gates rather than in the gates. The
instrument being the blind spot, one more level out.

Use `set -o pipefail`, or capture first and inspect second:

```bash
out="$(bash some-suite.sh 2>&1)"; rc=$?      # rc is the suite's
printf '%s\n' "$out" | tail -6
```

Corollary for a verdict that will be REPORTED to someone: the tally line and the exit
status are two different claims. `60 passed, 2 failed` printed next to a captured
`rc=0` should have read as a contradiction, and I read it as agreement.

## Session Errors

- **Reintroduced `cq-assert-anchor-not-bare-token` three times inside the commits fixing it.**
  Recovery: rescoped `T60i` and Row 7b(b2) to region + emission, rewrote `T1.9c` to bind each
  exit code to its own branch; all mutation-proven. Prevention: amend the rule's TEXT to the
  three-part form in §1 (issue filed) — the rule as written was followed and was insufficient.
- **Fixed the empty-actions instance at two addresses, left ~10 counters blind.** Recovery:
  one `undecidable_entries` counter over every address, HALTed upstream of the `destroy_count`
  sum. Prevention: when fixing a degraded-input shape, grep every consumer of that input before
  claiming the fix; the precedent was already documented in the file being edited.
- **`'"'"'` inside double-quoted strings made a whole `run:` body unparseable.** Recovery:
  removed the six escape characters. Prevention: `scripts/lint-workflow-run-body-syntax.py`,
  registered in `scripts/test-all.sh` in the same commit.
- **Placed wrapper self-tests before their definitions, twice** (`_bind`, then
  `gate_harness_selftest`). A call ahead of its definition is `command not found`, which moves
  no counter and reads exactly like a pass. Recovery: relocated both next to their subjects.
  Prevention: a self-test must be positioned by its subject's definition, never by the file's
  narrative order.
- **Spawned two review agents with overlapping file scopes.** One mutation-tested
  `gate-suite-harness.sh` in place while another was reading it; the second observed the file
  transiently neutered and correctly flagged the tree as unstable. Recovery: findings were
  re-derived from git objects; the tree was verified clean afterwards. Prevention: give
  concurrent review agents disjoint file scopes, or require mutation work on a scratch copy.
- **Called `test-scripts` hung at "~45 minutes" when it was at 29**, inside main's own 21–30
  minute band for that job. Arithmetic error on my part, stated to the user before checking.
  Prevention: compare against the same job's recent durations on `main` BEFORE calling
  something hung.
- **Read "9 checks passing" as a partial CI run.** It was CLA-only because the PR was `DIRTY`.
  Prevention: read `mergeStateStatus` before interpreting any check count; see §7.
- **Used `/tmp` for scratch files instead of the session scratchpad**, contributing to filling
  the 4 GB tmpfs (ENOSPC — tool output was lost for two calls). Recovery: cleared task outputs.
  Prevention: use the session scratchpad directory the environment provides.
- **Read `rc=$?` after a pipe, twice, and reported both readings.** Once as a false
  green (a suite that had been failing since the merge) and once as a false red (a CI
  job called hung at 29 minutes). Recovery: re-measured with the rc captured before the
  pipe; the real failure was then found and fixed. Prevention: see insight 9 — capture
  the output, then inspect it; and treat a tally line disagreeing with an exit status as
  a contradiction to resolve, never as agreement.
- **One-offs, no recurrence vector:** a `sleep 100` chain rejected by the harness; a second
  Monitor armed on `pr:7778` without stopping the first (hook warned; stopped it); a malformed
  `gh run list --jq` expression (`expected an object but got: string`).

## Tags

category: testing
module: destroy-guards, workflow-lints, test-instrumentation
