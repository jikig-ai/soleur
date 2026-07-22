---
module: workspaces-luks-cutover
date: 2026-07-20
problem_type: logic_error
component: infra_shell
symptoms:
  - "C1 itemized verify emitted `.d..t...... ./` and safe-aborted five real production cutovers on a byte-identical tree"
  - "Every diagnosis asserted without measurement proved wrong when measured"
  - "Four separate comments claimed mechanisms the code did not implement"
root_cause: unverified_assumption
severity: high
tags: [c1-verify, g4-quiescence, measurement-vs-assertion, comment-drift, mutation-testing, luks]
synced_to: [review, work, go]
---

# Learning: every property I asserted instead of measuring was wrong

## Problem

`assert_mount_quiesced` (G4) proves no straggler holds `$MOUNT` before the LUKS freeze
that repoints 8 production workspaces of live user data. Its positive control created and
unlinked `$MOUNT/.luks-g4-probe.$$` so `lsof` would have a fd to report. Both operations
advance the transfer **root's** mtime, and the gate runs at `pre-verify` — between the
pass-2 delta rsync and the C1 byte-identity verify. C1 correctly emitted `.d..t...... ./`
and five real cutovers safe-aborted on byte-identical copies.

**C1 was right all five times.** The gate was corrupting the evidence it was about to
certify.

## Solution

Remove the perturbation at source rather than repairing it. `exec 9<"$MOUNT/workspaces"`
— a read-open of a directory the script already requires — yields an fd `lsof +D` reports
just as it reported the write fd, and moves no mtime. The holder filter moves from
path-subtraction (`grep -vF -- "$probe"`) to PID-subtraction
(`awk -v p="$$" 'NR>1 && $2 != p'`), which is what the positive control always meant.

C1 is **byte-unchanged** (`sha256` on the extracted function matches `origin/main`).
Narrowing it would have silenced the one signal that catches a wrong-device copy.

The read-probe also **gains** a gate for free: when the mapper mounts but
`$MOUNT/workspaces` is absent, docker auto-creates an empty bind source and the cutover is
declared green with every user's data missing. The write-probe **succeeds** in that state.
A read-open fails closed on exactly it.

## Key Insight

**A gate that certifies a tree must not perturb that tree** — and a repair layer is not a
substitute for not perturbing.

The first fix accepted the perturbation and bracketed it: `touch -r` save/restore, a
depth-1 listing fingerprint, a measured read-back, strict/best-effort modes, five drift
codes, a tool guard, a telemetry emitter. 193 lines. Every layer needed its own guard, and
those guards needed guards. Review found a P1 in the fingerprint (it fails open — `find`
or `sort -z` failure collapses both samples to the empty-input sha, so they compare equal
and the guard passes vacuously while telemetry affirmatively reports clean).

Under the read-probe every residual is **structurally absent**. There is nothing to
restore, so there is nothing to get wrong.

### The meta-lesson: assertion is not measurement

Nine properties were asserted in this session. Every one that was subsequently measured was
false:

| Asserted | Measured |
|---|---|
| "C1 is a false positive" | C1 correct all five times; the probe was the defect |
| "the approval gate did not hold" | it held; a human had clicked approve |
| "the mount-failure hole is unfixed" | fixed 2h earlier by a commit in session context |
| "the fingerprint catches a create+delete pair" | it cannot — net-zero by construction (m19a) |
| "this die refuses to restore" | it restored (m21 — and again at a second site) |
| "best-effort covers the straggler path" | it does not; holders check runs after |
| "the scope block is now narrow and honest" | still an overclaim (same-name recreate, `RENAME_EXCHANGE`) |
| "the RED harness pins the defect" | it passed with **and** without the fix |
| "`--no-optional-locks` is missing" | present; my grep assumed argument order |

Each measurement took under five minutes. The `lsof` read-fd test that overturned the
entire design was three commands.

**Litmus for any claim written into a comment, a die message, or a PR body:** *if this were
false, what would fail?* If the answer is "nothing", it is documentation posing as
protection — delete it or make it enforceable.

### A mutation battery only covers what you mutate

The battery reported 71/0 green. An independent reviewer then ran 7 semantics-changing
mutations and **6 survived at the exact baseline count**. The shared shape was
**one-member quantification over a multi-member producer**: `moved` ∈ {yes, no, unknown}
sampled once; the tool loop ∈ {touch, stat, find} sampled once; skew direction ∈
{undershoot, overshoot} sampled once; `phase` ∈ {freeze, pre-verify} — the `freeze` call
site executed by **neither** suite.

Passing `$mt_pre` twice to the emitter hard-wired `src_moved_after_probe=no` forever,
destroying the foreign-writer channel whose own header argues at length that the two fields
must never be collapsed — with all 93 assertions green.

## Session Errors

**Filed a P1 security issue on absence-of-evidence read in the wrong channel** — concluded
"no human approved" because no chat message said so; a GitHub UI click is invisible to that
channel. Recovery: re-dispatched under identical conditions, observed the gate hold, closed
#6731 invalid. **Prevention:** before asserting an actor did not act, identify which
channels could carry that act and check each; absence in one channel is not absence.

**Filed two issues without checking merged commits** — #6732/#6733's mechanism was fixed by
`bec339250`, listed in the session's own opening context. Recovery: closed both.
**Prevention:** grep recent merges for the mechanism before filing.

**Instructed the pipeline to narrow C1** — would have permanently weakened the integrity
proof guarding 8 production workspaces. Recovery: the planning subagent refused and logged a
User-Challenge under ADR-084. **Prevention:** a gate that has fired N times on a
byte-identical tree is evidence of an upstream perturber, not of a false positive.

**Four comments claimed mechanisms the code did not implement** (m19a scope, m21 die, the
mode doc, the listing-changed die) and the correction to the first was itself an overclaim.
Recovery: mutation battery and review agents falsified each. **Prevention:** the
"if this were false, what would fail?" litmus at write time.

**Left the RED harness's defect branch emitting `ok` after the fix landed** — the suite
passed with and without the fix; `MIN_ASSERTIONS=17` had enough headroom to hide a 21→18
drop. **Prevention:** when a RED test flips to fixed-mode, the defect branch becomes `fail`
and the floor becomes the real count, not a round number below it.

**Stale `:1428` / `:1019` citations** in comments added by the same PR that shifted them.
**Prevention:** `cq-cite-content-anchor-not-line-number` — cite the function, not the line.

**A grep that encoded an assumed argument order** reported `--no-optional-locks` absent when
it was present as `git --no-optional-locks -C`. Nearly "fixed" correct code.
**Prevention:** anchor on the smallest invariant token, not a full argument sequence.

**Dropped plan task 2.9** (the `:229` load-bearing flag-set comment). One-off.

**Monitor filter re-emitted `waiting` on every poll** instead of on state change. Recovery:
stopped and re-armed with change-detection. One-off.

**No `session-state.md` written** for the spec dir despite the one-shot contract. One-off.

**`observability-coverage-reviewer` died** with a server error mid-response; its lane was
covered manually. Transient.

## Prevention

1. **Before diagnosing a gate as wrong, prove the gate is the thing that is wrong.** Look
   one layer up for something perturbing its input.
2. **Every claim in a comment gets the falsifiability test at write time.**
3. **A mutation battery's green is evidence about the mutations, not about the tests** —
   have someone who did not write the assertions try to break them.
4. **Quantify over full sets.** Name the set each claim ranges over and count the members
   the fixture instantiates.
5. **Prefer removing a defect at source over compensating for it.** Ask what disappears
   structurally rather than what must be guarded.

## Related

- `knowledge-base/project/learnings/2026-07-19-the-harness-broke-the-rule-it-enforced-and-the-canary-could-not-fail.md`
- `knowledge-base/project/learnings/2026-07-19-my-mutation-battery-was-green-and-it-only-measured-the-mutations-i-thought-of.md`
- `knowledge-base/project/learnings/2026-07-17-every-hole-was-a-claim-quantified-over-a-set-sampled-once.md`
- ADR-119 (LUKS at-rest for the live workspaces volume); issue #6733; PR #6735
