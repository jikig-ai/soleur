// Shared engine-floor guard for pdfjs-dist–dependent test suites.
//
// pdfjs-dist@5.4.296 calls `process.getBuiltinModule` during module init
// (legacy/build/pdf.mjs:5465); that builtin landed in Node 22.3 / 20.16.
// Below the floor the lazy `await import("pdfjs-dist/legacy/build/pdf.mjs")`
// throws and every assertion in the suite resolves to `lazy_import_failed`,
// masking the real contract.
//
// Effective floor: `>=22.3.0 OR (>=20.16.0 AND <21)`. The `apps/web-platform/
// package.json` `engines.node` field is `">=20.16.0 || >=22.3.0"`, which
// npm-semver evaluates as "matches if either clause matches" — that admits
// Node 21.x as a side-effect of the 20.16+ clause. The runtime floor enforced
// here is narrower (rejects 21.x) because Node 21 reached EOL before
// `process.getBuiltinModule` was back-ported. `apps/web-platform/.nvmrc`
// pins `22.3.0` to keep contributor workstations on the upper line.
//
// Use a regex match over `process.versions.node` (NOT `split(".").map(Number)`
// which returns NaN on prerelease tags like `22.3.0-nightly...`).
//
// Vitest discovery: this file sits under `test/helpers/` (no `.test.` infix)
// and cannot match `vitest.config.ts`'s `include: ["test/**/*.test.ts"]` —
// same precedent as `test/helpers/bundled-server.ts`.

export function supportsPdfjsEngineFloor(): boolean {
  const match = process.versions.node.match(/^(\d+)\.(\d+)\./);
  if (!match) return true; // Unknown shape (bun/deno emulation) — fail open.
  const maj = Number(match[1]);
  const min = Number(match[2]);
  if (!Number.isFinite(maj) || !Number.isFinite(min)) return true;
  if (maj >= 23) return true;
  if (maj === 22) return min >= 3;
  if (maj === 21) return false;
  if (maj === 20) return min >= 16;
  return false;
}

/**
 * `true` when the current Node runtime is below the pdfjs-dist@5 engine
 * floor (Node 22.3+ or 20.16+ on the 20-line). Pass to `describe.skipIf(...)`
 * so suites short-circuit cleanly on Node <22.3 dev workstations.
 */
export const BELOW_PDFJS_ENGINES_FLOOR = !supportsPdfjsEngineFloor();

function pdfjsEngineFloorDiagnostic(testFileLabel: string): string {
  return (
    `[${testFileLabel}] Node ${process.versions.node} is below the ` +
    `pdfjs-dist engines floor (>=22.3.0 or >=20.16.0). pdfjs-dist@5 calls ` +
    `process.getBuiltinModule (legacy/build/pdf.mjs:5465) which lands at ` +
    `those versions; below the floor the lazy import throws and every test ` +
    `in this file would resolve to {error: "lazy_import_failed"}. Run your ` +
    `version manager's .nvmrc reader (nvm use, fnm use, asdf install, ` +
    `volta pin) or install Node 22.3+ to run this test. See ` +
    `knowledge-base/project/learnings/2026-04-18-pdfjs-metadata-on-node-without-canvas.md.`
  );
}

// Idempotent module-init side-effect: throw on CI (so a misconfigured runner
// cannot ship a vacuous green), stderr-write on dev (single yellow skip).
export function emitPdfjsEngineFloorDiagnostic(testFileLabel: string): void {
  if (!BELOW_PDFJS_ENGINES_FLOOR) return;
  const diagnostic = pdfjsEngineFloorDiagnostic(testFileLabel);
  if (process.env.CI) {
    throw new Error(diagnostic);
  }
  process.stderr.write(diagnostic + "\n");
}
