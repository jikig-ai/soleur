# Phase 0 capture — real /v1/functions + GraphQL functions shape (inngest v1.19.4)

Captured 2026-06-18 against `inngest/inngest:v1.19.4` running `inngest start` locally in
Docker (the exact prod pin; the SAME authoritative method that pinned the eventsV2 schema in
`inngest-graphql-schema.md`). The `/v1/functions` route registration and the `/v0/gql`
`functions` field are determined by the inngest binary version, not by prod data, so a local
v1.19.4 reproduces the prod shape exactly. This is the AC1 captured evidence.

## (1) GET /v1/functions — the bug

    HTTP 404
    body: `404 page not found`     (literal text, not JSON)

The route is UNREGISTERED in v1.19.4. The inventory script's `curl -s` reads the 404 text body;
`jq 'if type=="object" then keys else type end'` parses the leading token `404` as a JSON number
→ emits `"number"` → the FATAL line reports `shape="number"`. This reproduces the issue's exact
symptom (`shape="number"`). Confirms H1 (healthy server, wrong-path artifact) — /health = 200
alongside.

## (2) /health — H1 vs H2

    HTTP 200    (healthy server; the number is a wrong-path 404 artifact, not a degraded read)

## (3) POST /v0/gql — the fix path

`Query.functions` IS a registered top-level field (Query introspection lists
`eventsV2, functions, functionRun`). Probe:

    request:  {"query":"query { functions { id name slug } }"}
    response (empty state): {"data":{"functions":[]}}

    request:  {"query":"query { functions { slug name triggers { type value } } }"}
    response (empty state): {"data":{"functions":[]}}

A populated host returns `{"data":{"functions":[{"id":"...","name":"...","slug":"...","triggers":[...]}]}}`.

### `Function` type field set (introspected, v1.19.4)
`id: String!`, `name: String!`, `slug: String!`, `failureHandler: Function`, `config: String!`,
`configuration: FunctionConfiguration!`, `concurrency: Int!`, `triggers: [FunctionTrigger!]`,
`url: String!`, `appID: String!`, `app: App!`.

### `FunctionTrigger` type field set
`type: FunctionTriggerTypes`, `value: String`, `condition: String`.

No auth on loopback `/v0/gql` in `start` mode (HTTP 200, no auth header) — same as eventsV2.

## Determination (decision tree branch (a))

Re-point the `functions` projection to the GraphQL `functions` query
(`POST /v0/gql { query: "query { functions { id name slug } }" }`), mirroring enumerate's
eventsV2 fetch. The emitted object's `functions` field stays a **sorted array of name strings**
(`[.data.functions[] | (.name // .slug // .id)] | sort`), so the workflow consumer
(`cutover-inngest.yml:239` `.functions | length`) needs NO change (AC8 satisfied without a
workflow edit). Pin the `functions` query + `Function`/`FunctionTrigger` field set in
`inngest-graphql-schema.md`.
