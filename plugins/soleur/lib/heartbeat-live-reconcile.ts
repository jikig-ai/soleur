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

export type ViolationReason = "fed-but-paused" | "absent-live";

export interface Violation {
  resourceName: string;
  liveName: string;
  /** `paused` for condition (a); `absent` for condition (b). */
  live: "paused" | "absent";
  reason: ViolationReason;
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
 * Extract every `betteruptime_heartbeat` block (brace-matched, like the parity parser) with its
 * live name, source-declared paused, and count-gate presence. Throws on an unbalanced block so a
 * malformed source can never silently drop a heartbeat from the reconcile.
 */
export function parseHeartbeatBlocks(tfText: string): DiscoveredHeartbeat[] {
  const stripped = stripComments(tfText);
  const header = /resource\s+"betteruptime_heartbeat"\s+"([A-Za-z0-9_]+)"\s*\{/g;
  const out: DiscoveredHeartbeat[] = [];
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
      throw new Error(`Unbalanced braces for betteruptime_heartbeat.${resourceName}`);
    }
    const body = stripped.slice(openBrace, end + 1);
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
