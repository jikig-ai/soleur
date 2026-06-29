import { describe, test, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import { FeatureFlagProvider, useFeatureFlag } from "@/components/feature-flags/provider";

function Probe({ name }: { name: "dev-signin" | "kb-chat-sidebar" }) {
  const enabled = useFeatureFlag(name);
  return <span data-testid="probe">{enabled ? "on" : "off"}</span>;
}

describe("FeatureFlagProvider + useFeatureFlag", () => {
  test("returns true for a flag set true in the snapshot", () => {
    render(
      <FeatureFlagProvider flags={{ "dev-signin": false, "team-workspace-invite": false, "byok-delegations": false, "kb-chat-sidebar": true, "c4-visualizer": false, "debug-mode": false, "c4-edit": false, "command-palette": false }}>
        <Probe name="kb-chat-sidebar" />
      </FeatureFlagProvider>,
    );
    expect(screen.getByTestId("probe").textContent).toBe("on");
  });

  test("returns false for a flag set false in the snapshot", () => {
    render(
      <FeatureFlagProvider flags={{ "dev-signin": false, "team-workspace-invite": false, "byok-delegations": false, "kb-chat-sidebar": false, "c4-visualizer": false, "debug-mode": false, "c4-edit": false, "command-palette": false }}>
        <Probe name="kb-chat-sidebar" />
      </FeatureFlagProvider>,
    );
    expect(screen.getByTestId("probe").textContent).toBe("off");
  });

  test("throws when used outside the provider", () => {
    // Suppress React's expected error log for this assertion.
    const originalError = console.error;
    console.error = () => {};
    try {
      expect(() => render(<Probe name="kb-chat-sidebar" />)).toThrow(
        /useFeatureFlag must be used inside <FeatureFlagProvider>/,
      );
    } finally {
      console.error = originalError;
    }
  });
});
