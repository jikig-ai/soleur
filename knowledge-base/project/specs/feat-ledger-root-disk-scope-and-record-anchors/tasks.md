# Tasks — ledger root-disk scope and record anchors

Plan: `knowledge-base/project/plans/2026-09-23-chore-8532-ledger-anchored-at-rest-records-and-host-root-disk-scope-plan.md`

Five PRs, strictly ordered. Each is its own branch off `main`; nothing here edits `apps/web-platform/infra/`.

## Phase 0 — PR-0: the refusal path stops carrying the address (BLOCKING)

- [ ] 0.1 Re-verify the chain before editing: the three interpolated `throw` sites, the `email_send` catch that mirrors them, `logger.ts` having no serializers, and journald `Storage=persistent` on the web host.
- [ ] 0.2 Write the failing test first: drive a refused send through the real emitter and assert no substring of the input address appears in the emitted record.
- [ ] 0.3 Replace the interpolations with synthetic messages that keep the failure class and drop the value.
- [ ] 0.4 Add the `err` serializer (or scoped equivalent) so a future throw cannot reintroduce the class.
- [ ] 0.5 Sweep `apps/web-platform/server/` for the same shape and classify every hit.
- [ ] 0.6 Confirm `docs/legal/privacy-policy.md` is unchanged and now true.

## Phase 1 — PR-1: floor and anchor integrity

- [ ] 1.1 `check_non_iac_identity`: every catalogued id resolves to a row.
- [ ] 1.2 `resolve_disclosed_as`: exactly-one-occurrence, distinct messages for 0 and for more than 1.
- [ ] 1.3 Close #8527: run the disclosure check on `luks` rows, positive direction.
- [ ] 1.4 Delete the now-false honesty note from the `hcloud_volume.registry` row.
- [ ] 1.5 Cases plus mutation rows MB-17/18/19; each must flip FAIL to PASS when its guard is deleted.
- [ ] 1.6 Raise `MIN_CASES` to the new count.

## Phase 2 — PR-2: host root disks

- [ ] 2.1 Add `host-root-disk` to both kind enums; move `hcloud_server` from `non_store_types` into `store_classes`.
- [ ] 2.2 Give every remaining `non_store_types` entry a reason.
- [ ] 2.3 Write the six rows. Each exception states its own justification, tracker, rebuild-window trigger and review date.
- [ ] 2.4 Rename `git_data.baked_credentials_on_host`, narrowed to the two live Doppler-fallback sites.
- [ ] 2.5 `check_instance_multiplicity` plus MB-14, with a two-instance fixture whose second member is the offender.
- [ ] 2.6 Amend the four `luks` rows' `does_not_defend` to name where each passphrase lives.
- [ ] 2.7 Schema update; ADR for the scope change; amend ADR-140 to record that the seed was mechanical.

## Phase 3 — PR-3: record anchors (#8532)

- [ ] 3.1 `records` field plus schema.
- [ ] 3.2 `check_records_resolve` and `check_record_anchors_named` over a hard-coded `RECORD_SURFACES`; MB-15/16.
- [ ] 3.3 Add `// ledger: <store id>` to the store elements in `model.c4`, and the Inngest store's missing at-rest posture.
- [ ] 3.4 Regenerate `model.likec4.json` in the same commit; run the C4 freshness and parity suites.
- [ ] 3.5 Register: the five CLO amendments, each with a dated amendment marker, plus the visible `(encryption-posture ledger: <id>)` clauses.
- [ ] 3.6 Record the amendment convention in the register's maintenance section, which has none today.
- [ ] 3.7 Route the register edits through the CLO before marking the PR ready.

## Phase 4 — PR-4: the web-host root-disk images (operator-gated)

- [ ] 4.1 Determine which of the four images the #6178 rollback still needs; record the finding.
- [ ] 4.2 Ledger row for the images as a provider-side derivative store.
- [ ] 4.3 Article 30 retention statement plus the Art. 17 reachability note; this discharges PA-36's standing commitment.
- [ ] 4.4 Propose deletion with the exact command and stop. Deletion runs only on the operator's per-command authorization, with an Art. 5(2) record written at the time.

## Phase 5 — close-out

- [ ] 5.1 Verify each AC against the measured value, amending any that the measurement contradicts.
- [ ] 5.2 File the `soleur:gdpr-gate` Art. 32 at-rest capability gap the CLO reported.
- [ ] 5.3 Label #8532 `domain/legal` as well as `domain/engineering`.
