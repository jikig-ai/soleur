// exec-placement.ts — the placement-aware step-call decision module (#9137,
// ADR-033 amendment 2026-11-10; CTO rulings T1–T3 2026-11-10).
//
// Since the 2026-11-08 serve flip (#12167) the Cloudflare LB on app.soleur.ai
// steers Inngest step calls randomly across web-1 and web-2, so ~half of every
// `host-affine` / `volume-bound` call lands on a host with no LUKS workspaces
// volume and no ADR-243 §2 single-flight map. This module is the single
// decision point that restores host affinity at the app layer:
//
//   - `portable` executes wherever the call lands (the issue's actual goal).
//   - `host-affine`, `volume-bound`, unknown and unclassifiable calls are
//     pinned to the exec host — EXEC_HOST_PRIVATE_IP — and forwarded verbatim
//     when the call lands elsewhere (exec-forward-client.ts).
//   - FAIL-CLOSED everywhere: a host that cannot establish it is the exec host
//     refuses rather than executing a pinned call locally, and a marked
//     (already-forwarded) call arriving on a non-exec host is refused, never
//     re-forwarded.
//
// `EXECUTION_PLACEMENT` (execution-placement.ts) is THE classification
// authority — imported here, never copied. An `onFailure` handler is served
// under `<id>-failure` and inherits its parent's class (manifest header), so
// the classifier strips the SDK's `-failure` suffix before lookup.
//
// Module-load safety: everything reads env at call time (`next build` loads
// route modules without env — mirror client.ts's IS_BUILD_PHASE / the relay's
// inert-when-absent pattern). Nothing here throws at import.
//
// Observability (plan Observability section): every step call emits one
// `placement_decision` structured row (fields fnId, class, decision, host_ip);
// refuse paths `placement.exec_identity_missing` and `placement.marked_on_nonexec`
// are error-level and mirrored to Sentry via reportSilentFallback with
// feature=inngest-exec-placement; `placement.missing_signature` (an unsigned
// public caller prodding the pinned surface) is a rate-limited warn only —
// unsigned calls can never execute, so it is a journald signal, not a page.

import { createChildLogger } from "../logger";
import { reportSilentFallback } from "../observability";
import {
  isExecHost,
  readHostPrivateIp,
  type HostExecIdentity,
} from "../host-private-ip";
import {
  EXECUTION_PLACEMENT,
  type ExecutionPlacement,
} from "./execution-placement";

const log = createChildLogger("inngest-exec-placement");

/** Sentry feature tag for every placement report (plan Observability). */
export const EXEC_PLACEMENT_FEATURE = "inngest-exec-placement";

/**
 * The exec host's private-net IP — the ADR-119 volume holder and the host
 * `inngest-host.tf`'s `sdk_url` already polls (web-1). HARDCODED by CTO ruling
 * T2: an env-derived pin re-opens #5182 (a Doppler write silently re-pointing
 * execution). Drift against `infra/inngest-host.tf` sdk_url and
 * `infra/variables.tf`/`network.tf` web-1 `private_ip` is guarded (Guard 4 of
 * test/server/inngest/exec-placement-forward.test.ts).
 */
export const EXEC_HOST_PRIVATE_IP = "10.0.1.10";

/**
 * Loop-guard marker set on a forwarded call. It is trusted ONLY because the
 * receiver accepts it on the private-TLS ingress (exec-receiver.ts): a forged
 * marker on the public path can never execute — a marked call on a non-exec
 * host is refused, and on the exec host the SDK's HMAC check still runs.
 */
export const EXEC_FORWARD_HEADER = "x-soleur-exec-forward";

/**
 * Dedicated receiver port (plan-review P1: NOT :8443 — the wss relay's 10 s
 * HELLO_DEADLINE_MS would kill a step call that streams for minutes). Chosen
 * as 8445: the plan's example 8444 appears in infra/ egress-firewall and
 * lb-weight-gate fixtures as the deliberately-WRONG relay port, so 8444 in
 * live config is a poisoned sentinel value.
 */
export const EXEC_FORWARD_PORT = 8445;

/**
 * The literal forward target — the pin, never derived from the request Host
 * header or any env value (Guard 3 asserts this literal origin).
 */
export const EXEC_FORWARD_URL = "https://10.0.1.10:8445/api/inngest";

/** The app-scoped prefix the SDK keys `this.fns` by (`<appId>-<fnId>`). */
export const INNGEST_APP_ID_PREFIX = "soleur-runtime-";
/** The SDK suffix on onFailure handlers, which inherit the parent's class. */
export const INNGEST_FAILURE_SUFFIX = "-failure";
/** Signature-presence gate (plan-review P5): only signed calls may forward. */
export const INNGEST_SIGNATURE_HEADER = "x-inngest-signature";

export type ExecIdentity = HostExecIdentity;

/** The refuse reasons, in the decision table's vocabulary. */
export type PlacementRefuseReason =
  | "exec_identity_missing"
  | "marked_on_nonexec"
  | "missing_signature";

export type PlacementDecision =
  | { action: "execute" }
  | { action: "forward"; target: string }
  | {
      action: "refuse";
      reason: PlacementRefuseReason;
      status: number;
      error: string;
    };

/**
 * The request facts the decision consumes — gathered once per POST by
 * `gatherPlacementFacts` so the pure function sees no Request/env plumbing.
 */
export interface PlacementFacts {
  /** HTTP method — only POST is a step call (GET/PUT are registration). */
  method: string;
  /** `?probe=` present (signature probes answer on any host). */
  hasProbe: boolean;
  /** `?fnId=` query key, raw — the SDK's own routing key. */
  fnId: string | null;
  /** EXEC_FORWARD_HEADER present (already-forwarded marker). */
  marked: boolean;
  /** This host's identity vs the pin: true / false / "unknown". */
  isExec: ExecIdentity;
  /** x-inngest-signature present (P5 gate — never forward unsigned). */
  hasSignature: boolean;
  /** The host's configured private IP for the log row (null = unestablished). */
  hostIp: string | null;
}

const REFUSE_STATUS: Readonly<Record<PlacementRefuseReason, number>> = {
  // Retriable by design (plan-review P9): a NIC-late deploy must stall ticks so
  // the run recovers inside the SDK retry window after the redeploy runbook
  // step — NEVER a NonRetriable-shaped 4xx here.
  exec_identity_missing: 503,
  marked_on_nonexec: 403,
  missing_signature: 401,
};

function refuse(reason: PlacementRefuseReason): PlacementDecision {
  return {
    action: "refuse",
    reason,
    status: REFUSE_STATUS[reason],
    error: `placement.${reason}`,
  };
}

/**
 * Resolve an inbound `?fnId=` to its EXECUTION_PLACEMENT class.
 *
 * The SDK addresses functions as `<appId>-<fnId>` with onFailure handlers at
 * `<appId>-<fnId>-failure`; strip the `soleur-runtime-` prefix and one
 * `-failure` suffix, then look up the manifest. Returns `null` — the
 * fail-closed direction, treated as pinned by decidePlacement — for a missing,
 * prefix-less, doubled-prefix, or manifest-absent id. It can never return a
 * wrong class for a known function.
 */
export function classifyFnId(
  rawFnId: string | null | undefined,
): ExecutionPlacement | null {
  if (typeof rawFnId !== "string") return null;
  const trimmed = rawFnId.trim();
  if (!trimmed.startsWith(INNGEST_APP_ID_PREFIX)) return null;
  const scoped = trimmed.slice(INNGEST_APP_ID_PREFIX.length);
  // Empty leaf or `soleur-runtime-soleur-runtime-*`: both unclassifiable.
  if (scoped.length === 0 || scoped.startsWith(INNGEST_APP_ID_PREFIX)) {
    return null;
  }
  const leaf = scoped.endsWith(INNGEST_FAILURE_SUFFIX)
    ? scoped.slice(0, -INNGEST_FAILURE_SUFFIX.length)
    : scoped;
  if (leaf.length === 0) return null;
  const row = EXECUTION_PLACEMENT[leaf] as
    | { placement: ExecutionPlacement; reason: string }
    | undefined;
  return row ? row.placement : null;
}

/**
 * The decision table (plan "Proposed Solution"), evaluated in this order —
 * every row below is pinned by a Guard-2 mutation-matrix test:
 *
 *   1. not a step call (non-POST or `?probe=`)          → execute locally
 *   2. marked + host IS exec                            → execute locally
 *   3. marked + host NOT exec / unidentifiable          → refuse (loop-guard)
 *   4. class `portable` (unmarked)                      → execute locally
 *   5. identity unestablished (unmarked, non-portable)  → refuse 503
 *   6. pinned class + host IS exec                      → execute locally
 *   7. pinned class + host NOT exec + no signature      → refuse (P5 gate)
 *   8. pinned class + host NOT exec + signed            → forward to the pin
 *
 * "Pinned class" includes every unclassifiable shape — unknown ids, missing
 * fnId, doubled/missing prefix — so a POST with no fnId and no probe fails
 * closed to the exec host, whose SDK rejects it there (plan Test Scenarios).
 */
export function decidePlacement(f: PlacementFacts): PlacementDecision {
  if (f.method !== "POST" || f.hasProbe) return { action: "execute" };
  // The marker is trusted ONLY on the confirmed exec host (it arrived on the
  // private-TLS listener). Anywhere else it is a forged public path call or a
  // second hop — refuse, never re-forward (loop-guard, AC5).
  if (f.marked) {
    if (f.isExec === true) return { action: "execute" };
    return refuse(
      f.isExec === "unknown" ? "exec_identity_missing" : "marked_on_nonexec",
    );
  }
  if (classifyFnId(f.fnId) === "portable") return { action: "execute" };
  // Pinned direction from here down: host-affine, volume-bound, unknown, or
  // unclassifiable — none may execute on a guess.
  if (f.isExec === "unknown") return refuse("exec_identity_missing");
  if (f.isExec === true) return { action: "execute" };
  // P5: the non-exec host forwards only signed calls — an unsigned public POST
  // must never reach the private listener through us.
  if (!f.hasSignature) return refuse("missing_signature");
  return { action: "forward", target: EXEC_FORWARD_URL };
}

/** Read the request into PlacementFacts (env read happens here, per call). */
export function gatherPlacementFacts(req: Request): PlacementFacts {
  const url = new URL(req.url);
  return {
    method: req.method,
    hasProbe: url.searchParams.has("probe"),
    fnId: url.searchParams.get("fnId"),
    marked: req.headers.has(EXEC_FORWARD_HEADER),
    isExec: isExecHost(EXEC_HOST_PRIVATE_IP),
    hasSignature: req.headers.has(INNGEST_SIGNATURE_HEADER),
    hostIp: readHostPrivateIp(),
  };
}

/** The wire body every refusal shares — `{ error: "placement.<reason>" }`. */
export function refuseResponse(
  decision: PlacementDecision & { action: "refuse" },
): Response {
  return Response.json({ error: decision.error }, { status: decision.status });
}

/**
 * One placement_decision row per step call (plan Observability `liveness_signal`),
 * plus the refuse-path Sentry mirrors (feature=inngest-exec-placement):
 * `placement.exec_identity_missing` and `placement.marked_on_nonexec` are
 * error-level + Sentry; `placement.missing_signature` is a warn row rate-limited
 * to one a minute — a spoof/forgery signal, not a page.
 */
const UNSIGNED_WARN_INTERVAL_MS = 60_000;
let lastUnsignedWarnAt = -UNSIGNED_WARN_INTERVAL_MS;

export function recordPlacementDecision(
  facts: PlacementFacts,
  decision: PlacementDecision,
): void {
  const cls =
    facts.fnId === null
      ? "absent"
      : (classifyFnId(facts.fnId) ?? "unresolved");
  const fields = {
    op: EXEC_PLACEMENT_FEATURE,
    event: "placement_decision",
    fnId: facts.fnId,
    class: cls,
    decision: decision.action,
    host_ip: facts.hostIp,
    ...(decision.action === "refuse" ? { reason: decision.reason } : {}),
  };
  if (decision.action !== "refuse") {
    log.info(fields, "placement_decision");
    return;
  }
  if (decision.reason === "missing_signature") {
    const now = Date.now();
    if (now - lastUnsignedWarnAt >= UNSIGNED_WARN_INTERVAL_MS) {
      lastUnsignedWarnAt = now;
      log.warn(fields, "placement_decision: refusing unsigned pinned call");
    }
    return;
  }
  log.error(fields, "placement_decision: refuse");
  reportSilentFallback(null, {
    feature: EXEC_PLACEMENT_FEATURE,
    op: `placement.${decision.reason}`,
    message: `inngest exec placement refused a step call: placement.${decision.reason}`,
    extra: { fnId: facts.fnId, class: cls, hostIp: facts.hostIp },
  });
}
