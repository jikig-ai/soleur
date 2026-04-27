// Pending-prompt registry for the `/soleur:go` runner.
//
// Plan: knowledge-base/project/plans/2026-04-23-feat-cc-route-via-soleur-go-plan.md
// Stage 2 §"Pending-prompt registry" + HARD REQUIREMENT #4.
//
// When the soleur-go-runner forwards an interactive tool_use from the SDK
// (AskUserQuestion / ExitPlanMode / Edit / Write / Bash / TodoWrite /
// NotebookEdit), it emits an `interactive_prompt` WS event AND records
// the pending state here so a later `interactive_prompt_response` client
// message can be matched back to the SDK `tool_use_id` and replied to.
//
// Security invariants (the whole point of this module):
//
//   (a) Composite key `${userId}:${conversationId}:${promptId}` prevents
//       prompt-id collisions across conversations AND across users. The
//       SDK mints UUIDs, but we don't trust client-side mint.
//   (b) Ownership check on get/consume: a lookup whose `lookupUserId`
//       doesn't match the record's owner returns undefined. SILENT
//       denial — never reveal that a prompt with a given id exists but
//       belongs to someone else.
//   (c) Idempotency: consume() removes the record, so a retried
//       response is a no-op. The ws-handler layer maps the no-op to a
//       structured "already responded" error to the client.
//   (d) 5-minute TTL reaper: a user who vanishes mid-prompt cannot hold
//       SDK `tool_use_id`s open indefinitely.
//   (e) Per-conversation cap of 50: bounds memory + prevents a runaway
//       workflow from spawning unbounded prompts.
//
// V2 (tracked as V2-7): persist to `conversations.pending_prompts jsonb`
// so container restarts don't drop in-flight prompts. For V1, a
// container restart drops the Map and the user sees a session-reset
// notice on reconnect (documented in runner header and Stage 5.2
// runbook).

// Mirrors the WSMessage `interactive_prompt.kind` union (Stage 3). The
// registry itself is kind-agnostic — it stores whatever the runner
// records — but constraining the discriminant here gives typecheck
// coverage before the full WSMessage extension lands.
export type InteractivePromptKind =
  | "ask_user"
  | "plan_preview"
  | "diff"
  | "bash_approval"
  | "todo_write"
  | "notebook_edit";

import type { PromptId, ConversationId } from "@/lib/branded-ids";

export interface PendingPromptRecord {
  promptId: PromptId;
  conversationId: ConversationId;
  userId: string;
  kind: InteractivePromptKind;
  toolUseId: string;
  createdAt: number;
  payload: unknown;
}

export interface PendingPromptRegistryOptions {
  nowFn?: () => number;
  ttlMs?: number;
  perConversationCap?: number;
}

export class PendingPromptCapExceededError extends Error {
  constructor(public readonly conversationId: ConversationId, public readonly cap: number) {
    super(
      `Pending-prompt cap exceeded for conversation ${conversationId} (cap=${cap})`,
    );
    this.name = "PendingPromptCapExceededError";
  }
}

/**
 * Build the composite registry key. Branded IDs prevent the most common
 * cross-confusion mistake at this positional callsite — passing
 * `(userId, promptId, conversationId)` instead of `(userId, conversationId,
 * promptId)`. The brand makes the swap a compile error.
 */
export function makePendingPromptKey(
  userId: string,
  conversationId: ConversationId,
  promptId: PromptId,
): string {
  return `${userId}:${conversationId}:${promptId}`;
}

const DEFAULT_TTL_MS = 5 * 60 * 1000;
const DEFAULT_PER_CONVERSATION_CAP = 50;

export class PendingPromptRegistry {
  private readonly records = new Map<string, PendingPromptRecord>();
  private readonly nowFn: () => number;
  private readonly ttlMs: number;
  private readonly perConversationCap: number;

  constructor(opts: PendingPromptRegistryOptions = {}) {
    this.nowFn = opts.nowFn ?? (() => Date.now());
    this.ttlMs = opts.ttlMs ?? DEFAULT_TTL_MS;
    this.perConversationCap = opts.perConversationCap ?? DEFAULT_PER_CONVERSATION_CAP;
  }

  register(record: PendingPromptRecord): void {
    const countForConv = this.countByConversation(record.conversationId);
    if (countForConv >= this.perConversationCap) {
      throw new PendingPromptCapExceededError(
        record.conversationId,
        this.perConversationCap,
      );
    }
    const key = makePendingPromptKey(
      record.userId,
      record.conversationId,
      record.promptId,
    );
    this.records.set(key, record);
  }

  get(key: string, lookupUserId: string): PendingPromptRecord | undefined {
    const record = this.records.get(key);
    if (!record) return undefined;
    if (record.userId !== lookupUserId) return undefined;
    return record;
  }

  consume(key: string, lookupUserId: string): PendingPromptRecord | undefined {
    const record = this.get(key, lookupUserId);
    if (!record) return undefined;
    this.records.delete(key);
    return record;
  }

  reap(): number {
    const cutoff = this.nowFn() - this.ttlMs;
    let removed = 0;
    for (const [key, record] of this.records) {
      if (record.createdAt <= cutoff) {
        this.records.delete(key);
        removed++;
      }
    }
    return removed;
  }

  size(): number {
    return this.records.size;
  }

  private countByConversation(conversationId: string): number {
    let n = 0;
    for (const record of this.records.values()) {
      if (record.conversationId === conversationId) n++;
    }
    return n;
  }
}
