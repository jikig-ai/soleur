import { describe, it, expect } from "vitest";
import { spawnSync } from "node:child_process";
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

// #9600: the agent-env config-carrier pin (`safe.bareRepository=explicit`) is a no-op on git older
// than 2.38, so the runner image asserts the floor at BUILD time. This test executes the Dockerfile's
// own assertion against a shimmed `git --version`, so lowering the literal, deleting the RUN or
// weakening the comparison turns it RED.
const dockerfile = readFileSync(path.resolve(__dirname, "..", "Dockerfile"), "utf8");

/** The runner stage: from `FROM … AS runner` to the next `FROM` (or end of file). */
function runnerStage(src: string): string {
  const start = src.search(/^FROM\s+\S+\s+AS\s+runner\s*$/m);
  if (start === -1) throw new Error("Dockerfile has no `FROM … AS runner` stage");
  const rest = src.slice(start + 1);
  const next = rest.search(/^FROM\s/m);
  return next === -1 ? src.slice(start) : src.slice(start, start + 1 + next);
}

/** The shell body of the floor assertion: the `RUN git --version …` instruction, continuations joined. */
function floorAssertion(stage: string): string | undefined {
  const joined = stage.replace(/^\s*#.*$/gm, "").replace(/\\\n\s*/g, " ");
  const m = joined.match(/^RUN (git --version [^\n]+)$/m);
  return m?.[1];
}

function runWithGit(body: string, versionLine: string): { status: number | null; stderr: string } {
  const dir = mkdtempSync(path.join(tmpdir(), "gitfloor-"));
  try {
    writeFileSync(path.join(dir, "git"), `#!/bin/sh\necho '${versionLine}'\n`);
    chmodSync(path.join(dir, "git"), 0o755);
    const r = spawnSync("sh", ["-c", body], {
      env: { PATH: `${dir}:/usr/bin:/bin`, NODE_ENV: "test" },
      encoding: "utf8",
    });
    return { status: r.status, stderr: r.stderr };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

describe("runner image asserts git >= 2.38 at build time (#9600)", () => {
  const body = floorAssertion(runnerStage(dockerfile));

  it("the runner stage carries the assertion, and it pins 2.38", () => {
    expect(body, "Dockerfile runner stage lost its `RUN git --version …` floor assertion").toBeDefined();
    expect(body).toMatch(/v\[2\] \+ 0 >= 38/);
  });

  it("a comment mentioning the floor does not satisfy the guard", () => {
    const fake = "FROM x AS runner\n# RUN git --version | awk 'x'\nRUN apt-get install -y git\n";
    expect(floorAssertion(runnerStage(fake))).toBeUndefined();
  });

  const OK = ["git version 2.38.0", "git version 2.39.5", "git version 2.47.3", "git version 2.56.0", "git version 3.0.0", "git version 2.100.1"];
  const BAD = ["git version 2.37.9", "git version 2.34.1", "git version 2.30.2", "git version 1.9.5", "git version 2.9.0"];

  it.each(OK)("passes on %s", (v) => {
    expect(runWithGit(body!, v).status).toBe(0);
  });

  it.each(BAD)("fails the build on %s and names the cause", (v) => {
    const r = runWithGit(body!, v);
    expect(r.status).not.toBe(0);
    expect(r.stderr).toContain("safe.bareRepository pin would be inert");
  });
});
