# Learning: Two fail-open traps when building a CI→deploy gate (skip-token grep + BuildKit cache mode)

## Context

Planning a gate that blocks the prod `deploy` job on CI's `test` check-run for the push SHA
(`web-platform-release.yml`), plus Docker `type=gha` layer caching. Brand-survival threshold =
single-user incident. spec-flow-analyzer caught both traps at plan time, before any code.

## Trap 1 — Unanchored `[skip ci]` grep over the commit message is a FAIL-OPEN hole

First instinct: to avoid the gate hanging on a deliberate `[skip ci]` release (CI never runs →
no `test` check-run → 15-min timeout), detect the skip-token in the commit message and bypass
the gate (`exit 0`).

**Why it's fail-open:** GitHub only honors a skip-token when it is on the **last line** of the
commit message. A `grep -qiE '\[(skip ci|...)\]'` over the **whole** message matches a token
**substring anywhere** — including a normal PR body that merely *mentions* it (a changelog
bullet "document [skip ci] behavior", a quoted revert, a co-author note). In that case CI runs
normally and produces a real — possibly **RED** — `test` check-run, but the grep sees the
substring and `exit 0`s, **deploying past a red CI**. The bypass meant to save 15 minutes
silently became the one path that ships broken `main`.

**Fix (fail-closed):** never trust the commit-message token as a deploy authorizer. Instead, if
**no `ci.yml` run exists for the SHA at all** after a short grace, fail-CLOSED fast
(`gh api actions/workflows/ci.yml/runs?head_sha=$SHA` → `.total_count == 0` → `exit 1` with an
actionable message). Deliberate skip-ci releases use the `workflow_dispatch` escape hatch. The
poll's ONLY `exit 0` must be guarded by `conclusion == "success"`.

## Trap 2 — `docker/build-push-action` `cache-to: mode=max` caches builder-stage SECRETS

`mode=max` exports **all** intermediate stages to the gha cache (which is repo-readable). If the
**builder** stage consumes a non-public secret build-arg (here `SENTRY_AUTH_TOKEN`, used for
sentry-cli source-map upload during `npm run build`), `mode=max` persists that secret-bearing
layer to a cache any workflow in the repo can read.

**Fix:** use `mode=min` — it exports only **final-image (runner-stage)** layers. The heavy-install
velocity wins (global CLIs, apt, playwright-chromium) live in the runner stage and ARE recovered;
the secret-bearing builder stage is never cached. Verify the invariant:
`awk '/AS runner/,0' Dockerfile | grep -c <SECRET_ARG>` returns `0`. Add a tripwire comment at
the `cache-to` line so a future editor can't silently flip to `max` or add a runner-stage secret.

## Key Insight

For a deploy gate at single-user-incident threshold, **every convenience shortcut must be
re-examined for a fail-OPEN inversion**: the skip-token bypass (meant to avoid a hang) and
`mode=max` (meant to maximize cache hits) each *looked* like pure optimizations but opened a
path to ship broken code / leak a secret. The flow-analysis lens (spec-flow-analyzer) catches
these because it walks "does this convenience ever let the bad thing through?" — schema/style
reviewers structurally cannot. Always run spec-flow + security review on a gate plan before code.

Corollary (arch-review): a cache claim must name the EXACT cacheable layer range. `npm ci
--omit=dev` below `ENV BUILD_SHA` is cache-busted every commit even though it "looks"
runner-stage; only layers ABOVE the volatile `ENV` are recovered. Grep the line numbers.

## Session Errors

None (clean planning session). The two traps above were caught at plan-review, not shipped —
this learning records them so the next CI-gate plan starts fail-closed.

## Tags
category: workflow-patterns
module: ci-cd
related: [5052, 5051, 5054, 5055]
