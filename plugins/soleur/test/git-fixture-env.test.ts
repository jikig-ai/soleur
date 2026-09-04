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

import { describe, expect, test } from "bun:test";
import { execFileSync } from "node:child_process";
import { mkdtempSync, mkdirSync, writeFileSync, chmodSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";

import { gitFixtureEnv, gitFixture } from "./lib/git-fixture-env";

// --- assertion ledger (AP-023) -------------------------------------------------------------
// An independent, append-only count of assertions that actually executed. The floors at the
// bottom report through `printf`-equivalent + a thrown error, never through expect(), so
// neutering the assertion helper cannot silence them (harness row H1).
const ledger: string[] = [];
function record(name: string): void {
  ledger.push(name);
}

/** Absolute path to a scratch root. TMPDIR is load-bearing (harness row H3) and must survive
 *  the helper's deny-list, so the fixtures below deliberately live under it. */
function scratch(prefix: string): string {
  return mkdtempSync(join(tmpdir(), prefix));
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

describe("Guard 1 — fixture git writes are contained under a hostile inherited env", () => {
  test("a fixture built with gitFixture() leaves the victim's HEAD, refs and index untouched", () => {
    const victim = makeVictim();
    const before = victim.read();

    // Enter the hostile environment for the duration of the fixture's work, exactly as an
    // inherited hook env would. gitFixtureEnv() must neutralise it.
    const saved = { d: process.env.GIT_DIR, i: process.env.GIT_INDEX_FILE };
    process.env.GIT_DIR = join(victim.dir, ".git");
    process.env.GIT_INDEX_FILE = join(victim.dir, ".git", "index");
    try {
      const fixtureDir = scratch("guard1-fixture-");
      const git = gitFixture(fixtureDir);
      git(["init", "-q", "-b", "main"]);
      writeFileSync(join(fixtureDir, "f.txt"), "hello\n");
      git(["add", "f.txt"]);
      git(["commit", "-q", "-m", "fixture-commit"]);

      // The fixture must be a real repository of its own — not a no-op that wrote elsewhere.
      const fixtureHead = execFileSync("git", ["rev-parse", "HEAD"], {
        cwd: fixtureDir,
        env: gitFixtureEnv(fixtureDir),
        encoding: "utf8",
      }).trim();
      expect(fixtureHead).toMatch(/^[0-9a-f]{40}$/);
      record("fixture-is-a-real-repo");
    } finally {
      if (saved.d === undefined) delete process.env.GIT_DIR;
      else process.env.GIT_DIR = saved.d;
      if (saved.i === undefined) delete process.env.GIT_INDEX_FILE;
      else process.env.GIT_INDEX_FILE = saved.i;
    }

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

    const saved = process.env.GIT_DIR;
    process.env.GIT_DIR = join(victim.dir, ".git");
    try {
      const inner = join(fixtureDir, "repo");
      mkdirSync(inner, { recursive: true });
      execFileSync("bash", [script, inner], { env: gitFixtureEnv(inner), encoding: "utf8" });
    } finally {
      if (saved === undefined) delete process.env.GIT_DIR;
      else process.env.GIT_DIR = saved;
    }

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

  test("the helper pins a committer identity (M7) and removes the location family (M1/M2)", () => {
    const dir = scratch("guard1-shape-");
    const env = gitFixtureEnv(dir);
    for (const k of [
      "GIT_DIR",
      "GIT_WORK_TREE",
      "GIT_INDEX_FILE",
      "GIT_COMMON_DIR",
      "GIT_OBJECT_DIRECTORY",
      "GIT_ALTERNATE_OBJECT_DIRECTORIES",
      "GIT_NAMESPACE",
    ]) {
      expect(env[k]).toBeUndefined();
    }
    // §M-7: an allowlist without an identity fails `Author identity unknown` on the first commit.
    for (const k of ["GIT_AUTHOR_NAME", "GIT_AUTHOR_EMAIL", "GIT_COMMITTER_NAME", "GIT_COMMITTER_EMAIL"]) {
      expect(env[k]).toBeTruthy();
    }
    expect(env.GIT_AUTHOR_EMAIL).toContain("@example.com");
    // §M-4: the ceiling must be the fixture's PARENT; the fixture-dir spelling does not stop escape.
    expect(env.GIT_CEILING_DIRECTORIES).toBeTruthy();
    expect(env.GIT_CEILING_DIRECTORIES).not.toBe(dir);
    // H3: TMPDIR is load-bearing and must survive the deny-list.
    if (process.env.TMPDIR) expect(env.TMPDIR).toBe(process.env.TMPDIR);
    record("helper-shape");
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
      "helper-shape",
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
