/**
 * Shared source-scanning helpers for the approval sentinels.
 *
 *   - `stripComments` (decide-boundary, runner-census, tools-census, cc-push-boundaries, workspace-head): a comment stripper
 *     that keeps string/template content intact (a URL with `//` inside a string is code, not a comment).
 *   - `censusSource`, `callSites`, `codeOffsets` (render-sink-scan, #9601): a role-classified census of module edges and call
 *     sites built on the TypeScript parser (`ts.createSourceFile`, parse only, no program). A hand-rolled lexer desynced on
 *     an apostrophe in JSX text and on a regex literal after `)`, so comments, strings, templates, JSX text and regexes are
 *     now whatever the real grammar says they are.
 */
import ts from "typescript";

/** Blank out comments, keeping string/template/regex-free-enough code intact. Newlines are preserved. */
export function stripComments(src: string): string {
  let out = "";
  let i = 0;
  const n = src.length;
  while (i < n) {
    const c = src[i];
    const d = src[i + 1];
    if (c === "/" && d === "/") {
      while (i < n && src[i] !== "\n") i++;
    } else if (c === "/" && d === "*") {
      i += 2;
      while (i < n && !(src[i] === "*" && src[i + 1] === "/")) {
        if (src[i] === "\n") out += "\n";
        i++;
      }
      i += 2;
    } else if (c === '"' || c === "'" || c === "`") {
      const quote = c;
      out += c;
      i++;
      while (i < n && src[i] !== quote) {
        if (src[i] === "\\") {
          out += src[i];
          i++;
        }
        if (i < n) out += src[i];
        i++;
      }
      if (i < n) out += quote;
      i++;
    } else {
      out += c;
      i++;
    }
  }
  return out;
}

// ---------------------------------------------------------------------------------------------------------------------
// #9601: a role-classified census of the module edges and call sites of a named export, over the TypeScript AST. An aliased
// import, `export { x } from`, `export *`, `import * as R` with `R.x(`, a dynamic `import()`, a `require()` and an
// `import x = require()` are each reported under their own role instead of slipping past a substring match. Anything the
// classifier cannot place is `other`, which callers pin to zero (the red `unclassified` bucket).
//
// Named residual: a computed-name access (`R["render" + "ApprovalView"]`) and a dynamic `import(expr)` with a non-literal
// specifier are invisible to a static scan.
// ---------------------------------------------------------------------------------------------------------------------

export type CensusRole =
  | "import"
  | "type-import"
  | "reexport"
  | "namespace-import"
  | "namespace-member"
  | "dynamic-import"
  | "require"
  | "call"
  | "definition"
  | "other";

export interface CensusHit {
  /** `id`: the bare identifier; `edge`: a module edge whose specifier resolves to a target module path. */
  kind: "id" | "edge";
  role: CensusRole;
  /** For an edge: the resolved target path (no extension), relative to apps/web-platform. */
  resolved?: string;
  pos: number;
}

/** Resolve an import specifier from `fromFile` (a path relative to apps/web-platform) to a path without extension, or null for a package. */
export function resolveSpecifier(fromFile: string, spec: string): string | null {
  let p: string;
  if (spec.startsWith("@/")) p = spec.slice(2);
  else if (spec.startsWith("./") || spec.startsWith("../")) {
    const parts = fromFile.split("/").slice(0, -1);
    for (const seg of spec.split("/")) {
      if (seg === "." || seg === "") continue;
      if (seg === "..") parts.pop();
      else parts.push(seg);
    }
    p = parts.join("/");
  } else return null;
  return p.replace(/\.(tsx?|jsx?|mjs|cjs|mts|cts)$/, "");
}

function scriptKindFor(file: string): ts.ScriptKind {
  if (/\.tsx$/.test(file)) return ts.ScriptKind.TSX;
  if (/\.jsx$/.test(file)) return ts.ScriptKind.JSX;
  if (/\.(js|mjs|cjs)$/.test(file)) return ts.ScriptKind.JS;
  return ts.ScriptKind.TS;
}

/** Parse only (no program, no type check). `file` picks the script kind (a `.tsx` parses JSX text, so an apostrophe in it is text). */
export function parseSource(src: string, file: string): ts.SourceFile {
  return ts.createSourceFile(file, src, ts.ScriptTarget.Latest, /* setParentNodes */ true, scriptKindFor(file));
}

const stringValue = (n: ts.Node | undefined): string | null =>
  n && (ts.isStringLiteral(n) || ts.isNoSubstitutionTemplateLiteral(n)) ? n.text : null;

/**
 * Census of one source file. `ident` is the exported name to follow (for example `renderApprovalView`), `targets` the module
 * paths (no extension, relative to apps/web-platform) whose edges to report. A local alias of `ident` (an `as` import) is
 * followed too: a call through it is a `call`, any other use of it is `other`.
 */
export function censusSource(src: string, file: string, ident: string, targets: readonly string[]): CensusHit[] {
  const sf = parseSource(src, file);
  const hits: CensusHit[] = [];
  const consumed = new Set<ts.Node>();
  const aliases = new Set<string>([ident]);
  const posOf = (n: ts.Node) => n.getStart(sf);
  const edge = (spec: string | null, role: CensusRole, pos: number) => {
    if (spec === null) return;
    const resolved = resolveSpecifier(file, spec);
    if (resolved !== null && targets.includes(resolved)) hits.push({ kind: "edge", role, resolved, pos });
  };
  /** Marks the specifier identifiers that spell `ident` as consumed and reports one id hit; follows an import alias. */
  const noteSpecifiers = (els: readonly (ts.ImportSpecifier | ts.ExportSpecifier)[], role: CensusRole, pos: number, importing: boolean): void => {
    let found = false;
    for (const el of els) {
      const imported = el.propertyName ?? el.name;
      if (imported.text !== ident) continue;
      found = true;
      consumed.add(imported);
      consumed.add(el.name);
      if (importing) aliases.add(el.name.text);
    }
    if (found) hits.push({ kind: "id", role, pos });
  };

  const visit = (node: ts.Node): void => {
    if (ts.isImportDeclaration(node)) {
      const spec = stringValue(node.moduleSpecifier);
      const clause = node.importClause;
      let role: CensusRole = "import";
      if (clause) {
        const nb = clause.namedBindings;
        const allInlineType = !!nb && ts.isNamedImports(nb) && nb.elements.length > 0 && !clause.name && nb.elements.every((e) => e.isTypeOnly);
        if (clause.isTypeOnly || allInlineType) role = "type-import";
        else if (nb && ts.isNamespaceImport(nb)) role = "namespace-import";
        if (nb && ts.isNamedImports(nb)) noteSpecifiers(nb.elements, role, posOf(node), true);
      }
      edge(spec, role, posOf(node));
      return;
    }
    if (ts.isImportEqualsDeclaration(node) && ts.isExternalModuleReference(node.moduleReference)) {
      edge(stringValue(node.moduleReference.expression), node.isTypeOnly ? "type-import" : "require", posOf(node));
      return;
    }
    if (ts.isExportDeclaration(node)) {
      const role: CensusRole = node.isTypeOnly ? "type-import" : "reexport";
      if (node.exportClause && ts.isNamedExports(node.exportClause)) noteSpecifiers(node.exportClause.elements, role, posOf(node), false);
      edge(stringValue(node.moduleSpecifier), role, posOf(node));
      return;
    }
    if (ts.isCallExpression(node)) {
      if (node.expression.kind === ts.SyntaxKind.ImportKeyword) edge(stringValue(node.arguments[0]), "dynamic-import", posOf(node));
      else if (ts.isIdentifier(node.expression) && node.expression.text === "require") edge(stringValue(node.arguments[0]), "require", posOf(node));
    }
    if (ts.isImportTypeNode(node) && ts.isLiteralTypeNode(node.argument)) edge(stringValue(node.argument.literal), "type-import", posOf(node));
    ts.forEachChild(node, visit);
  };
  visit(sf);

  // The identifier pass. Specifier names are consumed above; everything else that spells the name (or a local alias of it) is
  // classified by its parent.
  const visitIds = (node: ts.Node): void => {
    if (ts.isIdentifier(node) && !consumed.has(node) && aliases.has(node.text)) {
      const parent = node.parent;
      const isOriginal = node.text === ident;
      if (isOriginal && ts.isFunctionDeclaration(parent) && parent.name === node) hits.push({ kind: "id", role: "definition", pos: posOf(node) });
      else if (ts.isPropertyAccessExpression(parent) && parent.name === node) {
        if (isOriginal) hits.push({ kind: "id", role: "namespace-member", pos: posOf(node) });
      } else if (ts.isCallExpression(parent) && parent.expression === node) hits.push({ kind: "id", role: "call", pos: posOf(node) });
      else hits.push({ kind: "id", role: "other", pos: posOf(node) });
    }
    // `R["renderApprovalView"](...)`: an element access by the literal name is a namespace member too.
    if (ts.isElementAccessExpression(node) && stringValue(node.argumentExpression) === ident) hits.push({ kind: "id", role: "namespace-member", pos: posOf(node) });
    ts.forEachChild(node, visitIds);
  };
  visitIds(sf);
  return hits.sort((a, b) => a.pos - b.pos);
}

export interface CallArg {
  /** The argument's source text with all whitespace removed. */
  text: string;
  /** For an object literal argument: property name -> initializer text (whitespace removed). */
  props: Record<string, string>;
}
export interface CallSite {
  pos: number;
  args: CallArg[];
}

const squash = (s: string) => s.replace(/\s+/g, "");

/** Every real call whose callee is `name` or `<anything>.name`. Comments, strings and templates are never calls. */
export function callSites(src: string, file: string, name: string): CallSite[] {
  const sf = parseSource(src, file);
  const out: CallSite[] = [];
  const visit = (node: ts.Node): void => {
    if (ts.isCallExpression(node)) {
      const callee = node.expression;
      const calleeName = ts.isIdentifier(callee) ? callee.text : ts.isPropertyAccessExpression(callee) ? callee.name.text : null;
      if (calleeName === name) {
        out.push({
          pos: node.getStart(sf),
          args: node.arguments.map((a) => {
            const props: Record<string, string> = {};
            if (ts.isObjectLiteralExpression(a)) {
              for (const p of a.properties) {
                if (ts.isPropertyAssignment(p) && (ts.isIdentifier(p.name) || ts.isStringLiteral(p.name))) props[p.name.text] = squash(p.initializer.getText(sf));
                else if (ts.isShorthandPropertyAssignment(p)) props[p.name.text] = p.name.text;
              }
            }
            return { text: squash(a.getText(sf)), props };
          }),
        });
      }
    }
    ts.forEachChild(node, visit);
  };
  visit(sf);
  return out.sort((x, y) => x.pos - y.pos);
}

/** Offsets of the real call sites of `ident` (structural ordering checks). */
export function codeOffsets(src: string, ident: string, file = "x.ts"): number[] {
  return callSites(src, file, ident).map((c) => c.pos);
}
