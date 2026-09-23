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

- [x] 1.1 `check_non_iac_identity`: every catalogued id resolves to a row. Plus `check_store_id_accounted` (plan PR-1 item 4, R10): every row is a store-class `.tf` address or catalogued, no id repeats; `git_data.baked_credentials_on_host` catalogued. Floor now exact: 12 + 7 = 19.
- [x] 1.2 `resolve_disclosed_as`: exactly-one-occurrence, distinct messages for 0 and for more than 1.
- [x] 1.3 Close #8527: run the disclosure check on `luks` rows, positive direction (`check_luks_disclosure`: anchor line, anchor text removed, denial wins over claim).
- [x] 1.4 Supersede (dated, append-only) the now-false honesty note on the `hcloud_volume.registry` row.
- [x] 1.5 Cases plus mutation rows MB-17..MB-21 (plan numbering) and MB-22 on the floor's FAIL branch: MB-1 and MB-17 share a verdict with the now-exact floor, so each is proven by "floor deleted alone still FAILs" plus "both deleted flips to PASS".
- [x] 1.6 Raise `MIN_CASES` to the new count (30 -> 77; later derived from the ledger, 179 at review).

## Phase 2 — PR-2: host root disks

- [x] 2.1 Add `host-root-disk` to both kind enums; move `hcloud_server` from `non_store_types` into `store_classes`.
- [x] 2.2 Edit `hcloud_volume.workspaces` too: it is `for_each` over both web hosts, so PR-2 reds its own CI without it. (The `reason` per `non_store_types` entry is CUT — it crashes the partition check.)
- [x] 2.3 Write the six rows (tracker #8620; expiries staggered 2026-11-13 .. 2027-02-05). Each exception states its own justification, tracker, rebuild-window trigger and review date.
- [x] 2.4 ~~Rename~~ Narrow `git_data.baked_credentials_on_host` by dated addendum to the metadata-endpoint threat and the two live Doppler-fallback sites (`git-data-gc-failure.service`, `git-data-luks-reopen-failure.service`). The id is KEPT: five earlier plans cite it, and the host row now carries the root-disk copies.
- [x] 2.5 `check_instance_multiplicity` plus MB-14 (and MB-23 orphan rows, MB-24 fail-closed shapes, MB-25 singletons), with a two-instance fixture whose second member is the offender.
- [x] 2.6 Amend the ~~four~~ five `luks` rows' `does_not_defend` to name where each passphrase lives.
- [x] 2.7 Schema update (plus a script/schema parity test and unknown-row-key rejection); ADR-242 (ordinal provisional); ADR-140 amended.

## Phase 3 — PR-3: record anchors (#8532)

- [x] 3.1 `records` field plus schema (and `record_surfaces`; 56 records on 17 rows).
- [x] 3.2 `check_records_resolve` and `check_record_anchors_named` over a ledger-declared `RECORD_SURFACES` (R11) with a count floor and CODEOWNERS pin; MB-15/16.
- [x] 3.3 Add the ledger clause comments to the store elements in `model.c4` (12 clauses, 8 elements), and the Inngest server's root-disk at-rest posture plus the passphrase cache on `inngestRedis`.
- [x] 3.4 Regenerate `model.likec4.json` in the same commit; run the C4 freshness and parity suites (all pass).
- [x] 3.5 Register: the five CLO amendments (plus PA-1/2/21/22/36 and the cross-cutting encryption bullet), each with a dated amendment marker, plus the visible `(encryption-posture ledger: <id>)` clauses.
- [x] 3.6 Record the amendment convention in the register's maintenance section, which has none today.
- [x] 3.7 Route the register edits through the CLO before marking the PR ready. DISCHARGED with conditions: all 44 register pairs are in `records` (done); follow-ups filed as #8624 (PA-14 amendment + published claim review) and #8625 (no Hetzner backups; Art. 32(1)(c)). ADR-243 records the binding.

## Phase 4 — PR-4: the web-host root-disk images (operator-gated)

- [x] 4.1 Determine which of the four images the #6178 rollback still needs; record the finding. Only `411798619` (ADR-100 addendum 2026-09-23); the day-7 soak was NOT CLEAN. The listing is complete: 4 snapshots, 0 backups.
- [x] 4.2 Ledger row for the images as a provider-side derivative store (`hetzner.web1_inngest_cutover_snapshots`, catalogued, records PA-8/PA-13).
- [x] 4.3 Article 30 retention statement plus the Art. 17 reachability note (PA-8 §(f), PA-13 §(f)); PA-36 §(f) is marked partly discharged (its data is not in these images). Art. 5(2) template committed as `pending`.
- [ ] 4.4 Propose deletion with the exact command and stop. Deletion runs only on the operator's per-command authorization, with an Art. 5(2) record written at the time.

## Phase 5 — close-out

- [ ] 5.1 Verify each AC against the measured value, amending any that the measurement contradicts.
- [x] 5.2 File the `soleur:gdpr-gate` Art. 32 at-rest capability gap the CLO reported. Already tracked as #8526; not re-filed.
- [x] 5.3 Label #8532 `domain/legal` as well as `domain/engineering`.
