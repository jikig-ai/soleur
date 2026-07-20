---
name: trigger-cron
description: "This skill should be used to fire an allowlisted cron manual-trigger on demand via POST /api/internal/trigger-cron, without SSH. Reads the secret read-only from Doppler, lists allowlisted events, supports optional event data and a dry-run."
---

# trigger-cron

Fires a `cron/<name>.manual-trigger` event on demand by POSTing to the internal
trigger route `POST /api/internal/trigger-cron` — the no-SSH replacement for the
on-host `inngest send` loopback path (#4734, #4742). Use this instead of SSH-ing
to the Hetzner box whenever a cron needs an on-demand run.

## When to use

- Re-running a probe/audit cron after fixing a secret (e.g. `cron/oauth-probe.manual-trigger`).
- Targeting a specific issue with the bug-fixer (`cron/bug-fixer.manual-trigger`
  with `data: { issue_number: N }`).
- Any operator/agent "fire this cron now" need — see the runbooks
  `knowledge-base/engineering/operations/runbooks/inngest-server.md` and
  `oauth-probe-failure.md`.

The cron CRUD set: `soleur:schedule` (Create), `soleur:cron-list` (Read),
`soleur:cron-delete` (Delete), **`soleur:trigger-cron` (Run-now — this)**.

## How it works

The route authenticates a fail-closed shared secret
(`INNGEST_MANUAL_TRIGGER_SECRET`, Doppler-provisioned) via a `Bearer` header,
validates the event against the allowlist derived from `EXPECTED_CRON_FUNCTIONS`
(`apps/web-platform/server/inngest/cron-manifest.ts`), and dispatches the event
through the app's wired Inngest client. Route-controlled keys (`trigger`, `at`)
are stamped server-side and CANNOT be overridden by caller `data`.

## Usage

The wrapper script is [scripts/trigger.sh](./scripts/trigger.sh):

```bash
# List the allowlisted manual-trigger events (sourced from the cron manifest).
${CLAUDE_PLUGIN_ROOT:-plugins/soleur}/skills/trigger-cron/scripts/trigger.sh --list

# Dry-run: print the curl without firing.
${CLAUDE_PLUGIN_ROOT:-plugins/soleur}/skills/trigger-cron/scripts/trigger.sh \
  --event cron/bug-fixer.manual-trigger --data '{"issue_number":4383}' --dry-run

# Fire (default config: prd).
${CLAUDE_PLUGIN_ROOT:-plugins/soleur}/skills/trigger-cron/scripts/trigger.sh \
  --event cron/workspace-sync-health.manual-trigger
```

### Flags

| Flag | Meaning |
|---|---|
| `--list` | Print the allowlisted events (from `cron-manifest.ts`) and exit. |
| `--event <name>` | The `cron/<name>.manual-trigger` event to fire (validated against the allowlist). |
| `--data '<json>'` | Optional per-cron `event.data` (must be a JSON object). Forwarded verbatim; the route stamps `trigger`/`at` over it. |
| `--config prd\|dev` | Doppler config to read the secret from (default `prd`). |
| `--dry-run` | Print the curl invocation without firing. |

## Sharp edges

- **Run from a worktree, never the bare-repo root.** `trigger.sh` locates the allowlist via the repo's `cron-manifest.ts` and fails on a bare repo (`not inside a git repo (cannot locate cron-manifest.ts)`). From a bare-root session, `cd` into any `.worktrees/<feature>/` first (or run the script by absolute path while CWD is inside a worktree) — the firing curl is server-side-allowlist-validated, so the worktree's local manifest version does not affect correctness. See `knowledge-base/project/learnings/integration-issues/2026-06-05-cloud-task-silence-per-producer-triage-and-handler-fallback.md`.
- **Read-only secret access.** The script reads `INNGEST_MANUAL_TRIGGER_SECRET`
  via `doppler secrets get … --plain` only — it never writes or mutates the
  secret, never echoes or logs it, and `unset`s the token immediately after the
  `curl` call. The token is passed as the `curl` `Authorization` header argument
  (same exposure profile as every other operator `curl` in the runbooks); the
  `--dry-run` path prints the command form with `$TOKEN` unexpanded, so it never
  mints or reveals the secret.
- **The route is a dumb forwarder.** Per-cron field validation (e.g.
  `issue_number` positive-integer) lives in each cron, not the route. A bad
  `--data` shape that the route accepts (any plain object) may still be rejected
  cron-side with a Sentry fallback.
- **Allowlist is the blast-radius bound.** A non-allowlisted event returns 400.
  The allowlist auto-tracks `cron-*.ts` via `EXPECTED_CRON_FUNCTIONS` — there is
  no second hand-maintained list.
- **Mutating crons spend budget / open PRs / post publicly.** `cron/bug-fixer.manual-trigger`
  opens a PR; content/competitive/growth crons spend API budget;
  `cron/weekly-release-digest.manual-trigger` POSTS a digest to the public
  community `#releases` channel (no dry-run mode — every fire publishes). Use
  `--dry-run` first; never smoke-test a mutating cron post-merge — use a
  data-free, side-effect-light event like
  `cron/workspace-sync-health.manual-trigger`. (The digest's one-time
  post-merge verification fire per #5080 plan Phase 6.2 was the sanctioned
  launch post, not a precedent.)
