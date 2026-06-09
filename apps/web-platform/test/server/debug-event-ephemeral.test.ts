/**
 * feat-debug-mode-stream — standing write-boundary sentinel (AC7).
 *
 * The debug stream is founder-grade ONLY if it is render-only + ephemeral
 * (Legal/CLO: persistence ⇒ DPIA Art. 35). This gate fails CI if ANY
 * persistence / logging / Sentry sink line references `debug_event` — i.e. if
 * a future change ever routes a debug frame into `messages`, a logger, or
 * Sentry. Debug frames may ONLY flow to `sendToClient` (the ephemeral WS).
 *
 * Source-grep (not behavioral): a behavioral test would have to stand up the
 * full SDK dispatch loop; the grep is the cheaper standing guard that also
 * catches a sink added in a file this feature never touched.
 */
import { describe, it, expect } from "vitest";
import { execFileSync } from "node:child_process";
import { join } from "node:path";

const APP_ROOT = join(__dirname, "..", "..");

// Persistence / log / telemetry sinks that MUST NEVER carry a debug frame.
const SINK_RE =
  /\.insert\(|\.upsert\(|\.from\(["']messages["']\)|logger\.|console\.(log|info|warn|error)|captureException|captureMessage|addBreadcrumb|reportSilentFallback|warnSilentFallback|mirrorWithDebounce|\bpino\b/;

function grepDebugEventLines(): string[] {
  try {
    const out = execFileSync(
      "git",
      ["grep", "-In", "debug_event", "--", "server", "lib", "app", "components"],
      { cwd: APP_ROOT, encoding: "utf8" },
    );
    return out.split("\n").filter(Boolean);
  } catch (err) {
    // git grep exits 1 when there are NO matches. Any other exit is a real
    // failure (git missing, repo error) and should surface.
    if ((err as { status?: number }).status === 1) return [];
    throw err;
  }
}

describe("debug_event ephemeral invariant (write-boundary sentinel, AC7)", () => {
  it("references exist (guard is non-vacuous)", () => {
    // If this is ever 0, the grep target drifted and the gate below is vacuous.
    expect(grepDebugEventLines().length).toBeGreaterThan(0);
  });

  it("no persistence / logger / Sentry sink line references debug_event", () => {
    const offending = grepDebugEventLines().filter((line) => {
      // `line` is "path:lineno:content"; strip the location prefix.
      const content = line.replace(/^[^:]+:\d+:/, "");
      return SINK_RE.test(content);
    });
    expect(offending).toEqual([]);
  });
});
