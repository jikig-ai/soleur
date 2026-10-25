// The shared front-matter guard (#8293 review). gray-matter MERGES `engines` over its defaults, so
// `engines: {}` never disabled the `js` engine. Each of the two defences is pinned ALONE here (the other
// disabled), because a single layer can otherwise rot unseen while the combination stays green.
import { beforeEach, describe, expect, test } from "vitest";
import matter from "gray-matter";
import {
  SAFE_MATTER_OPTIONS,
  hasPlainFrontMatterOpener,
  hasTaggedFrontMatterOpener,
  parseFrontMatterSafe,
} from "@/server/front-matter-guard";

const g = globalThis as Record<string, unknown>;
const payload = (open: string, nl = "\n") => `${open}${nl}(globalThis.FM_GUARD_PWNED = 1, { title: 'x' })${nl}---${nl}body`;
const OPENERS: Array<[string, string]> = [
  ["js", "---js"],
  ["javascript", "---javascript"],
  ["upper", "---JS"],
  ["mixed", "---Javascript"],
  ["space", "--- js"],
  ["tab", "---\tjs"],
  ["NBSP", "--- js"],
];

beforeEach(() => {
  delete g.FM_GUARD_PWNED;
});

describe("front-matter guard", () => {
  test("positive control: plain openers parse (LF, CRLF, BOM, trailing blanks)", () => {
    expect(parseFrontMatterSafe("---\ntitle: ok\n---\nbody").data).toEqual({ title: "ok" });
    expect(parseFrontMatterSafe("﻿---\r\ntitle: ok\r\n---\r\nbody").data).toEqual({ title: "ok" });
    expect(parseFrontMatterSafe("---  \ntitle: ok\n---\nbody").data).toEqual({ title: "ok" });
    expect(parseFrontMatterSafe("no front matter").data).toEqual({});
  });

  test.each(OPENERS)("layer 1 alone: a %s opener is flagged as tagged, never plain", (_n, open) => {
    for (const nl of ["\n", "\r\n", "\r"]) {
      expect(hasTaggedFrontMatterOpener(payload(open, nl))).toBe(true);
      expect(hasPlainFrontMatterOpener(payload(open, nl))).toBe(false);
    }
  });

  test.each(OPENERS)("layer 2 alone: the engine overrides make a %s block throw instead of run", (_n, open) => {
    // Bypass the opener gate on purpose: only gray-matter plus SAFE_MATTER_OPTIONS.
    try {
      matter(payload(open), SAFE_MATTER_OPTIONS);
    } catch {
      /* the throw is the point */
    }
    expect(g.FM_GUARD_PWNED).toBeUndefined();
  });

  test("control: without the overrides the same payload DOES run (the test can fail)", () => {
    matter(payload("---js"), { engines: {} });
    expect(g.FM_GUARD_PWNED).toBe(1);
  });

  test.each(OPENERS)("the combined helper throws on %s and never runs the block", (_n, open) => {
    expect(() => parseFrontMatterSafe(payload(open))).toThrow();
    expect(g.FM_GUARD_PWNED).toBeUndefined();
  });

  test("layer 1 is wired into the helper: a harmless tagged opener (no js involved) is refused by the gate itself", () => {
    // `yaml` is a registered, safe engine, so only the opener gate can refuse this one.
    expect(() => parseFrontMatterSafe("---yaml\ntitle: x\n---\nbody")).toThrow(/tagged front matter opener/);
  });

  test("a tagged opener with no newline at all still cannot run", () => {
    expect(() => parseFrontMatterSafe("---js")).toThrow();
    expect(g.FM_GUARD_PWNED).toBeUndefined();
  });

  test("a BOM before a tagged opener is refused too", () => {
    expect(() => parseFrontMatterSafe(`﻿${payload("---js")}`)).toThrow();
    expect(g.FM_GUARD_PWNED).toBeUndefined();
  });
});
