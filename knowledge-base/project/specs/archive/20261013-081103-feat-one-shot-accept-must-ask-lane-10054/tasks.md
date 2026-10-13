# Tasks: accept the hosted must-ask lane (ADR-284)

Plan: `knowledge-base/project/plans/2026-10-12-feat-accept-hosted-must-ask-lane-plan.md`. Tracker #10054 (`Ref`, never `Closes`).
Draft PR #10101. Do not merge without the operator's explicit go-ahead; the Guard 2 fix must be merged before 2026-10-13T18:00Z.

## Phase 0 - Re-time the soak directives (first; the 24 h value is already due)

- 0.1 Derive T0 from `gh run view 38223902738` (`release-outcome.completedAt`); confirm no SDK or sandbox-option change since `dfb9e2dba5`.
- 0.2 Edit the `earliest=` line of #9976 (2026-10-13T08:40:00Z) and #9776 (2026-10-19T08:40:00Z) with the guarded loop; re-read both
  bodies through the sweeper's awk parse; update the prose line beside each directive.
- 0.3 Comment on #9976, #9776, #10054 with T0, run id, old and new values (no closing keyword).

## Phase 1 - Guard 2 first (RED tests, then the script)

- 1.1 Write the failing rows in `scripts/followthroughs/hosted-destroy-ask-window-9776.test.sh`: H0 (contamination shape), M1-M4, M6-M9, H1, H2.
- 1.2 Implement isolation (`MENTIONS`, `DECODABLE`, lane-row decode; raw-count truncation check kept), the raw-SQL liveness arm and
  the 7 d zero-ask exit 5 with the flip pointer in `hosted-destroy-ask-window-9776.sh`.
- 1.3 Run the suite; run the live 24 h wrapper and confirm no SHAPE_DRIFT (first line `hosted destroy-ask window 24h`).

## Phase 2 - Extend the real-SDK probe

- 2.1 Throwaway `HOME`; comma-list `PROBE_ONLY`; provenance fields on every line; header update.
- 2.2 Cases: `member-force-push-default`, `grant-live-control` (preconditions), `grant-force-push-default`, `gh-repo-delete`.
- 2.3 In-process Sentry capture and assertions; `PROBE_DECODE_ONLY` row; `PROBE_PREFLIGHT` case.
- 2.4 Run the baseline, the decode-only row and the Guard 1 rows M2-M5; record verbatim with the deployed `build_sha` from `/health`.

## Phase 3 - Telemetry readout (self-pulled)

- 3.1 Better Stack: allowlist quote, retention figure, archive-arm control, app-container positive control, lane counts over [T0, now].
- 3.2 Sentry: four ops since T0, release control, 30 d retention control. Apply the interpretation rule literally; counts only, under-5 rule.

## Phase 4 - Bound the inert window

- 4.1 Scratch detached worktree at `dfb9e2dba5^`, `npm ci`, copy the extended probe; record the feature-worktree tree invariants.
- 4.2 Controls (pre-fix on 0.3.284 FAILs, fixed on 0.3.284 PASSes); Tier 1 pins x 2 runs; per-pin code-side check with `git show`.
- 4.3 Tier 2 only if two adjacent pins disagree (cap 6 versions x 2); map version to production deploy dates; remove and prune the scratch worktree.

## Phase 5 - Records

- 5.1 Post-mortem (measured window, bisect commands, CLO-cleared notice edit only, statuses, no resolved).
- 5.2 ADR-284 (C9 block, proposed equivalence, Status sentence, Flip checklist; status stays `adopting`).
- 5.3 ADR-277 addendum dated soak-open pointer; counsel-review audit one-line pointer (through the CLO agent).
- 5.4 `BASELINE_DECLARED_PROBES` bump; deferral issue (scheduled probe on SDK bump and synthetic canary), linked from ADR-284.

## Phase 6 - Verify and hand off

- 6.1 Run: soak suite, `c4-count-parity`, preflight-discoverability suite, guard-contract and infra lints, markdownlint; AC13 diff scope.
- 6.2 Commit; mark the PR ready only when `Ref` wording is verified; stop for the operator's go-ahead. Surface operator decisions 1-4.
- 6.3 Soak tail (not this PR): T1, T2 (flip PR via ADR-284 Flip checklist), T3.
