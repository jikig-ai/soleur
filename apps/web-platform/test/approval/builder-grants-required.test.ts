/**
 * #4672 (ADR-309), round-2 Q4: `grants` is a REQUIRED option of the three grant-reading tool builders.
 *
 * A builder that took `grants?` would let a forgotten wiring compile and silently behave as "the approval flow never ran"
 * (legacy path): the gate would mark ITS grants object enforcing while the handler consulted nothing. The runtime cannot
 * see a missing type constraint, so this reads each builder's options interface with the TypeScript compiler API (parse
 * only, no program) and requires the `grants` member to exist, to be non-optional and to be typed `ExecutionGrants`, and
 * the exported builder to take that interface. Complements the runner census (which pins that agent-runner passes the
 * shared object).
 *
 * Does NOT prove: that callers outside agent-runner pass the right object (tests and probes pass an explicit instance).
 */
import { readdirSync, readFileSync } from "node:fs";
import { relative, resolve } from "node:path";
import ts from "typescript";
import { describe, expect, it } from "vitest";

const SERVER = resolve(__dirname, "../../server");

/** The least number of grant-reading builders that exist today; a census that finds fewer has stopped seeing them. */
const BUILDERS_FLOOR = 3;

function listTs(dir: string): string[] {
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    const full = resolve(dir, e.name);
    if (e.isDirectory()) return listTs(full);
    return e.isFile() && e.name.endsWith(".ts") ? [full] : [];
  });
}

/** True when the parsed file imports `checkGrant` by name (a real import, not a mention in a comment or string). */
function importsCheckGrant(sf: ts.SourceFile): boolean {
  return sf.statements.some(
    (st) =>
      ts.isImportDeclaration(st) &&
      st.importClause?.namedBindings !== undefined &&
      ts.isNamedImports(st.importClause.namedBindings) &&
      st.importClause.namedBindings.elements.some((el) => (el.propertyName ?? el.name).text === "checkGrant"),
  );
}

/** A member's NAME as the property key it declares: an identifier, a quoted key (`"grants": ...`) or a computed string key (`["grants"]`). */
function memberName(m: ts.TypeElement): string {
  const n = m.name;
  if (n === undefined) return "";
  if (ts.isIdentifier(n) || ts.isStringLiteral(n) || ts.isNoSubstitutionTemplateLiteral(n)) return n.text;
  if (ts.isComputedPropertyName(n) && (ts.isStringLiteral(n.expression) || ts.isNoSubstitutionTemplateLiteral(n.expression))) return n.expression.text;
  return n.getText();
}

/** Every interface in the parsed file that declares a `grants` member (optional or not). */
function grantsInterfaces(sf: ts.SourceFile): ts.InterfaceDeclaration[] {
  return sf.statements.filter(
    (st): st is ts.InterfaceDeclaration =>
      ts.isInterfaceDeclaration(st) && st.members.some((m) => ts.isPropertySignature(m) && memberName(m) === "grants"),
  );
}

/** `buildFooTools` -> `BuildFooToolsOpts`: the options interface a builder is paired with (CTO Fork 7, #11636). */
function optsNameFor(fn: string): string {
  return `${fn.charAt(0).toUpperCase()}${fn.slice(1)}Opts`;
}

/**
 * Derived by CONTENT, not by a hand-kept list: every server file that imports `checkGrant` reads grants, so the exported
 * builders in it (the exported `build*` functions) and the options interfaces they take are the subject. A fourth
 * grant-reading builder is therefore covered the day it is written, without anyone remembering to list it here.
 *
 * Pairing (#11636): a file can hold more than one builder (github-tools.ts has `buildGithubTools` and
 * `buildGithubPushBranchTool`), so each builder is paired with the grants-declaring interface NAMED after it
 * (`Build<Rest>Opts`); a file whose builder has no such interface but declares exactly one grants interface keeps the older
 * one-interface pairing. The options interface is still found by CONTENT (it must declare `grants`), never read back from
 * the builder's own parameter: the "takes its options as <iface>" check below must be able to fail when the parameter type
 * is changed.
 */
/**
 * Exported `build*` functions that live in a grant-importing file but read NO grants by design (#12469): the six read-only
 * GitHub tools. They take no `grants` option and cannot write, so the requirement does not apply; the test below proves each
 * one is really grant-free (its options interface declares no `grants` and no `requireGrant`), so this list cannot become a
 * way to hide a grant-reading builder.
 */
const GRANT_FREE_READ_BUILDERS: ReadonlySet<string> = new Set(["github-tools.ts#buildGithubReadTools"]);

function deriveBuilders(): Array<{ file: string; fn: string; iface: string }> {
  const out: Array<{ file: string; fn: string; iface: string }> = [];
  for (const full of listTs(SERVER)) {
    const sf = ts.createSourceFile(full, readFileSync(full, "utf8"), ts.ScriptTarget.Latest, true);
    if (!importsCheckGrant(sf)) continue;
    const fns = sf.statements.filter(
      (st): st is ts.FunctionDeclaration =>
        ts.isFunctionDeclaration(st) &&
        st.name !== undefined &&
        st.name.text.startsWith("build") &&
        (ts.getCombinedModifierFlags(st) & ts.ModifierFlags.Export) !== 0,
    );
    const ifaces = grantsInterfaces(sf);
    for (const f of fns) {
      if (GRANT_FREE_READ_BUILDERS.has(`${relative(SERVER, full)}#${f.name!.text}`)) continue;
      const named = ifaces.find((i) => i.name.text === optsNameFor(f.name!.text));
      const iface = named ?? (ifaces.length === 1 ? ifaces[0] : undefined);
      out.push({ file: relative(SERVER, full), fn: f.name!.text, iface: iface?.name.text ?? "" });
    }
  }
  return out;
}

const BUILDERS = deriveBuilders();

function parse(file: string): ts.SourceFile {
  const path = resolve(SERVER, file);
  return ts.createSourceFile(path, readFileSync(path, "utf8"), ts.ScriptTarget.Latest, true);
}

function findInterface(sf: ts.SourceFile, name: string): ts.InterfaceDeclaration | undefined {
  return sf.statements.find((s): s is ts.InterfaceDeclaration => ts.isInterfaceDeclaration(s) && s.name.text === name);
}

function findFunction(sf: ts.SourceFile, name: string): ts.FunctionDeclaration | undefined {
  return sf.statements.find((s): s is ts.FunctionDeclaration => ts.isFunctionDeclaration(s) && s.name?.text === name);
}

describe("the builder list is derived by content, with a floor", () => {
  it(`finds at least ${BUILDERS_FLOOR} grant-reading builders and the three known ones among them, plus the cc push builder`, () => {
    expect(BUILDERS.length).toBeGreaterThanOrEqual(BUILDERS_FLOOR);
    expect(BUILDERS.map((b) => b.fn).sort()).toEqual(
      expect.arrayContaining(["buildGithubPushBranchTool", "buildGithubTools", "buildKbShareTools", "buildWorkspaceSettingsTools"]),
    );
    for (const b of BUILDERS) expect(b.iface, `${b.fn} in ${b.file} must take a named options interface`).toMatch(/^[A-Z]\w+$/);
  });

  it("memberName reads a quoted or computed key as the name it declares (a `\"grants\": unknown` member cannot hide)", () => {
    const sf = ts.createSourceFile("x.ts", 'interface I { "grants": unknown; ["requireGrant"]: boolean; plain: 1 }', ts.ScriptTarget.Latest, true);
    const i = sf.statements[0] as ts.InterfaceDeclaration;
    expect(i.members.map(memberName)).toEqual(["grants", "requireGrant", "plain"]);
  });

  it("the content reader sees an import of checkGrant and ignores a comment or string that merely mentions it", () => {
    const parseText = (t: string) => ts.createSourceFile("x.ts", t, ts.ScriptTarget.Latest, true);
    expect(importsCheckGrant(parseText('import { checkGrant, ExecutionGrants } from "@/server/approval/grants";'))).toBe(true);
    expect(importsCheckGrant(parseText('import { checkGrant as cg } from "./approval/grants";'))).toBe(true);
    expect(importsCheckGrant(parseText('// import { checkGrant } from "x";\nconst s = "checkGrant";'))).toBe(false);
    expect(importsCheckGrant(parseText('import { ExecutionGrants } from "@/server/approval/grants";'))).toBe(false);
  });
});

describe("grants is a REQUIRED option of every grant-reading tool builder", () => {
  it.each(BUILDERS)("$fn: the options interface $iface has a non-optional `grants: ExecutionGrants`", ({ file, iface }) => {
    const decl = findInterface(parse(file), iface);
    expect(decl, `${iface} not found in ${file}`).toBeDefined();
    const member = decl!.members.find((m): m is ts.PropertySignature => ts.isPropertySignature(m) && memberName(m) === "grants");
    expect(member, `${iface} has no \`grants\` member`).toBeDefined();
    expect(member!.questionToken, `${iface}.grants must not be optional`).toBeUndefined();
    expect(member!.type?.getText()).toBe("ExecutionGrants");
  });

  it.each(BUILDERS)("$fn takes its options as $iface (so the requirement binds the exported builder)", ({ file, fn, iface }) => {
    const decl = findFunction(parse(file), fn);
    expect(decl, `${fn} not found in ${file}`).toBeDefined();
    expect(decl!.parameters.length).toBeGreaterThanOrEqual(1);
    expect(decl!.parameters[0].type?.getText()).toBe(iface);
  });

  it("every interface that declares `grants` is some builder's options interface (a second interface cannot hide from the pairing)", () => {
    const paired = new Set(BUILDERS.map((b) => `${b.file}#${b.iface}`));
    const unpaired: string[] = [];
    for (const full of listTs(SERVER)) {
      const sf = ts.createSourceFile(full, readFileSync(full, "utf8"), ts.ScriptTarget.Latest, true);
      if (!importsCheckGrant(sf)) continue;
      for (const i of grantsInterfaces(sf)) if (!paired.has(`${relative(SERVER, full)}#${i.name.text}`)) unpaired.push(`${relative(SERVER, full)}#${i.name.text}`);
    }
    expect(unpaired).toEqual([]);
  });

  it("a file with two builders pairs each with its OWN options interface (the pairing is by name, not first-match)", () => {
    const pair = Object.fromEntries(BUILDERS.filter((b) => b.file === "github-tools.ts").map((b) => [b.fn, b.iface]));
    expect(pair).toEqual({
      buildGithubTools: "BuildGithubToolsOpts",
      buildGithubPushBranchTool: "BuildGithubPushBranchToolOpts",
    });
  });

  it("every grant-free read builder is really grant-free (its options interface declares no `grants` and no `requireGrant`)", () => {
    for (const key of GRANT_FREE_READ_BUILDERS) {
      const [file, fn] = key.split("#");
      const sf = parse(file);
      const decl = findFunction(sf, fn);
      expect(decl, `${fn} not found in github-tools.ts`).toBeDefined();
      const ifaceName = decl!.parameters[0].type?.getText() ?? "";
      const iface = findInterface(sf, ifaceName);
      expect(iface, `${ifaceName} not found`).toBeDefined();
      // Walk the whole `extends` chain: an inherited `grants`/`requireGrant` would be invisible to an own-members check. The only
      // base permitted is another interface in this file, and it is held to the same rule.
      const seen = new Set<string>();
      const check = (name: string): void => {
        expect(seen.has(name), `${name}: cyclic heritage`).toBe(false);
        seen.add(name);
        const i = findInterface(sf, name);
        expect(i, `${name} not found in ${file}`).toBeDefined();
        const names = i!.members.filter((m): m is ts.PropertySignature => ts.isPropertySignature(m)).map((m) => memberName(m));
        expect(names, `${name} must not declare grants`).not.toContain("grants");
        expect(names, `${name} must not declare requireGrant`).not.toContain("requireGrant");
        for (const hc of i!.heritageClauses ?? []) for (const t of hc.types) check(t.expression.getText());
      };
      check(ifaceName);
    }
  });

  it("the cc push builder takes a REQUIRED boolean `requireGrant` (a forgotten wiring does not compile)", () => {
    const decl = findInterface(parse("github-tools.ts"), "BuildGithubPushBranchToolOpts");
    expect(decl, "BuildGithubPushBranchToolOpts not found in github-tools.ts").toBeDefined();
    const member = decl!.members.find((m): m is ts.PropertySignature => ts.isPropertySignature(m) && memberName(m) === "requireGrant");
    expect(member, "BuildGithubPushBranchToolOpts has no `requireGrant` member").toBeDefined();
    expect(member!.questionToken, "requireGrant must not be optional").toBeUndefined();
    expect(member!.type?.getText()).toBe("boolean");
  });

  it("the check is not vacuous: an optional `grants?` is seen as optional by the same reader", () => {
    const sf = ts.createSourceFile("x.ts", "interface O { grants?: ExecutionGrants }", ts.ScriptTarget.Latest, true);
    const decl = sf.statements[0] as ts.InterfaceDeclaration;
    const member = decl.members[0] as ts.PropertySignature;
    expect(member.questionToken).toBeDefined();
  });
});
