---
feature: feat-one-shot-4773-cron-eval-observability
issue: 4773
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-02-feat-cron-eval-observability-stdout-tail-and-vector-routing-plan.md
---

# Tasks — cron-eval observability (#4773)

> Phase order is load-bearing: PR-A (contract/producer) MUST precede PR-B (consumers).
> PR-C (infra) is independent. Single atomic PR. Test runner: vitest (NOT bun test).

## Phase 0 — Preconditions (verify, no code)

- [ ] 0.1 Confirm the 5 unthreaded sites + 3 done sites:
      `grep -rl "stderrTail: spawnResult.stderrTail" apps/web-platform/server/inngest/functions/cron-*.ts | wc -l` → 3 (pre-change).
- [ ] 0.2 Enumerate every resolve path setting `stderrTail` in `_cron-claude-eval-substrate.ts`
      (`grep -n "stderrTail"`) — PR-A adds a sibling `stdoutTail` to each.
- [ ] 0.3 Confirm 3 `docker run -d` sites:
      `grep -n "docker run -d" apps/web-platform/infra/ci-deploy.sh apps/web-platform/infra/cloud-init.yml` → cloud-init:505, ci-deploy:448 (canary), ci-deploy:613 (prod).
- [ ] 0.4 Pin the Docker journald-driver tag field (`CONTAINER_NAME`) with a `<!-- verified: -->` note.

## Phase 1 — PR-A: stdout tail capture (producer/contract)

- [ ] 1.1 Add `stdoutTail?: string` to `SpawnResult` with doc block (`_cron-claude-eval-substrate.ts:16-30`).
- [ ] 1.2 Add `export const STDOUT_TAIL_CAP_BYTES = 8192;` (mirror `STDERR_CAP_BYTES`; justify inline).
- [ ] 1.3 Add `let stdoutTail = "";` accumulator beside `stderrTail` (`:216`).
- [ ] 1.4 In the stdout readline handler (`:229-234`): keep `logger.info`, append redacted line via
      `stdoutTail = (stdoutTail + redacted + "\n").slice(-STDOUT_TAIL_CAP_BYTES)`.
- [ ] 1.5 Set `stdoutTail` in the `child.on("exit")` resolve (`:275-284`) and `child.on("error")`
      resolve (`:295-302`). Decide the error-path fallback (likely no `|| msg` — spawn error has no stdout).
- [ ] 1.6 `_cron-shared.ts resolveOutputAwareOk`: add optional `stdoutTail?: string` param; fold into
      `scheduled-output-missing` extra (`:334-345`) as a sliced sibling of `stderrTail`.

## Phase 2 — PR-B: thread diagnostics into 5 consumer sites

- [ ] 2.1 `cron-growth-audit.ts:212` — add `stderrTail`/`exitCode`/`stdoutTail` (copy from `cron-roadmap-review:288-294`).
- [ ] 2.2 `cron-campaign-calendar.ts:215` — same.
- [ ] 2.3 `cron-seo-aeo-audit.ts:241` — same.
- [ ] 2.4 `cron-community-monitor.ts:309` — same.
- [ ] 2.5 `cron-growth-execution.ts:249` — same.
- [ ] 2.6 Verify all 8 sites pass all three fields:
      `grep -rl "stderrTail: spawnResult.stderrTail" apps/web-platform/server/inngest/functions/cron-*.ts | wc -l` → 8.

## Phase 3 — PR-C: Vector routing (infra)

- [ ] 3.1 Add `--log-driver journald` to all 3 `docker run` sites (cloud-init:505, ci-deploy:613 prod, ci-deploy:448 canary).
- [ ] 3.2 Add `[sources.app_container_journald]` to `vector.toml` (journald, `include_matches.CONTAINER_NAME=["soleur-web-platform"]`,
      WARN+ PRIORITY filter, `/var/log/journal`, `batch_size=16`) — adopt the precedent shape (Precedent Diff table).
- [ ] 3.3 Add the new source to `pii_scrub_drop_userdata.inputs` (`:63`) so it traverses the full 3-stage redaction.
- [ ] 3.4 Tag it `source_kind = "app_container"` in `tag_journald`.
- [ ] 3.5 `vector validate --no-environment --config-toml apps/web-platform/infra/vector.toml` passes.
- [ ] 3.6 Extend `apps/web-platform/test/infra/vector-pii-scrub.test.sh` for the new source's redaction.
- [ ] 3.7 Update `betterstack-log-query.md` `## Known coverage gap` → closed; document the `source_kind=app_container` query.

## Phase 4 — Tests & verification

- [ ] 4.1 Add a stdout-tail capture test to `apps/web-platform/test/server/inngest/cron-claude-eval-substrate.test.ts`
      (mirror the `spawnSimple — stderr capture` describe: token redaction + bounded-tail + tail content).
- [ ] 4.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-claude-eval-substrate.test.ts` → all pass.
- [ ] 4.3 `vector validate` + `vector-pii-scrub.test.sh` green.
- [ ] 4.4 PR body uses `Closes #4773`. No post-merge operator steps (config ships via merge-driven bootstrap + container restart).
