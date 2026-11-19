# Spec — feat-one-shot-12742-public-sdk-url-poll

- **Issue:** #12742 item 1 (remedy (c) follow-up of #10538 / #10479)
- **Branch:** `feat-one-shot-12742-public-sdk-url-poll` (draft PR #12876)
- **Plan:** `knowledge-base/project/plans/2026-11-17-feat-inngest-sdk-url-sync-evidence-strict-preflight-plan.md`
- **Tasks:** `tasks.md` | **Decisions:** `decision-challenges.md`

## Summary

Merge-before-replace safety work for the public Inngest `sdk_url` poll:

1. The `SOLEUR_INNGEST_SERVER_PROBE` row gains `sdk_sync` (last-attempt result from the server's own
   `apps { url error }` poll state) and `sdk_app_url` (sanitized stored URLs) so a stale non-zero
   Postgres registry can no longer read as healthy; `probe_schema` bumps 9 → 10.
2. `image_ref`/`cli_version` are sanitized to `[A-Za-z0-9_:.@/+-]` so a free-text value containing
   ` registry_fns=5 ` cannot mask a real `registry_fns=0` (CTO F4(ii); sanitize option chosen).
3. The `PUBLIC-SDK-URL`/`PUBLIC-SDK-URL-BIRTH` typed-confirm steps on `inngest_host` and
   `inngest_host_replace` are replaced by a fail-closed `tests/scripts/lib/
   inngest-public-sdk-url-preflight.sh` that passes only when the last enabled Cloudflare
   config-settings rule matching `app.soleur.ai` has `ssl=strict` (via
   `cloudflare-readonly.sh config-entrypoint`); all confirmation-token recipes are swept; the B10
   parity tests are repointed at the new guard.
4. Items 2–9 of #12742 remain out of scope (production acts / separate PRs).

## Constraints

- Workflow byte budget: 489,995 / 490,000 — net-negative edits only.
- `inputs.confirm` is shared with ~10 other targets; only the two inngest jobs stop consuming it.
- Every new guard ships with mutation-row evidence; assertion floors stay honest.
- No GQL error text, tokens, or raw API bodies may reach journald/Better Stack/GHA logs.
- All infrastructure changes route through IaC/PR gates — no manual SSH/dashboard steps.
