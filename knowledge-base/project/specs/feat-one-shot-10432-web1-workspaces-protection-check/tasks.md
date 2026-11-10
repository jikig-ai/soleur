# Tasks: feat-one-shot-10432-web1-workspaces-protection-check

Plan: `knowledge-base/project/plans/2026-11-10-infra-web1-workspaces-volume-protection-check-plan.md`.
Issue #10432 (PR body: `Closes #10432`, `Ref #9927`). Draft PR #12563. Decisions: `decision-challenges.md` (19 rows).

## Phase 1 — Setup and suite (tests first)

- [ ] 1.1 Phase 1a: green refactor of `plugins/soleur/test/sole-copy-drift-check.test.sh` against the UNCHANGED workflow
  - [ ] 1.1.1 `use_entry inngest|web1` owns every per-entry name; delete the top-level `NAME`/`VOL_ID`, `OK_KEYS`, `TITLE_*` assignments
  - [ ] 1.1.2 Both ids as plain literals (`VOL_ID` per entry); retire the split `WEB1` constant
  - [ ] 1.1.3 Per-path `gh api commits` stub (`$S/api.<file>.json`, records `gh api commits path=<file>`); keep `#!/usr/bin/env bash`
  - [ ] 1.1.4 `mk_tf` / `set_api` parameterized; `assert_fixture_dir` on every directory operand; `printf`, no heredoc in quoted strings
  - [ ] 1.1.5 Invariants: other-entry id and name bans, the `issues.json` id ban, the commits-path check
  - [ ] 1.1.6 Run: `195/195 passed`, `FLOOR=195`, `TABLE_ROWS=126` unchanged; commit alone
- [ ] 1.2 Phase 1b: RED rows
  - [ ] 1.2.1 S0b: `gha-expr.py value "matrix.nope" '{}'` exits 3; `matrix.entry` present renders
  - [ ] 1.2.2 Harness: `rows.json`, row selection by `entry` (zero or two matches exit 3), `matrix` in `refs()`/`check()`; E1 requires the two include rows
  - [ ] 1.2.3 Shape: `matrix-shape` (strategy keys, `fail-fast` False with absent a violation, exactly 2 rows, exact key set, entry set, per-key value patterns, job `name:`), `id-placement` replacing `web1-id`; their S2 mutants
  - [ ] 1.2.4 Pins: N1 from `rows.json`; N1b = two sweep literals equal to the inngest row; N1c (ADR-119 addendum section with the backtick-tolerant regex, runbook 6604 read-only subsection line); N3 `file_unreadable` check moves to `Decision record: ${ADR}.`, adr-file existence, web-1 document pointers
  - [ ] 1.2.5 Web-1 rows: WV1-WV8, WV3b, WT1, WT3, WR1 (real `workspaces-luks.tf`), WF1, WF3, WF12, WX5, WX7, WX9, WX16
  - [ ] 1.2.6 Cross-entry rows C1-C6, C8 (must PASS), C9 (cancelled leg)
  - [ ] 1.2.7 Harness rows: H1 extension, H11a-d, H12, the `use_entry web1` constants row, the N1c empty-addendum and two-match rows
  - [ ] 1.2.8 F1 asserts today's Inngest decision sentence exactly; `recipe_vocab` gains `106443278`
  - [ ] 1.2.9 Run against the unchanged workflow: RED at E1; commit separately

## Phase 2 — Core implementation

- [ ] 2.1 `plugins/soleur/test/lib/gha-expr.py`: unknown `matrix.*` raises `ExprError`; docstring states the divergence
- [ ] 2.2 `.github/workflows/scheduled-terraform-drift.yml`, job `sole-copy-protection-check` only
  - [ ] 2.2.1 `name:` with `matrix.entry`; `strategy` with `fail-fast: false` and the two include rows
  - [ ] 2.2.2 `tf_commit` and `probe` read row values through `env:`; `readonly VOLUME_ID_PIN="$PIN"`; awk `-v res=` with the `[{]` pattern; the three volume-naming `finish()` notes use `${SUBJECT}`
  - [ ] 2.2.3 `file_finding`: `case "${ENTRY}:${VERDICT}"` with four named arms (Inngest strings copied, never retyped) and one `*)` arm keeping `sole_copy_finding_filer_unexpected_verdict` with the `entry:verdict` pair
  - [ ] 2.2.4 `file_unreadable`, `clear`, `notify`: `${SUBJECT}` / `${ADR}` / `${{ matrix.* }}`; step names entry-neutral
  - [ ] 2.2.5 Job comment: both rows, forcing functions (re-protect issue; Guard B4), per-leg check-in note beside `tracked: #10430`, ADDING AN ENTRY list
- [ ] 2.3 Suite green; set `FLOOR` and `TABLE_ROWS` to the realized numbers in the same commit

## Phase 3 — Sibling edits

- [ ] 3.1 ADR-119: append `## Addendum — 2026-11-10 (#10432, recurring delete-protection check for the volume)` (pin as `Hetzner id 106443278`, correction note without that form, pin-bump list, accepted windows, what it does not defend)
- [ ] 3.2 ADR-282: append the "pin moves to the matrix row" note
- [ ] 3.3 Runbook 6894: pin-bump checklist count three -> two plus the inngest row
- [ ] 3.4 Runbook 6604: append "Read back the delete-protection flag (read-only token)"; switch the four "Verify the retired end state" GETs to `HCLOUD_TOKEN_READONLY`; run the new one-liner once (expect `protected`)
- [ ] 3.5 `infra-credential-tiers-8209.md` register row: one GET per matrix leg
- [ ] 3.6 `token-drift-workflow-causes.test.sh` R3b literal
- [ ] 3.7 `scripts/lib/test-affected-paths.sh`: add `workspaces-luks.tf`, ADR-119, runbook 6604 (sorted)

## Phase 4 — Testing and verification

- [ ] 4.1 Timed suite run; record wall/user/sys before and after in `mutation-proofs.md`
- [ ] 4.2 Mutation proofs on copies for every non-S2 Guard 1-3 row; results in `mutation-proofs.md`
- [ ] 4.3 Delete one new row block on a suite copy: outer count fails
- [ ] 4.4 `token-drift-workflow-causes.test.sh`; ratchets (`fixture-dir-operand-assert`, `fixture-relative-assert`, `guard-vacuity-floor`, `grep-q-pipe-guard`, `alarm-issue-filing-guard`)
- [ ] 4.5 Workflow readers: `terraform-drift-step-order`, `terraform-drift-sentry-leg`, `heartbeat-reconcile-issue-step`, `c4-count-parity`, `terraform-target-parity.test.ts`, `tests/scripts/test-argv-bearer-sweep.sh`, `test-apply-github-infra-mint-shape.sh`, `test-git-data-wipe-wedge.sh`; rerun `git grep -l scheduled-terraform-drift` for new hits
- [ ] 4.6 YAML parse; Phase 4.8 byte-identity check (only the notify `subject:`/`body:` lines listed)
- [ ] 4.7 `lint-guard-contract.py` on the plan; `git diff --name-only origin/main...HEAD` lists no `.tf`/cloud-init/user_data
- [ ] 4.8 CI `merge_group` run is the Guard 1 evidence

## Phase 5 — After merge

- [ ] 5.1 First run on `main` (scheduled, or a `workflow_dispatch` watched with Monitor): `verdict=matches-declared` and `(clean)` in both `(inngest)` and `(web1)` legs
- [ ] 5.2 Ship phase: re-run the `unrouted` grep on current `origin/main`, then close #11163 with the evidence comment
