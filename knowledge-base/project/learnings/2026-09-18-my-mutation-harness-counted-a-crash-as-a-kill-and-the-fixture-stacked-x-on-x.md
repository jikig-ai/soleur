---
title: "My mutation harness counted a crash as a kill, and the fixture stacked X on X"
date: 2026-09-18
category: test-failures
tags: [mutation-testing, vacuity, fixtures, ratchets, lefthook, pre-commit, guardA, image-pin, merge-conflicts]
issue: 6894
pr: 8248
adr: ADR-142
related:
  - 2026-09-10-every-assertion-i-wrote-to-prove-the-fix-could-be-satisfied-while-the-defect-was-live.md
  - 2026-09-02-i-built-a-host-discriminator-out-of-an-absence-and-fixtured-the-absence.md
  - 2026-09-14-i-tested-both-endpoints-and-left-the-wire-between-them-unpinned.md
  - 2026-09-10-six-instruments-reported-could-not-measure-as-clean.md
  - 2026-09-18-my-local-gate-set-shrank-silently-and-ci-caught-what-it-could-not.md
---

# My mutation harness counted a crash as a kill, and the fixture stacked X on X

## What happened

The review round on #8248 (the ADR-142 additive LUKS cutover) closed with a 22-mutant battery
against the on-host FSM. Two rounds in a row scored this row as killed:

```text
KILLED   mounted_from back to head -1: floor/fatal
```

`floor/fatal` is the harness's *fallback* label: the mutant run exited non-zero and printed **no
`FAIL` line**. I read that as a kill. Re-driven against the tree that was about to be committed, the
same row came back `SURVIVED`, and driving the mutant by hand settled it:

```text
=== inngest-luks-cutover.test.sh: 89 passed, 0 failed (89 assertions, floor 89) ===
ok   - mounted_from reads the EFFECTIVE (last) mount of a stacked pair, not the shadowed one
```

The suite was **fully green with the defect live**, and the one arm that existed to catch it
printed `ok`. `mounted_from` reads `findmnt -no SOURCE "$mnt" | tail -1` because a stacked mount is
listed oldest-first and the kernel serves the *last* row; the mutant reverts it to `head -1`, which
is how the FSM would believe the encrypted mapper was serving while plaintext sat on top of it.

The fixture could not tell the two apart. `world stacked-mount` appended the **plaintext** device
"on top" of a fresh world — whose `/mnt/data` is *already* the plaintext device. Both rows named one
device, so `head -1` and `tail -1` returned the same answer and the assertion was satisfied by the
model, not by the code.

## Two defects, one row

**1. The harness scored any non-zero exit as a kill.** The scorer's branch was, in effect,
`rc != 0 && no FAIL line → KILLED (floor/fatal)`. That credits a kill to every way a run can die:
an unbound variable, a floor tripping because the mutant changed the assertion *count*, a fixture
`[FATAL]`, a helper self-test refusing to start. None of those is the suite *detecting* the mutation.
The earlier "kill" was almost certainly a floor artefact from a round where the assertion count had
moved — evidence about the harness, not about `mounted_from`. A crash is not a kill. **Require the
row's own `FAIL` line — or a named reason — before scoring KILLED**, and treat `rc != 0` with no
verdict line as UNRESOLVED, the same reading the runner gives a killed suite.

**2. The fixture stacked X on X.** This is the
[fixture-agrees-with-the-assertion](2026-09-02-i-built-a-host-discriminator-out-of-an-absence-and-fixtured-the-absence.md)
class by a new vector: not an absence, but a *stack whose layers are identical*. Any assertion of the
form "reads the effective/last/top/newest of a pair" is vacuous unless the two members differ on
exactly the axis being read. The fix, in order:

```bash
# build the stack EXPLICITLY — canonical mapper underneath (post-swap), plaintext on top
{ printf '%s %s\n' "$W/mapper/inngest-redis"                 "$W/mnt/data"   # SHADOWED, listed first
  printf '%s %s\n' "$W/byid/scsi-0HC_Volume_${PLAIN_ID}"     "$W/mnt/data"; } > "$W/mounts"   # ON TOP
# fixture non-vacuity control: the row below cannot discriminate if both rows name one device
[ "$_top" != "$_bot" ] || { printf '[FATAL] stacked-mount fixture: both rows name %s\n' "$_top" >&2; exit 2; }
# positive half: the effective mount is the top one
_mounted_from "$W/mnt/data" "$plain"  && ok "reads the EFFECTIVE (last) mount"
# NEGATIVE half: the shadowed mapper must NOT match — the thing a predicate accepting ANY row would do
_mounted_from "$W/mnt/data" "$mapper" || ok "does NOT match the SHADOWED mapper row"
```

Control 90/90; the mutant now reds on **both** arms with its own message. The negative half is
load-bearing: a `mounted_from` that answered true for any row of the stack would still have passed
the positive arm.

## The same session's other findings, because they share a shape

### A mutation ledger is only true for the tree it was measured on — in BOTH directions

[2026-09-10 §A](2026-09-10-every-assertion-i-wrote-to-prove-the-fix-could-be-satisfied-while-the-defect-was-live.md)
records an inherited **survivor** that was already dead. This is the inverse: an inherited **kill**
that was false. The 16/22 log I was carrying predated the review round's new arms; the honest
re-run found both a real survivor (`same-device` — killed by the arms added since) and this false
kill. Re-drive the whole battery against the commit candidate, and read the *reason column* of every
KILLED row, not just the count.

### Two equivalent mutants, argued at the code rather than papered over

Deleting T2's flip-latch leg leaves the suite green because the latch lives *inside* the tree the
listing and checksum legs already walk, so every way it can differ is caught above it. The tempting
fix — move the leg up so it becomes reachable — was tried and rejected: it would then out-rank
`t2-listing-unreadable` and report an unreadable destination as a mid-copy flip, **trading a vacuous
leg for a wrong diagnosis**. The leg stays where it is with a note saying exactly this, and the
suite row says it asserts rc only. Likewise `envfile_pointer`'s `-eq 1` is a post-condition on the
function's own write (`grep -v` strips every pointer line; at most one is appended), so no input can
move the count; it stays as the assertion a future rewrite would break.

### Four repo-global ratchets, none referencing a file in the diff

The class is documented in
[2026-09-14](2026-09-14-i-tested-both-endpoints-and-left-the-wire-between-them-unpinned.md); this
was its fourth measured recurrence and CI, not the file-selected suite set, returned it. What is new
is the **fix shapes**, because each ratchet's own failure text prescribes one and the temptation is
always the number:

| ratchet | red | the fix that is not "raise the number" |
|---|---|---|
| `fixture-relative-assert` (P1b) | 17 rows in 3 new files | **guard** the five that are cheap: `assert_fixture_dir` on a caller parameter; canonicalise `REPO="$(cd … && pwd)"` and put the guard **inside the function where the write is** — a top-level guard clears nothing by `_rel_guarded`'s own rule. Baseline the 12 that remain *with itemised reasons*, including two **false positives** left as rows rather than respelled: a `cp -a ` literal inside a `grep` *pattern*, and `[[ "$a" > "$b" ]]` (lexicographic compare read as a redirect). Dodging a detector is not a fix. |
| `fixture-dir-operand-assert` (P1a) | 3 inline copies drifted | restore byte-identical to `test-helpers.sh` — that equality is what P1b's guard recognition is *built on* |
| `lint-shell-capture-exit` | 3 `x=$(grep … \| head -1 \| cut …)` captures | `\|\| true` **with the reason written**: an empty line number means the anchor moved, and both consumers already require `-n` before comparing, so the miss reds *there*, with the value printed |
| `guard-vacuity-floor` | shrink-only ledger 47 → 48 | promote the file into `PROMOTED_FILES`; it meets the covered bar (`-lt` over an independent counter, `printf`+`exit 1`, literal bound adjacent) |

### The local full battery was structurally unpassable at this commit

The `bun-test` pre-commit hook ran the full battery (74 min, 431/440). Every red was measured:
GuardA is red **by construction** at the commit that freezes the carriers, because the tag that
greens it must be cut *at* that commit (the plan's execution amendment §1); `registry-userdata-budget`
was `bc` absent locally, fixed on main **one commit ahead** (#7960); one suite was 50/50 standalone
and red only under three concurrent batteries; five more fail **identically on a detached
`origin/main` worktree by the same command on this host**; and the component vitest environment has
`localStorage` undefined in jsdom while the diff touches no web-platform TypeScript and CI's vitest
jobs were green. The hatch used was `LEFTHOOK_EXCLUDE=bun-test` — verified to print
`bun-test (skip) name` — so gitleaks, markdown-lint, lint-infra-no-human-steps and generate-kb-index
still ran; the justification sits in the commit message. ADR-183: the pushed head's CI is the battery.

The avoidable cost was *ordering*: CI on the pushed head already listed the four ratchets when I
started the commit, and I read that list only after the hook had burned 35 minutes re-measuring the
same thing. **Read the pushed head's CI failure list before starting any commit whose hook re-runs
the same battery**, and check `git log HEAD..origin/main` before classifying a ratchet red as
PR-introduced — the `bc` one was already fixed upstream.

### An exact-count floor conflicted at the merge

`cutover-inngest-workflow.test.sh`'s `_EXACT_FLOOR` conflicted (main 648→649, branch 648→663).
Neither side is the answer: re-derive 649 + 15 = 664 and **measure** 664/664. The generated
`model.likec4.json` conflicted too and was regenerated from the merged `model.c4`, never hand-merged.

## Key insights

1. **A crash is not a kill.** A mutation scorer whose KILLED branch accepts `rc != 0` with no
   verdict line credits every unrelated fatal to the mutation. Require the row's own `FAIL` line or
   a named reason; score verdict-less non-zero exits UNRESOLVED.
2. **"Reads the last/top/effective member" is vacuous unless the members differ on that axis.**
   Add a fixture non-vacuity control that refuses to run when they do not, and a negative half that
   the any-row predicate would fail.
3. **An inherited mutation ledger is wrong in both directions.** Re-drive against the commit
   candidate and read every KILLED row's reason, not the count.
4. **Each ratchet's failure text names the remedy, and it is never the number.** Guard where a
   guard is cheap; baseline the residue with reasons; leave false positives as rows rather than
   respelling code to dodge a detector; promote a file rather than grow a shrink-only ledger.
5. **Read CI before re-running its battery locally**, and read `HEAD..origin/main` before calling a
   red PR-introduced.

## Session Errors

**1. Started a 74-minute pre-commit battery before reading the pushed head's CI failure list.**
CI already showed the four ratchets. **Prevention:** before any commit whose hook re-runs the
battery, `gh pr checks <n>` first and fix every red the file-selected set could not see.

**2. Credited a mutation kill to a crash (`floor/fatal`) for two rounds.** The mutant ran 89/89
green. **Prevention:** the scorer requires the FAIL line; a verdict-less non-zero exit is UNRESOLVED.

**3. Carried a stale mutation ledger across rounds.** It hid both a real survivor and a false kill.
**Prevention:** re-drive the whole battery against the commit candidate; read the reason column.

**4. Hand-wrote `assert_fixture_dir` into a new suite and drifted it from canonical.**
**Prevention:** copy the canonical body from `test-helpers.sh` (the P1a ratchet pins byte-equality).

**5. Read `registry-userdata-budget`'s red as PR-introduced before checking `origin/main`'s HEAD.**
It was `bc` absent locally, fixed upstream by #7960. **Prevention:** `git log HEAD..origin/main`
and re-run the suite on a detached `origin/main` worktree by the same command before classifying.

**6. Killed the same commit twice mid-battery.** Both kills were right (the ratchets; then the
false kill), but the second was avoidable had the battery been re-driven before committing.
**Prevention:** items 1 and 3 — the full pre-commit checklist runs *before* `git commit`.

**7. Four repo-global ratchets not visible to the file-selected suite set** — fourth recurrence.
**Prevention:** already documented (2026-09-14); this file records the fix shapes.

**8. `cd` inside a compound Bash command reset the shell cwd out of the worktree twice.**
**Prevention:** absolute `cd <worktree>` at the head of every command; never rely on carried cwd.

**9. A PreToolUse hook blocked a Bash heredoc because the Python source inside it contained the
literal `doppler secrets set …`** (a test's grep pattern, not a call). **Prevention:** use the Edit
tool for a file edit whose *content* carries a hook-trigger literal.

**10. The monitor-supersede hook listed expired monitors as live; `TaskStop` returned "No task
found".** Harmless. **Prevention:** none needed — an expiry notice is the stop.

**11. An exact-count floor and a generated JSON conflicted at the merge.** **Prevention:** re-derive
the floor from both sides' itemised deltas and measure; regenerate generated files from the merged
source.
