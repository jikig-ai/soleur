import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";

// #12910 (architecture R2-7, test-design N5) — server/index.ts must turn the pure
// hostIdentityBootReport() verdict into the production Sentry fallback event. The
// verdict is unit-tested in host-identity.test.ts; this pins the boot wiring, which
// nothing else exercises: a dropped call or a dropped branch would leave the
// #12910 incident shape (a prod host off its verified key) silent again.
//
// Comment-stripped (the quiet-window-wiring.test.ts stripper) so the prose that
// explains the wiring cannot satisfy the assertion that guards it; anchored on
// call forms and object-literal keys a comment cannot produce, each unique in
// its scope.
const read = (p: string) => readFileSync(join(__dirname, "..", p), "utf8");
const stripComments = (s: string) =>
  s
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/^\s*\/\/.*$/gm, "")
    .replace(/(^|[^:"'`])\/\/.*$/gm, "$1");
const count = (s: string, needle: string) => s.split(needle).length - 1;

/** The `{...}` body that opens at the first `{` at or after `from`, braces balanced. */
function braceBody(s: string, from: number): string | null {
  const open = s.indexOf("{", from);
  if (open < 0) return null;
  let depth = 0;
  for (let i = open; i < s.length; i++) {
    if (s[i] === "{") depth++;
    else if (s[i] === "}" && --depth === 0) return s.slice(open, i + 1);
  }
  return null;
}

/** Every violated wiring rule (empty = wired). Pure over the source text. */
function bootWiringViolations(rawSrc: string): string[] {
  const src = stripComments(rawSrc);
  const out: string[] = [];
  if (count(src, "hostIdentityBootReport(") !== 1) {
    out.push("hostIdentityBootReport( must be called exactly once");
    return out;
  }
  const call = /const (\w+) = hostIdentityBootReport\(\)/.exec(src);
  if (!call) return [...out, "the report must be bound: const <x> = hostIdentityBootReport()"];
  const v = call[1];
  // The boot block: the statements after the call, up to its enclosing block's end.
  const tail = src.slice(call.index);
  const branchNeedle = `if (${v}.reportFallback) {`;
  if (count(tail, branchNeedle) !== 1) {
    return [...out, `exactly one branch \`${branchNeedle}\` after the call`];
  }
  const body = braceBody(tail, tail.indexOf(branchNeedle));
  if (!body) return [...out, "unbalanced reportFallback branch body"];
  for (const needle of [
    "reportSilentFallback(",
    'op: "resolveHostId.key-fallback"',
    `tags: { source: ${v}.source }`,
  ]) {
    if (count(body, needle) !== 1) out.push(`reportFallback branch must contain exactly one \`${needle}\``);
  }
  return out;
}

describe("host identity boot wiring (server/index.ts, #12910)", () => {
  const src = read("server/index.ts");

  it("the boot block calls hostIdentityBootReport() and, on reportFallback, reports resolveHostId.key-fallback tagged by source", () => {
    expect(bootWiringViolations(src)).toEqual([]);
  });

  // Non-vacuity: the same checker rejects the real file with each load-bearing
  // piece removed or commented out.
  it.each([
    ["the reportSilentFallback call deleted", (s: string) => s.replace("reportSilentFallback(null, {", "void ({")],
    ["the reportSilentFallback call commented out", (s: string) => s.replace("reportSilentFallback(null, {", "// reportSilentFallback(null, {\n void ({")],
    ["the reportFallback branch dropped", (s: string) => s.replace(/if \((\w+)\.reportFallback\) \{/, "if (true) {")],
    ["the op renamed", (s: string) => s.replace('op: "resolveHostId.key-fallback"', 'op: "resolveHostId.other"')],
    ["the source tag dropped", (s: string) => s.replace(/tags: \{ source: (\w+)\.source \},/, "")],
    ["the report call commented out", (s: string) => s.replace("const boot = hostIdentityBootReport();", "// const boot = hostIdentityBootReport();\n const boot = { reportFallback: false, source: '', line: '' };")],
  ])("rejects a copy with %s", (_name, mutate) => {
    const mutated = mutate(src);
    expect(mutated).not.toBe(src); // the mutation applied to today's source
    expect(bootWiringViolations(mutated).length).toBeGreaterThan(0);
  });
});
