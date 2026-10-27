# PR body facts (S4 PR5 measurement slice, Ref #10861)

Outcome B: one suite qualified. Measurements taken in this PR at `origin/main` 6512cf3ee554 on 2026-10-26 (receipts: `receipts/measurement-stamp.txt`, `durations.tsv`, `glob-rate/glob-rate.tsv`, `glob-rate/glob-rate.marker`). The 200 units are the last 200 first-parent commits of that SHA: 200 distinct `(#N)` subjects, 2026-10-18 to 2026-10-26.

| suite | duration | src | rate, conservative / excluded | verdict | reason |
|---|---|---|---|---|---|
| .claude/hooks/grep-q-pipe-guard.test.sh | 6081 ms | measured | 125/200 / 83/159 | always_on | over-25-percent |
| plugins/soleur | none | missing | 152/200 / 111/159 | baselined | duration-missing |
| plugins/soleur/test/boundary-prefix.test.sh | 1184 ms | floor | 121/200 / 79/159 | baselined | duration-floor |
| tests/scripts/argv-bearer-sweep | 47034 ms | measured | 128/200 / 85/159 | baselined | rate-over-and-duration-over-30s |

- The brief's "43 suites" are 43 pairs over three suites (22, 16, 5); with boundary-prefix that is four suites measured.
- The `floor` and missing verdicts follow CTO row 3 (a floor row is an estimate, a missing row is no figure), not a literal reading of the quoted policy. No local timing was taken or used.
- The replay tool had no per-glob rate, so the read-only `glob-rate` subcommand was built first (tests and 38 mutants in the replay suite). The model was spot-checked against the real selector on 3 evenly spaced diffs: 2010 suite bits compared, no divergence. 40 of the 200 units name the runner files and count as selected in the conservative reading.
- No candidate glob was built for the two suites that pass the duration gate: a candidate entry can only raise a suite's rate, and both verdicts are already decided on the existing edges alone (83/159 and 85/159, both over 25%). The hot-file budget did not decide anything (ruling 5); `boundary-prefix` stops at the duration gate.
- Index edit: `.claude/hooks/grep-q-pipe-guard.test.sh` added to `ALWAYS_ON_SUITES`; `_MIN_ALWAYS_ON_DECLARED` 114 to 115 with its `f1` pin; 4 accept rows (stale, `suite-always-on`) and 20 `test-affected-kb-consumers.baseline.txt` rows deleted; the audit baseline goes 1619 to 1515 (104 lines drained, none added; all 104 belong to this suite; 22 of them were in the PR4c sweep scope). Post-edit check: an empty-candidate run on the edited tree reports 159 of 159 (tautological for an always-on suite, since it selects every unit; it shows the entry is installed, not that the verdict is right).
- `origin/main` had moved 5 commits past the measured SHA when this was written; none touched the index, the baseline, the accept file, the duration tables, the runner or the replay script, so only the ratchet is re-run on the merged tree.
- Reproducing the receipts: `glob-rate` reproduces `glob-rate.tsv` byte for byte only against a tree from BEFORE the index edit (the saved `rows.txt` predates it; on the edited tree the real selector selects the suite on every diff and the spot-check rightly stops with exit 4).
- The baseline file stays and no ADR-276 closing line is appended: strict zero is unreachable under the holds.
- Review round: 12 seats, no P1; the P2s were fixed inline (a `glob` verdict now needs a coverage proof, `@tree` with no recognised extension is refused, the spot-check is mandatory and per candidate suite, printed labels are escaped, an `always_on` verdict above the 10 s fast-tier cap is `baselined`).
- Local gate: the index edit is a runner trigger, so the local `--affected` gate degrades to the full battery; CI's required `test` context is the merge gate.
- Holds untouched: no `CI_PR_AFFECTED`, no activation-lock removal, no PR D (#10414), no PR3b (#10859), no evidence re-run (`collect`, `ejections`, `aggregate`, `verdict` not run), no flip PR.
