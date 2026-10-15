# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-15-fix-infra-observability-five-defect-batch-plan.md
- Status: recovered from partial-artifact (subagent terminated on an Anthropic session
  limit — "resets 3:30pm Europe/Paris" — mid-way through emitting its Session Summary;
  the plan body and decision-challenges.md were already on disk).

### Recovery evidence
- Plan is **v2, post-review**: a 6-reviewer panel falsified v1 on four points and the
  mechanical findings are applied. `plan` + `plan-review` both completed.
- Required sections all present: frontmatter, Overview, Research Reconciliation,
  Implementation Phases (0-5), Acceptance Criteria, Test Scenarios, Risks, Sharp Edges.
- Scope verified clean: `git diff origin/main...HEAD --name-only` empty — the planning
  subagent committed no product code. Only the init commit (60503199d) is on the branch.
- `deepen-plan` completion unconfirmed (no research-agent markers). Not re-run: the v2
  plan already carries RR-1..RR-20 and D-1..D-6, deeper than a typical deepen pass, and
  re-running would re-burn budget against a live session limit.

### Errors
- Planning subagent terminated early: "Agent terminated early due to an API error:
  You've hit your session limit · resets 3:30pm (Europe/Paris)". Session Summary never
  emitted; recovered via the on-disk artifact path instead of re-running plan.

### Decisions (from the plan v2)
- #6429 premise **falsified** (RR-1/2/3/4): the rule uses `event_unique_user_frequency`,
  not `event_frequency`; the issue's "three rules at :1233/:1380/:1462" is wrong on count
  and all three lines; the zot `value = 0` fix already landed. Real defect is elsewhere
  (RR-17, an in-file off-by-one).
- #6437 filed fix **void** (RR-6): emitting before the Doppler early-returns is a no-op —
  absent Doppler also empties the `SENTRY_*` prefetch, so the emitter's guard is false.
  Re-designed on a Doppler control probe.
- #6446 suggested fixture render **cannot work** (RR-10): that test's substituter handles
  `${...}` only, no `%{`. Reuse the existing `terraform console` render authority (AC7).
- #6447 is 1 of ~12 live wrong citations outside plans/specs (RR-12).
- RR-13 (**split, D-3**): `article-30-register.md:164` has a rotted anchor concealing a
  **false compliance claim** — states 30 MB rolling, but the container runs
  `--log-driver journald`; real bound is `SystemMaxUse=1G`. Re-pointing would leave the
  register wrong *and* freshly "verified".

### Resolved decision — UC-1 APPLIED (no longer blocks /work)
- **UC-1**: CPO (blocking) + DHH argued Phase 4 (`ci-deploy.sh`, #6437) must be its own PR
  — it is the only phase that can cause an `app.soleur.ai` outage (~22-line no-container
  window at `:1884-1907`). Plan left it NOT applied, citing an "operator's stated
  direction" (*"as one batch"*) that originated in the one-shot args, **not** from the
  operator. Escalated to the operator before any code was written.
- **Outcome: the operator chose the split; UC-1 is APPLIED.** This branch is **PR-A**
  (#6456: #6436, #6429, #6446, #6447 — jointly inert, no runtime path). Phase 4 / #6437 is
  **DEFERRED to PR-B by design — do not implement it here.** PR-A ACs green: AC1–AC6, AC11,
  AC13–AC16. Nothing in this section blocks /work.

### Components Invoked
- soleur:plan, soleur:plan-review (via one-shot planning subagent, terminated on limit)
