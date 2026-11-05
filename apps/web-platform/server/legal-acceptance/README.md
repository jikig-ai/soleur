# Legal acceptance (server)

Server side of the founder legal-acceptance card (#12011, ADR-319).

- `canonical.ts`: the text registry. One file per key under `texts/`; the recorded `text_hash` is the sha256 of the file's raw bytes.
- `service.ts`: typed wrappers over the migration-184 RPCs and the decide orchestration. `record_legal_acceptance` is called with the user-context client only.
- `reauth.ts`: identity (founder id and email from `getUser()`, web session id as the SQL reads it), the email-code check on a throwaway auth client, the per-user verify ceiling and the shared request guard.

Routes: `app/api/legal-acceptance/[key]/reauth` and `.../decide`.

## How the texts reach the production image

The server is bundled with esbuild into `dist/server/index.cjs` and the route handlers run from the Next build, so a
directory next to the compiled module does not contain `texts/`. The texts are COPIED into the runtime image, not
embedded in the bundle: the Dockerfile runner stage has

```text
COPY --from=builder /app/server/legal-acceptance/texts ./server/legal-acceptance/texts
```

and `resolveTextsDir` in `canonical.ts` reads `<cwd>/server/legal-acceptance/texts` when the directory next to the
module does not exist (the container working directory is `/app`, the same convention as `infra/egress-forwarder.mjs`).
Copying keeps the bytes untouched, so `sha256sum <file>` equals the recorded `text_hash`; an embedded string module would
need a generated file and a build step in two bundlers. `.dockerignore`'s `*.md` rule matches only at the context root, so
it does not drop this directory today; the `!server/legal-acceptance/texts/*.md` re-include is belt-and-braces.

`test/legal-acceptance/registry-embedding.test.ts` builds a bundle with the production esbuild flags, lays it out like
the image (bundle at `dist/server`, texts under `server/legal-acceptance/texts`, cwd at the app root), runs it with
node and compares the hash with `sha256sum`. It also asserts the Dockerfile COPY and the `.dockerignore` re-include. That
covers the esbuild bundle layout; the Next-compiled routes and pages rely on the same cwd convention (`WORKDIR /app`,
`node dist/server/index.cjs`). The post-deploy registry smoke (a key loaded from inside the container) stays open: no text is committed, so every key answers 404 and there is nothing to load (#12197).

## Sentry ops

Registered in `server/approval/ops.ts` with `feature: "legal-acceptance"`: `accepted` (once per recorded row),
`decide_rejected` (tag `reason`), `reauth_failed` (extra `errorClass`, never the address), `page_read_failed` (a founder page
could not read its rows; not paged) and `row_without_event` (reconciliation, reported by the check endpoint, see Ack and
reconciliation). PR-D adds `record_invalid` (a row failed its checksum; error) and `store_failed` (a verify, ack-state or ack
call failed; error; tag `stage` is `verify`, `ack_state` or `ack`). `record_invalid` and `store_failed` have no paging rule yet
(#12195). Nothing logs the note, the code, the address or the text.

## Check endpoint (PR-D)

`GET /api/internal/legal-acceptance/[key]?hash=<64 hex>` answers about the one founder id in its own configuration
(`LEGAL_ACCEPTANCE_FOUNDER_ID`), never one from the request. The 200 body has exactly four keys: `status`, `text_hash`,
`decided_at`, `row_ok`; it never carries the note. A row whose checksum no longer matches is `invalid` with `row_ok: false` and is
never reported as `none`. Auth is a bearer token, `LEGAL_ACCEPTANCE_VERIFY_TOKEN`, read through `lib/internal-auth.ts`
(`readInternalBearerSecret` takes the secret name) and separate from the Inngest token. Check order: 503 (token or founder id unset
or malformed, or the registry cannot be read), 401 (wrong token), 400 (malformed key or hash), 404 (key not in the registry), then
the lookup. Other statuses the route can emit are 200 and 502 (an RPC answer it does not recognise). `/api/internal/legal-acceptance`
is a narrow `PUBLIC_PATHS` entry so the middleware does not redirect it to the login page. The code merges dark: the endpoint answers
503 until the token and the founder id exist (follow-up #12196).

The hash is answered from the database for the exact hash asked. Whether it equals the committed text is the caller's job: the
`web-acceptance` gate in `plugins/soleur/skills/ship/scripts/hold-gate-eval.sh` compares it with the sha256 of the committed file.

## Ack and reconciliation (PR-D)

Migration 185 adds `legal_acceptance_ack(acceptance_id, acked_at)`, reachable only through two service-role RPCs:
`ack_legal_acceptance` and `legal_acceptance_ack_state`. It holds no founder id, no note and no decision field. The decide route
writes the ack only after the `accepted` event was emitted and `Sentry.flush` resolved true, off the request path, so the founder's
response never waits on it; `already_recorded` never acks. When the endpoint finds a row it reads the ack state and emits
`row_without_event` if the row has no ack and is older than the 120 s grace. That proves the web route did not ack the row, not that
Sentry received the event. It is alert-only (the response and the gate do not change) and pull-driven: it fires when a row is
verified. A sweep over unacked rows is a follow-up (#12194).

## Ops notes

- Request changes note: pull-only, read by the operator personally; see
  `knowledge-base/engineering/operations/runbooks/legal-acceptance-note-read.md`. Nothing pushes it, and no card copy changed.
- A row whose ack was lost is reconciled by the operator through the same runbook after confirming with the founder.
- Hard limits on the endpoint: the 48-character token, the read-only RPC and the single configured founder id. A wrong token is
  answered 401 with no throttle.
- A recorded Yes authorizes no production act; a `web-acceptance` gate backs only a hold on that legal acceptance itself.
- The founder page still shows an `invalid` row as recorded (no card state for it, #12193).
