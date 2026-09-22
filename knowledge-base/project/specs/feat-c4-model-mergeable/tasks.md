---
feature: c4-model-mergeable
plan: knowledge-base/project/plans/2026-09-22-fix-c4-model-mergeable-line-per-value-plan.md
lane: cross-domain
issue: 8542
---

# Tasks: mergeable model.likec4.json

## 1. Canonical module (TDD)

- [ ] 1.1 RED: write `plugins/soleur/test/c4-canonical.test.ts` (bun, `gitCleanEnv()` on every git spawn):
  - hash blanked only where present (≥ 2 views);
  - round trip + key order vs `JSON.stringify(JSON.parse(x))`;
  - no leading whitespace, single trailing `\n`;
  - idempotence;
  - non-view hash untouched;
  - bad input throws;
  - node CLI stdout ≡ import, and `--check` (0/1);
  - synthetic merge rows (a) disjoint, which merges, and (b) same-leaf, which conflicts;
  - `check-attr` shows only `linguist-generated`.
- [ ] 1.2 GREEN: `plugins/soleur/lib/c4-canonical.mjs` (pure, mirror header) and `plugins/soleur/lib/c4-canonical-cli.mjs` (stdout, `--check`, exit 2 on error).
- [ ] 1.3 `cp` the pure module to `apps/web-platform/lib/c4-canonical.mjs` and add `apps/web-platform/test/c4-canonical-mirror.test.ts` (bytes equal, paths differ).
- [ ] 1.4 Create `.gitattributes` with the `linguist-generated=true` line only.

## 2. Wire the writers

- [ ] 2.1 `scripts/regenerate-c4-model.sh`: after the gates, run the node CLI into `$TMP/canonical.json`, and refuse to publish on non-zero.
- [ ] 2.2 `apps/web-platform/server/c4-render.ts`: return `canonicalizeC4Model(raw)`; a throw maps to `io_error` with a `canonicalize failed` detail; update the comments.
- [ ] 2.3 `plugins/soleur/scripts/generate-c4-from-components.ts`: canonicalize the staged JSON before publish; a throw makes the run `failed` with no publish.
- [ ] 2.4 Tests:
  - `c4-render.test.ts`: canonical bytes, plus a `LikeC4Model.create` blank-hash row;
  - `c4-from-components.test.sh`: end-to-end `--check` row;
  - `c4-model-freshness.test.sh`: `--check` row;
  - `c4-likec4-version-pin.test.ts`: add the plugin `LIKEC4_VERSION`.
- [ ] 2.5 Check that both C4 routes handle a `JSON.parse` failure of the committed blob, and add a test row (fix if they don't).

## 3. Regenerate and plumbing

- [ ] 3.1 `bash scripts/regenerate-c4-model.sh`, then run the freshness suite and `--check`.
- [ ] 3.2 Update the `.gitattributes` comment in `resolve-regenerable-conflicts.sh`.

## 4. ADR and docs

- [ ] 4.1 Amend ADR-235: format, hash evidence, three writers + mirror, measured frequency, replay numbers, resolver scope limited to this repo, rollout and old-CLI churn, headroom.
- [ ] 4.2 ADR-050: note that the render returns canonical bytes.
- [ ] 4.3 Prose sweep via `git grep model.likec4.json -- plugins/soleur/skills`, fixing only the one-line, verbatim or raw-write claims.

## 5. Acceptance and verification

- [ ] 5.1 Replay with the real module, gaps 1-10, true-overlap pairs as the positive control; commit the table.
- [ ] 5.2 Apply mutation rows 1-6 and the harness rows; record each RED; restore the tree.
- [ ] 5.3 Run the AC6 suites (vitest + plugin suites, shell suites in CI-style env).
- [ ] 5.4 The `c4-count-parity` suite is green (no C4 impact).
