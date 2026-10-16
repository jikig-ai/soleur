# Index-completeness audit, criterion (b) (S4 PR C, Ref #9729)

Question (CTO R2/R3 (b)): is every repository path a registered suite (or the libs it sources, one hop) names declared for that suite in the
affected index, or covered by the runner-changed trigger? The audit is `python3 scripts/ci-pr-affected-replay.py audit`, run against a pinned
`origin/main` tree (`ee8644bded`). It joins the selector's own `AFFECTED_SELECTED` rows (the declared and derived patterns per suite) with the
tracked paths each suite file and its sourced libs name literally. Whole-line comments are skipped (a mention is not a read), and a path that
only triggers the runner-changed full battery (`scripts/test-all.sh`, `scripts/lib/test-affected-paths.sh`) is covered by the trigger list.

Fixture: the PR 9404 shape (a `-mutations` sibling that consumes `ci.yml` and a sibling suite while the index declares only its own file) IS
flagged (suite `ci-pr-affected-replay.test.sh`, the audit rows).

Measured on the pinned tree, before the two refinements: **226 of 630 suites** named an undeclared tracked path (1,918 references). After
skipping comment-only mentions and excusing the runner triggers: **145 of 630 suites, 964 references**. Command output line:
`SOLEUR_PR_AFFECTED_AUDIT suites=630 gap_suites=145 gap_refs=964`.

Most frequent undeclared paths: `README.md` (31 suites), `.claude/settings.json` (14), `AGENTS.md` (13), `AGENTS.rules.md` (11),
`.gitignore` (10), `.github/workflows/ci.yml` (10), `package.json` (9), `package-lock.json` (5), `lefthook.yml` (5), `.mcp.json` (4).

A literal-name scan over-approximates reads. A random sample (seed 9729) of 14 of the 355 pairs the audit lists (it prints the first six
undeclared paths per suite), each read at its referencing line: **6 are real reads** of the tracked file (for example
`$ROOT/apps/.../model-tiers.ts`, `$REPO_ROOT/.github/workflows/ci.yml`, `$REPO_ROOT/.claude/settings.json`, a workflow YAML, a symlink
to `README.md`), **3 write the named file INTO a scratch fixture repo**, and **5 are a message, a registry string or no non-comment line
at all**. Six of 14 is an unreliable share (n=14): extrapolated to 964 references it is on the order of 400 real undeclared reads, not
zero, and a path such as `README.md` is a doc-class path, so under the proposed per-suite rule a README-only diff would skip suites that
read it.

**Status for criterion (b) (zero unexplained gaps): `fail`.** The gap count is 145 suites, far outside any 10% band of zero. This is the
dominant reason the verdict is NO-GO; closing it means declaring the real reads for each suite (or removing the reads), which is index work for
a later PR, not a threshold to argue.

Limits: the scan sees literal names only (a path assembled from variables is invisible), skips whole-line comments only, follows one `source`
hop, and does not read non-registered helper files. It cannot prove a gap is a read, so the real-read share above is a sample, not a count.
