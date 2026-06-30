import { describe, it, expect, vi } from "vitest";

// #5796 — behavioral proof that the component-project setup file (setup-dom.ts)
// raises vitest's `vi.waitFor` default timeout floor from 1000ms to 10_000ms.
// This is the `.test.tsx` sibling of `vi-waitfor-floor.test.ts`: it runs under
// the happy-dom `component` project (setupFiles: test/setup-dom.ts), so it
// guards the SECOND wrapper install site. The component project holds the
// majority of `vi.waitFor` sites (live-repo-badge, org-switcher-container,
// use-active-repo-poll, …). Deleting the setup-dom wrapper turns the first
// assertion red.
describe("vi.waitFor default floor (component project / setup-dom.ts)", () => {
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
