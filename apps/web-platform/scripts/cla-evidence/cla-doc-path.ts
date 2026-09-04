/**
 * THE DISCRIMINANT MODULE — the one place either CLA document path is written.
 *
 * Six producer sites used to carry the ICLA path as a bare literal (three in
 * `.github/workflows/cla-evidence.yml`, plus `cla-backfill-evidence.ts`,
 * `cla-evidence/backfill.ts` and `cla-evidence/build-record.ts`), with two more
 * in test fixtures. With a Corporate CLA now also in play, a bare literal is no
 * longer a path — it is an unstated assertion about WHICH instrument a record
 * evidences, and the two are no longer interchangeable.
 *
 * This module stays PURE on import. `build-bypass.ts` is the cautionary
 * precedent: its top-level `main()` calls `process.exit()`, so importing
 * anything from it kills the test worker instead of failing an assertion. The
 * CLI below is therefore guarded on being the entrypoint, so `import`ing this
 * module has no side effect at all. Shell consumers (the workflow's bash steps,
 * which cannot import TypeScript) read the value via:
 *
 *   apps/web-platform/node_modules/.bin/tsx \
 *     apps/web-platform/scripts/cla-evidence/cla-doc-path.ts
 */

/** Individual CLA — the instrument an individual contributor signs. */
export const INDIVIDUAL_CLA_DOC_PATH = "docs/legal/individual-cla.md";

/** Corporate CLA — the instrument an employer executes. */
export const CORPORATE_CLA_DOC_PATH = "docs/legal/corporate-cla.md";

// Guarded CLI. True only when this file is the process entrypoint, so an
// `import` from a test or a sibling script remains side-effect free.
if (process.argv[1] && import.meta.url === new URL(`file://${process.argv[1]}`).href) {
  process.stdout.write(INDIVIDUAL_CLA_DOC_PATH);
}
