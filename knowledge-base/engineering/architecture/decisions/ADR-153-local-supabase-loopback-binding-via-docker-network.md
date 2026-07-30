# ADR-153 — Bind the local Supabase stack to loopback via a dedicated Docker network

- **Status:** Accepted
- **Date:** 2026-07-30
- **Issue:** #7081
- **Related:** [ADR-111](./ADR-111-runtime-authz-rls-fuzz-harness.md) (the RLS-fuzz harness whose
  disposable local stack this binds), `apps/web-platform/scripts/supabase-local.sh` (the wrapper),
  `apps/web-platform/supabase/config.toml` (where a reader will look first, and find only a pointer)

> **Ordinal.** ADR-153 is the next free ordinal against `origin/main` (highest existing is ADR-152),
> re-verified at `/work` time. Provisional until `/ship` re-checks at merge.

## Context

The local Supabase dev stack for `apps/web-platform` published **every** service on all
interfaces. Measured on the founder's laptop 2026-07-30 while auditing an unrelated incident:

| Port | Service | Reachable on the LAN IP |
|---|---|---|
| 54321 | Kong API gateway | yes |
| **54322** | **Postgres** | **yes** |
| **54323** | **Studio** (unauthenticated DB admin UI) | **yes** |
| 54324 | Inbucket (mail catcher) | yes |
| 54327 | Analytics / Logflare | yes |

Confirmed by direct TCP connect to `192.168.1.142`, not merely by reading `ss` output. The gate
built in this ADR reports **10 of 10 published bindings across 11 containers off-loopback**, on
both `0.0.0.0` **and** `::`.

This is Docker's default publish behaviour via `supabase start` — not an attacker artifact. The
host forensic sweep that surfaced it found no implant or persistence. But a developer laptop joins
untrusted networks, and local dev credentials are well-known defaults, so an unauthenticated
database admin UI and an open Postgres port travel with it.

## Decision

**Start the stack through `apps/web-platform/scripts/supabase-local.sh`, which attaches it to a
dedicated Docker network carrying `com.docker.network.bridge.host_binding_ipv4=127.0.0.1`.**

Three layers:

1. **Wrapper (prevention).** `supabase-local.sh` ensures the network exists *with the option*
   — verified by VALUE, not mere existence, because a pre-existing same-name network without it
   would silently publish on `0.0.0.0`. It then passes `--network-id` to the CLI, placed **before**
   `"$@"` so subcommands using `--` passthrough still parse. Exposed via `npm run db:start` etc.
2. **CI (detection).** `rls-authz-fuzz.yml` starts via the wrapper and runs
   `supabase-local.sh assert` **before** the bootstrap step, so a mis-bound runner is never seeded
   with fixture data. Both script paths were added to the workflow's `paths:` filter — without
   that, a PR editing them would have run nothing.
3. **SessionStart hook (tripwire).** `.claude/hooks/supabase-loopback-warn.sh` warns loudly if a
   stack is up and off-loopback — catching the case where someone bypassed the wrapper with a bare
   `supabase start`. Advisory only; it exits 0 unconditionally and never blocks a session.

## Why not `config.toml`

**There is no bind-address setting.** This was established six independent ways, because the
obvious rebuttal ("just set it in config") had to be closed properly:

1. The **official config reference** documents no `bind_address`/`listen_address`/`host` at any
   level — only `port` keys, plus `realtime.ip_version`, which selects IPv4-vs-IPv6 *protocol*,
   not a bind address.
2. **The repo's own config**, read in full: every section carries `port` and no listener host key.
   (Precision: a literal `grep` does find one `host` key — `# host = "smtp.sendgrid.net"`,
   commented, under `[auth.email.smtp]`. That is an **outbound SMTP relay**, not a listener.)
3. **`supabase start --help`** (v2.84.2, matching the CI pin; re-verified unchanged at v2.110.0)
   lists no bind flag. The relevant global flag is `--network-id`.
4. **CLI source at the pinned tag:** `internal/utils/docker.go` never sets `HostIP` on port
   bindings, so Docker's default always applies. At v2.110.0 the equivalent
   (`apps/cli-go/internal/db/start/start.go`) is still `PortBindings` with no `HostIP`; a repo-wide
   search for `HostIP` returns **zero** hits.
5. **Upgrading would not help — checked, not assumed.** The 100 most recent releases
   (through `v2.111.0-beta.14`) were queried and filtered for bind/host/loopback/listen terms.
   One match, unrelated ("pg-delta selinux bind mount").
6. **Upstream built it and rejected it on policy.** PR
   [supabase/cli#4613](https://github.com/supabase/cli/pull/4613) — *"Proposal to bind CLI services
   to local IPs (while being configurable)"* — was **closed unmerged** on 2025-12-23. Maintainer
   `@sweatybridge`: binding to localhost by default is *"the decision is no… it would be a breaking
   change to revert this for existing users"*, and *"we should lean on **docker network** because
   it's more robust than adding our own custom networking config."*

**Item 6 is why this wrapper is permanent, not provisional.** The maintainer's prescribed
alternative *is* this design. There is no upstream contribution left to attempt and no CLI upgrade
to wait for.

`config.toml` carries a comment at the port declarations pointing here, because that is the first
place a reader will look — and a `bind_address`-looking line added there would silently do nothing.

### The decoy

`SUPABASE_SERVICES_HOSTNAME` (added after 2.84.2) reads like a bind knob and will be found by
anyone grepping newer source. It is **dial-side only** — it changes which host the CLI *connects
to* for health checks in dev-container setups. It does not affect what containers bind to. Recorded
here so a future session does not "simplify" the wrapper away.

## Measured, not assumed

Sources disagreed on whether an **IPv4-named** option leaves the IPv6 `[::]` wildcard in place —
which decides whether this is a complete fix or a half fix. It was measured with a throwaway
network and container:

```text
$ docker network inspect probe-loopback-net --format '{{json .Options}}'
{"com.docker.network.bridge.host_binding_ipv4":"127.0.0.1"}
$ docker ps --format '{{.Ports}}'
127.0.0.1:65432->1234/tcp
$ ss -tlnp | grep 65432
LISTEN 0 4096  127.0.0.1:65432  0.0.0.0:*
```

A single loopback socket — no `0.0.0.0`, and decisively no `[::]`. Docker Engine 29.4.3, rootful.

## Consequences

- **Rootful Linux Docker only.** The `host_binding_ipv4` bridge option is a bridge-driver feature;
  Docker Desktop and rootless setups differ. The gate is the safety net there: it reports the real
  binding regardless of how the stack was started.
- **The gate reads `NetworkSettings.Ports`, never `HostConfig.PortBindings`.** `PortBindings`
  reports an **empty** `HostIp` for *both* the wildcard and the loopback-bound state, so a gate
  reading it cannot distinguish a fixed stack from a broken one. This is a real trap: the
  implementation initially treated an empty `HostIp` as "publishes nothing" and silently skipped
  the exact state the gate exists to catch. Pinned by a regression test.
- **`assert` has three exits, not two:** `0` ok-or-no-stack, `1` exposed, `2` docker unreachable.
  An unreachable daemon is **UNKNOWN**, never conflated with safe — an empty query is not evidence
  of absence.
- Developers must use `npm run db:*` rather than bare `supabase`. The wrapper is a general
  passthrough (`db diff`, `db reset`, `migration`, `gen types`) so there is one path, not two.
- The stack should be **stopped when not in use**; loopback binding reduces blast radius, it does
  not eliminate the local surface.
