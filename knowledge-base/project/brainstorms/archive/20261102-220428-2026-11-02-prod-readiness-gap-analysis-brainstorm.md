# Brainstorm: Production-Readiness Checklist and Best-Practice Gap Analysis for Customer Repos

**Date:** 2026-11-02
**Trigger:** Operator request: customers who already have a GitHub repo and an MVP (e.g. alpha tester Skouer) should get (1) a production-readiness checklist plus gap analysis for opening to their own customers, and (2) a gap analysis of Soleur engineering best practices missing from their repo. Where should it live — in `/soleur:sync`?
**Lane:** cross-domain
**Brand-survival threshold:** single-user incident

## What We're Building

A new **read-only analysis skill** (name decided at plan time; candidate naming from CMO: "Launch Check") that runs in the customer's own Claude Code session, on their machine and key, against their repo and produces:

1. **Production-readiness findings** across four v1 domains: Security & secrets; Tests & CI/CD; Tech debt & architecture; Reliability, performance & ops.
2. **Soleur best-practice gap findings**: guardrails, hooks, CI gates and conventions Soleur uses that the repo lacks, each mapped to the existing scaffold skill that would close it.
3. **One living markdown file** in the customer's `knowledge-base/` (re-run diffs against the previous run and ticks closed gaps).
4. **An epic with severity-ranked, domain-labeled sub-issues** in the customer's GitHub repo, created only after a preview and the customer's confirmation, deduplicated on re-run.

The analysis itself writes nothing but the report file. Issue creation is the only other write, and it is confirm-gated.

## Why This Approach

`/soleur:sync` is the wrong home (CTO, verified):

- `sync` is a **write path**: every finding lands in `knowledge-base/`, and the web platform runs `/soleur:sync --headless` on every repo clone (`apps/web-platform/server/auto-sync-trigger.ts:84`). A gap analysis plus issue creation there would run unattended on every connected repo.
- Only `go`, `sync`, `help`, `version` may be commands (`plugins/soleur/AGENTS.md`); new capability must be a skill.
- `sync` already has known customer-repo defects (#7452, #7442 class). `sync` can still *feed* the analysis (its `testing`, `debt`, `project` output is an input); it gets only a pointer to the new skill.

Nothing today reports "customer repo lacks these Soleur-style guardrails": `verification-scaffold` installs four guards but does not audit; `guardrail-audit.md` classifies only Soleur's own hooks and lints. The baseline manifest `guards.tsv` (`plugins/soleur/skills/verification-scaffold/references/guards.tsv`) is the precedent to extend.

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| D1 | New skill, not a `/sync` area and not a verification-scaffold mode | Sync is write-path and headless on every clone; verification-scaffold only knows four guards and cannot express production readiness. |
| D2 | v1 ships **both** reports (readiness + Soleur-baseline gap diff) | Operator decision, overriding the CPO's smaller-probe recommendation. |
| D3 | Output is **one living file** plus an **epic with severity-ranked, domain-labeled sub-issues** | Operator decision. Closure is built in (re-run ticks closed gaps), which answers the learnings warning that ledgers with no closure mechanic only grow. |
| D4 | Issue creation is **preview, then customer confirm, deduplicated on re-run** | Technical ruling: it writes to the customer's tracker. Not an operator question (`hr-technical-fork-is-not-an-operator-question`). Ruled by CTO agent pending plan-time confirmation. |
| D5 | v1 domains: Security & secrets; Tests & CI/CD; Tech debt & architecture; Reliability, performance & ops | Operator decision. |
| D6 | Baseline manifest ships **inside `plugins/soleur/`**, derived by a CI test from the repo (ADR-193 "derived, never listed") | `.claude/hooks/` and `scripts/lint-*` are not in the marketplace payload (#7442); content outside the payload vanishes on customer installs. |
| D7 | Deterministic scanner for facts, LLM only for architecture judgement and synthesis; every LLM finding cites a deterministic evidence line | Keeps findings reproducible; limits hallucinated gaps. |
| D8 | Local CLI only in v1, on the customer's machine and key, **no telemetry or "share your report" path** | CLO: this keeps Soleur a software supplier (Posture A); any phone-home makes Soleur a controller and contradicts the published no-telemetry statement. |
| D9 | Reuse the `code-to-prd` walker and redaction: `git ls-files` only, deny `.env*`, `*.pem`, `*.key`, `credentials.*`, `.git/**`, tfstate/tfvars, symlinks; add no-read for DB dumps, fixtures and CSVs; findings cite `path:line`, never content; redact-sentinel/gitleaks pass aborts the write on a hit | CLO + CTO. A leaked secret or personal data in a committed report or public issue is a Soleur-caused incident. Issue bodies get the same redaction. |
| D10 | Wording: findings list, no single score; avoid "certified/compliant/passed/production-ready"; standing banner (scope, absence of findings is not assurance, not a security audit/legal advice/certification, AI-generated); GDPR/SOC2-style items labeled "engineering signal, not compliance determination" | CLO + CMO. Skouer processes real officer data. |
| D11 | Dogfood on Skouer's repo run by the tester with their own key; add "was this useful?" to the cohort checkpoint | CPO + CLO condition C1: no Jikigai-keyed runs against tester content until an Art. 28(3) instrument exists. |
| D13 | **Also run it against this repo (jikig-ai/soleur)** as a self-test, in dry-run mode (report plus issue preview, no issues created) | Operator decision. Soleur is the source of the baseline, so the baseline-gap report should come back near-empty: any finding is either a real gap in Soleur or a false positive in the baseline, which calibrates the manifest before Skouer sees it. The readiness half gives a second, much larger real-world sample. Dry-run is mandatory so the run does not open an epic in the production tracker by accident. |
| D12 | Advisory phases need a machine-enforced promotion trigger | Learning 2026-07-16: advisory-first has never been promoted here. |

## User-Brand Impact

- **Artifact:** the customer-repo readiness skill, its report file, and the issues it creates in the customer's GitHub repo.
- **Vector:** a secret or personal data from the customer's repo leaks into a committed report or a public issue; or a report is read as an assurance or certification that turns out wrong.
- **Threshold:** `single-user incident`.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering (CTO)

**Summary:** Sync is the wrong home; build a new skill with a deterministic scanner, a payload-shipped derived baseline manifest, and confirm-gated writes. Medium complexity, about days.

### Product (CPO)

**Summary:** No cohort signal asks for this yet (speculative, n=1); fits Phase 4 only as a probe and must not displace live protocol defects (#8981 overdue checkpoint, #7459, C9 re-run before tester #2). Recommended a smaller slice with no auto-issues; operator chose a larger v1 (D2, D3).

### Legal (CLO)

**Summary:** Local CLI on the customer's key stays Posture A; hosted is Posture B and needs an Art. 28(3) instrument first (C1, C5 #7347, C9). Redaction, disclaimer banner and no-telemetry are required. Open: BUSL-1.1 attribution line for copied baseline text, and whether T&C/Disclaimer cover CLI outputs (not verified).

### Marketing (CMO)

**Summary:** Moderate to strong onboarding hook for founders with an existing repo, but technical register while the roadmap ICP is non-technical. Avoid "audit/score/certification"; no quantitative claims at n=1; a Skouer case study needs the testimonial opt-in and tester terms (#7331) first.

## Capability Gaps

- No skill audits a customer repo against Soleur's guardrail baseline. Evidence: `gh issue list --state all -L 200 --search '"production readiness" in:title,body'` returned `[]`; `git ls-files | grep -iE 'readiness|launch|gap'` found only unrelated code, ADRs and runbooks; `verification-scaffold` has install but no audit mode.
- No machine-readable portability manifest covers rules, workflows or ADRs. `guards.tsv` has four rows; ADR-171's `kb-blueprint.json` does not exist.

## Open Questions

1. Skill name and operator-invoked vs model-invocable (the skill-description word cap is a plan-time constraint; measure headroom then).
2. Baseline scope beyond the four guards: which AGENTS.md rule classes, CI gates and ADR classes are portable? Needs a portability audit extending `guardrail-audit.md`.
3. Severity rubric (critical/high/medium/low) and how it maps to labels created in the customer's repo.
4. GitHub mechanics: sub-issues API availability on the customer's plan, label creation, dedupe key.
5. BUSL-1.1 attribution wording for baseline text in the report footer; T&C/Disclaimer coverage of CLI outputs (counsel).
6. ICP register: technical founder (Skouer) vs non-technical ICP. `(parked; v1 targets technical founders)`
7. Hosted variant. `(out of scope; gated on Art. 28(3) instrument and gdpr-gate)`
9. Roadmap placement and tracking issue: no issue exists yet. The issue-filing gate refused a feature issue with no measurable fix size (0 lines / 0 files is inside the inline threshold) and no mandating rule. File it at plan time, once sized and placed in a roadmap phase (then `wg-every-feature-listed-in-a-roadmap-phase` mandates it). Draft PR #11867 is the tracker until then.
8. Auto-remediation via scaffold skills. `(out of scope for v1; gap findings only name the scaffold)`

## Session Errors

None recorded.
