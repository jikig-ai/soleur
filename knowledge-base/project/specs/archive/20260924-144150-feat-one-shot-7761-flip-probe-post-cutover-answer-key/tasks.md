# Tasks: fix(7761) flip-rollout probe post-cutover answer key

Plan: `knowledge-base/project/plans/2026-09-24-fix-7761-flip-rollout-probe-post-cutover-answer-key-plan.md` (v4, deepened). The plan is the source of truth; these are its phases as a checklist.

## Phase 1: Setup

- [x] 1.1 Live precondition (plan 0.0, read-only)
  - [x] 1.1.1 Run the exact `DRIFT_GREPS` query with `--since '2026-09-23 19:36:32' --limit 5000`. Expect exactly 1 row: the 19:42:45Z resume, object-shaped, `_MACHINE_ID 3cff04d3…`.
  - [x] 1.1.2 Confirm that ISO `--since` exits 22 on the unmodified `scripts/betterstack-query.sh`.
  - [x] 1.1.3 Record both results for the PR body. Commit no live rows as fixtures.

## Phase 2: Core Implementation

- [x] 2.1 RED commit (plan Phase 0)
  - [x] 2.1.1 Fixture helpers:
    - Change `row()` to the object shape, with `_MACHINE_ID` and a `tag` argument.
    - Add `row_str()`, which also carries `_MACHINE_ID`.
    - Take one anchor epoch `NOW` and derive every timestamp from it.
    - Generate bulk fixtures in one `jq -n` pass, with distinct, strictly increasing `start_ts`.
    - Set `FLIP_ROLLOUT_STALE_AFTER_S` explicitly in `run_probe`.
  - [x] 2.1.2 Make the stub faithful to `LIKE` on the raw text:
    - OR-combine repeated `--grep` terms;
    - match lines that fail to decode on their literal text;
    - apply `--limit` newest-N;
    - gate the `--since` shape (anything else exits 22);
    - add `STUB_FAIL_ON_TERM`.

    Add stub self-checks: OR, newest-N **order**, the `--since` shape, and quoted-term matching (object rows match, string rows do not). Add the `FLIP_ROLLOUT_TEST_TARGET` seam.
  - [x] 2.1.3 Add the ISO normalisation assertions (`--since`, `--until`, and a non-ISO passthrough) to `tests/scripts/test-betterstack-query-archive.sh`.
  - [x] 2.1.4 Extend the `#6178 EMITTER PARITY` block (introduced by PR #7647) in `apps/web-platform/infra/cutover-inngest-workflow.test.sh` to check the 7761 probe:
    - extract anchored on the `DRIFT_GREPS=( … )` block only;
    - negative control: delete one term;
    - print a "probe retired" notice when the file is absent.
  - [x] 2.1.5 Add verdict-table parity to the 7761 suite, with a negative control:
    - take the tokens from code lines only (`verdict_fail` `$1` and `reason=` in `echo` lines);
    - read the table from the header block only.
  - [x] 2.1.6 Add fixtures F1, F1L, F2, F2b, F3, F4, F5, F7–F11 (F9 in both page orders), F12b (object `R` + string-shaped `noop-done` → PASS), F13, F13a, F14, F16, F18 (with `noop-done` rows after the `R`s), F21, F23–F37.
    - Each gets a descriptive `TEST:` line tagged with its F-id.
    - Each asserts its reason token anchored and positive, and the competing tokens negative.
  - [x] 2.1.7 Re-base the existing tests (plan 0.7). D7 becomes F24. Add inline "unreachable from the current emitter" comments on the `armed`, `flipping` and `flushed` rows.
  - [x] 2.1.8 Run everything against the unmodified code, record the red output, and commit.
- [x] 2.2 GREEN (plan Phase 1)
  - [x] 2.2.1 `scripts/betterstack-query.sh`: normalise ISO-Z for `--since` and `--until`, before `sql_quote`. Update the comment, and remove the "rejects the ISO" note in `scripts/cutover-inngest.sh`.
  - [x] 2.2.2 `mine <since> <limit> <term>...`:
    - shape-check the limit (`^[1-9][0-9]{0,5}$`);
    - field-isolate `host`, `host_name` and `SYSLOG_IDENTIFIER == inngest-cutover-flip` for emit_state queries;
    - decode: object as-is; string via `fromjson?` if it yields an object, else raw pass-through. Objects get `+ {_mid}` then `tojson`;
    - emit the `__PAGE_FULL__` sentinel from the raw page count (`grep -c .`); callers strip it before any emptiness check.
  - [x] 2.2.3 Inline answer key:
    - `POST_CUTOVER_FLAG`, `DONE_ENTRY_REASON`, `FLUSH_PATH_REASONS`, `FLUSH_PATH_FLAGS`, `DRIFT_GREPS`;
    - `EXPECTED_GUARD="7761"` (drop the env override);
    - delete `EXPECTED_FLAG`, `TERMINAL_SAFE_FLAGS` and `DRIFT_WINDOW`;
    - give `DERIVE_WINDOW` a `24h` default.
  - [x] 2.2.4 Drift query since the boundary. Take the findings from one `jq` call:
    - the exemption is resume shape only;
    - class = max(reason, flag);
    - flush-path, then drift, both through `verdict_fail`, printing every finding.
  - [x] 2.2.5 Refusals since the boundary. A query failure gives `TRANSIENT refusals_query_failed`.
  - [x] 2.2.5b Output hygiene:
    - the reason allowlist and `_flag_for_display` for findings;
    - `_mid` as an 8-hex prefix;
    - a 20-row cap with `(+N more)`;
    - the `FAIL:` line repeated last;
    - `seams=default|overridden:<names>` on the PASS line.
  - [x] 2.2.5c Sidecar hardening: a symlink gives `sidecar_is_symlink`, over 64 bytes gives `sidecar_oversize`, and `boundary_unparseable` prints only a length.
  - [x] 2.2.5d Boundary-precedes-machine check. Query `[AFTER−1h, AFTER]`; any flip-tag row with `_mid == M` gives `TRANSIENT boundary_inside_owning_machine_lifetime`.
  - [x] 2.2.5e `non_verdict` helper: read-path TRANSIENTs exit 3 once a supplied boundary is over 7 days old.
  - [x] 2.2.6 Truncation TRANSIENT, evaluated before `stale_image` and before ownership.
  - [x] 2.2.6b `stale_image` from raw stamping (`post_stamped`/`post_oldrev` over post-boundary flip-tag `noop-done`), computed before ownership.
  - [x] 2.2.7 Ownership: `M` from the newest stamped LIVE `noop-done`, the owning resume from the drift rows with guard and `_mid == M`, and liveness after `OWNED_SINCE`. `done_not_resumed` names the boundary, op=resume and the sidecar move.
  - [x] 2.2.8 Doppler arm: `done` is corroboration, any other value FAILs, and the wording is updated.
  - [x] 2.2.9 Header: shorter, with the verdict table, the retractions and the object-shape note.
- [x] 2.3 Boundary (plan Phase 2)
  - [x] 2.3.1 Create `scripts/followthroughs/inngest-cutover-flip-rollout-7761.after` containing `2026-09-23T19:36:32Z`. Record provenance and lifecycle in the comment and the commit message.
  - [x] 2.3.2 Drop `# repo-path: runtime` from the `AFTER_FILE` line.
  - [x] 2.3.4 Add the probe path to `.github/workflows/infra-validation.yml` `pull_request.paths` (with a comment naming #7761) and to `AFFECTED_INFRA_RUNNER_PATHS` in `scripts/lib/test-affected-paths.sh`.  _(review: the `AFFECTED_INFRA_RUNNER_PATHS` half was dropped as inert; the workflow-paths half stands)_
  - [x] 2.3.3 Re-point the R3-M20 inverse in `scripts/lint-followthrough-varq-ban.test.sh` at a synthetic fixture. Its count rises by 1.

## Phase 3: Testing

- [x] 3.1 Run the 7761 suite green, then set `MIN_ASSERTIONS` to the measured count.
- [x] 3.2 Run the Guard 1–3 mutation matrices against **copies** via `FLIP_ROLLOUT_TEST_TARGET`, after a pristine-copy run that exits 0. A row counts only when the suite exits 1 and the named F-id's own `FAIL:` line appears. Record the per-row results.
- [x] 3.3 Run the remaining checks: `test-betterstack-query-archive.sh`, `cutover-inngest-workflow.test.sh`, the lint and its test, the exec-bit test, the fixture-relative-assert test (regenerate the baseline only if a row changed), and `shellcheck`.
- [x] 3.4 Do the pre-merge live read with every `FLIP_ROLLOUT_*` unset. Expect `PASS: #7761 delivered … owned since 2026-09-23T19:42:45Z … seams=default`, and paste it into the PR body.
- [x] 3.5 Write the PR body: `Ref #7761` with no closing keyword, the note that the fix was already delivered by earlier replaces, "no host change", and #8697/#8698 as follow-ups.
- [ ] 3.6 Post-merge: re-run the probe from `main` and run `gh issue comment 7761` with the verdict. After the next sweep, check `gh issue view 7761 --json state`.
