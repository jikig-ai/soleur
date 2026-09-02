---
title: "Tasks — gated inngest-volume-recut apply_target + LUKS recut"
branch: feat-one-shot-7695-inngest-volume-recut-luks
plan: knowledge-base/project/plans/2026-09-02-infra-inngest-volume-recut-luks-plan.md
tracks: [7695, 7674, 6894]
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Tasks

Derived from `knowledge-base/project/plans/2026-09-02-infra-inngest-volume-recut-luks-plan.md`.
Phase order is load-bearing: Phase 2 changes a contract (the probe's field set) that Phase 4
consumes, and Phase 3's cloud-init must tolerate the pre-recut state before any recut exists.

## Phase 1 — Preconditions (measure, do not assume)

- [ ] 1.1 Re-run every Premise Validation reading in the plan. Confirm `cutover_flag`, host-dark
      probe fields, G3.7's `L`/`H`, and the Hetzner volume's `format` + id. Record verbatim.
- [ ] 1.2 `terraform plan` in `apps/web-platform/infra/` and read whether removing
      `format = "ext4"` from `hcloud_volume.inngest_redis` queues a **replace**. Record the
      verbatim plan line. Decide `lifecycle { ignore_changes = [format] }` on that measurement.
- [ ] 1.3 `gh api repos/:owner/:repo/environments/inngest-cutover` — confirm the reviewer set is
      still **non-empty**. A zero-reviewer environment auto-approves silently.
- [ ] 1.4 Read all three `.c4` files in full and complete the external-actor / external-system /
      container / access-relationship enumeration the ADR-C4 gate requires. Record what was checked.
- [ ] 1.5 Verify `--history-retention` is actually set on the inngest-server unit (unit file, not
      prose) — PA-13(f) publishes a 30-day envelope that must be evidenced.
- [ ] 1.6 Confirm `RECUT-INNGEST-VOLUME` collides with no existing confirm literal.

## Phase 2 — The read channel (M0)

- [ ] 2.1 Extend `SOLEUR_INNGEST_SERVER_PROBE` in `apps/web-platform/infra/inngest-bootstrap.sh`
      with `flush_latched`, `latch_flushed_at`, `latch_dbsize` (parsed from the **last** line of the
      append-only latch record) and `redis_keys`.
- [ ] 2.2 `redis_keys` MUST come from `INFO keyspace` across **all** databases — never `DBSIZE`,
      which is db-0 only while `FLUSHALL` spans every db.
- [ ] 2.3 Emit the new fields from the `rolled-back` / `done` / `aborted` terminal no-op arms too;
      they currently ship an empty string.
- [ ] 2.4 Confirm no new inbound control plane is introduced — this extends an existing emitter over
      the already-adopted Vector → Better Stack transport. ADR-100 Decision 6a stays unamended.

## Phase 3 — LUKS apparatus (inert on merge)

- [ ] 3.1 Create `apps/web-platform/infra/inngest-redis-luks.tf` with
      `random_password.inngest_redis_luks` (length 40, `special = false`, **no** `ignore_changes`)
      and `doppler_secret.inngest_redis_luks_key` → `INNGEST_REDIS_LUKS_KEY` on
      `soleur-inngest/prd`, masked. Both in **one file** — the posture linter requires co-location.
- [ ] 3.2 Remove `format = "ext4"` from `hcloud_volume.inngest_redis` (gated on task 1.2).
- [ ] 3.3 Write the three-arm LUKS stage in `cloud-init-inngest.yml`: `ext4` → mount as-is and emit
      a `plaintext-awaiting-recut` marker; empty → `luksFormat`/`luksOpen`/`mkfs.ext4`/mount;
      `crypto_LUKS` → open and mount; anything else → FATAL halt.
- [ ] 3.4 Copy `cloud-init-git-data.yml`'s hardening in shape: exec'd child with `set -euo pipefail`
      + ERR trap; accept `blkid` rc 0 or 2 and treat any other rc as fatal; treat "status rc=1 but
      blkid still says crypto_LUKS" as a damaged header, not a blank volume.
- [ ] 3.5 Remove `|| true` from every step that could leave `/mnt/data` on the root disk, and drop
      the `nofail`-style silent-degrade semantics for the LUKS path.
- [ ] 3.6 Add an `ExecStartPre` `findmnt` re-assertion to the Redis unit so it refuses to serve off
      an unmounted path.
- [ ] 3.7 Register `SOLEUR_INNGEST_LUKS_STAGE` in `vector.toml` Source 4
      `include_matches.SYSLOG_IDENTIFIER` **and** in `vector-pii-scrub.test.sh` — same commit.
- [ ] 3.8 Write `apps/web-platform/infra/inngest-redis-luks.test.sh` (no `format` on the volume; key
      on `soleur-inngest` not `soleur`; blkid discriminator present; all four arms covered).

## Phase 4 — The gated apply_target

- [ ] 4.1 **Write both mutation matrices BEFORE the guards.** A matrix derived from finished code
      tests the code that exists; a matrix derived from the design tests the property.
- [ ] 4.2 `tests/scripts/lib/inngest-volume-recut-gate.sh` — sourced by both the workflow step and
      its test. Allow-set is exactly the volume + its attachment; `hcloud_server.inngest` is
      named-live and must show zero actions. Include the fail-closed preamble, the ID-PIN against
      `.change.before.id`, and the recovery bare-create arm (`["create"]` with `before == null`).
- [ ] 4.3 `tests/scripts/test-inngest-volume-recut-gate.sh` — mutation rows 1-9 (incl. 5b) plus
      harness rows H1-H3. Fixtures **synthesized**, never captured production plans.
- [ ] 4.4 `tests/scripts/lib/inngest-host-dark-gate.sh` — positive allowlist returning only `dark`;
      `silent` and `unreadable` are distinct tokens and both abort. All six conditions from one row.
- [ ] 4.5 `tests/scripts/test-inngest-host-dark-gate.sh` — mutation rows 1-10 plus H1-H3, including
      the busy-fleet must-PASS row and the two-different-rows row.
- [ ] 4.6 Add the `inngest-volume-recut` job to `apply-web-platform-infra.yml`:
      `environment: inngest-cutover`, typed `confirm=RECUT-INNGEST-VOLUME`,
      `expected_inngest_volume_id` (`^[0-9]+$`, slot 8 of 10 — add no second input), job-level
      `concurrency` mutex, **no `[ack-destroy]` bypass**, never auto-executed, never chained.
- [ ] 4.7 Register in all **five** sites: workflow `options:` + bound job,
      `terraform-target-parity.test.ts`, `stock-preflight-coverage.test.ts`, `test-all.sh`, and
      `.github/workflows/infra-validation.yml`.
- [ ] 4.8 Add the enum↔job binding check so the option cannot exist without its guarded job.

## Phase 5 — Records

- [ ] 5.1 Addendum-in-place to ADR-142 recording measured fact (host not serving across the
      observable window; occupancy unmeasured; ~20d retention makes the historical question
      unanswerable). Do **not** touch its `## Decision`.
- [ ] 5.2 New ADR (provisionally **ADR-198** — re-derive the ordinal against freshly-fetched refs
      before merge): destructive clearance authorized only on a measured-empty store; ADR-142's
      byte-copy mandatory otherwise. Record the ~20d retention floor and `L`'s polarity inversion
      between `op=arm` and `op=resume`.
- [ ] 5.3 Rewrite the `hcloud_volume.inngest_redis` ledger row: `mechanism` → `luks`, exception
      block **removed**, evidence rewritten with a **content anchor** (no bare line number),
      `does_not_defend` and `live_verification` updated.
- [ ] 5.4 Correct Article 30 PA-13 limb (e) — the substrate is a host-local Redis AOF on a block
      volume on a **dedicated** host, not "SQLite on the same Hetzner host".
- [ ] 5.5 File a `compliance/` issue for PA-13 limb (f): the cross-PA determination of whether the
      Inngest store is personal-data-bearing. Do not attempt it inline.
- [ ] 5.6 Add the Art. 5(2) destruction-record template under `knowledge-base/legal/audits/`.
- [ ] 5.7 Update `.c4` if task 1.4 found this store's encryption state annotated; re-run
      `c4-code-syntax.test.ts` + `c4-render.test.ts`.

## Phase 6 — Verification

- [ ] 6.1 `bash scripts/test-all.sh` in full — the full-suite exit gate, not the touched-file loop,
      is what catches a missed registration site.
- [ ] 6.2 `python3 scripts/lint-encryption-posture.py --repo-sweep` exits 0 with the row resolving
      as `mechanism: luks`.
- [ ] 6.3 `terraform validate` in `apps/web-platform/infra/`.
- [ ] 6.4 `actionlint` on `apply-web-platform-infra.yml`; `bash -n` on the extracted `run:` body.
- [ ] 6.5 Independently re-mutate every guard row and confirm RED (or PASS for the must-PASS rows).
      A self-graded battery is not proof.
- [ ] 6.6 PR body uses `Tracks #7695`, `Tracks #7674`, `Tracks #6894` — **never `Closes`**.

## Out of scope

- **#7698** (app dispatch failing) — separate issue, separate PR.
- Dispatching any state-changing `cutover-inngest.yml` op (`arm`, `execute`, `quiesce-web`,
  `rollback`, `rearm`). This work BUILDS the capability; opening the cutover window is a separate
  decision made at the window.
- Running the recut, `terraform apply`, or mutating `INNGEST_CUTOVER_FLIP` /
  `INNGEST_DIAGNOSTIC_BOOT`.
- The webhook latch readback (ADR-100 Decision 6a stands unamended).
- R2 header escrow (rejected for this store by ADR-142).
