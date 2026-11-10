import { execFileSync } from "node:child_process";
import { lstatSync, readFileSync } from "node:fs";
import { extname, join } from "node:path";
import ts from "typescript";
import { describe, expect, it } from "vitest";

// #8211, ADR-323 Decision 9 (2026-11-10 amendment, "What keeps the slot verify-only") — Guard 1 "the accept-only slot
// never signs", as structure rather than a call-site scan. What these rows check, and nothing more:
//   (a) no other file spells the MAC domain string literally (whole repo, any extension, test roots and the top-level
//       knowledge-base/ excluded);
//   (b, c) the export list of proxy-hello.ts is pinned, and the canonical-string builder is not exported;
//   (d) inside proxy-hello.ts only verifyProxyHello reads `acceptAlso`;
//   (e) proxy-hello.ts imports node:crypto and nothing else (no other import, no require(, no import();
//   (f) signProxyHello takes a `Buffer` key and MACs exactly `macOf(<that parameter>, buildHelloMacInput(...))`, the
//       parameter never reassigned or shadowed;
//   (g) module-wide, macOf is called exactly 3 times (signer once, verifier twice), buildHelloMacInput exactly twice
//       (signer, verifier) and HELLO_DOMAIN is read once (in the builder), never as a value, so neither the builder,
//       the MAC helper nor the domain constant can leave the module (an `Object.assign(signProxyHello, {...})` expando).
// Together (b)-(g) mean proxy-hello.ts itself cannot sign with the slot. Review-time residuals (ADR-323), which no row
// here sees:
//   - a new caller elsewhere handing the slot to the exported signProxyHello (it signs with whatever Buffer it gets);
//   - a domain string re-spelled elsewhere (fragments, escapes, base64) feeding a new HMAC;
//   - an edit to the existing call site or loader gated on a production-only signal other than NODE_ENV (a NODE_ENV
//     gate is caught by the NODE_ENV=production rows in session-proxy-hello.test.ts).
// The behaviour rows (the sender signs with current only, the verifier accepts both, the listener needs current) live
// in session-proxy-hello.test.ts, proxy-hello.test.ts and proxy-hello-rotation-phases.test.ts.

const DOMAIN = "soleur-proxy-hello-v1";
const MODULE = "apps/web-platform/server/proxy-hello.ts";
const REPO = execFileSync("git", ["rev-parse", "--show-toplevel"], { cwd: __dirname, encoding: "utf8" }).trim();

// Tracked files plus untracked, not-ignored ones (a new file is caught before it is committed). Out of scope, anchored
// at the repo root: the top-level knowledge-base/ and the real test roots (tests and prose quote the string on
// purpose). A production module under a nested `test/` or `knowledge-base/` segment (server/test/relay.ts) is scanned.
const EXCLUDED =
  /^(knowledge-base|test|\.github\/scripts\/test|apps\/[^/]+\/test|plugins\/soleur\/test|plugins\/soleur\/skills\/[^/]+\/test)\//;
const LISTED = execFileSync("git", ["ls-files", "-z", "--cached", "--others", "--exclude-standard"], {
  cwd: REPO,
  encoding: "utf8",
  maxBuffer: 64 * 1024 * 1024,
})
  .split("\0")
  .filter((f) => f !== "" && !EXCLUDED.test(f));

const SHEBANG = "#!/usr/bin/env bash";
const scanned: string[] = [];
const hits = new Map<string, string[]>([
  [DOMAIN, []],
  [SHEBANG, []],
]);
for (const f of [...new Set(LISTED)]) {
  const p = join(REPO, f);
  let st;
  try {
    st = lstatSync(p);
  } catch {
    continue; // tracked but deleted in the working tree
  }
  if (!st.isFile()) continue; // symlinks, submodule gitlinks
  scanned.push(f);
  const buf = readFileSync(p);
  for (const [needle, list] of hits) if (buf.includes(needle)) list.push(f);
}

const MODULE_SRC = readFileSync(join(REPO, MODULE), "utf8");
const SF = ts.createSourceFile("proxy-hello.ts", MODULE_SRC, ts.ScriptTarget.Latest, true);
const hasModifier = (n: ts.Node, k: ts.SyntaxKind) =>
  ts.canHaveModifiers(n) && (ts.getModifiers(n) ?? []).some((m) => m.kind === k);
const fnDecl = (name: string) =>
  SF.statements.find((s): s is ts.FunctionDeclaration => ts.isFunctionDeclaration(s) && s.name?.text === name);
const within = (n: ts.Node, outer: ts.Node | undefined) =>
  outer !== undefined && n.getStart(SF) >= outer.getStart(SF) && n.getEnd() <= outer.getEnd();
const where = (n: ts.Node) => `${SF.getLineAndCharacterOfPosition(n.getStart(SF)).line + 1}: ${n.parent.getText(SF).slice(0, 80)}`;
const forEachNode = (cb: (n: ts.Node) => void) => {
  const visit = (n: ts.Node) => {
    cb(n);
    ts.forEachChild(n, visit);
  };
  visit(SF);
};
/** Is `n` the `name` of a declaration (function, variable, parameter, binding element, class, property)? */
const isDeclName = (n: ts.Identifier) => {
  const p = n.parent as ts.Node & { name?: ts.Node };
  return (
    p.name === n &&
    (ts.isFunctionDeclaration(p) ||
      ts.isFunctionExpression(p) ||
      ts.isVariableDeclaration(p) ||
      ts.isParameter(p) ||
      ts.isBindingElement(p) ||
      ts.isClassDeclaration(p) ||
      ts.isClassExpression(p))
  );
};

describe("Guard 1 structure: the accept-only slot never signs (#8211)", () => {
  it("(a) positive control: the walk reads proxy-hello.ts and files of other types", () => {
    expect(scanned.length).toBeGreaterThan(1000);
    expect(scanned).toContain(MODULE);
    const exts = new Set(scanned.map((f) => extname(f)));
    for (const e of [".sh", ".mjs", ".yml", ".tf", ".json"]) expect(exts, e).toContain(e);
    // The same read finds a needle in a non-.ts file, so the content check is not blind outside TypeScript.
    expect(hits.get(SHEBANG)?.some((f) => f.endsWith(".sh"))).toBe(true);
  });

  it("(a) the exclusion is anchored: only real test roots and the top-level knowledge-base/ are skipped", () => {
    for (const p of ["knowledge-base/x.md", "apps/web-platform/test/x.test.ts", "plugins/soleur/test/x.sh", "test/x.sh"]) {
      expect(EXCLUDED.test(p), p).toBe(true);
    }
    for (const p of ["apps/web-platform/server/test/relay.ts", "apps/web-platform/lib/knowledge-base/relay.ts", "plugins/soleur/knowledge-base/x.md"]) {
      expect(EXCLUDED.test(p), p).toBe(false);
    }
  });

  it(`(a) the domain string "${DOMAIN}" appears only in proxy-hello.ts (any extension, test roots and knowledge-base/ excluded)`, () => {
    expect(hits.get(DOMAIN)).toEqual([MODULE]);
  });

  it("(b, c) the export list is exactly the pinned set: no re-export, alias, default export or exported builder", () => {
    const exported: string[] = [];
    const other: string[] = [];
    for (const st of SF.statements) {
      if (ts.isExportDeclaration(st) || ts.isExportAssignment(st)) {
        other.push(st.getText(SF));
        continue;
      }
      if (!hasModifier(st, ts.SyntaxKind.ExportKeyword)) continue;
      if (hasModifier(st, ts.SyntaxKind.DefaultKeyword)) other.push(st.getText(SF).slice(0, 80));
      else if (ts.isVariableStatement(st)) {
        for (const d of st.declarationList.declarations) {
          if (ts.isIdentifier(d.name)) exported.push(d.name.text);
          else other.push(d.name.getText(SF));
        }
      } else if (
        (ts.isFunctionDeclaration(st) ||
          ts.isInterfaceDeclaration(st) ||
          ts.isTypeAliasDeclaration(st) ||
          ts.isClassDeclaration(st) ||
          ts.isEnumDeclaration(st)) &&
        st.name
      ) {
        exported.push(st.name.text);
      } else other.push(ts.SyntaxKind[st.kind]);
    }
    expect(other).toEqual([]);
    expect(exported).toEqual([
      "HELLO_MAX_BYTES",
      "SKEW_S",
      "REPLAY_MAX",
      "isCanonicalUuid",
      "signProxyHello",
      "helloKeyFingerprint",
      "ReplayCache",
      "createReplayCache",
      "HelloVerifyKeys",
      "verifyProxyHello",
    ]);
    // The builder exists and carries no export modifier (b); (g) pins that it never leaves the module as a value.
    const builder = fnDecl("buildHelloMacInput");
    expect(builder).toBeDefined();
    expect(hasModifier(builder as ts.Node, ts.SyntaxKind.ExportKeyword)).toBe(false);
  });

  it("(d) `acceptAlso` is read only inside verifyProxyHello (the HelloVerifyKeys member declaration aside)", () => {
    const verifier = fnDecl("verifyProxyHello");
    expect(verifier).toBeDefined();
    const outside: string[] = [];
    let readsInVerifier = 0;
    forEachNode((n) => {
      const named =
        ((ts.isIdentifier(n) || ts.isPrivateIdentifier(n)) && n.text === "acceptAlso") ||
        ((ts.isStringLiteral(n) || ts.isNoSubstitutionTemplateLiteral(n)) && n.text === "acceptAlso");
      if (!named) return;
      const isMemberDecl =
        ts.isPropertySignature(n.parent) &&
        n.parent.name === n &&
        ts.isInterfaceDeclaration(n.parent.parent) &&
        n.parent.parent.name.text === "HelloVerifyKeys";
      if (within(n, verifier)) {
        if (ts.isPropertyAccessExpression(n.parent) && n.parent.name === n) readsInVerifier += 1;
      } else if (!isMemberDecl) outside.push(where(n));
    });
    expect(outside).toEqual([]);
    expect(readsInVerifier).toBeGreaterThanOrEqual(1); // vacuity floor: the verifier does read the slot
  });

  it("(e) proxy-hello.ts is a leaf: its only import is node:crypto, with no require(, import( or import = require", () => {
    const imports = SF.statements.filter(ts.isImportDeclaration).map((d) => (d.moduleSpecifier as ts.StringLiteral).text);
    expect(imports).toEqual(["node:crypto"]);
    const loaders: string[] = [];
    forEachNode((n) => {
      if (ts.isImportEqualsDeclaration(n)) loaders.push(where(n));
      else if (ts.isCallExpression(n) && n.expression.kind === ts.SyntaxKind.ImportKeyword) loaders.push(where(n));
      else if (ts.isIdentifier(n) && (n.text === "require" || n.text === "getBuiltinModule" || n.text === "createRequire")) loaders.push(where(n));
    });
    expect(loaders).toEqual([]);
  });

  it("(f) signProxyHello's key is a `Buffer` parameter, never reassigned or shadowed, and its one MAC is macOf(<key>, buildHelloMacInput(...))", () => {
    const signer = fnDecl("signProxyHello");
    expect(signer).toBeDefined();
    const param = signer!.parameters[0];
    expect(ts.isIdentifier(param.name)).toBe(true);
    const keyName = (param.name as ts.Identifier).text;
    expect(param.type?.getText(SF)).toBe("Buffer");
    expect(param.questionToken ?? param.initializer ?? param.dotDotDotToken).toBeUndefined();

    const macCalls: ts.CallExpression[] = [];
    const writes: string[] = [];
    const namesIn = (n: ts.Node): ts.Identifier[] => {
      const out: ts.Identifier[] = [];
      const v = (x: ts.Node) => {
        if (ts.isIdentifier(x) && x.text === keyName) out.push(x);
        ts.forEachChild(x, v);
      };
      v(n);
      return out;
    };
    forEachNode((n) => {
      if (!within(n, signer)) return;
      if (ts.isCallExpression(n) && ts.isIdentifier(n.expression) && n.expression.text === "macOf") macCalls.push(n);
      // Any assignment (plain, compound, or destructuring) whose target names the key.
      if (ts.isBinaryExpression(n) && n.operatorToken.kind >= ts.SyntaxKind.FirstAssignment && n.operatorToken.kind <= ts.SyntaxKind.LastAssignment) {
        for (const id of namesIn(n.left)) writes.push(`assigned ${where(id)}`);
      }
      if ((ts.isForOfStatement(n) || ts.isForInStatement(n)) && !ts.isVariableDeclarationList(n.initializer)) {
        for (const id of namesIn(n.initializer)) writes.push(`loop target ${where(id)}`);
      }
      if ((ts.isPrefixUnaryExpression(n) || ts.isPostfixUnaryExpression(n)) && namesIn(n.operand).length > 0) writes.push(`updated ${where(n)}`);
      if (ts.isIdentifier(n) && n.text === keyName && isDeclName(n) && n.parent !== param) writes.push(`shadowed ${where(n)}`);
    });
    expect(writes).toEqual([]);
    expect(macCalls).toHaveLength(1);
    const [keyArg, inputArg] = macCalls[0].arguments;
    expect(macCalls[0].arguments).toHaveLength(2);
    expect(ts.isIdentifier(keyArg) && keyArg.text === keyName).toBe(true);
    expect(ts.isCallExpression(inputArg) && ts.isIdentifier(inputArg.expression) && inputArg.expression.text === "buildHelloMacInput").toBe(true);
  });

  it("(g) macOf, buildHelloMacInput and HELLO_DOMAIN are referenced only at their pinned sites (no value use leaks them)", () => {
    const signer = fnDecl("signProxyHello");
    const verifier = fnDecl("verifyProxyHello");
    const builder = fnDecl("buildHelloMacInput");
    const refs = new Map<string, string[]>([
      ["macOf", []],
      ["buildHelloMacInput", []],
      ["HELLO_DOMAIN", []],
    ]);
    const decls = new Map<string, number>();
    forEachNode((n) => {
      if (!ts.isIdentifier(n) || !refs.has(n.text)) return;
      if (isDeclName(n)) {
        decls.set(n.text, (decls.get(n.text) ?? 0) + 1);
        return;
      }
      const fn = within(n, signer) ? "signer" : within(n, verifier) ? "verifier" : within(n, builder) ? "builder" : "module";
      const p = n.parent;
      const kind =
        ts.isCallExpression(p) && p.expression === n
          ? "call"
          : ts.isBinaryExpression(p) && p.left === n && p.operatorToken.kind === ts.SyntaxKind.PlusToken
            ? "concat"
            : `value ${where(n)}`;
      refs.get(n.text)!.push(`${fn}:${kind}`);
    });
    // Each name is declared once (no shadow, no second binding).
    expect(Object.fromEntries(decls)).toEqual({ macOf: 1, buildHelloMacInput: 1, HELLO_DOMAIN: 1 });
    expect(refs.get("macOf")).toEqual(["signer:call", "verifier:call", "verifier:call"]);
    expect(refs.get("buildHelloMacInput")).toEqual(["signer:call", "verifier:call"]);
    expect(refs.get("HELLO_DOMAIN")).toEqual(["builder:concat"]);
  });
});
