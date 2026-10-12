---
title: "fix: affected edges — under-cover siblings (whole-tree corpus suites with no kb/root edge)"
type: fix
date: 2026-10-12
slug: affected-edges-under-cover-siblings
branch: feat-one-shot-9969-edge-roots
issue: 9969
closes: 9969
lane: cross-domain
---

# fix: affected edges — under-cover siblings

## Overview

Three whole-tree corpus suites under-cover their declared affected edges in
`scripts/lib/test-affected-paths.sh`. `guard-vacuity-floor` and
`lint-orphan-test-suites` declare edge arrays enumerating only the roots that
hold test suites today (`apps/ .claude/ .github/ plugins/ scripts/ test/ tests/`),
while their producer corpus is whole-tree `git ls-files '*.test.sh'` — a
`*.test.sh` added under an unlisted root (`knowledge-base/`, `bin/`, `infra/`,
`docs/`, `spike/`, `todos/`, or the dot-dirs) is scanned by the suite but never
selects it locally. `scripts/lib/repo-write-boundary.test.sh` reads whole-tree
`git ls-files '*.sh'` filtered by `grep -l 'test-all\.sh'` yet carries no
declared array at all (`edge:derived` self-edge only). The `glob:` declared-edge
kind minted by PR #9945 (ADR-242 decision 22) makes the suffix-scoped fix
expressible; this plan applies it with the same per-suite verified-read-set
disposition method, and pins the new coverage with per-extension rows in the
affected battery (`scripts/test-all-affected.test.sh`).

## Problem Statement / Motivation

Under-coverage is silent: the suite still scans the file (its producer is
whole-tree) but `--affected` never dispatches it on the diff that adds or edits
that file, so the author only learns of a broken verdict in CI. This is the
inverse direction of what #9813 closed — there, `knowledge-base/` dir prefixes
over-selected extension-bounded corpus walkers on `.md` diffs; here, omitted
roots under-select whole-tree corpus suites on exactly the diffs they guard.
Concrete instance already in the tree: `lint-orphan-test-suites.sh`'s own
`EXPECTED_SUITE_ROOTS` superset arm would red on a `knowledge-base/*.test.sh`
… but the suite is never selected by that diff, so the red surfaces in CI only,
detached from the change that caused it.

## Research Insights

**Premise Validation** (phase 0.6 — all cited refs verified live on this branch):

- PR #9945 `test-all: extension-aware glob: affected edges for kb corpus walkers
  (#9813)` — `state: MERGED`, merged 2026-10-11. Issue #9813 — `state: CLOSED`.
- `glob:` edge kind live on branch: `_affected_add_edge` mint arm
  (`scripts/test-all.sh:2784-2832`), `_diff_edge_hit` hit arm
  (`scripts/test-all.sh:2135-2169`), declared-member census arm
  (`scripts/lint-orphan-test-suites.sh:~1140-1185`), `covers()` oracle
  (`scripts/test-affected-kb-consumers.test.sh`), `GLOBENT` registration-only
  classifier (`scripts/test-all.sh:2346`). Grammar: `glob:<literal-head>/<glob-tail>`,
  head must be an existing `/`-terminated repo-relative dir (else degrades to
  `^<head>/` dir prefix), tail must carry `*`; `*` crosses `/` under bash
  `[[ == ]]`; every malformed shape mints always-match (widen-only).
- `AFFECTED_SCRIPTS_GUARD_VACUITY_FLOOR_PATHS` and
  `AFFECTED_SCRIPTS_LINT_ORPHAN_TEST_SUITES_PATHS` confirmed enumerating the
  same 7-root shape (`scripts/lib/test-affected-paths.sh:1981-1992` and
  `:2007-2018`). No `AFFECTED_SCRIPTS_LIB_REPO_WRITE_BOUNDARY_TEST_SH_PATHS`
  exists — the suite is glob-registered via `scripts/lib/*.test.sh` and
  classifies `edge:derived`.
- Why the linter did not flag `repo-write-boundary.test.sh`: the repo-wide-idiom
  arm regex (`scripts/lint-orphan-test-suites.sh:1220`) requires
  `git (-C <unquoted-operand>)? ls-files`; this suite's producer is
  `git -C "$REPO_ROOT" ls-files '*.sh'` — the quoted `-C` operand falls outside
  the optional group, so the arm never matched it. Coverage gap confirmed by
  reading, not assumed.

**Verified read sets** (each suite's actual corpus, read from its discovery
code — the disposition table below derives from these, not from the issue
prose):

- `scripts/guard-vacuity-floor.test.sh`: `git ls-files '*.test.sh'`
  whole-tree (line 210) — every `*.test.sh` under every root; fixture
  `scripts/fixtures/vacuity-contract-control.sh` (line 1405); own file.
- `scripts/lint-orphan-test-suites.sh`: `git ls-files '*.test.sh'` whole-tree
  (line 95); `git ls-files 'apps/*/infra/main.test.sh' 'infra/*/main.test.sh'`
  (line 320); `.github/workflows/*.yml` surfaces 4/5/6 (lines 319, 345, 362);
  `REQUIRED_RUNNERS` — 7 files (lines 538-561): `scripts/lint-orphan-test-suites.sh`,
  `apps/web-platform/infra/run-registered-suites.sh`,
  `.github/scripts/test/run-all.sh`, `scripts/lint-legal-scope-block-placement.sh`,
  `scripts/lint-legal-mirror-drift-baseline.sh`, `scripts/lint-legal-registers.sh`,
  `scripts/probe-legal-corpus-truth.sh`; `scripts/test-all.sh` (56);
  `scripts/lib/test-relevance-paths.sh` (608); `scripts/lib/test-affected-paths.sh`
  (975); whole-index `_TRACKED_SET` membership reads (112).
- `scripts/lib/repo-write-boundary.test.sh`: `git -C "$REPO_ROOT" ls-files
  '*.sh' | xargs grep -l 'test-all\.sh'` whole-tree (line 546) — extension-bounded
  `*.sh`, content-filtered; `scripts/test-all.sh` RUNNER (394, sed at 505/772,
  sandbox copies 429/454); `scripts/lib/repo-write-boundary.sh` LIB (28); own file.
- Battery mechanism: `scripts/test-all-affected.test.sh` `build_sandbox` injects
  a `SANDBOX_DIFF_NAMES` diff seam + a corpus-trim keep-list (`run_suite` case
  block ~line 220-245); the three labels are NOT in the keep-list today, so new
  rows must add them or "absent from RAN" reads as a trim artifact. `run_arm`
  executes the sandboxed runner with `cd "$REPO_ROOT"` — `glob:` head `-d`
  probes resolve against the real tree, so negative-extension rows
  (a `.md` declining) are meaningful. Precedent: the `tg` row family
  (`test-all-affected.test.sh:2844+`) pins #9813's five kb-corpus walkers
  per-extension.

**Current `*.test.sh` root inventory** (measured
`git ls-files '*.test.sh' | awk -F/ 'NF{print $1}' | sort -u`):
`.claude .github apps plugins scripts` — the arrays' `test/`/`tests/` entries
are already vacant of `*.test.sh` today; `*.sh` roots (measured):
`.claude .github apps bin knowledge-base plugins scripts test tests`.

**Top-level directory inventory** (measured
`git ls-files | awk -F/ 'NF>1{print $1}' | sort -u`, all verified `[[ -d ]]`
on this branch): `.agents .claude .claude-plugin .codex .cursor-plugin .devin
.github .grok LICENSES apps bin docs infra knowledge-base plugins scripts spike
test tests todos` — 20 roots.

**Property List** (phase 0.6b — restating the ask as observable properties):

1. A `*.test.sh` added/edited under ANY existing top-level root selects
   `scripts/guard-vacuity-floor` and `scripts/lint-orphan-test-suites`.
2. A `*.sh` added/edited under ANY existing top-level root selects
   `scripts/lib/repo-write-boundary.test.sh` (new `edge:declared` array).
3. A non-corpus extension under an unlisted root (`knowledge-base/x.md`,
   `knowledge-base/x.sh` for the `*.test.sh` suites) does NOT select — the
   `glob:` kind must narrow, not just relocate the over-coverage.
4. The "when uncertain, select" degrade is untouched — no grammar/arm edits.
5. The new coverage is pinned: fabricated-diff rows in the affected battery
   assert both the positive (corpus extension selects) and negative
   (non-corpus extension declines) directions.

**Cut List** (phase 0.6b — mechanisms the ask proposed that an existing
mechanism already covers, or that buy no property): none — the `glob:` edge
kind, the mint/hit/census arms, and the battery's `SANDBOX_DIFF_NAMES` seam
already exist on `origin/main`; this plan is data-file edits + battery rows.
The four sibling deferred advisories stay deferred (dispositions in Scope
Check): `_affected_glob_split` helper extraction (waits for next grammar touch —
this is a data-file change), `|` in verbatim mints (cosmetic), `*bunfig.toml`
overmatch (widen-only, benign), census edge-satisfiability witness arm (a new
census mechanism — bigger than this fix; the dead-edge direction it would
cover is recorded as a residual in Dependencies & Risks).

**Learnings applied:**

- `2026-04-28-plan-globs-must-be-verified-against-repo-structure.md` — every
  `glob:` head verified `[[ -d ]]` on this branch (all 20 roots OK above).
- #9945's own disposition table (ADR-242 amendment 2026-10-10): a suite's read
  set decides its edges — content-keyed corpora keep dir edges
  (`operator-agent-runnable`), extension-bounded corpora take `glob:`.
- `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md`
  — harness rows in the Guard Contract; a positive selection row needs a
  non-canonical must-PASS input, not just the canonical kb path.
- `2026-08-20-the-channel-was-silent-on-the-path-it-was-built-for.md` — the
  under-coverage property is a window/selection property: pin it with a diff
  inside the window (the corpus extension under an unlisted root), not a
  delete row that any suite read would red on.

**CLAUDE.md / AGENTS.md conventions:** rule corpus is the `hr|wg|cq|rf|pdr|cm`
index; this work touches no surface they gate beyond the enforced sections
below (Observability / Guard Contract / Scope Check mandatory shapes).

## Research Reconciliation — Spec vs. Codebase

No spec exists for this branch (one-shot path). Every claim in issue #9969 was
verified against the tree during premise validation and held exactly as stated:
the two arrays' 7-root enumeration, `repo-write-boundary.test.sh`'s whole-tree
`*.sh` read and missing array, and the `glob:` kind's availability. One
refinement the issue leaves to this plan: `lint-orphan-test-suites.sh` is not a
pure `*.test.sh` corpus walker — it also reads `.github/workflows/*.yml` and
seven `REQUIRED_RUNNERS` files, so `.github/` and `scripts/` keep dir prefixes
(verified reads, not corpus globbing).

## Proposed Solution

Convert the two enumerating arrays to suffix-scoped `glob:` coverage over every
top-level root, keeping dir prefixes only where the verified read set includes
non-corpus files; declare a new `glob:`-scoped array for
`scripts/lib/repo-write-boundary.test.sh`; pin with per-extension battery rows.

**Disposition table** (root = every existing top-level dir; R = root set of 20):

| Suite | Verified corpus | Dir prefixes kept (verified non-corpus reads) | `glob:` entries | Explicit entries |
|---|---|---|---|---|
| `scripts/guard-vacuity-floor` | `*.test.sh` whole-tree | `scripts/fixtures/` (fixture `vacuity-contract-control.sh` is `.sh`, not `.test.sh`) | `glob:<root>/**.test.sh` × all 20 roots | `scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh` |
| `scripts/lint-orphan-test-suites` | `*.test.sh` whole-tree + `.github/workflows/*.yml` + REQUIRED_RUNNERS + libs | `.github/` (workflows + `scripts/test/run-all.sh`), `scripts/` (SUT + 4 REQUIRED_RUNNERS + both libs + battery) | `glob:<root>/**.test.sh` × all 20 roots | `apps/web-platform/infra/run-registered-suites.sh`, `scripts/lint-orphan-test-suites.test.sh`, `scripts/lib/test-affected-paths.sh` |
| `scripts/lib/repo-write-boundary.test.sh` (NEW array `AFFECTED_SCRIPTS_LIB_REPO_WRITE_BOUNDARY_TEST_SH_PATHS`) | `*.sh` whole-tree, content-keyed on `test-all\.sh` | none — every verdict-moving read is `*.sh` | `glob:<root>/**.sh` × all 20 roots | `scripts/test-all.sh`, `scripts/lib/repo-write-boundary.sh`, `scripts/lib/repo-write-boundary.test.sh`, `scripts/lib/test-affected-paths.sh` |

Explicit entries note: files already reachable via a kept dir prefix or a
`glob:` are still listed where convention does (self `.test.sh`, the lib, the
runner) — the census's self-inclusion arm requires the literal
`scripts/lib/test-affected-paths.sh` member in every array.

**Documented residuals** (inexpressible in the current grammar — recorded, not
silently accepted):

- A `*.test.sh`/`*.sh` file at the repo ROOT (`x.test.sh`, no directory) —
  `glob:` requires a `/`-terminated literal head. Root-level suite files are
  also outside `SUITE_GLOBS` discovery, so the gap is consistent with
  registration reality; named here so a future grammar extension knows the
  shape it would close.
- A NEW top-level dir created after this edit — `glob:` heads must exist at
  mint; there is no root-anchored `**.test.sh` form. This is the direction the
  deferred "census edge-satisfiability witness arm" advisory would close.
- The census's dead-edge direction: a diff deleting the last member of a
  declared element under an unlisted root can move the lint's verdict without
  selecting it — same deferred advisory.

**Battery rows** (`scripts/test-all-affected.test.sh`, new `th` family beside
the `tg` precedent, RED-first per `cq-write-failing-tests-before`):

1. Keep-list: add `scripts/guard-vacuity-floor`, `scripts/lint-orphan-test-suites`,
   `scripts/lib/repo-write-boundary.test.sh` to `build_sandbox`'s injected
   `run_suite` case block (without this, absent-from-RAN is a trim artifact).
2. `th1` — `SANDBOX_DIFF_NAMES=knowledge-base/x.test.sh` selects all three.
3. `th2` — `knowledge-base/x.sh` selects only `scripts/lib/repo-write-boundary.test.sh`
   of the three (negative row for the `*.test.sh` pair).
4. `th3` — `knowledge-base/x.md` selects none of the three.
5. `th4` — per-root positive loop: `bin/x.test.sh`, `infra/a/b.test.sh`,
   `docs/x.test.sh`, `test/x.test.sh`, `tests/x.test.sh`,
   `knowledge-base/a/b/c.test.sh` each select the `*.test.sh` pair (a
   must-PASS input differing from the canonical kb path).
6. `th5` — `scripts/lib/repo-write-boundary.test.sh` receipt reads
   `edge:declared` in `--print-affected-set` (was `edge:derived`).

## Technical Considerations

- `glob:` degrade ladder: all 20 heads verified `[[ -d ]]` on this branch, so
  every entry mints `^glob:<pattern>`, never the `^<head>/` dir-prefix degrade
  (which would silently re-widen to dir-prefix selection).
- Bash `[[ == ]]` semantics: `*` crosses `/`, so `glob:knowledge-base/**.test.sh`
  covers `x.test.sh` at head-root and `a/b/c.test.sh` at depth — both pinned by
  `th4`.
- The census declared-member arm validates each `glob:` head exists; all pass.
- `EXPECTED_SUITE_ROOTS` (lint-orphan:154) is a superset check — new roots in
  the producer output pass it; no edit needed there.
- Self-inclusion: every array must literally contain
  `scripts/lib/test-affected-paths.sh` (census arm ~line 1195) — a diff editing
  only edge data then selects the suites it could blind. All three arrays carry it.
- Existing `tg` rows keep their semantics: the `th` rows assert only on the
  three new labels; kb walkers' selections on `x.test.sh`/`x.sh`/`x.md` are
  unchanged and not re-asserted.
- No `scripts/test-all.sh` edit — the keep-list is injected by the battery's
  own Python rewrite; the runner's grammar is untouched (degrade preserved).

## User-Brand Impact

- **If this lands broken, the user experiences:** the local `--affected` gate
  silently declining a suite whose verdict the diff moved — the suite still
  scans the file but is not dispatched, so a broken corpus verdict surfaces in
  CI (or never, if the suite isn't CI-run) detached from the change.
- **If this leaks, the user's [data / workflow / money] is exposed via:**
  workflow only — under-selection is a missed local signal, not a data or
  money exposure; CI legs run the full corpus, bounding the blast radius to
  local convenience plus delayed feedback.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** internal test-selection machinery —
  the exposed artifact is a local gate signal with CI as the authoritative
  backstop, not a user-facing product surface or data path.

## Observability

```yaml
liveness_signal:
  what: "the three corpus suites' declared edges select on a corpus diff — the `th` battery rows and the lint-orphan declared-member census are the probes; --print-affected-set AFFECTED_CLASS receipts are the readback"
  cadence: "every --affected local run + every CI run of scripts/test-all-affected.test.sh and scripts/lint-orphan-test-suites.sh"
  alert_target: "red suite in CI / local gate output"
  configured_in: "scripts/test-all-affected.test.sh (th rows); scripts/lint-orphan-test-suites.sh (declared-edge census arm)"
error_reporting:
  destination: "suite stdout in the test-all run log (local and CI)"
  fail_loud: "[FAIL] th<N>: … rows; 'ERROR: <arr> declares glob: edge …' census lines; AFFECTED_CLASS receipts naming edge:derived for repo-write-boundary.test.sh"
failure_modes:
  - mode: "a *.test.sh added under a root the arrays omit declines the *.test.sh corpus suites silently"
    detection: "th1/th4 fabricated-diff rows assert selection on previously-unlisted roots (knowledge-base, bin, infra, docs, test, tests)"
    alert_route: "red scripts/test-all-affected suite"
  - mode: "a declared glob: head dir disappears — the mint degrade re-widens to ^<head>/ dir-prefix selection"
    detection: "lint-orphan declared-member census REDs glob: entries whose head dir vanishes"
    alert_route: "red scripts/lint-orphan-test-suites suite"
  - mode: "the new rwb array removed or emptied — the suite returns to edge:derived self-edge"
    detection: "th5 pins AFFECTED_CLASS edge:declared for the label; census flags an empty AFFECTED_ array"
    alert_route: "red scripts/test-all-affected / scripts/lint-orphan-test-suites suites"
logs:
  where: "suite stdout in CI run log; --print-affected-set AFFECTED_CLASS receipts"
  retention: "CI log retention"
discoverability_test:
  command: grep -c 'glob:knowledge-base/\*\*\.test\.sh' scripts/lib/test-affected-paths.sh
  expected_output: "2"
```

## Architecture Decision (ADR/C4)

**ADR:** none — this plan applies ADR-242 decision 22's existing `glob:` grammar
and per-suite disposition method to three more suites. No new decision, no
reversal, no grammar change. The dispositions themselves are recorded where
the convention keeps them: in the arrays' own comment blocks in
`scripts/lib/test-affected-paths.sh`.

**C4 views:** none. Checked all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`):
(a) external human actors — none introduced (existing actors: founder,
support-bubble user, PR contributor, Codex/Devin/Cursor harnesses); (b)
external systems/vendors — none introduced (existing: github, doppler,
betterstack, zot, egress gateway, git-data store); (c) containers/data-stores —
none touched (the edited files are repo-local test-selection data + a mutation
battery, below the model's component granularity); (d) actor↔surface
relationships — unchanged. The local `--affected` gate is not a C4 element.

## Guard Contract

### Guard 1 — corpus-suite edge completeness (the `th` row family + the declared-member census)

**Property.** A diff whose changed lines intersect a whole-tree corpus suite's
verified read set selects that suite under `--affected`: any `*.test.sh` under
any existing top-level root for `scripts/guard-vacuity-floor` and
`scripts/lint-orphan-test-suites`; any `*.sh` under any existing top-level root
for `scripts/lib/repo-write-boundary.test.sh`; and a non-corpus extension under
an unlisted root selects none of them.

**Assembly.** Three chokepoints, all named: (1) the three `AFFECTED_*_PATHS`
arrays in `scripts/lib/test-affected-paths.sh` — every declared edge for these
suites flows through them; (2) `_affected_add_edge`'s `glob:*` mint arm and
`_diff_edge_hit`'s `glob:*` hit arm in `scripts/test-all.sh` — every declared
glob resolves to a minted edge and every diff line evaluates through that pair
(the shipped machinery the rows exercise end-to-end); (3) the `th` rows +
sandbox keep-list in `scripts/test-all-affected.test.sh` and the
declared-member census in `scripts/lint-orphan-test-suites.sh` — the dispatch
that observes selection and the static check that a head dir still exists.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Delete `glob:knowledge-base/**.test.sh` from `AFFECTED_SCRIPTS_GUARD_VACUITY_FLOOR_PATHS` | RED — `th1`/`th4` lose a required RAN |
| 2 | Retarget a glob tail to a non-corpus extension (`glob:knowledge-base/**.md`) | RED — `th3` (the .md decline) now sees a RAN |
| 3 | Add a SECOND previously-unlisted root to a fabricated diff (`infra/a/b.test.sh` alongside `knowledge-base/x.test.sh`) — an enumeration that stops at the first new root is the defect class | RED — `th4` asserts each root independently |
| 4 | Remove the three labels from the sandbox keep-list (own-dispatch: positive rows can never observe RAN, so the guard reports "0 checked") | RED — `th1`/`th4` fail as trim artifacts |
| 5 | Delete the `AFFECTED_SCRIPTS_LIB_REPO_WRITE_BOUNDARY_TEST_SH_PATHS` array — the suite reverts to `edge:derived` | RED — `th5` receipt pin + `th2` decline |
| 6 | Must-PASS non-canonical input: `knowledge-base/a/b/c.test.sh` (nested depth, a shape the `*` tail explicitly permits) | PASS — `th4` loop member, not a RED |

**Anchor.** Arrays and battery land in the same commit; weakening an array
without touching the fabricated diff lines goes red. The grammar semantics the
matrix depends on (`_affected_add_edge`, `_diff_edge_hit`, the census arm) are
pinned independently by the five-site malformed-shape doctrine and the `tg`
rows shipped in #9945 — a weakening there is outside this diff's reach and
already guarded.

## Implementation Phases

### Phase 1 — Battery rows, RED-first

1. In `scripts/test-all-affected.test.sh`, add `scripts/guard-vacuity-floor`,
   `scripts/lint-orphan-test-suites`, and `scripts/lib/repo-write-boundary.test.sh`
   to `build_sandbox`'s injected `run_suite` case keep-list.
2. Add the `th` row family (th1–th5 per Proposed Solution) beside the `tg`
   rows, reusing `run_arm` / `ran_exact` / `SANDBOX_DIFF_NAMES`.
3. Run `bash scripts/test-all-affected.test.sh`; record the `th` rows RED —
   the previously-unlisted roots decline the suites on the current arrays.
   (The `test/`/`tests/` th4 members pass already — they are regression pins,
   not evidence; the RED demonstration is the unlisted roots.)

### Phase 2 — Declared-edge arrays

1. Re-run the root enumeration (`git ls-files | awk -F/ 'NF>1{print $1}' |
   sort -u`) and reconcile against the 20-root plan list.
2. Rewrite `AFFECTED_SCRIPTS_GUARD_VACUITY_FLOOR_PATHS` and
   `AFFECTED_SCRIPTS_LINT_ORPHAN_TEST_SUITES_PATHS` per the disposition table;
   add `AFFECTED_SCRIPTS_LIB_REPO_WRITE_BOUNDARY_TEST_SH_PATHS` beside them.
3. Update each array's comment block with the verified read set the
   disposition derives from (the method the issue prescribes — the comments
   are where the next author checks).

### Phase 3 — Verify

1. `bash scripts/test-all-affected.test.sh` — all `th` rows GREEN.
2. `bash scripts/lint-orphan-test-suites.sh` — census green over the new
   `glob:` members (zero dead edges).
3. `bash scripts/guard-vacuity-floor.test.sh` and
   `bash scripts/lint-orphan-test-suites.test.sh` — green.
4. `bash scripts/test-all.sh --affected --print-affected-set` — confirm
   `edge:declared` receipts for the three labels.
5. `git diff --name-only $(git merge-base HEAD origin/main)` — confirm the
   diff is limited to the two source files plus planning artifacts.

## Files to Edit

- `scripts/lib/test-affected-paths.sh` —
  `AFFECTED_SCRIPTS_GUARD_VACUITY_FLOOR_PATHS` (~line 1981): replace the 7 bare
  dir prefixes with `glob:<root>/**.test.sh` × 20 roots + `scripts/fixtures/`;
  keep `scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh`.
  `AFFECTED_SCRIPTS_LINT_ORPHAN_TEST_SUITES_PATHS` (~line 2007): replace
  `apps/ .claude/ plugins/ test/ tests/` with `glob:<root>/**.test.sh` × 20
  roots; keep `.github/`, `scripts/` dir prefixes; add
  `apps/web-platform/infra/run-registered-suites.sh`,
  `scripts/lint-orphan-test-suites.test.sh`; keep
  `scripts/test-all.sh` (under `scripts/`), `scripts/lib/test-affected-paths.sh`.
  New `AFFECTED_SCRIPTS_LIB_REPO_WRITE_BOUNDARY_TEST_SH_PATHS`:
  `glob:<root>/**.sh` × 20 roots + `scripts/test-all.sh`,
  `scripts/lib/repo-write-boundary.sh`,
  `scripts/lib/repo-write-boundary.test.sh`, `scripts/lib/test-affected-paths.sh`.
  Update each array's comment block to record the verified read set the
  disposition derives from.
- `scripts/test-all-affected.test.sh` — add the three labels to `build_sandbox`'s
  injected keep-list case block; add the `th` row family (th1–th5 per Proposed
  Solution).

## Files to Create

None.

## Open Code-Review Overlap

- **#8800** (`test fixture: census sandbox shares inodes/symlinks with live
  repo`) touches `scripts/lib/test-affected-paths.sh` and
  `scripts/test-all-affected.test.sh` — **Acknowledge.** Different concern
  (fixture filesystem isolation vs. edge declarations); the battery's sandbox
  copy mechanism is orthogonal to the labels/rows this plan adds. The scope-out
  stays open.
- #8659 and #7942 mention `scripts/test-all.sh` — not in this plan's Files to
  Edit (the runner is unmodified); no overlap with the planned diff.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "`guard-vacuity-floor` and `lint-orphan-test-suites` declare edge arrays enumerating only the roots that hold tests today … a `*.test.*` file added under an unlisted root (`knowledge-base/`, `bin/`, `infra/`) is scanned but never selects the suite" [issue #9969] | Files-to-Edit entry 1 (`AFFECTED_SCRIPTS_GUARD_VACUITY_FLOOR_PATHS`, `AFFECTED_SCRIPTS_LINT_ORPHAN_TEST_SUITES_PATHS`) + `th1`/`th4` rows | mapped |
| 2 | "`scripts/lib/repo-write-boundary.test.sh` reads whole-tree `git ls-files '*.sh'` + `grep -l 'test-all\.sh'` — including the 9 kb `.sh` files — but carries no declared array (`edge:derived` self-edge only). Its arm needs a verified read set first." [issue #9969] | New `AFFECTED_SCRIPTS_LIB_REPO_WRITE_BOUNDARY_TEST_SH_PATHS` + `th2`/`th5` rows; verified read set in Research Insights | mapped |
| 3 | "use the `glob:` declared-edge kind from ADR-242 decision 22 / PR #9945" [issue #9969] | Disposition table — all three suites take `glob:` entries | mapped |
| 4 | "verify each suite's actual corpus by reading its discovery code before choosing edges (the trap-tempfile `ALL_EXT` lesson — and the agent-runnable content-keyed lesson: `git grep` corpora are NOT extension-bounded and keep their dir edge)" [issue #9969] | "Verified read sets" in Research Insights + Disposition table (`.github/` and `scripts/` retained as dir prefixes for lint-orphan's non-corpus reads) | mapped |
| 5 | "keep the "when uncertain, select" degrade" [issue #9969] | No grammar/arm edits — AC8 pins Files-to-Edit to the data file + battery only | mapped |
| 6 | "pin per-extension rows in the affected battery" [issue #9969] | `th1`–`th5` rows in `scripts/test-all-affected.test.sh` | mapped |
| 7 | "Sibling deferred advisories from the same review (may fold in if the tracker convention allows): `_affected_glob_split` helper extraction … `|` in verbatim mints … `*bunfig.toml` overmatch … census edge-satisfiability witness arm" [issue #9969] | — | descoped — justification: each is already tracked as its own deferred advisory; none is required for this fix's acceptance criteria (the witness arm is a new census mechanism — the residual it would cover is named in Dependencies & Risks) |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `scripts/lib/test-affected-paths.sh` edits (three arrays) | asks 1–3 | asked |
| `scripts/test-all-affected.test.sh` keep-list + `th` rows | ask 6 ("pin per-extension rows in the affected battery") | asked |
| Disposition table / verified read sets | ask 4 ("verify each suite's actual corpus by reading its discovery code before choosing edges") | asked |
| Keep-list label additions (inside the battery file) | — | inferred — justification: without them, "absent from RAN" reads as a corpus-trim artifact, so ask 6's pins cannot observe selection at all |

### Split Assessment

- Subsystems touched: 1 — `scripts`
- Planned files: 2 | Estimated changed lines: ~200
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] `AFFECTED_SCRIPTS_LIB_REPO_WRITE_BOUNDARY_TEST_SH_PATHS` exists in
  `scripts/lib/test-affected-paths.sh`, contains `glob:knowledge-base/**.sh`,
  `glob:infra/**.sh`, `scripts/lib/repo-write-boundary.test.sh`,
  `scripts/lib/repo-write-boundary.sh`, `scripts/test-all.sh`, and
  `scripts/lib/test-affected-paths.sh`.
- [ ] `AFFECTED_SCRIPTS_GUARD_VACUITY_FLOOR_PATHS` and
  `AFFECTED_SCRIPTS_LINT_ORPHAN_TEST_SUITES_PATHS` each contain
  `glob:<root>/**.test.sh` for every top-level dir in the 20-root set
  (`.agents .claude .claude-plugin .codex .cursor-plugin .devin .github .grok
  LICENSES apps bin docs infra knowledge-base plugins scripts spike test tests
  todos`), and neither retains a bare `apps/`, `.claude/`, `plugins/`, `test/`,
  or `tests/` prefix. `lint-orphan` retains `.github/` and `scripts/` dir
  prefixes plus `apps/web-platform/infra/run-registered-suites.sh`;
  `guard-vacuity-floor` retains `scripts/fixtures/`.
- [ ] `bash scripts/test-all-affected.test.sh` exits 0, including new rows
  proving: `knowledge-base/x.test.sh` selects all three labels;
  `knowledge-base/x.sh` selects only `scripts/lib/repo-write-boundary.test.sh`
  of the three; `knowledge-base/x.md` selects none; and each of
  `bin/x.test.sh`, `infra/a/b.test.sh`, `docs/x.test.sh`, `test/x.test.sh`,
  `tests/x.test.sh`, `knowledge-base/a/b/c.test.sh` selects the two `*.test.sh`
  suites.
- [ ] `bash scripts/test-all.sh --affected --print-affected-set` reports
  `edge:declared` for `scripts/lib/repo-write-boundary.test.sh` (was
  `edge:derived`).
- [ ] `bash scripts/lint-orphan-test-suites.sh` exits 0 — the declared-member
  census validates every new `glob:` head and reports no dead edges.
- [ ] `bash scripts/guard-vacuity-floor.test.sh` and
  `bash scripts/lint-orphan-test-suites.test.sh` each exit 0.
- [ ] `git diff --name-only` against merge-base is limited to
  `scripts/lib/test-affected-paths.sh` and `scripts/test-all-affected.test.sh`
  plus planning artifacts — no edit to `_affected_add_edge`, `_diff_edge_hit`,
  the census arm, or `GLOBENT` (the "when uncertain, select" degrade is
  untouched).
- [ ] Every `glob:` entry mints a real glob edge, not the `^<head>/` degrade:
  the arrays' head dirs all exist at merge time (verified by the census staying
  green — AC above — and by `[[ -d <head> ]]` on each entry during review).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — repo-internal test-selection machinery
(engineering tooling). Product/UX gate: no UI-surface file in Files to Edit or
Files to Create; semantic sweep found no domain whose assessment question this
diff answers (the "user" here is the Soleur operator's local gate, already
covered under Engineering, which is the domain doing the work).

## Test Scenarios

- **unit** — Given the new `th` rows and keep-list labels, when
  `bash scripts/test-all-affected.test.sh` runs, then th1–th5 pass against the
  edited arrays (and were observed RED before the array edits — the RED-first
  ordering is the regression pin for #9969 itself).
- **unit** — Given a fabricated `knowledge-base/x.test.sh` diff, when
  `--affected` classifies, then `scripts/guard-vacuity-floor`,
  `scripts/lint-orphan-test-suites`, and
  `scripts/lib/repo-write-boundary.test.sh` all RAN (`.test.sh` matches both
  `**.test.sh` and `**.sh`).
- **unit** — Given a fabricated `knowledge-base/x.sh` diff, when `--affected`
  classifies, then only `scripts/lib/repo-write-boundary.test.sh` of the three
  RAN (the `*.test.sh` pair declines a non-corpus extension).
- **unit** — Given a fabricated `knowledge-base/x.md` diff, when `--affected`
  classifies, then none of the three RAN (narrows rather than relocates
  over-coverage).
- **unit** — Given the declared-member census, when
  `bash scripts/lint-orphan-test-suites.sh` runs, then every new `glob:` head
  resolves and no dead-edge ERROR fires.
- **integration** — Given the full lint + vacuity suites, when
  `bash scripts/lint-orphan-test-suites.test.sh` and
  `bash scripts/guard-vacuity-floor.test.sh` run, then both exit 0 — the
  subject suites' own verdicts are unchanged by the edge-data edit.

## Success Metrics

- A fabricated `knowledge-base/x.test.sh` diff selects the two `*.test.sh`
  corpus suites (was: declined).
- `scripts/lib/repo-write-boundary.test.sh` classifies `edge:declared` with a
  `glob:`-scoped corpus (was: `edge:derived` self-edge).
- `knowledge-base/x.md` selects none of the three (the `glob:` kind narrows —
  no relocated over-coverage).
- `lint-orphan-test-suites` census green over ~60 new `glob:` members (all
  heads resolve, zero dead edges).

## Dependencies & Risks

- **Residual (grammar-bound):** a `*.test.sh`/`*.sh` at the repo root and any
  top-level dir created after this edit stay uncovered — `glob:` heads must
  exist at mint and no root-anchored form exists. Recorded in Proposed
  Solution; the deferred census edge-satisfiability witness arm is the
  direction that would close it.
- **Residual (census dead-edge direction):** a diff deleting the last member
  of a declared element under an unlisted root can move lint-orphan's verdict
  without selecting it — same deferred advisory.
- **Enumeration drift:** the 20-root set is measured at plan time; the
  implementer re-runs `git ls-files | awk -F/ 'NF>1{print $1}' | sort -u` at
  edit time and reconciles any root added since.
- **Keep-list divergence:** if a later arm asserts a fourth new label the
  keep-list again needs the member — the battery's own header documents this.
- **Same-file semantics drift:** array comments record the verified read set;
  a future corpus change (e.g., lint-orphan starts reading `.test.ts`) must
  re-run the disposition method, not just append an extension.

## References & Research

- Issue: #9969 (this work). Prior art: PR #9945 / issue #9813 (`glob:` kind,
  disposition table, `tg` battery rows); ADR-242 amendment 2026-10-10
  (decision 22).
- Edge grammar: `scripts/test-all.sh` `_affected_add_edge` (~2784),
  `_diff_edge_hit` (~2135), `GLOBENT` (~2346); census arm
  `scripts/lint-orphan-test-suites.sh` (~1140-1198); `covers()` oracle
  `scripts/test-affected-kb-consumers.test.sh`.
- Arrays under change: `scripts/lib/test-affected-paths.sh` ~1981, ~2007;
  array-shape precedent `AFFECTED_SCRIPTS_LINT_TRAP_TEMPFILE_OWNERSHIP_PATHS`
  (~2021) — the seven-extension `glob:` enumeration.
- Battery: `scripts/test-all-affected.test.sh` `build_sandbox`/`run_arm`
  (~120-315), `tg` rows (~2844-2963).
- Verified suite corpora: `scripts/guard-vacuity-floor.test.sh:210,1405`;
  `scripts/lint-orphan-test-suites.sh:95,112,319-320,345,362,538-561,608,975`;
  `scripts/lib/repo-write-boundary.test.sh:28,394,429,454,505,546,772`.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail
  `deepen-plan` Phase 4.6. Filled above.
- The `th` rows MUST be authored before the array edits and observed RED —
  writing them after would leave the under-coverage claim unproven
  (`cq-write-failing-tests-before`).
- Every `glob:` head must still be a real dir at merge time — a root renamed
  between planning and merge degrades its entry to a `^<head>/` dir prefix,
  silently re-widening that root to dir-prefix selection (the census REDs it,
  which is the check, not the fix).
- Do not "simplify" the 20-entry root enumeration back into fewer bare dir
  prefixes during implementation — that is the defect this plan closes.
