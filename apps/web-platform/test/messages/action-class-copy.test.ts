/**
 * Phase 1 (#4067-followup) — Content-shape gates for `ACTION_CLASS_COPY`.
 *
 * Six runtime assertions per AC1:
 *   1. every `ACTION_CLASSES` member has a copy entry
 *   2. every entry has non-empty `title`
 *   3. every entry has non-empty `description`
 *   4. every `title` ≤ 60 chars (founder-readable cap)
 *   5. every `description` ≤ 200 chars (one-sentence cap)
 *   6. `category` ∈ the 8-value editorial set
 *   7. no dotted-ID leakage in titles (no `.`, no `_`)
 *
 * Registry-parity gate (every ActionClass has an entry) is also enforced
 * at compile time via the `satisfies Record<ActionClass, …>` rail in
 * `lib/messages/action-class-copy.ts` and a runtime parity assertion in
 * `test/server/scope-grants/action-class-exhaustive.test.ts`. This file
 * focuses on CONTENT shape.
 */

import { describe, expect, test } from "vitest";

import { ACTION_CLASSES } from "@/server/scope-grants/action-class-map";
import {
  ACTION_CLASS_COPY,
  CATEGORY_ORDER,
} from "@/lib/messages/action-class-copy";

const TITLE_MAX = 60;
const DESCRIPTION_MAX = 200;

describe("ACTION_CLASS_COPY content shape", () => {
  test("every ACTION_CLASSES member has a copy entry", () => {
    for (const ac of ACTION_CLASSES) {
      expect(ACTION_CLASS_COPY).toHaveProperty(ac);
    }
  });

  test("every entry has non-empty title and description", () => {
    for (const ac of ACTION_CLASSES) {
      const copy = ACTION_CLASS_COPY[ac];
      expect(copy.title.trim().length).toBeGreaterThan(0);
      expect(copy.description.trim().length).toBeGreaterThan(0);
    }
  });

  test(`every title ≤ ${TITLE_MAX} chars`, () => {
    for (const ac of ACTION_CLASSES) {
      expect(ACTION_CLASS_COPY[ac].title.length).toBeLessThanOrEqual(
        TITLE_MAX,
      );
    }
  });

  test(`every description ≤ ${DESCRIPTION_MAX} chars`, () => {
    for (const ac of ACTION_CLASSES) {
      expect(
        ACTION_CLASS_COPY[ac].description.length,
      ).toBeLessThanOrEqual(DESCRIPTION_MAX);
    }
  });

  test("every category ∈ the 8-value editorial set", () => {
    for (const ac of ACTION_CLASSES) {
      expect(CATEGORY_ORDER).toContain(ACTION_CLASS_COPY[ac].category);
    }
  });

  test("titles contain no dotted-ID characters (no `.`, no `_`)", () => {
    for (const ac of ACTION_CLASSES) {
      const title = ACTION_CLASS_COPY[ac].title;
      expect(title).not.toMatch(/[._]/);
    }
  });

  test("CATEGORY_ORDER has exactly the 8 editorial categories", () => {
    expect(CATEGORY_ORDER).toEqual([
      "Money",
      "Engineering",
      "Triage",
      "Security",
      "Knowledge",
      "Customer replies",
      "Brand-critical sends",
      "Infrastructure",
    ]);
  });
});
