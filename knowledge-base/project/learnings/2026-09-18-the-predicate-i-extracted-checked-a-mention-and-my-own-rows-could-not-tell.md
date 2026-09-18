---
module: System
date: 2026-09-18
problem_type: test_failure
component: testing_framework
symptoms:
  - "stripIsApplied returned true with the strip local passed as a templatefile var, as the third argument, or inside a quoted string"
  - "chain.slice(1).every and a dropped inngest chain link left the suite 57/57 green"
  - "git-data wrapper pointed at the ADR-152 sibling payload local stayed green while modelling a #cloud-config-eating strip"
  - "fixture-relative-assert ratchet red the whole session; my loop printed rc=0 from basename's status"
  - "a mutation battery reporting 10 ok / 0 problems had no row through its own row runner"
root_cause: logic_error
resolution_type: test_fix
severity: high
tags: [mutation-testing, extraction, hcl, cloud-init, user-data, guard-vacuity, fixture-direction, inherited-claims, exit-code]
synced_to: [work, review]
---

# The predicate I extracted checked a MENTION, and my own rows could not tell

**Issue:** #7968 · **PR:** #8338 · **Batch:** step 3 of the Inngest cutover follow-through.

## Problem

Three near-verbatim helper pairs in `plugins/soleur/test/cloud-init-user-data-size.test.ts` were
collapsed into `extractStripRegex` and `stripIsApplied`. The extraction was semantics-preserving
(byte parity 0 on all three hosts) and shipped with ten synthetic fixture arms and a committed
mutation battery reporting `10 ok, 0 problem(s)`. A 10-seat review found 25 findings that rolled
up to three structural gaps, none visible to the battery:

1. **The predicate checked a mention in the balanced span, not the argument.** Every per-host copy
   had `/local\.<name>/.test(span)`; the shared function inherited it. Measured: the local passed
   as a templatefile var (`{ s = local.x_rationale_strip }` — the M14 shape with the `replace()`
   wrapper kept), as `replace()`'s THIRD argument, or inside a quoted string all returned `true`.
   Trailing `# was local.x…` notes and `/* */`-commented renders also returned `true`, because
   `stripHclLineComments` stripped line-leading comments only.
2. **Every negative fixture pointed one way.** A8 broke the LAST chain link only, so
   `chain.slice(1).every(...)` and a wrapper that dropped link 1 were green; A9 put the decoy
   mention AFTER the anchor only. The git-data host had no `#cloud-config` arm, so pointing its
   extractor at the sibling `git_data_rationale_strip` (ADR-152's payload local, which eats
   `#cloud-config`) modelled a boot-bricking strip inside budget.
3. **The battery self-tested its verdict function but never its row runner.** H1/H1b/H4 drove
   `expect_red` directly; `survived()` and `landing()` were never called on a clean run, so a
   `row_red` whose verdict branch is `if true`, or a `survived()` that counts into `PASS`, exited 0.

## Solution

- `stripIsApplied` now locates the anchor's own `replace(` in the anchor-start..span-end region,
  splits its arguments at depth-0 commas with a string-aware walk, and requires `args[1] ===
  \`local.${localName}\``. `stripHclLineComments` strips all three HCL comment forms, string-aware
  and line-scoped. Parity re-measured: 0 delta.
- Arms: A1b (trailing-comment decoy definition), A6b/A6c (block/trailing comment fail-opens), A8
  per link, A9b (mention before the anchor), A9c (an earlier unrelated `replace()` using the
  local), A11 ×3 (var / third arg / quoted string), A12 (identifier guard); real-tree arms for the
  git-data `#cloud-config` survival, the inngest link-1 bypass, and a walker requiring a wrapper
  pair for every render-wired `*_rationale_strip` local.
- Battery: rows R5/R7/R8/R9; K1/K2 drive `row_red` with a known survivor and a known landing
  failure and net them out; `expect_red` checks `Ran N` and the summary `error(s)` line before the
  arm grep and prints bun's lines inline; `PRISTINE_TOTAL` measured, fixture describe pinned by a
  `-t` run; canonical `assert_fixture_dir` on the redirect operand; `--preload git-tripwire.ts`.
- Verified on scratch copies: W4/W6/W7 wrapper drifts and N2/N9/N11 harness mutants all die.

## Key Insight

**A mutation battery answers "can the guard fail?"; the review question is "is the predicate the
property?" — and when a stronger predicate lands mid-review, every row written against the weaker
one must be re-derived.** R6 and R7 SURVIVED after the positional check landed, not because the
guard had a gap, but because the positional check now refused the fixtures those rows relied on.
The fix was new fixtures on the axis the positional check does not cover (an earlier unrelated
`replace()`; a trailing-comment DEFINITION for the extractor), not weaker rows.

Two companions: (a) **fixture DIRECTION is a coverage axis** — "requires every chain link" with one
link broken pins one link; (b) **a battery's row runner is a guard too** — K1/K2 are the positive
controls the verdict helpers had and the runner did not.

## Session Errors

1. **Inherited narrative pasted unfalsified** — the docblock said "the third copy (#7458) shipped
   without the strip"; the issue body says it was the inngest pair in #7965's first commit, caught
   in review. Three seats converged. One day after routing "falsify a plan's LABELS and
   MECHANISMS" I falsified the numbers and copied the sentence. **Prevention:** for every `#N`
   the diff's prose attaches to a claim, run `gh issue view N --json body | grep <claim noun>`
   before writing it; a citation is a claim about what that artifact says.
2. **`echo "$(basename $t) RC=$?"` reported `basename`'s status** — `fixture-relative-assert` was
   red on the first run and I recorded rc=0; the log had `FAIL` lines I never read. The trap is
   documented in `work/SKILL.md`. **Prevention:** `rc=$?` on its own line immediately after the
   command, and grep the log for `FAIL` regardless of rc — a green rc with FAIL lines is a
   misread instrument, not a pass.
3. **Walker pin grepped a `(pass)` line bun never prints** (bun 1.3.14 prints `(fail)` only).
   **Prevention:** before asserting on a runner's output line, produce it once on a known input.
4. **Positional-check search started at the span's `(`**, excluding the anchor's own `replace`
   token; 5 real-tree arms red. **Prevention:** when a region is sliced from an offset, state
   which token the offset is AT and which it is AFTER.
5. **Two battery rows SURVIVED after the predicate strengthened** (R6/R7) — fixture gaps read as
   guard gaps until labelled. **Prevention:** after any predicate change, re-ask per row "what
   input does this row's fixture rely on, and does the new predicate refuse it for another
   reason?"
6. **Inline `case … /*)` guard on a redirect operand** — the P1b scanner recognises only the
   canonical `assert_fixture_dir` and its docstring says why. **Prevention:** read the scanner's
   `_rel_guarded` docstring before choosing a guard shape; copy the canonical helper.
7. **A two-file Python edit script asserted mid-way**, writing the `.ts` and not the `.sh`.
   **Prevention:** one script per file, or assert all anchors before any write.
8. **Verification mutant `[] /*[` broke syntax** and reported `1 fail` with no arm line.
   **Prevention:** a mutant must compile — read the `error:` line before reading the count.
9. **Mutant copies of the battery placed in the tracked test dir** (`.mutbat-*.test.sh`) so
   `SCRIPT_DIR` resolved; removed after. **Prevention:** copy the SUT beside the mutant in a
   scratch dir instead of the mutant beside the SUT.
10. **Shard gate refused (rc=4, two sibling runs)** — substitute suites derived from consumers.
    **Prevention:** none needed — the refusal is the designed outcome; derive the substitute set
    from `git grep -l` over the changed basenames plus the repo-global ratchets.
11. **Every commit under `LEFTHOOK=0`** — sanctioned; the linters ran by hand, and #2 is what
    hand-running looks like when the rc is read wrong. **Prevention:** when bypassing lefthook,
    run each linter with `rc=$?` on its own line and record the rc file, never an inline echo.
12. **Forwarded from plan phase:** first deepen-edit script aborted on a mismatched anchor;
    re-run clean. **Prevention:** assert every anchor before the first write (same as #7).

## Related

- `2026-09-18-three-sentences-i-pasted-from-the-plan-were-inherited-not-measured.md` — the
  learning routed the day before; error #1 is its recurrence one level down (a sentence in a
  docblock instead of a plan).
- `2026-09-10-my-battery-killed-all-26-and-could-not-see-any-of-the-20-escapes.md` — mutation vs
  escape; this session's rows R6/R7 are the inverse (a stronger predicate voids a row).
- `2026-07-21-my-fixture-set-had-a-direction-and-both-batteries-were-blind-to-the-other-one.md`.
- `2026-09-07-every-instrument-i-built-to-check-my-own-work-could-not-tell-clean-from-never-ran.md`.
