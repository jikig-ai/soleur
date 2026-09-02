import { createServer, type Server } from "node:http";
import type { Duplex } from "node:stream";
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
describe("websocket upgrade delegation", () => {
  let server: Server;
  let port: number;
  const delegated: string[] = [];

  beforeAll(async () => {
    server = createServer();
    setupWebSocket(server, (req, socket: Duplex) => {
      delegated.push(req.url ?? "");
      socket.destroy(); // stand-in for Next; we assert delegation, not the handshake
    });
    await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    port = (server.address() as { port: number }).port;
  });

  afterAll(() => {
    server.close();
  });

  const upgrade = (path: string) =>
    new Promise<"delegated" | "destroyed">((resolve) => {
      const before = delegated.length;
      const req = require("node:http").request({
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
      const done = () => resolve(delegated.length > before ? "delegated" : "destroyed");
      req.on("upgrade", done);
      req.on("response", done);
      req.on("error", done);
      req.end();
    });

  it("delegates Next's HMR upgrade instead of destroying it", async () => {
    await expect(upgrade("/_next/hmr?id=abc")).resolves.toBe("delegated");
  });

  it("still destroys upgrades neither we nor Next own", async () => {
    await expect(upgrade("/evil")).resolves.toBe("destroyed");
  });

  it("does not let a `_next`-prefixed path masquerade as Next's", async () => {
    // `/_nextfoo` must NOT match: the guard tests `/_next/`, trailing slash included.
    await expect(upgrade("/_nextfoo")).resolves.toBe("destroyed");
  });
});
