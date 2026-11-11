# Tasks — feat-one-shot-12579-enqueue-rejection

Plan: `knowledge-base/project/plans/2026-11-11-fix-unsuppress-enqueue-rejection-plan.md`
Issue: #12579 (`Closes #12579` in PR body). Tracking issue for the deferred retry arm: #12652.

## Phase 1 — RED: pin the failing behavior in the fixture suite

- [x] 1.1 In `.github/scripts/test/test-bump-inngest-bootstrap-pin.sh`, add to the `enqueuefail` fixture block (~line 1020): `assert_out_has 'g1.enqueuefail:reason' 'gh-stub: enqueuePullRequest rejected'` — fails today because `2>/dev/null` discards the stub's stderr.
- [x] 1.2 Add a flatten/bound row: extend the `MOCK_GH_ENQUEUE_FAIL` stub arm (~line 355) or add a `MOCK_GH_ENQUEUE_FAIL=2` variant emitting a two-line stderr message (optionally containing a literal ESC byte); assert the `::warning::` line is single-line, the raw second line does NOT appear verbatim in `$LAST_OUT`, and no control byte survives.
- [x] 1.3 Add a fallback row: stub exits 1 with empty stderr → assert the warning prints the `no stderr captured` fallback (must-PASS input differing from the canonical stub).
- [x] 1.4 Run `SOLEUR_FIXTURE_PACKED=1 bash .github/scripts/test/test-bump-inngest-bootstrap-pin.sh` — confirm the new rows are RED and every pre-existing row stays green.

## Phase 2 — GREEN: script change

- [x] 2.1 In `.github/scripts/bump-inngest-bootstrap-pin.sh` (~line 651): change the enqueue capture's `2>/dev/null` to `2>&1` so the rejection lands in `enq_out`.
- [x] 2.2 In the `else` arm: `enq_reason=$(tr '\n' ' ' <<<"$enq_out" | tr -d '[:cntrl:]' | cut -c1-300)` — the repo-canonical pipeline (precedent: same script :294/:377; `tr -d '[:cntrl:]'` from `vinngest-digest-freshness.sh:149`/`:279`) — and embed `${enq_reason:-no stderr captured (timeout or empty response)}` in the `::warning::` line (keep the existing `armed auto-merge remains` tail).
- [x] 2.3 Re-run the fixture suite — all rows green; update `MIN_ASSERTIONS` (line 84) to the new green count and append the count bump to the comment's running history.
- [x] 2.4 Success-path regression: confirm the `enqueue` fixture still prints `enqueued … position 1` (jq parse unaffected by `2>&1`).

## Phase 3 — Documentation + decision record

- [x] 3.1 Extend the comment block above the arm (~lines 634–645) with the confirmed precondition: `enqueuePullRequest` is refused while a REQUIRED status check is pending/failed/missing (`Pull request Required status check "<name>" is expected.`); admission gates on the required-check SET — failing non-required advisory contexts do not block (learning `2026-11-10-merge-queue-admission-is-not-pr-head-green`, PR #12520); refusal on a fresh PR is expected; the arm's value is already-green heads where armed auto-merge did not self-enqueue (#12489); re-evaluate via #12652 if a refusal is ever seen while required checks are green.
- [x] 3.2 Append a dated addendum entry to `knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md` after the `### Addendum 2026-11-09 (#12508)` section (heading :1180, ends ~:1217; insert before the `### Addendum 2026-11-09: max_entries_to_build` heading at :1218): the #12562 refusal observation, the documented protection-met precondition, the unsuppressed warning as per-run evidence channel, and deferral of retry-on-check-complete to #12652.
- [x] 3.3 Reference #12652 in the PR body (ship phase).

## Phase 4 — Verify acceptance criteria

- [x] 4.1 AC1: `sed -n '/enq_out=/,+2p' .github/scripts/bump-inngest-bootstrap-pin.sh | grep -c '2>/dev/null'` → `0`.
- [x] 4.2 AC2: `grep -n "tr -d '\[:cntrl:\]'" .github/scripts/bump-inngest-bootstrap-pin.sh` → ≥1 hit in the `else` arm; `grep -n 'enq_reason' .github/scripts/bump-inngest-bootstrap-pin.sh` → ≥2 hits; `cut -c1-300` on the assignment line.
- [x] 4.3 AC3: fixture suite exits 0; `MIN_ASSERTIONS` equals the new green count.
- [x] 4.4 AC4: `grep -n 'required status check\|protection' .github/scripts/bump-inngest-bootstrap-pin.sh` → ≥1 hit inside the comment lines.
- [x] 4.5 AC5: `grep -n '12562' knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md` → ≥1 hit.
- [x] 4.6 AC6: `gh issue view 12652 --json state -q .state` → `OPEN` and the issue is referenced in the PR body.

## Execution notes

- 2.2 shape correction (measured): the prescribed `<<<"$enq_out"` herestring appends a newline even when `enq_out` is empty — `tr` flattens it to a space, so `enq_reason=" "` and the `no stderr captured` fallback could never fire (caught RED→GREEN by the `enqueuefailempty` row). Shipped as `printf '%s' "$enq_out" | tr '\n' ' ' | tr -d '[:cntrl:]' | cut -c1-300` — same canonical pipeline, empty input stays empty.
- 4.1 AC1 caveat: the `sed -n '/enq_out=/,+2p'` span reaches line :671's success-path jq `2>/dev/null` (pre-existing, unrelated to the mutation capture). The `gh api graphql` capture itself ends `2>&1` (:669-670); the RED run proved the revert fails the reason rows. Semantic intent satisfied.
- 4.6 AC6: #12652 verified OPEN; PR-body reference lands in ship phase.
