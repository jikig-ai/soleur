import { describe, expect, it } from "vitest";

import {
  COMPOSER_ROLE,
  awaitVisibleOrDiagnose,
  emitLine,
  waitFailureState,
} from "../../scripts/live-verify/run";

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
  visible?: boolean;
  throwOn?: "url" | "count" | "title" | "rail" | "visible";
  hangOn?: "count" | "title" | "visible";
  seen?: { roles: string[]; selectors: string[] };
}) {
  const seen = opts.seen ?? { roles: [], selectors: [] };
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
      if (opts.hangOn === "title") return new Promise<string>(() => {});
      return opts.title ?? "Soleur";
    },
    getByRole: (role: string) => ({
      __role: (seen.roles.push(role), role),
      count: async () => {
        boom("count");
        // `hangOn` models a WEDGED RENDERER — the shape the never-hangs bound
        // exists for. A rejection-only fake pins the wrong half of the contract.
        if (opts.hangOn === "count") return new Promise<number>(() => {});
        return opts.textboxes ?? 0;
      },
      first: () => ({
        isVisible: async () => {
          boom("visible");
          if (opts.hangOn === "visible") return new Promise<boolean>(() => {});
          return opts.visible ?? false;
        },
      }),
    }),
    locator: (sel: string) => ({
      __sel: (seen.selectors.push(sel), sel),
      count: async () => {
        boom("rail");
        return opts.rail ?? 0;
      },
    }),
  } as unknown as Parameters<typeof waitFailureState>[0];
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
    // /auth/callback is not a path this harness should be on, so the allowlist
    // reduces it too — a strictly stronger guarantee than the path cut alone.
    expect(out).toContain("<unexpected:/auth>");
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

describe("awaitVisibleOrDiagnose — the WIRE, not the endpoints (#8092 review)", () => {
  // Why this block exists: waitFailureState was unit-tested in isolation and the
  // two call sites were inline try/catch, so REVERTING the PR's central change —
  // putting back a bare `await input.waitFor(...)` — left the whole suite GREEN
  // at 66/66. Both endpoints were pinned and the wire between them was not.
  it("returns null when the wait resolves, so the caller proceeds", async () => {
    const out = await awaitVisibleOrDiagnose(
      async () => undefined,
      fakePage({}),
      nav(200),
      "composer",
    );
    expect(out).toBeNull();
  });

  it("returns a CANT-RUN carrying the page state when the wait rejects", async () => {
    const out = await awaitVisibleOrDiagnose(
      async () => {
        throw new Error("Timeout 20000ms exceeded.");
      },
      fakePage({ url: "https://app.example.com/login", textboxes: 1 }),
      nav(200),
      "composer",
    );
    expect(out).not.toBeNull();
    expect(out!.kind).toBe("CANT-RUN");
    expect((out as { reason: string }).reason).toContain("composer-not-visible");
    expect((out as { reason: string }).reason).toContain("textboxes=1");
  });

  it("does not swallow the failure into a success", async () => {
    // The scope claim in PR #8092 is that nothing here can turn a real failure
    // green. A rejecting wait must never yield null.
    const out = await awaitVisibleOrDiagnose(
      async () => {
        throw new Error("boom");
      },
      fakePage({}),
      null,
      "rail",
    );
    expect(out).not.toBeNull();
  });
});

describe("emitted-line safety (#8092 review)", () => {
  it("reduces an unexpected path to its first segment, never a token", async () => {
    // /shared/<token>, /invite/<token> and /api/account/export/<jobId> all put a
    // credential in a PATH segment, which no redact.ts rule matches.
    const out = await waitFailureState(
      fakePage({ url: "https://app.example.com/shared/live-share-token-abc123" }),
      nav(200),
      "composer",
    );
    expect(out).not.toContain("live-share-token-abc123");
    expect(out).toContain("<unexpected:/shared>");
  });

  it("keeps the paths the harness legitimately visits", async () => {
    for (const p of ["/dashboard/chat/new", "/login", "/accept-terms"]) {
      const out = await waitFailureState(
        fakePage({ url: `https://app.example.com${p}` }),
        nav(200),
        "composer",
      );
      expect(out).toContain(`path=${p}`);
    }
  });

  it("strips U+2028/U+2029/DEL from the title so a crafted page cannot forge a verdict", async () => {
    // JSON.stringify escapes only C0, '"' and '\\' — these pass through raw and
    // render as a line break in a JSON log viewer.
    const out = await waitFailureState(
      fakePage({ title: "ok\u2028RESULT: PASS\u2029x\u007fy" }),
      nav(200),
      "composer",
    );
    expect(out).not.toContain("\u2028");
    expect(out).not.toContain("\u2029");
    expect(out).not.toContain("\u007f");
    expect(out).toContain("RESULT: PASS");
  });

  it("degrades the title to a sentinel, not to an empty string", async () => {
    // title="" is indistinguishable from a page that genuinely has none — which
    // is exactly the shell-never-hydrated case this diagnostic exists to detect.
    const out = await waitFailureState(fakePage({ throwOn: "title" }), nav(200), "composer");
    expect(out).toContain('title="<unreadable>"');
  });
});

describe("never HANGS, not merely never throws (#8092 review)", () => {
  // page.title() and Locator.count() accept no timeout and evaluate in the
  // RENDERER. Unbounded, a wedged renderer — one of #7969's own hypotheses —
  // would blow the job's timeout-minutes, emit NO RESULT line at all, and the
  // workflow escalates that absence to BLOCK=1: a blocking release failure
  // carrying LESS information than the timeout it replaced.
  it.each(["count", "title", "visible"] as const)(
    "returns a usable line when page.%s hangs forever",
    async (field) => {
      const started = Date.now();
      const out = await waitFailureState(fakePage({ hangOn: field }), nav(200), "composer");
      expect(typeof out).toBe("string");
      expect(out).toContain("composer-not-visible");
      // Well inside the job budget; the point is that it RETURNS at all.
      expect(Date.now() - started).toBeLessThan(15_000);
    },
    20_000,
  );

  it("reports visibility at report time, separating drift from a late paint", async () => {
    const hidden = await waitFailureState(
      fakePage({ textboxes: 1, visible: false }),
      nav(200),
      "composer",
    );
    expect(hidden).toContain("textboxes=1");
    expect(hidden).toContain("visible=false");
    const late = await waitFailureState(
      fakePage({ textboxes: 1, visible: true }),
      nav(200),
      "composer",
    );
    expect(late).toContain("visible=true");
  });

  it("carries the error NAME, which separates a timeout from a closed target", async () => {
    const e = new Error("Target page, context or browser has been closed");
    e.name = "TargetClosedError";
    const out = await awaitVisibleOrDiagnose(
      async () => {
        throw e;
      },
      fakePage({}),
      nav(200),
      "composer",
    );
    expect((out as { reason: string }).reason).toContain("err=TargetClosedError");
  });
});

describe("field PRESENCE and sentinels, not just shape (#8092 review)", () => {
  // Every earlier assertion read a field's VALUE, so deleting the field outright
  // was invisible: dropping `title=` and `rail=` from the template each left the
  // suite green. Pin that each field is emitted at all.
  it("emits every field the report is built from", async () => {
    const out = await waitFailureState(fakePage({}), nav(200), "composer");
    for (const key of [
      "path=",
      "http=",
      "nav=",
      "err=",
      "textboxes=",
      "visible=",
      "rail=",
      "title=",
    ]) {
      expect(out).toContain(key);
    }
  });

  it("keeps rail's could-not-read sentinel distinct from a real zero", async () => {
    // rail=0 means "the rail is absent"; rail=-1 means "we could not read it".
    // Collapsing them re-merges the conflation this PR exists to remove.
    const out = await waitFailureState(fakePage({ throwOn: "rail" }), nav(200), "composer");
    expect(out).toContain("rail=-1");
  });

  it("keeps status's sentinel when the response handle is dead", async () => {
    const dead = { status: () => { throw new Error("Target page … has been closed"); } };
    const out = await waitFailureState(fakePage({}), dead, "composer");
    expect(out).toContain("http=<unreadable>");
  });

  it("bounds the line near its real length, not 2x over", async () => {
    const out = await waitFailureState(fakePage({ title: "x".repeat(500) }), nav(200), "composer");
    expect(out.length).toBeLessThan(220);
  });

  it("asks the page for the SAME role the wait waited on", async () => {
    // The wait and the diagnostic previously re-derived "textbox" independently;
    // a change at the call site would have left the diagnostic counting the
    // wrong thing and reporting the opposite of the truth.
    const seen = { roles: [] as string[], selectors: [] as string[] };
    await waitFailureState(fakePage({ seen }), nav(200), "composer");
    expect(seen.roles.length).toBeGreaterThan(0);
    for (const r of seen.roles) expect(r).toBe(COMPOSER_ROLE);
  });
});

describe("emit() composition — the redaction is load-bearing (#8092 review)", () => {
  // The redact() on the CANT-RUN branch is a SECURITY property (live page state
  // reaching a public CI log) and reverting it left the whole suite green.
  it("redacts a secret-shaped token in a CANT-RUN reason", () => {
    const jwt = "eyJ" + "hbGciOi" + ".eyJzdWIiOiJ4" + ".s1Gn4tur3_AbC-dEf";
    const line = emitLine({ kind: "CANT-RUN", reason: `composer-not-visible title="${jwt}"` });
    expect(line).not.toContain(jwt);
    expect(line).toContain("RESULT: CANT-RUN:");
  });

  it("redacts an email in a CANT-RUN reason", () => {
    const line = emitLine({ kind: "CANT-RUN", reason: 'title="ops@example.com"' });
    expect(line).not.toContain("ops@example.com");
  });
});
