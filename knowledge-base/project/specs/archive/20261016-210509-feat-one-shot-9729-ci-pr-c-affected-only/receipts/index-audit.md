# Index-completeness audit, criterion (b) (S4 PR C, Ref #9729)

Question (CTO R2/R3 (b)): is every repository path a registered suite (or the libs it sources, one hop) names declared for that suite in the
affected index, or covered by the runner-changed trigger? The audit is `python3 scripts/ci-pr-affected-replay.py audit --root <tree>`, run
2026-10-16 against a pinned detached checkout of `origin/main` (`abbd36a696`). It joins the selector's own `AFFECTED_SELECTED` rows (the declared
and derived patterns per suite) with the tracked paths each suite file and its sourced libs name literally. The suite file is the FIRST pattern of
the suite's own row; whole-line comments are skipped (a mention is not a read); a path that only triggers the runner-changed full battery
(`scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh`) is covered by the trigger list; the selector's `^glob:<head>/<tail>` edges are
matched with the selector's own glob grammar (`*` crosses `/`); `always_on` suites run on every diff, so their index is exempt.

Fixture: the PR 9404 shape (a `-mutations` sibling that consumes `ci.yml` and a sibling suite while the index declares only its own file) IS
flagged, and a suite whose file the audit cannot read is reported `unaudited` and makes the audit exit 1 (the replay suite pins both).

**Measured: `SOLEUR_PR_AFFECTED_AUDIT suites=630 always_on=114 audited=515 unaudited=1 gap_suites=190 gap_refs=1079 accepted=0`** (exit 1; re-run with `--all-refs` and the selector-grammar edges at review, same figures). The full per-suite list is committed as `index-audit-gaps.tsv` (190 rows, 1,079 references) and the frequency table below is tallied from it, so it is reproducible. So **190 of
the 515 audited suites (about 37%; 190 of 630 registered, about 30%)** name an undeclared tracked path, 1,079 references; one suite (`plugins/soleur`, a directory
suite) is unaudited. **Correction of the first version of this receipt.** It reported 145 of 630 suites and 964 references. That audit located
each suite's file by guessing name variants and never read 189 of the 631 suites it listed, yet exited 0 with `gap_suites` computed over the rest,
and it silently skipped every `^glob:` edge (an uncompilable regex). 145 and 964 were floors; the corrected figures are above. The verdict is
unchanged and the gap is larger.

Most frequent undeclared paths (all 1,079 references, tallied from `index-audit-gaps.tsv`): `README.md` (36 suites), `AGENTS.md` (16),
`AGENTS.rules.md` (14), `.claude/settings.json` (14), `package.json` (13), `.gitignore` (12), `.github/workflows/ci.yml` (11),
`scripts/betterstack-query.sh` (10), `plugins/soleur/test/lib/git-fixture-env.sh` (7), `.github/workflows/apply-web-platform-infra.yml` (6),
`lefthook.yml` (6), `package-lock.json` (6).

A literal-name scan over-approximates reads. A random sample (seed 9729) of 14 pairs drawn from the FIRST version of the audit (355 pairs; the
audit prints the first six undeclared paths per suite), each read at its referencing line: **6 are real reads** of the tracked file (for example
`$ROOT/apps/.../model-tiers.ts`, `$REPO_ROOT/.github/workflows/ci.yml`, `$REPO_ROOT/.claude/settings.json`, a workflow YAML, a symlink to
`README.md`), **3 write the named file INTO a scratch fixture repo**, and **5 are a message, a registry string or no non-comment line at all**.
Six of 14 is an unreliable share (n=14) and the sample was not redrawn from the corrected audit: applied to 1,079 references it is on the order
of 460 real undeclared reads, not zero, and a path such as `README.md` is a doc-class path, so under the proposed per-suite rule a README-only
diff would skip suites that read it.

**Status for criterion (b) (zero unexplained gaps): `fail`.** The gap count is 190 suites, far outside any 10% band of zero (the band does not
apply to a zero threshold). This is the dominant reason the verdict is NO-GO; closing it means declaring the real reads for each suite (or
removing the reads), which is index work for a later PR, not a threshold to argue.

Limits: the scan sees literal names only (a path assembled from variables is invisible), skips whole-line comments only, follows one `source`
hop, and does not read non-registered helper files. It cannot prove a gap is a read, so the real-read share above is a sample, not a count.
