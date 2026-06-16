# Learning: infra `*.test.sh` orphan suites + docker `-e NODE_OPTIONS` clobbers `--env-file`

## Problem

While shipping the #5417 container-restart-churn fix (memory caps + a new host
`container-restart-monitor.sh` systemd timer + crash attribution), three
recurring-class traps surfaced:

1. **Orphan infra test suites.** `apps/web-platform/infra/*.test.sh` is NOT
   glob-discovered by CI. `.github/workflows/infra-validation.yml` runs an
   explicit *named* step per test (`run: bash apps/web-platform/infra/<x>.test.sh`).
   So a sibling that nobody added a step for never runs. `resource-monitor.test.sh`
   and `cat-deploy-state.test.sh` were pre-existing orphans CI never executed, and
   the new `container-restart-monitor.test.sh` would have been orphaned too —
   shipping a "tested" monitor whose test never gates. (Note: `scripts/test-all.sh`
   does NOT cover `apps/web-platform/infra/*.test.sh` either — its scripts-shard
   glob is `plugins/soleur/test/*`, `.claude/hooks/*`, `apps/web-platform/scripts/*`,
   never `infra/`.)

2. **`-e NODE_OPTIONS=` clobbers `--env-file`.** Adding `-e NODE_OPTIONS=--max-old-space-size=N`
   to a `docker run` that ALSO passes `--env-file "$ENV_FILE"` (the full Doppler
   dump) silently drops any operator-set `NODE_OPTIONS` from Doppler — docker
   resolves `-e` over `--env-file` for the same key. A future Doppler
   `NODE_OPTIONS=--enable-source-maps` would vanish on the next deploy with no
   warning, surfacing as an un-attributable behavior regression.

3. **Next-free ADR number is not what the plan says.** The plan referenced
   "ADR-061"; ADR-061 was already taken by a concurrently-landed ADR. Plan-quoted
   ADR/migration numbers are stale the moment a sibling PR lands one.

## Solution

1. **Register every new infra test as a named step** in `infra-validation.yml`
   (and backfill the orphans you find — they're free coverage). Done for all three
   monitor-family suites here.

2. **APPEND, never replace, env vars that the env-file also owns.** Compose
   `NODE_OPTIONS` from the Doppler value + your flag, your flag LAST so it wins:
   ```bash
   DOPPLER_NODE_OPTIONS=$(grep -E '^NODE_OPTIONS=' "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' || true)
   PROD_NODE_OPTIONS="${DOPPLER_NODE_OPTIONS:+$DOPPLER_NODE_OPTIONS }--max-old-space-size=$PROD_NODE_MAX_OLD_SPACE_MB"
   # docker run ... -e NODE_OPTIONS="$PROD_NODE_OPTIONS"
   ```

3. **Verify the next free ADR number at work-start** (`ls knowledge-base/engineering/architecture/decisions/ | grep -oE 'ADR-[0-9]+' | sort -t- -k2 -n | tail -1`), never trust the plan's quoted number.

## Key Insight

CI discovery that is *enumerated* (named steps, hard-coded `-target=` lists, a
fixed test array) rather than *globbed* is a standing orphan-generator: a new
member of the set is a non-conflicting addition that git merges silently and CI
never sees. The same shape recurs across the repo (the terraform `-target=` parity
guard exists for exactly this on `terraform_data` resources). When you add a file
to an enumerated set, grep the enumerator and add yourself — and backfill the
orphans you trip over.

## Session Errors

1. **ADR-061 collision** — Recovery: grep + sed ADR-061→ADR-062 across ci-deploy.sh + issue-alerts.tf. **Prevention:** verify next-free ADR at work-start (route-to-definition below).
2. **infra orphan-suite CI gap** — Recovery: registered container-restart-monitor + resource-monitor + cat-deploy-state in infra-validation.yml. **Prevention:** a guard test asserting every `apps/web-platform/infra/*.test.sh` has a named step in infra-validation.yml (file-tracked candidate; not inlined — different subsystem from this fix).
3. **`-e NODE_OPTIONS` clobbers `--env-file`** — Recovery: append-composition from the env-file. **Prevention:** captured here + the work skill's infra notes.
4. **Vacuous test gates** (OOM OR-signal armed multiple terms at once; sentry-config regex matched the comment block) — Recovery: split per-signal + assert the executable filter expression; mutation-verified. **Prevention:** already covered by `2026-04-18-red-verification-must-distinguish-gated-from-ungated.md` — apply it to shell OR-signal gates too, not just TS.
5. **vitest spread-mock TS2556** — `(...a)=>fn(...a)` passes vitest, fails tsc. Recovery: `vi.mocked(import)`. **Prevention:** one-off; prefer `vi.mocked` over spread-wrapper mocks.
6. **2 pre-existing ci-deploy doppler-env test failures** — one-off; doppler installed at `/usr/bin` on this box defeats the `MOCK_DOPPLER_MISSING` PATH-restriction; passes on CI runners.

## Tags
category: integration-issues
module: apps/web-platform/infra, ci
