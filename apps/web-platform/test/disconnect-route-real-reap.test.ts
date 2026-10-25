// #8211: runs the REAL deleteWorkspace through the disconnect route (the sibling
// disconnect-route.test.ts mocks it). Real filesystem under mkdtemp roots.
import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { existsSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { mockQueryChain } from "./helpers/mock-supabase";

const { mockGetUser, mockFrom, mockRpc, mockResolveActiveWorkspace, rmFailure } = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockFrom: vi.fn(),
  mockRpc: vi.fn(),
  mockResolveActiveWorkspace: vi.fn(),
  rmFailure: { substr: null as string | null },
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({ auth: { getUser: mockGetUser }, rpc: mockRpc })),
  createServiceClient: vi.fn(() => ({ from: mockFrom })),
}));
vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: vi.fn(() => ({ valid: true, origin: "https://app.soleur.com" })),
  rejectCsrf: vi.fn(),
}));
vi.mock("@/server/rate-limiter", () => ({
  SlidingWindowCounter: vi.fn().mockImplementation(function (this: Record<string, unknown>) {
    this.isAllowed = () => true;
  }),
}));
vi.mock("@/server/logger", () => {
  const l = { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() };
  return { default: l, createChildLogger: () => l };
});
vi.mock("@sentry/nextjs", () => ({ addBreadcrumb: vi.fn(), captureException: vi.fn() }));
vi.mock("@/server/workspace-repo-mirror", () => ({
  writeRepoColsToWorkspace: vi.fn().mockResolvedValue(undefined),
}));
// Only the membership-verified resolver is controlled; workspaceReapRoots stays REAL.
vi.mock("@/server/workspace-resolver", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/workspace-resolver")>()),
  resolveActiveWorkspace: mockResolveActiveWorkspace,
}));
// Real rm, except for a configured path substring (simulates an undeletable tree).
vi.mock("child_process", async () => {
  const { mockChildProcessFactory } = await import("./helpers/mock-child-process");
  return mockChildProcessFactory((_cmd, args) => {
    if (rmFailure.substr && args.some((a) => typeof a === "string" && a.includes(rmFailure.substr!))) {
      throw new Error("Permission denied");
    }
  });
});

import * as Sentry from "@sentry/nextjs";
import { DELETE } from "@/app/api/repo/disconnect/route";

const USER = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee";
const TEAM = "11111111-2222-4333-8444-555555555555";
const OTHER = "99999999-2222-4333-8444-555555555555";

let sandbox: string;
let wsRoot: string;
let wtRoot: string;
const saved = { ws: process.env.WORKSPACES_ROOT, wt: process.env.WORKTREE_ROOT };

function seed(root: string, id: string): string {
  const d = join(root, id);
  mkdirSync(join(d, "sub"), { recursive: true });
  writeFileSync(join(d, "sub", "f.txt"), "x");
  return d;
}

beforeEach(() => {
  vi.clearAllMocks();
  rmFailure.substr = null;
  sandbox = mkdtempSync(join(tmpdir(), "soleur-disc-"));
  wsRoot = join(sandbox, "workspaces");
  wtRoot = join(sandbox, "worktrees");
  mkdirSync(wsRoot);
  mkdirSync(wtRoot);
  process.env.WORKSPACES_ROOT = wsRoot;
  process.env.WORKTREE_ROOT = wtRoot;
  mockGetUser.mockResolvedValue({ data: { user: { id: USER } } });
  mockRpc.mockResolvedValue({ data: true, error: null });
  mockResolveActiveWorkspace.mockResolvedValue({ ok: true, workspaceId: TEAM });
  const chain = mockQueryChain({ repo_status: "ready" }, null);
  mockFrom.mockImplementation((t: string) => (t === "workspaces" ? { select: chain.select } : {}));
});

afterEach(() => {
  if (saved.ws === undefined) delete process.env.WORKSPACES_ROOT;
  else process.env.WORKSPACES_ROOT = saved.ws;
  if (saved.wt === undefined) delete process.env.WORKTREE_ROOT;
  else process.env.WORKTREE_ROOT = saved.wt;
  rmSync(sandbox, { recursive: true, force: true });
});

const req = () =>
  new Request("https://app.soleur.com/api/repo/disconnect", {
    method: "DELETE",
    headers: { origin: "https://app.soleur.com" },
  });

describe("DELETE /api/repo/disconnect through the REAL deleteWorkspace", () => {
  test("a team disconnect reaps WORKTREE_ROOT/<team-id> (the live clone) and the volume copy, nothing else", async () => {
    const live = seed(wtRoot, TEAM);
    const stale = seed(wsRoot, TEAM);
    const keep = seed(wtRoot, OTHER);

    const res = await DELETE(req());

    expect(res.status).toBe(200);
    expect(existsSync(live)).toBe(false);
    expect(existsSync(stale)).toBe(false);
    expect(existsSync(keep)).toBe(true);
    expect(Sentry.captureException).not.toHaveBeenCalled();
  });

  test("an aggregate reap failure still yields 200 and one tagged Sentry capture with no raw id", async () => {
    seed(wsRoot, TEAM);
    const live = seed(wtRoot, TEAM);
    rmFailure.substr = wtRoot; // the worktree tree cannot be removed

    const res = await DELETE(req());

    expect(res.status).toBe(200);
    expect(existsSync(join(wsRoot, TEAM))).toBe(false); // the other root was still reaped
    expect(Sentry.captureException).toHaveBeenCalledTimes(1);
    const [err, ctx] = vi.mocked(Sentry.captureException).mock.calls[0] as [AggregateError, object];
    expect(err).toBeInstanceOf(AggregateError);
    expect(ctx).toMatchObject({ tags: { feature: "repo-disconnect", op: "workspace-tree-erasure" } });
    expect(JSON.stringify([err.message, err.errors.map((e) => e.message), ctx])).not.toContain(TEAM);
    expect(existsSync(live)).toBe(true); // the failed tree is still there, and was reported
  });
});
