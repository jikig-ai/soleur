import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { spawnSync } from "node:child_process";
import { chmodSync, cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

// Required-lane wrapper for the closed-world docker run tuple check and the STATIC half of the masked-/proc docker
// suite (#10065, Guards 1 and 4).
//
// The three docker run tuples that start the app container (canary and prod in infra/ci-deploy.sh, first boot in
// infra/cloud-init.yml) carry the posture the sandbox /proc mask depends on. `infra/lib/docker-run-tuple.py` parses
// them closed-world (every option, environment name, volume and port outside the declared set is a violation, and
// every command-position `docker run|create` in the two files is censused). The infra-validation workflow jobs that
// also run it are ADVISORY (not in the required check set), so on their own they would not stop an appended
// `--cap-add` from merging; the webplat vitest shards run under the required `test` aggregator, which is why this
// wrapper exists. The unit and mutation battery for the helper itself is infra/docker-run-tuple.test.sh.
//
// The docker suite (infra/sandbox-masked-proc-docker.test.sh) runs its STATIC arms (tuple closed set, Dockerfile
// lineage, ENV PATH order, bwrap elevation, uid, the fixture-derived isolation argv, the drop analyzer) BEFORE its first
// docker call, so with a `docker` on PATH that always fails they run to completion on any runner and the suite then
// dies with DOCKER_UNAVAILABLE. That is exactly what the rows below drive: the unmutated tree must reach
// DOCKER_UNAVAILABLE with every static arm passed, and each mutated copy of the Dockerfile / fixture / tuples must die
// on its own token BEFORE any docker call. (The copy seam SANDBOX_MASKED_PROC_SRC_ROOT is refused when CI is set, so
// these runs drop CI from the child environment; the real docker run is never involved.)

const APP_ROOT = path.resolve(__dirname, "..");
const HELPER = path.join(APP_ROOT, "infra", "lib", "docker-run-tuple.py");
const SUITE = path.join(APP_ROOT, "infra", "sandbox-masked-proc-docker.test.sh");
const CI_DEPLOY = path.join(APP_ROOT, "infra", "ci-deploy.sh");
const CLOUD_INIT = path.join(APP_ROOT, "infra", "cloud-init.yml");

// The posture digest of the three real tuples. docker-run-tuple.test.sh pins the same literal: a posture change is a
// visible edit in this file AND that one, not only in the helper that computes it (a failure here says to update both).
const EXPECTED_POSTURE = "e959fc801d99";

function runCheck(root?: string) {
  const args = ["-I", HELPER, "check", ...(root ? ["--root", root] : [])];
  return spawnSync("python3", args, { encoding: "utf8", timeout: 60_000 });
}

describe("docker run tuple posture (closed world)", () => {
  it("passes on the real tree and reports exactly three app tuples with the pinned posture digest", () => {
    const r = runCheck();
    expect(r.error, `python3 could not be spawned: ${String(r.error)}`).toBeUndefined();
    expect(r.status, `docker-run-tuple.py check failed:\n${r.stdout}${r.stderr}`).toBe(0);
    expect(
      r.stdout.trim(),
      `the tuple posture digest changed: if the change is intended and security-reviewed, update BOTH EXPECTED_POSTURE literals (this file and infra/docker-run-tuple.test.sh)`,
    ).toBe(`docker-run-tuple:ok tuples=3 posture=${EXPECTED_POSTURE}`);
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
      expect(r.stdout, "the failure must carry its remediation hint").toMatch(/^HINT UNKNOWN_OPTION: /m);
    } finally {
      rmSync(tmp, { recursive: true, force: true });
    }
  });
});

describe("masked-/proc docker suite: static arms (no docker daemon needed)", () => {
  let work: string;
  let stubBin: string;
  let calls: string;

  beforeAll(() => {
    work = mkdtempSync(path.join(tmpdir(), "masked-proc-static-"));
    stubBin = path.join(work, "bin");
    calls = path.join(work, "docker-calls.log");
    mkdirSync(stubBin, { recursive: true });
    // A `docker` that records the call and always fails: `docker info` then ends the suite right after its static arms.
    writeFileSync(path.join(stubBin, "docker"), `#!/usr/bin/env bash\necho "$*" >> ${JSON.stringify(calls)}\nexit 1\n`);
    chmodSync(path.join(stubBin, "docker"), 0o755);
  });
  afterAll(() => {
    rmSync(work, { recursive: true, force: true });
  });

  /** Runs the suite; `copy` is a mutated copy of the files the static arms read (an app-root-shaped directory). */
  function runSuite(opts: { copy?: string; env?: Record<string, string> } = {}) {
    writeFileSync(calls, "");
    const env: NodeJS.ProcessEnv = {
      ...process.env,
      PATH: `${stubBin}:${process.env.PATH ?? ""}`,
      TMPDIR: work,
      ...(opts.copy ? { SANDBOX_MASKED_PROC_SRC_ROOT: opts.copy } : {}),
      ...(opts.env ?? {}),
    };
    // The copy seam is refused under CI; the real docker run is never involved here, so CI is dropped unless a row sets it.
    if (!("CI" in (opts.env ?? {}))) delete env.CI;
    delete env.SOLEUR_SANDBOX_DOCKER_APPARMOR;
    if (!opts.copy) delete env.SANDBOX_MASKED_PROC_SRC_ROOT; // an inherited copy seam would silently test another tree
    delete env.SANDBOX_MASKED_PROC_MUTATE;
    if (opts.env && "SANDBOX_MASKED_PROC_MUTATE" in opts.env) env.SANDBOX_MASKED_PROC_MUTATE = opts.env.SANDBOX_MASKED_PROC_MUTATE;
    const r = spawnSync("bash", [SUITE], { encoding: "utf8", timeout: 90_000, env, cwd: work });
    const dockerCalls = readFileSync(calls, "utf8")
      .split("\n")
      .filter((l) => l && !/^(rm -f|rmi -f) /.test(l));
    return { ...r, out: `${r.stdout}${r.stderr}`, dockerCalls };
  }

  function makeCopy(name: string): string {
    const dir = path.join(work, name);
    mkdirSync(path.join(dir, "infra"), { recursive: true });
    cpSync(path.join(APP_ROOT, "Dockerfile"), path.join(dir, "Dockerfile"));
    for (const f of ["ci-deploy.sh", "cloud-init.yml", "sandbox-canary-argv.json", "c4-render-sandbox-argv.json"]) {
      cpSync(path.join(APP_ROOT, "infra", f), path.join(dir, "infra", f));
    }
    return dir;
  }
  const edit = (file: string, fn: (text: string) => string) => {
    const before = readFileSync(file, "utf8");
    const after = fn(before);
    expect(after, `the mutation did not change ${file} (an anchor moved)`).not.toBe(before);
    writeFileSync(file, after);
  };

  // The counts the suite must print are read from its own source, so adding or deleting an arm is a deliberate edit of the
  // suite and this test follows it (a hard-coded number here would only restate the suite).
  const SUITE_SRC = readFileSync(SUITE, "utf8");
  const STATIC_ARMS = (SUITE_SRC.match(/^\s*pass "static: /gm) ?? []).length;
  const ANALYZER_ROWS = (SUITE_SRC.match(/^\s*drop_expect (?:ok|bad) /gm) ?? []).length;

  it("the unmutated tree passes every static arm and then stops at DOCKER_UNAVAILABLE with no docker call but `docker info`", () => {
    expect(existsSync(SUITE)).toBe(true);
    expect(STATIC_ARMS, "no `pass \"static: ` line was found in the suite source (the anchor moved)").toBeGreaterThan(0);
    expect(ANALYZER_ROWS, "no `drop_expect` row was found in the suite source (the anchor moved)").toBeGreaterThan(0);
    const r = runSuite();
    expect(r.status, r.out.slice(0, 2000)).toBe(1);
    expect(r.out).toMatch(/FAIL: DOCKER_UNAVAILABLE/);
    expect(
      (r.out.match(/^ {2}pass: static: /gm) ?? []).length,
      `the suite source declares ${STATIC_ARMS} static arms; a different number ran (an arm was skipped or died silently)`,
    ).toBe(STATIC_ARMS);
    expect(
      (r.out.match(/^ {2}pass: analyzer: /gm) ?? []).length,
      `the suite source declares ${ANALYZER_ROWS} analyzer rows; a different number ran`,
    ).toBe(ANALYZER_ROWS);
    expect(r.out.match(/^ {2}FAIL: /gm) ?? [], "an assertion failed before the docker gate").toHaveLength(0);
    expect(r.dockerCalls).toEqual(["info"]);
  }, 120_000);

  // The cli-tools base digest is read from the Dockerfile (a hard-coded copy here would go stale on every base bump).
  const CLI_TOOLS_FROM = /^(FROM \S+@sha256:)([0-9a-f]{8})([0-9a-f]{56} AS cli-tools)$/m;
  const ROWS: Array<[string, string, (copy: string) => void]> = [
    ["cli-tools FROM another digest", "BASE_LINEAGE", (c) => edit(path.join(c, "Dockerfile"), (t) => t.replace(CLI_TOOLS_FROM, (_m, a: string, _d: string, b: string) => `${a}00000000${b}`))],
    ["runner FROM builder", "BASE_LINEAGE", (c) => edit(path.join(c, "Dockerfile"), (t) => t.replace("FROM cli-tools AS runner", "FROM builder AS runner"))],
    ["ENV PATH puts /usr/bin first", "PATH_ORDER", (c) => edit(path.join(c, "Dockerfile"), (t) => t.replace("ENV NODE_ENV=production", "ENV NODE_ENV=production\nENV PATH=/usr/bin:/usr/local/bin:$PATH"))],
    ["ENV PATH from an unresolved ARG", "PATH_ORDER", (c) => edit(path.join(c, "Dockerfile"), (t) => t.replace("ENV NODE_ENV=production", "ENV NODE_ENV=production\nENV PATH=$EXTRA_PATH"))],
    ["bwrap given a file capability", "ELEVATION", (c) => edit(path.join(c, "Dockerfile"), (t) => `${t}\nRUN setcap cap_sys_admin+ep /usr/bin/bwrap\n`)],
    ["bwrap made setuid", "ELEVATION", (c) => edit(path.join(c, "Dockerfile"), (t) => `${t}\nRUN chmod u+s /usr/bin/bwrap\n`)],
    ["bwrap made setuid by octal mode", "ELEVATION", (c) => edit(path.join(c, "Dockerfile"), (t) => `${t}\nRUN chmod 4755 /usr/bin/bwrap\n`)],
    ["bwrap made setuid by a symbolic mode with s", "ELEVATION", (c) => edit(path.join(c, "Dockerfile"), (t) => `${t}\nRUN chmod u=rwxs,go=rx /usr/bin/bwrap\n`)],
    ["bwrap made setuid with a quoted mode", "ELEVATION", (c) => edit(path.join(c, "Dockerfile"), (t) => `${t}\nRUN chmod "u+s" /usr/bin/bwrap\n`)],
    ["bwrap installed with a glued setuid mode", "ELEVATION", (c) => edit(path.join(c, "Dockerfile"), (t) => `${t}\nRUN install -m4755 /x /usr/bin/bwrap\n`)],
    ["bwrap copied with a setuid --chmod", "ELEVATION", (c) => edit(path.join(c, "Dockerfile"), (t) => `${t}\nCOPY --chmod=4755 /x /usr/bin/bwrap\n`)],
    ["last USER is root", "USER_DRIFT", (c) => edit(path.join(c, "Dockerfile"), (t) => `${t}\nUSER root\n`)],
    ["canary fixture loses the vendor tail bind", "FIXTURE_TAIL", (c) => edit(path.join(c, "infra", "sandbox-canary-argv.json"), (t) => {
      const j = JSON.parse(t);
      const a: string[] = j.bwrapSetupArgv;
      for (let i = a.length - 3; i >= 0; i--) {
        if (a[i] === "--bind" && a[i + 1] === "/proc" && a[i + 2] === "/proc") { a.splice(i, 3); break; }
      }
      return JSON.stringify(j, null, 2);
    })],
    ["a prod tuple gains --cap-add", "TUPLE_CHECK", (c) => edit(path.join(c, "infra", "ci-deploy.sh"), (t) => t.replace("      --init \\\n", "      --init \\\n      --cap-add SYS_ADMIN \\\n"))],
  ];
  for (const [label, token, mutate] of ROWS) {
    it(`${label} dies ${token} before any docker call`, () => {
      const copy = makeCopy(`row-${token}-${label.replace(/\W+/g, "-")}`);
      mutate(copy);
      const r = runSuite({ copy });
      expect(r.status, r.out.slice(0, 1500)).toBe(1);
      expect(r.out).toMatch(new RegExp(`^FAIL: ${token}\\b`, "m"));
      expect(r.dockerCalls, "a docker call happened before the static arm refused").toEqual([]);
    }, 120_000);
  }

  it("a lowercase `as` stage name is read like `AS` (the static arms still pass; a stricter parse would only be a false red)", () => {
    const copy = makeCopy("row-lowercase-as");
    edit(path.join(copy, "Dockerfile"), (t) => t.replace(/^(FROM \S+) AS cli-tools$/m, "$1 as cli-tools"));
    const r = runSuite({ copy });
    expect(r.out).toMatch(/FAIL: DOCKER_UNAVAILABLE/);
    expect(r.out.match(/^ {2}pass: static: /gm) ?? [], r.out.slice(0, 1500)).toHaveLength(STATIC_ARMS);
    expect(r.dockerCalls).toEqual(["info"]);
  }, 120_000);

  it("the copy seam is refused under CI and an unknown mutation seam is refused (neither silently runs the baseline)", () => {
    const copy = makeCopy("row-seams");
    const underCi = runSuite({ copy, env: { CI: "1" } });
    expect(underCi.out).toMatch(/^FAIL: SRC_ROOT_REFUSED/m);
    const unknown = runSuite({ env: { SANDBOX_MASKED_PROC_MUTATE: "shim-splise" } });
    expect(unknown.out).toMatch(/^FAIL: MUTATION_UNKNOWN/m);
    expect(unknown.dockerCalls).toEqual([]);
  }, 120_000);
});
