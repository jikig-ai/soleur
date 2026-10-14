# Tasks: delete the git-data unpinned host-key fallback arm (#5914, host-key step 6)

Plan: `knowledge-base/project/plans/2026-09-28-feat-git-data-delete-unpinned-fallback-arm-5914-plan.md`

## Phase 0: Preconditions (reads only; no production write)

- [ ] 0.1 Confirm host-key step 5 status on #5914 (Part A). If no step-5 record exists, the step-5
  session runs Part A first; this PR does not merge before G1 reads GO.
- [ ] 0.2 Re-read the runbook's host-key post-merge sequence and Preconditions from `origin/main`;
  stop if step 6's text changed.

## Phase 1: RED tests

- [ ] 1.1 `apps/web-platform/test/git-data-host-key-pin.test.ts`: absent pin + flag off throws; erasure
  returns `unconfigured` `pin_absent:` and never dials; reason word updated; startup event rows
  (unarmed silent; whitespace-only silent; each arming input alone emits exactly one
  message-path `pin_absent_at_startup` with no leaked values); `beforeEach` stubs
  `GIT_DATA_SSH_HOST=""`; AC3 asserts the flag state in the message and no pin report.
- [ ] 1.2 `apps/web-platform/test/git-auth.test.ts`: the five `null` call sites pass a pinned key
  (the fallback test is deleted); runtime-guard cases per helper for `null`, `undefined`, `123` and a
  valid key with a trailing comment (exact guard text, `execFile` never called); delete the "TOFU
  literal exactly once" test.
- [ ] 1.3 `apps/web-platform/test/helpers/ssh-host-key-fixture.ts` and
  `apps/web-platform/test/git-data-replication.test.ts`: comment updates.
- [ ] 1.4 `tests/scripts/test-no-tofu-ssh-mutation.sh`: retarget row 5 (non-allow-listed needle) and
  row 5b (anchor on `git-data-ownership.test.sh`'s `UserKnownHostsFile` token; positional
  precondition: same line count, one matching line, 3 matches on it); confirm row 2's needle.
- [ ] 1.5 AC5b rows set all three arming inputs explicitly, overriding the file's `beforeEach`.

## Phase 2: GREEN (one commit)

- [ ] 2.1 `apps/web-platform/server/git-auth.ts`: delete `TOFU_FALLBACK_OPTS`; `hostKeyPin: string`;
  runtime guard in `gitDataHostKeyTrust` using the exported `GIT_DATA_HOST_KEY_PIN_RE`; comments.
- [ ] 2.2 `apps/web-platform/server/git-data-replication.ts`: `resolveGitDataHostKeyPin(): string`;
  delete `pinAbsentReported` and `pin_absent_store_disabled`; reason word `pin_absent`;
  `provisionGitDataRepo` param type; export `GIT_DATA_HOST_KEY_PIN_RE`; `pin_absent_at_startup` boot
  event (message path, inline arming check); move `pin_invalid_at_startup` to the message path.
- [ ] 2.3 `apps/web-platform/server/git-data-client.ts`: comment update. `account-delete.ts`: comment
  update, and move the erasure-outcome report to the message path (#8629; AC5c).
- [ ] 2.4 `tests/scripts/test-no-tofu-ssh.sh`: delete the `git-auth.ts` allow-list line.
- [ ] 2.5 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`; run the two vitest files, the two
  no-TOFU suites, and `git-data-flag-precheck.test.sh` unchanged (`76 passed`); AC7's grep prints `0`.

## Phase 3: Records

- [ ] 3.1 Runbook: tick steps 2, 3, 5 (record URL), 6; flag-flip paragraph and resolver sentence;
  step 5 (a), 5.2 and 6 notes (CTO/CLO rulings); one-line go/no-go and "Between merge and step 3"
  notes; verdict-map pin-fault row (`pin_absent:` and its post-flip limit); leave step 1 unticked.
- [ ] 3.2 ADR-237: addendum keyed by PR #9096; ADR-220: one amendment-log line; no earlier line
  modified in either.
- [ ] 3.3 C4: edit the `claude -> gitDataStore` edge prose; add the `api -> gitDataStore` erasure edge;
  regenerate `model.likec4.json`; run C4 syntax, render and count-parity suites.
- [ ] 3.4 Encryption ledger: flip the row selected by connection name to `cert_verification: on`, drop
  the exception, dated pointer in `tls`; run the encryption-posture lint and its test suite.
- [ ] 3.5 One `soleur:legal:clo` call for the four register markers (paste verbatim into
  `knowledge-base/legal/article-30-register.md`) and the draft re-attestation record, held until ship.
- [ ] 3.6 Run `soleur:gdpr-gate` scoped to the diff (work Phase 2 exit).

## Phase 4: Ship

- [ ] 4.1 Read G1 (newest member-authored step-5 record; 0 erasure events since it), G2 (expected
  fingerprint = Doppler `prd` pin fingerprint = newest startup line per expected host on the served
  build, plus the count-only shape check of the Doppler pin; no unresolved `erasure_outcome:unconfigured`
  issue), G3 (required checks on the head SHA); quote evidence in the PR body; `Closes #5914`.
- [ ] 4.2 At ship Phase 5.5, the CLO writes the re-attestation record under `knowledge-base/legal/audits/`.
- [ ] 4.3 After merge (Monitor-polled): deploy arm `DEPLOY=success`, served `CONTAINS`, G2 read 3
  again, the three Sentry tag queries return 0; on failure republish and redeploy, never revert.
  Comment on #8211 (next proof must read `TOFU_ARM absent`) and #8572 (reason word, tag-keyed
  routing, startup ops), then read #8572 back.
