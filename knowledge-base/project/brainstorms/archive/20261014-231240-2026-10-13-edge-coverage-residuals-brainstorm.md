---
title: "Edge-declaration coverage residuals — covers() tail-blindness, --paths normalization, census matchability, root-anchored gap detection"
date: 2026-10-13
issue: 10117
related_issues: [9969, 9307, 8621, 9323]
related_adrs: [ADR-242, ADR-262]
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Brainstorm: edge-declaration coverage residuals (#10117)

## What We're Building

Four residuals from the PR #10088 review (fix for #9969 — `glob:` edges for whole-tree corpus suites),
plus a fifth surfaced in an issue comment — all in the repo's affected-suite selection machinery
(`scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh`, `scripts/test-all-affected.test.sh`,
`scripts/lint-orphan-test-suites.sh`, `scripts/test-affected-kb-consumers.test.sh`):

1. **`covers()` dir-ref extension blindness** — `scripts/test-affected-kb-consumers.test.sh:287-296`.
   A `glob:<head>/**.<ext>` edge marks a directory ref under `<head>` covered iff the paths nest,
   regardless of whether the glob tail's extension class can match the charged file classes under the
   ref. The committed baseline now asserts coverage that does not exist for at least the 5 lint-orphan
   rows (bounded: ledger-only; runtime selection on `main` is unchanged).
2. **Root-anchored grammar gap** — a dir-less `x.test.sh`/`x.sh` at repo root is inside the
   `git ls-files` corpus but inexpressible in `glob:<dir-head>/<tail>` (the head must be
   `/`-terminated). An extension would touch the "ONE doctrine, FIVE sites" malformed-shape invariant
   (ADR-242 decision 22).
3. **`--paths=` `./`-spelling** — `./knowledge-base/x.test.sh` defeats every anchored edge at the
   `_PRINT_PATHS`→`_diff_names` boundary (`scripts/test-all.sh:2096`); print-only diagnostic, silent
   no-match.
4. **Census predicate `_th6_root_covered`** — `scripts/test-all-affected.test.sh:3036-3044` anchors
   the tail on string suffix `*"$3"` rather than matchability: `glob:docs/x.sh` (literal-in-glob
   spelling) and subset tails (`glob:root/**x.test.sh`) satisfy the census without covering the class.

Verified premise (2026-10-13): #10088 MERGED, #9969 CLOSED, #9307 OPEN umbrella; the #9969 plan
(`knowledge-base/project/plans/2026-10-12-fix-affected-edges-under-cover-siblings-plan.md`) documents
the residuals and the deferred census-witness advisory.

## Why This Approach

All four technical forks were **ruled by `soleur:engineering:cto`** (domain-leader spawn), corroborated
by repo + learnings research:

- **Item 1 — enumerate live dir members, all-containment.** `tracked()` already materializes the
  `git ls-files` set for `knowledge-base/` (the oracle is kb-scoped, so that coverage suffices). A dir
  ref is covered iff every tracked member under it `fnmatchcase`s the glob. Any-intersection was ruled
  out — it is a weaker form of the same hole. Evidence threading (scan→FORMS→suite_refs pipeline
  change) was ruled out: more churn, same verdict — a bare dir literal's charged class is genuinely
  "all of it."
- **Item 2 — detection row, not grammar extension.** Measured latent: zero root-level
  `*.test.sh`/`*.sh` exist today (`git ls-files | grep -cE '^[^/]+\.(test\.sh|sh)$'` → 0), and
  `SUITE_GLOBS` cannot discover one anyway — the gap is consistent with registration reality. A grammar
  extension touches five doctrine sites in three languages plus an ADR-242 amendment for zero current
  members. A census-adjacent probe (`git ls-files | awk -F/ 'NF==1 && corpus-ext'`) converts the silent
  gap into a loud gate at ~1-site cost.
- **Item 3 — normalize at ingestion.** Reuse `_affected_normpath` (`test-all.sh:2855`, the
  `${_NP#./}` strip + bounded `seg/../` collapse) on each `_PRINT_PATHS` element once at line 2096;
  the forwarded enumerate child (line 3834) inherits it. Real git output never emits `./`, so the
  normalize direction cannot narrow a true diff. Reject `../` outright.
- **Item 4 — matchability, not string suffix.** The witness-arm shape already recorded as the
  prevention seat's top candidate (2026-10-10 learning): synthesize the canonical member
  `root/x<corpus-ext>` and evaluate `[[ == ]]` against each `glob:` tail — preserving the current
  predicate's two properties (file-literal exclusion, wrong-extension decline) while closing the
  literal-in-glob and subset-tail escapes.

## Key Decisions

| Decision | Choice |
|---|---|
| Scope | All four residuals authorized by the operator, 2026-10-13 (full scope) |
| Item 1 mechanism | Enumerate live dir members via `tracked()`, **all-containment** — Ruled by CTO agent |
| Item 2 mechanism | Detection row beside th6/`_TH_ROOTS`; grammar extension **deferred until trigger** (first dir-less corpus file lands, i.e. the detection row fires) — Ruled by CTO agent |
| Item 3 mechanism | `_affected_normpath` per `_PRINT_PATHS` element at the `_diff_names` boundary; reject `../` — Ruled by CTO agent |
| Item 4 mechanism | Witness-shape matchability probe (synthesize `root/x<tail>`, `[[ == ]]` evaluation) — Ruled by CTO agent |
| Packaging | **Two independent PRs** targeting `main` — PR-A: items 3+4 + item-2 detection row (clean hardening); PR-B: item 1 `covers()` all-containment + baseline regen + per-row dispositions. Stacked PRs considered and rejected (adds a merge-order dependency where none exists; one-PR-review-by-commit was the closer fit to the operator's ask). Operator decision, 2026-10-13 |
| Item-1 dispositions | Baseline regen will re-surface the ≥5 lint-orphan rows (floor — other suites' dir refs may join). Disposition per row is baseline-row + comment, **not** edge widening (a `knowledge-base/legal/` dir edge would re-open the over-coverage #9813 closed) — ruled at plan time per row |
| `_affected_glob_split` extraction | Stays deferred — its trigger is "next grammar touch" and the detection row is not a grammar touch |
| Productize candidate | none (one-off machinery hardening) |

## User-Brand Impact

- **Artifact:** the affected-suite selection machinery and its coverage oracle ledger
  (`scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh`,
  `scripts/test-affected-kb-consumers.test.sh`, `scripts/lint-orphan-test-suites.sh`).
- **Vector:** a coverage predicate weaker than matchability reads green while a suite declines on a
  diff that should have selected it — the defect surfaces at CI instead of commit time, and for the
  legal-corpus gates this machinery guards (`lint-legal-*`, `probe-legal-corpus-truth`), silent
  under-coverage is the failure class where a register diff ships without its required gate.
- **Threshold:** `single-user incident`.

## Open Questions

- Item-1 dispositions: the exact reappearing-row set is unmeasured until baseline regen (≥5
  lint-orphan rows is the floor). Plan must enumerate them and rule each: baseline row + comment vs.
  genuine covering edge.
- Where the item-2 detection row lives: th6-family row in `test-all-affected.test.sh` beside the
  live `_TH_ROOTS` derivation (recommended — same lifecycle) vs. a census arm in
  `lint-orphan-test-suites.sh`.
- Sibling coordination: #8621 (selector convergence) may relocate `--paths` handling — land item 3
  first or coordinate; #9323 (path-gate self-test mutation batteries) overlaps item-4 territory —
  item 4 should ship its own mutation rows consistent with that direction.
- The census **dead-edge direction** (a diff deleting a declared element's last member moves a
  verdict without selecting it) remains deferred under the witness-arm advisory — outside #10117's
  four items.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product

**Summary:** Near-zero product impact — repo-internal test machinery, not shipped to installs
(published plugin is `plugins/soleur/` only); worst case is a deferred CI signal, never a shipped
defect. The `p3-low`/`chore` labels are correct; sequencing is the live question, not product scope.

### Legal

**Summary:** No legal surface — no PII, schemas, auth, regulated data, or distributed-artifact
concern; `soleur:gdpr-gate` not invoked. One advisory: the fail-toward-coverage doctrine this work
preserves is what keeps the legal-corpus gates from being silently skipped — protective direction.

### Engineering

**Summary:** Items 3+4 are hours-scale clean hardening; item 1 is medium risk via baseline-regen
dispositions; item 2's grammar extension is not worth five-site churn for zero current members —
ship a detection row and revisit on trigger. Separate PRs by risk class; `_affected_glob_split`
extraction stays deferred with the grammar itself.
