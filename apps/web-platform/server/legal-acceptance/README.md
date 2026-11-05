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
`node dist/server/index.cjs`). A post-deploy smoke that loads a key from inside the container is a PR-D or ship follow-up.

## Sentry ops

Registered in `server/approval/ops.ts` with `feature: "legal-acceptance"`: `accepted` (once per recorded row),
`decide_rejected` (tag `reason`), `reauth_failed` (extra `errorClass`, never the address), `page_read_failed` (a founder page
could not read its rows; not paged) and `row_without_event` (reconciliation, to be reported by the PR-D verify endpoint; no
emitter exists before then, so its page-severity alert is inert until PR-D). Nothing logs the note, the code, the address or the text.
