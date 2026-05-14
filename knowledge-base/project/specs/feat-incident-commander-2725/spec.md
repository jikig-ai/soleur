---
title: incident-commander — SEV classification + redaction-gated PIR scaffold
issue: 2725
parent_issue: 2718
branch: feat-incident-commander-2725
brainstorm: knowledge-base/project/brainstorms/2026-05-13-incident-commander-brainstorm.md
brand_survival_threshold: single-user incident
lane: cross-domain
status: drafted
date: 2026-05-13
---

# Spec: `/soleur:incident` skill — SEV classification + redaction-gated PIR scaffold

**Issue:** #2725 (parent #2718)
**Branch:** `feat-incident-commander-2725`
**Brainstorm:** [2026-05-13-incident-commander-brainstorm.md](../../brainstorms/2026-05-13-incident-commander-brainstorm.md)
**Draft PR:** #3721

## Problem Statement

> [Updated 2026-05-13: D1 direction reversed per plan Research Reconciliation — the dominant frontmatter form is `brand_survival_threshold:` (97 files), not the singular `brand_threshold:` (1 file). D1 (PR #3737, merged) renamed the minority forms toward the dominant key; references below to `brand_threshold` reflect the spec's original framing but the canonical key is `brand_survival_threshold`. Likewise `single-user-incident` (hyphenated) was renamed to `single-user incident` (space-form).]

Soleur has organic incident-response practice (24 runbooks, 1 worked post-incident review at `knowledge-base/engineering/ops/runbooks/dashboard-error-postmortem.md`) but no skill or agent that:

1. Classifies a live incident's `brand_threshold` (`none` / `single-user incident` / `aggregate pattern`) under time pressure — operators currently classify by feel.
2. Evaluates GDPR Art. 33/34 notification triggers BEFORE drafting narrative — burning the 72h CNIL window on PIR authoring is the documented failure mode.
3. Scaffolds the canonical PIR shape (the `dashboard-error-postmortem.md` frontmatter + actor-key conventions) so the next PIR is consistent.
4. Enforces pre-write redaction of secrets / PII / session tokens before any committed markdown is produced.
5. Produces a redaction-gated public-safe summary alongside the internal PIR (status page / Discord postable) so the founder does not author public copy under pressure.

Secondary problem: the `brand_threshold` frontmatter key has four inconsistent spellings across the repo (`brand_threshold`, `brand_survival`, `brand_survival_threshold`, `threshold`) and two value-forms (`single-user incident` with space vs `single-user-incident` hyphenated). This inconsistency must be resolved before a skill writes to the field, otherwise the skill ossifies the wrong form.

## Goals

> [Updated 2026-05-13: D1 direction reversed — `brand_threshold` references below reflect spec original framing; canonical key is `brand_survival_threshold`. Public-safe PIR artifact deferred to #3732 per plan-review YAGNI consensus.]

- Ship a standalone `/soleur:incident` skill at `plugins/soleur/skills/incident/SKILL.md` that classifies in <60s, gates on Art. 33/34, and scaffolds two PIR artifacts (internal + public-safe) after recovery.
- Standardize `brand_threshold` frontmatter key + value-form repo-wide as a separate prerequisite PR (D1).
- Add a pre-write redaction sentinel (mechanical regex pass) that blocks markdown commit if any pattern matches the proposed PIR body or public-summary body.
- Reuse the canonical `brand_threshold` 3-value taxonomy from `AGENTS.core.md` `hr-weigh-every-decision-against-target-user-impact` — DO NOT introduce a parallel SEV-1/2/3/4 scale.
- Avoid name collision with the existing `.claude/hooks/lib/incidents.sh` (rule-violation telemetry) — skill must NOT touch `emit_incident`, `incidents.sh`, `.rule-incidents.jsonl`, or the rule-telemetry event_type enum.
- Defer Sentry auto-fetch, on-call rotation, paging integrations, status-page automation as explicit out-of-scope.

## Non-Goals (Explicitly Out of Scope)

> [Updated 2026-05-13: D1 direction reversed — references below to `brand_threshold` reflect spec original framing; canonical key is `brand_survival_threshold`.]

- **Sentry / webhook / cron auto-firing.** Skill is operator-invoked only (`/soleur:incident` or via `/soleur:go` intent routing).
- **On-call rotation, paging integrations (PagerDuty / Opsgenie), incident-channel auto-creation, status page CMS.** Cannibalization vs parent #2718 wholesale-port rejection. Track separately if demand surfaces.
- **Auto-prod-writes.** Every prod-touching action behind `hr-menu-option-ack-not-prod-write-auth`. Skill output is advisory artifacts only.
- **Auto-escalation between brand_threshold tiers.** Operator decides; skill suggests.
- **Parallel SEV-1/2/3/4 vocabulary.** Reuse `brand_threshold` only.
- **Wholesale port of `alirezarezvani/claude-skills/engineering-team/incident-commander`.** Inspiration only; clean-room derivation with MIT NOTICE attribution.
- **Runbook generator** (auto-write new entries to `runbooks/`). PIR generation is enough.
- **SLO tracker / error-budget integration.**
- **Promoting `cq-pir-redaction-sentinel` to an `AGENTS.core.md` Code Quality rule** in this PR. Skill-local enforcement only; promote AFTER the sentinel proves reliable on a real incident.
- **Public-summary write to an Eleventy status-page collection.** MVP writes sidecar `<slug>-public.md` markdown; revisit when a status page exists.

## Functional Requirements

### FR1: `brand_threshold` key + value-form rename sweep (D1 — PR1, separate PR)

> [Updated 2026-05-13: D1 direction REVERSED per plan Research Reconciliation. Dominant form is `brand_survival_threshold:` (97 files); the original FR1 framing renamed TOWARD the minority singular form. Plan FR1 + PR #3737 (merged) reverse the direction: minority forms (`brand_threshold:` 1 file, `brand_survival:` 5, semantic `threshold:` 4) → `brand_survival_threshold:`. Value-form `single-user-incident` (50 files) → `single-user incident` (space).]

Standardize repo-wide BEFORE the skill PR:

- Frontmatter key: rename `brand_survival`, `brand_survival_threshold`, `threshold` → `brand_threshold` (singular).
- Value-form: rename `single-user-incident` (hyphenated) → `single-user incident` (with space). Other values (`none`, `aggregate pattern`) already consistent.
- Targets (verified via `git grep -lE "brand_threshold|brand_survival|brand_survival_threshold"`):
  - `.claude/hooks/README.md`, `.claude/hooks/session-rules-loader.sh`
  - `.github/CODEOWNERS`, `.github/workflows/scheduled-disk-io-7d-recheck.yml`, `scheduled-github-app-drift-guard.yml`, `scheduled-ruleset-bypass-audit.yml`
  - `AGENTS.core.md`
  - `apps/web-platform/server/soleur-go-runner.ts`
  - `knowledge-base/engineering/architecture/decisions/ADR-026`, `ADR-027`, `ADR-028`
  - `knowledge-base/engineering/ops/runbooks/dashboard-error-postmortem.md`, `ruleset-bypass-drift.md`, `github-app-drift.md`, `codeql-bot-coverage.md`, `lint-bot-statuses.md`
  - `knowledge-base/legal/audits/2026-05-12-gdpr-gate-plan-phase-2-7-outcome.md`, `knowledge-base/legal/compliance-posture.md`
  - `knowledge-base/marketing/content-strategy.md`
  - Multiple brainstorms / learnings / plans (full list to be enumerated in PR1)
- No behavior change. Lint addition: `scripts/lint-brand-threshold-key.py` (post-MVP, deferred) to prevent regression.

### FR2: `/soleur:incident` skill scaffold (D3 — PR2)

Skill at `plugins/soleur/skills/incident/SKILL.md`. Phases:

- **Phase 0** — Capture operator-provided incident facts: title, detected_at (UTC), symptom prose, suspected_change pointer (PR# or commit SHA), affected user count estimate.
- **Phase 1 — Classification (<60s target).** Skill prompts the operator with a structured decision tree mapping incident facts to `brand_threshold` ∈ {`none`, `single-user incident`, `aggregate pattern`}. Output: advisory recommendation + rationale. Operator confirms or overrides; selection is recorded verbatim into PIR frontmatter.
- **Phase 2 — Art. 33/34 notification-trigger gate.** Skill emits structured fields: `art_33_triggered: bool`, `art_34_triggered: bool`, `notification_deadline: detected_at + 72h`. If `art_33_triggered = true`, skill BLOCKS Phase 3+ until operator acknowledges the notification path (link to `knowledge-base/legal/article-30-register.md`).
- **Phase 3 — Runbook routing.** Skill scans `knowledge-base/engineering/ops/runbooks/*.md` for `triggers:` frontmatter matching the operator-supplied symptom tokens (literal-substring MVP); surfaces top-3 matches as suggestions. No automated action.
- **Phase 4 — Internal PIR scaffold.** Skill generates a draft `<slug>-postmortem.md` from a template (template at `plugins/soleur/skills/incident/templates/pir.md`). Frontmatter schema verbatim from `dashboard-error-postmortem.md`: `title`, `date`, `incident_pr`, `incident_window`, `suspected_change`, `brand_threshold`, `status: open`, `triggers[]`. Body sections: Symptom, Root-cause hypothesis (table), Timeline (actor-key tagged), Recovery verification, Follow-ups, Who-was-affected (enumerated by USER ROLE: prospect / authenticated app user / legal-document signer / admin via Access / billing customer / OAuth installation owner).
- **Phase 5 — Public-summary scaffold.** Skill generates a sidecar `<slug>-public.md` with stronger redaction (no usernames, no stack traces, no internal hostnames, no employee names). Template: status (investigating / identified / monitoring / resolved), blast-radius bucket, time-to-recovery, what-we-fixed.
- **Phase 6 — Redaction sentinel (BLOCKING, runs separately on each draft).** See FR3.
- **Phase 7 — Operator review + commit.** Skill emits both drafts inline for operator review. Markdown commit is a SEPARATE ack-gated step (per `2026-02-16-inline-only-output-for-security-agents.md`). On approval, commits `<slug>-postmortem.md` + `<slug>-public.md` under `knowledge-base/engineering/ops/runbooks/`.
- **Phase 8 — Compound-capture handoff.** Skill calls `/soleur:compound-capture` with the fix learning. Boundary: `incident-commander = chronology + SEV + impact + scrubbed timeline; compound-capture = solved-problem pattern`.

### FR3: Pre-write redaction sentinel

`plugins/soleur/skills/incident/scripts/redact-sentinel.sh` runs BEFORE any markdown file is written. Blocking pass over the proposed body bytes. Patterns (extended-regex; fixture-test required before landing):

- JWT three-segment: `eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}`
- Email: `\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b`
- UUID (Supabase `auth.users.id` shape): `\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b`
- Stripe keys: `\b(sk|pk|rk)_(live|test)_[A-Za-z0-9]{16,}\b`
- Stripe customer / PI: `\bcus_[A-Za-z0-9]{14,}\b|\bpi_[A-Za-z0-9]{14,}\b`
- IPv4: `\b(?:\d{1,3}\.){3}\d{1,3}\b` (IPv6 deferred to follow-up)
- Env-var-with-value: `\b[A-Z_]+=[^[:space:]]+\b` paired with a known sensitive-env-name allowlist (DOPPLER, SENTRY, STRIPE, SUPABASE, OPENAI, ANTHROPIC, ...)

Sentinel exits non-zero on first match; emits offending offsets + a 40-char redacted preview ("at offset N: `<8-char-prefix>***<8-char-suffix>` matched pattern P"). Operator redacts and reruns. Internal vs public sentinel: public mode has additional patterns (employee-name allowlist, internal-hostname allowlist like `.internal`, `.local`, `*.jikigai.com`).

### FR4: Trigger paths

- `/soleur:incident` direct invocation (operator).
- `/soleur:go` intent routing for messages matching incident regex (tokens: `incident`, `outage`, `down`, `breach`, `errored`, `customer says`, `Sentry alert`). Specific regex tuned in plan phase.
- No Sentry / cron / webhook / GitHub-Action auto-firing in MVP.

### FR5: Compound-capture handoff

Phase 8 invokes `/soleur:compound-capture` with structured input: incident slug, fix PR number, root-cause category, brand_threshold tier, primary triggers. Boundary: incident-commander writes the PIR + public summary; compound-capture writes the fix-learning. They MUST NOT both write to the same file.

### FR6: Naming-collision avoidance

Skill code MUST NOT:

- Define a function named `emit_incident`, `incident_log`, `incidents_*`, or anything else colliding with `.claude/hooks/lib/incidents.sh`.
- Write to `.claude/.rule-incidents.jsonl`. If skill emits structured telemetry, use `pir-log.jsonl` or a similarly disambiguated name under a separate path.
- Add `event_type` values that collide with the existing `{deny, bypass, applied, warn}` enum used by `incidents.sh`.

A lint check (`scripts/lint-incident-naming.py`, optional follow-up) can enforce this; for MVP, a code-review check is sufficient.

### FR7: Two-artifact split

PIR and public-summary are SEPARATE files with separate redaction passes. They MUST NOT be derivable from each other automatically — operator confirms each independently.

### FR8: Operator override + LLM-trust boundary

- Skill computes incident slug (kebab-case from title), branch name, and any IDs itself — does NOT use LLM-emitted identifiers.
- Operator can override `brand_threshold` classification at any point — skill records both the advisory and the operator override with reason text.

## Technical Requirements

### TR1: SKILL.md contract compliance

- Frontmatter: `name: incident`, `description: This skill should be used when ...` (single-line summary).
- Body uses standard Soleur skill conventions (Phase headers, no leading numbers in section titles for slash-resolution).
- No stdlib Python CLI (per parent #2718 audit constraint). Bash + heredoc + standard CLI tools (`gh`, `git`, `jq`, `awk`).

### TR2: Template structure

- `plugins/soleur/skills/incident/templates/pir.md` — heredoc-friendly template with `{{TITLE}}`, `{{DATE}}`, `{{INCIDENT_PR}}`, `{{INCIDENT_WINDOW}}`, `{{SUSPECTED_CHANGE}}`, `{{BRAND_THRESHOLD}}`, `{{TRIGGERS_LIST}}` substitution points.
- `plugins/soleur/skills/incident/templates/pir-public.md` — sidecar template, fewer substitutions, status-page friendly.
- No `\|` inside inline-code in tables (compliance-runbook authoring discipline).

### TR3: Redaction-sentinel testing

- Fixture-test against `knowledge-base/engineering/ops/runbooks/dashboard-error-postmortem.md` (must NOT trigger false positives on existing PIR — current PIR was hand-redacted and is the negative baseline).
- Fixture-test against a synthetic positive corpus (real-looking JWTs, emails, UUIDs, etc.) at `plugins/soleur/skills/incident/test/fixtures/`.
- Bash test harness: `plugins/soleur/skills/incident/test/redact-sentinel.test.sh`.
- Per `cq-test-fixtures-synthesized-only`: synthesize fixtures from format specs; do not paste real production strings.

### TR4: Actor-key + ack-gate compliance

Every operator-directed step in the PIR template is tagged `agent` / `agent-with-ack` / `human` (matching `dashboard-error-postmortem.md` convention). Prod-touching steps explicitly cite `hr-menu-option-ack-not-prod-write-auth`. No skill-emitted step bypasses ack gates.

### TR5: MIT attribution for upstream inspiration

- `plugins/soleur/skills/incident/NOTICE` — short MIT-attribution file naming alirezarezvani/claude-skills as inspiration (NOT a verbatim port; clean-room derivation per parent #2718).
- One-line header in `SKILL.md`: "Inspiration: alirezarezvani/claude-skills (MIT). See `NOTICE`. Clean-room derivation; no upstream code lifted verbatim."

### TR6: User-impact-reviewer integration

Skill output frontmatter includes `brand_threshold` value. PRs that ADD or MODIFY a PIR with `brand_threshold: single-user incident` trigger the `user-impact-reviewer` agent at review time (already automatic via existing review skill wiring).

### TR7: ROPA-emission scope decision

Spec leaves `art_33_triggered` / `art_34_triggered` / `notification_deadline` / `affected_user_count` / `data_categories_breached` as frontmatter fields, BUT the wiring to `knowledge-base/legal/article-30-register.md` consumption is **out of scope for this PR**. ROPA wiring tracked separately. PIR emits the structured fields; whoever owns Art. 30 register reads them later.

## Acceptance Criteria

> [Updated 2026-05-13: AC1-AC3 below reflect the spec's original D1 direction (rename TOWARD `brand_threshold:` singular). Plan reversed the direction and PR #3737 merged the reversed sweep. The plan's AC1-AC3 in `2026-05-13-feat-incident-commander-skill-plan.md` are the binding ACs for D1; the spec ACs here are kept for historical context.]

- [ ] **AC1 (D1, PR1):** `git grep -l "brand_survival\|brand_survival_threshold"` returns zero hits across `*.md`, `*.sh`, `*.py`, `*.ts`, `*.yml` files (excluding archived brainstorms).
- [ ] **AC2 (D1, PR1):** `git grep -l "^threshold:" -- '*.md'` returns only architectural-decision review-threshold cases (verified against the existing 4 hits during plan phase). All `brand_threshold`-semantic uses migrated.
- [ ] **AC3 (D1, PR1):** `git grep -l "single-user-incident"` returns zero hits across non-archived files.
- [ ] **AC4 (D3, PR2):** Skill files exist at `plugins/soleur/skills/incident/SKILL.md`, `templates/pir.md`, `templates/pir-public.md`, `scripts/redact-sentinel.sh`, `NOTICE`.
- [ ] **AC5 (D3, PR2):** Running `/soleur:incident` on a dry-run scenario (synthetic incident facts) produces an inline draft of both `<slug>-postmortem.md` and `<slug>-public.md` BEFORE any file is written.
- [ ] **AC6 (D3, PR2):** Redaction sentinel test suite passes with zero false positives on `dashboard-error-postmortem.md` and 100% true-positive recall on the synthesized positive corpus.
- [ ] **AC7 (D3, PR2):** No skill code defines `emit_incident`, writes to `.claude/.rule-incidents.jsonl`, or references the rule-telemetry `event_type` enum.
- [ ] **AC8 (D3, PR2):** When operator selects `brand_threshold: single-user incident`, the skill blocks Phase 3+ until operator acknowledges Art. 33/34 notification-trigger evaluation.
- [ ] **AC9 (D3, PR2):** PR #3721 (or its rebased equivalent) ships D2+D3 bundled and CLOSES #2725; D1 PR1 is referenced from this PR's body but ships first.
- [ ] **AC10 (D3, PR2):** `user-impact-reviewer` is recorded as having fired on the D3 PR's diff (since the new skill touches `brand_threshold: single-user incident` artifacts).

## Open Questions (Deferred to Plan Phase)

1. **Runbook trigger-match algorithm** — literal-substring (MVP) vs token-set Jaccard vs LLM classifier. Decided literal-substring for MVP unless plan-phase prototyping shows it's too noisy.
2. **`/soleur:go` intent regex** — exact token set for incident routing. Iterate from `incident|outage|down|breach|customer says|Sentry alert` baseline.
3. **Public-summary employee-name allowlist** — source the allowlist (`CODEOWNERS` parse? explicit `plugins/soleur/skills/incident/data/allowlists/employees.txt`?).
4. **Public-summary internal-hostname allowlist** — explicit list under `data/allowlists/internal-hostnames.txt` (`.internal`, `.local`, `app.soleur.ai` staging variants).
5. **`pir-log.jsonl` emission shape** — defer until first real incident; do not over-engineer telemetry pre-usage.

## Dependencies

- Existing canonical taxonomy: `AGENTS.core.md` `hr-weigh-every-decision-against-target-user-impact` (3-value `brand_threshold`).
- Existing PIR shape: `knowledge-base/engineering/ops/runbooks/dashboard-error-postmortem.md`.
- Existing skills: `compound-capture`, `compound`, `gdpr-gate`.
- Existing agents: `user-impact-reviewer` (auto-fires on `single-user incident` PRs).
- Worktree-manager (`plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`) for branch isolation per PR.

## Domain Review (carry-forward)

CPO, CLO, CTO, CMO assessments captured verbatim in the brainstorm document `## Domain Assessments` section. Plan Phase 2.6 inherits this section + the `## User-Brand Impact` section from the brainstorm — no re-authoring at plan time.
