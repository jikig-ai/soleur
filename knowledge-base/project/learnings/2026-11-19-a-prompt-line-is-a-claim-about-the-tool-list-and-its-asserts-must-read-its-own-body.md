---
title: A prompt line is a claim about the session's tool list, and its asserts must read its own body
date: 2026-11-19
category: test-failures
module: web-platform cc-dispatcher system prompt, cc-dispatcher-real-factory tests
tags: [review, prompt, degraded-path, test-design, vacuous-assert, catch-flag]
issue: 12598
pr: 12957
---

# Learning: a prompt line is a claim about the session's tool list, and its asserts must read its own body

## Problem

#12598 adds a line to the agent's system prompt when the workspace grant is on but the web-egress forwarder failed to
start. The plan and its CTO rulings passed plan review, and the author's six-row mutation battery passed. The review
panel still found three defects, all in what the plan prescribed rather than in how it was typed:

1. **The plan's main content assert could never fail.** `expect(prompt).toContain("failed to start")` ran against the
   whole system prompt, and `BASH_UNAVAILABLE_PROMPT_DIRECTIVE` is appended to every prompt and already contains
   "sandbox failed to start". Replacing the line's whole body with "`WebFetch` is unavailable." stayed 138/138 green, as
   did dropping its retry and new-conversation sentences. The author's battery mutated the gate and the heading, never
   the body, so it could not see this.
2. **The line's "no GitHub claim" ruling checked the prompt, not the tool list.** On the failure path the server-side
   `github_*` read tools stay registered (they use the installation token, not the forwarder), while the line told the
   agent it had no web access and to say so for anything needing the web. The agent would refuse GitHub questions its own
   tools could answer. The fix is a clause gated on `readRegistration.registered`, the same value that registers the
   tools. Its first draft named "the `github_*` tools", which also matches the gated write tool `github_push_branch`;
   it now names the `github_read_*` and `github_list_*` family.
3. **A flag set in a catch can coexist with the success state.** The spawn `try` also wrapped the `webEgress = {...}`
   assignment and a `log.info`, so a throwing log line would set "failed" while the forwarder was live, and one prompt
   would carry both "Web access enabled" and "Web access unavailable". The flag is now derived after the block:
   `webEgressEntitled && mode.runRepoLifecycle && webEgress === undefined`, the same handle the enabled addendum reads.

## Solution

- `startFailedBody(p)` in the test splits on the heading, asserts exactly one occurrence, and returns the body; every
  content assert reads that body. A no-repo row asserts the GitHub clause is absent, the degraded #12469 row asserts it
  is present, and a row makes the bound log line throw and asserts the enabled section is present and the line absent.
- Mutations re-driven by the lead and the test-design seat, each caught: clause unconditional, clause dropped, flag
  without `webEgress === undefined`, flag restored to catch-set, retry sentence removed, suffix dropped from the prompt,
  line emitted twice.

## Key Insight

A sentence in an agent's prompt is a claim about the session's capabilities. Check each clause against the tool list
the SDK actually receives on that path (`mcpServers`, `allowedTools`, `disallowedTools`), not only against the other
prompt text. And an assert on a section of a prompt built from many sections must read that section's body: check every
asserted fragment against the base prompt first, or the assert is satisfied by a sibling section.

## Session Errors

1. **collision-precheck.sh exit 10 on this branch's own draft PR** — Recovery: confirmed same head ref, no files —
   Prevention: none needed (the script reports the hit; the caller reads the head ref).
2. **Invalid YAML in the plan (unquoted colon-space)** — Recovery: quoted — Prevention: existing plan lint.
3. **markdownlint MD038 nested backticks** — Recovery: fixed — Prevention: existing lint.
4. **CTO ruling T1's rationale was factually wrong about `readRegistration`** — Recovery: amended as T1-r — Prevention:
   the plan-sharp-edges bullet below (verify a claim about a path against the code on that path).
5. **plan-sharp-edges.md read by grep (64k tokens); deepen right-sized to 3 seats** — Recovery: disclosed in the plan —
   Prevention: none (disclosed trade-off).
6. **Ruling T2 missed that `github_*` read tools stay registered on the failure path** (git-history seat, P2) —
   Recovery: CTO T2-r1, a clause gated on `readRegistration.registered` — Prevention: plan-sharp-edges bullet (check a
   prompt claim against the built tool list).
7. **The prescribed whole-prompt `toContain("failed to start")` could never fail** (test-design seat, P2) — Recovery: CTO
   T3-r3, body-scoped asserts — Prevention: plan-sharp-edges bullet (grep each asserted fragment against the base prompt).
8. **Catch-set flag could coexist with a live forwarder** (security, simplicity, code-quality seats) — Recovery: CTO
   T1-r2, flag derived from the success handle — Prevention: this learning; derive a failure flag from the success handle
   when the `try` wraps post-success code.
9. **First clause draft named `github_*`, matching the gated `github_push_branch`** (architecture and code-quality fix-round
   seats) — Recovery: named the read family — Prevention: one-off; list the tool names before naming a glob.
10. **Stop hook fired on a closing "I'll take it to the CTO" with no action taken** — Recovery: ended the turn with a
    `Paused:` line — Prevention: already hook-enforced (the stop hook).
11. **A seat brief carried a 38-character SHA** — Recovery: the seat used short SHAs — Prevention: one-off; derive SHAs
    with `git rev-parse` in the same call that writes the brief.
12. **Eleven auto-compactions in one session** — Recovery: none in-session — Prevention: the existing compaction
    directive; the resume prompt recommends a fresh session.

Accepted residual (CTO T1-r2): a throwing bound log line still reports `web-egress-forwarder-spawn` to Sentry; the
prompt is correct in that case.

## Tags

category: test-failures
module: web-platform cc-dispatcher
