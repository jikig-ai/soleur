# Tasks: feat-one-shot-10432-web1-workspaces-protection-check

Plan: `knowledge-base/project/plans/2026-11-10-infra-web1-workspaces-volume-protection-check-plan.md`.
Issue #10432 (PR body: `Closes #10432`, `Ref #9927`). Draft PR #12563. Decisions: `decision-challenges.md` (27 rows; 20-27 from review round 1).

## Phase 1 — Setup and suite (tests first)

- [x] 1.1 Phase 1a: green refactor of `plugins/soleur/test/sole-copy-drift-check.test.sh` against the UNCHANGED workflow
  - [x] 1.1.1 `use_entry inngest|web1` owns every per-entry name; delete the top-level `NAME`/`VOL_ID`, `OK_KEYS`, `TITLE_*` assignments
  - [x] 1.1.2 Both ids as plain literals (`VOL_ID` per entry); retire the split `WEB1` constant
  - [x] 1.1.3 Per-path `gh api commits` stub (`$S/api.<file>.json`, records `gh api commits path=<file>`); keep `#!/usr/bin/env bash`
  - [x] 1.1.4 `mk_tf` / `set_api` parameterized; `assert_fixture_dir` on every directory operand; `printf`, no heredoc in quoted strings
  - [x] 1.1.5 Invariants: other-entry id and name bans, the `issues.json` id ban, the commits-path check
  - [x] 1.1.6 Run: `195/195 passed`, `FLOOR=195`, `TABLE_ROWS=126` unchanged; commit alone
- [x] 1.2 Phase 1b: RED rows
  - [x] 1.2.1 S0b: `gha-expr.py value "matrix.nope" '{}'` exits 3; `matrix.entry` present renders
  - [x] 1.2.2 Harness: `rows.json`, row selection by `entry` (zero or two matches exit 3), `matrix` in `refs()`/`check()`; E1 requires the two include rows
  - [x] 1.2.3 Shape: `matrix-shape` (strategy keys, `fail-fast` False with absent a violation, exactly 2 rows, exact key set, entry set, per-key value patterns, job `name:`), `id-placement` replacing `web1-id`; their S2 mutants
  - [x] 1.2.4 Pins: N1 from `rows.json`; N1b = two sweep literals equal to the inngest row; N1c (ADR-119 addendum section with the backtick-tolerant regex, runbook 6604 read-only subsection line); N3 `file_unreadable` check moves to `Decision record: ${ADR}.`, adr-file existence, web-1 document pointers
  - [x] 1.2.5 Web-1 rows: WV1-WV8, WV3b, WT1, WT3, WR1 (real `workspaces-luks.tf`), WF1, WF3, WF12, WX5, WX7, WX9, WX16
  - [x] 1.2.6 Cross-entry rows C1-C6, C8 (must PASS), C9 (cancelled leg), C10 (checkout failed, files via `GH_REPO`); seeds carry the clear step's author/label/state and a same-`SCEN` positive control; C3 writes the other file with `set_age_other`
  - [x] 1.2.7 Harness rows: H1 extension, H11a-d (H11b/c against a `gha-expr.py` copy without its strict branch, exact rc 3 and stderr, instrument control), H12, the `use_entry web1` constants row, the selected-entry invariant (`result.json` entry equals `$ENTRY`), the N1c empty-addendum, two-match and emptied-runbook-section rows, the `date` shim for V3b/WV3b
  - [x] 1.2.7b WX16 via `file_finding`-only overrides (`VERDICT=bogus`, `ENTRY=zzz`) with the probe reporting lifted; assert step outcome, slug line, `issues.json` unchanged
  - [x] 1.2.8 F1 asserts today's Inngest decision sentence exactly; `recipe_vocab` gains `106443278`
  - [x] 1.2.9 Run against the unchanged workflow: RED at E1; commit separately
  - [x] 1.2.10 Run the RED suite against a scaffold-only workflow copy (matrix rows, `fail-fast: false`, steps unchanged): the 126 existing rows green, every new W/C row red with its own message; list them in `mutation-proofs.md`

## Phase 2 — Core implementation

- [x] 2.1 `plugins/soleur/test/lib/gha-expr.py`: unknown `matrix.*` raises `ExprError`; docstring states the divergence
- [x] 2.2 `.github/workflows/scheduled-terraform-drift.yml`, job `sole-copy-protection-check` only
  - [x] 2.2.1 `name:` with `matrix.entry`; `strategy` with `fail-fast: false` and the two include rows
  - [x] 2.2.2 `tf_commit` and `probe` read row values through `env:`; `readonly VOLUME_ID_PIN="$PIN"`; awk `-v res=` with the `[{]` pattern; the three volume-naming `finish()` notes use `${SUBJECT}`
  - [x] 2.2.3 `file_finding`: `case "${ENTRY}:${VERDICT}"` with four named arms (Inngest strings copied, never retyped) and one `*)` arm keeping `sole_copy_finding_filer_unexpected_verdict` with the `entry:verdict` pair
  - [x] 2.2.4 `file_unreadable`, `clear`, `notify`: `${SUBJECT}` / `${ADR}` / `${{ matrix.* }}`; step names entry-neutral; `GH_REPO: ${{ github.repository }}` on `file_finding`, `file_unreadable`, `clear`
  - [x] 2.2.5 Job comment: both rows, forcing functions (re-protect issue; Guard B4), the combined-`result` check-in note beside `tracked: #10430`, ADDING AN ENTRY list
- [x] 2.3 Suite green; set `FLOOR` and `TABLE_ROWS` to the realized numbers in the same commit

## Phase 3 — Sibling edits

- [x] 3.1 ADR-119: append `## Addendum — 2026-11-10 (#10432, recurring delete-protection check for the volume)` (pin as `Hetzner id 106443278`, correction note without that form, pin-bump list, accepted windows, what it does not defend)
- [x] 3.2 ADR-282: append the "pin moves to the matrix row" note
- [x] 3.3 Runbook 6894: pin-bump checklist count three -> two plus the inngest row
- [x] 3.4 Runbook 6604: append top-level `## Read back the delete-protection flag (read-only token)` (6894 5c shape); rewrite the four "Verify the retired end state" GETs in the same shape (`--only-secrets`, missing-token guard, `curl --config -`); run the new one-liner once (expect `protected`; never fall back to the read/write token)
- [x] 3.5 `infra-credential-tiers-8209.md` register row: one GET per matrix leg
- [x] 3.6 `token-drift-workflow-causes.test.sh` R3b literal
- [x] 3.7 `scripts/lib/test-affected-paths.sh`: add `workspaces-luks.tf`, ADR-119, runbook 6604 (sorted)

## Phase 4 — Testing and verification

- [x] 4.1 Timed suite run; record wall/user/sys before and after in `mutation-proofs.md`
- [x] 4.2 Mutation proofs on copies for every non-S2 Guard 1-3 row; results in `mutation-proofs.md`
- [x] 4.3 Delete one new row block on a suite copy: outer count fails
- [ ] 4.4 `token-drift-workflow-causes.test.sh`; ratchets (`fixture-dir-operand-assert`, `fixture-relative-assert`, `guard-vacuity-floor`, `grep-q-pipe-guard`, `alarm-issue-filing-guard`)
- [x] 4.5 Workflow readers: every test-file hit of `git grep -l scheduled-terraform-drift -- '*.test.*' 'tests/'` (floor list in plan Phase 4.6, incl. `sentry-monitor-iac-parity.test.ts`, `cron-terraform-drift.test.ts`, `check-cloudflare-token-drift.test.sh`, `git-data-rung2-rehearsal.test.sh`, `inngest-provision-rehearsal.test.sh`, `cf-tunnel-liveness-gate-mutations.test.sh`)
- [x] 4.6 YAML parse; Phase 4.8 byte-identity check (first half: only the notify `subject:`/`body:` lines listed; second half: substituted templates and the moved `TITLE_*` block diff empty)
- [x] 4.6b Confirm read-only that the `scheduled-terraform-drift` Sentry monitor still routes to a person
- [x] 4.7 `lint-guard-contract.py` on the plan; `git diff --name-only origin/main...HEAD` lists no `.tf`/cloud-init/user_data
- [ ] 4.8 CI `merge_group` run is the Guard 1 evidence

## Review round 1 (PR #12563, CTO rulings 20-27)

- [x] R.1 Docs: decision-challenges rows 20-27; ADR-119 addendum (re-protect issue as the forcing function, detach not
  observed, pin bump by `git grep -n 106443278`, steps parameterised, correction worded to the record); B4 comment line in
  `workspaces-luks.test.sh`; runbook 6604 verify block (`jq` inside the guarded wrapper, `--max-time 30`), read-back
  `--max-time 30`, `volume-gone` rows (6604, 6894) point at the 8209 project listing; 6894 pin list regenerated as a
  dated note; 6604 stale-example note; 8209 row date and attempt count; plan rulings 20-23 and 26
- [x] R.2 Code: workflow, suite, `gha-expr.py` revert, `mutation-proofs.md` (rulings 20 item 2, 21-23, 26, 27; R1, R3,
  R4 code half, R6 workflow copies, R7-R10)

## Review round 2 (PR #12563, ledger F1-F12, CTO ruling 28)

- [x] R2.1 Code: the shape check pins exact sets (ordered step list, per-step keys, env names and `if:`, workflow env names,
  checkout SHA and identity, notify `with:`, expression context roots); the harness refuses an unmodelled context or action
  (H11e); `rb_line_ok` pins the exact wrapper, stdin construct, curl argument grammar and token-name count; per-case
  verdict-line counts; N4 re-scoped to the job's own comment block with ruling 28's requirements and bans; derived
  cross-entry ban; negative controls for the sum clause, n1c's 404 clause and the new H15/H17 mutants; FLOOR 278
- [x] R2.2 Docs: ruling 28's four text changes and decision-challenges row 28; ADR-119 email and window (iii) corrections,
  #12608; pin literals removed from the 6604 note, the read-back prose and the ADR-119 bump sentence; 6604 verify-block
  note on lines 1 and 3; 6894 regenerated bullet; postmerge `volume-gone` prose; fail-fast wording; plan constants
- [ ] R2.3 F12 (6894 "Read-backs after `destroy`" to `--only-secrets` + stdin header): skipped, see the round-2 report

## Phase 5 — After merge

- [ ] 5.1 First run on `main` (scheduled, or a `workflow_dispatch` watched with Monitor): `verdict=matches-declared` and `(clean)` in both `(inngest)` and `(web1)` legs
- [ ] 5.2 Ship phase: re-run the `unrouted` grep on current `origin/main`, then close #11163 with the evidence comment
