// AST census of the token-bearing git surface (#12600, CTO ruling D12(1)), over EVERY apps/web-platform/server/**/*.ts(x),
// built on test/approval/source-scan.ts (`parseSource` = `ts.createSourceFile`, `censusSource`, `callSites`). It replaces
// the 2-file / 1-spelling regex census: a backtick literal, a variable, a spread, a `-c` prefix, an alias import or a
// function passed as a value are each seen by the grammar, not by a pattern.
//
//   1. Every `gitWithInstallationAuth` reference is an import, a call or its definition (an alias is followed; a value use,
//      namespace member, re-export or dynamic import is red). Every call is recorded as (file, first verb or `dynamic`,
//      arm = `hardened` when the options object carries `hardened:`, else `legacy`) and the multiset must equal
//      GIT_AUTH_SITES below.
//   2. Every string / no-substitution template literal (and template head) equal to `push`, `send-pack` or `receive-pack`
//      is recorded with its syntactic context (an argv array and the call or variable it feeds, a call argument, a
//      property, a variable, a comparison) and the multiset must equal PUSH_TOKEN_SITES. A token in a git argv position
//      (`argv@...` or `var:...`) may sit only in kb-sync-publish.ts (the ONE KB sync push) and push-branch.ts (the
//      approved cc push), plus the named non-workspace pushes and classifier word lists below.
//
// Out of the census by design: REST writes (the Contents API) are user-initiated KB UI writes, not git pushes. A
// computed name (`"pu" + "sh"`, `R["gitWith" + "InstallationAuth"]`) is invisible to a static scan (named residual).
import { cpSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
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
  "server/kb-sync-publish.ts ls-remote hardened",
  "server/kb-sync-publish.ts push hardened",
  "server/push-branch.ts push conditional", // hardened when the isolated dir was created, else the legacy cwd arm
  "server/session-sync.ts pull legacy",
  "server/workspace-sync.ts fetch opts-dynamic", // an options variable built from the injected runner's caller
  "server/workspace-sync.ts pull legacy",
  "server/workspace-sync.ts symbolic-ref legacy",
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
  "server/workspace-sync.ts other",
  "server/workspace-sync.ts other",
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
  "server/inngest/functions/_cron-safe-commit.ts push arg:failure",
  "server/inngest/functions/_cron-safe-commit.ts push argv@call:git",
  "server/inngest/functions/workspace-reconcile-on-push.ts push prop:op",
  "server/kb-sync-publish.ts push argv@call:gitWithInstallationAuth",
  "server/permission-callback-bash-batch.ts push argv@var:NO_BATCH_GIT_VERBS",
  "server/push-branch.ts push argv@call:gitWithInstallationAuth",
  "server/session-sync.ts push arg:autoCommitFailure",
];

const walk = (dir: string): string[] =>
  readdirSync(dir).flatMap((f) => {
    const p = join(dir, f);
    if (statSync(p).isDirectory()) return walk(p);
    return /\.tsx?$/.test(f) && !f.endsWith(".d.ts") ? [p] : [];
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

interface Census {
  gitAuth: string[];
  pushTokens: string[];
  /** references of the identifier that are not an import, a call or the definition */
  strayRefs: string[];
}

function census(root: string): Census {
  const out: Census = { gitAuth: [], pushTokens: [], strayRefs: [] };
  for (const abs of walk(join(root, "server"))) {
    const file = relative(root, abs);
    const src = readFileSync(abs, "utf8");
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
        const arm = !opts
          ? "legacy"
          : !ts.isObjectLiteralExpression(opts)
            ? "opts-dynamic"
            : opts.properties.some(named)
              ? "hardened"
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
  out.gitAuth.sort();
  out.pushTokens.sort();
  return out;
}

describe("census: the token-bearing git surface of server/ (D12)", () => {
  const c = census(APP);

  test("gitWithInstallationAuth: every reference is an import, a call or its definition (or a listed injection)", () => {
    expect([...c.strayRefs].sort()).toEqual([...STRAY_ALLOWED].sort());
  });

  test("gitWithInstallationAuth: the call sites by file, first verb and arm equal the checked-in table", () => {
    expect(c.gitAuth).toEqual([...GIT_AUTH_SITES].sort());
    // the KB sync's token-bearing calls are all hardened (H5)
    for (const s of c.gitAuth.filter((x) => x.startsWith("server/kb-sync-publish.ts "))) expect(s).toMatch(/ hardened$/);
  });

  test("push / send-pack / receive-pack tokens, in any form, equal the checked-in table", () => {
    expect(c.pushTokens).toEqual([...PUSH_TOKEN_SITES].sort());
  });

  test("a push-verb token in a git argv position sits only in the KB sync push, the cc push or a named non-workspace file", () => {
    const argv = c.pushTokens.filter((s) => / (argv@|var:)/.test(s));
    for (const s of argv) expect(Object.keys(ARGV_ALLOWED), s).toContain(s.split(" ")[0]);
    expect(argv.filter((s) => s.startsWith("server/kb-sync-publish.ts "))).toHaveLength(1);
    expect(argv.filter((s) => s.startsWith("server/session-sync.ts "))).toEqual([]);
  });

  test("known-positive: planted pushes in a temp copy (backtick, variable, spread with a -c prefix, alias) all turn the census red", () => {
    const tmp = mkdtempSync(join(tmpdir(), "census-"));
    try {
      cpSync(join(APP, "server"), join(tmp, "server"), { recursive: true });
      const target = join(tmp, "server", "session-sync.ts");
      const src = readFileSync(target, "utf8");
      const planted = [
        src.replace(
          'import { gitWithInstallationAuth } from "./git-auth";',
          'import { gitWithInstallationAuth, gitWithInstallationAuth as gAuth } from "./git-auth";',
        ),
        "export async function __plantedA(p: string): Promise<void> {",
        "  await gitWithInstallationAuth([`push`, \"u\", \"HEAD:refs/heads/x\"], 1, { cwd: p });",
        "}",
        "const PLANTED_VERB = \"send-pack\";",
        "export async function __plantedB(p: string): Promise<void> {",
        "  await gAuth([...[\"-c\", \"x=y\"], PLANTED_VERB, `receive-pack`], 1, { cwd: p });",
        "}",
      ].join("\n");
      writeFileSync(target, planted);
      const red = census(tmp);
      // the backtick push and the spread-prefixed call are new git-auth sites; the alias is followed
      expect(red.gitAuth).toContain("server/session-sync.ts push legacy");
      expect([...red.strayRefs].sort()).toEqual([...STRAY_ALLOWED].sort()); // the alias import is followed, not stray
      expect(red.gitAuth).toContain("server/session-sync.ts dynamic legacy");
      expect(red.gitAuth).not.toEqual([...GIT_AUTH_SITES].sort());
      // every spelling of the push verbs is seen
      expect(red.pushTokens).toContain("server/session-sync.ts push argv@call:gitWithInstallationAuth");
      expect(red.pushTokens).toContain("server/session-sync.ts send-pack var:PLANTED_VERB");
      expect(red.pushTokens).toContain("server/session-sync.ts receive-pack argv@call:gAuth");
      expect(red.pushTokens).not.toEqual([...PUSH_TOKEN_SITES].sort());
      // and the known-negative: the unmodified copy is green
      writeFileSync(target, src);
      const green = census(tmp);
      expect(green.gitAuth).toEqual([...GIT_AUTH_SITES].sort());
      expect(green.pushTokens).toEqual([...PUSH_TOKEN_SITES].sort());
    } finally {
      rmSync(tmp, { recursive: true, force: true });
    }
  });
});
