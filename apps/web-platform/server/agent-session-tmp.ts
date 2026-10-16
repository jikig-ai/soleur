import { createHash } from "node:crypto";

/** #10445 (CTO ruling 2026-10-16): the Agent SDK CLI persists every Bash command's output (a sibling's `env` included, with
 *  its per-session proxy credential) under `<CLAUDE_CODE_TMPDIR || tmpdir>/claude-<uid>/...`, and the vendored builder
 *  binds that whole dir writable into EVERY sandbox, so a shared one is a cross-tenant read channel that no `denyRead`
 *  closes (the covered allowWrite path is re-bound after the tmpfs). Each tenant therefore gets its own CLI temp base
 *  under this root, and the sandbox config denies the root: only the session's own `<root>/<id>/claude-<uid>` survives
 *  (the builder restores it as the CLI's own allowWrite). The per-uid dir must stay <= 44 bytes or the CLI silently
 *  falls back to the SHARED `<tmpdir>/claude-<uid>` for children (pinned in agent-runner-helpers.test.ts). */
export const AGENT_SESSION_TMP_ROOT = "/tmp/.cs";
export function agentSessionTmpDir(tenantKey: string): string {
  return `${AGENT_SESSION_TMP_ROOT}/${createHash("sha256").update(tenantKey).digest("hex").slice(0, 16)}`;
}
