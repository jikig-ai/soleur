---
title: "Alpha onboarding motion — validation record + per-tester runbook"
feature: feat-alpha-onboarding-motion
issue: "#7329"
lane: cross-domain
brand_survival_threshold: single-user incident
status: spec
date: 2026-08-06
branch: feat-alpha-onboarding-motion
pr: 7328
brainstorm: knowledge-base/project/brainstorms/2026-08-06-alpha-onboarding-motion-brainstorm.md
related:
  - knowledge-base/engineering/architecture/decisions/ADR-102-beta-crm-capture-store-per-tenant-owner-private-agent-native.md
  - knowledge-base/legal/legitimate-interest-assessments/2026-07-07-beta-crm-lia.md
  - knowledge-base/engineering/operations/runbooks/beta-crm-third-party-erasure.md
  - knowledge-base/product/roadmap.md
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
IaC routing gate reviewed and opted out deliberately. This change provisions no infrastructure:
it is documentation, GitHub issue comments, and a roadmap edit (see TR4 — no migrations, no
product code, no dependencies). The one operator-performed step it describes (the beta-CRM
contact upsert, TR1) is not automatable by design rather than by omission: migration
126_beta_crm.sql REVOKEs INSERT/UPDATE/DELETE from service_role and ADR-102 states no
service-role write pipeline exists, so automating it would require adding the exact bypass the
architecture exists to prevent. The remaining human steps describe onboarding a person, which
has no Terraform representation.
-->

# Spec — Alpha Onboarding Motion: Validation Record + Per-Tester Runbook

## Problem Statement

Soleur is onboarding its first external alpha tester (`2my8r9ry2t-wq/Skouer`) today, with the
operator co-located with the Skouer founder. Nothing in the repo records that active user
onboarding has begun: `roadmap.md` still reads `Beta users: 0`, and the five Phase 4 validation
issues (#1439–#1443) that define this exact motion have no recruit against them.

The gap is not "there is no place to record this" — the places exist and are well-designed. The
gap is that **the first run of a ten-times-repeating process is happening with no written
process**, and the compliance boundaries that govern where a tester's data may be written are
recorded in a migration comment and an LIA rather than anywhere an operator would look mid-session.

Two failure modes follow directly:

1. **Personal data written into git.** The beta-CRM LIA §46 establishes that git-committed
   third-party PII is an Art. 17 erasure impossibility, because git history is permanent. An
   operator recording a tester in a knowledge-base file — the obvious place — creates an
   un-erasable record. Nothing currently warns against it at the moment of writing.
2. **Recruitment-mix violation discovered at tester #10.** #1439 requires ≥3 of 10 founders to
   not be current Claude Code users. Skouer is a Claude Code user. Without tracking from tester
   #1, the constraint is only checkable once recruitment is complete and unfixable.

## Goals

- Record the pre-launch → active-onboarding transition against the **existing** Phase 4 protocol
  (#1439–#1443, roadmap rows 4.1–4.5), not beside it.
- Record Skouer as alpha tester #1 with zero personal data in git.
- Produce a repeatable per-tester runbook so testers 2–10 follow a written process.
- Encode the GDPR posture (Art. 13 vs Art. 14; the PII-never-in-git boundary) where an operator
  will actually encounter it — in the runbook, at the step that would otherwise breach it.
- Record the beta-CRM contact write as an explicitly tracked gate with a named unblock condition.
- Track the recruitment-mix constraint from tester #1.

## Non-Goals

- **A tester-facing surface or alpha dashboard.** ADR-102 defers tester-visible CRM surfaces
  because they change the transparency posture the LIA is built on. Out of scope.
- **Fixing the Concierge / web-platform deploy issues.** They are the reason the CLI path was
  chosen and they gate the CRM write, but repairing them is separate work.
- **Drafting alpha-tester terms or a Jikigai↔Skouer DPA.** A real gap (see TR5) but its own
  legal deliverable, not something to improvise inside an ops record.
- **Backfilling #1440, #1442, #1443** with speculative content — their triggers have not fired.
- **Building `soleur:alpha-onboard` as a skill.** Recorded as a Productize Candidate; run the
  runbook by hand for testers 1–3 first so real friction shapes it.

## Functional Requirements

**FR1 — Validation record.** Write
`knowledge-base/product/validation/2026-08-06-alpha-onboarding-motion-start.md` recording: the
motion start; Skouer as recruit #1 of 10; the repo URL; test surface (self-hosted CLI plugin);
the protocol position (operator-driven onboarding under #1441, with the deviation from the
#1440-before-#1441 sequence stated explicitly); and the reason the CLI path was chosen. Follows
the precedent of `knowledge-base/product/validation/2026-07-07-agent-operated-crm-validation.md`.

**FR2 — Zero personal data in the record.** FR1's artifact, and every other git-committed file in
this change, identify the tester **only** at company/repo level (`Skouer`,
`https://github.com/2my8r9ry2t-wq/Skouer`). No name, email, or personal identifier. A reviewer
must be able to verify this by reading the diff.

**FR3 — Per-tester onboarding runbook.** Write
`knowledge-base/engineering/operations/runbooks/alpha-tester-onboarding.md` covering, in order:
qualification against the recruitment mix; the alpha welcome message (FR4); where the tester
record goes and where it must never go (FR5); seeding the protocol issues; what to observe during
the session (#1441: which domain leader they reach for first, friction points); and the 2-week
checkpoint (#1442) with the measurement caveat from TR2.

**FR4 — Welcome message with the notice line.** The runbook carries a copy-pasteable alpha welcome
message including the LIA's Art. 14 notice line: that private notes of the conversation are kept
for follow-up on a legitimate-interest basis, retained up to 24 months, with objection and erasure
available at `legal@jikigai.com`. Delivered as a message, not in person. For testers who sign up
to the hosted platform, the runbook states that Art. 13 is satisfied by the existing
`accept-terms` privacy-policy flow and the line is redundant.

**FR5 — PII boundary stated at the point of breach.** The runbook step that records the tester
states inline that named contact data goes to the beta CRM (database) **only**, citing the LIA's
Art. 17/permanent-git-history rationale. The warning must sit at the step an operator would
otherwise get wrong, not in a preamble.

**FR6 — Protocol issue updates.** Comment on #1439 recording Skouer as recruit #1 of 10 and its
Claude-Code-user status against the mix constraint; comment on #1441 recording today's session,
its operator-driven CLI shape, and the sequence deviation.

**FR7 — Roadmap update.** `Beta users` 0 → 1. Update the Phase 4 row to reflect that row 4.1
recruitment is underway with the first recruit recorded.

**FR8 — Recruitment-mix tracker.** The runbook carries a running tally of Claude-Code-user vs
non-Claude-Code-user recruits, seeded at 1 CC / 0 non-CC, with the ≥3 non-CC requirement stated
and the check placed before recruiting tester #8 (the last point at which the constraint is still
satisfiable).

## Technical Requirements

**TR1 — Beta-CRM write recorded as a gate, never circumvented.** Migration
`126_beta_crm.sql:170-172` REVOKEs INSERT/UPDATE/DELETE from `PUBLIC, anon, authenticated,
service_role`; ADR-102 states no service-role write pipeline exists by design. No part of this
change may add one, script around it, or write to those tables out of band. The record states the
unblock condition: the operator performs the contact upsert as the authenticated owner once the
web platform is serving.

**TR2 — Usage-tracking measurability caveat.** The runbook and validation record state that
#1442's metrics (returns, KB growth, non-engineering agent usage) have **no server-side telemetry
on the self-hosted CLI plugin**, and that the one measurable proxy is KB growth via git history on
the tester's own `knowledge-base/` tree (the operator holds collaborator access on Skouer). Returns
and agent-mix are not measurable on this surface. This caveat must travel with any #1442 finding
so CLI-era data is not compared against future platform-era data as if equivalent.

**TR3 — Entry pipeline stage set deliberately.** When the CRM write unblocks, the contact enters at
`evaluating` (0.5 in `STAGE_PROBABILITY`) — past `qualified` (recruited, actively onboarding),
short of `committed` (no agreement, no willingness-to-pay signal). `beta_contact_stage_transitions`
is append-only, so the entry stage cannot be silently corrected later.

**TR4 — No new dependencies, migrations, or product code.** This change is documentation, issue
comments, and a roadmap edit only.

**TR5 — Agreement gap filed, not silently carried.** File a follow-up issue covering (a) alpha-tester
terms and (b) the Jikigai↔Skouer processor question: Skouer's product is a venture database holding
personal data about founders and investors, so Soleur agents operating on that repo plausibly make
Jikigai a processor of Skouer's third-party data — a relationship the beta-CRM LIA does not cover,
since it addresses the operator's notes *about* testers, not tester data Soleur processes.
`knowledge-base/legal/data-processing-agreement-template.md` and `side-letter-template.md` exist as
starting points. The issue must be filed before agents operate on the Skouer repo in earnest.

## Acceptance Criteria

- [ ] FR1 validation record exists and states motion start, recruit #1, surface, protocol position
- [ ] FR2 verified: `git diff` contains no personal name, email, or personal identifier
- [ ] FR3 runbook exists at the stated path and covers all six listed steps
- [ ] FR4 welcome message is copy-pasteable and carries the notice line verbatim
- [ ] FR5 PII boundary appears at the recording step, citing the LIA rationale
- [ ] FR6 #1439 and #1441 carry the Skouer comments
- [ ] FR7 roadmap `Beta users` reads 1
- [ ] FR8 mix tracker seeded 1 CC / 0 non-CC with the pre-tester-#8 check
- [ ] TR1 no write path to `beta_contacts` added anywhere in the diff
- [ ] TR2 measurability caveat present in both runbook and validation record
- [ ] TR5 follow-up issue filed and linked from the validation record
