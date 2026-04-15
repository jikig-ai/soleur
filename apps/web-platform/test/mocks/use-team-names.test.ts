import { describe, it, expect } from "vitest";
import { createUseTeamNamesMock } from "./use-team-names";

describe("createUseTeamNamesMock", () => {
  it("provides default values for every required field", () => {
    const mock = createUseTeamNamesMock();
    expect(mock.names).toEqual({});
    expect(mock.iconPaths).toEqual({});
    expect(mock.nudgesDismissed).toEqual([]);
    expect(mock.namingPromptedAt).toBeNull();
    expect(mock.loading).toBe(false);
    expect(mock.error).toBeNull();
    expect(typeof mock.updateName).toBe("function");
    expect(typeof mock.updateIcon).toBe("function");
    expect(typeof mock.dismissNudge).toBe("function");
    expect(typeof mock.refetch).toBe("function");
    expect(mock.getDisplayName("cto")).toBe("CTO");
    expect(mock.getBadgeLabel("cto")).toBe("CTO");
    expect(mock.getIconPath("cto")).toBeNull();
  });

  it("merges overrides on top of defaults", () => {
    const mock = createUseTeamNamesMock({
      loading: true,
      iconPaths: { cto: "settings/team-icons/cto.png" },
    });
    expect(mock.loading).toBe(true);
    expect(mock.iconPaths).toEqual({ cto: "settings/team-icons/cto.png" });
    expect(mock.names).toEqual({}); // unchanged default
    expect(mock.error).toBeNull(); // unchanged default
  });
});
