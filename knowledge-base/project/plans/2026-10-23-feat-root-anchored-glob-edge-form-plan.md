---
title: "feat: root-anchored glob: edge form for dir-less repo-root corpus files"
date: 2026-10-23
slug: feat-root-anchored-glob-edge-form
branch: feat-one-shot-10198-root-anchored-glob
issue: 10198
closes: 10198
type: feat
priority: p3-low
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# feat: root-anchored glob: edge form for dir-less repo-root corpus files

## Overview

Extend the `glob:<literal-head>/<glob-tail>` declared-edge grammar (ADR-242 decision 22) with a
root-anchored form so a dir-less `x.test.sh`/`x.sh` at repo root is expressible as a coverage edge:
a leading metachar-free head that is `/`-free (the empty head included, `glob:*.test.sh`) anchors
the whole pattern at the repository root and matches only dir-less diff lines. The extension keeps
the "ONE doctrine, FIVE sites" malformed-shape invariant — the mint arm `_affected_add_edge` and hit
arm `_diff_edge_hit` in `scripts/test-all.sh`, the census arm in
`scripts/lint-orphan-test-suites.sh`, the `covers()` oracle in
`scripts/test-affected-kb-consumers.test.sh`, and the `GLOBENT` registration-only classifier — and
pulls in the deferred `_affected_glob_split` helper extraction (the issue is the "next grammar
touch" the advisory waited on), reworks the th8 dir-less detection row into a coverage census, and
amends ADR-242 with decision 28. Issue #10198.

## Problem Statement / Motivation

ADR-242 decision 22's `glob:` grammar requires the literal head to end in `/`, so a corpus member
with no directory — a dir-less `x.test.sh`/`x.sh` at repo root — has no head to mint and is
unrepresentable as a declared edge. Decision 27 (the #10117 amendment) chose *detect-not-extend*:
the th8 row in `scripts/test-all-affected.test.sh` REDs on existence of any dir-less corpus member,
and the grammar extension was deferred to #10198 pending a live trigger. Neither stated trigger has
fired — `git ls-files | grep -cE '^[^/]+\.(test\.sh|sh)$'` is still `0` and `SUITE_GLOBS`
(`scripts/test-all.sh`:96-109) gained no root-level glob — but the operator pulled the issue, so the
extension lands now: it closes the last unexpressible corpus class, and because every grammar touch
must keep five classifiers in lockstep, it is also the cheap moment to pay down the
`_affected_glob_split` helper-extraction advisory (one shared bash classifier instead of three
hand-synced copies plus a test-side fourth).

The true site count is wider than the doctrine's named five — the plan's own census:

1. Mint arm `_affected_add_edge` — `scripts/test-all.sh` (~:2844-2914). Today a `/`-free head falls
   to `*) _p="^glob:${_p}" ;;` malformed → mints an always-match verbatim edge.
2. Hit arm `_diff_edge_hit` — `scripts/test-all.sh` (~:2187-2240). `[[ "$_gh" == */ ]] || return 0`
   → always-match.
3. Census arm — `scripts/lint-orphan-test-suites.sh` (~:1113-1172). `_cgh` not ending `/` →
   "its head does not end in /" static RED.
4. `covers()` oracle — `scripts/test-affected-kb-consumers.test.sh` (~:279-321).
   `not head.endswith("/")` → always-cover.
5. `GLOBENT` awk regex — `scripts/test-all.sh` (:2411) — requires `<head>/` (≥1 char + slash);
   a `/`-free member is not admitted → stays `semantic`.
6. `edge_hit()` — `scripts/ci-pr-affected-replay.py` (:967-1019), a Python MIRROR of the hit arm
   (its docstring pins bash-vs-python parity): `not head.endswith("/")` → always-match.
7. Copy sites (test-side): `materialise()`'s `_mp` split in
   `scripts/lint-orphan-test-suites.test.sh` (:163) — `/`-free head already no-ops correctly —
   and the Rg mint battery in `scripts/test-affected-derive.test.sh` (:1101-1170), whose Rg3
   malformed vector lists `glob:*.sh` as malformed — that fixture FLIPS to well-formed.

## Research Insights

**Premise Validation (Phase 0.6):** issue #10198 is OPEN (p3-low, `type/feature`, `meta/machinery`,
milestone Post-MVP / Later). The issue's own re-evaluation criteria — "reopen when the detection
row fires or when `SUITE_GLOBS` gains a root-level glob" — have NOT fired (dir-less corpus count 0,
SUITE_GLOBS unchanged, both re-measured 2026-10-23 on this worktree); the pull is an operator
priority decision, not a trigger event, and the ADR amendment records that honestly. All cited
artifacts verified live: `_affected_add_edge`/`_diff_edge_hit` (test-all.sh), the census arm
(lint-orphan), `covers()` (kb-consumers, now all-containment post-#10117), `GLOBENT` (:2411), the
th8 row machinery (`_th_ls_files`/`_th_root_corpus`/`_th8_eval`/`_th8_fix_repo`,
test-all-affected.test.sh:3117-3743), ADR-242 decisions 22 + 27 (28 is the next intra-file
ordinal), and the `_affected_glob_split` advisory (recorded deferred-to-next-grammar-touch in the
#9813 session-state, the #10117 brainstorm and the 2026-10-10 learning). Nothing stale.

**Property List (Phase 0.6b):**

- P1: a dir-less repo-root `*.test.sh`/`*.sh` is expressible as a coverage edge in the `glob:`
  grammar — the class form, not a per-file literal.
- P2: every site that classifies a `glob:` shape keeps identical verdicts (one doctrine) — mint and
  hit agree, the census REDs what runtime widens, mirrors track, GLOBENT stays a superset.
- P3: the th8 row's expectation is reconciled with the extended grammar — detection on existence
  becomes coverage census (decision 27's own "the row's expectation revisits what the new grammar
  expresses").
- P4: the shape-classification logic lives in ONE bash implementation (`_affected_glob_split`),
  not four copies — the deferred advisory's deliverable.
- P5: ADR-242 records the extension as a numbered decision and the lib header + site comments stop
  teaching the old doctrine.

**Cut List (Phase 0.6b):**

- A distinct spelling for the root form (`glob:/*.sh`, `glob:./`, a new `rootglob:` kind) → P1 —
  **cut**: every one collides with an existing malformed class (`/`/`./` heads are deliberately
  non-repo-relative today) or adds a second edge kind to five sites; the `/`-free-head form needs no
  new syntax — it is the shape the grammar currently rejects.
- Per-file literal edges as the interim answer → P1 — **cut**: literal edges already exist and cover
  exactly one file each; decision 22's alternatives table rejected per-suffix literals for the same
  drift class (`*.test.sh` members arriving later silently under-cover until arrays are re-edited).
- Extending `SUITE_GLOBS` registration discovery to root-level `*.test.sh` → P1 — **cut**: out of
  the issue's scope (edge grammar, not suite discovery); a dir-less suite file's registration is a
  separate mechanism (`run_suite` argv0) and zero members need it.
- Rewriting `covers()`/GLOBENT/`edge_hit` to consume the bash helper → P2 — **cut**: Python and awk
  cannot share a bash function; the doctrine is already "one bash implementation + mirrors +
  superset", and forcing a single implementation language is churn for zero verdict change.
- Removing the th8 row now that the grammar can express coverage → P3 — **cut**: that resurrects
  the silent hole — a dir-less member with NO covering edge would be invisible again; the census
  form is the durable version of the same guard.

**Research findings (inline repo research + prior-plan carry-forward):**

- Mint arm degrade ladder today: charset-clean + `_gh` (`${_g%%[*?[]*}`) `*/`-terminated → `-d`
  probe mints `^glob:<pattern>` or degrades to `^<head>/` prefix; all other shapes mint
  `^glob:<verbatim>` (always-match). For root form: no `-d` probe exists to degrade (the root is
  always present) → mint `^glob:<pattern>` directly.
- Hit arm cheap head pre-check `[[ "$_n" == *"${_NL}${_gh}"* ]]` is a substring may-admit; for an
  empty root head it degenerates to always-true (harmless) — keep it conditional on non-empty head.
- Bash `[[ == ]]` `*` crosses `/` — the load-bearing fact: a `/`-free pattern like `*.test.sh`
  matches `a/x.test.sh` unless the arm ALSO requires the line to be dir-less (`!= */*`). Same in
  Python (`fnmatch.fnmatchcase("a/b.sh", "*.sh")` is True) — the dir-less predicate is the whole
  feature; both mirrors need it.
- `covers()` dir-less-dir trap: EVERY dir ref under a root-anchored `^glob:` declines outright —
  including nested refs like `a/b` (Python `fnmatch`'s `*` crosses `/` exactly like bash
  `[[ == ]]`, so `fnmatchcase("docs/x.sh", "*.sh")` is True). A top-level dir ref (`docs`,
  `knowledge-base`) is `/`-free, so the root arm must decline dir refs
  (`p in _tracked()[1] or os.path.isdir(p)`) or `glob:*` would
  certify a whole dir.
- Reclassification safety: `glob:x*.sh` (non-empty `/`-free head) is malformed TODAY and the census
  REDs it ("its head does not end in /" — M22 pins this), so no live tree can carry one; upgrading
  it from always-match to a real narrow edge cannot silently narrow anything live. Recorded in the
  ADR amendment.
- `_edge_src` extraction (`test-all-affected.test.sh`:2582) and `DERIVE_SRC` extraction
  (`test-affected-derive.test.sh`:71-75) pull runner text by content anchors — a helper living in a
  lib is OUTSIDE both windows, so `_edge_run`/`derive_run` must `source` the glob lib inside the
  eval. `build_sandbox` (:133-137) and `build_pristine` (:215-224) copy libs explicitly — one `cp`
  line each.
- Sibling constraint: open S4 drain PR #10945 (`feat-one-shot-s4-affected-index-pr4-code-edge-drain`)
  mass-appends `AFFECTED_*_PATHS` arrays inside `scripts/lib/test-affected-paths.sh`; this plan
  touches that file ONLY in the top-of-file doc comment (:35-46) and puts the helper in a NEW lib —
  zero data-region collision. Its `lint-orphan-test-suites.sh` touch is "run it" only per its plan.
- `audit-suite-reads.sh` `UNCOVERED_AWK` (:191, :708-712) treats `^glob:` edges as
  literal/prefix strings — a read covered solely by a root-anchored `^glob:` member reports
  uncovered → over-report, the safe direction (same note as decision 27).
- kb literal discipline: every `knowledge-base/` literal in new test code is composed
  (`"knowledge""-base"`, `${_KB}`) — the kb-consumers oracle charges bare tokens as reads.
- Community/functional overlap: none (bespoke repo-internal machinery — same finding as the prior
  plan's registry scan).

## Research Reconciliation — Spec vs. Codebase

No `specs/feat-one-shot-10198-root-anchored-glob/spec.md` exists; the issue body is the source of
truth. Reconciling ITS claims against the tree:

| spec/issue claim | reality | plan response |
|---|---|---|
| "the extension touches the 'ONE doctrine, FIVE sites' malformed-shape invariant" — five sites named | six sites classify plus two test-side copies: `ci-pr-affected-replay.py` `edge_hit()` (:967-1019) is a Python mirror of the hit arm with identical malformed rules, and `test-affected-derive.test.sh` Rg3 (:1142) fixtures `glob:*.sh` as malformed | sites six and seven added to Files-to-Edit; Rg3 vector re-anchored; the doctrine comment enumerates the mirror honestly |
| "the gap is consistent with registration reality — `SUITE_GLOBS` cannot register one" | still true (verified: no root-level glob in SUITE_GLOBS); still zero dir-less corpus members | the extension is landed ahead of trigger per operator pull — stated in the ADR amendment, not implied |
| "reopen when the detection row fires … or `SUITE_GLOBS` gains a root-level glob" | neither fired | th8's census rework keeps the loud-on-uncovered property so the row's purpose survives without the trigger |

## Proposed Solution

One PR, four ordered movements. The grammar rule first, then where each site learns it:

**The extension rule.** `_AGS_HEAD` = the leading metachar-free run of `glob:`'s payload (today's
`${_g%%[*?[]*}`). A head containing `/` must end in `/` (dir-anchored — today's only legal head) or
is malformed; a `/`-free head — empty (`glob:*.test.sh`) or non-empty (`glob:x*.sh`, a root
file-prefix glob) — is ROOT-ANCHORED: the minted `^glob:` edge matches a diff line iff the line is
dir-less (`!= */*`) AND matches the whole pattern under bash `[[ == ]]`. A `/`-bearing tail under a
`/`-free head can never match a dir-less line → malformed (degrade-wider / census-RED), same
verdict class as a `/`-ending tail. Tail keeps the existing rules: carries `*`, never ends `/`.

**Phase 1 — `_affected_glob_split` extraction (doctrine-neutral refactor).** New
`scripts/lib/affected-glob.sh` defines one total classifier over the payload: emits
`_AGS_CLASS ∈ {literal, dir, malformed}` (root arrives in Phase 3), `_AGS_WHY` (token map:
`literal | charset | qbracket | head-not-reporel | head-mid-slash | tail-trailing-slash |
tail-no-star`), `_AGS_HEAD`, `_AGS_TAIL`; rc 0 always — malformed is data, never a failure arm
(`set -e`/`&&`-chain safe). Rewire the three bash sites to call it: mint arm (keeps its `-d` probe +
degrade spellings), hit arm (keeps return-0/1 verdicts), census arm (maps `_AGS_WHY` to its existing
message strings); `materialise()`'s `_mp` site in the test file switches too. Plumbing that must
land in the same phase: `test-all.sh` gains a glob-lib source in the `_AFF_LIB` block with
`_AFF_LIB_OK` requiring `declare -F _affected_glob_split` (a missing helper ≡ index-missing ≡
select-all degrade — never a mid-run rc-127 abort); `lint-orphan-test-suites.sh` sources it
fail-closed beside REL/AFF; `build_sandbox` and `build_pristine` each gain one `cp` line;
`_edge_run`/`derive_run` source the lib inside their evals. Every existing row stays green — the
phase proves neutrality.

**Phase 2 — RED-first battery rows.** Author the new rows before the code that satisfies them:
root-anchored mint accepts + root-malformed verbatims (`_edge_run` t-family + derive Rg), hit-arm
dir-less select/narrow probes (a sandbox lib member mutated to `glob:*.test.sh` — `x.test.sh`
selects the carriers, `a/x.test.sh` does NOT — the narrowing is the feature), census accept/decline
M-rows (`glob:*.test.sh` valid; `glob:x*/y` root-tail-slash RED; M22's `a*/b` fixture re-anchored to
`a/b*c` so the "does not end in /" class survives), covers() k5 vector cells (the `foo*.sh` cell
flips 1→0 plus dir-less/dir-bearing/dir-ref cells), GLOBENT admit/semantic registration fixtures,
`edge_hit` differential cells, and the th8v coverage-predicate vector + reworked th8 census rows +
re-anchored th8m mutation rows. Run, record RED, commit.

**Phase 3 — the extension.** `_affected_glob_split` gains the `root` class (+ `root-tail-slash`
why); each site gains its root arm (mint: no-probe `^glob:$_g`; hit: dir-less `[[ == ]]` loop;
census: valid, no `-d` probe; covers(): dir-less non-dir `fnmatch`; GLOBENT: second arm
`glob:` + `/`-free-charset-with-`*`; `edge_hit`: same dir-less rule); `_th8_eval` becomes the
uncovered-member census against the four corpus arrays via a new `_th8_corpus_covered <array>
<member>` predicate (member covered iff literal member, metachar-free `glob:` literal via mint
parity, or a well-formed root-anchored member matching it — split through the shared helper);
`_th6_root_covered` is untouched (root-anchored members are not `<root>` claims and decline
correctly). `MIN_CASES` bumps in all three batteries + count-literal sweep.

**Phase 4 — records.** ADR-242 `## Amendment — 2026-10-23 (#10198)` decision 28; lib header
doc-block update (top-of-file only, S4-separated); stale comment block updates (th6 comment at
:3378-3379, the five-site doctrine blocks ×3, `edge_hit` docstring, th8 row comment + message).

## Technical Considerations

- **RED-first ordering**: Phase 2 rows observed RED before Phase 3 lands; the PR body records it.
- **Bash 3.2**: helper uses `case`/`[[ ]]`/parameter expansion only; outputs via globals (the `_NP`
  idiom), never stdout.
- **The `declare -F` fold**: `_AFF_LIB_OK` gates on `ALWAYS_ON_SUITES` AND `_affected_glob_split` —
  a missing helper yields `AFFECTED_FALLBACK reason=index-missing` → selects everything, never a
  crash. CTO ruling additionally REQUIRES a fail-wide in-arm guard at the top of the hit arm's
  glob branch — `declare -F _affected_glob_split >/dev/null || return 0` — because
  `_diff_touches` over the relevance arrays calls `_diff_edge_hit` OUTSIDE the `_AFF_LIB_OK` gate
  (test-all.sh:2669), so a hand-placed `^glob:` relevance entry would otherwise rc-127 into a
  silent narrow under `set -euo pipefail`.
- **Content-minted tokens reclassify**: a `glob:`-spelled token in scanned file content that is
  `/`-free-headed now mints a REAL root edge instead of always-match — narrower and honest; live
  trees can't carry malformed members anyway (census REDs them).
- **`_th_fn_mut` anchors**: new predicates' mutation rows rewrite exact single-line anchors with
  exactly-once asserts — anchors must be chosen so the Phase-3 line exists once.
- **Count literals**: `MIN_CASES` (`test-all-affected`:228, `test-affected-derive`:116,
  `test-affected-kb-consumers`:30) plus `selected=N of=M`-class pins move — sweep before running.
- **Sandbox keep-list**: new asserted labels join `build_sandbox`'s trim keep-list (th7 binds it);
  the corpus trio is already listed.
- **Never edit battery files while a run reads them** (bash lazy-reads by byte offset).
- **NFR impacts**: none — repo-internal test machinery; no production/runtime surface.

## User-Brand Impact

- **If this lands broken, the user experiences:** a coverage edge shape that reads green while a
  dir-less corpus file selects nothing — or a root-anchored edge that matches MORE than dir-less
  (the `/`-crossing star) and silently widens every affected selection back toward the full
  battery; for the legal-corpus gates this machinery guards (`lint-legal-*`,
  `probe-legal-corpus-truth`), silent under-coverage is the class where a register diff ships
  without its required gate.
- **If this leaks, the user's [data / workflow / money] is exposed via:** workflow only — the
  affected selector is a local/CI acceleration mechanism; the full battery remains the merge
  backstop. No data or money surface.
- **Brand-survival threshold:** `single-user incident` (carried forward from the #10117 brainstorm)
- **Threshold decision (challengeable):** the machinery guards legal-corpus gates; a
  silently-narrowing or silently-widening coverage edge is a single-incident-class failure even
  though no product surface is touched.

## Observability

```yaml
liveness_signal:
  what: "the root-anchored grammar's six-site parity and the th8 dir-less coverage census — the new battery rows ARE the probes"
  cadence: "every --affected local run + every CI/main-push run of scripts/test-all-affected.test.sh, scripts/test-affected-derive.test.sh, scripts/lint-orphan-test-suites.test.sh and scripts/test-affected-kb-consumers.test.sh"
  alert_target: "red suite in CI / local gate output"
  configured_in: "scripts/test-all-affected.test.sh (th8/th8v/mint-hit rows); scripts/test-affected-derive.test.sh (Rg); scripts/lint-orphan-test-suites.test.sh (M); scripts/test-affected-kb-consumers.test.sh (k)"
error_reporting:
  destination: "suite stdout in the test-all run log (local and CI)"
  fail_loud: "[FAIL] <row>: … naming the declined member or the uncovered dir-less file"
failure_modes:
  - mode: "a dir-less corpus file lands with no covering edge"
    detection: "reworked th8 census REDs on the first battery run carrying it (producer-liveness floor keeps a dead ls-files RED, not green)"
    alert_route: "red scripts/test-all-affected suite"
  - mode: "a root-anchored pattern matches dir-bearing lines (the *-crosses-/ regression)"
    detection: "the a/x.test.sh decline probe + covers() k5 dir-bearing cells + edge_hit differential"
    alert_route: "red affected batteries"
  - mode: "the helper is missing while the arrays load"
    detection: "_AFF_LIB_OK stays 0 → AFFECTED_FALLBACK reason=index-missing selects all"
    alert_route: "loud fallback receipt; never a rc-127 mid-run abort"
logs:
  where: "suite stdout in CI run log; --print-selection AFFECTED_CLASS receipts"
  retention: "CI log retention"
discoverability_test:
  command: grep -c '^_affected_glob_split' scripts/lib/affected-glob.sh
  expected_output: "1"
```

## Architecture Decision (ADR/C4)

**ADR:** `ADR-242` amendment — **decision 28**, `## Amendment — 2026-10-23 (#10198)`: "the `glob:`
grammar gains a root-anchored form — a leading metachar-free head that is `/`-free (the empty head
included) anchors the whole pattern at the repository root and matches only dir-less diff lines —
superseding decision 27's unrepresentable posture. The extension landed ahead of decision 27's
stated trigger (operator pull, not a live member: the dir-less corpus count is still zero at
amendment time). Detection survives as the th8 coverage census. `_affected_glob_split` in
`scripts/lib/affected-glob.sh` is now the single bash classifier the mint/hit/census sites share;
the `covers()` oracle and `ci-pr-affected-replay.py`'s `edge_hit` remain Python mirrors, and
`GLOBENT` remains a deliberate superset that also admits the root form. The reclassification is
one-way safe: `/`-free heads were census-RED malformed yesterday, so no live array carries one.
Note for readers of `audit-suite-reads.sh`: unchanged — `^glob:` edges still report covered reads as
uncovered (over-report), now including root-anchored members." Plus an `amended_by:` frontmatter
entry and a superseded-by note appended inside decision 27's paragraph per the file's amendment
convention. **Ordinal verified:** 27 is the last decision; 28 is next. Intra-file ordinals are not
covered by `check-adr-ordinals.sh` (FILENAME ordinals only) — hand-verify now and re-verify at merge.

**C4 views:** none. Checked all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`) in the #10117 plan
— unchanged since: (a) external human actors — none introduced; (b) external systems/vendors — none;
(c) containers/data-stores — none touched (edited files are repo-root test machinery + one new lib,
below component granularity); (d) actor↔surface relationships — unchanged. The `--affected` selector
and its oracles are not C4 elements.

## Guard Contract

### Guard 1 — shared shape classifier parity (`_affected_glob_split` + mirrors)

**Property.** Every `glob:` payload classifies identically at every site: a `/`-free-headed
well-formed member is a real root edge that selects only dir-less lines; every malformed shape
degrades wider (mint verbatim always-match, hit match, oracle covers) or REDs statically (census)
or stays semantic (GLOBENT).

**Assembly.** One bash chokepoint: `_affected_glob_split` (`scripts/lib/affected-glob.sh`), called
by the mint arm, the hit arm, the census arm, and `materialise()`. Two Python mirrors
(`covers()`; `ci-pr-affected-replay.py edge_hit`) and the awk `GLOBENT` superset classify the same
input set — they cannot share the bash helper, so the parity is asserted by batteries (Rg/k5/
differential/rc-fixtures), not by construction; the census's `_AGS_WHY`-to-message map is the
single reason-vocabulary.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Delete the root arm's dir-less conjunct in the hit arm (`!= */*` dropped) — `a/x.test.sh` selects the carriers | RED — the decline probe flips |
| 2 | `_affected_glob_split` reports `literal` for every input | RED — mint/hit/census rows all fail; an always-literal classifier is the vacuous-dispatch shape (own dispatch) |
| 3 | A SECOND root member after a compliant first in a declared array — `glob:*.test.sh` then `glob:x*/y` — the census must still RED the bad second member | RED — walk reaches it (M25 idiom) |
| 4 | Harness row: mutate a decline fixture to an actually-covering one (`glob:*.test.sh` where `glob:x*/y` was scripted) | RED — guards a vacuous harness arm |
| 5 | Must-PASS non-canonical input: `glob:**.test.sh` and `glob:x*.sh` (`**` tail, non-empty `/`-free head — both legal spellings) | PASS |
| 6 | Mirror drift: `edge_hit` keeps `not head.endswith("/")` while the helper admits root | RED — the bash-vs-python differential row |

**Anchor.** `_AGS_*` outputs are data in one commit; the classifier, the site rewires and every
battery fixture land together — weakening the classifier without the fixtures goes red. The
`-d` probe and `git ls-files` derivations are outside the diff.

### Guard 2 — dir-less narrowing (the feature itself)

**Property.** A minted `^glob:` root edge matches a diff line iff the line is dir-less AND
`[[ == ]]`-matches the whole pattern — never a line under a directory.

**Assembly.** `_diff_edge_hit`'s root arm is the only chokepoint a diff line flows through for
root edges; minted edges reach it only via `_affected_add_edge` (one mint site); the TAB-split
rename-source blob is upstream (`_DEH_N`).

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Drop the `!= */*` conjunct | RED — `a/x.test.sh` selects (the crossing-star hole) |
| 2 | Revert to head-not-`/` always-match (pre-extension shape) | RED — an `x.md` non-corpus dir-less line also selects |
| 3 | Mutate the match to line-suffix (`== *$_g`-shaped) | RED — `x.test.sh.bak`-class lines select |
| 4 | Harness row: two diff lines `x.test.sh` + `a/x.test.sh` in one probe, assert select-and-decline on the SAME edge | RED if either arm binds nothing |
| 5 | Must-PASS non-canonical input: dir-less `x.test.sh` via `glob:**.test.sh` (the `**` spelling) | PASS |

**Anchor.** `SANDBOX_DIFF_NAMES` feeds the real `_diff_names` blob through the injected seam; the
edge comes from the sandbox's real lib copy mutated in-fixture — the assertion reads the shipped
arms, not a reimplementation.

### Guard 3 — th8 dir-less coverage census

**Property.** Every dir-less corpus member (`_th_root_corpus` complement of `git ls-files`) is
covered by each corpus suite's declared set — literal member or well-formed root-anchored glob
matching it — or the row REDs naming member and suite.

**Assembly.** `_th_ls_files()` producer (TESTROOT-confined `_TH_REPO`), the `_th_root_corpus`
disjoint-ext complement, `_th8_corpus_covered` over the four corpus arrays
(`AFFECTED_SCRIPTS_GUARD_VACUITY_FLOOR_PATHS`, `AFFECTED_SCRIPTS_LINT_ORPHAN_TEST_SUITES_PATHS`,
`AFFECTED_SCRIPTS_LIB_REPO_WRITE_BOUNDARY_TEST_SH_PATHS`,
`AFFECTED_TESTS_SCRIPTS_TRIO_BASELINE_CENSUS_PATHS`), evaluated inside the th6 subshell that already
sources the lib.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | `_TH_REPO` fixture repo with a dir-less `x.test.sh` and NO covering member | RED — the whole point of the row (precondition holds, property fails) |
| 2 | Empty fixture listing | RED — producer-liveness floor (EMPTY-ROOT-DERIVATION); own-dispatch |
| 3 | Fixture with `x.test.sh` + `y.sh` uncovered | RED — both flag; no stop-at-first |
| 4 | Predicate mutant: `_th8_corpus_covered` accepts only the literal channel (glob arm deadened) | RED — a `glob:*.test.sh`-carrying fixture array no longer certifies |
| 5 | Harness row: deaden one extension arm of `_th_root_corpus` (m4/m8 idiom) | RED — `x.test.sh` goes unflagged while `y.sh` flags |
| 6 | Must-PASS non-canonical input: fixture `x.md` (dir-less, non-corpus) | PASS — corpus-only detection |

**Anchor.** The complement derives live from `git ls-files`; the coverage arrays are the real lib —
weakening the predicate without the fixture arrays goes red via the th8v vector.

## Implementation Phases

### Phase 1 — helper extraction, doctrine-neutral

1. `scripts/lib/affected-glob.sh`: `_affected_glob_split` (literal|dir|malformed classes + why map).
2. Rewire mint arm, hit arm, census arm, `materialise()` `_mp` site to call it; `_AGS_WHY`-to-message
   map in the census keeps every existing reason string.
3. Plumbing: `test-all.sh` glob-lib source + `_AFF_LIB_OK` `declare -F` fold; lint-orphan fail-closed
   source; `build_sandbox` + `build_pristine` `cp` lines; `_edge_run`/`derive_run` lib source;
   `extract_oracle`/`edge-run.sh` in `plugins/soleur/test/ci-pr-affected-replay.test.sh` sources
   the lib in its eval (rc-127 on every `^glob:` row otherwise — CTO ruling).
4. Full green on all four batteries — the refactor proves itself.

### Phase 2 — RED-first rows

1. Mint rows (`_edge_run` + derive Rg): `glob:*.test.sh`, `glob:**.test.sh`, `glob:x*.sh` accept as
   `^glob:<pattern>`; `glob:x*/y`, `glob:*/x` verbatim malformed; Rg3 loses `glob:*.sh` to a new
   well-formed row.
2. Hit rows (sandbox lib mutation `glob:knowledge-base/**.test.sh`→`glob:*.test.sh` idiom):
   `x.test.sh` selects carriers; `a/x.test.sh`, `x.md` decline; `**` spelling parity.
3. Census M-rows: root accept; `glob:x*/y` root-tail-slash RED; M22 fixture `a*/b`→`a/b*c`.
4. covers() k5 cells; edge_hit differential cells; GLOBENT admit/semantic fixtures; th8v vector +
   reworked th8 + th8m anchors.
5. Run; record RED; bump `MIN_CASES` and count literals.

### Phase 3 — the extension

1. Helper `root` class + `root-tail-slash` why; all six site arms per Proposed Solution.
2. th8 census rework (`_th8_eval` + `_th8_corpus_covered`); comment/message updates.
3. All four batteries green; replay differential green.

### Phase 4 — records

1. ADR-242 amendment (decision 28) + `amended_by:` + decision-27 superseded-by note; lib header
   doc-block (:35-46) update; stale comment sweep (the `git grep` for `does not end in /`,
   `no head to mint`, `deferred to #10198`).
2. `bash scripts/check-adr-ordinals.sh`; re-grep the feature's artifacts for the ordinal.
3. Final: all batteries + `bash scripts/lint-orphan-test-suites.sh` + `--affected` sanity.

## Files to Edit

- `scripts/test-all.sh` — glob-lib source + `_AFF_LIB_OK` fold; mint arm root case; hit arm root
  arm; `GLOBENT` second arm; three doctrine comment blocks (:2200-2215, :2407-2409, :2849-2878)
- `scripts/lib/affected-glob.sh` — **also Files to Create** (new; listed here for the phase-1
  rewire tracking)
- `scripts/lint-orphan-test-suites.sh` — fail-closed glob-lib source; census arm → helper +
  root class + `root-tail-slash` reason string
- `scripts/lint-orphan-test-suites.test.sh` — `build_pristine` `cp` line; `materialise()` `_mp` →
  helper; M22 fixture re-anchor; new M-rows (root accept, root-tail-slash decline)
- `scripts/test-affected-kb-consumers.test.sh` — `covers()` root arm + malformed-check update;
  k5 vector (foo*.sh flip + ~10 new cells); k-family mutation rows; `MIN_CASES`
- `scripts/test-all-affected.test.sh` — `build_sandbox` `cp`; `_edge_run` lib source; new
  mint/hit/registration rows; th8 rework (`_th8_eval`, `_th8_corpus_covered`, th8v vector,
  th8m anchors); `MIN_CASES`
- `scripts/test-affected-derive.test.sh` — `derive_run` lib source; Rg3 vector re-anchor (`glob:*.sh`
  out); new Rg root rows; `MIN_CASES`
- `scripts/ci-pr-affected-replay.py` — `edge_hit` root arm + mid-slash/root-tail malformed rules +
  docstring
- `plugins/soleur/test/ci-pr-affected-replay.test.sh` — `extract_oracle`/`edge-run.sh` eval sources
  `affected-glob.sh`; `er` row `mal-head-not-slash-empty` (:1868) re-anchored (its `glob:*.sh` over
  `lib/z.txt` flips to non-match) + new root-arm rows (`x.sh`→1, `a/x.sh`→0, dir-bearing `.sh`→0);
  `row_edge_*` `mal-` name-prefix grouping and `EDGE_ROWS -ge 50` count literal reconciled (CTO
  ruling — the seventh consumer the site enumeration missed)
- `scripts/lib/test-affected-paths.sh` — header doc block (:35-46) ONLY: name the root form + helper
  (comment region; zero array-region touch — S4-separated)
- `knowledge-base/engineering/architecture/decisions/ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md`
  — `amended_by:` + `## Amendment — 2026-10-23 (#10198)` decision 28

## Files to Create

- `scripts/lib/affected-glob.sh` — `_affected_glob_split`, the single bash shape classifier
  (shebang-less lib idiom; sourced, never executed)

## Open Code-Review Overlap

- **#8800** (`test fixture: census sandbox shares inodes/symlinks with live repo`) touches
  `scripts/test-all-affected.test.sh` and `scripts/lib/test-affected-paths.sh` — **Acknowledge.**
  Fixture-isolation concern; this plan's new fixture rows add sandbox fixtures but do not worsen the
  write-through hazard (reads only). Scope-out stays open.
- **#8659** (EXIT-trap replacement leaks incident sandbox) and **#7942** (unregistered
  `*.mutation.sh` batteries) name `scripts/test-all.sh` — **Acknowledge.** Adjacent test-hygiene
  concerns; the glob-arm edits are localized with no interaction.
- **#10945** (S4 drain, open PR, not a code-review issue) mass-edits
  `scripts/lib/test-affected-paths.sh` arrays — this plan's only touch there is the top-of-file
  doc comment; the helper lives in a NEW file. Merge-order note in Dependencies & Risks.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Implement a root-anchored form for the `glob:<literal-head>/<glob-tail>` declared-edge grammar (ADR-242 decision 22) so a dir-less `x.test.sh`/`x.sh` at repo root becomes expressible as a coverage edge" [issue #10198] | Phase 3 (helper `root` class + six site arms) + Phase 2 RED rows + Guard 2 | mapped |
| 2 | "The extension touches the 'ONE doctrine, FIVE sites' malformed-shape invariant: mint arm `_affected_add_edge` and hit arm `_diff_edge_hit` in scripts/test-all.sh, the census arm in scripts/lint-orphan-test-suites.sh, the covers() oracle in scripts/test-affected-kb-consumers.test.sh, and the GLOBENT registration-only classifier" [issue #10198] | the five named sites + the discovered sixth (`edge_hit`) + test-side copies, all in Files to Edit | mapped |
| 3 | "plus an ADR-242 amendment and mutation rows" [issue #10198] | Phase 4 (decision 28) + th8m/th6m/k6-style mutation rows in Phase 2 | mapped |
| 4 | "also pull in the `_affected_glob_split` helper-extraction advisory deferred 'to next grammar touch' — this issue is that touch" [issue #10198] | Phase 1 (`scripts/lib/affected-glob.sh` + four-site rewire) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `scripts/lib/affected-glob.sh` + mint/hit/census/materialise rewire | "pull in the `_affected_glob_split` helper-extraction advisory" | asked |
| Root-anchored grammar extension across six sites | "root-anchored form … becomes expressible as a coverage edge" + "ONE doctrine, FIVE sites" | asked |
| ADR-242 amendment + mutation rows | "plus an ADR-242 amendment and mutation rows" | asked |
| `edge_hit` (ci-pr-affected-replay.py) + `test-affected-derive.test.sh` Rg rows | — | inferred — justification: the issue's "FIVE sites" enumeration missed the sixth classifier and the second mint battery; the malformed-shape invariant they mirror makes the plan's parity claim false without them (census-over-enumeration) |
| th8 existence→coverage-census rework (`_th8_eval`, `_th8_corpus_covered`, th8v) | — | inferred — justification: decision 27 says "the row's expectation revisits what the new grammar expresses"; leaving existence-RED after the remedy lands would keep the row permanently red-on-first-member with no exit |
| `_AFF_LIB_OK` `declare -F` fold + sandbox/pristine `cp` lines + `_edge_run`/`derive_run` lib source | — | inferred — justification: a lib-living helper is invisible to extracted-source harnesses and missing-file degrades; without the plumbing the rewire aborts at rc 127 or the sandbox runner classifies nothing |
| `MIN_CASES`/count-literal bumps | — | inferred — justification: new battery rows move the family's own floors; without the bump the suite's conservation accounting fails |
| lib header doc-block update (:35-46) | — | inferred — justification: the header teaches the `glob:` grammar; shipping a grammar extension while the doc still says heads must end in `/` re-introduces the stale-doctrine class |

### Split Assessment

- Subsystems touched: 2 — `scripts`, `knowledge-base`
- Planned files: 11 (10 edit + 1 create) | Estimated changed lines: ~450 (net; large comment blocks
  inflate the count — code is ~180)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — one grammar change whose sites must move in lockstep; splitting mint
  from census ships a tree where the two classifiers disagree.

## Acceptance Criteria

- [ ] `scripts/lib/affected-glob.sh` defines `_affected_glob_split` and the mint arm, hit arm,
      census arm and `materialise()` all classify through it — `grep -rn '%%\[\*?\[\]' scripts/`
      returns zero hits outside comments
- [ ] `glob:*.test.sh`, `glob:**.test.sh` and `glob:x*.sh` mint `^glob:<pattern>`; `glob:x*/y` and
      `glob:*/x` mint `^glob:<verbatim>` always-match; the Rg3 and t-family vectors updated
- [ ] A `^glob:*.test.sh` edge selects on `x.test.sh` and does NOT select on `a/x.test.sh` or
      `x.md` (dir-less narrowing proven by the sandbox probes); `**` tail parity holds
- [ ] The census accepts `glob:*.test.sh`/`glob:x*.sh`, REDs `glob:x*/y` with the
      `root-tail-slash` reason, and keeps every prior malformed class (M22 re-anchored to `a/b*c`)
- [ ] `covers()` reports a dir-less `p` covered iff it fnmatches a root-anchored `g` and is not a
      dir; `^glob:foo*.sh` flips to a real narrow edge in the k5 vector
- [ ] `edge_hit()` mirrors the same verdicts and the bash-vs-python differential pins them
- [ ] `GLOBENT` admits a root-anchored member (registration-only) and leaves `glob:x*/y` semantic
- [ ] The reworked th8 row asserts per-member coverage: a dir-less corpus member with no covering
      literal or root-anchored glob REDs naming member + suite; producer floor and `_TH_REPO`
      confinement intact; a covered member (fixture array) clears
- [ ] `test-all.sh` degrades to select-all (`AFFECTED_FALLBACK reason=index-missing`) when the glob
      lib is absent — no rc-127 abort — verified by a no-lib sandbox arm
- [ ] ADR-242 carries `## Amendment — 2026-10-23 (#10198)` with decision 28, an `amended_by:` entry,
      and a superseded-by note inside decision 27
- [ ] All four batteries green (`test-all-affected`, `test-affected-derive`,
      `lint-orphan-test-suites`, `test-affected-kb-consumers`) + `lint-orphan-test-suites.sh` green;
      `MIN_CASES` and count literals reconciled
- [ ] All new rows observed RED before their predicate/classifier edits (RED-first, recorded in
      the PR body)

<!-- founder-stated check: see plan-founder-check.md — headless run, no interactive gate -->

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** carried forward from the #10117 brainstorm — CTO ruled the mechanism class (grammar
extension is the trigger-activated remedy; the same ruling deferred `_affected_glob_split` to this
touch). CPO/CLO assessed near-zero product/legal surface for the parent work; nothing here widens
it — repo-internal test machinery, not shipped in the plugin payload.

**Brainstorm-recommended specialists:** none recommended by name in the domain assessments.

## Test Scenarios

- Given `glob:*.test.sh` declared, when `_affected_add_edge` mints, then `^glob:*.test.sh` is the
  edge; when `_diff_edge_hit` evaluates `x.test.sh` then match, `a/x.test.sh` then no match,
  `x.md` then no match (unit — t/th-family)
- Given `glob:x*/y` or `glob:*/x` declared, when any site classifies, then malformed: mint verbatim
  always-match, hit return 0, census `root-tail-slash` RED (unit)
- Given a sandbox lib carrying `glob:*.test.sh`, when `SANDBOX_DIFF_NAMES` is a dir-less corpus
  file, then the carriers select; a dir-bearing same-extension file declines (integration —
  run_arm)
- Given a fixture repo with a dir-less `x.test.sh` and no covering member, when the th8 census runs,
  then RED naming `x.test.sh` per suite; given a fixture array with `glob:*.test.sh`, then green
  (unit — th8v + fixture)
- Given `^glob:*.test.sh`, when `covers()`/`edge_hit` evaluate `x.test.sh` / `a/x.test.sh` /
  `docs` (dir ref) / `README.md`, then `1 0 0 0`-class verdicts identical in both mirrors (unit —
  k5 + differential)
- Given `glob:` members missing the glob lib, when the runner loads, then `index-missing`
  fallback selects all — never rc 127 (integration — no-lib arm)
- Given a registration diff adding `"glob:*.test.sh"`, when the classifier runs, then
  registration-only (admitted); `"glob:x*/y"` then semantic (integration — rc fixtures)

## Success Metrics

- A dir-less `*.test.sh`/`*.sh` declared via `glob:*.<ext>` selects exactly its carriers on a
  dir-less diff and declines on every dir-bearing diff
- One bash classifier: zero `%%[*?[]*` idioms outside `affected-glob.sh`
- th8 keeps its loud-on-first-member property, now exit-able via a root-anchored edge
- Four batteries green with `MIN_CASES` reconciled; ADR-242 decision 28 recorded

## Dependencies & Risks

- **S4 drain PR #10945** mass-edits `scripts/lib/test-affected-paths.sh` arrays — collision
  confined by design: this plan's only touch there is the top-of-file doc comment and the helper
  is a NEW file. Rebase onto origin/main immediately before the doc-comment commit if the drain
  lands first; the helper file has no merge surface.
- **Reclassification widening→narrow**: `glob:x*.sh` and `glob:*.sh` upgrade from always-match to
  real edges — safe because the census REDs those shapes today (no live array can hold one); the
  one channel that could carry them (hand-placed `^glob:` relevance entries) is asserted absent by
  a `git grep '\^glob:'` sweep over BOTH `scripts/lib/test-relevance-paths.sh` AND
  `scripts/lib/test-affected-paths.sh` in Phase 3, re-run in the SAME commit as the grammar flip
  (CTO ruling — closes the sibling-PR window).
- **The `*`-crosses-`/` trap** is the feature's central defect class — the dir-less conjunct in the
  hit arm AND both Python mirrors; one site forgetting it is the widening regression Guard 2 exists
  to catch.
- **Real-runner flake** — prefer grep/static probes in AC commands; real-runner arms can fail
  empty under sibling-gate contention (re-run to isolate).

## References & Research

- Issue: #10198 (this work); deferred from #10117 during brainstorm 2026-10-13
- Prior plan (direct precedent, carries the deferred scope):
  `knowledge-base/project/plans/archive/20261014-231240-2026-10-13-fix-edge-declaration-coverage-residuals-plan.md`
- Brainstorm (deferred the extension + the helper): `knowledge-base/project/brainstorms/archive/20261014-231240-2026-10-13-edge-coverage-residuals-brainstorm.md`
- ADR-242 (amendment target; decisions 22 grammar, 27 detect-not-extend; 28 next):
  `knowledge-base/engineering/architecture/decisions/ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md`
- `_affected_glob_split` advisory: `knowledge-base/project/learnings/workflow-issues/2026-10-10-a-declared-edge-must-say-what-the-walker-reads-and-a-malformed-one-must-fail-wide.md`
  (deferred advisories) + `specs/archive/20261013-062704-feat-one-shot-9813-extension-aware-edges/session-state.md`
- Sibling constraint: PR #10945 (S4 PR4 code-edge drain, open)
- Key code: `scripts/test-all.sh`:2187-2240 (hit), :2411 (GLOBENT), :2844-2914 (mint);
  `scripts/lint-orphan-test-suites.sh`:1113-1172 (census);
  `scripts/test-affected-kb-consumers.test.sh`:279-321 (covers), :730-773 (k5);
  `scripts/test-all-affected.test.sh`:3117-3743 (th6v/th8 machinery), :2582-2583 (`_edge_run`);
  `scripts/ci-pr-affected-replay.py`:967-1019 (`edge_hit`);
  `scripts/test-affected-derive.test.sh`:71-78 (`derive_run`), :1101-1170 (Rg)

## Sharp Edges

- `[[ == ]]` `*` crosses `/` in BOTH bash and `fnmatch` — the root arm's `!= */*` conjunct is
  load-bearing at three sites (hit, covers(), edge_hit); omitting it anywhere re-widens the edge
  to every `.sh` in the tree.
- `${_g#"$_AGS_HEAD"}` tail extraction — quote the pattern so a head can't glob inside `#`; the
  literal-compare quoting rule from #10117 carries over.
- The k5 `^glob:foo*.sh` cell FLIPS 1→0 — the vector position and its comment ("non-/ head →
  always-cover") both change; extend rather than renumber where possible.
- Rg3's `glob:*.sh` moves OUT of the malformed vector — do not leave it: under the extension it
  mints `^glob:*.sh`, and a stale fixture asserting `^glob:glob:*.sh` fails.
- The empty-head pre-check degenerates (`*NL*` always true) — keep the `_AGS_HEAD`-nonempty guard so
  the pre-check stays a real cheap decline for non-empty root heads.
- `_edge_run`/`derive_run` eval extracted source — the lib is OUTSIDE the extraction window; source
  `affected-glob.sh` inside the eval or every row reads rc 127.
- `materialise()` already no-ops `/`-free heads correctly — the helper call must preserve that
  (root class → materialise nothing).
- `_AFF_LIB_OK` fold keeps the degrade honest — a missing helper must read `index-missing`, never
  crash mid-selection.
- GLOBENT is a superset: admit `/`-free-with-`*` root members; keep `glob:x*/y` semantic (it
  contains `/` mid-pattern and matches neither arm).
- A plan whose `## User-Brand Impact` section omits the threshold fails deepen-plan Phase 4.6.
- Never edit `test-all-affected.test.sh`/`test-all.sh`/`test-affected-derive.test.sh` while a
  battery run reads them.
- After the ADR amendment, verify `scripts/check-adr-ordinals.sh` and re-grep the feature's own
  artifact set for decision numbers.

