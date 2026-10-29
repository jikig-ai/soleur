/**
 * The injected dependency of the gated branch for the approval flow (#4672). Types only, so `permission-callback.ts`
 * and its unit tests depend on this shape, not on Supabase. The production factory is `gate.ts`.
 *
 * Absence of `deps.approval` is the dormant state: the gated branch is then byte-identical to the in-memory review
 * gate (ADR-305).
 */

import type { ServerDerived } from "./canonical";
import type { ExecutionGrants } from "./grants";
import type { ConsumeResult, CreateApprovalParams, SubmitResult } from "./service";
import type { WaitDeps, WaitStatus } from "./waiters";

export interface ApprovalGateDeps {
  /** The flag seam, evaluated ONCE per gate. A throw or `false` means the old path; it never turns the flow on. */
  isEnabled(): Promise<boolean>;
  /** Workspace the conversation runs in (the hash and the row are bound to it). */
  workspaceId: string;
  /**
   * The per-session execution-grant object, shared by closure with the tool builders (#4672 R1). The gate marks it
   * `enforcing` once the flag is on and writes a one-shot grant right before each `allow()`.
   */
  grants: ExecutionGrants;
  /**
   * Fields the model cannot supply and the executed action depends on (email_reply recipient, repository, workspace
   * HEAD). A throw denies: an action whose bound fields cannot be resolved is never approvable.
   */
  resolveServerDerived(toolName: string, snapshot: Record<string, unknown>): Promise<ServerDerived | undefined>;
  /** Create-or-find the live request; an already-approved live row is consumed at once (service client). */
  submit(p: CreateApprovalParams): Promise<SubmitResult>;
  /** One indexed read of the row status; null = not found (treated as still pending by the wait loop). */
  readStatus(approvalId: string): Promise<WaitStatus | null>;
  /** Fail closed: only `{consumed: true}` from the database is an allow. */
  consume(p: { id: string; hash: string; conversationId: string }): Promise<ConsumeResult>;
  /** Role of the requester in the workspace; the owner can decide, a member sees a read-only waiting card. Failure = member. */
  viewerRole(): Promise<"owner" | "member">;
  /**
   * Optional best-effort side channel after a request is created (the push dispatch). `notify` is the database's
   * coalescing verdict (a new request with no other pending request created in the last 10 minutes); `expiresAt` goes
   * into the notification copy so no table read is needed. A throw or a slow dispatch is reported, never fatal.
   */
  onRequested?(p: { approvalId: string; created: boolean; notify: boolean; expiresAt: string }): Promise<void>;
  /** Test seam: deadline of the `onRequested` dispatch (the gate never waits on a push longer than this). */
  onRequestedDeadlineMs?: number;
  /** Test seam: deadline, clock, sleep and jitter of the wait loop. */
  waitOptions?: Partial<Pick<WaitDeps, "deadlineMs" | "now" | "sleep" | "random">>;
}
