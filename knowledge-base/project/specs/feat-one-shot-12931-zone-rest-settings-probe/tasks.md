# Tasks: fix(cf-token-scope) zone-rest settings PATCH probe body

Plan: `knowledge-base/project/plans/2026-11-26-fix-cf-token-scope-zone-rest-settings-probe-body-plan.md`
Ref #12931 (never `Closes`).

## Phase 1 — Setup / RED (test file only)

- [ ] 1.1 Mock write branch: `MOCK_WRITE_OVERRIDE` first; then `/zones/[^/]+/settings$` with a non-JSON body →
  `400` code 6007 for every token; then the token default (settings URL denied → 403 code 9109). Comment that the
  grant's 400 is assumed until Phase 5 measures it.
- [ ] 1.2 One preamble block above the D12c single-site assertion: `INV_BODY`, `SET_BODY` (parsed from source),
  hardcoded `WANT_SET_BODY`, `D12C_WRITE_ANCHOR='--data-binary "$w_body"'`.
- [ ] 1.3 `run_mut <label> <anchor> <replacement> <want-exit> <want-writes> <want-doppler-reads>` helper beside
  `d12c_mut` (vacuous-anchor refusal; runs the temp copy through the mock with fresh logs).
- [ ] 1.4 Add M0s, M0h, M2 per-URL body + deny-first, M2w, M5d (GET line counted twice), M11a-e, M10 updates.
- [ ] 1.5 Run the suite against the unmodified script; confirm M2 reds with `verdict=inconclusive`.

## Phase 2 — Core implementation (`plugins/soleur/skills/cf-token-scope/scripts/cf-token-scope.sh`)

- [ ] 2.1 `readonly SETTINGS_PROBE_BODY='{"items":[{"id":"cf_token_scope_probe_nonexistent_setting","value":"cf_token_scope_probe_never_valid"}]}'`.
- [ ] 2.2 6th row field on every write row (`invalid`; only the settings PATCH row `settings-json`); all 5 read
  sites read it (`_k` added to the `unset` line).
- [ ] 2.3 Static guard after `mig_url()`, before the dry-run block, looping over the arrays directly: body-kind set
  and settings-json URL template always; jq shape check (prefix inline, `>/dev/null`) gated on `command -v jq`.
- [ ] 2.4 `mig_req`: `local kind="${4:-}"`, `local w_body` (no initializer), closed `case` → two constants,
  `*) exit 2`, settings-json URL refusal, one curl with `--data-binary "$w_body"`.
- [ ] 2.5 `MIG_SETTINGS_LIST=""` init; capture on the authorized settings control; collision pre-check (jq to
  `/dev/null`, rc 0 → exit 2, rc 1 → proceed, else exit 2); settings-json row skipped as inconclusive when the list
  is empty.
- [ ] 2.6 Write loop passes `w_kind` to both `mig_req` calls.
- [ ] 2.7 Dry-run: both literals, the body-kind legend, per-row `(body-kind <kind>)`, recipes with
  `--data-binary \"\$w_body\"`; no new text containing `curl`.
- [ ] 2.8 Prose: header invariant 1, top summary, `INVALID_BODY` comment, `mig_req` comment, `usage()`,
  `mig_fatal` and pass messages (keep "a mutation may have landed"; no comment containing the write anchor).

## Phase 3 — Testing and docs

- [ ] 3.1 Regenerate the changed `D12C_CANON` lines from `bash --pretty-print`; review the diff.
- [ ] 3.2 `D12C_FLAGS` (F) admits only `"$w_body"`; single-site count via `D12C_WRITE_ANCHOR`; `w_body=` count = 2.
- [ ] 3.3 Guard Contract mutants as `run_mut` / `d12c_mut` lines (Guards 1-3), harness must-PASS rows.
- [ ] 3.4 `SKILL.md` (Usage intro, Migration profiles bullet + body column, exit 4) and the runbook L49 bullet.
- [ ] 3.5 Raise `MIN_ASSERTIONS` to the new total.
- [ ] 3.6 Run `bash plugins/soleur/test/cf-token-scope.test.sh`, `bash tests/scripts/test-cf-account-migration-runbook.sh`,
  `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`, `shellcheck` on both bash files, and
  the AC11 grep.

## Phase 4 — Post-merge (agent)

- [ ] 4.1 Run the staged zone-rest probe from `main`; post the verdict lines and the settings grant status/code on
  #12931; route per the plan's Phase 5 table (swap-0b stays held).
