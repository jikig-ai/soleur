# Tasks — feat-one-shot-command-center-qa-fixes

Plan: `knowledge-base/project/plans/2026-04-29-fix-command-center-qa-permissions-runaway-rename-plan.md`
Branch: `feat-one-shot-command-center-qa-fixes`

## Phase 1 — Tests RED (no implementation yet)

- 1.1 Write `apps/web-platform/test/permission-callback-safe-bash.test.ts`
  - 1.1.1 Allowlist hit cases (≥15): `pwd`, `ls`, `ls -la`, `cat package.json`, `head -n 5 README.md`, `git status`, `git log --oneline -5`, `git diff HEAD~1`, `git rev-parse HEAD`, `git config --get user.email`, `which bun`, `printenv NODE_ENV`, `whoami`, `date`, `echo "hello"`, `uname -a`, `hostname`, `id`, `wc -l package.json`, `stat README.md`.
  - 1.1.2 Compound-command negative cases (≥10): `pwd; ls`, `ls && rm`, `cat | nc`, `pwd > out`, `git status; sudo`, `echo $(curl)`, `pwd & bg`, `ls < input`, `cat >> out`, `` echo `id` ``.
  - 1.1.3 Block-precedence test: command matching both blocklist and allowlist denies.
  - 1.1.4 Assert no `review_gate` WS event emitted on safe match.
- 1.2 Write `apps/web-platform/test/soleur-go-runner-awaiting-user.test.ts`
  - 1.2.1 TS4: pause clears runaway, resume + result completes cleanly.
  - 1.2.2 TS5: pause then resume re-arms, fires `runner_runaway` only AFTER fresh window expires.
  - 1.2.3 AC17: 5-min safety-net interleave — abort fires `internal_error` once, no double-emit.
  - 1.2.4 `notifyAwaitingUser` on unknown conversation mirrors via `reportSilentFallback`.
- 1.3 Write `apps/web-platform/test/interactive-prompt-card-resolved.test.tsx`
  - 1.3.1 Resolved render for all 6 kinds: `bash_approval`, `ask_user`, `plan_preview`, `diff`, `todo_write`, `notebook_edit`.
  - 1.3.2 Each resolved row asserts: exactly one `<svg>` (checkmark), verb text, NO `<button>`, NO `<pre>`, `data-prompt-kind` + `data-prompt-id` still present.
- 1.4 Run `bun test` — all new tests RED.

## Phase 2 — GREEN

- 2.1 `permission-callback.ts` — add `SAFE_BASH_PATTERNS` allowlist + `isBashCommandSafe()` helper + pre-gate auto-approve branch.
  - 2.1.1 Implement shell-metachar denylist regex.
  - 2.1.2 Implement leading-token allowlist regex with per-tool arg shape.
  - 2.1.3 Wire into Bash branch BEFORE the review-gate; AFTER `BLOCKED_BASH_PATTERNS`; SKIP `bashApprovalCache` lookup on safe match.
  - 2.1.4 `logPermissionDecision(..., "allow", "safe-bash-allowlist")`.
- 2.2 `soleur-go-runner.ts` — add `notifyAwaitingUser`.
  - 2.2.1 Add `awaitingUser: boolean` to `ActiveQuery`.
  - 2.2.2 Modify `armRunaway` to no-op while `awaitingUser === true`.
  - 2.2.3 Modify `notifyAwaitingUser` to (a) `clearRunaway` on true, (b) `armRunaway` on false (with fresh `firstToolUseAt`), (c) `reportSilentFallback` on unknown conversation.
  - 2.2.4 Add `notifyAwaitingUser` to the `SoleurGoRunner` interface.
- 2.3 `cc-dispatcher.ts` — wire `notifyAwaitingUser` from `realSdkQueryFactory`'s `updateConversationStatus` closure.
  - 2.3.1 On `status === "waiting_for_user"`: `runner.notifyAwaitingUser(convId, true)`.
  - 2.3.2 On `status === "active"`: `runner.notifyAwaitingUser(convId, false)`.
  - 2.3.3 On `status === "failed"`: `runner.notifyAwaitingUser(convId, false)` (lets the resumed clock re-arm if the runner is still alive).
- 2.4 `cc-dispatcher.ts` — replace inline `Workflow ended (X)` template with `WORKFLOW_END_USER_MESSAGES` map (AC18).
  - 2.4.1 Map covers all `WorkflowEndStatus` values.
  - 2.4.2 Compile-time exhaustiveness rail (`_exhaustive: never`).
- 2.5 `interactive-prompt-card.tsx` — refactor 6 variants to compact resolved row.
  - 2.5.1 Extract `<ResolvedCardRow promptId={...} kind={...} verb={...} detail={...} />` shared subcomponent.
  - 2.5.2 Replace each variant's `disabled` block with the shared row.
- 2.6 `domain-leaders.ts` — rename `cc_router.title` / `cc_router.name` / `cc_router.description`.
  - 2.6.1 `title`: "Soleur Concierge"
  - 2.6.2 `name`: "Concierge"
  - 2.6.3 `description`: "Greets the user, routes their request to the right Soleur workflow, and reports back."
- 2.7 Grep + update remaining `Command Center Router` substrings:
  - `apps/web-platform/`, `knowledge-base/`, `plugins/soleur/docs/`.
  - 2.7.1 ADR-022-sdk-as-router.md — update title prose; preserve "ADR-022: SDK as Router" heading.
- 2.8 Run `bun test apps/web-platform/test/` — all green.

## Phase 3 — Compound + Review

- 3.1 `skill: soleur:compound` — capture learnings (e.g. "wall-clock timer must pause across user-await; #840 safety net interleaving").
- 3.2 Push branch.
- 3.3 `skill: soleur:review` — multi-agent review.
- 3.4 Resolve review findings inline.

## Phase 4 — QA + Ship

- 4.1 `bun test` repository-wide — green.
- 4.2 `skill: soleur:ship` — preflight, version label, PR ready.
- 4.3 `gh pr merge <N> --squash --auto`.
- 4.4 Post-merge:
  - 4.4.1 AC15 — QA on dev Command Center: `pwd` no prompt; `rm ~/.bashrc` still gates.
  - 4.4.2 AC16 — Screenshot compact resolved card.
  - 4.4.3 Verify Vercel deploy succeeded; verify Sentry has no new error class.

## Out of scope / deferral candidates

- Stage 2.13 control-plane (`Query.interrupt()` / `Query.setPermissionMode()`).
- `cc_router` ID rename (would ripple into 8 test files; too broad for this PR).
- Multi-question `AskUserQuestion` UI improvements.
- New ADR file (the changes are bug-fix follow-ups to ADR-022).
