---
title: "chore: finish the inngest #9786 residuals — rehearsal volume removal, blank-prd DR record, resolver-arm drift decision"
type: chore
date: 2026-11-06
slug: chore-inngest-9786-residuals
branch: feat-one-shot-10112-inngest-residuals
issue: 10112
closes: 10112
priority: p3-low
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

## Overview

Close out the remaining residuals of #9786 tracked in #10112, whose trigger (the plaintext-resolver-arm strip, PR #10081) merged 2026-10-15. Item 1 of the issue (strip plaintext vocabulary from the image-baked `inngest-luks-cutover.sh` + image release + pin bump) is already satisfied: the cutover trio was retired from the image by the host-replace-window prework that merged 2026-10-26, and no `inngest-luks-cutover.*` artifact exists on `origin/main`. The epic's residual "delete `scripts/followthroughs/inngest-verify-clean-10390.sh` on the next inngest PR" is likewise already satisfied — the file is absent on `origin/main` (retired by the inngest@4 upgrade PR); this change carries the verification note, not a deletion.

Remaining scope, three items:

- **Item 2** — remove the unused `hcloud_volume.rehearsal_inngest` volume and its attachment from `apps/web-platform/infra/inngest-provision-rehearsal/rehearsal.tf` (declared, attached, never read since #9786), together with its `scripts/encryption-posture-ledger.json` store row, the plan-shape fixtures in `tests/scripts/test-inngest-provision-plan-shape.sh`, and the "two scratch volumes" prose in `knowledge-base/engineering/operations/runbooks/inngest-provision-rehearsal.md`. The issue records this item as filed under an operator scope-exclusion "first candidate to pull forward if the operator lifts the exclusion"; the resume brief for this change explicitly lists the volume in scope, which is the lift.
- **Item 3** — record the blank-prd-volume disaster-recovery answer in `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md`: the unpointed format arm formats only on a `rehearsal_*` config and refuses everything else `unpointed_raw_refused`, so a brand-new blank volume on a `prd` config currently has no bring-up path. The runbook (and ADR-142's 2026-10-12 addendum) already state a written procedure is owed; the change writes the procedure — or an explicit decline with its reason.
- **Item 4** — the boot-reopen script (`inngest-luks-open.sh`, a `write_files` entry) and the first-boot runcmd stage in `apps/web-platform/infra/cloud-init-inngest.yml` each carry their own copy of the resolver decision (own-id allowlist, pointer handling). Both copies still exist on `origin/main`. The issue blesses either sharing them or accepting the drift in writing.

## Research Insights

**Lane note:** Spec lacks valid `lane:` (no spec.md exists for this branch) — defaulted to `cross-domain` (TR2 fail-closed).

**Coverage disclosure:** this plan ran inside a pipeline Task subagent (Devin CLI); subagents cannot nest, so every fan-out the skill prescribes (repo-research-analyst, learnings-researcher, functional-discovery, domain leaders, spec-flow-analyzer, advisor consult, plan-review panel) ran **sequentially inline** in this session — `Reviewed-Coverage: sequential-fallback`. No independent subagent review is claimed anywhere in this plan.

**Premise Validation (Phase 0.6, verified against `origin/main` `4e0f90b`):**

- `gh issue view 10112` — OPEN, milestone "Post-MVP / Later"; `gh issue view 10390` — OPEN (epic stays open).
- Trigger confirmed: PR #10081 `MERGED` 2026-10-15T18:39:40Z ("PARKED: strip the dead plaintext-volume resolver arm").
- `hcloud_volume.rehearsal_inngest` + `hcloud_volume_attachment.rehearsal_inngest` present in `apps/web-platform/infra/inngest-provision-rehearsal/rehearsal.tf` with the "UNUSED since #9786 … removal is tracked in #10112" comment — item 2 premise holds.
- `scripts/encryption-posture-ledger.json` carries **one** `stores[]` row for `hcloud_volume.rehearsal_inngest` (mechanism `plaintext-exception`, `disposed` exception block, `tracking_issue` retired #8285); no second row in `non_iac_stores` or `connections` — see Reconciliation.
- `unpointed_raw_refused` arm present in `cloud-init-inngest.yml` (the `case '${inngest_doppler_config}' in rehearsal_*)` allowlist); `inngest_doppler_config = "prd"` is a literal in `inngest-host.tf` — item 3 premise holds.
- Both resolver copies present: `write_files` block `/usr/local/bin/inngest-luks-open.sh` ("Same authority as in the runcmd resolver") and the runcmd `STAGE=resolve` + pointer/unpointed arms — item 4 premise holds.
- Item 1 already satisfied: no `inngest-luks-cutover.{sh,service,timer}` anywhere in the tree (`git ls-tree -r origin/main | grep -i luks` — the trio is gone; the 2026-10-15 ADR-142 addendum records the whole-executor deletion).
- `scripts/followthroughs/inngest-verify-clean-10390.sh` absent on `origin/main` — the epic residual is already discharged; the epic body still records it as "still owed" (lines dated 2026-10-27).
- ADR-corpus check for proposed mechanisms (Phase 0.6 step 4): ADR-142's 2026-10-12 addendum prescribes the `rehearsal_*` format allowlist and records the blank-prd DR procedure as owed; the 2026-10-13 addendum's **CTO ruling D5 already chose pinned duplication over a shared helper** for the `wait_dev` bound across the same two readers — a precedent squarely on point for item 4's accept-in-writing arm. ADR-199's 2026-10-14 addendum: the `inngest-volume-recut` target and `inngest_host_dark_gate` are retired — no standing destructive-birth machinery exists to reuse for item 3. `hcloud_volume.inngest_redis_luks` carries `delete_protection` + `prevent_destroy` (ADR-282); its two-step lift route is documented in `inngest-redis-luks.tf`.
- Collision precheck (`collision-precheck.sh 10112`): PR #12218 names #10112 — it is **this run's own auto-created draft** (WIP, zero files), not a foreign change. Five foreign `test-all.sh` processes in sibling worktrees — noted for the advisory-lock reminder at ship time.

**Property List (Phase 0.6b):**

- P1 — the rehearsal Terraform root declares only resources the rehearsal uses (no attached-but-unread volume).
- P2 — the encryption-posture ledger contains no row for a store that does not exist (and `lint-encryption-posture.py` stays green — its positive-work floor is computed from the `*.tf` census, which drops in step with the row).
- P3 — the plan-shape fixtures describe the post-removal create set.
- P4 — the cutover runbook tells the next incident what to do about a blank `prd` volume — a written procedure or a written decline; ADR-142's 2026-10-12 addendum already records the procedure as owed.
- P5 — the duplicated resolver decision is either single-sourced or its deliberate divergence is recorded with the control that bounds it (the loopback suite executes both copies verbatim).
- P6 — the epic's stale "delete `inngest-verify-clean-10390.sh`" residual is verified discharged.

**Cut List:** every mechanism the ask names buys a property above — nothing cut. The conditional cut lives in item 4: the "shared `write_files` helper" mechanism is proposed-but-not-chosen; the assumed disposition (accept drift in writing) cuts it as buying no property beyond what the existing pinned-duplication + loopback-suite apparatus already buys. Flagged for the parent ruling.

**Research Decision (Phase 1.6):** no external research. The work is entirely inside this repo — Terraform deletion, ledger row, fixtures, runbook text, ADR addendum — with two ADRs and a CTO ruling already on record. Community discovery: no uncovered stacks (Terraform/bash/YAML). Functional overlap (sequential-fallback): assessed no-op — a repo-internal residual cleanup has no community-skill analogue.

**Relevant file paths:**

- `apps/web-platform/infra/inngest-provision-rehearsal/rehearsal.tf` — `resource "hcloud_volume" "rehearsal_inngest"` (~line 241), `resource "hcloud_volume_attachment" "rehearsal_inngest"` (~line 330), `# --- The two volumes ---` comment block (~line 233).
- `scripts/encryption-posture-ledger.json` — `stores[]` row `"store": "hcloud_volume.rehearsal_inngest"` (~line 258, through its exception block ~line 276).
- `tests/scripts/test-inngest-provision-plan-shape.sh` — `ADDITIVE_OK` create-set (~line 79-82), Phase-B fixture `hcloud_volume.rehearsal_inngest:no-op` (~line 91), two import-refusal fixtures retargeted (~lines 108-111). NOTE: the suite's LUKS fixture is spelled `hcloud_volume.rehearsal_inngest_inngest_luks` — a synthesized address that does not match the real `hcloud_volume.rehearsal_inngest_luks` resource; normalize or leave as deliberate fixture at work time, but do not treat the fixture set as a resource census.
- `knowledge-base/engineering/operations/runbooks/inngest-provision-rehearsal.md` — "two scratch volumes" (~line 71).
- `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md` — the "After the host replace that carries #9786" block (~line 818-828) containing the placeholder "needs a disaster-recovery procedure written when it is ever needed".
- `knowledge-base/engineering/architecture/decisions/ADR-142-inngest-redis-aof-zero-data-loss-luks-migration.md` — addendum lineage (2026-09-03, 2026-09-18, 2026-10-10, 2026-10-12, 2026-10-13, 2026-10-15 addenda exist).
- `apps/web-platform/infra/cloud-init-inngest.yml` — READ-ONLY in this change (both resolver copies at the `inngest-luks-open.sh` write_files block and the `STAGE=resolve`/unpointed arm ~line 2577-2700; `unpointed_raw_refused` allowlist ~line 2690); edited only if the parent ruling flips item 4 to "share" or a later DR event patches the allowlist.
- `apps/web-platform/infra/inngest-host.tf` — `inngest_doppler_config = "prd"` literal (~line 391; read-only, anchors the DR recipe's allowlist patch).
- `apps/web-platform/infra/inngest-host.tf` — `inngest_luks_volume_id = hcloud_volume.inngest_redis_luks.id` (~line 373; read-only, anchors the DR recipe).
- `scripts/lint-encryption-posture.py` — the enforcing lint (positive-work floor from `*.tf` census; `unledgered store` FAIL; plaintext-exception `disclosed_as` R5 check) — read-only.
- `scripts/inngest-provision-plan-shape.sh` — the SUT under test by the fixtures; no `rehearsal_inngest` references inside it — read-only.

**Institutional learnings applied:**

- `2026-10-12-a-denylist-of-tool-names-is-a-bypass-list-close-the-set-and-scan-the-rendered-form.md` — the `unpointed_raw_refused` allowlist pattern is a deliberate close-the-set control; the DR recipe must widen it only as a reviewed, reverted patch.
- `2026-04-28-plan-globs-must-be-verified-against-repo-structure.md` — every path cited above was verified with `git ls-tree`/`git show` on `origin/main`, not assumed.
- ADR-141/ledger floors — a deleted store row cannot silently lower floors: `check_positive_work_floor` recomputes expected count from the `*.tf` census, so removing resource + row in the same diff stays consistent.
- Process reminders carried into Risks: never ship while `test-all` is queued on the advisory lock; `deploy-script-tests` GuardA may be expected-red on main (carrier bake pending); union-merge generated TSV/legal-doc conflicts on rebase + `regenerate-shard-manifest.py --incremental --write`; `apps/web-platform` vitest runs from `apps/web-platform/`.

## Problem Statement / Motivation

Issue #10112 filed four deliberately-parked residuals of the #9786 plaintext-resolver strip, gated on PR #10081 landing. That trigger merged 2026-10-15; item 1 was independently discharged 2026-10-26 (the cutover trio was deleted from the image entirely, which subsumes the "strip its plaintext vocabulary" ask). Three items remain, each a small, verified, code-and-docs change — none a defect in shipped behaviour, but each a rot vector if left: an attached-never-read scratch volume that costs a real Hetzner volume per rehearsal dispatch and keeps a stale plaintext-exception row in the encryption audit surface; a documented gap where the next blank-`prd`-volume incident would be improvised under pressure; and a two-copy resolver decision whose divergence is currently unwritten, so a future edit could drift one copy while every suite stays green.

## Proposed Solution

Three independent but atomic-in-one-PR edits:

1. **Item 2 — delete the unused rehearsal volume.** Remove `hcloud_volume.rehearsal_inngest` + `hcloud_volume_attachment.rehearsal_inngest` and rewrite the "two volumes" comment in `rehearsal.tf`; delete its `stores[]` row from `encryption-posture-ledger.json`; update the plan-shape fixtures and the "two scratch volumes" runbook line.
2. **Item 3 — write the blank-prd DR procedure** into `inngest-luks-cutover-6894.md`, replacing the placeholder sentence. Recommended arm: the *reviewed one-time allowlist patch* recipe (see Implementation Phases), which needs no new standing mechanism. Flagged `pending - assumed` for the parent ruling (design fork vs. written decline).
3. **Item 4 — record the resolver-duplication disposition.** Recommended arm: accept the drift in writing, in the runbook + an ADR-142 addendum, naming the deliberate asymmetries and the loopback suite as the drift bound — the same pinned-duplication posture CTO ruling D5 already took for `wait_dev`. Flagged `pending - assumed` for the parent ruling (share-vs-accept fork).

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Reality on `origin/main` | Plan response |
|---|---|---|
| "the two rows in `scripts/encryption-posture-ledger.json`" | One `stores[]` row (`hcloud_volume.rehearsal_inngest`, with `device_binding` + `plaintext-exception` + exception block); no reference in `non_iac_stores`/`connections` | Delete the one row; work phase re-greps the whole ledger for `rehearsal_inngest\b` before staging |
| "the rehearsal test" needs updating | `inngest-provision-rehearsal.test.sh` has zero `rehearsal_inngest` references; the affected fixture file is `tests/scripts/test-inngest-provision-plan-shape.sh` | Update the plan-shape fixtures; re-run the sentinel test to prove no hidden volume-count pin |
| item 1 needs an image release + pin bump | Already discharged — trio deleted from the image build 2026-10-26; absent on main | Verify-only AC; recorded in the PR body |
| item 4: "each carry their own copy of the resolver arms" | Both copies remain; post-#10081 the shared helpers (`wait_dev`, `luks_type`, `open_as`, `ensure_mount`, emit/fail) are also duplicated-but-pinned (D5), and only the stage has a format arm | Disposition scoped to the *resolver decision* duplication; helper duplication already posture-covered |
| epic residual: delete `inngest-verify-clean-10390.sh` | Already absent on main (retired by the inngest@4 upgrade PR); epic body still says "still owed" | Verify + record; ship phase posts the epic note/ticks the line |

## Technical Considerations

- **Attach topology.** Removing the volume removes it from the Phase-A create set and the Phase-B no-op set — the plan-shape guard's two modes are unaffected structurally (it admits rehearsal-scoped creates and grades the Phase-B delta as exactly the NIC); only the fixtures change.
- **Stranded-state edge.** If the rehearsal root's R2 state currently holds `hcloud_volume.rehearsal_inngest` (an incomplete teardown), the next Phase-A `additive` plan would carry a `delete` — which plan-shape *refuses* ("non-additive change"), correctly. The remediation is `terraform state rm` + a provider-side check, documented in the rehearsal runbook note; steady-state (teardown ran) shows no diff at all.
- **Ledger consistency.** `lint-encryption-posture.py` joins ledger rows to the `*.tf` census: deleting the TF resource without the row FAILs `unledgered store`-style checks in reverse; deleting both in one diff is the only consistent shape.
- **DR recipe correctness (verified anchors).** Stale `INNGEST_LUKS_ACTIVE_VOLUME_ID` → resolver refuses *before* the format arm (`reopen_pointer`/"not this host's volume"), so the pointer must be deleted first; the `rehearsal_*` allowlist is a rendered literal pinned by `_D6_HEAD` and the UNP5 assertions, so the DR PR carries its own pin updates; `inngest-host-replace` renders `inngest_luks_volume_id` from the TF resource id, so a new volume needs no template change.
- **Sensitive path.** `apps/web-platform/infra/**` matches preflight's `SENSITIVE_PATH_RE` — the User-Brand scope-out bullet is required and Observability Check 10 will run the declared probe.
- **NFR impacts.** Reliability (rehearsal fidelity preserved — the volume was never read, so removing it changes no behaviour the rehearsal measures), security (one fewer plaintext-exception audit row; the DR recipe preserves `unpointed_raw_refused` as a standing control), operability (runbook completeness). No performance, scaling, or data-model impact. No `soleur:architecture assess` needed — no NFR register entries move.

## Implementation Phases

### Phase 1 — Item 2: delete the unused rehearsal volume (FR-1..FR-4)

1. `rehearsal.tf`: delete `resource "hcloud_volume" "rehearsal_inngest"` and `resource "hcloud_volume_attachment" "rehearsal_inngest"`; rewrite the `# --- The two volumes ---` comment to describe the single LUKS volume (keeping the "RAW — the blkid signature IS the discriminator" rationale for `rehearsal_inngest_luks`).
2. `scripts/encryption-posture-ledger.json`: delete the `stores[]` row `"store": "hcloud_volume.rehearsal_inngest"` (with its `device_binding`, `at_rest`, `live_verification` and `exception` sub-blocks). Re-grep the whole file for `rehearsal_inngest\b` before staging — the issue said two rows; only one exists, and the grep proves it.
3. `tests/scripts/test-inngest-provision-plan-shape.sh`: remove `hcloud_volume.rehearsal_inngest:create` + `hcloud_volume_attachment.rehearsal_inngest:create` from `ADDITIVE_OK`; remove `hcloud_volume.rehearsal_inngest:no-op` from the Phase-B fixture; retarget the two `import=` refusal fixtures from `hcloud_volume.rehearsal_inngest` to `hcloud_volume.rehearsal_inngest_luks` (normalizing the synthesized `rehearsal_inngest_inngest_luks` spelling at the same time so fixtures mirror the real inventory).
4. `inngest-provision-rehearsal.md`: "two scratch volumes" → the one volume; add the stranded-state `state rm` remediation note.
5. Gates: `terraform validate`, `inngest-provision-rehearsal.test.sh`, `test-inngest-provision-plan-shape.sh`, `python3 scripts/lint-encryption-posture.py`.

### Phase 2 — Item 3: write the blank-`prd` DR record (FR-5)

Write into `inngest-luks-cutover-6894.md`, replacing the "needs a disaster-recovery procedure written when it is ever needed" sentence. **Recommended arm (assumed pending ruling):** a procedure headed "Blank `prd` volume bring-up (disaster recovery)":

1. *Preconditions* — the store is intentionally new (the sole-copy AOF is gone or deliberately abandoned; the refusal exists precisely because a blank device is otherwise indistinguishable from a damaged header). If replacing `hcloud_volume.inngest_redis_luks` in place, the ADR-282 two-step protection lift runs first in its own reviewed change.
2. Delete `INNGEST_LUKS_ACTIVE_VOLUME_ID` in `soleur-inngest/prd` — a stale pointer refuses at the resolver (`reopen_pointer` / "not this host's volume") before the format arm is ever reached.
3. A reviewed PR widens the `case '${inngest_doppler_config}' in rehearsal_*)` allowlist in `cloud-init-inngest.yml` to admit `prd` for the window (updating the `_D6_HEAD`/`UNP5` pins in the same diff); dispatch `apply_target=inngest-host-replace`.
4. Verify `SOLEUR_INNGEST_LUKS_STAGE` rows `luks_format` → `luks_open_fresh` → `mkfs` → `mount_luks` — never `unpointed_raw_refused`; Redis starts on the empty store.
5. A second reviewed PR reverts the allowlist; optionally re-write `INNGEST_LUKS_ACTIVE_VOLUME_ID` to the new volume id to restore the pinned-canonical invariant.
6. The section must also state what it deliberately is NOT: no standing flag, var, or apply target — a permanent blank-format path on `prd` re-opens the format-the-sole-copy hole the refusal exists to close.

**If the ruling is "decline":** the runbook instead gets a clearly-labelled decline naming the per-incident route (a reviewed emergency patch is still the only mechanism), which is strictly weaker — hence the assumed arm.

### Phase 3 — Item 4: record the resolver-duplication disposition (FR-6, FR-7)

**Recommended arm (assumed pending ruling):** accept the drift in writing. The runbook gains a short note naming: the two copies (`inngest-luks-open.sh` + runcmd stage), the shared decision (empty pointer → the rendered volume; `== LUKS_ID` → pointer arm; anything else → refuse), the deliberate asymmetries (reopen never formats — `reopen_not_luks`; reopen reports via `logger` pre-network while the stage tees to `$INNGEST_LUKS_DETAIL`; the stage distinguishes a non-numeric pointer first, the reopen folds it into `reopen_pointer`), and the drift bound (`inngest-redis-luks-loopback.test.sh` extracts and executes both copies verbatim; `inngest-redis-luks.test.sh` pins the arm literals; D5's pinned-duplication precedent). The ADR-142 addendum records items 3+4 (FR-7) in the same phase.

**If the ruling is "share":** extract the resolve decision into a `/usr/local/lib/` `write_files` entry sourced by both scripts (deliverable before `inngest-luks-open.service` runs — pre-network is fine, `write_files` precedes systemd), unify the refusal emit shapes or keep per-site emit adapters, update the loopback suite's two extraction points and the literal pins; the diff then also touches `cloud-init-inngest.yml` → re-run the #10243 overlap check.

## Files to Edit

1. `apps/web-platform/infra/inngest-provision-rehearsal/rehearsal.tf` — delete volume + attachment + comment rewrite (~30 lines)
2. `scripts/encryption-posture-ledger.json` — delete the `hcloud_volume.rehearsal_inngest` `stores[]` row (~20 lines)
3. `tests/scripts/test-inngest-provision-plan-shape.sh` — fixture updates (~8 lines)
4. `knowledge-base/engineering/operations/runbooks/inngest-provision-rehearsal.md` — volume count + stranded-state note (~4 lines)
5. `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md` — DR procedure + duplication-disposition note (~90 lines added)
6. `knowledge-base/engineering/architecture/decisions/ADR-142-inngest-redis-aof-zero-data-loss-luks-migration.md` — dated addendum (~30 lines added)

## Files to Create

None. (Pipeline artifacts — `tasks.md`, `decision-challenges.md` under `knowledge-base/project/specs/<branch>/` — are workflow records, not plan deliverables.)

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Item 3: shared standing mechanism (a `INNGEST_LUKS_ALLOW_BLANK_FORMAT` flag, a new var, or a dedicated DR apply target) | Rejected — buys no property the reviewed-patch recipe doesn't (a human must still authorize "intentionally blank"), and a permanent `prd` blank-format path re-opens the sole-copy-format hole `unpointed_raw_refused` closes |
| Item 3: explicit written decline | Kept as the ruling-dependent fallback — strictly weaker than the recipe (a decline still has to name the same per-incident route to be honest); the ADR already records the procedure as owed |
| Item 4: shared `/usr/local/lib/` resolver helper | Assumed-rejected pending ruling — the decision is frozen post-cutover, the loopback suite already executes both copies verbatim, and D5 set the pinned-duplication precedent; the helper costs host-rendered churn + two suites' extraction-point rewrites for a property already covered |
| Item 4: do nothing (no note) | Rejected — the issue explicitly requires sharing *or* written acceptance; silence leaves the divergence undocumented |
| Item 2: keep the volume (`lifecycle.ignore_changes` or comment-only) | Rejected — the resource costs a real Hetzner volume per dispatch, holds a stale plaintext-exception audit row, and was filed as removable the moment the scope-exclusion lifted |

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — the blast radius is a refused `inngest-provision-rehearsal.yml` plan-shape step or a red ledger lint/sentinel suite, all CI-surface-visible before any dispatch; the production inngest host is untouched (this root is dispatch-only, excluded from the per-merge apply by `apply-web-platform-infra.yml`'s path exclusion).
- **If this leaks, the user's [data / workflow / money] is exposed via:** no exposure vector — the deleted store was a scratch volume that never held data; the residual risk is a *stale audit claim* (ledger posture for a nonexistent store), bounded by the lint's tf-census join.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** infra/test/doc-only diff on a throwaway rehearsal root — no user-facing artifact, production service, or regulated-data surface changes; a broken landing is a refused CI plan, not a user-visible event.

*Scope-out override:* `threshold: none, reason: touches apps/web-platform/infra/ but only the dispatch-only rehearsal root (scratch Terraform, never applied to production) plus ledger/test/doc fixtures — no production host, credential, or user-data path is modified.`

## Infrastructure (IaC)

The change removes Terraform resources; nothing is provisioned manually. Required subsections:

### Terraform changes

- `apps/web-platform/infra/inngest-provision-rehearsal/rehearsal.tf` — delete `hcloud_volume.rehearsal_inngest` and `hcloud_volume_attachment.rehearsal_inngest`; rewrite the "two volumes" comment. No new resources, providers, or sensitive variables.

### Apply path

(a-variant) — this root is **dispatch-only**: `apply-web-platform-infra.yml` path-excludes it; it applies only inside `inngest-provision-rehearsal.yml` (Phase A create + Phase B NIC attach + always-teardown). The next rehearsal dispatch simply never creates the volume. No production apply, no `-replace`, no downtime — the volume is per-run scratch that never held data. Edge: if R2 state holds the resource from an incomplete teardown, the next Phase-A plan legitimately proposes its `delete`, which the `additive` plan-shape refuses — the documented remediation is `terraform state rm` plus a Hetzner-API existence check (rehearsal runbook step), not an exception to the guard.

### Host fan-out

No `terraform_data` SSH provisioners touched — not applicable.

### Distinctness / drift safeguards

Rehearsal-scoped root (`rehearsal_<runid>` non-inheriting Doppler environment, `soleur-inngest-rehearsal-<runid>` names, per-run R2 state key `web-platform/inngest-provision-rehearsal/terraform.tfstate`); zero overlap with production addresses — the sentinel suite's `\.rehearsal\b` name census re-verifies this.

### Vendor-tier reality check

No new vendor resources; Hetzner volume creation is per-dispatch and unaffected by tier limits.

## Observability

```yaml
liveness_signal:
  what: "Next inngest-provision-rehearsal.yml dispatch: phase-A plan-shape verdict (additive) + always-teardown orphan sweep (no rehearsal-prefixed volume survives)"
  cadence: "per-dispatch (workflow_dispatch; dry_run default true)"
  alert_target: "GitHub Actions job failure + ::error:: annotations"
  configured_in: ".github/workflows/inngest-provision-rehearsal.yml (PLAN_SHAPE step, teardown orphan assertion)"
error_reporting:
  destination: "workflow step output — ::error:: lines from scripts/inngest-provision-plan-shape.sh; local suite FAIL lines"
  fail_loud: "scripts/inngest-provision-plan-shape.sh exits 1 with '::error::plan-shape (additive): … is not admitted'; lint-encryption-posture.py prints 'FAIL: unledgered store …' and exits 1"
failure_modes:
  - mode: "ledger row deleted but TF resource left (or vice versa)"
    detection: "lint-encryption-posture.py joins ledger rows to the *.tf census — FAIL on the mismatched side"
    alert_route: "PR-time CI gate (required check)"
  - mode: "stale fixture references hcloud_volume.rehearsal_inngest"
    detection: "tests/scripts/test-inngest-provision-plan-shape.sh red in CI; harmless-to-dispatch (fixtures are synthesized) but caught pre-merge"
    alert_route: "PR-time CI gate"
  - mode: "R2 state holds the resource (incomplete prior teardown) — next phase-A plan proposes a delete"
    detection: "plan-shape additive mode refuses the delete with '::error:: … non-additive change(s)'"
    alert_route: "workflow run failure at the plan step — operator-visible"
logs:
  where: "workflow run logs (GitHub Actions); suite TAP output locally"
  retention: "GitHub default; artifact evidence per-dispatch via upload-artifact"
discoverability_test:
  command: grep -c 'resource "hcloud_volume"' apps/web-platform/infra/inngest-provision-rehearsal/rehearsal.tf
  expected_output: "1"
```

## Encryption Posture

```yaml
at_rest:
  - store: hcloud_volume.rehearsal_inngest (REMOVED by this change)
    mechanism: "was plaintext-exception — the resource and its stores[] row are deleted together; no posture remains to declare"
    evidence: "deletion — git grep 'rehearsal_inngest' over rehearsal.tf returns 0 post-change"
    defends_against: "n/a — store ceases to exist; its plaintext-exception audit surface evaporates rather than being renewed"
    does_not_defend: "n/a"
    disclosed_as: "n/a — the row is deleted, not disclosed"
    live_verification: "unavailable:n/a — scratch volume, destroyed per-run even before removal"
  - store: hcloud_volume.rehearsal_inngest_luks (unchanged)
    mechanism: luks
    evidence: "apps/web-platform/infra/cloud-init-inngest.yml cryptsetup anchors (existing ledger row, untouched)"
    defends_against: "a seized/detached rehearsal scratch volume"
    does_not_defend: "runtime reads while the mapper is open"
    disclosed_as: "not-publicly-claimed"
    live_verification: "unavailable:rehearsal-scoped, per-dispatch observation only"
in_transit: []  # no new cross-component connection; none modified
exception:      # none — the plaintext-exception row is DELETED, not renewed or replaced
```

## Architecture Decision (ADR/C4)

### ADR

**Amend** `knowledge-base/engineering/architecture/decisions/ADR-142-inngest-redis-aof-zero-data-loss-luks-migration.md` with a dated addendum recording two dispositions in the issue's named lineage: (a) the blank-`prd`-volume bring-up route — the reviewed one-time allowlist patch recipe now written into the cutover runbook, or a recorded decline if the parent rules that way; (b) the resolver-duplication decision — deliberate two-copy resolver with named asymmetries and the loopback suite as the drift bound (or the shared-helper design if the ruling flips item 4).

### C4 views

**No C4 impact.** Read all three model files (`model.c4`, `views.c4`, `spec.c4`). Enumeration checked: (a) external human actors — none new (the DR procedure serves the existing operator role); (b) external systems/vendors — none new (Hetzner and Doppler are already modeled); (c) containers/data-stores — the deleted volume is a throwaway CI artifact never modeled; `inngest` and `inngestRedis` descriptions were re-read and nothing in them is falsified (they correctly describe only the production LUKS store); (d) actor↔surface relationships — unchanged. No element, edge, or `view include` needs an edit; `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` unaffected.

### Sequencing

The addendum is authored in this PR describing the dispositions as decided — no `adopting` staging needed (the DR recipe is a written procedure, not a code path that takes effect later).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "`inngest-luks-cutover.sh` no longer names the plaintext volume, staging mapper or `/mnt/data-luks`, in a new image whose pin is bumped" [issue #10112 AC] | AC9 — verify-only (already satisfied on main; trio deleted, not just vocabulary-stripped) | mapped — satisfied-upstream |
| 2 | "`hcloud_volume.rehearsal_inngest` and its attachment are removed, with the ledger rows, plan-shape fixtures and rehearsal test updated" [issue #10112 AC] | FR-1..FR-4 / Phase 1 / Files-to-Edit #1-4 | mapped |
| 3 | "A disaster-recovery procedure for a blank `prd` volume exists in the cutover runbook, or is explicitly declined with a reason" [issue #10112 AC] | FR-5 / Phase 2 / Files-to-Edit #5 (+ ADR addendum #6) | mapped |
| 4 | "The duplicated resolver arms are either shared or the drift risk is accepted in writing" [issue #10112 AC] | FR-6 / Phase 3 / Files-to-Edit #5-6 | mapped |
| 5 | "delete scripts/followthroughs/inngest-verify-clean-10390.sh on the next inngest PR" [brief / epic #10390 log] | AC8 — verify-only (already absent on main; ship posts the epic note) | mapped — satisfied-upstream |
| 6 | "the resume brief for this run explicitly lists the unused rehearsal volume in scope, which is the lift; record that provenance in the plan's decision-challenges" [brief] | decision-challenges.md row (operator scope) + this provenance note | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| FR-1 rehearsal.tf deletion | "`hcloud_volume.rehearsal_inngest` and its attachment are removed" | asked |
| FR-2 ledger row deletion | "with the ledger rows" | asked |
| FR-3 plan-shape fixture update | "plan-shape fixtures" | asked |
| FR-4 rehearsal-runbook volume-count fix | "the rehearsal test updated" + attach-topology consequence | inferred — justification: the runbook claims "two scratch volumes"; leaving it falsifies the doc the next dispatcher reads |
| FR-5 DR procedure (or decline) | "a written disaster-recovery procedure is needed (or an explicit decision to decline one)" | asked |
| FR-6 resolver-duplication disposition | "either shared or the drift risk is accepted in writing" | asked |
| FR-7 ADR-142 addendum | "items 3 and 4 as design notes in the ADR-142 lineage" | asked |
| AC8/AC9 verification ACs | "verify what actually remains on main before scoping" + "confirm in the plan and tick the epic checkbox if present" | asked |

### Split Assessment

- Subsystems touched: 4 — `apps/web-platform` (infra), `scripts` (ledger), `tests` (fixtures), `knowledge-base` (runbooks, ADR)
- Planned files: 6 | Estimated changed lines: ~180 (≈60 removed, ≈120 added — mostly the DR procedure + addendum)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the root count is structural, not scope growth: the ledger row, its fixture, its doc and its ADR record must move atomically or the tf-census lint and suite greens break at intermediate commits; ~180 lines is far under the line threshold and all three items close one issue.

## Acceptance Criteria

- [ ] AC1: `git grep -nE 'hcloud_(volume|volume_attachment)"[[:space:]]+"rehearsal_inngest"' -- apps/web-platform/infra/inngest-provision-rehearsal/` returns zero hits (the `rehearsal_inngest_luks` resources remain — asserted by `grep -c 'resource "hcloud_volume"'` == 1).
- [ ] AC2: `scripts/encryption-posture-ledger.json` contains no `hcloud_volume.rehearsal_inngest` reference; `python3 scripts/lint-encryption-posture.py` exits 0.
- [ ] AC3: `bash tests/scripts/test-inngest-provision-plan-shape.sh` passes with the trimmed fixture set, including the two retargeted import-refusal cases.
- [ ] AC4: `bash apps/web-platform/infra/inngest-provision-rehearsal.test.sh` passes; `terraform -chdir=apps/web-platform/infra/inngest-provision-rehearsal init -backend=false -lockfile=readonly && terraform -chdir=apps/web-platform/infra/inngest-provision-rehearsal validate` clean (mirrors the infra-validation job).
- [ ] AC5: `inngest-luks-cutover-6894.md` carries a blank-`prd`-volume bring-up procedure (or an explicitly-labelled decline with reason) in place of the "needs a written procedure when it is ever needed" placeholder — naming the pointer deletion, the reviewed allowlist-patch window, the host-replace dispatch, the `luks_format`/`mount_luks` verification rows, and the revert step. The section must state plainly that the procedure is verified statically, not drilled (CTO dissent caveat, 2026-11-06).
- [ ] AC6: the resolver-duplication disposition is recorded in `inngest-luks-cutover-6894.md` and the ADR-142 addendum — either the shared helper is built (ruling-dependent) or the accepted drift names its asymmetries and the loopback-suite bound.
- [ ] AC7: `inngest-provision-rehearsal.md` no longer claims "two scratch volumes"; the stranded-state edge (`state rm` remediation) is documented.
- [ ] AC8: PR body records verification that `scripts/followthroughs/inngest-verify-clean-10390.sh` is absent on main and the epic #10390 residual line is annotated (comment or edit by ship phase).
- [ ] AC9: PR body records verification that no `inngest-luks-cutover.{sh,service,timer}` exists on main (item 1 closed upstream); `Closes #10112` in the PR body.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change. Product mechanical UI-surface override checked: no `*.tsx`/`app/**/page.tsx`/`layout.tsx` in Files to Edit or Create — override does not fire; tier is NONE.

## Test Scenarios

- Given `rehearsal.tf` post-deletion, when `inngest-provision-rehearsal.test.sh` runs, then the `\.rehearsal\b` name census and all pins still pass (`unit`/fixture).
- Given the trimmed `ADDITIVE_OK`, when the synthesized Phase-A plan feeds `inngest-provision-plan-shape.sh`, then it is admitted; when a plan carries `hcloud_volume.rehearsal_inngest_luks:no-op:import=<id>` in either mode, then it is refused with "the plan IMPORTS" (`unit`).
- Given the ledger minus the row, when `lint-encryption-posture.py` runs, then the tf-census join finds no unledgered store and no orphan row (`integration`-adjacent lint, runs pre-merge).
- Given the volume resource re-added to `rehearsal.tf` *without* a ledger row, when the lint runs, then it FAILs naming the unledgered store — the regression property for this deletion (`unit` lint behavior, asserted by existing lint suite shape).
- Given the runbook diff, when `markdownlint`/docs checks run, then the new DR section passes and names only mechanisms verified on main (`unpointed_raw_refused` allowlist, `INNGEST_LUKS_ACTIVE_VOLUME_ID`, `apply_target=inngest-host-replace`).
- Given a ruling flip on item 4, when the shared-helper design is chosen instead, then `inngest-redis-luks-loopback.test.sh` must still execute both readers verbatim — the AC6 conditional (`unit`, conditional scope).

## Success Metrics

- Zero `rehearsal_inngest` (word-boundary, non-`_luks`) references outside `**/archive/**` and planning artifacts; `python3 scripts/lint-encryption-posture.py` exits 0; both named suites green; `terraform validate` clean on the rehearsal root.
- Issue #10112 closes with all three remaining ACs evidenced in the PR body; epic #10390 gains the verification note and stays open.

## Dependencies & Risks

- **Stranded-state edge (documented, not blocking):** a rehearsal dispatch with the resource still in R2 state gets a refused additive plan — remediation `terraform state rm` + Hetzner-API existence check is in the runbook note.
- **Ruling flips:** if the parent rules "decline" on item 3 the runbook gets the decline text (strictly smaller diff); if it rules "share" on item 4 the diff grows by a `write_files` lib + source lines + suite pins in `cloud-init-inngest.yml` — re-run the affected derivation and re-check the #10243 file overlap in that case.
- **Rebase churn:** expect encryption-ledger/legal-TSV/generated-manifest conflicts on rebase — union-merge appended records, `regenerate-shard-manifest.py --incremental --write`, re-pin `LEGAL_DOC_SHAS` on canonical docs (arc process reminder).
- **Ship-time:** never push while `test-all` is queued on the advisory lock; `deploy-script-tests` GuardA may be expected-red on main pending the carrier bake — distinguish before treating as real-red.
- **Fixture-name drift:** the suite's `rehearsal_inngest_inngest_luks` fixture doesn't match the real resource name — normalize to `hcloud_volume.rehearsal_inngest_luks` at work time so the fixtures mirror the real inventory.

## Deepen-Plan Gate Record

Sequential-fallback run (2026-11-06): Phase 4.6 user-brand PASS (threshold none + sensitive-path scope-out bullet); 4.7 observability PASS (all fields populated; `discoverability_test.command` first token `grep` allowlisted, zero shell-active bytes, literal `expected_output`); 4.8 PAT-scan PASS (no GitHub-write token/variable introduced); 4.9 UI-wireframe SKIP (no UI surface); 4.10 encryption posture PASS (populated, removal recorded); 4.11 guard contract assessed-SKIP (no new guard/gate/lint authored — fixture-inventory update to the existing plan-shape suite only; `lint-guard-contract.py` detection does not fire); 4.12 scope check PASS (exactly one unfenced section, all asks mapped, no BLOCKED marker); 4.13 task design SKIP (no new autonomous-task surface); 4.4 precedent-diff SKIP (no scheduled job); 4.5 network-outage SKIP (no trigger tokens); 4.55 downtime/cutover SKIP (diff induces no production-offline operation — the DR recipe's host-replace is a documented pre-existing dispatch path). Sharp-edges pass applied: probe command runs clean and prints the expected literal.

## Open Code-Review Overlap

- `#10112` — this plan's own issue (the overlap query returns it because its body names the files).
- `#10243` (nft comment correction on PR 8945) — touches `cloud-init-inngest.yml`. **Disposition: acknowledge.** This plan does not edit `cloud-init-inngest.yml` under the assumed item-4 arm (accept-in-writing); if the ruling flips to "share", re-run the overlap check before editing that file.

## References & Research

- Issue: #10112 (trigger: PR #10081, merged 2026-10-15); epic #10390 (stays open).
- ADRs: ADR-142 (+ addenda 2026-10-12/13/15), ADR-199 (addendum 2026-10-14), ADR-282, ADR-140, ADR-279.
- Enforcing gates: `scripts/lint-encryption-posture.py`, `scripts/inngest-provision-plan-shape.sh`, `apps/web-platform/infra/inngest-provision-rehearsal.test.sh`, `tests/scripts/test-inngest-provision-plan-shape.sh`, `apps/web-platform/infra/inngest-redis-luks{,-loopback}.test.sh`.
- Similar implementation: `tests/scripts/test-git-data-rung2-plan-shape.sh` (the plan-shape suite pattern this file mirrors).
- Prior pipeline state: `knowledge-base/project/specs/archive/20261105-092601-feat-one-shot-10390-ci-hygiene-batch/session-state.md`.
