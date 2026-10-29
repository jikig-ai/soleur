/**
 * #4672 (ADR-307), round-2 Q4: `grants` is a REQUIRED option of the three grant-reading tool builders.
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
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import ts from "typescript";
import { describe, expect, it } from "vitest";

const SERVER = resolve(__dirname, "../../server");

const BUILDERS = [
  { file: "github-tools.ts", fn: "buildGithubTools", iface: "BuildGithubToolsOpts" },
  { file: "kb-share-tools.ts", fn: "buildKbShareTools", iface: "BuildKbShareToolsOpts" },
  { file: "workspace-settings-tools.ts", fn: "buildWorkspaceSettingsTools", iface: "BuildWorkspaceSettingsToolsOpts" },
] as const;

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
