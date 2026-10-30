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

/**
 * Derived by CONTENT, not by a hand-kept list: every server file that imports `checkGrant` reads grants, so the exported
 * builder in it (the exported `build*` function) and the options interface it takes are the subject. A fourth
 * grant-reading builder is therefore covered the day it is written, without anyone remembering to list it here.
 */
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
    // The options interface is found by CONTENT too (the interface in this file that declares a `grants` member, optional or
    // not), never read back from the builder's own parameter: the "takes its options as <iface>" check below must be able to
    // fail when the parameter type is changed.
    const iface = sf.statements.find(
      (st): st is ts.InterfaceDeclaration =>
        ts.isInterfaceDeclaration(st) && st.members.some((m) => ts.isPropertySignature(m) && m.name.getText() === "grants"),
    );
    for (const f of fns) out.push({ file: relative(SERVER, full), fn: f.name!.text, iface: iface?.name.text ?? "" });
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
  it(`finds at least ${BUILDERS_FLOOR} grant-reading builders and the three known ones among them`, () => {
    expect(BUILDERS.length).toBeGreaterThanOrEqual(BUILDERS_FLOOR);
    expect(BUILDERS.map((b) => b.fn).sort()).toEqual(expect.arrayContaining(["buildGithubTools", "buildKbShareTools", "buildWorkspaceSettingsTools"]));
    for (const b of BUILDERS) expect(b.iface, `${b.fn} in ${b.file} must take a named options interface`).toMatch(/^[A-Z]\w+$/);
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
    const member = decl!.members.find((m): m is ts.PropertySignature => ts.isPropertySignature(m) && m.name.getText() === "grants");
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

  it("the check is not vacuous: an optional `grants?` is seen as optional by the same reader", () => {
    const sf = ts.createSourceFile("x.ts", "interface O { grants?: ExecutionGrants }", ts.ScriptTarget.Latest, true);
    const decl = sf.statements[0] as ts.InterfaceDeclaration;
    const member = decl.members[0] as ts.PropertySignature;
    expect(member.questionToken).toBeDefined();
  });
});
