---
module: workspaces-luks-cutover
date: 2026-07-19
problem_type: logic_error
component: infra_shell
symptoms:
  - "A guard protecting an irreversible user-data deletion was vacuous on the real host while its test suite was 100% green"
  - "Moving a mutual-exclusion guard below the block it protects left the suite at 132 passed, 0 failed"
  - "A self-run 8-mutation battery reported all-caught; 8 review agents then found 5 P1s"
root_cause: fixture_modeled_convenient_shape_not_production_artifact
severity: critical
tags: [vacuity, mutation-testing, fail-open, fixtures, entrypoint-coverage, ap-009, verification-habits]
synced_to: [review, work]
---

# My mutation battery was green, and it only measured the mutations I thought of

**PR:** #6716 · **Issue:** Ref #6588 · **Spun-off security issue:** #6722

## Problem

I implemented a gated `CLEAN_STRAY=1` mode that deletes a stray plaintext copy of user
workspace source from web-1's root disk — a documented AP-009 ("Never delete user data")
deviation. Before review my verification was, by every visible signal, thorough:

- `workspaces-luks-staging.test.sh` — 152 assertions, 0 failed
- a new `workspaces-luks-cutover-workflow.test.sh` — 30 assertions, 0 failed
- `actionlint` clean, `shellcheck` clean
- full `scripts/test-all.sh` — rc=0
- **an 8-mutation battery I wrote and ran myself — all 8 caught**

Eight review agents then found **five P1s, four of which I had introduced.** The
mutation battery was not wrong. It measured the mutations I thought of.

## Root cause

Every hole reduced to the same shape: **a claim whose set I only ever sampled where it
was convenient.** The fixture, the harness seam, and the mutation list were each chosen
for legibility, and each choice silently excluded the states where the guard mattered.

### 1. A fixture that models a convenient layout hides the guard's vacuity

The subset check that the entire AP-009 deviation rests on compared
`find "$STAGING" -mindepth 1 -maxdepth 1`. On web-1, `/mnt/data`'s top level is
**infrastructure** (`workspaces/`, `plugins/`, `redis/`) and user identity lives one level
deeper at `workspaces/<id>/`. So the check reduced to *"does `/mnt/data` contain a directory
named `workspaces`?"* — true in **every reachable state, including one where the stray held
a user's only surviving copy.**

My fixtures placed entries at depth 1 (`ws-a`, `ws-ORPHAN`), so the
"provenance falsified → refuse" test looked like real coverage of a case that **cannot
arise at that depth on the real host.** The vacuity was invisible precisely because the
fixture and the check agreed with each other.

It propagated: the ungated preflight probe used the identical traversal, so the approval
banner's decisive instruction ("if `unique_to_stray:` lists ANY entry, do NOT approve")
was conditioned on a list that could never be populated. Both the mechanical falsifier
**and** the human check were vacuous, for the same reason.

```bash
# BEFORE — always true on the real host
find "$STAGING" -mindepth 1 -maxdepth 1 -printf '%f\n'      # -> workspaces plugins redis

# AFTER — runs to the depth where identity lives
find "$STAGING" -mindepth 1 -maxdepth "$SUBSET_DEPTH" -printf '%P\0'   # SUBSET_DEPTH=2
```

**Litmus:** *at the depth/granularity this check runs, is there any reachable state where
it says NO?* If not, it is decoration. Derive the fixture's **shape** from the production
artifact (the cloud-init that creates the dirs, a real listing, the migration) — never from
what reads well in a test.

### 2. Function-call coverage is not entrypoint coverage

The harness sources the script, and a `BASH_SOURCE` guard returns before the main body.
The mechanism that makes the harness possible is exactly what makes the main body
**permanently untested**. Two mutations, both **132 passed / 0 failed**:

| Mutation | Production effect |
|---|---|
| Move `assert_mode_exclusive` **below** the `ROLLBACK` block | Verbatim the failure its own docstring names: ROLLBACK's `exit 0` wins, the operator gets a gratuitous outage, the run exits green, the stray remains |
| Delete the `CLEAN_STRAY` mode block entirely | The whole mode is unreachable |

Behavioral cases invoke the functions **directly**, so no rollback code is ever in scope
and the ordering assertion is structurally incapable of failing. The only reachable seam is
the file itself:

```bash
ame_ln=$(grep -n '^assert_mode_exclusive$' "$CUTOVER" | head -1 | cut -d: -f1)
rb_ln=$(grep -n '^if \[ "\$ROLLBACK" = "1" \]; then$' "$CUTOVER" | head -1 | cut -d: -f1)
# fail LOUDLY if either anchor is missing — a silent "" comparison is a third vacuity
[ "$ame_ln" -lt "$rb_ln" ]
```

### 3. A mutation that does not land reports a false result — in both directions

I recorded one workflow mutation as **VACUOUS** when the replacement had never applied (bad
shell escaping). My "did it land" check compared against `HEAD` — always dirty, because the
file carried uncommitted fixes. Re-run with a real landing assertion, the guard **caught**
it.

```bash
# WRONG — HEAD is dirty during a review pass, so this never signals
git diff --quiet -- "$FILE" && echo "did not land"

# RIGHT — compare against a pristine backup, and treat baseline-identical as UN-RUN
BAK=$(mktemp -t bak.XXXXXXXX); cp "$FILE" "$BAK"; echo "BAK=$BAK"
python3 - <<'PY'
s=open(P).read(); assert OLD in s, "ANCHOR MISSING — mutation cannot land"
PY
diff -q "$BAK" "$FILE" >/dev/null && echo "!! NO DIFF — mutation did NOT land"
```

A baseline-identical result is a **null** result wearing a green result's clothes.

### 4. An upstream refusal can silently kill a downstream guard

`findmnt -no SOURCE "$STAGING"` matches **exact mount targets only**, and the guard above it
already `die`d if `$STAGING` was a mountpoint. So by the time the same-device check ran,
`staging_src` was unconditionally empty, `_same_dev` short-circuited on its empty-operand
guard, and the branch was **dead code in 100% of reachable states** — while reading exactly
like a live control, and while the ADR listed it among the guardrails justifying the AP-009
deviation. Three agents converged; one reproduced it (`stat %d` identical on both paths, the
check did not fire).

The test passed only because the fixture injected `FINDMNT_STAGING_SRC="$BLKDEV"` alongside
`MOUNTPOINT_RCS="1 0"` — a state that **cannot exist**. *A stub configuration contradicting an
earlier guard's assertion in the same case is a vacuity smell.*

**Ask of every guard in a chain:** does an EARLIER guard destroy this one's precondition?
The fix asked the question actually posed — `stat -c %d` on the **directories** (same
filesystem) — instead of reusing a helper built for a different operand type.

### 5. Three fail-open shapes in one function, all reading as guards

| Shape | Why it fails open |
|---|---|
| `if mountpoint -q "$STAGING"` | absent binary exits **127** → `if` reads false → the catastrophic-mode refusal silently does not fire |
| `while read … done <<EOF\n$(find …)\nEOF` | command substitution **discards exit status entirely** under `set -uo pipefail` with no `set -e`, so instrument failure passed the subset check and the deletion proceeded |
| `[ -z "$(ls -A "$STAGING" 2>/dev/null)" ]` | an `ls` failure reads as "empty" → emits `result=ok` |

**Unifying question:** *if this instrument were unavailable, does the guard say REFUSE or
PROCEED?*

### 6. A control whose only purpose is legibility must not degrade to nothing while green

The ungated `preflight` job exists **solely** so the approver can see what they authorize.
Its probe ended in `|| true`, so an SSH failure rendered an **empty** code block under the
heading "What will be deleted" — which reads as *"nothing unique, safe to approve."* Four
agents converged. It now fails the dispatch and writes `PROBE FAILED — DO NOT APPROVE`.

### 7. Running only the suites you touched misses siblings pinning your changed literal

`workspaces-luks-header.test.sh` **H17 pinned the gate expression byte-for-byte** and went
RED. `scripts/test-all.sh` does **not** cover `apps/web-platform/infra/` (those gate via
`infra-validation.yml`), so a green full-suite run was not evidence. The fix re-keyed H17
onto the fail-closed **shape** and left the exact-string pin in **one** place (the
YAML-parsing suite) rather than replicating the literal across two files with no parity test.

### 8. A background wrapper's "exit code 0" is not the command's exit code

Twice the harness reported a background task "completed (exit code 0)" while the suite was
**still running** and the rc file was missing — `cmd > log; echo $? > rc` reports the trailing
`echo`. Verify with an explicit rc **file** + a process check + log-size growth, never the
notification alone.

## Solution

- Subset check runs to `SUBSET_DEPTH=2`; fixtures rebuilt on the real `workspaces/<id>/` layout.
- Call-site **order** asserted against the file (`grep -n` line comparison, loud on missing anchors).
- Same-device check re-expressed as `stat -c %d` on the directories, fail-closed on unreadable.
- Instrument-availability loop (`mountpoint findmnt find stat du`) refuses before any guard runs.
- Enumerate **once** with `-print0`, reused for both the subset proof and the deletion (closes a
  TOCTOU and a newline-in-filename false-pass).
- Nested-mount refusal (`rm -rf` would otherwise descend a bind-mount beneath `$STAGING`).
- Preflight probe fails closed with an unmissable banner.
- **Non-degeneracy floors** in both suites — deleting the whole T4 region previously reported
  `109 passed, exit 0`.
- 13 mutations verified RED, each with a landing assertion against a pristine backup.

## Key insight

**A green mutation battery is evidence about the mutations, not about the tests.** When a
battery arrives with its own matrix ("each assertion proven RED"), that matrix measures the
suite against the author's imagination — and its green is indistinguishable from the green of
genuinely complete coverage. The productive question is never "did my mutations pass?" but
*"what set does this claim quantify over, and where did I only sample it once?"*

Adjacent, and cheap: enumerate the SUT's functions and confirm each appears on the **left of a
call** in the test file. Any zero is an untested function whatever the battery reported.

## Session Errors

1. **`gh issue create --milestone 4` failed** (`could not add to milestone '4': '4' not found`) — Recovery: passed the milestone TITLE. **Prevention:** `gh` matches milestones by title; resolve number→title first.
2. **Wrote a corrupted test file** (garbled text in the final loop) and had to rewrite it. **Prevention:** re-read any file written in one shot before running it.
3. **Miscounted predicate sites** (claimed 6, actual 7). Recovery: my own `assert s.count(old)==N` caught it. **Prevention:** assert counts in rewrite scripts rather than trusting a mental tally.
4. **Used `$WORKSPACES_STAGING` (subshell-only) in outer-shell predicates** → unbound variable, suite ran **zero** assertions. **Prevention:** the non-degeneracy floor now turns "0 assertions" into a loud failure.
5. **Put an apostrophe inside the harness's single-quoted `bash -c` body** → harness syntax error, suite ran **zero** assertions. The harness header documents this exact constraint. **Prevention:** re-read the constraint comment before editing that block; the floor catches the symptom.
6. **Backticks inside a double-quoted `die` string** (`` `exit 0` ``) → command substitution. **Prevention:** never backtick inside double quotes in a message string.
7. **Arithmetic on operator-supplied `CONFIRM_WIPE`** → evaluation hazard. **Prevention:** count by string equality against `"1"`, never arithmetic on env-supplied values.
8. **`stat -c %d` broke every test** — the harness creates `MNT`/`STG` under one scratch dir (same device). **Prevention:** when a guard adds a new instrument, check whether the harness must stub it BEFORE running.
9. **Ran only the two suites I touched**; sibling H17 went RED and review caught it, not me. **Prevention:** learning 7 — grep for suites asserting a changed literal and run every suite registered in the gating workflow.
10. **Background wrapper reported "exit code 0" twice** while the suite was still running / rc missing. **Prevention:** learning 8 — rc file + process check + log growth.
11. **Left an orphan `test-all.sh`** from a timed-out foreground run (two concurrent suites on one worktree). **Prevention:** after a foreground timeout, kill the surviving child before relaunching.
12. **Recorded a mutation as VACUOUS that never landed.** **Prevention:** learning 3 — landing assertion against a pristine backup.
13. **First mutation battery contained a no-op mutation** (deleted only the `echo`, left `exit 1`). **Prevention:** same as 12.
14. **Path-parity regex assumed the env var name equals the local name.** Recovery: the assertion failed loudly by design. **Prevention:** keep "could read the defaults" as an explicit precondition check rather than letting `None` silently skip.
15. **Protocol violation: emitted "Continuing to compound → ship" and then ended the turn.** The operator had to ask whether I had continued. **Prevention:** a phase-complete marker is a checkpoint, not a turn boundary — the next action in the SAME response must be the successor skill invocation. Stating an intention is not performing it.

## Related

- [The harness broke the rule it enforced and the canary could not fail](./2026-07-19-the-harness-broke-the-rule-it-enforced-and-the-canary-could-not-fail.md) — same issue lineage (#6588), the immediately preceding vacuity class
- [A mutation battery only covers what you mutate](./2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md) — the general form; this session is a fresh instance one round later
- [Every hole was a claim quantified over a set sampled once](./2026-07-17-every-hole-was-a-claim-quantified-over-a-set-sampled-once.md) — the unifying frame
- [The fix for an inert monitor shipped a probe that could never fire](./2026-07-16-the-fix-for-an-inert-monitor-shipped-a-probe-that-could-never-fire.md) — fixture models a convenient exit code instead of the real contract
- Issue #6722 — the live ungated-rollback hole this work surfaced and fixed
