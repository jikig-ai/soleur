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

const SEAT_ID_PATTERN = /^[A-Za-z0-9:._-]{1,128}$/;
const LINE_BREAK_PATTERN = /[\r\n\u2028\u2029]/;
const MAX_METADATA_STRING_LEN = 512;

const SECRET_VALUE_PATTERN =
  /BEGIN [A-Z ]*PRIVATE KEY|sk-ant-[A-Za-z0-9_-]{10,}|gh[pousr]_[A-Za-z0-9_]{16,}|github_pat_[A-Za-z0-9_]{16,}|sk_(?:live|test)_[A-Za-z0-9]{16,}|dp\.(?:pt|st|sa|ct)\.[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}/;

/**
 * Sanitize a seat identifier before embedding in log markers (CWE-117).
 */
export function sanitizeSeatIdForMarker(seatId: string): string {
  const cleaned = String(seatId)
    .replace(/[\x00-\x1f\x7f\u2028\u2029\s=]/g, "_")
    .replace(/[^A-Za-z0-9:._-]/g, "_")
    .slice(0, 128);
  return cleaned || "unknown-seat";
}

/**
 * Validate that a seat record conforms to the closed metadata-only field allowlist
 * and carries no raw prompt, transcript, non-primitive nested payloads, or secret-shaped values (FR2).
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
    if (
      val !== undefined &&
      val !== null &&
      typeof val !== "string" &&
      typeof val !== "number" &&
      typeof val !== "boolean"
    ) {
      throw new Error(
        `metadata-only violation: field '${key}' must be a primitive metadata value`,
      );
    }
    if (typeof val === "string") {
      if (val.length > MAX_METADATA_STRING_LEN || LINE_BREAK_PATTERN.test(val)) {
        throw new Error(
          `metadata-only violation: field '${key}' exceeds metadata length or single-line constraint`,
        );
      }
      if (SECRET_VALUE_PATTERN.test(val)) {
        throw new Error(
          `secret redaction violation: field '${key}' contains a credential-shaped token`,
        );
      }
    }
  }

  if (
    typeof raw.seat_id !== "string" ||
    !SEAT_ID_PATTERN.test(raw.seat_id) ||
    raw.seat_id === "." ||
    raw.seat_id === ".." ||
    raw.seat_id.startsWith("-")
  ) {
    throw new Error(
      "invalid seat metadata: seat_id must match /^[A-Za-z0-9:._-]{1,128}$/ without leading '-' or dot-segment traversal",
    );
  }

  if (typeof raw.artifact_path === "string" && /(?:^|[\\/])\.\.(?:[\\/]|$)/.test(raw.artifact_path)) {
    throw new Error("invalid seat metadata: artifact_path must not contain '..' traversal");
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
  attempt: number,
  fallbackTier: SemanticTier | null,
  reviewedCoverage: "full" | "degraded" | "sequential-fallback",
): string {
  const safeId = sanitizeSeatIdForMarker(seatId);
  const fb =
    action === "respawn" ? (fallbackTier ?? "same") : "none";
  return `SOLEUR_SEAT_LIVENESS seat=${safeId} status=${classification} action=${action} attempt=${attempt} fallback_tier=${fb} reviewed_coverage=${reviewedCoverage}`;
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
      marker: formatLivenessMarker(
        seat.seat_id,
        seat.classification,
        "none",
        seat.attempt,
        null,
        "full",
      ),
      reason: "seat is healthy or making progress within absolute turn cap",
    };
  }

  // Writable seat with dirty worktree diff: evaluate dirty-diff verification BEFORE artifactVerified
  // so an unverified or failed worktree diff can never be masked by an artifact check.
  if (seat.writable && diskState.dirtyDiff === true) {
    if (diskState.diffVerified === true) {
      return {
        action: "accept",
        fallbackTier: null,
        nextAttempt: seat.attempt,
        reviewedCoverage: "full",
        marker: formatLivenessMarker(
          seat.seat_id,
          seat.classification,
          "accept",
          seat.attempt,
          null,
          "full",
        ),
        reason: "on-disk dirty diff verified complete",
      };
    }
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
          seat.attempt,
          null,
          "degraded",
        ),
        reason: "writable seat left dirty diff; verify git diff before deciding recovery",
      };
    }
    return {
      action: "escalate",
      fallbackTier: null,
      nextAttempt: seat.attempt,
      reviewedCoverage: "degraded",
      marker: formatLivenessMarker(
        seat.seat_id,
        seat.classification,
        "escalate",
        seat.attempt,
        null,
        "degraded",
      ),
      reason: "writable seat left unverified dirty diff; refusing blind respawn over uncommitted changes",
    };
  }

  // Read-only or clean-diff seat whose expected artifact is verified complete on disk.
  if (diskState.artifactVerified === true) {
    return {
      action: "accept",
      fallbackTier: null,
      nextAttempt: seat.attempt,
      reviewedCoverage: "full",
      marker: formatLivenessMarker(
        seat.seat_id,
        seat.classification,
        "accept",
        seat.attempt,
        null,
        "full",
      ),
      reason: "on-disk artifact verified complete",
    };
  }

  // Non-idempotent external side-effecting seat: never auto-respawn.
  if (seat.side_effecting) {
    return {
      action: "escalate",
      fallbackTier: null,
      nextAttempt: seat.attempt,
      reviewedCoverage: "degraded",
      marker: formatLivenessMarker(
        seat.seat_id,
        seat.classification,
        "escalate",
        seat.attempt,
        null,
        "degraded",
      ),
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
      marker: formatLivenessMarker(
        seat.seat_id,
        seat.classification,
        "escalate",
        seat.attempt,
        null,
        "degraded",
      ),
      reason: "recovery cap reached (max 1 attempt); escalating with degraded coverage",
    };
  }

  const caps = getLivenessCapabilities(seat.harness);

  if (
    caps.inBandNudge &&
    (seat.classification === "hook_deferred" ||
      seat.classification === "truncated")
  ) {
    const nextAttempt = seat.attempt + 1;
    return {
      action: "nudge",
      fallbackTier: null,
      nextAttempt,
      reviewedCoverage: "full",
      marker: formatLivenessMarker(
        seat.seat_id,
        seat.classification,
        "nudge",
        nextAttempt,
        null,
        "full",
      ),
      reason: "in-band nudge supported for paused or truncated seat",
    };
  }

  const tier: SemanticTier = seat.tier ?? "inherit";
  const fallbackTier =
    seat.classification === "rate_limit" ? resolveFallbackTier(tier) : null;
  const nextAttempt = seat.attempt + 1;

  return {
    action: "respawn",
    fallbackTier,
    nextAttempt,
    reviewedCoverage: "full",
    marker: formatLivenessMarker(
      seat.seat_id,
      seat.classification,
      "respawn",
      nextAttempt,
      fallbackTier,
      "full",
    ),
    reason:
      seat.classification === "rate_limit"
        ? `rate-limited seat respawning once (fallbackTier=${fallbackTier ?? "same"})`
        : "safe seat respawning once after clean-disk verification",
  };
}
