// WikiSkill Phase 2 (#10550), verification pass -- `runGit`'s evidence mapping against a FAKE `execFile`.
//
// The real-git tests (compound-promote-create-gates.test.ts, the persist suite) cannot make git die with an odd signal
// name, overflow its buffer on demand, or show which options reached `execFile`. This suite replaces `execFile` and
// feeds `runGit` the Error shapes Node produces, then asserts the closed evidence that comes back and the closed extra
// that reaches Sentry, plus the options handed to `execFile` (the timeout clamp is observable ONLY there).
import { beforeEach, describe, expect, it, vi } from "vitest";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

type FakeErr = { code?: unknown; signal?: unknown; killed?: unknown } | null;
const h = vi.hoisted(() => ({
  calls: [] as Array<{ file: string; args: string[]; opts: Record<string, unknown> }>,
  next: { err: null, stdout: "" } as { err: unknown; stdout: string },
}));

vi.mock("node:child_process", async (importOriginal) => ({
  ...(await importOriginal<typeof import("node:child_process")>()),
  execFile: (file: string, args: string[], opts: Record<string, unknown>, cb: (err: FakeErr, stdout: string, stderr: string) => void) => {
    h.calls.push({ file, args, opts });
    cb(h.next.err as FakeErr, h.next.stdout, "");
    return {} as never;
  },
}));
vi.mock("@/server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/observability")>()),
  reportSilentFallback: vi.fn(),
}));
import { reportSilentFallback } from "@/server/observability";
import { GIT_MAX_TIMEOUT_MS, GIT_TIMEOUT_MS, runGit } from "@/server/compound-promote-create-gates";
import { GIT_HARDENING_ARGS } from "@/server/inngest/functions/_git-hardening";

const baseEnv = { PATH: "/usr/bin:/bin" };
const lastExtra = (): Record<string, unknown> => vi.mocked(reportSilentFallback).mock.calls.at(-1)?.[1]?.extra as Record<string, unknown>;

beforeEach(() => {
  expect.hasAssertions();
  h.calls.length = 0;
  h.next = { err: null, stdout: "" };
  vi.mocked(reportSilentFallback).mockClear();
});

describe("runGit evidence mapping (fake execFile)", () => {
  it("success returns stdout and mirrors nothing", async () => {
    h.next = { err: null, stdout: "abc\n" };
    expect(await runGit("/r", ["status"], { baseEnv })).toEqual({ ok: true, stdout: "abc\n" });
    expect(reportSilentFallback).not.toHaveBeenCalled();
  });

  it("a numeric exit code is `exit`; a non-integer or string code (an errno) is NOT an exit status", async () => {
    h.next = { err: { code: 128, killed: false, signal: null }, stdout: "" };
    expect(await runGit("/r", ["fetch"], { baseEnv })).toEqual({ ok: false, exit: 128, timedOut: false });
    expect(lastExtra()).toEqual({ sub: "fetch", exit: 128, killed: false, timedOut: false });
    h.next = { err: { code: "ENOENT", killed: false, signal: null }, stdout: "" };
    expect(await runGit("/r", ["fetch"], { baseEnv })).toEqual({ ok: false, timedOut: false });
    h.next = { err: { code: 1.5, killed: false, signal: null }, stdout: "" };
    expect(await runGit("/r", ["fetch"], { baseEnv })).toEqual({ ok: false, timedOut: false });
  });

  it("a signal whose name is not SIG<NAME> is reported as `other`, never echoed", async () => {
    h.next = { err: { code: null, killed: false, signal: "weird signal; rm -rf" }, stdout: "" };
    const r = await runGit("/r", ["fetch"], { baseEnv });
    expect(r).toEqual({ ok: false, signal: "other", timedOut: false });
    expect(lastExtra()).toEqual({ sub: "fetch", signal: "other", killed: false, timedOut: false });
    expect(JSON.stringify(vi.mocked(reportSilentFallback).mock.calls.map((c) => c[1]))).not.toContain("weird");
    // a real signal name keeps its name; an empty string is no signal
    h.next = { err: { code: null, killed: false, signal: "SIGKILL" }, stdout: "" };
    expect(await runGit("/r", ["fetch"], { baseEnv })).toEqual({ ok: false, signal: "SIGKILL", timedOut: false });
    h.next = { err: { code: null, killed: false, signal: "" }, stdout: "" };
    expect(await runGit("/r", ["fetch"], { baseEnv })).toEqual({ ok: false, timedOut: false });
  });

  it("a timeout kill (killed + SIGTERM) is timedOut:true", async () => {
    h.next = { err: { code: null, killed: true, signal: "SIGTERM" }, stdout: "" };
    expect(await runGit("/r", ["fetch"], { baseEnv })).toEqual({ ok: false, signal: "SIGTERM", timedOut: true });
    expect(lastExtra()).toEqual({ sub: "fetch", signal: "SIGTERM", killed: true, timedOut: true });
  });

  it("a maxBuffer overflow is killed + SIGTERM too but is NOT a timeout", async () => {
    h.next = { err: { code: "ERR_CHILD_PROCESS_STDIO_MAXBUFFER", killed: true, signal: "SIGTERM" }, stdout: "" };
    expect(await runGit("/r", ["ls-tree", "HEAD"], { baseEnv })).toEqual({ ok: false, signal: "SIGTERM", timedOut: false });
    expect(lastExtra()).toEqual({ sub: "ls-tree", signal: "SIGTERM", killed: true, timedOut: false });
  });

  it("killed by a signal other than SIGTERM is not a timeout either", async () => {
    h.next = { err: { code: null, killed: true, signal: "SIGKILL" }, stdout: "" };
    expect(await runGit("/r", ["fetch"], { baseEnv })).toMatchObject({ ok: false, signal: "SIGKILL", timedOut: false });
  });

  it("the Sentry `sub` is the first argument only when it is a plain lower-case token; anything else is `other`", async () => {
    h.next = { err: { code: 1 }, stdout: "" };
    for (const [args, sub] of [
      [["rev-parse", "x"], "rev-parse"],
      [["ls-remote"], "ls-remote"],
      [["Fetch"], "other"],
      [["-c", "x=y", "fetch"], "other"],
      [["a".repeat(30)], "other"],
      [["fetch origin"], "other"],
      [[], "other"],
    ] as const) {
      await runGit("/r", [...args], { baseEnv });
      expect(lastExtra().sub, JSON.stringify(args)).toBe(sub);
    }
  });

  it("the synthetic Error names only the sub, never the arguments or the root", async () => {
    h.next = { err: { code: 128 }, stdout: "" };
    await runGit("/some/root-with-a-token-name", ["fetch", "https://x-access-token:abc@example.invalid/o/r.git"], { baseEnv });
    const [err] = vi.mocked(reportSilentFallback).mock.calls.at(-1) as [Error, unknown];
    expect(err.message).toBe("git fetch failed");
  });
});

describe("runGit options reach execFile (the clamp is applied THROUGH the timeout option)", () => {
  it.each([
    [undefined, GIT_TIMEOUT_MS],
    [0, 1],
    [-50, 1],
    [5, 5],
    [GIT_MAX_TIMEOUT_MS, GIT_MAX_TIMEOUT_MS],
    [10 * GIT_MAX_TIMEOUT_MS, GIT_MAX_TIMEOUT_MS],
  ] as const)("timeoutMs %s -> execFile timeout %i", async (requested, expected) => {
    await runGit("/r", ["status"], { baseEnv, ...(requested === undefined ? {} : { timeoutMs: requested }) });
    expect(h.calls).toHaveLength(1);
    expect(h.calls[0].opts.timeout).toBe(expected);
  });

  it("the invocation is `git <hardening args> -C <root> <args>` with a bounded buffer, utf8, and a scrubbed env carrying no GIT_DIR", async () => {
    await runGit("/the/root", ["rev-parse", "HEAD"], { baseEnv: { ...baseEnv, GIT_DIR: "/elsewhere", GH_TOKEN: "t" } as never });
    const c = h.calls[0];
    expect(c.file).toBe("git");
    expect(c.args).toEqual([...GIT_HARDENING_ARGS, "-C", "/the/root", "rev-parse", "HEAD"]);
    expect(c.opts).toMatchObject({ maxBuffer: 16 * 1024 * 1024, encoding: "utf8" });
    const env = c.opts.env as Record<string, string>;
    expect(env.GIT_DIR).toBeUndefined();
    expect(env.GH_TOKEN).toBeUndefined();
    expect(env.GIT_TERMINAL_PROMPT).toBe("0");
  });
});
