# Tasks: relay hello accept-only key slot and GHCR push-denial diagnostics

Plan: `knowledge-base/project/plans/2026-11-09-feat-relay-hello-key-rotation-ghcr-push-diagnostics-plan.md`.
Branch `feat-one-shot-8211-hello-key-rotation-ghcr-diag`, draft PR #12536.

**STOP BEFORE MERGE.** This PR changes production, and merging is owner-gated.

Run single test files only. Never run `test-all.sh`, `run-registered-suites.sh` or the full or affected gate locally;
CI is the gate. Scratch and logs go under `/var/tmp`.

## Phase 1: Setup

- [ ] 1.1 Re-read ADR-323 Decisions 2, 6, 8 and 9, and `decision-challenges.md` rows A, B, B-a to B-e, E, C1 to C3, F.
- [ ] 1.2 Run `git grep -n 'verifyProxyHello\|loadProxyHelloKey\|signProxyHello' -- apps/web-platform` and record every
      consumer (`hr-type-widening-cross-consumer-grep`).
- [ ] 1.3 Re-run the R3 grep (measured 2026-11-10: no test pins the HALT remediation text).

## Phase 2: Core Implementation

Each task starts with failing tests (`cq-write-failing-tests-before`).

- [ ] 2.1 B.1 loader `loadProxyHelloKeys` (`server/proxy-tls.ts`): one cache, no wrapper.
  - [ ] 2.1.1 Write failing rows in `test/proxy-tls.test.ts`:
    - the AC-B4 loader states, including well-formed-and-distinct (`accept-also-active`), malformed with current absent,
      and call-twice;
    - named `reportSilentFallback` and `warnSilentFallback` spies;
    - deletion of both names (the malformed-value deletion row lives here);
    - the frozen key-set object redacts under `JSON.stringify` and `util.inspect`.
  - [ ] 2.1.2 Implement. Rename the three production callers: the `server/index.ts` boot call (same position), and the
        sender and server key reads in `server/session-proxy.ts`. Keep `__resetProxyHelloKeyForTests`. Update
        `test/server-index-boot-pin-line.test.ts`.
- [ ] 2.2 B.2 key-set verifier and `helloKeyFingerprint` (`server/proxy-hello.ts`).
  - [ ] 2.2.1 Write Guard 1 and Guard 5 rows in `test/proxy-hello.test.ts`. The known-answer vector and the success
        result shape stay unchanged.
  - [ ] 2.2.2 Implement. Both `timingSafeEqual` calls always run when the slot is set. Extend the existing spy row:
        2 calls when the slot is set, 1 when it is null.
- [ ] 2.3 B.3 call sites in `server/session-proxy.ts`. The sender signs with the current key only. The server starts
      only when a current key exists. The verifier receives the key set. Update the rows in
      `test/session-proxy-hello.test.ts` and `test/session-proxy.test.ts` (CPO conditions 1-3).
- [ ] 2.4 B.5 `relay_hello_key_fp` warn line, emitted once from `createProxyServer` after the key check.
- [ ] 2.5 B.6 add the name to `server/sensitive-keys.ts`, and parametrize `test/proxy-hello-key-isolation.test.ts` over both
      names (Guard 3).
- [ ] 2.6 Bump `BASELINE_DECLARED_PROBES` 96 → 97 in `plugins/soleur/test/preflight-discoverability-test.test.ts`. Add
      the `AFFECTED_PLUGINS_SOLEUR_TEST_REUSABLE_RELEASE_PUSH_FAILED_MARKER_TEST_SH_PATHS` entry to
      `scripts/lib/test-affected-paths.sh`.
- [ ] 2.7 Create `test/proxy-hello-rotation-phases.test.ts` (Guard 2), including the code-mutation row "the verifier
      ignores `acceptAlso`". It covers 6 adjacent round trips and 4
      skip-case directions:
  - P2→P0 refused (`mac`);
  - P0→P2 accepted;
  - P1→P3 refused (`mac`);
  - P3→P1 accepted.
- [ ] 2.9 B.7 records.
  - [ ] 2.9.1 ADR-323 amendment:
    - Decision 9: the slot, routine three phases, confirmed-leak single-phase (T4), "not executable until #12538", and
      no leak response or kill switch until then;
    - the normative #12538 phase-gate requirements (a) to (e) (T3);
    - Decision 6 and Decision 2;
    - the renamed consequence;
    - the Considered Options rows.
  - [ ] 2.9.2 `infra/proxy-hello-hmac.tf` header comment only.
  - [ ] 2.9.3 The HALT's "Intended rotation" line in `.github/workflows/apply-web-platform-infra.yml`, plus any test
        that pins its text.
  - [ ] 2.9.4 `runbooks/apply-web-platform-infra-job-rationale.md` and the relay section of
        `runbooks/betterstack-log-query.md` (the fingerprint query, the `accept_also!=none` alarm rule and the AC-P1
        failure branches).
- [ ] 2.10 C.1 marker step in `.github/workflows/reusable-release.yml`.
  - [ ] 2.10.1 Measure locally, never by dispatch. Use a throwaway docker-container builder under `/var/tmp`, and push to
        a local `registry:2` with htpasswd and wrong credentials, so you see a real 401/403. Measure the shape and order
        of `ls` over two failed builds, and save sanitized fixtures. Inspect artifacts by metadata only. Then find the error-message field in
        `docker buildx history inspect <ref> --format json` (buildx 0.38.1, the runner's version). Fall back to
        `see-step-log` if the field is absent.
  - [ ] 2.10.2 Write `plugins/soleur/test/reusable-release-push-failed-marker.test.sh` red first (Guard 4). Run it with a
        strict-argv `docker` stub and `bash --noprofile --norc -eo pipefail`, with per-rule fixtures. Classes:
        `push_denied`, `push_other`, `not_push`, `unknown`. Include:
    - the build-arg token fixture;
    - the LF-injection fixture;
    - the no-build-ref fallback;
    - the v0.402.0 error text.
  - [ ] 2.10.3 Add `DOCKER_BUILD_RECORD_UPLOAD: "false"` and `DOCKER_BUILD_SUMMARY: "false"` as env on `docker_build`
        (CTO D1). Then add the step, with `timeout-minutes: 1`, the JSON error field only and the allowlist
        `denial=`. `denial` never goes to `GITHUB_OUTPUT` or the email; the summary line sits in a code span; `attempt`
        is validated. In the failure email:
    - change the re-run wording to "'Re-run failed jobs' (on both the release run and the deploy-arm run) is safe; a
      fresh 'Run workflow' dispatch is not";
    - add the conditional sentence.

    The `permissions:` block stays byte-identical.
- [ ] 2.11 C.2 runbook `runbooks/web-platform-release-image-push-failed.md`:
  - Billing > Packages first;
  - re-run the failed jobs of both runs, using the deploy-arm lookup `gh run list --workflow web-platform-release.yml --commit <sha> --event workflow_run`, and never a fresh dispatch;
  - the cancelled or timed-out job residual, and `class=unknown` meaning "read the step log";
  - the Packages budget is an operator decision about money, and the agent stops there (CPO condition 7);
  - the retry re-evaluation trigger;
  - Zot is out of scope.

## Phase 3: Testing

- [ ] 3.1 From `apps/web-platform`, run each file on its own with `npx vitest run`:
  - `test/proxy-hello.test.ts`
  - `test/proxy-tls.test.ts`
  - `test/proxy-hello-key-isolation.test.ts`
  - `test/session-proxy-hello.test.ts`
  - `test/session-proxy.test.ts`
  - `test/proxy-hello-rotation-phases.test.ts`
  - `test/server-index-boot-pin-line.test.ts`
- [ ] 3.2 Run these one at a time:
  - `bash plugins/soleur/test/reusable-release-push-failed-marker.test.sh`
  - `bash plugins/soleur/test/reusable-release-caller-permissions.test.sh`
  - `bash tests/scripts/test-destroy-guard-counter-web-platform.sh`
  - `bun test plugins/soleur/test/terraform-target-parity.test.ts`
  - `bun test plugins/soleur/test/preflight-discoverability-test.test.ts`
- [ ] 3.3 Run `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`, then
      `bash scripts/lint-orphan-test-suites.sh`.
- [ ] 3.4 Run the AC-B6, AC-B8, AC-B10, AC-C2 and AC-D1 merge-base diff checks, and AC-G1 (the technical-ruling gate).
- [ ] 3.5 Push. CI is the gate. If `deploy-script-tests (4/4)` fails, it is pre-existing (#12489, item D); record it
      as such and do not fix it here.
- [ ] 3.6 Run `soleur:review`, including `user-impact-reviewer` (single-user incident).

## Phase 4: Ship (stop before merge)

- [ ] 4.1 PR body must carry:
  - the Item A answer, briefly;
  - the B and E rulings;
  - `Ref #8211`, `Ref #12538` and `Ref #12539`;
  - the operator ACTION line: the GitHub Packages budget, an operator decision about money;
  - `Closes #12167` only if AC-S3 passes, otherwise `Ref #12167`;
  - item D recorded as pre-existing.
- [ ] 4.2 Run `gh issue edit 8211 --add-blocked-by 12538` (AC-S4), and post the epic comment on #8211 worded "in PR #12536, pending owner merge" (AC-S5).
- [ ] 4.3 The PR body keeps the D1 wording neutral (it says "hardening: build records carry build args"). Under the CLO
      embargo, nothing names a run, an artifact or a token until the owner-side follow-up (D1-op) completes.
- [ ] 4.4 STOP BEFORE MERGE. Merging is owner-gated.
- [ ] 4.5 After merge, agent reads only:
  - AC-P0: relay health over the roll window. The rollback dispatch is the owner's act.
  - AC-P1: fingerprint lines on both hosts;
  - AC-P2: the slot-state events, read only if a slot is set;
  - AC-P3: the deployed round trip is still open until a real session runs;
  - AC-P4: `infra-validation` goes green after #12489.
