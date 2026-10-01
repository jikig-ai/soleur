import { beforeAll, describe, it, expect } from "vitest";
import fs from "node:fs";
import path from "node:path";
import { compile } from "@tailwindcss/node";
import postcss from "postcss";
import type { AtRule, Root, Rule } from "postcss";

// Guard 2 (caller-utilities-win contract), compiled-CSS half.
//
// `.soleur-btn` / `.soleur-btn-pad` must sit in `@layer components` so that any
// caller utility (`px-3`, `w-[36px]`, `rounded-md`, `flex`) — which Tailwind v4
// emits in `@layer utilities`, declared AFTER components in the layer order
// statement — beats the base box regardless of emit order.
//
// The assertions walk the postcss AST (`rule.parent` up to the enclosing
// `@layer` at-rule). A string/regex scan of the compiled text cannot tell a
// rule inside `@layer components { … }` from one after it, so it would stay
// green under mutation 2 (moving the rule out of the layer).

const APP_DIR = path.resolve(__dirname, "../..");
const GLOBALS = path.join(APP_DIR, "app/globals.css");

async function compileCss(
  css: string,
  candidates: string[] = [],
): Promise<Root> {
  const compiler = await compile(css, {
    base: APP_DIR,
    onDependency: () => {},
  });
  const out = compiler.build(candidates);
  return postcss.parse(out);
}

function enclosingLayer(node: Rule): string | null {
  let cur: Rule["parent"] | undefined = node.parent;
  while (cur) {
    if (cur.type === "atrule" && (cur as AtRule).name === "layer") {
      return (cur as AtRule).params.trim();
    }
    cur = cur.parent as Rule["parent"] | undefined;
  }
  return null;
}

/** Layer name for every rule whose selector is exactly `.<cls>`; null = unlayered. */
function layersOf(root: Root, cls: string): Array<string | null> {
  const layers: Array<string | null> = [];
  root.walkRules((rule) => {
    const sels = rule.selectors ?? [rule.selector];
    if (sels.some((s) => s.trim() === `.${cls}`)) {
      layers.push(enclosingLayer(rule));
    }
  });
  return layers;
}

function hasDecl(root: Root, cls: string, prop: string): boolean {
  let found = false;
  root.walkRules((rule) => {
    const sels = rule.selectors ?? [rule.selector];
    if (!sels.some((s) => s.trim() === `.${cls}`)) return;
    rule.walkDecls(prop, () => {
      found = true;
    });
  });
  return found;
}

describe("Button base box cascade layer (compiled app/globals.css)", () => {
  let root: Root;

  // Compiled at run time, never a cached copy, so a stale-copy mutation
  // cannot keep this green.
  beforeAll(async () => {
    const src = fs.readFileSync(GLOBALS, "utf8");
    root = await compileCss(src, ["px-3"]);
  });

  it("compiles app/globals.css to a non-empty stylesheet", () => {
    expect(root.nodes.length).toBeGreaterThan(0);
  });

  it("declares the layer order statement theme, base, components, utilities", () => {
    const orders: string[][] = [];
    root.walkAtRules("layer", (at) => {
      if (!at.nodes) {
        orders.push(at.params.split(",").map((s) => s.trim()));
      }
    });
    const order = orders.find(
      (o) => o.includes("components") && o.includes("utilities"),
    );
    expect(order, "no `@layer a, b, c;` order statement found").toBeDefined();
    expect(order).toEqual(["theme", "base", "components", "utilities"]);
  });

  it(".soleur-btn exists, only inside @layer components, with the base-box declarations", () => {
    expect(layersOf(root, "soleur-btn")).toEqual(["components"]);
    for (const prop of [
      "display",
      "align-items",
      "justify-content",
      "gap",
      "border-radius",
      "font-size",
      "font-weight",
    ]) {
      expect(hasDecl(root, "soleur-btn", prop), `soleur-btn lacks ${prop}`).toBe(
        true,
      );
    }
  });

  it(".soleur-btn carries NO padding (icon-only buttons must not be padded)", () => {
    for (const prop of [
      "padding",
      "padding-inline",
      "padding-block",
      "padding-left",
      "padding-right",
      "padding-top",
      "padding-bottom",
    ]) {
      expect(hasDecl(root, "soleur-btn", prop), `soleur-btn has ${prop}`).toBe(
        false,
      );
    }
  });

  it(".soleur-btn-pad exists only inside @layer components, with padding", () => {
    expect(layersOf(root, "soleur-btn-pad")).toEqual(["components"]);
    expect(hasDecl(root, "soleur-btn-pad", "padding-inline")).toBe(true);
    expect(hasDecl(root, "soleur-btn-pad", "padding-block")).toBe(true);
  });

  it("a caller utility (px-3) sits in @layer utilities, after components in the order statement", () => {
    expect(layersOf(root, "px-3")).toEqual(["utilities"]);
  });

  it("CONTROL: a top-level .soleur-btn is flagged by the same helper (the guard can go RED)", async () => {
    const control = await compileCss(
      `@import "tailwindcss";\n.soleur-btn { padding-inline: 1.5rem; }\n`,
    );
    expect(layersOf(control, "soleur-btn")).toEqual([null]);
    expect(layersOf(control, "soleur-btn")).not.toEqual(["components"]);
  });

  it("CONTROL: a .soleur-btn moved into @layer utilities is flagged too", async () => {
    const control = await compileCss(
      `@import "tailwindcss";\n@layer utilities { .soleur-btn { padding-inline: 1.5rem; } }\n`,
    );
    expect(layersOf(control, "soleur-btn")).toEqual(["utilities"]);
  });
});
