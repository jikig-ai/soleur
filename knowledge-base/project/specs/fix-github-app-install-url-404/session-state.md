# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-04-03-fix-github-app-install-url-404-plan.md
- Status: complete

### Errors

None

### Decisions

- Root cause is twofold: GitHub App is private/missing + slug `soleur-ai` is hardcoded but doesn't resolve
- Credentials never provisioned: `GITHUB_APP_ID` and `GITHUB_APP_PRIVATE_KEY` absent from all Doppler configs
- `NEXT_PUBLIC_GITHUB_APP_SLUG` must be added as Docker build ARG (Next.js inlines at build time)
- Defense-in-depth: server-side `getAppSlug()` function dynamically fetches slug via `GET /app`
- MINIMAL detail level — straightforward bug fix with clear root cause

### Components Invoked

- `soleur:plan` — created initial plan with local research and evidence gathering
- `soleur:deepen-plan` — enhanced with GitHub Docs research, codebase analysis, and institutional learnings
