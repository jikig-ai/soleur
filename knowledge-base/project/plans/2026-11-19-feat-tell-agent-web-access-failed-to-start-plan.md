---
title: "feat(web-egress): tell the agent when its session's web access failed to start"
type: feat
date: 2026-11-19
slug: feat-tell-agent-web-access-failed-to-start
branch: feat-one-shot-12598-agent-web-access-failed
issue: 12598
closes: 12598
priority: p3
domain: engineering
brand_survival_threshold: none
lane: cross-domain
---

# feat(web-egress): tell the agent when its session's web access failed to start

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). (No `spec.md` exists for this branch; the one-shot
path went straight to plan.)

## Enhancement Summary

**Deepened on:** 2026-11-19
**Sections enhanced:** 5 (Research Insights, Observability, Test Scenarios, Acceptance Criteria, Sharp Edges)
**Agents used:** `soleur:engineering:review:agent-native-reviewer`, `soleur:engineering:review:observability-coverage-reviewer`,
`soleur:engineering:review:test-design-reviewer`. The fan-out was right-sized to the two-file change, per the brief.
The skill's "run every agent" breadth was not used, and no external research was needed (no new library or API).
The hard gates 4.6 to 4.13 were run directly: all pass or skip. 4.9 (UI), 4.10 (store), 4.11 (guard) and 4.13 (task)
do not trigger.

### Key Improvements

1. Observability now cites its layers (layer 2 Sentry mirror, layer 6 CI log) and names where the failure cause is
   discriminated (the exception message, distinct per stage in `server/egress-forwarder.ts`). No new field, per T4.
2. Test design: a new mutation (`!readRegistration?.registered`) gives row 5 a mutant that only it kills, and row 5
   now asserts "exactly once". The TDD order is corrected: rows 2 to 4 are absence checks proven by mutations, and
   every mutation is run, not only the first three.
3. Recorded why the GitHub-read-tools silence in the failure state is deliberate, so a later reviewer does not move the
   line into `githubReadPromptSuffix`.

### New Considerations Discovered

- Sentry reaches a person for this op only through its default new-issue notification; there is no dedicated alert rule.
- Verified live: the forwarder has exactly one spawn call site (`server/cc-dispatcher.ts`), and every cited issue or
  PR state matches the plan.

## Overview

When a workspace has Agent web access turned on but the per-session egress forwarder fails to start, the Command Center
dispatcher degrades that session to zero web egress and reports the failure to Sentry. The agent itself is told nothing:
the "Web access enabled" prompt text is simply left out. This plan adds one system-prompt context line on that failure
path so the agent knows web access failed for this session, stops retrying fetches, and tells the owner accurately.

Detail level: MORE (trimmed). Two files: one production file, one test file. Roughly 20 to 40 changed lines.

## Problem Statement / Motivation

`realSdkQueryFactory` in `apps/web-platform/server/cc-dispatcher.ts` (block commented
`feat-open-web-egress (#9534) — spawn the per-session loopback forwarder`) does this:

```ts
if (webEgressEntitled && mode.runRepoLifecycle) {
  try { const fwd = await spawnEgressForwarder(...); webEgress = { ... }; log.info(...) }
  catch (err) { reportSilentFallback(err, { op: "web-egress-forwarder-spawn", ... }) }
}
```

On the catch path, `webEgress` stays `undefined`: `WebFetch` stays disallowed, `WEB_EGRESS_PROMPT_ADDENDUM` is omitted,
the sandbox credential deny census is not applied, and the GitHub read tools and `github_push_branch` are still
registered (those are server-side). The owner-facing settings copy (`lib/web-egress-disclosure.ts`) already says such a
session "runs as if this were off". The agent gets no signal at all. It sees a workspace whose owner turned web access
on, a user asking it to fetch something, and no `WebFetch` tool. So it retries through shell commands, or tells the owner
something wrong about what it can do. That is the User-Impact line on #12598.

## Proposed Solution

Ruled by CTO agent, 2026-11-19 (rows T1 to T4 in `decision-challenges.md`). Wording approved by the CLO agent, with the
one CTO clause correction folded in (rows L1 to L3).

1. Add a module-level, non-exported constant next to `WEB_EGRESS_PROMPT_ADDENDUM` in `server/cc-dispatcher.ts`:

   ```ts
   // #12598 — appended ONLY when the workspace grant is on and the forwarder spawn failed (the catch below). The
   // session then runs as if Agent web access were off; without this line the agent sees the grant but no WebFetch,
   // and retries or mis-states what it can do. No GitHub claim: GitHub access differs between the repo-token and
   // no-repo cases, and GH_NO_NETWORK_PROMPT_ADDENDUM already covers the latter.
   const WEB_EGRESS_START_FAILED_PROMPT_LINE =
     "## Web access unavailable in this session\n" +
     "Your workspace owner enabled Agent web access, but it failed to start for this session, so this " +
     "session runs as if it were off: `WebFetch` is unavailable and you have no general web access. Do not " +
     "retry web fetches, and do not try to reach other websites from shell commands (for example with curl). " +
     "If the user asks for something that needs the web, tell them web access failed to start for this " +
     "session and that starting a new conversation may restore it, or ask them to paste what you need.";
   ```

2. Declare `let webEgressStartFailed = false;` beside `let webEgress`, and set it to `true` inside the existing
   `catch (err)` only, after `reportSilentFallback`. Nowhere else.

3. Append the line AFTER `githubReadPromptSuffix` in the `systemPrompt:` expression:

   ```ts
   systemPrompt:
     effectiveSystemPrompt +
     (webEgress ? `\n\n${WEB_EGRESS_PROMPT_ADDENDUM}` : "") +
     githubReadPromptSuffix +
     (webEgressStartFailed ? `\n\n${WEB_EGRESS_START_FAILED_PROMPT_LINE}` : ""),
   ```

   The two existing lines stay as they are. `test/cc-github-read-prompt.test.ts` pins
   ``/WEB_EGRESS_PROMPT_ADDENDUM\}` : ""\) \+\s+githubReadPromptSuffix/``, so nothing may go between those terms.
   Also update the two existing comments that list what the degraded state does, so they stay true: the one above
   `systemPrompt:` ("a spawn-degraded session keeps WebFetch disallowed and gets no addendum claiming egress") and the
   block comment above the spawn ("the session degrades to zero-egress (`webEgress` stays undefined → no proxy env,
   WebFetch stays disallowed, ...)"). Each gains "plus the failed-to-start prompt line".

4. Tests in `test/cc-dispatcher-real-factory.test.ts` (see Test Scenarios).

### Why not the alternatives

- **Inside `githubReadPromptSuffix`:** `readRegistration` is set on every entitled Command Center dispatch (no-repo
  included), but the suffix text is only built under `webEgress !== undefined && webEgressEntitled`, so it is empty on
  the failure path. Re-gating it would mix two concerns: the line's trigger (the spawn catch) has nothing to do with
  GitHub reads. A separate append keeps the #12469 block single-purpose and independent of `readRegistration`'s
  lifetime (CTO T1, rationale amended as T1-r after plan review).
- **Exported function or new module:** not needed. `WEB_EGRESS_PROMPT_ADDENDUM` is already a non-exported const that
  tests read from source text (`test/web-egress-prompt-addendum.test.ts`). The behaviour test reads the built
  `systemPrompt` through the real factory.
- **A new Sentry event:** not needed. `reportSilentFallback` with `op: "web-egress-forwarder-spawn"` already fires on
  exactly the path that sets the flag (CTO T4).

## Files to Edit

- `apps/web-platform/server/cc-dispatcher.ts`: the new const, the flag, the `systemPrompt` append, the comment update.
- `apps/web-platform/test/cc-dispatcher-real-factory.test.ts`: the new and extended cases.

## Files to Create

None.

## Research Insights

**Premise validation.** #12598 is OPEN with no closing PR (`gh issue view 12598`). #12572 (owner-facing indicator) is
OPEN and out of scope; this plan must not close it. PR #12567 is MERGED (2026-11-10) and is where the owner-facing
"runs as if this were off" copy landed. `collision-precheck.sh 12598` returned one hit, PR #12957. That PR is this
branch's own auto-created draft (head `feat-one-shot-12598-agent-web-access-failed`, zero files), so it is not a
duplicate. Every cited symbol exists on this branch's base: `spawnEgressForwarder`, `WEB_EGRESS_PROMPT_ADDENDUM`,
`githubReadPromptSuffix`, `op: "web-egress-forwarder-spawn"`.

**Property list (Phase 0.6b).**

- P1: in a session whose web access failed to start, the agent's instructions say so.
- P2: the agent does not retry web fetches or try to reach websites from shell commands in that state.
- P3: what the agent tells the owner is true in every state where the line appears (repo connected or not; read tools
  and push tool registered or not).
- P4: sessions whose web access started, and sessions without the grant, get exactly the prompt they get today.

**Cut list.** No mechanism cut. The issue names one mechanism ("one context line on the failure path"), and it buys
P1 and P2. Nothing on `origin/main` already buys P1: the catch only reports to Sentry (`server/cc-dispatcher.ts`,
the grep authority). The owner-facing indicator (#12572) is a different property (owner visibility) and stays out of scope.

**Value claim.** Not a cost or performance plan; Phase 0.6c does not apply.

**Code facts the wording rests on (each checked in source):**

- No forwarder re-spawn exists mid-conversation. The warm-path block ("live-revocation on the warm path") only tears
  down; the next cold dispatch, for example a new conversation, tries the spawn again. So "a new conversation may restore
  it" is accurate and hedged.
- The sandbox for a no-web-egress session with a minted repo token still allows `github.com`, `api.github.com`,
  `registry.npmjs.org` and the Actions log hosts (`ENTITLED_EGRESS_DOMAINS`, `server/agent-runner-sandbox-config.ts`).
  That is why the line says "other websites", not "the internet" (CTO T2).
- With no repo token, `GH_NO_NETWORK_PROMPT_ADDENDUM` is already appended (`if (!ghToken)`). The new line makes no
  GitHub claim, so the two never contradict.
- The legacy runner (`server/agent-runner.ts`) never passes `webEgress` and never spawns a forwarder, so the line cannot
  fire there. The support persona has `mode.runRepoLifecycle` false and never enters the spawn block.
- `test/egress-audit-agent-surface-absence.test.ts` scans `cc-dispatcher.ts` with `/egress[-_]?audit/i`. The new
  const and comment do not match.

**States considered and left alone (agent-native review, deepen pass).** In the failure state the GitHub read tools are
still registered while the read addendum is absent (it is gated on a live forwarder). That is deliberate (#12469): the
credential deny census is not applied, so `gh` works and must not be called broken, and the tools describe themselves.
Do not "fix" it by moving the new line into `githubReadPromptSuffix` (ruled against in T1-r). The line is decided per
cold dispatch (one Query), so it cannot go stale inside a Query; a conversation resumed into a new cold dispatch whose
earlier history shows successful `WebFetch` calls is exactly the case the line corrects.

**Learnings applied.**

- `knowledge-base/project/learnings/2026-05-05-baseline-prompt-must-declare-capabilities-or-model-fabricates-missing-tools.md`:
  tell the model about the capability it does NOT have (the pattern `GH_NO_NETWORK_PROMPT_ADDENDUM` already follows).
- `knowledge-base/project/learnings/2026-11-10-a-copy-sentence-that-promises-enforcement-must-be-checked-on-every-runner-and-flag-state.md`:
  check each clause against every runner and state where it can appear. Done above; it is why the "reach websites from
  shell commands" clause was narrowed.

**Conventions.** Prompt constants are module-level string concatenations with a `#issue` comment
(`GH_NO_NETWORK_PROMPT_ADDENDUM`, `WEB_EGRESS_PROMPT_ADDENDUM`). Factory behaviour is tested through
`realSdkQueryFactory` with `mockQuery.mock.calls.at(-1)![0].options.systemPrompt`.

**External research:** skipped. Strong local patterns, no new library or API.

**Functional overlap / community discovery:** skipped. No new skill, agent or stack; this is a one-line product prompt change.

**Advisor consult (Step 4.5):** skipped. The plan is mechanical and the one design choice was ruled by the CTO agent.

## Open Code-Review Overlap

2 open scope-outs touch `apps/web-platform/server/cc-dispatcher.ts`:

- #3243 (decompose `cc-dispatcher.ts` into modules): **Acknowledge.** A multi-PR refactor; this change adds one const
  and one flag inside the existing factory and does not make it worse.
- #3242 (`tool_use` WS event lacks a raw name field): **Acknowledge.** A different concern (the WS event shape), not the
  system prompt.

`apps/web-platform/test/cc-dispatcher-real-factory.test.ts`: none.

## Technical Considerations

- **Prompt-cache effect:** the line is static and appears only on the failure path, so it adds one extra prompt variant
  for degraded sessions. These are rare (a Sentry-reported fault).
- **Security:** no new capability, credential or data flow. The text interpolates nothing.
- **NFRs:** none affected beyond agent-facing honesty, which is the point of the change.

## User-Brand Impact

- **If this lands broken, the user experiences:** an agent in a session whose web access did start telling the owner it
  has no web access (if the flag is set outside the catch), or, as today, an agent that retries fetches and mis-states
  its access after a failed start (if the line never appears).
- **If this leaks, the user's data is exposed via:** nothing. The line is a static string with no interpolation, and no
  capability, credential or data path changes.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the change only adds a sentence to the agent prompt on a path that already
  runs with less access, so no failure can widen access or expose data.
- `threshold: none, reason: the diff touches apps/web-platform/server/ only to append a static, non-interpolated sentence to the agent system prompt on the already-degraded forwarder-failure path; it changes no capability, credential, network or data flow.`

## Observability

```yaml
liveness_signal:
  what: existing Sentry silent-fallback event, op "web-egress-forwarder-spawn" (feature "cc-dispatcher"), fired on exactly the path that now appends the line; plus the existing cc-github-read outcome event carrying forwarderLive=false
  cadence: per cold dispatch of an entitled Command Center session whose forwarder spawn fails
  alert_target: Sentry issue (web-platform project)
  configured_in: apps/web-platform/server/cc-dispatcher.ts (reportSilentFallback in the forwarder spawn catch)

error_reporting:
  destination: Sentry web-platform project via reportSilentFallback (server/observability.ts)
  fail_loud: Sentry event message "web-egress forwarder spawn failed; session proceeds zero-egress"

failure_modes:
  - mode: forwarder spawn fails for an entitled session (the state this line describes)
    detection: 'layer 2 (pino to Sentry mirror; reportSilentFallback(err, ...) captureException), emitted in-surface by the dispatch process that builds the prompt; whether the line was appended follows from it (the flag is set only in that catch). The cause is in the exception message, which server/egress-forwarder.ts makes distinct per stage: "egress gateway unreachable at ..." (gateway-side start), an fs error with the token path redacted (token write), "egress forwarder did not report a bound port" or "exited before bind (code N)" (bind)'
    alert_route: Sentry issue (default new-issue notification; no dedicated alert rule)
  - mode: line appended to a session whose forwarder started (flag set outside the catch)
    detection: unit test in test/cc-dispatcher-real-factory.test.ts (spawn-OK case asserts the line is absent) on every CI run
    alert_route: layer 6 (workflow run log; the CI test job fails with the vitest error on the PR)

logs:
  where: Sentry (web-platform) and the app's pino logs shipped to Better Stack
  retention: Sentry plan retention; Better Stack plan retention

discoverability_test:
  command: grep -o web-egress-forwarder-spawn apps/web-platform/server/cc-dispatcher.ts
  expected_output: web-egress-forwarder-spawn
```

The probe was run on this branch before finalizing and printed `web-egress-forwarder-spawn`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "tell the agent when its session's web access failed to start" [issue #12598 title] | Proposed Solution steps 1 to 3; `server/cc-dispatcher.ts` | mapped |
| 2 | "one context line on the failure path" [issue #12598] | Proposed Solution steps 1 to 3 | mapped |
| 3 | "one test" [issue #12598] | Proposed Solution step 4; `test/cc-dispatcher-real-factory.test.ts` | mapped |
| 4 | "Sibling issue #12572 (owner-facing UI for the same failure) is NOT in scope — do not close it." [brief] | `closes: 12598` only; AC9 | mapped |
| 5 | "No production writes." [brief] | no deploy, flag or data step in the plan; AC9 | mapped |
| 6 | "Do not touch or flip the approval-queue feature flag." [brief] | no flag step; the tests only use the existing `mockApprovalFlag` mock; AC9 | mapped |
| 7 | "No edits under docs/ and no legal documents." [brief] | Files to Edit lists two non-docs files; CLO L2 rules that no legal-record change is needed; AC9 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `server/cc-dispatcher.ts` (const, flag, append) | "one context line on the failure path" | asked |
| `test/cc-dispatcher-real-factory.test.ts` | "one test" | asked |
| Wording assertions on the built prompt (Test Scenario 1, AC7) | — | inferred — justification: CTO T3-r1. They are the only assertions that red a later edit turning the line into a capability claim ("`WebFetch` is still available"). They extend an existing case in the same test file, so it is still "one test". |
| Comment update above `systemPrompt:` | — | inferred — justification: the existing comment says a degraded session "gets no addendum"; leaving it would make the code's own record false. |

### Split Assessment

- Subsystems touched: 1 — `apps/web-platform`
- Planned files: 2 | Estimated changed lines: 35
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

<!-- founder-stated check: see plan-founder-check.md -->

- [x] AC1: `grep -c '^const WEB_EGRESS_START_FAILED_PROMPT_LINE =' apps/web-platform/server/cc-dispatcher.ts` prints `1`,
      and the use sits directly after the suffix:
      `grep -A1 -F 'githubReadPromptSuffix +' apps/web-platform/server/cc-dispatcher.ts | grep -c 'webEgressStartFailed ?'`
      prints `1`.
- [x] AC2: `grep -c "webEgressStartFailed = true" apps/web-platform/server/cc-dispatcher.ts` prints `1`, and
      `awk '/op: "web-egress-forwarder-spawn"/{f=1} f && /const untrustedContentFlags/{exit} f && /webEgressStartFailed = true/{print "in-catch"; exit}' apps/web-platform/server/cc-dispatcher.ts`
      prints `in-catch` (the only assignment sits between the spawn-failure Sentry call and the next statement block).
      This is a review aid; the behaviour check that the flag is set only on failure is Test Scenario 2.
- [x] AC3: the existing pin `WEB_EGRESS_PROMPT_ADDENDUM\}` : ""\) \+\s+githubReadPromptSuffix` still matches (the
      `cc-github-read-prompt.test.ts` "pinned neighbours" case is green and unedited).
- [x] AC4: in the real-factory suite, an entitled Command Center session whose spawn rejects has a `systemPrompt` that
      contains `## Web access unavailable in this session` exactly once and does not contain
      `## Web access enabled for this session`. Checked both with a repo connected and with none.
- [x] AC5: in the real-factory suite, the line is absent for: an entitled session whose spawn succeeds; an unentitled
      session; an entitled support-persona session.
- [x] AC6: the existing #12469-suite case `entitled + DEGRADED forwarder` keeps every current assertion (tool list,
      read `ADDENDUM_HEAD` absent, no "GitHub tools are unavailable", `forwarderLive` `false`) and also asserts that the
      line appears exactly once (`split(LINE_HEAD)` has length 2). The push-suite degraded case is unchanged.
- [x] AC7: the spawn-failure case's built `systemPrompt` contains `failed to start` and `` `WebFetch` is unavailable ``
      and does not match `` /WebFetch`? (is|are) (still )?available/ ``.
- [x] AC8: from `apps/web-platform`,
      `npx vitest run $(grep -rln --include='*.test.ts' spawnEgressForwarder test/) test/cc-github-read-prompt.test.ts test/web-egress-prompt-addendum.test.ts test/egress-audit-agent-surface-absence.test.ts`
      passes, and `npx tsc --noEmit` passes.
- [ ] AC9: `git diff --name-only origin/main...HEAD` lists only the two files in Files to Edit plus this plan, its
      `tasks.md` and `decision-challenges.md`. Nothing under `docs/` or `knowledge-base/legal/`, no flag or Doppler change.
      The PR body says `Closes #12598` and does not name #12572 in a closing keyword.

## Domain Review

**Domains relevant:** Engineering, Legal

### Engineering

**Status:** reviewed
**Assessment:** CTO agent ruled the mechanism (module const, flag set only in the catch, appended after
`githubReadPromptSuffix`), corrected one clause ("other websites ... for example with curl", because the sandbox still
allows GitHub and npm with a repo token, and no GitHub claim may be added), set the test rows, and ruled that no new
observability is needed. Plan review then sent four dissents back to the CTO, all amended with the design unchanged:
T1-r (corrected rationale), T3-r1 (wording assertions on the built prompt replace the source-text pin), T3-r2 (extend
existing cases, one degraded-suite assertion) and AC8-r (run every suite that mocks the spawn).

### Legal

**Status:** reviewed
**Assessment:** CLO agent approved the wording: every clause matches the code and the owner-facing `PUSH_DISCLOSURE`
copy already ruled on in #12197. No Article 30, DPIA or compliance-posture change: no new processing, and the degraded
state is already recorded in `knowledge-base/legal/audits/2026-10-05-dpia-screening-agent-web-egress.md`. In scope
without #12572's wording review, because the text goes to the agent, not to an owner-facing surface. The CLO's optional
extra sentence ("Your usual access to the connected repository is unchanged.") is not taken, per CTO T2, because it is
false for a session with no repo connected.

Product: not relevant. No file in Files to Edit matches the UI-surface terms. The owner-facing indicator is #12572.
Marketing, Sales, Finance, Operations, Support: no implications.

## Test Scenarios

All `unit` layer, in `apps/web-platform/test/cc-dispatcher-real-factory.test.ts`. Rows 1 to 4 EXTEND the four
existing `it` blocks in the `web egress entitlement (#9534)` describe (`unentitled (default)`, `entitled + spawn OK`,
`entitled + spawn failure`, `entitled but support persona`); do not add near-duplicate tests. The top-level
`beforeEach` already resolves `mockGetCurrentRepoUrl` and `mockResolveInstallationId` to `null`, so the existing
spawn-failure case is already the no-repo case. Use a local `LINE_HEAD = "## Web access unavailable in this session"`.

1. Given an entitled Command Center session with no repo connected, when the forwarder spawn rejects, then
   `systemPrompt.split(LINE_HEAD)` has length 2, `## Web access enabled for this session` is absent, the prompt
   contains `failed to start` and `` `WebFetch` is unavailable ``, the prompt does not match
   `` /WebFetch`? (is|are) (still )?available/ ``, and the existing `op: "web-egress-forwarder-spawn"` mirror still
   fires once. (Extends the existing `entitled + spawn failure` case, which keeps its current assertions.)
2. Given an entitled session, when the spawn resolves, then `LINE_HEAD` is absent.
3. Given an unentitled session, then the spawn is not called and `LINE_HEAD` is absent.
4. Given an entitled support-persona session, then the spawn is not called and `LINE_HEAD` is absent.
5. Given an entitled session with a public repo connected, when the spawn rejects, then the line is present, and the
   tool registration is unchanged from today. Done by adding `expect(prompt().split(LINE_HEAD)).toHaveLength(2)` to the existing
   #12469-suite case `entitled + DEGRADED forwarder` without removing any of its assertions (CTO T3-r2: the push-suite
   copy is not added).

There is no source-text extraction test (CTO T3-r1): the wording assertions live on the real built prompt in row 1,
and `test/egress-audit-agent-surface-absence.test.ts` already scans `cc-dispatcher.ts` with `/egress[-_]?audit/i`.

**Mutations each row must catch (CTO T3, amended).** Check at least the first three by hand during work:

| Mutation | Red row(s) |
|---|---|
| Put the line inside the `webEgress !== undefined` guard of the #12469 block | 1, 5 |
| Set `webEgressStartFailed = true` outside the catch (before `try`) | 2 |
| Gate the append on `webEgressEntitled` alone | 2 (spawn OK), 4 (support persona with the grant) |
| Gate the append on `!webEgress` alone | 3 (unentitled), 4 |
| Reword the const to claim access ("`WebFetch` is still available") | 1 |
| Gate the append on `!readRegistration?.registered` | 5 only (row 1 has no registered tools, so it stays green) |

Order of work (`cq-write-failing-tests-before`): rows 1 and 5 are presence checks and must fail before the change. Rows
2 to 4 are absence checks that pass before the change, so they are proven only by the mutations: after the change is
GREEN and committed, apply EVERY mutation in the table, one at a time, run the suite, confirm the named rows red, and
restore with `git restore apps/web-platform/server/cc-dispatcher.ts`. Running them in a `scripts/soleur-sandbox.sh` copy
instead of the live tree is also fine. Note: `vi.clearAllMocks` keeps mock implementations in vitest 4 and
`mockSpawnEgressForwarder` is never reset, so rows 1, 2 and 4 each set the spawn mock themselves (the existing cases
already do); row 3 relies on the spawn not being called.

## Sharp Edges

- Do not insert anything between `(webEgress ? ... : "")` and `githubReadPromptSuffix`: the regex in
  `test/cc-github-read-prompt.test.ts` pins that exact adjacency.
- The `systemPrompt:` edit rewrites one existing line (`githubReadPromptSuffix,` becomes `githubReadPromptSuffix +`),
  so the diff has a `-` line. No AC claims "additions only".
- 15 test files mock `spawnEgressForwarder` (`grep -rln --include='*.test.ts' spawnEgressForwarder test/`). A suite
  that turns entitlement on with a bare `vi.fn()` spawn mock now gets the line, because `fwd.token` throws into the
  catch. Plan review found none that byte-pins the prompt today; AC8 runs every one of them, so do not trust a
  hand-written list. Fix any newly pinned prompt there rather than loosening the new test.
- The line is decided once per cold dispatch (Query construction). There is no mid-session re-spawn, so the line
  cannot go stale within a Query, and a warm turn never re-evaluates it.
- Keep "egress audit" spellings out of the new const and its comment (`egress-audit-agent-surface-absence.test.ts`).
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the
  threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `soleur:work`.

## References

- Issue #12598; sibling (out of scope) #12572; origin PR #12567 (#12197).
- `apps/web-platform/server/cc-dispatcher.ts`: `WEB_EGRESS_PROMPT_ADDENDUM`, `GH_NO_NETWORK_PROMPT_ADDENDUM`, the
  forwarder spawn block, the `#12469` prompt-suffix block, the `systemPrompt:` expression.
- `apps/web-platform/lib/web-egress-disclosure.ts`: the owner-facing "runs as if this were off" sentence.
- `apps/web-platform/test/web-egress-prompt-addendum.test.ts`: the pinned neighbour addendum test (unchanged).
- Decision record: `knowledge-base/project/specs/feat-one-shot-12598-agent-web-access-failed/decision-challenges.md`.

## Plan Review

Panel: `soleur:engineering:review:dhh-rails-reviewer`, `soleur:engineering:review:kieran-rails-reviewer`,
`soleur:engineering:review:code-simplicity-reviewer` (threshold `none`, 3-agent baseline), plus `soleur:engineering:cto`
on the devex lens (the plan edits code). No security or feasibility regression was raised.

- Applied (mechanical): AC1 now pins the append position; AC2 is a runnable command; both degraded-state comments are
  updated; rows 1 to 4 extend the existing cases; the redundant repo-mock setup is removed.
- Ruled by the CTO as dissents from T1 and T3 (rows T1-r, T3-r1, T3-r2, AC8-r): applied as amended.
- Not applied: DHH P3, dropping "and you have no general web access" (taste row W1; the CLO approved the text with that
  hedge). DHH P3, collapsing the gated sections (Observability, Scope Check, Domain Review): these are required by
  plan and deepen-plan gates. DHH P3, cutting the `!webEgress` mutation row: kept, because a
  `webEgress ? ADDENDUM : LINE` ternary is a natural way to write this bug.

## Addendum - 2026-11-19 (review of PR #12957)

Superseded by CTO review rulings T2-r1, T3-r3 and T1-r2 (see the spec's decision-challenges.md): the flag is derived
from the live forwarder handle after the spawn block (not set in the catch), the line gains a clause about the
`github_*` read tools only when they are registered, and the test's content asserts read the line's body. The code
sketch and Assessment above record the plan as written before review.
