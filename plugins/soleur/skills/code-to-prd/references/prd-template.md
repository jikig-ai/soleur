# PRD Template — code-to-prd output structure

Canonical section order for `knowledge-base/product/prd/<project>-prd.md` emitted by `plugins/soleur/skills/code-to-prd/scripts/code-to-prd.sh`. Mirrored by the `prd.md` template in `plugins/soleur/skills/spec-templates/SKILL.md`.

## Required frontmatter

```yaml
---
project: "<package.json name, kebab-case>"
framework: "next.js"
generator: "code-to-prd@v1"
generated_at: "<ISO-8601 UTC>"
walker_count: <int>
walker_excluded: <int>
---
```

## Section order (FR7)

1. **Banners** — dual non-removable disclaimers + inline `### How to Read This PRD` (verbatim from [banner-template.md](./banner-template.md)).
2. **Overview** — project name, framework detected, walk stats (tracked-file count, excluded-file count).
3. **Routes**
   - App Router — `app/**/page.{tsx,jsx,ts,js}` + `app/**/route.{ts,js}` (with HTTP methods).
   - Pages Router — `pages/**/*.{tsx,jsx,ts,js}` excluding `pages/_*`.
4. **State Shapes** — top-level `useState`/`useReducer`/server-component props (regex, best-effort).
5. **API & External Dependencies** — `fetch()` literal URLs + `@/lib/api*`/`@/server/*` imports + `process.env.*` names (values never read) + third-party SDK packages from `package.json`.
6. **Coverage Caveats** — FOUR mandatory subsections (FR10.1):
   - Frameworks not scanned (Rails, Django, etc.).
   - Extraction techniques used (regex-only, no AST).
   - What was excluded by path filter (count + category, not paths).
   - GDPR Art. 9 special-category disclaimer.
7. **Gap Analysis** — populated by `@agent-soleur:product:spec-flow-analyzer` Task spawn (FR8). Degraded-success appends `SKIPPED (spec-flow-analyzer unavailable at <ISO-8601>)`.
8. **MIT Attribution footer** — single line pointing at `plugins/soleur/NOTICE`.

## Banner contract

Banners are **non-removable** — operator-edit of the rendered PRD is allowed, but the dual-banner block must remain intact. Verbatim string match enforced by Phase 6 test assertion #6.

## Coverage Caveats contract

The `## Coverage Caveats` block MUST be non-empty on every run. "None" is forbidden. The four subsections are mandatory regardless of extractor coverage — even on a maximally simple input.
