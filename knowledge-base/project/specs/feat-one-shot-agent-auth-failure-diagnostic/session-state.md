# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-25-feat-agent-auth-failure-diagnostic-plan.md
- Status: complete (second attempt; the first died on a weekly API rate limit before saving anything, worktree dir was reaped, branch and draft PR #10976 survived)
- Plan artifact: complete (selector=branch)
- cto_spawns: recorded in decision-challenges.md (F1-F15, `Ruled by CTO agent, 2026-10-25`)

### Errors
- First planning subagent: API rate limit (HTTP 429, weekly limit, resets 2026-10-28 09:00 Europe/Paris); nothing committed. Recovery: re-attached a worktree to the existing branch, merged origin/main (clean), relaunched with commit-and-push after each step.
- Worktree has no node_modules, so no vitest or tsc ran during planning; the work phase installs first.

### Decisions
- One shared leaf module `server/agent-auth-failure.ts`; legacy runner via `authProbe.bindOptions(...)` plus `observe(message)`; cc runner via an iterator tap in `realSdkQueryFactory`.
- Matcher: structured arm `assistant.error === "authentication_failed"`, plus anchored text patterns gated on the CLI-set synthetic model or `is_api_error_message`.
- Event: `reportSilentFallback(null, {feature:"agent-auth", op:"cli-auth-failure"})` with ten closed-enum keys; per-user debounce, process-wide cap, isolation scope, fire-and-forget with `.catch(noop)`.
- Alert required by convention: `sentry_alert.agent_auth_failure`, `frequency_minutes = 40`, alert-reference.json entry, README counts to 48; declared temporary.
- Brand-survival threshold: single-user incident (requires_cpo_signoff, user-impact-reviewer at review).
- Open for work: file follow-up issues A and B before merge; run the named pre-push gates (tsc, guard-vacuity-floor, grep-q-pipe-guard, fixture-relative-assert, repo-wide-containment).

### Components Invoked
soleur:plan, soleur:plan-review, soleur:gdpr-gate, soleur:deepen-plan, plus the CTO, CPO, CLO and review agents listed in the plan.

## Review Phase (PR #10976, panel SHA 30ede92827, risk tier: single-user incident, source: plan)

13 report-only seats ran: user-impact, semgrep, pattern, performance, agent-native, security, data-integrity, simplicity,
code-quality, architecture, git-history, structural-enumeration, test-design. Reports: `/var/tmp/oneshot-10976/<seat>.md` (scratch, not committed).
No P1 from any seat except structural-enumeration, which rated the two guards (contract test, sentry-path canary) P1 for being narrower
than the property they name; both were widened (below). Raw headline findings, roughly 75 across seats, collapse to about 40 unique
after clustering by cause (counts are approximate: seats report in different shapes).

### Fixed in this PR (each pinned by a test that a mutation proves; 23 of 23 mutants caught, control green, sandbox removed)
- Tap `.then` read `done`/`value` outside any try: a throwing getter was an unhandled rejection (3 seats). Guarded; test with a throwing getter; unhandled-rejection listener in the tap suite.
- Tap fixture did not read `this` and the SDK description was wrong (it is an AsyncGenerator, not a single-use Stream): fixture now reads `this`, plus a fixture from a real `async function*` (pending `next()` then `return()`); plan, code comment and test header corrected.
- Swallowed faults were not observable: constant, distinct `logger.warn` for matcher, probe, tap and the runners' probe-construction fallback.
- `release()` debited the current window instead of the claim's window; dead oldest-first eviction branch removed; debounce-map bound pinned; released slot pinned.
- Wire tests did not pin `credentialScheme` or `dedupeToken` (4 survivors): OAuth-lease and two-user cases on both runners.
- "ONE warn per probe" test was vacuous (latch set before the throwing clock): result between the failures.
- Forgery gate, length gate and trim pins; `throw` delegation; closed sets tied (match_kind derived from the reply table, runner/auth_mode `satisfies`, `SDK_API_KEY_SOURCES` equal to the SDK's `ApiKeySource` at compile time).
- Guard 1 (contract): walks `server/`, `lib/`, `app/` in `.ts/.tsx/.mts/.js/.jsx/.mjs/.cjs`; counts the quoted feature token (constant, quoted key) as well as the op token; README/`.tf`/checklist agreement rows.
- Guard 2 (canary): fully clears the cloned isolation scope (tags, extra, contexts as well as user and breadcrumbs); the capture-time observation reads user, breadcrumbs, tags, extra and contexts of both scopes; console spies; fault paths; derived-form control on a sink outside the exact-shape check; a precondition instead of a silent ordering assumption.
- Docs: README is the single decode copy with the terms defined, the OAuth/`none` and legacy-source qualifications, responder steps and both literal read commands; the `.tf` points to it; removal checklist corrected and completed (translator comment, wrapper note, header paragraph, apply order). F1 comment in `claude-error-signatures.ts` corrected against the binary (the string is present, in remote-session throw paths).
- Follow-ups: #11085 got an absolute fallback date (2026-11-30), an owner and the full checklist; #11086 got an owner, `type/bug`, the Phase 4 milestone and the Cloud-gateway wording lead (history P2-3, a hypothesis).

### Rejected after checking the tree
- history P3-3 "1441 is free": `frequency_minutes = 1441` is taken (cron-monitor-alerts.tf) on origin/main and on this branch.
- Simplicity S1 (delete the probe-construction guard): kept, now with a visible warn (see the decision-challenges addendum).

### Declined (no behaviour change; the diagnostic is scheduled for removal in at most 30 days, #11085)
- Simplicity S2/S5/S6/S7 and the roughly 300 mergeable test lines; pattern P3s on replicated literals and duplicated fixtures; contract-test helper hoist. Churn on mutation-proven code that is deleted soon outweighs the benefit; not filed as issues (a deferral needs the CONCUR gate and these are not capabilities).
- Security P2-1 (about ten revoked-key accounts can fill the process-wide cap of 10 per 5 minutes and crowd out the tuple distribution; the email still fires): accepted, documented in the README (responder step 3); a per-scheme cap is a design change for #11086 if the first tuple is ambiguous.
- Data-integrity: claim expiry uses wall-clock; `unbound` conflates states the README names. `select("*")` in the persistence repository is pre-existing.
- `pdf-chapter-router.ts` and the Inngest/cron CLI spawns are unobserved (plan non-goals); named in the PR body and the README.

