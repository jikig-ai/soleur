import { describe, expect, it, vi } from "vitest";
import { createCodexAppServerLauncher } from "@/server/codex-app-server-launcher";

describe("Codex App Server launcher contract", () => {
  it("passes only the fixed stdio command and injected environment", async () => {
    const child = {
      stdin: { write: vi.fn((_chunk: string, cb: () => void) => cb()) },
      stdout: (async function* () {})(),
      stderr: (async function* () {})(),
      kill: vi.fn(() => true),
      once: vi.fn(),
      on: vi.fn(),
    };
    const spawn = vi.fn(() => child);
    const launcher = createCodexAppServerLauncher({
      command: "/opt/codex/bin/codex",
      spawn,
      environment: (lease) => ({ CODEX_ACCESS_TOKEN: lease.accessToken }),
      cwd: "/srv/soleur",
    });

    const process = await launcher.spawn({ accessToken: "opaque", expiresAt: Date.now() + 60_000 });
    expect(spawn).toHaveBeenCalledWith(
      "/opt/codex/bin/codex",
      ["app-server", "--stdio"],
      expect.objectContaining({ cwd: "/srv/soleur", env: { CODEX_ACCESS_TOKEN: "opaque" } }),
    );
    await process.kill();
    expect(child.kill).toHaveBeenCalledWith("SIGTERM");
  });
});
