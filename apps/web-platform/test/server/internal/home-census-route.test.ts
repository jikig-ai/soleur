// Guard 3 of the production-HOME census (Ref #10455): no real scan unless every condition holds.
// The handler is driven with injected deps (clock, uptime, fs, caps); the route file is checked for wiring.
// All fixtures are synthesized; nothing here scans a real HOME.
import { readFileSync, mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterAll, afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import * as Sentry from "@sentry/nextjs";

import { handleHomeCensus, scanHome, SUNSET_UTC, type CensusDeps, type CensusFs, type ScanFn } from "@/server/home-census";

const SECRET = "home-census-route-test-secret";
const SHA = "c".repeat(40);
const ORIG_SECRET = process.env.INNGEST_MANUAL_TRIGGER_SECRET;

function fsOf(n: Record<string, "dir" | "file">): CensusFs {
  const kids = (dir: string) => Object.keys(n).filter((p) => p.startsWith(dir + "/") && !p.slice(dir.length + 1).includes("/")).map((p) => p.slice(dir.length + 1));
  return {
    async lstat(p) {
      if (!n[p]) throw Object.assign(new Error("ENOENT"), { code: "ENOENT" });
      return { mode: n[p] === "dir" ? 0o700 : 0o600, dev: 1, ino: Object.keys(n).indexOf(p) + 1, isDirectory: () => n[p] === "dir", isSymbolicLink: () => false };
    },
    async opendir(p) {
      if (n[p] !== "dir") throw Object.assign(new Error("ENOENT"), { code: "ENOENT" });
      const names = kids(p);
      let i = 0;
      return { read: async () => (i < names.length ? { name: names[i++] } : null), close: async () => {} };
    },
  };
}

function makeDeps(over: Partial<CensusDeps> = {}): { deps: CensusDeps; lines: string[] } {
  const lines: string[] = [];
  const dir = mkdtempSync(join(tmpdir(), "home-census-route-"));
  mkdirSync(join(dir, "known"));
  writeFileSync(join(dir, "known", "x"), "x");
  return {
    lines,
    deps: {
      fs: fsOf({ "/home": "dir", "/home/soleur": "dir", "/home/soleur/.claude": "dir", "/home/soleur/.claude/debug": "dir", "/home/soleur/.claude/debug/a": "file" }),
      env: { HOME: "/home/soleur", BUILD_SHA: SHA },
      homedir: () => "/home/soleur",
      now: () => Date.parse("2026-11-05T00:00:00Z"),
      uptime: () => 90_000,
      yieldFn: async () => {},
      loadShed: () => false,
      canaryDir: join(dir, "known"),
      logDest: { write: (s: string) => void lines.push(s) },
      ...over,
    },
  };
}

function req(body: unknown, auth: string | null = `Bearer ${SECRET}`): Request {
  const headers = new Headers({ "content-type": "application/json" });
  if (auth !== null) headers.set("authorization", auth);
  return new Request("https://app.soleur.ai/api/internal/home-census", { method: "POST", headers, body: typeof body === "string" ? body : JSON.stringify(body) });
}
const real = (extra: Record<string, unknown> = {}) => ({ run_id: 1, mode: "real", expect_build_sha: SHA, ...extra });

function resetState() {
  const g = globalThis as Record<symbol, unknown>;
  for (const k of ["inflight", "limiter", "dryRunSentry"]) delete g[Symbol.for(`soleur.homeCensus.${k}`)];
}

beforeEach(() => {
  process.env.INNGEST_MANUAL_TRIGGER_SECRET = SECRET;
  resetState();
});
afterEach(async () => {
  if (ORIG_SECRET === undefined) delete process.env.INNGEST_MANUAL_TRIGGER_SECRET;
  else process.env.INNGEST_MANUAL_TRIGGER_SECRET = ORIG_SECRET;
});
afterAll(async () => {
  await Sentry.close(1000).catch(() => {});
});

const j = async (r: Response) => JSON.parse(await r.text());

describe("authentication", () => {
  it("absent and wrong bearer answer with identical status, headers and body bytes", async () => {
    const { deps } = makeDeps();
    const a = await handleHomeCensus(req({ run_id: 1 }, null), deps);
    const b = await handleHomeCensus(req({ run_id: 1 }, "Bearer wrong-secret"), deps);
    expect(a.status).toBe(401);
    expect(b.status).toBe(401);
    expect(await a.text()).toBe(await b.text());
    expect([...a.headers.entries()]).toEqual([...b.headers.entries()]);
  });
  it("authenticates before it reads the body", async () => {
    const { deps } = makeDeps();
    const res = await handleHomeCensus(req("{not json", "Bearer wrong"), deps);
    expect(res.status).toBe(401);
  });
  it("a missing secret answers 503", async () => {
    delete process.env.INNGEST_MANUAL_TRIGGER_SECRET;
    const { deps } = makeDeps();
    expect((await handleHomeCensus(req({ run_id: 1 }), deps)).status).toBe(503);
  });
});

describe("request contract", () => {
  it("rejects bad bodies without echoing them", async () => {
    const cases: Array<[string, unknown, number]> = [
      ["invalid json", "{nope", 400],
      ["array", [], 400],
      ["run_id zero", { run_id: 0 }, 400],
      ["run_id too large", { run_id: 1e9 + 1 }, 400],
      ["run_id float", { run_id: 1.5 }, 400],
      ["run_id string", { run_id: "7" }, 400],
      ["unknown key", { run_id: 1, extra: "/home/canary" }, 400],
      ["bad mode", { run_id: 1, mode: "banana" }, 400],
      ["bad sha shape", { run_id: 1, mode: "real", expect_build_sha: "not-a-sha-/home/canary" }, 400],
      ["bad accept_young", { run_id: 1, mode: "real", expect_build_sha: SHA, accept_young: "yes" }, 400],
    ];
    for (const [name, body, status] of cases) {
      const { deps } = makeDeps();
      const res = await handleHomeCensus(req(body), deps);
      const text = await res.text();
      expect(res.status, name).toBe(status);
      expect(text, name).not.toContain("canary");
    }
  });
  it("an over-large Content-Length is refused with 413 before the body is read", async () => {
    const { deps } = makeDeps();
    const r = new Request("https://app.soleur.ai/api/internal/home-census", {
      method: "POST",
      headers: new Headers({ "content-type": "application/json", authorization: `Bearer ${SECRET}`, "content-length": String(70 * 1024) }),
      body: JSON.stringify({ run_id: 1 }),
    });
    expect((await handleHomeCensus(r, deps)).status).toBe(413);
  });
  it("a body over 64 KB is refused with 413", async () => {
    const { deps } = makeDeps();
    const res = await handleHomeCensus(req(JSON.stringify({ run_id: 1, pad: "x".repeat(70 * 1024) })), deps);
    expect(res.status).toBe(413);
  });
  it("mode defaults to dry_run: synthetic source, nothing consumed, real uptime/build/sunset", async () => {
    const { deps } = makeDeps();
    const res = await handleHomeCensus(req({ run_id: 5 }), deps);
    const body = await j(res);
    expect(res.status).toBe(200);
    expect(body.mode).toBe("dry_run");
    expect(body.data_source).toBe("synthetic");
    expect(body.uptime_bucket).toBe("lt_7d");
    expect(body.build_sha).toBe(SHA);
    expect(body.sunset_utc).toBe(SUNSET_UTC);
    // a dry_run consumed neither the in-flight flag nor a limiter slot: two real runs still fit afterwards
    const r1 = await handleHomeCensus(req(real()), deps);
    expect(r1.status).toBe(200);
  });
  it("every response is no-store and carries no Access-Control header", async () => {
    const { deps } = makeDeps();
    for (const r of [await handleHomeCensus(req({ run_id: 1 }), deps), await handleHomeCensus(req({ run_id: 1 }, "Bearer x"), deps), await handleHomeCensus(req("{"), deps)]) {
      expect(r.headers.get("cache-control")).toBe("no-store");
      expect([...r.headers.keys()].filter((k) => k.toLowerCase().startsWith("access-control"))).toEqual([]);
    }
  });
});

describe("gate order and state", () => {
  it("410 after the sunset constant", async () => {
    const { deps } = makeDeps({ now: () => Date.parse(SUNSET_UTC) });
    expect((await handleHomeCensus(req(real()), deps)).status).toBe(410);
  });
  it("the sunset constant is the reviewed literal (it must be at most merge date + 30 days when marked ready)", () => {
    expect(SUNSET_UTC).toBe("2026-11-30T00:00:00Z");
  });
  it("build mismatch answers 409 with a constant body that never echoes the supplied sha", async () => {
    const { deps } = makeDeps();
    const other = "d".repeat(40);
    const res = await handleHomeCensus(req(real({ expect_build_sha: other })), deps);
    const text = await res.text();
    expect(res.status).toBe(409);
    expect(text).not.toContain(other);
    expect(JSON.parse(text).error_class).toBe("build_mismatch");
  });
  it("a server without a baked build sha ('dev') refuses real", async () => {
    const { deps } = makeDeps({ env: { HOME: "/home/soleur" } });
    expect((await handleHomeCensus(req(real()), deps)).status).toBe(409);
  });
  it("the young gate refuses real without accept_young before any claim and consumes nothing", async () => {
    const { deps } = makeDeps({ uptime: () => 100 });
    for (let i = 0; i < 5; i++) expect((await handleHomeCensus(req(real()), deps)).status).toBe(409);
    expect((await handleHomeCensus(req(real({ accept_young: true })), deps)).status).toBe(200);
    expect((await handleHomeCensus(req(real({ accept_young: true, run_id: 2 })), { ...deps, now: () => deps.now() + 3_600_001 })).status).toBe(200);
  });
  it("limiter: a second real scan inside 3600 s and a third in one process are refused with no remaining-time field", async () => {
    const { deps } = makeDeps();
    const t0 = deps.now();
    expect((await handleHomeCensus(req(real()), deps)).status).toBe(200);
    const again = await handleHomeCensus(req(real({ run_id: 2 })), { ...deps, now: () => t0 + 3_599_000 });
    expect(again.status).toBe(429);
    const body = await j(again);
    expect(body.error_class).toBe("rate_limited");
    expect(Object.keys(body).sort()).toEqual(["error_class", "interpretation", "ok", "schema_version"]);
    expect((await handleHomeCensus(req(real({ run_id: 2 })), { ...deps, now: () => t0 + 3_600_001 })).status).toBe(200);
    expect((await handleHomeCensus(req(real({ run_id: 3 })), { ...deps, now: () => t0 + 10_000_000 })).status).toBe(429);
  });
  it("503 control_failed when the known-answer control or the canary fails, and no limiter slot is consumed", async () => {
    const empty = mkdtempSync(join(tmpdir(), "home-census-empty-"));
    const { deps } = makeDeps({ canaryDir: empty });
    const res = await handleHomeCensus(req(real()), deps);
    expect(res.status).toBe(503);
    expect((await j(res)).error_class).toBe("control_failed");
    const ok = makeDeps();
    expect((await handleHomeCensus(req(real()), ok.deps)).status).toBe(200);
    expect((await handleHomeCensus(req(real({ run_id: 2 })), { ...ok.deps, now: () => ok.deps.now() + 3_600_001 })).status).toBe(200);
  });
  it("a scan that throws answers 500 with a constant body and releases the flag", async () => {
    const boom: ScanFn = async () => {
      throw new Error("boom /home/canary/secret");
    };
    const { deps } = makeDeps({ scan: boom });
    const res = await handleHomeCensus(req(real()), deps);
    const text = await res.text();
    expect(res.status).toBe(500);
    expect(text).not.toContain("canary");
    expect(Object.keys(JSON.parse(text)).sort()).toEqual(["error_class", "interpretation", "ok", "schema_version"]);
    expect(((globalThis as Record<symbol, unknown>)[Symbol.for("soleur.homeCensus.inflight")] ?? false)).toBe(false);
  });
});

describe("abandoned filesystem ops", () => {
  it("the in-flight flag is held until an fs op abandoned by the time cap has settled (handler level)", async () => {
    let rejectOrphan: (e: Error) => void = () => {};
    const stalled: CensusFs = {
      lstat: () => new Promise((_, rej) => (rejectOrphan = rej)),
      opendir: async () => {
        throw new Error("unused");
      },
    };
    const { deps } = makeDeps({ fs: stalled, timeCapMs: 50 });
    const first = await handleHomeCensus(req(real()), deps);
    expect(first.status).toBe(200);
    expect((await j(first)).truncation_reason).toBe("time_cap");
    const later = { ...deps, now: () => deps.now() + 3_600_001 };
    const second = await handleHomeCensus(req(real({ run_id: 2 })), later);
    expect(second.status).toBe(409);
    expect((await j(second)).error_class).toBe("busy");
    rejectOrphan(Object.assign(new Error("EIO lstat '/home/canary/secret'"), { code: "EIO" }));
    await new Promise((r) => setTimeout(r, 30));
    const third = await handleHomeCensus(req(real({ run_id: 3 })), { ...later, fs: makeDeps().deps.fs, timeCapMs: undefined });
    expect(third.status).toBe(200);
  });
});

describe("concurrency: observed INSIDE the window", () => {
  function blockingScan() {
    let n = 0;
    let release: () => void = () => {};
    const gate = new Promise<void>((r) => (release = r));
    let entered: () => void = () => {};
    const inScan = new Promise<void>((r) => (entered = r));
    const scan: ScanFn = async (o) => {
      if (++n === 1) return scanHome(o); // control
      if (n === 2) {
        entered();
        await gate; // the real scan blocks here
      }
      return scanHome(o);
    };
    return { scan, release: () => release(), inScan };
  }

  it("a second real request is refused 409 while the first is mid-scan; a dry_run still passes; the flag clears afterwards", async () => {
    const b = blockingScan();
    const { deps } = makeDeps({ scan: b.scan });
    const first = handleHomeCensus(req(real()), deps);
    await b.inScan;
    const second = await handleHomeCensus(req(real({ run_id: 2 })), { ...deps, scan: undefined, now: () => deps.now() + 3_600_001 });
    expect(second.status).toBe(409);
    expect((await j(second)).error_class).toBe("busy");
    expect((await handleHomeCensus(req({ run_id: 3 }), { ...deps, scan: undefined })).status).toBe(200);
    b.release();
    expect((await first).status).toBe(200);
    await new Promise((r) => setImmediate(r));
    expect((await handleHomeCensus(req(real({ run_id: 2 })), { ...deps, scan: undefined, now: () => deps.now() + 3_600_001 })).status).toBe(200);
  });

  it("the in-flight flag and the limiter survive vi.resetModules() followed by a DYNAMIC import", async () => {
    const b = blockingScan();
    const { deps } = makeDeps({ scan: b.scan });
    const first = handleHomeCensus(req(real()), deps);
    await b.inScan;
    vi.resetModules();
    const fresh = await import("@/server/home-census");
    expect(fresh.handleHomeCensus).not.toBe(handleHomeCensus); // a genuinely new module instance
    const second = await fresh.handleHomeCensus(req(real({ run_id: 2 })), { ...deps, scan: undefined });
    expect(second.status).toBe(409);
    b.release();
    await first;
    await new Promise((r) => setImmediate(r));
    const third = await fresh.handleHomeCensus(req(real({ run_id: 3 })), { ...deps, scan: undefined, now: () => deps.now() + 1000 });
    expect(third.status).toBe(429); // the limiter slot from the first run was seen by the new instance
  });
});

describe("Sentry visibility of refusals", () => {
  type Env = [Record<string, unknown>, Array<[{ type: string }, Record<string, any>]>];
  let sink: Env[] = [];
  let ready = false;
  // Initialized once: a re-init after Sentry.close() in one worker captures nothing, which would make the
  // "emits nothing" assertions vacuous.
  async function captured(fn: () => Promise<void>): Promise<Array<Record<string, any>>> {
    if (!ready) {
      ready = true;
      Sentry.init({
        dsn: "https://public@o0.ingest.sentry.io/0",
        tracesSampleRate: 0,
        transport: () => ({ send: async (e: unknown) => (sink.push(e as Env), { statusCode: 200 }), flush: async () => true }),
      });
    }
    sink = [];
    await fn();
    await Sentry.flush(2000);
    return sink.flatMap(([, items]) => items.filter(([h]) => h.type === "event").map(([, p]) => p));
  }
  it("the capture harness sees an event at all (positive control for the emptiness assertions)", async () => {
    const events = await captured(async () => {
      Sentry.captureMessage("control", "info");
    });
    expect(events).toHaveLength(1);
  });
  it("a refused authenticated real attempt emits one constant-message warning with enum tags only", async () => {
    const { deps } = makeDeps();
    const events = await captured(async () => {
      await handleHomeCensus(req(real({ expect_build_sha: "e".repeat(40) })), deps);
    });
    expect(events).toHaveLength(1);
    expect(events[0].message).toBe("home-census refused");
    expect(events[0].level).toBe("warning");
    expect(events[0].tags).toEqual({ error_class: "build_mismatch", mode: "real" });
  });
  it("an unauthenticated attempt emits nothing", async () => {
    const { deps } = makeDeps();
    const events = await captured(async () => {
      await handleHomeCensus(req(real(), "Bearer wrong"), deps);
    });
    expect(events).toHaveLength(0);
  });
  it("dry_run Sentry events are limited to one per ten minutes per process", async () => {
    const { deps } = makeDeps();
    let t = Date.parse("2026-11-05T00:00:00Z");
    const events = await captured(async () => {
      for (let i = 0; i < 3; i++) await handleHomeCensus(req({ run_id: 1 }), { ...deps, now: () => t });
      t += 600_001;
      await handleHomeCensus(req({ run_id: 1 }), { ...deps, now: () => t });
    });
    expect(events).toHaveLength(2);
    for (const e of events) expect(e.tags.mode).toBe("dry_run");
  });
});

describe("route wiring", () => {
  const src = readFileSync(resolve(__dirname, "../../../app/api/internal/home-census/route.ts"), "utf8");
  const code = src.replace(/\/\/.*$/gm, "");
  it("exports only POST", () => {
    const exports = [...code.matchAll(/^export\s+(?:async\s+)?(?:function|const|let|class)\s+(\w+)/gm)].map((m) => m[1]);
    expect(exports).toEqual(["POST"]);
  });
  it("delegates to handleHomeCensus and reads no cookie or query string", () => {
    expect(code).toMatch(/handleHomeCensus\(request\)/);
    expect(code).not.toMatch(/cookies\(|searchParams|nextUrl|new URL\(/);
  });
  it("is registered as an exact public path and nothing broader", () => {
    const routes = readFileSync(resolve(__dirname, "../../../lib/routes.ts"), "utf8");
    const entries = [...routes.matchAll(/^\s+"(\/api\/internal[^"]*)",/gm)].map((m) => m[1]);
    expect(entries).toContain("/api/internal/home-census");
    expect(entries).not.toContain("/api/internal");
    expect(entries).not.toContain("/api/internal/");
  });
});
