/**
 * Guard 2, runner dimension (#4672): the slice-1 tools are registered by exactly one runner today, and that runner wires
 * the approval dependency. A second runner that starts registering a slice-1 tool must wire it too (or record a reason
 * here), otherwise its gated branch silently stays on the in-memory path.
 *
 * The cc-soleur-go runner (cc-dispatcher.ts) registers exactly ONE of the eight slice-1 tools (#11636): `github_push_branch`,
 * through the gated registrar in cc-github-push.ts (flag, entitlement, persona, repo, installation; strict `requireGrant`
 * handler), never by naming it in cc-dispatcher.ts. Its `platformToolNames` is the c4 edit tool, the CRM lead tools and that
 * one registrar-derived name. It carries the approval wiring (ONE per-Query ExecutionGrants handed to BOTH the gate
 * dependency and the registrar, and the `approvalFailClosed` switch), so any other required tool registered there later is
 * denied, never answered from the in-memory card. The presence pins below read code (comments stripped); the real-factory
 * test in cc-dispatcher-real-factory.test.ts proves the live deps object carries the same values.
 */
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, test } from "vitest";
import { APPROVAL_REQUIRED_TOOLS } from "@/server/approval/tools";
import { stripComments } from "./source-scan";

const ROOT = join(__dirname, "../..");
/** Source with comments removed: every regex below must match CODE (a comment naming the wiring must not satisfy it). */
const src = (rel: string) => stripComments(readFileSync(join(ROOT, rel), "utf8"));
const SHORT = APPROVAL_REQUIRED_TOOLS.map((t) => t.replace("mcp__soleur_platform__", ""));
/** The wired grants argument: the identifier must END at `approvalGrants` (a different object named `approvalGrantsB` must not pass). */
const GRANTS_ARG = /grants:\s*approvalGrants\s*[,}]/;
/** The cc registration pattern: a quoted short name, or a quoted fully-qualified literal. Shared by the census and its self-test. */
const ccRegistrationRe = (name: string) => new RegExp(`["'\`](?:mcp__soleur_platform__)?${name}["'\`]`);
const BUILDERS = ["email-triage-tools", "github-tools", "kb-share-tools", "workspace-settings-tools"];

function createCanUseToolBlock(file: string): string {
  const text = src(file);
  const i = text.indexOf("createCanUseTool({");
  expect(i, `${file} calls createCanUseTool`).toBeGreaterThan(-1);
  return text.slice(i, i + 4000);
}

describe("runner registration census", () => {
  test("the legacy runner wires the approval dependency into its canUseTool deps", () => {
    const block = createCanUseToolBlock("server/agent-runner.ts");
    expect(block).toMatch(/approval:\s*createApprovalGateDeps\(/);
    expect(block).toMatch(/workspaceId:\s*activeWorkspaceId/);
  });

  test("the legacy runner creates ONE per-session ExecutionGrants and hands the same object to the gate and the three grant-reading builders (ADR-309 ExecutionGrants)", () => {
    const runner = src("server/agent-runner.ts");
    expect(runner.match(/new ExecutionGrants\(\)/g)).toHaveLength(1);
    const block = createCanUseToolBlock("server/agent-runner.ts");
    expect(block).toMatch(new RegExp(String.raw`createApprovalGateDeps\(\{[\s\S]{0,600}?` + GRANTS_ARG.source));
    expect(runner).toMatch(new RegExp(String.raw`buildGithubTools\(\{[^}]*` + GRANTS_ARG.source, 's'));
    expect(runner).toMatch(new RegExp(String.raw`buildKbShareTools\(\{[^}]*` + GRANTS_ARG.source, 's'));
    expect(runner).toMatch(new RegExp(String.raw`buildWorkspaceSettingsTools\(\{[^}]*` + GRANTS_ARG.source, 's'));
  });

  test("the cc runner constructs exactly ONE ExecutionGrants and hands that same identifier to createApprovalGateDeps AND to the push registrar", () => {
    const cc = src("server/cc-dispatcher.ts");
    expect(cc.match(/new ExecutionGrants\(\)/g)).toHaveLength(1);
    const bound = /const\s+(\w+)\s*=\s*new ExecutionGrants\(\)/.exec(cc);
    expect(bound, "the construction is bound to a const").not.toBeNull();
    const passed = /createApprovalGateDeps\(\{[\s\S]{0,600}?grants:\s*(\w+)\s*[,}]/.exec(cc);
    expect(passed, "createApprovalGateDeps receives a grants argument").not.toBeNull();
    expect(passed?.[1]).toBe(bound?.[1]);
    // The registrar gets the SAME object (a fresh one would leave the gate marking one object enforcing while the handler consults another).
    const registrar = /resolveCcGithubPushRegistration\(\{[\s\S]{0,900}?grants:\s*(\w+)\s*[,}]/.exec(cc);
    expect(registrar, "resolveCcGithubPushRegistration receives a grants argument").not.toBeNull();
    expect(registrar?.[1]).toBe(bound?.[1]);
  });

  test("the grants object is constructed BEFORE the tool build (hoisted above the registrar call, which needs it)", () => {
    const cc = src("server/cc-dispatcher.ts");
    const built = cc.search(/const\s+approvalGrants\s*=\s*new ExecutionGrants\(\)/);
    const registrarAt = cc.search(/resolveCcGithubPushRegistration\(\{/);
    const serverAt = cc.search(/const\s+c4McpServers\s*=/);
    expect(built).toBeGreaterThan(-1);
    expect(registrarAt).toBeGreaterThan(-1);
    expect(built).toBeLessThan(registrarAt);
    expect(built).toBeLessThan(serverAt);
  });

  test("the cc runner wires the approval dependency and sets the fail-closed switch in its canUseTool deps", () => {
    const cc = src("server/cc-dispatcher.ts");
    expect(cc).toMatch(/approval:\s*createApprovalGateDeps\(/);
    expect(cc).toMatch(/approvalFailClosed:\s*true/);
  });

  test("the cc runner names no slice-1 tool and imports none of the builder modules; it reaches the one push tool only through ./cc-github-push", () => {
    const cc = src("server/cc-dispatcher.ts");
    for (const name of SHORT) expect(cc, `cc-dispatcher registers ${name} without approval wiring`).not.toMatch(ccRegistrationRe(name));
    for (const b of BUILDERS) expect(cc, `cc-dispatcher imports ${b}`).not.toMatch(new RegExp(`/${b}["']`));
    expect(cc).toMatch(/from\s+["']\.\/cc-github-push["']/);
  });

  test("no non-test module under server/ other than github-tools.ts and cc-github-push.ts mentions buildGithubPushBranchTool (importer set derived, not a name list)", () => {
    // A filesystem walk, not `git ls-files`: the mutation battery runs this file against a copy of the app tree that has no git.
    const walk = (dir: string): string[] =>
      readdirSync(join(ROOT, dir), { withFileTypes: true }).flatMap((e) =>
        e.isDirectory() ? walk(`${dir}/${e.name}`) : /\.tsx?$/.test(e.name) ? [`${dir}/${e.name}`] : [],
      );
    const tracked = walk("server");
    expect(tracked.length, "the derivation is non-vacuous").toBeGreaterThan(100);
    const users = tracked.filter((f) => /\bbuildGithubPushBranchTool\b/.test(src(f))).sort();
    expect(users).toEqual(["server/cc-github-push.ts", "server/github-tools.ts"]);
  });

  test("the warm-path mirror consults the factory-published registered set, and canUseTool's platform list takes the registrar's names only", () => {
    const cc = src("server/cc-dispatcher.ts");
    expect(cc).toMatch(/shouldMirrorUnregisteredPlatformToolUse\(block\.name,\s*\[[^\]]*getCcRegisteredApprovalTools\(userId,\s*conversationId\)/);
    // The list handed to createCanUseTool spreads the registrar-derived names (a separate re-resolve would drift from the build).
    expect(cc).toMatch(/platformToolNames:\s*\[[\s\S]{0,400}?\.\.\.approvalToolNames/);
    expect(cc).toMatch(/approvalToolNames\s*=\s*pushRegistration\.toolNames/);
  });

  test("the workspace id the gate and the tool closure share is bound ONCE and never reassigned (a mid-Query switch cannot split them)", () => {
    const cc = src("server/cc-dispatcher.ts");
    expect(cc.match(/\bconst\s+activeWorkspaceId\s*=/g)).toHaveLength(1);
    // Every assignment-shaped occurrence is that one declaration: a `let` re-declaration or a later `activeWorkspaceId = ...` adds one.
    expect(cc.match(/\bactiveWorkspaceId\s*=(?!=)/g)).toHaveLength(1);
  });

  test("the census is not vacuous: the legacy runner does register the slice-1 builders", () => {
    const runner = src("server/agent-runner.ts");
    const registered = BUILDERS.filter((b) => new RegExp(`/${b}["']`).test(runner));
    expect(registered.length).toBeGreaterThan(0);
  });
});

describe("self-test: the census regexes see code, not comments (mutation list)", () => {
  test("the grants argument must end at approvalGrants: a longer identifier, or another object, fails it", () => {
    expect(GRANTS_ARG.test("buildGithubTools({ userId, grants: approvalGrants })")).toBe(true);
    expect(GRANTS_ARG.test("buildGithubTools({ grants: approvalGrants, userId })")).toBe(true);
    expect(GRANTS_ARG.test("buildGithubTools({ userId, grants: approvalGrantsB })")).toBe(false);
    expect(GRANTS_ARG.test("buildGithubTools({ userId, grants: approvalGrantsB, x })")).toBe(false);
    expect(new RegExp(String.raw`buildGithubTools\(\{[^}]*` + GRANTS_ARG.source, "s").test("buildGithubTools({ userId, grants: approvalGrantsB })")).toBe(false);
  });

  const WIRED = `createCanUseTool({ deps: { approval: createApprovalGateDeps({ grants: approvalGrants }), workspaceId: activeWorkspaceId } })`;
  const wired = (text: string) => /approval:\s*createApprovalGateDeps\(/.test(stripComments(text));

  test("the real wiring is seen", () => {
    expect(wired(WIRED)).toBe(true);
  });

  test("wiring that exists only in a line or block comment is NOT seen (deleting the real wiring turns the census red)", () => {
    expect(wired(`createCanUseTool({ deps: {} });\n// approval: createApprovalGateDeps({ grants: approvalGrants })`)).toBe(false);
    expect(wired(`createCanUseTool({ deps: {} });\n/* approval: createApprovalGateDeps( */`)).toBe(false);
    expect(wired(`createCanUseTool({ deps: {} }); /**\n * approval: createApprovalGateDeps(\n */`)).toBe(false);
  });

  test("the grants pins see code, not comments: wiring only in a comment is NOT seen", () => {
    const construct = (text: string) => stripComments(text).match(/new ExecutionGrants\(\)/g)?.length ?? 0;
    expect(construct(`const g = new ExecutionGrants();`)).toBe(1);
    expect(construct(`// const g = new ExecutionGrants();\nconst x = 1;`)).toBe(0);
    expect(construct(`const a = new ExecutionGrants();\nconst b = new ExecutionGrants();`)).toBe(2);
    const switchSet = (text: string) => /approvalFailClosed:\s*true/.test(stripComments(text));
    expect(switchSet(`const d = { approvalFailClosed: true };`)).toBe(true);
    expect(switchSet(`// approvalFailClosed: true\nconst d = {};`)).toBe(false);
  });

  test("the cc registration regex flags a quoted short name or fully-qualified literal, and not an unrelated or other-prefix string", () => {
    const re = ccRegistrationRe;
    expect(re("github_push_branch").test('const a = "github_push_branch";')).toBe(true);
    expect(re("github_push_branch").test('const a = "mcp__soleur_platform__github_push_branch";')).toBe(true);
    expect(re("github_push_branch").test('const a = "mcp__other__github_push_branch";')).toBe(false);
    expect(re("github_push_branch").test("const a = 'not_github_push_branch_x';")).toBe(false);
    // Composed names (a prefix constant plus interpolation) are NOT seen here; the derived sweep in tools-census.test.ts is the control.
  });

  test("the activeWorkspaceId pin has a mutant: `let` instead of `const`, or a reassignment, turns it red", () => {
    const constDecl = (t: string) => stripComments(t).match(/\bconst\s+activeWorkspaceId\s*=/g)?.length ?? 0;
    const assigns = (t: string) => stripComments(t).match(/\bactiveWorkspaceId\s*=(?!=)/g)?.length ?? 0;
    const good = "const activeWorkspaceId = ws.id;\nuse(activeWorkspaceId);";
    expect([constDecl(good), assigns(good)]).toEqual([1, 1]);
    const letMutant = good.replace("const", "let");
    expect(constDecl(letMutant)).toBe(0);
    const reassigned = `${good}\nactiveWorkspaceId = other.id;`;
    expect(assigns(reassigned)).toBe(2);
    expect(assigns("const activeWorkspaceId = ws.id; // activeWorkspaceId = 1")).toBe(1);
  });

  test("a URL with // inside a string literal is code and survives", () => {
    expect(stripComments(`const u = "https://a/b"; // trailing`)).toContain('"https://a/b"');
  });
});

