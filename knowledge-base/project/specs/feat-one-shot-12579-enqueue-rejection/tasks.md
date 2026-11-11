# Tasks — feat-one-shot-12579-enqueue-rejection

Plan: `knowledge-base/project/plans/2026-11-11-fix-unsuppress-enqueue-rejection-plan.md`
Issue: #12579 (`Closes #12579` in PR body). Tracking issue for the deferred retry arm: #12652.

## Phase 1 — RED: pin the failing behavior in the fixture suite

- [ ] 1.1 In `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh`, add to the `enqueuefail` fixture block (~line 1020): `assert_out_has 'g1.enqueuefail:reason' 'gh-stub: enqueuePullRequest rejected'` — fails today because `2>/dev/null` discards the stub's stderr.
- [ ] 1.2 Add a flatten/bound row: extend the `MOCK_GH_ENQUEUE_FAIL` stub arm (~line 355) or add a `MOCK_GH_ENQUEUE_FAIL=2` variant emitting a two-line stderr message; assert the `::warning::` line is single-line and the raw second line does NOT appear verbatim in `$LAST_OUT`.
- [ ] 1.3 Add a fallback row: stub exits 1 with empty stderr → assert the warning prints the `no stderr captured` fallback (must-PASS input differing from the canonical stub).
- [ ] 1.4 Run `SOLEUR_FIXTURE_PACKED=1 bash .github/scripts/test/test-bump-inngest-bootstrap-pin.sh` — confirm the new rows are RED and every pre-existing row stays green.

## Phase 2 — GREEN: script change

- [ ] 2.1 In `.github/scripts/bump-inngest-bootstrap-pin.sh` (~line 651): change the enqueue capture's `2>/dev/null` to `2>&1` so the rejection lands in `enq_out`.
- [ ] 2.2 In the `else` arm: `enq_reason=${enq_out//[$'\n\r']/ }` then `enq_reason=${enq_reason:0:300}`, and embed `${enq_reason:-no stderr captured (timeout or empty response)}` in the `::warning::` line (keep the existing `armed auto-merge remains` tail).
- [ ] 2.3 Re-run the fixture suite — all rows green; update `MIN_ASSERTIONS` (line 84) to the new green count and append the count bump to the comment's running history.
- [ ] 2.4 Success-path regression: confirm the `enqueue` fixture still prints `enqueued … position 1` (jq parse unaffected by `2>&1`).

## Phase 3 — Documentation + decision record

- [ ] 3.1 Extend the comment block above the arm (~lines 634–645) with the confirmed precondition: `enqueuePullRequest` is refused while branch protection is unmet (`Pull request Required status check "<name>" is expected.`); refusal on a fresh PR is expected; the arm's value is already-green heads where armed auto-merge did not self-enqueue (#12489); re-evaluate via #12652 if a refusal is ever seen while checks are green.
- [ ] 3.2 Append a dated addendum entry to `knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md` after `### Addendum 2026-11-09 (#12508)` (~line 1216): the #12562 refusal observation, the documented protection-met precondition, the unsuppressed warning as per-run evidence channel, and deferral of retry-on-check-complete to #12652.
- [ ] 3.3 Reference #12652 in the PR body (ship phase).

## Phase 4 — Verify acceptance criteria

- [ ] 4.1 AC1: `sed -n '/enq_out=/,+2p' .github/scripts/bump-inngest-bootstrap-pin.sh | grep -c '2>/dev/null'` → `0`.
- [ ] 4.2 AC2: `grep -n 'enq_reason' .github/scripts/bump-inngest-bootstrap-pin.sh` → ≥3 hits.
- [ ] 4.3 AC3: fixture suite exits 0; `MIN_ASSERTIONS` equals the new green count.
- [ ] 4.4 AC4: `grep -n 'required status check\|protection' .github/scripts/bump-inngest-bootstrap-pin.sh` → ≥1 hit inside the comment lines.
- [ ] 4.5 AC5: `grep -n '12562' knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md` → ≥1 hit.
- [ ] 4.6 AC6: `gh issue view 12652 --json state -q .state` → `OPEN` and the issue is referenced in the PR body.
