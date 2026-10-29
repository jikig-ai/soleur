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

const ROOT = join(__dirname, "../..");
const src = (rel: string) => readFileSync(join(ROOT, rel), "utf8");
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

  test("the legacy runner creates ONE per-session ExecutionGrants and hands the same object to the gate and the three grant-reading builders (R1)", () => {
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
