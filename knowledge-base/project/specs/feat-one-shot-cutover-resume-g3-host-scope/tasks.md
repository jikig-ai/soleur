# Tasks — fix(cutover): scope op=resume G3 host-audibility to the current server instance

Plan: `knowledge-base/project/plans/2026-09-24-fix-cutover-resume-g3-current-host-scope-plan.md`

## 1. Setup

- [ ] 1.1 Run the baseline suite: `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh`.
  Expect 753/0.
- [ ] 1.2 Record the `shellcheck -S warning scripts/cutover-inngest.sh` baseline (3 findings).
- [ ] 1.3 Confirm the CI runner's jq handles `fromdateiso8601` on the `Z` form, or plan the suite
  self-check row for it.

## 2. RED (one commit: test file only)

- [ ] 2.1 Extend the `call_flip_liveness_count` mocked `doppler()` to answer `secrets get HCLOUD_TOKEN`
  with a synthetic sentinel.
- [ ] 2.2 Add a mocked `curl()`:
  - [ ] It records argv and stdin to files.
  - [ ] It returns the real Hetzner list shape with synthetic values.
  - [ ] Failure modes mirror curl 8.x `-f`: rc 22 with EMPTY stdout, rc 28, rc 6.
- [ ] 2.3 Give the existing `rows`, `foreign` and `spoofed` fixture rows a
  `__REALTIME_TIMESTAMP` after the mocked `created`.
- [ ] 2.4 Add the `predecessor` mode (host-pair rows before `created`) and assert `'0'`.
- [ ] 2.5 Bump `_EXACT_FLOOR` in the same commit. Confirm the only FAIL is `predecessor`, then
  quote it for the PR body.

## 3. GREEN

- [ ] 3.1 Add `_hcloud_created_epoch` (pure) to `scripts/cutover-inngest.sh`:
  - [ ] exactly one name match;
  - [ ] normalize `+00:00` to `Z`;
  - [ ] print `__ABSENT__` or `__UNREADABLE__`.
- [ ] 3.2 Add `_inngest_server_created_epoch` (I/O):
  - [ ] token on stdin via `curl -H @-`;
  - [ ] body never echoed;
  - [ ] always return 0;
  - [ ] a `::warning::` names the cause, including the queried name and token project for absent.
- [ ] 3.3 Add `_current_instance_row_count` (pure): host pair AND decimal `__REALTIME_TIMESTAMP`
  ≥ floor × 10^6. A missing timestamp is excluded.
- [ ] 3.4 Rewrite `_flip_liveness_count` and `_luks_liveness_count`:
  - [ ] read the anchor first, and return `__UNREADABLE__` if it fails;
  - [ ] print the anchor `::notice::` with `created` and the age;
  - [ ] filter and print the count;
  - [ ] keep the `rows=$(_bs_query_rows …)` line shape.
- [ ] 3.5 Write the rationale comment block. Stay out of L50–L90, which PR #8690 touches.
- [ ] 3.6 Harness: awk-extract and eval the three new functions, with non-vacuity asserts.

## 4. Wording, coverage, runbook

- [ ] 4.1 Reword the `unreadable` arms of resume G3 and LUKS G3 to point at the `::warning::`
  above. Add the young-vs-old server-age sentence to both `silent` arms.
- [ ] 4.2 Add the Guard 1 rows: `current`, `mixed`, `no-ts`, `anchor-absent`, `anchor-fail`,
  reorder, H1 self-check and H2 must-PASS.
- [ ] 4.3 Add the Guard 2 decode table and the argv, stdin and body sentinel rows, plus the
  "returns 0 under set -e" row.
- [ ] 4.4 Add the `call_luks_liveness_count` harness with `predecessor` and `current` cases.
- [ ] 4.5 Add the pins: `_flush_latch_count` references neither new function, and
  `hcloud_server.inngest` has no `create_before_destroy`.
- [ ] 4.6 Verify the existing pins stay green unmodified (AC8), and set `_EXACT_FLOOR` to the
  measured count.
- [ ] 4.7 Update `knowledge-base/engineering/operations/runbooks/inngest-server.md` §op=resume G3.
- [ ] 4.8 Confirm shellcheck shows no new findings.

## 5. Verification

- [ ] 5.1 Run the read-only live replay: floor `0` vs floor `created` over one 18 h `noop-` row
  set. Record both counts in the PR body.
- [ ] 5.2 Run the full suite and check it exits 0.
- [ ] 5.3 Walk every Acceptance Criterion, AC1–AC12.
