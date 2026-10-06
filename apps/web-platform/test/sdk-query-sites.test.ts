import { describe, it, expect } from "vitest";
import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";

import { stripComments } from "./helpers/strip-comments";

// W1 (#9601, ADR-272) — a census of every place a Claude CLI session can be
// started through the Agent SDK. The credential deny rides the options the two
// session factories build with `buildAgentQueryOptions`; a NEW `query(` call
// that builds its own options gets no sandbox and no deny, and inherits whatever
// environment the server has. No suite saw such a site before (a `query({options:
// {allowedTools: []}})` file passed everything), so each site is named here with
// the control it relies on, and a new one fails this test until someone decides.
//
// Population: any non-test module under server/, lib/ or app/ that imports a
// session-starting export of the SDK (`query`, `startup`, `prewarm`; static or
// aliased), any namespace import of it, or a dynamic import of it. Comments are stripped
// by the TypeScript parser, so prose mentioning the package does not count.

const ROOT = path.join(__dirname, "..");
const SCAN_DIRS = ["server", "lib", "app"];
const SDK = "@anthropic-ai/claude-agent-sdk";

// file -> [why it is acceptable, source anchor proving the control is in place]
const SITES: Record<string, { control: string; anchor: RegExp }> = {
  [path.join("server", "agent-runner.ts")]: {
    control: "legacy session: options built by buildAgentQueryOptions (sandbox + credential deny)",
    anchor: /\bbuildAgentQueryOptions\(/,
  },
  [path.join("server", "cc-dispatcher.ts")]: {
    control: "Concierge session: options built by buildAgentQueryOptions (sandbox + credential deny)",
    anchor: /\bbuildAgentQueryOptions\(/,
  },
  [path.join("server", "pdf-chapter-router.ts")]: {
    control: "single routing turn with no built-in tool and no settings (inherits the server env, so nothing may run)",
    anchor: /\btools:\s*\[\]/,
  },
};

function* walk(dir: string): Generator<string> {
  let entries: import("node:fs").Dirent[];
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return;
  }
  for (const e of entries) {
    const full = path.join(dir, e.name);
    if (e.isDirectory()) {
      if (e.name === "node_modules" || e.name === ".next") continue;
      yield* walk(full);
    } else if (
      /\.(ts|tsx|mts|js|mjs|cjs)$/.test(e.name) &&
      !/\.(test|spec)\.(ts|tsx|mts|js|mjs|cjs)$/.test(e.name)
    ) {
      yield full;
    }
  }
}

const STATIC_QUERY = new RegExp(
  `import\\s*\\{[^}]*\\b(?:query|startup|prewarm)\\b[^}]*\\}\\s*from\\s*["']${SDK}["']`,
);
const NAMESPACE = new RegExp(`import\\s*\\*\\s*as\\s+\\w+\\s+from\\s*["']${SDK}["']`);
const DYNAMIC = new RegExp(`import\\(\\s*["']${SDK}["']\\s*\\)`);

describe("every Agent SDK query() site is accounted for (W1)", () => {
  const found = new Map<string, string>();
  const scanned: string[] = [];
  for (const base of SCAN_DIRS) {
    for (const file of walk(path.join(ROOT, base))) {
      const rel = path.relative(ROOT, file);
      scanned.push(rel);
      const raw = readFileSync(file, "utf8");
      // Prefilter: stripping only removes text, and the parser-based stripper is slow.
      if (!raw.includes(SDK)) continue;
      const code = stripComments(raw, rel);
      if (STATIC_QUERY.test(code) || NAMESPACE.test(code) || DYNAMIC.test(code)) found.set(rel, code);
    }
  }

  it("the scan is not vacuous", () => {
    expect(scanned.length).toBeGreaterThan(100);
    expect(scanned).toContain(path.join("server", "agent-runner.ts"));
  });

  it("the sites that start a CLI session are exactly the named ones", () => {
    expect([...found.keys()].sort()).toEqual(Object.keys(SITES).sort());
  });

  it.each(Object.entries(SITES))("%s keeps its control in place", (rel, { anchor }) => {
    expect(found.get(rel), rel).toMatch(anchor);
  });
});
