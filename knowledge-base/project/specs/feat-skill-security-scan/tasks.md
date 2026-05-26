# Tasks: skill-security-scan (#2719)

**Plan:** `knowledge-base/project/plans/2026-05-10-feat-skill-security-scan-plan.md`
**Spec:** `knowledge-base/project/specs/feat-skill-security-scan/spec.md`
**Branch:** `feat-skill-security-scan` | **Worktree:** `.worktrees/feat-skill-security-scan/` | **PR:** #3524

## Phase 0 — Token-budget reclamation (PRECONDITION)

- [ ] 0.1 Read `plugins/soleur/skills/heal-skill/SKILL.md` description; trim to ≤30 words preserving routing intent.
- [ ] 0.2 Read `plugins/soleur/skills/gemini-imagegen/SKILL.md` description; trim to ≤30 words.
- [ ] 0.3 Read `plugins/soleur/skills/discord-content/SKILL.md` description; trim to ≤30 words.
- [ ] 0.4 Read `plugins/soleur/skills/skill-creator/SKILL.md` description; trim to ≤30 words.
- [ ] 0.5 Read `plugins/soleur/skills/changelog/SKILL.md` description; trim to ≤30 words.
- [ ] 0.6 Run `bun test plugins/soleur/test/components.test.ts` — verify cumulative count ≤1769 (≥30 word headroom for the new skill description).
- [ ] 0.7 Fallback: if trim cannot recover 30 words without losing routing fidelity, raise `SKILL_DESCRIPTION_WORD_BUDGET` line 12 from 1800 → 1850 with comment citing #2719.

## Phase 1 — Skill scaffold + LICENSES + knowledge-base/security/

- [ ] 1.1 Create directory tree: `plugins/soleur/skills/skill-security-scan/{scripts,references/{rules,test-fixtures}}/`.
- [ ] 1.2 Write `plugins/soleur/skills/skill-security-scan/SKILL.md` with frontmatter (name, ≤30w description) + MIT attribution comment in body + reference link conventions.
- [ ] 1.3 Create `LICENSES/skill-security-auditor.MIT.txt` with verbatim MIT text + Copyright (c) 2025 Alireza Rezvani.
- [ ] 1.4 Create `knowledge-base/security/skill-overrides/.gitkeep`.
- [ ] 1.5 Stub all script files (`#!/usr/bin/env bash`, `set -euo pipefail`, TODO marker per Phase 2.x).
- [ ] 1.6 Write `references/override-artifact-schema.json` (frontmatter validation schema).
- [ ] 1.7 Write `references/first-party-skill-exceptions.yaml` (empty seed, documented format).
- [ ] 1.8 Run `bun test plugins/soleur/test/components.test.ts` — verify new skill description registered and budget OK.

## Phase 2 — Detection scripts (parallelizable after Phase 1)

### Phase 2.1 — Code-execution category

- [ ] 2.1.1 Write `scripts/check-codeexec.sh` (semgrep generic + targeted regex).
- [ ] 2.1.2 Write `references/rules/code-exec.yaml` (semgrep rules, languages: [generic, bash]).
- [ ] 2.1.3 Add `references/regex-patterns.md` section documenting code-exec regexes.
- [ ] 2.1.4 Write fixture `references/test-fixtures/malicious-codeexec.skill.md`.

### Phase 2.2 — Prompt-injection category

- [ ] 2.2.1 Write `scripts/check-prompt-injection.sh` with frontmatter parser + body proximity-gate.
- [ ] 2.2.2 Write `references/rules/frontmatter.yaml` (high-precision rules).
- [ ] 2.2.3 Write `references/rules/body.yaml` (generic-mode + Soleur prose allowlist).
- [ ] 2.2.4 Add `references/regex-patterns.md` section documenting prompt-injection patterns + Soleur allowlist.
- [ ] 2.2.5 Write fixture `references/test-fixtures/malicious-prompt-injection.skill.md`.

### Phase 2.3 — Supply-chain category

- [ ] 2.3.1 Write `scripts/check-supply-chain.sh` with osv.dev batch query + ecosystem allowlist + REVIEW-on-unknown.
- [ ] 2.3.2 Write `references/typosquat-targets.yaml` (top-1k packages list).
- [ ] 2.3.3 Implement OSV untrusted-input handling (schema validation, body-size cap, network-error-as-REVIEW).

### Phase 2.4 — Filesystem boundary category

- [ ] 2.4.1 Write `scripts/check-filesystem-boundary.sh` (semgrep generic + targeted regex).
- [ ] 2.4.2 Write `references/rules/filesystem-boundary.yaml`.

### Phase 2.5 — Telemetry surface category

- [ ] 2.5.1 Write `scripts/check-telemetry-surface.sh` with URL-host-aware allowlist (R14 mitigation).
- [ ] 2.5.2 Write `references/first-party-allowlist.yaml` (Soleur-owned domains + utm campaigns enumerated from `social-distribute` + `brainstorm`).
- [ ] 2.5.3 Write `references/redirect-domains.yaml` (vendor redirect/tracking domain list).
- [ ] 2.5.4 Write fixture `references/test-fixtures/malicious-telemetry-beacon.skill.md`.
- [ ] 2.5.5 Write fixture `references/test-fixtures/clean-soleur-style.skill.md` (must NOT trip allowlist).
- [ ] 2.5.6 Write fixture `references/test-fixtures/clean-third-party.skill.md`.

## Phase 3 — Verdict aggregator + disclaimer + .scan-meta.json

- [ ] 3.1 Write `scripts/run-scan.sh` orchestrator (parallel xargs, max-severity aggregation, WARN tier as finding-level metadata).
- [ ] 3.2 Write `references/disclaimer.md` (mandatory advisory disclaimer text per CLO Decision 1).
- [ ] 3.3 Write `references/scan-meta-schema.json` (validates `.scan-meta.json` shape).
- [ ] 3.4 Implement PII redaction pass (email/IP/IBAN-shape) before serializing `findings_summary` → `.scan-meta.json`.
- [ ] 3.5 Append disclaimer footer in aggregator only (single-point insertion).

## Phase 4 — Override mechanism (artifact-only, trailer dropped)

- [ ] 4.1 Write `scripts/parse-override.sh` (artifact-diff scanner, schema validator, freshness checker).
- [ ] 4.2 Write `references/override-mechanism.md` (operator docs, retention policy, lawful basis citations, future-extension /plan-mode note).

## Phase 5 — Self-defense

- [ ] 5.1 Write `references/rules/manifest.yaml` with per-file SHA pins + semgrep-version pin (R13 mitigation).
- [ ] 5.2 Implement SHA self-check in `run-scan.sh` (fail-closed REVIEW on tamper).
- [ ] 5.3 Write `scripts/run-self-test.sh` with `--regenerate-manifest` flag (CI strict-mode rejects flag).
- [ ] 5.4 Write `plugins/soleur/test/skill-security-scan.test.ts` (per-category fixture tests + E2E + calibration corpus check).

## Phase 6 — REMOVED per plan review

- [ ] 6.1 Document /plan-mode rationale in `references/override-mechanism.md` "Future extensions" section (not implemented in v1).

## Phase 7 — Calibration against existing Soleur skills

- [ ] 7.1 Run `run-scan.sh` over every `plugins/soleur/skills/**/SKILL.md` corpus.
- [ ] 7.2 Identify FPs; populate `references/regex-patterns.md` Soleur prose allowlist + `references/first-party-allowlist.yaml`.
- [ ] 7.3 Re-run until 0% HIGH-RISK + <5% REVIEW on first-party.
- [ ] 7.4 Implement detailed failure-message format in test (lists ALL offenders with inline JSON findings).
- [ ] 7.5 Write `.github/workflows/skill-security-scan-corpus.yml` (continuous CI smoke test on push to main + on rule-pack PRs).

## Phase 8 — Integration into skill-creator

- [ ] 8.1 Edit `plugins/soleur/skills/skill-creator/SKILL.md` Step 5 — add post-validation invocation of `skill-security-scan`.
- [ ] 8.2 Add `references/override-mechanism.md` link in skill-creator Step 5.
- [ ] 8.3 Test: scaffold deliberately-malicious test skill via skill-creator → scanner blocks the package step.

## Phase 9 — Integration into agent-finder + PreToolUse hook (load-bearing)

- [ ] 9.1 Edit `plugins/soleur/agents/engineering/discovery/agent-finder.md` insert §4b.5 (cooperative-fast-path).
- [ ] 9.2 Verify in-memory invariant: no disk writes between line 117 and line 148 (SpecFlow Gap 6).
- [ ] 9.3 Write `.claude/hooks/skill-security-scan-write.sh` (PreToolUse load-bearing gate — Kieran P0-1 fix).
- [ ] 9.4 Edit `.claude/settings.json` to add PreToolUse matcher for Write tool with `^\.claude/(skills|agents)/.+\.md$` filePathMatcher.
- [ ] 9.5 Test: agent-prose-injection fixture demonstrates hook fires regardless of agent cooperation.

## Phase 10 — Lefthook + CI gates (4 layers total)

- [ ] 10.1 Write `.claude/hooks/skill-security-scan.sh` (lefthook commit-time advisory, Layer B).
- [ ] 10.2 Add `lefthook.yml` stanza `skill-security-scan-advisory` (priority 7, array-of-globs, gobwas-safe per `2026-03-21-lefthook-gobwas-glob-double-star.md`).
- [ ] 10.3 Write `.github/workflows/skill-security-scan-pr-trailer.yml` (Layer C — pre-merge required check).
- [ ] 10.4 Write `.github/workflows/skill-security-scan-postmerge.yml` (Layer D — post-merge audit + auto-file compliance/critical on bypass).
- [ ] 10.5 Configure `main` branch protection to require `skill-security-scan-pr-trailer` status check (R15 mitigation). Verify via `gh api repos/jikig-ai/soleur/branches/main/protection`.

## Phase 11 — Documentation site + roadmap + compliance posture

- [ ] 11.1 Edit `plugins/soleur/docs/_data/skills.js` — add `"skill-security-scan"` to `SKILL_CATEGORIES["Review & Planning"]` array.
- [ ] 11.2 Edit `plugins/soleur/README.md` — bump skill count, add table row.
- [ ] 11.3 Edit `knowledge-base/legal/compliance-posture.md` Active Items append + Vendor DPAs row for osv.dev (per gdpr-gate `GDPR-ChapterV-1`).
- [ ] 11.4 Edit `docs/legal/disclaimer.md` — append automated-tooling clause.
- [ ] 11.5 Edit `knowledge-base/product/roadmap.md` row 4.11 status: `Brainstormed → Planned`.

## Phase 12 — Acceptance verification

- [ ] 12.1 All 16 E2E test scenarios pass (per plan Test Scenarios table).
- [ ] 12.2 Per-category fixture matrix passes (5 fixtures × 5 categories).
- [ ] 12.3 Calibration corpus check passes (0% HIGH-RISK, <5% REVIEW on first-party).
- [ ] 12.4 PII redaction test passes (Sentry + .scan-meta.json both redact `author@example.com`).
- [ ] 12.5 Branch protection check verified.
- [ ] 12.6 `bun test plugins/soleur/test/components.test.ts` passes (no budget regression).
- [ ] 12.7 `bun test plugins/soleur/test/skill-security-scan.test.ts` passes.
- [ ] 12.8 Verdict-name guard grep returns zero matches in non-comment lines.

## Out-of-scope deferrals — file as follow-up issues

- [ ] D1 LLM second-pass deep-mode (`/scan-on-demand`).
- [ ] D2 Runtime sandbox for installed skills.
- [ ] D3 Cross-skill dependency graph analysis.
- [ ] D4 SARIF output format support.
- [ ] D5 Telemetry/SIEM integration for scan-result aggregation.
- [ ] D6 Soleur Cloud UX surfaces for scan results.
- [ ] D7 `/soleur:scan-on-demand` skill for manual rescans.
- [ ] D8 `--no-redact` forensic-mode env flag for override-mechanism.md.
- [ ] D9 (if /plan-aware mode is needed in future) Re-evaluate Phase 6 design.

## Pre-merge AC summary checklist

(Mirror of plan AC; check off as each phase completes)

- [ ] Phase 0 budget reclamation
- [ ] Phase 1 scaffold
- [ ] Phase 2 (5 categories)
- [ ] Phase 3 aggregator + disclaimer + redaction
- [ ] Phase 4 override mechanism (artifact-only)
- [ ] Phase 5 self-defense
- [ ] Phase 6 REMOVED (documented only)
- [ ] Phase 7 calibration + CI smoke
- [ ] Phase 8 skill-creator integration
- [ ] Phase 9a cooperative + 9b PreToolUse
- [ ] Phase 10 hooks + CI + branch protection
- [ ] Phase 11 docs + compliance posture
- [ ] Phase 12 final verification
- [ ] PR body has `## Changelog` + `Closes #2719` + `semver:minor` label
- [ ] CPO sign-off confirmed
- [ ] GDPR-gate findings folded in (5 Suggestions)
