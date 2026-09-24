# Tasks: fix(7761) flip-rollout probe post-cutover answer key

Plan: `knowledge-base/project/plans/2026-09-24-fix-7761-flip-rollout-probe-post-cutover-answer-key-plan.md` (v3). The plan is the source of truth; these are its phases as a checklist.

## Phase 1: Setup

- [ ] 1.1 Live precondition (plan 0.0, read-only)
  - [ ] 1.1.1 Run the exact `DRIFT_GREPS` query with `--since '2026-09-23 19:36:32' --limit 5000`. Expect exactly 1 row: the 19:42:45Z resume, object-shaped, `_MACHINE_ID 3cff04d3…`.
  - [ ] 1.1.2 Confirm that ISO `--since` exits 22 on the unmodified `scripts/betterstack-query.sh`.
  - [ ] 1.1.3 Record both results for the PR body. Commit no live rows as fixtures.

## Phase 2: Core Implementation

- [ ] 2.1 RED commit (plan Phase 0)
  - [ ] 2.1.1 Change `row()` to the object shape, add `_MACHINE_ID`, and add `row_str()`. Generate the bulk fixtures in one `jq -n` pass, with distinct, strictly increasing `start_ts`.
  - [ ] 2.1.2 Make the stub faithful to `LIKE` on the raw text:
    - OR-combine repeated `--grep` terms;
    - match lines that fail to decode on their literal text;
    - apply `--limit` newest-N;
    - gate the `--since` shape (anything else exits 22);
    - add `STUB_FAIL_ON_TERM`.

    Add one self-check for the `--since` gate.
  - [ ] 2.1.3 Add the ISO normalisation assertions (`--since`, `--until`, and a non-ISO passthrough) to `tests/scripts/test-betterstack-query-archive.sh`.
  - [ ] 2.1.4 Extend the `#6178 EMITTER PARITY` block in `apps/web-platform/infra/cutover-inngest-workflow.test.sh` to check the 7761 probe too, with a negative control.
  - [ ] 2.1.5 Add verdict-table parity to the 7761 suite, with a negative control.
  - [ ] 2.1.6 Add fixtures F1, F1L, F2, F2b, F3, F4, F5, F7–F11, F12b, F13, F13a, F14, F16, F18, F21, F23–F27, each with a descriptive `TEST:` line tagged with its F-id.
  - [ ] 2.1.7 Re-base the existing tests (plan 0.7). D7 becomes F24. Add inline "unreachable from the current emitter" comments on the `armed`, `flipping` and `flushed` rows.
  - [ ] 2.1.8 Run everything against the unmodified code, record the red output, and commit.
- [ ] 2.2 GREEN (plan Phase 1)
  - [ ] 2.2.1 `scripts/betterstack-query.sh`: normalise ISO-Z for `--since` and `--until`.
  - [ ] 2.2.2 `mine <since> <limit> <term>...`:
    - shape-check the limit;
    - decode with an explicit `if`: object → `(+ {_mid}) | tojson`, string → pass through;
    - emit the `__PAGE_FULL__` sentinel from the raw page count (`grep -c .`).
  - [ ] 2.2.3 Inline answer key:
    - `POST_CUTOVER_FLAG`, `DONE_ENTRY_REASON`, `FLUSH_PATH_REASONS`, `FLUSH_PATH_FLAGS`, `DRIFT_GREPS`;
    - `EXPECTED_GUARD="7761"` (drop the env override);
    - delete `EXPECTED_FLAG`, `TERMINAL_SAFE_FLAGS` and `DRIFT_WINDOW`;
    - give `DERIVE_WINDOW` a `24h` default.
  - [ ] 2.2.4 Drift query since the boundary. Take the findings from one `jq` call:
    - the exemption is resume shape only;
    - class = max(reason, flag);
    - flush-path, then drift, both through `verdict_fail`, printing every finding.
  - [ ] 2.2.5 Refusals since the boundary. A query failure gives `TRANSIENT refusals_query_failed`.
  - [ ] 2.2.6 Truncation TRANSIENT, evaluated before `stale_image` and before ownership.
  - [ ] 2.2.7 Ownership: `M` from the newest stamped LIVE `noop-done`, the owning resume from the drift rows with guard and `_mid == M`, and liveness after `OWNED_SINCE`. `done_not_resumed` names the boundary, op=resume and the sidecar move.
  - [ ] 2.2.8 Doppler arm: `done` is corroboration, any other value FAILs, and the wording is updated.
  - [ ] 2.2.9 Header: shorter, with the verdict table, the retractions and the object-shape note.
- [ ] 2.3 Boundary (plan Phase 2)
  - [ ] 2.3.1 Create `scripts/followthroughs/inngest-cutover-flip-rollout-7761.after` containing `2026-09-23T19:36:32Z`. Record provenance and lifecycle in the comment and the commit message.
  - [ ] 2.3.2 Drop `# repo-path: runtime` from the `AFTER_FILE` line.
  - [ ] 2.3.3 Re-point the R3-M20 inverse in `scripts/lint-followthrough-varq-ban.test.sh` at a synthetic fixture. Its count rises by 1.

## Phase 3: Testing

- [ ] 3.1 Run the 7761 suite green, then set `MIN_ASSERTIONS` to the measured count.
- [ ] 3.2 Run the Guard 1–3 mutation matrices as scratch edits. Every row must go red on its named fixture; revert each edit and record the results.
- [ ] 3.3 Run the remaining checks: `test-betterstack-query-archive.sh`, `cutover-inngest-workflow.test.sh`, the lint and its test, the exec-bit test, the fixture-relative-assert test (regenerate the baseline only if a row changed), and `shellcheck`.
- [ ] 3.4 Do the pre-merge live read. Expect `PASS: #7761 delivered … owned since 2026-09-23T19:42:45Z`, and paste it into the PR body.
- [ ] 3.5 Write the PR body: `Ref #7761` with no closing keyword, the note that the fix was already delivered by earlier replaces, "no host change", and #8697/#8698 as follow-ups.
- [ ] 3.6 Post-merge: re-run the probe from `main` and run `gh issue comment 7761` with the verdict. After the next sweep, check `gh issue view 7761 --json state`.
