import { describe, test, expect } from "bun:test";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { FINDING_CATEGORIES } from "../../skills/ux-audit/scripts/dedup-hash";

// finding-schema.test.ts — contract test for #2362.3.
// Validates that (a) finding.schema.json ships, (b) its category enum
// matches FINDING_CATEGORIES, and (c) the example JSON inside
// ux-design-lead.md §"UX Audit (Screenshots) > Output contract"
// conforms to the schema. Structural validation only (no Ajv
// dependency) — the schema file itself is the machine-readable
// deliverable.

const SCHEMA_PATH = resolve(
  import.meta.dir,
  "../../skills/ux-audit/references/finding.schema.json",
);

const AGENT_MD_PATH = resolve(
  import.meta.dir,
  "../../agents/product/design/ux-design-lead.md",
);

interface FindingSchema {
  $schema: string;
  type: string;
  required: string[];
  additionalProperties: boolean;
  properties: Record<
    string,
    { type: string; enum?: string[]; pattern?: string; maxLength?: number }
  >;
}

const SCHEMA = JSON.parse(readFileSync(SCHEMA_PATH, "utf8")) as FindingSchema;
const AGENT_MD = readFileSync(AGENT_MD_PATH, "utf8");

// Section-anchored extraction. ux-design-lead.md has three fenced
// json blocks; we want the one inside `## UX Audit (Screenshots) >
// ### Output contract`. Renaming either heading breaks this regex,
// which the `.not.toBeNull()` assertion catches loudly.
const OUTPUT_CONTRACT_MATCH = AGENT_MD.match(
  /## UX Audit \(Screenshots\)[\s\S]*?### Output contract[\s\S]*?```json\n([\s\S]*?)\n```/,
);

describe("finding.schema.json contract (#2362.3)", () => {
  test("schema file ships with Draft 2020-12 $schema", () => {
    expect(SCHEMA.$schema).toBe(
      "https://json-schema.org/draft/2020-12/schema",
    );
    expect(SCHEMA.type).toBe("object");
    expect(SCHEMA.additionalProperties).toBe(false);
  });

  test("schema category enum matches FINDING_CATEGORIES", () => {
    const schemaEnum = SCHEMA.properties.category.enum ?? [];
    expect([...schemaEnum].sort()).toEqual([...FINDING_CATEGORIES].sort());
  });

  test("schema severity enum is critical|high|medium|low", () => {
    const schemaEnum = SCHEMA.properties.severity.enum ?? [];
    expect([...schemaEnum].sort()).toEqual(
      ["critical", "high", "low", "medium"].sort(),
    );
  });

  test("schema requires all seven output-contract fields", () => {
    const required = new Set(SCHEMA.required);
    for (const field of [
      "route",
      "selector",
      "category",
      "severity",
      "title",
      "description",
      "fix_hint",
      "screenshot_ref",
    ]) {
      expect(required.has(field)).toBe(true);
    }
  });

  test("ux-design-lead.md Output contract example exists", () => {
    expect(OUTPUT_CONTRACT_MATCH).not.toBeNull();
  });

  test("ux-design-lead.md example validates against schema (structural)", () => {
    expect(OUTPUT_CONTRACT_MATCH).not.toBeNull();
    const examples = JSON.parse(OUTPUT_CONTRACT_MATCH![1]) as Array<
      Record<string, unknown>
    >;
    expect(Array.isArray(examples)).toBe(true);
    expect(examples.length).toBeGreaterThan(0);

    for (const example of examples) {
      for (const required of SCHEMA.required) {
        expect(example).toHaveProperty(required);
      }
      expect(SCHEMA.properties.category.enum).toContain(
        example.category as string,
      );
      expect(SCHEMA.properties.severity.enum).toContain(
        example.severity as string,
      );
    }
  });
});
