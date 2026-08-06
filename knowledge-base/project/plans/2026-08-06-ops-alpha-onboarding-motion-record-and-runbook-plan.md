---
title: "Alpha onboarding motion — validation record + per-tester runbook"
type: ops
issue: "#7329"
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
date: 2026-08-06
branch: feat-alpha-onboarding-motion
pr: 7328
spec: knowledge-base/project/specs/feat-alpha-onboarding-motion/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-08-06-alpha-onboarding-motion-brainstorm.md
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
Phase 2.8 IaC routing gate reviewed and opted out deliberately. This plan provisions no
infrastructure: its entire Files-to-Create/Edit set is markdown under knowledge-base/, plus two
GitHub issue comments (TR4). The single operator-performed step it records (the beta-CRM contact
upsert) is non-automatable BY ARCHITECTURAL DESIGN, not by omission — migration 126_beta_crm.sql
lines 170-172 REVOKE INSERT/UPDATE/DELETE from PUBLIC, anon, authenticated AND service_role, and
ADR-102 states no service-role write pipeline exists. Automating it would require adding the exact
bypass the architecture exists to prevent. The remaining human steps describe onboarding a person,
which has no Terraform representation.
-->

# Plan — Alpha Onboarding Motion: Validation Record + Per-Tester Runbook

## Overview

Record Soleur's transition from pre-launch to **active user onboarding**, with
`2my8r9ry2t-wq/Skouer` as alpha tester #1, and produce the repeatable per-tester runbook.

The scope-shaping finding is that this is **not greenfield**. The roadmap already defines this
motion as a sequenced five-stage protocol (rows 4.1–4.5) tracked by open P1 issues #1439–#1443.
The plan therefore *advances an existing protocol* rather than creating a parallel structure. The
headline state change is `Beta users: 0 → 1` — the first non-zero value in the product's history.

Deliverables: one validation record, one runbook, two issue comments, one roadmap line, one
follow-up issue. No product code (TR4).

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality (verified) | Plan response |
|---|---|---|
| Art. 13 governs a tester who signs up; Art. 14 covers the CLI/no-signup case | **Partially wrong, and it must be corrected before it lands in a compliance record.** The beta-CRM record is Art. **14** *regardless of whether the tester signs up* — the LIA (§"Art. 14 transparency for involuntary data subjects") scopes it to data "not obtained from the data subject via a form they submitted", which is true of operator-authored conversation notes even for a tester with a platform account. `model.c4:22-24` models the `betaContact` actor as "An involuntary data subject (Art. 14)"; Art. 30 PA-30 records the same. Art. 13 governs only the *platform account data* collected at `accept-terms`, which is a different dataset. | Correct D7/FR4 in spec + brainstorm: **Art. 14 governs the CRM record** (notice = the LIA's pasteable line); Art. 13 additionally governs platform account data if/when Skouer signs up. Both routes are message/policy-delivered — neither is in-person. |
| Beta CRM writes REVOKEd from service_role; no automation path | Confirmed verbatim at `126_beta_crm.sql:170-172` + header comment "no service-role write pipeline exists" | TR1 unchanged — record as a gate, never circumvent |
| `evaluating` = 0.5 entry stage | Confirmed at `lib/crm/stage-probability.ts:24-32`; `beta_contact_stage_transitions` append-only | TR3 unchanged |
| Validation-record precedent exists | Confirmed: `validation/2026-07-07-agent-operated-crm-validation.md`, YAML frontmatter (`title/date/status/verdict/type/scope/lenses/origin`) | FR1 follows its frontmatter shape |
| No third-party PII in git | Confirmed and **reinforced by independent internal precedent**: Art. 30 PA-32 cites PA-30's LIA to conclude a *different* activity has no lawful basis precisely because it commits third-party identifiers to a public repo | FR2 is the load-bearing AC; verification greps the final diff |
| No alpha-tester runbook exists | Confirmed: `git ls-files \| grep -iE 'alpha\|tester'` → 0 hits in runbooks/ | FR3 creates it |
| #1439–#1443 open, P1, Phase 4 milestone | Confirmed via `gh issue view` on all five | FR6 comments on #1439 + #1441 |

## User-Brand Impact

**If this lands broken, the user experiences:** an alpha tester whose personal data was committed
to a public git history that cannot be erased, or who was recorded in the CRM with no notice that
notes about them exist — discovered by the tester rather than disclosed by us.

**If this leaks, the user's data is exposed via:** permanent git history. Unlike the beta-CRM
database (owner-only RLS, 24-month sweep, `crm_erase_contact` Art. 17 path), a committed name or
email is world-readable on a public repo, survives deletion, and is fork-replicated.

**Brand-survival threshold:** single-user incident. This is the product's *first* external user;
a trust breach here is unrecoverable in a way it would not be at user 500.

## Domain Review

**Domains relevant:** Product, Legal, Engineering, Sales, Operations

Carried forward from the brainstorm's `## Domain Assessments` (assessed inline by the orchestrator,
not via spawned leaders — this session runs under an operator constraint against agent fan-out;
recorded so the depth is not over-trusted). Substantive findings:

### Product

Skouer is recruit #1 of 10 against an already-defined protocol. Live risk is the recruitment-mix
constraint (≥3 of 10 non-Claude-Code users); Skouer consumes a CC-user slot, so the tally must
start at tester #1.

### Legal

Art. 14 governs the CRM record; notice is a pasteable line, not a ceremony. The load-bearing
constraint is no third-party PII in git. Genuine gap upstream of the CRM: no alpha terms and no
DPA, while Skouer's own repo holds third-party personal data (a venture database of founders and
investors) that Soleur agents may process → TR5.

### Engineering

CRM write path is `auth.uid()`-pinned and REVOKEd from `service_role`; the degraded web platform
therefore gates the contact record. CLI-only testing means #1442 has no server-side telemetry.

### Sales

Entry stage `evaluating` (0.5) — past `qualified`, short of `committed` (no agreement, no WTP
signal). Append-only transitions mean the entry stage must be chosen deliberately.

### Operations

Runbook belongs in `engineering/operations/runbooks/` (40+ siblings). The 2-week checkpoint needs
a mechanism, not memory → the runbook prescribes filing a dated `follow-through`-labelled issue at
onboarding time rather than relying on recall.

### Product/UX Gate

**Not applicable.** Mechanical UI-surface override did not fire: Files-to-Create/Edit are markdown
only — no `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`. Product tier = NONE.

## Architecture Decision (ADR/C4)

**No architectural decision; no C4 impact.** Per the Phase 2.10 completeness mandate, all three
model files were read rather than keyword-grepped. Enumeration:

- **External human actors:** the alpha tester is already modeled — `model.c4:22-24`
  `betaContact = actor "Beta Tester / Prospect"`, described as an involuntary Art. 14 data subject
  with no direct store access. Accurate for Skouer; no edit needed.
- **External systems:** none introduced. Skouer's repo is reached through the already-modeled
  GitHub edge; no new integration, webhook, or vendor.
- **Containers / data stores:** none introduced. `crmStore` (`model.c4:172-174`) already describes
  `beta_contacts / interview_notes / beta_contact_stage_transitions` with the owner-only RLS and
  RPC-only write posture this plan respects.
- **Access relationships:** unchanged. This plan adds no edge and alters no ownership boundary;
  it records a business milestone and documents a human process.

A competent engineer reading only the existing ADRs + C4 would not be misled after this ships.

## Observability

**Skipped — pure-docs plan.** Files-to-Edit contains no code-class file under `apps/*/server/`,
`apps/*/src/`, `apps/*/infra/`, or `plugins/*/scripts/`, and no new infrastructure surface.

## Encryption Posture

**Skipped.** No persistent store and no cross-component connection introduced.

## Implementation Phases

### Phase 1 — Correct the GDPR framing at its source (do first)

The Research Reconciliation correction must land **before** the artifacts that inherit it, or FR4's
notice text will carry the wrong article into a compliance record.

1. Edit `specs/feat-alpha-onboarding-motion/spec.md` D7/FR4: Art. 14 governs the beta-CRM record
   (cite the LIA §"Art. 14 transparency" + `model.c4:22-24` + PA-30); Art. 13 additionally governs
   platform account data via `accept-terms` if/when the tester signs up. Neither is in-person.
2. Apply the same correction to the brainstorm's D7 row and `### Legal` assessment.

### Phase 2 — Validation record (FR1, FR2, TR2)

Create `knowledge-base/product/validation/2026-08-06-alpha-onboarding-motion-start.md` with
frontmatter matching the 2026-07-07 precedent. Content: motion start; Skouer as recruit #1 of 10
(repo URL only); test surface = self-hosted CLI plugin, hosted platform deferred until it is
serving again; protocol position (#1441 guided onboarding, operator-driven, with the deviation
from the #1440-before-#1441 sequence stated); the TR2 measurability caveat; the TR1 CRM gate and
its unblock condition; a link to the TR5 follow-up issue.

### Phase 3 — Per-tester runbook (FR3, FR4, FR5, FR8)

Create `knowledge-base/engineering/operations/runbooks/alpha-tester-onboarding.md`, six steps in
order: (1) qualify against the recruitment mix, checking the FR8 tally first; (2) send the welcome
message (FR4, copy-pasteable, carrying the Art. 14 notice line); (3) record the tester —
**FR5 warning sited here**: named contact goes to the beta CRM database only, never to git, citing
the LIA's permanent-git-history rationale; (4) seed the protocol issues; (5) what to observe during
the session (#1441: which domain leader they reach for first, friction points); (6) the 2-week
checkpoint — file a dated `follow-through`-labelled issue **at onboarding time**, with the TR2
caveat attached. Close with the FR8 tally table seeded `1 CC / 0 non-CC` and the pre-tester-#8
check.

### Phase 4 — Protocol issue comments (FR6)

Comment on #1439 (Skouer = recruit #1 of 10; is a Claude Code user per `CLAUDE.md`/`.agents/`/
`skills/` in their repo; consumes a CC-user slot against the ≥3-non-CC constraint) and #1441
(today's session: operator-driven, CLI-based, sequence deviation). Company-level only.

### Phase 5 — Roadmap (FR7)

`| Beta users | 0 |` → `1`. Update the Phase 4 row to note row 4.1 recruitment has begun with the
first recruit recorded.

### Phase 6 — Follow-up issue (TR5) + FR2 verification

File the agreement-gap issue (alpha terms + the Jikigai↔Skouer processor question), link it from
the validation record, then run the FR2 diff grep.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (FR2 — load-bearing).** `git diff origin/main...HEAD` contains no third-party personal
      name, email, or personal identifier. Verify:
      `git diff origin/main...HEAD -- knowledge-base/ | grep -nEi '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}' | grep -viE 'legal@jikigai|ops@jikigai|noreply'`
      returns empty.
- [ ] **AC2 (FR1).** `knowledge-base/product/validation/2026-08-06-alpha-onboarding-motion-start.md`
      exists with YAML frontmatter containing `title`, `date`, `status`, `type`.
- [ ] **AC3 (FR1).** That record names all four of: recruit #1 of 10, the Skouer repo URL, the CLI
      test surface, and the #1441 protocol position with its sequence deviation.
- [ ] **AC4 (FR3).** `knowledge-base/engineering/operations/runbooks/alpha-tester-onboarding.md`
      exists and contains all six step headings.
- [ ] **AC5 (FR4).** The runbook contains a fenced copy-pasteable welcome message whose body
      includes `legitimate interest`, `24 months`, and `legal@jikigai.com`.
- [ ] **AC6 (FR4 — negative).** Neither new artifact frames notice delivery as in-person. Verify
      `grep -niE 'in person|in-person|sign the notice|hand (them|over)' <both files>` returns empty.
- [ ] **AC7 (FR5).** The runbook's *recording* step (step 3) contains the PII-boundary warning —
      assert the anchor phrase, not a bare token: `grep -c 'beta CRM database only' <runbook>` ≥ 1.
- [ ] **AC8 (FR8).** The runbook contains the mix tally seeded at 1 Claude-Code-user / 0 non-CC and
      names the pre-tester-#8 check.
- [ ] **AC9 (FR7).** `grep -c '| Beta users | 1 |' knowledge-base/product/roadmap.md` returns 1.
- [ ] **AC10 (TR1).** No write path to the CRM tables is added anywhere:
      `git diff origin/main...HEAD | grep -nE 'beta_contacts|interview_notes|beta_contact_stage_transitions' | grep -iE '^\+.*(insert|update|delete|upsert|crm_contact_upsert)'`
      returns empty.
- [ ] **AC11 (TR2).** Both the runbook and the validation record state that #1442's metrics have no
      server-side telemetry on the CLI surface and name KB-growth-via-git-history as the one proxy.
- [ ] **AC12 (TR4).** `git diff origin/main...HEAD --name-only` lists only paths under
      `knowledge-base/`.
- [ ] **AC13 (Phase 1).** The spec and brainstorm both state Art. 14 governs the beta-CRM record;
      `grep -c 'Art. 14' <spec> <brainstorm>` ≥ 1 each, and neither asserts Art. 13 governs it.

### Post-merge (operator)

- [ ] **AC14 (TR5).** Agreement-gap follow-up issue is open and linked from the validation record.
      *Automation:* filed in Phase 6 via `gh issue create` — not deferred.
- [ ] **AC15 (TR1).** Beta-CRM contact created at stage `evaluating` once the web platform is
      serving. *Automation: not feasible because* migration `126_beta_crm.sql:170-172` REVOKEs all
      writes from `service_role` and ADR-102 states no service-role write pipeline exists; the write
      is `auth.uid()`-pinned to an authenticated owner session by design. Automating it would
      require adding the bypass the architecture exists to prevent. This is a genuine architectural
      gate, not deferred work.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| A personal name reaches git via a well-meaning edit | AC1 greps the diff; FR5 sites the warning at the exact step that would breach it; PA-32's precedent quoted in the record |
| The Art. 14/13 correction is applied to one artifact but not the other | Phase 1 runs first and edits both; AC13 asserts both |
| Runbook rots into a write-only artifact | Step 6 prescribes filing a dated `follow-through` issue at onboarding time — mechanism, not memory |
| Recruitment mix violated at tester #10 | FR8 tally seeded at tester #1; check placed before tester #8, the last point at which ≥3 non-CC is still satisfiable |
| CLI-era #1442 data compared against future platform-era data as if equivalent | TR2 caveat travels with the record and the runbook |

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| New alpha-cohort structure beside #1439–#1443 | Orphans five open P1 issues and a roadmap phase |
| Record the tester only in the CRM, skip the KB | The CRM is owner-private and currently unreachable; the *motion start* is a company milestone that belongs in the repo |
| Build `soleur:alpha-onboard` as a skill now | YAGNI at tester #1. Recorded as a Productize Candidate; run by hand for testers 1–3 so real friction shapes it |
| Draft alpha terms inline | Legal deliverable in its own right; filed as TR5 rather than improvised inside an ops record |

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` cross-referenced against
`knowledge-base/product/roadmap.md`, `knowledge-base/product/validation`, and
`knowledge-base/engineering/operations/runbooks` returned zero matches.
