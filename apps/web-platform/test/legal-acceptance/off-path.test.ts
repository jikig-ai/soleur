/**
 * #12011 PR-D: the off-request-path scheduler used by the decide route. Decision (recorded in the PR report): `after()`
 * from next/server is used when it is available, because it works under the custom server (a production build served
 * through `next({dev:false}).getRequestHandler()` runs the callback after the response, measured at work time); outside a
 * request scope it throws, and the helper then falls back to a caught fire-and-forget promise so a task is never lost.
 */
import { beforeEach, describe, expect, it, vi } from "vitest";

// A plain mutable function, not vi.fn().mockImplementation(throw): the spy would record the throw and the runner reports it.
const h = vi.hoisted(() => ({ calls: [] as unknown[][], impl: (() => {}) as (...a: unknown[]) => void }));
vi.mock("next/server", async (orig) => ({ ...(await orig<typeof import("next/server")>()), after: (...a: unknown[]) => { h.calls.push(a); return h.impl(...a); } }));

import { runOffRequestPath } from "@/server/legal-acceptance/off-path";

beforeEach(() => {
  h.calls.length = 0;
  h.impl = () => {};
});

describe("runOffRequestPath", () => {
  it("hands the task to after() and does not run it inline", () => {
    h.impl = () => {};
    const task = vi.fn(async () => {});
    runOffRequestPath(task);
    expect(h.calls).toHaveLength(1);
    expect(task).not.toHaveBeenCalled();
    // after() receives a function that runs the task.
    return (h.calls[0][0] as () => Promise<void>)().then(() => expect(task).toHaveBeenCalledTimes(1));
  });
  it("when after() throws (no request scope), the task still runs once, as a caught fire-and-forget", async () => {
    h.impl = () => {
      throw new Error("`after` was called outside a request scope");
    };
    const task = vi.fn(async () => {
      throw new Error("task failure is swallowed");
    });
    runOffRequestPath(task);
    expect(h.calls).toHaveLength(1);
    await vi.waitFor(() => expect(task).toHaveBeenCalledTimes(1));
  });
});

describe("the real after() outside a request scope", () => {
  it("throws, which is why the fallback exists (unit tests and any non-Next caller are outside a scope)", async () => {
    const real = await vi.importActual<typeof import("next/server")>("next/server");
    expect(() => real.after(() => {})).toThrow(/outside a request scope/);
  });
});
