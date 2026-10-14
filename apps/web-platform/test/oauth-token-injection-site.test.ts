import { describe, it, expect } from "vitest";
import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";

import { stripComments } from "./helpers/strip-comments";

// feat-operator-cc-oauth FR6 — CWE-526 single-injection-site guard.
//
// `CLAUDE_CODE_OAUTH_TOKEN` is a subprocess auth env var. It must be SET in
// EXACTLY ONE place — `server/agent-env.ts buildAgentEnv` — so the
// deny-by-default subprocess env allowlist has a single auditable injection
// point. Any other module naming the literal is a potential 2nd injection
// site (a direct `process.env` write that bypasses the allowlist), the bug
// class this test exists to catch. Negative-space source grep, kept in a
// standalone file (no `node:fs` mock) per
// `2026-04-17-regex-on-source-delegation-tests-trim-to-negative-space`.
//
// W1 (#9601, ADR-272) moved the NAME into `server/agent-auth-env-vars.ts` so the
// sandbox config can deny exactly the set `buildAgentEnv` injects. That module
// only DEFINES names. Naming the literal through an identifier would otherwise
// slip past a grep for the literal, so the identifiers are pinned too: who may
// reference the shared names, and that the definition module never writes env.

const ROOT = path.join(__dirname, "..");
const SCAN_DIRS = ["server", "lib", "app"];
const LITERAL = "CLAUDE_CODE_OAUTH_TOKEN";
const AUTH_NAMES_MODULE = path.join("server", "agent-auth-env-vars.ts");
const ALLOWED = new Set([path.join("server", "agent-env.ts"), AUTH_NAMES_MODULE]);
// Identifiers that carry the auth variable names, and the only modules that
// may reference them: the injector reads the single names; the sandbox config
// reads the full set to deny it.
const NAME_IDENTIFIER_USERS: Record<string, Set<string>> = {
  OAUTH_ENV_VAR: new Set([path.join("server", "agent-env.ts"), AUTH_NAMES_MODULE]),
  API_KEY_ENV_VAR: new Set([path.join("server", "agent-env.ts"), AUTH_NAMES_MODULE]),
  AGENT_AUTH_ENV_VARS: new Set([
    path.join("server", "agent-runner-sandbox-config.ts"),
    AUTH_NAMES_MODULE,
  ]),
};

function* walkTsFiles(dir: string): Generator<string> {
  let entries: import("node:fs").Dirent[];
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return; // dir absent — nothing to scan
  }
  for (const e of entries) {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) {
      if (e.name === "node_modules" || e.name === ".next") continue;
      yield* walkTsFiles(full);
    } else if (
      /\.(ts|tsx|mts|js|mjs|cjs)$/.test(e.name) &&
      !/\.(test|spec)\.(ts|tsx|mts|js|mjs|cjs)$/.test(e.name)
    ) {
      yield full;
    }
  }
}

describe("CLAUDE_CODE_OAUTH_TOKEN single injection site (CWE-526)", () => {
  it("is named only by server/agent-env.ts and the names module", () => {
    const offenders: string[] = [];
    for (const base of SCAN_DIRS) {
      for (const file of walkTsFiles(path.join(ROOT, base))) {
        const rel = path.relative(ROOT, file);
        if (ALLOWED.has(rel)) continue;
        if (readFileSync(file, "utf8").includes(LITERAL)) offenders.push(rel);
      }
    }
    expect(offenders).toEqual([]);
  });

  it("the shared auth-name identifiers are used only by their sanctioned modules", () => {
    const offenders: string[] = [];
    for (const base of SCAN_DIRS) {
      for (const file of walkTsFiles(path.join(ROOT, base))) {
        const rel = path.relative(ROOT, file);
        const raw = readFileSync(file, "utf8");
        // Cheap prefilter: stripping only removes text, so a file whose raw text
        // never names an identifier cannot use it. The parser-based stripper is
        // exact but slow, so it runs only on the few files that mention one.
        const candidates = Object.entries(NAME_IDENTIFIER_USERS).filter(
          ([ident, allowed]) => !allowed.has(rel) && raw.includes(ident),
        );
        if (candidates.length === 0) continue;
        const text = stripComments(raw, rel);
        for (const [ident] of candidates) {
          if (new RegExp(`\\b${ident}\\b`).test(text)) offenders.push(`${rel} -> ${ident}`);
        }
      }
    }
    expect(offenders).toEqual([]);
  });

  it("the scan is not vacuous: it sees the injector, the sandbox config and the names module", () => {
    const seen = new Set<string>();
    for (const base of SCAN_DIRS) {
      for (const file of walkTsFiles(path.join(ROOT, base))) seen.add(path.relative(ROOT, file));
    }
    for (const must of [
      path.join("server", "agent-env.ts"),
      path.join("server", "agent-runner-sandbox-config.ts"),
      AUTH_NAMES_MODULE,
    ]) {
      expect(seen.has(must), must).toBe(true);
    }
    expect(seen.size).toBeGreaterThan(100);
  });

  it("the names module only defines names: no imports, no environment access, no re-exports", () => {
    const raw = readFileSync(path.join(ROOT, AUTH_NAMES_MODULE), "utf8");
    // The instrument is not empty: the module really defines the names.
    expect(raw).toContain(LITERAL);
    const code = stripComments(raw, AUTH_NAMES_MODULE);
    // Any import (`import { env } from "node:process"`), `process`/`globalThis`
    // access in any spelling (`process["env"]`), require/eval, or an env word.
    expect(code).not.toMatch(/\b(import|require|process|globalThis|eval|Function|env)\b/);
    // Re-export forms would hand the names to a module this test does not scan.
    expect(code).not.toMatch(/\bexport\s*(\*|\{)/);
  });
});
