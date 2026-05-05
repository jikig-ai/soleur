import { describe, test, expect } from "vitest";
import { readFileSync, existsSync, writeFileSync, unlinkSync } from "node:fs";
import { spawnSync } from "node:child_process";
import {
  generateKeyPairSync,
  createPublicKey,
  verify as cryptoVerify,
} from "node:crypto";
import { tmpdir } from "node:os";
import path from "node:path";

// =============================================================================
// Load-bearing constants. Drift in any of these silently weakens the guard;
// the tests below assert each appears verbatim in the workflow YAML.
// =============================================================================

// Leak-tripwire regex patterns. `BEGIN [A-Z ]*PRIVATE KEY` matches PEM headers:
// `BEGIN PRIVATE KEY` (PKCS#8), `BEGIN RSA PRIVATE KEY`, `BEGIN EC PRIVATE KEY`,
// `BEGIN OPENSSH PRIVATE KEY`. The `*` (zero-or-more) is load-bearing: PKCS#8
// has nothing between `BEGIN ` and `PRIVATE KEY`, so `+` would silently miss it.
// `BEGIN PUBLIC KEY` does NOT match (no "PRIVATE"). The `eyJ[A-Za-z0-9_-]{20,}`
// pattern matches JWT segments (base64url-encoded JSON header, 20+ chars covers
// a real header without false-positives on `eyJ`-prefixed prose).
//
// A future PR that loosens these (e.g., `BEGIN.*KEY` catches public keys;
// `BEGIN RSA PRIVATE KEY` misses PKCS#8) silently weakens the guard. CODEOWNERS
// requires a second-reviewer on the workflow file (see CODEOWNERS).
//
// See: knowledge-base/project/learnings/best-practices/2026-04-18-drift-guard-self-silent-failures.md
export const LEAK_TRIPWIRE_PEM_REGEX = "BEGIN [A-Z ]*PRIVATE KEY";
export const LEAK_TRIPWIRE_JWT_REGEX = "eyJ[A-Za-z0-9_-]{20,}";

// Concurrency group — must be unique across all workflows in this repo.
export const CONCURRENCY_GROUP = "scheduled-github-app-drift-guard";

// Issue title prefixes. Each prefix is distinct from oauth-probe's prefix
// (`[ci/auth-broken] Synthetic OAuth probe failed`) so the dedup search
// scoped to `drift-guard` does not collide.
//
// See: knowledge-base/project/plans/2026-05-05-feat-github-app-drift-guard-plan.md
//      Kieran review P1-3 for the collision avoidance rationale.
export const ISSUE_TITLE_PREFIX_AUTH_BROKEN =
  "[ci/auth-broken] GitHub App drift-guard fired";
export const ISSUE_TITLE_PREFIX_GUARD_BROKEN =
  "[ci/guard-broken] GitHub App drift-guard malfunctioned";
export const ISSUE_TITLE_PREFIX_LEAK_SUSPECTED =
  "[security/leak-suspected] GitHub App drift-guard log-leak tripwire";

// =============================================================================
// Helpers
// =============================================================================

const repoRoot = path.resolve(__dirname, "../../..");
const workflowPath = path.join(
  repoRoot,
  ".github/workflows/scheduled-github-app-drift-guard.yml",
);

// Extract a bash function body from the workflow's `run: |` script, robust
// to indentation reflows. Same pattern as oauth-probe-contract.test.ts.
function extractFunctionBody(yaml: string, name: string): string {
  const declRe = new RegExp(`(?:^|\\n)([ \\t]+)${name}\\(\\)\\s*\\{`);
  const decl = yaml.match(declRe);
  if (!decl || decl.index === undefined) {
    throw new Error(
      `${name} function not found in workflow — has it been renamed or removed?`,
    );
  }
  const indent = decl[1];
  const start = decl.index + (decl[0].startsWith("\n") ? 1 : 0);
  const tail = yaml.slice(start);
  const closeRe = new RegExp(`\\n${indent}\\}(?:\\n|$)`);
  const close = tail.match(closeRe);
  if (!close || close.index === undefined) {
    throw new Error(
      `${name} function close brace not found at indent="${indent.replace(/\t/g, "\\t")}" — workflow may be malformed`,
    );
  }
  return tail.slice(0, close.index + close[0].length);
}

// =============================================================================
// Trigger-surface contract — schedule + workflow_dispatch only
// =============================================================================

describe("scheduled-github-app-drift-guard.yml — trigger surface", () => {
  test("workflow file exists at expected path", () => {
    expect(
      existsSync(workflowPath),
      `Workflow not found at ${workflowPath} — was it moved or renamed?`,
    ).toBe(true);
  });

  test("on: contains schedule and workflow_dispatch only", () => {
    const yaml = readFileSync(workflowPath, "utf-8");
    // Allowlist: must contain these triggers
    expect(yaml).toMatch(/^on:\s*$/m);
    expect(yaml).toMatch(/^\s+schedule:\s*$/m);
    expect(yaml).toMatch(/^\s+workflow_dispatch:/m);
  });

  test("on: does NOT contain pull_request, pull_request_target, or workflow_run", () => {
    const yaml = readFileSync(workflowPath, "utf-8");
    // Forked-PR + workflow_run + pull_request_target are fork-secret-leak vectors.
    // Even commented-out, these strings should not appear at column-0 yaml-key
    // depth — the contract is "no support for fork-reachable triggers, ever."
    // Bare-key denylist (regex-anchored at line start with leading whitespace).
    expect(yaml).not.toMatch(/^\s+pull_request:/m);
    expect(yaml).not.toMatch(/^\s+pull_request_target:/m);
    expect(yaml).not.toMatch(/^\s+workflow_run:/m);
  });

  test("schedule is hourly cron '0 * * * *'", () => {
    const yaml = readFileSync(workflowPath, "utf-8");
    expect(yaml).toMatch(/cron:\s*['"]0 \* \* \* \*['"]/);
  });

  test("workflow_dispatch is gated to the canonical repository at job level", () => {
    // Per SpecFlow F6 — workflow_dispatch from a fork can't trigger a workflow
    // on the default branch, but a non-fork misroute or compromised collaborator
    // token could still try. The job-level `if: github.repository ==` guard is
    // the load-bearing run-time control; CODEOWNERS is review-time.
    const yaml = readFileSync(workflowPath, "utf-8");
    expect(yaml).toMatch(/if:\s+github\.repository\s*==\s*['"]jikig-ai\/soleur['"]/);
  });
});

// =============================================================================
// Permissions contract — minimum-privilege, no token-elevating scopes
// =============================================================================

describe("scheduled-github-app-drift-guard.yml — permissions", () => {
  test("permissions: contains contents: read and issues: write only", () => {
    const yaml = readFileSync(workflowPath, "utf-8");
    expect(yaml).toMatch(/^\s*contents:\s*read\s*$/m);
    expect(yaml).toMatch(/^\s*issues:\s*write\s*$/m);
  });

  test("permissions: does NOT grant id-token, actions: write, pages, or deployments", () => {
    const yaml = readFileSync(workflowPath, "utf-8");
    // These would each allow privilege escalation paths (OIDC token mint,
    // workflow self-modification, GH Pages publish, deployment creation).
    expect(yaml).not.toMatch(/^\s*id-token:/m);
    expect(yaml).not.toMatch(/^\s*actions:\s*write/m);
    expect(yaml).not.toMatch(/^\s*pages:\s*write/m);
    expect(yaml).not.toMatch(/^\s*deployments:/m);
  });
});

// =============================================================================
// Concurrency contract
// =============================================================================

describe("scheduled-github-app-drift-guard.yml — concurrency", () => {
  test("concurrency group is the canonical name with cancel-in-progress: false", () => {
    const yaml = readFileSync(workflowPath, "utf-8");
    expect(yaml).toContain(`group: ${CONCURRENCY_GROUP}`);
    expect(yaml).toMatch(/cancel-in-progress:\s*false/);
  });
});

// =============================================================================
// Leak-tripwire contract — regex string equality (load-bearing)
// =============================================================================

describe("scheduled-github-app-drift-guard.yml — leak tripwire", () => {
  test("leak tripwire greps for both anchored regex patterns", () => {
    const yaml = readFileSync(workflowPath, "utf-8");
    // Both patterns must appear verbatim in the workflow body. A future
    // edit that loosens or narrows either pattern silently weakens the
    // guard; CODEOWNERS requires a second-reviewer to catch this at PR.
    expect(yaml).toContain(LEAK_TRIPWIRE_PEM_REGEX);
    expect(yaml).toContain(LEAK_TRIPWIRE_JWT_REGEX);
  });

  test("leak tripwire is a separate step with if: always()", () => {
    const yaml = readFileSync(workflowPath, "utf-8");
    // The tripwire MUST run regardless of whether prior steps succeeded or
    // failed — if a prior step leaked the PEM and crashed, we still want
    // the leak detection to fire.
    expect(yaml).toMatch(/Leak tripwire[\s\S]+?if:\s*always\(\)/);
  });

  test("leak tripwire scans the captured step-output.log", () => {
    const yaml = readFileSync(workflowPath, "utf-8");
    // Pre-step `tee`-capture is what bridges leak → operator awareness;
    // grepping the GitHub-rendered log post-hoc is impossible mid-run.
    expect(yaml).toContain("step-output.log");
  });
});

// =============================================================================
// Failure-routing contract — record_failure 3-output shape + label split
// =============================================================================

describe("scheduled-github-app-drift-guard.yml — failure routing", () => {
  test("record_failure helper writes failure_mode + failure_detail + failure_label", () => {
    const yaml = readFileSync(workflowPath, "utf-8");
    const fnBody = extractFunctionBody(yaml, "record_failure");
    // All three outputs must be set inside record_failure (or via captured
    // shell vars referenced after it). The 3-output shape (Kieran P0-2) is
    // what lets the issue-creation step dispatch on `failure_label`.
    expect(fnBody).toMatch(/\bfailure_mode\b/);
    expect(fnBody).toMatch(/\bfailure_detail\b/);
    expect(fnBody).toMatch(/\bfailure_label\b/);
  });

  test("record_failure is first-failure-wins (matches oauth-probe pattern)", () => {
    const yaml = readFileSync(workflowPath, "utf-8");
    const fnBody = extractFunctionBody(yaml, "record_failure");
    // The oauth-probe pattern: only set state if not already set. Prevents
    // a downstream failure mode from overwriting the upstream root cause.
    expect(fnBody).toMatch(/if\s+\[\[\s*-z\s+["']?\$failure_mode/);
  });

  test("workflow uses all three issue title prefixes", () => {
    const yaml = readFileSync(workflowPath, "utf-8");
    expect(yaml).toContain(ISSUE_TITLE_PREFIX_AUTH_BROKEN);
    expect(yaml).toContain(ISSUE_TITLE_PREFIX_GUARD_BROKEN);
    expect(yaml).toContain(ISSUE_TITLE_PREFIX_LEAK_SUSPECTED);
  });

  test("dedup search scopes to drift-guard (no collision with oauth-probe)", () => {
    const yaml = readFileSync(workflowPath, "utf-8");
    // The search must include the literal token `drift-guard` so dedup is
    // scoped to this workflow only; oauth-probe issues use the same labels
    // (`ci/auth-broken`) but their titles do not contain `drift-guard`.
    expect(yaml).toMatch(/in:title\s+["']*drift-guard/);
  });

  test("idempotent label create for both new labels", () => {
    const yaml = readFileSync(workflowPath, "utf-8");
    // The pattern `gh label create … 2>/dev/null || true` is the load-bearing
    // idempotency idiom — see scheduled-oauth-probe.yml:436-438 precedent.
    expect(yaml).toMatch(/gh\s+label\s+create\s+ci\/guard-broken[\s\S]+?(\|\|\s*true|2>\/dev\/null)/);
    expect(yaml).toMatch(/gh\s+label\s+create\s+security\/leak-suspected[\s\S]+?(\|\|\s*true|2>\/dev\/null)/);
  });
});

// =============================================================================
// API call contract — curl with JWT in env (NOT gh api with JWT GH_TOKEN)
// =============================================================================

describe("scheduled-github-app-drift-guard.yml — gh api /app via curl", () => {
  test("API call uses curl, not `gh api` with JWT", () => {
    // Per Kieran P1-2: `gh api` sends `Authorization: token <value>`, not
    // `Bearer <value>`. App-JWT endpoints (/app, /app/installations) require
    // Bearer. Using `gh api` with a JWT silently 401s.
    const yaml = readFileSync(workflowPath, "utf-8");
    // Positive: must hit api.github.com/app via curl
    expect(yaml).toContain("https://api.github.com/app");
    expect(yaml).toMatch(/curl[\s\S]+?api\.github\.com\/app/);
    // Negative: must not call `gh api /app`
    expect(yaml).not.toMatch(/gh\s+api\s+\/app(\s|$)/m);
  });

  test("curl pins --max-time to bound network calls", () => {
    const yaml = readFileSync(workflowPath, "utf-8");
    // Per Sharp Edge: any `dig`/`curl` in CI must pin a timeout to prevent
    // hung jobs.
    expect(yaml).toMatch(/curl[\s\S]+?--max-time\s+\d+[\s\S]+?api\.github\.com\/app/);
  });

  test("Authorization: Bearer is present (not Authorization: token)", () => {
    const yaml = readFileSync(workflowPath, "utf-8");
    // GitHub App JWT requires Bearer scheme.
    expect(yaml).toContain("Authorization: Bearer");
  });
});

// =============================================================================
// JWT mint correctness — decode and verify with ephemeral keypair
// =============================================================================

describe("scheduled-github-app-drift-guard.yml — JWT mint correctness", () => {
  test("mint_jwt function exists in workflow", () => {
    const yaml = readFileSync(workflowPath, "utf-8");
    // Must be extractable — both for this test and for runbook references.
    expect(() => extractFunctionBody(yaml, "mint_jwt")).not.toThrow();
  });

  test("b64url helper exists and uses base64 -w 0 + tr -d '=\\n'", () => {
    const yaml = readFileSync(workflowPath, "utf-8");
    const fnBody = extractFunctionBody(yaml, "b64url");
    // Per Kieran P1-1: openssl base64 -A trails newline that tr -d '='
    // doesn't strip. Use coreutils base64 -w 0 (no wrap) + strip both =
    // padding AND any stray newline.
    expect(fnBody).toContain("base64 -w 0");
    expect(fnBody).toMatch(/tr\s+(?:-d\s+)?["']\+\/["']\s+["']-_["']/);
    expect(fnBody).toMatch(/tr\s+-d\s+["']=\\?n["']/);
  });

  test("minted JWT has well-formed segments and verifies under RS256", () => {
    // Generate ephemeral RSA keypair. Write private key to a temp PEM.
    // Extract the workflow's b64url + mint_jwt functions. Spawn bash with
    // them, set APP_ID + KEY_FILE env, capture the JWT from stdout.
    // Decode + verify with the ephemeral public key.
    const yaml = readFileSync(workflowPath, "utf-8");
    const b64urlBody = extractFunctionBody(yaml, "b64url");
    const mintBody = extractFunctionBody(yaml, "mint_jwt");

    const { privateKey, publicKey } = generateKeyPairSync("rsa", {
      modulusLength: 2048,
    });
    const privPem = privateKey.export({ type: "pkcs8", format: "pem" }) as string;

    const keyFile = path.join(tmpdir(), `gh-app-drift-guard-test-${process.pid}.pem`);
    writeFileSync(keyFile, privPem, { mode: 0o600 });

    try {
      const APP_ID = "12345";
      // Spawn bash with both function definitions, then call mint_jwt.
      // mint_jwt is expected to output the JWT (and only the JWT) on stdout.
      const script = `${b64urlBody}\n${mintBody}\nmint_jwt`;
      const out = spawnSync("bash", ["-c", script], {
        env: {
          ...process.env,
          APP_ID,
          KEY_FILE: keyFile,
          PATH: process.env.PATH ?? "",
        },
        encoding: "utf-8",
      });

      expect(out.status, `mint_jwt exited non-zero: ${out.stderr}`).toBe(0);
      const jwt = out.stdout.trim();

      // Three segments separated by `.`
      const parts = jwt.split(".");
      expect(parts.length, `JWT must have 3 segments, got ${parts.length}`).toBe(3);

      // No literal newline in any segment (Kieran P1-1 verification)
      parts.forEach((p, i) => {
        expect(p, `JWT segment ${i} contains a literal newline`).not.toContain("\n");
        expect(p, `JWT segment ${i} contains a literal carriage return`).not.toContain("\r");
      });

      // Header decode
      const header = JSON.parse(Buffer.from(parts[0], "base64url").toString());
      expect(header.alg).toBe("RS256");
      expect(header.typ).toBe("JWT");

      // Payload decode
      const payload = JSON.parse(Buffer.from(parts[1], "base64url").toString());
      expect(payload.iss).toBe(Number(APP_ID));
      const now = Math.floor(Date.now() / 1000);
      expect(payload.iat).toBeLessThanOrEqual(now);
      expect(payload.exp).toBeGreaterThan(now);
      // Exp - iat should be 600s (9-min forward + 60s back-buffer = 540 + 60).
      expect(payload.exp - payload.iat).toBe(600);

      // Signature verify
      const signingInput = Buffer.from(`${parts[0]}.${parts[1]}`);
      const signature = Buffer.from(parts[2], "base64url");
      const pub = createPublicKey(publicKey);
      const valid = cryptoVerify("RSA-SHA256", signingInput, pub, signature);
      expect(valid, "minted JWT signature did not verify under the ephemeral public key").toBe(true);
    } finally {
      try {
        unlinkSync(keyFile);
      } catch {
        // best effort cleanup
      }
    }
  });
});

// =============================================================================
// Defensive denials — no upload-artifact, no set -x with PEM/JWT in env
// =============================================================================

describe("scheduled-github-app-drift-guard.yml — defensive denials", () => {
  test("workflow does NOT use actions/upload-artifact", () => {
    const yaml = readFileSync(workflowPath, "utf-8");
    // Uploading the tee'd step-output.log would re-create the leak class
    // the tripwire is meant to detect. CODEOWNERS gates future additions.
    expect(yaml).not.toContain("actions/upload-artifact");
  });

  test("no `set -x` appears in any step that has PRIVATE_KEY_B64 or JWT in env", () => {
    const yaml = readFileSync(workflowPath, "utf-8");
    // `set -x` would echo every shell command including expanded env vars,
    // bypassing `::add-mask::` for the duration. Belt-and-suspenders to the
    // mask discipline.
    expect(yaml).not.toMatch(/set\s+-x/);
  });
});

// =============================================================================
// Negative-control fixture — synthesized /app response does NOT trip tripwire
// =============================================================================

describe("leak-tripwire regex semantics — negative control", () => {
  // Inline synthesized fixture per cq-test-fixtures-synthesized-only.
  // No real client_id, no live JWT, no production tokens.
  const FAKE_APP_RESPONSE = JSON.stringify({
    id: 12345,
    client_id: "Iv1.synthesized00000",
    slug: "test-app",
    node_id: "MDM6QXBwTm9kZQ==",
    owner: { login: "test-org", id: 99999 },
    name: "Test App",
    description: "Synthesized fixture for drift-guard contract test",
    external_url: "https://example.test",
    html_url: "https://github.com/apps/test-app",
    created_at: "2026-01-01T00:00:00Z",
    updated_at: "2026-01-01T00:00:00Z",
    permissions: { contents: "read", issues: "write" },
    events: [],
  });

  test("synthesized /app response does NOT match the PEM tripwire", () => {
    const re = new RegExp(LEAK_TRIPWIRE_PEM_REGEX);
    expect(FAKE_APP_RESPONSE).not.toMatch(re);
  });

  test("synthesized /app response does NOT match the JWT tripwire", () => {
    // Note: `node_id: "MDM6QXBwTm9kZQ=="` is base64-encoded but does NOT
    // start with `eyJ` and is shorter than 20 chars after the prefix —
    // verify the regex's anchoring catches both class boundaries.
    const re = new RegExp(LEAK_TRIPWIRE_JWT_REGEX);
    expect(FAKE_APP_RESPONSE).not.toMatch(re);
  });

  test("a real PEM block DOES match the PEM tripwire (positive control)", () => {
    const re = new RegExp(LEAK_TRIPWIRE_PEM_REGEX);
    expect("-----BEGIN RSA PRIVATE KEY-----").toMatch(re);
    expect("-----BEGIN PRIVATE KEY-----").toMatch(re);
    expect("-----BEGIN OPENSSH PRIVATE KEY-----").toMatch(re);
    // Public key MUST NOT match — the tripwire is for private key blocks only.
    expect("-----BEGIN PUBLIC KEY-----").not.toMatch(re);
  });

  test("a real JWT-shaped string DOES match the JWT tripwire (positive control)", () => {
    const re = new RegExp(LEAK_TRIPWIRE_JWT_REGEX);
    // 30+ char base64url after eyJ — well-formed JWT header prefix
    expect("eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9").toMatch(re);
    // Short (< 20 chars after eyJ) does NOT match — avoids false-positives
    // on `eyJ`-prefixed prose / log fragments.
    expect("eyJabc").not.toMatch(re);
  });
});
