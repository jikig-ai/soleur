# Learning: declaring affected-path edges has a hidden audit blast radius — pattern files and transitive source-hops

## Problem

PR #11779 (#11648 fast-tier demotion) taught that `AFFECTED_<LABEL>_PATHS` edges are not free coverage:

1. Declaring an edge on a file makes the ci-pr-affected audit READ that file for path mentions. Edging `.gitignore` (which grep-q-pipe-guard reads via `--exclude-standard`) minted ~442 live pairs — every pattern line in every tracked `.gitignore` became a (suite, path) pair needing an accept row. Correct coverage was unaffordable; deferred to #11810.
2. Moving a path from accept-row to edge is not neutral: it reveals the edged file's own mentions. `scripts/followthroughs/git-data-replication-signal.sh` (accept → edge for betterstack-emitter-read) exposed its `source betterstack-{read-classify,sources}.sh` lines as new-pairs — real reads that then needed edges too.
3. Fragmented-literal reads are invisible to both the derive extractor and the audit oracle: `test_lint_ratchet.py`'s `(REPO_ROOT/"plugins"/"soleur"/"skills"/rel/"SKILL.md").read_text()` (P1, three seats converged) and `check-deps-adapter-drift`'s `node "$TREE"` on `pen-identity-tree.mjs` were real reads no mechanical scan could see — only reading the SUT finds them.

## Solution

- Edges are decided against the SUT's *dynamic* read set (sweeps, rglobs, workflow run-body replays, `$VAR`-assembled paths), not its literal path mentions. The audit is a completeness check on literal names, not a truth source on reads.
- Accept rows are for name-only mentions; but an accept on a file that a census *evaluates* (ALLOW-map members whose content decides the verdict) is a false negative — the betterstack-emitter-read git-data-replication-signal accept was exactly this and had to become an edge.
- th6 exists-declared census bounds the "new top-level dir" residual — but only for arrays enrolled in it; new whole-tree arrays must be enrolled (and arrays with deliberate skip-sets, like encryption-posture's `.claude`, need exemptions or stay out).

## Session Errors

1. **`git rebase --continue` deadlocked on `git commit -e`** — non-interactive exec has no editor. **Prevention:** always `GIT_EDITOR=true git rebase --continue`.
2. **Edited `test-all-affected.test.sh` while a `--rows` run was executing it** — bash re-read mid-line → spurious syntax error + stale th6 fail. **Prevention:** never edit a file under active test execution; kill/wait first, re-run after.
3. **`.gitignore` edges minted ~442 audit pairs** (the audit reads edged files; pattern files name paths). **Prevention:** before edging a pattern/manifest file, consider what the audit will read and mint; if unaffordable, document the residual and file a follow-up (#11810).
4. **Unqualified `str.replace()` edits hit the wrong array** — deleted `cron-monitors.tf` from betterstack-incident-mirror (same string in two arrays), added `bearer-curl.sh` to check-cloudflare instead of token-drift, and one replace matched zero times silently. **Prevention:** scope replaces to the array block; after every scripted edit, `grep` the target array to confirm the rows landed where intended.
5. **th6 extension added a guaranteed-red row** — encryption-posture's `.claude` skip-set is deliberate SUT parity; a census row without a skip exemption reds every run. **Prevention:** extending a census to an array with a declared skip-set needs a per-suite exemption or the row stays out.

## Key Insight

Edge declarations are dual-cost: they bound under-selection (truth) and mint audit pairs (cost). The correct unit of review is not "does this edge fire" but "does the edge set bound the suite's *behavioral* read set without minting unpayable audit debt." Verdict-input reads (files whose content decides the outcome, including via `--exclude-standard`-style indirection) are the class most easily missed because they never appear as literal path strings in the suite.

## Route-to-definition proposals (recorded, not applied)

- `skills/review` or the index's own header: when a demotion lands whole-tree glob arrays, the review checklist should ask "does the enumeration command in the comment reproduce the committed set?" (`core.quotePath` + `LC_ALL=C` — Cyrillic paths produce a bogus 22nd dir).
- `ci-pr-affected-replay.py` (or its doc): `.gitignore`/pattern files deserve an audit-oracle exemption class (see #11810).

## Tags

category: ci-affected-selection
module: scripts/lib/test-affected-paths.sh, scripts/ci-pr-affected-replay.py
