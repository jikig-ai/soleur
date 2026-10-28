import { describe, expect, it, vi } from "vitest";
import { z } from "zod/v4";

// Phase 0.3 (#4672): the canonical field lists are CONFIRMED against each tool's real zod schema, not retyped.
// The tool builders are run with `tool()` stubbed to capture the zod shape each tool registers with the SDK;
// the shape's keys must equal the fixture's field list, and the real zod parse of a full sample must agree
// with the canonical object field-for-field (so a new field or a changed default in a tool cannot slip past
// the hash).

const captured = vi.hoisted(() => ({ shapes: {} as Record<string, Record<string, unknown>> }));

vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  tool: (name: string, description: string, shape: Record<string, unknown>, handler: unknown) => {
    captured.shapes[name] = shape;
    return { name, description, shape, handler };
  },
  createSdkMcpServer: vi.fn(),
}));
vi.mock("@/lib/supabase/tenant", () => ({ getFreshTenantClient: vi.fn() }));
vi.mock("@/server/observability", () => ({ reportSilentFallback: vi.fn(), warnSilentFallback: vi.fn() }));
vi.mock("@/server/email-triage/outbound", () => ({ sendCompliantOutbound: vi.fn() }));
vi.mock("@/server/github-app", () => ({ createPullRequest: vi.fn(), createIssue: vi.fn() }));
vi.mock("@/server/ci-tools", () => ({ readCiStatus: vi.fn(), readWorkflowLogs: vi.fn() }));
vi.mock("@/server/github-read-tools", () => ({
  readIssue: vi.fn(),
  readIssueComments: vi.fn(),
  readPullRequest: vi.fn(),
  listPullRequestComments: vi.fn(),
}));
vi.mock("@/server/trigger-workflow", () => ({ triggerWorkflow: vi.fn() }));
vi.mock("@/server/push-branch", () => ({ pushBranch: vi.fn() }));
vi.mock("@/server/resolve-bash-autonomous", () => ({ resolveBashAutonomous: vi.fn() }));
vi.mock("@/server/set-bash-autonomous", () => ({ setBashAutonomous: vi.fn() }));

import { buildEmailTriageTools } from "@/server/email-triage-tools";
import { buildGithubTools } from "@/server/github-tools";
import { buildKbShareTools } from "@/server/kb-share-tools";
import { buildWorkspaceSettingsTools } from "@/server/workspace-settings-tools";
import { canonicalizeAction } from "@/server/approval/canonical";
import { FIELD_LISTS, SAMPLES, USER_ID } from "./fixtures";

buildEmailTriageTools({ userId: USER_ID });
buildGithubTools({
  installationId: 1,
  owner: "example-org",
  repo: "example-repo",
  defaultBranch: "main",
  workspacePath: "/tmp/none",
  workflowRateLimiter: {} as never,
});
buildKbShareTools({ serviceClient: {} as never, userId: USER_ID, kbRoot: "/tmp/none", baseUrl: "https://example.test" });
buildWorkspaceSettingsTools({ userId: USER_ID });

const SHORT = (fq: string) => fq.replace("mcp__soleur_platform__", "");

describe("canonical field lists match the real tool schemas", () => {
  for (const tool of Object.keys(FIELD_LISTS)) {
    describe(tool, () => {
      const shape = captured.shapes[SHORT(tool)];

      it("the tool registers a zod shape", () => {
        expect(shape, `tool ${SHORT(tool)} not captured`).toBeTruthy();
      });

      it("the shape keys are exactly the fixture's input field list", () => {
        expect(Object.keys(shape ?? {}).sort()).toEqual([...FIELD_LISTS[tool].input].sort());
      });

      it("the real zod parse of the full sample equals the canonical input fields (defaults included)", () => {
        const parsed = z.object(shape as z.ZodRawShape).parse(SAMPLES[tool].input) as Record<string, unknown>;
        const fields = canonicalizeAction(tool, SAMPLES[tool].input, SAMPLES[tool].server).fields as Record<string, unknown>;
        const inputPart = Object.fromEntries(Object.entries(fields).filter(([k]) => FIELD_LISTS[tool].input.includes(k)));
        const clean = Object.fromEntries(Object.entries(parsed).filter(([, v]) => v !== undefined));
        expect(inputPart).toEqual(clean);
      });

      it("the zod defaults the handler applies are the ones the fixture records", () => {
        const minimal = structuredClone(SAMPLES[tool].input);
        for (const k of Object.keys(FIELD_LISTS[tool].defaults)) delete minimal[k];
        const parsed = z.object(shape as z.ZodRawShape).parse(minimal) as Record<string, unknown>;
        for (const [k, v] of Object.entries(FIELD_LISTS[tool].defaults)) expect(parsed[k], `default ${k}`).toEqual(v);
      });
    });
  }
});
