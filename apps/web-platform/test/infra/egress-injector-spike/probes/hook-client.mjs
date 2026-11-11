#!/usr/bin/env node
// Egress injector spike (#12517): criterion 5's hook-channel probe. Test path only. Runs in the app container,
// outside bwrap. Presents a client certificate to a session's hook socket over mutual TLS (R25) and sends one
// TransformRequest for an allowlisted read, the way iron-proxy would.
//
//   hook-client.mjs <socket> <client cert> <client key> <hook server root> <host> <path>
// Prints one line: `HOOK_CLIENT action=<CONTINUE|REJECT|UNKNOWN> status=<code> reason=<reason>` or
// `HOOK_CLIENT error=<code>` when the channel itself refused (TLS or transport). Never prints a body or a key.
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";

const require = createRequire("/app/package.json");
const grpc = require("@grpc/grpc-js");
const protoLoader = require("@grpc/proto-loader");
const [socket, cert, key, root, host, path] = process.argv.slice(2);

const def = protoLoader.loadSync("/app/test/infra/egress-injector-spike/transform.proto", { keepCase: true, longs: String, enums: Number, defaults: true, oneofs: true });
const Svc = grpc.loadPackageDefinition(def).transform.v1.TransformService;
const creds = grpc.credentials.createSsl(readFileSync(root), readFileSync(key), readFileSync(cert));
const client = new Svc(`unix://${socket}`, creds, { "grpc.ssl_target_name_override": "localhost", "grpc.default_authority": "localhost" });
const deadline = new Date(Date.now() + 8000);
// The request carries the tunnel context and the SNI iron-proxy gives a TLS-terminated tunnelled request (CTO R28,
// R37), so a refusal measures the channel's client identity, not the hook's tunnel or TLS guard (run 42811970877
// without the tunnel context, and run 42864371897 without the SNI: B's own control was refused both times).
const context = { tunnel: { target: `${host}:443` }, sni: host };
client.TransformRequest({ context, request: { method: "GET", url: path, host, headers: {}, body: Buffer.alloc(0) } }, { deadline }, (err, res) => {
  if (err) {
    console.log(`HOOK_CLIENT error=${grpc.status[err.code] ?? err.code}`);
    process.exit(0);
  }
  const action = { 1: "CONTINUE", 2: "REJECT" }[res?.action] ?? "UNKNOWN";
  const reason = res?.annotations?.soleur_reason ?? "";
  console.log(`HOOK_CLIENT action=${action} status=${res?.response?.status_code ?? ""} reason=${reason}`);
  process.exit(0);
});
