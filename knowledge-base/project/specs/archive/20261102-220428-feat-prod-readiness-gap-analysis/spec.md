---
title: Production-readiness checklist and best-practice gap analysis for customer repos
feature: feat-prod-readiness-gap-analysis
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-11-02-prod-readiness-gap-analysis-brainstorm.md
draft_pr: 11867
---

# Spec: Production-readiness and best-practice gap analysis

## Problem Statement

Customers who arrive with an existing GitHub repo and an MVP (first: alpha tester Skouer) have no way to learn what stands between their MVP and opening to their own customers, nor which of Soleur's engineering guardrails their repo lacks. `/soleur:sync` bootstraps a knowledge-base but does not judge readiness, and `verification-scaffold` installs four guards without auditing for their absence.

## Goals

- G1. Produce production-readiness findings across four domains: Security & secrets; Tests & CI/CD; Tech debt & architecture; Reliability, performance & ops.
- G2. Produce a Soleur best-practice gap report, each gap mapped to the scaffold skill that closes it.
- G3. Keep one living report file in the customer's `knowledge-base/`; re-runs diff against the previous run and tick closed gaps.
- G4. Create an epic with severity-ranked, domain-labeled sub-issues in the customer's repo, confirm-gated and deduplicated.
- G5. Validate on this repo (dry-run, self-test) and then on Skouer's repo run by the tester on their own key.

## Non-Goals

- Hosted/web-platform variant (gated on an Art. 28(3) instrument, gdpr-gate, C5 #7347).
- Auto-remediation (gap findings only name the scaffold skill).
- A single readiness score, certification wording, or benchmarking.
- Any telemetry or "share your report" path back to Jikigai.
- A `/soleur:sync` area or a new command.
- Compliance verdicts (GDPR/SOC2 items are "engineering signal" only).

## Functional Requirements

- FR1. A new read-only skill; the analysis writes only the report file. Operator-invoked or model-invocable decided at plan time against the description word cap.
- FR2. Deterministic scanner gathers facts (CI workflows, hook registration, lockfile/Dependabot, test-to-source ratio, SOLEUR-DEBT markers, guard presence, secrets via gitleaks); an LLM step judges architecture and synthesizes. Every LLM finding cites a deterministic evidence line.
- FR3. Baseline manifest ships inside `plugins/soleur/`, extends the `guards.tsv` precedent, and is derived/verified by a CI test (no hand-listed inventory).
- FR4. Each finding carries domain label, severity (rubric defined at plan time), evidence `path:line`, and (for baseline gaps) the closing scaffold skill.
- FR5. Report is one living markdown file; re-run diffs against the previous run and ticks closed gaps.
- FR6. Issue creation: preview of the epic and sub-issues, create only on explicit customer confirm, idempotent on re-run (dedupe key per gap id). `--dry-run` creates nothing.
- FR7. Standing banner in every report (scope and excluded files, absence of findings is not assurance, not a security audit/legal advice/certification, AI-generated); banned words: certified, compliant, passed, production-ready.
- FR8. Footer attribution for baseline text (wording per counsel).
- FR9. Self-test: run on jikig-ai/soleur in dry-run; baseline-gap findings are triaged into real Soleur gaps vs baseline false positives before Skouer's run.
- FR10. Add a "was this useful?" question to the cohort checkpoint for the Skouer run.

## Technical Requirements

- TR1. Reuse the `code-to-prd` walker: `git ls-files` only; deny `.env*`, `*.pem`, `*.key`, `credentials.*`, `.git/**`, tfstate/tfvars, symlinks; additionally never read DB dumps, fixtures or CSVs; read env var names only.
- TR2. Redaction (redact-sentinel/gitleaks) runs on the report and on every issue body before write; a hit aborts the write. Findings cite `path:line`, never content, and never quote personal data.
- TR3. All content the skill needs ships in the plugin payload (not `.claude/hooks/` or repo-root `scripts/`), per the #7442 packaging boundary; producers are presence-guarded and identity-anchored.
- TR4. Verify every capability the generated output depends on (sub-issues API on the customer's plan, label creation, `gh` auth) and label unbuilt pieces "planned".
- TR5. Any advisory phase carries a machine-enforced promotion/expiry trigger.
- TR6. Run `soleur:gdpr-gate` on the skill; record an ADR "Baseline manifest for customer gap analysis".
- TR7. No Jikigai-keyed run against tester content until the Art. 28(3) instrument exists (condition C1); re-run the controller/processor determination (C9) before tester #2.

## Open Questions

See the brainstorm: skill name and invocation mode, baseline portability scope, severity rubric, GitHub sub-issue mechanics, BUSL-1.1 attribution wording, T&C/Disclaimer coverage of CLI outputs.
