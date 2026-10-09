---
title: Cross-workspace isolation canary probe — design note
type: runbook
date: 2026-10-09
owners: engineering/ops
applies_to: apps/web-platform/infra/ci-deploy.sh
related_issues: [1285, 2640, 9860]
---

# Cross-workspace isolation canary probe — design note

Issue #2640 asked for two decisions to be recorded: which image strategy carries
vitest into the canary, and whether the probe is a deploy-GATE or a deploy-REPORT.
This note is that record (the issue's AC 1), plus the two scoping decisions the
implementation surfaced: the suite tier filter and the `/sys` cgroup-visibility
trade-off from the paired #1285 change.

## Probe shape

`run_workspace_isolation_probe` in `apps/web-platform/infra/ci-deploy.sh` runs,
inside the canary container and before the prod swap:

```text
timeout <cap> docker exec -w /app soleur-web-platform-canary \
  /usr/bin/env -i PATH=/usr/local/bin:/usr/bin:/bin HOME=/tmp \
  CI=true SOLEUR_ISOLATION_TEST_HOST=1 SOLEUR_ISOLATION_TIERS=direct SOLEUR_ISOLATION_IN_IMAGE=1 \
  /usr/local/bin/vitest run --config test/vitest.canary.config.ts
```

`/usr/bin/env -i` is load-bearing, not style: `docker exec` inherits the
canary's full `Config.Env` (the prd env-file — `GITHUB_APP_PRIVATE_KEY`,
`ANTHROPIC_API_KEY`, …), and this suite deliberately spawns
adversarially-probed inner sandboxes whose parent env is the exfil channel
under test. Scrubbing (the `github_app_key_canary_check` precedent) means a
real isolation break cannot leak credential material, and the vitest line
folded into `reason` can never carry it.

`SOLEUR_ISOLATION_IN_IMAGE=1` is load-bearing, not decoration: inside the image
the PATH-resolved `bwrap` IS the deployed PATH shim (`/usr/local/bin/bwrap`)
and the repo-side shim path (`/app/infra/bwrap-shim/bwrap`) is never baked —
so **FR7b self-skips in-image**. That row needs a real-binary control arm plus
a symlink to the repo shim; without the flag it fails both arms and every
deploy would page `workspace_isolation_failed` (a permanently-zero soak).
Nothing is lost: FR7b's shim-splice property is pinned by
`test/bwrap-shim.test.ts` and the faithful-canary replay.

Verdicts, classified from the `docker exec` rc exactly as
`run_faithful_sandbox_canary` does: `pass` (0), `workspace_isolation_failed`
(other non-zero), `workspace_isolation_timeout` (124, host-side `timeout`),
`canary_infra_error` (125/126/127 — could not exec, e.g. a pre-tooling image).
Verdicts persist to `/mnt/data/ci-deploy-workspace-isolation.json`, surface as
`.workspace_isolation` on `/hooks/deploy-status`, log a `WORKSPACE_ISOLATION:`
journald line per run, and Sentry-page on `workspace_isolation_failed` /
`workspace_isolation_timeout` only. The operational contract lives in
`canary-probe-set.md` ("Cross-workspace isolation canary"); this file records the
*why*.

## Image strategy — single runner image (chosen)

The runner image gains a globally-installed vitest in the existing `cli-tools`
stage, plus a three-file test payload COPYed into the `runner` stage:

```dockerfile
RUN npm install -g vitest@4.1.11 --before=2026-08-19 --ignore-scripts
```

The `--before` bound follows the `likec4` convention in the same stage (the day
after vitest 4.1.11's publish date, 2026-08-18): the exact pin is fixed, the
floating transitive tree is bounded, and `--ignore-scripts` matches the existing
install mode. The Dockerfile pin is asserted equal to `package-lock.json`'s
resolved vitest by `test/dockerfile-vitest-version-pin.test.ts`, so the canary
runs the vitest the suite was authored against. The payload is
`test/sandbox-isolation.test.ts`, `test/helpers/sandbox-isolation-fixtures.ts`,
and `test/vitest.canary.config.ts` — each re-included from the `test/` prune by
an exact-path `.dockerignore` bang (never a `!test/` directory bang, which
cascades).

Rejected alternatives (from the issue's option list):

| Approach | Why rejected |
|---|---|
| Surgical `COPY` of `node_modules/vitest` + transitive deps | ~50+ packages to enumerate; a missed dep fails only at deploy time — the worst place |
| Canary-only image stage/tag or `Dockerfile.canary` | a second image doubles the sign/push/verify/freshness surface and weakens `canary == prod` |

The decisive property is `canary == prod`: the canary runs `VERIFIED_REF`, the
same verified digest prod will run, so an additive global install keeps ONE
verified artifact and the probe measures the exact image that will serve
tenants. No new image means the cosign/zot/freshness machinery is untouched.

**Acknowledged cost (review):** the payload files are tenant-*readable* — every
agent sandbox `--ro-bind / /`s the image, so `/app/test/` documents the probe's
assertions, sentinel names, and the `SOLEUR_ISOLATION_*` knob contract. This is
deliberate info-disclosure (the server source is already in the image); the
payload carries no secrets (tokens are `randomBytes` per run) and a tenant
cannot reach the deploy exec that consumes it.

**Image-size delta:** measured at build time; recorded in PR #9809 description.

**Zero-specifier constraint on `test/vitest.canary.config.ts` (#9860):** the
config file must carry no specifier-resolution forms — `export default` a
plain object literal, never `defineConfig(...)`. In the image vitest is a
global install and `/app` has no `node_modules/vitest`, so a bare specifier in
the config resolves against nothing and the probe fails at config-load with
`reason=vitest_rc_1: … [UNRESOLVED_IMPORT]` — observed on the v0.334.1 deploy.
The ban covers every specifier-resolution form (`export … from`, `import()`,
`require()`, not only `import` declarations), and a sibling assertion
deep-equals the exported object because config *values* (`environment`,
`coverage.provider`, `reporters`, …) reach the same resolver. Suite files are
exempt from the specifier ban: `import … from "vitest"` inside
`test/*.test.ts` resolves internally to the running install (verified on
vitest 4.1.11 under `env -i`) — but their bare specifiers are pinned to
builtins / prod `dependencies` / in-payload relatives, since a devDep import
there fails the same way in-image. All pinned at PR time in
`apps/web-platform/test/dockerfile-vitest-version-pin.test.ts`.

## Gate vs report — report-only (chosen)

The probe ships **report-only**: it is invoked `|| true` inside the
`CANARY_HEALTHY` block after `run_faithful_sandbox_canary` and
`run_outer_wrap_canary` (and before the GitHub App key check + swap), so it
runs, classifies, records and pages — but no verdict rolls the deploy back.

Rationale: `wg-dark-launch-deploy-gates` — never validate a gate change with the
same deploy it gates. The faithful sandbox canary (#5875 / ADR-079) established
the arc this follows: dark-launch first, accumulate a soak on real deploys,
promote to blocking in a separate change. The `canary_infra_error` class exists
precisely for the deploy-order coupling window (the updated `ci-deploy.sh`
reaches hosts via `apply-deploy-pipeline-fix.yml` ahead of the first
vitest-carrying image): an rc-125/126/127 records state without paging, so the
window is benign by design and never reads as a false green.

**Promotion criteria** (checked by the committed soak probe
`scripts/followthroughs/workspace-isolation-verdict-2640.sh`, a stateless GET of
`/hooks/deploy-status` — the host accumulates the counters):

1. `consecutive_pass >= 5` — five consecutive green verdicts (any
   `workspace_isolation_failed` / `workspace_isolation_timeout` resets the
   counter; `canary_infra_error` holds it), AND
2. `>= 3 days` elapsed since `first_pass_at`.

When both hold, a follow-up PR promotes the probe to blocking — a code change,
not a flag flip: `run_workspace_isolation_probe` always `return 0`s today, so
promotion adds a red-verdict→rollback path inside it AND drops the call-site
`|| true`. A recorded `workspace_isolation_failed` or
`workspace_isolation_timeout` verdict means investigate first — do NOT promote
while either stands.

Two ordering/ledger facts worth knowing before triaging a soak anomaly:

- The probe runs (and records `pass`) **before** `github_app_key_canary_check` —
  a verdict is about the image's isolation property, and still stands even if a
  later gate rolls that canary back for unrelated reasons.
- `WORKSPACE_ISOLATION_STATE_FILE` is alias-guarded against both canary ledgers
  (`WORKSPACE_ISOLATION_LEDGER_ALIAS`, same failure class as
  `OUTER_LEDGER_ALIAS`): an env override that aliases it logs a warn and skips
  the probe entirely — verdict vocabularies must never interleave in one file.

## Tier scoping — `SOLEUR_ISOLATION_TIERS=direct`

`sandbox-isolation.test.ts` carries tiers beyond the deterministic direct-bwrap
arm: the query tier spawns a live `ANTHROPIC_API_KEY` session, and FR9 needs
`ANTHROPIC_ISOLATION_TEST_OK`. The canary's env-file carries `ANTHROPIC_API_KEY`,
so running the suite wholesale inside the deploy window would fire live Anthropic
API calls — wrong for a deploy gate on cost, latency and determinism grounds.
The `SOLEUR_ISOLATION_TIERS` env filter scopes the in-canary run to the `direct`
tier (bwrap + socat, both in the runner image) and `SOLEUR_ISOLATION_TEST_HOST=1`
converts a silent `probeSkip` into a throw, so a silently-skipped suite cannot
read as `pass`. A `-t` name filter was rejected: describe-name string matching
breaks on rename; the env knob is an explicit contract.

## `/sys` deny — cgroup-visibility trade-off (accepted)

The paired #1285 change adds `"/sys"` to the agent-sandbox `denyRead` constant
(`/proc` precedent: #1047 / PR #1282). Masking `/sys` also hides
`/sys/fs/cgroup` inside the sandbox, so sandboxed subprocesses (e.g. a Node
child) size heaps and thread pools to **host** totals rather than container
limits. The kernel cgroup still enforces the limits — this is a heap-sizing
behavior change, not an isolation break. Accepted and recorded here so a future
"why does the sandboxed process see host memory totals" investigation has the
answer without archaeology.

Other `/sys`-masked reads that now return empty/error for sandboxed
subprocesses: `lscpu`/`lsblk`/`udevadm`/`dmidecode` output and `/sys/class/net`
interface enumeration (MAC addresses, CPU topology — the fingerprint surface
#1285 is for). These are intended consequences, not breakage.

What the mask does NOT cover (denyRead is a mount-layer control; the live
procfs the sandbox still needs serves them): `/proc/sys/**` (kernel config:
kernel.*, vm.*, fs.*), `/proc/self/mountinfo` (mount table), `/proc/kallsyms`,
`/proc/cpuinfo`+`/proc/meminfo`+`/proc/version` (host CPU/RAM/kernel fingerprint),
`/proc/sys/kernel/random/boot_id` (per-boot host UUID), and `uname(2)` (host
kernel release — no `--unshare-uts` in the argv). A future vendored tail
`--bind /sys /sys` would also pass through the shim's `/proc`-only exposure
gate — recorded so "denyRead /sys" is not later over-read as "host kernel
config invisible to tenants."
