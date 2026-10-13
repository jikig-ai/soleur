# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-04-fix-concierge-github-403-wrong-installation-plan.md
- Status: complete

### Errors
None. One self-corrected gate trip (observability test comment contained literal "ssh"; reworded to "no remote shell"). CWD verified at start.

### Decisions
- Root cause CONFIRMED against installed code: the Concierge mints GH_TOKEN for the WRONG installation. `findInstallationForLogin` (github-app.ts:356-380) returns the user's personal-account installation FIRST, which has no access to org-owned jikig-ai/soleur, so every REST call returns 403 "Resource not accessible by integration". Matches screenshot evidence (403 on ALL calls). Org install 122213433 (has issues:write) is never selected. The "lacks issues:write" message is a misdiagnosis.
- Misdiagnosis is model-generated + reinforced server-side: `handleErrorResponse` (github-api.ts:227-237) hard-codes "approve new permissions" on ANY 403, discarding the real GitHub message.
- Three-part fix: (1) add `findInstallationForRepo` to select repo-correct installation + runtime self-heal in cc-dispatcher; (2) surface real GitHub message/status/installation in server error + Concierge prompt (degrade honestly, no re-consent advice); (3) log installation id + repository_selection + permissions at mint time. AC6 forbids touching the manifest or any permission declaration.
- Hypothesis dispositions: H1 CONFIRMED (different installation, not down-scoped). H2 partial (divergence is installation id, shared generateInstallationToken). H3 consistent (valid token, wrong install → 403 not 401/404).

### Components Invoked
- Skill: soleur:plan
- Skill: soleur:deepen-plan
- Bash, Read, Edit, Write
