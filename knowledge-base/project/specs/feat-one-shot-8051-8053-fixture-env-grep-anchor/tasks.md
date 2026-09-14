# Tasks — feat-one-shot-8051-8053-fixture-env-grep-anchor

Plan: `knowledge-base/project/plans/2026-09-14-fix-fixture-env-hook-scrub-grep-anchor-plan.md`
Closes: #8051, #8053

## Phase 1 — #8051: suite hermeticity (`plugins/soleur/test/git-fixture-env-shell.test.sh`)

- [x] 1.1 Add the ambient prefix scrub immediately after `export TMPDIR` (~line 18), before
  `REPO_ROOT`: `for _v in ${!GIT_@}; do [[ "$_v" == "GIT_LOCATION_VARS" ]] && continue; unset "$_v"; done; unset _v`
  with the #8051/2026-09-04-learning comment block (see plan §Proposed Solution item 1).
- [x] 1.2 Replace the five-name `env -u` chain in the leak probe (~lines 192–194) with an
  in-child prefix scrub before `source "$1"` (plan §Proposed Solution item 2); refresh the
  comment block at ~lines 185–191 keeping the #7917 history.
- [x] 1.3 Add the flag-gated hook-env replay arm before the summary section
  (`_GFE_HOOK_ENV_REPLAY` gate + injected `GIT_DIR`/`GIT_INDEX_FILE`/`GIT_AUTHOR_*`/`GIT_EDITOR`/
  `GIT_PREFIX`/`GIT_TERMINAL_PROMPT`/`GIT_EXEC_PATH`), asserting inner-run exit 0
  (plan §Proposed Solution item 3).
- [x] 1.4 Bump `readonly MIN_ASSERTIONS` 24→25 (line 25).
- [x] 1.5 Verify AC1–AC4: clean-env run green; hook-env run green; no `env -u GIT_` in the probe;
  `_GFE_HOOK_ENV_REPLAY` ≥2 hits.

## Phase 2 — #8053: anchor the recovery grep (`.github/workflows/apply-web-platform-infra.yml`)

- [x] 2.1 In the `::error::inngest-volume-recut REFUSED by Guard 2` message (~line 2325), change
  `grep -c "probe_schema=\$EXPECTED"` → `grep -c "^probe_schema=\$EXPECTED"` (one character; keep
  the `\$` escape intact).
- [x] 2.2 Verify AC5: `grep -cF 'grep -c "^probe_schema=\$EXPECTED"'` on the file → `1`; the
  unanchored pattern → `0`.

## Phase 3 — pin + validation

- [x] 3.1 Add "Row 6d" to `tests/scripts/test-inngest-volume-recut-gate.sh` inside the Row 6
  workflow-dispatch block (~after line 375): `grep -qF 'grep -c "^probe_schema=\$EXPECTED"' "$WF"`
  → `pass`, else `fail` naming #8053.
- [x] 3.2 Verify AC6: `EXPECTED=8; git show vinngest-v1.1.35:apps/web-platform/infra/inngest-bootstrap.sh | grep -c "^probe_schema=$EXPECTED"` → `1`.
- [x] 3.3 Verify AC7: `bash tests/scripts/test-inngest-volume-recut-gate.sh` exits 0 (floor holds).
- [x] 3.4 Verify AC8 (no collateral): `bash plugins/soleur/test/hook-git-env-coverage.test.sh`,
  `bash plugins/soleur/test/git-fixture-containment.test.sh`,
  `bash plugins/soleur/test/git-env-list-parity.test.sh` all exit 0.
- [x] 3.5 Mutation spot-check (Guard 1 row 1): temporarily delete the ambient scrub, run the suite
  under the AC2 env — the replay arm must report `[FAIL]`; restore.

## Out of scope

- `scripts/test-all.sh` / `lefthook.yml` nine-name unsets (canonical `GIT_LOCATION_VARS` list).
- #7822 census of other un-scrubbed suites (tracked separately).
- `plugins/soleur/test/lib/git-fixture-env.sh`, `tests/scripts/lib/inngest-host-dark-gate.sh`,
  `apps/web-platform/infra/inngest-bootstrap.sh` — context only, not edited.
