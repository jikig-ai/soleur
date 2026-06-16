// #5417 Deliverable C / AC4 — no-double-report gate.
//
// @sentry/node auto-installs OnUncaughtException + OnUnhandledRejection by
// default. server/crash-handlers.ts adds MANUAL process.on handlers for the
// same two signals (so unhandledRejection deterministically exits — Sentry's
// default mode only warns). If the auto integrations stayed enabled, every
// fatal would be reported TWICE. sentry.server.config.ts must filter both out.
//
// Negative-space source gate: asserts the config drops both auto integrations.
// A behavioral assert is impractical (Sentry.init has process-global side
// effects); this proves the filter exists. If a refactor re-enables the auto
// handlers, crash-handlers.ts double-reports and this fails.

import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const src = readFileSync(
  join(__dirname, "..", "sentry.server.config.ts"),
  "utf8",
);

describe("sentry.server.config.ts auto global-handler suppression (#5417 AC4)", () => {
  // Non-vacuity note: the comment block ALSO names OnUncaughtException /
  // OnUnhandledRejection in prose, so a bare `toMatch(/OnUncaughtException/)`
  // passes even against a no-op `integrations: (defaults) => defaults`. Assert
  // the FILTER EXPRESSION shape (the executable `i.name !== "..."` predicate),
  // which the comment prose does not contain — a gutted passthrough fails it.
  it("declares an integrations filter callback over the defaults", () => {
    expect(src).toMatch(
      /integrations\s*:\s*\(\s*defaults\s*\)\s*=>\s*\n?\s*defaults\.filter\(/,
    );
  });

  it("the filter predicate removes BOTH auto global-handler integrations by name", () => {
    expect(src).toMatch(/i\.name\s*!==\s*"OnUncaughtException"/);
    expect(src).toMatch(/i\.name\s*!==\s*"OnUnhandledRejection"/);
  });
});
