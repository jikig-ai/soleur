import { describe, it, expect } from "vitest";
import { spawnSync } from "node:child_process";
import { AGENT_GIT_GLOBAL_CONFIG } from "../server/agent-env";
import { chmodSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
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

function runWithGit(body: string, versionLine: string | null): { status: number | null; stderr: string } {
  const dir = mkdtempSync(path.join(tmpdir(), "gitfloor-"));
  try {
    // null = a git that prints NOTHING to stdout (zero lines), the case where awk's main rule never runs
    writeFileSync(path.join(dir, "git"), versionLine === null ? "#!/bin/sh\nexit 0\n" : `#!/bin/sh\necho '${versionLine}'\n`);
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

  it("fails the build when git prints NOTHING (a pipeline's status is awk's, and awk exits 0 on empty input)", () => {
    const r = runWithGit(body!, null);
    expect(r.status).not.toBe(0);
    expect(r.stderr).toContain("safe.bareRepository pin would be inert");
  });

  it.each(BAD)("fails the build on %s and names the cause", (v) => {
    const r = runWithGit(body!, v);
    expect(r.status).not.toBe(0);
    expect(r.stderr).toContain("safe.bareRepository pin would be inert");
  });
});

// The agent session pins GIT_CONFIG_GLOBAL at an image-owned identity file (server/agent-env.ts) so HOME's
// writable ~/.gitconfig is never read. These tests EXECUTE the Dockerfile's own RUN that creates it (with the
// destination redirected to a temp dir) and then prove, with real git, that a session with no local identity
// can commit while one with a local identity keeps it.
describe("runner image ships the agent identity-only gitconfig (#9600)", () => {
  const joined = runnerStage(dockerfile).replace(/^\s*#.*$/gm, "").replace(/\\\n\s*/g, " ");
  const run = joined.match(/^RUN (mkdir -p \/usr\/local\/share\/soleur [^\n]+)$/m)?.[1];

  it("the Dockerfile creates exactly the path the agent env points GIT_CONFIG_GLOBAL at", () => {
    expect(run, "Dockerfile lost the agent.gitconfig RUN").toBeDefined();
    expect(run).toContain(AGENT_GIT_GLOBAL_CONFIG);
  });

  it("the build proves the identity comes FROM the file, and the HOME global identity (kept equal for any other process in the image) is the same one", () => {
    expect(run).toContain("git var GIT_AUTHOR_IDENT");
    expect(run).toContain('= "github-actions[bot]"');
    const home = joined.match(/git config --global user\.name "([^"]+)"\s+&&\s+git config --global user\.email "([^"]+)"/);
    expect(home, "Dockerfile lost the HOME global identity lines").not.toBeNull();
    expect(run).toContain(`name = ${home![1]}`);
    expect(run).toContain(`email = ${home![2]}`);
  });

  function build(): { dir: string; file: string; cleanup: () => void } {
    const dir = mkdtempSync(path.join(tmpdir(), "agentcfg-"));
    const script = run!.split("/usr/local/share/soleur").join(dir);
    const r = spawnSync("sh", ["-c", script], {
      cwd: dir, // not inside any repository: a repo-local identity would beat the file under test
      env: { PATH: "/usr/bin:/bin", HOME: dir, NODE_ENV: "test" },
      encoding: "utf8",
    });
    expect(r.status, `identity RUN failed: ${r.stderr}`).toBe(0);
    return { dir, file: path.join(dir, "agent.gitconfig"), cleanup: () => rmSync(dir, { recursive: true, force: true }) };
  }

  const git = (cwd: string, env: Record<string, string>, ...args: string[]) =>
    spawnSync("git", args, { cwd, env: { PATH: "/usr/bin:/bin", HOME: cwd, NODE_ENV: "test", GIT_CONFIG_NOSYSTEM: "1", ...env }, encoding: "utf8" });

  it("identity-only content (nothing but [user] name and email), world-readable", () => {
    const b = build();
    try {
      const text = readFileSync(b.file, "utf8");
      expect(text).toMatch(/^\[user\]\n\tname = [^\n]+\n\temail = [^\n]+\n$/);
      expect(statSync(b.file).mode & 0o044).toBe(0o044);
    } finally {
      b.cleanup();
    }
  });

  it("a Start-Fresh style repo with NO local identity can commit under the pinned global file (and cannot under /dev/null)", () => {
    const b = build();
    const repo = mkdtempSync(path.join(tmpdir(), "agentrepo-"));
    try {
      expect(git(repo, {}, "init", "-q", "-b", "main").status).toBe(0);
      writeFileSync(path.join(repo, "f.txt"), "x\n");
      expect(git(repo, { GIT_CONFIG_GLOBAL: b.file }, "add", "f.txt").status).toBe(0);
      const ok = git(repo, { GIT_CONFIG_GLOBAL: b.file }, "commit", "-q", "-m", "c");
      expect(ok.status, ok.stderr).toBe(0);
      expect(git(repo, { GIT_CONFIG_GLOBAL: b.file }, "log", "-1", "--format=%an").stdout.trim()).toBe("github-actions[bot]");
      // control: the same commit with /dev/null as global must fail, so the pass above is the file, not ambient state
      writeFileSync(path.join(repo, "g.txt"), "y\n");
      git(repo, { GIT_CONFIG_GLOBAL: "/dev/null" }, "add", "g.txt");
      const bad = git(repo, { GIT_CONFIG_GLOBAL: "/dev/null" }, "-c", "user.useConfigOnly=true", "commit", "-q", "-m", "d");
      expect(bad.status).not.toBe(0);
      expect(bad.stderr).toMatch(/identity|Author identity unknown|empty ident/i);
    } finally {
      b.cleanup();
      rmSync(repo, { recursive: true, force: true });
    }
  });

  it("a workspace's own local identity still beats the global file", () => {
    const b = build();
    const repo = mkdtempSync(path.join(tmpdir(), "agentrepo-"));
    try {
      git(repo, {}, "init", "-q", "-b", "main");
      git(repo, {}, "config", "--local", "user.name", "Real User");
      git(repo, {}, "config", "--local", "user.email", "real@example.invalid");
      writeFileSync(path.join(repo, "f.txt"), "x\n");
      git(repo, { GIT_CONFIG_GLOBAL: b.file }, "add", "f.txt");
      expect(git(repo, { GIT_CONFIG_GLOBAL: b.file }, "commit", "-q", "-m", "c").status).toBe(0);
      expect(git(repo, { GIT_CONFIG_GLOBAL: b.file }, "log", "-1", "--format=%an").stdout.trim()).toBe("Real User");
    } finally {
      b.cleanup();
      rmSync(repo, { recursive: true, force: true });
    }
  });
});
