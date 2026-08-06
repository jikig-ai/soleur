# Tasks — feat-alpha-onboarding-motion

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
Mirrors the ack in the plan and spec. This task list provisions no infrastructure: every task
writes markdown under knowledge-base/ or posts a GitHub issue comment. The one human-performed
step it records (the beta-CRM contact upsert) is non-automatable by architectural design —
126_beta_crm.sql:170-172 REVOKEs writes from service_role, ADR-102 states no service-role write
pipeline exists — not by omission. The rest describe onboarding a person, which has no Terraform
representation.
-->

Plan: `knowledge-base/project/plans/2026-08-06-ops-alpha-onboarding-motion-record-and-runbook-plan.md`
Spec: `knowledge-base/project/specs/feat-alpha-onboarding-motion/spec.md`
Issue: #7329 · PR: #7328 · Lane: cross-domain · Threshold: single-user incident

**Standing constraint on every task below:** no third-party personal data in any committed file.
The tester is `Skouer` / `https://github.com/2my8r9ry2t-wq/Skouer` — no name, no email. The named
contact belongs in the beta-CRM database only (LIA: git history is permanent, so committed
third-party PII is an Art. 17 erasure impossibility).

## Phase 1 — Correct the GDPR framing at source (must run first)

- [x] 1.1 Edit `specs/feat-alpha-onboarding-motion/spec.md` D7/FR4: Art. **14** governs the
      beta-CRM record (cite LIA §"Art. 14 transparency for involuntary data subjects",
      `model.c4:22-24`, Art. 30 PA-30). Art. 13 additionally governs platform account data via the
      existing `accept-terms` flow if/when the tester signs up. Neither is in-person.
- [x] 1.2 Apply the identical correction to the brainstorm's D7 row and `### Legal` assessment.

## Phase 2 — Validation record (FR1, FR2, TR2)

- [x] 2.1 Create `knowledge-base/product/validation/2026-08-06-alpha-onboarding-motion-start.md`
      with frontmatter shaped like `2026-07-07-agent-operated-crm-validation.md`
      (`title`, `date`, `status`, `type`, `scope`, `origin`).
- [x] 2.2 Body: motion start (pre-launch → active onboarding); Skouer as recruit #1 of 10 against
      #1439; repo URL; test surface = self-hosted CLI plugin (hosted platform deferred until it is
      serving); protocol position = #1441 guided onboarding, agent-assisted, with the
      #1440-before-#1441 sequence deviation stated explicitly.
- [x] 2.3 Record the TR1 CRM gate + its unblock condition, and the TR2 measurability caveat.
- [x] 2.4 Leave a placeholder for the TR5 issue link; fill in Phase 6.

## Phase 3 — Per-tester runbook (FR3, FR4, FR5, FR8)

- [x] 3.1 Create `knowledge-base/engineering/operations/runbooks/alpha-tester-onboarding.md`
      following sibling runbook conventions.
- [x] 3.2 Step 1 — Qualify: check the FR8 mix tally before extending an invitation.
- [x] 3.3 Step 2 — Welcome message: fenced, copy-pasteable, carrying the Art. 14 notice line
      (private notes kept on a legitimate-interest basis, 24-month retention, object/erase at
      `legal@jikigai.com`). Note that a tester who signs up to the hosted platform additionally
      gets Art. 13 notice via `accept-terms`, and that neither route requires meeting anyone.
- [x] 3.4 Step 3 — Record the tester. **FR5 warning sited here**: named contact goes to the beta
      CRM database only, never to git; cite the permanent-git-history rationale. Include the TR3
      entry stage (`evaluating`, 0.5) and note transitions are append-only.
- [x] 3.5 Step 4 — Seed the protocol issues (#1439 recruit, then the #1440→#1443 sequence).
- [x] 3.6 Step 5 — Observe during the session: which domain leader they reach for first, friction
      points (#1441's stated observations).
- [x] 3.7 Step 6 — 2-week checkpoint: file a dated `follow-through`-labelled issue **at onboarding
      time** so closure is mechanism, not memory. Attach the TR2 caveat.
- [x] 3.8 Close with the FR8 tally table seeded `1 Claude-Code-user / 0 non-CC`, the ≥3-non-CC
      requirement, and the check placed before recruiting tester #8.

## Phase 4 — Protocol issue comments (FR6)

- [x] 4.1 Comment on #1439: Skouer = recruit #1 of 10; is an existing Claude Code user (evidence:
      `CLAUDE.md`, `.agents/`, `skills/` in their repo); consumes a CC-user slot against the
      ≥3-non-CC constraint; tally now 1 CC / 0 non-CC.
- [x] 4.2 Comment on #1441: today's session — agent-assisted, CLI-based (hosted platform
      degraded), sequence deviation from #1440.

## Phase 5 — Roadmap (FR7)

- [x] 5.1 `| Beta users | 0 |` → `| Beta users | 1 |`.
- [x] 5.2 Update the Phase 4 row: row 4.1 recruitment underway, first recruit recorded.

## Phase 6 — Follow-up issue + verification

- [x] 6.1 File the TR5 agreement-gap issue: (a) no alpha-tester terms exist; (b) Skouer's product
      is a venture database holding personal data about founders/investors, so Soleur agents
      operating on that repo plausibly make Jikigai a processor of Skouer's third-party data — not
      covered by the beta-CRM LIA, which addresses notes *about* testers. Cite
      `knowledge-base/legal/data-processing-agreement-template.md` and `side-letter-template.md`.
      Milestone: Phase 4: Validate + Scale.
- [x] 6.2 Link that issue from the validation record (fills 2.4).
- [x] 6.3 Run AC1 → AC13 verification commands from the plan; paste output.

## Acceptance verification (from plan)

- [x] AC1 FR2 diff grep clean (load-bearing)
- [x] AC2/AC3 validation record exists + names the four required facts
- [x] AC4/AC5 runbook exists with six steps + welcome message
- [x] AC6 no in-person framing in either artifact
- [x] AC7 PII warning at the recording step (anchor phrase, not bare token)
- [x] AC8 mix tally seeded + pre-tester-#8 check
- [x] AC9 roadmap Beta users = 1
- [x] AC10 no CRM write path added
- [x] AC11 TR2 caveat in both artifacts
- [x] AC12 diff confined to `knowledge-base/`
- [x] AC13 Art. 14 correction applied to spec + brainstorm
