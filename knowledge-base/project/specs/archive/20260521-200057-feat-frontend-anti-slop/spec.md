---
feature: frontend-anti-slop
status: draft
lane: cross-domain
brand_survival_threshold: none
brainstorm: knowledge-base/project/brainstorms/2026-05-21-frontend-anti-slop-skill-brainstorm.md
worktree: .worktrees/feat-frontend-anti-slop
branch: feat-frontend-anti-slop
related_issue: tbd
created: 2026-05-21
---

# Spec: frontend-anti-slop skill

## Problem Statement

Soleur users build React/Next.js apps with agent assistance, and the resulting UI converges on AI-generated visual tells (gradient text, generic font stacks, redrawn UI chrome, hero → 3-feature → CTA macrostructure, purple-on-white palettes). The existing `frontend-design` skill (Anthropic stock) gives generation-time guidance but has no rule IDs, no enforceable gates, and no audit verb. `ux-audit` reviews live rendered UI via screenshots but has no codified slop rule-set. There is no Soleur-owned skill that audits React source code against a structured anti-slop ruleset.

Nutlope's MIT-licensed [Hallmark](https://github.com/Nutlope/hallmark) skill (by Together AI) carries the rule corpus (60+ slop-test gates, anti-pattern catalog, genre rubrics) but targets self-contained CSS/HTML/JS pages, not React + Tailwind.

## Goals

1. Adapt Hallmark's React-applicable rules into a Soleur-native skill that audits `apps/web-platform/{app,components}/**/*.{tsx,css}` for anti-slop violations.
2. Two-tier scan: Tier 1 deterministic (Tailwind classname + JSX patterns), Tier 2 LLM judgment for variety / composition / microinteraction gates.
3. Integrate with `ux-audit` as a new `FINDING_CATEGORIES` entry (reuse dedup hash, caps, GitHub-issue filing).
4. Standalone invocation via `/soleur:frontend-anti-slop` for ad-hoc runs.
5. Pair with a new `engineering/review/anti-slop-reviewer.md` agent invoked by `pr-review-toolkit:review-pr` on PRs touching frontend files.
6. Ship opt-in + dry-run-first; calibrate before default-on.
7. Preserve MIT attribution: LICENSE.txt + NOTICE.md + per-file `<!-- Adapted from Hallmark (MIT) — see NOTICE -->` headers.

## Non-Goals

- No `build` / `redesign` / `study` verbs in v1.
- No macrostructure catalog port (21 page-layout archetypes; irrelevant to app surfaces).
- No 22 theme catalog port as prescription (kept only as monoculture-detection rubric).
- No "Powered by Together AI" footer in skill body (attribution via LICENSE/NOTICE).
- No default-on PR gate in v1.
- No extension of `frontend-design`, `web-design-guidelines`, or `pr-review-toolkit:code-reviewer` (external/non-Soleur-owned).

## Functional Requirements

- **FR1.** Skill is invocable via `Skill` tool with name `frontend-anti-slop` and via `/soleur:frontend-anti-slop` slash form.
- **FR2.** Skill accepts target paths or globs; defaults to staged + modified files in current worktree.
- **FR3.** Tier 1 scanner emits findings with `{file, line, rule_id, severity, message, suggested_fix}`. Default `dry_run=true` (emit to stdout, no GH-issue file).
- **FR4.** Tier 2 (LLM judgment) only runs on files where Tier 1 surfaced ≥1 hit, OR when explicitly requested via `--tier=2`.
- **FR5.** `ux-audit` `FINDING_CATEGORIES` extended with `anti-slop`; ux-audit invokes the Tier 1 scanner on its route-resolved files.
- **FR6.** New `anti-slop-reviewer` agent receives diff + Tier 1 findings and emits Tier 2 verdict.
- **FR7.** All findings cite a rule ID from `references/slop-rules.md` (Soleur-curated subset of Hallmark gates). Findings without a rule ID are invalid.
- **FR8.** Auto-file requires `dry_run=false` AND calibration signal (TR6) met.

## Technical Requirements

- **TR1.** Tier 1 scanner implemented in TypeScript at `plugins/soleur/skills/frontend-anti-slop/scripts/tier1-scan.ts`. Use ripgrep patterns or simple regex; no `ts-morph` unless ripgrep proves insufficient for a specific rule.
- **TR2.** Skill description ≤ 30 words. Cumulative skill-description budget must remain ≤ 1800 words after addition; sibling-trim sub-plan in spec lists the exact descriptions to shorten and the new word counts.
- **TR3.** New review agent description ≤ 100 words; cumulative agent description budget already has headroom.
- **TR4.** LICENSE.txt reproduces Hallmark's MIT verbatim. NOTICE.md credits Nutlope + Together AI by name. Per-file headers on every ported reference file.
- **TR5.** Vendor-surface scrub: no `utm_*` query params, no Together AI logo, no "Powered by Together AI" line anywhere in skill body.
- **TR6.** Calibration signal for `dry_run=false` promotion: ≥ 2 weeks dogfood + manual review of ≥ 20 findings + ≤ 10% operator-confirmed false-positive rate (per CPO assessment + `ux-audit-calibration-miss-path` lesson).
- **TR7.** Dedup hash for ux-audit integration: SHA-256 of `route|file|rule_id` (extends existing `route|selector|category` schema in `ux-audit/scripts/dedup-hash.ts`).
- **TR8.** Findings respect ux-audit caps: 20 open / 5 per run / 2 per route (no new caps).
- **TR9.** `pr-review-toolkit:review-pr` invokes `anti-slop-reviewer` only on PRs that modify files matching `apps/web-platform/{app,components}/**/*.{tsx,jsx,css}`.

## Acceptance Criteria

- [ ] Sibling-trim sub-plan present in spec listing ≥ 70 words freed across named SKILL.md descriptions.
- [ ] `bun test plugins/soleur/test/components.test.ts` passes (description budget ≤ 1800).
- [ ] `frontend-anti-slop` skill discoverable via `/soleur:help`.
- [ ] Tier 1 scanner runs on `apps/web-platform/components/ui/gold-button.tsx` and emits ≥ 1 rule-cited finding (calibration baseline).
- [ ] ux-audit invocation surfaces at least one `anti-slop` finding category in dry-run mode on the next scheduled run.
- [ ] `anti-slop-reviewer` agent invoked by `pr-review-toolkit:review-pr` on a test PR; emits Tier 2 verdict citing rule IDs.
- [ ] LICENSE.txt + NOTICE.md present; per-file headers on every ported reference; no Together AI footer in skill body; no `utm_*` URLs.
- [ ] No auto-filing of GitHub issues in v1 (default `dry_run=true`).

## Open from Brainstorm

- Specific gate subset (which of Hallmark's 60 are Tier 1 vs Tier 2 vs dropped) — fold into plan.
- Specific sibling descriptions to trim — fold into plan.
- Whether ux-audit needs a separate `component-list.yaml` or extends `route-list.yaml` — fold into plan.
