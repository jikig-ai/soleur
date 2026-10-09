---
module: web-platform deploy pipeline (apps/web-platform/infra/ci-deploy.sh)
date: 2026-10-09
problem_type: security_issue
component: cross_cutting_concern
symptoms:
  - "a docker exec'd probe suite inherits the canary container's FULL prd env-file — every secret Config.Env carries"
  - "an adversarial test suite that probes parent-environ exfil channels is handed live credentials as the channel's contents"
  - "any output the exec'd process emits into a journald/Sentry surface can carry prd values"
root_cause: code
resolution_type: fix
severity: high
issue: 2640
pr: 9809
tags: [docker-exec, env-leak, canary, sandbox, isolation, secrets, env-i]
---

# `docker exec` inherits the canary's full Config.Env — a probe that spawns adversarial sandboxes needs `env -i`

## Problem

`run_workspace_isolation_probe` originally ran the cross-workspace isolation
suite inside the canary as:

```
docker exec -w /app -e CI=true -e SOLEUR_ISOLATION_* soleur-web-platform-canary vitest run ...
```

`docker -e` is **additive only** — the exec'd process still inherits the
canary's `Config.Env`, which is the full `--env-file` the container was
launched with (`GITHUB_APP_PRIVATE_KEY`, `ANTHROPIC_API_KEY`, DB URLs, Doppler
tokens — every prd secret).

That is not a cosmetic detail for this particular suite: it spawns inner
bwrap sandboxes and measures whether *parent-process data* crosses the
workspace boundary (`fixtures.ts` spawns children with
`env: opts.env ?? process.env`; FR7 seeds a sentinel env var and has a sibling
sandbox attempt `/proc/<pid>/environ` reads). The channel under test was
carrying real credential material: on the regression the probe exists to
detect, a successful environ leak would have dumped live secrets into the
captured output — which the probe then wanted to fold into `reason` for
journald/Sentry triage (the P2 pair was: scrub env first, then surface
diagnostics; surfacing first would have been the leak).

## The fix pattern

Run the exec'd command under `/usr/bin/env -i` and pass the needed knobs as
`env`'s own assignments (the `github_app_key_canary_check` precedent, same
file):

```
timeout <cap> docker exec -w /app soleur-web-platform-canary \
  /usr/bin/env -i PATH=/usr/local/bin:/usr/bin:/bin HOME=/tmp \
  CI=true SOLEUR_ISOLATION_TEST_HOST=1 SOLEUR_ISOLATION_TIERS=direct SOLEUR_ISOLATION_IN_IMAGE=1 \
  /usr/local/bin/vitest run --config test/vitest.canary.config.ts
```

`env -i` constructs a clean environ; `-e` flags cannot subtract, only
override — so the knobs move inside env's argument list. PATH must cover
`/usr/local/bin` (the vitest bin's `#!/usr/bin/env node` shebang resolves
there) and HOME must be writable (`/tmp` — the suite runs as `soleur`).

## Residuals worth knowing

- `env -i` clears the *exec'd process's* environ; `/proc/1/environ` inside the
  container still holds `Config.Env` (same-uid readable). Nothing in the
  suite reads it, and the `_cred_err_tail` sanitizer's env-value redaction
  arm covers anything that slips into `reason` — defense in depth, not sole
  control.
- Scrubbing also drops runtime tunables (`NODE_OPTIONS` heap caps). Loud
  failure direction: OOM → rc 137 → red verdict → page.

## Generalization

Any `docker exec` into a container launched with `--env-file` whose exec'd
process's output (or child processes' attack surface) touches an observable
surface — journald, Sentry, state files, tenant-visible sandboxes — should
run under `env -i`, and diagnostic output should be surfaced through
`_cred_err_tail`, never raw.
