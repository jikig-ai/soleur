import { readFileSync } from "node:fs";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { describe, expect, it } from "vitest";
import { stripComments } from "./helpers/strip-comments";

/**
 * Playwright's `webServer` entries report a mid-run dev-server death as bare
 * net::ERR_CONNECTION_REFUSED — no exit code, no signal, no timestamp — so a
 * server that goes away mid-suite reads as a cascade of undiagnosable reds
 * (#9167; merge-group run 37435711833). `e2e/web-server.sh` wraps the dev
 * command, `wait`s on the child, and emits
 * `e2e-webserver: exited rc=<n> port=<PORT> distdir=<NEXT_DIST_DIR> uptime=<s>`
 * on the child's exit. rc is 128+N on death-by-signal N (137=SIGKILL, the
 * OOM signature).
 *
 * Config assertions read playwright.config.ts as TEXT with comments stripped —
 * a commented-out `command:`/`name:` line must not satisfy them
 * (cq-assert-anchor-not-bare-token, same convention as
 * playwright-dev-server-distdir.test.ts).
 */

const SCRIPT = join(__dirname, "..", "e2e", "web-server.sh");

const run = (args: string[], env: NodeJS.ProcessEnv = {}) =>
  spawnSync("bash", [SCRIPT, ...args], { env: { ...process.env, ...env }, encoding: "utf-8" });

describe("e2e/web-server.sh exit marker", () => {
  it("passes the child's clean exit through and marks rc=0 on stderr", () => {
    const r = run(["true"]);
    expect(r.status).toBe(0);
    expect(r.stderr).toContain("e2e-webserver: exited rc=0");
  });

  it("passes a non-zero child rc through unchanged", () => {
    const r = run(["bash", "-c", "exit 42"]);
    expect(r.status).toBe(42);
    expect(r.stderr).toContain("e2e-webserver: exited rc=42");
  });

  it("encodes death-by-signal as 128+N (self-SIGKILL → 137, the OOM signature)", () => {
    const r = run(["bash", "-c", "kill -9 $$"]);
    expect(r.status).toBe(137);
    expect(r.stderr).toContain("e2e-webserver: exited rc=137");
  });

  it("carries port=, distdir= and uptime= fields from the environment", () => {
    const r = run(["true"], { PORT: "3101", NEXT_DIST_DIR: ".next/e2e-x" });
    expect(r.stderr).toContain("port=3101");
    expect(r.stderr).toContain("distdir=.next/e2e-x");
    expect(r.stderr).toMatch(/uptime=\d+s/);
  });

  it("refuses a bare invocation with usage on stderr and rc 2", () => {
    const r = run([]);
    expect(r.status).toBe(2);
    expect(r.stderr).toContain("usage:");
  });

  it("--selftest runs the real spawn+wait+marker path and emits on stdout", () => {
    const r = run(["--selftest"]);
    expect(r.status).toBe(0);
    expect(r.stdout).toContain("e2e-webserver: exited rc=0");
  });
});

describe("playwright.config.ts webServer wiring", () => {
  const playwright = stripComments(
    readFileSync(join(__dirname, "..", "playwright.config.ts"), "utf-8"),
  );
  const webServerBlock = playwright.slice(playwright.indexOf("webServer:"));
  const entries = webServerBlock.split(/\bcommand:\s/).slice(1);

  it("routes every webServer entry's command through e2e/web-server.sh", () => {
    expect(entries.length).toBeGreaterThanOrEqual(2);
    for (const entry of entries) {
      expect(entry.slice(0, entry.indexOf("\n"))).toContain("e2e/web-server.sh");
    }
  });

  it("gives every webServer entry a distinct name: so each piped line is attributable", () => {
    // Field order inside an entry is free (`name:` may precede `command:`), so
    // names are counted across the whole block, not per `command:` segment.
    const names = [...webServerBlock.matchAll(/\bname:\s*"([^"]+)"/g)].map((m) => m[1]);
    expect(names).toHaveLength(entries.length);
    expect(new Set(names).size).toBe(entries.length);
  });
});
