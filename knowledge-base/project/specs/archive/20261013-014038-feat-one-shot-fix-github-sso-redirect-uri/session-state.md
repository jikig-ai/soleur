# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-fix-github-sso-redirect-uri/knowledge-base/project/plans/2026-05-04-fix-github-sso-redirect-uri-mismatch-plan.md
- Status: complete

### Errors
None — but a major mid-deepen finding inverted the leading hypothesis. Live curl probes against both OAuth flows during deepen-plan returned HTTP 200 + login form (not the error page) and zero matches for `redirect_uri is not associated`. The original plan's leading hypothesis (Flow B github-resolve callback URL missing) is rejected as the current cause; plan re-prioritised to H_A (already-fixed) and H_B (custom-domain dual-registration drift).

### Decisions
- **Two flows, ONE client_id.** Both `signInWithOAuth({provider:"github"})` (Supabase-mediated) and `/api/auth/github-resolve` use the same GitHub App `Iv23li9p88M5ZxYv1b7V`. The GitHub App's callback URL list governs both — single point of change, single point of failure.
- **Three callback URLs required** in the GitHub App: `https://app.soleur.ai/api/auth/github-resolve/callback`, `https://api.soleur.ai/auth/v1/callback` (custom-domain advertised by Supabase), AND `https://ifsccnjhymdmidffkzhl.supabase.co/auth/v1/callback` (canonical fallback per Supabase custom-domain docs).
- **Probe extension covers all three URLs**, asserts HTTP 200 + body grep for `redirect_uri is not associated` AND `Application suspended`, plus positive `<form` proof. Both healthy and failing states return HTTP 200 — body grep is load-bearing.
- **Workflow gate fix** in `/ship` Phase 7 Step 3.5: follow-through issues require verbatim redirect_uri + workflow run ID + callback-URL byte count before close (retroactively addresses the #1784 closure-without-verification recurrence).
- **No code changes** — `route.ts` is correct, Doppler `prd` is correct (`NEXT_PUBLIC_APP_URL`, `GITHUB_CLIENT_ID` verified). All work is config audit + observability + workflow gate.
- **User-Brand Impact threshold = `single-user incident`** → CPO sign-off required at plan time, `user-impact-reviewer` at review time.

### Components Invoked
- skill: soleur:plan
- skill: soleur:deepen-plan
- WebFetch (3×): docs.github.com user-authorization-callback-url, troubleshooting-authorization-request-errors, supabase.com auth-github + custom-domains
- WebSearch (2×): GitHub callback rules, Supabase custom-domain dual-registration
- ToolSearch (deferred-tool schema fetch)
- Bash live probes: github-resolve flow + Supabase-mediated flow against prod
- Doppler audits: `prd`, `dev`, `ci`, `prd_terraform` configs for `GITHUB_CLIENT_ID` / `NEXT_PUBLIC_APP_URL` / `NEXT_PUBLIC_SUPABASE_URL`
- gh CLI: issue search (#1784, #2979, #2997), workflow run inspection (`scheduled-oauth-probe.yml`), App API (`/app`, `/app/installations`)
- Phase 4.5 (Network-Outage Deep-Dive): not triggered — plan is a config-drift bug, not a connectivity symptom
- Phase 4.6 (User-Brand Impact halt): passed — section present with valid `single-user incident` threshold
