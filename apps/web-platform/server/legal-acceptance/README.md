# Legal acceptance (server)

Server side of the founder legal-acceptance card (#12011, ADR-319).

- `canonical.ts`: the text registry. One file per key under `texts/`; the recorded `text_hash` is the sha256 of the file's raw bytes.
- `service.ts`: typed wrappers over the migration-184 RPCs and the decide orchestration. `record_legal_acceptance` is called with the user-context client only.
- `reauth.ts`: identity (founder id and email from `getUser()`, web session id as the SQL reads it), the email-code check on a throwaway auth client, the per-user verify ceiling and the shared request guard.

Routes: `app/api/legal-acceptance/[key]/reauth` and `.../decide`.

**Who gates what.** The `service.ts` exports (`issueIntent`, `claimAttempt`, `markVerified`, `recordAcceptance`, `decideLegal`) are
deliberately UNGATED: they check neither the surface gate (`surface.ts`: `LEGAL_ACCEPTANCE_FOUNDER_ID` only; the `approval-queue` flag is not read) nor the
declared card kind. Only the two routes gate, through `guardLegalRequest` (surface gate first, then key, registry, kind). A new caller of these
functions (an Inngest function, a script) bypasses the gate; route every new entry point through `guardLegalRequest`. The database does not
check the founder id or the kind either: `record_legal_acceptance` needs a live server-issued intent, and a founder who holds one (30 minutes) cannot
record through the route once the gate is off (the decide route re-checks the gate on every request; a test pins it).

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
`node dist/server/index.cjs`). The post-deploy registry smoke (a key loaded from inside the container) stays open (#12197): a key can only be loaded from inside the container once a text is committed and deployed. The first one, `founder-acceptance-record`, is signed off as a v1 internal position (the CLO agent's ruling of 2026-11-07, which stands in for counsel on the operator's instruction and is not a lawyer's opinion); the smoke stays open until a text is published and answered.

## Who sees the card, and what it says

The card pages, the Inbox row and the decide and reauth routes require only that the signed-in user id equals
`LEGAL_ACCEPTANCE_FOUNDER_ID` (`isLegalSurfaceEnabled` in `surface.ts`; an unset or malformed variable disables the surface for
everyone). Anyone else gets the same 404 as an unknown key. The `approval-queue` flag is not read, so narrowing or turning off the
approval queue does not hide the founder's screen (why: ADR-319 "Amendment 2026-11-10 (#12197)"). Turning the flag on or off is the
operator's act, and an agent session does not do it.

The founder id is the only gate in every environment that sets it; the code does not check the environment. On 2026-11-10 it is
set only in the production Doppler config (`prd`, and the `prd_scheduled` and `prd_terraform` configs that inherit it) and unset in
`dev`, `dev_personal`, `dev_scheduled`, `ci`, `cli` and `cli_ops` (presence read, value not printed). A value set in a dev config opens
the card only for that user id in the dev Supabase project, which is a separate project from production; dev rows are never read by
ship's holds, which query only `https://app.soleur.ai`.

Kill switch, operationally:

- Unset the variable in Doppler, then redeploy; a restart is not enough, because the container's env file is frozen at creation
  (`hr-prod-host-config-change-immutable-redeploy`).
- It closes the surface for everyone. Already-recorded rows still render read-only on the card page and the index.
- It is also the production rollback: keep the schema and unset the variable. The header of
  `supabase/migrations/184_legal_acceptance.down.sql` still says "leave the flag off"; migrations are immutable, and ADR-319
  Amendment 2026-11-10 supersedes that line.
- It also closes the check endpoint (503), so ship's `web-acceptance` holds stay standing until the value is restored and the app
  redeployed. The counts route reads no founder id and keeps answering.
- An unset variable is silent. A set-but-malformed one reports `store_failed` / stage `config` once per reading module per process
  (the surface and the check endpoint each report, so up to two).
- To tell an accidental removal from a working setup, request the check endpoint without a token: 401 means the token and founder id
  are set and valid; 503 `{"error":"Not available"}` means one of them is unset or malformed (malformed also raises the `config` report).
- A founder mid-flow (code sent, not yet decided) gets a 404 on decide after the redeploy, and the intent expires unused.

Ruled by CTO agent, 2026-11-10.

The card's wording depends on the kind declared for the text key in `LEGAL_TEXT_KIND` (`lib/legal-acceptance-copy.ts`): `terms` or
`acknowledgement`. There is no default. A registered text with no declared kind renders no card, is a 404 on the card page, the decide route
and the reauth route (`guardLegalRequest`), is left out of the index, and is reported as `kind_undeclared` on every render of the card page or the index, after the surface gate (not debounced: the surface is founder-only).
`test/legal-acceptance/registry-pins.test.ts` requires the served keys, the pinned keys and the declared kinds to be the same set.

## Sentry ops

Registered in `server/approval/ops.ts` with `feature: "legal-acceptance"`: `accepted` (once per recorded row),
`decide_rejected` (tag `reason`), `reauth_failed` (extra `errorClass`, never the address), `page_read_failed` (a founder page
could not read its rows; not paged), `kind_undeclared` (a registered text has no declared card kind, so the page 404s and the index leaves it out; warn; tag `key`; reported only after the founder surface gate; not paged) and `row_without_event` (reconciliation, reported by the check endpoint, see Ack and
reconciliation). PR-D adds `record_invalid` (a row failed its checksum; error) and `store_failed` (a verify, ack-state or ack
call failed; error; tag `stage` is `verify`, `ack_state`, `ack`, `registry` (the legal text could not be read, or the committed text is malformed; the on-call reads `extra.code`) or `config` (a token or
founder id that is set but malformed; once per reading module per process, names only the variable)). `record_invalid` and `store_failed` have no paging rule yet
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
bearer first). The code merges dark: the endpoint answers 503 until the token (minted by Terraform, #12196) and the founder id (entered by the operator) exist and the web app is redeployed.

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
- A row whose ack was lost is reconciled through the same runbook after confirming with the founder. Before a text change is
  published, the runbook's count check must pass.
- Hard limits, the token, the accepted residuals and the open items: ADR-319 (PR-D amendment).
- The founder page still shows an `invalid` row as recorded (no card state for it, #12193).
