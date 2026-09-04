// Guard 1 — fixture git-write containment (runtime).
//
// PROPERTY. Under a hostile inherited git environment, a `git` write issued by a fixture mutates
// only the fixture repository: the victim repository's HEAD, its ref set, and its index are all
// unchanged.
//
// The guard sets the hostile environment ITSELF rather than relying on an ambient one, so it
// reproduces in a plain clone as well as in a linked worktree. Measured (spec `measurements.md`
// §M-1): a hook in a plain clone exports no GIT_DIR at all, so a guard that depended on the
// ambient env would silently assert nothing for anyone running outside a worktree.
//
// Why HEAD alone is not the assertion: with GIT_DIR scrubbed, an ABSOLUTE GIT_INDEX_FILE still
// retargets `git add` into the victim's index while HEAD stays put (§M-3). The three observables
// below are compared as a triple for that reason — mutation row M2 exists to keep it that way.

import { afterAll, describe, expect, test } from "bun:test";
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync, chmodSync, realpathSync, rmSync, symlinkSync } from "node:fs";
import { dirname, join } from "node:path";
import { tmpdir } from "node:os";

import { gitFixtureEnv, gitFixture, fixtureCeiling } from "./lib/git-fixture-env";

// --- assertion ledger (AP-023) -------------------------------------------------------------
// An independent, append-only count of assertions that actually executed. The floors at the
// bottom report through `printf`-equivalent + a thrown error, never through expect(), so
// neutering the assertion helper cannot silence them (harness row H1).
const ledger: string[] = [];
function record(name: string): void {
  ledger.push(name);
}

// ONE owning scratch root, removed in afterAll. Every fixture below lives inside it.
//
// The previous version called mkdtempSync(join(tmpdir(), …)) per fixture with no cleanup at all,
// leaking 7 directories and a driver file per run — and Guard 1 runs 4x per battery (once directly,
// three times inside the Guard 3 driver). Measured on this machine before the fix: 747 orphaned
// `guard1-*` directories totalling ~106 MB. Both sibling suites in this directory
// (welcome-hook.test.ts, gdpr-gate-repo-scan.test.ts) already clean up; this one did not.
//
// TMPDIR is load-bearing (harness row H3) and must survive the env sweep, so the root deliberately
// lives under it.
const SCRATCH_ROOT = mkdtempSync(join(tmpdir(), "guard1-root-"));

afterAll(() => {
  rmSync(SCRATCH_ROOT, { recursive: true, force: true });
});

function scratch(prefix: string): string {
  return mkdtempSync(join(SCRATCH_ROOT, prefix));
}

/** A victim repository with one commit, plus a reading of its three observables. */
function makeVictim(): { dir: string; read: () => string } {
  const dir = scratch("guard1-victim-");
  const env = gitFixtureEnv(dir);
  const g = (args: string[]) => execFileSync("git", args, { cwd: dir, env, encoding: "utf8" });
  g(["init", "-q", "-b", "main"]);
  g(["commit", "-q", "--allow-empty", "-m", "victim-base"]);

  const read = (): string => {
    const head = g(["rev-parse", "HEAD"]).trim();
    const refs = g(["for-each-ref", "--format=%(refname) %(objectname)"]).trim();
    const staged = g(["diff", "--cached", "--name-only"]).trim();
    // Fail closed on an empty baseline rather than passing on "" === "" (harness row H2).
    if (head === "") throw new Error("victim HEAD read empty — baseline is not established");
    return JSON.stringify({ head, refs, staged });
  };
  return { dir, read };
}

/** The hostile environment a linked-worktree git hook actually exports (§M-1). */
function hostileEnv(victimDir: string): Record<string, string> {
  return {
    ...(process.env as Record<string, string>),
    GIT_DIR: join(victimDir, ".git"),
    GIT_INDEX_FILE: join(victimDir, ".git", "index"),
  };
}

/**
 * Build a fixture repo inside a CHILD bun process started under `env`.
 *
 * The indirection is the point. The hazard is an environment INHERITED at process start, and Bun
 * only reproduces it that way: a variable assigned to `process.env` mid-test does not reach a
 * child spawned without an explicit `env`. Driving the fixture through a real child process makes
 * the default-env path observable, which is what lets mutation rows M4 and M6 discriminate.
 */
function runFixtureDriver(
  fixtureDir: string,
  env: Record<string, string>,
): { status: number; head: string } {
  const driver = join(SCRATCH_ROOT, `driver-${Math.random().toString(36).slice(2)}.ts`);
  writeFileSync(
    driver,
    [
      `import { gitFixture } from ${JSON.stringify(join(import.meta.dir, "lib", "git-fixture-env.ts"))};`,
      `import { writeFileSync } from "node:fs";`,
      `import { join } from "node:path";`,
      `const dir = process.argv[2];`,
      `const git = gitFixture(dir);`,
      `git(["init", "-q", "-b", "main"]);`,
      `writeFileSync(join(dir, "f.txt"), "hello\\n");`,
      `git(["add", "f.txt"]);`,
      `git(["commit", "-q", "-m", "fixture-commit"]);`,
      `process.stdout.write(git(["rev-parse", "HEAD"]).trim());`,
      ``,
    ].join("\n"),
  );
  try {
    const head = execFileSync("bun", ["run", driver, fixtureDir], {
      env,
      encoding: "utf8",
    }).trim();
    return { status: 0, head };
  } catch {
    return { status: 1, head: "" };
  }
}

describe("Guard 1 — fixture git writes are contained under a hostile inherited env", () => {
  test("a fixture built with gitFixture() leaves the victim's HEAD, refs and index untouched", () => {
    const victim = makeVictim();
    const before = victim.read();
    const fixtureDir = scratch("guard1-fixture-");

    // The hostile environment MUST be present at the child's process START, not injected by
    // mutating process.env in this process. Under Bun a child spawned without an explicit `env`
    // receives the values the process was STARTED with, so a `process.env.GIT_DIR = ...` here
    // would never reach a default-env grandchild — the fixture would be running clean while
    // claiming to be hostile, and any arm exercising the default-env path would pass vacuously.
    // Measured: written the mutate-process.env way, mutation rows M4 and M6 both SURVIVED.
    const out = runFixtureDriver(fixtureDir, hostileEnv(victim.dir));
    expect(out.status).toBe(0);

    // The fixture must be a real repository of its own — not a no-op that wrote elsewhere.
    expect(out.head).toMatch(/^[0-9a-f]{40}$/);
    record("fixture-is-a-real-repo");

    expect(victim.read()).toBe(before);
    record("victim-triple-unchanged");
  });

  test("a TRANSITIVE spawn — a shell script that runs git itself — is also contained", () => {
    // The arm neither a helper-call grep nor any source scan could reach: the suite does not run
    // `git`, it runs a script that does. An env CONSTRUCTOR becomes an env CHOKEPOINT only when
    // every spawn out of the suite carries it, so the constructed env is handed to the SCRIPT.
    const victim = makeVictim();
    const before = victim.read();

    const fixtureDir = scratch("guard1-transitive-");
    const script = join(fixtureDir, "make-repo.sh");
    writeFileSync(
      script,
      ["#!/bin/bash", "set -euo pipefail", 'cd "$1"', "git init -q -b main", "git commit -q --allow-empty -m via-script", ""].join("\n"),
    );
    chmodSync(script, 0o755);

    const inner = join(fixtureDir, "repo");
    mkdirSync(inner, { recursive: true });

    // Same reason as above: the hostile env must be inherited at process START, or the arm passes
    // vacuously against a clean environment.
    const driver = join(fixtureDir, "transitive-driver.ts");
    writeFileSync(
      driver,
      [
        `import { gitFixtureEnv } from ${JSON.stringify(join(import.meta.dir, "lib", "git-fixture-env.ts"))};`,
        `import { execFileSync } from "node:child_process";`,
        `const [script, dir] = process.argv.slice(2);`,
        `execFileSync("bash", [script, dir], { env: gitFixtureEnv(dir) });`,
        ``,
      ].join("\n"),
    );
    execFileSync("bun", ["run", driver, script, inner], {
      env: hostileEnv(victim.dir),
      encoding: "utf8",
    });

    expect(victim.read()).toBe(before);
    record("transitive-spawn-contained");
  });

  test("H3 (must-PASS): a fixture path with a space and a -leading segment still works", () => {
    // TMPDIR must survive the deny-list, and the helper must not choke on adversarial path shapes.
    const base = scratch("guard1-paths-");
    const odd = join(base, "has space", "-dashlead");
    mkdirSync(odd, { recursive: true });
    const git = gitFixture(odd);
    git(["init", "-q", "-b", "main"]);
    git(["commit", "-q", "--allow-empty", "-m", "odd-path"]);
    const head = execFileSync("git", ["rev-parse", "HEAD"], {
      cwd: odd,
      env: gitFixtureEnv(odd),
      encoding: "utf8",
    }).trim();
    expect(head).toMatch(/^[0-9a-f]{40}$/);
    record("H3-odd-paths-pass");
  });

  test("H4 (must-PASS): a read-only fixture is not collateral", () => {
    const victim = makeVictim();
    const before = victim.read();
    const git = gitFixture(victim.dir);
    expect(git(["status", "--porcelain"])).toBe("");
    expect(victim.read()).toBe(before);
    record("H4-readonly-pass");
  });

  test("the helper SWEEPS the GIT_ namespace, pins an identity, and sets an exact ceiling", () => {
    const base = scratch("guard1-shape-");
    const dir = join(base, "fixture");
    mkdirSync(dir, { recursive: true });

    // Assert against a SYNTHETIC hostile input, not against ambient absence. The previous version
    // looped over GIT_LOCATION_VARS asserting `expect(env[k]).toBeUndefined()` — which is
    // structurally vacuous here, because the tripwire aborts the whole runner at rc=97 if any of
    // those names is present at process START. That arm could therefore only ever execute in an
    // environment where all of them were already absent, and `toBeUndefined()` on a key that was
    // never there passes whatever the helper does. Measured: deleting five of the seven names, and
    // deleting the entire injection filter, both left the suite at 6 pass / 0 fail.
    //
    // Setting them HERE is safe and observable: the tripwire ran at import, so a mid-test
    // assignment reaches the helper without aborting anything.
    const injected = [
      "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR", "GIT_OBJECT_DIRECTORY",
      "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_NAMESPACE", "GIT_TEMPLATE_DIR", "GIT_EXEC_PATH",
      "GIT_SSH", "GIT_SSH_COMMAND", "GIT_ASKPASS", "GIT_EDITOR", "GIT_SEQUENCE_EDITOR",
      "GIT_EXTERNAL_DIFF", "GIT_PROXY_COMMAND", "GIT_CONFIG_COUNT", "GIT_CONFIG_KEY0",
      "GIT_CONFIG_PARAMETERS", "GIT_TRACE", "GIT_TRACE2", "GIT_TRACE_CURL", "GIT_ATTR_SOURCE",
      "GIT_ALLOW_PROTOCOL", "GIT_AUTHOR_DATE", "GIT_COMMITTER_DATE",
    ];
    const saved = new Map<string, string | undefined>();
    for (const k of [...injected, "SSH_ASKPASS"]) {
      saved.set(k, process.env[k]);
      process.env[k] = "/tmp/hostile-injected";
    }
    try {
      const env = gitFixtureEnv(dir);
      for (const k of injected) {
        // Every one of these is swept by the namespace rule, including the four a name list missed
        // (GIT_TEMPLATE_DIR, GIT_EXEC_PATH, GIT_SSH, the GIT_TRACE family) and GIT_AUTHOR_DATE,
        // which a hook exports and which a deny-list silently kept — pinning every fixture commit
        // in a hook-mediated run to one identical timestamp.
        if (k.startsWith("GIT_AUTHOR_") || k.startsWith("GIT_COMMITTER_")) continue;
        expect(env[k]).toBeUndefined();
      }
      // SSH_ASKPASS carries no GIT_ prefix, so the sweep cannot reach it by shape.
      expect(env.SSH_ASKPASS).toBeUndefined();
      record("sweep-removes-injected-vars");

      // §M-7: an env without an identity fails `Author identity unknown` on the first commit.
      for (const k of ["GIT_AUTHOR_NAME", "GIT_AUTHOR_EMAIL", "GIT_COMMITTER_NAME", "GIT_COMMITTER_EMAIL"]) {
        expect(env[k]).toBeTruthy();
      }
      expect(env.GIT_AUTHOR_EMAIL).toContain("@example.com");
      // A pinned date, so an inherited GIT_AUTHOR_DATE cannot survive the sweep and re-appear.
      expect(env.GIT_AUTHOR_DATE).toBeUndefined();
      record("identity-pinned");

      // EXACT ceiling, not merely "truthy and not the fixture dir" — a ceiling of "/" satisfies
      // both of those and git ignores it entirely, so the weaker assertion passed over a no-op.
      expect(env.GIT_CEILING_DIRECTORIES).toBe(fixtureCeiling(dir));
      expect(env.GIT_CEILING_DIRECTORIES).toBe(dirname(realpathSync(dir)));
      record("ceiling-exact");

      if (process.env.TMPDIR) expect(env.TMPDIR).toBe(process.env.TMPDIR);
    } finally {
      for (const [k, v] of saved) {
        if (v === undefined) delete process.env[k];
        else process.env[k] = v;
      }
    }
  });

  test("a SYMLINKED fixture directory is still contained", () => {
    // The ceiling must be dirname(realpath(fixture)), NOT realpath(dirname(fixture)). The second
    // resolves the LEXICAL parent, so when the fixture directory is itself a symlink the ceiling
    // names the link's parent while git's getcwd() reports the physical path — and discovery walks
    // straight out. Without this fixture the two spellings are indistinguishable: measured, the
    // buggy spelling passed the whole suite.
    const base = scratch("guard1-symlink-");
    const real = join(base, "physical", "fix");
    mkdirSync(real, { recursive: true });
    const link = join(base, "link");
    symlinkSync(real, link);

    // A victim repo sits at the LINK's lexical parent, which the buggy ceiling would have allowed.
    const victimDir = join(base, "victim");
    mkdirSync(victimDir, { recursive: true });
    const vg = gitFixture(victimDir);
    vg(["init", "-q", "-b", "main"]);
    vg(["commit", "-q", "--allow-empty", "-m", "victim-base"]);

    expect(gitFixtureEnv(link).GIT_CEILING_DIRECTORIES).toBe(dirname(realpathSync(link)));
    expect(gitFixtureEnv(link).GIT_CEILING_DIRECTORIES).not.toBe(dirname(link));
    record("symlinked-fixture-contained");
  });

  test("an unenforceable ceiling is REFUSED, not silently emitted", () => {
    // git ignores a ceiling of "/" and any entry containing ":" (the separator), so emitting one
    // reads as protection while doing nothing. Failing loudly is the only honest option.
    expect(() => gitFixtureEnv("/onelevel")).toThrow(/enforceable GIT_CEILING_DIRECTORIES/);
    const colon = join(scratch("guard1-colon-"), "a:b", "fix");
    mkdirSync(colon, { recursive: true });
    expect(() => gitFixtureEnv(colon)).toThrow(/enforceable GIT_CEILING_DIRECTORIES/);
    record("unenforceable-ceiling-refused");
  });
});

// --- anti-vacuity floors (AP-023) ----------------------------------------------------------
// These do NOT run through expect(): neutering the assertion helper must not silence them.
describe("Guard 1 floors", () => {
  test("the ledger recorded every assertion arm", () => {
    const expected = [
      "fixture-is-a-real-repo",
      "victim-triple-unchanged",
      "transitive-spawn-contained",
      "H3-odd-paths-pass",
      "H4-readonly-pass",
      "sweep-removes-injected-vars",
      "identity-pinned",
      "ceiling-exact",
      "symlinked-fixture-contained",
      "unenforceable-ceiling-refused",
    ];
    const missing = expected.filter((n) => !ledger.includes(n));
    if (missing.length > 0) {
      process.stderr.write(`Guard 1 FLOOR: arms did not execute: ${missing.join(", ")}\n`);
      throw new Error(`Guard 1 floor: ${missing.length} arm(s) did not execute`);
    }
    if (ledger.length < expected.length) {
      process.stderr.write(`Guard 1 FLOOR: ledger ${ledger.length} < ${expected.length}\n`);
      throw new Error("Guard 1 floor: ledger below expected cardinality");
    }
  });
});
