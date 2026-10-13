---
title: tech-debt-tracker — agent vs skill, lifecycle vs scanner
date: 2026-05-12
issue: 2723
parent_issue: 2718
lane: cross-domain
brand_survival_threshold: single-user incident
user_brand_critical: true
status: in-progress
---

# Tech-Debt-Tracker Brainstorm

## What We're Building

A **two-spec sequence** that closes the gap between Soleur's existing reactive tech-debt ledger and a productive debt-management workflow:

- **Spec A (immediate, ship now):** Ledger lifecycle. Add `status: open|resolved|wont-fix` and optional `linked_issue: #N` to entries under `knowledge-base/project/learnings/technical-debt/`. Backfill the 11 existing entries. Ship a new `/soleur:resolve-debt` skill that lists open entries (severity-sorted) and walks the founder through closing one with a PR/issue link.
- **Spec B (deferred with re-evaluation criteria):** Scheduled scanner. A skill (not an agent) wrapping `code-quality-analyst` + `pattern-recognition-specialist` + `semgrep-sast` in a new `scan-mode`, persisting findings as ledger upserts, gated by a 2-cycle dry-run, capped at 1 weekly digest issue. **Re-open only when:** (1) Spec A has shipped, AND (2) ≥3 ledger entries reach `status: resolved` within 60 days post-ship, AND (3) cloud platform (T1) has shipped or the founder reports velocity drag in retro.

Spec B is **not** in scope for this branch / PR / spec.

## Why This Approach

The triad converged on a sharp insight: the project's `knowledge-base/project/learnings/technical-debt/` directory is **write-mostly**. 11 entries exist (2026-02 through 2026-03); zero have a resolution marker; `gh issue list --search "tech-debt in:title" --state closed` returns empty. Layering a scanner that produces *more* unread entries onto a system that doesn't close existing entries compounds the problem, not the knowledge.

Building lifecycle first — and watching whether the founder actually closes entries via the new skill over the next 30-60 days — is a cheap, falsifiable test of whether a scanner would compound. If lifecycle alone produces zero closures, the scanner gets killed (correct outcome). If closures emerge, Spec B is unblocked with evidence.

## User-Brand Impact

**Artifact named:** `knowledge-base/project/learnings/technical-debt/*.md` ledger entries; future scanner-produced JSON snapshots and PR-body summaries.

**Vector named:** Public commits / PR descriptions in the `soleur` open-source repo. The `soleur` repo is public-on-merge; every byte in a committed ledger entry, PR body, or Discord release ping is public-by-default.

**Threshold:** `single-user incident`. A single committed entry that surfaces a prod hostname, an `infra/`/`terraform/`/`doppler/`/`supabase/migrations/` path, or a quoted TODO referencing credential rotation is sufficient to trip user-brand risk. **Headline risk (CLO):** *"Soleur's automated debt scanner committed `terraform/prod/main.tf:142 // TODO: rotate doppler_prod_token before Q3` to public PR #N, exposing infra topology and secret-rotation cadence."*

The risk is mostly **future** (Spec B), but Spec A's `linked_issue` field can still echo into issue bodies — any future scanner spec must inherit the path-allowlist and aggregate-only PR-body requirements documented under Open Questions / Spec B Constraints below.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | **Sequence: lifecycle first, scanner deferred.** | Existing ledger is write-mostly. Adding scan output without closure mechanics compounds backlog, not knowledge. |
| 2 | **Spec A scope: minimal — `status` + `linked_issue` only.** | Defers two-schema unification (older `module/problem_type` vs newer `title/category`). Backfilling 11 entries with only 2 new fields is reviewable in one PR. Schema unification is its own follow-up. |
| 3 | **Shape: SKILL, not agent.** | (a) All 15 existing `.github/workflows/scheduled-*.yml` invoke skills via `claude-code-action`, never agents directly — agents would require a skill wrapper anyway. (b) Upstream (`alirezarezvani/claude-skills/engineering/skills/tech-debt-tracker`) is a skill. (c) Existing review agents already cover review-time smell detection; founder/user invokes resolve-debt on demand, not autonomously. |
| 4 | **Spec B (deferred): scanner = skill wrapping existing review agents in scan-mode.** | Avoids forking smell-detection logic. Requires adding `mode: scan` to `code-quality-analyst.md`, `pattern-recognition-specialist.md`, `semgrep-sast.md`. Cost-of-change is a frontmatter/instruction edit per agent. |
| 5 | **Spec B constraints (carry-forward to future spec):** path allowlist `plugins/ apps/ packages/ knowledge-base/`; denylist `terraform/ infra/ doppler/ supabase/migrations/ .env* **/secrets/** **/private/** .worktrees/`; aggregate-only PR bodies (never paths); 2-cycle dry-run gate before commit mode; weekly digest issue capped 1/run; NOTICE attribution per gdpr-gate precedent; env-routed `${{ }}` expansion only. | CLO redaction requirements derived from `single-user incident` brand-survival threshold. These are non-negotiable for Spec B. |
| 6 | **Spec B persistence: extend ledger markdown (idempotent upsert); ephemeral JSON snapshots under `.soleur/tech-debt/` (already gitignored).** | Prevents bifurcation (humans→markdown, scanner→JSON). Single source of truth. |
| 7 | **No agent-vs-skill ambiguity remains.** | Decision recorded for Spec B as well — both specs land as skills. |
| 8 | **Cron slot for Spec B (when re-opened): Wed 11:00 UTC.** | Avoids contention with the 9 Monday-morning UTC slots and the daily 04/06/08/10/14/16/18 slots already populated. |

## Why Not — Rejected Alternatives

- **Full scheduled scanner now (issue body framing):** CPO blocks at founder-outcome gate (no T1-T4 mapping); CTO blocks on write-mostly evidence; CLO would proceed with guardrails but does not endorse premature build.
- **Defer #2723 entirely (CPO recommendation, option A):** Rejected in favor of the lifecycle prereq — it is small (~1d), evidence-gathering, and unblocks a future scanner decision with data instead of speculation.
- **Manual on-demand `/soleur:tech-debt` skill only (option C):** Functionally subsumed by `/soleur:resolve-debt` in Spec A. Re-titling does not change scope.
- **Schema unification + lifecycle in one pass:** Rejected for blast-radius reasons. Touches 11 files in one PR; harder to review. Schema unification is a separate cleanup follow-up.
- **Wholesale lift of upstream's three-tool framework (scanner/prioritizer/dashboard):** Rejected as YAGNI. We don't have the lifecycle yet; layering all three on top is premature. Upstream's reference content (taxonomy, frameworks) is liftable later with NOTICE attribution.

## Open Questions

- **Cost-of-delay framework choice (Spec A minor, Spec B blocker):** WSJF vs RICE vs ICE? No precedent in repo (research confirmed: no hits for any of these). Spec A's `/soleur:resolve-debt` skill needs a severity+age sort; WSJF is overkill, simple `severity × age_days` is enough. Defer framework choice to Spec B.
- **Schema unification follow-up issue:** When Spec A ships, file a separate P3 issue to unify the two frontmatter schemas under `learnings/technical-debt/`. Out of scope for this brainstorm.
- **`/soleur:compound` integration:** Does the compound skill need to learn to set `status: open` and prompt for `linked_issue` when it auto-creates new tech-debt entries? Likely yes — added to Spec A FRs.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Defers #2723 at the founder-outcome gate (no T1-T4 mapping; cloud platform is the critical path, debt tracking is not). Endorses the lifecycle-first prereq as the cheap falsifiable test of whether a scanner would compound. Re-evaluation: Phase 7 kickoff or ≥3 incidents traced to known-but-untracked debt.

### Engineering (CTO)

**Summary:** Build as skill, not agent — agents have no cron entry-point in current infra; all 15 scheduled workflows invoke skills via `claude-code-action`. Existing ledger is write-mostly (11 entries, 0 closures) — lifecycle is the load-bearing prerequisite. Spec B scanner should wrap `code-quality-analyst` + `pattern-recognition-specialist` + `semgrep-sast` in a new `scan-mode`, persist via markdown upsert, ephemeral JSON snapshots under gitignored `.soleur/tech-debt/`.

### Legal (CLO)

**Summary:** Proceed-with-guardrails. MIT→MIT lift is clean; NOTICE attribution per `plugins/soleur/skills/gdpr-gate/NOTICE` precedent is required for Spec B. GDPR/CCPA out of scope (no customer data path). Brand-survival risk concentrated in Spec B (committed artifacts in public repo); Spec A's `linked_issue` echo is a low residual surface. Non-negotiables for Spec B: path denylist, allowlist, aggregate-only PR bodies, 2-cycle dry-run gate, pre-commit regex for high-entropy strings + known secret prefixes.

## Capability Gaps

| Gap | Domain | Evidence | Spec |
|-----|--------|----------|------|
| No scan-only mode on review agents. | Engineering | `grep -c "scan-only\|scan mode\|--scan" plugins/soleur/agents/engineering/review/*.md` → 0 hits across 17 review agents. | Spec B |
| No ledger lifecycle skill. | Engineering | `ls plugins/soleur/skills/ \| grep -E "(resolve\|debt\|ledger)"` returns only `resolve-parallel`, `resolve-pr-parallel`, `resolve-todo-parallel` — no debt/ledger skill. | Spec A |
| `type/tech-debt` label may exist but is unused as triage signal. | Operations | `gh issue list --state closed --search "tech-debt in:title"` → empty array. | Spec A |
| No `CAP_PER_RUN` convention. | Engineering | Repo research: zero `CAP_PER_RUN`/`MAX_ISSUES`/`MAX_PRS` constants exist in any `.github/workflows/scheduled-*.yml`. Closest precedent: implicit `select first match` in `scheduled-bug-fixer.yml`. | Spec B (would establish convention) |
| No cost-of-delay framework precedent (WSJF/RICE/ICE). | Product | `git grep -i "WSJF\|RICE\|cost of delay"` on `knowledge-base/` and `plugins/soleur/` → empty. | Spec B |

## References (carry-forward for Spec B)

- Upstream pattern source: `github.com/alirezarezvani/claude-skills` — `engineering/skills/tech-debt-tracker/` (SKILL.md, references/{debt-classification-taxonomy.md, debt-frameworks.md, prioritization-framework.md, stakeholder-communication-templates.md}). MIT licensed, clean of vendor surface. Lift via NOTICE pattern when Spec B is built.
- NOTICE precedent: `plugins/soleur/skills/gdpr-gate/NOTICE` — frontmatter schema (`upstream`, `pinned-commit`, `last-verified`, `registry`, `lifted-files[].{path, upstream-path, upstream-blob-sha, local-blob-sha, status}`).
- Cron precedent: `.github/workflows/scheduled-content-vendor-drift.yml` (env-routed expansion, SHA-pinned actions, concurrency group, idempotent state mutation pattern).
- PR-authoring composite: `.github/actions/bot-pr-with-synthetic-checks/action.yml` (handles CLA + CI Required rulesets for bot PRs).
- Ledger entries to backfill: `knowledge-base/project/learnings/technical-debt/*.md` (11 files; two frontmatter schemas to preserve as-is in Spec A).
