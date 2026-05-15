---
spec: knowledge-base/project/specs/feat-cc-legal-skill-bridge/spec.md
plan: knowledge-base/project/plans/2026-05-15-feat-clo-founder-threshold-detection-plan.md
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Tasks — feat-cc-legal-skill-bridge

Derived from `2026-05-15-feat-clo-founder-threshold-detection-plan.md` after 5-agent plan review.

## Phase 0 — Preconditions

- [ ] **0.1** Read `plugins/soleur/agents/legal/clo.md`, `plugins/soleur/skills/legal-audit/SKILL.md`, `plugins/soleur/commands/go.md` (`hr-always-read-a-file-before-editing-it`).
- [ ] **0.2** Verify gdpr-gate.sh signature with `head -20 plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh` — confirm `{staged_files}` (NOT `--target`) and always-exit-0.
- [ ] **0.3** Confirm legal-audit phase numbering: `grep -nE "^## Phase [0-9]+" plugins/soleur/skills/legal-audit/SKILL.md` returns 0/1/2/3.
- [ ] **0.4** Snapshot `<critical_sequence>` baseline: `sed -n '65,69p' plugins/soleur/skills/legal-audit/SKILL.md > /tmp/critical-sequence-baseline.txt`.
- [ ] **0.5** Verify `knowledge-base/legal/recommended-tools.md` does NOT exist (new-file invariant).

## Phase 1 — `recommended-tools.md`

- [ ] **1.1** Create `knowledge-base/legal/recommended-tools.md` with top-of-file disclaimer (canonical DRAFT pattern; recommendations-page phrasing per plan Phase 2).
- [ ] **1.2** Add 5 H2 sections (anchors: `vendor-msa-review`, `dsar-request`, `ai-vendor-terms`, `oss-license-classification`, `breach-notice-triage`).
- [ ] **1.3** For each H2: 1-paragraph trigger + statutory deadline callout (DSAR + breach only) + tools table with ≥2 rows from plan Phase 1 frozen catalog.
- [ ] **1.4** Add "If you have no retained counsel" sub-paragraph for DSAR / breach / MSA.
- [ ] **1.5** Footer: links to brainstorm + #3786.

## Phase 2 — `clo.md`

- [ ] **2.1** Append "Common founder thresholds" subsection to "### 1. Assess" with 5-row table from plan Phase 1.
- [ ] **2.2** Append Sharp Edges entry "**Re-investigating downstream legal-tool integration**" (brainstorm-verdict pointer + atomic-rename grep reminder).
- [ ] **2.3** Verify `wc -w plugins/soleur/agents/legal/clo.md` ≤ 850.

## Phase 3 — `legal-audit/SKILL.md`

- [ ] **3.1** Edit Phase 0 short-circuit message at `SKILL.md:27` — append catalog pointer per plan Phase 4.
- [ ] **3.2** Append "When to escalate (inline-conversation only)" block at end of Phase 3 Report (after `<critical_sequence>` block, before `## Important Guidelines`).
- [ ] **3.3** Block includes statutory-deadline interpolation rule + dedicated `### Escalation required` H3 with deadline-in-heading + horizontal rules.
- [ ] **3.4** Block includes zero-findings + threshold-in-flight rule (clean audit + regulated-data surfaces present → emit catalog).
- [ ] **3.5** Verify byte-equality: `diff <(sed -n '65,69p' plugins/soleur/skills/legal-audit/SKILL.md) /tmp/critical-sequence-baseline.txt` returns empty.

## Phase 4 — `commands/go.md`

- [ ] **4.1** Add `legal-threshold` intent row to "Step 2: Classify and Route" table above the `default` row.
- [ ] **4.2** Trigger signals: MSA / DSAR / breach / AI vendor terms / OSS license keywords + variants.
- [ ] **4.3** Routes to: `clo` agent (Task spawn).

## Phase 5 — GDPR / Compliance Gate

- [ ] **5.1** Invoke `Skill: soleur:gdpr-gate` against the plan with `target=knowledge-base/project/plans/2026-05-15-feat-clo-founder-threshold-detection-plan.md`.
- [ ] **5.2** If Critical findings: write `compliance-posture.md` Active Items entry + create `compliance/critical`-labeled GitHub issue.
- [ ] **5.3** If no Critical findings: note PASS in PR body.

## Phase 6 — Tests

- [ ] **6.1** Add 10-line vendor-neutrality test to `plugins/soleur/test/components.test.ts` (or sibling `legal-recommended-tools.test.ts`).
- [ ] **6.2** Test asserts: file exists; exactly 5 H2 sections; each followed by table with ≥ 2 rows; no row has claude-for-legal as sole non-empty Tool; anchors in `clo.md` + `legal-audit/SKILL.md` referencing `recommended-tools.md#<anchor>` resolve.
- [ ] **6.3** Run `bun test plugins/soleur/test/components.test.ts` — must pass.
- [ ] **6.4** Run `bun test plugins/soleur/test/gdpr-gate.test.ts` — must pass (no regression on disclaimer invariants).

## Phase 7 — Documentation + close-out

- [ ] **7.1** Read `knowledge-base/legal/compliance-posture.md`. If `clo` Assess inventory references it AND there's a sensible Active Items slot, append one-line entry pointing at `recommended-tools.md`. Otherwise skip.
- [ ] **7.2** Verify README.md legal-doc count (per `plugins/soleur/AGENTS.md` line 23). If `bun run build:docs` available, run + verify.
- [ ] **7.3** Comment on #3786 (NO inline criteria mutation): one-line context note about brainstorm criteria being unobservable; defer revision to real-demand-time.

## Phase 8 — PR finalization

- [ ] **8.1** Update spec.md TR4 already done in plan-revision pass; confirm in `git diff`.
- [ ] **8.2** PR body: `Closes #3785`. `Refs #3786`. `## Changelog` section with `semver:patch`.
- [ ] **8.3** PR body: AC checklist from plan §Acceptance Criteria copy-paste.
- [ ] **8.4** Verify `git diff main -- 'AGENTS*.md' | wc -l` returns 0.
- [ ] **8.5** Mark PR ready (drop draft status).
- [ ] **8.6** Trigger `user-impact-reviewer` agent (per `hr-weigh-every-decision-against-target-user-impact`).
- [ ] **8.7** Capture CPO sign-off — single yes/no on the as-shipped 5-threshold catalog (per `requires_cpo_signoff: true`).

## Post-merge

None. This is a docs+agent-extension+classifier-row PR. No migrations, no infra applies, no Doppler updates.

## Sequencing notes

- Phases 1-4 are independent; can be edited in any order in a single commit.
- Phase 5 (gdpr-gate) runs once per plan revision; can run any time after Phase 0.
- Phase 6 tests gate Phases 1-4 (test verifies them).
- Phase 7 close-out runs last.
- Phase 8 PR finalization is the final commit / push / mark-ready cycle.
