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
  `knowledge-base/engineering/ops/runbooks/inngest-server.md` and
  `oauth-probe-failure.md`.

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
plugins/soleur/skills/trigger-cron/scripts/trigger.sh --list

# Dry-run: print the curl without firing.
plugins/soleur/skills/trigger-cron/scripts/trigger.sh \
  --event cron/bug-fixer.manual-trigger --data '{"issue_number":4383}' --dry-run

# Fire (default config: prd).
plugins/soleur/skills/trigger-cron/scripts/trigger.sh \
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

- **Read-only secret access.** The script reads `INNGEST_MANUAL_TRIGGER_SECRET`
  via `doppler secrets get … --plain` only — it never writes or mutates the
  secret, and never echoes it (the token is piped straight into the `curl`
  Authorization header).
- **The route is a dumb forwarder.** Per-cron field validation (e.g.
  `issue_number` positive-integer) lives in each cron, not the route. A bad
  `--data` shape that the route accepts (any plain object) may still be rejected
  cron-side with a Sentry fallback.
- **Allowlist is the blast-radius bound.** A non-allowlisted event returns 400.
  The allowlist auto-tracks `cron-*.ts` via `EXPECTED_CRON_FUNCTIONS` — there is
  no second hand-maintained list.
- **Mutating crons spend budget / open PRs.** `cron/bug-fixer.manual-trigger`
  opens a PR; content/competitive/growth crons spend API budget. Use `--dry-run`
  first; never smoke-test a mutating cron post-merge — use a data-free,
  side-effect-light event like `cron/workspace-sync-health.manual-trigger`.
