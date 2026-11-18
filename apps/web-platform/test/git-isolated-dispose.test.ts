// Module rows for server/git-isolated-dispose.ts (review fix round 1, WP1, simplicity H3): a failing dispose reports under its
// caller's feature, so a KB-sync leak no longer reads as the cc push's. Synthesized data only.
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import ts from "typescript";
import { describe, expect, test, vi } from "vitest";
import { parseSource } from "./approval/source-scan";

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

  test("the self-heal and the held-count refresh report under the feature their other Sentry ops use", () => {
    H.reports.length = 0;
    disposeIsolated(failing(), "kb-route-helpers");
    disposeIsolated(failing(), "kb-sync-held");
    expect(H.reports).toEqual([
      [null, { feature: "kb-route-helpers", op: "isolated-dir-dispose-failed", message: "KB self-heal: the isolated directory could not be removed", tags: { class: "EBUSY" }, extra: { class: "EBUSY" } }],
      [null, { feature: "kb-sync-held", op: "isolated-dir-dispose-failed", message: "KB sync held count: the isolated directory could not be removed", tags: { class: "EBUSY" }, extra: { class: "EBUSY" } }],
    ]);
  });

  test("every server call site passes its caller's feature (only the cc push keeps the default)", () => {
    const APP = join(__dirname, "..");
    const walk = (d: string): string[] =>
      readdirSync(d).flatMap((f) => (statSync(join(d, f)).isDirectory() ? walk(join(d, f)) : /\.ts$/.test(f) ? [join(d, f)] : []));
    const sites: string[] = [];
    for (const abs of walk(join(APP, "server"))) {
      const src = readFileSync(abs, "utf8");
      if (!src.includes("disposeIsolated(")) continue;
      const file = relative(APP, abs);
      const visit = (n: ts.Node): void => {
        if (ts.isCallExpression(n) && ts.isIdentifier(n.expression) && n.expression.text === "disposeIsolated") {
          const f = n.arguments[1];
          sites.push(`${file} ${f && ts.isStringLiteral(f) ? f.text : f ? "<computed>" : "<default>"}`);
        }
        ts.forEachChild(n, visit);
      };
      visit(parseSource(src, file));
    }
    expect(sites.sort()).toEqual([
      "server/kb-sync-held-refresh.ts kb-sync-held",
      "server/kb-sync-publish.ts session-sync",
      "server/push-branch.ts <default>",
      "server/push-branch.ts <default>",
      "server/session-sync.ts session-sync",
      "server/workspace-sync.ts kb-route-helpers",
    ]);
  });

  test("an absent handle reports nothing", () => {
    H.reports.length = 0;
    disposeIsolated(undefined, "session-sync");
    expect(H.reports).toEqual([]);
  });
});
