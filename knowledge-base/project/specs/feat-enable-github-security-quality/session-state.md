# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-04-10-feat-enable-github-security-quality-plan.md
- Status: complete

### Errors

None

### Decisions

- Use CodeQL default setup (managed by GitHub) over advanced setup (custom workflow YAML) since the repository has no compiled languages requiring custom build steps
- Use the extended query suite to cover both security vulnerabilities AND code quality findings
- Use remote_and_local threat model instead of default remote because the repo's shell scripts and GitHub Actions workflows heavily use environment variables and CLI arguments as data sources *(Superseded 2026-04-16: switched to `remote` — see Threat Model Update below)*
- Include actions, javascript-typescript, python languages; exclude ruby (only template assets, not runtime code)
- Keep CodeQL advisory-only (not added to CI Required ruleset) for initial rollout to avoid disrupting existing workflows

### Components Invoked

- soleur:plan -- created initial plan with local research, domain review, API verification, and learnings integration
- soleur:deepen-plan -- enhanced plan with external research, learnings integration, live API queries

## Threat Model Update (2026-04-16)

- **Change:** Switched CodeQL threat model from `remote_and_local` to `remote`
- **Issue:** #2418
- **Reason:** 100 false positives from `local` taint sources (env vars, file paths)
  dismissed in PR #2416. Switching to `remote` prevents recurrence on future PRs.
- **API:** `gh api -X PATCH repos/jikig-ai/soleur/code-scanning/default-setup`
  with `"threat_model": "remote"`
