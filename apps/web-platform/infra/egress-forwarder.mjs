#!/usr/bin/env node
// Per-dispatch egress forwarder (#9534). Spawned by the dispatch layer for an
// entitled session; bound to the session's lifetime.
//
// SRT only speaks `httpProxyPort` = localhost:<port>. This shim listens on
// 127.0.0.1:<bind-0 port>, requires the per-session token inbound, strips
// whatever Proxy-Authorization the client sent, injects
// `workspaceId:sessionToken` outbound, and pipes the tunnel to the gateway.
// The session token is also the gateway credential — the app-side file write
// to the shared token dir is what makes it valid.
//
// Env (all set by the dispatcher, never ambient):
//   EGRESS_GW_HOST        gateway IP on soleur-egress0 (default 172.31.100.2)
//   EGRESS_GW_PORT        gateway port (default 8443)
//   EGRESS_SESSION_TOKEN  per-session token (required)
//   EGRESS_WORKSPACE_ID   attribution username (required)
// Prints the bound port on stdout (the dispatcher reads it back).
import net from "node:net";

const GW_HOST = process.env.EGRESS_GW_HOST ?? "172.31.100.2";
const GW_PORT = Number(process.env.EGRESS_GW_PORT ?? 8443);
const TOKEN = process.env.EGRESS_SESSION_TOKEN;
const WORKSPACE = process.env.EGRESS_WORKSPACE_ID;
if (!TOKEN || !WORKSPACE) {
  console.error("egress-forwarder: EGRESS_SESSION_TOKEN and EGRESS_WORKSPACE_ID required");
  process.exit(1);
}

const INJECT = `Proxy-Authorization: Basic ${Buffer.from(`${WORKSPACE}:${TOKEN}`).toString("base64")}\r\n`;
const HEADER_END = Buffer.from("\r\n\r\n");

const server = net.createServer((client) => {
  let buf = Buffer.alloc(0);
  const onData = (chunk) => {
    buf = Buffer.concat([buf, chunk]);
    const end = buf.indexOf(HEADER_END);
    if (end === -1) {
      if (buf.length > 16 * 1024) { client.destroy(); }
      return;
    }
    client.off("data", onData);
    const head = buf.subarray(0, end).toString("latin1");
    const rest = buf.subarray(end);

    // Inbound auth: the per-session token must be the proxy password.
    const authLine = head.match(/^proxy-authorization:[ \t]*basic[ \t]+(\S+)/im);
    const presented = authLine ? Buffer.from(authLine[1], "base64").toString("latin1") : "";
    if (!presented.includes(`:${TOKEN}`)) {
      client.end("HTTP/1.1 407 Proxy Authentication Required\r\nProxy-Authenticate: Basic realm=soleur\r\nContent-Length: 0\r\n\r\n");
      return;
    }

    // Strip client Proxy-Authorization lines, inject ours.
    const rewritten = head
      .split("\r\n")
      .filter((l) => !/^proxy-authorization:/i.test(l))
      .join("\r\n");

    const gw = net.connect(GW_PORT, GW_HOST, () => {
      gw.write(rewritten + "\r\n" + INJECT + "\r\n" + rest.toString("latin1"));
      client.pipe(gw);
      gw.pipe(client);
    });
    gw.on("error", () => client.destroy());
    client.on("error", () => gw.destroy());
  };
  client.on("data", onData);
});

// ppid watchdog: the dispatcher is our parent; if it dies, so do we.
setInterval(() => {
  try { process.kill(process.ppid, 0); } catch { process.exit(0); }
}, 5000).unref();

server.listen(0, "127.0.0.1", () => {
  const { port } = server.address();
  console.log(`egress-forwarder-listening ${port}`);
});
