// exec-placement-forward.test.ts — the Guard Contract suite for the #9137
// placement-aware step-call execution (plan "Guard Contract", tasks 2.1):
// Guards 1–4 with EVERY mutation-matrix row. Complements — does not duplicate —
// exec-placement-decision.test.ts (pure-function unit rows) and
// exec-forward-transport.test.ts (transport seams): this file binds the
// CONTRACT itself —
//
//   Guard 1  the route's served set resolves through the REAL classifier —
//            EXECUTION_PLACEMENT by module identity, never a shape-equal copy;
//   Guard 2  the fail-closed direction — every decidePlacement branch, plus the
//            route-level probe that REDs if POST is unwrapped (own dispatch);
//   Guard 3  wire fidelity end-to-end through the REAL receiver
//            (startInngestExecReceiver + a fixture app server over synthesized
//            TLS, helpers/proxy-test-tls.ts);
//   Guard 4  the 10.0.1.10 pin is one source of truth across exec-placement.ts,
//            infra/inngest-host.tf sdk_url, infra/variables.tf web-1, the
//            network.tf attachment pair, and the workspaces-LUKS host binding.
//
// All fixtures synthesized (cq-test-fixtures-synthesized-only).

import { createServer as createHttpServer, type Server as HttpServer } from "node:http";
import type { AddressInfo } from "node:net";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { NextRequest } from "next/server";
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { makeProxyTestTls, type ProxyTestTls } from "../../helpers/proxy-test-tls";
import { stripComments } from "../../helpers/strip-comments";

const { mockReport } = vi.hoisted(() => {
  // Route + function modules transitively import server/inngest/client.ts,
  // whose load-time env guards throw unless NEXT_PHASE is the build phase
  // (function-registry-count.test.ts convention). Set BEFORE any import.
  process.env.NEXT_PHASE = "phase-production-build";
  return { mockReport: vi.fn() };
});
vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReport,
  warnSilentFallback: vi.fn(),
  infoSilentFallback: vi.fn(),
}));

import {
  EXEC_FORWARD_HEADER,
  EXEC_FORWARD_PORT,
  EXEC_FORWARD_URL,
  EXEC_HOST_PRIVATE_IP,
  INNGEST_APP_ID_PREFIX,
  INNGEST_FAILURE_SUFFIX,
  INNGEST_SIGNATURE_HEADER,
  classifyFnId,
  decidePlacement,
  gatherPlacementFacts,
  type PlacementDecision,
  type PlacementFacts,
} from "@/server/inngest/exec-placement";
import {
  EXECUTION_PLACEMENT,
  EXECUTION_PLACEMENTS,
  type ExecutionPlacement,
} from "@/server/inngest/execution-placement";
import {
  EXEC_FORWARD_CONNECT_TIMEOUT_MS,
  EXEC_FORWARD_IDLE_TIMEOUT_MS,
  PlacementForwardError,
  buildForwardHeaders,
  dispatchPlacementAwarePost,
  forwardStepCall,
} from "@/server/inngest/exec-forward-client";
import { startInngestExecReceiver } from "@/server/inngest-exec-receiver";

// ---------------------------------------------------------------------------
// Shared fixtures
// ---------------------------------------------------------------------------

const APP_ROOT = join(__dirname, "..", "..", "..");
const ROUTE_REL = "app/api/inngest/route.ts";
const EXEC_PLACEMENT_REL = "server/inngest/exec-placement.ts";
const EXEC_FORWARD_REL = "server/inngest/exec-forward-client.ts";

const appFile = (rel: string): string =>
  readFileSync(join(APP_ROOT, rel), "utf8");
const infraFile = (rel: string): string =>
  readFileSync(join(APP_ROOT, "infra", rel), "utf8");

const ROUTE_SRC = appFile(ROUTE_REL);

/** RFC 7230 §6.1 hop-by-hop set + host — the envelope's allowed mutations. */
const HOP_BY_HOP = new Set([
  "connection",
  "keep-alive",
  "proxy-authenticate",
  "proxy-authorization",
  "te",
  "trailer",
  "transfer-encoding",
  "upgrade",
  "host",
]);

function connTokens(raw: string | null | undefined): Set<string> {
  const out = new Set<string>();
  for (const v of raw?.split(",") ?? []) {
    const t = v.trim().toLowerCase();
    if (t) out.add(t);
  }
  return out;
}

function facts(over: Partial<PlacementFacts> = {}): PlacementFacts {
  return {
    method: "POST",
    hasProbe: false,
    fnId: `${INNGEST_APP_ID_PREFIX}agent-on-spawn-requested`,
    marked: false,
    isExec: false,
    hasSignature: true,
    hostIp: null,
    ...over,
  };
}

/** A Request-shaped step POST the Guard-2 rows feed gatherPlacementFacts. */
function stepPost(opts: {
  fnId?: string | null;
  probe?: boolean;
  marked?: boolean;
  signed?: boolean;
  method?: string;
}): Request {
  const u = new URL("https://app.soleur.ai/api/inngest");
  if (opts.fnId) u.searchParams.set("fnId", opts.fnId);
  if (opts.probe) u.searchParams.set("probe", "trust_probe");
  const headers = new Headers();
  if (opts.signed !== false) headers.set(INNGEST_SIGNATURE_HEADER, "t=1&s=abc");
  if (opts.marked) headers.set(EXEC_FORWARD_HEADER, "1");
  const method = opts.method ?? "POST";
  return new Request(u, {
    method,
    headers,
    // GET/HEAD cannot carry a body — registration calls have none anyway.
    ...(method === "GET" || method === "HEAD" ? {} : { body: "{}" }),
  });
}

const decideFor = (req: Request): PlacementDecision =>
  decidePlacement(gatherPlacementFacts(req));

let tls: ProxyTestTls;
beforeAll(() => {
  tls = makeProxyTestTls();
});
afterAll(() => {
  tls.cleanup();
});
afterEach(() => {
  vi.clearAllMocks();
  vi.unstubAllEnvs();
});

function closeAll(
  ...servers: (HttpServer | import("node:https").Server | null | undefined)[]
): Promise<void> {
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

// ---------------------------------------------------------------------------
// The served set — parsed from route.ts (the serve() chokepoint), ids read off
// the REAL function objects so the rows exercise the shipped registry shape.
// ---------------------------------------------------------------------------

interface ServedFn {
  ident: string;
  spec: string;
  id: string;
}

function parseServed(): { ident: string; spec: string }[] {
  const imports = new Map<string, string>();
  for (const m of ROUTE_SRC.matchAll(
    /import\s*\{([^}]+)\}\s*from\s*"(@\/server\/inngest\/functions\/[^"]+)";/g,
  )) {
    for (const name of m[1].split(",")) {
      const ident = name.trim();
      if (ident) imports.set(ident, m[2]);
    }
  }
  const arr = ROUTE_SRC.match(
    /\bserve\(\{[\s\S]*?\bfunctions:\s*\[([\s\S]*?)\n\s*\]/,
  );
  if (!arr) throw new Error("route.ts: serve() functions array not found");
  const idents = [...arr[1].matchAll(/^\s*(\w+),?\s*$/gm)].map((e) => e[1]);
  return idents.map((ident) => {
    const spec = imports.get(ident);
    if (!spec) {
      throw new Error(
        `route.ts: served \`${ident}\` has no @/server/inngest/functions/* import`,
      );
    }
    return { ident, spec };
  });
}

let served: ServedFn[] = [];
let routeModule: typeof import("@/app/api/inngest/route");

// One cold import of the whole route graph (the SDK + every function module),
// paid against the 60 s hook budget — the signature-verify convention (#5113).
beforeAll(async () => {
  routeModule = await import("@/app/api/inngest/route");
  served = await Promise.all(
    parseServed().map(async ({ ident, spec }) => {
      const mod = (await import(spec)) as Record<
        string,
        { id?: unknown; opts?: { id?: string } }
      >;
      const fn = mod[ident];
      const id =
        typeof fn?.id === "function" ? (fn.id as () => string)() : fn?.opts?.id;
      if (typeof id !== "string") {
        throw new Error(`cannot read a function id off ${ident} (${spec})`);
      }
      return { ident, spec, id };
    }),
  );
}, 60_000);

// ===========================================================================
// Guard 1 — served-set/classifier parity
// ===========================================================================

describe("Guard 1 — served-set/classifier parity", () => {
  it("every served id resolves through classifyFnId to exactly one EXECUTION_PLACEMENT class", () => {
    expect(served.length).toBeGreaterThan(0);
    for (const s of served) {
      const cls = classifyFnId(`${INNGEST_APP_ID_PREFIX}${s.id}`);
      // RED row: a served function with no manifest row classifies null.
      expect(
        cls,
        `${s.id} (${s.spec}) must resolve to a manifest class`,
      ).not.toBeNull();
      expect(EXECUTION_PLACEMENTS).toContain(cls);
      // The class the classifier returns IS the manifest row — no second table.
      expect(cls).toBe(EXECUTION_PLACEMENT[s.id]?.placement);
    }
  });

  it("the served set and the manifest keys are the same set — a stale row is RED", () => {
    // RED row: a manifest row for an id no route serves.
    expect(new Set(served.map((s) => s.id))).toEqual(
      new Set(Object.keys(EXECUTION_PLACEMENT)),
    );
  });

  it("every <id>-failure wire id inherits its parent's class (onFailure handler)", () => {
    // GREEN-PASS row: an onFailure handler added to a served function keeps the
    // parent's class — asserted for EVERY served id, not a sample.
    for (const s of served) {
      expect(
        classifyFnId(
          `${INNGEST_APP_ID_PREFIX}${s.id}${INNGEST_FAILURE_SUFFIX}`,
        ),
        `${s.id}-failure must inherit the parent's class`,
      ).toBe(EXECUTION_PLACEMENT[s.id]?.placement);
    }
  });

  it("a class change flips the verdict — per-class decision parity over the whole served set", () => {
    // RED row: `portable` → `host-affine` moves the function's decision.
    for (const s of served) {
      const d = decidePlacement(
        facts({ fnId: `${INNGEST_APP_ID_PREFIX}${s.id}` }),
      );
      if (EXECUTION_PLACEMENT[s.id].placement === "portable") {
        expect(d, `portable ${s.id} must execute on a non-exec host`).toEqual({
          action: "execute",
        });
      } else {
        expect(
          d,
          `${EXECUTION_PLACEMENT[s.id].placement} ${s.id} must forward on a non-exec host`,
        ).toEqual({ action: "forward", target: EXEC_FORWARD_URL });
      }
    }
  });

  it("a missing or doubled soleur-runtime- prefix is unclassifiable → pinned-class fail-closed, never a wrong-class execute", () => {
    // RED row: prefix missing or doubled → classifier fail-closed, forward on
    // non-exec (the exec host's SDK is the arbiter), NEVER execute.
    for (const s of served) {
      for (const bad of [
        s.id, // prefix missing
        `${INNGEST_APP_ID_PREFIX}${INNGEST_APP_ID_PREFIX}${s.id}`, // doubled
      ]) {
        expect(classifyFnId(bad), `${bad} must not classify`).toBeNull();
        expect(
          decidePlacement(facts({ fnId: bad })),
          `${bad} must take the pinned direction on a non-exec host`,
        ).toEqual({ action: "forward", target: EXEC_FORWARD_URL });
      }
    }
  });

  it("the classifier reads THE EXECUTION_PLACEMENT object — a live mutation is visible through it", () => {
    // RED row: the classifier module replaced by a copy. A shape-equal copy
    // never sees a mutation of THE table; the imported object does.
    const mutable = EXECUTION_PLACEMENT as Record<
      string,
      { placement: ExecutionPlacement; reason: string }
    >;
    const probeId = "guard1-identity-probe";
    mutable[probeId] = { placement: "portable", reason: "identity probe" };
    try {
      expect(
        classifyFnId(`${INNGEST_APP_ID_PREFIX}${probeId}`),
        "the classifier must observe THE manifest object, not a copy",
      ).toBe("portable");
    } finally {
      delete mutable[probeId];
    }
  });

  it("the app-id prefix is the client's real id — never a drifted literal (review #12554 P3)", () => {
    // Replicated-literal parity (replicated literals across >=2 source files
    // need a parity pin): client.ts `new Inngest({ id: "soleur-runtime" })` is
    // the SDK-side app id and `classifyFnId` keys on `${id}-`. Guard 1 builds
    // wire ids FROM the constant, so only a source assertion ties them — a
    // client-id rename would otherwise silently unclassify every step call.
    const client = stripComments(
      appFile("server/inngest/client.ts"),
      "client.ts",
    );
    const m = client.match(/new\s+Inngest\(\{[^}]*\bid:\s*"([^"]+)"/);
    expect(m, "client.ts must declare the Inngest app id").not.toBeNull();
    expect(`${m![1]}-`).toBe(INNGEST_APP_ID_PREFIX);
  });

  it("exec-placement.ts binds EXECUTION_PLACEMENT from ./execution-placement — never a re-declared table", () => {
    const src = stripComments(appFile(EXEC_PLACEMENT_REL), "exec-placement.ts");
    expect(src).toMatch(
      /import\s*\{[^}]*\bEXECUTION_PLACEMENT\b[^}]*\}\s*from\s*"\.\/execution-placement"/,
    );
  });
});

// ===========================================================================
// Guard 2 — fail-closed direction (the decision matrix, request-shaped)
// ===========================================================================

describe("Guard 2 — fail-closed direction", () => {
  const PINNED = `${INNGEST_APP_ID_PREFIX}agent-on-spawn-requested`; // volume-bound
  const NONEXEC = "10.0.1.11";

  it("SOLEUR_HOST_PRIVATE_IP unset / empty / 0.0.0.0 + a pinned call → refuse, never execute", () => {
    for (const v of [undefined, "", "   ", "0.0.0.0"] as const) {
      vi.stubEnv("SOLEUR_HOST_PRIVATE_IP", v as string);
      expect(decideFor(stepPost({ fnId: PINNED })), `env=${JSON.stringify(v)}`).toEqual({
        action: "refuse",
        reason: "exec_identity_missing",
        status: 503,
        error: "placement.exec_identity_missing",
      });
    }
  });

  it("SOLEUR_HOST_PRIVATE_IP=10.0.1.11 (web-2) + a signed pinned call → forward to 10.0.1.10, marker set", () => {
    vi.stubEnv("SOLEUR_HOST_PRIVATE_IP", NONEXEC);
    expect(decideFor(stepPost({ fnId: PINNED }))).toEqual({
      action: "forward",
      target: EXEC_FORWARD_URL,
    });
    expect(EXEC_FORWARD_URL).toBe(`https://${EXEC_HOST_PRIVATE_IP}:8445/api/inngest`);
    // "marker set" — buildForwardHeaders is what stamps the loop-guard header.
    const out = buildForwardHeaders(stepPost({ fnId: PINNED }));
    expect(out[EXEC_FORWARD_HEADER]).toBe("1");
  });

  it("a marked call on a non-exec host → refuse marked_on_nonexec — never re-forward", () => {
    vi.stubEnv("SOLEUR_HOST_PRIVATE_IP", NONEXEC);
    expect(decideFor(stepPost({ fnId: PINNED, marked: true }))).toEqual({
      action: "refuse",
      reason: "marked_on_nonexec",
      status: 403,
      error: "placement.marked_on_nonexec",
    });
    // Dispatch level: the refusal is the RESPONSE, the local handler never runs.
    const localPost = vi.fn(async () => new Response("local"));
    return dispatchPlacementAwarePost(
      stepPost({ fnId: PINNED, marked: true }),
      undefined,
      localPost,
    ).then(async (res) => {
      expect(res.status).toBe(403);
      expect(await res.json()).toEqual({
        error: "placement.marked_on_nonexec",
      });
      expect(localPost).not.toHaveBeenCalled();
    });
  });

  it("a marked call on an unidentifiable host → refuse exec_identity_missing", () => {
    vi.stubEnv("SOLEUR_HOST_PRIVATE_IP", "");
    expect(decideFor(stepPost({ fnId: PINNED, marked: true }))).toEqual({
      action: "refuse",
      reason: "exec_identity_missing",
      status: 503,
      error: "placement.exec_identity_missing",
    });
  });

  it("POST with no fnId and no probe → forward on non-exec (fail-closed; the exec SDK rejects it)", () => {
    vi.stubEnv("SOLEUR_HOST_PRIVATE_IP", NONEXEC);
    expect(decideFor(stepPost({}))).toEqual({
      action: "forward",
      target: EXEC_FORWARD_URL,
    });
    // …and own-dispatch on the exec host itself.
    vi.stubEnv("SOLEUR_HOST_PRIVATE_IP", EXEC_HOST_PRIVATE_IP);
    expect(decideFor(stepPost({}))).toEqual({ action: "execute" });
  });

  it("?probe= on a non-exec host → execute locally (must-PASS: probes answer anywhere)", () => {
    for (const v of [NONEXEC, ""] as const) {
      vi.stubEnv("SOLEUR_HOST_PRIVATE_IP", v);
      expect(decideFor(stepPost({ fnId: PINNED, probe: true }))).toEqual({
        action: "execute",
      });
      expect(decideFor(stepPost({ probe: true }))).toEqual({
        action: "execute",
      });
    }
  });

  it("GET/PUT registration on a non-exec host → execute locally (must-PASS)", () => {
    vi.stubEnv("SOLEUR_HOST_PRIVATE_IP", NONEXEC);
    for (const method of ["GET", "PUT"] as const) {
      expect(decideFor(stepPost({ method, fnId: PINNED }))).toEqual({
        action: "execute",
      });
    }
  });

  it("a pinned call on the exec host → execute locally (own dispatch)", () => {
    vi.stubEnv("SOLEUR_HOST_PRIVATE_IP", EXEC_HOST_PRIVATE_IP);
    expect(decideFor(stepPost({ fnId: PINNED }))).toEqual({
      action: "execute",
    });
    vi.stubEnv("SOLEUR_HOST_PRIVATE_IP", ` ${EXEC_HOST_PRIVATE_IP} `);
    expect(decideFor(stepPost({ fnId: PINNED }))).toEqual({
      action: "execute",
    });
  });

  it("a pinned call on a non-exec host with no signature → refuse before any dial (AC9b)", () => {
    vi.stubEnv("SOLEUR_HOST_PRIVATE_IP", NONEXEC);
    expect(decideFor(stepPost({ fnId: PINNED, signed: false }))).toEqual({
      action: "refuse",
      reason: "missing_signature",
      status: 401,
      error: "placement.missing_signature",
    });
  });

  it("the route's POST is wrapped — a marked request-shaped probe on a non-exec host answers the placement refusal, never the SDK handler", async () => {
    // RED row: the forwarder removed from the route (serve() exposed
    // directly). Unwrapped, this request reaches the SDK handler — a streamed
    // 201/401 envelope, never a 403 placement.marked_on_nonexec body.
    vi.stubEnv("SOLEUR_HOST_PRIVATE_IP", NONEXEC);
    const res = await routeModule.POST(
      new Request("https://app.soleur.ai/api/inngest?fnId=soleur-runtime-agent-on-spawn-requested", {
        method: "POST",
        headers: {
          [EXEC_FORWARD_HEADER]: "1",
          [INNGEST_SIGNATURE_HEADER]: "t=1&s=abc",
          "content-type": "application/json",
        },
        body: "{}",
      }) as unknown as NextRequest,
      undefined,
    );
    expect(res.status).toBe(403);
    expect(await res.json()).toEqual({
      error: "placement.marked_on_nonexec",
    });
    // The refusal is mirrored to Sentry with the placement feature tag.
    expect(mockReport).toHaveBeenCalledWith(
      null,
      expect.objectContaining({
        feature: "inngest-exec-placement",
        op: "placement.marked_on_nonexec",
      }),
    );
  });

  it("route-level: a pinned call with unestablished exec identity → 503 refuse (retriable, never a 4xx dead-end)", async () => {
    vi.stubEnv("SOLEUR_HOST_PRIVATE_IP", "");
    const res = await routeModule.POST(
      new Request("https://app.soleur.ai/api/inngest?fnId=soleur-runtime-agent-on-spawn-requested", {
        method: "POST",
        headers: {
          [INNGEST_SIGNATURE_HEADER]: "t=1&s=abc",
          "content-type": "application/json",
        },
        body: "{}",
      }) as unknown as NextRequest,
      undefined,
    );
    expect(res.status).toBe(503);
    expect(await res.json()).toEqual({
      error: "placement.exec_identity_missing",
    });
  });
});

// ===========================================================================
// Guard 3 — forwarder wire fidelity, end-to-end through the real receiver
// ===========================================================================

interface SeenRequest {
  method?: string;
  url?: string;
  headers: Record<string, string | string[] | undefined>;
  body: Buffer;
}

/** The real :8445 receiver (ephemeral port) re-emitting onto a fixture app. */
async function execIngressFixture(
  handler: (
    req: import("node:http").IncomingMessage,
    res: import("node:http").ServerResponse,
  ) => void,
): Promise<{ receiver: import("node:https").Server; app: HttpServer; port: number }> {
  vi.stubEnv("PROXY_TLS_KEY", tls.KEY);
  vi.stubEnv("PROXY_TLS_CERT", tls.CERT);
  vi.stubEnv("SOLEUR_PROXY_BIND", "127.0.0.1");
  vi.stubEnv("SOLEUR_PROXY_PEER_ALLOWLIST", "127.0.0.1");
  const app = createHttpServer(handler);
  const receiver = startInngestExecReceiver({
    httpServer: app,
    port: 0,
    privateBindPrefix: "127.0.0.",
  });
  expect(receiver).not.toBeNull();
  await new Promise<void>((r) => receiver!.once("listening", r));
  const port = (receiver!.address() as AddressInfo).port;
  return { receiver: receiver!, app, port };
}

describe("Guard 3 — forwarder wire fidelity (end-to-end through the real receiver)", () => {
  it("a pinned step POST is byte-faithful end to end: method, path, full query, end-to-end headers + marker, raw body; the response streams", async () => {
    const seen: SeenRequest[] = [];
    const { receiver, app, port } = await execIngressFixture((req, res) => {
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
        res.write("chunk-1 ");
        setTimeout(() => {
          res.write("chunk-2");
          res.end();
        }, 120);
      });
    });

    const body = '{"ctx":{"fn_id":"x"},"steps":{}}';
    const inboundHeaders = {
      "x-inngest-signature": "t=1700000000&s=deadbeef",
      "x-inngest-sdk": "inngest-js v4",
      "x-request-id": "rid-9",
      "content-type": "application/json",
      "content-length": String(body.length),
      connection: "keep-alive, x-hop-token",
      "x-hop-token": "drop-me",
      "keep-alive": "timeout=5",
      "proxy-authorization": "Basic drop",
      te: "trailers",
      upgrade: "websocket",
      host: "app.soleur.ai",
    };
    const req = new Request(
      "https://app.soleur.ai/api/inngest?fnId=soleur-runtime-agent-on-spawn-requested&stepId=s&deployId=d",
      { method: "POST", headers: inboundHeaders, body },
    );
    const res = await forwardStepCall(req, {
      ca: tls.CERT,
      target: `https://127.0.0.1:${port}`,
    });

    // must-PASS row: forwarded response bytes + status identical — and
    // STREAMED: the first chunk resolves before the upstream completes.
    expect(res.status).toBe(201);
    const reader = res.body!.getReader();
    const first = await reader.read();
    expect(new TextDecoder().decode(first.value)).toContain("chunk-1");
    const rest: Buffer[] = [];
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      if (value) rest.push(Buffer.from(value));
    }
    expect(Buffer.concat(rest).toString()).toContain("chunk-2");

    expect(seen).toHaveLength(1);
    const got = seen[0];
    expect(got.method).toBe("POST");
    expect(got.url).toBe(
      "/api/inngest?fnId=soleur-runtime-agent-on-spawn-requested&stepId=s&deployId=d",
    );
    expect(got.body.toString()).toBe(body);

    // Header-set equality modulo Host + the marker + the RFC 7230 hop-by-hop
    // set (incl. Connection-named tokens). A dropped end-to-end header is RED.
    const inboundEndToEnd = new Set(
      Object.keys(inboundHeaders)
        .map((n) => n.toLowerCase())
        .filter(
          (n) => !HOP_BY_HOP.has(n) && !connTokens(inboundHeaders.connection).has(n),
        ),
    );
    const receivedEndToEnd = new Set(
      Object.keys(got.headers)
        .map((n) => n.toLowerCase())
        .filter((n) => n && !HOP_BY_HOP.has(n)),
    );
    expect(receivedEndToEnd).toEqual(
      new Set([...inboundEndToEnd, EXEC_FORWARD_HEADER]),
    );
    for (const name of inboundEndToEnd) {
      const want =
        inboundHeaders[name as keyof typeof inboundHeaders] ??
        inboundHeaders[
          Object.keys(inboundHeaders).find(
            (k) => k.toLowerCase() === name,
          ) as keyof typeof inboundHeaders
        ];
      expect(got.headers[name], `header ${name} must arrive verbatim`).toBe(want);
    }
    expect(got.headers[EXEC_FORWARD_HEADER]).toBe("1");
    expect(got.headers.host).toBe(`127.0.0.1:${port}`); // the target's own Host
    await closeAll(receiver, app);
  });

  it("an untrusted CA fails closed with placement.forward_failed — and the dial pins ca + rejectUnauthorized: true literally", async () => {
    // RED row: rejectUnauthorized:false or ca omitted. Behaviour first…
    const other = makeProxyTestTls();
    const { receiver, app, port } = await execIngressFixture((_req, res) => {
      res.writeHead(200);
      res.end("unreachable");
    });
    await expect(
      forwardStepCall(
        new Request("https://app.soleur.ai/api/inngest?fnId=x", {
          method: "POST",
        }),
        { ca: other.CERT, target: `https://127.0.0.1:${port}` },
      ),
    ).rejects.toBeInstanceOf(PlacementForwardError);
    await closeAll(receiver, app);
    other.cleanup();

    // …then the options literal (comment-stripped source, helpers/strip-comments).
    const src = stripComments(
      appFile(EXEC_FORWARD_REL),
      "exec-forward-client.ts",
    );
    expect(src).toContain("rejectUnauthorized: true");
    expect(src).not.toContain("rejectUnauthorized: false");
    expect(src).not.toContain("checkServerIdentity"); // never a new identity check
    expect(src).toMatch(
      /httpsRequest\(\s*target\s*,\s*\{[\s\S]*?\bca\b[\s\S]*?rejectUnauthorized: true/,
    );
  });

  it("the marker header is stamped on the forward (omitting it is RED at the app side)", () => {
    // RED row: marker omitted on forward — covered end-to-end above; this pins
    // the builder itself so the mutation fails fast and named.
    const req = new Request("https://app.soleur.ai/api/inngest?fnId=x", {
      method: "POST",
      headers: { "x-inngest-signature": "t=1&s=a" },
    });
    const out = buildForwardHeaders(req);
    expect(out[EXEC_FORWARD_HEADER]).toBe("1");
  });

  it("the forward target is the literal https://10.0.1.10:8445 pin — never request-Host- or env-derived", () => {
    // RED row: target derived from request Host or env.
    expect(EXEC_FORWARD_URL).toBe("https://10.0.1.10:8445/api/inngest");
    expect(EXEC_FORWARD_PORT).toBe(8445);
    expect(
      decidePlacement(facts()),
      "the decision's forward target is the pin literal",
    ).toEqual({ action: "forward", target: EXEC_FORWARD_URL });
    // The constant is literal in source — not `${...}`-computed.
    const src = stripComments(appFile(EXEC_PLACEMENT_REL), "exec-placement.ts");
    expect(src).toContain(
      'EXEC_FORWARD_URL = "https://10.0.1.10:8445/api/inngest"',
    );
  });

  it("a forward with no target override dials the pinned origin and fails closed when unreachable", async () => {
    // The DEFAULT target is EXEC_FORWARD_URL: with no `target` dep the dial is
    // attempted against the pin — a bounded connect failure proves the pin is
    // what was dialed (never a request-derived or local fallback target).
    await expect(
      forwardStepCall(
        new Request("https://app.soleur.ai/api/inngest?fnId=x&probe=none", {
          method: "POST",
          headers: { host: "app.soleur.ai" },
        }),
        { ca: tls.CERT, connectTimeoutMs: 400 },
      ),
    ).rejects.toBeInstanceOf(PlacementForwardError);
  });

  it("a marked request dispatched on a non-exec host refuses — the second hop never happens (loop-guard)", async () => {
    // Harness row: the fixture sees the loop twice → RED. At dispatch level
    // the marked request on a non-exec host is refused BEFORE any dial — a
    // second hop can never start.
    vi.stubEnv("SOLEUR_HOST_PRIVATE_IP", "10.0.1.11");
    const localPost = vi.fn(async () => new Response("local"));
    const res = await dispatchPlacementAwarePost(
      stepPost({ fnId: `${INNGEST_APP_ID_PREFIX}agent-on-spawn-requested`, marked: true }),
      undefined,
      localPost,
    );
    expect(res.status).toBe(403);
    expect(await res.json()).toEqual({ error: "placement.marked_on_nonexec" });
    expect(localPost).not.toHaveBeenCalled();
    // …and the refuse path emits the Sentry mirror (Guard-2's feature tag).
    expect(mockReport).toHaveBeenCalledWith(
      null,
      expect.objectContaining({ op: "placement.marked_on_nonexec" }),
    );
  });
});

// ===========================================================================
// Guard 4 — pin-target drift: one source of truth for 10.0.1.10
// ===========================================================================

describe("Guard 4 — pin-target drift", () => {
  it("the constant is the literal 10.0.1.10 in exec-placement.ts", () => {
    // RED row: constant changed to 10.0.1.11.
    expect(EXEC_HOST_PRIVATE_IP).toBe("10.0.1.10");
    const src = stripComments(appFile(EXEC_PLACEMENT_REL), "exec-placement.ts");
    expect(src).toContain('EXEC_HOST_PRIVATE_IP = "10.0.1.10"');
  });

  it("inngest-host.tf sdk_url's host IS the pin", () => {
    // RED row: sdk_url host changed.
    const tf = infraFile("inngest-host.tf");
    const m = tf.match(
      /sdk_url\s*=\s*"http:\/\/(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}):(\d+)\/api\/inngest"/,
    );
    expect(m, "inngest-host.tf must declare a literal sdk_url").not.toBeNull();
    expect(m![1]).toBe(EXEC_HOST_PRIVATE_IP);
    expect(tf).toContain('sdk_url = "http://10.0.1.10:3000/api/inngest"');
  });

  it("variables.tf web-1 private_ip IS the pin, and network.tf attaches var.web_hosts at each.value.private_ip", () => {
    const vars = infraFile("variables.tf");
    const web1 = vars.match(/"web-1"\s*=\s*\{[^}]*\}/);
    expect(web1, "variables.tf must declare a web-1 host").not.toBeNull();
    const ip = web1![0].match(/private_ip\s*=\s*"([^"]+)"/);
    expect(ip).not.toBeNull();
    expect(ip![1]).toBe(EXEC_HOST_PRIVATE_IP);

    const net = infraFile("network.tf");
    const attach = net.match(
      /resource\s+"hcloud_server_network"\s+"web"\s*\{[\s\S]*?\n\}/,
    );
    expect(
      attach,
      "network.tf must declare hcloud_server_network.web",
    ).not.toBeNull();
    expect(attach![0]).toContain("for_each  = var.web_hosts");
    expect(attach![0]).toContain("ip        = each.value.private_ip");
    expect(attach![0]).toContain("hcloud_server.web[each.key].id");
  });

  it("the workspaces_luks attachment is bound to web-1 — the pin follows the volume holder", () => {
    // RED row: the workspaces-LUKS host binding repointed to web-2. A
    // declarable attachment exists (workspaces-luks.tf), so the pin binds to
    // it directly; the hcloud_server_network.web["web-1"] pair above is the
    // same coupling at the NIC layer.
    const luks = infraFile("workspaces-luks.tf");
    const attach = luks.match(
      /resource\s+"hcloud_volume_attachment"\s+"workspaces_luks"\s*\{[\s\S]*?\n\}/,
    );
    expect(
      attach,
      "workspaces-luks.tf must declare hcloud_volume_attachment.workspaces_luks",
    ).not.toBeNull();
    expect(attach![0]).toContain(
      'server_id = hcloud_server.web["web-1"].id',
    );
    expect(attach![0]).toContain(
      "volume_id = hcloud_volume.workspaces_luks.id",
    );
  });

  it("SOLEUR_HOST_PRIVATE_IP injection is pinned on the prod docker-run tuple, empty on the canary, ${private_ip} on first boot", () => {
    // RED row: injection line removed from the prod tuple (the
    // docker-run-tuple.test.sh K32* rows pin the same tuple end-to-end; these
    // literals are the Guard-4 binding).
    const deploy = infraFile("ci-deploy.sh");
    expect(deploy).toContain('-e SOLEUR_HOST_PRIVATE_IP="$PROXY_BIND"');
    // Exactly one prod injection LINE (line-anchored — prose mentions don't
    // count); a second literal-IP injection is a drift.
    expect(
      deploy.match(/^\s*-e SOLEUR_HOST_PRIVATE_IP="\$PROXY_BIND"/gm),
    ).toHaveLength(1);
    expect(deploy).not.toMatch(/^\s*-e SOLEUR_HOST_PRIVATE_IP=\d/m);
    // Canary carries it literal-empty.
    expect(deploy).toContain("-e SOLEUR_HOST_PRIVATE_IP= \\");
    // First-boot tuple resolves the host's private_ip at template time.
    const ci = infraFile("cloud-init.yml");
    expect(ci).toContain("-e SOLEUR_HOST_PRIVATE_IP=${private_ip}");
    // The prod tuple publishes the exec-forward receiver exactly like :8443.
    expect(deploy).toContain(
      '-p "${RELAY_PUBLISH_BIND:-127.0.0.1}:8445:8445"',
    );
  });

  it("must-PASS: the constants agree across code, sdk_url, web-1, and the tuples (real tree, unmutated)", () => {
    // GREEN row: one source of truth.
    const tf = infraFile("inngest-host.tf");
    const vars = infraFile("variables.tf");
    const sdkHost = tf.match(
      /sdk_url\s*=\s*"http:\/\/(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}):/,
    )![1];
    const web1ip = vars
      .match(/"web-1"\s*=\s*\{[^}]*\}/)![0]
      .match(/private_ip\s*=\s*"([^"]+)"/)![1];
    expect(
      new Set([EXEC_HOST_PRIVATE_IP, sdkHost, web1ip]),
      "pin / sdk_url / web-1 private_ip must agree",
    ).toEqual(new Set(["10.0.1.10"]));
  });

  it("no TOTAL read deadline on the forward — only a connect bound plus a per-chunk idle bound", () => {
    // RED row: a TOTAL read deadline (streamed steps outlive any total
    // deadline — ADR-243's CF-524 class). The two named bounds stand; any
    // other timeout-shaped construct on the forward path reds this.
    expect(EXEC_FORWARD_CONNECT_TIMEOUT_MS).toBeGreaterThan(0);
    expect(EXEC_FORWARD_IDLE_TIMEOUT_MS).toBeGreaterThan(0);
    const src = stripComments(
      appFile(EXEC_FORWARD_REL),
      "exec-forward-client.ts",
    );
    expect(src.match(/\.setTimeout\(/g)).toHaveLength(2);
    expect(src).toContain("upstream.setTimeout(connectTimeoutMs)");
    expect(src).toContain("socket.setTimeout(idleTimeoutMs)");
    for (const banned of [
      "AbortSignal",
      "headersTimeout",
      "requestTimeout",
      "keepAliveTimeout",
      "timeout:",
    ]) {
      expect(src, `the forward path must not carry \`${banned}\``).not.toContain(
        banned,
      );
    }
  });
});
