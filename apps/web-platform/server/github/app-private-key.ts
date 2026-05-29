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
