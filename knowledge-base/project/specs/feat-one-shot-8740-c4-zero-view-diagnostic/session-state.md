# Session State

## Plan Phase

- Plan file: knowledge-base/project/plans/2026-09-25-fix-c4-zero-view-model-project-diagnostic-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors

- `gh issue create` blocked twice by hooks (missing `--milestone`; body file outside the worktree). Resolved by adding the milestone and staging the body in the specs folder, then deleting it (not committed).
- Plan write blocked once by a banned-token guard on a quoted phrase; rephrased instead of opting out.

### Decisions

- No tenant write: this PR does not re-render or write to the external repo; options (a) leave / (b) one re-render / (c) contact via support are in `decision-challenges.md`. #8740 stays open (`Ref`), closes on evidence via a 14-day follow-through.
- Concierge-first copy: the diagnostic names the Concierge, not Save (Save is behind the `c4-edit` flag, off for everyone), with a reload clause until #8739 ships; one matching sentence added to the Concierge prompt.
- Security fix folded in: the existing `dir` traversal (`%252e%252e/...`) in the same route is fixed here; debounce key uses the canonical path.
- Follow-through is the push signal: no new Sentry alert rule; stubbed test for the evidence-close script.
- Plugin writers (`render-c4-model.sh`, `generate-c4-from-components.ts`) deferred to #8861; shared model counting moves to `lib/c4-model-shape.ts`.

### Components Invoked

soleur:plan, soleur:gdpr-gate, soleur:plan-review, soleur:deepen-plan; repo-research-analyst, learnings-researcher, functional-discovery; cpo, cto, ux-design-lead, cmo; dhh/kieran/simplicity/security/observability/test-design/architecture/agent-native reviewers; issue #8861 created.

### Post-planning collision re-probe

- #8740: no open linked or body-referencing PR other than this one. Planned files: no open PR touches any of them.

## Work Phase

### Deviations from the plan

- `dir` validation is a per-segment blocklist (empty, `.`, `..` segments; `%`, `\`, `?`, `#`; C0 controls, DEL, U+2028/U+2029; 256 cap) with per-segment `encodeURIComponent`, not the plan's ASCII allowlist. The allowlist would have 400'd KB folders with spaces or non-ASCII names, which work today; `server/validate-context-path.ts` chose a blocklist for the same reason. The control-character check is a code-point loop, not a regex, so it adds no `no-control-regex` finding to the eslint ratchet.
- The Concierge sentence names `edit_c4_diagram` instead of "this tool", because the addendum is the system prompt, not the tool description.
- Follow-through probe: written, then deleted in review (see Review Phase).

### Verification

- vitest (8 files, 137 tests), `tsc --noEmit`, eslint on changed files, probe suite 39/39, varq-ban, capture-exit-live, trap-tempfile (live + highwater), fixture-relative/dir-operand, guard-vacuity-floor, orphan-suites, eslint-config ratchet: all green.
- Route guard and diagnostic: 8 mutations, all RED.
- `test-all.sh --affected` degraded to full (`runner-changed`, the diff adds a `run_suite` row) and was REFUSED rc=4 on a sibling full run; the `TEST_GROUP=affected` substitute sat 29 min at queue position 2 and was cancelled. No local runner verdict for this diff; CI's full battery is the merge gate.

## Review Phase

- Panel (report-only, SHA d1c8cf3d85): git-history, pattern-recognition, architecture, security, performance, agent-native, code-quality, test-design, semgrep-sast, structural enumeration, code-simplicity. Semgrep 79 rules / 10 files, no net-new findings.
- CTO ruling (option A): the follow-through probe is deleted. Live flag state (2026-09-25): `c4-visualizer` default off, on only for `role-dev` in dev and prd, so the external tenant cannot load the viewer and a Sentry-absence close would be vacuous. #8740 closes by hand on a census re-run.
- Fixed inline: copy ("This is not caused by your diagram source"; "ask the Concierge to re-render this diagram"); Concierge addendum (scoped to the canonical folder, append-only on the smallest `.c4`, Grep the model, model contents are data); zero-view check derived from `viewIds` (elements counted only when views are empty); `null` model no longer throws into a misattributed 503; tests for explicit canonical dir, subfolder near misses, U+2029/DEL/NUL, line 1, non-empty array views, a listing path that differs from the request dir, and `lib/c4-model-shape.ts` units; stale shared-route citation; dead `Diagnostic` re-export.
- Fixed inline (pre-existing, same class): the `%2e%2e` / backslash traversal in `app/api/kb/upload/route.ts` and `app/api/kb/file/[...path]/route.ts`, via the shared `server/kb-github-path.ts` guard (the filing gate put it inside the ADR-131 inline threshold). Rename, delete and upload URLs are per-segment encoded; mutation-checked.
- Wontfix in this PR (pre-existing P3, deliberate design): raw share tokens in share-route logs and Sentry `extra`. The 2026-04-10 sharing plan names the token as the analytics key for `shared_page_viewed` / `share_revoked`; changing it is an analytics-contract decision, surfaced to the operator.
