# Tasks: auto-mint the vinngest-v* tag on carrier change (#4326)

Plan: `knowledge-base/project/plans/2026-09-27-feat-auto-mint-vinngest-tag-on-carrier-change-plan.md`

## Phase 0: Tests first

- [ ] 0.1 Write `.github/scripts/test/test-mint-inngest-bootstrap-tag.sh`. The harness uses a real
  `git` working clone, a bare fixture origin, a synthesized build workflow and `.tf` files, and a
  PATH-shimmed `gh` that replays the real REST contracts, including the 422 body.
  - [ ] 0.1.1 Guard 1 rows (decision) and Guard 2 rows (allocation, concurrent-tag, 422).
  - [ ] 0.1.2 Guard 3 rows (parity and credential shape). Each failure prints the authority file
    and the copies that must change with it.
  - [ ] 0.1.3 Spec-flow flow rows (a)–(m), ancestry refusals, the xtrace refusal, and `--dry-run`
    making no network call on a non-main HEAD.
- [ ] 0.2 Raise `MIN_SUITES` in `.github/scripts/test/run-all.sh` from 13 to 14, and update its
  history comment.
- [ ] 0.3 Confirm that every row reds against an `exit 0` stub script.

## Phase 1: Script

- [ ] 1.1 Create `.github/scripts/mint-inngest-bootstrap-tag.sh`:
  - the xtrace refusal first, then `LC_ALL=C` and the `GIT_TRACE*` unset;
  - the credential variables `MINT_TAG_TOKEN` and `MINT_DISPATCH_TOKEN`;
  - two modes: `--dry-run` and full.
- [ ] 1.2 Copy the selector from the bump script, the carrier extractor from Guard A, and the pin
  patterns from the build step, all byte-identical.
- [ ] 1.3 Implement the stages:
  - decide: fail-closed extraction; carriers over the union, pins, heredoc;
  - allocate: `ls-remote`, numeric prefix, `^{}` strip;
  - tag: pre-create re-read, REST with `GITHUB_TOKEN`, 422 fatal, the R1 reason;
  - dispatch: App token, exactly once, remediation printed.
- [ ] 1.4 Run `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main`
  and its negative control (AC4).

## Phase 2: Workflow

- [ ] 2.1 Create `.github/workflows/mint-inngest-bootstrap-tag.yml`:
  - triggers: push to `main` (paths filter) and `workflow_dispatch`;
  - checkout `ref: main` and the concurrency group;
  - the `Decide`, Doppler, App mint (unchanged composite) and `Mint` steps, plus Slack on failure;
  - SHA-pinned actions.

## Phase 3: Build workflow

- [ ] 3.1 Update comments only in `.github/workflows/build-inngest-bootstrap-image.yml`. Nothing
  may change inside the `DOCKERFILE` heredoc or the pin-read step.

## Phase 4: Architecture and docs

- [ ] 4.1 Amend ADR-232: §8 with residuals R1, R6, R9 and R10, the #8209 fallback line, condensed
  alternatives, and an `## Amendment 2026-09-27 (#4326)` section.
- [ ] 4.2 Update the `model.c4` `github -> soleurMarketplace` prose, then run the C4 tests
  (count-parity, freshness, syntax, render).
- [ ] 4.3 Add a Group 4 row to `infra-credential-tiers-8209.md`.
- [ ] 4.4 In `inngest-server.md` §Bootstrap-image release, make step 1 automatic, add the
  hand-tag-only-if-no-tag rule, and add the recovery table.
- [ ] 4.5 In `main-health-monitor.yml`, change "13 fixture suites" to 14.

## Phase 5: Verification

- [ ] 5.1 AC1–AC12. Re-verify #9081 and the #6766 links (AC11).
- [ ] 5.2 AC6: `git diff --quiet origin/main...HEAD -- apps/web-platform/infra`.
