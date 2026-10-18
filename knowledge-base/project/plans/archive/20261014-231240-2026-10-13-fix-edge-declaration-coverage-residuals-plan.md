---
title: "fix: edge-declaration coverage residuals — covers() dir-ref containment, census matchability, --paths normalization, root-gap detection"
date: 2026-10-13
slug: fix-edge-declaration-coverage-residuals
branch: feat-10117-edge-coverage-residuals
issue: 10117
closes: 10117
type: fix
priority: p3-low
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix: edge-declaration coverage residuals — covers() dir-ref containment, census matchability, --paths normalization, root-gap detection

## Overview

Repair four coverage-predicate residuals in the repo's affected-suite selection machinery, filed as
issue #10117 by the PR #10088 review: make the `covers()` oracle's dir-ref arm evaluate real
membership (all-containment over tracked members), tighten the `_th6_root_covered` census predicate
to tail matchability, normalize `./` spellings on the `--paths` diagnostic input, and convert the
latent root-anchored grammar gap into a loud detection row. Packaging: two independent PRs — a clean
hardening PR (items 3+4 + detection row + ADR-242 amendment) and a judgment-laden PR (covers() +
baseline regen + dispositions) — per the operator's packaging decision at brainstorm close.

## Problem Statement / Motivation

PR #10088 (fix for #9969) added `glob:` declared edges for whole-tree corpus suites and, in review,
filed four residuals it deliberately scoped out as design-cycle items rather than inline edits:

1. **`covers()` dir-ref extension blindness** — the oracle's dir-ref arm
   (`scripts/test-affected-kb-consumers.test.sh`, Python `covers()`) accepts a directory reference
   when a glob tail covers *the directory's own corpus extension* — it does not check whether the
   extension classes actually stored under that directory are all covered.
   `glob:knowledge-base/plans/archive/**.md` therefore "covers" a dir ref whose corpus is `.sh` +
   `.md`. The nest clause (`head.startswith(p…)`) treats path nesting as coverage and is blind to
   extension-class composition.
2. **Root-anchored grammar gap** — the `glob:` grammar requires a head dir ending in `/`
   (decision-22 enforcement in `lint-orphan-test-suites.sh` declines the metachar head `glob:*.<ext>`
   at :1147; a metachar-free `glob:<dir>` never reaches the decline — :1152-1154 recurses it to a
   whole-tree literal dir edge), so a root-level `*.test.sh`/`*.sh` corpus file is unrepresentable
   as a declared edge. Verified latent today: zero dir-less `.sh`/`.test.sh` files exist in the
   repo, and `SUITE_GLOBS`-driven registration cannot mint one. The residual's true shape: an
   *unregistered* dir-less `x.test.sh` already REDs lint-orphan's census — what stays silent is a
   dir-less `*.sh` (no orphan suite walks that extension) and a root file registered via an
   exclusion-key escape (registered-but-edge-unrepresentable). The new row covers both.
3. **`--paths` `./` normalization** — `--paths=./foo` is passed raw into `_diff_names`
   (`scripts/test-all.sh`:2096); the `./` spelling never matches a git path, so the diagnostic
   silently misleads (while `--affected`, which normalizes via `git diff --name-only`, stays
   correct).
4. **`_th6_root_covered` validates shape, not matchability** — the census predicate accepts any
   tail ending in `*<corpus-ext>` as coverage for a root (`scripts/test-all-affected.test.sh`:3036-3044),
   including literal-in-glob spellings (`glob:root/x.test.sh` suffix-matches `.test.sh`) that the
   literal-satisfaction constraint was built to exclude.

## Research Insights

**Premise Validation (Phase 0.6):** issue #10117 is OPEN (p3-low, chore, deferred-scope-out);
PR #10088 reported MERGED 2026-10-13T03:14Z; parent #9969 reported CLOSED; the cited plan
(`knowledge-base/project/plans/2026-10-12-fix-affected-edges-under-cover-siblings-plan.md`, 648
lines) exists on `origin/main`; #9307 is an issue reference, not a PR (`gh pr view` unresolvable —
read as issue). Nothing stale. Review panel (six seats: DHH, Kieran, code-simplicity,
architecture-strategist, spec-flow ×2) — approve-with-amendments; all findings folded (decision-27
renumber, function-scoped `_th_ls_files` + TESTROOT confinement, disjoint ext classes, per-element
FR1, `UNCLASSIFIED` new-row ratchet, head-side decline row).

**Property List (Phase 0.6b):**

- P1: `--paths=<./p>` selects identically to `--paths=<p>` — the diagnostic must not silently
  mislead; it is print-only, so a bad spelling must fail loud or normalize, never select nothing.
- P2: the th6 census certifies only `glob:` tails that can actually match a canonical corpus
  member — matchability, not string-suffix shape — and declines literal-in-glob and subset-only
  tails.
- P3: a dir-less repo-root corpus file produces a loud gate failure on the next full battery run,
  not a silent coverage hole.
- P4: `covers()` reports a dir ref covered only when every tracked member under it matches the glob
  tail — all-containment.

**Cut List (Phase 0.6b):**

- Root-anchored grammar extension → P3's expressibility — **cut**: latent (zero dir-less corpus
  files; `SUITE_GLOBS` cannot register one). Detection row covers the failure-to-notice property at
  a fraction of the cost; grammar extension tracked as #10198 pending a live trigger.
- `_affected_glob_split` helper extraction → "five sites share one regex" — **cut**: its trigger was
  "next grammar touch"; the grammar is not touched here.
- `covers()` evidence threading (option (a)) → richer verdict data — **cut**: changes what a REF row
  means for the same verdict; option (b) (all-containment) is the simpler semantic.
- New normalization helper for `--paths` → P1 — **cut**: `_affected_normpath` exists; and a same-
  line `${p#./}` + `..`-rejection at the parse site is cheaper than hoisting.

**Research findings (brainstorm fan-out + plan-scoped follow-up):**

- `_affected_normpath` (`scripts/test-all.sh`:2855-2870) returns via global `_NP`, strips leading
  `./`, collapses `seg/../` in a bounded 6-iteration sed loop — but is **defined ~760 lines after**
  the `--paths` ingestion block (:2095-2099, top-level code, no `main()`); calling it there is
  rc 127 under `set -euo pipefail`. Normalize at the `_PRINT_PATHS` parse arm (~:307) instead —
  upstream of `_diff_names` (:2096), the enumerate-child forward (:3834), and every consumer.
- **Mutation/pin constraints on the FR1 edit:** m6 anchors the exact two-space-indented line
  `_diff_names="${_PRINT_PATHS//,/$'\n'}"` (:2809) — do not touch it; q6 (:2836-2845) greps the
  `_aff_child_paths` build shape — keep `if (( _PRINT_PATHS_REQ == 1 )); then _aff_child_paths=(--paths=` intact.
- `_th6_root_covered` tightens to: tail carries `*` AND tail is the bare wildcard form
  `*<corpus-ext>` or `**<corpus-ext>` — `[[ "$tail" == "*${ext}" || "$tail" == "**${ext}" ]]`.
  A single-member `[[ == ]]` witness under-declines subset tails (`x.test.sh` matches `*x.test.sh`
  and `**x.test.sh` under bash glob semantics where `*` crosses `/`); the bare-form check is the
  equivalent-correct predicate and also declines subdir-scoped tails (`sub/*.test.sh`) that do not
  cover the root class.
- Detection-row home: the th6 family in `test-all-affected.test.sh` beside the `_TH_ROOTS`
  derivation (:3028-3029) — the `NF>1` filter's `NF==1` complement is the population, and the
  comment at :3023-3027 already names the residual. lint-orphan's census is per-member declared-edge
  validity (wrong population; no root/corpus-tail concept). Neither placement catches the diff that
  introduces the file under `--affected` (a dir-less corpus file selects no suite — that *is* the
  gap); the row's job is to RED the next full battery/main-push run.
- Baseline mechanics: `bash scripts/test-affected-kb-consumers.test.sh --write-baseline` regenerates
  `scripts/test-affected-kb-consumers.baseline.txt` (240 rows: ~232 two-col `argv-code` rows with NO
  classification possible — row b1 compares the first three columns exactly — plus 8
  `dir-operand-tests` rows carrying `false-positive: <reason>`). Advisor consult surfaced that
  `argv-code` rows CAN carry a classification with a two-line emitter extension (`baseline` mode
  prints `label<TAB>path<TAB>argv-code<TAB><cls>` when carry-forward yields one; u1's fixture and
  b1's 3-col compare already tolerate it) — so in-file dispositions are available for the new rows
  AND the PR carries the D2-style per-row disposition table. #10088 deliberately avoided regen by
  fixture-scoping kb literals; this work cannot.
- Oracle self-guard pins to respect: k5's expectation vector (`:702-725`) currently expects
  `"1 1 0 0 1 1 1 1 1"` with the last two positions = the dir-ref nest clause — all-containment
  flips them to `0`; extend the vector with new cases rather than only re-deriving. Mutation
  arms use `SANDBOX_MUT_OLD`/`SANDBOX_MUT_NEW` exact single-line rewrites (rc 98 if unfound).
- Community/functional overlap: none (bespoke repo-internal oracle; registry scan found only
  category-adjacent diff→tests selectors).

## Research Reconciliation — Spec vs. Codebase

| spec claim | reality | plan response |
|---|---|---|
| FR1: normalize "at the `_PRINT_PATHS`→`_diff_names` ingestion point (~2096)" reusing `_affected_normpath` | `_affected_normpath` is defined at :2855, after BOTH the top-level ingestion block (:2096) AND the parse arm (:307) — the `while` arg-parse loop at :256 is also top-level, so the helper is callable NOWHERE near the input; calling it is rc 127 in both places | Inline byte-level normalization at the parse arm (~:307): `${_PRINT_PATHS#./}` for the head element and `${_PRINT_PATHS//,\.\//,}` for interior elements, plus a `..`/absolute reject with a named error — no helper call (hoisting rejected as out-of-scope churn). `_PRINT_PATHS` normalized at store-time also fixes the child forward (:3834) while :2096 stays byte-identical, so m6/q6 pins hold |
| FR2: "synthesized canonical member `root/x<corpus-ext>` + `[[ == ]]`" | a single-member witness under-declines subset tails — `x.test.sh` matches `*x.test.sh`/`**x.test.sh` | Equivalent predicate: bare-wildcard tail form (`*<ext>` or `**<ext>`) + metachar requirement; declines literal-in-glob AND subset-only tails (the spec's stated goals) |
| FR3 row asserts `_TH_ROOTS`-derived expected set | expected set is empty — inverted non-vacuity | Row carries a producer-liveness floor (`git ls-files` non-empty AND `_TH_ROOTS` non-empty) so a dead producer reads RED |
| FR4: "baseline row + comment" dispositions | `argv-code` rows emit 2 cols today, but the machinery nearly supports classification: `unclassified_rows` (:84) accepts any NF>=3 row whose $4 is `false-positive: <reason>` (u1's fixture proves a classified argv-code-shape row validates) | Extend the `baseline` emitter (:344-351) to print `label\tp\targv-code\t<cls>` when carry-forward yields a classification; b1's first-3-cols compare stays consistent. Dispositions thus live in-file AND in the PR's per-row table (D2 precedent) |

## Proposed Solution

Two independent PRs off `main` (operator decision — independent, not stacked; the diffs touch
disjoint files and can land in either order):

### PR-A — predicate + input hardening (FR1, FR2, FR3, ADR amendment)

- **FR1**: at the `--paths=` parse arm in `scripts/test-all.sh` (:307-310), normalize **per
  element** (split the value on `,`): strip leading `./` to fixpoint
  (`while [[ "$p" == ./* ]]; do p="${p#./}"; done`), then reject — named error echoing the
  offending element plus a valid example — any element that is not a clean repo-relative path:
  empty (incl. `--paths=.` / `./` / `a,,b`), `.` or still `./`-headed after the loop, absolute,
  a segment-anchored `..` (`..`, `../*`, `*/..`, `*/../*` — NOT substring: `foo..bar.sh` is
  legal), `//` or `/.` segments/trails, a trailing `/` (a dir ref is not a diff path), or a TAB
  **or LF** byte (`:2126` splits TAB and `:2096` joins comma→newline — both silently mint fake
  diff lines today). `--paths` is print-only: failing loud is honest, narrowing silently is not.
  NO helper call: `_affected_normpath` is defined at :2855, after both the :256 parse loop and :2096
  — it is callable nowhere near the input (hoisting rejected as out-of-scope churn; and it would
  *collapse* `a/../b` where this plan rejects — different semantics besides). Normalizing
  `_PRINT_PATHS` at store-time covers `:2096` (m6-anchored, byte-identical) AND the enumerate-child
  forward (:3834, q6-pinned) — the child re-parses through the same arm, so a bad element can never
  reach it (parent exits 2 first). **Spec divergence, recorded:** spec FR1 contemplated
  `seg/../` collapse (`a/../b` → `b`); this plan *rejects* `..` segments outright — louder and
  simpler for a diagnostic spelling that is almost certainly a typo. Update the `--help` line at
  :333-334 to name the `./` normalization and the reject set.
- **FR2**: tighten `_th6_root_covered` (`scripts/test-all-affected.test.sh`:3036-3044), keeping
  BOTH existing arms and tightening the glob arm: (i) retain the bare `$_m == "$2/"` dir-prefix
  disjunct — it is what covers the seven `_TH_PREFIX_ROOTS` (`apps .claude .github plugins scripts
  test tests`) under the `.test.sh` pair; pin an accept row for it. (ii) For `glob:` members,
  prefix-match on `glob:$2/`, extract the tail with `${_m#"glob:$2/"}` (quotes load-bearing here
  too: unquoted, `$2` acts as a glob pattern inside `#` and mis-strips a root containing `?`/`[`),
  then **literal-compare** the remainder — `[[ "$tail" == "*${ext}" || "$tail" == "**${ext}" ]]`
  with the RHS FULLY QUOTED (a quoted RHS is a literal compare; an unquoted `*${ext}` pattern
  degenerates to the old suffix check — the quotes carry the fix, and this fact must live in an
  inline code comment at the predicate, not only in this plan). The head anchor is the literal
  `glob:$2/` prefix — decline `glob:<root>x/**.test.sh` (different root sharing the string prefix,
  head-side witness) as well as `glob:<root>/sub/*.test.sh` (tail-side). Declines: literal-in-glob (`x.test.sh`), subset (`pre*.test.sh`,
  `*x.test.sh`), subdir-scoped (`sub/*.test.sh`), wrong-ext (`.md`), and the overlap class
  `**.test.sh` declared to satisfy a `.sh` corpus (a previously-masked false-accept the old
  suffix check admitted — `**.test.sh` ends in `.sh`). **Canonical-form ratchet, stated:** covering
  but non-canonical tails (`***<ext>`, `*<ext>*`, `*test.sh`) now decline — announced in the PR.
- **FR3**: new th-family row beside `_TH_ROOTS` asserting no dir-less repo-root `*.sh`/`*.test.sh`
  exists. **Producer seam — function-scoped, not variable-scoped:** wrap the listing in
  `_th_ls_files() { git -C "${_TH_REPO:-$REPO_ROOT}" -c core.quotePath=false ls-files; }` and derive
  `_TH_ROOTS` (NF>1) plus the `NF==1` corpus complement through it — "shares the producer" means
  same function, not one frozen capture (a top-level variable is captured before any row sets
  `_TH_REPO`, which would make every mutation arm dead). The detection row re-invokes the function
  inside its own subshell under a per-row `_TH_REPO` — mutation arms exercise the real producer
  cheaply without re-running the suite and without clobbering `_TH_ROOTS` for th4–th6. `_TH_REPO`
  is **confined**: it must resolve under `"$TESTROOT"` (the file's `assert_fixture_dir` :70-79
  idiom) — refuse otherwise, so the seam can never retarget the th family at a sibling checkout
  whose populated listing would read green. The complement filter classifies extensions
  **disjointly** (`*.test.sh` vs `*.sh`-but-not-`*.test.sh` — last-two-dot vs last-dot), because a
  monolithic `\.sh$` subsumes `.test.sh` and leaves the extension-arm mutation nothing to observe.
  `-c core.quotePath=false` is load-bearing (C-quoted non-ASCII names keep `NF==1` but break the
  ext filter); fixture adds use `git add -f` (a global `core.excludesFile` matching `*.test.sh`
  would silently drop the fixture). Liveness floor binds to the producer output (empty listing →
  RED, same `EMPTY-ROOT-DERIVATION` idiom as :3203) — the complement is legitimately empty today,
  so the floor must be on the producer, not the output. Scope: the row covers the th6 corpus
  extension pair; other whole-tree tooling (lint-trap's `ALL_EXT` walk) is separately enumerated
  and not edge-based — out of scope. Failure message names the deferred grammar extension (#10198)
  as remedy, and the stale comment block at :3023-3027 gains a pointer to this row.
- **ADR-242 amendment**: decision 27 records "the root-anchored gap stays unrepresentable and is
  detected-not-extended; grammar extension triggers only on a live dir-less corpus file" — the
  durable doctrine choice, in the same PR as the detection row that enforces it.
- Battery: q-family pin asserting `--paths=./<p>` selects identically to `--paths=<p>`; th-family
  rows for FR2 decline/accept shapes and FR3 (RED-first ordering — rows land before predicates).

### PR-B — `covers()` dir-ref all-containment + baseline regen (FR4)

- Tighten the dir-ref arm in `covers()` (`scripts/test-affected-kb-consumers.test.sh`:268-296):
  for a `knowledge-base`-scoped dir ref, enumerate its tracked members via `tracked()`'s `_TRACKED`
  set and require every member to match the glob tail (all-containment); a kb ref with an empty
  member set declines. Non-kb dir refs keep the nest-clause verdict (production refs are always
  kb-scoped — `scan()` filters at :205 — so the nest clause survives only for synthetic/future
  populations; the rule is stated, not left implicit). Two traps the arm must handle: `_TRACKED` is
  `None` until `tracked()` runs — materialize it via any `tracked(p)` call (`tracked` is a
  membership *predicate*; the dict population is its side effect), then prefix-filter
  `_TRACKED[0]` on `f.startswith(p.rstrip("/") + "/")`. The accessor (`members_under`) wraps those
  two steps; it does not call `tracked("knowledge-base")` for a member list (no such contract).
  Needed because k5's `_cov` helper calls `covers()`
  on a fresh exec'd module; and `isdir`/`ls-files` resolve against process cwd — k5's heredoc
  already runs under `cd "$REPO_ROOT"` (:703); the `cd` requirement applies to NEW `_cov`-style
  rows exercising `members_under`/`isdir` (`_cov` itself, :681, does not `cd` and only passes
  non-dir paths — the new dir-ref cases change that contract; say so in an inline comment).
  Real residual, stated:
  all-containment still over-approximates — a `dir/*.md` read is charged as the whole dir, so
  flipped rows will include true false positives (that is what the disposition channel is for).
  Expect the regen to be dominated by bare `knowledge-base` dir refs (the trim loop charges the
  whole kb dir when an intermediate component is untracked) — likely MORE than the "≥5" floor;
  a large set is a replan signal, not a wider baseline.
- Extend the `baseline` emitter so `argv-code` rows can carry a 4th classification column
  (`label<TAB>path<TAB>argv-code<TAB>false-positive: <reason>`) — the c1 shape check and b1's 3-col
  compare already tolerate it; u1 accepts NF>=3 column-agnostically, so add one u-family fixture
  row pinning the argv-code 4-col shape explicitly. **New-row ratchet:** an `argv-code` row ABSENT
  from the old baseline emits `\tUNCLASSIFIED` as its 4th column — c1 refuses it, so every
  genuinely-new row forces an explicit disposition at regen time; the 232 grandfathered 2-col rows
  carry forward untouched. Without this the convention only scales socially — a reappearing row
  regens 2-col and its justification dies with the PR.
- **c1 remedy message:** the `c1:` fail line (or the comment above `unclassified_rows`) names the
  two exits — "add a covering edge in `scripts/lib/test-affected-paths.sh`, or a `false-positive:
  <reason>` 4th column; `UNCLASSIFIED`/reason-less rows are refused." An engineer hitting the red
  on an unrelated PR should not have to reverse-engineer the vocabulary from the 8 seeded rows.
- Extend the k5-family expectation vector (the last two positions flip `1`→`0` under
  all-containment) with new dir-ref cases — including a must-PASS positive via a `glob:<KB>/**`
  bare-`**` tail edge (all members match); add mutation coverage for the tightened arm.
- Regenerate the baseline via `--write-baseline` **in the same commit as the `covers()` change**
  (b1 must never be red mid-commit); reappearing rows (dir refs whose members include
  non-matching classes — ≥5 lint-orphan rows expected) are dispositioned per-row: covering edge
  added, `false-positive:` classification in-file, or a narrowed scan — never edge widening to
  silence the oracle. The PR additionally carries the per-row disposition table.

## Technical Considerations

- **RED-first ordering**: new battery rows are authored and observed RED before predicate/
  normalization edits land; the PR description records the RED demonstration.
- **Count literals**: bump `MIN_CASES` and grep every count literal before running
  (`selected=N of=M`, th6 `_TG_ALL_SEVEN`-class pins, f1 floor) — they move when families grow.
- **kb literal discipline**: all `knowledge-base/` literals in new test code are composed or
  fixture-scoped (`"knowledge""-base/…"`, `SANDBOX_*` env values) — a bare literal is charged to
  this suite as a real read by the kb-consumers oracle.
- **Nested runner env**: real-runner rows apply `env -u CI -u TEST_GROUP` (ENV_SCRUB) — inherited
  `CI=1` early-returns `_diff_touches` → vacuous green.
- **`covers()` self-materializes `_TRACKED`**: k5's `_cov` helper calls `covers()` on a fresh
  exec'd module where `_TRACKED` is `None` — the dir-ref arm calls `members_under(p)` which lazily
  runs `tracked("knowledge-base")`. New `_cov`-style rows must `cd "$REPO_ROOT"` (`isdir`/`ls-files`
  are cwd-relative).
- **Sandbox hygiene**: `run_arm`/`ran_exact` idioms; mutations anchor on post-swap text and assert
  exactly-one occurrence; any new asserted label joins `build_sandbox`'s keep-list.
- **Never edit battery files while a run reads them** (bash lazy-reads by byte offset).
- **`covers()` scope**: `scan()` emits only `knowledge-base`-prefixed refs and `_TRACKED` is
  kb-scoped, so every dir ref has a member set — the accepted residual is over-approximation
  (a `dir/*.md` read is charged as the whole dir), which is what the disposition channel is for.
- **Sibling coordination**: #8621 may relocate `--paths` handling (land FR1 early in PR-A);
  #9323 overlaps FR2's mutation-row territory — stay consistent with its battery direction.
- **NFR impacts**: none — repo-internal test machinery; no production/runtime surface.

## User-Brand Impact

- **If this lands broken, the user experiences:** a coverage predicate that reads green while a
  suite declines on a diff that should have selected it — the defect surfaces at CI instead of
  commit time; for the legal-corpus gates this machinery guards (`lint-legal-*`,
  `probe-legal-corpus-truth`), silent under-coverage is the class where a register diff ships
  without its required gate.
- **If this leaks, the user's [data / workflow / money] is exposed via:** workflow only — the
  affected selector is a local/CI acceleration mechanism; the full battery remains the merge
  backstop. No data or money surface.
- **Brand-survival threshold:** `single-user incident` (carried forward from the brainstorm)
- **Threshold decision (challengeable):** the machinery guards legal-corpus gates; a
  silently-narrowing coverage predicate is a single-incident-class failure even though no product
  surface is touched.

## Observability

```yaml
liveness_signal:
  what: "the census predicate and detection row assert real coverage — th6-family rows, the new root-file detection row, and the kb-consumers oracle rows are the probes"
  cadence: "every --affected local run + every CI/main-push run of scripts/test-all-affected.test.sh and scripts/test-affected-kb-consumers.test.sh"
  alert_target: "red suite in CI / local gate output"
  configured_in: "scripts/test-all-affected.test.sh (th/q rows); scripts/test-affected-kb-consumers.test.sh (k/mutation rows)"
error_reporting:
  destination: "suite stdout in the test-all run log (local and CI)"
  fail_loud: "[FAIL] th<N>: … rows; named --paths reject; 'UNCLASSIFIED' c1 failures on a regen"
failure_modes:
  - mode: "a dir-less root corpus file lands and no suite selects it"
    detection: "new detection row REDs on next full battery run (producer-liveness floor keeps a dead ls-files RED, not green)"
    alert_route: "red scripts/test-all-affected suite"
  - mode: "a literal-in-glob or subset tail declared to cover a root's corpus"
    detection: "th6 tightened predicate declines; FR2 decline rows assert it"
    alert_route: "red scripts/test-all-affected suite"
  - mode: "a dir ref covered by a glob that misses some member extension class"
    detection: "covers() all-containment flips the oracle verdict; row 2/b1 baseline gates fail on the regen drift"
    alert_route: "red scripts/test-affected-kb-consumers suite"
logs:
  where: "suite stdout in CI run log; --print-selection AFFECTED_CLASS receipts"
  retention: "CI log retention"
discoverability_test:
  command: grep -c 'NF==1' scripts/test-all-affected.test.sh
  expected_output: "1"
```

## Architecture Decision (ADR/C4)

**ADR:** `ADR-242` amendment — decision 27, landed in PR-A: "root-level (`NF==1`) corpus files are
outside the `glob:` grammar by design; the gap is *detected* by the th-family row (a dir-less
`*.test.sh`/`*.sh` at repo root is RED) rather than *bridged* by a grammar extension; extension is
deferred to #10198 and activates only if a live dir-less corpus file appears. In the interim a
dir-less file that must be covered has only literal-edge or `always_on` recourse — the amendment
says so explicitly so the row's failure message can name the remedy. Census certification is
matchability, not suffix shape (FR2). Note for readers of `audit-suite-reads.sh`: its
`UNCOVERED_AWK` treats `^glob:` edges as literals, so glob-only-covered recorded reads report
uncovered — over-report, safe direction; those rows are not oracle disagreements." Appended
`## Amendment — 2026-10-13 (#10117)` section + `amended_by:` frontmatter entry, per the file's
established amendment convention. **Ordinal verified:** decisions 23-26 already exist in the
2026-10-11 (#9815) amendment — 27 is next; `check-adr-ordinals.sh` covers FILENAME ordinals only,
so the intra-file number is hand-verified now and re-verified at merge (a claim, not a
reservation).

**C4 views:** none. Checked all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`):
(a) external human actors — none introduced (existing: founder, emailSender, betaContact,
contributor, publicReader, supportUser, and the codex/devin/cursorCli harness systems); (b) external
systems/vendors — none introduced (existing externals enumerated in views.c4:36); (c)
containers/data-stores — none touched (edited files are repo-root test machinery, below the
model's component granularity); (d) actor↔surface relationships — unchanged. The local
`--affected` selector and its oracles are not C4 elements.

## Guard Contract

### Guard 1 — root-level corpus detection row (PR-A, FR3)

**Property.** A dir-less repo-root file matching the corpus extensions (`*.test.sh`, `*.sh`)
produces a RED th-family row on the next full battery run — the latent grammar gap can never land
silently.

**Assembly.** One chokepoint: `_th_ls_files()` — `git -C "${_TH_REPO:-$REPO_ROOT}" -c
core.quotePath=false ls-files`, confined to `"$TESTROOT"` when overridden — invoked per-evaluation:
`_TH_ROOTS` derives through it at load; the detection row re-invokes it in a row-local subshell so
a mutation arm's `_TH_REPO` repoints the real producer without touching the th4–th6 population.
The complement filter classifies `*.test.sh` vs `*.sh` disjointly (a `\.sh$` monolith would mask a
dropped `.test.sh` arm). The guard's dispatch is the battery's `cases`/PASS+FAIL==cases
accounting.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Point `_TH_REPO` at a `TESTROOT` fixture repo containing a dir-less `x.test.sh` | RED — the property fails while the producer works (precondition holds, property fails) |
| 2 | Point `_TH_REPO` at an empty `TESTROOT` fixture repo (ls-files emits nothing) | RED — liveness floor fires on the empty `_TH_LISTING` capture; a dead producer must not read "zero root files" = green (own-dispatch) |
| 3 | Fixture repo with TWO dir-less corpus files, one per extension (`x.test.sh` + `y.sh`) — pins both extensions and the no-stop-at-first enumeration | RED |
| 4 | Mutation drops the `.test.sh` arm of the disjoint complement filter (`x.test.sh` fixture goes unflagged) | RED — extension-completeness row; vacuous under a monolithic `\.sh$`, which is why the disjoint classes are load-bearing |
| 5 | Must-PASS non-canonical input: fixture repo whose only dir-less file is non-corpus (`x.md`) | PASS — NF==1 but wrong extension; the row discriminates |
| 6 | `_TH_REPO` set outside `"$TESTROOT"` (a sibling `.worktrees/` checkout — populated, not empty) | RED — confinement refuses; a foreign-but-populated listing must not read green |

**Anchor.** `git ls-files` is outside the diff, but the `_TH_ROOTS`/`NF==1` derivation is NOT —
the shared-function refactor puts both filters inside it. The liveness floor covers the
empty-producer case; the wrong-filter case is backstopped by th4/th4b/th4c reading the same
`_TH_ROOTS` (a weakened derivation reds them too).

### Guard 2 — census tail-matchability predicate (PR-A, FR2)

**Property.** `_th6_root_covered` certifies a `glob:` member covers a (root, corpus-ext) pair only
when the member's head covers the root AND the tail is a bare wildcard to the corpus extension —
literal-in-glob, subset, subdir-scoped, and wrong-ext tails all decline.

**Assembly.** The predicate (`test-all-affected.test.sh`:3036-3044) is the single chokepoint every
(root × corpus-tail) census evaluation flows through; the member set derives live from the declared
arrays + `_TH_ROOTS`; the battery's decline/accept rows and `SANDBOX_MUT_*` arms are the dispatch.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Revert the tail check to the old suffix form (`*<ext>` case match) | RED — the literal-in-glob decline row (`glob:root/x.test.sh` must not certify) fails |
| 2 | Delete the metachar requirement inside the predicate (accept any tail) | RED — same decline rows; a predicate that accepts everything is the defect |
| 3 | Supply TWO non-covering members after a compliant fixture head (`glob:root/pre*.test.sh` + `glob:root/sub/*.test.sh`) | RED — subset/subdir-scoped tails each decline; the enumeration does not stop at the first |
| 4 | Harness row: mutate the battery's own decline-case fixture so the "must decline" input is actually covering (`glob:root/*.test.sh` where a decline was scripted) | RED — guards a vacuous harness arm |
| 5 | Must-PASS non-canonical input: `glob:root/**.test.sh` (`**` — the spelling every live declaration actually uses) | PASS — both bare-wildcard forms certify |
| 6 | Mutation drops the head anchor's `/` (`glob:$2*` prefix instead of `glob:$2/`) | RED — the head-side decline row (`glob:<root>x/**.test.sh` must not certify for root `<root>`) catches it |

**Anchor.** The corpus-tail set and `_TH_ROOTS` derive live from the tree; the predicate, fixtures,
and expected verdicts land in one commit — weakening the predicate without the fixtures goes red.

### Guard 3 — `covers()` dir-ref all-containment (PR-B, FR4)

**Property.** The oracle's dir-ref arm reports covered only when every tracked member under the
referenced directory matches the glob tail — path nesting alone never certifies coverage.

**Assembly.** `covers()`'s dir-ref arm (`test-affected-kb-consumers.test.sh`:268-296) is the
chokepoint every dir-ref REF flows through; `_TRACKED` (the `tracked()` materialization, kb-scoped)
is the member source; the oracle's own k5 vector and `SANDBOX_MUT_*`-shaped mutation rows are the
dispatch; the committed baseline + b1/c1 rows are the ratchet.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Restore the nest clause (`head.startswith(p…)`) as the dir-ref verdict | RED — the extended k5 vector's new dir-ref cases decline under all-containment |
| 2 | Make all-containment ANY-containment (`any()` instead of `all()`) | RED — second-member defect class: a dir whose first member matches but second does not must report uncovered |
| 3 | Empty-member derail: `tracked()` returns no members for a kb-scoped ref dir | RED — all() over an empty set is vacuous-true; the arm must decline an empty member set (own-dispatch equivalent). (Non-kb dir refs keep the nest clause — kb refs are the enumerated population.) |
| 4 | Harness row: extend the k5 expectation vector wrongly (stale `1` where all-containment yields `0`) | RED — expectation-vector mismatch guards a stale harness |
| 5 | Must-PASS non-canonical input: a dir ref whose members all match via `**` tail (nested member depth) | PASS — coverage by matching, not by canonical shape |

**Anchor.** The baseline is stored-vs-regenerated compared by row b1 — a regen that hides a real
new violation needs the code and the baseline edited in one diff, which b1 + c1 + the disposition
table in the PR make visible; `_TRACKED` derives from `git ls-files` outside the diff.

## Implementation Phases

The two PRs are independent; each carries its own RED-first row ordering.

### PR-A — `feat-10117-hardening` (items 3+4+2 + ADR amendment)

#### Phase 1 — Battery rows, RED-first

0. Fixture sweep first: `rg 'glob:' scripts/test-all-affected.test.sh` over the sandbox fixture
   members — the tightened FR2 predicate flips any existing fixture that scripts a non-bare tail
   as an accept case; reconcile those before writing new rows.
1. `scripts/test-all-affected.test.sh`: add the q-family pin
   (`--print-selection --paths=./<p>` selects identically to `--paths=<p>`; plus one reject-class
   pin per class in Test Scenarios), the FR2 decline/accept rows (literal-in-glob, subset
   `pre*.test.sh`, subdir `sub/*.test.sh`, head-side `<root>x/`, overlap `**.test.sh`-for-`.sh`,
   wrong-ext all decline; `*<ext>`, `**<ext>`, and a bare `<root>/` dir member accept), and the
   FR3 detection row with producer-liveness floor.
2. Run the suite; record new rows RED (FR1/FR2 rows fail on current predicates; FR3 row passes
   today — zero dir-less corpus files — its RED demonstration is the mutation row, not the live
   tree).
3. Bump `MIN_CASES`; grep and reconcile every count literal.

#### Phase 2 — Predicates + normalization

1. `scripts/test-all.sh` ~:307 `--paths=` parse arm: per-element `./`-to-fixpoint strip, the
   reject set with a named error (echo the offending element + a valid example), rejoin into
   `_PRINT_PATHS`; update the `--help` line (:333-334).
2. `scripts/test-all-affected.test.sh` `_th6_root_covered`: bare-wildcard tail requirement.

#### Phase 3 — ADR amendment + verify

1. ADR-242: append `## Amendment — 2026-10-13 (#10117)` with decision 27; add `amended_by:` entry.
2. Full `bash scripts/test-all-affected.test.sh` green; `bash scripts/test-all.sh --affected` sanity;
   `bash scripts/test-affected-kb-consumers.test.sh` green (no new baseline rows — kb literals are
   fixture-scoped per Technical Considerations).

### PR-B — `feat-10117-covers-containment` (item 1)

#### Phase 1 — Oracle rows, RED-first

1. Extend the k5-family vector with dir-ref cases whose verdicts all-containment changes
   (the two nest-clause positions flip `1`→`0`; add member-mixed dir-ref cases).
2. Add the Guard-3 mutation rows (`SANDBOX_MUT_*` or the scratch-copy oracle idiom at :680-696).
3. Run `bash scripts/test-affected-kb-consumers.test.sh`; record the new rows RED.

#### Phase 2 — `covers()` arm + regen + dispositions

1. Rewrite the dir-ref arm: enumerate `tracked()` members under the ref dir; require all match the
   glob tail; empty member set declines.
2. Extend the `baseline` emitter for classified `argv-code` rows (incl. the `UNCLASSIFIED`
   new-row stamp + the u-family 4-col fixture + the c1 remedy message), then `--write-baseline`
   regen **in the same commit as the `covers()` change** (b1 must not be red mid-commit); inspect
   the diff line-by-line; reappearing rows get a per-row disposition (covering edge — conditional
   `test-affected-paths.sh` edit, runner-critical / `false-positive:` in-file / narrowed scan).
   **Rebase onto origin/main immediately before the regen** (drawdown precedent). Stale-doctrine
   hygiene in the same diff: the `covers()` comment block at :272-277 (five-site invariant) and
   :288-294 ("tightening is tracked as a scope-out" — now landed) get updated.
3. Verify: oracle suite green; `b1`/`c1` gates green; disposition table complete — every new row
   ruled. PR body carries a row-count delta summary plus the disposition table **grouped by
   disposition type** (rows are expected to be dominated by bare `knowledge-base` dir refs).
   PR-A's body notes that `affected-prepass-bench.sh --probe` forwards into `--paths` — a bad
   probe now exits rc 2 (`DIFFERS`), loud but cryptic — one orientation line.

## Files to Edit

- `scripts/test-all.sh` — `--paths=` parse arm (~:307): per-element `./` strip + `..`/absolute
  reject (PR-A)
- `scripts/test-all-affected.test.sh` — `_th6_root_covered` (:3036-3044); new q-family `--paths=./`
  pin, FR2 decline/accept rows, FR3 detection row beside `_TH_ROOTS`; `MIN_CASES` + count literals
  (PR-A)
- `knowledge-base/engineering/architecture/decisions/ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md`
  — `amended_by:` + `## Amendment — 2026-10-13 (#10117)` decision 27 (PR-A)
- `scripts/test-affected-kb-consumers.test.sh` — `covers()` dir-ref arm (:268-296); k5 vector
  extension; mutation rows (PR-B)
- `scripts/test-affected-kb-consumers.baseline.txt` — row *membership* is regen-only (b1's
  first-3-column compare enforces it); the 4th classification column is the one sanctioned
  hand-edit — reasons enter by hand-seeding after regen, then `--write-baseline` carries them
  forward (re-regen verifies carry-forward). (PR-B)
- `scripts/lib/test-affected-paths.sh` — CONDITIONAL, PR-B only: if a reappearing row dispositions
  to a new covering edge; such an edit makes the PR runner-critical (`runner-changed` → local
  full battery). Preferred dispositions leave it untouched.
- `scripts/test-affected-kb-consumers.test.sh` also carries `MIN_CASES=22` (:741) — bumped with the
  k5/mutation additions (named, not only generic "count literals").

## Files to Create

None.

## Open Code-Review Overlap

- **#8800** (`test fixture: census sandbox shares inodes/symlinks with live repo`) touches
  `scripts/test-all-affected.test.sh` and `scripts/lib/test-affected-paths.sh` — **Acknowledge.**
  Fixture-isolation concern; this plan's new rows add sandbox fixtures but do not worsen the
  write-through hazard (reads only). Scope-out stays open.
- **#8659** (EXIT-trap replacement leaks incident sandbox) and **#7942** (unregistered
  `*.mutation.sh` batteries) mention `scripts/test-all.sh` — **Acknowledge.** Adjacent test-hygiene
  concerns, different subsystems of that file; the FR1 edit is a ~10-line parse-arm change with no
  interaction.
- **#9323** overlaps FR2's mutation-row territory (path-gate self-test batteries) — **Acknowledge**;
  new rows follow that battery's direction.
- **#10117** is this plan's own issue (self-reference, not an overlap).
- **#8621** (selector convergence) may relocate `--paths` handling — noted in Dependencies & Risks.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "`covers()` dir-ref extension blindness … `glob:knowledge-base/plans/archive/**.md` "covers" the ref while only the `.md` class is covered" [issue #10117] | PR-B Phase 2 (`covers()` all-containment) + k5 vector extension + Guard 3 | mapped |
| 2 | "Root-anchored grammar gap … a root-level `*.test.sh`/`*.sh` corpus file is unrepresentable" [issue #10117] | FR3 detection row + ADR-242 decision 27 (detect-not-extend) + #10198 deferral | mapped (detection, not extension — brainstorm ruling) |
| 3 | "`--paths` `./` normalization … `--paths=./foo` silently misleads" [issue #10117] | PR-A Phase 2.1 (parse-arm normalization) + q-family pin | mapped |
| 4 | "`_th6_root_covered` validates string suffix shape rather than actual matchability" [issue #10117] | PR-A Phase 2.2 (bare-wildcard predicate) + FR2 decline/accept rows + Guard 2 | mapped |
| 5 | "Two independent PRs" [operator packaging decision] | PR-A/PR-B split in Implementation Phases | mapped |
| 6 | "Authorize full scope" [operator authorization covering all four items] | all of the above | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `scripts/test-all.sh` parse-arm normalization | ask 3 ("`--paths` `./` normalization") | asked |
| `_th6_root_covered` tightening + decline/accept rows | ask 4 ("validates string suffix shape rather than actual matchability") | asked |
| FR3 detection row | ask 2 (root-anchored gap) — detection is the brainstorm-ruled shape of the ask | asked |
| `covers()` all-containment + baseline regen | ask 1 (`covers()` dir-ref extension blindness) | asked |
| ADR-242 amendment (decision 27) | — | inferred — justification: "detect-not-extend until a live trigger" is a durable grammar-doctrine decision; the ADR corpus is its home, and an undocumented deferral reads as an oversight to the next engineer (plan Phase 2.10) |
| Disposition table (PR deliverable, not a file) | ask 1 — the residual's fix is defined by how reappearing rows are ruled | asked |
| `MIN_CASES`/count-literal bumps | — | inferred — justification: new battery rows change the family's own floors; without the bump the suite's own accounting fails |

### Split Assessment

- Subsystems touched: 2 — `scripts`, `knowledge-base`
- Planned files: 5 | Estimated changed lines: ~350 (PR-A ~150, PR-B ~200)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split — operator-decided two-PR packaging; the blast-radius boundary is
  judgment-free hardening (PR-A) vs. baseline-disposition judgment (PR-B)

## Acceptance Criteria

- [ ] `bash scripts/test-all.sh --print-selection --paths=./<p>` selects the identical set as
      `--paths=<p>` for a tracked fixture path; every reject class (empty/`.`/`./`-residual,
      absolute, segment-`..` incl. `a/../b`, `//`/`/.` segment, trailing `/`, TAB, LF) exits 2
      with a named error echoing the element + a valid example (PR-A)
- [ ] `_th6_root_covered` declines `glob:<root>/x.test.sh` (literal-in-glob),
      `glob:<root>/pre*.test.sh` (subset), `glob:<root>/sub/*.test.sh` (subdir-scoped),
      `glob:<root>x/**.test.sh` (head-side), `glob:<root>/**.test.sh` for a `.sh` corpus
      (overlap), and wrong-ext tails; accepts `*<corpus-ext>`, `**<corpus-ext>`, and a bare
      `<root>/` member (PR-A)
- [ ] A `git ls-files` `NF==1` `*.test.sh`/`*.sh` member produces a RED detection row whose message
      names the deferred grammar extension; the row's producer-liveness floor REDs on an empty
      ls-files (PR-A)
- [ ] ADR-242 carries `## Amendment — 2026-10-13 (#10117)` with decision 27 and an `amended_by:`
      entry (PR-A)
- [ ] `covers()` reports a dir ref uncovered when any tracked member under it fails the glob tail;
      the k5 expectation vector includes the new dir-ref cases (PR-B)
- [ ] `scripts/test-affected-kb-consumers.baseline.txt` regenerated via `--write-baseline`; every
      reappearing row has a recorded disposition — in-file `false-positive:` classification via
      the emitter extension, a covering edge, or a narrowed scan — plus the PR's per-row
      disposition table grouped by type; `b1`/`c1` green; zero `UNCLASSIFIED` rows (PR-B)
- [ ] `bash scripts/test-all-affected.test.sh` and `bash scripts/test-affected-kb-consumers.test.sh`
      green on both PRs; `MIN_CASES` and count literals reconciled
- [ ] PR-A and PR-B are independent — either merge order lands green
- [ ] All new rows observed RED before their predicate/normalization edits (RED-first, recorded in
      each PR body)

<!-- founder-stated check: see plan-founder-check.md -->

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** carried forward from brainstorm — CTO ruled the per-item mechanism
(bare-form matchability for FR2, parse-site normalization for FR1, all-containment for FR4,
detection-row-not-grammar for FR3); CPO/CLO assessed near-zero product/legal surface. Internal
test machinery, not shipped in the plugin.

**Brainstorm-recommended specialists:** none recommended by name in the domain assessments.

## Test Scenarios

- Given `--paths=./scripts/foo.test.sh`, when `--print-selection` runs, then the printed selection
  equals `--paths=scripts/foo.test.sh`'s (unit — battery q-family pin)
- Given `--paths=../esc`, `--paths=/abs`, `--paths=a/../b`, `--paths=a,,b`, `--paths=././x`,
  `--paths=$'a\tb'`, `--paths=$'a\nb'`, or `--paths=dir/`, when parsed, then a named reject
  (rc 2 + message echoing the element and a valid example) — not a silent empty selection (unit)
- Given `--paths=foo..bar.sh` or `--paths=a b.sh`, when parsed, then accepted — the `..` reject is
  segment-anchored and spaces in filenames are legal (unit)
- Given `glob:<root>/x.test.sh` declared, when th6 evaluates the root's `.test.sh` corpus, then it
  declines (unit — FR2 decline row)
- Given a dir-less `x.test.sh` (and separately `y.sh`) in a `TESTROOT` fixture repo via `_TH_REPO`,
  when the detection row runs, then RED with the grammar-extension remedy named; given `_TH_REPO`
  outside `TESTROOT`, then refused (unit — FR3 row + mutations)
- Given a dir ref `knowledge-base/plans` with mixed `.md`/`.sh` members and a
  `glob:…/**.md` edge, when `covers()` evaluates, then uncovered (unit — k5 extension)
- Given the regen, when `b1`/`c1` rows run, then stale/missing/unclassified baseline rows fail
  (integration — existing oracle gates)
- Given both PRs, when merged in either order, then both suites green (integration)

## Success Metrics

- `--paths=./` selection parity; named rejects for escape spellings
- Census declines the four non-covering tail shapes, accepts both bare forms
- Zero dir-less corpus files undetected (row REDs within one full-battery run of introduction)
- Baseline regen leaves zero unexplained rows; every new row dispositioned
- Either merge order green

## Dependencies & Risks

- **#8621** (selector convergence) may relocate `--paths` handling — land FR1 early in PR-A; the
  parse-site edit is small and relocates cleanly.
- **#9323** overlaps FR2 mutation-row territory — keep new rows consistent with its direction.
- **Reappearing-row set unmeasured** — ≥5 lint-orphan rows expected; actual count at regen. A
  large unexpected set is a replan signal, not a wider baseline.
- **Real-runner flake** — real-runner arms can fail empty under sibling-gate contention; re-run to
  isolate before diagnosing. Prefer grep/static probes in AC commands over the full
  `--print-selection` walk (>60s cap).
- **PR-B ordering hazard** — baseline regen rewrites 240-row TSV; rebase onto origin/main
  immediately before the regen commit (drawdown precedent).

## References & Research

- Brainstorm: `knowledge-base/project/brainstorms/2026-10-13-edge-coverage-residuals-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-10117-edge-coverage-residuals/spec.md`
- Issue: #10117; deferred grammar extension: #10198; draft PR: #10190
- Prior plan (direct precedent): `knowledge-base/project/plans/2026-10-12-fix-affected-edges-under-cover-siblings-plan.md`
- ADR-242 (amendment target, decision 27 next): `knowledge-base/engineering/architecture/decisions/ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md`
- Disposition-table precedent: `knowledge-base/project/specs/archive/20261013-062704-feat-affected-parallel-test-gate/always-on-audit.md` §D2
- Key code: `scripts/test-all.sh`:307 (parse), :2095-2099 (ingestion), :2855-2870 (`_affected_normpath`);
  `scripts/test-all-affected.test.sh`:3028-3044 (`_TH_ROOTS` + `_th6_root_covered`), :2619-2845
  (p/q families); `scripts/test-affected-kb-consumers.test.sh`:268-296 (`covers()`), :368-375
  (`--write-baseline`), :702-725 (k5); `scripts/lint-orphan-test-suites.sh`:1104-1198 (census)

## Sharp Edges

- `m6` anchors the exact `_diff_names` line and `q6` greps the `_aff_child_paths` shape — the FR1
  normalization lives at the parse arm, not at :2096.
- `_affected_normpath` is defined at :2855 — after the top-level `--paths` ingestion; it cannot be
  called there (rc 127). Normalization must not be placed at the ingestion block.
- A single-member `[[ == ]]` witness under-declines subset tails (`x.test.sh` matches `*x.test.sh`);
  the predicate is the bare-wildcard form check, not the spec's literal witness wording.
- `argv-code` baseline rows carry a 4th classification column only via the emitter extension —
  b1 compares the first three columns; a hand-written 4th column on a 2-col-emitted row is still a
  b1 failure, so the column exists only because the emitter writes it.
- FR1 is INLINE per-element normalize+reject at the parse arm — `_affected_normpath` is defined
  at :2855 and callable nowhere near the parse arm or :2096 (and it collapses `a/../b` where this
  plan rejects — wrong semantics besides); do not "fix" this by calling it. Strip `./` to
  fixpoint, THEN reject residual `./`-heads — single-pass `${p#./}` leaves `--paths=././x` still
  misleading. The `..` reject is segment-anchored (`..`/`../*`/`*/..`/`*/../*`), not substring —
  `foo..bar.sh` is a legal tracked name. `a/../b` is REJECTED, not collapsed (spec contemplated
  collapse; divergence recorded in Proposed Solution). LF as well as TAB is a reject byte.
- FR2's `[[ "$tail" == "*${ext}" ]]` is a LITERAL compare — the quotes carry the fix; unquoting the
  RHS degenerates to the old suffix check, and the load-bearing quoting must be an inline code
  comment (it looks like a glob to a future reader). Tail extraction is `${_m#"glob:$2/"}` — quote
  the pattern so `$2` can't glob inside `#`. The head anchor is the literal `glob:$2/` prefix:
  decline `glob:<root>x/**.test.sh` (head-side) and keep the bare `<root>/` disjunct that covers
  `_TH_PREFIX_ROOTS`.
- FR3's producer is the `_th_ls_files()` FUNCTION (re-invocable per evaluation) — a single frozen
  capture would leave every `_TH_REPO` mutation arm dead; the row re-invokes it in a subshell and
  `_TH_REPO` is confined to `"$TESTROOT"`. The complement filter classifies `.test.sh` vs `.sh`
  disjointly — a monolithic `\.sh$` subsumes `.test.sh` and makes the extension-arm mutation
  vacuous. `-c core.quotePath=false` is load-bearing for non-ASCII names; fixtures `git add -f`;
  the liveness floor binds to the producer output, never to the complement's.
- `covers()`'s dir-ref arm must materialize `_TRACKED` itself (k5's `_cov` calls it on a fresh
  module) and new rows must `cd "$REPO_ROOT"`.
- Baseline: row membership is `--write-baseline` only after rebase; the 4th classification column
  is the sanctioned hand-edit (seeded by hand, carried by regen).
- `discoverability_test` pins `grep -c 'NF==1'` == 1 — new code/comments must not spell the token
  a second time; re-derive the count post-implementation if a second `NF==1` site is unavoidable.
- Never `producer | grep -q` under pipefail; capture rc on its own line; `cases` incremented at the
  call site.
- Never edit `test-all-affected.test.sh`/`test-all.sh`/`test-affected-paths.sh` while a battery run
  reads them.
- kb literals in test code are composed/fixture-scoped, never bare `knowledge-base/` literals.
- A plan whose `## User-Brand Impact` section omits the threshold fails deepen-plan Phase 4.6.
- After the ADR amendment, verify `scripts/check-adr-ordinals.sh` and re-grep the feature's own
  artifact set for the ordinal (a sibling PR can claim 23 mid-pipeline).
