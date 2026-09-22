// Source of truth: plugins/soleur/lib/c4-canonical.mjs. Byte-identical, parity-tested copy:
// apps/web-platform/lib/c4-canonical.mjs. Edit the plugin copy, then
//   cp plugins/soleur/lib/c4-canonical.mjs apps/web-platform/lib/c4-canonical.mjs
//
// Canonical on-disk format of the compiled LikeC4 model (model.likec4.json),
// shared by all three writers so they emit byte-identical files (ADR-235):
//   - scripts/regenerate-c4-model.sh            (via c4-canonical-cli.mjs)
//   - apps/web-platform/server/c4-render.ts      (via the apps/ mirror)
//   - plugins/soleur/scripts/generate-c4-from-components.ts
//
// PURE on purpose: no imports, no I/O, no import.meta. The web app bundles this
// into CommonJS (esbuild -> dist/server/index.cjs), where import.meta is
// undefined, and its tests mock node:fs/promises wholesale.
//
// Why this shape: likec4 exports one ~1.1 MB line, so any two PRs that
// regenerate it conflict. One JSON value per line lets git merge regenerations
// whose changes do not touch the same value. Every view's `hash` changes on
// almost every edit, which alone made nearly every pair conflict, so it is
// blanked. It is a content hash of the pre-layout view that nothing in
// @likec4/diagram, LikeC4Model or this repo reads, and the likec4 CLI never
// reads the exported artifact back. The key is kept (value "") because the
// ViewWithHash type declares it.

/**
 * @param {string} json raw `likec4 export json` output (or an already-canonical file)
 * @returns {string} canonical bytes: one value per line, no indentation, trailing "\n"
 */
export function canonicalizeC4Model(json) {
  const model = JSON.parse(json);
  if (model === null || typeof model !== "object" || Array.isArray(model)) {
    throw new TypeError("c4 model must be a JSON object");
  }
  const views = model.views;
  if (views !== null && typeof views === "object" && !Array.isArray(views)) {
    for (const view of Object.values(views)) {
      if (view !== null && typeof view === "object" && Object.prototype.hasOwnProperty.call(view, "hash")) {
        view.hash = "";
      }
    }
  }
  // Strip only the indentation that FOLLOWS a "\n". A JSON string can never
  // contain a raw "\n" (stringify escapes it), so every "\n" is structural. Do
  // NOT use /^ +/gm: with the m flag, ^ also matches after U+2028/U+2029, which
  // JSON.stringify leaves raw inside strings, so it would eat spaces in a value.
  return JSON.stringify(model, null, 1).replace(/\n +/g, "\n") + "\n";
}
