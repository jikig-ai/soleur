import { createServer, request as httpRequest, type Server } from "node:http";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { setupWebSocket } from "../server/ws-handler";

/**
 * The custom server owns the HTTP `upgrade` event, and Node dispatches that event to
 * EVERY registered listener. Before #7591 this handler destroyed any upgrade whose path
 * was not `/ws` -- including Next's dev HMR socket, which next 16 serves at
 * `/_next/hmr`. Next's dev client waits on that handshake, so the page rendered
 * server-side and then sat inert: a checkbox toggled in the DOM while no React handler
 * ran. That was the whole of #7591's 72-failure e2e surface, and it reproduced
 * byte-identically under Turbopack and webpack -- which is why the bundler was a red
 * herring and this delegation is the actual fix.
 *
 * Two properties have to hold together, which is why both are asserted here: Next's
 * upgrades must reach Next, and everything else must still be destroyed. A fix that
 * delegated indiscriminately would turn a deny-by-default upgrade path into an
 * allow-by-default one.
 */
describe("websocket upgrade routing", () => {
  let server: Server;
  let port: number;

  beforeAll(async () => {
    server = createServer();
    // Ours must be registered FIRST, because that is the real order: next attaches its
    // listener lazily inside NextCustomServer.setupWebSocketHandler, on the first request
    // the custom server handles, whereas setupWebSocket runs at boot.
    setupWebSocket(server, true);
    // A stand-in for next's own upgrade listener, registered exactly the way next does it
    // (customServer.on("upgrade", ...)). Node dispatches "upgrade" to EVERY listener, so
    // this one runs whether or not ours destroyed the socket first -- which is precisely
    // why declining rather than destroying is what lets next answer.
    server.on("upgrade", (_req, socket) => {
      if (!socket.destroyed) socket.end("HTTP/1.1 101 Switching Protocols\r\n\r\n");
    });
    await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    port = (server.address() as { port: number }).port;
  });

  afterAll(() => {
    server.close();
  });

  const upgrade = (path: string) =>
    new Promise<"reached-next" | "destroyed" | "unreachable">((resolve) => {
      const req = httpRequest({
        host: "127.0.0.1",
        port,
        path,
        headers: {
          Connection: "Upgrade",
          Upgrade: "websocket",
          "Sec-WebSocket-Key": "dGhlIHNhbXBsZSBub25jZQ==",
          "Sec-WebSocket-Version": "13",
        },
      });
      req.on("upgrade", () => resolve("reached-next"));
      req.on("response", () => resolve("reached-next"));
      // ECONNREFUSED is NOT a deny verdict. Without this split, every deny assertion is
      // satisfied by any failure to reach the SUT at all -- measured: pointing the client
      // at a closed port left the deny cases passing.
      req.on("error", (e: NodeJS.ErrnoException) =>
        resolve(e.code === "ECONNREFUSED" ? "unreachable" : "destroyed"),
      );
      req.end();
    });

  it("lets next's own listener answer the HMR upgrade instead of destroying it", async () => {
    await expect(upgrade("/_next/hmr?id=abc")).resolves.toBe("reached-next");
  });

  it("still destroys upgrades neither we nor Next own", async () => {
    await expect(upgrade("/evil")).resolves.toBe("destroyed");
  });

  it("does not let a `_next`-prefixed path masquerade as Next's", async () => {
    // `/_nextfoo` must NOT match: the path is compared for EQUALITY, so no prefix or
    // substring form reaches next.
    await expect(upgrade("/_nextfoo")).resolves.toBe("destroyed");
  });

  // `url.parse` does NOT normalise dot segments, so under a prefix test `/_next/../ws` and
  // `/_next/hmr/../../ws` both satisfied `startsWith("/_next/")`. Equality defeats the whole
  // family at once, but the family is what a prefix regression would re-admit, so it is
  // pinned rather than argued.
  it.each([
    ["/_next/../ws", "traversal toward our own socket"],
    ["/_next/hmr/../../ws", "traversal via the HMR path itself"],
    ["/_next/static/chunks/x.js", "a real next asset path next will not upgrade"],
    ["/foo/_next/hmr", "the HMR path as a substring, not a prefix"],
    ["/_next/", "the bare prefix"],
    ["/_NEXT/hmr", "case variation"],
  ])("destroys %s (%s)", async (path) => {
    await expect(upgrade(path)).resolves.toBe("destroyed");
  });
});

/**
 * The production posture is a separate contract and needs its own server, because the
 * flag is fixed at setup. It is not symmetry for its own sake: in production next's
 * upgrade path reaches "If there's no matched output, we don't handle the request as
 * user's custom WS server may be listening on the same path" (router-server.js) and
 * returns WITHOUT closing the socket. If we also decline, nobody closes it, and an
 * unauthenticated client holds a file descriptor per request on any `/_next/` path --
 * bypassing the IP throttle and the pending-connection limit, both of which sit after
 * the early return. So in production we must destroy.
 */
describe("websocket upgrade routing (production posture)", () => {
  let server: Server;
  let port: number;

  beforeAll(async () => {
    server = createServer();
    // NO second argument -- the DEFAULT must be the safe one. Passing `false`
    // explicitly here would leave the default unpinned, and flipping it to `true` is a
    // one-token edit that reopens the leak in production. (Measured: with `false` passed
    // explicitly, that mutation survived the whole suite green.)
    setupWebSocket(server);
    server.on("upgrade", (_req, socket) => {
      if (!socket.destroyed) socket.end("HTTP/1.1 101 Switching Protocols\r\n\r\n");
    });
    await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    port = (server.address() as { port: number }).port;
  });

  afterAll(() => {
    server.close();
  });

  const upgradeProd = (path: string) =>
    new Promise<"reached-next" | "destroyed" | "unreachable">((resolve) => {
      const req = httpRequest({
        host: "127.0.0.1",
        port,
        path,
        headers: {
          Connection: "Upgrade",
          Upgrade: "websocket",
          "Sec-WebSocket-Key": "dGhlIHNhbXBsZSBub25jZQ==",
          "Sec-WebSocket-Version": "13",
        },
      });
      req.on("upgrade", () => resolve("reached-next"));
      req.on("response", () => resolve("reached-next"));
      req.on("error", () => resolve("destroyed"));
      req.end();
    });

  it("destroys `/_next/` upgrades so they cannot leak a socket", async () => {
    await expect(upgradeProd("/_next/hmr?id=abc")).resolves.toBe("destroyed");
  });

  it("still serves our own /ws", async () => {
    await expect(upgradeProd("/ws")).resolves.toBe("reached-next");
  });
});
