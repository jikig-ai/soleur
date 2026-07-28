# Learning: the fix for a too-noisy alarm shipped five new ways for it to go silent

## Problem

`scripts/tmpfs-guard.sh` alarms every 5 minutes, forever, because `COUNT_TRIGGER=5000` sits against
a ~20,800-entry pre-existing `/tmp` backlog. #7004 PR 0 rebaselined the signal from **absolute
count** to **growth above a downward-ratcheting watermark** (`floor = min(stored, current)`), so the
standing backlog goes quiet while a new leak still alarms.

The change was ~80 lines, TDD'd (RED 43/6 → GREEN 49/0), shellcheck-clean, and self-mutation-tested
3/3. Eight review agents then found **six merge-blocking defects, four of them introduced by the
fix**. Every one had the same shape: *the guard keeps reporting health while the alarm it exists to
raise can no longer fire.* On an alarm path there is no loud failure mode — the failure surface is
silence, which is byte-identical to success.

## Solution

Each defect below was independently reproduced before being fixed.

**1. `min(stored, current)` does not neutralise a bad stored value — it is what destroys the signal.**
I reasoned that a corrupt or hostile watermark was safe because it gets re-floored. It does — **to
`current`** — which forgives the entire accumulated growth. Measured:

| perturbation (true floor 5, leak at 14) | floor after | then +15 entries |
|---|---|---|
| watermark deleted | **14** | no alarm |
| watermark = `xx` | **14** | no alarm |
| hostile `999999999` | **14** | no alarm |

At production scale: a leak at 18,000 over a legitimate floor of 600 has its floor rewritten to
18,000, so the alarm now needs 23,000 — and the write most likely to fail is one happening *during*
the disk pressure being alarmed. The discriminator was already on disk: `HEARTBEAT_FILE` exists
**iff** a previous run completed, so heartbeat-present + watermark-absent is **state loss**, not a
first run. Reseed (there is nothing else to floor to) but `alarm_record` it.

**2. An enumeration failure floored the watermark to 0, permanently.** `find` failing was swallowed
into `0`; because the ratchet is down-only that persists `floor=0` and re-arms the forever-alarm on
the next healthy run. Reproduced: run1 `wm=30`, run2 (unreadable `/tmp`) `wm=0`, run3 alarms at the
full count and never stops. Fix: return non-zero for *"could not look"* and leave the stored floor
untouched.

**3. The dead variable was load-bearing as a side effect.** `entry_count` had no reader —
`shellcheck` can't flag it, and **two agents independently said delete it**. A third proved that
under `set -euo pipefail` its un-guarded `find` **aborted the function** when `/tmp` was unreadable,
and that abort was the only thing keeping defect 2 latent. Deleting it alone converts latent →
live. Fail-close the counter *first*, then delete: **one change, never two.**

**4. Making the alarm rarer made it invisible.** The SessionStart loader renders `tail -1` of the
alarm file. The count alarm appends at run *start*; the usage alarm appends at run *end*. While the
count alarm re-fired every 5 minutes this was harmless. The moment it became edge-triggered, a
genuine leak was the tail line for exactly **one** run, then outranked every run after — and evicted
from the 200-line cap within hours. Verified against the operator's real alarm log:
`20:25:02 COUNT → 20:31:29 USAGE`, repeatedly.

**5. A silent write failure disarmed growth detection forever**, with no artifact on any channel.
Fixed with atomic tmp+mv (mirroring `alarm_record`) plus a `COUNT_DEGRADED` flag, because
`alarm_clear_if_healthy` would otherwise erase the very alarm reporting the disarm (a disarmed guard
reports `growth=0`, which satisfies "no pressure").

**6. The test suite overwrote the operator's real heartbeat.** `guard_env` defaulted `LOG_SINK` and
`LOCKFILE` but not `HEARTBEAT_FILE`. Live proof found mid-review: the real heartbeat read
`run complete: /tmp/tmpfs-guard.vFKDu4hJ/tmp at 94%` — a **fixture root**. That refreshes the mtime
SessionStart checks, so a genuinely dead cron reads as alive for 30 minutes. My own test runs caused
it.

Also: a recogniser (the ownership-schema regex) was shipped **one PR ahead of its producer**. It
matched zero entries, so it delivered nothing, while its failure direction was silent — if PR 1's
allocator emits a different suffix arity, nothing matches and the forever-alarm returns *at the
moment the allocator lands*. Moved to PR 1; five of eleven surviving mutants were schema-regex
vacuities that dissolved with the move.

## Key Insight

**On a signal path, ask of every change: what input makes this go quiet while the condition it
watches is still true?** Correctness review asks "does it compute the right answer"; an alarm needs
the adversarial question instead, because its failure mode is indistinguishable from its success
mode. Four of the six defects were introduced by a change whose entire purpose was to make the alarm
*more* trustworthy.

Three generalisable sub-rules:

- **A clamp that "protects" against a bad input may be the thing that destroys the signal.**
  `min(stored, current)` reads as defensive and is the amnesty mechanism. Ask what the clamp does to
  the *good* value when the *other* operand is wrong.
- **"Dead code" is a claim about the return value, not about the failure mode.** Before deleting an
  unread variable, ask what its *failure* contributes under `set -e` / `pipefail`. Agent convergence
  is not proof — two agents agreed on the deletion that would have shipped the bug.
- **Level-triggered → edge-triggered is a breaking change for every consumer that samples rather
  than accumulates.** Rarity and invisibility are the same thing to a `tail -1` reader.

## Recurrence signal (the part worth the most)

Three of this session's findings are **re-occurrences of classes already documented in this repo**,
and I hit them anyway with the rules loaded:

- The threshold finding — a hardcoded `growth >= 7` passed the entire 49-assertion suite, so
  `COUNT_TRIGGER`, its env override, and the documented justification for 5000 were unfalsifiable —
  is the class in
  [[2026-07-24-count-vs-floor-guard-single-value-fixtures-cannot-discriminate-operator]], written
  **four days earlier**, which already prescribes the exact fix ("pins that the guard reads the
  declared value, not a hardcoded 1").
- The self-graded battery is [[2026-07-19-my-own-mutation-battery-was-the-false-confidence]]. I ran
  3 mutations, all killed, and recorded "mutation-verified". An independent pass ran 13 and **11
  survived**.
- The void baseline is
  [[2026-07-19-a-self-graded-mutation-battery-went-vacuous-twice-in-one-pr-and-the-two-producer-count-that-fixed-it]].
  It went void **twice more here**, from two different causes: a sandbox missing a file a drift-guard
  arm reads, and `/tmp` hitting 99% (partly from my own repeated 20 MB-fixture runs) so the first arm
  could not allocate. Both times the baseline exited non-zero with **zero `[FAIL]` lines** and the
  mutation column looked exactly like a column of kills.

The operational takeaway is not "read the learnings harder". It is that these three have a
**mechanical gate** available and prose has now failed for them repeatedly:

1. require the un-mutated baseline to be `rc=0` **and** assert each mutation LANDED against a
   pristine backup before scoring it — a battery whose baseline is red is void in *both* directions;
2. for any threshold, fixture the boundary pair (`== N` and `== N-1`) and a second magnitude, so a
   hardcoded constant cannot pass;
3. treat a self-run battery as a floor and hand the suite to an independent pass whose mandate is
   *"find the vacuity my battery missed"* — not to re-run its mutations.

## Session Errors

1. **Self-authored mutation battery recorded as proof.** 3 mutations, all killed → "mutation-verified"
   in `tasks.md`. Independent pass: 11 of 13 survived. — *Recovery:* wrote arms 22–29 to close them;
   8/8 now killed against a green control; corrected the `tasks.md` claim (each original figure was
   also inflated by 1, because the cardinality guard fires on any failure and is not an independent
   detector). — **Prevention:** never record a self-run battery as verification; state its mutation
   count and hand the suite to an independent vacuity pass.
2. **Mutation baseline VOID (sandbox incomplete).** Sandbox omitted
   `.claude/hooks/session-rules-loader.sh`, which a drift-guard arm reads; baseline exited non-zero
   with 0 `[FAIL]` lines, so all three "RED" results were the same harness abort. — *Recovery:*
   copied the file, re-ran with an explicit positive control. — **Prevention:** positive control
   first; a non-green baseline voids the run.
3. **Mutation baseline VOID again (resource exhaustion).** `/tmp` at 99% → Arm 1's 20 MB fixture
   could not allocate → baseline aborted with 0 failures, again looking like kills. — *Recovery:*
   re-ran with `TMPDIR=/var/tmp`. — **Prevention:** same gate; write large fixtures to disk, not
   tmpfs.
4. **Threshold constant unfalsifiable.** See Recurrence signal. — **Prevention:** boundary-pair
   fixtures.
5. **`min(stored,current)` reasoned safe, measured harmful.** — *Recovery:* heartbeat-based
   state-loss discrimination + alarm. — **Prevention:** on any clamp, ask what it does to the good
   operand when the other is wrong.
6. **Nearly deleted a load-bearing "dead" variable on two agents' advice.** — *Recovery:* fail-closed
   the counter first, then deleted. — **Prevention:** ask what an unread variable's *failure mode*
   contributes.
7. **Test suite polluted the operator's real heartbeat.** — *Recovery:* defaulted
   `TMPFS_GUARD_HEARTBEAT_FILE` in `guard_env`. — **Prevention:** every state file a script writes
   needs a test seam defaulted for *every* arm, not per-arm.
8. **My test runs drove `/tmp` 94% → 99%.** — *Recovery:* cleaned up only my own artifacts (never a
   sibling session's, per the shared-tmpfs rule). — **Prevention:** route repeated large-fixture runs
   to `/var/tmp`.
9. **Arm 21(a) false-failed after adding state-loss detection** — the heartbeat leaked in from
   earlier arms, so a "first run" fixture wasn't one. — *Recovery:* removed both state files in the
   arm and added a dedicated state-loss arm with a mutation control. — **Prevention:** an arm must
   clear *every* piece of state its assertion depends on, not just the one it names.
10. **One unexplained arm failure I nearly hand-waved.** The degraded-watermark arm failed once, then
    passed. — *Recovery:* ran it 12× in isolation (12/12) and 4× in-suite (4/4); traced it to stale
    state from my own interleaved manual probing. — **Prevention:** don't interleave ad-hoc probes
    with suite runs; a one-off failure in a test you just wrote is a stability question, not noise.
11. **Full suite 232/233 twice**, both times a contention timeout on a file the diff never touched
    (`skill-security-scan` 194 s, then `pdf-text-extract` 15 s). — *Recovery:* the documented
    three-way confirmation (isolated re-run, branch CI gate, clean full re-run — 233/233 rc=0).
    — **Prevention:** none needed; the protocol worked as written.
12. **CI `lint-bot-statuses` failed** on three plan lines where "operator" co-occurred with an infra
    imperative. All three were descriptive (they state the backlog resolves *passively*). —
    *Recovery:* reworded rather than wrapping in `lint-infra-ignore`, keeping the gate armed over
    that span. — **Prevention:** run `python3 scripts/lint-infra-no-human-steps.py --changed --base
    origin/main` locally before pushing prose that mentions reboot/mount near "operator".
13. **Push rejected post-rebase.** — *Recovery:* verified the remote held only my own commits, then
    `--force-with-lease`. — **Prevention:** expected after rebasing a draft-PR branch; verify
    authorship before forcing.

## Tags

category: logic-errors
module: scripts/tmpfs-guard.sh
