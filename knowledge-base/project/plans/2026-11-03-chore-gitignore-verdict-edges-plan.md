---
title: "chore: declare .gitignore verdict-input edges for grep-q-pipe-guard.test.sh"
type: chore
date: 2026-11-03
slug: gitignore-verdict-edges
branch: feat-one-shot-11810-gitignore-verdict-edges
issue: 11810
closes: 11810
lane: cross-domain
priority: p3-low
domain: engineering
brand_survival_threshold: none
---

# chore: declare .gitignore verdict-input edges for grep-q-pipe-guard.test.sh

## Overview

`.claude/hooks/grep-q-pipe-guard.test.sh` sweeps the real checkout with `git grep --no-index --exclude-standard` (`sweep_git_grep`, grep-q-pipe-guard.test.sh — `SWEEP_PATHSPEC`) and asserts via `git ls-files -ci --exclude-standard` that no swept file is ignore-hidden (the test-canaries check). A diff that only changes a `.gitignore` can therefore flip the suite's verdict while selecting nothing — a live under-selection gap in the affected-suite index (#11810, deferred from PR #11779 review).

The binding CTO ruling (issue #11810 comment, 2026-11-03) directs: declare `.gitignore` verdict-input edges in `AFFECTED_CLAUDE_HOOKS_GREP_Q_PIPE_GUARD_TEST_SH_PATHS` **only** — the root literal plus one `glob:<top-dir>/**.gitignore` per tracked top-level dir, mirroring the array's existing #11648 whole-tree enumeration — and delete the 10 `.gitignore` accept rows in `scripts/ci-pr-affected-audit.accept.tsv` the edges render stale.

Explicitly excluded by the ruling: edges for `tests/scripts/lint-ratchet` (its three ignore-sensitive calls are unreachable on this repo — `classify_user` returns `SOLEUR` at the `_is_soleur_checkout` early return), issue remedies (a)/(b)/(c) (the ~442-pair blocker does not reproduce — the audit's `code_pats_of` only admits `CODE_EXT` extensions and never reads `.gitignore`), and the `glob:**.gitignore` / `glob:**/.gitignore` shapes (root-anchored arm with `/`-bearing tail → `root-tail-slash` malformed → always-match degrade).

## Problem Statement / Motivation

Under S4 affected-only PR runs, a suite is skipped when no declared or derived edge hits the diff. `grep-q-pipe-guard.test.sh`'s verdict depends on the ignore rules themselves — `--exclude-standard` changes the swept population, and the canary check fails when a tracked swept file becomes ignore-hidden — yet `.gitignore` paths have no edge in its declared set. A `.gitignore`-only PR-mode diff would skip the suite that the diff can fail; the merge_group full battery still runs it, but after queue entry. This is precisely the verdict-input class the edge index exists to cover.

An earlier fix attempt in PR #11779 was reverted on the premise that declaring `.gitignore` edges makes the audit READ each `.gitignore`, minting ~442 accept-required pairs across 22 files. The CTO ruling established that premise is mechanistically impossible under the audit's reach (`code_pats_of`, scripts/ci-pr-affected-replay.py:1376, admits a `^file` pat into the naming walk only when `os.path.splitext(e)[1] in CODE_EXT`; `.gitignore` has no extension, is never a suite input, and cannot be a source hop), and reproduced empirically: byte-identical audit output, only `stale` moving. This session reproduced the ruling on this worktree — see Research Insights.

## Research Insights

### Premise Validation (Phase 0.6)

- `gh issue view 11810 --json state`: **OPEN**, title `chore(11648-followup): .gitignore verdict-input edges for grep-q-pipe-guard + lint-ratchet`, no closing PR. Premise live.
- PR #11779 (MERGED 2026-11-01) is the cited prior attempt; the issue body and the CTO comment carry the deferred scope. All cited paths verified on `origin/main`-equivalent worktree: `scripts/lib/test-affected-paths.sh` (array at `AFFECTED_CLAUDE_HOOKS_GREP_Q_PIPE_GUARD_TEST_SH_PATHS=(`, ~line 2071), `scripts/ci-pr-affected-audit.accept.tsv` (461 lines), `scripts/ci-pr-affected-replay.py` (`code_pats_of`:1376, `CODE_EXT`:1074).
- Collision precheck (`scripts/collision-precheck.sh 11810`): one PR names #11810 — **PR #11955 is this pipeline's own draft on this branch** (not a foreign collision). Foreign `test-all.sh` processes belong to unrelated worktrees.

### Empirical reproduction (this session, worktree HEAD)

- Baseline: `audit --all-refs --accept scripts/ci-pr-affected-audit.accept.tsv` → `SOLEUR_PR_AFFECTED_AUDIT suites=724 always_on=116 audited=608 unaudited=0 gap_suites=252 gap_refs=1512 accepted=234 stale=0 refs=4031 files_read=1203` — identical counters to the CTO's f05eaab78f reproduction baseline.
- Injected the 22 proposed edges (`^.gitignore` + 21 `^glob:<dir>/**.gitignore`) into grep-q's `AFFECTED_SELECTED` edge column in a saved selector-rows file, re-ran `audit --list`: `accepted=233 stale=10`, every other counter identical; the 10 `stale` lines are exactly the 10 grep-q `.gitignore` accept rows (`not-a-gap`).
- Same injection with the 10 rows removed from a scratch accept file: `accepted=233 stale=0`, and the full `--all-refs` output is **byte-identical to baseline except the one summary-line delta** (`accepted: 234 → 233`). Confirms: no pairs are minted, no `.gitignore` file is read, and deleting the 10 rows restores a clean audit.
- lint-ratchet exclusion verified in source: `classify_user` (plugins/soleur/scripts/lint-ratchet.py:1275) returns `SOLEUR` at the `_is_soleur_checkout(root)` early return (line 1279) before the ignore-sensitive `check-ignore` call at line 1344; the suite's only real-root arm (`test_lint_ratchet.py` `test_the_soleur_repository_is_skipped_by_script_identity_without_provisioning`, `lr.classify_user(REPO_ROOT, …)`) exits through that same early return; every other arm runs against `tests/scripts/fixtures/lint-ratchet` scratch repos. The dissent's flip-evidence (a real-root arm reaching `check-ignore`/`--exclude-standard`) does not exist.

### Property List (Phase 0.6b)

- **P1** — A diff touching any tracked (or future-tracked under an existing top-level dir) `.gitignore` selects `.claude/hooks/grep-q-pipe-guard.test.sh` under `--affected`.
- **P2** — No accept row claims a pair the declared edges now cover (`stale=0` on the post-change audit; `ratchet` stays green).
- **P3** — The change widens nothing else: no new suites selected on unrelated diffs; no `.gitignore` pair minted, no `.gitignore` file read by the audit.

### Cut List (Phase 0.6b)

- Edges for `AFFECTED_TESTS_SCRIPTS_LINT_RATCHET_PATHS` → P1 does not hold for that suite (ignore-sensitive calls unreachable; `classify_user` early-returns `SOLEUR`) — **ruled out by CTO**, verified above.
- Remedy (a) bulk accept-rows (~442) → premised on pairs that measurably do not exist — **ruled out by CTO**.
- Remedy (b) teach the audit `.gitignore` lines aren't path mentions → the audit never opens `.gitignore`; nothing to exempt — **ruled out by CTO**.
- Remedy (c) sentinel edge shape → machinery for a phantom blocker — **ruled out by CTO**.
- `glob:**.gitignore` / `glob:**/.gitignore` → `root-tail-slash` malformed → always-match degrade (fail-wide, census RED) — **ruled out by CTO**.
- Extending th6's per-root census to `.gitignore` tails → not asked; the new-top-dir residual is the one the array's own comment already records — deferred (see Non-Goals).

### Relevant file paths and conventions

- `scripts/lib/test-affected-paths.sh` — the declared-edge index. `AFFECTED_CLAUDE_HOOKS_GREP_Q_PIPE_GUARD_TEST_SH_PATHS` spans ~lines 2071–2473; the #11648 whole-tree block ends with root-anchored `glob:*.<ext>` rows (~2454–2472). Append the new block before the closing `)` at ~2473 — new content goes last so a rebase over a sibling registration does not move unrelated rows (array convention, noted at line ~1009).
- `scripts/ci-pr-affected-audit.accept.tsv` — TSV `suite<TAB>path<TAB>anchor<TAB>ordinal<TAB>reason`; the 10 grep-q `.gitignore` rows sit at lines 13–22 (anchors `177450ed8313 1b8002147f10 41fcab8fb458 431de38b8410 69439580879b 75ee73f7f5c2 8a31a0e41298 a705f8fd72eb abb8b449c28d d4491363f3a4`, all ordinal 1). Delete by the (suite, path) pair predicate, not line numbers — anchors shift if a sibling lands first.
- Top-level dirs (21, `git -c core.quotePath=false ls-files | awk -F/ 'NF>1{print $1}' | LC_ALL=C sort -u`): `.agents .claude .claude-plugin .codex .cursor-plugin .devin .github .grok LICENSES apps bin docs infra knowledge-base packages plugins scripts spike test tests todos` — the same set the #11648 block enumerates; write them in this identical order.
- Tracked `.gitignore` files (7): root `​.gitignore`, `apps/cla-evidence/infra/`, `apps/web-platform/`, `apps/web-platform/infra/`, `apps/web-platform/scripts/spike/`, `apps/web-platform/supabase/` (all under `apps/`), `infra/github/` (under `infra/`). The `apps` and `infra` globs are live cover; the other 19 are forward cover for a `.gitignore` added later — mirroring the #11648 glob rows' forward-cover role.
- Edge doctrine (`scripts/lib/affected-glob.sh` `_affected_glob_split`): `glob:apps/**.gitignore` → class `dir` (head `apps/` metachar-free, `*-carrying` tail, no trailing `/`) → mints `^glob:apps/**.gitignore`; `*` crosses `/`, so it matches `.gitignore` at any depth including `apps/.gitignore` itself. Literal `".gitignore"` → `^.gitignore` exact-file edge via `_affected_add_declared_edge`.
- Census enrollment: `lint-orphan-test-suites.sh` declared-member census (~line 1197) requires a `dir`-class glob's head dir to exist (all 21 do) and the literal entry to be tracked (root `.gitignore` is); `test-all-affected.test.sh` th6 census requires every tracked root `.sh`-covered (untouched). No zero-match rule exists for `dir` globs.
- Entry grammar (`scripts/test-all.sh` GLOBENT ~line 2882): `"glob:[A-Za-z0-9_./-]+/[A-Za-z0-9_./*-]*\*[A-Za-z0-9_./*-]*"` — `glob:.agents/**.gitignore` admits (head charset includes `.`; tail `**.gitignore` is `*` + allowed bytes).
- FILES_7376 parity check inside `grep-q-pipe-guard.test.sh` (`unwired_in`, ~line 357): reads the array body with comments dropped and greps for `  "<member>"` whole lines — new rows are inert to it.

### Institutional learnings

- `knowledge-base/project/learnings/2026-10-26-a-ratchet-green-on-the-branch-tip-was-red-on-the-merged-tree.md`: branch-tip ratchet green is not merged-tree green for anchor-keyed artifacts — re-run `ratchet` on the merged tree before arming; the accept file is exactly that artifact class.
- `knowledge-base/project/learnings/test-failures/2026-11-01-ratchet-repair-pair-disposition-moved-echoes-and-sut-source-boundary.md`: run `audit --all-refs` before choosing dispositions (the ratchet report caps ref lines at 3/pair); `--print-baseline` is prune-only.
- `knowledge-base/project/learnings/test-failures/2026-11-01-hot-anchor-accept-rows-are-kept-when-no-expressible-alternative.md`: accept-row disposition turns on mechanism truth, not hot-file limits — here the mechanism (declared edge makes the pair not-a-gap) makes the rows stale, which the ratchet reds; deletion is the designed remedy.
- Runbook `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md`: for index edits, run locally the ratchet, the audit, `test-affected-kb-consumers.test.sh`, `scripts/lib/inngest-probe-row.test.sh` and the replay suite; a paths-lib edit degrades `--affected` to the full battery (`runner-changed` fallback), so the full local gate runs detached and CI's `test` context is the merge gate.

### External research

Skipped (Phase 1.6): repo-internal CI tooling with strong local doctrine and a binding CTO ruling; no external surface.

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Codebase reality | Plan response |
|---|---|---|
| ".gitignore edges make the audit READ each .gitignore; every pattern line mints a pair (~442 live pairs across 22 files)" | `code_pats_of` admits only `CODE_EXT` `^file` pats; `.gitignore` mints zero pairs. Empirically: audit output byte-identical except `stale`/`accepted`. Reproduced both by the CTO at f05eaab78f and in this session. | Implement the edges; delete the 10 stale accept rows; implement no remedy. |
| "22 [`.gitignore`] files" | 7 tracked `.gitignore` files (`git ls-files \| grep '\.gitignore$'`). | Edges cover all 7 plus forward cover per top-level dir. |
| "lint-ratchet uses `check-ignore`/`--exclude-standard` in `classify_user`" | True in source, but unreachable: `classify_user` early-returns `SOLEUR` on this repo (`_is_soleur_checkout`), and every suite arm drives fixture roots. | No lint-ratchet edges; its 5 `.gitignore` accept rows stay. |
| `.gitignore` diffs have "no edge" for grep-q | Confirmed: `AFFECTED_CLAUDE_HOOKS_GREP_Q_PIPE_GUARD_TEST_SH_PATHS` contains no `.gitignore` member today. | This plan adds the edge set. |

## Proposed Solution

Two files change, nothing else:

1. **`scripts/lib/test-affected-paths.sh`** — inside `AFFECTED_CLAUDE_HOOKS_GREP_Q_PIPE_GUARD_TEST_SH_PATHS`, append a commented block after the root-anchored `glob:*.<ext>` rows, before the closing `)`:

   ```bash
     # --- #11810: .gitignore verdict-input edges. sweep_git_grep runs
     # `git grep --no-index --exclude-standard` and the test-canaries check
     # runs `git ls-files -ci --exclude-standard` over the real checkout, so a
     # .gitignore-only diff can flip this suite's verdict while selecting
     # nothing. Root literal plus one dir-anchored glob per tracked top-level
     # dir, mirroring the #11648 whole-tree enumeration above. Do NOT use
     # `glob:**.gitignore` / `glob:**/.gitignore` — a root-anchored arm with a
     # /-bearing tail classifies root-tail-slash and degrades to always-match.
     # A .gitignore under a NEW top-level dir stays uncovered until
     # re-enumerated — the same residual the #11648 comment records.
     ".gitignore"
     "glob:.agents/**.gitignore"
     "glob:.claude/**.gitignore"
     "glob:.claude-plugin/**.gitignore"
     "glob:.codex/**.gitignore"
     "glob:.cursor-plugin/**.gitignore"
     "glob:.devin/**.gitignore"
     "glob:.github/**.gitignore"
     "glob:.grok/**.gitignore"
     "glob:LICENSES/**.gitignore"
     "glob:apps/**.gitignore"
     "glob:bin/**.gitignore"
     "glob:docs/**.gitignore"
     "glob:infra/**.gitignore"
     "glob:knowledge-base/**.gitignore"
     "glob:packages/**.gitignore"
     "glob:plugins/**.gitignore"
     "glob:scripts/**.gitignore"
     "glob:spike/**.gitignore"
     "glob:test/**.gitignore"
     "glob:tests/**.gitignore"
     "glob:todos/**.gitignore"
   ```

2. **`scripts/ci-pr-affected-audit.accept.tsv`** — delete the 10 rows where `suite==​.claude/hooks/grep-q-pipe-guard.test.sh` and `path==​.gitignore` (currently lines 13–22; match on the pair, not line numbers). Leave the 5 `tests/scripts/lint-ratchet` `.gitignore` rows and every other row untouched.

## Technical Considerations

- **Why edges and not accept/baseline:** the suite really reads the ignore semantics (the `--exclude-standard` sweep population and the hidden-file verdict both change with a `.gitignore` diff), so per the runbook's declare-vs-accept rule an accept row on a real verdict input is the false negative this PR removes — the 10 rows were accurate when the suite merely *named* `.gitignore`-adjacent fixture text; once the edges land they are `stale` (`not-a-gap`) and must go.
- **Entry spelling:** the array member is written `".gitignore"` (literal file → mints `^.gitignore`) and `"glob:<dir>/**.gitignore"` (dir-anchored glob → mints `^glob:<dir>/**.gitignore`). The `^` forms shown in the ruling are the *minted* edge strings, not the array spellings.
- **Mint verification:** `bash scripts/test-all.sh --print-selection --paths=README.md` prints the suite's `AFFECTED_SELECTED` row; its edge column must contain `^.gitignore` and all 21 `^glob:<dir>/**.gitignore` tokens.
- **Oracle-input notice expected:** both edited files are in `RATCHET_ORACLE` (ci-pr-affected-replay.py:~1747), so the `affected-index-ratchet` job will emit the `oracle-inputs-changed:` warning on this PR — expected, not a defect; the job is advisory (`continue-on-error`) but `ratchet` must exit 0.
- **Runner-changed fallback:** a diff to `scripts/lib/test-affected-paths.sh` degrades `--affected` selection to the full battery for this PR (documented at the lib's SELF-INCLUSION note); local `--affected` verification is still valid because `--print-selection` prints the minted edges directly.
- **Rebase hygiene:** accept rows are anchor-keyed (12-hex content hash of the mention line). If main edits any of the ten host lines before merge, the surviving rows' anchors could go `anchor-not-live` — re-run `audit --all-refs` on the merged tree before arming (the 2026-10-26 learning).
- **Residual (accepted, documented):** a `.gitignore` under a *new* top-level dir is uncovered until the enumeration is refreshed — identical to the residual the #11648 comment already records; the th6 census bounds `.sh` tails only, not `.gitignore`.

## Non-Goals

- Edges for `tests/scripts/lint-ratchet` / `AFFECTED_TESTS_SCRIPTS_LINT_RATCHET_PATHS` (ruled out; ignore-sensitive calls unreachable on this repo — `classify_user` SOLEUR early return).
- Issue remedies (a) bulk accept-rows, (b) audit oracle change, (c) sentinel edge shape — all ruled out.
- Any `glob:**.gitignore` / `glob:**/.gitignore` member anywhere in the edge index (malformed → always-match).
- Baseline (`ci-pr-affected-audit.baseline.tsv`) edits — `--print-baseline` is prune-only and no grep-q `.gitignore` baseline rows exist.
- Extending the th6 census to `.gitignore` tails or any other census/test-authoring change — the ruling keeps the existing residual.
- Suite changes to `grep-q-pipe-guard.test.sh` itself — the FILES_7376 parity check is inert to non-FILES_7376 members.

## Implementation Phases

### Phase 1 — Edge declaration (scripts/lib/test-affected-paths.sh)

- 1.1 Append the `.gitignore` block (comment + `".gitignore"` + 21 `glob:` rows, order per the #11648 enumeration) immediately before the array's closing `)`.
- 1.2 Mint check: `bash scripts/test-all.sh --print-selection --paths=README.md` → grep-q's `AFFECTED_SELECTED` edge column carries `^.gitignore` + all 21 `^glob:` tokens, no `^glob:**` malformed verbatim.
- 1.3 Selection check: `--print-selection --paths=.gitignore`, `--paths=apps/web-platform/.gitignore`, `--paths=infra/github/.gitignore` each show `AFFECTED_SELECTED … 1` for the suite; `--paths=README.md` keeps its current verdict for the suite (must-PASS non-canonical input).

### Phase 2 — Accept-row deletion (scripts/ci-pr-affected-audit.accept.tsv)

- 2.1 Delete the 10 `(​.claude/hooks/grep-q-pipe-guard.test.sh, .gitignore)` rows via the pair predicate (`awk -F'\t' '!($1==".claude/hooks/grep-q-pipe-guard.test.sh" && $2==".gitignore")'`), writing back in place. Assert exactly 10 rows removed (`wc -l` 461 → 451).
- 2.2 Assert the 5 `tests/scripts/lint-ratchet` `.gitignore` rows and all other rows are untouched (`git diff` on the file shows only deletions of the 10 anchors listed in Files to Edit).

### Phase 3 — Verification battery (ruling's prescribed checks + runbook suite set)

- 3.1 `python3 -I scripts/ci-pr-affected-replay.py audit --all-refs --accept scripts/ci-pr-affected-audit.accept.tsv` → `stale=0`, `accepted=233`, all other summary counters identical to the pre-edit baseline (`suites=724 always_on=116 audited=608 unaudited=0 gap_suites=252 gap_refs=1512 refs=4031 files_read=1203`); no `gap`/`ref`/`unaudited`/`stale` line mentioning `.gitignore` or the suite.
- 3.2 `python3 -I scripts/ci-pr-affected-replay.py ratchet` → exit 0 (`SOLEUR_PR_AFFECTED_RATCHET exit=0`).
- 3.3 `bash scripts/lint-orphan-test-suites.sh` → exit 0 (declared-member census enrollment of the new rows).
- 3.4 `bash scripts/test-all-affected.test.sh` → exit 0 (th6 exists-declared census + probes).
- 3.5 `bash scripts/test-affected-kb-consumers.test.sh`, `bash scripts/lib/inngest-probe-row.test.sh`, `bash plugins/soleur/test/ci-pr-affected-replay.test.sh` → exit 0 (runbook suite set for index edits).
- 3.6 `bash .claude/hooks/grep-q-pipe-guard.test.sh` → exit 0 (subject suite green; it runs ~16 s).
- 3.7 lint-ratchet flip-evidence re-check: `grep -n 'classify_user(REPO_ROOT\|check-ignore\|exclude-standard' tests/scripts/test_lint_ratchet.py` — confirm the only real-root arm is the SOLEUR-early-return assertion; if a real-root `check-ignore`/`--exclude-standard` arm exists, edge lint-ratchet identically and delete its 5 rows (the ruling's dissent clause).

## Files to Edit

- `scripts/lib/test-affected-paths.sh` — append the 22-member `.gitignore` block (comment + `".gitignore"` + `glob:<dir>/**.gitignore` × 21) inside `AFFECTED_CLAUDE_HOOKS_GREP_Q_PIPE_GUARD_TEST_SH_PATHS`, before its closing `)` (~line 2473).
- `scripts/ci-pr-affected-audit.accept.tsv` — delete 10 rows (anchors `177450ed8313`, `1b8002147f10`, `41fcab8fb458`, `431de38b8410`, `69439580879b`, `75ee73f7f5c2`, `8a31a0e41298`, `a705f8fd72eb`, `abb8b449c28d`, `d4491363f3a4`, all `(​.claude/hooks/grep-q-pipe-guard.test.sh, .gitignore)` ordinal 1).

## Files to Create

None.

## User-Brand Impact

- **If this lands broken, the user experiences:** a wrong affected-selection verdict — a `.gitignore`-only PR-mode diff either silently skips `grep-q-pipe-guard.test.sh` (the defect this fixes) or selects it on unrelated diffs (a malformed glob spelling); the merge_group full battery is the backstop, so the observable artifact is a red merge-queue run or wasted CI minutes, not shipped product behavior.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no data exposure surface — the change alters which test suite a diff selects; worst case is CI cost (selection) or a delayed verdict (under-selection caught at merge_group).
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** internal CI-selection metadata for one hook suite; no user-facing surface, no data, and the merge_group full battery bounds the failure to a red check — `single-user incident` would require a user-visible artifact, which this change does not produce.

## Guard Contract

The deliverable modifies the declared-edge set of the affected-selection gate (and deletes rows from the ratchet's accept oracle) — the guard under test is the edge set's completeness over the `.gitignore` diff surface.

### Guard 1 — grep-q `.gitignore` verdict-input edges

**Property.** Every diff that adds, edits or deletes a tracked `.gitignore` — at the repo root or under any of the 21 tracked top-level dirs — selects `.claude/hooks/grep-q-pipe-guard.test.sh`, and no member of the new block selects a diff that touches no `.gitignore`.

**Assembly.** (a) The 22-member block in `AFFECTED_CLAUDE_HOOKS_GREP_Q_PIPE_GUARD_TEST_SH_PATHS` (scripts/lib/test-affected-paths.sh); (b) the mint arms `_affected_add_declared_edge` and `_affected_glob_split` (scripts/lib/affected-glob.sh), the single chokepoint every declared member flows through; (c) the selection predicate `edge_hit` in `scripts/test-all.sh` `_diff_edge_hit` and its Python mirror in `scripts/ci-pr-affected-replay.py` (bash/Python parity pinned by the differential row); (d) the census enrollment — `lint-orphan-test-suites.sh` declared-member arm (malformed-shape and dead-edge checks) and `test-all-affected.test.sh` th6; (e) the ratchet oracle — `ci-pr-affected-audit.accept.tsv` rows for the same (suite, path) pair.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Drop `glob:apps/**.gitignore` → `--paths=apps/web-platform/.gitignore` selects the suite with `selected=0` (assembly narrowing — the property fails on the dir holding 5 of 7 tracked `.gitignore` files) | RED |
| 2 | Drop the literal `".gitignore"` entry → `--paths=.gitignore` selects the suite with `selected=0` (guard's own first member missing — a set that silently covers only nested dirs) | RED |
| 3 | Spell `glob:**.gitignore` instead of the 21 dir rows → `_affected_glob_split` classifies `root-tail-slash` → mints `^glob:<verbatim>` always-match (every diff selects) AND `lint-orphan-test-suites.sh` census prints the malformed member RED | RED |
| 4 | Keep one of the 10 accept rows → `audit` prints `stale	…/.gitignore	…	not-a-gap` and `ratchet` exits 1 `stale-accept` (harness's own oracle detects the row the edges retire) | RED |
| 5 | `--paths=README.md` (a non-`.gitignore` input the contract permits to decline the suite via these edges) → the 22 new edges contribute no hit; the suite's verdict is decided by its pre-existing edges alone | must-PASS |
| 6 | Second-member row: with `glob:apps/**.gitignore` compliant, add `glob:plugins/**.gitignore` coverage probe — `--paths=plugins/soleur/x/.gitignore` selects the suite (a check that stopped at the first member is the defect itself) | RED-if-absent |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "declare `.gitignore` verdict-input edges for `.claude/hooks/grep-q-pipe-guard.test.sh` ONLY — `^.gitignore` plus `glob:<top-dir>/**.gitignore` for each of the 21 top-level dirs (mirroring the existing `AFFECTED_CLAUDE_HOOKS_GREP_Q_PIPE_GUARD_TEST_SH_PATHS` whole-tree enumeration)" | Phase 1 / Files-to-Edit `scripts/lib/test-affected-paths.sh` | mapped |
| 2 | "delete the 10 `.gitignore` accept rows the edges render stale" | Phase 2 / Files-to-Edit `scripts/ci-pr-affected-audit.accept.tsv` | mapped |
| 3 | "Do NOT edge `tests/scripts/lint-ratchet` … its 5 `.gitignore` accept rows are accurate and stay" | Non-Goals + Phase 3.7 flip-evidence check | mapped |
| 4 | "Do NOT implement issue remedies (a)/(b)/(c)" | Non-Goals | mapped |
| 5 | "Constraint: `glob:**.gitignore` / `glob:**/.gitignore` must NOT be used (root-anchored arm with `/`-bearing tail degrades to always-match)" | Non-Goals + Guard Contract row 3 | mapped |
| 6 | "re-run `audit --all-refs` (or the suite's audit invocation) and confirm only expected deltas (the 10 stale-row deletions)" | Phase 3.1 / AC-3 | mapped |
| 7 | "verify the array's exists-declared census enrollment covers the new glob rows" | Phase 3.3–3.4 / AC-6–7 | mapped |
| 8 | "a `.gitignore` under a NEW top-level dir stays uncovered — same residual the array's own comment records" | Technical Considerations residual bullet + array comment in Phase 1.1 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `scripts/lib/test-affected-paths.sh` edit | "`^.gitignore` plus `glob:<top-dir>/**.gitignore` for each of the 21 top-level dirs" | asked |
| `scripts/ci-pr-affected-audit.accept.tsv` edit | "delete the 10 `.gitignore` accept rows the edges render stale" | asked |
| Phase 3 verification battery (ratchet, censuses, suite set) | "re-run `audit --all-refs` (or the suite's audit invocation)" + "verify the array's exists-declared census enrollment" | asked (ruling checks); extended by runbook's index-edit suite set — `ci-pr-affected-activation.md` "Run the ratchet, the audit, test-affected-kb-consumers.test.sh, scripts/lib/inngest-probe-row.test.sh and the replay suite locally" |
| Comment block inside the array | — | inferred — justification: the array's convention documents each declared set's residual inline (the #11648 comment does); the ruling requires recording the same residual for `.gitignore` ("same residual the array's own comment records") |

### Split Assessment

- Subsystems touched: 1 — `scripts/` (both files under `scripts/`; `scripts/lib/` shares the `scripts` root)
- Planned files: 2 | Estimated changed lines: ~33 (+23 block lines, −10 accept rows)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md — headless pipeline, checked against issue/ruling text -->

- [ ] `AFFECTED_CLAUDE_HOOKS_GREP_Q_PIPE_GUARD_TEST_SH_PATHS` in `scripts/lib/test-affected-paths.sh` contains, in a commented block, the literal `".gitignore"` and exactly one `glob:<top-dir>/**.gitignore` row for each of the 21 roots printed by `git -c core.quotePath=false ls-files | awk -F/ 'NF>1{print $1}' | LC_ALL=C sort -u` (`.agents .claude .claude-plugin .codex .cursor-plugin .devin .github .grok LICENSES apps bin docs infra knowledge-base packages plugins scripts spike test tests todos`), in that order.
- [ ] No `glob:**.gitignore` or `glob:**/.gitignore` member exists anywhere in `scripts/lib/test-affected-paths.sh` (`grep -n 'glob:\*\*' scripts/lib/test-affected-paths.sh` returns nothing for the new block; `_affected_glob_split` classifies every new member `dir`).
- [ ] `scripts/ci-pr-affected-audit.accept.tsv` holds zero rows matching `suite==​.claude/hooks/grep-q-pipe-guard.test.sh` and `path==​.gitignore` (the 10 anchors in Files-to-Edit are gone; file length 461 → 451), and the 5 `(tests/scripts/lint-ratchet, .gitignore)` rows remain.
- [ ] `python3 -I scripts/ci-pr-affected-replay.py audit --all-refs --accept scripts/ci-pr-affected-audit.accept.tsv` prints `stale=0` and `accepted=233` with `suites=724 always_on=116 audited=608 unaudited=0 gap_suites=252 gap_refs=1512 refs=4031 files_read=1203` unchanged vs the measured baseline; no `gap`/`ref`/`unaudited`/`stale` output line names `.gitignore` or the suite. (Exit 1 is expected — 252 baselined gap suites remain; the green check is `ratchet`.)
- [ ] `python3 -I scripts/ci-pr-affected-replay.py ratchet` exits 0 (the `oracle-inputs-changed:` notice for the two edited files is expected and acceptable).
- [ ] `bash scripts/test-all.sh --print-selection --paths=README.md` prints grep-q's `AFFECTED_SELECTED` edge column containing `^.gitignore` and `^glob:apps/**.gitignore` (and no `^glob:**` verbatim token); `--paths=.gitignore`, `--paths=apps/web-platform/.gitignore`, and `--paths=infra/github/.gitignore` each print `AFFECTED_SELECTED	.claude/hooks/grep-q-pipe-guard.test.sh	1`.
- [ ] `bash scripts/lint-orphan-test-suites.sh` exits 0 — the declared-member census enrolls all 22 new members (each `dir`-class glob's head exists; the literal is tracked).
- [ ] `bash scripts/test-all-affected.test.sh` exits 0 — th6's per-root `.sh` cover and all behavioral probes pass with the new members present.
- [ ] `bash scripts/test-affected-kb-consumers.test.sh`, `bash scripts/lib/inngest-probe-row.test.sh`, `bash plugins/soleur/test/ci-pr-affected-replay.test.sh`, and `bash .claude/hooks/grep-q-pipe-guard.test.sh` all exit 0.
- [ ] `AFFECTED_TESTS_SCRIPTS_LINT_RATCHET_PATHS` is byte-identical to `origin/main` (no lint-ratchet edge added); no new accept row exists for `tests/scripts/lint-ratchet`; the Phase 3.7 grep finds no real-root arm reaching `check-ignore`/`--exclude-standard` (if it does, the ruling's dissent clause fires — see that phase).
- [ ] `git diff origin/main` touches exactly the two Files-to-Edit paths (plus planning artifacts under `knowledge-base/project/`).

Note: spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change: two data files under `scripts/` governing which CI suite a diff selects. Mechanical UI-surface override check: `## Files to Edit`/`## Files to Create` contain no `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`, or any ui-surface glob match → Product/UX gate not triggered (NONE tier). Domain-leader fan-out not run: headless pipeline, and the assessment is `none` for all business domains.

## Open Code-Review Overlap

None — queried `gh issue list --label code-review --state open --limit 200` bodies for `scripts/lib/test-affected-paths.sh`, `scripts/ci-pr-affected-audit.accept.tsv`, `ci-pr-affected-replay.py`, `grep-q-pipe-guard`: zero matches.

## Test Scenarios

- Given the new block is declared, when `bash scripts/test-all.sh --print-selection --paths=.gitignore` runs, then the suite's `AFFECTED_SELECTED` bit is `1` (unit — selector edge hit; pyramid label `integration` since it exercises the real runner).
- Given `glob:apps/**.gitignore` is declared, when `--print-selection --paths=apps/web-platform/supabase/.gitignore` runs, then selected bit `1` (nested-depth match — `*` crosses `/`).
- Given only a non-`.gitignore` diff (`--paths=README.md`), when selection runs, then the new edges contribute no hit to the suite's verdict (must-PASS non-canonical input — the suite's selection remains decided by its pre-existing edges).
- Given the edges are declared and the 10 accept rows deleted, when `audit --all-refs` runs, then `stale=0`, `accepted=233`, and every `ref`/`gap`/`unaudited` line is byte-identical to baseline (integration — the ruling's "only expected deltas" check).
- Given a sibling merges a `.gitignore` mention-line edit to one of the ten host files after this branch, when the merged tree is audited before arming, then any `anchor-not-live` on a *remaining* accept row surfaces as `stale` (per the 2026-10-26 learning — re-run on the merged tree; this PR deletes rather than adds anchors, so the residual risk is on other suites' rows, not these).

## Context

- Issue: #11810 (`chore(11648-followup): .gitignore verdict-input edges for grep-q-pipe-guard + lint-ratchet`); binding CTO ruling: issue comment of 2026-11-03 (`issuecomment-6597435507`).
- Prior art: #11648 demotion spec `knowledge-base/project/specs/archive/20261101-205920-feat-one-shot-11648-fast-tier-demotion/`; the whole-tree enumeration this block mirrors; runbook `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md`.
- This PR's diff touches `scripts/lib/test-affected-paths.sh` → the `--affected` gate degrades to the full battery (`runner-changed`), so CI runs everything regardless; the local `--print-selection` checks still verify the minted edges.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6 — filled above.
- **Write the glob rows literally.** `glob:**.gitignore` / `glob:**/.gitignore` classify `root-tail-slash` → always-match `^glob:<verbatim>` — a silent widen that only the census REDs; spell each row `glob:<dir>/**.gitignore`.
- **Delete accept rows by pair predicate, not line range** — sibling merges shift line numbers; the 10 rows are identified by `(​.claude/hooks/grep-q-pipe-guard.test.sh, .gitignore)`, and the file must end at 451 lines.
- **Audit exit code is 1 by design** while baselined gaps remain — judge the run on the summary counters (`stale=0 accepted=233`) and `ratchet` exit 0, not on the audit's raw rc.
- **Do not "fix" `accepted=233`** — the delta vs baseline (234→233) is the exempted-pair count dropping by exactly one (the grep-q `.gitignore` pair), the ruling's expected delta.
- **Stale anchors are branch-relative** — re-run the audit/ratchet on the merged tree before arming if siblings landed on the accept file's host lines.
- **The suite file itself is untouched** — `unwired_in`'s parity check greps only FILES_7376 members; adding array members needs no `PIN_7376` update.

## Enhancement Summary

### Deepen-plan gate results (2026-11-03, run inline — no agent spawn tool in this session)

- **Phase 4.4 Precedent-diff:** pattern-bound shape exists — the #11648 `glob:<dir>/**.<ext>` whole-tree enumeration in the same array; the new block mirrors it verbatim (21-dir ordering, comment style, forward-cover role). No novel pattern.
- **Phase 4.45 verify-the-negative:** every negative claim in the plan was re-verified against repo state, not memory — `code_pats_of` `CODE_EXT` exclusion (ci-pr-affected-replay.py:1074,1376), `_is_soleur_checkout` early return (lint-ratchet.py:1224–1281), zero `.gitignore` members in the array, zero `(grep-q|lint-ratchet, .gitignore)` baseline rows, and the 4-line total audit delta measured live.
- **Phase 4.6 User-Brand Impact:** PASS — section present, `none` threshold with decision line; no sensitive-path files (`scripts/lib/test-affected-paths.sh`, `scripts/ci-pr-affected-audit.accept.tsv` match no `SENSITIVE_PATH_RE` arm).
- **Phase 4.7 Observability:** SKIP — no file under `apps/*/server|src|infra` or `plugins/*/scripts`, no new infrastructure surface.
- **Phase 4.8 PAT-shaped variable:** PASS — zero matches.
- **Phase 4.9 UI-wireframe:** SKIP — no UI-surface files.
- **Phase 4.10 Encryption Posture:** SKIP — no `.tf`/`.sql`/cloud-init/docker-compose file, no store class.
- **Phase 4.11 Guard Contract:** PASS — `lint-guard-contract.py` reports 1 guard entry, zero FAILs; Assembly names the mint chokepoint (`_affected_add_declared_edge`/`_affected_glob_split`/`edge_hit`) + census + ratchet oracle, not a member snapshot; 6 mutation rows incl. own-dispatch (row 2), malformed-degrade (row 3), oracle self-detection (row 4), must-PASS (row 5), second-member (row 6).
- **Phase 4.12 Scope Check:** PASS — exactly one `## Scope Check`; all 8 ruling asks mapped, two file items `asked`, verification battery `asked` (ruling checks + runbook suite set), one `inferred` item (array comment) with justification; split assessment single PR.
- **Phase 4.13 Task Design:** SKIP — no new autonomous-task surface (no workflow/cron/registration/check).
- **Phases 2/3/4/5 (skill, learnings, per-section research, review agents):** executed inline (no Task spawn tool available in this Devin session). Learnings folded in: ratchet-green-vs-merged-tree (2026-10-26), moved-echo accept-row repair (2026-11-01), hot-anchor accept rows (2026-11-01), the runbook's index-edit suite set.

### Key improvements from deepening

- Empirical end-state proof landed in Research Insights: baseline → edges-only → edges+deletion audit counters measured in-session (`accepted 234→233`, `stale 0`, all else byte-identical), so Phase 3.1 verifies against *measured* numbers rather than asserted ones.
- `AFFECTED_TESTS_SCRIPTS_LINT_RATCHET_PATHS` byte-identity AC added (AC row 10) so the "do NOT edge lint-ratchet" half of the ruling is mechanically asserted, not just prose.
- Guard Contract row 4 pins the harness's own oracle (a kept accept row → `stale`/`stale-accept` RED) — the deletion is verified by the gate it retires, not by inspection.

## References

- Issue: [#11810](https://github.com/jikig-ai/soleur/issues/11810) — [CTO ruling comment](https://github.com/jikig-ai/soleur/issues/11810#issuecomment-6597435507)
- Prior PR: #11779 (merged 2026-11-01) — the demotion that made this suite edge-selected and surfaced this gap
- `scripts/ci-pr-affected-replay.py` (`audit`, `ratchet` subcommands; `code_pats_of`, `CODE_EXT`)
- `scripts/lib/affected-glob.sh` (`_affected_glob_split` — the glob-shape doctrine)
- `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md`
