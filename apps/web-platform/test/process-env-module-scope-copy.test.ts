import { readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";
import ts from "typescript";
import { describe, expect, it } from "vitest";

// #8211, ADR-323 Decision 9 (2026-11-10 amendment) — no production module copies process.env at module scope.
// index.ts deletes the relay hello keys from process.env at boot, but ESM imports are hoisted above that call: every
// imported module's top-level code has already run. A top-level `{ ...process.env }`, `Object.assign({}, process.env)`
// or any other call handed process.env therefore snapshots the keys and can pass them to a child process later.
// Copies inside a function body run at call time and are fine. The TypeScript parser decides top level vs inside a
// function (comments and strings never count). The behavioural row for the one known instance is
// test/server/inngest/cron-content-vendor-drift-env.test.ts (it also catches a cached helper result, which no
// syntactic scan can see).

const ROOT = join(__dirname, "..");
const PROD_DIRS = ["server", "lib", "app"];

function walk(dir: string): string[] {
  const out: string[] = [];
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    if (e.name === "node_modules" || e.name.startsWith(".")) continue;
    const p = join(dir, e.name);
    if (e.isDirectory()) out.push(...walk(p));
    else if (/\.(tsx?|mjs)$/.test(e.name) && !/\.d\.ts$/.test(e.name) && !/\.test\.(tsx?|mjs)$/.test(e.name)) out.push(p);
  }
  return out;
}

const ALL_FILES = PROD_DIRS.flatMap((d) => walk(join(ROOT, d)));

const unwrap = (e: ts.Expression): ts.Expression => {
  let x = e;
  while (
    ts.isParenthesizedExpression(x) ||
    ts.isAsExpression(x) ||
    ts.isNonNullExpression(x) ||
    ts.isSatisfiesExpression(x) ||
    ts.isTypeAssertionExpression(x)
  ) {
    x = x.expression;
  }
  return x;
};

const isProcess = (e: ts.Expression): boolean => {
  const x = unwrap(e);
  return (ts.isIdentifier(x) && x.text === "process") || (ts.isPropertyAccessExpression(x) && x.name.text === "process");
};

/** `process.env`, `process["env"]`, `globalThis.process.env`, under any parentheses or type assertion. */
const isProcessEnv = (e: ts.Expression): boolean => {
  const x = unwrap(e);
  if (ts.isPropertyAccessExpression(x)) return x.name.text === "env" && isProcess(x.expression);
  if (ts.isElementAccessExpression(x)) {
    const a = x.argumentExpression;
    return (ts.isStringLiteral(a) || ts.isNoSubstitutionTemplateLiteral(a)) && a.text === "env" && isProcess(x.expression);
  }
  return false;
};

interface Copy {
  file: string;
  line: number;
  text: string;
  inFunction: boolean;
}

/** Every copy of process.env in one source: a spread of it, or a call that receives it as an argument. */
function envCopies(src: string, file: string): Copy[] {
  const sf = ts.createSourceFile(file, src, ts.ScriptTarget.Latest, true, file.endsWith(".tsx") ? ts.ScriptKind.TSX : undefined);
  const out: Copy[] = [];
  const record = (node: ts.Node, inFunction: boolean) =>
    out.push({
      file,
      line: sf.getLineAndCharacterOfPosition(node.getStart(sf)).line + 1,
      text: node.getText(sf).replace(/\s+/g, " ").slice(0, 100),
      inFunction,
    });
  const visit = (node: ts.Node, inFunction: boolean) => {
    const fn = inFunction || ts.isFunctionLike(node);
    if ((ts.isSpreadAssignment(node) || ts.isSpreadElement(node)) && isProcessEnv(node.expression)) record(node, fn);
    else if ((ts.isCallExpression(node) || ts.isNewExpression(node)) && (node.arguments ?? []).some(isProcessEnv)) record(node, fn);
    ts.forEachChild(node, (c) => visit(c, fn));
  };
  visit(sf, false);
  return out;
}

// Only a file whose raw text names process.env (in any spelling the parser accepts) can hold a copy.
const MENTIONS = /process\s*[.[]\s*["'`]?env/;
const COPIES: Copy[] = ALL_FILES.flatMap((p) => {
  const raw = readFileSync(p, "utf8");
  return MENTIONS.test(raw) ? envCopies(raw, relative(ROOT, p)) : [];
});

describe("no module-scope copy of process.env in production code (#8211)", () => {
  it("vacuity floor: the walk sees the production tree and the detector finds the known call-time copies", () => {
    expect(ALL_FILES.length).toBeGreaterThan(100);
    expect(ALL_FILES.some((f) => f.endsWith(".tsx"))).toBe(true);
    const vendorDrift = COPIES.filter((c) => c.file === "server/inngest/functions/cron-content-vendor-drift.ts");
    expect(vendorDrift.some((c) => c.inFunction && c.text.startsWith("...process.env"))).toBe(true);
  });

  it("the detector classifies the three shapes at module scope and inside a function", () => {
    const src = [
      "const a = { ...process.env };",
      "const b = Object.assign({}, process.env);",
      "const c = { ...(process.env as NodeJS.ProcessEnv) };",
      "function f() { return { ...process.env, X: '1' }; }",
      "const g = () => Object.assign({}, process['env']);",
      "const h = process.env.PATH;",
    ].join("\n");
    expect(envCopies(src, "fixture.ts").map((c) => [c.line, c.inFunction])).toEqual([
      [1, false],
      [2, false],
      [3, false],
      [4, true],
      [5, true],
    ]);
  });

  it("no production module copies process.env at module scope", () => {
    expect(COPIES.filter((c) => !c.inFunction)).toEqual([]);
  });
});
