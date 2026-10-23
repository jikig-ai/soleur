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
  });
  afterEach(() => {
    vi.unstubAllEnvs();
    rmSync(root, { recursive: true, force: true });
  });

  it("a forced peer-socket failure is captured ONCE as a tagged message, with no pino-mirror exception beside it", () => {
    const notADir = join(root, "file");
    writeFileSync(notADir, "");
    vi.stubEnv("TMPDIR", notADir);
    vi.stubEnv("WORKSPACES_ROOT", root);
    buildAgentSandboxConfig(join(root, "00000000-0000-0000-0000-000000000003"));

    const msgs = maskedMessages();
    expect(msgs).toHaveLength(1);
    const [message, opts] = msgs[0];
    expect(opts.tags).toMatchObject({ feature: "agent-sandbox", op: "masked-dir-precreate", dir_kind: "peer-socket" });
    expect(opts.level).toBe("error");
    expect(message).toBe("agent-sandbox: peer-socket masked dir could not be created; its read-deny may not apply");
    expect(message).not.toContain(root);
    expect(opts.extra).toMatchObject({ dir: join(notADir, "cc-socks"), code: "ENOTDIR", syscall: "mkdir" });
    // The defect this test exists for: no Error reached the pino mirror, so there is nothing to dedupe behind.
    expect(pinoMirrorCaptures()).toHaveLength(0);
    expect(
      (sentry.captureException.mock.calls as unknown[][]).filter((c) => (c[1] as { tags?: { op?: string } })?.tags?.op === "masked-dir-precreate"),
    ).toHaveLength(0);
  });

  it("CONTROL: the instrument can see the defect: an Error first argument does produce a feature=pino-mirror capture", () => {
    reportSilentFallback(new Error("boom"), { feature: "agent-sandbox", op: "masked-dir-precreate", tags: { dir_kind: "transcript" } });
    expect(pinoMirrorCaptures().length).toBeGreaterThanOrEqual(1);
  });
});
