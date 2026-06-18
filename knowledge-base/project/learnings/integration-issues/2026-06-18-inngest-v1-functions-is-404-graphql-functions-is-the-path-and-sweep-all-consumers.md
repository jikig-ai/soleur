---
title: "inngest GET /v1/functions is an unregistered 404; /v0/gql functions is the path — and sweep ALL endpoint consumers, not just the plan's named two"
date: 2026-06-18
category: integration-issues
module: apps/web-platform/infra
issue: 5517
tags: [inngest, graphql, external-api-shape, captured-fixture, sweep-discipline, no-ssh]
related:
  - knowledge-base/project/learnings/integration-issues/2026-06-16-external-api-shape-ac-must-land-captured-fixture-not-probed-claim.md
  - knowledge-base/project/learnings/best-practices/2026-05-18-sweep-class-fixes-grep-enumerated-not-intuited.md
---

# Learning: inngest `/v1/functions` is a 404; the registered path is `/v0/gql { functions }` — and grep ALL consumers

## Problem

`op=inventory` (host-side cutover diagnostics) failed loud:
`FATAL /v1/functions unreachable or non-array (shape="number")`. The script assumed
`GET /v1/functions` returns a JSON array of function objects. The shape was **mirrored**
from a sibling (`inngest-wiped-volume-verify.sh`) whose `jq 'if type=="array" then length
else 0 end'` *tolerated* a non-array — so no path ever captured the real bytes.

## Root cause (captured against the exact prod pin)

Spun up `inngest/inngest:v1.19.4` in Docker and probed directly:

- `GET /v1/functions` → **HTTP 404**, body `404 page not found` (literal text). `curl -s | jq`
  parses the leading token `404` as a JSON number → the FATAL reports `shape="number"`.
  The route is **UNREGISTERED** in v1.19.4 (the v1 router registers
  `GET /v1/apps/{appName}/functions`, not a bare `/v1/functions`).
- `/health` → 200 (confirms the number is a wrong-path artifact on a HEALTHY server, not a
  degraded read).
- `POST /v0/gql { functions { id name slug } }` → `{"data":{"functions":[…]}}` — a clean
  object array, registered top-level Query field, no auth on loopback (same endpoint
  `eventsV2` already uses).

## Solution

Re-point the `functions` projection to the GraphQL `functions` query (mirrors enumerate's
`eventsV2` fetch): guard on `.data.functions | type == "array"`, project
`[.data.functions[] | (.name // .slug // .id)] | sort`. The emitted object's `functions`
field stays a sorted **name array**, so the workflow consumer
(`cutover-inngest.yml:239` `.functions | length`) needs no change.

## Key Insight

1. **A quoted external-API shape is a hypothesis, not a fact** (reinforces
   [[2026-06-16-external-api-shape-ac-must-land-captured-fixture-not-probed-claim]]). The
   version-determined route registration is reproducible in local Docker WITHOUT touching
   prod — the `/v1/functions` 404 and the `/v0/gql functions` field are functions of the
   inngest binary version, not prod data. Local-Docker capture is the authoritative,
   no-SSH-needed method (same way the `eventsV2` schema was pinned).
2. **Sweep ALL consumers of the broken endpoint via grep — the plan's named set is a
   starting hypothesis.** `git grep '/v1/functions'` found **three** consumers; the plan
   named two. The third (`ci-deploy.sh:302`, an advisory cron-plan probe using `curl -sf`)
   was permanently dead (404 → empty → advisory always fires). It was a different
   subsystem (the hard deploy gate + a 2000-line test, needs an advisory-probe redesign) →
   filed as its own issue (#5520), not folded in. Reinforces
   [[2026-05-18-sweep-class-fixes-grep-enumerated-not-intuited]].

## Session Errors

1. **inngest container start failed twice during Phase-0 capture.** `--signing-key
   signkey-prod-<64hex>` → `signing-key must be hex string with even number of chars` (the
   v1.19.4 `start` parser hex-decodes the WHOLE value, prefix included); starting with no
   keys → `signing-key is required`. **Recovery:** pure-hex signing key
   (`$(printf 'ab%.0s' {1..32})`). **Prevention:** documented in
   `inngest-graphql-schema.md` §"runbook gotcha (image invocation)".
2. **`${WVV_FUNCTIONS_BODY:-<brace-heavy JSON>}` in the sibling test mock** terminated the
   parameter-expansion default at the first `}` inside the JSON → malformed output →
   sibling GREEN failed on first run. **Recovery:** explicit `if [[ -n "$VAR" ]]; then …
   else printf '<json>'; fi`. **Prevention:** never put brace-heavy JSON in a `${:-default}`;
   documented inline in the test mock comment.
3. **(forwarded from session-state.md)** two deepen-plan gate false-positives (4.7 SSH check
   tripped on a `# NO ssh` annotation; 4.9 UI check matched negative prose) — self-resolved
   during planning. One-off; no recurrence vector.
