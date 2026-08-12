---
title: "chore: flip ADR-184 adopting → accepted on the observed first PASS, and retire the not-yet-delivered claim class"
date: 2026-08-12
slug: chore-adr-184-status-flip-accepted
branch: feat-one-shot-7455-adr-184-accepted
issue: 7455
closes: []
lane: cross-domain
type: chore
priority: p2-medium
domain: engineering
brand_survival_threshold: none
---

## Overview

ADR-184 ships at `status: adopting`. Its own `## Status flip condition` section names the flip
trigger as the **first PASS** of `scripts/followthroughs/zot-log-channel-7440.sh`. That PASS was
observed on 2026-08-12 at 21:03:51Z.

This plan flips the status and retires the claim class that the flip falsifies. Three artifacts
outside the ADR assert, in present tense, that the zot container-log channel has **not** been
delivered and that zero rows is the expected reading. That was true when written and is now false —
and in one case (the incident runbook) the stale claim actively instructs a reader to interpret a
real fault as normal.

The deliverable is a status flip plus a bounded coherence sweep. No behaviour changes.

## Research Insights

### Premise Validation (Phase 0.6)

| Premise (as given) | Verified how | Verdict |
|---|---|---|
| ADR-184 is at `status: adopting` | `grep '^status:'` on fresh `origin/main` | **HOLDS** — line 3 |
| The probe PASSed | Ran the probe against live Better Stack; exit 0 | **HOLDS** — `envelope=37 control=7`, floor 7 |
| #7455 is OPEN | `gh issue view 7455 --json state` | **HOLDS** — OPEN, 0 comments |
| The flip condition is a first PASS | Read ADR `## Status flip condition` | **HOLDS** — verbatim |
| `related_specs:` frontmatter path | `ls` on the cited path | **STALE** — path does not exist; spec was archived to `specs/archive/20260812-194844-feat-one-shot-7440-zot-log-shipping/`. `related_plans:` was swept to its archive path; `related_specs:` was not |
| Delivery would ride #7287 step 6 | `gh issue view 7287` (CLOSED) + its closing comment | **FALSIFIED** — the host was replaced by the atomic `registry-luks-recut` on 2026-08-10T22:08Z, ~45h **before** the shipper merged (2026-08-12T19:38Z). Delivery required a separate `registry-host-replace`, run 31639782781, completed 2026-08-12T20:54:12Z |

The last row is the load-bearing one: it is why three artifacts still describe delivery as pending.

### Property List (Phase 0.6b)

1. ADR-184's recorded status matches its own stated flip condition and the observed evidence.
2. A reader of any live artifact is not told the channel is undelivered when it is delivered.
3. The evidence for the flip is recoverable from the ADR itself, not only from a chat transcript.
4. Every `knowledge-base/` path cited in ADR-184's frontmatter resolves.

### Cut List (Phase 0.6b)

| Mechanism considered | Property it would buy | Why cut |
|---|---|---|
| A new "flip evidence" file or ledger | 3 | **Cut.** ADR-044's flip precedent (`dbf0e89d0`) appends an `## Amendment <date>` section inside the ADR. That mechanism already exists and is the repo's convention |
| An ADR status index / README | 1 | **Cut.** `ls knowledge-base/engineering/architecture/decisions/` returns only `ADR-*.md` — there is **no** index, README or ledger recording ADR status. Nothing to update |
| A guard asserting status matches probe state | 1 | **Cut.** No property in the list needs it; the probe already fails visibly, and a guard over 8 `adopting` ADRs is machinery the ask did not name |

### Precedent (the convention this plan follows)

`git log -S"status: adopting"` finds two completed flips: **ADR-044** (`dbf0e89d0`) and **ADR-030**.
The ADR-044 diff is the template:

```diff
-status: adopting
+status: accepted
```
plus a `+48`-line appended section opening:
```markdown
## Amendment 2026-06-18 — PR-2b column DROP (arc CLOSED)

**Status flip:** `adopting → accepted`. ...
```

So the convention is **flip the frontmatter and append a dated amendment section that records why** —
not an in-place rewrite of the superseded prose. This plan follows that shape exactly, which also
preserves ADR-184's §6/§7 as the historical record they are.

### The not-yet-delivered claim class — bounded by grep

`git grep -nl "step-6 registry-host-replace\|merged inert\|INERT UNTIL A PROVISIONING"` over
`knowledge-base/ apps/ scripts/`, excluding `plans/archive` and `specs/archive`, returns **exactly
four** files:

| File | Disposition |
|---|---|
| `knowledge-base/engineering/architecture/diagrams/model.c4` | **Fix** — `zotRegistry -> betterstack` edge |
| `knowledge-base/engineering/architecture/diagrams/model.likec4.json` | **Regenerate** — generated artifact, byte-diffed by CI |
| `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` | **Fix** — the ⚠️ warning box |
| `scripts/followthroughs/zot-log-channel-7440.sh` | **Acknowledge, do not touch** — see Risks |

Archived plan/spec artifacts legitimately retain the old claim as a point-in-time record and are
excluded by construction, per the path-rename-sweep carve-out convention.

### Mechanical coupling discovered (changes this plan's shape)

`plugins/soleur/test/c4-model-freshness.test.sh` renders the `.c4` sources with the pinned
`likec4@1.50.0` CLI and **byte-diffs** the committed `model.likec4.json`. Any edit to `model.c4`
therefore *requires* regenerating the JSON or CI goes red. The test's own failure message names the
remedy: `bash scripts/regenerate-c4-model.sh` (verified present, mode `-rwxrwxr-x`).

### Institutional learnings applied

- `cq-cite-content-anchor-not-line-number` — every edit below is anchored on a quoted string, not a
  line number, because three of the four files are long and actively edited.
- `hr-no-dashboard-eyeball-pull-data-yourself` — the PASS evidence was self-pulled via
  `scripts/betterstack-query.sh`, not requested from the operator.
- The plan skill's Sharp Edge on Glob-verifying `knowledge-base/` citations is what surfaced the
  broken `related_specs:` path.

### CLAUDE.md / AGENTS conventions in play

`wg-architecture-decision-is-a-plan-deliverable` (the ADR edit is the deliverable, not a follow-up),
`cq-cite-content-anchor-not-line-number`, `hr-always-read-a-file-before-editing-it` (ADR-184 read in
full, 328 lines).

## Research Reconciliation — Spec vs. Codebase

| Claim as given to this plan | Codebase reality | Plan response |
|---|---|---|
| "status flip plus whatever ADR conventions require (index, README or ledger)" | No ADR index/README/ledger exists | Scope reduces to the ADR + the claim-class sweep |
| "Do NOT touch the shipper code, the cloud-init, or the probe" | The probe carries the stale claim class | Honoured — recorded as an explicit Acknowledge with rationale, not silently skipped |
| Implied: only the ADR is stale | Three other live artifacts carry the falsified claim | Sweep widened to the grep-bounded set of 3 (+1 generated) |

## Open Code-Review Overlap

**None.** 64 open `code-review` issues queried via `gh issue list --label code-review --state open
--limit 200`; a `jq --arg path` containment check against all three edited paths returned zero
matches for each.

## User-Brand Impact

**If this lands broken, the user experiences:** an incident runbook that tells them a dark log
channel is expected. The `betterstack-log-query.md` warning box currently reads *"every query in
this section correctly returns zero rows, and that zero is a not-yet, not a fault."* Left as-is,
the next operator debugging a registry incident reads a genuine channel outage as normal and stops
investigating.

**If this leaks, the user's data/workflow/money is exposed via:** no new exposure surface. This
plan adds no store, no connection, no credential, and no processing activity. The channel it
documents was already delivered and already disclosed (counsel review 2026-08-12 recorded PA-8
recipients and TOMs as DISCHARGED for this emitter).

**Brand-survival threshold:** `none`

Rationale for `none`: docs-only, no runtime surface, no regulated-data path, no user-facing artifact.
The runbook staleness above is an operator-facing correctness issue, not a user-facing one — which is
precisely why it is fixed here rather than deferred.

## Implementation Phases

### Phase 1 — ADR-184: the flip and its evidence

1.1 Flip frontmatter `status: adopting` → `status: accepted`.

1.2 Repair the frontmatter `related_specs:` entry to the archived path
    `knowledge-base/project/specs/archive/20260812-194844-feat-one-shot-7440-zot-log-shipping/session-state.md`,
    matching the already-correct `related_plans:` entry.

1.3 Add `7455` to the frontmatter `related:` list (currently `[7440]`) — the tracker that carried
    the flip condition.

1.4 Append `## Amendment 2026-08-12 — first PASS observed (status ACCEPTED)`, following the ADR-044
    shape. It records, in this order:
    - **Status flip:** `adopting → accepted`, and the probe output that triggered it (verbatim
      counts: `envelope=37 control=7 gc_start=1 gc_done=1 gc_blobs=1 patch_upload=0 dropped_rows=2`,
      window 30m, floor 7, `boot_marker(1)`, 27/37 rows carrying `zotregistry.dev/zot/v2/pkg/api`).
    - **What §6 and §7 got wrong, and why they are preserved rather than rewritten.** §6 says *"a
      step-6 `registry-host-replace` is the pending event this change rides"* and §7 says *"the
      rider is recorded on the open zot-pin ordered path"*. Delivery did **not** ride step 6: the
      ordered path's host replace had already fired atomically inside `registry-luks-recut` on
      2026-08-10T22:08Z, ~45 hours before this shipper merged, so the change was inert on a host
      born before it existed. Delivery took a **separate** `registry-host-replace`
      (run 31639782781, completed 2026-08-12T20:54:12Z).
    - **The generalisable lesson:** a rider recorded against a pending vehicle is only valid while
      that vehicle is still pending. Nothing detected that the vehicle had departed; the probe
      correctly reported `not_delivered` throughout and would have done so for 90 days.
    - **The boot-id transition** `bc135d5b-…` → `93c52405-…`, superseding §6's cited boot.
    - **First operational reading of the new counter:** `dropped_rows=2` of 37 on the first window —
      comfortably clear of the floor of 7, most likely startup backlog, recorded because it is the
      first real reading rather than because it is alarming.

### Phase 2 — Retire the falsified claim in the live runbook

2.1 In `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`, replace the
    warning box anchored on `**⚠️ THIS CHANNEL IS LIVE ONLY AFTER DELIVERY.` The replacement states
    the channel is **live as of 2026-08-12**, that zero rows is now a **fault** rather than a
    not-yet, and keeps the pointer to the enrolled probe as the first diagnostic. This inverts the
    box's operational advice, which is the entire point of the edit.

### Phase 3 — C4 coherence and regeneration

3.1 In `model.c4`, correct the trailing clause of the `zotRegistry -> betterstack` edge description
    anchored on `A host-side change is still INERT UNTIL A PROVISIONING EVENT`. Record that
    delivery occurred on 2026-08-12 via a dedicated `registry-host-replace` — explicitly **not** the
    step-6 event the clause names — and that the cloud-init-only inertness rule itself still holds
    for *future* changes. Preserve the existing RETRACTED/CORRECTED annotation style of the file.

3.2 Run `bash scripts/regenerate-c4-model.sh` and commit the updated `model.likec4.json`.

3.3 Verify with `bash plugins/soleur/test/c4-model-freshness.test.sh`.

## Files to Edit

| File | Change |
|---|---|
| `knowledge-base/engineering/architecture/decisions/ADR-184-registry-host-container-log-shipper.md` | Status flip, 2 frontmatter repairs, appended amendment section |
| `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` | Invert the ⚠️ delivery warning box |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | Correct the `zotRegistry -> betterstack` delivery clause |
| `knowledge-base/engineering/architecture/diagrams/model.likec4.json` | **Regenerated**, not hand-edited |

## Files to Create

None.

## Acceptance Criteria

### Pre-merge (PR)

1. `grep -c '^status: accepted' <ADR-184>` returns `1`; `grep -c '^status: adopting' <ADR-184>` returns `0`.
2. The path in ADR-184's `related_specs:` resolves: `test -f "$(awk '/^related_specs:/{getline; sub(/^ *- */,""); print; exit}' <ADR-184>)"` exits 0.
3. ADR-184 contains a heading matching `^## Amendment 2026-08-12`.
4. That amendment section contains the literal `envelope=37` and the literal `31639782781`.
5. `grep -c 'THIS CHANNEL IS LIVE ONLY AFTER DELIVERY' <runbook>` returns `0`.
6. The runbook's replacement box asserts the fault reading — `grep -c 'zero rows' <runbook>` ≥ 1 **and** the surrounding box no longer contains the string `not-yet, not a fault`.
7. `git grep -c 'INERT UNTIL A PROVISIONING EVENT' -- knowledge-base/engineering/architecture/diagrams/model.c4` returns `0`.
8. `bash plugins/soleur/test/c4-model-freshness.test.sh` exits 0 (this is the authority; it byte-diffs the regenerated JSON against a fresh render).
9. The full-suite gate runs at its usual point in `/work`; no suite regresses.
10. No file under `apps/web-platform/infra/`, `scripts/followthroughs/`, or `.tf` appears in `git diff origin/main...HEAD --name-only`.

### Post-merge

None. #7455 is closed by the scheduled follow-through sweeper on the probe's exit 0, which also
posts the PASS evidence; this PR deliberately does not race it.

## Architecture Decision (ADR/C4)

### ADR

**ADR-184**, amended in place — this plan *is* the ADR deliverable, not a follow-up. No new ADR and
no new ordinal, so the ordinal-collision gate does not apply.

### C4 views

**Container view — corrected, not extended.** The C4 completeness mandate was satisfied by reading
all three model files (`model.c4`, `views.c4`, `spec.c4`) rather than grepping for the feature noun.
Enumeration:

- **External human actors:** none introduced or changed by this flip.
- **External systems:** `betterstack` — already modelled, already carries the `SOLEUR_ZOT_LOG`
  channel (#7444 updated `model.c4` in the same commit, `4 ++--`). No new element needed.
- **Containers / data stores:** `zotRegistry` — already modelled.
- **Access relationships:** the `zotRegistry -> betterstack` edge already exists and already
  describes the shipper. What is falsified is only its **delivery-status clause**, which is the
  Phase 3.1 correction.

So the C4 work is a description correctness fix, not a modelling gap — and it is named here rather
than concluded as "no C4 impact", because a clause in that description is measurably false.

### Sequencing

None. Nothing here is soak-gated; the soak already elapsed and produced the PASS this plan records.

## Domain Review

**Domains relevant:** engineering

Assessed inline across all 8 domains rather than by spawning domain-leader agents — see
*Deviations* below.

### Engineering

**Status:** reviewed
**Assessment:** Docs + generated-artifact change. The only mechanical risk is the `model.likec4.json`
byte-diff coupling, which has a named regeneration script and a CI test that is the authority on
success. No runtime, schema, or infrastructure surface.

### Product/UX Gate

Not applicable. The mechanical UI-surface override was evaluated against `## Files to Edit`: no path
matches the UI-surface term list or glob superset (no `components/**/*.tsx`, no `app/**/page.tsx`,
no `app/**/layout.tsx`). Product tier resolves to **NONE**.

### Legal

**Not relevant — verified, not assumed.** ADR-184 is cited by `article-30-register.md`,
`compliance-posture.md` and `legal/audits/2026-08-counsel-review-7440.md`, so this was checked rather
than skipped. Those citations reference the shipper's *existence* as a non-Vector emitter (PA-8
recipients + TOMs, recorded **DISCHARGED** by the 2026-08-12 counsel review) and are independent of
the ADR's status field. A grep for the not-yet-delivered claim class across the legal corpus returned
only unrelated Sentry/Hetzner rows.

## Test Scenarios

1. **Status flip is machine-readable.** `grep '^status:' <ADR-184>` → `status: accepted`.
2. **Broken citation is repaired.** The `related_specs:` path resolves on disk (AC2). Regression
   guard for the archival sweep that missed it.
3. **C4 regeneration is in sync.** `bash plugins/soleur/test/c4-model-freshness.test.sh` → PASS.
   Negative control: hand-editing `model.c4` without regenerating must fail this test — that is the
   coupling being relied upon, and its failure message names the fix.
4. **The claim-class sweep is complete.** Re-run the bounding grep
   (`git grep -nl "step-6 registry-host-replace\|merged inert\|INERT UNTIL A PROVISIONING"` over
   `knowledge-base/ apps/ scripts/`, excluding both archive trees).

   **[Amended 2026-08-12 during /work — the original expectation was wrong.]** This scenario
   originally read "expected survivors: exactly `scripts/followthroughs/zot-log-channel-7440.sh`".
   That was authored before the retraction wording existed, and a *file-level* grep structurally
   cannot tell a live claim from prose that QUOTES the claim it retracts — so the correct check is
   line-level inspection of each survivor, not a survivor count. Measured result: **6 files, zero
   live stale claims** —

   | Survivor | What matched | Verdict |
   |---|---|---|
   | `model.c4`, `model.likec4.json` | inside the `is RETRACTED 2026-08-12 (#7455)` sentence | correct — the file's own annotation style |
   | `betterstack-log-query.md` | `was **merged inert**`, followed immediately by the delivery timestamp | correct — true past tense |
   | this plan, this `tasks.md` | the feature's own planning artifacts | documented carve-out |
   | `scripts/followthroughs/zot-log-channel-7440.sh` | operator-excluded probe | documented Acknowledge |

   This is the inverse of the known "grep assertion false-matches its own comments" class: a
   *correction* sweep false-fires on the correction's own quotation of what it corrected.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| `regenerate-c4-model.sh` cannot run locally (no network for `npx -y likec4@1.50.0`) | The freshness test's remedy line is the documented path; if the pinned CLI cannot be fetched, **drop Phase 3 entirely** rather than hand-editing the JSON. A hand-edited `model.likec4.json` cannot be byte-identical to a fresh render and would red CI. Phases 1–2 stand alone and carry the operator-facing value |
| Editing the enrolled probe would disturb a live follow-through | Not edited. Its header states ADR-184 *shipped at* `adopting`, which stays true as a historical statement, and the sweeper only lists `--state open`, so the probe goes dormant when #7455 closes |
| The PR races the sweeper and double-closes #7455 | `closes: []` — no closing keyword anywhere in the PR body. `Ref #7455` only |
| `model.c4` carries a *second*, unrelated staleness | Real but out of scope — see Open Questions |

## Alternatives Considered

| Alternative | Verdict | Reason |
|---|---|---|
| Flip `status:` only, change nothing else | **Rejected** | Leaves an ADR that reads `accepted` while its own §6/§7 call delivery pending, and leaves a runbook that tells an incident reader a dark channel is expected |
| Rewrite §6/§7 in place to remove the falsified claims | **Rejected** | Contradicts the ADR-044 precedent and destroys the historical record. The repo's convention is an appended dated amendment; ADR-184 itself argues at length for preserving superseded reasoning with an explicit retraction rather than deleting it |
| Also close #7455 from this PR | **Rejected** | The sweeper closes it on exit 0 and posts the PASS evidence as it does. Racing it produces a close with strictly less evidence attached |
| Fold in the `model.c4` zot-image-pin staleness | **Rejected — deferred** | Different subsystem (image pin, not log delivery), created by #7287's recut rather than by this flip. Bundling it widens the review surface of a status-flip PR. See Open Questions |
| Hand-edit `model.likec4.json` | **Rejected** | It is byte-diffed against a fresh render; a hand edit cannot pass |

## Open Questions / Follow-ups

**One follow-up issue to file** (not folded in, per the Alternatives table):

`model.c4`'s `zotRegistry` element description asserts *"the LIVE host still runs v2.1.2 and will
until the registry-host-replace apply fires (#7287)"*. That is now false — and the datum settling it
is already measured, so the follow-up is cheap and fully specified: the live `SOLEUR_ZOT_DISK` rows
report `zot_image_digest=95a837a0afac`, which matches the `v2.1.20@sha256:95a837a0afac…` pin quoted
in ADR-184 §3. The live host runs the pinned image. Closing that issue also needs a
`regenerate-c4-model.sh` run, so it should be batched with any other `model.c4` correction rather
than shipped alone.

## Deviations from the plan skill (declared)

This session carries an explicit instruction not to spawn agents unless the operator requests them.
Four plan phases that normally delegate were therefore run **inline** rather than skipped:

| Phase | Normally | Here |
|---|---|---|
| 1.1 research fan-out | `repo-research-analyst` + `learnings-researcher` | Inline greps; findings in Research Insights |
| 1.5 / 1.5b discovery | `agent-finder`, `functional-discovery` | Skipped — no new stack, no new capability |
| 2.5 domain sweep | 8 domain-leader agents | Inline 8-domain semantic sweep, recorded above |
| 3 / 4.5 / plan-review | `spec-flow-analyzer`, advisor consult, review panel | Not run |

The cost of the deviation is concentrated in plan-review: no independent panel has challenged this
plan's scope calls, in particular the decision to widen from "flip the status" to "flip the status
and sweep the claim class". That widening is defended by the grep bound (exactly four files, one
excluded by operator instruction, one generated) and is stated here so it can be cut rather than
discovered.

Phase 0.7's skeleton checkpoint was written as a complete plan rather than a stub, because the
research it exists to protect ran inline and had already finished — there was no fan-out to lose.
