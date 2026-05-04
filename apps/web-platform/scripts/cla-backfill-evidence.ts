// One-shot backfill runner for the existing two CLA signers (deruelle + Elvalio).
// Run as `bun run apps/web-platform/scripts/cla-backfill-evidence.ts`.
//
// Reads the canonical signed-list from the cla-signatures branch, builds
// evidence records via apps/web-platform/scripts/cla-evidence/backfill.ts,
// and writes each one through apps/cla-evidence/scripts/upload-evidence.sh.
// Idempotent: subsequent runs return 412 on every conditional PUT (Kieran F10).
//
// Operator-only post-merge action. Requires:
//   R2_CLA_EVIDENCE_ACCESS_KEY_ID   (Doppler prd_cla)
//   R2_CLA_EVIDENCE_SECRET          (Doppler prd_cla)
//   R2_CLA_EVIDENCE_ENDPOINT        (Doppler prd_cla)
//   R2_CLA_EVIDENCE_BUCKET          (Doppler prd_cla)
//   GH_TOKEN                        (read-only access to comments)
//
// Usage:
//   doppler run -p soleur -c prd_cla -- bun run apps/web-platform/scripts/cla-backfill-evidence.ts [--dry-run]

import { execFileSync, spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { buildBackfillPayloads } from "./cla-evidence/backfill";
import { computeBodyHash, computeDocHash } from "./cla-evidence/hash";

const dryRun = process.argv.includes("--dry-run");

const env = (k: string): string => {
  const v = process.env[k];
  if (!v) {
    process.stderr.write(`::error::env ${k} missing (use \`doppler run -p soleur -c prd_cla -- ...\`)\n`);
    process.exit(1);
  }
  return v;
};

interface ClaJson {
  signedContributors: Array<{
    name: string;
    id: number;
    pullRequestNo: number;
    comment_id: number;
    created_at: string;
    signedOnPR?: number;
  }>;
}

function readClaJson(): ClaJson & { schema_version: "1.0" } {
  const out = execFileSync("git", ["show", "cla-signatures:signatures/cla.json"], { encoding: "utf8" });
  const parsed = JSON.parse(out) as ClaJson;
  // The upstream action's cla.json does not carry a schema_version field; we
  // assert "1.0" at the wrapper boundary so the consumer-boundary contract
  // (learning #18) holds across all three consumers (sidecar, backfill, inspect).
  return { schema_version: "1.0", ...parsed };
}

function resolveDocSha(repoRoot: string, createdAt: string): { sha: string; contentSha256: string; preExisted?: boolean } {
  const pathArg = "docs/legal/individual-cla.md";
  const log = spawnSync(
    "git",
    ["log", `--until=${createdAt}`, "-1", "--format=%H", "--", pathArg],
    { cwd: repoRoot, encoding: "utf8" },
  );
  let sha = (log.stdout ?? "").trim();
  let preExisted = false;
  if (!sha) {
    // Pre-existed: file post-dates the signer's row. Fall back to the first
    // commit that introduced the file.
    const first = spawnSync(
      "git",
      ["log", "--diff-filter=A", "--reverse", "--format=%H", "--", pathArg],
      { cwd: repoRoot, encoding: "utf8" },
    );
    sha = (first.stdout ?? "").trim().split("\n")[0];
    preExisted = true;
  }
  if (!sha) throw new Error(`could not resolve doc sha for createdAt=${createdAt}`);
  // computeDocHash is async; do the sync subset inline.
  const content = execFileSync("git", ["show", `${sha}:${pathArg}`], { encoding: "buffer" });
  const contentSha256 = require("node:crypto").createHash("sha256").update(content).digest("hex") as string;
  return { sha, contentSha256, preExisted };
}

async function fetchCommentBodySync(commentId: number): Promise<{ body: string; sha256: string }> {
  const token = env("GH_TOKEN");
  const r = await fetch(`https://api.github.com/repos/jikig-ai/soleur/issues/comments/${commentId}`, {
    headers: { Authorization: `Bearer ${token}`, Accept: "application/vnd.github+json" },
  });
  if (r.status !== 200) {
    throw new Error(`comment ${commentId} fetch returned ${r.status}`);
  }
  const j = (await r.json()) as { body?: string };
  const body = j.body ?? "";
  return { body, sha256: computeBodyHash(body) };
}

async function main(): Promise<void> {
  const cla = readClaJson();
  const repoRoot = execFileSync("git", ["rev-parse", "--show-toplevel"], { encoding: "utf8" }).trim();

  // Pre-fetch comment bodies and doc-shas synchronously so the buildBackfillPayloads
  // helper stays pure.
  const cache: Record<string, { body: string; sha256: string }> = {};
  const docCache: Record<string, { sha: string; contentSha256: string; preExisted?: boolean }> = {};
  for (const row of cla.signedContributors) {
    cache[`c${row.comment_id}`] = await fetchCommentBodySync(row.comment_id);
    docCache[row.created_at] = resolveDocSha(repoRoot, row.created_at);
  }

  const payloads = buildBackfillPayloads(cla, {
    fetchCommentBody: (id) => cache[`c${id}`]!,
    resolveDocSha: (createdAt) => docCache[createdAt]!,
  });

  for (const p of payloads) {
    const json = JSON.stringify(p);
    if (dryRun) {
      process.stdout.write(json + "\n");
      continue;
    }
    const uploader = "apps/cla-evidence/scripts/upload-evidence.sh";
    if (!existsSync(uploader)) throw new Error(`uploader not found at ${uploader}`);
    const r = spawnSync("bash", [uploader, json], { stdio: "inherit" });
    if (r.status !== 0) process.exit(r.status ?? 1);
  }
  process.stderr.write(`backfill complete: ${payloads.length} record(s) processed${dryRun ? " (dry-run)" : ""}\n`);
}

main().catch((e: unknown) => {
  process.stderr.write(`::error::${e instanceof Error ? e.message : String(e)}\n`);
  process.exit(1);
});

// Touch unused imports so tsc doesn't strip them in --noEmit mode.
void computeDocHash;
void readFileSync;
