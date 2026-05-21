/**
 * PR-I (#4078) — Template registry exhaustiveness + hash determinism + collision regression.
 *
 * Three gates in one file (mirrors action-class-exhaustive.test.ts):
 *
 *   (a) Parity: TEMPLATE_REGISTRY covers every TemplateId (compile-time via
 *       `satisfies`, enforced at source). At runtime, every TEMPLATE_IDS
 *       entry must have a registry row.
 *   (b) Determinism: getTemplateHash returns the same hex for the same
 *       template_id across repeated calls.
 *   (c) Collision regression (TR8): pairwise distinct hashes for all
 *       (a, b) where a !== b in TEMPLATE_IDS. Catches the misconfiguration
 *       class where two registry rows accidentally share body_template.
 *   (d) Unknown-id fallback: getTemplateHash falls through to default_legacy
 *       when template_id is not a known TemplateId.
 */

import { createHash } from "node:crypto";

import { describe, expect, test } from "vitest";

import {
  TEMPLATE_IDS,
  TEMPLATE_REGISTRY,
  type TemplateId,
  getTemplateHash,
  isKnownTemplateId,
} from "@/server/templates/template-registry";

describe("template-registry — runtime gates", () => {
  test("(a) parity: every TEMPLATE_IDS entry has a TEMPLATE_REGISTRY row", () => {
    for (const id of TEMPLATE_IDS) {
      expect(TEMPLATE_REGISTRY).toHaveProperty(id);
      const row = TEMPLATE_REGISTRY[id];
      expect(row.id).toBe(id);
      expect(typeof row.body_template).toBe("string");
      expect(row.body_template.length).toBeGreaterThan(0);
    }
  });

  test("(b) determinism: getTemplateHash returns same hex for repeated calls", () => {
    for (const id of TEMPLATE_IDS) {
      const h1 = getTemplateHash({ template_id: id });
      const h2 = getTemplateHash({ template_id: id });
      expect(h1).toBe(h2);
      expect(h1).toMatch(/^[a-f0-9]{64}$/);
    }
  });

  test("(b2) hash equals sha256(body_template)", () => {
    for (const id of TEMPLATE_IDS) {
      const expected = createHash("sha256")
        .update(TEMPLATE_REGISTRY[id].body_template)
        .digest("hex");
      expect(getTemplateHash({ template_id: id })).toBe(expected);
    }
  });

  test("(c) collision regression (TR8): pairwise distinct hashes for all template-id pairs", () => {
    const hashesById = new Map<TemplateId, string>();
    for (const id of TEMPLATE_IDS) {
      hashesById.set(id, getTemplateHash({ template_id: id }));
    }
    const ids = [...TEMPLATE_IDS];
    for (let i = 0; i < ids.length; i++) {
      for (let j = i + 1; j < ids.length; j++) {
        const a = ids[i]!;
        const b = ids[j]!;
        expect(
          hashesById.get(a),
          `hash collision between template-id '${a}' and '${b}' — body_template values must be distinct`,
        ).not.toBe(hashesById.get(b));
      }
    }
  });

  test("(d) unknown template_id falls back to default_legacy hash", () => {
    const fallback = getTemplateHash({ template_id: "default_legacy" });
    // Cast: the function accepts any string (TemplateId | string) per plan §Phase 1.
    expect(
      getTemplateHash({ template_id: "definitely_not_a_real_template_id" as unknown as TemplateId }),
    ).toBe(fallback);
  });

  test("(d2) missing template_id (null/undefined) also falls back to default_legacy", () => {
    const fallback = getTemplateHash({ template_id: "default_legacy" });
    expect(getTemplateHash({ template_id: null as unknown as TemplateId })).toBe(fallback);
    expect(getTemplateHash({ template_id: undefined as unknown as TemplateId })).toBe(fallback);
  });

  test("(e) isKnownTemplateId typeguard discriminates known from unknown", () => {
    expect(isKnownTemplateId("default_legacy")).toBe(true);
    expect(isKnownTemplateId("not_a_template")).toBe(false);
    expect(isKnownTemplateId("")).toBe(false);
  });
});
