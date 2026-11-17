#!/usr/bin/env node
// Egress injector spike (#12517): criterion 6's CONNECT probes (CTO R36). Test path only. Runs in the app container
// as the app uid, outside bwrap, and sends one CONNECT carrying the ROUTER credential to an iron-proxy listener:
//
//   http-listen  <port>   a plain CONNECT to http_listen
//   https-listen <port>   TLS to https_listen (SNI from <sni>, or none when <sni> is "none"), then a CONNECT inside it
//   in-tunnel    <port>   a CONNECT to tunnel_listen (the outer tunnel), TLS to <host> inside it (verified against the
//                         session bundle), then a second CONNECT inside that TLS
//
// Usage: connect-probe.mjs <mode> <port> <router credential file> <ca bundle> [<host>=api.github.com] [<sni>=none]
// The credential is read the way connect-router.mjs reads it (basicFromFile: the file's `user:password`, trimmed,
// as one Basic value) and is never printed. Output: one line
//   CONNECT_PROBE mode=<mode> [outer=<status>] status=<status|none> [error=<code>]
import { readFileSync } from "node:fs";
import net from "node:net";
import tls from "node:tls";

const [mode, portArg, credFile, caFile, host = "api.github.com", sniArg = "none"] = process.argv.slice(2);
const port = Number(portArg);
const auth = "Basic " + Buffer.from(readFileSync(credFile, "utf8").trim(), "utf8").toString("base64");
const connect = `CONNECT ${host}:443 HTTP/1.1\r\nHost: ${host}:443\r\nProxy-Authorization: ${auth}\r\n\r\n`;
const fields = [`mode=${mode}`];
const done = (status, error) => {
  fields.push(`status=${status ?? "none"}`);
  if (error) fields.push(`error=${String(error).replace(/[^A-Za-z0-9_.:-]/g, "_").slice(0, 80)}`);
  process.stdout.write(`CONNECT_PROBE ${fields.join(" ")}\n`);
  process.exit(0);
};
setTimeout(() => done(null, "timeout"), 12000).unref();

/** The status code of the first response head on `sock` (null when it closes first). */
function statusOf(sock) {
  return new Promise((resolve) => {
    let buf = "";
    const onData = (c) => {
      buf += c.toString("latin1");
      const end = buf.indexOf("\r\n\r\n");
      if (end === -1 && buf.length < 16384) return;
      sock.off("data", onData);
      const m = buf.match(/^HTTP\/\d(?:\.\d)? (\d{3})/);
      resolve(m ? m[1] : "unparsed");
    };
    sock.on("data", onData);
    sock.on("error", (e) => resolve(`error:${e.code ?? "unknown"}`));
    sock.on("close", () => resolve(null));
  });
}

async function main() {
  if (mode === "http-listen") {
    const s = net.connect(port, "127.0.0.1", () => s.write(connect));
    return done(await statusOf(s));
  }
  if (mode === "https-listen") {
    // An empty servername sends no SNI extension (the "none" case); iron-proxy's leaf is not verified here.
    const s = tls.connect({ host: "127.0.0.1", port, servername: sniArg === "none" ? "" : sniArg, rejectUnauthorized: false }, () => s.write(connect));
    return done(await statusOf(s));
  }
  if (mode === "in-tunnel") {
    const outer = net.connect(port, "127.0.0.1", () => outer.write(connect));
    const o = await statusOf(outer);
    fields.push(`outer=${o ?? "none"}`);
    if (o !== "200") return done(null, "outer-not-established");
    const inner = tls.connect({ socket: outer, servername: host, ca: readFileSync(caFile) }, () => inner.write(connect));
    inner.on("error", (e) => done(null, e.code ?? "tls-error"));
    return done(await statusOf(inner));
  }
  return done(null, "unknown-mode");
}

main().catch((e) => done(null, e?.code ?? "exception"));
