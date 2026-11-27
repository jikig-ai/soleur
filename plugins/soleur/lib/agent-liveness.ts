/**
 * Spawned-agent liveness monitoring and bounded recovery (#12524, ADR-332).
 *
 * Capability-tiered, metadata-only liveness classification and max-1 bounded
 * recovery for fan-out subagents across Claude Code, Grok Build, Codex, Devin,
 * Cursor, OpenCode, and Antigravity.
 *
 * Clean-room implementation: zero code, prompt, or schema reuse from external
 * AGPL sources. All seat records are strictly metadata-only (no prompt text,
 * transcript bodies, or credentials).
 */

import { getLivenessCapabilities, type Harness } from "./harness";
import {
  isSaturationError,
  resolveFallbackTier,
  type SemanticTier,
} from "./harness-model-map";

export type SeatClassification =
  | "alive"
  | "legit_long_turn"
  | "rate_limit"
  | "truncated"
  | "hook_deferred"
  | "crash";

export type SeatStatus = "running" | "completed" | "recovered" | "escalated";

export type RecoveryAction =
  | "none"
  | "nudge"
  | "respawn"
  | "verify_disk"
  | "accept"
  | "escalate";

export interface SeatMetadata {
  seat_id: string;
  harness: Harness;
  role: string;
  tier?: SemanticTier;
  writable: boolean;
  side_effecting: boolean;
  started_at: number;
  last_progress_at: number;
  deadline_at: number;
  idle_timeout_ms: number;
  attempt: number;
  status: SeatStatus;
  classification: SeatClassification;
  artifact_path?: string;
}

export interface SeatSignals {
  now?: number;
  exited?: boolean;
  exitCode?: number;
  error?: unknown;
  hookDeferred?: boolean;
  artifactPresent?: boolean;
  floorPassed?: boolean;
}

export interface DiskVerificationState {
  dirtyDiff?: boolean;
  diffVerified?: boolean;
  artifactVerified?: boolean;
}

export interface RecoveryDecision {
  action: RecoveryAction;
  fallbackTier: SemanticTier | null;
  nextAttempt: number;
  reviewedCoverage: "full" | "degraded" | "sequential-fallback";
  marker: string;
  reason: string;
}

const ALLOWED_SEAT_KEYS: ReadonlySet<string> = new Set([
  "seat_id",
  "harness",
  "role",
  "tier",
  "writable",
  "side_effecting",
  "started_at",
  "last_progress_at",
  "deadline_at",
  "idle_timeout_ms",
  "attempt",
  "status",
  "classification",
  "artifact_path",
  "recovery_action",
  "fallback_tier",
  "reviewed_coverage",
  "updated_at",
]);

const SECRET_VALUE_PATTERN =
  /BEGIN [A-Z ]*PRIVATE KEY|sk-ant-[A-Za-z0-9_-]{10,}|gh[pousr]_[A-Za-z0-9_]{16,}|github_pat_[A-Za-z0-9_]{16,}|sk_(?:live|test)_[A-Za-z0-9]{16,}|dp\.(?:pt|st|sa|ct)\.[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}/;

/**
 * Validate that a seat record conforms to the closed metadata-only field allowlist
 * and carries no raw prompt, transcript, or secret-shaped values (FR2).
 */
export function validateSeatMetadata(
  raw: Record<string, unknown>,
): SeatMetadata {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    throw new Error("metadata-only violation: seat record must be a plain object");
  }

  for (const key of Object.keys(raw)) {
    if (!ALLOWED_SEAT_KEYS.has(key)) {
      throw new Error(
        `metadata-only violation: forbidden seat field '${key}' (transcripts, prompts, and unallowlisted fields are prohibited)`,
      );
    }
    const val = raw[key];
    if (typeof val === "string" && SECRET_VALUE_PATTERN.test(val)) {
      throw new Error(
        `secret redaction violation: field '${key}' contains a credential-shaped token`,
      );
    }
  }

  if (typeof raw.seat_id !== "string" || raw.seat_id.trim() === "") {
    throw new Error("invalid seat metadata: seat_id must be a non-empty string");
  }

  return raw as unknown as SeatMetadata;
}

/**
 * Record an in-flight progress heartbeat on a seat.
 * Resets the idle window (`last_progress_at`) while preserving `deadline_at`
 * so progress beats can never extend the absolute turn cap (FR3).
 */
export function recordSeatHeartbeat(
  seat: SeatMetadata,
  now: number = Date.now(),
): SeatMetadata {
  return {
    ...seat,
    last_progress_at: Math.max(seat.last_progress_at, now),
    deadline_at: seat.deadline_at,
  };
}

/**
 * Deterministically classify a spawned seat's health/silence state (FR3).
 */
export function classifySeatSilence(
  seat: SeatMetadata,
  signals: SeatSignals = {},
): SeatClassification {
  const now = signals.now ?? Date.now();

  if (signals.hookDeferred === true) {
    return "hook_deferred";
  }

  if (signals.error !== undefined && isSaturationError(signals.error)) {
    return "rate_limit";
  }

  const cleanCompleted =
    signals.exited === true &&
    (signals.exitCode === undefined || signals.exitCode === 0) &&
    signals.artifactPresent !== false &&
    signals.floorPassed !== false;

  // Absolute turn cap is never reset by progress heartbeats.
  if (now >= seat.deadline_at && !cleanCompleted) {
    return "crash";
  }

  if (signals.exited === true) {
    if (signals.exitCode !== undefined && signals.exitCode !== 0) {
      return "crash";
    }
    if (
      signals.floorPassed === false ||
      signals.artifactPresent === false ||
      (Boolean(seat.artifact_path) && signals.artifactPresent !== true)
    ) {
      return "truncated";
    }
    return "alive";
  }

  const idleElapsed = now - seat.last_progress_at;
  if (idleElapsed > seat.idle_timeout_ms) {
    return "crash";
  }

  const totalElapsed = now - seat.started_at;
  if (totalElapsed > seat.idle_timeout_ms) {
    return "legit_long_turn";
  }

  return "alive";
}

function formatLivenessMarker(
  seatId: string,
  classification: SeatClassification,
  action: RecoveryAction,
): string {
  return `SOLEUR_SEAT_LIVENESS seat=${seatId} status=${classification} action=${action}`;
}

/**
 * Decide the bounded recovery action for a seat after inspecting on-disk state (FR4, FR5).
 * Enforces max 1 recovery attempt (`attempt < 1`), inspects on-disk diffs/artifacts first,
 * and refuses auto-respawn on `side_effecting` or unverified dirty-diff `writable` seats.
 */
export function decideSeatRecovery(
  seat: SeatMetadata,
  diskState: DiskVerificationState = {},
): RecoveryDecision {
  if (
    seat.classification === "alive" ||
    seat.classification === "legit_long_turn"
  ) {
    return {
      action: "none",
      fallbackTier: null,
      nextAttempt: seat.attempt,
      reviewedCoverage: "full",
      marker: formatLivenessMarker(seat.seat_id, seat.classification, "none"),
      reason: "seat is healthy or making progress within absolute turn cap",
    };
  }

  // On-disk verification first: if the expected artifact or diff is already valid on disk,
  // accept the work rather than wasting a respawn (2026-11-02 & 2026-05-15 learnings).
  if (
    diskState.artifactVerified === true ||
    (seat.writable && diskState.dirtyDiff === true && diskState.diffVerified === true)
  ) {
    return {
      action: "accept",
      fallbackTier: null,
      nextAttempt: seat.attempt,
      reviewedCoverage: "full",
      marker: formatLivenessMarker(seat.seat_id, seat.classification, "accept"),
      reason: "on-disk artifact or diff verified complete",
    };
  }

  // Writable seat with dirty worktree diff: never blindly spawn a second writer over uncommitted diffs.
  if (seat.writable && diskState.dirtyDiff === true) {
    if (diskState.diffVerified === undefined) {
      return {
        action: "verify_disk",
        fallbackTier: null,
        nextAttempt: seat.attempt,
        reviewedCoverage: "degraded",
        marker: formatLivenessMarker(
          seat.seat_id,
          seat.classification,
          "verify_disk",
        ),
        reason: "writable seat left dirty diff; verify git diff before deciding recovery",
      };
    }
    return {
      action: "escalate",
      fallbackTier: null,
      nextAttempt: seat.attempt,
      reviewedCoverage: "degraded",
      marker: formatLivenessMarker(seat.seat_id, seat.classification, "escalate"),
      reason: "writable seat left unverified dirty diff; refusing blind respawn over uncommitted changes",
    };
  }

  // Non-idempotent external side-effecting seat: never auto-respawn.
  if (seat.side_effecting) {
    return {
      action: "escalate",
      fallbackTier: null,
      nextAttempt: seat.attempt,
      reviewedCoverage: "degraded",
      marker: formatLivenessMarker(seat.seat_id, seat.classification, "escalate"),
      reason: "side-effecting seat cannot be safely auto-restarted",
    };
  }

  // Enforce max 1 recovery attempt.
  if (seat.attempt >= 1) {
    return {
      action: "escalate",
      fallbackTier: null,
      nextAttempt: seat.attempt,
      reviewedCoverage: "degraded",
      marker: formatLivenessMarker(seat.seat_id, seat.classification, "escalate"),
      reason: "recovery cap reached (max 1 attempt); escalating with degraded coverage",
    };
  }

  const caps = getLivenessCapabilities(seat.harness);

  if (
    caps.inBandNudge &&
    (seat.classification === "hook_deferred" ||
      seat.classification === "truncated")
  ) {
    return {
      action: "nudge",
      fallbackTier: null,
      nextAttempt: seat.attempt + 1,
      reviewedCoverage: "full",
      marker: formatLivenessMarker(seat.seat_id, seat.classification, "nudge"),
      reason: "in-band nudge supported for paused or truncated seat",
    };
  }

  const tier: SemanticTier = seat.tier ?? "inherit";
  const fallbackTier =
    seat.classification === "rate_limit" ? resolveFallbackTier(tier) : null;

  return {
    action: "respawn",
    fallbackTier,
    nextAttempt: seat.attempt + 1,
    reviewedCoverage: "full",
    marker: formatLivenessMarker(seat.seat_id, seat.classification, "respawn"),
    reason:
      seat.classification === "rate_limit"
        ? `rate-limited seat respawning once (fallbackTier=${fallbackTier ?? "same"})`
        : "safe seat respawning once after clean-disk verification",
  };
}
