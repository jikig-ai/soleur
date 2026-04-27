// Drift-guard for `buildAgentSandboxConfig` — the helper extracted from
// the prior inline `sandbox: {...}` block at the `agent-runner.ts`
// `query({ options })` call site. Two consumers (legacy domain-leader
// runner + cc-soleur-go `realSdkQueryFactory`) MUST receive an
// identical shape. If a field is silently dropped here, both consumers
// regress to a wider sandbox profile in prod.
//
// Per plan T17 / AC3: assert verbatim deep-equality vs the canonical
// literal. Test uses `toEqual` (not `toBe`) — readonly-object identity
// differs across calls.
//
// See learning `2026-04-19-claude-agent-sdk-subprocess-exit-tag-via-stderr-substring.md`
// for the helper-extraction risk class addressed by this test.

import { describe, it, expect } from "vitest";

import { buildAgentSandboxConfig } from "@/server/agent-runner-sandbox-config";

describe("buildAgentSandboxConfig drift guard", () => {
  it("matches the canonical inline shape verbatim (T17)", () => {
    const workspacePath = "/tmp/test-workspace";
    const result = buildAgentSandboxConfig(workspacePath);

    // Verbatim copy of the literal that lived at the prior
    // `agent-runner.ts` `query({ options: { sandbox: ... } })` call site.
    // A field drop in the helper trips this assertion.
    expect(result).toEqual({
      enabled: true,
      failIfUnavailable: true,
      autoAllowBashIfSandboxed: true,
      allowUnsandboxedCommands: false,
      enableWeakerNestedSandbox: true,
      network: {
        allowedDomains: [],
        allowManagedDomainsOnly: true,
      },
      filesystem: {
        allowWrite: [workspacePath],
        denyRead: ["/workspaces", "/proc"],
      },
    });
  });

  it("threads the workspacePath into filesystem.allowWrite (per-user write isolation)", () => {
    const result = buildAgentSandboxConfig("/workspaces/alice");
    expect(result.filesystem.allowWrite).toEqual(["/workspaces/alice"]);
  });

  it("filesystem.denyRead is constant across workspaces", () => {
    const a = buildAgentSandboxConfig("/workspaces/alice");
    const b = buildAgentSandboxConfig("/workspaces/bob");
    expect(a.filesystem.denyRead).toEqual(b.filesystem.denyRead);
    expect(a.filesystem.denyRead).toEqual(["/workspaces", "/proc"]);
  });

  it("network is locked down — no allowed domains, managed-only", () => {
    const result = buildAgentSandboxConfig("/tmp/x");
    expect(result.network.allowedDomains).toEqual([]);
    expect(result.network.allowManagedDomainsOnly).toBe(true);
  });
});
