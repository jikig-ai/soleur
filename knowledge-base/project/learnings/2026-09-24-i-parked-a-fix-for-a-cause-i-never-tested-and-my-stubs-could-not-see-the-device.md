---
title: I parked a fix for a cause I never tested, and my stubs could not see which device they were handed
date: 2026-09-24
category: test-failures
module: git-data-bootstrap
tags: [ext4, jbd2, device-mapper, loopback, test-harness, stubs, mutation-testing, sysfs, github-actions]
pr: 8711
issue: 5274
---

# Learning: a real-kernel failure is a claim about the kernel until an experiment says otherwise

## Problem

PR #8711 reads the retained git-data plaintext volume through a non-persistent dm snapshot, so a
dirty ext4 journal replays into a RAM COW rather than onto the volume. Three things went wrong on
the way to a green real-kernel run.

1. **Arm C (a repository that exists only in the journal) failed on CI** with
   `INSTRUMENT: arm c: after 3 builds the entry was not journal-only`. I diagnosed it as a stale
   block-device page cache, wrote a `reattach()` patch, and parked it. The data-integrity seat's
   reading was different: `fsync` on the directory commits the transaction, and `umount`
   (`sync_filesystem` → `sync_blockdev`, plus the loop device's last-close flush) writes the
   directory block to its home location. The image really did contain `ws-1.git`; `debugfs` was
   right. A fresh loop device reads the same bytes, so the patch fixed nothing.
2. **The stub harness passed 279/279 with a mount of the origin in it.** The allowlist matched the
   origin's node string `$FX/dev/vol`; `mount -r "$_pt_link"` spelled it `$FX/dev/by-id/…`.
   The stubs also answered by call count and ignored their operand, so `cryptsetup isLuks
   /dev/null`, reading `errors_count` of the served store, or an `e2fsck` of the origin (no stub
   at all) all stayed green. Every mutant I had written deleted or moved a SUT line; none edited
   what the stubs could observe.
3. **Two runtime gates would have failed in production, in opposite directions.** The write check
   compared a `dmesg` line count before and after. That fails open: a saturated ring keeps the
   count flat, the ring wraps, and since v6.0 the read-only warning fires once per device. The
   `errors_count == 0` requirement fails closed forever: the counter mirrors the on-disk
   `s_error_count`, which accumulates over the volume's life.

## Solution

- **Journal-only state is captured, not hoped for.** After the fsync and `EXT4_IOC_SHUTDOWN`,
  `cp --sparse=always` the backing file *before* `umount`, then attach the copy. The debugfs
  precondition stays as the instrument. CI: 91/91 over 11 arms, including C, a real torn commit
  (F: the first commit block from `debugfs logdump` zeroed, with two independent read-write replays
  as the oracle), and W, a mutant that writes one origin sector and must FATAL.
- **The write gate reads the device, not the log.** `/sys/dev/block/<maj:min>/stat` field 7
  (sectors written) and field 14 (sectors discarded), read before `--setro` and after teardown.
  Not the write-I/O count and not the flush counters: the snapshot target sends empty flushes to
  its origin, and those move neither sector field. On CI the counters moved `176 0 -> 177 0` under
  arm W and stayed flat in every other arm.
- **Liveness: compare to history.** Require `errors_count` after replay to equal the origin
  superblock's `FS Error count` and not to move across the count.
- **Stubs check their operand and model time.** Each stub `exit 64`s on an unexpected device or
  name. The errors counter keys off a "counted" marker set by the `find` stub. Catch-all stubs log
  every filesystem tool, and `umount`/`mount` refuse any path outside the fixture root. The old
  harness `rm -rf`'d whatever path it was handed.

## Key Insight

A failure on a platform you cannot run locally produces a *hypothesis* about that platform. Parking
a fix for it creates a sunk cost. The next CI round then tests the fix, not the hypothesis. Before
writing the fix, write the experiment that would distinguish the candidate causes: here, one
`debugfs -c` against a copy taken before `umount` and one taken after. That is the same shape as
the rule that settles a hazard by a reversible experiment, not an argument.

The stub half is the same defect one layer down. A mutation battery that only edits the system
under test measures the SUT against a fixed observer. When the observer cannot see an axis
(operand, time, a tool it has no stub for), no SUT mutation along that axis can fail. The
test-design seat found survivors on four axes the battery never touched: operand, time, gating and
window.

## Session Errors

1. **Planning subagent died on a session limit.** Recovery: re-spawned and resumed from the skeleton plan. **Prevention:** none needed (one-off harness limit).
2. **Phase 0 CI red on T2e KNOWN_UNDERIVED.** A new root-only suite was not in `run-registered-suites.test.sh` KNOWN_UNDERIVED. Recovery: added it. **Prevention:** already covered by work's "a file-selected suite set cannot see a repo-global ratchet" rule.
3. **The new floor exited 0 under a neutered helper (guard-vacuity-floor).** Recovery: `printf '[FATAL]' + exit 1` with the literal bound adjacent, plus a PROMOTED_FILES entry. **Prevention:** covered by the ADR-193 floor rule.
4. **Capture-test fixture mismatch.** It used a `Z` timestamp and byte equality, and its precheck ran late. Recovery: a no-zone stamp, `cmp -n`, and the precheck moved earlier. **Prevention:** one-off.
5. **Plan-shape row-6 mutant anchor misplaced.** Recovery: moved after the tls arm. **Prevention:** one-off; the mutant's landed-check caught it.
6. **fixture-relative-assert grew, twice.** Recovery: `assert_fixture_dir` on the operands, a quoted heredoc for a stub, and a regenerated (shrunk) baseline. **Prevention:** gate-enforced.
7. **lint-shell-trace-credential-refusal flagged the seed's curl.** Recovery: `--disable --noproxy '*'`, pinned destinations. **Prevention:** gate-enforced.
8. **lint-infra-no-human-steps flagged ADR alternative L.** Recovery: reworded. **Prevention:** gate-enforced.
9. **`terraform validate` on a copied layout failed.** Recovery: validated in place with a scratch `TF_DATA_DIR`. **Prevention:** one-off.
10. **A background poll was blocked by the hook.** Recovery: Monitor. **Prevention:** hook-enforced (hr-monitor-not-run-in-background-for-polling).
11. **A fix was parked for an untested cause (page cache) of arm C's CI failure.** Recovery: the data-integrity seat's kernel reading; journal-only state captured from a pre-`umount` copy; 91/91 on CI. **Prevention:** write the discriminating experiment before the fix (this learning; see Routing for why no skill bullet).
12. **Edited a file during a report-only review panel, then restored HEAD.** Recovery: restored and applied the fix in the post-panel batch. **Prevention:** covered by review's report-only protocol.
13. **Inherited premise:** the work-phase deviation said the teardown job carries no `environment:` because "the environment has required reviewers". `infra-privileged-environment.tf` says "NO `reviewers` block". Recovery: teardown binds `infra-privileged`. **Prevention:** covered by compound's inherited-framing check (name the command that falsifies the claim, then run it).
14. **The plan's Legal paragraph said "the register does not name the `noload` mechanism".** It names it twice. Recovery: CLO draft, three register markers, and a superseded marker on the plan sentence. **Prevention:** covered by the same inherited-claim check.
15. **The runbook's G2 "clean" address list was read off run 35979304442**, where `tls_private_key` and `doppler_secret` were creates. Recovery: point at `git_data_host_replace_gate` as the single source. **Prevention:** covered by work's "verify a measurement at the granularity you claim it".
16. **`pgrep -f` was blocked by the hook.** Recovery: `proc.sh`. **Prevention:** hook-enforced.
17. **`sed` got a negative line number** from an empty grep. Recovery: re-ran with a grep that matched. **Prevention:** one-off.
18. **The inline `assert_fixture_dir` was copied from a sibling (the plan-shape test), not the canonical `test-helpers.sh` body**, so fixture-dir-operand's drift arm went red. Recovery: canonical body. **Prevention:** gate-enforced; copy from `plugins/soleur/test/test-helpers.sh`, never a sibling.
19. **Census G4c went red on an orphan main had added after the branch was cut.** Recovery: rebase. **Prevention:** one-off (re-derive after every merge).
20. **`deploy-script-tests` was cancelled at its 27-minute ceiling in the runcmd rehearsal step**, on main too. Recovery: not required; the loopback step completed before the cancel. **Prevention:** tracked by #8688.
21. **Session-state's plan-phase decision "blockdev --setro stays on for the host's lifetime" is false**: `BLKROSET` is in memory, per boot. Recovery: ADR-239 and register wording corrected; the review record in session-state notes it. **Prevention:** covered by the inherited-claim check.

## Routing

- Not routed to a skill. The natural home, `plugins/soleur/skills/work/SKILL.md` Common Pitfalls, is
  at its `lint-skill-body-budget` ceiling (362,000 bytes; the bullet put it 519 over), and
  extracting a block is ADR-229-gated work outside this PR. This learning carries the rule and is
  discoverable by tag (`loopback`, `stubs`, `mutation-testing`).
