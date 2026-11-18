// AST census of two token-bearing git SPELLINGS in apps/web-platform/server/** (`.ts`, `.tsx`, `.mts`, `.mjs`), plus the
// import boundaries of the KB sync pull (#12600, CTO rulings D12(1), D19, D25; #12704 D45(d)). What it assembles, and only
// that (it is not the whole token-bearing git surface):
//
//   1. Every `gitWithInstallationAuth` reference is an import, a call or its definition (an alias is followed; a value use,
//      namespace member, re-export or dynamic import is red). Every call is recorded as (file, first verb or `dynamic`,
//      arm = `hardened` when the options object carries `hardened:` with a value that is not `undefined`, `void 0` or
//      `null`; such a value is `legacy-suspect`, which no table row may hold (D19(1); git-auth.ts also throws on a present
//      undefined key at runtime); else `legacy`) and the multiset must equal GIT_AUTH_SITES below.
//   2. Every string / no-substitution template literal (and template head) equal to `push`, `send-pack` or `receive-pack`
//      is recorded with its syntactic context (an argv array and the call or variable it feeds, a call argument, a
//      property, a variable, a comparison) and the multiset must equal PUSH_TOKEN_SITES. A token in a git argv position
//      (`argv@...` or `var:...`) may sit only in kb-sync-publish.ts (the ONE KB sync push) and push-branch.ts (the
//      approved cc push), plus the named non-workspace pushes and classifier word lists below.
//   3. No non-test file OUTSIDE server/ can reach `gitWithInstallationAuth`: none names it, and every edge into server/git-auth
//      is a plain named import of another export (no namespace import, re-export, dynamic import or require), pinned in
//      OUTSIDE_SERVER_GIT_AUTH_EDGES (D19(2)).
//   4. D25(3), D45(d): no PUSH_FREE_MODULES file reaches kb-sync-publish.ts or push-branch.ts through its RUNTIME import
//      graph, transitively: static imports, re-exports, dynamic `import()` and `require()` are followed through every app
//      module; a type-only import or re-export is erased by the compiler and is not an edge; a computed specifier, an
//      unresolvable app path or a listed file that does not exist is red.
//   5. D25(5), D45(d): the token-free KB sync modules spawn no git of their own (no child_process, no `X("git")`), call the
//      isolated runner a known number of times, and import a CLOSED set of runtime bindings (TOKEN_FREE_IMPORTS), so a new
//      git-capable wrapper (`runGit`, a key-auth helper, a future one) is a reviewed row, not a silent bypass.
//
// PUSH_TOKEN_SITES churns with HUMAN-TEXT `push` tokens too (an op slug, a message, a word list): a new row there is reviewed
// like any other, it is not proof of a new git push. The known-positive plants its shapes through an in-memory override of
// one file, so only that file is re-parsed (D19(3)).
//
// Out of the census by design: REST writes (the Contents API) are user-initiated KB UI writes, not git pushes. A
// computed name (`"pu" + "sh"`, `R["gitWith" + "InstallationAuth"]`) is invisible to a static scan (named residual). NOT
// assembled here (FU-5, D45(d)): the agent sandbox's installation-token env against the workspace (by design, E1), the
// key-auth wrapper, token-in-URL cron clones, a token env built through `buildIsolatedGitEnv` or `hostGitInvocation`
// extraEnv, and code outside server/. test/host-git-consumers-real-git.test.ts classifies host-side git exec sites.
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import ts from "typescript";
import { describe, expect, test } from "vitest";
import { callSites, censusSource, parseSource, resolveSpecifier } from "./approval/source-scan";

const APP = join(__dirname, "..");
const IDENT = "gitWithInstallationAuth";
const VERBS = new Set(["push", "send-pack", "receive-pack"]);

/** (file verb arm) for every call. Update ONLY with a reviewed reason: each row is a token-bearing git child. */
const GIT_AUTH_SITES = [
  "server/ensure-workspace-repo.ts clone legacy",
  "server/kb-sync-publish.ts push hardened",
  // #12718 (D25(1), D25(5)): the session-start pull's reads, both from the isolated directory against the literal URL
  "server/kb-sync-remote.ts fetch hardened",
  "server/kb-sync-remote.ts ls-remote hardened",
  "server/push-branch.ts push conditional", // hardened when the isolated dir was created, else the legacy cwd arm
  "server/workspace-sync.ts fetch opts-dynamic", // an options variable built from the injected runner's caller
  "server/workspace-sync.ts pull legacy",
  "server/workspace.ts clone legacy",
];

/**
 * References that are neither an import nor a call, with the reason. workspace-sync.ts loads the function by a dynamic
 * import (destructured) and injects it into its helpers as a parameter of the same name, whose calls are counted above.
 */
const STRAY_ALLOWED = [
  "server/workspace-sync.ts edge:dynamic-import",
  "server/workspace-sync.ts other",
  "server/workspace-sync.ts other",
  "server/workspace-sync.ts other",
];

/** #12718 (D25(5)): KB sync modules with ZERO token-bearing calls and no git exec of their own (the isolated runner only). */
const KB_SYNC_TOKEN_FREE = ["server/kb-sync-objects.ts", "server/kb-sync-pull.ts", "server/kb-sync-side-pr.ts", "server/kb-sync-held.ts"];

/** The known `runIsolatedGitLocal` call sites per token-free KB sync file (a new token-free child is a reviewed row). */
const ISOLATED_RUNNER_SITES: Record<string, number> = {
  "server/kb-sync-objects.ts": 7, // isCommitPresent, isAncestor, commitTree, handOver, isKbOnlySide (merge-base, diff), mergeEffectIsKbOnly (D34)
  "server/kb-sync-pull.ts": 5, // the walk, the size check, merge-tree, the first-parent chain and its KB batch read
  "server/kb-sync-side-pr.ts": 0,
  "server/kb-sync-held.ts": 1, // the held count's diff (#12714)
};

/**
 * D45(d), tests F7: every RUNTIME binding each token-free module imports, as `<specifier> <name>` (`(dynamic)` for an
 * `import()`, with its destructured names). The closed set of what the module can call: a new import of any git-capable
 * helper is a reviewed row here, whatever it is named. Type-only imports are erased and not listed.
 */
const TOKEN_FREE_IMPORTS: Record<string, string[]> = {
  "server/kb-sync-objects.ts": [
    "./agent-git-identity AGENT_AUTHOR_EMAIL",
    "./agent-git-identity AGENT_AUTHOR_NAME",
    "./approval/workspace-head HEX40",
    "./git-isolated-local runIsolatedGitLocal",
    "./git-isolated-local verifyObject",
    "./kb-root KB_ROOT",
  ],
  "server/kb-sync-pull.ts": [
    "./approval/workspace-head HEX40",
    "./error-frame firstAppFrame",
    "./git-isolated-local ISOLATED_LOCAL_TIMEOUT_MS",
    "./git-isolated-local runIsolatedGitLocal",
    "./kb-root KB_ROOT",
    "./kb-sync-objects commitTree",
    "./kb-sync-objects handOver",
    "./kb-sync-objects isAncestor",
    "./kb-sync-objects isCommitPresent",
    "./kb-sync-objects isKbOnlySide",
    "./kb-sync-objects kbOf",
    "./kb-sync-objects mergeEffectIsKbOnly",
    "./kb-sync-objects readVerified",
    "./kb-sync-objects sameKb",
    "./kb-sync-remote KB_SYNC_SIDE_BRANCH",
    "./kb-sync-remote KbRemoteError",
    "./kb-sync-remote cappedTimeout",
    "./kb-sync-remote fetchIntoIsolated", // the hardened token-bearing fetch lives (and is counted) in kb-sync-remote.ts
    "./kb-sync-remote readRemoteState", // likewise the hardened ls-remote
    "./kb-sync-side-pr createKbSyncPr",
    "./kb-sync-side-pr readSidePrState",
  ],
  "server/kb-sync-side-pr.ts": [
    "./github-app createPullRequest (dynamic)", // REST, not git
    "./github-app createPullRequest (dynamic)",
    "./github-app findOpenPullRequest (dynamic)",
    "./github-app listPullRequestsForHead (dynamic)",
    "./kb-sync-remote KB_SYNC_SIDE_BRANCH",
  ],
  "server/kb-sync-held.ts": [
    "./approval/workspace-head HEX40",
    "./approval/workspace-head SmallFileError",
    "./approval/workspace-head readSmallRegularFile",
    "./git-isolated-local runIsolatedGitLocal",
    "./kb-root KB_ROOT",
    "./logger createChildLogger",
    "@/lib/kb-sync-held-copy HELD_FILES_RENDER_MAX",
    "node:fs lstatSync",
    "node:fs readdirSync",
    "node:fs realpathSync",
    "node:path join",
  ],
};

/**
 * #12718 (D25(3)), #12704 (D45(d)): modules on the pull's and the self-heal's runtime import graph that must never reach
 * the push, checked transitively (a module they load that loads the push is red).
 */
const PUSH_FREE_MODULES = [
  "server/kb-sync-objects.ts",
  "server/kb-sync-pull.ts",
  "server/kb-sync-remote.ts",
  "server/kb-sync-side-pr.ts",
  "server/workspace-sync.ts", // the self-heal (KB routes, c4-writer, cron, webhook reconcile)
  "server/git-isolated-dispose.ts",
  "server/agent-git-identity.ts",
  // Review Phase 0: the leaves the pull and the self-heal reach (the collision precheck, the held-count path; the held
  // count is also loaded by cc-dispatcher.ts's dynamic import for the D39(a) close refresh).
  "server/workspace-collision.ts",
  "server/kb-sync-held-refresh.ts",
  // D45(d): the connected-repo writer the self-heal and the pull load. Its `import type { KbWorkspaceWriter }` from
  // kb-sync-publish.ts is a type-only edge, erased, so it is not a push edge (pinned in the known-positive below).
  "server/connected-repo-git.ts",
];

/** The push modules no PUSH_FREE_MODULES file may reach at runtime. */
const PUSH_MODULES = new Set(["server/kb-sync-publish.ts", "server/push-branch.ts"]);

/** Files whose push-verb tokens in an argv position are allowed, with the reason. */
const ARGV_ALLOWED: Record<string, string> = {
  "server/kb-sync-publish.ts": "the ONE post-session KB sync push (Guard 1 token, hardened arm)",
  "server/push-branch.ts": "the Owner-approved cc push (hardened arm)",
  "server/git-data-replication.ts": "key-auth mirror push to the git-data remote; no installation token, not the user's repo",
  "server/inngest/functions/_cron-safe-commit.ts": "cron worker push from its own scratch clone, not a workspace",
  "server/destroy-ask-classifier.ts": "a classifier reading the agent's argv (word lists), never a git invocation",
  "server/permission-callback-bash-batch.ts": "a deny-list of git verbs for the Bash batch gate, never a git invocation",
};

/** (file verb context) for every push-verb token. */
const PUSH_TOKEN_SITES = [
  "server/approval/render.ts push ReturnStatement", // the approval card's human text (`push commit <sha> to branch ...`)
  "server/destroy-ask-classifier.ts push arg:includes",
  "server/destroy-ask-classifier.ts push arg:indexOf",
  "server/destroy-ask-classifier.ts receive-pack argv@var:GIT_PUSH_LONG",
  "server/destroy-ask-classifier.ts receive-pack argv@var:GIT_PUSH_VALUE_LONG",
  "server/git-data-replication.ts push argv@var:pushArgs",
  "server/git-data-replication.ts push argv@var:rescuePushArgs",
  "server/inngest/cron-bash-allowlist-hook.mjs push cmp", // a Bash allowlist hook comparing the agent's git subcommand
  "server/inngest/functions/_cron-safe-commit.ts push arg:failure",
  "server/inngest/functions/_cron-safe-commit.ts push argv@call:git",
  "server/inngest/functions/workspace-reconcile-on-push.ts push prop:op",
  "server/kb-sync-publish.ts push argv@call:gitWithInstallationAuth",
  "server/permission-callback-bash-batch.ts push argv@var:NO_BATCH_GIT_VERBS",
  "server/push-branch.ts push argv@call:gitWithInstallationAuth",
  "server/session-sync.ts push arg:autoCommit", // the auto-commit stage name (human text; #12718 D26(1) shared helper)
];

/** Edges into server/git-auth from non-test files outside server/: (file role). Each is a named import of another export. */
const OUTSIDE_SERVER_GIT_AUTH_EDGES = [
  "app/api/repo/setup/route.ts import", // GitOperationError, sanitizeGitStderr
  "app/api/repo/status/route.ts import", // parseErrorPayload
  "components/connect-repo/failed-state.tsx type-import", // GitErrorCode
];

const SOURCE_RE = /\.(tsx?|mts|mjs)$/;
const SKIP_DIRS = new Set(["node_modules", ".next", "test", "tests", "e2e", "__tests__", "coverage", "dist", "public", ".git"]);
const walk = (dir: string, skip: ReadonlySet<string> = new Set()): string[] =>
  readdirSync(dir).flatMap((f) => {
    const p = join(dir, f);
    if (statSync(p).isDirectory()) return skip.has(f) ? [] : walk(p, skip);
    return SOURCE_RE.test(f) && !f.endsWith(".d.ts") && !/\.(test|spec)\.[cm]?[jt]sx?$/.test(f) ? [p] : [];
  });

const calleeName = (e: ts.Expression): string =>
  ts.isIdentifier(e) ? e.text : ts.isPropertyAccessExpression(e) ? e.name.text : ts.SyntaxKind[e.kind];
const literalText = (n: ts.Node): string | null =>
  ts.isStringLiteral(n) || ts.isNoSubstitutionTemplateLiteral(n) ? n.text : ts.isTemplateExpression(n) ? n.head.text.trim() : null;

/** The first git verb of an argv array literal: `-c <k=v>` pairs and `-` options skipped; a spread or variable first is `dynamic`. */
function firstVerb(arg: ts.Expression | undefined): string {
  if (!arg || !ts.isArrayLiteralExpression(arg)) return "dynamic";
  const els = arg.elements;
  for (let i = 0; i < els.length; i++) {
    const t = literalText(els[i]);
    if (t === null) return "dynamic";
    if (t === "-c") {
      i++;
      continue;
    }
    if (t.startsWith("-")) continue;
    return t;
  }
  return "dynamic";
}

/** The syntactic context of a push-verb token. */
function contextOf(node: ts.Node): string | null {
  let p = node.parent;
  if (ts.isLiteralTypeNode(p)) return null; // a type, not a value
  if (ts.isTemplateSpan(p) || ts.isTemplateExpression(p)) p = p.parent;
  if (ts.isSpreadElement(p)) p = p.parent;
  if (ts.isArrayLiteralExpression(p)) {
    let q: ts.Node = p;
    while (q.parent && (ts.isArrayLiteralExpression(q.parent) || ts.isSpreadElement(q.parent) || ts.isParenthesizedExpression(q.parent) || ts.isAsExpression(q.parent))) q = q.parent;
    const holder = q.parent;
    if (holder && ts.isCallExpression(holder)) return `argv@call:${calleeName(holder.expression)}`;
    if (holder && ts.isNewExpression(holder) && holder.parent && ts.isVariableDeclaration(holder.parent)) return `argv@var:${holder.parent.name.getText()}`;
    if (holder && ts.isVariableDeclaration(holder)) return `argv@var:${holder.name.getText()}`;
    if (holder && ts.isPropertyAssignment(holder)) return `argv@prop:${holder.name.getText()}`;
    return `argv@${holder ? ts.SyntaxKind[holder.kind] : "?"}`;
  }
  if (ts.isCallExpression(p)) return `arg:${calleeName(p.expression)}`;
  if (ts.isPropertyAssignment(p)) return `prop:${p.name.getText()}`;
  if (ts.isVariableDeclaration(p)) return `var:${p.name.getText()}`;
  if (ts.isBinaryExpression(p)) return "cmp";
  if (ts.isCaseClause(p)) return "case";
  return ts.SyntaxKind[p.kind];
}

/** `undefined`, `void <x>` or `null`, through parentheses, `as`, `satisfies` and `!`: a `hardened:` value that hardens nothing. */
function nullish(e: ts.Expression): boolean {
  let x: ts.Expression = e;
  while (ts.isParenthesizedExpression(x) || ts.isAsExpression(x) || ts.isSatisfiesExpression(x) || ts.isNonNullExpression(x)) x = x.expression;
  return (ts.isIdentifier(x) && x.text === "undefined") || ts.isVoidExpression(x) || x.kind === ts.SyntaxKind.NullKeyword;
}

interface Census {
  gitAuth: string[];
  pushTokens: string[];
  /** references of the identifier that are not an import, a call or the definition */
  strayRefs: string[];
}

/** The census of ONE server file. */
function censusFile(file: string, src: string): Census {
  const out: Census = { gitAuth: [], pushTokens: [], strayRefs: [] };
  {
    for (const h of censusSource(src, file, IDENT, ["server/git-auth"])) {
      if (h.kind === "edge" && h.role !== "import" && h.role !== "type-import") out.strayRefs.push(`${file} edge:${h.role}`);
      if (h.kind === "id" && !["import", "call", "definition"].includes(h.role)) out.strayRefs.push(`${file} ${h.role}`);
      if (h.kind === "id" && h.role === "definition" && file !== "server/git-auth.ts") out.strayRefs.push(`${file} definition`);
    }
    const sf = parseSource(src, file);
    // aliases of the identifier imported from git-auth (an `as` import is followed)
    const aliases = new Set<string>([IDENT]);
    sf.forEachChild((n) => {
      if (ts.isImportDeclaration(n) && n.importClause?.namedBindings && ts.isNamedImports(n.importClause.namedBindings)) {
        for (const el of n.importClause.namedBindings.elements) if ((el.propertyName ?? el.name).text === IDENT) aliases.add(el.name.text);
      }
    });
    let calls = 0;
    const visit = (n: ts.Node): void => {
      if (ts.isCallExpression(n) && ts.isIdentifier(n.expression) && aliases.has(n.expression.text)) {
        calls++;
        const opts = n.arguments[2];
        const named = (p: ts.ObjectLiteralElementLike) => (ts.isPropertyAssignment(p) || ts.isShorthandPropertyAssignment(p)) && p.name.getText(sf) === "hardened";
        const prop = opts && ts.isObjectLiteralExpression(opts) ? opts.properties.find(named) : undefined;
        const arm = !opts
          ? "legacy"
          : !ts.isObjectLiteralExpression(opts)
            ? "opts-dynamic"
            : prop
              ? ts.isPropertyAssignment(prop) && nullish(prop.initializer)
                ? "legacy-suspect"
                : "hardened"
              : opts.properties.some((p) => ts.isSpreadAssignment(p) && /\bhardened\s*:/.test(p.expression.getText(sf)))
                ? "conditional"
                : "legacy";
        out.gitAuth.push(`${file} ${firstVerb(n.arguments[0])} ${arm}`);
      }
      const t = literalText(n);
      if (t !== null && (VERBS.has(t) || [...VERBS].some((v) => ts.isTemplateExpression(n) && t.startsWith(`${v} `)))) {
        const ctx = contextOf(n);
        if (ctx !== null) out.pushTokens.push(`${file} ${t.split(" ")[0]} ${ctx}`);
      }
      ts.forEachChild(n, visit);
    };
    visit(sf);
    // cross-check with the shared call-site scanner (no alias in that file: the two counts agree)
    if (aliases.size === 1 && file !== "server/git-auth.ts") {
      const shared = callSites(src, file, IDENT).filter((c) => !src.slice(c.pos).startsWith(`.${IDENT}`)).length;
      if (shared !== calls) out.strayRefs.push(`${file} callSites=${shared} ast=${calls}`);
    }
  }
  return out;
}

/** Every server file's census, parsed once from disk; the known-positive re-parses only the file it overrides. */
const SERVER_FILES = walk(join(APP, "server")).map((abs) => relative(APP, abs));
const BASE = new Map(SERVER_FILES.map((f) => [f, censusFile(f, readFileSync(join(APP, f), "utf8"))] as const));

function census(overrides: ReadonlyMap<string, string> = new Map()): Census {
  const out: Census = { gitAuth: [], pushTokens: [], strayRefs: [] };
  for (const f of SERVER_FILES) {
    const src = overrides.get(f);
    const c = src === undefined ? (BASE.get(f) as Census) : censusFile(f, src);
    out.gitAuth.push(...c.gitAuth);
    out.pushTokens.push(...c.pushTokens);
    out.strayRefs.push(...c.strayRefs);
  }
  out.gitAuth.sort();
  out.pushTokens.sort();
  return out;
}

/** A module edge the emitted JS still has: a type-only import or re-export is erased by the compiler and is not one. */
interface ModuleEdge {
  spec: string; // "<computed>" for a non-literal dynamic import() or require()
  kind: "static" | "reexport" | "dynamic" | "require";
  names: string[]; // the bindings it loads ("default", "*", "<side-effect>", or "<dynamic>" when not destructured)
}

const specText = (n: ts.Node | undefined): string =>
  n && (ts.isStringLiteral(n) || ts.isNoSubstitutionTemplateLiteral(n)) ? n.text : "<computed>";

/** The names a dynamic `import()` / `require()` destructures (`const { a, b } = await import("x")`), else `<dynamic>`. */
function destructured(call: ts.CallExpression): string[] {
  let p: ts.Node = call.parent;
  while (ts.isAwaitExpression(p) || ts.isParenthesizedExpression(p)) p = p.parent;
  if (ts.isVariableDeclaration(p) && ts.isObjectBindingPattern(p.name)) {
    return p.name.elements.map((e) => (e.propertyName ?? e.name).getText());
  }
  return ["<dynamic>"];
}

/** Every runtime module edge of one file (static imports, re-exports, dynamic import(), require, import = require). */
function moduleEdges(src: string, file: string): ModuleEdge[] {
  const sf = parseSource(src, file);
  const out: ModuleEdge[] = [];
  const visit = (n: ts.Node): void => {
    if (ts.isImportDeclaration(n) && ts.isStringLiteral(n.moduleSpecifier)) {
      const c = n.importClause;
      const spec = n.moduleSpecifier.text;
      if (!c) out.push({ spec, kind: "static", names: ["<side-effect>"] });
      else if (!c.isTypeOnly) {
        const names: string[] = [];
        if (c.name) names.push("default");
        const nb = c.namedBindings;
        if (nb && ts.isNamespaceImport(nb)) names.push("*");
        if (nb && ts.isNamedImports(nb)) for (const e of nb.elements) if (!e.isTypeOnly) names.push((e.propertyName ?? e.name).text);
        // `import { type A } from "x"` with only type elements is erased too (isolatedModules, no verbatimModuleSyntax).
        if (names.length > 0) out.push({ spec, kind: "static", names });
      }
    } else if (ts.isExportDeclaration(n) && n.moduleSpecifier && ts.isStringLiteral(n.moduleSpecifier)) {
      const ec = n.exportClause;
      const names = n.isTypeOnly ? [] : ec && ts.isNamedExports(ec) ? ec.elements.filter((e) => !e.isTypeOnly).map((e) => (e.propertyName ?? e.name).text) : ["*"];
      if (names.length > 0) out.push({ spec: n.moduleSpecifier.text, kind: "reexport", names });
    } else if (ts.isImportEqualsDeclaration(n) && !n.isTypeOnly && ts.isExternalModuleReference(n.moduleReference)) {
      out.push({ spec: specText(n.moduleReference.expression), kind: "require", names: ["*"] });
    } else if (ts.isCallExpression(n)) {
      if (n.expression.kind === ts.SyntaxKind.ImportKeyword) out.push({ spec: specText(n.arguments[0]), kind: "dynamic", names: destructured(n) });
      else if (ts.isIdentifier(n.expression) && n.expression.text === "require") out.push({ spec: specText(n.arguments[0]), kind: "require", names: destructured(n) });
    }
    ts.forEachChild(n, visit);
  };
  visit(sf);
  return out;
}

const CODE_EXT = [".ts", ".tsx", ".mts", ".mjs", ".js", "/index.ts", "/index.tsx"];
/** An app module path (relative to apps/web-platform) for a specifier; null for a package; undefined when it resolves to nothing. */
function resolveModule(from: string, spec: string): string | null | undefined {
  const base = resolveSpecifier(from, spec);
  if (base === null) return null;
  for (const ext of CODE_EXT) {
    const f = `${base}${ext}`;
    if (existsSync(join(APP, f)) && statSync(join(APP, f)).isFile()) return f;
  }
  // a data file (`./x.json`): a leaf, nothing to follow
  if (existsSync(join(APP, base)) && statSync(join(APP, base)).isFile()) return base;
  return undefined;
}

const EDGE_CACHE = new Map<string, ModuleEdge[]>();
function edgesOf(file: string, overrides: ReadonlyMap<string, string>): ModuleEdge[] {
  const o = overrides.get(file);
  if (o !== undefined) return moduleEdges(o, file);
  if (!SOURCE_RE.test(file)) return [];
  let e = EDGE_CACHE.get(file);
  if (!e) EDGE_CACHE.set(file, (e = moduleEdges(readFileSync(join(APP, file), "utf8"), file)));
  return e;
}

/**
 * The runtime import closure of `root` (breadth first). `violation` is the import path to the first push module reached,
 * or to a computed / unresolvable specifier (red: the walk cannot see past it); null when the closure is push-free.
 */
function runtimeClosure(root: string, overrides: ReadonlyMap<string, string> = new Map()): { reached: Set<string>; violation: string[] | null } {
  const parent = new Map<string, string | null>([[root, null]]);
  const trail = (f: string): string[] => {
    const p: string[] = [];
    for (let x: string | null = f; x !== null; x = parent.get(x) ?? null) p.unshift(x);
    return p;
  };
  if (!existsSync(join(APP, root)) && !overrides.has(root)) return { reached: new Set(), violation: [`<missing ${root}>`] };
  const queue = [root];
  while (queue.length > 0) {
    const f = queue.shift() as string;
    for (const e of edgesOf(f, overrides)) {
      if (e.spec === "<computed>") return { reached: new Set(parent.keys()), violation: [...trail(f), `<computed ${e.kind}>`] };
      const t = resolveModule(f, e.spec);
      if (t === null) continue; // a package: it cannot load app code
      if (t === undefined) return { reached: new Set(parent.keys()), violation: [...trail(f), `<unresolved ${e.spec}>`] };
      if (parent.has(t)) continue;
      parent.set(t, f);
      if (PUSH_MODULES.has(t)) return { reached: new Set(parent.keys()), violation: trail(t) };
      queue.push(t);
    }
  }
  return { reached: new Set(parent.keys()), violation: null };
}

/**
 * D25(5), D45(d): what is wrong with one token-free KB sync module (empty = nothing). `src` undefined = the listed file
 * does not exist, which fails (pattern P3-13: a rename must not turn the row vacuous).
 */
function tokenFreeViolations(f: string, src: string | undefined): string[] {
  if (src === undefined) return [`${f}: listed but missing`];
  const sf = parseSource(src, f);
  const out: string[] = [];
  let runnerCalls = 0;
  const visit = (n: ts.Node): void => {
    if (ts.isCallExpression(n)) {
      const name = calleeName(n.expression);
      if (name === "runIsolatedGitLocal") runnerCalls++;
      const first = n.arguments[0];
      if (first && literalText(first) === "git") out.push(`${f}: ${name}("git")`);
    }
    ts.forEachChild(n, visit);
  };
  visit(sf);
  const edges = moduleEdges(src, f);
  for (const e of edges) if (/(^|:)child_process$/.test(e.spec)) out.push(`${f}: child_process ${e.kind} import`);
  const imports = edges.flatMap((e) => e.names.map((n) => `${e.spec} ${n}${e.kind === "static" ? "" : ` (${e.kind})`}`)).sort();
  const listed = [...(TOKEN_FREE_IMPORTS[f] ?? [])].sort();
  for (const i of imports) if (!listed.includes(i)) out.push(`${f}: unlisted import ${i}`);
  for (const i of listed) if (!imports.includes(i)) out.push(`${f}: listed import no longer present ${i}`);
  if (runnerCalls !== ISOLATED_RUNNER_SITES[f]) out.push(`${f}: ${runnerCalls} runIsolatedGitLocal calls, table says ${ISOLATED_RUNNER_SITES[f]}`);
  return out;
}

describe("census: gitWithInstallationAuth calls, push-verb tokens and the KB pull import boundaries in server/ (D12, D19, D25)", () => {
  const c = census();

  test("the walk covers .mts and .mjs server files too (D19(2))", () => {
    expect(SERVER_FILES.some((f) => f.endsWith(".mjs"))).toBe(true);
    expect(SERVER_FILES).toContain("server/kb-sync-publish.ts");
  });

  test("gitWithInstallationAuth: every reference is an import, a call or its definition (or a listed injection)", () => {
    expect([...c.strayRefs].sort()).toEqual([...STRAY_ALLOWED].sort());
  });

  test("gitWithInstallationAuth: the call sites by file, first verb and arm equal the checked-in table", () => {
    expect(c.gitAuth).toEqual([...GIT_AUTH_SITES].sort());
    expect(c.gitAuth.filter((s) => s.endsWith(" legacy-suspect"))).toEqual([]);
    // the KB sync's token-bearing calls are all hardened (H5, D25(5)): the push, and the pull's ls-remote and fetch
    const kbSync = c.gitAuth.filter((x) => /^server\/kb-sync-(publish|remote)\.ts /.test(x));
    expect(kbSync).toHaveLength(3);
    for (const s of kbSync) expect(s).toMatch(/ hardened$/);
    // D25(5): the pull leaves and the held count never carry the token, and session-sync no longer does at all
    for (const f of KB_SYNC_TOKEN_FREE) expect(c.gitAuth.filter((x) => x.startsWith(`${f} `)), f).toEqual([]);
    expect(c.gitAuth.filter((x) => x.startsWith("server/session-sync.ts "))).toEqual([]);
    // Phase 0: the connected-repo wrapper (moved out of session-sync) carries no token either.
    expect(c.gitAuth.filter((x) => x.startsWith("server/connected-repo-git.ts "))).toEqual([]);
  });

  test("D25(5), D45(d): the token-free KB sync modules spawn no git, call the isolated runner a known number of times and import a closed set", () => {
    expect(Object.keys(TOKEN_FREE_IMPORTS).sort()).toEqual([...KB_SYNC_TOKEN_FREE].sort());
    for (const f of KB_SYNC_TOKEN_FREE) {
      expect(tokenFreeViolations(f, SERVER_FILES.includes(f) ? readFileSync(join(APP, f), "utf8") : undefined), f).toEqual([]);
    }
  });

  test("known-positive (D45(d)): a missing listed file, an unlisted git wrapper, a dynamic import and a child_process import each fail the token-free check", () => {
    const f = "server/kb-sync-held.ts";
    const src = readFileSync(join(APP, f), "utf8");
    // pattern P3-13: renamed or moved, the row fails instead of being skipped
    expect(tokenFreeViolations("server/kb-sync-held-count.ts", undefined)).toEqual(["server/kb-sync-held-count.ts: listed but missing"]);
    // tests F7 M8e: an existing git wrapper under any name
    const wrapper = `import { runGit } from "./compound-promote-create-gates";\n${src}\nexport const __planted = () => runGit("/w", ["fetch", "origin"]);\n`;
    expect(tokenFreeViolations(f, wrapper)).toEqual([`${f}: unlisted import ./compound-promote-create-gates runGit`]);
    const dyn = `${src}\nexport async function __planted(): Promise<void> {\n  const { gitWithPrivateKeyAuth } = await import("./git-key-auth");\n  void gitWithPrivateKeyAuth;\n}\n`;
    expect(tokenFreeViolations(f, dyn)).toEqual([`${f}: unlisted import ./git-key-auth gitWithPrivateKeyAuth (dynamic)`]);
    const cp = `import { execFile } from "node:child_process";\n${src}\nexport const __planted = () => execFile("git", ["fetch"]);\n`;
    expect(tokenFreeViolations(f, cp)).toEqual([
      `${f}: execFile("git")`,
      `${f}: child_process static import`,
      `${f}: unlisted import node:child_process execFile`,
    ]);
    // the type-only form is erased, so it is not an import of a callable
    expect(tokenFreeViolations(f, `import type { RunGit } from "./compound-promote-create-gates";\n${src}`)).toEqual([]);
  });

  test("D25(3), D45(d): no push-free module reaches the push at runtime, transitively (static, re-export, dynamic import(), require)", () => {
    for (const f of PUSH_FREE_MODULES) {
      expect(SERVER_FILES, f).toContain(f);
      expect(runtimeClosure(f).violation, f).toBeNull();
    }
    // non-vacuity: the walk follows dynamic edges (the self-heal loads the writer and the held count only by import())
    const selfHeal = runtimeClosure("server/workspace-sync.ts").reached;
    for (const m of ["server/connected-repo-git.ts", "server/kb-sync-held-refresh.ts", "server/kb-sync-pull.ts", "server/kb-sync-remote.ts"]) {
      expect(selfHeal, m).toContain(m);
    }
  });

  test("known-positive (D45(d)): the pre-leaf-move shape, a value edge, a re-export, a computed or unresolvable specifier and a missing file are red; a type-only edge is not", () => {
    const ws = "server/workspace-sync.ts";
    const wsSrc = readFileSync(join(APP, ws), "utf8");
    // arch F5, before the Phase 0 leaf move: the self-heal dynamic-imported session-sync, which statically imports the push
    const preMove = runtimeClosure(ws, new Map([[ws, `${wsSrc}\nexport const __planted = () => import("@/server/session-sync");\n`]])).violation;
    expect(preMove?.slice(0, 2)).toEqual([ws, "server/session-sync.ts"]);
    expect(PUSH_MODULES.has(preMove?.at(-1) ?? "")).toBe(true);
    // two hops deep through a module that is not listed: still red
    const crg = "server/connected-repo-git.ts";
    const crgSrc = readFileSync(join(APP, crg), "utf8");
    const TYPE_EDGE = 'import type { KbWorkspaceWriter } from "./kb-sync-publish";';
    expect(crgSrc).toContain(TYPE_EDGE); // Phase 0's pinned type-only edge
    expect(runtimeClosure(crg).violation).toBeNull();
    expect(runtimeClosure(crg, new Map([[crg, crgSrc.replace(TYPE_EDGE, 'import { type KbWorkspaceWriter } from "./kb-sync-publish";')]])).violation).toBeNull();
    expect(runtimeClosure(crg, new Map([[crg, crgSrc.replace(TYPE_EDGE, 'import { classifyPushError } from "./kb-sync-publish";')]])).violation).toEqual([crg, "server/kb-sync-publish.ts"]);
    expect(runtimeClosure(crg, new Map([[crg, `${crgSrc}\nexport { classifyPushError } from "./kb-sync-publish";\n`]])).violation).toEqual([crg, "server/kb-sync-publish.ts"]);
    expect(runtimeClosure(crg, new Map([[crg, `${crgSrc}\nexport type { PushErrorClass } from "./kb-sync-publish";\n`]])).violation).toBeNull();
    expect(runtimeClosure(crg, new Map([[crg, `${crgSrc}\nexport const __planted = (m: string) => import(m);\n`]])).violation).toEqual([crg, "<computed dynamic>"]);
    expect(runtimeClosure(crg, new Map([[crg, `${crgSrc}\nexport const __planted = () => import("./no-such-module");\n`]])).violation).toEqual([crg, "<unresolved ./no-such-module>"]);
    expect(runtimeClosure("server/kb-sync-gone.ts").violation).toEqual(["<missing server/kb-sync-gone.ts>"]);
  });

  test("push / send-pack / receive-pack tokens, in any form, equal the checked-in table", () => {
    expect(c.pushTokens).toEqual([...PUSH_TOKEN_SITES].sort());
  });

  test("a push-verb token in a git argv position sits only in the KB sync push, the cc push or a named non-workspace file", () => {
    const argv = c.pushTokens.filter((s) => / (argv@|var:)/.test(s));
    for (const s of argv) expect(Object.keys(ARGV_ALLOWED), s).toContain(s.split(" ")[0]);
    expect(argv.filter((s) => s.startsWith("server/kb-sync-publish.ts "))).toHaveLength(1);
    expect(argv.filter((s) => s.startsWith("server/session-sync.ts "))).toEqual([]);
    expect(argv.filter((s) => s.startsWith("server/connected-repo-git.ts "))).toEqual([]);
  });

  test("no non-test file outside server/ can reach gitWithInstallationAuth (D19(2))", () => {
    const edges: string[] = [];
    for (const abs of walk(APP, new Set([...SKIP_DIRS, "server"]))) {
      const file = relative(APP, abs);
      const src = readFileSync(abs, "utf8");
      if (!src.includes("git-auth") && !src.includes(IDENT)) continue; // the AST below decides; this only skips the parse
      for (const h of censusSource(src, file, IDENT, ["server/git-auth"])) {
        if (h.kind === "id") edges.push(`${file} id:${h.role}`);
        else edges.push(`${file} ${h.role}`);
      }
    }
    expect(edges.sort()).toEqual([...OUTSIDE_SERVER_GIT_AUTH_EDGES].sort());
  });

  test("known-positive: planted pushes (backtick, variable, spread with a -c prefix, alias) and falsy hardened values all turn the census red", () => {
    // #12718: session-sync.ts no longer imports gitWithInstallationAuth (the pull moved to the hardened arm), so the plant
    // adds the import, with an alias, next to an import the file keeps.
    const target = "server/session-sync.ts";
    const src = readFileSync(join(APP, target), "utf8");
    const ANCHOR = 'import { KB_ROOT } from "./kb-root";';
    expect(src).toContain(ANCHOR);
    const planted = [
      src.replace(ANCHOR, `import { gitWithInstallationAuth, gitWithInstallationAuth as gAuth } from "./git-auth";\n${ANCHOR}`),
      "export async function __plantedA(p: string): Promise<void> {",
      "  await gitWithInstallationAuth([`push`, \"u\", \"HEAD:refs/heads/x\"], 1, { cwd: p });",
      "}",
      "const PLANTED_VERB = \"send-pack\";",
      "export async function __plantedB(p: string): Promise<void> {",
      "  await gAuth([...[\"-c\", \"x=y\"], PLANTED_VERB, `receive-pack`], 1, { cwd: p });",
      "}",
      "export async function __plantedC(): Promise<void> {",
      "  await gitWithInstallationAuth([\"ls-remote\", \"u\"], 1, { hardened: undefined });",
      "  await gitWithInstallationAuth([\"ls-remote\", \"u\"], 1, { hardened: void 0 });",
      "  await gitWithInstallationAuth([\"ls-remote\", \"u\"], 1, { hardened: (null as never) });",
      "}",
    ].join("\n");
    const red = census(new Map([[target, planted]]));
    // the backtick push and the spread-prefixed call are new git-auth sites; the alias is followed
    expect(red.gitAuth).toContain("server/session-sync.ts push legacy");
    expect([...red.strayRefs].sort()).toEqual([...STRAY_ALLOWED].sort()); // the alias import is followed, not stray
    expect(red.gitAuth).toContain("server/session-sync.ts dynamic legacy");
    // D19(1): `hardened:` is classified by value, so a falsy handle is not "hardened"
    expect(red.gitAuth.filter((x) => x === "server/session-sync.ts ls-remote legacy-suspect")).toHaveLength(3);
    expect(red.gitAuth).not.toEqual([...GIT_AUTH_SITES].sort());
    // every spelling of the push verbs is seen
    expect(red.pushTokens).toContain("server/session-sync.ts push argv@call:gitWithInstallationAuth");
    expect(red.pushTokens).toContain("server/session-sync.ts send-pack var:PLANTED_VERB");
    expect(red.pushTokens).toContain("server/session-sync.ts receive-pack argv@call:gAuth");
    expect(red.pushTokens).not.toEqual([...PUSH_TOKEN_SITES].sort());
    // and the known-negative: the unmodified file through the same override path is green
    const green = census(new Map([[target, src]]));
    expect(green.gitAuth).toEqual([...GIT_AUTH_SITES].sort());
    expect(green.pushTokens).toEqual([...PUSH_TOKEN_SITES].sort());
  });
});
