# Tasks — ledger root-disk scope and record anchors

Plan: `knowledge-base/project/plans/2026-09-23-chore-8532-ledger-anchored-at-rest-records-and-host-root-disk-scope-plan.md`

Revised after plan review (see the plan's `## Plan Review Revisions`). **Four deliverables, not five PRs:**

0. Arm the gate (#6907) — until then every property below is advisory.
A. The email refusal fix, shipping independently.
B. One ledger PR: floor integrity, host rows, record anchors, and the images' records.
C. The image deletion, operator-gated on #6178.

Nothing here edits `apps/web-platform/infra/`.

## Phase 0 — PR-0: the refusal path stops carrying the address (BLOCKING)

- [ ] 0.1 Re-verify the chain before editing: the three interpolated `throw` sites, the `email_send` catch that mirrors them, `logger.ts` having no serializers, and journald `Storage=persistent` on the web host.
- [ ] 0.2 Write the failing test first: drive a refused send through the real emitter and assert no substring of the input address appears in the emitted record.
- [ ] 0.3 Replace the interpolations with synthetic messages that keep the failure class and drop the value.
- [x] 0.4 Class fix at the emit seams (leaf `pii-redact.ts`, observability emitters, `logger.ts` logMethod hook, `sentry-scrub.ts` value layer) — not a pino serializer, per R8. Shipped in PR #8617.
- [ ] 0.5 Sweep `apps/web-platform/server/` for the same shape and classify every hit.
- [ ] 0.6 Confirm `docs/legal/privacy-policy.md` is unchanged and now true.

## Phase 0b — arm the gate first (#6907)

- [ ] 0b.1 Add a blocking step that runs the sweep against the REAL ledger inside the already-required `test` check. Until this lands, "a new host cannot ship unledgered" is not delivered by anything in this plan.

## Phase 1 — floor and anchor integrity

- [ ] 1.1 `check_non_iac_identity`: every catalogued id resolves to a row.
- [ ] 1.2 `resolve_disclosed_as`: exactly-one-occurrence, distinct messages for 0 and for more than 1.
- [ ] 1.3 Close #8527: run the disclosure check on `luks` rows, positive direction.
- [ ] 1.4 Delete the now-false honesty note from the `hcloud_volume.registry` row.
- [ ] 1.5 Cases plus mutation rows MB-17/18/19; each must flip FAIL to PASS when its guard is deleted.
- [ ] 1.6 Raise `MIN_CASES` to the new count.

## Phase 2 — PR-2: host root disks

- [ ] 2.1 Add `host-root-disk` to both kind enums; move `hcloud_server` from `non_store_types` into `store_classes`.
- [ ] 2.2 Edit `hcloud_volume.workspaces` too: it is `for_each` over both web hosts, so PR-2 reds its own CI without it. (The `reason` per `non_store_types` entry is CUT — it crashes the partition check.)
- [ ] 2.3 Write the six rows. Each exception states its own justification, tracker, rebuild-window trigger and review date.
- [ ] 2.4 Rename `git_data.baked_credentials_on_host`, narrowed to the two live Doppler-fallback sites.
- [ ] 2.5 `check_instance_multiplicity` plus MB-14, with a two-instance fixture whose second member is the offender.
- [ ] 2.6 Amend the four `luks` rows' `does_not_defend` to name where each passphrase lives.
- [ ] 2.7 Schema update; ADR for the scope change; amend ADR-140 to record that the seed was mechanical.

## Phase 3 — PR-3: record anchors (#8532)

- [ ] 3.1 `records` field plus schema.
- [ ] 3.2 `check_records_resolve` and `check_record_anchors_named` over a ledger-declared `RECORD_SURFACES` (R11) with a count floor and CODEOWNERS pin; MB-15/16.
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
