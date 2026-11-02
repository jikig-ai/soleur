// Source of truth: plugins/soleur/lib/c4-canonical.mjs. Byte-identical, parity-tested copy:
// apps/web-platform/lib/c4-canonical.mjs. Edit the plugin copy, then
//   cp plugins/soleur/lib/c4-canonical.mjs apps/web-platform/lib/c4-canonical.mjs
//
// Canonical on-disk format of the compiled LikeC4 model (model.likec4.json),
// shared by all three writers so they emit byte-identical files (ADR-235):
//   - plugins/soleur/scripts/render-c4-model.sh (via c4-canonical-cli.mjs)
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
//
// Relation IDs are additionally RE-KEYED to a content hash. Since likec4 1.60
// the CLI derives relation ids from the absolute workspace path, so two renders
// of identical .c4 sources at different roots differ on every relation id —
// and nothing else: a same-source two-path diff moves only the `relations` map
// keys, each relation's `id` field, and `views[*].edges[*].relations[]`
// referents. Without a re-key the committed artifact can never byte-match a
// render at CI's checkout path (#11915). The new id is a 64-bit FNV-1a hash
// (base36) of the relation's content minus `id`; element ids, edge ids and all
// other fields stay as rendered. A repeated content hash (duplicate relations,
// or a freak collision) is disambiguated with a `-N` suffix in insertion order,
// which is deterministic for a given input.

const FNV_OFFSET = 0xcbf29ce484222325n;
const FNV_PRIME = 0x100000001b3n;
const FNV_MASK = 0xffffffffffffffffn;

function fnv1a64Base36(str) {
  let h = FNV_OFFSET;
  for (let i = 0; i < str.length; i++) {
    h = (h ^ BigInt(str.charCodeAt(i))) * FNV_PRIME & FNV_MASK;
  }
  return h.toString(36);
}

function rekeyRelations(model) {
  const relations = model.relations;
  if (relations === null || typeof relations !== "object" || Array.isArray(relations)) {
    return;
  }
  const idMap = new Map();
  const seen = new Map();
  const next = Object.create(null);
  for (const [oldId, rel] of Object.entries(relations)) {
    if (rel === null || typeof rel !== "object" || Array.isArray(rel)) {
      next[oldId] = rel;
      continue;
    }
    const { id: oldRelId, ...content } = rel;
    const base = fnv1a64Base36(JSON.stringify(content));
    const n = (seen.get(base) ?? 0) + 1;
    seen.set(base, n);
    const newId = n === 1 ? base : `${base}-${n}`;
    idMap.set(oldId, newId);
    if (typeof oldRelId === "string") idMap.set(oldRelId, newId);
    if (Object.prototype.hasOwnProperty.call(rel, "id")) rel.id = newId;
    next[newId] = rel;
  }
  model.relations = next;
  const views = model.views;
  if (views === null || typeof views !== "object" || Array.isArray(views)) {
    return;
  }
  for (const view of Object.values(views)) {
    if (view === null || typeof view !== "object" || !Array.isArray(view.edges)) {
      continue;
    }
    for (const edge of view.edges) {
      if (edge !== null && typeof edge === "object" && Array.isArray(edge.relations)) {
        edge.relations = edge.relations.map((r) => idMap.get(r) ?? r);
      }
    }
  }
}

/**
 * @param {string} json raw `likec4 export json` output (or an already-canonical file)
 * @returns {string} canonical bytes: one value per line, no indentation, trailing "\n"
 */
export function canonicalizeC4Model(json) {
  const model = JSON.parse(json);
  if (model === null || typeof model !== "object" || Array.isArray(model)) {
    throw new TypeError("c4 model must be a JSON object");
  }
  rekeyRelations(model);
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
