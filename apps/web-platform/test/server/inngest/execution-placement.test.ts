// Inngest execution placement (#7230, ADR-033 amendment 2026-09-28).
//
// server/inngest/execution-placement.ts records, per served Inngest function, where it COULD run
// (portable / host-affine / volume-bound). Four guards bind that record to the code:
//
//   Guard 1  the manifest covers exactly the served set, keyed by Inngest function id;
//   Guard 2  a `portable` function cannot reach a host-local dependency;
//   Guard 3  no Inngest-executed module names an external-only verifier of its own substrate
//            (ADR-033's anti-circularity corollary, #6808);
//   Guard 4  exactly one module reaches an Inngest step-executor API, and its production serve URL
//            is exactly https://app.soleur.ai (the app half of single-host execution; the DNS half
//            is infra/lb-weight-gate.test.sh Condition C).
//
// Guards 3 and 4 are REGRESSION LINTS over string literals and import edges, not proofs: the ADR-033
// amendment lists the shapes they cannot see. Each guard is a pure helper over a GraphFs seam; the
// real-tree tests and the synthesized fixture rows call the same helpers, the fixtures with an
// in-memory filesystem and fixture-sized config (cq-test-fixtures-synthesized-only).

import { join, resolve } from "node:path";
import ts from "typescript";
import { describe, expect, it } from "vitest";
import { EXECUTION_PLACEMENT, EXECUTION_PLACEMENTS } from "@/server/inngest/execution-placement";
import { WATCHDOG_DISPATCH_TABLE } from "@/server/watchdog-dispatch-table";
import {
  type GraphFs,
  type ModuleEdge,
  type WalkOptions,
  isImportOrRequireCall,
  moduleEdges,
  parseModule,
  realFs,
  relTo,
  resolveSpecifier,
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
  // #9274: pure Octokit + REPO_* constants — no host-local dependency. The
  // first portable caller is cron-bot-pr-reaper (the prior caller,
  // cron-content-publisher, was already host-affine so it never needed this).
  "ensureDedupIssue",
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

/** Bare modules whose import alone is a host-local capability (a process, a thread, a Claude spawn). */
const HOST_LOCAL_MODULES: ReadonlySet<string> = new Set([
  "child_process",
  "node:child_process",
  "worker_threads",
  "node:worker_threads",
  "cluster",
  "node:cluster",
  "execa",
  "simple-git",
  "@anthropic-ai/claude-agent-sdk",
]);

/** Calls that load a module the walker cannot see. */
const OPAQUE_LOADERS: ReadonlySet<string> = new Set(["createRequire", "getBuiltinModule"]);

type DynamicImportExemptions = Readonly<Record<string, { counts: Readonly<Record<string, number>>; reason: string }>>;

/** The only non-literal dynamic imports any served closure may carry, counted per argument. */
const DYNAMIC_IMPORT_EXEMPTIONS: DynamicImportExemptions = {
  "server/inngest/functions/cron-ux-audit.ts": {
    counts: { botFixturePath: 2, botSigninPath: 1 },
    reason:
      "loads plugins/soleur/skills/ux-audit/scripts/bot-{fixture,signin}.ts by a runtime path (turbopackIgnore); outside the walked closure — a known gap in the ADR-033 amendment",
  },
};

const LEAF_PATH = "server/inngest/execution-placement.ts";
const LEAF_REPO_PATH = `apps/web-platform/${LEAF_PATH}`;
const ROUTE_PATH = "app/api/inngest/route.ts";
const PROD_SERVE_URL = "https://app.soleur.ai";
const CLASSES: ReadonlySet<string> = new Set(EXECUTION_PLACEMENTS);
const CLASS_RULE =
  "volume-bound if it reads WORKSPACES_ROOT or reaches server/workspace*.ts; else host-affine if it spawns Claude or a child process, clones under CRON_WORKSPACE_ROOT, or takes the deploy lease; else portable";
/** `inngest` itself and every subpath (`inngest/next`, `inngest/deno/fresh`, `inngest/connect`, …). */
const INNGEST_MODULE_RE = /^inngest(\/.+)?$/;
/** The SDK exports that execute steps for a remote Inngest server. */
const STEP_EXECUTOR_EXPORTS: ReadonlySet<string> = new Set(["serve", "connect", "createServer", "InngestCommHandler"]);
const SOURCE_FILE_RE = /\.(ts|tsx|js|mjs|cjs)$/;
const TEST_FILE_RE = /\.test\.(ts|tsx|js|mjs|cjs)$/;
const VOLUME_LITERAL_PREFIXES = ["/workspaces", "/mnt/data"];
const WORKSPACE_ENV_VARS: ReadonlySet<string> = new Set(["WORKSPACES_ROOT", "CRON_WORKSPACE_ROOT"]);

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

/** Text of every string-literal-shaped node under `root` (comments are not nodes, so never count). */
function stringLiteralTexts(root: ts.Node): string[] {
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
  visit(root);
  return out;
}

const volumeLiterals = (root: ts.Node): string[] =>
  stringLiteralTexts(root).filter((t) => VOLUME_LITERAL_PREFIXES.some((p) => t.startsWith(p)));

/** `process.env`, `process["env"]`, `globalThis.process.env`. */
function isProcessEnv(e: ts.Expression): boolean {
  const x = unwrap(e);
  let key: string | null = null;
  let obj: ts.Expression | null = null;
  if (ts.isPropertyAccessExpression(x)) {
    key = x.name.text;
    obj = unwrap(x.expression);
  } else if (ts.isElementAccessExpression(x)) {
    key = stringValue(x.argumentExpression);
    obj = unwrap(x.expression);
  }
  if (key !== "env" || !obj) return false;
  if (ts.isIdentifier(obj)) return obj.text === "process";
  return ts.isPropertyAccessExpression(obj) && obj.name.text === "process" && ts.isIdentifier(obj.expression) && obj.expression.text === "globalThis";
}

/**
 * Workspace-root env reads under `root`: direct (`process.env.X`, `process.env["X"]`), destructured
 * (`const { X } = process.env`, also in a parameter), through an alias (`const e = process.env`,
 * `env = process.env` defaults, `import { env } from "node:process"`). A computed key
 * (`process.env[name]`) is a recorded gap: generic secret readers use one on every path.
 */
function workspaceEnvReads(root: ts.Node, sf: ts.SourceFile): string[] {
  const aliases = new Set<string>();
  for (const e of moduleEdges(sf)) {
    if (e.spec === "process" || e.spec === "node:process") for (const b of e.named) if (b.imported === "env" && !b.typeOnly) aliases.add(b.local);
  }
  const collectAliases = (n: ts.Node): void => {
    if ((ts.isVariableDeclaration(n) || ts.isParameter(n)) && ts.isIdentifier(n.name) && n.initializer && isProcessEnv(n.initializer)) {
      aliases.add(n.name.text);
    }
    ts.forEachChild(n, collectAliases);
  };
  collectAliases(sf);
  const isEnv = (e: ts.Expression): boolean => {
    const u = unwrap(e);
    return isProcessEnv(u) || (ts.isIdentifier(u) && aliases.has(u.text));
  };

  const out: string[] = [];
  const visit = (n: ts.Node): void => {
    if (ts.isPropertyAccessExpression(n) && isEnv(n.expression) && WORKSPACE_ENV_VARS.has(n.name.text)) {
      out.push(n.name.text);
    } else if (ts.isElementAccessExpression(n) && isEnv(n.expression)) {
      const k = stringValue(n.argumentExpression);
      if (k !== null && WORKSPACE_ENV_VARS.has(k)) out.push(k);
    } else if ((ts.isVariableDeclaration(n) || ts.isParameter(n)) && ts.isObjectBindingPattern(n.name) && n.initializer && isEnv(n.initializer)) {
      for (const el of n.name.elements) {
        const pn = el.propertyName;
        const k = pn ? (ts.isIdentifier(pn) || ts.isStringLiteral(pn) ? pn.text : null) : el.name.getText(sf);
        if (k !== null && WORKSPACE_ENV_VARS.has(k)) out.push(k);
      }
    }
    ts.forEachChild(n, visit);
  };
  visit(root);
  return out;
}

/** Calls under `root` to a loader the walker cannot see through (`createRequire`, `getBuiltinModule`). */
function opaqueLoaderCalls(root: ts.Node): string[] {
  const out: string[] = [];
  const visit = (n: ts.Node): void => {
    if (ts.isCallExpression(n)) {
      const callee = unwrap(n.expression);
      const name = ts.isIdentifier(callee) ? callee.text : ts.isPropertyAccessExpression(callee) ? callee.name.text : null;
      if (name && OPAQUE_LOADERS.has(name)) out.push(name);
    }
    ts.forEachChild(n, visit);
  };
  visit(root);
  return out;
}

/** Literal `require()`/`import()` of a host-local module under `root`. */
function hostLocalCalls(root: ts.Node): string[] {
  const out: string[] = [];
  const visit = (n: ts.Node): void => {
    if (isImportOrRequireCall(n)) {
      const s = stringValue(n.arguments[0]);
      if (s && HOST_LOCAL_MODULES.has(s)) out.push(s);
    }
    ts.forEachChild(n, visit);
  };
  visit(root);
  return out;
}

const isValueEdge = (e: ModuleEdge): boolean => !e.typeOnly;

/** Local names bound, as values, by the file's static imports: local -> { spec, imported }. */
function importBindings(sf: ts.SourceFile): Map<string, { spec: string; imported: string }> {
  const out = new Map<string, { spec: string; imported: string }>();
  for (const e of moduleEdges(sf)) {
    if ((e.form !== "import" && e.form !== "import-equals") || e.spec === null || e.typeOnly) continue;
    if (e.defaultLocal) out.set(e.defaultLocal, { spec: e.spec, imported: "default" });
    if (e.namespaceLocal) out.set(e.namespaceLocal, { spec: e.spec, imported: "*" });
    for (const b of e.named) if (!b.typeOnly) out.set(b.local, { spec: e.spec, imported: b.imported });
  }
  return out;
}

/** Throwing `replace`: a fixture edit whose anchor is missing must fail the row, not no-op. */
function mustReplace(src: string, anchor: string, replacement: string): string {
  if (!src.includes(anchor)) throw new Error(`fixture anchor not found: ${anchor}`);
  return src.replace(anchor, replacement);
}

// ---------------------------------------------------------------------------
// Guard 1 — the served set, derived from route.ts, and the manifest's coverage of it
// ---------------------------------------------------------------------------

interface Served {
  module: string;
  id: string;
}

/** Local names route.ts binds to `serve` from an Inngest module. */
function serveLocals(sf: ts.SourceFile): Set<string> {
  const out = new Set<string>();
  for (const [local, { spec, imported }] of importBindings(sf)) if (INNGEST_MODULE_RE.test(spec) && imported === "serve") out.add(local);
  return out;
}

function serveCalls(sf: ts.SourceFile): ts.CallExpression[] {
  const locals = serveLocals(sf);
  const out: ts.CallExpression[] = [];
  const visit = (n: ts.Node): void => {
    if (ts.isCallExpression(n) && ts.isIdentifier(n.expression) && locals.has(n.expression.text)) out.push(n);
    ts.forEachChild(n, visit);
  };
  visit(sf);
  return out;
}

/**
 * The keys a spread inside an object literal can contribute, or null when the guard cannot read
 * them (anything but object literals behind parentheses and conditionals).
 */
function spreadKeys(e: ts.Expression): Set<string> | null {
  const x = unwrap(e);
  if (ts.isConditionalExpression(x)) {
    const a = spreadKeys(x.whenTrue);
    const b = spreadKeys(x.whenFalse);
    return a && b ? new Set([...a, ...b]) : null;
  }
  if (!ts.isObjectLiteralExpression(x)) return null;
  const keys = new Set<string>();
  for (const p of x.properties) {
    if (ts.isSpreadAssignment(p)) {
      const inner = spreadKeys(p.expression);
      if (!inner) return null;
      for (const k of inner) keys.add(k);
    } else if (p.name && (ts.isIdentifier(p.name) || ts.isStringLiteral(p.name))) keys.add(p.name.text);
    else return null;
  }
  return keys;
}

/** Offenders for a config literal whose spreads could override `key` (fail-closed when unreadable). */
function spreadOverrideProblems(obj: ts.ObjectLiteralExpression, key: string, where: string): string[] {
  const out: string[] = [];
  for (const p of obj.properties) {
    if (!ts.isSpreadAssignment(p)) continue;
    const keys = spreadKeys(p.expression);
    if (!keys) out.push(`${where}: a spread the guard cannot read could override \`${key}\` — spell \`${key}\` out as a plain property (fail-closed)`);
    else if (keys.has(key)) out.push(`${where}: a spread overrides \`${key}\` — the guard reads only the plain \`${key}\` property`);
  }
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
      const spread = spreadOverrideProblems(cfg, "id", where);
      if (spread.length) return { error: spread.join("\n") };
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
  for (const [local, b] of importBindings(sf)) {
    if (b.spec.startsWith("@/server/inngest/functions/") && b.imported !== "*" && b.imported !== "default") fnImports.set(local, b);
  }

  const calls = serveCalls(sf);
  if (calls.length !== 1) {
    return { served: [], offenders: [`${ROUTE_PATH}: expected exactly one serve() call, found ${calls.length} (fail-closed)`] };
  }
  const arg = calls[0].arguments[0] ? unwrap(calls[0].arguments[0]) : undefined;
  if (!arg || !ts.isObjectLiteralExpression(arg)) {
    return { served: [], offenders: [`${ROUTE_PATH}: the serve() config is not an object literal (fail-closed)`] };
  }
  offenders.push(...spreadOverrideProblems(arg, "functions", ROUTE_PATH));
  const fnsProps = arg.properties.filter(
    (p): p is ts.PropertyAssignment => ts.isPropertyAssignment(p) && ts.isIdentifier(p.name) && p.name.text === "functions",
  );
  const arr = fnsProps.length === 1 ? unwrap(fnsProps[0].initializer) : undefined;
  if (!arr || !ts.isArrayLiteralExpression(arr)) {
    return { served: [], offenders: [...offenders, `${ROUTE_PATH}: serve() needs exactly one \`functions: [ ... ]\` array literal (fail-closed)`] };
  }

  const idents: string[] = [];
  for (const el of arr.elements) {
    if (ts.isIdentifier(el)) idents.push(el.text);
    else offenders.push(`${ROUTE_PATH}: serve() functions element \`${el.getText(sf)}\` is not a plain identifier — the placement guard cannot resolve it (fail-closed)`);
  }
  const seen = new Set<string>();
  for (const i of idents) {
    if (seen.has(i)) offenders.push(`${ROUTE_PATH}: \`${i}\` is listed twice in the serve() functions array — remove the duplicate`);
    seen.add(i);
    if (!fnImports.has(i)) offenders.push(`${ROUTE_PATH}: served identifier \`${i}\` is not a named import from @/server/inngest/functions/* — import it by name from its module`);
  }
  for (const [i, { spec }] of fnImports) {
    if (!seen.has(i)) offenders.push(`${ROUTE_PATH}: \`${i}\` is imported from ${spec} but missing from the serve() functions array — serve it or drop the import`);
  }

  const served: Served[] = [];
  for (const ident of seen) {
    const imp = fnImports.get(ident);
    if (!imp) continue;
    const mod = resolveSpecifier(imp.spec, routeAbs, fs);
    if (!mod || mod === "unresolved") {
      offenders.push(`${ROUTE_PATH}: cannot resolve ${imp.spec} (fail-closed)`);
      continue;
    }
    const id = functionIdOf(fs, mod, imp.imported);
    if (typeof id === "string") served.push({ module: mod, id });
    else offenders.push(id.error);
  }
  return { served, offenders };
}

function rowStub(id: string): string {
  return `  "${id}": { placement: "<${EXECUTION_PLACEMENTS.join(" | ")}>", reason: "<the marker that pins it, or why it is host-free>" },`;
}

function manifestViolations(served: Served[], manifest: Manifest, fs: GraphFs): string[] {
  const out: string[] = [];
  const byId = new Map<string, string>();
  for (const s of served) {
    const prior = byId.get(s.id);
    if (prior) out.push(`function id "${s.id}" is served twice (${prior} and ${relTo(fs, s.module)}) — ids must be unique`);
    byId.set(s.id, relTo(fs, s.module));
  }
  for (const s of served) {
    if (!Object.hasOwn(manifest, s.id)) {
      out.push(
        `missing EXECUTION_PLACEMENT row for served function "${s.id}" (${relTo(fs, s.module)}). Add to ${LEAF_REPO_PATH}, classed by the first rule that matches (${CLASS_RULE}):\n${rowStub(s.id)}`,
      );
    }
  }
  for (const k of Object.keys(manifest)) {
    if (!byId.has(k)) out.push(`stale EXECUTION_PLACEMENT row "${k}": no served function has that id — delete it from ${LEAF_REPO_PATH}`);
  }
  for (const [k, v] of Object.entries(manifest)) {
    if (!CLASSES.has(v.placement)) out.push(`row "${k}": placement "${v.placement}" is not one of ${EXECUTION_PLACEMENTS.join(" | ")}`);
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
  for (const e of moduleEdges(sf)) {
    if (e.spec === null || !isValueEdge(e)) continue;
    const t = resolver(e.spec, m, fs);
    if (!t || t === "unresolved" || !isDefiner(fs, t)) continue;
    const def = relTo(fs, t);
    const add = (detail: string): void => {
      out.push({ module: m, detail });
    };
    if (e.form === "call") add(`a dynamic import()/require() of ${def}`);
    else if (e.form === "import-equals") add(`\`import = require()\` of ${def}`);
    else if (e.sideEffect) add(`a side-effect import of ${def}`);
    else if (e.starExport) add(`\`export * from\` ${def}`);
    else {
      if (e.defaultLocal) add(`a default import of ${def}`);
      if (e.namespaceLocal) add(`a namespace ${e.form === "export" ? "re-export" : "import"} of ${def}`);
      const verb = e.form === "export" ? "re-exported from" : "imported from";
      for (const b of e.named) {
        if (!b.typeOnly && !allowlist.has(b.imported)) add(`\`${b.imported}\` (${verb} ${def}; not in PORTABLE_SAFE_SHARED_EXPORTS)`);
      }
    }
  }
  return out;
}

/** Chokepoint (ii): host-local markers in a closure module's own source. */
function hostLocalMarkers(sf: ts.SourceFile, m: string): Marker[] {
  const out: Marker[] = [];
  for (const e of moduleEdges(sf)) {
    if (e.spec !== null && isValueEdge(e) && HOST_LOCAL_MODULES.has(e.spec)) out.push({ module: m, detail: `\`${e.spec}\`` });
  }
  for (const l of opaqueLoaderCalls(sf)) out.push({ module: m, detail: `the opaque module loader \`${l}\`` });
  for (const lit of volumeLiterals(sf)) out.push({ module: m, detail: `the volume path literal "${lit}"` });
  for (const v of workspaceEnvReads(sf, sf)) out.push({ module: m, detail: `process.env .${v}` });
  return out;
}

interface TopDecl {
  node: ts.Node;
  exported: boolean;
}

function topLevelDecls(sf: ts.SourceFile): Map<string, TopDecl> {
  const out = new Map<string, TopDecl>();
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
    }
  }
  return out;
}

/** `export { local as Exported }` (no module specifier): exported name -> local name. */
function localExportAliases(sf: ts.SourceFile): Map<string, string> {
  const out = new Map<string, string>();
  for (const st of sf.statements) {
    if (ts.isExportDeclaration(st) && !st.moduleSpecifier && st.exportClause && ts.isNamedExports(st.exportClause) && !st.isTypeOnly) {
      for (const el of st.exportClause.elements) if (!el.isTypeOnly) out.set(el.name.text, (el.propertyName ?? el.name).text);
    }
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
 * top-level declarations, must not reach a non-allowlisted export, a host-local module (by import
 * binding or by `require()`/`import()` call), an opaque loader, a volume literal, or a workspace env
 * read. An identifier imported from another module is not followed here: the closure walk descends
 * into that module and chokepoint (ii) scans it.
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
    const aliases = localExportAliases(sf);
    const imports = importBindings(sf);
    const reExported = new Set(
      moduleEdges(sf)
        .filter((e) => e.form === "export")
        .flatMap((e) => e.named.map((b) => b.local)),
    );
    const exportedNames = new Set([...[...tops].filter(([, t]) => t.exported).map(([n]) => n), ...aliases.keys(), ...reExported]);
    for (const name of allowlist) {
      if (!exportedNames.has(name)) continue;
      found.add(name);
      if (reExported.has(name)) continue; // re-exported from another module: that module is walked and scanned
      const fix = `\`${name}\` is in PORTABLE_SAFE_SHARED_EXPORTS but is no longer host-free; remove it from the allowlist and re-class every portable function that imports it`;
      const local = aliases.get(name) ?? name;
      if (!tops.has(local) && !imports.has(local)) {
        out.push(`${d}: cannot locate the declaration of allowlisted \`${name}\` — the body scan would skip it (fail-closed)`);
        continue;
      }
      const seen = new Set<string>();
      const queue = [local];
      while (queue.length) {
        const n = queue.pop()!;
        if (seen.has(n)) continue;
        seen.add(n);
        const decl = tops.get(n);
        if (!decl) {
          const imp = imports.get(n);
          if (imp && HOST_LOCAL_MODULES.has(imp.spec)) out.push(`${d}: ${fix} — it reaches \`${n}\` from ${imp.spec}`);
          continue;
        }
        if (n !== local && decl.exported) {
          if (!allowlist.has(n)) out.push(`${d}: ${fix} — it reaches the non-allowlisted export \`${n}\``);
          continue; // an allowlisted export is scanned in its own right
        }
        for (const lit of volumeLiterals(decl.node)) out.push(`${d}: ${fix} — it reaches the volume path literal "${lit}"`);
        for (const v of workspaceEnvReads(decl.node, sf)) out.push(`${d}: ${fix} — it reaches a process.env read (${v})`);
        for (const c of hostLocalCalls(decl.node)) out.push(`${d}: ${fix} — it loads ${c}`);
        for (const l of opaqueLoaderCalls(decl.node)) out.push(`${d}: ${fix} — it calls the opaque module loader \`${l}\``);
        for (const id of valueIdentifiers(decl.node)) if (id !== n) queue.push(id);
      }
    }
  }
  for (const name of allowlist) {
    if (!found.has(name)) out.push(`PORTABLE_SAFE_SHARED_EXPORTS names \`${name}\`, which no definer module exports — remove the stale entry`);
  }
  return out;
}

interface ModuleScan {
  markers: Marker[];
  /** Local edges from this module that resolved to a module under server/. */
  serverTargets: number;
}

function scanModule(m: string, fs: GraphFs, allowlist: ReadonlySet<string>, resolver: Resolver): ModuleScan {
  const sf = load(fs, m);
  if (!sf) return { markers: [], serverTargets: 0 }; // the walk already reported it
  let serverTargets = 0;
  for (const e of moduleEdges(sf)) {
    if (e.spec === null) continue;
    const t = resolver(e.spec, m, fs);
    if (t && t !== "unresolved" && t.startsWith(join(fs.appRoot, "server") + "/")) serverTargets++;
  }
  const markers = definerEdgeMarkers(sf, m, fs, allowlist, resolver);
  if (!isDefiner(fs, m)) markers.push(...hostLocalMarkers(sf, m));
  return { markers, serverTargets };
}

interface PortableResult {
  offenders: string[];
  checkedCount: number;
}

function portableViolations(args: {
  served: Served[];
  manifest: Manifest;
  fs: GraphFs;
  allowlist: ReadonlySet<string>;
  walkOpts?: WalkOptions;
}): PortableResult {
  const { served, manifest, fs, allowlist, walkOpts } = args;
  const resolver = walkOpts?.resolver ?? resolveSpecifier;
  const offenders = allowlistBodyViolations(fs, allowlist);
  const scans = new Map<string, ModuleScan>(); // per-call memo: the fixture rows vary fs and allowlist
  let checkedCount = 0;
  for (const s of served) {
    if (manifest[s.id]?.placement !== "portable") continue;
    checkedCount++;
    const { reach, problems } = walk(s.module, fs, { ...walkOpts, elideTypeOnlySpecifiers: true });
    for (const p of problems) offenders.push(`portable ${s.id}: ${p} — the walk must be total (fail-closed)`);
    const markers: Marker[] = [];
    let serverTargets = 0;
    for (const m of reach) {
      let scan = scans.get(m);
      if (!scan) {
        scan = scanModule(m, fs, allowlist, resolver);
        scans.set(m, scan);
      }
      markers.push(...scan.markers);
      serverTargets += scan.serverTargets;
    }
    if (markers.length) {
      const list = markers.map((mk) => `${mk.detail} via ${relTo(fs, mk.module)}`).join("; ");
      offenders.push(
        `portable ${s.id} reaches ${list}. Re-class it in ${LEAF_REPO_PATH} by the first rule that matches (${CLASS_RULE}) — never widen PORTABLE_SAFE_SHARED_EXPORTS to make it pass`,
      );
    }
    if (reach.size <= 1 || serverTargets === 0) {
      offenders.push(
        `portable ${s.id}: its closure is ${reach.size} module(s) with no edge resolved into server/ — the walk followed nothing, so the boundary check would be vacuous`,
      );
    }
  }
  return { offenders, checkedCount };
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

const countsKey = (c: Readonly<Record<string, number>>): string =>
  Object.entries(c)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([k, v]) => `${k}×${v}`)
    .join(", ");

function circularityViolations(args: {
  served: Served[];
  fs: GraphFs;
  forbidden: Forbidden[];
  exemptions: DynamicImportExemptions;
}): { offenders: string[]; scanned: Set<string> } {
  const { served, fs, forbidden, exemptions } = args;
  const offenders = new Set<string>();
  if (forbidden.length === 0) offenders.add("the forbidden verifier set is empty — Guard 3 would check nothing (fail-closed)");
  const repoRoot = resolve(fs.appRoot, "../.."); // the app lives at <repo>/apps/web-platform
  for (const f of forbidden) {
    if (!fs.exists(join(repoRoot, ".github/workflows", f.file))) {
      offenders.add(`forbidden workflow ${f.file} (${f.source}) does not exist under .github/workflows/ — a stale entry guards nothing; remove it`);
    }
  }
  const stems = forbidden.map((f) => ({ stem: f.file.replace(/\.ya?ml$/, ""), source: f.source }));

  const scanned = new Set<string>();
  for (const p of fs.listFiles(join(fs.appRoot, "server/inngest"))) {
    if (SOURCE_FILE_RE.test(p) && !TEST_FILE_RE.test(p)) scanned.add(p);
  }
  const r = walk(
    served.map((s) => s.module),
    fs,
    { elideTypeOnlySpecifiers: true, recordDynamicImportArgs: true },
  );
  for (const p of r.problems) offenders.add(`${p} — the anti-circularity walk must be total (fail-closed)`);
  for (const m of r.reach) scanned.add(m);

  const byFile = new Map<string, Record<string, number>>();
  for (const d of r.nonLiteral) {
    const key = relTo(fs, d.file);
    const c = byFile.get(key) ?? {};
    c[d.argText] = (c[d.argText] ?? 0) + 1;
    byFile.set(key, c);
  }
  for (const [file, counts] of byFile) {
    const ex = exemptions[file];
    if (!ex || countsKey(counts) !== countsKey(ex.counts)) {
      offenders.add(
        `${file}: non-literal import()/require() (${countsKey(counts)}) — the walk cannot see where it leads. Use a literal specifier${ex ? `, or update DYNAMIC_IMPORT_EXEMPTIONS (it is exactly ${countsKey(ex.counts)})` : ""}.`,
      );
    }
  }
  for (const [file, ex] of Object.entries(exemptions)) {
    if (!byFile.has(file)) offenders.add(`the dynamic-import exemption for ${file} (${countsKey(ex.counts)}) matches no non-literal import — remove it`);
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
  return { offenders: [...offenders], scanned };
}

// ---------------------------------------------------------------------------
// Guard 4 — one step-executor module, production serve URL exactly https://app.soleur.ai
// ---------------------------------------------------------------------------

/** True when the module binds (or loads opaquely) an Inngest step-executor API. */
function reachesStepExecutor(sf: ts.SourceFile): boolean {
  return moduleEdges(sf).some((e) => {
    if (e.spec === null || !INNGEST_MODULE_RE.test(e.spec) || e.typeOnly) return false;
    if (e.form === "call" || e.form === "import-equals" || e.starExport) return true;
    if (e.namespaceLocal || (e.defaultLocal && e.spec !== "inngest")) return true;
    return e.named.some((b) => !b.typeOnly && STEP_EXECUTOR_EXPORTS.has(b.imported));
  });
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

/** Every file Next can serve or import on the step path: app/, server/, lib/, pages/, src/, root entry files. */
function stepPathFiles(fs: GraphFs): string[] {
  const roots = ["app", "server", "lib", "pages", "src"].flatMap((d) => fs.listFiles(join(fs.appRoot, d)));
  const rootFiles = ["instrumentation", "middleware"].flatMap((b) =>
    ["ts", "tsx", "js", "mjs", "cjs"].map((x) => join(fs.appRoot, `${b}.${x}`)).filter((p) => fs.exists(p)),
  );
  return [...roots, ...rootFiles].filter((p) => SOURCE_FILE_RE.test(p) && !TEST_FILE_RE.test(p) && !p.endsWith(".d.ts"));
}

const SERVE_HOST_RULE = `the production branch of SERVE_HOST must be the string literal "${PROD_SERVE_URL}"`;

function serveAnchorViolations(fs: GraphFs): string[] {
  const out: string[] = [];
  const reaching: string[] = [];
  for (const f of stepPathFiles(fs)) {
    const sf = load(fs, f);
    if (!sf) out.push(`${relTo(fs, f)}: unreadable (fail-closed)`);
    else if (reachesStepExecutor(sf)) reaching.push(relTo(fs, f));
  }
  reaching.sort();
  if (reaching.length !== 1 || reaching[0] !== ROUTE_PATH) {
    out.push(
      `modules reaching an Inngest step-executor API (serve / connect / createServer / InngestCommHandler, or an opaque load of an inngest module): [${reaching.join(", ")}] — expected exactly [${ROUTE_PATH}]. A second executor registers a second step path; revisit the ADR-033 #7230 placement rule first.`,
    );
  }

  const sf = load(fs, join(fs.appRoot, ROUTE_PATH));
  if (!sf) return [...out, `${ROUTE_PATH}: unreadable (fail-closed)`];
  const decl = topLevelDecls(sf).get("SERVE_HOST");
  const init = decl && ts.isVariableDeclaration(decl.node) && decl.node.initializer ? unwrap(decl.node.initializer) : undefined;
  if (!init) {
    out.push(`${ROUTE_PATH}: \`const SERVE_HOST\` not found — ${SERVE_HOST_RULE} (fail-closed)`);
  } else if (!ts.isConditionalExpression(init) || !isNodeEnvProduction(init.condition)) {
    out.push(`${ROUTE_PATH}: SERVE_HOST is not \`process.env.NODE_ENV === "production" ? ... : ...\` — ${SERVE_HOST_RULE}`);
  } else {
    const w = unwrap(init.whenTrue);
    if (!ts.isStringLiteral(w) || w.text !== PROD_SERVE_URL) out.push(`${ROUTE_PATH}: ${SERVE_HOST_RULE}, found \`${init.whenTrue.getText(sf)}\``);
  }

  const calls = serveCalls(sf);
  if (calls.length !== 1) {
    out.push(`${ROUTE_PATH}: expected exactly one serve() call bound from an Inngest module, found ${calls.length} (fail-closed)`);
    return out;
  }
  const hosts: ts.ObjectLiteralElementLike[] = [];
  const visit = (n: ts.Node): void => {
    if ((ts.isPropertyAssignment(n) || ts.isShorthandPropertyAssignment(n)) && ts.isIdentifier(n.name) && n.name.text === "serveHost") hosts.push(n);
    ts.forEachChild(n, visit);
  };
  if (calls[0].arguments[0]) visit(calls[0].arguments[0]);
  if (hosts.length === 0) out.push(`${ROUTE_PATH}: serve() sets no serveHost — it must be \`serveHost: SERVE_HOST\``);
  for (const h of hosts) {
    const v = ts.isPropertyAssignment(h) ? unwrap(h.initializer) : undefined;
    if (!v || !ts.isIdentifier(v) || v.text !== "SERVE_HOST") {
      out.push(`${ROUTE_PATH}: serve()'s serveHost is \`${h.getText(sf)}\` — it must be \`serveHost: SERVE_HOST\` so steps are called at ${PROD_SERVE_URL}`);
    }
  }
  return out;
}

// ===========================================================================
// Real tree
// ===========================================================================

const APP_ROOT = resolve(__dirname, "../../..");
const REAL_FS = realFs(APP_ROOT);
const REAL_TREE_TIMEOUT_MS = 60_000;

describe("execution placement — the real tree (#7230)", () => {
  const real = servedFunctions(REAL_FS);

  it("Guard 1: route.ts resolves to its served functions, each with a statically readable id", () => {
    expect(real.offenders).toEqual([]);
    expect(real.served.length).toBeGreaterThan(0);
  });

  it("Guard 1: EXECUTION_PLACEMENT has exactly one valid row per served function", () => {
    expect(manifestViolations(real.served, EXECUTION_PLACEMENT, REAL_FS)).toEqual([]);
  });

  it("the manifest leaf imports nothing", () => {
    const sf = load(REAL_FS, join(APP_ROOT, LEAF_PATH));
    expect(sf).not.toBeNull();
    expect(moduleEdges(sf!)).toEqual([]);
  });

  it(
    "Guard 2: no portable function reaches a host-local dependency, and every portable row is checked",
    () => {
      const r = portableViolations({ served: real.served, manifest: EXECUTION_PLACEMENT, fs: REAL_FS, allowlist: PORTABLE_SAFE_SHARED_EXPORTS });
      expect(r.offenders).toEqual([]);
      expect(checkedCountViolation(r, EXECUTION_PLACEMENT)).toBeNull();
    },
    REAL_TREE_TIMEOUT_MS,
  );

  it(
    "Guard 3: no Inngest-executed module names an external-only verifier workflow, and every served module is scanned",
    () => {
      const r = circularityViolations({
        served: real.served,
        fs: REAL_FS,
        forbidden: forbiddenWorkflows(WATCHDOG_DISPATCH_TABLE, HOST_STATE_VERIFIER_WORKFLOWS),
        exemptions: DYNAMIC_IMPORT_EXEMPTIONS,
      });
      expect(r.offenders).toEqual([]);
      expect(real.served.filter((s) => !r.scanned.has(s.module)).map((s) => s.id)).toEqual([]);
    },
    REAL_TREE_TIMEOUT_MS,
  );

  it(
    `Guard 4: one step-executor module, and its production serve URL is exactly ${PROD_SERVE_URL}`,
    () => {
      expect(serveAnchorViolations(REAL_FS)).toEqual([]);
    },
    REAL_TREE_TIMEOUT_MS,
  );
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
  configExtra?: string;
  preamble?: string;
  postamble?: string;
}): string {
  const serveHostDecl =
    opts.serveHostDecl ?? `const SERVE_HOST =\n  process.env.NODE_ENV === "production" ? ${opts.prodBranch ?? `"${PROD_SERVE_URL}"`} : undefined;`;
  return `${opts.preamble ?? ""}import { serve } from "inngest/next";
import { inngest } from "@/server/inngest/client";
${opts.imports.map(([i, m]) => `import { ${i} } from "@/server/inngest/functions/${m}";`).join("\n")}

${serveHostDecl}

const handlers = serve({
  client: inngest,
  functions: [${opts.array.join(", ")}],
  ...(SERVE_HOST ? { serveHost: ${opts.serveHostProp ?? "SERVE_HOST"}, servePath: "/api/inngest" } : {}),${opts.configExtra ?? ""}
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
/** A third served function `cronGamma` with the given module source, and its manifest row. */
const withGamma = (src: string, placement = "portable") => ({
  files: withFiles({
    [ROUTE_PATH]: routeSrc({ imports: [...BASE_ROUTE.imports, ["cronGamma", "cron-gamma"]], array: [...BASE_ROUTE.array, "cronGamma"] }),
    "server/inngest/functions/cron-gamma.ts": src,
  }),
  manifest: { ...BASE_MANIFEST, "cron-gamma": { placement, reason: "x" } } as Manifest,
});

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
  it("a served id without a row is RED, and the message carries the classification rule and a paste-ready row stub", () => {
    for (const manifest of [{ "cron-beta": BASE_MANIFEST["cron-beta"] }, {}] as Manifest[]) {
      const g1 = joined(runAll(baseFiles(), manifest).g1);
      expect(g1).toContain(`missing EXECUTION_PLACEMENT row for served function "cron-alpha"`);
      expect(g1).toContain(LEAF_REPO_PATH);
      expect(g1).toContain(CLASS_RULE);
      expect(g1).toContain(rowStub("cron-alpha"));
    }
  });

  it("a row naming no served function is RED (stale)", () => {
    const g1 = joined(runAll(baseFiles(), { ...BASE_MANIFEST, "cron-does-not-exist": { placement: "portable", reason: "x" } }).g1);
    expect(g1).toContain(`stale EXECUTION_PLACEMENT row "cron-does-not-exist"`);
  });

  it("a spread element in the serve() array fails closed", () => {
    const g1 = joined(runAll(withFiles({ [ROUTE_PATH]: routeSrc({ ...BASE_ROUTE, array: [...BASE_ROUTE.array, "...extraFns"] }) })).g1);
    expect(g1).toContain("`...extraFns` is not a plain identifier");
  });

  it("a spread in the serve() config that could override `functions` is RED, readable or not", () => {
    const over = joined(runAll(withFiles({ [ROUTE_PATH]: routeSrc({ ...BASE_ROUTE, configExtra: "\n  ...{ functions: [] }," }) })).g1);
    expect(over).toContain("a spread overrides `functions`");
    const opaque = joined(runAll(withFiles({ [ROUTE_PATH]: routeSrc({ ...BASE_ROUTE, configExtra: "\n  ...extraConfig," }) })).g1);
    expect(opaque).toContain("a spread the guard cannot read could override `functions`");
  });

  it("a function imported by route.ts but missing from the array is RED", () => {
    const r = runAll(
      withFiles({
        [ROUTE_PATH]: routeSrc({ imports: [...BASE_ROUTE.imports, ["cronFoo", "cron-foo"]], array: BASE_ROUTE.array }),
        "server/inngest/functions/cron-foo.ts": fnSrc("cronFoo", "cron-foo"),
      }),
    );
    expect(joined(r.g1)).toContain("`cronFoo` is imported from @/server/inngest/functions/cron-foo but missing from the serve() functions array");
  });

  it("an identifier listed twice, and one id served by two modules, are each RED", () => {
    const twice = joined(runAll(withFiles({ [ROUTE_PATH]: routeSrc({ ...BASE_ROUTE, array: [...BASE_ROUTE.array, "cronAlpha"] }) })).g1);
    expect(twice).toContain("`cronAlpha` is listed twice");
    const { files } = withGamma(fnSrc("cronGamma", "cron-alpha"));
    expect(joined(runAll(files).g1)).toContain(`function id "cron-alpha" is served twice`);
  });

  it("of two new served functions, only the FIRST with a row — RED names the second", () => {
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

  it("an id that is not a literal or a same-file const — a call, a `let`, or a spread-overridable config — is RED", () => {
    const call = `import { inngest } from "@/server/inngest/client";\nconst makeId = () => "cron-alpha";\nexport const cronAlpha = inngest.createFunction({ id: makeId() }, { cron: "0 * * * *" }, async () => null);\n`;
    expect(joined(runAll(withFiles({ "server/inngest/functions/cron-alpha.ts": call })).g1)).toContain("use a string literal or a same-file const");
    const letId = `import { inngest } from "@/server/inngest/client";\nlet ID = "cron-alpha";\nexport const cronAlpha = inngest.createFunction({ id: ID }, { cron: "0 * * * *" }, async () => null);\n`;
    expect(joined(runAll(withFiles({ "server/inngest/functions/cron-alpha.ts": letId })).g1)).toContain("use a string literal or a same-file const");
    const spread = `import { inngest } from "@/server/inngest/client";\nexport const cronAlpha = inngest.createFunction({ id: "cron-alpha", ...more }, { cron: "0 * * * *" }, async () => null);\n`;
    expect(joined(runAll(withFiles({ "server/inngest/functions/cron-alpha.ts": spread })).g1)).toContain("could override `id`");
  });

  it("an unknown class or an empty reason is RED", () => {
    const bad = runAll(baseFiles(), { ...BASE_MANIFEST, "cron-alpha": { placement: "anywhere", reason: "x" } }).g1;
    expect(joined(bad)).toContain(`placement "anywhere" is not one of`);
    const empty = runAll(baseFiles(), { ...BASE_MANIFEST, "cron-alpha": { placement: "portable", reason: "  " } }).g1;
    expect(joined(empty)).toContain(`row "cron-alpha": reason is empty`);
  });

  it("must-pass: set identity is order-free and ids may carry digits", () => {
    const r = runAll(
      withFiles({
        [ROUTE_PATH]: routeSrc({ imports: [["oneshotX", "oneshot-4217-x"], ...BASE_ROUTE.imports], array: ["cronBeta", "oneshotX", "cronAlpha"] }),
        "server/inngest/functions/oneshot-4217-x.ts": fnSrc("oneshotX", "oneshot-4217-x"),
      }),
      { "oneshot-4217-x": { placement: "host-affine", reason: "x" }, ...BASE_MANIFEST },
    );
    expect(r.g1).toEqual([]);
  });

  it("must-pass: two functions in one module, configs wrapped `as unknown as Parameters<...>[0]`, one id via a same-file const", () => {
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
  const DEF = "server/inngest/functions/_cron-shared.ts";

  it("a portable function importing spawnClaudeEval is RED, and the message names the rule and the never-widen fix", () => {
    const g2 = joined(runAll(alpha(`import { spawnClaudeEval } from "./_cron-claude-eval-substrate";`)).g2);
    expect(g2).toContain("portable cron-alpha reaches `spawnClaudeEval` (imported from server/inngest/functions/_cron-claude-eval-substrate.ts; not in PORTABLE_SAFE_SHARED_EXPORTS)");
    expect(g2).toContain(CLASS_RULE);
    expect(g2).toContain("never widen PORTABLE_SAFE_SHARED_EXPORTS");
  });

  it("a non-allowlisted definer export, imported directly or under an alias, is RED by its original name", () => {
    for (const head of [
      `import { postSentryHeartbeat, resolveCronWorkspaceRoot } from "./_cron-shared";`,
      `import { resolveCronWorkspaceRoot as r } from "./_cron-shared";`,
    ]) {
      expect(joined(runAll(alpha(head)).g2)).toContain(`\`resolveCronWorkspaceRoot\` (imported from ${DEF}; not in PORTABLE_SAFE_SHARED_EXPORTS)`);
    }
  });

  it.each([
    ["namespace import", `import * as shared from "./_cron-shared";`, `a namespace import of ${DEF}`],
    ["default import", `import shared from "./_cron-shared";`, `a default import of ${DEF}`],
    ["side-effect import", `import "./_cron-shared";`, `a side-effect import of ${DEF}`],
    ["export * from", `export * from "./_cron-shared";`, `\`export * from\` ${DEF}`],
    ["import = require()", `import shared = require("./_cron-shared");`, `\`import = require()\` of ${DEF}`],
    ["dynamic import()", `const load = () => import("./_cron-shared");`, `a dynamic import()/require() of ${DEF}`],
  ])("a %s of a definer is RED", (_l, head, want) => {
    expect(joined(runAll(alpha(head)).g2)).toContain(want);
  });

  it("a re-export of a non-allowlisted definer name is RED", () => {
    const r = runAll(
      withFiles({
        "server/inngest/functions/cron-alpha.ts": fnSrc("cronAlpha", "cron-alpha", `import { resolveCronWorkspaceRoot } from "@/server/reexp";`, "resolveCronWorkspaceRoot()"),
        "server/reexp.ts": `export { resolveCronWorkspaceRoot } from "./inngest/functions/_cron-shared";\n`,
      }),
    );
    expect(joined(r.g2)).toContain(`\`resolveCronWorkspaceRoot\` (re-exported from ${DEF}`);
  });

  it("own dispatch — a resolver that drops every edge trips the in-helper floor", () => {
    const g2 = joined(runAll(baseFiles(), BASE_MANIFEST, { walkOpts: { resolver: () => null } }).g2);
    expect(g2).toContain("portable cron-alpha: its closure is");
    expect(g2).toContain("no edge resolved into server/");
  });

  it("a closure module that exists but cannot be read fails closed", () => {
    const base = memFs(alpha(`import { ghost } from "@/server/ghost";`, "ghost()"));
    const ghost = join(FX_APP, "server/ghost.ts");
    const fs: GraphFs = { ...base, exists: (p) => p === ghost || base.exists(p) };
    const r = portableViolations({ served: servedFunctions(fs).served, manifest: BASE_MANIFEST, fs, allowlist: FX_ALLOW });
    expect(joined(r.offenders)).toContain("server/ghost.ts: unreadable module — the walk must be total (fail-closed)");
  });

  it("must-pass: a portable function whose client import is relative still satisfies the floor", () => {
    const { files, manifest } = withGamma(`import { inngest } from "../client";\nexport const cronGamma = inngest.createFunction({ id: "cron-gamma" }, { cron: "0 * * * *" }, async () => null);\n`);
    expect(runAll(files, manifest).g2).toEqual([]);
  });

  it("of two portable functions, the second reaching child_process two hops away is named", () => {
    const { files, manifest } = withGamma(fnSrc("cronGamma", "cron-gamma", `import { hop1 } from "@/server/hop1";`, "hop1()"));
    const r = runAll(
      { ...files, "server/hop1.ts": `import { hop2 } from "./hop2";\nexport const hop1 = () => hop2();\n`, "server/hop2.ts": `import { execFileSync } from "node:child_process";\nexport const hop2 = () => execFileSync("git");\n` },
      manifest,
    );
    expect(r.g2).toHaveLength(1);
    expect(r.g2[0]).toContain("portable cron-gamma reaches `node:child_process` via server/hop2.ts");
  });

  it("a host-local module reached through a `../` import inside a mixed type/value import is RED (the walk keeps both)", () => {
    const { files, manifest } = withGamma(fnSrc("cronGamma", "cron-gamma", `import { type T, hop } from "../../util/hop";\nexport type U = T;`, "hop()"));
    const r = runAll({ ...files, "server/util/hop.ts": `import { spawnSync } from "node:child_process";\nexport type T = number;\nexport const hop = () => spawnSync("x");\n` }, manifest);
    expect(joined(r.g2)).toContain("portable cron-gamma reaches `node:child_process` via server/util/hop.ts");
  });

  it("a default import carrying type-only names is not erased (TypeScript keeps it)", () => {
    const { files, manifest } = withGamma(fnSrc("cronGamma", "cron-gamma", `import hop, { type T } from "@/server/hop";\nexport type U = T;`, "hop()"));
    const r = runAll({ ...files, "server/hop.ts": `import { fork } from "node:child_process";\nexport type T = number;\nexport default () => fork("x");\n` }, manifest);
    expect(joined(r.g2)).toContain("portable cron-gamma reaches `node:child_process` via server/hop.ts");
  });

  it.each([
    ["a dynamic import of child_process", `export async function later() {\n  return import("node:child_process");\n}\n`, "reaches `node:child_process` via server/later.ts"],
    ["worker_threads", `import { Worker } from "node:worker_threads";\nexport const later = () => new Worker("x");\n`, "reaches `node:worker_threads` via server/later.ts"],
    ["a host-local package", `import { execa } from "execa";\nexport const later = () => execa("git");\n`, "reaches `execa` via server/later.ts"],
    ["an opaque module loader", `import { createRequire } from "node:module";\nexport const later = () => createRequire("/x")("child" + "_process");\n`, "the opaque module loader `createRequire` via server/later.ts"],
    ["a /workspaces literal", `export const later = () => "/workspaces/abc";\n`, `the volume path literal "/workspaces/abc" via server/later.ts`],
    ["a /mnt/data template head", "export const later = (id: string) => `/mnt/data/${id}`;\n", `the volume path literal "/mnt/data/" via server/later.ts`],
    ["process.env.WORKSPACES_ROOT", `export const later = () => process.env.WORKSPACES_ROOT;\n`, "process.env .WORKSPACES_ROOT via server/later.ts"],
    ["process.env[\"CRON_WORKSPACE_ROOT\"]", `export const later = () => process.env["CRON_WORKSPACE_ROOT"];\n`, "process.env .CRON_WORKSPACE_ROOT via server/later.ts"],
    ["a destructured env read", `export const later = () => {\n  const { WORKSPACES_ROOT } = process.env;\n  return WORKSPACES_ROOT;\n};\n`, "process.env .WORKSPACES_ROOT via server/later.ts"],
    ["an env alias", `const e = process.env;\nexport const later = () => e.WORKSPACES_ROOT;\n`, "process.env .WORKSPACES_ROOT via server/later.ts"],
    ["an env default parameter", `export const later = (env = process.env) => env.CRON_WORKSPACE_ROOT;\n`, "process.env .CRON_WORKSPACE_ROOT via server/later.ts"],
    ["an env imported from node:process", `import { env } from "node:process";\nexport const later = () => env.WORKSPACES_ROOT;\n`, "process.env .WORKSPACES_ROOT via server/later.ts"],
    ["a globalThis.process.env read", `export const later = () => globalThis.process.env.WORKSPACES_ROOT;\n`, "process.env .WORKSPACES_ROOT via server/later.ts"],
  ])("a closure module with %s is RED", (_l, laterSrc, want) => {
    const r = runAll(withFiles({ "server/inngest/functions/cron-alpha.ts": fnSrc("cronAlpha", "cron-alpha", `import { later } from "@/server/later";`, "later()"), "server/later.ts": laterSrc }));
    expect(joined(r.g2)).toContain(want);
  });

  it("an allowlisted export that calls a helper importing child_process is RED (the walk descends through the definer)", () => {
    const shared = mustReplace(FX_SHARED, "function heartbeatUrl(slug: string): string {", `import { runGit } from "@/server/git-helper";\nfunction heartbeatUrl(slug: string): string {\n  runGit();`);
    const r = runAll(withFiles({ [DEF]: shared, "server/git-helper.ts": `import { execFileSync } from "node:child_process";\nexport const runGit = () => execFileSync("git");\n` }));
    expect(joined(r.g2)).toContain("portable cron-alpha reaches `node:child_process` via server/git-helper.ts");
  });

  it.each([
    [
      "calls a same-file helper calling a non-allowlisted export",
      (s: string) => mustReplace(s, "return heartbeatUrl(slug);", "return viaRoot(slug);") + `function viaRoot(slug: string): string {\n  return resolveCronWorkspaceRoot() + slug;\n}\n`,
      "the non-allowlisted export `resolveCronWorkspaceRoot`",
    ],
    ["dynamically imports child_process", (s: string) => mustReplace(s, "return heartbeatUrl(slug);", `await import("node:child_process");\n  return heartbeatUrl(slug);`), "it loads node:child_process"],
    [
      "uses a top-level `require()` binding",
      (s: string) => `const cp = require("child_process");\n` + mustReplace(s, "return heartbeatUrl(slug);", "cp.execSync(slug);\n  return heartbeatUrl(slug);"),
      "it loads child_process",
    ],
    [
      "uses an `import = require()` binding",
      (s: string) => `import cp = require("node:child_process");\n` + mustReplace(s, "return heartbeatUrl(slug);", "cp.execSync(slug);\n  return heartbeatUrl(slug);"),
      "it reaches `cp` from node:child_process",
    ],
    ["reads an env alias", (s: string) => mustReplace(s, "return heartbeatUrl(slug);", "const e = process.env;\n  return heartbeatUrl(e.WORKSPACES_ROOT ?? slug);"), "it reaches a process.env read (WORKSPACES_ROOT)"],
  ])("an allowlisted export that %s is RED (chokepoint iii)", (_l, edit, want) => {
    const g2 = joined(runAll(withFiles({ [DEF]: edit(FX_SHARED) })).g2);
    expect(g2).toContain("`postSentryHeartbeat` is in PORTABLE_SAFE_SHARED_EXPORTS but is no longer host-free");
    expect(g2).toContain(want);
  });

  it("an allowlisted name exported under an alias is scanned through its local declaration", () => {
    const aliased =
      mustReplace(FX_SHARED, "export async function postSentryHeartbeat(slug: string): Promise<string> {\n  return heartbeatUrl(slug);", "async function beatImpl(slug: string): Promise<string> {\n  return resolveCronWorkspaceRoot() + heartbeatUrl(slug);") +
      "export { beatImpl as postSentryHeartbeat };\n";
    expect(joined(runAll(withFiles({ [DEF]: aliased })).g2)).toContain("the non-allowlisted export `resolveCronWorkspaceRoot`");
  });

  it("an allowlisted name whose declaration cannot be located fails closed", () => {
    const orphan = mustReplace(FX_SHARED, "export async function postSentryHeartbeat", "async function beatImpl") + "export { ghost as postSentryHeartbeat };\n";
    expect(joined(runAll(withFiles({ [DEF]: orphan })).g2)).toContain("cannot locate the declaration of allowlisted `postSentryHeartbeat`");
  });

  it("a stale allowlist entry is RED", () => {
    const fs = memFs(baseFiles());
    const r = portableViolations({ served: servedFunctions(fs).served, manifest: BASE_MANIFEST, fs, allowlist: new Set([...FX_ALLOW, "noSuchExport"]) });
    expect(joined(r.offenders)).toContain("PORTABLE_SAFE_SHARED_EXPORTS names `noSuchExport`, which no definer module exports");
  });

  it("a manifest with zero portable rows trips the checked-count assertion", () => {
    const manifest: Manifest = { ...BASE_MANIFEST, "cron-alpha": { placement: "host-affine", reason: "x" } };
    const r = runAll(baseFiles(), manifest);
    expect(r.g2result.checkedCount).toBe(0);
    expect(checkedCountViolation(r.g2result, manifest)).toContain("it must check every one, and at least one");
    expect(checkedCountViolation(runAll(baseFiles()).g2result, BASE_MANIFEST)).toBeNull();
  });

  it("must-pass: aliased allowlisted names plus type-only specifiers of both definers", () => {
    const r = runAll(
      alpha(
        `import { postSentryHeartbeat as beat, REPO_OWNER, type HandlerArgs } from "./_cron-shared";\nimport { type SpawnResult } from "./_cron-claude-eval-substrate";\nexport type Both = HandlerArgs | SpawnResult;`,
        "beat(REPO_OWNER)",
      ),
    );
    expect(r.g2).toEqual([]);
  });

  it("must-pass: a host-affine function importing spawnClaudeEval is not guarded (over-pinning is safe)", () => {
    const files = baseFiles();
    expect(files["server/inngest/functions/cron-beta.ts"]).toContain(`import { spawnClaudeEval } from "./_cron-claude-eval-substrate";`);
    expect(runAll(files).g2).toEqual([]);
  });
});

describe("Guard 3 — anti-circularity", () => {
  const LUKS_DISPATCH = `const WORKFLOW_FILE = "workspaces-luks-verify.yml";\nexport const wf = WORKFLOW_FILE;`;

  it("a served dispatcher naming workspaces-luks-verify.yml is RED, with the #6808 pointer", () => {
    const g3 = joined(runAll(withFiles({ "server/inngest/functions/cron-alpha.ts": fnSrc("cronAlpha", "cron-alpha", LUKS_DISPATCH) })).g3);
    expect(g3).toContain(`names the forbidden workflow "workspaces-luks-verify" (HOST_STATE_VERIFIER_WORKFLOWS)`);
    expect(g3).toContain("#6808");
  });

  it("a helper outside server/inngest/ reached from a served cron is covered by the closure walk", () => {
    const r = runAll(
      withFiles({
        "server/inngest/functions/cron-alpha.ts": fnSrc("cronAlpha", "cron-alpha", `import { dispatch } from "@/server/github/dispatch-luks";`, "dispatch()"),
        "server/github/dispatch-luks.ts": `export const dispatch = () => "workspaces-luks-verify";\n`,
      }),
    );
    expect(joined(r.g3)).toContain(`server/github/dispatch-luks.ts names the forbidden workflow "workspaces-luks-verify"`);
  });

  it("own dispatch — an empty forbidden set is RED, and the positive fixture fires under the real set", () => {
    const fs = memFs(withFiles({ "server/inngest/functions/cron-alpha.ts": fnSrc("cronAlpha", "cron-alpha", LUKS_DISPATCH) }));
    const { served } = servedFunctions(fs);
    expect(joined(circularityViolations({ served, fs, forbidden: forbiddenWorkflows([], []), exemptions: {} }).offenders)).toContain("the forbidden verifier set is empty");
    expect(joined(circularityViolations({ served, fs, forbidden: FX_FORBIDDEN, exemptions: {} }).offenders)).toContain(`names the forbidden workflow "workspaces-luks-verify"`);
  });

  it("a second watchdog-table row is forbidden because the set is derived from the table", () => {
    const fs = memFs(withFiles({ "server/inngest/functions/cron-alpha.ts": fnSrc("cronAlpha", "cron-alpha", `export const wf = "x-verify.yml";`), "/fx/.github/workflows/x-verify.yml": "on: {}\n" }));
    const forbidden = forbiddenWorkflows([{ workflowFile: "scheduled-inngest-health.yml" }, { workflowFile: "x-verify.yml" }], ["workspaces-luks-verify.yml"]);
    expect(joined(circularityViolations({ served: servedFunctions(fs).served, fs, forbidden, exemptions: {} }).offenders)).toContain(`"x-verify" (WATCHDOG_DISPATCH_TABLE)`);
  });

  it("a verifier naming a workflow absent from .github/workflows/ is RED (stale)", () => {
    const fs = memFs(baseFiles());
    const forbidden = forbiddenWorkflows([{ workflowFile: "scheduled-inngest-health.yml" }], ["workspaces-luks-verify.yml", "gone-verify.yml"]);
    expect(joined(circularityViolations({ served: servedFunctions(fs).served, fs, forbidden, exemptions: {} }).offenders)).toContain("forbidden workflow gone-verify.yml (HOST_STATE_VERIFIER_WORKFLOWS) does not exist");
  });

  describe("the dynamic-import exemption is exact", () => {
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
    it("a third botFixturePath import is RED", () => {
      const ux = mustReplace(uxBody("botFixturePath", "botFixturePath", "botSigninPath"), "\n}\n", "\n  await import(botFixturePath);\n}\n");
      expect(joined(g3(files(ux)))).toContain("server/inngest/functions/cron-ux.ts: non-literal import()/require() (botFixturePath×3, botSigninPath×1)");
    });
    it("swapping botSigninPath for x (same total) is RED", () => {
      expect(joined(g3(files(uxBody("botFixturePath", "botFixturePath", "x"))))).toContain("(botFixturePath×2, x×1)");
    });
    it("a non-literal import in another file is RED", () => {
      const ux = mustReplace(uxBody("botFixturePath", "botFixturePath", "botSigninPath"), "export async function ux", `import { other } from "@/server/other";\nexport async function ux`);
      expect(joined(g3(files(ux, { "server/other.ts": `const x = "./y";\nexport const other = () => import(x);\n` })))).toContain("server/other.ts: non-literal import()/require() (x×1)");
    });
    it("an exemption that matches no import is RED (stale)", () => {
      expect(joined(g3(baseFiles()))).toContain("the dynamic-import exemption for server/inngest/functions/cron-ux.ts (botFixturePath×2, botSigninPath×1) matches no non-literal import");
    });
  });

  it.each([
    ["an .mjs", "server/inngest/hook.mjs"],
    ["a .cjs", "server/inngest/hook.cjs"],
    ["a .js", "server/inngest/hook.js"],
    ["a .tsx", "server/inngest/hook.tsx"],
  ])("%s module under server/inngest/ naming a forbidden stem is RED", (_l, path) => {
    expect(joined(runAll(withFiles({ [path]: `export const target = "scheduled-inngest-health";\n` })).g3)).toContain(`${path} names the forbidden workflow "scheduled-inngest-health"`);
  });

  it("must-pass: comments mentioning a forbidden stem do not count", () => {
    const r = runAll(withFiles({ "server/inngest/functions/cron-alpha.ts": fnSrc("cronAlpha", "cron-alpha", `// dispatches nothing like workspaces-luks-verify\n/** not workspaces-luks-verify.yml either */`) }));
    expect(r.g3).toEqual([]);
  });

  it("must-pass: a *.test.ts under server/inngest/ is listed but filtered", () => {
    const files = withFiles({ "server/inngest/functions/cron-alpha.test.ts": `export const wf = "scheduled-inngest-health.yml";\n` });
    expect(memFs(files).listFiles(join(FX_APP, "server/inngest"))).toContain(join(FX_APP, "server/inngest/functions/cron-alpha.test.ts"));
    expect(runAll(files).g3).toEqual([]);
  });
});

describe("Guard 4 — single step-executing host (serve-URL anchor)", () => {
  const route = (o: Partial<Parameters<typeof routeSrc>[0]>) => withFiles({ [ROUTE_PATH]: routeSrc({ ...BASE_ROUTE, ...o }) });

  it("a moved production literal is RED even while a trailing comment still names app.soleur.ai", () => {
    const files = route({ prodBranch: `"https://worker.soleur.ai"`, postamble: `// the old origin was "${PROD_SERVE_URL}"\n` });
    expect(files[ROUTE_PATH]).toContain(`// the old origin was "${PROD_SERVE_URL}"`);
    expect(joined(runAll(files).g4)).toContain(`${SERVE_HOST_RULE}, found \`"https://worker.soleur.ai"\``);
  });

  it("a SERVE_HOST gated on another NODE_ENV value is RED", () => {
    const files = route({ serveHostDecl: `const SERVE_HOST = process.env.NODE_ENV === "development" ? "${PROD_SERVE_URL}" : undefined;` });
    expect(joined(runAll(files).g4)).toContain("SERVE_HOST is not `process.env.NODE_ENV === \"production\" ? ... : ...`");
  });

  it("own dispatch — an indirected or missing SERVE_HOST fails closed", () => {
    const indirect = route({ serveHostDecl: `const SERVE_ORIGIN = process.env.NODE_ENV === "production" ? "${PROD_SERVE_URL}" : undefined;\nconst SERVE_HOST = SERVE_ORIGIN;` });
    expect(joined(runAll(indirect).g4)).toContain("SERVE_HOST is not `process.env.NODE_ENV === \"production\" ? ... : ...`");
    const gone = withFiles({ [ROUTE_PATH]: routeSrc(BASE_ROUTE).replaceAll("SERVE_HOST", "SERVE_ORIGIN") });
    expect(joined(runAll(gone).g4)).toContain("`const SERVE_HOST` not found");
  });

  it("serveHost not referencing SERVE_HOST is RED", () => {
    expect(joined(runAll(route({ serveHostProp: "process.env.X" })).g4)).toContain("serve()'s serveHost is `serveHost: process.env.X`");
  });

  it.each([
    ["serve (aliased) from another adapter", "app/api/inngest-infra/route.ts", `import { serve as s } from "inngest/express";\nexport const h = s;\n`],
    ["serve from a two-segment adapter path", "app/api/inngest-fresh/route.ts", `import { serve } from "inngest/deno/fresh";\nexport const h = serve;\n`],
    ["connect (worker mode)", "server/inngest/worker.ts", `import { connect } from "inngest/connect";\nexport const w = connect;\n`],
    ["createServer", "server/inngest/node-server.ts", `import { createServer } from "inngest/node";\nexport const s = createServer;\n`],
    ["InngestCommHandler from the root package", "lib/comm.ts", `import { InngestCommHandler } from "inngest";\nexport const C = InngestCommHandler;\n`],
    ["a namespace import of an adapter", "lib/other-serve.ts", `import * as i from "inngest/next";\nexport const h = i.serve;\n`],
    ["a default import of an adapter", "lib/other-serve.ts", `import adapter from "inngest/next";\nexport const h = adapter;\n`],
    ["a re-export of serve", "lib/barrel.ts", `export { serve } from "inngest/next";\n`],
    ["a require() of an adapter", "lib/other-serve.ts", `const { serve } = require("inngest/next");\nexport const h = serve;\n`],
    ["a .js route file", "app/api/inngest-b/route.js", `import { serve } from "inngest/next";\nexport const h = serve;\n`],
    ["a root middleware.ts", "middleware.ts", `import { serve } from "inngest/next";\nexport const h = serve;\n`],
  ])("a second executor — %s — is RED", (_l, path, src) => {
    const g4 = joined(runAll(withFiles({ [path]: src })).g4);
    expect(g4).toContain("modules reaching an Inngest step-executor API");
    expect(g4).toContain(path);
  });

  it("must-pass: a parenthesized conditional still anchors the literal", () => {
    expect(runAll(route({ serveHostDecl: `const SERVE_HOST = (process.env.NODE_ENV === "production" ? ("${PROD_SERVE_URL}") : undefined);` })).g4).toEqual([]);
  });

  it("must-pass: type-only imports, a plain client import, and a comment containing `serve(` do not count", () => {
    const r = runAll(
      withFiles({
        "lib/types.ts": `import type { serve } from "inngest/next";\nimport { type connect } from "inngest/connect";\nimport { Inngest } from "inngest";\n// call serve( here someday\nexport type S = typeof serve | typeof connect;\nexport const I = Inngest;\n`,
      }),
    );
    expect(r.g4).toEqual([]);
  });
});
