// #8572 — the REAL-PATH pin-fault event test.
//
// test/git-data-host-key-pin.test.ts mocks `observability` and `logger`, so it can only
// assert the call ARGUMENTS. This file keeps both real and mocks only `@sentry/nextjs`, so
// it observes what actually reaches Sentry: one captureMessage (never a captureException —
// the #8629 double capture would show up here), the `pin_fault` tag, cleared breadcrumbs,
// and no raw workspace, worktree or user identifier anywhere in the payload.

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { makeEd25519Pin } from "./helpers/ssh-host-key-fixture";

const env = vi.hoisted(() => {
  // Read at module load by observability.ts; without it every hash is "pepper_unset" and
  // the positive control below would pass for the wrong reason.
  process.env.SENTRY_USERID_PEPPER = "synthetic-pepper-8572";
  return {};
});
void env;

const sentry = vi.hoisted(() => {
  const events: string[] = [];
  return {
    events,
    captureMessage: vi.fn((..._a: unknown[]) => {
      events.push("captureMessage");
      return "evt";
    }),
    captureException: vi.fn((..._a: unknown[]) => {
      events.push("captureException");
      return "evt";
    }),
    addBreadcrumb: vi.fn((..._a: unknown[]) => {
      events.push("addBreadcrumb");
    }),
    withIsolationScope: vi.fn((cb: (scope: { clearBreadcrumbs: () => void }) => unknown) => {
      events.push("scope:open");
      const out = cb({
        clearBreadcrumbs: () => {
          events.push("scope:clearBreadcrumbs");
        },
      });
      events.push("scope:close");
      return out;
    }),
  };
});

vi.mock("@sentry/nextjs", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@sentry/nextjs")>()),
  captureMessage: sentry.captureMessage,
  captureException: sentry.captureException,
  addBreadcrumb: sentry.addBreadcrumb,
  withIsolationScope: sentry.withIsolationScope,
}));

const gitTransport = vi.fn();
const sshTransport = vi.fn();
vi.mock("../server/git-auth", () => ({
  gitWithPrivateKeyAuth: (...args: unknown[]) => gitTransport(...args),
  sshWithPrivateKeyAuth: (...args: unknown[]) => sshTransport(...args),
}));
vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async () => ({ rpc: vi.fn(async () => ({ data: true, error: null })) })),
  RuntimeAuthError: class RuntimeAuthError extends Error {},
}));
vi.mock("child_process", async (importOriginal) => ({
  ...(await importOriginal<typeof import("child_process")>()),
  execFileSync: vi.fn(() => Buffer.from("")),
}));

// Distinctive, so a substring sweep over the payload cannot collide with anything else.
const WS = "ws-raw-sentinel-8572a";
const WT = "wt-raw-sentinel-8572b";
const USER = "user-raw-sentinel-8572c";

async function push(onLogger?: (logger: typeof import("../server/logger").default) => void) {
  vi.resetModules();
  const { replicateToGitData } = await import("../server/git-data-replication");
  const logger = (await import("../server/logger")).default;
  onLogger?.(logger);
  // A breadcrumb candidate carrying a raw workspace path, as a session's own logs would.
  logger.warn({ workspacePath: `/workspaces/${WS}/repo` }, "pre-push workspace note");
  return replicateToGitData({ workspacePath: `/workspaces/${WS}`, workspaceId: WS, worktreeId: WT, leaseGeneration: 7, userId: USER }).then(
    () => "resolved" as const,
    (e: unknown) => e,
  );
}

beforeEach(() => {
  sentry.events.length = 0;
  for (const f of [sentry.captureMessage, sentry.captureException, sentry.addBreadcrumb, sentry.withIsolationScope]) f.mockClear();
  gitTransport.mockReset().mockResolvedValue(Buffer.from(""));
  sshTransport.mockReset().mockResolvedValue(Buffer.from(""));
  vi.stubEnv("GIT_DATA_STORE_ENABLED", "true");
  vi.stubEnv("GIT_DATA_SSH_HOST", "10.0.0.9");
  vi.stubEnv("GIT_DATA_SSH_HOST_KEY", "");
  vi.stubEnv("GIT_PROVISION_SSH_PRIVATE_KEY", "synthetic-provision-key");
  vi.stubEnv("GIT_TRANSPORT_SSH_PRIVATE_KEY", "synthetic-transport-key");
});

afterEach(() => {
  vi.unstubAllEnvs();
});

function assertOnePinFaultEvent(reason: string, via: "ssh" | "git") {
  // Exactly one Sentry event, on the message path. A captureException here is the #8629
  // double capture (pino mirror + tagged capture), which drops the tag.
  expect(sentry.captureException).not.toHaveBeenCalled();
  expect(sentry.captureMessage).toHaveBeenCalledTimes(1);
  const [message, ctx] = sentry.captureMessage.mock.calls[0] as [string, Record<string, unknown>];
  expect(message).toBe(
    `git-data replication push pin fault (${reason}): the workspace's objects were NOT replicated to the shared store`,
  );
  expect(ctx).toMatchObject({ level: "error", extra: { via, pinFault: reason, leaseGeneration: 7 } });
  // Exact: a tag added to push events only (an erasure outcome, a raw-ish id) must fail here.
  expect(ctx.tags).toEqual({ feature: "worktree_lease", op: "git_data_replication_push", pin_fault: reason });
  // Captured inside ONE forked isolation scope, after its breadcrumbs were cleared — so the
  // pre-push breadcrumb carrying the raw path cannot ride this event.
  expect(sentry.withIsolationScope).toHaveBeenCalledTimes(1);
  const i = sentry.events.indexOf("captureMessage");
  expect(sentry.events.slice(0, i)).toContain("scope:clearBreadcrumbs");
  expect(sentry.events.lastIndexOf("scope:open", i)).toBeLessThan(sentry.events.lastIndexOf("scope:clearBreadcrumbs", i));
  expect(sentry.events.indexOf("scope:close", i)).toBeGreaterThan(i);
  return JSON.stringify(sentry.captureMessage.mock.calls[0]);
}

describe("push pin fault — what actually reaches Sentry", () => {
  it("absent pin: one tagged message-path event, breadcrumbs cleared, no raw identifiers", async () => {
    const settled = await push();
    expect(settled).toBeInstanceOf(Error);
    // The pre-push log DID emit a breadcrumb, so clearing it is not vacuous.
    expect(sentry.addBreadcrumb).toHaveBeenCalled();
    const payload = assertOnePinFaultEvent("pin_absent", "ssh");
    for (const raw of [WS, WT, USER]) expect(payload).not.toContain(raw);
    // Positive control: the pseudonymized identifiers ARE present, so the sweep above is
    // looking at a payload that carries identifiers at all.
    const { hashUserId } = await import("../server/observability");
    expect(hashUserId(WS)).not.toBe("pepper_unset");
    expect(payload).toContain(hashUserId(WS));
    expect(payload).toContain(hashUserId(WT));
  });

  it("host key not established on the provision dial: host_key_mismatch via ssh, no stderr on the event", async () => {
    vi.stubEnv("GIT_DATA_SSH_HOST_KEY", makeEd25519Pin());
    sshTransport.mockRejectedValueOnce(
      Object.assign(new Error(`Command failed: ssh git@10.0.0.9 provision ${WS}`), {
        code: 255,
        stderr: "Host key verification failed.",
      }),
    );
    const settled = await push();
    expect(settled).toBeInstanceOf(Error);
    const payload = assertOnePinFaultEvent("host_key_mismatch", "ssh");
    expect(payload).not.toMatch(/verification failed|Command failed/);
    for (const raw of [WS, WT, USER]) expect(payload).not.toContain(raw);
  });

  it("a non-pin push failure keeps the Error path (no pin_fault tag reaches Sentry)", async () => {
    vi.stubEnv("GIT_DATA_SSH_HOST_KEY", makeEd25519Pin());
    gitTransport.mockRejectedValueOnce(
      Object.assign(new Error("Command failed: git push"), { code: 1, stderr: "remote: fence: stale lease-gen" }),
    );
    await push();
    const tagged = [...sentry.captureMessage.mock.calls, ...sentry.captureException.mock.calls].filter((c) =>
      JSON.stringify(c).includes("pin_fault"),
    );
    expect(tagged).toHaveLength(0);
    expect(sentry.captureException).toHaveBeenCalled();
  });

  it("a scope that cannot be opened never throws into the push: the original error is rethrown, pino only", async () => {
    sentry.withIsolationScope.mockImplementationOnce(() => {
      throw new TypeError("withIsolationScope is not a function");
    });
    let errorSpy!: ReturnType<typeof vi.spyOn>;
    const settled = await push((logger) => {
      errorSpy = vi.spyOn(logger, "error");
    });
    // The resolver's refusal, not the observability failure.
    expect(settled).toMatchObject({ name: "GitDataHostKeyPinError", reason: "pin_absent" });
    // Never captured in the ambient scope, whose breadcrumbs hold the raw path.
    expect(sentry.captureMessage).not.toHaveBeenCalled();
    expect(sentry.captureException).not.toHaveBeenCalled();
    const lines = errorSpy.mock.calls.filter((c: unknown[]) => String(c[1]).startsWith("git-data replication push pin fault"));
    expect(lines).toHaveLength(1);
    expect(lines[0][0]).toMatchObject({ op: "git_data_replication_push", pinFault: "pin_absent", via: "ssh" });
    expect(JSON.stringify(lines[0])).not.toContain(USER);
    errorSpy.mockRestore();
  });

  it("a report that throws inside the scope is swallowed once, never re-logged", async () => {
    // reportSilentFallback guards its Sentry calls itself; its pino line is the unguarded step.
    let errorSpy!: ReturnType<typeof vi.spyOn>;
    const settled = await push((logger) => {
      errorSpy = vi.spyOn(logger, "error").mockImplementationOnce(() => {
        throw new Error("pino transport exploded");
      });
    });
    // The resolver's refusal still reaches the caller, not the observability failure.
    expect(settled).toMatchObject({ name: "GitDataHostKeyPinError", reason: "pin_absent" });
    const lines = errorSpy.mock.calls.filter((c: unknown[]) => String(c[1]).startsWith("git-data replication push pin fault"));
    expect(lines).toHaveLength(1);
    errorSpy.mockRestore();
  });
});
