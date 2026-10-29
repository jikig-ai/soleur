/**
 * Per-session execution grants (#4672, CTO ruling 1): the narrow side channel that carries what the Owner approved from
 * the gate to the tool handler that executes it.
 *
 * Why: the approval binds identifiers (and, for a push, the commit), but three handlers re-resolve something at execution
 * (`github_push_branch` pushes the workspace HEAD, `workspace_set_autonomous` and `kb_share_create` resolve the active
 * workspace). The tool zod strips extra keys and an SDK tool handler gets no reliable `tool_use_id`, so a pinned value
 * cannot ride in the tool input without letting the model supply it. This object is created once per session in
 * `agent-runner.ts` and shared BY CLOSURE between `createApprovalGateDeps` (writer) and the tool builders (readers). No
 * MCP tool exposes it and the Bash sandbox holds no handle to it, so the model cannot write a grant.
 *
 * Contract:
 *  - The gate `put`s a grant immediately before `allow()` on BOTH allow paths (live consume and re-proposal release).
 *  - A handler `take`s it once (one-shot), keyed by `handlerArgsKey(tool, zodParsedArgs)`.
 *  - `enforcing` goes true the first time the flag evaluates true in the session and never goes back (sticky): from then
 *    on a handler that finds no grant REFUSES instead of falling back to the legacy path, so a flag turned off
 *    mid-session cannot reopen the drift. While it is false (flag never on) handlers behave exactly as before.
 *  - Grants expire after 120 s and the map holds at most 64 entries (oldest dropped), so a grant for a call the SDK never
 *    executed cannot linger or grow without bound.
 *
 * Gate side only. Never imports the decide path.
 */

import { handlerArgsKey } from "./canonical";

export interface ExecutionBinding {
  /** The workspace the approval was granted in (the hash binds it). */
  workspaceId: string;
  /** For `github_push_branch`: the exact commit the Owner approved. */
  headSha?: string;
}

export const GRANT_TTL_MS = 120_000;
export const GRANT_MAX_ENTRIES = 64;

interface Entry {
  binding: ExecutionBinding;
  expiresAt: number;
}

export class ExecutionGrants {
  /** Sticky: true once the approval flow ran in this session. A missing grant then means refuse. */
  enforcing = false;

  private readonly entries = new Map<string, Entry>();

  constructor(private readonly now: () => number = Date.now) {}

  private static id(tool: string, argsKey: string): string {
    return `${tool}\u0000${argsKey}`;
  }

  put(tool: string, argsKey: string, binding: ExecutionBinding): void {
    const id = ExecutionGrants.id(tool, argsKey);
    // Re-insert so the entry is the newest (Map keeps insertion order; oldest = first key).
    this.entries.delete(id);
    this.entries.set(id, { binding: { ...binding }, expiresAt: this.now() + GRANT_TTL_MS });
    while (this.entries.size > GRANT_MAX_ENTRIES) {
      const oldest = this.entries.keys().next();
      if (oldest.done) break;
      this.entries.delete(oldest.value);
    }
  }

  /** Read once: the grant is deleted whether or not it was still valid. */
  take(tool: string, argsKey: string): ExecutionBinding | null {
    const id = ExecutionGrants.id(tool, argsKey);
    const e = this.entries.get(id);
    if (!e) return null;
    this.entries.delete(id);
    return e.expiresAt > this.now() ? e.binding : null;
  }

  size(): number {
    return this.entries.size;
  }
}

/** Convenience for the gate: key the grant by the model-supplied snapshot, exactly as a handler keys its zod args. */
export function putGrant(grants: ExecutionGrants, tool: string, snapshot: unknown, binding: ExecutionBinding): void {
  grants.put(tool, handlerArgsKey(tool, snapshot), binding);
}

/**
 * Outcome of a handler's grant check. `refuse` = the flow ran in this session but no grant matched (never run the
 * action). `legacy` = the approval flow never ran in this session, behave as before. `granted` = proceed with the binding.
 */
export type GrantCheck =
  | { kind: "legacy" }
  | { kind: "refuse" }
  | { kind: "granted"; binding: ExecutionBinding };

export function checkGrant(grants: ExecutionGrants | undefined, tool: string, args: unknown): GrantCheck {
  if (!grants) return { kind: "legacy" };
  let binding: ExecutionBinding | null = null;
  try {
    binding = grants.take(tool, handlerArgsKey(tool, args));
  } catch {
    binding = null;
  }
  if (binding) return { kind: "granted", binding };
  return grants.enforcing ? { kind: "refuse" } : { kind: "legacy" };
}

export const GRANT_MISSING_MESSAGE = "approval grant missing; ask again";
export const WORKSPACE_CHANGED_MESSAGE = "the active workspace changed after approval; ask again";
