import { describe, expect, it, vi } from "vitest";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import matter from "gray-matter";
import { extractEnabledFlag } from "@/server/inngest/functions/cron-compound-promote";

// AC10: gray-matter YAML-1.1 trap probe. Verifies the handler's config
// extractor normalizes various YAML boolean forms to the correct boolean.
// Even though extractEnabledFlag uses hand-rolled regex (not gray-matter),
// this test locks the contract against the coercion trap.

describe("cron-compound-promote gray-matter YAML 1.1 trap", () => {
  const cases: Array<{ input: string; expected: boolean; label: string }> = [
    { input: "enabled: true", expected: true, label: "unquoted true" },
    { input: 'enabled: "true"', expected: true, label: "quoted true" },
    { input: "enabled: yes", expected: true, label: "YAML 1.1 yes" },
    { input: "enabled: 1", expected: true, label: "YAML 1.1 numeric 1" },
    { input: "enabled: TRUE", expected: true, label: "uppercase TRUE" },
    { input: "enabled: false", expected: false, label: "unquoted false" },
    { input: 'enabled: "false"', expected: false, label: "quoted false" },
    { input: "enabled: no", expected: false, label: "YAML 1.1 no" },
    { input: "enabled: 0", expected: false, label: "YAML 1.1 numeric 0" },
  ];

  for (const { input, expected, label } of cases) {
    it(`extractEnabledFlag: ${label} → ${expected}`, () => {
      const raw = `# Config\n${input}\n`;
      expect(extractEnabledFlag(raw)).toBe(expected);
    });
  }

  it("gray-matter coercion: unquoted 'true' becomes JS boolean true", () => {
    const parsed = matter("---\nenabled: true\n---\n");
    expect(typeof parsed.data.enabled).toBe("boolean");
    expect(parsed.data.enabled).toBe(true);
  });

  it("gray-matter coercion: quoted 'true' stays string", () => {
    const parsed = matter('---\nenabled: "true"\n---\n');
    expect(typeof parsed.data.enabled).toBe("string");
    expect(parsed.data.enabled).toBe("true");
  });

  it("extractEnabledFlag handles missing enabled key", () => {
    expect(extractEnabledFlag("# nothing here\nfoo: bar\n")).toBe(false);
  });

  it("extractEnabledFlag handles inline comment after value", () => {
    expect(extractEnabledFlag("enabled: true # opt in\n")).toBe(true);
  });
});
