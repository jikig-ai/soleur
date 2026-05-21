/**
 * Phase 1 (#4067-followup) — Content-shape gates for `ACTION_CLASS_COPY`.
 *
 * Seven runtime assertions per AC1, applied per-entry via `test.each` so
 * a failure surfaces the offending action class in the test name (not
 * just the matcher diff):
 *   1. every `ACTION_CLASSES` member has a copy entry
 *   2. non-empty `title`
 *   3. non-empty `description`
 *   4. `title` ≤ 60 chars (founder-readable cap)
 *   5. `description` ≤ 200 chars (one-sentence cap)
 *   6. `category` ∈ the 8-value editorial set
 *   7. no dotted-ID leakage in titles (no `.`, no `_`)
 *
 * The `CATEGORY_ORDER` constant is asserted exactly — adding a category
 * is a UX decision that should explicitly bump this test.
 *
 * Registry-parity gate (every ActionClass has an entry) is also enforced
 * at compile time via the `satisfies Record<ActionClass, …>` rail in
 * `lib/messages/action-class-copy.ts` and a runtime parity assertion in
 * `test/server/scope-grants/action-class-exhaustive.test.ts`.
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
  test.each(ACTION_CLASSES)("%s has a copy entry", (ac) => {
    expect(ACTION_CLASS_COPY).toHaveProperty(ac);
  });

  test.each(ACTION_CLASSES)("%s has non-empty title and description", (ac) => {
    const copy = ACTION_CLASS_COPY[ac];
    expect(copy.title.trim().length).toBeGreaterThan(0);
    expect(copy.description.trim().length).toBeGreaterThan(0);
  });

  test.each(ACTION_CLASSES)(
    `%s title ≤ ${TITLE_MAX} chars`,
    (ac) => {
      expect(ACTION_CLASS_COPY[ac].title.length).toBeLessThanOrEqual(
        TITLE_MAX,
      );
    },
  );

  test.each(ACTION_CLASSES)(
    `%s description ≤ ${DESCRIPTION_MAX} chars`,
    (ac) => {
      expect(ACTION_CLASS_COPY[ac].description.length).toBeLessThanOrEqual(
        DESCRIPTION_MAX,
      );
    },
  );

  test.each(ACTION_CLASSES)(
    "%s category ∈ the 8-value editorial set",
    (ac) => {
      expect(CATEGORY_ORDER).toContain(ACTION_CLASS_COPY[ac].category);
    },
  );

  test.each(ACTION_CLASSES)(
    "%s title contains no dotted-ID characters",
    (ac) => {
      expect(ACTION_CLASS_COPY[ac].title).not.toMatch(/[._]/);
    },
  );

  // Intentional duplication — changing CATEGORY_ORDER is a UX decision
  // that should require an explicit test update.
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
