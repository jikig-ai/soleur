// #12517 — hermetic tests for the egress injector spike's per-session CONNECT router (CTO R24, R26).
//
// connect-router.mjs is the first chokepoint of Guard 2: it is the only path by which a CONNECT reaches iron-proxy,
// which terminates every tunnel it is given (tracer item 2). These tests pin its pure parts — the bounded head
// reader, the CONNECT head parse, target normalization, the route decision and the inbound credential check — and
// then drive the real server over loopback with stub upstreams (no TLS anywhere; the router never terminates).
// Guard 2 rows 11 and 12 are covered here. Fixtures are synthesized (cq-test-fixtures-synthesized-only).

import { once } from "node:events";
import net from "node:net";
import { afterEach, describe, expect, it } from "vitest";

import * as router from "./infra/egress-injector-spike/connect-router.mjs";

const SESSION_CRED = "sess-cred-synthetic";
const basic = (user: string, pass: string) => "Basic " + Buffer.from(`${user}:${pass}`).toString("base64");

describe("connect-router.mjs — head reader (16 KiB cap)", () => {
  it("returns the head and the bytes after the blank line, across chunk boundaries", () => {
    const r = router.createHeadReader();
    expect(r.push(Buffer.from("CONNECT github.com:443 HTTP/1.1\r\nHost: github.com:443\r"))).toEqual({ state: "need-more" });
    const out = r.push(Buffer.from("\n\r\n\x16\x03\x01"));
    expect(out.state).toBe("done");
    expect(out.head).toBe("CONNECT github.com:443 HTTP/1.1\r\nHost: github.com:443");
    expect([...out.rest!]).toEqual([0x16, 0x03, 0x01]);
  });

  it("refuses a head past the cap", () => {
    expect(router.HEAD_CAP).toBe(16 * 1024);
    const r = router.createHeadReader();
    const big = Buffer.alloc(router.HEAD_CAP + 1, "a");
    expect(r.push(big).state).toBe("too-large");
  });
});

describe("connect-router.mjs — parse and normalize", () => {
  it("parses a CONNECT head with its Proxy-Authorization", () => {
    const p = router.parseConnectHead(`CONNECT GitHub.com.:443 HTTP/1.1\r\nHost: x\r\nProxy-Authorization: ${basic("s", SESSION_CRED)}`);
    expect(p).toMatchObject({ ok: true, method: "CONNECT", host: "github.com", port: 443 });
    expect(p.proxyAuthorization).toBe(basic("s", SESSION_CRED));
  });

  it("refuses non-CONNECT methods, including absolute-form plain HTTP (405)", () => {
    expect(router.parseConnectHead("GET http://github.com/ HTTP/1.1\r\nHost: github.com")).toMatchObject({ ok: false, status: 405 });
    expect(router.parseConnectHead("POST / HTTP/1.1")).toMatchObject({ ok: false, status: 405 });
  });

  it("refuses a malformed target (400)", () => {
    for (const line of [
      "CONNECT github.com HTTP/1.1",
      "CONNECT github.com:0 HTTP/1.1",
      "CONNECT github.com:99999 HTTP/1.1",
      "CONNECT github.com:44x3 HTTP/1.1",
      "CONNECT github.com..:443 HTTP/1.1",
      "CONNECT git_hub.com:443 HTTP/1.1",
      "CONNECT :443 HTTP/1.1",
      "CONNECT github.com:443",
      "garbage",
    ]) {
      expect(router.parseConnectHead(line), line).toMatchObject({ ok: false, status: 400 });
    }
  });

  it("normalizes case and one trailing dot; recognizes IP literals", () => {
    expect(router.normalizeHost("API.GitHub.COM.")).toBe("api.github.com");
    expect(router.parseConnectHead("CONNECT 140.82.112.3:443 HTTP/1.1")).toMatchObject({ ok: true, host: "140.82.112.3", ip: true });
    expect(router.parseConnectHead("CONNECT [2606:50c0::1]:443 HTTP/1.1")).toMatchObject({ ok: true, host: "2606:50c0::1", ip: true });
  });
});

describe("connect-router.mjs — route decision (R24)", () => {
  const route = (head: string) => {
    const p = router.parseConnectHead(head);
    expect(p.ok).toBe(true);
    return router.routeConnect(p);
  };

  it("sends exactly the four inject hosts on 443 to iron-proxy", () => {
    for (const h of ["github.com", "api.github.com", "uploads.github.com", "codeload.github.com", "GITHUB.com."]) {
      expect(route(`CONNECT ${h}:443 HTTP/1.1`), h).toEqual({ branch: "injector" });
    }
  });

  it("Guard 2 row 11: suffix, prefix and substring look-alikes go to the forwarder", () => {
    for (const h of ["evilgithub.com", "github.com.evil", "gist.github.com", "raw.githubusercontent.com", "xgithub.com", "api.github.co"]) {
      expect(route(`CONNECT ${h}:443 HTTP/1.1`), h).toEqual({ branch: "forwarder" });
    }
  });

  it("Guard 2 row 12: a non-inject host (the Anthropic API) goes to the forwarder", () => {
    expect(route("CONNECT api.anthropic.com:443 HTTP/1.1")).toEqual({ branch: "forwarder" });
  });

  it("IP literals go to the forwarder, never iron-proxy", () => {
    expect(route("CONNECT 140.82.112.3:443 HTTP/1.1")).toEqual({ branch: "forwarder" });
    expect(route("CONNECT [::1]:443 HTTP/1.1")).toEqual({ branch: "forwarder" });
  });

  it("an inject name on another port is refused 403", () => {
    expect(route("CONNECT github.com:80 HTTP/1.1")).toEqual({ branch: "refused", status: 403 });
    expect(route("CONNECT api.github.com:8443 HTTP/1.1")).toEqual({ branch: "refused", status: 403 });
  });
});

describe("connect-router.mjs — inbound credential", () => {
  it("accepts only the session credential (any user name), constant-time compared", () => {
    expect(router.checkProxyAuthorization(basic("session", SESSION_CRED), SESSION_CRED)).toBe(true);
    expect(router.checkProxyAuthorization(basic("session", SESSION_CRED + "x"), SESSION_CRED)).toBe(false);
    expect(router.checkProxyAuthorization(basic("session", ""), SESSION_CRED)).toBe(false);
    expect(router.checkProxyAuthorization(undefined, SESSION_CRED)).toBe(false);
    expect(router.checkProxyAuthorization("Bearer " + SESSION_CRED, SESSION_CRED)).toBe(false);
    expect(() => router.checkProxyAuthorization(basic("s", "x"), "")).toThrow();
  });

  it("rewrites the head: strips every client Proxy-Authorization, normalizes the target, adds the upstream credential", () => {
    const head = `CONNECT GitHub.com.:443 HTTP/1.1\r\nHost: GitHub.com.:443\r\nProxy-Authorization: ${basic("s", SESSION_CRED)}\r\nproxy-authorization: dup`;
    const p = router.parseConnectHead(head);
    const out = router.rewriteHead(p, basic("router", "up-cred"));
    expect(out).toBe(`CONNECT github.com:443 HTTP/1.1\r\nHost: github.com:443\r\nProxy-Authorization: ${basic("router", "up-cred")}\r\n\r\n`);
    expect(out).not.toContain(SESSION_CRED);
    expect(out).not.toContain("dup");
  });
});

// ---------------------------------------------------------------------------------------------------------------
// The real server over loopback: two stub upstreams record what reaches them.
// ---------------------------------------------------------------------------------------------------------------

type Stub = { port: number; heads: string[]; server: net.Server };

async function stubUpstream(): Promise<Stub> {
  const heads: string[] = [];
  const server = net.createServer((sock) => {
    let buf = "";
    sock.on("data", (d) => {
      buf += d.toString("latin1");
      const end = buf.indexOf("\r\n\r\n");
      if (end !== -1 && !sock.readableEnded) {
        heads.push(buf.slice(0, end));
        sock.write("HTTP/1.1 200 Connection Established\r\n\r\n");
        sock.write(buf.slice(end + 4)); // echo the tunneled bytes back
        buf = "";
      }
    });
    sock.on("error", () => {});
  });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  return { port: (server.address() as net.AddressInfo).port, heads, server };
}

const closers: Array<() => void> = [];
afterEach(() => {
  while (closers.length) closers.pop()!();
});

async function startRouter() {
  const injector = await stubUpstream();
  const forwarder = await stubUpstream();
  const srv = router.createRouter({
    sessionCredential: SESSION_CRED,
    injector: { host: "127.0.0.1", port: injector.port, credential: basic("router", "router-cred-synthetic") },
    forwarder: { host: "127.0.0.1", port: forwarder.port, credential: basic("ws-synthetic", "fwd-token-synthetic") },
    log: () => {},
  });
  srv.listen(0, "127.0.0.1");
  await once(srv, "listening");
  closers.push(() => srv.close(), () => injector.server.close(), () => forwarder.server.close());
  return { port: (srv.address() as net.AddressInfo).port, injector, forwarder, srv };
}

async function send(port: number, data: string): Promise<string> {
  const sock = net.connect(port, "127.0.0.1");
  await once(sock, "connect");
  sock.write(data);
  let out = "";
  sock.on("data", (d) => (out += d.toString("latin1")));
  await Promise.race([once(sock, "close"), new Promise((r) => setTimeout(r, 400))]);
  sock.destroy();
  return out;
}

describe("connect-router.mjs — server", () => {
  it("407 without the session credential; nothing reaches either upstream", async () => {
    const { port, injector, forwarder } = await startRouter();
    const out = await send(port, "CONNECT github.com:443 HTTP/1.1\r\nHost: github.com:443\r\n\r\n");
    expect(out).toMatch(/^HTTP\/1\.1 407 /);
    expect(injector.heads).toHaveLength(0);
    expect(forwarder.heads).toHaveLength(0);
  });

  it("an inject host goes to iron-proxy with the router credential; tunneled bytes pass through unchanged", async () => {
    const { port, injector, forwarder } = await startRouter();
    const out = await send(port, `CONNECT github.com:443 HTTP/1.1\r\nProxy-Authorization: ${basic("s", SESSION_CRED)}\r\n\r\nCLIENTHELLO`);
    expect(out).toContain("200 Connection Established");
    expect(out).toContain("CLIENTHELLO");
    expect(injector.heads).toHaveLength(1);
    expect(injector.heads[0]).toContain(`Proxy-Authorization: ${basic("router", "router-cred-synthetic")}`);
    expect(injector.heads[0]).not.toContain(SESSION_CRED);
    expect(forwarder.heads).toHaveLength(0);
  });

  it("a non-inject host goes to the forwarder with the forwarder credential, never to iron-proxy", async () => {
    const { port, injector, forwarder } = await startRouter();
    await send(port, `CONNECT api.anthropic.com:443 HTTP/1.1\r\nProxy-Authorization: ${basic("s", SESSION_CRED)}\r\n\r\n`);
    expect(forwarder.heads).toHaveLength(1);
    expect(forwarder.heads[0]).toMatch(/^CONNECT api\.anthropic\.com:443 HTTP\/1\.1/);
    expect(forwarder.heads[0]).toContain(basic("ws-synthetic", "fwd-token-synthetic"));
    expect(injector.heads).toHaveLength(0);
  });

  it("an inject name on port 80 is refused 403; a non-CONNECT is refused 405", async () => {
    const { port, injector, forwarder } = await startRouter();
    expect(await send(port, `CONNECT github.com:80 HTTP/1.1\r\nProxy-Authorization: ${basic("s", SESSION_CRED)}\r\n\r\n`)).toMatch(/^HTTP\/1\.1 403 /);
    expect(await send(port, `GET http://github.com/ HTTP/1.1\r\nProxy-Authorization: ${basic("s", SESSION_CRED)}\r\n\r\n`)).toMatch(/^HTTP\/1\.1 405 /);
    expect(injector.heads).toHaveLength(0);
    expect(forwarder.heads).toHaveLength(0);
  });

  it("logs the branch per CONNECT without any header value", async () => {
    const lines: string[] = [];
    const injector = await stubUpstream();
    const forwarder = await stubUpstream();
    const srv = router.createRouter({
      sessionCredential: SESSION_CRED,
      injector: { host: "127.0.0.1", port: injector.port, credential: basic("router", "router-cred-synthetic") },
      forwarder: { host: "127.0.0.1", port: forwarder.port, credential: basic("ws-synthetic", "fwd-token-synthetic") },
      log: (l: string) => lines.push(l),
      sessionId: "sessA",
    });
    srv.listen(0, "127.0.0.1");
    await once(srv, "listening");
    closers.push(() => srv.close(), () => injector.server.close(), () => forwarder.server.close());
    const port = (srv.address() as net.AddressInfo).port;
    await send(port, `CONNECT github.com:443 HTTP/1.1\r\nProxy-Authorization: ${basic("s", SESSION_CRED)}\r\n\r\n`);
    await send(port, `CONNECT api.anthropic.com:443 HTTP/1.1\r\nProxy-Authorization: ${basic("s", SESSION_CRED)}\r\n\r\n`);
    await send(port, "CONNECT github.com:443 HTTP/1.1\r\n\r\n");
    const joined = lines.join("\n");
    expect(joined).toMatch(/SOLEUR_EGRESS_ROUTE session=sessA branch=injector host=github\.com port=443/);
    expect(joined).toMatch(/SOLEUR_EGRESS_ROUTE session=sessA branch=forwarder host=api\.anthropic\.com port=443/);
    expect(joined).toMatch(/SOLEUR_EGRESS_ROUTE session=sessA branch=refused status=407/);
    for (const secret of [SESSION_CRED, "router-cred-synthetic", "fwd-token-synthetic", Buffer.from(`s:${SESSION_CRED}`).toString("base64")]) {
      expect(joined).not.toContain(secret);
    }
  });

  it("closes a connection whose head exceeds the cap without contacting an upstream", async () => {
    const { port, injector, forwarder } = await startRouter();
    const out = await send(port, "CONNECT github.com:443 HTTP/1.1\r\nX: " + "a".repeat(router.HEAD_CAP + 10));
    expect(out).toMatch(/^(HTTP\/1\.1 431 [\s\S]*)?$/);
    expect(injector.heads).toHaveLength(0);
    expect(forwarder.heads).toHaveLength(0);
  });
});
