# Session State

## Plan Phase

- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-fix-repo-setup-git-clone-creds/knowledge-base/project/plans/2026-04-23-fix-repo-setup-git-clone-creds-plan.md
- Status: complete

### Errors

None. markdownlint passes with 0 errors.

### Decisions

- Root cause hypothesis: credential helper (`credential.helper=!${helperPath}`) is not being consulted in prod, likely due to container `/tmp` `noexec` or shell-invocation failure. No `GIT_TERMINAL_PROMPT=0` means silent fall-through to prompt, producing the observed `could not read Username ... No such device or address`. Phase 0 adds a definitive exec-probe (`chmod +x /tmp/x.sh && /tmp/x.sh`) — `mount | grep noexec` alone misses user-namespace bind mounts.
- Fix approach: switch all 5 call sites from `credential.helper=!<path>` to `GIT_ASKPASS`-based pattern via a new shared `server/git-auth.ts#gitWithInstallationAuth` helper. Token is passed via `GIT_INSTALLATION_TOKEN` env var (never interpolated into script body or argv), eliminating shell-injection class. Plan sets `GIT_TERMINAL_PROMPT=0`, `GIT_CONFIG_NOSYSTEM=1`, and resets inherited `credential.helper` via `-c credential.helper=` since git docs confirm `credential.helper` wins over `GIT_ASKPASS` when configured.
- Preflight repo-access check: Phase 3 adds `GET /repos/{owner}/{repo}` with the installation token BEFORE clone to distinguish `REPO_ACCESS_REVOKED`, `REPO_NOT_FOUND`, `INSTALLATION_SUSPENDED` from generic clone failures.
- UX remediation: Phase 4 adds `errorCode` field, code-mapped copy in `FailedState`, and CTA for reinstall when installation access is revoked. Raw git stderr moved into collapsible `<details>` for support, not the default visible message.
- Token-validator drift-proofing: permissive regex `^ghs_[A-Za-z0-9_-]{30,128}$`; log-warn on mismatch but DO NOT throw (GitHub does not document the token format, so a throw is a latent outage class).
- Diagnostic retry: one-shot retry with `GIT_TRACE=1 GIT_CURL_VERBOSE=1` on `AUTH_FAILED` when preflight succeeded (only routes to logs/Sentry, never to user-visible `repo_error`). Feature-flagged via `CLONE_DIAGNOSTIC_RETRY` and scheduled for removal post-stabilization.

### Components Invoked

- skill: soleur:plan (generated initial plan)
- skill: soleur:deepen-plan (deepened with parallel research)
- WebFetch (git-scm.com/docs/gitcredentials)
- WebFetch (docs.github.com REST API)
- WebSearch (GIT_ASKPASS + Node.js + installation token patterns)
- WebSearch (container/Docker credential-helper silent-failure class)
- WebSearch (git askpass shell-injection hardening)
- npx markdownlint-cli2 --fix
