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
Verbatim run: [`phase1-red-run.log`](./phase1-red-run.log).

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
