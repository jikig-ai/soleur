# Tasks: feat-one-shot-plugin-version-visibility

Plan: `knowledge-base/project/plans/2026-10-11-feat-plugin-version-visibility-plan.md`
Slice A = items 2-4 + shared resolver (ships unconditionally). Slice B = item 1, the manifest stamp
(only if Phase 0 is Go; dark-launched).

> **Execution gate:** do Phase 0 (M2, M4, M5 at minimum), Phases 1-3, and the Slice-A parts of
> Phase 5. Phases 4 and 5.1/5.2 (Slice B + governance reversal) run ONLY if the operator confirms
> DC-1 in `decision-challenges.md`, Phase 0 is Go (M1, M3, p95 lag <= 120 min), and the "Slice B
> conditions" in the plan hold. Otherwise file the two issues under "Deferral tracking" and stop.

## Phase 0 — Falsification gate (Slice B go/no-go)

- 0.1 Build the clean-HOME local-marketplace harness (reuse 7471 measurements section 1.9 style)
- 0.2 M1: two-arm `claude plugin update` with changing vs constant `version` (git-subdir and relative-path sources)
- 0.3 M2: recorded version + cache dir name stamped vs keyless
- 0.4 M3: keyless marketplace entry + versioned plugin.json at git-subdir path; `claude plugin validate`
- 0.5 M4: SessionStart `systemMessage` rendering (stream-json hook events)
- 0.6 M5: `git ls-remote --tags --refs` latency/bytes on this repo
- 0.7 M6: refresh merge-lag baseline for last 30 `app/soleur-infra` PRs
- 0.8 Write `measurements.md` with explicit Go/No-go line; if No-go file the follow-up issue and skip Phase 4

## Phase 1 — Shared resolver (Slice A)

- 1.1 Write `plugins/soleur/test/plugin-version.test.sh` first (RED)
- 1.2 Implement `plugins/soleur/scripts/plugin-version.sh` (`--installed`, `--latest [--refresh]`, `--cached-latest`, `--compare`; jq with sed fallback)
- 1.3 Tag-filter rows: reject `vinngest-v*`, `web-v*`, `zot-image-*`, prerelease suffix; numeric order
- 1.4 Cache rows: stale, corrupt, unwritable dir; atomic write; 0700/0600

## Phase 2 — SessionStart hook (Slice A)

- 2.1 Write `plugins/soleur/test/version-banner-hook.test.sh` first (default-off zero-network proof)
- 2.2 Implement `plugins/soleur/hooks/version-banner.sh` (opt-in `SOLEUR_UPDATE_CHECK=1`, kill switch, background refresh, fail open)
- 2.3 Register one SessionStart block in `plugins/soleur/hooks/hooks.json` (matcher `startup`, timeout 10)

## Phase 3 — Command, help header, docs (Slice A)

- 3.1 Create `plugins/soleur/commands/version.md`
- 3.2 Edit `plugins/soleur/commands/help.md` Step 1 + header line only (leave Step 2.5 / Cursor column untouched)
- 3.3 Update README command count/table; run components, invocation-axis, harness parity suites; harness command mirrors
- 3.4 Legal: privacy-policy 4.1 + DPD carve-out, mirrors, `legal-doc-shas.ts`, five legal gates
- 3.5 README opt-in docs (`env` in settings)

## Phase 4 — Stamp pipeline (Slice B, gated)

- 4.1 Tests first: `is-plugin-version-stamp-commit.test.sh` (Guard 1 matrix), `stamp-plugin-version.test.sh`, `plugin-version-pr-guard.test.sh` (Guard 3 matrix)
- 4.2 Implement the three scripts
- 4.3 `stamp-plugin-version.yml` (workflow_run + dispatch `dry_run`, infra-privileged live path only, App token, concurrency group, dark-launch var) + `stamp-plugin-version.sh` incl. queued-PR rule and `--remove-key`
- 4.4 `version-bump-and-release.yml`: `gate` job (errors -> stamp=false, checkout depth 2); `reusable-release.yml` `check_changed` optional input; `web-platform-release.yml` passes it; extend `workflow-run-deploy-invariants.test.sh`; mirror carve-out in `prod-version-drift-check.sh` + test B8
- 4.5 `ci.yml` + `scripts/test-all.sh` wiring; update `plugin-version-fallback.test.ts`
- 4.6 `scheduled-marketplace-drift.yml` stale-stamp assertion (Guard 2) + keyless assertions; `actionlint`
- 4.7 Dry-run `workflow_dispatch` (flag off prints `would-stamp`)

## Phase 5 — ADR, rules, C4 (both slices)

- 5.1 Amend ADR-182 and ADR-017; write ADR-285 (`adopting`); sweep ordinal if renumbered
- 5.2 Edit rule body `wg-never-bump-version-files-in-feature` with `rule-body-lint` ack; edit prose surfaces
- 5.3 Read all three `.c4` files; update descriptions/edges; run c4 tests and `c4-count-parity`
- 5.4 Runbook note on the stamp window

## Phase 6 — Verify and ship

- 6.1 Run all new suites + `components.test.ts` + marketplace validator
- 6.2 PR: `semver:minor`, `## Changelog`, CPO sign-off recorded, decision-challenges rendered
- 6.3 (Slice B) Post-merge: green `dry_run` on main, `gh variable set PLUGIN_VERSION_STAMP --body on`, observe ONE staged live stamp (one stamp PR, no release/web run on its SHA, prod drift green)
- 6.4 (Slice B) Enroll soak follow-through script + tracker (>= 7 days AND >= 3 releases), then flip ADR-285 to accepted; failure action `--remove-key`
- 6.5 File the two deferral issues (plan "Deferral tracking")
