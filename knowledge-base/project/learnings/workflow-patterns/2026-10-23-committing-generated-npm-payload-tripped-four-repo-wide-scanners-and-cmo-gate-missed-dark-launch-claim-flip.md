---
title: "Committing a generated npm payload tripped four repo-wide scanners, and dark-launched claim flips bypassed the CMO gate"
date: 2026-10-23
category: workflow-patterns
tags: [opencode, npm, packaging, ci, cmo, gtm]
module: plugins/soleur
symptom: "PR #10723 failed gitleaks, markdown-lint, lint-trap-tempfile-ownership, and dependency-review when the generated @soleur/opencode payload was committed to git, and the OpenCode launch arc (#10571 -> #10815 -> #10723) never triggered CMO content generation."
root_cause: "1) Repo-wide scanners allowlist fixtures and lockfiles under canonical plugins/soleur/ paths, so committing a second copy under packages/opencode-plugin/ duplicated test fixtures outside those allowlists; mutating the live repo tree during bun test also raced directory-walking suites. 2) ship Phase 5.5's CMO Content-Opportunity Gate and tweet-eligibility.sh exclude docs(claim): PRs and non-app:web-platform PRs."
---

# Committing a generated npm payload tripped four repo-wide scanners, and dark-launched claim flips bypassed the CMO gate

## Context

When packaging the Soleur OpenCode adapter as `@soleur/opencode` (`packages/opencode-plugin/`), `npx @soleur/opencode install` must vendor `PAYLOAD_DIRS` (`skills`, `agents`, `commands`, `hooks`, `scripts`, `lib`, `opencode`, `.claude-plugin`) into `<configdir>/soleur/` so installed references survive `npx` / `bunx` cache eviction.

## What Went Wrong

1. **Committed generated payload vs. path-anchored repo scanners:** Committing the ~800 generated payload files into `packages/opencode-plugin/` caused four CI checks to fail simultaneously (`gitleaks scan`, `markdown-lint`, `lint-bot-statuses` / `lint-trap-tempfile-ownership.py`, and `dependency-review`) because canonical exemptions in `.gitleaks.toml`, `.markdownlintignore`, and trap-ownership allowlists are anchored to `plugins/soleur/...`.
2. **In-tree materialization during `bun test`:** Materializing the payload into the live `packages/opencode-plugin/` directory in `beforeAll` and deleting it in `afterAll` risked leaving ~800 untracked files on test interruption and raced concurrent filesystem-walking suites.
3. **Executable mode loss (`0755` -> `0644`):** Copying payload files via `readFileSync(..., "utf-8")` + `writeFileSync` stripped executable bits from `hooks/*.sh` and `scripts/*.sh`.
4. **CMO gate blind spot on dark-launch → claim-flip arcs:** Across the OpenCode arc (`#10571` adapter build → `#10745` live dogfood → `#10815` `docs(claim):` public flip → `#10723` npm package), the build PR held back public claims while the claim-flip PR (`docs(claim):`) and plugin package PR (`packages/opencode-plugin/`) missed `ship` Phase 5.5's CMO trigger paths and `tweet-eligibility.sh`'s `app:web-platform` filter.

## Resolution

- Keep only the hand-written package files (`package.json`, `README.md`, `install.js`, `bin/soleur-opencode.js`) tracked in git under `packages/opencode-plugin/`, gitignore the generated payload subtrees, and materialize them via `bun plugins/soleur/scripts/sync-npm-package.ts` (`--out-dir` into a hermetic `mkdtempSync` directory during `bun test`, and into `packages/opencode-plugin/` in `.github/workflows/npm-publish.yml`).
- Preserve executable file permissions (`statSync(full).mode & 0o111` → `chmodSync(..., 0o755)`) in both `sync-npm-package.ts` and `install-opencode-adapter.ts`.
- Trigger `npm-publish.yml` on `workflow_run` of `"Version Bump and Release"` (since `GITHUB_TOKEN`-authored releases do not fire `on: release:` workflows) as well as `release` and `main`-guarded `workflow_dispatch`.
