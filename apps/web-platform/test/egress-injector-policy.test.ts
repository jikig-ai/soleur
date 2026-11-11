// #12517 — hermetic tests for the egress injector spike's pure decision code (plan
// knowledge-base/project/plans/archive/20261110-211546-2026-11-09-feat-agent-runtime-sandbox-eval-injector-first-plan.md, Phase 1).
//
// Three modules under test, all on the test path (no production code imports them):
//   policy.mjs        the per-host classifier and the action-hash recipe (Guard 2's chokepoint)
//   approval-hook.mjs decide(): the hook's decision order over a fake RPC client (every reason code)
//   verdict.mjs       the outcome floor (Guard 3): GO / NO-GO / INCONCLUSIVE from the arms' records
//
// Guard 2 rows covered here: 1, 3, 4, 5, 7, 9 (and 10, the must-PASS). Guard 3 rows: 1, 2, 3, 5, 6.
// Every fixture is synthesized in this file (cq-test-fixtures-synthesized-only): no real token, repository or user.

import { createHash, randomBytes } from "node:crypto";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { gzipSync } from "node:zlib";
import { describe, expect, it } from "vitest";
import { parse as parseYaml } from "yaml";

import * as policyMod from "./infra/egress-injector-spike/policy.mjs";
import * as hookMod from "./infra/egress-injector-spike/approval-hook.mjs";
import * as verdictMod from "./infra/egress-injector-spike/verdict.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const SPIKE = join(HERE, "infra", "egress-injector-spike");
// URL-path traversal fixtures are built, not written: a literal `..` run reads as this suite escaping the app
// to test/repo-wide-containment.test.ts. They are request paths for the classifier, never filesystem paths.
const UP2 = "../".repeat(2);
const BASE_POLICY = policyMod.compilePolicy(parseYaml(readFileSync(join(SPIKE, "policy.yaml"), "utf8")));
const OVERLAY_POLICY = policyMod.compilePolicy(
  policyMod.mergePolicy(
    parseYaml(readFileSync(join(SPIKE, "policy.yaml"), "utf8")),
    parseYaml(readFileSync(join(SPIKE, "policy.add-verb.yaml"), "utf8")),
  ),
);
const KEY = randomBytes(32);
const REPOS = ["acme-synth/widget"];
const OID_A = "a".repeat(40);
const OID_B = "b".repeat(40);
const OID_C = "c".repeat(40);

type Req = {
  method: string;
  host: string;
  path: string;
  query?: string;
  // A header may repeat (iron-proxy forwards every value; policy.mjs lowerHeaders accepts both shapes).
  headers?: Record<string, string | string[]>;
  body?: Buffer;
};

// Every request iron-proxy forwards from a tunnel carries that tunnel's CONNECT target (measured 2026-11-10) and,
// once TLS is terminated, the SNI it terminated (iron-proxy v0.56.0 proxy.go); the defaults here are the ones the
// router path produces, `<host>:443` and `<host>`. Rows that test the R28, R36 and R37 guards override them.
function req(r: Req & { tunnelTarget?: string | null; sni?: string | null }) {
  const h = String(r.host).toLowerCase();
  // REST writes must carry a JSON body (review 2026-11-10); the default here is what gh and the REST clients send.
  return { query: "", body: Buffer.alloc(0), tunnelTarget: `${h}:443`, sni: h, ...r, headers: { "content-type": "application/json", ...(r.headers ?? {}) } };
}

function pkt(line: string): string {
  const len = (Buffer.byteLength(line, "latin1") + 4).toString(16).padStart(4, "0");
  return len + line;
}

function receivePack(updates: Array<[string, string, string]>, opts: { shallow?: string } = {}): Buffer {
  const lines: string[] = [];
  if (opts.shallow) lines.push(pkt(`shallow ${opts.shallow}\n`));
  updates.forEach(([o, n, ref], i) => {
    lines.push(pkt(i === 0 ? `${o} ${n} ${ref}\0report-status side-band-64k\n` : `${o} ${n} ${ref}\n`));
  });
  lines.push("0000");
  return Buffer.concat([Buffer.from(lines.join(""), "latin1"), Buffer.from("PACK-synthetic-bytes")]);
}

function gql(body: unknown): Buffer {
  return Buffer.from(JSON.stringify(body));
}

function classify(r: Req, policy = BASE_POLICY, repositories = REPOS) {
  return policyMod.classify(policyMod.normalizeRequest(req(r)), policy, { repositories });
}

function hashOf(r: Req, policy = BASE_POLICY) {
  const c = classify(r, policy);
  expect(c.verdict).toBe("write");
  return policyMod.actionHash(c.canonical, KEY);
}

describe("policy.mjs — module shape", () => {
  it("imports nothing from server code or the network (portable into server/ unchanged)", () => {
    const src = readFileSync(join(SPIKE, "policy.mjs"), "utf8");
    const specs = [...src.matchAll(/^\s*import\s[^;]*?from\s+["']([^"']+)["']/gm)].map((m) => m[1]);
    expect(specs.length).toBeGreaterThan(0);
    for (const s of specs) expect(["node:crypto", "node:zlib", "graphql"]).toContain(s);
  });

  it("actionHash requires the HMAC key (no default)", () => {
    const c = classify({ method: "POST", host: "github.com", path: "/acme-synth/widget/git-receive-pack", body: receivePack([[OID_A, OID_B, "refs/heads/main"]]) });
    expect(() => policyMod.actionHash(c.canonical, undefined)).toThrow();
    expect(() => policyMod.actionHash(c.canonical, Buffer.alloc(0))).toThrow();
    expect(policyMod.actionHash(c.canonical, KEY)).toMatch(/^[0-9a-f]{64}$/);
  });

  it("the base policy declares exactly the four inject hosts", () => {
    expect([...BASE_POLICY.injectHosts].sort()).toEqual(["api.github.com", "codeload.github.com", "github.com", "uploads.github.com"]);
  });
});

describe("policy.mjs — git smart HTTP", () => {
  it("upload-pack advertisement and POST git-upload-pack are reads on the allowlist", () => {
    expect(classify({ method: "GET", host: "github.com", path: "/acme-synth/widget.git/info/refs", query: "service=git-upload-pack" }).verdict).toBe("read");
    expect(classify({ method: "POST", host: "github.com", path: "/acme-synth/widget.git/git-upload-pack", body: Buffer.from("0000") }).verdict).toBe("read");
  });

  it("the receive-pack advertisement GET is a push-advert (vends without a row, CTO R1)", () => {
    const c = classify({ method: "GET", host: "github.com", path: "/acme-synth/widget/info/refs", query: "service=git-receive-pack" });
    expect(c.verdict).toBe("push-advert");
  });

  it("Guard 2 row 1: POST git-receive-pack is a write, never a read", () => {
    const c = classify({ method: "POST", host: "github.com", path: "/acme-synth/widget.git/git-receive-pack", body: receivePack([[OID_A, OID_B, "refs/heads/main"]]) });
    expect(c.verdict).toBe("write");
    expect(c.rule).toBe("git-push");
    expect(c.canonical).toMatchObject({ kind: "git-push", host: "github.com", repository: "acme-synth/widget" });
    expect(c.canonical.updates).toEqual([{ old: OID_A, new: OID_B, ref: "refs/heads/main" }]);
  });

  it("parses two ref updates and skips shallow lines", () => {
    const c = classify({
      method: "POST", host: "github.com", path: "/acme-synth/widget/git-receive-pack",
      body: receivePack([[OID_A, OID_B, "refs/heads/main"], [OID_C, OID_A, "refs/heads/dev"]], { shallow: OID_C }),
    });
    expect(c.verdict).toBe("write");
    expect(c.canonical.updates).toHaveLength(2);
  });

  it("decodes a gzip-encoded receive-pack body (tracer item 3: the hook sees it still encoded)", () => {
    const raw = receivePack([[OID_A, OID_B, "refs/heads/main"]]);
    const plain = classify({ method: "POST", host: "github.com", path: "/acme-synth/widget/git-receive-pack", body: raw });
    const gz = classify({ method: "POST", host: "github.com", path: "/acme-synth/widget/git-receive-pack", body: gzipSync(raw), headers: { "content-encoding": "gzip" } });
    expect(gz.verdict).toBe("write");
    expect(policyMod.actionHash(gz.canonical, KEY)).toBe(policyMod.actionHash(plain.canonical, KEY));
  });

  it("a receive-pack body with no ref update, a bad pkt-line or an unknown encoding is unparseable", () => {
    // A body of exactly "0000" is git's large-push probe and vends (CTO R39, its own row below); a flush followed by
    // anything is still a body with no ref update.
    for (const body of [Buffer.from("00000000"), Buffer.from("0000PACK"), Buffer.from("zzzz"), Buffer.from("0010short")]) {
      expect(classify({ method: "POST", host: "github.com", path: "/acme-synth/widget/git-receive-pack", body })).toMatchObject({ verdict: "refused", subreason: "unparseable" });
    }
    expect(classify({ method: "POST", host: "github.com", path: "/acme-synth/widget/git-receive-pack", body: receivePack([[OID_A, OID_B, "refs/heads/main"]]), headers: { "content-encoding": "br" } })).toMatchObject({ verdict: "refused", subreason: "unparseable" });
  });

  it("a push to a repository outside the allowlist is refused with no row", () => {
    const c = classify({ method: "POST", host: "github.com", path: "/other-synth/thing/git-receive-pack", body: receivePack([[OID_A, OID_B, "refs/heads/main"]]) });
    expect(c).toMatchObject({ verdict: "refused", subreason: "write-outside-allowlist" });
  });
});

describe("policy.mjs — REST", () => {
  it("GET and HEAD on an allowlisted repository path are reads", () => {
    expect(classify({ method: "GET", host: "api.github.com", path: "/repos/acme-synth/widget" }).verdict).toBe("read");
    expect(classify({ method: "HEAD", host: "api.github.com", path: "/repos/acme-synth/widget/pulls/3" }).verdict).toBe("read");
    expect(classify({ method: "GET", host: "codeload.github.com", path: "/acme-synth/widget/tar.gz/main" }).verdict).toBe("read");
  });

  it("GET outside the allowlist is refused read-outside-allowlist", () => {
    expect(classify({ method: "GET", host: "api.github.com", path: "/repos/other-synth/thing" })).toMatchObject({ verdict: "refused", subreason: "read-outside-allowlist" });
    expect(classify({ method: "GET", host: "api.github.com", path: "/user" })).toMatchObject({ verdict: "refused", subreason: "read-outside-allowlist" });
  });

  it("a listed REST write is a write with the REST recipe", () => {
    const c = classify({ method: "POST", host: "api.github.com", path: "/repos/acme-synth/widget/pulls", body: Buffer.from('{"title":"t"}') });
    expect(c).toMatchObject({ verdict: "write", rule: "rest-create-pull" });
    expect(c.canonical).toMatchObject({ kind: "rest", method: "POST", host: "api.github.com", repository: "acme-synth/widget" });
    expect(c.canonical.body_sha256).toBe(createHash("sha256").update('{"title":"t"}').digest("hex"));
  });

  it("Guard 2 row 7: an unlisted REST write is not-allowlisted, never 'needs a row' (CTO R13)", () => {
    const c = classify({ method: "POST", host: "api.github.com", path: "/repos/acme-synth/widget/issues", body: Buffer.from("{}") });
    expect(c).toMatchObject({ verdict: "refused", subreason: "unlisted-write" });
    for (const method of ["PUT", "PATCH", "DELETE"]) {
      expect(classify({ method, host: "api.github.com", path: "/repos/acme-synth/widget" })).toMatchObject({ verdict: "refused", subreason: "unlisted-write" });
    }
  });

  it("criterion 7: the overlay moves create-issue from refused to gated with policy data only", () => {
    const r = { method: "POST", host: "api.github.com", path: "/repos/acme-synth/widget/issues", body: Buffer.from('{"title":"x"}') };
    expect(classify(r).verdict).toBe("refused");
    expect(classify(r, OVERLAY_POLICY)).toMatchObject({ verdict: "write", rule: "rest-create-issue" });
  });
});

describe("policy.mjs — GraphQL (classified with the graphql package, CTO R23)", () => {
  const path = "/graphql";
  const host = "api.github.com";

  it("a single query is a read; Guard 2 row 10 must-PASS: a query with variables and an operationName", () => {
    expect(classify({ method: "POST", host, path, body: gql({ query: "{ viewer { login } }" }) }).verdict).toBe("read");
    expect(classify({ method: "POST", host, path, body: gql({ query: "query Repo($o: String!) { repository(owner: $o, name: \"w\") { id } }", variables: { o: "acme-synth" }, operationName: "Repo" }) }).verdict).toBe("read");
  });

  it("a single listed mutation is a write with the GraphQL recipe", () => {
    const c = classify({ method: "POST", host, path, body: gql({ query: "mutation M { addComment(input: {subjectId: \"x\", body: \"y\"}) { clientMutationId } }" }) });
    expect(c).toMatchObject({ verdict: "write", rule: "graphql-mutation" });
    expect(c.canonical).toMatchObject({ kind: "graphql", host, operation_name: "M", operation_type: "mutation" });
  });

  it("Guard 2 row 3: query first, mutation second, selected by operationName, is a write", () => {
    const doc = "query Q { viewer { login } } mutation M { addComment(input: {subjectId: \"x\", body: \"y\"}) { clientMutationId } }";
    expect(classify({ method: "POST", host, path, body: gql({ query: doc, operationName: "M" }) }).verdict).toBe("write");
    expect(classify({ method: "POST", host, path, body: gql({ query: doc, operationName: "Q" }) }).verdict).toBe("read");
  });

  it("multi-operation without operationName, unknown operationName, batched array and unparseable bodies are refused", () => {
    const doc = "query Q { viewer { login } } mutation M { addComment(input: {}) { clientMutationId } }";
    expect(classify({ method: "POST", host, path, body: gql({ query: doc }) })).toMatchObject({ verdict: "refused", subreason: "unparseable" });
    expect(classify({ method: "POST", host, path, body: gql({ query: doc, operationName: "Nope" }) })).toMatchObject({ verdict: "refused", subreason: "unparseable" });
    expect(classify({ method: "POST", host, path, body: gql([{ query: "{ viewer { login } }" }]) })).toMatchObject({ verdict: "refused", subreason: "batched" });
    expect(classify({ method: "POST", host, path, body: Buffer.from("{not json") })).toMatchObject({ verdict: "refused", subreason: "unparseable" });
    expect(classify({ method: "POST", host, path, body: gql({ query: "mutation { " }) })).toMatchObject({ verdict: "refused", subreason: "unparseable" });
  });

  it("an unlisted mutation field, a mixed listed/unlisted mutation, a top-level fragment and a subscription are refused", () => {
    expect(classify({ method: "POST", host, path, body: gql({ query: "mutation { deleteRepository(input: {}) { clientMutationId } }" }) })).toMatchObject({ verdict: "refused", subreason: "unlisted-write" });
    expect(classify({ method: "POST", host, path, body: gql({ query: "mutation { addComment(input: {}) { clientMutationId } deleteRepository(input: {}) { clientMutationId } }" }) })).toMatchObject({ verdict: "refused", subreason: "unlisted-write" });
    expect(classify({ method: "POST", host, path, body: gql({ query: "mutation { ...F } fragment F on Mutation { deleteRepository(input: {}) { clientMutationId } }" }) })).toMatchObject({ verdict: "refused", subreason: "unparseable" });
    expect(classify({ method: "POST", host, path, body: gql({ query: "subscription { x }" }) })).toMatchObject({ verdict: "refused", subreason: "unlisted-write" });
  });

  it("an aliased unlisted mutation is judged by field name, not alias", () => {
    expect(classify({ method: "POST", host, path, body: gql({ query: "mutation { addComment: deleteRepository(input: {}) { clientMutationId } }" }) })).toMatchObject({ verdict: "refused", subreason: "unlisted-write" });
  });
});

describe("policy.mjs — canonical path (normalized or refused before matching and hashing)", () => {
  it("refuses traversal, encoded slashes and dots, double slashes and backslashes", () => {
    for (const p of [
      `/repos/acme-synth/widget/${UP2}other-synth/thing`,
      "/repos/acme-synth/widget/%2e%2e/x",
      "/repos/acme-synth/widget/%2E%2E/x",
      "/repos/acme-synth%2Fwidget",
      "/repos//acme-synth/widget",
      "/repos/acme-synth/widget\\x",
      "/repos/acme-synth/./widget",
    ]) {
      expect(classify({ method: "GET", host: "api.github.com", path: p }), p).toMatchObject({ verdict: "refused", subreason: "unparseable" });
    }
  });

  it("owner/repo case variants and percent-encoded letters resolve to the allowlisted repository", () => {
    expect(classify({ method: "GET", host: "api.github.com", path: "/repos/ACME-Synth/Widget" }).verdict).toBe("read");
    expect(classify({ method: "GET", host: "api.github.com", path: "/repos/acme-synth/%77idget" }).verdict).toBe("read");
  });

  it("host case and a trailing dot are normalized; a Host header that disagrees with the target is refused (Guard 2 row 14)", () => {
    expect(classify({ method: "GET", host: "API.GitHub.com.", path: "/repos/acme-synth/widget" }).verdict).toBe("read");
    expect(classify({ method: "GET", host: "api.github.com", path: "/repos/acme-synth/widget", headers: { host: "api.github.com:443" } }).verdict).toBe("read");
    expect(classify({ method: "GET", host: "api.github.com", path: "/repos/acme-synth/widget", headers: { host: "uploads.github.com" } })).toMatchObject({ verdict: "refused", subreason: "unparseable" });
  });

  it("a host outside the four inject hosts is refused", () => {
    expect(classify({ method: "GET", host: "gist.github.com", path: "/acme-synth/widget" })).toMatchObject({ verdict: "refused", subreason: "unparseable" });
  });
});

describe("policy.mjs — action hash recipe (CTO R6)", () => {
  const push = (path: string, updates: Array<[string, string, string]>) => ({ method: "POST", host: "github.com", path, body: receivePack(updates) });
  const rest = (path: string, body: string) => ({ method: "POST", host: "api.github.com", path, body: Buffer.from(body) });

  // Found 2026-11-10 while generating the results note's canonical_action samples: the REST canonical path kept only
  // the captured segments, so /repos/o/r/pulls and /repos/o/r/issues (the overlay verb) both canonicalised to "/o/r"
  // and, with the same body, shared a hash. A row approved for one verb would then authorize the other.
  it("two listed REST writes with the same body but different paths hash differently (literal segments are hashed)", () => {
    const body = '{"title":"same"}';
    const pull = classify(req(rest("/repos/acme-synth/widget/pulls", body)), OVERLAY_POLICY);
    const issue = classify(req(rest("/repos/acme-synth/widget/issues", body)), OVERLAY_POLICY);
    expect(pull).toMatchObject({ verdict: "write", rule: "rest-create-pull" });
    expect(issue).toMatchObject({ verdict: "write", rule: "rest-create-issue" });
    expect(pull.canonical.path).toBe("/repos/acme-synth/widget/pulls");
    expect(issue.canonical.path).toBe("/repos/acme-synth/widget/issues");
    expect(policyMod.actionHash(pull.canonical, KEY)).not.toBe(policyMod.actionHash(issue.canonical, KEY));
  });

  it("each single hashed-field change produces a different hash", () => {
    const base = hashOf(push("/acme-synth/widget/git-receive-pack", [[OID_A, OID_B, "refs/heads/main"]]));
    expect(hashOf(push("/acme-synth/widget/git-receive-pack", [[OID_C, OID_B, "refs/heads/main"]]))).not.toBe(base);
    expect(hashOf(push("/acme-synth/widget/git-receive-pack", [[OID_A, OID_C, "refs/heads/main"]]))).not.toBe(base);
    expect(hashOf(push("/acme-synth/widget/git-receive-pack", [[OID_A, OID_B, "refs/heads/dev"]]))).not.toBe(base);
    const r1 = hashOf(rest("/repos/acme-synth/widget/pulls", '{"title":"a"}'));
    expect(hashOf(rest("/repos/acme-synth/widget/pulls", '{"title":"b"}'))).not.toBe(r1); // Guard 2 row 4
    expect(hashOf(rest("/repos/acme-synth/widget/issues/1/comments", '{"title":"a"}'))).not.toBe(r1);
    const g1 = hashOf({ method: "POST", host: "api.github.com", path: "/graphql", body: gql({ query: "mutation { addComment(input: {body: \"a\"}) { clientMutationId } }" }) });
    const g2 = hashOf({ method: "POST", host: "api.github.com", path: "/graphql", body: gql({ query: "mutation { addComment(input: {body: \"b\"}) { clientMutationId } }" }) });
    const g3 = hashOf({ method: "POST", host: "api.github.com", path: "/graphql", body: gql({ query: "mutation { addComment(input: {body: $b}) { clientMutationId } }", variables: { b: "a" } }) });
    const g4 = hashOf({ method: "POST", host: "api.github.com", path: "/graphql", body: gql({ query: "mutation { addComment(input: {body: $b}) { clientMutationId } }", variables: { b: "z" } }) });
    expect(new Set([g1, g2, g3, g4]).size).toBe(4);
  });

  it("repository spelling variants hash equal", () => {
    const a = hashOf(push("/acme-synth/widget/git-receive-pack", [[OID_A, OID_B, "refs/heads/main"]]));
    expect(hashOf(push("/ACME-SYNTH/Widget.git/git-receive-pack", [[OID_A, OID_B, "refs/heads/main"]]))).toBe(a);
    expect(hashOf(push("/acme-synth/%77idget.git/git-receive-pack", [[OID_A, OID_B, "refs/heads/main"]]))).toBe(a);
  });

  it("Guard 2 row 5: a fork hashes differently (repository path is always hashed)", () => {
    const repos = ["acme-synth/widget", "fork-synth/widget"];
    const p = (path: string) => policyMod.classify(policyMod.normalizeRequest(req(push(path, [[OID_A, OID_B, "refs/heads/main"]]))), BASE_POLICY, { repositories: repos });
    const a = p("/acme-synth/widget/git-receive-pack");
    const b = p("/fork-synth/widget/git-receive-pack");
    expect(policyMod.actionHash(a.canonical, KEY)).not.toBe(policyMod.actionHash(b.canonical, KEY));
  });

  it("GraphQL whitespace and key-order differences do not change the hash", () => {
    const a = hashOf({ method: "POST", host: "api.github.com", path: "/graphql", body: gql({ query: "mutation{addComment(input:{body:$b}){clientMutationId}}", variables: { b: "a", c: 1 } }) });
    const b = hashOf({ method: "POST", host: "api.github.com", path: "/graphql", body: gql({ query: "mutation {\n  addComment(input: {body: $b}) {\n    clientMutationId\n  }\n}", variables: { c: 1, b: "a" } }) });
    expect(a).toBe(b);
  });

  it("a different HMAC key gives a different hash", () => {
    const c = classify(push("/acme-synth/widget/git-receive-pack", [[OID_A, OID_B, "refs/heads/main"]]));
    expect(policyMod.actionHash(c.canonical, KEY)).not.toBe(policyMod.actionHash(c.canonical, randomBytes(32)));
  });
});

// ---------------------------------------------------------------------------------------------------------------
// approval-hook.mjs decide() over a fake RPC client that mirrors 180_approval_request.sql's contract.
// ---------------------------------------------------------------------------------------------------------------

type Row = { id: string; status: string; expires_at: string; action_sha256: string; conversation_id: string };

function fakeRpc(opts: { now: () => number }) {
  const rows: Row[] = [];
  const calls: string[] = [];
  let throwOnCreate: { code: string; message: string } | null = null;
  let consumeOverride: { consumed: boolean; reason: string } | null = null;
  let n = 0;
  const live = (r: Row) => r.status === "pending" || r.status === "approved";
  const rpc = {
    async create(a: { conversationId: string; hash: string; ttlSeconds: number; toolName: string; canonical: object }) {
      calls.push(`create:${a.toolName}`);
      if (throwOnCreate) throw Object.assign(new Error(throwOnCreate.message), { code: throwOnCreate.code });
      const existing = rows.find((r) => r.conversation_id === a.conversationId && r.action_sha256 === a.hash && live(r));
      if (existing) return { approval: { ...existing }, created: false };
      const row: Row = {
        id: `00000000-0000-4000-8000-${String(++n).padStart(12, "0")}`,
        status: "pending",
        expires_at: new Date(opts.now() + a.ttlSeconds * 1000).toISOString(),
        action_sha256: a.hash,
        conversation_id: a.conversationId,
      };
      rows.push(row);
      return { approval: { ...row }, created: true };
    },
    async consume(a: { id: string; hash: string; conversationId: string }) {
      calls.push("consume");
      if (consumeOverride) return consumeOverride;
      const r = rows.find((x) => x.id === a.id);
      if (!r) return { consumed: false, reason: "not_found" };
      if (r.status === "consumed") return { consumed: false, reason: "already_consumed" };
      if (r.status !== "approved") return { consumed: false, reason: "not_approved" };
      if (Date.parse(r.expires_at) <= opts.now()) return { consumed: false, reason: "expired" };
      if (r.conversation_id !== a.conversationId) return { consumed: false, reason: "wrong_conversation" };
      if (r.action_sha256 !== a.hash) return { consumed: false, reason: "hash_mismatch" };
      r.status = "consumed";
      return { consumed: true, reason: "ok" };
    },
    async status(id: string) {
      calls.push("status");
      const r = rows.find((x) => x.id === id);
      return r ? { status: r.status } : null;
    },
  };
  return {
    rpc,
    rows,
    calls,
    approveAll: () => rows.filter((r) => r.status === "pending").forEach((r) => (r.status = "approved")),
    rejectAll: () => rows.filter((r) => r.status === "pending").forEach((r) => (r.status = "rejected")),
    expireAll: () => rows.filter((r) => live(r)).forEach((r) => (r.status = "expired")),
    failCreate: (code: string, message = "x") => (throwOnCreate = { code, message }),
    overrideConsume: (v: { consumed: boolean; reason: string } | null) => (consumeOverride = v),
  };
}

const SESSION = {
  sessionId: "sessA",
  conversationId: "11111111-1111-4111-8111-111111111111",
  workspaceId: "22222222-2222-4222-8222-222222222222",
  requesterId: "33333333-3333-4333-8333-333333333333",
  repositories: REPOS,
  flagOn: true,
  routerCredential: "router-cred-synthetic-A",
};

function setup(over: Record<string, unknown> = {}) {
  let t = Date.parse("2026-11-10T00:00:00Z");
  const fake = fakeRpc({ now: () => t });
  const decider = hookMod.createDecider({
    policy: BASE_POLICY,
    hmacKey: KEY,
    rpc: fake.rpc,
    toolName: hookMod.SPIKE_TOOL_NAME,
    ttlSeconds: 600,
    now: () => t,
    ...over,
  });
  return { fake, decider, advance: (ms: number) => (t += ms) };
}

const PUSH = () => req({ method: "POST", host: "github.com", path: "/acme-synth/widget/git-receive-pack", body: receivePack([[OID_A, OID_B, "refs/heads/main"]]) });
const READ = () => req({ method: "GET", host: "api.github.com", path: "/repos/acme-synth/widget" });

describe("approval-hook.mjs decide() — client_auth marker field (Guard 2 row 8)", () => {
  // The hook must run before the secrets transform, so it sees only the Authorization headers the CLIENT sent.
  // Its markers carry the COUNT (never a value); a reordered pipeline shows up as client_auth>0 for a client that
  // sent none (run 42820864911: with secrets first, nothing reached the stub, so only the hook could see it).
  it("counts the Authorization headers the hook received, in every marker", async () => {
    const { decider } = setup();
    const none = await decider.decide(req({ method: "GET", host: "api.github.com", path: "/repos/acme-synth/widget" }), SESSION);
    expect(none.marker.fields.client_auth).toBe(0);
    const two = await decider.decide(req({ method: "GET", host: "api.github.com", path: "/repos/acme-synth/widget", headers: { Authorization: ["a", "b"] } }), SESSION);
    expect(two.marker.fields.client_auth).toBe(2);
    const refused = await decider.decide(req({ method: "GET", host: "api.github.com", path: "/repos/other/repo", headers: { authorization: "x" } }), SESSION);
    expect(refused.marker.fields.client_auth).toBe(1);
  });
});

describe("approval-hook.mjs decide() — tunnel guard (CTO R28)", () => {
  // Measured 2026-11-10: a request sent straight to iron-proxy's http_listen (absolute form, no tunnel) reached the
  // hook with no tunnel context and was vended. Every non-CONNECT request must come from a tunnel to <host>:443.
  const read = (tunnelTarget: string | null | undefined) => req({ method: "GET", host: "api.github.com", path: "/repos/acme-synth/widget", tunnelTarget });
  for (const [label, t] of [["no tunnel context", null], ["undefined", undefined], ["another host", "other.example:443"], ["a non-443 port", "api.github.com:8443"]] as const) {
    it(`refuses a request with ${label} as guard-refused/no-tunnel, before any RPC`, async () => {
      const { fake, decider } = setup();
      const d = await decider.decide(read(t), SESSION);
      expect(d).toMatchObject({ action: "REJECT", status: 403, reason: "guard-refused", subreason: "no-tunnel" });
      expect(fake.calls).toHaveLength(0);
    });
  }
  it("runs before the flag-off rule (step 0b)", async () => {
    const { decider } = setup();
    expect((await decider.decide(read(null), { ...SESSION, flagOn: false })).subreason).toBe("no-tunnel");
  });
  it("a matching tunnel target (any case, trailing dot) proceeds", async () => {
    const { decider } = setup();
    expect((await decider.decide(read("API.GitHub.com.:443"), SESSION)).action).toBe("CONTINUE");
  });
  it("fromTransformRequest carries context.tunnel.target", () => {
    const m = hookMod.fromTransformRequest({ method: "GET", url: "/x", host: "github.com", headers: {}, body: Buffer.alloc(0) }, { tunnel: { target: "github.com:443" } });
    expect(m.tunnelTarget).toBe("github.com:443");
    expect(hookMod.fromTransformRequest({ method: "GET", url: "/x", host: "github.com", headers: {}, body: Buffer.alloc(0) }).tunnelTarget).toBeNull();
  });
});

describe("approval-hook.mjs decide() — per-session TTL (criterion 3's expiry arm)", () => {
  it("a session's ttlSeconds overrides the hook default for the rows it creates", async () => {
    const { fake, decider } = setup();
    await decider.decide(PUSH(), { ...SESSION, ttlSeconds: 60 });
    await decider.decide(PUSH(), { ...SESSION, conversationId: "00000000-0000-4000-8000-0000000000c2" });
    const [short, normal] = fake.rows;
    expect(Date.parse(short.expires_at) - Date.parse("2026-11-10T00:00:00Z")).toBe(60_000);
    expect(Date.parse(normal.expires_at) - Date.parse("2026-11-10T00:00:00Z")).toBe(600_000);
  });

  it("a non-integer or out-of-range session TTL is ignored (the hook default applies)", async () => {
    const { fake, decider } = setup();
    await decider.decide(PUSH(), { ...SESSION, ttlSeconds: "60" as unknown as number });
    expect(Date.parse(fake.rows[0].expires_at) - Date.parse("2026-11-10T00:00:00Z")).toBe(600_000);
  });
});

describe("approval-hook.mjs decide() — decision order", () => {
  it("1. flag off REJECTs every vend, reads included, and creates no row (CTO R2)", async () => {
    const { fake, decider } = setup();
    const s = { ...SESSION, flagOn: false };
    for (const r of [READ(), PUSH()]) {
      const d = await decider.decide(r, s);
      expect(d).toMatchObject({ action: "REJECT", reason: "flag-off" });
    }
    expect(fake.rows).toHaveLength(0);
  });

  it("Guard 2 row 9: the flag is read from the session input, not from a constant", async () => {
    const { decider } = setup();
    expect((await decider.decide(READ(), { ...SESSION, flagOn: true })).action).toBe("CONTINUE");
    expect((await decider.decide(READ(), { ...SESSION, flagOn: false })).action).toBe("REJECT");
    expect((await decider.decide(READ(), { ...SESSION, flagOn: "true" as unknown as boolean })).reason).toBe("flag-off");
  });

  it("2. an unlisted write is REJECTed not-allowlisted with no row", async () => {
    const { fake, decider } = setup();
    const d = await decider.decide(req({ method: "POST", host: "api.github.com", path: "/repos/acme-synth/widget/issues", body: Buffer.from("{}") }), SESSION);
    expect(d).toMatchObject({ action: "REJECT", reason: "not-allowlisted", subreason: "unlisted-write" });
    expect(fake.rows).toHaveLength(0);
  });

  it("3. an allowlisted read and the push advertisement CONTINUE with no row", async () => {
    const { fake, decider } = setup();
    expect(await decider.decide(READ(), SESSION)).toMatchObject({ action: "CONTINUE", class: "read" });
    expect(await decider.decide(req({ method: "GET", host: "github.com", path: "/acme-synth/widget/info/refs", query: "service=git-receive-pack" }), SESSION)).toMatchObject({ action: "CONTINUE", class: "push-advert" });
    expect(fake.rows).toHaveLength(0);
  });

  it("4. a read outside the allowlist is REJECTed with no row", async () => {
    const { fake, decider } = setup();
    expect(await decider.decide(req({ method: "GET", host: "api.github.com", path: "/repos/other-synth/thing" }), SESSION)).toMatchObject({ action: "REJECT", reason: "not-allowlisted", subreason: "read-outside-allowlist" });
    expect(fake.rows).toHaveLength(0);
  });

  it("5. a listed write with no row creates one pending row; a retry reuses it", async () => {
    const { fake, decider } = setup();
    const d1 = await decider.decide(PUSH(), SESSION);
    expect(d1).toMatchObject({ action: "REJECT", reason: "pending" });
    expect(d1.approvalId).toBe(fake.rows[0].id);
    expect(d1.body).toContain(fake.rows[0].id);
    expect(fake.calls).toEqual([`create:${hookMod.SPIKE_TOOL_NAME}`]);
    const d2 = await decider.decide(PUSH(), SESSION);
    expect(d2).toMatchObject({ action: "REJECT", reason: "pending", approvalId: d1.approvalId });
    expect(fake.rows).toHaveLength(1);
  });

  it("5. approved and live: consumed exactly once, then a retry creates a new pending row", async () => {
    const { fake, decider } = setup();
    await decider.decide(PUSH(), SESSION);
    fake.approveAll();
    const d = await decider.decide(PUSH(), SESSION);
    expect(d).toMatchObject({ action: "CONTINUE", class: "write", rule: "git-push" });
    expect(fake.rows[0].status).toBe("consumed"); // Guard 2 row 2: consume ran before CONTINUE
    const again = await decider.decide(PUSH(), SESSION);
    expect(again).toMatchObject({ action: "REJECT", reason: "pending" });
    expect(fake.rows).toHaveLength(2);
  });

  it("5. approved but expired by the hook's own clock: REJECT expired, no consume", async () => {
    const { fake, decider, advance } = setup();
    await decider.decide(PUSH(), SESSION);
    fake.approveAll();
    advance(601_000);
    const d = await decider.decide(PUSH(), SESSION);
    expect(d).toMatchObject({ action: "REJECT", reason: "expired" });
    expect(fake.calls).not.toContain("consume");
  });

  it("5. a rejected (or expired) previous row is reported once, later retries report pending", async () => {
    for (const [settle, reason] of [["rejectAll", "rejected"], ["expireAll", "expired"]] as const) {
      const { fake, decider } = setup();
      const first = await decider.decide(PUSH(), SESSION);
      fake[settle]();
      const d = await decider.decide(PUSH(), SESSION);
      expect(d).toMatchObject({ action: "REJECT", reason });
      expect(d.approvalId).not.toBe(first.approvalId);
      expect(await decider.decide(PUSH(), SESSION)).toMatchObject({ reason: "pending" });
    }
  });

  it("binding: a row approved for request X does not authorize request Y", async () => {
    const { fake, decider } = setup();
    await decider.decide(PUSH(), SESSION);
    fake.approveAll();
    const y = req({ method: "POST", host: "github.com", path: "/acme-synth/widget/git-receive-pack", body: receivePack([[OID_A, OID_C, "refs/heads/main"]]) });
    expect(await decider.decide(y, SESSION)).toMatchObject({ action: "REJECT", reason: "pending" });
    expect(fake.rows.find((r) => r.status === "approved")).toBeDefined();
  });

  it("maps every RPC failure to its reason code", async () => {
    for (const [code, message, reason] of [
      ["AP429", "approval: too many pending requests", "cap"],
      ["AP430", "approval: too many pending requests", "cap"],
      ["40001", "approval: concurrent change, retry", "retry"],
      ["P0001", "approval: conversation closed", "closed"],
      ["22023", "approval: conversation not found in workspace", "rpc-error"],
    ] as const) {
      const { fake, decider } = setup();
      fake.failCreate(code, message);
      expect(await decider.decide(PUSH(), SESSION), code).toMatchObject({ action: "REJECT", reason });
    }
  });

  it("maps consume failures to consume-failed with the RPC's subreason", async () => {
    for (const sub of ["already_consumed", "decider_not_owner", "requester_not_member"]) {
      const { fake, decider } = setup();
      await decider.decide(PUSH(), SESSION);
      fake.approveAll();
      fake.overrideConsume({ consumed: false, reason: sub });
      expect(await decider.decide(PUSH(), SESSION)).toMatchObject({ action: "REJECT", reason: "consume-failed", subreason: sub });
    }
  });

  it("bounds its own work: a stalled RPC yields hook-timeout", async () => {
    const { decider } = setup({
      deadlineMs: 50,
      rpc: { create: () => new Promise(() => {}), consume: async () => ({}), status: async () => null },
    });
    const t0 = performance.now();
    expect(await decider.decide(PUSH(), SESSION)).toMatchObject({ action: "REJECT", reason: "hook-timeout" });
    expect(performance.now() - t0).toBeLessThan(2000);
  });

  it("CONNECT: the router-only credential is required (407 without it), and a CONNECT is not a vend (R26)", async () => {
    const { fake, decider } = setup();
    // The synthetic CONNECT iron-proxy builds for a tunnel_listen tunnel: SNI = host, no tunnel context (CTO R36).
    const conn = (auth?: string) => req({ method: "CONNECT", host: "github.com", path: "", tunnelTarget: null, headers: auth ? { "proxy-authorization": auth } : {} });
    const good = "Basic " + Buffer.from(`router:${SESSION.routerCredential}`).toString("base64");
    expect(await decider.decide(conn(), SESSION)).toMatchObject({ action: "REJECT", status: 407 });
    expect(await decider.decide(conn("Basic " + Buffer.from("router:wrong").toString("base64")), SESSION)).toMatchObject({ action: "REJECT", status: 407 });
    expect(await decider.decide(conn(good), SESSION)).toMatchObject({ action: "CONTINUE", class: "connect" });
    expect(fake.rows).toHaveLength(0);
  });

  it("markers carry no body, header value or token, and name request id, source and hash prefix", async () => {
    const { decider } = setup();
    const canary = "BODY-CANARY-" + randomBytes(6).toString("hex");
    const tokenish = "decoy-" + randomBytes(8).toString("hex");
    const r = req({ method: "POST", host: "api.github.com", path: "/repos/acme-synth/widget/pulls", body: Buffer.from(`{"title":"${canary}"}`), headers: { authorization: `token ${tokenish}` } });
    const d = await decider.decide({ ...r, requestId: "req-1" }, SESSION);
    const line = hookMod.formatMarker(d.marker.name, d.marker.fields);
    expect(line).toMatch(/^SOLEUR_EGRESS_VEND_REFUSED /);
    expect(line).toContain("request_id=req-1");
    expect(line).toContain("source=hook");
    expect(line).toContain("reason=pending");
    expect(line).toMatch(/action_sha256=[0-9a-f]{12}( |$)/);
    expect(line).not.toContain(canary);
    expect(line).not.toContain(tokenish);
    expect(hookMod.formatMarker("SOLEUR_EGRESS_VEND", { host: "a b\nSOLEUR_FAKE=1" })).not.toMatch(/\n|a b/);
  });
});

describe("approval-hook.mjs — header strip and transform mapping", () => {
  it("removes every case variant of Idempotency-Key and leaves the rest, or returns null when absent", () => {
    const r = { method: "POST", url: "https://api.github.com/x", host: "api.github.com", body: Buffer.alloc(0), headers: { "Idempotency-Key": { values: ["k1"] }, "idempotency-key": { values: ["k2"] }, Accept: { values: ["*/*"] } } };
    const out = hookMod.withoutStrippedHeaders(r);
    expect(Object.keys(out!.headers)).toEqual(["Accept"]);
    expect(hookMod.withoutStrippedHeaders({ ...r, headers: { Accept: { values: ["*/*"] } } })).toBeNull();
  });

  it("maps iron-proxy's HttpRequest to the decider's struct (path, query, header lists, body)", () => {
    const m = hookMod.fromTransformRequest({ method: "GET", url: "https://github.com/acme-synth/widget/info/refs?service=git-upload-pack", host: "github.com", headers: { Accept: { values: ["a", "b"] } }, body: Buffer.from("x") });
    expect(m).toMatchObject({ method: "GET", host: "github.com", path: "/acme-synth/widget/info/refs", query: "service=git-upload-pack", headers: { Accept: ["a", "b"] } });
    expect(policyMod.classify(policyMod.normalizeRequest(m), BASE_POLICY, { repositories: REPOS }).verdict).toBe("read");
  });

  // Measured 2026-11-10 against iron-proxy v0.56.0: a MITM'd request arrives with `url` in ORIGIN form
  // (`/repos/o/r?x=1`) and the authority in `host`, so a parser that requires an absolute URL refuses every request.
  it("maps an origin-form url (what iron-proxy sends) against the host field", () => {
    const m = hookMod.fromTransformRequest({ method: "GET", url: "/acme-synth/widget/info/refs?service=git-upload-pack", host: "github.com", headers: {}, body: Buffer.alloc(0) });
    expect(m).toMatchObject({ method: "GET", host: "github.com", path: "/acme-synth/widget/info/refs", query: "service=git-upload-pack" });
    expect(policyMod.classify(policyMod.normalizeRequest(m), BASE_POLICY, { repositories: REPOS }).verdict).toBe("read");
  });

  it("refuses an absolute url whose authority differs from the host field (Guard 2 row 14)", () => {
    const m = hookMod.fromTransformRequest({ method: "GET", url: "https://evil.example/acme-synth/widget/info/refs?service=git-upload-pack", host: "github.com", headers: {}, body: Buffer.alloc(0) });
    expect(policyMod.normalizeRequest(m).ok).toBe(false);
  });
});

describe("approval-hook.mjs — Supabase target guard (CTO R21)", () => {
  const status = { API_URL: "http://127.0.0.1:54321", SERVICE_ROLE_KEY: "svc-synthetic" };
  it("accepts a loopback URL whose URL and key match supabase status", () => {
    expect(hookMod.checkSupabaseTarget({ url: "http://127.0.0.1:54321", key: "svc-synthetic", status })).toEqual({ ok: true });
  });
  it("refuses a non-loopback host, a hostname, or a URL/key that differs from supabase status", () => {
    expect(hookMod.checkSupabaseTarget({ url: "https://abc.supabase.co", key: "svc-synthetic", status }).ok).toBe(false);
    expect(hookMod.checkSupabaseTarget({ url: "http://localhost:54321", key: "svc-synthetic", status }).ok).toBe(false);
    expect(hookMod.checkSupabaseTarget({ url: "http://127.0.0.1:54321", key: "other", status }).ok).toBe(false);
    expect(hookMod.checkSupabaseTarget({ url: "http://127.0.0.1:9999", key: "svc-synthetic", status }).ok).toBe(false);
    expect(hookMod.checkSupabaseTarget({ url: "http://127.0.0.1:54321", key: "svc-synthetic", status: {} }).ok).toBe(false);
  });
});

// ---------------------------------------------------------------------------------------------------------------
// verdict.mjs — Guard 3 (outcome floor and never-skip).
// ---------------------------------------------------------------------------------------------------------------

function allPass() {
  return Array.from({ length: 9 }, (_, i) => ({ criterion: i + 1, verdict: "pass", observation: `observed-${i + 1}` }));
}

describe("verdict.mjs — outcome floor", () => {
  it("GO when criteria 1-9 all pass with an observation", () => {
    expect(verdictMod.computeVerdict({ records: allPass() })).toMatchObject({ verdict: "GO", exitCode: 0 });
  });

  it("Guard 3 row 6 must-PASS: every criterion measured, criterion 4 fails: NO-GO, exit 0", () => {
    const recs = allPass();
    recs[3] = { criterion: 4, verdict: "fail", observation: "vended without approval" };
    expect(verdictMod.computeVerdict({ records: recs })).toMatchObject({ verdict: "NO-GO", exitCode: 0, f1Holds: false });
  });

  it("a failure of criterion 2 or 5 is recorded as F1 evidence", () => {
    for (const c of [2, 5]) {
      const recs = allPass();
      recs[c - 1] = { criterion: c, verdict: "fail", observation: "x" };
      expect(verdictMod.computeVerdict({ records: recs })).toMatchObject({ verdict: "NO-GO", f1Holds: true });
    }
  });

  it("Guard 3 row 1: a missing arm (criterion 5) is INCONCLUSIVE, exit 1", () => {
    const v = verdictMod.computeVerdict({ records: allPass().filter((r) => r.criterion !== 5) });
    expect(v).toMatchObject({ verdict: "INCONCLUSIVE", exitCode: 1 });
    expect(v.missing).toEqual([5]);
  });

  it("Guard 3 row 2: no records at all is INCONCLUSIVE", () => {
    expect(verdictMod.computeVerdict({ records: [] })).toMatchObject({ verdict: "INCONCLUSIVE", exitCode: 1 });
    expect(verdictMod.computeVerdict({})).toMatchObject({ verdict: "INCONCLUSIVE", exitCode: 1 });
  });

  it("Guard 3 row 3: the floor counts distinct ids (criterion 4 twice, criterion 6 never)", () => {
    const recs = allPass().filter((r) => r.criterion !== 6);
    recs.push({ criterion: 4, verdict: "pass", observation: "dup" });
    expect(recs).toHaveLength(9);
    expect(verdictMod.computeVerdict({ records: recs })).toMatchObject({ verdict: "INCONCLUSIVE", missing: [6] });
  });

  it("Guard 3 row 5: all unmeasurable with reasons is INCONCLUSIVE and each reason is carried", () => {
    const recs = allPass().map((r) => ({ criterion: r.criterion, verdict: "unmeasurable", reason: `harness-${r.criterion}` }));
    const v = verdictMod.computeVerdict({ records: recs });
    expect(v).toMatchObject({ verdict: "INCONCLUSIVE", exitCode: 1 });
    expect(v.unmeasurable).toHaveLength(9);
    expect(v.unmeasurable[0]).toEqual({ criterion: 1, reason: "harness-1" });
  });

  it("a pass with no positive observation does not count as a verdict", () => {
    const recs = allPass();
    recs[0] = { criterion: 1, verdict: "pass", observation: "" };
    expect(verdictMod.computeVerdict({ records: recs })).toMatchObject({ verdict: "INCONCLUSIVE" });
  });

  it("a measured failure of criterion 2 is still F1 evidence when the run is INCONCLUSIVE", () => {
    const recs = allPass().filter((r) => r.criterion !== 9);
    recs[1] = { criterion: 2, verdict: "fail", observation: "x" };
    expect(verdictMod.computeVerdict({ records: recs })).toMatchObject({ verdict: "INCONCLUSIVE", f1Holds: true });
  });

  it("conflicting records for one id: fail beats unmeasurable beats pass", () => {
    const recs = allPass();
    recs.push({ criterion: 3, verdict: "fail", observation: "x" });
    expect(verdictMod.computeVerdict({ records: recs })).toMatchObject({ verdict: "NO-GO", failed: [3] });
    const recs2 = allPass();
    recs2.push({ criterion: 3, verdict: "unmeasurable", reason: "r" } as never);
    expect(verdictMod.computeVerdict({ records: recs2 })).toMatchObject({ verdict: "INCONCLUSIVE" });
  });

  it("an unknown criterion id or verdict value makes the run INCONCLUSIVE", () => {
    expect(verdictMod.computeVerdict({ records: [...allPass(), { criterion: 10, verdict: "pass", observation: "x" }] })).toMatchObject({ verdict: "INCONCLUSIVE" });
    const recs = allPass();
    recs[0] = { criterion: 1, verdict: "PASS", observation: "x" };
    expect(verdictMod.computeVerdict({ records: recs })).toMatchObject({ verdict: "INCONCLUSIVE" });
  });

  it("a stored top-level verdict that disagrees with the records is INCONCLUSIVE", () => {
    expect(verdictMod.computeVerdict({ verdict: "GO", records: allPass() })).toMatchObject({ verdict: "GO" });
    const recs = allPass();
    recs[0] = { criterion: 1, verdict: "fail", observation: "x" };
    expect(verdictMod.computeVerdict({ verdict: "GO", records: recs })).toMatchObject({ verdict: "INCONCLUSIVE" });
  });
});

// Review 2026-11-10 (PR #12518): the hook judged a URL-parser-cleaned path, GraphQL ignored the query string, and a
// consume could commit after the hook had already answered hook-timeout. Each row below drives the live entry point
// (fromTransformRequest -> normalizeRequest -> classify / decide), not classify on a hand-built struct.
describe("review 2026-11-10 — what the hook judges is what goes upstream", () => {
  const map = (url: string, host = "api.github.com", method = "GET") =>
    hookMod.fromTransformRequest({ method, url, host, headers: {}, body: Buffer.alloc(0) }, { tunnel: { target: `${host}:443` }, sni: host });
  const verdictOf = (m: ReturnType<typeof map>) => policyMod.classify(policyMod.normalizeRequest(m), BASE_POLICY, { repositories: REPOS });

  it("refuses every traversal spelling on the live path instead of resolving it", () => {
    for (const url of [
      "//evil/repos/acme-synth/widget/contents",
      "/\\evil/repos/acme-synth/widget/contents",
      `/repos/other-synth/thing/${UP2}acme-synth/widget/x`,
      "/repos/other-synth/thing/%2e%2e/%2e%2e/acme-synth/widget/x",
      "/repos/acme-synth/widget/.%2E/x",
      `/repos/acme-synth/widget/x#frag/${"../".repeat(3)}other-synth/r`,
      "https://api.github.com//evil/repos/acme-synth/widget",
    ]) {
      expect(verdictOf(map(url)), url).toMatchObject({ verdict: "refused", subreason: "unparseable" });
    }
  });

  it("must-PASS: the plain allowlisted read still maps and vends", () => {
    expect(verdictOf(map("/repos/acme-synth/widget/contents/README.md?ref=main"))).toMatchObject({ verdict: "read" });
    expect(map("/repos/acme-synth/widget/x").sni).toBe("api.github.com");
  });

  it("refuses a GraphQL request that carries a query string (operationName or query override)", () => {
    const doc = "query Q { viewer { login } } mutation M { addComment(input: {}) { clientMutationId } }";
    const body = gql({ query: doc, operationName: "Q" });
    for (const query of ["operationName=M", "query=mutation%7BaddComment%7D", "x=1"]) {
      expect(classify({ method: "POST", host: "api.github.com", path: "/graphql", query, body }), query).toMatchObject({ verdict: "refused", subreason: "unparseable" });
    }
    expect(classify({ method: "POST", host: "api.github.com", path: "/graphql", body }).verdict).toBe("read");
  });

  it("refuses GraphQL JSON two parsers could read differently: duplicate keys, unsafe integers", () => {
    const raw = (s: string) => classify({ method: "POST", host: "api.github.com", path: "/graphql", body: Buffer.from(s) });
    expect(raw('{"query":"mutation { addComment(input: {}) { clientMutationId } }","query":"{ viewer { login } }"}')).toMatchObject({ verdict: "refused", subreason: "unparseable" });
    expect(raw('{"query":"mutation M($b: String) { addComment(input: {body: $b}) { clientMutationId } }","variables":{"b":"a","b":"z"}}')).toMatchObject({ verdict: "refused", subreason: "unparseable" });
    expect(raw('{"query":"mutation M($n: Int) { addComment(input: {n: $n}) { clientMutationId } }","variables":{"n":9007199254740993}}')).toMatchObject({ verdict: "refused", subreason: "unparseable" });
    expect(raw('{"query":"mutation M($n: Int) { addComment(input: {n: $n}) { clientMutationId } }","variables":{"n":42,"s":"a \\"b\\" c"}}').verdict).toBe("write");
  });

  it("refuses a lowercase method and every method-override spelling", () => {
    expect(classify({ method: "get", host: "api.github.com", path: "/repos/acme-synth/widget" })).toMatchObject({ verdict: "refused", subreason: "unparseable" });
    for (const h of ["X-HTTP-Method-Override", "x-http-method", "X-Method-Override"]) {
      expect(classify({ method: "GET", host: "api.github.com", path: "/repos/acme-synth/widget", headers: { [h]: "DELETE" } }), h).toMatchObject({ verdict: "refused" });
    }
    expect(classify({ method: "GET", host: "api.github.com", path: "/repos/acme-synth/widget", query: "_method=DELETE" })).toMatchObject({ verdict: "refused" });
  });

  it("hashes the REST query string as sent, so a reordered query is a different approval", () => {
    const at = (query: string) => hashOf({ method: "POST", host: "api.github.com", path: "/repos/acme-synth/widget/pulls", query, body: Buffer.from("{}") });
    expect(at("a=1&a=2")).not.toBe(at("a=2&a=1"));
    expect(at("a=1&a=2")).toBe(at("a=1&a=2"));
  });

  it("hashes git push capabilities and push options, so options cannot ride on another push's approval", () => {
    const body = (caps: string, opts: string[] = []) => {
      const lines = [pkt(`${OID_A} ${OID_B} refs/heads/main\0${caps}\n`), "0000", ...opts.map((o) => pkt(`${o}\n`)), opts.length ? "0000" : ""];
      return Buffer.concat([Buffer.from(lines.join(""), "latin1"), Buffer.from("PACK-synthetic-bytes")]);
    };
    const at = (b: Buffer) => hashOf({ method: "POST", host: "github.com", path: "/acme-synth/widget/git-receive-pack", body: b });
    const base = at(body("report-status push-options", ["ci.skip"]));
    expect(at(body("report-status push-options", ["merge_request.create"]))).not.toBe(base);
    expect(at(body("report-status atomic push-options", ["ci.skip"]))).not.toBe(base);
    expect(at(body("push-options report-status", ["ci.skip"]))).toBe(base); // capability order is not meaning
  });

  it("stableJson refuses values JSON cannot represent exactly", () => {
    for (const v of [{ a: undefined }, { a: Number.NaN }, { a: () => 1 }, { a: Infinity }]) expect(() => policyMod.stableJson(v)).toThrow();
    expect(policyMod.stableJson({ b: 1, a: [null, "x"] })).toBe('{"a":[null,"x"],"b":1}');
  });

  it("a consume already in flight is not cut off by the deadline: the paid-for vend proceeds", async () => {
    let consumes = 0;
    const row = { id: "row-late", status: "approved", expires_at: "2099-01-01T00:00:00Z" };
    const { decider } = setup({
      deadlineMs: 50,
      rpc: {
        create: async () => ({ approval: row, created: false }),
        consume: () => new Promise((r) => setTimeout(() => { consumes++; r({ consumed: true }); }, 120)),
        status: async () => null,
      },
    });
    expect(await decider.decide(PUSH(), SESSION)).toMatchObject({ action: "CONTINUE", class: "write", approvalId: "row-late" });
    expect(consumes).toBe(1);
  });

  it("a deadline that fires before consume starts refuses hook-timeout and never consumes", async () => {
    let consumes = 0;
    const row = { id: "row-slow", status: "approved", expires_at: "2099-01-01T00:00:00Z" };
    const { decider } = setup({
      deadlineMs: 50,
      rpc: {
        create: () => new Promise((r) => setTimeout(() => r({ approval: row, created: false }), 90)),
        consume: async () => { consumes++; return { consumed: true }; },
        status: async () => null,
      },
    });
    expect(await decider.decide(PUSH(), SESSION)).toMatchObject({ action: "REJECT", reason: "hook-timeout" });
    await new Promise((r) => setTimeout(r, 150));
    expect(consumes).toBe(0);
  });
});

describe("review 2026-11-10 — CTO R36, R37, R39, R40", () => {
  const good = "Basic " + Buffer.from(`router:${SESSION.routerCredential}`).toString("base64");
  const connect = (over: Record<string, unknown>) => req({ method: "CONNECT", host: "api.github.com", path: "", tunnelTarget: null, headers: { "proxy-authorization": good }, ...over });

  it("R36: a CONNECT passes the hook only with the router credential, SNI = host and no tunnel context (the method list is the control for the rest)", async () => {
    const { fake, decider } = setup();
    expect(await decider.decide(connect({}), SESSION)).toMatchObject({ action: "CONTINUE", class: "connect" });
    for (const [over, sub] of [
      [{ sni: null }, "no-sni"], // a CONNECT sent to http_listen
      [{ sni: "github.com" }, "sni-mismatch"],
      [{ tunnelTarget: "api.github.com:443" }, "in-tunnel"], // a CONNECT sent inside a tunnel
      [{ headers: {} }, "credential"],
    ] as const) {
      expect(await decider.decide(connect(over), SESSION), sub).toMatchObject({ action: "REJECT", status: 407, subreason: sub });
    }
    expect(fake.rows).toHaveLength(0);
  });

  it("R36: every secrets rule in the iron-proxy template carries the method list, so no CONNECT gets the credential", () => {
    const tmpl = parseYaml(readFileSync(join(SPIKE, "iron-proxy.config.tmpl.yaml"), "utf8").replace(/@@[A-Z_]+@@/g, "x"));
    const secrets = tmpl.transforms.find((t: { name: string }) => t.name === "secrets").config.secrets;
    const rules = secrets.flatMap((x: { rules: Array<{ host: string; methods?: string[] }> }) => x.rules);
    expect(rules.length).toBe(4);
    for (const r of rules) {
      expect(r.methods, r.host).toEqual(["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE"]);
    }
  });

  it("R37: a request with no SNI (plain HTTP inside the tunnel) or another SNI is refused no-tls, before the flag", async () => {
    const { fake, decider } = setup();
    for (const sni of [null, "", "github.com"]) {
      expect(await decider.decide(req({ method: "GET", host: "api.github.com", path: "/repos/acme-synth/widget", sni }), SESSION), String(sni)).toMatchObject({ action: "REJECT", reason: "guard-refused", subreason: "no-tls" });
      expect(await decider.decide(req({ method: "GET", host: "api.github.com", path: "/repos/acme-synth/widget", sni }), { ...SESSION, flagOn: false })).toMatchObject({ subreason: "no-tls" });
    }
    expect(await decider.decide(req({ method: "GET", host: "api.github.com", path: "/repos/acme-synth/widget", sni: "API.GITHUB.COM." }), SESSION)).toMatchObject({ action: "CONTINUE" });
    expect(fake.rows).toHaveLength(0);
  });

  it("R40: a body at or over the cap is refused with no row; one byte under is classified", async () => {
    const { fake, decider } = setup({ bodyCapBytes: 64 });
    const at = (n: number) => req({ method: "POST", host: "api.github.com", path: "/repos/acme-synth/widget/pulls", body: Buffer.alloc(n, 0x20) });
    expect(await decider.decide(at(64), SESSION)).toMatchObject({ action: "REJECT", reason: "guard-refused", subreason: "body-over-cap" });
    expect(await decider.decide(at(65), SESSION)).toMatchObject({ subreason: "body-over-cap" });
    expect(fake.rows).toHaveLength(0);
    expect(await decider.decide(at(63), SESSION)).toMatchObject({ reason: "pending" });
  });

  it("R40: the hook's cap equals iron-proxy's max_request_body_bytes and stays under grpc-js's 4 MiB receive limit", () => {
    const tmpl = parseYaml(readFileSync(join(SPIKE, "iron-proxy.config.tmpl.yaml"), "utf8").replace(/@@[A-Z_]+@@/g, "x"));
    expect(tmpl.proxy.max_request_body_bytes).toBe(hookMod.BODY_CAP_BYTES);
    expect(hookMod.BODY_CAP_BYTES).toBeLessThan(4 * 1024 * 1024);
  });

  it("R39: git's flush-only receive-pack probe vends with no row; any other body is the gated push", async () => {
    const { fake, decider } = setup();
    const post = (body: Buffer, path = "/acme-synth/widget/git-receive-pack") => req({ method: "POST", host: "github.com", path, body });
    expect(await decider.decide(post(Buffer.from("0000")), SESSION)).toMatchObject({ action: "CONTINUE", class: "push-advert", rule: "git-receive-pack-probe" });
    expect(fake.rows).toHaveLength(0);
    for (const b of ["00000", "0000\n", "0000PACK", ""]) {
      expect((await decider.decide(post(Buffer.from(b)), SESSION)).class, JSON.stringify(b)).not.toBe("push-advert");
    }
    expect(await decider.decide(post(Buffer.from("0000"), "/other-synth/thing/git-receive-pack"), SESSION)).toMatchObject({ action: "REJECT", subreason: "read-outside-allowlist" });
    expect(await decider.decide(PUSH(), SESSION)).toMatchObject({ reason: "pending" });
  });
});

describe("verdict.mjs — a pass carrying a failed observation (review F1)", () => {
  const withNine = (rec: Record<string, unknown>) => [...allPass().filter((r) => r.criterion !== 9), { criterion: 9, ...rec }];

  it("refuses a pass whose observation starts with `failed:` as a harness error (INCONCLUSIVE)", () => {
    const v = verdictMod.computeVerdict({ records: withNine({ verdict: "pass", observation: "failed: x" }) });
    expect(v).toMatchObject({ verdict: "INCONCLUSIVE", exitCode: 1 });
    expect(v.unmeasurable).toEqual([{ criterion: 9, reason: "pass-with-failed-observation" }]);
    expect(v.harness).toContain("pass-with-failed-observation:9");
  });

  it("trims the observation before the check", () => {
    const v = verdictMod.computeVerdict({ records: withNine({ verdict: "pass", observation: "  failed: x" }) });
    expect(v).toMatchObject({ verdict: "INCONCLUSIVE", exitCode: 1 });
    expect(v.harness).toContain("pass-with-failed-observation:9");
  });

  it("keeps a pass whose observation mentions failure without the `failed:` prefix", () => {
    const v = verdictMod.computeVerdict({ records: withNine({ verdict: "pass", observation: "all checks held: a failed-login probe" }) });
    expect(v).toMatchObject({ verdict: "GO", exitCode: 0 });
    expect(v.harness).toEqual([]);
  });

  it("refuses only a pass: a fail with `failed:` beside eight passes is NO-GO", () => {
    const v = verdictMod.computeVerdict({ records: withNine({ verdict: "fail", observation: "failed: x" }) });
    expect(v).toMatchObject({ verdict: "NO-GO", exitCode: 0, failed: [9] });
  });
});

describe("review 2026-11-10 fix round — policy holes", () => {
  it("a REST write whose body is not JSON (form-encoded `_method=DELETE`, or no content type) is refused, not hashed", () => {
    const at = (ct: string | undefined) => classify({ method: "POST", host: "api.github.com", path: "/repos/acme-synth/widget/pulls", body: Buffer.from("_method=DELETE"), headers: ct === undefined ? { "content-type": "" } : { "content-type": ct } });
    expect(at("application/x-www-form-urlencoded")).toMatchObject({ verdict: "refused", subreason: "unparseable" });
    expect(at("multipart/form-data; boundary=x")).toMatchObject({ verdict: "refused", subreason: "unparseable" });
    expect(at(undefined)).toMatchObject({ verdict: "refused", subreason: "unparseable" });
    for (const ct of ["application/json", "application/json; charset=utf-8", "application/vnd.github+json", "application/vnd.github.v3+json"]) {
      expect(classify({ method: "POST", host: "api.github.com", path: "/repos/acme-synth/widget/pulls", body: Buffer.from("{}"), headers: { "content-type": ct } }).verdict, ct).toBe("write");
    }
  });

  it("push options are hashed when the capability carries a value (push-options=<v>)", () => {
    const body = (caps: string, opt: string) => Buffer.concat([Buffer.from([pkt(`${OID_A} ${OID_B} refs/heads/main\0${caps}\n`), "0000", pkt(`${opt}\n`), "0000"].join(""), "latin1"), Buffer.from("PACK-synthetic-bytes")]);
    const at = (b: Buffer) => hashOf({ method: "POST", host: "github.com", path: "/acme-synth/widget/git-receive-pack", body: b });
    expect(at(body("report-status push-options=1", "ci.skip"))).not.toBe(at(body("report-status push-options=1", "deploy=prod")));
  });
});

describe("review 2026-11-10 verification pass — Content-Type is unambiguous", () => {
  const post = (headers: Record<string, unknown>) => policyMod.classify(policyMod.normalizeRequest({ method: "POST", host: "api.github.com", path: "/repos/acme-synth/widget/pulls", query: "", body: Buffer.from("{}"), headers, tunnelTarget: "api.github.com:443", sni: "api.github.com" }), BASE_POLICY, { repositories: REPOS });
  it("refuses two Content-Type values (one key holding two, or two case variants), however the first is parameterised", () => {
    expect(post({ "content-type": ["application/json; x", "application/x-www-form-urlencoded"] })).toMatchObject({ verdict: "refused", subreason: "unparseable" });
    // Each value valid on its own: only the one-value rule refuses this (a first-wins reader would take the JSON).
    expect(post({ "content-type": ["application/json", "application/x-www-form-urlencoded"] })).toMatchObject({ verdict: "refused", subreason: "unparseable" });
    expect(post({ "Content-Type": "application/json", "content-type": "application/json" })).toMatchObject({ verdict: "refused", subreason: "unparseable" });
    expect(post({ "Content-Type": "application/json; a", "content-type": "application/x-www-form-urlencoded" })).toMatchObject({ verdict: "refused", subreason: "unparseable" });
  });
  it("accepts only charset=utf-8 as a parameter", () => {
    expect(post({ "content-type": "application/json; charset=utf-16" })).toMatchObject({ verdict: "refused" });
    expect(post({ "content-type": "application/json; boundary=x" })).toMatchObject({ verdict: "refused" });
    expect(post({ "content-type": "application/json; charset=UTF-8" }).verdict).toBe("write");
    expect(post({ "content-type": "application/json" }).verdict).toBe("write");
  });
});
