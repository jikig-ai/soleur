---
title: "Tasks — ADR-142 additive blue-green LUKS apparatus for the Inngest Redis AOF volume"
date: 2026-09-17
branch: feat-one-shot-adr142-inngest-aof-luks-bluegreen
plan: knowledge-base/project/plans/2026-09-17-infra-inngest-adr142-bluegreen-luks-apparatus-plan.md
lane: cross-domain
---

# Tasks

Derived from the plan. Phase order is dependency order. Directory and topic are prescribed for new
learnings; filenames are chosen at write time.

## Phase 0 — preconditions, measured not assumed

- [x] 0.1 Run the cloud-init byte-budget script and record the verbatim output in the PR body.
- [x] 0.2 Confirm the ADR-142 amendment claims no new ordinal, verified across every `origin/*` ref rather than `origin/main` alone.
- [x] 0.3 Read the cutover environment through the GitHub API and confirm a non-empty reviewer set and a `main`-pinned deployment branch policy.
- [x] 0.4 Read `INNGEST_CUTOVER_FLIP`. If it reads `done`, record the post-replace re-entry verb as an ordered step — the `done-owner` marker lives on the root disk a replace destroys, and the start guard refuses a prod start without it.
- [x] 0.5 Read the newest `SOLEUR_INNGEST_SERVER_PROBE` row; record `host_role`, `redis_keys`, `redis_key_patterns`, `data_mount_devid`.
- [x] 0.5b Measure the three vendor behaviours docs could not settle: whether starting Redis on a copy mutates it; the authoritative read of a mapper's backing device; whether `blkid -p` needs root.
- [x] 0.6 **Stop gate (acceptance criterion 0, not a bullet).** Record the reading verbatim in the PR body. If `redis_keys` is 0 under the three pins, halt: the additive build is the wrong instrument and the gated recut closes the issue instead. If the scheduler now lives on the dedicated host, repoint the canary's T0/T3 before designing them.

## Phase 1 — guard contracts before guards

- [x] 1.1 Write the four guard contracts and their mutation matrices from the design, not from code.
- [x] 1.2 For each guard, name the chokepoint rather than listing today's members; include the own-dispatch anti-vacuity row, the add-a-second-member row, the order/lifetime row, the two harness rows and the outside anchor.
- [x] 1.3 Run the guard-contract lint and confirm it passes over this plan.

## Phase 2 — Terraform, inert on merge

- [x] 2.1 Declare `hcloud_volume.inngest_redis_luks` in `apps/web-platform/infra/inngest-redis-luks.tf` — no `format`, size and location from the existing variables, labels matching the siblings.
- [x] 2.2 Declare `hcloud_volume_attachment.inngest_redis_luks` **in the same file**. Co-location is a lint requirement: the posture lint reads the file that declares the attachment and requires a co-located passphrase pair.
- [x] 2.3 Pass `inngest_luks_volume_id` into the cloud-init render in `apps/web-platform/infra/inngest-host.tf`.
- [x] 2.4 Add both addresses to `OPERATOR_APPLIED_EXCLUSIONS` in the target-parity test.
- [x] 2.5 Add both to the `inngest-host` `-target=` set. Add **only the attachment** to the `inngest-host-replace` set — that dispatch preserves the durable volume by omission, and targeting the new volume there would break the invariant.
- [x] 2.6 Admit the new attachment in `tests/scripts/lib/inngest-host-replace-gate.sh`'s allow-set, and the new volume create-only, mirroring the existing plaintext-volume admission. Keep the destroyed-volume backstop and add its twin.
- [x] 2.7 Admit **both** `INNGEST_LUKS_CUTOVER` and `INNGEST_LUKS_ACTIVE_VOLUME_ID` in the boot isolation pattern, positioned before `HEARTBEAT_URL`; do not bump the floor. A live miss bricks the next re-provision.
- [x] 2.8 Extend `apps/web-platform/infra/inngest-host.test.sh`'s name-set replay for both new admitted names.
- [x] 2.9 Add the `hcloud_volume.inngest_redis_luks` ledger row with `mechanism: plaintext-exception`, its own exception block, and the escrow-absence negative in `does_not_defend`.
- [x] 2.10 Amend the `hcloud_volume.inngest_redis` row's `reevaluate_when` in-cell to admit the additive route; leave `mechanism` and `expires_on` untouched.
- [x] 2.11 Confirm the posture lint reports 19 stores and zero failing checks.

## Phase 3 — cloud-init: the two-device resolver

- [x] 3.1 Generalise the existing discriminator into one resolver over both by-id devices.
- [x] 3.2 Make the pointer authoritative and the signature corroborating. The pointer is a value on the isolated project, staged into the root-disk env file by the first-boot stage — **not** a root-disk value, which the only delivery path destroys. Pointer present and contradicted, or naming an absent device, is a refusal, never a fall-through.
- [x] 3.3 Add the mapper-level probe with the cache-bypassing flag; mkfs only on an empty mapper.
- [x] 3.4 Add the positive control: staging mount resolves to the staging mapper, and the staging mapper resolves to the staging device. Both links, because neither alone proves which block device sits underneath a path.
- [x] 3.5 Generalise the boot-reopen script the same way, from the same pointer.
- [x] 3.6 Change the fstab writer to replace-in-place, retain `nofail`, and assert exactly one `/mnt/data` line.
- [x] 3.7 Fold the resolver's structural assertions into `apps/web-platform/infra/inngest-redis-luks.test.sh`. No third suite.
- [x] 3.8 Extend the loopback suite with staging arms, and widen its non-global device rebinds so both readers are substituted — assert each substitution landed.
- [x] 3.9 Add the plaintext-only regression case: pointer absent, one device attached, behaviour byte-identical to today.
- [x] 3.10 Re-run the byte-budget script and the model-side size test. Both budgets, not just the cap.

## Phase 4 — the on-host cutover unit trio and the image cycle

- [x] 4.1 Write `apps/web-platform/infra/inngest-luks-cutover.sh` with the phase functions, the enumerated freeze set, the specified rollback contract (including closing the canonical mapper and asserting it is gone), and the `flock` self-inhibit. No epoch token — terminal-state no-ops already cover re-entry.
- [x] 4.2 Write the state table: state, entry condition, guard predicate, legal successors, writer — one row per abort point.
- [x] 4.3 Make the latch record completion-with-verification, never entry, and give the retry path its own state whose guard admits a latched-partial. Keep it in the cutover's own state directory — never append to the flush latch.
- [x] 4.4 Write the unit and timer. `PrivateMounts=no` and therefore no `ReadWritePaths=` (the man page states it implies a private namespace and that propagation to the host stays off, so the mounts would vanish on exit); `/etc` writable; `EnvironmentFile` supplying the project; a `SyslogIdentifier` matching the log allowlist exactly; no `Persistent=true`; injection scoped to an explicit name list.
- [x] 4.5 Add the new `SyslogIdentifier` to the log-shipper allowlist, and assert it equal to the unit's own value. Every observability detection routes through that one exact-value list.
- [x] 4.6 Add the cutover script to all four enumerating sites in the image build workflow.
- [x] 4.7 Add the install block to `apps/web-platform/infra/inngest-bootstrap.sh`, **fail-closed** on missing assets rather than mirroring the skip arm.
- [x] 4.8 Add the new unit to `apps/web-platform/infra/doppler-injection-bound.test.sh`'s population. **No sudoers change** — the unit is a root oneshot and the host runs no listener.
- [x] 4.9 Push the tag, build the image, **capture the digest**, then re-pin it at both sites. CORRECTED 2026-09-18 (see the plan's execution amendment): this is IN-PR, not post-merge — GuardA reds until the pinned tag contains the new carriers, and the repo's own precedent tags feature-branch commits. It is the LAST step before ship, after review freezes the carriers. DONE 2026-09-18: tag `vinngest-v1.1.36` at 8841c83f0 (the review-round head), build run 35357585629 success, signed digest `sha256:73ae626273681b11f936af52198043c236cc220cbdc0cb71599eccb18d8bf700` read by command from the run's own `Signed …@sha256:` line and its `digest:` push line; re-pinned at all FOUR sites (cloud-init-inngest.yml IREF+ZIREF, cloud-init.yml IREF+ZIREF); GuardA 160/160, every carrier resolves and is byte-identical, 13 of 13.
- [x] 4.9b Assert the pinned digest resolves to an image containing the cutover script, before the replace. DONE 2026-09-18, from the signing run's own record (GHCR is private and the read PAT is revoked — AP-016 — so no local pull exists): layers 13/16, 14/16, 15/16 of the build that produced this digest are `COPY inngest-luks-cutover.sh|.service|.timer`, the ENTRYPOINT copies all three to /tmp for the bootstrap, and the zot mirror step reports the same digest (crane copy is digest-preserving). GuardA additionally proves the tag's TREE carries the trio byte-identical to HEAD.
- [x] 4.10 Write `apps/web-platform/infra/inngest-luks-cutover.test.sh` and register it single-line.

## Phase 5 — the writer and the plan-shape gate

- [x] 5.1 Add `luks-cutover` and `luks-rollback` to the dispatch workflow's choice list, and extend **both** the environment conditional and the token-injection conditional. An op in the list with an unextended ternary runs ungated with the write token in hand.
- [x] 5.2 Add the op bodies to the driver script: a pre-write state guard, the stdin write, and a confirmation read that the on-host FSM reached the expected state.
- [x] 5.3 Extend the workflow test with the same write-order and stdin-not-argv assertions it already pins for the sibling flag.
- [x] 5.4 Write `tests/scripts/lib/inngest-luks-additive-gate.sh` and wire it into the `inngest-host` job — the dispatch that actually plans a create. **No new `apply_target`.**
- [x] 5.5 Write its drop-one battery, one case per predicate rather than per verdict token.
- [x] 5.6 Wire the probe-row alert that detects a resolved device alias that is not the encrypted volume's, and file the tracked issue with its expiry. **The detach dispatch is cut** — a destroy of a still-declared attachment is re-created by the next routine apply.

## Phase 6 — records

- [x] 6.1 Append the ADR-142 amendment with its entries; append superseded-markers to the sibling records that name the recut as the sole route.
- [x] 6.2 Correct the C4 node's stale format claim and extend it with the additive apparatus; regenerate the compiled model and commit it.
- [x] 6.3 Write the cutover runbook.
- [x] 6.4 Author the new ADR for per-operation latched flags as the control channel for the no-inbound host, including the verification-does-not-actuate waiver with its bounds. Contested between two reviewers; if the ordinal is contested at merge, fold as an amendment entry rather than blocking.
- [x] 6.5 File the backstop-wipe tracking issue with its expiry, so the ledger row can cite it.
- [x] 6.6 Write the two follow-through scripts and their directives; file the ledger flip as its own tracked item.
- [x] 6.7 Capture the session's learnings under `knowledge-base/project/learnings/` — directory and topic only, filename chosen at write time.

## Ship gate

- [ ] 7.1 All pre-merge acceptance criteria green.
- [x] 7.2 PR body carries `Ref #6894`, `Ref #7695`, `Ref #8017` — never `Closes`. DONE 2026-09-18: body carries exactly those three `Ref` lines, `closingIssuesReferences` is empty (0), title is `feat(inngest): additive blue-green LUKS cutover for the Redis AOF store (#6894)`.
- [ ] 7.3 Full battery green, or every failure confirmed pre-existing on `origin/main` by the same command.

## Cross-cutting, added by the review passes

- [x] 8.1 Liveness for the cutover unit is read from the **timer**, never the oneshot service — a oneshot's healthy steady state is `inactive`.
- [x] 8.2 The missed-tick enumeration is a mandatory close-out of every window. Ticks due in-window are not backfilled.
- [x] 8.3 The rollback contract's mapper close is graded by a named suite case, not left in prose.
- [x] 8.4 `## User-Brand Impact` enumerates by window and role — the reminder arm-er, the dashboard sender, the cron beneficiary, the data subject — not by store.
