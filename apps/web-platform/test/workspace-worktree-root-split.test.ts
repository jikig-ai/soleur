import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { workspacePathForWorkspaceId } from "@/server/workspace-resolver";

// epic #5274 Phase 2 PR B (task 2.4) — the worktree/bare-store split is gated by
// GIT_DATA_STORE_ENABLED, which DEFAULTS to the single RWO volume. This suite
// pins the load-bearing AC6b property: with the flag defaulted, the app resolves
// the working tree from the VOLUME exactly as today (inert), and only the PR-C
// cutover flip routes it to host-local NVMe.

const WS = "11111111-1111-4111-8111-111111111111";

beforeEach(() => {
  // Neutralize any Doppler/CI-injected values so the default-off branch is
  // faithful (vi.unstubAllEnvs cannot delete a process-inherited var; an explicit
  // empty stub is the canonical defense — see the env-leak learning).
  vi.stubEnv("GIT_DATA_STORE_ENABLED", "");
  vi.stubEnv("WORKSPACES_ROOT", "");
  vi.stubEnv("WORKTREE_ROOT", "");
});

afterEach(() => {
  vi.unstubAllEnvs();
});

describe("workspace worktree-root split (behind the volume-default read flag)", () => {
  it("flag OFF (default): resolves the working tree under the volume root — INERT, byte-identical to today", () => {
    expect(workspacePathForWorkspaceId(WS)).toBe(`/workspaces/${WS}`);
  });

  it("flag OFF honors an explicit WORKSPACES_ROOT override (the mounted volume path)", () => {
    vi.stubEnv("WORKSPACES_ROOT", "/mnt/data/workspaces");
    expect(workspacePathForWorkspaceId(WS)).toBe(`/mnt/data/workspaces/${WS}`);
  });

  it("flag ON: resolves the working tree under the host-local NVMe WORKTREE_ROOT (post-cutover)", () => {
    vi.stubEnv("GIT_DATA_STORE_ENABLED", "true");
    vi.stubEnv("WORKTREE_ROOT", "/var/lib/soleur/worktrees");
    expect(workspacePathForWorkspaceId(WS)).toBe(`/var/lib/soleur/worktrees/${WS}`);
  });

  it("flag ON without WORKTREE_ROOT falls back to the NVMe default, NEVER the volume", () => {
    vi.stubEnv("GIT_DATA_STORE_ENABLED", "true");
    const p = workspacePathForWorkspaceId(WS);
    expect(p).toBe(`/var/lib/soleur/worktrees/${WS}`);
    expect(p).not.toBe(`/workspaces/${WS}`);
  });

  it("flag set to a NON-'true' value is treated as OFF (strict 'true' gate, fail-safe to the volume)", () => {
    vi.stubEnv("GIT_DATA_STORE_ENABLED", "1"); // not the literal "true"
    expect(workspacePathForWorkspaceId(WS)).toBe(`/workspaces/${WS}`);
  });
});
