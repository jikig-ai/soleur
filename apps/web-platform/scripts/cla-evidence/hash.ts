import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

/**
 * Read `<path>` at git revision `<sha>` from `<repoRoot>` and return the
 * SHA-256 hex of its byte content. Used by the sidecar to bind every evidence
 * record to the exact CLA document text that was in force at PR base SHA.
 */
export async function computeDocHash(
  repoRoot: string,
  sha: string,
  path: string,
): Promise<string> {
  const { stdout } = await execFileAsync("git", ["show", `${sha}:${path}`], {
    cwd: repoRoot,
    encoding: "buffer",
    maxBuffer: 8 * 1024 * 1024,
  });
  return createHash("sha256").update(stdout).digest("hex");
}

/** SHA-256 hex of a UTF-8 string (used for verbatim comment-body fingerprint). */
export function computeBodyHash(s: string): string {
  return createHash("sha256").update(s, "utf8").digest("hex");
}
