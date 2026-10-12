/**
 * #10032 follow-up — a Bash tool_result carrying a sandbox denial is mirrored to Sentry, and ONLY the scrubbed
 * matched line leaves the process (Art. 5(1)(c)). The classifier's own cases live in
 * sandbox-startup-classifier.test.ts; this file pins the dispatcher side: the event shape, the debounce key, and
 * that the tool output / command / workspace path never reach the event.
 */
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, it, expect, vi, beforeEach } from "vitest";

const mirrorSpy = vi.hoisted(() => vi.fn());

vi.mock("@/server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/observability")>()),
  mirrorWithDebounce: (...args: unknown[]) => mirrorSpy(...args),
}));

import { mirrorBashSandboxFailure } from "@/server/cc-dispatcher";

const USER = "754ee124-706a-4f21-a4f4-e828257b0380";
const CONV = "c0ffee00-0000-4000-8000-000000000001";
const PROC_EPERM = "bwrap: Can't mount proc on /newroot/proc: Operation not permitted";

describe("mirrorBashSandboxFailure (#10032)", () => {
  beforeEach(() => mirrorSpy.mockClear());

  it("mirrors a sandbox denial once, tagged agent-sandbox / bash-tool-result, keyed per user", () => {
    mirrorBashSandboxFailure(PROC_EPERM, USER, CONV);
    expect(mirrorSpy).toHaveBeenCalledTimes(1);
    const [err, ctx, userId, errorClass] = mirrorSpy.mock.calls[0];
    // null, never a real Error: the pino mirror would capture an Error first, untagged and user-less (#8629).
    expect(err).toBeNull();
    expect(ctx.message).toBe("bash sandbox denial: proc_mount_eperm");
    expect(ctx.feature).toBe("agent-sandbox");
    expect(ctx.op).toBe("bash-tool-result");
    expect(ctx.tags.sandboxKind).toBe("seccomp_or_userns_denial");
    expect(ctx.extra.sandboxErrorCode).toBe("proc_mount_eperm");
    expect(ctx.extra.sandboxStderr).toBe(PROC_EPERM);
    expect(userId).toBe(USER);
    expect(errorClass).toBe("agent-sandbox-bash-tool-result");
  });

  it("data minimisation: neither the surrounding output nor a workspace path reaches the event", () => {
    const secret = "AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY";
    const pathLine = `bwrap: Can't bind mount /workspaces/${USER}/repo on /newroot/x: Operation not permitted`;
    mirrorBashSandboxFailure(`${secret}\n${pathLine}\ncat: notes.txt: top secret plan`, USER, CONV);
    const serialized = JSON.stringify(mirrorSpy.mock.calls[0]);
    expect(serialized).not.toContain("wJalrXUtnFEMI");
    expect(serialized).not.toContain("top secret plan");
    // The user id legitimately appears as the debounce key / extra.userId (pseudonymized at the emit boundary);
    // what must NOT appear is the workspace PATH carrying it inside the stderr line.
    expect(mirrorSpy.mock.calls[0][1].extra.sandboxStderr).not.toContain("/workspaces/");
    expect(mirrorSpy.mock.calls[0][1].extra.sandboxStderr).not.toContain(USER);
  });

  it("does not mirror an ordinary permission error or empty output", () => {
    mirrorBashSandboxFailure("cat: /etc/shadow: Permission denied", USER, CONV);
    mirrorBashSandboxFailure("", USER, CONV);
    expect(mirrorSpy).not.toHaveBeenCalled();
  });
});

// The wire between the helper and its only caller: a helper test cannot see a deleted or misplaced call.
describe("onToolResult calls the mirror (call-site pin)", () => {
  const src = readFileSync(resolve(__dirname, "../../server/cc-dispatcher.ts"), "utf8")
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/^\s*\/\/.*$/gm, "");

  it("calls mirrorBashSandboxFailure(block.output, …) exactly once, before the autonomous-posture gate", () => {
    const calls = [...src.matchAll(/\bmirrorBashSandboxFailure\(block\.output,/g)];
    expect(calls).toHaveLength(1);
    const gate = src.indexOf("if (!bashAutonomousPosture) return;", calls[0].index);
    expect(gate).toBeGreaterThan(calls[0].index!);
  });
});
