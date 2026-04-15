import { vi } from "vitest";
import type { DomainLeaderId } from "@/server/domain-leaders";
import type { useTeamNames } from "@/hooks/use-team-names";

type TeamNamesState = ReturnType<typeof useTeamNames>;

/**
 * Shared factory for mocking `useTeamNames` in tests.
 *
 * Returns a self-contained default shape plus optional per-test overrides.
 * Uses `ReturnType<typeof useTeamNames>` for compile-time drift detection:
 * if the hook's return shape changes, every consumer of this factory breaks.
 *
 * Usage (Pattern A — closure-wrapped, recommended):
 *
 *   import { createUseTeamNamesMock } from "./mocks/use-team-names";
 *   vi.mock("@/hooks/use-team-names", () => ({
 *     useTeamNames: () => createUseTeamNamesMock(),
 *   }));
 *
 * Per-test override:
 *
 *   vi.mock("@/hooks/use-team-names", () => ({
 *     useTeamNames: () => createUseTeamNamesMock({ loading: true }),
 *   }));
 */
export function createUseTeamNamesMock(
  overrides: Partial<TeamNamesState> = {},
): TeamNamesState {
  return {
    names: {},
    iconPaths: {},
    nudgesDismissed: [],
    namingPromptedAt: null,
    loading: false,
    error: null,
    updateName: vi.fn(),
    updateIcon: vi.fn(),
    dismissNudge: vi.fn(),
    refetch: vi.fn(),
    getDisplayName: (id: DomainLeaderId) => id.toUpperCase(),
    getBadgeLabel: (id: DomainLeaderId) => id.toUpperCase().slice(0, 3),
    getIconPath: (_id: DomainLeaderId) => null,
    ...overrides,
  };
}
