import { describe, expect, it } from "vitest";

import { waitFailureState } from "../../scripts/live-verify/run";

// #7969. The composer wait timed out on the first triggered live-verify run in
// five releases and emitted only `Timeout 20000ms exceeded ... waiting for
// getByRole('textbox').first() to be visible`. That is consistent with three
// different causes and distinguishes none, so the issue enumerated all three
// and could close none.
//
// These cases pin the DISCRIMINATING fields. Each asserts a field that, had it
// been present in the original failure, would have eliminated at least one
// hypothesis on sight.

/** Minimal Page stand-in: only the surface waitFailureState actually touches. */
function fakePage(opts: {
  url?: string;
  textboxes?: number;
  rail?: number;
  title?: string;
  throwOn?: "url" | "count" | "title" | "rail";
}) {
  const boom = (k: string) => {
    if (opts.throwOn === k) throw new Error(`synthetic ${k} failure`);
  };
  return {
    url: () => {
      boom("url");
      return opts.url ?? "https://app.example.com/dashboard/chat/new";
    },
    title: async () => {
      boom("title");
      return opts.title ?? "Soleur";
    },
    getByRole: (_role: string) => ({
      count: async () => {
        boom("count");
        return opts.textboxes ?? 0;
      },
    }),
    locator: (_sel: string) => ({
      count: async () => {
        boom("rail");
        return opts.rail ?? 0;
      },
    }),
  } as never;
}

const nav = (status: number) => ({ status: () => status });

describe("waitFailureState (#7969)", () => {
  it("reports the path, so a bounce is distinguishable from a render failure", async () => {
    const out = await waitFailureState(
      fakePage({ url: "https://app.example.com/login?redirectTo=%2Fdashboard" }),
      nav(200),
      "composer",
    );
    expect(out).toContain("path=/login");
  });

  it("reduces the URL to a path, so a credential in the query cannot reach the log", async () => {
    const out = await waitFailureState(
      fakePage({ url: "https://app.example.com/auth/callback?code=sensitive-grant-abc123" }),
      nav(200),
      "composer",
    );
    expect(out).not.toContain("sensitive-grant-abc123");
    expect(out).not.toContain("code=");
    expect(out).toContain("path=/auth/callback");
  });

  it("reports the HTTP status, which separates a 5xx from a slow paint", async () => {
    const out = await waitFailureState(fakePage({}), nav(503), "composer");
    expect(out).toContain("http=503");
  });

  it("distinguishes 'no response object' from a real status", async () => {
    const out = await waitFailureState(fakePage({}), null, "composer");
    expect(out).toContain("http=<no-response>");
  });

  it("counts textboxes — the field that REFUTES the /login-bounce hypothesis", async () => {
    // /login renders <input type="email">, whose ARIA role IS textbox. A bounce
    // there yields a NON-ZERO count, which is why a bounce could never have
    // produced this timeout in the first place.
    const out = await waitFailureState(
      fakePage({ url: "https://app.example.com/login", textboxes: 1 }),
      nav(200),
      "composer",
    );
    expect(out).toContain("textboxes=1");
  });

  it("names which wait failed, so composer and rail are not conflated", async () => {
    const composer = await waitFailureState(fakePage({}), nav(200), "composer");
    const rail = await waitFailureState(fakePage({}), nav(200), "rail");
    expect(composer).toContain("composer-not-visible");
    expect(rail).toContain("rail-not-visible");
  });

  it("NEVER THROWS when the page itself is unusable, and says so per field", async () => {
    // It runs only on the failure path. Throwing here would replace a
    // diagnosable timeout with an undiagnosable one — the defect it removes.
    for (const k of ["url", "count", "title", "rail"] as const) {
      const out = await waitFailureState(fakePage({ throwOn: k }), nav(200), "composer");
      expect(typeof out).toBe("string");
      expect(out.length).toBeGreaterThan(0);
    }
    const urlDead = await waitFailureState(fakePage({ throwOn: "url" }), nav(200), "composer");
    expect(urlDead).toContain("path=<unreadable>");
    const countDead = await waitFailureState(fakePage({ throwOn: "count" }), nav(200), "composer");
    expect(countDead).toContain("textboxes=-1");
  });

  it("caps the title, so an arbitrarily long page cannot flood the result line", async () => {
    const out = await waitFailureState(
      fakePage({ title: "x".repeat(500) }),
      nav(200),
      "composer",
    );
    expect(out.length).toBeLessThan(300);
  });
});
