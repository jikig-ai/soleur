# Tasks — feat(live-verify): re-home harness into web-platform-release.yml (report-only, GHA)

Plan: `knowledge-base/project/plans/2026-06-17-feat-live-verify-gha-rehome-report-only-plan.md`
Issue: #5487 · Branch: feat-one-shot-5487-live-verify-gha-rehome · lane: cross-domain

## Phase 0 — Preconditions (verify, no code)

- [ ] 0.1 Confirm `deploy:` last step is "Verify deploy health and version" (web-platform-release.yml L467-529).
- [ ] 0.2 Confirm `NEXT_PUBLIC_SENTRY_DSN` is a workflow secret (reusable-release.yml L370).
- [ ] 0.3 Confirm `DOPPLER_TOKEN_PRD` secret name (sibling steps L122/L150/L251).
- [ ] 0.4 Confirm live-verify env contract: `grep -nE 'required\(|optional\(' apps/web-platform/scripts/live-verify/run.ts` (L102-110).
- [ ] 0.5 Confirm playwright version pin (apps/web-platform/package.json `@playwright/test` = 1.58.2) for browser setup.

## Phase 1 — Report-only live-verify job

- [ ] 1.1 Add `live-verify:` job: `needs: [deploy]`, `if: always() && needs.deploy.result == 'success' && github.event_name == 'push'`, `runs-on: ubuntu-latest`. NOTHING `needs:` it.
- [ ] 1.2 Steps: checkout (pinned SHA), dopplerhq/cli-action (pinned SHA), oven-sh/setup-bun (pinned SHA).
- [ ] 1.3 `bun install --frozen-lockfile` in apps/web-platform.
- [ ] 1.4 `npx playwright install --with-deps chromium` in apps/web-platform. LIVE_VERIFY_BROWSER_CHANNEL/PATH UNSET.
- [ ] 1.5 Trigger-paths gate step (`id: gate`): changed files via **GH compare API** (`gh api repos/.../compare/<before>...<sha>`, NOT `git diff` — zero-SHA fragility); strip comments/blanks, `grep -qE -f`. Three outcomes: match → `triggered=1`; no match → `SKIPPED:no-triggering-paths` (`triggered=0`); compare-API fail → `CANT-RUN:gate-diff-failed` (`gate_failed=1`, NOT silent skip). Branch on `github.event_name` (skip harness on dispatch).
- [ ] 1.6 Harness step (`id: harness`, `if: triggered == 1`, `continue-on-error: true`): `set +e; doppler run -c prd -- bun run scripts/live-verify/run.ts 2>&1 | tee /tmp/live-verify.out; rc=${PIPESTATUS[0]}; set -e`; extract last `RESULT:`; empty → `CANT-RUN:no-result-line:exit=$rc` + redacted stderr tail; write `result_line` + `rc` to `$GITHUB_OUTPUT`. `env: DOPPLER_TOKEN: secrets.DOPPLER_TOKEN_PRD`.

## Phase 2 — Sentry emit (NEW integration, not precedent reuse)

- [ ] 2.1 Emit step (`if: always()` for triggered/skipped/gate_failed): POST redacted result as a REAL event (not breadcrumb) to region-aware `https://<dsn-host>/api/<project>/store/` from `NEXT_PUBLIC_SENTRY_DSN` (public key as `sentry_key`; carry the DSN region, no `us` default); tags `gate=live-verify`, `component=web-platform`, `result=<tri-state>`; FAIL/no-result-line/gate-diff-failed → level=error, CANT-RUN → warning, SKIPPED → info. Fail-closed to `CANT-RUN:no-result-line` on empty `result_line`. Bounded 2-3 retry. Non-2xx → `::error::` + `$GITHUB_STEP_SUMMARY` (don't red the job). Reuse only the DSN-split shape from `sentry-monitors-audit.sh` (NOT its cluster-default).

## Phase 3 — ADR-064 amendment

- [ ] 3.1 Via `/soleur:architecture` amend ADR-064 §Substrate: append `### Inngest re-home considered and rejected (2026-06-17)` decision-of-record block (CTO reasoning). No status change. No new C4 edge (edge already `adopting`).

## Phase 4 — Workflow validation

- [ ] 4.1 `actionlint .github/workflows/web-platform-release.yml` → 0 errors (NOT `bash -n` on the YAML).
- [ ] 4.2 `bash -c '<snippet>'` over each new embedded `run:` block (gate, harness, emit).
- [ ] 4.3 Prove harness-failure-cannot-fail-the-deploy: (a) no other job lists `live-verify` in `needs:`; (b) harness step `continue-on-error: true`. Comment both.
- [ ] 4.3b Prove failure-still-produces-a-recording: stub a non-zero harness exit, confirm `result_line` output is still populated AND emit would POST a non-empty `result` tag (fail-closed `CANT-RUN:no-result-line:exit=<rc>`).
- [ ] 4.4 Confirm `deploy:` job `needs:` (L256) + `if:` (L265-273) byte-for-byte unchanged (additive diff only).

## Acceptance verification (pre-merge)

- [ ] AC live-verify job present, `needs: [deploy]`, nothing needs it, push-only.
- [ ] AC harness step `continue-on-error: true`.
- [ ] AC runs `doppler run -c prd -- bun run scripts/live-verify/run.ts`; BROWSER_CHANNEL/PATH never set.
- [ ] AC trigger-paths gated; SKIPPED on no match.
- [ ] AC Sentry emit of redacted RESULT, tri-state tagged, SSH-free.
- [ ] AC `actionlint` clean; deploy job unchanged.
- [ ] AC ADR-064 §Substrate has the Inngest-rejected block.

## Post-merge (feeds #5463)

- [ ] First qualifying deploy emits correct PASS/FAIL/CANT-RUN Sentry event; record on #5463 (verify via Sentry API, not dashboard-eyeball).
