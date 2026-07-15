// resolveWorkspaceMode — the single pure discriminant driving support's
// read-only, repo-gate-bypassed execution (CTO ruling, ADR-113, T1).
// Pure module, no app runtime.

import { describe, it, expect } from "vitest";

import {
  resolveWorkspaceMode,
  type Persona,
} from "@/server/workspace-mode";

describe("resolveWorkspaceMode", () => {
  it("command_center = full repo lifecycle, workspace cwd, workspace write", () => {
    const m = resolveWorkspaceMode("command_center");
    expect(m).toEqual({
      persona: "command_center",
      runRepoLifecycle: true,
      cwdSource: "workspace",
      sandboxWrite: "workspace",
    });
  });

  it("support = NO repo lifecycle, plugin cwd, NO write (the P1 read-only invariant)", () => {
    const m = resolveWorkspaceMode("support");
    expect(m).toEqual({
      persona: "support",
      runRepoLifecycle: false,
      cwdSource: "plugin",
      sandboxWrite: "none",
    });
  });

  it("impossible-state coupling: support can NEVER pair plugin cwd with a write-set", () => {
    const m = resolveWorkspaceMode("support");
    // The union binds cwd + write at construction — a docs cwd is always writeless.
    expect(m.cwdSource === "plugin" && m.sandboxWrite === "none").toBe(true);
    expect(m.runRepoLifecycle).toBe(false);
  });

  it("a garbage/cast persona THROWS (never falls through to the repo path)", () => {
    expect(() => resolveWorkspaceMode("attacker" as unknown as Persona)).toThrow();
  });
});
