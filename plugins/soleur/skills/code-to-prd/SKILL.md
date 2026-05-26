---
name: code-to-prd
description: "This skill should be used when generating a PRD from a Next.js codebase for buyer/investor/agent handoff. Walks tracked files, redacts secrets, writes structured markdown to knowledge-base/product/prd/."
---

# Code-to-PRD

Reverse-engineer a Next.js codebase (App Router + Pages Router) into a PRD markdown document the founder can hand to a buyer, investor, or coding agent. Output lands at `knowledge-base/product/prd/<project>-prd.md`. v1 ships Next.js-only; Rails/Django and exhaustive field inventory deferred to v2 (#3794).

## When to Use

- Inherited Next.js prototype heading into buyer/investor due diligence.
- Founder needs to onboard a coding agent or contractor to an unfamiliar codebase.
- Sell-side IP handoff where the founder needs a structured artifact but cannot share raw source.

## Output

Single PRD at `knowledge-base/product/prd/<project>-prd.md` where `<project>` is the kebab-cased `package.json` `name`. **A second run with a target whose `package.json` `name` matches an earlier run overwrites the prior PRD** — the script emits a loud `WARNING — overwriting existing PRD at ...` on stderr so a wrong-codebase PRD does not reach a buyer's data room silently. Commit or rename the previous PRD before regenerating against a different codebase.

The PRD contains:

1. **Banners** — dual non-removable disclaimers (due-diligence + PII/confidentiality) + inline `### How to Read This PRD` subsection explaining redaction tokens.
2. **Overview** — project name, framework detected, walk stats.
3. **Routes** — App Router (`app/**/page.{tsx,jsx,ts,js}`, `app/**/route.{ts,js}`) and Pages Router (`pages/**/*.{tsx,jsx,ts,js}` excluding `pages/_*`).
4. **State Shapes** — top-level `useState`/`useReducer`/server-component props (best-effort regex).
5. **API & External Dependencies** — `fetch()` literal URLs + `@/lib/api*`/`@/server/*` imports + `process.env.*` names (values never read) + third-party SDK packages from `package.json`.
6. **Coverage Caveats** — frameworks not scanned + extraction techniques + path-filter exclusion counts + Art. 9 special-category disclaimer.
7. **Gap Analysis** — produced by `@agent-soleur:product:spec-flow-analyzer` Task spawn after the PRD is written and verified.
8. **MIT Attribution** — footer pointing at `plugins/soleur/NOTICE`.

## Redaction (3-layer, fail-closed)

The skill is user-brand-critical (`single-user incident` threshold). Redaction is automated and fail-closed; the founder is NOT the last line of defense.

- **Layer 1 — path exclusion.** Walker uses `git -C <target> ls-files -c -o --exclude-standard` (honors `.gitignore`) and an explicit deny-list: `.env*`, `secrets.*`, `*.pem`, `*.key`, `credentials.*`, `master.key`, `.git/**`. Symlinks resolving outside `<target>` are rejected via `realpath`.
- **Layer 2 — pre-write sentinel.** Rendered PRD passes through [redact-sentinel.sh](../incident/scripts/redact-sentinel.sh) immediately before disk write. Exit code 1 (matches found) MUST abort the write. No partial PRD ever lands on disk.
- **Layer 3 — post-write verifier.** `gitleaks detect --source <prd-file> --no-git --report-format json` is the independent verifier. Any finding deletes the PRD and verifies the deletion succeeded. `gitleaks` is a Phase 0 preflight precondition — the skill refuses to start without it.

## Preconditions

- `gitleaks` binary on PATH (Layer 3 verifier).
- `<target>` contains a `package.json` at the root.
- `<target>` is under git OR contains tracked files (`git ls-files` returns ≥1 entry).
- Framework detected as Next.js (presence of `next.config.{js,ts,mjs}` alongside `package.json`).

## Resources

- [prd-template.md](./references/prd-template.md) — canonical PRD section order + frontmatter (Phase 4).
- [banner-template.md](./references/banner-template.md) — dual banners + inline How-to-Read content (Phase 4).
- [code-to-prd.sh](./scripts/code-to-prd.sh) — entry-point script.

## Implementation Status

Scaffold landed (Phase 0); full implementation in progress per `knowledge-base/project/plans/2026-05-15-feat-code-to-prd-skill-plan.md`. See `knowledge-base/project/specs/feat-code-to-prd-2726/tasks.md` for phase progress.

---

_Adapted from `alirezarezvani/claude-skills` (MIT) — see [plugins/soleur/NOTICE](../../NOTICE)._
