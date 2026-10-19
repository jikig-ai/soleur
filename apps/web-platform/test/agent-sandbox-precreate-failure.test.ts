// #10445: a masked dir that cannot be pre-created leaves its read-deny OFF (the SDK skips a deny landing that does not
// exist), so the failure must reach reportSilentFallback with op `masked-dir-precreate`, and the dir must STILL be in
// denyRead (the mask fails open per dir, never by dropping the entry).
import { mkdtempSync, rmSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const reported = vi.hoisted(() => [] as Array<{ op?: string; extra?: { dir?: string } }>);
vi.mock("@/server/observability", async (orig) => {
  const real = await orig<typeof import("@/server/observability")>();
  return {
    ...real,
    reportSilentFallback: (_e: unknown, o: { op?: string; extra?: { dir?: string } }) => {
      reported.push(o);
    },
  };
});

import { buildAgentSandboxConfig, peerMessagingSocketDirs } from "@/server/agent-runner-sandbox-config";

describe("masked-dir pre-create failure (#10445)", () => {
  let root: string;
  beforeEach(() => {
    root = mkdtempSync(join(tmpdir(), "sbx-precreate-"));
    reported.length = 0;
  });
  afterEach(() => {
    vi.unstubAllEnvs();
    rmSync(root, { recursive: true, force: true });
  });

  it("reports masked-dir-precreate for the dir that cannot be created and keeps it in denyRead", () => {
    // A regular FILE as the TMPDIR base makes `<base>/cc-socks` fail with ENOTDIR.
    const notADir = join(root, "file");
    writeFileSync(notADir, "");
    vi.stubEnv("TMPDIR", notADir);
    vi.stubEnv("WORKSPACES_ROOT", root);
    const cfg = buildAgentSandboxConfig(join(root, "00000000-0000-0000-0000-000000000001"));
    const bad = join(notADir, "cc-socks");
    expect(peerMessagingSocketDirs()).toContain(bad);
    expect(reported.some((o) => o.op === "masked-dir-precreate" && o.extra?.dir === bad)).toBe(true);
    expect(cfg.filesystem.denyRead).toContain(bad);
  });
});
