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
 * module has no side effect at all. Shell consumers that cannot import
 * TypeScript read the value via:
 *
 *   apps/web-platform/node_modules/.bin/tsx \
 *     apps/web-platform/scripts/cla-evidence/cla-doc-path.ts [corporate]
 *
 * `cla-evidence.yml` is NOT one of them. It carries the ICLA path as a
 * job-level `env:` literal pinned to this module by a guard
 * (test/cla-evidence/cla-doc-path.test.ts), because resolving a constant at run
 * time put an npm install and a new `exit 1` on the critical path of a required
 * check to learn something a test already knows before merge.
 */
import { pathToFileURL } from "node:url";

/** Individual CLA — the instrument an individual contributor signs. */
export const INDIVIDUAL_CLA_DOC_PATH = "docs/legal/individual-cla.md";

/** Corporate CLA — the instrument an employer executes. */
export const CORPORATE_CLA_DOC_PATH = "docs/legal/corporate-cla.md";

// Guarded CLI. True only when this file is the process entrypoint, so an
// `import` from a test or a sibling script remains side-effect free.
// `new URL(\`file://${argv[1]}\`)` stood here. Measured: it agrees with
// `pathToFileURL` on spaces and on non-ASCII (both percent-encode), and
// DISAGREES on `#` and `?` — the URL parser reads those as the fragment and
// query delimiters and stops, so `/tmp/a#b/x.ts` became `file:///tmp/a#b/x.ts`
// against a real `file:///tmp/a%23b/x.ts`. The guard would then be false, the
// CLI would print nothing, and every consumer would receive an EMPTY path —
// the one output this module must never produce. `pathToFileURL` is what Node
// documents for exactly this check.
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  // `cla-doc-path.ts` -> the Individual CLA (the default: every pre-existing
  // producer wanted that one). `cla-doc-path.ts corporate` -> the Corporate CLA.
  process.stdout.write(
    process.argv[2] === "corporate" ? CORPORATE_CLA_DOC_PATH : INDIVIDUAL_CLA_DOC_PATH,
  );
}
