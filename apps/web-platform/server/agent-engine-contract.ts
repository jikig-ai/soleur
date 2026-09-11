/** Web execution contract. Plugin invocation harnesses have a separate registry.
 * Native protocol types and credentials stay inside adapters and their leases.
 */
export type AgentEngineId = string;
export type EngineCapability =
  | "streaming" | "approvals" | "platform-tools" | "continuation"
  | "cancellation" | "attachments" | "workspace" | "usage" | "artifacts";
export type CapabilityStatus = "unsupported" | "supported" | "verified";
export type EngineDataClass = "synthetic" | "customer";

export interface EngineQualification {
  authMode: string;
  adapterVersion: string;
  workflow: string;
  dataClass: EngineDataClass;
  expiresAt: number;
  evidenceRef: string;
  capabilities: Partial<Record<EngineCapability, CapabilityStatus>>;
}

export interface EngineDefinition {
  id: AgentEngineId;
  version: string;
  transport: "local" | "remote";
  enabledForNewRuns: boolean;
  enabledForExistingRuns: boolean;
  authModes: string[];
  qualifications: EngineQualification[];
}

/** Constructed by shared policy from authenticated context and persisted state;
 * never from a client-provided dispatch configuration.
 */
export interface EngineSelection {
  engineId: AgentEngineId;
  authMode: string;
  operation: "new-run" | "existing-run";
  workflow: string;
  dataClass: EngineDataClass;
  requiredCapabilities: readonly EngineCapability[];
  now: number;
}

export type EngineExecution =
  | { kind: "conversation"; conversationId: string }
  | { kind: "routine"; routineId: string; routineRunId: string };

/** Non-secret durable record; a default change never rewrites this binding. */
export interface EngineBinding {
  workspaceId: string;
  execution: EngineExecution;
  engineId: AgentEngineId;
  authMode: string;
  adapterVersion: string;
  boundAt: string;
}

export type EngineRunStatus =
  | "queued" | "running" | "waiting" | "cancel_requested"
  | "completed" | "failed" | "cancelled";

export interface NativeSessionReference {
  /** Opaque resume handle, never logged or rendered. */
  resumeHandle: string;
  /** Native live-session identity may differ from the resume handle. */
  sessionId: string | null;
}

export interface EngineUsage {
  native: { unit: string; value: number }[];
  cost:
    | { provenance: "reported" | "estimated"; amount: number; currency: string }
    | { provenance: "unavailable" };
}

export type EngineEventPayload =
  | { type: "status"; status: EngineRunStatus }
  | { type: "text"; text: string }
  | { type: "progress"; message: string }
  | { type: "approval"; requestId: string; tool: string; description: string }
  | { type: "artifact"; artifactId: string; revision: string }
  | { type: "usage"; usage: EngineUsage }
  | { type: "error"; code: string; retryable: boolean };

export interface EngineEvent {
  runId: string;
  eventId: string;
  sequence: number;
  payload: EngineEventPayload;
}

export interface EngineRunContext {
  runId: string;
  binding: EngineBinding;
  idempotencyKey: string;
  signal: AbortSignal;
}

export interface EngineInput {
  text: string;
  attachmentIds: readonly string[];
}

/** Concrete adapters enforce shared policy through injected server-side services.
 * Resolving an engine definition alone does not authorize execution.
 */
export interface EngineAdapter {
  start(context: EngineRunContext, input: EngineInput): AsyncIterable<EngineEvent>;
  continue(context: EngineRunContext, session: NativeSessionReference, input: EngineInput): AsyncIterable<EngineEvent>;
  cancel(context: EngineRunContext, session: NativeSessionReference): Promise<"requested" | "confirmed">;
  reconcile(context: EngineRunContext, session: NativeSessionReference): Promise<EngineRunStatus>;
  resumeFromCursor(context: EngineRunContext, cursor: string | null): AsyncIterable<EngineEvent>;
  respondToApproval(context: EngineRunContext, requestId: string, decision: "allow" | "deny"): Promise<void>;
  erase(context: EngineRunContext, session: NativeSessionReference): Promise<"confirmed" | "unsupported">;
  dispose(): Promise<void>;
}
