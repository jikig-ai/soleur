// TR9 PR-4 (#4235) — TS port of bin/diff-github-app-manifest.sh.
//
// The Next.js Docker container ships without bin/ + jq, so the previous
// child_process.spawn approach to invoking the bash diff script cannot run
// in production. This module reimplements the same semantics in pure TS so
// the drift-guard handler can run without spawning a subprocess.
//
// Caller passes parsed JSON objects (manifest + GET /app or per-installation
// synthesis); this module returns a tagged-union result that the handler
// maps to its `DriftResult` shape.
//
// Algorithm preserves the bash precedence exactly:
//   1. Response-shape sanity check FIRST. Malformed permissions/events ->
//      response_shape_unparseable. Order matters: a malformed payload must
//      NOT be classified as semantic drift.
//   2. permission_drift > permission_unexpected_grant. Security-regression
//      direction (manifest declares X, live lacks X) surfaces ahead of
//      inventory drift.
//
// Ref #4115, #4179, #4235.

export type ManifestDiffResult =
  | { kind: "ok" }
  | { kind: "permission_drift"; detail: string }
  | { kind: "permission_unexpected_grant"; detail: string }
  | { kind: "response_shape_unparseable"; detail: string };

export interface AppManifest {
  default_permissions?: Record<string, string>;
  default_events?: string[];
}

export interface AppLikeResponse {
  permissions?: unknown;
  events?: unknown;
}

// Mirrors `jq type` output exactly so the response_shape_unparseable detail
// reads identically to the bash version (operators triage on this string).
function jqType(v: unknown, present: boolean): string {
  if (!present) return "missing";
  if (v === null) return "null";
  if (Array.isArray(v)) return "array";
  const t = typeof v;
  if (t === "object") return "object";
  if (t === "string" || t === "number" || t === "boolean") return t;
  return "missing";
}

export function diffGithubAppManifest(
  manifest: AppManifest,
  response: AppLikeResponse,
): ManifestDiffResult {
  // --- 1. Response-shape check FIRST. ---
  const hasPerms = Object.prototype.hasOwnProperty.call(response, "permissions");
  const hasEvents = Object.prototype.hasOwnProperty.call(response, "events");
  const permsOk =
    hasPerms &&
    typeof response.permissions === "object" &&
    response.permissions !== null &&
    !Array.isArray(response.permissions);
  const eventsOk = hasEvents && Array.isArray(response.events);
  if (!permsOk || !eventsOk) {
    const permsType = jqType(response.permissions, hasPerms);
    const eventsType = jqType(response.events, hasEvents);
    return {
      kind: "response_shape_unparseable",
      detail: `response.permissions=${permsType} response.events=${eventsType}`,
    };
  }

  // --- 2. Normalize. ---
  const manifestPerms: Record<string, string> = manifest.default_permissions ?? {};
  const responsePerms = response.permissions as Record<string, string>;
  const manifestEvents = (manifest.default_events ?? []).slice().sort();
  const responseEvents = (response.events as string[]).slice().sort();

  // --- 3. Compute diff sets. ---
  const missingInLive: Record<string, string> = {};
  const sharedKeysWithDiff: Array<{ key: string; manifest: string; live: string }> = [];
  for (const [k, v] of Object.entries(manifestPerms)) {
    if (!Object.prototype.hasOwnProperty.call(responsePerms, k)) {
      missingInLive[k] = v;
    } else if (responsePerms[k] !== v) {
      // Entry differs — mirrors bash `to_entries - to_entries` which captures
      // any {k:v} pair not in the other side. Also surfaces in extraInLive,
      // but the shared-keys-with-diff axis classifies as drift directionally.
      missingInLive[k] = v;
      sharedKeysWithDiff.push({ key: k, manifest: v, live: responsePerms[k] });
    }
  }
  const extraInLive: Record<string, string> = {};
  for (const [k, v] of Object.entries(responsePerms)) {
    if (!Object.prototype.hasOwnProperty.call(manifestPerms, k)) {
      extraInLive[k] = v;
    } else if (manifestPerms[k] !== v) {
      extraInLive[k] = v;
    }
  }
  const manifestEventsSet = new Set(manifestEvents);
  const responseEventsSet = new Set(responseEvents);
  const missingEventsInLive = manifestEvents.filter((e) => !responseEventsSet.has(e));
  const extraEventsInLive = responseEvents.filter((e) => !manifestEventsSet.has(e));

  // --- 4. Precedence: permission_drift > permission_unexpected_grant. ---
  const driftCount =
    sharedKeysWithDiff.length +
    Object.keys(missingInLive).length +
    missingEventsInLive.length;
  if (driftCount > 0) {
    // Strip shared-key entries from missingInLive — bash's `from_entries`
    // collapses duplicate keys but our two-axis walk records each shared
    // mismatch in BOTH missingInLive AND sharedKeysWithDiff. Bash semantics
    // emit a single missing_perms map keyed on the manifest value, so do
    // the same here.
    return {
      kind: "permission_drift",
      detail: JSON.stringify({
        scope_diff: sharedKeysWithDiff,
        missing_perms: missingInLive,
        missing_events: missingEventsInLive,
      }),
    };
  }
  if (Object.keys(extraInLive).length > 0 || extraEventsInLive.length > 0) {
    return {
      kind: "permission_unexpected_grant",
      detail: JSON.stringify({
        extra_perms: extraInLive,
        extra_events: extraEventsInLive,
      }),
    };
  }
  return { kind: "ok" };
}
