// #8505 — every production caller of the operator-key HTTP transport threads its
// cron name, so the credit marker is tagged `source=cron:<name>` and never
// `cron:unknown`. The caller SET is derived by walking server/, not listed, so a new
// caller joins the guarded set by existing. Comments are stripped before matching so
// a call described in prose cannot satisfy or dodge the check.

import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import { describe, expect, it } from "vitest";
import { stripComments } from "../helpers/strip-comments";

const SERVER = join(__dirname, "../../server");
const DEFINER = "inngest/functions/_cron-shared.ts";

function walk(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const p = join(dir, name);
    return statSync(p).isDirectory() ? walk(p) : p.endsWith(".ts") ? [p] : [];
  });
}


/** Each `postAnthropicMessage({ ... })` call body, balanced on braces. */
function callBodies(src: string): string[] {
  const out: string[] = [];
  let at = src.indexOf("postAnthropicMessage({");
  while (at !== -1) {
    let i = src.indexOf("{", at);
    let depth = 0;
    const start = i;
    for (; i < src.length; i++) {
      if (src[i] === "{") depth++;
      else if (src[i] === "}" && --depth === 0) break;
    }
    out.push(src.slice(start, i + 1));
    at = src.indexOf("postAnthropicMessage({", i);
  }
  return out;
}

const callers = walk(SERVER)
  .filter((p) => relative(SERVER, p) !== DEFINER)
  .map((p) => ({ file: relative(SERVER, p), calls: callBodies(stripComments(readFileSync(p, "utf8"))) }))
  .filter((c) => c.calls.length > 0);

describe("postAnthropicMessage callers thread markerSource (#8505)", () => {
  it("finds the known callers (the walk is not vacuous)", () => {
    expect(callers.map((c) => c.file).sort()).toEqual(
      expect.arrayContaining([
        "inngest/functions/cron-anthropic-credit-probe.ts",
        "inngest/functions/cron-compound-promote.ts",
        "inngest/functions/cron-weekly-release-digest.ts",
      ]),
    );
  });

  it("every call passes a markerSource", () => {
    const missing = callers.flatMap((c) =>
      c.calls.filter((body) => !/\bmarkerSource\s*:/.test(body)).map(() => c.file),
    );
    expect(missing).toEqual([]);
  });
});
