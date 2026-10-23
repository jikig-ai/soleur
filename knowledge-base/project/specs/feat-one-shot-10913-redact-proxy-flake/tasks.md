# Tasks — fix: de-flake playwright-mcp-redact-proxy G1 row (#10913)

Plan: `knowledge-base/project/plans/2026-10-23-fix-playwright-mcp-redact-proxy-flake-plan.md`
Issue: #10913 (sibling #10919 — same case; diagnostics ask covered by FR-3)

## Phase 1 — Driver mode (FR-1)

- [x] 1.1 In `plugins/soleur/skills/agent-browser/test/fixtures/proxy-session-driver.py`, add `expect_death` to the `o = {...}` literal in `parse()` (default `False`) and a `--expect-death` parse arm setting it `True`.
- [x] 1.2 Skip the reply-wait loop when `o["expect_death"]` is set (proxy is expected to die, not answer); keep `--send` writes (BrokenPipe already suppressed) and the post-send drain pump.
- [x] 1.3 Add `EXPECT_DEATH_TIMEOUT_S = 30` constant; under `expect_death` the post-`--end` wait loop uses it instead of `o["timeout"]`; `p.kill()` + `rc="TIMEOUT"` unchanged on expiry. Update the docstring's flag list.
- [x] 1.4 Unit-check the driver manually: `python3 proxy-session-driver.py --out /tmp/x --proxy <v-load-outside proxy> --send "$INIT" --end eof --expect-death --server python3 <stub>` → rc file = 1.

## Phase 2 — Suite sweep + asserts (FR-2, FR-3, FR-4)

- [x] 2.1 In `plugins/soleur/skills/agent-browser/test/playwright-mcp-redact-proxy.test.sh`, replace `--timeout 3` with `--expect-death` on every `session()` call whose verdict asserts a startup exit: the ~68 `assert_refused_start` call sites, `v-load-outside` (~line 735), AND `m63` (~line 1151 — its `red` verdict asserts `rcof != "2"`, which a TIMEOUT satisfies → false green; CTO ruling 2026-10-23). Do NOT touch live-session rows (`odd`, served `m<N>` mutants, `inst-*`, `exit3`, `killchild`, spy/withheld) or the synthetic helper-control; `B1` rows are already driver-free. If a startup-exit row's `--timeout` proves load-bearing beyond the death wait, keep it and record it in the sweep-exemption list (CTO dissent clause).
- [x] 2.2 Split the `v-load-outside` `assert_true` into four per-observable rows: `assert_rc` (rc 1), `assert_true` zero stdout lines via `fact`, `assert_true` empty `child_pgid`, `assert_true+stderr_has (presence; needle appears 2x in a traceback — count pin would be fragile)` `_OutsideBase` ×1 (FR-3).
- [x] 2.3 Add `v-load-outside-slow` fixture + two rows (FR-4): module-level `import time; time.sleep(10)` before the `raise _OutsideBase()` — one row under `--expect-death` asserting rc 1, one row under `--timeout 3` asserting `rc=TIMEOUT` (negative control pinning the old deadline arm).
- [x] 2.4 Sweep-pairing check (AC-3): python/awk pass asserting each startup-exit verdict (`assert_refused_start`, `v-load-outside`'s rc-1 asserts, `m63`'s `rcof != "2"` verdict) pairs with a `session(` line carrying `--expect-death` (helper-control and `B1` exempt); `grep -n 'session .*--timeout'` output reviewed against the pairing list confirms only the live-session set retains `--timeout`.

## Phase 3 — Verification

- [x] 3.1 `bash plugins/soleur/skills/agent-browser/test/playwright-mcp-redact-proxy.test.sh` → exits 0, `0 failed`, cases ≥ `MIN_ASSERTIONS`.
- [x] 3.2 Mechanism proof: run the slow fixture under both modes; record before/after rc in PR body evidence.
- [x] 3.3 `SOLEUR_TEST_FORCE_ALL=1 bash scripts/test-all.sh` (or affected subset covering the suite) green on branch.
- [ ] 3.4 `gh workflow run ci.yml` on the branch; verify `test-scripts (5/8)` green (issue's prescribed verification).
