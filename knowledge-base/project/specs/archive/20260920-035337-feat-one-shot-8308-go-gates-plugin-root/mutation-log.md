# Mutation log — #8308 (AC3)

Battery: `/var/tmp/mutate.py` (session-local). It restores from a **pristine copy** taken before
row 1, never `git checkout` — which restores to HEAD, a different thing while a fix is in flight —
and every row asserts its mutation **landed** against that copy, because a mutation that does not
land reports the BASELINE and that is byte-indistinguishable from a pass.

`SOLEUR_GO_GATES_SKIP_H3=1` is exported for the battery so 27 rows do not spawn 27 headless Claude
sessions. Row 17 targets the skip logic itself, so the opt-out does not exempt it.

## Phase 1 — the pre-fix red run (the suite can see the defect it was written for)

`plugins/soleur/test/go-session-gates.test.sh` against unmodified `go.md`:

```
go-session-gates.test.sh: 72 passed, 60 failed, 132 assertion(s) executed (floor 110)
```

Red rows: R1, R2, R3, R3b(0), R3c, R4(partial), R5b, R5c, R6, R6b, R6c, R7, R8, R9, H2.
Verbatim run: [`phase1-red-run.txt`](./phase1-red-run.txt).

`plugin-root-anchoring.test.ts` against the same tree: P1, P1b and P6 red, and **P6's own
`checked` floor dropped 8 → 6** — the measurement that `ROOT_ASSIGN_LITERAL` was load-bearing
rather than decorative. `workflow-fidelity.test.ts`: 1 failed / 82 passed.

## Control

```
[CONTROL] guard1 rc=0 fails=0 | guard2 anchoring=0 wf=0
```

A red control voids every row below it, so it is read first.

## Guard 1 — go-session-gates (19 rows)

| # | Mutation | Expected | Result |
|---|---|---|---|
| 1 | revert arm 1 to the #8061 form in all three fences | RED | RED |
| 2 | delete the `SOLEUR_PLUGIN_ROOT_RESOLVE` echo line | RED | RED |
| 3 | remove the `name=soleur` conjunct | RED | RED |
| 4 | insert a CWD default ABOVE the identity check | RED | RED |
| 5 | fix 0.0 and 0.5, leave Step 0 on the #8061 form | RED | RED |
| 6 | change the delivered token to the unbraced form | RED | RED |
| 7 | move Step 0's dispatch above the identity check | RED | RED |
| 8 | copy the Devin cache arm into Step 0's fence | RED | RED |
| 9 | delete Step 0's session-class gate | RED | RED |
| 10 | rename `worktree-manager.sh` without updating the operand | RED | RED |
| 11 | add `set -u` to a fence | RED | RED |
| 12 | replace `-exec grep` with a GNU-only `xargs -r` | RED | RED |
| 13 | interpolate the resolved path into the marker | RED | RED |
| 14 | rename a gate heading so the extractor finds 2 fences | RED | RED **(after a fix — see below)** |
| 15 | make `deliver()` also replace the `:-` form | RED | RED **(after a fix)** |
| 16 | pre-seed the assertion counter to the expected total | RED | RED |
| 17 | make H3 print `SKIP-DECLARED` unconditionally | RED | RED **(after a fix)** |
| 18 | MUST-PASS: `GATE=` two lines above the anchor, extra blank line, different comment text outside the anchors | PASS | PASS |
| 19 | MUST-PASS: R6b's decoy-claiming-`soleur` row | PASS | PASS |

## Guard 2 — command-surface anchor form (8 rows)

| # | Mutation | Expected | Result |
|---|---|---|---|
| 1 | reintroduce the #8061 form in `go.md` | RED | RED |
| 2 | introduce an unbraced `$CLAUDE_PLUGIN_ROOT` in `sync.md` | RED | RED |
| 3 | introduce `${CLAUDE_PLUGIN_ROOT:?msg}` in `help.md` | RED | RED |
| 4 | add a FOURTH command file carrying the #8061 form | RED | RED |
| 5 | harness: empty `COMMANDS_DIR` | RED | RED |
| 6 | harness: remove the #8061-form entry from P1b's own fixture array | RED | RED |
| 7 | harness: leave the P5 floor unraised after adding the control | RED | RED |
| 8 | MUST-PASS: the token inside a comment plus a `${ROOT}` operand | PASS | PASS |

Final: **27/27 rows behaved as specified**, `[RESTORE CHECK] guard1 rc=0 | guard2 anchoring=0 wf=0`,
and every tracked file byte-identical to its pristine copy.

## The three rows that SURVIVED on the first pass, and what each was

A surviving mutant has two readings — the fixtures do not exercise the property, or the mutant is
equivalent. None of these three was equivalent.

- **Row 14 — a GUARD gap.** `extract_fence` matched its heading anchor as a **prefix**
  (`index($0, anchor) == 1`), so `## Step 0.5: Cloud Mode detection (renamed)` still matched, the
  extractor still found three fences, and R10's count check could never fire. Now whole-line
  equality.
- **Row 15 — a FIXTURE-SPACE gap, which a mutation battery structurally cannot detect.** The Arm 5
  probe carried no `${CLAUDE_PLUGIN_ROOT:-…}` row, so widening `deliver()` to also replace that
  form perturbed nothing the fixture instantiated. The battery scores the SUT *through* the
  fixtures it already has, so no row could have caught it. Fixed by extending the probe, re-running
  it against the real loader, and asserting the new line in H1.
- **Row 17 — the shipped shape WAS the mutation.** H3 was gated on an opt-**in**
  (`SOLEUR_GO_GATES_H3=1`), so its skip did not derive from `command -v claude` at all; the row
  changed nothing that was not already true. Now an opt-**out** with a truthful reason string, and
  the skip arm FAILS if it claims the binary is absent while `command -v` finds it.

Guard 2 row 2 also did not fire on the first pass — a **battery-harness** error (an anchor string
that does not exist in `sync.md`), caught by the battery's own did-the-mutation-land assertion
rather than reported as a guard result.

## Lint counts (AC15)

```
with this plan:      scanned 1576 plan file(s), 33 with a Guard Contract, 79 guard entries
plan file removed:   scanned 1575 plan file(s), 32 with a Guard Contract, 77 guard entries
```

One more file, two more guard entries — the delta the plan predicted. The invariant is the delta,
not the literals.

## Round 2 — the 11-seat review panel (2026-09-20)

The first battery scored 27/27 and was measuring the axes its author imagined. The panel
enumerated the axes it never edited, and every merge-blocking finding was in this PR's own
verification rather than in the fix.

### The axis the first battery never touched: the deciders' own branch

`pass()`/`fail()` had a control (block `L`). That proves DISPATCH. `want_in`, `want_not_in`,
`want_eq`, `check_r8` and `check_r9` each decide a branch and THEN call `pass()`, so a decider
that always passes appends a genuine `PASS` row and counters, ledger and floor all reconcile.

| Mutation | Before (measured) | After block L2 |
|---|---|---|
| `want_in() { ck; pass "$3"; }` | GREEN 137/0/137 | rc=2, named FATAL |
| `want_not_in() { ck; pass "$3"; }` | GREEN 137/0/137 | rc=2, named FATAL |
| `want_eq() { ck; pass "$3"; }` | GREEN 137/0/137 | rc=2, named FATAL |
| `case "$1" in` → `case "$1$2" in` (one token, 21 rows blind) | GREEN 137/0/137 | rc=2, named FATAL |
| `check_r8` body → `ck; pass` loop | GREEN 137/0/137 | rc=2, named FATAL |
| `check_r9` body → `ck; pass` loop | GREEN 167/0/167 | rc=2, named FATAL |

**The composite result, before the fix:** three decider bodies gutted **plus** a ban-evading
revert of the resolver (`XROOT="${CLAUDE_PLUGIN_ROOT}"; ROOT="${GROK_PLUGIN_ROOT:-$XROOT}"`) —
the defect this PR exists to fix, live — reported `137 passed, 0 failed`, rc=0.

### Other axes the panel added, each now mutation-proven

| Axis | Mutation | Before | After |
|---|---|---|---|
| TS scan wiring | P1b scan body → `return []`, real violation planted | GREEN 27/27 | rc=1, 2 failed |
| TS predicate | revert `readsRootUnsafely` to the 2-clause form | GREEN | rc=1, 2 failed |
| TS anchor | `XROOT` indirection revert of the resolver | GREEN 83/0 | rc=1 |
| Set cardinality | add a 4th gate fence to `go.md` | GREEN 137/0/137 | rc=1, named |
| Set cardinality | shorten `GATE_NAMES` to 2 | raw `unbound variable` after 100+ PASS rows | rc=1, named |
| SUT (the P1) | revert the `.mcp.json` write-then-rename | no row existed | rc=1, 2 failed |
| SUT | restore the duplicate `absent-from-verified-root` marker | no row existed | rc=1, named |

### Predicate bypasses found by measurement, not by mutation

A mutation battery scores the SUT through the fixtures it already has, so it cannot see a
fixture-space gap. These were found by feeding the PRISTINE predicate a corpus it should refuse:

| Shape | Old predicate | Tightened |
|---|---|---|
| `${CLAUDE_PLUGIN_ROOT-./plugins/soleur}` (colon-less — the #7442 class) | NOT flagged | flagged |
| `${CLAUDE_PLUGIN_ROOT:=./plugins/soleur}` | NOT flagged | flagged |
| `$(printenv CLAUDE_PLUGIN_ROOT)` | NOT flagged | flagged |
| `ROOT="${CLAUDE_PLUGIN_ROOT}"` … later `ROOT="${GROK_PLUGIN_ROOT:-$ROOT}"` | NOT flagged | caught by the new `workflow-fidelity` negative |

### Instrument notes

Two rows in this round initially reported a FALSE result and were re-run: one `perl`-style
anchor did not land (the script asserts before its single write, so the whole batch was
discarded while the suite reported its previous green — indistinguishable from a pass), and one
vitest verdict grep was defeated by ANSI codes and returned empty for every arm. Both were
caught by requiring the mutation to be asserted landed and by reading the exit code rather than
a parsed summary line.

## Round 3 — the pre-ship advisor consult (2026-09-20)

Three defects found AFTER the 11-seat panel had finished, all in code this PR authored, all
fixed inline. Two got rows; the third is stated as uncovered rather than implied to be covered.

| # | Defect | Fix | Row | Mutation | Result |
|---|---|---|---|---|---|
| 3.1 | `reason=mcp-json-absent-on-main` asserted one of three possible causes for every `git show` failure — AP-021, the rule this file's other markers enforce. The adjacent comment enumerated the other two. | measure: `mcp-json-no-local-main` / `mcp-json-absent-on-main` / `mcp-json-read-failed rc=<n>`, with `$?` captured before `rm` overwrites it | `R3g` | collapse the three arms back to the single `mcp-json-absent-on-main` echo | **RED** — exactly 2 assertions: `R3g: names the missing branch` (missing) and `R3g: and does NOT claim main lacks the file` (present). 153 passed / 2 failed. |
| 3.2 | the `.mcp.json` restore was nested inside `if [ -f worktree-manager.sh ]`, so a verified-but-torn root missing only that script skipped the restore and the only marker named the reaper — #8308's own coupling in miniature | make the restore a SIBLING of the reaper arm | `R3f` | re-gate only the restore on the reaper's presence (`[ -f … ] && git show …`) | **RED** — exactly 1 assertion: `R3f: the restore ran anyway`. 154 passed / 1 failed. |
| 3.4 | `SESSION_VERDICT="$(… \| head -1)"` assumes the classifier leads with the verdict. R2 drives the real one-line script and R3c a one-line stub, so neither can tell `head -1` from `tail -1` — both pass under either. | none needed; the row is the fix | `R3h` | `head -1` -> `tail -1` in go.md | **RED** — exactly 2 assertions: `R3h: a leading 'local' verdict proceeds despite trailing output` (missing `STUB_WORKTREE_MANAGER`) and `R3h: and the trailing line is not read as the verdict` (present `reason=cloud-session`). 155 passed / 2 failed. |
| 3.3 | a failed `mv` left `.mcp.json.soleur-tmp` in the customer's worktree with no output | `reason=mcp-json-rename-failed` + `rm -f` | **none** | — | **NOT COVERED.** Driving a failed rename needs a read-only fixture directory. Recorded as a gap rather than left to be inferred from the two rows beside it. |

**Row 3.4 was an assumption, not a defect.** `head -1` is correct today; what was missing was
anything that could tell it from `tail -1`. Both existing classifier fixtures print exactly one
line, so the two spellings are indistinguishable to the suite — the classic one-element-fixture
blind spot, and the reason the new stub prints the verdict FIRST and noise after.

**Why no row saw 3.2 before.** `R6c` for the session-start gate asserts the reaper did NOT
dispatch and says nothing about `.mcp.json`, so decoupling the restore left the suite
byte-identical at `149 passed, 0 failed`. That is the same shape as round 2's disarmable
deciders: a green suite over a changed property.

Control before each mutation: green. Restore after each: `cmp -s` byte-identical against a
pre-mutation copy, asserted rather than assumed.

Assertion floor raised 147 -> 155 in the same edit (the H3-SKIPPED total; H3 running adds two,
for 157). Raising it is part of adding a row.
