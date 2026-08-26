# Tasks — fix(release): image build fails on a type-checked import of a dockerignored file

Plan: `knowledge-base/project/plans/2026-08-26-fix-release-build-dockerignored-import-plan.md`
Branch: `feat-one-shot-7395-release-esm-build-failure`
Issue: #7395 · Lane: cross-domain · Threshold: single-user incident

Three PRs. **PR-1a is the P0 unfreeze and is hostage to nothing** — do not couple it to PR-1b.

---

## PR-1a — Unfreeze production

### Phase 0 — Preconditions (read-only)

- [ ] 0.1 Confirm the break is still live: `gh run list --workflow web-platform-release.yml --branch main --limit 3 --json headSha,conclusion`. Enumerate by workflow name, never `--commit` (saturates at `-L 200`).
- [ ] 0.2 Record the frozen build: `curl -fsS https://app.soleur.ai/health | jq -r .build_sha`. Expected pre-fix `dc201e757f63…`. AC11 compares against it.
- [ ] 0.3 Reproduce at the context layer: busybox probe on `test/repo-wide-suites.ts` → expect non-zero / `not found`.
- [ ] 0.4 Re-enumerate the reference set — `git grep -n repo-wide-suites -- ':!knowledge-base'`. The plan measured 5 sites; confirm before moving.
- [ ] 0.5 Re-check for accumulated Supabase migrations (AC14): `git diff --name-only <prod_sha>..origin/main -- apps/web-platform/supabase/migrations/`. Was zero at plan time; more commits have landed since.

### Phase 1 — Move the file

- [ ] 1.1 `git mv apps/web-platform/test/repo-wide-suites.ts apps/web-platform/repo-wide-suites.ts`
- [ ] 1.2 `vitest.config.ts:4` → `from "./repo-wide-suites"`
- [ ] 1.3 `test/repo-wide-containment.test.ts:42` → `from "../repo-wide-suites"`
- [ ] 1.4 `test/repo-wide-containment.test.ts:210` and `:232` — prose strings `test/repo-wide-suites.ts` → `repo-wide-suites.ts` (these are the messages the guard prints to whoever trips it; a stale path sends them to a file that no longer exists)
- [ ] 1.5 `scripts/lib/test-relevance-paths.sh:248` — same prose fix in the comment
- [ ] 1.6 AC1: `git grep -c 'test/repo-wide-suites' -- ':!knowledge-base'` returns 0

### Phase 2 — Prove the containerized build passes

- [ ] 2.1 AC2: busybox probe on `repo-wide-suites.ts` → PRESENT
- [ ] 2.2 **AC3 (load-bearing)** — `docker build --target builder` on a throwaway copy of `apps/web-platform` carrying the fix. Record the outcome in the PR body.
      `next build` reports only the FIRST type error and exits, and `test/` has been context-absent since the exclusion was added — so further failures could be masked behind `vitest.config.ts:4`. Without this, "the fix is sufficient" is an inference, not a measurement.
- [ ] 2.3 If AC3 names a second failing file, STOP and re-plan. Do not merge and discover it from a red release run.
- [ ] 2.4 AC4: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` → 0 errors. Never `npm run -w` (no root `workspaces` field).
- [ ] 2.5 AC5: `bash scripts/test-all.sh` green — the `repo-wide` project validates the moved constant against `repo-wide-containment.test.ts`.

### Phase 3 — Ship and correct the record

- [ ] 3.1 PR body: `Closes #7395`, link the plan, record the AC3 outcome.
- [ ] 3.2 Comment on #7395 with the Research Reconciliation table — real cause, corrected 08-20 date, three conflated failure classes, alerting already in place.
- [ ] 3.3 File the **PR-1b** issue (guard widening) with the chokepoint list and mutation matrix.
- [ ] 3.4 File the **PR-2** issue (presence-aware post-merge verification) with the measured `-L 200` saturation evidence and the two-glob-dialect hazard.
- [ ] 3.5 **AC15** — file the split-brain issue: `cron-gh-pages-cert-state` monitor disarmed live by `a05ae1f77` while its producer stays frozen, plus the general class (any PR spanning auto-applied `infra/**` and image code is split by a freeze).
- [ ] 3.6 Leave #7676 alone — it self-closes on the next `CLEAN` drift run.

### Phase 4 — Post-merge verification (automated)

- [ ] 4.1 **AC11 (primary)** — `curl -fsS https://app.soleur.ai/health | jq -r .build_sha` returns the new merge SHA, not `dc201e757f63…`. Subsumes any digest check.
- [ ] 4.2 AC12 (corroboration only) — release run shows `release: success` **and** `deploy: success`, not skipped. Secondary by design: this plan recorded that the workflow+branch-filtered query returned 5-day-stale results in this very session.
- [ ] 4.3 AC13 — drift alerter reports `CLEAN`; `gh issue view 7676 --json state` returns `CLOSED` on its own.

---

## PR-1b — Widen the guard (separate PR; must not gate PR-1a)

### Phase 5 — RED first: the mutation matrix

- [ ] 5.1 Encode mutation rows 1–6 and harness rows H1–H4 before touching the guard. Derive them from the design, not from finished code.
- [ ] 5.2 Confirm rows 1, 2 and 4 do **not** redden against the unmodified guard — that failure is the proof the predicate is the defect.
- [ ] 5.3 H2/H3/H4 are **must-PASS**. A battery where every row reddens has not shown the guard discriminates.

### Phase 6 — GREEN: the predicate

- [ ] 6.1 **Two-sided** membership: flag only when the importer is context-present AND the resolved target is not. A one-sided rule yields 17 false positives from `scripts/`-internal sibling imports.
- [ ] 6.2 **Preserve the outside-`$APP` branch explicitly, before any context evaluation** — a context-relative evaluator fed `../../scripts/lib/…` matches nothing and silently drops #6852 coverage.
- [ ] 6.3 **Alias extraction** — resolve `tsconfig.paths` (`@/*` → `./*`), read from tsconfig, never hardcoded. Live instance: `app/internal/github-app-init/page.tsx:3`.
- [ ] 6.4 Extraction must cover `import type`, `export … from`, and **every** specifier on a line (current code pipes through `head -1`).
- [ ] 6.5 **Resolution probing** — `.ts`, `.tsx`, `.d.ts`, `.js`, `/index.*`, mirroring `moduleResolution: "bundler"`. Unresolvable → **fail loud, never skip**. Use `realpath -ms` (no-symlinks) to match Docker's literal-path matching.
- [ ] 6.6 Parse `.dockerignore` at runtime for exclusions and exact `!<path>` re-includes; **fail loud** on any unmodelled re-include shape. Do **not** extract a shared evaluator — two models already exist (`dockerfile-copy-dockerignore-parity.test.ts`, `cloud-init-user-data-size.test.ts:1173`).
- [ ] 6.7 Calibrate the type-checked population empirically. It is neither a subset nor a superset of "tracked ∩ context" — `identity.test.ts` is in both and apparently unchecked; `next-env.d.ts` and `.next/types/**` are context-absent yet generated and checked inside the builder.
- [ ] 6.8 Vacuity floor written `-lt 1`, not `-eq 0` — `scripts/guard-vacuity-floor.test.sh` derives its population by matching `-lt|-le|-ge`, so an `-eq` floor is invisible to the meta-guard.
- [ ] 6.9 Fix the success message (AP-021): it currently asserts "Docker build context intact", a cause it never measured.
- [ ] 6.10 Rehome into the `repo-wide` vitest project — `scripts/test-all.sh` runs it unconditionally ("never gated by the thing it guards"), which removes the shard problem with no manual-invocation clause.

### Phase 7 — Verify

- [ ] 7.1 AC8: rows 1–6 RED, H1 RED, H2/H3/H4 PASS. Record observed output per row.
- [ ] 7.2 AC9: re-measure exposure after the change — alias-aware and two-sided — and report an explicit count. Do not assert "zero".
- [ ] 7.3 AC10: no *new* `.dockerignore` model introduced.
- [ ] 7.4 AC7: guard green on the real repo with a non-zero scan count.
- [ ] 7.5 Full battery.

---

## PR-2 — Presence-aware post-merge verification (issue only)

Covered on the drift alerter's cron cadence at ~5h latency in the meantime, so it gates nothing.

- [ ] `ship/SKILL.md:2016-2060` — expected-set presence assertion (design already written at `:2040`)
- [ ] `ship/SKILL.md:2045` — delete the "steady total" heuristic; at saturation it certifies completeness
- [ ] `ship/SKILL.md:1934` — same cap on the PR-head query
- [ ] `postmerge/SKILL.md:49` — `--limit 3` + warn-and-proceed; add a release/deploy line to the Phase 7 report template
- [ ] Regression test for the Phase 7 query shape — none exists today
- [ ] ADR: presence-of-expected-set over absence-of-failures; ordinal re-verified against `origin/main` immediately before merge
