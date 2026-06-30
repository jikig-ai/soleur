import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { mkdtemp, rm, mkdir, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

// #5733 deliverable D2 — the absent/dir-invalid strand gate. The 77e77c3 host
// rev-parse confirm only ran for the `dir-valid` slice; an ABSENT (or dir-invalid)
// `.git` returned "ready" → a doomed agent spawn. D2 widens the shared gate so an
// absent/dir-invalid `.git` is a confirmed terminal strand on the COLD (post-heal)
// dispatch surface → emit `agent_readiness_self_stop` + honest-block. The
// reconcile (pre-heal) surface re-clones the same shape one line later, so it must
// NOT emit here (soak-signal guard).

const { mockSelfStop, mockInconclusive } = vi.hoisted(() => ({
  mockSelfStop: vi.fn(),
  mockInconclusive: vi.fn(),
}));
vi.mock("@/server/repo-resolver-divergence", () => ({
  reportAgentReadinessSelfStop: mockSelfStop,
  reportAgentReadinessProbeInconclusive: mockInconclusive,
}));

import {
  evaluateAgentReadiness,
  type GitRevParseOutcome,
} from "@/server/git-worktree-validity";

describe("evaluateAgentReadiness — absent/dir-invalid strand gate (#5733 D2)", () => {
  let dir: string;
  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "agentready-absent-"));
    vi.clearAllMocks();
  });
  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  const coldCtx = {
    userId: "user-1",
    activeWorkspaceId: "754ee124",
    connected: true,
    dbReady: true,
    phase: "post-heal" as const,
  };
  // The probe must NEVER be consulted for a non-dir-valid shape.
  const neverProbe = vi.fn(
    (): Promise<GitRevParseOutcome> => Promise.resolve("not-a-worktree"),
  );

  async function absentWs(name: string): Promise<string> {
    const p = join(dir, name);
    await mkdir(p, { recursive: true }); // no `.git`
    return p;
  }
  async function dirInvalidWs(name: string): Promise<string> {
    const p = join(dir, name);
    await mkdir(join(p, ".git"), { recursive: true }); // bare `mkdir .git`, no HEAD/objects
    return p;
  }
  async function dirValidWs(name: string): Promise<string> {
    const p = join(dir, name);
    await mkdir(join(p, ".git", "objects"), { recursive: true });
    await writeFile(join(p, ".git", "HEAD"), "ref: refs/heads/main\n");
    return p;
  }

  it("AC2: cold (post-heal) absent `.git` → block + self-stop (gitKind:absent, gitRevParseValid:false, source:host-pre-heal)", async () => {
    const ws = await absentWs("absent");
    expect(await evaluateAgentReadiness(ws, coldCtx, neverProbe)).toBe("block");
    expect(neverProbe).not.toHaveBeenCalled();
    expect(mockSelfStop).toHaveBeenCalledTimes(1);
    expect(mockSelfStop).toHaveBeenCalledWith(
      expect.objectContaining({
        userId: "user-1",
        activeWorkspaceId: "754ee124",
        gitKind: "absent",
        gitRevParseValid: false,
        source: "host-pre-heal",
      }),
    );
  });

  it("AC2: cold (post-heal) dir-invalid `.git` → block + self-stop (gitKind:dir-invalid)", async () => {
    const ws = await dirInvalidWs("invalid");
    expect(await evaluateAgentReadiness(ws, coldCtx, neverProbe)).toBe("block");
    expect(neverProbe).not.toHaveBeenCalled();
    expect(mockSelfStop).toHaveBeenCalledWith(
      expect.objectContaining({ gitKind: "dir-invalid", gitRevParseValid: false }),
    );
  });

  it("AC5: reconcile (pre-heal) absent `.git` → ready WITHOUT a self-stop emit (the heal owns it)", async () => {
    const ws = await absentWs("absent-reconcile");
    expect(
      await evaluateAgentReadiness(ws, { ...coldCtx, phase: "pre-heal" }, neverProbe),
    ).toBe("ready");
    expect(mockSelfStop).not.toHaveBeenCalled();
  });

  it("AC5: reconcile (pre-heal) dir-invalid `.git` → ready WITHOUT a self-stop emit", async () => {
    const ws = await dirInvalidWs("invalid-reconcile");
    expect(
      await evaluateAgentReadiness(ws, { ...coldCtx, phase: "pre-heal" }, neverProbe),
    ).toBe("ready");
    expect(mockSelfStop).not.toHaveBeenCalled();
  });

  it("no regression: dir-valid + worktree → ready (host confirm still runs)", async () => {
    const ws = await dirValidWs("ok");
    const probe = vi.fn((): Promise<GitRevParseOutcome> => Promise.resolve("worktree"));
    expect(await evaluateAgentReadiness(ws, coldCtx, probe)).toBe("ready");
    expect(probe).toHaveBeenCalledTimes(1);
    expect(mockSelfStop).not.toHaveBeenCalled();
  });

  it("no regression: inconclusive×2 → ready (fail-open), no self-stop", async () => {
    const ws = await dirValidWs("blip");
    const probe = vi.fn((): Promise<GitRevParseOutcome> => Promise.resolve("inconclusive"));
    expect(await evaluateAgentReadiness(ws, coldCtx, probe)).toBe("ready");
    expect(probe).toHaveBeenCalledTimes(2);
    expect(mockInconclusive).toHaveBeenCalledTimes(1);
    expect(mockSelfStop).not.toHaveBeenCalled();
  });

  it("not connected → ready WITHOUT probing or emitting (even for absent)", async () => {
    const ws = await absentWs("repoless");
    expect(
      await evaluateAgentReadiness(ws, { ...coldCtx, connected: false }, neverProbe),
    ).toBe("ready");
    expect(mockSelfStop).not.toHaveBeenCalled();
  });
});
