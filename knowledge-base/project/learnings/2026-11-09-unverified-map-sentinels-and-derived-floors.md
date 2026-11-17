# Learning: lazily-built maps need a built-sentinel fail-closed; derived floors must derive at run time

## Problem

The five-issue merge-queue/tmpfs batch (PR #12510; #11764, #12484, #12501,
#12507, #12508) went through a 10-seat review panel that converged
independently on two defects of the same family — a check reading state it
never verified was produced:

1. **Unverified freshness map (`_FRESH_TOP`).** `reap_owned_cs_base` in
   `scripts/tmpfs-guard.sh` already failed closed on an unbuilt *liveness*
   map (`_INUSE_TOP`) — "couldn't look" must never read as "nothing is
   live". The new `.cs` age arm read a second, lazily-built map
   (`_FRESH_TOP`, the recursive-age map) with no equivalent check: a
   mid-walk `find`/`awk` abort — exactly the tmpfs-full condition the arm
   exists for — leaves an empty map that reads as "nothing is fresh",
   silently disarming the recursive-age gate over a mass-delete path.
   Multiple seats (security, data-integrity, architecture) named the same
   hole from different angles.
2. **`BASE_ROWS` floor mis-derived from a stale count.**
   `scripts/ci-pr-selection.test.sh`'s anti-vacuity floor is
   `BASE_ROWS + ROWS_PER_SOURCED_FILE * ${#SOURCED[@]}` — the sourced count
   is read at run time, but `BASE_ROWS` was re-derived by hand as
   `4762 - 19*7`, subtracting the *stale* sourced count (7) copied from a
   comment when the run actually sources 9 files. Result: a floor (4800)
   no run could reach — deterministic red, and worse, a "measurement" that
   was arithmetic on a remembered constant.
3. Companion mechanical misses the same round caught: a new
   synthesized-fixture pair in the affected-index ratchet needed an
   anchor-keyed `accept.tsv` row (`7811c4a3878a/1`) — each new pair is a
   ratchet red until accepted; an unbounded `git fetch` / `gh pr view`
   could stall a step past its notice path (`timeout 30` / `timeout 60`
   applied); `reaped++` on an unchecked `find -delete` counted deletes
   that may never have happened.

## Solution

- `_build_fresh_top` sets `_FRESH_TOP[__built__]` **last**; the arm now
  checks the sentinel and skips fail-closed with a named log line — the
  identical contract the liveness map already carried. Three test rows pin
  it: named skip logged, nothing reaped, exit 0.
- `BASE_ROWS` re-derived correctly as `4762 - 19*9 = 4591`, and the header
  comment now states the formula and *why the previous derivation was
  wrong* — the run-time `${#SOURCED[@]}` was always right; only the
  hand-derived baseline was stale.
- Verified-delete counting: `find -xdev -depth -delete` guarded by `if` —
  success increments `reaped`, failure logs and counts as `retained`.
- `.soleur-owned` marker deference and a `CS_MAX_REAP` per-run cap
  (default 500, logged + `alarm_record`) brought the `.cs` arm to Reaper
  2/3 parity; `TMPFS_GUARD_CS_BASE` is pinned to `$TMP_ROOT/.cs` so a
  user-set base can never arm age-only deletion over shared `/tmp`.

## Key Insight

When a gate reads a lazily-built structure, the build and the read are two
facts. The sentinel that records "the build completed" must be written
last and checked first — a consumer that reads an unbuilt map gets the
zero value of the domain it is guarding, which is precisely the dangerous
reading (empty liveness map = "nothing live"; empty freshness map =
"nothing fresh"). Review panels converge on these: three independent seats
named the same hole, so a single inline self-review would likely have
missed it. And any floor/baseline derived by subtracting a per-N count
must derive N at run time — subtracting a count remembered in a comment
produces a floor that certifies nothing.

## Session Errors

1. **prescribed parallel fan-outs ran sequentially inline** (forwarded
   from session-state.md) — Recovery: disclosed `sequential-fallback` in
   the plan's Enhancement Summary; the 10-seat review panel ran as real
   seats. — Prevention: environment constraint (no spawn tool in the
   Devin seat); no repo fix applies — keep the disclosure trailer.
2. **`precommit-guard.sh` exits 0 as validator only** (forwarded) —
   Recovery: commits run separately after the guard passed. — Prevention:
   already covered by the commit contract; no change needed.
3. **`BASE_ROWS` re-derived off a stale sourced count (P1)** — Recovery:
   recomputed at run time, derivation comment added. — Prevention: when a
   formula mixes a run-time term (`${#SOURCED[@]}`) with a hand-derived
   baseline, re-derive the baseline against the *current* count and write
   the arithmetic into the comment.
4. **Affected-index ratchet red on the new fixture pair (P1)** —
   Recovery: anchor-keyed `accept.tsv` row added. — Prevention: the
   ratchet's own failure output names the missing pair; expected cost of
   adding synthesized fixtures — one-off mechanic.
5. **Plan-review ran as focused inline self-review** (forwarded) —
   Recovery: real 10-seat panel ran at the review stage; verdict
   SHIP-WITH-FIXES. — Prevention: same sequential-fallback constraint as
   item 1.

Deviation Analyst: no hard-rule deviations detected in this session
(worktree-only edits, no stash, bounded output, commit contract followed).
Rule budget: linter `[WARN] B_ALWAYS=44383 >= 44000` (approaching the
46000 ratchet); registry 44456 bytes / 99 rules (longest 597 chars);
constitution.md 321 bullets (>300 advisory). Both new insights above are
already-enforced in-code and domain-scoped — no AGENTS.rules.md promotion
applied at WARN budget.
Route-to-definition: solution insights classified already-enforced
(sentinels + tests now exist); no skill/agent file edits proposed — the
learning file is the carrier. Archival of the plan/spec dirs deferred to
`soleur:ship` Phase 6.45 (ship does the last live reads).
Token-efficiency: within thresholds (332 lines changed, no outliers).

## Tags

category: test-failures
module: scripts/tmpfs-guard.sh, scripts/ci-pr-selection.test.sh, .cs reaper
