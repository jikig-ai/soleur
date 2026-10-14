---
feature: Edge-declaration coverage residuals — covers() containment, census matchability, --paths normalization, root-gap detection
issue: "#10117"
pr: "#10190 (docs) + #10237 (PR-A hardening) + #10242 (PR-B containment)"
branch: feat-10117-edge-coverage-residuals
plan: knowledge-base/project/plans/2026-10-13-fix-edge-declaration-coverage-residuals-plan.md
spec: knowledge-base/project/specs/feat-10117-edge-coverage-residuals/spec.md
status: done
---

# Tasks: Edge-declaration coverage residuals (#10117)

Two independent PRs, either merge order green. PR-A = judgment-free hardening
(FR1 `--paths` normalization, FR2 census matchability, FR3 root-gap detection row,
ADR-242 amendment). PR-B = `covers()` all-containment + baseline regen +
dispositions (FR4). RED-first ordering inside each PR: battery rows land and are
observed RED before the predicate/normalization edits.

## PR-A — `feat-10117-hardening` (FR1 + FR2 + FR3 + ADR)

### Phase A1 — Battery rows, RED-first

- [x] A1.1 Fixture sweep first: `rg 'glob:' scripts/test-all-affected.test.sh` over
      sandbox fixture members — reconcile any accept-case fixture carrying a
      non-bare tail BEFORE writing new rows (the tightened FR2 predicate flips them).
- [x] A1.2 q-family pin: `--print-selection --paths=./<p>` selects byte-identically
      to `--paths=<p>`; one reject-class row per class: empty (`a,,b`, `--paths=.`,
      `./`), absolute (`/x`), segment-`..` incl. `a/../b` (rejected, NOT collapsed —
      spec divergence), `a//b`, `a/./b`, trailing `dir/`, TAB byte, LF byte,
      residual `./` after strip (`././x`). Non-cases pinned: `foo..bar.sh`,
      `a b.sh`. Named error echoes the offending element + a valid example.
- [x] A1.3 FR2 decline/accept rows on `_th6_root_covered`
      (`scripts/test-all-affected.test.sh`:3036-3044): decline literal-in-glob
      `glob:<root>/x.test.sh`, subset `pre*.test.sh`/`*x.test.sh`, subdir-scoped
      `sub/*.test.sh`, head-side `glob:<root>x/**.test.sh`, overlap
      `glob:<root>/**.test.sh` for a `.sh` corpus, wrong-ext; accept `*<ext>`,
      `**<ext>`, and a bare `<root>/` dir member (the `_TH_PREFIX_ROOTS` disjunct).
      Row arm = sandboxed run, verdict in `selection`.
- [x] A1.4 FR3 detection row beside `_TH_ROOTS`: `git -C "${_TH_REPO:-$REPO_ROOT}"
      -c core.quotePath=false ls-files` behind a `_th_ls_files()` function;
      `NF==1` complement with DISJOINT extension classes (`*.test.sh` vs
      `*.sh`-but-not-`*.test.sh`); producer-liveness floor (empty listing → RED,
      `EMPTY-ROOT-DERIVATION` idiom); failure message names #10198; `_TH_REPO`
      confined to `"$TESTROOT"` (`assert_fixture_dir` idiom); stale comment block
      at :3023-3027 gains a pointer to the row.
- [x] A1.5 Run `bash scripts/test-all-affected.test.sh`; record new rows RED.
      FR3's live-tree row passes today (zero dir-less corpus files) — its RED
      demonstration is the mutation arms, not the live tree.
- [x] A1.6 Bump `MIN_CASES` (`test-all-affected.test.sh`:3247) to the new literal;
      grep and reconcile every count literal.

### Phase A2 — Predicates + normalization

- [x] A2.1 `scripts/test-all.sh` ~:307 `--paths=` parse arm: per-element
      `./`-strip to fixpoint + reject set + named error (element echoed + valid
      example); rejoin into `_PRINT_PATHS`. Do NOT call `_affected_normpath`
      (defined :2855, rc-127 here; wrong semantics anyway). Update `--help`
      (:333-334) with the normalization + reject set.
- [x] A2.2 `_th6_root_covered`: glob arm = prefix-match `glob:$2/`, tail extracted
      via `${_m#"glob:$2/"}` (quoted — `$2` must not glob inside `#`),
      literal-compare `[[ "$tail" == "*${ext}" || "$tail" == "**${ext}" ]]` (quoted
      RHS is a literal compare — inline comment REQUIRED, the quotes carry the
      fix); retain the bare `$_m == "$2/"` disjunct.

### Phase A3 — ADR amendment + verify

- [x] A3.1 ADR-242: append `## Amendment — 2026-10-13 (#10117)` with **decision 27**
      (23-26 taken by the #9815 amendment; `check-adr-ordinals.sh` covers filename
      ordinals only — hand-verify) + `amended_by:` entry. Content: detect-not-extend
      + #10198 deferral + literal-edge/`always_on` interim recourse + census =
      matchability + the `audit-suite-reads.sh` glob-literal divergence note.
- [x] A3.2 `bash scripts/test-all-affected.test.sh` green;
      `bash scripts/test-all.sh --affected` sanity;
      `bash scripts/test-affected-kb-consumers.test.sh` green (no new baseline
      rows — kb literals fixture-scoped).
- [x] A3.3 PR-A body: RED-first record + one line noting
      `affected-prepass-bench.sh --probe` forwards into `--paths` (a bad probe now
      exits rc 2 `DIFFERS` — loud but cryptic).

## PR-B — `feat-10117-covers-containment` (FR4)

### Phase B1 — Oracle rows, RED-first

- [x] B1.1 Extend the k5 vector (`test-affected-kb-consumers.test.sh`:702-725):
      last two positions flip `1`→`0`; add a fully-covered case
      (`glob:knowledge-base/**` vs nested dir ref → 1) and a second-member-decline
      case (first member matches, second does not → declines). New dir-ref rows
      run under `cd "$REPO_ROOT"` — inline comment naming the changed contract
      (`_cov` at :681 does not `cd`).
- [x] B1.2 Guard-3 mutation rows (`SANDBOX_MUT_*` or the :680-696 scratch-copy
      idiom): restore nest clause → RED; `any()` for `all()` → RED; empty-member
      set → RED; stale `1` in the vector → RED; must-PASS `**`-tail full-coverage
      case.
- [x] B1.3 Run `bash scripts/test-affected-kb-consumers.test.sh`; record new rows
      RED.

### Phase B2 — `covers()` arm + emitter + regen + dispositions

- [x] B2.1 Rewrite the dir-ref arm (:268-296): for kb-scoped refs, materialize
      `_TRACKED` via any `tracked(p)` call then prefix-filter `_TRACKED[0]` on
      `f.startswith(p.rstrip("/") + "/")` (`members_under` accessor — `tracked()`
      is a predicate, not an enumerator); require EVERY member to match the glob
      tail; empty member set declines; non-kb refs keep the nest clause.
      LANDED AS: `_tracked()` accessor split; dual dispatch `p in
      _tracked()[1] or os.path.isdir(p)` (index dirs catch sparse-checkout/
      deleted dirs, isdir catches foreign dirs); members match the FULL minted
      glob `g` (tail-only matching would accept members outside head); non-kb
      dir refs decline identically (memberless) — no separate nest path needed.
- [x] B2.2 Emitter extension (:344-351): `argv-code` rows carry an optional 4th
      classification column (`false-positive: <reason>`); a row ABSENT from the
      old baseline emits `\tUNCLASSIFIED` so c1 forces a disposition; add one
      u-family fixture pinning the argv-code 4-col shape; the `c1:` fail line
      (or the `unclassified_rows` comment) names the two exits (covering edge in
      `scripts/lib/test-affected-paths.sh`, or `false-positive:` 4th column).
      DEVIATION (landed): the 4-col classification + UNCLASSIFIED stamp already
      existed on main for non-argv-code forms; argv-code rows remain 2-col by
      contract — the 12 new rows' dispositions are recorded in the PR body
      table instead, and c1's fail line gained the remedy text.
- [x] B2.3 Stale-doctrine hygiene in the same diff: `covers()` comments at
      :272-277 and :288-294 updated.
- [x] B2.4 Rebase onto `origin/main` immediately before regen (drawdown
      precedent), then `bash scripts/test-affected-kb-consumers.test.sh
      --write-baseline` **in the same commit** as the `covers()` change. Workflow:
      regen → hand-seed `false-positive: <reason>` on rows needing it (the one
      sanctioned hand-edit) → re-regen to verify carry-forward → inspect
      line-by-line. CONDITIONAL: `scripts/lib/test-affected-paths.sh` only if a
      row dispositions to a new covering edge (makes the PR runner-critical).
- [x] B2.5 Verify: suite green, `b1`/`c1` green, zero `UNCLASSIFIED` rows;
      bump `MIN_CASES=22` (:741) for the new rows; PR body = row-count delta
      summary + disposition table grouped by disposition type.

## Cross-cutting

- [x] X.1 Both suites green on both PRs; either merge order lands green.
- [x] X.2 All new rows observed RED before their predicate edits (recorded per PR).
- [x] X.3 No bare `knowledge-base/` literal in new non-comment code anywhere —
      PR-A edits files inside the oracle's scan surface (composed-literal
      discipline; a stray literal flips baseline rows in either merge order).
- [x] X.4 `discoverability_test` (`grep -c 'NF==1' == 1`) — no second `NF==1`
      token in new code/comments.
