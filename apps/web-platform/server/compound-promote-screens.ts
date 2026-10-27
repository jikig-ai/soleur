// The screens and the cluster hash shared by the compound-promote handler and the gated create arm (#10550).
//
// A LEAF module: it imports nothing from the app, so both `inngest/functions/cron-compound-promote.ts` and
// `compound-promote-create.ts` can depend on it without a cycle. The handler re-exports `PII_REGEX` and
// `CREDENTIAL_RE` so every existing importer (and test) keeps working; `createClusterHash` is this same function.
// `test/server/compound-promote-screens.test.ts` pins object identity across the three modules and the absence of
// any static import path from the create modules back to the handler.

import { createHash } from "node:crypto";

// Byte-for-byte port of PII_REGEX in scripts/compound-promote.sh.
// Unit-tested for parity (AC8). The shell copy's comment block carries the
// over-exclusion posture: the canonical credential class makes this gate
// slightly over-excluding -- a `gh[pousr]_<slug>`/`github_pat_<slug>`-shaped
// identifier in prose drops the learning (fail-closed toward the DPA-covered
// model call -- intended).
export const PII_REGEX = new RegExp(
  "([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,})" +
    "|([0-9]{1,3}(\\.[0-9]{1,3}){3})" +
    "|([A-Z]{2}[0-9]{2}[A-Z0-9]{4}[0-9]{7}([A-Z0-9]?){0,16})" +
    "|(eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+)" +
    "|(sk-ant-[A-Za-z0-9_-]{20,})" +
    "|(gh[pousr]_[A-Za-z0-9._~+/=-]{20,})|(github_pat_[A-Za-z0-9._~+/=-]{20,})" +
    "|(AKIA[0-9A-Z]{16})" +
    "|((sk|pk)_(live|test)_[A-Za-z0-9]{20,})" +
    "|(xox[baprs]-[A-Za-z0-9-]{10,})",
);

// The credential alternatives of PII_REGEX only (Anthropic key, JWT, GitHub tokens, AWS,
// Stripe, Slack). The email / IPv4 / IBAN alternatives over-match rule prose, and the
// committed text goes to a public repo, so the credential shapes are the ones that matter.
export const CREDENTIAL_RE = new RegExp(
  "(eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+)" +
    "|(sk-ant-[A-Za-z0-9_-]{20,})" +
    "|(gh[pousr]_[A-Za-z0-9._~+/=-]{20,})|(github_pat_[A-Za-z0-9._~+/=-]{20,})" +
    "|(AKIA[0-9A-Z]{16})" +
    "|((sk|pk)_(live|test)_[A-Za-z0-9]{20,})" +
    "|(xox[baprs]-[A-Za-z0-9-]{10,})" +
    // Not in PII_REGEX (its job is to keep personal data out of a prompt), but a private-key
    // header or a bearer credential in text bound for a public repo is the same class.
    "|(-----BEGIN [A-Z ]*PRIVATE KEY-----)|(Bearer[ \\t]+[A-Za-z0-9._~+/=-]{20,})",
);

/**
 * The cluster hash over a set of evidence keys: sha256 of the SORTED keys, newline-joined with a trailing newline.
 * The branch name, the PR title and the ledger all key on it, so the edit arm and the create arm MUST share it.
 */
export function computeClusterHash(sourceLearnings: readonly string[]): string {
  const sorted = [...sourceLearnings].sort();
  return createHash("sha256").update(sorted.join("\n") + "\n").digest("hex");
}
