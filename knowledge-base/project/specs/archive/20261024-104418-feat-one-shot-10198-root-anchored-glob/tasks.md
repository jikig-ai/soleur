# Tasks — feat-one-shot-10198-root-anchored-glob

Plan: `knowledge-base/project/plans/2026-10-23-feat-root-anchored-glob-edge-form-plan.md`
Issue: #10198 (closes it). One PR.

## Phase 1 — `_affected_glob_split` extraction (doctrine-neutral refactor)

- [ ] 1.1 Create `scripts/lib/affected-glob.sh`: `_affected_glob_split <pattern>` — emits
      `_AGS_CLASS ∈ {literal,dir,malformed}`, `_AGS_WHY`, `_AGS_HEAD`, `_AGS_TAIL`; rc 0 always;
      bash 3.2-safe; comment block carries the ONE-doctrine doctrine.
- [ ] 1.2 `scripts/test-all.sh`: glob-lib source in the `_AFF_LIB` block; `_AFF_LIB_OK` requires
      `declare -F _affected_glob_split`; rewire mint arm + hit arm to call the helper; hit arm's
      glob branch opens with `declare -F _affected_glob_split >/dev/null || return 0` (fail-wide —
      `_diff_touches` reaches `_diff_edge_hit` outside the `_AFF_LIB_OK` gate at :2669).
- [ ] 1.3 `scripts/lint-orphan-test-suites.sh`: fail-closed source beside REL/AFF; census arm →
      helper + `_AGS_WHY`-to-message map (keep every existing reason string).
- [ ] 1.4 `scripts/lint-orphan-test-suites.test.sh`: `materialise()` `_mp` → helper;
      `build_pristine` `cp` line for the new lib.
- [ ] 1.5 `scripts/test-all-affected.test.sh`: `build_sandbox` `cp` line; `_edge_run` sources the
      lib inside its eval.
- [ ] 1.6 `scripts/test-affected-derive.test.sh`: `derive_run` sources the lib inside its eval.
- [ ] 1.6b `plugins/soleur/test/ci-pr-affected-replay.test.sh`: `extract_oracle`/`edge-run.sh`
      eval sources `affected-glob.sh` (rc-127 on every `^glob:` row once the hit arm calls the
      out-of-window helper).
- [ ] 1.7 Run all four batteries — all green (neutrality proof). Commit.

## Phase 2 — RED-first battery rows

- [ ] 2.1 Mint rows: `_edge_run`/`derive_run` vectors — `glob:*.test.sh`, `glob:**.test.sh`,
      `glob:x*.sh` → `^glob:<pattern>`; `glob:x*/y`, `glob:*/x` → `^glob:<verbatim>`.
      `test-affected-derive.test.sh` Rg3: remove `glob:*.sh` from the malformed vector; new Rg root
      rows.
- [ ] 2.2 Hit rows (sandbox lib `glob:` member → `glob:*.test.sh`): `x.test.sh` selects carriers;
      `a/x.test.sh` and `x.md` decline; `**` tail parity.
- [ ] 2.3 Census M-rows: `glob:*.test.sh`/`glob:x*.sh` accept; `glob:x*/y` → `root-tail-slash` RED;
      M22 fixture `a*/b` → `a/b*c` (preserves the "does not end in /" class).
- [ ] 2.4 covers() k5 cells (foo*.sh flips 1→0; dir-less covered/declined/dir-ref cells);
      `edge_hit` differential cells; GLOBENT admit/semantic fixtures; th8v vector + reworked th8
      rows + th8m anchors.
- [ ] 2.4b `plugins/soleur/test/ci-pr-affected-replay.test.sh`: re-anchor `er` row
      `mal-head-not-slash-empty` (:1868 — `glob:*.sh` over `lib/z.txt` flips to non-match); add
      root-arm rows (`x.sh`→1, `a/x.sh`→0, dir-bearing `.sh`→0); reconcile `row_edge_*` `mal-`
      name-prefix grouping + `EDGE_ROWS -ge 50` count literal.
- [ ] 2.5 Run; record every new row RED; bump `MIN_CASES` (×3) + sweep count literals. Commit.

## Phase 3 — the extension

- [ ] 3.1 `affected-glob.sh`: `root` class + `root-tail-slash` why.
- [ ] 3.2 `test-all.sh`: mint root case (no-probe `^glob:$_g`); hit root arm
      (`!= */*` + `[[ == ]]`, `_AGS_HEAD`-nonempty pre-check); GLOBENT second arm
      (`/`-free charset with `*`).
- [ ] 3.3 `lint-orphan-test-suites.sh`: census root class → valid (no `-d` probe).
- [ ] 3.4 `test-affected-kb-consumers.test.sh`: covers() root arm (dir-less, not-a-dir, fnmatch) +
      malformed-check update (mid-slash head; root tail with `/`).
- [ ] 3.5 `ci-pr-affected-replay.py`: `edge_hit` root arm + same malformed rules + docstring.
- [ ] 3.6 th8 rework: `_th8_corpus_covered <array> <member>` (literal | metachar-free glob literal |
      well-formed root glob `[[ == ]]`); `_th8_eval` emits uncovered suite:member pairs; comment +
      message updates.
- [ ] 3.7 `git grep '\^glob:'` sweep over BOTH `scripts/lib/test-relevance-paths.sh` AND
      `scripts/lib/test-affected-paths.sh` (reclassification evidence — CTO ruling), re-run in the
      SAME commit as the grammar flip; three doctrine comment blocks updated; `git grep`
      stale-doctrine sweep (`does not end in /`, `no head to mint`, `deferred to #10198`).
- [ ] 3.8 All four batteries green. Commit.

## Phase 4 — records + verify

- [ ] 4.1 ADR-242: `amended_by:` entry + `## Amendment — 2026-10-23 (#10198)` decision 28 +
      superseded-by note inside decision 27.
- [ ] 4.2 `scripts/lib/test-affected-paths.sh` header doc block (:35-46) names the root form +
      helper (comment region only — S4-separated).
- [ ] 4.3 `bash scripts/check-adr-ordinals.sh`; re-grep feature artifacts for the decision number;
      `bash scripts/lint-orphan-test-suites.sh` + `--affected` sanity.
- [ ] 4.4 Final battery sweep; PR body records RED-first demonstration + the decision-28 text.
