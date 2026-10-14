---
title: "A 'no raw id reaches Sentry' claim tested at the call arguments missed three sinks on the same event"
date: 2026-09-25
category: security-issues
module: apps/web-platform/server (spawn-dead-letter, sentry-scrub, inngest middleware)
tags: [pii, pseudonymization, sentry, inngest, review, mutation-testing]
issues: ["#8719", "#8803"]
pr: "#8794"
---

# Learning: a per-event property checked at one key

## Problem

PR #8794 moved leader-loop dead-letters of `agent.spawn.requested` onto the Sentry message path, so they keep their `feature`, `op` and `reason` tags. It also pseudonymized the founder id: `founderId` is passed as `userId`, which `reportSilentFallback` hashes to `userIdHash`. A unit test asserted that the "raw id [is] nowhere in the event".

The test's haystack was the arguments of the one `captureMessage` call, built from a fixture error that did not contain the id. The review panel found the id still reached Sentry by three other routes on the same event:

1. **Middleware scope extra.** `server/inngest/middleware/sentry-correlation.ts` sets `scope.setExtra("inngest.event_data", ctx.event.data)` on every event of a run. That data carries `founderId`, and the scrubber only renamed `userId`/`user_id`.
2. **Error message text.** The resolve-installation step threw `` `no github_installation_id for founder ${founderId}` ``. `toMessagePathError` copies `message` and `stack` verbatim into `extra.err` and the pino line.
3. **The same shape for a different value.** `safeToolName` sanitized `extra.tool`, but the same call site built `new Error(\`tool ${tu.name} not in allowlist\`)` from the raw, model-chosen name. So `extra.err.message` carried the unsanitized copy (U+2028 and unbounded length included).

## Solution

- Remove the id from the error text; `actionSendId` already identifies the row.
- Hash `founderId` as `founderIdHash` in `server/sentry-scrub.ts`. It runs on every Sentry event, so it covers the middleware's scope extra fleet-wide.
- Sanitize the tool name once (`sanitizeToolNameForLog`, the existing helper) and use it in both the error text and `extra.tool`.
- Search every sink in the test, not one key: `JSON.stringify([captureMessage.mock.calls, addBreadcrumb.mock.calls])`. Add a handler-level case with a hostile tool name, and a case asserting the installation-error text has no founder id.

Each fix was mutation-checked: reverting it reddens a named test.

## Key Insight

A property worded as "X never appears in the event" is about the WHOLE event. An event is assembled from several contributors:
- the call's own arguments;
- scope extras set by middleware;
- breadcrumbs;
- free-text fields such as `err.message`, which embed other values;
- anything a `beforeSend` does or does not scrub.

A test that inspects the call arguments checks one contributor and reads as if it checked all of them. So enumerate the contributors first, then decide where the guarantee is enforced. A property enforced at the boundary every event passes through (the `beforeSend` scrubber) covers contributors nobody listed. Sanitizing one field at the call site covers only that field.

The two shapes seen here (a sibling free-text field carrying the unsanitized copy, and middleware-attached context) are the ones to check first.

## Session Errors

1. **The planning subagent's `grep` blocked on stdin** because it was given an unset variable. Recovery: the task was stopped and the edit confirmed applied. **Prevention:** guard every `grep "$VAR"` with `: "${VAR:?}"`, or pass the path explicitly.
2. **Two scripted plan edits failed their anchor check.** Recovery: re-run with the corrected anchor. **Prevention:** the existing `assert old in s` guard did its job. Read the anchor from the file (`sed -n`) before writing the edit.
3. **A forced-throw test used `mockImplementation`,** which `vi.clearAllMocks()` does not reset, so it would have leaked into later tests. Recovery: added `mockReset()` to `beforeEach`. **Prevention:** a test that installs an implementation on a shared spy must reset it in `beforeEach`, not rely on `clearAllMocks`.
4. **A stray `git stash list` inside a compound command** got the whole command refused by the stash hook. Recovery: re-ran without it. **Prevention:** never put git-stash verbs in a probe command, even read-only ones.
5. **A `ps | awk '/pattern/'` probe self-matched** and was refused by the pkill-self-match hook. Recovery: `pgrep -a node | grep … | grep -v grep`. **Prevention:** use the hook's suggested forms.
6. **A review seat overwrote my shared mutation helper.** The test-design seat wrote `mut.py` into the same session scratchpad, so my first battery never mutated anything (every row printed NOT-LANDED). Recovery: a uniquely named helper (`lead-mut-8794.py`). **Prevention:** a lead's harness files in the shared scratchpad get a lead-unique name, and seats are briefed to use seat-unique names.
7. **Two mutation rows were malformed.** R9 opened `/*` without closing it and "survived" on invalid HCL. R13 broke TypeScript syntax and could have scored a crash as a kill. Recovery: re-ran both as valid, well-formed mutations. **Prevention:** a mutation must leave a well-formed program. Check that the killing failure names the assertion under test, not a parse error.
8. **The trigger-set extractor matched the nested `interval =` key** inside `event_frequency_count`. Recovery: anchored on line-leading `{`. **Prevention:** anchor HCL list extractors on the entry's line position, not on `{ key =`.
9. **The filing hook refused the scope-out issue** because it named no user-visible consequence. Recovery: added `User-Impact`/`Fix-Size` lines. **Prevention:** include them in the body template for any user-facing filing.
10. **The nav-states gate was INFRA-BLOCKED.** The Playwright install hung on another session's download lock, and `chromium_headless_shell-1208` was missing. Recovery: recorded INFRA-BLOCKED and deferred to CI's `e2e` job. **Prevention:** the QA skill's documented INFRA-BLOCKED path applies. Don't wait past ~5 minutes on the install.
11. **The deploy-arm monitor's filter matched its own "waiting" lines**, so every poll became an event. Recovery: re-armed filtering those out. **Prevention:** filter a poller's progress lines out and emit only terminal lines.
12. **#8758's `web-platform-build` failed on a transient Google Fonts "Module not found".** The prior run on the same branch and `main` were green. Recovery: re-ran the failed jobs. **Prevention:** compare against the branch's previous run and `main` before treating a build-time vendor fetch failure as a regression.
13. **The PR's "raw id nowhere in the event" claim was tested at the call arguments only** (this learning's subject). Recovery: fixed three sinks and widened the test haystack. **Prevention:** see Key Insight. The plan's Sharp Edges now carries a bullet.
14. **Moving quiet reasons to `warnSilentFallback` broke two leader-loop tests,** because the suite's observability mock lacked that export. Recovery: added a warn spy, and the helpers read both spies. **Prevention:** when a module starts importing another export from a wholesale-mocked module, grep the suites that mock it and extend each factory.
15. **The Art. 30 register TOM (8) still described the old mechanism.** It was found only by grepping the message literal repo-wide, outside the diff's file list. Recovery: rewrote TOM (8). **Prevention:** the existing "sweep bounded by the diff's own file list" rule. Grep a changed identifier or message across `knowledge-base/legal/` too.

## Tags
category: security-issues
module: apps/web-platform/server
