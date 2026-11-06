# Tasks — feat-one-shot-10112-inngest-residuals

Plan: `knowledge-base/project/plans/2026-11-06-chore-inngest-9786-residuals-plan.md`
Issue: #10112 (closes). Epic #10390 stays OPEN.

## Phase 1 — Setup & verification

- 1.1 `git fetch origin main`; re-verify every premise the plan pinned: `hcloud_volume.rehearsal_inngest` + attachment still in `rehearsal.tf`; ledger row present; `unpointed_raw_refused` arm present; both resolver copies present; `inngest-verify-clean-10390.sh` still absent.
- 1.2 Confirm decision-challenges.md ruling rows: proceed on the `pending - assumed` defaults unless the parent session-state records a different ruling (item 3 procedure-vs-decline; item 3 `prd`-admission mechanism; item 4 share-vs-accept).
- 1.3 Write `specs/feat-one-shot-10112-inngest-residuals/verification-notes.md` — the durable artifact `ship` folds into the PR body: item-1 verification (trio absent on main), verify-clean-10390 absence, item-2 scope-lift provenance.

## Phase 2 — Item 2: remove the unused rehearsal volume (FR-1..FR-4)

- 2.1 `apps/web-platform/infra/inngest-provision-rehearsal/rehearsal.tf`: delete `resource "hcloud_volume" "rehearsal_inngest"` and `resource "hcloud_volume_attachment" "rehearsal_inngest"`; rewrite the "two volumes" comment for the single LUKS volume.
- 2.2 `scripts/encryption-posture-ledger.json`: delete the `stores[]` row `"store": "hcloud_volume.rehearsal_inngest"` (device_binding, at_rest, live_verification, exception blocks). Re-grep the whole file for `rehearsal_inngest\b`.
- 2.3 `tests/scripts/test-inngest-provision-plan-shape.sh`: trim `ADDITIVE_OK` (volume + attachment creates), drop the Phase-B `hcloud_volume.rehearsal_inngest:no-op`, retarget the two `import=` refusal fixtures at `hcloud_volume.rehearsal_inngest_luks`; normalize the `rehearsal_inngest_inngest_luks` spelling.
- 2.4 `knowledge-base/engineering/operations/runbooks/inngest-provision-rehearsal.md`: "two scratch volumes" → one; add the stranded-state `terraform state rm` remediation note.
- 2.5 Gates: `terraform -chdir=apps/web-platform/infra/inngest-provision-rehearsal validate`; `bash apps/web-platform/infra/inngest-provision-rehearsal.test.sh`; `bash tests/scripts/test-inngest-provision-plan-shape.sh`; `python3 scripts/lint-encryption-posture.py`.

## Phase 3 — Item 3: blank-prd DR record (FR-5)

- 3.1 `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md`: replace the "needs a written disaster-recovery procedure when it is ever needed" sentence with the "Blank `prd` volume bring-up" procedure (assumed arm): preconditions (intentionally-blank establishment; ADR-282 two-step lift if replacing `hcloud_volume.inngest_redis_luks`), delete `INNGEST_LUKS_ACTIVE_VOLUME_ID` in `soleur-inngest/prd`, reviewed allowlist-patch window admitting `prd`, `apply_target=inngest-host-replace`, `luks_format`→`mount_luks` verification rows, revert PR, optional pointer re-write. State what it deliberately is NOT (no standing flag/target).

## Phase 4 — Item 4 + ADR-142 addendum (FR-6, FR-7)

- 4.1 Runbook note (same file): the deliberate two-copy resolver — shared decision, named asymmetries, drift bound (`inngest-redis-luks-loopback.test.sh` verbatim extraction + `inngest-redis-luks.test.sh` literal pins + D5 precedent).
- 4.2 `ADR-142` addendum: dated entry recording the item-3 route and the item-4 disposition.
- 4.3 If ruling = "share": extract a `/usr/local/lib/` `write_files` helper sourced by both scripts; update loopback extraction points + literal pins; re-run #10243 overlap check; re-run `inngest-redis-luks{,-loopback}.test.sh`.

## Phase 5 — Close-out

- 5.1 AC sweep AC1–AC9 against the plan; write outcomes into verification-notes.md.
- 5.2 `git status` clean; affected suites green (`scripts/test-all.sh` affected derivation — wait out the advisory lock if queued); GuardA expected-red vs real-red distinction applied.
- 5.3 Ship phase: `Closes #10112` in the PR body; annotate epic #10390 (the `inngest-verify-clean-10390.sh` residual is discharged — verified absent on main).
