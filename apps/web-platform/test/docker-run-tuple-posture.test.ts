import { describe, it, expect } from "vitest";
import { spawnSync } from "node:child_process";
import { cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

// Required-lane wrapper for the closed-world docker run tuple check (#10065, Guard 1).
//
// The three docker run tuples that start the app container (canary and prod in infra/ci-deploy.sh, first boot in
// infra/cloud-init.yml) carry the posture the sandbox /proc mask depends on. `infra/lib/docker-run-tuple.py` parses
// them closed-world (every option, environment name, volume and port outside the declared set is a violation, and
// every command-position `docker run|create` in the two files is censused). The infra-validation workflow jobs that
// also run it are ADVISORY (not in the required check set), so on their own they would not stop an appended
// `--cap-add` from merging; the webplat vitest shards run under the required `test` aggregator, which is why this
// wrapper exists. The unit and mutation battery for the helper itself is infra/docker-run-tuple.test.sh.

const APP_ROOT = path.resolve(__dirname, "..");
const HELPER = path.join(APP_ROOT, "infra", "lib", "docker-run-tuple.py");
const CI_DEPLOY = path.join(APP_ROOT, "infra", "ci-deploy.sh");
const CLOUD_INIT = path.join(APP_ROOT, "infra", "cloud-init.yml");

function runCheck(root?: string) {
  const args = ["-I", HELPER, "check", ...(root ? ["--root", root] : [])];
  return spawnSync("python3", args, { encoding: "utf8", timeout: 60_000 });
}

describe("docker run tuple posture (closed world)", () => {
  it("passes on the real tree and reports exactly three app tuples", () => {
    const r = runCheck();
    expect(r.error, `python3 could not be spawned: ${String(r.error)}`).toBeUndefined();
    expect(r.status, `docker-run-tuple.py check failed:\n${r.stdout}${r.stderr}`).toBe(0);
    expect(r.stdout).toMatch(/^docker-run-tuple:ok tuples=3 posture=[0-9a-f]{12}$/m);
    expect(r.stdout).not.toMatch(/^FAIL /m);
  });

  it("goes red when a posture-changing option is appended to a tuple (the wrapper is not vacuous)", () => {
    const tmp = mkdtempSync(path.join(tmpdir(), "docker-run-tuple-"));
    try {
      const infra = path.join(tmp, "apps", "web-platform", "infra");
      mkdirSync(infra, { recursive: true });
      cpSync(CLOUD_INIT, path.join(infra, "cloud-init.yml"));
      const src = readFileSync(CI_DEPLOY, "utf8");
      const anchor = "      --init \\\n";
      expect(src.includes(anchor), "the canary tuple's --init continuation line moved; update this anchor").toBe(true);
      writeFileSync(path.join(infra, "ci-deploy.sh"), src.replace(anchor, `${anchor}      --cap-add SYS_ADMIN \\\n`));
      const r = runCheck(tmp);
      expect(r.status, `expected exit 1, got:\n${r.stdout}${r.stderr}`).toBe(1);
      expect(r.stdout).toMatch(/^FAIL UNKNOWN_OPTION: --cap-add in ci-deploy\.sh canary/m);
    } finally {
      rmSync(tmp, { recursive: true, force: true });
    }
  });
});
