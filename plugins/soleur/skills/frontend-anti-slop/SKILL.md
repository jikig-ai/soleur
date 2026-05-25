---
name: frontend-anti-slop
description: This skill should be used when auditing React/Next.js source for Hallmark-adapted anti-AI-slop patterns via a deterministic Tailwind/JSX scanner.
version: 1.0.0
---

# frontend-anti-slop

A deterministic source-static audit for React/Next.js components that flags AI-default visual and microinteraction patterns adapted from [Nutlope/hallmark](https://github.com/Nutlope/hallmark) (MIT). v1 ships 15 Tier 1 ripgrep gates over `apps/web-platform/{app,components}/**/*.{tsx,jsx,css}`. v1.5 (post-calibration) adds a Tier 2 LLM-judgment reviewer agent for the ~12 gates regex cannot resolve.

> **Attribution.** Rule set and anti-pattern names adapted from Hallmark (Together AI, MIT). Verbatim license at [`/LICENSES/hallmark.MIT.txt`](../../../../LICENSES/hallmark.MIT.txt); upstream stanza in [`/plugins/soleur/NOTICE`](../../NOTICE).

## When this skill fires

- Invoked by `soleur:review` when a PR touches `apps/web-platform/(app|components)/.*\.(tsx|jsx|css)$`. See `plugins/soleur/skills/review/SKILL.md § Anti-slop Scanner Hook`.
- Manual: `/soleur:frontend-anti-slop --paths <files-or-dirs> [--dry-run|--json] [--rule <ID>]`.

The scanner is **non-blocking by design** — exit code is 0 regardless of finding count. v1 ships in calibration mode: findings surface in PR review output for operator review, no auto-filing to GitHub issues. Calibration unlocks v1.5 (auto-file + Tier 2 agent) at ≤ 10% FP rate over ≥ 20 findings ≥ 2 weeks.

## Invocation

```bash
# Default — scans staged + modified frontend files vs. the index.
bun run plugins/soleur/skills/frontend-anti-slop/scripts/tier1-scan.ts

# Explicit paths (files or directories).
bun run plugins/soleur/skills/frontend-anti-slop/scripts/tier1-scan.ts \
  --paths apps/web-platform/components/ui/ --json

# Single rule.
bun run plugins/soleur/skills/frontend-anti-slop/scripts/tier1-scan.ts \
  --paths apps/web-platform/components/ --rule GRADIENT-TEXT --json
```

Skill tool form:

```text
Skill(skill: "soleur:frontend-anti-slop")
Skill(skill: "soleur:frontend-anti-slop", args: "--paths apps/web-platform/components/ui/ --json")
```

## Scope

| In scope (v1) | Out of scope |
|---|---|
| `apps/web-platform/(app|components)/**/*.{tsx,jsx,css}` | Other apps in the monorepo (`web-platform-docs`, infra apps) |
| 15 deterministic Tier 1 gates (regex-only) | Tier 2 LLM-judgment gates (deferred to v1.5) |
| Source-static analysis | Rendered-DOM / screenshot analysis (that's [`soleur:ux-audit`](../ux-audit/SKILL.md)) |
| JSON output matching [`finding.schema.json`](../ux-audit/references/finding.schema.json) | Auto-filing GitHub issues |
| `<!-- anti-slop:disable RULE_ID reason="..." -->` per-file overrides | AST-based gates (CARD-IN-CARD, focus states) — v1.5 with ts-morph |

## Rule set

The 15 Tier 1 gates live in [slop-rules.md](./references/slop-rules.md) as a parsed Markdown table. Each row: `id`, `tier`, `category`, `hallmark_gate`, `severity`, `pattern`, `message`, `suggested_fix`. The scanner filters to `tier === 1` and runs each `pattern` regex line-by-line over target files.

React/Tailwind code examples for each rule live in [anti-patterns.md](./references/anti-patterns.md).

Findings emit as JSON conforming to `finding.schema.json`:

```json
{
  "route": "",
  "selector": "<file-path>#<RULE-ID>",
  "category": "anti-slop",
  "severity": "high",
  "title": "<rule message> (rule <ID>)",
  "description": "<rule message>. Detected at <path>:<line>.",
  "fix_hint": "<rule suggested_fix>",
  "screenshot_ref": "/tmp/anti-slop/no-screenshot.png"
}
```

The `selector` overload (`<file>#<RULE-ID>`) reuses the existing `soleur:ux-audit` dedup hash (`sha256("route|selector|category")`) without a `Finding` interface change — see plan §"Research Reconciliation #2".

## Per-file rule disable

To intentionally use a flagged pattern (designer-mandated gradient, brand-specific font), add a comment in the source file:

```tsx
{/* anti-slop:disable GRADIENT-TEXT reason="brand-mandated marketing hero gradient" */}
<h1 className="bg-clip-text text-transparent bg-gradient-to-r from-soleur-accent-gradient-start to-soleur-accent-gradient-end">
  ...
</h1>
```

Disable comments work in JSX comment form (`{/* ... */}`), HTML-comment form (`<!-- ... -->`), or CSS-comment form (`/* ... */`) — the scanner matches the literal `anti-slop:disable <RULE_ID>` substring.

## Calibration mode

v1 ships in calibration mode (no auto-filing). The promotion gate to v1.5 (auto-file + Tier 2 agent):

- ≥ 20 findings logged over ≥ 2 weeks of dogfood
- ≤ 10% operator-confirmed false-positive rate

The follow-up issue filed at merge tracks the calibration window. v1.5 picks up when the gate trips.
