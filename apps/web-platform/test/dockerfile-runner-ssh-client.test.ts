import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// #5914 (CTO ruling 2026-09-28): git-auth.ts spawns `ssh` directly (sshWithPrivateKeyAuth)
// and through GIT_SSH_COMMAND (gitWithPrivateKeyAuth). git only RECOMMENDS openssh-client,
// so the runner stage's `--no-install-recommends` silently dropped it, and every git-data
// dial in production — Art. 17 erasure included — failed ENOENT. Measured: node:22-slim +
// that apt line prints no `ssh`. The runtime half of this guard is the startup line
// `git_data_ssh_client=present|absent`.
const dockerfile = readFileSync(path.resolve(__dirname, "..", "Dockerfile"), "utf8");

/** The runner stage: from `FROM … AS runner` to the next `FROM` (or end of file). */
function runnerStage(src: string): string {
  const start = src.search(/^FROM\s+\S+\s+AS\s+runner\s*$/m);
  if (start === -1) throw new Error("Dockerfile has no `FROM … AS runner` stage");
  const rest = src.slice(start + 1);
  const next = rest.search(/^FROM\s/m);
  return next === -1 ? src.slice(start) : src.slice(start, start + 1 + next);
}

/** Every package named by a `apt-get install … --no-install-recommends` in `stage`. */
function aptPackages(stage: string): string[] {
  const stripped = stage.replace(/^\s*#.*$/gm, "").replace(/\\\n/g, " ");
  const pkgs: string[] = [];
  for (const m of stripped.matchAll(/apt-get install\s+-y\s+--no-install-recommends\s+([^&;\n]+)/g)) {
    pkgs.push(...m[1].trim().split(/\s+/));
  }
  return pkgs;
}

describe("runner image ships an ssh client (#5914)", () => {
  it("the runner stage installs openssh-client (git only Recommends it)", () => {
    const pkgs = aptPackages(runnerStage(dockerfile));
    // Positive control: the extraction reads the real apt line, not nothing.
    expect(pkgs).toContain("git");
    expect(
      pkgs,
      "openssh-client missing from the runner stage: --no-install-recommends drops git's " +
        "Recommends, so `ssh` is absent and every git-data dial fails ENOENT (#5914)",
    ).toContain("openssh-client");
  });

  it("a comment mentioning openssh-client does not satisfy the guard", () => {
    const fake = "FROM x AS runner\n# openssh-client\nRUN apt-get install -y --no-install-recommends git jq\n";
    expect(aptPackages(runnerStage(fake))).not.toContain("openssh-client");
  });
});
