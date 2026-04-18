# Tasks — fix invalid ollama command on /getting-started/

Plan: `knowledge-base/project/plans/2026-04-18-fix-invalid-ollama-command-getting-started-plan.md`
Issue: #2550 (P0, `domain/marketing`, `type/bug`)

## 1. Setup

- [x] 1.1 Verify on branch `feat-one-shot-2550-fix-ollama-command` (worktree already active).
- [x] 1.2 Confirm no uncommitted changes before starting (`git status --short`).

## 2. Core Implementation (single commit)

- [x] 2.1 Edit `plugins/soleur/docs/pages/getting-started.njk`:
  - [x] 2.1.1 Delete the `<div class="callout">` at lines ~66–68 containing `ollama launch claude --model gemma4:31b-cloud`.
  - [x] 2.1.2 In the FAQ answer at lines ~172–173, delete the sentence "Alternatively, you can run Soleur using Ollama via the `ollama launch` command." Leave the rest of the answer intact.
  - [x] 2.1.3 Mirror 2.1.2 into the `application/ld+json` `FAQPage` `text` field at lines ~206–210. The visible answer and the JSON-LD `text` must remain string-identical.
- [x] 2.2 Edit `plugins/soleur/README.md`:
  - [x] 2.2.1 Delete line 13 (`**Running with Ollama?** Use`ollama launch …``) and the paired blank line.
- [x] 2.3 Edit root `README.md`:
  - [x] 2.3.1 Delete line 31 (`**Running with Ollama?** Use`ollama launch …``) and the paired blank line.

## 3. Verification

- [x] 3.1 Regression grep (must return empty) — from worktree root:

  ```bash
  grep -rn --include='*.njk' --include='*.md' --include='*.html' \
    --exclude-dir=knowledge-base --exclude-dir=node_modules --exclude-dir=_site \
    -e 'ollama launch' -e 'gemma4:31b-cloud' \
    .
  ```

- [x] 3.2 Run `npx markdownlint-cli2 --fix plugins/soleur/README.md README.md` (targeted, per AGENTS.md `cq-markdownlint-fix-target-specific-paths`).
- [x] 3.3 Build the docs site from the repo root: `npm ci && npm run docs:build` (Eleventy 3.x). Do NOT run `npm run build` inside `plugins/soleur/docs/` — that script does not exist.
- [x] 3.4 Serve the build and manually load `/getting-started/`:
  - [x] 3.4.1 Confirm the "Existing project? / Starting fresh?" callout still renders.
  - [x] 3.4.2 Confirm the Ollama callout is gone.
  - [x] 3.4.3 Confirm the FAQ answer reads cleanly (no dangling "Alternatively" fragment).
- [x] 3.5 Validate JSON-LD: rendered FAQ `<p class="faq-answer">` text must match the JSON-LD `text` field verbatim. Paste into Google Rich Results Test if in doubt.

## 4. Ship

- 4.1 `/ship` creates the PR. PR body includes `Closes #2550`, `Ref #2549`, `## Changelog`, and `semver:patch` label.
- 4.2 Queue auto-merge: `gh pr merge <N> --squash --auto`.
- 4.3 Poll to MERGED and run `cleanup-merged`.
- 4.4 Post-merge: confirm next docs-site deploy renders cleanly on soleur.ai/getting-started/.

## Non-Goals (do NOT do in this PR)

- Write `/docs/local-models/` and re-introduce a callout. Separate roadmap item.
- Rewrite historical knowledge-base references to the bad command (audit, roadmap row 3.27, community digests, prior spec). Audit trail stays intact.
- Substitute a different Ollama command (e.g., `ollama run gemma2:27b`). Audit R5 prescribes removal until the linked doc exists.
