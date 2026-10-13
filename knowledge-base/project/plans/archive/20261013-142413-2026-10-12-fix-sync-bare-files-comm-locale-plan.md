---
title: "fix: sync_bare_files prune step deletes tracked files under a non-C locale"
date: 2026-10-12
slug: fix-sync-bare-files-comm-locale
branch: fix-sync-bare-files-comm-locale
issue: none
type: fix
lane: single-domain
brand_survival_threshold: none
---

# fix: sync_bare_files prune step deletes tracked files under a non-C locale

## Enhancement Summary

**Deepened on:** 2026-10-12
**Passes:** plan-review panel (code-simplicity, Kieran-style correctness, DHH-style critique), five CTO forks, deepen-plan halt gates 4.6, 4.7, 4.8, 4.9 (no UI), 4.10 (no store), 4.11, 4.12. A 40-agent generic fan-out was not run: this is a bash fix with a single-file blast radius and the design forks were already ruled by the CTO.

### Key Improvements

1. Scope Check rewritten to the mandatory three-table schema (a missing Ask Mapping would have halted deepen-plan 4.12).
2. Ceiling re-aimed from the candidate set (3568 legitimate lines) to the to-remove list; abort-all on any tracked hit.
3. Test surface merged from nine arms to five (F0 sensitivity guard, F1 per-locale, F5 ceiling, F7 census, F8 injected ordering bug) after plan-review.
4. Redundant quoted-line skip branch removed (the `-f`/`-L` on-disk check already discards git-quoted spellings).

### Gate results

- 4.6 User-Brand Impact: present, threshold `none`, scope-out line present (the diff touches `apps/web-platform/infra/`, a sensitive path).
- 4.7 Observability: present; `discoverability_test.command` starts with `grep` (allowlisted), runs in milliseconds, `expected_output` is the literal `1`.
- 4.8 PAT-shaped variable sweep: no hits. 4.9/4.10: not triggered (no UI surface, no store or connection).
- 4.11 Guard Contract: `python3 scripts/lint-guard-contract.py` green (2 guard entries); assembly is structural (single `rm` chokepoint, population derived from `git ls-files`).
- 4.12 Scope Check: one unfenced section, three subsections, no `unmapped`, every `inferred` row justified.

### New Considerations Discovered

- A candidate-set ceiling of ~2000 (as worded in the ask) would abort every legitimate prune, because the correct candidate set is 3568 lines today.
- The fixture must be calibrated, not hand-picked: a 5-path fixture does not reproduce the warning at all, and the hit rate for emitting `marketplace.json` specifically is chance-based; F0 asserts the warning plus any tracked path so collation-version drift cannot flake it.

## Overview

The prune step of `sync_bare_files()` in `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`
(called by `sync`, `sync-bare-files` and the tail of `cleanup-merged`) compares two path lists with
`comm`. Both inputs are sorted with `LC_ALL=C`, but `comm` itself runs in the user's locale
(`en_US.UTF-8`). It then prints `comm: file 1 is not in sorted order` / `input is not in sorted order`
and returns a wrong difference, so paths that ARE tracked at HEAD are removed from the bare root,
including `.claude-plugin/marketplace.json`. With that file gone the `soleur` marketplace fails to load
(`cache-miss`) and `claude plugin update soleur@soleur` reports the plugin as not found. The break is
silent and recurs after every `cleanup-merged`.

Measured on this repo today (read-only, scratch files in the session scratchpad, bare root untouched):
history candidate list 22322 lines, HEAD list 18754 lines; `comm -23` gives **3568** under `LC_ALL=C`
and **4766** under `en_US.UTF-8` with three "not in sorted order" warnings. 4766 - 3568 = **1198**,
exactly the "Removed 1198 stale tracked-deleted file(s)" the bare root reported. In the en_US output
`.claude-plugin/marketplace.json` is line 5.

Second defect, same line: `git log --name-only` and `git ls-tree` quote non-ASCII paths by default
(`core.quotePath=true`), e.g. `"knowledge-base/specs/verify-canus\320\265\321\202ool-caching-876/..."`.
Both sides quote identically so the compare is consistent, but the quoted spelling never exists on
disk, so a deleted non-ASCII path is never pruned (silent miss).

## Premise Validation

No issue or PR is cited. Checked by reference: the function and line (`worktree-manager.sh:4460`, prune
at 4488-4505) exist on `origin/main`; the failure reproduces read-only against this repo's own history
(numbers above); ADR corpus grep for the mechanism (`sync_bare_files`, `comm`) hits only ADR-258
(reap-archive persistence), which relies on `sync_bare_files`' checkout-index and does not touch the prune
step. "The bare root `sync` does X" claims are not run: the brief forbids running `sync`/`cleanup-merged`
against the bare root, so the fix is proven on fixture repos only.

## Property List and Cut List (Phase 0.6b)

Properties the ask names:

1. P1 - The prune set is exactly "paths git ever tracked that are absent from HEAD", in any user locale.
2. P2 - A tracked path can never be removed from the bare root, even if a future ordering bug returns.
3. P3 - A runaway prune is bounded.
4. P4 - Non-ASCII paths are compared byte-exactly (a deleted non-ASCII path is pruned, a tracked one survives).
5. P5 - The regression cannot return unseen: a fixture that actually exercises the bug, run in both locales.
6. P6 - Siblings of the same defect class are fixed.

Mechanisms considered and cut:

| Mechanism | Property | Disposition |
|---|---|---|
| Full `-z` NUL pipeline (git log -z, sort -z, comm -z) | P4 | Cut: BSD/macOS `comm` has no `-z`; `-c core.quotePath=false` buys P4 portably (CTO ruling, Fork 1) |
| Ceiling of ~2000 on the candidate set | P3 | Cut as specified: the correct candidate set is already 3568, so it would abort every legitimate run. Re-aimed at the on-disk, not-tracked list (CTO ruling, Fork 2) |
| Set-based membership filter (`grep -xF -f` of the ls-tree list) | P2 | Cut: depends on the same sort/locale machinery as the bug; per-path `git cat-file -e` is order-independent (CTO ruling, Fork 3) |
| New test suite file + shard registration | P5 | Cut: `plugins/soleur/test/worktree-manager-bare-sync.test.sh` already exists and is registered in `scripts/suite-shard-legs.tsv` (line `...bare-sync.test.sh<TAB>8`); extend it (CTO ruling, Fork 4) |
| Per-file mutation test for each sibling | P6 | Cut: one census arm over all tracked non-test `*.sh` covers all current and future siblings (CTO ruling, Fork 5) |

## Technical Rulings

All forks were ruled by `soleur:engineering:cto` (no operator question). Rows persisted in
`knowledge-base/project/specs/fix-sync-bare-files-comm-locale/decision-challenges.md`.

- Fork 1: `git -c core.quotePath=false` on both git calls plus `LC_ALL=C` on sed/sort/comm; newline-delimited. Plan-review amendment (two reviewers, mechanical): the CTO's explicit skip-and-count of `"`-leading lines is dropped as redundant, because a git-quoted spelling never exists on disk and the `-f`/`-L` check already discards it. An embedded-newline path splits into fragments, made fail-safe by the existence check and the per-path tracked guard. Accepted theoretical edge.
- Fork 2: ceiling applies to the list about to be `rm`'d (on disk, not tracked at HEAD), default **5000**, override `SOLEUR_SYNC_PRUNE_MAX`; over it, skip the prune only, loud WARN on stderr naming the count and the override, return 0 so `cleanup-merged` completes; the earlier checkout-index refresh stays.
- Fork 3: per-path guard right before removal: for each on-disk candidate (`-f` or `-L` only) run `git cat-file -e "HEAD:$rel"`; success means tracked, so do not remove it, log `ERROR: tracked path in prune set: <rel>` to stderr, and treat any such hit as an ordering-bug signal that **aborts the whole prune** (remove nothing, warn, return 0). Drop-then-continue was rejected: a set proven wrong cannot be trusted for the rest of its members. Plan-review amendment (correctness, mechanical): the guard compares `git cat-file -t "HEAD:$rel"` to `blob` instead of `cat-file -e`, because `-e` also succeeds for a tree, so a historic file now a directory at HEAD would falsely abort the prune; the candidate lists are built into a scratch dir with each stage's exit status checked (a failing git must not read as an empty or full candidate set), and the script's own comments must not repeat the literal `LC_ALL=C comm -23` (the discoverability probe counts it).
- Fork 4: extend the existing suite; locale arm under `en_US.UTF-8` when `locale -a` lists it, otherwise an explicit counted SKIP (a hard FAIL when `CI=true`); raise the `print_results` floor to match.
- Fork 5: fix `scripts/plugin-delivery-canary.sh:653-654` and `apps/web-platform/infra/run-registered-suites.sh:1068` with `LC_ALL=C comm`; one census arm in the bare-sync suite.

## Research Insights

- Repo facts: prune block at `worktree-manager.sh` 4488-4505; the file runs `set -euo pipefail` (line 29), so empty-array expansion must use the `${a[@]+"${a[@]}"}` idiom (bash 3.2 treats an empty array as unbound; see the existing comment near line 177). Existing suite `plugins/soleur/test/worktree-manager-bare-sync.test.sh` (5 tests, no floor, `print_results` with no argument) builds a seed repo, `git clone --bare`s it, populates the bare root with commit-1 state and runs `bash "$SCRIPT" --yes sync-bare-files`. Its fixture is far too small to reproduce the bug: a 5-path fixture produces no "not in sorted order" warning (measured).
- Fixture sensitivity (measured): a seeded random search over the real HEAD/history lists found subsets of ~31 HEAD paths + ~9 deleted paths for which the legacy pipeline under `en_US.UTF-8` emits `.claude-plugin/marketplace.json` itself; 20-path and smaller subsets did not (hit rate is chance-based, not monotone). Phase 1 therefore freezes a calibrated fixture list (committed as a literal array in the suite) and a **fixture-sensitivity guard** proves the legacy pipeline is wrong on it.
- Sibling audit (census run, 2026-10-12): among tracked non-test `*.sh` files that use `LC_ALL=C sort|uniq`, do not export `LC_ALL`, and call `comm`/`join` without `LC_ALL=C` on the same line, exactly three files qualify: `worktree-manager.sh:4500`, `scripts/plugin-delivery-canary.sh:653,654` (its comment states "both come from LC_ALL=C sorts above"), `apps/web-platform/infra/run-registered-suites.sh:1068` (multi-line `comm -13 \`). Consistent-locale files (`cron-egress-resolve.sh`, `generate-apex-rollback-pr.sh`, `stop-hook.sh`, `lint-legal-*`, `lint-migration-fk-preconditions.sh`, `run-migrations.sh`) sort and compare in the same locale and are not this class. `lint-integration-env-gates.sh`, `lint-orphan-test-suites.sh`, `inngest-soak-6178.sh` export or pin `LC_ALL=C`; `allowlist-diff.sh`, `workspaces-cutover.sh`, `sentry-forget-import-bijection.sh`, `apply-sentry-infra.yml` pin it on the comm line. `join` and `sort -c` have no occurrences in the class.
- Learnings applied: `2026-09-07-my-instruments-reported-green-while-measuring-nothing.md` ("`comm` locale trap, twice": `LC_ALL=C` on every sort/comm pair and a `grep -Fxf` cross-check) and `2026-08-03-the-verification-i-shipped-could-not-fail-...md` (`comm` compares byte strings). The same trap has recurred in this repo; this plan makes it a census-enforced property.
- Test conventions: the suite already clears `GIT_*` env and pins `GIT_CONFIG_GLOBAL/SYSTEM=/dev/null`; keep those. `print_results <floor>` is the anti-vacuity floor (a floor, not equality; derive from a green run).

## Open Code-Review Overlap

- `#8496` (cleanup-merged never gh-queries `[gone]` branches with no worktree) touches `worktree-manager.sh`: **Acknowledge**, a different function (branch reaping), not this prune step; stays open.
- `#8659` (33 suites replace test-helpers' composed EXIT trap and leak the incident sandbox) lists `worktree-manager-bare-sync.test.sh`: **Acknowledge**; this plan keeps the suite's existing `trap 'rm -rf "$TEST_DIR"' EXIT` and does not change trap handling.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "run comm under LC_ALL=C (and make the git log / ls-tree pipelines NUL-safe or quotePath=false) so the prune set is exactly \"paths git ever tracked that are absent from HEAD\"" | Phase 1 (`LC_ALL=C` on every stage, `-c core.quotePath=false`) | mapped |
| 2 | "Add a safety invariant: after computing the prune set, drop (and loudly log) any path that `git ls-tree HEAD` still contains" | Phase 1 per-path `git cat-file -e` guard + ERROR log | mapped |
| 3 | "abort the prune if the set is larger than a sane ceiling (e.g. 2000) or if any tracked path is in it" | Phase 1 ceiling (5000 on the to-remove list, CTO-ruled) + abort on any tracked hit | mapped |
| 4 | "Test: extend the existing worktree-manager bash tests ... with a both-direction fixture bare repo: tracked dotfile (.claude-plugin/marketplace.json), non-ASCII path, a really deleted-then-removed file (must be pruned), run with LC_ALL=en_US.UTF-8 and LC_ALL=C" | Phase 2 arms F0, F1 (both locales) in the existing suite | mapped |
| 5 | "assert marketplace.json survives and the 'not in sorted order' warning never appears" | Phase 2 F1 asserts | mapped |
| 6 | "Exact case floor and a vacuity guard like sibling suites; register new suites in scripts/suite-shard-legs.tsv if the repo requires it" | Phase 2 `print_results` floor + F0 fixture-sensitivity guard; no new suite, so no registration | mapped |
| 7 | "Grep the rest of worktree-manager.sh and other scripts for the same pattern ... and fix any sibling" | Phase 3 (two sibling files fixed) | mapped |
| 8 | "Put these as post-merge verification steps in the plan." | `## Post-Merge Verification` | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `LC_ALL=C` on comm/sed/sort | "run comm under LC_ALL=C" | asked |
| `-c core.quotePath=false` | "core.quotePath handling (use -z or -c core.quotePath=false)" | asked |
| per-path tracked guard + abort | "drop (and loudly log) any path that `git ls-tree HEAD` still contains" | asked |
| ceiling | "abort the prune if the set is larger than a sane ceiling" | asked |
| fixture, both locales, F1 | "both-direction fixture bare repo" | asked |
| `print_results` floor, F0 | "Exact case floor and a vacuity guard like sibling suites" | asked |
| sibling fixes | "fix any sibling" | asked |
| post-merge steps | "Put these as post-merge verification steps in the plan" | asked |
| `SOLEUR_SYNC_PRUNE_MAX` override | none | inferred - justification: the ceiling's WARN must name an actionable remedy, otherwise a legitimately large drift can never be pruned; one env read, CTO-ruled (Fork 2) |
| F8 stub-comm arm | none | inferred - justification: the ask's invariant is "a future ordering bug can never delete a tracked file"; only an injected ordering bug proves that independent of the locale pin |
| F7 sibling census | none | inferred - justification: the ask says to grep and fix siblings once; the census keeps the class from recurring in new scripts (CTO-ruled, Fork 5); plan-review challenged it as taste, default kept |
| SKILL.md sentence | none | inferred - justification: documents the new env knob and abort behaviour for the next operator; one sentence |

### Split Assessment

- Subsystems touched: 4 - `plugins/`, `scripts/`, `apps/`, `knowledge-base/`
- Planned files: 7 | Estimated changed lines: ~350
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR - the root-count threshold trips only because the two sibling fixes are one-token edits in `scripts/` and `apps/`; splitting them off would separate the fix from the census that pins it.

## User-Brand Impact

- **If this lands broken, the user experiences:** the maintainer's local `soleur` plugin marketplace failing to load (`claude plugin list` shows `Marketplace soleur failed to load: cache-miss`) after a `cleanup-merged`, i.e. the existing failure persisting.
- **If this leaks, the user's data / workflow is exposed via:** no exposure vector; the function only removes files inside the local bare root and the removed files are re-materializable from git HEAD by the next `sync`.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** local developer tooling on the maintainer's own checkout, no customer data or customer-facing surface, and every removed file is recoverable from HEAD; not `single-user incident` because no end user of the product is affected.

`threshold: none, reason: the diff touches apps/web-platform/infra/run-registered-suites.sh only to pin a locale on a CI-summary diagnostic comm; no credential, tenant or runtime path is changed.`

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Five design forks ruled (see Technical Rulings). No product, legal, marketing, finance, operations, sales or support implications: internal developer tooling, no UI surface, no regulated data, no new infrastructure.

## Files to Edit

- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` - rewrite the prune block of `sync_bare_files()` (Phase 1).
- `plugins/soleur/test/worktree-manager-bare-sync.test.sh` - new arms, fixture, floor (Phase 2).
- `scripts/plugin-delivery-canary.sh` - `LC_ALL=C comm` at lines 653-654 (Phase 3).
- `apps/web-platform/infra/run-registered-suites.sh` - `LC_ALL=C comm -13` at line 1068 (Phase 3).
- `plugins/soleur/skills/git-worktree/SKILL.md` - one sentence in the `sync-bare-files` description: prune is locale-independent, guarded per path, bounded by `SOLEUR_SYNC_PRUNE_MAX`. (Verify the section exists with `grep -n 'sync-bare' plugins/soleur/skills/git-worktree/SKILL.md` before editing; skip if it documents no prune detail.)

## Files to Create

- `knowledge-base/project/specs/fix-sync-bare-files-comm-locale/decision-challenges.md` (CTO ruling rows; created by this planning run).
- `knowledge-base/project/specs/fix-sync-bare-files-comm-locale/tasks.md` (created by this planning run).

No new test suite, so no change to `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv` or their `.n` files. Phase 2 re-verifies this with `bash scripts/lint-orphan-test-suites.sh` and the registration test; only if the suite's measured duration class changes would `python3 scripts/regenerate-shard-manifest.py --incremental --write` apply (the manifest header names it as the sanctioned regenerator).

## Implementation Phases

### Phase 1 - Fix `sync_bare_files()` (tests first per cq-write-failing-tests-before: write Phase 2 arms, see them RED, then implement)

Replace the `while ... done < <(comm ...)` block with two phases. Sketch (final text decided at work time):

```bash
  # Phase A: build both lists into a scratch dir so each stage's exit status is checked (a failing
  # git or comm must never read as "nothing to prune" or, worse, "everything to prune").
  # LC_ALL=C on EVERY stage (comm prints "not in sorted order" and returns a wrong set otherwise);
  # quotePath=false so non-ASCII paths are byte-exact. A git-quoted spelling (tab/newline/quote/
  # backslash in the name) never exists on disk, so the -f/-L check below discards it.
  local prune_max="${SOLEUR_SYNC_PRUNE_MAX:-5000}" rel prune_dir
  local -a prune_list=()
  local tracked_hits=0 stage_ok=1
  prune_dir=$(mktemp -d)
  git -c core.quotePath=false log HEAD --pretty=format: --name-only --diff-filter=AMRC 2>/dev/null \
    | LC_ALL=C sed '/^$/d' | LC_ALL=C sort -u > "$prune_dir/ever" || stage_ok=0
  git -c core.quotePath=false ls-tree -r --name-only HEAD 2>/dev/null \
    | LC_ALL=C sort -u > "$prune_dir/head" || stage_ok=0
  LC_ALL=C comm -23 "$prune_dir/ever" "$prune_dir/head" > "$prune_dir/cand" || stage_ok=0
  if [[ "$stage_ok" -ne 1 || ! -s "$prune_dir/head" ]]; then
    echo "WARN: prune skipped, could not compute the candidate set from git" >&2
  else
    while IFS= read -r rel; do
      [[ -n "$rel" ]] || continue
      [[ -f "$GIT_ROOT/$rel" || -L "$GIT_ROOT/$rel" ]] || continue
      # order-independent tracked-path guard; blob type check so a path that is a DIRECTORY at HEAD
      # is not mistaken for a tracked file (cat-file -e succeeds on trees too)
      if [[ "$(git cat-file -t "HEAD:$rel" 2>/dev/null)" == blob ]]; then
        tracked_hits=$((tracked_hits + 1))
        echo "ERROR: tracked path in prune set: $rel" >&2
        continue
      fi
      prune_list+=("$rel")
    done < "$prune_dir/cand"
    # Phase B (explicit control flow, one branch executes):
    #   tracked_hits > 0               -> ordering-bug signal: remove NOTHING, WARN (stderr)
    #   ${#prune_list[@]} > prune_max  -> remove NOTHING, WARN naming the count and SOLEUR_SYNC_PRUNE_MAX
    #   else                           -> rm -f loop over ${prune_list[@]+"${prune_list[@]}"};
    #                                     rmdir -p run RELATIVE to $GIT_ROOT (cd in a subshell) with
    #                                     `|| true`, so the walk can never climb above the root;
    #                                     "Removed N ..." line as today
  fi
  rm -rf "$prune_dir"
```

Rules the sketch must honour: stderr for ERROR/WARN (the suite captures `2>&1`); every abort (git failure, tracked hit, ceiling) falls through to the chmod tail and exits 0 so `cleanup-merged` completes and the checkout-index refresh and chmod tail still run; no `-z`, no associative arrays (bash 3.2); `"HEAD:$rel"` quoted; gitlink paths (submodules) are directories on disk and never reach the blob check; the guard is a belt-and-braces layer for an ordering bug, not a replacement for the comm correctness. Keep the `LC_ALL=C comm -23` token on the one physical line so the census predicate and the discoverability probe both key on it; the scratch dir is removed on every path that leaves the block (no early `return` inside it).

### Phase 2 - Tests in `plugins/soleur/test/worktree-manager-bare-sync.test.sh`

Keep Tests 1-5 unchanged. Add a second fixture (`SEED2` / `BARE2`, built with the same env scrubbing) and arms:

| Arm | Locale | Asserts |
|---|---|---|
| F0 fixture-sensitivity guard | `en_US.UTF-8` | an embedded literal copy of the LEGACY pipeline run on the fixture's lists emits `.claude-plugin/marketplace.json` and prints `not in sorted order`; proves the fixture can see the bug. Absent locale: FAIL when `CI=true`, otherwise counted SKIP. |
| F1 (run once per locale: `en_US.UTF-8`, then `C`) | both | after `sync-bare-files` on a fresh copy of the drifted disk state: `.claude-plugin/marketplace.json` exists; every HEAD path exists (loop, count equals the fixture's HEAD count); tracked non-ASCII path exists; deleted ASCII path and deleted non-ASCII path are gone; combined output has no `not in sorted order`; `Removed 2` line present; a SECOND run prints no `Removed` line and removes nothing (idempotency). Removing the `LC_ALL=C` pin makes the en_US run RED (the guard keeps tracked files but aborts, so the deleted paths remain) |
| F5 ceiling | `en_US.UTF-8` | `SOLEUR_SYNC_PRUNE_MAX=1` with 2 stale paths: both remain, stderr WARN names the count and `SOLEUR_SYNC_PRUNE_MAX`, exit 0, checkout-index refresh still applied |
| F8 injected ordering bug | `C` | an executable stub `comm` earlier in `PATH` (in `$TEST_DIR/stubbin`; it ignores args and stdin and touches `$TEST_DIR/stub-comm.called`, which the arm asserts exists so the arm cannot pass vacuously if the SUT stops calling `comm`) that emits one tracked path (`.claude-plugin/marketplace.json`) plus the really-deleted path; run the REAL script: marketplace.json still exists, stderr `ERROR: tracked path in prune set`, nothing pruned. Proves the per-path guard works independent of the locale pin |
| F7 sibling census | n/a | over `git ls-files '*.sh'` minus `*.test.sh`: files that use `LC_ALL=C sort\|uniq`, have no line-start `LC_ALL=` assignment/export, and contain a non-comment `comm`/`join` with `-<digit>` on a line lacking `LC_ALL=C` -> violation list must be empty; the census must also report it examined >= 1 candidate file (empty-population floor), and a self-check feeds a synthetic offending file to the predicate and asserts it IS flagged (harness row) |

Fixture content (frozen literals in the suite): HEAD set of ~31 paths calibrated by the seeded search so the legacy pipeline emits `.claude-plugin/marketplace.json` under `en_US.UTF-8`, including `.claude-plugin/marketplace.json`, `.claude/...`, `.github/workflows/...`, `AGENTS.md`, `plugins/...`, `knowledge-base/project/specs/verify-canus<U+0435>tool-caching-876/tasks.md` (non-ASCII, tracked); deleted set of ~9 paths including one ASCII path and one non-ASCII path (`knowledge-base/project/specs/verify-canus<U+0435>old/x.md`), added in commit 1 and removed in commit 2. Each locale arm runs against a fresh copy of the pristine drifted disk state (copy a template dir; never reuse a swept root). Each arm builds its own scratch under `$TEST_DIR`; no arm touches the real bare root.

Floor: `print_results <N>` where N is the minimum assertion count of a LOCALE-ABSENT run (the C arm, F5, F7, F8 and the existing Tests 1-5), so a dev box without `en_US.UTF-8` does not trip it; the en_US arms add assertions on top, and a missing locale is a counted SKIP (`SKIPPED` is part of `ran = PASS + FAIL + SKIPPED`). Under `CI=true` a missing locale is a FAIL. At least N, never `-eq`. Locale detection: `locales=$(locale -a 2>/dev/null || true)` into a variable, then `grep -qiE '^en_US\.utf-?8$' <<<"$locales"` (no `locale -a | grep -q` pipe under `pipefail`, which can SIGPIPE into a false "absent").

RED-first order: write F0, F1, F5, F7, F8, run against the unmodified script and confirm F1 (en_US) fails with the `sorted order` evidence while F1 (C) passes, then implement Phase 1.

### Phase 3 - Siblings

- `scripts/plugin-delivery-canary.sh` 653-654: `LC_ALL=C comm -23 ...` / `LC_ALL=C comm -13 ...`; keep `|| true`; update the comment to say the compare is pinned.
- `apps/web-platform/infra/run-registered-suites.sh` 1068: `LC_ALL=C comm -13 \`.
- Run each sibling's own suite: `bash scripts/plugin-delivery-canary.test.sh`, `bash apps/web-platform/infra/run-registered-suites.test.sh` (read the file header for its env needs first), plus F7.

### Phase 4 - Docs and wrap

SKILL.md sentence (Files to Edit). No ADR (no architectural decision), no C4 change, no version bump (CI derives it; wg-never-bump-version-files-in-feature). PR body: `## Changelog` with a patch note; no `Closes #` (no issue). Add a learning note only if review finds something new (the locale trap is already recorded; point at this PR from the 2026-09-07 learning if the repo convention allows).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `LC_ALL=en_US.UTF-8 bash plugins/soleur/test/worktree-manager-bare-sync.test.sh` and `LC_ALL=C bash ...` both exit 0 and print no `not in sorted order`.
- [ ] Before the fix, arm F1 is RED with `.claude-plugin/marketplace.json` missing (evidence captured in the work log); after the fix it is GREEN.
- [ ] F0 proves the fixture is sensitive: the legacy pipeline emits `.claude-plugin/marketplace.json` under `en_US.UTF-8`.
- [ ] F8: with a stub `comm` that returns a tracked path, marketplace.json still survives, stderr carries `ERROR: tracked path in prune set`, and nothing is pruned.
- [ ] F5: ceiling skip leaves files in place, exits 0, stderr names `SOLEUR_SYNC_PRUNE_MAX`.
- [ ] A deleted non-ASCII path is pruned and a tracked non-ASCII path survives (core.quotePath handling).
- [ ] `print_results` is called with a numeric floor of at least the locale-absent run's assertion count; the file contains no `|| true` that can swallow an arm.
- [ ] F7 census is empty over the repo and flags its synthetic offender; `git grep -nE 'LC_ALL=C comm' plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh scripts/plugin-delivery-canary.sh apps/web-platform/infra/run-registered-suites.sh` shows all three files fixed.
- [ ] `bash scripts/lint-orphan-test-suites.sh` and the infra suite-registration check stay green; `scripts/suite-shard-legs.tsv` unchanged.
- [ ] `python3 scripts/lint-guard-contract.py` passes on this plan; markdownlint passes on the plan/spec files.
- [ ] No command in the PR's tests ran `sync`, `sync-bare-files` or `cleanup-merged` against the real bare root (fixtures only, under `$TEST_DIR`).

### Post-merge (parent pipeline; read-only unless stated)

See `## Post-Merge Verification`.

## Post-Merge Verification

Handled by the parent pipeline, not by the work phase. In the bare root `/data/git-repositories/jikig-ai/soleur` after the fix is merged and the bare root's HEAD has the new script:

1. Before running anything mutating, record `git ls-tree -r --name-only HEAD | wc -l` and the on-disk existence of `.claude-plugin/marketplace.json` (the unfixed run may already have removed it).
2. `bash plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh sync` (using the merged script): expect no `not in sorted order` line, no `ERROR: tracked path in prune set`, and either no `Removed` line or a `Removed N` where each removed path is untracked-at-HEAD.
3. `test -f .claude-plugin/marketplace.json` succeeds (the sync's checkout-index re-materializes it).
4. `claude plugin list` shows `soleur@soleur` enabled and no `cache-miss`; `claude plugin update soleur@soleur` no longer reports `not found`.
5. Read-only historical note: compare `git ls-tree -r --name-only HEAD` against the bare root's disk once (`comm -23` under `LC_ALL=C` of the HEAD list against `find`-derived on-disk files, or per-path `test -e`); report how many tracked paths were missing before step 2 (the earlier unfixed runs deleted up to 1198 per run, but each `sync` re-materializes them via checkout-index, so the expected residue after one fixed run is 0; a non-zero residue after step 2 is a new finding to file).
6. Run `sync` a second time: no `Removed` line (idempotency on the real root).

## Guard Contract

### Guard 1 - tracked-path-never-pruned invariant in `sync_bare_files()`

**Property.** No path that `HEAD` tracks is ever removed from the bare root by the prune step, regardless of the user's locale or any ordering error in the candidate computation.

**Assembly.** Every code path that can remove a file in `sync_bare_files()` flows through ONE chokepoint: the single `rm -f "$GIT_ROOT/$rel"` loop over `prune_list`, which can only contain entries that passed the per-path `git cat-file -e "HEAD:$rel"` check in Phase A. Members: the comm-derived candidate stream (locale-dependent), the quoted-path skip, the `-f/-L` filter, the cat-file guard, the tracked-hit abort, the ceiling. The guard is deliberately independent of sort order: it queries the object database per path. Sites outside this function that delete files in the bare root (`reap_archive_persist`, cleanup-merged branch reaping) are out of scope for this property and are not changed.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | remove `LC_ALL=C` from the `comm` (en_US run) | F1 en_US RED: marketplace.json survives but the deleted paths are not pruned and stderr carries `ERROR: tracked path in prune set` |
| 2 | delete the tracked-path guard (the blob check) in the SUT during work, keep `LC_ALL=C comm` | arm F8 (C locale, stub `comm` emitting a tracked path) goes RED: marketplace.json missing; proves the guard, not the locale pin, is what protects |
| 3 | change the tracked-hit handling from abort-all to drop-and-continue | F8 asserts the really-deleted file is still present; goes RED |
| 4 | remove the ceiling check | F5 goes RED (files removed despite `SOLEUR_SYNC_PRUNE_MAX=1`) |
| 5 | add a second stale file after a compliant first (2 stale paths, ceiling 1) | F5 asserts BOTH remain (a check that stops at the first member is the class) |
| 6 | revert `-c core.quotePath=false` on one of the two git calls | non-ASCII arm RED (deleted non-ASCII path not pruned, or tracked one dropped) |
| 7 | neuter the arms: make `assert_eq` a no-op or delete half of the arms | `print_results` floor trips (exit 1, "ANTI-VACUITY FLOOR TRIPPED") |
| 8 | the locale arm silently not run (en_US absent) | counted SKIP lowers PASS+FAIL below the floor unless SKIP is counted; under `CI=true` it FAILs |

**Harness rows.** H1: F0 runs the legacy pipeline on the fixture under en_US and must be wrong (print `not in sorted order` and emit at least one tracked path, calibrated at authoring time to be `.claude-plugin/marketplace.json`); a fixture that cannot reproduce the bug fails the suite. Collation-version drift can move which tracked path is emitted, so F0 asserts the warning plus any tracked path, not marketplace.json by name. H2 (must-PASS, not the canonical): F1's second run on the already-synced root (no stale files) must report zero removals under both locales, so a guard that aborts or removes on everything fails it. H3: the census self-check feeds a synthetic offender file and a synthetic compliant file; the offender is flagged and the compliant file is not (rejects both a census that flags nothing and one that flags everything).

**Anchor.** The guard compares to the object database at `HEAD`, which the prune cannot edit; a diff that weakens the guard changes the script and the suite in the same commit, so consistency is proven but integrity is not. What must also move for a weakening to pass: the F8 mutation arm reading the script text (a deletion of the guard reds them) and the numeric `print_results` floor (a reviewer sees the floor edit); neither is outside-the-commit, stated as a residual.

### Guard 2 - locale-pinned comm census (F7)

**Property.** No tracked non-test shell script that sorts with `LC_ALL=C` feeds the result to `comm` or `join` without `LC_ALL=C` on that consumer.

**Assembly.** Population: every path from `git ls-files '*.sh'` excluding `*.test.sh`, derived at run time (not a hard-coded list); scope predicate: file contains `LC_ALL=C sort|uniq`, has no line-start `LC_ALL=` assignment or export (those pin the whole script); violation predicate: a non-comment line matching a `comm|join` invocation with a `-<digit>` option and lacking `LC_ALL=C`. Multi-line invocations (`comm -13 \`) are caught because the option is on the same physical line as the command. Members drift (new scripts); the chokepoint is the `git ls-files` derivation.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | strip `LC_ALL=C` from the comm at `scripts/plugin-delivery-canary.sh:653` | F7 RED naming the file and line |
| 2 | strip it from the SECOND violating line (654) after 653 stays compliant | F7 RED (a census that stops at the first member is the defect) |
| 3 | add a new tracked script with the offending shape | F7 RED (population is derived, not listed) |
| 4 | make the population derivation return nothing (bad pathspec) | F7 fails on the empty-population floor, not green on "0 checked" |
| 5 | line-start `export LC_ALL=C` added to an otherwise offending file | F7 stays GREEN for it (permitted variation; must-PASS row) |

**Harness rows.** The synthetic offender/compliant pair (H3 above); a must-PASS file that exports `LC_ALL=C` at line start.

**Anchor.** Same-commit weakening is possible (edit predicate and offender together); the self-check rows pin the predicate's behaviour on synthetic inputs so a weakened predicate that stops flagging the synthetic offender reds the suite.

## Observability

The change adds no server-side surface; the deliverable is a bash tool and CI-summary diagnostics. The prune now emits structured stderr markers that a caller (a developer terminal or a CI log) can see without SSH.

```yaml
liveness_signal:
  what: sync_bare_files prints "Synced on-disk files from git HEAD" on completion and a "Removed N stale tracked-deleted file(s)" line only when it removed something
  cadence: every `sync`, `sync-bare-files` and the tail of `cleanup-merged`
  alert_target: the invoking terminal/CI log (stdout); abort conditions go to stderr as WARN/ERROR
  configured_in: plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh
error_reporting:
  destination: stderr of the invoking process; `ERROR: tracked path in prune set: <rel>` and `WARN: prune skipped ...`
  fail_loud: yes - an ordering bug can no longer delete silently; it prints ERROR per path and aborts the prune
failure_modes:
  - mode: locale/ordering regression returns tracked paths in the candidate set
    detection: `ERROR: tracked path in prune set` on stderr; suite arms F1/F8
    alert_route: terminal/CI log; suite red in CI
  - mode: runaway candidate list over SOLEUR_SYNC_PRUNE_MAX
    detection: `WARN` naming the count and the override
    alert_route: terminal/CI log
logs:
  where: invoking terminal or CI job log
  retention: CI job log retention
discoverability_test:
  command: grep -c 'LC_ALL=C comm -23' plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh
  expected_output: "1"
```

## Test Scenarios

- Fixture bare repo with tracked dotfile dir `.claude-plugin/marketplace.json`, non-ASCII tracked path, really-deleted ASCII and non-ASCII paths, run under `en_US.UTF-8` and `C`: marketplace survives, deleted paths pruned, no `not in sorted order`.
- Idempotent second run removes nothing.
- Ceiling and tracked-path abort arms (above).
- Census arm over the whole repo.

## Sharp Edges

- Do not run `sync`, `sync-bare-files` or `cleanup-merged` against the bare root while developing; the unfixed script deletes tracked files there. Every test uses a fixture under `$TEST_DIR`.
- A fixture too small to reproduce the bug is green under the broken code: F0 exists so that cannot happen again. The hit rate for marketplace.json specifically is chance-based; freeze the calibrated list, do not regenerate it per run.
- `locale -a` spells the locale `en_US.utf8`; `LC_ALL=en_US.UTF-8` still resolves. Do NOT probe with `LC_ALL=en_US.UTF-8 locale charmap`: for a missing locale it exits 0 and prints `ANSI_X3.4-1968`. Use the `locale -a` list captured into a variable (see the Floor paragraph).
- `git cat-file -e HEAD:<dir>` succeeds for a directory, so the guard uses `git cat-file -t` and compares to `blob`; a historic file that is now a directory at HEAD is not "tracked".
- The file runs `set -euo pipefail` on bash 3.2-compatible syntax: empty array expansion needs `${a[@]+"${a[@]}"}`; no `mapfile`, no associative arrays.
- A plan whose `## User-Brand Impact` is empty fails deepen-plan Phase 4.6; this one is filled with threshold `none` and a scope-out line.
- The ceiling counts paths about to be removed, not candidates; a real mirror's candidate count is in the thousands by design.
