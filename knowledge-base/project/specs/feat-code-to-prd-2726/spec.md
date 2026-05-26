---
feature: code-to-prd
issue: 2726
parent_issue: 2718
branch: feat-code-to-prd-2726
pr: 3783
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-05-15-code-to-prd-brainstorm.md
---

# Feature: code-to-prd skill

## Problem Statement

Solo founders frequently inherit undocumented Next.js prototypes (contractor handoff, small acquisition, abandoned cofounder). When the founder needs to share that codebase context externally — with a buyer in due diligence, with an investor, with a contractor under NDA, or with a coding agent for onboarding — there is no fast, safe way to produce a PRD-style document. Manual write-up takes days. Letting a generic LLM scrape the repo risks leaking secrets, PII, or proprietary IP into the output. Existing Soleur skills go the opposite direction (`spec-flow-analyzer` reads a spec and finds code gaps); nothing reads code and writes a spec.

## Goals

- A founder can run `code-to-prd` against a Next.js codebase and receive a structured PRD markdown document in `knowledge-base/product/prd/<project>-prd.md` within minutes.
- The PRD contains a route map, top-level state-shape summary, and external API/dependency inventory — enough for a buyer's CTO or onboarding agent to orient.
- Every PRD ships with mandatory due-diligence and PII banners, MIT attribution, and a `## Coverage Caveats` block that enumerates extractor limits honestly.
- Secret redaction is automated and fail-closed at four independent layers; the founder is not the last line of defense.
- The skill reuses existing Soleur infrastructure: `incident/scripts/redact-sentinel.sh`, `spec-flow-analyzer` agent, `spec-templates` PRD template.

## Non-Goals

- v1 does **not** support Rails, Django, Flask, FastAPI, Express, NestJS, Vue, Svelte, Remix, or any framework other than Next.js (App Router + Pages Router).
- v1 does **not** produce an exhaustive field inventory. State-shape summary only.
- v1 does **not** generate diagrams (page-relationship or otherwise) — text PRD only.
- v1 does **not** invoke any third-party API for analysis — local-only operation.
- v1 does **not** auto-commit the generated PRD. Operator opens a PR review window.
- The skill does **not** call other Soleur skills programmatically (skill-cannot-invoke-skill constraint). It spawns agents via Task and instructs the operator to run downstream skills.

## Functional Requirements

### FR1: Framework detection

Skill detects Next.js by presence of `package.json` AND one of `next.config.{js,ts,mjs}`. If detection is ambiguous or framework is not Next.js, the skill MUST refuse to run and emit a clear error pointing the operator to v2 framework roadmap.

### FR2: Filesystem walk

Skill walks the target codebase using `git -C <target> ls-files -c -o --exclude-standard` to honor `.gitignore` semantics. Pre-scan filter additionally excludes any path matching `.env*`, `secrets.*`, `*.pem`, `*.key`, `credentials.*`, `master.key`, or `.git/**`. No file matching these patterns is read into memory under any condition.

### FR3: Route extraction (Next.js)

For App Router: enumerate `app/**/page.{tsx,jsx,ts,js}` and `app/**/route.{ts,js}`. For Pages Router: enumerate `pages/**/*.{tsx,jsx,ts,js}` excluding `pages/_*.{tsx,jsx,ts,js}`. For each route, capture: HTTP methods (for route handlers), dynamic segments, and a one-line description sourced from JSDoc/TSDoc on the default export when present.

### FR4: State-shape summary (not exhaustive)

For each route, identify top-level state hooks (`useState`, `useReducer`, server component props) via filesystem regex. Capture variable name and type annotation where syntactically obvious. Files where extraction confidence falls below threshold are appended to `## Coverage Caveats`.

### FR5: API/external dependency inventory

Scan all walked files for: `fetch()` call sites with literal string URLs, named imports from `@/lib/api*` or `@/server/*`, and `process.env.*` references (env var *names* only — values never read). Cross-reference `package.json` dependencies and flag third-party SDK packages (e.g., `stripe`, `@supabase/*`, `openai`).

### FR6: Redaction stack (3 layers, fail-closed)

Revised post-plan-review (DHH + Simplicity converge: the original Layer 2 input-sanitization ran the same sentinel script on overlapping bytes as Layer 3 — redundant defense-in-paint, not defense-in-depth).

- **Layer 1 — pre-scan exclusion:** FR2 path filter (walker output filtered through deny-list before any file is read).
- **Layer 2 — pre-write sentinel:** rendered PRD passes through `redact-sentinel.sh` immediately before disk write. Exit code 1 (matches found) MUST abort write and surface the matched secret types to the operator. No partial PRD ever lands on disk.
- **Layer 3 — post-write verifier:** `gitleaks detect --source <prd-file> --no-git --report-format json`. Any finding MUST delete the written PRD and verify `test ! -e <path>` (FR6.1). `gitleaks` is a Phase 0 preflight precondition (FR6.2) — the skill aborts at Phase 0 if the binary is not on PATH. Layer 3 is always present at runtime.

### FR7: PRD output

Output path: `knowledge-base/product/prd/<project-name>-prd.md` where `<project-name>` is derived from `package.json` `name` (sanitized to kebab-case). Output begins with mandatory banners:

```
> **Generated by Soleur `code-to-prd` on YYYY-MM-DD.** Not a substitute for code review, security audit, or legal review. May omit material risks, undocumented behaviors, or runtime dependencies. Do not rely on as sole basis for acquisition decisions.
>
> **May contain PII, fixtures, or internal references extracted from source comments and seed data.** Review and redact before sharing externally. Verbatim code comments and algorithm descriptions may be included — review for proprietary content before contractor handoff.
```

Sections (in order): Banners → Overview (project name, framework detected, walk stats) → Routes → State Shapes → API & External Dependencies → Coverage Caveats → Gap Analysis (populated by FR8) → MIT Attribution footer.

### FR8: Gap analysis via spec-flow-analyzer

After PRD is written and post-write verifier passes, skill spawns `@agent-soleur:product:spec-flow-analyzer` via Task with the written PRD path. Agent appends a `## Gap Analysis` section identifying missing flows, dead-ends, undocumented error states, and undocumented entry points. Skill MUST NOT proceed if the agent reports the PRD path could not be read.

### FR9: MIT attribution

SKILL.md footer reads: `Adapted from alirezarezvani/claude-skills (MIT) — see plugins/soleur/NOTICE`. **Plugin-root** `plugins/soleur/NOTICE` (NOT repo-root per Kieran plan-review P1 — plugin is the unit of redistribution) contains full MIT text and upstream copyright line. Drift detection is NOT in v1 (DHH + Simplicity converge on YAGNI); v2 may add a dedicated `scripts/check-notice-drift.sh`.

### FR10: Coverage Caveats block

Mandatory section enumerating: files the extractor declined (with reason), framework boundaries (dynamic routes detected but params not enumerated, server actions not traced through), and "best-effort vs. exhaustive" labels per section. Block is non-empty for every PRD even if extractor ran cleanly — at minimum lists declined framework features.

## Technical Requirements

### TR1: Skill location and structure

`plugins/soleur/skills/code-to-prd/` with: `SKILL.md` (≤35-word description per skill-description-budget rule), `scripts/walk-and-extract.sh`, `scripts/render-prd.sh`, `references/banner-template.md`, `references/prd-template.md`. Add to `plugins/soleur/docs/_data/skills.js` `SKILL_CATEGORIES` map under `product-team`.

### TR2: Reuse of `incident/scripts/redact-sentinel.sh`

Skill MUST invoke the existing sentinel verbatim — no parallel redaction implementation. Per `hr-write-boundary-sentinel-sweep-all-write-sites`, every write site routes through one shared helper. Sweep verification belongs in the implementation review.

### TR3: Walker primitive

`git -C <target> ls-files -c -o --exclude-standard` only. No `find` traversal of the user's filesystem. Per FR2, the pre-scan path filter is applied to walker output before any file is read.

### TR4: No skill-from-skill invocation

Per `2026-02-18-skill-cannot-invoke-skill.md`, the skill MUST NOT shell out to `/soleur:gdpr-gate` or any other Soleur skill. If gap analysis identifies regulated-data surfaces, the skill prints a recommendation to run `/soleur:gdpr-gate` and exits — does not invoke.

### TR5: Description budget

SKILL.md `description:` field MUST fit ≤35 words, ≤1024 chars. Plugin-wide description budget is at 99% capacity (per learning #1 `2026-03-15-skill-description-budget-prevents-context-compaction-loss.md`); a verbose description blocks compaction-safe loading.

### TR6: Agent spawn pattern

The `spec-flow-analyzer` Task spawn uses the prompt pattern documented at `plugins/soleur/skills/plan/SKILL.md:298`, adapted to read a written PRD instead of a planning doc.

### TR7: spec-templates extension

Add a `prd.md` template to `plugins/soleur/skills/spec-templates/SKILL.md` documenting the section order from FR7. Reuses `component.md`'s frontmatter pattern (`updated`, `primary_location`) since the PRD is derived-from-code and benefits from source tracking.

### TR8: Test fixture

`plugins/soleur/skills/code-to-prd/test/fixture/` contains a minimal Next.js skeleton (3 routes, NO server action — v1 does not extract them) with deliberate `STRIPE_SECRET_KEY=sk_test_<<24+ alnum chars, no underscores>>` (alnum-only after prefix, verified to match sentinel regex `sk_(test|live)_[A-Za-z0-9]{16,}` — the original `sk_test_<<tail-with-underscores>>` would NOT have matched because `_` ∉ `[A-Za-z0-9]`; caught by Kieran plan-review P0). Test asserts the full 11-assertion set in plan Phase 6. Fixture is synthesized only — never real secrets (per `cq-test-fixtures-synthesized-only`). Allowlist sequencing: commit `.gitleaks.toml` allowlist entry FIRST, then fixture in a SEPARATE commit (Kieran P0-3 — pre-commit hook reads allowlist from HEAD).

### TR9: Sequencing

Defer scheduling of implementation work until #2725 (incident-commander) merges. Re-evaluate at that point.

## Acceptance Criteria

- Running the skill against the test fixture (TR8) produces a PRD with all required sections, banners present, zero secrets in output, MIT attribution intact, `## Coverage Caveats` non-empty.
- Layer 3 sentinel halts the write when fixture contains a fresh secret pattern; verifier (Layer 4) deletes the file if Layer 3 is bypassed for any reason.
- `spec-flow-analyzer` Task appends `## Gap Analysis` and the skill exits successfully.
- SKILL.md frontmatter passes `scripts/package_skill.py` validation including description-budget check.
- `NOTICE` (or `THIRD_PARTY_LICENSES.md`) contains the MIT block for `alirezarezvani/claude-skills`.
- Plan-time triad (CPO + CLO + CTO) sign-off recorded per `hr-new-skills-agents-or-user-facing`.
