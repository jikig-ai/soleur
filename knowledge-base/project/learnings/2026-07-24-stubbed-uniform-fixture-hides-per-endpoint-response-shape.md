---
title: "A uniform stub fixture hides a per-endpoint response-shape divergence; only live QA (or a captured-real fixture) catches it"
date: 2026-07-24
category: test-failures
tags: [testing, fixtures, cloudflare, external-api, qa, fail-closed]
module: plugins/soleur/skills/cf-token-scope
issue: 6755
pr: 6892
problem_type: test-vacuity
---

# Learning: a uniform stub fixture hides a per-endpoint response-shape divergence

## Problem

Building `soleur:cf-token-scope` (a Cloudflare retained-scope probe), the body-shape
layer of a three-layer fail-closed classifier required `.result | type == "array"`
for **every** probe. The bash unit test stubbed `curl` and returned the SAME shape
— `{"success":true,"result":[]}` — for all six endpoints. 41 assertions passed, a
6-agent review panel (incl. a dedicated test-vacuity agent that ran an 11-mutation
battery) found no shape bug, and the full suite was green.

Then **live QA against production Cloudflare** exited 3 on a healthy token: every
zone entrypoint reported `degraded (200 body not success/array)`, only the account
list reported `authorized (200)`.

## Root cause

Cloudflare returns `.result` as **different JSON types per endpoint**:

- `GET /zones/<zone>/rulesets/phases/<phase>/entrypoint` → `.result` is a single
  ruleset **object** (`{id, kind, phase, rules, ...}`).
- `GET /accounts/<acct>/rulesets` (list) → `.result` is an **array**.

The `type == "array"` check was correct only for the account list; it rejected
every real authorized zone 200. The uniform `result:[]` stub matched the (wrong)
array assumption on both schemes, so the test was structurally incapable of
observing the divergence — a **fixture-shape** coverage hole, not a mutation the
battery missed. Mutation testing, assertion count, and parametricity all miss it
because they vary the *code* and the *assertions*, never the *fixture shape*.

## Solution

1. Make the body-shape check **per scheme**: `authorized_body <body> <want_type>`
   where `want_type` is `object` for zone entrypoints and `array` for the account
   list (derived from the probe's scheme). `null` is neither, so the degraded
   `{"success":true,"result":null}` fail-open still fails closed in both directions.
2. Correct the stub to the **real** shapes (zone → object, account → array) and add
   regression assertions that pin the type in BOTH directions (a zone 200 whose
   result is an array FAILs; an account 200 whose result is an object FAILs) —
   mutation-verified.
3. Verify against the live endpoint (read-only) before trusting green.

## Key Insight

**A stub that returns one uniform response shape cannot test a contract where the
real service returns different shapes per endpoint.** For any classifier/parser
keyed on an external API's response *shape*, a unit test proves only that the code
agrees with the *fixture author's model* of the API — which is exactly the thing in
doubt. Land a captured-real fixture (per endpoint), or run a live read-only probe in
QA, before trusting the shape assertion. This is the response-shape sibling of "an
external-API shape AC must land a captured fixture, not a probed claim."

Corollary (#6): a fail-closed classifier's 404-trust must be pinned to the ONE
endpoint whose 403-on-missing was empirically verified; trusting 404 on unverified
phases is a fail-open a dropped scope can hide behind. The plan's Phase 0 flagged
"pin the semantics or keep 404=FAIL" — skipping that precondition shipped the
fail-open to review.

## Session Errors

1. **Plan-phase review agents died mid-response (API connection closed)** — Recovery: resolved their questions from first-party analysis. Prevention: transient; one-off.
2. **PreToolUse hook blocked `doppler secrets set` in negation prose** during planning — Recovery: `iac-routing-ack` comment + reword. Prevention: expected guard behavior; one-off.
3. **Draft-PR init commit diverged after rebase → push rejected** — Recovery: `git push --force-with-lease`. Prevention: expected when rebasing a fresh draft branch; one-off.
4. **`doppler run -c prd_terraform -- bash <self-fetching-script>` broke the script's nested `doppler secrets get` (empty → exit 2)** — Recovery: run the script standalone (it self-fetches via `doppler secrets get`). Prevention: a script that reads its own secrets via `doppler secrets get -p … -c …` must NOT be wrapped in `doppler run`; the nested call under a `doppler run` env returns empty. SKILL.md Usage shows the correct standalone form.
5. **Uniform stub fixture hid the per-endpoint response-shape divergence** — Recovery: per-scheme type check + captured-real shapes + bidirectional regression tests + live probe. Prevention: this learning; for external-API shape contracts, verify against a captured-real or live response, not a self-authored uniform stub.
6. **Fail-open 404-trust on unverified phases (plan Phase-0 precondition skipped)** — Recovery: trust 404-as-empty only for the ADR-130-verified `http_config_settings`; fail closed elsewhere. Prevention: honor plan Phase-0 "pin the live semantics or fail closed" preconditions before shipping a live-API gate.

## Tags

category: test-failures
module: plugins/soleur/skills/cf-token-scope
