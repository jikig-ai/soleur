---
date: 2026-05-15
topic: code-to-prd skill (reverse-engineer codebase → PRD)
issue: 2726
parent_issue: 2718
branch: feat-code-to-prd-2726
pr: 3783
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Brainstorm: code-to-prd skill (#2726)

## What We're Building

A new Soleur skill `code-to-prd` that reverse-engineers an existing Next.js codebase into a PRD markdown document the founder can hand to a buyer, investor, or coding agent. Skill performs deterministic extraction (filesystem walk, route enumeration, state shape sampling, API/external dependency inventory), passes every input and output through a fail-closed redaction stack, writes the PRD to `knowledge-base/product/prd/<project>-prd.md`, then spawns `spec-flow-analyzer` via Task as a closing gap-analysis pass.

Adapted from the MIT-licensed pattern in `alirezarezvani/claude-skills/product-team/code-to-prd`. Diverges from vendor on three load-bearing points: (1) automated secret redaction (vendor has none), (2) Next.js-only v1 (vendor spans 12+ frameworks), (3) skill orchestrates an existing agent rather than reinventing the gap-analysis lens.

## User-Brand Impact

**Threshold: single-user incident.** A single founder posting a leaky PRD into a buyer's data room is brand-ending.

- **Artifact:** generated PRD markdown written to `knowledge-base/product/prd/<project>-prd.md`.
- **Vector 1 — credential/PII leak:** skill ingests source, `.env*`, fixtures, seed data, comments. Without redaction, output may contain API keys (`sk_*`, `ghp_*`, `AKIA*`), OAuth secrets, DB connection strings, PII (test user emails, customer references in comments), or internal company info. Founder commits/shares as-is.
- **Vector 2 — silent-wrong PRD:** founder treats a plausible-but-incomplete PRD as ground truth for due diligence. Missing routes, mislabeled state, omitted API dependencies — buyer's CTO finds 4 undocumented routes mid-diligence, founder loses leverage.
- **Operator framing answer:** "1 and 2" — both vectors confirmed user-brand-critical.

## Why This Approach

1. **Skill orchestrates agent, not pure skill.** The deterministic extraction (filesystem walk, route file detection, redaction) is procedural and belongs in a skill. The interpretive synthesis (gap analysis, missing-element detection) is judgment-driven and already covered by `spec-flow-analyzer`. Mirrors the `incident` skill's redaction-sentinel + structured-phases pattern.
2. **Next.js only at v1.** Matches Soleur's own stack (smallest blast radius for getting it wrong), App Router + Pages Router are filesystem-driven (no parser needed for route enumeration), and CTO complexity estimate is +2 days per added framework — Rails/Django defer until one paying founder runs v1.
3. **Output committed by default but with automated leak detection.** Operator explicitly stated: "Soleur should automatically check for leaks; founder shouldn't have to verify manually." Architecture is 4-layer fail-closed (below) — committed location is acceptable only because the redaction stack is load-bearing.
4. **Exhaustive field inventory cut from v1.** Vendor's "exhaustive field inventory" is the largest Vector 1 surface (every model, every fixture, every comment scanned). Grep-based field extraction silently misses 30% (mapped types, inherited types, Rails STI). v1 ships route + state-shape-summary + API dependency only, with mandatory `## Coverage Caveats` block.
5. **MIT attribution mandatory at two surfaces.** Pattern lifted from a MIT-licensed repo. SKILL.md footer attribution AND `NOTICE`/`THIRD_PARTY_LICENSES.md` block (CLO: single-surface attribution insufficient for redistributable plugin).

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Founder outcome anchor | IP-safe handoff to buyer/investor | Forces redaction + disclaimers upstream into spec; ties to a recurring transaction. |
| Framework coverage v1 | Next.js only (App Router + Pages Router) | Matches Soleur stack; filesystem-driven route enum needs no parser; smallest YAGNI footprint. |
| Output path | `knowledge-base/product/prd/<project>-prd.md` (committed by default) | Matches `business-validator` convention; founder needs to share externally. Acceptable only with fail-closed redaction. |
| Redaction architecture | 4-layer fail-closed | (1) `git ls-files -c -o --exclude-standard` walker honors `.gitignore` and excludes `.env*`/`*.pem`/`*.key`/`secrets.*`. (2) `redact-sentinel.sh` on every input chunk before template render. (3) `redact-sentinel.sh` on rendered PRD before disk write — fail-closed (exit 1 → abort, no write). (4) `gitleaks detect --source <prd-file>` post-write verifier — re-runs and BLOCKS commit if anything escapes. |
| Secret posture (CLO) | REFUSE not flag | Replace matches with `[REDACTED:secret_type]`. Flag-only shifts liability onto founder; unacceptable for user-brand-critical surface. |
| PRD output banners | Dual mandatory | Top of every PRD: (a) due-diligence disclaimer ("not a substitute for code review, may omit material risks") + (b) PII/confidentiality notice ("may contain PII or proprietary content; review before sharing externally"). Non-removable by skill logic. |
| Coverage Caveats block | Mandatory in every PRD | Vector 2 mitigation. Enumerates files extractor declined, framework boundaries (e.g., dynamic routes detected but params not enumerated), and "best-effort vs. exhaustive" labels per section. |
| Field inventory | Cut from v1, deferred to v2 | Grep-based silently misses 30%; vendor's "exhaustive" promise is the largest leak surface. Re-evaluate when AST coverage is proven on Next.js. |
| spec-flow-analyzer integration | Skill orchestrates as closing pass | After PRD written + verified, skill spawns `spec-flow-analyzer` via Task on the written PRD. Agent appends `## Gap Analysis` section identifying missing flows, dead-ends, undocumented states. Same agent reviews both spec→code (existing) and code→spec (new). |
| Skill vs. agent | Hybrid (skill orchestrates agent) | Mirrors `incident` skill orchestrating redaction sentinel + structured phases. Skill = deterministic, agent = judgment-driven. |
| MIT attribution | SKILL.md footer + `NOTICE`/`THIRD_PARTY_LICENSES.md` | Required for redistributable plugin. CLO: single-surface insufficient. |
| Output template | Extend `spec-templates` skill with `prd.md` | Single source of truth for templates; avoids drift from canonical Soleur PRD shape. Reuses `component.md`'s frontmatter pattern (YAML with `updated`, `primary_location`) since PRD is derived-from-code. |
| Sequencing vs. #2718 siblings | After #2725 incident-commander, before #2727 karpathy-check | CPO ordering — incident-commander mitigates a higher-frequency founder pain (prod breakage > inherited-prototype handoff). |

## Open Questions

- **Coverage confidence file (deferred):** Should the skill also write a sibling `.prd-coverage.json` for machine-readable confidence per route/section? Defer to v2 — text Coverage Caveats sufficient for v1.
- **Next v2 framework:** Rails (server-rendered routes via `bin/rails routes --expanded` shell-out, CTO-validated) or Django (stdlib `ast` on `urls.py`)? Decide based on which paying founder shows up first.
- **Diagram support:** Vendor pattern includes page-relationship diagrams. Defer to v2 — text PRD only for v1, no Mermaid generation.
- **Redaction sentinel extension:** Should the sentinel detect SDK *call sites* (e.g., `new Stripe(...)`), not just literal keys? Currently catches keys only. Defer; if v1 surfaces this gap, add to `redact-sentinel.sh` upstream (benefits `incident` too).
- **AST tooling decision:** v1 is filesystem-driven (no AST needed for route enum). v2 field inventory requires tree-sitter-typescript availability — verify in pre-plan: `which tree-sitter`. If absent, factor install into plan.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Founder-ICP-shaped for the "inherited prototype / sell-side due diligence" archetype. Anchor on IP-safe handoff outcome — forces redaction upstream into spec. v1 scope cut: route + state + API; field inventory and exhaustive coverage deferred. Worst-case failure modes: credential leak in committed PRD posted to buyer's data room; silent-wrong PRD used as buyer ground truth. Recommended sequencing: after #2725 incident-commander.

### Legal (CLO)

**Summary:** MIT attribution required at TWO surfaces (SKILL.md footer + `NOTICE`/`THIRD_PARTY_LICENSES.md`); single-surface insufficient for redistributable plugin. Secret posture must be REFUSE (replace with `[REDACTED:type]`), not FLAG — flag-only shifts liability onto a tired founder. Dual banners mandatory: due-diligence disclaimer + PII/confidentiality notice, non-removable. Local-only operation = no DPA needed; obligation is disclosure-as-warning.

### Engineering (CTO)

**Summary:** Hybrid skill+agent (skill orchestrates `spec-flow-analyzer`) mirrors `incident` skill pattern. Framework detection: filesystem heuristics first (`package.json` + `next.config.{js,ts,mjs}`), operator `--framework` override for monorepos, reject ambiguous detections. Reuse `incident/scripts/redact-sentinel.sh` verbatim — 14 secret classes already covered. Walker = `git ls-files -c -o --exclude-standard` (matches `gdpr-gate`, respects `.gitignore`). Architectural pivot risk: grep-based field extraction silently misses 30% — mandatory `## Coverage Caveats` block. Complexity: 3-5 days for Next.js-only v1.

## Capability Gaps

| Gap | Domain | Why | Verification |
|-----|--------|-----|--------------|
| No centralized framework detector | Engineering | v1 needs `package.json + next.config.*` heuristic; v2 will add Rails/Django/etc. Natural home is a shared `scripts/detect-framework.sh` helper. | `git grep -l "next.config\|Gemfile\|manage.py" -- plugins/soleur/skills/` returned scattered inline checks only (CTO research, repo-research analyst report §8). |
| `tree-sitter` availability for v2 | Engineering | v2 field inventory needs AST per language. v1 does not require it. | `which tree-sitter && tree-sitter --version` (verify in plan-time). |
| `gitleaks` available in worktree | Engineering | Post-write verifier layer 4 needs `gitleaks detect --source <prd-file>`. `.gitleaks.toml` exists at repo root (CTO report) but binary must be on PATH at skill-run time. | `which gitleaks && gitleaks version`. If absent, factor `brew install gitleaks` (macOS) or fallback regex sweep into plan. |
| MIT attribution surfaces | Legal | `NOTICE` or `THIRD_PARTY_LICENSES.md` may not exist at repo root. | `test -f NOTICE -o -f THIRD_PARTY_LICENSES.md`. If absent, create as part of plan. |

## Bundled Scoping

- Parent issue #2718 (claude-skills competitive audit action plan) — Tier 2, sibling to #2723, #2724, #2725, #2727.
- Sequencing recommendation: defer until #2725 (incident-commander) ships. Re-evaluate after.

## Vendor Divergence Summary

Three load-bearing divergences from `alirezarezvani/claude-skills/product-team/code-to-prd`:

1. **Redaction stack:** vendor has none documented; Soleur ships 4-layer fail-closed.
2. **Framework scope:** vendor lists 12+ frameworks; Soleur ships Next.js-only v1.
3. **Orchestration:** vendor is two Python scripts (`codebase_analyzer.py` → `prd_scaffolder.py`); Soleur is a skill that orchestrates an existing agent (`spec-flow-analyzer`) for the gap-analysis layer.

Attribution: MIT notice preserved in `SKILL.md` footer + `NOTICE` entry.
