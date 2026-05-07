# Session State

## Plan Phase
- Plan file: /home/harry/Documents/Stage/Soleur/soleur/.worktrees/feat-one-shot-kb-create-private-repo-403/knowledge-base/project/plans/2026-05-07-fix-kb-create-private-repo-403-plan.md
- Status: complete

### Errors
None. All plan + deepen gates passed: Phase 1.4 / 1.5 not triggered (no SSH/network keywords; no new uncovered stack), Phase 2.5 Domain Review (Engineering + Legal flagged, Product/UX auto-accepted as advisory since no new UI surface), Phase 2.6 User-Brand Impact section non-empty with `single-user incident` threshold and `requires_cpo_signoff: true`, Phase 4.5 deep-dive skipped, Phase 4.6 halt gate passed.

### Decisions
- **Root cause live-reproduced:** `POST /user/repos` with a GitHub App installation token returns `403 Resource not accessible by integration`. Endpoint requires user-to-server (UAT) auth, not installation tokens. Reproduced live against installation_id `130018654` (Elvalio).
- **Recommended fix is Approach B (template-generate via installation token).** Live-verified end-to-end during deepen-plan: created public template under `jikig-ai`, called `/generate` with user installation token + `owner: Elvalio`, got 201 + private repo. Cleanup verified.
- **Critical constraint discovered live:** the template MUST be public — private template returns 404 to user installation tokens. This changes the threat model (template content becomes publicly indexable), so Risks now mandates seed-only `README.md`, branch protection, CODEOWNERS, and `gitleaks` on the template repo.
- **Path corrections:** org slug is `jikig-ai`, not `soleur-ai` (which is the App slug). Plan paths corrected throughout.
- **Test-fixture-vs-real-API drift captured:** existing `user installation: routes to /user/repos` test mocked 201 for a code path that has never worked end-to-end — Sharp Edge documents this anti-pattern.
- Approach A (UAT token) kept as alternative if CPO rejects template-sidebar visibility on user repos.

### Components Invoked
- skill: soleur:plan
- skill: soleur:deepen-plan
- WebFetch (GitHub REST docs for `/user/repos`, `/generate`, `PATCH /repos/{owner}/{repo}`)
- Live GitHub REST API (App JWT mint, installation token exchange, repo create/PATCH/generate/delete — both org and user installations)
- Doppler CLI (retrieve `GITHUB_APP_PRIVATE_KEY` from `prd`)
- gh CLI (issue lookup + open code-review issue overlap query)
- Institutional learning cross-reference (4 prior learning files cited in plan)
