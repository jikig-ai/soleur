---
title: "Edge-declaration coverage residuals — oracle dir-ref containment, census matchability, --paths normalization, root-gap detection"
status: specified
issue: 10117
brainstorm: knowledge-base/project/brainstorms/2026-10-13-edge-coverage-residuals-brainstorm.md
branch: feat-10117-edge-coverage-residuals
pr: 10190
date: 2026-10-13
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Spec: edge-declaration coverage residuals (#10117)

<!-- archival of this spec dir is deferred until after plan/work/ship — it is the live input to the pending plan phase -->

## Problem Statement

The PR #10088 review (fix for #9969 — `glob:` edges for whole-tree corpus suites) closed its probed
defects inline and filed the residuals whose fixes are each a design cycle as #10117. Four coverage
predicates in the affected-suite selection machinery are weaker than matchability, and one is silent:

1. `covers()`'s dir-ref arm (`scripts/test-affected-kb-consumers.test.sh:287-296`) marks a directory
   ref under a glob's literal head covered by path nesting alone — so the regenerated baseline asserts
   coverage the glob tail's extension class cannot provide (≥5 lint-orphan rows: ledger-only blast
   radius; runtime selection on `main` unchanged).
2. A dir-less `x.test.sh`/`x.sh` at repo root is in the `git ls-files` corpus but inexpressible in
   `glob:<dir-head>/<tail>` — a latent gap (zero such files today; `SUITE_GLOBS` cannot register one).
3. `--paths=./x` spellings defeat every anchored edge at the `_PRINT_PATHS`→`_diff_names` boundary
   (`scripts/test-all.sh:2096`) — a silent no-match in a print-only diagnostic.
4. `_th6_root_covered` (`scripts/test-all-affected.test.sh:3036-3044`) accepts `glob:$2/*$3` by
   string suffix: file-literal-in-glob spellings and subset tails satisfy the census without covering
   the corpus class.

## Goals

- Every coverage predicate in the residual set evaluates **matchability**, not string shape.
- The `--paths` diagnostic fails toward coverage like the gate itself — a `./` spelling resolves to
  the same selection as the bare spelling; `../` is rejected.
- The latent root-anchored grammar gap becomes a **loud** gate (detection row), converting silent
  inexpressibility into a named failure at the moment it first has a member.
- Preserve the widen-only doctrine end to end: no change may narrow a selection a real diff would
  produce today.

## Non-Goals

- Extending the `glob:` grammar with a root-anchored form — deferred until the detection row fires
  (first dir-less corpus file lands). That is an ADR-242 amendment + five-site change, its own
  planning cycle. Tracked in a follow-up issue.
- `_affected_glob_split` helper extraction — deferred "to next grammar touch"; a detection row is not
  a grammar touch.
- The census dead-edge direction (last-member deletion under an unlisted root) — owned by the
  deferred census-witness advisory, outside this scope.
- Selector convergence (#8621) and mutation-battery path-gating (#9323) — siblings, coordinate, do
  not absorb.

## Functional Requirements

### FR1: `--paths=` normalization

Each `--paths=<a,b,...>` element is normalized through `_affected_normpath` (or equivalent
`${p#./}` + `seg/../` collapse) at the `_PRINT_PATHS`→`_diff_names` ingestion point
(`scripts/test-all.sh:~2096`), before comma→newline split. `../`-rooted elements are rejected with a
named error. `--print-selection --paths=./scripts/x.sh` produces the same selection as the bare
spelling. The forwarded enumerate child inherits the normalization.

### FR2: `_th6_root_covered` matchability

The census predicate evaluates whether the minted edge *can match* a canonical corpus member rather
than whether the member's string ends with the corpus tail: for each `glob:` member, synthesize
`<root>/x<corpus-tail>` (or the equivalent `[[ == ]]` evaluation) and require the tail to match.
Must preserve both current properties — file-literal edges do not count (literal-satisfaction
exclusion) and wrong-extension tails do not count — while newly declining literal-in-glob spellings
and subset-only tails. Ships mutation rows (file-literal tail, subset tail, dead-head) in the th6
family.

### FR3: Root-corpus detection row

A battery row (th6 family, beside the live `_TH_ROOTS` derivation) asserts that the set of dir-less
root files matching the corpus extensions (`git ls-files | awk -F/ 'NF==1'` filtered to
`*.test.sh`/`*.sh`) is empty — i.e., RED the moment a root-anchored corpus file exists, with the
failure message naming the deferred grammar extension as the remedy.

### FR4: `covers()` dir-ref all-containment

The oracle's dir-ref arm enumerates the tracked members under the ref (via the existing
`tracked()`/`_TRACKED` set — kb-scoped, sufficient) and reports covered iff **every** member under
the ref matches the glob tail (all-containment, not any-intersection). The committed baseline is
regenerated; each reappearing row receives an explicit disposition (baseline row + comment vs.
covering edge) — recorded in a disposition table in the PR. Edge widening to satisfy the oracle is
forbidden (it re-opens the over-coverage #9813 closed).

## Technical Requirements

### TR1: Packaging — two independent PRs targeting `main`

- **PR-A (this branch or a split):** FR1 + FR2 + FR3 — clean hardening, different files from the
  oracle (`test-all.sh`, `test-all-affected.test.sh`). Fast review.
- **PR-B:** FR4 — `covers()` all-containment + baseline regeneration + disposition table. Judgment-
  laden review, lands independently in either order.

### TR2: Doctrine preservation

Every degrade rung still fails toward coverage: malformed mints mint `^glob:<verbatim>`
(always-match), never bare `^`; the census stays a static RED on malformed declarations; no
predicate may narrow what a well-formed edge selects today.

### TR3: Mutation/battery idiom

New rows follow the th/tg idiom: RED-first, keep-list binding, sandbox probes via `run_arm`,
`env -u TEST_GROUP -u CI` on nested runner rows, scratch-root per-process fixture dirs, non-vacuity
floors. kb-literals in new battery rows must live inside `SANDBOX_*` env values or composed literals
(`"knowledge""-base"`) so the kb-consumers oracle does not charge them as real reads. Never edit a
file a running battery reads.

### TR4: Verification

Item-level pins: FR1 via a `--print-selection --paths=./<p>` row; FR2 via the new mutation rows;
FR3 via a sandboxed root-file fixture going RED; FR4 via the k5-family oracle tests extended with
dir-ref/all-containment cases plus the regenerated baseline diff reviewed row-by-row.
