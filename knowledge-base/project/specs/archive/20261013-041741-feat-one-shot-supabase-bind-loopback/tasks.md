<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
  Phase 2.8 reviewed. This feature provisions no infrastructure: no server, host, vendor account,
  DNS record, TLS cert, secret, packet-filter rule, systemd unit, or cron job; no .tf, cloud-init,
  or docker-compose file is touched. The single `systemctl restart docker` below is a READ-ONLY
  PROBE on the developer's own workstation (probe P2), verifying that the loopback binding survives
  a daemon restart — because all 11 containers run `restart: unless-stopped`, making dockerd the
  dominant publish path. It configures nothing. See the plan's ## Infrastructure (IaC) section.
-->

# Tasks — bind the local Supabase stack to loopback

Derived from
[`knowledge-base/project/plans/2026-07-30-fix-supabase-local-stack-loopback-bind-plan.md`](../../plans/2026-07-30-fix-supabase-local-stack-loopback-bind-plan.md)
(v2, post 7-agent review).

`lane: cross-domain` · `brand_survival_threshold: single-user incident` · `requires_cpo_signoff: true`
(CPO signed off with conditions C1–C6, all folded in).

---

## Phase 0 — Immediate mitigation + premise probes

- [ ] **0.1 STOP THE STACK NOW.** `supabase stop`. Closes 100% of a three-week-old live exposure at
      zero cost — nothing depends on this stack. Record the timestamp; it goes in the PR body as the
      exposure-close time. **Do this before any other task.**
- [ ] 0.2 Confirm the CLI on PATH is `2.84.2` (matches the `supabase/setup-cli` pin in
      `.github/workflows/rls-authz-fuzz.yml`). A version skew invalidates the source citations.
- [ ] 0.3 Confirm `apps/web-platform/package.json` has no existing `db:*` script collision.
- [ ] 0.4 Derive the project id from `apps/web-platform/supabase/config.toml` (`project_id`) — do
      not hardcode `web-platform` in more than one place.
- [ ] 0.5 Set a `trap` so Phase 0 always exits with the stack **stopped or loopback-bound**. Never
      run an unscoped `docker network prune`; scope every removal by name.
- [ ] **0.6 Probe P1 — does the option hold on the real stack?** Recreate the network with
      `com.docker.network.bridge.host_binding_ipv4=127.0.0.1`, start, read `NetworkSettings.Ports`.
      Must show `127.0.0.1` and **no** `::`. *Failure ⇒ the mechanism is wrong: halt, file an
      `action-required` issue naming CPO as decision owner, re-enter planning. Do not silently fall
      back to a root-level design CPO sign-off has not covered.*
- [ ] **0.7 Probe P2 — does the binding survive a daemon restart?** Restart the Docker daemon, then
      re-read `NetworkSettings.Ports`. Must remain loopback-only. **This is the dominant publish
      path** — all 11 containers are `restart: unless-stopped` and docker is enabled at boot.
      *Failure ⇒ the fix does not survive a reboot; the design changes.*
- [ ] **0.8 Probe P3 — does bare `supabase start` reuse the network, and does it re-label it?**
      Reuses AND leaves it unlabelled ⇒ Layer 2 works. Anything else ⇒ **drop Layer 2, no further
      deliberation** (CPO condition C4). Layers 1 and 3 are unaffected either way.
- [ ] 0.9 Record P1–P3 outcomes for the PR body.

## Phase 1 — RED: the gate, proven to fail

- [ ] 1.1 Create `apps/web-platform/scripts/supabase-local.sh` with an `assert` subcommand:
  - [ ] enumerate containers by label **key presence**
        (`docker ps --filter label=com.supabase.cli.project`) — not `key=value`, so a future second
        project is genuinely covered
  - [ ] read **`NetworkSettings.Ports`** — never `HostConfig.PortBindings`, which reads `HostIp: ""`
        identically before and after the fix
  - [ ] treat *published* as a **non-null, non-empty** binding array (6 of 11 containers return
        `"8080/tcp": null`)
  - [ ] derive the port set **dynamically** — never a `5432[0-9]` regex (would miss 8083)
  - [ ] probe with bash `/dev/tcp` (guaranteed present; `nc` is not)
  - [ ] include **link-local IPv6** (`ip -o addr show` without `scope global`)
  - [ ] emit three distinguishable conditions: `EXPOSED`, `NO_CONTAINERS`, `DOCKER_ERROR`
  - [ ] always print `enumerated N containers / M published ports` and
        `probed K non-loopback addresses` — an empty enumeration must **fail**, never pass
  - [ ] every failure path names the exact remediation command
  - [ ] declare `docker` / `jq` dependencies explicitly
- [ ] 1.2 Create `apps/web-platform/scripts/supabase-local.test.sh` using the repo's PATH-shimmed
      fake-binary convention (see `postgrest-reload-schema.test.sh`, which shims `curl`). Fixtures:
      wildcard IPv4, wildcard `::`, loopback-good, **null port entries**, **zero containers**,
      docker-unreachable, and the `HostConfig.PortBindings` proxy trap.
      **Must pass with no Docker and no stack** — `scripts/test-all.sh:560` globs
      `apps/web-platform/scripts/*.test.sh`, so it runs on every full-suite run with zero wiring.
- [ ] 1.3 Run the gate against the exposed stack in a short **attended** window. It MUST fail.
      Capture output as RED evidence, then return the machine to the safe state.

## Phase 2 — GREEN: the wrapper

- [ ] 2.1 Add the ensure/passthrough logic to `supabase-local.sh`:
  - [ ] default behaviour is a **general passthrough**: `exec supabase --network-id "$NET" "$@"`
        with the flag **before** `"$@"` (otherwise `--` passthrough subcommands break). Covers
        `start`/`stop`/`status` *and* `db diff`/`db reset`/`db lint`/`migration`/`gen types`.
  - [ ] ensure-condition is **all three** of: option **value equality** with `127.0.0.1`; the
        `com.supabase.cli.project` label **absent** (the CLI creates it labelled, and
        `supabase stop` prunes labelled networks); `Driver == "bridge"`.
  - [ ] **abort** if `docker network rm` or `docker network create` fails — never fall through to
        `supabase start` on a surviving wildcard network.
  - [ ] pin the subnet on recreate (avoid a 172.17–172.31 VPN/corporate-route collision).
  - [ ] `#!/usr/bin/env bash`, `set -euo pipefail`, `--help`.
- [ ] 2.2 Migrate the live stack via the wrapper; re-run the gate — MUST pass.

## Phase 3 — Wire the safe path

- [ ] 3.1 **Layer 3 detector:** wire `supabase-local.sh assert` into the existing SessionStart hook
      (`.claude/hooks/`). Warn loudly if EXPOSED; silent when clean or when no stack is running;
      never block the session.
- [ ] 3.2 `apps/web-platform/package.json`: `db:start`, `db:stop`, `db:status`,
      `db:assert-loopback`, `db:cli` (passthrough).
- [ ] 3.3 `.github/workflows/rls-authz-fuzz.yml`: start via the wrapper; add an
      `Assert loopback-only binding` step after `Start local Supabase stack` and before
      `Bootstrap migration-tracking table (content_sha shim)`; **add both new script paths to the
      `paths:` filter** (neither is covered today).
- [ ] 3.4 `apps/web-platform/README.md`: new "Local Supabase stack (RLS-fuzz substrate)" section —
      purpose; the wrapper as the only documented path **including `db diff`/`db reset`/
      `migration`**; **stop it when not in use** (CPO C6); the rootful-Linux-only caveat;
      synthesized-fixtures-only; pointer to ADR-153.
- [ ] 3.5 `apps/web-platform/supabase/config.toml`: comment only at the port declarations — bind
      address is not configurable here; see the wrapper + ADR-153.

## Phase 4 — Architecture record

- [ ] 4.1 Write a **terse** ADR under
      `knowledge-base/engineering/architecture/decisions/` (provisional ordinal **ADR-153**;
      `/ship` re-verifies against `origin/main`). Content: the six-way justification **including
      PR supabase/cli#4613's rejection and the maintainer's docker-network prescription** (why this
      workaround is permanent, not provisional); the three-control structure and which one is the
      boundary; the value-equality + label-absence + bridge-driver ensure-condition; the
      `NetworkSettings.Ports` rule; the `unless-stopped` republish path; the
      `SUPABASE_SERVICES_HOSTNAME` decoy; the measured dual-stack result; the limits; alternatives
      C/D/E. **Plus a re-evaluation trigger:** if the CLI pin moves to a v3 line, re-check whether
      the localhost default landed — if it did, delete the wrapper and Layer 2 and keep only the gate.
- [ ] 4.2 Add a one-line `Related: ADR-153` cross-reference to
      `ADR-111-runtime-authz-rls-fuzz-harness.md`.
- [ ] 4.3 If the ordinal is renumbered, sweep the whole feature's artifacts for the old value
      (`grep -rn 'ADR-153' knowledge-base/project/{plans,specs}/`).

## Phase 5 — Verification

- [ ] 5.1 Execute and capture every acceptance criterion AC1–AC10.
- [ ] 5.2 `cd apps/web-platform && bun run test:rls-fuzz` — green against the loopback-bound stack.
      **Not** bare `vitest` (not on PATH).
- [ ] 5.3 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`. **Not** `npm run -w …` (the
      repo root declares no `workspaces`).
- [ ] 5.4 `bash scripts/test-all.sh` — confirms the new `*.test.sh` passes with no Docker present.
- [ ] 5.5 Build the AC3 reachability matrix (every published port × every non-loopback address,
      including link-local IPv6) for the PR body.

## Phase 6 — Deferrals

- [ ] 6.1 File: **host-wide Docker publish hardening** (daemon `{"ip":"127.0.0.1"}` + optional
      `DOCKER-USER` rules). `type/security`, `domain/engineering`, `priority/p2-medium`, milestone
      `Post-MVP / Later`. Trigger: next planned untrusted-network trip **or 2026-09-30**.
- [ ] 6.2 File: **verify the TypeScript CLI honours `--network-id` before any pin bump**.
      `type/chore`, `domain/engineering`, `priority/p2-medium`, milestone `Post-MVP / Later`.
      Trigger: any PR moving the `supabase/setup-cli` pin off 2.84.2.
- [ ] 6.3 File: **reduce the started service set** (`-x studio,inbucket,logflare,vector`).
      `type/chore`, `domain/engineering`, `priority/p3-low`, milestone `Post-MVP / Later`.
      Trigger: next ADR-111 substrate change **or 2026-09-30**.

## Phase 7 — Ship

- [ ] 7.1 PR body must carry: the §Step 0 exposure-close timestamp; P1–P3 probe outcomes; the AC3
      dual-stack reachability matrix; the CLI-limitation statement with all citations (AC10);
      `git ls-files | grep -c 'supabase/config\.toml'` → `1`.
- [ ] 7.2 `ship` renders `decision-challenges.md` (UC-1, UC-2, UC-3) into the PR body and files the
      `action-required` issue.
- [ ] 7.3 Use `Closes #<n>` only for issues this PR actually resolves; the deferrals are `Ref`.
