"use client";

// feat-ui-action-feedback Layer 2 — module-level route-pending store
// (implementation-brief §1; plan Technical Approach Layer 2). Plain functions
// over a tiny external store (subscribe/getSnapshot for useSyncExternalStore),
// so a trigger firing pre-hydration cannot throw and no provider/context wraps
// the tree. The store owns the whole episode lifecycle — 150ms entry delay,
// ~400ms min-visible hold, ~30s stall termination (spec-flow C1) — so start()
// idempotency (a no-op while pending AND through the post-commit hold, until
// the bar is fully hidden) is enforced in one place and the island stays a
// pure renderer.

import { track } from "@/lib/analytics-client";
import { reportSilentFallback } from "@/lib/client-observability";
import { NAV_MIN_VISIBLE_MS, PENDING_ENTRY_DELAY_MS } from "@/lib/pending-timing";

export type NavPendingTrigger = "link" | "router" | "popstate";

// Shared timing contract (implementation-brief §7/§9-R8) — the canonical
// values live in lib/pending-timing.ts (the button spinner delay consumes the
// same 150ms); re-exported here so nav-pending consumers have one import site.
export { PENDING_ENTRY_DELAY_MS };
export const PENDING_MIN_VISIBLE_MS = NAV_MIN_VISIBLE_MS;
export const PENDING_STALL_MS = 30_000;

type NavPendingPhase = "idle" | "pending" | "visible" | "holding";

export interface NavPendingSnapshot {
  /** Episode open OR inside the min-visible hold — start() no-ops while true. */
  pending: boolean;
  /** Past the entry delay — drives the bar render and the live region. */
  visible: boolean;
  trigger: NavPendingTrigger | null;
  startedAt: number | null;
}

const IDLE_SNAPSHOT: NavPendingSnapshot = {
  pending: false,
  visible: false,
  trigger: null,
  startedAt: null,
};

let phase: NavPendingPhase = "idle";
let trigger: NavPendingTrigger | null = null;
let startedAt = 0;
let visibleAt = 0;
let lastLocation = "";
let entryTimer: ReturnType<typeof setTimeout> | null = null;
let stallTimer: ReturnType<typeof setTimeout> | null = null;
let hideTimer: ReturnType<typeof setTimeout> | null = null;
let snapshot = IDLE_SNAPSHOT;

const listeners = new Set<() => void>();

function emit(): void {
  snapshot =
    phase === "idle"
      ? IDLE_SNAPSHOT
      : {
          pending: true,
          visible: phase === "visible" || phase === "holding",
          trigger,
          startedAt,
        };
  for (const listener of listeners) listener();
}

function clearTimer(which: "entry" | "stall" | "hide"): void {
  if (which === "entry" && entryTimer !== null) {
    clearTimeout(entryTimer);
    entryTimer = null;
  }
  if (which === "stall" && stallTimer !== null) {
    clearTimeout(stallTimer);
    stallTimer = null;
  }
  if (which === "hide" && hideTimer !== null) {
    clearTimeout(hideTimer);
    hideTimer = null;
  }
}

function currentLocationKey(): string {
  if (typeof window === "undefined") return "";
  return window.location.pathname + window.location.search;
}

// Seed the continuously-tracked last location at module init (brief §1
// popstate edge — compared at popstate time so hash-only entries like the
// `#main-content` skip link never fire).
lastLocation = currentLocationKey();

export function getNavLastLocation(): string {
  return lastLocation;
}

/** Called by the island's commit watcher on every pathname/searchParams change. */
export function noteNavLocation(): void {
  const key = currentLocationKey();
  if (key) lastLocation = key;
}

function forceStopStalledEpisode(): void {
  const stalledTrigger = trigger;
  const stalledSince = startedAt;
  clearTimer("entry");
  clearTimer("stall");
  clearTimer("hide");
  phase = "idle";
  trigger = null;
  emit();
  try {
    reportSilentFallback("nav-pending episode stalled", {
      feature: "nav-pending",
      op: "stall-timeout",
      extra: { trigger: stalledTrigger, startedAt: stalledSince, lastLocation },
    });
  } catch {
    console.warn("[nav-pending] stalled episode force-stopped", stalledTrigger);
  }
}

/**
 * Open a pending episode. Idempotent: a no-op while an episode is pending AND
 * during the ~400ms min-visible hold after commit — a second start inside the
 * hold is ignored until the bar is fully hidden (brief §1 step 5, ux #8).
 * Arms the ~30s stall timeout: a hung RSC fetch or never-committing trigger
 * can never leave a permanent bar (spec-flow C1).
 */
export function startNavPending(t: NavPendingTrigger): void {
  if (phase !== "idle") return;
  phase = "pending";
  trigger = t;
  startedAt = Date.now();
  entryTimer = setTimeout(() => {
    entryTimer = null;
    if (phase !== "pending") return;
    phase = "visible";
    visibleAt = Date.now();
    emit();
  }, PENDING_ENTRY_DELAY_MS);
  stallTimer = setTimeout(() => {
    stallTimer = null;
    forceStopStalledEpisode();
  }, PENDING_STALL_MS);
  emit();
}

// Layer 5 telemetry — `nav_duration_ms` per committed soft nav. sanitize.ts
// allowlists props to `["path"]` and no route-pattern normalizer exists, so
// `path` carries only `nav:<trigger>:<section>` — trigger ∈ link|router|
// popstate, section ∈ a fixed first-segment enum (never a concrete path —
// token segments aren't masked by the server scrubber; plan Layer 5 / kieran
// #5). Per-episode durations ride the Sentry breadcrumb on stalls; tail-drop
// under the 120/min analytics throttle is accepted — the signal needs trends.
const NAV_SECTIONS = new Set([
  "dashboard",
  "connect-repo",
  "shared",
  "invite",
  "login",
  "signup",
  "internal",
]);

function emitNavTelemetry(episodeTrigger: NavPendingTrigger | null): void {
  const segment = window.location.pathname.split("/")[1] ?? "";
  const section = NAV_SECTIONS.has(segment) ? segment : "other";
  void track("nav_duration_ms", {
    path: `nav:${episodeTrigger ?? "programmatic"}:${section}`,
  });
}

/**
 * Close the pending episode on route commit (or abort). Before the entry
 * delay elapses this cancels silently — fast navs produce no flash (AC2).
 * Once visible, the bar holds for the remainder of the min-visible window.
 */
export function stopNavPending(): void {
  if (phase === "idle" || phase === "holding") return;
  clearTimer("stall");
  emitNavTelemetry(trigger);
  if (phase === "pending") {
    clearTimer("entry");
    phase = "idle";
    trigger = null;
    emit();
    return;
  }
  phase = "holding";
  const remaining = Math.max(0, PENDING_MIN_VISIBLE_MS - (Date.now() - visibleAt));
  hideTimer = setTimeout(() => {
    hideTimer = null;
    phase = "idle";
    trigger = null;
    emit();
  }, remaining);
  emit();
}

type UrlObjectLike = {
  href?: string | null;
  pathname?: string | null;
  search?: string | null;
  query?: string | Record<string, unknown> | null;
};

/** `next/link`-compatible href: string or UrlObject. */
export type NavPendingHref = string | UrlObjectLike;

function searchSuffix(href: UrlObjectLike): string {
  if (typeof href.search === "string" && href.search) {
    return href.search.startsWith("?") ? href.search : `?${href.search}`;
  }
  const query = href.query;
  if (typeof query === "string" && query) return `?${query.replace(/^\?+/, "")}`;
  if (query && typeof query === "object") {
    const params = new URLSearchParams();
    for (const [key, value] of Object.entries(query)) {
      if (value == null) continue;
      if (Array.isArray(value)) {
        for (const item of value) params.append(key, String(item));
      } else {
        params.append(key, String(value));
      }
    }
    const serialized = params.toString();
    if (serialized) return `?${serialized}`;
  }
  return "";
}

function hrefToString(href: NavPendingHref): string {
  if (typeof href === "string") return href;
  if (typeof href.href === "string" && href.href) return href.href;
  return `${href.pathname ?? ""}${searchSuffix(href)}`;
}

/**
 * True when `href` resolves to the current document's pathname+search — hash
 * excluded (a hash-only href like `#main-content` is same-doc). Resolution is
 * `new URL(href, location.href)` so relative hrefs (`?status=…`, `./x`) and
 * UrlObject inputs normalize against the live location, read at call time —
 * never a hook subscription (plan Layer 2 trigger (b)).
 */
export function isSameDocTarget(href: NavPendingHref): boolean {
  if (typeof window === "undefined") return false;
  try {
    const target = new URL(hrefToString(href), window.location.href);
    return (
      target.pathname + target.search ===
      window.location.pathname + window.location.search
    );
  } catch {
    return false;
  }
}

export function subscribeNavPending(listener: () => void): () => void {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

export function getNavPendingSnapshot(): NavPendingSnapshot {
  return snapshot;
}

export function getNavPendingServerSnapshot(): NavPendingSnapshot {
  return IDLE_SNAPSHOT;
}
