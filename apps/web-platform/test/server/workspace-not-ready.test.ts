import { describe, expect, it } from "vitest";
import {
  WorkspaceNotReadyError,
  WORKSPACE_DB_ERROR_MSG,
  noRepoSwitchMsg,
} from "@/server/workspace-not-ready";

describe("WorkspaceNotReadyError — dispatch-boundary not-ready states (ADR-044 PR-1)", () => {
  it("db-error → transient copy; carries no team id, no reconnect", () => {
    const err = new WorkspaceNotReadyError({ kind: "db-error" });
    expect(err.message).toBe(WORKSPACE_DB_ERROR_MSG);
    expect(err.message).toMatch(/try again/i);
    // Transient copy must NOT mention reconnect or switching.
    expect(err.message).not.toMatch(/reconnect/i);
    expect(err.message).not.toMatch(/switch/i);
    expect(err.name).toBe("WorkspaceNotReadyError");
  });

  it("no-repo-switch with a resolvable team name → names the team, says switch", () => {
    const team = "11111111-1111-1111-1111-111111111111";
    const err = new WorkspaceNotReadyError({
      kind: "no-repo-switch",
      targetTeamId: team,
      teamName: "Acme Eng",
    });
    expect(err.state.kind).toBe("no-repo-switch");
    if (err.state.kind === "no-repo-switch") {
      expect(err.state.targetTeamId).toBe(team);
    }
    expect(err.message).toMatch(/Acme Eng/);
    expect(err.message).toMatch(/switch workspaces/i);
    // No-repo copy must NOT tell a member to reconnect (they don't own it).
    expect(err.message).not.toMatch(/reconnect/i);
  });

  it("no-repo-switch with an unresolvable team name → name-omitted fallback (no undefined leak)", () => {
    const team = "22222222-2222-2222-2222-222222222222";
    const err = new WorkspaceNotReadyError({
      kind: "no-repo-switch",
      targetTeamId: team,
    });
    expect(err.message).not.toMatch(/undefined|null/);
    expect(err.message).toMatch(/switch workspaces/i);
    expect(err.message).toMatch(/no project connected/i);
  });

  it("noRepoSwitchMsg is the importable single-source string (no drift)", () => {
    expect(noRepoSwitchMsg("Acme Eng")).toContain("Acme Eng");
    expect(noRepoSwitchMsg()).not.toContain("undefined");
  });
});
