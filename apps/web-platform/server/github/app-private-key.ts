import { createPrivateKey } from "crypto";

// Canonicalize the GitHub App private key to a clean LF-only PKCS#8 PEM BEFORE
// handing it to @octokit/app. Shared by every `new App({ privateKey })` site
// (createProbeOctokit / createAppJwtOctokit in probe-octokit.ts, and the
// founder-facing createGitHubAppClient in app-client.ts) so they all mint JWTs
// from the same normalized key.
//
// @octokit/app mints its App JWT via universal-github-app-jwt@2.2.2, whose
// getDERfromPEM() does `pem.trim().split("\n").slice(1,-1).join("")` + atob.
// That extraction corrupts the DER when the PEM carries CRLF line endings
// (every body line keeps a trailing \r) or arrives as a single line with
// literal `\n` separators (a common Doppler/Docker env-var encoding) —
// surfacing as GitHub's opaque "A JSON web token could not be decoded"
// (Sentry 4e6a3003…). On the Node runtime the library already auto-converts
// PKCS#1→PKCS#8 itself, so format is not the operative bug; line endings are.
//
// Node's createPrivateKey().export() is whitespace/format-tolerant (the same
// crypto module the sibling github-app.ts signs through) and re-emits exactly
// the one-header / body / one-footer single-trailing-LF PEM that slice(1,-1)
// expects — fixing CRLF and escaped-\n while harmlessly normalizing PKCS#1 too.
export function normalizeAppPrivateKey(raw: string): string {
  const pem = raw.replace(/\\n/g, "\n"); // expand escaped \n (env/Doppler)
  return createPrivateKey(pem)
    .export({ type: "pkcs8", format: "pem" })
    .toString();
}

// Canonicalize + validate the GitHub App ID before it becomes the JWT `iss`.
// Shared by every `new App({ appId })` site (createProbeOctokit /
// createAppJwtOctokit in probe-octokit.ts, createGitHubAppClient in
// app-client.ts) and by the hand-rolled signer's getAppId() in github-app.ts,
// so all App-JWT paths derive `iss` from the same validated value.
//
// @octokit/app and universal-github-app-jwt@2.2.2 accept `appId: number | string`
// and NEVER validate it (types: `appId?: number | string`); the library sets
// `iss: id` verbatim. So a whitespace-laden or client-id-shaped GITHUB_APP_ID is
// silently signed into the JWT, and GitHub is the only validator — it returns the
// opaque "A JSON web token could not be decoded" with no hint at the cause.
// Sentry 00bdfdf1… fired on a prod GITHUB_APP_ID of "3261325\n" (correct numeric
// App ID, trailing newline). normalizeAppPrivateKey fixes the KEY; this guard is
// the only pre-GitHub catch point for the APP ID.
//
// Whitespace surrounding an otherwise-numeric value is RECOVERABLE — trimmed and
// used (matching normalizeAppPrivateKey's silent \n-expansion). A non-numeric
// value (the client_id-confusion class) is UNRECOVERABLE — thrown loud and
// self-explaining so the next recurrence reads its own cause instead of GitHub's
// opaque error.
export function readAppId(raw: string): string {
  const id = raw.trim();
  if (!/^[0-9]+$/.test(id)) {
    const shape = /^Iv\d/.test(id)
      ? "a client_id-shaped value — this looks like the GitHub App's client_id, not its numeric App ID"
      : id.length === 0
        ? "an empty/whitespace-only value"
        : "a non-numeric value";
    throw new Error(
      `GITHUB_APP_ID must be the numeric GitHub App ID (e.g. "3261325"), got ${shape}. ` +
        `A non-numeric App ID is signed verbatim into the JWT \`iss\` and GitHub ` +
        `rejects it as the opaque "A JSON web token could not be decoded".`,
    );
  }
  return id;
}
