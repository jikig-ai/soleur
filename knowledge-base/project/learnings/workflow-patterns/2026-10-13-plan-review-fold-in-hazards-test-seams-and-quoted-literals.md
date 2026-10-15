---
title: "Plan-review fold-in hazards: capture-vs-repoint seams, extension-class subsumption, and quoting-carrying-semantics"
date: 2026-10-13
type: learning
domain: workflow-patterns
source_issue: "#10117"
related_artifacts:
  - knowledge-base/project/plans/archive/20261014-231240-2026-10-13-fix-edge-declaration-coverage-residuals-plan.md
---

# Learning: plan-review fold-in hazards — seams, subsumption, quoting, seeded columns

## Problem

The #10117 plan went through advisor + spec-flow + a six-seat review panel
(DHH, Kieran, code-simplicity, architecture-strategist, spec-flow re-check, CTO
devex). Four defect patterns recurred across seats — each is a plan-authoring
trap that survives prose-only review and only falls to reviewers who re-execute
the mechanism mentally against the code.

## Key patterns (each was caught by ≥2 independent seats)

1. **"Capture ONCE" contradicts a per-row injection seam.** A plan that says
   "capture `git ls-files` once into a variable, mutation arms set `_TH_REPO`"
   is vacuous: a top-level capture runs before any row can repoint the seam.
   The working shape is a *function* (`_th_ls_files()` honoring
   `${_TH_REPO:-$REPO_ROOT}`) invoked per-evaluation — "shares the producer"
   means same function, not same variable. The seam also needs confinement
   (`_TH_REPO` must resolve under `$TESTROOT`), or an accidental env-set
   retargets the *whole* census at a populated sibling checkout.

2. **Extension classes subsume.** A complement filter written `\.sh$` matches
   `x.test.sh` — so a mutation "drop the `.test.sh` arm" has nothing observable
   to drop, and a "must flag `.sh`" row can't discriminate. Filters over
   extension sets must classify *disjointly* (last-two-dot `test.sh` vs
   last-dot `sh`-but-not-`test.sh`) or the extension-completeness mutation is
   vacuous theatre.

3. **Bash quoting carries the semantics.** Two places in one predicate:
   `[[ "$tail" == "*${ext}" ]]` — quoted RHS is a literal compare, unquoted is a
   glob match that silently restores the bug; and `${_m#"glob:$2/"}` — unquoted,
   `$2` becomes a *pattern* inside `#` and mis-strips roots containing `?`/`[`.
   A fix whose correctness lives in quote placement must be stated as an inline
   code comment — it looks like a bug to the next reader.

4. **"Never hand-edited" vs the seeded column.** A generated baseline whose
   emitter carries a classification column *forward* can never mint the first
   classification — the seed must be a hand-edit. State the split explicitly:
   row *membership* is regen-only; the classification column is the one
   sanctioned hand-edit. Better still: emit `UNCLASSIFIED` for rows absent from
   the old baseline so the shape-check (c1) makes the convention self-enforcing.

## Session-error inventory item

The batch-edit script aborted twice because `old_string` was reconstructed from
memory rather than read from the file immediately before composing the edit —
same class as the plan-time "paraphrase-without-verification" Sharp Edge,
applied to my own edits. Rule: for scripted multi-edits, `rep()`-style
functions must assert-and-fail AND the batch must re-read targets first; an
assert thrown before `write_text` discards all prior edits in the script.

## Also captured (smaller)

- ADR *intra-file* decision numbers are not covered by `check-adr-ordinals.sh`
  (filename ordinals only) — hand-verify the next free number (the plan's
  "decision 23" collided with existing 23-26).
- `_TRACKED`-style lazy globals: the accessor is "materialize via any call +
  filter the dict", never "call the predicate for a member list" — read the
  callee's contract before describing the seam.
- Trailing-slash dir elements, embedded LF (not just TAB), and residual `./`
  after a single-pass strip were all silent-mislead classes a minimal `${p#./}`
  fix misses — normalize to fixpoint, then reject residue.

## Tags

plan-review, test-machinery, bash-quoting, mutation-matrix, baseline-ratchet,
vacuous-mutations, paraphrase-without-verification
