# Fix-commit review — security-sentinel + code-quality-analyst (targeted round)

- **Scope:** `git diff 79db88e18b..HEAD` (HEAD `73f497e48a`), 4 files only: `scripts/ci-pr-affected-replay.py`, `plugins/soleur/test/ci-pr-affected-replay.test.sh`, `.github/workflows/ci.yml` (comment), `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` §7. The 7 review-report files also in the diff are prior-round artifacts, not review subjects.
- **Method:** static read of the gate and the test harness + an empirical probe in `mktemp -d -t soleur-fr.XXXX` (`/tmp/soleur-fr.9JtH`): synthetic fixtures run through the fixed SUT *and* the pre-fix SUT (`git show 79db88e18b:scripts/ci-pr-affected-replay.py`), so both arms of the gate are observed, not inferred.

## Verdicts per question

### (a) `base_text is not None` gate (scripts/ci-pr-affected-replay.py:2092) — CORRECT

The gate suppresses the restore/regenerate tail exactly under base-absent and preserves it under base-present:

- **Base-absent + head-present = the `baseline-reintroduced` arm** (:2058 fires iff `head_text is not None and base_text is None`). The line-level findings (`stale-line`, `baseline-dup`, `baseline-order`) still co-fire on the re-added file's contents — verified live: a re-add holding a stale line and a dup prints `baseline-reintroduced` + delete remedy + `stale-line` + `baseline-dup`, and *no* tail. Pre-fix, the same run emitted the full tail, including `git checkout origin/main -- <rel>` (impossible — the file does not exist at the base) and `ratchet --print-baseline > …` (the forbidden regeneration). The gate removes exactly the two remedies that are respectively impossible and prohibited under strict zero.
- **Cannot suppress `grown`:** `grown` is appended only under `if base_text is not None and head_text is not None` (:2075), so `grown ∈ names` implies `base_text is not None` — the new conjunct is tautologically satisfied whenever a grown remedy exists. Trivially fine.
- **Base-absent + head-absent:** `uniq` is empty, so none of the four findings can fire; the gate is a no-op there.
- **Lost `stale-line` caution under reintroduced — acceptable.** The caution ("confirm the pair is really gone … do not prune: rerun") guards against *pruning on a degraded census*. Under base-absent pruning is never a legal remedy — the reintroduced remedy (:2060) already prescribes wholesale deletion, which is correct regardless of selector completeness because `baseline-reintroduced` is unconditional (it does not depend on `live` at all). The caution has no applicable action in that arm; suppressing it alongside the recipe is right, and the runbook table row documents the co-fire + "delete the file" remedy.
- **Base-present:** unchanged. Verified live: a base-present stale fixture emits both tail lines byte-identical to `row_rt_text_stale`'s golden (`:2567-2570`, which builds `want` with the caution + the `--print-baseline` recipe and compares the WHOLE stdout on the `ok` fixture, where `rt_variants` puts `bl-stale.tsv` at the base). The golden still pins the tail.

### (b) New test conjuncts assert real output text — YES, with one vacuous-but-harmless conjunct

- `grep -qxF -- $'baseline-reintroduced\tscripts/bl-ok.tsv\ta baseline file absent at the base cannot be adopted: strict zero retired it'` — whole-line fixed-string match against the :2059 format; `q(rel)` emits `scripts/bl-ok.tsv` unquoted (verified byte-for-byte in the live run).
- `grep -q '^baseline-dup'$'\t'` — prefix+TAB on the real `baseline-dup\t<rel>\t<shown>` row shape (verified).
- `! grep -q -- '--print-baseline' <<<"$ROUTALL"` — the only `--print-baseline` emit site on the verdict path is the gated tail (:2097); `RATCHET_REMEDY_NEW` (:1760-1770) and the reintroduced remedy contain none. The assertion is stable and correctly scoped to `ROUTALL` (stdout+stderr of the last `rt_go`).
- **Vacuousness note (see P3-1):** in `row_rt_reintroduced`'s first run (`std`/`adopt`/`bl-ok.tsv`), `live == head_lines`, so *no* line-level finding co-fires and the tail would not have printed even pre-fix — confirmed: pre-fix and fixed SUT produce byte-identical output on that shape. The non-vacuous suppression pin is `row_rt_big_baseline` (`:2511`): the 150k-line `bl-big.tsv` is uncommitted-at-base → `stale-line` (150k entries, capped) + `baseline-dup` co-fire under the reintroduced marker, which forced the tail pre-fix. Verified empirically on the same shape.
- `row_rt_big_baseline`'s ordering is correct: `rt_is` result captured into `r`, then budget check, `[[ "$r" -eq 0 ]]`, the `baseline-dup` presence check, the `--print-baseline` absence check, `return 0`; any failure → `return 1`.
- The `chk :2970` label change ("always reports baseline-reintroduced changes no verdict") matches `rt_p_weak`'s `baseline_at → None` semantics under strict-zero vocabulary — accurate.

### (c) Defects introduced by the fix — NONE

- Mutant-suite integrity: `ratchet-adoption-refused` (`:4889`, targets grown's `if base_text is not None and head_text is not None:` at :2075) and `ratchet-stale-line-remedy-without-confirm` (`:5021`, targets the inner `if "stale-line" in names:` at :2094) still match uniquely — the new gate line at :2092 collides with neither pattern.
- Shell-shape checklist clean: `$'…'` ANSI-C quoting is bash-3.2-safe; `! grep -q` is used as an assertion (not an error-vs-nomatch membership test); no jq-in-single-quote, `git remote get-url`, or rename-detection hazards added.
- No new input/injection surface: the change deletes output lines; `rel` in the surviving remedies follows the pre-existing unquoted-`%s` pattern unchanged elsewhere.
- ci.yml comment, runbook §7, and `--help`/docstring rewordings are consistent with the verified behavior (runbook's "line-level checks still co-fire on a malformed re-add under `baseline-reintroduced`" is literally what the probe printed).

## Findings

- **P1:** none.
- **P2:** none.
- **P3-1 (test vacuity, informational):** `row_rt_reintroduced`'s `! grep -q -- '--print-baseline'` cannot distinguish pre/post-fix code on its own fixture (no co-firing line-level finding). Coverage is real via `row_rt_big_baseline`; the conjunct still guards against `--print-baseline` text leaking into the reintroduced remedy itself. No action needed.
- **P3-2 (docstring precision):** `scripts/ci-pr-affected-replay.py:135` "ratchet green iff audit green" (and the parallel "green exactly when the audit is" in `.github/workflows/ci.yml:401`) is a slight over-simplification: a *present* baseline file with stale lines makes ratchet red while the audit is green (stale-line/reintroduced are baseline-hygiene verdicts, not audit findings). The immediately following `(baseline-reintroduced)` clause disambiguates; cosmetic.
- **P3-3 (optional, style):** no dedicated `mutate` line for the new conjunct (e.g., `base_text is not None and names &` → `names &`), though `row_rt_big_baseline`'s `--print-baseline` pin already kills that mutant shape. Symmetric with the suite's convention; optional.

## Overall verdict

**Ship.** The gate is the minimal correct discriminator, verified on both arms against the real SUT (pre-fix vs fixed); the new assertions are real output text; no defect introduced.
