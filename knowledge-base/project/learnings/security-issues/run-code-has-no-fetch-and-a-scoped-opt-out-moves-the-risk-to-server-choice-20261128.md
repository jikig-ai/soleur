---
title: 'browser_run_code_unsafe has no fetch; a scoped opt-out moves the risk to which server you call'
date: 2026-11-28
category: security-issues
tags: [playwright-mcp, run-code, page-request, redact-proxy, opt-out, cloudflare-remint]
symptoms: [Phase 5 mint returned refused:"sink" and deleted a good token, ReferenceError fetch is not defined inside browser_run_code_unsafe]
module: agent-browser
component: playwright-mcp-redact-proxy
problem_type: security_issue
resolution_type: code_fix
root_cause: wrong_api_assumption
severity: high
---

# Learning: run_code has no `fetch`, and a scoped opt-out moves the risk to server choice

## Problem

The #12931 Phase 5 mint body (`p5-mint.js`) handed a fresh Cloudflare token to a 127.0.0.1 sink with a bare
Node-side `fetch`. In @playwright/mcp 0.0.78 the `browser_run_code_unsafe` vm context holds only `page`, `__end__`
and the compiled `__fn__` (V8 supplies `console`); no host global is copied in. The call threw, the cleanup deleted
the good token, and the mint returned `{refused:"sink"}`.

Moving the hand-off to `page.request.post` put a token on a plain-http loopback request sent by the server process,
so the redact proxy gained refusals for anything that could proxy, record or MITM it (proxy flags, `NODE_OPTIONS`,
`NODE_EXTRA_CA_CERTS`, `NODE_TLS_REJECT_UNAUTHORIZED`, config `proxy`/`recordHar`/`extraHTTPHeaders`). The
user-impact seat then found that those refusals locked out every user behind a corporate proxy or extra CA.

## Solution

- Mint: `page.request.post(sinkPost, {maxRedirects: 0, failOnStatusCode: false, timeout: 15000})`. The sink proves
  itself with a 32-char answer carried as the `sink_url` fragment. Before sending, the body checks for tampering
  with `page.request === page.context().request` and no own `post`/`delete`. `Object.hasOwn(page, 'request')` is
  always true in 0.0.78 (Page constructor), so it is not usable as a check.
- Proxy: refusals stay on by default. `--allow-proxy-and-node-env` (before `--`) turns off exactly the proxy
  argv/env rows, the three `NODE_*` rows and the config `proxy` key. Only `plugins/soleur/.mcp.json` passes it.
- Every startup refusal on a setting ends with a `To fix:` remedy.
- Runbook: the sitting runs on the repo `.mcp.json` server. It checks that `claude mcp get playwright` shows no
  opt-out flag and calls only `mcp__playwright__browser_run_code_unsafe`, never `mcp__plugin_soleur_playwright__*`.

## Key Insight

When a guard is relaxed for one registration, choosing which registration to call becomes the security control.
Before the opt-out, both servers refused the same settings, so calling the wrong one was harmless. After it, the
plugin server starts under exactly the settings the sitting must exclude. Any procedure that depends on the strict
registration has to pin the tool prefix, not just inspect that registration's args.

A second lesson: a ruled mechanism (`hasOwn`, a new `sink_answer` argument) is a hypothesis. Measure it against the
pinned dependency and the frozen artifacts (archived plan holds) before implementing it.

## Session Errors

1. **First push rejected transiently.** Recovery: retry. **Prevention:** none needed (one-off).
2. **S1b compared the full sink answer, but the client prints 20 body chars.** Recovery: compare `${SINK_ANSWER:0:20}`. **Prevention:** read the consumer's print width before asserting on its output.
3. **XM17 anchor stale after renaming `sinkPost`.** Recovery: retarget. **Prevention:** the harness's "did not land" FAIL already catches it; rerun mutants after any rename.
4. **Ruled `Object.hasOwn(page,'request')` would refuse every mint.** Recovery: identity check plus own-method check. **Prevention:** measure a ruled check against the pinned library source (coreBundle.js) before implementing it.
5. **Ruled `sink_answer` argument would break archived-plan hold parity.** Recovery: carry the answer as the URL fragment. **Prevention:** grep frozen artifacts that pin the command shape before adding an argument.
6. **A perl substitution for the `__fn__` wording matched nothing, silently.** Recovery: python replace with `assert count == 1`. **Prevention:** use replacements that assert their match count.
7. **Proxy suite run under parallel load gave 2 timing FAILs.** Recovery: rerun alone. **Prevention:** run the redact-proxy suite with no concurrent suites.
8. **My `.ini`/context_keys refactor broke FR5 `.ini` fixture, row 41 and the mutant 76 anchor.** Recovery: rename the fixture to `.conf`, retarget the anchors. **Prevention:** after changing a refusal's condition, grep the test file for fixtures and mutants anchored on the old lines.
9. **Edited the proxy and test while their suite ran in the background.** Recovery: TaskStop, commit, rerun. **Prevention:** commit first and run a suite only against a tree nobody edits until it finishes.
10. **`pkill -f` blocked by hook; then `list_runs`/`kill_mine` called without a pattern.** Recovery: `kill_mine <pattern>`. **Prevention:** already hook-enforced; pass the pattern.
11. **`emit-review-trailer.sh` skipped because a trailer existed.** Recovery: `--fix-round --since <panel sha>`. **Prevention:** after a post-review fix round, use `--fix-round`.
12. **The opt-out made a wrong-server call unsafe, and the runbook did not pin the prefix (security re-review P2).** Recovery: runbook pins `mcp__playwright__` and forbids the plugin prefix. **Prevention:** when relaxing a guard per registration, sweep every procedure that relies on the strict one and pin its tool prefix (routed to agent-browser SKILL.md).

## Tags

category: security-issues
module: agent-browser
