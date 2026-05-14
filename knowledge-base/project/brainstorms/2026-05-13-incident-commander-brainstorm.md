---
title: incident-commander — SEV classification + PIR scaffold
date: 2026-05-13
issue: 2725
parent_issue: 2718
brand_survival_threshold: single-user incident
lane: cross-domain
status: brainstormed
---

# Brainstorm: `/soleur:incident` skill — SEV classification + redaction-gated PIR scaffold

## What We're Building

A new standalone skill at `plugins/soleur/skills/incident/SKILL.md` that:

1. **Classifies** an incident's `brand_threshold` value (`none` / `single-user incident` / `aggregate pattern`) in <60 seconds during live incident response. Advisory only — no auto-escalation, no auto-prod-writes.
2. **Routes** to the matching existing runbook(s) under `knowledge-base/engineering/ops/runbooks/` via a `triggers:` keyword match.
3. **Gates** PIR drafting behind a Phase-0 GDPR Art. 33/34 notification-trigger evaluation. If personal data is involved and risk to rights/freedoms is non-negligible, the skill surfaces the 72h CNIL deadline as a structured field BEFORE proceeding to narrative drafting.
4. **Scaffolds** two PIR artifacts after recovery:
   - **Internal PIR**: `knowledge-base/engineering/ops/runbooks/<slug>-postmortem.md`, full detail, follows the existing `dashboard-error-postmortem.md` frontmatter schema verbatim.
   - **Public-safe summary**: `knowledge-base/engineering/ops/runbooks/<slug>-public.md`, redaction-gated, status-page / Discord postable.
5. **Enforces** a pre-write redaction sentinel (mechanical regex pass) BEFORE either markdown file is written. Sentinel scans for JWT three-segment, email, UUID, Stripe key prefixes, Stripe customer/PI IDs, IPv4, env-var-with-value forms. Pre-write blocking; operator must redact-and-retry.
6. **Calls** `/soleur:compound-capture` at the end to extract the fix learning into `knowledge-base/project/learnings/` (clear seam: incident-commander = chronology + SEV + impact + scrubbed timeline; compound = solved-problem pattern).

Trigger: operator-only via `/soleur:incident` or via `/soleur:go` intent routing when the user message matches an incident regex. No Sentry-alert auto-firing (no substrate exists; deferred).

## Why This Approach

### Outcome reframe — locked

Original issue body: "PIR in <30 min." Reframed to: **"correct SEV decision in <60s during incident + redaction-gated PIR scaffold after recovery."**

The original framing optimized for PIR authoring (post-recovery work where time pressure is gone). The actual founder bottleneck during a single-user incident is **classification + triage routing** (which runbook to open, whether to start the GDPR 72h clock, who to page). PIR generation as the headline outcome risks the worst-case path the operator named: "wrong-cause framing." Also: per CLO, burning the 72h CNIL window on narrative work IS the failure mode — Phase-0 notification-trigger evaluation MUST sit before drafting.

### Skill, not agent — locked

3/4 leaders unanimous. No stateful long-running coordination needed (no Sentry/Slack/Linear automation substrate exists in repo to coordinate). Skill (SKILL.md + bash + heredoc template) matches `postmerge` / `preflight` shape. An agent here would duplicate `/soleur:compound` and `/soleur:fix-issue`.

### Reuse `brand_threshold` 3-tier — locked

The repo already has a canonical 3-value taxonomy in `AGENTS.core.md` under `hr-weigh-every-decision-against-target-user-impact`: `none / single-user incident / aggregate pattern`. The `user-impact-reviewer` agent already gates on `single-user incident`. Inventing a parallel SEV-1/2/3/4 scale duplicates surface area and creates two vocabularies the operator must keep synced. Instead: standardize the inconsistent frontmatter keys (`brand_survival`, `brand_survival_threshold`, `threshold` → `brand_threshold`) repo-wide.

### Two artifacts in MVP — locked

CMO load-bearing: if app.soleur.ai has an outage during early ICP usage, silence is a bigger brand risk than a redacted public note. Designing the public artifact under pressure is failure mode. Both artifacts in MVP; redaction sentinel runs separately on each.

### D1 rename sweep first as separate PR — locked

Smaller blast radius per PR. PR1: `brand_threshold` key-rename across all callers (CODEOWNERS, ADRs, runbooks, brainstorms, learnings, hooks, workflow YAMLs). No behavior change. PR2: `/soleur:incident` skill + template + redaction sentinel + Art. 33/34 gate, building on the standardized vocabulary.

## Key Decisions

| Decision | Value | Rationale |
|---|---|---|
| Outcome | SEV <60s + redaction-gated PIR scaffold | Founder bottleneck is classification + Art. 33/34 routing, not authoring |
| Implementation shape | Skill, not agent | No automation substrate; one-shot template + classification fits SKILL.md contract |
| Severity taxonomy | Reuse `brand_threshold` 3-tier (`none` / `single-user incident` / `aggregate pattern`) | Already canonical in `AGENTS.core.md`; `user-impact-reviewer` already gates on it |
| Frontmatter standardization | Rename `brand_survival`, `brand_survival_threshold`, `threshold` → `brand_threshold` (singular) repo-wide [Updated 2026-05-13: REVERSED at plan-time — the dominant form is `brand_survival_threshold:` (97 files); minority forms were renamed toward the dominant key. PR #3737 (merged) implements the reversed direction.] | Resolves the 4-key inconsistency; ships as D1 PR1 |
| Value-form standardization | `single-user incident` (space form) is canonical; `single-user-incident` (hyphenated) gets renamed | One canonical form to grep for; included in D1 PR1 |
| Skill location | `plugins/soleur/skills/incident/SKILL.md` | Avoids name collision with `.claude/hooks/lib/incidents.sh` (rule-telemetry, NOT incidents); skill is singular, hooks library is plural |
| PIR write location | `knowledge-base/engineering/ops/runbooks/<slug>-postmortem.md` | Matches existing `dashboard-error-postmortem.md` convention; same dir as runbooks for discoverability |
| Public summary write location | `knowledge-base/engineering/ops/runbooks/<slug>-public.md` | Sidecar pattern; separate redaction sentinel pass |
| PIR frontmatter schema | Verbatim reuse of `dashboard-error-postmortem.md` keys: `title`, `date`, `incident_pr`, `incident_window`, `suspected_change`, `brand_threshold`, `status`, `closed_on`, `closed_via`, `triggers[]` | Sole prior PIR is the canonical template; no need to invent |
| Actor-key convention | Every step tagged `agent` / `agent-with-ack` / `human` per `hr-menu-option-ack-not-prod-write-auth` | Constraint inherited from existing PIR; auto-classifier output stays advisory |
| Art. 33/34 gate placement | Phase-0 (BEFORE drafting). Skill computes `art_33_triggered: bool`, `art_34_triggered: bool`, `notification_deadline` (incident_detected_at + 72h) | CLO load-bearing: 72h CNIL clock starts on detection; burning it on narrative work is the failure mode |
| Redaction sentinel placement | Pre-write, blocking. Regex pass on both internal and public draft BEFORE markdown is written to disk | Operator worst-outcome named: PII leak. Post-write audit is theatre once committed |
| Redaction patterns | JWT three-segment, email, UUID (Supabase `auth.users.id`), Stripe `sk_/pk_/rk_`, `cus_/pi_`, IPv4, env-var-with-value (`<NAME>=<value>`) | Per CLO; explicit allowlist, NOT a "remove sensitive info" prompt |
| Secret-leak special case | If `brand_threshold = single-user incident` AND triggers include credential/key terms, PIR step 0 hard-codes **revoke-first** + full git history rewrite procedure | Learning `2026-02-10-api-key-leaked-in-git-history-cleanup.md` constraint |
| Compound integration | Skill calls `/soleur:compound-capture` at completion, NOT `/soleur:compound`. Compound-capture writes the fix-learning to `knowledge-base/project/learnings/<category>/`. Incident-commander writes the PIR. Clean seam. | CTO + research §5 |
| Naming collision avoidance | Skill MUST NOT touch `.claude/hooks/lib/incidents.sh`, `emit_incident()`, `.claude/.rule-incidents.jsonl`, or the `event_type ∈ {deny, bypass, applied, warn}` enum. PIR telemetry (if any) uses disambiguated names like `pir-log.jsonl` | Learning `2026-04-24-rule-metrics-emit-incident-coverage-session-gotchas.md` constraint |
| Trigger paths | `/soleur:incident` operator-invoked; `/soleur:go` intent routing for messages matching incident keywords | No Sentry/webhook substrate exists; deferred |
| Build vs. borrow | Clean-room derive from Soleur's `brand_threshold` vocabulary. Upstream MIT taxonomy (alirezarezvani/claude-skills/engineering-team/incident-commander) is inspiration only. `NOTICE` + one-line attribution header per `2026-05-09-evaluating-vendor-branded-claude-code-skills.md` 30-sec recon | Parent #2718 audit concluded: extract patterns, do NOT wholesale port |
| LLM-trust boundary | Skill computes incident slug, hash, branch name itself. LLM-emitted IDs are untrusted. PIR draft passes through `pr-review-toolkit:silent-failure-hunter` discipline before promotion | Learning `2026-05-11-compound-promotion-loop-multi-agent-review-trust-models.md` |
| Threshold inheritance | Skill re-audits `brand_threshold` per artifact, NOT mechanically carries from incident classification | Learning `2026-05-12-brainstorm-re-audit-inherited-transparency-surfaces.md` |
| User-impact enumeration | PIR "Who was affected" section enumerates by USER ROLE (prospect / authenticated app user / legal-document signer / admin via Access / billing customer / OAuth installation owner), not by surface | Learning `2026-05-06-user-impact-section-by-role-not-surface.md` |
| Security-hook tolerance | Template uses generic phrasing ("raw system-shell invocations", "credential family X"), NOT literal sensitive-API tokens, to avoid `security_reminder_hook.py` blocks | Learning `2026-04-21-peer-plugin-audit-brainstorm-patterns.md` session-error #3 |
| Markdown executable-artifact discipline | No `\|` inside inline-code in tables. No `jq 'del(.results[].path)'` schema-blind redaction in template. | Learning `best-practices/2026-04-18-compliance-runbook-authoring-gotchas.md` |
| Output convention | Inline-only output for skill execution (operator reads inline first); markdown commit is a SEPARATE ack-gated step | Learning `2026-02-16-inline-only-output-for-security-agents.md` |
| Ship sequencing | D1 (rename sweep) → PR1. D2+D3 (skill + template + sentinel + Art. 33/34 gate) → PR2 bundled | CPO recommendation; smaller per-PR blast radius |

## Non-Goals (Explicitly Out of Scope)

- **Sentry auto-fetch / webhook receiver / cron-triggered auto-PIR**. No substrate exists. Operator-invoked only.
- **On-call rotation, paging integrations (PagerDuty/Opsgenie), incident-channel auto-creation**. Cannibalization risk per parent #2718 "wholesale-port rejection". If shipped as MVP, defer all of these.
- **Auto-prod-writes** (revoke keys, rollback canary, page on-call). Every prod-touching action stays behind `hr-menu-option-ack-not-prod-write-auth`. Skill output is advisory artifacts only.
- **Auto-escalation between SEV tiers**. Operator decides; skill suggests.
- **SLO tracker / error-budget integration**. Out of scope for MVP; revisit only if operator demand surfaces.
- **Wholesale port of alirezarezvani/claude-skills/engineering-team/incident-commander**. Inspiration only; clean-room derivation per parent #2718.
- **Runbook generator** (auto-write new entries to `runbooks/`). PIR generation is enough; runbook authoring stays human-curated.
- **Parallel SEV-1/2/3/4 vocabulary**. Reuse `brand_threshold` only.

## User-Brand Impact

**Artifact:** `/soleur:incident` skill output (internal PIR markdown + public-safe summary markdown).

**Vector:**
1. Misclassification of SEV → delayed response, customer impact compounds (operator-named worst outcome a).
2. PIR PII/secret leak from timeline reconstruction committed to public repo (operator-named worst outcome b).
3. Wrong-cause PIR framing → misattributed fixes, eroded operator trust in the process (operator-named worst outcome c).
4. Burning the 72h CNIL window on narrative work instead of notification triage (CLO-added vector).
5. Public summary contains internal hostnames / employee names / user counts that should not be disclosed (CMO-added vector).

**Threshold:** `single-user incident` (inherited from Phase 0.1 framing; user endorsed all three preset risk paths; aggregate-pattern threshold considered but not adopted since the skill operates on a single live incident at a time).

**Mitigations:**
- Pre-write redaction sentinel (mechanical regex, blocking).
- Phase-0 Art. 33/34 notification-trigger gate before PIR drafting.
- Two-artifact split (internal vs public) with separate redaction passes.
- Actor-key + per-command ack on every prod-touching step.
- LLM-trust boundary (skill computes IDs, not LLM).
- `user-impact-reviewer` agent fires automatically when `brand_threshold = single-user incident`.

## Open Questions

1. **Public-summary write location**: `knowledge-base/engineering/ops/runbooks/<slug>-public.md` sidecar (current decision) vs. `app.soleur.ai/status` Eleventy collection (future-facing if a status page exists). Decision: sidecar for MVP; revisit when a status page lands.
2. **Redaction-sentinel false-positive rate**: CLO flagged proposed regexes as "unverified — need fixture testing against real Sentry/Supabase output before landing." Spec must include fixture-based test plan against the existing `dashboard-error-postmortem.md`.
3. **`triggers[]` matching algorithm for runbook routing**: literal-substring vs token-set Jaccard vs LLM classifier. Decision deferred to plan phase; literal-substring is the conservative MVP.
4. **ROPA emission**: CLO recommended a structured frontmatter block for `knowledge-base/legal/article-30-register.md` consumption (`affected_user_count`, `data_categories_breached`, `legal_basis_impacted`, `art_33_triggered`, `art_34_triggered`, `notification_sent_at`, `dpa_partner_notified[]`). Scope into MVP or defer to a follow-up PR that wires ROPA consumption?
5. **AGENTS.md rule addition**: Should `cq-pir-redaction-sentinel` be added to `AGENTS.core.md` Code Quality as a hard rule, or stay scoped to the skill's own pre-write check? Recommendation: skill-local for MVP; promote to AGENTS rule only after the sentinel proves reliable on a real incident.
6. **`/soleur:go` intent regex for incident routing**: tokens like `incident`, `outage`, `down`, `breach`, `errored`, `customer says`, `Sentry alert`. Decision deferred to plan phase.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Reframe outcome from "PIR <30 min" to "correct SEV <60s + redaction-gated PIR scaffold." Skill, not agent. Reuse `brand_threshold` 3-tier — do NOT invent SEV-1/2/3/4. Ship D1 key-rename sweep as a separate PR before the skill PR. Cannibalization risk vs parent #2718 is moderate (1 sibling closed, 3 open including this); revisit if #2726/#2727 also reframe-or-defer.

### Legal (CLO)

**Summary:** Phase-0 Art. 33/34 notification-trigger gate MUST sit BEFORE PIR drafting — 72h CNIL clock starts on detection. Data-minimization at PIR-write time via pre-write redaction sentinel (regex allowlist for JWT/email/UUID/Stripe IDs/IPv4/env-vars; flagged as fixture-test-pending). ROPA structured frontmatter emission (Art. 30 register input) recommended in scope. `gdpr-gate` placement pre-write, blocking-by-acknowledgment.

### Engineering (CTO)

**Summary:** Skill not agent (no automation substrate). Clean-room SEV taxonomy ties to `USER_BRAND_CRITICAL` semantics. PII-scrubber prerequisite is brand-critical given operator worst-outcome b. Sentry auto-fetch deferred as out-of-scope MVP. New `incidents/` dir crosses GDPR boundary — recommend ADR for "Incident artifact location + PII-scrub contract." (Note: CTO sub-agent had path-resolution issue on initial CWD; orchestrator verified file count and runbook presence via direct grep — runbooks/ has 24+ entries, `dashboard-error-postmortem.md` exists, `brand_threshold` IS the de facto vocabulary.)

### Marketing (CMO)

**Summary:** No standalone launch — parent #2718 bundle-don't-announce rule holds. BUT scope expansion required: skill must produce TWO artifacts when SEV ≥ single-user incident — internal PIR (full detail, committed) + public-safe summary (redaction-gated, status-page postable). Trust signal accrues passively from `status: closed` / `closed_via` markers — no marketing work required. Watch for "incident-commander suite" scope creep (runbook generator, on-call rotation, paging) which re-triggers #2718 wholesale-port rejection.

## Capability Gaps

| Gap | Domain | Why needed | Evidence cited |
|---|---|---|---|
| **PII-scrubber for PIR generation** (mechanical regex pass that runs pre-write, blocking) | Engineering / Legal | Operator worst-outcome b (PIR PII leak). `gdpr-gate` skill audits diffs but does not transform incident chronologies. No existing skill or agent redacts user IDs / emails / JWT fragments from log excerpts before writing committed markdown. | Verified absent via `git grep -lE "redact|scrubber|sanitize" plugins/soleur/skills/` (zero hits for incident-class redaction). CLO assessment names this explicitly. |
| **Sentry-fetch / webhook substrate** | Engineering | Not required for MVP (operator-invoked skill); flagged as deferred. Required if PIR auto-population from Sentry events ever becomes in-scope. | Verified via `grep -rln "sentry" .github/workflows/` (only `reusable-release.yml` build-arg passthrough). PIR follow-up D6 in `dashboard-error-postmortem.md` explicitly tracks this as known unfilled gap. |
| **Public status page** | Marketing / Engineering | CMO recommended public-summary write to a status page. No status page exists today (MVP writes to sidecar `<slug>-public.md` markdown file). Defer until ICP demand surfaces. | Verified via `find apps/web-platform -name "status*" -type d` (no status route). |

## Resume Prompt

```
/soleur:plan #2725 — incident-commander (SEV classification + redaction-gated PIR scaffold).
Brainstorm: knowledge-base/project/brainstorms/2026-05-13-incident-commander-brainstorm.md.
Spec: knowledge-base/project/specs/feat-incident-commander-2725/spec.md.
Branch: feat-incident-commander-2725.
Worktree: .worktrees/feat-incident-commander-2725/.
PR: #3721 (draft).
Brand-survival threshold: single-user incident.
Lane: cross-domain.
Brainstorm complete; ship sequencing: D1 brand_threshold key-rename PR first, then D2+D3 skill PR.
```
