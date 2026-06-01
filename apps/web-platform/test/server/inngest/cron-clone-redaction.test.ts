// #4689 follow-on (security) — the clone URL embeds the installation token
// (`https://x-access-token:<TOKEN>@github.com/...`) and git echoes the remote
// on auth failures. spawnSimple now captures stderr and setupEphemeralWorkspace
// folds it into the thrown `git clone failed` error, so the raw token MUST be
// redacted before it reaches the message / Sentry. This file pins that
// redaction by mocking node:child_process to emit a token-bearing stderr line.
//
// Separate file: vi.mock("node:child_process") hoists file-wide and would
// clobber the real-spawn calls in cron-claude-eval-substrate.test.ts.

import { afterEach, describe, expect, it, vi } from "vitest";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

const spawnSpy = vi.fn();
vi.mock("node:child_process", () => ({ spawn: spawnSpy }));

const SENTINEL_TOKEN = "ghs_SENTINEL_INSTALLATION_TOKEN_DO_NOT_LEAK";

function fakeCloneChild(stderrLine: string, exitCode: number) {
  // Minimal EventEmitter-shaped stub matching spawnSimple's usage.
  const stderrHandlers: Record<string, (arg: unknown) => void> = {};
  const childHandlers: Record<string, (...a: unknown[]) => void> = {};
  const child = {
    stderr: {
      setEncoding: () => {},
      on: (ev: string, cb: (arg: unknown) => void) => {
        stderrHandlers[ev] = cb;
      },
    },
    on: (ev: string, cb: (...a: unknown[]) => void) => {
      childHandlers[ev] = cb;
    },
  };
  // Emit AFTER spawnSimple attaches its listeners (the SUT wires handlers
  // synchronously on the returned object, then we fire on the microtask).
  queueMicrotask(() => {
    stderrHandlers["data"]?.(stderrLine);
    childHandlers["exit"]?.(exitCode, null);
  });
  return child;
}

describe("setupEphemeralWorkspace — clone-failure token redaction", () => {
  afterEach(() => {
    spawnSpy.mockReset();
    vi.resetModules();
  });

  it("redacts the installation token out of the thrown clone-failure error", async () => {
    const leakyStderr = `fatal: unable to access 'https://x-access-token:${SENTINEL_TOKEN}@github.com/jikig-ai/soleur.git/': The requested URL returned error: 403`;
    spawnSpy.mockImplementation(() => fakeCloneChild(leakyStderr, 128));

    const { setupEphemeralWorkspace } = await import(
      "@/server/inngest/functions/_cron-claude-eval-substrate"
    );

    let thrown: Error | null = null;
    try {
      await setupEphemeralWorkspace({
        installationToken: SENTINEL_TOKEN,
        cronName: "cron-test",
      });
    } catch (err) {
      thrown = err as Error;
    }

    expect(thrown).not.toBeNull();
    // The diagnostic reason is folded in...
    expect(thrown!.message).toContain("git clone failed (exit 128");
    expect(thrown!.message).toContain("error: 403");
    // ...but the raw token is scrubbed and the redaction sentinel is present.
    expect(thrown!.message).not.toContain(SENTINEL_TOKEN);
    expect(thrown!.message).toContain("[REDACTED-INSTALLATION-TOKEN]");
  });
});
