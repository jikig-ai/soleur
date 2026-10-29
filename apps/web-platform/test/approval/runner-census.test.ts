/**
 * Guard 2, runner dimension (#4672): the slice-1 tools are registered by exactly one runner today, and that runner wires
 * the approval dependency. A second runner that starts registering a slice-1 tool must wire it too (or record a reason
 * here), otherwise its gated branch silently stays on the in-memory path.
 *
 * Why the cc-soleur-go runner (cc-dispatcher.ts) is out of slice 1: its `platformToolNames` is the c4 edit tool plus the
 * CRM lead tools. None of the eight slice-1 tools (email, GitHub write, kb share, workspace autonomy) is registered
 * there, so no approval can arise on that path until one is.
 */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, test } from "vitest";
import { APPROVAL_REQUIRED_TOOLS } from "@/server/approval/tools";
import { stripComments } from "./source-scan";

const ROOT = join(__dirname, "../..");
/** Source with comments removed: every regex below must match CODE (a comment naming the wiring must not satisfy it). */
const src = (rel: string) => stripComments(readFileSync(join(ROOT, rel), "utf8"));
const SHORT = APPROVAL_REQUIRED_TOOLS.map((t) => t.replace("mcp__soleur_platform__", ""));
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

  test("the legacy runner creates ONE per-session ExecutionGrants and hands the same object to the gate and the three grant-reading builders (ADR-307 ExecutionGrants)", () => {
    const runner = src("server/agent-runner.ts");
    expect(runner.match(/new ExecutionGrants\(\)/g)).toHaveLength(1);
    const block = createCanUseToolBlock("server/agent-runner.ts");
    expect(block).toMatch(/createApprovalGateDeps\(\{[\s\S]{0,600}?grants:\s*approvalGrants/);
    expect(runner).toMatch(/buildGithubTools\(\{[^}]*grants:\s*approvalGrants/s);
    expect(runner).toMatch(/buildKbShareTools\(\{[^}]*grants:\s*approvalGrants/s);
    expect(runner).toMatch(/buildWorkspaceSettingsTools\(\{[^}]*grants:\s*approvalGrants/s);
  });

  test("the cc runner never builds the approval gate dependency or the execution grants", () => {
    const cc = src("server/cc-dispatcher.ts");
    expect(cc).not.toMatch(/createApprovalGateDeps|ExecutionGrants/);
  });

  test("the cc runner registers no slice-1 tool and imports none of their builders (recorded reason above)", () => {
    const cc = src("server/cc-dispatcher.ts");
    for (const name of SHORT) expect(cc, `cc-dispatcher registers ${name} without approval wiring`).not.toMatch(new RegExp(`["'\`]${name}["'\`]`));
    for (const b of BUILDERS) expect(cc, `cc-dispatcher imports ${b}`).not.toMatch(new RegExp(`/${b}["']`));
  });

  test("the census is not vacuous: the legacy runner does register the slice-1 builders", () => {
    const runner = src("server/agent-runner.ts");
    const registered = BUILDERS.filter((b) => new RegExp(`/${b}["']`).test(runner));
    expect(registered.length).toBeGreaterThan(0);
  });
});

describe("self-test: the census regexes see code, not comments (mutation list)", () => {
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

  test("a forbidden name in a comment does not trip the cc-runner negative checks, in a string it still does", () => {
    const forbidden = (text: string) => /createApprovalGateDeps|ExecutionGrants/.test(stripComments(text));
    expect(forbidden(`// no ExecutionGrants here\nconst x = 1;`)).toBe(false);
    expect(forbidden(`const g = new ExecutionGrants();`)).toBe(true);
    expect(forbidden(`const s = "createApprovalGateDeps";`)).toBe(true);
  });

  test("a URL with // inside a string literal is code and survives", () => {
    expect(stripComments(`const u = "https://a/b"; // trailing`)).toContain('"https://a/b"');
  });
});

