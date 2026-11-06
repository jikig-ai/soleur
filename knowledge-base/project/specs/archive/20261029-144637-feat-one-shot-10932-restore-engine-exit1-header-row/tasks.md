# Tasks — feat-one-shot-10932-restore-engine-exit1-header-row

Plan: `knowledge-base/project/plans/2026-10-29-chore-restore-engine-exit-1-header-row-plan.md`

## Phase 1 - Engine header row

- 1.1 Re-check every `die 1` line precedes the first `crane` call (`grep -n 'die 1' scripts/registry-restore-from-ghcr.sh` vs first `$CRANE`/`crane_capture` line).
- 1.2 Insert the exit-1 row (first line must read exactly `#   1  INPUT ...`; the Observability probe is `grep -c "^#   1  INPUT"` -> 1) between the `0` and `2` rows of the header table in `scripts/registry-restore-from-ghcr.sh` (letter-initial label, 3 spaces before the digit, 2 after; no continuation line starting with digits + 2 spaces; no `docker pull`; no battery anchor fragments).
- 1.3 Verify: extractor prints `1 2 3 4 5 6 78`; emit codes unchanged vs `origin/main`; non-comment lines identical to `origin/main`; `bash -n` clean.

## Phase 2 - Stale comments and messages (tests, text only)

- 2.1 `tests/scripts/lib/restore-engine-header.sh` lines 8-11: reword per ruling Q1 (no `#10932`).
- 2.2 `tests/scripts/test-registry-pull-path-health.sh`: drop "tracked in #10932" in the A2 comment; fail message "(seven header rows, exit 1 included)".
- 2.3 `tests/scripts/test-registry-d10-workflow-wiring.sh` ~line 495: "fewer than 6" -> "fewer than 7". Leave `grep -vx 1`, `-ge 7`, `EXPECTED_ASSERTIONS=47`.

## Phase 3 - Runbook

- 3.1 `knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md` ~495-497: replace the "does not yet list exit 1" sentence (only that sentence).

## Phase 4 - Verify and ship

- 4.1 Run `test-registry-restore-from-ghcr.sh`, `test-registry-pull-path-health.sh`, `test-registry-d10-workflow-wiring.sh` (same pass counts as `origin/main`).
- 4.2 Run the mutation battery (~860 s) via the affected-tests harness as a backgrounded run; exit 2 = anchor collision (fix header text).
- 4.3 Confirm `git diff origin/main --name-only` excludes `.github/workflows/` and `apps/web-platform/infra/`.
- 4.4 Update draft PR #11518: body has `Ref #9757` and `Ref #10932` only (no closing keyword anywhere); mark ready; `gh pr merge 11518 --squash --auto`.
