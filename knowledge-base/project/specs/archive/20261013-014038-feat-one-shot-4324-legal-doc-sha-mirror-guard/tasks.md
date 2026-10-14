---
title: "Tasks — Generalize check-tc-document-sha.sh + mirror-equivalence to all 9 legal docs"
date: 2026-05-22
issue: 4324
plan: knowledge-base/project/plans/2026-05-22-feat-legal-doc-sha-mirror-guard-plan.md
lane: single-domain
---

# Tasks: feat-one-shot-4324-legal-doc-sha-mirror-guard

Derived from `2026-05-22-feat-legal-doc-sha-mirror-guard-plan.md` post-deepen-pass.

## Phase 0 — Preconditions

- 0.1. Verify `ls docs/legal/` returns exactly 9 files; `ls plugins/soleur/docs/pages/legal/` returns exactly 9 files; 1:1 basename match.
- 0.2. Run `bash apps/web-platform/scripts/check-tc-document-sha.sh` on `main` — assert exit 0 (baseline green).
- 0.3. Run `bunx vitest run apps/web-platform/test/legal-doc-consistency.test.ts` — assert green; confirm `package.json scripts.test` uses vitest (verified at plan time).
- 0.4. Compute SHA-256 of each canonical doc; cross-check against the seed table in plan AC1. Any drift means another PR landed first — refresh the table inline before continuing.
- 0.6. Run `grep -hoE '\((\./|/legal/|[a-z-]+\.md|https?://[^)]+)[^)]*\)' docs/legal/*.md plugins/soleur/docs/pages/legal/*.md | sort -u` — confirm every doc-class link form is covered by the existing `collapse` sed block (26 rules). Any new link form requires a new sed rule in the same PR before Phase 2 lands.
- 0.7. Run `grep -n "Last Updated" docs/legal/cookie-policy.md docs/legal/disclaimer.md` — confirm cookie-policy has zero body hits (allowlisted) and disclaimer has the `**Last Updated:**` form (normal coverage).

## Phase 1 — Create `legal-doc-shas.ts`

- 1.1. Create `apps/web-platform/lib/legal/legal-doc-shas.ts` with `LEGAL_DOC_SHAS: Readonly<Record<string, string>>` containing the 8 non-T&C SHAs from plan AC1 (re-verified at Phase 0.4).
- 1.2. Top-of-file JSDoc: explain (a) drift-detection-only role, (b) T&C exception with citation to `app/api/accept-terms/route.ts:48`, (c) the bump-policy rubric link.
- 1.3. Verify no consumer is wired yet (the file is a constants-only export at this stage); `tsc --noEmit` green.

## Phase 2 — Generalise the bash script

- 2.1. Refactor `apps/web-platform/scripts/check-tc-document-sha.sh` to filesystem-glob-derived `CANONICAL_DOCS` array via `shopt -s nullglob; for f in docs/legal/*.md`. Add `EXPECTED_COUNT=9` sentinel + `::warning::` on mismatch.
- 2.2. Upgrade the SHA-literal extraction from the brittle `tr -d '\n' | grep -oE` form to the `awk gsub` precedent (`run-scan.sh:34` shape). Verify the extracted T&C SHA before/after the upgrade produces the same value via `diff <(old-extractor) <(new-extractor)`.
- 2.3. Add a parallel map-key extractor for `LEGAL_DOC_SHAS["<key>"]` reading from `legal-doc-shas.ts` (uses `awk` with `BEGIN{re="\"<key>\":\\s*\"[0-9a-f]{64}\""}`).
- 2.4. Per-doc loop: body normalisation via existing `normalize_canonical` + `normalize_plugin` + `collapse`; SHA-match check; T&C-only `TC_VERSION` bypass (keep the existing `Step 2.5` seed-script parity block inside the T&C arm).
- 2.5. Accumulator pattern: `set +e ... rc=$? ; set -e ; if [ $rc -ne 0 ]; then failures+=("<doc>: <reason>"); fi`. Exit 1 if `${#failures[@]} -gt 0`.
- 2.6. Preserve every existing `::error::` annotation substring verbatim (`"T&C body drift"`, `"TC_DOCUMENT_SHA literal not found"`, `"T&C document SHA changed but TC_DOCUMENT_SHA literal is stale and TC_VERSION was not bumped"`, plus the `canonical_sha=...`/`literal_sha=...`/`file=...`/`Remediation: ...` block). For the 8 non-T&C docs, emit parallel-shaped messages naming the doc.
- 2.7. Run the new script on `main` — assert exit 0.

## Phase 3 — Update CI workflow

- 3.1. Edit `.github/workflows/ci.yml:106-115`: keep job name `tc-document-sha-guard`, keep script path; update step `name:` to "Verify all 9 legal-doc SHAs pinned".
- 3.2. Do NOT touch `infra/github/ruleset-ci-required.tf` — the job-name pin remains valid.

## Phase 4 — Refactor `legal-doc-consistency.test.ts`

- 4.1. Replace the hand-edited `DOCS` array with `readdirSync('docs/legal/').filter(f => f.endsWith('.md')).map(f => f.replace(/\.md$/, '')).sort()` at module top-level (vitest supports this).
- 4.2. Add `NO_BODY_LAST_UPDATED: ReadonlySet<string> = new Set(['individual-cla', 'corporate-cla', 'cookie-policy'])` with per-doc comment.
- 4.3. Update the `Last Updated date is identical` test to skip body-date assertions for docs in the allowlist; keep mirror-hero-date assertions for non-CLA docs.
- 4.4. Add meta-assertions: `expect(DOCS.length).toBeGreaterThanOrEqual(9)` AND `expect(DOCS).toEqual(expect.arrayContaining(['cookie-policy', 'disclaimer', 'terms-and-conditions']))`.
- 4.5. Run `bunx vitest run apps/web-platform/test/legal-doc-consistency.test.ts` — green.

## Phase 5 — Drift-smoke vitest harness

- 5.1. Create `apps/web-platform/test/legal-doc-shas-guard.test.ts`. Import `spawnSync` from `node:child_process`.
- 5.2. Per AC7 case (a): baseline pass — copy the legal-doc tree + `lib/legal/` to a `mkdtempSync` tempdir; invoke `spawnSync('bash', ['apps/web-platform/scripts/check-tc-document-sha.sh'], { cwd: tempdir, encoding: 'utf8' })`; assert `status === 0`.
- 5.3. Case (b): controlled mirror drift — flip one non-template word in tempdir's `plugins/soleur/docs/pages/legal/acceptable-use-policy.md`; re-invoke; assert `status === 1` AND `stderr.includes('acceptable-use-policy')`.
- 5.4. Case (c): stale SHA literal — append one byte to tempdir's `docs/legal/cookie-policy.md` (and do NOT touch `legal-doc-shas.ts`); re-invoke; assert `status === 1` AND `stderr.includes('cookie-policy')`.
- 5.5. Case (d): T&C `TC_VERSION` bypass — change canonical T&C in tempdir AND bump `TC_VERSION` in tempdir's `tc-version.ts` (simulate a base-ref via `GITHUB_BASE_REF` env or skip this case if the bypass path requires real git history; in the latter case assert via a unit-shaped helper instead).
- 5.6. All 4 cases green.

## Phase 6 — Extend bump-policy rubric

- 6.1. Edit `knowledge-base/legal/tc-version-bump-policy.md`. Add a `## Non-T&C legal docs` section per AC5: (a) every edit requires SHA refresh in `legal-doc-shas.ts`; (b) Tier 1/2/3 classification still applies for Article 30 register + counsel-review-ledger; (c) CLA docs + Cookie Policy exempt from body `**Last Updated:**` line (rely on Git history + hero-date).
- 6.2. Update the document header section (`Applies to all 9 docs` vs `Applies to T&C only`) per OQ3 default.
- 6.3. Optional CLO advisory tag in PR body; not blocking.

## Phase 7 — End-to-end CI verification

- 7.1. Push branch. Observe `tc-document-sha-guard` green in CI.
- 7.2. Throwaway commit deliberately mutating one canonical doc (e.g., `docs/legal/cookie-policy.md` + leave SHA stale). Push. Observe `tc-document-sha-guard` red with per-doc annotation. Revert.
- 7.3. Squash to clean history before marking PR ready.

## Phase 8 — Plan-review + ship

- 8.1. `/plan_review` against the plan file: DHH + Kieran + simplicity. Apply revisions.
- 8.2. `/soleur:ship`.

## Files to Edit

- `apps/web-platform/scripts/check-tc-document-sha.sh` — generalise per-doc loop; doc-agnostic `collapse`; per-doc failure accumulation; T&C-special-case for `TC_VERSION` bypass.
- `apps/web-platform/lib/legal/tc-version.ts` — no functional change; optional comment cross-reference to `legal-doc-shas.ts`.
- `apps/web-platform/test/legal-doc-consistency.test.ts` — filesystem-glob `DOCS`; `NO_BODY_LAST_UPDATED` allowlist; meta-assertions.
- `.github/workflows/ci.yml:106-115` — step name update; no job-name change.
- `knowledge-base/legal/tc-version-bump-policy.md` — non-T&C-docs section per AC5.

## Files to Create

- `apps/web-platform/lib/legal/legal-doc-shas.ts` — `LEGAL_DOC_SHAS` map for 8 non-T&C docs.
- `apps/web-platform/test/legal-doc-shas-guard.test.ts` — drift-smoke vitest harness (AC7).
