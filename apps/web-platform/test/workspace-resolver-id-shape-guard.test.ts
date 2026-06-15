import { describe, expect, it, vi } from "vitest";
import { randomUUID } from "crypto";
import {
  resolveWorkspacePathForUser,
  workspacePathForWorkspaceId,
} from "@/server/workspace-resolver";
import { mockQueryChain } from "./helpers/mock-supabase";

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
}));

// Build a minimal supabase-shape stub that returns `chain` for every
// `.from(table)` call (mirrors test/server/workspace-resolver.test.ts).
function supabaseFor(chain: unknown) {
  return { from: vi.fn(() => chain) } as unknown as Parameters<
    typeof resolveWorkspacePathForUser
  >[1];
}

const ROOT = "/tmp/soleur-test-workspaces-id-shape";

// CWE-22 defense-in-depth (#5344): a workspaceId is DB-sourced (typed
// `string | null`) and flows into join() to build a bwrap mount path
// (ADR-038). These tests pin the two id→path boundary guards that reject
// any non-UUID-shaped value before it can escape the per-tenant mount.
describe("workspace-resolver: workspacePathForWorkspaceId id-shape guard (#5344)", () => {
  it("returns <root>/<uuid> for a valid UUID (no throw, happy path)", () => {
    process.env.WORKSPACES_ROOT = ROOT;
    const id = randomUUID();
    expect(workspacePathForWorkspaceId(id)).toBe(`${ROOT}/${id}`);
  });

  it("returns a path for the all-zero UUID (shape-valid; existence is a separate concern)", () => {
    process.env.WORKSPACES_ROOT = ROOT;
    const zero = "00000000-0000-0000-0000-000000000000";
    expect(workspacePathForWorkspaceId(zero)).toBe(`${ROOT}/${zero}`);
  });

  it("accepts an uppercase UUID (the `i` flag is load-bearing — pins it against a regex tighten)", () => {
    process.env.WORKSPACES_ROOT = ROOT;
    const id = "ABCDEF01-2345-4678-89AB-CDEF01234567";
    expect(workspacePathForWorkspaceId(id)).toBe(`${ROOT}/${id}`);
  });

  it("throws on a parent-traversal id (`../etc`)", () => {
    expect(() => workspacePathForWorkspaceId("../etc")).toThrow(
      /Invalid workspaceId format/,
    );
  });

  it("throws on an embedded-slash id (`a/b`)", () => {
    expect(() => workspacePathForWorkspaceId("a/b")).toThrow(
      /Invalid workspaceId format/,
    );
  });

  it("throws on an absolute-prefix id (`/absolute` — defeats join)", () => {
    expect(() => workspacePathForWorkspaceId("/absolute")).toThrow(
      /Invalid workspaceId format/,
    );
  });

  it("throws on an empty id", () => {
    expect(() => workspacePathForWorkspaceId("")).toThrow(
      /Invalid workspaceId format/,
    );
  });

  it("throws on a non-UUID id", () => {
    expect(() => workspacePathForWorkspaceId("not-a-uuid")).toThrow(
      /Invalid workspaceId format/,
    );
  });

  it("throws on a newline-suffix evasion (`<uuid>\\n../etc`) — pins the missing `m` flag", () => {
    expect(() =>
      workspacePathForWorkspaceId(
        "00000000-0000-0000-0000-000000000000\n../etc",
      ),
    ).toThrow(/Invalid workspaceId format/);
  });
});

describe("workspace-resolver: resolveWorkspacePathForUser id-shape guard (#5344)", () => {
  it("returns the joined path when the DB resolves a valid-UUID workspace_id", async () => {
    process.env.WORKSPACES_ROOT = ROOT;
    const userId = randomUUID();
    const supabase = supabaseFor(mockQueryChain([{ workspace_id: userId }]));

    expect(await resolveWorkspacePathForUser(userId, supabase)).toBe(
      `${ROOT}/${userId}`,
    );
  });

  it("throws when the DB resolves a non-UUID workspace_id (the threat vector)", async () => {
    const userId = randomUUID();
    // The DB column is typed `string | null` — a future writer / backfill bug
    // / unpinned SECURITY DEFINER RPC could land a malformed value here.
    const supabase = supabaseFor(
      mockQueryChain([{ workspace_id: "../../etc/passwd" }]),
    );

    await expect(
      resolveWorkspacePathForUser(userId, supabase),
    ).rejects.toThrow(/Invalid workspaceId format/);
  });
});
