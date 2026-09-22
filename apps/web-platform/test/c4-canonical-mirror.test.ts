import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";
import { LikeC4Model } from "@likec4/core/model";
import type { LayoutedLikeC4ModelData } from "@likec4/core/types";
import { canonicalizeC4Model } from "@/lib/c4-canonical.mjs";

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

describe("canonical model is still a valid LikeC4 model", () => {
  // The viewer (components/kb/c4-shared.tsx) builds the model exactly this way.
  // Blank view hashes must not break it: @likec4/core reads no view hash, and
  // this row fails if a future @likec4 upgrade starts to.
  it("LikeC4Model.create accepts the canonicalized committed artifact", () => {
    const raw = readFileSync(
      path.resolve(APP, "../../knowledge-base/engineering/architecture/diagrams/model.likec4.json"),
      "utf8",
    );
    const dump = JSON.parse(canonicalizeC4Model(raw));
    expect(Object.values<{ hash: string }>(dump.views).every((v) => v.hash === "")).toBe(true);
    const model = LikeC4Model.create(dump as unknown as LayoutedLikeC4ModelData);
    expect([...model.views()].length).toBe(Object.keys(dump.views).length);
    expect([...model.elements()].length).toBeGreaterThan(0);
  });
});
