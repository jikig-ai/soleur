---
title: "ci: make the doc-only skip classifiers mode-aware (#10416); #10415 deferred with sharpened re-evaluation criteria"
type: fix
date: 2026-10-18
slug: ci-mode-aware-doc-only-classifiers
branch: feat-one-shot-10415-10416-s4-followups
issue: 10416
closes: [10416]
refs: [10415, 9729]
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

# ci: make the doc-only skip classifiers mode-aware (#10416); #10415 deferred

Spec lacks valid `lane:` (no spec.md for this branch) — defaulted to cross-domain (TR2 fail-closed).

## Overview

Two follow-ups deferred from the S4 affected-only work (Ref #9729) were asked for in one PR.

- **#10416 (built here).** `scripts/ci-e2e-classify.sh` and `scripts/ci-shard-totality-classify.sh` decide "this pull request cannot move the job" from `git diff --name-status` rows, which carry no file mode. An added symlink named `*.md` (status `A`), a symlink-to-file swap that git reports as `T` (already caught), or an exec-bit flip on a `.md` (status `M`) is therefore still "markdown" and the required `e2e` job (and the non-required `shard-totality-mutations` battery) is skipped. The S4 PR B driver (`scripts/ci-pr-selection.sh`, stage 1) already judges modes from `git diff --raw`. This plan feeds the classifiers `--raw` rows and gates on modes, failing closed on anything it cannot parse.
- **#10415 (deferred, not built).** Ruled by the CTO agent (below) as out of scope: the marker `SOLEUR_FULL_BATTERY_ESCAPE` has no emitter on `main` (S4 PR C ended NO-GO and its audit probe was never built), so a Better Stack heartbeat would be a dead observability surface. The PR ships the ruling and sharpened, observable re-evaluation criteria; the PR body uses `Ref #10415`, not `Closes #10415`.

**Does merging this alone mutate production?** No infrastructure, secret, ruleset, variable or Terraform state changes. Merging changes only how two CI classify steps judge future pull requests (fail-closed direction); `merge_group`, `push` and `workflow_dispatch` runs are unaffected because both classifiers emit `true` off `pull_request` before reading any row.

Hard constraints honoured: `CI_PR_AFFECTED` is not touched, the lock stays, activation state is unchanged, `scripts/required-checks.txt` is unchanged, #10414 and #10448 (index completion) are not started, `scripts/ci-pr-affected-preactivation.test.sh` and `scripts/ci-pr-affected-replay.*` are not edited (the CTO grepped both: neither references the classifiers, so their assertion/mutant floors are unaffected). Git identity is the configured one (`jean.deruelle@jikigai.com`), never `s@example.invalid`.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / ADR / header comment) | Reality (verified on origin/main 840dc667fc) | Plan response |
|---|---|---|
| #10416: the PR B driver's allowlist is "ordinary file modes only", so align the classifiers with it | The driver allows modes `{000000, 100644, 100755}` (`scripts/ci-pr-selection.sh` lines 343-344; a 100644 to 100755 flip on a doc file stays doc-class). The issue title nonetheless names "executable". | Classifiers are STRICTER than the driver (CTO ruling R2): new mode must be `100644`; `M` needs old `100644` too; `A` needs old `000000`. The driver can afford 100755 because later stages also gate; a classifier skip has no second stage. Headers document the deliberate divergence. |
| `ci-shard-totality-classify.sh` header: the no-mode gap "is accepted here because the battery's census reads only `*.sh`/`*.bash` and shebang files" | A shebang file is a census subject. An executable `.md` that starts with `#!` is therefore readable by the battery. The accepted-exposure comment is wrong for exec-bit rows. | Header rewritten; exec-bit rows now fail closed. |
| ADR-276 "Named responder for `SOLEUR_FULL_BATTERY_ESCAPE`" says a Better Stack route is wired and "PR C wires the route" | ADR-276 PR C amendment item 4(b) records that the audit probe, the filing job and the paging route were never built. `git ls-files plugins/soleur/scripts/ci-full-battery-audit.sh` is empty; `git grep -n 'full-battery-escape'` (excluding archive) hits only ADR-276 text. | #10415 deferred. No ADR-276 edit (the ADR convention is that superseded sentences stay unedited and 4(b) already supersedes the bullet). |
| #10415: the heartbeat needs `betteruptime_heartbeat` + a Doppler secret + a GitHub Actions secret | Existing Better Stack Terraform is in `apps/web-platform/infra` (`uptime-alerts.tf`, `betterstack-logs-alerts.tf`, `web-probe.tf`, ...). Creating the two secrets and applying Terraform is production-mutating and cannot be finished by a PR. | Not built (ruling R1). |
| Issue text: the classifier skip is used only for "a non-required job or `e2e`" | `e2e` is required (`scripts/required-checks.txt`); `shard-totality-mutations` is not in it and not in the `test` aggregator's `needs`. | No change needed; recorded as the re-evaluation boundary for #10416 (see Deferrals). |

## Research Insights

**Premise validation (Phase 0.6).** Checked by reference: #10415, #10416, #10414, #10448, #9729 all `OPEN`, none closed by a PR. #10416's cited artifacts exist: both classifiers (`git ls-files scripts/ci-e2e-classify.sh scripts/ci-shard-totality-classify.sh`), the driver's `GUARD:G2-MODE-OLD/NEW` lines, and the three pinning suites. Held: the mode-blind behaviour is real (reproduced: a symlinked `.md` and an exec-bit `.md` are `A`/`M` under `--name-status` but `120000`/`100755` under `--raw`, scratchpad fixture). Stale: the "ordinary file modes only" wording (see reconciliation row 1) and the ADR-276 named-responder bullet (row 3). Mechanism vs. ADR corpus: ADR-276 "Supersession (2)" already states the intended rule ("status M, or A/D inside that set, ordinary file modes only"); this PR conforms the PR A classifiers to it and is not a new decision.

**Property List (Phase 0.6b).**
- P1. A pull-request diff containing a symlink, gitlink or exec-bit markdown path never yields a skip verdict from either classifier.
- P2. An ordinary markdown-only pull request (modes `100644`) still skips, so the measured saving is kept.
- P3. The classifiers stay judged by the BASE ref's copy; a PR cannot weaken the gate it is judged by.
- P4. Any input the classifier cannot parse as a raw row (legacy name-status, bare path, malformed, renamed) fails closed (`true`).
- P5. (#10415) A `SOLEUR_FULL_BATTERY_ESCAPE` reaches a human. Buyable only once an emitter exists.

**Cut List (Phase 0.6b).**
- Better Stack `betteruptime_heartbeat` + Doppler/GitHub secrets (P5) -> no emitter exists to ping it; deferred by CTO ruling R1.
- Shared sourced helper for the row parse in `scripts/lib/` -> the classifiers run from a base-ref `git show` copy in `$RUNNER_TEMP` where `scripts/lib` is absent, and `scripts/lib/**` is on the driver's full-battery trigger list. Replaced by duplicated block + byte-parity test (R3).
- Per-path `git ls-tree` mode lookup inside the classifier -> `--raw` rows already carry both modes (P1 bought with zero extra git calls).
- ADR-276 edit -> 4(b) already supersedes the stale bullet.
- Aligning to the driver's `100755` allowance -> would keep the shebang-census exposure open (R2).

**Value-proposition measurement (Phase 0.6c).** No cost saving is claimed. The risk to P2 is measured by an acceptance criterion: replay the new classifier over recent markdown-only first-parent commits and require the verdict to match the old classifier's wherever no non-`100644` mode is present (command in AC9).

**Local research.** Files: `scripts/ci-e2e-classify.sh` (76 lines), `scripts/ci-shard-totality-classify.sh` (75), `scripts/ci-pr-selection.sh` (driver, stage 1 at lines 332-356, `is_doc_path` at 181-188), `.github/workflows/ci.yml` classify steps (`Classify shard-totality applicability` ~1708-1738, `Classify e2e applicability` ~2210-2262), pinning suites `plugins/soleur/test/ci-e2e-skip-anchors.test.sh` (floor 51), `ci-shard-totality-skip.test.sh` (floor 52), `ci-classify-step-exec.test.sh` (floor 16). Shard registration of those three already exists (`scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv`), so adding NO new suite file avoids the shard-totality and orphan-suite gates.

**Institutional learnings applied** (`knowledge-base/project/learnings/`):
- `2026-10-12-docs-only-ci-skip-premise-is-false-when-tests-read-the-kb.md` — a skip is only as safe as the reader inventory behind it; the `&& 0 || 1` falsy ternary gotcha is already pinned.
- `2026-10-01-anchoring-a-matcher-flips-its-error-direction-and-the-ratchet-i-wrote-never-ran.md` — when a matcher gets stricter, ask what text it can no longer see (rename rows, C-quoted names).
- `security-issues/2026-09-18-my-fix-for-the-allowlist-bypass-shipped-a-second-bypass.md` — enumerate create/delete/rename/copy shapes; refuse on empty derived set.
- `2026-05-10-empirical-hook-input-shape-prevents-silent-zero-emission.md` and `2026-03-03-set-euo-pipefail-upgrade-pitfalls.md` — here-string over pipe (SIGPIPE) is already used; keep it.
- `2026-10-14-a-dark-lever-measures-itself-...md` — after editing test files, run the repo-global ratchets (`fixture-relative-assert`, `guard-vacuity-floor`, `test-affected-kb-consumers`), not only the touched suites.
- `2026-07-24-count-vs-floor-guard-single-value-fixtures-cannot-discriminate-operator.md` — test off the boundary; applied to the mutation-count pin.

**Overlap preflight.** `bash plugins/soleur/skills/ship/scripts/pr-overlap-preflight.sh --mode start --files "<planned files>"` -> `No other open work overlaps`. Open PR probe for the planned paths: #10451 touches only `apps/web-platform/server/sandbox-startup-classifier.ts` (no overlap); #7390 (a stale WIP) edits `.github/workflows/ci.yml` in an unrelated job (provenance build arg) — textual conflict is possible only if it is revived; acknowledged. Sibling worktree `feat-one-shot-9757-heartbeat-url-off-argv` is a different issue and does not touch these paths.

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` searched for each planned file path; no matches.)

## Decisions (CTO rulings, 2026-10-18; persisted in `knowledge-base/project/specs/feat-one-shot-10415-10416-s4-followups/decision-challenges.md`)

- **R1 (#10415).** Ruled by CTO agent, 2026-10-18: defer; build nothing for #10415 in this PR; PR body says `Ref #10415` - a heartbeat with no emitter is a dead surface, and a heartbeat is the wrong shape for an event marker (it alarms on a missing ping, the marker is a should-never-appear event); the Terraform could be written unapplied but its Doppler and GitHub secrets are production-mutating, leaving half-wired infra with an unfinishable last step.
- **R2 (#10416 modes).** Ruled by CTO agent, 2026-10-18: strict in BOTH classifiers - status `A` needs old `000000` and new `100644`; status `M` needs old and new both `100644`; everything else (100755, 120000, 160000, any mode-changing `M`) emits `true` - strict is a subset of the driver's allowlist so it never passes what the driver blocks, and the shard-totality census reads shebang files.
- **R3 (#10416 input contract and placement).** Ruled by CTO agent, 2026-10-18: both classifiers and both `ci.yml` classify steps move to `git diff --raw --no-color --no-ext-diff "origin/${GITHUB_BASE_REF}...HEAD"` (default rename detection kept, no `-z` because the here-string and command substitution drop NULs); a row that does not match the raw-row grammar emits `true` (this removes the "bare path is M" rule, a deliberate contract break); duplicate the ~12-line parse block in both scripts with a byte-parity test, no sourced helper; editing the two classify steps is not the S4 activation path and `scripts/required-checks.txt` is untouched.
- **R4 (transition).** Ruled by CTO agent, 2026-10-18: the old base-ref classifier reads the first whitespace token (`:100644`) as the status, which is not `M`/`A`, so it emits `true` on raw rows: this PR's own CI run therefore runs the full `e2e` and shard-totality battery. That is the safe direction and is expected; it is stated in the PR body so nobody reads it as a regression.

## Proposed Solution

### Row grammar and gate (identical block in both scripts)

Replace the status/path parse in each classifier with a raw-row parse. The marker-delimited block is ONE contiguous region inside the `while read` loop (both `tab` and `row_re` are assigned inside it, a per-iteration cost of nothing, so the parity extraction compares a single region). Final text is written at work time; sketch:

```bash
  # BEGIN mode-aware-row-parse
  tab=$'\t'
  row_re="^:([0-7]{6}) ([0-7]{6}) [0-9a-f]+ [0-9a-f]+ ([A-Z][0-9]*)${tab}([^${tab}]+)$"
  [[ "$line" =~ $row_re ]] || emit true                       # GUARD:ROW-GRAMMAR
  om="${BASH_REMATCH[1]}"; nm="${BASH_REMATCH[2]}"; status="${BASH_REMATCH[3]}"; path="${BASH_REMATCH[4]}"
  case "$status" in
    A) [ "$om" = 000000 ] || emit true ;;                      # GUARD:MODE-OLD-ADD
    M) [ "$om" = 100644 ] || emit true ;;                      # GUARD:MODE-OLD-MOD
    *) emit true ;;                                            # GUARD:STATUS
  esac
  [ "$nm" = 100644 ] || emit true                              # GUARD:MODE-NEW
  # END mode-aware-row-parse
```

The existing `case "$path" in` allowlist (three top-level arms, pinned by both suites as "exactly 3") stays byte-for-byte and keeps its 4-space arm indentation (no 4-space comments are added inside it, because the pin counts 4-space lines); the `empty list -> true`, `--enum-failed -> true`, non-PR events -> `true`, and unknown-argv exit 2 behaviours are unchanged. Every `# GUARD:<ID>` tag sits at the end of its own line, and the harness seds anchor on `# GUARD:<ID>$` (the rewritten headers may mention tags in prose). Header comments of both scripts are rewritten: stdin contract is `git diff --raw` rows; the strict-vs-driver divergence and why; the stale "accepted here" paragraph in `ci-shard-totality-classify.sh` is removed. Note on `set -u`: both scripts run under `set -uo pipefail`; a mutant that bypasses the grammar guard must assign `BASH_REMATCH` explicitly, otherwise it crashes on an unbound variable (rc 1) instead of falling through.

### Workflow feed

In `.github/workflows/ci.yml`, in the `Classify shard-totality applicability` and `Classify e2e applicability` steps ONLY, change `git diff --name-status "origin/${GITHUB_BASE_REF}...HEAD"` to `git diff --raw --no-color --no-ext-diff "origin/${GITHUB_BASE_REF}...HEAD"` (stderr stays captured into `$GIT_ERR`; here-string stays; base-ref `git show` stays; fallback literal `APPLICABLE=true` stays). No job-level `if:`/`needs:` line is touched (those are pinned verbatim by `scripts/ci-push-dedupe.test.sh` and `scripts/ci-draft-light.test.sh`). One comment sentence is added per step stating the feed is raw rows and why. `.github/workflows/tenant-integration.yml` mentions the e2e classifier in a comment only (verified: no `classify` invocation there) and is not edited; `scripts/ci-pr-selection.test.sh` names the classifier only as a trigger-list non-member fixture and is not edited.

### Tests (no new suite file)

Rewriting fixtures and extending the three existing suites keeps the shard-totality, orphan-suite and `suite-durations.tsv` gates untouched. Single-sourcing (plan review): the shared machinery lives in ONE suite and loops over BOTH classifiers, because the parse block is byte-identical (Guard 3) and so one mutation of it exercises both.

1. `plugins/soleur/test/ci-e2e-skip-anchors.test.sh`: add the `raw_row <status> <old> <new> <path>` builder (printf with a tab, 7-hex shas) plus `mrow`/`arow`; rewrite every existing `$'M\t...'` fixture through it; add the mode matrix (below); change the pinned diff anchor to the `--raw` spelling; raise its floor (51) to the exact new total (no slack).
2. `plugins/soleur/test/ci-shard-totality-skip.test.sh`: the same builder, fixture rewrite, mode matrix, anchor and exact floor (52 raised); PLUS the single-sourced machinery looping over both scripts: (a) the grammar-derived census, (b) the sed-mutation battery, (c) the byte-parity assertion.
   - (a) Census: a table-driven cross product of statuses {A, M, D, R100, C100, T, U, M99} x old modes x new modes {000000, 100644, 100755, 120000, 160000} on `knowledge-base/a.md`; expected `false` for exactly (A,000000,100644) and (M,100644,100644); a tuple the expectation function does not classify is a failure (red unclassified bucket); the checked count must equal the product of the axis array lengths computed at runtime (not a literal 200), reported as one summary assertion per classifier.
   - (b) Mutation battery on a `mktemp` copy only (never the repo file): a named mutant array whose length is pinned exactly; each mutant is verified to differ from the original (`cmp`), to remain `bash -n` valid, and (for fall-through mutants) to exit 0 on its probe row, otherwise FATAL (a no-op, a syntax break or a crash must never count as RED). The unmutated control passes the full matrix. Mutants are rewrites, not deletions, where deletion fails closed anyway (see Guard 1).
   - (c) Parity: extract the text between `# BEGIN mode-aware-row-parse` and `# END mode-aware-row-parse` from both scripts; assert exactly one marker pair each, non-empty, byte-identical. The classifier list is an array with its count pinned.
3. `plugins/soleur/test/ci-classify-step-exec.test.sh`: the fixture base commit also seeds a root `README.md` (needed by `modeflip`; this changes the base for every mode and is harmless to them); add executed modes `symlink` (added symlinked `.md` under `knowledge-base/`), `execbit` (added exec-bit `.md`), `modeflip` (`M` flipping `100644` to `100755` on root `README.md`) for both jobs, each expecting `applicable=true`; `md` stays `false`; an additional `transition` case runs the step against an embedded frozen copy of the PRE-change classifier as the base-ref copy and expects `true` (R4, no dependence on `origin/main`'s current content). Floor 16 raised to the exact new total.
4. `scripts/lib/test-affected-paths.sh`: add `scripts/ci-e2e-classify.sh` to `AFFECTED_PLUGINS_SOLEUR_TEST_CI_SHARD_TOTALITY_SKIP_TEST_SH_PATHS` ONLY IF the affected-index ratchets (`scripts/test-affected-kb-consumers.test.sh`, `scripts/ci-pr-selection.test.sh`) go red without it; otherwise the file is not touched (the operator forbade index-completion work, and `scripts/lib/**` is on the driver's trigger list).

## Technical Considerations

- **Transition and self-judging.** The classifier a PR is judged by is the BASE ref's copy, and the workflow file is the merge ref's copy. On this PR's own run: new `ci.yml` (raw rows) + old classifier -> first token `:100644` is not `M`/`A` -> `true` (full battery, fail-closed). After merge both are new. A revert reverts both together. The reverse mismatch (new classifier, name-status input) also emits `true`: no row matches the raw grammar.
- **Rename and copy rows.** Default rename detection is kept (as `--name-status` had). A rename row has two tab-separated paths, so it fails the `([^<tab>]+)$` tail and falls to `true`; its status `R100` also fails the status case.
- **Hash width.** The grammar accepts any lower-case hex run, so abbreviated (default) and `--no-abbrev` object names both parse; uppercase hex or a missing field fails closed.
- **Path quoting.** C-quoted paths (control characters) begin with `"` and fail every path-allowlist arm, as before.
- **Fork heads and admin merges.** Unchanged: non-`pull_request` events emit `true` before any row is read.
- **Attack-surface enumeration (security-class fix).** Every route by which a `.md` path can carry non-markdown content past the allowlist: (a) added symlink (`A`, `120000`) — closed by MODE-NEW; (b) file-to-symlink swap (`T`) — closed by STATUS (already); (c) exec-bit flip (`M`, `100644 -> 100755`) — closed by MODE-NEW; (d) exec-bit removal (`M`, `100755 -> 100644`) — closed by MODE-OLD-MOD (the removed file may have been a census subject); (e) gitlink (`160000`) — closed by MODE-NEW; (f) added executable `.md` (`A`, `100755`) — closed by MODE-NEW; (g) `A` row carrying a non-null old mode (malformed) — closed by MODE-OLD-ADD; (h) path in a subtree where an allowed extension is not markdown — unchanged, the three-arm path case.
- **NFR / architecture.** No architectural decision (see Architecture Decision gate below).
- **User-Brand Impact** is in its own section.

## User-Brand Impact

- **If this lands broken, the user experiences:** pull requests whose diffs contain non-markdown content named `*.md` merge with the required `e2e` job (or the shard-totality battery) skipped, i.e. a regression in app code or CI guards reaches `main` with a green required check; the opposite failure (over-strict) only costs the founder CI minutes on a markdown-only pull request that then runs the full job.
- **If this leaks, the user's workflow is exposed via:** a crafted symlinked or executable `.md` in a pull request that the skip verdict does not inspect (the exposure that exists today); no data, credential or customer-facing surface is involved.
- **Brand-survival threshold:** `aggregate pattern`

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Spawned as a blocking Task with the evidence for both forks (ruling R1-R4 above). It confirmed the old classifiers fail closed on raw rows (transition safe), ruled strict modes for both classifiers, ruled against a shared sourced helper because the classifiers run from a base-ref copy at `$RUNNER_TEMP`, and ruled the `ci.yml` classify-step edits are outside the S4 activation path. No other domain is relevant: no UI surface, no user data, no spend, no legal text, no marketing surface. Product/UX Gate: not applicable (no new or modified user-facing page or component).

## Deferrals (tracked)

- **#10415 (Better Stack route for the escape marker).** Tracking issue is #10415 itself (OPEN). Sharpened re-evaluation criteria, observable and tied to the emitter existing; re-evaluate when ANY holds:
  1. `git ls-files plugins/soleur/scripts/ci-full-battery-audit.sh` is non-empty;
  2. `gh issue list --repo jikig-ai/soleur --label ci/full-battery-escape --state all` lists an issue;
  3. a PR that removes the S4 activation lock is opened after a GO recorded on #10448.
  Rule when it fires: the heartbeat Terraform, the emitter and the ping-per-run versus event-webhook semantics decision ship in one PR; a route without an emitter is never built. The comment text (below) is posted to #10415 by the work/ship phase via `gh issue comment 10415 --body-file <file>`; posting a tracking comment is not a production mutation.
- **Re-evaluation of #10416's own boundary.** Revisit the strictness (and whether `docs/**`-style widening is safe) before any widening of a doc-only allowlist, or if either classifier's skip is ever used for a context other than `e2e` or a non-required job. Recorded in the new header comments of both scripts (no new issue: this PR closes #10416 and the boundary is a standing comment, not a deferred capability).

Comment text for #10415 (verbatim, to post at ship):

> Disposition, 2026-10-18 (CTO agent ruling, recorded in the PR for #10416): not built. `SOLEUR_FULL_BATTERY_ESCAPE` has no emitter on main: the PR C audit probe (`plugins/soleur/scripts/ci-full-battery-audit.sh`) and the `ci/full-battery-escape` filing job were never built (ADR-276 PR C amendment, item 4(b), which also supersedes the "named responder" bullet's claim that a Better Stack route is wired). A heartbeat alarms on a missing ping, while the marker is an event that should only ever appear on a bypass merge, so the route's shape depends on the emitter's design. Re-evaluate when any of: (1) `plugins/soleur/scripts/ci-full-battery-audit.sh` exists on main; (2) any issue labelled `ci/full-battery-escape` exists; (3) a PR removing the S4 lock is opened after a GO on #10448. When it fires, the `betteruptime_heartbeat` Terraform, the emitter and the ping-versus-webhook decision ship in one PR; a route without an emitter is never built.

## Architecture Decision (ADR/C4) Gate

Skipped: this PR makes no architectural decision. It conforms two classifiers to the rule ADR-276 "Supersession (2)" already states ("ordinary file modes only") and changes no boundary, substrate or ownership. A competent engineer reading the ADRs and C4 would not be misled after it ships. C4 completeness check for the "no C4 impact" conclusion: read `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` at work time and confirm none models the classifiers or the `git diff` feed (external actors: none new; external systems: none new; data stores: none; actor-surface access: none); run `plugins/soleur/test/c4-count-parity.test.sh` once (it must stay green; no cardinality moves because no workflow, monitor or heartbeat is added).

## Guard Contract

### Guard 1 — both classifiers are mode-aware and fail closed

**Property.** `scripts/ci-e2e-classify.sh` and `scripts/ci-shard-totality-classify.sh` each emit `false` for a `pull_request` only when the changed-file list is non-empty and every row is a well-formed `git diff --raw` row of status `A` (old mode `000000`) or `M` (old mode `100644`), new mode `100644`, on a path their own allowlist admits.

**Assembly.** The chokepoints the property quantifies over, in EACH script: (1) the row-grammar match (`GUARD:ROW-GRAMMAR`), the only door from a stdin line to the verdict; (2) the status case (`GUARD:STATUS`, `GUARD:MODE-OLD-ADD`, `GUARD:MODE-OLD-MOD`); (3) the new-mode test (`GUARD:MODE-NEW`); (4) the three-arm path case (pinned "exactly 3" in each suite); (5) the loop over EVERY stdin row (a check that stops at the first compliant row is the defect class); (6) the empty-list and `--enum-failed` exits; (7) the caller: the matching `Classify … applicability` step in `ci.yml` (Guard 3) that produces the rows and judges by the base-ref copy. The shard-totality allowlist rests on a census fact (it reads `*.sh`/`*.bash` AND shebang files), so the fixtures include an executable `.md` under `knowledge-base/` and at the root. Members are generated from the grammar, not from today's rows.

**Mutation matrix:**

| # | Mutation (applied to a mktemp copy, per classifier) | Expected |
|---|---|---|
| 1 | delete the `# GUARD:MODE-NEW$` line (symlink, gitlink, executable new modes now pass) | RED (120000, 160000, 100755 new-mode fixtures) |
| 2 | rewrite the `MODE-OLD-MOD` arm to `M) ;;` and the `MODE-OLD-ADD` arm to `A) ;;` (each separately; deleting the arm would fall to the closing `*) emit true` and stay fail-closed, so it is NOT a valid mutant) | RED each (exec-bit-removal `M`; non-null-old `A`) |
| 3 | rewrite `[ "$nm" = 100644 ]` as `[[ "$nm" == 100[67]* ]]` (widened toward the driver's `100755`) | RED |
| 4 | make a non-matching line fall through as an ordinary modified file: replace `|| emit true` on the `ROW-GRAMMAR` line with `|| BASH_REMATCH=(z 100644 100644 M "$line")` (a bare deletion crashes under `set -u` with rc 1 and would be RED for the wrong reason; the harness asserts the mutant exits 0 on its probe) | RED (legacy name-status and bare-path rows pass) |
| 5 | dispatch row: delete the `[ "$saw_any" -eq 1 ] \|\| emit true` line (empty stdin must be `true`; a classifier that checked nothing and printed `false` is vacuous) | RED |
| 6 | read only the first row: insert `break` before the loop's closing `done` with `sed '/^done$/i\  break'` (the matrix has a compliant first row followed by a symlink second row, and the reverse) | RED |
| 7 | rewrite the `GUARD:STATUS` arm to `*) ;;` (D, R, C, T, U, M99 fall through; D/T/U are also stopped by MODE-NEW, so R, C and M99 are the rows that expose it) | RED via R100, C100 and M99 tuples |
| 8 | add a fourth top-level arm to the path case | RED via the existing "exactly 3" pin |
| 9 | CENSUS row, derived from the grammar not from today's rows (see Tests 2a): any mutant that opens a third `false` tuple | RED (unclassified tuple is a failure) |

**Harness rows.** (a) Edit the SUITE: make `expect_verdict` compare nothing (always pass) -> the instrument self-test and the control row (the unmutated copy must pass the matrix, and the matrix must contain at least one `false` and one `true` expectation) go RED. (b) Must-PASS inputs that are NOT the canonical: a plain `100644` `.md` with a path containing spaces, a 40-hex `--no-abbrev` row, an `A` + `000000` row at a deep `knowledge-base/a/b/c.md`, and a root `README.md` `M 100644 100644`, all `false` (a classifier that rejects everything is caught). (c) Each mutant is verified to change the file (`cmp`), to stay `bash -n` valid and, for fall-through mutants, to exit 0 on the probe; otherwise the harness aborts FATAL.

**Anchor.** The matrix floor is a `>= N` count; the suites set it to the exact total (no slack) and the mutant list is a named array whose length is pinned exactly, so replacing a mutant with a weaker one at equal N changes a printed id and the pinned list. Outside the commit: the BASE-ref copy of each classifier judges every PR (including the one that edits it), so a weakening PR cannot change its own verdict; the suites are edited in the same diff and prove consistency, not integrity - base-ref judging is the integrity anchor, and `scripts/` review ownership is the human anchor. This limit is stated, not hidden.

### Guard 2 — the two duplicated parse blocks are identical

**Property.** The text between `# BEGIN mode-aware-row-parse` and `# END mode-aware-row-parse` is byte-identical in both classifiers.

**Assembly.** Both scripts, exactly one marker pair each, checked from one suite (`ci-shard-totality-skip.test.sh`), because there is no shared helper by ruling R3. Chokepoint: the marker pair; a third classifier added later is out of reach and must be added to the pinned classifier array.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | edit one literal inside the block in ONE script only | RED |
| 2 | delete the END marker in one script (an unbounded extraction would compare to end-of-file) | RED (marker-count and non-empty checks) |
| 3 | add a second marker pair to one script after a compliant first | RED (exactly one pair per script) |
| 4 | point the extraction at a file that lacks both markers (0 checked) | RED (non-empty extraction; dispatch row) |

**Harness rows.** Suite edit: replace the comparison with `true` -> the assertion's own mutant (copy both scripts to a temp dir, perturb one) must go RED. Must-PASS non-canonical: temp copies whose header comment OUTSIDE the markers differs must still pass.

**Anchor.** Nothing outside the commit holds this: one diff can edit both copies equally, which is fine (the property is parity, not content). Content integrity is Guard 1.

### Guard 3 — the workflow feed matches the classifier contract (executed)

**Property.** The `Classify … applicability` run-blocks extracted from `ci.yml` and executed against a real git repository emit `applicable=true` for an added symlinked `.md`, an added executable `.md` and a `100644 -> 100755` flip, and `applicable=false` for a plain markdown-only diff.

**Assembly.** Both classify steps (extracted by PyYAML, not regex); both classifiers; the real `git diff --raw` output (modes come from git, not a hand-written fixture; this also proves the fixture builder emits what git emits), including the base-ref `git show` copy and the transition case (frozen pre-change classifier as base copy).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | in a temp copy of `ci.yml`, change `--raw` back to `--name-status` in the e2e step | RED (the new classifier gets no matching rows, so the plain `md` case turns `true`; the pinned diff anchor also fails) |
| 2 | same for the shard-totality step only (second member after a compliant first) | RED |
| 3 | make the classifier a stub that always prints `false` | RED (the new mode cases) |
| 4 | the harness case list loses the `symlink` mode | RED via the raised exact floor |

**Harness rows.** Suite edit: drop failure propagation from the executed step wrapper -> the `rc` check must red. Must-PASS non-canonical: root `README.md` `M 100644 100644` and a `knowledge-base/deep/x.md` `A` (differing from the canonical `knowledge-base/a.md`).

**Anchor.** The executed run uses the checked-in classifier copied into the fixture's base commit, so the test judges the same bytes CI would; the base-ref-judging pin (`git show "origin/${GITHUB_BASE_REF}:scripts/..."`) stays in the anchor suites.

## Implementation Phases

Phase 1 - RED tests first (`cq-write-failing-tests-before`). In the three suites: add the row builder, rewrite fixtures to raw rows, add the mode matrix, and in `ci-shard-totality-skip.test.sh` the census, mutation battery and parity assertion; in `ci-classify-step-exec.test.sh` the executed modes. Run the suites against the UNCHANGED classifiers/workflow: the new mode fixtures must FAIL (symlink/exec cases emit `false` today) and the rewritten legacy-skip cases must fail on grammar. Record the failing counts.

Phase 2 - Classifier edits. `scripts/ci-e2e-classify.sh`, `scripts/ci-shard-totality-classify.sh`: row-parse block with markers and `# GUARD:` tags, header rewrite. Suites go green.

Phase 3 - Workflow feed. Two `ci.yml` step edits (diff command + one comment sentence each). Update the pinned diff anchors. Executed suite goes green.

Phase 4 - Ratchets. Run `bash scripts/ci-pr-selection.test.sh`, `bash scripts/ci-push-dedupe.test.sh`, `bash scripts/ci-draft-light.test.sh`, `bash plugins/soleur/test/c4-count-parity.test.sh`, `bash scripts/guard-vacuity-floor.test.sh`, the affected-index ratchets and the repo-global ratchets named in the 2026-10-14 learning; add the one edge path only if a ratchet demands it (Tests item 4). Confirm `git diff origin/main --stat` shows no change to `scripts/required-checks.txt`, `scripts/ci-pr-selection.sh`, `scripts/ci-pr-affected-preactivation.sh`, `scripts/ci-pr-affected-replay.py` or the two `plugins/soleur/test/ci-pr-affected-*.test.sh` suites.

Phase 5 - Replay and records. Run the AC9 replay once locally; simulate the rollback (AC14); post the #10415 comment; ensure `soleur:ship` renders the PR body with `Closes #10416`, `Ref #10415`, `Ref #9729`, a `## Changelog` section and the transition note.

## Files to Edit

- `scripts/ci-e2e-classify.sh`
- `scripts/ci-shard-totality-classify.sh`
- `.github/workflows/ci.yml` (the two classify steps only)
- `plugins/soleur/test/ci-e2e-skip-anchors.test.sh`
- `plugins/soleur/test/ci-shard-totality-skip.test.sh`
- `plugins/soleur/test/ci-classify-step-exec.test.sh`
- `scripts/lib/test-affected-paths.sh` (CONDITIONAL: one path added to one array only if an affected-index ratchet demands it)

## Files to Create

- None in the product tree (no new suite, so no shard/duration/orphan registration). Planning artifacts only: this plan, `knowledge-base/project/specs/feat-one-shot-10415-10416-s4-followups/tasks.md`, `.../decision-challenges.md`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Implement #10415 and #10416 in ONE PR" | Overview; Decisions R1 (#10415 deferred by CTO ruling) and R2-R4 (#10416 built) | mapped (one PR; #10415 part is a recorded ruling plus a posted disposition, because the CTO ruled it out of scope now, as the brief instructed to spawn the CTO to decide) |
| 2 | "#10415: route SOLEUR_FULL_BATTERY_ESCAPE to a Better Stack heartbeat" | Deferrals section; R1 | descoped - justification: CTO ruling R1 (no emitter exists; dead surface; secrets are production-mutating) |
| 3 | "#10416: fix the mode-blind sibling classifiers (scripts ci-e2e-classify.sh and ci-shard-totality-classify.sh) that treat a symlinked or executable .md as doc-only" | Proposed Solution; Guards 1-3; Phases 1-3 | mapped |
| 4 | "do NOT do #10414 (per-suite selection, gated on index completion) and do NOT start any index-completion work" | Hard constraints paragraph; Phase 4 note on the single edge-array path | mapped |
| 5 | "Reference #9729 with \"Ref #9729\" only, never Closes/Fixes/Resolves; use \"Closes #10415\" and \"Closes #10416\" in the PR body for the two items this PR completes" | Phase 5 (PR body: `Closes #10416`, `Ref #10415`, `Ref #9729`) | mapped (the brief's own rule: "If the CTO rules #10415 should be deferred ... use \"Ref #10415\"") |
| 6 | "do not flip CI_PR_AFFECTED, do not remove the lock, and do not change the activation state; leave scripts/required-checks.txt and the S4 activation path unchanged" | Phase 4 verification command; AC7 | mapped |
| 7 | "Do not commit an author or committer identity of s@example.invalid" | Phase 5 / AC8 | mapped |
| 8 | "Existing suites ci-pr-affected-preactivation.test.sh and ci-pr-affected-replay.test.sh have assertion/mutant floors — do not lower them" | Overview (not edited); AC7 | mapped |
| 9 | "Start from origin/main at 840dc667fc" | Branch base; Research Insights | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Strict modes (A: 000000->100644, M: 100644->100644) in both classifiers | "treat a symlinked or executable .md as doc-only" | asked |
| `--raw` feed in the two ci.yml classify steps | "Align the two classifiers with the PR B driver's mode-aware positive allowlist" | asked (no other source of modes exists in `--name-status`) |
| Duplicated block + parity guard | "fix the mode-blind sibling classifiers" | inferred - justification: the CTO ruled out a shared helper (base-ref copy has no `scripts/lib`), so two copies need a drift guard |
| `scripts/lib/test-affected-paths.sh` one-path edge (conditional) | "do NOT start any index-completion work" | inferred - justification: the shared machinery makes `ci-shard-totality-skip.test.sh` read a second file; the edge is added only if a ratchet demands it, and is then maintenance of the touched suite's own entry, not index completion |
| Mutation batteries in the existing suites | "fix the mode-blind sibling classifiers" | inferred - justification: Guard Contract gate (plan Phase 2.12) requires a mutation matrix for a guard deliverable |
| #10415 disposition comment text | "records the ruling and the sharpened re-evaluation criteria for #10415" (brief, if deferred) | asked |
| Raised assertion floors | "have assertion/mutant floors — do not lower them" | asked (applies to the same discipline for the touched suites) |

### Split Assessment

- Subsystems touched: 3 - `scripts/`, `.github/workflows/`, `plugins/soleur/test/`
- Planned files: 7 edited, 0 created | Estimated changed lines: ~450 (about 80 production, about 370 fixtures and batteries)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1. Both classifiers emit `true` for each of: added `120000` `.md`, added `100755` `.md`, added `160000`, `M` with `100644 -> 100755`, `M` with `100755 -> 100644`, `A` with a non-`000000` old mode, `T`, `R100`, `C`, `D`, legacy name-status row, bare path, uppercase-hex row, row with a missing tab, empty input. Located in the mode matrices of `plugins/soleur/test/ci-e2e-skip-anchors.test.sh` and `plugins/soleur/test/ci-shard-totality-skip.test.sh`; verified by running each suite.
- [ ] AC2. Both classifiers emit `false` for plain `100644` markdown-only diffs: `A 000000->100644` and `M 100644->100644`, including a path with spaces, a deep `knowledge-base/a/b/c.md`, a root `README.md`, and a 40-hex `--no-abbrev` row. Same suites.
- [ ] AC3. The mode gate sits in a block delimited by `# BEGIN mode-aware-row-parse` / `# END mode-aware-row-parse` in `scripts/ci-e2e-classify.sh` and `scripts/ci-shard-totality-classify.sh`; the two blocks are byte-identical; the parity assertion lives in `plugins/soleur/test/ci-shard-totality-skip.test.sh`.
- [ ] AC4. The `Classify e2e applicability` and `Classify shard-totality applicability` steps of `.github/workflows/ci.yml` use `git diff --raw --no-color --no-ext-diff "origin/${GITHUB_BASE_REF}...HEAD"`; the literal `git diff --name-status` no longer appears in either step (`git grep -n 'git diff --name-status' .github/workflows/ci.yml` shows no hit inside them; prose comments may still say "name-status" when contrasting the old feed); the pinned anchors in both anchor suites use the `--raw` spelling; no job-level `if:`/`needs:` line changed (`git diff origin/main -- .github/workflows/ci.yml` shows hunks only inside the two steps).
- [ ] AC5. `plugins/soleur/test/ci-classify-step-exec.test.sh` executes, against real git fixtures (base commit seeds a root `README.md`), the `symlink`, `execbit` and `modeflip` modes for both jobs with `applicable=true`, a `transition` case (frozen pre-change classifier as the base-ref copy) with `applicable=true`, and the plain `md` mode still `applicable=false`; floor raised from 16 to the new exact count.
- [ ] AC6. `plugins/soleur/test/ci-shard-totality-skip.test.sh` holds the single-sourced machinery for BOTH classifiers: the grammar-derived census (checked count equals the product of the axis array lengths computed at runtime, one summary assertion per classifier, a tuple the expectation does not classify fails), the mutation battery (named mutant array with exactly-pinned length; each mutant `cmp`-differs, passes `bash -n`, fall-through mutants exit 0 on their probe; unmutated control passes) and the parity assertion; assertion floors of all three suites (51, 52, 16) are raised to their exact new totals, never lowered; each suite prints its total.
- [ ] AC7. `git diff origin/main --stat` shows no change to `scripts/required-checks.txt`, `scripts/ci-pr-selection.sh`, `scripts/ci-pr-affected-preactivation.sh`, `scripts/ci-pr-affected-replay.py`, `plugins/soleur/test/ci-pr-affected-preactivation.test.sh`, `plugins/soleur/test/ci-pr-affected-replay.test.sh`, or any ADR file, and the lever literals are untouched (`git grep -c 'CI_PR_AFFECTED' -- .github scripts plugins` per-file counts identical between `origin/main` and the branch).
- [ ] AC8. `git log origin/main..HEAD --format='%an <%ae> | %cn <%ce>'` contains no `s@example.invalid`; the configured identity is used.
- [ ] AC9. Replay (no regression of the saving): for the 30 most recent first-parent commits of `origin/main` whose changed paths are all `*.md`, compare the new classifier fed `git diff --raw --no-color --no-ext-diff <c>^1 <c>` with the pre-change classifier (`git show origin/main:scripts/ci-e2e-classify.sh` written to a temp file BEFORE the branch's edit lands in the worktree copy) fed `git diff --name-status <c>^1 <c>`; the verdicts must be equal for every commit that has no non-`100644` mode; a one-sentence result goes in the PR body. Local git only, no network.
- [ ] AC10. `bash scripts/ci-pr-selection.test.sh`, `bash scripts/ci-push-dedupe.test.sh`, `bash scripts/ci-draft-light.test.sh`, the three edited suites, `bash plugins/soleur/test/c4-count-parity.test.sh`, and the affected-index / guard-vacuity ratchets pass.
- [ ] AC11. The PR body (authored by `soleur:ship` Phase 6, which full-replaces it from the diff and from `decision-challenges.md`; `work` and `plan` do not write it) carries: `Closes #10416`, `Ref #10415`, `Ref #9729`, a `## Changelog` section, and one sentence that this PR's own `e2e` and `shard-totality-mutations` run the full job because the base-ref classifier fails closed on the new feed (R4). It does not contain `Closes #10415`.
- [ ] AC12. The #10415 disposition comment (text in Deferrals) is posted with `gh issue comment 10415`; `gh issue view 10415 --json state` stays `OPEN`.
- [ ] AC13. `python3 scripts/lint-guard-contract.py` passes on this plan (3 entries, each with at least 3 matrix rows).
- [ ] AC14. Rollback simulated at work time: in a scratch detached worktree, `git revert --no-commit` of the change commits followed by the three edited suites exits 0.

## Test Scenarios

- Given an `A` row `:000000 120000 ... A\tknowledge-base/x.md` (symlink), when either classifier runs for `pull_request`, then it emits `true` (unit).
- Given an `A` row `:000000 100755 ... A\tknowledge-base/x.md`, when classified, then `true` (unit).
- Given `:100644 100755 ... M\tREADME.md`, when classified, then `true` (unit).
- Given `:100755 100644 ... M\tknowledge-base/x.md`, when classified, then `true` (unit).
- Given `:000000 100644 ... A\tknowledge-base/a.md` then `:100644 100644 ... M\tREADME.md`, when classified, then `false`; reversed order also `false` (unit).
- Given a compliant first row followed by a symlinked `.md`, when classified, then `true`; reversed order `true` (unit).
- Given the grammar-derived cross product of 8 statuses x 5 old modes x 5 new modes, when classified, then exactly two tuples give `false` and the checked count equals the product of the axis lengths (unit; census).
- Given legacy `M\tknowledge-base/a.md`, a bare path, or an uppercase-hex raw row, when classified, then `true` (unit).
- Given a real two-commit git fixture whose PR adds a symlinked `.md`, when the extracted `ci.yml` step is executed under `bash --noprofile --norc -eo pipefail`, then `applicable=true` (integration).
- Given the same fixture with a plain `.md`, then `applicable=false` (integration).
- Given a base ref lacking `origin/<base>` (shallow), then the fallback is `true` with the measured-cause warning (integration; existing case, unchanged).
- Given each sed mutant of a classifier copy, then the matrix goes RED and the mutant is `bash -n` valid and differs from the original (unit; mutation battery).
- Regression (transition, R4): given an embedded frozen copy of the PRE-change classifier as the base-ref copy and a raw-row feed from real git, when the extracted step runs, then `applicable=true` (integration; lives in `ci-classify-step-exec.test.sh`, not in the anchors suite, which uses no git fixture repos).

## Observability

Not triggered as a new surface (Files to Edit are CI scripts and tests, outside the application/infra/plugin-script paths of the gate). The existing run-visible signal is unchanged: each classify step emits `::notice::e2e applicable=<verdict> (event=<event>)` and `::notice::shard-totality applicable=<verdict> ...` and, on a fallback, a `::warning::` that names the measured cause. A mode-driven `true` is deliberately not given a new reason channel (Cut List: not asked, and the verdict line plus the diff already identify the offending row).

## Rollback

Revert the merge commit: it restores the old classifiers AND the `--name-status` feed together, so there is no mixed state. The recipe is simulated before the plan is final, at work time: in a scratch detached worktree run `git revert --no-commit <change commits>` and then the three edited suites plus `bash scripts/ci-push-dedupe.test.sh` and `bash scripts/ci-draft-light.test.sh`; the recipe is written from what that run needs (AC14). No variable, ruleset or secret participates, so there is nothing to un-set.

## Dependencies & Risks

- **Fixture churn** (about 90 existing rows rewritten): mitigated by a single row builder per suite and by running Phase 1 RED first.
- **A missed raw-format edge** shows up as unnecessary full runs (the safe direction); AC9 measures it on real history before merge.
- **Self-judging transition**: this PR's own run is a full run by design (R4).
- **`#7390`** (stale WIP) edits `ci.yml` elsewhere; textual conflict only if revived.
- **Pre-existing flake** `scripts/test-all-orphan-log-retention` can redden a queue run unrelated to this change (noted in #10448); do not read it as caused by this PR.
- **No production mutation** anywhere in this plan: nothing applies Terraform, creates secrets, flips a variable, or changes a ruleset.

## References & Research

- Issues: #10416, #10415, #10414, #10448, #9729; ADR-276 (`knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md`, PR B amendment "Supersession (2)", PR C amendment items 3-4).
- Driver precedent: `scripts/ci-pr-selection.sh` stage 1 (`GUARD:G2-MODE-OLD`, `GUARD:G2-MODE-NEW`).
- Decision record: `knowledge-base/project/specs/feat-one-shot-10415-10416-s4-followups/decision-challenges.md`.
