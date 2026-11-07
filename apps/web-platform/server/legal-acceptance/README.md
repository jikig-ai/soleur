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
call failed; error; tag `stage` is `verify`, `ack_state`, `ack`, `registry` (the legal text could not be read, or the committed text is malformed; the on-call reads `extra.code`) or `config` (a token or
founder id that is set but malformed; once per process, names only the variable)). `record_invalid` and `store_failed` have no paging rule yet
(#12195). Nothing logs the note, the code, the address or the text.

## Check endpoint (PR-D)

`GET /api/internal/legal-acceptance/[key]?hash=<64 hex>` answers about the one founder id in its own configuration
(`LEGAL_ACCEPTANCE_FOUNDER_ID`), never one from the request. The 200 body has exactly four keys: `status`, `text_hash`,
`decided_at`, `row_ok`; it never carries the note. A row whose checksum no longer matches is `invalid` with `row_ok: false` and is
never reported as `none`. The check order, the closed set of statuses (including what each 503 and 502 covers) and the auth
shape are in the route docblock (`app/api/internal/legal-acceptance/[key]/route.ts`) and in ADR-319 (PR-D amendment, "Read path
as built"). The token is `LEGAL_ACCEPTANCE_VERIFY_TOKEN` (minted at 48 alphanumeric characters per Doppler config by `infra/legal-acceptance-secrets.tf`, #12196; the guard accepts 48 to 256),
read through `lib/internal-auth-named.ts` so that `lib/internal-auth.ts` stays byte-identical to the CLO-discharged census sha.
`/api/internal/legal-acceptance` is a prefix `PUBLIC_PATHS` entry (dynamic `[key]` segment; every handler under it must check the
bearer first). The code merges dark: the endpoint answers 503 until the token and the founder id exist (follow-up #12196).

The hash is answered from the database for the exact hash asked. Whether it equals the committed text is the caller's job: the
`web-acceptance` gate in `plugins/soleur/skills/ship/scripts/hold-gate-eval.sh` compares it with the sha256 of the committed file.

## Ack and reconciliation (PR-D)

Migration 185 adds `legal_acceptance_ack(acceptance_id, acked_at)`, reachable only through two service-role RPCs:
`ack_legal_acceptance` and `legal_acceptance_ack_state`. It holds no founder id, no note and no decision field; it is pseudonymous
personal data through its key (the id of a `legal_acceptance` row), and the deletion path for `legal_acceptance` (#12080) must
delete the matching ack rows too (no foreign key, so no cascade). The decide route writes the ack only after the `accepted` event
was emitted and `Sentry.flush` resolved true, off the request path, so the founder's response never waits on it;
`already_recorded` never acks. When the endpoint finds a row it reads the ack state and emits `row_without_event` if the row has no
ack and is at least 120 s old. That proves the web route did not ack the row. It does not prove that Sentry received the event:
a `true` flush result means the flush completed without an error, not that Sentry received and kept the event (it can also be
`true` when no DSN is configured, or when the event was dropped before sending), so a row that raises no `row_without_event` is not
proof that its `accepted` event was delivered. `row_without_event` is alert-only; if the reconciliation read fails or disagrees
with the verify read, the endpoint answers 503 or 502 and never a partial 200. It is pull-driven: it fires when a row is
verified. A flush that answers false or times out acks nothing and writes one warning log line (key only); a flush that throws or
an ack write that fails is `store_failed` (stage `ack`). A sweep over unacked rows is a follow-up (#12194). Migrations apply
before the deploy, so the functions exist when the code that calls them runs.

## Ops notes

- Request changes note: pull-only, read by the operator personally; see
  `knowledge-base/engineering/operations/runbooks/legal-acceptance-note-read.md`. Nothing pushes it, and no card copy changed.
  The note is not readable through the endpoint or any `service_role` path; a database-owner credential could read it; it is held by
  the operator and by the production migration pipeline (a CI secret), and no agent session is meant to use either, so "not shown to an
  agent" is a policy, not a control.
- A row whose ack was lost is reconciled through the same runbook after confirming with the founder. Before the `approval-queue`
  flag is on in the production project, the runbook's pre-flip count check must pass.
- Hard limits, the token, the accepted residuals and the open items: ADR-319 (PR-D amendment).
- The founder page still shows an `invalid` row as recorded (no card state for it, #12193).
