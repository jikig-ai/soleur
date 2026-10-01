# Tasks: auto-mint the vinngest-v* tag on carrier change (#4326)

Plan: `knowledge-base/project/plans/2026-09-27-feat-auto-mint-vinngest-tag-on-carrier-change-plan.md`
(deepened 2026-09-27). The DC1 challenge in `decision-challenges.md` asks whether `GITHUB_TOKEN`
alone should replace the App token.

## Phase 0: Tests first

- [ ] 0.1 Write `.github/scripts/test/test-mint-inngest-bootstrap-tag.sh`.
  - The harness sources `plugins/soleur/test/lib/git-fixture-env.sh`, copies the canonical
    `assert_fixture_dir`, and sets `MIN_ASSERTIONS` to the green run's exact count.
  - It uses a real `git` clone, a bare fixture origin, and a synthesized build workflow and `.tf`
    files.
  - [ ] 0.1.1 The fake `gh` replays the real contracts:
    - `git/tags` creates a real tag object with `git mktag` and returns a multi-line body with both
      `sha` and `object.sha`;
    - `git/refs` runs `update-ref`, answering 422 `Reference already exists` when the ref exists
      and 422 `Object does not exist` for an unknown SHA;
    - a 204 prints nothing, and an error exits 1 with the body on stdout and `(HTTP 422)` on
      stderr;
    - the workflows-permission body is synthesized and has a negative control.
  - [ ] 0.1.2 Every row asserts one `result=` line, `reason=`/`stage=`, the exit code, the `gh`
    call log, and the origin tag set. A created tag must be annotated (`cat-file -t` gives `tag`),
    peel to HEAD, and carry the expected tagger and message.
  - [ ] 0.1.3 Guard 1 rows (decision), including one table-driven row per pin and first-carrier
    and last-carrier rows.
  - [ ] 0.1.4 Guard 2 rows (allocation), including the origin-only human tag, a 7-digit component,
    `no-base`, and a 422.
  - [ ] 0.1.5 Guard 3 rows (parity; credential isolation per step; `ref: main`; the job `if:`).
    Each failure prints the authority file and the copies that must change with it.
  - [ ] 0.1.6 Flow rows and ancestry refusals.
    - The xtrace canary token, and `--dry-run` with an unreachable origin.
    - `--dispatch` with an invalid or off-main tag.
  - [ ] 0.1.7 The composite scope-down case, with curl shimmed: empty inputs send no `-d`, and set
    inputs send the exact JSON body.
  - [ ] 0.1.8 Script-mutation rows. Each has a positive control on the unmutated copy, checks that
    the edit landed in the target function, and counts only rc 1 as caught.
- [ ] 0.2 Raise `MIN_SUITES` in `.github/scripts/test/run-all.sh` from 13 to 14, and update its
  history comment.
- [ ] 0.3 Confirm that every row reds against an `exit 0` stub script.

## Phase 1: Script

- [ ] 1.1 Create `.github/scripts/mint-inngest-bootstrap-tag.sh`:
  - the xtrace refusal first, then `LC_ALL=C`;
  - unset `GIT_TRACE*`, `GIT_CURL_VERBOSE`, `GH_DEBUG` and `DEBUG`;
  - three modes: `--dry-run`, `--tag` and `--dispatch <tag>`.
- [ ] 1.2 Each mode reads only its own `MINT_*_TOKEN`, copies it into a local variable, `unset`s
  the env var, and passes it per call as `GH_TOKEN=`.
- [ ] 1.3 Copy the selector from the bump script, the carrier extractor from Guard A, and the pin
  patterns from the build step, all byte-identical.
- [ ] 1.4 Implement the stages:
  - decide: fail-closed; carriers over the union, the 4 pins, exactly one heredoc; `no-base`;
  - allocate: `ls-remote`, `^{}` strip, numeric prefix, at most 6 digits per component, strict
    regex on NEXT;
  - tag: pre-create re-read; `jq`-built bodies; `jq -r .sha`; 422 fatal; `reason=` plus body
    length;
  - dispatch: exactly once, printing the remediation.
- [ ] 1.5 Output contract:
  - the result line goes to stdout, and `--dry-run` exits 0 on `would-mint`;
  - guarded `GITHUB_OUTPUT`/`GITHUB_STEP_SUMMARY` writes, fixed-vocabulary outputs only;
  - percent-encoded annotations;
  - the `noop` summary lists every comparison made.
- [ ] 1.6 Run `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main`
  and its negative control (AC4).

## Phase 2: Workflow and composite

- [ ] 2.1 Create `.github/workflows/mint-inngest-bootstrap-tag.yml`:
  - triggers: push to `main` (paths filter) and `workflow_dispatch`;
  - the job `if: github.ref == 'refs/heads/main'`, and checkout `ref: main`;
  - the concurrency group;
  - the steps: `Decide`, then `Create tag` (`MINT_TAG_TOKEN` only), then Doppler + App mint
    (scoped), then `Dispatch build` (`MINT_DISPATCH_TOKEN` only), then Slack through `jq` + `curl`,
    with an unset-webhook warning;
  - SHA-pinned actions.
- [ ] 2.2 Composite `.github/actions/mint-soleur-ai-app-token/action.yml`:
  - add the optional `permissions` and `repositories` inputs;
  - build a `jq` body with a JSON array for `repositories`;
  - send no `-d` when both are empty;
  - correct the grant doc comment.

## Phase 3: Build workflow

- [ ] 3.1 Update comments only in `.github/workflows/build-inngest-bootstrap-image.yml`. Nothing
  may change inside the `DOCKERFILE` heredoc or the pin-read step.

## Phase 4: Architecture and docs

- [ ] 4.1 Amend ADR-232:
  - §8 "Auto-mint on `main`";
  - scope the title's "never `GITHUB_TOKEN`" to PR authoring, and correct the least-scope
    sentence;
  - residuals R1, R6, R9, R10 and R12;
  - the #8798 dependency and the #8781 naming constraint;
  - the #8209 fallback via the mint workflow, with A5 as a prerequisite;
  - condensed alternatives;
  - an `## Amendment 2026-09-27 (#4326)` section.
- [ ] 4.2 In `model.c4`, split the `github -> soleurMarketplace` "NOT a push-to-main job" sentence
  into the auto-minted and manual cases. Then run the C4 tests (count-parity, freshness, syntax,
  render).
- [ ] 4.3 Add a Group 4 row to `infra-credential-tiers-8209.md`.
- [ ] 4.4 In `inngest-server.md` §Bootstrap-image release:
  - step 1 is automatic;
  - the fallback is `gh workflow run mint-inngest-bootstrap-tag.yml --ref main`;
  - hand-tag only for R1, and only when no tag points at the commit;
  - add the recovery table, including the R12 `mirror_only` and lost-dispatch rows.
- [ ] 4.5 In `main-health-monitor.yml`, change "13 fixture suites" to 14.

## Phase 5: Verification

- [ ] 5.1 AC1–AC12 and AC15. Re-verify #9081, #9082 and the #6766 links (AC11).
- [ ] 5.2 AC6: `git diff --quiet origin/main...HEAD -- apps/web-platform/infra`.
