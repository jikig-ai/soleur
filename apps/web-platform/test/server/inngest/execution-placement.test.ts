// Inngest execution placement (#7230, ADR-033 amendment 2026-09-28).
//
// Every function app/api/inngest/route.ts serves EXECUTES on the one step-executing host (web-1):
// the Inngest server calls steps at the registered serve URL, https://app.soleur.ai/api/inngest,
// and `cloudflare_record.app` points only at web-1. This suite makes where each function COULD run
// a checked, recorded rule. server/inngest/execution-placement.ts puts every served function in
// one of three classes (portable / host-affine / volume-bound), and four guards bind it to code:
//
//   Guard 1  the manifest covers exactly the served set, keyed by Inngest function id;
//   Guard 2  a `portable` function cannot reach a host-local dependency;
//   Guard 3  no Inngest-executed code names an external-only verifier of its own substrate
//            (ADR-033's anti-circularity corollary, #6808);
//   Guard 4  there is one serve() registry and its production serve URL is exactly
//            https://app.soleur.ai (the app half of single-host execution; the DNS half is
//            infra/lb-weight-gate.test.sh Condition C).
//
// Each guard is ONE pure helper over a filesystem seam. The real-tree tests and the synthesized
// fixture rows call the same helper and differ only in the GraphFs they pass, so the two paths
// cannot diverge. Every fixture is synthesized in memory (cq-test-fixtures-synthesized-only); no
// row reads or mutates a tracked file other than through the real-tree tests.

import { join, resolve } from "node:path";
import ts from "typescript";
import { describe, expect, it } from "vitest";
import { EXECUTION_PLACEMENT } from "@/server/inngest/execution-placement";
import { WATCHDOG_DISPATCH_TABLE } from "@/server/watchdog-dispatch-table";
import {
  type GraphFs,
  type NonLiteralImport,
  type WalkOptions,
  parseModule,
  realFs,
  relTo,
  resolveSpecifier,
  specifiersOf,
  walk,
} from "../../helpers/ts-import-graph";

// ---------------------------------------------------------------------------
// Guard configuration. Adding a name to PORTABLE_SAFE_SHARED_EXPORTS is an architecture change
// (ADR-033 amendment): it declares a helper of a pinning module host-free for every function.
// ---------------------------------------------------------------------------

/** Exports of the two pinning-definer modules a `portable` function may import (default-deny). */
const PORTABLE_SAFE_SHARED_EXPORTS: ReadonlySet<string> = new Set([
  "REPO_OWNER",
  "REPO_NAME",
  "mintInstallationToken",
  "postSentryHeartbeat",
  "redactToken",
  "isFinalAttempt",
  "postDiscordWebhook",
  "postAnthropicMessage",
  "getAnthropicAdminReport",
  "AnthropicApiError",
  "ANTHROPIC_AUTH_FAILURE_RE",
  "ANTHROPIC_CREDIT_EXHAUSTED_RE",
  "AUDIT_SELF_REPORT_BODY_PREFIX",
  "ISSUE_CREATOR_CRON_TOKEN_PERMISSIONS",
  // Not imported by a portable function directly, but reached by the bodies of the allowlisted
  // helpers above (chokepoint iii): three Sentry DSN validation regexes and a redacting formatter.
  "SENTRY_DOMAIN_RE",
  "SENTRY_PROJECT_RE",
  "SENTRY_PUBLIC_KEY_RE",
  "formatTailForSentry",
]);

/**
 * External-only verifiers that are not ADR-248 watchdog rows: workflows whose own run is the only
 * signal of the total loss of a host Inngest executes on. Kept here, not under server/inngest/, so
 * Guard 3 cannot collide with its own list.
 */
const HOST_STATE_VERIFIER_WORKFLOWS: readonly string[] = [
  "workspaces-luks-verify.yml",
  "scheduled-prod-version-drift.yml",
];

/** The two modules that define host-local helpers; their exports are judged by name. */
const DEFINER_MODULES = [
  "server/inngest/functions/_cron-shared.ts",
  "server/inngest/functions/_cron-claude-eval-substrate.ts",
];

type DynamicImportExemptions = Readonly<Record<string, { counts: Readonly<Record<string, number>>; reason: string }>>;

/** The only non-literal dynamic imports any served closure may carry, counted per argument. */
const DYNAMIC_IMPORT_EXEMPTIONS: DynamicImportExemptions = {
  "server/inngest/functions/cron-ux-audit.ts": {
    counts: { botFixturePath: 2, botSigninPath: 1 },
    reason:
      "loads plugins/soleur/skills/ux-audit/scripts/bot-{fixture,signin}.ts by a runtime path (turbopackIgnore); outside the walked closure, recorded as a known gap in the ADR-033 amendment",
  },
};

const LEAF_PATH = "server/inngest/execution-placement.ts";
const ROUTE_PATH = "app/api/inngest/route.ts";
const PROD_SERVE_URL = "https://app.soleur.ai";
const CLASSES = new Set(["portable", "host-affine", "volume-bound"]);
const SERVE_ADAPTER_RE = /^inngest\/[a-z0-9-]+$/;
const CHILD_PROCESS_RE = /^(node:)?child_process$/;
const VOLUME_LITERAL_PREFIXES = ["/workspaces", "/mnt/data"];
const WORKSPACE_ENV_VARS = new Set(["WORKSPACES_ROOT", "CRON_WORKSPACE_ROOT"]);

type Manifest = Readonly<Record<string, { placement: string; reason: string }>>;

// ---------------------------------------------------------------------------
// AST utilities
// ---------------------------------------------------------------------------

function unwrap(e: ts.Expression): ts.Expression {
  let x = e;
  while (
    ts.isParenthesizedExpression(x) ||
    ts.isAsExpression(x) ||
    ts.isSatisfiesExpression(x) ||
    ts.isTypeAssertionExpression(x) ||
    ts.isNonNullExpression(x)
  ) {
    x = x.expression;
  }
  return x;
}

function stringValue(e: ts.Expression | undefined): string | null {
  if (!e) return null;
  const x = unwrap(e);
  return ts.isStringLiteral(x) || ts.isNoSubstitutionTemplateLiteral(x) ? x.text : null;
}

function load(fs: GraphFs, abs: string): ts.SourceFile | null {
  const src = fs.readFile(abs);
  return src === null ? null : parseModule(abs, src);
}

function hasExportModifier(n: ts.Node): boolean {
  return (ts.canHaveModifiers(n) ? ts.getModifiers(n) ?? [] : []).some((m) => m.kind === ts.SyntaxKind.ExportKeyword);
}

function isRequireOrImportCall(n: ts.Node): n is ts.CallExpression {
  return (
    ts.isCallExpression(n) &&
    (n.expression.kind === ts.SyntaxKind.ImportKeyword || (ts.isIdentifier(n.expression) && n.expression.text === "require"))
  );
}

/** Text of every string-literal-shaped node (comments are not nodes, so they never count). */
function stringLiteralTexts(sf: ts.SourceFile): string[] {
  const out: string[] = [];
  const visit = (n: ts.Node): void => {
    if (
      ts.isStringLiteral(n) ||
      ts.isNoSubstitutionTemplateLiteral(n) ||
      ts.isTemplateHead(n) ||
      ts.isTemplateMiddle(n) ||
      ts.isTemplateTail(n)
    ) {
      out.push(n.text);
    }
    ts.forEachChild(n, visit);
  };
  visit(sf);
  return out;
}

function isProcessEnv(e: ts.Expression): boolean {
  const x = unwrap(e);
  return ts.isPropertyAccessExpression(x) && x.name.text === "env" && ts.isIdentifier(x.expression) && x.expression.text === "process";
}

/** `process.env.X`, `process.env["X"]` and `const { X } = process.env` reads of a workspace root. */
function workspaceEnvReads(root: ts.Node): string[] {
  const out: string[] = [];
  const visit = (n: ts.Node): void => {
    if (ts.isPropertyAccessExpression(n) && isProcessEnv(n.expression) && WORKSPACE_ENV_VARS.has(n.name.text)) {
      out.push(n.name.text);
    } else if (ts.isElementAccessExpression(n) && isProcessEnv(n.expression)) {
      const k = stringValue(n.argumentExpression);
      if (k && WORKSPACE_ENV_VARS.has(k)) out.push(k);
    } else if (ts.isVariableDeclaration(n) && ts.isObjectBindingPattern(n.name) && n.initializer && isProcessEnv(n.initializer)) {
      for (const el of n.name.elements) {
        const k = (el.propertyName ?? el.name).getText();
        if (WORKSPACE_ENV_VARS.has(k)) out.push(k);
      }
    }
    ts.forEachChild(n, visit);
  };
  visit(root);
  return out;
}

function volumeLiterals(root: ts.Node): string[] {
  const out: string[] = [];
  const visit = (n: ts.Node): void => {
    if (ts.isStringLiteral(n) || ts.isNoSubstitutionTemplateLiteral(n) || ts.isTemplateHead(n)) {
      if (VOLUME_LITERAL_PREFIXES.some((p) => n.text.startsWith(p))) out.push(n.text);
    }
    ts.forEachChild(n, visit);
  };
  visit(root);
  return out;
}

// ---------------------------------------------------------------------------
// Guard 1 — the served set, derived from route.ts, and the manifest's coverage of it
// ---------------------------------------------------------------------------

interface Served {
  ident: string;
  module: string;
  id: string;
}

/** Local names route.ts binds to `serve` from an `inngest/<adapter>` module. */
function serveLocals(sf: ts.SourceFile): Set<string> {
  const out = new Set<string>();
  for (const st of sf.statements) {
    if (!ts.isImportDeclaration(st) || !ts.isStringLiteral(st.moduleSpecifier) || st.importClause?.isTypeOnly) continue;
    if (!SERVE_ADAPTER_RE.test(st.moduleSpecifier.text)) continue;
    const nb = st.importClause?.namedBindings;
    if (nb && ts.isNamedImports(nb)) {
      for (const el of nb.elements) if (!el.isTypeOnly && (el.propertyName ?? el.name).text === "serve") out.add(el.name.text);
    }
  }
  return out;
}

function serveCalls(sf: ts.SourceFile, locals: Set<string>): ts.CallExpression[] {
  const out: ts.CallExpression[] = [];
  const visit = (n: ts.Node): void => {
    if (ts.isCallExpression(n) && ts.isIdentifier(n.expression) && locals.has(n.expression.text)) out.push(n);
    ts.forEachChild(n, visit);
  };
  visit(sf);
  return out;
}

function topLevelConstString(sf: ts.SourceFile, name: string): string | null {
  for (const st of sf.statements) {
    if (!ts.isVariableStatement(st) || !(st.declarationList.flags & ts.NodeFlags.Const)) continue;
    for (const d of st.declarationList.declarations) {
      if (ts.isIdentifier(d.name) && d.name.text === name) return stringValue(d.initializer);
    }
  }
  return null;
}

function functionIdOf(fs: GraphFs, mod: string, exportName: string): string | { error: string } {
  const where = `${relTo(fs, mod)} (${exportName})`;
  const sf = load(fs, mod);
  if (!sf) return { error: `${where}: module unreadable` };
  for (const st of sf.statements) {
    if (!ts.isVariableStatement(st) || !hasExportModifier(st)) continue;
    for (const d of st.declarationList.declarations) {
      if (!ts.isIdentifier(d.name) || d.name.text !== exportName || !d.initializer) continue;
      const call = unwrap(d.initializer);
      if (!ts.isCallExpression(call) || !ts.isPropertyAccessExpression(call.expression) || call.expression.name.text !== "createFunction") {
        return { error: `${where}: not \`inngest.createFunction(...)\` — the guard cannot read its id (fail-closed)` };
      }
      const cfg = call.arguments[0] ? unwrap(call.arguments[0]) : undefined;
      if (!cfg || !ts.isObjectLiteralExpression(cfg)) return { error: `${where}: the createFunction config is not an object literal (fail-closed)` };
      const idProp = cfg.properties.find(
        (p): p is ts.PropertyAssignment => ts.isPropertyAssignment(p) && ts.isIdentifier(p.name) && p.name.text === "id",
      );
      if (!idProp) return { error: `${where}: the createFunction config has no \`id\` property` };
      const lit = stringValue(idProp.initializer);
      if (lit !== null) return lit;
      const init = unwrap(idProp.initializer);
      if (ts.isIdentifier(init)) {
        const v = topLevelConstString(sf, init.text);
        if (v !== null) return v;
      }
      return {
        error: `${where}: the function id \`${idProp.initializer.getText(sf)}\` is not statically readable — use a string literal or a same-file const`,
      };
    }
  }
  return { error: `${where}: no \`export const ${exportName} = ...\` found (fail-closed)` };
}

function servedFunctions(fs: GraphFs): { served: Served[]; offenders: string[] } {
  const routeAbs = join(fs.appRoot, ROUTE_PATH);
  const sf = load(fs, routeAbs);
  if (!sf) return { served: [], offenders: [`${ROUTE_PATH}: unreadable`] };
  const offenders: string[] = [];

  const fnImports = new Map<string, { spec: string; imported: string }>();
  for (const st of sf.statements) {
    if (!ts.isImportDeclaration(st) || !ts.isStringLiteral(st.moduleSpecifier) || st.importClause?.isTypeOnly) continue;
    const spec = st.moduleSpecifier.text;
    const nb = st.importClause?.namedBindings;
    if (!spec.startsWith("@/server/inngest/functions/") || !nb || !ts.isNamedImports(nb)) continue;
    for (const el of nb.elements) if (!el.isTypeOnly) fnImports.set(el.name.text, { spec, imported: (el.propertyName ?? el.name).text });
  }

  const calls = serveCalls(sf, serveLocals(sf));
  if (calls.length !== 1) {
    return { served: [], offenders: [`${ROUTE_PATH}: expected exactly one serve() call, found ${calls.length} (fail-closed)`] };
  }
  const arg = calls[0].arguments[0] ? unwrap(calls[0].arguments[0]) : undefined;
  const fnsProp =
    arg && ts.isObjectLiteralExpression(arg)
      ? arg.properties.find((p): p is ts.PropertyAssignment => ts.isPropertyAssignment(p) && ts.isIdentifier(p.name) && p.name.text === "functions")
      : undefined;
  const arr = fnsProp ? unwrap(fnsProp.initializer) : undefined;
  if (!arr || !ts.isArrayLiteralExpression(arr)) {
    return { served: [], offenders: [`${ROUTE_PATH}: serve() has no \`functions: [ ... ]\` array literal (fail-closed)`] };
  }

  const idents: string[] = [];
  for (const el of arr.elements) {
    if (ts.isIdentifier(el)) idents.push(el.text);
    else offenders.push(`${ROUTE_PATH}: serve() functions element \`${el.getText(sf)}\` is not a plain identifier — the placement guard cannot resolve it (fail-closed)`);
  }
  const identSet = new Set(idents);
  for (const i of idents) if (!fnImports.has(i)) offenders.push(`${ROUTE_PATH}: served identifier ${i} is not imported from @/server/inngest/functions/*`);
  for (const [i, { spec }] of fnImports) if (!identSet.has(i)) offenders.push(`${ROUTE_PATH}: ${i} is imported from ${spec} but missing from the serve() functions array`);
  if (identSet.size !== idents.length) offenders.push(`${ROUTE_PATH}: the serve() functions array lists an identifier twice`);

  const served: Served[] = [];
  for (const ident of identSet) {
    const imp = fnImports.get(ident);
    if (!imp) continue;
    const mod = resolveSpecifier(imp.spec, routeAbs, fs);
    if (!mod || mod === "unresolved") {
      offenders.push(`${ROUTE_PATH}: cannot resolve ${imp.spec} (fail-closed)`);
      continue;
    }
    const id = functionIdOf(fs, mod, imp.imported);
    if (typeof id === "string") served.push({ ident, module: mod, id });
    else offenders.push(id.error);
  }
  return { served, offenders };
}

function rowStub(id: string): string {
  return `  "${id}": { placement: "<portable | host-affine | volume-bound>", reason: "<the marker that pins it, or why it is host-free>" },`;
}

function manifestViolations(served: Served[], manifest: Manifest, fs: GraphFs): string[] {
  const out: string[] = [];
  const ids = new Set<string>();
  for (const s of served) {
    if (ids.has(s.id)) out.push(`function id "${s.id}" is served twice`);
    ids.add(s.id);
  }
  for (const s of served) {
    if (!Object.hasOwn(manifest, s.id)) {
      out.push(`missing EXECUTION_PLACEMENT row for served function "${s.id}" (${relTo(fs, s.module)}). Add to ${LEAF_PATH}, with the tightest class its markers imply:\n${rowStub(s.id)}`);
    }
  }
  for (const k of Object.keys(manifest)) {
    if (!ids.has(k)) out.push(`stale EXECUTION_PLACEMENT row "${k}": no served function has that id — delete it from ${LEAF_PATH}`);
  }
  for (const [k, v] of Object.entries(manifest)) {
    if (!CLASSES.has(v.placement)) out.push(`row "${k}": placement "${v.placement}" is not one of portable | host-affine | volume-bound`);
    if (typeof v.reason !== "string" || v.reason.trim() === "") out.push(`row "${k}": reason is empty — name the marker that pins it, or why it is host-free`);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Guard 2 — the portable boundary
// ---------------------------------------------------------------------------

interface Marker {
  module: string;
  detail: string;
}

type Resolver = NonNullable<WalkOptions["resolver"]>;

const isDefiner = (fs: GraphFs, abs: string): boolean => DEFINER_MODULES.some((d) => abs === join(fs.appRoot, d));

/** Chokepoint (i): every edge into a definer module, judged by the names it binds. */
function definerEdgeMarkers(sf: ts.SourceFile, m: string, fs: GraphFs, allowlist: ReadonlySet<string>, resolver: Resolver): Marker[] {
  const out: Marker[] = [];
  const target = (spec: string): string | null => {
    const t = resolver(spec, m, fs);
    return t && t !== "unresolved" && isDefiner(fs, t) ? relTo(fs, t) : null;
  };
  const judge = (names: string[], def: string, verb: string): void => {
    for (const n of names) if (!allowlist.has(n)) out.push({ module: m, detail: `\`${n}\` (${verb} ${def}; not in PORTABLE_SAFE_SHARED_EXPORTS)` });
  };
  const visit = (n: ts.Node): void => {
    if (ts.isImportDeclaration(n) && ts.isStringLiteral(n.moduleSpecifier)) {
      const def = target(n.moduleSpecifier.text);
      const c = n.importClause;
      if (def && !c?.isTypeOnly) {
        if (!c) out.push({ module: m, detail: `a side-effect import of ${def}` });
        else {
          if (c.name) out.push({ module: m, detail: `a default import of ${def}` });
          if (c.namedBindings && ts.isNamespaceImport(c.namedBindings)) out.push({ module: m, detail: `a namespace import of ${def}` });
          if (c.namedBindings && ts.isNamedImports(c.namedBindings)) {
            judge(c.namedBindings.elements.filter((e) => !e.isTypeOnly).map((e) => (e.propertyName ?? e.name).text), def, "imported from");
          }
        }
      }
    } else if (ts.isExportDeclaration(n) && n.moduleSpecifier && ts.isStringLiteral(n.moduleSpecifier)) {
      const def = target(n.moduleSpecifier.text);
      if (def && !n.isTypeOnly) {
        if (!n.exportClause) out.push({ module: m, detail: `\`export * from\` ${def}` });
        else if (ts.isNamespaceExport(n.exportClause)) out.push({ module: m, detail: `a namespace re-export of ${def}` });
        else judge(n.exportClause.elements.filter((e) => !e.isTypeOnly).map((e) => (e.propertyName ?? e.name).text), def, "re-exported from");
      }
    } else if (ts.isImportEqualsDeclaration(n) && ts.isExternalModuleReference(n.moduleReference)) {
      const s = stringValue(n.moduleReference.expression);
      const def = s ? target(s) : null;
      if (def) out.push({ module: m, detail: `\`import = require()\` of ${def}` });
    } else if (isRequireOrImportCall(n)) {
      const s = stringValue(n.arguments[0]);
      const def = s ? target(s) : null;
      if (def) out.push({ module: m, detail: `a dynamic import()/require() of ${def}` });
    }
    ts.forEachChild(n, visit);
  };
  visit(sf);
  return out;
}

/** Chokepoint (ii): host-local markers in a closure module's own source. */
function hostLocalMarkers(sf: ts.SourceFile, m: string): Marker[] {
  const out: Marker[] = [];
  for (const s of specifiersOf(sf, { elideTypeOnlySpecifiers: true })) {
    if (s.kind === "literal" && CHILD_PROCESS_RE.test(s.spec)) out.push({ module: m, detail: `\`${s.spec}\`` });
  }
  for (const lit of volumeLiterals(sf)) out.push({ module: m, detail: `the volume path literal "${lit}"` });
  for (const v of workspaceEnvReads(sf)) out.push({ module: m, detail: `process.env.${v}` });
  return out;
}

interface TopDecl {
  node: ts.Node;
  exported: boolean;
}

function topLevelDecls(sf: ts.SourceFile): Map<string, TopDecl> {
  const out = new Map<string, TopDecl>();
  const localExports = new Set<string>();
  for (const st of sf.statements) {
    const exported = hasExportModifier(st);
    if ((ts.isFunctionDeclaration(st) || ts.isClassDeclaration(st) || ts.isEnumDeclaration(st)) && st.name) {
      out.set(st.name.text, { node: st, exported });
    } else if (ts.isVariableStatement(st)) {
      for (const d of st.declarationList.declarations) {
        const names: string[] = [];
        const collect = (b: ts.BindingName): void => {
          if (ts.isIdentifier(b)) names.push(b.text);
          else for (const el of b.elements) if (!ts.isOmittedExpression(el)) collect(el.name);
        };
        collect(d.name);
        for (const n of names) out.set(n, { node: d, exported });
      }
    } else if (ts.isExportDeclaration(st) && !st.moduleSpecifier && st.exportClause && ts.isNamedExports(st.exportClause)) {
      for (const el of st.exportClause.elements) localExports.add((el.propertyName ?? el.name).text);
    }
  }
  for (const n of localExports) {
    const d = out.get(n);
    if (d) d.exported = true;
  }
  return out;
}

function exportedNames(sf: ts.SourceFile, tops: Map<string, TopDecl>): Set<string> {
  const out = new Set<string>();
  for (const [n, d] of tops) if (d.exported) out.add(n);
  for (const st of sf.statements) {
    if (ts.isExportDeclaration(st) && st.exportClause && ts.isNamedExports(st.exportClause)) {
      for (const el of st.exportClause.elements) out.add(el.name.text);
    }
  }
  return out;
}

function importBindings(sf: ts.SourceFile): Map<string, string> {
  const out = new Map<string, string>();
  for (const st of sf.statements) {
    if (!ts.isImportDeclaration(st) || !ts.isStringLiteral(st.moduleSpecifier) || st.importClause?.isTypeOnly) continue;
    const c = st.importClause;
    if (!c) continue;
    if (c.name) out.set(c.name.text, st.moduleSpecifier.text);
    const nb = c.namedBindings;
    if (nb && ts.isNamespaceImport(nb)) out.set(nb.name.text, st.moduleSpecifier.text);
    if (nb && ts.isNamedImports(nb)) for (const el of nb.elements) if (!el.isTypeOnly) out.set(el.name.text, st.moduleSpecifier.text);
  }
  return out;
}

/** Identifiers in value positions (type positions and member/property names are skipped). */
function valueIdentifiers(root: ts.Node): string[] {
  const out: string[] = [];
  const visit = (n: ts.Node): void => {
    if (ts.isTypeNode(n) && !ts.isExpressionWithTypeArguments(n)) return;
    if (ts.isIdentifier(n)) {
      const p = n.parent;
      const isName =
        (ts.isPropertyAccessExpression(p) && p.name === n) ||
        (ts.isPropertyAssignment(p) && p.name === n) ||
        ((ts.isMethodDeclaration(p) || ts.isPropertyDeclaration(p) || ts.isGetAccessor(p) || ts.isSetAccessor(p)) && p.name === n) ||
        (ts.isBindingElement(p) && p.propertyName === n) ||
        ts.isQualifiedName(p);
      if (!isName) out.push(n.text);
    }
    ts.forEachChild(n, visit);
  };
  visit(root);
  return out;
}

/**
 * Chokepoint (iii): each allowlisted export's own declaration, followed through same-file
 * top-level declarations, must not reach a non-allowlisted export, a child_process binding, a
 * volume literal, or a workspace env read. An identifier imported from another module is not
 * followed here: the closure walk descends into that module and chokepoint (ii) scans it.
 */
function allowlistBodyViolations(fs: GraphFs, allowlist: ReadonlySet<string>): string[] {
  const out: string[] = [];
  const found = new Set<string>();
  for (const d of DEFINER_MODULES) {
    const sf = load(fs, join(fs.appRoot, d));
    if (!sf) {
      out.push(`${d}: definer module unreadable (fail-closed)`);
      continue;
    }
    const tops = topLevelDecls(sf);
    const exported = exportedNames(sf, tops);
    const imports = importBindings(sf);
    for (const name of allowlist) {
      if (!exported.has(name)) continue;
      found.add(name);
      const fix = `\`${name}\` is in PORTABLE_SAFE_SHARED_EXPORTS but is no longer host-free; remove it from the allowlist and re-class every portable function that imports it`;
      const seen = new Set<string>();
      const queue = [name];
      while (queue.length) {
        const n = queue.pop()!;
        if (seen.has(n)) continue;
        seen.add(n);
        const decl = tops.get(n);
        if (!decl) {
          const spec = imports.get(n);
          if (spec && CHILD_PROCESS_RE.test(spec)) out.push(`${d}: ${fix} — it reaches \`${n}\` from ${spec}`);
          continue;
        }
        if (n !== name && decl.exported) {
          if (!allowlist.has(n)) out.push(`${d}: ${fix} — it reaches the non-allowlisted export \`${n}\``);
          continue; // an allowlisted export is scanned in its own right
        }
        for (const lit of volumeLiterals(decl.node)) out.push(`${d}: ${fix} — it reaches the volume path literal "${lit}"`);
        for (const v of workspaceEnvReads(decl.node)) out.push(`${d}: ${fix} — it reaches process.env.${v}`);
        for (const id of valueIdentifiers(decl.node)) if (id !== n) queue.push(id);
      }
    }
  }
  for (const name of allowlist) {
    if (!found.has(name)) out.push(`PORTABLE_SAFE_SHARED_EXPORTS names \`${name}\`, which no definer module exports — remove the stale entry`);
  }
  return out;
}

interface ClosureScan {
  reach: Set<string>;
  problems: string[];
  markers: Marker[];
  serverEdges: number;
}

function scanClosure(entry: string, fs: GraphFs, allowlist: ReadonlySet<string>, walkOpts: WalkOptions = {}): ClosureScan {
  const resolver = walkOpts.resolver ?? resolveSpecifier;
  const { reach, problems } = walk(entry, fs, { ...walkOpts, elideTypeOnlySpecifiers: true });
  const markers: Marker[] = [];
  let serverEdges = 0;
  for (const m of reach) {
    const sf = load(fs, m);
    if (!sf) continue; // the walk already reported it
    for (const s of specifiersOf(sf, { elideTypeOnlySpecifiers: true })) {
      if (s.kind === "literal" && s.spec.startsWith("@/server/")) {
        const t = resolver(s.spec, m, fs);
        if (t && t !== "unresolved") serverEdges++;
      }
    }
    markers.push(...definerEdgeMarkers(sf, m, fs, allowlist, resolver));
    if (!isDefiner(fs, m)) markers.push(...hostLocalMarkers(sf, m));
  }
  return { reach, problems, markers, serverEdges };
}

interface PortableResult {
  offenders: string[];
  checkedCount: number;
  closureSizes: Record<string, number>;
}

function portableViolations(args: {
  served: Served[];
  manifest: Manifest;
  fs: GraphFs;
  allowlist: ReadonlySet<string>;
  walkOpts?: WalkOptions;
}): PortableResult {
  const { served, manifest, fs, allowlist, walkOpts } = args;
  const offenders = allowlistBodyViolations(fs, allowlist);
  const closureSizes: Record<string, number> = {};
  let checkedCount = 0;
  for (const s of served) {
    if (manifest[s.id]?.placement !== "portable") continue;
    checkedCount++;
    const scan = scanClosure(s.module, fs, allowlist, walkOpts);
    closureSizes[s.id] = scan.reach.size;
    for (const p of scan.problems) offenders.push(`portable ${s.id}: ${p} — the walk must be total (fail-closed)`);
    for (const mk of scan.markers) {
      offenders.push(
        `portable ${s.id} reaches ${mk.detail} via ${relTo(fs, mk.module)}; re-class it to the tightest class that marker implies (host-affine, or volume-bound for workspace data) in ${LEAF_PATH} — never widen PORTABLE_SAFE_SHARED_EXPORTS to make it pass`,
      );
    }
    if (scan.reach.size <= 1 || scan.serverEdges === 0) {
      offenders.push(
        `portable ${s.id}: its closure is ${scan.reach.size} module(s) and resolved no @/server/* edge — the walk followed nothing, so the boundary check would be vacuous`,
      );
    }
  }
  return { offenders, checkedCount, closureSizes };
}

/** The anti-vacuity check the real-tree test applies to Guard 2's result. */
function checkedCountViolation(result: PortableResult, manifest: Manifest): string | null {
  const portableRows = Object.values(manifest).filter((r) => r.placement === "portable").length;
  if (portableRows === 0 || result.checkedCount !== portableRows) {
    return `Guard 2 checked ${result.checkedCount} portable function(s) against ${portableRows} portable row(s) — it must check every one, and at least one`;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Guard 3 — anti-circularity (ADR-033 corollary, #6808)
// ---------------------------------------------------------------------------

interface Forbidden {
  file: string;
  source: string;
}

function forbiddenWorkflows(table: ReadonlyArray<{ workflowFile: string }>, verifiers: readonly string[]): Forbidden[] {
  return [
    ...table.map((r) => ({ file: r.workflowFile, source: "WATCHDOG_DISPATCH_TABLE" })),
    ...verifiers.map((f) => ({ file: f, source: "HOST_STATE_VERIFIER_WORKFLOWS" })),
  ];
}

function sameCounts(a: Record<string, number>, b: Readonly<Record<string, number>>): boolean {
  const ka = Object.keys(a).sort();
  const kb = Object.keys(b).sort();
  return ka.length === kb.length && ka.every((k, i) => k === kb[i] && a[k] === b[k]);
}

const fmtCounts = (c: Readonly<Record<string, number>>): string =>
  Object.entries(c)
    .sort()
    .map(([k, v]) => `${k}×${v}`)
    .join(", ");

function circularityViolations(args: {
  served: Served[];
  fs: GraphFs;
  forbidden: Forbidden[];
  exemptions: DynamicImportExemptions;
  walkOpts?: WalkOptions;
}): { offenders: string[]; scannedCount: number } {
  const { served, fs, forbidden, exemptions, walkOpts } = args;
  const offenders = new Set<string>();
  if (forbidden.length === 0) offenders.add("the forbidden verifier set is empty — Guard 3 would check nothing (fail-closed)");
  const repoRoot = resolve(fs.appRoot, "../..");
  for (const f of forbidden) {
    if (!fs.exists(join(repoRoot, ".github/workflows", f.file))) {
      offenders.add(`forbidden workflow ${f.file} (${f.source}) does not exist under .github/workflows/ — a stale entry guards nothing; remove it`);
    }
  }
  const stems = forbidden.map((f) => ({ stem: f.file.replace(/\.ya?ml$/, ""), source: f.source }));

  const scanned = new Set<string>();
  for (const p of fs.listFiles(join(fs.appRoot, "server/inngest"))) {
    if (/\.(ts|mjs)$/.test(p) && !/\.test\.(ts|mjs)$/.test(p)) scanned.add(p);
  }
  const nonLiteral = new Map<string, NonLiteralImport>();
  for (const s of served) {
    const r = walk(s.module, fs, { ...walkOpts, elideTypeOnlySpecifiers: true, recordDynamicImportArgs: true });
    for (const p of r.problems) offenders.add(`${p} — the anti-circularity walk must be total (fail-closed)`);
    for (const m of r.reach) scanned.add(m);
    for (const d of r.nonLiteral) nonLiteral.set(`${d.file}:${d.pos}`, d);
  }

  const byFile = new Map<string, Record<string, number>>();
  for (const d of nonLiteral.values()) {
    const c = byFile.get(d.file) ?? {};
    c[d.argText] = (c[d.argText] ?? 0) + 1;
    byFile.set(d.file, c);
  }
  for (const [file, counts] of byFile) {
    const ex = exemptions[relTo(fs, file)];
    if (!ex || !sameCounts(counts, ex.counts)) {
      offenders.add(
        `${relTo(fs, file)}: non-literal import()/require() (${fmtCounts(counts)}) — the walk cannot see where it leads.${ex ? ` Its exemption is exactly ${fmtCounts(ex.counts)}.` : ""}`,
      );
    }
  }
  for (const [file, ex] of Object.entries(exemptions)) {
    if (![...byFile.keys()].some((f) => relTo(fs, f) === file)) {
      offenders.add(`the dynamic-import exemption for ${file} (${fmtCounts(ex.counts)}) matches no non-literal import — remove it`);
    }
  }

  for (const p of scanned) {
    const sf = load(fs, p);
    if (!sf) {
      offenders.add(`${relTo(fs, p)}: unreadable (fail-closed)`);
      continue;
    }
    const texts = stringLiteralTexts(sf);
    for (const { stem, source } of stems) {
      if (texts.some((t) => t.includes(stem))) {
        offenders.add(
          `${relTo(fs, p)} names the forbidden workflow "${stem}" (${source}). Inngest-executed code must not dispatch an external-only verifier of its own substrate — its silence would read as health (#6808; ADR-033 anti-circularity corollary).`,
        );
      }
    }
  }
  return { offenders: [...offenders], scannedCount: scanned.size };
}

// ---------------------------------------------------------------------------
// Guard 4 — one serve() registry, production serve URL exactly https://app.soleur.ai
// ---------------------------------------------------------------------------

function reachesServeAdapter(sf: ts.SourceFile): boolean {
  let hit = false;
  const visit = (n: ts.Node): void => {
    if (hit) return;
    if (ts.isImportDeclaration(n) && ts.isStringLiteral(n.moduleSpecifier) && SERVE_ADAPTER_RE.test(n.moduleSpecifier.text)) {
      const c = n.importClause;
      if (c && !c.isTypeOnly) {
        if (c.name) hit = true;
        const nb = c.namedBindings;
        if (nb && ts.isNamespaceImport(nb)) hit = true;
        if (nb && ts.isNamedImports(nb) && nb.elements.some((e) => !e.isTypeOnly && (e.propertyName ?? e.name).text === "serve")) hit = true;
      }
    } else if (ts.isExportDeclaration(n) && n.moduleSpecifier && ts.isStringLiteral(n.moduleSpecifier) && SERVE_ADAPTER_RE.test(n.moduleSpecifier.text) && !n.isTypeOnly) {
      if (!n.exportClause || ts.isNamespaceExport(n.exportClause)) hit = true;
      else if (n.exportClause.elements.some((e) => !e.isTypeOnly && (e.propertyName ?? e.name).text === "serve")) hit = true;
    } else if (ts.isImportEqualsDeclaration(n) && ts.isExternalModuleReference(n.moduleReference)) {
      const s = stringValue(n.moduleReference.expression);
      if (s && SERVE_ADAPTER_RE.test(s)) hit = true;
    } else if (isRequireOrImportCall(n)) {
      const s = stringValue(n.arguments[0]);
      if (s && SERVE_ADAPTER_RE.test(s)) hit = true;
    }
    ts.forEachChild(n, visit);
  };
  visit(sf);
  return hit;
}

function isNodeEnvProduction(e: ts.Expression): boolean {
  const x = unwrap(e);
  if (!ts.isBinaryExpression(x)) return false;
  if (x.operatorToken.kind !== ts.SyntaxKind.EqualsEqualsEqualsToken && x.operatorToken.kind !== ts.SyntaxKind.EqualsEqualsToken) return false;
  const isNodeEnv = (s: ts.Expression): boolean => {
    const u = unwrap(s);
    return ts.isPropertyAccessExpression(u) && u.name.text === "NODE_ENV" && isProcessEnv(u.expression);
  };
  return (isNodeEnv(x.left) && stringValue(x.right) === "production") || (isNodeEnv(x.right) && stringValue(x.left) === "production");
}

function serveAnchorViolations(fs: GraphFs): string[] {
  const out: string[] = [];
  const files = ["app", "server", "lib"]
    .flatMap((d) => fs.listFiles(join(fs.appRoot, d)))
    .filter((p) => /\.tsx?$/.test(p) && !/\.test\.tsx?$/.test(p) && !p.endsWith(".d.ts"));
  const reaching: string[] = [];
  for (const f of files) {
    const sf = load(fs, f);
    if (sf && reachesServeAdapter(sf)) reaching.push(relTo(fs, f));
  }
  reaching.sort();
  if (reaching.length !== 1 || reaching[0] !== ROUTE_PATH) {
    out.push(
      `modules reaching an inngest serve adapter: [${reaching.join(", ")}] — expected exactly [${ROUTE_PATH}]. A second serve() registry registers a second step-executing URL; revisit the ADR-033 #7230 placement rule first.`,
    );
  }

  const sf = load(fs, join(fs.appRoot, ROUTE_PATH));
  if (!sf) return [...out, `${ROUTE_PATH}: unreadable (fail-closed)`];
  const want = `the production branch of SERVE_HOST must be the string literal "${PROD_SERVE_URL}"`;
  let serveHostDecl: ts.VariableDeclaration | undefined;
  for (const st of sf.statements) {
    if (!ts.isVariableStatement(st)) continue;
    for (const d of st.declarationList.declarations) if (ts.isIdentifier(d.name) && d.name.text === "SERVE_HOST") serveHostDecl = d;
  }
  if (!serveHostDecl?.initializer) {
    out.push(`${ROUTE_PATH}: \`const SERVE_HOST\` not found — ${want} (fail-closed)`);
  } else {
    const init = unwrap(serveHostDecl.initializer);
    if (!ts.isConditionalExpression(init) || !isNodeEnvProduction(init.condition)) {
      out.push(`${ROUTE_PATH}: SERVE_HOST is not \`process.env.NODE_ENV === "production" ? ... : ...\` — ${want}`);
    } else if (stringValue(init.whenTrue) !== PROD_SERVE_URL || !ts.isStringLiteral(unwrap(init.whenTrue))) {
      out.push(`${ROUTE_PATH}: ${want}, found \`${init.whenTrue.getText(sf)}\``);
    }
  }

  const calls = serveCalls(sf, serveLocals(sf));
  if (calls.length !== 1) {
    out.push(`${ROUTE_PATH}: expected exactly one serve() call bound from an inngest adapter, found ${calls.length} (fail-closed)`);
  } else {
    const hosts: ts.ObjectLiteralElementLike[] = [];
    const visit = (n: ts.Node): void => {
      if ((ts.isPropertyAssignment(n) || ts.isShorthandPropertyAssignment(n)) && ts.isIdentifier(n.name) && n.name.text === "serveHost") hosts.push(n);
      ts.forEachChild(n, visit);
    };
    if (calls[0].arguments[0]) visit(calls[0].arguments[0]);
    if (hosts.length === 0) out.push(`${ROUTE_PATH}: serve() sets no serveHost — it must be \`serveHost: SERVE_HOST\``);
    for (const h of hosts) {
      const init = ts.isPropertyAssignment(h) ? unwrap(h.initializer) : undefined;
      if (!init || !ts.isIdentifier(init) || init.text !== "SERVE_HOST") {
        out.push(`${ROUTE_PATH}: serve()'s serveHost is \`${h.getText(sf)}\` — it must be \`serveHost: SERVE_HOST\`, so ${want.replace("the production branch of SERVE_HOST must be ", "the step URL is ")}`);
      }
    }
  }
  return out;
}

// ===========================================================================
// Real tree
// ===========================================================================

const APP_ROOT = resolve(__dirname, "../../..");
const REAL_FS = realFs(APP_ROOT);
const REAL = servedFunctions(REAL_FS);
const REAL_PORTABLE_ROWS = Object.values(EXECUTION_PLACEMENT).filter((r) => r.placement === "portable").length;

describe("execution placement — the real tree (#7230)", () => {
  it(`Guard 1: route.ts resolves to ${REAL.served.length} served functions, each with a statically readable id`, () => {
    expect(REAL.offenders).toEqual([]);
    expect(REAL.served.length).toBeGreaterThan(0);
  });

  it(`Guard 1: EXECUTION_PLACEMENT has exactly one valid row per served function (${Object.keys(EXECUTION_PLACEMENT).length} rows)`, () => {
    expect(manifestViolations(REAL.served, EXECUTION_PLACEMENT, REAL_FS)).toEqual([]);
  });

  it(`Guard 2: none of the ${REAL_PORTABLE_ROWS} portable functions reaches a host-local dependency`, () => {
    const r = portableViolations({ served: REAL.served, manifest: EXECUTION_PLACEMENT, fs: REAL_FS, allowlist: PORTABLE_SAFE_SHARED_EXPORTS });
    expect(r.offenders).toEqual([]);
    expect(checkedCountViolation(r, EXECUTION_PLACEMENT)).toBeNull();
  });

  it("Guard 3: no Inngest-executed module names an external-only verifier workflow", () => {
    const r = circularityViolations({
      served: REAL.served,
      fs: REAL_FS,
      forbidden: forbiddenWorkflows(WATCHDOG_DISPATCH_TABLE, HOST_STATE_VERIFIER_WORKFLOWS),
      exemptions: DYNAMIC_IMPORT_EXEMPTIONS,
    });
    expect(r.offenders).toEqual([]);
    expect(r.scannedCount).toBeGreaterThan(REAL.served.length);
  });

  it(`Guard 4: one serve() registry, and its production serve URL is exactly ${PROD_SERVE_URL}`, () => {
    expect(serveAnchorViolations(REAL_FS)).toEqual([]);
  });
});

// ===========================================================================
// Synthesized fixtures
// ===========================================================================

const FX_APP = "/fx/apps/web-platform";

function memFs(files: Record<string, string>, appRoot = FX_APP): GraphFs {
  const abs = new Map(Object.entries(files).map(([k, v]) => [k.startsWith("/") ? k : join(appRoot, k), v]));
  return {
    appRoot,
    readFile: (p) => abs.get(p) ?? null,
    exists: (p) => abs.has(p),
    listFiles: (dir) => [...abs.keys()].filter((p) => p.startsWith(`${dir}/`)),
  };
}

const FX_ALLOW: ReadonlySet<string> = new Set(["postSentryHeartbeat", "REPO_OWNER"]);

const FX_SHARED = `export const REPO_OWNER = "acme";
function heartbeatUrl(slug: string): string {
  return \`https://sentry.example/\${slug}\`;
}
export async function postSentryHeartbeat(slug: string): Promise<string> {
  return heartbeatUrl(slug);
}
export function resolveCronWorkspaceRoot(): string {
  return process.env.CRON_WORKSPACE_ROOT ?? "/workspaces";
}
export interface HandlerArgs {
  step: unknown;
}
`;

const FX_SUBSTRATE = `import { spawn } from "node:child_process";
export interface SpawnResult {
  code: number;
}
export function spawnClaudeEval(): SpawnResult {
  spawn("claude");
  return { code: 0 };
}
`;

function fnSrc(exportName: string, id: string, head = "", body = "null"): string {
  return `import { inngest } from "@/server/inngest/client";
${head}
export const ${exportName} = inngest.createFunction({ id: "${id}" }, { cron: "0 * * * *" }, async () => ${body});
`;
}

function routeSrc(opts: {
  imports: Array<[ident: string, mod: string]>;
  array: string[];
  prodBranch?: string;
  serveHostProp?: string;
  serveHostDecl?: string;
  serveImport?: string;
  preamble?: string;
  postamble?: string;
}): string {
  const serveHostDecl =
    opts.serveHostDecl ?? `const SERVE_HOST =\n  process.env.NODE_ENV === "production" ? ${opts.prodBranch ?? `"${PROD_SERVE_URL}"`} : undefined;`;
  return `${opts.preamble ?? ""}${opts.serveImport ?? `import { serve } from "inngest/next";`}
import { inngest } from "@/server/inngest/client";
${opts.imports.map(([i, m]) => `import { ${i} } from "@/server/inngest/functions/${m}";`).join("\n")}

${serveHostDecl}

const handlers = serve({
  client: inngest,
  functions: [${opts.array.join(", ")}],
  ...(SERVE_HOST ? { serveHost: ${opts.serveHostProp ?? "SERVE_HOST"}, servePath: "/api/inngest" } : {}),
});
export const { GET, POST, PUT } = handlers;
${opts.postamble ?? ""}`;
}

const BASE_ROUTE = { imports: [["cronAlpha", "cron-alpha"], ["cronBeta", "cron-beta"]] as Array<[string, string]>, array: ["cronAlpha", "cronBeta"] };

function baseFiles(): Record<string, string> {
  return {
    [ROUTE_PATH]: routeSrc(BASE_ROUTE),
    "server/inngest/client.ts": `export const inngest = { id: "acme", createFunction: (...a: unknown[]) => a };\n`,
    "server/inngest/functions/_cron-shared.ts": FX_SHARED,
    "server/inngest/functions/_cron-claude-eval-substrate.ts": FX_SUBSTRATE,
    "server/inngest/functions/cron-alpha.ts": fnSrc("cronAlpha", "cron-alpha", `import { postSentryHeartbeat, REPO_OWNER } from "./_cron-shared";`, "postSentryHeartbeat(REPO_OWNER)"),
    "server/inngest/functions/cron-beta.ts": fnSrc("cronBeta", "cron-beta", `import { spawnClaudeEval } from "./_cron-claude-eval-substrate";`, "spawnClaudeEval()"),
    "/fx/.github/workflows/scheduled-inngest-health.yml": "on: {}\n",
    "/fx/.github/workflows/workspaces-luks-verify.yml": "on: {}\n",
  };
}

const BASE_MANIFEST: Manifest = {
  "cron-alpha": { placement: "portable", reason: "host-free: Sentry heartbeat only" },
  "cron-beta": { placement: "host-affine", reason: "spawnClaudeEval (process-local single-flight)" },
};

const FX_FORBIDDEN: Forbidden[] = forbiddenWorkflows([{ workflowFile: "scheduled-inngest-health.yml" }], ["workspaces-luks-verify.yml"]);

function runAll(files: Record<string, string>, manifest: Manifest = BASE_MANIFEST, opts: { exemptions?: DynamicImportExemptions; walkOpts?: WalkOptions } = {}) {
  const fs = memFs(files);
  const s = servedFunctions(fs);
  const g2 = portableViolations({ served: s.served, manifest, fs, allowlist: FX_ALLOW, walkOpts: opts.walkOpts });
  return {
    fs,
    served: s.served,
    g1: [...s.offenders, ...manifestViolations(s.served, manifest, fs)],
    g2: g2.offenders,
    g2result: g2,
    g3: circularityViolations({ served: s.served, fs, forbidden: FX_FORBIDDEN, exemptions: opts.exemptions ?? {} }).offenders,
    g4: serveAnchorViolations(fs),
  };
}

const withFiles = (patch: Record<string, string>): Record<string, string> => ({ ...baseFiles(), ...patch });
const joined = (xs: string[]): string => xs.join("\n");

describe("fixture control — the unmutated synthesized app passes every guard", () => {
  it("control", () => {
    const r = runAll(baseFiles());
    expect(r.served.map((s) => s.id).sort()).toEqual(["cron-alpha", "cron-beta"]);
    expect(r.g1).toEqual([]);
    expect(r.g2).toEqual([]);
    expect(r.g2result.checkedCount).toBe(1);
    expect(r.g3).toEqual([]);
    expect(r.g4).toEqual([]);
  });
});

describe("Guard 1 — the manifest covers exactly the served set", () => {
  it("row 1: a served id without a row is RED, and the message carries a paste-ready row stub", () => {
    for (const manifest of [{ "cron-beta": BASE_MANIFEST["cron-beta"] }, {}] as Manifest[]) {
      const g1 = joined(runAll(baseFiles(), manifest).g1);
      expect(g1).toContain(`missing EXECUTION_PLACEMENT row for served function "cron-alpha"`);
      expect(g1).toContain(LEAF_PATH);
      expect(g1).toContain(rowStub("cron-alpha"));
    }
  });

  it("row 2: a row naming no served function is RED (stale)", () => {
    const g1 = joined(runAll(baseFiles(), { ...BASE_MANIFEST, "cron-does-not-exist": { placement: "portable", reason: "x" } }).g1);
    expect(g1).toContain(`stale EXECUTION_PLACEMENT row "cron-does-not-exist"`);
  });

  it("row 3: a spread element in the serve() array fails closed", () => {
    const g1 = joined(runAll(withFiles({ [ROUTE_PATH]: routeSrc({ ...BASE_ROUTE, array: [...BASE_ROUTE.array, "...extraFns"] }) })).g1);
    expect(g1).toContain("`...extraFns` is not a plain identifier");
  });

  it("row 4: a function imported by route.ts but missing from the array is RED", () => {
    const r = runAll(
      withFiles({
        [ROUTE_PATH]: routeSrc({ imports: [...BASE_ROUTE.imports, ["cronFoo", "cron-foo"]], array: BASE_ROUTE.array }),
        "server/inngest/functions/cron-foo.ts": fnSrc("cronFoo", "cron-foo"),
      }),
    );
    expect(joined(r.g1)).toContain("cronFoo is imported from @/server/inngest/functions/cron-foo but missing from the serve() functions array");
  });

  it("row 5: two new served functions, only the FIRST with a row — RED names the second", () => {
    const r = runAll(
      withFiles({
        [ROUTE_PATH]: routeSrc({
          imports: [...BASE_ROUTE.imports, ["cronGamma", "cron-gamma"], ["cronDelta", "cron-delta"]],
          array: [...BASE_ROUTE.array, "cronGamma", "cronDelta"],
        }),
        "server/inngest/functions/cron-gamma.ts": fnSrc("cronGamma", "cron-gamma"),
        "server/inngest/functions/cron-delta.ts": fnSrc("cronDelta", "cron-delta"),
      }),
      { ...BASE_MANIFEST, "cron-gamma": { placement: "host-affine", reason: "x" } },
    );
    expect(r.g1).toHaveLength(1);
    expect(r.g1[0]).toContain(`"cron-delta"`);
  });

  it("row 6: a non-literal function id is RED with the fix", () => {
    const r = runAll(
      withFiles({
        "server/inngest/functions/cron-alpha.ts": `import { inngest } from "@/server/inngest/client";\nconst makeId = () => "cron-alpha";\nexport const cronAlpha = inngest.createFunction({ id: makeId() }, { cron: "0 * * * *" }, async () => null);\n`,
      }),
    );
    expect(joined(r.g1)).toContain("use a string literal or a same-file const");
  });

  it("row 7: an unknown class or an empty reason is RED", () => {
    const bad = runAll(baseFiles(), { ...BASE_MANIFEST, "cron-alpha": { placement: "anywhere", reason: "x" } }).g1;
    expect(joined(bad)).toContain(`placement "anywhere" is not one of`);
    const empty = runAll(baseFiles(), { ...BASE_MANIFEST, "cron-alpha": { placement: "portable", reason: "  " } }).g1;
    expect(joined(empty)).toContain(`row "cron-alpha": reason is empty`);
  });

  it("H1 must-pass: set identity is order-free and ids may carry digits", () => {
    const r = runAll(
      withFiles({
        [ROUTE_PATH]: routeSrc({ imports: [["oneshotX", "oneshot-4217-x"], ...BASE_ROUTE.imports], array: ["cronBeta", "oneshotX", "cronAlpha"] }),
        "server/inngest/functions/oneshot-4217-x.ts": fnSrc("oneshotX", "oneshot-4217-x"),
      }),
      { "oneshot-4217-x": { placement: "host-affine", reason: "x" }, ...BASE_MANIFEST },
    );
    expect(r.g1).toEqual([]);
  });

  it("H2 must-pass: two functions in one module, configs wrapped `as unknown as Parameters<...>[0]`, one id via a same-file const", () => {
    const pair = `import { inngest } from "@/server/inngest/client";
const REQUESTED_ID = "agent-pair-requested";
export const pairSettle = inngest.createFunction(
  { id: "agent-pair-settle", retries: 3 } as unknown as Parameters<typeof inngest.createFunction>[0],
  { event: "x" } as unknown as Parameters<typeof inngest.createFunction>[1],
  (async () => null) as unknown as Parameters<typeof inngest.createFunction>[2],
);
export const pairRequested = inngest.createFunction(
  { id: REQUESTED_ID } as unknown as Parameters<typeof inngest.createFunction>[0],
  { event: "y" } as unknown as Parameters<typeof inngest.createFunction>[1],
  (async () => null) as unknown as Parameters<typeof inngest.createFunction>[2],
);
`;
    const r = runAll(
      withFiles({
        [ROUTE_PATH]: routeSrc({ imports: BASE_ROUTE.imports, array: [...BASE_ROUTE.array, "pairSettle", "pairRequested"], preamble: `import { pairRequested, pairSettle } from "@/server/inngest/functions/agent-pair";\n` }),
        "server/inngest/functions/agent-pair.ts": pair,
      }),
      { ...BASE_MANIFEST, "agent-pair-settle": { placement: "host-affine", reason: "x" }, "agent-pair-requested": { placement: "host-affine", reason: "x" } },
    );
    expect(r.g1).toEqual([]);
    expect(r.served.map((s) => s.id)).toEqual(expect.arrayContaining(["agent-pair-settle", "agent-pair-requested"]));
  });
});

describe("Guard 2 — the portable boundary", () => {
  const alpha = (head: string, body = "null"): Record<string, string> => withFiles({ "server/inngest/functions/cron-alpha.ts": fnSrc("cronAlpha", "cron-alpha", head, body) });

  it("row 1: a portable function importing spawnClaudeEval is RED, and the message names the re-class fix", () => {
    const g2 = joined(runAll(alpha(`import { spawnClaudeEval } from "./_cron-claude-eval-substrate";`)).g2);
    expect(g2).toContain("portable cron-alpha reaches `spawnClaudeEval`");
    expect(g2).toContain("re-class it to the tightest class");
    expect(g2).toContain("never widen PORTABLE_SAFE_SHARED_EXPORTS");
  });

  it("row 2: a non-allowlisted _cron-shared export is RED", () => {
    expect(joined(runAll(alpha(`import { postSentryHeartbeat, resolveCronWorkspaceRoot } from "./_cron-shared";`)).g2)).toContain("`resolveCronWorkspaceRoot`");
  });

  it("row 3: own dispatch — a resolver that drops every @/ edge trips the in-helper floor", () => {
    const dropAt: WalkOptions["resolver"] = (spec, from, fs) => (spec.startsWith("@/") ? null : resolveSpecifier(spec, from, fs));
    const g2 = joined(runAll(baseFiles(), BASE_MANIFEST, { walkOpts: { resolver: dropAt } }).g2);
    expect(g2).toContain("portable cron-alpha: its closure is");
    expect(g2).toContain("resolved no @/server/* edge");
  });

  it("row 4: of two portable functions, the second reaching child_process two hops away is named", () => {
    const r = runAll(
      withFiles({
        [ROUTE_PATH]: routeSrc({ imports: [...BASE_ROUTE.imports, ["cronGamma", "cron-gamma"]], array: [...BASE_ROUTE.array, "cronGamma"] }),
        "server/inngest/functions/cron-gamma.ts": fnSrc("cronGamma", "cron-gamma", `import { hop1 } from "@/server/hop1";`, "hop1()"),
        "server/hop1.ts": `import { hop2 } from "./hop2";\nexport const hop1 = () => hop2();\n`,
        "server/hop2.ts": `import { execFileSync } from "node:child_process";\nexport const hop2 = () => execFileSync("git");\n`,
      }),
      { ...BASE_MANIFEST, "cron-gamma": { placement: "portable", reason: "x" } },
    );
    expect(r.g2).toHaveLength(1);
    expect(r.g2[0]).toContain("portable cron-gamma reaches `node:child_process` via server/hop2.ts");
  });

  it("row 5: an aliased non-allowlisted import is judged by its original name", () => {
    expect(joined(runAll(alpha(`import { resolveCronWorkspaceRoot as r } from "./_cron-shared";`)).g2)).toContain("`resolveCronWorkspaceRoot`");
  });

  it("row 6: an allowlisted export that calls a helper importing child_process is RED (the walk descends through the definer)", () => {
    const shared = FX_SHARED.replace(
      "function heartbeatUrl(slug: string): string {",
      `import { runGit } from "@/server/git-helper";\nfunction heartbeatUrl(slug: string): string {\n  runGit();`,
    );
    const r = runAll(withFiles({ "server/inngest/functions/_cron-shared.ts": shared, "server/git-helper.ts": `import { execFileSync } from "node:child_process";\nexport const runGit = () => execFileSync("git");\n` }));
    expect(joined(r.g2)).toContain("portable cron-alpha reaches `node:child_process` via server/git-helper.ts");
  });

  it.each([
    ["namespace import", `import * as shared from "./_cron-shared";`, "a namespace import of server/inngest/functions/_cron-shared.ts"],
    ["dynamic import()", `const load = () => import("./_cron-shared");`, "a dynamic import()/require() of server/inngest/functions/_cron-shared.ts"],
  ])("row 7: a %s of a definer is RED", (_l, head, want) => {
    expect(joined(runAll(alpha(head)).g2)).toContain(want);
  });

  it("row 8: `await import(\"node:child_process\")` in a reached helper is RED", () => {
    const r = runAll(
      withFiles({
        "server/inngest/functions/cron-alpha.ts": fnSrc("cronAlpha", "cron-alpha", `import { later } from "@/server/later";`, "later()"),
        "server/later.ts": `export async function later() {\n  const cp = await import("node:child_process");\n  return cp;\n}\n`,
      }),
    );
    expect(joined(r.g2)).toContain("reaches `node:child_process` via server/later.ts");
  });

  it("row 9: a closure module reading process.env.WORKSPACES_ROOT is RED", () => {
    const r = runAll(
      withFiles({
        "server/inngest/functions/cron-alpha.ts": fnSrc("cronAlpha", "cron-alpha", `import { root } from "@/server/ws-root";`, "root()"),
        "server/ws-root.ts": `export const root = () => process.env.WORKSPACES_ROOT;\n`,
      }),
    );
    expect(joined(r.g2)).toContain("reaches process.env.WORKSPACES_ROOT via server/ws-root.ts");
  });

  it("row 10: an allowlisted export that calls a same-file helper calling resolveCronWorkspaceRoot is RED (chokepoint iii)", () => {
    const shared = FX_SHARED.replace("return heartbeatUrl(slug);", "return viaRoot(slug);").concat(
      `function viaRoot(slug: string): string {\n  return resolveCronWorkspaceRoot() + slug;\n}\n`,
    );
    const g2 = joined(runAll(withFiles({ "server/inngest/functions/_cron-shared.ts": shared })).g2);
    expect(g2).toContain("`postSentryHeartbeat` is in PORTABLE_SAFE_SHARED_EXPORTS but is no longer host-free");
    expect(g2).toContain("the non-allowlisted export `resolveCronWorkspaceRoot`");
  });

  it("row 11: a re-export of a non-allowlisted definer name is RED", () => {
    const r = runAll(
      withFiles({
        "server/inngest/functions/cron-alpha.ts": fnSrc("cronAlpha", "cron-alpha", `import { resolveCronWorkspaceRoot } from "@/server/reexp";`, "resolveCronWorkspaceRoot()"),
        "server/reexp.ts": `export { resolveCronWorkspaceRoot } from "./inngest/functions/_cron-shared";\n`,
      }),
    );
    expect(joined(r.g2)).toContain("`resolveCronWorkspaceRoot` (re-exported from server/inngest/functions/_cron-shared.ts");
  });

  it("H1: a manifest with zero portable rows trips the checked-count assertion", () => {
    const manifest: Manifest = { ...BASE_MANIFEST, "cron-alpha": { placement: "host-affine", reason: "x" } };
    const r = runAll(baseFiles(), manifest);
    expect(r.g2result.checkedCount).toBe(0);
    expect(checkedCountViolation(r.g2result, manifest)).toContain("it must check every one, and at least one");
    expect(checkedCountViolation(runAll(baseFiles()).g2result, BASE_MANIFEST)).toBeNull();
  });

  it("H2 must-pass: aliased allowlisted names plus type-only specifiers of both definers", () => {
    const r = runAll(
      alpha(
        `import { postSentryHeartbeat as beat, REPO_OWNER, type HandlerArgs } from "./_cron-shared";\nimport { type SpawnResult } from "./_cron-claude-eval-substrate";\nexport type Both = HandlerArgs | SpawnResult;`,
        "beat(REPO_OWNER)",
      ),
    );
    expect(r.g2).toEqual([]);
  });

  it("H3 must-pass: a host-affine function importing spawnClaudeEval is not guarded (over-pinning is safe)", () => {
    expect(runAll(baseFiles()).g2).toEqual([]);
    expect(baseFiles()["server/inngest/functions/cron-beta.ts"]).toContain("spawnClaudeEval");
  });
});

describe("Guard 3 — anti-circularity", () => {
  const LUKS_DISPATCH = `const WORKFLOW_FILE = "workspaces-luks-verify.yml";\nexport const wf = WORKFLOW_FILE;`;

  it("row 1: a served dispatcher naming workspaces-luks-verify.yml is RED, with the #6808 pointer", () => {
    const g3 = joined(runAll(withFiles({ "server/inngest/functions/cron-alpha.ts": fnSrc("cronAlpha", "cron-alpha", LUKS_DISPATCH) })).g3);
    expect(g3).toContain(`names the forbidden workflow "workspaces-luks-verify" (HOST_STATE_VERIFIER_WORKFLOWS)`);
    expect(g3).toContain("#6808");
  });

  it("row 2: a helper outside server/inngest/ reached from a served cron is covered by the closure walk", () => {
    const r = runAll(
      withFiles({
        "server/inngest/functions/cron-alpha.ts": fnSrc("cronAlpha", "cron-alpha", `import { dispatch } from "@/server/github/dispatch-luks";`, "dispatch()"),
        "server/github/dispatch-luks.ts": `export const dispatch = () => "workspaces-luks-verify";\n`,
      }),
    );
    expect(joined(r.g3)).toContain(`server/github/dispatch-luks.ts names the forbidden workflow "workspaces-luks-verify"`);
  });

  it("row 3: own dispatch — an empty forbidden set is RED, and the positive fixture fires under the real set", () => {
    const fs = memFs(withFiles({ "server/inngest/functions/cron-alpha.ts": fnSrc("cronAlpha", "cron-alpha", LUKS_DISPATCH) }));
    const { served } = servedFunctions(fs);
    const empty = circularityViolations({ served, fs, forbidden: forbiddenWorkflows([], []), exemptions: {} }).offenders;
    expect(joined(empty)).toContain("the forbidden verifier set is empty");
    const real = circularityViolations({ served, fs, forbidden: FX_FORBIDDEN, exemptions: {} }).offenders;
    expect(joined(real)).toContain(`names the forbidden workflow "workspaces-luks-verify"`);
  });

  it("row 4: a second watchdog-table row is forbidden because the set is derived from the table", () => {
    const fs = memFs(
      withFiles({
        "server/inngest/functions/cron-alpha.ts": fnSrc("cronAlpha", "cron-alpha", `export const wf = "x-verify.yml";`),
        "/fx/.github/workflows/x-verify.yml": "on: {}\n",
      }),
    );
    const { served } = servedFunctions(fs);
    const forbidden = forbiddenWorkflows([{ workflowFile: "scheduled-inngest-health.yml" }, { workflowFile: "x-verify.yml" }], ["workspaces-luks-verify.yml"]);
    expect(joined(circularityViolations({ served, fs, forbidden, exemptions: {} }).offenders)).toContain(`"x-verify" (WATCHDOG_DISPATCH_TABLE)`);
  });

  it("row 5: a verifier naming a workflow absent from .github/workflows/ is RED (stale)", () => {
    const fs = memFs(baseFiles());
    const { served } = servedFunctions(fs);
    const forbidden = forbiddenWorkflows([{ workflowFile: "scheduled-inngest-health.yml" }], ["workspaces-luks-verify.yml", "gone-verify.yml"]);
    expect(joined(circularityViolations({ served, fs, forbidden, exemptions: {} }).offenders)).toContain("forbidden workflow gone-verify.yml (HOST_STATE_VERIFIER_WORKFLOWS) does not exist");
  });

  describe("row 6: the dynamic-import exemption is exact", () => {
    const EX: DynamicImportExemptions = { "server/inngest/functions/cron-ux.ts": { counts: { botFixturePath: 2, botSigninPath: 1 }, reason: "x" } };
    const uxBody = (a: string, b: string, c: string) =>
      `const botFixturePath = "/p/f.ts";\nconst botSigninPath = "/p/s.ts";\nconst x = "/p/x.ts";\nexport async function ux() {\n  await import(/* turbopackIgnore: true */ ${a});\n  await import(${b});\n  await import(${c});\n}\n`;
    const files = (ux: string, extra: Record<string, string> = {}) =>
      withFiles({
        [ROUTE_PATH]: routeSrc({ imports: [...BASE_ROUTE.imports, ["cronUx", "cron-ux"]], array: [...BASE_ROUTE.array, "cronUx"] }),
        "server/inngest/functions/cron-ux.ts": fnSrc("cronUx", "cron-ux", ux),
        ...extra,
      });
    const g3 = (f: Record<string, string>) => runAll(f, { ...BASE_MANIFEST, "cron-ux": { placement: "host-affine", reason: "x" } }, { exemptions: EX }).g3;

    it("must-pass: exactly botFixturePath×2 and botSigninPath×1", () => {
      expect(g3(files(uxBody("botFixturePath", "botFixturePath", "botSigninPath")))).toEqual([]);
    });
    it("(a) a third botFixturePath import is RED", () => {
      const ux = uxBody("botFixturePath", "botFixturePath", "botSigninPath").replace("\n}\n", "\n  await import(botFixturePath);\n}\n");
      expect(joined(g3(files(ux)))).toContain("server/inngest/functions/cron-ux.ts: non-literal import()/require() (botFixturePath×3, botSigninPath×1)");
    });
    it("(b) swapping botSigninPath for x (same total) is RED", () => {
      expect(joined(g3(files(uxBody("botFixturePath", "botFixturePath", "x"))))).toContain("(botFixturePath×2, x×1)");
    });
    it("(c) a non-literal import in another file is RED", () => {
      const r = g3(
        files(uxBody("botFixturePath", "botFixturePath", "botSigninPath").replace("export async function ux", `import { other } from "@/server/other";\nexport async function ux`), {
          "server/other.ts": `const x = "./y";\nexport const other = () => import(x);\n`,
        }),
      );
      expect(joined(r)).toContain("server/other.ts: non-literal import()/require() (x×1)");
    });
  });

  it("row 7: an .mjs module under server/inngest/ naming a forbidden stem is RED", () => {
    const r = runAll(withFiles({ "server/inngest/hook.mjs": `export const target = "scheduled-inngest-health";\n` }));
    expect(joined(r.g3)).toContain(`server/inngest/hook.mjs names the forbidden workflow "scheduled-inngest-health"`);
  });

  it("H1 must-pass: comments mentioning a forbidden stem do not count", () => {
    const r = runAll(withFiles({ "server/inngest/functions/cron-alpha.ts": fnSrc("cronAlpha", "cron-alpha", `// dispatches nothing like workspaces-luks-verify\n/** not workspaces-luks-verify.yml either */`) }));
    expect(r.g3).toEqual([]);
  });

  it("H2 must-pass: a *.test.ts under server/inngest/ is listed but filtered", () => {
    const files = withFiles({ "server/inngest/functions/cron-alpha.test.ts": `export const wf = "scheduled-inngest-health.yml";\n` });
    expect(memFs(files).listFiles(join(FX_APP, "server/inngest"))).toContain(join(FX_APP, "server/inngest/functions/cron-alpha.test.ts"));
    expect(runAll(files).g3).toEqual([]);
  });
});

describe("Guard 4 — single step-executing host (serve-URL anchor)", () => {
  const route = (o: Partial<Parameters<typeof routeSrc>[0]>) => withFiles({ [ROUTE_PATH]: routeSrc({ ...BASE_ROUTE, ...o }) });
  const FUNCTION_REGISTRY_G_REGEX = /const SERVE_HOST\s*=\s*[\s\S]*process\.env\.NODE_ENV\s*===\s*["']production["'][\s\S]*["']https:\/\/app\.soleur\.ai["']/;

  it("row 1: a moved production literal is RED even while a comment still names app.soleur.ai (guard (g)'s regex stays green)", () => {
    const files = route({ prodBranch: `"https://worker.soleur.ai"`, postamble: `// the old origin was "https://app.soleur.ai"\n` });
    expect(FUNCTION_REGISTRY_G_REGEX.test(files[ROUTE_PATH])).toBe(true);
    const g4 = joined(runAll(files).g4);
    expect(g4).toContain(`the production branch of SERVE_HOST must be the string literal "${PROD_SERVE_URL}", found \`"https://worker.soleur.ai"\``);
  });

  it("row 2: own dispatch — a renamed SERVE_HOST declaration fails closed", () => {
    const g4 = joined(runAll(route({ serveHostDecl: `const SERVE_ORIGIN = process.env.NODE_ENV === "production" ? "${PROD_SERVE_URL}" : undefined;\nconst SERVE_HOST = SERVE_ORIGIN;` })).g4);
    expect(g4).toContain("SERVE_HOST is not `process.env.NODE_ENV === \"production\" ? ... : ...`");
    const gone = joined(runAll(withFiles({ [ROUTE_PATH]: routeSrc(BASE_ROUTE).replaceAll("SERVE_HOST", "SERVE_ORIGIN") })).g4);
    expect(gone).toContain("`const SERVE_HOST` not found");
  });

  it("row 3: a second module importing serve (aliased) from another adapter is RED", () => {
    const g4 = joined(runAll(withFiles({ "app/api/inngest-infra/route.ts": `import { serve as s } from "inngest/express";\nexport const h = s;\n` })).g4);
    expect(g4).toContain("[app/api/inngest-infra/route.ts, app/api/inngest/route.ts]");
  });

  it("row 4: serveHost not referencing SERVE_HOST is RED", () => {
    expect(joined(runAll(route({ serveHostProp: "process.env.X" })).g4)).toContain("serve()'s serveHost is `serveHost: process.env.X`");
  });

  it.each([
    ["namespace import", `import * as i from "inngest/next";\nexport const h = i.serve;\n`],
    ["require()", `const { serve } = require("inngest/next");\nexport const h = serve;\n`],
  ])("row 5: a %s of an adapter elsewhere is RED", (_l, src) => {
    expect(joined(runAll(withFiles({ "lib/other-serve.ts": src })).g4)).toContain("lib/other-serve.ts");
  });

  it("H1 must-pass: a parenthesized conditional still anchors the literal", () => {
    const files = route({
      serveHostDecl: `const SERVE_HOST = (process.env.NODE_ENV === "production" ? ("${PROD_SERVE_URL}") : undefined);`,
    });
    expect(runAll(files).g4).toEqual([]);
  });

  it("H2 must-pass: a type-only import of serve and a comment containing `serve(` do not count", () => {
    expect(runAll(withFiles({ "lib/types.ts": `import type { serve } from "inngest/next";\n// call serve( here someday\nexport type S = typeof serve;\n` })).g4).toEqual([]);
  });
});
