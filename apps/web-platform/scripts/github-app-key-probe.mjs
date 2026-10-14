#!/usr/bin/env node
// GitHub App key acceptance probe (#8609). Contract: plan
// 2026-09-30-security-evict-runtime-app-key-from-prd-reachability §3.3.
//
// Run inside a container of the image under test — the deploy canary (ci-deploy.sh) and the
// booted web container (soleur-github-app-key-check, soleur-host-bootstrap.sh) — as
// `node /app/scripts/github-app-key-probe.mjs`. Reads GITHUB_APP_ID and GITHUB_APP_PRIVATE_KEY
// from its OWN environment (never passed with `docker exec -e`), signs an App JWT and calls
// GET https://api.github.com/app.
//
// OUTPUT IS EXACTLY ONE LINE from a fixed enum: `github_app_key_probe=ok|transport`, or
// `github_app_key_probe=rejected reason=<REJECT_REASONS>`. Never the JWT, a header, the body or an
// error message — both callers forward stdout to sinks that leave the host. The reason separates
// the hypotheses a bare `rejected` merged (a bad GITHUB_APP_ID, a PEM the env-file merge mangled,
// a key GitHub refuses, an unknown App, another App's key); both host parsers carry the same enum. Standalone on purpose (node:crypto + fetch, no app imports) so the probe
// cannot be broken by the app bundle it is judging.
import { createPrivateKey, createSign } from "node:crypto";
import { pathToFileURL } from "node:url";

export const GITHUB_APP_URL = "https://api.github.com/app";
export const EXPECTED_SLUG = "soleur-ai";
export const PROBE_TIMEOUT_MS = 10_000;
export const VERDICTS = Object.freeze(["ok", "rejected", "transport"]);
export const REJECT_REASONS = Object.freeze([
  "no_app_id",
  "unparseable_key",
  "http_401",
  "http_404",
  "wrong_app",
  "http_other",
]);

// Same steps as normalizeAppPrivateKey() in server/github/app-private-key.ts (the escaped-`\n`
// expansion Doppler's docker format needs, then Node's format-tolerant re-export). Not imported:
// this file ships without the TypeScript build. test/github-app-key-probe.test.ts pins the parity.
export function normalizeAppPrivateKey(raw) {
  const pem = raw.replace(/\\n/g, "\n");
  return createPrivateKey(pem).export({ type: "pkcs8", format: "pem" }).toString();
}

// RS256 App JWT. iat is backdated 60 s and exp is now+300 s — never GitHub's 600 s ceiling, which
// 401s intermittently under clock skew. base64url is Node's unpadded variant.
export function buildAppJwt({ appId, privateKeyPem, nowSec }) {
  const enc = (v) => Buffer.from(v).toString("base64url");
  const header = enc(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payload = enc(JSON.stringify({ iat: nowSec - 60, exp: nowSec + 300, iss: String(appId) }));
  const signingInput = `${header}.${payload}`;
  const signature = createSign("RSA-SHA256").update(signingInput).sign(privateKeyPem);
  return `${signingInput}.${enc(signature)}`;
}

// A 403 is a rate limit (not a rejected key) only when GitHub says so: a Retry-After header or an
// exhausted primary quota. GitHub attaches x-ratelimit-* to most API responses, so their mere
// presence is not the signal.
function isRateLimited(headers) {
  return headers.get("retry-after") !== null || headers.get("x-ratelimit-remaining") === "0";
}

export function classifyResponse({ status, headers, body, appId }) {
  if (status === 200) {
    return body !== null && typeof body === "object" && body.slug === EXPECTED_SLUG && String(body.id) === appId
      ? "ok"
      : "rejected";
  }
  if (status === 429 || status >= 500) return "transport";
  if (status === 403 && isRateLimited(headers)) return "transport";
  return "rejected";
}

// The closed sub-reason of a `rejected` HTTP verdict: 200 (a body that is not this App), 401, 404,
// or any other status classifyResponse rejects (403 without a rate-limit signal, 3xx, 4xx).
export function rejectReason(status) {
  if (status === 200) return "wrong_app";
  if (status === 401) return "http_401";
  if (status === 404) return "http_404";
  return "http_other";
}

const rejected = (reason) => ({ verdict: "rejected", reason });

// probeResult → { verdict, reason }: reason is one of REJECT_REASONS when verdict is `rejected`,
// else null.
export async function probeResult({ env = process.env, fetchImpl = globalThis.fetch, now = Date.now } = {}) {
  // Trimmed exactly as readAppId() does; anything non-numeric can never be accepted by GitHub.
  const appId = String(env.GITHUB_APP_ID ?? "").trim();
  const raw = env.GITHUB_APP_PRIVATE_KEY ?? "";
  if (!/^[0-9]+$/.test(appId)) return rejected("no_app_id");
  if (raw === "") return rejected("unparseable_key");
  let jwt;
  try {
    jwt = buildAppJwt({ appId, privateKeyPem: normalizeAppPrivateKey(raw), nowSec: Math.floor(now() / 1000) });
  } catch {
    return rejected("unparseable_key");
  }
  let res;
  try {
    res = await fetchImpl(GITHUB_APP_URL, {
      method: "GET",
      redirect: "manual",
      headers: {
        accept: "application/vnd.github+json",
        authorization: `Bearer ${jwt}`,
        "user-agent": "soleur-github-app-key-probe",
        "x-github-api-version": "2022-11-28",
      },
      signal: AbortSignal.timeout(PROBE_TIMEOUT_MS),
    });
  } catch {
    return { verdict: "transport", reason: null };
  }
  let body = null;
  if (res.status === 200) {
    let text;
    try {
      text = await res.text();
    } catch {
      return { verdict: "transport", reason: null }; // the connection died mid-body
    }
    try {
      body = JSON.parse(text);
    } catch {
      body = null; // a 200 that is not JSON (a proxy's HTML page) is not this App: rejected
    }
  }
  const verdict = classifyResponse({ status: res.status, headers: res.headers, body, appId });
  return verdict === "rejected" ? rejected(rejectReason(res.status)) : { verdict, reason: null };
}

export async function probe(opts = {}) {
  return (await probeResult(opts)).verdict;
}

export async function runCli({ env = process.env, fetchImpl = globalThis.fetch, write = (s) => process.stdout.write(s) } = {}) {
  const { verdict, reason } = await probeResult({ env, fetchImpl });
  write(verdict === "rejected" ? `github_app_key_probe=rejected reason=${reason}\n` : `github_app_key_probe=${verdict}\n`);
  return verdict === "rejected" ? 1 : 0;
}

const invokedPath = process.argv[1] ? pathToFileURL(process.argv[1]).href : "";
if (invokedPath === import.meta.url) {
  runCli().then(
    (code) => {
      process.exitCode = code;
    },
    () => {
      // No verdict line: the caller classifies a non-zero exit without one as rejected.
      process.exitCode = 70;
    },
  );
}
