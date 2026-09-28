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
    // Never follows a symlink (a `..` link would loop), but LISTS it, so a guard that reads the
    // entry either gets the target's content or an unreadable-path it must fail closed on.
    listFiles: (dir) => {
      const out: string[] = [];
      const rec = (d: string): void => {
        for (const e of readdirSync(d, { withFileTypes: true })) {
          if (e.name === "node_modules") continue;
          const p = join(d, e.name);
          if (e.isSymbolicLink() || e.isFile()) out.push(p);
          else if (e.isDirectory()) rec(p);
        }
      };
      if (existsSync(dir)) rec(dir);
      return out;
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

// Parses are memoized by path AND source text: fixture filesystems reuse one path with different
// contents, so a path-only key would hand a guard a stale tree and a silent false pass.
const PARSE_CACHE = new Map<string, ts.SourceFile>();

export function parseModule(file: string, src: string): ts.SourceFile {
  const hit = PARSE_CACHE.get(file);
  if (hit && hit.text === src) return hit;
  const sf = ts.createSourceFile(
    file,
    src,
    ts.ScriptTarget.Latest,
    true,
    file.endsWith(".tsx") ? ts.ScriptKind.TSX : file.endsWith(".ts") ? ts.ScriptKind.TS : ts.ScriptKind.JS,
  );
  PARSE_CACHE.set(file, sf);
  return sf;
}

export function isImportOrRequireCall(n: ts.Node): n is ts.CallExpression {
  return (
    ts.isCallExpression(n) &&
    (n.expression.kind === ts.SyntaxKind.ImportKeyword || (ts.isIdentifier(n.expression) && n.expression.text === "require"))
  );
}

export interface EdgeBinding {
  local: string;
  imported: string;
  typeOnly: boolean;
}

/** One module-loading construct. Every guard reads imports through this one extractor. */
export interface ModuleEdge {
  form: "import" | "export" | "import-equals" | "call";
  /** The literal specifier, or null for a non-literal `import()`/`require()`. */
  spec: string | null;
  /** Source text of a non-literal call argument (comments excluded); "" otherwise. */
  argText: string;
  pos: number;
  /** `import type …` / `export type …` — erased as a whole. */
  typeOnly: boolean;
  /** `import "x"` with no clause. */
  sideEffect: boolean;
  defaultLocal: string | null;
  /** `import * as x`, `export * as x`, `import x = require()`. */
  namespaceLocal: string | null;
  /** `export * from`. */
  starExport: boolean;
  named: EdgeBinding[];
}

const EDGE_CACHE = new WeakMap<ts.SourceFile, ModuleEdge[]>();

export function moduleEdges(sf: ts.SourceFile): ModuleEdge[] {
  const cached = EDGE_CACHE.get(sf);
  if (cached) return cached;
  const out: ModuleEdge[] = [];
  const base = (form: ModuleEdge["form"], spec: string | null, pos: number): ModuleEdge => ({
    form,
    spec,
    argText: "",
    pos,
    typeOnly: false,
    sideEffect: false,
    defaultLocal: null,
    namespaceLocal: null,
    starExport: false,
    named: [],
  });
  const visit = (n: ts.Node): void => {
    if (ts.isImportDeclaration(n) && ts.isStringLiteral(n.moduleSpecifier)) {
      const e = base("import", n.moduleSpecifier.text, n.getStart(sf));
      const c = n.importClause;
      e.sideEffect = !c;
      e.typeOnly = !!c?.isTypeOnly;
      e.defaultLocal = c?.name?.text ?? null;
      const nb = c?.namedBindings;
      if (nb && ts.isNamespaceImport(nb)) e.namespaceLocal = nb.name.text;
      if (nb && ts.isNamedImports(nb)) {
        e.named = nb.elements.map((el) => ({ local: el.name.text, imported: (el.propertyName ?? el.name).text, typeOnly: el.isTypeOnly }));
      }
      out.push(e);
    } else if (ts.isExportDeclaration(n) && n.moduleSpecifier && ts.isStringLiteral(n.moduleSpecifier)) {
      const e = base("export", n.moduleSpecifier.text, n.getStart(sf));
      e.typeOnly = n.isTypeOnly;
      const ec = n.exportClause;
      e.starExport = !ec;
      if (ec && ts.isNamespaceExport(ec)) e.namespaceLocal = ec.name.text;
      if (ec && ts.isNamedExports(ec)) {
        e.named = ec.elements.map((el) => ({ local: el.name.text, imported: (el.propertyName ?? el.name).text, typeOnly: el.isTypeOnly }));
      }
      out.push(e);
    } else if (
      ts.isImportEqualsDeclaration(n) &&
      ts.isExternalModuleReference(n.moduleReference) &&
      ts.isStringLiteral(n.moduleReference.expression)
    ) {
      const e = base("import-equals", n.moduleReference.expression.text, n.getStart(sf));
      e.namespaceLocal = n.name.text;
      out.push(e);
    } else if (isImportOrRequireCall(n)) {
      const a = n.arguments[0];
      const literal = a && (ts.isStringLiteral(a) || ts.isNoSubstitutionTemplateLiteral(a)) ? a.text : null;
      const e = base("call", literal, n.getStart(sf));
      if (literal === null) e.argText = a ? a.getText(sf) : "";
      out.push(e);
    }
    ts.forEachChild(n, visit);
  };
  visit(sf);
  EDGE_CACHE.set(sf, out);
  return out;
}

/** True when TypeScript erases the edge: every named specifier is `type`-qualified. */
function allNamedTypeOnly(e: ModuleEdge): boolean {
  if (e.defaultLocal || e.namespaceLocal || e.starExport || e.sideEffect) return false;
  return e.named.length > 0 && e.named.every((b) => b.typeOnly);
}

export type Specifier = { kind: "literal"; spec: string } | { kind: "non-literal"; argText: string; pos: number };

export function specifiersOf(sf: ts.SourceFile, opts: WalkOptions = {}): Specifier[] {
  const out: Specifier[] = [];
  for (const e of moduleEdges(sf)) {
    if (e.spec === null) {
      out.push({ kind: "non-literal", argText: e.argText, pos: e.pos });
      continue;
    }
    if ((e.form === "import" || e.form === "export") && (e.typeOnly || (opts.elideTypeOnlySpecifiers && allNamedTypeOnly(e)))) continue;
    out.push({ kind: "literal", spec: e.spec });
  }
  return out;
}

export interface WalkResult {
  reach: Set<string>;
  problems: string[];
  nonLiteral: NonLiteralImport[];
}

/** Walk from one entry, or from several at once (their closures unioned, each module visited once). */
export function walk(entry: string | readonly string[], fs: GraphFs, opts: WalkOptions = {}): WalkResult {
  const resolver = opts.resolver ?? resolveSpecifier;
  const reach = new Set<string>();
  const problems: string[] = [];
  const nonLiteral: NonLiteralImport[] = [];
  const stack = typeof entry === "string" ? [entry] : [...entry];
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
