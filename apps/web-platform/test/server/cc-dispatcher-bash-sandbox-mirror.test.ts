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

import {
  mirrorBashSandboxFailure,
  selectCommandStreamOutput,
  BASH_UNAVAILABLE_PROMPT_DIRECTIVE,
} from "@/server/cc-dispatcher";
import { BASH_UNAVAILABLE_NOTICE } from "@/server/sandbox-startup-classifier";

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
    expect(errorClass).toBe("agent-sandbox-bash-tool-result:proc_mount_eperm");
  });

  it("#10445: the apply-seccomp helper line flows through with sandboxErrorCode=helper_userns_eperm (the alert's needle)", () => {
    const HELPER = "apply-seccomp: unshare(CLONE_NEWUSER): Operation not permitted";
    mirrorBashSandboxFailure(`ok\n${HELPER}\n`, USER, CONV);
    expect(mirrorSpy).toHaveBeenCalledTimes(1);
    const [err, ctx] = mirrorSpy.mock.calls[0];
    expect(err).toBeNull();
    expect(ctx.feature).toBe("agent-sandbox");
    expect(ctx.op).toBe("bash-tool-result");
    expect(ctx.message).toBe("bash sandbox denial: helper_userns_eperm");
    expect(ctx.extra.sandboxErrorCode).toBe("helper_userns_eperm");
    expect(ctx.extra.sandboxStderr).toBe(HELPER);
  });

  it("#10445: the debounce slot is per error code, so another code cannot consume the helper row's slot", () => {
    const HELPER = "apply-seccomp: unshare(CLONE_NEWUSER): Operation not permitted";
    mirrorBashSandboxFailure(PROC_EPERM, USER, CONV);
    mirrorBashSandboxFailure(HELPER, USER, CONV);
    const classes = mirrorSpy.mock.calls.map((c) => c[3]);
    expect(classes).toEqual([
      "agent-sandbox-bash-tool-result:proc_mount_eperm",
      "agent-sandbox-bash-tool-result:helper_userns_eperm",
    ]);
    expect(new Set(classes).size).toBe(2);
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

// #10455 e — another helper step failing with EPERM is mirrored under its own code, and the alert pages on both.
describe("mirrorBashSandboxFailure — helper_step_eperm (#10455 e)", () => {
  const STEP_LINE = "apply-seccomp: prctl(PR_CAP_AMBIENT_CLEAR_ALL): Operation not permitted";
  const USERNS_LINE = "apply-seccomp: unshare(CLONE_NEWUSER): Operation not permitted";
  beforeEach(() => mirrorSpy.mockClear());

  it("emits one event with sandboxErrorCode=helper_step_eperm and only the fixed matched line", () => {
    mirrorBashSandboxFailure(`ok\n${STEP_LINE}\n`, USER, CONV);
    expect(mirrorSpy).toHaveBeenCalledTimes(1);
    const [err, ctx, userId, errorClass] = mirrorSpy.mock.calls[0];
    expect(err).toBeNull();
    expect(ctx.feature).toBe("agent-sandbox");
    expect(ctx.op).toBe("bash-tool-result");
    expect(ctx.message).toBe("bash sandbox denial: helper_step_eperm");
    expect(ctx.extra.sandboxErrorCode).toBe("helper_step_eperm");
    expect(ctx.extra.sandboxStderr).toBe(STEP_LINE);
    expect(userId).toBe(USER);
    expect(errorClass).toBe("agent-sandbox-bash-tool-result:helper_step_eperm");
  });

  it("the two helper codes have separate debounce slots (one cannot consume the other's page)", () => {
    mirrorBashSandboxFailure(STEP_LINE, USER, CONV);
    mirrorBashSandboxFailure(USERNS_LINE, USER, CONV);
    expect(mirrorSpy.mock.calls.map((c) => c[3])).toEqual([
      "agent-sandbox-bash-tool-result:helper_step_eperm",
      "agent-sandbox-bash-tool-result:helper_userns_eperm",
    ]);
  });

  it("the mirror still fires for a post-fork step line (it pages) even though the notice never rewrites it", () => {
    mirrorBashSandboxFailure("apply-seccomp: waitpid: Operation not permitted", USER, CONV);
    expect(mirrorSpy).toHaveBeenCalledTimes(1);
    expect(mirrorSpy.mock.calls[0][1].extra.sandboxErrorCode).toBe("helper_step_eperm");
  });
});

// #10455 c — the streamed command output becomes the platform notice only for a qualifying result.
describe("selectCommandStreamOutput — the streamed text (#10455 c)", () => {
  const LINE = "apply-seccomp: unshare(CLONE_NEWUSER): Operation not permitted";

  it("a single-line pre-fork denial with an error result streams the fixed platform notice", () => {
    expect(selectCommandStreamOutput(LINE, true)).toBe(BASH_UNAVAILABLE_NOTICE);
    expect(selectCommandStreamOutput(`${LINE}\n`, true)).toBe(BASH_UNAVAILABLE_NOTICE);
    expect(selectCommandStreamOutput("bwrap: Can't mount proc on /newroot/proc: Operation not permitted", true)).toBe(
      BASH_UNAVAILABLE_NOTICE,
    );
  });

  it("everything else passes through byte for byte: non-error, mixed, multi-line, post-fork, ordinary output", () => {
    const passthrough: Array<[string, boolean | undefined]> = [
      [LINE, false],
      [LINE, undefined],
      [`hello\n${LINE}`, true],
      [`${LINE}\nhello`, true],
      ["apply-seccomp: waitpid: Operation not permitted", true],
      ["apply-seccomp: fork(worker): Operation not permitted", true],
      ["On branch main\n", true],
      ["", true],
    ];
    for (const [out, isError] of passthrough) {
      expect(selectCommandStreamOutput(out, isError), JSON.stringify([out, isError])).toBe(out);
    }
  });

  it("forged-line negative: a command that ran and printed the line with a non-error result is NOT rewritten", () => {
    expect(selectCommandStreamOutput(`done\n${LINE}`, false)).toBe(`done\n${LINE}`);
  });
});

// The wire between the helpers and the observer: a helper test cannot see a deleted or misplaced call.
describe("onToolResult streams through selectCommandStreamOutput (call-site pin)", () => {
  const src = readFileSync(resolve(__dirname, "../../server/cc-dispatcher.ts"), "utf8")
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/^\s*\/\/.*$/gm, "");

  it("rewrites ONLY on the command_stream path: after the mirror call and after the autonomous-posture gate", () => {
    const calls = [...src.matchAll(/\bselectCommandStreamOutput\(block\.output, block\.isError\)/g)];
    expect(calls).toHaveLength(1);
    const mirror = src.indexOf("mirrorBashSandboxFailure(block.output,");
    const gate = src.indexOf("if (!bashAutonomousPosture) return;");
    expect(mirror).toBeGreaterThan(-1);
    expect(gate).toBeGreaterThan(mirror);
    expect(calls[0].index).toBeGreaterThan(gate);
  });

  it("the mirror reads the RAW output, never the rewritten text", () => {
    expect(src).toMatch(/mirrorBashSandboxFailure\(block\.output,/);
    expect(src).not.toMatch(/mirrorBashSandboxFailure\(selectCommandStreamOutput/);
  });
});

// The SDK-visible tool_result cannot be rewritten (no hook), so the model sees the RAW line: the directive keys on it.
describe("BASH_UNAVAILABLE_PROMPT_DIRECTIVE (#10455 c)", () => {
  const raw = readFileSync(resolve(__dirname, "../../server/cc-dispatcher.ts"), "utf8");
  const d = BASH_UNAVAILABLE_PROMPT_DIRECTIVE;

  it("keys on the RAW helper / bwrap error line the model actually sees, not on the notice text", () => {
    expect(d).toMatch(/apply-seccomp:/);
    expect(d).toMatch(/bwrap:/);
    expect(d).not.toContain(BASH_UNAVAILABLE_NOTICE);
  });

  it("tells the model not to echo raw sandbox text, and carves out the 403 directive's verbatim rule", () => {
    expect(d).toMatch(/do not (?:quote|repeat|echo|paste)/i);
    expect(d).toMatch(/verbatim/i);
    expect(d).toMatch(/takes precedence|overrides|exception/i);
  });

  it("allows ONE retry of the same command only when read-only or idempotent, else ask the user", () => {
    expect(d).toMatch(/once/i);
    expect(d).toMatch(/read-only|idempotent/i);
    expect(d).toMatch(/ask the user/i);
  });

  it("after a second failure: stop and tell the user to try again later", () => {
    expect(d).toMatch(/second|again fails|fails again/i);
    expect(d).toMatch(/stop/i);
    expect(d).toMatch(/try again later/i);
  });

  it("never claims the command did not run", () => {
    expect(d).not.toMatch(/did not run|never ran|was not executed/i);
  });

  it("is declared beside GH_403_PROMPT_DIRECTIVE and appended right after it, unconditionally", () => {
    expect(raw.indexOf("const BASH_UNAVAILABLE_PROMPT_DIRECTIVE")).toBeGreaterThan(raw.indexOf("const GH_403_PROMPT_DIRECTIVE"));
    expect(raw).toMatch(
      /effectiveSystemPrompt \+= `\\n\\n\$\{GH_403_PROMPT_DIRECTIVE\}`;\s*(?:\/\/[^\n]*\n\s*)*effectiveSystemPrompt \+= `\\n\\n\$\{BASH_UNAVAILABLE_PROMPT_DIRECTIVE\}`;/,
    );
  });
});
