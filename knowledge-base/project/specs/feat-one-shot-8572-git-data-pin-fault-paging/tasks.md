# Tasks: sentry page on git-data host-key pin faults (#8572)

Plan: `knowledge-base/project/plans/2026-09-28-feat-sentry-git-data-pin-fault-paging-plan.md`

## Phase 1: RED — emitter contract

- [ ] 1.1 In `apps/web-platform/test/git-data-host-key-pin.test.ts`, update the three boot `toEqual`
  assertions to add `tags: { pin_fault }` and `extra: { pinFault }`. Keep them strict.
- [ ] 1.2 In the same file, add push cases:
  - absent pin → `pin_absent`, and invalid pin → `pin_invalid`, each with one report, `err = null`,
    `feature: worktree_lease` and `op: git_data_replication_push`;
  - provision `spawn ssh` ENOENT → `ssh_client_absent`;
  - provision 255 with host-key text → `host_key_mismatch`;
  - provision 128 with host-key text → not a pin fault;
  - git 128 with host-key text → `host_key_mismatch`;
  - `spawn git` ENOENT → not a pin fault;
  - fence reject → unchanged Error path.
- [ ] 1.3 Create `apps/web-platform/test/git-data-pin-fault.test.ts`:
  - a classifier table covering every arm × `via`;
  - inputs that must return `null` and never throw;
  - a real-path event test through `observability.ts` with `captureMessage` and `captureException`
    spied, `scrubSentryEvent` keeping `pin_fault`, and a raw-id sweep over the message, tags, extra
    and user.
- [ ] 1.4 In `apps/web-platform/test/account-delete.test.ts`: the erasure report never carries
  `pin_fault`.
- [ ] 1.5 Confirm the existing erasure-outcome tests stay unmodified.

## Phase 2: GREEN — emitter

- [ ] 2.1 Create `apps/web-platform/server/git-data-pin-fault.ts` containing:
  - `GIT_DATA_PIN_FAULT_REASONS` and `GitDataPinFault`;
  - `GitDataHostKeyPinError`;
  - `SSH_HOST_KEY_MISMATCH` (moved from the replication module, byte-identical);
  - `classifyGitDataPinFault(err, via)`, which never throws;
  - `reportGitDataPinFault`, the only writer of `pin_fault`.
- [ ] 2.2 In `apps/web-platform/server/git-data-replication.ts`:
  - `resolveGitDataHostKeyPin` throws `GitDataHostKeyPinError` with byte-identical messages;
  - the three boot reports go through `reportGitDataPinFault`;
  - the push catch sets `via` and classifies, with one report per failure;
  - add a comment that provision must stay before the git push;
  - import `SSH_HOST_KEY_MISMATCH`. The erasure logic stays unchanged.
- [ ] 2.3 In `apps/web-platform/server/account-delete.ts`, append a dated comment correcting the
  "first-seen / reappeared / regression" note.
- [ ] 2.4 Run the Phase 1 suites green, then `./node_modules/.bin/tsc --noEmit`.

## Phase 3: Rule contract and Terraform

- [ ] 3.1 Create `apps/web-platform/test/sentry-git-data-pin-fault-alert-op-contract.test.ts`
  (Guards 1 and 2, the census, the harness rows). Confirm it fails first.
- [ ] 3.2 In `issue-alerts.tf`, append `sentry_alert.git_data_host_key_pin_fault`:
  - `frequency_minutes = 240`;
  - 4 triggers;
  - `pin_fault in` the 4 values;
  - `ActiveMembers`;
  - a comment block per the plan's §B.1.
- [ ] 3.3 In `issue-alerts.tf`, add `event_frequency_count {1h,0}` to `art17_erasure_incomplete`
  and append a dated comment that corrects the "Keys on erasure_outcome" and "four routed values"
  statements.
- [ ] 3.4 In `alert-reference.json`, add the new entry and update the art17 triggers, both
  hand-authored in `jq -S` shape.
- [ ] 3.5 Run `terraform fmt -check` (and `init -backend=false && validate` if the provider is
  reachable). The contract test is green.

## Phase 4: Records

- [ ] 4.1 Update the README counts and the `model.c4` edge count using the AC8 formula, then run
  `bash scripts/regenerate-c4-model.sh`.
- [ ] 4.2 Runbook `git-data-luks-cutover-5274.md`:
  - erasure pin-fault row: name the rule, add the post-resolve query and the post-flip #8211
    dependency;
  - add a new push pin-fault row;
  - host-key rows: add the known_hosts note;
  - soak-query note near line 1196;
  - append to the flag-flip precondition bullet.
- [ ] 4.3 Append the dated ADR-237 addendum bullet and the ADR-220 precondition note.
- [ ] 4.4 Spawn `soleur:legal:clo` to draft the register markers (PA-36 TOM (g)) and the counsel
  audit addendum, conditioned on the merge and both deploys. Apply them append-only (AC7).

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
  - comment on #8211 (the two-part check, boot-only before the flip, the re-erasure dependency);
  - close #8572 with both run URLs;
  - open the evidence-only PR with the dated verification lines.
- [ ] 6.3 Red path: link the failure-filed p1 issue to #8572, and record the failed state in the
  evidence PR.
