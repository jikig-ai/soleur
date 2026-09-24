// Server-private root for the C4 re-render's staging directories (#8623).
//
// NOT os.tmpdir(): the `likec4` child and the agent sandbox run as the same
// uid, so a staging root the sandbox could write would let an agent drop a
// likec4 config into a stage between staging and spawn. The agent sandbox's
// write set is its own workspace plus the SDK's implicit `/tmp/claude`,
// `~/.npm/_logs` and `~/.claude/debug` (measured from the SDK 0.3.197 binary,
// 2026-09-24), so a directory under `~/.cache` is outside it. It is also added
// to the sandbox `denyRead` set (agent-runner-sandbox-config.ts) so one
// tenant's agent cannot read another tenant's staged sources mid-render.
//
// Leaf module (node:os + node:path only) so the sandbox config can import it
// without pulling child_process or the GitHub client into its graph.
import { homedir } from "node:os";
import { join, resolve } from "node:path";

/** Resolved at call time so tests (and ops) can override it via env. */
export function c4RenderStagingRoot(): string {
  const fromEnv = process.env.C4_RENDER_STAGING_ROOT;
  if (fromEnv && fromEnv.trim()) return resolve(fromEnv);
  return join(homedir(), ".cache", "soleur-c4-render");
}
