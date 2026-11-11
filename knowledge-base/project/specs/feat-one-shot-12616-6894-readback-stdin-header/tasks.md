# Tasks: runbook 6894 destroy read-back on stdin, pinned by N3b (#12616)

Plan: `knowledge-base/project/plans/2026-11-11-security-runbook-6894-destroy-readback-stdin-header-plan.md`
Rulings: `knowledge-base/project/specs/feat-one-shot-12616-6894-readback-stdin-header/decision-challenges.md`

## Phase 1: Setup, refactor, RED

- [x] 1.1 Baseline: run `bash plugins/soleur/test/sole-copy-drift-check.test.sh` to a scratchpad log and `tail -3` it;
  expect `284/284`.
- [x] 1.2 Commit A (equivalence refactor): extract `rb_line_readback <id>` and `rb_line_get404 <id>`, and re-express
  `rb_expected` with them. `cmp` the `rb_expected "$_wpin"` output before and after. The suite must stay `284/284`, with
  N3 and H15 green.
- [x] 1.3 Rewrite N1 as `n1_rb <runbook> <pin>`:
  - 1.3.1 a readable-file check;
  - 1.3.2 one shared `RE404` regex;
  - 1.3.3 the set clause (exemption);
  - 1.3.4 the pin clause (`grep -c`, no `|| _g=0`);
  - 1.3.5 a comment naming N3b as the check that covers the comment-keyed exemption;
  - 1.3.6 N1 keeps its other conjuncts and a single pass/fail line.
- [x] 1.4 Add `INNGEST_RETIRED_ID=106261946` (an oracle comment) and `n3b`:
  - 1.4.1 the slot check, which prints `slot:` and returns at once;
  - 1.4.2 the destroy fence, matched by heading string equality plus `fence1`;
  - 1.4.3 a whole-file tolower census with predicates p1, p2 and p3 (ruling 8a), an exact multiset, and unclassified
    lines reported with their predicate;
  - 1.4.4 every message starts with a fixed tag: `slot:`, `destroy-fence:`, `unclassified p1|p2|p3:`, `count`.

  Add the N3b row beside N3.
- [x] 1.5 Add H18 on copies of the real documents under `$TMP/n3b/`:
  - 1.5.1 Guard 1 rows 1-10 and H-a, H-b, H-c, each row requiring its named tag (row 9: no `count` line);
  - 1.5.2 Guard 2 rows 1-4, judged by `n1_rb` only, reusing the Guard 1 row 3 and 4 copies for rows 1 and 2;
  - 1.5.3 the `cmp -s` did-not-land check;
  - 1.5.4 rows 1-4 and 9 edit only inside their section, and a changed-lines-in-section check reports `misplaced`;
  - 1.5.5 failures listed as `uncaught:<label>` and `spurious:<label>:<first line>`.
- [x] 1.6 RED run on the unfixed documents, with no commit. N3b must fail, naming the destroy fence and three
  unclassified lines, and H18 fails too. Save both FAIL lines for the PR body.

## Phase 2: Core Implementation (GREEN)

- [x] 2.1 Runbook 6894 section 5b destroy fence: the line becomes `D(106261946)`, without 6604's 5-space indentation.
- [x] 2.2 Runbook 6894 section 5c fence and the postmerge SKILL.md Phase 5.7 fence: both become `R(106903269)`,
  byte-identical. Add no skill prose.
- [x] 2.3 Runbook prose:
  - 2.3.1 the paragraph under the destroy fence: `missing-token` exit 3, step O5, no fallback, pinned by N3b;
  - 2.3.2 the 5c paragraph: a confinement sentence; replace the stub and real-API sentences (the 2026-10-15 run was of
    the earlier form; the current form has not been run against the real API).
- [x] 2.4 Set FLOOR to the realized total (expected 286). Update the header comment `:27-30`: H11-H18; the
  negative-control list naming N1's exemption and N3b; the counts; N1/N3b reading runbook 6894 and the skill. Commit B.

## Phase 3: Testing

- [x] 3.1 Run the suite to a log and `tail -3` it: all passed, rc 0, N1/N3/N3b/H14/H15/H18 `pass`.
- [x] 3.2 `bash apps/web-platform/infra/inngest-luks-sole-copy.test.sh` (H2 byte-identity).
- [x] 3.3 Run `git fetch origin main`, then the remaining gates:
  - `bash tests/scripts/test-argv-bearer-sweep.sh`
  - `python3 scripts/lint-skill-body-budget.py --base origin/main`
  - `python3 scripts/lint-infra-no-human-steps.py`
  - markdownlint on the two documents
- [x] 3.4 AC2 replay: run `n3b` on `git show 408ad9c0e1ae60a344f26e48b90357d6a7fdc22e:<file>` (pinned base, recorded in the PR body) copies; expect `destroy-fence:`
  plus three `unclassified` lines. AC4 grep returns nothing. AC7 normalized grep prints `0` for the old claim, and the new wording is present in
  section 5c.
- [x] 3.5 For each of the four CTO mutants, run it on the worktree file:
  - 3.5.1 edit the file;
  - 3.5.2 run the suite;
  - 3.5.3 capture the N3b FAIL line (plus the N1 FAIL line for mutants 3 and 4);
  - 3.5.4 `git checkout -- <file>`;
  - 3.5.5 confirm `git diff --quiet -- <file>`.
- [x] 3.6 Stub re-run of the 5c line in the scratchpad, never committed:
  - 3.6.1 extract the line from the fixed fence;
  - 3.6.2 stubs: `doppler`, `curl` (whole-stdin check kept), and argv-checking pass-throughs for `jq`, `sed`, `tail`;
    every stub logs to `$FAKE_LOG` (`accepted` / `refused:<reason>`);
  - 3.6.3 run the ten cases twice, with `sh` as bash and as dash; assert `command -V printf` is a builtin in each;
  - 3.6.4 per case: one `accepted` curl line on the seven rows that reach curl, an empty log on the other three, no
    `refused:token-on-argv`; build the tables from the log; note strace is absent.

  Do not cite a destroy-line stub run.
- [x] 3.7 PR body:
  - `Closes #12616` and `Ref #9927`
  - `## Changelog`
  - the RED-before lines and the AC2 replay output, the four mutant FAIL lines, and the bash and dash stub tables (no
    real-API run claimed)

  Then add the `semver:patch` label and use normal ship and auto-merge.
