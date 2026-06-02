# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-02-fix-kb-chat-fresh-conversation-history-404-plan.md
- Status: complete

### Errors
None. (Task subagent tool unavailable inside the planning delegation, so deepen-plan's research/review passes ran inline via direct codebase inspection.)

### Decisions
- Root cause: WS server uses deferred conversation creation (no DB row at session_started; inserted lazily on first chat message). Client resume-history effect fires unconditional GET /api/conversations/{pendingUUID}/messages for the fresh deferred UUID → guaranteed 404 via .single(). Both server + client log at level=error on the most common new-conversation path.
- Fix is client-side discrimination, not server restructuring: skip history fetch for fresh (session_started) sessions; keep fetching for genuine resumes (session_resumed). Deferred-creation model preserved. Discriminator added as client-local sessionKind state (TR2a), no wire change.
- Defense-in-depth: downgrade row-absent 404 from error → warning via warnSilentFallback on server (FR3) + client (FR4), keeping HTTP status + op string unchanged so alert rules still match and genuine 401/500 still page. Matches in-file precedent (api-messages.ts:155-166).
- Premise correction: no App-Router route.ts for [id]/messages — endpoint is the custom Node server (api-messages.ts); plan flags do-NOT-add-a-duplicate-route. User-facing "An unexpected error occurred." is the dashboard error boundary (FR5 covers deep-link empty-state degradation).
- Threshold = single-user incident; requires_cpo_signoff: true; code-review overlaps #3280/#3374/#3289 acknowledged.

### Components Invoked
- skill: soleur:plan
- skill: soleur:deepen-plan
- Artifacts committed + pushed: plan + tasks.md
