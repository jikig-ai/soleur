import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, resolve } from "node:path";

import { describe, expect, it } from "vitest";

// #10136 (CTO G4, plan Phase 3 "Canary layer" check 3): the ci-deploy canary proves the verified-TLS link by sending a REAL
// synthetic event, `soleur.tls-canary.ping`, from inside the canary container. That is only safe if NO function triggers on it:
// otherwise every deploy would run production work as a side effect of a connectivity check. This test greps the FULL trigger
// set under server/inngest/ (string-literal `event:` triggers, the exported *_EVENT constants functions import, and
// wildcard patterns) and fails if the canary name is among them, directly or through a glob.
//
// A static scan cannot see an event name computed at runtime, so the scan also refuses the canary's distinctive fragment
// anywhere in the server tree (a dynamic builder would have to spell it), and it is made non-vacuous by requiring the collected
// set to contain a known real trigger and a plausible number of names.

const CANARY_EVENT = "soleur.tls-canary.ping";
const FUNCTIONS_DIR = resolve(__dirname, "../../../server/inngest/functions");
const SERVER_DIR = resolve(__dirname, "../../../server");

function walk(dir: string, out: string[] = []): string[] {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    const st = statSync(p);
    if (st.isDirectory()) walk(p, out);
    else if (/\.(ts|tsx|template)$/.test(name) && !/\.test\.ts$/.test(name)) out.push(p);
  }
  return out;
}

function globToRegExp(glob: string): RegExp {
  return new RegExp(`^${glob.split("*").map((s) => s.replace(/[.+?^${}()|[\]\\]/g, "\\$&")).join(".*")}$`);
}

function collectTriggerEvents(): { names: Set<string>; byFile: Map<string, string[]> } {
  const names = new Set<string>();
  const byFile = new Map<string, string[]>();
  const add = (file: string, n: string) => {
    names.add(n);
    byFile.set(file, [...(byFile.get(file) ?? []), n]);
  };
  for (const file of walk(resolve(SERVER_DIR, "inngest"))) {
    const src = readFileSync(file, "utf8");
    // `event: "x"` (createFunction triggers and waitForEvent), in any quoting style
    for (const m of src.matchAll(/\bevent\s*:\s*(["'`])([^"'`$\n]+)\1/g)) add(file, m[2]);
    // exported event-name constants that functions import into a trigger
    for (const m of src.matchAll(/\bconst\s+[A-Z0-9_]*EVENT[A-Z0-9_]*\s*(?::\s*[\w<>[\]"' |]+)?=\s*(["'`])([^"'`$\n]+)\1/g)) add(file, m[2]);
  }
  return { names, byFile };
}

describe("tls-canary event: no function may trigger on it", () => {
  const { names } = collectTriggerEvents();

  it("the trigger scan is not vacuous (it finds the known reminder trigger and a plausible number of names)", () => {
    expect(names.has("reminder.scheduled"), "the scan no longer sees event-scheduled-reminder's trigger").toBe(true);
    expect(names.size).toBeGreaterThan(15);
    expect(readdirSync(FUNCTIONS_DIR).length).toBeGreaterThan(40);
  });

  it(`no trigger or event constant is exactly ${CANARY_EVENT}`, () => {
    expect(names.has(CANARY_EVENT)).toBe(false);
  });

  it("no wildcard trigger pattern matches the canary event", () => {
    const wild = [...names].filter((n) => n.includes("*"));
    for (const w of wild) expect(globToRegExp(w).test(CANARY_EVENT), `wildcard trigger ${w} matches ${CANARY_EVENT}`).toBe(false);
    // a catch-all pattern is a wildcard too
    expect(names.has("*")).toBe(false);
  });

  it("the canary name (or its distinctive fragment) is spelled nowhere in the non-test server tree", () => {
    const hits: string[] = [];
    for (const file of walk(SERVER_DIR)) {
      const src = readFileSync(file, "utf8");
      if (src.includes("tls-canary") || src.includes(CANARY_EVENT)) hits.push(file);
    }
    expect(hits, "a server file names the TLS canary event: if a function triggers on it every deploy runs production work").toEqual([]);
  });

  it("the scanner itself sees a planted canary trigger (negative control)", () => {
    const planted = `inngest.createFunction({ id: "x", triggers: { event: "${CANARY_EVENT}" } }, async () => {});`;
    const found = [...planted.matchAll(/\bevent\s*:\s*(["'`])([^"'`$\n]+)\1/g)].map((m) => m[2]);
    expect(found).toEqual([CANARY_EVENT]);
    expect(globToRegExp("soleur.*").test(CANARY_EVENT)).toBe(true);
    expect(globToRegExp("cron/*").test(CANARY_EVENT)).toBe(false);
  });
});
