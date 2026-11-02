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
  recordCcSeccompArtifact,
  selectCommandStreamOutput,
  BASH_UNAVAILABLE_PROMPT_DIRECTIVE,
  __resetDispatcherForTests,
} from "@/server/cc-dispatcher";
import { recordSandboxPosture } from "@/server/agent-sandbox-seccomp";
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

// The wire from onToolResult to the mirror is driven behaviourally in test/cc-dispatcher-bash-notice-wire.test.ts.

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

  it("C3: the event carries the seccomp artifact the conversation's sandbox config is paired with (unixdeny / base); absent when unregistered", () => {
    const HELPER = "apply-seccomp: unshare(CLONE_NEWUSER): Operation not permitted";
    mirrorBashSandboxFailure(HELPER, USER, CONV);
    expect(mirrorSpy.mock.calls[0][1].extra).not.toHaveProperty("seccompArtifact");

    const variant = recordSandboxPosture({}, { hasEgress: false, unixDenyFlag: true });
    recordCcSeccompArtifact(USER, CONV, { sandbox: variant });
    mirrorBashSandboxFailure(HELPER, USER, CONV);
    expect(mirrorSpy.mock.calls[1][1].extra.seccompArtifact).toBe("unixdeny");

    // An egress session never uses the variant whatever the flag says.
    const egress = recordSandboxPosture({}, { hasEgress: true, unixDenyFlag: true });
    recordCcSeccompArtifact(USER, CONV, { sandbox: egress });
    mirrorBashSandboxFailure(HELPER, USER, CONV);
    expect(mirrorSpy.mock.calls[2][1].extra.seccompArtifact).toBe("base");

    // A config with no recorded posture leaves the previous entry untouched (never throws).
    expect(() => recordCcSeccompArtifact(USER, CONV, { sandbox: {} })).not.toThrow();
    __resetDispatcherForTests();
    mirrorBashSandboxFailure(HELPER, USER, CONV);
    expect(mirrorSpy.mock.calls[3][1].extra).not.toHaveProperty("seccompArtifact");
  });

  it("C3 wiring: the factory records the posture of the options it hands to the SDK, and the close paths drain the registry", () => {
    const src = readFileSync(resolve(__dirname, "../../server/cc-dispatcher.ts"), "utf8");
    // The auth-failure probe's identity wrapper is REQUIRED around the recorder (so this pin also proves the probe is bound to the
    // FINAL options), and the recorder still wraps the builder.
    expect(src).toMatch(
      /options: authProbe\.bindOptions\(recordCcSeccompArtifact\(args\.userId, args\.conversationId, buildAgentQueryOptions\(/,
    );
    expect(src.match(/_ccSeccompArtifact\.delete\(/g)?.length).toBeGreaterThanOrEqual(2);
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

  it("a single-line pre-command denial with an error result streams the fixed platform notice", () => {
    expect(selectCommandStreamOutput(LINE, true)).toBe(BASH_UNAVAILABLE_NOTICE);
    expect(selectCommandStreamOutput(`${LINE}\n`, true)).toBe(BASH_UNAVAILABLE_NOTICE);
    expect(selectCommandStreamOutput("bwrap: Can't mount proc on /newroot/proc: Operation not permitted", true)).toBe(
      BASH_UNAVAILABLE_NOTICE,
    );
    // 2026-10-19 review ruling (rationale: canary-probe-set.md, the helper-step list under "SDK Bash smoke and the helper_userns_eperm denial"): the worker-side steps that run before the tenant command are in the subset too.
    for (const step of ["fork(worker)", "prctl(PR_SET_NO_NEW_PRIVS)", "prctl(PR_SET_SECCOMP)", "execvp"]) {
      expect(selectCommandStreamOutput(`apply-seccomp: ${step}: Operation not permitted`, true), step).toBe(BASH_UNAVAILABLE_NOTICE);
    }
  });

  it("everything else passes through byte for byte: non-error, mixed, multi-line, post-fork, ordinary output", () => {
    const passthrough: Array<[string, boolean | undefined]> = [
      [LINE, false],
      [LINE, undefined],
      [`hello\n${LINE}`, true],
      [`${LINE}\nhello`, true],
      ["apply-seccomp: waitpid: Operation not permitted", true],
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

// The wire from onToolResult to the stream is driven behaviourally in test/cc-dispatcher-bash-notice-wire.test.ts
// (a source regex cannot see a comma-operator mutant of the call).

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

  it("allows ONE retry of the same command only when read-only or idempotent, else ask the user (full sentence pinned)", () => {
    expect(d).toContain(
      "You may retry the SAME command ONCE, and only if it is read-only or idempotent (it changes nothing, or running it twice is harmless); otherwise ask the user before running it again.",
    );
  });

  it("after a second failure: stop and tell the user to try again later (full sentence pinned)", () => {
    expect(d).toContain(
      "After a second failure with a sandbox error line, stop running commands, do not try again, and tell the user to try again later.",
    );
  });

  it("A2: the trigger is a FAILED Bash call whose whole output is one apply-seccomp:/bwrap: line ending in Operation not permitted (or EPERM), and not a waitpid line", () => {
    expect(d).toContain(
      "If a Bash call FAILED (its result is marked as an error) and its whole output is a single line starting with `apply-seccomp:` or `bwrap:` and ending in `Operation not permitted` (or `EPERM`), and it is not an `apply-seccomp: waitpid:` line",
    );
    // The loose old trigger ("output is a single sandbox error line") must be gone.
    expect(d).not.toContain("If a Bash call's output is a single sandbox error line");
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
