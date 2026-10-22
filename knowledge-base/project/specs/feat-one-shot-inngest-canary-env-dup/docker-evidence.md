# Local real-Docker confirmation (2026-10-22, Docker 29.9.2, image bash:3.2, containers created and removed, none started except one `--rm env`)

Not CI and not production. A green mock is a proxy; this is the real daemon's view of the same input shapes.

| Input | Entries for `INNGEST_BASE_URL` in `Config.Env` |
|---|---|
| `--env-file` with `INNGEST_BASE_URL=http://pinned-in-file` plus `-e INNGEST_BASE_URL=https://flag` (no scrub) | **2** (both kept: the production symptom) |
| the same env-file after `inngest_link_scrub_env_file` plus the same `-e` | **1** |
| `docker run --rm` of the unscrubbed pair, `env` inside | the `-e` value is the one the process sees (last wins), so the app was never reading the env-file value |
| `INNGEST_BASE_URL =padded` (space before `=`) | Docker refuses the env-file: `variable 'INNGEST_BASE_URL ' contains whitespaces` |
| a no-break space (U+00A0) before the name | Docker accepts it as `INNGEST_BASE_URL` (1 entry): the scrub's name-prefix class must tolerate it |
| a UTF-8 BOM before the name on the first line | Docker accepts it as `INNGEST_BASE_URL` (1 entry): same |

Limits: the daemon here is 29.9.2, the production hosts run their own version; the image's own `ENV` was not exercised; the prod container is never inspected by the deploy.
