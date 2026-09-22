import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Mirror guard (#8542): lib/c4-canonical.mjs is a byte-identical copy of
// plugins/soleur/lib/c4-canonical.mjs. The app's Docker build context is
// apps/web-platform only, and the plugin runs from its install root in customer
// repos where apps/ does not exist, so no single path reaches all three writers
// of model.likec4.json. If the copies drift, the app and the repo/plugin
// writers emit different bytes and rewrite each other's file on every save.
// The plugin bun suite (c4-canonical.test.ts) carries the same row, so a PR
// touching either copy runs a parity check.
const APP = path.resolve(__dirname, "..");
const MIRROR = path.join(APP, "lib/c4-canonical.mjs");
const SOURCE = path.resolve(APP, "../../plugins/soleur/lib/c4-canonical.mjs");

describe("c4-canonical mirror", () => {
  it("is byte-identical to the plugin source of truth", () => {
    expect(SOURCE).not.toBe(MIRROR);
    expect(readFileSync(MIRROR, "utf8")).toBe(readFileSync(SOURCE, "utf8"));
  });
});
