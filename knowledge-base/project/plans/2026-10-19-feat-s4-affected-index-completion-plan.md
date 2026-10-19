---
title: "feat: complete the S4 affected index and ratchet it (Ref #9729, #10448 option i)"
date: 2026-10-19
slug: s4-affected-index-completion
branch: feat-one-shot-s4-affected-index-completion
issue: 10448
lane: cross-domain
type: feat
brand_survival_threshold: none
---

# feat: complete the S4 affected index and ratchet it

Spec lacks valid `lane:` (no spec.md exists for this branch): defaulted to `cross-domain` (fail-closed). All PR text says `Ref #9729` and `Ref #10448`; nothing in this work uses a closing keyword.

## Overview

The S4 stage of the CI cost work (Ref #9729) measured a NO-GO on index completeness: registered test suites
read repository paths that the affected index does not declare for them. The budget owner funded option (i)
of #10448 on 2026-10-19: bring the audit (`python3 scripts/ci-pr-affected-replay.py audit`) to a clean exit
(`gap_suites=0`, `unaudited=0`, every remaining row carrying a `false-positive:` reason in the census style),
and make a ratchet that fails when a suite names an undeclared tracked path a required CI check. The lever stays
dark. Flipping `CI_PR_AFFECTED`, removing the lock, PR D (#10414), the replay re-run and the go/no-go re-ruling are
NOT part of this plan; they are a later gate that starts after the audit is 0 and the ratchet is required.

The work is five PRs (a sixth is conditional), in the order the CTO ruled on 2026-10-19 in two rounds (see
`## Technical Rulings`): a cost spike and a fast, total audit; the ratchet landed early as a shrink-only baseline; the
heavy-tail drain; the remainder with the baseline deleted so the ratchet is strict zero; and, only if measured to be
worth it, a separate precision PR.

## Live Re-measurement (the number to use)

Measured 2026-10-19 on this worktree (clean tree at `c5fded35cc`, main plus the branch-init commit):
`time python3 scripts/ci-pr-affected-replay.py audit --all-refs` took 5m28s (real) and printed

`SOLEUR_PR_AFFECTED_AUDIT suites=643 always_on=116 audited=526 unaudited=1 gap_suites=195 gap_refs=1108 accepted=0`

| Source | Gap suites | Suites | Note |
|---|---|---|---|
| Issue #10448 body | 145 | 630 | first receipt version; read only part of the suites, a floor (a measurement-version change, not drift) |
| CTO verdict / corrected receipt | 190 | 630 | pinned tree `abbd36a696` |
| Live today | **195** | **643** | the number every PR below reports. Only 190 to 195 (630 to 643 suites) is real drift, but it is drift in the wrong direction while the drain runs, which is why the ratchet lands before the drain finishes |

Shape of the 1,108 references (tallied from the output): median 2 refs per suite and 144 of 195 suites have 3 or fewer;
heavy tail `scripts/test-affected-derive` 483, `.claude/hooks/grep-q-pipe-guard.test.sh` 52,
`scripts/test-all-infra-coverage-notice` 35, `scripts/ci-pr-selection` 22, `tests/scripts/scratch-residue` 19 (about
611 refs in five suites). Most frequent paths: `README.md` 40 suites, `AGENTS.md` 16, `AGENTS.rules.md` 14,
`.claude/settings.json` 14, `package.json` 13, `.gitignore` 12, `.github/workflows/ci.yml` 12,
`scripts/betterstack-query.sh` 10. The one unaudited suite is the directory suite `plugins/soleur` (`^plugins/soleur/`);
the 1,108 figure EXCLUDES the references the directory-suite scan will add (about 315 test files), so PR1 reports the
new total and a re-split trigger (see PR1 step 4).

## Research Reconciliation: Spec vs. Codebase

| Claim in the brief / issue | Reality on main | Plan response |
|---|---|---|
| "145 of 630" (issue) vs "190 of 630" (CTO) | live audit: 195 of 643 | use 195 / 643; each PR re-measures on its own tree |
| "add a ratchet as a required CI check ... adding a new required check needs the usual ruleset path" | `test` is already a required context and runs `scripts/test-all.sh`; a new context needs `required-checks.txt`, the canonical JSON, `infra/github/ruleset-ci-required.tf`, pins in `ci-push-dedupe.test.sh` and `ci-draft-light.test.sh`, and a bot-PR synthetic green that the file header forbids for content-scoped gates | CTO ruling 3(i): the ratchet is an always-on suite inside `test`; `scripts/required-checks.txt` is untouched; a separately named context stays a follow-up PR if the owner asks for one |
| "any remaining row needs a human-written `false-positive:` reason" | `--accept` TSV supports `false-positive:` rows; there is no accept file in the repo yet | anchor-keyed accept TSV (CTO round 2, C); reasons are drafted from the line context by the agent and reviewed in the PR; Ask 1 is therefore `adapted`, and PR1's text raises it on #10448 (decision-challenges.md row 9) |
| the audit is quick enough to gate | 5m28s: the substring scan is 39s (643 suites x 19,363 tracked files), the rest is the `--print-selection` subprocess; CI has no derive-cache restore step (ADR-276 item 4(e)), so the selector runs cold (receipts: cold 146 s); `scripts/test-affected-kb-consumers` already walks `--print-selection` inside `test-all.sh` at 91 s (`scripts/suite-durations.tsv`) | CTO round 2 A: accept a cold ceiling of 180 s billed per full-battery run with a 300 s suite timeout; spike it first (PR1 step 0) |
| "unaudited=0" | the directory suite `plugins/soleur` is unaudited; ADR-276 item 5 (2026-10-16) says it "needs a `*` row" | CTO 4 + round 2 F(2): audit its test files; the PR3 amendment supersedes that clause by subject |
| nested selector call from a suite is unverified | `scripts/test-affected-kb-consumers.test.sh` already does a `--print-selection` walk inside a suite, so recursion safety is established | only the cost is open (spike in PR1 step 0) |
| PR #10389 touches the affected area | its 22 files are the plugin-generic gate (`plugins/soleur/scripts/affected-tests.sh`, `lib/affected-tests/*`, ADR-288 file, skills, `.soleur-test-gate.json`) | no overlap with any planned file (checked with `gh pr view 10389 --json files`); see `## Sibling PR Overlap` |

## Research Insights

**Premise Validation.** Checked: #10448 is open and carries the owner decision comment of 2026-10-19 (option i, scope as briefed, lever stays dark); #9729 is open; PR #10412 (evidence PR) merged 2026-10-16 and its receipts are under `knowledge-base/project/specs/archive/20261016-210509-feat-one-shot-9729-ci-pr-c-affected-only/receipts/`; PR #10389 is an open draft with no file overlap. The cited command exists on main (`scripts/ci-pr-affected-replay.py` `cmd_audit`, `--accept`, `--all-refs`, `--list`, `--root`). Held: all of the above. Stale: the 145 and 190 figures (live is 195 of 643). ADR corpus: ADR-276 amendment item 5 (2026-10-16) is the entry condition this plan implements; ADR-290 (shrink-only ratchet keyed on file/rule/anchor) is the pattern the ratchet reuses (its `resolve_base` and `baseline_at` in `scripts/lint-ratchet.py` are reused, not reimplemented); neither lists the chosen mechanism among rejected alternatives. Open code-review issues: see `## Open Code-Review Overlap`.

**Property List.**
1. P1: the audit exits 0 on main: every tracked path a registered suite names is declared for that suite, covered by the runner trigger, or carries a `false-positive:` reason.
2. P2: a suite that newly names an undeclared tracked path fails a required merge check before it lands.
3. P3: the check costs at most the CTO ceiling (180 s billed per full-battery run cold, 300 s suite timeout).
4. P4: a false-positive reason cannot rot silently (stale or anchor-mismatched rows fail) and cannot exempt a NEW reading line without a diff a reviewer sees.
5. P5: the dark lever, the lock, `CI_PR_AFFECTED` and PR D are untouched.

**Cut List** (mechanism -> property -> what already covers it):
- A new required CI job and context -> P2 -> the required `test` aggregator already runs `test-all.sh` on `pull_request` and `merge_group` (CTO 3(i)).
- A generated manifest or per-suite header declarations -> P1 -> the 177 `AFFECTED_*_PATHS` arrays are the selector's authority (`edge_hit`); a second source would drift (CTO 1).
- A second ratchet script re-implementing the audit -> P2 -> a `ratchet` subcommand of the existing script shares `suite_refs`/`edge_hit`; one implementation.
- Using the inotify recorder as a CI gate -> P2 -> it is operator-run, Linux-only and cannot prove a read never happens; it stays a positive oracle (CTO 2).
- Blanket `README.md`/`AGENTS.md` edges on all 40/16 suites -> P1 -> declare only where the line context shows a real read (CTO 2).
- Excluding heredoc/`printf` fixture writes in the audit -> P1 -> lexically unsound (CTO 2).
- `*` accept row for `plugins/soleur` -> P1 -> the audit reads the directory suite's test files instead (CTO 4); the ratchet rejects `*` rows.
- Symlink and parent-symlink refusals on the baseline -> P2 -> baseline equality with the live gap set already makes the file unforgeable; no threat model at threshold `none` (CTO round 2 D, dropped from the ADR-290 carry-over).
- 90%-of-live-count floors -> P2 -> rot on legitimate shrinkage; replaced by structural floors (CTO round 2 E).
- A permanent copy of the old `f in blob` scan in the suite -> P3 -> a pinned-tree differential receipt in PR1 is the proof for a pure-function change; the 39 s scan must not live in CI.
- Value-proposition re-measurement of the saving (0.6c) -> not needed: the saving (51.58 suite-minutes per full-battery commit) was measured by #10412's receipts and is the later gate's concern; the new measurements here are the audit wall time (5m28s, `time python3 scripts/ci-pr-affected-replay.py audit`) and the cold ratchet cost (PR1 step 0).

**Mechanics (file anchors by content).**
- Index: per-label bash arrays `AFFECTED_<LABEL>_PATHS` in `scripts/lib/test-affected-paths.sh` (177 today); entries are a literal path, an anchored `dir/` prefix, or `glob:<head>/<tail>`; `ALWAYS_ON_SUITES` holds always-on labels. Consumer: `_affected_classify` in `scripts/test-all.sh` (precedence group, always_on, consumed, declared, derived, unclassified). Editing that file degrades a PR to the full battery (`runner-changed`) except for a registration-only diff.
- Audit: `cmd_audit`, `suite_refs` (`f in blob` over every tracked path, comments stripped, one `source` hop), `edge_hit`, `load_accept` in `scripts/ci-pr-affected-replay.py`; selector rows are `AFFECTED_SELECTED<TAB>label<TAB>sel<TAB>class<TAB>edges|...` from `test-all.sh --print-selection`; `main()` maps `ReadError` to 3 and an uncaught error to 4.
- Tests: `plugins/soleur/test/ci-pr-affected-replay.test.sh` (946 lines; fixtures via `--list`, mutation rows copy the SUT and apply one edit, anti-vacuity floors), registered by the `plugins/soleur/test/*.test.sh` glob and listed in `scripts/suite-shard-legs.tsv` and `scripts/suite-durations.tsv`.
- Census-style precedent: `scripts/test-affected-kb-consumers.baseline.txt` (4-column `label<TAB>path<TAB>class<TAB>false-positive: <one sentence naming the mechanism>`).
- Recorder: `scripts/audit-suite-reads.sh record --mode check --cover-from-selection` (operator tooling) gives observed OPEN events per suite.
- `test-scripts` and heavy jobs check out with `fetch-depth: 0` (`ci.yml`), and `lint-ratchet-ruff-live` already relies on merge-base resolution on `merge_group`, so `git show origin/main:<baseline>` is available to the suite.

**Institutional learnings applied** (from `knowledge-base/project/learnings/`):
- `2026-10-05-registering-a-suite-is-itself-a-runner-edit.md`: the ratchet suite's `run_suite` line must fit the closed-grammar registration-only shape; register by exact file, never by glob (`2026-10-14-my-stubs-checked-the-shape-of-argv-and-never-the-value-and-a-glob-registered-suite-degrades-the-affected-gate.md`).
- `workflow-issues/2026-10-10-a-declared-edge-must-say-what-the-walker-reads-and-a-malformed-one-must-fail-wide.md`: malformed declared edges already mint always-match edges and the census linter flags them; this plan does not add a second validator.
- `test-failures/2026-10-14-a-mutation-row-is-vacuous-until-a-fixture-distinguishes-the-mutant.md`: mutation rows need injected synthetic census state or a scratch repo, with `GIT_CEILING_DIRECTORIES` set (`test-failures/2026-10-13-home-git-repo-makes-ratchet-nonrepo-control-walk-up.md`).
- `2026-07-23-ci-guard-test-must-assert-enforcement-not-just-presence.md`: each guard gets a behavioural mutation proof, not a line-presence pin.
- `best-practices/2026-10-10-env-gated-suite-dormancy-is-a-conjunction-not-a-wiring-check.md`: census floors plus a mutation battery are the anti-vacuity shape.
- `2026-05-11-multi-word-required-check-exposes-strip-all-whitespace-bug.md` and `2026-03-20-github-required-checks-skip-ci-synthetic-status.md`: the reason a new required context is avoided (CTO 3(i)).

## Technical Rulings

All technical forks were ruled by the CTO agent on 2026-10-19 in two rounds (each spawned with "do NOT use AskUserQuestion"); the rows are persisted in `knowledge-base/project/specs/feat-one-shot-s4-affected-index-completion/decision-challenges.md`. One row (11) is closed by the PR1 step 0 spike rather than by a ruling. Summary:

1. Index format: keep the per-label arrays; the false-positive census is a committed TSV `scripts/ci-pr-affected-audit.accept.tsv`, created by the first PR that needs a row (a missing file means no exemptions), read through the existing `--accept` flag. Rows are anchor-keyed: `suite<TAB>path<TAB>anchor<TAB>ordinal<TAB>false-positive: <reason>`, anchor = first 12 hex of sha256 of the whitespace-normalised source line (ADR-290 style); a (suite, path) pair is accepted only when every boundary-match line is accepted; a row whose anchor matches no live line is stale and fails.
2. Mentions, fixture writes, strings: classify each pair from its line context. Real reads become declared edges; a `false-positive:` row only when the class is mechanically clear (message string, path written into a scratch fixture never read back from the real repo, negative-test fixture content); unclear means declare. Doc-class paths are declared only for suites that really read them.
3. Match definition (round 2 B): byte-identical output to the old scan is NOT required. A match is a substring that starts at a path-component boundary (run start or the character after `/`), enumerated component by component against a prefix set of tracked paths, with per-file memoisation across suites. A committed differential must show every dropped ref on the pinned tree has a mid-component start, and the recorder must observe none of them opened. A throwaway prototype timing comes before the design is committed (target 30 s or less for the scan on the pinned tree). If memoisation alone meets the target, the left/right boundary rule moves to a separate conditional precision PR that runs only if PR1's dry run shows it drops at least 30 gap pairs; otherwise those pairs are accept rows.
4. Ratchet: an always-on suite inside the required `test` context; shrink-only baseline of `(suite, path)` pairs during the drain; an absent baseline means strict zero, except at the bootstrap PR, so the last drain PR deletes the file and the ratchet then requires an empty live set. Cost ceiling: at most 180 s billed per full-battery run cold, 300 s suite timeout; the ratchet gets its own leg in `scripts/suite-shard-legs.tsv`; if the cold run exceeds the ceiling the ratchet takes `--rows FILE` with one walk shared inside one leg. Not folded into the `test-affected-kb-consumers` walk.
5. Baseline integrity: copy ADR-290's merge-base rule exactly (under `CI` a baseline missing at the merge base is accepted only when the script at the merge base does not yet define the scope, keyed on a pinned constant `RATCHET_BASELINE`), reusing `resolve_base` and `baseline_at` from `scripts/lint-ratchet.py`; per suite the baseline never grows versus the merge base and a suite absent there cannot appear; refuse duplicate lines and unsorted input (one sorted pair per line); no symlink refusals.
6. Floors are structural: the selector's `AFFECTED_SUMMARY` total equals the count of rows it printed, `fallback=none`, suite / audited-suite / tracked-file counts nonzero, tracked-file count equals `git ls-files`, and a planted control suite is flagged. Exit codes: 0 clean, 1 drift or vacuity, 2 infrastructure (a `ReadError` and any unexpected error map to 2 inside `ratchet`, never 3 or 4).
7. `plugins/soleur`: audit its test files; the ratchet rejects `*` rows (an unaudited suite is always a failure).
8. ADR: a dated `## Amendment` to ADR-276 in the ratchet PR (non-activating; supersedes by subject the item 5 clause that `plugins/soleur` "needs a `*` row"), a Stage-status line, and a closing dated line in the last PR; no new ADR.

## Implementation Phases

Every PR is a normal feature PR off `main` (never stack unmerged), PR text ends `Ref #9729` and `Ref #10448`, and each PR re-runs the audit on its own tree and states the live numbers. PR1 carries this plan, `tasks.md` and `decision-challenges.md`; later PRs are new branches that cite them by their archived path.

### PR1 - spike, fast and total audit, accept-row validation

0. Spike first, before any tokeniser code (about ten minutes of measurement, results in the PR body): (a) cold cost of a nested `--print-selection` walk from inside a `test-all.sh` suite on a fresh clone (recursion is already known safe: `test-affected-kb-consumers` does it); compare with the 180 s / 300 s ceiling; (b) a throwaway prototype timing of the component-boundary match against the 30 s target. If (a) exceeds the ceiling, the ratchet takes `--rows FILE` per ruling 4; if (b) misses, memoisation alone is the fallback and the precision rule becomes the conditional PR.
1. In `scripts/ci-pr-affected-replay.py` replace the `f in blob` scan in `suite_refs` with the ruling-3 match: path-component-boundary starts only, extended component by component against a prefix set of the tracked paths (stop at the first absent prefix), per-file memoisation across suites, the one-hop library reads cached per run. Keep `edge_hit` unchanged. Commit `receipts/audit-differential.tsv` (old versus new refs on a pinned tree, every dropped ref listed with its line) and run the recorder over the dropped refs of the heavy-tail suites; the PR fails if an observed open sits in the dropped set. The old scan is NOT kept in the suite (a pinned-tree differential is the proof; the 39 s scan stays out of CI).
2. Directory suites: when the first pattern is a `dir/` prefix, scan the tracked bun-discoverable test files under it (`*.test.ts`, `*.test.tsx`, `*.test.js`, `*.spec.*` per bun's discovery) and union their refs; references inside the directory are covered by the `^dir/` edge. `*` accept rows are rejected by the audit when they name a readable suite.
3. Accept-row validation in `load_accept`/`cmd_audit`, built here with unit fixtures before any row exists: the anchor column, the `false-positive: <non-empty>` reason (the shape check already exists; the anchor and staleness are new), a (suite, path) pair accepted only when every boundary-match line is accepted, and a stale row (path untracked, suite unregistered, or anchor matching no live line) fails. The tokeniser records line numbers only for pairs that appear in the accept file. A missing accept file means no exemptions.
4. Report the new live total after the directory-suite scan (`SOLEUR_PR_AFFECTED_AUDIT` line) in the PR body and on #10448; if the added references exceed the 1,108 figure by more than half, PR4/PR5 are re-split by directory before work starts.
5. Raise the "human-written" wording on #10448 in the PR text: reasons are agent-drafted from line context, cite line kind and number, and are reviewed as diff lines (decision-challenges.md row 9).
6. Extend `plugins/soleur/test/ci-pr-affected-replay.test.sh` with the Guard 2 rows below.

### PR2 (conditional) - boundary precision

Runs only if PR1's prototype showed memoisation alone meets the target AND PR1's dry run shows the left/right boundary rule drops at least 30 gap pairs; otherwise those pairs are handled as accept rows in PR4/PR5 and this PR is not opened. Adds the left boundary as a DENYLIST (reject a match only when the character before the `/`-joined remainder is a word character; everything else, including tab, start of line, backtick, `,`, `{`, `|`, `;`, `&`, `<`, `>`, `$VAR/`, `${VAR}/`, `)/`, `"/`, `./`, `../`, is kept) and the right boundary (next character not `[A-Za-z0-9_-]`), a committed `receipts/boundary-differential.tsv`, per-form fixtures and Guard 3.

### PR3 - the ratchet, the baseline, the ADR-276 amendment

1. `ratchet` subcommand in `scripts/ci-pr-affected-replay.py` (shares `suite_refs`/`edge_hit`; no second implementation). Check order, fail-fast, exit 0 clean, 1 drift or vacuity, 2 infrastructure (including `ReadError`): the selector rc is 0 and `AFFECTED_SUMMARY` total equals the printed row count with `fallback=none`; structural floors (ruling 6); unaudited suites and `*` accept rows are failures; accept rows are valid (PR1 step 3); the baseline file is refused when it carries a duplicate line or is unsorted; the live gap set (minus accepted lines) EQUALS the baseline `(suite, path)` set (a new gap fails, a stale baseline row fails, and the failure text prints the exact line to delete); per suite the baseline never holds more pairs than at the merge base and a suite absent from the merge-base baseline cannot appear (reusing `resolve_base`/`baseline_at` from `scripts/lint-ratchet.py`, bootstrap rule on `RATCHET_BASELINE`); an absent baseline means strict zero except at the bootstrap PR.
2. Failure text is a behavioural contract (pinned by the suite, not a presence check): it names the suite, the path and the referencing line number; offers the two remedies (add the path to `AFFECTED_<LABEL>_PATHS`, or add an anchor-keyed accept row with the exact TSV shape); states that editing `scripts/lib/test-affected-paths.sh` runs the full battery and that a baseline row cannot be added for a new suite. The contributor how-to lives in `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` (a header edit to the shared lib would break the registration-only shape).
3. Create `scripts/ci-pr-affected-audit.baseline.tsv`, one sorted `suite<TAB>path` pair per line, REGENERATED on the rebased tree immediately before merge (every remaining pair at that moment). Create the accept TSV only if a row is needed in this PR.
4. Create `scripts/ci-pr-affected-index-ratchet.test.sh`: one real-tree ratchet run (a single real selector walk) plus controls driven from `--list` row fixtures and scratch `git init` repos with `GIT_CEILING_DIRECTORIES` set (planted undeclared path flagged; planted stale baseline row fails; baseline growth versus a scratch merge base fails; the failure-text contract). Total at most the 300 s suite timeout. Register it by exact file at the END of the registration block in `scripts/test-all.sh` (`run_suite "scripts/ci-pr-affected-index-ratchet" bash scripts/ci-pr-affected-index-ratchet.test.sh`; the runner's ordinal-parity note requires an appended registration), add its label to `ALWAYS_ON_SUITES` in `scripts/lib/test-affected-paths.sh`, give it its own leg in `scripts/suite-shard-legs.tsv` (the totality test chooses the leg for slack), and add its row to `scripts/suite-durations.tsv`. These are the only edits to the two shared files in PR3, shaped as a registration-only runner diff.
5. ADR-276: append a dated `## Amendment <PR3 merge date> (S4 index completion ratchet, #10448)` (non-activating: the lock, `CI_PR_AFFECTED` and PR D (#10414) are untouched; cites item 5 of the 2026-10-16 amendment as the entry condition; supersedes by subject its clause that `plugins/soleur` "needs a `*` row"; states that false-positive reasons are agent-drafted from line context and reviewed in the PR; states the residuals: the baseline comparison is vacuous on a push to `main` where the merge base equals HEAD, and the control is human PR review, not CODEOWNERS, which is documentation only here) and one dated line under `### Stage status`. No edit of earlier text.
6. Update `ci-pr-affected-activation.md` section 2 and 3 (the ratchet exists, the baseline path, how to drain a row, the contributor how-to, the rollback recipe).

### PR4 - heavy-tail suites (about 611 of the 1,108 refs)

For each of `scripts/test-affected-derive` (483), `.claude/hooks/grep-q-pipe-guard.test.sh` (52), `scripts/test-all-infra-coverage-notice` (35), `scripts/ci-pr-selection` (22), `tests/scripts/scratch-residue` (19): read the line context per ref; use the recorder as a positive oracle (an observed open is declared, no further reasoning). If the suite's verdict is a property of the whole tree or the runner (the header's `ALWAYS_ON` meaning), classify it always-on with one `ALWAYS_ON_SUITES` line and record the added minutes from `scripts/suite-durations.tsv` in the PR; if its duration is 60 s or more, use rows instead. Drain the matching baseline pairs in the same commit as the index edit. This is an index-touching PR and pays the full battery once.

### PR5 - remainder, strict zero, closing line

Batch every remaining pair into one edit of `scripts/lib/test-affected-paths.sh` (declared edges for real reads, inserted in alphabetical position by label) plus anchor-keyed rows in `scripts/ci-pr-affected-audit.accept.tsv` for mechanically clear false positives, each citing line kind and line number. Doc-class paths (`README.md`, `AGENTS.md`, `AGENTS.rules.md`, `package.json`, `.gitignore`) are declared per suite that really reads them. Delete `scripts/ci-pr-affected-audit.baseline.tsv` in the same PR (an absent baseline is strict zero); edit `scripts/ci-pr-affected-index-ratchet.test.sh` to retire the baseline-only rows (the merge-base growth and new-suite rows) and add the strict-zero rows (an empty live set passes, a single planted gap fails, a reintroduced baseline file is refused). Append the closing dated line to ADR-276 `### Stage status` ("audit exits 0, ratchet strict; replay and go/no-go re-ruling pending") and update the runbook. The replay, saving and reader-audit re-run on a fresh window and the go/no-go re-ruling are a separate gate that starts after this PR merges, with their own go-ahead. If the drain does not finish in PR5, a PR5b carries the leftover and the delete.

## Files to Edit

- `scripts/ci-pr-affected-replay.py` (PR1, PR2 if opened, PR3)
- `plugins/soleur/test/ci-pr-affected-replay.test.sh` (PR1, PR2 if opened, PR3)
- `scripts/test-all.sh` (PR3: one appended `run_suite` registration)
- `scripts/lib/test-affected-paths.sh` (PR3: one `ALWAYS_ON_SUITES` entry; PR4 and PR5: declared edges)
- `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv` (PR3)
- `scripts/ci-pr-affected-index-ratchet.test.sh` (PR5: strict-zero rows)
- `knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md` (PR3 and PR5: dated amendment and stage-status lines, append-only)
- `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` (PR3, PR5)

## Files to Create

- `scripts/ci-pr-affected-index-ratchet.test.sh` (PR3)
- `scripts/ci-pr-affected-audit.baseline.tsv` (PR3, shrunk in PR4 and PR5, deleted in PR5)
- `scripts/ci-pr-affected-audit.accept.tsv` (created by the first PR that needs a row)
- `knowledge-base/project/specs/feat-one-shot-s4-affected-index-completion/receipts/audit-differential.tsv` (PR1; archived with the spec at ship, so the ADR and runbook cite the archived leaf name)
- `knowledge-base/project/specs/feat-one-shot-s4-affected-index-completion/receipts/boundary-differential.tsv` (PR2 if opened)

Glob check (`hr-when-a-plan-specifies-relative-paths-e-g`): every path above was confirmed with `git ls-files` or is a Create entry; `scripts/suite-shard-legs.tsv` and `scripts/suite-durations.tsv` exist and already list `plugins/soleur/test/ci-pr-affected-replay.test.sh`. The new baseline and accept file names are new text in the ratchet suite (always-on, exempt) and in the replay suite (glob-registered, audited): each PR runs the ratchet on its own tree so a gap created by its own new files fails there.

## Sibling PR Overlap

PR #10389 (draft, branch `feat-one-shot-9307-generic-affected-gate`) changes 22 files: `plugins/soleur/scripts/affected-tests.sh`, `plugins/soleur/scripts/affected-tests.test.sh`, `plugins/soleur/scripts/grok-pre-push-gate.sh`, `plugins/soleur/scripts/lib/affected-tests/{common,go,js,nx-turbo,python}.sh`, `.soleur-test-gate.json`, the ADR-288 file, its plan and specs, `plugins/soleur/skills/{one-shot,review,ship,test-fix-loop,work}/SKILL.md`, `plugins/soleur/skills/ship/references/affected-gate-contract.md`, `plugins/soleur/test/fullsuite-merge-gate.test.ts` and `plugins/soleur/test/workflow-fidelity.test.ts`. Overlap with this plan's files: **none** (zero shared paths). It is the plugin-generic local gate, a different subsystem from the repo's `scripts/test-all.sh` affected index. Re-check with `gh pr view 10389 --json files` at the start of each PR and when it leaves draft.

## Open Code-Review Overlap

Open `code-review` issues naming planned files, none fixed here:
- #8800 (test fixture: census sandbox shares inodes/symlinks with live repo, write-through hazard) names `scripts/lib/test-affected-paths.sh`. Acknowledge: different concern (census sandbox fixtures); this plan only appends array entries, and its new fixtures use scratch `git init` repos with `GIT_CEILING_DIRECTORIES` set, so it does not worsen the hazard.
- #8659 (33 suites replace the composed EXIT trap and leak the incident sandbox) and #7942 (two mutation batteries named `*.mutation.sh` run in no gate) name `scripts/test-all.sh`. Acknowledge: different concerns; the new suite sources the shared test helpers and does not replace the EXIT trap.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "complete the S4 affected index so the audit `python3 scripts/ci-pr-affected-replay.py audit` exits 0 (gap_suites=0, unaudited=0; any remaining row needs a human-written `false-positive:` reason in the census style)" [brief] | PR1 (total audit), PR4, PR5; anchor-keyed accept TSV | adapted - reasons are agent-drafted and reviewed, not authored by a person; raised on #10448 in PR1 (decision-challenges.md row 9) |
| 2 | "then add a ratchet as a required CI check that fails when a suite names an undeclared tracked path" [brief] | PR3 (`ratchet` subcommand, always-on suite in required `test`), PR5 (strict) | mapped |
| 3 | "Multi-PR is expected (index completion, then ratchet)" [brief] | five-PR sequence; ratchet lands early as shrink-only (decision-challenges.md row 10) | mapped |
| 4 | "Do NOT in this work: flip CI_PR_AFFECTED, remove the lock, change scripts/required-checks.txt activation semantics beyond adding the ratchet check itself ... or start S4 PR D" [brief] | Non-goals; ADR-276 amendment states non-activating; `scripts/required-checks.txt` untouched | mapped |
| 5 | "The replay + saving + reader-audit re-run on a fresh window and the go/no-go re-ruling come AFTER the audit is 0 and the ratchet is required; treat them as a follow-up gate" [brief] | PR5 closing line names the follow-up gate; nothing built here | mapped |
| 6 | "Technical forks ... go to the CTO, not the operator" [brief] | `## Technical Rulings` (two CTO rounds) | mapped |
| 7 | "re-measure first and use the live number" [brief] | `## Live Re-measurement` (195 of 643) | mapped |
| 8 | "check whether its files overlap the planned files and record the result in the plan" [brief] | `## Sibling PR Overlap` | mapped |
| 9 | "Use \"Ref #9729\" in PR text, never Closes/Fixes/Resolves" [brief] | every PR body; AC below | mapped |
| 10 | "Do not commit an author or committer identity of s@example.invalid" [brief] | AC below (`git log --format` check per PR) | mapped |
| 11 | "Known flake when reading any replay: scripts/test-all-orphan-log-retention" [brief] | AC below: red on that suite alone is re-run, not a regression | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| PR1 step 0 cost spike and fast scan | "a ratchet as a required CI check that fails when a suite names an undeclared tracked path" | inferred - justification: a 5m28s audit cannot gate every PR and merge-queue entry, so speed is a dependency of ask 2 and the CTO ruled the ceiling |
| PR1 directory-suite scan | "unaudited=0" | asked (ask 1) |
| PR1 accept-row validation (anchor-keyed, stale rows fail) | "any remaining row needs a human-written `false-positive:` reason" | inferred - justification: a stale or line-mismatched reason is a false claim, and a (suite, path) key would let a later real read stay exempt; the CTO ruled the anchor key |
| PR2 (conditional) boundary precision | "complete the S4 affected index" | inferred - justification: mid-component substring matches inflate the gap list with non-reads; it runs only if measured to drop at least 30 pairs |
| PR3 ratchet in required `test` | "a ratchet as a required CI check" | asked (ask 2) |
| PR3 shrink-only baseline | "Multi-PR is expected" | inferred - justification: the live count drifted 190 to 195 while the evidence was written; without a ratchet the drain chases a moving target (CTO 3(ii)) |
| PR3 ADR-276 amendment | "adding a new required check needs the usual ruleset path, no bypass" | inferred - justification: ADR-276 Decision 3(g) says a stage change in CI behaviour takes effect only through its own dated amendment |
| PR4 and PR5 index drain | "complete the S4 affected index" | asked (ask 1) |
| PR5 baseline deletion, strict zero | "exits 0 (gap_suites=0, unaudited=0" | asked (ask 1) |
| runbook update | "The replay + saving + reader-audit re-run ... treat them as a follow-up gate" | inferred - justification: the runbook's section 3 states the entry condition and the contributor how-to, and rots otherwise |

### Split Assessment

- Subsystems touched: 3 - `scripts`, `plugins/soleur`, `knowledge-base` (`.github` and `infra` are NOT touched)
- Planned files: 13 | Estimated changed lines: ~1,600 across the PRs (largest single PR: PR5, a batched array edit)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split - already five PRs (plus one conditional) along the seams the CTO ruled; no PR exceeds one subsystem pair

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-visible. A broken ratchet fails a PR in the founder's own CI or lets an undeclared read through; the lever stays dark, so no merge skips a suite because of this work.
- **If this leaks, the user's data is exposed via:** no vector. The tooling reads tracked file names and suite text only; no credential, personal data or customer content is read, stored or logged, and the receipts contain repository paths.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the work changes no runtime behaviour while `CI_PR_AFFECTED` is unset; the harm class (a skipped suite letting a regression land) only exists after activation, which is explicitly out of scope and needs its own go-ahead.

threshold: none, reason: the touched paths are CI tooling and test registration with no web-platform runtime and no credential or workflow-secret path, and no workflow file is edited.

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The CTO agent ruled all technical forks on 2026-10-19 in two rounds (see `## Technical Rulings`), the second after plan review found the cold-cost, tokeniser and accept-key evidence. A devex-lens CTO review of the finished plan produced six taste findings, dispositioned in decision-challenges.md rows 14-19. No Product/UX surface exists (no UI file in Files to Edit/Create); Marketing, Sales, Legal, Finance, Operations and Support have no implication (internal CI tooling, no vendor, spend or customer-facing change; the budget owner's funding decision is already recorded on #10448).

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-276 (no new ADR; the ratchet reuses ADR-290's pattern): a dated `## Amendment` in PR3 (non-activating; entry condition per item 5 of the 2026-10-16 amendment; supersedes by subject its `*`-row clause for `plugins/soleur`; agent-drafted false-positive reasons stated plainly; the ratchet is an always-on suite in the existing required `test` context, so no new required context) and a closing dated line under `### Stage status` in PR5. Earlier text is never edited (append-only). This is a task in PR3 and PR5, not a follow-up issue.

### C4 views

No C4 impact. Checked against all three model files (`model.c4`, `views.c4`, `spec.c4`): (a) external human actors - none added or changed (no new actor reads or writes data); (b) external systems or vendors - none (the audit runs offline over tracked files; `github` is already modeled and no new edge is added); (c) containers or data stores - none (two TSV files in the repository are not a modeled store); (d) actor-to-surface access relationships - unchanged. `grep -c test-all` returns 0 in `model.c4` and `views.c4`, so no element description is falsified. Derived cardinalities embedded in edge prose (workflows, monitors) do not move because no workflow, job or monitor is added; PR3 still runs `bash plugins/soleur/test/c4-count-parity.test.sh` and records it green.

### Sequencing

The ADR amendment is authored in PR3 describing the ratchet as it lands; PR5 adds the closing line when the baseline is deleted.

## Guard Contract

### Guard 1 - the ratchet (`ratchet` subcommand plus its suite)

**Property.** No registered suite can name a tracked path that is neither declared for it, covered by the runner trigger, nor carrying a live anchor-keyed `false-positive:` row, without the required `test` context going red.

**Assembly.** The population is every row `test-all.sh --print-selection` prints (643 today), not a list of current suites: the chokepoint is `cmd_audit`'s row loop reading the selector's own `AFFECTED_SELECTED` rows, so a new registration flows through it automatically. Members that must flow through the one chokepoint: suites with a file first pattern (`suite_file`), directory suites (PR1 scan), `always_on` suites (exempt but counted), suites sourcing a library (one hop), short or unreadable rows (counted unaudited). The tracked-path set is `git ls-files`; the edge grammar is `edge_hit` (literal, `dir/`, `glob:`). Everything that can add a gap row enters through `suite_refs`; the baseline and the accept TSV are the only stored values, both validated against the live census.

**Mutation matrix.**

| # | Edit (must drive the guard RED) | Expected red |
|---|---|---|
| M1 | add a line to a scratch suite naming an undeclared tracked path while a compliant suite precedes it in the rows (second member after a compliant first) | ratchet exits 1, names suite, path and line |
| M2 | make the selector print zero `AFFECTED_SELECTED` rows or exit non-zero (the guard's own dispatch) | exit 2 (ReadError and zero rows both map to 2), never 0 with "0 checked" |
| M3 | delete a baseline pair whose gap still exists | exit 1 (gap not in baseline) |
| M4 | leave a baseline pair whose gap was fixed (stale row) | exit 1 (baseline not equal to census), text prints the line to delete |
| M5 | add a baseline pair for a suite absent at the merge base (new suite baselined) | exit 1 (baseline growth for a new suite) |
| M6 | add a duplicate line to the baseline, then separately an unsorted order | exit 1 each (two sub-rows) |
| M7 | accept row whose anchor matches no live line (stale), and separately an accept row for a suite that adds a second reading line of the same path | exit 1 each: stale row; the unaccepted second line is a new gap |
| M8 | set `AFFECTED_SUMMARY` total different from the printed row count | exit 2 (structural floor) |
| M9 | make one suite unreadable (unaudited) | exit 1 |
| M10 | a `*` accept row naming a readable suite | exit 1 |
| M11 | drop the planted control suite from the self-test's fixture rows | the suite's own floor reds (the harness row below) |

**Harness rows.** Edit to the suite (not the guard): remove the planted-undeclared-path control from `scripts/ci-pr-affected-index-ratchet.test.sh`; the suite's anti-vacuity floor (assertion count and "control flagged") must go RED. Must-PASS non-canonical input: a fixture suite that reads `"$ROOT/plugins/x/README.md"` with the edge declared as the nested `^plugins/x/` prefix (a shape different from the canonical fixture), and an anchor-keyed accept row for a mechanically clear false positive; both must exit 0.

**Anchor.** The baseline is a stored value compared to the thing it protects. Outside the commit: the merge-base baseline (per-suite pair counts never grow, a suite absent at the merge base cannot appear) and human PR review of the baseline and of `scripts/ci-pr-affected-audit.accept.tsv` (new reasons are visible diff lines; CODEOWNERS is documentation only here and this plan adds no CODEOWNERS entry). On a push to `main` the merge base equals HEAD, so only baseline-equals-census gates there (the ADR-290 residual, stated in the amendment); the strict-zero state has no baseline to edit.

### Guard 2 - fast-scan match definition (PR1)

**Property.** Every reference the new component-boundary scan drops relative to the old `f in blob` scan has a mid-component start (is not a read), and no reference a suite really reads is dropped.

**Assembly.** The tracked-path set (19,363 files), every suite blob (suite file plus one sourced hop, comments stripped), the prefix set the scan extends against, and the per-file memoisation cache. The chokepoint is `suite_refs`. The differential is a committed receipt on a pinned tree, and the recorder oracle (`scripts/audit-suite-reads.sh`) is the independent check on the dropped set.

**Mutation matrix.**

| # | Edit | Expected red |
|---|---|---|
| M1 | scan drops the last run in a blob (off-by-one at end of text) | a fixture whose only reference is at end of text reds |
| M2 | scan stops at the first matching path in a blob (stops at first member) | a two-path fixture reds |
| M3 | prefix-set extension stops at a path component containing `(` (an out-of-charset path such as `apps/(auth)/page.tsx`) | the fixture row for that path reds |
| M4 | `suite_refs` returns an empty list for every suite (the audit's own dispatch) | `gap_suites=0` is caught by the fixture rows asserting a known gap is reported; the differential on the pinned tree reds |
| M5 | memoisation keyed on file name only (not content) so a changed library is served stale | a fixture that edits a sourced library between two suites reds |

**Harness rows.** Edit the suite: delete the suffix-path fixture; the suite's per-form floor reds. Must-PASS non-canonical: a blob where a tracked path is a suffix of a longer tracked path (`a/b.sh` and `x/a/b.sh`), both present; and a reference preceded by a tab.

**Anchor.** Outside the commit: the recorder oracle run (independent of the code under change) and the pinned-tree differential receipt reviewed in the PR. Not a stored-value guard.

### Guard 3 - boundary precision (PR2, only if opened)

**Property.** The left/right boundary rule never drops a reference the suite really reads.

**Assembly.** The left-boundary DENYLIST (a match is rejected only when the character before it is a word character), the right-boundary set, and the one boundary predicate in `suite_refs`; the dropped set is the committed `receipts/boundary-differential.tsv`.

**Mutation matrix.**

| # | Edit | Expected red |
|---|---|---|
| M1 | reject a match preceded by `/` after a variable (`$REPO/README.md`) | the `$REPO/README.md` fixture drops; row reds |
| M2 | reject `../README.md` after a compliant `./README.md` first | the `../` fixture drops; row reds |
| M3 | right boundary accepts `-` and `_` continuation (`README.md-x`) | the over-match fixture reds |
| M4 | boundary predicate never called (dispatch) | the `plugins/soleur/README.md` negative fixture matches the root path; row reds |

**Harness rows.** Edit the suite: delete the dropped-negative fixture; the per-form floor reds. Must-PASS non-canonical: a path preceded by a tab and followed by a closing quote, and one at start of line.

**Anchor.** Recorder oracle outside the commit: any dropped reference that `scripts/audit-suite-reads.sh` observes being opened fails PR2; the differential is reviewed in the PR.

## Test Scenarios

1. Live tree: `python3 scripts/ci-pr-affected-replay.py ratchet` exits 0 at PR3 merge and exits 1 after adding an undeclared read to any registered suite.
2. Differential: the PR1 receipt lists every dropped ref with its line, and each has a mid-component start; the recorder sees none opened.
3. Fixture: a suite that writes `README.md` into a scratch repo it builds and never reads the real one is an anchor-keyed `false-positive:` row; the same suite adding a SECOND line that reads `"$ROOT/README.md"` fails until the edge is declared (the new line has no accepted anchor).
4. New-suite attack: a PR adds a suite with 3 undeclared reads and 3 baseline rows for it; the ratchet rejects it (merge-base growth rule).
5. Stale census: remove the last mention from a suite while its accept row remains; the ratchet fails and names the row.
6. Strict end state: after PR5 `python3 scripts/ci-pr-affected-replay.py audit` prints `gap_suites=0 unaudited=0` and exits 0, and the baseline file is gone.

## Acceptance Criteria

Pre-merge (per PR; each PR states the live audit line in its body):
- [ ] Each PR body contains `Ref #9729` and `Ref #10448` and none of `Closes`, `Fixes`, `Resolves` (`gh pr view --json body --jq .body | grep -ciE '(closes|fixes|resolves) #' || true` prints 0).
- [ ] No commit carries the identity `s@example.invalid` (`git log origin/main..HEAD --format='%ae %ce' | grep -c 's@example.invalid' || true` prints 0).
- [ ] No edit to `scripts/ci-pr-selection.sh`, the `pr-selection` job, the `CI_PR_AFFECTED` variable, the activation lock or PR D files; `scripts/required-checks.txt` and `.github/workflows/ci.yml` are unchanged (merge-base form, so a sibling merge cannot redden it: `git diff origin/main...HEAD --stat -- scripts/required-checks.txt .github/workflows/ci.yml scripts/ci-pr-selection.sh` prints nothing). Files the pipeline itself writes (`knowledge-base/INDEX.md`, `specs/feat-one-shot-s4-affected-index-completion/{tasks,session-state,decision-challenges}.md`, receipts) are outside this scope check.
- [ ] PR1 step 0: the spike results (cold nested-walk cost, prototype timing) are in the PR body and compared to the ceiling (180 s billed cold, 300 s suite timeout; 30 s scan target); a miss follows the ruling-4 and ruling-3 fallbacks instead of proceeding.
- [ ] PR1: the tokeniser's work is bounded by a deterministic fixture (an operation-count assertion over a synthetic 20,000-path tree and a 10 KB blob, not a wall-clock one, so a busy machine cannot flip it); `receipts/audit-differential.tsv` is committed and every dropped ref has a mid-component start (a mechanical check in the suite over the receipt); the recorder sees none opened; the post-directory-scan live total is reported with the re-split trigger of PR1 step 4.
- [ ] PR1: accept-row validation fixtures cover a stale row, an anchor mismatch, a missing reason, a `*` row naming a readable suite and a missing accept file (no exemptions).
- [ ] PR2, only if opened: `receipts/boundary-differential.tsv` committed; zero dropped refs observed opened by the recorder; per-form fixtures green; the PR body shows the measured drop of at least 30 gap pairs.
- [ ] PR3: `python3 scripts/ci-pr-affected-replay.py ratchet` exits 0 on the live tree; `bash scripts/ci-pr-affected-index-ratchet.test.sh` green with M1-M11, the harness rows and the failure-text contract; the baseline was regenerated after the last rebase (the suite's real-tree run is the proof: a stale baseline fails it); the suite is in `ALWAYS_ON_SUITES`, has its own `scripts/suite-shard-legs.tsv` leg and a `scripts/suite-durations.tsv` row; `bash scripts/lint-orphan-test-suites.sh` (slow, runs the whole census) reports the new suite registered and classified; `bash plugins/soleur/test/c4-count-parity.test.sh` green; the PR body states the ratchet's cost on the path it touches, cold and with a restored cache (the `--print-selection` pre-pass dominates; a prior ratchet meant to license a saving cost 11 minutes per run because only suite-seconds were priced) and that docs-only PRs pay it too, and the cold figure fits the ceiling or the PR stops and re-rules.
- [ ] PR3 ADR check: ADR-276 has the new amendment and no deleted lines (`git diff --numstat origin/main...HEAD -- knowledge-base/engineering/architecture/decisions/ADR-276-demand-first-hosted-runner-budget-merge-group-is-the-full-battery-authority.md | awk '$2>0{n++} END{print n+0}'` prints 0, the second numstat column being deletions).
- [ ] PR3 rollback: the revert recipe was simulated (scratch detached worktree, `git revert --no-commit` of the PR's commits, then `bash scripts/lint-orphan-test-suites.sh`, the shard-totality census, `bash plugins/soleur/test/ci-pr-affected-replay.test.sh` and the ADR append-only check) and the recipe is in the runbook.
- [ ] PR4/PR5: the baseline strictly shrinks (`wc -l` smaller, no new pair, still sorted); every added accept row starts with `false-positive:`, carries an anchor, and cites a line kind and number; the live `SOLEUR_PR_AFFECTED_AUDIT` line is quoted.
- [ ] PR5: `python3 scripts/ci-pr-affected-replay.py audit --accept scripts/ci-pr-affected-audit.accept.tsv` prints `gap_suites=0` and `unaudited=0` and exits 0; the baseline file is deleted and the ratchet suite asserts an absent baseline is strict zero and a reintroduced baseline file is refused; the ratchet runs with no flags (it reads the committed TSV).
- [ ] `scripts/test-all-orphan-log-retention` red alone on a PR run is re-run and recorded as the known flake, not treated as a regression.

Post-merge:
- [ ] After PR3 and PR5, the ratchet suite's pass line appears in the `test-scripts` leg log of the main push run and of a `merge_group` run (`gh run list --workflow ci.yml --event merge_group --limit 1 --json databaseId` then `gh run view <id> --log | grep -c 'ci-pr-affected-index-ratchet'` is at least 1).
- [ ] #10448 receives a comment per PR with the live audit line; the issue stays open until the follow-up gate (replay re-run and go/no-go) is decided.

## Rollback

Each PR is independently revertible, but a recipe nobody has executed is first run during an incident, so PR3 and PR5 each simulate theirs before they are called done (the PR3 acceptance criterion above). PR3 revert removes the suite, its `ALWAYS_ON_SUITES` entry, its leg and duration rows, the ratchet subcommand and the baseline together; the ADR amendment stays (append-only) and gains a one-line dated note that the ratchet was withdrawn. Reverting PR4 or PR5 restores the baseline pairs those PRs drained, which is why each of those PRs keeps the baseline edit and the index edit in one commit (a revert that restores the index edit without the baseline rows would fail the ratchet).

## Non-Goals

- Flipping `CI_PR_AFFECTED`, removing the activation lock, PR D (#10414), per-suite selection.
- A separately named required context for the ratchet (a follow-up PR with its own ruleset authorization if the owner asks for one; the `test` suite already makes it required).
- Re-running the escape replay, the saving measurement or the reader audit, and the go/no-go re-ruling: a separate gate after PR5, tracked on #10448.
- Making the recorder a CI gate; auditing paths assembled from variables (the audit sees literal names only, so `gap_suites=0` stays a lower bound, as the runbook already states).
- A `ratchet --prune-baseline` command (a contributor deletes the printed line by hand; see decision-challenges.md row 15).

## Risks and Sharp Edges

- The ratchet runs the selector cold from inside a `test-all.sh` suite; the CTO ceiling is 180 s billed per full-battery run. PR1 step 0 measures it; a miss triggers the `--rows FILE` fallback and a CTO re-rule if that also misses.
- `scripts/lib/test-affected-paths.sh` is a merge-conflict hotspot and any non-registration edit makes that PR run the full battery; keep PR4 and PR5 to one batched edit each, insert in alphabetical position by label, and rebase just before merge. Merge-queue revalidation covers the baseline-equals-census race with a suite edit landing on main; the rebase is mechanical (regenerate the baseline).
- The baseline is a stored value; its integrity rests on the merge-base growth rule and review, and is vacuous on a push to `main` (ADR-290 residual, recorded in the amendment).
- A `false-positive:` reason is a claim about suite behaviour; the ratchet validates shape, staleness and the line anchor, not truth. Reasons are agent-drafted from line context and reviewed in the PR (decision-challenges.md row 9).
- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6; this plan fills it.
- Audit counts drift as suites are added; always quote the live line from the PR's own tree.
