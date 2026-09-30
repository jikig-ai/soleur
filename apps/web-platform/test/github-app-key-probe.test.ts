import { spawnSync } from "node:child_process";
import { createPublicKey, createVerify, generateKeyPairSync } from "node:crypto";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

// #8609 plan §3.3 — the canary/boot GitHub App key probe. Keys are generated here, never
// committed (cq-test-fixtures-synthesized-only); no test reaches the network.
import {
  buildAppJwt,
  classifyResponse,
  EXPECTED_SLUG,
  GITHUB_APP_URL,
  normalizeAppPrivateKey as probeNormalize,
  probe,
  PROBE_TIMEOUT_MS,
  runCli,
} from "../scripts/github-app-key-probe.mjs";
import { normalizeAppPrivateKey as serverNormalize } from "../server/github/app-private-key";

const MJS_PATH = fileURLToPath(new URL("../scripts/github-app-key-probe.mjs", import.meta.url));
const APP_ID = "4242";
const { privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
const PKCS8 = privateKey.export({ type: "pkcs8", format: "pem" }).toString();
const PKCS1 = privateKey.export({ type: "pkcs1", format: "pem" }).toString();
// The Doppler docker-format shape measured in plan §0.2: one line, literal `\n` separators.
const ESCAPED = PKCS1.trimEnd().replace(/\n/g, "\\n");

const decode = (seg: string) => JSON.parse(Buffer.from(seg, "base64url").toString("utf8"));
const hdrs = (h: Record<string, string> = {}) => new Headers(h);
const okBody = { slug: EXPECTED_SLUG, id: Number(APP_ID) };

function stubFetch(status: number, body: unknown, headers: Record<string, string> = {}) {
  const calls: { url: string; init: RequestInit }[] = [];
  const fetchImpl = async (url: string, init: RequestInit) => {
    calls.push({ url, init });
    return new Response(typeof body === "string" ? body : JSON.stringify(body), { status, headers });
  };
  return { calls, fetchImpl };
}

describe("normalizeAppPrivateKey — parity with server/github/app-private-key.ts", () => {
  for (const [label, raw] of [
    ["escaped-\\n PKCS#1 (Doppler docker format)", ESCAPED],
    ["LF PKCS#1", PKCS1],
    ["CRLF PKCS#1", PKCS1.replace(/\n/g, "\r\n")],
    ["LF PKCS#8", PKCS8],
    ["escaped-\\n PKCS#8", PKCS8.trimEnd().replace(/\n/g, "\\n")],
  ] as const) {
    it(`${label}: byte-identical output`, () => {
      expect(probeNormalize(raw)).toBe(serverNormalize(raw));
    });
  }

  it("both reject the same garbage", () => {
    expect(() => serverNormalize("not a key")).toThrow();
    expect(() => probeNormalize("not a key")).toThrow();
  });
});

describe("buildAppJwt — RS256 App JWT contract", () => {
  const nowSec = 1_900_000_000;
  const jwt = buildAppJwt({ appId: APP_ID, privateKeyPem: probeNormalize(ESCAPED), nowSec });
  const [h, p, s] = jwt.split(".");

  it("header is RS256/JWT, claims are iat=now-60, exp=now+300, iss=String(appId)", () => {
    expect(decode(h)).toEqual({ alg: "RS256", typ: "JWT" });
    expect(decode(p)).toEqual({ iat: nowSec - 60, exp: nowSec + 300, iss: APP_ID });
    expect(typeof decode(p).iss).toBe("string");
  });

  it("is unpadded base64url", () => {
    expect(jwt).toMatch(/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/);
  });

  it("signature verifies against the public half", () => {
    const ok = createVerify("RSA-SHA256")
      .update(`${h}.${p}`)
      .verify(createPublicKey(privateKey), Buffer.from(s, "base64url"));
    expect(ok).toBe(true);
  });
});

describe("classifyResponse — verdict rules", () => {
  const c = (status: number, body: unknown = null, h: Record<string, string> = {}) =>
    classifyResponse({ status, headers: hdrs(h), body, appId: APP_ID });

  it("200 with slug soleur-ai and the configured id ⇒ ok", () => expect(c(200, okBody)).toBe("ok"));
  it("200 with another App's slug ⇒ rejected", () => expect(c(200, { ...okBody, slug: "other-app" })).toBe("rejected"));
  it("200 with another App's id ⇒ rejected", () => expect(c(200, { ...okBody, id: 1 })).toBe("rejected"));
  it("200 with no parseable body ⇒ rejected", () => expect(c(200, null)).toBe("rejected"));
  it("401 ⇒ rejected", () => expect(c(401)).toBe("rejected"));
  it("404 ⇒ rejected", () => expect(c(404)).toBe("rejected"));
  it("403 carrying ordinary x-ratelimit-* headers ⇒ rejected", () =>
    expect(c(403, null, { "x-ratelimit-limit": "5000", "x-ratelimit-remaining": "4999" })).toBe("rejected"));
  it("403 with an exhausted quota ⇒ transport", () =>
    expect(c(403, null, { "x-ratelimit-remaining": "0" })).toBe("transport"));
  it("403 with Retry-After (secondary limit) ⇒ transport", () =>
    expect(c(403, null, { "retry-after": "60" })).toBe("transport"));
  it("429 ⇒ transport", () => expect(c(429)).toBe("transport"));
  it("500 / 503 ⇒ transport", () => {
    expect(c(500)).toBe("transport");
    expect(c(503)).toBe("transport");
  });
  it("302 ⇒ rejected (no redirect is followed)", () => expect(c(302)).toBe("rejected"));
});

describe("probe — request shape and failure classes", () => {
  const env = { GITHUB_APP_ID: `${APP_ID}\n`, GITHUB_APP_PRIVATE_KEY: ESCAPED };

  it("GETs the hard-coded /app URL with a Bearer JWT, a 10 s abort signal and manual redirects", async () => {
    const { calls, fetchImpl } = stubFetch(200, okBody);
    expect(await probe({ env, fetchImpl })).toBe("ok");
    expect(calls).toHaveLength(1);
    expect(calls[0].url).toBe(GITHUB_APP_URL);
    expect(GITHUB_APP_URL).toBe("https://api.github.com/app");
    expect(calls[0].init.method).toBe("GET");
    expect(calls[0].init.redirect).toBe("manual");
    expect(calls[0].init.signal).toBeInstanceOf(AbortSignal);
    expect(PROBE_TIMEOUT_MS).toBe(10_000);
    const auth = (calls[0].init.headers as Record<string, string>).authorization;
    expect(auth).toMatch(/^Bearer [A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/);
    // iss is the TRIMMED id, exactly as readAppId() would sign it.
    expect(decode(auth.split(" ")[1].split(".")[1]).iss).toBe(APP_ID);
  });

  it("a fetch that throws (DNS, reset, abort/timeout) ⇒ transport", async () => {
    const fetchImpl = async () => {
      throw new DOMException("The operation was aborted due to timeout", "TimeoutError");
    };
    expect(await probe({ env, fetchImpl })).toBe("transport");
  });

  it("absent key, absent or non-numeric id, or an unparseable key ⇒ rejected without a request", async () => {
    const { calls, fetchImpl } = stubFetch(200, okBody);
    expect(await probe({ env: { GITHUB_APP_ID: APP_ID }, fetchImpl })).toBe("rejected");
    expect(await probe({ env: { GITHUB_APP_PRIVATE_KEY: ESCAPED }, fetchImpl })).toBe("rejected");
    expect(await probe({ env: { GITHUB_APP_ID: "Iv1.abc", GITHUB_APP_PRIVATE_KEY: ESCAPED }, fetchImpl })).toBe("rejected");
    expect(await probe({ env: { GITHUB_APP_ID: APP_ID, GITHUB_APP_PRIVATE_KEY: "EVICTED_SEE_ADR_241" }, fetchImpl })).toBe(
      "rejected",
    );
    expect(calls).toHaveLength(0);
  });
});

describe("runCli — exactly one enum line, nothing else", () => {
  const env = { GITHUB_APP_ID: APP_ID, GITHUB_APP_PRIVATE_KEY: ESCAPED };

  for (const [status, body, headers, verdict, code] of [
    [200, okBody, {}, "ok", 0],
    [401, { message: "A JSON web token could not be decoded" }, {}, "rejected", 1],
    [503, "upstream down", {}, "transport", 0],
  ] as const) {
    it(`HTTP ${status} ⇒ "github_app_key_probe=${verdict}" and exit ${code}`, async () => {
      const { calls, fetchImpl } = stubFetch(status, body, headers);
      let out = "";
      const rc = await runCli({ env, fetchImpl, write: (s: string) => (out += s) });
      expect(out).toBe(`github_app_key_probe=${verdict}\n`);
      expect(rc).toBe(code);
      const jwt = (calls[0].init.headers as Record<string, string>).authorization.split(" ")[1];
      expect(out).not.toContain(jwt.split(".")[2]);
    });
  }

  it("the real CLI with no key prints only the rejected line (no network needed)", () => {
    const r = spawnSync(process.execPath, [MJS_PATH], {
      env: { PATH: process.env.PATH ?? "" },
      encoding: "utf8",
      timeout: 15_000,
    });
    expect(r.stdout).toBe("github_app_key_probe=rejected\n");
    expect(r.stderr).toBe("");
    expect(r.status).toBe(1);
  });
});
