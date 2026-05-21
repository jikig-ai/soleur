---
date: 2026-05-21
topic: frontend-anti-slop-skill
status: brainstorm-complete
lane: cross-domain
brand_survival_threshold: none
related_issue: tbd
worktree: .worktrees/feat-frontend-anti-slop
branch: feat-frontend-anti-slop
---

# Brainstorm: frontend-anti-slop skill (Hallmark adaptation)

## What We're Building

A new Soleur-native skill, `frontend-anti-slop`, that adapts the rule-set from [Nutlope/hallmark](https://github.com/Nutlope/hallmark) (MIT, by Together AI) into a React/Next.js audit pass for the apps Soleur users ship. Skill emits a deterministic Tier 1 scan (Tailwind classname patterns: gradient-text triad, generic font imports, redrawn UI chrome, mid-render token improvisation) and delegates Tier 2 judgment (variety, hero composition, microinteraction polish) to an LLM reviewer agent. Findings flow into `ux-audit`'s existing `FINDING_CATEGORIES` pipeline (dedup hash + caps + GitHub-issue filing), and the skill is also independently invocable via `/soleur:frontend-anti-slop`.

Ships v1 opt-in + dry-run-first. Default-on PR gating deferred until precision is measured against dogfood signal.

## Why This Approach

User asked whether Soleur should benefit from Hallmark so its users don't ship bland AI-looking UI. Two routes were on the table — vendor Hallmark as-is, or extract its rule-set into a Soleur-adapted skill. User picked the latter (Route 2) because Hallmark targets self-contained CSS/HTML/JS pages while Soleur users ship Next.js + Tailwind + a hand-rolled `components/ui/` substrate; the patterns transfer but the output format doesn't.

Three domain leaders (CTO, CPO, CMO) plus repo research and learnings research converged on:

- **Audit-only complement, not wrapper.** Leave `frontend-design` (Anthropic stock skill) untouched — wrapping it would couple generation and review and bloat its routing description. The differentiated job is the pre-merge audit, which fires repeatedly and is structurally enforceable; build-from-prompt is one-shot.
- **Cherry-pick, don't lift wholesale.** ~15 of Hallmark's 219 files are React-relevant. Drop the 21 macrostructure catalog (page-shaped, aimed at marketing sites; Soleur users build dashboards, settings, forms). Keep `slop-test.md` (curated subset), `anti-patterns.md`, 4 genre descriptions, and ~10–20 component-pattern references that map to dashboard surfaces.
- **Two-tier scan substrate.** Tier 1 = deterministic ripgrep/AST sweep over `apps/web-platform/{app,components}/**/*.{tsx,css}` for the mechanically-auditable subset (~20 of 60 gates). Tier 2 = LLM judgment via reviewer agent, gated by Tier 1 hits, riding on the existing screenshot pipeline.
- **Plug into ux-audit.** `ux-audit` already owns the GitHub-issue infra (dedup SHA-256 hash of `route|selector|category`, caps: 20 open / 5 per run / 2 per route). Adding `anti-slop` to its `FINDING_CATEGORIES` is the lowest-cost wiring.
- **Opt-in v1 + dry-run.** Per `2026-04-15-ux-audit-calibration-miss-path.md`: subjective UX categories diverge from operator prior; ship findings as artifact + manual file until calibration signal demonstrably passes (<10% false-positive rate per CPO; >85% precision per CMO).

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | Approach **B**: new `frontend-anti-slop` skill + integration with `ux-audit` | Standalone invocability matches user framing; attribution lives in clean home; consolidation alternative (A) requires sibling trims anyway. |
| 2 | Drop Hallmark's 21 macrostructure catalog from v1 | Page-shaped (bento, manifesto, specimen); Soleur users ship app UIs, not landing pages. ~30% of Hallmark's bulk eliminated. |
| 3 | Strip "Powered by Together AI" footer from skill body | Keep MIT credit via LICENSE + NOTICE.md + per-file `<!-- Adapted from Hallmark (MIT) — see NOTICE -->` headers. Clean Soleur surface; attribution still satisfies MIT terms. |
| 4 | Findings flow into `ux-audit` FINDING_CATEGORIES (new `anti-slop` entry) | Reuse dedup + caps + issue-filing pipeline. Avoid duplicate GH-issue surface. |
| 5 | Two-tier scan: Tier 1 deterministic (Tailwind scanner), Tier 2 LLM judgment | ~20 of 60 gates mechanically auditable; ~40 require judgment. Pair satisfies `2026-05-12-multi-agent-review-cross-reconcile-catches-false-positive-high-findings.md` (single-agent HIGH is modal false-positive). |
| 6 | New review agent: `plugins/soleur/agents/engineering/review/anti-slop-reviewer.md` | Invoked by `pr-review-toolkit:review-pr` on PRs touching `apps/web-platform/{app,components}/**`. |
| 7 | Ship opt-in v1 with `dry_run=true` default; auto-file only after calibration | Subjective UX calls diverge from operator prior; `ux-audit-calibration-miss-path` lesson. |
| 8 | Description budget: must free ≥70 words from sibling skills before adding entry | Cumulative description budget is at 1840/1800 (40 over cap); new skill needs ~30 words. Sibling trim is plan-time, not validation-phase, work. |
| 9 | Defer launch beat | CMO recommendation: quiet ship now, earn launch in 60 days on Soleur audit data (before/after screenshots from N user repos), not on the derivative ruleset. |

## Non-Goals (v1)

- **Build verb** — `frontend-design` (Anthropic stock) keeps that job. No wrapper.
- **Study verb** — DNA extraction from screenshots/URLs is interesting but tangential; defer to v2 if v1 finds traction.
- **Redesign verb** — refactoring existing components is high-risk for an automated skill; out of scope.
- **22 theme catalog** — kept as a rubric for "monoculture detection" but NOT prescribed. We are not picking themes for Soleur users' apps.
- **Macrostructure catalog** — page-shaped; not relevant to app-surface auditing.
- **Default-on PR gate** — opt-in until precision is benchmarked.
- **Extending `pr-review-toolkit:code-reviewer`** — external/non-Soleur-owned skill; can't extend without forking.
- **Extending `web-design-guidelines`** — Vercel-owned user-local skill at `~/.agents/skills/web-design-guidelines/`; can't extend without forking.

## Open Questions

| # | Question | Owner | When |
|---|---|---|---|
| 1 | Which specific sibling skill descriptions to trim to free ≥70 words? | Plan time | Pre-spec |
| 2 | Exact subset of Hallmark's 60 gates to port (Tier 1 vs Tier 2 split) | Plan time | Spec |
| 3 | Should `ux-audit`'s `route-list.yaml` extend to cover component-level audit (not just route), or do we add a separate `component-list.yaml`? | Plan time | Spec |
| 4 | What's the calibration signal that flips v1 → v2 (auto-filing)? Precision %, dogfood week count, or operator sign-off? | Plan time | Spec |
| 5 | Should the Tier 1 scanner be `ripgrep` patterns (zero deps) or `ts-morph` AST? CTO recommended ripgrep first. | Plan time | Spec |
| 6 | Sibling-trim selection — `budget-analyst` could automate by ranking longest descriptions, but worth doing by hand to avoid value loss | Plan time | Spec |

## Domain Assessments

**Assessed:** Engineering (CTO), Product (CPO), Marketing (CMO), Operations, Legal, Sales, Finance, Support

Operations, Legal, Sales, Finance, Support: not applicable (internal skill authoring, no commercial / regulatory / channel surface).

### Engineering (CTO)

**Summary:** Audit-only complement named `soleur:anti-slop` (peer to `frontend-design`, consumed by `ux-audit`). Two-tier mechanical-first scan (Tier 1 ripgrep over Tailwind/JSX, Tier 2 LLM judgment via reviewer agent). Port floor ~15 files of Hallmark's 219; below ~10 the differentiator collapses; above ~25 maintenance dominates value. Plug as new finding source in `ux-audit/FINDING_CATEGORIES` + new `engineering/review/anti-slop-reviewer.md` agent invoked by `pr-review-toolkit:review-pr`.

### Product (CPO)

**Summary:** Audit > build for leverage (audit fires repeatedly + structurally enforceable; build is one-shot). Positioning: audit-only complement; do NOT merge with `frontend-design`. Drop macrostructure catalog (page-shaped, wasted budget for app UIs). Canary risk = false slop verdict (kills adoption fastest); verdicts must cite rule ID + fix suggestion. Sequencing: v1 opt-in `/soleur:frontend-anti-slop`; v2 wire into `ux-audit` route runs after <10% FP rate; v3 default-on PR gate.

### Marketing (CMO)

**Summary:** Quiet ship now; earn launch beat in 60 days on Soleur audit data (before/after screenshots from N user repos). Launching off Hallmark today courts "Soleur reskins OSS" narrative. Attribution: fork-with-credit (LICENSE + NOTICE + per-file header). Opt-in until precision >85% — bundling unproven audit with `security-sentinel` / `gdpr-gate` contaminates high-stakes gates. Differentiation: real pillar (v0/Bolt/Lovable don't audit output for slop), but only credible after shipped-app evidence.

## Capability Gaps

- **Tailwind/JSX classname scanner script** (engineering). Tier 1 audit needs a deterministic scanner. Belongs as `plugins/soleur/skills/frontend-anti-slop/scripts/tailwind-slop-scan.ts`. **Evidence:** `find plugins/soleur/skills -name "*.ts" -path "*/scripts/*"` shows no existing Tailwind-classname scanner across the 73 skills. No false-negative risk from grep — the scanner format would be specific.
- **`anti-slop-reviewer` agent** (engineering/review). New agent for Tier 2 LLM-judgment gates. Counts ~10 words against the 2500-word agent description budget. **Evidence:** `ls plugins/soleur/agents/engineering/review/` (17 review agents, none UI-aware per repo-research-analyst report).

## Productize Candidates

None — the skill itself IS the productized output of recurring UI-audit work.

## Session Errors

None — Phase 0.4 lane resolution was clean (cross-domain), USER_BRAND_CRITICAL=false was clean (no statutory/credential exposure despite lexical `auth` hit in a negation phrase), agent spawn was a single parallel batch.

## References

- Source repo: <https://github.com/Nutlope/hallmark> (MIT, by Together AI; 219 files at commit time of brainstorm)
- Soleur asset wrapped/complemented: `plugins/soleur/skills/frontend-design/SKILL.md`
- Integration target: `plugins/soleur/skills/ux-audit/SKILL.md` + `references/finding.schema.json` + `scripts/dedup-hash.ts`
- Frontend substrate audited: `apps/web-platform/` (Next.js 15.5.18 App Router, React 19.1, Tailwind v4.1, `--soleur-*` CSS custom properties in `app/globals.css:39-95`)
- Learnings:
  - `2026-05-09-evaluating-vendor-branded-claude-code-skills.md` — utm-tagged links / vendor surface
  - `2026-04-21-skill-description-budget-at-cap-requires-plan-time-surgery.md` — sibling-trim plan-time work
  - `2026-04-15-ux-audit-calibration-miss-path.md` — dry-run escape hatch for subjective categories
  - `2026-05-12-multi-agent-review-cross-reconcile-catches-false-positive-high-findings.md` — single-agent HIGH false-positive
  - `2026-04-17-review-backlog-net-positive-filing.md` — cap, drain, tag provenance
  - `2026-02-14-plan-review-agent-consolidation.md` — "split when it hurts" (consolidation candidates not Soleur-owned, so new skill justified)
