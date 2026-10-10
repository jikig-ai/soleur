# Tasks: canary DIAG bundle kernel-denial row and no-proc control probe (Ref #9860)

Plan: knowledge-base/project/plans/2026-10-10-fix-canary-diag-kernel-denial-and-proc-mask-rows-plan.md

Never `Closes #9860` (PR body uses `Ref #9860`). Do not archive the #9871 plan or spec. No production write without the
explicit per-command go-ahead recorded in the plan's gate table (G1-G4). Doppler reads only; never print a secret.

## Phase 0: User impact, sandbox, baselines

- 0.1 Read-only user-impact check first (Sentry feature=agent-sandbox / "sandbox required but unavailable" since 2026-10-09T04:52Z via scripts/sentry-issue.sh; GET only). Record in the PR body; if users are failing, flag the operator before merge.
- 0.2 Allocate ONE scratch copy: `SBX=$(bash "$ROOT/scripts/soleur-sandbox.sh" new canary-kdeny)`; run suites and mutants via `run-isolated`; restore pristine per mutant; `rm "$SBX"` before returning. On ALLOC-FAILED stop.
- 0.3 Baseline in the sandbox: `ci-deploy.test.sh` (568/568), `lint-shell-capture-exit.py`, `lint-orphan-test-suites.sh`.
- 0.4 Local masked-/proc repro with the exact docker run flags plus the `sdk_noproc` argv; record in the PR body.

## Phase 1: Tests first (ci-deploy.test.sh, all RED before any ci-deploy.sh edit)

- 1.1 `create_mock_kernlog`: ONE mock installed as `journalctl` and `dmesg` (switch on basename), knobs MOCK_KLOG_{OUT,RC,SLEEP} per name, recorder MOCK_KLOG_LOG, `/bin/sleep` for hangs, rc 127 = absent, synthesized fixtures only.
- 1.2 Mock default diag body gains `sdk_noproc rc=0`; `D_SECTIONS` gains `sdk_noproc`.
- 1.3 Update in place (same row count): D1c, D1i (`lines=11`), D3c2 (`-le 21`), D3c3, D4g (forged `kdeny` becomes raw), D6a, D9a/b, plus strings/comments saying "ten" or `host, hostsec, kernel, done`.
- 1.4 New rows D10a-h: placement+shape+recorder; realistic AppArmor mount denial reads `j=ok hits=1 mproc=1` with closed-key fields and no name/comm/pid; table-driven ladder states; both-rungs hang via diag_inert; 4 MB then a final denial still counted (newest-first); credential scrub on both sinks with control; census with positive control; 200-char tail boundary.
- 1.5 New row D11: the REAL script's `sdk_noproc` has --unshare-user --unshare-pid and no --proc, while `sdk_probe` keeps it.
- 1.6 Raise CI_DEPLOY_ASSERT_FLOOR 568 to the measured count (expected 577) with a dated changelog line.

## Phase 2: Implementation (ci-deploy.sh)

- 2.1 `_canary_kdeny_read` inside CANARY_DIAG_BEGIN..END with a SOLEUR-DEBT removal-trigger marker: journal rung (`-n 400 --since=-5min`), dmesg rung (`tail -n 400` before `head -c`), `timeout -k 1 3`, anchored hint-line classifier, awk counts (no grep -c under pipefail), 141 = ok, closed-key fields (no name/comm) capped at 130 bytes, all locals, `return 0`.
- 2.2 Emit `kdeny` via `_canary_diag_emit` after `kernel`, before `done`; `kdeny` NOT in the in-container allowlist.
- 2.3 `sdk_noproc` line in CANARY_DIAG_SCRIPT (no single quotes; closing quote stays on the last line) and the allowlist regex entry.
- 2.4 Suite green in the sandbox; shellcheck; lint-shell-capture-exit; grep-q-pipe guard by hand.

## Phase 3: Runbook and ratchet

- 3.1 canary-probe-set.md: `sdk_noproc` + `kdeny` rows, sixteen-row bundle, ten -> eleven in-container, `lines=11`, H6-H8, sdk_probe measured contrast, "Reading kdeny" note. No SSH.
- 3.2 Bump BASELINE_DECLARED_PROBES 53 -> re-measured (54) with PLACEMENT/TRUTH/NO SUBSTITUTE comment; run the preflight-discoverability suite.

## Phase 4: Mutation battery and verification (sandbox only)

- 4.1 Drive every Guard 1 matrix row (11); record each killing assertion in the PR body.
- 4.2 lint-guard-contract.py and lint-infra-no-human-steps.py on the plan; diff-scope checks (probe statement, rollback line, #8016 blocks byte-identical; no rename of the #9871 plan/spec).

## Phase 5: Pipeline and operator gates (parent runs review, QA, compound, ship, postmerge)

- 5.1 G1: explicit go-ahead before `gh pr merge` (delivers ci-deploy.sh to production). G2: dispatch of apply-deploy-pipeline-fix. G3: re-run of the release deploy job. G4: no Doppler write is planned.

## Phase 6: Post-deploy follow-up (NOT this PR's code)

- 6.1 `check-deploy-script-parity.sh --bs-only` (read-only).
- 6.2 Monitor (until-loop, never sleep) on betterstack-query.sh for a `section=kdeny` row; time-box 3 days then G3 or the repro path.
- 6.3 Decide with the plan's 3-row table; H6 is a separate issue (different subsystem) with availability-vs-isolation framing, container-wide-scope review and CTO+CLO; H7 is a new plan in the same infra subsystem; kernel-stream access follow-up only if `noaccess` and still needed.
