// #10455 (PR-B): the REAL-PATH proof for the masked-dir-precreate alert. agent-sandbox-precreate-failure.test.ts mocks
// reportSilentFallback, so it cannot see the #8629-class defect: with an Error first argument the REAL pino logger
// mirrors `logger.error({ err })` to Sentry.captureException(err, { tags: { feature: "pino-mirror" } }) and Sentry drops the
// second, tagged capture, so a rule filtering feature=agent-sandbox AND op=masked-dir-precreate could never match.
// Here the logger and reportSilentFallback are REAL; only the Sentry SDK is replaced by spies.
import { mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const sentry = vi.hoisted(() => ({
  captureMessage: vi.fn(),
  captureException: vi.fn(),
  addBreadcrumb: vi.fn(),
}));
vi.mock("@sentry/nextjs", async (orig) => {
  const real = await orig<typeof import("@sentry/nextjs")>();
  return { ...real, ...sentry };
});

// Passthrough `mkdirSync` that fails for chosen paths: the session-tmp root is the constant `/tmp/.cs`, so it cannot be forced to fail
// through the environment (and a test must never leave a file at the real /tmp/.cs).
const failMkdir = vi.hoisted(() => new Map<string, string>());
vi.mock("fs", async (orig) => {
  const real = await orig<typeof import("fs")>();
  return {
    ...real,
    mkdirSync: ((dir: string, opts: unknown) => {
      const code = failMkdir.get(String(dir));
      if (code) throw Object.assign(new Error(`${code}: mkdir '${dir}'`), { code, syscall: "mkdir" });
      return (real.mkdirSync as (d: string, o: unknown) => unknown)(dir, opts);
    }) as typeof real.mkdirSync,
  };
});

import { AGENT_SESSION_TMP_ROOT } from "@/server/agent-session-tmp";
import { buildAgentSandboxConfig } from "@/server/agent-runner-sandbox-config";
import { reportSilentFallback } from "@/server/observability";

type Call = [string, { level?: string; tags?: Record<string, string>; extra?: Record<string, unknown> }];
const maskedMessages = () =>
  (sentry.captureMessage.mock.calls as Call[]).filter(([, o]) => o?.tags?.op === "masked-dir-precreate");
const pinoMirrorCaptures = () =>
  (sentry.captureException.mock.calls as Array<[unknown, { tags?: Record<string, string> }?]>).filter(
    ([, o]) => o?.tags?.feature === "pino-mirror",
  );

describe("masked-dir-precreate over the real logger and the real reportSilentFallback", () => {
  let root: string;
  beforeEach(() => {
    root = mkdtempSync(join(tmpdir(), "sbx-sentry-path-"));
    for (const f of Object.values(sentry)) f.mockClear();
    failMkdir.clear();
  });
  afterEach(() => {
    vi.unstubAllEnvs();
    rmSync(root, { recursive: true, force: true });
  });

  // One forced failure per dir_kind (the rule's closed three-value tag): the same real-path invariant for each.
  const kinds: Array<{ kind: string; force: () => string; code: RegExp }> = [
    {
      kind: "peer-socket",
      // A regular FILE as the TMPDIR base makes `<base>/cc-socks` fail with ENOTDIR.
      force: () => {
        const notADir = join(root, "file");
        writeFileSync(notADir, "");
        vi.stubEnv("TMPDIR", notADir);
        return join(notADir, "cc-socks");
      },
      code: /^ENOTDIR$/,
    },
    {
      kind: "transcript",
      // A HOME that is a file makes `<HOME>/.claude/projects` fail (ENOTDIR, or EEXIST when mkdir -p meets the file first).
      force: () => {
        const notADir = join(root, "homefile");
        writeFileSync(notADir, "");
        vi.stubEnv("HOME", notADir);
        vi.stubEnv("CLAUDE_CONFIG_DIR", "");
        return join(notADir, ".claude", "projects");
      },
      code: /^(ENOTDIR|EEXIST)$/,
    },
    {
      kind: "session-tmp",
      force: () => {
        failMkdir.set(AGENT_SESSION_TMP_ROOT, "ENOSPC");
        return AGENT_SESSION_TMP_ROOT;
      },
      code: /^ENOSPC$/,
    },
  ];

  for (const { kind, force, code } of kinds) {
    it(`a forced ${kind} failure is captured ONCE as a tagged message, with no pino-mirror exception beside it`, () => {
      vi.stubEnv("WORKSPACES_ROOT", root);
      const failing = force();
      buildAgentSandboxConfig(join(root, "00000000-0000-0000-0000-000000000003"));

      const msgs = maskedMessages();
      expect(msgs).toHaveLength(1);
      const [message, opts] = msgs[0];
      expect(opts.tags).toMatchObject({ feature: "agent-sandbox", op: "masked-dir-precreate", dir_kind: kind });
      expect(opts.level).toBe("error");
      expect(message).toBe(`agent-sandbox: ${kind} masked dir could not be created; its read-deny may not apply`);
      expect(message).not.toContain(root);
      expect(opts.extra).toMatchObject({ dir: failing, syscall: "mkdir" });
      expect(String(opts.extra?.code)).toMatch(code);
      // The defect this test exists for: no Error reached the pino mirror, so there is nothing to dedupe behind.
      expect(pinoMirrorCaptures()).toHaveLength(0);
      expect(
        (sentry.captureException.mock.calls as unknown[][]).filter((c) => (c[1] as { tags?: { op?: string } })?.tags?.op === "masked-dir-precreate"),
      ).toHaveLength(0);
    });
  }

  it("CONTROL: the instrument can see the defect: an Error first argument does produce a feature=pino-mirror capture", () => {
    reportSilentFallback(new Error("boom"), { feature: "agent-sandbox", op: "masked-dir-precreate", tags: { dir_kind: "transcript" } });
    expect(pinoMirrorCaptures().length).toBeGreaterThanOrEqual(1);
  });
});
