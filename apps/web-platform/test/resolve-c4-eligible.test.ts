/**
 * #5388 — focused unit tests for `resolveC4Eligible`'s precondition gating, the
 * load-bearing AC2 false-suppression guard: the dispatcher must NOT advertise the
 * edit_c4_diagram FQN more permissively than the factory registers the tool. The
 * predicate-contract tests live in cc-mcp-tier-allowlist.test.ts; this file
 * exercises the actual eligibility decision (the logic that BUILDS the advertised
 * set) with the seam functions mocked — no Supabase/Flagsmith/SDK in the loop.
 *
 * `parseConnectedRepo` is intentionally NOT mocked so the real owner/repo parse
 * runs; the four userId-keyed primitives + the role/flag reads are mocked.
 */
import { describe, test, expect, vi, beforeEach } from "vitest";

vi.mock("../server/current-repo-url", () => ({
  getCurrentRepoUrl: vi.fn(),
}));
vi.mock("../server/resolve-installation-id", () => ({
  resolveInstallationId: vi.fn(),
}));
vi.mock("../server/cc-effective-installation", () => ({
  resolveEffectiveInstallationId: vi.fn(),
}));
vi.mock("@/lib/feature-flags/server", () => ({
  getRuntimeFlag: vi.fn(),
}));
vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(),
}));

import { resolveC4Eligible, resolveC4FlagEnabled } from "../server/resolve-c4-eligible";
import { getCurrentRepoUrl } from "../server/current-repo-url";
import { resolveInstallationId } from "../server/resolve-installation-id";
import { resolveEffectiveInstallationId } from "../server/cc-effective-installation";
import { getRuntimeFlag } from "@/lib/feature-flags/server";
import { getFreshTenantClient } from "@/lib/supabase/tenant";
import { C4_VISUALIZER_FLAG, C4_EDIT_FLAG } from "@/lib/c4-constants";

const USER = "user-7f3a9c2e-1d4b-4a5c-9e8f-0b1c2d3e4f5a";

/** Minimal tenant chain: `.from("users").select("role").eq("id", …).single()`. */
function mockTenantWithRole(role: string): void {
  const single = vi.fn().mockResolvedValue({ data: { role } });
  const eq = vi.fn(() => ({ single }));
  const select = vi.fn(() => ({ eq }));
  const from = vi.fn(() => ({ select }));
  vi.mocked(getFreshTenantClient).mockResolvedValue({ from } as never);
}

beforeEach(() => {
  vi.clearAllMocks();
});

describe("resolveC4Eligible precondition gating (#5388 AC2)", () => {
  test("no connected repo (null repoUrl) ⇒ not eligible (flag never consulted)", async () => {
    vi.mocked(getCurrentRepoUrl).mockResolvedValue(null);
    vi.mocked(resolveInstallationId).mockResolvedValue(42);

    expect(await resolveC4Eligible(USER)).toBe(false);
    // Short-circuits before the installation + flag reads.
    expect(resolveEffectiveInstallationId).not.toHaveBeenCalled();
    expect(getRuntimeFlag).not.toHaveBeenCalled();
  });

  test("malformed repoUrl ⇒ not eligible", async () => {
    vi.mocked(getCurrentRepoUrl).mockResolvedValue("not-a-url");
    vi.mocked(resolveInstallationId).mockResolvedValue(42);

    expect(await resolveC4Eligible(USER)).toBe(false);
    expect(getRuntimeFlag).not.toHaveBeenCalled();
  });

  test("valid repo but effectiveInstallationId === null ⇒ not eligible (the false-suppression guard)", async () => {
    vi.mocked(getCurrentRepoUrl).mockResolvedValue("https://github.com/acme/widgets");
    vi.mocked(resolveInstallationId).mockResolvedValue(null);
    vi.mocked(resolveEffectiveInstallationId).mockResolvedValue(null);

    expect(await resolveC4Eligible(USER)).toBe(false);
    // Flag must NOT be consulted once the installation precondition fails —
    // advertising c4 here would be MORE permissive than the factory's build gate.
    expect(getRuntimeFlag).not.toHaveBeenCalled();
  });

  test("all preconditions met but flag OFF ⇒ not eligible (flag checked last)", async () => {
    vi.mocked(getCurrentRepoUrl).mockResolvedValue("https://github.com/acme/widgets.git");
    vi.mocked(resolveInstallationId).mockResolvedValue(42);
    vi.mocked(resolveEffectiveInstallationId).mockResolvedValue(99);
    mockTenantWithRole("dev");
    vi.mocked(getRuntimeFlag).mockResolvedValue(false);

    expect(await resolveC4Eligible(USER)).toBe(false);
    expect(getRuntimeFlag).toHaveBeenCalledTimes(1);
  });

  test("all preconditions met and flag ON ⇒ eligible", async () => {
    vi.mocked(getCurrentRepoUrl).mockResolvedValue("https://github.com/acme/widgets");
    vi.mocked(resolveInstallationId).mockResolvedValue(42);
    vi.mocked(resolveEffectiveInstallationId).mockResolvedValue(99);
    mockTenantWithRole("dev");
    vi.mocked(getRuntimeFlag).mockResolvedValue(true);

    expect(await resolveC4Eligible(USER)).toBe(true);
  });

  test("resolution error propagates (caller fails closed)", async () => {
    vi.mocked(getCurrentRepoUrl).mockRejectedValue(new Error("tenant down"));
    vi.mocked(resolveInstallationId).mockResolvedValue(42);

    await expect(resolveC4Eligible(USER)).rejects.toThrow("tenant down");
  });
});

describe("resolveC4FlagEnabled (#5388 shared flag decision)", () => {
  test("maps a non-dev role to prd before resolving the flag", async () => {
    mockTenantWithRole("prd");
    vi.mocked(getRuntimeFlag).mockResolvedValue(false);

    expect(await resolveC4FlagEnabled(USER)).toBe(false);
    expect(getRuntimeFlag).toHaveBeenCalledWith(
      expect.any(String),
      expect.objectContaining({ userId: USER, role: "prd", orgId: null }),
    );
  });

  test("passes role=dev through for a dev user", async () => {
    mockTenantWithRole("dev");
    vi.mocked(getRuntimeFlag).mockResolvedValue(true);

    expect(await resolveC4FlagEnabled(USER)).toBe(true);
    expect(getRuntimeFlag).toHaveBeenCalledWith(
      expect.any(String),
      expect.objectContaining({ role: "dev" }),
    );
  });

  test("AC9 — Concierge eligibility resolves c4-visualizer, NEVER c4-edit (no cross-wiring)", async () => {
    mockTenantWithRole("dev");
    vi.mocked(getRuntimeFlag).mockResolvedValue(true);

    await resolveC4FlagEnabled(USER);
    // The flag NAME passed must be the visualizer flag — gating the Concierge on
    // c4-edit would couple the two surfaces and re-break the deliberate split.
    expect(getRuntimeFlag).toHaveBeenCalledWith(
      C4_VISUALIZER_FLAG,
      expect.anything(),
    );
    expect(getRuntimeFlag).not.toHaveBeenCalledWith(
      C4_EDIT_FLAG,
      expect.anything(),
    );
  });
});
