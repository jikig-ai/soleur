---
module: Infrastructure
date: 2026-09-20
problem_type: observability_gap
component: followthrough_probes
symptoms:
  - "A staleness clock read `earliest=` from its own file header while the sweeper that gates the run parses it from the issue body — and the comment above it asserted the opposite"
  - "Two predicate helpers owned ~64 assertions and could each be replaced with `return 0` at full green: the instrument self-test drives dispatch, not decision"
  - "cryptsetup rc 127 (PATH regression), 124 (timeout), 1 (non-root) and an empty blkid all rendered off-box as the same `store_luks=unknown`"
  - "Two hardcoded field lists, each found by a different review round, each a restatement of what the producer emits"
  - "A floor sat below the measured case count twice in one session — 44 while 49 ran, then 49 while 53 ran"
root_cause: wrong_source_of_truth
resolution_type: instrumentation_fix
severity: high
synced_to: [review, work, compound]
tags: [followthrough, staleness-clock, second-copy, predicate-reject-control, discriminator, derived-floor, anti-vacuity, sweeper, env-i]
---

# My probe graded itself against a clock its grader never read

## Problem

#8386 adds a host-side at-rest posture emitter and a follow-through probe that grades it daily. The probe carries a staleness clock: past a 30-day horizon, a branch parked on CANNOT ESTABLISH stops reading as "legitimately waiting" and escalates to ACTION REQUIRED. The horizon comes from `earliest=`.

The clock read `earliest=` out of the probe's **own file header**, and the comment above it explained why:

> Read from the tracker directive in this file's OWN header, never from a second copy: the directive is what the sweeper acts on, so anything else would let the two drift.

That sentence is backwards, and one `grep` refutes it. `sweep-followthroughs.sh` parses `earliest=` from the **issue body** (`parse_directive`, awk over the fetched body) and gates the run on that value. It never opens the probe file. So the header copy is precisely the second copy the comment forbids — and because probes run under `env -i`, nothing the sweep computed reached the probe at all.

The drift is not hypothetical for this PR. #8386's delivery is blocked on #8361; when that slips, the body directive gets re-baselined and the probe keeps measuring against a horizon nobody set. The same plan files a deferral tracker carrying its **own** directive pointing at this same probe — two trackers, two `earliest=` values, one file-header constant.

Three more instruments in the same change could report clean while measuring nothing:

1. **Two predicate helpers were never driven red.** The suite had reject controls for `assert`, `assert_emit` and `assert_field` — the *dispatch* helpers. `_head_tokens_ok` and `_posture_fields_in_head` *decide* the verdict for ~64 assertions, and a `return 0` in either left them all unbacked at full green.
2. **A captured discriminator was dropped at the wire.** `_bk_rc` was assigned and never read; `_cs_rc` never left the process. cryptsetup exit 127 (a host PATH regression — costs a host replace), 124 (timeout), 1 (not root) and a blkid that answered nothing all rendered off-box as one `store_luks=unknown`, which the review had just made a 30-day cannot-establish.
3. **Two field lists were restatements.** `store_mount_base` sat outside `_posture_fields_in_head` (hardcoded to five names); a round later `store_probe_rc` sat outside the boot guard's presence loop. Each was found by a review seat, not a guard.

## Solution

**The clock.** The sweeper now forwards the value it actually gated on as `SOLEUR_FT_EARLIEST`; the probe reads that, with the header as the standalone-run fallback. Three states, and the malformed one is why this is not a bare `${SOLEUR_FT_EARLIEST:-<header>}`:

| state | behaviour |
|---|---|
| set + well-formed | the sweeper's value — one clock, no drift |
| set + malformed | **REFUSE** the clock (no clock never escalates), naming `empty_` vs `malformed_` because those are different operator fixes |
| unset | the header copy — a standalone run has no sweeper to ask |

A silent fallback on malformed would restore the drift in the one case the two values are *known* to disagree. The shape regex is the validator in all three states: this is author-controlled text off an issue body, and `date -d` also accepts `next friday`, `@0` and `yesterday`, each of which silently re-dates the clock.

`SOLEUR_FT_*` is reserved in `valid_secret_name`, so a directive cannot name the channel in `secrets=` — forwarding is last-assignment-wins, so a directive-supplied copy placed after the sweeper's would hand the probe a horizon the sweep did not gate on. Two mechanisms, because only one is a validator: the assignment is also appended *after* the secrets loop.

A provenance line (`clock=<src> days=<n>`) now prints once per run on every path. Which clock a verdict was graded against is not recoverable from the verdict, and the escalation marker exists only where it *did* escalate — so the interesting case, a probe that stayed quiet because its clock was refused, was silent about why.

**The predicates.** Both got reject controls with FATAL reconciliation. That was immediately load-bearing: because no fixture ever violated the charset contract, three emitter guards were free to delete. A fixture on the far side (a cryptsetup `device:` line carrying a space) fixed that — deleting the backing guard now reds two assertions and the row shows `store_backing_dev=/dev/sd`, the field-splitting corruption the guard exists to stop.

**The discriminator.** `store_probe_rc=cs<rc>.bk<rc>` ships in the trusted region and the indeterminate verdict names how to read it. Writing it surfaced a real defect the suite caught on its first run: `_cs_rc` was assigned only inside the mapper arm, so on a raw-ext4 mount `set -u` aborted the **entire heartbeat** — no row at all, on every non-mapper path.

**The field lists.** Both are now derived from the `LINE=` assembly, each behind a floor so a broken extraction cannot report a clean sweep over nothing.

## Key Insight

**A coordination value held in two places has exactly one authoritative copy, and the measuring side is usually holding the other one.** Ask, of any constant a probe grades itself against: *which process made the decision this value encodes, and where did that process read it from?* The answer is a fact about a second file, not a matter of taste — so it is checkable in one `grep`, and it was never checked because the rationale sitting above the line read as though it already had been.

That generalises the review rule about prose. A comment that names a mechanism (*"the sweeper acts on this"*) is a **falsifiable claim about another file**, not an explanation of the line beneath it. Treat every such sentence the way we already treat a number: name the command that refutes it, and run it. The cost is seconds; the alternative is a rationale that actively teaches the next reader the inverted model — and that reader will extend the code *consistently with it*.

And the corollary for instruments: **an instrument self-test that drives the dispatch helpers proves dispatch works, not that anything was decided.** `pass()`/`fail()` move counters; a predicate returns the verdict those counters record. Drive the helper that *owns* the verdict, not the one that reports it — and if no fixture can make that predicate return false, the guards it protects are already free to delete.

## Prevention

- **For every causal or universal sentence a diff ADDS, name the falsifying command and run it.** Highest-yield targets: claims about what *another* process reads, a platform's execution model, and what a shared name buys.
- **Reject-control the deciders, not just the reporters.** For each helper, ask: how many assertions does a `return 0` here unback? If the answer is non-zero and there is no control, write one.
- **A captured rc that is never read is a dropped discriminator.** Grep new code for variables assigned once and never expanded; on an off-box reporter, each one is a distinct host fault rendering identically to the operator.
- **Never restate a producer's field set.** Derive it, put a floor under the derivation, and make the floor exact — slack in a floor is attack budget, not padding.
- **Raise the floor in the same edit that adds the row.** This session shipped a stale floor twice; both times the gap was pure slack in the one guard that exists to detect truncation.

## Session Errors

- **A false dated causal claim in my own ADR amendment** — wrote "#6895 closed on the 2026-08-10 recut". Measured: #6895 closed `2026-07-24T18:49:47Z`, two seconds after PR #6926 merged the LUKS *design*. Recovery: rewrote with verified dates. **Prevention:** the rule above — run the falsifying command (`gh issue view --json closedAt`) before writing a dated causal claim, not after review asks.
- **A false rationale in my own clock comment** — asserted "never from a second copy: the directive is what the sweeper acts on"; the sweeper reads the issue body. Recovery: recorded the inversion rather than deleting it, and inverted the source order. **Prevention:** same rule; a comment naming another file's behaviour is a claim about that file.
- **`_cs_rc` unbound on non-mapper paths** — `set -u` aborted the entire heartbeat on raw-ext4; no row on every non-mapper path. Caught by `P-raw-ext4` on the first run. Recovery: bound `_cs_rc=na` before the branch. **Prevention:** already covered — the fixture existed because the suite enumerates mount *shapes*, not just the happy one.
- **`$${_cs_rc}` renders to `${_cs_rc}`** and tripped the suite's own no-unrendered-interpolation assertion. Recovery: unbraced `$$_cs_rc`. **Prevention:** covered by that assertion; it worked.
- **`store_mount_base` outside the hardcoded field list**, then `store_probe_rc` outside the boot guard's. Recovery: both lists derived with floors. **Prevention:** the no-restatement rule above.
- **V4b too broad** — suppressed the plaintext verdict even when independent disjuncts fired, hiding a definitively-wrong volume. Recovery: narrowed to `-z "$V4_REASONS"`; mutation M2 now reds. **Prevention:** one-off logic defect; the mutation battery is the durable guard.
- **V4b's `absent` branch was dead and its fixture producer-impossible** — `STORE_LUKS=absent` is set only on the `__NOMOUNT__` path. Recovery: rebuilt the case on the real producer shape. **Prevention:** build fixtures from the producer's own emit sites, not from the field's value space.
- **Legend/token mismatch** — the legend printed `store_luks_not_yes`; `_v4_add` produces `store_luks_no`. One-off.
- **`$REPO_ROOT` undefined in the boot guard** — aborted rc=1 *before* its own floor, so the floor could not report the truncation. Recovery: `$SCRIPT_DIR/../../../scripts/…`. **Prevention:** already ruled (`hr-when-a-command-exits-non-zero-or-prints`); the lesson is that a guard aborting before its floor is the floor's blind spot.
- **`printf … | grep -q` under `set -o pipefail`** — SIGPIPE false negative on an early match. Recovery: herestrings. **Prevention:** no rule covers this; routed to definition.
- **An absolute PATH broke the test harness twice** — first the whole-replace removed jq/curl/awk (no row emitted at all); then removing inheritance broke the no-jq tier-4 cases that pass `PATH=` via env. Recovery: the render seam keeps inheritance in the copy, the shipped template keeps the secure prepend, and the property is asserted against the template. **Prevention:** when a seam rewrites an environment variable, state which of {the copy, the shipped artifact} each assertion is about.
- **Member id `<file>:<line>` broke the parity suite's print loop** (`No such file or directory`). One-off.
- **`cp -r apps` into a sandbox → "Disk quota exceeded"** (copied `node_modules`). Recovery: narrow sandboxes under `/var/tmp` holding only the files under test. **Prevention:** copy the suite's declared inputs, never a source tree root.
- **Sandbox control RED voided mutation rows twice** — once because the sandbox was not a git repo (the parity guard derives via `git grep`), once because an M1 control file was absent. Recovery: both fixed before scoring. **Prevention:** already the standing rule — run the unmutated control first; a red control voids every row. It worked both times.
- **`rc=$?` after a pipeline read `tail`'s status.** Recovery: re-measured with a redirect. **Prevention:** already ruled in `work/SKILL.md`.
- **Shipped a stale anti-vacuity floor twice** — `MIN_CASES=44` while 49 cases ran, then 49 while 53 ran. Recovery: raised both. **Prevention:** routed to definition — raise the floor in the same edit that adds the row.
- **Asserted a marker with the wrong field order** (`branch= days= clock=` emitted, `branch= clock=` asserted). Caught by the suite immediately. One-off.
- **Ran `lint-shell-capture-exit.py` without `--baseline`** and read 201 baselined findings as 201 new ones. Recovery: re-ran with the baseline (0 new). **Prevention:** routed to definition — a baselined linter invoked bare reports its entire baseline as new.
- **Full gate refused (rc=4)** with three sibling gate runs in other worktrees. Recovery: ran the diff's suites plus the repo-global ratchets by hand. **Prevention:** already documented in `one-shot/SKILL.md`; behaved exactly as specified.
- **`rm -rf "$SB"` blocked twice** by the protected-location guard on an unresolvable variable. Recovery: `mktemp -d` and no delete. **Prevention:** one-off; the guard is correctly conservative.
- Forwarded from the plan phase: a range replacement deleted `## Acceptance Criteria`; an overbroad premise in the issue text ("exits 0 on every failure arm") was corrected; two citation defects (`ADR-190` was ADR-169; plan and `tasks.md` named different halves of the `lint-followthrough-varq-ban` pair); the `playwright` MCP server failed to connect.

## Related

- `2026-09-08-every-field-my-alarm-trusted-came-from-the-region-it-did-not-trust.md` — the trusted-region contract this emitter writes into.
- `2026-09-07-every-instrument-i-built-to-check-my-own-work-could-not-tell-clean-from-never-ran.md` — the same could-not-measure/measured-bad collapse, one layer down.
- `2026-08-12-every-blocking-finding-was-the-defect-class-the-pr-existed-to-close.md` — the prose-claims rule this session's two false claims fall under.
- #8406 — filed from this review: a probe's FAIL and ACTION REQUIRED verdicts leave the daily sweeper run green with no `::error::`.
