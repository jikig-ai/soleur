// exec-forward-transport.test.ts — transport tests for the pinned-TLS forward
// client and the exec-step receiver (#9137, tasks 1.1 + 1.3). Real sockets
// against synthesized TLS material (test/helpers/proxy-test-tls.ts, SAN
// IP:127.0.0.1); no fixture files (cq-test-fixtures-synthesized-only).
//
// Covers: header/marker/query/body wire fidelity, streamed pass-through
// (first chunk before upstream completes — the behavioural Guard-3 row),
// fail-closed forward errors (no CA, untrusted CA), and receiver admission
// (peer allowlist, marker requirement, emit-to-shared-server transport).

import { createServer as createHttpServer, type Server as HttpServer } from "node:http";
import { createServer as createHttpsServer, request as httpsRequest } from "node:https";
import type { AddressInfo } from "node:net";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { makeProxyTestTls, type ProxyTestTls } from "../../helpers/proxy-test-tls";

const { mockReport } = vi.hoisted(() => ({ mockReport: vi.fn() }));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReport,
  warnSilentFallback: vi.fn(),
  infoSilentFallback: vi.fn(),
}));

import {
  EXEC_FORWARD_HEADER,
  EXEC_FORWARD_PORT,
} from "@/server/inngest/exec-placement";
import {
  PlacementForwardError,
  buildForwardHeaders,
  forwardStepCall,
} from "@/server/inngest/exec-forward-client";
import { startInngestExecReceiver } from "@/server/inngest-exec-receiver";

let tls: ProxyTestTls;
beforeAll(() => {
  tls = makeProxyTestTls();
});

afterEach(() => {
  vi.clearAllMocks();
  vi.unstubAllEnvs();
});

interface SeenRequest {
  method?: string;
  url?: string;
  headers: Record<string, string | string[] | undefined>;
  body: Buffer;
}

function closeAll(...servers: (HttpServer | import("node:https").Server | null | undefined)[]): Promise<void> {
  return Promise.all(
    servers.map(
      (s) =>
        new Promise<void>((resolve) => {
          if (!s) return resolve();
          s.closeAllConnections?.();
          s.close(() => resolve());
        }),
    ),
  ).then(() => undefined);
}

describe("buildForwardHeaders", () => {
  it("strips hop-by-hop + Host, keeps end-to-end headers, adds the marker", () => {
    const req = new Request("https://app.soleur.ai/api/inngest?fnId=x", {
      method: "POST",
      headers: {
        host: "app.soleur.ai",
        connection: "keep-alive, x-mock-hop",
        "x-mock-hop": "drop-me",
        "keep-alive": "timeout=5",
        "transfer-encoding": "chunked",
        "x-inngest-signature": "t=1&s=abc",
        "x-inngest-sdk": "inngest-js v4",
        "content-type": "application/json",
        "content-length": "17",
      },
    });
    const out = buildForwardHeaders(req);
    expect(out[EXEC_FORWARD_HEADER]).toBe("1");
    expect(out["x-inngest-signature"]).toBe("t=1&s=abc");
    expect(out["x-inngest-sdk"]).toBe("inngest-js v4");
    expect(out["content-type"]).toBe("application/json");
    for (const dropped of ["host", "connection", "x-mock-hop", "keep-alive", "transfer-encoding"]) {
      expect(Object.keys(out)).not.toContain(dropped);
    }
  });
});

describe("forwardStepCall", () => {
  it("forwards method/path/query/headers/body verbatim + marker over pinned TLS", async () => {
    const seen: SeenRequest[] = [];
    const upstream = createHttpsServer({ key: tls.KEY, cert: tls.CERT }, (req, res) => {
      const chunks: Buffer[] = [];
      req.on("data", (c) => chunks.push(c));
      req.on("end", () => {
        seen.push({
          method: req.method,
          url: req.url,
          headers: req.headers,
          body: Buffer.concat(chunks),
        });
        res.writeHead(201, { "content-type": "application/json" });
        res.end('{"ok":true}');
      });
    });
    await new Promise<void>((r) => upstream.listen(0, "127.0.0.1", r));
    const port = (upstream.address() as AddressInfo).port;

    const body = '{"event":{"name":"app/test"},"ctx":{"fn_id":"x"},"steps":{}}';
    const req = new Request(
      "https://app.soleur.ai/api/inngest?fnId=soleur-runtime-agent-on-spawn-requested&stepId=s&deployId=d",
      {
        method: "POST",
        headers: {
          "x-inngest-signature": "t=1700000000&s=deadbeef",
          "x-inngest-sdk": "inngest-js v4",
          "x-request-id": "rid-1",
          "content-type": "application/json",
          "content-length": String(body.length),
        },
        body,
      },
    );
    const res = await forwardStepCall(req, {
      ca: tls.CERT,
      target: `https://127.0.0.1:${port}/api/inngest`,
    });
    expect(res.status).toBe(201);
    expect(await res.text()).toBe('{"ok":true}');

    expect(seen).toHaveLength(1);
    const got = seen[0];
    expect(got.method).toBe("POST");
    expect(got.url).toBe(
      "/api/inngest?fnId=soleur-runtime-agent-on-spawn-requested&stepId=s&deployId=d",
    );
    expect(got.body.toString()).toBe(body);
    expect(got.headers["x-inngest-signature"]).toBe("t=1700000000&s=deadbeef");
    expect(got.headers["x-request-id"]).toBe("rid-1");
    expect(got.headers[EXEC_FORWARD_HEADER]).toBe("1");
    expect(got.headers.host).toBe(`127.0.0.1:${port}`); // target's own Host
    await closeAll(upstream);
  });

  it("streams the response: the first chunk arrives before the upstream completes", async () => {
    const upstream = createHttpsServer({ key: tls.KEY, cert: tls.CERT }, (_req, res) => {
      res.writeHead(201, { "content-type": "application/json" });
      res.write("chunk-1 ");
      setTimeout(() => {
        res.write("chunk-2");
        res.end();
      }, 150);
    });
    await new Promise<void>((r) => upstream.listen(0, "127.0.0.1", r));
    const port = (upstream.address() as AddressInfo).port;

    const res = await forwardStepCall(
      new Request("https://app.soleur.ai/api/inngest?fnId=x", { method: "POST" }),
      { ca: tls.CERT, target: `https://127.0.0.1:${port}/api/inngest` },
    );
    expect(res.status).toBe(201);
    const reader = res.body!.getReader();
    const first = await reader.read(); // resolves while the upstream is still open
    expect(new TextDecoder().decode(first.value)).toContain("chunk-1");
    const rest: Uint8Array[] = [];
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      if (value) rest.push(value);
    }
    const tail = Buffer.concat(rest.map((c) => Buffer.from(c))).toString();
    expect(tail).toContain("chunk-2");
    await closeAll(upstream);
  });

  it("an untrusted CA fails closed with placement.forward_failed (never insecure)", async () => {
    const other = makeProxyTestTls();
    const upstream = createHttpsServer({ key: other.KEY, cert: other.CERT }, (_req, res) => {
      res.writeHead(200);
      res.end("ok");
    });
    await new Promise<void>((r) => upstream.listen(0, "127.0.0.1", r));
    const port = (upstream.address() as AddressInfo).port;
    await expect(
      forwardStepCall(
        new Request("https://app.soleur.ai/api/inngest?fnId=x", { method: "POST" }),
        { ca: tls.CERT, target: `https://127.0.0.1:${port}/api/inngest` },
      ),
    ).rejects.toBeInstanceOf(PlacementForwardError);
    await closeAll(upstream);
    other.cleanup();
  });

  it("no pinned CA → placement.forward_failed before any dial", async () => {
    vi.stubEnv("PROXY_TLS_CERT", "");
    await expect(
      forwardStepCall(
        new Request("https://app.soleur.ai/api/inngest?fnId=x", { method: "POST" }),
        { target: "https://127.0.0.1:1/api/inngest" },
      ),
    ).rejects.toBeInstanceOf(PlacementForwardError);
  });

  it("exec host unreachable → placement.forward_failed (fail-closed, never local)", async () => {
    await expect(
      forwardStepCall(
        new Request("https://app.soleur.ai/api/inngest?fnId=x", { method: "POST" }),
        {
          ca: tls.CERT,
          target: "https://127.0.0.1:1/api/inngest",
          connectTimeoutMs: 2000,
        },
      ),
    ).rejects.toBeInstanceOf(PlacementForwardError);
  });
});

describe("startInngestExecReceiver", () => {
  it("inert without TLS material → null, no throw", () => {
    vi.stubEnv("PROXY_TLS_KEY", "");
    vi.stubEnv("PROXY_TLS_CERT", "");
    expect(startInngestExecReceiver({ httpServer: createHttpServer() })).toBeNull();
  });

  it("inert without a bind → null + Sentry report", () => {
    vi.stubEnv("PROXY_TLS_KEY", tls.KEY);
    vi.stubEnv("PROXY_TLS_CERT", tls.CERT);
    vi.stubEnv("SOLEUR_PROXY_BIND", "");
    expect(startInngestExecReceiver({ httpServer: createHttpServer() })).toBeNull();
    expect(mockReport).toHaveBeenCalledWith(
      expect.any(Error),
      expect.objectContaining({ feature: "inngest-exec-placement" }),
    );
  });

  it("inert without a peer allowlist → null + Sentry report", () => {
    vi.stubEnv("PROXY_TLS_KEY", tls.KEY);
    vi.stubEnv("PROXY_TLS_CERT", tls.CERT);
    vi.stubEnv("SOLEUR_PROXY_BIND", "127.0.0.1");
    vi.stubEnv("SOLEUR_PROXY_PEER_ALLOWLIST", "");
    expect(startInngestExecReceiver({ httpServer: createHttpServer() })).toBeNull();
    expect(mockReport).toHaveBeenCalled();
  });

  it("emits a marked POST /api/inngest onto the shared server — marker preserved, response streamed back", async () => {
    vi.stubEnv("PROXY_TLS_KEY", tls.KEY);
    vi.stubEnv("PROXY_TLS_CERT", tls.CERT);
    vi.stubEnv("SOLEUR_PROXY_BIND", "127.0.0.1");
    vi.stubEnv("SOLEUR_PROXY_PEER_ALLOWLIST", "127.0.0.1");

    const appSeen: SeenRequest[] = [];
    const app = createHttpServer((req, res) => {
      const chunks: Buffer[] = [];
      req.on("data", (c) => chunks.push(c));
      req.on("end", () => {
        appSeen.push({
          method: req.method,
          url: req.url,
          headers: req.headers,
          body: Buffer.concat(chunks),
        });
        res.writeHead(201, { "content-type": "application/json" });
        res.write("part-a ");
        setTimeout(() => res.end("part-b"), 60);
      });
    });
    await new Promise<void>((r) => app.listen(0, "127.0.0.1", r));

    const receiver = startInngestExecReceiver({
      httpServer: app,
      port: 0,
      privateBindPrefix: "127.0.0.",
    });
    expect(receiver).not.toBeNull();
    await new Promise<void>((r) => receiver!.once("listening", r));
    const port = (receiver!.address() as AddressInfo).port;

    const body = "step-payload-bytes";
    const response = await new Promise<{ status: number; text: string }>((resolve, reject) => {
      const r = httpsRequest(
        `https://127.0.0.1:${port}/api/inngest?fnId=soleur-runtime-agent-on-spawn-requested`,
        {
          method: "POST",
          ca: tls.CERT,
          rejectUnauthorized: true,
          headers: {
            [EXEC_FORWARD_HEADER]: "1",
            "x-inngest-signature": "t=1&s=f",
            "content-type": "application/json",
            "content-length": String(body.length),
          },
        },
        (res) => {
          const chunks: Buffer[] = [];
          res.on("data", (c) => chunks.push(c));
          res.on("end", () =>
            resolve({ status: res.statusCode ?? 0, text: Buffer.concat(chunks).toString() }),
          );
        },
      );
      r.on("error", reject);
      r.end(body);
    });

    expect(response.status).toBe(201);
    expect(response.text).toBe("part-a part-b");
    expect(appSeen).toHaveLength(1);
    expect(appSeen[0].method).toBe("POST");
    expect(appSeen[0].url).toBe(
      "/api/inngest?fnId=soleur-runtime-agent-on-spawn-requested",
    );
    expect(appSeen[0].headers[EXEC_FORWARD_HEADER]).toBe("1");
    expect(appSeen[0].headers["x-inngest-signature"]).toBe("t=1&s=f");
    expect(appSeen[0].body.toString()).toBe(body);
    await closeAll(receiver, app);
  });

  it("unmarked or non-/api/inngest requests get a flat 404 — the transport only serves forwarded calls", async () => {
    vi.stubEnv("PROXY_TLS_KEY", tls.KEY);
    vi.stubEnv("PROXY_TLS_CERT", tls.CERT);
    vi.stubEnv("SOLEUR_PROXY_BIND", "127.0.0.1");
    vi.stubEnv("SOLEUR_PROXY_PEER_ALLOWLIST", "127.0.0.1");
    const app = createHttpServer((_req, res) => res.end("app"));
    await new Promise<void>((r) => app.listen(0, "127.0.0.1", r));
    const receiver = startInngestExecReceiver({
      httpServer: app,
      port: 0,
      privateBindPrefix: "127.0.0.",
    });
    await new Promise<void>((r) => receiver!.once("listening", r));
    const port = (receiver!.address() as AddressInfo).port;

    const get404 = (path: string, marked: boolean) =>
      new Promise<number>((resolve, reject) => {
        const r = httpsRequest(
          `https://127.0.0.1:${port}${path}`,
          {
            method: "POST",
            ca: tls.CERT,
            rejectUnauthorized: true,
            headers: marked ? { [EXEC_FORWARD_HEADER]: "1" } : {},
          },
          (res) => {
            res.resume();
            res.on("end", () => resolve(res.statusCode ?? 0));
          },
        );
        r.on("error", reject);
        r.end("x");
      });

    expect(await get404("/api/inngest?fnId=x", false)).toBe(404); // unmarked
    expect(await get404("/health", true)).toBe(404); // marked but wrong path
    await closeAll(receiver, app);
  });

  it("a non-allowlisted peer is destroyed before TLS — no request reaches the app", async () => {
    vi.stubEnv("PROXY_TLS_KEY", tls.KEY);
    vi.stubEnv("PROXY_TLS_CERT", tls.CERT);
    vi.stubEnv("SOLEUR_PROXY_BIND", "127.0.0.1");
    vi.stubEnv("SOLEUR_PROXY_PEER_ALLOWLIST", "10.0.1.99");
    const app = createHttpServer((_req, res) => res.end("app"));
    await new Promise<void>((r) => app.listen(0, "127.0.0.1", r));
    const receiver = startInngestExecReceiver({
      httpServer: app,
      port: 0,
      privateBindPrefix: "127.0.0.",
    });
    await new Promise<void>((r) => receiver!.once("listening", r));
    const port = (receiver!.address() as AddressInfo).port;

    await expect(
      new Promise((resolve, reject) => {
        const r = httpsRequest(
          `https://127.0.0.1:${port}/api/inngest`,
          { method: "POST", ca: tls.CERT, rejectUnauthorized: true, headers: { [EXEC_FORWARD_HEADER]: "1" } },
          (res) => {
            res.resume();
            res.on("end", resolve);
          },
        );
        r.on("error", reject);
        r.end("x");
      }),
    ).rejects.toThrow();
    await closeAll(receiver, app);
  });

  it("receiver default port constant is 8445 (not the deliberately-wrong 8444 fixture port)", () => {
    expect(EXEC_FORWARD_PORT).toBe(8445);
  });
});
