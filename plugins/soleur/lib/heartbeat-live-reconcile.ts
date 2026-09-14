// Pure, network-free reconcile logic for the nightly source-vs-live Better Stack heartbeat check
// (#6549 item 2). The CLI wrapper that fetches the live payload lives in
// `plugins/soleur/scripts/reconcile-live-heartbeats.ts`.
//
// Why this exists: `heartbeat-reprovision-parity.test.ts` proves a feeder exists in SOURCE, but
// `lifecycle { ignore_changes = [paused] }` (plus these resources being untargeted) makes the .tf
// `paused` value only a LOWER BOUND on live state. A heartbeat that is `paused` or absent in LIVE
// Better Stack is invisible to any source-only test — the exact state that hid the registry
// heartbeat for 9 days (#6537). This module compares the live payload against the executable
// MANIFEST and flags two mismatch classes. It only READS; it never unpauses anything.

import type { ManifestEntry } from "./heartbeat-manifest";

/** A `betteruptime_heartbeat` block parsed from the infra `.tf` source. */
export interface DiscoveredHeartbeat {
  /** The `.tf` resource label — `betteruptime_heartbeat.<resourceName>`; the MANIFEST join key. */
  resourceName: string;
  /** The `name = "..."` attribute — how live Better Stack keys the monitor. */
  liveName: string;
  /**
   * The source-declared `paused` value (defaults to false when the attribute is absent). Carried
   * for reporting/diagnostics only — `reconcileHeartbeats` keys its decision on live state +
   * `feeder.kind`, never on this (source `paused` is only a lower bound on live; that decoupling is
   * the whole reason a live reconcile exists).
   */
  sourcePaused: boolean;
  /** Whether the block carries a `count =` meta-argument (the paid-tier item-1 carve-out). */
  countGated: boolean;
}

/** One heartbeat as reported by `GET /api/v2/heartbeats` (`data[].attributes`). */
export interface LiveHeartbeat {
  name: string;
  paused: boolean;
}

/**
 * `fed-but-paused` / `absent-live` are the heartbeat classes (a)/(b) below. `logs-alert-paused` /
 * `logs-alert-absent` are the #8097 `logs_alert` arm: a declared `logtail_exploration_alert`
 * that is paused live or missing live. Why a poller and not the drift plan: see ADR-218 §5 (the
 * per-merge apply re-arms `paused = false`, and the untargeted plan is already perpetually
 * non-zero, so a one-line `~ paused` there is not a detector).
 * Every consumer that switches on this union is listed in the scheduled-terraform-drift.yml
 * issue-body decode list (cq-union-widening-grep-three-patterns).
 */
export type ViolationReason = "fed-but-paused" | "absent-live" | "logs-alert-paused" | "logs-alert-absent";

export interface Violation {
  resourceName: string;
  liveName: string;
  /**
   * `paused` / `absent` are heartbeat live STATES (conditions (a)/(b)); `logs_alert` is a SURFACE
   * tag for the #8097 arm, whose state is carried by `reason` (`logs-alert-paused|absent`). Two
   * axes in one field, kept because the marker grammar `live=…` is a wire contract consumed by
   * scheduled-terraform-drift.yml's decode list and ADR-218.
   */
  live: "paused" | "absent" | "logs_alert";
  reason: ViolationReason;
  /**
   * Free text carried ONLY for the `logs_alert` arm (the vendor's `paused_reason`). Rendered inside
   * a quoted `detail="…"` so the k=v marker grammar stays parseable; absent for heartbeat classes.
   */
  detail?: string;
}

/** A `logtail_exploration_alert` block parsed from the infra `.tf` source (#8097). */
export interface DiscoveredLogsAlert {
  resourceName: string;
  /** The `name = "..."` attribute — how the Telemetry API keys the alert. */
  liveName: string;
}

/** One alert as reported by `GET telemetry.betterstack.com/api/v2/alerts` (`data[].attributes`). */
export interface LiveLogsAlert {
  name: string;
  paused: boolean;
  /** Vendor free text; `""` when absent/null (coalesced once, at parse). */
  pausedReason: string;
}

/**
 * Strip HCL line comments (`#` and `//`) so a `count =` / `paused =` token that appears only inside
 * an explanatory comment cannot be mistaken for real config. Mirrors the comment-stripped view the
 * parity test parses. A `#`/`//` inside a double-quoted string is preserved.
 */
export function stripComments(text: string): string {
  return text
    .split("\n")
    .map((line) => {
      let inString = false;
      for (let i = 0; i < line.length; i++) {
        const ch = line[i];
        if (ch === '"' && line[i - 1] !== "\\") {
          inString = !inString;
          continue;
        }
        if (inString) continue;
        if (ch === "#") return line.slice(0, i);
        if (ch === "/" && line[i + 1] === "/") return line.slice(0, i);
      }
      return line;
    })
    .join("\n");
}

/**
 * Brace-matched extraction of every `resource "<type>" "<name>" {…}` block in comment-stripped
 * HCL. Throws on an unbalanced block so a malformed source can never silently drop a resource.
 */
function resourceBlocks(stripped: string, type: string): { resourceName: string; body: string }[] {
  const header = new RegExp(`resource\\s+"${type}"\\s+"([A-Za-z0-9_]+)"\\s*\\{`, "g");
  const out: { resourceName: string; body: string }[] = [];
  let m: RegExpExecArray | null;
  while ((m = header.exec(stripped)) !== null) {
    const resourceName = m[1];
    const openBrace = header.lastIndex - 1;
    let depth = 0;
    let end = -1;
    for (let i = openBrace; i < stripped.length; i++) {
      if (stripped[i] === "{") depth++;
      else if (stripped[i] === "}") {
        depth--;
        if (depth === 0) {
          end = i;
          break;
        }
      }
    }
    if (end === -1) {
      throw new Error(`Unbalanced braces for ${type}.${resourceName}`);
    }
    out.push({ resourceName, body: stripped.slice(openBrace, end + 1) });
  }
  return out;
}

/**
 * Extract every `betteruptime_heartbeat` block (brace-matched, like the parity parser) with its
 * live name, source-declared paused, and count-gate presence. Throws on an unbalanced block so a
 * malformed source can never silently drop a heartbeat from the reconcile.
 */
export function parseHeartbeatBlocks(tfText: string): DiscoveredHeartbeat[] {
  const stripped = stripComments(tfText);
  const out: DiscoveredHeartbeat[] = [];
  for (const { resourceName, body } of resourceBlocks(stripped, "betteruptime_heartbeat")) {
    const nameMatch = /\bname\s*=\s*"([^"]+)"/.exec(body);
    const pausedMatch = /\bpaused\s*=\s*(true|false)\b/.exec(body);
    out.push({
      resourceName,
      liveName: nameMatch ? nameMatch[1] : "",
      // Absent `paused` defaults to active (false) — the conservative reading; an omission cannot
      // silently exempt a live heartbeat. Mirrors heartbeat-reprovision-parity.test.ts.
      sourcePaused: pausedMatch ? pausedMatch[1] === "true" : false,
      countGated: /\bcount\s*=/.test(body),
    });
  }
  return out;
}

/** Extract every `logtail_exploration_alert` block's live name (#8097 `logs_alert` arm). */
export function parseLogsAlertBlocks(tfText: string): DiscoveredLogsAlert[] {
  const stripped = stripComments(tfText);
  return resourceBlocks(stripped, "logtail_exploration_alert").map(({ resourceName, body }) => {
    const nameMatch = /\bname\s*=\s*"([^"]+)"/.exec(body);
    return { resourceName, liveName: nameMatch ? nameMatch[1] : "" };
  });
}

/**
 * Reconcile the declared Logs alerts against the live Telemetry payload (#8097 / ADR-218).
 *
 * - **logs-alert-absent** — a declared `logtail_exploration_alert` missing from the live payload
 *   (the main apply never created it, or it was deleted vendor-side).
 * - **logs-alert-paused** — present but `paused` live. Unlike heartbeats there is no fed/unfed
 *   distinction: every declared alert writes `paused = false` as intent, so a live pause is
 *   always a vendor-side rejection (`paused_reason` carried as `detail`) or a hand pause.
 *
 * Foreign live alerts (not declared in `.tf`) are ignored — the arm only READS.
 */
export function reconcileLogsAlerts(
  declared: readonly DiscoveredLogsAlert[],
  live: readonly LiveLogsAlert[],
): Violation[] {
  const byName = new Map<string, LiveLogsAlert>();
  for (const a of live) byName.set(a.name, a);
  const violations: Violation[] = [];
  for (const d of declared) {
    const l = byName.get(d.liveName);
    if (!l) {
      violations.push({ resourceName: d.resourceName, liveName: d.liveName, live: "logs_alert", reason: "logs-alert-absent" });
      continue;
    }
    if (l.paused) {
      violations.push({
        resourceName: d.resourceName,
        liveName: d.liveName,
        live: "logs_alert",
        reason: "logs-alert-paused",
        detail: l.pausedReason,
      });
    }
  }
  return violations;
}

type ManifestRow = Pick<ManifestEntry, "name" | "feeder" | "arming_pending">;

/**
 * Reconcile the live Better Stack payload against the MANIFEST + discovered `.tf` blocks.
 *
 * - **(a) fed-but-paused** — a heartbeat whose MANIFEST feeder is a working feeder
 *   (`kind ∈ {cron,timer}`) that is `paused` in the live payload (the #6537 9-days-dark shape).
 *   A row carrying `arming_pending` is EXEMPT from (a): its paused state is a deliberately-deferred
 *   arming window owned by an issue (ADR-117's FED-but-inert legal state), not a forgotten monitor.
 * - **(b) absent-live** — a non-count-gated heartbeat present in `.tf`/MANIFEST but missing from the
 *   live payload (the `git_data_prd` shape, #6548). Count-gated rows (the paid-tier webhook
 *   heartbeats, item 1) are intentionally absent under the free tier and are carved out.
 *   `arming_pending` does NOT exempt (b) — a declared-but-not-applied monitor is still surfaced.
 *
 * The two classes are mutually exclusive per heartbeat (present-but-paused vs. absent).
 */
export function reconcileHeartbeats(
  manifest: readonly ManifestRow[],
  discovered: readonly DiscoveredHeartbeat[],
  live: readonly LiveHeartbeat[],
): Violation[] {
  const livePausedByName = new Map<string, boolean>();
  for (const hb of live) livePausedByName.set(hb.name, hb.paused);

  const discByResource = new Map<string, DiscoveredHeartbeat>();
  for (const d of discovered) discByResource.set(d.resourceName, d);

  const violations: Violation[] = [];
  for (const row of manifest) {
    const disc = discByResource.get(row.name);
    // A manifest row with no matching .tf block is a source-consistency issue that the static
    // parity test owns; the live reconcile cannot resolve a live name without it, so skip.
    if (!disc) continue;

    const present = livePausedByName.has(disc.liveName);
    const fed = row.feeder.kind === "cron" || row.feeder.kind === "timer";

    if (!disc.countGated && !present) {
      violations.push({
        resourceName: disc.resourceName,
        liveName: disc.liveName,
        live: "absent",
        reason: "absent-live",
      });
      continue;
    }

    if (fed && !row.arming_pending && present && livePausedByName.get(disc.liveName) === true) {
      violations.push({
        resourceName: disc.resourceName,
        liveName: disc.liveName,
        live: "paused",
        reason: "fed-but-paused",
      });
    }
  }
  return violations;
}
