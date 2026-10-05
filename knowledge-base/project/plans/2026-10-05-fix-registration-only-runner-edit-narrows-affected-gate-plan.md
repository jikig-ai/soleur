---
title: "fix(test-gate): a registration-only runner edit takes the bounded selection, not the full battery"
type: fix
date: 2026-10-05
slug: fix-registration-only-runner-edit-narrows-affected-gate
branch: feat-one-shot-registration-only-runner-edit
issue: 9552
priority: p2-medium
domain: engineering
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

# fix(test-gate): a registration-only runner edit takes the bounded selection, not the full battery

Draft PR: #9552. No tracking issue exists for this topic (collision re-checked 2026-10-05: no open issue or PR matches `runner-changed` x registration). Spec lacks a `lane:` (no brainstorm ran on the one-shot path), so `lane: cross-domain` is the fail-closed default; the only relevant domain is Engineering.

## Overview

Any diff touching `scripts/test-all.sh` or `scripts/lib/test-affected-paths.sh` fires the `runner-changed` fallback in the affected pre-pass and runs the whole battery. Registering a new suite is itself such an edit: a `run_suite` line in the runner, plus an `AFFECTED_<LABEL>_PATHS` array or an `ALWAYS_ON_SUITES` entry in the index whenever the orphan census demands a classification (measured below: it does, for any suite whose SUT derivation reaches nothing). So every PR that adds a suite pays the full battery, and the run looks like a hang (a recent suite-adding PR was stopped after 2h13m of contended local run).

The fallback exists so an edit that NARROWS a selection cannot blind itself. A registration cannot narrow an existing suite's selection if, and only if, the edit is provably nothing but new-suite registration. This plan adds a closed-grammar classifier for the runner-file content diff, inline in `scripts/test-all.sh`, shipped in slices: the banner and `--help` first (Phase 1), the runner-only grammar next (Phase 2a), index declarations last and droppable (Phase 2b). A registration-only diff takes the bounded-selection walk that ADR-242 decision 10 already accepts under `--affected-scope=staged`; anything else, including any single line outside the grammar mixed into an otherwise clean diff, keeps `runner-changed` and the full battery. It also rewrites the degraded banner and the `--help` text so the full run states its cost, its cause, and the escape.

Recommended mechanism: **(a) parse the runner diff against a closed registration grammar, fail closed**. (b) and (c) are cut as the mechanism, see the Cut List; (c)'s banner half is kept because the fail-closed arm still needs it.

## Research Insights

### Premise Validation (Phase 0.6)

- Issue 9173 (closed by PR 9197, merged 2026-09-29): prior art, cited as prose. It bounded the PRE-COMMIT hook by swapping the diff source to the index (`--affected-scope=staged`); branch scope kept the full fallback byte-identical. Stale-premise check: still true on `origin/main` (`scripts/test-all.sh` elif arm `[[ "${_AFF_SCOPE:-branch}" != "staged" ]] && (( _aff_runner_in_diff == 1 ))` is present).
- Issue 9441 (open): declared edge to a deleted subject; prior art only, not this plan's target. Constraint carried: ADR-242 decision 12 (a declared edge to a deleted path is dropped at mint) is untouched.
- Issue 9307 (open epic): the affected-only gate. Its PR-1 residuals list "narrow the nine heavy always-on batteries" and "make the pre-pass cheap"; neither is this plan. Measured here: the `--print-selection` pre-pass costs about 70 to 80 s after #9375/#9422 (the 11-minute figure in the issue body is stale).
- ADR corpus (Phase 0.6 item 4, the load-bearing finding): ADR-242 `## Amendment - 2026-09-29`, "Alternatives added", REJECTED exactly this mechanism as "option d": *`runner-changed` distinguishes selection-logic vs registration-data edits - a pathname trigger cannot see edit kind without fragile diff-content inspection, and the dangerous narrowing edit is data-shaped, already covered by self-inclusion edges, the always-on census, and unclassified-selects-anyway.* This plan therefore does not propose an unconsidered idea; it proposes to reverse a recorded rejection, so the ADR amendment is a deliverable (see `## Architecture Decision (ADR/C4)`). Why the two reasons no longer hold: (1) the rejection assumed inspection of an unbounded text; a CLOSED grammar over added lines only, with zero tolerance for removed lines and a per-line allowlist, is not fragile in the sense that matters, because every miss falls toward the full battery; (2) "the dangerous narrowing edit is data-shaped" is true and is exactly what the label-binding rule answers: the only data edit that can narrow is a new `AFFECTED_*_PATHS` array on an EXISTING unclassified label (it turns "always runs" into "runs only when its edge is touched"), and the grammar admits arrays only for labels that the same diff registers. The residual the ADR accepted under staged scope (a selector-corrupting edit narrows the selector it runs under, bounded by the always-on runner-SUT battery plus CI's full battery on the PR head) is the same residual accepted here.
- Capability claims verified, not assumed (`hr-verify-repo-capability-claim-before-assert`): (i) TSV rows are NOT runner edits and are NOT required: `scripts/suite-shard-legs*.tsv` and `scripts/suite-durations*.tsv` are outside the two-file trigger and a missing row degrades to positional assignment; the brief's "TSV row" is therefore a scratch-measurement convenience, not part of the problem. (ii) `TEST_GROUP=affected` has NO `runner-changed` arm: it is the heuristic selector (`_suite_affected`), whose content-reference signal selects every suite whose text mentions `test-all.sh` (153 of 2126 test files mention it). It "degrades" by over-selection, not by a full fallback, and it cannot be combined with `--affected` (rc 2). (iii) The orphan census DOES demand classification for a new suite (measured below), so the index edit is routine, not exotic. (iv) The declared-edge mechanism UNIONS declared and derived edges (`_affected_classify`, "Union, not shadow"), so extending an array can only widen; a NEW array for a previously unclassified label narrows.

### Measurements (`--print-selection` only; scratch edit reverted; `git status` clean)

Scratch edit: one `run_suite "scripts/zz-scratch-registration" bash scripts/zz-scratch-registration.test.sh` line after `scripts/battery-ref-guard`, one untracked trivial suite file, one row in each of `suite-durations.tsv` and `suite-shard-legs.tsv`. Durations are the sum of `scripts/suite-durations.tsv` and `scripts/suite-durations-heavy.tsv` over the selected labels (manifest weights, serial, uncontended).

| Scenario | Command | Outcome | Wall |
|---|---|---|---|
| Baseline, KB-only diff | `bash scripts/test-all.sh --print-selection` | `AFFECTED_SUMMARY selected=146 of=559 always_on=146 edge=0 fallback=none` | 71 s |
| Registration edit, real branch diff | same | `AFFECTED_FALLBACK reason=runner-changed`; `AFFECTED_SUMMARY selected=all of=all always_on=all edge=all fallback=runner-changed`; banner `MODE=full (degraded: runner-changed) - selection declines disabled; relevance declines still apply.` | 1 s (the fallback skips the walk) |
| Same edit, bounded arm (`--affected-scope=staged --paths=<the four edited paths>`) | `bash scripts/test-all.sh --print-selection --affected-scope=staged --paths=scripts/test-all.sh,scripts/zz-scratch-registration.test.sh,scripts/suite-durations.tsv,scripts/suite-shard-legs.tsv` | `AFFECTED_RUNNER_IN_SCOPE reason=runner-changed`; `AFFECTED_SUMMARY selected=190 of=566 always_on=146 edge=43 fallback=none`; the new suite selected as `unclassified` | 79 s |
| Census on the scratch tree | `bash scripts/lint-orphan-test-suites.sh` | `ERROR: registration 'scripts/zz-scratch-registration' is UNCLASSIFIED ... Add it to ALWAYS_ON_SUITES, declare an AFFECTED_*_PATHS edge ...` (the edit to the index is demanded, not optional) | - |

Hit-rate measurement (the value-proposition check, Phase 0.6c; a 30-line script over `git log -p`, kept in the session scratchpad and re-runnable in `soleur:work`): of 226 non-merge commits since 2026-06-01 that touched either runner file, **152 (67%) fit the grammar INCLUDING the anchor rule and 139 (61.5%) of those add a registration**. Of the registration-only commits, 137 touch only the runner, 4 add an `AFFECTED_*_PATHS` block and 1 adds an index entry: the index half serves about 3.5% of the demand, which is why it is a separable slice (Phase 2b). 115 of the 137 runner-only commits add a comment or blank line beside the registration, so admitting comments (with the anchor) is what makes the hit rate real; excluding them leaves 22. Per-commit, not per-PR, so an indicator rather than a PR-level rate; it is nonetheless the evidence that the narrowed path is the common case for runner-touching work, which is what separates mechanism (a) from the cheaper-looking (c).

Cost model (manifest weights): full battery 566 registrations = 91.4 min (76.3 light + 15.1 heavy); bounded selection 190 = 58.6 min (146 always-on = 21.7 min; the 43 edge suites = 36.9 min); KB-only baseline 21.7 min. **The honest saving is 32.8 min (36%) at manifest weights, not "minutes".** The 43 edge suites are the runner-SUT mutation batteries plus suites that reach the runner only through the self-inclusion of every declared edge set; 13.6 min of them (`registry-gate-mutation-battery` 491 s, `cf-tunnel-liveness-gate-mutations` 162 s, `orphan-process-reaper-mutations` 113 s, `registry-delivery-change-mutation-battery` 49 s) are not runner-SUT. Dropping those needs a per-suite declaration and is deferred (Cut List). The local contended full run measured over 2h13m before being stopped; the manifest sum is the uncontended floor, and the ratio, not the absolute, is the claim.

### Property List (Phase 0.6b)

1. **P1.** A diff whose runner/index edits are registration-only (new `run_suite` lines for new labels plus the index declarations that bind those same labels) takes the bounded selection under branch scope: `AFFECTED_SUMMARY ... fallback=none`, the new suite selected, no full battery.
2. **P2.** Any other runner/index edit keeps `runner-changed` and the full battery, including a diff that mixes registration lines with ONE line outside the grammar anywhere in either file.
3. **P3.** A registration edit cannot narrow or alter any EXISTING suite: no removed line, no edited line, no array for an existing label, no closure-leaf / floor / selection-logic edit is admitted.
4. **P4.** When the battery runs in full because of a runner edit, the operator is told, before it starts: that the diff edits the runner, the first line the grammar refused, the expected duration, and the commands that preview or scope a registration-only edit; `--help` carries the same guidance, including that `TEST_GROUP=affected` is a distinct selector and not the escape.
5. **P5.** The classifier judges the same window the selection uses (merge-base to working tree) and degrades to full whenever it cannot decide (no merge-base, git error, empty content diff, `--paths` mode, `bash -n` failure).
6. **P6.** Classifier correctness is proven by a mutation battery in which every semantic row reddens and a non-canonical registration row still passes.
7. **P7.** The lesson "registering a suite is itself a runner edit" is captured as one learning (written during `soleur:work`).

### Cut List (Phase 0.6b)

| Mechanism | Property it would buy | Disposition |
|---|---|---|
| (b) Move registrations out of `test-all.sh` into a data file | P1 | CUT. About 560 registrations are interleaved with relevance-gated `if _diff_touches ... else skip_suite` blocks, per-group `want_*` wrappers and ordinal-indexed shard selection; migrating them is a large re-tiling with a regression surface far above the benefit. The data file would also become a third runner-critical path needing its own fallback and grammar (an append-only grammar over a data file is mechanism (a) relocated), and `CLOSURE_LEAF_FILES` is pinned equal to the two-file trigger by a derive row. The index half of a registration (arrays) is already data and is still a trigger today. |
| (c) Keep full, banner only | P4 only | CUT as the mechanism (does not deliver P1); the banner half is KEPT, rendered by the fail-closed arm. |
| Selection-equivalence oracle (run `--print-affected-set` or `--print-selection` on base and head runners, compare existing labels) | P2/P3 | CUT. It sees selection metadata only, not exit-handling, ceiling or classification-of-results edits; costs two walks (about 70-80 s each) plus a base-runner materialization; the grammar already proves "no existing line changed". |
| Third file for the classifier (`scripts/lib/runner-diff-class.sh`) | maintainability | CUT. An edit to it would not match the two-file trigger and would be unguarded; inline in `test-all.sh`, any edit to the classifier is itself a non-registration line and goes full. |
| Admit deleted/edited lines (label rename, argv edit) | P1 for rename PRs | CUT. A removed `run_suite` is a narrowing edit by definition (symmetry: add is registration, delete is semantic); renames are rare and may pay the full battery. |
| Admit relevance-gated multi-line registrations (`if _diff_touches ...; then run_suite ... else skip_suite ... fi`) | P1 for ~10 call sites | CUT. Not single-line; the grammar stays one shape. Takes today's fallback. |
| Admit appends to existing arrays other than `ALWAYS_ON_SUITES` (`AFFECTED_CONSUMED_EDGES`, `_CLOSURE_LEAF_RT_*`, `CLOSURE_LEAF_FILES`) | P1 | CUT. `CLOSURE_LEAF_FILES` additions narrow closures; the others need per-array reasoning for no measured demand. |
| Auto-discover root `scripts/*.test.sh` through `SUITE_GLOBS` (so most suite additions touch neither runner file; review suggestion) | P1 | CUT. 162 explicit root registrations exist (the orphan census s1 surface), so a glob either double-runs them or forces a mass conversion; the glob edit is itself a semantic runner edit, it changes what the battery contains (suites that were never run standalone), and it removes the deliberate "registration is a reviewed act" property the `2026-07-16` learning records. Re-evaluate only with a measured plan. |
| A new always-on battery file for the classifier rows | P6 | CUT (review). The rows live in `scripts/test-all-affected.test.sh`, already selected by every runner-touching diff (edge on the runner; ADR-262 withdrew it from always-on); a new file would add a registration, an always-on entry and a `+250`-line runner edit for no added reach. |
| A second record type `AFFECTED_RUNNER_CLASS` | P4 | CUT (review). `AFFECTED_RUNNER_IN_SCOPE reason=registration-only` carries the class on the bounded path and the banner carries the offender on the full path; a new parsed-by-prefix record is surface without a requirement. |
| Edits to `plugins/soleur/skills/{work,ship}/SKILL.md` | P4 | CUT (review). Their sentences ("a diff touching the runner or index itself degrades the run to the full battery") stay true for every non-registration edit. |
| A static banner clause instead of the manifest-weight `N` | P4 | KEPT as written: ask 5 names "about N min" explicitly; the clause states its provenance and degrades to "duration unknown". |
| Second-stage narrowing: drop the 13.6 min of runner-edge heavy batteries that are not runner-SUT from the registration-only selection | cost | DEFERRED (new selection concept: a declared runner-SUT set). Re-evaluate when registration-only runs are measured at the bounded-selection cost and 13.6 min dominates; file a deferral issue in Phase 0 of `soleur:work` after a collision re-check, milestone from `knowledge-base/product/roadmap.md`. |
| Extend to `TEST_GROUP=affected` | P1 | CUT. Distinct heuristic selector, no `runner-changed` arm; `--help` states this. |
| `SANDBOX_*`-style env seam shipped inline for the classifier's diff source | testability | CUT. #9197's security review: an env-readable substitution in production is the first seam that could narrow a real run's diff. The battery injects its seam at sandbox build time, never shipped (same discipline as `SANDBOX_STAGED_NAMES`). |

### Institutional learnings applied

- `2026-10-05-a-guard-built-from-spellings-needed-an-allowlist-and-the-affected-run-saw-two-ratchets-my-targeted-tests-could-not.md`: the affected run is the only instrument that exercises repo-global ratchets; targeted suite runs cannot stand in for it (drives the Test Strategy: run the always-on runner-SUT suites, not only the new suite).
- `2026-09-28-every-grammar-rule-my-lexer-skipped-was-a-bypass-and-my-oracle-explained-its-own-flips.md`: every syntax rule the classifier does not model is a bypass. The grammar therefore models NONE of bash's syntax: it admits a closed set of whole-line shapes and rejects everything else, with a charset that excludes `$ \` ( ) ; | & < > " ' \` and backslash inside the argv.
- `2026-06-14-fail-closed-gate-audit-every-input-branch-and-symmetric-guard.md`: audit every input branch (names-only seam, `--paths`, no merge-base, empty diff) and keep guards symmetric (add admitted, delete refused).
- `2026-05-09-pathspec-regex-translation-and-classifier-piggyback.md`: a classifier that downgrades selection is a security boundary; enumerate "worst-case piggyback" diffs (the matrix rows below).
- `2026-09-30-print-affected-set-prints-classes-not-selection-and-the-ask-was-half-shipped.md`: classification is not selection; the acceptance check is the printed `AFFECTED_SUMMARY`, not the class string.
- `2026-07-16-a-gate-that-proves-it-cannot-fail-open-shipped-its-own-proof-unwired.md`: `test-all.sh` hand-registers suites; the new battery MUST be registered (and, as a runner-SUT battery, always-on) or it runs in zero gates.
- No existing learning covers "registering a suite is itself a runner edit": one is a planned deliverable (Phase 4).

### Code-review overlap

Open `code-review` issues naming files this plan edits: #8659 (test suites replace test-helpers' composed EXIT trap; names `scripts/test-all.sh`) and #7942 (two mutation batteries named `*.mutation.sh` run in no gate; names `scripts/test-all.sh`) - ACKNOWLEDGE both: different concerns (trap composition; unregistered batteries), neither is closed by this change; the new battery is registered and always-on so it does not add to #7942's class. #8800 (census sandbox shares inodes/symlinks with the live repo; names `scripts/lib/test-affected-paths.sh` and `scripts/test-all-affected.test.sh`) - ACKNOWLEDGE with a constraint: the new fixtures copy files into a scratch git repo and never hardlink or symlink into the live tree (the write-through hazard #8800 describes).

## Design

### Where the decision lives

In the pre-pass, immediately AFTER the existing `_aff_runner_in_diff` membership block (which `plugins/soleur/test/fanout-suite-scope.test.sh` neuters by anchoring on that exact text; those lines are NOT edited) and BEFORE the `if/elif` ladder. The runner runs under `set -euo pipefail`, so the call is written to be failure-proof and every variable is initialised first:

```
_aff_runner_class=""
_aff_runner_first_offender=""
# Computed only when it can matter. _aff_fallback is assigned INSIDE the ladder, so it cannot be
# the guard here: spell out the three rungs that precede the runner arm.
if [[ "${_AFF_SCOPE:-branch}" != "staged" ]] && (( _aff_runner_in_diff == 1 )) \
   && [[ "${SOLEUR_TEST_FORCE_ALL:-}" != "1" ]] && (( _AFF_LIB_OK == 1 )) \
   && [[ "$_diff_detect_ok" == "1" && "$_diff_head_ok" == "1" ]] && (( _PRINT_PATHS_REQ == 0 )); then
  _aff_classify_runner_diff || _aff_runner_class=undecidable   # never lets a git/awk failure exit the runner
fi
```

`--paths` mode (no content to read) skips the call and keeps today's behaviour, so existing row q4 is unaffected. The `runner-changed` elif gains one conjunct (`&& [[ "$_aff_runner_class" != registration-only ]]`). Everything else in the ladder is untouched, and the else-branch that already carries the staged note is extended, not duplicated: `AFFECTED_RUNNER_IN_SCOPE\treason=runner-changed` stays for staged scope; branch scope with a registration-only class emits `AFFECTED_RUNNER_IN_SCOPE\treason=registration-only` (this one line is the observable; no second record type is added). The below-floor census refusal still precedes it, so a gutted index refuses before any narrowing (the #9197 lesson: never consume the elif chain with a dedicated arm, or `_aff_ready=0` reads as "select everything"). `AFFECTED_FALLBACK reason=runner-changed` and the `AFFECTED_SUMMARY` format are byte-identical (parsers: `plugins/soleur/scripts/grok-pre-push-gate.sh`, the ship/work skills read them by prefix).

**Label uniqueness comes from the live enumerate stream, not from grep.** About 270 of the 566 registrations are produced by loops and `SUITE_GLOBS`, so their labels never appear as literals; a textual "label absent from the base file" check would let an added literal collide with a glob-discovered label. The pre-pass already walks the head runner's `--enumerate-commands` stream: after the walk, every label added by this diff must occur EXACTLY ONCE in that stream; any other count degrades the run to full through the existing fallback print block (`_aff_fallback=runner-changed`, `_aff_ready` left 0), never to a silent narrow. This check sits inside the walk's else-branch, so it is a post-walk degrade, not a new ladder arm.

### The diff window and its parsing

`base=$(git merge-base origin/main HEAD)`; text = `git -c core.quotePath=false -c diff.mnemonicPrefix=false -c diff.noprefix=false diff --no-color --no-ext-diff --no-textconv --no-renames --src-prefix=a/ --dst-prefix=b/ -U0 "$base" -- scripts/test-all.sh scripts/lib/test-affected-paths.sh` (user diff config must not rename the prefixes: a commit-to-worktree diff otherwise prints `c/` and `w/`). A commit compared to the working tree yields committed plus uncommitted tracked changes, i.e. exactly what will execute. The post-image used for context rules is the working-tree file. Parsing rules, each pinned by a row:

- Track header-versus-body state from the `@@` line, never by prefix: a removed body line `-- x` prints as `--- x` and an added `++ x` as `+++ x`, which a prefix-matching awk would swallow as a file header and skip G1.
- `@@ -a[,b] +c[,d] @@`: an omitted count means 1; for a pure addition `b` is 0 and `c` is the first added line; a `+` side count of 0 is a pure deletion (G1 refuses it).
- Strip a trailing CR before every shape test (CRLF would turn a valid registration into an undiagnosable charset reject; the reject is safe but the message must name the cause).
- Any failure to obtain `base`, the text, or either image, or an EMPTY text while the runner is in the name list (mode-only change, the names-only `SANDBOX_DIFF_NAMES` seam of existing row k), classifies `undecidable`, which behaves as `semantic` (full). Row k stays valid by construction.
- The offending line printed in the banner is passed through `tr -cd '[:print:]'` and truncated: it is untrusted text going to a terminal (no escape sequences).

### The closed grammar (G)

Violating any rule makes the WHOLE diff `semantic`; the first offender is reported as `<file>:<post-image line>`. Phase 2a ships G0, G1, G2, G4 plus "any hunk in the index file is semantic"; Phase 2b adds G3 and G5.

- **G0 headers.** Only `diff --git a/X b/X`, `index`, `--- a/X`, `+++ b/X`, `@@` lines. Any `old mode`, `new mode`, `deleted file`, `new file`, `rename`, `copy`, `similarity`, `Binary files`, `GIT binary patch`, or `\ No newline at end of file` marker is `semantic`.
- **G1 no removals.** Zero removed body lines in either file. (Add is registration; delete is a narrowing edit. An edited line is a removal plus an addition.)
- **G2 runner additions** (`scripts/test-all.sh`), each added line is exactly one of:
  - blank, or a `#` comment line (no NUL), **and** the anchor rule below holds. The anchor binds EVERY added line, blank and comment lines included: a blank line after a line ending in a backslash splits a command, and a blank or comment line inside a heredoc or multi-line string changes its content. (Measured: 115 of the 137 registration-only runner commits since 2026-06-01 add a comment or blank line beside the registration, so comment admission is load-bearing for the hit rate.)
  - a registration line: `^  run_suite "<label>" <argv0> <arg>...$` with label in `[A-Za-z0-9_./ -]+`, `argv0` in `{bash, python3, bun, node}`, each arg in `[A-Za-z0-9_./@=:-]+`, no trailing backslash, no trailing comment; the label must be unique among added labels and occur exactly once in the enumerate stream (above); **and** the anchor rule holds. (Measured: 284 of the 297 live `run_suite` lines match this shape; the other 13 are multi-line, `env ...`, or quoted-argument registrations and take the full fallback.)
  - **Anchor rule:** the nearest preceding POST-image line that is neither blank nor a `#` comment must itself be a complete single-line registration line matching the same regular expression (an added one counts). This kills the continuation hazard (`cmd \` followed by an added line would join it), keeps the line out of a heredoc or a multi-line string (`USAGE` is the only heredoc in the file and its body holds no registration-shaped line), and sends a first-in-group insertion to the full fallback (fail closed). The claim is "an added line never changes an existing suite's registration", not "the line lands in the live registration region": a registration inside a relevance-gated `if` is still only a new suite.
  - Note: a mid-file insertion shifts the registration ordinals of every later suite. Selection is by label, so the bounded walk is unaffected, but positional shard placement for labels missing from the manifest shifts; `plugins/soleur/test/scripts-shard-totality.test.sh` covers it (Test Strategy).
- **G4 syntax.** `bash -n` passes on both post-image files.
- **Index file, Phase 2a.** Any hunk in `scripts/lib/test-affected-paths.sh` is `semantic`. Measured: only 5 of the 142 registration-only runner commits since 2026-06-01 touched the index at all (4 array blocks, 1 entry), so this alone serves about 96% of the measured demand.
- **G3 index additions, Phase 2b** (`scripts/lib/test-affected-paths.sh`), each added line is exactly one of:
  - part of ONE contiguous added block `AFFECTED_<MAP(label)>_PATHS=(` ... `)`: opener at column 0, entries `^  "[A-Za-z0-9_./-]+/?"$` (comments and blank lines inside allowed), closer a lone `)` at column 0, all inside one hunk, **anchored**: the nearest preceding post-image non-blank line is a column-0 `)` or a complete array-entry line (a block cannot open inside a function, heredoc or `if`); `MAP` is the census normalisation (`tr a-z A-Z`, every non-alphanumeric to `_`, leading `_` stripped) of a label ADDED in the same diff;
  - a single entry `  "<label>"` whose post-image enclosing array is `ALWAYS_ON_SUITES` (the last column-0 `NAME=(` opener before the line, with no intervening column-0 `)`), where `<label>` is a label ADDED in the same diff.
  - **Injectivity:** the label-to-array mapping is not injective (`a/b-c` and `a/b_c` both map to `A_B_C`), and an array can be named by an explicit `AFFECTED_CONSUMED_EDGES` pair (`AFFECTED_INFRA_RUNNER_PATHS`). A "new block for an added label" colliding with an existing array or label would overwrite an existing suite's edges (a previously unclassified, always-selected suite becomes edge-selected: a narrowing edit). So the array name must be (i) absent from the base lib, (ii) defined exactly once in the post-image lib, (iii) not the value of any `AFFECTED_CONSUMED_EDGES` pair in the base lib, and (iv) `MAP(label)` of no OTHER label in the enumerate stream (loop- and glob-generated labels included). Entries are `source`d as shell, so the entry charset stays closed.
- **G5 binding (Phase 2b).** Every array block / always-on entry names a label added by G2 in this diff: this is what makes a registration unable to touch an existing suite's selection.

Not admitted, on purpose: comment-only edits anywhere but beside registrations, any edit inside a function, any array append other than the two above, any `skip_suite`/gated multi-line registration, any `_MIN_ALWAYS_ON_DECLARED` / `CLOSURE_LEAF_FILES` / `_CLOSURE_LEAF_RT_*` change.

### Residual (stated, bounded)

The classifier is part of the file it judges, so a PR that edits the classifier is, by G1/G2, a semantic edit and goes full. A PR that breaks the classifier AND weakens the rows that test it in the same diff is outside this guard's reach; it is the residual ADR-242 decision 10 already accepts for staged scope, bounded by (i) the classifier rows living in `scripts/test-all-affected.test.sh`, which every runner-touching run selects (the runner is in its declared edge set and the diff names it), so a classifier that narrows its own run still executes the rows that would redden, and (ii) CI's full sharded battery on the PR head, which stays the authoritative merge gate. The Guard Contract Anchor names this.

### Banner and `--help`

In the `_aff_fallback` print block, for `runner-changed` only (the final line is copied verbatim from the live source, including its em dash: `[affected] MODE=full (degraded: ${_aff_fallback}) — selection declines disabled; relevance declines still apply.`), print BEFORE it:

```
[affected] this diff edits the runner (scripts/test-all.sh or scripts/lib/test-affected-paths.sh); the battery is running in FULL (about N min of suite time at manifest weights, serial and uncontended; contended runs take longer).
[affected] first line outside the registration grammar: <file>:<line>: <sanitized, truncated text>   (or: could not classify the diff: <reason>)
[affected] a registration-only edit (new single-line run_suite registrations for NEW suites) takes the bounded selection automatically. Preview any diff: bash scripts/test-all.sh --print-selection. To scope an edit you judge safe: git add it, then bash scripts/test-all.sh --affected --affected-scope=staged (selects on the INDEX only; earlier commits on the branch are not in its window).
```

`N` = the sum of the second column of `scripts/suite-durations.tsv` and `scripts/suite-durations-heavy.tsv` in minutes, rounded; if either manifest is absent or unparsable, the clause reads "(duration unknown, manifest unavailable)" rather than a guess. (The ask names "about N min" explicitly, so the number stays; its provenance is stated in the line.)

`--help` gains a `RUNNER EDITS` block: what triggers the fallback; that a registration-only diff narrows automatically and how to confirm (`--print-selection` shows `fallback=none`, and the run prints `AFFECTED_RUNNER_IN_SCOPE reason=registration-only`); the staged-scope command with its index-only caveat; and that `TEST_GROUP=affected` is a DISTINCT heuristic selector (#8591) with no registration-only narrowing (its content-reference signal selects every suite whose text mentions the changed path), not combinable with `--affected`, and not an escape. The existing `--affected-scope=V` help line gains the index-only caveat.

## Implementation Phases

### Phase 0 - Setup (in `soleur:work`)

- 0.1 Re-run the collision check (open issues/PRs for `runner-changed` x registration). File ONE deferral issue for the second-stage narrowing (Cut List) with re-evaluation criteria and a milestone from `knowledge-base/product/roadmap.md`; no issue for the known flakes `workspaces-boot-unlock` and `gen-github-egress-cidr` (tracked on 7376).
- 0.2 This PR is itself a SEMANTIC runner edit: its local `--affected` run degrades to full by design (dogfood of the banner), and `--print-selection` on this branch prints `runner-changed`. Do not run the full battery locally under a sibling's lock; verify with the targeted suites in Test Strategy and rely on CI's full battery as the merge gate.
- 0.3 Re-run the commit hit-rate measurement and put the numbers in the PR body.

### Phase 1 - Banner and `--help` first (separate commit; independent of the classifier)

- 1.1 Rewrite the `runner-changed` banner and the `--help` block with the `N` computation (graceful when the manifests are absent). Rows beside row k in `scripts/test-all-affected.test.sh` assert the banner text (cost clause, first-offender line or the could-not-classify reason, both commands, the verbatim em-dash `MODE=full` line). This slice alone removes the "looks like a hang" part of the problem.

### Phase 2a - RED then GREEN: the runner-only classifier

- 2a.1 RED: add the classifier rows (Guard Contract matrix, runner-file rows) to `scripts/test-all-affected.test.sh`, after row k and outside every pinned extraction span. Function-level rows extract `_aff_classify_runner_diff` by awk range; three end-to-end rows run the real runner in the existing trimmed-corpus sandbox with a diff-text seam injected by `build_sandbox` at one unique anchor (never shipped inline; the #9197 discipline). Fixtures are scratch git repos built by copying files, never links (#8800). All RED before 2a.2.
- 2a.2 GREEN: `_aff_classify_runner_diff` (G0, G1, G2, G4, "any index hunk is semantic") beside `_diff_edge_hit`; the class computation, the extra elif conjunct, the else-branch note, the post-walk label-uniqueness degrade.
- 2a.3 Verify, do not weaken, every pinned consumer: `plugins/soleur/test/fanout-suite-scope.test.sh` neuter anchor, `scripts/test-all-affected.test.sh` rows k / sc1-sc9 / q4 / w1 / A7, `scripts/test-affected-derive.test.sh` A5.

### Phase 2b - Index declarations (separable commit; droppable without touching 2a)

- 2b.1 RED then GREEN: G3 + G5 and the injectivity rules, with their matrix rows (6, 7, 16). Flagged as a User-Challenge in `decision-challenges.md`: the operator named "a new AFFECTED_*_PATHS array" as registration-only, while review recommended cutting it on the measured 3.5% demand. Default is the operator's direction (implement); dropping 2b changes no 2a line.

### Phase 3 - ADR amendment (short)

- 3.1 Amend ADR-242 via `soleur:architecture` (see the section below): about 25 lines, not a second ADR. It is an amendment, not a new ordinal, so the ordinal-collision gate does not apply; run the ADR lint that `soleur:architecture` names.

### Phase 4 - Learning

- 4.1 Write ONE learning, `knowledge-base/project/learnings/2026-10-05-registering-a-suite-is-itself-a-runner-edit.md`, one short page: the measured wall (2h13m stopped run; 91.4 vs 58.6 min at manifest weights), why the runner and the index are their own SUT AND the registration surface, the label-binding rule as the answer to ADR-242's "data-shaped narrowing" objection, and the closed-grammar-not-lexer lesson. Route via `soleur:compound` at ship; not written during planning.

## Files to Edit

- `scripts/test-all.sh` - classifier function, class computation after the membership block, extra elif conjunct, else-branch note, post-walk uniqueness degrade, banner, `--help`.
- `scripts/test-all-affected.test.sh` - banner rows and the classifier rows (after row k; no new suite, no new registration, no new always-on entry).
- `scripts/lib/test-affected-paths.sh` - header comment only (the line saying a diff touching either file degrades to full names the registration-only exception for the runner file). NOTE: this is an index-file edit, so this PR's own diff is semantic by design.
- `knowledge-base/engineering/architecture/decisions/ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md` - amendment 2026-10-05 (decision 20), `amended_by` frontmatter entry, pointer from the option-d row of the 2026-09-29 "Alternatives added" table.

## Files to Create

- `knowledge-base/project/learnings/2026-10-05-registering-a-suite-is-itself-a-runner-edit.md` - the one learning (Phase 4).

`plugins/soleur/skills/work/SKILL.md` and `plugins/soleur/skills/ship/SKILL.md` were checked and are NOT edited: their statements ("a diff touching the runner or index itself degrades the run to the full battery") stay true for every non-registration edit.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1. In the battery's fixture (a scratch git repo whose base is a copy of the runner and index; the PR branch itself cannot show this because it carries the semantic classifier edit), a diff with exactly one new anchored single-line `run_suite` registration plus an untracked suite file prints `AFFECTED_RUNNER_IN_SCOPE reason=registration-only` and `AFFECTED_SUMMARY ... fallback=none`, selects the new label, and prints no `AFFECTED_FALLBACK`. (Pre-change the same fixture prints `fallback=runner-changed`, selected=all.) The assertion is `fallback=none` plus the new label selected, not a selection count.
- [ ] AC2. Each semantic row of the Guard Contract matrix prints `AFFECTED_FALLBACK reason=runner-changed` and `fallback=runner-changed` (full); the registration-only fixture plus ONE semantic line elsewhere also goes full.
- [ ] AC3. The classifier rows pass; with `_aff_classify_runner_diff` mutated to always return `registration-only` the semantic rows go RED; mutated to always return `semantic` the must-PASS rows go RED; the end-to-end dispatch row goes RED when the pre-pass stops consulting the classifier.
- [ ] AC4. The full-fallback banner contains the cost clause (`about <N> min`), the first offending `<file>:<line>` (sanitized), the preview command and the staged-scope command with its index-only caveat; the final `MODE=full (degraded: runner-changed) — selection declines disabled; relevance declines still apply.` line is byte-identical to the live source (em dash included); `AFFECTED_FALLBACK reason=runner-changed` and the `AFFECTED_SUMMARY` format are unchanged (existing row k and the grok pre-push parser still pass).
- [ ] AC5. `bash scripts/test-all.sh --help` contains a `RUNNER EDITS` block naming `--print-selection`, `--affected --affected-scope=staged` with its index-only caveat, and that `TEST_GROUP=affected` is a distinct selector that does not narrow runner edits.
- [ ] AC6. `bash scripts/lint-orphan-test-suites.sh` is green; `bash plugins/soleur/test/fanout-suite-scope.test.sh`, `bash scripts/test-all-affected.test.sh`, `bash scripts/test-affected-derive.test.sh`, `bash scripts/test-all-group-affected.test.sh`, `bash plugins/soleur/test/scripts-shard-totality.test.sh` pass.
- [ ] AC7. `python3 scripts/lint-guard-contract.py` passes on this plan and `bash plugins/soleur/test/c4-count-parity.test.sh` stays green (13 passed, 0 failed at plan time).
- [ ] AC8. ADR-242 carries amendment decision 20 and its option-d row points to it.
- [ ] AC9. `git diff --stat origin/main` shows only the files listed above; no production write, no change under `.github/workflows/`.

## Test Strategy

Local verification is targeted, not the full battery (this PR is a semantic runner edit and would degrade to full by design; sibling sessions hold the advisory lock): run `scripts/test-all-affected.test.sh`, `plugins/soleur/test/fanout-suite-scope.test.sh`, `scripts/test-affected-derive.test.sh`, `scripts/test-all-group-affected.test.sh`, `scripts/lint-orphan-test-suites.sh`, `plugins/soleur/test/scripts-shard-totality.test.sh` directly, plus a scratch registration edit on a base-derived tree (revert; `git status` clean). CI's sharded full battery is the merge gate. Acceptance criteria are deterministic fixtures: none depends on ambient machine state or a sibling session.

## Guard Contract

### Guard 1 - registration-only runner-diff classifier (`_aff_classify_runner_diff` in `scripts/test-all.sh`)

**Property.** No runner/index diff reaches the bounded selection unless every changed line is a new-suite registration (or, in Phase 2b, an index declaration bound to a suite registered in the same diff); any other change, in either file, in any hunk, falls to the full battery.

**Assembly.** Chokepoint: the single call site in the pre-pass that sets `_aff_runner_class`, the single extra conjunct on the `runner-changed` elif, and the post-walk uniqueness degrade; all three must flow through `_aff_classify_runner_diff` and the one fallback print block. The population the property quantifies over is every changed line of BOTH files across ALL hunks (the classifier folds over hunks, not the first), every header kind git can emit for a path (mode, rename, delete, binary, no-newline), every input branch of the decision (git failure, no merge-base, empty text with the runner in the name list, `--paths` mode, the names-only seam of row k), every label source (literal `run_suite` lines AND loop/glob-generated labels, via the enumerate stream), and both scopes (staged scope stays byte-identical: the classifier is not computed there). Members drift (new array kinds, new registration shapes); the structure is "allowlist of whole-line shapes, default semantic". The label-binding relation (an index addition names a label added in the same diff, and no existing label maps to the same array) is part of the assembly, not a per-member check.

**Mutation matrix:**

| # | Mutation (edit that MUST drive the guard RED, i.e. keep or force the full battery) | Expected |
|---|---|---|
| 1 | Semantic edit: add `_aff_fallback=""` (or edit `_MIN_ALWAYS_ON_DECLARED=141` to `=0`) in the runner | `AFFECTED_FALLBACK reason=runner-changed`, full |
| 2 | Registration-shaped smuggle: `run_suite "x/new" bash a.test.sh; _aff_fallback=` (and variants with `$(...)`, backticks, `&&`, a redirect, a trailing comment) | each rejected by the charset, full |
| 3 | Delete an existing `run_suite` line, and edit an existing `run_suite` argv with the label unchanged (G1 is one rule: any removed line) | full |
| 4 | Two hunks: a clean registration, then a semantic line elsewhere (the second member after a compliant first) | full; the offender reported is the second hunk's line |
| 5 | New `AFFECTED_FOO_PATHS` array for an EXISTING unclassified label (the narrowing-by-data edit ADR-242 named) (Phase 2b; in 2a every index hunk is already semantic) | G5 violated, full |
| 6 | Append an entry to `CLOSURE_LEAF_FILES` / `_CLOSURE_LEAF_RT_HOOKS` / `AFFECTED_CONSUMED_EDGES` (Phase 2b) | enclosing array not admitted, full |
| 7 | Continuation and context hazards: an added registration, blank line, or comment directly after an unchanged line ending in `\` (the four live backslash-continued `run_suite` calls are the real shape); a blank line added inside the `USAGE` heredoc; an added registration-shaped line after a non-registration line | anchor rule binds every added line, full |
| 8 | `chmod`-only change, rename, or delete of either file; binary header; `\ No newline at end of file` | G0, full |
| 9 | Own dispatch: remove the call site so the pre-pass never computes the class, then run the registration-only fixture | the end-to-end row reports `fallback=runner-changed` instead of `none` (a guard that is never consulted is detected) |
| 10 | Vacuity: classifier invoked but the awk fold sees zero hunks (empty text, `SANDBOX_DIFF_NAMES` names-only, no merge-base, git error) | `undecidable`, run is full, never `registration-only` ("0 lines checked" cannot pass); `--paths` mode never calls the classifier and stays full |
| 11 | Reorder/lifetime: compute the class from the STAGED diff, or before `git merge-base` resolves, instead of merge-base..working tree | a fixture with a committed semantic edit plus an unstaged clean registration goes `semantic` (the window is the property) |
| 12 | Label collision: add a `run_suite` whose label already exists as a loop- or glob-generated label (absent as a literal in the file); and two added lines with the same new label | post-walk uniqueness degrade, full |
| 13 | Syntax: a clean-looking registration whose post-image fails `bash -n` (unbalanced quote added in a comment line) | G4, full |
| 14 | Non-injective mapping (Phase 2b): add `a/b_c` while `a/b-c` exists, with a "new" `AFFECTED_A_B_C_PATHS` block; a new label whose mapped name equals an `AFFECTED_CONSUMED_EDGES` target; an array block opened inside a function or `if` | injectivity rules (i)-(iv) and the block anchor, full |
| 15 | Parser pitfalls: a removed body line `-- x` (prints as `--- x`) and an added `++ x` (prints as `+++ x`) hidden inside an otherwise clean diff; user config `diff.mnemonicPrefix=true`; CRLF line endings | header-versus-body tracking catches the removal; prefixes pinned; CR stripped (still `registration-only` for a clean CRLF registration) |

**Harness rows** (edits to the SUITE, not the guard; at least one must-PASS non-canonical input):

| # | Edit to the suite or fixture | Expected |
|---|---|---|
| H1 | Replace the classifier with `echo registration-only` | the semantic rows go RED (the suite can see a permissive stub) |
| H2 | Replace the classifier with `echo semantic` | the must-PASS rows go RED (the suite can see a reject-everything stub; RED rows alone cannot) |
| H3 | Must-PASS non-canonical: a label containing spaces and dots (`tests/scripts/a.b c`; bracketed labels such as `apps/web-platform [unit]` are NOT in the grammar), a `python3 -m unittest tests.scripts.test_x` argv, a registration after a blank-and-comment run, two new registrations in one hunk; in Phase 2b also two registrations plus their `AFFECTED_*_PATHS` block and an `ALWAYS_ON_SUITES` entry | all `registration-only` (each differs from the canonical single-line bash row in a way the grammar explicitly permits) |
| H4 | Fixture-builder mutation: build the scratch repo without `origin/main` | the rows fail loudly at fixture build (rc 98 convention), they do not skip to green |
| H5 | The runner under test is a COPY: assert the copy's classifier text equals the live runner's (extraction-span parity) | RED if the rows ever test a stale copy |

**Anchor.** The classifier compares nothing stored; it compares the diff against a fixed grammar, so the thing an edit would move is the grammar itself, and the grammar lives in the file it judges. A weakening therefore needs a diff that edits the classifier (non-grammar lines, so the local run goes FULL and exercises the whole battery) AND the rows that test it. What outside the commit must also move: CI's required `test` context runs the full sharded battery on the PR head, and the runner-touching selection always includes `scripts/test-all-affected` (edge on the runner), which carries these rows. Set identity, not a count floor: the matrix pins the admitted shapes by fixtures, not by a `>= N` ratchet.

**Exit-site table (the classifier writes nothing into the user's tree; it reads git and runs `bash -n` on the post-image):** it creates no files and needs no cleanup; every failure exits through `undecidable` (semantic) via `|| _aff_runner_class=undecidable`, so a `set -e` abort cannot occur. Any temp file for the awk fold is created under `$TMPDIR` by `mktemp` and removed in the existing runner `EXIT` trap.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-242 (`soleur:architecture`), short (about 25 lines): `## Amendment - 2026-10-05`, **decision 20** - *A registration-only runner diff takes the bounded selection under branch scope; every other runner edit keeps `runner-changed`.* Content: the closed grammar G0-G5 in one paragraph, the label-binding and enumerate-stream uniqueness rules, the banner contract; the reversal in part of the 2026-09-29 option-d rejection with its two reasons answered (see Premise Validation); the measured costs (91.4 vs 58.6 min at manifest weights, 36%; 61.5% of runner-touching commits are registration-only); the accepted residual (identical to decision 10); Alternatives considered: (b) data-file registrations, (c) banner only, selection-equivalence oracle, third-file classifier, `SUITE_GLOBS` auto-discovery, admitting deletions. Add an `amended_by` frontmatter entry and a pointer in the option-d table row. The amendment ships in THIS plan's PR (`wg-architecture-decision-is-a-plan-deliverable`), not as a deferred issue.

### C4 views

No C4 impact. Checked against all three model files (`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`, read, not keyword-grepped): (a) external human actors: `contributor` ("Contributor / PR Author") and `founder` already modeled; the `contributor` description scopes PR-head execution trust boundaries and states operator-side execution of a checked-out PR head is outside both boundaries - it does not describe local gate SCOPE, so nothing it says is falsified; (b) external systems: GitHub/CI already modeled, unchanged (CI runs the full battery; the affected axis is off under `CI`); no new vendor; (c) containers/data stores: none touched (a local script and two TSV data files); (d) actor-surface relationships: none change. The derived-cardinality gate was run: `bash plugins/soleur/test/c4-count-parity.test.sh` -> 13 passed, 0 failed (2026-10-05).

### Sequencing

None: the decision is true on merge (no soak-gated slice).

## User-Brand Impact

**If this lands broken, the user experiences:** a contributor's local `--affected` run reports a bounded selection (and exits green) for a runner edit that actually changed selection semantics, so a narrowing edit reaches review looking verified; CI's full sharded battery on the PR head still gates the merge, so the failure shows up as a red CI check after a green local gate, not as a shipped regression.

**If this leaks, the user's [workflow] is exposed via:** no data, credential, or runtime surface is touched (local test-selection tooling in `scripts/`; no network, no secret read, no production write); the only exposure is a false-green local verdict, bounded as above.

**Brand-survival threshold:** none

threshold: none, reason: local test-selection tooling with no user-data, credential, auth or production path; CI's full battery remains the authoritative merge gate and the failure mode is a false-green local gate that CI catches.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed

**Assessment:** Recorded from the research above and the CTO assessment run during planning (see Plan Review Revisions). Engineering concerns: the closed-grammar classifier must default to semantic and model none of bash's syntax; the classifier lives in the file it judges (accepted residual, bounded by the always-on runner-SUT battery and CI); the saving is 36% at manifest weights, so the banner must state the cost honestly rather than imply minutes; a second-stage narrowing is deferred with a tracking issue.

No Product/UX surface (no `components/`, `app/**/page.tsx`, or UI files in Files to Edit/Create), so the Product/UX Gate does not fire and no wireframe is required.

## Observability

```yaml
liveness_signal:
  what: the AFFECTED_RUNNER_IN_SCOPE reason=registration-only note on the bounded path, and the banner's first-offender line on the full path, for every runner-touching affected run
  cadence: per local --affected / --print-selection run
  alert_target: the operator terminal and the ship/work skill transcripts that already grep AFFECTED_FALLBACK
  configured_in: scripts/test-all.sh pre-pass
error_reporting:
  destination: stdout note plus stderr banner; a classifier failure is reported in the banner as could-not-classify and runs the full battery (fail loud, never a silent narrow)
  fail_loud: true
failure_modes:
  - mode: classifier admits a semantic edit
    detection: the classifier rows in scripts/test-all-affected.test.sh (selected by every runner-touching run) and CI full battery
    alert_route: red suite in the local gate and a red required CI check
  - mode: classifier cannot decide (no merge-base, git error)
    detection: the banner's could-not-classify reason
    alert_route: terminal banner; the run proceeds full
logs:
  where: stdout/stderr of scripts/test-all.sh; per-suite scratch logs already printed on the summary line
  retention: the existing per-run scratch log retention
discoverability_test:
  command: bash scripts/test-all.sh --help
  expected_output: RUNNER EDITS
```

## Risks and Sharp Edges

- The dominant risk is a semantic edit shaped like a registration. The charset is closed (no `$`, backtick, quote, `;`, `|`, `&`, `<`, `>`, `(`, `)`, backslash in argv), and the anchor rule keeps added lines out of continuations, heredocs and strings; matrix rows 2, 7, 8 pin them.
- A diff of only registration-shaped lines can still land the line in the wrong `if want_*` group; that changes which group the NEW suite runs in, never an existing suite's selection, and the orphan census plus the new suite's own run catch a suite that never executes.
- `fanout-suite-scope.test.sh` neuters the membership block by exact text; do not reformat those lines.
- `scripts/test-all-affected.test.sh` pins extraction spans and `grep -A3` offsets (rows w1, A7): add new rows after row k, never inside a pinned block, and re-run the whole file.
- The banner's `N` is a manifest-weight sum, not a promise; it must say "at manifest weights, serial and uncontended".
- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6; this one carries all three lines.
- The staged-scope arm must stay byte-identical (ADR-242 decision 10): the class is not computed under `--affected-scope=staged`.
- `set -euo pipefail` is active in the runner: the classifier call is `|| _aff_runner_class=undecidable` and its variables are initialised first.
- The label-uniqueness check must sit inside the walk's else-branch as a post-walk degrade; a new ladder arm would repeat the #9197 silent-full-battery defect.
- The measurement edit (one `run_suite` line, an untracked suite, two TSV rows) was reverted; `git status` was clean before this plan was written.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "stop registering a new test suite from degrading the affected-gate to the full battery" | Design, Phase 2a, AC1 | mapped |
| 2 | "Distinguish a REGISTRATION-ONLY runner edit (append of a run_suite line / a new AFFECTED_*_PATHS array / TSV rows) from a SEMANTIC runner edit (selection logic, classification, exit handling)" | Closed grammar G0-G5 (index declarations in Phase 2b), AC1, AC2 | mapped (TSV rows are not triggers; verified) |
| 3 | "recommend ONE, with the failure mode each prevents and the one it risks" | Overview (mechanism a), Cut List, Premise Validation | mapped |
| 4 | "Whatever is chosen needs a mutation battery proving a semantic edit still falls back to full." | Guard Contract, Phase 2a.1, AC3 | mapped |
| 5 | "the degraded banner must say \"this diff edits the runner; the battery is running in full (about N min); registration-only edits can be verified with <command>\"" | Banner and `--help`, Phase 1, AC4 | mapped |
| 6 | "Include the correct invocation in the --help text" | Banner and `--help`, AC5 | mapped |
| 7 | "Measure, don't guess: add ONE trivial run_suite line + one TSV row (scratch edit in this worktree, revert after), run `bash scripts/test-all.sh --print-selection`" | Measurements table | mapped (done during planning) |
| 8 | "plan (soleur:plan) with Property List + Cut List + Guard Contract mutation matrix (>=3 rows incl. a semantic edit that must still go full), then deepen" | Research Insights, Guard Contract | mapped |
| 9 | "Add ONE learning for \"registering a suite is itself a runner edit\" (planned, written during work)" | Phase 4, Files to Create | mapped |
| 10 | "Offline/local only; no production writes." | AC9, Observability | mapped |
| 11 | "do not touch the main checkout or other sessions' worktrees" | Test Strategy (targeted suites, no full battery) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `scripts/test-all.sh` classifier, banner, `--help` | asks 1, 2, 5, 6 | asked |
| classifier rows in `scripts/test-all-affected.test.sh` | "Whatever is chosen needs a mutation battery proving a semantic edit still falls back to full." | asked |
| Phase 2b (index declarations: G3, G5, injectivity) | "a new AFFECTED_*_PATHS array" | asked (operator-named registration-only shape; flagged as a User-Challenge because review measured 3.5% demand and recommended cutting it) |
| post-walk label-uniqueness degrade | "a semantic edit can slip through" (the rejected-by-design trap) | inferred - justification: loop- and glob-generated labels are invisible to a textual label check, so a literal registration could alias an existing suite; the degrade is the cheapest closure of that hole |
| ADR-242 amendment | "recommend ONE, with the failure mode each prevents and the one it risks" | inferred - justification: the ADR corpus recorded this mechanism as a rejected alternative, and `wg-architecture-decision-is-a-plan-deliverable` makes the amendment part of the change, else the recorded architecture lies |
| `scripts/lib/test-affected-paths.sh` header comment | "registration-only edits can be verified with <command>" | inferred - justification: the header currently states the contradicted rule ("a diff touching either degrades the gate to full"), so it must name the exception or the comment lies |
| learning file | ask 9 | asked |
| Deferral issue for second-stage narrowing | - | inferred - justification: deferral tracking (`wg-defer-only-after-inline-triage`): a deferred item without an issue is invisible |

### Split Assessment

- Subsystems touched: 3 - `scripts/` (runner, lib header, one test file), `knowledge-base/engineering/architecture/decisions/`, `knowledge-base/project/learnings/`
- Planned files: 5 | Estimated changed lines: about 350-450 (classifier about 90, banner/help about 40, test rows about 180, ADR about 30)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Plan Review Revisions

### CTO assessment (Phase 2.5 domain leader, 2026-10-05)

1. **Applied.** Blank/comment lines are not inert (continuation, heredoc, quoted string): the anchor rule now binds every added line (G2), matrix rows 8, 9, 17.
2. **Applied.** The label-to-array mapping is not injective and can alias an existing or explicitly-mapped array: the Injectivity rules (G3 (i)-(iv)) and row 16 were added.
3. **Disputed with measurement.** The CTO's cheaper single mechanism is (b), a data file, and asks for the classifier's hit rate first. Measured: 62% of runner-touching commits since 2026-06-01 are registration-only (see Measurements), so the narrowed path is the common case; (b) remains cut for its re-tiling cost and because the data file becomes a third trigger path needing its own grammar. The CTO's fallback "(c) plus the staged-scope hint" is KEPT as the banner for the fail-closed arm. The 296-run_suite-lines versus 566-registrations gap is loops and auto-discovered globs, which need no runner edit; the grammar governs only new literal one-liners.
4. **Constraints honoured.** No env var for classifier behaviour (flag-selected scope, ADR-242 decision 11): none is added. The registration-only note stays inside the walk's else-branch (the #9197 silent-full-battery lesson). The below-floor `_MIN_ALWAYS_ON_DECLARED` refusal still precedes it. ADR-262: the runner and the index are in `PR_GATE_MACHINERY_PATHS` and arm every gated battery through the unchanged NAME list, which still contains both paths in a registration-only run, so the gated batteries keep arming; the matrix does not touch that arming (acceptance: the 43-suite edge count is unchanged by the classifier).

### Plan-review panel (DHH, Kieran, code-simplicity; headless 2026-10-05)

Mechanical findings applied to this plan:

- Kieran: label uniqueness must come from the enumerate stream, not grep (loop/glob labels); AC1 cannot run on the PR branch (semantic) so it moved to a base-derived fixture and dropped its drifting counts; the `MODE=full` line quoted with its real em dash; the always-false pseudo-guard replaced by the explicit rung conditions and `--paths` skip; `set -euo pipefail` handling (`|| undecidable`, initialised variables); diff-parsing pitfalls (header-vs-body state from `@@`, pinned prefixes, `--no-textconv`, CR strip, omitted counts); G3 block anchor; banner offender sanitised; ordinal shift noted; "closed grammar" wording tightened to "never changes an existing suite's registration".
- DHH + simplicity: classifier rows folded into `scripts/test-all-affected.test.sh` (no new suite, no always-on entry, ADR-262 had withdrawn that battery from always-on for the same reason); the `AFFECTED_RUNNER_CLASS` record and the two SKILL edits cut; banner and `--help` shipped first as its own commit; ADR amendment shortened; matrix rows 3/4 and several others merged (17 rows to 15 plus 5 harness rows).
- Measured instead of argued: the hit rate was re-run WITH the anchor rule (152 of 226 commits fit, 139 add a registration; 137 runner-only, 4 array blocks, 1 entry; 115 of 137 carry a comment or blank line, so comment admission is load-bearing).

Taste / User-Challenge findings (persisted to `knowledge-base/project/specs/feat-one-shot-registration-only-runner-edit/decision-challenges.md`, not auto-applied): cut the index-declaration slice (G3/G5, injectivity) on the measured 3.5% demand; drop blank/comment admission; "a registration-only run still costs 58.6 min, measure before building"; matrix size; anchor-rule simplification; `SUITE_GLOBS` auto-discovery as the real fix for the common case.
