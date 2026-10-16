# Tasks: standing registry fill-rate detection (#7521 part b)

Plan: `knowledge-base/project/plans/2026-10-16-feat-standing-registry-fill-rate-alarm-plan.md` (cite the archived path under `knowledge-base/project/plans/archive/` once `archive-kb.sh` has run at ship).
Branch: `feat-one-shot-7521-standing-fill-rate-detection`. Draft PR: #10444. PR body: `Ref #7521` (no closing keyword), a `## Changelog` section, "unavailable" or "disruption" wording only.

## Phase 0 — RED first (wiring test)

- 0.1 Create `scripts/zot-fill-rate-standing-wiring.test.sh` with `set -uo pipefail`, one `trap ... EXIT` owning every `mktemp`, call-site `cases` counter, literal-bound `MIN_CASES` floor and accounting sentinel, and the `ZOT_FILL_WIRING_ROOT` test seam.
- 0.2 T1 Sentry isolation: `steps.<id>` identifier set of the `status:` expression equals `{alarm}`; still `if: always()`; job timeout unchanged at 8; probe step timeout at most 3; at least 3 fill-referencing steps found.
- 0.3 T2 ordering: alarm < existing filing steps < `Sentry check-in (final)` < fill < fill filing steps.
- 0.4 T3 classification and defect flag, executed against a fixture tree with a fake `scripts/followthroughs/zot-fill-rate-7341.sh`: three valid pairs; invalid cases (rc 0 no header, rc 2 no header, rc 0 with FAIL header, rc 3, rc 127, two headers, a `::error::` body line) -> UNEVALUATED, outputs written, step exits 1; defect-flag fixtures for each benign token, one defect token, and `ALARM_EXIT` 2 suppression; a `\r::error::x` body line.
- 0.5 T4 FAIL filing against a PATH-shimmed `gh`: create versus comment, label-list lookup (never `--search`), dedupe-failure trade, title parity with the PASS loop, hostile `FILL_LINE` defanged and capped, no `BETTERSTACK_*` in any filing step's env, body holds only the verdict line, reproduce command and run link.
- 0.6 T5 PASS close hysteresis (5 h no close, 7 h close, none open no-op).
- 0.7 Run the suite with `ZOT_FILL_WIRING_ROOT` pointed at the `origin/main` workflow and record that it is RED.
- 0.8 Edit `apps/web-platform/test/server/watchdog-workflow-idempotence.test.ts`: the exact `select(.title` pin 15 -> 17 (and the floor 17 -> 19).

## Phase 1 — Workflow edit

- 1.1 In `.github/workflows/scheduled-zot-restart-loop.yml`, after `Sentry check-in (final)`, add step `Run standing fill-rate probe` (`id: fill`, `if: !cancelled()`, `timeout-minutes: 3`, secrets via `env:`): `|| rc=$?` capture, pipe-prefixed log lines, exactly-one column-0 header, exit-code map plus header agreement, outputs `fill_verdict` / `fill_line`, annotations, step summary, `exit 1` on UNEVALUATED.
- 1.2 Add step `Open or comment fill-rate issue (FAIL)` (bare `ISSUE_TITLE`, idempotent label create, label-list lookup, create or comment; body = origin sentence, verdict line, reproduce command, consequence sentence, close rule, run link).
- 1.2b Add step `Open or comment probe-defect issue` (`fill_defect == 'true'`, title `[ci/zot-fill-rate] Registry fill-rate probe defect`, same label and lookup shape); the FAIL step also closes any open probe-defect issue.
- 1.3 Add step `Auto-close fill-rate issue after a quiet period (PASS)` looping over both titles with the 21600 s `updatedAt` test.
- 1.3b In the probe step add `::add-mask::` of the lowercased host, the `*.betterstackdata.com` scrub, control-character and CR stripping before the pipe prefix, the `fill_defect` computation (closed benign-token allowlist, `ALARM_EXIT` not 2) and `ALARM_EXIT` env.
- 1.4 Update the workflow header comment only; leave the `Sentry check-in (final)` step byte-identical.

## Phase 2 — Registration

- 2.1 Register `scripts/zot-fill-rate-standing-wiring` in `scripts/test-all.sh` next to `scripts/alarm-issue-filing-guard`.
- 2.2 Regenerate `scripts/suite-shard-legs.tsv` and `scripts/suite-durations.tsv` with `python3 scripts/regenerate-shard-manifest.py --incremental --write`.
- 2.3 Reword the `scheduled-zot-restart-loop.yml` disposition in `scripts/lint-betterstack-emitter-read.sh` (its env now also feeds the fill reader).
- 2.4 Bump `BASELINE_DECLARED_PROBES` in `plugins/soleur/test/preflight-discoverability-test.test.ts` with the PLACEMENT / TRUTH / NO SUBSTITUTE comment; do it as the last commit after the final rebase (it is the one line expected to conflict).

## Phase 3 — ADR

- 3.1 Add the dated ADR-096 paragraph (fill-rate leg hosted in the restart-loop workflow, poller pattern, `#7521`, independent of the zot exit code and the Sentry status).
- 3.2 Leave `model.c4`, ADR-184 and the script header untouched.

## Phase 4 — Verification

- 4.1 Run the verification block in the plan (wiring test, script harness, alarm tests, filing guard, emitter-read lint, inventory workflow guard, ratchets, c4-count-parity, orphan census, vitest, bun, markdownlint, `lint-infra-no-human-steps --changed`).
- 4.2 Run the live read-only probe once (`doppler run -p soleur -c prd_terraform -- bash scripts/followthroughs/zot-fill-rate-7341.sh`) and paste the verdict line into the PR body.
- 4.3 Confirm AC1 and AC2 diff-scope commands (`git diff --name-only origin/main...HEAD` matches no infra path; the script, its harness, the alarm script and the parse library show an empty diff).
- 4.4 Re-run `gh run list --workflow apply-web-platform-infra.yml` and `--workflow registry-host-replace-dispatch.yml`, and re-read `knowledge-base/engineering/operations/runbooks/registry-host-replace-dispatch.md`.

## Phase 5 — Ship (stops at the owner-go gate)

- 5.1 Run compound, rebase onto `origin/main` (never merge main), push.
- 5.2 File the deferral issues listed in the plan (FAIL-arm prose refresh, library reconciliation, standing-name rename, 24 h seam / streak escalation) with a roadmap milestone each.
- 5.3 Stop and wait for the owner's explicit go; only then arm with a single bare `gh pr merge <N> --squash --auto`.
- 5.4 After merge: deploy-arm `find --wait <full-sha>` then `served <full-sha>` from a detached `origin/main` worktree (expected `DEPLOY=skipped` and `NOT_CONTAINED`), then the first-post-merge-run read in the plan's `## Post-merge probe`.
