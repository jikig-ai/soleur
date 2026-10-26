# Tasks: migrate the headless Pencil adapter to @pen.dev/cli, with a stale-file save guard

Plan: `knowledge-base/project/plans/2026-10-26-chore-migrate-pencil-adapter-to-pen-cli-and-stale-save-guard-plan.md`
Closes #11156 and #11168 (one PR). Tests come before the code they cover in every phase.

## Phase 1: Engine migration (#11156)

- [ ] 1.1 Tests and captured evidence first
  - [ ] 1.1.1 Capture a redacted real 0.3.13 transcript into `plugins/soleur/test/fixtures/pen-0.3.13-transcript.txt` and assert the stub reproduces each shape
  - [ ] 1.1.2 Update `pencil-repl-surface.test.ts` (table, escaping, validators with caps, `read_skill` pattern, prompt, Node floor 22.18.x vs 22.19.0)
  - [ ] 1.1.3 Update `pencil-response-classification.test.ts` (`Save failed:` is an error) and `pencil-error-enrichment.test.ts` (hint per stub, no `batch_get`/`edits` advice)
  - [ ] 1.1.4 Rewrite `fixtures/pencil-stub-repl.mjs` to the measured shapes, importing the table and prompt from the surface module
  - [ ] 1.1.5 Rewrite the key-gated `engine-contract-probe.sh` cases (stay RED until 1.5)
- [ ] 1.2 `pencil-repl-surface.mjs`: new table, prompt constant, nonce count builder, validators, `planSpawn` kept
- [ ] 1.3 `pencil-response-classify.mjs`: add `^Save failed:`
- [ ] 1.4 `pencil-error-enrichment.mjs`: one hint table feeding the 9 stubs
- [ ] 1.5 `pencil-mcp-adapter.mjs`
  - [ ] 1.5.1 Node gate 22.19.0 (numeric compare), key resolution (empty is unset), child env `PEN_CLI_KEY` only, rolling-tail redaction
  - [ ] 1.5.2 `findPenBinary()` identity check (realpath inside the package, name check, no PATH fallback)
  - [ ] 1.5.3 Register 8 live tools and 9 stubs; screenshot, export (contained `outputDir`, no rename), variables, editor-state, `read_skill` handlers; `Document:` line on `batch_design`
- [ ] 1.6 `pencil-save-gate.mjs`: nonce-anchored count parse; header cleanup
- [ ] 1.7 `check_deps.sh`: pin 0.3.13, `.bin/pen` detection with identity, leftover-package warning, auth check, Node floor, `realpath` fallback
- [ ] 1.8 `engine-contract-probe.sh` finished; write the redacted `probe-transcript.md`
- [ ] 1.9 Prose and docs
  - [ ] 1.9.1 `pencil-setup/SKILL.md` (registration, contract, one-writer rule, read-saves note, snapshot note)
  - [ ] 1.9.2 `ux-design-lead.md` (headless guidance via `read_skill`, drop `snapshot_layout`, out-of-engine post-save gate, no adapter rename) and regenerate the three mirrors with their sync scripts
  - [ ] 1.9.3 `brainstorm/SKILL.md` and `plan/SKILL.md` (byte-neutral pointer), `brainstorm-brand-workshop.md` case pattern, `constitution.md`

## Phase 2: Stale-file save guard (#11168)

- [ ] 2.1 Tests first: `fingerprintBytes`, `decideStale` over four baseline states, `runGuardedSave` ordering; stub-REPL cases (smaller-over-larger, own-save re-baseline, tested recovery, two sessions, refusal then respawn, removed file, startup window, probe window); sentinel for one emission and baseline sites
- [ ] 2.2 `pencil-save-gate.mjs`: fingerprint, tagged states, `decideStale`, stale refusal text, `runGuardedSave` hooks (bytes read, fresh read, confirmation)
- [ ] 2.3 `pencil-mcp-adapter.mjs`: `SaveBaseline` object, capture before `nodeSpawn`, commit with `outputFile`, `refusalPending`, positive `Saved <path>` confirmation
- [ ] 2.4 `SKILL.md` sharp edge for the stale rule, recovery and the window it cannot close

## Phase 3: Verify and record

- [ ] 3.1 `bun test plugins/soleur/test/pencil-*.test.ts`, pencil `*.test.sh` suites, `bash scripts/test-all.sh`, `check_deps.sh --check-adapter-drift`
- [ ] 3.2 Live probe: `doppler run -p soleur -c dev -- bash plugins/soleur/skills/pencil-setup/scripts/engine-contract-probe.sh` prints `PROBE OK`
- [ ] 3.3 Retired-term census, `lint-skill-body-budget.py`, hooks-unchanged diff, `c4-count-parity.test.sh`, read all three `.c4` files and record the result
- [ ] 3.4 ADR-304 through `soleur:architecture` (re-check the free ordinal across every `origin/*` ref)
- [ ] 3.5 `technical-ruling-gate.sh --branch` and markdownlint green; PR body with `Closes #11156`, `Closes #11168`
