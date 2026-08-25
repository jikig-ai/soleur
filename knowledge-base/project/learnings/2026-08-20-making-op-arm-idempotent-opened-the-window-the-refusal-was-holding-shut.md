---
title: Making op=arm idempotent opened a double-fire window the refusal had been holding shut
date: 2026-08-20
issue: 7462
pr: 7647
category: workflow-patterns
module: cutover-inngest
tags: [inngest, cutover, fail-closed, guard-design, idempotence, stale-claims, propagation]
---

# Making `op=arm` idempotent opened the window the refusal had been holding shut

## Problem

`op=arm`'s G3 gate refused whenever the DSN it was about to write already equalled the value in
place. That condition became permanently true after the first successful arm on
**2026-07-23T15:46Z** — `op=arm` writes the prod DSN and `op=rollback` has no inverse for that
write — so the cutover could never be re-armed after a rollback, which is precisely what rollback
exists to allow. Removing the refusal is correct and is what #7462 shipped.

What the refusal was ALSO doing, incidentally, was blocking a re-arm of a host that had already
been FLUSHALL'd.

## The finding

Once a flip completes, the monotonic latch on `/mnt/data` (`inngest-cutover-flip.sh`
`flush_already_performed`, #7228 P0-5) refuses every subsequent re-arm and drives the flag to
terminal `aborted`. That refusal is correct and is not the defect. The defect is everything
`op=arm` did on the way to it:

1. G4 wrote both prod secrets.
2. G5 wrote `INNGEST_CUTOVER_FLIP=armed`.
3. For the ~30-60s until the on-host 30s timer fired, the flag sat at `armed` — a value **inside**
   `inngest-server-flip-guard.sh`'s prod-start allowlist `{armed,flipping,flushed,done}` — while
   `op=rollback` had already re-enabled the co-located web schedulers.
4. A reboot inside that window starts a SECOND prod scheduler. A double-fire, not data loss.

Pre-#7462 that window was unreachable **only incidentally**: the equality refusal blocked the
re-arm outright. Idempotence removed the accidental block, so the window is PR-introduced.

## Key insight

**A guard you remove for one reason may be load-bearing for a second reason it never names.** G3's
error text named exactly one hazard ("would flip onto the DARK backend"), and that hazard was
genuinely held elsewhere (the positive prod-project pin). The FLUSHALL hazard was held elsewhere
too — by the on-host latch. Both of those checks passed. What neither covers is the *interval*
between writing `armed` and the on-host latch refusing it, and nothing in the refusal's own
justification pointed at that interval, because a gate's stated rationale is a description of why
it was ADDED, never an inventory of what it currently prevents.

The generalisable move: when removing a refusal, do not only ask "is the hazard it names held
elsewhere?" Ask "what states does the system now reach that it could not reach before?" — and check
each new state against the allowlists of every OTHER guard. Here the newly-reachable state was
`INNGEST_CUTOVER_FLIP=armed` on an already-flushed host, and the guard that read it was in a
different file.

## Solution

**G3.7 — a pre-G4 flush-latch gate.** It refuses the doomed arm before any prod write, asking the
same question the on-host latch asks ("has a FLUSHALL ever been performed for this host?") over the
same no-SSH `betterstack-query.sh` reader `_flip_transition_dt` already uses, keyed on the two
`emit_state` literals that prove it: `"reason":"flip-complete"` and
`"reason":"refuse-rearm-after-done"`. No new transport, credential or fixture class.

It also implements a precondition that until now existed only in prose: `op=resume`'s header has
named a G2 *"the durable flush latch must EXIST"* precondition since #7228 and nothing enforced it.

Four design choices worth carrying forward:

- **Pre-filter, not authority.** The on-host latch remains what actually prevents a second FLUSHALL;
  this gate can only ever ADD a refusal. That is what makes both error directions safe: a window
  too WIDE costs a refused dispatch on a legitimately-recut host, and a window too NARROW degrades
  to the pre-gate behaviour. Stating which of the two guards is authoritative is what lets the
  remediation be a *narrowing lever* rather than a bypass.
- **Positive allowlist, not a blocklist of refusals.** The gate proceeds only on the literal
  `clear`, so a future outcome token fails closed by construction. G3 became a pure logger at 381/0
  green precisely by falling through an unenumerated case.
- **Existence needs no truncation guard, and the asymmetry is the point.** `_flip_transition_dt`
  needs the EARLIEST transition, so a full page can hide the row it must return and it refuses.
  G3.7 needs only existence, which is monotone in the page: a full page means `n >= limit >= 1`.
  Truncation cannot manufacture an absence.
- **The window is a variable because the refusal names it.** See Session Error 3.

## Session Errors

1. **I corrected the stale AC-DARK claim at the site I had read, and there were two more in the same
   file.** `inngest-host.tf`'s opening paragraph said "a distinct non-prod Postgres backend"; I
   corrected it, then ran the propagation sweep and found the identical claim at `:38`
   (`DARK-ON-PROVISION (AC-DARK): the host is born on a DISTINCT NON-PROD Postgres backend`) and
   `:205` (`AC-DARK: at provision this points at a DISTINCT NON-PROD Postgres backend`) — both
   operative present-tense comments next to the live resources, i.e. the copies a reader is most
   likely to act on.
   **Recovery:** corrected both, single-sourcing the rationale at the header note and ADR-100.
   **Prevention:** run the OLD-claim grep **before** writing the correction, not after. The rule
   ("PROPAGATED is a measurement across every site asserting the claim") is already in
   `work/SKILL.md` and I applied it — but as a post-hoc audit, which makes it a lucky catch rather
   than a work-list. Grepping first turns the same rule into the thing that scopes the edit.

2. **The correction landed mid-sentence.** Inserting the note into `inngest-host.tf`'s opening
   comment split *"…on the existing"* from *"private network (network.tf) at 10.0.1.40"*, leaving a
   dangling clause — the same shape as the ref-removal-closure class, in reverse.
   **Recovery:** relocated the note to its own paragraph after the sentence ends.
   **Prevention:** after any insertion into a multi-line comment block, read back the *surrounding
   paragraph*, not just the inserted lines. A diff shows what you added; only the paragraph shows
   what you broke.

3. **The gate's remediation named a variable the workflow does not export.** G3.7's refusal tells
   the operator to re-dispatch with `FLUSH_LATCH_SINCE` set. GitHub does not export repo vars to a
   step unless the workflow NAMES them, so without a mapping that remediation is unperformable —
   the #6617 dead-remediation defect, which `cutover-inngest.yml` already carries a comment about
   ("Previously read from a name that was neither a dispatch input nor a step env var… both arms
   printed a remediation the operator could not perform without editing and merging this file").
   **Recovery:** mapped `FLUSH_LATCH_SINCE: ${{ vars.FLUSH_LATCH_SINCE }}` into the step env, and
   pinned it with an assertion so removing the mapping reddens the suite.
   **Prevention:** treat every operator-facing remediation string as a claim with a falsifying
   command. For an env var: does the workflow name it? For a command: does it exist? The cheapest
   form is a test that greps the workflow for the variable the message quotes — which is what
   shipped here.

4. **My own explanatory comment false-FAILED an existing static grep.** The comment quoted
   `deploy-status` while paraphrasing `op=resume`'s header, and the suite asserts
   `arm) adds NO deploy-status poll` with a bare-token grep over the arm body — which cannot tell a
   comment from code.
   **Recovery:** reworded the comment to drop the literal, and said in-line why.
   **Prevention:** already documented (`cq-assert-anchor-not-bare-token`, and `work/SKILL.md`'s
   "reword forbidden-literal comments to drop the literal"). Worth noting the direction: this is the
   *author* of new prose tripping an *existing* guard, which is the cheap direction — the expensive
   one is a new guard whose own comment makes it vacuous.

5. **Three net-new shellcheck findings from test-harness shapes.** SC2317 ×7 on the stubbed
   `doppler()` function (invoked indirectly by an `eval`'d SUT, so shellcheck cannot see the call),
   SC2034 on a variable read only inside an `eval`'d `assert` condition, SC2016 on a deliberate
   single-quoted literal search pattern.
   **Recovery:** three targeted `# shellcheck disable=` directives, each naming why; the PR's
   zero-net-new property holds.
   **Prevention:** none needed — these are inherent to the `eval`-the-extracted-function harness
   pattern this suite uses, and the file already carried the same three shapes before this change.

6. **A bash mutation battery died on quoting.** Nested single quotes inside a `mut "$label" "$file"
   "$py_expr"` helper produced `syntax error near unexpected token 'then'`.
   **Recovery:** rewrote the battery in Python (mutations as `(label, file, old, new)` tuples).
   **Prevention:** when a harness needs to carry code as *data*, do not carry it through two levels
   of shell quoting. This is why the resulting battery is easier to extend, not just easier to write.

7. **A foreground `run-registered-suites.sh` hit the 2-minute Bash ceiling.**
   **Recovery:** relaunched under `setsid nohup` writing to an explicit rc file, per the documented
   pattern; result 100/100.
   **Prevention:** already documented in `work/SKILL.md` §9; the run also had to be read via the rc
   file rather than the completion notification, and the box was `CAPACITY_CONTENDED` throughout
   (two sibling worktrees), which is why the `TEST_GROUP=scripts` shard queued on the advisory lock.

8. **My new harness captures would have KILLED the suite instead of failing an assertion.**
   `scripts/lint-shell-capture-exit.py` reported **11 new findings**, all of the shape
   `X=$(grep -n … "$ARM_FILE" | head -1 | cut -d: -f1)`. Under `set -euo pipefail` a `grep` that
   finds nothing exits 1, the assignment inherits it, and the suite **dies at that line** — so if
   an ordering anchor ever stopped matching, the operator would get an abrupt exit with no
   diagnostic rather than the named assertion failing. The pre-existing `G3ABORT_LN` I copied the
   shape from is baselined, which is exactly why copying it felt safe.
   **Recovery:** `|| true` on all 11; every consumer already guards with `-n`, so an empty capture
   now FAILS its assertion loudly (mutation-confirmed: M1 and M16 still red).
   **Prevention:** run the repo's own lints against the branch, not only the suite. This one is a
   registered suite in `test-all.sh` and it caught in one second what reading the diff did not.

9. **preflight Check 10's `env -i` sandbox found a PRE-EXISTING locale bug — and it was reported
   as my regression.** Inside the sandbox the suite read **448 passed, 2 failed**, one of which was
   the anti-deletion floor. The root cause was a single assertion from #6218:
   `grep -qE 'SEAM . operator maintenance-window steps'`, where the separator is an **em-dash**
   (`e2 80 94`). ERE `.` matches exactly one **byte**, so measured: `LC_ALL=C` → 0 matches,
   `LC_ALL=en_US.UTF-8` → 1. Every local run has a UTF-8 locale; `env -i` does not, and neither
   does a CI runner with no `LANG`.
   **Recovery:** `grep -qF` on the literal — byte-exact and locale-independent — fixed inline
   (1 line, a file this PR already owns, so the cost-of-filing gate says inline). The suite is now
   green under **both** `LC_ALL=C` and UTF-8, and Check 10 executes it in the sandbox and passes.
   **Prevention:** this is `work/SKILL.md` §9's "re-run each touched shard under the environments
   it SHIPS into" rule paying for itself from an unexpected direction — the environment that
   surfaced it was a *preflight gate's* sandbox, not a shard re-run. Generalise it: any assertion
   using ERE `.` or a character class against text containing a multi-byte character is
   locale-dependent, and `grep -F` is the fix. Note the shape of the false signal — the floor
   assertion made ONE broken assertion look like TWO, and both looked like mine.

## Verification

- `apps/web-platform/infra/cutover-inngest-workflow.test.sh` — **449 passed, 0 failed**;
  anti-deletion floor raised 408 → 449 (+41), recorded as a delta.
- **Mutation battery: 16 rows, 16 caught, 0 survived, 0 void**, unmutated control green before and
  after, each mutation asserted to have LANDED against a pristine backup. Axes edited: the abort
  gate (delete / invert / relocate past the first prod write), the decision (all three arms), the
  reader (each `--grep`, the `--since` bound, the fail-closed sentinel, the purity contract,
  admitting the `noop-*` heartbeat firehose), the window constant, the workflow env mapping, and
  cross-file emitter parity (both reasons, renamed in `inngest-cutover-flip.sh`).
  **Axes deliberately NOT edited:** the `assert` helper and the scenario-dispatch harness — both
  already carry self-tests that `exit 2` — and the suite-wide anti-deletion floor.
- `apps/web-platform/infra/run-registered-suites.sh` — 100/100.
- `terraform fmt -check -recursive` clean; `lint-workflows.sh` exit 0 with no
  `cutover-inngest.yml` findings; shellcheck net-new **zero** on both edited shell files.

## Tags

category: workflow-patterns
module: cutover-inngest
