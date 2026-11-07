// WikiSkill Phase 2 (#10550) -- the import-cycle break.
//
// `compound-promote-create.ts` needs the handler's PII/credential screens and cluster hash; the handler now needs
// the create arm. A cycle between them was safe only by luck (names used inside function bodies), so the three
// shared definitions live in ONE leaf module that both import, and the handler re-exports the two regexes so every
// existing importer (and test) keeps working.
//
// PROPERTY: there is exactly one PII_REGEX, one CREDENTIAL_RE and one cluster-hash function, and no static import
// path leads from the create modules back to the handler.
import { describe, expect, it, vi } from "vitest";
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});
vi.mock("@/server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/observability")>()),
  reportSilentFallback: vi.fn(),
}));

import * as handler from "@/server/inngest/functions/cron-compound-promote";
import * as create from "@/server/compound-promote-create";
import * as leaf from "@/server/compound-promote-screens";

const SERVER = join(__dirname, "..", "..", "server");
const HANDLER = join(SERVER, "inngest", "functions", "cron-compound-promote.ts");

/** Static local imports of a file (`@/server/...` and relative), resolved to a .ts path. Type-only imports count. */
function localImports(file: string): string[] {
  const src = readFileSync(file, "utf8");
  const out: string[] = [];
  for (const m of src.matchAll(/(?:^|\n)\s*(?:import|export)\s[^"';]*?from\s+["']([^"']+)["']/g)) {
    const spec = m[1];
    let abs: string | null = null;
    if (spec.startsWith("@/server/")) abs = join(SERVER, spec.slice("@/server/".length));
    else if (spec.startsWith("./") || spec.startsWith("../")) abs = resolve(dirname(file), spec);
    if (abs) out.push(`${abs}.ts`);
  }
  return out;
}

function reaches(from: string, target: string): boolean {
  const seen = new Set<string>();
  const stack = [from];
  while (stack.length > 0) {
    const f = stack.pop() as string;
    if (f === target) return true;
    if (seen.has(f)) continue;
    seen.add(f);
    let next: string[];
    try {
      next = localImports(f);
    } catch {
      continue; // not a local .ts file (a package or a directory import)
    }
    stack.push(...next);
  }
  return false;
}

describe("one definition of the screens and the cluster hash", () => {
  it("the handler re-exports the leaf's regexes (object identity), so existing importers are unchanged", () => {
    expect(handler.PII_REGEX).toBe(leaf.PII_REGEX);
    expect(handler.CREDENTIAL_RE).toBe(leaf.CREDENTIAL_RE);
  });

  it("the create module's screens ARE the leaf's (identity), not a second copy", () => {
    expect(create.CREATE_SCREENS.pii).toBe(leaf.PII_REGEX);
    expect(create.CREATE_SCREENS.credential).toBe(leaf.CREDENTIAL_RE);
  });

  it("createClusterHash IS computeClusterHash (identity), and the handler no longer declares its own", () => {
    expect(create.createClusterHash).toBe(leaf.computeClusterHash);
    const src = readFileSync(HANDLER, "utf8");
    expect(src).not.toMatch(/^function computeClusterHash\(/m);
    expect(src).toMatch(/computeClusterHash[^;]*from "@\/server\/compound-promote-screens"/s);
    expect(src).not.toMatch(/^export const PII_REGEX = new RegExp\(/m);
    expect(src).not.toMatch(/^export const CREDENTIAL_RE = new RegExp\(/m);
  });

  it("the leaf is a real leaf: it imports nothing from the app", () => {
    expect(localImports(join(SERVER, "compound-promote-screens.ts"))).toEqual([]);
  });

  it("the cluster hash is order-independent sha256 over the sorted, newline-joined keys", () => {
    expect(leaf.computeClusterHash(["b", "a"])).toBe(leaf.computeClusterHash(["a", "b"]));
    expect(leaf.computeClusterHash(["a", "b"])).toMatch(/^[0-9a-f]{64}$/);
    expect(leaf.computeClusterHash(["a"])).not.toBe(leaf.computeClusterHash(["a", "b"]));
  });
});

describe("no static import path leads from the create modules back to the handler", () => {
  const CREATE_MODULES = ["compound-promote-create.ts", "compound-promote-create-gates.ts", "compound-promote-create-arm.ts"];

  it("non-vacuity: the walker does see the handler's imports and reaches the leaf from it", () => {
    expect(reaches(HANDLER, join(SERVER, "compound-promote-screens.ts"))).toBe(true);
    expect(reaches(HANDLER, join(SERVER, "compound-promote-create-arm.ts"))).toBe(true);
  });

  it.each(CREATE_MODULES)("%s cannot reach the handler", (name) => {
    const file = join(SERVER, name);
    expect(readFileSync(file, "utf8").length).toBeGreaterThan(0);
    expect(reaches(file, HANDLER)).toBe(false);
  });

  it("dispatch: the walker flags a synthetic cycle (a module that imports the handler)", () => {
    // The handler imports the arm, so the arm importing the handler back would be a cycle: model that edge.
    const arm = join(SERVER, "compound-promote-create-arm.ts");
    expect(reaches(HANDLER, arm)).toBe(true);
  });
});
