// Reproduce harness for feat-one-shot-concierge-gh-403-token-diagnosis.
//
// PROVES the Concierge "403 on every gh call" is a WRONG-INSTALLATION token,
// NOT a missing `issues:write` scope. It mints a token for EVERY GitHub App
// installation, then probes whether that token can read the connected org repo
// (`jikig-ai/soleur` by default). The signature of the bug:
//
//   - the PERSONAL-account installation token → 403 "Resource not accessible by
//     integration" on GET /repos/jikig-ai/soleur (and on every other org-repo
//     call), despite having full `issues:write` etc. in its `permissions`.
//   - the ORG installation token (122213433) → 200, repository_selection
//     covering the repo.
//
// A scope gap would 403 ONLY on issues endpoints; a wrong-installation token
// 403s on ALL endpoints including this plain repo GET — which is exactly what
// the screenshot evidence shows.
//
// Path follows the in-tree spike convention (`scripts/spike/<name>.ts`, Node 22
// via tsx, NOT Bun — production worker is `next start` on Node 22). Reads ONLY
// non-secret metadata into stdout; the token VALUE is never printed
// (hr-github-app-auth-not-pat). This is a one-off diagnostic, NOT prod runtime.
//
// Operator command:
//   doppler run -p soleur -c dev -- ./node_modules/.bin/tsx \
//     scripts/spike/reproduce-gh-403.ts
//
// Optional env knobs:
//   GH_403_TARGET_REPO="jikig-ai/soleur"   # owner/repo to probe (default)

import { createSign } from "node:crypto";

const GITHUB_API = "https://api.github.com";
const TARGET = process.env.GH_403_TARGET_REPO ?? "jikig-ai/soleur";
const [TARGET_OWNER, TARGET_REPO] = TARGET.split("/");

function base64url(input: Buffer): string {
  return input
    .toString("base64")
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}

// Self-contained App-JWT signer mirroring github-app.ts createAppJwt (kept
// internal to the runtime module; replicated here so the spike does not widen
// the prod export surface).
function createAppJwt(): string {
  const appId = process.env.GITHUB_APP_ID;
  const rawKey = process.env.GITHUB_APP_PRIVATE_KEY;
  if (!appId) throw new Error("GITHUB_APP_ID is not set");
  if (!rawKey) throw new Error("GITHUB_APP_PRIVATE_KEY is not set");
  const pem = rawKey.replace(/\\n/g, "\n");

  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const payload = { iss: appId.trim(), iat: now - 60, exp: now + 9 * 60 };
  const signingInput = `${base64url(
    Buffer.from(JSON.stringify(header)),
  )}.${base64url(Buffer.from(JSON.stringify(payload)))}`;
  const signer = createSign("RSA-SHA256");
  signer.update(signingInput);
  signer.end();
  return `${signingInput}.${base64url(signer.sign(pem))}`;
}

function ghHeaders(auth: string): HeadersInit {
  return {
    Authorization: auth,
    Accept: "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
  };
}

interface AppInstallation {
  id: number;
  account: { login: string; type: string } | null;
}

interface AccessTokenResponse {
  token: string;
  expires_at: string;
  repository_selection?: "all" | "selected";
  permissions?: Record<string, string>;
}

async function main(): Promise<void> {
  console.log(`\n=== reproduce-gh-403 — probing access to ${TARGET} ===\n`);

  const jwt = createAppJwt();

  // 1. List every installation of this App.
  const installsRes = await fetch(
    `${GITHUB_API}/app/installations?per_page=100`,
    { headers: ghHeaders(`Bearer ${jwt}`) },
  );
  if (!installsRes.ok) {
    console.error(
      `FATAL: GET /app/installations → ${installsRes.status}: ${(
        await installsRes.text()
      ).slice(0, 300)}`,
    );
    process.exit(1);
  }
  const installations = (await installsRes.json()) as AppInstallation[];
  console.log(`Found ${installations.length} installation(s).\n`);

  let owningInstall: number | null = null;
  let wrongInstallWith403 = false;

  // 2. For each installation: mint a token, capture repository_selection +
  //    permission keys, then read-probe the target repo.
  for (const inst of installations) {
    const acct = inst.account
      ? `${inst.account.login} (${inst.account.type})`
      : "(unknown account)";
    console.log(`--- installation ${inst.id} — ${acct} ---`);

    const mintRes = await fetch(
      `${GITHUB_API}/app/installations/${inst.id}/access_tokens`,
      { method: "POST", headers: ghHeaders(`Bearer ${jwt}`) },
    );
    if (!mintRes.ok) {
      console.log(
        `  mint → ${mintRes.status}: ${(await mintRes.text()).slice(0, 200)}\n`,
      );
      continue;
    }
    const data = (await mintRes.json()) as AccessTokenResponse;
    const permissionKeys = Object.keys(data.permissions ?? {}).sort();
    console.log(`  repository_selection: ${data.repository_selection}`);
    console.log(`  permission keys: ${permissionKeys.join(", ")}`);
    console.log(
      `  issues permission: ${data.permissions?.issues ?? "(absent)"}`,
    );

    // 3. Read-probe the target org repo with this installation's token
    //    (avoids issue residue — a plain repo GET 403s identically to an
    //    issues POST when the installation lacks repo access).
    const repoRes = await fetch(
      `${GITHUB_API}/repos/${TARGET_OWNER}/${TARGET_REPO}`,
      { headers: ghHeaders(`token ${data.token}`) },
    );
    if (repoRes.ok) {
      owningInstall = inst.id;
      console.log(`  GET /repos/${TARGET} → ${repoRes.status} OK ✅ (owning install)\n`);
    } else {
      const body = await repoRes.text();
      let message = body.slice(0, 200);
      try {
        message = (JSON.parse(body) as { message?: string }).message ?? message;
      } catch {
        /* non-JSON body */
      }
      if (repoRes.status === 403) wrongInstallWith403 = true;
      console.log(
        `  GET /repos/${TARGET} → ${repoRes.status} ❌  message: "${message}"\n`,
      );
    }
  }

  // 4. Verdict
  console.log("=== verdict ===");
  if (owningInstall !== null) {
    console.log(`✅ owning installation for ${TARGET}: ${owningInstall}`);
  } else {
    console.log(`⚠️  NO installation could read ${TARGET}`);
  }
  if (wrongInstallWith403) {
    console.log(
      `✅ confirmed: at least one installation token 403s on a plain repo GET ` +
        `→ wrong-installation token, NOT an issues-scope gap.`,
    );
  }
  console.log(
    `\nIf the Concierge resolves a NON-owning installation id from ` +
      `workspaces.github_installation_id, every gh call 403s exactly as above.`,
  );
}

main().catch((err) => {
  console.error("reproduce-gh-403 failed:", err);
  process.exit(1);
});
