---
title: A thrown error loses its status at the Inngest step boundary, so return the verdict instead
date: 2026-09-24
category: integration-issues
module: apps/web-platform/server/inngest
tags: [inngest, anthropic, prompt-caching, error-classification, step-boundary, byok]
related: [8717, 8726, 8635, 8629, 8719]
---

# Learning: a thrown error loses its status at the Inngest step boundary

## Problem

Two defects in the BYOK leader loop (`agent-on-spawn-requested.ts`), fixed in PR #8717.

1. **Cache breakpoints over the cap.** The `messages.create` call put `cache_control` on the system block and on every tool. The Messages API allows 4 breakpoints per request, and `security.cve_alert` has 5 tools, so each of its turns would 400. The marked prefix (tools + system) was also below the minimum cacheable length, so the markers cached nothing; the part that repeats — the growing conversation across up to 8 calls — was never cached.
2. **Every API error read as a timeout.** A step's thrown error reaches the handler as an Inngest `StepError`. Inngest's serializer keeps `message`, `stack` and a string `cause`, and drops `status` and any custom `name` (rewritten to `"Error"`). So the handler's `classifyAnthropicOrLeaseError` saw no status for any Anthropic error and returned `anthropic_timeout` for all of them, including a deterministic 400 — which `retries: 3` then re-sent three more times. Unit tests passed only because the mock `step.run` re-throws the raw error in-process.

## Solution

- **Caching:** one explicit marker on the last system block plus top-level automatic caching (`cache_control: { type: "ephemeral" }` on the request; SDK 0.93 declares the field). Two breakpoints on every turn. Both keep the 5-minute TTL `MODEL_PRICING` assumes.
- **Classification:** classify the LIVE error inside the step (`classifyLiveRejection`), and RETURN a deterministic rejection as plain JSON (`{ kind: "turn_rejection", rejected, status, message, stack }`). Inngest memoizes a returned value and never retries it. Transient failures (408/409/429 — one `TRANSIENT_4XX` set — 5xx, connection errors) still throw and retry. The try covers only pre-billing statements (`getRestApiKey` through `create`), so nothing after the founder is billed can be read as a rejection.
- **Founder-account 400s:** an exhausted credit balance and the founder's own spend cap arrive as **400** `invalid_request_error`, not 402 — reuse `isAnthropicCreditExhausted` and map both to `byok_lease_unavailable`.
- **Unhandled `stop_reason`:** any stop other than `end_turn`/`tool_use` is terminal (`refusal` → `leader_refused`). Falling through appended an assistant message with no user turn after it, so the next request 400ed as a prefill — which the new classification would have labelled "request rejected".

## Key Insight

**Never route a decision that crosses an Inngest step boundary on an error's `status` or `name`. Read them on the live error inside the step and return the verdict.** The `cause` string survives; nothing else structured does. And a test harness whose mock step re-throws the raw error cannot see this class at all — model the round-trip (rebuild the escaping error with only `message`, `stack`, `cause`).

The same bug exists elsewhere: 9 cron handlers check `instanceof DeployInProgressError` after `step.run("setup-workspace")`, and the drift guard checks `instanceof LeakDetectedError` after its step (#8726).

Second insight: **a guard that pins where cache markers sit does not pin that caching works.** A system prompt that varies per turn breaks the cache on every call while every marker assertion stays green. Assert the property — the prefix (system, tools, earlier messages) is byte-identical across turns.

## Session Errors

1. **Plan Phase 2 carrier superseded twice** (custom error name, then a message tag) once measured against Inngest's serializer. — Recovery: returned value. — **Prevention:** measure what survives the boundary (`serializeError` + `new StepError`) before designing a carrier.
2. **Deferral filing refused** by the inline-threshold hook; the retry needed a milestone. — Recovery: folded into the plan. — **Prevention:** existing hook; no change.
3. **No Anthropic credential**, so prompt token sizes are character estimates. — **Prevention:** none needed; stated in the plan.
4. **A backgrounded `git commit` reported exit 0 while the commit never landed** (the trailing `git log` owned the exit). — Recovery: checked `git log`, re-committed. — **Prevention:** existing rule — `echo COMMIT_RC=$?` on the line after the commit, and never trust a background notification's exit.
5. **Pre-commit affected gate queued behind 4-5 sibling full runs.** — Recovery: `LEFTHOOK_EXCLUDE=bun-test` after the touched suite was green. — **Prevention:** run `test-all.sh --capacity` before committing `.ts` on a contended box.
6. **`pgrep -f` blocked by the self-match hook.** — **Prevention:** use `plugins/soleur/scripts/lib/proc.sh list_runs` from the start.
7. **Phase 2 affected gate sat at queue position 4 for 12+ minutes** and was killed as stale once review fixes were pending; the local exit gate never completed. — **Prevention:** on a contended box, launch the affected gate after review fixes land, once.
8. **Plan premise false: "credit exhaustion is a 402; a 400 only on older accounts".** The repo's own `cron-anthropic-credit-probe.ts` recorded the incident as HTTP 400. Five review seats caught it. — **Prevention:** before a plan asserts a vendor's status code for an error class, grep the repo for an incident record of that class.
9. **Unhandled `stop_reason` would have been relabelled "request rejected"** by the new classification. — Recovery: terminal branch + `leader_refused`. — **Prevention:** when a PR changes how a failure is labelled, enumerate every upstream path that can produce that failure.
10. **A restructure script aborted because its input file was not yet written.** — **Prevention:** write inputs first, then run the script that reads them.
11. **The `rm -rf` guard blocked a multi-path batch and a command with `df -h /tmp` after it.** — Recovery: one path per call. — **Prevention:** keep an `rm -rf` alone in its Bash call.
12. **Playwright Chromium install hung ~1h46m** on the shared `__dirlock`; nav-states gate INFRA-BLOCKED (headless shell binary missing). — **Prevention:** bound the install with `timeout -k 10 300` and treat a hang as INFRA-BLOCKED (not routed: `qa/SKILL.md` is at its byte ceiling).
13. **Guard 1 pinned marker placement, not prefix stability** — a per-turn system prompt survived the suite. — Recovery: prefix-stability test. — **Prevention:** for a caching change, assert the cached prefix is byte-stable across turns.
14. **The Guard 2 harness asserted opposite outcomes for the same 429** (an unserialized row production never produces). — Recovery: the retrying step always serializes. — **Prevention:** a harness that models a boundary must model it on every row.
15. **`require('@anthropic-ai/sdk/package.json')` failed** (`ERR_PACKAGE_PATH_NOT_EXPORTED`). — **Prevention:** read `node_modules/<pkg>/package.json` with `grep` instead.

## Tags
category: integration-issues
module: apps/web-platform/server/inngest
