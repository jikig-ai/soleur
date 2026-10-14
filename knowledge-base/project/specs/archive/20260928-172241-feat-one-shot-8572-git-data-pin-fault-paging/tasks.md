# Tasks: sentry page on git-data host-key pin faults (#8572)

Plan (deepened 2026-09-28): `knowledge-base/project/plans/2026-09-28-feat-sentry-git-data-pin-fault-paging-plan.md`

## Phase 1: RED — emitter contract

- [x] 1.1 In `apps/web-platform/test/git-data-host-key-pin.test.ts` (call-argument assertions only):
  - [x] 1.1.1 Update the three boot `toEqual` assertions to add `tags: { pin_fault }` and
    `extra: { pinFault }`. Keep them strict.
  - [x] 1.1.2 Build every transport rejection as
    `Object.assign(new Error("Command failed: …"), { code, stderr, syscall })`.
  - [x] 1.1.3 Add the push cases:
    - absent pin → `pin_absent`, and invalid pin → `pin_invalid`, each with one report, `err = null`
      and `extra.via`;
    - provision `spawn ssh` ENOENT → `ssh_client_absent`;
    - provision 255 with host-key text → `host_key_mismatch` (`via: ssh`);
    - provision 128 with host-key text → not a pin fault;
    - git 128 with host-key text → `host_key_mismatch` (`via: git`);
    - `spawn git` ENOENT → not a pin fault;
    - fence reject → `toEqual` of the full Error-path options.
- [x] 1.2 Create `apps/web-platform/test/git-data-pin-fault.test.ts` (unit, no module mocks):
  - a classifier table over every arm × `via`;
  - the `err.name` fallback without `instanceof`;
  - a forged `reason` → `null`;
  - hostile inputs → `null`, never a throw;
  - the `GitDataHostKeyPinError` messages are byte-identical to today's resolver strings.
- [x] 1.3 Create `apps/web-platform/test/git-data-pin-fault-event.test.ts`, the real-path test:
  - drive `replicateToGitData` with real `observability` and `logger`, and `vi.mock`
    `@sentry/nextjs` (importOriginal plus spies, and a `withIsolationScope` that records
    `clearBreadcrumbs`);
  - set `SENTRY_USERID_PEPPER` in `vi.hoisted`;
  - emit a pre-push warn log with a raw `WS` path;
  - assert one `captureMessage`, no `captureException`, `level: "error"`, `tags.pin_fault` and that
    breadcrumbs were cleared;
  - assert no raw `WS`, `WT` or `USER` anywhere in the payload;
  - positive control: `hashUserId(WS)` is present.
- [x] 1.4 In `apps/web-platform/test/account-delete.test.ts`: assert the erasure report is called for
  each outcome, that its tags never carry `pin_fault`, and that both sites use `ART17_ERASURE_OP`.
- [x] 1.5 Confirm the existing erasure-outcome tests stay unmodified.

## Phase 2: GREEN — emitter

- [x] 2.1 Create `apps/web-platform/server/git-data-pin-fault.ts`, with a "MESSAGE PATH ON PURPOSE"
  header like `anthropic-credit.ts` and `spawn-dead-letter.ts`. It contains:
  - `GIT_DATA_PIN_FAULT_REASONS` and `GitDataPinFault`;
  - `GitDataHostKeyPinError(reason, { storeEnabled })`, which builds its own fixed messages;
  - `SSH_HOST_KEY_MISMATCH` (moved, byte-identical);
  - `classifyGitDataPinFault(err, via)`: never throws; `instanceof` or `name`; reason validated;
    `spawn ssh`; 255 for ssh, 128 for git; a `// review: swallowed` catch;
  - `reportGitDataPinFault`, the only writer of `pin_fault`, which captures inside
    `Sentry.withIsolationScope` with `clearBreadcrumbs()`.
- [x] 2.2 In `apps/web-platform/server/git-data-replication.ts`:
  - the resolver throws `GitDataHostKeyPinError`;
  - the boot reports go through `reportGitDataPinFault`;
  - the push tracks `via`, classifies, sends `extra.via`, and makes one report per failure;
  - add the provision-before-push comment;
  - the erasure logic stays unchanged (it only imports the regex).
- [x] 2.3 In `apps/web-platform/server/account-delete.ts`:
  - export `ART17_ERASURE_FEATURE` and `ART17_ERASURE_OP`, used at both erasure sites
    (behavior-neutral);
  - append a dated comment correcting "first-seen / reappeared / regression".
- [x] 2.4 Run the Phase 1 suites green, then `./node_modules/.bin/tsc --noEmit`.

## Phase 3: Rule contract and Terraform

- [x] 3.1 Create `apps/web-platform/test/sentry-git-data-pin-fault-alert-op-contract.test.ts`
  implementing Guards 1 and 2 with every mutation and harness row in the plan. That covers:
  - a comment-stripped, test-excluding writer-shape census with an import check and a
    recursion-proof floor;
  - the reference mirror;
  - exactly one condition under `all` for the new rule;
  - exactly two conditions under `all` for rule 1b;
  - `1h/0` on both rules;
  - `enabled`;
  - `frequency_minutes` uniqueness.

  Confirm it fails first.
- [x] 3.2 In `issue-alerts.tf`, append `sentry_alert.git_data_host_key_pin_fault` per §B.1:
  - `frequency_minutes = 240`;
  - 4 triggers;
  - `pin_fault in` the 4 values;
  - `ActiveMembers`;
  - a comment block that includes the advisory-tag note.
- [x] 3.3 In `issue-alerts.tf`, add `event_frequency_count {1h,0}` to `art17_erasure_incomplete`.
  Append a dated comment correcting "Keys on erasure_outcome" and "four routed values", and stating
  the 5-minute throttle and its 288-a-day ceiling.
- [x] 3.4 In `alert-reference.json`, add the new entry and the art17 trigger, hand-authored in
  `jq -S` shape. If the gate mismatches, copy only those two entries from its artifact.
- [x] 3.5 Run `terraform fmt -check` (plus `init -backend=false && validate` if the provider is
  reachable). The contract test is green.

## Phase 4: Records

- [x] 4.1 Update the README counts and the `model.c4` edge count using the AC8 formula, then run
  `bash scripts/regenerate-c4-model.sh`.
- [x] 4.2 Runbook `git-data-luks-cutover-5274.md`:
  - [x] 4.2.1 Erasure pin-fault row: name the rule, add the post-resolve query and the post-flip
    #8211 dependency.
  - [x] 4.2.2 New push pin-fault row:
    - verify through the Better Stack `git_data_pin=present fp=` line and a Sentry query;
    - diagnose with `extra.via` and the cutover dry-run `_access_reason`;
    - add the H4 never-re-pin rule.
  - [x] 4.2.3 Host-key rows: add the known_hosts note.
  - [x] 4.2.4 Add the soak-query note near line 1196.
  - [x] 4.2.5 Flag-flip precondition bullet: append that #8572 is met on merge plus both deploys,
    with the re-erasure path as a hard precondition.
- [x] 4.3 Append the dated ADR-237 addendum bullet and the ADR-220 precondition note.
- [x] 4.4 Spawn `soleur:legal:clo` to draft the register markers (PA-36 TOM (g)) and the counsel
  audit addendum. The marker text should say "at most once per issue per 5 min, not per refusal",
  conditioned on the merge and both deploys. Apply them append-only (AC7).

## Phase 5: Ship

- [ ] 5.1 Commit with `LEFTHOOK_EXCLUDE=bun-test,plugin-component-test`, then push.
- [ ] 5.2 PR body:
  - first line: the merge mutates prod via `apply-sentry-infra.yml` and `web-platform-release.yml`;
  - `Ref #8572`;
  - the `GitDataHostKeyPinError` grouping-name note;
  - the rendered `decision-challenges.md`.
- [ ] 5.3 Get CI green by name on the head SHA, including `plan_pr` showing exactly 1 add and 1
  in-place change, the reference gate, and `sentry-destroy-required`. Then admin merge.

## Phase 6: Post-merge (read-only verification)

- [ ] 6.1 Monitor `apply-sentry-infra.yml` (the live fidelity PASS literal) and
  `web-platform-release.yml` on the merge SHA.
- [ ] 6.2 Green path:
  - [ ] 6.2.1 Run a read-only Sentry query for `pin_fault:*` and the three boot messages since the
    merge, and check that no issue group is archived or ignored.
  - [ ] 6.2.2 Comment on #8211:
    - the two-part check;
    - boot-only before the flip;
    - the re-erasure path is a hard precondition;
    - "no event" is not healthy.
  - [ ] 6.2.3 Close #8572 with both run URLs, then open the evidence-only PR.
- [ ] 6.3 Red path:
  - link the failure-filed p1 issue to #8572;
  - read rule 1b's live state (a drift `workflow_dispatch` needs the operator's per-step
    authorization; otherwise wait for the next daily run);
  - record the state in the evidence PR.
