import { describe, it, expect, vi } from "vitest";

// #5796 — behavioral proof that the node-project setup file (setup-node.ts)
// raises vitest's `vi.waitFor` default timeout floor from 1000ms to 10_000ms.
// vitest's `vi.waitFor` has NO global config knob (unlike RTL's
// `configure({ asyncUtilTimeout })`, which #5113 already raised), so the only
// way to lift the default across all 18 node-project call sites
// (cc-dispatcher.test.ts, server/templates/is-template-authorized.test.ts) is
// the setup-file wrapper. Deleting that wrapper turns the first assertion red.
describe("vi.waitFor default floor (node project / setup-node.ts)", () => {
  it("default floor is >1s: a condition that settles at ~1300ms resolves (would time out at the 1000ms default)", async () => {
    let ready = false;
    const t = setTimeout(() => {
      ready = true;
    }, 1300);
    try {
      await vi.waitFor(() => {
        if (!ready) throw new Error("not ready yet");
      });
      expect(ready).toBe(true);
    } finally {
      clearTimeout(t);
    }
  });

  it("an explicit object-form { timeout } still wins over the injected default", async () => {
    await expect(
      vi.waitFor(
        () => {
          throw new Error("never settles");
        },
        { timeout: 150 },
      ),
    ).rejects.toThrow();
  });

  it("an explicit number-form timeout is honored", async () => {
    await expect(
      vi.waitFor(() => {
        throw new Error("never settles");
      }, 150),
    ).rejects.toThrow();
  });
});
