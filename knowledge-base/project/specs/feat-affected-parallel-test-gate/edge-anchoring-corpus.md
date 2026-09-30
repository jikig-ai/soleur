# Edge-anchoring corpus record (PR 1, umbrella #9307)

Plan Phase 1 step 5: anchoring changes how every derived/declared/consumed edge matches, so the
selection is compared old-vs-new over a corpus of real diffs, and every suite that stops being
selected must be a demonstrated false positive.

## Method

- **Corpus:** the last 30 first-parent commits on `origin/main` as of 2026-09-30
  (`git log --first-parent --name-only --format='@@%H' -30 origin/main`), one diff per commit.
- **Edge sets:** dumped from the real runner, not reconstructed. A scratch copy of `scripts/test-all.sh`
  with suite execution neutered and a `printf` after `_affected_classify` wrote one
  `label<TAB>class<TAB>edges` row per registration (533 rows: 145 `always_on`, 93 `edge:declared`,
  295 `edge:derived`) under a forced `README.md` diff. Edges are the anchored form (`^dir/`, `^file`).
- **Old semantics:** an edge selects when it is a substring of any diff line. The old edge is
  recovered from the new one by dropping `^` and a trailing `/`. That is the *widest* plausible old
  edge (a directory argv given as `plugins/soleur/` was stored slash-terminated and matched less), so
  the "stops being selected" list below is an upper bound on what anchoring removed.
- **New semantics:** `^dir/` selects when a diff line starts with `dir/`; `^file` when a diff line
  equals `file`; an unanchored edge (`.`/`..`/`./`/`../` rooted) keeps the substring match.
- **Always-on suites** (145) are selected under both and are excluded from the comparison.

## Result

| Measure | Old | New |
|---|---|---|
| Edge-suite selections across the 30 diffs | 1663 | 1579 |
| Selections present only under the new matcher | | **0** |
| Distinct suites that stop being selected in at least one diff | | 7 |

Anchoring never widens selection (0 new-only selections). The 84 dropped selections belong to 7 suites:

| Suite | Diffs dropped | Edge | Example path that no longer selects it | Verdict |
|---|---|---|---|---|
| `test/content-publisher` | 19 | `^test/` | `.claude/hooks/memory-backstop.test.sh` | false positive: the path only contains the word `test`; the suite's root is `test/` |
| `test/x-community` | 19 | `^test/` | `.claude/hooks/memory-backstop.test.sh` | false positive (same) |
| `test/linkedin-community` | 19 | `^test/` | `.claude/hooks/memory-backstop.test.sh` | false positive (same) |
| `test/pre-merge-rebase` | 18 | `^test/` | `.claude/hooks/memory-backstop.test.sh` | false positive (same) |
| `plugins/soleur` | 7 | `^test/` | `apps/web-platform/test/components/inbox/email-triage-row.test.tsx` | false positive: a nested `test/` is not the repo-root `test/`; its real edge `^plugins/soleur/` is unaffected |
| `tests/scripts/destroy-guard-counter-github` | 1 | `^infra/github/` | `apps/web-platform/infra/github-app-runtime-project.tf` | false positive: the suite guards the repo-root `infra/github/`; `apps/web-platform/infra/github-app-...` is a different directory that only contains the substring |
| `plugins/soleur/skills/review/test/emit-review-trailer.test.sh` | 1 | `^scripts/` | `.github/scripts/test/fixtures-validate-infra-templates.sh` | false positive: `.github/scripts/` is not the repo-root `scripts/` |

No suite lost a selection it had a real edge for. The five `test/` rows are the false positive this
PR exists to remove; the last two are the same class (a directory token matched inside a longer path).

## Reproduce

```bash
git log --first-parent --name-only --format='@@%H' -30 origin/main > corpus.txt
# patch a scratch copy of scripts/test-all.sh: neuter the `"$@" || rc=$?` line, add a
# diff seam before `_diff_touches() {`, and print "$_AC_CLASS" and "${_AC_EDGES[*]}" after
# the `_affected_classify` call in the pre-pass; run it with --affected; then evaluate the
# old and new match per (suite, diff) offline.
```

The committed regression rows for this behavior are `t1`-`t6` and mutants `m1`-`m3` in
`scripts/test-all-affected.test.sh`.

## Follow-up found while proving the `test/` rows (same PR)

Anchoring alone still left `^test/` as an edge of the five `bun test <file>` suites, so any diff
under root `test/` selected all five. The word is the runner's SUBCOMMAND, not an operand, so
`_affected_derive` now skips `test` after `bun|npm|pnpm|yarn|go|cargo` (rows t7 / m5).

Removing it exposed that three of the five (`test/x-community`, `test/linkedin-community`,
`test/content-publisher`) had no real edge at all: the bogus edge had been making them look
classified while selecting them only when a diff path happened to contain "test", and NOT when their
SUT changed. They now declare their SUT (`plugins/soleur/skills/community/scripts/`,
`scripts/content-publisher.sh`, their helpers) in `scripts/lib/test-affected-paths.sh`;
`test/pre-merge-rebase` already declared its hook, and `plugins/soleur` keeps its own
`^plugins/soleur/` edge. `bash scripts/lint-orphan-test-suites.sh` reports 580 covered, 0 orphaned.
