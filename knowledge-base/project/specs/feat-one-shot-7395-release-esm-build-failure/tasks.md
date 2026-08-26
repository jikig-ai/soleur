# Tasks — fix(release): image build fails on a type-checked import of a dockerignored file

Plan: `knowledge-base/project/plans/2026-08-26-fix-release-build-dockerignored-import-plan.md`
Branch: `feat-one-shot-7395-release-esm-build-failure`
Issue: #7395 · Lane: cross-domain · Threshold: single-user incident

---

## Phase 0 — Preconditions (read-only)

- [ ] 0.1 Re-confirm the break is still live: `gh run list --workflow web-platform-release.yml --branch main --limit 3 --json headSha,conclusion`. Enumerate by workflow name — never `--commit`, which saturates at `-L 200`.
- [ ] 0.2 Re-confirm production is still frozen: `curl -fsS https://app.soleur.ai/health | jq -r .build_sha`. Expected pre-fix: `dc201e757f63faa2001b4cf3e4ae4d8e6748bb38`. Record the value; AC10 compares against it.
- [ ] 0.3 Reproduce the root cause at the context layer (T1):
      `printf 'FROM busybox\nCOPY test/repo-wide-suites.ts /x\nRUN ls -l /x\n' | docker build -q -f - -t dockerignore-probe apps/web-platform`
      Expected: non-zero, `not found`.
- [ ] 0.4 Run the control probe (T3) on `scripts/assert-dev-signin-eliminated.sh`. Expected: exit 0. If this fails, the whole fix mechanism is wrong — stop and re-plan.
- [ ] 0.5 Read `apps/web-platform/scripts/lib/no-cross-context-import.test.sh` and the `.dockerignore` evaluator in `plugins/soleur/test/dockerfile-copy-dockerignore-parity.test.ts` before editing either.
- [ ] 0.6 Capture the baseline: `bash apps/web-platform/scripts/lib/no-cross-context-import.test.sh` — record the current scanned count.

## Phase 1 — RED: the mutation matrix, written before the guard

Per `cq-write-failing-tests-before` and the plan's Guard Contract, the matrix is derived from the
design, not from the finished guard.

- [ ] 1.1 Encode mutation rows 1–6 as executable cases.
- [ ] 1.2 Encode harness rows H1–H4. **H3 and H4 are must-PASS** — a battery where every row reddens has not shown the guard discriminates.
- [ ] 1.3 Confirm rows 1–3 currently FAIL to redden against the unmodified guard. That failure is the proof the existing predicate is the defect.

## Phase 2 — GREEN: restore the build context

- [ ] 2.1 Edit `apps/web-platform/.dockerignore`: add `!test/repo-wide-suites.ts` **after** the `test/` line, with the comment block from the plan (cites #7395, names the tsconfig coupling, points at the guard).
- [ ] 2.2 Re-run the busybox probe (T2). Expected: exit 0. **This, not a grep of `.dockerignore`, is the authoritative check.**
- [ ] 2.3 Re-run the control probe (T3). Expected: still exit 0 — the edit must not disturb the sibling re-include.

## Phase 3 — GREEN: widen the guard predicate

- [ ] 3.1 Choose shape 2a (extract the evaluator to a shared module — preferred) or 2b (bash shells out to a node/bun entrypoint). Decide on the smaller diff. **Do not duplicate the matcher.**
- [ ] 3.2 Replace the `"$APP"/*` membership test with a Docker-build-context membership test consulting `.dockerignore` through the single evaluator.
- [ ] 3.3 Derive the type-checked file set from `tsconfig.json` include/exclude intersected with context membership. Do not hardcode "everything except `test/`".
- [ ] 3.4 Keep the existing vacuity floor (`checked -eq 0` → FAIL) and add one for the context-membership side.
- [ ] 3.5 Preserve fail-loud semantics on unmodeled `.dockerignore` pattern shapes (row 5). Never silently skip.
- [ ] 3.6 Update the guard's header comment — the current one asserts the proxy *is* the property, which is what made this outage invisible.

## Phase 4 — Verify the guard is not vacuous

- [ ] 4.1 Run mutation rows 1–6. All must redden (T5–T10).
- [ ] 4.2 Run harness rows H1–H4 (T11–T14). H1/H2 RED; H3/H4 PASS.
- [ ] 4.3 Row 5 subsumption check (AC5): re-introduce the #6852 shape (production file importing repo-root `scripts/lib/…`) and confirm it still reddens. No coverage traded away.
- [ ] 4.4 Record the observed output for every row — it goes in the PR body per AC4.
- [ ] 4.5 Clean-repo run (AC3): guard exits 0 with a non-zero scanned count.

## Phase 5 — Full battery

- [ ] 5.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (T15). Never `npm run -w` — the repo root declares no `workspaces` field.
- [ ] 5.2 Run the **scripts** shard (the bash guard) and the **bun** shard (the parity suite) explicitly. A diff touching only `.dockerignore` reaches neither under the #7352 touched-shard rule — the parity suite is an orphan suite here.
- [ ] 5.3 `bash scripts/test-all.sh` (AC7).
- [ ] 5.4 Confirm the parity suite's pre-existing assertions still pass after the extraction (T16, AC6).

## Phase 6 — Ship PR-1

- [ ] 6.1 PR body: `Closes #7395`, link to the plan, and the full mutation/harness matrix results.
- [ ] 6.2 File the PR-2 follow-up issue (AC14) carrying the measured `-L 200` saturation evidence and the two-glob-dialect hazard.
- [ ] 6.3 Comment on #7395 with the Research Reconciliation table (AC13) — real cause, corrected 08-20 date, three conflated failure classes, alerting already in place.
- [ ] 6.4 Leave #7676 alone. It self-closes on the next `CLEAN` drift run.

## Phase 7 — Post-merge verification (automated)

- [ ] 7.1 AC9: release run reaches `release: success` **and** `deploy: success`, not skipped. Enumerate by workflow name.
- [ ] 7.2 AC10: `curl -fsS https://app.soleur.ai/health | jq -r .build_sha` returns the new merge SHA, not `dc201e75…`. A green run is not proof.
- [ ] 7.3 AC11: the published image digest differs from the one previously served.
- [ ] 7.4 AC12: drift alerter reports `CLEAN`; `gh issue view 7676 --json state` returns `CLOSED` on its own.

---

## Deferred to PR-2 (tracked, not dropped)

Presence-aware post-merge verification. Covered on a cron cadence at ~5h latency by
`scheduled-prod-version-drift.yml` in the meantime — this is a latency improvement on a covered
property, which is why it does not block PR-1.

- [ ] `ship/SKILL.md:2016-2060` — expected-set presence assertion (design already written at `:2040`)
- [ ] `ship/SKILL.md:2045` — delete the "steady total" heuristic; it certifies completeness at saturation
- [ ] `ship/SKILL.md:1934` — same cap on the PR-head query
- [ ] `postmerge/SKILL.md:49` — `--limit 3` + warn-and-proceed; and add a release/deploy line to the Phase 7 report
- [ ] Regression test for the Phase 7 query shape — none exists today
- [ ] ADR: presence-of-expected-set over absence-of-failures (ordinal re-verified against `origin/main` immediately before merge)
