import { readdirSync, readFileSync } from "node:fs";
import { join, relative } from "node:path";
import ts from "typescript";
import { describe, expect, it } from "vitest";

// #8211, ADR-323 Decision 9 (2026-11-10 amendment) — no production module copies process.env at module scope.
// index.ts deletes the relay hello keys from process.env at boot, but ESM imports are hoisted above that call: every
// imported module's top-level code has already run. A top-level `{ ...process.env }`, `Object.assign({}, process.env)`,
// a rest element destructured out of it (`const { A, ...rest } = process.env`), or any other call handed process.env
// therefore snapshots the keys and can pass them to a child process later. The same holds through a same-file alias
// (`const E = process.env`, `const { env } = process`, `const P = process`) and inside a function that is invoked as
// soon as it is defined (an IIFE, or `.call`/`.apply` on a function expression): both run at module load. A copy inside
// any other function body runs at call time and is fine. The TypeScript parser decides top level vs inside a function
// (comments and strings never count).
//
// Residuals (review-time, not seen here): an alias that crosses a module boundary, an object property or a function
// return (`export const E = process.env` consumed elsewhere, `const o = { e: process.env }; ({ ...o.e })`); a
// helper whose result is cached at module scope (`const SNAP = gitIsolatedEnv()`), which no syntactic scan can tell
// from a call-time read. The behavioural row for the one known instance is
// test/server/inngest/cron-content-vendor-drift-env.test.ts (it catches a cached helper result on both git spawners).

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

interface Aliases {
  /** Names bound to `process` itself (`const P = process`). */
  proc: Set<string>;
  /** Names bound to process.env (`const E = process.env`, `const { env } = process`, `const { env: E } = process`). */
  env: Set<string>;
}

const isProcess = (e: ts.Expression, al?: Aliases): boolean => {
  const x = unwrap(e);
  return (
    (ts.isIdentifier(x) && (x.text === "process" || (al?.proc.has(x.text) ?? false))) ||
    (ts.isPropertyAccessExpression(x) && x.name.text === "process")
  );
};

/** `process.env`, `process["env"]`, `globalThis.process.env`, or a same-file alias of it, under any parentheses or type assertion. */
const isProcessEnv = (e: ts.Expression, al?: Aliases): boolean => {
  const x = unwrap(e);
  if (ts.isIdentifier(x)) return al?.env.has(x.text) ?? false;
  if (ts.isPropertyAccessExpression(x)) return x.name.text === "env" && isProcess(x.expression, al);
  if (ts.isElementAccessExpression(x)) {
    const a = x.argumentExpression;
    return (ts.isStringLiteral(a) || ts.isNoSubstitutionTemplateLiteral(a)) && a.text === "env" && isProcess(x.expression, al);
  }
  return false;
};

/** The property name a binding element reads (`env` in `{ env }` and in `{ env: E }`). */
const boundProperty = (b: ts.BindingElement): string | undefined => {
  const n = b.propertyName ?? b.name;
  return ts.isIdentifier(n) || ts.isStringLiteral(n) ? n.text : undefined;
};

/**
 * A function that runs as soon as it is defined: the callee of a call or `new` (through parentheses), or the
 * receiver of an immediate `.call(...)` / `.apply(...)`. Its body runs at module load when the definition does.
 */
const isImmediatelyInvoked = (node: ts.Node): boolean => {
  if (!ts.isFunctionExpression(node) && !ts.isArrowFunction(node)) return false;
  let x: ts.Node = node;
  while (ts.isParenthesizedExpression(x.parent)) x = x.parent;
  const p = x.parent;
  if ((ts.isCallExpression(p) || ts.isNewExpression(p)) && p.expression === x) return true;
  return (
    ts.isPropertyAccessExpression(p) &&
    p.expression === x &&
    ["call", "apply"].includes(p.name.text) &&
    ts.isCallExpression(p.parent) &&
    p.parent.expression === p
  );
};

interface Copy {
  file: string;
  line: number;
  text: string;
  inFunction: boolean;
}

/**
 * Every copy of process.env in one source: a spread of it, a call that receives it as an argument, or a rest
 * element destructured out of it, also through a same-file alias of process or process.env.
 */
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
  // Pass 1: same-file aliases, by name (scope-blind, so it can only over-report). Repeated until stable so an alias
  // of an alias is followed.
  const al: Aliases = { proc: new Set(), env: new Set() };
  for (let before = -1; before !== al.proc.size + al.env.size; ) {
    before = al.proc.size + al.env.size;
    const collect = (node: ts.Node) => {
      if (ts.isVariableDeclaration(node) && node.initializer) {
        if (ts.isIdentifier(node.name)) {
          if (isProcessEnv(node.initializer, al)) al.env.add(node.name.text);
          else if (isProcess(node.initializer, al)) al.proc.add(node.name.text);
        } else if (ts.isObjectBindingPattern(node.name) && isProcess(node.initializer, al)) {
          for (const el of node.name.elements) {
            if (!el.dotDotDotToken && boundProperty(el) === "env" && ts.isIdentifier(el.name)) al.env.add(el.name.text);
          }
        }
      }
      ts.forEachChild(node, collect);
    };
    collect(sf);
  }
  // A rest element (`...rest`) of an object pattern whose source is process.env: `const { A, ...rest } = process.env`
  // or `const { env: { ...rest } } = process`.
  const restOfEnv = (el: ts.BindingElement): boolean => {
    const pattern = el.parent;
    if (!el.dotDotDotToken || !ts.isObjectBindingPattern(pattern)) return false;
    const owner = pattern.parent;
    if (ts.isVariableDeclaration(owner)) return owner.initializer !== undefined && isProcessEnv(owner.initializer, al);
    if (ts.isBindingElement(owner) && boundProperty(owner) === "env" && ts.isObjectBindingPattern(owner.parent)) {
      const decl = owner.parent.parent;
      return ts.isVariableDeclaration(decl) && decl.initializer !== undefined && isProcess(decl.initializer, al);
    }
    return false;
  };
  const visit = (node: ts.Node, inFunction: boolean) => {
    const fn = inFunction || (ts.isFunctionLike(node) && !isImmediatelyInvoked(node));
    if ((ts.isSpreadAssignment(node) || ts.isSpreadElement(node)) && isProcessEnv(node.expression, al)) record(node, fn);
    else if ((ts.isCallExpression(node) || ts.isNewExpression(node)) && (node.arguments ?? []).some((a) => isProcessEnv(a, al))) record(node, fn);
    else if (ts.isBindingElement(node) && restOfEnv(node)) record(node, fn);
    ts.forEachChild(node, (c) => visit(c, fn));
  };
  visit(sf, false);
  return out;
}

// Only a file whose raw text names `process` can hold a copy. Deliberately not narrowed to `process.env`: the
// destructured `const { env } = process` never spells that.
const MENTIONS = /\bprocess\b/;
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

  it("the detector classifies each shape at module scope and inside a function", () => {
    const src = [
      "const a = { ...process.env };",
      "const b = Object.assign({}, process.env);",
      "const c = { ...(process.env as NodeJS.ProcessEnv) };",
      "function f() { return { ...process.env, X: '1' }; }",
      "const g = () => Object.assign({}, process['env']);",
      "const h = process.env.PATH;",
      "const i = (() => ({ ...process.env }))();",
      "const j = (function () { return Object.assign({}, process.env); })();",
      "const k = (async () => ({ ...process.env }))();",
      "const l = function () { return { ...process.env }; }.call(null);",
      "const { NODE_ENV: _n, ...m } = process.env;",
      "const { env: { ...n } } = process;",
      "function o() { const { ...p } = process.env; return p; }",
      "const { env } = process; const q = { ...env };",
      "const E = process.env; const r = { ...E };",
      "const P = process; const s = { ...P.env };",
      "const t = () => (() => ({ ...process.env }))();",
    ].join("\n");
    expect(envCopies(src, "fixture.ts").map((c) => [c.line, c.inFunction])).toEqual([
      [1, false],
      [2, false],
      [3, false],
      [4, true],
      [5, true],
      [7, false], // IIFE: runs at module load
      [8, false],
      [9, false],
      [10, false], // .call on a function expression
      [11, false], // rest element of process.env
      [12, false], // rest element of the destructured env
      [13, true],
      [14, false], // through `const { env } = process`
      [15, false], // through `const E = process.env`
      [16, false], // through `const P = process`
      [17, true], // an IIFE inside a function runs at call time
    ]);
  });

  it("no production module copies process.env at module scope", () => {
    expect(COPIES.filter((c) => !c.inFunction)).toEqual([]);
  });
});
