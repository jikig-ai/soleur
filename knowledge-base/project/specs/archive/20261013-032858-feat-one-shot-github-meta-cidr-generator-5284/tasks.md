---
plan: knowledge-base/project/plans/2026-06-14-feat-self-refreshing-github-meta-cidr-generator-plan.md
issue: 5284
branch: feat-one-shot-github-meta-cidr-generator-5284
lane: cross-domain
---

# Tasks — Self-refreshing GitHub /meta CIDR generator (#5284)

Derived from the deepened plan. Implement in phase order (the contract-producer — generator —
lands before the cron consumer; ACs are PR-time gates, not phase audits).

## Phase 0 — Preconditions (verify, no code)

- [x] 0.1 `ls apps/web-platform/infra/test-fixtures/` — confirm fixture home exists.
- [x] 0.2 Confirm `ubuntu-24.04` runner ships `jq` + `curl` (preinstalled).
- [x] 0.3 Live-probe the jq shape: `curl -fsS --max-time 30 https://api.github.com/meta | jq -r '(.git+.api)[]|select(test(":")|not)' | sort -u | wc -l` — adopt this filter verbatim (matches file header line 28 + runbook line 81).
- [x] 0.4 Read `cron-egress-nftables.sh:70-78` — copy the `is_valid_ipv4_cidr` regex + octet/prefix bounds byte-for-byte for the generator.
- [x] 0.5 Read `cron-content-vendor-drift.ts` end-to-end — it is the cron template (Octokit fetch in step.run, safeCommitAndPr mergeMode "direct", Sentry heartbeat, five-registry slug).

## Phase 1 — Generator script (TDD)

- [x] 1.1 Write `apps/web-platform/infra/test-fixtures/github-meta-sample.json` (synthesized: a few `.git`/`.api` IPv4, ≥1 IPv6, ≥1 `0.0.0.0/0` over-broad entry, ≥1 duplicate).
- [x] 1.2 Write `apps/web-platform/infra/scripts/gen-github-egress-cidr.test.sh` (RED) — golden body, header markers (`DO NOT EDIT`/source URL/`Snapshot:` today), IPv6 drop, dup collapse, malformed→exit1, over-broad→exit1, empty→exit1, date-header no-op, `--check` exit codes, idempotent re-run, atomic-write trap (no stray tmp). Include `bash -n` self-check assertion.
- [x] 1.3 Write `apps/web-platform/infra/scripts/gen-github-egress-cidr.sh` (GREEN): fetch (`curl -fsS --max-time 30` or `META_JSON_FILE`), extract (verbatim jq), validate per-line (loader regex) + prefix-floor `>= /8`, non-empty guard, body-only no-op decision, atomic write (`mktemp` in target dir + `trap rm EXIT` + `mv -f`). `--check` mode.
- [x] 1.4 Run `bash gen-github-egress-cidr.test.sh` → green.

## Phase 2 — Regenerate committed file + rewrite drift-guard

- [x] 2.1 Run the generator against live `/meta`; commit regenerated `cron-egress-allowlist-cidr.txt` (generated header; body unchanged from #5281 unless rotated).
- [x] 2.2 Run the `comm -23` gap check → empty (zero coverage gap).
- [x] 2.3 In `cron-egress-firewall.test.sh`: delete the `count==52` block; add structural offline asserts (140.82 presence; ≥1 `^20[.]…/32`; ≥1 `^4[.]…/32`; floor `count >= 40`; no prefix `< /8`). Keep `is_valid_ipv4_cidr` unit tests (213-255) unchanged. Do NOT assert committed==fixture; do NOT call live `/meta`.
- [x] 2.4 Register `gen-github-egress-cidr.test.sh` as a step in `.github/workflows/infra-validation.yml` next to the `cron-egress-firewall.test.sh` step (~line 166).

## Phase 3 — Inngest refresh cron (template: cron-content-vendor-drift.ts)

- [x] 3.1 Write `apps/web-platform/server/inngest/functions/cron-github-cidr-refresh.ts`: `createFunction({…},{cron:"<daily>"}, …)`; step.run mint-installation-token (App auth); step.run detect-drift (Octokit GET /meta → shared extraction+validation → compare CIDR body, not header); no-drift→heartbeat+return; drift→`safeCommitAndPr({ mergeMode:"direct", allowedPaths:["apps/web-platform/infra/cron-egress-allowlist-cidr.txt"], scheduledIssueLabel: SLUG })`; heartbeat on every path.
- [x] 3.2 Extraction parity: prefer shelling out to `gen-github-egress-cidr.sh` (one source of truth); else re-implement jq+validator in TS AND add a parity test (TS body == shell body for the fixture).
- [x] 3.3 Write `cron-github-cidr-refresh.test.ts` (drift-detect, direct-merge path, heartbeat).
- [x] 3.4 Five-registry lockstep — slug byte-identical across: handler, `route.ts`, `cron-manifest.ts`, manifest-count test (`test/server/internal/trigger-cron-route.test.ts`), Sentry monitor (`infra/sentry/*` + `apply-sentry-infra.yml`). Register self-failure ops route.
- [x] 3.5 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` → green.

## Phase 4 — Docs + post-mortem

- [x] 4.1 Runbook `cron-egress-blocked.md`: replace manual `curl|jq` regen recipe with "run `gen-github-egress-cidr.sh`"; note cron auto-heal; keep `comm -23` probe.
- [x] 4.2 Post-mortem `ruleset-bypass-audit-cron-egress-cidr-gap-postmortem.md`: close the #5284 action item with the PR link.

## Phase 5 — Verify ACs

- [x] 5.1 Pre-merge ACs AC1-AC12 green (determinism, jq-verbatim, fail-loud incl. over-broad, validator parity, regenerated file, zero gap, drift-guard de-magicked + de-circularized, no-op date-header, loader untouched, five-registry lockstep, fetch timeout, extraction parity).
- [x] 5.2 Run the full infra test suite (`infra-validation.yml` steps locally) + `tsc` + `bun`/`vitest` for the cron test.
- [x] 5.3 PR body uses `Closes #5284` (body, not title). No `Closes` for any follow-up issue.
- [x] 5.4 Post-merge AC13 (apply path re-fires) + AC14 (cron dry-fire via `/api/internal/trigger-cron`, no SSH).
