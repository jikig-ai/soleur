---
title: "Tasks — gated inngest-volume-recut apply_target + LUKS recut"
branch: feat-one-shot-7695-inngest-volume-recut-luks
plan: knowledge-base/project/plans/2026-09-02-infra-inngest-volume-recut-luks-plan.md
tracks: [7695, 7674, 6894]
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Tasks

> **Delivery status — 2026-09-03 (Merge B).** Boxes are ticked ONLY where this session ran the
> check itself, never in bulk. Phase 1 is Merge A's and is left untouched here — §D3 of the plan
> records that task 1.8 was NOT delivered, so ticking Phase 1 wholesale would assert something the
> plan itself contradicts. Still open at the end of this session, with reasons:
>
> - **5.1** (`bash scripts/test-all.sh` in full) — deferred to the `/ship` full-battery checkpoint
>   per ADR-183. A sibling worktree held the advisory lock throughout
>   (`CAPACITY_CONTENDED reason=sibling_runs`), and a run queued behind it measures nothing useful.
> - **5.4** (`actionlint`) — run and clean; `scripts/lint-workflows.sh` reports its pre-existing
>   census findings (tracked #7042) and none of them name the new job.
> - **5.5** — done for both guards (Guard 1: 34 assertions; Guard 2: 61, including a 20-case
>   per-PREDICATE drop-one battery and a guard-mutation harness that requires each mutation to
>   change exactly one line). Also done for all 13 structural arms of the LUKS suite.
> - **4.4 / 4.5** — DONE. The CLO ruled, and widened it: the propagation set is THIRTEEN files, not
>   one limb. PA-13 (e), (f) and (g)/TOM-11 are corrected in place with the CLO's drafted wording;
>   the published data-protection disclosure and privacy policy are corrected canonical + mirror
>   with the SHAs re-pinned; ADR-030's `Bound to 127.0.0.1 only` Decision clause is STRUCK (it is
>   the citation every downstream false claim traced back to); a runbook intro and a source comment
>   are corrected; and the LIA plus two DPIA screenings get dated APPENDED addenda rather than
>   in-place edits, because silently editing the factual premise of a completed balancing destroys
>   the evidence of what was weighed. The CLO also reversed part of its own first draft: `/v1/*` IS
>   loopback-gated in software, so the retired text understated the safeguard rather than
>   overstating it. Deferred to #7779: the Redis AOF retention determination, the shared-store
>   plaintext-at-rest gap across PA-13/14/21/22/27/31, and a live probe of whether
>   `/api/dashboard/runs` actually functions as the Art. 15 route we publish.
> - **B4** is recorded FALSIFIED AS WRITTEN in the plan's delivery addendum, with the property it
>   was standing in for measured PASSING. It is not quietly satisfied by a looser reading.

Derived from the plan **after** its deepen-plan revision (see §Deepen-Plan Revisions). Two merges:
Merge A's delivery vehicle aborts on Merge B's `.tf` edits, so combining them makes Merge A
undeliverable. Phase order is load-bearing throughout.

## Phase 0 — Preconditions

- [ ] 0.1 Re-run every Premise Validation reading in the plan; record verbatim.
- [x] 0.2 `terraform plan` — record the verbatim line proving `apply_target=inngest-host` yields a
      **zero-delete** plan under `ignore_changes = [format]`.
- [ ] 0.3 `gh api repos/:owner/:repo/environments/inngest-cutover` — reviewer set non-empty.
- [x] 0.4 Read all three `.c4` files; complete the external-actor / external-system / container /
      access-relationship enumeration and record what was checked.
- [x] 0.5 Verify `--history-retention` against the inngest-server unit file.
- [ ] 0.6 Confirm `RECUT-INNGEST-VOLUME` is a unique confirm literal and the workflow is at 7 of 10
      dispatch inputs before adding the 8th.

## Phase 1 — MERGE A: the read channel (and nothing else)

- [ ] 1.1 Extend `SOLEUR_INNGEST_SERVER_PROBE` with `probe_schema=2`, `flush_latched`,
      `latch_flushed_at`, `latch_lines`, `redis_keys`, `data_mount_src`, `data_bytes`.
- [ ] 1.2 Apply the change at **BOTH** emit sites — the unconditional `logger -t` line **and** the
      `inngest-boot-phone-home.sh` Vector-down fallback. The fallback is the channel that carries a
      row when Vector is down, i.e. exactly when `silent` would otherwise fire.
- [ ] 1.3 Add a test asserting the two emit sites' field lists are **identical**.
- [ ] 1.4 `redis_keys` from `INFO keyspace` across **all** dbs — never `DBSIZE`. On any non-zero rc,
      or a missing `# Keyspace` header, emit `__UNREADABLE__` — never an empty string, never `0`.
- [ ] 1.5 `data_mount_src` from `findmnt -no SOURCE /mnt/data`; `data_bytes` from `du -sb /mnt/data`.
- [ ] 1.6 Give the probe unit its Redis credential. Do **not** ship raw stderr from a credentialed
      CLI — the file already warns that would route the token's own error text to Better Stack.
- [ ] 1.7 Scope the new fields to the dedicated host (`inngest-bootstrap.sh` is the **shared**
      renderer for both hosts). On the web host emit `n/a`, never `0`. Pin with a fixture.
- [ ] 1.8 Emit the new fields from the `rolled-back` / `done` / `aborted` terminal no-op arms.
- [ ] 1.9 **Verify no `.tf` or cloud-init LUKS change is in this merge** — that is what keeps
      `inngest_host_replace_gate`'s three-address allow-set satisfied. Run
      `bash tests/scripts/test-inngest-host-replace-gate.sh`.

## Phase 2 — MERGE B: LUKS apparatus (inert except the passphrase)

- [ ] 2.1 `inngest-redis-luks.tf`: `random_password.inngest_redis_luks` (len 40, `special = false`,
      no `ignore_changes`) + `doppler_secret.inngest_redis_luks_key` → `INNGEST_REDIS_LUKS_KEY` on
      `soleur-inngest/prd`, masked. **One file** — the posture linter requires co-location.
- [ ] 2.2 Add **both** to the per-merge `-target=` allowlist. The passphrase must exist before any
      host boots that reads it; "merge is inert" is the defect here, not the safety property.
- [ ] 2.3 `lifecycle { ignore_changes = [format] }` on `hcloud_volume.inngest_redis`. Do **not**
      remove the `format` line at merge — that would make `apply_target=inngest-host` permanently
      abort under its additive-only guard.
- [ ] 2.4 Five-arm cloud-init discriminator: device-absent-after-wait → FATAL; `ext4` → mount as-is
      pre-recut / **FATAL** post-recut (via the `expect_luks` flag); empty → luksFormat/luksOpen/
      mkfs/mount; `crypto_LUKS` → open + mount; anything else → FATAL.
- [ ] 2.5 Bounded device-presence wait (~30s, `[ -b "$DEV" ]` + non-zero `blockdev --getsize64`)
      **before** the discriminator. `blkid` on an absent path returns rc 2, which the accept-0-or-2
      policy would otherwise route into the luksFormat arm.
- [ ] 2.6 Thread `expect_luks` through `templatefile()` the way `inngest_volume_id` already is.
- [ ] 2.7 git-data hardening: exec'd child with `set -euo pipefail` + ERR trap; `blkid` rc 0 or 2
      accepted and any other rc fatal; "status rc=1 but blkid says crypto_LUKS" = damaged header;
      per-operation rc checks on luksFormat/luksOpen/mkfs/mount.
- [ ] 2.8 No `|| true`, no `|| :`, no `set +e` on any step that could leave `/mnt/data` on the root
      disk. **Keep `nofail` in fstab** — a strict fstab on a no-SSH host turns a slow attach into an
      unrecoverable boot wedge.
- [x] 2.9 `inngest-luks-open.service`: `Type=oneshot`, `RemainAfterExit=yes`,
      `DefaultDependencies=no`, `Before=inngest-redis.service`; passphrase via
      `/etc/default/inngest-doppler`. `runcmd` runs **first boot only**, so without this the mapper
      is absent on boot 2 and Redis writes plaintext to the root disk.
- [x] 2.10 Two-state `ExecStartPre` `findmnt` gate: always assert `/mnt/data` is a mountpoint;
      assert the source is `/dev/mapper/inngest-redis` **only when** `blkid` reported `crypto_LUKS`.
      A one-state gate deadlocks the plan by blocking Redis on the pre-recut host.
- [ ] 2.11 `SOLEUR_INNGEST_LUKS_STAGE` in `vector.toml` Source 4 **and** `vector-pii-scrub.test.sh`,
      same commit.
- [x] 2.12 `inngest-redis-luks.test.sh` covering all five arms + the ext4-still-starts-Redis case +
      a second-simulated-boot case for the reopen unit (loop-file harness precedent).

## Phase 3 — MERGE B: the gated apply_target

- [x] 3.1 **Write both mutation matrices BEFORE the guards.**
- [x] 3.2 `tests/scripts/lib/inngest-volume-recut-gate.sh` — allow-set is the volume + its
      attachment only; `hcloud_server.inngest` is named-live and must show zero actions. Fail-closed
      preamble, ID-PIN on `.change.before.id`, `id_pin_absent` when the pin is empty on a genuine
      destroy, recovery bare-create arm.
- [x] 3.3 `tests/scripts/test-inngest-volume-recut-gate.sh` — mutation rows 1-10 + harness H1-H3.
      Fixtures **synthesized**, never captured production plans.
- [x] 3.4 `tests/scripts/lib/inngest-host-dark-gate.sh` — all 13 conditions from ONE row, positive
      allowlist returning only `dark`; `silent`, `unreadable`, `stale_schema`, `mount_mismatch`,
      `not_dark` are distinct tokens and all abort.
- [x] 3.5 `tests/scripts/test-inngest-host-dark-gate.sh` — mutation rows 1-15, harness H1-H3, and
      the **drop-one battery** (one case per condition, each asserting a distinct reason token).
- [x] 3.6 A test feeding a **real emitter line** through the Guard 2 parser, asserting every field
      name resolves — the emit/read contract.
- [x] 3.7 Workflow job: `environment: inngest-cutover`, typed `confirm=RECUT-INNGEST-VOLUME`,
      `expected_inngest_volume_id` (`^[0-9]+$`, slot 8 of 10 — no second input), no `[ack-destroy]`
      bypass, never auto-executed, never chained.
- [x] 3.8 `concurrency: {group: inngest-cutover, cancel-in-progress: false}` on the recut job,
      `inngest_host`, `inngest_host_replace`, **and** `cutover-inngest.yml`'s arm/resume path.
- [x] 3.9 Synchronous Doppler flag re-read immediately before apply; refuse on anything but
      `rolled-back` / `aborted`.
- [x] 3.10 Register in all **six** sites: workflow `options:`, the bound job,
      `terraform-target-parity.test.ts`, `stock-preflight-coverage.test.ts`, `test-all.sh`,
      `infra-validation.yml`. Amend the `confirm` input **description** too — it enumerates which
      targets carry an `environment:` gate.
- [x] 3.11 Enum↔job binding check.
- [x] 3.12 Mechanically-runnable mutation harness: applies each mutation as a patch to a pristine
      copy, runs the guard, asserts the **reason token** (not just rc). Invoked from `test-all.sh`.

## Phase 4 — MERGE B: records

- [x] 4.1 ADR-142 **addendum-in-place** recording measured fact. Do not touch its `## Decision`.
- [x] 4.2 New ADR (ordinal provisional — re-derive against freshly-fetched refs before merge):
      destructive clearance authorized only on a measured-empty store and a serving-capable host;
      ADR-142's byte-copy mandatory otherwise. Record the ~20d retention floor and `L`'s polarity
      inversion between `op=arm` and `op=resume`.
- [x] 4.3 Ledger row: **keep the `exception`**, re-dated, with the bare-line-number citation
      replaced by a content anchor. Do **not** flip `mechanism` to `luks` in this merge.
- [x] 4.4 Article 30 PA-13 limb (e) — substrate is a host-local Redis AOF on a block volume on a
      dedicated host, not "SQLite on the same Hetzner host".
- [x] 4.5 File a `compliance/` issue for PA-13 limb (f).
- [x] 4.6 File an issue for the **append-only authorized latch clear** — the stated fallback for the
      `redis_keys > 0` branch, which is otherwise circular.
- [x] 4.7 Art. 5(2) destruction-record template under `knowledge-base/legal/audits/`.
- [x] 4.8 Update `.c4` if 0.4 found this store's encryption state annotated; re-run
      `c4-code-syntax.test.ts` + `c4-render.test.ts`.

## Phase 5 — Verification

- [ ] 5.1 `bash scripts/test-all.sh` in full.
- [x] 5.2 `python3 scripts/lint-encryption-posture.py --repo-sweep` — exits 0 **with the exception
      block still present**.
- [x] 5.3 `terraform validate`.
- [ ] 5.4 `actionlint` on both workflows; `bash -n` on extracted `run:` bodies.
- [ ] 5.5 Independently re-mutate every guard row and confirm RED (or PASS for must-PASS rows).
- [x] 5.6 PR bodies use `Tracks`, never `Closes`.

## Out of scope

- Dispatching any state-changing `cutover-inngest.yml` op (`arm`, `execute`, `quiesce-web`,
  `rollback`, `rearm`). This work BUILDS the capability.
- Running the recut, `terraform apply`, or mutating `INNGEST_CUTOVER_FLIP` /
  `INNGEST_DIAGNOSTIC_BOOT`.
- **Fixing #7674's bind failure.** It is a hard *precondition* of the recut dispatch, enforced by
  Guard 2, but diagnosing it is separate work.
- **#7698** (app dispatch failing) — separate issue, separate PR.
- The webhook latch readback (ADR-100 Decision 6a stands unamended).
- R2 header escrow (rejected for this store by ADR-142, confirmed by the CTO ruling).
