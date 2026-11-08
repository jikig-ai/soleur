/**
 * Shared source-scanning helpers for the approval sentinels.
 *
 *   - `stripComments` (decide-boundary, runner-census, tools-census, cc-push-boundaries, workspace-head, git-auth-hardened-env):
 *     a comment blanker on the TypeScript parser (a URL with `//` inside a string is code, a JSX apostrophe or a regex literal
 *     containing `//` cannot desync it).
 *   - `censusSource`, `callSites`, `codeOffsets`, `sinkCensus`, `frameLiterals`, `stringLiteralSites` (render-sink-scan, #9601):
 *     a role-classified census of module edges, call sites and frame literals built on the TypeScript parser
 *     (`ts.createSourceFile`, parse only, no program), so comments, strings, templates, JSX text and regexes are whatever the
 *     real grammar says they are.
 */
import ts from "typescript";

/**
 * Blank out every comment (each comment character becomes a space; newlines are kept, so offsets, columns and line numbers
 * still match the file). Comment ranges come from the TypeScript parser, not a hand-rolled lexer: an apostrophe in JSX text,
 * a regex literal containing `//` or a quote, a template string and a URL inside a string are whatever the real grammar says
 * they are. `file` picks the language variant; when it is omitted the source is parsed as `.ts` and, if that parse reports
 * syntax errors, re-parsed as `.tsx` (JSX) and the cleaner parse wins.
 */
export function stripComments(src: string, file?: string): string {
  const errors = (sf: ts.SourceFile) => ((sf as unknown as { parseDiagnostics?: unknown[] }).parseDiagnostics ?? []).length;
  let sf: ts.SourceFile;
  if (file !== undefined) sf = parseSource(src, file);
  else {
    const asTs = parseSource(src, "x.ts");
    sf = errors(asTs) === 0 ? asTs : (() => {
      const asTsx = parseSource(src, "x.tsx");
      return errors(asTsx) < errors(asTs) ? asTsx : asTs;
    })();
  }
  const ranges = new Map<number, number>();
  // Every token's leading AND trailing trivia (a comment on the same line as the previous token is only "trailing" to the
  // parser's trivia API), so a comment right before a closing `}` or `)` is found. JSX text is not trivia:
  // `<p>// not a comment</p>` is text, but the trailing-trivia scan of the `>` before it would read it as a comment, so any
  // range that starts inside a JsxText node is dropped.
  const jsxText: Array<[number, number]> = [];
  const visit = (node: ts.Node): void => {
    if (node.kind === ts.SyntaxKind.JsxText) {
      jsxText.push([node.pos, node.end]);
      return;
    }
    for (const r of ts.getLeadingCommentRanges(src, node.pos) ?? []) ranges.set(r.pos, r.end);
    for (const r of ts.getTrailingCommentRanges(src, node.end) ?? []) ranges.set(r.pos, r.end);
    for (const child of node.getChildren(sf)) visit(child);
  };
  visit(sf);
  const chars = src.split("");
  for (const [pos, end] of ranges) {
    if (jsxText.some(([a, b]) => pos >= a && pos < b)) continue;
    for (let i = pos; i < end; i++) if (chars[i] !== "\n" && chars[i] !== "\r") chars[i] = " ";
  }
  return chars.join("");
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

// ---------------------------------------------------------------------------------------------------------------------
// #9601: the send census. A pin of the form "exactly one approval_request send" must not be evadable by the SHAPE of the
// second send. `sinkCensus` finds EVERY mention of the sink name (`sendToClient`, `send`) in a file and classifies it:
//   - `calls`: a call through any spelling of the callee: `a.sendToClient(...)`, `a["sendToClient"](...)`,
//     `(a.sendToClient as any)(...)`, `a.sendToClient!(...)`, `a.sendToClient?.(...)`, `a.sendToClient.call(t, ...)`,
//     `.apply(t, [...])`, and a bare `sendToClient(...)` (a destructured or aliased binding). Each call records the target
//     (argument 0, whitespace removed) and `frame`: the frame's `type` read from the AST literal's `.text` (single, double or
//     template quotes, `as const`, parentheses and `satisfies` unwrapped, a string-literal or computed-literal key), or `"?"`
//     when the frame is a variable, a call result, a spread of something that may carry a `type`, a computed non-literal key,
//     or a non-literal `type`.
//   - `refs`: any other mention (an alias `const s = a.sendToClient`, a destructure, `.bind`, a comma-expression callee, an
//     object-property pass-through): a sink that escapes the call-site view. Callers pin it to zero.
//   - `declarations`: the name as a type member (`sendToClient: (...) => boolean`).
// Named residual: a computed non-literal access (`a["send" + "ToClient"]`) and a callee fetched through `Reflect.get`.
// ---------------------------------------------------------------------------------------------------------------------

export interface SinkCall {
  pos: number;
  /** Argument 0 (the target user), whitespace removed; null for an `.apply` call. */
  target: string | null;
  /** The frame's literal `type`, or `"?"` when it cannot be read statically. */
  frame: string;
  via: "direct" | "call" | "apply";
}
export interface SinkCensus {
  calls: SinkCall[];
  refs: number;
  declarations: number;
}

/** Strip parentheses, `as`, `satisfies`, `!` and angle-bracket assertions. */
function unwrapExpr(e: ts.Expression): ts.Expression {
  let cur = e;
  while (ts.isParenthesizedExpression(cur) || ts.isAsExpression(cur) || ts.isNonNullExpression(cur) || ts.isTypeAssertionExpression(cur) || ts.isSatisfiesExpression(cur)) {
    cur = cur.expression;
  }
  return cur;
}

const literalText = (e: ts.Expression | undefined): string | null => (e ? stringValue(unwrapExpr(e)) : null);

/** A property key's literal name, or null for a computed non-literal key. */
function keyName(n: ts.PropertyName): string | null {
  if (ts.isIdentifier(n) || ts.isStringLiteral(n) || ts.isNoSubstitutionTemplateLiteral(n) || ts.isNumericLiteral(n) || ts.isPrivateIdentifier(n)) return n.text;
  if (ts.isComputedPropertyName(n)) return literalText(n.expression);
  return null;
}

/** True when a spread operand provably cannot carry a `type` key: an object literal without one, through a conditional. */
function spreadCannotCarryType(e: ts.Expression): boolean {
  const u = unwrapExpr(e);
  if (ts.isConditionalExpression(u)) return spreadCannotCarryType(u.whenTrue) && spreadCannotCarryType(u.whenFalse);
  if (!ts.isObjectLiteralExpression(u)) return false;
  return u.properties.every((p) => {
    if (ts.isSpreadAssignment(p)) return spreadCannotCarryType(p.expression);
    if (!p.name) return false;
    const k = keyName(p.name);
    return k !== null && k !== "type";
  });
}

/** The `type` literal of an object-literal frame, or `"?"` when the argument is not an object literal or `type` is not a literal. */
function frameType(e: ts.Expression | undefined): string {
  if (!e) return "?";
  const u = unwrapExpr(e);
  if (!ts.isObjectLiteralExpression(u)) return "?";
  let type: string | null = null;
  for (const p of u.properties) {
    if (ts.isSpreadAssignment(p)) {
      if (!spreadCannotCarryType(p.expression)) return "?";
      continue;
    }
    if (!p.name) return "?";
    const k = keyName(p.name);
    if (k === null) return "?";
    if (k !== "type") continue;
    if (!ts.isPropertyAssignment(p)) return "?";
    const t = literalText(p.initializer);
    if (t === null) return "?";
    type = t;
  }
  return type ?? "?";
}

export function sinkCensus(src: string, file: string, name: string): SinkCensus {
  const sf = parseSource(src, file);
  const out: SinkCensus = { calls: [], refs: 0, declarations: 0 };
  const isWrapper = (n: ts.Node): n is ts.ParenthesizedExpression | ts.AsExpression | ts.NonNullExpression | ts.TypeAssertion | ts.SatisfiesExpression =>
    ts.isParenthesizedExpression(n) || ts.isAsExpression(n) || ts.isNonNullExpression(n) || ts.isTypeAssertionExpression(n) || ts.isSatisfiesExpression(n);

  const classify = (mention: ts.Node): void => {
    // The name as a type member is a declaration, not a use.
    if (ts.isIdentifier(mention) && (ts.isPropertySignature(mention.parent) || ts.isMethodSignature(mention.parent)) && mention.parent.name === mention) {
      out.declarations++;
      return;
    }
    let cur: ts.Node = mention;
    if (ts.isIdentifier(mention) && ts.isPropertyAccessExpression(mention.parent) && mention.parent.name === mention) cur = mention.parent;
    while (cur.parent && isWrapper(cur.parent) && cur.parent.expression === cur) cur = cur.parent;
    const parent = cur.parent;
    // `.call(...)`, `.apply(...)`, `.bind(...)` on the sink.
    if (parent && ts.isPropertyAccessExpression(parent) && parent.expression === cur && ["call", "apply", "bind"].includes(parent.name.text)) {
      const call = parent.parent;
      if (parent.name.text !== "bind" && ts.isCallExpression(call) && call.expression === parent) {
        if (parent.name.text === "call") {
          out.calls.push({ pos: call.getStart(sf), target: call.arguments[1] ? squash(call.arguments[1].getText(sf)) : null, frame: frameType(call.arguments[2]), via: "call" });
        } else out.calls.push({ pos: call.getStart(sf), target: null, frame: "?", via: "apply" });
        return;
      }
      out.refs++;
      return;
    }
    if (parent && ts.isCallExpression(parent) && parent.expression === cur) {
      out.calls.push({ pos: parent.getStart(sf), target: parent.arguments[0] ? squash(parent.arguments[0].getText(sf)) : null, frame: frameType(parent.arguments[1]), via: "direct" });
      return;
    }
    out.refs++;
  };

  const visit = (node: ts.Node): void => {
    if (ts.isIdentifier(node) && node.text === name) classify(node);
    else if (ts.isElementAccessExpression(node) && literalText(node.argumentExpression) === name) classify(node);
    else if (ts.isComputedPropertyName(node) && literalText(node.expression) === name) out.refs++;
    ts.forEachChild(node, visit);
  };
  visit(sf);
  out.calls.sort((a, b) => a.pos - b.pos);
  return out;
}

/** Offsets of every string / no-substitution-template literal whose value is `text` (any quote style; comments never match). */
export function stringLiteralSites(src: string, file: string, text: string): number[] {
  const sf = parseSource(src, file);
  const out: number[] = [];
  const visit = (node: ts.Node): void => {
    if ((ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node)) && node.text === text) out.push(node.getStart(sf));
    ts.forEachChild(node, visit);
  };
  visit(sf);
  return out;
}

/** Offsets of every object literal whose `type` key (identifier, string or literal computed) holds the literal `typeText`. */
export function frameLiterals(src: string, file: string, typeText: string): number[] {
  const sf = parseSource(src, file);
  const out: number[] = [];
  const visit = (node: ts.Node): void => {
    if (ts.isObjectLiteralExpression(node)) {
      for (const p of node.properties) {
        if (ts.isPropertyAssignment(p) && keyName(p.name) === "type" && literalText(p.initializer) === typeText) out.push(node.getStart(sf));
      }
    }
    ts.forEachChild(node, visit);
  };
  visit(sf);
  return out;
}
