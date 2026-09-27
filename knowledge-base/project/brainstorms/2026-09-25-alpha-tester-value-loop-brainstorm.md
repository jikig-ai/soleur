---
title: "Alpha-tester onboarding flow + value-prop validation loop"
date: 2026-09-25
type: brainstorm
feature: feat-alpha-tester-value-loop
lane: cross-domain
brand_survival_threshold: single-user incident
branch: feat-alpha-tester-value-loop
pr: 8868
related:
  - knowledge-base/engineering/operations/runbooks/alpha-tester-onboarding.md
  - knowledge-base/product/validation/2026-08-06-alpha-onboarding-motion-start.md
  - knowledge-base/product/roadmap.md
  - knowledge-base/product/business-validation.md
  - knowledge-base/project/learnings/technical-debt/2026-09-25-system-one-decision-engine-eval-deferred.md
  - knowledge-base/legal/2026-08-06-alpha-tester-processing-annex.md
  - knowledge-base/legal/legitimate-interest-assessments/2026-08-06-alpha-tester-repo-observation-lia.md
---

# Brainstorm — Alpha-tester onboarding flow + value-prop validation loop

## Premise correction (verified 2026-09-25 against origin/main)

The request framed this as greenfield ("zero testers, prior work: none"). Verified state differs:

- **Alpha tester #1 (Skouer) onboarded 2026-08-06** on the self-hosted CLI plugin. Recruitment is
  1 of 10 under #1439 (mix: 1 Claude-Code user / 0 non-CC; floor ≥3 non-CC, hard check before
  tester #8).
- **A complete Phase 4 validation protocol exists** — roadmap rows 4.1–4.5, issues #1439–#1443,
  per-tester runbook `alpha-tester-onboarding.md`, and a falsification tree (engineering-only →
  CaaS thesis wrong; multi-domain + no KB return → compounding wrong; multi-domain + KB return →
  holds) plus quantitative exit criteria (5+ of 10 on 2+ domains for 2+ weeks; 3+ WTP).
- **The validation loop's decision criteria are already written.** This brainstorm's job is the
  measurement machinery and cohort ops that produce those numbers — protocol advancement, not a
  parallel structure (the 2026-08-06 brainstorm's own D1).
- **Live defects on the running loop**: tester #1's 2-week checkpoint issue was never filed (due
  ~2026-08-20, now 5+ weeks overdue); #7459 terms re-notify is open across two TC bumps (2.5.0 →
  2.5.1); the beta-CRM contact record was gated on platform health — the platform is serving
  again (app.soleur.ai → /login 200); the processing annex is drafted but unexecuted, and the
  controller/processor determination requires a C9 re-run before tester #2's first session
  (#7348).

## User-Brand Impact

- **Artifact:** the alpha-tester onboarding flow + value-prop validation instrumentation.
- **Vector:** worst case — a silent onboarding failure or a telemetry/consent misstep burns the
  first real users' trust in the small communities (IH, solopreneur-X) that double as recruitment
  channels; or instrumented "value" is measured wrong and steers pre-PMF product decisions off a
  false signal.
- **Threshold:** `single-user incident`.

## What We're Building

A three-slice cohort program that advances the existing Phase 4 protocol rather than creating a
parallel structure:

- **Slice 1 — Repair + unblock the running loop.** Tester #1's owed actions (checkpoint, terms
  re-notify #7459, beta-CRM contact now the platform serves, C9 re-run for tester #2); fix
  `welcome-hook.sh:16` so marketplace installs actually get the first-session welcome (#5119);
  recruitment mix mechanics (screening question, non-CC interleaving, channel attribution).
- **Slice 2 — Onboarding flow v2.** Runbook update for the hosted path: guided key setup step,
  Slack tester channel, structured observation template, armed (not remembered) checkpoints; a
  `soleur:cohort-status` skill giving the non-technical operator one pull-based table; a
  tester-facing setup doc (the welcome message's `[link to setup instructions]` has no canonical
  target today).
- **Slice 3 — Instrumentation.** Cohort tagging (invite-token attribution, backend — no signup
  UI change); reuse of the existing `computeFunnel`/`computeMetrics` activation definition
  (domainCount ≥ 2 + span ≥ 14d); a tester-owned local `.soleur/decisions.jsonl` decision log
  (dual-write: hook matchers where supported + prose-directed `emit-decision.sh` for all four
  harnesses) serving triple duty — #1442 metrics, the parked System-1 eval corpus, and
  decision-quality feedback; a checkpoint aggregate-pull script (`alpha-metrics.sh`).

## Why This Approach

- **Hosted platform for testers 2–10** — the ≥3 non-Claude-Code testers cannot install a CLI
  plugin; the strategy thesis itself is "cloud service, not plugin"; and only hosted gives
  comparable funnel telemetry. CLI-era data stays a separate, caveated era (tester #1).
- **Local log + tester-initiated aggregate pull, no beacon** — CLO: a local write is Posture A
  (zero new regulated surface); transmission makes Jikigai a controller and falsifies published
  absolute claims (PP §4.1 "does not phone home", T&C "does not collect, transmit") requiring
  consent + Art. 13 + PA row + docs lockstep + TC bump. Deferred, with re-eval criteria.
- **Guided key setup** — preserves the tester's-key legal posture; works today; the delegation
  flag stays a legal-gated later step.

## Key Decisions

| # | Decision | Choice | Rationale |
|---|----------|--------|-----------|
| D1 | Test surface for testers 2–10 | **Hosted platform for all** | Non-CC testers cannot install a CLI plugin; single-surface keeps cohort data comparable; validates the product the roadmap bets on |
| D2 | API-key wall for non-technical testers | **Guided key setup in-session** | Works today, keeps tester's-key posture (Posture A); `BYOK_DELEGATIONS_ENABLED` flip deferred until the Side Letter lands |
| D3 | Feature scope | **Full loop incl. tester-#1 repair** | A loop built on a broken first iteration bakes the defect in; recruitment aids included (bottleneck is fill, not UX) |
| D4 | Onboarding shape | **Guided for ~3 more, then taper to self-serve** | Guided sessions are the protocol's observation instrument; taper once the friction list stabilizes |
| D5 | Tester support channel | **Slack** (operator choice) | Private channel, near-zero friction; last-message timestamps double as activity signal; may need workspace provisioning — flag at plan |
| D6 | Instrumentation mechanism | **Local `.soleur/decisions.jsonl` + aggregate pull** | Posture A preserved; dual-write (hook + prose emitter) covers 4 harnesses; triple duty (metrics/corpus/feedback) |
| D7 | Activation definition | **Reuse `domainCount ≥ 2` + span ≥ 14d** (existing `ACTIVATION_DEF`) | Already implemented in `computeFunnel` + designed in `activation-funnel.pen`; no parallel definition |
| D8 | Cohort capture | **Invite-token attribution (backend)** | `/invite/<token>` flow exists; cohort recorded server-side; no signup UI change |
| D9 | Tester #1 handling | **Repair loop + retro problem interview flagged post-exposure** | Cheap second data point; never pooled with clean #1440 data |
| D10 | Opt-in telemetry beacon | **Deferred** | Full consent/docs/PA stack + TC bump; re-eval when: a checkpoint pull proves insufficient for ≥2 testers, or a tester asks for live observability |
| — | Productize candidate | `soleur:cohort-status` (per-tester onboarding + checkpoints recur 9×) | Phase 2.5 productize checkpoint |

## Open Questions

- Does an operator-facing Slack tester channel already exist, or must the workspace/channel be
  provisioned? (Plan-time check; new vendor/sub-processor would route to CLO.)
- `ADMIN_USER_IDS`/`PLAUSIBLE_SITE_ID` populated in prd? (Env-level; verify at plan.)
- Exact `.soleur/decisions.jsonl` schema — field-allowlisted metadata only (NO-ECHO contract:
  label, skill, event, harness, session_id, ts, plugin SHA; never intent text/args). Plan/ADR
  detail.
- Cohort-tag storage: `users` column vs. invite-table join vs. beta_contacts link — plan-time
  schema decision (gdpr-gate applies).
- Whether the alpha cohort gets a private Slack *Connect* channel or a private workspace
  channel — different data-residency notes for the welcome message.

## Open Questions (out of scope / parked)

- BYOK delegation flag flip — gated on the Side Letter (legal), not this feature. (parked)
- Questionnaire-driven onboarding (#6008) — existing backlog item; this feature does not absorb
  it. (out of scope)
- CRM UI editing / funnel tooling (#6250) — deferred platform work. (out of scope)

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** The load-bearing fork was surface choice — hosted resolves the thesis contradiction
and the non-CC constraint at once. n=10 yields qualitative proxies, not statistics; the honest
instruments are the protocol conversations + KB growth, and willingness-to-pay (#1443) is the
only metric that closes the business question. Recruitment throughput (1/10 in 7 weeks) is the
true bottleneck. Durable decision-logging in the tester's own artifacts doubles as
moat-visibility (the tester *sees* their AI org's record).

### Legal (CLO)

**Summary:** Local-only logging is Posture A — zero new regulated surface; the regulated event
is collection, so use tester-initiated aggregate export at the existing checkpoint and defer
beacons. Testers 2–10 can onboard under Posture A without the annex provided the C9
determination re-runs and no Jikigai-keyed run occurs; #7348/#7459 are preconditions to scaling
the cohort, not to building. `soleur:gdpr-gate` does not auto-fire on plugin-side code — manual
invocation required at plan/work gates.

### Engineering (CTO)

**Summary:** Nothing in today's plugin ships decision capture — the skill-invocation/incident
logs are repo-side dev tooling (ADR-229). Hook parity is ~1.5/4 harnesses (CC full; Devin-local
partial; Grok/Codex-cloud none) so dual-write is required; record schema must be
field-allowlisted (NO-ECHO); metrics must be harness-tagged or capture-rate conflates with
usage-rate. All pieces are cloneable from `skill-invocation-logger.sh` precedent — port + wire,
not invention.

### Marketing (CMO)

**Summary:** The ≥3 non-CC mix constraint and the surface constraint are the same constraint —
hosted resolves both. Fill non-CC seats first (testers #2–4), add a screening question to the
recruitment DM, and harvest the Buttondown waitlist as the cheapest warm channel. The welcome
message's legal paragraphs are trust scaffolding — mutable: framing/CTA; immutable: notice
content + the banned withdrawn lead. Record channel + framing attribution per tester; design a
testimonial opt-in ask into #1443 now.

### Operations (COO)

**Summary:** The operational tail is failing, not the onboarding front — checkpoint never filed,
terms superseded, CRM write still open. Skill-ify the mechanical 60% (cohort-status pull, armed
checkpoints via the existing `schedule-reminder` primitive); keep the human 40% human (CRM
upsert, messages, sessions). Three-substrate drift (git tally / issues / CRM) is how tester #1's
state went stale — the cohort-status skill is the reconciliation answer.

### Support (CCO)

**Summary:** A non-CC tester's first session is currently a blank wall — welcome hook never
fires on marketplace installs, no tester-facing setup doc, no inbound channel named.
`beta_contacts.last_contact`/`next_action` fields already carry the quiet-tester instrument;
the observation template is a near-free fix that makes 10 sessions comparable. Capability gap:
no customer-success/adoption-tracking agent exists (acceptable at n≤3; flag for testers 5+).

### Sales (CRO) — not spawned

Assessment question not matched (no pipeline/deal motion; alpha recruitment is a validation
protocol, not sales).

### Finance (CFO) — not spawned

Assessment question not matched (no budget/planning impact; no alpha-tester recurring spend
needed — COO ledger check).

## Capability Gaps

- **Customer-success/adoption-tracking agent seat** (Support domain): no agent owns per-tester
  adoption tracking. Evidence: `ls plugins/soleur/agents/support/` → `cco.md`,
  `community-manager.md`, `ticket-triage.md` only; cohort tracking currently has no specialist
  owner. Not needed at n≤3; revisit when cohort ≥5.
- **No durable decision-log substrate shipped in the plugin** (Engineering): evidence —
  `plugins/soleur/hooks/hooks.json` registers only credential-guard/SessionStart/Stop/PreCompact
  matchers; `.claude/hooks/skill-invocation-logger.sh` is `$CLAUDE_PROJECT_DIR`-registered repo
  tooling (ADR-229), not shipped. This brainstorm's Slice 3 builds it.
- **No tester-facing setup doc** (Support): evidence — runbook welcome block has `[link to setup
  instructions for their chosen surface]` with no canonical target; only `plugins/soleur/README.md`
  (developer-facing) exists. Slice 2 produces it.

## Session Errors / Verification Log

- Premise corrected: "zero testers / prior work: none" → tester #1 exists; full Phase 4 protocol
  exists. Reframed to protocol advancement before any leader spawn (operator confirmed
  "extend existing protocol").
- `welcome-hook.sh:16` guard verified in source: gates on `plugins/soleur` dir existing in
  project root — false for marketplace installs.
- Tester #1 checkpoint issue: searched `checkpoint`, `2-week`, `usage review`, `Skouer` across
  all states — none found for the 2-week usage checkpoint; the Step-6 filing did not happen.
- Platform health: `app.soleur.ai` → 307 → `/login` 200 (2026-09-25).
- Laya/Jev System-1 eval tech-debt entry verified at
  `knowledge-base/project/learnings/technical-debt/2026-09-25-system-one-decision-engine-eval-deferred.md`;
  none of its four revisit triggers fire; its "enabling action" (durable decision log) is
  adopted as Slice 3 scope.
