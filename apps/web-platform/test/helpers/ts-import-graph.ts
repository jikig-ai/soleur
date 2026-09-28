// Transitive TypeScript import walker, shared by two static guards:
//   - test/server/watchdog-dispatch-clock.test.ts (Guard 2: the clock never
//     reaches server/inngest/), and
//   - test/server/inngest/execution-placement.test.ts (#7230: the placement
//     rule and the anti-circularity corollary).
//
// It parses every module with the TypeScript compiler and follows static
// import/export-from, `import x = require()`, `require()` and `import()` in any
// position or quoting. It FAILS CLOSED: a local specifier that does not resolve,
// or an `import()`/`require()` with a non-literal argument, is a problem rather
// than a silently dropped edge. Whole-clause type-only imports are erased and
// skipped, as TypeScript erases them.
//
// The filesystem is a REQUIRED seam (`GraphFs`) so a guard can be driven over an
// in-memory synthesized fixture as well as the real tree. Every option defaults
// to the behaviour the clock guard was written against.

import { existsSync, readdirSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import ts from "typescript";

export interface GraphFs {
  /** File contents, or null when the path is not a readable file. */
  readFile(path: string): string | null;
  exists(path: string): boolean;
  /** Every file under `dir`, recursively, as absolute paths. */
  listFiles(dir: string): string[];
  /** The app root that `@/` specifiers resolve against. */
  appRoot: string;
}

export interface NonLiteralImport {
  file: string;
  /** Source text of the non-literal argument, comments excluded. */
  argText: string;
  pos: number;
}

export interface WalkOptions {
  /**
   * Drop an import/export-from edge whose every named specifier is
   * `type`-qualified (`import { type X }`), as TypeScript erases it. A clause
   * carrying a default or namespace binding is never elided.
   */
  elideTypeOnlySpecifiers?: boolean;
  /**
   * Record a non-literal `import()`/`require()` in `nonLiteral` instead of
   * reporting it as a problem, so a caller can key an exact exemption by its
   * argument.
   */
  recordDynamicImportArgs?: boolean;
  /** Replace specifier resolution (a harness seam; defaults to `resolveSpecifier`). */
  resolver?: (spec: string, fromFile: string, fs: GraphFs) => string | null | "unresolved";
}

export const SOURCE_EXTS = [".ts", ".tsx", ".js", ".mjs", ".cjs"];

export function realFs(appRoot: string): GraphFs {
  return {
    appRoot,
    readFile: (p) => {
      try {
        return readFileSync(p, "utf-8");
      } catch {
        return null;
      }
    },
    exists: (p) => existsSync(p),
    listFiles: (dir) => {
      if (!existsSync(dir)) return [];
      return (readdirSync(dir, { recursive: true, withFileTypes: true }) as import("node:fs").Dirent[])
        .filter((d) => d.isFile())
        .map((d) => join(d.parentPath, d.name))
        .filter((p) => !p.includes("/node_modules/"));
    },
  };
}

export function resolveSpecifier(spec: string, fromFile: string, fs: GraphFs): string | null | "unresolved" {
  let base: string;
  if (spec.startsWith("@/")) base = join(fs.appRoot, spec.slice(2));
  else if (spec.startsWith(".")) base = resolve(dirname(fromFile), spec);
  else return null; // bare package — outside the property
  const stem = base.replace(/\.(js|mjs|cjs)$/, "");
  const candidates = [
    base,
    ...SOURCE_EXTS.map((e) => `${stem}${e}`),
    ...SOURCE_EXTS.map((e) => join(base, `index${e}`)),
  ];
  for (const cand of candidates) {
    if (fs.exists(cand) && SOURCE_EXTS.some((e) => cand.endsWith(e))) return cand;
  }
  return "unresolved";
}

export function parseModule(file: string, src: string): ts.SourceFile {
  return ts.createSourceFile(
    file,
    src,
    ts.ScriptTarget.Latest,
    true,
    file.endsWith(".tsx") ? ts.ScriptKind.TSX : file.endsWith(".ts") ? ts.ScriptKind.TS : ts.ScriptKind.JS,
  );
}

/** True when a named-import/export clause is erased by TypeScript. */
function allNamedSpecifiersTypeOnly(n: ts.ImportDeclaration | ts.ExportDeclaration): boolean {
  if (ts.isImportDeclaration(n)) {
    const c = n.importClause;
    if (!c || c.name || !c.namedBindings || !ts.isNamedImports(c.namedBindings)) return false;
    const els = c.namedBindings.elements;
    return els.length > 0 && els.every((e) => e.isTypeOnly);
  }
  const ec = n.exportClause;
  if (!ec || !ts.isNamedExports(ec)) return false;
  return ec.elements.length > 0 && ec.elements.every((e) => e.isTypeOnly);
}

export type Specifier = { kind: "literal"; spec: string } | { kind: "non-literal"; argText: string; pos: number };

export function specifiersOf(sf: ts.SourceFile, opts: WalkOptions = {}): Specifier[] {
  const out: Specifier[] = [];
  const visit = (n: ts.Node): void => {
    if (
      (ts.isImportDeclaration(n) || ts.isExportDeclaration(n)) &&
      n.moduleSpecifier &&
      ts.isStringLiteral(n.moduleSpecifier)
    ) {
      const typeOnly = ts.isImportDeclaration(n) ? !!n.importClause?.isTypeOnly : n.isTypeOnly;
      const elided = !!opts.elideTypeOnlySpecifiers && allNamedSpecifiersTypeOnly(n);
      if (!typeOnly && !elided) out.push({ kind: "literal", spec: n.moduleSpecifier.text });
    } else if (
      ts.isImportEqualsDeclaration(n) &&
      ts.isExternalModuleReference(n.moduleReference) &&
      ts.isStringLiteral(n.moduleReference.expression)
    ) {
      out.push({ kind: "literal", spec: n.moduleReference.expression.text });
    } else if (
      ts.isCallExpression(n) &&
      (n.expression.kind === ts.SyntaxKind.ImportKeyword ||
        (ts.isIdentifier(n.expression) && n.expression.text === "require"))
    ) {
      const a = n.arguments[0];
      if (a && (ts.isStringLiteral(a) || ts.isNoSubstitutionTemplateLiteral(a))) out.push({ kind: "literal", spec: a.text });
      else out.push({ kind: "non-literal", argText: a ? a.getText(sf) : "", pos: n.getStart(sf) });
    }
    ts.forEachChild(n, visit);
  };
  visit(sf);
  return out;
}

export interface WalkResult {
  reach: Set<string>;
  problems: string[];
  nonLiteral: NonLiteralImport[];
}

export function walk(entry: string, fs: GraphFs, opts: WalkOptions = {}): WalkResult {
  const resolver = opts.resolver ?? resolveSpecifier;
  const reach = new Set<string>();
  const problems: string[] = [];
  const nonLiteral: NonLiteralImport[] = [];
  const stack = [entry];
  while (stack.length) {
    const f = stack.pop()!;
    if (reach.has(f)) continue;
    reach.add(f);
    const src = fs.readFile(f);
    if (src === null) {
      problems.push(`${f}: unreadable module`);
      continue;
    }
    for (const s of specifiersOf(parseModule(f, src), opts)) {
      if (s.kind === "non-literal") {
        if (opts.recordDynamicImportArgs) nonLiteral.push({ file: f, argText: s.argText, pos: s.pos });
        else problems.push(`${f}: non-literal import()/require()`);
        continue;
      }
      const target = resolver(s.spec, f, fs);
      if (target === "unresolved") problems.push(`${f}: unresolved local specifier ${s.spec}`);
      else if (target) stack.push(target);
    }
  }
  return { reach, problems, nonLiteral };
}

export function relTo(fs: GraphFs, p: string): string {
  return p.startsWith(`${fs.appRoot}/`) ? p.slice(fs.appRoot.length + 1) : p;
}
