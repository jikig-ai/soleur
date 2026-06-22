---
title: "inngest secrets via env not argv + non-secret durable-detection sentinel swap"
date: 2026-06-18
category: security-issues
module: apps/web-platform/infra
tags: [inngest, systemd, secrets, doppler, proc-cmdline, drift-guard, terraform]
ref: 5560
---

# Learning: deliver process secrets via environment, not argv — and swap the detection signal to a non-secret sentinel

## Problem

inngest-server's systemd `ExecStart` (written by `inngest-bootstrap.sh`) expanded four
Doppler-injected secrets (`INNGEST_POSTGRES_URI`, `INNGEST_REDIS_PASSWORD`,
`INNGEST_SIGNING_KEY`, `INNGEST_EVENT_KEY`) into the `inngest start` **argv** via
`doppler run … bash -c '… --postgres-uri "$X" --signing-key "$Y" …'`. The resolved
values land in `/proc/<pid>/cmdline` (mode `0444`, world-readable) — harvestable by any
local process with `ps -eo args | grep inngest`. On a host that also runs
user-influenced agent code, that is a real cross-tenant credential-exposure surface.

## Solution

Two coupled moves:

1. **argv → environment.** `inngest start` reads all four secrets from env vars
   (`INNGEST_POSTGRES_URI`, `INNGEST_REDIS_URI`, `INNGEST_SIGNING_KEY`,
   `INNGEST_EVENT_KEY` — verified against the official self-hosting docs). The
   `doppler run` wrapper already injects three by name; only `INNGEST_REDIS_URI` is
   constructed (`export INNGEST_REDIS_URI="redis://:${INNGEST_REDIS_PASSWORD}@…"`) and
   the signing key is re-exported stripped of its `signkey-prod-` prefix. The bash `-c`
   script `exec`s inngest, so the child inherits the env (`/proc/<pid>/environ`, mode
   `0400`, owner-only) and carries **no** secret on argv. The bash process's own cmdline
   shows only `${VAR}` *references*, never expanded values (bash does not rewrite its own
   argv on expansion).
2. **Detection-signal swap.** Removing `--postgres-uri`/`--redis-uri` from argv broke
   every durable-backend detector that grepped the ExecStart for those substrings (3
   runtime parsers: `ci-deploy.sh` verify-health + re-derivation, `inngest-inventory.sh`
   classifier, `inngest-wiped-volume-verify.sh` data-safety wipe guard). The fix re-keys
   detection on the **non-secret** `--postgres-max-open-conns` flag, which the bootstrap
   writes on argv *only* in the durable branch (present iff durable).

## Key Insight

- **A secret belongs in the environment, never argv.** `/proc/<pid>/cmdline` is
  world-readable (`0444`); `/proc/<pid>/environ` is owner-only (`0400`). When a CLI
  supports both flag and env-var forms for a secret, always choose env. The bash `-c`
  literal that *does* appear in cmdline must contain only unexpanded `${VAR}` references
  + an `exec` so no child re-exposes the resolved value.
- **When you move a secret off argv, the env var is still present in the conditional
  branch that must NOT use it.** Doppler injects `INNGEST_POSTGRES_URI` in *both* the
  durable and the SQLite-only fail-safe scope, so the fail-safe must `unset
  INNGEST_POSTGRES_URI` or inngest auto-reads it from env and connects to Postgres —
  silently defeating the fail-safe. Moving a flag to env converts "absent flag" into
  "present env var you must actively suppress."
- **If a detection signal IS the thing you're removing, pick a non-secret co-located
  marker that's present iff the condition holds.** Here `--postgres-max-open-conns` (a
  pool-tuning flag already written only in the durable branch) is the natural sentinel —
  zero new state, no marker file. Document the elevation at the definition site: the one
  residual a rename-only drift-guard can't catch is **prefix-promotion** (moving the
  sentinel into the shared prefix would make it present in both branches → SQLite-only
  misdetected as durable → the wipe guard destroys real state).
- **`exec` in a multi-statement `bash -c` is load-bearing**: without it, inngest runs as
  a bash *child* and SIGTERM on `systemctl stop`/restart hits bash, breaking
  `Type=simple` drain + `inngest pause` semantics.

## Session Errors

1. **Planning subagent crashed mid-Session-Summary** (connection closed, 29 tool calls in). **Recovery:** the one-shot fallback ran `soleur:plan` inline after confirming no partial artifact was on disk. **Prevention:** none needed — the documented fallback worked; transient API error, one-off.
2. **Plan Write blocked by the IaC-routing hook** (systemctl/operator prose). **Recovery:** added `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->` after confirming the prose described EXISTING bootstrap behavior, not a new manual step. **Prevention:** when a plan narrates existing IaC-driven `systemctl`/restart behavior, expect the gate and pre-emptively add the ack comment with a rationale.
3. **Plan Write blocked — wrote to the bare-root absolute path** instead of the worktree path. **Recovery:** re-issued the Write against the worktree-absolute path. **Prevention:** already hook-enforced (`hr-when-in-a-worktree-never-read-from-bare`); from a worktree always use worktree-absolute paths for Write/Edit.
4. **`git stash list` blocked by hook.** **Recovery:** dropped the `git stash list` and re-ran the rest. **Prevention:** the Phase 0.5 pre-flight already prescribes `git rev-parse --verify --quiet refs/stash` instead of `git stash list`; use that.
5. **Edit "file not read yet" after rebase.** **Recovery:** re-read the file then edited. **Prevention:** expected — re-Read a file after a rebase before editing.
6. **Plan's "7 consumers" was actually 8** — sibling PR #5553 merged a 3rd durable-detection parser (`inngest-inventory.sh` + a drift-guard) between plan-write and /work. **Recovery:** the Phase-0.5 `rebase origin/main` + the /work-time cross-consumer grep (`hr-type-widening-cross-consumer-grep`) surfaced the 8th consumer; folded it into the sweep inline. **Prevention:** already covered by `2026-05-20-rebase-before-applying-agents-md-plan-edits` + the sweep-class-grep-enumerated rule — this is a **confirming instance** for the durable-detection-parser family: plan-enumerated consumer counts go stale when a sibling lands a coupled subsystem mid-flight; the rebase + grep are the load-bearing recovery, not the plan's count.
7. **3 pre-existing test failures** (2 doppler-CLI env mocks in `ci-deploy.test.sh`, 1 pin-freshness drift in `cloud-init-inngest-bootstrap.test.sh`). **Recovery:** confirmed pre-existing by running the origin/main versions in isolation. **Prevention:** per `wg-when-tests-fail-and-are-confirmed-pre`, verify against origin/main before treating a failure as a regression — both were env/time-dependent, not code.

## Post-ship discovery: rotating a `doppler_secret`-backed credential needs a DUAL `-replace`, not a lone `taint` (#5575)

This learning's plan prescribed (AC9) rotating `INNGEST_REDIS_PASSWORD` via
`terraform taint random_password.inngest_redis_password_prd` (or a lone
`-replace` of just the `random_password`). **That is an INCOMPLETE rotation.**

`doppler_secret.inngest_redis_password_prd` carries `lifecycle { ignore_changes
= [value] }`. `ignore_changes` applies to **updates**, not **creates**. So:

- A lone `taint`/`-replace` of `random_password` regenerates the value **in
  tfstate**, but on the next apply the `doppler_secret` is *updated* (not
  recreated) — and `ignore_changes=[value]` **suppresses that update**. Doppler
  (and therefore the running inngest, which reads the value from Doppler) keeps
  the **OLD** password. The exposed credential is NOT actually rotated.

**Correct method — replace BOTH resources together** so the `doppler_secret` is
*recreated* (create writes the new value, bypassing `ignore_changes`):

```bash
terraform apply -replace=random_password.inngest_redis_password_prd \
                -replace=doppler_secret.inngest_redis_password_prd
# then redeploy inngest so it loads the new value.
```

The `INNGEST_POSTGRES_URI` rotation is a *separate* action (it is out-of-band,
NOT a `doppler_secret` resource): reset the Supabase project DB password, then
`doppler secrets set INNGEST_POSTGRES_URI` (stdin) — an in-place **update**,
which is fine because no `ignore_changes` resource suppresses it.

**Verification signature (Doppler prd activity log):** a correct dual-`-replace`
shows a `1 removed` + `1 added` pair (the `doppler_secret` destroy+recreate); the
Postgres URI re-set shows `1 updated`. A rotation that shows only `1 updated` for
the Redis secret (or nothing) used the incomplete lone-`taint` path and did NOT
change the live password. (This is how #5560's rotation was verified complete.)

**Generalizable rule:** any `doppler_secret` (or any provider resource) with
`ignore_changes=[value]` cannot be rotated by changing only its *source* value —
you must `-replace` the resource that carries `ignore_changes` so the new value
lands via *create*. Caught post-ship (#5575) and fixed in the `inngest.tf`
rotation comment; this addendum makes it searchable beyond that one file.

## Tags
category: security-issues
module: apps/web-platform/infra
