# Inngest v1.19.4 `/v0/gql` schema — verified pin (Phase 0.2/0.3 BLOCKING gate)

Empirically verified against `inngest/inngest:v1.19.4` (`1.19.4-2c8385ba8`, the exact prod pin) running `inngest start` locally in Docker. This is the load-bearing reconstruction shape for `inngest-enumerate-reminders.sh` (AC1). The runbook's prior query (`id name receivedAt`) was **incomplete** — it returned no payload and was un-re-armable.

## `eventsV2` shape
- **Payload field: `raw: String!`** — a JSON-string scalar that MUST be `JSON.parse`'d. There is **NO** `data`/`payload`/`json` field on `EventV2`. `raw` is the full sorted-key envelope: `{"data":{...},"id":"<producer id>","name":"...","ts":<epoch-ms>,"v":null}`. Producer payload = `JSON.parse(node.raw).data`; future fire epoch-ms = `JSON.parse(node.raw).ts`.
- `id: ULID!` — server-generated ULID, NOT the producer id. Producer id surfaces as `idempotencyKey: String` (and inside `raw.id`).
- `occurredAt: Time!` = producer `ts` (the future fire-time). `receivedAt: Time!` = ingest time. Both ISO-8601.
- **`eventsV2(first: Int!, after: String, filter: EventsFilter!)`**. `EventsFilter`: `from: Time!` (required), `until: Time` (optional), `eventNames: [String]`, `query: String`, `includeInternalEvents: Boolean!` (required).
- **CRITICAL: `from`/`until` bound `receivedAt` (ingest time), NOT `occurredAt`/fire-time.** A future-dated event cannot be selected server-side by fire-time. Strategy: fetch a wide `from` (receivedAt lower bound covering the earliest plausible arm time) then **client-side filter** `occurredAt > now`.
- Connection: `EventsConnection { totalCount, pageInfo { hasNextPage endCursor }, edges { cursor node {...} } }`. Paginate with `first` + `after: endCursor` while `hasNextPage`.

## runs cross-ref
- Nested on the event node: `node { runs { id status startedAt endedAt } }`. `EventV2.runs: [FunctionRunV2!]!`.
- `FunctionRunStatus` enum: `COMPLETED, FAILED, CANCELLED, RUNNING, QUEUED, SKIPPED`.
- **Terminal / already-fired (DROP): `COMPLETED, FAILED, CANCELLED, SKIPPED`.** Not-yet-terminal: `RUNNING, QUEUED`. Empty `runs: []` = armed, never picked up (dominant not-yet-fired signal).
- **Re-arm decision:** keep iff `occurredAt`/`ts` is future AND no run is in `{COMPLETED,CANCELLED,FAILED,SKIPPED}`.

## working enumeration query (verified)
```graphql
query EnumReminders($first: Int!, $after: String, $filter: EventsFilter!) {
  eventsV2(first: $first, after: $after, filter: $filter) {
    totalCount
    pageInfo { hasNextPage endCursor }
    edges { cursor node { id name occurredAt receivedAt idempotencyKey raw runs { id status startedAt endedAt } } }
  }
}
```
Variables: `{ first, after, filter: { from: "<wide receivedAt lower bound>", eventNames: ["reminder.scheduled"], includeInternalEvents: false } }`.

Re-armable record reconstructed from `JSON.parse(node.raw)`: `{reminder_id, fire_at, actor, action}` (= `.data`) — exactly the `schedule-reminder` route's input (it recomputes `id`/`ts` from `reminder_id`/`fire_at`, so re-arm through the route preserves the dedup keys automatically).

## `functions` query (registered-function list, #5517)
- **`Query.functions: [Function!]`** is a registered top-level field at `POST /v0/gql` (Query introspection lists `eventsV2, functions, functionRun`). It returns the rich object array the devserver UI shows — the same loopback endpoint + no-auth as `eventsV2`.
- **`GET /v1/functions` is an UNREGISTERED route in v1.19.4 → HTTP 404, body `404 page not found`.** A `curl -s | jq type` on that body parses the leading token `404` as a number, which is why the old inventory guard reported `shape="number"`. The correct REST path is `GET /v1/apps/{appName}/functions` (requires app-name discovery) — the GraphQL `functions` query avoids that and is preferred.
- **`Function` field set** (introspected, v1.19.4): `id: String!`, `name: String!`, `slug: String!`, `failureHandler: Function`, `config: String!`, `configuration: FunctionConfiguration!`, `concurrency: Int!`, `triggers: [FunctionTrigger!]`, `url: String!`, `appID: String!`, `app: App!`.
- **`FunctionTrigger` field set**: `type: FunctionTriggerTypes`, `value: String`, `condition: String`.
- **Working names query** (what `inngest-inventory.sh` uses): `query { functions { id name slug } }` → `{"data":{"functions":[{...}]}}`; empty state → `{"data":{"functions":[]}}`. Project names with `[.data.functions[] | (.name // .slug // .id)] | sort`.
- `triggers` is `[FunctionTrigger!]` — a selection of subfields is REQUIRED (`triggers { type value }`), a bare `triggers` is a `GRAPHQL_VALIDATION_FAILED` error.

## auth
- **None on loopback `/v0/gql` in `start` mode** (HTTP 200 with no auth header). `--signing-key`/`--event-key` gate only SDK-sync + `/e/<key>` ingest, not the GraphQL read API. Verified for both `eventsV2` and `functions`.

## runbook gotcha (image invocation)
- `inngest/inngest:v1.19.4` has `ENTRYPOINT=null`, `CMD=["inngest"]` → must invoke `docker run … inngest/inngest:v1.19.4 inngest start --host 0.0.0.0 --port 8288 --sqlite-dir <dir> --signing-key <k> --event-key <k>`.
