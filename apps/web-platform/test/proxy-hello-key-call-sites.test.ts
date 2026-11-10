import { execFileSync } from "node:child_process";
import { lstatSync, readFileSync } from "node:fs";
import { extname, join } from "node:path";
import ts from "typescript";
import { describe, expect, it } from "vitest";

// #8211, ADR-323 Decision 9 (2026-11-10 amendment) — Guard 1 "the accept-only slot never signs", as structure rather
// than a call-site scan. Only proxy-hello.ts can build the MAC input: (a) the domain string exists nowhere else in the
// repo, so no other file can rebuild the canonical string; (b) the builder is module-private; (c) the module's export
// list is pinned, so nothing re-exports or aliases a signing path; (d) inside the module only the verifier reads
// `acceptAlso`. A second signer has to break one of the four. The behaviour rows (the sender signs with current only,
// the verifier accepts both, the listener needs current) live in session-proxy-hello.test.ts, proxy-hello.test.ts and
// proxy-hello-rotation-phases.test.ts.

const DOMAIN = "soleur-proxy-hello-v1";
const MODULE = "apps/web-platform/server/proxy-hello.ts";
const REPO = execFileSync("git", ["rev-parse", "--show-toplevel"], { cwd: __dirname, encoding: "utf8" }).trim();

// Tracked files plus untracked, not-ignored ones (a new file is caught before it is committed). Paths under any
// `test/` directory and under knowledge-base/ are out of scope: tests and prose quote the string on purpose.
const EXCLUDED = /(^|\/)test\/|(^|\/)knowledge-base\//;
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

describe("Guard 1 structure: the accept-only slot never signs (#8211)", () => {
  it("(a) positive control: the walk reads proxy-hello.ts and files of other types", () => {
    expect(scanned.length).toBeGreaterThan(1000);
    expect(scanned).toContain(MODULE);
    const exts = new Set(scanned.map((f) => extname(f)));
    for (const e of [".sh", ".mjs", ".yml", ".tf", ".json"]) expect(exts, e).toContain(e);
    // The same read finds a needle in a non-.ts file, so the content check is not blind outside TypeScript.
    expect(hits.get(SHEBANG)?.some((f) => f.endsWith(".sh"))).toBe(true);
  });

  it(`(a) the domain string "${DOMAIN}" appears only in proxy-hello.ts (any extension, tests and knowledge-base excluded)`, () => {
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
    // The builder exists and is module-private (b).
    const builder = SF.statements.find((s) => ts.isFunctionDeclaration(s) && s.name?.text === "buildHelloMacInput");
    expect(builder).toBeDefined();
    expect(hasModifier(builder as ts.Node, ts.SyntaxKind.ExportKeyword)).toBe(false);
  });

  it("(d) `acceptAlso` is read only inside verifyProxyHello (the HelloVerifyKeys member declaration aside)", () => {
    const verifier = SF.statements.find(
      (s): s is ts.FunctionDeclaration => ts.isFunctionDeclaration(s) && s.name?.text === "verifyProxyHello",
    );
    expect(verifier).toBeDefined();
    const [vStart, vEnd] = [verifier!.getStart(SF), verifier!.getEnd()];
    const outside: string[] = [];
    let readsInVerifier = 0;
    const visit = (n: ts.Node) => {
      const named =
        ((ts.isIdentifier(n) || ts.isPrivateIdentifier(n)) && n.text === "acceptAlso") ||
        ((ts.isStringLiteral(n) || ts.isNoSubstitutionTemplateLiteral(n)) && n.text === "acceptAlso");
      if (named) {
        const pos = n.getStart(SF);
        const isMemberDecl =
          ts.isPropertySignature(n.parent) &&
          n.parent.name === n &&
          ts.isInterfaceDeclaration(n.parent.parent) &&
          n.parent.parent.name.text === "HelloVerifyKeys";
        if (pos >= vStart && pos < vEnd) {
          if (ts.isPropertyAccessExpression(n.parent) && n.parent.name === n) readsInVerifier += 1;
        } else if (!isMemberDecl) {
          const { line } = SF.getLineAndCharacterOfPosition(pos);
          outside.push(`${line + 1}: ${n.parent.getText(SF).slice(0, 80)}`);
        }
      }
      ts.forEachChild(n, visit);
    };
    visit(SF);
    expect(outside).toEqual([]);
    expect(readsInVerifier).toBeGreaterThanOrEqual(1); // vacuity floor: the verifier does read the slot
  });
});
