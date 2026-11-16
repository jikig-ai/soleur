// #12600, CTO rulings D20 and D23: `firstAppFrame`, the code location the syncPush outer catch and `self-heal-failed` put in
// `extra.frame`. D23: the frame carries the column (a minified chunk is one long line), and a production-shaped stack (the
// esbuild bundle `dist/server/index.cjs`, Next's `.next/server/chunks/*.js`) names the bundle it ran from, never a source path
// that does not exist. Synthesized stacks only (cq-test-fixtures-synthesized-only).
import { describe, expect, test } from "vitest";
import { firstAppFrame } from "../../server/error-frame";

const withStack = (frames: string[], message = "boom", name = "Error"): Error => {
  const err = new Error(message);
  err.name = name;
  err.stack = [`${name}: ${message}`, ...frames].join("\n");
  return err;
};

describe("firstAppFrame (D20, D23)", () => {
  test("a source-tree frame is repo-relative file:line:column", () => {
    const err = withStack([
      "    at Object.next (node:internal/streams/x:10:3)",
      "    at helper (/srv/app/node_modules/pkg/index.js:5:1)",
      "    at publishKbOnly (/srv/app/apps/web-platform/server/kb-sync-publish.ts:812:17)",
    ]);
    expect(firstAppFrame(err)).toBe("server/kb-sync-publish.ts:812:17");
  });

  test("a frame with no column keeps file:line", () => {
    expect(firstAppFrame(withStack(["    at /srv/app/apps/web-platform/lib/x.ts:4"]))).toBe("lib/x.ts:4");
  });

  test("production (bundle) shape: the esbuild server bundle is named as the bundle, with line and column", () => {
    const err = withStack([
      "    at ChildProcess.exithandler (node:child_process:422:12)",
      "    at syncPush (/app/dist/server/index.cjs:48211:11)",
      "    at async Promise.all (index 0)",
    ]);
    expect(firstAppFrame(err)).toBe("dist/server/index.cjs:48211:11");
  });

  test("production (bundle) shape: a Next server chunk keeps its .next prefix and the column that localises line 1", () => {
    const err = withStack(["    at a (/app/.next/server/chunks/8123.js:1:40417)", "    at b (/app/.next/server/app/api/kb/route.js:1:900)"]);
    expect(firstAppFrame(err)).toBe(".next/server/chunks/8123.js:1:40417");
  });

  test("every frame matches the credential-proof shape [\\w./-]+:line(:column)", () => {
    for (const f of [
      "    at x (/srv/app/apps/web-platform/server/a.ts:1:2)",
      "    at x (/app/dist/server/index.cjs:3:4)",
      "    at x (C:\\srv\\apps\\web-platform\\app\\page.tsx:5:6)",
    ]) {
      expect(firstAppFrame(withStack([f]))).toMatch(/^[\w./-]+:\d+:\d+$/);
    }
  });

  test("no app frame (node internals, node_modules, tests only) -> undefined", () => {
    const err = withStack(["    at a (node:internal/x:1:1)", "    at b (/srv/app/node_modules/p/server/i.js:2:2)", "    at c (/srv/ws/test/x.test.ts:3:3)"]);
    expect(firstAppFrame(err)).toBeUndefined();
  });

  test("an `at` line inside the MESSAGE never becomes the frame", () => {
    const err = withStack([], "argv\n    at forged (/srv/app/apps/web-platform/server/evil.ts:1:1)");
    expect(firstAppFrame(err)).toBeUndefined();
  });
});
