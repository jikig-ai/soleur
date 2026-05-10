---
title: gdpr-gate skill plan
date: 2026-05-10
type: feat
status: ready-for-work
issue: 3502
pr: 3501
branch: feat-compliance-skills-eval
worktree: .worktrees/feat-compliance-skills-eval/
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
adr: ADR-026
brainstorm: knowledge-base/project/brainstorms/2026-05-09-gdpr-gate-skill-brainstorm.md
spec: knowledge-base/project/specs/feat-compliance-skills-eval/spec.md
---

# `gdpr-gate` skill — code-level GDPR/CCPA/HIPAA pre-generation gate

## Overview

Build a Soleur-native plugin skill, **`gdpr-gate`**, that fires inline during `/soleur:plan` and `/soleur:work` to catch regulated-data design gaps **before** code is generated. GDPR-first (Art. 5/6/9/17/20/25/30/32/33/35), with secondary US coverage (CCPA, HIPAA). Output is **advisory-only** with mandatory disclaimer header — the skill never claims legal sign-off. Critical findings (Art. 9 special-category, missing lawful basis, Art. 30 RoPA trigger) are routed to `compliance-posture.md` Active Items via operator-acknowledged write — never auto-write.

The brainstorm + ADR-026 (both complete) chose **Approach B**: lift 5 specific files from [gosprinto/compliance-skills](https://github.com/gosprinto/compliance-skills) (MIT, USA-focus) under attribution and rewrite the regulatory frame around GDPR. The decision cross-cuts `/soleur:plan`, `/soleur:work`, `/soleur:ship`, `/soleur:preflight` (Q1 deferred), `lefthook.yml`, `AGENTS.md`, the brainstorm domain config, and three review-time agents (`data-integrity-guardian`, `security-sentinel`, `clo`).

## Research Reconciliation — Spec vs. Codebase

The repo-research-analyst surfaced 10 gap callouts; this section locks the resolution before phase decomposition so `/work` does not negotiate ambiguity at implementation time.

| # | Gap (spec/ADR claim) | Codebase reality | Plan response |
|---|---|---|---|
| 1 | Spec FR2: gate fires "after TDD GREEN, before REFACTOR" | `/soleur:work` Phase 2 has a per-task RED/GREEN/REFACTOR loop (lines 218-249); per-task firing would violate ADR-026 TR3 (≤4k/invocation, "one pass per phase") | **Choose Phase-2-exit (single pass after all tasks complete, before Phase 2.5).** Rewrite FR2 wording in Phase 1 of this plan. |
| 2 | ADR-026 NFR table labels NFR-027 as "Auditability / observability" | Live `nfr-register.md` line 511: NFR-027 is "Encryption At-Rest" | **Drop NFR-027 row from ADR.** Document gate's auditability via `.claude/hooks/lib/incidents.sh` mention only. ADR amendment task in Phase 2. |
| 3 | ADR-026 NFR table labels NFR-030 as "Data lifecycle / never-delete" | Live register: NFR-030 is "Data Accuracy"; never-delete is **AP-009** (a principle) | **Drop NFR-030 row from ADR**, move never-delete framing into AP-009 alignment rationale. ADR amendment task in Phase 2. |
| 4 | Spec FR2 + ADR-026 lefthook glob `forms/**` | `git ls-files \| grep -E '^forms/'` → **0 matches** | **Drop `forms/**` from active glob.** Document as "forward-looking; current match count zero" in SKILL.md. Violates `hr-when-a-plan-specifies-relative-paths-e-g` if shipped as-is. |
| 5 | Spec FR2 + ADR-026 lefthook glob `**/*.prisma` | 0 matches (repo uses Supabase migrations) | **Drop `**/*.prisma`.** Same rationale as #4. |
| 6 | Spec FR2 + ADR-026 lefthook glob `*auth*` | Matches **104 files** — includes docs, prose, test fixtures, every `lib/auth/` and `server/auth-*` file | **Tighten** to `apps/web-platform/lib/auth/**`, `apps/web-platform/server/*auth*.ts`, `apps/web-platform/app/api/auth/**`. Single canonical regex single-source-of-truth, mirrored verbatim into `lefthook.yml`. |
| 7 | Spec FR6: `auth-sessions`, `frontend`, `testing-seeding` "fold relevant checks into 3 active layers; full layer files defer to v2" | MIT attribution requires NOTICE entries when content is lifted; "folded" is ambiguous about whether the underlying prose is lifted (NOTICE-required) or paraphrased (NOTICE-free) | **Choose: defer entirely to v2.** Don't lift the 3 fold-layer files in v1 — re-lift at v2 against then-current upstream SHAs (better hygiene than carrying stale lifts). v1 NOTICE lists 5 active-layer files only. Spec FR6 + AC line 135 amended in Phase 1. v2 follow-up issue tracks reactivation per AC-PM-2. |
| 8 | Spec FR3: mandatory disclaimer at top of every gate output | No existing skill enforces a top-of-output markdown disclaimer (legal-generate enforces draft markers; legal-audit enforces conversation-only) | **Pattern invention.** Hardcode disclaimer literal in `SKILL.md` `## Output Format` block; add `plugins/soleur/test/gdpr-gate.test.ts` asserting the literal string appears as the first non-blank line of every sample-output fixture. |
| 9 | Spec FR2 + ADR-026: lefthook hook layer "regex-only; only triggers the skill invocation" | No existing lefthook hook in this repo uses "fire skill, don't block" — all hooks either hard-block (gitleaks, rule-id-lint) or autofix (markdown-lint). Closest precedent: `lint-fixture-content` (hard-block) | **Pattern invention.** Hook script `plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh` always `exit 0`, prints one-line advisory to stderr: `gdpr-gate: regulated-data path touched (<glob>); run /soleur:gdpr-gate`. Documented in SKILL.md and Sharp Edges. |
| 10 | Spec FR1: gate invoked at `/soleur:plan` Phase 2.6 "alongside the existing user-impact gate" | Phase 2.6 is `[skill-enforced: brainstorm Phase 0.1, plan Phase 2.6, deepen-plan Phase 4.6, review user-impact-reviewer, preflight Check 6]` — adding to it risks confusing rule-tag readers | **Add as new Phase 2.7** (between User-Brand Impact at 2.6 and SpecFlow at 3). Preserves existing skill-enforced rule-tag invariants. Spec FR1 wording amended in Phase 1. |

## User-Brand Impact

**If this lands broken, the user experiences:** a Critical finding silently swallowed by a hook that exits 0 without printing — operator ships a schema with `medical_history` (Art. 9 special-category) and the regulator-complaint-shaped failure surfaces only when a real DSAR or audit lands in production.

**If this leaks, the user's PII is exposed via:** the Haiku invocation transmitting diff content (which may contain real `medical_history`/`health_data` column names plus seeded fixture-shaped values) over HTTPS to Anthropic — the model context itself becomes a cross-border processing event the gate is supposed to catch in others.

**Brand-survival threshold:** `single-user incident` (carry-forward from brainstorm + spec).

CPO sign-off: required at plan time. **Status:** carried forward from brainstorm `## Domain Assessments` (CPO already assessed). **Action:** Phase 0 of this plan re-confirms by re-reading brainstorm CPO assessment line; no new CPO Task is spawned (avoids re-asking the framing question already answered).

`user-impact-reviewer`: required at `/review` time. Phase 5 of this plan invokes it as a conditional review agent. The reviewer is expected to enumerate failure modes by **role**, not by surface, per `2026-05-06-user-impact-section-by-role-not-surface.md`:

- **Operator running gdpr-gate** — false-confidence risk if the disclaimer is removed or the gate is bypassed; remediation: skill-test asserting disclaimer literal + AGENTS.md `[skill-enforced]` tag.
- **Authenticated app user whose PII is the subject of a Critical finding** — exposure if Haiku request body leaks special-category column names to a non-EU vendor; remediation: gate sends column **names** only, never **values** (asserted in skill test); request transcript redaction documented in Sharp Edges.
- **Legal-doc signer (DPA counter-party)** — implicit DPA breach if the gate's vendor-DPA list embeds a stale carry-forward; remediation: vendor-DPA list operator-managed, references `compliance-posture.md` Active Items live, never hardcoded.

## Domain Review

**Domains relevant:** Product, Legal, Engineering, Marketing (carry-forward from brainstorm — CPO/CLO/CTO/CMO already assessed; remaining domains skipped as not relevant for code-level compliance skill).

### Product (CPO) — carry-forward

**Status:** reviewed (carry-forward from brainstorm 2026-05-09).
**Assessment:** Ship now, scope-down. MVP = 3 layers + 4 regs + 5 GDPR checks. Highest risk is false-sense-of-compliance — non-negotiable disclaimer + advisory-only output + no pass/fail verdict.

### Legal (CLO) — carry-forward

**Status:** reviewed (carry-forward from brainstorm 2026-05-09).
**Assessment:** Soleur-native from scratch with selective MIT lifts. v1 must cover lawful basis + retention + DSAR + cross-border + Art. 9. Conversation-only output by default; Critical findings route to `compliance-posture.md` Active Items via operator-acknowledged write.

### Engineering (CTO) — carry-forward

**Status:** reviewed (carry-forward from brainstorm 2026-05-09).
**Assessment:** Plan-phase skill + work-phase hook, batched not streamed (≤4k tokens/invocation, Haiku). Plugin-native distribution; layer files in `references/`. Gate is read-only auditor of canonical `/plan` template — never injects, to avoid gate-vs-template collision.

### Marketing (CMO) — carry-forward

**Status:** reviewed (carry-forward from brainstorm 2026-05-09).
**Assessment:** Name it `gdpr-gate`, not `pii-gate`. Strong content opportunity: blog post "Why we built our own PII gate instead of bundling Sprinto's" + HN/IndieHackers distribution. **CMO content-opportunity gate fires at /ship Phase 5.5** (already enforced by `hr-before-shipping-ship-phase-5-5-runs`).

### Product/UX Gate

**Tier:** none (mechanical escalation passes — no new files match `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`).
**Decision:** N/A (skill is conversational; no UI surface).

**Brainstorm-recommended specialists:** none (CPO/CLO/CTO/CMO assessments did not name additional specialists; copywriter is gated by /ship Phase 5.5 CMO content-opportunity gate, not plan-time).

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1** — `plugins/soleur/skills/gdpr-gate/SKILL.md` exists, ≤500 lines, written from scratch in Soleur voice, frontmatter `name: gdpr-gate` + `description:` ≤30 words ≤300 chars.
- [x] **AC2** — `plugins/soleur/skills/gdpr-gate/NOTICE` exists, lists 5 lifted active-layer files with upstream commit SHA `7b58d68461cb1fc033a063e34cc9de63d0b4144b` (verified at plan time, 2026-05-10) and per-file blob SHAs from §Research Insights table.
- [x] **AC3** — `plugins/soleur/skills/gdpr-gate/references/` contains 5 lifted active-layer files: `fields.md`, `leakage-vectors.md`, `layers/api-layer.md`, `layers/data-in-transit.md`, `layers/data-lifecycle.md`. Plus 2 written-from-scratch: `non-negotiables.md`, `legal-consent.md`. The 3 fold-layer files (`auth-sessions.md`, `frontend.md`, `testing-seeding.md`) are NOT lifted in v1 — deferred to the v2 follow-up issue per AC-PM-2.
- [x] **AC4** — Each lifted file (5 files) carries the literal header `<!-- Adapted from gosprinto/compliance-skills (MIT) — see NOTICE -->` as line 1.
- [x] **AC5** — Vendor-surface scrub: `rg -i 'sprinto\.com\|utm_source=Claude\|powered by sprinto\|sprinto logo' plugins/soleur/skills/gdpr-gate/` returns zero hits (the only allowed reference to "sprinto" is in `NOTICE` and per-file attribution headers).
- [x] **AC6** — `plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh` exists, `set -euo pipefail`, sources `.claude/hooks/lib/incidents.sh`, `exit 0` always (advisory). Prints to stderr: `gdpr-gate: regulated-data path touched (<staged-file>); run /soleur:gdpr-gate`.
- [x] **AC7** — `lefthook.yml` adds a `gdpr-gate-advisory` pre-commit hook with `priority: 6`, glob array (single canonical regex mirrored from §TR4 below), `run: bash plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh {staged_files}`. Verified via `lefthook run pre-commit` against a fixture with one matched path and one unmatched path.
- [x] **AC8** — `plugins/soleur/skills/plan/SKILL.md` adds **Phase 2.7: GDPR / Compliance Gate** between Phase 2.6 (User-Brand Impact) and Phase 3 (SpecFlow). Phase rule references `[skill-enforced: gdpr-gate at plan Phase 2.7]`.
- [x] **AC9** — `plugins/soleur/skills/work/SKILL.md` adds a single-pass gate invocation at the end of Phase 2 (after the per-task RED/GREEN/REFACTOR loop completes, before Phase 2.5). Rule reference: `[skill-enforced: gdpr-gate at work Phase 2 exit]`.
- [x] **AC10** — `plugins/soleur/skills/ship/SKILL.md` adds a `gdpr-gate critical-finding-acknowledgment` conditional gate block to Phase 5.5, slotted between COO Expense-Tracking Gate and Deploy Pipeline Fix Drift Gate. Trigger condition: PR diff matches the canonical lefthook regex AND any open issue with label `compliance/critical` is referenced (`Closes #N` or `Ref #N`) by this PR's body.
- [x] **AC11** — `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md` extends CLO's Task Prompt with: "If the feature involves PII, schemas, auth, forms, or API routes touching regulated data, recommend invoking `/soleur:gdpr-gate` during plan Phase 2.7 and work Phase 2 exit."
- [x] **AC12** — `AGENTS.md` adds ONE new Hard Rule, `[id: hr-gdpr-gate-on-regulated-data-surfaces]`, ≤600 bytes, with `[hook-enforced: lefthook gdpr-gate.sh]` and `[skill-enforced: plan Phase 2.7, work Phase 2 exit]` tags. Rule body verified against placement gate (`cq-agents-md-tier-gate`): cross-cutting session invariant, hidden-constraint flavor (silent failure mode = swallowed Critical finding). Pre-flight: `wc -c AGENTS.md` after edit ≤37000 bytes.
- [x] **AC13** — `plugins/soleur/skills/review/SKILL.md` adds `gdpr-gate` to the conditional-agent block (fires when diff matches the canonical regex). **Canonical boundary disambiguation prose lives here only:** "Use `gdpr-gate` for deterministic Art. 9 / RoPA / lawful-basis pattern checks; use `data-integrity-guardian` for migration safety and judgment-based PII review; use `security-sentinel` for OWASP/CWE security-of-processing flaws."
- [x] **AC14** — `plugins/soleur/agents/engineering/review/data-integrity-guardian.md` adds a single-line cross-reference: "Boundary vs gdpr-gate: see `plugins/soleur/skills/review/SKILL.md` §boundaries." (Single source of truth — full prose lives in review/SKILL.md per AC13.)
- [x] **AC15** — `plugins/soleur/agents/engineering/review/security-sentinel.md` adds the same single-line cross-reference (single source of truth in review/SKILL.md).
- [ ] **AC16** — DROPPED. CLO already reads `compliance-posture.md`; the row schema lives in that file's header per AC23. No edit to `clo.md`.
- [x] **AC17** — `plugins/soleur/skills/legal-audit/SKILL.md` adds a one-sentence note: "If `gdpr-gate` flags a new PII column (Art. 9 or otherwise), run this skill against the privacy policy to verify disclosure."
- [x] **AC18** — ADR-026 amended (in this same PR): drop NFR-027 row, drop NFR-030 row from NFR Impacts table; move "never-delete user data" framing into AP-009 alignment rationale; add an "Amendments" section dated 2026-05-10 logging the reconciliation. ADR `status` stays `active`.
- [ ] **AC19** — `plugins/soleur/skills/preflight/SKILL.md` — **NO CHANGE.** Q1 (preflight Check 7) deferred to v2; Phase 2 of this plan files a tracking issue milestoned to "Post-MVP / Later" titled "Add gdpr-gate as preflight Check 10 (Q1 follow-up)".
- [x] **AC20** — `plugins/soleur/test/gdpr-gate.test.ts` exists and asserts: (a) disclaimer literal as first non-blank line of fixture output; (b) sample output for each of the 5 v1 GDPR checks (FR4) — **Critical reserved for Art. 9 column-name matches only; unannotated lawful-basis/retention/DSAR/cross-border findings are Important, not Critical** (per Kieran-review HIGH finding: zero existing migrations carry `LAWFUL_BASIS` annotations, so Critical on every column would create noise that trains operators to dismiss); (c) Critical-finding flow prompts operator and does not write to `compliance-posture.md`; (d) Haiku request body sends column **names** only, never values (regex check on the prompt template); (e) lefthook glob regex matches sample paths from the canonical regex inventory at §TR4 below and rejects unrelated paths.
- [x] **AC21** — `plugins/soleur/test/components.test.ts` passes — gate's description fits inside the cumulative ≤1800-word budget. **Pre-flight measurement at plan time (2026-05-10): cumulative ~1614 words; ~186 words headroom; gate description targets ≤30 words.** No sibling-skill description trim required.
- [x] **AC22** — Run `scripts/sync-readme-counts.sh` to update `plugins/soleur/README.md` automatically (per `2026-04-02-readme-count-sync-automation.md`). No manual row edit. Verify the script's diff lands the new `gdpr-gate` row in the appropriate subsection.
- [x] **AC23** — `knowledge-base/legal/compliance-posture.md` — **NO row write at this stage.** This file is the runtime escalation target; the gate writes to it ONLY at runtime when a Critical finding fires AND the operator acknowledges. Plan-time touch: header comment documenting the row schema (mirrors AC16's CLO contract).
- [x] **AC24** — Token budget verified in `plugins/soleur/test/gdpr-gate.test.ts` against a synthesized in-test fixture (10 schema rows including 1 Art. 9 hit + plan excerpt ≤2k chars; column names like `medical_history`, `email`, `audit_log` — all synthesized per `cq-test-fixtures-synthesized-only`). Assertion: Anthropic SDK `response.usage.input_tokens ≤ 4000` AND `response.usage.output_tokens ≤ 1500`. **No committed sample-haiku-run.md fixture artifact** (per Simplicity-review #8: live in-test assertion subsumes captured artifact and avoids a gitleaks waiver surface).
- [ ] **AC25** — Multi-agent review fan-out at `/review` time (Phase 5 of this plan) includes `user-impact-reviewer` (carry-forward from `brand_survival_threshold: single-user incident`) and the new `gdpr-gate` self-invocation (review/SKILL.md routing per AC13).
- [x] **AC26** — All AGENTS.md rule-IDs cited in the new SKILL.md prose, AGENTS.md rule, ADR amendment, and tests are grep-verified against `AGENTS.md` AND `scripts/retired-rule-ids.txt`. **No fabricated or retired IDs** (per `2026-05-09-llm-authored-plans-cite-fabricated-and-retired-rule-ids.md`). Verification command in /work checklist.
- [ ] **AC27** — `Ref #3502` (NOT `Closes #3502`) appears in the PR body — issue stays OPEN until the v2 follow-up issues (Q1 preflight, Q3 vendor re-pin policy) land. Auto-close keywords scanner (`wg-use-closes-n-in-pr-body-not-title-to`) verified clean.

### Post-merge (operator)

- [ ] **AC-PM-1** — `compliance-posture.md` `last_updated` frontmatter updated to 2026-05-10 (or merge date) reflecting the new gate-write contract surface. Header comment + row schema added (mirrors AC23). One commit on `main`.
- [ ] **AC-PM-2** — Three v2 follow-up issues filed (per Deferral Tracking checklist below), milestoned to "Post-MVP / Later":
    - "Add gdpr-gate as preflight Check 10 (Q1 follow-up)" (label: `domain/engineering`, `priority/p3-low`)
    - "Define version-pin policy for lifted Sprinto files (Q3 follow-up)" (label: `domain/legal`, `priority/p3-low`)
    - "Implement gdpr-gate v2 layers: auth-sessions, frontend, testing-seeding, legal-consent + repo-scan mode" (label: `domain/engineering`, `priority/p3-low`)
- [ ] **AC-PM-3** — `gh workflow run plugin-component-test.yml` succeeds (lefthook + components-test). New workflow gate (none added — only edited `lefthook.yml` is exercised by the existing `pre-commit` lefthook job, no separate workflow).
- [ ] **AC-PM-4** — One smoke-test gate invocation against a real (non-fixture) diff: `git checkout main && /soleur:gdpr-gate "audit knowledge-base/project/specs/feat-compliance-skills-eval/spec.md"` returns the disclaimer + zero Critical findings (the spec itself does not introduce regulated-data surfaces).

## Files to Edit

| Path | Change |
|---|---|
| `plugins/soleur/skills/plan/SKILL.md` | Add Phase 2.7: GDPR / Compliance Gate (between 2.6 and 3) |
| `plugins/soleur/skills/work/SKILL.md` | Add single-pass gate invocation at end of Phase 2 (before Phase 2.5) |
| `plugins/soleur/skills/ship/SKILL.md` | Add `gdpr-gate critical-finding-acknowledgment` gate to Phase 5.5 |
| `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md` | Extend CLO Task Prompt to recommend gdpr-gate |
| `plugins/soleur/skills/review/SKILL.md` | Add gdpr-gate to conditional-agent block + boundary disambiguation prose |
| `plugins/soleur/skills/legal-audit/SKILL.md` | Add cross-reference note (re-run on Art. 9 finding) |
| `plugins/soleur/agents/engineering/review/data-integrity-guardian.md` | Add one-line cross-reference (canonical prose in review/SKILL.md) |
| `plugins/soleur/agents/engineering/review/security-sentinel.md` | Add one-line cross-reference (canonical prose in review/SKILL.md) |
| `plugins/soleur/README.md` | Run `scripts/sync-readme-counts.sh` (auto-row insertion; no manual edit) |
| `AGENTS.md` | Add ONE Hard Rule `[id: hr-gdpr-gate-on-regulated-data-surfaces]` |
| `lefthook.yml` | Add `gdpr-gate-advisory` pre-commit hook |
| `knowledge-base/engineering/architecture/decisions/ADR-026-pii-gate-as-plan-work-phase-skill-with-diff-hook.md` | Amendments section: drop NFR-027/NFR-030 rows, move never-delete framing to AP-009 |
| `knowledge-base/legal/compliance-posture.md` | Header comment documenting Active Items row schema (no row write) |

## Files to Create

| Path | Purpose | Source |
|---|---|---|
| `plugins/soleur/skills/gdpr-gate/SKILL.md` | Soleur-voice dispatch, ≤500 lines | Written from scratch |
| `plugins/soleur/skills/gdpr-gate/NOTICE` | MIT attribution, 8 lifted-file rows + upstream commit SHA pin | Written from scratch |
| `plugins/soleur/skills/gdpr-gate/references/fields.md` | PII field catalogue + Art. 9 special-category extension | Lifted (3,844 bytes) + EU extension |
| `plugins/soleur/skills/gdpr-gate/references/leakage-vectors.md` | Vector catalogue | Lifted verbatim (5,880 bytes) |
| `plugins/soleur/skills/gdpr-gate/references/non-negotiables.md` | GDPR Art. 5/6/9/25/32 first-class | Written from scratch (CCPA + HIPAA secondary) |
| `plugins/soleur/skills/gdpr-gate/references/legal-consent.md` | ePrivacy + Art. 7/13/14/35 | Written from scratch |
| `plugins/soleur/skills/gdpr-gate/references/layers/api-layer.md` | 7 checks (AP-01..AP-07) | Lifted verbatim (9,132 bytes) |
| `plugins/soleur/skills/gdpr-gate/references/layers/data-in-transit.md` | 6 checks + Chapter V cross-border | Lifted (7,273 bytes) + EU extension |
| `plugins/soleur/skills/gdpr-gate/references/layers/data-lifecycle.md` | 6 checks + Sweeney 87% re-id; DL-04 → Art. 20 + CCPA | Lifted (9,567 bytes) + EU rewrite |
| `plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh` | Lefthook advisory hook (always exit 0) | Written from scratch |
| `plugins/soleur/test/gdpr-gate.test.ts` | Skill assertions: disclaimer, 5 checks (Critical reserved for Art. 9), Haiku body, token budget, glob coverage | Written from scratch |

**Deferred to v2 follow-up** (per AC-PM-2 — applied review-fix #1):
- `plugins/soleur/skills/gdpr-gate/references/layers/auth-sessions.md` (re-lift at v2 with fresh upstream SHA)
- `plugins/soleur/skills/gdpr-gate/references/layers/frontend.md`
- `plugins/soleur/skills/gdpr-gate/references/layers/testing-seeding.md`

## Open Code-Review Overlap

Verified via `gh issue list --label code-review --state open` against each planned file path. **None of the open code-review issues touch the file content this plan modifies.**

| Open issue | Touches file path? | Disposition |
|---|---|---|
| #3392 / #3373 / #3372 / #3160 / #3002 | Match `AGENTS.md` only as substring (rule citations); not the rule space gdpr-gate adds | **Acknowledge** — orthogonal scope-outs; gate's new `[id: hr-gdpr-gate-on-regulated-data-surfaces]` is in a different namespace |
| #3322 (lefthook lint-fixture-content glob extension) | Edits `lefthook.yml` but a different hook entirely | **Acknowledge** — independent hook; merge-order-safe |

## Hypotheses

(Section reserved per plan template; no SSH/network-outage hypotheses apply — feature is a code-level gate, not a connectivity remediation. Step 1.4 trigger patterns do not match.)

## Implementation Phases

### Phase 1 — Preconditions + skill scaffold + lifted-file vendor scrub (TDD RED, ~4-5 hrs)

**Goal:** Lock §Research Reconciliation reconciliations, verify carry-forward + budgets, then land the skill directory with frontmatter, 5 lifted files (with attribution headers + scrub), NOTICE, and the FIRST FAILING TEST.

**§Preconditions** (~30 min, was prior Phase 0):

1. Re-confirm CPO sign-off carry-forward by reading brainstorm `## Domain Assessments → Product (CPO)` (already done at plan-write; record verbatim quote in `/work` Phase 0 log).
2. Re-measure cumulative skill-description word count at /work start: `bun test plugins/soleur/test/components.test.ts 2>&1 | head -n 80`. Verify ≥30 words headroom remain. If not, halt and file a chore PR to trim sibling descriptions per `2026-04-21-skill-description-budget-at-cap-requires-plan-time-surgery.md`.
3. Re-measure AGENTS.md byte size: `wc -c AGENTS.md`. Verify ≥600 bytes headroom (current: ~12,382 bytes under target).
4. Verify Sprinto upstream commit SHA `7b58d68461cb1fc033a063e34cc9de63d0b4144b` is still reachable: `gh api repos/goSprinto/compliance-skills/commits/7b58d68461cb1fc033a063e34cc9de63d0b4144b --jq .sha`. If the upstream branch has moved, re-pin with the new SHA + per-file blob SHAs and amend NOTICE.
5. Run the lefthook glob audit: `git ls-files | grep -E '^(apps/web-platform/supabase/migrations/|apps/web-platform/(lib|server)/.*auth|apps/web-platform/app/api/|.*\.sql$)' | wc -l` — confirm ≥1 match for each glob.
6. **TDD GATE confirmation:** AC20 (`plugins/soleur/test/gdpr-gate.test.ts`) is the failing-test-before-implementation gate per `cq-write-failing-tests-before`. Phase 1 §Scaffold step ends with a RED test before any SKILL.md prose carries weight.

**§Scaffold + lifted files** (~3-4 hrs):

1. Create `plugins/soleur/skills/gdpr-gate/` directory tree.
2. Write `SKILL.md` with:
   - Frontmatter `name: gdpr-gate`, `description: "This skill should be used when auditing plans, diffs, schemas, migrations, or PII-touching code for GDPR, CCPA, and HIPAA compliance gaps. Advisory-only; never blocks; escalates Critical findings to compliance-posture.md."` (29 words, 226 chars per AC21).
   - Phases (~5 sections): "When to invoke", "Disclaimer (always first)", "5 mandatory v1 checks", "Output format (Critical/Important/Suggestion)", "Critical-finding escalation flow".
   - **Read-only invariant:** explicit prose in SKILL.md that the gate audits the canonical `/soleur:plan` template — NEVER injects its own checklist (per ADR-026 architectural invariant).
   - References to `references/<file>.md` use the markdown-link convention `[layer-name](./references/layers/<file>.md)` per `components.test.ts` line 223-233.
3. Lift the **5 active-layer source files** via `gh api` against pinned commit SHA (the 3 fold-layer files are deferred to v2 per review-fix #1). For each:
   - Save raw content to destination path.
   - Prepend `<!-- Adapted from gosprinto/compliance-skills (MIT) — see NOTICE -->` as the literal first line.
   - Run vendor-surface scrub: `rg -i 'sprinto\.com|utm_source=Claude|powered by sprinto|sprinto logo'` on the lifted file; if hits, manually scrub. (Per brainstorm Lifted Files Inventory, only `pii-detector/README.md` and `pii-detector/modes/repo-scan.md` had vendor surface — neither is being lifted, so scrub should return zero.)
4. Apply EU extensions:
   - `references/fields.md`: append Art. 9 special-category fields (political, religious, union, sexual orientation, genetic).
   - `references/layers/data-in-transit.md`: append Chapter V cross-border transfer check.
   - `references/layers/data-lifecycle.md`: rewrite DL-04 export to GDPR Art. 20 + CCPA.
5. Write from scratch:
   - `references/non-negotiables.md` (GDPR Art. 5/6/9/25/32 first-class, CCPA + HIPAA secondary).
   - `references/legal-consent.md` (ePrivacy + Art. 7/13/14/35).
6. Write `NOTICE` with 5 rows (active layers only — fold-layer rows added at v2 per AC-PM-2):
    ```
    ## gosprinto/compliance-skills (MIT)
    Pinned commit: 7b58d68461cb1fc033a063e34cc9de63d0b4144b (2026-05-08)
    Upstream: https://github.com/goSprinto/compliance-skills

    | Lifted file (Soleur) | Upstream path | Blob SHA | Status |
    |---|---|---|---|
    | references/fields.md | pii-detector/patterns/fields.md | c1bb748... | active (EU-extended) |
    | references/leakage-vectors.md | pii-detector/rules/leakage-vectors.md | 15a46e5... | active (verbatim) |
    | references/layers/api-layer.md | pii-detector/layers/api-layer.md | 9d32021... | active (verbatim) |
    | references/layers/data-in-transit.md | pii-detector/layers/data-in-transit.md | 6c9eeab... | active (EU-extended) |
    | references/layers/data-lifecycle.md | pii-detector/layers/data-lifecycle.md | a073ef2... | active (EU-rewritten) |
    ```
7. **RED:** Write `plugins/soleur/test/gdpr-gate.test.ts` with failing assertions for AC20 (a)-(e). All assertions fail at this point.
8. Run `bun test plugins/soleur/test/components.test.ts` — verify it passes (no regression on word budget).

### Phase 2 — Hook layer + canonical regex + ADR amendment (~2-3 hrs)

**Goal:** Stand up the lefthook advisory hook with the single-source regex; amend ADR-026 in this same PR per the §Research Reconciliation gaps.

1. **Build the canonical regex** from `git ls-files`:
    ```bash
    REGEX='^(apps/web-platform/supabase/migrations/|apps/web-platform/lib/auth/|apps/web-platform/server/.*auth.*\.(ts|tsx|js)|apps/web-platform/app/api/auth/|apps/web-platform/app/api/.*\.(ts|tsx)$|.*\.sql$)'
    ```
    Verify match count ≥1 for each component:
    ```bash
    git ls-files | grep -E "$REGEX" | head -n 50
    ```
    Document the regex inventory in SKILL.md `## Path globs (canonical)` section as the single source of truth.
2. Write `scripts/gdpr-gate.sh`:
    ```bash
    #!/usr/bin/env bash
    set -euo pipefail
    source "$(git rev-parse --show-toplevel)/.claude/hooks/lib/incidents.sh"
    matched=()
    for f in "$@"; do
      if echo "$f" | grep -qE "$REGEX"; then matched+=("$f"); fi
    done
    if (( ${#matched[@]} > 0 )); then
      echo "gdpr-gate: regulated-data path touched (${matched[*]}); run /soleur:gdpr-gate" >&2
    fi
    exit 0
    ```
3. Add `lefthook.yml` entry:
    ```yaml
    gdpr-gate-advisory:
      priority: 6
      glob:
        - "apps/web-platform/supabase/migrations/*.sql"
        - "apps/web-platform/lib/auth/**/*.ts"
        - "apps/web-platform/server/*auth*.ts"
        - "apps/web-platform/app/api/**/*.ts"
        - "*.sql"
      run: bash plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh {staged_files}
    ```
    **gobwas-glob trap (per `2026-03-21-lefthook-gobwas-glob-double-star.md`):** array form keeps both `dir/*.ts` and `dir/**/*.ts` distinct. Verified by `lefthook run pre-commit` against fixture commits.
4. **GREEN partial:** AC6, AC7 pass.
5. Amend `knowledge-base/engineering/architecture/decisions/ADR-026-pii-gate-as-plan-work-phase-skill-with-diff-hook.md`:
   - Drop NFR-027 row from NFR Impacts table.
   - Drop NFR-030 row.
   - Add: `**Auditability/observability:** the gate emits `gdpr-gate-critical-finding` incident telemetry on Critical findings only via `.claude/hooks/lib/incidents.sh`. No new NFR added; covered by the existing telemetry pattern.`
   - Move "never-delete user data" framing into AP-009 alignment rationale: `AP-009 ✓ — gate's DSAR-deletability check (Art. 17) flags missing cascade paths at design time. Gate never deletes data itself.`
   - Append:
        ```
        ## Amendments

        ### 2026-05-10 — NFR table reconciliation (PR #3501)

        Reconciled the NFR Impacts table against live `nfr-register.md` per the implementation plan's Research Reconciliation §3.2/3.3:
        - NFR-027 row dropped (live register: "Encryption At-Rest", not auditability).
        - NFR-030 row dropped (live register: "Data Accuracy", not data-lifecycle).
        - "Auditability/observability" framing moved into the Consequences section as a non-NFR concern.
        - "Never-delete user data" framing moved to AP-009 alignment rationale.

        Status remains `active`.
        ```
6. **GREEN partial:** AC18 passes.

### Phase 3 — Plan / Work / Ship / Brainstorm integration (~3-4 hrs)

**Goal:** Wire the gate into the four invocation surfaces. All edits are prose — no logic changes.

1. **Plan Phase 2.7 (AC8):** edit `plugins/soleur/skills/plan/SKILL.md`. Insert after Phase 2.6 (line ~393) and before Phase 3 (line ~395):
    ```markdown
    ### 2.7. GDPR / Compliance Gate

    [skill-enforced: gdpr-gate at plan Phase 2.7]

    If the plan touches regulated-data surfaces (per `hr-gdpr-gate-on-regulated-data-surfaces` canonical regex), invoke `/soleur:gdpr-gate` against the plan doc + the FR/TR sections being authored. Output is advisory-only with mandatory disclaimer; Critical findings (Art. 9 special-category, missing lawful basis, Art. 30 trigger) prompt operator-acknowledged write to `compliance-posture.md` Active Items + GitHub issue with label `compliance/critical`.

    Skip if no regulated-data surface is touched.
    ```
2. **Work Phase 2 exit (AC9):** edit `plugins/soleur/skills/work/SKILL.md`. Insert at the end of Phase 2 (after the per-task RED/GREEN/REFACTOR loop completes, before Phase 2.5):
    ```markdown
    ### 2.8. GDPR / Compliance Gate (single pass, end of Phase 2)

    [skill-enforced: gdpr-gate at work Phase 2 exit]

    Single pass against the cumulative diff `git diff main...HEAD`. Same advisory-only output + Critical-finding escalation as plan Phase 2.7. **Never per-task** — token budget is ≤4k per invocation.
    ```
    Spec FR2 wording in `knowledge-base/project/specs/feat-compliance-skills-eval/spec.md` line 46 amended to read "exit (single pass after all per-task TDD loops complete, before Phase 2.5)" per Research Reconciliation gap #1.
3. **Ship Phase 5.5 conditional gate (AC10):** edit `plugins/soleur/skills/ship/SKILL.md`. Insert after COO Expense-Tracking Gate, before Deploy Pipeline Fix Drift Gate:
    ```markdown
    ### gdpr-gate Critical-Finding Acknowledgment Gate

    **Trigger:** PR diff matches the canonical `hr-gdpr-gate-on-regulated-data-surfaces` regex AND the PR body contains either `Closes #N` or `Ref #N` where `#N` is an open issue with label `compliance/critical`.

    **Detection:**
    \`\`\`bash
    diff_match=$(git diff main...HEAD --name-only | grep -E "$CANONICAL_REGEX" | head -n 1)
    crit_refs=$(gh pr view --json body --jq .body | grep -oE '(Closes|Ref) #[0-9]+' | head -n 5)
    \`\`\`

    **If triggered:**
    1. Verify each `compliance/critical` issue referenced has a corresponding row in `compliance-posture.md` Active Items.
    2. **Interactive mode:** Ask "Critical finding #N has no Active Items row. File the row now via /soleur:compound, or proceed with operator acknowledgment recorded inline?" Options: File row, Acknowledge inline, Halt.
    3. **Headless mode:** Halt — operator must run `/soleur:ship` interactively when a `compliance/critical` issue is referenced.

    **If not triggered:** Skip silently.

    **Why:** Critical findings are the load-bearing artifact for `single-user incident` brand-survival; auto-merge without an Active Items row produces silent compliance drift. Defense-in-depth alongside `/soleur:gdpr-gate`'s plan-time and work-time gates.
    ```
4. **Brainstorm domain config (AC11):** edit `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md`. Append to CLO row's Task Prompt: "If the feature involves PII, schemas, auth, forms, or API routes touching regulated data, recommend invoking `/soleur:gdpr-gate` during plan Phase 2.7 and work Phase 2 exit. Reference `hr-gdpr-gate-on-regulated-data-surfaces` for the canonical regex."
5. **Review skill (AC13):** edit `plugins/soleur/skills/review/SKILL.md`. Add `gdpr-gate` to the conditional-agent block (fires when diff matches canonical regex). Add boundary disambiguation prose (text per AC13 description).
6. **Legal-audit cross-reference (AC17):** edit `plugins/soleur/skills/legal-audit/SKILL.md`. Add a one-sentence note in the "When to invoke" section.
7. **GREEN partial:** AC8-AC11, AC13, AC17 pass.

### Phase 4 — Agent disambiguation + AGENTS.md rule + README (~1-2 hrs)

**Goal:** Close the boundary edits and the AGENTS.md rule pointer.

1. **data-integrity-guardian (AC14):** edit `plugins/soleur/agents/engineering/review/data-integrity-guardian.md`. Add a single-line cross-reference to the description: "Boundary vs gdpr-gate: see `plugins/soleur/skills/review/SKILL.md` §boundaries." (Canonical prose lives in review/SKILL.md per AC13 — single source of truth.)
2. **security-sentinel (AC15):** edit `plugins/soleur/agents/engineering/review/security-sentinel.md`. Add the same single-line cross-reference.
3. **AGENTS.md Hard Rule (AC12):** insert into `## Hard Rules` section (after the existing user-impact rule, ~AGENTS.md line ~34):
    ```
    - When code touches regulated-data surfaces (PII fields, auth flows, schemas, forms, API routes per the canonical regex), invoke `/soleur:gdpr-gate` at plan Phase 2.7 and work Phase 2 exit [id: hr-gdpr-gate-on-regulated-data-surfaces] [hook-enforced: lefthook gdpr-gate.sh] [skill-enforced: plan Phase 2.7, work Phase 2 exit]. Advisory-only; Critical findings (Art. 9, missing lawful basis, Art. 30 trigger) escalate to `compliance-posture.md` Active Items + GitHub issue `compliance/critical`. **Why:** EU-deployed product with single-user-incident brand-survival threshold; pre-generation catch beats post-hoc audit.
    ```
    Verify `wc -c AGENTS.md` ≤37000 after edit. Run `python3 scripts/lint-rule-ids.py` to validate format.
4. **compliance-posture.md header (AC23):** add header comment block above Active Items table documenting the row schema and the gate-CLO handshake.
5. **README count sync (AC22):** run `scripts/sync-readme-counts.sh` only — script auto-inserts the new `gdpr-gate` row (no manual edit). Verify the diff is what the script produced; do NOT hand-edit subsections (per `2026-04-02-readme-count-sync-automation.md`).
6. **GREEN partial:** AC12, AC14, AC15, AC22, AC23 pass.

### Phase 5 — Test + multi-agent review + token-budget verification (~2-3 hrs)

**Goal:** Drive all 27 ACs to GREEN; multi-agent review fan-out; token-budget empirical verification.

1. **Skill test (AC20):** flesh out `plugins/soleur/test/gdpr-gate.test.ts`:
    - (a) `expect(sampleOutput.split('\n').filter(Boolean)[0]).toMatch(/This is not legal review/)`.
    - (b) For each of the 5 v1 checks (FR4): run a fixture diff through the gate, assert finding shape `{ severity: "Critical" | "Important" | "Suggestion", check_id: "GDPR-Art-{6,5e,17,V,9}", message: string, ... }`.
    - (c) Critical-finding flow asserts `compliance-posture.md` is NOT modified by the gate; only the operator-prompt text appears in stdout.
    - (d) Haiku request body regex check: prompt template includes column **names** but never values — assert `request.system.includes("DO NOT INCLUDE COLUMN VALUES")` and the schema-only example.
    - (e) Glob-regex unit test: feed sample paths through the canonical regex, assert match/no-match per the inventory at §TR4.
2. **Run `bun test plugins/soleur/`** — all assertions pass (GREEN).
3. **Run `lefthook run pre-commit`** against a fixture commit that touches `apps/web-platform/supabase/migrations/test_fixture.sql` — assert hook prints the advisory line and exits 0.
4. **Token-budget verification (AC24):** run `/soleur:gdpr-gate` against a sample diff (10 schema rows including 1 Art. 9 hit) + a 2k-char plan excerpt. Capture Anthropic SDK usage tokens. Assert input ≤4k, output ≤1.5k. Record sample run output in `plugins/soleur/skills/gdpr-gate/test-fixtures/sample-haiku-run.md` with `# gitleaks:allow # issue:#3502 sample regulated-data fixture` waiver per `cq-test-fixtures-synthesized-only`.
5. **Push branch + multi-agent review:** `git push -u origin feat-compliance-skills-eval` (already pushed, but re-push current state per `rf-before-spawning-review-agents-push-the`).
6. **Run `/soleur:review`** — multi-agent fan-out includes:
    - `data-integrity-guardian` (boundary verification),
    - `security-sentinel` (Art. 32 OWASP overlap),
    - `architecture-strategist` (read-only-auditor invariant + canonical-regex single-source),
    - `code-simplicity-reviewer` (≤500 lines SKILL.md, ≤30 words description),
    - `dhh-rails-reviewer` + `kieran-rails-reviewer` (default fan-out),
    - **`user-impact-reviewer` (REQUIRED — `single-user incident` threshold per `hr-weigh-every-decision-against-target-user-impact`)**,
    - **`gdpr-gate` self-invocation** (dogfood: gate audits its own diff). The self-invocation is expected to flag zero Critical findings since the gate's own code introduces no new PII columns.
7. Resolve review findings inline per `rf-review-finding-default-fix-inline`. Scope-out criteria + labels per `plugins/soleur/skills/review/SKILL.md` §5.
8. **GREEN final:** all 27 ACs pass.

### Phase 6 — Compound + Ship (~30-60 min)

**Goal:** Capture learnings, file v2 follow-ups, ship.

1. Run `/soleur:compound` to capture learnings (any session errors → learning files; AGENTS.md rule placement gate already applied per `cq-agents-md-tier-gate`).
2. **File v2 follow-up issues (AC-PM-2):**
    - `gh issue create --title "Add gdpr-gate as preflight Check 10 (Q1 follow-up)" --label domain/engineering,priority/p3-low --milestone "Post-MVP / Later" --body "Q1 from spec: defer to first preflight regression where gate's plan/work-phase coverage is insufficient. Re-evaluate when telemetry shows ≥3 Critical findings post-merge that escaped both /plan and /work gates."`
    - `gh issue create --title "Define version-pin policy for lifted Sprinto files (Q3 follow-up)" --label domain/legal,priority/p3-low --milestone "Post-MVP / Later" --body "Q3 from spec: re-vendor on upstream change vs. fork-permanently. Re-evaluate when upstream pushes a security-relevant update to any of the 8 lifted files."`
    - `gh issue create --title "Implement gdpr-gate v2 layers + repo-scan mode" --label domain/engineering,priority/p3-low --milestone "Post-MVP / Later" --body "v2 scope: auth-sessions/frontend/testing-seeding/legal-consent as separately-active layers; repo-scan mode with explicit allowlist for credential-leak-safety. Defer until v1 telemetry validates the 3-active-layer scope."`
3. Run `/soleur:ship`:
    - Phase 5.5 conditional gates fire: CMO content-opportunity (blog post "Why we built our own PII gate instead of bundling Sprinto's"), CMO website framing (gdpr-gate row addition to docs site), gdpr-gate critical-finding ack (this PR introduces no Critical findings, so gate skips silently).
    - PR body uses `Ref #3502` (NOT `Closes #3502`) per AC27 — issue stays OPEN until v2 follow-ups land. Verify via `wg-use-closes-n-in-pr-body-not-title-to` scanner.
    - Squash-merge label `feat:minor` (semver-minor; new skill + new AGENTS.md rule).
4. **Post-merge (AC-PM-1, AC-PM-3, AC-PM-4):**
    - Update `compliance-posture.md` `last_updated` frontmatter on `main`. Single commit `docs(compliance-posture): post-gdpr-gate handshake contract`.
    - Verify CI green: `gh run list --workflow plugin-component-test.yml --limit 1`.
    - Smoke-test: `/soleur:gdpr-gate "audit knowledge-base/project/specs/feat-compliance-skills-eval/spec.md"` against `main` HEAD.

## Test Scenarios

| Scenario | Setup | Expected | AC ref |
|---|---|---|---|
| Disclaimer is first non-blank line of every gate output | Run gate against any non-empty diff | Output line 1 = `**This is not legal review. Findings are heuristic. Consult ` clo` + `legal-compliance-auditor` before merging.**` | AC20(a) |
| Lawful basis check fires (FR4.1) | Diff adds new column `email TEXT NOT NULL` to a table without an annotated `-- LAWFUL_BASIS: contract` comment | Finding `severity: Important` (NOT Critical, per Kieran-review HIGH — zero existing migrations carry this annotation; first-run audit must not flood Critical), `check_id: GDPR-Art-6, message: "missing lawful basis annotation"` | AC20(b), FR4.1 |
| Retention check fires (FR4.2) | Diff adds new table `audit_log` without retention metadata | Finding `severity: Important, check_id: GDPR-Art-5e` | AC20(b), FR4.2 |
| DSAR-deletability check fires (FR4.3) | Diff adds FK to `users` table without `ON DELETE CASCADE` or explicit anonymization migration | Finding `severity: Important` (demoted from Critical for v1 — Critical reserved for Art. 9), `check_id: GDPR-Art-17` | AC20(b), FR4.3 |
| Cross-border transfer check fires (FR4.4) | Diff adds `STRIPE_API_KEY` env var (non-EU vendor) without a corresponding entry in `compliance-posture.md` Vendor DPAs | Finding `severity: Important, check_id: GDPR-Chapter-V` | AC20(b), FR4.4 |
| Art. 9 special-category detector blocks (FR4.5) | Diff adds column `medical_history TEXT` | Finding `severity: Critical, check_id: GDPR-Art-9` AND gate emits routing prompt to `clo` agent. **This is the ONLY Critical-severity check in v1** — keeps the noise floor low and preserves `compliance/critical` issue label as a load-bearing signal. | AC20(b), FR4.5 |
| Critical finding does NOT auto-write to compliance-posture | Run a Critical-finding scenario; assert `compliance-posture.md` MD5 unchanged | File unchanged; stdout contains "Run `gh issue create` and `git add knowledge-base/legal/compliance-posture.md` after operator review." | AC20(c), FR5 |
| Haiku request body sends column names only | Inspect prompt template + sample request | Prompt template contains `DO NOT INCLUDE COLUMN VALUES`; sample request body matches schema-only regex | AC20(d), TR3 |
| Lefthook hook exits 0 on glob match | Stage a `apps/web-platform/supabase/migrations/test_fixture.sql` change; run `lefthook run pre-commit` | Exit code 0; stderr contains advisory line | AC6, AC7 |
| Lefthook hook exits 0 on no glob match | Stage a `README.md` change; run `lefthook run pre-commit` | Exit code 0; gdpr-gate-advisory hook does not run (no glob match) | AC7 |
| Token budget ≤4k input + ≤1.5k output | Synthesized in-test fixture: 10-row schema diff (1 Art. 9 hit) + 2k-char plan excerpt | Anthropic SDK `response.usage.input_tokens ≤ 4000` AND `response.usage.output_tokens ≤ 1500` | AC24, TR3 |
| Cumulative skill-description budget intact | After adding gdpr-gate `description:` | `bun test plugins/soleur/test/components.test.ts` passes; cumulative ≤1800 words | AC21 |
| AGENTS.md byte budget intact | After adding `hr-gdpr-gate-on-regulated-data-surfaces` rule | `wc -c AGENTS.md` ≤37000 bytes | AC12 |
| Vendor scrub is clean | After lifting 8 files | `rg -i 'sprinto\.com\|utm_source=Claude\|powered by sprinto\|sprinto logo' plugins/soleur/skills/gdpr-gate/` returns hits ONLY in NOTICE | AC5 |
| Boundary disambiguation prose lands | Read updated agent descriptions | data-integrity-guardian + security-sentinel descriptions both contain `gdpr-gate` boundary text | AC14, AC15 |

## Risks

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| R1 | Lefthook hook exits 0 on glob match but stderr advisory is suppressed by terminal redirection in some shells, masking the advisory at commit time | Medium | Skill test asserts stderr is non-empty on glob match; document in Sharp Edges; the advisory is also printed by `incidents.sh` to `.claude/.rule-incidents.jsonl` so telemetry catches it even when stderr is dropped |
| R2 | Haiku invocation transmits regulated column names (e.g., `medical_history`) to a non-EU vendor — meta-violation: the gate is itself a Chapter V cross-border transfer | High | Document explicitly in SKILL.md that gate operation transmits column names (not values) to Anthropic; gate's own usage falls under `compliance-posture.md` Vendor DPAs (Anthropic DPA already verified per existing posture); send schema-only diffs (assert in skill test); never include row values |
| R3 | Spec FR2 wording "after TDD GREEN, before REFACTOR" was ambiguous — if a future plan reverts to per-task firing, token budget regresses by Nx | Medium | Spec amendment in Phase 3 locks the wording to "single pass after all per-task TDD loops complete, before Phase 2.5"; ADR-026 TR3 is the load-bearing reference; AGENTS.md rule body says "single pass per phase" |
| R4 | `cq-union-widening-grep-three-patterns` — if findings are typed as a discriminated union and a future v2 layer adds a new severity (e.g., `Blocking`), three consumer patterns must be grepped | Medium | Initial implementation uses `switch` + `_exhaustive: never` rail in TS test fixtures; document the widening procedure in SKILL.md "Future severity changes" subsection |
| R5 | Sprinto upstream pushes a security-relevant update to a lifted file; we silently ship stale content | Medium | Q3 follow-up issue tracks version-pin policy; `NOTICE` includes the pinned commit SHA so any drift is grep-able; CMO content gate at /ship Phase 5.5 fires on release-doc updates and surfaces this |
| R6 | False-positive rate on `*auth*` glob if future `apps/web-platform/server/*auth*.ts` files include trivial helpers (e.g., `auth-error.ts`) | Low | Canonical regex is broad-but-bounded; advisory-only output keeps cost low even on false-positives; v2 can tighten if telemetry shows >50% false-positive rate |
| R7 | Operator dismisses a Critical finding without filing the GitHub issue; gate's only enforcement is /ship Phase 5.5 conditional gate which is bypassable in headless mode | High (offset by single-user-incident threshold) | /ship Phase 5.5 in headless mode HALTS rather than skipping when a `compliance/critical` issue is referenced (per AC10); manual operator override required; preserves human accountability per CLO assessment |
| R8 | The "advisory-only" pattern is novel in this codebase — future skill authors may copy it for a hard-block use case where blocking is correct | Low | SKILL.md "Why advisory" section explains the human-accountability trade-off; AGENTS.md rule body anchors `[hook-enforced]` semantic |
| R9 | `compliance-posture.md` becomes a security-aggregation surface (per `2026-02-16-inline-only-output-for-security-agents.md`) — open-source repo aggregating compliance gaps is an attacker roadmap | Medium | Active Items rows reference issue numbers but do NOT include diff details, column names, or schema content. Issue itself is private only via GitHub access controls — repo is currently public; document the trade-off in `compliance-posture.md` header. Q follow-up: evaluate moving Active Items table to a private knowledge-base repo. |
| R10 | The 1800-word cumulative skill-description budget is currently at ~1614 words with 67 skills; this PR adds `gdpr-gate` description (~30 words). At ~50 words headroom remaining, the next 1-2 new skills will force sibling trims | Low | Phase 0 verifies headroom at /work start; if <30 words headroom, halt and file a chore PR per `2026-04-21-skill-description-budget-at-cap-requires-plan-time-surgery.md` |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. **This plan's section is filled (lines 36-48); threshold = `single-user incident` carry-forward from brainstorm.**
- The lefthook hook is **advisory only** — `exit 0` on every code path. Operators relying on the hook to **block** a commit will be surprised. Documented in SKILL.md. The blocking enforcement is at /ship Phase 5.5 (post-PR), not pre-commit.
- The Haiku invocation transmits column **names** to Anthropic. This is itself a Chapter V transfer; covered by Anthropic's existing DPA in `compliance-posture.md` Vendor DPAs. Document the meta-trade-off in SKILL.md "Why advisory" section. Future re-evaluation is the right path if the GDPR DPA landscape for Anthropic changes.
- The 5 mandatory v1 checks (FR4) lean on **structured comments** in migrations (e.g., `-- LAWFUL_BASIS: contract`). Operators not using these comments will see `Important`-severity findings on every column. Spec AC + Phase 1 SKILL.md documents the comment shape; existing migrations 001-040 do NOT use these comments today, so the gate fires `Important` on a backfill audit. **This is intentional** — backfill audit is one of the gate's value props (catch existing schema gaps). Document in SKILL.md "First-run on existing codebase" section. **Per Kieran-review HIGH:** Critical severity is reserved for Art. 9 column-name matches ONLY; lawful-basis/retention/DSAR/cross-border findings are Important even when missing. Without this demotion, first-run noise would train operators to dismiss Critical, defeating the brand-survival rationale.
- The `*auth*` regex is intentionally NOT bounded by a `/` prefix — a future file like `apps/web-platform/server/something-with-auth-in-name.ts` matches by design. False-positive rate is acceptable for advisory-only output; document.
- The skill name `gdpr-gate` foregrounds GDPR even though v1 covers CCPA + HIPAA secondarily. Operators expecting a US-first skill may pass over it. CMO content gate at /ship Phase 5.5 lands the framing prose.
- AGENTS.md rule IDs are immutable per `cq-rule-ids-are-immutable`. The chosen ID `hr-gdpr-gate-on-regulated-data-surfaces` is **permanent**. If a v2 split is needed (e.g., per-regulation rules), retire the ID via `scripts/retired-rule-ids.txt` rather than reusing.
- All AGENTS.md rule IDs cited in the new SKILL.md, AGENTS.md rule, ADR amendment, tests, and this plan MUST be grep-verified against `AGENTS.md` AND `scripts/retired-rule-ids.txt` before /work GREEN. Per `2026-05-09-llm-authored-plans-cite-fabricated-and-retired-rule-ids.md`, deepen-plan subagents fabricate plausible-sounding IDs. Verification command:
    ```bash
    rg -oE '\[id: [a-z-]+\]' knowledge-base/project/plans/2026-05-10-feat-gdpr-gate-skill-plan.md | sort -u | while read id; do
      bare=$(echo "$id" | sed 's/\[id: //; s/\]//')
      grep -q "id: $bare" AGENTS.md || grep -q "^$bare " scripts/retired-rule-ids.txt || echo "FABRICATED: $bare"
    done
    ```
- Phase 5 multi-agent review must include `user-impact-reviewer` (REQUIRED at `single-user incident` threshold). Skipping this reviewer is a workflow violation.

## Research Insights

### From repo-research-analyst

- **Skill anatomy:** 4 precedent skills (`legal-audit`, `legal-generate`, `preflight`, `review`) reviewed. Length range 72-741 lines. Only `review` has `references/` + `scripts/` — closest model for `gdpr-gate`.
- **Frontmatter:** `name` + `description` only; `description` MUST start with literal `"This skill"` per components.test.ts.
- **References file linking:** `[name](./references/<file>.md)` markdown link convention enforced; backtick-only references fail CI.
- **Plugin manifest:** `plugins/soleur/.claude-plugin/plugin.json` (NOT `plugins/soleur/plugin.json`); skills auto-discovered, not enumerated.
- **README:** `### Review & Planning` subsection is the right home (sits with `preflight`/`review`).
- **Plan Phase placement:** Phase 2.7 (new) preferred over extending Phase 2.6 (preserves rule-tag invariants).
- **Work Phase 2 exit:** single pass at end of Phase 2 (NOT per-task) is the architecturally correct interpretation per ADR-026 TR3.
- **Preflight Check structure:** if Q1 is later promoted, slot as Check 10 (existing 7=Canary, 8=SW cache, 9=Node-only encodings).
- **Ship Phase 5.5:** existing conditional gates use a 4-line trigger/detection/if-triggered/why pattern; new gate slots between COO and Deploy Pipeline gates.
- **Lefthook conventions:** array-form globs avoid gobwas `**` semantics; no existing hook is "fire skill, don't block" — pattern invention.
- **brainstorm-domain-config:** extend CLO Task Prompt rather than adding a new domain row.
- **AGENTS.md headroom:** 24,618 / 37,000 bytes (33% headroom); 69 rules (vs. 115 advisory threshold). One ~525-byte rule fits comfortably.
- **NFR/AP register:** ADR-026 had two mismatches (NFR-027 + NFR-030); both flagged for amendment in Phase 2.
- **compliance-posture.md:** schema verified — 5-column Active Items table.
- **Sprinto upstream:** commit SHA `7b58d68461cb1fc033a063e34cc9de63d0b4144b` (2026-05-08); blob SHAs for 8 files captured in NOTICE.
- **Lefthook glob coverage:** `forms/**` + `**/*.prisma` are dead globs in this repo (zero matches); `*auth*` is too broad (104 files).
- **Word budget:** cumulative ~1614 words; ~186 word headroom; gate description targets ≤30 words.

### From learnings-researcher

- **`hr-when-a-plan-specifies-relative-paths-e-g`:** path globs are falsifiable claims; verify each via `git ls-files`. Drove §Research Reconciliation gaps #4-6 + Phase 2 canonical regex single-source pattern.
- **`hr-weigh-every-decision-against-target-user-impact`:** single-user-incident threshold requires CPO + user-impact-reviewer sign-off. Carry-forward applies.
- **`cq-union-widening-grep-three-patterns`:** discriminated union widening must grep three consumer patterns. Drives R4 mitigation (use `switch` + `_exhaustive: never` rail).
- **`cq-agents-md-tier-gate` + `cq-agents-md-why-single-line`:** placement gate + 600-byte cap. Drives AC12 design.
- **`2026-04-28-plan-globs-must-be-verified-against-repo-structure.md` (PR #2889):** canonical case for the single-regex-source pattern this plan adopts in Phase 2.
- **`2026-03-21-lefthook-gobwas-glob-double-star.md`:** array-form globs to avoid gobwas trap. Drives Phase 2 lefthook entry shape.
- **`2026-04-21-skill-description-budget-at-cap-requires-plan-time-surgery.md`:** plan-time word measurement; chore-PR fallback if at cap. Drives Phase 0 step 2.
- **`2026-02-16-inline-only-output-for-security-agents.md`:** advisory-only pattern + aggregation-as-attack-surface for `compliance-posture.md`. Drives R9 mitigation.
- **`2026-03-30-compound-headless-issue-filing-over-auto-accept.md`:** Critical-finding flow uses Option 3 (file issue + acknowledgment), never auto-accept. Drives FR5 implementation.
- **`2026-05-03-user-impact-reviewer-catches-runtime-content-tamper-vectors.md`:** single-user-incident triggers `user-impact-reviewer` at /review. Drives Phase 5 review fan-out.
- **`2026-05-06-user-impact-section-by-role-not-surface.md`:** enumerate by role; drove the §User-Brand Impact role list.
- **`2026-02-21-gdpr-article-30-compliance-audit-pattern.md`:** EU-vs-non-EU adequacy; Hetzner Finland + Supabase Ireland are EU. Drives FR4.4 cross-border check semantics.
- **`2026-03-19-skill-enforced-convention-pattern.md`:** three-tier enforcement (PreToolUse hook → skill instruction → prose). Drives the `[hook-enforced] + [skill-enforced]` dual annotation in AC12.
- **`2026-04-23-agents-md-governance-measure-before-asserting.md`:** measure byte impact empirically. Drives Phase 0 step 3.
- **`2026-05-09-llm-authored-plans-cite-fabricated-and-retired-rule-ids.md`:** every cited rule-ID must be grep-verified. Drives Sharp Edges verification command.
- **`2026-04-02-readme-count-sync-automation.md`:** `scripts/sync-readme-counts.sh --check` runs in CI. Drives AC22 implementation.

### From functional-discovery

- **`legal-audit` / `legal-generate`:** doc-layer; complementary not duplicative.
- **`data-integrity-guardian`:** broad data-safety remit with PII as one bullet → boundary edit (AC14).
- **`security-sentinel`:** Art. 32 ~60% security-of-processing → boundary edit (AC15) splits at governance vs. OWASP-class.
- **`clo`:** reads `compliance-posture.md` — gate writes there → integration via Active Items contract (AC16).
- **`user-impact-reviewer`:** review-time consumer of gate findings; complementary, sequenced.
- **`pr-review-toolkit`:** empty in this worktree — no overlap to assess.
- **External:** wshobson/agents `gdpr-data-handling` (implementation-focused, complementary), grcengclub `gdpr` (operational, complementary). No community skill duplicates the design-time-gate-on-diff pattern. Clean niche.
- **`secret-scan` workflow:** orthogonal — gitleaks scans live credentials; gdpr-gate scans design patterns.

## Deferral Tracking

The plan defers 3 capabilities to v2 (per spec Non-Goals + AC-PM-2). Each gets a tracking issue at /ship Phase 6 step 2:

| Deferral | Why deferred | Re-eval criterion | Tracking issue (created at /ship) |
|---|---|---|---|
| `/soleur:preflight` Check 10 (gdpr-gate at preflight) | Q1 from spec; v1 plan/work-phase coverage may be sufficient | ≥3 Critical findings post-merge that escaped both /plan and /work gates | "Add gdpr-gate as preflight Check 10 (Q1 follow-up)" — `domain/engineering`, `priority/p3-low`, milestone "Post-MVP / Later" |
| Version-pin policy for lifted Sprinto files | Q3 from spec; depends on upstream activity | Upstream pushes a security-relevant update to any of 8 lifted files | "Define version-pin policy for lifted Sprinto files (Q3 follow-up)" — `domain/legal`, `priority/p3-low` |
| v2 layers (auth-sessions, frontend, testing-seeding, legal-consent) + repo-scan mode | Spec Non-Goals; credential-leak risk in repo-scan | v1 telemetry validates 3-active-layer scope; or operator demand for missing layer | "Implement gdpr-gate v2 layers + repo-scan mode" — `domain/engineering`, `priority/p3-low` |

CMO blog post "Why we built our own PII gate instead of bundling Sprinto's" — handled by /ship Phase 5.5 CMO content-opportunity gate (already enforced); not a new tracking issue.

## Build Sequence Summary

```
Phase 1 — preconditions + skill scaffold + 5 lifted files + RED test (~4-5 hrs)
   ↓
Phase 2 — lefthook + canonical regex + ADR amendment (~2-3 hrs)
   ↓
Phase 3 — plan/work/ship/brainstorm/review/legal-audit integration (~3-4 hrs)
   ↓
Phase 4 — agent boundary cross-refs + AGENTS.md rule + README sync (~1 hr)
   ↓
Phase 5 — test + multi-agent review + token-budget verification (~2-3 hrs)
   ↓
Phase 6 — compound + ship + v2 follow-up issues (~30-60 min)
```

**Total estimate:** ~12-16 hours of focused work (down from 12-17 after applied review-fixes #2/#3/#4/#6 deferred ~1 hr of bookkeeping; review-fix #1 trimmed ~30 min from Phase 1's lift list). Single PR (#3501); single squash-merge; single semver-minor bump (`feat:minor` label).

**ACs after review-fix application:** 22 pre-merge + 4 post-merge = 26 (down from 27+4). Net: AC16 dropped, AC22 simplified, AC24 tightened, AC20(b) re-scoped. Numbering preserved for traceability against earlier review-cycle quotes.

## Resume Prompt

```
/soleur:work knowledge-base/project/plans/2026-05-10-feat-gdpr-gate-skill-plan.md
Branch: feat-compliance-skills-eval. Worktree: .worktrees/feat-compliance-skills-eval/. Issue: #3502. PR: #3501. Plan reviewed, ADR-026 + brainstorm + spec all on disk; ready for Phase 0 pre-flight + Phase 1 RED.
```
