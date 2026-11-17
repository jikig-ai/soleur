// Module rows for server/git-isolated-dispose.ts (review fix round 1, WP1, simplicity H3): a failing dispose reports under its
// caller's feature, so a KB-sync leak no longer reads as the cc push's. Synthesized data only.
import { describe, expect, test, vi } from "vitest";

const H = vi.hoisted(() => ({ reports: [] as unknown[][] }));
vi.mock("@/server/observability", () => ({ reportSilentFallback: (...a: unknown[]) => H.reports.push(a) }));
vi.mock("../server/observability", () => ({ reportSilentFallback: (...a: unknown[]) => H.reports.push(a) }));

import { disposeIsolated } from "@/server/git-isolated-dispose";

const failing = () =>
  ({
    dispose: () => {
      throw Object.assign(new Error("boom /tmp/secret-path"), { code: "EBUSY" });
    },
  }) as never;

describe("disposeIsolated: the feature tag (simplicity H3)", () => {
  test("default stays cc-push; the KB sync passes session-sync with its own static message", () => {
    H.reports.length = 0;
    disposeIsolated(failing());
    disposeIsolated(failing(), "session-sync");
    expect(H.reports).toEqual([
      [null, { feature: "cc-push", op: "isolated-dir-dispose-failed", message: "cc-push: the isolated push directory could not be removed", tags: { class: "EBUSY" }, extra: { class: "EBUSY" } }],
      [null, { feature: "session-sync", op: "isolated-dir-dispose-failed", message: "KB sync: the isolated directory could not be removed", tags: { class: "EBUSY" }, extra: { class: "EBUSY" } }],
    ]);
  });

  test("an absent handle reports nothing", () => {
    H.reports.length = 0;
    disposeIsolated(undefined, "session-sync");
    expect(H.reports).toEqual([]);
  });
});
