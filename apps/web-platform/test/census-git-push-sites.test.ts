// AST census of the token-bearing git surface (#12600, CTO rulings D12(1), D19), over EVERY apps/web-platform/server/** source
// file (`.ts`, `.tsx`, `.mts`, `.mjs`),
// built on test/approval/source-scan.ts (`parseSource` = `ts.createSourceFile`, `censusSource`, `callSites`). It replaces
// the 2-file / 1-spelling regex census: a backtick literal, a variable, a spread, a `-c` prefix, an alias import or a
// function passed as a value are each seen by the grammar, not by a pattern.
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
//
// PUSH_TOKEN_SITES churns with HUMAN-TEXT `push` tokens too (an op slug, a message, a word list): a new row there is reviewed
// like any other, it is not proof of a new git push. The known-positive plants its shapes through an in-memory override of
// one file, so only that file is re-parsed (D19(3)).
//
// Out of the census by design: REST writes (the Contents API) are user-initiated KB UI writes, not git pushes. A
// computed name (`"pu" + "sh"`, `R["gitWith" + "InstallationAuth"]`) is invisible to a static scan (named residual).
import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import ts from "typescript";
import { describe, expect, test } from "vitest";
import { callSites, censusSource, parseSource } from "./approval/source-scan";

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
  "server/kb-sync-objects.ts": 6, // isCommitPresent, isAncestor, commitTree, handOver, isKbOnlySide (merge-base, diff)
  "server/kb-sync-pull.ts": 5, // the walk, the size check, merge-tree, the first-parent chain and its KB batch read
  "server/kb-sync-side-pr.ts": 0,
  "server/kb-sync-held.ts": 1, // the held count's diff (#12714)
};

/** #12718 (D25(3)): modules on the pull's import graph that must never import the push. */
const PUSH_FREE_MODULES = [
  "server/kb-sync-objects.ts",
  "server/kb-sync-pull.ts",
  "server/kb-sync-remote.ts",
  "server/kb-sync-side-pr.ts",
  "server/workspace-sync.ts",
  "server/git-isolated-dispose.ts",
  "server/agent-git-identity.ts",
  // Review Phase 0: the leaves the pull and the self-heal reach (the collision precheck, the held-count path).
  "server/workspace-collision.ts",
  "server/kb-sync-held-refresh.ts",
];

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

describe("census: the token-bearing git surface of server/ (D12, D19)", () => {
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

  test("Phase 0: connected-repo-git.ts reaches the push module for a type only (no runtime edge to kb-sync-publish or push-branch)", () => {
    const f = "server/connected-repo-git.ts";
    expect(SERVER_FILES).toContain(f);
    const sf = parseSource(readFileSync(join(APP, f), "utf8"), f);
    const runtime: string[] = [];
    const visit = (n: ts.Node): void => {
      if ((ts.isImportDeclaration(n) || ts.isExportDeclaration(n)) && n.moduleSpecifier && ts.isStringLiteral(n.moduleSpecifier)) {
        const typeOnly = ts.isImportDeclaration(n) ? n.importClause?.isTypeOnly === true : n.isTypeOnly;
        if (!typeOnly) runtime.push(n.moduleSpecifier.text);
      }
      if (ts.isCallExpression(n) && n.expression.kind === ts.SyntaxKind.ImportKeyword) {
        runtime.push(n.arguments[0] ? (literalText(n.arguments[0]) ?? "<computed>") : "<computed>");
      }
      ts.forEachChild(n, visit);
    };
    visit(sf);
    expect(runtime.filter((m) => /(^|\/)(kb-sync-publish|push-branch|session-sync)$/.test(m) || m === "<computed>")).toEqual([]);
  });

  test("D25(5): no literal git exec in the token-free KB sync modules; their isolated-runner call sites are the known counts", () => {
    for (const f of KB_SYNC_TOKEN_FREE) {
      if (!SERVER_FILES.includes(f)) continue; // kb-sync-held.ts lands with #12714's half of this PR
      const sf = parseSource(readFileSync(join(APP, f), "utf8"), f);
      const spawnsGit: string[] = [];
      let runnerCalls = 0;
      const visit = (n: ts.Node): void => {
        if (ts.isImportDeclaration(n) && ts.isStringLiteral(n.moduleSpecifier) && /child_process$/.test(n.moduleSpecifier.text)) spawnsGit.push("child_process import");
        if (ts.isCallExpression(n)) {
          const name = calleeName(n.expression);
          if (name === "runIsolatedGitLocal") runnerCalls++;
          const first = n.arguments[0];
          if (first && literalText(first) === "git") spawnsGit.push(`${name}("git")`);
          if (n.expression.kind === ts.SyntaxKind.ImportKeyword && first && /child_process$/.test(literalText(first) ?? "")) spawnsGit.push("child_process dynamic import");
        }
        ts.forEachChild(n, visit);
      };
      visit(sf);
      expect(spawnsGit, f).toEqual([]);
      expect(runnerCalls, f).toBe(ISOLATED_RUNNER_SITES[f]);
    }
  });

  test("D25(3): the pull leaves never import the push (kb-sync-publish.ts, push-branch.ts), statically or dynamically", () => {
    for (const f of PUSH_FREE_MODULES) {
      expect(SERVER_FILES, f).toContain(f);
      const sf = parseSource(readFileSync(join(APP, f), "utf8"), f);
      const specs: string[] = [];
      const visit = (n: ts.Node): void => {
        if ((ts.isImportDeclaration(n) || ts.isExportDeclaration(n)) && n.moduleSpecifier && ts.isStringLiteral(n.moduleSpecifier)) specs.push(n.moduleSpecifier.text);
        if (ts.isCallExpression(n) && n.expression.kind === ts.SyntaxKind.ImportKeyword) {
          const t = n.arguments[0] ? literalText(n.arguments[0]) : null;
          specs.push(t ?? "<computed>");
        }
        ts.forEachChild(n, visit);
      };
      visit(sf);
      expect(specs.filter((m) => /(^|\/)(kb-sync-publish|push-branch)$/.test(m) || m === "<computed>"), f).toEqual([]);
    }
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
